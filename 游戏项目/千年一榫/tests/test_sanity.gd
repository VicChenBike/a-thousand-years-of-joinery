extends "res://tests/test_base.gd"

func _initialize() -> void:
	print("== test_sanity ==")
	check(1 + 1 == 2, "基础算术")
	check(ProjectSettings.get_setting("application/config/name") == "千年一榫", "工程名读取")
	finish()
