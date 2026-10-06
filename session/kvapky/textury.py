#!/usr/bin/env python3
# Textúry materiálov pre okná Goo (1. 10. 2026): „reálna textúra aspoň na časť povrchu okien“ (používateľ).
# Zdroj: voľné textúry CC0 z ambientCG (https://ambientcg.com, licencia CC0 1.0) — brúsený hliník Metal009, matné
# striebro so šmuhami Metal010; tepaný kov (zlato) je vygenerovaný: výšková mapa z jamiek po kladive, nasvietená.
# Každá textúra sa zafarbí farbou okien témy a smerom k uchu kvapky (káva) sa vytratí: _v = ucho dole (pre ucho hore
# ju scéna otočí o 180°), _h = ucho vľavo (vpravo otočí). Výstup: session/kvapky/textury/<téma>_{v,h}.webp
# Použitie: python3 session/kvapky/textury.py   (sťahuje do ~/.cache/latteos/textury)
import io, os, random, urllib.request, zipfile
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "textury")
CACHE = os.path.expanduser("~/.cache/latteos/textury")
W, H = 640, 560                     # karta spúšťača (dw × dh)
ALPHA = 0.84                        # textúra nie je úplne krycia: cez sklo karty presvitá rozmazané pozadie

def ambientcg(asset):
    """Farebná mapa textúry z ambientCG (1K, CC0), stiahnutá raz do vyrovnávacej pamäte."""
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, f"{asset}_Color.jpg")
    if not os.path.exists(path):
        url = f"https://ambientcg.com/get?file={asset}_1K-JPG.zip"
        data = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "LatteOS"}), timeout=60).read()
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            name = next(n for n in z.namelist() if n.endswith("_Color.jpg"))
            open(path, "wb").write(z.read(name))
    return Image.open(path).convert("L")

def cover(img, w, h):
    """Zväčší a oreže na w × h (bez deformácie)."""
    s = max(w / img.width, h / img.height)
    img = img.resize((int(img.width * s + 0.5), int(img.height * s + 0.5)), Image.LANCZOS)
    x, y = (img.width - w) // 2, (img.height - h) // 2
    return img.crop((x, y, x + w, y + h))

def hammered(w, h, seed=7):
    """Tepaný kov: jamky po kladive (prekrývajúce sa misky rôznej veľkosti), nasvietené zhora zľava.
    Kreslí sa s okrajom 40 px, ktorý sa odreže (filter reliéfu robí na okrajoch pásy)."""
    return _hammered(w + 80, h + 80, seed).crop((40, 40, w + 40, h + 40))

def _hammered(w, h, seed):
    rnd = random.Random(seed)
    height = Image.new("L", (w, h), 255)
    dent = Image.radial_gradient("L")                    # 0 v strede → 255 na okraji: miska
    for _ in range(int(w * h / 1400)):
        r = rnd.randint(18, 40)
        d = dent.resize((2 * r, 2 * r))
        x, y = rnd.randint(-r, w - r), rnd.randint(-r, h - r)
        region = height.crop((x, y, x + 2 * r, y + 2 * r))
        height.paste(ImageChops.darker(region, d), (x, y))   # hlbšia jamka vyhráva (ako pri skutočnom tepaní)
    height = height.filter(ImageFilter.GaussianBlur(4.5))           # plôšky po kladive sú zaoblené, nie ostré
    relief = height.filter(ImageFilter.EMBOSS).filter(ImageFilter.GaussianBlur(1.2))
    relief = ImageOps.autocontrast(relief, cutoff=0.5)
    # jemné stopy leštenia navrch
    grain = Image.effect_noise((w, h // 8), 24).resize((w, h)).filter(ImageFilter.GaussianBlur(0.6))
    return ImageChops.blend(relief, grain, 0.12)

def hexrgb(c):
    c = c.lstrip("#")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))

def shade(rgb, f):
    return tuple(max(0, min(255, int(v * f))) for v in rgb)

def colorize(gray, base, lo=0.80, hi=1.10, contrast=1.0):
    """Svetlosť textúry → farba okien témy (tmavšia a svetlejšia okolo nej)."""
    g = ImageOps.autocontrast(gray, cutoff=0.5)
    if contrast != 1.0:
        g = Image.eval(g, lambda v: max(0, min(255, int(128 + (v - 128) * contrast))))
    rgb = hexrgb(base)
    return ImageOps.colorize(g, black=shade(rgb, lo), white=shade(rgb, hi), mid=rgb)

def fade(w, h, horizontal):
    """Priehľadnosť: plná ďaleko od ucha, k uchu (dole / vľavo) sa vytratí — tam je káva."""
    ramp = Image.linear_gradient("L")                    # 0 hore → 255 dole
    if horizontal:
        ramp = ramp.rotate(-90)                          # 0 vpravo → 255 vľavo
    ramp = ramp.resize((w, h))
    # 0 … 45 % plná, 45 … 82 % sa vytráca, ďalej nič
    return Image.eval(ramp, lambda v: int(255 * ALPHA * max(0.0, min(1.0, (0.82 - v / 255) / 0.37))))

MATERIALS = {
    # téma: (zdroj, farba okien témy, rozsah svetlosti, kontrast)
    "hlinik":   (lambda w, h: cover(ambientcg("Metal009"), w, h), "#D9DDE1", 0.78, 1.12, 1.6),
    "striebro": (lambda w, h: cover(ambientcg("Metal010"), w, h), "#E6E9EC", 0.82, 1.08, 1.0),
    "zlato":    (hammered, "#E3C98F", 0.66, 1.14, 1.0),
}

os.makedirs(OUT, exist_ok=True)
for theme, (src, base, lo, hi, k) in MATERIALS.items():
    for suffix, horizontal in (("v", False), ("h", True)):
        tex = colorize(src(W, H), base, lo, hi, k).convert("RGBA")
        tex.putalpha(fade(W, H, horizontal))
        path = os.path.join(OUT, f"{theme}_{suffix}.webp")
        tex.save(path, "WEBP", quality=86, method=6)
        print(path, os.path.getsize(path) // 1024, "kB")
