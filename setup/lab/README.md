# latte-lab — reálne testovacie PC

28. 9. 2026 · @Arkay

ASUS Rampage IV Gene (X79) · i7-4820K · 16 GB · AMD RX 550 (Polaris, RADV) · WD 500 GB · len kábel.
Stojí pod stolom, káblom priamo v hlavnom PC, bez klávesnice; všetko ide z hlavného PC (SSH, VS Code, Cockpit, Moonlight).

Postup: **ručne** BIOS a Anaconda (~20 min, disk sa delí raz a s ohľadom na Bazzite), potom **jeden príkaz**
cez SSH: `setup/lab/install.sh`.

## 1. BIOS (Del pri štarte)

- Load Optimized Defaults → UEFI boot, SATA **AHCI**.
- **Wait for 'F1' If Error → Disabled** (štart bez klávesnice).
- APM: **Restore AC Power Loss → Power On**, **Power On By PCIE/PCI → Enabled**, **ErP Ready → Disabled**
  (bez toho sieťovka vo vypnutom PC nemá prúd a Wake-on-LAN nejde).
- F10, pri štarte **F8** → USB ako `UEFI: …`. USB kľúč do **čierneho USB 2.0** portu vzadu
  (modré USB 3.0 sú na čipe ASMedia a zavádzanie z nich býva nespoľahlivé; biely ROG Connect nie).

## 2. Disk 500 GB (= 465 GiB) — Fedora, Bazzite, Dáta

| # | Oddiel | Veľkosť | Súborový systém | Kto |
|---|---|---|---|---|
| 1 | EFI Fedora | 1 GiB | FAT32 `/boot/efi` | Fedora |
| 2 | boot Fedora | 2 GiB | ext4 `/boot` | Fedora |
| 3 | Fedora | 120 GiB | Btrfs, subvolúmy `root` → `/`, `home` → `/home` | Fedora |
| 4 | Dáta | 220 GiB | Btrfs `/data` (samostatný oddiel, nie subvolúm oddielu 3) | spoločné |
| — | **voľné** | ~122 GiB | nič | neskôr Bazzite |

- 100 GiB na systém stačí (vývojová VM má celý disk 52 GB). 120 dáva rezervu na snímky Btrfs a Ollama modely;
  **hry, ISO a veľké modely patria na `/data`**, tam ich uvidí Fedora aj Bazzite (Steam knižnica na `/data/steam`).
- V Anaconde: *Installation Destination → Advanced Custom (Blivet-GUI)*. Pri `/data` zvoliť nový oddiel
  (partition), nie subvolúm v Btrfs oddielu Fedory. Zvyšok disku nechať **nerozdelený**.

### Bazzite neskôr: vlastné EFI

Fedora aj Bazzite zapisujú zavádzač do `EFI/fedora/` — pri spoločnom EFI oddiele by Bazzite prepísal zavádzač
Fedory. Bazzite preto dostane **vlastný EFI a boot**. Pred inštaláciou Bazzite ich vytvor z Fedory cez SSH
(disk `sda` over cez `lsblk`):

```
sudo dnf -y install gdisk
sudo sgdisk -n 0:0:+1G -t 0:ef00 -c 0:bazzite-efi \
            -n 0:0:+2G -t 0:8300 -c 0:bazzite-boot \
            -n 0:0:0   -t 0:8300 -c 0:bazzite-root /dev/sda
lsblk -o NAME,SIZE,PARTLABEL /dev/sda
```

V inštalátore Bazzite potom *priradenie prípojných bodov*: `bazzite-efi` → `/boot/efi` (formátovať),
`bazzite-boot` → `/boot`, `bazzite-root` → `/`, `/data` nechať bez zmeny.

Prepínanie systémov bez monitora: oba zápisy v UEFI sa volajú „Fedora“, líšia sa oddielom (`efibootmgr -v`).
Z bežiaceho systému cez SSH: `sudo efibootmgr --bootnext XXXX && sudo reboot` — raz naštartuje druhý systém,
potom sa vráti na predvolený. Wake-on-LAN treba zapnúť v každom systéme zvlášť (`nmcli`, pozri `install.sh`).

## 3. Anaconda

English, klávesnica sk + us, Europe/Bratislava, hostname **latte-lab**, sieť automaticky, root uzamknutý,
používateľ **arkay** (administrátor), softvér predvolený Fedora Server. Po reštarte vytiahnuť USB.

## 4. Sieť: kábel priamo do hlavného PC

Latte-lab stojí pod stolom a je **natrvalo** zapojený krátkym káblom do voľného Ethernetu hlavného PC
(Wi-Fi nemá, switch je inde). Hlavné PC mu zdieľa internet zo svojej Wi-Fi (Windows ICS).

1. Windows: *Ovládací panel → Sieťové pripojenia → Wi-Fi → Vlastnosti → Zdieľanie →* „Povoliť ostatným
   používateľom siete pripojiť sa…“, vybrať **Ethernet**. Ethernet hlavného PC dostane `192.168.137.1`,
   latte-lab cez DHCP `192.168.137.x` (inštalácia z DVD ISO ide aj bez siete).
2. Zdieľanie po reštarte Windowsu občas samo prestane fungovať. Prevencia (PowerShell ako správca):
   ```
   Set-Service SharedAccess -StartupType Automatic
   New-ItemProperty -Path HKLM:\Software\Microsoft\Windows\CurrentVersion\SharedAccess -Name EnableRebootPersistConnection -Value 1 -PropertyType DWord -Force
   ```
3. Adresa: `ssh arkay@latte-lab.local` (mDNS zapne `install.sh`). Ak by Windows `.local` na tomto
   pripojení nenašiel, pevná adresa: `setup/lab/install.sh --ip 192.168.137.50/24 --gw 192.168.137.1`.
4. `~/.ssh/config` vo Windowse, potom stačí `ssh latte-lab` aj vo VS Code:
   ```
   Host latte-lab
       HostName latte-lab.local
       User arkay
   ```

Dôsledky: latte-lab má internet iba keď beží hlavné PC (a tak sa aj tak ovláda z neho); z iných zariadení
v domácej sieti nie je vidieť; Moonlight ide priamo po gigabitovom kábli (menšie oneskorenie ako cez switch).
Wake-on-LAN posiela hlavné PC rovno do toho kábla. Monitor je vedľa: záchrana = prepnúť vstup / prepojiť kábel.

Bez hlavného PC (napr. na stiahnutie pred prvým zapojením) by stačil aj USB tethering z telefónu — Fedora ho
vidí ako sieťovku bez ovládačov (~3–4 GB dát pre `install.sh`).

## 5. Prvé kroky s monitorom, potom jeden príkaz

Na latte-lab: `ip -4 -br a` (adresa). Z hlavného PC (PowerShell) skopírovať kľúč:

```
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh arkay@<IP> "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Potom už cez SSH, **monitor nechať zapojený** (skript si uloží jeho EDID do `~/edid/` ako náhradu dummy zástrčky):

```
sudo dnf -y install git
git clone https://github.com/arkaysk/latteos && cd latteos
setup/lab/install.sh
```

`install.sh` (opakovateľný, záznam v `~/latte-lab-install.log`):

1. snímka Btrfs pred zmenami (`snapper`),
2. `dnf upgrade`,
3. SSH (heslo sa vypne, iba ak je uložený kľúč), Cockpit, mDNS, firewall,
4. Wake-on-LAN, prípadne pevná adresa,
5. RPM Fusion + VA-API s H.264/HEVC pre AMD (kódovanie pre Sunshine),
6. `setup/f0-install.sh` (balíky; VirtualBox časť sa na reálnom PC preskočí),
7. `setup/f1/install-session.sh` (latte-boot, relácie, greeter, GRUB SAFE, Plymouth),
8. kontrola: ovládač GPU, Vulkan, `latte-boot status` (čakáme `renderer = hw`), adresa.

Grafický štart zapne až `setup/lab/install.sh --enable`, keď kontrola vyjde a SSH aj Cockpit fungujú.
Potom test bez periférií: `sudo poweroff`, odpojiť monitor a klávesnicu, zobudiť Wake-on-LAN, `ssh latte-lab`.
Monitor Acer Predator Z301C má DP (hlavné PC, G-Sync) a HDMI. RX 550 HDMI nemá → latte-lab trvalo do HDMI
cez pasívny kábel/redukciu **mini-DP → HDMI**; vstup sa prepína v ponuke monitora (Input). Kým monitor hlási
EDID aj na neaktívnom vstupe, funguje ako dummy zástrčka. Overiť s monitorom prepnutým na hlavné PC:
`cat /sys/class/drm/card*-DP-*/status` → `connected` (aj cez redukciu sa výstup volá DP-x). Na inštaláciu stačí dočasne prepojiť DP kábel.

## Neskôr (nie je v skripte)

- Dummy zástrčka do DP → Sunshine + Moonlight, automatické prihlásenie cez greetd do `latte-session`.
  Bez nej (skúsiť v tomto poradí): virtuálny výstup Hyprlandu `hyprctl output create headless` (kreslí GPU,
  Sunshine ho zachytí), alebo uložený EDID ako softvérový monitor: `~/edid/DP-1.bin` → `/usr/lib/firmware/edid/`
  a parametre jadra `drm.edid_firmware=DP-1:edid/DP-1.bin video=DP-1:e` (na DP pri amdgpu neisté, treba overiť).
- `latte-shell` (fork Noctalie) sa postaví, iba ak je zdroj v `~/latte-shell`; inak beží Noctalia z COPR.
- `hyprland-latte` (vmwgfx záplata) na reálnom PC netreba; Hyprland ostáva z COPR `lionheartp/Hyprland`
  a jeho aktualizácie z COPR blokuje `excludepkgs` (pluginy sú postavené proti nainštalovanej verzii).

## Na diaľku bez monitora, myši a klávesnice (Sunshine + Moonlight)
Sunshine je server na latte-lab (sníma obrazovku, kóduje grafickou kartou, prijíma myš a klávesnicu), Moonlight je
klient na pracovnom PC. Rýchlejšie a plynulejšie ako VNC/RDP (stavané na hry), so zvukom.

1. Na latte-lab (raz): `sudo setup/lab/vzdialene.sh` — Sunshine z oficiálneho COPR `lizardbyte/stable` ako služba
   v každej relácii LatteOS, snímanie cez Wayland (`capture = wlr`), kódovanie VAAPI (RX 640: H.264, HEVC), porty
   vo firewalle, **automatické prihlásenie** po štarte (greetd `initial_session`; po odhlásení je prihlasovacia
   obrazovka). Bez pripojeného monitora si Hyprland vytvorí **virtuálnu obrazovku** `LATTE-VIRT` 1920×1080
   (hyprland.lua), po pripojení monitora ju zruší.
2. Na pracovnom PC (Windows, PowerShell): `winget install MoonlightGameStreamingProject.Moonlight`
3. V prehliadači na pracovnom PC: `https://192.168.137.231:47990` — pri prvej návšteve si vytvoríš meno a heslo
   správcu Sunshine (certifikát je vlastný, prehliadač sa spýta; pokračovať).
4. V Moonlighte: ⊕ → `192.168.137.231` → ukáže PIN → zadať ho v Sunshine (karta PIN) → Desktop.

Po odpojení monitora (overené 30. 9.): Hyprland prejde na `LATTE-VIRT`, okná mimo obrazovky vráti na stred,
priveľké zmenší na 90 % a prepne na plochu s oknami (`latte.windows_onscreen`, hyprland.lua).
Ukončenie streamu: Ctrl+Alt+Shift+Q (Moonlight). Obraz sa prispôsobí rozlíšeniu okna Moonlightu.
