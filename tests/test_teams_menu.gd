extends TestBase
## The Equipos screen, the online card in Jugar, the friends column's Invitar button and the queue bar. FakeOnline only
## replaces the transport, so the requests are the real ones; the server rules live in supabase/tests.

const SCRATCH := "user://test_teams_settings.cfg"
const ANA := "76561199000000001"
const BETO := "76561199000000002"
const CARO := "76561199000000003"


func _menu() -> MenuScreen:
	SettingsStore.path = SCRATCH
	SettingsStore.clear_shared()
	var m := MenuScreen.new()
	m.offer_tutorial = false
	m.visible = false
	tree.root.add_child(m)
	m.visible = true
	return m


func _drop(m: MenuScreen) -> void:
	tree.root.remove_child(m)
	m.free()
	SettingsStore.path = SettingsStore.PATH
	SettingsStore.clear_shared()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func _api() -> FakeOnline:
	var api := FakeOnline.new()
	api.base_url = "http://127.0.0.1:54321"
	api.anon_key = "anon"
	api.enabled = true
	api.clock = 1000.0
	api.token = "jwt"
	api.token_expires = 99999.0
	api.steam_id = ANA
	return api


## A menu with the online services wired, signed in (ready) unless `ready` is false.
func _online(ready := true) -> Dictionary:
	var m := _menu()
	var api := _api()
	var session := OnlineSession.new(api, FakeSteam.new().user(7001, "Ana"))
	session.state = "ready" if ready else "failed"
	session.note = "" if ready else "Steam no aceptó tu sesión en línea."
	var teams := TeamService.new(api)
	var q := QueueService.new(api)
	m.set_online(session, teams, q)
	m._input(_key(KEY_SPACE))
	return {"m": m, "api": api, "teams": teams, "q": q, "session": session}


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func _view(m: MenuScreen) -> MTeams:
	return m._views.teams as MTeams


func _team(mode := 2, captain := ANA) -> Dictionary:
	return {"id": "t%d" % mode, "mode": mode, "name": "Los Lobos", "captain": captain,
		"members": [{"steam_id": ANA, "name": "Ana", "captain": captain == ANA}, {"steam_id": BETO, "name": "Beto", "captain": captain == BETO}],
		"invites": [{"id": "inv1", "to": CARO, "to_name": "Caro", "expires_at": "x"}]}


func _last_path(api: FakeOnline, from_end := 0) -> String:
	var c: Dictionary = api.calls[api.calls.size() - 1 - from_end]
	return str(c.url).get_slice("/rpc/", 1)


func test_online_is_hidden_without_the_services() -> void:
	var m := _menu()
	m._input(_key(KEY_SPACE))
	check(not m.top_bar.tab("teams").visible, "sin online no hay pestaña Equipos")
	check(not (m._views.play as MPlay)._cards.online.visible, "ni tarjeta En línea en Jugar")
	check(not m._queue_bar.visible, "ni barra de búsqueda")
	_drop(m)


func test_online_tab_and_card_appear_with_the_services() -> void:
	var o := _online()
	var m: MenuScreen = o.m
	check(m.top_bar.tab("teams").visible, "con online aparece Equipos")
	m.top_bar.tab("teams").pressed.emit()
	eq(m.nav.current, "teams", "abre la pantalla")
	eq(m.top_bar.active, "teams", "queda marcada")
	var play := m._views.play as MPlay
	m.go("play")
	check(play._cards.online.visible, "tarjeta En línea")
	check(not play._cards.online.disabled, "habilitada con sesión")
	_drop(m)


func test_not_ready_shows_a_notice_and_no_controls() -> void:
	var o := _online(false)
	var m: MenuScreen = o.m
	m.go_tab("teams")
	var v := _view(m)
	check(v.notice.visible, "avisa")
	check(v.notice.text.contains("Steam"), "con el motivo en castellano")
	check(v.buttons.is_empty(), "sin controles que rompan")
	var play := m._views.play as MPlay
	m.go("play")
	check(play._cards.online.disabled, "la tarjeta de Jugar queda deshabilitada")
	_drop(m)


func test_create_team_sends_the_cleaned_name() -> void:
	var o := _online()
	var m: MenuScreen = o.m
	var api: FakeOnline = o.api
	m.go_tab("teams")
	var v := _view(m)
	check(v.buttons.has("create_2") and v.buttons.has("create_3"), "se puede crear de 2 y de 3")
	(v.buttons.name_2 as LineEdit).text = "  Los   Lobos "
	api.calls.clear()
	(v.buttons.create_2 as Button).pressed.emit()
	eq(_last_path(api, 2), "create_team", "pide crear")
	eq(JSON.parse_string(api.calls[0].body), {"p_mode": 2.0, "p_name": "Los Lobos"}, "con el nombre limpio y la modalidad")
	_drop(m)


func test_captain_manages_members_and_invites() -> void:
	var o := _online()
	var m: MenuScreen = o.m
	var api: FakeOnline = o.api
	var teams: TeamService = o.teams
	m.go_tab("teams")
	teams.teams = [_team(2, ANA)]
	var v := _view(m)
	v._rebuild()
	check(not v.buttons.has("create_2"), "con equipo ya no ofrece crear")
	check(v.buttons.has("kick_%s" % BETO), "el capitán puede echar")
	check(not v.buttons.has("kick_%s" % ANA), "pero no a sí mismo")
	check(v.buttons.has("transfer_%s" % BETO), "y pasar la capitanía")
	check(v.buttons.has("cancel_inv1"), "y cancelar una invitación")
	api.calls.clear()
	(v.buttons["kick_%s" % BETO] as Button).pressed.emit()
	eq(_last_path(api, 2), "kick_member", "echar")
	eq(JSON.parse_string(api.calls[0].body).p_steam_id, BETO, "id como texto")
	teams.teams = [_team(2, ANA)]
	v._rebuild()
	api.calls.clear()
	(v.buttons.invite_2_id as LineEdit).text = CARO
	(v.buttons.invite_2 as Button).pressed.emit()
	eq(_last_path(api, 2), "invite_to_team", "invitar por Steam id")
	eq(JSON.parse_string(api.calls[0].body).p_steam_id, CARO, "al id escrito")
	teams.teams = [_team(2, ANA)]
	v._rebuild()
	api.calls.clear()
	var leave: Button = v.buttons.leave_2
	check(leave.text.contains("Disolver"), "el capitán disuelve")
	leave.pressed.emit()
	eq(api.calls.size(), 0, "disolver pide confirmación")
	(v.buttons.leave_2 as Button).pressed.emit()
	eq(_last_path(api, 2), "disband_team", "al confirmar disuelve")
	_drop(m)


func test_member_cannot_manage_and_can_leave() -> void:
	var o := _online()
	var m: MenuScreen = o.m
	var api: FakeOnline = o.api
	m.go_tab("teams")
	(o.teams as TeamService).teams = [_team(3, BETO)]
	var v := _view(m)
	v._rebuild()
	check(not v.buttons.has("kick_%s" % BETO) and not v.buttons.has("invite_3"), "sin controles de capitán")
	check((v.buttons.leave_3 as Button).text.contains("Irse"), "puede irse")
	api.calls.clear()
	(v.buttons.leave_3 as Button).pressed.emit()
	(v.buttons.leave_3 as Button).pressed.emit()
	eq(_last_path(api, 2), "leave_team", "tras confirmar se va")
	_drop(m)


func test_invitations_accept_and_decline() -> void:
	var o := _online()
	var m: MenuScreen = o.m
	var api: FakeOnline = o.api
	m.go_tab("teams")
	(o.teams as TeamService).invites = [{"id": "i9", "team_id": "t", "team_name": "Cuervos", "mode": 2, "from": BETO, "from_name": "Beto", "expires_at": "x"}]
	(o.q as QueueService).group_invites = [{"id": "g9", "mode": 3, "from": CARO, "from_name": "Caro", "team_name": null}]
	var v := _view(m)
	v._rebuild()
	check(v.buttons.has("accept_i9") and v.buttons.has("decline_i9"), "invitación de equipo")
	check(v.buttons.has("confirm_g9") and v.buttons.has("gdecline_g9"), "invitación de grupo")
	api.calls.clear()
	(v.buttons.accept_i9 as Button).pressed.emit()
	eq(_last_path(api, 2), "accept_invite", "aceptar")
	(o.teams as TeamService).invites = [{"id": "i9", "team_id": "t", "team_name": "Cuervos", "mode": 2, "from": BETO, "from_name": "Beto", "expires_at": "x"}]
	v._rebuild()
	api.calls.clear()
	(v.buttons.decline_i9 as Button).pressed.emit()
	eq(_last_path(api, 2), "decline_invite", "rechazar")
	(o.q as QueueService).group_invites = [{"id": "g9", "mode": 3, "from": CARO, "from_name": "Caro", "team_name": null}]
	v._rebuild()
	api.calls.clear()
	(v.buttons.confirm_g9 as Button).pressed.emit()
	eq(_last_path(api, 2), "group_confirm", "confirmar grupo")
	_drop(m)


func test_group_needs_everyone_confirmed_before_searching() -> void:
	var o := _online()
	var m: MenuScreen = o.m
	var api: FakeOnline = o.api
	var q: QueueService = o.q
	m.go_tab("teams")
	var v := _view(m)
	v._rebuild()
	check(v.buttons.has("new_group_2") and v.buttons.has("new_group_3"), "sin grupo: ofrece crearlo")
	q.group = {"id": "g1", "mode": 2, "team_id": null, "leader": ANA, "queued": false,
		"members": [{"steam_id": ANA, "name": "Ana", "confirmed": true}, {"steam_id": BETO, "name": "Beto", "confirmed": false}]}
	v._rebuild()
	check((v.buttons.group_search as Button).disabled, "con alguien sin confirmar no se puede buscar")
	check(v.buttons.has("gkick_%s" % BETO), "la líder puede quitar a alguien")
	q.group.members[1].confirmed = true
	v._rebuild()
	check(not (v.buttons.group_search as Button).disabled, "con todos confirmados se puede")
	api.calls.clear()
	(v.buttons.group_search as Button).pressed.emit()
	eq(_last_path(api, 0), "join_queue", "busca partida")
	eq(JSON.parse_string(api.calls[0].body).p_group, "g1", "con el grupo")
	check(m._queue_bar.visible, "y aparece la barra de búsqueda en todas las pantallas")
	check(m._queue_label.text.contains("2v2"), "con la modalidad")
	m.queue_cancel()
	check(not m._queue_bar.visible, "cancelar la oculta")
	_drop(m)


func test_prefill_from_a_friend_fills_the_id_boxes() -> void:
	var o := _online()
	var m: MenuScreen = o.m
	(o.api as FakeOnline).queue_ok([_team(2, ANA)])  # what the screen's own reload will fetch
	(o.api as FakeOnline).queue_ok([])
	m.invite_friend({"id": int(CARO), "name": "Caro"})
	eq(m.nav.current, "teams", "abre Equipos")
	eq((_view(m).buttons.invite_2_id as LineEdit).text, CARO, "con el id del amigo")
	_drop(m)


func test_friends_column_offers_invitar_only_when_online_is_ready() -> void:
	var p := SocialPanel.new()
	tree.root.add_child(p)
	var net := FakeSteam.new()
	var me := net.user(7001, "Ana")
	var friend := net.user(7002, "Beto")
	net.befriend(7001, 7002)
	p.bind(me)
	check(p.rows.size() >= 1, "hay un amigo")
	check(not p.rows[0].invite.visible, "sin online no hay Invitar")
	p.invite_enabled = true
	check(p.rows[0].invite.visible, "con online sí")
	var got: Array = []
	p.invite_pressed.connect(func(f): got.append(f))
	p.rows[0].invite.pressed.emit()
	eq(got.size(), 1, "emite el amigo")
	eq(int(got[0].id), 7002, "el correcto")
	friend = null
	p.queue_free()


func test_matched_bar_says_what_it_waits_for() -> void:
	var o := _online()
	var m: MenuScreen = o.m
	var q: QueueService = o.q
	q.state = "matched"
	q.current = {"id": "m1", "host": BETO, "is_host": false, "lobby_id": "", "side": "red", "sides": {}}
	m._refresh_queue_bar()
	check(m._queue_bar.visible, "visible")
	check(m._queue_label.text.contains("esperando la sala"), "el invitado espera la sala del anfitrión")
	q.current.lobby_id = "109775241000000001"
	m._refresh_queue_bar()
	check(m._queue_label.text.contains("entrando"), "con la sala, entra")
	_drop(m)
