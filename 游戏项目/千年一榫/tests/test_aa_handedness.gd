extends "res://tests/test_base.gd"
## 批次 AA（AA-A 波，spec §4 W1 手性域）GDScript 侧护栏用例：
##   ① W1-9/W1-10 包级防重：同一只手（landmark 重合）不得同时出现在 left 与 right
##      （骨架只绘一份、优先 left）；两只不同手照常双侧；**左蓝右红映射纯透传不改**。
##   ② W1-11 心跳 `stale` 帧：不 teardown、累计态（semantic/hand_id/join 边沿）保留；
##      **无 stale 的老空包行为零变化**（协议只增不改）。
##   ③ W1-8 诊断日志：`GAME_GESTURE_DEBUG` 通道落 `label_mp`/`mp_score`/`label_geo` 三字段。
## 零摄像头纪律：全部经 `GestureBridge.simulate_packet` / `GestureRouter.feed` /
## `GestureMap.feed_frame` 构造包注入，不触碰任何采集设备与 9876/9877/9878 真端口。
## 4.7 实证规律：`GestureMap` 为 RefCounted → Variant 直调（禁 `as Node`）；桥/手 dict
## 取键一律 `.get(key, 缺省)`；`_initialize` 阶段节点不在树内 → 需要树的前置先 `await process_frame`。

const SkScript := preload("res://scenes/shared/camera_skeleton.gd")
const PaletteScript := preload("res://scripts/palette.gd")
const CursorLayerScript := preload("res://scripts/gesture_cursor_layer.gd")

var _save: Variant
var _bridge: Variant
var _router: Variant
var _gi_had := false
var _gi_prev: Variant = null
var _dbg_existed := false
var _dbg_bytes := PackedByteArray()

# ---------- 夹具 ----------

func _mk_lm(cx: float) -> Array:
	## 21 点归一 landmarks（cx=该手水平基准；两手不同 cx = 两只不同手）
	var lm: Array = []
	for i: int in 21:
		lm.append([cx + float(i % 5) * 0.01, 0.40 + (float(i) / 5.0) * 0.01])
	return lm

func _near_lm(base: Array, dx: float) -> Array:
	var lm: Array = []
	for p: Variant in base:
		var a: Array = p
		lm.append([float(a[0]) + dx, float(a[1])])
	return lm

func _hand(conf: float, fingers: Array, label: String, id: String, palm := 0.1) -> Dictionary:
	var lm := _mk_lm(0.30)
	lm[0] = [0.30, 0.60]
	lm[5] = [0.35, 0.54]   # 食指根（腕右上）
	lm[17] = [0.25, 0.55]  # 小指根（腕左上）
	lm[8] = [0.32, 0.41]   # 食指尖（tip）
	return {"gesture": "", "gesture_id": 0, "confidence": conf,
		"hand_x": 0.32, "hand_y": 0.41, "hand_z": 0.0,
		"hand_rotation_x": 5.0, "hand_rotation_y": 0.0, "hand_rotation_z": 0.0,
		"fingers": fingers, "pinch_distance": 0.4,
		"hand_index": 0 if label == "Left" else 1, "handedness": label,
		"landmarks": lm, "fps": 30.0, "is_detected": true, "timestamp": 0.0,
		"palm_size": palm, "id": id}

func _debug_path() -> String:
	return "user://gesture_debug.log"

## 收口还原：gesture_input 内存态 + gesture_debug.log（不落盘改动用户数据）
func _restore() -> void:
	if _save != null:
		var st_v: Variant = _save.get("_data")
		if typeof(st_v) == TYPE_DICTIONARY and (st_v as Dictionary).has("settings"):
			var st: Dictionary = (st_v as Dictionary)["settings"]
			if _gi_had:
				st["gesture_input"] = _gi_prev
			else:
				st.erase("gesture_input")
	var p := _debug_path()
	if _dbg_existed:
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_dbg_bytes)
			f.flush()
			f.close()
	elif FileAccess.file_exists(p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

func finish() -> void:
	_restore()
	super.finish()

# ---------- 主流程 ----------

func _initialize() -> void:
	print("== test_aa_handedness ==")

	# ==== 段 1：W1-10 骨架同源防重（包级「同一只手不出现两次」的渲染落点）====
	var sk: Control = SkScript.new()
	var lm_same := _mk_lm(0.5)
	sk.set_hands({"landmarks": lm_same, "id": "L0"}, {"landmarks": lm_same, "id": "R0"})
	check_eq(sk._hands.size(), 1,
		"W1-10：左右同源（landmark 重合）→ 骨架只存一份（现状存两份=双骨架判红）")
	check(sk._hands.has("left"), "W1-10：同源时优先保留 left（spec §4.3 W1-10 口径）")
	sk.set_hands({"landmarks": lm_same}, {"landmarks": _near_lm(lm_same, 0.005)})
	check_eq(sk._hands.size(), 1, "W1-10：逐点偏差 0.005 < 容差 0.02 → 判同源只存一份")
	sk.set_hands({"landmarks": _mk_lm(0.3)}, {"landmarks": _mk_lm(0.7)})
	check_eq(sk._hands.size(), 2, "W1-10：两只不同手照常双侧（护栏不误合并）")
	check_eq(int(sk.mouse_filter), Control.MOUSE_FILTER_IGNORE,
		"W1-9：骨架 mouse_filter 仍 IGNORE（透传语义未改）")
	# 左蓝右红映射纯透传锁（spec §4.3 W1-9：不得改映射）
	check((SkScript.SKELETON_COLOR_LEFT as Color).is_equal_approx(Color(0.30, 0.55, 1.0)),
		"W1-9：左手蓝映射保持（camera_skeleton.gd 纯透传零改动）")
	check((SkScript.SKELETON_COLOR_RIGHT as Color).is_equal_approx(Color(1.0, 0.35, 0.30)),
		"W1-9：右手红映射保持（camera_skeleton.gd 纯透传零改动）")
	# 批次 AA 审查回修 P3-8：光圈层（gesture_cursor_layer）左蓝右红此前**未入任何断言**
	# ——补轻量断言锁死「左=CURSOR_BLUE、右=CURSOR_RED」（实例级行为断言，非源码串匹配）。
	var cl: Variant = CursorLayerScript.new()
	cl.call("_ready")   # 无头 --script 下不入树，直接驱动 _ready（其内仅 add_child/常量赋值，无树依赖）
	var rings_v: Variant = cl.get("_rings")
	var ring_l: Variant = (rings_v as Dictionary).get("left", null)
	var ring_r: Variant = (rings_v as Dictionary).get("right", null)
	check(ring_l != null and (ring_l as Control).get("ring_color").is_equal_approx(PaletteScript.CURSOR_BLUE),
		"P3-8：左光圈色 = Palette.CURSOR_BLUE（左蓝）")
	check(ring_r != null and (ring_r as Control).get("ring_color").is_equal_approx(PaletteScript.CURSOR_RED),
		"P3-8：右光圈色 = Palette.CURSOR_RED（右红）")
	check_eq(int(cl.get("layer")), 101, "P3-8：光圈层 layer=101（Z6-P3-4 不动）")

	# ==== 段 2：经 GestureBridge.simulate_packet 注入同源左右包（任务书指定注入方式）====
	_bridge = get_root().get_node("GestureBridge")
	var lm2 := _mk_lm(0.55)
	var got := {"n": 0}
	var handler := func(d: Dictionary) -> void:
		sk.set_hands(d.get("left"), d.get("right"))
		got["n"] = int(got["n"]) + 1
	_bridge.gesture_state_received.connect(handler)
	_bridge.simulate_packet(JSON.stringify({
		"left": {"landmarks": lm2, "id": "L0", "gesture": "Open_Palm"},
		"right": {"landmarks": lm2, "id": "R0", "gesture": "Open_Palm"},
		"timestamp": 1.0}))
	check_eq(int(got["n"]), 1, "W1-9：simulate_packet 注入包 → gesture_state_received 恰发一次")
	check_eq(sk._hands.size(), 1,
		"W1-9：同源左右包经真实链路注入 → 骨架只绘一份（现状两份判红）")
	# 反向：两只不同手 → 双侧照常（防重护栏不吞第二只手）
	_bridge.simulate_packet(JSON.stringify({
		"left": {"landmarks": _mk_lm(0.3), "id": "L1", "gesture": "Open_Palm"},
		"right": {"landmarks": _mk_lm(0.75), "id": "R1", "gesture": "Open_Palm"},
		"timestamp": 2.0}))
	check_eq(sk._hands.size(), 2, "W1-9：两只不同手 → 双侧骨架照常（第二只手不被防重护栏吞掉）")
	_bridge.gesture_state_received.disconnect(handler)

	# ==== 段 3：W1-11 心跳 stale 帧短路（不 teardown / 不清累计态）====
	_save = get_root().get_node("SaveManager")
	_router = get_root().get_node("GestureRouter")
	# SaveManager._ready 在 --script 下可能被推迟 → _data 空时才回落 load_game（读侧优先，少碰盘）
	var data_v: Variant = _save.get("_data")
	if not (typeof(data_v) == TYPE_DICTIONARY and (data_v as Dictionary).has("settings")):
		_save.load_game()
	var st_v: Variant = _save.get("_data")
	if typeof(st_v) == TYPE_DICTIONARY and (st_v as Dictionary).has("settings"):
		var st: Dictionary = (st_v as Dictionary)["settings"]
		_gi_had = st.has("gesture_input")
		_gi_prev = st.get("gesture_input", null)
		st["gesture_input"] = true   # 内存态强制（feed 消费门），收口 _restore 还原，零落盘
	_bridge._set_state(1)            # READY（feed 消费前提）
	_router._setup()
	var f_cursor: Array = [0.1, 0.9, 0.1, 0.1, 0.1]
	_router.feed({"left": _hand(0.9, f_cursor, "Left", "L0"), "right": null, "timestamp": 0.0})
	var map: Variant = _router.get("_map")
	check(map != null, "前置：router._setup 后 GestureMap 就位")
	var sides: Dictionary = map.get("_side")
	check_eq(String((sides["left"] as Dictionary).get("semantic", "")), "cursor",
		"前置：左手已进 cursor 语义（断言基线）")
	check_eq(String((sides["left"] as Dictionary).get("hand_id", "")), "L0",
		"前置：hand_id 在位（断言基线）")
	check((map.get("_join_edges") as Dictionary).has("left"),
		"前置：cursor 进入边沿已记账（断言基线）")

	# 3a. 心跳空包带 stale → 不得 teardown（R1-g，修复前判红）
	_router.feed({"left": null, "right": null, "stale": true, "timestamp": 1.0})
	sides = map.get("_side")
	check_eq(String((sides["left"] as Dictionary).get("semantic", "")), "cursor",
		"W1-11：stale 心跳帧不 teardown（semantic 保留，现状被清判红）")
	check_eq(String((sides["left"] as Dictionary).get("hand_id", "")), "L0",
		"W1-11：stale 心跳帧不清 hand_id（防整侧清态打断翻转/缩放累计）")
	check((map.get("_join_edges") as Dictionary).has("left"),
		"W1-11：stale 心跳帧不清 join 边沿")

	# 3b. 老包（无 stale 字段）行为零变化 → 照常 teardown（协议只增不改护栏，恒绿）
	_router.feed({"left": null, "right": null, "timestamp": 2.0})
	sides = map.get("_side")
	check_eq(String((sides["left"] as Dictionary).get("semantic", "")), "",
		"W1-11：无 stale 的老空包照常 teardown（向后兼容，老包行为零变化）")
	check_eq(String((sides["left"] as Dictionary).get("hand_id", "")), "",
		"W1-11：老空包照常清 hand_id（既有语义保持）")

	# ==== 段 4：W1-8 诊断日志三字段（label_mp / mp_score / label_geo）====
	if FileAccess.file_exists(_debug_path()):
		_dbg_existed = true
		_dbg_bytes = FileAccess.get_file_as_bytes(_debug_path())
	var dbg_map: Variant = load("res://scripts/gesture_map.gd").new()
	dbg_map.set_debug_enabled(true)
	var dh := _hand(0.9, f_cursor, "Left", "L0")
	dh["label_mp"] = "Left"
	dh["mp_score"] = 0.93
	dh["label_geo"] = "Left"
	dbg_map.feed_frame(dh, {}, 10.0)
	dbg_map.set_debug_enabled(false)
	var log_txt := FileAccess.get_file_as_string(_debug_path())
	check(log_txt.contains("label_mp="),
		"W1-8：诊断日志含 label_mp=（现状缺失判红）")
	check(log_txt.contains("mp_score="), "W1-8：诊断日志含 mp_score=")
	check(log_txt.contains("label_geo="), "W1-8：诊断日志含 label_geo=")
	check(log_txt.contains("0.93"), "W1-8：mp_score 实值落盘（真手复验可定位）")

	# ==== 段 5：W1-11 回修 P2-2① 连续 stale 时长上限（STALE_MAX_SEC=5.0【暂定·待用户复验】）====
	# 动机：旧码 stale 短路期间**无上界**保留 semantic/flip_locked/flip_streak/hand_id/zooming/
	# join 边沿——捂镜/无帧数分钟后恢复，残留 pending 翻转配对可能被新姿态误完成（审查 P2-2）。
	var two_f: Array = [0.1, 0.9, 0.9, 0.1, 0.1]

	# 5a. 连续 stale 4.9s（≤5.0 上限）→ 状态保留（短路语义不变）
	var cur_f: Array = [0.1, 0.9, 0.1, 0.1, 0.1]
	var m5: Variant = load("res://scripts/gesture_map.gd").new()
	m5.feed_frame(_hand(0.9, cur_f, "Left", "L0"), {}, 100.0)
	var s5: Dictionary = m5.get("_side")
	check_eq(String((s5["left"] as Dictionary).get("semantic", "")), "cursor", "前置：左手 cursor 语义在位")
	check((m5.get("_join_edges") as Dictionary).has("left"), "前置：join 边沿已记账")
	m5.feed_frame(null, null, 100.1, true)                      # 连续 stale 起算 t=100.1
	m5.feed_frame(null, null, 105.0, true)                      # 连续 stale 4.9s（心跳 1Hz 逐拍推进）
	s5 = m5.get("_side")
	check_eq(String((s5["left"] as Dictionary).get("semantic", "")), "cursor",
		"P2-2①：连续 stale 4.9s（≤5.0）→ 状态保留（不得提前清）")
	check_eq(String((s5["left"] as Dictionary).get("hand_id", "")), "L0",
		"P2-2①：stale 4.9s → hand_id 保留")
	check((m5.get("_join_edges") as Dictionary).has("left"),
		"P2-2①：stale 4.9s → join 边沿保留")

	# 5b. 连续 stale 5.1s（>5.0 上限）→ 强制双侧清态 + 兜底抬起意图
	var m6: Variant = load("res://scripts/gesture_map.gd").new()
	m6.feed_frame(_hand(0.9, two_f, "Left", "L0"), {}, 200.0)
	m6.feed_frame(_hand(0.9, two_f, "Left", "L0"), {}, 200.033)
	var out6: Array = []
	m6.feed_frame(null, null, 200.1, true)                      # 连续 stale 起算 t=200.1
	out6 = m6.feed_frame(null, null, 205.2, true)               # 连续 stale 5.1s → 超上限
	s5 = m6.get("_side")
	check_eq(String((s5["left"] as Dictionary).get("semantic", "")), "",
		"P2-2①：连续 stale 5.1s（>5.0）→ 强制清态（旧码无 TTL 恒保留 = 判红点）")
	check_eq(String((s5["left"] as Dictionary).get("hand_id", "")), "",
		"P2-2①：超时强制清态连 hand_id 一并清（新会话 id 复用才可断链）")
	check_eq(String((s5["right"] as Dictionary).get("semantic", "")), "",
		"P2-2①：强制清态为**双侧**（_teardown_side 双侧各一次）")
	var types5: Array = []
	for it5_v: Variant in out6:
		if typeof(it5_v) == TYPE_DICTIONARY:
			types5.append(String((it5_v as Dictionary).get("type", "")))
	check(types5.has("two_up"),
		"P2-2①：强制清态须派发兜底 two_up（防虚拟键卡死），实际=" + str(types5))

	# 5c. 反向护栏：**非 stale 供帧复位计时器**（4.0s stale + 正常帧 + 再起算 ≠ 累计 6.5s）
	var m7: Variant = load("res://scripts/gesture_map.gd").new()
	m7.feed_frame(_hand(0.9, two_f, "Left", "L0"), {}, 300.0)
	m7.feed_frame(_hand(0.9, two_f, "Left", "L0"), {}, 300.033)
	m7.feed_frame(null, null, 304.0, true)                      # stale 起算 t=304
	# 非 stale 供帧（**双侧都在场** → 本帧零侧 teardown，故计时器唯一复位点=feed_frame 的
	# 非 stale 分支；单侧夹具会让 _teardown_side 的复位把本探针掩护掉）
	m7.feed_frame(_hand(0.9, two_f, "Left", "L0"), _hand(0.9, two_f, "Right", "R0"), 306.0)
	m7.feed_frame(null, null, 310.5, true)                      # 重新起算（若未复位则 310.5-304=6.5>5 → 误清）
	s5 = m7.get("_side")
	check_eq(String((s5["left"] as Dictionary).get("semantic", "")), "two",
		"P2-2①反向护栏：非 stale 供帧复位计时器（否则被分段 stale 累计误清）")

	# ==== 段 6：W1-11 回修 P2-2② 桥「非 READY→READY」边沿强制清态（python 重启 id 碰撞防护）====
	# 动机：python 进程重启后 id 计数器归零 → 新手复得 "L0" 等旧 id → id 相等不触发
	# gesture_map 的 id 断链 teardown → 旧手 zooming/flip 态泄入新手会话（审查 P2-2 (b)）。
	# 4.7 实证⑥：_initialize 阶段树未激活（绝对路径 get_node 会报错，见上方 ERROR 行），
	# 先等一帧让桥/Router 进入活动树；再**复刻 _setup 的接线**（_initialize 里 _setup 因
	# `not is_inside_tree()` 早退未接线）→ 用真实 load_state_changed 信号驱动边沿。
	await process_frame
	var cb_edge := Callable(_router, "_on_bridge_state_for_reset")
	var wired_edge: bool = _bridge.load_state_changed.is_connected(cb_edge)
	if not wired_edge:
		_bridge.load_state_changed.connect(cb_edge)
	var palm_f: Array = [0.1, 0.9, 0.9, 0.9, 0.95]
	_bridge._set_state(1)   # 确保桥 READY（已在 READY 则 no-op 不发信号）
	var m8: Variant = _router.get("_map")
	check(m8 != null, "前置：router._map 就位")
	# 批次 AC 4A（spec §4.6-3）：生产语义改**双手协同推拉/间距缩放**，单手掌推拉通道默认关。
	# 本段构造「zooming 残留态」经兼容开关开启历史单手掌通道（等价改写留痕：断言行与数量不变，
	# 仅加一行开关；本段被测对象=UNAVAILABLE/stale 边沿全量清态，与缩放通道选择正交）。
	m8.call("set_single_hand_zoom_enabled", true)
	var t8 := 400.0
	# 6a. 建立左手 palm 语义 + 翻转锁 + 缩放态（palm_size 递增推满 push_streak=3）
	m8.feed_frame(_hand(0.9, palm_f, "Left", "L0", 0.10), {}, t8)
	m8.feed_frame(_hand(0.9, palm_f, "Left", "L0", 0.10), {}, t8 + 0.033)
	var s8: Dictionary = m8.get("_side")
	check_eq(String((s8["left"] as Dictionary).get("semantic", "")), "palm", "前置：左手 palm 语义在位")
	check(bool((s8["left"] as Dictionary).get("flip_locked", false)), "前置：flip_locked=true 在位")
	m8.feed_frame(_hand(0.9, palm_f, "Left", "L0", 0.13), {}, t8 + 0.066)
	m8.feed_frame(_hand(0.9, palm_f, "Left", "L0", 0.15), {}, t8 + 0.099)
	m8.feed_frame(_hand(0.9, palm_f, "Left", "L0", 0.16), {}, t8 + 0.132)
	m8.feed_frame(_hand(0.9, palm_f, "Left", "L0", 0.17), {}, t8 + 0.165)
	s8 = m8.get("_side")
	check(bool((s8["left"] as Dictionary).get("zooming", false)), "前置：zooming=true 在位")
	# 6b. 短 stale 段（<5s，不触发①强制清态）→ 状态仍应在（①②两条互不越界）
	m8.feed_frame(null, null, t8 + 1.0, true)
	s8 = m8.get("_side")
	check(bool((s8["left"] as Dictionary).get("zooming", false)), "短 stale（<TTL）不清态（①②互不越界）")
	# 6c. 模拟 python 重启：桥离开 READY（LOADING，期间无包）→ 回 READY（**边沿**）
	_bridge._set_state(0)
	_bridge._set_state(1)
	s8 = m8.get("_side")
	check_eq(String((s8["left"] as Dictionary).get("semantic", "")), "",
		"P2-2②：非READY→READY 边沿强制清态（旧语义泄入 = 判红点）")
	check_eq(bool((s8["left"] as Dictionary).get("zooming", false)), false,
		"P2-2②：旧 zooming 不得泄入新手会话")
	check_eq(bool((s8["left"] as Dictionary).get("flip_locked", false)), false,
		"P2-2②：旧 flip_locked 不得泄入新手会话")
	check_eq(String((s8["left"] as Dictionary).get("hand_id", "")), "",
		"P2-2②：hand_id 清空——python id 计数器归零后复用 \"L0\" 才可触发 id 断链")
	# 6d. 新会话复用同一 id "L0" → 首帧零**继承**意图（旧码会吐 zoom_end 等旧态意图）
	# 批次 AD（§4.1.1）等价改写：清态后的首帧 cursor_move 不再是「旧语义泄入」——它是本次
	# **全新会话本手逐帧跟手**的合法光标意图（上方三条清态断言逐条不变，旧态字段全部为假）。
	# 判据加强（非放宽）：①断言不得含任何**旧态动作词**（zoom_end/zoom_begin/two_*/flip/undo/
	# redo/join/clear/delete/palm_begin/exit_flip）；②cursor_move 坐标必须等于本帧食指尖映射值
	# （证明是新帧数据，而非陈旧缓存回吐。）旧判据「整帧零意图」是「光标受状态机门控」时代的
	# 产物，AD 解耦后该形态不可达（这正是 §4.1.1 的目标）。
	var post8: Array = m8.feed_frame(_hand(0.9, [0.1, 0.1, 0.1, 0.1, 0.1], "Left", "L0"),
		{}, t8 + 1.5)
	s8 = m8.get("_side")
	check_eq(String((s8["left"] as Dictionary).get("semantic", "")), "",
		"P2-2②：新会话 L0 首帧不继承旧语义")
	check_eq(bool((s8["left"] as Dictionary).get("zooming", false)), false,
		"P2-2②：新会话 zooming 仍 false")
	var stale_types: Array = ["zoom_end", "zoom_begin", "two_up", "two_down", "two_move",
		"flip", "undo", "redo", "join", "clear", "delete", "palm_begin", "exit_flip"]
	var leaked8: Array = []
	for it8: Variant in post8:
		var t8s := String((it8 as Dictionary).get("type", ""))
		if stale_types.has(t8s):
			leaked8.append(t8s)
	check(leaked8.is_empty(),
		"P2-2②：新会话首帧零**旧态泄入**意图（旧码吐 zoom_end = 判红），实际泄漏=" + str(leaked8))
	var cm8 := Vector2(-9, -9)
	var has_cm8 := false
	for it8b: Variant in post8:
		if String((it8b as Dictionary).get("type", "")) == "cursor_move":
			has_cm8 = true
			cm8 = Vector2((it8b as Dictionary).get("pos", Vector2(-9, -9)))
	var gm8: Dictionary = (load("res://scripts/gesture_map.gd") as Script).get_script_constant_map()
	# 该夹具 _hand 的 lm[8]（食指尖）= (0.32, 0.41)、无 tip_x/tip_y → 走 landmark 源
	var exp8: Vector2 = (load("res://scripts/gesture_map.gd") as Script).apply_cursor_gain(
		Vector2(0.32, 0.41), float(gm8.get("CURSOR_GAIN", 2.5)))
	check(has_cm8 and bool(cm8.is_equal_approx(exp8)),
		"AD §4.1.1：新会话首帧 cursor_move 坐标=本帧食指尖映射值 %s（新帧数据、非陈旧缓存回吐；清态后光标即刻跟手）实际 %s" % [str(exp8), str(cm8)])

	# ---- 段 6e：反向护栏（不得「每次 READY 都清态」）----
	m8.feed_frame(_hand(0.9, cur_f, "Left", "L0"), {}, t8 + 2.0)
	s8 = m8.get("_side")
	check_eq(String((s8["left"] as Dictionary).get("semantic", "")), "cursor", "前置：重连后已建立 cursor 态")
	_router._on_bridge_state_for_reset(1)   # **重复 READY 事件**（READY→READY，非边沿）
	s8 = m8.get("_side")
	check_eq(String((s8["left"] as Dictionary).get("semantic", "")), "cursor",
		"反向护栏：READY→READY 重复事件不得清态（「每次 READY 都清」= 误清正常重连，判红）")
	check_eq(String((s8["left"] as Dictionary).get("hand_id", "")), "L0",
		"反向护栏：重复 READY 不清 hand_id")
	# 正常重连（UNAVAILABLE→READY，手 id 延续）后同 id 手持续供帧 → 不误清、照常累计
	_bridge._set_state(2)
	_bridge._set_state(1)
	m8.feed_frame(_hand(0.9, cur_f, "Left", "L0"), {}, t8 + 2.5)
	m8.feed_frame(_hand(0.9, cur_f, "Left", "L0"), {}, t8 + 2.533)
	s8 = m8.get("_side")
	check_eq(String((s8["left"] as Dictionary).get("semantic", "")), "cursor",
		"反向护栏：正常重连后同 id 手照常累计（边沿只清一次，不逐帧/逐事件误清）")
	# 收口：只断开本测试自行接上的边沿线（不动 _setup 的既有接线）
	if not wired_edge and _bridge.load_state_changed.is_connected(cb_edge):
		_bridge.load_state_changed.disconnect(cb_edge)

	finish()
