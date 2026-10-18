class_name MHub
extends MenuView
## Main hub: JUGAR, then Campeones / Configuración / Salir, and the current champion chip.

var _greet: Label
var _play: MButton
var _chip_art: TextureRect
var _chip_name: Label
var _chip_role: Label


func _ready() -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(72, 170)
	col.custom_minimum_size = Vector2(430, 0)
	col.add_theme_constant_override("separation", 12)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	col.add_child(UiKit.caption("Menú principal", UiKit.LAVA, 14))
	_greet = UiKit.heading("", 52, UiKit.INK, 700, 2)
	_greet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_greet)
	var sub := UiKit.label("Elegí tu campeón y entrá a la arena.", 17, UiKit.MUTED)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sub)
	col.add_child(UiKit.spacer(26))
	_play = MButton.new("JUGAR", "primary", "ui_play")
	_play.custom_minimum_size = Vector2(430, 74)
	_play.add_theme_font_size_override("font_size", 32)
	_play.pressed.connect(func(): menu.go("play"))
	col.add_child(_play)
	col.add_child(UiKit.spacer(2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var champs := MButton.new("Campeones", "secondary", "ui_helm")
	var cfg := MButton.new("Configuración", "secondary", "ui_gear")
	var quit := MButton.new("Salir", "secondary", "ui_door")
	for b in [champs, cfg, quit]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 48)
		b.add_theme_font_size_override("font_size", 16)
		row.add_child(b)
	champs.pressed.connect(func(): menu.go("champions"))
	cfg.pressed.connect(func(): menu.go("settings"))
	quit.pressed.connect(func(): get_tree().quit())
	# current champion chip
	var chip := Card.new("", "", "", UiKit.GOLD)
	chip.custom_minimum_size = Vector2(330, 120)
	chip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	chip.position = Vector2(-72 - 330, -64 - 120)
	chip.size = Vector2(330, 120)
	chip.pressed.connect(func(): menu.go("champions"))
	add_child(chip)
	chip.get_child(1).queue_free()  # the card's default text column: replaced by a custom row
	var r := HBoxContainer.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	r.add_theme_constant_override("separation", 14)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(r)
	_chip_art = TextureRect.new()
	_chip_art.custom_minimum_size = Vector2(112, 96)
	_chip_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_chip_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_chip_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(_chip_art)
	var tc := VBoxContainer.new()
	tc.alignment = BoxContainer.ALIGNMENT_CENTER
	tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(tc)
	tc.add_child(UiKit.caption("Tu campeón", UiKit.MUTED, 11))
	_chip_name = UiKit.heading("", 30, UiKit.GOLD, 700, 1)
	_chip_role = UiKit.label("", 13, UiKit.MUTED)
	_chip_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip_role.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.add_child(_chip_name)
	tc.add_child(_chip_role)
	var change := UiKit.caption("Cambiar  >", UiKit.LAVA, 12)
	change.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.add_child(change)


func menu_enter() -> void:
	var n := str(menu.st.get_value("name"))
	_greet.text = ("Hola, %s" % n) if n != "" else "Bienvenido"
	var cls := str(menu.st.get_value("cls"))
	var spec: Dictionary = GameData.classes[cls]
	_chip_art.texture = Portraits.bust(cls)
	_chip_name.text = str(spec.name)
	_chip_role.text = ", ".join(spec.tags)


func first_focus() -> Control:
	return _play


func hints() -> Array:
	return [["Flechas", "Navegar"], ["Enter", "Aceptar"]]
