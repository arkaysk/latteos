# LatteOS Goo — 22 pravidiel plochy

Zásady správania kvapiek, fyziky a vstupov. **Záväzné pri vývoji.**

*Úplný originál je v LATTEOS-GOO.md §2–§3.*

## Princípy (§2)

### 1–5: Základy

1. **Myš je prvá** — každá funkcia myšou (ľavé, pravé, koliesko, ťahanie); klávesy doplnok
2. **Návyky Windows 11** — všetko dole, klik v lište prepne/minimalizuje, pravý klik = ponuka okna
3. **Preberať, nevymýšľať** — Noctalia, pleamar, Marea majú prioritu
4. **Preložiteľnosť** — texty po anglicky + `translations sk` v scéne
5. **Oddelené prostredia** — Goo, čistá Noctalia, Marea a cudzie prostredia (Plasma…) sa nepoškodzujú (Classic je zrušený)

### 6–13: Vzhľad

6. **Kvapky sú vždy káva** — pomer vody a mlieka (Barista); vodová káva (lungo, americano) je sklo, espresso a mliečne kávy nepriehľadné
7. **Bez tváre a bez očí** — hodiny sú digitálne
8. **Klik iba tam, kde má funkciu** — ak funkcia nemá pravý/ľavý klik, kvapka tiež nie; tlačidlo bez funkcie goo zavibruje. Od 6. 10. má každá základná kvapka funkciu na oboch tlačidlách (LATTEOS-GOO.md §3.5)
9. **Okno z kvapky rastie z rohu** — vyskakovacie okno vyrastie z kvapky, ktorá vystúpi a sedí v jeho rohu (ucho); riadne okná sa rodia z bubliny (14)
10. **Vlastný vzhľad ponúk** — rozhranie Goo, nie kopírovanie z Classic
11. **Moderný štýl** — ikony Tabler, písmo Inter, minimalizmus, vkus, užitočnosť
12. **Materiál a priehľadnosť** — prechod z kávy do textúry okien (hliník, zlato, sklo)
13. **Sklo na oknách (Hyprglass)** — okná s lomom a dúhou, iba sklenené témy, vypnutie v `~/.config/latteos/bez-skla`

### 14–16: Interakcia

14. **Z bubliny do okna** — kvapka vypľuje bublinu, tá sa nafúkne na okno, zatvorenie = prasknutie
15. **Farby guliek:** červená = HW, zelená = sieť, modrá = softvér
16. **Všetky kvapky sú drag & drop** — aj Hodiny a vypínač

### 17–22: Fyzika a efekty

17. **Farebné jadro** — gradient od farby do kávy (upozornenie, svetlo…), voliteľne pulzuje
18. **Vlnky na hladine** — kameň (dve vlny) alebo vibrácia, okraj je hladina
19. **Vietor** — náhodný smer, občas aj pri práci; menšie kvapky sa vlnia viac
20. **Krk iba po vzdialenosť** — odtrhnutie po 1,6 polomeru (dlhý krk je nepekný), návrat k okraju ako ponor
21. **Oká ostré** — okrajová čiara medzi spojmi kvapiek je ostrá (nie rozmazaná), vlákno spája susedov
22. **Neprekrývanie** — kvapky sa zlievajú, ale neprekrývajú: ani keď je kurzor ďaleko, ani pri hre; zvýraznený okraj zliatych kvapiek je spoločný (bez deliacej čiary)

---

## Fyzika (§3)

### Nízka gravitácia, pružnosť
- Vlastný pohyb aj bez myši (dýchanie, drift)
- Vzájomné pôsobenie iba v blízkosti
- Lepia sa k okraju a k sebe

### Pokoj
- Kým kurzor nie je nablízku, kvapky si sadnú k okraju (pod hladinu) a sploštia sa
- Pri kurzore sa zdvihnú a zaguľatia

### Gravitácia a okraje
- Na každú kvapku platí gravitácia: pustená vo voľnom priestore spadne dole, ponorí sa a vynorí
- Kvapky sa lepia ku **každému okraju** (dole, vľavo, hore, vpravo), nielen k dnu — pustená pri okraji sa k nemu prilepí
- Nič nevisí vo vzduchu

### Vlákna a spájanie
- Iba na vzdialenosti, aké sú v trojici GooPower – LensGoo – hlava GooBaru (najviac 2,3 súčtu polomerov)
- Vlákno sa naťahuje a trhá, po určitej dĺžke praskne
- Každá kvapka je v **jednom goo tele** — všetky sa spájajú, keď sú blízko (aj Goobar a ikry okien)

### Hladina
- Okraj obrazovky = voda
- Vlnky sa rozbehnú a slabnú
- Po prasknutí krku zvyšková kvapka

### Svetlo
- Pasívne — zhora vľavo
- **Kurzor = aktívne svetlo** — svetlá škvrna a odlesk na strane ku kurzoru

### Živý tvor
- Kurzor je pre kvapky to, **po čom túžia**
- Priblíženie → kvapka sa nadnesie (výstup od okraja na stopke)
- Susedia sa prelievajú a spájajú

---

## Živé bytosti (§3.1) — správanie pri nečinnosti

### Nečinnosť (myš + klávesnica)

- **Stupeň 1** (po ~1 min) — zaspávajú (menšie nadnesenie)
- **Stupeň 2** (po ~3 min) — počasie: dážď alebo vietor podľa Open-Meteo (zatiaľ iba rezerva, nie je hotové)
- **Stupeň 3** (po ~6 min) — hra: naháňačka so zrážkou, behanie (ostatné uhnú), skákanie; nič sa neprekryje

### Prebudenie
- Okamžité — pohyb myši alebo kláves
- Zachvenie a návrat na miesto

### Kedy nie
- Okno na celú obrazovku / hra
- Zamknutá obrazovka
- Batéria < 20 % alebo úsporný profil
- Stupeň Softvér (llvmpipe)

---

## Engine (podrobne v session/goo/README.md)

Engine dáva spoločné pravidlá pre **všetky kvapky** jednou kópiou:

- Fyzika: poloha, ťahanie, prichytenie, nadnesenie, vnútri-telá
- Kurzor: priťahuje (nikdy neodpudzuje), svetlo
- Vstupy: myš (vľavo, vpravo, stred, koliesko, podržanie, ťahanie)
- Susedia: nadnesenie, vlákna, voda, zliatie
- Efekty: jadro, vlnky, vietor, ponor, krk, ostrý okraj, neprekrývanie

**Kvapka je iba definícia:**
- Čísla (povaha, polomer, dosah…)
- Háčiky (klik, pravý, efekty…)
- JSON alebo Luau modul

---

## Ďalej

- [Rozhranie — jednotlivé kvapky podľa Novej architektúry](ROZHRANIE.md)
- Denník rozhodnutí
- Originál v LATTEOS-GOO.md
