extends "res://tests/test_base.gd"
## 修复批红测 8（P3，手势域）：翻转锁定跨缩放残留。
## 病灶：gesture_map.gd zoom 期 flip 态冻结（_feed_flip `if zooming return` :747），
## zoom_begin 不清 flip_locked —— 锁定于入缩放前的 flip_at 残余 1.0s 窗（FLIP_WINDOW_SEC）
## 跨过整个缩放段继续有效，收掌后窗内翻转姿态可误发 flip（undo/redo 误触发）。
## 修法（保守）：zoom_begin 时清本侧 flip_locked/flip_streak + 同侧在途 _pending_flip
##（缩放意图下翻转前置作废）；对侧 pending 不动（缩放只作废本侧翻转前置）。
## 不改翻转主判定（锁定/触发/冷却/配对窗零改动）。
## 纯逻辑层直调（夹具=tests/test_gesture_map 手 dict 构造同款；零真手零摄像头零存档）。
const MAP_SRC := "res://scripts/gesture_map.gd"
const F_FOUR := [0.1, 0.9, 0.9, 0.9, 0.9]
const F_FOLD := [0.1, 0.9, 0.1, 0.1, 0.1]
const F_CURSOR := [0.1, 0.9, 0.1, 0.1, 0.1]

func _hand(conf: float, fingers: Array, roll: float, facing: bool, label: String,
		palm_size: float, tip: Vector2, ts: float) -> Dictionary:
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
	lm[9] = [lm[0][0], lm[0][1] - palm_size, 0.0]
	return {"gesture": "", "gesture_id": 0, "confidence": conf,
		"hand_x": tip.x, "hand_y": tip.y, "hand_z": 0.0,
		"hand_rotation_x": roll, "hand_rotation_y": 0.0, "hand_rotation_z": 0.0,
		"fingers": fingers, "pinch_distance": 0.5,
		"hand_index": 0 if label == "Left" else 1, "handedness": label,
		"landmarks": lm, "fps": 30.0, "is_detected": true,
		"timestamp": ts, "palm_size": palm_size}

func _fl(m: Variant, fingers: Array, roll: float, facing: bool, ps: float, now: float) -> Array:
	return m.feed_frame(_hand(0.9, fingers, roll, facing, "Left", ps, Vector2(0.3, 0.4), now), {}, now)

## 双手同帧（负例用：双侧在场防 _teardown_side 清掉对侧 pending）
func _fb(m: Variant, lf: Array, lroll: float, lfac: bool, lps: float, now: float) -> Array:
	return m.feed_frame(
		_hand(0.9, lf, lroll, lfac, "Left", lps, Vector2(0.3, 0.4), now),
		_hand(0.9, F_CURSOR, 5.0, true, "Right", 0.5, Vector2(0.7, 0.4), now), now)

func _has(intents: Array, t: String) -> bool:
	for it: Variant in intents:
		if typeof(it) == TYPE_DICTIONARY and String((it as Dictionary).get("type", "")) == t:
			return true
	return false

func _side_st(m: Variant, side: String) -> Dictionary:
	var all: Variant = m.get("_side")
	return (all as Dictionary).get(side, {}) if typeof(all) == TYPE_DICTIONARY else {}

func _initialize() -> void:
	print("== test_fix_gesture_zoom_flip ==")
	var m: Variant = (load(MAP_SRC) as GDScript).new()
	check(m != null, "前置：GestureMap 实例化")
	# 批次 AC 4A（spec §4.6-3）：生产语义改**双手协同推拉/间距缩放**，单手掌推拉通道默认关。
	# 本件四段的被测对象=「单手掌态缩放与翻转前置的互作（残余窗/pending 作废）」——经兼容开关
	# 开启历史单手掌通道后逐字节照跑（等价改写留痕：夹具与时序零变化，仅加一行开关；双手协同
	# 缩放通道的进入清障断言见 test_ac_batch4_gesture 段 2）。
	m.call("set_single_hand_zoom_enabled", true)

	# ============ 段 1：翻转锁定 → 推拉入缩放 → 锁定清零（红测） ============
	# 夹具序列与 tests/test_gesture_map 段 10 同构（palm 确认 2 帧锁 flip → 3 帧推拉 zoom）
	var f1: Array = _fl(m, F_FOUR, 5.0, true, 0.2, 50.0)
	var f2: Array = _fl(m, F_FOUR, 5.0, true, 0.2, 50.033)
	check_eq(bool(_side_st(m, "left").get("flip_locked", false)), true,
		"前置：palm 确认 2 帧 → flip_locked=true（锁定建立）")
	check_eq(String(m.get_side_semantic("left")), "palm", "前置：左手语义=palm")
	_fl(m, F_FOUR, 5.0, true, 0.35, 50.066)
	_fl(m, F_FOUR, 5.0, true, 0.35, 50.099)
	var f5: Array = _fl(m, F_FOUR, 5.0, true, 0.35, 50.132)
	check(_has(f5, "zoom_begin"), "前置：推拉 15%→3 帧 → zoom_begin（夹具走通）")
	check_eq(bool(_side_st(m, "left").get("flip_locked", false)), false,
		"P3 红测：zoom_begin 清本侧 flip_locked（改前冻结残留 true → 收掌后残余窗可误发 flip）")
	check_eq(int(_side_st(m, "left").get("flip_streak", -1)), 0,
		"P3 红测：zoom_begin 清本侧 flip_streak（前置确认计数一并作废）")

	# ============ 段 2：缩放结束 → 残余窗内翻转姿态零 flip（红测） ============
	_fl(m, F_FOUR, 5.0, true, 0.35, 50.165)   # 缩放持续
	var f7: Array = _fl(m, F_FOLD, 5.0, true, 0.35, 50.30)
	check(_has(f7, "zoom_end"), "前置：收掌 → zoom_end")
	# 残余窗：flip_at=50.033 → 窗至 51.033；现于 50.40/50.433 喂翻转姿态（roll 大变）
	var f8: Array = _fl(m, F_FOUR, 130.0, false, 0.35, 50.40)
	var f9: Array = _fl(m, F_FOUR, 130.0, false, 0.35, 50.433)
	# 说明：feed_frame 内部消费 "flip" 意图转 _pending_flip（gesture_map:300），输出数组
	# 永不含 "flip"——可观察的误发证据=对侧未翻而 _pending_flip 被单翻占用（随后 1.2s 解算 undo）。
	check_eq(bool((m.get("_pending_flip") as Dictionary).is_empty()), true,
		"P3 红测：缩放残余窗内翻转姿态零 flip 占用（改前 flip_locked 跨缩放残留 → f9 误发 flip→pending，")
	check(not _has(f8, "undo") and not _has(f9, "undo"),
		"P3 红测：零 flip → 同帧零 undo 解算（解算在窗闭合 1.2s 后，本断言锁当前帧）")

	# ============ 段 3：同侧在途 pending 随 zoom_begin 作废（红测） ============
	var m2: Variant = (load(MAP_SRC) as GDScript).new()
	m2.call("set_single_hand_zoom_enabled", true)   # AC 4A：单手掌通道兼容开关（同上）
	m2.set("_pending_flip", {"side": "left", "at": 60.0, "other_recent": false})
	_fb(m2, F_FOUR, 5.0, true, 0.2, 60.0)
	_fb(m2, F_FOUR, 5.0, true, 0.2, 60.033)
	_fb(m2, F_FOUR, 5.0, true, 0.35, 60.066)
	_fb(m2, F_FOUR, 5.0, true, 0.35, 60.099)
	var s5: Array = _fb(m2, F_FOUR, 5.0, true, 0.35, 60.132)
	check(_has(s5, "zoom_begin"), "段3 前置：m2 进入缩放")
	check_eq(bool((m2.get("_pending_flip") as Dictionary).is_empty()), true,
		"P3 红测：同侧在途 pending 随 zoom_begin 作废（缩放意图下翻转前置作废；改前残留）")

	# ============ 段 4：对侧 pending 不受本侧缩放影响（反向护栏，防改过头） ============
	var m3: Variant = (load(MAP_SRC) as GDScript).new()
	m3.call("set_single_hand_zoom_enabled", true)   # AC 4A：单手掌通道兼容开关（同上）
	m3.set("_pending_flip", {"side": "right", "at": 70.0, "other_recent": false})
	_fb(m3, F_FOUR, 5.0, true, 0.2, 70.0)
	_fb(m3, F_FOUR, 5.0, true, 0.2, 70.033)
	_fb(m3, F_FOUR, 5.0, true, 0.35, 70.066)
	_fb(m3, F_FOUR, 5.0, true, 0.35, 70.099)
	var t5: Array = _fb(m3, F_FOUR, 5.0, true, 0.35, 70.132)
	check(_has(t5, "zoom_begin"), "段4 前置：m3 左手进入缩放")
	check_eq(bool((m3.get("_pending_flip") as Dictionary).is_empty()), false,
		"反向护栏：对侧（right）在途 pending 不受本侧 zoom 影响（作废只限翻转发起侧）")

	finish()
