#!/usr/bin/env bash
# F1/F3 — test aplikácie LatteOS bez obrazovky: labwc s headless backendom a pixmanom (žiadne DRM/GPU).
# Hodí sa, keď je grafika VM obsadená alebo pokazená. Použitie:
#   setup/f1/headless.sh <sekundy> <výstup.png> <príkaz…>
#   HEADLESS_ACTION="wtype -k F3" setup/f1/headless.sh …   (akcia pred screenshotom)
secs="$1"; out="$2"; shift 2
rt="$(mktemp -d)"; chmod 700 "$rt"
export XDG_RUNTIME_DIR="$rt" WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_HEADLESS_OUTPUTS=1 LIBGL_ALWAYS_SOFTWARE=1
cfg="$rt/labwc"; mkdir -p "$cfg"; printf '<labwc_config><core><decoration>server</decoration></core></labwc_config>\n' > "$cfg/rc.xml"
labwc -C "$cfg" -s "sh -c 'wlr-randr --output HEADLESS-1 --custom-mode 1600x900 >/dev/null 2>&1; $*'" >"$rt/labwc.log" 2>&1 &
pid=$!
sleep "$secs"
# HEADLESS_ACTION: príkazy (napr. wtype -k F3) spustené pred screenshotom v rámci displeja
if [ -n "${HEADLESS_ACTION:-}" ]; then
    WAYLAND_DISPLAY=$(ls "$rt" | grep -E '^wayland-[0-9]+$' | head -1) sh -c "$HEADLESS_ACTION"
    sleep 2
fi
WAYLAND_DISPLAY=$(ls "$rt" | grep -E '^wayland-[0-9]+$' | head -1) grim "$out" && echo "screenshot: $out"
kill $pid 2>/dev/null; sleep 1; kill -9 $pid 2>/dev/null
grep -iE "error|warn" "$rt/labwc.log" | grep -viE "portal|edid|xwayland" | head -5
rm -rf "$rt"
