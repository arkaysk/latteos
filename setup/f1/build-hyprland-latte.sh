#!/usr/bin/env bash
# F1 — zostaví hyprland-latte: SRPM Hyprlandu z COPR lionheartp/Hyprland + náš vmwgfx-dmabuf patch.
# Výsledné RPM sú v ~/rpmbuild/RPMS/x86_64/. Build závislosti inštaluje cez sudo (dnf builddep).
# Použitie: setup/f1/build-hyprland-latte.sh
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
patch="$repo/resources/patches/hyprland-0.56.2-vmwgfx-dmabuf.patch"
top="$HOME/rpmbuild"

rpmdev-setuptree
cd "$top/SRPMS"
rm -f hyprland-[0-9]*.src.rpm
dnf download --source hyprland
srpm=$(ls hyprland-[0-9]*.src.rpm | head -1)
echo "== SRPM: $srpm"

rpm -i --define "_topdir $top" "$srpm"
spec="$top/SPECS/$(rpm -qlp "$srpm" | grep "\.spec$" | head -1)"
cp "$patch" "$top/SOURCES/"

# patch do specu: Patch9001 za posledný Patch riadok (mimo %if blokov), %autopatch ho aplikuje.
# Release: pevné <base>.latte, aby hyprland-latte bolo novšie než COPR a dalo sa rozlíšiť.
pname="$(basename "$patch")"
if ! grep -q "$pname" "$spec"; then
    last=$(grep -nE '^Patch[0-9]*:' "$spec" | tail -1 | cut -d: -f1)
    [ -n "$last" ] || { echo "!! spec nemá Patch riadok"; exit 1; }
    sed -i "${last}a Patch9001:      $pname" "$spec"
    base=$(rpm -qp --qf '%{RELEASE}' "$srpm" | sed 's/\.fc[0-9]*$//')
    sed -i "s/^Release:.*/Release:        ${base}.latte%{?dist}/" "$spec"
fi
grep -nE "^(Name|Version|Release|Patch[0-9]*):|%autopatch|%autosetup" "$spec"
grep -q '%autopatch\|%autosetup.*-p' "$spec" || { echo "!! spec neaplikuje patche automaticky"; exit 1; }

if sudo -n true 2>/dev/null; then sudo dnf -y builddep "$spec"
else echo "== sudo bez hesla nie je k dispozícii, builddep preskočený (spusti: sudo dnf builddep $spec)"; fi
rpmbuild -bb "$spec"
ls -1 "$top/RPMS/x86_64/" | grep -i hyprland
