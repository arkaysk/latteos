#!/usr/bin/env bash
# F1 — test relácie latte-session priamo na obrazovke VM (bez greetd), zo SSH cez seatd.
# Použitie: setup/f1/session-test.sh <normal|safe|crash|segv> [sekundy]
#   normal  latte-session podľa /run/latteos (Hyprland + Noctalia)
#   safe    latte-session safe (labwc + pixman + Noctalia + ponuka latte-safe)
#   crash   simulovaný pád Hyprlandu hneď pri štarte (LATTE_HYPRLAND=false) → musí prejsť do SAFE
#   segv    skutočný pád: po 20 s pošle Hyprlandu SIGSEGV → musí prejsť do SAFE
# Spúšťa sa cez sudo -u <používateľ>, aby mal proces nové skupiny (seat, latte).
set -uo pipefail
case_="${1:?normal|safe|crash}"; secs="${2:-30}"
here="$(cd "$(dirname "$0")" && pwd)"
out="$here/results/session-$case_-$(date +%H%M%S)"; mkdir -p "$out"
u="$(id -un)"; rt="/run/user/$(id -u)"
sudo() { if [ -n "${SUDO_ASKPASS:-}" ]; then command sudo -A "$@"; else command sudo "$@"; fi; }
log="$HOME/.local/state/latteos/session.log"; : > "$log" 2>/dev/null || true

args=(); extra=()
[ "$case_" = safe ] && args=(safe)
[ "$case_" = crash ] && extra=(LATTE_HYPRLAND=false)
before="$(cat /var/lib/latteos/crash-count 2>/dev/null || echo 0)"

sudo -u "$u" env -i HOME="$HOME" USER="$u" PATH=/usr/bin:/bin XDG_RUNTIME_DIR="$rt" \
    LIBSEAT_BACKEND=seatd "${extra[@]}" setsid latte-session "${args[@]}" &
if [ "$case_" = segv ]; then
    sleep 20; echo "== posielam SIGSEGV Hyprlandu"; pkill -SEGV -u "$u" -x Hyprland
    sleep $((secs - 20))
else
    sleep "$secs"
fi
sock=$(ls -t "$rt" | grep -E '^wayland-[0-9]+$' | head -1)
WAYLAND_DISPLAY="$sock" grim "$out/screen.png" 2>/dev/null
comp=$(pgrep -u "$u" -x Hyprland >/dev/null && echo Hyprland || { pgrep -u "$u" -x labwc >/dev/null && echo labwc || echo žiadny; })
{
    echo "test: $case_  $(date -Is)"
    echo "kompozitor: $comp   noctalia: $(pgrep -u "$u" -x noctalia >/dev/null && echo beží || echo nebeží)   latte-safe: $(pgrep -u "$u" -f 'latte-safe' >/dev/null && echo beží || echo nebeží)"
    echo "počítadlo pádov: pred=$before teraz=$(cat /var/lib/latteos/crash-count 2>/dev/null || echo 0)"
    echo "--- session.log"; cat "$log"
} | tee "$out/summary.txt"
cp "$log" "$out/" 2>/dev/null
pkill -u "$u" -x noctalia; pkill -u "$u" -x foot; pkill -u "$u" -x Hyprland; pkill -u "$u" -x labwc; sleep 2
