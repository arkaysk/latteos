# LatteOS — relácia (session/)

Čo je v tomto priečinku a kam sa to inštaluje. Inštalácia: `setup/f1/install-session.sh` (bezpečné
opakovať, konfigurácie vymieňa atomicky). Kontrola bez obrazovky: `setup/f1/apps-check.sh`,
`setup/f1/plugins-check.sh`.

## Štart a relácia

| Súbor | Úloha |
|---|---|
| `../crates/latte-boot` | pri štarte vyberie NORMAL/SAFE a grafiku → `/run/latteos/{mode.toml,session.env}`, počítadlo pádov |
| `bin/latte-greeter`, `greeter/shell.qml` | obrazovka prihlásenia (Quickshell pod labwc + pixman): posledné dva účty, log pádu, vzhľad z `/var/lib/latteos/greeter/` |
| `bin/latte-session` | relácia: Hyprland (NORMAL) alebo labwc (SAFE), strážca pádov, záznam pádu pre greeter, jazyk z `~/.config/latteos/locale` |
| `hypr/hyprland.lua`, `hypr/latte/*.lua` | Lua modul: stupne výkonu, režimy okien, rozloženia (Super+Z), herný režim, OOM, skratky, gestá |
| `oom/` | OOM politika (F5): najprv aplikácia, nie relácia |

## Shell (Noctalia) — `noctalia/`

`config.toml` je základ (lišta z ostrovov), zmeny používateľa idú do `~/.local/state/noctalia/settings.toml`
(`bin/latte-shellset`). Pluginy (`noctalia/plugins/`, Luau):

| Plugin | Čo robí |
|---|---|
| `apps` | široká dlaždica aplikácií s textúrou (klik spúšťač, pravý klik App Manager) |
| `time` | čas a dátum; panel Čas · Oznámenia · Kalendár s plánovačom |
| `system` | šálka = systémové menu (relácia, režim, stupeň, okná, napájanie) |
| `textbar` | Text Bar: Lokálne / Web / AI / Linux príkaz |
| `cat` | maskot (vlastná pixel-art, `make-mascots.py`) |
| `kapsa` | schránka: jedna vec navrchu, sloty histórie (cliphist) |
| `devices` | Zariadenia: sieť, zvuk, jas, herný režim, profil výkonu |
| `overview` | prehľad pásky (Super+Tab) |
| `snap` | rozloženie okna (Super+Z) |
| `ai` | AI rozhovor (Super+I) |
| `games` | Herňa (Super+G) |

Pozor: `runAsync` má v Noctalii limit 5 s (tretí argument, max 60 s); dlhé príkazy cez `runStream`.
Nové pluginy (panely) sa načítajú až po reštarte shellu; `require` iba `"./subor.luau"`.

## Aplikácie (Quickshell QML) — `apps/`, spúšťa `bin/latte-app <meno> [arg]`

| Aplikácia | Backend | Poznámka |
|---|---|---|
| `nastavenia` | `latte-shellset`, `latte-theme`, `latte-ai`, `latte-backup`… | vrstvené karty oblastí, detail Stav/Oblasť/Uložené v |
| `subory` | — | Data Manager: dva panely, štítky, kôš, kopírovanie s priebehom, hľadanie všade |
| `monitor` | `latte-sysmon` | procesy, po štarte, telemetria (Ctrl+Shift+Esc) |
| `aplikacie` | `latte-apps`, `latte-net` | App Manager: Objavovať, Aktualizácie, Nainštalované, NET, „Bude to fungovať?“ |
| `zariadenia` | `latte-devices` | Device Manager, obrazovky s potvrdením do 15 s |
| `heidelberg` | — | editor dokumentov (md, html, txt) |
| `barista` | — | sprievodca prvým spustením |

Spoločná kostra: `apps/common/` (LatteTheme, SideBar, CardStack, HeaderBar s NET, ContextMenu, Glyph).
Ikony Glyph sú výber z Tabler (`common/Glyph.qml`); nová ikona sa musí pridať do mapy.

## Nástroje (`bin/`)

`latte-theme` (témy, svetlá/tmavá/auto, tapeta podľa plochy) · `latte-shellset` (prepisy Noctalie) ·
`latte-ai` (lokálne/domáci server/cloud, chat) · `latte-sysmon` · `latte-apps` · `latte-devices` ·
`latte-backup` (snímky rsync --link-dest) · `latte-games` (Steam/Heroic, herný režim) ·
`latte-net` (internet pre aplikáciu: Flatpak override / bubblewrap) · `latte-safe` (ponuka SAFE).

## Kde sú dáta používateľa

| Čo | Kde |
|---|---|
| téma, režim, stupeň, maskot, lišta | `~/.config/latteos/{theme,theme-mode,tier,mascot,bar-anim,bar-scene}` |
| AI | `~/.config/latteos/ai.toml`, kľúče `ai-keys` (0600) |
| štítky a obľúbené Súborov | `~/.config/latteos/tags.json`, `subory.json` |
| obrazovky | `~/.config/latteos/monitors.lua` |
| zálohy | `~/.config/latteos/backup.conf` → `<cieľ>/LatteOS-zaloha-<meno>/<dátum>` |
| udalosti kalendára | `~/.local/share/latteos/events.json` |
| stav okien, herný režim | `~/.local/state/latteos/{window-mode,game-mode}` |
| greeter (systém) | `/var/lib/latteos/greeter/{greeter.conf,last-crash.log,avatars/}` |
