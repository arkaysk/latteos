#!/usr/bin/env bash
# Kontrola pluginov LatteOS: headless labwc + Noctalia s /usr/share/latteos (nainštalovaná verzia),
# postupne otvorí každý panel pluginu a vypíše chyby Luau. Snímka: setup/f1/results/check-plugins.png
repo="$(cd "$(dirname "$0")/../.." && pwd)"
log="$(mktemp)"; trap 'rm -f "$log"' EXIT
panels="latteos/system:menu latteos/devices:panel latteos/time:panel latteos/kapsa:panel latteos/overview:panel latteos/ai:chat latteos/snap:panel latteos/games:panel"
action=""
for p in $panels; do action="$action noctalia msg panel-open $p >/dev/null 2>&1; sleep 1.5; noctalia msg panel-toggle $p >/dev/null 2>&1; sleep 0.5;"; done
HEADLESS_ACTION="$action noctalia msg panel-open latteos/time:panel; sleep 1" \
    "$repo/setup/f1/headless.sh" 10 "$repo/setup/f1/results/check-plugins.png" "NOCTALIA_CONFIG_HOME=/usr/share/latteos noctalia >$log 2>&1" >/dev/null 2>&1
loaded="$(grep -o "loaded plugin 'latteos/[a-z]*'" "$log" | sort -u | wc -l)"
errs="$(grep -E '\[luau\]|plugin .*failed' "$log" | grep -E 'ERR|WRN' | sed 's/\x1b\[[0-9;]*m//g' | sort -u)"
echo "načítaných pluginov LatteOS: $loaded"
if [ -n "$errs" ]; then echo "✗ chyby:"; echo "$errs" | head -20 | sed 's/^/    /'; exit 1; fi
echo "✓ bez chýb Luau"
