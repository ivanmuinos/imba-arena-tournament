class_name MTournament
extends MenuView
## "Torneo": the cups of each mode (4 tiers with locks and cups won), the bracket of the run in progress, the 18 class
## challenges and the cosmetic rewards with what is equipped. Everything it shows comes from TournamentInfo.

const TIER_ACCENT := {"bronze": Color("#cd7f32"), "silver": Color("#c0c8d4"), "gold": Color("#ffd23f"), "gladiator": Color("#e0402f")}

var _mode := 1
var _tier := "bronze"
var _tabs: Segmented
var _pages := {}
var _mode_seg: Segmented
var _cards := {}
var _bracket: HBoxContainer
var _side: VBoxContainer
var _level: Label
var _xp_fill: ColorRect
var _xp_text: Label
var _challenges: GridContainer
var _rewards: VBoxContainer


func section() -> String:
	return "Jugar"


func _ready() -> void:
	header("Torneo")
	_build_level_badge()
	_tabs = Segmented.new().setup([["cups", "Copas"], ["challenges", "Desafíos"], ["rewards", "Recompensas"]], "cups").as_tabs()
	_tabs.position = Vector2(72, 150)
	_tabs.changed.connect(_show_page)
	add_child(_tabs)
	_build_cups()
	_challenges = GridContainer.new()
	_challenges.columns = 3
	_challenges.position = Vector2(72, 204)
	_challenges.add_theme_constant_override("h_separation", 14)
	_challenges.add_theme_constant_override("v_separation", 14)
	add_child(_challenges)
	_pages["challenges"] = _challenges
	_rewards = VBoxContainer.new()
	_rewards.position = Vector2(72, 204)
	_rewards.custom_minimum_size = Vector2(1136, 0)
	_rewards.add_theme_constant_override("separation", 12)
	add_child(_rewards)
	_pages["rewards"] = _rewards
	_show_page("cups")


# ---------------------------------------------------------------- account level

func _build_level_badge() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(900, 92)
	box.custom_minimum_size = Vector2(308, 0)
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_level = UiKit.heading("", 24, UiKit.GOLD, 700, 2, HORIZONTAL_ALIGNMENT_RIGHT)
	box.add_child(_level)
	var bar := ColorRect.new()
	bar.color = Color(1, 1, 1, 0.1)
	bar.custom_minimum_size = Vector2(308, 6)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bar)
	_xp_fill = ColorRect.new()
	_xp_fill.color = UiKit.GOLD
	_xp_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_xp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_xp_fill)
	_xp_text = UiKit.caption("", UiKit.MUTED, 12)
	_xp_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	box.add_child(_xp_text)


func _refresh_level() -> void:
	var p := menu.profile.progress()
	_level.text = "NIVEL %d" % p.level
	_xp_fill.anchor_right = 1.0 if p.maxed else clampf(float(p.into) / maxf(1.0, float(p.need)), 0.0, 1.0)
	_xp_text.text = "Nivel máximo" if p.maxed else "%d / %d XP" % [p.into, p.need]


# ---------------------------------------------------------------- cups tab

func _build_cups() -> void:
	var page := Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)
	_pages["cups"] = page
	_mode_seg = Segmented.new().setup([["1", "1v1"], ["2", "2v2"], ["3", "3v3"]], "1")
	_mode_seg.position = Vector2(560, 152)
	_mode_seg.changed.connect(func(v):
		_mode = int(v)
		_refresh_cups())
	page.add_child(_mode_seg)
	var row := HBoxContainer.new()
	row.position = Vector2(72, 204)
	row.custom_minimum_size = Vector2(1136, 0)
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(row)
	for id in Tournament.tier_ids():
		var c := Card.new("", str(Tournament.tier(id).name), "", TIER_ACCENT.get(id, UiKit.GOLD))
		c.custom_minimum_size = Vector2(266, 172)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.set_title_size(30)
		var tid: String = id
		c.pressed.connect(func():
			_tier = tid
			_refresh_cups())
		row.add_child(c)
		_cards[id] = c
	_bracket = HBoxContainer.new()
	_bracket.position = Vector2(72, 402)
	_bracket.custom_minimum_size = Vector2(700, 230)
	_bracket.add_theme_constant_override("separation", 22)
	_bracket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(_bracket)
	_side = VBoxContainer.new()
	_side.position = Vector2(820, 402)
	_side.custom_minimum_size = Vector2(388, 0)
	_side.add_theme_constant_override("separation", 8)
	page.add_child(_side)


func _refresh_cups() -> void:
	var store: TournamentStore = menu.tstore
	var tiers := Tournament.tier_ids()
	if not store.is_unlocked(_mode, _tier):
		_tier = tiers[0]
	for id in tiers:
		var d := TournamentInfo.tier_card(store, _mode, id)
		var c: Card = _cards[id]
		var lines: Array = ["Copas ganadas: %d" % d.cups, d.status]
		if d.bonus != "":
			lines.append(d.bonus)
		c.set_subtitle("\n".join(lines))
		c.set_badge("OPCIONAL" if d.optional else ("BLOQUEADO" if d.locked else ""))
		c.disabled = d.locked
		c.selected = id == _tier
	_refresh_bracket()
	_refresh_side()


func _refresh_bracket() -> void:
	for c in _bracket.get_children():
		c.queue_free()
	var run: Dictionary = menu.tstore.run
	var shown := not run.is_empty() and int(run.get("mode", 0)) == _mode and str(run.get("tier", "")) == _tier
	var cols := TournamentInfo.bracket_columns(run) if shown else []
	if cols.is_empty():
		var t := UiKit.label("Copa de 8 equipos contra bots: 3 partidas, cada una al mejor de 3 rondas.\nGanar una copa abre el siguiente nivel. El sorteo se hace cuando la empezás.", 15, UiKit.MUTED)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t.custom_minimum_size = Vector2(620, 0)
		_bracket.add_child(t)
		return
	for r in cols.size():
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(210, 0)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 6 + 20 * r * r)
		col.add_child(UiKit.caption(str(Tournament.data().rounds[r]).to_upper(), UiKit.GOLD, 11))
		for m in cols[r]:
			col.add_child(_match_box(m))
		_bracket.add_child(col)


func _match_box(m: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiKit.box(Color(1, 1, 1, 0.05), UiKit.GOLD if m.mine else UiKit.LINE, 6, 1, 5))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	for side in 2:
		var won: bool = m.winner == side
		var lost: bool = m.winner >= 0 and not won
		var l := UiKit.label(str(m.a if side == 0 else m.b), 14, UiKit.GOLD if won else (UiKit.DIM if lost else UiKit.INK))
		l.clip_text = true
		l.custom_minimum_size = Vector2(196, 0)
		v.add_child(l)
	return p


func _refresh_side() -> void:
	for c in _side.get_children():
		c.queue_free()
	var store: TournamentStore = menu.tstore
	var run: Dictionary = store.run
	var cfg := menu._cfg()
	var cls_name := str(GameData.classes[str(cfg.cls)].name)
	var champ := UiKit.label("Tu campeón: %s" % cls_name, 16, UiKit.INK)
	_side.add_child(champ)
	var change := MButton.new("Cambiar campeón", "ghost")
	change.custom_minimum_size = Vector2(0, 34)
	change.pressed.connect(func(): menu.go_tab("champions"))
	_side.add_child(change)
	var same := store.has_active_run() and int(run.mode) == _mode and str(run.tier) == _tier
	var d := TournamentInfo.tier_card(store, _mode, _tier)
	if d.bonus != "":
		var b := UiKit.label(d.bonus + ".", 14, Color("#ff9a7a"))
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_side.add_child(b)
	if same:
		var info := UiKit.label(TournamentInfo.continue_text(store), 14, UiKit.MUTED)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_side.add_child(info)
		var go := MButton.new("CONTINUAR COPA", "primary", "ui_play")
		go.pressed.connect(func(): menu.resume_tournament())
		_side.add_child(go)
		var fresh := MButton.new("Empezar de cero", "ghost")
		fresh.pressed.connect(func(): menu.start_tournament(_mode, _tier, true))
		_side.add_child(fresh)
	else:
		if store.has_active_run():
			var warn := UiKit.label("Ya tenés una copa en curso (%s). Empezar otra la reemplaza." % TournamentInfo.continue_text(store), 13, UiKit.MUTED)
			warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_side.add_child(warn)
		var go2 := MButton.new("EMPEZAR COPA", "primary", "ui_play")
		go2.disabled = d.locked
		go2.pressed.connect(func(): menu.start_tournament(_mode, _tier, false))
		_side.add_child(go2)


# ---------------------------------------------------------------- challenges tab

func _refresh_challenges() -> void:
	for c in _challenges.get_children():
		c.queue_free()
	for cls in GameData.playable_ids():
		var p := UiKit.glass(UiKit.class_color(str(cls)), 10, 12, 3.0, 0.6)
		p.custom_minimum_size = Vector2(366, 0)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 3)
		p.add_child(v)
		v.add_child(UiKit.heading(str(GameData.classes[cls].name).to_upper(), 18, UiKit.class_color(str(cls)), 700, 2))
		for r in TournamentInfo.challenge_rows(menu.profile, str(cls)):
			var line := HBoxContainer.new()
			var name_l := UiKit.label(("✓ " if r.done else "") + str(r.name), 14, UiKit.GREEN if r.done else UiKit.INK)
			name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_l.clip_text = true
			line.add_child(name_l)
			line.add_child(UiKit.label(str(r.progress_text), 14, UiKit.MUTED, HORIZONTAL_ALIGNMENT_RIGHT))
			v.add_child(line)
			var d := UiKit.label(str(r.desc), 12, UiKit.DIM)
			d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			d.custom_minimum_size = Vector2(340, 0)
			v.add_child(d)
		_challenges.add_child(p)


# ---------------------------------------------------------------- rewards tab

func _refresh_rewards() -> void:
	for c in _rewards.get_children():
		c.queue_free()
	var prof: ProfileStore = menu.profile
	_rewards.add_child(UiKit.label("Elegí qué lucís en la arena. Se desbloquea con desafíos y con el nivel de cuenta (%d de %d recompensas)." % [prof.unlocked.size(), Challenges.items().size()], 15, UiKit.MUTED))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	_rewards.add_child(grid)
	_picker(grid, "Título", "title", "")
	_picker(grid, "Anillo", "ring", "")
	for cls in GameData.playable_ids():
		_picker(grid, "Color: %s" % str(GameData.classes[cls].name), "recolor", str(cls))
	var next_lv := prof.level() + 1
	if next_lv <= ProfileStore.max_level():
		var it := Challenges.item(ProfileStore.level_reward(next_lv))
		if not it.is_empty():
			_rewards.add_child(UiKit.label("Próximo premio de nivel (%d): %s" % [next_lv, str(it.name)], 15, UiKit.GOLD))


## One caption + dropdown: "Ninguno" and the unlocked items of that slot (recolors only of `cls`).
func _picker(parent: Control, caption: String, slot: String, cls: String) -> void:
	var prof: ProfileStore = menu.profile
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.add_child(UiKit.caption(caption, UiKit.GOLD, 11))
	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(260, 36)
	opt.add_item("Ninguno")
	opt.set_item_metadata(0, "")
	var current: String = str(prof.equipped.recolor.get(cls, "")) if slot == "recolor" else str(prof.equipped[slot])
	for it in Challenges.items():
		if str(it.kind) != slot or not prof.is_unlocked(str(it.id)) or (slot == "recolor" and str(it.cls) != cls):
			continue
		opt.add_item(str(it.name))
		opt.set_item_metadata(opt.item_count - 1, str(it.id))
		if str(it.id) == current:
			opt.select(opt.item_count - 1)
	opt.item_selected.connect(func(i):
		var id := str(opt.get_item_metadata(i))
		if id == "":
			prof.unequip(slot, cls)
		else:
			prof.equip(slot, id))
	col.add_child(opt)
	parent.add_child(col)


# ---------------------------------------------------------------- view

func _show_page(id: String) -> void:
	for k in _pages:
		(_pages[k] as Control).visible = k == id
	match id:
		"challenges":
			_refresh_challenges()
		"rewards":
			_refresh_rewards()
		_:
			_refresh_cups()


## Debug/screenshots (--menu=tournament:challenges): "cups", "challenges" or "rewards".
func select_page(id: String) -> void:
	if _pages.has(id):
		_tabs.select(id, false)
		_show_page(id)


func menu_enter() -> void:
	menu.tstore.load_file()
	menu.profile.load_file()
	_refresh_level()
	_show_page(_tabs.value if _tabs.value != "" else "cups")


func first_focus() -> Control:
	return _cards[_tier]


func hints() -> Array:
	return [["Flechas", "Navegar"], ["Enter", "Elegir"], ["Esc", "Volver"]]
