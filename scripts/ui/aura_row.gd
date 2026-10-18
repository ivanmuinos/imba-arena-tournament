class_name AuraRow
extends HBoxContainer
## WoW-style aura icons: coloured border and a countdown. Reuses nodes between updates.

var icon_size := 28
var _items := {}


func setup(px: int) -> AuraRow:
	icon_size = px
	add_theme_constant_override("separation", 2)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self


## list: Effects.debuffs_of()/buffs_of() entries.
func set_effects(list: Array) -> void:
	var seen := {}
	for e in list:
		seen[e.key] = true
		var it: Dictionary = _items.get(e.key, {})
		if it.is_empty():
			var p := Panel.new()
			p.custom_minimum_size = Vector2(icon_size, icon_size)
			p.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var icon := Icons.rect(e.icon, icon_size)
			icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 1)
			var t := UiKit.label("", maxi(9, int(icon_size * 0.36)), Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
			UiKit.outlined(t, 4)
			t.set_anchors_preset(Control.PRESET_FULL_RECT)
			t.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			t.mouse_filter = Control.MOUSE_FILTER_IGNORE
			p.add_child(icon)
			p.add_child(t)
			p.tooltip_text = e.name
			add_child(p)
			it = {"panel": p, "time": t}
			_items[e.key] = it
		if it.get("color") != e.color:
			it["color"] = e.color
			(it.panel as Panel).add_theme_stylebox_override("panel", UiKit.box(Color(0, 0, 0, 0.6), e.color, 4, 2, 0))
		(it.time as Label).text = str(e.text) if e.has("text") else Effects.secs(e.ms)
	for k in _items.keys():
		if not seen.has(k):
			_items[k].panel.queue_free()
			_items.erase(k)
