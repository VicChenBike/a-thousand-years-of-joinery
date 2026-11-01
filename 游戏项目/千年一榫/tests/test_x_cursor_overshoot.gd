extends "res://tests/test_base.gd"
## 批次 X X1 波（P2，spec §3）：光标四角余量 CURSOR_OVERSHOOT 域判定用例（新件）。
## ① 常量锚：CURSOR_OVERSHOOT=0.15（调优带 0.10~0.25）+ CURSOR_GAIN=2.5 / CURSOR_DEADZONE=0.0015
##    （批次 AA W2-2/W2-3 等价平移：3.5→2.5、0.0035→0.0015。**口径勘误留痕**：批次 X「增益
##    不回退=拍板语义 A」系误诊——spec §5.2 R2-3 实证 CURSOR_OVERSHOOT 修复对「四角可达」
##    无效、根因与 gain=3.5 公式不符；批次 AA 按 §5.3 W2-2 降增益，本件锚随实现等价平移）
##    不回退（拍板语义 A「框=映射区大一圈、屏幕内缩」=增益不降只扩钳制域）；
## ② apply_cursor_gain overshoot 语义：钳制域 [-m,1+m]（签名不变、纯函数语义保持）——域缘收口
##    tip=0→−0.15 / 1→1.15、四角余量带、屏幕角内可达 0.357/0.643→−0.0005/1.0005 不再硬钳、
##    中心 (0.5,0.5) 不动点、行内式回代（钳界 [-m,1+m]）；
## ③ 参考框（camera_skeleton.cursor_zone_rect）：第四参 overshoot 缺省=0 → 旧框 [0.5±1/(2g)]²
##    等价直测（旧调用零破坏）、overshoot=0.15 → half=(0.5+m)/g 归一 [0.314,0.686]² 数值锚、
##    新框严格包含旧框（映射区大一圈）、gain≤0 守卫退化不猜值；
## ④ 同源读取：map_cursor_overshoot()==GestureMap.CURSOR_OVERSHOOT（get_script_constant_map
##    零静态引用纪律，同 map_cursor_gain）；⑤ P2-5 哨兵语义分离（spec §3-6 探针授权）：router
##    在屏标志生命周期（cursor_move 派发置位/reset_runtime 清零）+ 负坐标光标走 hover 实测路径
##    （不再与 Vector2(-1,-1)「从未有光标」哨兵相混）。
## 夹具沿用 test_v_cursor_map 的 MockLayer；哨兵段直调 router._dispatch/_hovered_ui_interactive
## （下划线方法直调=工程既有先例），不触 user:// 档案。

var router: Variant
var mock: MockLayer

class MockLayer extends CanvasLayer:
	## 合成事件流水记录（click_route 同款）
	var calls: Array = []
	func synth_button(_pos: Vector2, _pressed: bool, _ctrl: bool) -> InputEventMouseButton:
		calls.append(["btn"])
		return InputEventMouseButton.new()
	func synth_motion(_pos: Vector2) -> InputEventMouseMotion:
		calls.append(["motion"])
		return InputEventMouseMotion.new()
	func push(_ev: InputEvent) -> void:
		calls.append(["push"])
	func show_cursor(_side: String, _pos: Vector2) -> void:
		pass

func _script_has_method(s: Variant, mname: String) -> bool:
	for md: Dictionary in (s as Script).get_script_method_list():
		if String(md.get("name", "")) == mname:
			return true
	return false

func _motion_count() -> int:
	var n := 0
	for c: Variant in mock.calls:
		if c[0] == "motion":
			n += 1
	return n

func _initialize() -> void:
	print("== test_x_cursor_overshoot ==")
	var gm_s: Variant = load("res://scripts/gesture_map.gd")
	var gm: Dictionary = (gm_s as Script).get_script_constant_map()

	# ---- 1. 常量锚（P2；调优带留痕）----
	check_eq(float(gm.get("CURSOR_OVERSHOOT", -1.0)), 0.15, "X1：CURSOR_OVERSHOOT=0.15（新增；调优带 0.10~0.25 留痕=批次X规格§3）")
	check_eq(float(gm.get("CURSOR_GAIN", -1.0)), 2.5, "W2-2：CURSOR_GAIN=2.5（批次 AA 降增益；批次 X「3.5 不回退=拍板语义A」系误诊留痕，spec §5.3 W2-2/§15#3；暂定值·待用户复验）")
	# 批次 AD（§4.1.2）等价改写：CURSOR_DEADZONE 0.0015→0.0003（仅滤硬件微噪，1152 视口折
	# 约 0.35px）；旧值留痕 0.0015=批次 AA W2-3、0.0035=批次 T §4-7。本件其余断言（overshoot
	# 钳域 / 增益不动点 / 在屏标志）随常量**无关**，逐条零改写照跑——判据判别力不降。
	check_eq(float(gm.get("CURSOR_DEADZONE", -1.0)), 0.0003, "AD §4.1.2：CURSOR_DEADZONE 0.0015→0.0003（移动初始卡顿死区根治；旧 0.0015=批次 AA W2-3 / 0.0035=批次 T §4-7 留痕）")
	check(_script_has_method(gm_s, "apply_cursor_gain"), "X1：apply_cursor_gain 纯函数在位（函数签名不变=两参调用）")

	# ---- 2. apply_cursor_gain overshoot 语义（钳制域 [-m,1+m]）----
	# 批次 AC（§4.4-2）等价改写：纵向中心基准上移 c_y=(0.5+m)/g——纵向采样点须绕 c_y 取值，
	# 「(0.5,0.5) 中心不动点」随拍板退役为「(0.5,c_y) 新不动点」（见 tests/test_ac_batch3_algo）。
	var g35 := 3.5
	var mo := 0.15
	var cy35: float = (0.5 + mo) / g35
	check(bool(gm_s.apply_cursor_gain(Vector2(0.0, cy35), g35).is_equal_approx(Vector2(-mo, 0.5))),
		"X1：tip x=0 → x 钳 −0.15（域缘收口，旧硬钳 0 废止留痕；AC 纵向基准改 c_y）")
	check(bool(gm_s.apply_cursor_gain(Vector2(1.0, cy35), g35).is_equal_approx(Vector2(1.0 + mo, 0.5))),
		"X1：tip x=1 → x 钳 1.15（域缘收口，旧硬钳 1 废止留痕）")
	check(bool(gm_s.apply_cursor_gain(Vector2(0.5, 0.0), g35).is_equal_approx(Vector2(0.5, -mo))),
		"X1/AC：tip y=0（视觉框顶边）→ y 钳 −0.15（域缘收口；AC 顶边基准即 0.0）")
	check(bool(gm_s.apply_cursor_gain(Vector2(0.5, 2.0 * cy35), g35).is_equal_approx(Vector2(0.5, 1.0 + mo))),
		"X1/AC：tip y=2c_y（视觉框底边 0.52）→ y 钳 1.15（域缘收口；AC 旧「tip y=1」等价平移）")
	check(bool(gm_s.apply_cursor_gain(Vector2(0.0, 0.0), g35).is_equal_approx(Vector2(-mo, -mo))),
		"X1：tip=(0,0)→(−0.15,−0.15)（左上角余量带可达）")
	check(bool(gm_s.apply_cursor_gain(Vector2(1.0, 1.0), g35).is_equal_approx(Vector2(1.15, 1.15))),
		"X1：tip=(1,1)→(1.15,1.15)（右下角余量带可达；AC 中心上移后仍双饱和）")
	check(bool(gm_s.apply_cursor_gain(Vector2(0.357, cy35), g35).is_equal_approx(Vector2(-0.0005, 0.5))),
		"X1：屏幕角内可达 x−（0.357,·)→−0.0005 不再硬钳（旧 V12「0.357→0」废止留痕）")
	check(bool(gm_s.apply_cursor_gain(Vector2(0.643, cy35), g35).is_equal_approx(Vector2(1.0005, 0.5))),
		"X1：屏幕角内可达 x+（0.643,·)→1.0005 不再硬钳（旧 V12「0.643→1」废止留痕）")
	check(bool(gm_s.apply_cursor_gain(Vector2(0.5, cy35), g35).is_equal_approx(Vector2(0.5, 0.5))),
		"AC §4.4-2：新不动点 (0.5, c_y=(0.5+m)/g) → 屏幕正中 (0.5,0.5)（旧 (0.5,0.5) 不动点随纵向中心上移退役留痕）")
	var man := ((Vector2(0.7, 0.3) - Vector2(0.5, cy35)) * g35 + Vector2(0.5, 0.5)).clamp(Vector2(-mo, -mo), Vector2(1.0 + mo, 1.0 + mo))
	check(bool(Vector2(gm_s.apply_cursor_gain(Vector2(0.7, 0.3), g35)).is_equal_approx(man)),
		"X1：纯函数与行内式回代等价（g=3.5 钳界 [-m,1+m]；AC 行内式纵向基准同步 c_y）")

	# ---- 3. 参考框：overshoot 缺省=0 旧框等价 + 0.15 新框公式 ----
	var sk_s: Variant = load("res://scenes/shared/camera_skeleton.gd")
	var has_zone: bool = _script_has_method(sk_s, "cursor_zone_rect")
	check(has_zone, "X1：cursor_zone_rect 在位（第四参 overshoot 缺省=0）")
	check(_script_has_method(sk_s, "map_cursor_overshoot"), "X1：camera_skeleton 新增 map_cursor_overshoot（同款零静态引用守卫读取）")
	if has_zone:
		var win := Vector2(1152, 648)
		var inner: Rect2 = sk_s.pillarbox_rect(win, win)
		var lof := 0.5 - 0.5 / 3.5
		# 批次 AC（§4.4-1）等价改写：纵向顶边贴画面顶（y0=0.0、h=2half）；旧「纵向居中」退役。
		var exp_old := Rect2(inner.position + Vector2(lof, 0.0) * inner.size, Vector2(1.0 / 3.5, 1.0 / 3.5) * inner.size)
		var got_d: Rect2 = sk_s.cursor_zone_rect(win, win, 3.5)
		var got_0: Rect2 = sk_s.cursor_zone_rect(win, win, 3.5, 0.0)
		check(bool(got_d.position.is_equal_approx(exp_old.position) and got_d.size.is_equal_approx(exp_old.size)),
			"AC §4.4-1：overshoot 缺省=0 → 顶边贴顶 y0=0、h=1/g（满窗例 pos≈(411.4,0) size≈(329.1,185.1)；X1 纵向居中退役留痕）")
		check(bool(got_0.position.is_equal_approx(got_d.position) and got_0.size.is_equal_approx(got_d.size)),
			"X1：overshoot=0 显式传参 == 缺省调用（调用面零变化）")
		var lon := 0.5 - 0.65 / 3.5
		var half_new := 0.65 / 3.5
		var exp_new := Rect2(inner.position + Vector2(lon, 0.0) * inner.size, Vector2(2.0 * half_new, 2.0 * half_new) * inner.size)
		var got_n: Rect2 = sk_s.cursor_zone_rect(win, win, 3.5, 0.15)
		check(bool(got_n.position.is_equal_approx(exp_new.position) and got_n.size.is_equal_approx(exp_new.size)),
			"AC §4.4-1：overshoot=0.15 → 顶边贴顶、h=2half=0.65/3.5（满窗例 pos≈(362.1,0) size≈(427.9,240.7)）")
		var nlo: Vector2 = (got_n.position - inner.position) / inner.size
		var nhi: Vector2 = (got_n.end - inner.position) / inner.size
		check(bool(absf(nlo.x - lon) < 0.0001 and absf(nlo.y) < 0.0001
			and absf(nhi.x - (0.5 + 0.65 / 3.5)) < 0.0001 and absf(nhi.y - 2.0 * half_new) < 0.0001),
			"AC §4.4-1：新框归一数值锚 x∈[0.314,0.686]、y∈[0.0,0.371]（旧 [0.314,0.686]² 纵向居中留痕）")
		check(bool(got_n.position.x < got_d.position.x and got_n.position.y <= got_d.position.y + 0.001
			and got_n.end.x > got_d.end.x and got_n.end.y > got_d.end.y),
			"AC §4.4-1：overshoot 扩展框在横/下三向严格外扩（顶边同贴顶=新几何必然）")
		var inner2: Rect2 = sk_s.pillarbox_rect(Vector2(320, 180), Vector2(640, 480))
		var got_ln: Rect2 = sk_s.cursor_zone_rect(Vector2(320, 180), Vector2(640, 480), 3.5, 0.15)
		var exp_ln := Rect2(inner2.position + Vector2(lon, 0.0) * inner2.size, Vector2(2.0 * half_new, 2.0 * half_new) * inner2.size)
		check(bool(got_ln.position.is_equal_approx(exp_ln.position) and got_ln.size.is_equal_approx(exp_ln.size)),
			"AC §4.4-1：letterbox 例 overshoot=0.15（框随内衬矩形自适应，顶边贴顶）")
		var got_l0: Rect2 = sk_s.cursor_zone_rect(Vector2(320, 180), Vector2(640, 480), 3.5, 0.0)
		var exp_l0 := Rect2(inner2.position + Vector2(lof, 0.0) * inner2.size, Vector2(1.0 / 3.5, 1.0 / 3.5) * inner2.size)
		check(bool(got_l0.position.is_equal_approx(exp_l0.position) and got_l0.size.is_equal_approx(exp_l0.size)),
			"AC §4.4-1：letterbox 例 overshoot=0 → 顶边贴顶（X1 纵向居中语义退役留痕）")
		var fb0n: Rect2 = sk_s.cursor_zone_rect(Vector2(320, 180), Vector2(640, 480), 0.0, 0.15)
		check(bool(fb0n.position.is_equal_approx(inner2.position) and fb0n.size.is_equal_approx(inner2.size)),
			"X1：无效增益（≤0）时 overshoot 不参与（同守卫退化为整个内衬矩形，不猜值）")
	if _script_has_method(sk_s, "map_cursor_gain") and _script_has_method(sk_s, "map_cursor_overshoot"):
		check(is_equal_approx(float(sk_s.map_cursor_gain()), float(gm.get("CURSOR_GAIN", 2.5))), "X1：map_cursor_gain()==GestureMap.CURSOR_GAIN（同源读取保持；批次 AA W2-2 后=2.5，硬编码旧值 3.5 等价改写为同源比对）")
		check(is_equal_approx(float(sk_s.map_cursor_overshoot()), 0.15), "X1：map_cursor_overshoot()==GestureMap.CURSOR_OVERSHOOT=0.15（同源读取测试锁定）")

	# ---- 4. P2-5 哨兵语义分离（router 探针授权域；在屏标志生命周期）----
	var rt_s: Variant = load("res://autoload/gesture_router.gd")
	router = rt_s.new()
	add_child(router)
	await process_frame
	mock = MockLayer.new()
	add_child(mock)
	router.set_cursor_layer(mock)
	# 场景 A：该手从未有 cursor_move → 「无光标」哨兵原语义保持（早退不推 motion）
	router.set("_last_cursor_pos", {})
	router.set("_cursor_seen", {})
	mock.calls.clear()
	var a_ok: bool = bool(router.call("_hovered_ui_interactive", "left"))
	check(a_ok == false, "X1-P2-5：无光标位 → _hovered_ui_interactive=false（哨兵原语义保持）")
	check(_motion_count() == 0, "X1-P2-5：无光标位早退不推 synth_motion（原语义保持）")
	# 场景 B：cursor_move 派发置在屏标志——负坐标（overshoot 左缘余量）光标 ≠ 无光标
	router.call("_dispatch", {"type": "cursor_move", "side": "left", "pos": Vector2(-0.15, 0.5)})
	var seen: Variant = router.get("_cursor_seen")
	check(seen is Dictionary and bool((seen as Dictionary).get("left", false)),
		"X1-P2-5：cursor_move 派发置在屏标志（负坐标光标不再被哨兵吞没）")
	var cached: Vector2 = Vector2(router.get("_last_cursor_pos").get("left", Vector2(9, 9)))
	var vp_size: Vector2 = router.get_viewport().get_visible_rect().size
	check(cached.x < 0.0 and is_equal_approx(cached.x, -0.15 * vp_size.x) and is_equal_approx(cached.y, 0.5 * vp_size.y),
		"X1-P2-5：左缘余量光标 content 落地缓存（x=−m×视宽<0=负坐标真实入位）")
	# 场景 C：负坐标光标 → 走 hover 实测路径（推 synth motion；旧 pos.x<0 哨兵早退=语义相混证据）
	mock.calls.clear()
	var c_ok: bool = bool(router.call("_hovered_ui_interactive", "left"))
	check(_motion_count() > 0, "X1-P2-5：负坐标光标进入 hover 实测路径（推 synth_motion；旧码哨兵早退不推）")
	check(c_ok == false, "X1-P2-5：负坐标光标处无控件 → hover 实测 false（不误判为可点，命中判定交给引擎）")
	# 场景 D：reset_runtime 清零在屏标志（与 _last_cursor_pos 同生命周期，W P3-2c 同族）
	router.call("reset_runtime")
	var seen2: Variant = router.get("_cursor_seen")
	check(seen2 is Dictionary and (seen2 as Dictionary).is_empty(),
		"X1-P2-5：reset_runtime 清零在屏标志（跨场景光标缓存三键清零同族纪律）")
	router.queue_free()
	mock.queue_free()
	await process_frame
	finish()
