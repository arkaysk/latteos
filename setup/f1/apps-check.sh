#!/usr/bin/env bash
# Kontrola aplikácií LatteOS bez obrazovky: každú QML aplikáciu (a greeter v náhľade) spustí v headless
# labwc (setup/f1/headless.sh), urobí snímku do setup/f1/results/check-<app>.png a vypíše chyby QML.
#   setup/f1/apps-check.sh            všetky
#   setup/f1/apps-check.sh subory     len vybrané
repo="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
apps=("$@"); [ ${#apps[@]} -gt 0 ] || apps=(subory nastavenia monitor aplikacie zariadenia heidelberg barista zivatapeta instalator netznak kapsavyrez nahlad aichat plocha spustac pohoda greeter)
fail=0
for a in "${apps[@]}"; do
    qml="$repo/session/apps/$a.qml"; env="QT_QUICK_BACKEND=software"
    [ "$a" = greeter ] && { qml="$repo/session/greeter/shell.qml"; env="$env LATTE_GREETER_TEST=1"; }
    printf '#!/bin/sh\nexport PATH=%s/session/bin:$PATH %s\nexec qs -n -p %s > %s/%s.log 2>&1\n' "$repo" "$env" "$qml" "$tmp" "$a" > "$tmp/run-$a.sh"
    chmod +x "$tmp/run-$a.sh"
    "$repo/setup/f1/headless.sh" 6 "$repo/setup/f1/results/check-$a.png" "$tmp/run-$a.sh" >/dev/null 2>&1
    errs="$(grep -E 'ERROR|TypeError|ReferenceError|is not defined|Cannot read property' "$tmp/$a.log" | sed 's/\x1b\[[0-9;]*m//g')"
    if [ -n "$errs" ]; then echo "✗ $a"; echo "$errs" | head -5 | sed 's/^/    /'; fail=1; else echo "✓ $a"; fi
done
exit $fail
