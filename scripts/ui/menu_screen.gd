class_name MenuScreen
extends Control
## Front end: splash -> hub -> play / setup / join -> champion select, plus settings.
## Navigation lives in MenuNav, persisted choices in SettingsStore (both unit-tested); this node only
## animates screens and forwards the launch signals main.gd listens to.

signal play_offline(cfg: Dictionary)
## "Arena de práctica" (training yard, offline) and the guided tutorial.
signal play_practice(cfg: Dictionary)
signal start_tutorial(cfg: Dictionary)
signal host(cfg: Dictionary, port: int)
signal join(cfg: Dictionary, address: String, port: int)
signal map_changed(map_id: String)
signal gfx_changed(choice: String)
signal steam_host(cfg: Dictionary, friends_only: bool)
signal steam_browse
signal steam_changed
## "Unirse" on a friend in the home's social panel: enter their Steam lobby.
signal steam_join(lobby_id: int)
## The splash/hub asks for the 3D backdrop mood: "splash" (cinematic flythrough) or "hub".
signal backdrop_requested(kind: String)

const DESIGN := Vector2(1280, 720)
const SLIDE := 64.0

var st: SettingsStore
var nav := MenuNav.new()
var status: Label
var steam_ok := false
var steam_text := "Steam no disponible"
## Friends, avatars and the overlay for the home screen (null until main.gd hands it over).
var steam_backend: SteamBackend = null
var top_bar: TopBar
## In-client private chat with friends (null without Steam).
var dm: DirectChat = null
var scale_ := 1.0
## The hub offers the tutorial on the first launch (off for scripted runs and screenshots).
var offer_tutorial := true

var _stage: Control
var _shade: TextureRect
var _views := {}
var _view: MenuView = null
var _tw: Tween
var _chrome: Control
var _bar_bg: ColorRect
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
	# The top bar spans the whole window (also on ultrawide, where the content stays 1280 wide and centred).
	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0.035, 0.022, 0.018, 0.94)
	_bar_bg.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bg.visible = false
	add_child(_bar_bg)
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	for pair in [["splash", MSplash], ["hub", MHub], ["play", MPlay], ["setup", MSetup], ["join", MJoin], ["champions", MChampions], ["settings", MSettings], ["howto", MHowTo]]:
		var v: MenuView = pair[1].new()
		v.menu = self
		_views[pair[0]] = v
		_stage.add_child(v)
	_build_chrome()
	status = UiKit.label("", 16, Color("#ffd9b3"), HORIZONTAL_ALIGNMENT_CENTER)
	status.add_theme_stylebox_override("normal", UiKit.box(Color(0.08, 0.04, 0.03, 0.92), UiKit.LINE_STRONG, 8, 1, 10))
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	# left of the home's chat window and friends column, so notices never cover them
	status.offset_left = 72
	status.offset_right = -(TopBar.SIDE + 16 + DmWindow.W + 16)
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
	_bar_bg.offset_bottom = TopBar.HEIGHT * scale_


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
		"howto":
			nav.go("howto")
		"setup", "champions", "join":
			nav.go("play")
			nav.start_flow("join" if id == "join" else "practice")
			if id == "champions":
				nav.next()
				if parts.size() > 1 and GameData.playable(parts[1]):
					st.set_value("cls", parts[1])
		"settings":
			nav.go("settings")
			(_views.settings as MSettings).select_tab(parts[1] if parts.size() > 1 else "graficos")
	_booted = true
	_present(nav.current, 1, true)
	backdrop_requested.emit("splash" if id == "splash" else "hub")


func set_steam_backend(b: SteamBackend) -> void:
	steam_backend = b
	dm = DirectChat.new(b) if b.available() else null
	set_steam(b.available(), b.status_text())
	_refresh_profile()
	if b.available():
		b.avatar_ready.connect(func(id, tex): if id == b.my_id(): top_bar.set_avatar(tex))
		b.request_avatar(b.my_id())


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
		"arena":
			play_practice.emit(cfg)
		_:
			play_offline.emit(cfg)
	# If main kept the menu visible (error), allow another try.
	get_tree().create_timer(0.5).timeout.connect(func(): _launching = false)


## "Cómo jugar" -> tutorial. Marks it as seen so it is only offered by itself once.
func launch_tutorial() -> void:
	if _launching:
		return
	_launching = true
	st.set_value("tutorial_seen", true)
	var cfg := _cfg()
	start_tutorial.emit(cfg)
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


# ---------------------------------------------------------------- chrome (top bar, hints, version)

func _build_chrome() -> void:
	_chrome = Control.new()
	_chrome.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_chrome)
	top_bar = TopBar.new()
	top_bar.play_pressed.connect(func(): go_tab("play"))
	top_bar.tab_pressed.connect(go_tab)
	top_bar.back_pressed.connect(back)
	top_bar.settings_pressed.connect(func(): go_tab("settings"))
	top_bar.quit_pressed.connect(func(): get_tree().quit())
	top_bar.name_edit.text_changed.connect(func(t): st.set_value("name", t); st.save())
	_chrome.add_child(top_bar)
	_refresh_profile()
	# hints + version, bottom of the content area (the friends column takes the right edge on the home)
	_hints = HBoxContainer.new()
	_hints.add_theme_constant_override("separation", 22)
	_hints.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_hints.position = Vector2(-TopBar.SIDE - 24 - 420, -40)
	_hints.custom_minimum_size = Vector2(420, 28)
	_hints.alignment = BoxContainer.ALIGNMENT_END
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.add_child(_hints)
	var ver := UiKit.label("v%s" % str(ProjectSettings.get_setting("application/config/version", "0")), 13, UiKit.DIM)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position = Vector2(24, -34)
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chrome.add_child(ver)


## Tabs and JUGAR: one level under the home, so Esc / Volver always lead back to it.
func go_tab(screen: String) -> void:
	if nav.current == screen:
		return
	nav.reset_to("hub")
	if screen != "hub":
		nav.go(screen)
	_present(nav.current, 1)


## Which part of the top bar is lit for a screen.
func active_tab(id: String) -> String:
	if nav.mode != "" or id in ["play", "setup", "join"]:
		return "play"
	return id if id in ["hub", "champions", "howto"] else ""


func _refresh_profile() -> void:
	var online := steam_backend != null and steam_backend.available()
	top_bar.set_profile(steam_backend.persona_name() if online else "", str(st.get_value("name")), online)


func _update_chrome(id: String) -> void:
	_chrome.visible = id != "splash"
	_bar_bg.visible = _chrome.visible
	create_tween().tween_property(_shade, "modulate:a", 0.0 if id == "splash" else (0.5 if id == "champions" else 1.0), 0.3)
	_refresh_profile()
	top_bar.set_active(active_tab(id))
	top_bar.back.visible = nav.can_back() and nav.mode != ""
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
	if nav.current == "settings" and (_views.settings as MSettings).capture_input(event):
		get_viewport().set_input_as_handled()
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
