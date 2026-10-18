class_name MenuMusic
extends RefCounted
## Cheap synthesised ambient loop for the menus: a slow minor pad, a sub drone and a few sparse bell notes.
## 10 s at 11 kHz; every tone completes whole cycles so the loop is seamless.

const RATE := 11025
const LEN := 10.0


static func make() -> AudioStreamWAV:
	var n := int(LEN * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var pad := [110.0, 130.8, 164.8, 220.0, 329.6]  # A minor, whole cycles in 10 s
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t := float(i) / RATE
		var trem := 0.65 + 0.35 * sin(TAU * 0.2 * t)
		var s := 0.0
		for k in pad.size():
			var f: float = pad[k]
			s += sin(TAU * f * t + sin(TAU * 0.1 * t + k) * 0.6) * (0.5 / (1.0 + k * 0.7))
		s = s * trem * 0.16
		s += sin(TAU * 55.0 * t) * 0.14 * (0.8 + 0.2 * sin(TAU * 0.1 * t))
		buf[i] = s
	# bells: pentatonic, decaying, never crossing the loop end
	var notes := [[0.8, 659.0], [3.1, 784.0], [5.4, 880.0], [7.2, 587.0]]
	for nt in notes:
		var start := int(nt[0] * RATE)
		var count := int(2.4 * RATE)
		for i in count:
			var k := float(i) / RATE
			buf[start + i] += sin(TAU * nt[1] * k) * exp(-k * 2.2) * 0.07 + sin(TAU * nt[1] * 2.01 * k) * exp(-k * 4.0) * 0.025
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 26000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = bytes
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w
