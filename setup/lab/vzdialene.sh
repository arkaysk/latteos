#!/usr/bin/env bash
# setup/lab/vzdialene.sh — latte-lab na diaľku bez monitora, myši a klávesnice: Sunshine (server na latte-lab)
# + Moonlight (klient na pracovnom PC). Spustiť raz (dá sa znova): sudo setup/lab/vzdialene.sh [používateľ]
#   · Sunshine z oficiálneho COPR autorov (lizardbyte/stable) beží UŽ PRED PRIHLÁSENÍM (30. 9. 2026): používateľská
#     služba v default.target a „linger“ (systemd používateľa štartuje s PC), snímanie priamo z grafickej karty (KMS)
#     — jeden stream od prihlasovacej obrazovky cez prihlásenie a odhlásenie po akúkoľvek reláciu. Kódovanie VAAPI.
#     Používateľ je v skupinách video a input: pri prihlasovacej obrazovke je aktívny greetd, nie on (uaccess ACL).
#   · virtuálny monitor na grafickej karte: EDID „LATTE-VIRT“ 1920×1080 (resources/edid) na voľnom výstupe
#     (VIRT_OUT, predvolene DP-1 — skutočný monitor latte-lab je na DP-3) cez parameter jadra; EDID je aj v initramfs.
#     Keď je pripojený skutočný monitor, LatteOS (hyprland.lua) virtuálny vypne.
#   · porty Sunshine vo firewalle (iba zóna s LAN káblom k pracovnému PC)
#   · bez automatického prihlásenia: po štarte je prihlasovacia obrazovka s výberom relácie (cez Moonlight)
# Potom na pracovnom PC: Moonlight (winget install MoonlightGameStreamingProject.Moonlight) → pridať 192.168.137.231
# → PIN zadať na https://192.168.137.231:47990 (pri prvej návšteve si tam vytvoríš meno a heslo správcu).
set -euo pipefail
user="${1:-${SUDO_USER:-arkay}}"
[ "$(id -u)" = 0 ] || { echo "spusti cez sudo"; exit 1; }
id "$user" >/dev/null

echo "== Sunshine (COPR lizardbyte/stable)"
dnf copr enable -y lizardbyte/stable >/dev/null
rpm -q Sunshine >/dev/null || dnf install -y Sunshine
udevadm trigger --subsystem-match=misc --action=change 2>/dev/null || true     # /dev/uinput pre prihláseného (uaccess)

echo "== nastavenie Sunshine pre $user (snímanie KMS, kódovanie VAAPI)"
home="$(getent passwd "$user" | cut -d: -f6)"
conf="$home/.config/sunshine/sunshine.conf"
install -d -o "$user" -g "$user" "$home/.config/sunshine"
if [ ! -f "$conf" ]; then
    cat > "$conf" <<'EOC'
# LatteOS (setup/lab/vzdialene.sh): snímanie z grafickej karty (KMS) — funguje pred prihlásením aj v každej relácii;
# bez monitora sníma virtuálny monitor z parametra jadra; kódovanie grafickou kartou
capture = kms
encoder = vaapi
sunshine_name = latte-lab
EOC
    chown "$user:$user" "$conf"
fi
# webové rozhranie z pracovného PC: CSRF ochrana Sunshine inak púšťa iba localhost
if ! grep -q '^csrf_allowed_origins' "$conf"; then
    ip="$(hostname -I | awk '{print $1}')"; h="$(hostname -s)"
    printf '# webové rozhranie z pracovného PC (inak ho CSRF ochrana pustí iba z localhost)\ncsrf_allowed_origins = https://%s:47990,https://%s.local:47990,https://%s:47990\n' "$ip" "$h" "$h" >> "$conf"
fi
sed -i 's/^capture = wlr$/capture = kms/' "$conf"      # staršie nastavenie (iba v relácii, cez Wayland)
usermod -aG video,input "$user"
loginctl enable-linger "$user"
# zapnutie používateľskej služby = odkaz vo wants (to isté, čo robí `systemctl --user enable`, ale bez bežiacej
# relácie): default.target (štart PC vďaka linger), nie graphical-session.target (iba po prihlásení)
unit=app-dev.lizardbyte.app.Sunshine.service
ud="$home/.config/systemd/user"
install -d -o "$user" -g "$user" "$home/.config/systemd" "$ud" "$ud/default.target.wants" "$ud/$unit.d"
rm -f "$ud/graphical-session.target.wants/$unit"
ln -sf "/usr/lib/systemd/user/$unit" "$ud/default.target.wants/$unit"
cat > "$ud/$unit.d/latteos.conf" <<'EOU'
# LatteOS (setup/lab/vzdialene.sh): Sunshine od štartu PC, nie až v grafickej relácii (snímanie KMS). After= z balíka
# (graphical-session.target) ostáva — závislosti sa v rozšírení vynulovať nedajú; pri štarte PC sa relácia nespúšťa,
# takže naň nečaká
[Install]
WantedBy=
WantedBy=default.target
EOU
chown -R -h "$user:$user" "$ud/default.target.wants" "$ud/$unit.d"

echo "== virtuálny monitor na grafickej karte (${VIRT_OUT:=DP-1})"
here="$(cd "$(dirname "$0")/../.." && pwd)"
python3 "$here/resources/edid/make-edid.py" /tmp/latte-virt-1080p.bin
install -Dm644 /tmp/latte-virt-1080p.bin /usr/lib/firmware/edid/latte-virt-1080p.bin
echo 'install_items+=" /usr/lib/firmware/edid/latte-virt-1080p.bin "' > /etc/dracut.conf.d/latte-virt-edid.conf
dracut -f --regenerate-all >/dev/null
grubby --update-kernel=ALL --args="drm.edid_firmware=$VIRT_OUT:edid/latte-virt-1080p.bin video=$VIRT_OUT:e"

echo "== firewall (porty Sunshine)"
zone="$(firewall-cmd --get-default-zone)"
for p in 47984/tcp 47989/tcp 47990/tcp 48010/tcp 47998/udp 47999/udp 48000/udp 48002/udp 48010/udp; do
    firewall-cmd -q --permanent --zone="$zone" --add-port="$p"
done
firewall-cmd -q --reload

echo "== bez automatického prihlásenia: prihlasovacia obrazovka s výberom relácie (Sunshine beží už pri nej)"
cfg=/etc/greetd/config.toml
if grep -q '^\[initial_session\]' "$cfg"; then
    cp -a "$cfg" "$cfg.pred-sunshine-kms"
    awk '/^\[initial_session\]/{skip=1; next} /^\[/{skip=0} !skip' "$cfg.pred-sunshine-kms" \
        | sed -e '/latte-lab na diaľku (setup\/lab\/vzdialene.sh): po štarte rovno prihlásiť/d' -e '/po odhlásení sa ukáže prihlasovacia obrazovka$/d' > "$cfg"
fi
echo "hotovo — účinné po reštarte PC (parameter jadra); na pracovnom PC: Moonlight → pridať $(hostname -I | awk '{print $1}') → PIN na https://$(hostname -I | awk '{print $1}'):47990"
