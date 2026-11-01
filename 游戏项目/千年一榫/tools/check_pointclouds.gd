extends SceneTree

func _initialize() -> void:
	var names: Array[String] = ["石器", "宋", "元", "明", "现代"]
	var failed: int = 0
	for n: String in names:
		var path: String = "res://assets/models/points/%s_points.res" % n
		if not ResourceLoader.exists(path):
			print("[FAIL] 缺失 %s" % path)
			failed += 1
			continue
		var res: Resource = load(path)
		var pts: PackedVector3Array = res.get("points")
		var cols: PackedColorArray = res.get("colors")
		if pts.size() < 10000 or pts.size() > 100000:
			print("[FAIL] %s 点数异常: %d" % [n, pts.size()])
			failed += 1
			continue
		if cols.size() != pts.size():
			print("[FAIL] %s 颜色数组长度不匹配" % n)
			failed += 1
			continue
		print("[PASS] %s: %d 点" % [n, pts.size()])
	if failed == 0:
		print("ALL TESTS PASSED (5 models)")
		quit(0)
	else:
		print("TESTS FAILED: %d/5" % failed)
		quit(1)
