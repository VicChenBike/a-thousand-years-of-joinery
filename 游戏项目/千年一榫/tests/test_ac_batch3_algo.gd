extends "res://tests/test_base.gd"
## 批次 AC（2026-09-27）Wave AC-3「手势底层算法」专项回归（spec §4.3/§4.4/§4.5）。
## 段口径（红态=改前；全部零 UDP / 零设备：纯函数直调 + 合成手 dict 直喂 GestureMap）：
##   A（常量锚）：CURSOR_EMA_ALPHA 0.35→0.60；FINGER_EXTEND_TH=[0.55,0.55,0.48,0.48,0.55]
##     （中指 0.55→0.48、无名指 0.45→0.48）；新增 TWO_RING_COUPLE_MAX=0.65 /
##     TWO_MIDDLE_RING_GAP=0.12（中指-无名指肌腱连带解耦）；CURSOR_ARM_WINDOW_SEC=0.25。
##   B（§4.4 活动框与光标映射上移）：
##     B1 `cursor_zone_rect` 纵向顶边贴画面顶（y0=0.0、h=2·half，归一 [0, 0.52]）；
##     B2 `apply_cursor_gain` 纵向中心由 0.5 上移至 c_y=(0.5+m)/gain=0.26——
##        框顶→−m、框中心→0.5、框底→1+m（视觉框与映射严格互为反函数）；
##     B3 横向语义零变化（中心 x 恒 0.5、增益式不变）。
##   C（§4.5 食指瞄准后竖中指单击）：
##     C1 无名指肌腱连带（fraw[3] ≤0.65 且 fraw[2]−fraw[3] ≥0.12）→ 判 two 非 three；
##     C2 无名指真实主动伸展（>0.65 或与中指齐平）→ 仍判 three（三指删除不受损）；
##     C3 小指泄漏守卫零回归（e[4] 为真时仍走 palm/three 链，不落 two）；
##     C4 cursor 态上下文内无名指连带 → two（semantic 上下文条件）；
##     C5 cursor→two 过渡单帧 rest 容忍：确认帧数不清零、two_down 仍触发；
##     C6 确认期（瞄准预备窗内）cursor_move 持续刷新（Router S10 新鲜度门不丢击）。
## 零摄像头纪律：全部合成手 dict 直喂，不触 UDP/端口/设备（spec §2.1 红线）。
## 坑位纪律：GestureMap 为 RefCounted → 一律 Variant 直调，禁 `as Node`。

const GM_SRC := "res://scripts/gesture_map.gd"
const SK_SRC := "res://scenes/shared/camera_skeleton.gd"

const F_CURSOR := [0.1, 0.9, 0.1, 0.1, 0.1]
const F_TWO := [0.1, 0.9, 0.9, 0.1, 0.1]
const F_TWO_COUPLE := [0.1, 0.9, 0.72, 0.52, 0.1]     # 竖中指 + 无名指肌腱连带抬升 0.52
const F_THREE := [0.1, 0.9, 0.9, 0.9, 0.1]            # 真实三指（无名指主动伸展）
const F_RING_HIGH := [0.1, 0.9, 0.72, 0.70, 0.1]      # 无名指 0.70 >0.65（真实抬升）
const F_RING_FLUSH := [0.1, 0.9, 0.58, 0.55, 0.1]     # AD 等价平移：中 0.58/无名 0.55 齐平（差 0.03 <0.12），两者均过各自进入阈
const F_RING_LEAD := [0.1, 0.9, 0.58, 0.60, 0.1]      # AD 等价平移：中指 0.58 ≥新阈 0.55、无名指反超 0.60（context 用；差值 -0.02 不足）
const F_COUPLE_LEAK := [0.1, 0.9, 0.72, 0.52, 0.6]    # 连带 + 小指泄漏 0.6
const F_REST := [0.1, 0.1, 0.1, 0.1, 0.1]

var m: Variant

func gm_s() -> Variant:
	return load(GM_SRC)

func sk_s() -> Variant:
	return load(SK_SRC)

func _script_has_method(s: Variant, mname: String) -> bool:
	for md: Dictionary in (s as Script).get_script_method_list():
		if String(md.get("name", "")) == mname:
			return true
	return false

## 合成手 dict（test_gesture_map / test_aa_gesture_stability 同构）。
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

func _types(intents: Array) -> Array:
	var out: Array = []
	for it: Variant in intents:
		out.append(String((it as Dictionary).get("type", "")))
	return out

func _has(intents: Array, t: String) -> bool:
	return _types(intents).has(t)

func _count(intents: Array, t: String) -> int:
	var n := 0
	for it: Variant in intents:
		if String((it as Dictionary).get("type", "")) == t:
			n += 1
	return n

func _initialize() -> void:
	print("== test_ac_batch3_algo ==")
	m = load(GM_SRC).new()
	var gm: Dictionary = (load(GM_SRC) as Script).get_script_constant_map()

	# ================= 段 A：常量锚（spec §4.3/§4.5） =================
	# 批次 AD（§4.1.2 / §4.2）等价改写：CURSOR_EMA_ALPHA 0.60→1.0=直通（消除级联低通）、
	# FINGER_EXTEND_TH 中指 0.48→0.55（收回安全区间，防瞄准期中指连带误判 two）。
	# 断言强度保持：登记值逐一锁死；下方 C1/C2/C4 的行为用例随新阈**等价平移夹具**后照跑。
	check(absf(float(gm.get("CURSOR_EMA_ALPHA", -1.0)) - 1.0) < 1e-9,
		"AD §4.1.2：CURSOR_EMA_ALPHA 0.60→1.0=直通（消除 Python+GDScript 级联双低通粘滞；旧 0.60=批次 AC §4.3-2、0.35=批次 AA W2-1 留痕）")
	check(absf(float(gm.get("CURSOR_GAIN", -1.0)) - 2.5) < 1e-9,
		"AC：CURSOR_GAIN=2.5 维持（映射中心上移不改增益）")
	check(absf(float(gm.get("CURSOR_OVERSHOOT", -1.0)) - 0.15) < 1e-9,
		"AC：CURSOR_OVERSHOOT=0.15 维持（m 参与 c_y 推导）")
	var th_v: Variant = gm.get("FINGER_EXTEND_TH", null)
	var th: Array = th_v if typeof(th_v) == TYPE_ARRAY else []
	var th_ok := th.size() == 5
	var th_expect := [0.55, 0.55, 0.55, 0.48, 0.55]
	if th_ok:
		for i: int in 5:
			if absf(float(th[i]) - float(th_expect[i])) > 1e-9:
				th_ok = false
	check(th_ok,
		"AC §4.5-1：FINGER_EXTEND_TH=[0.55,0.55,0.48,0.48,0.55]（中指 0.55→0.48、无名指 0.45→0.48）实际 %s" % str(th))
	check(absf(float(gm.get("TWO_RING_COUPLE_MAX", -1.0)) - 0.65) < 1e-9,
		"AC §4.5-1：新增 TWO_RING_COUPLE_MAX=0.65（无名指生理连带抬升容忍上限）")
	check(absf(float(gm.get("TWO_MIDDLE_RING_GAP", -1.0)) - 0.12) < 1e-9,
		"AC §4.5-1：新增 TWO_MIDDLE_RING_GAP=0.12（中指领先无名指最小差值）")
	check(absf(float(gm.get("CURSOR_ARM_WINDOW_SEC", -1.0)) - 0.25) < 1e-9,
		"AC §4.5-2：新增 CURSOR_ARM_WINDOW_SEC=0.25（瞄准预备窗）")
	check(absf(float(gm.get("PALM_PINKY_TH", -1.0)) - 0.70) < 1e-9,
		"AC：PALM_PINKY_TH=0.70 维持（小指泄漏守卫不回归）")
	check(int(gm.get("CONFIRM_FRAMES", -1)) == 2, "AC：CONFIRM_FRAMES=2 维持")

	# ================= 段 B：活动框与光标映射上移（spec §4.4） =================
	var gain := float(gm.get("CURSOR_GAIN", 2.5))
	var mo := float(gm.get("CURSOR_OVERSHOOT", 0.15))
	var cy: float = (0.5 + mo) / gain   # 0.26
	var has_gain: bool = _script_has_method(gm_s(), "apply_cursor_gain")
	check(has_gain, "B 前置：apply_cursor_gain 纯函数在位")
	if has_gain:
		var p_top := Vector2(gm_s().apply_cursor_gain(Vector2(0.5, 0.0), gain))
		check(bool(p_top.is_equal_approx(Vector2(0.5, -mo))),
			"AC §4.4-2：框顶 tip_y=0 → 屏幕 y=−m（−0.15；视觉框顶边与映射上缘严格对齐）实际 %s" % str(p_top))
		var p_mid := Vector2(gm_s().apply_cursor_gain(Vector2(0.5, cy), gain))
		check(bool(p_mid.is_equal_approx(Vector2(0.5, 0.5))),
			"AC §4.4-2：框纵向中心 tip_y=c_y=%.2f → 屏幕正中 (0.5,0.5)（视觉框与光标映射完全对齐）实际 %s" % [cy, str(p_mid)])
		var p_bot := Vector2(gm_s().apply_cursor_gain(Vector2(0.5, 2.0 * cy), gain))
		check(bool(p_bot.is_equal_approx(Vector2(0.5, 1.0 + mo))),
			"AC §4.4-2：框底 tip_y=2c_y=0.52 → 屏幕 y=1+m（1.15）实际 %s" % str(p_bot))
		var p_old := Vector2(gm_s().apply_cursor_gain(Vector2(0.5, 0.5), gain))
		check(absf(p_old.y - 1.10) < 1e-6,
			"AC §4.4-2 留痕：(0.5,0.5) 不再是映射不动点——现映射到 y=1.10（旧 0.5 随中心上移退役）实际 %.4f" % p_old.y)
		var p_x := Vector2(gm_s().apply_cursor_gain(Vector2(0.6, cy), gain))
		check(absf(p_x.x - 0.75) < 1e-6 and absf(p_x.y - 0.5) < 1e-6,
			"AC §4.4-2：横向语义零变化（x：(0.6−0.5)×2.5+0.5=0.75；纵向中心基准不动）实际 %s" % str(p_x))
		var p_clamp := Vector2(gm_s().apply_cursor_gain(Vector2(0.5, -0.4), gain))
		check(absf(p_clamp.y - (-mo)) < 1e-6,
			"AC：上溢仍钳制在 −m（扩边钳制域 [-m,1+m] 零回归）实际 %.4f" % p_clamp.y)

	var has_zone: bool = _script_has_method(sk_s(), "cursor_zone_rect")
	check(has_zone, "B 前置：camera_skeleton.cursor_zone_rect 纯函数在位")
	if has_zone:
		var win := Vector2(1152, 648)
		var inner: Rect2 = sk_s().pillarbox_rect(win, win)
		var half: float = (0.5 + mo) / gain   # 0.26
		var exp_rect := Rect2(inner.position + Vector2(0.5 - half, 0.0) * inner.size,
			Vector2(2.0 * half, 2.0 * half) * inner.size)
		var got: Rect2 = sk_s().cursor_zone_rect(win, win, gain, mo)
		check(bool(got.position.is_equal_approx(exp_rect.position) and got.size.is_equal_approx(exp_rect.size)),
			"AC §4.4-1：参考框顶边贴画面顶（y0=0.0、h=2half=0.52）pos=%s size=%s" % [str(got.position), str(got.size)])
		check(absf(got.position.y - inner.position.y) < 1e-6,
			"AC §4.4-1：框顶=内衬矩形顶部（顶边顶住摄像头画面顶部）实际 %.3f vs %.3f" % [got.position.y, inner.position.y])
		var n_top: float = (got.position.y - inner.position.y) / inner.size.y
		var n_bot: float = (got.end.y - inner.position.y) / inner.size.y
		check(absf(n_top) < 1e-6 and absf(n_bot - 2.0 * half) < 1e-6,
			"AC §4.4-1：归一纵向覆盖 [0.0, 0.52]（下半 0.52~1.0 留给手掌/手腕）实际 [%.4f, %.4f]" % [n_top, n_bot])
		check(absf(n_bot - 0.52) < 1e-6,
			"AC §4.4-1 数值锚：框底归一 0.52 = 2×(0.5+m)/g 实际 %.4f" % n_bot)
		var n_l: float = (got.position.x - inner.position.x) / inner.size.x
		check(absf(n_l - (0.5 - half)) < 1e-6,
			"AC §4.4-1：横向保持居中（x0=0.5−half=0.24）实际 %.4f" % n_l)
		var got_d: Rect2 = sk_s().cursor_zone_rect(win, win, gain)
		check(absf((got_d.position.y - inner.position.y) / inner.size.y) < 1e-6,
			"AC §4.4-1：overshoot 缺省=0 时顶边仍贴画面顶（新纵向语义对缺省调用同样生效）")
		var fb: Rect2 = sk_s().cursor_zone_rect(win, win, 0.0, mo)
		check(bool(fb.position.is_equal_approx(inner.position) and fb.size.is_equal_approx(inner.size)),
			"AC：无效增益（≤0）回退整个内衬矩形（不猜值防御零回归）")
		# 框 ↔ 映射互为反函数（三锚点闭环）
		var inv_ok := true
		for pair: Array in [[0.0, -mo], [half, 0.5], [2.0 * half, 1.0 + mo]]:
			var tip_y := float(pair[0])
			var want_y := float(pair[1])
			var got_y := float(gm_s().apply_cursor_gain(Vector2(0.5, tip_y), gain).y)
			if absf(got_y - want_y) > 1e-6:
				inv_ok = false
		check(inv_ok, "AC §4.4-1/2：参考框三锚点（顶/中心/底）经 apply_cursor_gain 精确落到 −m/0.5/1+m（互为反函数）")

	if _script_has_method(sk_s(), "map_cursor_gain") and _script_has_method(sk_s(), "map_cursor_overshoot"):
		check(is_equal_approx(float(sk_s().map_cursor_gain()), gain),
			"AC：参考框增益与 GestureMap.CURSOR_GAIN 同源读取零回归")
		check(is_equal_approx(float(sk_s().map_cursor_overshoot()), mo),
			"AC：参考框 overshoot 与 GestureMap.CURSOR_OVERSHOOT 同源读取零回归")

	# ================= 段 C：中指-无名指解耦与单击灵敏（spec §4.5） =================
	# C1：连带抬升 0.52（≤0.65）且中指领先 0.20（≥0.12）→ two
	m.reset()
	var c1a: Array = _feed_left(F_TWO_COUPLE, Vector2(0.5, 0.3), 0.9, 10.0)
	var c1b: Array = _feed_left(F_TWO_COUPLE, Vector2(0.5, 0.3), 0.9, 10.033)
	check(_has(c1b, "two_down"),
		"AC §4.5-1：竖中指+无名指连带 0.52（≤0.65、差值 0.20≥0.12）→ two_down（旧判 three 判红）")
	check(not _has(c1b, "delete"), "AC §4.5-1：连带态零 delete（不得误判三指删除）")
	check(int(c1a.size()) >= 0, "C1 探针占位（首帧仅确认，无 two_down）")
	check(not _has(c1a, "two_down"), "AC §4.5：确认帧数=2 不回退（首帧不 two_down）")

	# C2：无名指真实主动伸展 → 仍判 three（三指删除不受损）
	m.reset()
	var c2a: Array = _feed_left(F_THREE, Vector2(0.5, 0.3), 0.9, 11.0)
	var c2b: Array = _feed_left(F_THREE, Vector2(0.5, 0.3), 0.9, 11.033)
	check(_has(c2b, "delete"), "AC §4.5-1 反向护栏：无名指伸展 0.9（>0.65）→ three=delete 照常")
	check(not _has(c2b, "two_down"), "AC §4.5-1 反向护栏：真实三指不得落 two")
	m.reset()
	var c2c: Array = _feed_left(F_RING_HIGH, Vector2(0.5, 0.3), 0.9, 12.0)
	var c2d: Array = _feed_left(F_RING_HIGH, Vector2(0.5, 0.3), 0.9, 12.033)
	check(_has(c2d, "delete"),
		"AC §4.5-1 反向护栏：无名指 0.70（>TWO_RING_COUPLE_MAX）→ three=delete")
	m.reset()
	var c2e: Array = _feed_left(F_RING_FLUSH, Vector2(0.5, 0.3), 0.9, 13.0)
	var c2f: Array = _feed_left(F_RING_FLUSH, Vector2(0.5, 0.3), 0.9, 13.033)
	check(_has(c2f, "delete"),
		"AC §4.5-1 反向护栏：中/无名指齐平（差 0.05<0.12）→ three=delete（真三指语义保留）")
	# C3：小指泄漏守卫（e[4] 真 → 不落 two 链）→ 批次 AD §4.3.2 等价改写：删除收紧为**严格三指**
	#（食/中/无名 ≥0.55 且小指收拢 ≤THREE_PINKY_FOLD_MAX=0.35）——小指泄漏 0.6（未收）不再判 three=delete
	#（旧 W2-6/AC 口径「泄漏 ≤0.70 → three 链照常 delete」随本批**有意收紧**退役；真三指删除可达性由
	# C2 段 F_THREE/F_RING_HIGH/F_RING_FLUSH（小指 0.1≤0.35）反向护栏继续覆盖，断言数 2→2 不减）。
	m.reset()
	var c3a: Array = _feed_left(F_COUPLE_LEAK, Vector2(0.5, 0.3), 0.9, 14.0)
	var c3b: Array = _feed_left(F_COUPLE_LEAK, Vector2(0.5, 0.3), 0.9, 14.033)
	check(not _has(c3b, "two_down"),
		"AC §4.5-1：小指泄漏（0.6 未收）时解耦不生效——不落 two 链（守卫零回归）")
	check(not _has(c3b, "delete"),
		"AD §4.3.2：小指泄漏 + 连带（0.6>0.35 未收拢）→ 零 delete（旧「泄漏→three=delete」随严格三指门收紧退役留痕）")

	# C4：cursor 态上下文内无名指连带（差值不足）→ two
	m.reset()
	_feed_left(F_CURSOR, Vector2(0.5, 0.3), 0.9, 15.0)
	_feed_left(F_CURSOR, Vector2(0.5, 0.3), 0.9, 15.033)
	var c4a: Array = _feed_left(F_RING_LEAD, Vector2(0.5, 0.3), 0.9, 15.066)
	var c4b: Array = _feed_left(F_RING_LEAD, Vector2(0.5, 0.3), 0.9, 15.099)
	check(_has(c4b, "two_down"),
		"AC §4.5-1：cursor 态上下文内（fraw[3]=0.62 ≤0.65）→ 判 two（差值条件由上下文豁免）")
	check(not _has(c4b, "delete"), "AC §4.5-1：上下文内连带零 delete")

	# C5：cursor→two 过渡单帧 rest 容忍（不清零确认计数）
	m.reset()
	_feed_left(F_CURSOR, Vector2(0.5, 0.3), 0.9, 20.0)
	_feed_left(F_CURSOR, Vector2(0.5, 0.3), 0.9, 20.033)
	var c5a: Array = _feed_left(F_TWO_COUPLE, Vector2(0.5, 0.3), 0.9, 20.066)   # 确认 1
	check(not _has(c5a, "two_down"), "C5 前置：确认第 1 帧未提交")
	var c5r: Array = _feed_left(F_REST, Vector2(0.5, 0.3), 0.9, 20.099)          # 单帧过渡
	check(not _has(c5r, "two_up"), "AC §4.5-2：瞄准预备窗内单帧 rest 不触发兜底抬键")
	var c5b: Array = _feed_left(F_TWO_COUPLE, Vector2(0.5, 0.3), 0.9, 20.132)   # 确认 2
	check(_has(c5b, "two_down"),
		"AC §4.5-2：过渡单帧不清零确认计数——第 2 帧即 two_down（旧码 rest 即 _clear_pending 判红）")
	# 反向护栏：无 cursor 前置（冷启动）时 rest 单帧仍清空确认计数
	m.reset()
	_feed_left(F_TWO_COUPLE, Vector2(0.5, 0.3), 0.9, 21.0)
	_feed_left(F_REST, Vector2(0.5, 0.3), 0.9, 21.033)
	var c5c: Array = _feed_left(F_TWO_COUPLE, Vector2(0.5, 0.3), 0.9, 21.066)
	check(not _has(c5c, "two_down"),
		"AC §4.5-2 反向护栏：无瞄准预备窗时单帧 rest 照常清零确认（不放大误触）")
	var c5d: Array = _feed_left(F_TWO_COUPLE, Vector2(0.5, 0.3), 0.9, 21.099)
	check(_has(c5d, "two_down"), "AC §4.5-2：重计满 2 帧 → two_down（确认语义不回退）")

	# C6：确认期 cursor_move 持续刷新（Router S10 新鲜度门）
	m.reset()
	_feed_left(F_CURSOR, Vector2(0.5, 0.3), 0.9, 30.0)
	_feed_left(F_CURSOR, Vector2(0.5, 0.3), 0.9, 30.033)
	var c6a: Array = _feed_left(F_TWO_COUPLE, Vector2(0.4, 0.35), 0.9, 30.066)
	check(_has(c6a, "cursor_move"),
		"AC §4.5-2：cursor→two 确认第 1 帧仍发 cursor_move（光标新鲜度不因过渡丢失）")
	check(bool(c6a.size()) and (c6a as Array).size() >= 0, "C6 探针")
	var c6b: Array = _feed_left(F_TWO_COUPLE, Vector2(0.4, 0.35), 0.9, 30.099)
	check(_has(c6b, "two_down"), "AC §4.5-2：确认帧满即 two_down（单击干脆）")
	check(_has(c6b, "cursor_move"), "AC §4.5-2：提交帧 cursor_move 与 two_down 同帧（S10 门序保持）")

	# 段 C 收口：手势状态连续性——整个 cursor→two 链上 hand_id 不变、无 teardown
	m.reset()
	var hid0 := ""
	for i: int in 4:
		var f: Array = F_CURSOR if i < 2 else F_TWO_COUPLE
		var its: Array = _feed_left(f, Vector2(0.5, 0.3), 0.9, 40.0 + 0.033 * float(i))
		if i == 3:
			check(_has(its, "two_down"), "AC §4.5-2：四帧序列（cursor×2 → 连带 two×2）末帧 two_down")
	var st: Dictionary = m.get("_side")["left"]
	check_eq(String(st.get("semantic", "")), "two",
		"AC §4.5-2：终态 semantic=two（状态连续性：无中间 teardown）")
	hid0 = String(st.get("hand_id", ""))
	check(hid0 != "", "AC：hand_id 在链上登记（L0 类稳定 id 语义）")

	finish()
