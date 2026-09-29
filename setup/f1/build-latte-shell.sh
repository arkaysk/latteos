#!/usr/bin/env bash
# Fork Noctalie pre LatteOS (latte-shell, ~/latte-shell vetva latteos): zostaví a nainštaluje ako /usr/local/bin/noctalia.
# /usr/local/bin je v PATH pred /usr/bin, takže relácia, `noctalia msg` aj latte-boot (proces „noctalia“) používajú fork;
# assets zdieľa s balíkom noctalia-git (rovnaká verzia). Návrat na pôvodnú: sudo rm /usr/local/bin/noctalia
set -euo pipefail
src="${LATTE_SHELL_SRC:-$HOME/latte-shell}"
[ -d "$src/src" ] || { echo "latte-shell nenájdený v $src (git clone … latte-shell && git checkout latteos)"; exit 1; }
rpm -q librsvg2-devel libsecret-devel libsodium-devel polkit-devel pipewire-devel wireplumber-devel libcurl-devel \
      libqalculate-devel md4c-devel json-devel libical-devel jemalloc-devel pam-devel stb_image_resize2-devel \
      stb_image_write-devel libwebp-devel libjxl-devel libsndfile-devel >/dev/null 2>&1 \
  || sudo dnf -y -q install librsvg2-devel libsecret-devel libsodium-devel polkit-devel pipewire-devel wireplumber-devel \
       libcurl-devel libqalculate-devel md4c-devel json-devel libical-devel jemalloc-devel pam-devel stb_image_resize2-devel \
       stb_image_write-devel libwebp-devel libjxl-devel libsndfile-devel
[ -f "$src/build/build.ninja" ] || meson setup "$src/build" "$src" --buildtype=release
ninja -C "$src/build"
sudo install -Dm755 "$src/build/noctalia" /usr/local/bin/noctalia.tmp-latte
sudo mv -f /usr/local/bin/noctalia.tmp-latte /usr/local/bin/noctalia
sudo mkdir -p /usr/local/share/noctalia
sudo ln -sfn /usr/share/noctalia/assets /usr/local/share/noctalia/assets
echo "latte-shell nainštalovaný: $(git -C "$src" log --oneline -1)"
