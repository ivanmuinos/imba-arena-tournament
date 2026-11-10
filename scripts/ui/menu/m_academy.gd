class_name MAcademy
extends MenuView
## The Academia: chapters of lessons with their medals. Every lesson can be played and replayed at any time.

var reference_button: MButton
var _list: VBoxContainer
var _rows := {}  # lesson id -> {badge, detail, play, row}
var _chapter_labels := {}  # chapter id -> Label
var _suggested := ""


func _ready() -> void:
	header("Academia", "Aprendé a jugar de a poco. Repetí cualquier lección para ganar una medalla mejor.")
	reference_button = MButton.new("Controles y reglas", "secondary")
	reference_button.position = Vector2(948, 118)
	reference_button.custom_minimum_size = Vector2(260, 46)
	reference_button.add_theme_font_size_override("font_size", 18)
	reference_button.pressed.connect(func(): menu.nav.go("howto"); menu.present_current())
	add_child(reference_button)
	var box := UiKit.glass(UiKit.LINE, 12, 16, 3.0, 0.7)
	box.position = Vector2(72, 186)
	box.custom_minimum_size = Vector2(1136, 460)
	box.size = Vector2(1136, 460)
	add_child(box)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	for c in AcademyCatalog.chapters():
		_add_chapter(c)


func _add_chapter(chapter: Dictionary) -> void:
	var head := HBoxContainer.new()
	head.add_child(UiKit.heading(str(chapter.title), 24, UiKit.GOLD, 700, 1))
	var count := UiKit.label("", 15, UiKit.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(count)
	_chapter_labels[str(chapter.id)] = count
	_list.add_child(head)
	_list.add_child(UiKit.label(str(chapter.blurb), 15, UiKit.MUTED))
	for l in chapter.lessons:
		_list.add_child(_lesson_row(l))
	_list.add_child(UiKit.spacer(10))


func _lesson_row(lesson: Dictionary) -> PanelContainer:
	var id := str(lesson.id)
	var row := PanelContainer.new()
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	row.add_child(line)
	var badge := MedalBadge.new()
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(badge)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 0)
	words.add_child(UiKit.heading(str(lesson.title), 20, UiKit.INK, 600, 1))
	var detail := UiKit.label("", 14, UiKit.MUTED)
	words.add_child(detail)
	line.add_child(words)
	var play := MButton.new("Jugar", "secondary", "ui_play")
	play.custom_minimum_size = Vector2(150, 44)
	play.add_theme_font_size_override("font_size", 17)
	play.pressed.connect(func(): menu.launch_lesson(id))
	line.add_child(play)
	_rows[id] = {"badge": badge, "detail": detail, "play": play, "row": row}
	return row


func menu_enter() -> void:
	var store := AcademyStore.shared()
	_suggested = AcademyCatalog.next_lesson(store)
	for c in AcademyCatalog.chapters():
		var p := AcademyCatalog.progress(c, store)
		(_chapter_labels[str(c.id)] as Label).text = "%d de %d completas · %d de oro" % [p.done, p.total, p.gold]
	for id in _rows:
		var r: Dictionary = _rows[id]
		(r.badge as MedalBadge).medal = store.medal(id)
		(r.detail as Label).text = _detail_of(id, store)
		var on: bool = id == _suggested
		(r.play as MButton).text = "Volver a jugar" if store.played(id) else "Jugar"
		(r.row as PanelContainer).add_theme_stylebox_override("panel", UiKit.box(Color(0.1, 0.05, 0.03, 0.75) if on else Color(0, 0, 0, 0.25), UiKit.LINE_STRONG if on else Color(0, 0, 0, 0), 8, 1, 10))


func _detail_of(id: String, store: AcademyStore) -> String:
	var medal := store.medal(id)
	if medal > AcademyMedals.NONE:
		return "%s · mejor tiempo %s" % [AcademyMedals.NAMES[medal], AcademyMedals.time_text(store.best_ms(id))]
	if id == _suggested:
		return "Seguí por acá" if not store.lessons.is_empty() else "Empezá por acá"
	return "Sin medalla todavía"


func medal_shown(id: String) -> int:
	return (_rows[id].badge as MedalBadge).medal


func detail_text(id: String) -> String:
	return (_rows[id].detail as Label).text


func is_suggested(id: String) -> bool:
	return id == _suggested


func play_button(id: String) -> MButton:
	return _rows[id].play


func first_focus() -> Control:
	if _rows.has(_suggested):
		return play_button(_suggested)
	return play_button(str(AcademyCatalog.lesson_ids()[0]))


func section() -> String:
	return "Aprender"
