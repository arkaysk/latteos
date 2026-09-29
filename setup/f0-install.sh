#!/usr/bin/env bash
# F0 — základné balíky LatteOS (Fedora 44 Server): vývojová VM vo VirtualBoxe aj reálne PC (latte-lab).
# Idempotentné: opätovné spustenie len doinštaluje chýbajúce. Spúšťať ako root: sudo ./f0-install.sh
# Nič nepovoľuje do štartu okrem VirtualBox guest služby (len vo VM) a seatd; greetd/relácie rieši F1.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Spusti cez sudo."; exit 1; }

# --- grafika: Mesa (llvmpipe/lavapipe, svga) + diagnostika --------------------
GRAPHICS=(mesa-dri-drivers mesa-vulkan-drivers mesa-libEGL mesa-libgbm
          egl-utils glx-utils mesa-demos vulkan-tools pciutils)
# --- VirtualBox hosť (iba vo VirtualBoxe; na reálnom PC nič) -------------------
VM=()
[ "$(systemd-detect-virt 2>/dev/null)" = oracle ] && VM=(virtualbox-guest-additions)
# --- relácia: SAFE (labwc) + spoločné -----------------------------------------
SESSION=(greetd greetd-selinux tuigreet labwc foot fuzzel xorg-x11-server-Xwayland
         xdg-desktop-portal xdg-desktop-portal-gtk xdg-user-dirs xdg-utils polkit
         pipewire wireplumber pipewire-pulseaudio wl-clipboard grim slurp
         udisks2 upower accountsservice NetworkManager systemd-oomd-defaults
         plymouth-plugin-two-step plymouth-theme-spinner)   # téma latteos (Fedora Server ich nemá)
# --- NORMAL: Hyprland sada z COPR lionheartp/Hyprland -------------------------
HYPR=(hyprland hyprland-devel hyprlock hypridle xdg-desktop-portal-hyprland
      hyprpolkitagent hyprland-qt-support hyprland-guiutils hyprpicker uwsm cliphist
      quickshell matugen noctalia-git noctalia-greeter-git)
# --- Qt pre shell ------------------------------------------------------------
QT=(qt6-qtwayland qt6-qtmultimedia qt6-qtsvg qt6-qt5compat)
# --- písma a ikony (radar: Inter + JetBrains Mono) -----------------------------
FONTS=(rsms-inter-fonts rsms-inter-vf-fonts jetbrains-mono-fonts
       google-noto-sans-fonts google-noto-emoji-fonts adwaita-icon-theme)
# --- vývoj: C++/Rust/Go, balenie RPM (hyprland-latte), Lua --------------------
DEV=(git gcc-c++ cmake meson ninja-build rust cargo golang
     rpm-build rpmdevtools dnf5-plugins lua lua-devel
     python3-pillow)   # maskoti na lištu a logo Plymouth (install-session.sh)
# --- F1 testy: seatd (kompozitor zo SSH), GL klienti, rozlíšenie ------------------
TEST=(seatd kitty wlr-randr)
# --- AI (CPU, malý model; služba sa nepovoľuje) --------------------------------
AI=(ollama)

dnf -y install dnf5-plugins
dnf -y copr enable lionheartp/Hyprland

dnf -y install "${GRAPHICS[@]}" "${VM[@]}" "${SESSION[@]}" "${HYPR[@]}" \
               "${QT[@]}" "${FONTS[@]}" "${DEV[@]}" "${TEST[@]}" "${AI[@]}"

[ ${#VM[@]} -eq 0 ] || systemctl enable --now vboxservice.service || true
systemctl enable --now seatd.service || true
usermod -aG seat "${SUDO_USER:-user}" || true

echo
echo "== F0 hotové. Kontrola:"
rpm -q hyprland labwc quickshell mesa-dri-drivers greetd | sed 's/^/  /'
