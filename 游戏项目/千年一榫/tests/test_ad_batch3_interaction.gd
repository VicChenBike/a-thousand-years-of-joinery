extends "res://tests/test_base.gd"
## 批次 AD 步骤三（2026-09-27，spec §4.3）：关卡交互重构与悬停光晕恢复专项回归。
## 覆盖内容：
##   段 A：双手握拳清空测试与彻底废除右掌 dwell（§4.3.4）
##   段 B：严格三指批量删除（§4.3.2）
##   段 C：单手翻转撤销侧立保护（§4.3.3）
##   段 D：关卡旋转模式显式有界拖拽与自然退出（§4.3.1）
##   段 E：悬停光晕轻量合成注入与立绘点击避让修复（§4.3.5）
##   批次 AD 终验补强（2026-09-28）：F-2①=P2-1 越阈帧零阶跃（段 D D3b/MockLevel）；
##   F-2②=P2-4 双手同帧 synth_motion 手别仲裁落左手（段 E E3）；F-2③=P2-5 立绘锁门（段 E E2b）。
## 零摄像头纪律：全部合成手 dict 直喂，绝不触发摄像头与真实硬件。
## 清档纪律：user://save.json 完整备份还原逐字节比对。

const GM_SRC := "res://scripts/gesture_map.gd"
const ROUTER_SRC := "res://autoload/gesture_router.gd"
const LEVEL_SCENE_PATH := "res://scenes/level/level_scene.tscn"

const DISC_SAVE_PATH := "user://save.json"
const DISC_BK_PATH := "user://_adb3_save.json.bak"

# 手指姿势特征向量
const F_REST := [0.1, 0.1, 0.1, 0.1, 0.1]
const F_CURSOR := [0.1, 0.9, 0.1, 0.1, 0.1]
const F_TWO := [0.1, 0.9, 0.9, 0.1, 0.1]
const F_PALM := [0.1, 0.9, 0.9, 0.9, 0.9]

# 握拳：食、中、无名 <= 0.35；拇指小指不计
const F_FIST := [0.1, 0.2, 0.2, 0.2, 0.8]
const F_FIST_PARTIAL := [0.1, 0.2, 0.2, 0.8, 0.8] # 仅两指弯曲，不判握拳

# 三指删除：食、中、无名 >= 0.55，且小指 <= 0.35
const F_THREE_STRICT := [0.1, 0.9, 0.9, 0.9, 0.2]
const F_THREE_LOOSE_PINKY := [0.1, 0.9, 0.9, 0.9, 0.5] # 小指未收拢，不判三指删除

var _pre_save_text: String = ""
var m: Variant

## 批次 AD 终验补强 F-2①（2026-09-28）：可观测关卡替身——旋转驱动链 `_orbit_apply_move` 的
## 前置是 `_semantic_zone()=="level"` 且 `_level()` 返回**带 orbit_rotate_panel 的关卡**；无头
## --script 下 Game 初始态=BOOT、_current_scene=null，旋转调用在进入关卡分支前就被拦，P2-1 的
## 「越阈帧零阶跃」在旧环境里根本不可观测（这正是三处回修一并回退仍 159/159 全绿的根因）。
## 替身只实现 Router 真实点名的方法（_level() 认 select_voxel、_orbit_apply_move 认
## orbit_rotate_panel、_locked() 认 is_input_locked、态切/提示认 clear_selection/set_orbit_hint）。
class MockLevel:
	extends Node
	var rot_calls: Array = []          # orbit_rotate_panel 调用台账（Δ 逐条留痕）
	var locked := false
	var hint_on := false
	func select_voxel(_cell: Variant, _add: bool) -> void:
		pass                           # 仅作 _level() 认证方法，段 D 不走选块链
	func orbit_rotate_panel(_panel: Node, rel: Vector2) -> void:
		rot_calls.append(rel)
	func is_input_locked() -> bool:
		return locked
	func clear_selection() -> void:
		pass
	func set_orbit_hint(on: bool) -> void:
		hint_on = on
	func _raycast_cell(_local: Vector2, _cont: Node) -> Vector3i:
		return Vector3i(-1, -1, -1)    # 无体素几何：一律空白（段 D 空白按下判据同旧口径）

## 批次 AD 终验补强 F-2②（2026-09-28）：synth_motion 注入位记录替身（_cursor_layer 为
## CanvasLayer 强类型，故必须继承 CanvasLayer；只记注入位，不触视口）。
class MockSynthLayer:
	extends CanvasLayer
	var motions: Array = []
	func synth_motion(pos: Vector2) -> InputEventMouseMotion:
		motions.append(pos)
		return InputEventMouseMotion.new()
	func synth_button(_pos: Vector2, _pressed: bool, _ctrl: bool) -> InputEventMouseButton:
		return InputEventMouseButton.new()
	func synth_wheel(_pos: Vector2, _dir: int) -> InputEventMouseButton:
		return InputEventMouseButton.new()
	func push(_ev: InputEvent) -> void:
		pass
	func show_cursor(_side: String, _pos: Vector2) -> void:
		pass

func _backup_user() -> void:
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
		DirAccess.copy_absolute(DISC_SAVE_PATH, DISC_BK_PATH)
	else:
		_pre_save_text = ""

func _restore_user() -> void:
	if _pre_save_text != "":
		DirAccess.copy_absolute(DISC_BK_PATH, DISC_SAVE_PATH)
		DirAccess.remove_absolute(DISC_BK_PATH)
	elif FileAccess.file_exists(DISC_SAVE_PATH):
		DirAccess.remove_absolute(DISC_SAVE_PATH)
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 测前测后还原逐字节等价")

func finish() -> void:
	_restore_user()
	super.finish()

func _hand(fingers: Array, tip: Vector2, conf: float, label: String, facing: bool, ts: float, rot_x: float = 5.0) -> Dictionary:
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
	lm[9] = [lm[0][0], lm[0][1] - 0.2, 0.0]
	return {
		"gesture": "", "gesture_id": 0, "confidence": conf,
		"hand_x": tip.x, "hand_y": tip.y, "hand_z": 0.0,
		"hand_rotation_x": rot_x, "hand_rotation_y": 0.0, "hand_rotation_z": 0.0,
		"fingers": fingers, "pinch_distance": 0.5,
		"hand_index": 0 if label == "Left" else 1, "handedness": label,
		"landmarks": lm, "fps": 30.0, "is_detected": true, "timestamp": ts,
		"palm_size": 0.2, "tip_x": tip.x, "tip_y": tip.y,
		"id": "L0" if label == "Left" else "R0", "held": false
	}

func _types(intents: Array) -> Array:
	var out: Array = []
	for it: Variant in intents:
		if typeof(it) == TYPE_DICTIONARY:
			out.append(String((it as Dictionary).get("type", "")))
	return out

func _has(intents: Array, t: String) -> bool:
	return _types(intents).has(t)

func _find_intent(intents: Array, t: String) -> Dictionary:
	for it: Variant in intents:
		if typeof(it) == TYPE_DICTIONARY and String((it as Dictionary).get("type", "")) == t:
			return it as Dictionary
	return {}

func _initialize() -> void:
	print("== test_ad_batch3_interaction ==")
	await process_frame
	_backup_user()
	m = load(GM_SRC).new()

	# =========================================================================
	# 段 A：双手握拳清空测试与彻底废除右掌 dwell（spec §4.3.4）
	# =========================================================================
	print("--- 段 A：双手握拳清空测试与彻底废除右掌 dwell ---")
	m.reset()

	# A1: 验证单手仅握拳时绝不触发 clear
	var a1_1: Array = m.feed_frame(_hand(F_FIST, Vector2(0.3, 0.4), 0.9, "Left", true, 1.0), {}, 1.0)
	var a1_2: Array = m.feed_frame(_hand(F_FIST, Vector2(0.3, 0.4), 0.9, "Left", true, 1.033), {}, 1.033)
	check(not _has(a1_1, "clear") and not _has(a1_2, "clear"), "AD §4.3.4：仅左手握拳绝不触发 clear")

	m.reset()
	var a2_1: Array = m.feed_frame({}, _hand(F_FIST, Vector2(0.7, 0.4), 0.9, "Right", true, 1.0), 1.0)
	var a2_2: Array = m.feed_frame({}, _hand(F_FIST, Vector2(0.7, 0.4), 0.9, "Right", true, 1.033), 1.033)
	check(not _has(a2_1, "clear") and not _has(a2_2, "clear"), "AD §4.3.4：仅右手握拳绝不触发 clear")

	# A2: 验证一侧握拳、另一侧未完全握拳（F_FIST_PARTIAL），绝不触发 clear
	m.reset()
	var a3_1: Array = m.feed_frame(
		_hand(F_FIST, Vector2(0.3, 0.4), 0.9, "Left", true, 2.0),
		_hand(F_FIST_PARTIAL, Vector2(0.7, 0.4), 0.9, "Right", true, 2.0),
		2.0
	)
	var a3_2: Array = m.feed_frame(
		_hand(F_FIST, Vector2(0.3, 0.4), 0.9, "Left", true, 2.033),
		_hand(F_FIST_PARTIAL, Vector2(0.7, 0.4), 0.9, "Right", true, 2.033),
		2.033
	)
	check(not _has(a3_1, "clear") and not _has(a3_2, "clear"), "AD §4.3.4：双手其中一只手仅部分弯曲绝不触发 clear")

	# A3: 双手同时握拳，第 1 帧不触发（CONFIRM_FRAMES=2），第 2 帧稳定触发 clear
	m.reset()
	var a4_1: Array = m.feed_frame(
		_hand(F_FIST, Vector2(0.3, 0.4), 0.9, "Left", true, 3.0),
		_hand(F_FIST, Vector2(0.7, 0.4), 0.9, "Right", true, 3.0),
		3.0
	)
	check(not _has(a4_1, "clear"), "AD §4.3.4：双手握拳第 1 帧处于确认期，不触发 clear")

	var a4_2: Array = m.feed_frame(
		_hand(F_FIST, Vector2(0.3, 0.4), 0.9, "Left", true, 3.033),
		_hand(F_FIST, Vector2(0.7, 0.4), 0.9, "Right", true, 3.033),
		3.033
	)
	check(_has(a4_2, "clear"), "AD §4.3.4：双手握拳连续 2 帧稳定触发 clear")
	var clr_it: Dictionary = _find_intent(a4_2, "clear")
	check_eq(clr_it.get("side", ""), "both", "AD §4.3.4：clear 意图的 side 必须为 both")

	# A4: 持续双手握拳，受 Latch 保护不重复触发
	var a4_3: Array = m.feed_frame(
		_hand(F_FIST, Vector2(0.3, 0.4), 0.9, "Left", true, 3.066),
		_hand(F_FIST, Vector2(0.7, 0.4), 0.9, "Right", true, 3.066),
		3.066
	)
	var a4_4: Array = m.feed_frame(
		_hand(F_FIST, Vector2(0.3, 0.4), 0.9, "Left", true, 3.100),
		_hand(F_FIST, Vector2(0.7, 0.4), 0.9, "Right", true, 3.100),
		3.100
	)
	check(not _has(a4_3, "clear") and not _has(a4_4, "clear"), "AD §4.3.4：双手握拳 Latch 锁存生效，保持握拳不连续重复触发")

	# A5: 松开一只手，再次双手握拳，可再次触发
	m.feed_frame(
		_hand(F_CURSOR, Vector2(0.3, 0.4), 0.9, "Left", true, 3.2),
		_hand(F_FIST, Vector2(0.7, 0.4), 0.9, "Right", true, 3.2),
		3.2
	)
	m.feed_frame(
		_hand(F_FIST, Vector2(0.3, 0.4), 0.9, "Left", true, 3.3),
		_hand(F_FIST, Vector2(0.7, 0.4), 0.9, "Right", true, 3.3),
		3.3
	)
	var a5_2: Array = m.feed_frame(
		_hand(F_FIST, Vector2(0.3, 0.4), 0.9, "Left", true, 3.333),
		_hand(F_FIST, Vector2(0.7, 0.4), 0.9, "Right", true, 3.333),
		3.333
	)
	check(_has(a5_2, "clear"), "AD §4.3.4：松手重置 Latch 后，再次双手握拳 2 帧成功再次触发 clear")

	# A6: 彻底废除右掌 dwell 清空
	m.reset()
	var dwell_cleared := false
	for i: int in 50:
		var t: float = 10.0 + float(i) * 0.033
		var its: Array = m.feed_frame({}, _hand(F_PALM, Vector2(0.7, 0.5), 0.9, "Right", true, t), t)
		if _has(its, "clear"):
			dwell_cleared = true
			break
	check(not dwell_cleared, "AD §4.3.4：彻底废除右掌 dwell 清空，右掌静止 1.5s 绝不触发 clear")

	# ---- A7（批次 AD 审查回修 P2-7①，2026-09-28）：clear 后 CLEAR_FLIP_GUARD_SEC(0.35s)
	# 翻转冷却——窗内完整翻腕序列零 undo/redo，超窗后翻腕恢复可达。旧值留痕：本批前该冷却
	# 门**零断言覆盖**（常量漂移/门被删均不判红）；下面先源锚锁常量，再行为面双段验证。 ----
	var gm_src_a7: String = FileAccess.get_file_as_string(GM_SRC)
	check(gm_src_a7.contains("CLEAR_FLIP_GUARD_SEC := 0.35"),
		"P2-7① 源锚：CLEAR_FLIP_GUARD_SEC=0.35（clear 防误翻冷却窗常量在案）")
	m.reset()
	# 双手握拳 clear @20.033 → 双侧 flip_cooldown_until = 20.033+0.35 = 20.383
	var a7_clr1: Array = m.feed_frame(_hand(F_FIST, Vector2(0.3, 0.4), 0.9, "Left", true, 20.0),
		_hand(F_FIST, Vector2(0.7, 0.4), 0.9, "Right", true, 20.0), 20.0)
	var a7_clr2: Array = m.feed_frame(_hand(F_FIST, Vector2(0.3, 0.4), 0.9, "Left", true, 20.033),
		_hand(F_FIST, Vector2(0.7, 0.4), 0.9, "Right", true, 20.033), 20.033)
	check(not _has(a7_clr1, "clear"), "P2-7① 前置：双手握拳第 1 帧确认期零 clear（2 帧门）")
	check(_has(a7_clr2, "clear"), "P2-7① 前置：双手握拳第 2 帧 clear 恰一次（冷却起点 20.033）")
	# 冷却窗内（<20.383）完整翻腕序列（锁 2 帧 + 翻 2 帧）：_feed_flip 冷却早退 → 零 flip → 零 pending
	var a7_guard: Array = []
	a7_guard.append_array(m.feed_frame(_hand(F_THREE_STRICT, Vector2(0.3, 0.4), 0.9, "Left", true, 20.066, 5.0), {}, 20.066))
	a7_guard.append_array(m.feed_frame(_hand(F_THREE_STRICT, Vector2(0.3, 0.4), 0.9, "Left", true, 20.100, 5.0), {}, 20.100))
	a7_guard.append_array(m.feed_frame(_hand(F_THREE_STRICT, Vector2(0.3, 0.4), 0.9, "Left", false, 20.133, 120.0), {}, 20.133))
	a7_guard.append_array(m.feed_frame(_hand(F_THREE_STRICT, Vector2(0.3, 0.4), 0.9, "Left", false, 20.166, 120.0), {}, 20.166))
	check_eq((m.get("_pending_flip") as Dictionary).is_empty(), true,
		"P2-7①：clear 后 0.35s 冷却窗内完整翻腕序列 → _pending_flip 空（冷却早退把锁/翻整段挡下）")
	check(not _has(a7_guard, "undo") and not _has(a7_guard, "redo"),
		"P2-7①：冷却窗内翻腕零 undo/redo")
	# 推过本应的解算点（20.166+1.2=21.366）仍零 undo——若冷却门被删，pending 会在此帧解算出 undo
	var a7_after: Array = m.feed_frame({}, {}, 21.5)
	check(not _has(a7_after, "undo") and not _has(a7_after, "redo")
			and (m.get("_pending_flip") as Dictionary).is_empty(),
		"P2-7①：推到 21.5（>本应解算点 21.366）仍零 undo/redo 且 pending 空（冷却门真守卫，非空转）")
	# 超窗可达：冷却过期后同姿势翻腕 → pending 建立 → 窗口闭合解算 undo
	var a7_o1: Array = m.feed_frame(_hand(F_THREE_STRICT, Vector2(0.3, 0.4), 0.9, "Left", true, 21.6, 5.0), {}, 21.6)
	var a7_o2: Array = m.feed_frame(_hand(F_THREE_STRICT, Vector2(0.3, 0.4), 0.9, "Left", true, 21.633, 5.0), {}, 21.633)
	var a7_o3: Array = m.feed_frame(_hand(F_THREE_STRICT, Vector2(0.3, 0.4), 0.9, "Left", false, 21.666, 120.0), {}, 21.666)
	var a7_o4: Array = m.feed_frame(_hand(F_THREE_STRICT, Vector2(0.3, 0.4), 0.9, "Left", false, 21.700, 120.0), {}, 21.700)
	check(not _has(a7_o1, "undo") and not _has(a7_o2, "undo") and not _has(a7_o3, "undo") \
			and not _has(a7_o4, "undo"),
		"P2-7①：超窗翻腕四帧过程零 undo（翻转意图先入 pending，不即时解算）")
	check(not (m.get("_pending_flip") as Dictionary).is_empty(),
		"P2-7①：超窗翻腕 → _pending_flip 建立（冷却过期后翻转通路恢复）")
	var a7_mid: Array = m.feed_frame({}, {}, 22.0)
	check(not _has(a7_mid, "undo"), "P2-7①：窗口内（22.0-21.7=0.3≤1.2）不抢跑解算")
	var a7_end: Array = m.feed_frame({}, {}, 22.95)
	check(_has(a7_end, "undo"),
		"P2-7①：超窗后（22.95-21.7=1.25>1.2）窗口闭合 → undo 可达（冷却与解算解耦双段验证）")

	# ---- A8（P2-7②）：_exit_countdown（退出倒数）期双手握拳零 clear——倒数期手势清空冻结，
	# 倒数结束同姿势恢复可达（门为唯一阻断因；旧值留痕：本批前该门零断言覆盖）。 ----
	m.reset()
	m.set_exit_countdown(true)
	var a8_hold: Array = []
	for i: int in 4:
		var t8: float = 30.0 + float(i) * 0.033
		a8_hold.append_array(m.feed_frame(_hand(F_FIST, Vector2(0.3, 0.4), 0.9, "Left", true, t8),
			_hand(F_FIST, Vector2(0.7, 0.4), 0.9, "Right", true, t8), t8))
	check(not _has(a8_hold, "clear"),
		"P2-7②：_exit_countdown 期双手握拳 4 帧零 clear（倒数期冻结；无门则第 2 帧即触发）")
	m.set_exit_countdown(false)
	var a8_r1: Array = m.feed_frame(_hand(F_FIST, Vector2(0.3, 0.4), 0.9, "Left", true, 30.133),
		_hand(F_FIST, Vector2(0.7, 0.4), 0.9, "Right", true, 30.133), 30.133)
	var a8_r2: Array = m.feed_frame(_hand(F_FIST, Vector2(0.3, 0.4), 0.9, "Left", true, 30.166),
		_hand(F_FIST, Vector2(0.7, 0.4), 0.9, "Right", true, 30.166), 30.166)
	check(not _has(a8_r1, "clear") and _has(a8_r2, "clear"),
		"P2-7②：倒数结束后同姿势 2 帧 clear 恰一次可达（倒数门为唯一阻断因，非空转）")

	# ---- A9（P2-7③）：flip_locked（翻转前置锁）期双手握拳 clear 挂起——锁窗内零 clear，
	# 锁窗过期（FLIP_WINDOW_SEC=1.0s）自动解锁后同姿势恢复可达（旧值留痕：本批前该挂起门
	# 零断言覆盖）。 ----
	m.reset()
	m.feed_frame(_hand(F_THREE_STRICT, Vector2(0.3, 0.4), 0.9, "Left", true, 40.0, 5.0), {}, 40.0)
	var a9_l2: Array = m.feed_frame(_hand(F_THREE_STRICT, Vector2(0.3, 0.4), 0.9, "Left", true, 40.033, 5.0), {}, 40.033)
	check(not _has(a9_l2, "undo"), "P2-7③ 前置：三指锁定 2 帧仅 lock 不发 flip（前置确认非翻转）")
	var a9_sd: Dictionary = m.get("_side") as Dictionary
	check(bool((a9_sd["left"] as Dictionary).get("flip_locked", false)),
		"P2-7③ 前置：左手 flip_locked=true（挂起门触发前提在案）")
	# 锁窗内（≤40.033+1.0=41.033）双手握拳 → 挂起 → 零 clear
	var a9_hold: Array = []
	var a9_times: Array = [40.066, 40.100, 40.133, 40.5]
	for i: int in a9_times.size():
		var t9: float = float(a9_times[i])
		a9_hold.append_array(m.feed_frame(_hand(F_FIST, Vector2(0.3, 0.4), 0.9, "Left", true, t9, 5.0),
			_hand(F_FIST, Vector2(0.7, 0.4), 0.9, "Right", true, t9, 5.0), t9))
	check(not _has(a9_hold, "clear"),
		"P2-7③：flip_locked 窗内双手握拳 4 帧零 clear（挂起生效；无门则第 2 帧即触发）")
	# 锁窗过期（>41.033）→ _feed_flip 自动解锁 → 挂起解除 → 2 帧 clear 可达
	var a9_r1: Array = m.feed_frame(_hand(F_FIST, Vector2(0.3, 0.4), 0.9, "Left", true, 41.066, 5.0),
		_hand(F_FIST, Vector2(0.7, 0.4), 0.9, "Right", true, 41.066, 5.0), 41.066)
	var a9_r2: Array = m.feed_frame(_hand(F_FIST, Vector2(0.3, 0.4), 0.9, "Left", true, 41.100, 5.0),
		_hand(F_FIST, Vector2(0.7, 0.4), 0.9, "Right", true, 41.100, 5.0), 41.100)
	check(not _has(a9_r1, "clear") and _has(a9_r2, "clear"),
		"P2-7③：锁窗过期自动解锁后 2 帧 clear 恰一次可达（挂起门为唯一阻断因，非空转）")

	# =========================================================================
	# 段 B：严格三指批量删除（spec §4.3.2）
	# =========================================================================
	print("--- 段 B：严格三指批量删除 ---")
	m.reset()

	# B1: 食中无名同时伸直且小指弯曲收拢（<=0.35），连续 2 帧触发 delete
	var b1_1: Array = m.feed_frame(_hand(F_THREE_STRICT, Vector2(0.3, 0.4), 0.9, "Left", true, 100.0), {}, 100.0)
	check(not _has(b1_1, "delete"), "AD §4.3.2：严格三指第 1 帧处于确认期，不触发 delete")
	var b1_2: Array = m.feed_frame(_hand(F_THREE_STRICT, Vector2(0.3, 0.4), 0.9, "Left", true, 100.033), {}, 100.033)
	check(_has(b1_2, "delete"), "AD §4.3.2：严格三指连续 2 帧稳定触发 delete")

	# B2: 小指未收拢（0.50），绝不判为三指删除
	m.reset()
	var b2_1: Array = m.feed_frame(_hand(F_THREE_LOOSE_PINKY, Vector2(0.3, 0.4), 0.9, "Left", true, 110.0), {}, 110.0)
	var b2_2: Array = m.feed_frame(_hand(F_THREE_LOOSE_PINKY, Vector2(0.3, 0.4), 0.9, "Left", true, 110.033), {}, 110.033)
	var b2_3: Array = m.feed_frame(_hand(F_THREE_LOOSE_PINKY, Vector2(0.3, 0.4), 0.9, "Left", true, 110.066), {}, 110.066)
	check(not _has(b2_1, "delete") and not _has(b2_2, "delete") and not _has(b2_3, "delete"),
		"AD §4.3.2：小指未收拢（>0.35）绝不触发三指删除")

	# =========================================================================
	# 段 C：单手翻转撤销侧立保护（spec §4.3.3）
	# =========================================================================
	print("--- 段 C：单手翻转撤销侧立保护 ---")
	m.reset()

	# C1: 单手左手三指朝镜锁定（连续 2 帧），第 3~4 帧翻转
	m.feed_frame(_hand(F_THREE_STRICT, Vector2(0.3, 0.4), 0.9, "Left", true, 200.0, 5.0), {}, 200.0)
	m.feed_frame(_hand(F_THREE_STRICT, Vector2(0.3, 0.4), 0.9, "Left", true, 200.033, 5.0), {}, 200.033)
	m.feed_frame(_hand(F_THREE_STRICT, Vector2(0.3, 0.4), 0.9, "Left", false, 200.066, 120.0), {}, 200.066)
	var c1_4: Array = m.feed_frame(_hand(F_THREE_STRICT, Vector2(0.3, 0.4), 0.9, "Left", false, 200.100, 120.0), {}, 200.100)
	# 此时产生 flip，存入 _pending_flip，但因为单手翻转需等待 SAME_WINDOW_SEC(1.2s) 判断是否有对侧翻转配对
	check(not _has(c1_4, "undo"), "C1 前置：翻转当帧放入 _pending_flip，不立即输出 undo")

	# C2: 侧立丢帧：在随后帧（如 200.15s），左手侧立导致丢帧（空手或 is_detected=false）触发 _teardown_side
	var c2_drop: Array = m.feed_frame({}, {}, 200.150)
	# 检查 _pending_flip 在侧立丢帧后是否被错误清空
	# 如果没有被清空，在 200.100 + 1.25 = 201.35s 推进时，应该能稳定输出 undo！
	var c3_out: Array = m.feed_frame({}, {}, 201.350)
	check(_has(c3_out, "undo"), "AD §4.3.3：单手翻转侧立丢帧期间 _pending_flip 受保护不被清空，到期成功输出 undo")

	# =========================================================================
	# 段 D：关卡旋转模式显式有界拖拽与自然退出（spec §4.3.1）
	# =========================================================================
	print("--- 段 D：关卡旋转模式显式有界拖拽与自然退出 ---")
	var router: Node = root.get_node_or_null("GestureRouter")
	check(router != null, "GestureRouter autoload 节点在树内就位")
	# 批次 AD 终验补强 F-2①（2026-09-28）：把关卡拉到「旋转链可观测」环境——Game 直接置态
	# （test_aa_gesture_remap 段 7 同款 `game.set("_state", …)`，零场景切换/零存档写入）+
	# MockLevel 顶上 _current_scene；段末逐项还原，段 E 及后续段零干扰。
	var game_d: Node = root.get_node_or_null("Game")
	var prev_state_d: int = int(game_d.current_state())
	var prev_scene_d: Variant = game_d.get("_current_scene")
	var mlv: MockLevel = MockLevel.new()
	mlv.name = "MockLevel"
	root.add_child(mlv)
	game_d.set("_current_scene", mlv)
	game_d.set("_state", int(game_d.State.LEVEL))
	check_eq(int(game_d.current_state()), int(game_d.State.LEVEL),
		"F-2① 前置：Game 置 LEVEL 态（_semantic_zone=level，旋转链可观测）")
	check_eq(game_d.get_current_scene(), mlv, "F-2① 前置：_current_scene=MockLevel（_level() 认证在位）")
	if router != null:
		router.call("reset_runtime")
		router.set("_active_panel", null)
		router.set("_level_mode", "SELECT_ARMED")

		# 创建一个虚拟 Panel 模拟绑定视口
		var mock_panel: Control = Control.new()
		mock_panel.name = "MockMainView"
		mock_panel.add_to_group("gesture_panel")
		mock_panel.position = Vector2(100, 100)
		mock_panel.size = Vector2(800, 500)
		root.add_child(mock_panel)

		# 设置激活面板
		router.call("_set_active_panel", mock_panel)
		check_eq(router.get("_active_panel"), mock_panel, "mock_panel 成功绑定为激活视口")
		check_eq(router.get("_level_mode"), "SELECT_ARMED", "初始状态为 SELECT_ARMED")

		# D1: 在视口空白处（非块）二指按下，进入 ORBIT_PENDING，记录 _orbit_anchor_pos
		var press_pos := Vector2(200, 200)
		router.set("_last_two_pos", {"left": press_pos})
		router.call("_on_level_two_down_left", press_pos, null)

		check_eq(String(router.get("_level_mode")), "ORBIT_PENDING",
			"AD §4.3.1：视口空白处二指按下不立即进入 ORBIT，而是进入 ORBIT_PENDING")
		var anchor_val: Variant = router.get("_orbit_anchor_pos")
		var anchor_v2: Vector2 = anchor_val if (anchor_val is Vector2) else Vector2.INF
		check_eq(anchor_v2, press_pos,
			"AD §4.3.1：记录 _orbit_anchor_pos 为按下起点")

		var vp_sz: Vector2 = router.call("_content", Vector2.ONE)

		# D2: 微小移动（<= 15px，例如移动 6px 水平）依然保持 ORBIT_PENDING，不触发旋转
		var small_move := press_pos + Vector2(6.0, 0.0) # length = 6.0px <= 15.0px
		router.call("_on_two_move", {"side": "left", "pos": small_move / vp_sz})
		check_eq(String(router.get("_level_mode")), "ORBIT_PENDING",
			"AD §4.3.1：位移 <= 15px 时保持 ORBIT_PENDING，不进入 ORBIT")
		check_eq(mlv.rot_calls.size(), 0, "P2-1：未越阈帧零旋转（准备态拖动不施加 Δ）")

		# D3: 移动超过 15px（例如移动 20px），正式进入 ORBIT
		var large_move := press_pos + Vector2(20.0, 0.0) # length = 20.0px > 15.0px
		router.call("_on_two_move", {"side": "left", "pos": large_move / vp_sz})
		check_eq(String(router.get("_level_mode")), "ORBIT",
			"AD §4.3.1：位移 > 15px 时正式切换为 ORBIT 模式")

		# ---- D3b（批次 AD 终验补强 F-2① / P2-1，2026-09-28）：越阈帧零阶跃 ----
		# 旧值留痕：P2-1 前越阈帧直调 `_orbit_apply_move(now_pos)`，把「压下点→越阈点」的 20px
		# 全量位移当单帧 Δ 施加 → 起手即一次可见的单帧阶跃旋转；本批前该回修**零回归断言锚定**
		# （实证：P2-1/P2-4/P2-5 三处一并回退后全量仍 159/159 全绿）。断言三段：越阈当帧零旋转、
		# 基准重置到越阈点、随后续帧按帧间 Δ 恰驱动一次。
		check_eq(mlv.rot_calls.size(), 0,
			"P2-1：越阈当帧零旋转（只立 Δ 基准不施加；旧行为=当帧 20px 阶跃即判红）")
		var last_v_d: Variant = router.get("_orbit_last_pos")
		check_eq(last_v_d if (last_v_d is Vector2) else Vector2.INF, large_move,
			"P2-1：越阈当帧 Δ 基准重置到越阈点（后续帧按帧间位移平滑驱动）")
		var next_move_d := large_move + Vector2(10.0, 0.0)
		router.call("_on_two_move", {"side": "left", "pos": next_move_d / vp_sz})
		check_eq(mlv.rot_calls.size(), 1,
			"P2-1：越阈后首帧 → 恰一次 orbit_rotate_panel（通路可达，非空转假绿）")
		check(mlv.rot_calls.size() == 1 and (mlv.rot_calls[0] as Vector2).is_equal_approx(Vector2(10.0, 0.0)),
			"P2-1：后续帧旋转量 = 帧间 Δ(10px)，绝非压下点起算的 30px")

		# D4: 自然退出：左手松开中指（two_up），立即退出 ORBIT 平滑回到 SELECT_ARMED
		router.call("_on_two_up", {"side": "left", "pos": large_move / vp_sz})
		check_eq(String(router.get("_level_mode")), "SELECT_ARMED",
			"AD §4.3.1：松开中指立即自然退出 ORBIT，平滑回到 SELECT_ARMED")

		# D5: 重新测试进入 ORBIT_PENDING 后直接松手，自然回到 SELECT_ARMED
		router.set("_last_two_pos", {"left": press_pos})
		router.call("_on_level_two_down_left", press_pos, null)
		check_eq(String(router.get("_level_mode")), "ORBIT_PENDING", "再次按下进入 ORBIT_PENDING")
		router.call("_on_two_up", {"side": "left", "pos": press_pos / vp_sz})
		check_eq(String(router.get("_level_mode")), "SELECT_ARMED", "未越阈直接松手，自然退回 SELECT_ARMED")

		mock_panel.queue_free()
		router.call("reset_runtime")

	# 批次 AD 终验补强 F-2① 收尾卫生：Game 态/当前场景逐项还原，MockLevel 释放（段 E 起零残留）
	game_d.set("_current_scene", prev_scene_d)
	game_d.set("_state", prev_state_d)
	mlv.queue_free()
	check_eq(int(game_d.current_state()), prev_state_d, "F-2① 收尾：Game 态还原到测前值")
	check(game_d.get("_current_scene") == prev_scene_d,
		"F-2① 收尾：_current_scene 还原到测前值")

	# =========================================================================
	# 段 E：悬停光晕轻量合成注入与立绘点击避让修复（spec §4.3.5）
	# =========================================================================
	print("--- 段 E：悬停光晕轻量合成注入与立绘点击避让修复 ---")
	# E1: 检查 level_scene.tscn 文件文本中的配置
	var tscn_content: String = FileAccess.get_file_as_string(LEVEL_SCENE_PATH)
	check(tscn_content.find("anchor_left = 0.115") != -1 or tscn_content.find("anchor_left = 0.1150") != -1,
		"AD §4.3.5：level_scene.tscn 中 MainView 锚点 anchor_left 微调收窄至 0.115 避让立绘")

	# E2: 实例化 level_scene，检查 WitnessPortrait 的属性与点击交互
	var lvl_packed: PackedScene = load(LEVEL_SCENE_PATH) as PackedScene
	check(lvl_packed != null, "level_scene.tscn 加载成功")
	if lvl_packed != null:
		var lvl: Node = lvl_packed.instantiate()
		root.add_child(lvl)
		await process_frame

		var wp: TextureRect = lvl.get_node_or_null("WitnessPortrait") as TextureRect
		check(wp != null, "WitnessPortrait 节点存在")
		if wp != null:
			check_eq(int(wp.mouse_filter), int(Control.MOUSE_FILTER_STOP),
				"AD §4.3.5：WitnessPortrait 的 mouse_filter 恢复为 MOUSE_FILTER_STOP(0)")
			check(wp.gui_input.is_connected(Callable(lvl, "_on_witness_gui_input")) or wp.gui_input.get_connections().size() > 0,
				"AD §4.3.5：WitnessPortrait.gui_input 已连接点击事件")

			# 模拟在 WitnessPortrait 上点击左键
			var mb := InputEventMouseButton.new()
			mb.button_index = MOUSE_BUTTON_LEFT
			mb.pressed = true
			mb.position = Vector2(10, 10)
			# ---- E2b（批次 AD 终验补强 F-2③ / P2-5 立绘锁门，2026-09-28）----
			# 旧值留痕：P2-5 前 WitnessPortrait.gui_input 直连接口缺 `_input_locked` 门（MainView
			# 分流入口有锁、直连入口裸奔）→ 成功动画锁定期点立绘仍会弹泡；本批前该回修**零回归
			# 断言锚定**（实证三处一并回退仍 159/159 全绿）。断言=锁态 emit 左键按下气泡不弹，
			# 解锁后同输入对照弹（下面既有 AD §4.3.5 断言即对照段，原文不动）。
			lvl.set("_input_locked", true)
			check_eq(bool(lvl.call("is_input_locked")), true, "F-2③ 前置：_input_locked=true")
			var open_pre8: bool = bool(lvl.get("_witness_bubble_open"))
			wp.gui_input.emit(mb)
			check_eq(bool(lvl.get("_witness_bubble_open")), open_pre8,
				"F-2③（P2-5）：_input_locked=true 点立绘 → 气泡不弹（直连入口锁门在位；无门则弹=判红）")
			lvl.set("_input_locked", false)
			var bubble: Label = lvl.get_node_or_null("WitnessBubble") as Label
			var was_open: bool = bool(lvl.get("_witness_bubble_open"))
			wp.gui_input.emit(mb)
			check_eq(bool(lvl.get("_witness_bubble_open")), not was_open,
				"AD §4.3.5：点击 WitnessPortrait 成功触发 _toggle_witness_bubble 切换气泡显示")

		lvl.queue_free()

	# ---- E3（批次 AD 终验补强 F-2② / P2-4 手别仲裁，2026-09-28）----
	# 旧值留痕：P2-4 前 synth_motion 注入位直取本条 cursor_move 的 cm_side——feed_frame 恒先左
	# 后右，双手同帧双活跃时末位右手恒覆盖引擎指针 → 左手正悬停的控件 hover_glow 点不亮；
	# 本批前该仲裁**零回归断言锚定**（实证三处一并回退仍 159/159 全绿）。
	# 判据用**刷新前**的双侧时刻（l_pre/r_pre）：左手帧先派发立时间戳，右手帧读到 l_pre>r_pre
	# → 取左手位；单手（右手独占）l_pre=-1 不满足 → 仍取右手位（单手场景零变化）。
	var layer3: MockSynthLayer = MockSynthLayer.new()
	router.call("reset_runtime")
	router.call("set_cursor_layer", layer3)
	router.set("_last_real_mouse_time", -1.0e9)   # 让位窗判据钉死为「无真实鼠标」
	var nL3 := Vector2(0.25, 0.35)
	var nR3 := Vector2(0.75, 0.65)
	# 双手同帧双活跃（严格按 feed_frame 恒先左后右的派发次序）
	router.call("_dispatch", {"type": "cursor_move", "side": "left", "pos": nL3})
	layer3.motions.clear()
	router.call("_dispatch", {"type": "cursor_move", "side": "right", "pos": nR3})
	check_eq(layer3.motions.size(), 1, "F-2② 前置：右手帧恰注入 1 条 synth_motion")
	check(layer3.motions.size() == 1
			and (layer3.motions[0] as Vector2).is_equal_approx(router.call("_content", nL3)),
		"F-2②：双手同帧双活跃 → 注入位=左手位（末位右手不覆盖；旧码 cm_side 直取落右手位=判红）")
	# 单手场景零变化：复位后只有右手在场 → 注入位仍为右手位
	router.call("reset_runtime")
	layer3.motions.clear()
	router.call("_dispatch", {"type": "cursor_move", "side": "right", "pos": nR3})
	check(layer3.motions.size() == 1
			and (layer3.motions[0] as Vector2).is_equal_approx(router.call("_content", nR3)),
		"F-2②：单手（右手独占）→ 注入位=右手位（单手场景零变化）")
	router.call("set_cursor_layer", null)
	router.call("reset_runtime")

	print("--- 专项测试全部断言完成 ---")
	finish()
