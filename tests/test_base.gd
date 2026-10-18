class_name TestBase
extends RefCounted
## Tiny assertion helpers for the headless test runner.

## Set by the runner so UI tests can add nodes to the live tree.
static var tree: SceneTree = null

var failures: Array[String] = []
var current := ""


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append("%s: %s" % [current, msg])


func eq(a, b, msg := "") -> void:
	check(a == b, "%s (esperado %s, obtuvo %s)" % [msg, str(b), str(a)])


func near(a: float, b: float, tol: float, msg := "") -> void:
	check(absf(a - b) <= tol, "%s (esperado ~%s, obtuvo %s)" % [msg, str(b), str(a)])
