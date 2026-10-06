# LatteOS — Architektúra

Princípy a vrstvy systému LatteOS.

## Základné princípy

1. **Linux first** — Hyprland, Wayland, štandardné protokoly (GSettings, XDG, portály)
2. **Myš prvá** — Všetko sa dá ovládať myšou (ľavé, pravé, koliesko); klávesy sú doplnok
3. **Preberať, nevymýšľať** — Existujúce riešenia (Noctalia, pleamar) sa integrujú, nie vytvárajú znova
4. **Jedno miesto pravdy** — Každá vlastnosť má jeden zdroj (režim štartu `/run/latteos/mode.toml`, téma `latte-theme`, kvapky `~/.config/latteos/kvapky.json`…)

## Vrstvy architektúry

### Vrstva 1: Boot a detekcia HW

```
crates/latte-boot
├── detekcia grafiky (GPU, renderer)
└── výber režimu (NORMAL / SAFE)

crates/latte-hw
├── CPU (x86-64 generácia, takty, cache)
├── RAM, swap, disky (vrátane LVM/LUKS)
└── GPU, UEFI, Secure Boot
```

**Proces:**
1. GRUB zavedie kernel; služba `latte-boot.service` (pred greetd) spustí `latte-boot select`
2. `latte-boot` zistí grafiku (ovládač, EGL, GLES 3) a počítadlo pádov
3. Vyberie režim a zapíše `/run/latteos/mode.toml`:
   - **NORMAL** — OpenGL ES 3 funguje → Hyprland + efekty (renderer `hw`, vo VM `sw-gl` alebo `vm-3d`)
   - **SAFE** — grafika nefunguje alebo relácia 2× za sebou spadla → labwc + pixman bez efektov + záchrana

### Vrstva 2: Relácia (Session)

```
session/bin/latte-session
├── výber relácie (LatteOS Kvapky, Kvapky – engine test, SAFE, Hra; pokusy: Noctalia čistá, Marea; Classic zrušený)
├── profily prostredí (oddelené konfigurácie)
└── systemd user jednotky

session/bin/latte-greeter
└── prihlasovacia obrazovka s výberom
```

**Konfigurácie:**
- `session/hypr/` — Hyprland (režimy okien, animácie)
- `session/noctalia/` — Noctalia (corner bar, widgets)
- `session/wayland-sessions/` — .desktop súbory

### Vrstva 3: Shell (Rozhranie)

#### LatteOS Classic (zrušený 5. 10. 2026 — kód ostáva, kým ho GOO nenahradí)
```
Noctalia (panel Noctalie) + Hyprland
├── Lišta dole so widgetmi
├── Control center a panely
├── OSD a notifikácie
└── Aplikácie LatteOS (Quickshell, QML)
```

#### LatteOS Goo
```
pleamar engine (scéna goo.plm + logika Luau)
├── Tekuté kvapky (128 miest)
├── Fyzika: kurzor, nadnesenie, susedia, vietor, vlnky
├── Vstupy: myš (všetky tlačidlá, koliesko, ťahanie)
├── Kvapky: GooBar (okná), GooPower, LensGoo (jadro); QueenGoo, ClockGoo, ChatGoo (voliteľné); vlastné
├── Noctalia (rohová lišta s widgetmi)
└── Hyprland (okná aplikácií)
```
Pôvodná scéna plochy Kvapky (`session/kvapky/kvapka.plm`, staré mená TimeGoo, PowerGoo, DaNoGoo) sa už nenasadzuje.

**Goo v detaile:**
- Scéna: `session/goo/goo.plm` (fyzika, vstupy, kresba, karta Goo, pás výkonu)
- Logika: `session/goo/lib/engine.luau` (API, register, pravidlá); `lib/goobar.luau`, `lib/spustac.luau`, `lib/cas.luau`
- Kvapky: `session/goo/kvapky/*.luau` (goobar, goopower, lensgoo, queengoo, clockgoo + ukážky)
- Generátor: `session/goo/gen.py` (rozpíše telo goo, ktoré jazyk nemá v cykloch)
- Pomocníci: `session/bin/latte-goo` (kvapky, polohy, účet, kalendár, počasie…), `latte-sysmon goo` (pás výkonu)

### Vrstva 4: Aplikácie

```
session/apps/
├── App Manager (inštalácia programov, Flatpak + RPM, aktualizácie)
├── Nastavenia (vzhľad, HW, sieť, AI, Kvapky…)
├── Monitor (procesy, senzory, autorun, výkon)
├── Device Manager (zariadenia, ovládače, siete, obrazovky)
├── Súbory (s archívmi ako priečinkami)
└── iné (Heidelberg, Barista…) — zoznam v session/README.md
```

**Technológia:**
- Quickshell (QML) — GUI, spúšťa `latte-app <meno>`
- D-Bus — komunikácia so systémom
- systemd — služby, úlohy na pozadí

## Ako všetko komunikuje

```
Hyprland (WM)
    ↓ (Wayland)
 pleamar engine ↔ Hyprland ↔ Aplikácie (Hyprland okná)
    ↓                           ↓
  Goo                    Noctalia control center
  (kvapky, vstupy)       (panely, widgets)
    ↓
 latte-kvapky, latte-goo (CLI)
    ↓
 systemd user, D-Bus, skript
```

## Súborová štruktúra

```
.
├── crates/              ← Rust: hw detekcia, boot
├── session/             ← Relácie a shell
│   ├── bin/             ← Úkony (latte-session, latte-goo…)
│   ├── hypr/            ← Hyprland config (Lua)
│   ├── goo/             ← Engine Goo (scéna + logika)
│   ├── kvapky/          ← Pôvodná plocha Kvapky (už sa nenasadzuje)
│   ├── apps/            ← Aplikácie (Quickshell)
│   ├── noctalia/        ← Noctalia integrácia
│   └── wayland-sessions/← .desktop súbory
├── setup/               ← Inštalácia
│   ├── f0-install.sh    ← VM, balíky
│   ├── f1/              ← Relácie, testy
│   └── lab/             ← Reálny PC
├── resources/           ← Upstream zdroje
│   ├── patches/         ← Naše záplaty
│   └── fetch.sh         ← Sťahovanie
├── docs/                ← Táto dokumentácia
├── old/                 ← Predchádzajúca verzia (len čítanie)
└── docs_zaloha/         ← Archív: staré dokumenty, reporty a merania s dátumom
```

## Režimy a varianty

### Relácia (`latte-session [safe|hra|noctalia|klasicke]`)
```
bez argumentu   → LATTE_VARIANT=kvapky     LatteOS GOO: engine Goo (LATTE_KVAPKY_SCENE = session/goo/goo.plm)
noctalia        → LATTE_VARIANT=noctalia   čistá Noctalia na pokusy
safe, hra       → núdzová relácia, herná relácia (nie sú v ponuke prihlásenia)
klasicke        → LATTE_VARIANT=klasicke   LatteOS Classic (zrušený, kód ostáva, v ponuke nie je)
```
Ponuka prihlásenia (6. 10. 2026): **LatteOS GOO**, **Marea**, **Noctalia (čistá)**, **Serpantinum**. Prvé dve položky
LatteOS inštaluje `setup/f1/install-session.sh`, Mareu `setup/lab/marea-povodna.sh`, Serpantinum
`setup/lab/serpantinum.sh`. SAFE príde sám (pády, GRUB › LatteOS SAFE), do hry sa prepína z plochy (`latte-hra`).
Pôvodná plocha Kvapky (`session/kvapky/kvapka.plm`) sa nenasadzuje; staré mená `kvapky` a `kvapky-engine` znamenajú GOO.

### Štart (`latte-boot select` → `/run/latteos/mode.toml`)
```
mode = normal   renderer hw (grafická karta) · sw-gl (llvmpipe) · vm-3d (VMSVGA)   Hyprland + efekty podľa stupňa
mode = safe     renderer pixman                                                     labwc bez efektov + záchrana
```

## Čas vývoja

Podľa ROADMAP.md:

| Fáza | Popis | Stav |
|------|-------|------|
| F0 | základ VM bez GPU, softvérové vykresľovanie | ✅ |
| F1 | grafický stack a režimy NORMAL / SAFE | ✅ |
| F2 | Hyprland Lua modul LatteOS | ✅ základ |
| F3 | shell; **F3·G** plocha Kvapky a engine Goo (hlavná práca) | 🔸 |
| F4–F8 | systémové služby, stabilita, bezpečnosť, AI a Text Bar, herná vrstva | 🔸 |
| H | reálny hardvér (latte-lab s AMD; NVIDIA neoverená) | 🔸 |
| O | optimalizácia (trvalá priorita) | 🔸 |
| A | Fedora Atomic — až keď bude všetko hotové | ⬜ |

---

## Ďalej

- [LatteOS Goo — Pravidlá](goo/PRAVIDLA.md)
- [Engine Goo — API](../session/goo/README.md)
- [Setup — Inštalácia](../setup/lab/README.md)
