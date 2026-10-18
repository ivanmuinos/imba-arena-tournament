class_name OffscreenIndicator
extends RefCounted
## Where to draw an arrow at the screen edge for something that is off-screen (your target).


## screen_pos = unprojected position; behind = the point is behind the camera.
## Returns {visible, pos (on the edge, inset by margin), angle (radians, 0 = right, PI/2 = down)}.
static func edge_point(screen_pos: Vector2, behind: bool, viewport: Vector2, margin: float) -> Dictionary:
	var centre := viewport / 2.0
	var p := screen_pos
	if behind:
		p = centre + (centre - screen_pos)  # mirror: the target is behind us, so point "down"
		p.y = maxf(p.y, viewport.y + 10.0)
	var inside := p.x >= margin and p.x <= viewport.x - margin and p.y >= margin and p.y <= viewport.y - margin
	if inside and not behind:
		return {"visible": false, "pos": p, "angle": 0.0}
	var dir := p - centre
	if dir.length() < 1e-3:
		dir = Vector2(0, 1)
	var half := centre - Vector2(margin, margin)
	var k := minf(half.x / maxf(absf(dir.x), 1e-3), half.y / maxf(absf(dir.y), 1e-3))
	return {"visible": true, "pos": centre + dir * k, "angle": dir.angle()}
