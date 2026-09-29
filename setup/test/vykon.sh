#!/usr/bin/env bash
# Meranie výkonu relácie LatteOS (ROADMAP fáza O): CPU za N sekúnd a skutočná pamäť (PSS) procesov LatteOS.
# Nemení nič v relácii. Výsledok vypíše a uloží do ~/.local/state/latteos/vykon/<čas>-<commit>.txt na porovnanie.
#   setup/test/vykon.sh [sekundy] [poznámka]      napr.  setup/test/vykon.sh 20 "po zlúčení démonov"
repo="$(cd "$(dirname "$0")/../.." && pwd)"
exec python3 - "${1:-15}" "${2:-}" "$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo ?)" <<'PY'
import os, re, sys, time
secs, note, rev = float(sys.argv[1]), sys.argv[2], sys.argv[3]
hz = os.sysconf("SC_CLK_TCK")
def cmd(p):
    try: return open(f"/proc/{p}/cmdline", "rb").read().replace(b"\0", b" ").decode(errors="replace").strip()
    except OSError: return ""
def name(c):
    if c.startswith("qs -n -p"): return os.path.basename(c.split()[3]).removesuffix(".qml")
    if "python3" in c.split()[0]: return os.path.basename(next((a for a in c.split()[1:] if not a.startswith("-")), "python"))
    return os.path.basename(c.split()[0])
want = re.compile(r"^(Hyprland|noctalia|qs -n -p|/usr/bin/python3 .*latte|/usr/libexec/latteos/|/usr/bin/(pipewire|wireplumber))")
pids = [p for p in os.listdir("/proc") if p.isdigit() and want.search(cmd(p))]
def ticks(p):
    try: f = open(f"/proc/{p}/stat").read().rsplit(")", 1)[1].split(); return int(f[11]) + int(f[12])
    except OSError: return None
def sysstat():
    f = [int(x) for x in open("/proc/stat").readline().split()[1:]]
    return sum(f), f[3] + f[4]            # spolu, nečinnosť (idle + iowait)
t0 = {p: ticks(p) for p in pids}
s0 = sysstat()
time.sleep(secs)
s1 = sysstat()
ncpu = os.cpu_count() or 1
system = (1 - (s1[1] - s0[1]) / max(1, s1[0] - s0[0])) * 100 * ncpu   # v % jedného jadra, ako top
rows = []
for p in pids:
    t1 = ticks(p)
    if t1 is None or t0[p] is None: continue
    try: pss = int(re.search(r"^Pss:\s+(\d+)", open(f"/proc/{p}/smaps_rollup").read(), re.M).group(1)) / 1024
    except (OSError, AttributeError): pss = None
    rows.append((name(cmd(p)), (t1 - t0[p]) / hz / secs * 100, pss))
rows.sort(key=lambda r: -r[1])
tier = re.search(r'tier = "(\w+)"', open("/run/latteos/mode.toml").read()) if os.path.exists("/run/latteos/mode.toml") else None
lines = [f"LatteOS výkon · {time.strftime('%F %T')} · commit {rev} · {secs:g} s · stupeň {tier.group(1) if tier else '?'}" + (f" · {note}" if note else ""),
         f"{'proces':<22}{'CPU %':>8}{'PSS MB':>10}"]
lines += [f"{n:<22}{c:>8.1f}{(f'{m:.1f}' if m is not None else '—'):>10}" for n, c, m in rows]
lines.append(f"{'SPOLU':<22}{sum(r[1] for r in rows):>8.1f}{sum(r[2] or 0 for r in rows):>10.1f}")
lines.append(f"{'CELÝ SYSTÉM':<22}{system:>8.1f}          (vrátane krátkych procesov; {ncpu} jadrá = {ncpu*100} %)")
out = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "latteos", "vykon")
os.makedirs(out, exist_ok=True)
path = os.path.join(out, time.strftime("%Y%m%d-%H%M%S") + f"-{rev}.txt")
open(path, "w").write("\n".join(lines) + "\n")
print("\n".join(lines)); print(f"(uložené: {path})")
PY
