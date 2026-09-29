#!/usr/bin/python3
"""Vyrezanie animácií maskotov z listov s pomenovanými riadkami (dodal používateľ 26. 9. 2026):
list-foxy-maid.png, list-robot.png, list-kavovy-drak.png.

  python3 vyrez2.py náhľad LIST VÝSTUP.png   nájdené objekty s číslami a rámčekmi (na kontrolu rozloženia)
  python3 vyrez2.py balík MASKOT CIEĽ         podľa RIADKOV nižšie zapíše CIEĽ/<snímka>-<n>.png a doplní pet.json

Pozadie: listy maid a robot majú šachovnicu nakreslenú v obrázku (svetlé neutrálne tóny ~234 a ~250). Za pozadie sa
považuje šachovnica spojená s okrajom a uzavreté ostrovčeky, v ktorých sú oba tóny (biela zástera maid ostane).
List dráčika je priehľadný; červené lemy po starom odstránení pozadia sa zmažú (tmavočervené, polopriehľadné pri okraji).
"""
import json, os, sys
from collections import deque
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))


def checker_mask(im):
    """True = pozadie (šachovnica)."""
    w, h = im.size
    px = im.load()
    cand = bytearray(w * h)
    tone = bytearray(w * h)                         # 1 = svetlý (≥245), 2 = stredný
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y][:3]
            if max(r, g, b) - min(r, g, b) <= 12 and min(r, g, b) >= 224:
                cand[y * w + x] = 1
                tone[y * w + x] = 1 if min(r, g, b) >= 245 else 2
    bg = bytearray(w * h)
    seen = bytearray(w * h)
    for sy in range(h):
        for sx in range(w):
            i0 = sy * w + sx
            if not cand[i0] or seen[i0]:
                continue
            q = deque([i0]); seen[i0] = 1
            comp, edge, n1, n2 = [], False, 0, 0
            while q:
                i = q.popleft(); comp.append(i)
                x, y = i % w, i // w
                if x == 0 or y == 0 or x == w - 1 or y == h - 1:
                    edge = True
                if tone[i] == 1: n1 += 1
                else: n2 += 1
                for j in (i - 1, i + 1, i - w, i + w):
                    if 0 <= j < w * h and cand[j] and not seen[j] and abs((j % w) - x) <= 1:
                        seen[j] = 1; q.append(j)
            n = len(comp)
            checker = n >= 60 and n1 >= 0.2 * n and n2 >= 0.2 * n
            if edge or checker:
                for i in comp:
                    bg[i] = 1
    return bg


def cutout(im):
    """RGBA bez pozadia."""
    im = im.convert("RGBA")
    w, h = im.size
    if im.getpixel((0, 0))[3] == 0:                 # už priehľadný list (dráčik): zmazať červené lemy
        px = im.load()
        a = im.split()[3].load()
        for y in range(h):
            for x in range(w):
                r, g, b, al = px[x, y]
                if al == 0:
                    continue
                near = any(0 <= x + dx < w and 0 <= y + dy < h and a[x + dx, y + dy] == 0
                           for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0), (0, 2), (0, -2)))
                if near and r > 120 and r > g * 1.9 and r > b * 1.9:
                    px[x, y] = (0, 0, 0, 0)          # červený lem
                elif near and al < 200:
                    px[x, y] = (r, g, b, al // 2)
        return im
    bg = checker_mask(im)
    px = im.load()
    for y in range(h):
        for x in range(w):
            if bg[y * w + x]:
                px[x, y] = (0, 0, 0, 0)
    # svetlý lem pri okraji postavy (vyhladená hrana do šachovnice) → polopriehľadný
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            r, g, b, al = px[x, y]
            if al and min(r, g, b) >= 214 and max(r, g, b) - min(r, g, b) <= 16 and \
               any(bg[(y + dy) * w + x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                px[x, y] = (r, g, b, 90)
    return im


def objects(im, min_side=18, gap=4):
    """Súvislé objekty (s dilatáciou o gap px) → [(x0, y0, x1, y1)] zoradené po riadkoch."""
    w, h = im.size
    a = im.split()[3].point(lambda v: 255 if v > 40 else 0).filter(ImageFilter.MaxFilter(2 * gap + 1))
    ap = a.load()
    seen = bytearray(w * h)
    boxes = []
    for y in range(h):
        for x in range(w):
            if ap[x, y] and not seen[y * w + x]:
                q = deque([(x, y)]); seen[y * w + x] = 1
                x0 = x1 = x; y0 = y1 = y
                while q:
                    cx, cy = q.popleft()
                    x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
                    for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                        if 0 <= nx < w and 0 <= ny < h and ap[nx, ny] and not seen[ny * w + nx]:
                            seen[ny * w + nx] = 1; q.append((nx, ny))
                if x1 - x0 >= min_side and y1 - y0 >= min_side:
                    boxes.append((x0 + gap, y0 + gap, x1 - gap + 1, y1 - gap + 1))
    boxes.sort(key=lambda b: (b[1] // 40, b[0]))
    return boxes


def preview(sheet, out):
    im = cutout(Image.open(os.path.join(HERE, sheet)))
    boxes = objects(im)
    canvas = Image.new("RGBA", im.size, (40, 44, 52, 255))
    canvas.alpha_composite(im)
    d = ImageDraw.Draw(canvas)
    for i, b in enumerate(boxes):
        d.rectangle(b, outline=(255, 80, 80, 255))
        d.text((b[0] + 2, b[1] + 2), str(i), fill=(255, 255, 0, 255))
    canvas.save(out)
    for i, b in enumerate(boxes):
        print(i, b)


# RIADKY: (animácia, y0, y1, x0, x1, počet snímok, slučka, obr/s, druh) — druh "mala" (lišta, výbehy) alebo "zblizka"
# (priblíženie z monitora). Hranice riadkov z profilu priehľadnosti (prázdne pásy medzi riadkami).
MASKOTI = {
    "maid": {
        "list": "list-foxy-maid.png", "mierka": 0.72, "zblizka_v": 300, "orez_spodok": {},
        "riadky": [
            ("zameta", 0, 93, 120, 700, 4, True, 6, "mala"), ("oprasuje", 93, 186, 120, 700, 4, True, 6, "mala"),
            ("lesti", 186, 278, 120, 700, 4, True, 6, "mala"), ("predklon", 279, 370, 120, 700, 3, False, 4, "mala"),
            ("selfie", 371, 471, 120, 700, 4, True, 3, "mala"), ("srdiecka", 472, 566, 120, 700, 3, False, 3, "mala"),
            ("kava", 567, 677, 120, 700, 4, True, 2, "mala"), ("zivne", 680, 752, 120, 700, 4, False, 3, "mala"),
            ("nahliada", 764, 850, 120, 400, 2, True, 2, "mala"), ("vykukne", 773, 1013, 400, 1300, 3, False, 2, "zblizka"),
            ("dvere-von", 100, 202, 890, 1450, 4, False, 4, "mala"), ("dvere-dnu", 217, 320, 890, 1450, 4, False, 4, "mala"),
            ("padak", 326, 465, 890, 1450, 3, False, 3, "mala"), ("urazena", 474, 583, 890, 1450, 4, True, 3, "mala"),
            ("zazera", 596, 696, 890, 1450, 2, True, 2, "mala"),
        ],
    },
    "robot": {
        "list": "list-robot.png", "mierka": 0.5, "zblizka_v": 280, "orez_spodok": {},
        "riadky": [
            ("boost", 12, 141, 140, 1536, 4, True, 8, "mala"), ("vznasa", 157, 297, 140, 1536, 2, True, 3, "mala"),
            ("foti", 310, 428, 140, 1536, 4, False, 3, "mala"), ("skenuje", 449, 567, 140, 1536, 3, True, 3, "mala"),
            ("nabija", 584, 706, 140, 1536, 2, True, 1, "mala"), ("zblizka", 728, 1010, 140, 1536, 3, False, 1, "zblizka"),
        ],
    },
    "drak": {
        "list": "list-kavovy-drak.png", "mierka": 0.62, "zblizka_v": 280,
        "orez_spodok": {"vzlet": 12, "pristatie": 12, "strazi": 12},       # hnedá podložka pod snímkami
        "riadky": [
            ("let", 16, 108, 140, 1312, 4, True, 6, "mala"), ("plachti", 135, 207, 140, 1312, 2, True, 2, "mala"),
            ("vzlet", 219, 325, 140, 1312, 3, False, 5, "mala"), ("pristatie", 346, 441, 140, 1312, 3, False, 5, "mala"),
            ("strazi", 458, 551, 140, 1312, 3, True, 1, "mala"), ("ohen", 572, 655, 140, 1312, 4, False, 4, "mala"),
            ("v-salke", 672, 788, 140, 1312, 3, True, 1, "mala"), ("zlakne-sa", 793, 909, 140, 1312, 3, False, 5, "mala"),
            ("zblizka", 940, 1178, 140, 1312, 3, False, 1, "zblizka"),
        ],
    },
}


def segments(im, box, count):
    """Snímky v riadku: stĺpce oddelené medzerou; ak ich je viac než count, najmenšie sa pripoja k susedovi (dym, iskry)."""
    x0, y0, x1, y1 = box
    a = im.split()[3].load()
    occ = [sum(1 for y in range(y0, y1) if a[x, y] > 40) > 1 for x in range(x0, x1)]
    segs, cur, gap = [], None, 0
    for i, o in enumerate(occ):
        if o:
            if cur is None: cur = [i, i]
            else: cur[1] = i
            gap = 0
        elif cur is not None:
            gap += 1
            if gap >= 10:
                segs.append(cur); cur = None; gap = 0
    if cur: segs.append(cur)
    segs = [[s[0] + x0, s[1] + x0 + 1] for s in segs if s[1] - s[0] >= 6]
    while len(segs) > count:                         # pripojiť najužší k bližšiemu susedovi
        i = min(range(len(segs)), key=lambda k: segs[k][1] - segs[k][0])
        if i == 0: j = 1
        elif i == len(segs) - 1: j = i - 1
        else: j = i - 1 if segs[i][0] - segs[i - 1][1] < segs[i + 1][0] - segs[i][1] else i + 1
        lo, hi = min(i, j), max(i, j)
        segs[lo] = [segs[lo][0], segs[hi][1]]; del segs[hi]
    out = []
    for sx0, sx1 in segs:
        crop = im.crop((sx0, y0, sx1, y1))
        bb = crop.getbbox()
        if bb:
            out.append(crop.crop(bb))
    return out


def export(mid, dst):
    spec = MASKOTI[mid]
    im = cutout(Image.open(os.path.join(HERE, spec["list"])))
    os.makedirs(dst, exist_ok=True)
    anim, closeup = {}, []
    for name, y0, y1, x0, x1, count, loop, fps, kind in spec["riadky"]:
        frames = segments(im, (x0, y0, x1, y1), count)
        cut = spec["orez_spodok"].get(name, 0)
        if cut:
            frames = [f.crop((0, 0, f.width, f.height - cut)).crop(f.crop((0, 0, f.width, f.height - cut)).getbbox()) for f in frames]
        if len(frames) != count:
            print("!! %s/%s: %d snímok namiesto %d" % (mid, name, len(frames), count))
        W, H = max(f.width for f in frames), max(f.height for f in frames)
        k = spec["mierka"] if kind == "mala" else spec["zblizka_v"] / H
        names = []
        for n, f in enumerate(frames, 1):
            c = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            c.alpha_composite(f, ((W - f.width) // 2, H - f.height))          # spoločné plátno: dole na stred
            c = c.resize((max(1, round(W * k)), max(1, round(H * k))), Image.LANCZOS)
            fn = "%s-%d" % (name, n)
            c.save(os.path.join(dst, fn + ".png"), optimize=True)
            names.append(fn)
        if kind == "zblizka":
            closeup = names
        else:
            anim[name] = {"frames": names, "fps": fps, "loop": loop}
    return anim, closeup


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "balík":
        a, c = export(sys.argv[2], sys.argv[3])
        print(json.dumps({"anim": a, "closeup": c}, ensure_ascii=False))
        sys.exit(0)
    if len(sys.argv) >= 4 and sys.argv[1] == "náhľad":
        preview(sys.argv[2], sys.argv[3])
    else:
        print(__doc__)
