# F1 — namerané výsledky na `latteOSdev`

23. 9. 2026 · VirtualBox VMSVGA (3D zapnuté), 4 vCPU, 11 GB RAM, výstup 1920×1080 · Mesa 26.2.3

Každý test: kompozitor na obrazovke VM (cez seatd), klienti `foot` (CPU/shm), `kitty` a
`es2gears_wayland` (GL → dmabuf), 25 s, potom screenshot. Skript: [probe.sh](probe.sh).
Surové logy a screenshoty ležia v `results/` (netrackované).

| Kompozitor | Cesta | Beží | foot | kitty | es2gears | FPS gears | CPU kompozitora | Poznámka |
|---|---|---|---|---|---|---|---|---|
| labwc 0.9.6 | **pixman** | ✅ | ✅ | ✅ | ✅ | 65 | 50 % | **SAFE funguje**; GL klienti prejdú na softvér |
| labwc 0.9.6 | swgl | ✅ | ✅ | ✅ | ✅ | 187 | 64 % | |
| labwc 0.9.6 | vm3d | ✅ | ✅ | ❌ | ❌ | — | 1 % | `importing the supplied dmabufs failed` (wlroots bez patchu) |
| Hyprland 0.56.2 (COPR) | vm3d | ✅ | ✅ | ❌ | ❌ | — | 31 % | `invalid arguments for wl_surface.attach`, čierna plocha okrem foot |
| Hyprland 0.56.2 (COPR) | **swgl** | ✅ | ✅ | ✅ | ✅ | 76 | 133 % | stabilné, bez artefaktov; aquamarine hlási `no renderer for gl formats` (bez vplyvu) |
| hyprland-latte (patch) | vm3d | ✅ | ✅ | ✅ | ⚠️ zaseknutý | — | 24 % | klienti sa už neodpájajú, ale es2gears „Not Responding“, čierne okná, artefakty |
| hyprland-latte (patch) | vm3d + render voľby¹ | ✅ | ✅ | ✅ | ✅ | **201** | 36 % | funguje; biele čiary na okrajoch okna kitty |

¹ `render { not_shown_fifo_lock = false; commit_timing_enabled = false; direct_scanout = 0 }`

FPS je orientačné, okná mali pri rôznych rozloženiach rôznu veľkosť. CPU je priemer procesu
kompozitora za celý beh (100 % = jedno jadro).

## Závery

1. **SAFE = labwc + pixman je overené.** Beží úplne bez GL a zobrazí aj GL aplikácie.
2. **NORMAL vo VM = Hyprland + swgl** (`MESA_LOADER_DRIVER_OVERRIDE=kms_swrast`, `LIBGL_ALWAYS_SOFTWARE=1`).
   Je stabilné. V pokoji berie kompozitor 0 % CPU, no pri animovanom obsahu (es2gears) ~1,3 jadra.
   Každý pohyb na obrazovke stojí CPU, preto budú efekty v stupni **Softvér** vypnuté.
3. **vm3d je iba experimentálna voľba.** Vyžaduje hyprland-latte a render voľby a aj tak má artefakty.
   Zodpovedá to varovaniu kernelu „unsupported hypervisor, likely broken“. Selektor ju
   predvolene nevyberie.
4. Patch `vmwgfx-dmabuf` je **potrebný, ale nie postačujúci**. Zaseknutie GL klientov odstráni
   **`render:commit_timing_enabled = false`** (overené po jednej voľbe: es2gears 178 FPS; samotné
   `not_shown_fifo_lock = false` ani `direct_scanout = 0` nepomôžu). Biele čiary na okraji okna kitty
   ostávajú aj tak. Pod swgl nie sú, takže ich spôsobuje kreslenie klienta cez SVGA3D, nie kompozitor.

## Noctalia v5 (shell) a Noctalia Greeter

23. 9. 2026 · `noctalia-git` 5.1.0 (61aa227), `noctalia-greeter-git` 1.5.0 z COPR `lionheartp/Hyprland`.
Test: `SHELL_CMD=noctalia ./probe.sh …`. CPU v pokoji je vzorka posledných 10 s behu
(100 % = jedno jadro). Pri „panel otvorený“ sa pred meraním zavolá `noctalia msg panel-open control-center`.

| Kompozitor / cesta | Stav | Kompozitor CPU pokoj | Kompozitor RSS | Noctalia CPU pokoj | Noctalia RSS |
|---|---|---|---|---|---|
| Hyprland swgl, bez shellu (základ) | — | 0 % | 240 MB | — | — |
| Hyprland swgl, **len lišta** | ✅ | 3 % | 264 MB | 0 % | 240 MB |
| Hyprland swgl, panel otvorený, **používateľ klikal** (živý test) | ⚠️ | 80 % | 267 MB | 4 % | 251 MB |
| Hyprland swgl, panel otvorený, **bez zásahu** | ✅ | 5 % | 340 MB | 0 % | 247 MB |
| labwc pixman (SAFE), **len lišta** | ✅ | 0 % | 59 MB | 0 % | 258 MB |
| labwc pixman (SAFE), **panel otvorený** | ✅ | 5 % | 63 MB | 5 % | 270 MB |
| labwc pixman, **Noctalia Greeter** | ✅ | 0 % | 50 MB | 0 % | 166 MB |

**Závery:**
1. **Noctalia v5 beží vo VM v NORMAL aj v SAFE**, bez Qt a bez úprav. Vzhľad je v oboch režimoch
   rovnaký a lišta v pokoji nestojí nič.
2. **Záťaž prichádza z interakcie, nie zo shellu.** Pri živom teste používateľ klikal (Caffeine) a hýbal
   myšou a kompozitor vtedy išiel na ~80 %. Bez zásahu má otvorený panel 5 %. Vo VM so softvérovým GL
   teda stojí CPU každá animácia (hover, prechody). Na reálnom HW s 3D akceleráciou to prevezme GPU.
   Tiene a animácie Hyprlandu nie sú príčina: ich vypnutie pri kliknutiach nepomohlo (132 %).
3. **Greeter**: prvý snímok za ~0,3 s (softvér), potom 0 % CPU. Výber relácie berie z
   `/usr/share/wayland-sessions` (teraz Hyprland, Hyprland uwsm), takže tam pribudnú
   „LatteOS“ a „LatteOS SAFE“. Bez greetd ukáže „Login service is unavailable“ (očakávané).
4. Pamäť: Noctalia ~250 MB RSS. Porovnanie s DMS a Caelestia ešte chýba.

## Porovnanie shellov: Noctalia v5 · DMS · Caelestia

23. 9. 2026, rovnaký test bez zásahu používateľa, 45 s. CPU = pokoj (posledných 10 s), RSS = súčet
celého stromu procesov shellu.

| Shell | Verzia | Procesy | Hyprland swgl: lišta | Hyprland swgl: panel otvorený | labwc pixman (SAFE): lišta | SAFE: panel | RSS shellu |
|---|---|---|---|---|---|---|---|
| **Noctalia v5** | 5.1.0 (alfa) | 1 (C++) | komp. 3 % · shell 0 % | komp. 5 % · shell 0 % | 0 % · 0 % | 0 % · 0 % ✅ | **240–270 MB** |
| **DMS** | 1.4.4 (Fedora) | 2 (Go + Quickshell) | 1 % · 0 % | 3 % · 0 % | 0 % · 0 % | 0 % · 0 % ✅ | 441–526 MB |
| **Caelestia** | 2.3.0 (COPR celestelove) | 2 (Quickshell) | 0 % · 0 % | **114 % · 97 %** (animovaný dashboard) | 0 % · 0 % | ❌ panel sa neotvorí, chýbajú plochy | 541–625 MB |

Poznámky:
- DMS a Caelestia sa **nedajú nainštalovať súčasne**: každý chce iný balík Quickshellu (`quickshell` vs `quickshell-git`).
  Caelestia navyše pevne vyžaduje `tuned-ppd` a ťahá vývojové balíky (`*-devel`, cmake, gcc).
- Caelestia je naviazaná na Hyprland: pod labwc ukáže lištu, ale IPC panely (`drawers`) a pracovné plochy nefungujú.
- DMS aj Caelestia pri prvom štarte otvoria uvítacie okno.
- Na reálnom HW s 3D akceleráciou sa rozdiely v CPU zmenšia, rozdiely v pamäti nie.

## Štart systému LatteOS (latte-boot, greetd, relácie)

23. 9. 2026 · `setup/f1/install-session.sh --enable`, testy `setup/f1/session-test.sh`.

| Test | Výsledok |
|---|---|
| `latte-boot select` (systemd, pred greetd) | NORMAL · sw-gl · softver, ~85 ms (2 EGL testy paralelne) |
| Relácia NORMAL (`latte-session`) | Hyprland + Noctalia; počítadlo 1 po štarte, 0 po 60 s |
| Skutočný pád (`SIGSEGV` Hyprlandu po 20 s) | relácia hneď prešla do SAFE, počítadlo 1 |
| 2. pád, 3. pokus | počítadlo 2 → tretí pokus ide rovno do SAFE, ďalší štart vyberie SAFE |
| Sirota `latte-boot ok` po páde | opravené: `ok` kontroluje, či rodič (kompozitor) ešte žije |
| Relácia SAFE | labwc + pixman + Noctalia + `latte-safe` |
| GRUB „SAFE — bez ovládača grafiky“ | naštartuje so simpledrm; `latte-boot` → SAFE (nomodeset) |
| Plymouth | logo šálky na espresso pozadí ✅ |
| greetd + tuigreet, prihlásenie „LatteOS“ | ✅ celý reťazec, boot 13,4 s, pamäť po prihlásení 1,7 GB |

### Nájdené a vyriešené problémy

1. **Noctalia Greeter pod greetd prepúšťa pamäť jadra.** Rast ~36 MB/s (`SUnreclaim`, `kmalloc-256`),
   bez interakcie; po ukončení sa pamäť nevráti. Po ~15 min to viedlo k OOM a zamrznutiu VM.
   labwc + pixman ani Hyprland (vm3d/swgl) pamäť neprepúšťajú. Riešenie: greeter = tuigreet,
   Noctalia Greeter vypnutý (`greeter = "tui"` v `/etc/latteos/boot.toml`). Príčinu treba nájsť vo F3.
2. **SELinux:** greeter (doména `xdm_t`) nesmel čítať `/run/latteos` (`var_run_t`) → vždy ponúkal SAFE.
   Riešenie: `semanage fcontext -a -t xdm_var_run_t '/run/latteos(/.*)?'`.
3. **`start-hyprland`** po páde reštartuje Hyprland bez `-c` (vygeneruje cudziu konfiguráciu) a zakryje
   pád. Riešenie: Hyprland priamo, strážca = `latte-session`.
4. **tuigreet ponúkal aj reláciu „Hyprland“ z COPR** (bez Noctalie). Riešenie: vlastný priečinok
   `/usr/share/latteos/sessions` s reláciami „LatteOS“ a „LatteOS SAFE“.
5. **Testy na VT3:** natvrdo ukončený kompozitor nechá VT v grafickom režime s vypnutou klávesnicou
   (vyzerá ako zamrznutie). vm3d test pri `nomodeset` zablokoval `seatd` v jadre (stav D). Poučenie:
   testovať cez skutočný štart, vm3d iba so zavedeným `vmwgfx`.

Poznámka: Hyprland berie preferovaný režim výstupu od VirtualBoxu (veľkosť okna VM), napr. 706×507.
