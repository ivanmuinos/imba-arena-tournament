extends TestBase
## Tizón, the coach of the Academia: his model and portraits are where the game expects them.

const MOODS := ["neutral", "contenta", "burlona", "seria", "orgullosa"]
const ANIMATIONS := ["idle", "walk", "celebrate", "point"]


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var found := _find_player(c)
		if found != null:
			return found
	return null


func test_the_model_has_every_animation_he_needs() -> void:
	var scene := load("res://assets/models/tizon.glb") as PackedScene
	check(scene != null, "el modelo existe")
	if scene == null:
		return
	var node := scene.instantiate()
	var player := _find_player(node)
	check(player != null, "tiene animaciones")
	if player != null:
		for a in ANIMATIONS:
			check(player.has_animation(a), "anima %s" % a)
	node.free()


func test_every_mood_has_a_portrait_the_size_of_the_others() -> void:
	var champion := load("res://assets/ui/portraits/mage.png") as Texture2D
	for mood in MOODS:
		var tex := load("res://assets/ui/portraits/tizon_%s.png" % mood) as Texture2D
		check(tex != null, "retrato %s" % mood)
		if tex != null:
			eq(tex.get_size(), champion.get_size(), "%s mide igual que los campeones" % mood)
