extends SceneTree
## Ability icons from the reference sheet (referencias/referencia_iconos.png), 128 px, one per id in MAP:
##   godot --headless --script res://tools/slice_reference_icons.gd -- <sheet.png> <out_dir>   (copy the PNGs to assets/icons)
# Cuts the reference sheet into 128 px ability icons. Each cell is cropped tighter than the drawn rune circle
# (ZOOM), so the subject fills the button like the polymorph sheep; TUNE nudges single icons.
const ROWS := [[3, 111], [131, 239], [259, 367], [387, 494], [512, 594], [615, 698], [719, 801], [820, 903], [922, 1006]]
const COLS_A := [[4, 123], [132, 252], [260, 379], [388, 507], [515, 635], [643, 764], [771, 891], [899, 1019]]
const COLS_R4 := [[2, 99], [102, 161], [163, 252], [256, 345], [349, 409], [418, 507], [512, 613], [627, 706], [728, 808], [825, 915], [925, 1020]]
const MAP := [
	["power_crit", "power_stealth", "power_shield", "power_haste", "power_heal", "fireball", "pyro", "nova"],
	["blink", "counter", "meteor", "dragonbreath", "frostbolt", "icelance", "blizzard", "shadowbolt"],
	["corruption", "agony", "fear", "soulrot", "shot", "aimed", "trap", "conc"],
	["disengage", "silence", "volley", "mortal", "charge", "hamstring", "shieldwall", "bladestorm"],
	["heal", "", "pwshield", "scream", "renew", "dispel", "hymn", "stab", "eviscerate", "cheapshot", "blind"],
	["vanish", "kick", "deathmark", "", "wrath", "regrowth", "ironbark", "cyclone", "naturescure", "tranquility"],
	["rifle", "headshot", "flashbang", "kevlar", "knife", "awp", "tempest", "windwall", "flow", "lastbreath"],
	["pass", "chip", "nutmeg", "dribble", "onetwo", "tackle", "golazo", "stunbolt", "disarm", "wardshield"],
	["broom", "confuse", "guardian", "punch", "kiblast", "flashstep", "kiguard", "awaken", "palm", "kiwave"],
]
const ZOOM_CIRCLE := 0.74  # rows 0-3: the circle fills the cell; keep its inside
const ZOOM_FLAT := 0.92
var TUNE := {  # id -> [zoom, dx, dy] (dx, dy in source px): circled icons of row 5 cropped inside the rune ring
	"vanish": [0.76, 0, 0], "kick": [0.76, 0, 0], "deathmark": [0.76, 0, 0], "wrath": [0.76, 0, 0], "regrowth": [0.76, 0, 0],
	"ironbark": [0.76, 0, 0], "cyclone": [0.76, 0, 0], "naturescure": [0.76, 0, 0], "blind": [0.82, -3, 0]}

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var src := Image.load_from_file(a[0])
	src.convert(Image.FORMAT_RGBA8)
	var sheet := Image.create(10 * 64 + 8, 9 * 64 + 8, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#2a1810"))
	for r in MAP.size():
		var row: Array = MAP[r]
		var y0: int = ROWS[r][0]; var y1: int = ROWS[r][1]
		for c in row.size():
			var id: String = row[c]
			if id == "":
				continue
			var xr: Array
			if r < 4: xr = COLS_A[c]
			elif r == 4: xr = COLS_R4[c]
			else: xr = [int(c * 102.4) + 2, int((c + 1) * 102.4) - 2]
			var cx: float = (xr[0] + xr[1]) / 2.0
			var cy: float = (y0 + y1) / 2.0
			var side: float = float(maxi(xr[1] - xr[0], y1 - y0)) if r < 4 else float(y1 - y0)
			var z: float = ZOOM_CIRCLE if r < 4 else ZOOM_FLAT
			var t: Array = TUNE.get(id, [])
			if t.size() == 3:
				z = t[0]; cx += t[1]; cy += t[2]
			var s := side * z
			var rect := Rect2i(int(cx - s / 2), int(cy - s / 2), int(s), int(s))
			rect = rect.intersection(Rect2i(0, 0, src.get_width(), src.get_height()))
			var ic := src.get_region(rect)
			ic.resize(128, 128, Image.INTERPOLATE_LANCZOS)
			ic.save_png(a[1].path_join(id + ".png"))
			var sm := ic.duplicate()
			sm.resize(56, 56, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(sm, Rect2i(0, 0, 56, 56), Vector2i(8 + c * 64 if r != 4 else 8 + c * 58, 8 + r * 64))
	sheet.save_png(a[1].path_join("_sheet.png"))
	quit()
