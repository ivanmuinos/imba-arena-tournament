class_name Minimap
extends Control
## The round minimap of the valley, top right: the map from above with north up, you in the middle as an arrow that turns
## with you, the places of the valley, who is around, and the name of where you are. The wheel over it zooms.

const SIZE := 184.0
const RANGES := [26.0, 40.0, 62.0]  # metres from the centre to the rim, per zoom level
const NAME_H := 26.0

var map: GameMap
var me := Vector2.ZERO
var facing := PI
var place := ""
## [{pos: Vector2, color: Color, size: float}]: who is around (set every frame by the owner).
var dots: Array = []
## Where the current quest sends you (Vector2.INF: nowhere).
var goal := Vector2.INF
var zoom := 1

var _view: ColorRect
var _over: Control
var _name: Label
var _mat: ShaderMaterial
var _t := 0.0


func _init(p_map: GameMap) -> void:
	map = p_map
	custom_minimum_size = Vector2(SIZE, SIZE + NAME_H + 4.0)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UiKit.box(Color(0.05, 0.03, 0.025, 0.88), UiKit.LINE_STRONG, 13, 1, 3))
	pill.position = Vector2(0, 0)
	pill.custom_minimum_size = Vector2(SIZE, NAME_H)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pill)
	_name = UiKit.heading("", 14, UiKit.GOLD, 700, 1, HORIZONTAL_ALIGNMENT_CENTER)
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(_name)
	_view = ColorRect.new()
	_view.position = Vector2(0, NAME_H + 4.0)
	_view.size = Vector2(SIZE, SIZE)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/minimap.gdshader")
	_mat.set_shader_parameter("map_tex", ImageTexture.create_from_image(MinimapImage.paint(map)))
	_view.material = _mat
	add_child(_view)
	_over = Control.new()
	_over.position = _view.position
	_over.size = _view.size
	_over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_over.draw.connect(_draw_over)
	add_child(_over)


func reach() -> float:
	return float(RANGES[clampi(zoom, 0, RANGES.size() - 1)])


## Where a world point lands on the round window (pixels from its top left), and whether it is inside it.
func spot(world: Vector2) -> Dictionary:
	var rel := (world - me) / reach() * (SIZE / 2.0)
	var inside := rel.length() <= SIZE / 2.0 - 7.0
	if not inside:
		rel = rel.normalized() * (SIZE / 2.0 - 7.0)
	return {"at": Vector2(SIZE, SIZE) / 2.0 + rel, "inside": inside}


func _process(delta: float) -> void:
	_t += delta
	_mat.set_shader_parameter("center", MinimapImage.uv_of(map, me.x, me.y))
	_mat.set_shader_parameter("span", reach() / (2.0 * map.half_x))
	_name.text = place if place != "" else map.name
	_over.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = maxi(0, zoom - 1)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = mini(RANGES.size() - 1, zoom + 1)
			accept_event()


func _draw_over() -> void:
	var c := Vector2(SIZE, SIZE) / 2.0
	var r := SIZE / 2.0
	for zn in map.zones:
		var s := spot(Vector2(float(zn.x), float(zn.z)))
		if s.inside:
			_over.draw_circle(s.at, 4.5, Color(0, 0, 0, 0.7))
			_over.draw_circle(s.at, 3.2, UiKit.GOLD)
		else:
			_edge_mark(s.at, c, Color(UiKit.GOLD, 0.75), 5.0)
	for d in dots:
		var s := spot(d.pos)
		if s.inside:
			_over.draw_circle(s.at, float(d.size) + 1.2, Color(0, 0, 0, 0.75))
			_over.draw_circle(s.at, float(d.size), d.color)
	if goal != Vector2.INF:
		var s := spot(goal)
		var pulse := 1.0 + 0.25 * sin(_t * 5.0)
		if s.inside:
			_over.draw_arc(s.at, 7.0 * pulse, 0.0, TAU, 24, Color("#fff27a"), 2.0, true)
			_over.draw_circle(s.at, 3.0, Color("#fff27a"))
		else:
			_edge_mark(s.at, c, Color("#fff27a"), 8.0 * pulse)
	# you: an arrow that turns with you
	var dir := Vector2(sin(facing), cos(facing))
	var side := Vector2(-dir.y, dir.x)
	var arrow := PackedVector2Array([c + dir * 9.0, c - dir * 6.0 + side * 6.0, c - dir * 2.5, c - dir * 6.0 - side * 6.0])
	_over.draw_colored_polygon(arrow, Color("#fff6e0"))
	_over.draw_polyline(PackedVector2Array([arrow[0], arrow[1], arrow[2], arrow[3], arrow[0]]), Color(0, 0, 0, 0.85), 1.5, true)
	# frame
	_over.draw_arc(c, r - 1.0, 0.0, TAU, 72, Color(0.04, 0.025, 0.02), 5.0, true)
	_over.draw_arc(c, r - 3.5, 0.0, TAU, 72, UiKit.LINE_STRONG, 1.5, true)
	_over.draw_arc(c, r + 1.0, 0.0, TAU, 72, Color(0.75, 0.52, 0.25), 1.5, true)
	var north := c + Vector2(0, -r + 1.0)
	_over.draw_circle(north, 8.0, Color(0.04, 0.025, 0.02))
	_over.draw_arc(north, 8.0, 0.0, TAU, 20, UiKit.LINE_STRONG, 1.2, true)
	var font := UiKit.display(700)
	_over.draw_string(font, north + Vector2(-4.5, 4.5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.GOLD)


## A small arrowhead on the rim, pointing out toward something beyond the window.
func _edge_mark(at: Vector2, centre: Vector2, col: Color, length: float) -> void:
	var out := (at - centre).normalized()
	var side := Vector2(-out.y, out.x)
	_over.draw_colored_polygon(PackedVector2Array([at + out * length, at - out * 2.0 + side * length * 0.7, at - out * 2.0 - side * length * 0.7]), col)
