extends TestBase
## Giving up a match against bots: the Esc menu's leave button (GameMenu) says what it costs, and MatchView turns it into a forfeit.


func test_the_button_says_it_counts_as_a_loss() -> void:
	check(GameMenu.forfeit_text(true).contains("derrota"), "torneo: cuenta como derrota")
	check(GameMenu.forfeit_text(true).contains("torneo"), "menciona el torneo")
	check(not GameMenu.forfeit_text(false).contains("torneo"), "contra bots normales no habla del torneo")


func _leave_from(forfeit_enabled: bool, practice: bool) -> Array:
	var view := MatchView.new()
	view.forfeit_enabled = forfeit_enabled
	view.practice = practice
	view.game_menu = GameMenu.new()
	var got: Array = []
	view.forfeit_requested.connect(func(): got.append("forfeit"))
	view.leave_requested.connect(func(): got.append("leave"))
	view._on_menu_leave()
	view.game_menu.free()
	view.free()
	return got


func test_leaving_a_bot_match_forfeits_and_anything_else_just_leaves() -> void:
	eq(_leave_from(true, false), ["forfeit"], "contra bots: se rinde")
	eq(_leave_from(true, true), ["leave"], "práctica: vuelve al menú")
	eq(_leave_from(false, false), ["leave"], "online: abandona sin rendirse")
