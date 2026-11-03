extends TestBase
## Result reporting (S18, reduced): the GDScript formula and the SQL one agree on the shared vectors, what the client
## reports, and the XP of an online match (account level never reaches matchmaking: nothing of it is ever sent).

const VECTORS_FILE := "res://supabase/tests/database/04_skill_vectors.test.sql"


## Rows (my, their, won, games, want) between the BEGIN VECTORS / END VECTORS markers of the SQL test.
func _vectors() -> Array:
	var f := FileAccess.open(VECTORS_FILE, FileAccess.READ)
	if f == null:
		return []
	var text := f.get_as_text()
	var a := text.find("-- BEGIN VECTORS")
	var b := text.find("-- END VECTORS")
	if a < 0 or b < a:
		return []
	var re := RegEx.new()
	re.compile("\\(\\s*(-?[0-9.]+),\\s*(-?[0-9.]+),\\s*(true|false),\\s*(\\d+),\\s*(-?\\d+)\\s*\\)")
	var out: Array = []
	for m in re.search_all(text.substr(a, b - a)):
		out.append([float(m.get_string(1)), float(m.get_string(2)), m.get_string(3) == "true", int(m.get_string(4)), int(m.get_string(5))])
	return out


func test_skill_formula_matches_the_sql_vectors() -> void:
	var rows := _vectors()
	check(rows.size() >= 20, "se leyeron los vectores del test SQL (%d)" % rows.size())
	for r in rows:
		eq(Ranked.delta(r[0], r[1], r[2], r[3]), r[4], "Ranked.delta(%s, %s, %s, %d)" % [str(r[0]), str(r[1]), str(r[2]), r[3]])


func test_window_matches_the_server() -> void:
	eq(Ranked.window(0.0), 200, "ventana inicial")
	eq(Ranked.window(10.0), 300, "a los 10 s")
	eq(Ranked.window(1000.0), 800, "tope")


func test_reported_winner_is_a_side() -> void:
	eq(QueueService.winner_to_report("red"), "red", "rojo")
	eq(QueueService.winner_to_report("blue"), "blue", "azul")
	eq(QueueService.winner_to_report(""), "", "sin ganador no se informa")
	eq(QueueService.winner_to_report("draw"), "", "cualquier otra cosa no se informa")


func test_online_match_gives_xp_with_source_online() -> void:
	var p := ProfileStore.new("user://test_online_profile.json")
	var win := TournamentSession.record_online(p, "mage", true, {"dmg": 900, "kills": 1, "deaths": 0, "heal": 0})
	check(int(win.xp) > 0, "ganar en linea da XP")
	var lose := TournamentSession.record_online(p, "mage", false, {})
	check(int(lose.xp) > 0 and int(lose.xp) < int(win.xp), "perder da menos XP que ganar")
	eq(p.class_stats("mage").matches, 2, "cuenta como partida de la clase")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_online_profile.json"))
