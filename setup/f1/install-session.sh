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
BINS="latte-session latte-safe latte-greeter latte-greetd latte-goo-greeter latte-zamok latte-gooconfig latte-theme latte-app latte-ai latte-shellset latte-sysmon latte-apps latte-devices latte-backup latte-games latte-net latte-cloud latte-siet latte-otvor latte-kos latte-spustac latte-sandbox latte-kopia latte-tc latte-ostrovy latte-rychle latte-tapety latte-vyber latte-ponuka latte-prichytenie latte-snimka latte-emoji latte-nove-okno latte-nahravanie latte-maskoti latte-sklo latte-inspektor latte-terminal latte-hypr-udalosti latte-sukromie latte-kapsa-store latte-hra latte-kvapky latte-profil latte-upstream latte-marea latte-serpantinum latte-hladaj latte-riadok latte-pocasie latte-chatgoo latte-goo"
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
put "$S/hypr/noctalia.lua" /usr/share/latteos/hypr/noctalia.lua     # relácia „Noctalia (čistá)“
for f in rc.xml autostart environment menu.xml; do sudo install -Dm644 "$S/labwc/$f" "/usr/share/latteos/labwc/$f"; done
# relácie LatteOS: v systémovom zozname (pre iné greetery) aj vo vlastnom, ktorý ponúka latte-greeter
# (tuigreet by inak ponúkol aj „Hyprland“ z COPR bez Noctalie a bez latte-session).
# Ponuka prihlásenia (6. 10. 2026): LatteOS GOO a Noctalia (čistá) odtiaľto; samostatné prostredia Marea a Serpantinum
# si svoju položku inštalujú samy (setup/lab/marea-povodna.sh, setup/lab/serpantinum.sh). Mimo ponuky: SAFE (príde
# sám pri pádoch alebo z GRUB › LatteOS SAFE), Hra (z plochy cez latte-hra), zrušený Classic a pôvodná plocha Kvapky.
for f in latteos.desktop latteos-noctalia.desktop; do
    sudo install -Dm644 "$S/wayland-sessions/$f" "/usr/share/wayland-sessions/$f"
    sudo install -Dm644 "$S/wayland-sessions/$f" "/usr/share/latteos/sessions/$f"
done
for f in latteos-safe.desktop latteos-hra.desktop latteos-kvapky.desktop latteos-goo-engine.desktop; do   # staré položky ponuky
    sudo rm -f "/usr/share/wayland-sessions/$f" "/usr/share/latteos/sessions/$f"
done

echo "== latte-shell (fork Noctalie: panely v tvare L z ostrova), ak je zdroj v ~/latte-shell"
if [ -d "$HOME/latte-shell/src" ]; then "$repo/setup/f1/build-latte-shell.sh" | tail -2 | sed 's/^/   /'; else echo "   preskočené (bez ~/latte-shell ostáva pôvodná Noctalia)"; fi
echo "== okenné tlačidlá: plugin hyprbars (postavený proti hyprland-devel)"
if rpm -q hyprland-devel >/dev/null 2>&1 && "$repo/setup/f1/build-hyprbars.sh" | sed 's/^/   /'; then
    sudo install -Dm755 "$repo/resources/upstream/hyprland-plugins/hyprbars/hyprbars.so" /usr/lib64/latteos/hyprbars.so
else
    echo "   hyprbars sa nepostavil (chýba hyprland-devel?) — okná bez vlastnej hlavičky budú bez tlačidiel"
fi
echo "== sklo okien s perleťovými okrajmi: plugin Hyprglass (iba plocha Goo a sklenené témy, latte/sklo.lua)"
if rpm -q hyprland-devel >/dev/null 2>&1 && "$repo/setup/f1/build-hyprglass.sh" | sed 's/^/   /'; then
    sudo install -Dm755 "$repo/resources/upstream/hyprglass/hyprglass.so" /usr/lib64/latteos/hyprglass.so
else
    echo "   hyprglass sa nepostavil (chýba hyprland-devel?) — okná bez skla"
fi
echo "== prichytenie okien k okrajom: plugin latte-okna (udalosti ťahania pre latte/prichytenie.lua)"
if rpm -q hyprland-devel >/dev/null 2>&1 && make -s -C "$S/hypr/plugins/latte-okna" >/dev/null; then
    sudo install -Dm755 "$S/hypr/plugins/latte-okna/latte-okna.so" /usr/lib64/latteos/latte-okna.so
else
    echo "   latte-okna sa nepostavil — okná sa nebudú prichytávať ťahaním (Win+←→ a Win+Z fungujú)"
fi
echo "== LatteOS GOO: textúry okien, engine Goo, pleamar so záplatami LatteOS"
# pôvodná plocha Kvapky (session/kvapky/kvapka.plm) sa od 6. 10. 2026 nenasadzuje; jej scéna z predošlej inštalácie preč
sudo rm -f /usr/share/latteos/kvapky/kvapka.plm /usr/share/latteos/kvapky/kvapka.luau /usr/share/latteos/kvapky/ikony.luau
sudo install -d /usr/share/latteos/kvapky/textury                     # textúry materiálov okien (textury.py)
sudo install -m644 "$S"/kvapky/textury/*.webp "$S"/kvapky/textury/LICENCIA.txt /usr/share/latteos/kvapky/textury/
sudo rm -f /usr/share/latteos/goo/kvapky/*.luau        # premenované kvapky (TimeGoo → LensGoo…) neostanú ako staré súbory
( cd "$S/goo" && for f in goo.plm goo.luau login.plm login.luau zamok.plm zamok.luau README.md lib/*.luau kvapky/*.luau priklady/*.json; do
    put "$f" "/usr/share/latteos/goo/$f"; done )
# menšie scény enginu (32 a 64 miest): prázdne miesta stoja CPU každú snímku, engine preto beží na najmenšej scéne,
# do ktorej sa zmestí, a o väčšiu si povie sám (latte-kvapky miesta N). Logika a kvapky sú spoločné (odkazy).
for n in 32 64; do
    tmpg="$(mktemp -d)"
    python3 "$S/goo/gen.py" --n "$n" --out "$tmpg" >/dev/null
    sudo install -d "/usr/share/latteos/goo/m$n"
    put "$tmpg/goo.plm" "/usr/share/latteos/goo/m$n/goo.plm"
    put "$S/goo/goo.luau" "/usr/share/latteos/goo/m$n/goo.luau"
    for l in lib kvapky priklady; do sudo ln -sfn "../$l" "/usr/share/latteos/goo/m$n/$l"; done
    rm -rf "$tmpg"
done
pl="$repo/resources/upstream/pleamar"
pl_ver=0.2.24                                      # pripnutá verzia (resources/fetch.sh); staršia sa preloží znova
pl_patched() { git -C "$pl" apply --reverse --check "$repo/resources/patches/$1.patch" 2>/dev/null; }   # už je v zdroji
if command -v cargo >/dev/null && { ! "$pl/target/release/pleamar" --version 2>/dev/null | grep -q "pleamar $pl_ver " \
        || ! pl_patched pleamar-prazdne-tvary || ! pl_patched pleamar-ostre-okraje || ! pl_patched pleamar-pasy-tela; }; then
    "$repo/resources/fetch.sh" pleamar >/dev/null
    # záplaty LatteOS (resources/patches/README.md); prazdne-tvary: prázdne miesta enginu Goo nič nestoja (bez nej
    # pomalšie); ostre-okraje: ostrý okraj aj v zliatí (oká medzi kvapkami); pasy-tela: pixel počíta iba tvary
    # vo svojom dosahu (záťaž GPU nerastie s počtom kvapiek)
    for z in pleamar-hyprland-okna-8bit pleamar-prazdne-tvary pleamar-ostre-okraje pleamar-pasy-tela; do
        pl_patched "$z" && continue
        git -C "$pl" apply --check "$repo/resources/patches/$z.patch" 2>/dev/null && git -C "$pl" apply "$repo/resources/patches/$z.patch" \
            || echo "   záplata $z sa nedá použiť (možno ju autor už má)"
    done
    (cd "$pl" && cargo build --release -q) || true
fi
# brána: scéna sa nasadí, iba ak ju tento pleamar prečíta (inak by relácia ukázala iba tapetu)
if [ -x "$pl/target/release/pleamar" ]; then
    python3 "$S/goo/gen_zamok.py" --check || echo "   POZOR: zamok.plm nezodpovedá login.plm — spusti python3 session/goo/gen_zamok.py"
    for sc in "$S/goo/goo.plm" "$S/goo/login.plm" "$S/goo/zamok.plm"; do
        "$pl/target/release/pleamar" --check "$sc" >/dev/null 2>&1 || echo "   POZOR: $sc nepreložil pleamar $pl_ver: $("$pl/target/release/pleamar" --check "$sc" 2>&1 | head -1)"
    done
fi
if [ -x "$pl/target/release/pleamar" ]; then
    sudo install -Dm755 "$pl/target/release/pleamar" /usr/bin/pleamar
else
    echo "   pleamar sa nepostavil (chýba cargo?) — relácia LatteOS GOO ukáže iba tapetu"
fi

echo "== vzhľad: Noctalia (téma Latte), písma Manrope/Fraunces (OFL), tapety LatteOS"
put "$S/noctalia/config.toml" /usr/share/latteos/noctalia/config.toml   # Noctalia sleduje priečinok (hot reload)
sudo install -Dm644 "$S/noctalia/palettes/Latte.json" /usr/share/latteos/noctalia/palettes/Latte.json
sudo install -Dm644 "$S/noctalia/icons/latte-cup.png" /usr/share/latteos/noctalia/icons/latte-cup.png
# doplnky lišty a maskoti patria zrušenému Classicu; vo verejnej verzii nie sú (setup/verejne/vynechat.txt) — preskočia sa
for p in "$S"/noctalia/plugins/*/; do   # pluginy LatteOS (zdroj „latteos“ v config.toml)
    [ -d "$p" ] || continue
    n="$(basename "$p")"; sudo install -d "/usr/share/latteos/noctalia/plugins/$n"
    for f in "$p"*; do [ -f "$f" ] && sudo install -m644 "$f" "/usr/share/latteos/noctalia/plugins/$n/"; done   # súbory
    if [ -d "$p/translations" ]; then                                    # preklady doplnku (noctalia.tr)
        sudo install -d "/usr/share/latteos/noctalia/plugins/$n/translations"
        sudo install -m644 "$p"translations/*.json "/usr/share/latteos/noctalia/plugins/$n/translations/"
    fi
done
# maskoti na lištu: vlastná pixel-art, snímky sa generujú (plugin latteos/cat)
tmpm="$(mktemp -d)"
if [ -f "$S/noctalia/plugins/cat/make-mascots.py" ]; then
    python3 "$S/noctalia/plugins/cat/make-mascots.py" "$tmpm" | sed 's/^/   /'
    sudo install -d /usr/share/latteos/noctalia/plugins/cat/mascots
    sudo install -m644 "$tmpm"/*.png /usr/share/latteos/noctalia/plugins/cat/mascots/
fi
# balíčky maskotov (plné snímky + pet.json) pre výbehy — apps/maskot.qml
for d in "$S"/noctalia/plugins/cat/balicky/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"; sudo install -d "/usr/share/latteos/maskoti/$n"
    sudo install -m644 "$d"* "/usr/share/latteos/maskoti/$n/"
done
rm -rf "$tmpm"
sudo install -d /usr/share/fonts/latteos /usr/share/backgrounds/latteos
sudo install -m644 "$S"/fonts/*.ttf "$S"/fonts/OFL-*.txt /usr/share/fonts/latteos/
# ikony Tabler z Noctalie aj pre pleamar (spúšťač Kvapiek píše ikony ako znaky tohto písma)
[ -f /usr/share/noctalia/assets/fonts/noctalia-tabler.ttf ] && sudo ln -sf /usr/share/noctalia/assets/fonts/noctalia-tabler.ttf /usr/share/fonts/latteos/noctalia-tabler.ttf
sudo fc-cache -f /usr/share/fonts/latteos
sudo install -m644 "$S"/wallpapers/*.jpg /usr/share/backgrounds/latteos/
sudo install -d /usr/share/latteos/themes
sudo install -m644 "$S"/themes/*.theme /usr/share/latteos/themes/
sudo install -m644 "$S"/noctalia/palettes/*.json /usr/share/latteos/noctalia/palettes/
# slovenský katalóg Noctalie: bez neho je Noctalia celá po anglicky a nenačíta ani preklady doplnkov (1. 10. 2026)
[ -d /usr/share/noctalia/assets/translations ] && sudo install -m644 "$S/noctalia/translations/sk.json" /usr/share/noctalia/assets/translations/sk.json

echo "== greeter LatteOS (Quickshell QML pod labwc + pixman)"
sudo install -Dm644 "$S/greeter/shell.qml" /usr/share/latteos/greeter/shell.qml
sudo install -Dm644 "$S/greeter/I18n.qml" /usr/share/latteos/greeter/I18n.qml      # odkaz na apps/common/I18n.qml (Quickshell nič mimo priečinka)
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
rpm -q mpvpaper mpv ffmpegthumbnailer >/dev/null || sudo dnf -y -q install mpvpaper mpv ffmpegthumbnailer
# ffmpeg: plný z RPM Fusion (setup/lab/install.sh, dekódovanie grafickou kartou) alebo ffmpeg-free z Fedory
rpm -q ffmpeg >/dev/null || rpm -q ffmpeg-free >/dev/null || sudo dnf -y -q install ffmpeg-free
rpm -q wf-recorder wtype >/dev/null || sudo dnf -y -q install wf-recorder wtype   # nahrávanie obrazovky (Win+Alt+R), vloženie emoji (Win+.)
rpm -q fuse3 >/dev/null || sudo dnf -y -q install fuse3                             # FTP/SFTP ako priečinky (latte-siet, rclone mount)

echo "== systémový backend zariadení: telefón na USB, tlač a skenovanie (Správca zariadení, Súbory)"
# GVFS: telefón (MTP), fotoaparát (PTP), iPhone (AFC) a sieťové disky Windows (SMB) ako priečinky v /run/user/UID/gvfs
rpm -q gvfs-mtp gvfs-gphoto2 gvfs-afc gvfs-smb >/dev/null || sudo dnf -y -q install gvfs-mtp gvfs-gphoto2 gvfs-afc gvfs-smb
# tlač: CUPS s tlačou bez ovládača (IPP Everywhere / AirPrint, USB cez ipp-usb); skenovanie: SANE + sieťové skenery (airscan)
rpm -q cups cups-filters cups-pk-helper ipp-usb sane-backends sane-airscan simple-scan >/dev/null \
    || sudo dnf -y -q install cups cups-filters cups-pk-helper ipp-usb sane-backends sane-airscan simple-scan
# CUPS sa spustí až pri prvom použití (soket), nebeží stále
sudo systemctl enable --now cups.socket >/dev/null 2>&1 || true
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo "== aplikácie LatteOS (Quickshell QML): Súbory, Nastavenia, Monitor, Aplikácie"
sudo install -d /usr/share/latteos/apps/common /usr/share/latteos/apps/data
sudo install -m644 "$S"/apps/*.qml /usr/share/latteos/apps/
sudo install -m644 "$S"/apps/common/*.qml /usr/share/latteos/apps/common/
sudo install -d /usr/share/latteos/i18n               # preklady aplikácií LatteOS (common/I18n.qml): <jazyk>.json
sudo install -m644 "$S"/i18n/*.json /usr/share/latteos/i18n/
sudo install -m644 "$S"/apps/data/*.qml /usr/share/latteos/apps/data/
sudo install -m644 "$S"/apps/*.desktop /usr/share/applications/
xdg-mime default latteos-subory.desktop inode/directory 2>/dev/null || true
# Markdown otvára Heidelberg (editor dokumentov LatteOS); obyčajný text ostáva na systémovej voľbe
xdg-mime default latteos-heidelberg.desktop text/markdown 2>/dev/null || true
# inštalačné súbory otvára App Manager („Bude to fungovať?“)
for m in application/x-rpm application/vnd.flatpak.ref application/x-msdownload application/vnd.android.package-archive application/vnd.debian.binary-package application/x-iso9660-appimage; do
    xdg-mime default latteos-aplikacie.desktop "$m" 2>/dev/null || true
done
# AI: nástroje predplatných (Claude, ChatGPT, Gemini, Copilot) hneď pri inštalácii, nie dodatočne — pri výbere služby
# sa používateľ iba prihlási (meno a heslo) alebo zadá kľúč API. Preskočí sa, ak je AI vypnutá (Bez AI).
if grep -qs '^provider = "ziadna"' "${XDG_CONFIG_HOME:-$HOME/.config}/latteos/ai.toml"; then
    echo "== AI vypnutá — nástroje predplatných sa neinštalujú"
elif command -v npm >/dev/null; then
    echo "== AI: nástroje predplatných → /usr/local/lib/latteos-ai"
    sudo /usr/bin/latte-ai instaluj-system || echo "   (nepodarilo sa — Nastavenia › AI ich doinštalujú klikom)"
fi
# archívy otvárajú Súbory ako priečinok (bughunt/bug001: .zip nemal čím otvoriť)
for m in application/zip application/x-7z-compressed application/vnd.rar application/x-rar application/x-tar application/x-compressed-tar application/x-bzip2-compressed-tar application/x-xz-compressed-tar application/x-zstd-compressed-tar application/x-cd-image application/vnd.ms-cab-compressed application/x-cpio; do
    xdg-mime default latteos-subory.desktop "$m" 2>/dev/null || true
done
# „Nájsť viac v aplikácii Softvér“ (GTK) a iné volania gnome-software → App Manager, ak skutočný gnome-software chýba
if [ -x /usr/bin/gnome-software ]; then sudo rm -f /usr/local/bin/gnome-software
else sudo install -Dm755 "$S/bin/gnome-software" /usr/local/bin/gnome-software; fi

echo "== systemd + tmpfiles + /etc/latteos"
sudo install -Dm644 "$S/systemd/latte-boot.service" /usr/lib/systemd/system/latte-boot.service
sudo install -Dm755 "$S/bin/latte-netd" /usr/libexec/latteos/latte-netd                     # okamžité tlačidlo NET (root)
# háčik gamescope-session: Steam › Prepnúť na desktop → latte-hra desktop (Bazzite tu má steamosctl)
sudo install -Dm755 "$S/libexec/os-session-select" /usr/libexec/os-session-select
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
printf 'version=%s\ncommit=%s\ndate=%s\nbranch=%s\nsource=%s\n' "$(sed -n '/^\[workspace.package\]/,/^\[/s/^version = "\(.*\)"$/\1/p' "$repo/Cargo.toml")" "$(git -C "$repo" rev-parse --short HEAD 2>/dev/null)" "$(git -C "$repo" log -1 --format=%cs 2>/dev/null)" \
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
