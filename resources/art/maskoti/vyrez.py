#!/usr/bin/python3
"""Vyrezanie spritov maskotov z koncepčných listov (kolekcia-1.png, kolekcia-2.png — dodal používateľ, 25. 9. 2026).

  python3 vyrez.py náhľad VÝSTUP.png     všetky nájdené objekty s číslami (na výber)
  python3 vyrez.py balíky CIEĽ           podľa VÝBERU nižšie zapíše balíky CIEĽ/<maskot>/<snímka>.png + pet.json

Postup: v pásoch listu sa nájdu súvislé objekty (popredie = farba ďaleko od tmavého pozadia karty), pozadie
spojené s okrajom výrezu sa odstráni zaplavením (tmavé oči a obrysy vnútri postavy ostanú).
"""
import json, os, sys
from collections import deque
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
# (list, x0, x1, y0, y1): pásy s kartami — hlavný obrázok aj riadky „Kľud“ / „V pohybe“
BANDS = {
    "kolekcia-1": [(0, 1536, 105, 250), (0, 1536, 264, 332), (0, 1536, 350, 425),
                   (0, 1536, 540, 675), (0, 1536, 694, 757), (0, 1536, 772, 845)],
    "kolekcia-2": [(0, 1312, 128, 295), (0, 1312, 318, 392), (0, 1312, 414, 488),
                   (0, 1312, 638, 785), (0, 1312, 808, 885), (0, 1312, 905, 985)],
}


def dist(a, b):
    return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])


def components(im, box, thr=48, min_side=22, lines=False):
    x0, x1, y0, y1 = box
    w, h = x1 - x0, y1 - y0
    px = im.load()
    bg = (8, 14, 30)
    fg = [[dist(px[x0 + x, y0 + y], bg) > thr for x in range(w)] for y in range(h)]
    if lines:                                 # deliace čiary kariet: dlhý súvislý vodorovný úsek (postavy sú užšie)
        for y in range(h):
            row, x = fg[y], 0
            while x < w:
                if row[x]:
                    e = x
                    while e < w and row[e]:
                        e += 1
                    if e - x > 110:
                        for k in range(x, e):
                            row[k] = False
                    x = e
                else:
                    x += 1
    # dilatácia o 3 px, nech sa iskry a chvosty spoja s postavou
    R = 3
    dil = [[False] * w for _ in range(h)]
    for y in range(h):
        row = fg[y]
        for x in range(w):
            if row[x]:
                for yy in range(max(0, y - R), min(h, y + R + 1)):
                    r2 = dil[yy]
                    for xx in range(max(0, x - R), min(w, x + R + 1)):
                        r2[xx] = True
    seen = [[False] * w for _ in range(h)]
    out = []
    for y in range(h):
        for x in range(w):
            if dil[y][x] and not seen[y][x]:
                q = deque([(x, y)]); seen[y][x] = True
                mnx = mxx = x; mny = mxy = y; n = 0
                while q:
                    cx, cy = q.popleft(); n += 1
                    mnx, mxx, mny, mxy = min(mnx, cx), max(mxx, cx), min(mny, cy), max(mxy, cy)
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < w and 0 <= ny < h and dil[ny][nx] and not seen[ny][nx]:
                            seen[ny][nx] = True; q.append((nx, ny))
                bw, bh = mxx - mnx + 1, mxy - mny + 1
                # zlepené objekty (pás snímok, hlavný obrázok + malá postava) rozdeliť podľa zvislých medzier
                runs, cur = [], None
                for xx in range(mnx, mxx + 1):
                    occ = any(fg[yy][xx] for yy in range(mny, mxy + 1))
                    if occ and cur is None:
                        cur = [xx, xx]
                    elif occ:
                        cur[1] = xx
                    elif cur is not None and xx - cur[1] >= 4:
                        runs.append(cur); cur = None
                if cur is not None:
                    runs.append(cur)
                runs = [r for r in runs if r[1] - r[0] >= 18]
                parts = []
                for r in (runs if len(runs) > 1 else [[mnx, mxx]]):
                    ys = [yy for yy in range(mny, mxy + 1) if any(fg[yy][xx] for xx in range(r[0], r[1] + 1))]
                    if ys:
                        parts.append((r[0], ys[0], r[1], ys[-1]))
                for (ax, ay, bx, by) in parts:
                    pw_, ph_ = bx - ax + 1, by - ay + 1
                    if pw_ >= min_side and ph_ >= min_side and ph_ > 0.35 * pw_ ** 0.9 and (n > 400 or len(parts) > 1):
                        out.append((x0 + ax, y0 + ay, x0 + bx + 1, y0 + by + 1))
    return out


def cutout(im, bb, thr=40):
    """RGBA výrez: pozadie spojené s okrajom → priehľadné."""
    c = im.crop(bb).convert("RGBA")
    w, h = c.size
    px = c.load()
    bg = (8, 14, 30)
    q = deque()
    mark = [[False] * w for _ in range(h)]
    for x in range(w):
        for y in (0, h - 1):
            q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            q.append((x, y))
    while q:
        x, y = q.popleft()
        if mark[y][x]:
            continue
        p = px[x, y]
        if dist(p, bg) > thr and max(p[:3]) > 38:
            continue
        mark[y][x] = True
        px[x, y] = (0, 0, 0, 0)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not mark[ny][nx]:
                q.append((nx, ny))
    # zvyšok deliacej čiary v spodných riadkoch (široký a tenký) preč
    for y in range(max(0, h - 5), h):
        if sum(1 for x in range(w) if px[x, y][3]) > 0.45 * w:
            for x in range(w):
                px[x, y] = (0, 0, 0, 0)
    # polopriehľadný okraj: tmavé pixely hneď vedľa priehľadných zjemniť
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a and max(r, g, b) < 55 and any(0 <= x + dx < w and 0 <= y + dy < h and px[x + dx, y + dy][3] == 0
                                               for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                px[x, y] = (r, g, b, 150)
    return c


def all_objects():
    res = []
    for sheet, bands in BANDS.items():
        im = Image.open(os.path.join(HERE, sheet + ".png")).convert("RGB")
        for bi, band in enumerate(bands):
            for bb in sorted(components(im, band, lines=bi % 3 != 0), key=lambda b: b[0]):
                res.append((sheet, bi, bb))
    return res


# výber: maskot → { snímka: (list, [x0, y0, x1, y1]) } — doplní sa po náhľade
VYBER_FILE = os.path.join(HERE, "vyber.json")


def main(a):
    if a[:1] == ["náhľad"] or a[:1] == ["nahlad"]:
        objs = all_objects()
        cols = 12
        cell = 110
        sheet = Image.new("RGBA", (cols * cell, ((len(objs) + cols - 1) // cols) * (cell + 14)), (40, 30, 24, 255))
        d = ImageDraw.Draw(sheet)
        listing = []
        for i, (sh, bi, bb) in enumerate(objs):
            im = Image.open(os.path.join(HERE, sh + ".png")).convert("RGB")
            c = cutout(im, bb)
            c.thumbnail((cell - 6, cell - 6))
            x, y = (i % cols) * cell, (i // cols) * (cell + 14)
            sheet.paste(c, (x + 3, y + 3), c)
            d.text((x + 3, y + cell - 2), "%d %s%d" % (i, sh[-1], bi), fill=(255, 220, 120))
            listing.append({"i": i, "sheet": sh, "band": bi, "box": bb})
        sheet.save(a[1])
        json.dump(listing, open(os.path.join(HERE, "objekty.json"), "w"), indent=0)
        print(len(objs), "objektov →", a[1])
        return 0
    if a[:1] == ["balíky"] or a[:1] == ["baliky"]:
        vyber = json.load(open(VYBER_FILE))
        objs = json.load(open(os.path.join(HERE, "objekty.json")))
        cache = {}
        for pet, spec in vyber.items():
            if pet.startswith("_"):
                continue
            outd = os.path.join(a[1], pet)
            os.makedirs(outd, exist_ok=True)
            for frame, idx in spec["frames"].items():
                o = objs[idx]
                if o["sheet"] not in cache:
                    cache[o["sheet"]] = Image.open(os.path.join(HERE, o["sheet"] + ".png")).convert("RGB")
                box = list(o["box"])
                cr = spec.get("crop", {}).get(frame)            # [x0, y0, x1, y1] ako podiel výrezu
                if cr:
                    bw, bh = box[2] - box[0], box[3] - box[1]
                    box = [int(box[0] + cr[0] * bw), int(box[1] + cr[1] * bh), int(box[0] + cr[2] * bw), int(box[1] + cr[3] * bh)]
                c = cutout(cache[o["sheet"]], tuple(box))
                bb = c.getbbox()
                if bb:
                    c = c.crop(bb)
                if spec.get("mirror", {}).get(frame):
                    c = c.transpose(Image.FLIP_LEFT_RIGHT)
                c.save(os.path.join(outd, frame + ".png"))
            meta = {k: v for k, v in spec.items() if k != "frames"}
            meta["frames"] = sorted(spec["frames"])
            json.dump(meta, open(os.path.join(outd, "pet.json"), "w"), ensure_ascii=False, indent=1)
            print(pet, len(spec["frames"]), "snímok")
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
