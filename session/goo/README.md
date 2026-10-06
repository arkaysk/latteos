# Engine Goo

Spoločný engine pre kvapky LatteOS Goo. Je to rozšírenie pleamar 0.2.6 („DLC“), ktoré používa zdokumentovaný jazyk
0.2 a API logiky. Záplaty Rustu (`resources/patches/`: `pleamar-prazdne-tvary` a `pleamar-pasy-tela` na výkon,
`pleamar-ostre-okraje` na ostré oká) nie sú nutné: bez nich engine funguje, iba pomalšie a s mäkšími okrajmi.

Na systém sa nasadzuje iba engine (pôvodná plocha Kvapky `session/kvapky` už nie) a je predvoleným
prihlásením: relácia **LatteOS GOO** na prihlasovacej obrazovke (`latte-session` bez argumentu). Kvapky sú podľa Novej architektúry
(LATTEOS-GOO.md): jadro GooBar, GooPower, LensGoo; voliteľné QueenGoo, ClockGoo (ChatGoo zatiaľ nie je).

**Pravidlá plochy platia aj tu: LATTEOS-GOO.md §2 a §3** (pred prácou prečítať).
Engine ich nastavuje všeobecne:
- Kvapky sú vždy káva (pomer vody a mlieka z Baristu) a nemajú tvár.
- Kurzor kvapky **iba priťahuje** a je ich svetlom.
- Klik je iba tam, kde má kvapka funkciu; tlačidlo bez funkcie goo zavibruje (kliky kvapiek shellu: LATTEOS-GOO.md §4).
- Všetky kvapky sú drag & drop.
- Všetky sú v jednom goo tele s lištou.

## Prečo engine

V ploche Kvapky má každá kvapka vlastnú kópiu pravidiel: polohu, ťahanie, zoom aj zóny. Tu sú pravidlá napísané
**raz**. Kvapka je iba záznam s číslami (povaha) a voliteľnými háčikmi (správanie).

| Vrstva | Súbor | Čo robí |
|---|---|---|
| scéna | `goo.plm` | fyzika a vstupy myši pre **128 miest** (`repeat`), jedno goo telo s okrajom |
| generátor | `gen.py` | rozpíše telo goo (jazyk nemá `repeat` v `body`), nastaví počet miest `N`, zoznam modulov |
| logika | `lib/engine.luau` | register kvapiek, povahy, háčiky, uloženie polôh, káva, nečinnosť (hra) |
| používateľ | `lib/pouzivatel.luau` + `latte-goo` | kvapky z JSON, za behu (bez reštartu) |
| kvapky | `kvapky/*.luau` | moduly: **GooBar, GooPower, LensGoo, QueenGoo, ClockGoo** (rozmery a rozostupy trojice ako v Kvapkách), počítadlo, hodiny, zvedavka, lepkavá, ťažká, bublinka, kvapôčka |
| príklady | `priklady/*.json` | kvapky používateľa (kalkulačka, systém) |
| Goobar | `lib/goobar.luau` | okná ako kvapky (ikry po aplikáciách, vlastná skupina, menšie, uhýbajú oknám pri lište), pomenovanie okien, ponuka okna, režim okien |

**Kvapky plochy v engine:** `goobar` (hlava + okná), `goopower` (ponuka, batéria), `lensgoo` (lupa, spúšťač) — jadro,
`zaklad = true`, nedajú sa skryť; `queengoo` (guľky, App Manager / Správca zariadení) a `clockgoo` (čas, dátum,
upozornenia) — voliteľné, skrýva ich Nastavenia › Kvapky (`kvapky.json`). Kliky (LATTEOS-GOO.md §4):

| kvapka | ľavý | pravý |
|---|---|---|
| hlava GooBaru | ďalší režim okien | ukázať plochu (Win+D) |
| ikra okna | prepnúť / minimalizovať | ponuka okna |
| GooPower | karta: profil účtu, Zamknúť · Odhlásiť, napájanie a profil napájania, Nastavenia, Monitor, Uspať · Reštartovať · Vypnúť | pás výkonu (kapsula s CPU, RAM, GPU, VRAM — `latte-sysmon goo`) |
| LensGoo | spúšťač | rýchly zoznam (dlaždice naposledy spustených a obľúbených) |
| ClockGoo | upozornenia a kalendár (dva stĺpce) | čas: prehľad, stopky, minútka, budíky, počasie |
| QueenGoo | App Manager | Správca zariadení | Spoločné: **ponuka Goo** (`E.menu`, karta pri
mieste kliku, podponuky, preklady), **guľky** (`d:gulky(n, farby)`), **ikona aplikácie** (`d:obrazok(meno)`),
**`E.upsert`** (kvapky, ktoré vznikajú za behu, napr. okná, bez preskočenia).

## Čo robí každá kvapka (spoločné pravidlá)

- **Kurzor ako gravitácia a svetlo:** v dosahu (`dosah` px) ju priťahuje (`gravitacia` 0…1, nikdy neodpudzuje)
  a kvapka sa k nemu nakloní. Svetlá škvrna a odlesk sú na strane ku kurzoru.
- **Nadnesenie:** keď sa kurzor priblíži, kvapka na lište sa nadnesie (`vznos`), vystúpi kolmo od lišty na
  stopke, ktorá sa naťahuje a tenčí. Susedné kvapky sa pri tom prelievajú a spájajú. Keď kurzor odíde, padne
  späť s prestrelením a odrazom.
- **Susedia na lište** (logika ich nájde podľa polohy, do ~2,6 súčtu polomerov), ako vypínač ↔ Hodiny ↔ hlava
  v Kvapkách:
  - keď sa kurzor priblíži k jednej, sused sa nadnesie tiež (o 30 %) a nakloní sa k nej;
  - spája ich **voda pri okraji**: údolie medzi nimi nesiaha k okraju a skupina pôsobí ako jedna hmota;
  - spája ich **goo vlákno** medzi hornými časťami: čím sú bližšie, tým je hrubšie; nepravidelné (vlastný šum
    hrúbky aj koncov), hrubne s nadnesením a samo sa tvorí a trhá s tokom. Pod ním, nad vodou, vznikajú **oká**;
  - voda leží pod hladinou a nad ňu sa dvíha iba zliatím (inak by zaliala oká).
- **Tok:** každá kvapka pomaly vystupuje a klesá vo vlastnom rytme. Sila zliatia (`10 + 16 · nadnesenie +
  10 · tok`, ako `link` v Kvapkách) sa mení s ním, preto sa susedia raz spoja, raz rozdelia.
- **Nad kvapkou:** mierne sa nafúkne a rôsolovito pulzuje (do šírky a do výšky). Obsah sa nemení, názov a popis
  sú iba v bubline. Pri stlačení sa stlačí (squish).
- **Vlastný pohyb aj bez myši:** dych a pomalý drift.
- **Vstupy:** ľavé tlačidlo (klik = pustenie bez ťahania), pravé, stredné, podržanie (0,65 s), koliesko.
  **Bez háčika nerobia nič** (pravidlo 8) — kvapka iba zavibruje. Veľkosť kolieskom má každá kvapka (`zoom`
  predvolene áno, „zväčšovať sa dajú všetky“), ak koliesko nepoužíva na iné; nie okná GooBaru a bobule.
- **Ťahanie (všetky kvapky):**
  - `lepivost` 0…1 drží kvapku doma: natiahne krk a odtrhne sa až za `trhanie` px; pustená skôr sa vráti;
  - pri lište sa k nej prilepí;
  - ťažká (`hmotnost`) spadne na lištu a odrazí sa.
- **Farebné jadro (pravidlo 17):** od stredu prechod z farby do kávy, predvolene upozornenie.
  - Luau: `d:jadro("siet", 1, true)`, `d:jadro()` zhasne.
  - JSON: `"jadro": "softver"` (stále) alebo `"upozornenie": {"prikaz": "…", "kazdych": 30}` — výstup príkazu je
    farba (`hardver`, `siet`, `softver`, `vystraha`, `svetlo`, `ine`), prázdny výstup jadro zhasne; nové
    upozornenie zvlní hladinu.
- **Hladina (pravidlo 18):** okraj obrazovky je voda.
  - Kameň do vody: dve vlny sa rozbehnú od miesta dopadu a slabnú, kvapky na nich sa nadvihnú.
  - Vibrácia: chvenie na mieste.
  - Luau: `d:vlnka(sila)`, `d:vibruj(sila)`, `E.vlnka(x_px, sila, "kamen" | "vibracia")`.
  - Zvonka: `pleamar --say goo "emit goo_kamen 512"` (napr. minimalizované okno padne do lišty).
- **Vietor (pravidlo 19):** občas zavanie, smer je náhodný; postupná vlna pozdĺž okraja, kvapky sa vlnia ako obilie.
  Menšie kvapky sa vlnia viac (aj tok a drift).
- **Návrat k okraju (pravidlo 20, Marea):** kvapka sa ponorí pod hladinu a vynorí, hladina sa zvlní. Odtrhnutie
  najneskôr po 1,6 polomeru (dlhý krk je nepekný).
- **Oká a ostrý okraj (pravidlo 21):** záplata `pleamar-ostre-okraje` vyhladzuje hranu podľa skutočnej zmeny
  vzdialenosti na pixel, preto je okraj ôk ostrá čiara; tieň je tesný (0, 2, 2).
- **Neprekrývanie (pravidlo 22):** kvapky sa môžu zlievať, ale nie úplne prekryť. Stredy ostanú aspoň 0,95 súčtu
  polomerov od seba, inak sa jedna plynule odsunie, aj reťazovo. Ustúpi tá, na ktorú pustili, nikdy okná Goobaru ani
  pripnuté kvapky. `E.separate()` po pustení, pridaní, zmene veľkosti a zmene okien.
- **Okraje a gravitácia:** kvapka sedí na jednom zo štyroch okrajov (`okraj` 0 dole, 1 vľavo, 2 hore, 3 vpravo;
  predvolene dole). Pustená do 130 px od okraja sa k nemu prilepí, inak spadne dole voľným pádom (`GRAV`) — nič
  nevisí vo vzduchu. `vratit = true` (GooBar): pri pustení
  uprostred sa vráti. Háčik `pustenie(d, X, Y, okraj)` dostane miesto v px obrazovky; `false` = nepresúvať.
  `d:px()` je poloha pozdĺž okraja kvapky; `E.hiAlong(d)` najďalej, kam smie (rohová lišta Noctalie je zakázaná zóna).
- **Kapsula:** `kw` (polovica rovnej časti, px) a `t2` (druhý riadok) urobia z kvapky kapsulu s ikonou vľavo.
  Rovná časť leží **pozdĺž okraja** kvapky (na bokoch zvisle) a jej dĺžka sa mení pružinou — kvapka sa do kapsuly
  natiahne. `kd` = smer: 0 na obe strany (bobuľa), −1 / +1 iba jedným smerom — ikona ostane na konci pri pôvodnej
  kvapke (pás výkonu GooPower). Pravidlo 22 ráta s celou kapsulou (`E.capOff`): susedia sa odsunú. `fix = true` =
  kvapka si v pokoji nesadá (obsah musí byť celý vidieť).
  `koruna = "crown"` nakreslí znak na vonkajšej strane kvapky.
- **Karta Goo** `E.menu(items, šírka, opts)`: položky `label, glyph, hint, on, off, danger, sep, sub, run` a navyše
  `big` (veľký nadpis), `bar` (pruh 0…1), `keep` (klik kartu nezavrie), `wheel = function(smer)` (koliesko nad
  riadkom). `opts.chips = { { label, glyph, on, run } }` sú záložky hore, `opts.id` meno karty (`E.menuId()`),
  `opts.keep` obnovenie otvorenej karty bez zmeny zvýrazneného riadku (živé údaje).
  Ďalšie položky: `info` (údaj na čítanie), `{ grid = true }` (mriežka kalendára: `model.kal`, `E.calendar(klik, šípky)`),
  `{ input = true, label = nápoveď, submit = function(text) }` (textové pole, Enter odošle). Esc kartu zavrie.
  V riadku ešte: `img` (ikona aplikácie podľa mena), `right = function()` (pravý klik), `para` (odsek v bubline),
  pri poli `change = function(text)` (písanie; `submit` vráti `true`, ak má text v poli ostať). `E.menuAt(d)` položí
  kartu ku kvapke (otvorenie z klávesnice), `E.menuText(v)` číta a nastaví text poľa. Rozmery: zadaná šírka × 1,2,
  riadok 44 px; koliesko v karte prepína záložky, Tab / Shift+Tab tiež, šípky a Enter vyberú riadok bez myši.
  Rozloženie (6. 10.): `t2` druhý riadok pod názvom (telo upozornenia), `hd` nadpis sekcie (malé tučné), `pro`
  profil účtu (portrét `img` v kruhu, meno `label`, údaje `t2`), `{ pills = { … } }` rad tlačidiel vedľa seba
  (každé ako položka; `on` = vybrané, `danger` = červené), `{ tiles = { … }, per = 4 }` dlaždice aplikácií (ikona nad
  názvom); `opts.cols = { šírka1, šírka2 }` karta v dvoch stĺpcoch — položka s `col = 2` (aj mriežka kalendára
  a textové pole) ide do pravého. Najviac 24 riadkov; čo sa nezmestí na výšku (1024 × 768), sa nepridá.
- **Efekty scény:** `dych`, `kmit`, `tras`, `obeh`, `tlkot` (+ `sila`).
- **Rezerva na nedefinované efekty:**
  - efekty 6–9 v scéne sú voľné;
  - kanály `e1`…`e4` na každej kvapke (s pružinou): e1 veľkosť, e2/e3 posun, e4 žiara okraja;
  - druhy vzhľadu 2–3 sú voľné.
- **Nečinnosť (§3.1):**
  - stupeň 1 po 1 min: zaspávajú (menšie nadnesenie);
  - stupeň 2 po 3 min: počasie (rezerva, háčik `necinnost`);
  - stupeň 3 po 6 min: hra hravých kvapiek — naháňačka so zámernou zrážkou a stlačením, behanie, skákanie;
  - prebudenie myšou: zachvejú sa a vrátia na miesto.

Povahy (balík čísel): `pokojna`, `zvedava`, `lepkava`, `tazka`, `hrava`.

## Nová kvapka — používateľ (bez programovania)

```sh
latte-goo novy "Moja kvapka"     # vytvorí ~/.config/latteos/goo/kvapky/moja-kvapka.json zo vzoru
latte-goo skontroluj             # povie, čo je v súboroch zle
```

Súbor stačí upraviť a uložiť. Kvapka sa ukáže, zmení alebo zmizne do 4 s, bez reštartu. Príklad:

```json
{
  "id": "kalkulacka", "nazov": "Kalkulačka", "ikona": "calculator", "povaha": "zvedava",
  "popis": "Klik: kalkulačka", "poloha": { "x": 0.3, "y": 0 },
  "text": { "prikaz": "date +%H:%M", "kazdych": 30 },
  "akcie": {
    "klik": { "aplikacia": "org.gnome.Calculator" },
    "pravy": { "vystup": "uptime -p" },
    "podrz": { "otvor": "~/Dokumenty" },
    "koliesko": "velkost"
  }
}
```

**Akcie:**
- `spusti` — príkaz;
- `aplikacia` — id .desktop;
- `otvor` — súbor alebo adresa;
- `vystup` — výstup príkazu v bubline;
- vstavané `domov`, `velkost`, `poskoc`, `nic`;
- koliesko môže mať aj `{ "hore": akcia, "dole": akcia }`.

Príkazy vykoná `latte-goo` podľa id kvapky a mena akcie. Logika scény nikdy nepošle príkaz sama.

**Čísla a voľby:**
- veľkosť a pohyb: `velkost` 8–80, `gravitacia` 0…1, `vznos` 0…1, `dosah`, `lepivost` 0…1, `trhanie`,
  `svetlo`, `rast`, `hmotnost` 0…1;
- vzhľad: `efekt` + `sila`, `druh` (`ikona` | `ukazovatel` s `hodnota` 0…1);
- ďalšie: `tahat` (true/false), `poloha` (`x` = podiel šírky, `y` = px nad lištou);
- skupina: `pri` (id inej kvapky) + `odstup` (px), `vyska` (stred nad okrajom, px), `vznos` 0…2;
- skupina a zliatie: `sk` (0 ostatné kvapky, 1 ikry Goobaru, 2 hlava Goobaru — patrí do oboch; telo goo je jedno), `zliatie` (sila zliatia so susedmi), `mlaka` (mláka a voda pri okraji 0…1).

Farba nie je: kvapky sú vždy káva.

Neskôr to isté pribudne v Nastaveniach › Kvapky (formulár nad týmto súborom).

## Nová kvapka — programátor (vlastné správanie)

Modul `kvapky/<meno>.luau` vracia definíciu: rovnaké polia ako JSON a k nim **háčiky**.

```lua
return {
    id = "pocitadlo", nazov = "Počítadlo", ikona = "number-123", druh = "ukazovatel", povaha = "pokojna",
    start    = function(d) d.n = 0 d:text("0") end,
    klik     = function(d) d.n += 1 d:text(tostring(d.n)) d:hodnota(d.n % 100 / 100) end,
    pravy    = function(d) … end,  stredny = function(d) … end,  podrz = function(d) … end,
    koliesko = function(d, smer) … end,          -- smer +1 hore, −1 dole
    nad = function(d) d:rezerva(4, 1) end,  prec = function(d) d:rezerva(4, 0) end,
    popis    = function(d) return "text bubliny" end,
    tahanie  = function(d) d:efekt("tras", 1) end,
    pustenie = function(d, x, y) return false end,  -- false = nepresúvať (inak engine uloží novú polohu)
    necinnost = function(d, stupen) end,          -- 0 aktívny, 1 po 1 min, 2 po 3 min, 3 po 6 min
    kazdych = 10000, tik = function(d) … end,
}
```

Metódy kvapky:
- upozornenie a hladina: `d:jadro(farba, sila, pulz)`, `d:vlnka(sila)`, `d:vibruj(sila)`, `d:stlac()`;
- obsah: `d:text`, `d:ikona`, `d:nazov`, `d:hodnota`, `d:bublina(text)`;
- vzhľad: `d:efekt(meno, sila)`, `d:rezerva(i, v)`, `d:velkost(z)`;
- poloha: `d:presun(x, y)`, `d:domov()`, `d:poskoc()`;
- všeobecne: `d:nastav{…}`.

Po pridaní súboru treba spustiť `python3 gen.py`, ktorý obnoví `kvapky/zoznam.luau`. Pleamar potom logiku znova
načíta sám. Príkazy, ktoré modul spúšťa cez `run`, musia byť v `permissions` v `goo.plm`.

## Nový efekt

- **V scéne** (plynulý, bez logiky): doplniť výraz pre `fx == 6` (rezerva) do `fxs`/`fxw`/`fxx`/`fxy` v `goo.plm`
  a meno do `EFEKTY` v `lib/engine.luau`.
- **V logike** (zriedkavé zmeny): kanály `d:rezerva(1…4, hodnota)`, scéna ich vyhladí pružinou.

## Prihlásenie (`login.plm`, `login.luau`) — predvolené (`greeter = "goo"`)

Scéna podľa LATTEOS-GOO.md §6.2: šálka z úvodnej obrazovky → kvapka vyskočí doprostred → odvalí sa ~5 cm doľava
a nechá riadok (LoginGoo s ikonou Power · meno · heslo · šípka) → rovina klesne k hladine (káva v spodnej tretine,
z boku ako vodná hladina) → pod hladinou výpis posledného pádu, inak novinky z RSS → hodiny vpravo hore → po minúte
nečinnosti sa vynoria informačné goo (batéria, úlohy; neklikateľné) → po správnom hesle LoginGoo spadne na miesto
GooPower a pozadie zmizne. Klik na LoginGoo = Uspať · Reštartovať · Vypnúť.

- **Skúška:** `latte-goo login-skuska [sekundy]` — nad bežiacou plochou, heslo „latte“ sedí, iné nie, nič sa nemení
  a scéna sama skončí (predvolene po 40 s). Odkryť goo bez čakania: `pleamar --say login "emit e_hra"`.
- **Údaje:** `latte-goo prihlasenie` (meno, káva, pád / novinky, info, znaky ikon, miesto GooPower).
- **Režim** podľa `LATTE_LOGIN`: `skuska` (predvolené), `greetd` (všeobecná relácia prihlasovača), `zamok` (zámok
  obrazovky). Logika je spoločná: `lib/prihlasenie.luau` (`login.luau` a `zamok.luau` ju iba spustia).
- **Zámok obrazovky** (Win+L, GooPower › Zamknúť → `latte-zamok`): tá istá scéna ako `kind: lock` — kompozitor ručí,
  že kým trvá, nič iné nie je vidno ani sa nedá ovládať; heslo overí systém (`auth.check`), po odomknutí LoginGoo
  spadne na miesto GooPower a scéna skončí. `zamok.plm` sa **generuje** z `login.plm` (`python3 gen_zamok.py`, po
  každej zmene login.plm; inštalátor to kontroluje). Zámok má na všetkých monitoroch jedno rozloženie (rozmer
  najmenšieho monitora, vycentrované; pozadie a káva cez celú šírku) — pleamar v zámku nedáva rozmer monitora
  každej kópii. Keby scéna spadla, zámok prevezme Noctalia (`allow_session_lock_restore`). Zámok pri nečinnosti
  robí zatiaľ Noctalia svojím.
- **Obloha a počasie:** silueta slnka alebo mesiaca na skutočnom mieste (obzor = hladina, mesiac vo fáze), dážď
  a sneh podľa počasia vonku; miesto z `greeter.conf` (Nastavenia › Účet › Prihlasovanie).
- **Výber relácie** (vývojárska verzia): goo na hladine za riadkom; zoznam ako v doterajšom prihlasovači.
- **Zapojenie** (6. 10., rozhodnutie: zámok nad VŠEOBECNOU reláciou): `greeter = "goo"` v `/etc/latteos/boot.toml`
  → `latte-greeter` spustí labwc s grafickou kartou pod účtom prihlasovača a v ňom `latte-goo-greeter` (scéna na
  monitore s najväčším rozlíšením, `LATTE_LOGIN=greetd`). Heslo ide z poľa cez `files.write` do súkromného súboru
  na tmpfs (`$XDG_RUNTIME_DIR/latte-login`), `latte-greetd prihlas` ho prečíta, zmaže a overí cez greetd; po
  odchode LoginGoo `latte-greetd koniec` ukončí všeobecnú reláciu a greetd spustí reláciu používateľa (vybranú
  v goo výberu relácie). Bez karty, v režime SAFE alebo keď scéna skončí bez prihlásenia, nasleduje doterajší
  prihlasovač (`latte`). Log scény: `/run/user/<uid prihlasovača>/latte-login/login.log`.
- **Monitory:** `screens: each` — každý monitor má vlastnú kópiu s vlastným rozložením; fakty a texty (heslo, čas)
  sú spoločné. Bez toho sa kópie rozložia podľa šírky posledného monitora.
- **Meno** je pole predvyplnené naposledy prihláseným (Tab prepína meno ↔ heslo); iné účty sa neponúkajú.
- **Novinky:** `rss_url` v `greeter.conf` môže niesť viac zdrojov (medzera, čiarka); titulky sa striedajú.
- **Odovzdanie ploche:** LoginGoo padá presne na miesto GooPower používateľa (`latte-goo uloz-stav` ho odkladá do
  `/var/lib/latteos/greeter/goo-<účet>.json`), plocha spúšťa kvapky pred tapetou a Hyprland má espresso pozadie.
  Aj tak je medzi prihlásením a plochou asi sekunda čiernej (odovzdanie obrazovky medzi dvoma kompozitormi).
- **Ostáva:** odstrániť tú čiernu sekundu (relácia dostáva `LATTE_Z_PRIHLASENIA=1`), údaje používateľa pred heslom
  (upozornenia, úlohy — všeobecná relácia ich nevidí), viac zdrojov noviniek v Nastaveniach (zatiaľ jedno pole).
- **Pri skúšaní:** `systemctl restart greetd` počas bežiaceho prihlasovača nechá jeho labwc a scénu bežať
  (osirelé procesy účtu greetd) — po skúške ich treba ukončiť.
- Skúšať treba v skutočnej relácii: v skrytom kompozitore (labwc headless) pleamar vykreslí iba prvú snímku.

## Ovládanie z klávesnice

Win+T (`latte/skratky.lua` → `pleamar --say goo "emit kb_toggle"`) zapne režim: scéna drží klávesnicu (`keyboard:
exclusive while ctx_open or kb`), `kbk` je miesto vybranej kvapky. Klávesy sú pravidlá scény (`on key … while kb and
not ctx_open`), ktoré posielajú `kb_nav` a `kb_act`; logika (`lib/engine.luau`) chodí po kvapkách po obvode
(`kbRing`) a volá tie isté háčiky ako myš (`klik`, `pravy`, `koliesko`). Pasce: písacie pole karty si klávesnicu
vezme, keď ju plocha dostane — preto `blur` pri vstupe, pri zisku klávesnice a po zatvorení karty; a hodnota udalosti
je vo `while` ešte z predošlej udalosti — preto bublinu kladie jedno pravidlo podľa `kbx`, `kby` (gen.py), nie
pravidlo na miesto. Skúška bez klávesnice: `emit kb_toggle`, `emit kb_nav 1`, `emit kb_act 0`.

## GooBar na každom monitore

Hlavný monitor (ľavý horný roh 0,0) má celú plochu so všetkými kvapkami. Každý ďalší monitor má **vlastnú inštanciu
enginu** iba s GooBarom (`latte-kvapky` › `scene_up`: `LATTE_GOO_VEDLAJSI=1`, malá scéna `m32`, `--screen MENO`) —
jedna inštancia na monitor, lebo kópie jednej scény majú v pleamare spoločný stav a na monitoroch s rôznym
rozlíšením by boli polohy zle. Služba `window` nevie, na ktorom monitore okno je, preto GooBar páruje okná
s `hyprctl clients` a berie iba tie zo svojho monitora (`E.monitorId`, `lib/goobar.luau` › `mark_hidden`). Vedľajšia
inštancia má vlastné uložené miesta (`stav-<monitor>.json`) a log (`kvapky-<monitor>.log`); na príkazy odpovedá ako
`goo-<pid>` (meno `goo` má hlavná). Vypnúť: `~/.config/latteos/goobar-monitory` s obsahom `off`.

## Počet miest podľa potreby

Scéna počíta každú snímku všetky miesta pre kvapky, aj prázdne (pravidlá, pružiny, skladanie): 128 miest 42 % jadra,
64 miest 24 %, 32 miest 17 % (latte-lab, 16 kvapiek). Engine preto beží na najmenšej scéne, do ktorej sa zmestí:
`gen.py --n 32 --out DIR` vyrobí menšiu scénu (inštalátor: `/usr/share/latteos/goo/m32`, `m64`; logika a kvapky sú
odkazy na spoločné), scéna nesie `fact miesta` a logika podľa neho rozdáva miesta. Keď ostávajú najviac 4 voľné,
`E.miesta()` si povie o väčšiu (`latte-kvapky miesta 64|128` — scéna sa vymení, kvapky sa vrátia na miesta); späť
na menšiu po troch minútach, keď je voľno. Posledná veľkosť: `~/.local/state/latteos/goo/miesta`.

## Obloha a počasie na hladine

`lib/engine.luau` sa raz za 10 minút spýta `latte-goo obloha` (slnko, mesiac, dážď / sneh, vietor; miesto
z `greeter.conf`): výška slnka → fakty `den` a `zlata` (svetlo v kvapkách `svit`, žiara nad horizontom). Počasie sa
ukáže až pri nečinnosti (stupeň 2, po 3 minútach) a iba keď smie (`allowed`: vypínač Živé správanie, nie stupeň
Softvér, batéria pod 20 %, úsporný profil, okno na celú obrazovku): fakt `prsi` zapne častice, vlnky robí logika
(`E.vlnka`). Skúška bez čakania: `pleamar --say goo "fact idle 2"` a `"emit goo_pocasie N"` (0 nič, 1 riedky dážď,
2 dážď, 3 sneh, 4 vietor), späť `"fact idle 0"`. Tú istú funkciu používa prihlásenie (`latte-goo prihlasenie`).

## Profil používateľa v jednom dokumente (`latte-gooconfig`)

`~/.config/latteos/<účet>@gooconfig.json` (práva 600) — celé prostredie účtu v jednom dokumente: `goo` (kde ktorá
kvapka sedí a aká je veľká, skryté a vlastné kvapky, káva, pás výkonu), `okna` (téma, režim, stupeň výkonu), `tapeta`,
`obrazovky`, `noctalia` (widgety rohovej lišty, nastavenia), `spustac`, `subory`, `maskot`, `ai` (bez tajných kľúčov),
`siet`, `slovnik`. Každý účet má svoj — každý môže mať GooPower inde, iné goo aj tapetu.

- **Stav (prvá verzia, 6. 10.):** programy ešte čítajú svoje pôvodné súbory (`~/.config/latteos/*`,
  `~/.local/state/latteos/**`); dokument s nimi drží v zhode **oboma smermi** `latte-gooconfig sleduj` (beží
  s plochou, spúšťa `latte-kvapky start`): zmena nastavení → do 5 s v dokumente; dokument zmenený ručne alebo
  prinesený → rozloží sa do nastavení a bežiaci engine, tapeta a téma ho prevezmú hneď. Pri prihlásení to isté
  robí `latte-gooconfig prihlasenie` (`latte-session`) ešte pred štartom plochy.
- **Príkazy:** `ukaz`, `zber`, `pouzi [SÚBOR] [--hned]`, `export SÚBOR`, `cesta`. Prenos na iný počítač:
  `export` tam, `pouzi` tu. Mapu „časť dokumentu ↔ súbor“ má skript hore (`MAPA`) — nové nastavenie sa pridá riadkom.
- **Prihlasovanie** do domova nevidí: dostane iba výťah `/var/lib/latteos/greeter/goo-<účet>.json` (kde sedí
  GooPower, aká je káva) — LoginGoo padá na miesto GooPower toho, kto sa prihlasuje, a káva je jeho.
- **Ostáva:** aby programy čítali dokument priamo (engine cez `latte-goo`, Nastavenia, tapety, téma) a pôvodné
  súbory zanikli; export a import v Nastaveniach › Účet; overiť s druhým účtom.

## Ďalej (z pravidiel plochy, zatiaľ nie v engine)

- Dážď a vietor podľa počasia pri nečinnosti (LATTEOS-GOO.md, nečinnosť stupeň 2). Ostatné otvorené úlohy enginu
  sú v ROADMAP.md (F3·G).

## Jazyk pleamar 0.2 a Luau — pasce (stálo to čas)

**Scéna (pleamar):**
- V `body` nie je `repeat`, preto existuje `gen.py`. `gen.py` prepisuje **každé** `repeat k in 0..N`, ďalšie cykly
  musia mať iné meno premennej (menu používa `m`).
- `let` v `repeat` je lokálny pre kópiu. Hodnotu do rovnakého snímku exportuje `prop X.$k = 0 ~0ms` + `follow`.
- `sin`/`cos` berú **stupne**.
- `smooth()` chce konštantné hrany, inak treba ručné t²(3−2t).
- `size:` textu je **iba pevné číslo**: `size: 14 * čokoľvek` kreslí 14 (fakt, prop aj let — overené skúšobnou scénou
  5. 10.). Cloud predpokladal, že násobiteľ funguje; preto sa pri nafukovaní kvapky text nemenil. Text, ktorý má
  rásť, sa kreslí vo väčšej pevnej veľkosti v `group { pivot; scale }` a posuny vnútri sa delia mierkou.
  (`letter_scale` nepomôže — písmená sa prekryjú.) To isté platí pre `kvapka.plm` (`size: 16 * zt.p`).
- `pick()` nevie farby, pomôže vnorený `if`. `gradient` existuje iba v `body`.
- Tvary tela sa počítajú pre každý pixel a `show:false` ich neodstráni. Preto nulová veľkosť + záplata prazdne-tvary.
- `while` v pravidle vidí **stav zo začiatku snímky**. Príznak nastavený pri `press` preto `release` v tej istej
  snímke (ťuknutie na touchpade, virtuálna myš) nevidí: každý druhý klik sa stratil. Poradie patrí do logiky.
- `release zone` príde pri pustení **ktoréhokoľvek** tlačidla; v pravidle sa nedá zistiť, ktorého.
- Po reštarte scény nepríde `enter`, kým sa myš nepohne (Wayland).
- Viac monitorov: scéna sa kreslí na každom, ale voľné `prop` a `fact` sú **jedny pre všetky kópie** (aj so
  `screens: each`) a `screen.width` je z poslednej kópie. Vlastný stav na monitor = mená s `$screen` alebo jeden
  proces na monitor (`--screen MENO`). Engine zatiaľ beží iba na hlavnom monitore.
- Číslo pri `pleamar --say goo "emit udalosť N"` má malý rozsah (zbalené 48-bitové neprešlo): viac hodnôt poslať
  ako fakty (`fact meno hodnota`) a potom udalosť.
- `scroll zone` dostane **každá** zóna pod kurzorom, nielen vrchná: koliesko nad riadkom príde aj ploche karty —
  logika si pamätá, že ho použil riadok (`wheel_used`), a plocha karty chvíľu počká (`ctx_bgw`).
- `lines:` textu chce číslo, nie výraz; `anchor: left top` kreslilo odsek mimo — odsek je `left center` na strede
  odhadnutej výšky. Text sa s textom porovnať nedá (`a == ""`): pomocné číselné pole.
- Skrytý `input` (`show: false`) stále berie kliky na svojom mieste: nepoužité pole odsunúť mimo (`-4000`).
- `keyboard: on_demand` dá klávesnicu až po kliku do plochy; modálna karta potrebuje `exclusive while …`.
- Chyba v obsluhe udalosti logiky (napr. klik na čip) sa do logu nezapíše — zložitejšie stavanie karty obaliť
  `pcall` a chybu vypísať (`text.hud`).
- Skúšobná myš: skok von z kvapky skôr, než sa začne ťahanie (> 6 px vnútri zóny), kompozitor berie ako pustenie.
  Ťahanie v teste začať malými krokmi (ydotool drží tlačidlo, wlrctl alebo ydotool hýbe).
- `screen.width` je pri dvoch monitoroch jedna hodnota pre obe plochy (scéna má jeden stav): na latte-lab 1920
  aj na monitore 2560. Scéna sa na oboch monitoroch kreslí rovnako, ako pôvodné Kvapky.

**Logika (Luau):**
- `emit(name)` z logiky **nenesie dáta** (opačný smer `emit ev(k)` áno). Signál pre konkrétnu kvapku sa preto posiela
  počítadlom (fakt + `on change`).
- Luau nemá `goto`. `save` je deklarované dopredu (`local save` … `save = function()`).
- `sys.watch` musí predchádzať `sys.call` tej istej služby, inak padli ďalšie kvapky.
- `tabler.json` Noctalie má kódy ako `U+EA35` (nie `0x…`); mená ikon overiť proti nemu (`123` neexistuje,
  je `number-123`).
- Logika nepozná rozmer obrazovky: scéna exportuje `fact sw/sh` cez `every 1s while sw != W or sh != H`.
  Na štarte je 0, preto fallback 1920.

**CLI pleamaru:**
- `--mouse` nemá stredné tlačidlo.
- `click@`/`right@` stlačia a pustia v jednom snímku, testy preto používajú `down@ up@`.
- `--say` berie meno scény malými písmenami (`goo`).

## Testovanie bez obrazovky (cloud)

1. `resources/fetch.sh` a build pleamaru v `resources/upstream/pleamar` so záplatami.
   apt balíky: `libxkbcommon-dev libwayland-dev libfontconfig-dev libdbus-1-dev libpam0g-dev`.
2. `python3 session/goo/gen.py`, potom `pleamar --check session/goo/goo.plm` (aj `session/kvapky/kvapka.plm`).
3. Headless Sway (pixman, llvmpipe), 1920×1080, plávajúce okná, spúšťané cez `setsid -f`. Sway medzi ťahmi umiera,
   skript sa musí vytvoriť znova (bol v `/tmp`). Testovacie okná sú `foot`/`weston-terminal`, snímky `grim`, výrezy
   cez Pillow.
4. Pleamar: `--scene … --mouse "x,y@ms down@ up@ right@ wheel+@ out@" --record mena --say goo "emit goo_kamen 900"
   --seconds N --no-hud --no-vsync`.
5. V cloude chýba font Tabler, takže glyfy nie sú vidieť. To je očakávané.

## Overenie

```sh
pleamar --check goo.plm                         # jazyk, mená, poradie
pleamar --scene goo.plm --mouse "429,690@1500 down@2000 up@2100 wheel+@3000 right@3400" --record hud
```

Vľavo hore (`ladenie`) je posledná udalosť. V cloude to beží v headless Sway (llvmpipe) s falošnou myšou.
Falošná myš pleamar nevie stredné tlačidlo; `click` a `right` pošlú stlačenie aj pustenie v tom istom snímku,
preto treba `down@… up@…`.
