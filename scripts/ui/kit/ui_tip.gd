class_name UiTip
extends PanelContainer
## Styled ability tooltip: name, key chip, cooldown/range line and description.

var _title: Label
var _key: Label
var _meta: Label
var _desc: Label
var _usage: Label
var _icon: TextureRect
var _tw: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiKit.glass_box(UiKit.LINE_STRONG, 12, 16, 1))
	material = UiKit.glass_material(3.6, 0.8)
	custom_minimum_size = Vector2(300, 0)
	visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_icon = Icons.rect("fireball", 56)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_icon.material = HudArt.circle_mask()  # the painted icons are round
	row.add_child(_icon)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_title = UiKit.heading("", 24, UiKit.INK, 700, 1)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_key = UiKit.heading("", 15, Color("#1a0800"), 700, 1, HORIZONTAL_ALIGNMENT_CENTER)
	_key.add_theme_stylebox_override("normal", UiKit.box(UiKit.GOLD, Color(0, 0, 0, 0), 5, 0, 5))
	head.add_child(_title)
	head.add_child(_key)
	col.add_child(head)
	_meta = UiKit.label("", 13, UiKit.GOLD)
	_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_meta.custom_minimum_size.x = 250
	col.add_child(_meta)
	_desc = UiKit.label("", 14, Color("#e6dccf"))
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(250, 0)
	col.add_child(_desc)
	_usage = UiKit.label("", 13, Color("#9edcfa"))
	_usage.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_usage.custom_minimum_size.x = 250
	col.add_child(_usage)


func set_ability(a: Dictionary, key: String) -> void:
	_icon.texture = Icons.tex(str(a.icon))
	_title.text = str(a.name)
	_title.add_theme_color_override("font_color", UiKit.GOLD if a.get("ult", false) else UiKit.INK)
	_key.text = key
	_meta.text = meta_line(a)
	_desc.text = str(a.desc).trim_prefix("DEFINITIVA: ")
	_usage.text = usage_line(a, key)
	reset_size()


static func usage_line(a: Dictionary, key: String) -> String:
	var action: String = {
		"auto": "Seleccioná un enemigo. Pulsá %s para activar o detener el autoataque.",
		"hostile": "Seleccioná un enemigo con clic o Tab y pulsá %s.",
		"friendly": "Seleccioná un aliado (F1–F3) y pulsá %s. Sin aliado, se aplica sobre vos.",
		"ground": "Pulsá %s y apuntá al suelo: clic izquierdo confirma; clic derecho o Esc cancela.",
		"self": "Pulsá %s: se aplica sobre vos o alrededor tuyo.",
		"direction": "Orientá tu personaje y pulsá %s: se usa en la dirección indicada por la habilidad.",
	}.get(SpellKinds.kind(a), "Pulsá %s.")
	return action % key


## "Recarga 6 s · Alcance 18 m" (ultimates say "Definitiva").
static func meta_line(a: Dictionary) -> String:
	var parts: Array = []
	if a.get("ult", false):
		parts.append("Definitiva (una vez por partida)")
	elif int(a.get("cd", 0)) > 0:
		parts.append("Recarga %s s" % _num(float(a.cd) / 1000.0))
	else:
		parts.append("Sin recarga")
	if float(a.get("cast", 0)) > 0.0:
		parts.append("Lanzamiento %s s" % _num(float(a.cast) / 1000.0))
	if float(a.get("range", 0)) > 0.0:
		parts.append("Alcance %s m" % _num(float(a.range)))
	return " · ".join(parts)


static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


func pop(at: Vector2) -> void:
	position = at
	if _tw != null:
		_tw.kill()
	visible = true
	modulate.a = 0.0
	_tw = create_tween().set_parallel(true)
	_tw.tween_property(self, "modulate:a", 1.0, 0.12)
	_tw.tween_property(self, "position:y", at.y, 0.12).from(at.y + 8.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func hush() -> void:
	if _tw != null:
		_tw.kill()
	visible = false
