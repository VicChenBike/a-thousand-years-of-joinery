extends "res://tests/test_base.gd"
## 批次 AA 终审（review 专用，不入回归分母）：方向1b 手势长跑量化 + 方向4 交叉验证。
## Phase1 Router 6000 帧 churn（MAIN_MENU 区 armed 单击 ledger 平衡）
## Phase2 Map 级右掌 dwell（恰一次 clear / 位移取消）
## Phase3 Map 级双手 two 对接仲裁（join 恰一次 / 退出补发单击）
## Phase4 W7-3 三条件看门狗闭合 + 强制抬起序列
## Phase5 W7-2 armed/jitter/物理按压 motion 冻结
## 尾态：全部台账/标志归零 + Map 状态字典键集稳定。

const ROUTER_GD := "res://autoload/gesture_router.gd"
const MAP_GD := "res://scripts/gesture_map.gd"

class SpyLayer extends CanvasLayer:
	var motion_n := 0
	var btn_down_n := 0
	var btn_up_n := 0
	var wheel_n := 0
	var last_release_pos := Vector2.INF
	func push(ev: Variant) -> void:
		if ev is InputEventMouseMotion:
			motion_n += 1
		elif ev is InputEventMouseButton:
			if ev.pressed:
				btn_down_n += 1
			else:
				btn_up_n += 1
				last_release_pos = ev.position
		elif ev is InputEventMouseButton and ev.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			wheel_n += 1
	func synth_motion(pos: Vector2) -> InputEventMouseMotion:
		var ev := InputEventMouseMotion.new()
		ev.position = pos
		return ev
	func synth_button(pos: Vector2, pressed: bool, ctrl: bool) -> InputEventMouseButton:
		var ev := InputEventMouseButton.new()
		ev.position = pos
		ev.pressed = pressed
		ev.ctrl_pressed = ctrl
		ev.button_index = MOUSE_BUTTON_LEFT
		return ev
	func synth_wheel(pos: Vector2, dir: int) -> InputEventMouseButton:
		var ev := InputEventMouseButton.new()
		ev.position = pos
		ev.button_index = MOUSE_BUTTON_WHEEL_UP if dir > 0 else MOUSE_BUTTON_WHEEL_DOWN
		return ev
	func show_cursor(_side: String, _pos: Vector2) -> void:
		pass

var _now := 100.0

func _hand(tip: Vector2, fingers: Array, conf := 0.9, roll := 5.0, palm := 0.2) -> Dictionary:
	return {"gesture": "", "gesture_id": 0, "confidence": conf,
		"hand_x": tip.x, "hand_y": tip.y, "hand_z": 0.0,
		"hand_rotation_x": roll, "hand_rotation_y": 0.0, "hand_rotation_z": 0.0,
		"pinch_distance": 0.5, "hand_index": 0, "handedness": "Left", "fps": 30.0,
		"is_detected": true, "timestamp": _now, "palm_size": palm, "fingers": fingers,
		"tip_x": tip.x, "tip_y": tip.y}

func _feed(router: Node, left: Dictionary, right: Dictionary, dt := 0.0167) -> void:
	_now += dt
	router.call("feed", {"left": left, "right": right, "timestamp": _now})

func _initialize() -> void:
	await process_frame
	await process_frame
	var bridge: Node = get_root().get_node("GestureBridge")
	check(bridge != null, "前置：/root/GestureBridge 在位")
	if bridge == null:
		finish()
		return
	bridge.call("_set_state", 1)   # READY（test_aa_pointer_stuck 同口径）
	var router: Node = load(ROUTER_GD).new()
	root.add_child(router)
	await process_frame
	bridge.call("_set_state", 1)
	router.call("_setup")
	var spy := SpyLayer.new()
	router.call("set_cursor_layer", spy)
	# 内存内强制手势开关为 true（磁盘存档可能为 false——窗口走查红线补丁），不落盘不转发
	var save_node: Node = get_root().get_node_or_null("SaveManager")
	if save_node != null:
		(save_node.call("get_settings") as Dictionary)["gesture_input"] = true
	var game: Node = get_root().get_node_or_null("Game")
	if game != null:
		game.call("goto_state", 1, {})   # MAIN_MENU（枚举序 BOOT/MM/MOVIE/TALK/LEVEL/SETTLE/CATALOG）

	# ---------- Phase 1：6000 帧 armed 单击 churn ----------
	var frames := 0
	var click_cycles := 0
	for i: int in 1000:
		# 左手光标 2 帧（新鲜度）
		_feed(router, _hand(Vector2(0.5, 0.5), [0.1, 0.9, 0.1, 0.1, 0.1]), {})
		_feed(router, _hand(Vector2(0.502, 0.5), [0.1, 0.9, 0.1, 0.1, 0.1]), {})
		# 左手 two 确认 2 帧 → armed 按下
		_feed(router, _hand(Vector2(0.502, 0.5), [0.1, 0.9, 0.9, 0.1, 0.1]), {})
		_feed(router, _hand(Vector2(0.502, 0.5), [0.1, 0.9, 0.9, 0.1, 0.1]), {})
		if bool(router.get("_synth_left_held")):
			click_cycles += 1
		# 按住 2 帧
		_feed(router, _hand(Vector2(0.502, 0.5), [0.1, 0.9, 0.9, 0.1, 0.1]), {})
		_feed(router, _hand(Vector2(0.503, 0.501), [0.1, 0.9, 0.9, 0.1, 0.1]), {})
		# 收中指 → two_up 抬起
		_feed(router, _hand(Vector2(0.503, 0.501), [0.1, 0.9, 0.1, 0.1, 0.1]), {})
		frames += 6
	check_eq(click_cycles, 1000, "1000 轮单击每轮均有合成按下（ledger 置真）")
	check_eq(spy.btn_down_n, 1000, "spy 合成按下次数=1000")
	check_eq(spy.btn_up_n, 1000, "spy 合成抬起次数=1000（零丢失）")
	check_eq(bool(router.get("_synth_left_held")), false, "尾态：_synth_left_held 归零")
	check_eq(bool(router.get("_menu_click_armed").get("left", true)), false, "尾态：left armed 归零")
	check_eq(bool(router.get("_menu_click_armed").get("right", true)), false, "尾态：right armed 归零")
	check_eq(bool(router.get("_left_stroking")), false, "尾态：_left_stroking 归零")

	# ---------- Phase 4：W7-3 三条件看门狗闭合 ----------
	var down_before := spy.btn_down_n
	var up_before := spy.btn_up_n
	router.call("_push_btn", Vector2(300, 300), true, false)   # 合成按下（台账真）
	check_eq(bool(router.get("_synth_left_held")), true, "看门狗前置：台账真")
	for i: int in 40:
		router.call("_process", 0.0167)   # 无按压标志/无物理按压 → 30 帧后强制释放
	check_eq(bool(router.get("_synth_left_held")), false, "W7-3：看门狗补发抬起后台账归零")
	check_eq(spy.btn_down_n - down_before, 2, "强制序列=补按下+原按下（2 次 down）")
	check_eq(spy.btn_up_n - up_before, 1, "强制序列=恰 1 次抬起")
	check_eq(spy.motion_n > 0, true, "强制序列含屏外 motion（刷 pressuring_inside）")
	# 再跑 90 帧：台账已清 → 不再触发（无误触发）
	var up_before2 := spy.btn_up_n
	for i: int in 90:
		router.call("_process", 0.0167)
	check_eq(spy.btn_up_n - up_before2, 0, "台账清零后看门狗零误触发（90 帧零抬起）")

	# ---------- Phase 5：W7-2 armed 冻结 ----------
	var mo_before := spy.motion_n
	router.set("_menu_click_armed", {"left": true, "right": false})
	_feed(router, _hand(Vector2(0.51, 0.51), [0.1, 0.9, 0.1, 0.1, 0.1]), {})
	check_eq(spy.motion_n, mo_before, "armed 期 cursor_move 不推 synth_motion（冻结生效）")
	router.set("_menu_click_armed", {"left": false, "right": false})
	_feed(router, _hand(Vector2(0.51, 0.51), [0.1, 0.9, 0.1, 0.1, 0.1]), {})
	check_eq(spy.motion_n, mo_before + 1, "解除 armed 后恢复推送")

	# ---------- Phase 2：Map 级右掌 dwell ----------
	var map: Variant = load(MAP_GD).new()
	var t := 1000.0
	var clear_n := 0
	var intents: Array = []
	for i: int in 80:   # 80 帧 @30fps ≈ 2.7s 静止
		t += 1.0 / 30.0
		intents = map.call("feed_frame", {}, _hand(Vector2(0.6, 0.6),
			[0.1, 0.9, 0.9, 0.9, 0.9], 0.9, 5.0, 0.3), t, false)
		for it_v: Variant in intents:
			if String((it_v as Dictionary).get("type", "")) == "clear":
				clear_n += 1
	check_eq(clear_n, 1, "W3-2：右掌静止 2.7s 恰一次 clear")
	# 横向平移 palm（下一段掌态）→ dwell 取消零 clear
	clear_n = 0
	var moved := false
	for i: int in 90:
		t += 1.0 / 30.0
		var tip := Vector2(0.6, 0.6) if i < 3 else Vector2(0.6 + 0.02 * i, 0.6)
		intents = map.call("feed_frame", {}, _hand(tip, [0.1, 0.9, 0.9, 0.9, 0.9], 0.9, 5.0, 0.3), t, false)
		for it_v: Variant in intents:
			if String((it_v as Dictionary).get("type", "")) == "clear":
				clear_n += 1
		if i > 10:
			moved = true
	check(moved, "平移段前置：tip 确已移动")
	check_eq(clear_n, 0, "W3 回修 P2-2：横向平移取消 dwell（零 clear）")
	# 左掌静止零 clear（手别门）
	clear_n = 0
	for i: int in 80:
		t += 1.0 / 30.0
		intents = map.call("feed_frame", _hand(Vector2(0.6, 0.6), [0.1, 0.9, 0.9, 0.9, 0.9], 0.9, 5.0, 0.3), {}, t, false)
		for it_v: Variant in intents:
			if String((it_v as Dictionary).get("type", "")) == "clear":
				clear_n += 1
	check_eq(clear_n, 0, "W3-2 手别门：左掌静止零 clear")

	# ---------- Phase 3：Map 级双手 two 对接仲裁 ----------
	map.call("reset")
	t += 10.0
	var join_n := 0
	var two_down_n := 0
	for i: int in 20:   # 双手同帧 two 0.6s
		t += 1.0 / 30.0
		intents = map.call("feed_frame",
			_hand(Vector2(0.4, 0.5), [0.1, 0.9, 0.9, 0.1, 0.1]),
			_hand(Vector2(0.6, 0.5), [0.1, 0.9, 0.9, 0.1, 0.1]), t, false)
		for it_v: Variant in intents:
			var ty := String((it_v as Dictionary).get("type", ""))
			if ty == "join":
				join_n += 1
			elif ty == "two_down":
				two_down_n += 1
	check_eq(join_n, 1, "W3-4：双手 two 恰一次 join（latch）")
	check_eq(two_down_n, 0, "W3-4：配对期两侧 two_down 被抑制")
	# 配对退出后 pending 已被 join 消费 → 不应补发单击（规格①：join 承接即作废两侧左键）
	two_down_n = 0
	for i: int in 6:
		t += 1.0 / 30.0
		intents = map.call("feed_frame", {}, _hand(Vector2(0.6, 0.5), [0.1, 0.9, 0.9, 0.1, 0.1]), t, false)
		for it_v: Variant in intents:
			if String((it_v as Dictionary).get("type", "")) == "two_down":
				two_down_n += 1
	check_eq(two_down_n, 0, "W3-4：join 承接后配对退出零补发（单击已被对接消费）")
	# 规格②场景：右手 two 在对侧【确认中】被挂起 → 对侧当帧改光标（确认破裂）→ 同帧补发单击
	map.call("reset")
	two_down_n = 0
	t += 10.0
	for i: int in 2:   # 帧1：双手 two 同入确认；帧2：左手改光标、右手第二确认帧提交
		t += 1.0 / 30.0
		var l_hand := _hand(Vector2(0.4, 0.5), [0.1, 0.9, 0.9, 0.1, 0.1]) if i == 0 			else _hand(Vector2(0.4, 0.5), [0.1, 0.9, 0.1, 0.1, 0.1])
		intents = map.call("feed_frame", l_hand,
			_hand(Vector2(0.6, 0.5), [0.1, 0.9, 0.9, 0.1, 0.1]), t, false)
		for it_v: Variant in intents:
			if String((it_v as Dictionary).get("type", "")) == "two_down":
				two_down_n += 1
	check_eq(two_down_n >= 1, true, "W3-4：对侧确认破裂后单击同帧补发（two_down ≥1）")

	# ---------- 尾态：Map 状态字典键集稳定 ----------
	var st: Dictionary = map.get("_side")
	var keys_l: Array = (st.get("left", {}) as Dictionary).keys()
	keys_l.sort()
	check_eq(keys_l.has("semantic") and keys_l.has("dwell_fired") and keys_l.has("ext_hyst"),
		true, "Map 侧状态字典键集含 W1/W2/W3 新键（结构稳定）")
	check_eq(bool(map.get("_join_latched")), false, "尾态：_join_latched 复位")
	check_eq((map.get("_pending_flip") as Dictionary).is_empty(), true, "尾态：_pending_flip 空")

	finish()
