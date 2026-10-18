class_name UiSound
extends RefCounted
## Menu micro-interaction sounds (synthesised by AudioBank, no files) and the volume settings.

static var _bank: AudioBank = null


static func play(sound: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return
	if _bank == null or not is_instance_valid(_bank):
		_bank = AudioBank.new()
		loop.root.add_child(_bank)
	_bank.gain_db = linear_to_db(maxf(0.001, SettingsStore.shared().get_value("sfx")))
	_bank.play(sound)


## Applies master volume to the Master bus (effects volume is read by AudioBank users).
static func apply_volumes() -> void:
	var st := SettingsStore.shared()
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, st.get_value("master"))))


static func release() -> void:
	if _bank != null and is_instance_valid(_bank):
		_bank.queue_free()
	_bank = null
