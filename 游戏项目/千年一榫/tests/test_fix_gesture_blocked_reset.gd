extends "res://tests/test_base.gd"
## 修复批红测 4（P3，手势域）：手势禁用期间每包 reset + 无条件 countdown_cancelled。
## 病灶双联：
##   a) gesture_router.gd feed 非 READY/禁用分支（:210-212）每包调 reset_runtime（N 包 N 次清态）；
##   b) gesture_exit_tracker.gd reset() 末尾无条件 emit countdown_cancelled("reset")（:38）。
## 后果：倒数进行中关手势 → N 个 blocked 包 → cancelled 信号被打 N 次（主侧幂等 hide 掩盖，
## 但信号风暴属病灶；清态每帧重跑也是无谓开销）。
## 修法：a) router 侧「状态迁移才 reset」（进入 blocked 恰一次 latch，恢复后解除）；
##       b) tracker.reset 仅在倒数活跃（_remaining>0）时才 emit（清态语义不变）。
## 红断言：倒数激活 → 禁用手势 → 连喂 5 个 blocked 包 → cancelled 恰 1 次（改前=5）。
## 零磁盘写：settings 只改 SaveManager._data 内存（不走 update_settings/save_game），
## 终段还原内存 + save.json 逐字节自证。
const ROUTER_SRC := "res://autoload/gesture_router.gd"
const TRACKER_SRC := "res://scripts/gesture_exit_tracker.gd"
const SAVE_PATH := "user://save.json"
var _pre_save_text := ""
var _orig_gesture_input := true
var _cancel_count := 0

## null/异型安全布尔读（bool(null) 4.7 无构造器中止坑防御）
func _to_bool(v: Variant, d: bool) -> bool:
	if typeof(v) == TYPE_BOOL:
		return v
	if typeof(v) == TYPE_INT:
		return int(v) != 0
	if typeof(v) == TYPE_STRING:
		return String(v) == "true" or String(v) == "1"
	return d

func _on_cancelled(_reason: String) -> void:
	_cancel_count += 1

func _initialize() -> void:
	print("== test_fix_gesture_blocked_reset ==")
	if FileAccess.file_exists(SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(SAVE_PATH)
	await process_frame   # 树激活
	var bridge: Node = root.get_node("GestureBridge")
	var router: Node = root.get_node("GestureRouter")
	var save: Node = root.get_node("SaveManager")
	check(bridge != null and router != null and save != null, "前置：三 autoload 在位")
	if bridge == null or router == null or save == null:
		finish()
		return
	# 桥置 READY（feed 非 blocked 的另一半门；先置态避免其信号边沿清态计入计数）
	bridge.call("_set_state", 1)
	router.call("_setup")   # 确保 _map/_tracker 就位（无头 _initialize 期直取安全）
	var tr: Variant = router.get("_tracker")
	check(tr != null, "前置：tracker 就位（RefCounted，禁 as Node——4.7 空转换坑）")
	if tr == null:
		finish()
		return
	# 内存读原值（不落盘）——settings 字典经 update_settings 同款引用机制直改；
	# 判空防御（bool(null) 4.7 无构造器中止坑——并行跑测期存档态可能缺键）
	var set_v: Variant = save.call("get_settings")
	_orig_gesture_input = true
	if typeof(set_v) == TYPE_DICTIONARY:
		_orig_gesture_input = _to_bool((set_v as Dictionary).get("gesture_input"), true)
	# 计数器接在所有清态动作之后（_set_state 若有边沿清态不计入）
	_cancel_count = 0
	tr.connect("countdown_cancelled", _on_cancelled)
	# 激活倒数（首翻 → _remaining=3，倒数弹条在场语义）
	tr.call("notify_flip", 100.0)
	check_eq(int(tr.get("_remaining")), 3, "前置：倒数已激活（_remaining=3）")
	# 进入 blocked：手势禁用（内存改写，零写盘）
	if typeof(set_v) != TYPE_DICTIONARY:
		check(false, "前置：settings 字典在位（非字典=并行跑测期存档态异常，防中止挂死）")
		finish()
		return
	var settings: Dictionary = set_v
	settings["gesture_input"] = false
	# 连喂 5 个 blocked 包
	for i: int in 5:
		router.call("feed", {"left": null, "right": null, "timestamp": float(i) * 0.033})
	check_eq(_cancel_count, 1,
		"P3 红测：5 个 blocked 包 → countdown_cancelled 恰 1 次（改前每包 reset=5 次；清态保留首迁）")
	check_eq(int(tr.get("_remaining")), 0, "清态语义保持：倒数已清（首迁 reset 生效）")
	# 反向护栏 1：再连喂 3 个 blocked 包 → 仍不新增 emit（latch 持续）
	for i: int in 3:
		router.call("feed", {"left": null, "right": null, "timestamp": 1.0 + float(i) * 0.033})
	check_eq(_cancel_count, 1, "反向护栏：持续 blocked 不重复 emit（latch 生效）")
	# 反向护栏 2：恢复启用 → 首个正常包解除 latch；再次禁用 → 新一轮恰 1 次
	settings["gesture_input"] = true
	router.call("feed", {"left": null, "right": null, "timestamp": 2.0})
	tr.call("notify_flip", 200.0)
	check_eq(int(tr.get("_remaining")), 3, "恢复后倒数可重新激活（清态不破坏重启）")
	settings["gesture_input"] = false
	router.call("feed", {"left": null, "right": null, "timestamp": 2.1})
	check_eq(_cancel_count, 2, "再入 blocked 迁移 → 恰再 1 次（迁移语义，非每包）")
	# 还原内存原值 + 磁盘逐字节自证（本测试零写盘）
	settings["gesture_input"] = _orig_gesture_input
	var post: String = FileAccess.get_file_as_string(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：save.json 起测/终测逐字节等价（本测试零写盘）")
	finish()
