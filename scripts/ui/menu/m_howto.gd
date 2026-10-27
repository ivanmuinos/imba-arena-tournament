class_name MHowTo
extends MenuView
## "Cómo jugar": the interactive tutorial entry plus a static reference (controls, rules, champions).

var _text: RichTextLabel
var _tabs: Segmented


func _ready() -> void:
	header("Cómo jugar", "Aprendé jugando o consultá lo básico.")
	var go := MButton.new("Empezar el tutorial", "primary", "ui_play")
	go.position = Vector2(72, 188)
	go.custom_minimum_size = Vector2(380, 62)
	go.add_theme_font_size_override("font_size", 24)
	go.pressed.connect(func(): menu.launch_tutorial())
	add_child(go)
	var note := UiKit.label("Dura unos minutos, usa tu campeón y los pasos se completan haciendo cada acción.", 14, UiKit.MUTED)
	note.position = Vector2(72, 256)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(note)
	_tabs = Segmented.new().setup([["controls", "Controles"], ["rules", "Reglas"], ["classes", "Campeones"]], "controls").as_tabs()
	_tabs.position = Vector2(72, 296)
	_tabs.changed.connect(_show_tab)
	add_child(_tabs)
	var box := UiKit.glass(UiKit.LINE, 12, 16, 3.0, 0.7)
	box.position = Vector2(72, 346)
	box.custom_minimum_size = Vector2(1136, 300)
	box.size = Vector2(1136, 300)
	add_child(box)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = false
	_text.scroll_active = true
	_text.custom_minimum_size = Vector2(1100, 270)
	_text.add_theme_font_size_override("normal_font_size", 16)
	_text.add_theme_font_size_override("bold_font_size", 16)
	_text.add_theme_color_override("default_color", Color("#e6dccf"))
	box.add_child(_text)
	_show_tab("controls")


func _show_tab(tab: String) -> void:
	_text.text = {"controls": HowToContent.controls(), "rules": HowToContent.rules(), "classes": HowToContent.classes()}.get(tab, "")
	_text.scroll_to_line(0)


func menu_enter() -> void:
	_tabs.select("controls")


func first_focus() -> Control:
	return get_child(1) as Control if get_child_count() > 1 else null


func hints() -> Array:
	return [["Enter", "Aceptar"], ["Esc", "Volver"]]


func section() -> String:
	return "Aprender"
