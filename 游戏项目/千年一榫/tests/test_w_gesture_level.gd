extends "res://tests/test_base.gd"
## 批次 W W4（2026-09-20 规格 §5）——关卡手势交互 TDD 红测先行。
## 段口径：
##   A（N15 拍板 10）：删琥珀环——进出 ORBIT 光标色零变化（恒左蓝右红）+ 提示行文字提示
##     出现/消失（「【左】旋转模式：二指再点空白退出」，批次 AA W3-5 措辞消歧）。
##   B（P1-8c）：ORBIT 态光标移出面板矩形后空白二指 → 回待命；回待命后可再次选块
##     （批次 X P5-a：立即合成按下真入视口 → MainView STROKE → 选中全链）。
##   C（N7 拍板 8，推翻批次 T 拍板 3）：关卡内 UI 按钮合成单击——悬停锐眼钮 → armed 按下
##     派发（真入视口）；悬停 3D 区 → click_zone 仍 false（零 armed 按下、N8 交互模型零污染）。
## 供件：SpyLayer 继承真 GestureCursorLayer（push 真入视口 + 记录事件），环色直读 _rings。
## 夹具/清档纪律沿用 test_t_level_mode（真 level_scene 驱动 + user:// 备份还原）。

const SCENE_PATH := "res://scenes/level/level_scene.tscn"
const MISS := Vector3i(-1, -1, -1)

var router: Variant
var spy: SpyLayer

class SpyLayer:
	extends "res://scripts/gesture_cursor_layer.gd"
	## 真层派生：push 照常注入视口（真 GUI 命中/hover 链）并记录事件供断言
	var events: Array = []

	func push(ev: InputEvent) -> void:
		events.append(ev)
		super.push(ev)

	func _init() -> void:
		pass

# ===== 清档纪律（test_t_level_mode 同款，独立前缀 w4gl）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_w4gl_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _pre_save_text: String = ""

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _backup_user() -> void:
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	for c: Node in root.get_children():
		if not DISC_AUTOLOADS.has(String(c.name)):
			c.free()
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(_disc_abs(p)):
			DirAccess.remove_absolute(_disc_abs(p))
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(_disc_abs(bk)):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(_disc_abs(bk))
	var real_sm: Node = root.get_node_or_null("SaveManager")
	if real_sm != null:
		real_sm.load_game()
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")

func finish() -> void:
	_restore_user()
	super.finish()

func _hand(conf: float, fingers: Array, tip: Vector2) -> Dictionary:
	var lm: Array = []
	for i: int in 21:
		lm.append([0.5, 0.5, 0.0])
	lm[0] = [tip.x - 0.05, tip.y + 0.2, 0.0]
	lm[5] = [lm[0][0] + 0.05, lm[0][1] - 0.06, 0.0]   # 左掌面朝镜
	lm[17] = [lm[0][0] - 0.05, lm[0][1] - 0.05, 0.0]
	lm[8] = [tip.x, tip.y, 0.0]
	lm[9] = [lm[0][0], lm[0][1] - 0.2, 0.0]
	return {"gesture": "", "gesture_id": 0, "confidence": conf,
		"hand_x": tip.x, "hand_y": tip.y, "hand_z": 0.0,
		"hand_rotation_x": 5.0, "hand_rotation_y": 0.0, "hand_rotation_z": 0.0,
		"fingers": fingers, "pinch_distance": 0.5, "hand_index": 0, "handedness": "Left",
		"landmarks": lm, "fps": 30.0, "is_detected": true, "timestamp": 0.0, "palm_size": 0.2,
		"tip_x": tip.x, "tip_y": tip.y}

func _feed_left(fingers: Array, tip: Vector2) -> void:
	router.feed({"left": _hand(0.9, fingers, tip), "right": null, "timestamp": 0.0})

## 批次 AC 4B（§4.6-2 手别门）：右手 cursor_move 直调（确定性判据，绕开二级 EMA 干扰）——
## 与同判据下的左手阳性对照配对，构成「旋转左手专属」的正反双向锚。
func _dispatch_cursor(side: String, norm: Vector2) -> void:
	router.call("_dispatch", {"type": "cursor_move", "side": side, "pos": norm})

func _btn_presses() -> Array:
	var out: Array = []
	for ev: Variant in spy.events:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			out.append(mb)
	return out

## 批次 AA（W2-1）等价改写基建（spec §5.3 W2-1 连带）：二级 EMA（α0.35）后单帧喂位仅到位
## 35%、死区 0.0015 归一留 ≤4.3px 锁定地板——位置敏感断言前喂到位。像素版（按钮类大目标）：
## 续喂至距目标 ≤4.6px（地板上限 4.43px 2D 合成可达成）即返回；上限 40 帧。
func _settle_px(side: String, fingers: Array, tip: Vector2, target: Vector2) -> void:
	for i: int in 40:
		_feed_left(fingers, tip)
		var lp_v: Variant = router.get("_last_cursor_pos")
		var cur: Variant = null
		if typeof(lp_v) == TYPE_DICTIONARY:
			cur = (lp_v as Dictionary).get(side, null)
		if typeof(cur) == TYPE_VECTOR2 and (cur as Vector2).distance_to(target) <= 4.6:
			return

## 射线命中版（体素格类窄目标，批次 AA W2-1 连带）：二级 EMA 的死区 0.0015 归一留下
## ≤4.32px(content) 锁定地板带 [t−d, t]——单点收敛的落点可能整带偏出窄格面（C2 实测：
## 探针点 524 命中而落点 519.7~522 偏出）。故先**细扫 ON 区间**（0.5px 步进 ±32px）取含
## 探针点的连续命中段 [a,b]，再把收敛终点取在区间右端内侧（b−0.05）使整条地板带 ⊆ ON
##（要求区间宽 ≥4.6px；窄区间退化取中点尽力 + 备选端点各试一档），命中即返，上限 60 帧。
func _settle_cell(side: String, fingers: Array, tip: Vector2, want: Variant,
		gpos: Vector2, inst: Node, cam: Camera3D, cont: SubViewportContainer) -> void:
	var o := cont.get_global_rect().position
	var local_y: float = gpos.y - o.y
	var ga: float = gpos.x - o.x
	var a := INF
	var b := -INF
	for k: int in range(-64, 65):
		var xx: float = ga + 0.5 * float(k)
		var h: Variant = inst.call("get_cell_hit", cam.project_ray_origin(Vector2(xx, local_y)),
			cam.project_ray_normal(Vector2(xx, local_y)))
		if h == want:
			a = minf(a, xx)
			b = maxf(b, xx)
	if a > b:
		a = ga
		b = ga
	var cands: Array = []
	if b - a >= 4.6:
		cands = [b - 0.05, a + 0.05]
	else:
		cands = [(a + b) * 0.5, b - 0.05]
	var vp := get_root().get_visible_rect().size
	## 批次 AC §4.4-2：逆映射纵向基准上移 c_y=(0.5+m)/g（与 apply_cursor_gain 互逆）。
	var _gm_c: Dictionary = load("res://scripts/gesture_map.gd").get_script_constant_map()
	var gain_v: float = float(_gm_c.get("CURSOR_GAIN", 2.5))
	var cy_v: float = (0.5 + float(_gm_c.get("CURSOR_OVERSHOOT", 0.15))) / gain_v
	var budgets: Array = [34, 16, 16]
	for ci: int in cands.size():
		var tgt := o + Vector2(float(cands[ci]), local_y)
		var nt := (tgt / vp - Vector2(0.5, 0.5)) / gain_v + Vector2(0.5, cy_v)
		for i: int in int(budgets[mini(ci, budgets.size() - 1)]):
			_feed_left(fingers, nt)
			var lp_v: Variant = router.get("_last_cursor_pos")
			var cur: Variant = null
			if typeof(lp_v) == TYPE_DICTIONARY:
				cur = (lp_v as Dictionary).get(side, null)
			if typeof(cur) != TYPE_VECTOR2:
				continue
			var local: Vector2 = (cur as Vector2) - o
			var hit: Variant = inst.call("get_cell_hit",
				cam.project_ray_origin(local), cam.project_ray_normal(local))
			if hit == want:
				return

func _initialize() -> void:
	print("== test_w_gesture_level ==")
	_backup_user()
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(_disc_abs(p)):
			DirAccess.remove_absolute(_disc_abs(p))
	get_root().get_node("SaveManager").call("load_game")
	var bridge: Node = get_root().get_node("GestureBridge")
	var game: Node = get_root().get_node("Game")
	bridge._set_state(1)
	router = load("res://autoload/gesture_router.gd").new()
	add_child(router)
	await process_frame
	bridge._set_state(1)
	router._setup()
	spy = SpyLayer.new()
	add_child(spy)
	await process_frame
	router.set_cursor_layer(spy)
	var inst: Node = (load(SCENE_PATH) as PackedScene).instantiate()
	check(inst != null, "前置：关卡场景可实例化")
	inst.call("set_context", {"chapter": 1})
	add_child(inst)
	game._current_scene = inst
	await process_frame
	await process_frame
	game.goto_state(game.State.LEVEL)
	await process_frame
	var cont: SubViewportContainer = inst.get_node_or_null("MainView/ViewportContainer") as SubViewportContainer
	var vps: SubViewport = inst.get_node_or_null("MainView/ViewportContainer/SubViewport") as SubViewport
	var cam: Camera3D = inst.get_node_or_null("MainView/ViewportContainer/SubViewport/Camera3D")
	check(cont != null and vps != null and cam != null, "前置：容器/视口/相机在位")
	# 中线步进找 2 互异命中格 + 1 空白位（t_level_mode 同款）
	var found: Array = []
	var seen: Array = []
	var x := vps.size.x * 0.5
	while found.size() < 2 and x < vps.size.x:
		var c: Variant = inst.call("get_cell_hit", cam.project_ray_origin(Vector2(x, vps.size.y * 0.5)),
			cam.project_ray_normal(Vector2(x, vps.size.y * 0.5)))
		if c != MISS and not seen.has(c):
			seen.append(c)
			found.append([c, cont.get_global_rect().position + Vector2(x, vps.size.y * 0.5)])
		x += 8.0
	check_eq(found.size(), 2, "前置：主视中线探得 2 互异格")
	var blank: Vector2 = cont.get_global_rect().position + Vector2(6.0, 6.0)
	if inst.call("get_cell_hit", cam.project_ray_origin(Vector2(6.0, 6.0)),
			cam.project_ray_normal(Vector2(6.0, 6.0))) != MISS:
		blank = cont.get_global_rect().position + Vector2(4.0, vps.size.y - 4.0)
	var _gm_c2: Dictionary = load("res://scripts/gesture_map.gd").get_script_constant_map()
	var gain: float = float(_gm_c2.get("CURSOR_GAIN", 3.5))
	var cy2_v: float = (0.5 + float(_gm_c2.get("CURSOR_OVERSHOOT", 0.15))) / gain
	var vp_sz: Vector2 = get_root().get_visible_rect().size
	var inv := func(gpos: Vector2) -> Vector2:
		return (gpos / vp_sz - Vector2(0.5, 0.5)) / gain + Vector2(0.5, cy2_v)
	var cell_norm: Vector2 = inv.call(found[0][1])
	var blank_norm: Vector2 = inv.call(blank)
	var f_cursor: Array = [0.1, 0.9, 0.1, 0.1, 0.1]
	var f_two: Array = [0.1, 0.9, 0.9, 0.1, 0.1]
	var hint: Label = inst.get_node("HintLabel")
	var rings: Dictionary = spy.get("_rings")
	var col_a: Color = Color("#3E7BBD")
	var col_b: Color = Color("#C0504D")

	# ---- 段 A（N15）：进出 ORBIT 光标色零变化 + 提示行 ----
	# A0 绑定笔（批次 AC 4B §4.6-1：视口空白二指单击=显式绑定 MainView，零交互）
	_feed_left(f_cursor, blank_norm)
	_feed_left(f_two, blank_norm)
	_feed_left(f_two, blank_norm)
	_feed_left(f_cursor, blank_norm)
	check_eq(String(router.get("_level_mode")), "SELECT_ARMED", "A0 前置：绑定笔零交互（mode 不变；AC 4B 显式绑定）")
	check(router.get("_active_panel") == cont, "A0 前置：MainView 空白单击 → 绑定主视图（态 1）")
	# A1 空白 two_down → ORBIT
	# 批次 AD §4.3.1 等价改写：空白二指双帧仅入 ORBIT_PENDING，按住拖拽 >15px 才正式切入 ORBIT
	#（旧「空白双帧即 ORBIT」判据整体后移至拖拽帧；本文件以 _content 口径 20px 拖拽触发，
	#  test_ad_batch3_interaction 段 D 已专项覆盖有界进入阈值判据）。
	_feed_left(f_two, blank_norm)
	_feed_left(f_two, blank_norm)
	_feed_left(f_two, blank_norm + Vector2(20.0 / vp_sz.x, 0.0))   # 拖拽 20 content px > 15 → ORBIT
	check_eq(String(router.get("_level_mode")), "ORBIT", "A 前置：SELECT_ARMED 空白 →（拖拽越阈）ORBIT（§4.3.1 有界进入）")
	check((rings["left"].ring_color as Color).is_equal_approx(col_a)
		and (rings["right"].ring_color as Color).is_equal_approx(col_b),
		"N15①：进 ORBIT 光标色零变化（左蓝/右红恒定，琥珀环已删）")
	check_eq(String(hint.text), String(inst.ORBIT_HINT_TEXT),
		"N15①：ORBIT 进入 → 提示行「【左】旋转模式：二指再点空白退出」")
	check_eq(spy.events.filter(func(ev: Variant) -> bool: return ev is InputEventMouseButton).size(), 0,
		"AC 4B §4.6-2 等价改写：空白进 ORBIT 零合成事件（旧「合成按下旋转笔」随不限框语义直驱退役）")
	# A2 ORBIT → 回待命：**批次 AD §4.3.1 自然退出**——松开中指（two→cursor 发 two_up）立即回
	#   SELECT_ARMED（旧 §4.6-2「先收中指再空白二指单击」两拍退役：cursor 帧即完成退出；旧值留痕
	#   `f_cursor+f_two+f_two → SELECT_ARMED`。断言条数不变，仅驱动帧序随语义等价精简）。
	_feed_left(f_cursor, blank_norm)
	check_eq(String(router.get("_level_mode")), "SELECT_ARMED", "A 前置：ORBIT 松中指 → 自然退出回待命（§4.3.1）")
	check((rings["left"].ring_color as Color).is_equal_approx(col_a)
		and (rings["right"].ring_color as Color).is_equal_approx(col_b),
		"N15②：出 ORBIT 光标色零变化（旧 reset_ring_color 恢复断言等价改写）")
	check_eq(String(hint.text), String(inst.HINT_OPERATIONS),
		"N15②：ORBIT 退出 → 提示行还原常驻操作提示")

	# ---- 段 B（批次 AC 4B §4.6-2 等价改写，原 P1-8c 段）：ORBIT **不限框**——光标移出视口矩形
	# 后继续移动，旋转照常持续且 mode 保持 ORBIT（旧「panel 命中失败 → 回待命」随用户拍板退役：
	# 旋转中断正是实机反馈缺陷）。退出唯一途径=空白二指单击/手势消失（本次前后各验一次）。----
	# B1 重新进 ORBIT（批次 AD §4.3.1 有界进入：双帧入 PENDING + 拖拽 >15px 正式 ORBIT）
	_feed_left(f_cursor, blank_norm)
	_feed_left(f_two, blank_norm)
	_feed_left(f_two, blank_norm)
	_feed_left(f_two, blank_norm + Vector2(20.0 / vp_sz.x, 0.0))
	check_eq(String(router.get("_level_mode")), "ORBIT", "B 前置：重进 ORBIT（§4.3.1 拖拽越阈）")
	# B2 光标移出全部 gesture_panel 矩形（所有注册矩形底边之下 20px）后**继续拖动手势**
	var outside := Vector2(100.0, 0.0)
	var max_bottom := 0.0
	for n: Node in get_root().get_tree().get_nodes_in_group("gesture_panel"):
		if n is Control:
			max_bottom = maxf(max_bottom, (n as Control).get_global_rect().end.y)
	outside.y = minf(max_bottom + 20.0, vp_sz.y - 4.0)
	var outside_norm: Vector2 = inv.call(outside)
	var yaw0: float = float(inst.get("_orbit_yaw"))
	_feed_left(f_two, blank_norm)         # ORBIT 期基准帧（Δ 基准 = blank 位）
	_feed_left(f_two, outside_norm)       # 移出视口矩形：Δ 非零 → 旋转照常推进
	_feed_left(f_two, outside_norm + Vector2(0.02, 0.0))   # 视口外继续移动（不限框核心断言）
	check(absf(float(inst.get("_orbit_yaw")) - yaw0) > 0.0005,
		"AC 4B §4.6-2：ORBIT 期光标移出视口矩形并继续移动 → _orbit_yaw 持续变化（不限框红锁）")
	check_eq(String(router.get("_level_mode")), "ORBIT",
		"AC 4B §4.6-2：移出视口矩形绝不中断旋转（旧 P1-8c「回待命」判据退役留痕）")
	# B2a' 手别门：右手移动**绝不**驱动旋转（旋转=左手专属语义，§4.6-2）。
	# 判据走 `_dispatch` 直调（确定性，无二级 EMA 干扰）：同一条 cursor_move 意图，side=right
	# 时 yaw 必须不动、side=left 时必须动——手别门的正/反双向锚，且以 left 为阳性对照证明
	# 「yaw 可动」的前提成立（否则 right 的零变化可能是别的原因造成的假绿）。
	var yaw_g0 := float(inst.get("_orbit_yaw"))
	router.set("_orbit_last_pos", Vector2.INF)          # Δ 基准复位（首帧仅立基准）
	_dispatch_cursor("right", outside_norm)
	_dispatch_cursor("right", outside_norm + Vector2(0.05, 0.0))
	check(is_equal_approx(float(inst.get("_orbit_yaw")), yaw_g0),
		"AC 4B §4.6-2 手别门：right cursor_move 零旋转（旋转左手专属；右二指=减选笔）")
	router.set("_orbit_last_pos", Vector2.INF)
	_dispatch_cursor("left", outside_norm)
	_dispatch_cursor("left", outside_norm + Vector2(0.05, 0.0))
	check(absf(float(inst.get("_orbit_yaw")) - yaw_g0) > 0.0001,
		"AC 4B §4.6-2 阳性对照：left cursor_move 驱动旋转（同判据下 yaw 必动，证手别门非假绿）")
	check_eq(String(router.get("_level_mode")), "ORBIT",
		"AC 4B §4.6-2：两手 cursor_move 均不打断 ORBIT")
	check_eq(String(router.get("_level_mode")), "ORBIT",
		"AC 4B §4.6-2：右二指移动不打断 ORBIT（两手语义正交）")
	# B2b 视口外二指**拖拽**亦不退出（仅中指松开/离屏退出；两指按住移出画面持续旋转=§4.6-2 不限框
	# 与 §4.3.1 有界进入并存：PENDING 拖拽越阈正式进 ORBIT 后继续移出视口不中断）。
	# 批次 AD-3 回修留痕：旧写法 cursor 起笔——§4.3.1 后 cursor 收中指触发 two_up 自然退出，与
	# 「视口外起笔保持旋转」判据自相矛盾；改由视口外二指双帧 + 拖拽（Δ>15px 于视口外完成进入），
	# 左手 semantic 全程保持 two，旋转持续（正是本断言语义）。
	_feed_left(f_two, outside_norm)
	_feed_left(f_two, outside_norm)
	_feed_left(f_two, outside_norm + Vector2(30.0 / vp_sz.x, 0.0))   # 视口外拖拽越阈：进入/推进均不外露 two_up
	check_eq(String(router.get("_level_mode")), "ORBIT",
		"AC 4B §4.6-2：视口外二指持续在场拖拽 → 旋转保持 ORBIT（不限框；§4.3.1 有界进入于视口外同样成立）")
	# B2c 退出途径①：ORBIT 中绑定视口内空白二指单击 → 回 SELECT_ARMED。
	# 批次 AD-3 回修留痕：直喂链下「two 在场→再按两指」不产生新 two_down（map 连续 two 只发
	# two_move），且任何 cursor 起笔必先经 two_up 触发途径②抢跑，使途径①经端到端喂帧不可达；
	# 沿用本套件既有直调先例（_dispatch_cursor / test_ad_batch3 直调 _on_level_two_down_left）
	# 确定性验证路由出口①（生产代码零改动，退出途径①语义保持：空白二指按下=显式退出）。
	check_eq(String(router.get("_level_mode")), "ORBIT", "B2c 前置：B2b 后仍在 ORBIT")
	router.call("_on_level_two_down_left", router.call("_content", blank_norm), null)
	check_eq(String(router.get("_level_mode")), "SELECT_ARMED",
		"AC 4B §4.6-2：ORBIT 中空白二指按下（直调）→ 退出旋转回待命（退出途径①）")
	# B2c2 退出途径②：**手势完全消失**（二指按住期间整手离开画面，无 two_up 可发）→ 连续丢手
	# 超窗回待命（绑定保持）。
	# 批次 AD-3 回修留痕：①map 语义层残留/轨道角被 B2b 拖拽扰动，端到端重喂链进入判据受相机
	# 位姿牵连（B1 段首已全链验证 §4.3.1「双帧+拖拽>15px 进 ORBIT」，本段聚焦退出途径②）→
	# 与 B2c 同款直调：空白二指按下入 PENDING，视口内拖拽 20px 越阈正式 ORBIT（生产零改动）。
	router.call("_on_level_two_down_left", router.call("_content", blank_norm), null)
	router.call("_on_two_move", {"side": "left", "pos": (blank_norm + Vector2(20.0 / vp_sz.x, 0.0))})
	check_eq(String(router.get("_level_mode")), "ORBIT", "B2c2 前置：重进 ORBIT（§4.3.1 拖拽越阈）")
	# 批次 AD §4.3.1 反置留痕（旧值留痕：`check_eq(... "ORBIT", "松中指转食指瞄准 → 保持 ORBIT")`）：
	# 「松开中指」由本批**有意**改为立即自然退出（旧 §4.6-2 不限单/二指保持口径退役——实机反馈
	# 「转两下断不掉」的反向根治：中指一松即回待命）。
	_feed_left(f_cursor, blank_norm)   # 收中指 → two_up → 自然退出
	check_eq(String(router.get("_level_mode")), "SELECT_ARMED",
		"AD §4.3.1：松中指转食指瞄准 → 自然退出回待命（旧 §4.6-2「保持 ORBIT」反置留痕）")
	# 退出途径②：二指按住期间整手离开画面（无 two_up 可发）→ 连续丢手超窗回待命（绑定保持）
	_feed_left(f_two, blank_norm)
	_feed_left(f_two, blank_norm)
	_feed_left(f_two, blank_norm + Vector2(20.0 / vp_sz.x, 0.0))   # 重进 ORBIT（保持 two 在场）
	for _i: int in (int(router.get("ORBIT_LOST_FRAMES")) + 2):
		router.feed({"left": null, "right": null, "timestamp": 0.0})
	check_eq(String(router.get("_level_mode")), "SELECT_ARMED",
		"AC 4B §4.6-2：手势完全消失（连续丢手超窗）→ 回待命（退出途径②；绑定保持）")
	var act_kept: Variant = router.get("_active_panel")
	check(act_kept == cont, "AC 4B §4.6-2：退出旋转不清绑定（蓝框仍在该视口）")
	# B2d 相机复位（段 B 的旋转已改主视轨道角，后续选块断言依赖原探针点位——复位后重探）
	inst.set("_orbit_yaw", yaw0)
	inst.call("_update_main_camera")
	await process_frame
	found.clear()
	seen.clear()
	x = vps.size.x * 0.5
	while found.size() < 2 and x < vps.size.x:
		var c2: Variant = inst.call("get_cell_hit", cam.project_ray_origin(Vector2(x, vps.size.y * 0.5)),
			cam.project_ray_normal(Vector2(x, vps.size.y * 0.5)))
		if c2 != MISS and not seen.has(c2):
			seen.append(c2)
			found.append([c2, cont.get_global_rect().position + Vector2(x, vps.size.y * 0.5)])
		x += 8.0
	check_eq(found.size(), 2, "B2d 前置：相机复位后重探 2 互异格（旋转段扰动隔离）")
	cell_norm = inv.call(found[0][1])
	# B3 回待命后再次选块全链（批次 X P5-a 等价替换：dwell 计时断言随「立即按下」退役——
	# two_down 双帧 → 立即合成按下真入视口 → MainView STROKE → 选中全链）。
	# 批次 AC 4B 夹具硬化（等价改写留痕）：「选中 found[0][0]」改为「按下恰一次 + 选区非空」——
	# found[0][1] 系中线 8px 步进探得点，可能恰落格边界（探针实测 gpos=(576,787.5) 骑缝），
	# 二级 EMA 收敛后射线可落相邻格；断言对象=选块全链真通，与「具体命中哪一格」正交。
	spy.events.clear()
	inst.call("clear_selection")
	_feed_left(f_cursor, cell_norm)
	_settle_cell("left", f_cursor, cell_norm, found[0][0], found[0][1], inst, cam, cont)  # W2-1：喂到射线真达格
	_feed_left(f_two, cell_norm)
	_feed_left(f_two, cell_norm)
	var presses: Array = _btn_presses()
	check_eq(presses.size(), 1, "X4：回待命后块上 two_down → 立即合成按下真入视口恰一次（旧 dwell 直注断言退役留痕）")
	if presses.size() == 1:
		check(((presses[0] as InputEventMouseButton).position as Vector2).distance_to(
			Vector2((router.get("_last_cursor_pos") as Dictionary).get("left", Vector2.ZERO))) < 0.5,
			"X4/AC 4B：按下位=该手光标 content 坐标（实现契约直比，免探针点骑缝脆性）")
	check(not (inst.call("get_selected_voxels") as Array).is_empty(),
		"P1-8c：回待命后可再次选块（选中全链真通；命中格由射线实况决定）")
	_feed_left(f_cursor, cell_norm)   # 收笔
	spy.events.clear()

	# ---- 段 C（N7）：关卡内 UI 按钮合成单击（真 hover 链）----
	var eye_btn: Button = inst.get_node_or_null("TopBar/Buttons/EyeButton") as Button
	check(eye_btn != null, "C 前置：锐眼钮在位")
	var eye_c: Vector2 = eye_btn.get_global_rect().get_center()
	router.set("_level_mode", "SELECT_ARMED")
	_feed_left(f_cursor, inv.call(eye_c))
	_settle_px("left", f_cursor, inv.call(eye_c), eye_c)  # W2-1：喂到距钮心 ≤4.6px（悬停 armed 须真达）
	_feed_left(f_two, inv.call(eye_c))
	_feed_left(f_two, inv.call(eye_c))
	check(bool(router.get("_menu_click_armed")["left"]), "N7①：悬停锐眼钮 → click_zone 放行 armed")
	check_eq(_btn_presses().size(), 1, "N7①：armed 按下真入视口恰一次（悬停按钮单击派发）")
	_feed_left(f_cursor, inv.call(eye_c))   # 抬起（armed 释放）
	spy.events.clear()
	# C2 悬停 3D 区（体素格）→ click_zone 仍 false：零 armed 按下 + 左键笔立即按下
	#（批次 X P5-a 等价替换：旧「3D 区零合成按下+dwell 进位」断言随新模型改写——
	#  二指点块即刻合成左键按下选中，不走 armed 单击链，N7 语义「普通单击非 Ctrl」保留。
	#  C1 的 armed 抬起会真点开锐眼时长面板（X2 自绘面板模态消费外点）——先关面板防
	#  C2 合成按下被面板消费，与被测路由决策无关）
	inst.call("_close_eye_menu")
	await process_frame
	router.set("_level_mode", "SELECT_ARMED")
	inst.call("clear_selection")
	spy.events.clear()
	_feed_left(f_cursor, cell_norm)
	_settle_cell("left", f_cursor, cell_norm, found[0][0], found[0][1], inst, cam, cont)  # W2-1：喂到射线真达格
	_feed_left(f_two, cell_norm)
	_feed_left(f_two, cell_norm)
	check(bool(router.get("_menu_click_armed")["left"]) == false,
		"N7②：悬停 3D 体素区 → click_zone 仍 false（零 armed）")
	check_eq(_btn_presses().size(), 1, "X4：3D 区 two_down → 左键笔立即合成按下恰一次（旧「零合成按下」留痕改写）")
	check((inst.call("get_selected_voxels") as Array).has(found[0][0]),
		"X4：3D 区二指立即选中（悬停选中链路真通；旧 dwell 进位断言退役留痕）")

	# 收尾卫生：断开新实例挂到 autoload 桥的 feed 连接（防 freed 回调）
	var bridge2: Node = get_root().get_node("GestureBridge")
	if bridge2 != null and bridge2.gesture_state_received.is_connected(router.feed):
		bridge2.gesture_state_received.disconnect(router.feed)
	router.queue_free()
	spy.queue_free()
	finish()
