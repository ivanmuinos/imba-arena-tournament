class_name Nameplate
extends Control
## Name, health bar, cast bar and CC icons floating over a fighter (WoW nameplate).

const W := 112.0

var _name: Label
var _hp_bg: Panel
var _hp: ColorRect
var _cast_bg: Panel
var _cast: ColorRect
var _auras: AuraRow
var _ally := false
var _hp_color := Color("#4caf50")
var targeted := false
var _border := Color.TRANSPARENT


func setup(p_name: String, ally: bool, is_me: bool, team_color: Color) -> Nameplate:
	_ally = ally
	custom_minimum_size = Vector2(W, 44)
	size = Vector2(W, 44)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hp_color = Color("#4caf50") if ally else team_color
	_auras = AuraRow.new().setup(20)
	_auras.position = Vector2(0, 0)
	_auras.size = Vector2(W, 20)
	_auras.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_auras)
	_name = UiKit.label(p_name, 13, Color("#ffd27a") if is_me else (Color("#bfe0ff") if ally else Color("#ffb3b3")), HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.outlined(_name, 5)
	_name.position = Vector2(0, 20)
	_name.size = Vector2(W, 16)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name)
	_hp_bg = Panel.new()
	_hp_bg.position = Vector2(4, 36)
	_hp_bg.size = Vector2(W - 8, 8)
	_hp_bg.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.7), Color(0, 0, 0, 0.9), 3, 1, 0))
	_hp_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp_bg)
	_hp = ColorRect.new()
	_hp.color = _hp_color
	_hp.position = Vector2(5, 37)
	_hp.size = Vector2(W - 10, 6)
	_hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hp)
	_cast_bg = Panel.new()
	_cast_bg.position = Vector2(14, 46)
	_cast_bg.size = Vector2(W - 28, 5)
	_cast_bg.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.7), Color(0, 0, 0, 0.9), 2, 1, 0))
	_cast_bg.visible = false
	_cast_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cast_bg)
	_cast = ColorRect.new()
	_cast.color = Color("#ffd166")
	_cast.position = Vector2(15, 47)
	_cast.size = Vector2(0, 3)
	_cast.visible = false
	_cast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cast)
	return self


func update_state(hp_ratio: float, cast, effects: Array, loc_color) -> void:
	_hp.size.x = (W - 10) * clampf(hp_ratio, 0.0, 1.0)
	_cast_bg.visible = cast != null
	_cast.visible = cast != null
	if cast != null:
		_cast.size.x = (W - 30) * clampf(1.0 - cast.left / maxf(cast.total, 1.0), 0.0, 1.0)
	_auras.set_effects(effects)
	var border := Color(0, 0, 0, 0.9)
	if loc_color != null:
		border = loc_color
	elif targeted:
		border = Color("#ff2a2a")
	if border != _border:
		_border = border
		_hp_bg.add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.7), border, 3, 2 if (loc_color != null or targeted) else 1, 0))
