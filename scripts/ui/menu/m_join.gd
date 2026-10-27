class_name MJoin
extends MenuView
## Address + port of a friend's game, validated before moving on to champion select.

var _addr: LineEdit
var _port: LineEdit
var _err: Label
var _go: MButton


func _ready() -> void:
	header("Unirse a una partida", "Pedile al anfitrión su IP (o nombre) y el puerto.")
	var p := UiKit.glass(UiKit.LINE, 14, 28)
	p.position = Vector2(72, 220)
	p.custom_minimum_size = Vector2(620, 0)
	add_child(p)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	p.add_child(col)
	col.add_child(UiKit.caption("Dirección del anfitrión"))
	_addr = LineEdit.new()
	_addr.placeholder_text = "192.168.0.10  o  mi-servidor.com:7777"
	_addr.custom_minimum_size = Vector2(0, 50)
	_addr.add_theme_font_size_override("font_size", 20)
	col.add_child(_addr)
	col.add_child(UiKit.caption("Puerto UDP"))
	_port = LineEdit.new()
	_port.custom_minimum_size = Vector2(180, 50)
	_port.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_port.add_theme_font_size_override("font_size", 20)
	col.add_child(_port)
	_err = UiKit.label("", 15, Color("#ff9a8a"))
	_err.custom_minimum_size = Vector2(0, 22)
	col.add_child(_err)
	_go = MButton.new("CONTINUAR", "primary")
	_go.custom_minimum_size = Vector2(0, 60)
	_go.pressed.connect(_submit)
	col.add_child(_go)
	_addr.text_submitted.connect(func(_t): _submit())
	_port.text_submitted.connect(func(_t): _submit())
	var tip := UiKit.label("Por internet: el anfitrión necesita abrir el puerto UDP, o usar una VPN (ZeroTier, Tailscale) o playit.gg. Más detalles en el README.", 13, UiKit.MUTED)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(560, 0)
	col.add_child(tip)


func menu_enter() -> void:
	_addr.text = str(menu.st.get_value("addr"))
	_port.text = str(menu.st.get_value("port"))
	_err.text = ""


func _submit() -> void:
	var parts := SettingsStore.split_address(_addr.text)
	if not SettingsStore.valid_address(parts.addr):
		_fail("Esa dirección no parece válida (usá una IP o un nombre, sin espacios).")
		return
	var port: int = parts.port if parts.port > 0 else SettingsStore.parse_port(_port.text)
	if port < 0:
		_fail("El puerto tiene que ser un número entre 1 y 65535.")
		return
	menu.st.set_value("addr", parts.addr)
	menu.st.set_value("port", port)
	menu.st.save()
	_err.text = ""
	menu.next_step()


func _fail(text: String) -> void:
	_err.text = text
	UiSound.play("uiBack")


func first_focus() -> Control:
	return _addr


func hints() -> Array:
	return [["Enter", "Continuar"], ["Esc", "Volver"]]


func section() -> String:
	return "Jugar · Por IP"
