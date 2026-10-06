#!/usr/bin/env python3
# Slovenský katalóg Noctalie (1. 10. 2026, LATTEOS-GOO.md pred 6. 10. §7 A6, docs_zaloha/2026-10-06-latteos-goo-pred-rozdelenim.md): Noctalia hľadá translations/<jazyk>.json a bez
# neho beží celá po anglicky — a preklady doplnkov (plugins/*/translations/sk.json) vôbec nenačíta. Tento skript
# zlúči dávky prekladov (sk-*.tsv: kľúč<TAB>text, \n = nový riadok) so súčasným sk.json a zapíše sk.json v poradí
# kľúčov anglického katalógu; čo nie je preložené, Noctalia vezme z angličtiny (kľúč po kľúči).
# Inštalácia: setup/f1/install-session.sh → /usr/share/noctalia/assets/translations/sk.json
# Použitie: python3 session/noctalia/translations/zluc.py
import glob, json, os

HERE = os.path.dirname(os.path.abspath(__file__))
EN = "/usr/share/noctalia/assets/translations/en.json"
OUT = os.path.join(HERE, "sk.json")


def flat(node, prefix=""):
    for k, v in node.items():
        key = f"{prefix}.{k}" if prefix else k
        if isinstance(v, dict):
            yield from flat(v, key)
        else:
            yield key, v


en = json.load(open(EN, encoding="utf-8"))
sk = dict(flat(json.load(open(OUT, encoding="utf-8")))) if os.path.exists(OUT) else {}
for path in sorted(glob.glob(os.path.join(HERE, "sk-*.tsv"))):
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if "\t" in line:
            k, v = line.split("\t", 1)
            sk[k] = v.replace("\\n", "\n")
# texty bez slov (iba zástupné znaky) ostanú ako v angličtine
en_flat = dict(flat(en))
for k, v in en_flat.items():
    if k not in sk and not any(c.isalpha() for c in v.replace("{when}", "").replace("{location}", "")):
        sk[k] = v


def build(node, prefix=""):
    out = {}
    for k, v in node.items():
        key = f"{prefix}.{k}" if prefix else k
        if isinstance(v, dict):
            sub = build(v, key)
            if sub:
                out[k] = sub
        elif key in sk:
            out[k] = sk[key]
    return out


unknown = sorted(k for k in sk if k not in en_flat)
json.dump(build(en), open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
done = sum(1 for k in en_flat if k in sk)
print(f"sk.json: {done} / {len(en_flat)} textov ({100 * done // len(en_flat)} %)" + (f"; neznáme kľúče: {unknown}" if unknown else ""))
