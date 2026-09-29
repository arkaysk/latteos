# LatteOS

Desktopové prostredie pre Linux s teplým „kávovým“ vzhľadom. Stojí na Fedore, kompozitore Hyprland
a shelli [Noctalia](https://github.com/noctalia-dev/noctalia-shell) (vlastný fork), s vlastnými
aplikáciami (Súbory, Nastavenia, Monitor, Aplikácie, Herňa) a bezpečným štartom:
keď grafika nefunguje, naštartuje jednoduchý režim **SAFE** namiesto čiernej obrazovky.

> **Stav: skorý vývoj.** Systém sa mení každý deň, konfigurácia nie je stabilná a veci sa môžu pokaziť.
> Inštaluj iba na testovací počítač alebo do virtuálneho stroja, nie na počítač, na ktorom pracuješ.

## Čo potrebuješ

- **Fedora 44 Server** (klasická, nie Atomic), čistá inštalácia.
- Grafika: **AMD** (Mesa, overené na RX 550/640) alebo virtuálny stroj bez 3D akcelerácie
  (softvérové vykresľovanie). NVIDIA zatiaľ nie je overená.
- Aspoň 4 GB RAM, ~20 GB miesta, internet.

## Inštalácia

Reálny počítač — celý postup (BIOS, disk, sieť, vzdialený prístup) je v
[setup/lab/README.md](setup/lab/README.md). Po inštalácii Fedory stačí:

```
sudo dnf -y install git
git clone https://github.com/arkaysk/latteos && cd latteos
setup/lab/install.sh            # všetko okrem grafického štartu
setup/lab/install.sh --enable   # keď kontrola na konci vyjde: zapne prihlasovaciu obrazovku LatteOS
```

Pred zmenami sa urobí snímka Btrfs, takže systémové súbory sa dajú vrátiť (`snapper`).
Virtuálny stroj: `sudo setup/f0-install.sh` a potom `setup/f1/install-session.sh --enable`.

## Režimy NORMAL a SAFE

Pri každom štarte `latte-boot` zistí grafiku a vyberie režim:

| Režim | Kedy | Čo beží |
|---|---|---|
| NORMAL | funguje OpenGL ES 3 (grafická karta alebo softvérovo) | Hyprland + plný shell s efektmi |
| SAFE | grafika nefunguje, alebo relácia dvakrát za sebou spadla | labwc bez efektov + záchranná ponuka |

V GRUB-e sú vždy položky **LatteOS SAFE** (aj „bez ovládača grafiky“) na ručnú záchranu.
Stav zistíš príkazom `latte-boot status`.

## Štruktúra

| Priečinok | Obsah |
|---|---|
| `crates/` | Rust: `latte-hw` (zistenie grafiky), `latte-boot` (výber režimu, počítadlo pádov) |
| `session/` | relácia, greeter, konfigurácia Hyprlandu a labwc, pluginy shellu, aplikácie, témy — [prehľad](session/README.md) |
| `setup/` | inštalačné skripty a testy |
| `resources/` | naše záplaty cudzích projektov, `fetch.sh` stiahne ich zdroje |
| `bughunt/` | snímky a podklady k nájdeným chybám |

## Chyby a príspevky

Našiel si chybu? Otvor [Issue](https://github.com/arkaysk/latteos/issues) a pripoj:
`latte-boot status`, `journalctl -b -e` a čo si robil. Snímky obrazovky pomáhajú.
Pull requesty sú vítané, najlepšie malé a s popisom, na čom si to vyskúšal.

## Licencia

Licencia projektu ešte nie je stanovená. Súčasti tretích strán majú vlastné licencie
(napr. písma Manrope a Fraunces: SIL OFL, `session/fonts/`).
