class_name MenuScreen
extends Control
## Front end: splash -> hub -> play / setup / join -> champion select, plus settings.
## Navigation lives in MenuNav, persisted choices in SettingsStore (both unit-tested); this node only
## animates screens and forwards the launch signals main.gd listens to.

signal play_offline(cfg: Dictionary)
signal host(cfg: Dictionary, port: int)
signal join(cfg: Dictionary, address: String, port: int)
signal map_changed(map_id: String)
signal gfx_changed(choice: String)
signal steam_host(cfg: Dictionary, friends_only: bool)
signal steam_browse
signal steam_changed
## The splash/hub asks for the 3D backdrop mood: "splash" (cinematic flythrough) or "hub".
signal backdrop_requested(kind: String)

const DESIGN := Vector2(1280, 720)
const SLIDE := 64.0

var st: SettingsStore
var nav := MenuNav.new()
var status: Label
var steam_ok := false
var steam_text := "Steam no disponible"
var scale_ := 1.0

var _stage: Control
var _shade: TextureRect
var _views := {}
var _view: MenuView = null
var _tw: Tween
var _chrome: Control
var _name_edit: LineEdit
var _back: MButton
var _hints: HBoxContainer
var _booted := false
var _launching := false
var _music: AudioStreamPlayer
var _status_tw: Tween


func _ready() -> void:
	theme = UiKit.theme()
	st = SettingsStore.shared()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(UiKit.backdrop())
	_shade = UiKit.side_shade(0.72)
	add_child(_shade)
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	for pair in [["splash", MSplash], ["hub", MHub], ["play", MPlay], ["setup", MSetup], ["join", MJoin], ["champions", MChampions], ["settings", MSettings]]:
		var v: MenuView = pair[1].new()
		v.menu = self
		_views[pair[0]] = v
		_stage.add_child(v)
	_build_chrome()
	status = UiKit.label("", 16, Color("#ffd9b3"), HORIZONTAL_ALIGNMENT_CENTER)
	status.add_theme_stylebox_override("normal", UiKit.box(Color(0.08, 0.04, 0.03, 0.92), UiKit.LINE_STRONG, 8, 1, 10))
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	status.offset_left = 340
	status.offset_right = -340
	status.offset_top = -120
	status.offset_bottom = -76
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.modulate.a = 0.0
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(status)
	_rescale()
	get_viewport().size_changed.connect(_rescale)
	visibility_changed.connect(_on_visibility)
	gfx_changed.emit(st.get_value("gfx"))
	_apply_system_settings()
	map_changed.emit(st.get_value("map"))


func _rescale() -> void:
	var win := Vector2(get_viewport().get_visible_rect().size)
	scale_ = Hud.ui_scale_for(win)
	var box := content_box(win)
	_stage.scale = Vector2(scale_, scale_)
	_stage.position = box.position
	_stage.size = box.size


## The menu layout is designed for 1280 px of width: on ultrawide windows (21:9, 32:9) it stays that wide and centred
## instead of stretching to the edges. Returns the content rectangle in window pixels (position) and design pixels (size).
static func content_box(win: Vector2) -> Rect2:
	var s := Hud.ui_scale_for(win)
	var design := win / s
	var w := minf(design.x, DESIGN.x)
	return Rect2(Vector2((win.x - w * s) / 2.0, 0.0), Vector2(w, design.y))


func _on_visibility() -> void:
	if not is_visible_in_tree():
		_stop_music()
		return
	if not _booted:
		_booted = true
		_present("splash", 1, true)
		backdrop_requested.emit("splash")
	else:
		nav.reset_to("hub")
		_launching = false
		_present("hub", -1, true)
		backdrop_requested.emit("hub")
	_start_music()


# ---------------------------------------------------------------- public API used by main.gd

func selected_map() -> String:
	return str(st.get_value("map"))


## Match config from the saved choices (name falls back to "Jugador" in MatchConfig).
func _cfg() -> Dictionary:
	st.save()
	return st.to_cfg()


func set_status(text: String) -> void:
	status.text = text
	if _status_tw != null:
		_status_tw.kill()
	if text == "":
		status.modulate.a = 0.0
		return
	status.modulate.a = 0.0
	_status_tw = create_tween()
	_status_tw.tween_property(status, "modulate:a", 1.0, 0.2)
	_status_tw.tween_interval(6.0)
	_status_tw.tween_property(status, "modulate:a", 0.0, 0.6)


## Steam is optional: without the extension/client the Steam options are disabled and say why.
func set_steam(available: bool, text: String) -> void:
	steam_ok = available
	steam_text = text
	steam_changed.emit()


## Debug/screenshots: "hub", "play", "setup:practice", "champions:rogue", "settings:audio", "join".
func debug_goto(spec: String) -> void:
	var parts := spec.split(":")
	var id := parts[0]
	if not _views.has(id):
		return
	nav.reset_to("hub")
	if id == "splash":
		nav.reset_to("splash")
	else:
		nav.current = "hub"
	match id:
		"play":
			nav.go("play")
		"setup", "champions", "join":
			nav.go("play")
			nav.start_flow("join" if id == "join" else "practice")
			if id == "champions":
				nav.next()
				if parts.size() > 1 and GameData.classes.has(parts[1]):
					st.set_value("cls", parts[1])
		"settings":
			nav.go("settings")
			(_views.settings as MSettings).select_tab(parts[1] if parts.size() > 1 else "graficos")
	_booted = true
	_present(nav.current, 1, true)
	backdrop_requested.emit("splash" if id == "splash" else "hub")


# ---------------------------------------------------------------- navigation

func go(screen: String) -> void:
	nav.go(screen)
	_present(nav.current, 1)


func back() -> void:
	var r := nav.back()
	if r != "":
		UiSound.play("uiBack")
		_present(r, -1)


func start_flow(mode: String) -> void:
	nav.start_flow(mode)
	_present(nav.current, 1)


func next_step() -> void:
	nav.next()
	if nav.flow_done():
		_launch()
	else:
		_present(nav.current, 1)


func _launch() -> void:
	if _launching:
		return
	_launching = true
	var cfg := _cfg()
	match nav.mode:
		"host":
			host.emit(cfg, int(st.get_value("port")))
		"join":
			join.emit(cfg, str(st.get_value("addr")), int(st.get_value("port")))
		"steam_host":
			steam_host.emit(cfg, bool(st.get_value("steam_friends")))
		"steam_browse":
			steam_browse.emit()
		_:
			play_offline.emit(cfg)
	# If main kept the menu visible (error), allow another try.
	get_tree().create_timer(0.5).timeout.connect(func(): _launching = false)


func _present(id: String, dir: int, instant := false) -> void:
	var next: MenuView = _views[id]
	var prev := _view
	if _tw != null:
		_tw.kill()
	for v in _views.values():
		if v != next and v != prev:
			v.visible = false
	_view = next
	_update_chrome(id)
	next.visible = true
	next.menu_enter()
	if instant or prev == null or prev == next:
		if prev != null and prev != next:
			prev.visible = false
		next.position = Vector2.ZERO
		next.modulate.a = 1.0
		_focus_view.call_deferred(next)
		return
	UiSound.play("uiWhoosh")
	next.position = Vector2(SLIDE * dir, 0)
	next.modulate.a = 0.0
	_tw = create_tween().set_parallel(true)
	_tw.tween_property(prev, "position:x", -SLIDE * dir, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_tw.tween_property(prev, "modulate:a", 0.0, 0.2)
	_tw.tween_property(next, "position:x", 0.0, 0.32).set_delay(0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tw.tween_property(next, "modulate:a", 1.0, 0.26).set_delay(0.08)
	_tw.chain().tween_callback(func():
		prev.visible = false
		prev.position = Vector2.ZERO
		prev.modulate.a = 1.0
		_focus_view(next))


func _focus_view(v: MenuView) -> void:
	if v == _view and is_instance_valid(v):
		var f := v.first_focus()
		if f != null and f.is_inside_tree() and f.is_visible_in_tree():
			f.grab_focus()


# ---------------------------------------------------------------- chrome (logo, name chip, back, hints, version)

func _build_chrome() -> void:
	_chrome = Control.new()
	_chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_chrome)
	var mark := UiKit.heading("IMBA", 30, Color("#ffcf6a"), 700, 4)
	mark.position = Vector2(72, 30)
	UiKit.outlined(mark, 6, Color("#3a1204"))
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.add_child(mark)
	var mark2 := UiKit.heading("ARENA TOURNAMENT", 14, UiKit.MUTED, 600, 5)
	mark2.position = Vector2(170, 41)
	mark2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.add_child(mark2)
	# name chip, top right
	var chip := UiKit.glass(UiKit.LINE, 22, 0, 3.0, 0.5)
	chip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	chip.position = Vector2(-72 - 230, 26)
	chip.custom_minimum_size = Vector2(230, 40)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var av := Icons.rect("ui_user", 20)
	av.modulate = UiKit.GOLD
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(10, 0)
	row.add_child(pad)
	row.add_child(av)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Tu nombre"
	_name_edit.max_length = 16
	_name_edit.flat = true
	_name_edit.custom_minimum_size = Vector2(150, 36)
	_name_edit.add_theme_font_override("font", UiKit.display(600, 1))
	_name_edit.add_theme_font_size_override("font_size", 19)
	_name_edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_name_edit.add_theme_stylebox_override("focus", UiKit.box(Color(1, 1, 1, 0.07), UiKit.GOLD, 14, 1, 6))
	_name_edit.text = str(st.get_value("name"))
	_name_edit.text_changed.connect(func(t): st.set_value("name", t); st.save())
	_name_edit.text_submitted.connect(func(_t): _name_edit.release_focus())
	_name_edit.tooltip_text = "Tu nombre (se puede editar acá)"
	row.add_child(_name_edit)
	chip.add_child(row)
	_chrome.add_child(chip)
	# back
	_back = MButton.new("Volver", "ghost", "ui_back")
	_back.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_back.position = Vector2(-72 - 230 - 16 - 128, 27)
	_back.size = Vector2(128, 38)
	_back.custom_minimum_size = Vector2(128, 38)
	_back.pressed.connect(back)
	_chrome.add_child(_back)
	# hints + version
	_hints = HBoxContainer.new()
	_hints.add_theme_constant_override("separation", 22)
	_hints.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_hints.position = Vector2(-72 - 420, -50)
	_hints.custom_minimum_size = Vector2(420, 28)
	_hints.alignment = BoxContainer.ALIGNMENT_END
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.add_child(_hints)
	var ver := UiKit.label("v%s" % str(ProjectSettings.get_setting("application/config/version", "0")), 13, UiKit.DIM)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position = Vector2(72, -42)
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.add_child(ver)


func _update_chrome(id: String) -> void:
	_chrome.visible = id != "splash"
	create_tween().tween_property(_shade, "modulate:a", 0.0 if id == "splash" else (0.5 if id == "champions" else 1.0), 0.3)
	if _name_edit.text != str(st.get_value("name")) and not _name_edit.has_focus():
		_name_edit.text = str(st.get_value("name"))
	_back.visible = nav.can_back() and id != "hub"
	for c in _hints.get_children():
		c.queue_free()
	for h in _views[id].hints():
		var key := UiKit.heading(str(h[0]), 13, Color("#1a0800"), 700, 1, HORIZONTAL_ALIGNMENT_CENTER)
		key.add_theme_stylebox_override("normal", UiKit.box(Color(1, 0.85, 0.55, 0.9), Color(0, 0, 0, 0), 4, 0, 4))
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var txt := UiKit.label(str(h[1]), 13, UiKit.MUTED)
		txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 7)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pair.add_child(key)
		pair.add_child(txt)
		_hints.add_child(pair)


# ---------------------------------------------------------------- input / audio

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if nav.current == "splash":
		var any: bool = (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) or (event is InputEventJoypadButton and event.pressed)
		if any:
			get_viewport().set_input_as_handled()
			UiSound.play("uiConfirm")
			nav.advance_from_splash()
			_present("hub", 1)
			backdrop_requested.emit("hub")
		return
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		var fo := get_viewport().gui_get_focus_owner()
		get_viewport().set_input_as_handled()
		if fo is LineEdit:
			fo.release_focus()
			return
		if nav.can_back():
			back()


func _apply_system_settings() -> void:
	UiSound.apply_volumes()
	if DisplayServer.get_name() != "headless":
		var want := DisplayServer.WINDOW_MODE_FULLSCREEN if st.get_value("fullscreen") else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != want and not OS.has_feature("editor"):
			DisplayServer.window_set_mode(want)
	if _music != null:
		_music.volume_db = linear_to_db(maxf(0.0001, float(st.get_value("music")) * 0.6))


## Called by the settings screen after any change.
func settings_changed(key: String) -> void:
	st.save()
	if key == "gfx":
		gfx_changed.emit(st.get_value("gfx"))
	_apply_system_settings()


func _start_music() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _music == null:
		_music = AudioStreamPlayer.new()
		_music.stream = MenuMusic.make()
		add_child(_music)
	_apply_system_settings()
	if not _music.playing:
		_music.play()


func _stop_music() -> void:
	if _music != null:
		_music.stop()


func _exit_tree() -> void:
	if _music != null:
		_music.stop()
		_music.stream = null
	UiSound.release()
