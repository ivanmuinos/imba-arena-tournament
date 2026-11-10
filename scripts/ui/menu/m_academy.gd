class_name MAcademy
extends MenuView
## The Academia: Tizón and what you earned on the left, the chapters with their lessons on the right. Nothing is locked: every
## lesson can be played and replayed at any time, and the one that comes next is lit.

const TILE := Vector2(256, 104)
const TALK := {
	"new": "¡Bienvenido! Soy Tizón, el más viejo de esta arena. Empezá por «%s» y en un rato estás peleando.",
	"going": "Vas bien. Ahora te toca «%s».",
	"graduate": "Ya sabés todo lo que hay que saber. Te quedan %d medallas por subir a oro, por si te animás.",
	"master": "No me queda nada que enseñarte. Andá a la arena y hacé que me sienta orgulloso.",
}

var reference_button: MButton
var continue_button: MButton
var _tiles := {}  # lesson id -> {tile, badge, detail, tag}
var _chapter_labels := {}  # chapter id -> Label
var _chapter_bars := {}  # chapter id -> StatBar
var _suggested := ""
var _face: TizonFace
var _rank: Label
var _talk: Label
var _count: Label
var _bar: StatBar
var _tally := {}  # medal -> Label
var _champion: Label
var _scroll: ScrollContainer


func _ready() -> void:
	header("Academia", "De cero a tu primer duelo, con medallas en cada lección.")
	_build_coach()
	_build_chapters()


func _build_coach() -> void:
	var box := UiKit.glass(UiKit.LINE, 12, 18, 3.0, 0.7)
	box.position = Vector2(72, 186)
	box.custom_minimum_size = Vector2(300, 460)
	box.size = Vector2(300, 460)
	add_child(box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	box.add_child(col)
	var top := CenterContainer.new()
	_face = TizonFace.new(124.0, "contenta")
	top.add_child(_face)
	col.add_child(top)
	_rank = UiKit.heading("", 22, UiKit.GOLD, 700, 1, HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_rank)
	_talk = UiKit.label("", 14, Color("#e6dccf"), HORIZONTAL_ALIGNMENT_CENTER)
	_talk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_talk.custom_minimum_size = Vector2(260, 62)
	col.add_child(_talk)
	_count = UiKit.caption("", UiKit.MUTED, 12)
	col.add_child(_count)
	_bar = StatBar.new()
	_bar.custom_minimum_size = Vector2(0, 8)
	col.add_child(_bar)
	var tally := HBoxContainer.new()
	tally.alignment = BoxContainer.ALIGNMENT_CENTER
	tally.add_theme_constant_override("separation", 6)
	col.add_child(tally)
	for m in [AcademyMedals.GOLD, AcademyMedals.SILVER, AcademyMedals.BRONZE]:
		var badge := MedalBadge.new(30.0)
		badge.medal = m
		tally.add_child(badge)
		var n := UiKit.heading("0", 20, UiKit.INK, 700, 0)
		n.custom_minimum_size = Vector2(26, 0)
		tally.add_child(n)
		_tally[m] = n
	var grow := Control.new()
	grow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(grow)
	continue_button = MButton.new("Empezar", "primary", "ui_play")
	continue_button.custom_minimum_size = Vector2(0, 50)
	continue_button.add_theme_font_size_override("font_size", 19)
	continue_button.pressed.connect(func(): menu.launch_lesson(_suggested if _suggested != "" else str(AcademyCatalog.lesson_ids()[0])))
	col.add_child(continue_button)
	reference_button = MButton.new("Controles y reglas", "secondary")
	reference_button.custom_minimum_size = Vector2(0, 40)
	reference_button.add_theme_font_size_override("font_size", 16)
	reference_button.pressed.connect(func(): menu.nav.go("howto"); menu.present_current())
	col.add_child(reference_button)


func _build_chapters() -> void:
	_champion = UiKit.label("", 14, UiKit.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	_champion.position = Vector2(708, 150)
	_champion.custom_minimum_size = Vector2(500, 0)
	_champion.size = Vector2(500, 20)
	add_child(_champion)
	var box := UiKit.glass(UiKit.LINE, 12, 14, 3.0, 0.7)
	box.position = Vector2(388, 186)
	box.custom_minimum_size = Vector2(820, 460)
	box.size = Vector2(820, 460)
	add_child(box)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	_scroll.add_child(list)
	var n := 0
	for c in AcademyCatalog.chapters():
		n += 1
		list.add_child(_chapter_head(c, n))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		list.add_child(grid)
		for l in c.lessons:
			grid.add_child(_lesson_tile(l))
		list.add_child(UiKit.spacer(6))


func _chapter_head(chapter: Dictionary, number: int) -> Control:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var disc := PanelContainer.new()
	disc.add_theme_stylebox_override("panel", UiKit.box(Color(1.0, 0.48, 0.1, 0.16), UiKit.LINE_STRONG, 16, 1, 0))
	disc.custom_minimum_size = Vector2(32, 32)
	disc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	disc.add_child(UiKit.heading(str(number), 18, UiKit.GOLD, 700, 0, HORIZONTAL_ALIGNMENT_CENTER))
	head.add_child(disc)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", -2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_child(UiKit.heading(str(chapter.title), 22, UiKit.INK, 700, 1))
	words.add_child(UiKit.label(str(chapter.blurb), 14, UiKit.MUTED))
	head.add_child(words)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var count := UiKit.label("", 13, UiKit.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	right.add_child(count)
	var bar := StatBar.new()
	bar.custom_minimum_size = Vector2(150, 5)
	right.add_child(bar)
	head.add_child(right)
	_chapter_labels[str(chapter.id)] = count
	_chapter_bars[str(chapter.id)] = bar
	return head


func _lesson_tile(lesson: Dictionary) -> Button:
	var id := str(lesson.id)
	var tile := Button.new()
	tile.custom_minimum_size = TILE
	tile.focus_mode = Control.FOCUS_ALL
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.clip_contents = true
	tile.pressed.connect(func(): menu.launch_lesson(id))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(row)
	var badge := MedalBadge.new(46.0)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(badge)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 1)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	var tag := UiKit.caption("", UiKit.LAVA, 10)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(tag)
	var title := UiKit.heading(str(lesson.title), 17, UiKit.INK, 700, 0)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(170, 0)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(title)
	var detail := UiKit.label("", 12, UiKit.MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size = Vector2(170, 0)
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(detail)
	var mins := UiKit.caption("%d min" % int(lesson.get("mins", 1)), UiKit.DIM, 10)
	mins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.add_child(mins)
	_tiles[id] = {"tile": tile, "badge": badge, "detail": detail, "tag": tag, "mins": mins}
	return tile


func menu_enter() -> void:
	var store := AcademyStore.shared()
	_suggested = AcademyCatalog.next_lesson(store)
	for c in AcademyCatalog.chapters():
		var p := AcademyCatalog.progress(c, store)
		(_chapter_labels[str(c.id)] as Label).text = "%d de %d completas · %d de oro" % [p.done, p.total, p.gold]
		(_chapter_bars[str(c.id)] as StatBar).animate_to(float(p.done) / maxf(1.0, float(p.total)), UiKit.GOLD if p.gold == p.total else UiKit.LAVA)
	var counts := {AcademyMedals.GOLD: 0, AcademyMedals.SILVER: 0, AcademyMedals.BRONZE: 0}
	for id in _tiles:
		var t: Dictionary = _tiles[id]
		var medal := store.medal(id)
		if counts.has(medal):
			counts[medal] += 1
		(t.badge as MedalBadge).medal = medal
		(t.detail as Label).text = _detail_of(id, store)
		var on: bool = id == _suggested
		(t.tag as Label).text = ("EMPEZÁ POR ACÁ" if store.lessons.is_empty() else "SEGUÍ POR ACÁ") if on else ""
		(t.tag as Label).visible = on
		(t.mins as Label).visible = medal <= AcademyMedals.NONE and not on
		_style_tile(t.tile, on)
	for m in _tally:
		(_tally[m] as Label).text = str(counts[m])
	var all := AcademyCatalog.overall(store)
	_rank.text = str(all.rank)
	_count.text = "%d de %d lecciones · %d de oro" % [all.done, all.total, all.gold]
	_bar.animate_to(float(all.done) / maxf(1.0, float(all.total)), UiKit.GOLD)
	_talk.text = coach_line(store)
	_face.mood = "orgullosa" if int(all.gold) >= int(all.total) else "contenta" if int(all.done) > 0 else "neutral"
	continue_button.text = "Empezar" if store.lessons.is_empty() else "Continuar" if _suggested != "" else "Repasar"
	var cfg: Dictionary = menu._cfg()
	_champion.text = "Las lecciones se adaptan a tu campeón: %s" % AcademyKit.new(str(cfg.get("cls", "mage")), str(cfg.get("spec", ""))).class_name_text()
	if _tiles.has(_suggested):
		_scroll.ensure_control_visible.call_deferred(_tiles[_suggested].tile)


func _style_tile(tile: Button, on: bool) -> void:
	var edge := UiKit.LINE_STRONG if on else Color(1, 1, 1, 0.08)
	tile.add_theme_stylebox_override("normal", UiKit.box(Color(0.16, 0.075, 0.03, 0.9) if on else Color(0.06, 0.04, 0.035, 0.82), edge, 8, 2 if on else 1, 0))
	tile.add_theme_stylebox_override("hover", UiKit.box(Color(0.22, 0.1, 0.04, 0.95), UiKit.LINE_STRONG, 8, 2, 0))
	tile.add_theme_stylebox_override("pressed", UiKit.box(Color(0.26, 0.12, 0.04, 0.95), UiKit.GOLD, 8, 2, 0))
	tile.add_theme_stylebox_override("focus", UiKit.box(Color(0, 0, 0, 0), UiKit.GOLD, 8, 2, 0))


## What Tizón says on this screen, by how far the player is.
static func coach_line(store: AcademyStore) -> String:
	var all := AcademyCatalog.overall(store)
	var next := AcademyCatalog.next_lesson(store)
	if int(all.gold) >= int(all.total):
		return str(TALK.master)
	if next == "":
		return str(TALK.graduate) % (int(all.total) - int(all.gold))
	var title := str(AcademyCatalog.info(next).get("title", ""))
	return str(TALK["new"] if int(all.done) == 0 else TALK.going) % title


func _detail_of(id: String, store: AcademyStore) -> String:
	var medal := store.medal(id)
	var info := AcademyCatalog.info(id)
	if medal > AcademyMedals.NONE:
		return "%s · mejor tiempo %s" % [AcademyMedals.NAMES[medal], AcademyMedals.time_text(store.best_ms(id))]
	return str(info.get("blurb", ""))


func medal_shown(id: String) -> int:
	return (_tiles[id].badge as MedalBadge).medal


func detail_text(id: String) -> String:
	return (_tiles[id].detail as Label).text


func is_suggested(id: String) -> bool:
	return id == _suggested


func play_button(id: String) -> Button:
	return _tiles[id].tile


func first_focus() -> Control:
	if _tiles.has(_suggested):
		return play_button(_suggested)
	return play_button(str(AcademyCatalog.lesson_ids()[0]))


func section() -> String:
	return "Aprender"
