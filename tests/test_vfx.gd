extends TestBase


func test_attacks_and_hits_preserve_running_legs() -> void:
	var rig := CharacterRig.new()
	rig.setup("warrior", Color.RED)
	var bt := rig._tree.tree_root as AnimationNodeBlendTree
	for key in ["attack", "hit"]:
		var node := bt.get_node(key)
		check(node.filter_enabled, "ataque/golpe filtra torso: " + key)
		var anim := rig.player.get_animation("Running_A")
		var upper := 0
		for i in anim.get_track_count():
			var path := anim.track_get_path(i)
			if str(path).contains(":chest"):
				check(node.is_path_filtered(path), "pecho recibe gesto")
				upper += 1
			if str(path).contains(":upperleg") or str(path).contains(":lowerleg"):
				check(not node.is_path_filtered(path), "piernas siguen locomoción")
		check(upper > 0, "test encuentra tracks reales del pecho")
	rig.root.free()


func test_combat_audio_is_layered_real_samples_with_no_synth_for_abilities() -> void:
	var bank := AudioBank.new()
	var sounds: Array = MatchView.CAST_SOUND.values() + ["heal", "nova", "blink", "boom", "hit", "hitMe", "hitMeSpell", "hitSpell", "scream", "hymn", "dragonbreath", "death"]
	for sound in sounds:
		check(AudioBank.LAYERS.has(sound), "evento con capas de audio real: " + sound)
		check(not AudioBank.R.has(sound), "sin sintetizador: " + sound)
		for layer in AudioBank.LAYERS.get(sound, []):
			for f in AudioBank.SAMPLE_GROUPS[layer[0]]:
				check(bank._sample(f) is AudioStreamWAV or bank._sample(f) is AudioStreamOggVorbis, "%s/%s se importa" % [sound, f])
	bank.free()


func test_combat_sound_groups_never_use_door_lock_or_household_noises() -> void:
	var combat_events := AudioBank.LAYERS.keys().filter(func(k): return not (k.begins_with("ui") or k in ["error", "tick"]))
	for ev in combat_events:
		for layer in AudioBank.LAYERS[ev]:
			for f in AudioBank.SAMPLE_GROUPS[layer[0]]:
				check(not AudioBank.BANNED_IN_COMBAT.has(f), "%s usa %s (prohibido en combate)" % [ev, f])
	for k in ["hit", "hitMe", "hitMeSpell", "hitSpell", "crit"]:
		for layer in AudioBank.LAYERS[k]:
			check(layer[0] in ["punch", "cloth", "arc_soft", "blade"], "%s: sólo impactos corporales (%s)" % [k, layer[0]])
	check(not AudioBank.LAYERS.has("tickDot"), "los ticks de daño periódico no tienen sonido")


## Spell schools: every ability belongs to a school with a palette and burst profile that scales with quality.


func test_every_ability_has_a_known_school() -> void:
	GameData.ensure_loaded()
	for cid in GameData.classes:
		for a in GameData.classes[cid].abilities:
			var s := SpellSchools.school_of(str(a.id))
			check(SpellSchools.SCHOOLS.has(s), "%s/%s: escuela %s existe" % [cid, a.id, s])
			check(SpellSchools.explicit(str(a.id)), "%s/%s: asignada explícitamente" % [cid, a.id])


func test_expected_school_assignments() -> void:
	eq(SpellSchools.school_of("fireball"), "fire", "bola de fuego")
	eq(SpellSchools.school_of("nova"), "frost", "nova de escarcha")
	eq(SpellSchools.school_of("blink"), "arcane", "parpadeo")
	eq(SpellSchools.school_of("smite"), "holy", "castigo")
	eq(SpellSchools.school_of("vanish"), "shadow", "desvanecer")
	eq(SpellSchools.school_of("renew"), "nature", "renovar")
	eq(SpellSchools.school_of("strike"), "physical", "golpe")
	eq(SpellSchools.school_of("???"), "physical", "desconocido = físico")


func test_palettes_are_distinct_and_complete() -> void:
	var seen := {}
	for s in SpellSchools.SCHOOLS:
		var p := SpellSchools.palette(s)
		for k in ["core", "mid", "edge"]:
			check(p.has(k) and p[k] is Color, "%s: color %s" % [s, k])
		check(not seen.has(p.mid.to_html()), "%s: color propio" % s)
		seen[p.mid.to_html()] = true


func test_burst_profile_scales_with_quality_but_never_vanishes() -> void:
	var hi := SpellSchools.burst("fire", 1.0)
	var lo := SpellSchools.burst("fire", 0.3)
	check(lo.n < hi.n, "menos partículas en calidad baja")
	check(lo.n >= 3, "pero siempre algo")
	eq(lo.life, hi.life, "la duración no cambia")
	for s in SpellSchools.SCHOOLS:
		var b := SpellSchools.burst(s, 1.0)
		check(b.n > 0 and b.speed > 0.0 and b.life > 0.0 and b.size > 0.0, "%s: perfil válido" % s)


# ---------------------------------------------------------------- KayKit characters (CC0)

func test_kaykit_models_have_every_clip_and_weapon_mesh() -> void:
	for cls in CharacterRig.KAYKIT:
		var def: Dictionary = CharacterRig.KAYKIT[cls]
		var path := "res://assets/third_party/kaykit/%s.glb" % def.file
		check(ResourceLoader.exists(path), "%s: existe %s" % [cls, path])
		var inst: Node = (load(path) as PackedScene).instantiate()
		var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
		for logical in def.clips:
			check(ap.has_animation(def.clips[logical]), "%s: clip %s (%s)" % [cls, def.clips[logical], logical])
		for extra in ["Walking_A", "Jump_Full_Short"]:
			check(ap.has_animation(extra), "%s: clip %s" % [cls, extra])
		var names := []
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			names.append(String(mi.name))
		for w in def.show:
			check(names.has(w), "%s: arma/accesorio %s" % [cls, w])
		for w in def.get("hide", []):
			check(names.has(w), "%s: pieza a ocultar %s" % [cls, w])
		inst.free()


func test_kaykit_license_is_bundled() -> void:
	var lic := FileAccess.get_file_as_string("res://assets/third_party/kaykit/LICENSE.txt")
	check(lic.contains("CC0") and lic.contains("Creative Commons Zero"), "la licencia CC0 está junto a los modelos")
	check(FileAccess.get_file_as_string("res://assets/third_party/kaykit/SOURCE.txt").contains("github.com/KayKit-Game-Assets"), "la fuente está registrada")


func test_rig_builds_blend_tree_and_accepts_state_changes() -> void:
	for cls in ["mage", "warrior", "rogue", "hunter", "priest"]:
		var rig := CharacterRig.new()
		rig.setup(cls, Color.RED)
		check(rig._tree != null, "%s: tiene árbol de animación" % cls)
		rig.drive(0.0, true, false, false, 0.0, true, 1.0)
		rig.drive(0.1, true, true, false, 0.0, false, 0.0)
		rig.drive(0.2, true, false, true, 800.0, false, 0.0)
		rig.drive(0.3, false, false, false, 0.0, false, 0.0)
		rig.once("attack", 0.4)
		rig.once("hit", 0.5)
		rig.jump(0.6)
		rig.root.free()


func test_every_sample_group_resolves_to_a_licensed_audio_file() -> void:
	for g in AudioBank.SAMPLE_GROUPS:
		for f in AudioBank.SAMPLE_GROUPS[g]:
			var found := false
			for path in ["res://assets/third_party/oga_sfx/%s.wav" % f, "res://assets/third_party/kenney_audio/%s.ogg" % f, "res://assets/third_party/kenney_ui/%s.ogg" % f]:
				found = found or ResourceLoader.exists(path)
			check(found, "%s/%s existe" % [g, f])
	for ev in AudioBank.LAYERS:
		for layer in AudioBank.LAYERS[ev]:
			check(AudioBank.SAMPLE_GROUPS.has(layer[0]), "%s apunta a un grupo existente (%s)" % [ev, layer[0]])
	for d in ["kenney_audio", "kenney_ui", "oga_sfx"]:
		check(FileAccess.file_exists("res://assets/third_party/%s/SOURCE.txt" % d), "%s: fuente registrada" % d)
	check(FileAccess.get_file_as_string("res://assets/third_party/oga_sfx/LICENSE.txt").contains("CC0"), "oga_sfx: licencia CC0")
	check(FileAccess.get_file_as_string("res://assets/third_party/kenney_ui/LICENSE.txt").contains("Creative Commons Zero") or FileAccess.get_file_as_string("res://assets/third_party/kenney_ui/LICENSE.txt").contains("CC0"), "kenney_ui: licencia CC0")
