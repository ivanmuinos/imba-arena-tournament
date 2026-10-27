extends TestBase
## In-client chat between friends who are both in the game: messages go player to player over Steam (no server),
## history and unread counts live on this PC. Clicking a friend's card opens the chat window on the home.

const HISTORY := "user://test_dm_history.json"
const SCRATCH := "user://test_dm_settings.cfg"


func _chat(b: SteamBackend) -> DirectChat:
	DirectChat.path = HISTORY
	DirectChat.clear_file()
	return DirectChat.new(b)


func _cleanup() -> void:
	DirectChat.clear_file()
	DirectChat.path = DirectChat.PATH


func test_messages_reach_the_friend_and_count_as_unread() -> void:
	var net := FakeSteam.new()
	var ana := net.user(51, "Ana")
	var beto := net.user(52, "Beto")
	net.befriend(51, 52)
	var ca := _chat(ana)
	var cb := DirectChat.new(beto)
	check(ca.send(52, "hola!"), "se envía")
	beto.run_callbacks()
	eq(cb.history_of(51).map(func(m): return [m.me, m.text]), [[false, "hola!"]], "le llega a Beto")
	eq(ca.history_of(52).map(func(m): return [m.me, m.text]), [[true, "hola!"]], "y queda en el historial de Ana")
	eq(cb.unread_of(51), 1, "Beto no tenía el chat abierto: 1 sin leer")
	eq(cb.total_unread(), 1, "total")
	cb.open(51)
	eq(cb.unread_of(51), 0, "al abrirlo se lee")
	cb.send(51, "buenas")
	ana.run_callbacks()
	eq(ca.unread_of(52), 1, "la respuesta llega a Ana")
	_cleanup()


func test_rejects_empty_long_and_strangers() -> void:
	var net := FakeSteam.new()
	var ana := net.user(61, "Ana")
	var extra := net.user(62, "Desconocido")
	var ca := _chat(ana)
	check(not ca.send(62, "   "), "vacío no")
	check(not ca.send(62, "x".repeat(Wire.CHAT_MAX + 1)), "demasiado largo no")
	var ce := DirectChat.new(extra)
	ce.send(61, "spam")  # not friends
	ana.run_callbacks()
	eq(ca.history_of(62), [], "un desconocido no puede escribirte")
	_cleanup()


func test_history_is_saved_and_bounded() -> void:
	var net := FakeSteam.new()
	var ana := net.user(71, "Ana")
	net.user(72, "Beto")
	net.befriend(71, 72)
	var ca := _chat(ana)
	for i in DirectChat.KEEP + 10:
		ca.send(72, str(i))
	eq(ca.history_of(72).size(), DirectChat.KEEP, "se guardan los últimos")
	var again := DirectChat.new(ana)
	eq(again.history_of(72).size(), DirectChat.KEEP, "y se recuperan al volver a abrir el juego")
	eq(again.history_of(72).back().text, str(DirectChat.KEEP + 9), "en orden")
	_cleanup()


func test_can_chat_only_when_the_friend_is_in_the_game() -> void:
	check(DirectChat.can_chat({"state": 1, "app": 480}, 480), "en el juego: sí")
	check(not DirectChat.can_chat({"state": 1, "app": 0}, 480), "en línea fuera del juego: no")
	check(not DirectChat.can_chat({"state": 0, "app": 0}, 480), "desconectado: no")


func test_mock_steam_delivers_direct_messages() -> void:
	var a := SteamBackendMock.new("Ana", 47720, 4, 8001)
	var b := SteamBackendMock.new("Beto", 47720, 4, 8002)
	for i in 100:
		for m in [a, b]:
			m.announce()
			m.run_callbacks()
		if a.friends().size() == 1 and b.friends().size() == 1:
			break
		OS.delay_msec(10)
	var got := []
	b.dm_received.connect(func(from, text): got.append([from, text]))
	a.send_dm(8002, "hola por el simulado")
	for i in 100:
		b.run_callbacks()
		if not got.is_empty():
			break
		OS.delay_msec(10)
	eq(got, [[8001, "hola por el simulado"]], "llega por UDP")
	a.shutdown()
	b.shutdown()


# ---------------------------------------------------------------- home UI

func _menu() -> MenuScreen:
	SettingsStore.path = SCRATCH
	SettingsStore.clear_shared()
	DirectChat.path = HISTORY
	DirectChat.clear_file()
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
	_cleanup()


func _key(code: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func test_clicking_a_friend_opens_the_chat_window_and_talks() -> void:
	var net := FakeSteam.new()
	var me := net.user(81, "Yo")
	var amigo := net.user(82, "Amigo")
	net.befriend(81, 82)
	var their := DirectChat.new(amigo)
	var m := _menu()
	m.set_steam_backend(me)
	m._input(_key(KEY_SPACE))
	var hub := m._views.hub as MHub
	check(not hub.dm_window.visible, "cerrada al principio")
	hub.social.rows[0].pressed.emit()
	check(hub.dm_window.visible, "tocar la tarjeta del amigo abre el chat")
	eq(hub.dm_window.friend_id, 82, "con ese amigo")
	check(hub.dm_window.entry.visible and not hub.dm_window.offline_note.visible, "está en el juego: se puede escribir")
	hub.dm_window.entry.text_submitted.emit("che, jugamos?")
	amigo.run_callbacks()
	eq(their.history_of(81).back().text, "che, jugamos?", "le llega al amigo")
	check(hub.dm_window.log_text().contains("che, jugamos?"), "y se ve en la ventana")
	their.send(81, "dale")
	me.run_callbacks()
	check(hub.dm_window.log_text().contains("dale"), "la respuesta aparece con la ventana abierta")
	eq(m.dm.unread_of(82), 0, "sin pendientes porque está abierta")
	hub.dm_window.close_button.pressed.emit()
	check(not hub.dm_window.visible, "se cierra")
	their.send(81, "?")
	me.run_callbacks()
	eq(hub.social.rows[0].badge.text, "1", "con el chat cerrado, la tarjeta muestra 1 sin leer")
	check(hub.social.rows[0].badge.visible, "visible")
	_drop(m)


func test_friend_outside_the_game_offers_steam_chat() -> void:
	var net := FakeSteam.new()
	var me := net.user(91, "Yo")
	var amigo := net.user(92, "Amigo")
	net.befriend(91, 92)
	amigo.online = false
	var m := _menu()
	m.set_steam_backend(me)
	m._input(_key(KEY_SPACE))
	var hub := m._views.hub as MHub
	hub.social.rows[0].pressed.emit()
	check(hub.dm_window.visible and hub.dm_window.offline_note.visible, "avisa que no está en el juego")
	check(not hub.dm_window.entry.visible, "no se puede escribir")
	hub.dm_window.steam_button.pressed.emit()
	eq(me.overlay_calls.back(), ["chat", 92], "ofrece abrir el chat de Steam")
	_drop(m)
