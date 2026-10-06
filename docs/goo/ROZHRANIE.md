# LatteOS Goo — Rozhranie

Popis jednotlivých kvapiek a ich správania podľa **Novej architektúry** (rozhodnutie 5. 10. 2026) a klikov
podľa rozhodnutia 6. 10. (LATTEOS-GOO.md §4).

| Goo | Ľavý klik | Pravý klik | Koliesko |
|---|---|---|---|
| Hlava GooBaru | ďalší režim okien | ukázať plochu (Win+D) | ďalšie okno / posun pásky |
| Ikry okien | prepnúť / minimalizovať | ponuka okna | — |
| GooPower | karta: účet, napájanie, Nastavenia, Monitor, vypnutie | pás výkonu | veľkosť |
| LensGoo | spúšťač (aj kláves Win) | rýchly zoznam aplikácií | veľkosť |
| ClockGoo | upozornenia a kalendár | čas, stopky, minútka, budíky, počasie | veľkosť |
| QueenGoo | App Manager | Správca zariadení | veľkosť |

Stredné tlačidlo nemá žiadna kvapka shellu; tlačidlo bez funkcie goo zavibruje. Veľkosť hlavy GooBaru je
v Nastaveniach › Kvapky (koliesko na nej prepína okná).

*Záväzné znenie je v LATTEOS-GOO.md §4. Staršie rozdelenie (TimeGoo, DaNoGoo, PowerGoo)
patrí pôvodnej ploche Kvapky, ktorá sa už nenasadzuje (archív: `docs_zaloha/`).*

Stĺpec **Engine** hovorí, čo z toho už vie engine Goo (`session/goo`); zvyšok je zatiaľ iba v scéne Kvapky.

## Jadro — nedá sa skryť

### GooBar — hlavná lišta a správca okien

- **Hlava** (najväčšia kvapka): ikona režimu okien (páska / nad sebou / dlaždice)
  - Ľavý klik = ďalší režim
  - Pravý klik = ukázať plochu (ako Win+D), druhý pravý klik vráti okná
  - Koliesko = posun pásky (páska) alebo ďalšie okno (ako Alt+Tab)
  - Ťahanie = presun lišty k inému okraju (pustená uprostred sa vráti)
- **Ikry okien** (strapce po aplikáciách; menšie, aby sa nezamieňali s ostatnými)
  - Vyrastajú z hlavy doprava alebo nadol (`reversed` v Nastaveniach to otočí)
  - Čím viac okien, tým menšie; do výšky sa vrstvia iba okná tej istej aplikácie
  - Okno pri lište → ikry sa stiahnu nižšie
  - Ľavý klik = prepnúť / minimalizovať (v páske bez minimalizácie), pravý = ponuka okna, ťahanie = poradie
  - Minimalizované = menšie, stlmené; **48 miest**, potom zberná guľôčka
- GooBar sa s inými kvapkami spája iba zo strany, kde nevyrastajú ikry
- Lišta sa zmestí po kraj obrazovky a zastaví pred rohovými prvkami
- **Viac monitorov:** každá obrazovka má vlastný GooBar, okná sa dajú prenášať

**Engine:** hlava, ikry a strapce, uhýbanie oknám, klik, ponuka okna, ukázať plochu, poradie ťahaním, 48 miest,
presun lišty k inému okraju, zastavenie pred rohovou lištou Noctalie (zakázaná zóna, premenlivá šírka), pád
minimalizovaného okna do lišty (pravidlo 14).
**Chýba:** `reversed`, vlastný GooBar na každom monitore (engine beží zatiaľ iba na hlavnom).

### GooPower — napájanie a monitor systému

- **Ľavý klik** = karta Goo spojená s kvapkou: profil účtu (portrét, meno, `login@počítač · od HH:MM`), tlačidlá
  Zamknúť · Odhlásiť; NAPÁJANIE — batéria s pruhom a profil napájania Úspora · Vyvážený · Výkon
  (`powerprofilesctl`); Nastavenia, Monitor; tlačidlá Uspať · Reštartovať · Vypnúť (akcie relácie robí Noctalia)
- **Pravý klik** = **pás výkonu**: kvapka sa natiahne pozdĺž okraja do kapsuly s bunkami CPU · RAM · GPU · VRAM
  (`latte-sysmon goo`, raz za sekundu), okolné goo odtlačí a po vtiahnutí ich vráti; jantárová nad 80 %, červená
  nad 95 % alebo pri prehriatí; prechod myšou = podrobnosti, klik = Monitor, pravý klik = vtiahnuť. FPS v páse nie
  je (hra na celú obrazovku je nad vrstvou Goo)
- **Batéria** (notebook): na kvapke bublinky — 3 zelené ≥ 60 %, 2 žlté ≥ 30 %, 1 červená < 30 %; pod 10 % pulzuje;
  pri nabíjaní dýcha. Na stolnom počítači bez indikátora

**Engine:** všetko vyššie (`kvapky/goopower.luau`); overiť naživo.

### LensGoo — univerzálny spúšťač a lupa

- Kvapka s lupou: vyhľadávač, spúšťač a rozhranie pre AI
- **Režimy** (klik na ikonu režimu, koliesko nad ňou, Tab; pamätá sa v `spustac.json`):
  Aplikácie · Súbory (`fd`) · Web · Terminál (`latte-terminal`) · AI Chat
- **AI** (`latte-ai`): rozhovor v goo bublinách priamo v spúšťači, **nikdy neotvára prehliadač**; bez kľúča API
  cez prihlásené nástroje (Claude Code, Gemini, Codex); bodka rozlišuje lokálny a cloudový model

**Engine:** okno spúšťača v karte Goo (klik na LensGoo alebo **kláves Windows** — dá sa ovládať celé bez myši:
Tab / Shift+Tab režimy, šípky riadok, Enter, Esc; koliesko v karte tiež prepína režimy):
- Aplikácie: obľúbené a nedávne, hľadanie s ikonami, kalkulačka a prevody, stránky Nastavení, rýchle prepnutie
  do iných režimov, pravý klik = akcie aplikácie;
- Súbory: domovské priečinky, `latte-hladaj`, pravý klik otvorí priečinok so súborom;
- Web: adresa, predvolený vyhľadávač, návrhy pri písaní, ostatné vyhľadávače;
- Terminál: príkaz v `latte-terminal` (**terminál po príkaze ostane otvorený**), nebezpečný chce druhý Enter,
  história a dopĺňanie;
- AI: rozhovor v bublinách priamo v karte cez `latte-ai`, odpoveď po riadkoch, nikdy neotvára prehliadač.
Režim, nedávne a história príkazov sú v `spustac.json` spoločne s plochou Kvapky.
- **Pravý klik** (6. 10.) = **rýchly zoznam**: naposledy spustené a obľúbené aplikácie ako dlaždice s ikonami
  (klik spustí), pod nimi Hľadať… (otvorí spúšťač) a App Manager.

**Chýba:** mriežka obľúbených 6 × 3 a nedávne 2 × 2 v spúšťači (teraz zoznam; dlaždice má rýchly zoznam), ťahanie
aplikácií do záložiek obľúbených, filtre typov súborov, „Ukázať výstup tu“, prílohy a hlas v AI, farebná bodka
lokálny/cloud (teraz text).

---

## Voliteľné — dajú sa zapnúť a vypnúť v Nastaveniach

### QueenGoo — App Manager a Správca zariadení

- Korunka na vonkajšej strane (tvar sa dá zmeniť v Nastaveniach)
- **Bodky:** červená = zariadenie potrebuje pozornosť, zelená = výpadok siete, modrá = aktualizácie
- **Ľavý klik** = App Manager (pri aktualizáciách rovno na nich), **pravý** = Správca zariadení (pri výpadku na Sieťach),
  **koliesko** = veľkosť
- Kvapka sa nestáva rohom okna: vypľuje bublinu, ktorá sa nafúkne na okno vedľa nej (1220 × 780)

**Engine:** bodky, oba kliky, korunka, okno sa rodí z bubliny (preletí vedľa kvapky a nafúkne sa na okno), zatvorené
praskne. **Chýba:** voliteľný tvar korunky.

### ClockGoo — čas, kalendár, upozornenia a pohoda

Spája čas a centrum upozornení (predtým TimeGoo a DaNoGoo). V kvapke veľký čas a dátum s teplotou, guľky počtu
upozornení; nové upozornenie zvlní hladinu.

- **Ľavý klik** (od 6. 10.) = **upozornenia a kalendár** v jednej karte s dvoma stĺpcami (ako centrum upozornení
  vo Windows 11): vľavo upozornenia (ikona aplikácie, nadpis, telo; klik otvorí, pravý klik akcie a Zahodiť),
  Nerušiť, Vymazať všetko, Nastavenia oznámení; vpravo mesiac od pondelka, udalosti a úlohy vybraného dňa, nový
  záznam do poľa („10:30 Porada“, „Porada“, „! úloha“) a Prepojené kalendáre (Google, iCloud, CalDAV cez Noctaliu)
- **Pravý klik** = **karta času**: Prehľad (dátum, týždeň, najbližší budík, digitálna pohoda s tromi aplikáciami,
  svetové hodiny) · Stopky (medzičasy) · Minútka (koliesko) · Budíky · Počasie (Dnes / Zajtra / Týždeň)
- Do 6. 10. bol na ľavom klike **hrozno upozornení** na lepkavom vlákne; scéna ho ešte vie, karta ho nahradila

**Engine:** všetko vyššie (`kvapky/clockgoo.luau`, `lib/cas.luau`). Minútka a budíky zvonia aj pri zavretej karte;
bežiaca minútka alebo stopky sa ukazujú v kvapke namiesto dátumu. Údaje sú spoločné s plochou Kvapky
(`casovace.json`, `events.json`, `todo.json`).
**Chýba:** synchronizácia kalendára (účty spravuje Noctalia, karta ich zatiaľ iba otvorí), názov budíka.

### ChatGoo — Beeper

- Aktívna iba s nainštalovaným alebo bežiacim Beeperom; minimalizovaný Beeper „vtečie“ do kvapky
- Upozornenia Beepera idú z ClockGoo do ChatGoo; správy ako hrozno bublín s odznakom siete
- Pomocník `session/bin/latte-chatgoo`

**Engine:** zatiaľ nič.

---

## Návrhy ďalších kvapiek

ClipGoo (schránka), MediaGoo (prehrávač, MPRIS), PassGoo (heslá), CastGoo (streamovanie obrazovky).

---

## Rohová lišta (Noctalia)

- Iba **pravá časť** Noctalie, natvrdo prilepená v rohu
- Ikony programov na pozadí, sieť, hlasitosť, ovládacie centrum
- Plán: priehľadnosť + goo telo pod ňou

## Nastavenia › Kvapky (Goo)

- Jadro (GooBar, GooPower, LensGoo): iba veľkosť a vrátenie na miesto
- Voliteľné (QueenGoo, ClockGoo): klik na kartu = skryť / ukázať
- **Veľkosť:** 50–220 % (to isté robí koliesko nad kvapkou), **Vrátiť na miesto**
- **ChatGoo:** kvapka, alebo ikona Beepera v rohovej lište
- **Vlastné kvapky:** názov, ikona, príkaz
- Súbor: `~/.config/latteos/kvapky.json` (číta sa každé 2 s)

---

## Ďalej

- [Pravidlá plochy](PRAVIDLA.md)
- Denník rozhodnutí
- Originál v LATTEOS-GOO.md
