extends "res://tests/test_base.gd"
## 批次 AC 4A/4B（2026-09-27）专项回归：
##   4A（spec §4.6-3/§4.6-4/§4.6-7）手势映射层重构与退出追踪器加固——段 1~4；
##   4B（spec §4.6-1/2/4/6/8）关卡手势交互重构与键鼠焦点隔离——段 5（源契约锚，运行时
##   行为由 test_t_level_mode / test_w_gesture_level / test_y_subtract_pen /
##   test_x_gesture_remap / test_t_cursor_filter / test_aa_pointer_stuck 各自承载）。
## 四段：
##   段 1（§4.6-3）**双手协同推拉/间距缩放**：双手同在 palm（或 three）且掌面朝镜时——
##       双掌间距拉开 >10% 连续 2 帧 → zoom_begin + zoom_step(dir=+1) + **zoom_in** 动作事件；
##       双掌靠拢 → dir=−1 + **zoom_out**；双掌推近（palm_size 增）同走间距/面积双判据取大者；
##       **单手一律零缩放**（`zoom_in`/`zoom_out`/`zoom_step`/`zoom_begin` 全零——旧「单手翻掌/
##       横向移动误触发缩放」根除的红锁）；收掌（任一四指 <0.40）→ 恰一次 zoom_end；
##       双手静止抖动（±2%）→ 零 zoom_begin/零 zoom_step（10% 门 + 2 帧确认 + 基准跟随三重兜底）。
##   段 2（§4.6-4）**至少三指翻转撤销/重做**：左手/右手伸三指（食+中+无名，小指微曲，
##       `[0.1,0.9,0.9,0.9,0.1]`）翻转 → 分别触发 undo / redo（旧 `cls=="palm"` 门要求四指
##       全伸 + 小指 >0.70，此姿势永不锁定=红锁）；四指 palm 翻转语义零回归（对照段）。
##   段 3（§4.6-4）**左三指删除后翻转防误触冷却**：`suppress_flip_after_delete("left", now)`
##       施加 DELETE_FLIP_GUARD_SEC（0.6s）——冷却期内同侧三指翻转零 undo；冷却过期后
##       重锁再翻转 undo 照常可达（不毁语义可用性）；对侧（right）不受影响（反向护栏）。
##   段 4（§4.6-7）**2.0s 侧立丢帧容忍**：ExitGestureTracker 完整 4 次同翻序列中注入 1.5s
##       离场空窗 → 倒数不重置并成功在第 4 翻 exit_confirmed（旧 0.8s 档必红）；
##       + 常量断言 HAND_LOST_CANCEL_SEC==2.0 与 gesture_map 侧「翻转手侧立盲区保留 pending」
##       配对护栏（倒数期翻转手短暂掉出 → 对侧同窗内翻 → exit_flip 仍成对）。
##   夹具口径：map 级合成手 dict + now 显式注入（零真时钟/零摄像头/零 user://）；段 4 后半
##       直调 map（纯逻辑层），tracker 部分纯逻辑直调。断言纪律：Variant 直调、字典 .get 缺省防御。

const MAP_PATH := "res://scripts/gesture_map.gd"
const TRACKER_PATH := "res://scripts/gesture_exit_tracker.gd"

# 手指通道夹具
const F_THREE := [0.1, 0.9, 0.9, 0.9, 0.1]      # 食+中+无名（小指收）——「至少三指」翻转/双缩放姿势
const F_FOUR := [0.1, 0.9, 0.9, 0.9, 0.9]       # 四指（palm）
const F_CURSOR := [0.1, 0.9, 0.1, 0.1, 0.1]
const F_REST := [0.1, 0.1, 0.1, 0.1, 0.1]

## 手 dict 构造（test_gesture_map._hand 同构；tip 可控以驱动双掌间距）
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
	return {"gesture": "", "gesture_id": 0, "confidence": conf,
		"hand_x": tip.x, "hand_y": tip.y, "hand_z": 0.0,
		"hand_rotation_x": roll, "hand_rotation_y": 0.0, "hand_rotation_z": 0.0,
		"fingers": fingers, "pinch_distance": 0.5, "hand_index": 0 if label == "Left" else 1,
		"handedness": label, "landmarks": lm, "fps": 30.0, "is_detected": true,
		"timestamp": ts, "palm_size": ps}

## 双手同帧喂帧（左手 tip / 右手 tip / 双掌 palm_size 全可控——双缩放双判据驱动）
func _fb(m: Variant, lf: Array, rf: Array, ltip: Vector2, rtip: Vector2,
		lps: float, rps: float, now: float, facing: bool = true) -> Array:
	return m.feed_frame(
		_hand(0.9, lf, 5.0, facing, "Left", lps, ltip, now),
		_hand(0.9, rf, 5.0, facing, "Right", rps, rtip, now), now)

## 单手喂帧（右手侧空 → 右侧照常 teardown，不影响左语义）
func _fl(m: Variant, fingers: Array, ps: float, tip: Vector2, now: float) -> Array:
	return m.feed_frame(_hand(0.9, fingers, 5.0, true, "Left", ps, tip, now), {}, now)

func _types(intents: Array) -> Array:
	var out: Array = []
	for it: Variant in intents:
		if typeof(it) == TYPE_DICTIONARY:
			out.append(String((it as Dictionary).get("type", "")))
	return out

func _has(intents: Array, t: String) -> bool:
	return _types(intents).has(t)

func _count(intents: Array, t: String) -> int:
	var n := 0
	for it: Variant in intents:
		if typeof(it) == TYPE_DICTIONARY and String((it as Dictionary).get("type", "")) == t:
			n += 1
	return n

## 某类型全部意图的 dir 序列（缩放方向断言用）
func _dirs(intents: Array, t: String) -> Array:
	var out: Array = []
	for it: Variant in intents:
		if typeof(it) == TYPE_DICTIONARY and String((it as Dictionary).get("type", "")) == t:
			out.append(int((it as Dictionary).get("dir", 0)))
	return out

func _new_map() -> Variant:
	return load(MAP_PATH).new()

# ==================== 段 1（§4.6-3）：双手协同推拉/间距缩放 ====================

## 双掌张开态就位（双 palm 双帧确认；间距基准 = 左右 tip 归一距 0.20）
func _dual_ready(m: Variant, t0: float) -> Array:
	var acc: Array = []
	acc.append_array(_fb(m, F_FOUR, F_FOUR, Vector2(0.30, 0.4), Vector2(0.50, 0.4), 0.20, 0.20, t0))
	acc.append_array(_fb(m, F_FOUR, F_FOUR, Vector2(0.30, 0.4), Vector2(0.50, 0.4), 0.20, 0.20, t0 + 0.033))
	return acc

func _seg1_dual_zoom() -> void:
	# 1a. 双掌间距拉开 → zoom_begin + zoom_step(dir=+1) + zoom_in 动作事件
	var m: Variant = _new_map()
	var a: Array = _dual_ready(m, 10.0)
	check_eq(_count(a, "zoom_begin"), 0, "1a 前置：双掌就位帧零 zoom_begin（10% 门未越）")
	# 间距 0.20 → 0.30（+50%），逐帧推进：第 2 帧越 10% 门即进缩放态
	for i: int in 6:
		var k: float = 0.20 + 0.02 * float(i + 1)
		a.append_array(_fb(m, F_FOUR, F_FOUR,
			Vector2(0.5 - k * 0.5, 0.4), Vector2(0.5 + k * 0.5, 0.4), 0.20, 0.20, 10.066 + 0.033 * i))
	check_eq(_count(a, "zoom_begin"), 1, "1a：双掌间距拉开 >10% 确认帧满 → zoom_begin 恰一次")
	check(_count(a, "zoom_step") > 0, "1a：跨 ZOOM_STEP_LN 台阶 → zoom_step 派发")
	check(_count(a, "zoom_in") > 0, "1a：拉开（放大）→ 显式动作事件 zoom_in（本批新词汇）")
	check_eq(_count(a, "zoom_out"), 0, "1a：拉开零 zoom_out（方向单一真值）")
	check(_dirs(a, "zoom_in").has(1), "1a：zoom_in.dir=+1（双手拉开/推近=放大）")
	check_eq(_count(a, "clear"), 0, "1a：双缩放期零 clear（双侧 dwell 已作废；与清空互斥）")
	# 收掌（双掌任一四指 <0.40）→ 恰一次 zoom_end
	var e: Array = _fb(m, F_REST, F_REST, Vector2(0.30, 0.4), Vector2(0.50, 0.4), 0.20, 0.20, 10.50)
	check_eq(_count(e, "zoom_end"), 1, "1a：收掌 → zoom_end 恰一次（双通道统一收尾）")

	# 1b. 双掌靠拢 → dir=−1 + zoom_out
	m.reset()
	var b: Array = _dual_ready(m, 20.0)
	for i: int in 6:
		var k2: float = 0.20 - 0.022 * float(i + 1)   # 0.178/0.156/0.134…（相对 0.20 缩 >10%）
		b.append_array(_fb(m, F_FOUR, F_FOUR,
			Vector2(0.5 - k2 * 0.5, 0.4), Vector2(0.5 + k2 * 0.5, 0.4), 0.20, 0.20, 20.066 + 0.033 * i))
	check_eq(_count(b, "zoom_begin"), 1, "1b：双掌靠拢 >10% → zoom_begin 恰一次")
	check(_count(b, "zoom_out") > 0, "1b：靠拢（缩小）→ 显式动作事件 zoom_out")
	check(_dirs(b, "zoom_out").has(-1), "1b：zoom_out.dir=−1（双手靠拢/拉远=缩小）")

	# 1c. 双掌同步推近镜头（palm_size +25%，间距不变）→ 面积判据接管 → 放大
	m.reset()
	var c: Array = _dual_ready(m, 30.0)
	for i: int in 8:
		c.append_array(_fb(m, F_FOUR, F_FOUR, Vector2(0.30, 0.4), Vector2(0.50, 0.4),
			0.20 + 0.01 * float(i + 1), 0.20 + 0.01 * float(i + 1), 30.066 + 0.033 * i))
	check(_count(c, "zoom_begin") == 1, "1c：双掌推近（palm_size +）→ zoom_begin（面积分量判据）")
	check(_count(c, "zoom_in") > 0, "1c：推近镜头（掌面积增大）→ zoom_in（dir=+1 口径一致）")

	# 1d. 单手（对侧全程离场）推拉 → **零缩放**（旧语义红锁：生产默认关单手掌通道）
	m.reset()
	var d: Array = []
	d.append_array(_fl(m, F_FOUR, 0.20, Vector2(0.30, 0.4), 40.0))
	d.append_array(_fl(m, F_FOUR, 0.20, Vector2(0.30, 0.4), 40.033))
	for i: int in 8:
		d.append_array(_fl(m, F_FOUR, 0.35, Vector2(0.30, 0.4), 40.066 + 0.033 * i))
	check_eq(_count(d, "zoom_begin"), 0, "1d：单手推拉零 zoom_begin（AC 4A 生产语义红锁：旧单手通道默认关）")
	check_eq(_count(d, "zoom_step"), 0, "1d：单手推拉零 zoom_step")
	check_eq(_count(d, "zoom_in") + _count(d, "zoom_out"), 0, "1d：单手推拉零 zoom_in/zoom_out 动作事件")
	check(_count(d, "palm_begin") == 1, "1d 对照：单手掌态语义照常（palm_begin 在位；仅缩放通道关）")
	# 单手横向平移（tip 大幅横移、掌面积不变）→ 同样零缩放（用户实机误触发主场景）
	m.reset()
	var d2: Array = []
	d2.append_array(_fl(m, F_FOUR, 0.20, Vector2(0.30, 0.4), 50.0))
	d2.append_array(_fl(m, F_FOUR, 0.20, Vector2(0.30, 0.4), 50.033))
	for i: int in 10:
		d2.append_array(_fl(m, F_FOUR, 0.20, Vector2(0.30 + 0.03 * float(i + 1), 0.4), 50.066 + 0.033 * i))
	check_eq(_count(d2, "zoom_step"), 0, "1d：单手横向平移零 zoom_step（AC 4A 根除的误触发主场景红锁）")

	# 1e. 双手静止（含 ±2% MediaPipe 抖动）→ 零 zoom_begin/零 zoom_step（基准跟随兜底）
	m.reset()
	var e2: Array = _dual_ready(m, 60.0)
	for i: int in 40:
		var jit: float = 0.004 if (i % 2 == 0) else -0.004   # 间距 ±2%
		var k3: float = 0.20 + jit
		e2.append_array(_fb(m, F_FOUR, F_FOUR, Vector2(0.5 - k3 * 0.5, 0.4), Vector2(0.5 + k3 * 0.5, 0.4),
			0.20 + jit, 0.20 + jit, 60.066 + 0.033 * i))
	check_eq(_count(e2, "zoom_begin"), 0, "1e：双手静止 ±2% 抖动 → 零 zoom_begin（10% 门 + 基准跟随兜底）")
	check_eq(_count(e2, "zoom_step"), 0, "1e：双手静止抖动 → 零 zoom_step（防自走缩放红锁）")

	# 1f. 双手同在但**掌面背对镜头**（facing=false）→ 不参与双缩放（进入门要求朝镜）
	m.reset()
	var f: Array = []
	f.append_array(_fb(m, F_FOUR, F_FOUR, Vector2(0.30, 0.4), Vector2(0.50, 0.4), 0.20, 0.20, 70.0, false))
	f.append_array(_fb(m, F_FOUR, F_FOUR, Vector2(0.30, 0.4), Vector2(0.50, 0.4), 0.20, 0.20, 70.033, false))
	for i: int in 6:
		var k4: float = 0.20 + 0.03 * float(i + 1)
		f.append_array(_fb(m, F_FOUR, F_FOUR, Vector2(0.5 - k4 * 0.5, 0.4), Vector2(0.5 + k4 * 0.5, 0.4),
			0.20, 0.20, 70.066 + 0.033 * i, false))
	check_eq(_count(f, "zoom_begin"), 0, "1f：双掌背对镜头（facing=false）→ 零 zoom_begin（朝镜进入门）")

	# 1g. 三指形（F_THREE：食+中+无名，小指收）同样构成双缩放资格（§4.6-3「至少三指」）
	m.reset()
	var g: Array = _dual_ready(m, 80.0)
	for i: int in 6:
		var k5: float = 0.20 + 0.025 * float(i + 1)
		g.append_array(_fb(m, F_THREE, F_THREE, Vector2(0.5 - k5 * 0.5, 0.4), Vector2(0.5 + k5 * 0.5, 0.4),
			0.20, 0.20, 80.066 + 0.033 * i))
	check(_count(g, "zoom_begin") == 1, "1g：双手三指形（palm 或 three）→ 双缩放同样成立（§4.6-3 至少三指）")
	check(_count(g, "zoom_in") > 0, "1g：三指形拉开 → zoom_in 派发")

# ==================== 段 2（§4.6-4）：至少三指翻转 → 撤销/重做 ====================

## 单侧三指翻转序列（label 侧；对侧离场）：入态 2 帧锁定 → 翻腕 2 帧 → 静默帧闭合 1.2s 窗
func _flip_seq(m: Variant, label: String, t0: float, fingers: Array, tip: Vector2) -> Array:
	var acc: Array = []
	var other := {} if label == "Left" else {}
	var h := func(roll: float, ts: float) -> Dictionary:
		return _hand(0.9, fingers, roll, true, label, 0.20, tip, ts)
	if label == "Left":
		acc.append_array(m.feed_frame(h.call(10.0, t0), null, t0))
		acc.append_array(m.feed_frame(h.call(10.0, t0 + 0.033), null, t0 + 0.033))   # 前置锁定
		acc.append_array(m.feed_frame(h.call(130.0, t0 + 0.10), null, t0 + 0.10))
		acc.append_array(m.feed_frame(h.call(130.0, t0 + 0.133), null, t0 + 0.133))  # 翻转触发
	else:
		acc.append_array(m.feed_frame(null, h.call(10.0, t0), t0))
		acc.append_array(m.feed_frame(null, h.call(10.0, t0 + 0.033), t0 + 0.033))
		acc.append_array(m.feed_frame(null, h.call(130.0, t0 + 0.10), t0 + 0.10))
		acc.append_array(m.feed_frame(null, h.call(130.0, t0 + 0.133), t0 + 0.133))
	# 静默帧（收指回 rest）推进 SAME_WINDOW_SEC(1.2s) 窗闭合 → 解算 undo/redo
	acc.append_array(m.feed_frame(
		_hand(0.9, F_REST, 5.0, true, label, 0.20, tip, t0 + 1.40) if label == "Left" else null,
		_hand(0.9, F_REST, 5.0, true, label, 0.20, tip, t0 + 1.40) if label == "Right" else null,
		t0 + 1.40))
	return acc

func _seg2_three_finger_flip() -> void:
	# 2a. 左手三指翻转 → undo（旧 cls=="palm" 门要求四指全伸 + 小指 >0.70 → 此姿势永不锁定=红锁）
	var m: Variant = _new_map()
	var a: Array = _flip_seq(m, "Left", 10.0, F_THREE, Vector2(0.30, 0.4))
	check(_has(a, "undo"), "2a：左手三指（食+中+无名）翻转 → undo（AC 4A 放宽门限红→绿）")
	check(not _has(a, "redo"), "2a：左手翻转零 redo（手别分派单一真值）")
	# 2b. 右手三指翻转 → redo
	m.reset()
	var b: Array = _flip_seq(m, "Right", 20.0, F_THREE, Vector2(0.70, 0.4))
	check(_has(b, "redo"), "2b：右手三指翻转 → redo（AC 4A 放宽门限红→绿）")
	check(not _has(b, "undo"), "2b：右手翻转零 undo")
	# 2c. 对照：四指 palm 翻转语义零回归（左 undo / 右 redo）
	m.reset()
	var c: Array = _flip_seq(m, "Left", 30.0, F_FOUR, Vector2(0.30, 0.4))
	check(_has(c, "undo"), "2c 对照：四指 palm 翻转 undo 语义零回归（旧通路不动）")
	m.reset()
	var c2: Array = _flip_seq(m, "Right", 40.0, F_FOUR, Vector2(0.70, 0.4))
	check(_has(c2, "redo"), "2c 对照：右手四指 palm 翻转 redo 语义零回归")
	# 2d. 反向护栏：仅二指（食+中）翻转不得进入翻转链（三指门仍有判别力）
	m.reset()
	var d: Array = _flip_seq(m, "Left", 50.0, [0.1, 0.9, 0.9, 0.1, 0.1], Vector2(0.30, 0.4))
	check(not _has(d, "undo") and not _has(d, "redo"),
		"2d 反向护栏：仅二指翻转零 undo/redo（至少三指门保持判别力，未被放宽过头）")

# ==================== 段 3（§4.6-4）：左三指删除后翻转防误触冷却 ====================

func _seg3_delete_flip_guard() -> void:
	var gm: Dictionary = (load(MAP_PATH) as Script).get_script_constant_map()
	check_eq(float(gm.get("DELETE_FLIP_GUARD_SEC", -1.0)), 0.6,
		"3a：DELETE_FLIP_GUARD_SEC=0.6（spec §4.6-4 定值）")
	var m: Variant = _new_map()
	check(m.has_method("suppress_flip_after_delete"), "3a：suppress_flip_after_delete(side, now) 公开接口在位")
	# 3b. 冷却期内同侧三指翻转 → 零 undo（收手瞬间手腕偏转不再误触发）
	# 前置：先建立一次真实三指翻转（证明该姿势本可触发），再显式施加删除冷却重试
	var pre: Array = _flip_seq(m, "Left", 10.0, F_THREE, Vector2(0.30, 0.4))
	check(_has(pre, "undo"), "3b 前置：无冷却时左手三指翻转 → undo 可达（对照组）")
	m.reset()
	m.call("suppress_flip_after_delete", "left", 20.0)
	var st: Dictionary = (m.get("_side") as Dictionary).get("left", {})
	check_eq(bool(st.get("flip_locked", true)), false, "3b：冷却施加即清 flip_locked")
	check_eq(int(st.get("flip_streak", -1)), 0, "3b：冷却施加即清 flip_streak")
	var cold: Array = _flip_seq(m, "Left", 20.1, F_THREE, Vector2(0.30, 0.4))
	check(not _has(cold, "undo"), "3b：冷却期内（<0.6s）三指翻转 → 零 undo（防误触红锁）")
	# 3c. 冷却过期（>0.6s）后重锁再翻转 → undo 照常可达（不毁语义可用性）
	m.reset()
	m.call("suppress_flip_after_delete", "left", 30.0)
	var warm: Array = _flip_seq(m, "Left", 31.0, F_THREE, Vector2(0.30, 0.4))
	check(_has(warm, "undo"), "3c：冷却过期（>0.6s）后重锁翻转 → undo 照常可达（可用性不毁）")
	# 3d. 反向护栏：对侧（right）不受 left 冷却影响
	m.reset()
	m.call("suppress_flip_after_delete", "left", 40.0)
	var other: Array = _flip_seq(m, "Right", 40.1, F_THREE, Vector2(0.70, 0.4))
	check(_has(other, "redo"), "3d 反向护栏：left 冷却不影响 right 翻转 → redo 照常可达")
	# 3e. 缺省 now（-1.0）：仅清前置态、不写冷却（保守处置；调用方无时钟注入时的安全语义）
	m.reset()
	m.call("suppress_flip_after_delete", "left")
	var st2: Dictionary = (m.get("_side") as Dictionary).get("left", {})
	check_eq(bool(st2.get("flip_locked", true)), false, "3e：缺省 now → 前置态照清")
	var noco: Array = _flip_seq(m, "Left", 50.0, F_THREE, Vector2(0.30, 0.4))
	check(_has(noco, "undo"), "3e：缺省 now 不写冷却 → 三指翻转 undo 照常可达（零阻挡）")

# ==================== 段 4（§4.6-7）：2.0s 侧立丢帧容忍与配对保留 ====================

func _wire_tracker(t: Variant) -> Array:
	var sig := [[], [], [], []]
	t.countdown_started.connect(func(r: int) -> void: sig[0].append(r))
	t.countdown_changed.connect(func(r: int) -> void: sig[1].append(r))
	t.countdown_cancelled.connect(func(r: String) -> void: sig[2].append(r))
	t.exit_confirmed.connect(func() -> void: sig[3].append(true))
	return sig

func _seg4_exit_tolerance() -> void:
	# 4a. 常量断言：HAND_LOST_CANCEL_SEC=2.0（旧 0.8 退役留痕）
	var tk_c: Dictionary = (load(TRACKER_PATH) as Script).get_script_constant_map()
	check_eq(float(tk_c.get("HAND_LOST_CANCEL_SEC", -1.0)), 2.0,
		"4a：HAND_LOST_CANCEL_SEC=2.0（旧 0.8s 档退役留痕）")
	# 4b. 4 次同翻序列中注入 1.5s 侧立丢手空窗 → 倒数不重置，第 4 翻仍 exit_confirmed
	var t: Variant = load(TRACKER_PATH).new()
	var sig: Array = _wire_tracker(t)
	var now := 100.0
	t.notify_flip(now)                                   # #1 → started(3)
	now += 0.6
	t.tick(now, true)
	t.notify_flip(now)                                   # #2 → changed(2)
	# 侧立盲区：1.5s 双手丢帧（> 旧 0.8s 档，< 新 2.0s 档）
	now += 0.5
	t.tick(now, false)
	now += 1.0
	t.tick(now, false)                                   # 累计离场 1.5s —— 旧 0.8s 档此处已 cancelled
	check((sig[2] as Array).is_empty(), "4b：1.5s 侧立丢手空窗不取消（旧 0.8s 档红锁）")
	now += 0.3
	t.tick(now, true)                                    # 手回正（累计离场 1.5s 内 → 未取消）
	check((sig[2] as Array).is_empty(), "4b：手回正后倒数仍在（未重置）")
	now += 0.1
	t.notify_flip(now)                                   # #3 → changed(1)
	check_eq((sig[1] as Array).size(), 2, "4b：#3 照常计数（changed 第 2 次）")
	check_eq(int(sig[1][1]), 1, "4b：#3 remaining=1（3→2→1 递减口径保持）")
	now += 0.1
	t.notify_flip(now)                                   # #4 → exit_confirmed
	check_eq((sig[3] as Array).size(), 1, "4b：第 4 次同翻 → exit_confirmed（1.5s 空窗未中断流程）")
	check((sig[2] as Array).is_empty(), "4b：全流程零 cancelled（倒数为中途归零）")

	# 4c. 配对保留护栏（map 侧）：倒数期翻转手侧立短暂掉出 → 对侧同窗内翻 → exit_flip 仍成对
	var m: Variant = _new_map()
	m.set_exit_countdown(true)
	var acc: Array = []
	# 双方入态（前置锁定）
	acc.append_array(_fb(m, F_FOUR, F_FOUR, Vector2(0.30, 0.4), Vector2(0.50, 0.4), 0.20, 0.20, 200.0))
	acc.append_array(_fb(m, F_FOUR, F_FOUR, Vector2(0.30, 0.4), Vector2(0.50, 0.4), 0.20, 0.20, 200.033))
	# 左翻触发（roll 130 连 2 帧；右保持 10）→ pending(left)
	acc.append_array(_fb(m, F_FOUR, F_FOUR, Vector2(0.30, 0.4), Vector2(0.50, 0.4), 0.20, 0.20, 200.10))
	acc.append_array(m.feed_frame(
		_hand(0.9, F_FOUR, 130.0, true, "Left", 0.20, Vector2(0.30, 0.4), 200.133),
		_hand(0.9, F_FOUR, 10.0, true, "Right", 0.20, Vector2(0.50, 0.4), 200.133), 200.133))
	acc.append_array(m.feed_frame(
		_hand(0.9, F_FOUR, 130.0, true, "Left", 0.20, Vector2(0.30, 0.4), 200.166),
		_hand(0.9, F_FOUR, 10.0, true, "Right", 0.20, Vector2(0.50, 0.4), 200.166), 200.166))
	check_eq(bool((m.get("_pending_flip") as Dictionary).is_empty()), false, "4c 前置：左翻已进 pending")
	# 左手侧立盲区掉出（1 帧）——倒数期 + 对侧仍在场 → pending 保留
	acc.append_array(m.feed_frame(null, _hand(0.9, F_FOUR, 10.0, true, "Right", 0.20,
		Vector2(0.50, 0.4), 200.20), 200.20))
	check_eq(bool((m.get("_pending_flip") as Dictionary).is_empty()), false,
		"4c：倒数期左翻手侧立掉出 → pending 保留（旧码 teardown 直清=同翻配对中断红锁）")
	# 右手在配对窗内同翻 → exit_flip 成对（计数递减）
	acc.append_array(m.feed_frame(_hand(0.9, F_FOUR, 130.0, true, "Left", 0.20,
		Vector2(0.30, 0.4), 200.70), _hand(0.9, F_FOUR, 130.0, true, "Right", 0.20,
		Vector2(0.50, 0.4), 200.70), 200.70))
	acc.append_array(m.feed_frame(_hand(0.9, F_FOUR, 130.0, true, "Left", 0.20,
		Vector2(0.30, 0.4), 200.733), _hand(0.9, F_FOUR, 130.0, true, "Right", 0.20,
		Vector2(0.50, 0.4), 200.733), 200.733))
	check(_has(acc, "exit_flip"),
		"4c：侧立盲区后对侧同窗内翻 → exit_flip 仍成对（2.0s 容忍的配对侧护栏）")

## 批次 AC 4B 段（spec §4.6-1/2/4/6/8，2026-09-27）——**静态源契约锚**（Router 源码 + level_scene
## 公开契约面）。运行时行为已在既有套件等价改写中就位并逐条验证：
##   §4.6-1/2 三态绑定与不限框旋转 → tests/test_t_level_mode.gd（⑧ 空白绑定 / T10①②③ 态迁移）
##                + tests/test_w_gesture_level.gd（段 B 移出视口矩形持续旋转 + 退出唯一途径）
##                + tests/test_y_subtract_pen.gd（段 1 显式绑定前置 + 段 4 视口隔离）
##   §4.6-4 左三指批量删除与 0.6s 冷却 → tests/test_x_gesture_remap.gd 段 5 + 本文件段 3
##   §4.6-6 右二指滑动连续减选 → tests/test_x_gesture_remap.gd 段 4（滑过已选块逐一取消）
##   §4.6-8 键鼠焦点隔离 → tests/test_t_cursor_filter.gd（空闲零注入 + show_cursor 保值）
##                + tests/test_aa_pointer_stuck.gd（真实按压期 hover 不被拽走）
## 本段补的是**「实现面在案」类锚点**：公开契约方法签名/关键分支/常量真值单点可核，
## 防未来重构把已拍板语义悄悄拆掉（与 test_aa_gesture_remap 段 5 文案-实现同源同族纪律）。
func _seg5_router_source_contracts() -> void:
	var rt_s: Variant = load("res://autoload/gesture_router.gd")
	var rt_c: Dictionary = (rt_s as Script).get_script_constant_map()
	var rt_src: String = FileAccess.get_file_as_string("res://autoload/gesture_router.gd")
	var lv_src: String = FileAccess.get_file_as_string("res://scenes/level/level_scene.gd")
	# 方法在位判据（工程既有纪律：Script 资源取 get_script_method_list，非 has_method）
	var rt_methods: Array = []
	for md: Dictionary in (rt_s as Script).get_script_method_list():
		rt_methods.append(String(md.get("name", "")))
	# 5a. 常量真值
	check_eq(float(rt_c.get("REAL_MOUSE_YIELD_SEC", -1.0)), 1.5,
		"5a：REAL_MOUSE_YIELD_SEC=1.5（§4.6-8 真实鼠标让位窗）")
	check(String(rt_c.get("MAIN_PANEL_PATH", "")) == "MainView/ViewportContainer",
		"5a：主视口路径常量唯一源（选块/删除语义域判定基准）")
	# 5b. §4.6-1/§4.6-2：三态状态机与公开契约在案
	for mth: String in ["_on_level_two_down_left", "_on_level_two_down_right", "_hit_panel_cell",
			"_panel_view_kind", "_clear_bound_view_selection", "_orbit_mode_active",
			"_orbit_apply_move", "_exit_orbit_to_select"]:
		check(rt_methods.has(mth), "5b：Router 分派单元 %s 在位（§4.6-1/2 三态状态机）" % mth)
	check(lv_src.contains("func hit_panel_cell(") and lv_src.contains("func orbit_rotate_panel("),
		"5b：level_scene 公开契约 hit_panel_cell / orbit_rotate_panel 在位（§4.6-1/§4.6-2）")
	# 5c. §4.6-2 退化解耦：旧「移出面板 → 强制回待命」中断逻辑整体退役（不限框红线）
	check(not rt_src.contains("_exit_orbit_to_select()\n\t\t\t\treturn") \
		and not rt_src.contains("\t\t\tif _semantic_zone() == \"level\" and String(_level_mode) == \"ORBIT\""),
		"5c：旧 P1-8c「panel 命中失败 → 回待命」中断逻辑已删除（§4.6-2 不限框）")
	check(rt_src.contains("_orbit_apply_move(") and not rt_src.contains("_orbit_rotate_panel("),
		"5c：旋转驱动收口 _orbit_apply_move（经 level_scene.orbit_rotate_panel 语义直驱，零合成拖拽）")
	# 5d. §4.6-4 删除优先级与冷却调用点
	check(rt_src.contains("removed = int(lv.call(\"delete_selected\"))") \
		and rt_src.contains("suppress_flip_after_delete"),
		"5d：_do_delete 优先 delete_selected + 实际删除回调 suppress_flip_after_delete（§4.6-4）")
	check(rt_src.contains("if removed > 0 and _map != null:"),
		"5d：冷却仅在 removed>0 时施加（选区为空零副作用，不毁 undo 可用性）")
	# 5d2. §4.6-1 视口隔离 → 批次 AD §4.3.4 等价改写：清空仍**严格受绑定视口约束**（未绑定即忽略），
	# 但作用域由旧「硬编码仅 Main」按 §4.3.4「双手握拳清空当前已绑定视口的全部选区」拓宽为「按
	# _panel_view_kind 分派的已绑定视口」（Main→clear_selection、Target/Join→_clear_side_selection）。
	# 旧值留痕：`rt_src.contains("_panel_view_kind(_active_panel) == \"Main\"")`（§4.6-1 clear 分支内联判 Main）
	# 随 §4.3.4 收口到 _clear_bound_view_selection 退役；判据语义「未绑定忽略 + 受绑定视口约束」保持。
	var cv_i: int = rt_src.find("\"clear\":")
	var cv_block: String = rt_src.substr(cv_i, 300) if cv_i >= 0 else ""
	var cv_fn_i: int = rt_src.find("func _clear_bound_view_selection(")
	var cv_fn_block: String = rt_src.substr(cv_fn_i, 600) if cv_fn_i >= 0 else ""
	check(cv_block.contains("_active_panel != null") and cv_block.contains("_clear_bound_view_selection()") \
			and cv_fn_block.contains("match _panel_view_kind(_active_panel)") \
			and cv_fn_block.contains("clear_selection") and cv_fn_block.contains("_clear_side_selection"),
		"5d2：清空受绑定视口约束（未绑定忽略）+ 经 _clear_bound_view_selection 按 _panel_view_kind 分派（§4.3.4 已绑定视口全清空）")
	var zs_i: int = rt_src.find("func _do_zoom_step(")
	var zs_block: String = rt_src.substr(zs_i, 2000) if zs_i >= 0 else ""
	# 缩进/注释无关判据：按行剥离空白后比对（注释行会插在守卫与 return 之间）
	var zs_stripped := ""
	for ln: String in zs_block.split("\n"):
		var s := ln.strip_edges()
		if not s.begins_with("#"):
			zs_stripped += s + "\n"
	check(zs_stripped.contains("if _active_panel == null or not is_instance_valid(_active_panel):\nreturn"),
		"5d2：缩放未绑定视口即忽略（旧「未激活面板回退主视图」链退役，§4.6-1）")
	check(not zs_block.contains("_first_zoomable_panel"),
		"5d2：_do_zoom_step 内零注册面板回退（视口隔离单一真值）")
	# 5e. §4.6-6 右二指滑动减选
	check(rt_src.contains("_right_sliding = true") and rt_src.contains("func _on_right_slide("),
		"5e：右二指滑动减选标志与单帧处理单元在位（起笔即置位，§4.6-6）")
	check(not rt_src.contains("if cell_r == NO_CELL or not bool(lv.call(\"is_cell_selected\", cell_r)):\n\t\t\treturn\n\t\tif String(_level_mode)"),
		"5e：旧「首帧未命中即失效」路径已重构（滑动期持续检测）")
	# 5f. §4.6-8 键鼠焦点隔离
	check(rt_src.contains("_note_real_mouse_motion") and rt_src.contains("_real_mouse_recent()"),
		"5f：真实鼠标新鲜度记账与让位窗判据在位（§4.6-8）")
	check(rt_src.contains("_last_real_mouse_time") and rt_src.contains("mm.has_meta(_synth_meta_key)"),
		"5f：记账源=真实事件（合成事件按 SYNTH_META 跳过，防自我续期）")
	# 空闲 cursor_move 不再直推：motion 推送收在 armed/jitter/物理按压/让位窗门内
	# → 批次 AD §4.3.5 等价改写（悬停光晕恢复）：空闲巡航 cursor_move 在「真实物理鼠标静止」时
	#   重新下发轻量 synth_motion（点亮 hover_glow）。旧 §4.6-8「笔画在场(_left_stroking or
	#   _right_stroking)」硬门随光晕恢复退役；键鼠焦点隔离语义**不削弱**——推送仍收在
	#   `_cursor_layer != null`（光标层缺席零注入）+ `not _real_mouse_recent()`（1.5s 让位窗内绝不打扰物理鼠标）
	#   + armed/jitter/物理按压三重门之内。旧值留痕：`cm_block.contains("and (_left_stroking or _right_stroking)")`。
	var cm_i: int = rt_src.find("\"cursor_move\":")
	var cm_block: String = rt_src.substr(cm_i, 2400) if cm_i >= 0 else ""
	check(cm_block.contains("if _cursor_layer != null") and not cm_block.contains("_left_stroking or _right_stroking"),
		"5f：巡航 synth_motion 门随 §4.3.5 光晕恢复重构（笔画在场硬门退役→光标层在场守卫；旧 §4.6-8 留痕）")
	check(cm_block.contains("and not _real_mouse_recent()"),
		"5f：让位窗内零 synth_motion（键鼠 hover/点击 100% 归物理鼠标）")
	# 按下点补 motion：锚定 _push_btn 内「pressed 分支先 push(synth_motion(pos))」的实现面
	# （缩进无关判据：该行以 TAB 缩进，故按行剥离空白后比对，防排版微调误杀）
	var pb_i: int = rt_src.find("func _push_btn(")
	var pb_block: String = rt_src.substr(pb_i, 1800) if pb_i >= 0 else ""
	var pb_stripped := ""
	for ln: String in pb_block.split("\n"):
		pb_stripped += ln.strip_edges() + "\n"
	check(pb_stripped.contains("if pressed:\n_cursor_layer.call(\"push\", _cursor_layer.call(\"synth_motion\", pos))"),
		"5f：按下点补一次 motion 定位悬停控件（BaseButton pressuring_inside 就位，§4.6-8 风险三缓解）")

func _initialize() -> void:
	print("== test_ac_batch4_gesture ==")
	_seg1_dual_zoom()
	_seg2_three_finger_flip()
	_seg3_delete_flip_guard()
	_seg4_exit_tolerance()
	_seg5_router_source_contracts()
	finish()
