class_name MenuNav
extends RefCounted
## Navigation state machine of the front end: a history stack of screens plus the "play flow"
## (which setup steps a game mode needs). Pure logic; MenuRoot turns it into animated screens.

const SCREENS := ["splash", "hub", "play", "setup", "join", "champions", "settings", "howto"]
const FLOWS := {
	"practice": ["setup", "champions"],
	"arena": ["champions"],
	"host": ["setup", "champions"],
	"join": ["join", "champions"],
	"steam_host": ["setup", "champions"],
	"steam_browse": ["champions"],
}

var current := "splash"
var mode := ""
var _history: Array = []
var _flow: Array = []
var _step := -1


static func flow_for(play_mode: String) -> Array:
	return FLOWS.get(play_mode, FLOWS.practice)


func can_back() -> bool:
	return not _history.is_empty()


func go(screen: String) -> void:
	if not SCREENS.has(screen) or screen == current:
		return
	_history.append(current)
	current = screen


func replace(screen: String) -> void:
	if SCREENS.has(screen):
		current = screen


## Any key on the title screen: straight to the hub, without keeping the title in the history.
func advance_from_splash() -> void:
	if current == "splash":
		current = "hub"


## Esc / back button. Returns the screen we land on, or "" when there is nowhere to go.
func back() -> String:
	if _history.is_empty():
		return ""
	current = _history.pop_back()
	if _step > 0 and _flow.has(current):
		_step = _flow.find(current)
	return current


func reset_to(screen: String) -> void:
	_history.clear()
	_flow = []
	_step = -1
	mode = ""
	current = screen if SCREENS.has(screen) else "hub"


func start_flow(play_mode: String) -> void:
	mode = play_mode
	_flow = flow_for(play_mode)
	_step = 0
	go(_flow[0])


func flow_done() -> bool:
	return _step >= _flow.size()


func next() -> void:
	if _step < 0:
		return
	_step += 1
	if _step < _flow.size():
		go(_flow[_step])
