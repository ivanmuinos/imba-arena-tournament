class_name Rng
extends RefCounted
## mulberry32: the same deterministic generator as the web version, so maps match exactly.

const MASK := 0xFFFFFFFF
var _a: int


func _init(seed_value: int) -> void:
	_a = seed_value & MASK


static func _imul(a: int, b: int) -> int:
	# 64-bit multiply then keep the low 32 bits (what JS Math.imul does).
	return (a * b) & MASK


func next() -> float:
	_a = (_a + 0x6D2B79F5) & MASK
	var t := _a
	t = _imul(t ^ (t >> 15), t | 1)
	t ^= (t + _imul(t ^ (t >> 7), t | 61)) & MASK
	t &= MASK
	return float((t ^ (t >> 14)) & MASK) / 4294967296.0
