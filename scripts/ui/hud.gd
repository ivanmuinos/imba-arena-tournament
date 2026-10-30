class_name Hud
extends CanvasLayer
## In-match interface (port of src/hud.ts + the HUD part of src/main.ts): score, frames, target
## frame, ability bar, casts, debuffs, loss-of-control alert, kill feed, nameplates and
## floating combat text.

signal frame_clicked(id: int)
signal macro_pressed(index: int)

const TEAM_NAME := {"red": "ROJO", "blue": "AZUL"}
## Health bars: allies and you green, enemies red everywhere; team colour is only for borders and accents.
const HP_ALLY := Color("#4caf50")
const HP_ENEMY := Color("#e53935")
const TEAM_COL := {"red": Color("#ff4d4d"), "blue": Color("#4da3ff")}

var my_team := "red"
var my_cls := "mage"
var my_spec := ""
var my_id := -1
## Absolute local ms when each slot is ready (shared with the PlayerController).
var ready_at: Array = []

var _root := Control.new()
var _roster: Array = []
var _frames := {}
var _slots: Array = []
## PvP trinket button (T), after the abilities: {sweep, cd}; ready at this time (ms, client clock).
var _trinket := {}
var trinket_ready := 0.0
var _span := {}  # slot -> length of the cooldown being shown (ms)
var _plates := {}
var _floats: Array = []
var _feed_expiry: Array = []
var _dead := {}
var _last_phase := ""
var _fight_at := 0.0
var _last_score := {"red": 0, "blue": 0}
var _round_winner := ""
var _error_until := 0.0
var _fps_t := 0.0
var _fps_frames := 0

var score_red: Label
var score_blue: Label
## Practice arena: no score, rounds or countdown on screen.
var practice := false
var damp := 0.0  # fraction of healing removed by Dampening, shown as a debuff on everyone
var round_label: Label
var ping_label: Label
var fps_label: Label
var center_text: Label
var center_sub: Label
var error_text: Label
var status_line: Label
var lock_hint: Label
var _frames_ally: VBoxContainer
var _frames_enemy: VBoxContainer
var _killfeed: VBoxContainer
var _bar_frame: ActionBarFrame
var _bar_holder: Control
var bar_scale := 1.0
var _my_debuffs: AuraRow
var _my_cast: CastBar
var _cast_track := CastTracker.new()
var _my_cast_label: Label
var _loc: PanelContainer
var _loc_icon: TextureRect
var _loc_name: Label
var _loc_time: Label
var _tint: ColorRect
var _vignette: TextureRect
var _arrow: Polygon2D
var _target_panel: VBoxContainer
var _focus_panel: VBoxContainer
var _ff := {}
var _tf := {}
var _plate_layer := Control.new()
var _float_layer := Control.new()
var _ability_tip: UiTip
var _tip_slot := -1
var _spirit: ColorRect
var _spectator: Label


const DESIGN_SIZE := Vector2(1280, 720)
var ui_scale := 1.0


## The layout is designed for 1280x720 and scaled uniformly to the window.
static func ui_scale_for(window: Vector2) -> float:
	return clampf(minf(window.x / DESIGN_SIZE.x, window.y / DESIGN_SIZE.y), 0.5, 2.0)


static func screen_to_ui(p: Vector2, scale: float) -> Vector2:
	return p / scale


func _rescale() -> void:
	var win := Vector2(get_viewport().get_visible_rect().size)
	ui_scale = ui_scale_for(win)
	_root.scale = Vector2(ui_scale, ui_scale)
	_root.position = Vector2.ZERO
	_root.size = win / ui_scale


func _ready() -> void:
	layer = 10
	_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.theme()
	add_child(_root)
	_rescale()
	get_viewport().size_changed.connect(_rescale)
	_build()


var _overlays: Array = []


## Adds a panel to the scaled HUD root, pinned `top` px from the top and `margin` px from the right edge (design pixels).
func add_overlay(c: Control, top: float, margin := 12.0, from_right := true) -> void:
	_root.add_child(c)
	_overlays.append(c)
	var place := func():
		c.position = Vector2(_root.size.x - c.size.x - margin if from_right else margin, top)
	place.call()
	_root.resized.connect(place)
	c.resized.connect(place)


## True when a screen position is over one of the interactive overlays (practice panel, tutorial card): the world ignores that click.
func blocks_mouse(pos: Vector2) -> bool:
	for c in _overlays:
		if is_instance_valid(c) and c.is_visible_in_tree() and Rect2(c.global_position, c.size * ui_scale).has_point(pos):
			return true
	return false


## Screen rectangle of a HUD element the tutorial points at ("bar", "target_panel", "cast", "score", "frames"), or an empty Rect2.
func rect_of(key: String) -> Rect2:
	var c: Control = {"bar": _bar_frame, "target_panel": _target_panel, "cast": _my_cast, "score": round_label, "frames": _frames_ally}.get(key)
	if c == null or not c.is_visible_in_tree():
		return Rect2()
	return c.get_global_rect()  # includes the bar's own scale


## Ability slot whose tooltip is showing (-1 when none).
func tooltip_slot() -> int:
	return _tip_slot


func _full(c: Control) -> Control:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(c)
	return c


func _build() -> void:
	# Only the world is desaturated: this is drawn before the HUD, and hidden while alive.
	_spirit = ColorRect.new()
	var spirit_mat := ShaderMaterial.new()
	spirit_mat.shader = load("res://assets/shaders/spirit.gdshader")
	_spirit.material = spirit_mat
	_spirit.visible = false
	_full(_spirit)
	# Screen tint + vignette sit under everything else.
	_tint = ColorRect.new()
	_tint.color = Color(0, 0, 0, 0)
	_full(_tint)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.55, 1.0])
	g.colors = PackedColorArray([Color(1, 0.1, 0, 0), Color(1, 0.1, 0, 0.55)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	_vignette = TextureRect.new()
	_vignette.texture = gt
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.modulate.a = 0.0
	_full(_vignette)
	_full(_plate_layer)
	_full(_float_layer)
	_arrow = Polygon2D.new()
	_arrow.polygon = PackedVector2Array([Vector2(16, 0), Vector2(-10, -13), Vector2(-4, 0), Vector2(-10, 13)])
	_arrow.color = Color("#ff3b3b")
	_arrow.visible = false
	_root.add_child(_arrow)

	# Score bar.
	var sb := PanelContainer.new()
	sb.add_theme_stylebox_override("panel", HudArt.panel_style(12))
	sb.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sb.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sb.position.y = 10
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	score_red = UiKit.label("0", 34, UiKit.RED, HORIZONTAL_ALIGNMENT_CENTER)
	score_red.custom_minimum_size = Vector2(40, 0)
	round_label = UiKit.label("Ronda 1", 15, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	round_label.custom_minimum_size = Vector2(240, 0)
	round_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	score_blue = UiKit.label("0", 34, UiKit.BLUE, HORIZONTAL_ALIGNMENT_CENTER)
	score_blue.custom_minimum_size = Vector2(40, 0)
	ping_label = UiKit.label("– ms", 12, UiKit.MUTED)
	ping_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fps_label = UiKit.label("– fps", 12, UiKit.MUTED)
	fps_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for c in [score_red, round_label, score_blue, ping_label, fps_label]:
		h.add_child(c)
	sb.add_child(h)
	_root.add_child(sb)

	_frames_ally = VBoxContainer.new()
	_frames_ally.add_theme_constant_override("separation", 6)
	_frames_ally.position = Vector2(16, 14)
	_root.add_child(_frames_ally)
	_frames_enemy = VBoxContainer.new()
	_frames_enemy.add_theme_constant_override("separation", 6)
	_frames_enemy.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_frames_enemy.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_frames_enemy.position = Vector2(-16, 14)
	_frames_enemy.resized.connect(func(): _frames_enemy.pivot_offset = Vector2(_frames_enemy.size.x, 0))  # scales from the right edge
	_root.add_child(_frames_enemy)
	_killfeed = VBoxContainer.new()
	_killfeed.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_killfeed.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_killfeed.position = Vector2(16, -190)  # above the action bar's left orb
	_root.add_child(_killfeed)

	_build_target_frame()

	# Centre texts.
	var centre := VBoxContainer.new()
	centre.anchor_left = 0.0
	centre.anchor_right = 1.0
	centre.offset_top = 120
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_text = UiKit.label("", 64, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	center_text.add_theme_font_override("font", UiKit.title_font())
	UiKit.outlined(center_text, 12, Color("#3a1306"))
	center_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_sub = UiKit.label("", 22, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.outlined(center_sub, 8)
	center_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(center_text)
	centre.add_child(center_sub)
	_root.add_child(centre)
	error_text = UiKit.label("", 20, Color("#ffd27a"), HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.outlined(error_text, 6)
	error_text.anchor_left = 0.0
	error_text.anchor_right = 1.0
	error_text.anchor_top = 0.62
	error_text.anchor_bottom = 0.62
	error_text.offset_bottom = 30
	error_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(error_text)
	status_line = UiKit.label("", 18, Color("#ffb347"), HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.outlined(status_line, 6)
	status_line.anchor_left = 0.0
	status_line.anchor_right = 1.0
	status_line.anchor_top = 1.0
	status_line.anchor_bottom = 1.0
	status_line.offset_top = -200
	status_line.offset_bottom = -176
	status_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(status_line)
	lock_hint = UiKit.label("Clic derecho + arrastrar: mirar · Clic izquierdo + arrastrar: cámara · Tab: objetivo · Esc: soltar objetivo", 14, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.outlined(lock_hint, 5)
	lock_hint.anchor_left = 0.0
	lock_hint.anchor_right = 1.0
	lock_hint.anchor_top = 0.35
	lock_hint.anchor_bottom = 0.35
	lock_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lock_hint.visible = false
	_root.add_child(lock_hint)

	# Own debuffs, cast bar and ability bar (bottom centre).
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.position.y = -14
	bottom.add_theme_constant_override("separation", 6)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_my_debuffs = AuraRow.new().setup(34)
	_my_debuffs.alignment = BoxContainer.ALIGNMENT_CENTER
	_my_debuffs.custom_minimum_size = Vector2(0, 36)
	bottom.add_child(_my_debuffs)
	_my_cast = CastBar.new()
	_my_cast.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_my_cast)
	_macro_bar = HBoxContainer.new()  # your macros, a small row over the ability bar
	_macro_bar.add_theme_constant_override("separation", 5)
	_macro_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(_macro_bar)
	_bar_frame = ActionBarFrame.new()  # the action bar art with its holes and orbs, scaled by the "bar_scale" setting
	_bar_holder = Control.new()  # takes the frame's scaled size in the column: a container ignores its children's scale
	_bar_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_holder.add_child(_bar_frame)
	bottom.add_child(_bar_holder)
	_root.add_child(bottom)

	# Loss-of-control alert.
	_loc = PanelContainer.new()
	_loc.set_anchors_preset(Control.PRESET_CENTER)
	_loc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loc.grow_vertical = Control.GROW_DIRECTION_BOTH
	_loc.position = Vector2(0, 90)
	var lh := HBoxContainer.new()
	lh.add_theme_constant_override("separation", 14)
	_loc_icon = Icons.rect("fx_stun", 58)
	var lv := VBoxContainer.new()
	_loc_name = UiKit.label("", 26, Color.WHITE)
	_loc_time = UiKit.label("", 20, UiKit.INK)
	lv.add_child(_loc_name)
	lv.add_child(_loc_time)
	lh.add_child(_loc_icon)
	lh.add_child(lv)
	_loc.add_child(lh)
	_loc.visible = false
	_loc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_loc)
	_spectator = UiKit.label("", 20, Color("#c8edff"), HORIZONTAL_ALIGNMENT_CENTER)
	_spectator.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_spectator.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_spectator.position.y = 230
	_spectator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spectator.visible = false
	UiKit.outlined(_spectator, 6)
	_root.add_child(_spectator)
	_ability_tip = UiTip.new()
	_ability_tip.custom_minimum_size.x = 440
	# A flat card avoids an additional blurred screen copy during combat.
	_ability_tip.material = null
	_ability_tip.add_theme_stylebox_override("panel", HudArt.panel_style(18))
	_root.add_child(_ability_tip)


func set_spectator(dead: bool, observed: String) -> void:
	_spirit.visible = dead
	_spectator.visible = dead
	_spectator.text = "EN ESPÍRITU · %s\nTab: cambiar aliado · arrastrar: mirar" % observed if observed != "" else "EN ESPÍRITU\nEsperando la próxima ronda"


func _show_ability_tip(index: int) -> void:
	_tip_slot = index
	_ability_tip.set_ability(GameData.abilities(my_cls, my_spec)[index], Keybinds.shared().slot_label(index))
	_ability_tip.modulate.a = 0.0
	_ability_tip.show()
	_place_ability_tip.call_deferred(index)


func _place_ability_tip(index: int) -> void:
	# Autowrapped labels need their final width before their minimum height is valid.
	await get_tree().process_frame
	await get_tree().process_frame
	if not _ability_tip.visible or index != _tip_slot or index >= _slots.size():
		return
	_ability_tip.size.y = 0
	var slot := (_slots[index].root as Control).get_global_rect()
	var at := screen_to_ui(slot.position, ui_scale)
	_ability_tip.pop(Vector2(clampf(at.x + slot.size.x / ui_scale / 2 - _ability_tip.size.x / 2, 8, maxf(8, _root.size.x - _ability_tip.size.x - 8)), maxf(8, at.y - _ability_tip.size.y - 14)))


func _build_target_frame() -> void:
	_target_panel = VBoxContainer.new()
	_target_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_target_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_target_panel.position = Vector2(0, 66)
	_target_panel.add_theme_constant_override("separation", 2)
	_target_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var holder := Control.new()  # both art variants on the same spot; show_target shows one
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for kind in ["ally", "enemy"]:
		var uf := HudArt.unit_frame(HudArt.ALLY if kind == "ally" else HudArt.ENEMY, 0.44 if kind == "ally" else 0.42)
		var hp: Bar = uf.bars[0]
		var cast: Bar = uf.bars[1]
		cast.fill = Color("#ffd166")
		var nm := UiKit.label("", 19, UiKit.INK)
		UiKit.outlined(nm, 5)
		nm.position = hp.position + Vector2(2, -25)
		nm.size = Vector2(hp.size.x * 0.75, 24)
		nm.clip_text = true
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dist := UiKit.label("", 13, UiKit.INK, HORIZONTAL_ALIGNMENT_RIGHT)
		UiKit.outlined(dist, 4)
		dist.position = hp.position + Vector2(hp.size.x * 0.75, -22)
		dist.size = Vector2(hp.size.x * 0.25 - 2, 20)
		dist.mouse_filter = Control.MOUSE_FILTER_IGNORE
		uf.root.add_child(nm)
		uf.root.add_child(dist)
		holder.add_child(uf.root)
		holder.custom_minimum_size = holder.custom_minimum_size.max(uf.root.custom_minimum_size)
		_tf[kind] = {"root": uf.root, "icon": uf.icon, "name": nm, "dist": dist, "hp": hp, "cast": cast}
	_target_panel.add_child(holder)
	_tf.auras = AuraRow.new().setup(30)
	_tf.auras.alignment = BoxContainer.ALIGNMENT_CENTER
	_target_panel.add_child(_tf.auras)
	_tf.status = UiKit.label("", 14, UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.outlined(_tf.status, 4)
	_target_panel.add_child(_tf.status)
	_target_panel.visible = false
	_root.add_child(_target_panel)
	_build_focus_frame()


## The focus (macros' [@focus]): the skull bar under the target's frame with name, health and cast.
func _build_focus_frame() -> void:
	_focus_panel = VBoxContainer.new()
	_focus_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_focus_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_focus_panel.position = Vector2(290, 74)
	_focus_panel.add_theme_constant_override("separation", 0)
	_focus_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ff.name = UiKit.label("", 14, UiKit.INK)
	UiKit.outlined(_ff.name, 4)
	_focus_panel.add_child(_ff.name)
	var uf := HudArt.unit_frame(HudArt.FOCUS, 0.45)
	_ff.hp = uf.bars[0]
	_ff.hp.fill = HP_ENEMY
	_focus_panel.add_child(uf.root)
	_ff.cast = Bar.new(8.0, Color("#ffd166"))
	_ff.cast.visible = false
	_focus_panel.add_child(_ff.cast)
	_focus_panel.visible = false
	_root.add_child(_focus_panel)


func show_focus(info: Dictionary) -> void:
	_focus_panel.visible = not info.is_empty()
	if info.is_empty():
		return
	_ff.name.text = "Foco: %s" % info.name
	_ff.hp.fill = HP_ALLY if info.get("friend", false) else HP_ENEMY
	_ff.hp.ratio = info.hp / info.max_hp
	_ff.cast.visible = info.cast != null
	if info.cast != null:
		_ff.cast.ratio = 1.0 - info.cast.left / maxf(info.cast.total, 1.0)
	_focus_panel.modulate.a = 0.55 if info.lost else 1.0


# ---------------------------------------------------------------- setup per match

func setup(roster: Array, you: int, cls: String, team: String, spec := "") -> void:
	my_id = you
	my_cls = cls
	my_spec = spec
	my_team = team
	_roster = roster
	_dead.clear()
	_last_phase = ""
	_last_score = {"red": 0, "blue": 0}
	ready_at = []
	for i in int(GameData.C.SLOT_COUNT):
		ready_at.append(0.0)
	for c in _frames_ally.get_children() + _frames_enemy.get_children() + _killfeed.get_children() + _plate_layer.get_children() + _float_layer.get_children():
		c.queue_free()
	_frames.clear()
	_plates.clear()
	_floats.clear()
	for r in roster:
		var f := _make_frame(r, r.id == you)
		(_frames_ally if r.team == team else _frames_enemy).add_child(f.root)
		_frames[r.id] = f
		var plate := Nameplate.new().setup(r.name, r.team == team, r.id == you, HP_ALLY if r.team == team else HP_ENEMY)
		plate.visible = false
		_plate_layer.add_child(plate)
		_plates[r.id] = plate
	_build_bar()
	apply_scales()
	_target_panel.visible = false
	center_text.text = ""
	center_sub.text = ""
	error_text.text = ""
	status_line.text = ""
	_loc.visible = false
	_tint.color.a = 0.0


## A party or enemy frame from the HUD art (allies: round portrait and three bars; enemies: the horned skull frame),
## name over the health bar, auras under it. Clicking it targets the unit.
func _make_frame(r: Dictionary, me: bool) -> Dictionary:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	root.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			frame_clicked.emit(r.id))
	var ally: bool = r.team == my_team
	var uf := HudArt.unit_frame(HudArt.ALLY if ally else HudArt.ENEMY, 0.3 if ally else 0.29)
	var frame: Control = uf.root
	var picon: TextureRect = uf.icon
	picon.texture = Icons.tex(GameData.classes[r.cls].icon)
	var ptime := UiKit.label("", 16, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.outlined(ptime, 5)
	ptime.position = picon.position
	ptime.size = picon.size
	ptime.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ptime.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(ptime)
	var hp: Bar = uf.bars[0]
	hp.fill = HP_ALLY if ally else HP_ENEMY
	var cast: Bar = uf.bars[1]
	cast.fill = Color("#ffd166")
	cast.visible = false
	var nm := UiKit.label(("%s (vos)" % r.name) if me else (("%s " % r.name) if r.bot else r.name), 13, UiKit.INK)
	UiKit.outlined(nm, 4)
	nm.position = hp.position + Vector2(2, -17)
	nm.size = Vector2(hp.size.x, 16)
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hp_text := UiKit.label("", 11, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)  # inside the health bar, at its right end
	UiKit.outlined(hp_text, 4)
	hp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_text.position = hp.position + Vector2(hp.size.x * 0.5, -4)
	hp_text.size = Vector2(hp.size.x * 0.5 - 3, hp.size.y + 8)
	hp_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(nm)
	frame.add_child(hp_text)
	var auras := AuraRow.new().setup(22)
	root.add_child(frame)
	root.add_child(auras)
	return {"root": root, "art": uf.art, "portrait": picon, "picon": picon, "ptime": ptime, "icon": GameData.classes[r.cls].icon, "hp": hp,
		"hp_text": hp_text, "cast": cast, "auras": auras, "name": nm}


## Applies the HUD sizes from the settings (ability bar, enemy and party frames); also live, from the in-match menu.
func apply_scales() -> void:
	var st := SettingsStore.shared()
	bar_scale = float(st.get_value("bar_scale"))
	_fit_bar()
	_frames_ally.scale = Vector2.ONE * float(st.get_value("ally_frame_scale"))
	_frames_enemy.scale = Vector2.ONE * float(st.get_value("enemy_frame_scale"))


## A full-screen panel over the HUD (the Esc menu), at the HUD's scale.
func add_modal(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(c)


## Sizes the bar frame to its buttons, at the player's chosen scale.
func _fit_bar() -> void:
	_bar_frame.scale = Vector2(bar_scale, bar_scale)
	_bar_frame.size = _bar_frame.custom_minimum_size
	_bar_holder.custom_minimum_size = _bar_frame.size * bar_scale


func _build_bar() -> void:
	bar_scale = float(SettingsStore.shared().get_value("bar_scale"))
	_bar_frame.clear()
	_slots.clear()
	var abilities: Array = GameData.abilities(my_cls, my_spec)
	var dot := Image.create(60, 60, false, Image.FORMAT_RGBA8)
	dot.fill(Color(0, 0, 0, 0.68))
	var dim_tex := ImageTexture.create_from_image(dot)
	for i in abilities.size():
		var a: Dictionary = abilities[i]
		var slot := Panel.new()
		slot.custom_minimum_size = Vector2(60, 60)
		var ult: bool = a.get("ult", false)
		slot.add_theme_stylebox_override("panel", UiKit.box(Color(0.03, 0.02, 0.015, 0.95), Color("#ffb84d") if ult else Color(0, 0, 0, 0), 2, 2 if ult else 0, 0))
		slot.mouse_filter = Control.MOUSE_FILTER_PASS
		slot.mouse_entered.connect(_show_ability_tip.bind(i))
		slot.mouse_exited.connect(_ability_tip.hush)
		_track_hover(slot, "slot_%d" % i)
		var charge := ColorRect.new()
		charge.color = Color(1.0, 0.7, 0.2, 0.35)
		charge.position = Vector2(2, 58)
		charge.size = Vector2(56, 0)
		charge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := Icons.rect(a.icon, 56)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 3)
		var key := UiKit.label("", 11, Color("#ffd27a"))
		UiKit.outlined(key, 4)
		key.position = Vector2(4, 1)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sweep := TextureProgressBar.new()
		sweep.fill_mode = TextureProgressBar.FILL_CLOCKWISE
		sweep.texture_progress = dim_tex
		sweep.max_value = 100.0
		sweep.value = 0.0
		sweep.position = Vector2.ZERO
		sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cd := UiKit.label("", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		UiKit.outlined(cd, 6)
		cd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(charge)
		slot.add_child(icon)
		slot.add_child(sweep)
		slot.add_child(key)
		slot.add_child(cd)
		_bar_frame.add_button(slot)
		_slots.append({"root": slot, "sweep": sweep, "cd": cd, "charge": charge, "icon": icon, "ult": ult, "auto": a.get("auto", false), "key": key})
	_build_trinket(dim_tex)
	_build_macro_bar()
	refresh_keys()
	_fit_bar()


## Keybinding mode and the hovered button: every bar button reports its action while the mouse is over it.
var _hovered := ""
var _binding_banner: Label = null
var _macro_buttons: Array = []  # [{root, key, index}]
var _macro_bar: HBoxContainer


func _track_hover(c: Control, action: String) -> void:
	c.mouse_entered.connect(func(): _hovered = action)
	c.mouse_exited.connect(func(): if _hovered == action: _hovered = "")


func hovered_action() -> String:
	return _hovered


## The keys on every button, from Keybinds (after a rebind too).
func refresh_keys() -> void:
	var kb := Keybinds.shared()
	for i in _slots.size():
		var sl: Dictionary = _slots[i]
		(sl.key as Label).text = ("Auto · " if sl.auto else "") + kb.slot_label(i)
	if not _trinket.is_empty():
		(_trinket.key as Label).text = kb.label("trinket")
	for m in _macro_buttons:
		(m.key as Label).text = kb.label("macro_%d" % (m.index + 1))


func set_binding(on: bool) -> void:
	if _binding_banner == null:
		_binding_banner = UiKit.label("", 17, Color("#ffd166"), HORIZONTAL_ALIGNMENT_CENTER)
		UiKit.outlined(_binding_banner, 6)
		_binding_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_binding_banner.position.y -= 150
		_binding_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_binding_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(_binding_banner)
	_binding_banner.text = "MODO TECLAS · pasá el mouse por un botón y apretá la tecla · Esc: sin tecla · %s: salir" % Keybinds.shared().label("bind_mode")
	_binding_banner.visible = on
	for sl in _slots:
		(sl.root as Control).modulate = Color(1.0, 0.9, 0.6) if on else Color.WHITE


## Your macros as small buttons after the trinket (only the ones with text): click to run, rebind in keybinding mode.
func _build_macro_bar() -> void:
	_macro_buttons.clear()
	for c in _macro_bar.get_children():
		c.queue_free()
	if not MacroStore.ENABLED:
		return
	var store := MacroStore.new()
	for i in MacroStore.COUNT:
		if store.is_empty(i):
			continue
		var b := Button.new()
		b.custom_minimum_size = Vector2(96, 34)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", UiKit.box(Color(0.12, 0.06, 0.12, 0.85), Color("#c77dff"), 8, 2, 0))
		b.add_theme_stylebox_override("hover", UiKit.box(Color(0.2, 0.1, 0.2, 0.9), Color("#e0b0ff"), 8, 2, 0))
		b.add_theme_stylebox_override("pressed", UiKit.box(Color(0.3, 0.15, 0.3, 0.95), Color("#ffffff"), 8, 2, 0))
		b.text = "      " + store.title(i)
		b.add_theme_font_size_override("font_size", 11)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.tooltip_text = store.title(i)
		b.pressed.connect(func(): macro_pressed.emit(i))
		var key := UiKit.label("", 11, Color("#ffd27a"))
		UiKit.outlined(key, 4)
		key.position = Vector2(4, 1)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(key)
		_macro_bar.add_child(b)
		_track_hover(b, "macro_%d" % (i + 1))
		_macro_buttons.append({"root": b, "key": key, "index": i})


## The PvP trinket next to the bar: gold frame, "T", a 2 minute sweep.
func _build_trinket(dim_tex: Texture2D) -> void:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(60, 60)
	slot.add_theme_stylebox_override("panel", UiKit.box(Color(0.1, 0.05, 0.04, 0.85), Color("#ffd166"), 30, 2, 0))
	slot.tooltip_text = "Abalorio PvP: rompe aturdimientos, ovejas, miedos, raíces, silencios y ralentizaciones. 2 min de reutilización."
	var icon := Icons.rect("dispel", 56)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 3)
	var key := UiKit.label("", 11, Color("#ffd27a"))
	UiKit.outlined(key, 4)
	key.position = Vector2(6, 1)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sweep := TextureProgressBar.new()
	sweep.fill_mode = TextureProgressBar.FILL_CLOCKWISE
	sweep.texture_progress = dim_tex
	sweep.max_value = 100.0
	sweep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cd := UiKit.label("", 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.outlined(cd, 6)
	cd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in [icon, sweep, key, cd]:
		slot.add_child(c)
	_bar_frame.add_button(slot)
	_trinket = {"sweep": sweep, "cd": cd, "key": key}
	_track_hover(slot, "trinket")


# ---------------------------------------------------------------- state in

func mark_dead(id: int) -> void:
	_dead[id] = true


func ally_ids() -> Array:
	return _roster.filter(func(r): return r.team == my_team).map(func(r): return r.id)


func set_friend(id: int) -> void:
	for fid in _frames:
		var f: Dictionary = _frames[fid]
		(f.art as TextureRect).self_modulate = Color(0.7, 1.0, 0.7) if fid == id else Color.WHITE


func on_state(s: Dictionary, me: Dictionary, now_ms: float) -> void:
	if s.phase != _last_phase:
		if s.phase == "prep":
			_dead.clear()
		if s.phase == "fight":
			_fight_at = now_ms
		if s.phase == "between" or s.phase == "over":
			_round_winner = "red" if s.score.red > _last_score.red else ("blue" if s.score.blue > _last_score.blue else "")
		_last_score = s.score.duplicate()
		_last_phase = s.phase
	score_red.text = str(s.score.red)
	score_blue.text = str(s.score.blue)
	damp = float(s.get("damp", 0.0))
	round_label.text = "Ronda %d · al mejor de 3" % s.round

	if s.phase == "prep":
		center_text.text = str(ceili(s.phaseLeft / 1000.0))
		center_sub.text = "Ronda %d — preparate · Esc: menú y tamaño del HUD" % s.round
		center_text.remove_theme_color_override("font_color")
	elif s.phase == "fight" and now_ms - _fight_at < 1200.0:
		center_text.text = "¡PELEA!"
		center_sub.text = ""
	elif s.phase == "between" or s.phase == "over":
		center_sub.text = ""
		center_text.text = ("Ronda para %s" % TEAM_NAME[_round_winner]) if _round_winner != "" else "Empate"
		center_text.add_theme_color_override("font_color", TEAM_COL[_round_winner] if _round_winner != "" else UiKit.INK)
	else:
		center_text.text = ""
		center_sub.text = ""
		center_text.remove_theme_color_override("font_color")

	if practice:
		round_label.text = "Arena de práctica"
		score_red.visible = false
		score_blue.visible = false
		center_text.text = ""
		center_sub.text = ""

	var seen := {}
	for u in s.units:
		seen[u.id] = u
	for id in _frames:
		var f: Dictionary = _frames[id]
		var u = seen.get(id)
		var dead: bool = (not u.alive) if u != null else _dead.has(id)
		(f.root as Control).modulate.a = 0.45 if dead else (0.6 if u == null else 1.0)
		var bad: Array = Effects.debuffs_of(u.cc) if (u != null and u.alive) else []
		var loc = null
		for d in bad:
			if d.loc:
				loc = d
				break
		f.picon.texture = Icons.tex(loc.icon if loc != null else f.icon)
		f.ptime.text = Effects.secs(loc.ms) if loc != null else ""
		if u == null:
			f.hp_text.text = "" if dead else "?"
			f.cast.visible = false
			f.auras.set_effects([])
			if not dead:
				f.auras.set_effects([])
			continue
		var max_hp: float = GameData.entry_max_hp(_entry_of(id))
		f.hp.ratio = u.hp / max_hp
		f.hp_text.text = str(u.hp) if u.alive else ""
		f.cast.visible = u.cast != null
		if u.cast != null:
			f.cast.ratio = 1.0 - u.cast.left / maxf(u.cast.total, 1.0)
		f.auras.set_effects(bad + (Effects.buffs_of(u.buffs) + Effects.damp_effect(damp) if u.alive else []))

	# Ability bar state.
	var abilities: Array = GameData.abilities(my_cls, my_spec)
	var cds: Array = s.you.cds
	for i in cds.size():
		if not abilities[i].get("ult", false):
			var at := now_ms + float(cds[i])
			if at > ready_at[i] + 50.0:
				_span[i] = float(cds[i])  # a new cooldown (or the global one): the sweep is relative to it
			ready_at[i] = at
	trinket_ready = now_ms + float(s.you.get("trinket", 0))
	var alive: bool = not me.is_empty() and me.alive
	var stunned: bool = (not me.is_empty() and (me.cc.has("stun") or me.cc.has("incap"))) or not alive
	var silenced: bool = not me.is_empty() and me.cc.has("silence")
	if not me.is_empty():
		_bar_frame.set_health(float(me.hp) if alive else 0.0, GameData.entry_max_hp(_entry_of(my_id)))
	_bar_frame.set_ult(float(s.you.ult))
	for i in _slots.size():
		var a: Dictionary = abilities[i]
		var sl: Dictionary = _slots[i]
		var locked: bool = stunned or (silenced and not a.get("physical", false))
		(sl.icon as TextureRect).modulate = Color(1, 1, 1, 0.35) if locked else Color.WHITE
		if sl.auto:  # auto-attack toggle indicator: lit border while it is on
			var on: bool = s.you.get("auto", false)
			(sl.root as Panel).add_theme_stylebox_override("panel", UiKit.box(Color(0.35, 0.12, 0.05, 0.95) if on else Color(0.1, 0.05, 0.04, 0.85), Color("#ff5a3a") if on else UiKit.LINE, 8, 3 if on else 2, 0))
		if sl.ult:
			(sl.charge as ColorRect).size.y = -56.0 * s.you.ult / 100.0
			(sl.charge as ColorRect).position.y = 58.0
			var ready: bool = s.you.ult >= 100
			(sl.root as Panel).add_theme_stylebox_override("panel", UiKit.box(Color(0.25, 0.14, 0.04, 0.9) if ready else Color(0.1, 0.05, 0.04, 0.85), Color("#ffd166") if ready else Color("#ffb84d"), 8, 3 if ready else 2, 0))
			(sl.cd as Label).text = "" if ready else "%d%%" % s.you.ult
	# Own debuffs + loss-of-control alert and screen tint.
	var mine: Array = Effects.debuffs_of(me.cc) if alive else []
	_my_debuffs.set_effects(mine + (Effects.buffs_of(me.buffs) + Effects.damp_effect(damp) if alive else []))
	var loc2 = null
	for d in mine:
		if d.loc:
			loc2 = d
			break
	_loc.visible = loc2 != null
	if loc2 != null:
		_loc.add_theme_stylebox_override("panel", HudArt.panel_style(14))
		_loc.self_modulate = Color.WHITE.lerp(loc2.color, 0.35)
		_loc_icon.texture = Icons.tex(loc2.icon)
		_loc_name.text = loc2.name.to_upper()
		_loc_time.text = Effects.secs(loc2.ms)
	_tint.color = Color(loc2.color.r, loc2.color.g, loc2.color.b, 0.13) if loc2 != null else Color(0, 0, 0, 0)
	var cast = me.get("cast") if not me.is_empty() else null
	var ev := _cast_track.update(cast if alive else null)
	if ev == "start":
		var spec: Dictionary = abilities[cast.slot]
		_my_cast.begin(spec, SpellSchools.palette(SpellSchools.school_of(str(spec.id))).mid)
	elif ev == "complete":
		_my_cast.complete()
	elif ev == "interrupted":
		_my_cast.interrupted()
	if cast != null and _cast_track.active():
		_my_cast.set_progress(_cast_track.progress(), float(cast.total))


func _team_of(id: int) -> String:
	for r in _roster:
		if r.id == id:
			return r.team
	return "red"


func _entry_of(id: int) -> Dictionary:
	for r in _roster:
		if r.id == id:
			return r
	return {"cls": "mage"}


func _cls_of(id: int) -> String:
	for r in _roster:
		if r.id == id:
			return r.cls
	return "mage"


## Smooth per-frame cooldown sweep + fading texts.
func tick(now_ms: float, dt: float, cam: Camera3D) -> void:
	var abilities: Array = GameData.abilities(my_cls, my_spec)
	for i in _slots.size():
		var a: Dictionary = abilities[i]
		var sl: Dictionary = _slots[i]
		if sl.ult or sl.auto:
			continue
		var left := maxf(0.0, ready_at[i] - now_ms)
		var pct: float = minf(100.0, left / maxf(float(_span.get(i, a.cd)), 1.0) * 100.0)
		(sl.sweep as TextureProgressBar).value = pct if left > 0.0 else 0.0
		(sl.cd as Label).text = (str(ceili(left / 1000.0)) if left > 3000.0 else "%.1f" % (left / 1000.0)) if (left > 0.0 and a.cd > 1000) else ""
	if not _trinket.is_empty():
		var tl := maxf(0.0, trinket_ready - now_ms)
		(_trinket.sweep as TextureProgressBar).value = tl / float(GameData.C.TRINKET_CD_MS) * 100.0
		(_trinket.cd as Label).text = ("%d:%02d" % [floori(tl / 60000.0), floori(fmod(tl, 60000.0) / 1000.0)]) if tl > 0.0 else ""
	for i in range(_feed_expiry.size() - 1, -1, -1):
		if now_ms >= _feed_expiry[i].at:
			if is_instance_valid(_feed_expiry[i].line):
				_feed_expiry[i].line.queue_free()
			_feed_expiry.remove_at(i)
	if now_ms > _error_until:
		error_text.modulate.a = maxf(0.0, error_text.modulate.a - dt * 4.0)
	_update_floats(dt, cam)
	_fps_frames += 1
	_fps_t += dt
	if _fps_t >= 1.0:
		var fps := roundi(_fps_frames / _fps_t)
		fps_label.text = "%d fps" % fps
		fps_label.add_theme_color_override("font_color", Color("#7dff9a") if fps >= 50 else (Color("#ffd166") if fps >= 30 else Color("#ff6b6b")))
		_fps_frames = 0
		_fps_t = 0.0


func set_ping(ms: int) -> void:
	if ms < 0:
		ping_label.text = "local"
		return
	ping_label.text = "%d ms" % ms
	ping_label.add_theme_color_override("font_color", Color("#7dff9a") if ms < 80 else (Color("#ffd166") if ms < 160 else Color("#ff6b6b")))


func error(text: String) -> void:
	error_text.text = text
	error_text.modulate.a = 1.0
	_error_until = Time.get_ticks_msec() + 1400.0


func kill(msg: Dictionary) -> void:
	var line := HBoxContainer.new()
	var killer: String = msg.killer if msg.killer != null else "El magma"
	var k := UiKit.label(killer, 14, TEAM_COL.get(msg.killerTeam, UiKit.INK) if msg.killerTeam != null else UiKit.INK)
	var mid := UiKit.label(" ", 14)
	var v := UiKit.label(msg.victim, 14, TEAM_COL[msg.victimTeam])
	for l in [k, mid, v]:
		UiKit.outlined(l, 5)
		line.add_child(l)
	_killfeed.add_child(line)
	while _killfeed.get_child_count() > 4:
		var old := _killfeed.get_child(0)
		_killfeed.remove_child(old)
		old.queue_free()
	_feed_expiry.append({"line": line, "at": Time.get_ticks_msec() + 6000.0})


func status(text: String, danger: bool) -> void:
	status_line.text = text
	_vignette.modulate.a = 1.0 if danger else 0.0


## Arrow at the screen edge pointing at the selected target when it is off-screen (or behind you).
func show_target_arrow(target_id: int, views: Dictionary, cam: Camera3D) -> void:
	var v: UnitView = views.get(target_id)
	if v == null or not v.shown or not v.is_alive():
		_arrow.visible = false
		return
	var wp := v.position + Vector3(0, 1.2 * UnitView.VS, 0)
	var win := Vector2(get_viewport().get_visible_rect().size)
	var behind := cam.is_position_behind(wp)
	var e := OffscreenIndicator.edge_point(cam.unproject_position(wp), behind, win, 48.0 * ui_scale)
	_arrow.visible = e.visible
	if e.visible:
		_arrow.position = screen_to_ui(e.pos, ui_scale)
		_arrow.rotation = e.angle
		_arrow.color = Color("#5cff8a") if v.entry.team == my_team else Color("#ff3b3b")
		_arrow.scale = Vector2.ONE * (1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.01))


# ---------------------------------------------------------------- target frame

## info: {name, cls, hp, max_hp, cast, effects, dist, status, status_kind, lost}  or {} to hide.
func show_target(info: Dictionary) -> void:
	_target_panel.visible = not info.is_empty()
	if info.is_empty():
		return
	var friend: bool = info.get("friend", false)
	var v: Dictionary = _tf.ally if friend else _tf.enemy
	(_tf.ally.root as Control).visible = friend
	(_tf.enemy.root as Control).visible = not friend
	v.icon.texture = Icons.tex(GameData.classes[info.cls].icon)
	v.name.text = info.name
	v.dist.text = info.dist
	v.hp.fill = HP_ALLY if friend else HP_ENEMY
	v.hp.ratio = info.hp / info.max_hp
	v.hp.text = "%d / %d" % [info.hp, info.max_hp]
	v.cast.visible = info.cast != null
	if info.cast != null:
		v.cast.ratio = 1.0 - info.cast.left / maxf(info.cast.total, 1.0)
	_tf.auras.set_effects(info.effects)
	_tf.status.text = info.status
	var col: Color = {"good": Color("#7dff9a"), "warn": Color("#ffd166"), "bad": Color("#ff6b6b")}.get(info.status_kind, UiKit.MUTED)
	_tf.status.add_theme_color_override("font_color", col)
	_target_panel.modulate.a = 0.55 if info.lost else 1.0


# ---------------------------------------------------------------- world-anchored widgets

func update_plate(id: int, view: UnitView, cam: Camera3D, targeted: bool, hovered := false) -> void:
	var plate: Nameplate = _plates.get(id)
	if plate == null:
		return
	var s: Dictionary = view.snap
	if not view.shown or s.is_empty() or not s.alive or cam.is_position_behind(view.head_position()):
		plate.visible = false
		return
	var p := screen_to_ui(cam.unproject_position(view.head_position()), ui_scale)
	plate.visible = true
	var sc := 1.4 if targeted else (1.1 if hovered else 1.0)
	plate.scale = Vector2(sc, sc)
	plate.pivot_offset = Vector2(Nameplate.W / 2.0, 44.0)
	plate.position = p - Vector2(Nameplate.W / 2.0, 44.0)
	if targeted and plate.get_index() != _plate_layer.get_child_count() - 1:
		_plate_layer.move_child(plate, _plate_layer.get_child_count() - 1)  # the target's plate is drawn on top
	plate.targeted = targeted
	var cc: Dictionary = s.cc
	var bad := Effects.debuffs_of(cc)
	var loc = null
	for d in bad:
		if d.loc:
			loc = d.color
			break
	var max_hp: float = GameData.entry_max_hp(view.entry)
	plate.update_state(s.hp / max_hp, s.cast, bad + Effects.buffs_of(s.buffs), loc)


func hide_plate(id: int) -> void:
	var plate: Nameplate = _plates.get(id)
	if plate != null:
		plate.visible = false


## Combat text that drifts up from a world position.
func float_text(pos: Vector3, text: String, color: Color, small := false, kind := "") -> void:
	var l := UiKit.heading(text, 24 if small else (46 if kind == "crit" else 32), color, 700, 1, HORIZONTAL_ALIGNMENT_CENTER)
	UiKit.outlined(l, 7)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.custom_minimum_size = Vector2(220, 0)
	_float_layer.add_child(l)
	_floats.append({"label": l, "pos": pos + Vector3(randf_range(-0.3, 0.3), 0, 0), "t": 0.0, "dur": 1.1, "kind": kind})


func _update_floats(dt: float, cam: Camera3D) -> void:
	for i in range(_floats.size() - 1, -1, -1):
		var f: Dictionary = _floats[i]
		f.t += dt
		var k: float = f.t / f.dur
		if k >= 1.0:
			f.label.queue_free()
			_floats.remove_at(i)
			continue
		var wp: Vector3 = f.pos + Vector3(0, k * 1.2, 0)
		var l: Label = f.label
		if cam.is_position_behind(wp):
			l.visible = false
			continue
		l.visible = true
		l.position = screen_to_ui(cam.unproject_position(wp), ui_scale) - Vector2(l.size.x / 2.0, 14)
		l.modulate.a = 1.0 if k < 0.6 else 1.0 - (k - 0.6) / 0.4
		var sc := 1.0 + (0.7 * (1.0 - k * 3.0) if f.kind == "crit" and k < 0.33 else 0.0)
		l.pivot_offset = l.size / 2.0
		l.scale = Vector2(sc, sc)
