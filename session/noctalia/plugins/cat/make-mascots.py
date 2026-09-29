#!/usr/bin/python3
"""Maskoti LatteOS — balíčky postáv (balicky/<id>/<snímka>.png + pet.json) a snímky pre lištu.

  python3 make-mascots.py <výstup>                 snímky lišty 44 × 36 z balíčkov: <id>-<snímka>.png (inštalácia)
  python3 make-mascots.py balicky <balicky>        dokreslené balíčky (Latte mačka, Mokka, Tieň) — vlastná pixel-art
  python3 make-mascots.py lista <balicky> <výstup> to isté ako prvý príkaz, s iným priečinkom balíčkov

Balíčky z koncepčných listov používateľa (Homebrew, Kávový drak, Ktulu, Robot turista, Maid, Kapybara, Líška,
Mýval, Svetluška, Dráčik) vyrezáva resources/art/maskoti/vyrez.py. Snímky lišty: sedi, zmurk, spi, hlad, smutny,
lapka-l/p (hudba), odchod-1..3, prazdny, chapadla-1/2 (Ktulu). Plné snímky pre výbehy (maskot.qml) sú v balíčku.
"""
import json, os, struct, sys, zlib

SCALE = 2
# predloha (riadky znakov) → mriežka; DESK/H/W používali pôvodné ASCII mačky, balíčky majú vlastnú veľkosť


def shade(hexc, f):
    r, g, b = (int(hexc[i:i + 2], 16) for i in (0, 2, 4))
    if f >= 1:
        r, g, b = (int(c + (255 - c) * (f - 1)) for c in (r, g, b))
    else:
        r, g, b = (int(c * f) for c in (r, g, b))
    return bytes((r, g, b))


def scale2x(grid):
    """EPX/scale2x: zväčšenie na dvojnásobok so zaoblenými šikminami (podrobnejší obrys než kocky)."""
    h, w = len(grid), len(grid[0])
    out = [["."] * (w * 2) for _ in range(h * 2)]
    at = lambda y, x: grid[y][x] if 0 <= y < h and 0 <= x < w else "."
    for y in range(h):
        for x in range(w):
            p = grid[y][x]
            a, b, c, d = at(y - 1, x), at(y, x + 1), at(y, x - 1), at(y + 1, x)
            e = [p, p, p, p]
            if c == a and c != d and a != b: e[0] = a
            if a == b and a != c and b != d: e[1] = b
            if d == c and d != b and c != a: e[2] = c
            if b == d and b != a and d != c: e[3] = d
            out[2 * y][2 * x], out[2 * y][2 * x + 1], out[2 * y + 1][2 * x], out[2 * y + 1][2 * x + 1] = e
    return out


def png(path, grid, pal):
    """Pixel-art s tieňovaním: horná hrana farby svetlejšia, spodná tmavšia (objem), obrys K ostáva; potom scale2x."""
    g = scale2x(grid) if SCALE == 2 else grid
    h, w = len(g), len(g[0])
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for x in range(w):
            ch = g[y][x]
            if ch == ".":
                raw += b"\x00\x00\x00\x00"
                continue
            base = pal[ch]
            if ch in ("K", "E", "Z", "d"):
                raw += bytes.fromhex(base) + b"\xff"
                continue
            up = g[y - 1][x] if y > 0 else "."
            up2 = g[y - 2][x] if y > 1 else "."
            dn = g[y + 1][x] if y + 1 < h else "."
            dn2 = g[y + 2][x] if y + 2 < h else "."
            lf = g[y][x - 1] if x > 0 else "."
            if up != ch and up2 != ch:
                c = shade(base, 1.28)                 # odlesk na hornej hrane
            elif up != ch or lf != ch and lf in (".", "K"):
                c = shade(base, 1.12)
            elif dn != ch or dn2 != ch:
                c = shade(base, 0.78)                 # tieň pri spodku
            else:
                c = bytes.fromhex(base)
            raw += c + b"\xff"

    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))


def main(out):
    packs = os.path.join(os.path.dirname(os.path.abspath(__file__)), "balicky")
    print("maskoti na lištu:", ", ".join(bar_frames(packs, out)), "→", out)



# ═══ balíčky (25. 9.): Latte mačka, Mokka a Tieň (všeobecný „enderman“) dokreslené podrobnejšie ════════
# ostatné balíčky sa vyrezávajú z koncepčných listov (resources/art/maskoti/vyrez.py) a sú uložené v balicky/
# paleta: K obrys, B telo, L svetlé (brucho, papuľka), P ružová (uši, vankúšiky), E oči, W odlesk oka, N nos, Z „z“
CAT_PAL = {
    "latte": {"K": "3A2618", "B": "E9D2B0", "L": "FFF6E6", "P": "E8A0A0", "E": "5A3A22", "W": "FFFFFF", "N": "D07070", "Z": "E4B283", "S": "C9A983"},
    "mokka": {"K": "0B0806", "B": "2E241E", "L": "4A3A30", "P": "C07070", "E": "F2C94C", "W": "FFF6C0", "N": "8A5050", "Z": "E4B283", "S": "1E1712"},
}
CAT = {
    "sedi": [
        "............................", ".....KK..............KK.....", "....KLBK............KBLK....", "....KLPBK..........KBPLK....",
        "....KBPBBKKKKKKKKKKBBPBK....", "...KBBBBBBBBBBBBBBBBBBBBK...", "...KBBBBBBBBBBBBBBBBBBBBK...", "..KBBBKKKBBBBBBBBBBKKKBBBK..",
        "..KBBKEEWKBBBBBBBBKEEWKBBK..", "..KBBKEEEKBBBBBBBBKEEEKBBK..", "..KBBBKKKBBBBNNBBBBKKKBBBK..", "..KLBPPBBBBBBKKBBBBBBPPBLK..",
        "...KLBBBBBBKBBBBKBBBBBBLK...", "....KKLLLBBBKKKKBBBLLLKK....", "......KLLBBBBBBBBBBLLK......", ".....KBBBBBBBBBBBBBBBBK.....",
        "....KBBBBLLLLLLLLLLBBBBK....", "....KBBBLLLLLLLLLLLLBBBK..KK", "....KBBBLLLLLLLLLLLLBBBK.KBK", "....KBBBBLLLLLLLLLLBBBBKKBK.",
        "....KBBKBBBBBBBBBBBBKBBKBK..", "....KBKPPKBBBBBBBBKPPKBKK...", "....KKKKKKKKKKKKKKKKKKKK....", "............................"],
    "chodza-1": [
        "............................", "............................", "...KK...KK..................", "..KBBK.KBBK.................",
        "..KBPBKBPBK.................", "..KBBBBBBBBK................", ".KBBKEBBBKEBK...............", ".KBBBBBBBBBBK.........KK....",
        ".KNBBBPPBBBBK........KBK....", "..KBBKKBBBBBKKKKKKKKKBK.....", "...KKLLBBBBBBBBBBBBBBBK.....", "....KLLLBBBBBBBBBBBBBBK.....",
        "....KLLLLLLBBBBBBBBBBBK.....", "....KBLLLLLLLLLBBBBBBK......", "....KBKKBBKKKKKKBBKKBK......", "....KBK.KBK....KBK.KBK......",
        "....KK...KK....KK...KK......"],
    "chodza-2": [
        "............................", "............................", "...KK...KK..................", "..KBBK.KBBK.................",
        "..KBPBKBPBK.................", "..KBBBBBBBBK................", ".KBBKEBBBKEBK...............", ".KBBBBBBBBBBK..........KK...",
        ".KNBBBPPBBBBK.........KBK...", "..KBBKKBBBBBKKKKKKKKKBK.....", "...KKLLBBBBBBBBBBBBBBBK.....", "....KLLLBBBBBBBBBBBBBBK.....",
        "....KLLLLLLBBBBBBBBBBBK.....", "....KBLLLLLLLLLBBBBBBK......", "...KBKKKBBKKKKKKKBBKKBK.....", "..KBK...KBK....KBK...KBK....",
        "..KK.....KK...KK.....KK....."],
    "plazi": [
        "............................", "............................", "............................", "............................",
        "............................", "...KK...KK..................", "..KBBK.KBBK.................", "..KBPBKBPBKKKKKKKKKKKKKK....",
        ".KBBKEBBBKEBBBBBBBBBBBBBKK..", ".KNBBBPPBBBBBBBBBBBBBBBBBBK.", "..KBLLLLLLLBBBBBBBBBBBBBBBBK", "..KKLLLLLLLLLLLLLBBBBBBKKKK.",
        "..KBKKKBBKKKKKKKKKBBKKBK....", ".KBK...KBK......KBK..KBK....", ".KK.....KK......KK....KK....", "............................",
        "............................"],
    "skok": [
        "....................KK......", "...KK...KK..........KBK.....", "..KBBK.KBBK........KBK......", "..KBPBKBPBK.......KBK.......",
        "..KBBBBBBBBK....KKBK........", ".KBBKEBBBKEBK..KBBK.........", ".KBBBBBBBBBBKKKBBBK.........", ".KNBBBPPBBBBBBBBBBK.........",
        "..KBBKKBBBBBBBBBBK..........", "...KKLLLBBBBBBBBK...........", "..KBKLLLLLLBBBBK............", ".KBK.KLLLLLLBBKBK...........",
        "KBK...KKKKKKK.KBK...........", "KK.............KBK..........", "................KK..........", "............................",
        "............................"],
    "spi": [
        "............................", ".........................ZZ.", ".....................ZZ...Z.", ".....................Z...ZZ.",
        "...KK..KK............ZZ.....", "..KBPKKPBK..................", "..KBBBBBBBKKKKKKKKKK........", ".KBBBBBBBBBBBBBBBBBBKK......",
        ".KBKKBBKKBBBBBBBBBBBBBK.....", ".KBBBBBBBBBBBBBBBBBBBBBK....", "..KBBPBBBBBLLLLLLBBBBBBK....", "..KLBBBBBLLLLLLLLLBBBBBK....",
        "...KLLLLLLLLLLLLLLBBBBKK....", "....KKBBBBBBBBBBBBBBBBBBK...", ".....KKKKKKKKKKKKKKKKKKK...."],
}
CAT["zmurk"] = [r.replace("KEEWK", "KKKKK").replace("KEEEK", "KBBBK") for r in CAT["sedi"]]
TIEN_PAL = {"K": "050308", "B": "1C1622", "L": "2E2638", "P": "E05CFF", "W": "FFD0FF", "C": "6A4E3A", "G": "4E8A3A", "Z": "C07AE0"}
TIEN = {
    "stoji": ["....KKKKKK....", "...KBBBBBBK...", "...KBLBBLBK...", "...KBBBBBBK...", "...KPWBBPWK...", "...KBBBBBBK...", "...KBBBBBBK...",
              "....KKKKKK....", ".....KBBK.....", "..KKKBBBBKKK..", ".KBBBBLLBBBBK.", ".KBKBBLLBBKBK.", ".KBKBBBBBBKBK.", ".KBKBBBBBBKBK.",
              ".KBKBBBBBBKBK.", ".KBKBBBBBBKBK.", ".KBKKBBBBKKBK.", ".KBK.KBBK.KBK.", ".KBK.KBBK.KBK.", ".KBK.KBBK.KBK.", ".KK..KBBK..KK.",
              ".....KBBK.....", "....KBKKBK....", "....KBKKBK....", "....KBKKBK....", "....KBKKBK....", "....KBKKBK....", "....KBKKBK....",
              "....KBKKBK....", "...KBK..KBK...", "...KKK..KKK..."],
}
TIEN["chodza-1"] = TIEN["stoji"][:22] + ["....KBKKBK....", "...KBK.KBK....", "...KBK..KBK...", "..KBK...KBK...", "..KBK....KBK..",
                                          "..KBK....KBK..", ".KBK......KBK.", ".KBK......KBK.", "KBK........KBK", "KKK........KKK"]
TIEN["chodza-2"] = TIEN["stoji"][:22] + ["....KBKKBK....", "....KBKKBK....", "....KBKKBK....", "....KBKKBK....", "....KBKKBK....",
                                          "....KBKKBK....", "...KBK.KBK....", "...KBK..KBK...", "..KBK....KBK..", "..KKK....KKK.."]
# drží blok (tráva/hlina) nad hlavou — „akoby niečo vzal“
TIEN["drzi"] = ["..KKKKKKKKKK..", "..KGGGGGGGGK..", "..KCCCCCCCCK..", "..KCCCCCCCCK..", "..KKKKKKKKKK..", ".KBK......KBK.", ".KBKKKKKKKKBK.",
                ".KBKBBBBBBKBK.", ".KBKBLBBLBKBK.", ".KBKPWBBPWKBK.", ".KBKBBBBBBKBK.", "..KKKKKKKKKK..", ".....KBBK.....", "...KKBBBBKK...",
                "...KBBLLBBK...", "...KBBBBBBK...", "...KBBBBBBK...", "...KBBBBBBK...", "....KBBBBK....", ".....KBBK.....", ".....KBBK.....",
                ".....KBBK.....", "....KBKKBK....", "....KBKKBK....", "....KBKKBK....", "....KBKKBK....", "....KBKKBK....", "....KBKKBK....",
                "....KBKKBK....", "...KBK..KBK...", "...KKK..KKK..."]


def draw_packs(out):
    """Nakreslené balíčky: <out>/<id>/<snímka>.png + pet.json (rovnaký formát ako vyrezané)."""
    def grid(rows):
        w = max(len(r) for r in rows)
        return [list(r.ljust(w, ".")) for r in rows]
    packs = []
    for pid, pal in CAT_PAL.items():
        d = os.path.join(out, pid); os.makedirs(d, exist_ok=True)
        for name, rows in CAT.items():
            png(os.path.join(d, name + ".png"), grid(rows), pal)
        png(os.path.join(d, "hero.png"), grid(CAT["sedi"]), pal)
        meta = {"name": "Latte mačka" if pid == "latte" else "Mokka", "profile": "macka", "flyer": False, "facing": "left", "scale": 1.2,
                "about": "skáče, plíži sa, uhýba kurzoru; keď sa dlho nič nedeje, priblíži sa a pozerá na teba",
                "idle": ["sedi", "sedi", "zmurk"], "sleep": "spi", "move": ["chodza-1", "chodza-2"], "frames": sorted(CAT) + ["hero"]}
        json.dump(meta, open(os.path.join(d, "pet.json"), "w"), ensure_ascii=False, indent=1)
        packs.append(pid)
    d = os.path.join(out, "tien"); os.makedirs(d, exist_ok=True)
    for name, rows in TIEN.items():
        png(os.path.join(d, name + ".png"), grid(rows), TIEN_PAL)
    png(os.path.join(d, "hero.png"), grid(TIEN["stoji"]), TIEN_PAL)
    json.dump({"name": "Tieň", "profile": "teleport", "flyer": False, "facing": "none", "scale": 1.4,
               "about": "teleportuje sa; občas akoby niečo vzal, ale vždy to vráti",
               "idle": ["stoji"], "sleep": "stoji", "move": ["chodza-1", "chodza-2"], "frames": sorted(TIEN) + ["hero"]},
              open(os.path.join(d, "pet.json"), "w"), ensure_ascii=False, indent=1)
    packs.append("tien")
    return packs



def kacka(packs):
    """Kapybara: gumová kačička zvlášť (žltá z hlavy na snímke s-kackou) — odráža sa po lište vo výbehu."""
    from PIL import Image
    src = os.path.join(packs, "kapybara", "s-kackou.png")
    if not os.path.exists(src):
        return
    im = Image.open(src).convert("RGBA"); w, h = im.size; px = im.load()
    ys = [(x, y) for y in range(int(h * 0.45)) for x in range(w)
          if px[x, y][3] > 0 and px[x, y][0] > 180 and px[x, y][1] > 140 and px[x, y][2] < 120]
    if ys:
        im.crop((min(x for x, _ in ys) - 2, max(0, min(y for _, y in ys) - 2), max(x for x, _ in ys) + 3, max(y for _, y in ys) + 3)) \
          .save(os.path.join(packs, "kapybara", "kacka.png"))


def bar_frames(packs, out):
    """Snímky pre lištu (44 × 36, postava stojí dole) z balíčkov: <out>/<id>-<snímka>.png — widget mascot.luau."""
    from PIL import Image
    os.makedirs(out, exist_ok=True)
    W2, H2 = 44, 36
    done = []
    for pid in sorted(os.listdir(packs)):
        pj = os.path.join(packs, pid, "pet.json")
        if not os.path.exists(pj):
            continue
        meta = json.load(open(pj))
        load = lambda n: Image.open(os.path.join(packs, pid, n + ".png")).convert("RGBA")

        def fit(im, dx=0, dy=0):
            im = im.copy(); im.thumbnail((W2, H2), Image.LANCZOS)
            c = Image.new("RGBA", (W2, H2), (0, 0, 0, 0))
            c.paste(im, ((W2 - im.width) // 2 + dx, H2 - im.height + dy), im)
            return c
        idle = [load(n) for n in meta["idle"]]
        sleep = load(meta.get("sleep") or meta["idle"][0])
        happy = load("srdce") if "srdce" in meta["frames"] else idle[-1]
        blink = load("zmurk") if "zmurk" in meta["frames"] else idle[1 % len(idle)]
        frames = {"sedi": fit(idle[0]), "zmurk": fit(blink), "spi": fit(sleep), "hlad": fit(happy, dy=-2), "smutny": fit(sleep),
                  "lapka-l": fit(idle[0], dy=-2), "lapka-p": fit(idle[0]),
                  "odchod-1": fit(idle[0], dx=12), "odchod-2": fit(idle[0], dx=24), "odchod-3": fit(idle[0], dx=36),
                  "prazdny": Image.new("RGBA", (W2, H2), (0, 0, 0, 0))}
        if "chapadla" in meta["frames"]:
            frames["chapadla-1"] = fit(load("chapadla")); frames["chapadla-2"] = fit(load("chapadla"), dy=-1)
        for n, im in frames.items():
            im.save(os.path.join(out, "%s-%s.png" % (pid, n)))
        done.append(pid)
    return done


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["balicky"] and len(a) > 1:
        print("nakreslené balíčky:", ", ".join(draw_packs(a[1])))
        kacka(a[1])
    elif a[:1] == ["lista"] and len(a) > 2:
        print("snímky lišty:", ", ".join(bar_frames(a[1], a[2])))
    else:
        main(a[0] if a else "mascots")
