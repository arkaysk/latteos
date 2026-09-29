#!/usr/bin/env bash
# F1 — nainštaluje štart LatteOS do systému: latte-boot, relácie NORMAL/SAFE, greeter, GRUB SAFE, Plymouth.
# Spúšťať ako bežný používateľ (build ide bez roota, inštalácia cez sudo):
#   setup/f1/install-session.sh            nainštaluje a pripraví, grafický štart NEZAPNE
#   setup/f1/install-session.sh --enable   navyše zapne latte-boot + greetd a graphical.target
# Opätovné spustenie je bezpečné (prepíše súbory LatteOS, pôvodné konfigurácie zálohuje raz).
set -euo pipefail
repo="$(cd "$(dirname "$0")/../.." && pwd)"
S="$repo/session"
enable=0; [ "${1:-}" = --enable ] && enable=1
[ "$(id -u)" -ne 0 ] || { echo "Spúšťaj ako používateľ (nie cez sudo); skript si sudo vyžiada sám."; exit 1; }
user="$(id -un)"
# bez terminálu (automatizácia): SUDO_ASKPASS=<skript> → sudo -A
sudo() { if [ -n "${SUDO_ASKPASS:-}" ]; then command sudo -A "$@"; else command sudo "$@"; fi; }

# kontrola pred prvým zásahom do systému (DSanalyze.md): chýbajúci súbor = poškodený checkout, nie polovičná inštalácia
BINS="latte-session latte-safe latte-greeter latte-theme latte-app latte-ai latte-shellset latte-sysmon latte-apps latte-devices latte-backup latte-games latte-net latte-cloud latte-siet latte-otvor latte-kos latte-spustac latte-sandbox latte-kopia latte-tc latte-ostrovy latte-rychle latte-tapety latte-vyber latte-ponuka latte-prichytenie latte-snimka latte-emoji latte-nove-okno latte-nahravanie latte-maskoti latte-sklo latte-inspektor latte-terminal latte-hypr-udalosti latte-sukromie latte-kapsa-store"
missing=""
for f in $BINS; do [ -f "$S/bin/$f" ] || missing="$missing $f"; done
[ -z "$missing" ] || { echo "Chýbajú skripty v $S/bin:$missing — inštaláciu nezačínam (git status / git pull)."; exit 1; }

echo "== build latte-boot"
(cd "$repo" && cargo build --release --offline -q)

echo "== skupina latte (zápis počítadla pádov z relácie)"
sudo groupadd -f latte
sudo usermod -aG latte "$user"

echo "== binárky a skripty → /usr/bin"
sudo install -Dm755 "$repo/target/release/latte-boot" /usr/bin/latte-boot
for f in $BINS; do sudo install -Dm755 "$S/bin/$f" "/usr/bin/$f"; done

echo "== konfigurácie relácií → /usr/share/latteos"
# bežiaci Hyprland sleduje svoje súbory a pri zmene sa znovu načíta: súbor sa preto vymieňa atomicky
# (dočasný súbor + premenovanie) a moduly latte/*.lua idú pred hyprland.lua. Inak reload uprostred
# inštalácie nenájde modul a Hyprland prejde do núdzového režimu (stalo sa 24. 9. 2026).
put() { sudo install -Dm644 "$1" "$2.latte-new" && sudo mv -f "$2.latte-new" "$2" || { sudo rm -f "$2.latte-new"; return 1; }; }
sudo install -d /usr/share/latteos/hypr/latte
for f in "$S"/hypr/latte/*.lua; do put "$f" "/usr/share/latteos/hypr/latte/$(basename "$f")"; done
put "$S/hypr/hyprland.conf" /usr/share/latteos/hypr/hyprland.conf
put "$S/hypr/hyprland.lua" /usr/share/latteos/hypr/hyprland.lua
for f in rc.xml autostart environment menu.xml; do sudo install -Dm644 "$S/labwc/$f" "/usr/share/latteos/labwc/$f"; done
# relácie LatteOS: v systémovom zozname (pre iné greetery) aj vo vlastnom, ktorý ponúka latte-greeter
# (tuigreet by inak ponúkol aj „Hyprland“ z COPR bez Noctalie a bez latte-session)
for f in latteos.desktop latteos-safe.desktop; do
    sudo install -Dm644 "$S/wayland-sessions/$f" "/usr/share/wayland-sessions/$f"
    sudo install -Dm644 "$S/wayland-sessions/$f" "/usr/share/latteos/sessions/$f"
done

echo "== latte-shell (fork Noctalie: panely v tvare L z ostrova), ak je zdroj v ~/latte-shell"
if [ -d "$HOME/latte-shell/src" ]; then "$repo/setup/f1/build-latte-shell.sh" | tail -2 | sed 's/^/   /'; else echo "   preskočené (bez ~/latte-shell ostáva pôvodná Noctalia)"; fi
echo "== okenné tlačidlá: plugin hyprbars (postavený proti hyprland-devel)"
if rpm -q hyprland-devel >/dev/null 2>&1 && "$repo/setup/f1/build-hyprbars.sh" | sed 's/^/   /'; then
    sudo install -Dm755 "$repo/resources/upstream/hyprland-plugins/hyprbars/hyprbars.so" /usr/lib64/latteos/hyprbars.so
else
    echo "   hyprbars sa nepostavil (chýba hyprland-devel?) — okná bez vlastnej hlavičky budú bez tlačidiel"
fi
echo "== prichytenie okien k okrajom: plugin latte-okna (udalosti ťahania pre latte/prichytenie.lua)"
if rpm -q hyprland-devel >/dev/null 2>&1 && make -s -C "$S/hypr/plugins/latte-okna" >/dev/null; then
    sudo install -Dm755 "$S/hypr/plugins/latte-okna/latte-okna.so" /usr/lib64/latteos/latte-okna.so
else
    echo "   latte-okna sa nepostavil — okná sa nebudú prichytávať ťahaním (Win+←→ a Win+Z fungujú)"
fi

echo "== vzhľad: Noctalia (téma Latte), písma Manrope/Fraunces (OFL), tapety LatteOS"
put "$S/noctalia/config.toml" /usr/share/latteos/noctalia/config.toml   # Noctalia sleduje priečinok (hot reload)
sudo install -Dm644 "$S/noctalia/palettes/Latte.json" /usr/share/latteos/noctalia/palettes/Latte.json
sudo install -Dm644 "$S/noctalia/icons/latte-cup.png" /usr/share/latteos/noctalia/icons/latte-cup.png
for p in "$S"/noctalia/plugins/*/; do   # pluginy LatteOS (zdroj „latteos“ v config.toml)
    n="$(basename "$p")"; sudo install -d "/usr/share/latteos/noctalia/plugins/$n"
    for f in "$p"*; do [ -f "$f" ] && sudo install -m644 "$f" "/usr/share/latteos/noctalia/plugins/$n/"; done   # iba súbory
done
# maskoti na lištu: vlastná pixel-art, snímky sa generujú (plugin latteos/cat)
tmpm="$(mktemp -d)"; python3 "$S/noctalia/plugins/cat/make-mascots.py" "$tmpm" | sed 's/^/   /'
sudo install -d /usr/share/latteos/noctalia/plugins/cat/mascots
sudo install -m644 "$tmpm"/*.png /usr/share/latteos/noctalia/plugins/cat/mascots/
# balíčky maskotov (plné snímky + pet.json) pre výbehy — apps/maskot.qml
for d in "$S"/noctalia/plugins/cat/balicky/*/; do
    n="$(basename "$d")"; sudo install -d "/usr/share/latteos/maskoti/$n"
    sudo install -m644 "$d"* "/usr/share/latteos/maskoti/$n/"
done
rm -rf "$tmpm"
sudo install -d /usr/share/fonts/latteos /usr/share/backgrounds/latteos
sudo install -m644 "$S"/fonts/*.ttf "$S"/fonts/OFL-*.txt /usr/share/fonts/latteos/
sudo fc-cache -f /usr/share/fonts/latteos
sudo install -m644 "$S"/wallpapers/*.jpg /usr/share/backgrounds/latteos/
sudo install -d /usr/share/latteos/themes
sudo install -m644 "$S"/themes/*.theme /usr/share/latteos/themes/
sudo install -m644 "$S"/noctalia/palettes/*.json /usr/share/latteos/noctalia/palettes/

echo "== greeter LatteOS (Quickshell QML pod labwc + pixman)"
sudo install -Dm644 "$S/greeter/shell.qml" /usr/share/latteos/greeter/shell.qml
for f in rc.xml environment; do sudo install -Dm644 "$S/greeter/labwc/$f" "/usr/share/latteos/greeter/labwc/$f"; done
# vzhľad greetera (Nastavenia › Účet › Prihlasovanie) a záznam pádu: skupina latte píše, greeter (xdm_t) číta
sudo install -d -m2775 -o root -g latte /var/lib/latteos/greeter /var/lib/latteos/greeter/avatars   # avatary pre obrazovku prihlásenia
[ -f /var/lib/latteos/greeter/greeter.conf ] || sudo install -m664 -o root -g latte "$S/greeter/greeter.conf" /var/lib/latteos/greeter/greeter.conf

echo "== App Manager: Flatpak a Flathub (inštalácia aplikácií pre používateľa bez roota)"
rpm -q bubblewrap xdg-dbus-proxy nmap-ncat >/dev/null || sudo dnf -y -q install bubblewrap xdg-dbus-proxy nmap-ncat   # izolácia aplikácií (latte-sandbox odmietne bez nej)
rpm -q flatpak >/dev/null || sudo dnf -y -q install flatpak
rpm -q rclone >/dev/null || sudo dnf -y -q install rclone        # Synchronizácia (cloudové priečinky)
rpm -q breeze-icon-theme >/dev/null || sudo dnf -y -q install breeze-icon-theme   # ikony súborov (Kapsa, Súbory)
rpm -q pandoc-cli hunspell-sk poppler-utils >/dev/null || sudo dnf -y -q install pandoc-cli hunspell hunspell-sk poppler-utils   # Heidelberg: dokumenty, PDF a kontrola textu
rpm -q smartmontools dmidecode mesa-demos vulkan-tools i2c-tools >/dev/null || sudo dnf -y -q install smartmontools dmidecode mesa-demos vulkan-tools i2c-tools   # Monitor › Hardvér (SMART, moduly, OpenGL/Vulkan, SPD)
rpm -q bsdtar 7zip >/dev/null || sudo dnf -y -q install bsdtar 7zip
# Tapety (živé tapety podľa Aury): mpvpaper, mpv, ffmpeg na náhľady — video sa spustí iba s GPU
# dialóg výberu súboru (Prehľadávať…) a vzhľad GTK aplikácií podľa témy (šablóny gtk3/gtk4 v config.toml Noctalie)
rpm -q zenity adw-gtk3-theme >/dev/null || sudo dnf -y -q install zenity adw-gtk3-theme
rpm -q mpvpaper mpv ffmpeg-free ffmpegthumbnailer >/dev/null || sudo dnf -y -q install mpvpaper mpv ffmpeg-free ffmpegthumbnailer   # Súbory: archívy ako priečinky (zip, 7z, rar, tar, iso), balenie 7z
rpm -q wf-recorder wtype >/dev/null || sudo dnf -y -q install wf-recorder wtype   # nahrávanie obrazovky (Win+Alt+R), vloženie emoji (Win+.)
rpm -q fuse3 >/dev/null || sudo dnf -y -q install fuse3                             # FTP/SFTP ako priečinky (latte-siet, rclone mount)
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "== aplikácie LatteOS (Quickshell QML): Súbory, Nastavenia, Monitor, Aplikácie"
sudo install -d /usr/share/latteos/apps/common /usr/share/latteos/apps/data
sudo install -m644 "$S"/apps/*.qml /usr/share/latteos/apps/
sudo install -m644 "$S"/apps/common/*.qml /usr/share/latteos/apps/common/
sudo install -m644 "$S"/apps/data/*.qml /usr/share/latteos/apps/data/
sudo install -m644 "$S"/apps/*.desktop /usr/share/applications/
xdg-mime default latteos-subory.desktop inode/directory 2>/dev/null || true
# Markdown otvára Heidelberg (editor dokumentov LatteOS); obyčajný text ostáva na systémovej voľbe
xdg-mime default latteos-heidelberg.desktop text/markdown 2>/dev/null || true
# inštalačné súbory otvára App Manager („Bude to fungovať?“)
for m in application/x-rpm application/vnd.flatpak.ref application/x-msdownload application/vnd.android.package-archive application/vnd.debian.binary-package application/x-iso9660-appimage; do
    xdg-mime default latteos-aplikacie.desktop "$m" 2>/dev/null || true
done

echo "== systemd + tmpfiles + /etc/latteos"
sudo install -Dm644 "$S/systemd/latte-boot.service" /usr/lib/systemd/system/latte-boot.service
sudo install -Dm755 "$S/bin/latte-netd" /usr/libexec/latteos/latte-netd                     # okamžité tlačidlo NET (root)
sudo install -Dm644 "$S/systemd/latte-netd.service" /usr/lib/systemd/system/latte-netd.service
sudo install -Dm644 "$S/systemd/latteos.tmpfiles" /usr/lib/tmpfiles.d/latteos.conf
sudo install -Dm644 "$S/systemd/latte-session.target" /usr/lib/systemd/user/latte-session.target
# SELinux: greeter beží v doméne xdm_t a smie čítať iba xdm_var_run_t → štítok pre /run/latteos
# (bez neho greeter nevidí session.env a vždy ponúkne SAFE; zistené testom 23. 9. 2026)
if command -v semanage >/dev/null || sudo dnf -y -q install policycoreutils-python-utils; then
    sudo semanage fcontext -l 2>/dev/null | grep -q '^/run/latteos' || sudo semanage fcontext -a -t xdm_var_run_t '/run/latteos(/.*)?'
    sudo semanage fcontext -l 2>/dev/null | grep -q '^/var/lib/latteos/greeter' || sudo semanage fcontext -a -t xdm_var_lib_t '/var/lib/latteos/greeter(/.*)?'
fi
sudo restorecon -R /var/lib/latteos/greeter 2>/dev/null || true
sudo systemd-tmpfiles --create /usr/lib/tmpfiles.d/latteos.conf
sudo restorecon -R /run/latteos
[ -f /etc/latteos/boot.toml ] || sudo install -Dm644 "$S/etc/boot.toml" /etc/latteos/boot.toml
# nové kľúče doplniť do existujúceho boot.toml (hodnoty používateľa sa nemenia)
grep -q '^greeter' /etc/latteos/boot.toml || sed -n '/^# obrazovka prihlásenia/,/^greeter/p' "$S/etc/boot.toml" | sudo tee -a /etc/latteos/boot.toml >/dev/null
echo "== OOM politika (F5): najprv aplikácia, nie relácia"
sudo install -Dm644 "$S/oom/user@-50-latteos-oom.conf" /usr/lib/systemd/system/user@.service.d/50-latteos-oom.conf
sudo install -Dm644 "$S/oom/user@-52-latteos-oomd.conf" /usr/lib/systemd/system/user@.service.d/52-latteos-oomd.conf
sudo install -Dm644 "$S/oom/user.conf.d-50-latteos-oom.conf" /usr/lib/systemd/user.conf.d/50-latteos-oom.conf
grep -v '^#' "$S/oom/services.list" | while read -r svc; do
    [ -n "$svc" ] && sudo install -Dm644 "$S/oom/user-service-50-latteos-oom.conf" "/usr/lib/systemd/user/$svc.service.d/50-latteos-oom.conf"
done
sudo systemctl daemon-reload
sudo systemctl enable --now latte-netd.service || echo "   latte-netd sa nespustil (NET bude platiť až po reštarte aplikácie)"

echo "== greetd → latte-greeter (záloha pôvodnej konfigurácie raz)"
[ -f /etc/greetd/config.toml.pre-latteos ] || sudo cp -a /etc/greetd/config.toml /etc/greetd/config.toml.pre-latteos
sudo install -Dm644 "$S/greetd/config.toml" /etc/greetd/config.toml

echo "== GRUB: položky LatteOS SAFE pre nainštalované kernely"
sudo install -Dm755 "$S/kernel-install/96-latteos-safe.install" /etc/kernel/install.d/96-latteos-safe.install
for k in /lib/modules/*/; do
    v="$(basename "$k")"
    [ -e "/boot/vmlinuz-$v" ] && sudo /etc/kernel/install.d/96-latteos-safe.install add "$v"
done
sudo sh -c 'ls /boot/loader/entries/' | sed 's/^/   /'

echo "== Plymouth téma latteos"
th=/usr/share/plymouth/themes/latteos
sudo install -d "$th"
sudo install -m644 "$S/plymouth/latteos/latteos.plymouth" "$th/latteos.plymouth"
# otáčadlo a ikonky dialógov (heslo, capslock…) zo systémovej témy spinner, potom naše logo navrch
sudo sh -c "cp -f /usr/share/plymouth/themes/spinner/*.png $th/"
tmp="$(mktemp --suffix=.png)"
python3 "$S/plymouth/latteos/make-logo.py" "$tmp" 192
sudo install -m644 "$tmp" "$th/watermark.png"
rm -f "$tmp"
if [ "$(plymouth-set-default-theme)" != latteos ]; then
    echo "   plymouth-set-default-theme latteos -R (prestavba initramfs, ~1 min)"
    sudo plymouth-set-default-theme latteos -R
fi

echo "== hyprland-latte: lokálny repozitár, COPR ho nesmie prepísať"
rpm -q createrepo_c >/dev/null || sudo dnf -y -q install createrepo_c
sudo install -d /var/lib/latteos/repo
sudo cp -f "$HOME"/rpmbuild/RPMS/x86_64/hyprland-{0,devel-0,uwsm-0}*.latte.*.rpm /var/lib/latteos/repo/ 2>/dev/null || true
sudo createrepo_c -q /var/lib/latteos/repo
sudo tee /etc/yum.repos.d/latteos-local.repo >/dev/null <<'REPO'
[latteos-local]
name=LatteOS lokálne balíky (hyprland-latte s vmwgfx patchom)
baseurl=file:///var/lib/latteos/repo
enabled=1
gpgcheck=0
priority=10
REPO
copr=/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:lionheartp:Hyprland.repo
if [ -f "$copr" ] && ! grep -q '^excludepkgs=hyprland' "$copr"; then
    sudo sed -i '/^\[copr:copr.fedorainfracloud.org:lionheartp:Hyprland\]/a excludepkgs=hyprland,hyprland-devel,hyprland-uwsm,hyprland-debuginfo,hyprland-debugsource' "$copr"
fi

echo "== verzia súčastí LatteOS (App Manager › Aktualizácie porovnáva s repozitárom)"
printf 'commit=%s\ndate=%s\nbranch=%s\nsource=%s\n' "$(git -C "$repo" rev-parse --short HEAD 2>/dev/null)" "$(git -C "$repo" log -1 --format=%cs 2>/dev/null)" \
    "$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)" "$repo" | sudo tee /usr/share/latteos/VERSION >/dev/null

echo "== prvý výber režimu"
sudo systemctl restart latte-boot.service || sudo latte-boot select
latte-boot status | sed 's/^/   /'
{ Hyprland --verify-config -c /usr/share/latteos/hypr/hyprland.lua 2>&1 || true; } | tail -2 | sed 's/^/   Hyprland: /'

if [ $enable -eq 1 ]; then
    echo "== zapínam grafický štart: latte-boot + greetd, graphical.target"
    sudo systemctl enable latte-boot.service greetd.service
    sudo systemctl set-default graphical.target
    echo "   Pri ďalšom reštarte naštartuje LatteOS greeter. Konzola ostáva na Ctrl+Alt+F2, SSH beží ďalej."
else
    if systemctl is-enabled -q greetd.service 2>/dev/null; then
        echo "== grafický štart je zapnutý (greetd); súbory sú aktualizované"
    else
        echo "== grafický štart NIE je zapnutý (spusti s --enable)"
    fi
fi
if pgrep -x noctalia >/dev/null; then
    echo "   Bežiaca Noctalia prevezme zmeny konfigurácie sama; NOVÉ pluginy (panely) až po reštarte shellu:"
    echo "   pkill -x noctalia; hyprctl eval 'hl.exec_cmd(\"noctalia\")'   (alebo sa odhlás a prihlás)"
fi
echo "Hotovo. Nová skupina latte platí po novom prihlásení používateľa $user."
