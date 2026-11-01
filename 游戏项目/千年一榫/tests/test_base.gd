extends SceneTree
## 轻量测试基类：统计 check/check_eq 结果，全部通过退出码 0，否则 1。
## 用法：测试脚本 extends 本文件（继承时脚本放 tests/ 下），在 _initialize() 里写断言，最后调用 finish()。

var _total: int = 0
var _failed: int = 0

func add_child(node: Node) -> void:
	## SceneTree 本身无 add_child；测试中把被测节点挂到根窗口（转发）。
	root.add_child(node)

func check(cond: bool, msg: String) -> void:
	_total += 1
	if cond:
		print("[PASS] %s" % msg)
	else:
		_failed += 1
		print("[FAIL] %s" % msg)

func check_eq(actual: Variant, expected: Variant, msg: String) -> void:
	check(actual == expected, "%s（期望 %s，实际 %s）" % [msg, str(expected), str(actual)])

func finish() -> void:
	if _failed == 0:
		print("ALL TESTS PASSED (%d checks)" % _total)
		quit(0)
	else:
		print("TESTS FAILED: %d/%d" % [_failed, _total])
		quit(1)
