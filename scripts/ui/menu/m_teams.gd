class_name MTeams
extends MenuView
## "Equipos": persistent 2v2 / 3v3 teams (create, invite by Steam friend or id, accept or decline, kick, hand over the
## captaincy, leave, disband, match history) and the group used to search together. Everything is a request to the
## server (TeamService, QueueService); this screen only draws their last known state. There is no rating anywhere.
## Without the online session it says why instead of showing controls.

const COL_W := 548.0
const REFRESH_EVERY := 10.0

## Handles for tests: name -> control ("create_2", "invite_2", "kick_<steam id>", "accept_<id>", "decline_<id>", ...).
var buttons := {}
var notice: Label
var history_labels := {}  # team id -> Label

var _left: VBoxContainer
var _right: VBoxContainer
var _retry: MButton
var _ids: Array[LineEdit] = []
var _history := {}  # team id -> [{at, mode, won, opponents}]
var _confirm := ""  # a destructive button asks twice: the key of the one pending
var _timer: Timer


func section() -> String:
	return "Equipos"


func _ready() -> void:
	header("Equipos", "Tu equipo fijo de 2v2 o 3v3 y los grupos para buscar partida juntos.")
	notice = UiKit.label("", 18, UiKit.MUTED)
	notice.position = Vector2(72, 200)
	notice.custom_minimum_size = Vector2(900, 0)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(notice)
	_retry = MButton.new("Reintentar", "secondary")
	_retry.position = Vector2(72, 260)
	_retry.custom_minimum_size = Vector2(180, 44)
	_retry.pressed.connect(func(): if menu.online_session != null: menu.online_session.start())
	add_child(_retry)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(72, 176)
	scroll.custom_minimum_size = Vector2(1136, 500)
	scroll.size = Vector2(1136, 500)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 20)
	scroll.add_child(cols)
	_left = VBoxContainer.new()
	_left.custom_minimum_size = Vector2(COL_W, 0)
	_left.add_theme_constant_override("separation", 14)
	cols.add_child(_left)
	_right = VBoxContainer.new()
	_right.custom_minimum_size = Vector2(COL_W, 0)
	_right.add_theme_constant_override("separation", 14)
	cols.add_child(_right)
	_timer = Timer.new()
	_timer.wait_time = REFRESH_EVERY
	_timer.timeout.connect(_reload)
	add_child(_timer)
	menu.online_changed.connect(_rebuild)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			_timer.start()
		else:
			_timer.stop())
	_rebuild()


func menu_enter() -> void:
	_confirm = ""
	_reload()
	_rebuild()


func first_focus() -> Control:
	return buttons.get("create_2") if buttons.has("create_2") else _retry


func hints() -> Array:
	return [["Tab", "Moverse"], ["Enter", "Elegir"], ["Esc", "Volver"]]


## "Invitar" from the friends column: every Steam id box gets that player.
func prefill(steam_id: String) -> void:
	for e in _ids:
		if is_instance_valid(e):
			e.text = steam_id
	if not _ids.is_empty():
		_ids[0].grab_focus()


## Reloads teams, invitations, the group and the history from the server (quietly when it is unreachable).
func _reload() -> void:
	if not menu.online_ready():
		return
	menu.team_service.refresh(func(_r): _fetch_history())
	menu.queue.refresh_group()


func _fetch_history() -> void:
	for t in menu.team_service.teams:
		var id := str(t.id)
		menu.queue.team_history(id, func(r: Dictionary):
			if r.ok and typeof(r.data) == TYPE_ARRAY:
				_history[id] = r.data
				_fill_history(id))
	_rebuild()


func _say(text: String) -> void:
	menu.set_status(text)


## Standard callback of an action: shows the server's refusal in plain Spanish.
func _after(r: Dictionary, ok_text := "") -> void:
	if r.ok:
		if ok_text != "":
			_say(ok_text)
	else:
		_say(TeamService.error_text(str(r.get("error", ""))) if not _queue_code(str(r.get("error", ""))) else QueueService.error_text(str(r.get("error", ""))))
	_rebuild()


static func _queue_code(code: String) -> bool:
	return code in ["group_not_found", "not_leader", "group_full", "not_confirmed", "group_locked", "already_in_group", "already_queued", "already_in_match", "invalid_target", "invalid_mode"]


# ---------------------------------------------------------------- drawing

func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _rebuild() -> void:
	if _left == null:
		return
	_clear(_left)
	_clear(_right)
	buttons.clear()
	history_labels.clear()
	_ids.clear()
	var ready: bool = menu.online_ready()
	notice.visible = not ready
	_retry.visible = not ready and menu.online_session != null and menu.online_session.state == "failed"
	if not ready:
		notice.text = menu.online_notice()
		return
	for mode in [2, 3]:
		_team_card(mode)
	_invites_card()
	_group_card()


func _card(parent: Control, title: String, accent: Color = UiKit.LINE) -> VBoxContainer:
	var p := UiKit.glass(accent, 12, 14, 3.0, 0.7)
	p.custom_minimum_size = Vector2(COL_W, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	p.add_child(col)
	col.add_child(UiKit.heading(title, 22, UiKit.INK, 700, 2))
	parent.add_child(p)
	return col


func _team_card(mode: int) -> void:
	var team := menu.team_service.team_for_mode(mode)
	var col := _card(_left, "EQUIPO %dv%d" % [mode, mode], UiKit.GOLD)
	if team.is_empty():
		col.add_child(UiKit.label("Todavía no tenés equipo de %dv%d. Elegí un nombre y creálo; después invitá a tus compañeros." % [mode, mode], 14, UiKit.MUTED))
		var name := _line("Nombre del equipo (3 a 20 letras)")
		col.add_child(name)
		var create := MButton.new("Crear equipo", "accent")
		create.custom_minimum_size = Vector2(0, 42)
		create.pressed.connect(func(): menu.team_service.create_team(mode, name.text, func(r): _after(r, "Equipo creado.")))
		col.add_child(create)
		buttons["create_%d" % mode] = create
		buttons["name_%d" % mode] = name
		return
	var tid := str(team.id)
	var captain: bool = menu.team_service.is_captain(team)
	col.add_child(UiKit.label("%s%s" % [team.name, "  (sos el capitán)" if captain else ""], 18, UiKit.GOLD))
	for m in team.members:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var is_me: bool = str(m.steam_id) == menu.team_service.api.steam_id
		var l := UiKit.label("%s%s%s" % ["★ " if m.captain else "", m.name, " (vos)" if is_me else ""], 16, UiKit.INK)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if captain and not is_me:
			var pass_b := _small("Pasar capitanía")
			pass_b.pressed.connect(func(): menu.team_service.transfer_captain(tid, str(m.steam_id), func(r): _after(r, "Ahora el capitán es %s." % m.name)))
			row.add_child(pass_b)
			buttons["transfer_%s" % m.steam_id] = pass_b
			var kick := _small("Echar")
			kick.pressed.connect(func(): menu.team_service.kick_member(tid, str(m.steam_id), func(r): _after(r, "%s ya no está en el equipo." % m.name)))
			row.add_child(kick)
			buttons["kick_%s" % m.steam_id] = kick
		col.add_child(row)
	for inv in team.invites:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := UiKit.label("Invitado: %s" % inv.to_name, 15, UiKit.MUTED)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if captain:
			var cancel := _small("Cancelar")
			cancel.pressed.connect(func(): menu.team_service.cancel_invite(str(inv.id), func(r): _after(r)))
			row.add_child(cancel)
			buttons["cancel_%s" % inv.id] = cancel
		col.add_child(row)
	if captain:
		col.add_child(_invite_row(func(id: String): menu.team_service.invite(tid, id, func(r): _after(r, "Invitación enviada.")), "invite_%d" % mode))
		if not menu.queue.in_group():
			var grp := _small("Armar grupo con este equipo")
			grp.pressed.connect(func(): menu.queue.create_group(mode, tid, func(r): _after(r, "Grupo armado: invitá a tus compañeros.")))
			col.add_child(grp)
			buttons["group_%d" % mode] = grp
	var leave := _small("Disolver equipo" if captain else "Irse del equipo")
	var key := "leave_%d" % mode
	leave.pressed.connect(func():
		if _confirm != key:
			_confirm = key
			leave.text = "¿Seguro? Tocá de nuevo"
			return
		_confirm = ""
		if captain:
			menu.team_service.disband_team(tid, func(r): _after(r, "Equipo disuelto."))
		else:
			menu.team_service.leave_team(tid, func(r): _after(r, "Saliste del equipo.")))
	col.add_child(leave)
	buttons[key] = leave
	col.add_child(UiKit.caption("ÚLTIMAS PARTIDAS", UiKit.DIM, 11))
	var hist := UiKit.label("", 14, UiKit.MUTED)
	hist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hist)
	history_labels[tid] = hist
	_fill_history(tid)


func _fill_history(team_id: String) -> void:
	var l: Label = history_labels.get(team_id)
	if l == null or not is_instance_valid(l):
		return
	var rows: Array = _history.get(team_id, [])
	if rows.is_empty():
		l.text = "Todavía no jugaron partidas con resultado."
		return
	var lines: Array = []
	for h in rows.slice(0, 5):
		lines.append("%s %dv%d · contra %s" % ["Ganaron" if h.won else "Perdieron", int(h.mode), int(h.mode), ", ".join(PackedStringArray(h.opponents))])
	l.text = "\n".join(lines)


func _invites_card() -> void:
	var col := _card(_right, "INVITACIONES", UiKit.LAVA)
	var any := false
	for i in menu.team_service.invites:
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var l := UiKit.label("%s te invitó a %s (%dv%d)" % [i.from_name, i.team_name, int(i.mode), int(i.mode)], 15, UiKit.INK)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(l)
		var yes := _small("Aceptar")
		yes.pressed.connect(func(): menu.team_service.accept_invite(str(i.id), func(r): _after(r, "Te uniste a %s." % i.team_name)))
		row.add_child(yes)
		buttons["accept_%s" % i.id] = yes
		var no := _small("Rechazar")
		no.pressed.connect(func(): menu.team_service.decline_invite(str(i.id), func(r): _after(r)))
		row.add_child(no)
		buttons["decline_%s" % i.id] = no
		col.add_child(row)
	for g in menu.queue.group_invites:
		any = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var what: String = "al grupo de %s" % g.team_name if g.get("team_name") != null else "a un grupo"
		var l := UiKit.label("%s te invitó %s (%dv%d)" % [g.from_name, what, int(g.mode), int(g.mode)], 15, UiKit.INK)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(l)
		var yes := _small("Confirmar")
		yes.pressed.connect(func(): menu.queue.group_confirm(str(g.id), func(r): _after(r, "Te uniste al grupo.")))
		row.add_child(yes)
		buttons["confirm_%s" % g.id] = yes
		var no := _small("Rechazar")
		no.pressed.connect(func(): menu.queue.group_decline(str(g.id), func(r): _after(r)))
		row.add_child(no)
		buttons["gdecline_%s" % g.id] = no
		col.add_child(row)
	if not any:
		col.add_child(UiKit.label("No tenés invitaciones pendientes.", 14, UiKit.MUTED))


func _group_card() -> void:
	var col := _card(_right, "GRUPO PARA BUSCAR PARTIDA", UiKit.GREEN)
	var q: QueueService = menu.queue
	if not q.in_group():
		col.add_child(UiKit.label("Un grupo busca partida junto: queda del mismo lado. Cada integrante tiene que confirmar. También podés armarlo desde tu equipo.", 14, UiKit.MUTED))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		for mode in [2, 3]:
			var b := _small("Crear grupo %dv%d" % [mode, mode])
			b.pressed.connect(func(): q.create_group(mode, "", func(r): _after(r, "Grupo creado: invitá a tus compañeros.")))
			row.add_child(b)
			buttons["new_group_%d" % mode] = b
		col.add_child(row)
		return
	var g := q.group
	var leader := q.is_leader()
	var title := "Grupo %dv%d%s" % [g.mode, g.mode, " (de un equipo)" if g.get("team_id") != null else ""]
	col.add_child(UiKit.label(title, 18, UiKit.GREEN))
	var all_ok := true
	for m in g.members:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		all_ok = all_ok and bool(m.confirmed)
		var l := UiKit.label("%s%s  ·  %s" % ["★ " if str(m.steam_id) == str(g.leader) else "", m.name, "listo" if m.confirmed else "esperando confirmación"], 15, UiKit.INK if m.confirmed else UiKit.MUTED)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if leader and str(m.steam_id) != q.api.steam_id and not g.queued:
			var kick := _small("Quitar")
			kick.pressed.connect(func(): q.group_kick(str(m.steam_id), func(r): _after(r)))
			row.add_child(kick)
			buttons["gkick_%s" % m.steam_id] = kick
		col.add_child(row)
	if leader and not g.queued and g.members.size() < int(g.mode):
		col.add_child(_invite_row(func(id: String): q.group_add(id, func(r): _after(r, "Invitación enviada.")), "ginvite"))
	if leader:
		var go := MButton.new("Buscar partida %dv%d con el grupo" % [g.mode, g.mode], "accent")
		go.custom_minimum_size = Vector2(0, 42)
		go.disabled = g.queued or not all_ok
		go.tooltip_text = "Faltan integrantes por confirmar." if not all_ok else ""
		go.pressed.connect(func(): menu.queue_join(int(g.mode), true))
		col.add_child(go)
		buttons["group_search"] = go
	var leave := _small("Disolver grupo" if leader else "Salir del grupo")
	var key := "leave_group"
	leave.pressed.connect(func():
		if _confirm != key and leader:
			_confirm = key
			leave.text = "¿Seguro? Tocá de nuevo"
			return
		_confirm = ""
		q.leave_group(func(r): _after(r, "Saliste del grupo.")))
	col.add_child(leave)
	buttons[key] = leave


## A Steam id box, a pick-a-friend list (online Steam friends) and an Invitar button.
func _invite_row(action: Callable, key: String) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var id := _line("Steam id del jugador (17 dígitos)")
	id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ids.append(id)
	row.add_child(id)
	var go := _small("Invitar")
	go.pressed.connect(func(): action.call(id.text.strip_edges()))
	id.text_submitted.connect(func(_t): action.call(id.text.strip_edges()))
	row.add_child(go)
	col.add_child(row)
	buttons[key] = go
	buttons[key + "_id"] = id
	var friends := _friend_pick(id)
	if friends != null:
		col.add_child(friends)
	return col


func _friend_pick(into: LineEdit) -> OptionButton:
	if menu.steam_backend == null or not menu.steam_backend.available():
		return null
	var list: Array = menu.steam_backend.friends()
	if list.is_empty():
		return null
	var ob := OptionButton.new()
	ob.add_item("Elegir un amigo de Steam…")
	var ids: Array = [""]
	for f in list:
		ob.add_item(str(f.name))
		ids.append(str(int(f.id)))
	ob.item_selected.connect(func(i: int): if i > 0: into.text = ids[i])
	return ob


func _line(placeholder: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(0, 40)
	e.add_theme_font_size_override("font_size", 16)
	return e


func _small(text: String) -> MButton:
	var b := MButton.new(text, "secondary")
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_size_override("font_size", 14)
	return b
