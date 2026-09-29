#!/usr/bin/env bash
# Dymový test LatteOS (secalfaanalyze.md bod 5: testy aj mimo Rustu). Bez root, bez zásahu do relácie:
#   1. syntax všetkých skriptov v session/bin (Python: py_compile do dočasného priečinka, shell: sh -n / bash -n),
#   2. každá QML aplikácia sa spustí bez obrazovky (setup/f1/headless.sh) s izolovaným XDG_CONFIG/STATE/CACHE
#      a v jej výpise sa hľadajú chyby QML (načítanie, TypeError, ReferenceError, slučky väzieb).
# Použitie: setup/test/dym.sh [aplikácia…]   (bez argumentov všetky; živá tapeta sa vynechá — prehráva video)
set -u
repo="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/cfg" "$tmp/state" "$tmp/cache" "$tmp/pyc"
fail=0

echo "== syntax skriptov"
for f in "$repo"/session/bin/*; do
    [ -f "$f" ] || continue
    first=$(head -1 "$f")
    case "$first" in
        *python*) PYTHONPYCACHEPREFIX="$tmp/pyc" python3 -m py_compile "$f" 2>"$tmp/err" || { echo "  CHYBA $(basename "$f")"; sed 's/^/    /' "$tmp/err"; fail=1; } ;;
        *bash*)   bash -n "$f" 2>"$tmp/err" || { echo "  CHYBA $(basename "$f")"; sed 's/^/    /' "$tmp/err"; fail=1; } ;;
        *sh*)     sh -n "$f" 2>"$tmp/err" || { echo "  CHYBA $(basename "$f")"; sed 's/^/    /' "$tmp/err"; fail=1; } ;;
    esac
done
[ $fail = 0 ] && echo "  v poriadku"

echo "== QML aplikácie bez obrazovky"
apps=("$@")
[ ${#apps[@]} -eq 0 ] && for q in "$repo"/session/apps/*.qml; do n=$(basename "$q" .qml); [ "$n" = zivatapeta ] || apps+=("$n"); done
for n in "${apps[@]}"; do
    cat > "$tmp/run.sh" <<RUN
#!/bin/sh
export XDG_CONFIG_HOME=$tmp/cfg XDG_STATE_HOME=$tmp/state XDG_CACHE_HOME=$tmp/cache QT_QUICK_BACKEND=software
exec qs -n -p "$repo/session/apps/$n.qml" > "$tmp/$n.log" 2>&1
RUN
    chmod +x "$tmp/run.sh"
    "$repo/setup/f1/headless.sh" 7 "$tmp/$n.png" "$tmp/run.sh" >/dev/null 2>&1
    bad=$(grep -E "ERROR|TypeError|ReferenceError|Binding loop|is not defined|Cannot assign|unavailable" "$tmp/$n.log" 2>/dev/null | grep -v "Wayland connection" | head -3)
    if [ -n "$bad" ]; then echo "  CHYBA $n"; echo "$bad" | sed 's/^/    /'; fail=1; else echo "  ok    $n"; fi
done
[ $fail = 0 ] && echo "== všetko v poriadku" || echo "== našli sa chyby"
exit $fail
