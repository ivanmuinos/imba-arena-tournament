#!/usr/bin/env python3
"""Merges balance_sim JSON files from a directory and prints markdown tables (class win rates overall / by mode / by map, 2v2 pairings)."""
import glob, json, math, sys
d = sys.argv[1]
agg = {}
matches = unfinished = 0
durs = []
for f in glob.glob(d + "/*.json"):
    try:
        j = json.load(open(f))
    except Exception:
        continue
    matches += j["matches"]; unfinished += j["unfinished"]; durs += j.get("durations", [])
    for k, (w, g) in j["stats"].items():
        a = agg.setdefault(k, [0, 0]); a[0] += w; a[1] += g
classes = sorted({k.split("|")[1] for k in agg if k.startswith("all|")})
def rate(k):
    w, g = agg.get(k, [0, 0]); return (100.0 * w / g if g else float("nan")), g
def ci(k):
    w, g = agg.get(k, [0, 0]); return 196.0 * math.sqrt(0.25 / g) if g else 0
print(f"matches: {matches}, unfinished: {unfinished}\n")
if durs:
    durs.sort()
    print(f"Duración de pelea por partida (s, sin pausas): media {sum(durs)/len(durs):.0f}, mediana {durs[len(durs)//2]:.0f}, p90 {durs[int(len(durs)*0.9)]:.0f}, máx {durs[-1]:.0f}; partidas > 180 s: {100.0*sum(1 for d in durs if d>180)/len(durs):.0f}%\n")
print("| Clase | Win rate | +/- (95%) | Partidas-clase |\n|---|---|---|---|")
for c in classes:
    r, g = rate("all|" + c); print(f"| {c} | {r:.1f}% | {ci('all|'+c):.1f} | {g} |")
for title, prefix, keys in (("Por modo", "mode", ["mode2", "mode3"]), ("Por mapa", "map_", ["map_bridge", "map_pillars", "map_tomb", "map_living"])):
    print(f"\n### {title}\n\n| Clase | " + " | ".join(keys) + " |\n|---|" + "---|" * len(keys))
    for c in classes:
        print(f"| {c} | " + " | ".join(f"{rate(k+'|'+c)[0]:.1f}%" for k in keys) + " |")
pairs = sorted((k for k in agg if k.startswith("pair|")), key=lambda k: -rate(k)[0])
print("\n### Parejas 2v2 (min. 15 partidas)\n\n| Pareja | Win rate | N |\n|---|---|---|")
for k in pairs:
    r, g = rate(k)
    if g >= 15: print(f"| {k[5:]} | {r:.1f}% | {g} |")
