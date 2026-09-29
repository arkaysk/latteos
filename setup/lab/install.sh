#!/usr/bin/env bash
# H0 — latte-lab: celý LatteOS na reálnom PC jedným príkazom, hneď po čistej inštalácii Fedora 44 Server.
# Postup pred ním (BIOS, disk, Anaconda) je v setup/lab/README.md. Spúšťať ako bežný používateľ, ideálne cez SSH:
#   setup/lab/install.sh                                     všetko, grafický štart ešte NEZAPNE
#   setup/lab/install.sh --enable                            navyše latte-boot + greetd (grafický štart)
#   setup/lab/install.sh --ip 192.168.1.50/24 --gw 192.168.1.1   pevná adresa (platí po reštarte)
# Opätovné spustenie je bezpečné. Záznam: ~/latte-lab-install.log
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
enable=""; ip=""; gw=""; dns=""
while [ $# -gt 0 ]; do
    case "$1" in
        --enable) enable=--enable ;;
        --ip) ip="$2"; shift ;;
        --gw) gw="$2"; shift ;;
        --dns) dns="$2"; shift ;;
        -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
        *) echo "Neznámy parameter: $1 (pozri --help)"; exit 1 ;;
    esac
    shift
done
[ -z "$ip" ] || [ -n "$gw" ] || { echo "--ip potrebuje aj --gw (adresa routera)"; exit 1; }
[ "$(id -u)" -ne 0 ] || { echo "Spúšťaj ako používateľ (nie cez sudo); skript si sudo vyžiada sám."; exit 1; }
user="$(id -un)"
. /etc/os-release
[ "${ID:-}" = fedora ] || { echo "Toto nie je Fedora ($PRETTY_NAME)."; exit 1; }
[ "${VERSION_ID:-}" = 44 ] || echo "!! Fedora $VERSION_ID — skript je overený pre 44, pokračujem."
virt="$(systemd-detect-virt 2>/dev/null || true)"
[ "$virt" = none ] || echo "!! Beží vo VM ($virt) — skript je pre reálne PC, pokračujem."

log="$HOME/latte-lab-install.log"
exec > >(tee -a "$log") 2>&1
echo "=== latte-lab install $(date '+%F %T') · $(git -C "$repo" log --oneline -1)"

# sudo raz na začiatku, potom ho drží nažive (build trvá dlhšie ako platnosť hesla)
sudo -v
( while kill -0 $$ 2>/dev/null; do sudo -n true; sleep 50; done ) 2>/dev/null &

step() { echo; echo "== $*"; }

step "1/8 snímka Btrfs pred inštaláciou (návrat súborov: sudo snapper -c root undochange <č>..0)"
if [ "$(findmnt -no FSTYPE /)" = btrfs ]; then
    rpm -q snapper >/dev/null || sudo dnf -y -q install snapper
    sudo snapper list-configs 2>/dev/null | grep -q '^root ' || sudo snapper -c root create-config /
    sudo snapper -c root create -d "pred latte-lab install.sh" --print-number | sed 's/^/   snímka č. /'
else
    echo "   / nie je Btrfs ($(findmnt -no FSTYPE /)) — bez snímky"
fi

step "2/8 aktualizácia systému"
sudo dnf -y upgrade --refresh

step "3/8 vzdialený prístup: SSH, Cockpit, mDNS (latte-lab.local), firewall"
sudo dnf -y -q install openssh-server cockpit avahi ethtool pciutils
sudo systemctl enable --now sshd.service cockpit.socket avahi-daemon.service
for s in ssh cockpit mdns; do sudo firewall-cmd -q --permanent --add-service="$s"; done
sudo firewall-cmd -q --reload
# heslo cez SSH vypnúť iba keď je uložený kľúč — inak by sa dalo zamknúť zvonku
if grep -qE "^(ssh-|ecdsa-|sk-)" "$HOME/.ssh/authorized_keys" 2>/dev/null; then
    printf '# LatteOS latte-lab: iba kľúče (setup/lab/install.sh)\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin no\n' \
        | sudo tee /etc/ssh/sshd_config.d/40-latteos.conf >/dev/null
    sudo sshd -t && sudo systemctl reload sshd.service
    echo "   SSH: iba kľúč (heslo vypnuté); konzola s heslom funguje ďalej"
else
    echo "   !! ~/.ssh/authorized_keys neobsahuje žiadny kľúč — SSH ostáva s heslom (skopíruj kľúč a spusti skript znova)"
fi

step "4/8 sieť: Wake-on-LAN, prípadne pevná adresa"
nmcli -t -f NAME,TYPE,DEVICE connection show --active | while IFS=: read -r name type dev; do
    [ "$type" = 802-3-ethernet ] || continue
    sudo nmcli connection modify "$name" 802-3-ethernet.wake-on-lan magic
    sudo ethtool -s "$dev" wol g 2>/dev/null || echo "   !! $dev: karta Wake-on-LAN odmietla"
    mac="$(cat "/sys/class/net/$dev/address")"
    echo "   $dev ($name): Wake-on-LAN zapnutý, MAC $mac, $(sudo ethtool "$dev" | awk '/^\s*Wake-on:/{print "stav " $2}')"
    if [ -n "$ip" ]; then
        sudo nmcli connection modify "$name" ipv4.method manual ipv4.addresses "$ip" ipv4.gateway "$gw" \
            ipv4.dns "${dns:-$gw}"
        echo "   $name: pevná adresa $ip (brána $gw) — platí po reštarte, SSH sa teraz nepreruší"
    fi
done

step "5/8 RPM Fusion (kodeky, Steam) a VA-API s H.264/HEVC pre AMD (Sunshine)"
fv="$(rpm -E %fedora)"
rpm -q rpmfusion-free-release rpmfusion-nonfree-release >/dev/null 2>&1 || sudo dnf -y install \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$fv.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$fv.noarch.rpm"
if lspci -n | grep -q ' 0300: 1002:\| 0380: 1002:'; then
    rpm -q mesa-va-drivers-freeworld >/dev/null || sudo dnf -y swap mesa-va-drivers mesa-va-drivers-freeworld \
        || echo "   !! mesa-va-drivers-freeworld sa nenainštaloval (verzia Mesa v RPM Fusion ešte nedobehla?) — skús neskôr"
fi

step "6/8 balíky LatteOS (setup/f0-install.sh)"
sudo "$repo/setup/f0-install.sh"

step "7/8 štart a relácie LatteOS (setup/f1/install-session.sh $enable)"
"$repo/setup/f1/install-session.sh" $enable

step "8/8 kontrola"
if mountpoint -q /data; then
    sudo install -d -o "$user" -g "$user" /data/snimky /data/iso /data/logy
    echo "   /data: $(findmnt -no FSTYPE,SIZE /data | tr -s ' ')"
else
    echo "   !! /data nie je pripojený (oddiel Dáta z README)"
fi
# EDID pripojeného monitora: náhrada dummy zástrčky (drm.edid_firmware) — uložiť, kým je monitor zapojený
mkdir -p "$HOME/edid"
for e in /sys/class/drm/card*-*/edid; do
    c="$(basename "$(dirname "$e")")"; f="$HOME/edid/${c#card*-}.bin"
    cat "$e" > "$f" 2>/dev/null   # súbory v /sys hlásia veľkosť 0, test -s by ich preskočil
    if [ -s "$f" ]; then echo "   EDID monitora ${c#card*-} uložený: ~/edid/${c#card*-}.bin"; else rm -f "$f"; fi
done
{ lspci -k | grep -A3 -E 'VGA|Display' | grep -E 'VGA|Display|driver in use' | sed 's/^\s*/   /'; } || true
{ vulkaninfo --summary 2>/dev/null | grep -m2 -E 'deviceName|driverName' | sed 's/^\s*/   /'; } || echo "   !! vulkaninfo zlyhal"
echo "   latte-boot (na reálnom PC čakáme renderer = hw):"
{ latte-boot status 2>&1 | sed 's/^/     /'; } || true
ip -4 -br addr show scope global | sed 's/^/   /'
echo
echo "Hotovo. Záznam: $log"
rpm -q --last kernel-core | head -1 | grep -q "$(uname -r)" || echo "Nainštalované nové jadro — reštartuj: sudo reboot"
[ -n "$enable" ] || echo "Grafický štart nie je zapnutý. Keď renderer = hw a SSH/Cockpit fungujú: setup/lab/install.sh --enable"
echo "Z hlavného PC: ssh $user@$(hostname -s).local · Cockpit https://$(hostname -s).local:9090"
