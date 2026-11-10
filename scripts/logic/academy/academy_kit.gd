class_name AcademyKit
extends RefCounted
## What a lesson needs to know about the player's kit to speak about it: the real key of each ability, which one controls,
## which one cuts a cast. Lessons never name an ability by hand, so a kit change shows up in the tests and not in the text.

## The ability each kit uses to learn crowd control: a hard control (stun, incapacitate, fear) on a single enemy.
const CONTROL := {"mage:fire": "poly", "mage:frost": "poly", "warlock": "fear", "hunter": "trap", "warrior": "charge", "priest": "scream", "rogue": "cheapshot", "druid": "cyclone", "paladin": "hammer"}
## The quickest way each kit has to cut an enemy cast. No kit has an interrupt without talents: control does it.
const STOPPER := {"mage:fire": "dragonbreath", "mage:frost": "poly", "warlock": "fear", "hunter": "trap", "warrior": "charge", "priest": "scream", "rogue": "cheapshot", "druid": "cyclone", "paladin": "hammer"}
## Words for the kind of control, as the game labels them.
const CC_WORDS := {"poly": "lo convierte en oveja", "fear": "lo hace huir aterrorizado", "trap": "lo congela cuando la pisa", "charge": "lo aturde", "scream": "aterroriza a los enemigos cercanos", "cheapshot": "lo aturde", "cyclone": "lo encierra en un ciclón", "hammer": "lo aturde", "dragonbreath": "lo desorienta"}

var cls := "mage"
var spec := ""
var abilities: Array = []


func _init(p_cls := "mage", p_spec := "") -> void:
	GameData.ensure_loaded()
	cls = p_cls if GameData.playable(p_cls) else "mage"
	spec = GameData.normalize_spec(cls, p_spec)
	abilities = GameData.abilities(cls, spec)


func kit_key() -> String:
	return "%s:%s" % [cls, spec] if spec != "" else cls


func class_name_text() -> String:
	var info: Dictionary = GameData.classes[cls]
	return "%s (%s)" % [info.name, info.specs[spec].name] if spec != "" else str(info.name)


func ability(slot: int) -> Dictionary:
	return abilities[clampi(slot, 0, abilities.size() - 1)]


func slot_of(id: String) -> int:
	for i in abilities.size():
		if str(abilities[i].id) == id:
			return i
	return -1


## The key the player really has on that ability (their own keys and their own bar order).
func key(slot: int) -> String:
	return Keybinds.shared().slot_label(BarLayout.shared().pos_of(Talents.key(cls, spec), slot))


## "[key]2[/key] [b]Polimorfia[/b]", ready for a step's text.
func named(slot: int) -> String:
	return "[key]%s[/key] [b]%s[/b]" % [key(slot), str(ability(slot).name)]


func kind(slot: int) -> String:
	return SpellKinds.kind(ability(slot))


func ult_slot() -> int:
	return int(GameData.C.ULT_SLOT)


func has_friendly() -> bool:
	for a in abilities:
		if SpellKinds.kind(a) == "friendly":
			return true
	return false


## The first ability with a cast bar, hostile ones first (-1: the kit has none).
func cast_slot() -> int:
	var fallback := -1
	for slot in ult_slot():
		if float(ability(slot).get("cast", 0)) > 0.0:
			if kind(slot) != "friendly":
				return slot
			if fallback < 0:
				fallback = slot
	return fallback


func control_slot() -> int:
	return _table_slot(CONTROL)


func stopper_slot() -> int:
	return _table_slot(STOPPER)


## How to aim that ability, in a few words ("" when it just goes to your target).
func how(slot: int) -> String:
	match kind(slot):
		"ground":
			return " (se apunta en el piso: [key]clic izquierdo[/key] confirma)"
		"friendly":
			return " (sobre tu aliado, o sobre vos sin objetivo aliado)"
		"direction":
			return " (sale hacia donde mirás)"
		"self":
			return " (alrededor tuyo: acercate)"
		"auto":
			return " (auto-ataque: [key]clic derecho[/key] sobre el enemigo)"
	return ""


func cc_words(slot: int) -> String:
	return str(CC_WORDS.get(str(ability(slot).id), "lo controla"))


## A kit nobody listed still gets a lesson: its first ability that controls for some time.
func _table_slot(table: Dictionary) -> int:
	var slot := slot_of(str(table.get(kit_key(), "")))
	if slot >= 0:
		return slot
	for i in ult_slot():
		if float(ability(i).get("ccMs", 0)) > 0.0:
			return i
	return 1
