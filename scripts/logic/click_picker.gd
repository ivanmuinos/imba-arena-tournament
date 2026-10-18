class_name ClickPicker
extends RefCounted
## Picks the unit under the mouse from their projected screen positions.


## candidates: [{id, pos: Vector2 (screen), r: pick radius in px, depth: distance to camera}]. Returns the id or -1.
## Overlapping candidates: the one closest to the camera wins.
static func pick(candidates: Array, mouse: Vector2) -> int:
	var best := -1
	var best_depth := INF
	for c in candidates:
		if mouse.distance_to(c.pos) <= c.r and c.depth < best_depth:
			best_depth = c.depth
			best = c.id
	return best
