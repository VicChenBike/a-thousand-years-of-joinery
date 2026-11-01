extends "res://tests/test_base.gd"
## 批次 W W4（2026-09-20 规格 §5）——手势状态与输入边界 TDD 红测先行。
## 段口径：
##   A（P1-8a）reset_runtime 合成抬起兜底：armed/_left_stroking/_right_stroking 三类按下
##     标志各按原 ctrl 语义补 _push_btn(记位,false,ctrl) 抬起（左/笔支 false、右取消支 true 对齐
##     STROKE_DESELECT :447 口径）；无按下标志时零合成事件。
##   B（P1-8b）ExitGestureTracker.reset() 末尾 emit countdown_cancelled("reset")——倒数中 reset
##     补发恰一次；router.reset_runtime 链路转发（main 侧幂等 hide 消费）。
##   C（P1-1）退出确认全分支 _tracker.reset()：MAIN_MENU/CATALOG/OPENING_MOVIE/TALK/LEVEL 五
##     确认分支确认后 _done 复位、再次四翻可重新触发（推翻「保持分支局部」旧裁决，规格拍板 1）。
##   D（P3-2b）单击抬起统一取按下位：armed 按下位记位，two_up 抬起位=按下位（旧码用抬起帧
##     指尖位=缺陷）。
##   E（P3-2c）reset_runtime 清 _last_cursor_pos/_last_two_pos/_last_cursor_at 三键。
##   F（P3-2d/e）gesture_map：另一手离场/翻转手自身离场 → pending flip 丢弃（零撤销）；同侧
##     连续翻转刷新窗口起点（恰一次撤销）；fingers 短数组/脏值 feed 不炸。
##   G（P2-6）键鼠互斥门：物理鼠标按下期间 _push_btn 合成事件丢弃。
##   H（N6）骨架变细常量锁：SKELETON_LINE_W=1.2 / TIP_R=4.0 / JOINT_R=2.5。
## 无头纪律：零摄像头零子进程；bridge._set_state(1) 直置 READY（test_t_level_mode 先例）；
## user:// 零触碰（本文件不读写存档）。

const F_CURSOR := [0.1, 0.9, 0.1, 0.1, 0.1]
const F_TWO := [0.1, 0.9, 0.9, 0.1, 0.1]
const F_FOUR := [0.1, 0.9, 0.9, 0.9, 0.9]
const F_FOLD := [0.1, 0.1, 0.1, 0.1, 0.1]
const F_REST := [0.1, 0.1, 0.1, 0.1, 0.1]

var router: Variant
var mock: MockLayer

class MockLayer extends CanvasLayer:
	var calls: Array = []
	func synth_button(pos: Vector2, pressed: bool, ctrl: bool) -> InputEventMouseButton:
		calls.append(["btn", pos, pressed, ctrl])
		return InputEventMouseButton.new()
	func synth_motion(pos: Vector2) -> InputEventMouseMotion:
		calls.append(["motion", pos])
		return InputEventMouseMotion.new()
	func push(_ev: InputEvent) -> void:
		calls.append(["push"])
	func show_cursor(_side: String, _pos: Vector2) -> void:
		pass

func _btn_releases() -> Array:
	var out: Array = []
	for c: Variant in mock.calls:
		if c[0] == "btn" and not bool(c[2]):
			out.append(c)
	return out

## test_gesture_map 同构手 dict（palm_size 参与掌面朝镜叉积基准）
func _hand(conf: float, fingers: Array, roll: float, facing: bool, label: String,
		tip: Vector2, ts: float) -> Dictionary:
	var lm: Array = []
	for i: int in 21:
		lm.append([0.5, 0.5, 0.0])
	lm[0] = [tip.x - 0.05, tip.y + 0.2, 0.0]
	# 朝向分支照抄 test_gesture_map._hand（cz<0=左掌朝镜；左+facing=true 走 else 镜像布局）
	if (label == "Right") == facing:
		lm[5] = [lm[0][0] - 0.05, lm[0][1] - 0.06, 0.0]
		lm[17] = [lm[0][0] + 0.05, lm[0][1] - 0.05, 0.0]
	else:
		lm[5] = [lm[0][0] + 0.05, lm[0][1] - 0.06, 0.0]
		lm[17] = [lm[0][0] - 0.05, lm[0][1] - 0.05, 0.0]
	lm[8] = [tip.x, tip.y, 0.0]
	lm[9] = [lm[0][0], lm[0][1] - 0.2, 0.0]
	return {"gesture": "", "gesture_id": 0, "confidence": conf,
		"hand_x": tip.x, "hand_y": tip.y, "hand_z": 0.0,
		"hand_rotation_x": roll, "hand_rotation_y": 0.0, "hand_rotation_z": 0.0,
		"fingers": fingers, "pinch_distance": 0.5, "hand_index": 0, "handedness": label,
		"landmarks": lm, "fps": 30.0, "is_detected": true, "timestamp": ts, "palm_size": 0.2}

func _initialize() -> void:
	print("== test_w_gesture_state ==")
	var game: Node = get_root().get_node("Game")
	var bridge: Node = get_root().get_node("GestureBridge")
	bridge._set_state(1)
	router = load("res://autoload/gesture_router.gd").new()
	add_child(router)
	await process_frame
	# AF 同步批（2026-11-01）：内存钉 gesture_input=true（本文件纪律「user:// 零触碰」，不落盘
	# 进程退出即弃）。实证：router.feed 守卫链 `_gesture_enabled()`（W4 键鼠互斥门同族前置）读
	# SaveManager settings 的 gesture_input——用户存档 Q3 双关时全部 feed 走 blocked 早退+reset，
	# 段 D armed 单击/段 I 掌态推拉/P2-4 新首包登记的合成帧全部不可达（非代码回归；「手势关=
	# 零手势事件」生产语义正确）。钉位必须在本文件首个 await 之后——--script 模式 SaveManager
	# ._ready（load_game 整体替换 _data 引用）在树激活（首个 await）时才跑，先前钉会被冲
	#（test_w_bridge_lifecycle 段 C 同款钉位实证）。
	var sm_state: Node = get_root().get_node("SaveManager")
	if sm_state != null:
		var sm_data_state: Dictionary = sm_state.get("_data")
		if typeof(sm_data_state.get("settings")) != TYPE_DICTIONARY:
			sm_data_state["settings"] = {}
		(sm_data_state["settings"] as Dictionary)["gesture_input"] = true
	# 批次 AF 终审备案族（语言钉扎先例=6411fae o_catalog_shop）：autoload _ready 推迟至树激活，
	# 须等一帧后钉 zh——用户真实存档现 language=en，不钉则文案断言呈 en 态假红。
	# 编译窗安全：经节点查找而非全局名（--script 模式 autoload 全局名编译期未注册）。
	var i18n_node: Variant = get_root().get_node_or_null("I18n")
	if i18n_node != null:
		i18n_node.call("set_language", "zh")
	router._setup()
	mock = MockLayer.new()
	add_child(mock)
	router.set_cursor_layer(mock)

	# ---- 段 A（P1-8a）：reset_runtime 合成抬起兜底 ----
	# A1 armed 左支：记位=_last_cursor_pos["left"]，抬起 (false,false)
	router.set("_menu_click_armed", {"left": true, "right": false})
	router.set("_last_cursor_pos", {"left": Vector2(100, 50), "right": Vector2(600, 300)})
	router.call("reset_runtime")
	var rel: Array = _btn_releases()
	check_eq(rel.size(), 1, "A1：armed 残留 → reset_runtime 合成抬起恰一次")
	if rel.size() == 1:
		check(bool(rel[0][2]) == false and bool(rel[0][3]) == false,
			"A1：左支抬起 ctrl=false（左键语义）")
		check_eq((rel[0][1] as Vector2), Vector2(100, 50), "A1：抬起位=armed 记位")
	check_eq(bool(router.get("_menu_click_armed")["left"]), false, "A1：armed 标志清零")
	mock.calls.clear()
	# A2 左笔 stroking：记位=_last_two_pos["left"]
	router.set("_left_stroking", true)
	router.set("_last_two_pos", {"left": Vector2(200, 60), "right": Vector2(600, 300)})
	router.call("reset_runtime")
	rel = _btn_releases()
	check_eq(rel.size(), 1, "A2：_left_stroking 残留 → 合成抬起恰一次")
	if rel.size() == 1:
		check(bool(rel[0][3]) == false, "A2：笔画抬起 ctrl=false")
		check_eq((rel[0][1] as Vector2), Vector2(200, 60), "A2：抬起位=two 记位")
	mock.calls.clear()
	# A3 右取消支：Ctrl 抬起配对（对齐 :447 STROKE_DESELECT 口径）
	router.set("_right_stroking", true)
	router.set("_last_two_pos", {"left": Vector2(200, 60), "right": Vector2(300, 70)})
	router.call("reset_runtime")
	rel = _btn_releases()
	check_eq(rel.size(), 1, "A3：_right_stroking 残留 → 合成抬起恰一次")
	if rel.size() == 1:
		check(bool(rel[0][3]) == true, "A3：右取消支抬起 ctrl=true（Ctrl 抬起配对断言）")
		check_eq((rel[0][1] as Vector2), Vector2(300, 70), "A3：抬起位=右 two 记位")
	mock.calls.clear()
	# A4 无按下标志 → 零合成事件
	router.call("reset_runtime")
	check_eq(_btn_releases().size(), 0, "A4：无按下标志 reset_runtime → 零合成抬起")
	# A5 三类并存 → 按侧去重恰两次（左支 armed∨stroking 一次、右支 cancel ctrl 一次——
	# 物理鼠标单键语义：每侧恰一次抬起，ctrl=true 仅右取消支）。
	# 审查 P3-A 红绿漂移留痕：红测期本断言期望 3（三类标志各派发一次的直读口径），绿期按
	# 物理单键语义细化为「按侧去重恰 2」——armed 与 stroking 同属左键一个虚拟按下域、cancel
	# 与 armed 同属右键一个虚拟按下域，双发抬起会伪造一次无按下的抬起（假点击），故收窄。
	router.set("_menu_click_armed", {"left": true, "right": true})
	router.set("_left_stroking", true)
	router.set("_right_stroking", true)
	router.call("reset_runtime")
	var rel5: Array = _btn_releases()
	check_eq(rel5.size(), 2, "A5：三类按下标志并存 → 按侧去重恰两次合成抬起")
	if rel5.size() == 2:
		var ctrl_cnt: int = 0
		for c: Variant in rel5:
			if bool(c[3]):
				ctrl_cnt += 1
		check_eq(ctrl_cnt, 1, "A5：恰一次 Ctrl 抬起（右取消支）")

	# ---- 段 E（P3-2c）：reset_runtime 清三键缓存 ----
	router.set("_last_cursor_pos", {"left": Vector2(1, 2)})
	router.set("_last_two_pos", {"left": Vector2(3, 4)})
	router.set("_last_cursor_at", {"left": 123.0})
	router.call("reset_runtime")
	check_eq((router.get("_last_cursor_pos") as Dictionary).size(), 0,
		"E：reset_runtime 清 _last_cursor_pos")
	check_eq((router.get("_last_two_pos") as Dictionary).size(), 0,
		"E：reset_runtime 清 _last_two_pos")
	check_eq((router.get("_last_cursor_at") as Dictionary).size(), 0,
		"E：reset_runtime 清 _last_cursor_at")

	# ---- 段 D（P3-2b）：单击抬起统一取按下位 ----
	# 时序：cursor@P1 → two×2@P1（armed，按下@P1）→ two 持帧@P2（移动）→ cursor@P3（two_up 抬起）
	# 修复前：抬起位=_content(two_up 帧 tip)=P2/P3 系（缺陷）；修复后：抬起位=按下位 P1。
	var vp_sz: Vector2 = get_root().get_visible_rect().size
	var _gm_c: Dictionary = load("res://scripts/gesture_map.gd").get_script_constant_map()
	var gain: float = float(_gm_c.get("CURSOR_GAIN", 3.5))
	## 批次 AC §4.4-2：逆映射纵向基准上移 c_y=(0.5+m)/g（与 apply_cursor_gain 互逆）。
	var cy_w: float = (0.5 + float(_gm_c.get("CURSOR_OVERSHOOT", 0.15))) / gain
	var inv := func(n: Vector2) -> Vector2:
		return (n - Vector2(0.5, 0.5)) / gain + Vector2(0.5, cy_w)
	var p1: Vector2 = Vector2(300.0, 300.0)
	var p2: Vector2 = p1 + Vector2(80.0, 0.0)
	var p3: Vector2 = p1 + Vector2(150.0, 20.0)
	# MAIN_MENU 态 → zone none → click_zone true（armed 单击路径可达）
	game.set("_state", game.State.MAIN_MENU)
	router.call("reset_runtime")
	var ts := 100.0
	router.feed({"left": _hand(0.9, F_CURSOR, 5.0, true, "Left", inv.call(p1 / vp_sz), ts),
		"right": null, "timestamp": 0.0})
	router.feed({"left": _hand(0.9, F_TWO, 5.0, true, "Left", inv.call(p1 / vp_sz), ts),
		"right": null, "timestamp": 0.0})
	router.feed({"left": _hand(0.9, F_TWO, 5.0, true, "Left", inv.call(p1 / vp_sz), ts),
		"right": null, "timestamp": 0.0})
	var downs: Array = []
	for c: Variant in mock.calls:
		if c[0] == "btn" and bool(c[2]):
			downs.append(c)
	check_eq(downs.size(), 1, "D 前置：armed 单击按下恰一次")
	if downs.size() == 1:
		check(((downs[0][1] as Vector2) - p1).length() < 0.5, "D 前置：按下位=P1")
	mock.calls.clear()
	# two 语义内移指（two_move 不产生 armed 事件）再收中指（two_up 位=末帧 tip）
	router.feed({"left": _hand(0.9, F_TWO, 5.0, true, "Left", inv.call(p2 / vp_sz), ts),
		"right": null, "timestamp": 0.0})
	router.feed({"left": _hand(0.9, F_CURSOR, 5.0, true, "Left", inv.call(p3 / vp_sz), ts),
		"right": null, "timestamp": 0.0})
	var ups: Array = _btn_releases()
	check_eq(ups.size(), 1, "D：armed 抬起恰一次")
	if ups.size() == 1:
		check(((ups[0][1] as Vector2) - p1).length() < 0.5,
			"D：抬起位=按下位 P1（旧码=P2/P3 抬起帧位，缺陷）")
	mock.calls.clear()
	router.call("reset_runtime")

	# ---- 段 C（P1-1 + 批次 Y Y-A22）：退出确认全分支 tracker 复位 ----
	# 批次 Y（Y-A22，spec §2-㉒）：SETTLE/BOOT 静默分支并入复位断言——旧码 _done 残留使该两态
	# 手势退出一次失灵（红测：修复前 C/SETTLE、C/BOOT 第二轮断言红灯）。
	var confirmed_cnt: Array = []
	router.exit_confirmed.connect(func() -> void: confirmed_cnt.append(true))
	game.close_overlay()   # 清覆盖层态（走覆盖层分支会分流）
	game.set("_overlay_instance", null)
	var t5: Variant = router.get("_tracker")
	for st_name: String in ["MAIN_MENU", "CATALOG", "OPENING_MOVIE", "TALK", "LEVEL", "SETTLE", "BOOT"]:
		var st_val: int = int(game.State.get(st_name))
		game.set("_state", st_val)
		game.set("_current_scene", null)   # 只验 reset 语义，不触场景转发
		t5.notify_flip(1000.0)
		t5.notify_flip(1000.2)
		t5.notify_flip(1000.4)
		t5.notify_flip(1000.6)
		check_eq((confirmed_cnt as Array).size(), 1, "C/%s：四翻 → exit_confirmed" % st_name)
		check(bool(t5.get("_done")) == false, "C/%s：确认后 _tracker._done 已复位（P1-1 全分支 reset）" % st_name)
		confirmed_cnt.clear()
		# 再触发可达：新一轮四翻再次确认
		t5.notify_flip(2000.0)
		t5.notify_flip(2000.2)
		t5.notify_flip(2000.4)
		t5.notify_flip(2000.6)
		check_eq((confirmed_cnt as Array).size(), 1, "C/%s：确认后再次四翻可重新触发（该界面退出不再失灵）" % st_name)
		confirmed_cnt.clear()
	router.call("reset_runtime")

	# ---- 段 B（P1-8b）：tracker.reset() 补发 countdown_cancelled("reset") ----
	var t: Variant = load("res://scripts/gesture_exit_tracker.gd").new()
	var started: Array = []
	var cancelled: Array = []
	t.countdown_started.connect(func(_r: int) -> void: started.append(true))
	t.countdown_cancelled.connect(func(reason: String) -> void: cancelled.append(reason))
	t.notify_flip(0.0)
	t.tick(0.7, true)
	check_eq((started as Array).size(), 1, "B 前置：倒数已启动")
	t.reset()
	check_eq((cancelled as Array).size(), 1, "B：倒数中 reset → countdown_cancelled 恰一次")
	if (cancelled as Array).size() == 1:
		check_eq(String(cancelled[0]), "reset", "B：取消原因=reset")
	check(bool(t.get("_done")) == false and int(t.get("_remaining")) == 0,
		"B：reset 后状态清零（再次倒数可达）")
	cancelled.clear()
	t.reset()
	# 修复批 P3（2026-09-26）等价改写：旧断言「未在倒数时 reset 亦补发」随「仅活跃态 emit」
	# 拍板推翻——无条件补发在禁用期 blocked 每包 reset 下打出 cancelled 信号 N 连发
	#（main 侧幂等 hide 虽无害，信号风暴属病灶；倒数中恰一次由上一条断言锁定）。
	check_eq((cancelled as Array).size(), 0,
		"B：未在倒数时 reset 不再补发（修复批 P3：仅倒数活跃态 emit，防 blocked 每包信号风暴）")
	t = null   # RefCounted 置空释放（free 对 RefCounted 报错且中止 _initialize 挂死占端口——2026-09-21 实证）
	# router 链路：reset_runtime → tracker.reset → router.countdown_cancelled("reset") 转发
	var r_cancelled: Array = []
	router.countdown_cancelled.connect(func(reason: String) -> void: r_cancelled.append(reason))
	router.get("_tracker").notify_flip(0.0)
	router.call("reset_runtime")
	check_eq((r_cancelled as Array).size(), 1, "B：router.reset_runtime → countdown_cancelled 转发恰一次")
	if (r_cancelled as Array).size() == 1:
		check_eq(String(r_cancelled[0]), "reset", "B：router 转发原因=reset")

	# ---- 段 F（P3-2d/e）：gesture_map 单翻落空与脏 feed ----
	var m: Variant = load("res://scripts/gesture_map.gd").new()
	# F1 回归护栏：单手翻（另一手全程离场）→ 1.2s 窗口闭合 → 左 undo（既有特性不得被 P3-2d 破坏；
	# Z5 配对窗 0.8→1.2 平移——0.867s 处新窗未闭合=中途帧红锁，1.267s 才解算）
	m.reset()
	var flips: Array = []
	flips.append_array(_feed_map_left(m, F_FOUR, 0.9, 10.0, true, 0.2, Vector2(0.3, 0.4), 20.0))
	flips.append_array(_feed_map_left(m, F_FOUR, 0.9, 10.0, true, 0.2, Vector2(0.3, 0.4), 20.033))
	flips.append_array(_feed_map_left(m, F_FOUR, 0.9, 130.0, true, 0.2, Vector2(0.3, 0.4), 20.10))
	flips.append_array(_feed_map_left(m, F_FOUR, 0.9, 130.0, true, 0.2, Vector2(0.3, 0.4), 20.133))
	var flips_mid: Array = _feed_map_left(m, F_FOLD, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 21.0)
	check(not _map_has(flips_mid, "undo"), "F1 中途帧：0.867s<1.2s 窗未闭合 → 未解算（Z5 窗放宽红锁）")
	flips.append_array(flips_mid)
	flips.append_array(_feed_map_left(m, F_FOLD, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 21.40))
	check(_map_has(flips, "undo"), "F1 回归：单手翻（另一手全程离场）1.2s 窗口闭合 → 左 undo（既有特性保持；Z5 配对窗 0.8→1.2 平移留痕）")
	# F2：双手场景「落空配对」丢弃——另一手（先在场）离场 → pending flip 丢弃 → 零撤销
	# （P3-2d 拍板语义；批次 AD 审查回修 P1-3 前本段为**空转假绿**：序列止于 30.70 <
	#  at+SAME_WINDOW_SEC(1.2)=31.333，即使 _teardown_side 完全不判（pending 原样存活），
	#  窗未闭合时 _resolve_pending_flip 也不会发 undo，`not _map_has(f2,"undo")` 恒真。
	#  现将喂帧**延伸到超窗**，并补 _pending_flip 直接状态断言，使其成为真守卫：
	#  若有人删除/放宽「非翻转侧离场 → 清空」判据（=AD 曾犯的越 spec 放宽），超窗解算
	#  立即发出 undo → 本段判红。）
	m.reset()
	var f2: Array = []
	# 右手先在场（cursor 态）
	f2.append_array(_feed_map_both(m, F_FOUR, F_CURSOR, 0.9, 10.0, true, 0.2, Vector2(0.3, 0.4), Vector2(0.7, 0.4), 30.0))
	f2.append_array(_feed_map_left(m, F_FOUR, 0.9, 10.0, true, 0.2, Vector2(0.3, 0.4), 30.033))
	f2.append_array(_feed_map_left(m, F_FOUR, 0.9, 130.0, true, 0.2, Vector2(0.3, 0.4), 30.10))
	f2.append_array(_feed_map_left(m, F_FOUR, 0.9, 130.0, true, 0.2, Vector2(0.3, 0.4), 30.133))   # 左翻（pending，other_recent=true）
	check(bool(m.get("_pending_flip").get("other_recent", false)),
		"F2 前置：左翻时右手 0.133s 前曾在场 → other_recent=true（双手落空配对判据成立）")
	# 右手离场（另一手 teardown；离场前曾在场）
	f2.append_array(_feed_map_left(m, F_FOLD, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 30.30))
	check_eq((m.get("_pending_flip") as Dictionary).is_empty(), true,
		"F2：非翻转侧（右手）离场 → 落空配对当场丢弃（_pending_flip 清空，窗内即清不待到期）")
	f2.append_array(_feed_map_frame(m, {}, 30.35))
	f2.append_array(_feed_map_left(m, F_FOLD, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 30.70))
	check(not _map_has(f2, "undo"), "F2 窗内：另一手在场后离场 → 单翻落空丢弃 → 零撤销（P3-2d 主断言）")
	# 超窗延伸（31.40 > at 30.133 + SAME_WINDOW_SEC 1.2 = 31.333）：撤销意图已被丢弃，
	# 窗口到期也不得解算——本帧是断言的**真判据**（旧空转版只测窗内恒真帧）。
	var f2_over: Array = _feed_map_left(m, F_FOLD, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 31.40)
	f2.append_array(f2_over)
	check(not _map_has(f2_over, "undo"),
		"F2 超窗：at+1.2s 到期解算仍零撤销（落空配对丢弃为真语义；若 _teardown 清空判据被删则本断言必红）")
	# F3：翻转手自身离场（**单手场景**：对侧从未在场 → other_recent=false）
	# ——批次 AD 审查回修 P1-3 改写：本段旧断言「翻转手自身离场 → pending 清 → 零撤销」
	#  系旧口径（W/AC：翻转手在窗内离场需「倒数中 or 对侧在场」才保留，单手两条件皆假
	#  → 清空），且序列止于 40.70 < at+1.2=41.333，**窗未闭合时任何实现都恒真=空转假绿**。
	#  spec §4.3.3 拍板反置该旧值：单手翻转（other_recent=false）窗内**严禁清空**，
	#  侧立丢帧由保留窗兜住，超窗后由 _resolve_pending_flip 稳定解算 → **undo 可达**。
	#  现按新口径三段验证：①窗内丢帧当帧不清空（状态断言）②窗内不抢跑解算③超窗 undo 可达。
	#  旧值留痕：`check(not _map_has(f3, "undo"), "F3：翻转手自身离场 → pending 清 → 零撤销（清对应侧）")`。
	m.reset()
	var f3: Array = []
	f3.append_array(_feed_map_left(m, F_FOUR, 0.9, 10.0, true, 0.2, Vector2(0.3, 0.4), 40.0))
	f3.append_array(_feed_map_left(m, F_FOUR, 0.9, 10.0, true, 0.2, Vector2(0.3, 0.4), 40.033))
	f3.append_array(_feed_map_left(m, F_FOUR, 0.9, 130.0, true, 0.2, Vector2(0.3, 0.4), 40.10))
	f3.append_array(_feed_map_left(m, F_FOUR, 0.9, 130.0, true, 0.2, Vector2(0.3, 0.4), 40.133))
	check_eq(bool(m.get("_pending_flip").get("other_recent", true)), false,
		"F3 前置：单手翻（对侧从未在场）→ other_recent=false（§4.3.3 保护态判据）")
	var f3_drop: Array = _feed_map_frame(m, {}, 40.30)   # 左手离场（翻转手自身；窗内 0.167s<1.2s）
	f3.append_array(f3_drop)
	check_eq((m.get("_pending_flip") as Dictionary).is_empty(), false,
		"F3 窗内：翻转手自身侧立丢帧 → §4.3.3 保护，_pending_flip **不清空**（旧「清对应侧」值随 §4.3.3 反置留痕）")
	check(not _map_has(f3_drop, "undo"),
		"F3 窗内：丢帧当帧不抢跑解算（保护期语义=不清空也不提前发 undo）")
	f3.append_array(_feed_map_left(m, F_FOLD, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 40.70))
	# 超窗回归（41.40 > at 40.133 + SAME_WINDOW_SEC 1.2 = 41.333）→ 到期稳定解算 undo
	var f3_over: Array = _feed_map_left(m, F_FOLD, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 41.40)
	f3.append_array(f3_over)
	check(_map_has(f3_over, "undo"),
		"F3 超窗：单手翻转侧立丢帧 → 窗口自然到期解算 undo **可达**（§4.3.3 根治「撤销 100% 丢失」）")
	# F4/F6（P3-2e）：同侧连续翻转刷新窗口起点 → 恰一次撤销且时点随刷新后移
	m.reset()
	m.call("_on_flip_raw", "left", 50.0)
	m.call("_on_flip_raw", "left", 50.4)   # 同侧连翻：刷新窗口起点（旧码丢弃）
	var r46: Array = m.call("_resolve_pending_flip", 50.9)   # 旧起点 50.0+0.8 已过 → 若未刷新此刻已发
	check(_map_has(r46, "undo") == false, "F4：同侧连翻刷新起点 → 旧起点到期不发")
	r46 = m.call("_resolve_pending_flip", 51.7)   # 50.4+1.2=51.6 已过（Z5 窗 0.8→1.2 平移）→ 恰一次
	check(_map_has(r46, "undo"), "F4：新起点到期 → 恰一次撤销（Z5 配对窗 1.2s）")
	r46 = m.call("_resolve_pending_flip", 52.4)
	check(_map_has(r46, "undo") == false, "F4：不重复撤销")
	# F5（P3-2e）：fingers 短数组/脏值 feed 不炸
	m.reset()
	var f5: Variant = _feed_map_frame(m, _dirty_hand(0.9, [0.1, 0.9], 60.0), 60.0)   # 短于 5
	var f5b: Array = _feed_map_frame(m, _dirty_hand(0.9, [0.1, "x", 0.9, null, 0.1], 60.033), 60.033)
	var f5c: Array = _feed_map_frame(m, _dirty_hand(0.9, [], 60.066), 60.066)
	check(f5 is Array and f5b is Array and f5c is Array,
		"F5：短数组/脏值 fingers feed 不炸且返回意图数组（坑⑦⑪族防御）")
	# 连续翻转仅一次撤销（feed 域端到端）：冷却期内第二次翻不可能，经直接注入域已由 F4 覆盖

	# ---- 段 G（P2-6）：键鼠互斥门 ----
	var press_ev := InputEventMouseButton.new()
	press_ev.button_index = MOUSE_BUTTON_LEFT
	press_ev.pressed = true
	press_ev.position = Vector2(10, 10)
	Input.parse_input_event(press_ev)
	Input.flush_buffered_events()
	check(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "G 前置：物理左键按下态注入成功")
	mock.calls.clear()
	router.call("_push_btn", Vector2(400, 400), true, false)
	var g_dropped: int = 0
	for c: Variant in mock.calls:
		if c[0] == "btn":
			g_dropped += 1
	check_eq(g_dropped, 0, "G：物理按下期间合成按下被丢弃（P2-6 互斥门）")
	var rel_ev := InputEventMouseButton.new()
	rel_ev.button_index = MOUSE_BUTTON_LEFT
	rel_ev.pressed = false
	rel_ev.position = Vector2(10, 10)
	Input.parse_input_event(rel_ev)
	Input.flush_buffered_events()
	check(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "G 前置：物理左键释放")
	mock.calls.clear()
	router.call("_push_btn", Vector2(400, 400), true, false)
	g_dropped = 0
	for c: Variant in mock.calls:
		if c[0] == "btn":
			g_dropped += 1
	check_eq(g_dropped, 1, "G：物理释放后合成事件恢复派发")

	# ---- 段 H（N6）：骨架变细常量 ----
	var sk: Script = load("res://scenes/shared/camera_skeleton.gd")
	var cmap: Dictionary = sk.get_script_constant_map()
	check(is_equal_approx(float(cmap.get("SKELETON_LINE_W", -1.0)), 1.2), "H：SKELETON_LINE_W=1.2（N6 变细起步档）")
	check(is_equal_approx(float(cmap.get("SKELETON_TIP_R", -1.0)), 4.0), "H：SKELETON_TIP_R=4.0")
	check(is_equal_approx(float(cmap.get("SKELETON_JOINT_R", -1.0)), 2.5), "H：SKELETON_JOINT_R=2.5")

	# ---- 段 I（批次 Y 扫描回修 P2-4）：桥 UNAVAILABLE 边沿 → 语义层全量复位 ----
	# 缺陷：python 判死期无帧可达，复位仅发生在「帧到达而桥非 READY」（feed 守卫链）——
	# 重拉后首包 id 复位 "L0"/"R0" 与残留 hand_id 相同 → gesture_map id 断链清态永不触发，
	# 新物理手继承旧 zooming/flip 累计态。修复：Router 订阅桥 load_state_changed，
	# UNAVAILABLE 边沿（判死/断流/重拉失败）走 reset_runtime（幂等，S16 同款全量清）。
	bridge._set_state(1)   # READY（重拉成功语义）
	game.set("_state", game.State.MAIN_MENU)   # zone none（沿用段 D 前置）
	router.call("reset_runtime")
	var m2: Variant = router.get("_map")
	# 批次 AC 4A（spec §4.6-3）：生产语义改**双手协同推拉/间距缩放**，单手掌推拉通道默认关。
	# 本段构造「zooming 残留态」经兼容开关开启历史单手掌通道（等价改写留痕：断言行与数量不变，
	# 仅加一行开关；本段被测对象=UNAVAILABLE 边沿全量清态，与缩放通道选择正交）。
	m2.call("set_single_hand_zoom_enabled", true)
	# 残留态构造（经 router.feed 真链路）：左手 id="L0" palm 确认 2 帧 → 推拉 3 帧（palm_size 0.2→0.5）
	# → zooming=true。
	# 修复批 P3（2026-09-26）夹具等价改写：zoom_begin 现清本侧 flip_locked（缩放意图下翻转前置
	# 作废，防收掌后残余 1.0s 窗误发 flip——test_fix_gesture_zoom_flip 红测锁定）——自然 feed
	# 不再产出「zooming+flip_locked 双残留」并存态。本段被测对象=UNAVAILABLE 边沿全量清态
	#（与 zoom_begin 清锁正交），flip_locked 改直接注入构造残留：断言行语义与数量不变。
	for k9: int in 2:
		router.feed({"left": _hand_id(0.9, F_FOUR, 5.0, true, "Left", Vector2(0.5, 0.5), "L0", 0.2),
			"right": null, "timestamp": 0.0})
	for k9: int in 3:
		router.feed({"left": _hand_id(0.9, F_FOUR, 5.0, true, "Left", Vector2(0.5, 0.5), "L0", 0.5),
			"right": null, "timestamp": 0.0})
	var side_l: Dictionary = (m2.get("_side") as Dictionary).get("left", {})
	check(bool(side_l.get("zooming", false)), "I 前置：掌态推拉建立 zooming=true（残留态）")
	check_eq(String(side_l.get("hand_id", "")), "L0", "I 前置：残留 hand_id=L0")
	side_l["flip_locked"] = true   # 注入构造（自然路径随修复批 P3 于 zoom_begin 清锁）
	check(bool(side_l.get("flip_locked", false)), "I 前置：翻转前置锁残留 flip_locked=true")
	bridge._set_state(2)   # python 判死 → UNAVAILABLE 边沿（修复后此处即全量复位）
	side_l = (m2.get("_side") as Dictionary).get("left", {})
	check(not bool(side_l.get("zooming", false)), "P2-4：UNAVAILABLE 边沿 → zooming 残留清零（旧口径无帧可达不复位）")
	check(not bool(side_l.get("flip_locked", false)), "P2-4：UNAVAILABLE 边沿 → flip 锁残留清零")
	bridge._set_state(1)   # 重拉成功 → READY
	router.feed({"left": _hand_id(0.9, F_FOUR, 5.0, true, "Left", Vector2(0.5, 0.5), "L0", 0.5),
		"right": null, "timestamp": 0.0})   # 首包 id="L0"（与残留同名）
	side_l = (m2.get("_side") as Dictionary).get("left", {})
	check(not bool(side_l.get("zooming", false)), "P2-4：重拉后首包 id 复用不继承 zooming（新物理手从初值起算）")
	check(not bool(side_l.get("flip_locked", false)), "P2-4：重拉后首包不继承 flip 锁")
	check_eq(String(side_l.get("hand_id", "")), "L0", "P2-4：新首包 hand_id 正常登记")

	# 收尾卫生：断开新实例挂到 autoload 的连接（防 freed 回调）
	var bridge2: Node = get_root().get_node("GestureBridge")
	if bridge2 != null and bridge2.gesture_state_received.is_connected(router.feed):
		bridge2.gesture_state_received.disconnect(router.feed)
	if bridge2 != null and bridge2.load_state_changed.is_connected(router._on_bridge_state_for_reset):
		bridge2.load_state_changed.disconnect(router._on_bridge_state_for_reset)
	router.queue_free()
	mock.queue_free()
	await process_frame
	finish()

func _dirty_hand(conf: float, fingers_v: Variant, ts: float) -> Dictionary:
	var lm: Array = []
	for i: int in 21:
		lm.append([0.5, 0.5, 0.0])
	lm[8] = [0.4, 0.4, 0.0]
	return {"gesture": "", "confidence": conf, "fingers": fingers_v,
		"hand_rotation_x": 5.0, "handedness": "Left", "landmarks": lm,
		"is_detected": true, "timestamp": ts, "palm_size": 0.2}

## 段 I（P2-4）：带 per-hand 稳定 id 的手 dict（_hand 同构 + id 键，Y1 契约 §3.1）
func _hand_id(conf: float, fingers: Array, roll: float, facing: bool, label: String,
		tip: Vector2, id: String, ps: float) -> Dictionary:
	var h: Dictionary = _hand(conf, fingers, roll, facing, label, tip, 0.0)
	h["id"] = id
	h["palm_size"] = ps
	return h

func _feed_map_left(m: Variant, fingers: Array, conf: float, roll: float, facing: bool,
		ps: float, tip: Vector2, now: float) -> Array:
	return m.feed_frame(_hand(conf, fingers, roll, facing, "Left", tip, now), {}, now)

func _feed_map_both(m: Variant, lf: Array, rf: Array, conf: float, roll: float, facing: bool,
		ps: float, ltip: Vector2, rtip: Vector2, now: float) -> Array:
	return m.feed_frame(_hand(conf, lf, roll, facing, "Left", ltip, now),
		_hand(conf, rf, roll, facing, "Right", rtip, now), now)

func _feed_map_frame(m: Variant, left_v: Variant, now: float) -> Array:
	return m.feed_frame(left_v, {}, now)

func _map_has(intents: Array, type: String) -> bool:
	for it: Variant in intents:
		if typeof(it) == TYPE_DICTIONARY and String((it as Dictionary).get("type", "")) == type:
			return true
	return false
