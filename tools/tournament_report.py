#!/usr/bin/env python3
"""Merges tournament_sim JSON files: win rate and match length per mode x tier, per round, and an estimated cup win rate
(the product of the three round win rates, with Bronze/Silver's free rematch counted as a second try per run)."""
import glob, json, math, sys
cells, n, skill = {}, 0, None
for f in glob.glob(sys.argv[1] + "/*.json"):
    try:
        j = json.load(open(f))
    except Exception:
        continue
    skill = j.get("player_skill", skill); n = j.get("n", n)
    for k, v in j["cells"].items():
        a = cells.setdefault(k, {"n": 0, "wins": 0, "unfinished": 0, "total_s": 0.0, "fight_s": 0.0})
        for key in a: a[key] += v[key]
tiers = ["bronze", "silver", "gold", "gladiator"]
rematch = {"bronze": 1, "silver": 1, "gold": 0, "gladiator": 0}
def rate(c):
    return c["wins"] / c["n"] if c["n"] else None
def pct(x):
    return "-" if x is None else f"{100*x:.0f}%"
print(f"Proxy: bot con skill {skill}, {n} partidas por celda (modalidad x nivel x ronda)\n")
print("| modalidad | nivel | cuartos | semifinal | final | copa estimada | partida media (s) | pelea media (s) | sin terminar |")
print("|---|---|---|---|---|---|---|---|---|")
for mode in (1, 2, 3):
    for t in tiers:
        rs = [cells.get(f"{mode}|{t}|{r}") for r in range(3)]
        if any(c is None or c["n"] == 0 for c in rs):
            continue
        p = [rate(c) for c in rs]
        # a loss with a rematch retries the same round once per run: P(clear round) = p + (1-p)*p for the one round that uses it; approximated on the weakest round
        cup = p[0] * p[1] * p[2]
        if rematch[t]:
            worst = min(range(3), key=lambda i: p[i])
            q = list(p); q[worst] = p[worst] + (1 - p[worst]) * p[worst]
            cup = q[0] * q[1] * q[2]
        done = sum(c["n"] - c["unfinished"] for c in rs)
        total = sum(c["total_s"] for c in rs) / done if done else 0
        fight = sum(c["fight_s"] for c in rs) / done if done else 0
        unf = sum(c["unfinished"] for c in rs)
        print(f"| {mode}v{mode} | {t} | {pct(p[0])} | {pct(p[1])} | {pct(p[2])} | {pct(cup)} | {total:.0f} | {fight:.0f} | {unf} |")
tot_n = sum(c["n"] for c in cells.values())
print(f"\nPartidas simuladas: {tot_n}. Margen de error al 95% por celda de ronda: hasta +/-{98/math.sqrt(max(n, 1)):.0f} puntos (peor caso, 50%).")
