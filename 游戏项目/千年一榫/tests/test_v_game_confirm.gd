extends "res://tests/test_base.gd"
## 批次 V（V-C3a，spec §3.1/§3.2）判定用例：Game.confirm/info 全局弹条统一入口（TDD 先写）。
## 契约（confirm 类消费方——settings_panel 摄像头钮 / main_menu 新游戏退出 / level_scene 退出 /
## shop_panel 购买确认——统一 Game 级入口，本 API 为并行迁移路的消费地基）：
##   Game.confirm(text, on_confirmed=Callable(), on_canceled=Callable())——
##     已注册 strip（attach_strip 收到过）→ 委托 strip.push_confirm(text, on_confirmed, on_canceled)
##       恰 1 次（不双投右上 ToastCenter）；
##     未注册（极端时序/无头 fresh 实例）→ 兜底 Game.toast(text, "warn", 3.0, true)（信息可达性，
##       不静默丢弃）+ push_warning 留痕，回调不执行（无条即无确认/取消按钮，静默执行=不可撤销副作用）；
##   Game.info(text, seconds=3.0)——= toast(text, "warn", seconds, true) 对称便捷口：
##     已注册 strip → toast 的 V-C1 单点改道进 strip.push_info；未注册 → 右上原路径降级
##     （既有 toast 行为零改动）。
## 4.7 坑 1：回调判空一律 is_valid()（不引入 bool/Callable 强转）；坑 8：计数器用成员变量
##（lambda 按值捕获局部变量，成员变量经 self 读写可见）。
## P2-5 纪律：load()/has_method()/call()，不引用全局类名；
## 复跑 test_v_top_strip.gd / test_toast_center.gd 防回归（既有 toast/attach 链路零改动）。

const GAME_SCRIPT := "res://autoload/game.gd"
const SPY_SCRIPT := "res://tests/fixtures/toast_spy.gd"

## 内联夹具：TopStrip 替身——记录 push_confirm/push_info 调用参数；确认/取消路径由测试直接
## 调用记录到的回调（模拟 strip 按钮触发），验证 Game.confirm 的回调透传语义。
class StripSpy extends Node:
	var confirm_calls: Array = []   # 每项 [text, on_confirmed, on_canceled]
	var info_calls: Array = []      # 每项 [text, seconds]
	func push_confirm(text: String, on_confirmed: Callable = Callable(),
			on_canceled: Callable = Callable()) -> void:
		confirm_calls.append([text, on_confirmed, on_canceled])
	func push_info(text: String, seconds: float = 3.0) -> void:
		info_calls.append([text, seconds])

var _ok_count := 0
var _cancel_count := 0
var _fallback_ok := 0

func _initialize() -> void:
	print("== test_v_game_confirm ==")
	var game_script: GDScript = load(GAME_SCRIPT) as GDScript
	check(game_script != null, "V-C3a：game.gd 可加载")
	if game_script == null:
		finish()
		return

	# ---- A. 契约形态：confirm/info 两 API 齐备（未实现即红；早退防后续 call 错误刷屏） ----
	var game: Node = game_script.new()
	add_child(game)
	var has_api: bool = game.has_method("confirm") and game.has_method("info")
	check(has_api, "V-C3a：Game.confirm/info 契约方法齐备")
	if not has_api:
		finish()
		return
	check(game.get("_strip") == null, "V-C3a：fresh 实例 _strip 初始为空（未注册态）")

	# ---- B. 注册路径：confirm 委托 strip.push_confirm（参数透传、恰 1 次、不双投右上） ----
	var ssp: StripSpy = StripSpy.new()
	add_child(ssp)
	var tsp: Node = (load(SPY_SCRIPT) as GDScript).new()
	add_child(tsp)
	game.call("attach_strip", ssp)
	game.call("attach_toast", tsp)
	var ok_cb: Callable = func() -> void: _ok_count += 1
	var cancel_cb: Callable = func() -> void: _cancel_count += 1
	game.call("confirm", "退出《千年一榫》？", ok_cb, cancel_cb)
	check_eq(ssp.confirm_calls.size(), 1, "V-C3a：注册后 Game.confirm → strip.push_confirm 恰 1 次")
	if ssp.confirm_calls.size() == 1:
		var rec: Array = ssp.confirm_calls[0]
		check_eq(String(rec[0]), "退出《千年一榫》？", "V-C3a：push_confirm 收到原文案")
		check(rec[1] is Callable and (rec[1] as Callable).is_valid(),
			"V-C3a：on_confirmed 透传且有效（坑 1：is_valid 判空口径）")
		check(rec[2] is Callable, "V-C3a：on_canceled 透传")
	check_eq((tsp.call("get_calls") as Array).size(), 0,
		"V-C3a：注册路径不走右上 ToastCenter（单点委托不双投）")

	# ---- C. 模拟 strip 回调：确认/取消路径各恰 1 次（透传语义成立） ----
	if ssp.confirm_calls.size() == 1:
		(ssp.confirm_calls[0][1] as Callable).call()
		check(_ok_count == 1 and _cancel_count == 0,
			"V-C3a：确认路径（模拟 strip 触发 on_confirmed）→ 恰 1 次、on_canceled 零调用")
		(ssp.confirm_calls[0][2] as Callable).call()
		check(_cancel_count == 1, "V-C3a：取消路径（模拟 strip 触发 on_canceled）→ 恰 1 次")
	# 缺省回调：confirm 只传文案 → 透传 Callable()（strip 侧 is_valid 判空静默收起）
	game.call("confirm", "静默条")
	if ssp.confirm_calls.size() == 2:
		var ok2: Callable = ssp.confirm_calls[1][1]
		var cancel2: Callable = ssp.confirm_calls[1][2]
		check(not ok2.is_valid() and not cancel2.is_valid(),
			"V-C3a：缺省回调透传 Callable()（strip 侧静默收起，无强转）")

	# ---- D. 注册路径：info 经 toast 单点改道 strip.push_info（参数透传 + 右上零转发） ----
	game.call("info", "本游戏支持手势交互和键鼠交互", 4.0)
	check_eq(ssp.info_calls.size(), 1, "V-C3a：注册后 Game.info → strip.push_info 恰 1 次")
	if ssp.info_calls.size() >= 1:
		check_eq(String(ssp.info_calls[0][0]), "本游戏支持手势交互和键鼠交互", "V-C3a：info 收到原文案")
		check_eq(float(ssp.info_calls[0][1]), 4.0, "V-C3a：info 透传 seconds")
	check_eq((tsp.call("get_calls") as Array).size(), 0,
		"V-C3a：info 改道时右上 ToastCenter 零转发（不双投）")
	game.call("info", "默认档")
	if ssp.info_calls.size() >= 2:
		check_eq(float(ssp.info_calls[1][1]), 3.0, "V-C3a：info 缺省 seconds=3.0")

	# ---- E. 未注册路径：fresh 实例 confirm 兜底 toast（信息可达）+ 回调不执行 ----
	var game2: Node = game_script.new()
	add_child(game2)
	var tsp2: Node = (load(SPY_SCRIPT) as GDScript).new()
	add_child(tsp2)
	game2.call("attach_toast", tsp2)   # 未 attach_strip → 走兜底
	game2.call("confirm", "兜底条", func() -> void: _fallback_ok += 1)
	check_eq(_fallback_ok, 0, "V-C3a：未注册 confirm 回调不执行（无条即无按钮，不静默执行）")
	var calls2: Array = tsp2.call("get_calls") as Array
	check_eq(calls2.size(), 1, "V-C3a：未注册 confirm → 兜底 Game.toast 恰 1 次（不静默丢弃）")
	if calls2.size() == 1:
		check_eq(String(calls2[0][0]), "兜底条", "V-C3a：兜底收到原文案")
		check_eq(String(calls2[0][1]), "warn", "V-C3a：兜底 level=warn")
		check_eq(float(calls2[0][2]), 3.0, "V-C3a：兜底 seconds=3.0")
		check_eq(bool(calls2[0][3]), true, "V-C3a：兜底 centered=true（居中警示档）")

	# ---- E2. 未注册路径：info → 右上原路径降级（= toast(text,"warn",seconds,true) 既有口径） ----
	game2.call("info", "降级中央", 2.0)
	var calls3: Array = tsp2.call("get_calls") as Array
	check_eq(calls3.size(), 2, "V-C3a：未注册 info → 右上 ToastCenter 原路径（降级可达）")
	if calls3.size() == 2:
		check_eq(String(calls3[1][0]), "降级中央", "V-C3a：降级 info 原文案")
		check_eq(String(calls3[1][1]), "warn", "V-C3a：降级 info level 固定 warn")
		check_eq(float(calls3[1][2]), 2.0, "V-C3a：降级 info 透传 seconds")
		check_eq(bool(calls3[1][3]), true, "V-C3a：降级 info centered=true")

	# ---- E3. 全未挂接：confirm/info 零异常（push_warning 静默降级，回调仍不执行） ----
	var game3: Node = game_script.new()
	add_child(game3)
	game3.call("confirm", "全降级确认", func() -> void: _fallback_ok += 1)
	game3.call("info", "全降级信息")
	check(true, "V-C3a：全未挂接 confirm/info 零异常（push_warning 静默降级）")
	check_eq(_fallback_ok, 0, "V-C3a：全降级路径回调恒不执行")

	game.queue_free()
	game2.queue_free()
	game3.queue_free()
	tsp.queue_free()
	tsp2.queue_free()
	ssp.queue_free()
	await process_frame
	finish()
