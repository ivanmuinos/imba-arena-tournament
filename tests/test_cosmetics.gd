extends TestBase
## Cosmetics (S11): equipped title, ring colour and class recolors as the views read them.


func _profile() -> ProfileStore:
	var path := "user://test_cos_profile.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ".tmp"))
	return ProfileStore.new(path)


func test_nothing_equipped_gives_defaults() -> void:
	Cosmetics.profile = null
	eq(Cosmetics.title(), "", "sin título")
	eq(Cosmetics.ring_color(Color.RED), Color.RED, "anillo por defecto")
	eq(Cosmetics.skin_for("mage"), "", "sin recoloreado")
	Cosmetics.profile = _profile()
	eq(Cosmetics.title(), "", "perfil vacío: sin título")
	eq(Cosmetics.skin_for("mage"), "", "perfil vacío: sin recoloreado")
	Cosmetics.profile = null


func test_equipped_items_are_read_from_the_profile() -> void:
	var p := _profile()
	p.unlocked = ["title_mage", "ring_mage", "recolor_mage", "recolor_warrior"]
	check(p.equip("title", "title_mage") and p.equip("ring", "ring_mage") and p.equip("recolor", "recolor_mage"), "equipa")
	Cosmetics.profile = p
	eq(Cosmetics.title(), str(Challenges.item("title_mage").name), "título")
	eq(Cosmetics.ring_color(Color.RED), Color(str(Challenges.item("ring_mage").value)), "color del anillo")
	eq(Cosmetics.skin_for("mage"), "recolor_mage", "recoloreado del mago")
	eq(Cosmetics.skin_for("warrior"), "", "otra clase sin recoloreado")
	eq(Cosmetics.rig_skin("mage"), {"id": "recolor_mage", "recolor": Cosmetics.tint("recolor_mage")}, "la skin reemplaza el recoloreado de la clase")
	eq(Cosmetics.rig_skin("warrior"), {}, "otra clase sin skin")
	Cosmetics.profile = null


func test_every_recolor_item_has_a_valid_tint() -> void:
	var n := 0
	for it in Challenges.items():
		if str(it.kind) != "recolor":
			continue
		n += 1
		var t := Cosmetics.tint(str(it.id))
		check(t.has_all(["hue", "sat", "val"]), "tinte completo: " + str(it.id))
		check(absf(float(t.hue)) <= 1.0 and absf(float(t.sat)) <= 1.0 and absf(float(t.val)) <= 1.0, "valores acotados: " + str(it.id))
	eq(n, 13, "13 recoloreados")
	eq(Cosmetics.tint("nope"), {}, "desconocido: sin tinte")


func test_skin_replaces_the_base_recolor_and_changes_the_cache_key() -> void:
	Cosmetics.profile = null
	eq(Cosmetics.rig_skin("mage"), {}, "sin perfil: sin skin")
	check(CharacterRig.recolor_key("mage", "Mage", "a") != CharacterRig.recolor_key("mage", "Mage", "b"), "la clave distingue skins")
	check(CharacterRig.recolor_key("mage", "Mage", "") != CharacterRig.recolor_key("mage", "Mage", "a"), "y la ausencia de skin")


func test_warlock_is_in_the_rig_table() -> void:
	check(CharacterRig.KAYKIT.has("warlock"), "brujo con modelo")
	for cls in GameData.playable_ids():
		check(CharacterRig.KAYKIT.has(cls), "toda clase jugable tiene modelo: " + str(cls))
