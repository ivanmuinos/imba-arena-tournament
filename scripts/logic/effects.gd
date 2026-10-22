class_name Effects
extends RefCounted
## Crowd-control / buff descriptions for the HUD (port of src/debuffs.ts).
## An effect is {key, icon, name, ms, color: Color, loc, good}; `loc` = takes control away.

## Buffs from class abilities (power-up buffs come from GameData.powers).
const CLASS_BUFFS := {
	"darkpact": {"icon": "darkpact", "name": "Pacto oscuro", "color": 0xb18ae8},
	"wall": {"icon": "fx_wall", "name": "Muro de escudo (−60% daño)", "color": 0xc9ced6},
	"absorb": {"icon": "fx_absorb", "name": "Absorción", "color": 0xffd27a},
	"hot": {"icon": "fx_hot", "name": "Renovar", "color": 0x5cff8a},
	"storm": {"icon": "fx_storm", "name": "Filotormenta", "color": 0xffd166},
}


## Tooltip text per effect key (what it does to whoever carries it).
const DESC := {
	"corruption": "Maldición: daño continuo por segundo. Se puede disipar. Refrescarla no acumula daño.",
	"agony": "Maldición: daño continuo por segundo. Coexiste con Corrupción y se puede disipar.",
	"soulrot": "Maldición definitiva: daño continuo muy alto. Se puede disipar.",
	"darkpact": "Absorbe daño recibido mientras dura. No te libera de ningún control.",
	"fear": "Huís sin control y no podés lanzar nada. El daño recibido lo rompe (más de 40).",
	"stun": "No podés moverte ni lanzar hechizos.",
	"silence": "No podés lanzar hechizos (las habilidades físicas sí).",
	"root": "No podés moverte, pero sí atacar y lanzar.",
	"slow": "Te movés más lento.",
	"burn": "Daño por segundo de fuego.",
	"mortal": "La curación que recibís se reduce a la mitad.",
	"marked": "Recibís 40% más de daño.",
	"incap": "Incapacitado: el daño recibido rompe el efecto.",
	"wall": "Recibís 60% menos de daño.",
	"absorb": "Un escudo absorbe el próximo daño.",
	"hot": "Curación por segundo.",
	"storm": "Girás golpeando a todos los cercanos. Inmune al control.",
	"damp": "La curación recibida baja cada vez más con el tiempo de combate.",
}


static func _fx(key: String, icon: String, fx_name: String, ms: float, color: Color, loc: bool, good: bool) -> Dictionary:
	return {"key": key, "icon": icon, "name": fx_name, "ms": ms, "color": color, "loc": loc, "good": good, "desc": DESC.get(key, "")}


## Ordered by severity, the way WoW's loss-of-control alert picks what to show.
static func debuffs_of(cc: Dictionary) -> Array:
	var out: Array = []
	for id in ["corruption", "agony", "soulrot"]:
		if cc.has(id):
			var names := {"corruption": "Corrupción", "agony": "Agonía", "soulrot": "Putrefacción del alma"}
			out.append(_fx(id, id, names[id], cc[id], Color("#b18ae8"), false, false))
	if cc.has("incap"):
		var kind: String = cc.get("incapKind", "freeze")
		var d: Array = ["fx_disorient", "Ciclón", "#9fe8a0"] if kind == "cyclone" else ["fx_disorient", "Desorientado", "#ffb060"] if kind == "disorient" else ["fx_poly", "Polimorfia", "#f0e6ff"] if kind == "poly" else (["fx_blind", "Cegado", "#b0a8c0"] if kind == "blind" else ["fx_freeze", "Congelado", "#9be7ff"])
		out.append(_fx("incap", d[0], d[1], cc.incap, Color(d[2]), true, false))
	if cc.has("fear"): out.append(_fx("fear", "fx_fear", "Aterrorizado", cc.fear, Color("#c77dff"), true, false))
	if cc.has("stun"): out.append(_fx("stun", "fx_stun", "Aturdido", cc.stun, Color("#ffd166"), true, false))
	if cc.has("silence"): out.append(_fx("silence", "fx_silence", "Silenciado", cc.silence, Color("#c77dff"), true, false))
	if cc.has("root"): out.append(_fx("root", "fx_root", "Enraizado", cc.root, Color("#7fdbff"), true, false))
	if cc.has("slow"): out.append(_fx("slow", "fx_slow", "Ralentizado", cc.slow, Color("#4da3ff"), false, false))
	if cc.has("burn"): out.append(_fx("burn", "fx_burn", "Quemadura", cc.burn, Color("#ff7a2a"), false, false))
	if cc.has("mortal"): out.append(_fx("mortal", "fx_mortal", "Herida mortal (−50% curación)", cc.mortal, Color("#ff4d4d"), false, false))
	if cc.has("marked"): out.append(_fx("marked", "fx_marked", "Marcado (+40% daño recibido)", cc.marked, Color("#ff2a2a"), false, false))
	return out


## Dampening debuff shown on every unit once it starts (healing received is reduced by `damp`, 0..1). `text` replaces the timer.
static func damp_effect(damp: float) -> Array:
	if damp <= 0.0:
		return []
	var pct := int(roundf(damp * 100.0))
	var e := _fx("damp", "fx_damp", "Amortiguación (−%d%% curación recibida)" % pct, 0.0, Color("#b890e8"), false, false)
	e["text"] = "%d%%" % pct
	e["desc"] = "El combate se alarga: la curación recibida baja un %d%% y sigue bajando cada segundo." % pct
	return [e]


static func buffs_of(b: Dictionary) -> Array:
	var out: Array = []
	for k in b:
		var spec: Dictionary = GameData.powers[k] if GameData.powers.has(k) else CLASS_BUFFS.get(k, {})
		if spec.is_empty():
			continue
		var e := _fx(k, spec.icon, spec.name, b[k], Color.hex(int(spec.color) << 8 | 0xff), false, true)
		if e.desc == "" and spec.has("desc"):
			e.desc = spec.desc
		out.append(e)
	return out


static func secs(ms: float) -> String:
	return str(ceili(ms / 1000.0)) if ms >= 10000 else "%.1f" % (ms / 1000.0)
