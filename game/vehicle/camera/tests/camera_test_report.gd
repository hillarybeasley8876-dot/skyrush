extends RefCounted
## Shared PASS/FAIL report for the camera unit's tests.

var checks: int = 0
var fails: int = 0


func check(name: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if condition:
		print("PASS %s" % name)
	else:
		fails += 1
		print("FAIL %s %s" % [name, detail])


func near(name: String, actual: float, expected: float, eps: float = 0.05) -> void:
	check(name, absf(actual - expected) <= eps, "got %.4f expected %.4f" % [actual, expected])


func merge(other: RefCounted) -> void:
	checks += int(other.get("checks"))
	fails += int(other.get("fails"))
