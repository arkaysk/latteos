#!/usr/bin/env bash
# setup/lab/noctalia-kvapky.sh — Noctalia pre plochu Kvapky s rohovou lištou (1. 10. 2026): tá istá verzia ako
# nainštalovaný balík noctalia-git, plus záplata resources/patches/noctalia-rohova-lista.patch (margin_start /
# margin_end: lišta iba v rohu, vyduté rohy do bočnej steny aj po spodnom okraji). Samostatný program
# /usr/lib64/latteos/noctalia-kvapky/noctalia — pôvodná Noctalia (/usr/bin/noctalia, relácia „Noctalia (čistá)“)
# ostáva nedotknutá. Spúšťa ju latte-kvapky. Po aktualizácii noctalia-git spustiť znova.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
N="$HOME/.local/share/latteos-noctalia-kvapky"
commit="$(rpm -q --qf '%{VERSION}' noctalia-git | sed -n 's/.*\^[0-9]*\.\([0-9a-f]*\)$/\1/p')"
[ -n "$commit" ] || { echo "noctalia-git nie je nainštalovaný"; exit 1; }
mkdir -p "$N"
[ -d "$N/src/.git" ] || git clone --quiet https://github.com/noctalia-dev/noctalia-shell.git "$N/src"
git -C "$N/src" fetch --quiet origin
git -C "$N/src" checkout --quiet -- . && git -C "$N/src" checkout --quiet "$commit"
git -C "$N/src" apply "$here/resources/patches/noctalia-rohova-lista.patch"
echo "noctalia $commit + záplata rohovej lišty"
[ -d "$N/build" ] || meson setup "$N/build" "$N/src" --buildtype=release --prefix="$N/inst" >/dev/null
ninja -C "$N/build" >/dev/null
sudo install -Dm755 "$N/build/noctalia" /usr/lib64/latteos/noctalia-kvapky/noctalia.new
sudo mv -f /usr/lib64/latteos/noctalia-kvapky/noctalia.new /usr/lib64/latteos/noctalia-kvapky/noctalia
echo "hotovo: $(/usr/lib64/latteos/noctalia-kvapky/noctalia --version)"
