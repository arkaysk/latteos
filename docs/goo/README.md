# LatteOS Goo — Začni tu

**LatteOS GOO** (jediná edícia LatteOS; Classic je od 5. 10. 2026 zrušený) je plocha s tekutými kávovými kvapkami pri okraji obrazovky (predvolene dole). Je inšpirovaná Windows 11 a fyzikou tekutiny.

## Čo to je v 30 sekundách

- **Lišta:** kvapky na okraji — GooBar s oknami, LensGoo (spúšťač), GooPower (vypínač a účet), ClockGoo (čas,
  upozornenia a kalendár), QueenGoo (App Manager a Správca zariadení)
- **Fyzika:** pružia sa, lepia na okraj, spájajú sa navzájom, reagujú na kurzor
- **Vstupy:** myš (všetko sa dá ovládať: klik, pravý, koliesko, ťahanie); každá kvapka má funkciu na ľavom aj
  pravom tlačidle, koliesko mení veľkosť (LATTEOS-GOO.md §4)
- **Efekty:** vietor, vlnky na hladine (aj pri minimalizácii okna), hra pri nečinnosti

## Čo s tým robím

### Iba chcem používať
→ [Setup/inštalácia](../../setup/lab/README.md)

### Chcem porozumieť pravidlám
→ [22 pravidiel plochy](PRAVIDLA.md) — všetko, čo sa smie a čo nie

### Chcem zmeniť alebo pridať kvapku
→ Najprv: [Pravidlá](PRAVIDLA.md) (§2 a §3)
→ Potom: [Engine API](../../session/goo/README.md)

### Som programátor a resetla sa session
→ LATTEOS-GOO.md (čo platí), denník rozhodnutí, plán v ROADMAP.md (F3·G)
→ história a merania: docs_zaloha/

---

## Prehľad

| Dokument | Čo v ňom je |
|----------|------------|
| [PRAVIDLA.md](PRAVIDLA.md) | 22 zásad správania kvapiek, fyzika, nečinnosť |
| [ROZHRANIE.md](ROZHRANIE.md) | Jednotlivé kvapky a ich kliky (GooBar, GooPower, LensGoo, QueenGoo, ClockGoo, ChatGoo) |
| [session/goo/README.md](../../session/goo/README.md) | Ako programovať: API, háčiky, príklady |
| ROZHODNUTIA.md | Denník rozhodnutí s dátumami a zamietnuté nápady |
| docs_zaloha/ | Archív: odovzdávka enginu k 5. 10. s meraniami, záznam z cloudu, staré varianty |

---

## Rýchly start

**Prvý deň:**
1. Prečítaj [Pravidlá](PRAVIDLA.md) — stránka 1 (§1–2)
2. Pozri sa na [Rozhranie](ROZHRANIE.md) — ako vyzerajú jednotlivé kvapky

**Keď chceš zmeniť kvapku:**
1. Skontroluj, či zmena porušuje [Pravidlá](PRAVIDLA.md) §2
2. Pozri sa na [API enginu](../../session/goo/README.md) — ako sa to programuje
3. Zmeniť kvapku `moja-kvapka.json`:
   ```bash
   latte-goo novy "Moja kvapka"  # vytvorí súbor
   # [uprav súbor]
   latte-goo skontroluj          # skontroluj
   ```

**Keď padne session:**
1. Prečítaj [ROZHRANIE.md](ROZHRANIE.md) (čo je hotové a čo chýba) a ROADMAP F3·G
2. Zafixuj to, čo treba opraviť
3. Oprav platný stav (ROZHRANIE.md, LATTEOS-GOO.md), rozhodnutie zapíš do ROZHODNUTIA.md + commit

---

## Architektúra

```
session/goo/
├── goo.plm                 ← Scéna (fyzika, kresba, vstupy)
├── goo.luau                ← Vstupný bod (init)
├── gen.py                  ← Generátor (rozpíše cykly)
│
├── lib/
│   ├── engine.luau         ← API: register, pravidlá, karta Goo, nečinnosť
│   ├── goobar.luau         ← Okná a ich správa
│   ├── spustac.luau        ← Spúšťač a rýchly zoznam LensGoo
│   ├── cas.luau            ← Stopky, minútka, budíky (ClockGoo)
│   └── pouzivatel.luau     ← JSON kvapky
│
├── kvapky/
│   ├── goobar.luau         ← GooBar (hlava + okná)
│   ├── goopower.luau       ← Karta GooPower, pás výkonu
│   ├── lensgoo.luau        ← Lupa: spúšťač, rýchly zoznam
│   ├── queengoo.luau       ← Kráľovná (App Manager, Device Manager)
│   ├── clockgoo.luau       ← Čas, upozornenia, kalendár
│   └── ukážky (počítadlo, hodiny, lepkavá, ťažká…)
│
├── priklady/
│   ├── kalkulacka.json     ← Príklad: JSON kvapka
│   └── system.json         ← Príklad: monitoring
│
└── README.md               ← Technické detaily
```

---

## Licencie

- **pleamar** (scéna, kresba) — BSD-3-Clause, od k4ditano (Marea)
- **LatteOS Goo** — vlastný obsah
- **Hyprland** — LGPL

Pred vydaním sa požiada povolenie všetkých strán.

---

## Prvé kroky

```bash
# Klonovať repo
git clone https://github.com/arkaysk/jihlavanka001
cd jihlavanka001
git checkout main

# Inštalácia
sudo setup/f0-install.sh        # VM: balíky
setup/f1/install-session.sh     # relácie

# Po zmene
git add .
git commit -m "goo: zmena"
git push -u origin main

# Aktualizovať dokumentáciu
# platné: LATTEOS-GOO.md, docs/goo/ROZHRANIE.md · rozhodnutia: docs/goo/ROZHODNUTIA.md · plán: ROADMAP.md
```

---

**Ďalej:** [Pravidlá plochy](PRAVIDLA.md)
