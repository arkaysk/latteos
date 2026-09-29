#!/usr/bin/env bash
# F1 — test kompatibility grafického stacku na VM (ROADMAP: tabuľka A/B/C).
# Spustí kompozitor priamo na obrazovke VM cez seatd, pustí testovacích klientov,
# po chvíli urobí screenshot a zapíše výsledok. Kompozitor potom ukončí.
#
# Použitie:  sg seat -c "setup/f1/probe.sh <hyprland|labwc> <vm3d|swgl|pixman> [sekundy]"
#            HYPR_EXTRA="render { ... }" pridá riadky do testovacej hyprland.conf
#            PRE_IDLE="noctalia msg panel-close" vykoná sa 15 s pred koncom, pred meraním pokoja
#            SHELL_CMD="noctalia" spustí shell namiesto kitty/es2gears (foot ostáva); meria RSS a CPU v pokoji
# Výstup:    setup/f1/results/<kompozitor>-<cesta>-<čas>/  (log, screenshot, summary.txt)
set -uo pipefail

comp="${1:?kompozitor: hyprland|labwc}"
path="${2:?cesta: vm3d|swgl|pixman}"
secs="${3:-25}"
here="$(cd "$(dirname "$0")" && pwd)"
out="$here/results/$comp-$path-$(date +%H%M%S)"
mkdir -p "$out"

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export LIBSEAT_BACKEND=seatd
export XDG_SESSION_TYPE=wayland
unset WAYLAND_DISPLAY DISPLAY HYPRLAND_INSTANCE_SIGNATURE
rm -rf "$XDG_RUNTIME_DIR/hypr"   # staré logy Hyprlandu, aby sa nemiešali

case "$path" in
    vm3d)   ;;                                              # Mesa svga nad VMSVGA 3D
    swgl)   export MESA_LOADER_DRIVER_OVERRIDE=kms_swrast   # llvmpipe pre GBM (kompozitor)
            export LIBGL_ALWAYS_SOFTWARE=1 ;;               # llvmpipe pre wayland klientov
    pixman) [ "$comp" = labwc ] || { echo "pixman vie iba labwc"; exit 2; }
            export WLR_RENDERER=pixman ;;
    *) echo "neznáma cesta $path"; exit 2 ;;
esac

# klienti: foot (CPU/shm), kitty a es2gears (GL → dmabuf, tu vzniká čierna obrazovka)
clients="$here/clients.sh"
cat > "$clients" <<EOF
#!/usr/bin/env bash
cd "$out"
date +%s.%N > start.ts
foot -e sh -c 'echo LatteOS F1 $comp/$path; sleep 600' >foot.log 2>&1 &
if [ -n "${SHELL_CMD:-}" ]; then
    ${SHELL_CMD:-} >shell.log 2>&1 &
    echo \$! > shell.pid
else
    kitty -e sh -c 'sleep 600'  >kitty.log 2>&1 &
    stdbuf -oL es2gears_wayland >gears.log 2>&1 &
fi
EOF
chmod +x "$clients"

case "$comp" in
    hyprland)
        cat > "$out/hyprland.conf" <<EOF
monitor = , 1920x1080@60, auto, 1
ecosystem {
    no_update_news = true
    no_donation_nag = true
}
cursor { no_hardware_cursors = true }
misc { disable_hyprland_logo = true; disable_splash_rendering = true }
decoration { blur { enabled = false } }
exec-once = $clients
${HYPR_EXTRA:-}
EOF
        Hyprland --config "$out/hyprland.conf" >"$out/compositor.log" 2>&1 &
        ;;
    labwc)
        mkdir -p "$out/labwc"
        printf '%s\n' "$clients" > "$out/labwc/autostart"
        cat > "$out/labwc/rc.xml" <<'XML'
<labwc_config><core><gap>0</gap></core></labwc_config>
XML
        # rozlíšenie 1920x1080 pre porovnateľné merania (predvolene VM hlási 640x480)
        printf '%s\n' "wlr-randr --output Virtual-1 --mode 1920x1080 >/dev/null 2>&1 || true" | cat - "$out/labwc/autostart" > "$out/labwc/a" && mv "$out/labwc/a" "$out/labwc/autostart"
        labwc -C "$out/labwc" -d >"$out/compositor.log" 2>&1 &
        ;;
    *) echo "neznámy kompozitor $comp"; exit 2 ;;
esac
cpid=$!

# CPU v pokoji: vzorka /proc/<pid>/stat za posledných 10 s behu
# strom procesov (shell = napr. dms run → dms backend + quickshell)
tree() { local p=$1 c; echo $p; for c in $(pgrep -P $p 2>/dev/null); do tree $c; done; }
ticks() { local t=0 p v; for p in $(tree $1); do v=$(awk '{print $14+$15}' "/proc/$p/stat" 2>/dev/null) && t=$((t+v)); done; echo $t; }
sleep $((secs - 15))
# PRE_IDLE: príkaz pred meraním pokoja (napr. zatvoriť panel shellu)
[ -n "${PRE_IDLE:-}" ] && { WAYLAND_DISPLAY="$(ls -t "$XDG_RUNTIME_DIR" | grep -E "^wayland-[0-9]+$" | head -1)" sh -c "$PRE_IDLE" >"$out/pre_idle.log" 2>&1; }
sleep 5
spid=$(cat "$out/shell.pid" 2>/dev/null || true)
c0=$(ticks $cpid); s0=$([ -n "$spid" ] && ticks $spid || echo 0)
sleep 10
c1=$(ticks $cpid); s1=$([ -n "$spid" ] && ticks $spid || echo 0)
hz=$(getconf CLK_TCK)
idle_c=$(( (c1 - c0) * 100 / (10 * hz) ))
idle_s=$(( (s1 - s0) * 100 / (10 * hz) ))
rss() { local k=0 p v; for p in $(tree $1); do v=$(awk '/VmRSS/{print $2}' "/proc/$p/status" 2>/dev/null) && k=$((k+${v:-0})); done; echo "$((k/1024)) MB ($(tree $1 | wc -l) proc.)"; }

alive() { kill -0 "$1" 2>/dev/null && echo áno || echo NIE; }
cl() { pgrep -u "$(id -u)" -f "^$1" >/dev/null && echo beží || echo SPADOL; }

# screenshot cez wayland socket kompozitora
sock=$(ls -t "$XDG_RUNTIME_DIR" 2>/dev/null | grep -E '^wayland-[0-9]+$' | head -1)
[ -n "$sock" ] && WAYLAND_DISPLAY="$sock" grim "$out/screen.png" 2>"$out/grim.log"

cpu=$(ps -o %cpu= -p "$cpid" 2>/dev/null | tr -d ' ')
{
    echo "kompozitor: $comp   cesta: $path   čas: ${secs}s   $(date -Is)"
    echo "kompozitor beží: $(alive $cpid)   CPU (priemer): ${cpu:-?} %   CPU v pokoji: ${idle_c} %   RSS: $(rss $cpid)"
    if [ -n "$spid" ]; then
        echo "shell '$SHELL_CMD' beží: $(alive $spid)   CPU v pokoji: ${idle_s} %   RSS: $(rss $spid)"
        echo "foot: $(cl foot)"
    else
        echo "foot: $(cl foot)   kitty: $(cl kitty)   es2gears: $(cl es2gears_wayland)"
        echo "es2gears FPS: $(grep -oE '[0-9.]+ FPS' "$out/gears.log" | tail -1)"
    fi
    echo "renderer: $(grep -m1 -oiE '(renderer|GL_RENDERER)[^\n]{0,80}(llvmpipe|SVGA3D|pixman)[^\n]{0,20}' "$out/compositor.log" "$XDG_RUNTIME_DIR"/hypr/*/hyprland.log 2>/dev/null | tail -1)"
    echo "chyby wl_surface.attach: $(cat "$out"/*.log 2>/dev/null | grep -c 'wl_surface.*attach')"
    echo "dmabuf chyby: $(cat "$out/compositor.log" "$XDG_RUNTIME_DIR"/hypr/*/hyprland.log 2>/dev/null | grep -ciE 'close dmabuf|dmabuf.*fail')"
    echo "screenshot: $([ -s "$out/screen.png" ] && echo screen.png || echo žiadny)"
} | tee "$out/summary.txt"

# Hyprland log presunúť k výsledkom
for d in "$XDG_RUNTIME_DIR"/hypr/*/; do [ -f "$d/hyprland.log" ] && cp "$d/hyprland.log" "$out/"; done

pkill -u "$(id -u)" -f "^es2gears_wayland"; pkill -u "$(id -u)" -x kitty; pkill -u "$(id -u)" -x foot
[ -n "$spid" ] && kill $(tree "$spid") 2>/dev/null
kill "$cpid" 2>/dev/null; sleep 2; kill -9 "$cpid" 2>/dev/null
rm -f "$clients"
exit 0
