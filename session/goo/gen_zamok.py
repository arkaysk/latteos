#!/usr/bin/env python3
"""gen_zamok.py — zo scény prihlásenia (login.plm) urobí zámok obrazovky (zamok.plm).

Zámok je `kind: lock` (ext-session-lock: kompozitor ručí, že kým trvá, nič iné nie je vidno ani sa nedá ovládať),
a to musí byť pomenovaná plocha s `open:` — druh plochy sa nedá prepnúť za behu. Obsah je ten istý, preto sa
zamok.plm NEPÍŠE ručne: po každej zmene login.plm spustiť `python3 gen_zamok.py` (inštalátor to kontroluje).
"""
import os, re, sys

here = os.path.dirname(os.path.realpath(__file__))
src = open(os.path.join(here, "login.plm"), encoding="utf-8").read()


def block(text, start):
    """vyberie blok `start { … }` (aj s vnorenými zátvorkami); vráti (blok, text bez neho)"""
    i = text.index(start)
    j = text.index("{", i)
    depth, k = 0, j
    while True:
        depth += text[k] == "{"
        depth -= text[k] == "}"
        k += 1
        if depth == 0:
            break
    k = text.index("\n", k) + 1
    return text[i:k], text[:i] + text[k:]


head, rest = src.split("scene Login {\n", 1)
rest = rest[:rest.rindex("}")]
_, rest = block(rest, "    surface {")
perms, rest = block(rest, "    permissions {")
trans, rest = block(rest, "    translations sk {")
perms = perms.replace('"latte-greetd"', '"latte-greetd", "pleamar"')


def swap(text, old, new, n=1):
    assert text.count(old) == n, (old, text.count(old))
    return text.replace(old, new)


# Zámok má na všetkých monitoroch JEDNO rozloženie, vycentrované (pleamar: rámček `size:` v strede každého monitora;
# `screen.width` je v ňom rovnaká pre všetky). Rozloženie má preto rozmer najmenšieho monitora (fakty zw × zh, dá ich
# latte-zamok cez logiku) a pozadie, káva a zrážky siahajú ďaleko za jeho okraje.
rest = swap(rest, "    let W = screen.width\n    let H = screen.height\n", "    let W = zw\n    let H = zh\n")
rest = swap(rest, "box { from: 0, 0; size: W, H; color: #1a1410;", "box { from: -4000, -4000; size: W + 8000, H + 8000; color: #1a1410;")
rest = swap(rest, "        box { from: -80, wy; size: W + 160, H }\n", "        box { from: -4000, wy; size: W + 8000, H + 4000 }\n")
rest = swap(rest, "area: W + 300, 20;", "area: W + 3000, 20;", 2)
rest = swap(rest, "area: W + 200, 20;", "area: W + 3000, 20;")
# po odomknutí padá LoginGoo na miesto GooPower na HLAVNOM monitore (šírka mw), nie v rámci vycentrovaného rozloženia
rest = swap(rest, "(tox * W - bx)", "(tox * mw - (mw - zw) / 2 - bx)")
head = re.sub(r"\A(//[^\n]*\n)+", "", head)
out = ("// LatteOS GOO — zámok obrazovky. VYGENEROVANÉ z login.plm (gen_zamok.py) — neupravovať ručne.\n"
       "// Obsah a správanie sú scéna prihlásenia (LATTEOS-GOO.md §6.2) bez úvodu so šálkou; logika lib/prihlasenie.luau\n"
       "// v režime zamok, spúšťa latte-zamok.\n" + head + "scene Zamok {\n"
       "    // zámok je vlastná plocha nižšie; táto nič nekreslí, iba drží scénu\n"
       "    surface { size: 1, 1; anchor: top; margin: 0 }\n" + perms + trans +
       "    fact zamknute = false                      // kým to neplatí, zámok neexistuje; nastaví logika pri štarte\n"
       "    fact zw = 1920                             // rozmer rozloženia: najmenší monitor (latte-zamok)\n"
       "    fact zh = 1080\n"
       "    fact mw = 1920                             // šírka hlavného monitora (tam je GooPower)\n"
       "    surface zamok {\n        kind: lock\n"
       "        // rozmer zámku je rámček vycentrovaný na každom monitore a musí byť číslo (`full` tu neplatí): 0 × 0, takže\n"
       "        // počiatok je v strede monitora a obsah (zw × zh) sa posunie tak, aby bol vycentrovaný\n"
       "        size: 0, 0\n        open: zamknute\n        group {\n"
       "            move: 0 - zw / 2, 0 - zh / 2\n" + rest + "        }\n    }\n}\n")
dst = os.path.join(here, "zamok.plm")
if "--check" in sys.argv:
    sys.exit(0 if os.path.exists(dst) and open(dst, encoding="utf-8").read() == out else 1)
open(dst, "w", encoding="utf-8").write(out)
print("zamok.plm: %d riadkov" % out.count("\n"))
