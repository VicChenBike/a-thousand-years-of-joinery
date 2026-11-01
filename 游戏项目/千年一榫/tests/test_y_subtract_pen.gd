extends "res://tests/test_base.gd"
## 批次 Y（Y-A12/Y-A13，spec §2-⑫⑬拍板）：右手二指=纯减选笔 + 首点激活面板且语义同施——TDD 红测。
##   Y-A12：router 来源判别——右笔仅命中**已选块**才合成 Ctrl+左键事件，未选块/空白零事件
##     （旧码未选块反被「Ctrl+点击选中」=减选笔变选笔缺陷红灯）；键鼠 Ctrl+拖拽路径零改动；
##     ORBIT 态选块类手势（右二指）统一忽略（左右口径对称）。
##   Y-A13：进关后首次二指点击激活面板**且**执行选中语义（旧码激活笔 return 吞首笔=红灯）。
## 清档纪律沿用 test_x_gesture_remap（真 level_scene + SpyLayer + user:// 备份还原，独立前缀 y3sp）。

const SCENE_PATH := "res://scenes/level/level_scene.tscn"
const MISS := Vector3i(-1, -1, -1)

# fingers 夹具（test_x_gesture_remap 同源）
const F_CURSOR := [0.1, 0.9, 0.1, 0.1, 0.1]
const F_TWO := [0.1, 0.9, 0.9, 0.1, 0.1]

var router: Variant
var spy: Variant

class SpyLayer:
	extends "res://scripts/gesture_cursor_layer.gd"
	var events: Array = []
	func push(ev: InputEvent) -> void:
		events.append(ev)
		super.push(ev)
	func _init() -> void:
		pass

# ===== 清档纪律（test_x_gesture_remap 同款，独立前缀 y3sp）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_y3sp_backup_"
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

# ===== 手势夹具（test_x_gesture_remap 同款）=====
func _hand(conf: float, fingers: Array, tip: Vector2, hside: String = "Left") -> Dictionary:
	var lm: Array = []
	for i: int in 21:
		lm.append([0.5, 0.5, 0.0])
	lm[0] = [tip.x - 0.05, tip.y + 0.2, 0.0]
	lm[5] = [lm[0][0] + 0.05, lm[0][1] - 0.06, 0.0]
	lm[17] = [lm[0][0] - 0.05, lm[0][1] - 0.05, 0.0]
	lm[8] = [tip.x, tip.y, 0.0]
	lm[9] = [lm[0][0], lm[0][1] - 0.2, 0.0]
	return {"gesture": "", "gesture_id": 0, "confidence": conf,
		"hand_x": tip.x, "hand_y": tip.y, "hand_z": 0.0,
		"hand_rotation_x": 5.0, "hand_rotation_y": 0.0, "hand_rotation_z": 0.0,
		"fingers": fingers, "pinch_distance": 0.5, "hand_index": 0, "handedness": hside,
		"landmarks": lm, "fps": 30.0, "is_detected": true, "timestamp": 0.0, "palm_size": 0.2,
		"tip_x": tip.x, "tip_y": tip.y}

func _feed(side: String, fingers: Array, tip: Vector2) -> void:
	var h: Dictionary = _hand(0.9, fingers, tip, "Left" if side == "left" else "Right")
	router.feed({"left": h if side == "left" else null, "right": h if side == "right" else null, "timestamp": 0.0})

func _btn_events(pressed: bool) -> Array:
	var out: Array = []
	for ev: Variant in spy.events:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed == pressed:
			out.append(mb)
	return out

func _ctrl_presses() -> Array:
	var out: Array = []
	for ev: Variant in spy.events:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mb.ctrl_pressed:
			out.append(mb)
	return out

func _sel(inst: Variant) -> Array:
	return inst.call("get_selected_voxels") as Array

## 批次 AA（W2-1）等价改写基建（spec §5.3 W2-1 连带）：二级 EMA（α0.35）后单帧喂位仅到位
## 35%，且死区 0.0015 归一留 ≤4.3px 锁定地板——位置敏感断言（右笔命中已选块才合成 Ctrl）
## 前用射线命中回灌喂到位：①先纯收敛（≤48 帧，无微推防目标后移）；②距目标 ≤12px 仍未中
## =地板/探针点位误差 → 朝 +x 细推 6px（>死区使 pos 真跨步）×6 帧驻留逐档深探（探针点近
## 格面左缘，ON 面向右延伸；空白目标朝角落 −6px），上限 4 档。旧「filtered 直喂直出」时代
## 本函数恒 1 帧即中（零行为差）。
func _settle_cell(side: String, fingers: Array, tip: Vector2, want: Variant,
		gpos: Vector2, inst: Node, cam: Camera3D, cont: SubViewportContainer) -> void:
	var origin := tip
	var pushed := 0
	for i: int in 48:
		_feed(side, fingers, tip)
		var lp_v: Variant = router.get("_last_cursor_pos")
		var cur: Variant = null
		if typeof(lp_v) == TYPE_DICTIONARY:
			cur = (lp_v as Dictionary).get(side, null)
		if typeof(cur) != TYPE_VECTOR2:
			continue
		var local: Vector2 = (cur as Vector2) - cont.get_global_rect().position
		var hit: Variant = inst.call("get_cell_hit",
			cam.project_ray_origin(local), cam.project_ray_normal(local))
		if hit == want:
			return
		if pushed < 4 and (cur as Vector2).distance_to(gpos) <= 12.0 and (i % 6) == 5:
			pushed += 1
			var dir: float = -1.0 if (want is Vector3i and want == MISS) else 1.0
			tip = origin + Vector2(dir * 6.0 * float(pushed) / 1152.0
				/ float(load("res://scripts/gesture_map.gd").get_script_constant_map().get("CURSOR_GAIN", 2.5)), 0.0)

func _initialize() -> void:
	print("== test_y_subtract_pen ==")
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
	game.goto_state(game.State.LEVEL)   # state_changed → reset_runtime（_active_panel=null=进关实况）
	await process_frame
	await process_frame
	var cont: SubViewportContainer = inst.get_node_or_null("MainView/ViewportContainer") as SubViewportContainer
	var vps: SubViewport = inst.get_node_or_null("MainView/ViewportContainer/SubViewport") as SubViewport
	var cam: Camera3D = inst.get_node_or_null("MainView/ViewportContainer/SubViewport/Camera3D")
	check(cont != null and vps != null and cam != null, "前置：容器/视口/相机在位")
	# 中线步进探 3 互异命中格 + 空白位（x4gr 同款）
	var found: Array = []
	var seen: Array = []
	var x := vps.size.x * 0.5
	while found.size() < 3 and x < vps.size.x:
		var c: Variant = inst.call("get_cell_hit", cam.project_ray_origin(Vector2(x, vps.size.y * 0.5)),
			cam.project_ray_normal(Vector2(x, vps.size.y * 0.5)))
		if c != MISS and not seen.has(c):
			seen.append(c)
			found.append([c, cont.get_global_rect().position + Vector2(x, vps.size.y * 0.5)])
		x += 8.0
	check_eq(found.size(), 3, "前置：主视中线探得 3 互异格")
	var blank: Vector2 = cont.get_global_rect().position + Vector2(6.0, 6.0)
	if inst.call("get_cell_hit", cam.project_ray_origin(Vector2(6.0, 6.0)),
			cam.project_ray_normal(Vector2(6.0, 6.0))) != MISS:
		blank = cont.get_global_rect().position + Vector2(4.0, vps.size.y - 4.0)
	var _gm_c: Dictionary = load("res://scripts/gesture_map.gd").get_script_constant_map()
	var gain: float = float(_gm_c.get("CURSOR_GAIN", 3.5))
	## 批次 AC §4.4-2：逆映射纵向基准上移 c_y=(0.5+m)/g（与 apply_cursor_gain 互逆）。
	var cy_s: float = (0.5 + float(_gm_c.get("CURSOR_OVERSHOOT", 0.15))) / gain
	var vp_sz: Vector2 = get_root().get_visible_rect().size
	var inv := func(gpos: Vector2) -> Vector2:
		return (gpos / vp_sz - Vector2(0.5, 0.5)) / gain + Vector2(0.5, cy_s)
	var cell1_norm: Vector2 = inv.call(found[0][1])
	var cell2_norm: Vector2 = inv.call(found[1][1])
	var blank_norm: Vector2 = inv.call(blank)
	var cell1: Vector3i = found[0][0]
	var cell2: Vector3i = found[1][0]

	# ================= 段 1（批次 AC 4B §4.6-1 等价改写：旧 Y-A13「首笔二指=激活+选中同施」
	# 随用户拍板退役——现契约=必须先在**视口空白处**二指单击显式绑定视口（点亮蓝框），
	# 绑定当笔零交互；绑定后块上起笔才选块。断言数不变，判据逐条留痕。）=================
	check(router.get("_active_panel") == null, "段 1 前置：进关后 _active_panel 为空（未绑定=态 0，reset_runtime 实况）")
	# 1a. 块上起笔（未绑定态）→ 零动作（旧 Y-A13 首笔即选块旁路退役的红锁）
	_feed("left", F_CURSOR, cell1_norm)
	_feed("left", F_TWO, cell1_norm)
	_feed("left", F_TWO, cell1_norm)
	check(router.get("_active_panel") == null and _btn_events(true).size() == 0,
		"AC 4B §4.6-1：未绑定态块上二指起笔 → 零绑定零合成事件（旧 Y-A13 首笔旁路退役）")
	check(_sel(inst).is_empty(), "AC 4B §4.6-1：未绑定态块上起笔不选块（显式绑定前置）")
	_feed("left", F_CURSOR, cell1_norm)   # 收笔
	spy.events.clear()
	# 1b. 视口空白处二指单击 → 仅绑定（蓝框点亮）+ 零交互
	_feed("left", F_CURSOR, blank_norm)
	_feed("left", F_TWO, blank_norm)
	_feed("left", F_TWO, blank_norm)
	check(router.get("_active_panel") == cont, "AC 4B §4.6-1：视口空白二指单击 → 绑定主视图（描边点亮）")
	check_eq(String(router.get("_level_mode")), "SELECT_ARMED", "AC 4B §4.6-1：绑定当笔不进入旋转（态 0→态 1）")
	check_eq(_btn_events(true).size(), 0, "AC 4B §4.6-1：绑定当笔零合成事件（不选块不旋转）")
	_feed("left", F_CURSOR, blank_norm)
	spy.events.clear()
	# 1c. 绑定后块上起笔 → 选块全链（键鼠同源）
	_feed("left", F_CURSOR, cell1_norm)
	_settle_cell("left", F_CURSOR, cell1_norm, cell1, found[0][1], inst, cam, cont)  # 喂到射线真达 cell1
	_feed("left", F_TWO, cell1_norm)
	_feed("left", F_TWO, cell1_norm)
	check_eq(_btn_events(true).size(), 1, "AC 4B §4.6-1：绑定后块上二指 → 合成左键按下恰一次（左键笔）")
	check(_sel(inst).has(cell1), "AC 4B §4.6-1：绑定后命中块立即选中（select_voxel additive 全链真通）")
	_feed("left", F_CURSOR, cell1_norm)   # 收笔（未划新格=单选替换，选区仍 {cell1}）
	spy.events.clear()

	# ================= 段 2（Y-A12①③）：右笔纯减选——未选块零事件 / 已选块减选 =================
	inst.call("clear_selection")
	# ①右笔扫未选块：选中数不变、零合成事件
	_feed("right", F_CURSOR, cell2_norm)
	_feed("right", F_TWO, cell2_norm)
	_feed("right", F_TWO, cell2_norm)   # 右笔双帧（命中未选块 cell2）
	check_eq(_ctrl_presses().size(), 0,
		"Y-A12①：右笔命中未选块 → 零 Ctrl 合成事件（来源判别；旧码反被 Ctrl+点击选中=红灯）")
	check(_sel(inst).is_empty(), "Y-A12①：右笔扫未选块 → 选中数不变（纯减选笔）")
	_feed("right", F_CURSOR, cell2_norm)   # 抬起
	_feed("right", F_CURSOR, blank_norm)
	_feed("right", F_TWO, blank_norm)
	_feed("right", F_TWO, blank_norm)   # 右笔空白：同源判别零事件
	check_eq(_ctrl_presses().size(), 0, "Y-A12①：右笔空白 → 零合成事件（键鼠 Ctrl 点空白原行为不经手势）")
	_feed("right", F_CURSOR, blank_norm)
	spy.events.clear()
	# ③右笔命中已选块 → Ctrl 按下+toggle 取消（既有减选语义回归）
	inst.call("select_voxel", cell1, false)
	check(_sel(inst).has(cell1), "③前置：键鼠选区 {cell1}")
	_feed("right", F_CURSOR, cell1_norm)
	_settle_cell("right", F_CURSOR, cell1_norm, cell1, found[0][1], inst, cam, cont)  # W2-1：喂到射线真达 cell1
	_feed("right", F_TWO, cell1_norm)
	_feed("right", F_TWO, cell1_norm)
	check_eq(_ctrl_presses().size(), 1, "Y-A12③：右笔命中已选块 → 合成 Ctrl+左键按下恰一次")
	check(_sel(inst).is_empty(), "Y-A12③：Ctrl+点击命中已选块 → toggle 取消（减选语义回归）")
	_feed("right", F_CURSOR, cell1_norm)
	check_eq(_btn_events(false).size(), 1, "Y-A12③：Ctrl 抬起配对（STROKE_DESELECT Q1 口径）")
	spy.events.clear()

	# ================= 段 3（Y-A12②）：键鼠 Ctrl+拖拽回归不变 =================
	# 真输入管线注入 Ctrl+左键按下@未选块 cell2（不经 Router 右笔判别——键鼠路径零改动）
	var ev_press := InputEventMouseButton.new()
	ev_press.button_index = MOUSE_BUTTON_LEFT
	ev_press.pressed = true
	ev_press.ctrl_pressed = true
	ev_press.position = found[1][1]
	ev_press.global_position = found[1][1]
	spy.push(ev_press)
	var ev_rel := InputEventMouseButton.new()
	ev_rel.button_index = MOUSE_BUTTON_LEFT
	ev_rel.pressed = false
	ev_rel.ctrl_pressed = true
	ev_rel.position = found[1][1]
	ev_rel.global_position = found[1][1]
	spy.push(ev_rel)
	check(_sel(inst).has(cell2),
		"Y-A12②：键鼠 Ctrl+点击未选块 → 选中（additive toggle 键鼠基准 :1466-1471 零改动）")
	inst.call("clear_selection")
	spy.events.clear()

	# ================= 段 4（Y-A12④）：ORBIT 态右二指统一忽略（对称化）=================
	# 批次 AC 4B（§4.6-2）：进 ORBIT 前须已绑定视口（段 1b 绑定主视图后保持）。
	# 批次 AD §4.3.1 等价改写：绑定视口内空白二指双帧仅进入准备态 ORBIT_PENDING，须再
	# 「按住二指拖动位移 > 15px」才正式切入 ORBIT（旧「空白二指双帧 → 即时 ORBIT」随有界
	# 拖拽门槛退役；旧值留痕：cursor+two+two+cursor→ORBIT）。vp_sz.x=视口像素宽，归一偏移
	# 20px/vp_sz.x 经 _content 还原为 20 content px > ORBIT_DRAG_THRESHOLD(15)。
	_feed("left", F_CURSOR, blank_norm)
	_feed("left", F_TWO, blank_norm)
	_feed("left", F_TWO, blank_norm)      # 空白二指双帧 → ORBIT_PENDING
	_feed("left", F_TWO, blank_norm + Vector2(20.0 / vp_sz.x, 0.0))   # 拖拽 >15px → ORBIT
	check_eq(String(router.get("_level_mode")), "ORBIT", "④前置：绑定视口内空白二指拖拽 >15px → ORBIT 态（§4.3.1 有界进入）")
	inst.call("select_voxel", cell1, false)   # ORBIT 态键鼠选区
	check(_sel(inst).has(cell1), "④前置：选区 {cell1}")
	# 批次 AD §4.3.1 回修留痕：本段须**左手持续在场**（二指保持=旋转态存活），旧写法改喂右手时
	# `left: null` 触发左手 teardown→two_up→§4.3.1 自然退出 ORBIT（旧 §4.6-2「收中指保持旋转」
	# 语义已由本批反置）。故右帧与左手 F_TWO 同帧共喂，保持 ORBIT 存活以验「右二指统一忽略」。
	var _hf: Callable = func(f: Array, tip: Vector2, s: String) -> Dictionary: return _hand(0.9, f, tip, s)
	router.feed({"left": _hf.call(F_TWO, blank_norm, "Left"), "right": _hf.call(F_CURSOR, cell1_norm, "Right"), "timestamp": 0.0})
	router.feed({"left": _hf.call(F_TWO, blank_norm, "Left"), "right": _hf.call(F_TWO, cell1_norm, "Right"), "timestamp": 0.0})
	router.feed({"left": _hf.call(F_TWO, blank_norm, "Left"), "right": _hf.call(F_TWO, cell1_norm, "Right"), "timestamp": 0.0})   # ORBIT 态右二指（命中已选块）
	check_eq(_ctrl_presses().size(), 0, "Y-A12④：ORBIT 态右二指 → 零合成事件（左右口径对称统一忽略）")
	check(_sel(inst).has(cell1), "Y-A12④：ORBIT 态右二指 → 选区原样（防误选对称化）")
	router.feed({"left": _hf.call(F_TWO, blank_norm, "Left"), "right": _hf.call(F_CURSOR, cell1_norm, "Right"), "timestamp": 0.0})
	spy.events.clear()

	# 收尾卫生：断开桥 feed 连接（防 freed 回调）
	if bridge != null and bridge.gesture_state_received.is_connected(router.feed):
		bridge.gesture_state_received.disconnect(router.feed)
	router.queue_free()
	spy.queue_free()
	await process_frame
	finish()
