extends TestBase
## Sonido de partida: pisadas, salto, aterrizaje y fanfarrias son grabaciones reales; los sonidos del mundo salen de
## un punto del espacio (se escuchan a izquierda o derecha) y la arena tiene un fondo de ambiente.


func test_movement_and_round_cues_are_real_recordings() -> void:
	var bank := AudioBank.new()
	for sound in ["step", "jump", "land", "fight", "win", "lose"]:
		check(AudioBank.LAYERS.has(sound), "%s tiene capas de audio real" % sound)
		check(not AudioBank.R.has(sound), "%s ya no es un pitido sintetizado" % sound)
		for layer in AudioBank.LAYERS.get(sound, []):
			for f in AudioBank.SAMPLE_GROUPS[layer[0]]:
				check(bank._sample(f) != null, "%s/%s se importa" % [sound, f])
	bank.free()


func test_world_sounds_come_from_their_place_and_ui_sounds_do_not() -> void:
	var bank := AudioBank.new()
	tree.root.add_child(bank)
	bank.listener = Vector2(0, 0)
	bank.play("hit", Vector2(5.0, 7.0))
	var placed := bank._spatial.filter(func(p): return p.stream != null)
	check(not placed.is_empty(), "un sonido con posición usa un reproductor espacial")
	if not placed.is_empty():
		near((placed[0] as AudioStreamPlayer3D).position.x, 5.0, 1e-4, "en la x del golpe")
		near((placed[0] as AudioStreamPlayer3D).position.z, 7.0, 1e-4, "en la z del golpe")
		eq((placed[0] as AudioStreamPlayer3D).attenuation_model, AudioStreamPlayer3D.ATTENUATION_DISABLED, "el volumen por distancia lo sigue decidiendo el banco")
	bank.play("uiClick")
	check(bank._players.any(func(p): return p.stream != null), "la interfaz suena centrada, sin posición")
	bank.free()


func test_arena_ambience_loops_and_stops() -> void:
	var bank := AudioBank.new()
	tree.root.add_child(bank)
	bank.start_ambience()
	check(bank._ambience != null and bank._ambience.stream != null, "hay un fondo de ambiente")
	check((bank._ambience.stream as AudioStreamOggVorbis).loop, "y se repite sin cortes")
	check(bank._ambience.volume_db < -12.0, "bajo: acompaña, no tapa el combate")
	bank.stop_ambience()
	check(not bank._ambience.playing, "se puede apagar")
	bank.free()


func test_footsteps_follow_the_stride() -> void:
	var c := StepCadence.new()
	var steps := 0
	for i in 60:  # 1 s a velocidad de carrera
		if c.advance(1.0 / 60.0, 7.0, 7.0, true):
			steps += 1
	check(steps >= 2 and steps <= 4, "corriendo: unas 3 pisadas por segundo (%d)" % steps)
	steps = 0
	for i in 60:
		if c.advance(1.0 / 60.0, 7.0, 7.0, false):
			steps += 1
	eq(steps, 0, "en el aire no hay pisadas")
	for i in 60:
		if c.advance(1.0 / 60.0, 0.2, 7.0, true):
			steps += 1
	eq(steps, 0, "quieto tampoco")
	var slow := 0
	for i in 120:
		if c.advance(1.0 / 60.0, 3.5, 7.0, true):
			slow += 1
	var fast := 0
	for i in 120:
		if c.advance(1.0 / 60.0, 7.0, 7.0, true):
			fast += 1
	check(slow < fast, "más lento, pisadas más espaciadas (%d < %d)" % [slow, fast])
