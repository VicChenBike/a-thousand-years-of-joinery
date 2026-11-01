extends "res://tests/test_base.gd"
## 批次 Y（Y-A11，spec §2-⑪）：光标恒跟随——二指笔画（选中/减选）、ORBIT 拖拽、掌态缩放期间
## 该手 cursor_move 持续发送（指尖 lm[8] 口径），光标不再冻结 2s 被 HIDE_AFTER_SEC 隐藏。
##   map 级：two 态/缩放态 cursor_move 意图派发断言（旧码两态零 cursor_move=红灯）；
##   router 级：真 cursor layer 光标圈可见+位置随二指帧更新+2s 内不隐藏（HIDE_AFTER_SEC 刷新链）。
## 无头零摄像头；user:// 零触碰。

const F_CURSOR := [0.1, 0.9, 0.1, 0.1, 0.1]
const F_TWO := [0.1, 0.9, 0.9, 0.1, 0.1]
const F_FOUR := [0.1, 0.9, 0.9, 0.9, 0.9]

func _hand(conf: float, fingers: Array, roll: float, facing: bool, label: String,
		ps: float, tip: Vector2, ts: float) -> Dictionary:
	var lm: Array = []
	for i: int in 21:
		lm.append([0.5, 0.5, 0.0])
	lm[0] = [tip.x - 0.05, tip.y + 0.20, 0.0]
	if (label == "Right") == facing:
		lm[5] = [lm[0][0] - 0.05, lm[0][1] - 0.06, 0.0]
		lm[17] = [lm[0][0] + 0.05, lm[0][1] - 0.05, 0.0]
	else:
		lm[5] = [lm[0][0] + 0.05, lm[0][1] - 0.06, 0.0]
		lm[17] = [lm[0][0] - 0.05, lm[0][1] - 0.05, 0.0]
	lm[8] = [tip.x, tip.y, 0.0]
	lm[9] = [lm[0][0], lm[0][1] - ps, 0.0]
	return {
		"gesture": "", "gesture_id": 0, "confidence": conf,
		"hand_x": tip.x, "hand_y": tip.y, "hand_z": 0.0,
		"hand_rotation_x": roll, "hand_rotation_y": 0.0, "hand_rotation_z": 0.0,
		"fingers": fingers, "pinch_distance": 0.5,
		"hand_index": 0 if label == "Left" else 1, "handedness": label,
		"landmarks": lm, "fps": 30.0, "is_detected": true,
		"timestamp": ts, "palm_size": ps,
	}

func _types(intents: Array) -> Array:
	var out: Array = []
	for it: Variant in intents:
		if typeof(it) == TYPE_DICTIONARY:
			out.append(String(it["type"]))
	return out

func _has(intents: Array, t: String) -> bool:
	return _types(intents).has(t)

func _initialize() -> void:
	print("== test_y_cursor_follow ==")
	var m: Variant = load("res://scripts/gesture_map.gd").new()
	# 批次 AC 4A（spec §4.6-3）：生产语义改**双手协同推拉/间距缩放**，单手掌推拉通道默认关。
	# 本文件段 2 的「掌态缩放期 cursor_move 恒派发」存量用例经兼容开关开启历史通道后照跑
	#（等价改写留痕：帧序与时序零变化，仅加一行开关；双手协同缩放新语义见 test_ac_batch4_gesture）。
	m.call("set_single_hand_zoom_enabled", true)

	# ---- 段 1（map 级）：二指笔画期 cursor_move 恒派发（左选中笔）----
	# 帧序注：two 经 2 帧确认——第 1 two 帧仅入暂存；第 2 two 帧=two_down+cursor_move（commit 帧同发）；
	# 第 3 two 帧=two_move+cursor_move。
	var a1: Array = m.feed_frame(_hand(0.9, F_CURSOR, 5.0, true, "Left", 0.2, Vector2(0.3, 0.4), 1.0), {}, 1.0)
	check(_has(a1, "cursor_move"), "段 1 前置：光标态 cursor_move 既有语义")
	m.feed_frame(_hand(0.9, F_TWO, 5.0, true, "Left", 0.2, Vector2(0.3, 0.4), 1.10), {}, 1.10)   # 暂存帧（零意图）
	var a3: Array = m.feed_frame(_hand(0.9, F_TWO, 5.0, true, "Left", 0.2, Vector2(0.35, 0.4), 1.133), {}, 1.133)
	check(_has(a3, "two_down") and _has(a3, "cursor_move"),
		"Y-A11：two_down 起笔帧同步 cursor_move（光标圈随按下降落；旧码两态零 cursor_move=红灯）")
	var a3b: Array = m.feed_frame(_hand(0.9, F_TWO, 5.0, true, "Left", 0.2, Vector2(0.38, 0.4), 1.166), {}, 1.166)
	check(_has(a3b, "two_move") and _has(a3b, "cursor_move"),
		"Y-A11：二指笔画移动帧 cursor_move 持续发送（旧码仅 two_move=光标冻结 2s 隐藏红灯）")
	var a4: Array = m.feed_frame(_hand(0.9, F_CURSOR, 5.0, true, "Left", 0.2, Vector2(0.38, 0.4), 1.20), {}, 1.20)
	check(_has(a4, "two_up") and _has(a4, "cursor_move"),
		"Y-A11：收中指抬起帧 cursor_move 同步（抬起位光标可见）")
	# 右手减选笔同口径（对称）
	m.reset()
	m.feed_frame({}, _hand(0.9, F_CURSOR, 5.0, true, "Right", 0.2, Vector2(0.7, 0.4), 2.0), 2.0)
	m.feed_frame({}, _hand(0.9, F_TWO, 5.0, true, "Right", 0.2, Vector2(0.7, 0.4), 2.10), 2.10)
	var b2: Array = m.feed_frame({}, _hand(0.9, F_TWO, 5.0, true, "Right", 0.2, Vector2(0.65, 0.4), 2.133), 2.133)
	check(_has(b2, "two_down") and _has(b2, "cursor_move"),
		"Y-A11：右手减选笔起笔帧 two_down+cursor_move（左右口径对称）")
	var b3: Array = m.feed_frame({}, _hand(0.9, F_TWO, 5.0, true, "Right", 0.2, Vector2(0.62, 0.4), 2.166), 2.166)
	check(_has(b3, "two_move") and _has(b3, "cursor_move"),
		"Y-A11：右手减选笔笔画期 cursor_move 恒派发（左右口径对称）")

	# ---- 段 2（map 级）：掌态缩放期 cursor_move 恒派发 ----
	# 帧序注：palm_ema α=0.3 平滑——批次 Z Z5 掌推阈值 15%→12% 后，0.30/0.38/0.46 三推帧即达成
	# streak（zoom_begin 提前至 0.46 帧；旧 0.50 帧锚随 15% 档退役留痕）。
	m.reset()
	m.feed_frame(_hand(0.9, F_FOUR, 5.0, true, "Left", 0.2, Vector2(0.3, 0.4), 10.0), {}, 10.0)
	m.feed_frame(_hand(0.9, F_FOUR, 5.0, true, "Left", 0.2, Vector2(0.3, 0.4), 10.033), {}, 10.033)   # 掌态确认+锁定
	m.feed_frame(_hand(0.9, F_FOUR, 5.0, true, "Left", 0.30, Vector2(0.3, 0.4), 10.20), {}, 10.20)
	m.feed_frame(_hand(0.9, F_FOUR, 5.0, true, "Left", 0.38, Vector2(0.3, 0.4), 10.233), {}, 10.233)
	var c2: Array = m.feed_frame(_hand(0.9, F_FOUR, 5.0, true, "Left", 0.46, Vector2(0.3, 0.4), 10.266), {}, 10.266)
	var c2b: Array = m.feed_frame(_hand(0.9, F_FOUR, 5.0, true, "Left", 0.52, Vector2(0.3, 0.4), 10.30), {}, 10.30)
	check(_has(c2, "zoom_begin"), "段 2 前置：Z5 掌推 12% 档 → 第 3 推帧（0.46）即 zoom_begin（旧 15% 档 0.50 帧锚退役留痕）")
	check(_has(c2b, "zoom_factor"), "段 2：后续推帧持续 zoom_factor（缩放态保持；中途帧护栏）")
	var c3: Array = m.feed_frame(_hand(0.9, F_FOUR, 5.0, true, "Left", 0.60, Vector2(0.32, 0.4), 10.40), {}, 10.40)
	check(_has(c3, "zoom_factor") and _has(c3, "cursor_move"),
		"Y-A11：掌态缩放期 cursor_move 恒派发（旧 §5.3 注 2「掌态光标暂停」收窄为缩放期恒跟随）")
	var c4: Array = m.feed_frame(_hand(0.9, F_CURSOR, 5.0, true, "Left", 0.60, Vector2(0.32, 0.4), 10.50), {}, 10.50)
	check(_has(c4, "zoom_end"), "段 2 后置：收掌 zoom_end（缩放态退出）")

	# ---- 段 3（router 级）：真 cursor layer 光标圈笔画期可见+位置随帧更新（不进 2s 隐藏）----
	var bridge: Node = get_root().get_node("GestureBridge")
	var game: Node = get_root().get_node("Game")
	bridge._set_state(1)
	game.set("_state", game.State.MAIN_MENU)   # zone none：two_down 无关卡消费、cursor_move 照常派发
	var router: Node = load("res://autoload/gesture_router.gd").new()
	add_child(router)
	await process_frame
	# AF 同步批（2026-11-01）：内存钉 gesture_input=true（本文件纪律「user:// 零触碰」，不落盘
	# 进程退出即弃；钉位于本文件首个 await 之后防 SaveManager._ready load_game 整体替换 _data
	# 引用冲钉）。实证：router.feed 守卫链 `_gesture_enabled()` 读 SaveManager settings 的
	# gesture_input——用户存档 Q3 双关时段 3 全部 feed 走 blocked 早退，光标圈不显示、位置不更新
	#（非代码回归；「手势关=零手势事件」生产语义正确，map 级段 1/2 直调 feed_frame 不经守卫链
	# 故不受影响）。
	var sm_follow: Node = get_root().get_node("SaveManager")
	if sm_follow != null:
		var sm_data_follow: Dictionary = sm_follow.get("_data")
		if typeof(sm_data_follow.get("settings")) != TYPE_DICTIONARY:
			sm_data_follow["settings"] = {}
		(sm_data_follow["settings"] as Dictionary)["gesture_input"] = true
	# 批次 AF 终审备案族（语言钉扎先例=6411fae o_catalog_shop）：autoload _ready 推迟至树激活，
	# 须等一帧后钉 zh——用户真实存档现 language=en，不钉则文案断言呈 en 态假红。
	# 编译窗安全：经节点查找而非全局名（--script 模式 autoload 全局名编译期未注册）。
	var i18n_node: Variant = get_root().get_node_or_null("I18n")
	if i18n_node != null:
		i18n_node.call("set_language", "zh")
	bridge._set_state(1)
	router._setup()
	var spy: Node = load("res://scripts/gesture_cursor_layer.gd").new()
	add_child(spy)
	await process_frame
	router.set_cursor_layer(spy)
	var ring_l: Control = spy.get_child(0)
	var vp_sz: Vector2 = get_root().get_visible_rect().size
	var _gm_c: Dictionary = load("res://scripts/gesture_map.gd").get_script_constant_map()
	var gain: float = float(_gm_c.get("CURSOR_GAIN", 3.5))
	## 批次 AC §4.4-2：逆映射纵向基准上移 c_y=(0.5+m)/g（与 apply_cursor_gain 互逆）。
	var cy_y: float = (0.5 + float(_gm_c.get("CURSOR_OVERSHOOT", 0.15))) / gain
	var inv := func(n: Vector2) -> Vector2:
		return (n - Vector2(0.5, 0.5)) / gain + Vector2(0.5, cy_y)
	var p1: Vector2 = inv.call(Vector2(0.3, 0.4)) * vp_sz
	router.feed({"left": _hand(0.9, F_CURSOR, 5.0, true, "Left", 0.2, inv.call(Vector2(0.3, 0.4)), 0.0),
		"right": null, "timestamp": 0.0})
	check(ring_l.visible, "段 3 前置：光标圈可见（cursor 态）")
	router.feed({"left": _hand(0.9, F_TWO, 5.0, true, "Left", 0.2, inv.call(Vector2(0.3, 0.4)), 0.033),
		"right": null, "timestamp": 0.033})
	var pos_before: Vector2 = ring_l.position
	router.feed({"left": _hand(0.9, F_TWO, 5.0, true, "Left", 0.2, inv.call(Vector2(0.4, 0.45)), 0.066),
		"right": null, "timestamp": 0.066})
	# 位置断言取相对位移（EMA 兜底平滑+增益链非恒等映射，绝对坐标对 EMA α 敏感——批次 R 坑⑥口径）
	check((ring_l.position - pos_before).length() > 2.0,
		"Y-A11：二指笔画期光标圈位置随指尖帧更新（位移 %.1fpx；旧码零更新=红灯）" % (ring_l.position - pos_before).length())
	check(ring_l.visible, "Y-A11：二指笔画期光标圈保持可见（HIDE_AFTER_SEC 计时被 cursor_move 持续刷新）")
	# 2s 无事件才隐藏（既有隐藏链不回退——笔画结束后正常超时隐藏）
	await create_timer(0.1).timeout
	check(ring_l.visible, "Y-A11：短时无新帧不立即隐藏（既有 2s 链路保持）")
	if bridge != null and bridge.gesture_state_received.is_connected(router.feed):
		bridge.gesture_state_received.disconnect(router.feed)
	router.queue_free()
	spy.queue_free()
	await process_frame
	finish()
