class_name ValleyHud
extends Node
## What the valley adds to the match's screen: the minimap, and the name of each place written across the screen when you
## walk into it.

var mv: MatchView
var minimap: Minimap
var zone_id := ""
var _banner: Label
var _sub: Label
var _tw: Tween


func attach(p_mv: MatchView) -> void:
	mv = p_mv
	mv.add_child(self)
	minimap = Minimap.new(mv.world.map)
	mv.hud.add_overlay(minimap, 40.0, 12.0, true)
	mv.hud.hide_enemy_frames()
	mv.hud.plate_range = 34.0
	_banner = UiKit.outlined(UiKit.heading("", 40, UiKit.GOLD, 700, 3, HORIZONTAL_ALIGNMENT_CENTER), 8)
	_sub = UiKit.outlined(UiKit.label("", 16, UiKit.INK, HORIZONTAL_ALIGNMENT_CENTER), 5)
	for l in [_banner, _sub]:
		l.set_anchors_preset(Control.PRESET_TOP_WIDE)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.modulate.a = 0.0
		mv.hud.add_plain(l)
	_banner.offset_top = 96.0
	_sub.offset_top = 146.0


func _process(_delta: float) -> void:
	if mv == null or mv.me.is_empty():
		return
	var pos := Vector2(mv.predictor.m.x, mv.predictor.m.z)
	minimap.me = pos
	minimap.facing = mv._face
	var zn := mv.world.map.zone_at(pos.x, pos.y)
	minimap.place = str(zn.get("name", ""))
	var dots: Array = []
	for id in mv.views:
		var v: UnitView = mv.views[id]
		if id == mv.my_id or not v.shown or not v.is_alive():
			continue
		var crate := str(v.entry.get("dummy", "")) == "crate"
		dots.append({"pos": Vector2(v.position.x, v.position.z), "color": Color("#c9a26a") if crate else UiKit.GREEN if v.entry.team == mv.my_team else UiKit.RED, "size": 2.2 if crate else 3.2})
	if mv.world.tizon != null:
		dots.append({"pos": Vector2(mv.world.tizon.position.x, mv.world.tizon.position.z), "color": UiKit.LAVA, "size": 4.0})
	minimap.dots = dots
	var id_now := str(zn.get("id", ""))
	if id_now != zone_id:
		zone_id = id_now
		if id_now != "":
			_announce(str(zn.name))


## The place's name, large, for a moment: you arrived somewhere.
func _announce(text: String) -> void:
	_banner.text = text
	_sub.text = mv.world.map.name
	if _tw != null and _tw.is_valid():
		_tw.kill()
	_tw = create_tween()
	_tw.tween_property(_banner, "modulate:a", 1.0, 0.5)
	_tw.parallel().tween_property(_sub, "modulate:a", 0.85, 0.5)
	_tw.tween_interval(2.2)
	_tw.tween_property(_banner, "modulate:a", 0.0, 1.0)
	_tw.parallel().tween_property(_sub, "modulate:a", 0.0, 1.0)
