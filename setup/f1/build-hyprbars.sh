#!/usr/bin/env bash
# Postaví plugin hyprbars (okenné tlačidlá LatteOS, latte/bars.lua) proti nainštalovanému hyprland-devel.
# Commit hyprland-plugins sa berie z hyprpm.toml podľa verzie Hyprlandu (napr. 0.56.2 → 7644cec…).
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
src="$repo/resources/upstream/hyprland-plugins"
[ -d "$src/.git" ] || git clone -q https://github.com/hyprwm/hyprland-plugins.git "$src"
ver="$(pkg-config --modversion hyprland)"
git -C "$src" fetch -q origin 2>/dev/null || true
# piny sú v najnovšom hyprpm.toml (vytiahnutý commit ich pre svoju vlastnú verziu ešte nemá)
commit="$(git -C "$src" show origin/main:hyprpm.toml | grep -E "# $ver\s*$" | head -1 | sed -E 's/.*", "([0-9a-f]+)".*/\1/')"
[ -n "$commit" ] || { echo "hyprpm.toml nepozná Hyprland $ver"; exit 1; }
git -C "$src" cat-file -e "$commit^{commit}" 2>/dev/null || git -C "$src" fetch -q --depth 1 origin "$commit"   # plytká kópia z fetch.sh
git -C "$src" -c advice.detachedHead=false checkout -q "$commit"
# LatteOS záplata (alfatest 1): pravý klik na titulok = ponuka okna, tlačidlá a ťahanie iba ľavým tlačidlom,
# podržanie myši nad tlačidlom (on_button_hover) = rozloženia nad □ ako Windows 11
patch="$repo/resources/patches/hyprbars-latte.patch"
git -C "$src" checkout -q -- hyprbars
git -C "$src" apply "$patch"
make -C "$src/hyprbars" -j"$(nproc)" >/dev/null
echo "$src/hyprbars/hyprbars.so (Hyprland $ver, hyprland-plugins $commit + $(basename "$patch"))"
