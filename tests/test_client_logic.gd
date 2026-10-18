extends TestBase
## Interpolation, prediction and the local player's casting rules.


func _snap(ts: float, units: Array) -> Dictionary:
	return {"ts": ts, "units": units}


func _u(id: int, x: float, z: float, rot := 0.0) -> Dictionary:
	return {"id": id, "x": x, "z": z, "rot": rot}


# ---------------------------------------------------------------- snapshot buffer

func test_buffer_interpolates_between_snapshots() -> void:
	var b := SnapshotBuffer.new()
	# Server clock == local clock (offset 0); render 100 ms in the past.
	b.push(_snap(1000.0, [_u(1, 0.0, 0.0)]), 1000.0)
	b.push(_snap(1033.0, [_u(1, 1.0, 0.0)]), 1033.0)
	b.push(_snap(1066.0, [_u(1, 2.0, 0.0)]), 1066.0)
	b.push(_snap(1099.0, [_u(1, 3.0, 0.0)]), 1099.0)
	# local 1166 -> render time 1066 -> exactly the third snapshot
	near(b.sample(1166.0)[1].x, 2.0, 0.01, "en el instante de un snapshot")
	# local 1149.5 -> render 1049.5 -> halfway between 1033 and 1066
	near(b.sample(1149.5)[1].x, 1.5, 0.01, "a mitad de camino")


func test_buffer_holds_last_position_when_starved() -> void:
	var b := SnapshotBuffer.new()
	b.push(_snap(1000.0, [_u(1, 5.0, 5.0)]), 1000.0)
	near(b.sample(5000.0)[1].x, 5.0, 0.001, "sin datos nuevos se queda quieto")


func test_buffer_drops_out_of_order_and_hides_missing_units() -> void:
	var b := SnapshotBuffer.new()
	check(b.push(_snap(1000.0, [_u(1, 0, 0), _u(2, 1, 1)]), 1000.0), "primero")
	check(not b.push(_snap(990.0, [_u(1, 9, 9)]), 1010.0), "fuera de orden descartado")
	b.push(_snap(1033.0, [_u(1, 1, 0)]), 1033.0)  # unit 2 left our vision
	var s := b.sample(1200.0)
	check(s.has(1), "visible")
	check(not s.has(2), "el que salió de la vista no se muestra")


func test_buffer_does_not_slide_across_teleports() -> void:
	var b := SnapshotBuffer.new()
	b.push(_snap(1000.0, [_u(1, 0.0, 0.0)]), 1000.0)
	b.push(_snap(1033.0, [_u(1, 8.0, 0.0)]), 1033.0)  # blink
	b.push(_snap(1066.0, [_u(1, 8.0, 0.0)]), 1066.0)
	near(b.sample(1140.0)[1].x, 8.0, 0.001, "salta, no desliza")


func test_buffer_interpolates_rotation_the_short_way() -> void:
	var b := SnapshotBuffer.new()
	b.push(_snap(1000.0, [_u(1, 0, 0, 3.0)]), 1000.0)
	b.push(_snap(1100.0, [_u(1, 0, 0, -3.0)]), 1100.0)
	var r: float = b.sample(1150.0)[1].rot  # halfway
	check(absf(r) > 2.9, "pasa por PI, no por 0 (%s)" % r)


# ---------------------------------------------------------------- predictor

func _me(x: float, z: float) -> Dictionary:
	return {"x": x, "z": z, "alive": true, "cc": {}, "buffs": {}, "cast": null, "dashing": false}


func test_predictor_moves_like_the_server() -> void:
	var map := GameMap.create("test")
	var p := Predictor.new()
	p.place(0.0, 40.0)
	var me := _me(0.0, 40.0)
	for i in 60:
		p.step(1.0 / 60.0, Vector2(0, -1), me, "mage", true, map, 1.0, 0.0)
	near(40.0 - p.m.z, 6.1, 0.3, "avanza ~velocidad de clase en 1 s")


func test_predictor_does_not_move_when_stunned_or_in_prep() -> void:
	var map := GameMap.create("test")
	var p := Predictor.new()
	p.place(0.0, 40.0)
	var me := _me(0.0, 40.0)
	me.cc = {"stun": 1000}
	for i in 30:
		p.step(1.0 / 60.0, Vector2(0, -1), me, "mage", true, map, 1.0, 0.0)
	near(p.m.z, 40.0, 0.01, "aturdido")
	me.cc = {}
	for i in 30:
		p.step(1.0 / 60.0, Vector2(0, -1), me, "mage", false, map, 1.0, 0.0)
	near(p.m.z, 40.0, 0.01, "en preparación")


func test_predictor_converges_to_server_and_snaps_on_big_error() -> void:
	var map := GameMap.create("test")
	var p := Predictor.new()
	p.place(0.0, 40.0)
	var me := _me(1.0, 40.0)
	for i in 120:
		p.step(1.0 / 60.0, Vector2.ZERO, me, "mage", true, map, 0.01, 1000.0)
	near(p.m.x, 1.0, 0.05, "corrige hacia el servidor")
	me = _me(20.0, 10.0)
	p.on_state(me, "fight", 1000.0)
	near(p.m.x, 20.0, 0.001, "error grande: se reubica")


func test_predicted_blink_is_instant_and_ignores_corrections() -> void:
	var map := GameMap.create("test")
	var p := Predictor.new()
	p.place(0.0, 40.0)
	var me := _me(0.0, 40.0)
	check(p.predict_movement("mage", 4, Vector2(0, -1), me, map, 1000.0), "predice la traslación")
	near(p.m.z, 32.0, 0.01, "8 m hacia adelante")
	for i in 5:
		p.step(1.0 / 60.0, Vector2.ZERO, me, "mage", true, map, 0.01, 1100.0)
	near(p.m.z, 32.0, 0.05, "no lo corrige el snapshot viejo")
	check(not p.predict_movement("warrior", 4, Vector2(0, -1), me, map, 1000.0), "otras clases no")
