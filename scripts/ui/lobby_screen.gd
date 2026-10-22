class_name LobbyScreen
extends StagedScreen
## Waiting room: team columns with portraits, host settings, class picker, connection info, start.

signal settings(s: Dictionary)
signal start_pressed
signal ready_changed(on: bool)
signal leave_pressed
signal invite_pressed

var is_host := false
var info_text := ""
var _title: Label
var _hint: Label
var _cols := {}
var _mode: Segmented
var _map: Segmented
var _diff: Segmented
var _pref: Segmented
var _tiles := {}
var _start: MButton
var _ready_button: MButton
var _is_ready := false
var _building := false
var _info_box: VBoxContainer
var _info_btns: HBoxContainer
var _info_label: Label
var _local_ips: Array = []
var _public_ip := ""
var _port := 7777
var _http: HTTPRequest
var _invite: MButton
var _copy_local: MButton
var _copy_public: MButton


func _ready() -> void:
	stage.add_child(UiKit.heading("SALA DE ESPERA", 46, UiKit.INK, 700, 3))
	stage.get_child(0).position = Vector2(72, 40)
	_title = UiKit.label("", 17, UiKit.GOLD)
	_title.position = Vector2(74, 98)
	stage.add_child(_title)
	_hint = UiKit.label("", 14, UiKit.MUTED)
	_hint.position = Vector2(74, 124)
	_hint.custom_minimum_size = Vector2(900, 0)
	stage.add_child(_hint)
	# team columns
	for t in ["red", "blue"]:
		var tint: Color = UiKit.RED if t == "red" else UiKit.BLUE
		var p := UiKit.glass(Color(tint.r, tint.g, tint.b, 0.7), 14, 16)
		p.position = Vector2(72 if t == "red" else 668, 150)
		p.custom_minimum_size = Vector2(540, 0)
		stage.add_child(p)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		var head := UiKit.heading(("EQUIPO ROJO" if t == "red" else "EQUIPO AZUL"), 22, tint, 700, 3)
		v.add_child(head)
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 6)
		v.add_child(list)
		p.add_child(v)
		_cols[t] = list
	var vs := UiKit.heading("VS", 40, UiKit.GOLD, 700, 2, HORIZONTAL_ALIGNMENT_CENTER)
	vs.position = Vector2(612, 226)
	vs.custom_minimum_size = Vector2(56, 0)
	stage.add_child(vs)
	# options
	var op := UiKit.glass(UiKit.LINE, 14, 16)
	op.position = Vector2(72, 430)
	op.custom_minimum_size = Vector2(540, 0)
	stage.add_child(op)
	var oc := VBoxContainer.new()
	oc.add_theme_constant_override("separation", 6)
	op.add_child(oc)
	_mode = _opt(oc, "Modo (lo elige el anfitrión)", [["2", "2v2"], ["3", "3v3"]], "2")
	_map = _opt(oc, "Arena", [["random", "Aleatoria"], ["bridge", "Puente"], ["pillars", "Pilares"], ["tomb", "Tumba"], ["living", "Vivos"], ["spire", "Sol Eterno"]], "random")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	oc.add_child(row)
	_diff = _opt(row, "Bots", [["easy", "Fácil"], ["normal", "Normal"], ["hard", "Difícil"]], "normal")
	_pref = _opt(row, "Tu equipo", [["any", "Al azar"], ["red", "Rojo"], ["blue", "Azul"]], "any")
	_mode.changed.connect(func(v): if not _building: settings.emit({"mode": int(v)}))
	_map.changed.connect(func(v): if not _building: settings.emit({"map": v}))
	_diff.changed.connect(func(v): if not _building: settings.emit({"diff": v}))
	_pref.changed.connect(func(v): if not _building: settings.emit({"pref": v}))
	# class picker
	var cap := UiKit.caption("Tu campeón", UiKit.MUTED, 12)
	cap.position = Vector2(668, 436)
	stage.add_child(cap)
	var tr := HBoxContainer.new()
	tr.position = Vector2(668, 458)
	tr.add_theme_constant_override("separation", 10)
	stage.add_child(tr)
	for id in GameData.classes:
		var tile := RosterTile.new(id)
		tile.custom_minimum_size = Vector2(100, 112)
		tile.pressed.connect(func(): settings.emit({"cls": id, "spec": str(SettingsStore.shared().get_value("specs").get(id, ""))}))
		tr.add_child(tile)
		_tiles[id] = tile
	# connection info
	_info_box = VBoxContainer.new()
	_info_box.position = Vector2(668, 584)
	_info_box.custom_minimum_size = Vector2(540, 0)
	_info_box.add_theme_constant_override("separation", 6)
	_info_box.visible = false
	stage.add_child(_info_box)
	_info_label = UiKit.label("", 13, UiKit.GOLD)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(_info_label)
	_info_btns = HBoxContainer.new()
	_info_btns.add_theme_constant_override("separation", 8)
	_info_box.add_child(_info_btns)
	_copy_local = MButton.new("Copiar IP local", "secondary", "ui_copy")
	_copy_local.custom_minimum_size = Vector2(170, 36)
	_copy_local.add_theme_font_size_override("font_size", 14)
	_copy_local.pressed.connect(func(): _copy(_local_ips[0] if not _local_ips.is_empty() else ""))
	_copy_public = MButton.new("Copiar IP pública", "secondary", "ui_copy")
	_copy_public.custom_minimum_size = Vector2(190, 36)
	_copy_public.add_theme_font_size_override("font_size", 14)
	_copy_public.pressed.connect(func(): _copy(_public_ip))
	_info_btns.add_child(_copy_local)
	_info_btns.add_child(_copy_public)
	_http = HTTPRequest.new()
	_http.timeout = 6.0
	_http.request_completed.connect(_on_public_ip)
	add_child(_http)
	# buttons
	var leave := MButton.new("Salir de la sala", "ghost", "ui_back")
	leave.position = Vector2(72, 660)
	leave.size = Vector2(190, 40)
	leave.pressed.connect(func(): leave_pressed.emit())
	stage.add_child(leave)
	_start = MButton.new("EMPEZAR PARTIDA", "primary", "ui_play")
	_start.position = Vector2(868, 650)
	_start.size = Vector2(340, 58)
	_start.custom_minimum_size = Vector2(340, 58)
	_start.pressed.connect(func(): start_pressed.emit())
	stage.add_child(_start)
	_ready_button = MButton.new("LISTO", "secondary")
	_ready_button.position = Vector2(620, 660)
	_ready_button.size = Vector2(220, 40)
	_ready_button.pressed.connect(func(): ready_changed.emit(not _is_ready))
	stage.add_child(_ready_button)


func _opt(parent: Control, title: String, options: Array, initial: String) -> Segmented:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(UiKit.caption(title, UiKit.MUTED, 11))
	var seg := Segmented.new().setup(options, initial)
	box.add_child(seg)
	parent.add_child(box)
	return seg


func _slot(e: Dictionary, msg: Dictionary, team: String) -> Control:
	var tint: Color = UiKit.RED if team == "red" else UiKit.BLUE
	var p := PanelContainer.new()
	var bot: bool = e.bot
	var me: bool = not bot and e.peer == msg.you
	p.add_theme_stylebox_override("panel", UiKit.box(Color(1, 1, 1, 0.06 if not me else 0.12), Color(tint.r, tint.g, tint.b, 0.9 if me else 0.25), 8, 2 if me else 1, 8))
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 12)
	p.add_child(r)
	var art := TextureRect.new()
	art.texture = Portraits.bust(str(e.cls)) if GameData.classes.has(e.cls) else null
	art.custom_minimum_size = Vector2(72, 46)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.modulate = Color(1, 1, 1, 0.45) if bot else Color.WHITE
	r.add_child(art)
	var tc := VBoxContainer.new()
	tc.alignment = BoxContainer.ALIGNMENT_CENTER
	tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(tc)
	var nm := str(e.name) if not bot else "Lugar libre"
	if me:
		nm += "  (vos)"
	tc.add_child(UiKit.heading(nm, 22, UiKit.GOLD if me else (UiKit.DIM if bot else UiKit.INK), 700, 1))
	var cls_name := str(GameData.classes.get(e.cls, {}).get("name", ""))
	var sp := str(e.get("spec", ""))
	if sp != "" and GameData.classes.get(e.cls, {}).has("specs"):
		cls_name += " · " + str(GameData.classes[e.cls].specs[sp].name)
	var status := " · LISTO" if e.get("ready", false) else " · esperando"
	tc.add_child(UiKit.label(("Bot · " + cls_name) if bot else cls_name + status, 13, UiKit.GREEN if not bot and e.get("ready", false) else UiKit.MUTED))
	if not bot and e.peer == msg.host:
		var tag := UiKit.heading("ANFITRIÓN", 12, Color("#1a0800"), 700, 2, HORIZONTAL_ALIGNMENT_CENTER)
		tag.add_theme_stylebox_override("normal", UiKit.box(UiKit.GOLD, Color(0, 0, 0, 0), 4, 0, 5))
		tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(tag)
	elif not bot:
		var tag2 := UiKit.heading("CONECTADO", 12, UiKit.GREEN, 700, 2, HORIZONTAL_ALIGNMENT_CENTER)
		tag2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(tag2)
	return p


## Host of a Steam room: no IPs, just the invite button (Steam relays the connection).
func show_steam_info() -> void:
	_info_box.visible = true
	_info_label.text = "Sala de Steam: tus amigos entran desde Steam (lista de amigos o Shift+Tab)."
	_copy_local.visible = false
	_copy_public.visible = false
	if _invite == null:
		_invite = MButton.new("Invitar amigos", "steam", "ui_people")
		_invite.custom_minimum_size = Vector2(0, 38)
		_invite.add_theme_font_size_override("font_size", 16)
		_invite.pressed.connect(func(): invite_pressed.emit())
		_info_btns.add_child(_invite)
	_invite.visible = true


## Host only: show the addresses friends can use, and look up the public IP (fails quietly offline).
func show_connect_info(local_ips: Array, port: int) -> void:
	_local_ips = local_ips
	_port = port
	_public_ip = ""
	_info_box.visible = true
	_copy_local.visible = true
	_copy_public.visible = true
	if _invite != null:
		_invite.visible = false
	_refresh_info("buscando…")
	if _http.request("https://api.ipify.org") != OK:
		_refresh_info("no disponible")


func _on_public_ip(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var ip := body.get_string_from_utf8().strip_edges()
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and ip.count(".") == 3 and ip.length() < 16:
		_public_ip = ip
		_refresh_info(ip)
	else:
		_refresh_info("no disponible")


func _refresh_info(public_text: String) -> void:
	var local := ", ".join(_local_ips) if not _local_ips.is_empty() else "(sin red)"
	_info_label.text = "Puerto UDP %d  ·  IP local: %s  ·  IP pública: %s" % [_port, local, public_text]


func _copy(ip: String) -> void:
	if ip != "":
		DisplayServer.clipboard_set("%s:%d" % [ip, _port])
		_hint.text = "Copiado: %s:%d" % [ip, _port]


## A transient message (e.g. a server error) in the hint line.
func flash(text: String) -> void:
	_hint.text = text


func show_lobby(msg: Dictionary, host_flag: bool) -> void:
	_building = true
	is_host = host_flag
	_title.text = "Partida %dv%d" % [msg.mode, msg.mode]
	_mode.select(str(msg.mode), false)
	_map.select(msg.map, false)
	_diff.select(msg.diff, false)
	for s in [_mode, _map, _diff]:
		s.set_locked(not is_host)
	var me: Dictionary = {}
	for m in msg.members:
		if m.peer == msg.you:
			me = m
	if not me.is_empty():
		_pref.select(me.pref, false)
	_is_ready = me.get("ready", false)
	_ready_button.text = "NO ESTOY LISTO" if _is_ready else "LISTO"
	var my_cls := ""
	for t in ["red", "blue"]:
		var list: VBoxContainer = _cols[t]
		for c in list.get_children():
			c.queue_free()
		for e in msg.teams[t]:
			list.add_child(_slot(e, msg, t))
			if not e.bot and e.peer == msg.you:
				my_cls = str(e.cls)
	for id in _tiles:
		_tiles[id].selected = id == my_cls
	_start.visible = is_host
	_start.disabled = not msg.get("can_start", false)
	var humans: int = msg.members.size()
	if is_host:
		_hint.text = "%d jugador%s · Todos deben marcar Listo antes de empezar · Enter: chat" % [humans, "" if humans == 1 else "es"]
	else:
		_hint.text = "%d jugadores · Marcá Listo y esperá al anfitrión · Enter: chat" % humans
	_building = false
