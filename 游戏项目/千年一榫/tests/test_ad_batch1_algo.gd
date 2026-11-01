extends "res://tests/test_base.gd"
## 批次 AD 批次一（2026-09-27，spec §4.1/§4.2）：手势核心算法与光标流畅度重构专项回归。
## 段口径（红态=改前；全部零 UDP / 零设备：纯函数直调 + 合成手 dict 直喂 GestureMap）：
##   A（常量锚）：CURSOR_DEADZONE 0.0015→0.0003（仅滤硬件微噪）；
##     CURSOR_EMA_ALPHA 0.60→1.0（GDScript 二级低通退役=直通，只依赖 Python 端 One Euro）；
##     FINGER_EXTEND_TH[中指] 0.48→0.55（中指微伸不再误判双指）、EXTEND_EXIT_TH 0.40→0.45。
##   B（§4.1.1 光标位置与姿态状态机解耦）：只要本帧检出有效手且过置信度激活门，
##     **无论 semantic 处 cursor/two/rest/palm/确认过渡**，每帧恒恰一条 cursor_move，
##     坐标=当帧食指尖（增益映射后），绝不归零/不中断（旧码 rest 过渡帧零 cursor_move=红）。
##   C（§4.1.2 极窄死区）：0.0004 归一微动越死区、0.0002 微动锁上帧（0.0003 单阈判据）。
##   D（§4.2 食指瞄准与中指连带解耦）：中指 <0.55 → cursor（严禁误判 two）；
##     中指 ≥0.55 双帧 → two；无名指连带（≤0.65 且中指领先 ≥0.12）→ two；
##     无名指**反超**中指（过渡/连带形）→ 严禁回落 three=delete；真三指 → delete；
##     小指泄漏守卫零回归。
## 零摄像头纪律：全部合成手 dict 直喂，不触 UDP/端口/设备（spec §2.1 红线）。
## 坑位纪律：GestureMap 为 RefCounted → 一律 Variant 直调，禁 `as Node`。

const GM_SRC := "res://scripts/gesture_map.gd"

const F_CURSOR := [0.1, 0.9, 0.1, 0.1, 0.1]
const F_TWO := [0.1, 0.9, 0.9, 0.1, 0.1]
const F_MID_LOW := [0.1, 0.9, 0.52, 0.1, 0.1]     # 中指微伸 0.52（∈[0.45,0.55) 滞回带）→ 严禁判 two
const F_MID_EDGE := [0.1, 0.9, 0.55, 0.1, 0.1]     # 中指恰落新进入阈 0.55（边界含）→ two
const F_COUPLE := [0.1, 0.9, 0.72, 0.52, 0.1]      # 中指主动 + 无名指连带抬升 0.52（≤0.65）
const F_RING_LEAD := [0.1, 0.9, 0.56, 0.62, 0.1]   # 无名指**反超**中指（过渡/连带形）→ 严禁 three
const F_THREE := [0.1, 0.9, 0.9, 0.9, 0.1]         # 真三指（无名指主动伸展）
const F_THREE_LEAK := [0.1, 0.9, 0.9, 0.9, 0.6]    # 三指 + 小指泄漏 0.60 → 不进 two 链
const F_REST := [0.1, 0.1, 0.1, 0.1, 0.1]
const F_PALM := [0.1, 0.9, 0.9, 0.9, 0.9]

var m: Variant


func gm_s() -> Variant:
	return load(GM_SRC)


func _script_has_method(s: Variant, mname: String) -> bool:
	for md: Dictionary in (s as Script).get_script_method_list():
		if String(md.get("name", "")) == mname:
			return true
	return false


## 合成手 dict（test_ac_batch3_algo / test_gesture_map 同构）。
func _hand(fingers: Array, tip: Vector2, conf: float, label: String,
		facing: bool, ts: float) -> Dictionary:
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
	return {"gesture": "", "gesture_id": 0, "confidence": conf,
		"hand_x": tip.x, "hand_y": tip.y, "hand_z": 0.0,
		"hand_rotation_x": 5.0, "hand_rotation_y": 0.0, "hand_rotation_z": 0.0,
		"fingers": fingers, "pinch_distance": 0.5,
		"hand_index": 0 if label == "Left" else 1, "handedness": label,
		"landmarks": lm, "fps": 30.0, "is_detected": true, "timestamp": ts,
		"palm_size": 0.2, "tip_x": tip.x, "tip_y": tip.y,
		"id": "L0" if label == "Left" else "R0", "held": false}


func _feed_left(fingers: Array, tip: Vector2, conf: float, ts: float) -> Array:
	return m.feed_frame(_hand(fingers, tip, conf, "Left", true, ts), {}, ts)


func _feed_both(lf: Array, rf: Array, tip: Vector2, conf: float, ts: float) -> Array:
	return m.feed_frame(_hand(lf, tip, conf, "Left", true, ts),
		_hand(rf, tip, conf, "Right", true, ts), ts)


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


## 首条 cursor_move 的 pos（缺省哨兵 (−9,−9) 表「本帧无光标」）。
func _cm_pos(intents: Array) -> Vector2:
	for it: Variant in intents:
		if typeof(it) == TYPE_DICTIONARY and String((it as Dictionary).get("type", "")) == "cursor_move":
			return Vector2((it as Dictionary).get("pos", Vector2(-9, -9)))
	return Vector2(-9, -9)


## 期望的增益后内容坐标（apply_cursor_gain 同式；AC §4.4-2 纵向基准 c_y=(0.5+m)/g）。
func _expect_content(tip: Vector2, g: float, mo: float) -> Vector2:
	var cy: float = (0.5 + mo) / g
	return (tip - Vector2(0.5, cy)) * g + Vector2(0.5, 0.5)


func _initialize() -> void:
	print("== test_ad_batch1_algo ==")
	m = load(GM_SRC).new()
	var gm: Dictionary = (load(GM_SRC) as Script).get_script_constant_map()
	var g: float = float(gm.get("CURSOR_GAIN", 2.5))
	var mo: float = float(gm.get("CURSOR_OVERSHOOT", 0.15))

	# ================= 段 A：常量锚（spec §4.1.2 / §4.2） =================
	check(absf(float(gm.get("CURSOR_DEADZONE", -1.0)) - 0.0003) < 1e-12,
		"AD §4.1.2：CURSOR_DEADZONE 0.0015→0.0003（1152 视口折 0.35px 仅滤硬件微噪；旧 0.0015=批次 AA W2-3 留痕）")
	check(absf(float(gm.get("CURSOR_EMA_ALPHA", -1.0)) - 1.0) < 1e-9,
		"AD §4.1.2：CURSOR_EMA_ALPHA 0.60→1.0=直通（GDScript 二级低通退役，消除级联滞后；旧 0.60=批次 AC 留痕）")
	var th_v: Variant = gm.get("FINGER_EXTEND_TH", null)
	var th: Array = th_v if typeof(th_v) == TYPE_ARRAY else []
	var th_ok := th.size() == 5
	if th_ok:
		for i: int in 5:
			if absf(float(th[i]) - float([0.55, 0.55, 0.55, 0.48, 0.55][i])) > 1e-9:
				th_ok = false
	check(th_ok,
		"AD §4.2：FINGER_EXTEND_TH=[0.55,0.55,0.55,0.48,0.55]（中指 0.48→0.55 收回安全区间；旧 0.48=批次 AC §4.5-1 留痕）实际 %s" % str(th))
	check(absf(float(gm.get("EXTEND_EXIT_TH", -1.0)) - 0.45) < 1e-9,
		"AD §4.2：EXTEND_EXIT_TH 0.40→0.45（滞回退出阈；与进入阈 0.55 保持 0.10 滞后带，且严格低于无名指 0.48 阈——无带反转）实际 %.4f" % float(gm.get("EXTEND_EXIT_TH", -1.0)))
	check(absf(float(gm.get("CONF_ENTER", -1.0)) - 0.55) < 1e-9
		and absf(float(gm.get("CONF_EXIT", -1.0)) - 0.45) < 1e-9,
		"AD：置信度门 CONF_ENTER/CONF_EXIT=0.55/0.45 维持（本批不改置信度轴——光标解耦只针对姿态状态机，见 B 段口径注）")
	check(int(gm.get("CONFIRM_FRAMES", -1)) == 2, "AD：CONFIRM_FRAMES=2 维持（进入确认帧数不回退）")

	# ================= 段 B：光标位置与姿态状态机解耦（spec §4.1.1） =================
	# B1 冷启动两帧确认过渡：第 1 帧（仅入暂存）也必须发 cursor_move（旧码零派发=红）
	m.reset()
	var b1a: Array = _feed_left(F_TWO, Vector2(0.3, 0.4), 0.9, 1.0)
	check(_count(b1a, "cursor_move") == 1,
		"AD §4.1.1：two 确认第 1 帧（语义未提交）仍发 cursor_move（姿态状态机不再门控光标；旧码确认期零派发=红）")
	check(not _has(b1a, "two_down"), "B1 前置：确认第 1 帧零 two_down（2 帧门不回退）")
	var b1b: Array = _feed_left(F_TWO, Vector2(0.3, 0.4), 0.9, 1.033)
	check(int(_count(b1b, "cursor_move")) == 1,
		"AD §4.1.1：two 提交帧恰一条 cursor_move（帧末仲裁补出，不重复；[two_down, cursor_move] 序保持）")
	check(_has(b1b, "two_down"), "B1 前置：确认第 2 帧 two_down（既有语义零回归）")
	var t_dn: int = _types(b1b).find("two_down")
	var t_cm: int = _types(b1b).find("cursor_move")
	check(t_dn >= 0 and t_cm > t_dn,
		"S10 序保持：two_down 先于同帧 cursor_move（commit 帧先判定后刷新鲜度，陈旧坐标误点防线不被绕过）")

	# B2 二指→单指瞄准过渡：兜底 two_up 帧的 cursor_move 必须带当帧指尖位（不归零/不中断）
	var b2: Array = _feed_left(F_CURSOR, Vector2(0.6, 0.3), 0.9, 1.066)
	check(_has(b2, "two_up") and int(_count(b2, "cursor_move")) == 1,
		"AD §4.1.1：two→cursor 过渡帧 two_up + 恰一条 cursor_move（旧码过渡帧零光标=屏幕顿挫根因）")
	check(bool((_cm_pos(b2) - _expect_content(Vector2(0.6, 0.3), g, mo)).length() < 1e-5),
		"AD §4.1.1：过渡帧光标位=当帧食指尖增益映射值 %s（非归零、非上帧残留；α=1.0 直通）实际 %s" % [
			str(_expect_content(Vector2(0.6, 0.3), g, mo)), str(_cm_pos(b2))])

	# B3 rest（全收指）连续 5 帧：每帧恒恰一条 cursor_move，坐标随指尖逐帧推进
	m.reset()
	var b3_ok := true
	var b3_pos_ok := true
	var b3_zero := false
	for i: int in 5:
		var tip := Vector2(0.40 + 0.02 * float(i), 0.45)
		var its: Array = _feed_left(F_REST, tip, 0.9, 10.0 + 0.033 * float(i))
		if _count(its, "cursor_move") != 1:
			b3_ok = false
		var p := _cm_pos(its)
		if (p - _expect_content(tip, g, mo)).length() > 1e-5:
			b3_pos_ok = false
		if p.is_equal_approx(Vector2.ZERO) or p.is_equal_approx(Vector2(0.5, 0.5)):
			b3_zero = true
	check(b3_ok, "AD §4.1.1：rest 态连续 5 帧每帧恒恰一条 cursor_move（旧码 rest 态零派发=光标卡死根因）")
	check(b3_pos_ok, "AD §4.1.1：rest 态 cursor_move 坐标逐帧等于当帧食指尖增益映射值（逐帧跟手，非冻结）")
	check(not b3_zero, "AD §4.1.1：rest 态光标坐标绝不归零/不回落画面中心哨兵")

	# B4 palm 观察态（左掌四指，未进缩放）：光标不再暂停（§4.1.1 明列 palm 亦每帧派发）
	m.reset()
	_feed_left(F_PALM, Vector2(0.4, 0.4), 0.9, 20.0)
	var b4a: Array = _feed_left(F_PALM, Vector2(0.4, 0.4), 0.9, 20.033)
	check(_has(b4a, "palm_begin"), "B4 前置：左掌四指+掌面朝镜 → palm_begin（既有语义零回归）")
	var b4b: Array = _feed_left(F_PALM, Vector2(0.45, 0.42), 0.9, 20.066)
	check(int(_count(b4b, "cursor_move")) == 1,
		"AD §4.1.1：palm 观察态仍每帧恰一条 cursor_move（spec §4.1.1 明列 palm；旧码掌观察态光标暂停=红）")
	check(bool((_cm_pos(b4b) - _expect_content(Vector2(0.45, 0.42), g, mo)).length() < 1e-5),
		"AD §4.1.1：palm 观察态光标位=当帧食指尖映射值实际 %s" % str(_cm_pos(b4b)))

	# B5 双手同帧：两次 cursor_move（各手一条），且互不串位
	m.reset()
	var b5: Array = _feed_both(F_CURSOR, F_CURSOR, Vector2(0.3, 0.4), 0.9, 30.0)
	check(int(_count(b5, "cursor_move")) == 2,
		"AD §4.1.1：双手在场同帧各发一条 cursor_move（两侧并行上报；实际 %d 条）" % _count(b5, "cursor_move"))
	var b5_sides: Array = []
	for it: Variant in b5:
		if String((it as Dictionary).get("type", "")) == "cursor_move":
			b5_sides.append(String((it as Dictionary).get("side", "")))
	b5_sides.sort()
	check(b5_sides == ["left", "right"], "AD §4.1.1：双手 cursor_move 手别齐备（left/right 各一）实际 %s" % str(b5_sides))

	# ================= 段 C：极窄死区（spec §4.1.2） =================
	# C1 越阈：0.0004 > 0.0003 → 坐标必须推进（旧 0.0015 死区把 0.0004~0.0014 全锁上帧）
	m.reset()
	var dz: float = float(gm.get("CURSOR_DEADZONE", 0.0015))
	_feed_left(F_CURSOR, Vector2(0.50, 0.40), 0.9, 40.0)
	var c1: Array = _feed_left(F_CURSOR, Vector2(0.50 + dz * 1.3333, 0.40), 0.9, 40.033)
	check(not bool(_cm_pos(c1).is_equal_approx(_expect_content(Vector2(0.50, 0.40), g, mo))),
		"AD §4.1.2：帧间位移 1.33×死区（0.0004 归一）必须击穿推进（旧 0.0015 死区下同位移被锁=移动初始卡顿根因）实际 %s" % str(_cm_pos(c1)))
	# C2 微噪锁定：0.0002 < 0.0003 → 锁上帧（仅滤传感器微噪，语义不丢）
	m.reset()
	var c2a: Array = _feed_left(F_CURSOR, Vector2(0.50, 0.40), 0.9, 41.0)
	var c2b: Array = _feed_left(F_CURSOR, Vector2(0.50 + dz * 0.6667, 0.40), 0.9, 41.033)
	check(bool(_cm_pos(c2b).is_equal_approx(_cm_pos(c2a))),
		"AD §4.1.2：帧间位移 0.67×死区（0.0002 归一）锁上帧（死区仅滤硬件微噪）")
	check(bool(bool((c2b[0] as Dictionary).get("jitter", false))),
		"AD §4.1.2：微噪锁定帧 jitter=true（下游 Router 不推合成 motion 的既有判据保持）")

	# ================= 段 D：食指瞄准与中指连带解耦（spec §4.2） =================
	# D1 中指微伸 0.52（< 新阈 0.55）→ 判 cursor，严禁 two
	m.reset()
	_feed_left(F_CURSOR, Vector2(0.5, 0.4), 0.9, 50.0)
	var d1a: Array = _feed_left(F_MID_LOW, Vector2(0.5, 0.4), 0.9, 50.033)
	var d1b: Array = _feed_left(F_MID_LOW, Vector2(0.5, 0.4), 0.9, 50.066)
	check(not _has(d1a, "two_down") and not _has(d1b, "two_down"),
		"AD §4.2：中指微伸 0.52（<0.55）两帧零 two_down（瞄准时中指连带不再误判双指=单击误触发根因）")
	check_eq(String(m.get_side_semantic("left")), "cursor",
		"AD §4.2：中指微伸 0.52 → 语义保持 cursor（严禁误判 two）")

	# D2 中指恰落新进入阈 0.55（边界含）→ two 照常
	m.reset()
	_feed_left(F_MID_EDGE, Vector2(0.5, 0.4), 0.9, 51.0)
	var d2: Array = _feed_left(F_MID_EDGE, Vector2(0.5, 0.4), 0.9, 51.033)
	check(_has(d2, "two_down"),
		"AD §4.2 反向护栏：中指 0.55=新进入阈（边界含）→ two 照常（竖中指单击仍可达）")

	# D3 无名指连带（≤0.65 且中指领先 ≥0.12）→ two（AC §4.5-1 语义零回归）
	m.reset()
	_feed_left(F_COUPLE, Vector2(0.5, 0.4), 0.9, 52.0)
	var d3: Array = _feed_left(F_COUPLE, Vector2(0.5, 0.4), 0.9, 52.033)
	check(_has(d3, "two_down") and not _has(d3, "delete"),
		"AD §4.2：无名指生理连带（0.52≤0.65、中指领先 0.20≥0.12）→ two 且零 delete（AC 解耦零回归）")

	# D4 无名指**反超**中指（异常连带形：真手三指伸展时中指恒 ≥ 无名指）→ 严禁回落 three=delete
	m.reset()
	var d4a: Array = _feed_left(F_RING_LEAD, Vector2(0.5, 0.4), 0.9, 53.0)
	var d4b: Array = _feed_left(F_RING_LEAD, Vector2(0.5, 0.4), 0.9, 53.033)
	check(not _has(d4a, "delete") and not _has(d4b, "delete"),
		"AD §4.2：无名指反超中指（0.62>0.56，≤连带上限 0.65）→ 零 delete（严禁过渡态直接回落 three；旧码冷上下文落 three 误删=红）")
	check_eq(String(m.get_side_semantic("left")), "",
		"AD §4.2：反超异常形语义落 rest（get_side_semantic 对 rest 返回空串；既非 two 也非 three——destructive 语义零触发）")

	# D5 真三指（三指均伸直 + 小指弯曲）→ delete（删除可达性零回归）
	m.reset()
	_feed_left(F_THREE, Vector2(0.5, 0.4), 0.9, 54.0)
	var d5: Array = _feed_left(F_THREE, Vector2(0.5, 0.4), 0.9, 54.033)
	check(_has(d5, "delete"), "AD §4.2 反向护栏：食+中+无名三指均伸直、小指弯曲 → three=delete 照常")

	# D6 小指泄漏守卫零回归：三指 + 小指 0.60 → 不进 two 链
	m.reset()
	_feed_left(F_THREE_LEAK, Vector2(0.5, 0.4), 0.9, 55.0)
	var d6: Array = _feed_left(F_THREE_LEAK, Vector2(0.5, 0.4), 0.9, 55.033)
	check(not _has(d6, "two_down"),
		"AD §4.2：小指泄漏 0.60（未收拢）时解耦不生效——仍走 three 链（PALM_PINKY_TH 守卫零回归）")

	# D7 滞回带内（[0.45,0.55)）分指判定保持上帧、无来回翻转
	#     AD 等价改写（W2-5 原带 [0.40,0.55) → 现 [0.45,0.55)）：摆动幅值随新带平移，
	#     零 two_up/零重复 two_down 的判据与断言强度不变（另在段 D8 锁新下沿）。
	m.reset()
	_feed_left(F_TWO, Vector2(0.5, 0.4), 0.9, 56.0)
	var d7a: Array = _feed_left(F_TWO, Vector2(0.5, 0.4), 0.9, 56.033)
	check(_has(d7a, "two_down"), "D7 前置：中指 0.9 双帧 → two_down（进入态建立）")
	var osc: Array = [0.47, 0.60, 0.46, 0.57, 0.48, 0.59, 0.47, 0.56,
		0.49, 0.60, 0.46, 0.58, 0.48, 0.55, 0.47, 0.53]
	var ups := 0
	var downs := 0
	var moves := 0
	var ts_o := 56.10
	for v_v: Variant in osc:
		var oh: Dictionary = _hand([0.1, 0.9, float(v_v), 0.1, 0.1], Vector2(0.5, 0.4), 0.9, "Left", true, ts_o)
		var its: Array = m.feed_frame(oh, {}, ts_o)
		if _has(its, "two_up"):
			ups += 1
		if _has(its, "two_down"):
			downs += 1
		if _has(its, "two_move"):
			moves += 1
		ts_o += 0.033
	check_eq(ups, 0,
		"AD §4.2：滞回带 [0.45,0.55) 内摆动 16 帧零 two_up（退出阈 0.45 生效；W2-5 原带 [0.40,0.55) 摇摆幅值等价平移）")
	check_eq(downs, 0, "AD §4.2：滞回带内摆动零重复 two_down（无 cursor↔two 来回翻转）")
	check_eq(moves, osc.size(), "AD §4.2：滞回带内 two_move 每帧在（语义恒 two，零冻结）")

	# D8 新退出阈下沿：0.44 < 0.45 → 退出 two（退出阈 0.45 的红绿双锚）
	m.reset()
	_feed_left(F_TWO, Vector2(0.5, 0.4), 0.9, 57.0)
	_feed_left(F_TWO, Vector2(0.5, 0.4), 0.9, 57.033)
	var d8: Array = _feed_left([0.1, 0.9, 0.44, 0.1, 0.1], Vector2(0.5, 0.4), 0.9, 57.10)
	check(_has(d8, "two_up"),
		"AD §4.2：中指 0.44 < 0.45 退出阈 → 立即退出 two（two_up 兜底抬起；旧 0.40 阈下此处仍判 two=红）")

	# D9 中指退出阈与无名指进入阈无带反转自检（EXTEND_EXIT_TH 必须严格低于所有 FINGER_EXTEND_TH）
	var min_enter := 1.0
	for i: int in 5:
		min_enter = minf(min_enter, float(th[i]) if th_ok else 1.0)
	check(float(gm.get("EXTEND_EXIT_TH", 1.0)) < min_enter,
		"AD §4.2 结构护栏：EXTEND_EXIT_TH(%.2f) < min(FINGER_EXTEND_TH)(%.2f)——滞回带全域非空、无带反转" % [
			float(gm.get("EXTEND_EXIT_TH", 1.0)), min_enter])

	finish()
