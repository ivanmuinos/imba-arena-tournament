class_name ControlBindings
extends RefCounted
## Local preferences only; the simulation still receives movement vectors and slot indices.

const ACTIONS := {
	"forward": "Avanzar", "back": "Retroceder", "left": "Girar izquierda", "right": "Girar derecha",
	"strafe_left": "Paso lateral izquierdo", "strafe_right": "Paso lateral derecho",
	"jump": "Saltar / confirmar área (mando)", "target": "Siguiente objetivo", "ally": "Siguiente aliado",
	"ally_0": "Aliado 1", "ally_1": "Aliado 2", "ally_2": "Aliado 3",
	"cancel": "Cancelar / soltar objetivo", "face": "Mirar al objetivo", "mute": "Silenciar",
	"orbit": "Seleccionar / orbitar cámara", "look": "Autoataque / mirar con cámara",
	"slot_0": "Habilidad 1", "slot_1": "Habilidad 2", "slot_2": "Habilidad 3", "slot_3": "Habilidad 4",
	"slot_4": "Habilidad 5", "slot_5": "Habilidad 6", "slot_6": "Habilidad 7",
}
var store: RefCounted

func _init(settings: RefCounted = null) -> void:
	store = settings if settings != null else SettingsStore.shared()

static func defaults() -> Dictionary:
	var out := {}
	for a in ACTIONS: out[a] = {"key": [], "pad": []}
	var keys := {"forward": [KEY_W, KEY_UP], "back": [KEY_S, KEY_DOWN], "left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT], "strafe_left": [KEY_Q], "strafe_right": [KEY_E], "jump": [KEY_SPACE], "target": [KEY_TAB], "cancel": [KEY_ESCAPE], "mute": [KEY_M], "ally_0": [KEY_F1], "ally_1": [KEY_F2], "ally_2": [KEY_F3]}
	for a in keys:
		for k in keys[a]: out[a].key.append("k:%d" % k)
	out.orbit.key = ["m:1"]
	out.look.key = ["m:2"]
	var pad := {"jump": JOY_BUTTON_A, "target": JOY_BUTTON_RIGHT_SHOULDER, "ally": JOY_BUTTON_LEFT_SHOULDER, "cancel": JOY_BUTTON_RIGHT_STICK, "face": JOY_BUTTON_LEFT_STICK}
	for a in pad: out[a].pad = ["p:%d" % pad[a]]
	for i in 7:
		out["slot_%d" % i].key = ["k:%d" % (KEY_1 + i)]
		out["slot_%d" % i].pad = ["p:%d" % [JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_B, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_RIGHT, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT][i]]
	return out

static func valid(token: String, channel: String) -> bool:
	var p := token.split(":")
	if p.size() != 2 or not p[1].is_valid_int(): return false
	var n := int(p[1])
	if channel == "pad": return p[0] == "p" and n >= 0 and n < JOY_BUTTON_MAX
	if p[0] == "m": return n in [1, 2, 3, 8, 9]
	return p[0] == "k" and n > 0 and n <= KEY_MAX and n not in [KEY_ENTER, KEY_KP_ENTER]

static func sanitize(raw: Variant) -> Dictionary:
	var out := defaults()
	if not raw is Dictionary: return out
	for channel in ["key", "pad"]:
		var candidate := out.duplicate(true)
		for a in ACTIONS:
			if not raw.get(a) is Dictionary: continue
			var entries = raw[a].get(channel)
			if not entries is Array or entries.size() > 2: continue
			if entries.all(func(t): return t is String and valid(t, channel)):
				candidate[a][channel] = entries.duplicate()
		var seen := []
		var collision := false
		for a in ACTIONS:
			for token in candidate[a][channel]:
				if seen.has(token): collision = true
				seen.append(token)
		if not collision: out = candidate
	return out

func bindings() -> Dictionary:
	var raw: Dictionary = store.get_value("bindings")
	return defaults() if raw.is_empty() else raw

func assign(a: String, channel: String, token: String) -> String:
	if not ACTIONS.has(a) or channel not in ["key", "pad"]: return "Acción inválida"
	if token in ["m:4", "m:5", "m:6", "m:7"]: return "La rueda sólo se usa para zoom"
	if token != "" and not valid(token, channel): return "Entrada reservada o no compatible"
	var data := bindings().duplicate(true)
	for other in ACTIONS:
		if other != a and token in data[other][channel]: return "Ya usado por: " + ACTIONS[other]
	data[a][channel] = [] if token == "" else [token]
	store.set_value("bindings", data)
	return ""

func reset() -> void:
	store.set_value("bindings", defaults())

static func token_for(event: InputEvent) -> String:
	if event is InputEventKey:
		return "k:%d" % (event.physical_keycode if event.physical_keycode != 0 else event.keycode)
	if event is InputEventMouseButton: return "m:%d" % event.button_index
	if event is InputEventJoypadButton: return "p:%d" % event.button_index
	return ""

func action(event: InputEvent) -> String:
	var token := token_for(event)
	var channel := "pad" if event is InputEventJoypadButton else "key"
	var data := bindings()
	for a in ACTIONS:
		if token in data[a][channel]: return a
	return ""

func held(a: String, device := -1) -> bool:
	var data := bindings()
	for token in data[a].key:
		var n := int(token.split(":")[1])
		if token.begins_with("k:") and Input.is_physical_key_pressed(n): return true
		if token.begins_with("m:") and Input.is_mouse_button_pressed(n): return true
	if device >= 0:
		for token in data[a].pad:
			if Input.is_joy_button_pressed(device, int(token.split(":")[1])): return true
	return false

func label(a: String, channel := "key") -> String:
	var names: Array[String] = []
	for token in bindings()[a][channel]:
		var n := int(token.split(":")[1])
		if token.begins_with("k:"): names.append(OS.get_keycode_string(n))
		elif token.begins_with("m:"): names.append("Mouse %d" % n)
		else: names.append(["A / Cross", "B / Circle", "X / Square", "Y / Triangle", "Back", "Guide", "Start", "L3", "R3", "LB", "RB", "↑", "↓", "←", "→"][n] if n < 15 else "Pad %d" % n)
	return " / ".join(names) if not names.is_empty() else "—"

static func slot_label(index: int) -> String:
	return ControlBindings.new().label("slot_%d" % index)
