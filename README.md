# LatteOS GOO

Plocha pre Linux, v ktorej lištu, Štart, hodiny a systémové prvky nahrádzajú **tekuté kávové kvapky**.
Kvapky pružia, lepia sa k okraju obrazovky aj k sebe, naťahujú sa a reagujú na kurzor. Ovládanie je
postavené pre ľudí zvyknutých na Windows 11: všetko ide myšou, klávesové skratky sú doplnok.

> **Stav: skorý vývoj.** Systém sa mení každý deň, nastavenia nie sú stabilné a veci sa môžu pokaziť.
> Inštaluj iba na testovací počítač, nie na počítač, na ktorom pracuješ.

## Čo na ploche nájdeš

| Kvapka | Ľavý klik | Pravý klik |
|---|---|---|
| **GooBar** — lišta s oknami | hlava: ďalší režim okien · ikra: prepnúť alebo minimalizovať okno | hlava: ukázať plochu · ikra: ponuka okna |
| **GooPower** — účet a napájanie | karta účtu, napájania a výkonu | pás výkonu (CPU, RAM, GPU) |
| **LensGoo** — spúšťač (aj kláves Win) | aplikácie, súbory, web, terminál, AI | rýchly zoznam aplikácií |
| **ClockGoo** — čas | upozornenia a kalendár | čas, stopky, budíky, počasie |
| **QueenGoo** — správa systému | App Manager s obchodom | Správca zariadení |
| **ChatGoo** — doplnok pre Beeper | ukázať alebo schovať Beeper | správy |

GooBar, GooPower a LensGoo sú na ploche vždy; ostatné kvapky sa dajú vypnúť v Nastaveniach › Kvapky.
Kvapky sa dajú ťahať myšou a kolieskom zväčšovať. Bez myši: **Win** otvorí spúšťač, **Win+T** zapne výber
kvapiek šípkami, **Win+L** zamkne obrazovku.

K ploche patria vlastné aplikácie (Súbory, Nastavenia, Monitor, App Manager, Správca zariadení),
prihlasovacia obrazovka a zámok v rovnakom štýle.

## Čo potrebuješ

- **Fedora 44 Server** (klasická, nie Atomic), čistá inštalácia.
- Grafickú kartu **AMD** (Mesa; overené na RX 550 a RX 640). NVIDIA a virtuálny stroj nie sú s plochou Goo overené.
- Aspoň 4 GB RAM, ~20 GB miesta, internet.

## Inštalácia

Celý postup pre reálny počítač (BIOS, disk, sieť, vzdialený prístup) je v
[setup/lab/README.md](setup/lab/README.md). Po inštalácii Fedory stačí:

```
sudo dnf -y install git
git clone https://github.com/arkaysk/latteos && cd latteos
setup/lab/install.sh            # všetko okrem grafického štartu
setup/lab/install.sh --enable   # keď kontrola na konci vyjde: zapne prihlasovaciu obrazovku LatteOS
```

Pred zmenami sa urobí snímka Btrfs, takže systémové súbory sa dajú vrátiť (`snapper`).
Na prihlasovacej obrazovke vyber reláciu **LatteOS GOO**.

Konkrétnu verziu nainštaluješ jej značkou, napríklad `git checkout v0.3.0` pred spustením inštalátora.

## Bezpečný štart

Pri každom štarte `latte-boot` zistí grafiku a vyberie režim:

| Režim | Kedy | Čo beží |
|---|---|---|
| NORMAL | grafika funguje | plocha LatteOS GOO |
| SAFE | grafika nefunguje, alebo relácia dvakrát za sebou spadla | jednoduchá plocha bez efektov so záchrannou ponukou |

V GRUB-e sú vždy položky **LatteOS SAFE** na ručnú záchranu. Stav zistíš príkazom `latte-boot status`.

## Verzie

Každé zverejnenie má vlastnú verziu a značku `vX.Y.Z`; čo sa zmenilo, je v [ZMENY.md](ZMENY.md).
Vývoj prebieha inde a sem sa presúva po fázach, preto je tu jeden commit na vydanie.

## Štruktúra

| Priečinok | Obsah |
|---|---|
| `session/goo/` | engine Goo: scéna plochy, kvapky a ich logika — [ako napísať vlastnú kvapku](docs/goo/ROZHRANIE.md) |
| `session/` | relácia, prihlásenie, nastavenie Hyprlandu, aplikácie, témy — [prehľad](session/README.md) |
| `crates/` | Rust: `latte-hw` (zistenie grafiky), `latte-boot` (výber režimu, počítadlo pádov) |
| `setup/` | inštalačné skripty a testy |
| `resources/` | naše záplaty cudzích projektov; `fetch.sh` stiahne ich zdroje |
| `docs/` | architektúra a pravidlá kvapiek |

## Z čoho LatteOS GOO vychádza

Kvapky kreslí [pleamar](https://github.com/k4ditano/pleamar) od k4ditano a prvým vzorom bola jeho plocha Marea.
LatteOS GOO z nich vyšiel, dnes je to však samostatná plocha s vlastným enginom kvapiek, vlastnými aplikáciami
a vlastným spôsobom ovládania. Okná spravuje Hyprland, rohovú lištu a ovládacie centrum dodáva Noctalia.
Úplný zoznam cudzích súčastí a ich licencií je v [TRETIE-STRANY.md](TRETIE-STRANY.md).

## Chyby a príspevky

Našiel si chybu? Otvor [Issue](https://github.com/arkaysk/latteos/issues) a pripoj
`latte-boot status`, `journalctl -b -e` a čo si robil. Snímky obrazovky pomáhajú.

## Licencia

[MIT](LICENSE). Súčasti tretích strán majú vlastné licencie — [TRETIE-STRANY.md](TRETIE-STRANY.md).
