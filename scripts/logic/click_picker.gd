class_name ClickPicker
extends RefCounted
## Picks the unit under the mouse from their projected screen positions.

## Clickable half-width of a body as a fraction of its on-screen height (a chibi is roughly that wide).
const BODY_WIDTH := 0.3


## A whole-body candidate: a screen-space capsule from the feet to the head, at least `min_r` px wide.
static func body(id: int, feet: Vector2, head: Vector2, depth: float, min_r := 18.0) -> Dictionary:
	return {"id": id, "a": feet, "b": head, "r": maxf(min_r, feet.distance_to(head) * BODY_WIDTH), "depth": depth}


## candidates: [{id, pos: Vector2 (screen), r: pick radius in px, depth: distance to camera}] or bodies from body().
## Returns the id or -1. Overlapping candidates: the one closest to the camera wins.
static func pick(candidates: Array, mouse: Vector2) -> int:
	var best := -1
	var best_depth := INF
	for c in candidates:
		var d: float = mouse.distance_to(c.pos) if c.has("pos") else mouse.distance_to(Geometry2D.get_closest_point_to_segment(mouse, c.a, c.b))
		if d <= c.r and c.depth < best_depth:
			best_depth = c.depth
			best = c.id
	return best
