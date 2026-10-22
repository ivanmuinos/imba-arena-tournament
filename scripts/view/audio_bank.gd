class_name AudioBank
extends Node
## Every ability and combat sound is a layered mix of real CC0 recordings (assets/third_party/oga_sfx: OpenGameArt packs;
## Kenney impact/UI packs for body hits and the interface). Nothing about an ability is synthesised.
## Only the round fanfares and countdown "fight" keep tiny synth recipes ("R", [wave, at_s, dur_s, f0, f1, vol]).
## Each event is a list of layers [group, pitch, dB, delay_s]: cast/charge + release/whoosh + impact, with a little random
## pitch and volume per play, a small room reverb send and a distance low-pass (three buses: near / mid / far).
## Periodic damage (DoT ticks) never plays a sound.

const RATE := 22050
const POOL := 24
## Where the listener is (camera focus); positional sounds fade with distance.
var listener := Vector2.ZERO
var muted := false
## Extra gain in dB (the player's effects-volume setting).
var gain_db := 0.0

var _cache := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _buses_ready := false

## Files that must never appear in a combat group: household/mechanical noises that read as a door lock or a page turn.
const BANNED_IN_COMBAT := ["metalLatch", "creak1", "bookFlip1", "bookOpen", "drawKnife1", "impactBell_heavy_000", "impactBell_heavy_001",
	"impactGlass_heavy_000", "impactGlass_heavy_001", "impactGlass_light_000", "impactWood_heavy_000"]

const SAMPLE_GROUPS := {
	# fire
	"fire_cast": ["fire_cast_1", "fire_cast_2"], "fire_whoosh": ["fire_whoosh"], "fire_big": ["fire_big_1", "fire_big_2"], "fire_hit": ["fire_hit_1", "fire_hit_2"],
	# frost
	"frost_cast": ["frost_cast"], "frost_crack": ["frost_crack_1", "frost_crack_2"], "frost_big": ["frost_big"],
	# arcane
	"arc_soft": ["arc_1", "arc_2", "arc_5"], "arc_bright": ["arc_3", "arc_4"], "arc_blink": ["arc_6"], "arc_seal": ["arc_7"],
	# shadow
	"shadow_cast": ["shadow_1", "shadow_2"], "shadow_swell": ["shadow_3"], "shadow_low": ["shadow_low"],
	# holy / healing
	"holy_chime": ["holy_1", "holy_2", "holy_3", "holy_4"], "holy_choir": ["holy_choir"], "heal": ["heal_1", "heal_2"],
	# physical
	"swish": ["swish_1", "swish_2", "swish_3", "swish_4"], "whoosh_long": ["whoosh_long"], "blade": ["blade_1", "blade_2", "blade_3"],
	"metal": ["metal_1", "metal_2", "metal_3"], "chain": ["chain_1"], "stone": ["stone_1", "stone_2"], "earth_big": ["earth_big"],
	"wood": ["wood_1"], "death": ["death_1"],
	# soft body impacts (Kenney Impact Sounds, assets/third_party/kenney_audio)
	"punch": ["impactPunch_heavy_000", "impactPunch_heavy_001"], "cloth": ["cloth1", "cloth2"],
	# Kenney Interface Sounds (assets/third_party/kenney_ui)
	"ui_hover": ["tick_001"], "ui_click": ["click_003"], "ui_back": ["back_002"], "ui_confirm": ["confirmation_002"],
	"ui_select": ["select_003"], "ui_tick": ["tick_002"], "ui_error": ["error_004"], "ui_count": ["tick_004"],
	"ui_whoosh": ["scroll_002"],
}
const UI_GROUPS := ["ui_hover", "ui_click", "ui_back", "ui_confirm", "ui_select", "ui_tick", "ui_error", "ui_count", "ui_whoosh"]

## event -> layers [group, pitch, extra dB, delay s]
const LAYERS := {
	"uiHover": [["ui_hover", 1.0, -10.0, 0.0]], "uiClick": [["ui_click", 1.0, -4.0, 0.0]], "uiBack": [["ui_back", 1.0, -5.0, 0.0]], "uiConfirm": [["ui_confirm", 1.0, -3.0, 0.0]],
	"uiSelect": [["ui_select", 1.0, -5.0, 0.0]], "uiTick": [["ui_tick", 1.0, -9.0, 0.0]], "error": [["ui_error", 1.0, -9.0, 0.0]], "tick": [["ui_count", 1.0, -4.0, 0.0]],
	"uiWhoosh": [["ui_whoosh", 1.0, -10.0, 0.0]],
	# generic
	"castStart": [["cloth", 1.3, -14.0, 0.0]],
	"hit": [["punch", 1.05, -4.0, 0.0], ["cloth", 1.2, -10.0, 0.02]],
	"crit": [["punch", 0.85, -3.0, 0.0], ["blade", 1.0, -9.0, 0.0], ["cloth", 1.0, -9.0, 0.03]],
	"hitSpell": [["punch", 1.4, -10.0, 0.0], ["arc_soft", 1.5, -14.0, 0.0]],
	"hitMe": [["punch", 1.2, -8.0, 0.0], ["cloth", 1.0, -9.0, 0.0]],            # melee / arrow hit on you: short organic thud
	"hitMeSpell": [["punch", 1.45, -11.0, 0.0], ["arc_soft", 1.6, -16.0, 0.0]],  # spell hit on you: softer, with a faint magical tail
	"death": [["death", 1.0, -3.0, 0.0]], "land": [["wood", 0.9, -9.0, 0.0]],
	"heal": [["heal", 1.0, -8.0, 0.0]], "power": [["arc_bright", 1.0, -8.0, 0.0]], "absorb": [["holy_chime", 1.1, -9.0, 0.0]],
	"interrupt": [["metal", 1.3, -7.0, 0.0]], "ccMe": [["shadow_low", 1.1, -8.0, 0.0]],
	# fire
	"fireball": [["fire_cast", 1.0, -3.0, 0.0], ["fire_whoosh", 0.9, -8.0, 0.05]],
	"pyro": [["fire_big", 1.0, -3.0, 0.0], ["fire_whoosh", 0.7, -6.0, 0.1]],
	"dragonbreath": [["fire_big", 0.85, -2.0, 0.0], ["fire_whoosh", 0.8, -4.0, 0.05], ["whoosh_long", 1.1, -10.0, 0.0]],
	"meteorFall": [["whoosh_long", 0.6, -4.0, 0.0], ["fire_big", 0.6, -4.0, 0.15]],
	"boom": [["fire_hit", 0.8, -3.0, 0.0], ["stone", 0.8, -6.0, 0.03]],
	"bigBoom": [["earth_big", 0.8, -2.0, 0.0], ["fire_big", 0.55, -4.0, 0.02], ["stone", 0.6, -4.0, 0.05]],
	# frost
	"frostbolt": [["frost_cast", 1.0, 0.0, 0.0], ["arc_soft", 1.5, -14.0, 0.0]],
	"icelance": [["frost_cast", 1.35, 0.0, 0.0], ["swish", 1.3, -9.0, 0.0]],
	"blizzard": [["frost_big", 0.9, -4.0, 0.0], ["whoosh_long", 1.2, -12.0, 0.0]],
	"nova": [["frost_crack", 1.0, 0.0, 0.0], ["frost_big", 1.0, -6.0, 0.05]],
	# arcane
	"blink": [["arc_blink", 1.0, -5.0, 0.0], ["swish", 1.5, -10.0, 0.0]],
	"poly": [["arc_bright", 1.2, -6.0, 0.0]], "counter": [["arc_seal", 1.0, -6.0, 0.0], ["metal", 1.6, -14.0, 0.0]],
	"silence": [["arc_seal", 0.8, -6.0, 0.0], ["shadow_low", 1.0, -10.0, 0.0]],
	# physical
	"shot": [["swish", 1.35, -2.0, 0.0]], "aimed": [["swish", 0.9, -1.0, 0.0], ["whoosh_long", 1.4, -14.0, 0.0]],
	"conc": [["swish", 1.15, -4.0, 0.0], ["arc_soft", 1.3, -16.0, 0.0]], "volley": [["swish", 0.8, -2.0, 0.0], ["swish", 1.0, -4.0, 0.07], ["swish", 1.2, -5.0, 0.13]],
	"disengage": [["whoosh_long", 1.3, -6.0, 0.0], ["cloth", 1.3, -8.0, 0.0]], "trapSet": [["chain", 1.2, -8.0, 0.0], ["cloth", 1.0, -10.0, 0.0]],
	"trapHit": [["metal", 1.4, -8.0, 0.0], ["swish", 1.0, -8.0, 0.02]],
	"swing": [["swish", 1.0, -3.0, 0.0]], "heavySwing": [["swish", 0.7, -1.0, 0.0], ["blade", 0.9, -8.0, 0.05]],
	"charge": [["whoosh_long", 0.9, -5.0, 0.0], ["swish", 0.8, -6.0, 0.05]], "wall": [["metal", 0.7, -5.0, 0.0], ["stone", 0.9, -10.0, 0.0]],
	"storm": [["swish", 0.6, -2.0, 0.0], ["swish", 0.7, -3.0, 0.12], ["whoosh_long", 1.0, -8.0, 0.0]],
	# holy
	"smite": [["holy_chime", 1.3, -6.0, 0.0], ["arc_bright", 1.2, -12.0, 0.03]], "shieldUp": [["holy_chime", 0.9, -6.0, 0.0]],
	"renew": [["heal", 1.1, -12.0, 0.0]], "dispel": [["arc_soft", 1.3, -6.0, 0.0], ["holy_chime", 1.4, -12.0, 0.0]],
	"hymn": [["holy_choir", 1.0, -5.0, 0.0], ["holy_chime", 0.8, -12.0, 0.2]],
	# wizard
	"spark": [["arc_soft", 1.6, -6.0, 0.0]], "stunbolt": [["arc_bright", 1.0, -3.0, 0.0], ["fire_hit", 1.4, -8.0, 0.0]],
	"disarm": [["arc_bright", 1.3, -4.0, 0.0], ["swish", 1.5, -8.0, 0.0]], "wardshield": [["arc_seal", 1.0, -5.0, 0.0]],
	"broom": [["whoosh_long", 1.2, -3.0, 0.0], ["cloth", 1.2, -8.0, 0.0]], "confuse": [["arc_soft", 0.8, -4.0, 0.0], ["arc_blink", 1.1, -8.0, 0.1]],
	"guardian": [["holy_choir", 1.1, -3.0, 0.0], ["arc_bright", 0.8, -6.0, 0.1]],
	# crack
	"kick": [["swish", 1.5, -4.0, 0.0], ["stone", 1.7, -10.0, 0.0]], "chip": [["swish", 1.2, -2.0, 0.0], ["stone", 1.4, -6.0, 0.0]],
	"dribble": [["whoosh_long", 1.5, -5.0, 0.0], ["cloth", 1.4, -8.0, 0.0]], "onetwo": [["swish", 1.6, -5.0, 0.0], ["swish", 1.6, -5.0, 0.15]],
	"golazo": [["earth_big", 1.0, -2.0, 0.0], ["holy_choir", 1.25, -6.0, 0.25]],
	# ronin
	"slash": [["blade", 1.2, -4.0, 0.0], ["swish", 1.3, -6.0, 0.0]], "tempest": [["swish", 1.5, -2.0, 0.0], ["blade", 1.4, -6.0, 0.03]],
	"windwall": [["whoosh_long", 0.7, -2.0, 0.0], ["whoosh_long", 1.0, -6.0, 0.2]], "sweep": [["whoosh_long", 1.4, -4.0, 0.0], ["blade", 1.2, -6.0, 0.1]],
	"flow": [["whoosh_long", 1.2, -8.0, 0.0], ["holy_chime", 1.6, -14.0, 0.0]], "lastbreath": [["whoosh_long", 0.8, -2.0, 0.0], ["blade", 0.8, -2.0, 0.15], ["earth_big", 1.3, -8.0, 0.2]],
	# counter-terrorist
	"rifle": [["metal", 1.7, -4.0, 0.0], ["fire_hit", 1.5, -8.0, 0.0]], "headshot": [["metal", 1.4, -2.0, 0.0], ["fire_hit", 1.2, -5.0, 0.0]],
	"flashbang": [["earth_big", 1.6, -3.0, 0.0], ["arc_bright", 1.5, -6.0, 0.0]], "kevlar": [["cloth", 0.8, -6.0, 0.0], ["metal", 0.6, -10.0, 0.05]],
	"knife": [["blade", 1.3, -5.0, 0.0]], "awp": [["earth_big", 1.2, -1.0, 0.0], ["metal", 0.9, -4.0, 0.0]],
	# nature (druid)
	"wrath": [["arc_soft", 1.1, -6.0, 0.0], ["swish", 1.2, -12.0, 0.0]], "regrowth": [["heal", 0.9, -8.0, 0.0]],
	"ironbark": [["stone", 0.8, -6.0, 0.0], ["earth_big", 1.2, -14.0, 0.05]], "cyclone": [["whoosh_long", 0.8, -4.0, 0.0], ["whoosh_long", 1.1, -8.0, 0.15]],
	"tranquility": [["holy_choir", 0.85, -6.0, 0.0], ["heal", 0.7, -10.0, 0.2]],
	# shadow
	"blind": [["shadow_cast", 1.0, -5.0, 0.0], ["swish", 0.8, -10.0, 0.0]], "vanish": [["shadow_cast", 0.8, -6.0, 0.0], ["whoosh_long", 1.2, -8.0, 0.0]],
	"deathmark": [["shadow_swell", 0.8, -6.0, 0.0], ["metal", 0.7, -14.0, 0.1]], "scream": [["shadow_swell", 0.9, -3.0, 0.0], ["shadow_low", 0.8, -6.0, 0.05]],
	"shadowbolt": [["shadow_cast", 1.15, -4.0, 0.0], ["swish", 0.8, -12.0, 0.0]], "corruption": [["shadow_cast", 0.85, -5.0, 0.0]],
	"agony": [["shadow_cast", 0.7, -5.0, 0.0], ["shadow_low", 1.2, -12.0, 0.0]], "darkpact": [["shadow_low", 0.9, -4.0, 0.0], ["holy_chime", 0.5, -16.0, 0.1]],
	"drainlife": [["shadow_swell", 1.1, -6.0, 0.0], ["heal", 0.8, -12.0, 0.25]], "soulrot": [["shadow_swell", 0.7, -3.0, 0.0], ["earth_big", 0.9, -9.0, 0.05]],
}

## Non-ability synth recipes (countdown fight cue, round result jingles, footstep).
const R := {
	"fight": [["saw", 0.0, 0.3, 200, 400, 0.22], ["sine", 0.08, 0.4, 600, 900, 0.3]],
	"win": [["sine", 0.0, 0.15, 520, 520, 0.3], ["sine", 0.15, 0.15, 660, 660, 0.3], ["sine", 0.3, 0.15, 780, 780, 0.3], ["sine", 0.45, 0.5, 1040, 1040, 0.3]],
	"step": [["noise", 0.0, 0.07, 0.22, 0, 0.22], ["sine", 0.0, 0.06, 120, 70, 0.22]],
	"lose": [["sine", 0.0, 0.25, 400, 400, 0.3], ["sine", 0.25, 0.25, 330, 330, 0.3], ["sine", 0.5, 0.6, 260, 200, 0.3]],
}


func _ready() -> void:
	for group in SAMPLE_GROUPS.values():
		for file in group:
			_sample(file)
	_make_buses()
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


## Three SFX buses with a shared-style room reverb send; the far ones also low-pass (distant sounds lose their highs).
func _make_buses() -> void:
	if _buses_ready:
		return
	for spec in [["SFX_near", 20500.0], ["SFX_mid", 5500.0], ["SFX_far", 2200.0]]:
		if AudioServer.get_bus_index(spec[0]) >= 0:
			continue
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, spec[0])
		AudioServer.set_bus_send(i, "Master")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = spec[1]
		AudioServer.add_bus_effect(i, lp)
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.35
		rv.damping = 0.6
		rv.wet = 0.1
		rv.dry = 0.95
		AudioServer.add_bus_effect(i, rv)
	_buses_ready = true


func _exit_tree() -> void:
	for p in _players:
		p.stop()
		p.stream = null
	_cache.clear()


## pos: world (x, z) of the source; Vector2.INF = not positional.
func play(sound: String, pos := Vector2.INF, max_dist := 70.0) -> void:
	if muted or _players.is_empty() or not (LAYERS.has(sound) or R.has(sound)):
		return
	var vol := 0.0
	var bus := "SFX_near"
	if pos != Vector2.INF:
		var d := pos.distance_to(listener)
		if d > max_dist:
			return
		vol = -clampf(d / 3.0, 0.0, 24.0)
		bus = "SFX_near" if d < 18.0 else ("SFX_mid" if d < 40.0 else "SFX_far")
	if not LAYERS.has(sound):
		_fire(_stream(sound), 1.0, vol - 6.0 + gain_db, "SFX_near")
		return
	var is_ui := sound.begins_with("ui") or sound == "error" or sound == "tick"
	for layer in LAYERS[sound]:
		var group: Array = SAMPLE_GROUPS[layer[0]]
		var stream := _sample(group.pick_random())
		var pitch: float = float(layer[1]) * (1.0 if is_ui else randf_range(0.95, 1.05))
		var db: float = vol - 6.0 + gain_db + float(layer[2]) + (0.0 if is_ui else randf_range(-1.5, 1.0))
		var delay: float = layer[3]
		if delay <= 0.0 or not is_inside_tree():
			_fire(stream, pitch, db, "SFX_near" if is_ui else bus)
		else:
			get_tree().create_timer(delay).timeout.connect(_fire.bind(stream, pitch, db, bus))


func _fire(stream: AudioStream, pitch: float, db: float, bus: String) -> void:
	if _players.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = db
	p.bus = bus if AudioServer.get_bus_index(bus) >= 0 else "Master"
	p.play()


func toggle_mute() -> bool:
	muted = not muted
	return muted


func _sample(file: String) -> AudioStream:
	if not _cache.has(file):
		for path in ["res://assets/third_party/oga_sfx/%s.wav" % file, "res://assets/third_party/kenney_audio/%s.ogg" % file, "res://assets/third_party/kenney_ui/%s.ogg" % file]:
			if ResourceLoader.exists(path):
				_cache[file] = load(path)
				break
	return _cache.get(file)


func _stream(sound: String) -> AudioStream:
	if _cache.has(sound):
		return _cache[sound]
	var layers: Array = R[sound]
	var total := 0.0
	for l in layers:
		total = maxf(total, l[1] + l[2])
	var n := int(total * RATE) + 1
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sound)
	for l in layers:
		var start := int(l[1] * RATE)
		var count := int(l[2] * RATE)
		var phase := 0.0
		var lp := 0.0
		for i in count:
			var k := float(i) / count
			var env := (1.0 - k) * minf(1.0, i / 90.0)  # linear decay with a tiny attack
			var s := 0.0
			match l[0]:
				"noise":
					lp += (rng.randf_range(-1.0, 1.0) - lp) * clampf(l[3], 0.02, 1.0)
					s = lp
				_:
					var f: float = lerpf(l[3], l[4], k)
					phase = fmod(phase + f / RATE, 1.0)
					match l[0]:
						"sine": s = sin(phase * TAU)
						"square": s = 1.0 if phase < 0.5 else -1.0
						"saw": s = phase * 2.0 - 1.0
			buf[start + i] += s * env * l[5]
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	_cache[sound] = w
	return w
