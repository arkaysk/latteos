#!/usr/bin/env bash
# Postaví plugin Hyprglass (sklo okien s perleťovými okrajmi, latte/sklo.lua) proti nainštalovanému hyprland-devel.
# github.com/hyprnux/hyprglass (BSD-3); verzia Hyprlandu, na ktorú je stavaný, je v .hyprland-version.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
src="$repo/resources/upstream/hyprglass"
[ -d "$src/.git" ] || git clone -q https://github.com/hyprnux/hyprglass "$src"
ver="$(pkg-config --modversion hyprland)"
want="$(cat "$src/.hyprland-version" 2>/dev/null || echo "?")"
[ "$ver" = "$want" ] || echo "pozor: Hyprglass je stavaný na Hyprland $want, máme $ver"
make -C "$src" -j"$(nproc)" >/dev/null 2>&1
echo "$src/hyprglass.so (Hyprland $ver, hyprglass $(git -C "$src" log --oneline -1 --format=%h))"
