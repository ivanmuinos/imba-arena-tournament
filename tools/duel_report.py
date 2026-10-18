#!/usr/bin/env python3
"""Merges duel JSON files and prints the 1v1 win-rate matrix (row beats column) plus the mean time to the first kill."""
import glob, json, sys
d = sys.argv[1]
duel, ttk = {}, {}
for f in glob.glob(d + "/*.json"):
    try:
        j = json.load(open(f))
    except Exception:
        continue
    for k, (w, g) in j["duel"].items():
        a = duel.setdefault(k, [0, 0]); a[0] += w; a[1] += g
    for k, (t, g) in j["ttk"].items():
        a = ttk.setdefault(k, [0.0, 0]); a[0] += t; a[1] += g
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
