# Patche nad upstreamom

## vmwgfx dmabuf — patch proti čiernej obrazovke vo VM

| Súbor | Cieľ | Overené |
|---|---|---|
| `hyprland-0.56.2-vmwgfx-dmabuf.patch` | Hyprland `src/protocols/LinuxDMABUF.cpp` | `git apply --check` na tagu **v0.56.2**, teda na verzii balíka v COPR `lionheartp/Hyprland` |
| `hyprland-main-vmwgfx-dmabuf.patch` | to isté, vetva `main` | `git apply --check` na `23118f9f7f24` (= `hyprland-git` v COPR); `LOGM` → `LOG` |
| `wlroots-vmwgfx-dmabuf.patch` | wlroots `types/wlr_linux_dmabuf_v1.c` (labwc, SAFE režim) | `git apply --check` na 0.21-dev (`297e01d2d4a7`) |

**Autor:** Pascal-0x90, [hyprwm/Hyprland diskusia #12966](https://github.com/hyprwm/Hyprland/discussions/12966) (31. 8. 2026).
Do upstreamu zatiaľ nie je začlenený. Pôvodný balík opráv
`ClaireDuSoleil/hyprland-vmware-fix` už neexistuje (404).

**Príznak:** Hyprland štartuje, ale ukáže čiernu plochu, prípadne len kurzor. GPU klienti (kitty,
alacritty, Quickshell, tapeta) padnú na prvom snímku s chybou
`invalid arguments for wl_surface.attach`.

**Príčina:** kernelový ovládač `vmwgfx` pri importe dmabuf-u (`vmw_prime_fd_to_handle`) vráti
**TTM** handle namiesto GEM handle. Kompozitor ho potom nevie zavrieť cez `drmCloseBufferHandle`
(EINVAL) a klienta odpojí.

**Oprava:** ak `drmCloseBufferHandle` zlyhá a zariadenie je `vmwgfx`, handle sa uvoľní cez
`DRM_VMW_UNREF_SURFACE`. Na iných ovládačoch sa správanie nemení.

**Týka sa aj VirtualBoxu:** grafický adaptér VMSVGA sa v hosťovi hlási ako `VMware SVGA II
[15ad:0405]` a používa rovnaký ovládač `vmwgfx`. Overené na `latteOSdev`.
Chyba sa prejaví iba pri **zapnutej 3D akcelerácii**. Bez nej Mesa nepoužije ovládač `svga`
a klienti kreslia cez llvmpipe a zdieľanú pamäť.

Doplnkové nastavenia pre VM (nie sú súčasťou patchu, pozri ROADMAP F1):
`cursor { no_hardware_cursors = true }` a pri problémoch `LIBGL_ALWAYS_SOFTWARE=1` pre klientov.

## noctalia-bar-blur-capsules.patch (29. 9. 2026, latte-lab)

Noctalia (5.2, 9287a78) žiada kompozitor (ext-background-effect) o rozmazanie **celého obdĺžnika lišty**,
aj keď je lišta priehľadná (`background_opacity = 0`) a vidieť iba ostrovy → po celej šírke mliečny pás.
Záplata: pri priehľadnej lište rozmaže iba zaoblené obdĺžniky kapsúl a prepočíta ich po každom rozložení.
Vhodná na upstream PR. Použitie: `git apply` v zdroji Noctalie (alebo forku latte-shell), potom
`LATTE_SHELL_SRC=<zdroj> setup/f1/build-latte-shell.sh`.

## pleamar-hyprland-okna-8bit.patch (29. 9. 2026, latte-lab, pleamar 5f9cd54)

Dve opravy pre Kvapky, obe vhodné na upstream:
1. **Zoznam okien na Hyprlande.** Služba `window` cez socket Hyprlandu hlási iba aktívne okno (bez `list`) a príkazy
   `window.*` nepozná. `PLEAMAR_GENERIC=1` to obišlo, no vypne aj `cursor.x/y` (myš mimo scény). Záplata:
   `PLEAMAR_GENERIC=window` (zoznam oddelený čiarkami) pošle cez všeobecné protokoly (wlr-foreign-toplevel) iba to,
   čo menuje; kurzor ostáva z Hyprlandu. `=1` sa správa ako doteraz.
2. **Farby o tón svetlejšie.** RADV ponúka ako prvý nesRGB formát `Rgba16Float`; Hyprland ho berie ako lineárne
   svetlo a zakóduje ešte raz → káva #1c0f09 vyšla ako #5c4333. Záplata uprednostní `Bgra8Unorm`/`Rgba8Unorm`.

3. **Ťahanie aj pravým tlačidlom.** pleamar začína ťahanie (`on drag`) iba ľavým; lišta-kvapka sa má dať presunúť
   ľavým aj pravým (ako panel úloh). Záplata: pravé tlačidlo nad zónou začne to isté ťahanie a jeho pustenie ho
   ukončí (`on release`); `on press right` ostáva, takže scéna rozlíši ľavý klik od pravého.

4. **Ikony podľa mena.** pleamar hľadal iba v `/usr/share/icons` a v domove, bez `XDG_DATA_DIRS` (ikony Flatpaku),
   bez rozloženia Breeze (`apps/48/…`) a bez AdwaitaLegacy → `system-file-manager`, `org.mozilla.firefox` sa
   nenačítali. Záplata: všetky `…/icons` z `XDG_DATA_DIRS`, téma z `PLEAMAR_ICON_THEME`/`QS_ICON_THEME` ako prvá,
   veľkosti oboch zápisov (48x48 aj 48) a kontext `legacy`.

5. **Viac odberateľov služby okien.** `window` (a `workspaces`) cez wlr-foreign-toplevel mala jediné miesto pre
   odberateľa: `service window` v scéne a `sys.watch("window")` v jej logike sú dvaja, druhý prvého vytlačil a scéna
   ostala so starým zoznamom — v lište guľôčky okien, ktoré už neexistovali (nedali sa kliknúť ani zavrieť).
   Záplata: zoznam odberateľov, zmenu dostanú všetci.

Použitie: `git apply` v `resources/upstream/pleamar`, potom `cargo build --release`.

## pleamar-wm-linearny-buffer.patch (pôvodná Marea, setup/lab/marea-povodna.sh)

pleamar-wm (k4ditano) žiada obrazový buffer iba s modifiermi. Na latte-lab (RX 640, GFX8) to radeonsi nevie
(`the card did not make a buffer of 1920×1080: No such file or directory`), obrazovka ostala čierna s textom
terminálu. Záplata: keď alokácia s modifiermi zlyhá, lineárny buffer (Vulkan ho preberá ako modifier 0) — ako
„modifier-less allocation“ v aquamarine (Hyprland). Kandidát na hlásenie autorovi (iba ak to používateľ chce).

## pleamar-linearny-dmabuf.patch (pôvodná Marea, setup/lab/marea-povodna.sh)

Druhá polovica toho istého problému (6. 10. 2026): lineárny buffer z predošlej záplaty pleamar-wm odovzdá Vulkanu cez
`Gpu::import_dmabuf`, a ten cez wgpu vyžaduje `VK_EXT_image_drm_format_modifier`. RADV na Polaris (RX 640) ho nemá —
import skončil chybou `Unexpected` (`session · DP-3: Unexpected`) a monitory ostali na texte terminálu
(„pleamar-wm · its log: …“). Záplata: bez toho rozšírenia a s modifierom 0 sa buffer prevezme ako obraz s lineárnym
uložením (`VK_EXT_external_memory_dma_buf`), iba ak ovládač ukladá riadky rovnako ako buffer. Platí pre kópiu pleamaru
v `~/.local/share/marea-povodna` (LatteOS `/usr/bin/pleamar` ju nepotrebuje — kreslí ako klient). Okná programov
na tejto karte ďalej idú cez zdieľanú pamäť (pomalšie). Kandidát na hlásenie autorovi (iba ak to používateľ chce).

## Základ (30. 9. 2026)

Záplaty 1–5 (`pleamar-hyprland-okna-8bit.patch`) sú na **pleamar 0.2.3** (upstream 0728337, jazyk 0.2,
spätne číta 0.1). Prechod z 5f9cd54 (0.1.0) bez konfliktov. Nové zmeny u autora: `latte-upstream`.

**1. 10. 2026: pleamar v0.2.6** (`8bb920f`), pleamar-wm v0.2.5 (`c213f55`), marea-plm `a589189`: obe záplaty
(`pleamar-hyprland-okna-8bit.patch`, `pleamar-wm-linearny-buffer.patch`) sedia bez úprav (`git apply --check`),
pleamar so záplatou sa preloží. Scéna Kvapky aj engine Goo prejdú `pleamar --check` (jazyk 0.2 číta aj 0.1).
Verzie sú pripnuté v `resources/fetch.sh`; `install-session.sh` preloží pleamar znova, keď sa verzia líši.

**6. 10. 2026: pleamar v0.2.24** (`0efbcd9`, 70 zmien od v0.2.6). `pleamar-prazdne-tvary`, `pleamar-ostre-okraje`,
`pleamar-pasy-tela` a `pleamar-linearny-dmabuf` sedia bez úprav. `pleamar-hyprland-okna-8bit.patch` je nanovo
vytvorená proti v0.2.24: autor medzitým pridal službu náhľadov na to isté miesto (`platform/mod.rs`), a časť 3
(ťahanie aj pravým tlačidlom) je **vypustená** — slúžila lište pôvodnej plochy Kvapky, engine Goo ťahá iba ľavým
a pravé tlačidlo má pre akcie. Scény enginu, prihlásenia, zámku aj pôvodná scéna Kvapky prejdú `pleamar --check`;
záťaž enginu na latte-lab rovnaká ako na v0.2.6 (CPU 43 % jadra, GPU 53 % so zapnutým pásom výkonu), pamäť nižšia
(150 MB oproti 174 MB).

Pôvodná Marea (`setup/lab/marea-povodna.sh`, 6. 10.): pleamar 0.2.24, **pleamar-wm 0.2.25**, marea-plm `6cfd438` —
`pleamar-wm-linearny-buffer` aj `pleamar-linearny-dmabuf` sedia bez úprav; na latte-lab relácia s pleamar-wm kreslí
na oba monitory (prihlásenie do nej cez goo výberu relácie overené).

## noctalia-rohova-lista.patch (Noctalia pre plochu Kvapky, setup/lab/noctalia-kvapky.sh)

Rohová lišta Noctalie vpravo dole (1. 10. 2026): k súmernému `margin_ends` voliteľné `margin_start` a `margin_end`
(začiatok = vľavo/hore, koniec = vpravo/dole). Lišta s jedným koncom pri stene a druhým odsadeným má zmiešané
vyduté rohy: koniec pri stene sa vyduje do bočnej steny (ako lišta cez celú dĺžku), odsadený koniec sa rozleje po
spodnom okraji (ako odsadená lišta) — goo v rohu. Bez týchto kľúčov sa Noctalia správa ako pôvodná. Preložená
zvlášť do /usr/lib64/latteos/noctalia-kvapky/noctalia, pôvodná /usr/bin/noctalia ostáva nedotknutá.


## pleamar-prazdne-tvary.patch (1. 10. 2026, engine Goo, pleamar 0.2.6)

Tvar s nulovou veľkosťou (elipsa s polomerom pod štvrť pixela, čiara s nulovou hrúbkou) sa do tela goo nedá.
Pleamar to už robil pre obdĺžniky („pod pol pixela neexistuje“), elipsy a čiary počítal ďalej. Teleso počíta
každý svoj tvar pre každý pixel a `show: false` tvar z tela nevyradí. Engine Goo má 64 miest, prázdne majú
nulovú veľkosť. Merané v cloude (llvmpipe, 1280×720): 192 skrytých tvarov **102 ms → 18 ms** na snímku
(rovnako ako bez nich), celý engine **192 ms → 21,6 ms**. **Pomáha aj súčasnej ploche Kvapky: 62 → 24 ms** (aj ona má v tele skryté tvary). Zároveň zmizne hrbček,
ktorý bod nulovej veľkosti cez zliatie vydul. Vhodná na upstream. Bez nej engine funguje, iba pomalšie (prázdne
miesta ležia pod obrazovkou, aby hrbček nebolo vidieť).

## pleamar-ostre-okraje.patch (1. 10. 2026, oká medzi kvapkami, pleamar 0.2.6)

Telo goo vyhladzuje hranu pevnou šírkou (0,75 px), ako keby sa vzdialenosť od okraja menila všade o pixel na pixel.
V zliatí (smooth min) je však stlačená: mení sa pomalšie, a hrana sa rozmaže na niekoľko pixelov. Najviac to vidno
na **okách** medzi zliatymi kvapkami (Hodiny ↔ vypínač), ktoré mali rozmazaný okraj; používateľ chce ostrú čiaru
ohraničenia. Záplata vydelí vzdialenosť jej skutočnou zmenou na pixel (`dpdx`/`dpdy`, už sa počítali pre sklo) pred
vyhladením výplne, okraja (`border`), lemu a tieňa pod sklom. Hrana sa tak môže iba zostriť (najviac 5×), nikdy
rozmazať. Overené v cloude na súčasnej scéne Kvapky (zväčšené oko: rozmazaný prstenec → tenká ostrá čiara).
Vhodná na upstream.

## pleamar-pasy-tela.patch (5. 10. 2026, engine Goo na latte-lab, pleamar 0.2.6)

Telo goo je jeden obdĺžnik (hranice všetkých jeho tvarov) a shader pre **každý jeho pixel počíta každý tvar tela**
(pri tieni dvakrát). Lišta s 17 kvapkami má 85 tvarov cez celú šírku obrazovky, hoci na pixel majú vplyv iba tie
v okolí. Na RX 640 (dva monitory) preto engine v pokoji zaťažil GPU na 70–77 % (pôvodné Kvapky 37 %, plocha bez
kvapiek 21–27 %) a každá ďalšia kvapka pridala ~3 %.
Záplata (`src/gpu.rs`, `strips`): telo s 8 a viac tvarmi širšie než 288 px sa nakreslí po zvislých pásoch (96 px)
a každý pás dostane iba tvary, ktoré naň dosiahnu (hranice tvaru + najväčšie zliatie + dosah tieňa). Obraz je
rovnaký: zliatie (`smooth_min`) je za hranicou zliatia obyčajné `min`, vzdialený tvar ho nezmení. Overené statickou
scénou so 41 tvarmi — **0 odlišných pixelov** oproti pleamaru bez záplaty. Telá so sklom (sleduje celú siluetu),
s transformáciou a malé telá ostávajú ako boli.
Merané na latte-lab (RX 640, 2560×1080 + 1920×1080, v pokoji): engine 17 kvapiek **70 % → 35 %** GPU, engine
5 kvapiek 43 % → 33 %, Kvapky 37 % → 36 %. Nahrádza „ostrovy“ navrhnuté v cloude (netreba meniť scénu).
Sedí aj na pleamar 0.2.17. Vhodná na upstream. Bez nej engine funguje, iba s vyššou záťažou GPU.
