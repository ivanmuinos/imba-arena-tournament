#!/usr/bin/env python3
"""Merges duel JSON files and prints the 1v1 win-rate matrix (row beats column), the mean time to the first kill and, per pair, the time-limit / draw / unfinished / match-length metrics."""
import glob, json, sys
d = sys.argv[1]
duel, ttk, meta = {}, {}, {}
for f in glob.glob(d + "/*.json"):
    try:
        j = json.load(open(f))
    except Exception:
        continue
    for k, (w, g) in j["duel"].items():
        a = duel.setdefault(k, [0, 0]); a[0] += w; a[1] += g
    for k, (t, g) in j["ttk"].items():
        a = ttk.setdefault(k, [0.0, 0]); a[0] += t; a[1] += g
    for k, v in j.get("meta", {}).items():
        a = meta.setdefault(k, [0] * 5 + [0.0] + [0] * 5)
        for i, x in enumerate(v): a[i] += x
names = sorted({k.split("|")[0] for k in duel})
print("| fila vs columna | " + " | ".join(names) + " |")
print("|---|" + "---|" * len(names))
for a in names:
    cells = []
    for b in names:
        w, g = duel.get(a + "|" + b, [0, 0])
        cells.append(f"{100.0*w/g:.0f}%" if g else "-")
    print(f"| {a} | " + " | ".join(cells) + " |")
print("\nTiempo medio hasta la primera baja (s), fila contra columna:\n")
print("| fila vs columna | " + " | ".join(names) + " |")
print("|---|" + "---|" * len(names))
for a in names:
    cells = []
    for b in names:
        t, g = ttk.get(a + "|" + b, [0.0, 0])
        cells.append(f"{t/g:.1f}" if g else "-")
    print(f"| {a} | " + " | ".join(cells) + " |")

# Per unordered pair (both directions merged). Columns: duels, unfinished (no result in 12 min), rounds, rounds ended at the
# 180 s limit, draw rounds, mean fight length of finished duels, and how often the higher-max-HP side won a decided limit round.
print("\nMétricas por pareja (ambas direcciones sumadas; largo = segundos de pelea sin pausas, solo duelos terminados):\n")
print("| pareja | duelos | sin terminar | rondas | rondas al límite | empates | largo medio (s) | límite: gana más HP máx |")
print("|---|---|---|---|---|---|---|---|")
pairs = {}
for k, v in meta.items():
    a, b = k.split("|")
    t = pairs.setdefault(tuple(sorted((a, b))), [0] * 5 + [0.0] + [0] * 5)
    for i, x in enumerate(v): t[i] += x
tot = [0] * 5 + [0.0] + [0] * 5
for (a, b), v in sorted(pairs.items()):
    for i, x in enumerate(v): tot[i] += x
    fin = v[0] - v[1]
    mean = f"{v[5]/fin:.0f}" if fin else "-"
    hi = f"{100.0*v[7]/v[6]:.0f}% ({v[7]}/{v[6]})" if v[6] else "-"
    lim = f"{100.0*v[3]/v[2]:.0f}% ({v[3]})" if v[2] else "-"
    print(f"| {a} vs {b} | {v[0]} | {v[1]} | {v[2]} | {lim} | {v[4]} | {mean} | {hi} |")
fin = tot[0] - tot[1]
if tot[0]:
    print(f"\nTotal: {tot[0]} duelos, {tot[1]} sin terminar, {tot[2]} rondas, {100.0*tot[3]/max(tot[2],1):.1f}% al límite, {tot[4]} empates, largo medio {tot[5]/max(fin,1):.0f} s; límite decidido a favor de más HP máx: {tot[7]}/{tot[6]}")
    print(f"Rondas al límite con ganador por HP absoluto: {tot[8]}; el ganador por % de HP sería el otro equipo en {tot[9]} y habría empate en {tot[10]}")
print("\nWin rate global por variante (contra todas las demás, sin espejo):\n")
print("| variante | win rate | duelos |")
print("|---|---|---|")
for a in names:
    w = g = 0
    for b in names:
        if a == b: continue
        x, y = duel.get(a + "|" + b, [0, 0]); w += x; g += y
        x, y = duel.get(b + "|" + a, [0, 0]); w += y - x; g += y
    if g: print(f"| {a} | {100.0*w/g:.1f}% | {g} |")
