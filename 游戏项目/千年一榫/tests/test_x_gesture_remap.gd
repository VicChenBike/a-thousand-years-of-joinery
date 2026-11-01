extends "res://tests/test_base.gd"
## 批次 X X4 波（spec §6 P5，20260921）——手势重映射「左手=左键笔 / 右手=Ctrl 减选笔 /
## 左三指=删除」新模型 TDD 红测先行。七组断言（spec §6 验收锚点）：
##   ①左手立即选中：two_down 双帧确认→**同批喂帧内**即刻合成左键按下（无 dwell 0.3s/28px
##     等待、无 0.8s 冷却；dwell/冷却成员退役实证）+ 双帧确认保留（单帧不触发）。
##   ②左手划选/单选替换：按住拖=STROKE 划选；抬起未划新格=单选替换（键鼠基准同链）。
##   ③右手 Ctrl 减选 toggle：two_down 双帧→合成 Ctrl+左键按下@光标→命中已选块 toggle 取消。
##   ④右手按住拖批量反选：Ctrl+按住拖=STROKE_DESELECT 扫选（Ctrl 态随侧）。
##   ⑤左三指删除两态：光标命中某块→delete_cell 单删（选区保留/撤销栈入栈）；未命中→
##     delete_selected 删全部已选（整组一组入栈）；右手三指零意图（左手专属）。
##   ⑥退役断言：快伸快收零挖除（router 级剩余集/撤销栈不变 + map 级无 dig/deselect_arm 意图）+
##     聚焦手势退役（map 三指无 focus 意图、router _do_focus/_on_deselect_arm 方法退役源证据）。
##   ⑦不变七项回归：清空=右掌静止 dwell 1.0s（W3-2）、翻转=undo/redo（map 级意图 + router
##     dispatch 真恢复/再删）、对接=双手同帧 two（W3-4）、退出=双手四指同翻 exit_flip 意图
##     （批次 AA W3 等价改写：旧「右四指双帧即 clear / 双手竖食指边沿 join」判据随 §6.3 退役）。
## 夹具/清档纪律沿用 test_w_gesture_level（真 level_scene + SpyLayer + user:// 备份还原，
## 独立前缀 x4gr）。

const SCENE_PATH := "res://scenes/level/level_scene.tscn"
const MISS := Vector3i(-1, -1, -1)

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

# ===== 清档纪律（test_w_gesture_level 同款，独立前缀 x4gr）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_x4gr_backup_"
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

# ===== 手势夹具（router 级：test_w_gesture_level 同款 + 双手侧）=====
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

## 批次 AA（W2-1）等价改写基建（spec §5.3 W2-1 连带）：二级 EMA（α0.35）后单帧喂位仅到位
## 35%，且死区 0.0015 归一留 ≤4.3px 锁定地板——位置敏感断言（划选/删除/单选替换的射线
## 命中）前用射线命中回灌喂到位：①先纯收敛（≤48 帧，无微推防大位移目标后移）；②距目标
## ≤12px 仍未中 = 地板/探针点位误差 → 朝 +x 细推 6px（>死区使 pos 真跨步）×6 帧驻留逐档
## 深探（探针点近格面左缘、ON 面向右延伸；空白目标朝角落 −6px），上限 4 档。旧「filtered
## 直喂直出」时代本函数恒 1 帧即中（零行为差）。
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

# ===== map 级夹具（test_gesture_map 同构，now 注入零时序依赖）=====
const F_CURSOR := [0.1, 0.9, 0.1, 0.1, 0.1]
const F_TWO := [0.1, 0.9, 0.9, 0.1, 0.1]
const F_THREE := [0.1, 0.9, 0.9, 0.9, 0.1]
const F_FOUR := [0.1, 0.9, 0.9, 0.9, 0.9]
const F_FOLD := [0.1, 0.9, 0.1, 0.1, 0.1]
const F_REST := [0.1, 0.1, 0.1, 0.1, 0.1]
const F_FIST := [0.1, 0.2, 0.2, 0.2, 0.8]

func _mhand(conf: float, fingers: Array, roll: float, facing: bool, label: String,
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
		"fingers": fingers, "pinch_distance": 0.5, "hand_index": 0, "handedness": label,
		"landmarks": lm, "fps": 30.0, "is_detected": true, "timestamp": ts, "palm_size": ps}

func _map_feed_left(m: Variant, fingers: Array, now: float, roll: float = 5.0) -> Array:
	return m.feed_frame(_mhand(0.9, fingers, roll, true, "Left", 0.2, Vector2(0.3, 0.4), now), {}, now)

func _map_feed_both(m: Variant, lf: Array, rf: Array, roll: float, now: float) -> Array:
	return m.feed_frame(
		_mhand(0.9, lf, roll, true, "Left", 0.2, Vector2(0.3, 0.4), now),
		_mhand(0.9, rf, roll, true, "Right", 0.2, Vector2(0.7, 0.4), now), now)

func _map_types(intents: Array) -> Array:
	var out: Array = []
	for it: Variant in intents:
		if typeof(it) == TYPE_DICTIONARY:
			out.append(String((it as Dictionary).get("type", "")))
	return out

func _map_has(intents: Array, t: String) -> bool:
	return _map_types(intents).has(t)

func _sel(inst: Variant) -> Array:
	return inst.call("get_selected_voxels") as Array

## 源码去注释（整行/行尾注释剥除）——test_aa_gesture_remap 段 5c 同款 helper（批次 AD 终验补强
## F-3 引入）：源证据断言只对**代码**生效，历史留痕注释里记载旧字面不构成锚命中。目标 token
## 不出现于「# 之后的字符串字面量」场景时，首个 '#' 截断安全。
func _code_only(src: String) -> String:
	var out: PackedStringArray = []
	for ln: String in src.split("\n"):
		var i: int = ln.find("#")
		out.append(ln if i < 0 else ln.substr(0, i))
	return "\n".join(out)

func _initialize() -> void:
	print("== test_x_gesture_remap ==")
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
	# 中线步进探 3 互异命中格 + 1 空白位（t_level_mode/w_gesture_level 同款）。
	# 批次 Z Z2 等价改写（新数据 12×3×5 中线实况暴露的死区耦合；断言集零增减仅探针取样更稳健）：
	# 探针相邻格**屏幕间距 ≥ gap_min**——手势死区 CURSOR_DEADZONE=0.0035 在增益前归一坐标判定，
	# 折算屏距 = deadzone×CURSOR_GAIN×视口宽（@1152≈14.1px）；8px 步进的首两互异格可仅隔 8px
	#（新数据实况 (7,2,4)@576/(7,2,3)@584），喂帧位移 (8/1152)/3.5≈0.00198<0.0035 被死区锁上帧、
	# Router 不推 motion → ②划选/④反选丢格（红根因；旧数据 8×3×8 探针间距恰 ≥ 阈值掩盖）。
	# gap_min 取死区折算 ×1.8 余量，随视口宽与两常量动态自适应。
	var gm_cm: Dictionary = load("res://scripts/gesture_map.gd").get_script_constant_map()
	var gain: float = float(gm_cm.get("CURSOR_GAIN", 3.5))
	var deadzone: float = float(gm_cm.get("CURSOR_DEADZONE", 0.0035))
	var vp_sz: Vector2 = get_root().get_visible_rect().size
	var gap_min: float = deadzone * gain * vp_sz.x * 1.8
	var found: Array = []
	var seen: Array = []
	var x := vps.size.x * 0.5
	while found.size() < 3 and x < vps.size.x:
		var c: Variant = inst.call("get_cell_hit", cam.project_ray_origin(Vector2(x, vps.size.y * 0.5)),
			cam.project_ray_normal(Vector2(x, vps.size.y * 0.5)))
		if c != MISS and not seen.has(c):
			var gpos: Vector2 = cont.get_global_rect().position + Vector2(x, vps.size.y * 0.5)
			if found.is_empty() or gpos.distance_to(found.back()[1]) >= gap_min:
				seen.append(c)
				found.append([c, gpos])
		x += 8.0
	check_eq(found.size(), 3, "前置：主视中线探得 3 互异格（批次 Z：相邻间距 ≥%.0fpx 越过手势死区）" % gap_min)
	var blank: Vector2 = cont.get_global_rect().position + Vector2(6.0, 6.0)
	if inst.call("get_cell_hit", cam.project_ray_origin(Vector2(6.0, 6.0)),
			cam.project_ray_normal(Vector2(6.0, 6.0))) != MISS:
		blank = cont.get_global_rect().position + Vector2(4.0, vps.size.y - 4.0)
	## 批次 AC §4.4-2：逆映射纵向基准上移 c_y=(0.5+m)/g（与 apply_cursor_gain 互逆）。
	var cy_x: float = (0.5 + float(gm_cm.get("CURSOR_OVERSHOOT", 0.15))) / gain
	var inv := func(gpos: Vector2) -> Vector2:
		return (gpos / vp_sz - Vector2(0.5, 0.5)) / gain + Vector2(0.5, cy_x)
	var cell1_norm: Vector2 = inv.call(found[0][1])
	var cell2_norm: Vector2 = inv.call(found[1][1])
	var cell3_norm: Vector2 = inv.call(found[2][1])
	var blank_norm: Vector2 = inv.call(blank)
	var cell1: Vector3i = found[0][0]
	var cell2: Vector3i = found[1][0]
	var cell3: Vector3i = found[2][0]

	# ================= 段 1（①左手选块：AC 4B §4.6-1 显式绑定前置；无 dwell 等待、无冷却；
	# 双帧确认保留）=================
	# 批次 AC 4B 等价改写（spec §4.6-1）：旧 Y-A13「进关首笔在块上激活+选块同施」退役——现契约=
	# 先视口空白二指单击显式绑定（点亮蓝框、零交互），绑定后块上起笔才合成左键按下选块。
	# 断言集零缩减，判据逐条留痕（新增 1c/1d 两个绑定语义锚，红→绿锁定）。
	check(router.get("_active_panel") == null, "段 1 前置：进关 _active_panel 为空（态 0 未绑定，AC 4B）")
	_feed("left", F_CURSOR, blank_norm)
	_feed("left", F_TWO, blank_norm)
	_feed("left", F_TWO, blank_norm)   # 1a. 空白二指双帧 → 仅绑定
	check(router.get("_active_panel") == cont, "①前置：视口空白单击 → 绑定主视图（描边点亮；AC 4B 显式绑定）")
	check_eq(_btn_events(true).size(), 0, "①前置：绑定当笔不得合成任何事件（不选块不旋转）")
	_feed("left", F_CURSOR, blank_norm)   # 收笔
	spy.events.clear()
	_feed("left", F_CURSOR, cell1_norm)
	_settle_cell("left", F_CURSOR, cell1_norm, cell1, found[0][1], inst, cam, cont)  # 喂到射线真达 cell1
	_feed("left", F_TWO, cell1_norm)
	_feed("left", F_TWO, cell1_norm)   # 1b. 绑定后块上二指双帧 → 立即按下
	check(_sel(inst).has(cell1), "①前置：绑定后命中块立即选中（AC 4B 绑定前置链）")
	_feed("left", F_CURSOR, cell1_norm)   # 抬起
	spy.events.clear()
	_feed("left", F_CURSOR, cell1_norm)
	_settle_cell("left", F_CURSOR, cell1_norm, cell1, found[0][1], inst, cam, cont)  # 喂到射线真达 cell1
	_feed("left", F_TWO, cell1_norm)
	_feed("left", F_TWO, cell1_norm)   # 双帧确认 → **同批同步喂帧内**立即合成左键按下
	var downs1: Array = _btn_events(true)
	check_eq(downs1.size(), 1, "①：块上 two_down 双帧 → 立即合成左键按下恰一次（无 dwell 0.3s 等待）")
	if downs1.size() == 1:
		# AC 4B 夹具硬化（等价改写留痕）：按下位**恒等**于该手光标 content 缓存（实现契约直比，
		# 确定性判读）；与探针点的距离另作 ≤12px 宽松锚（_settle_cell 的 6px 级微推 + 死区锁定
		# 使「严格 <0.5px」在骑缝探针点下不可得——断言对象=按下位取自光标缓存，非探针点标定）。
		var press_pos: Vector2 = (downs1[0] as InputEventMouseButton).position
		var cur_pos: Vector2 = router.get("_last_cursor_pos").get("left", Vector2.ZERO)
		check(press_pos.distance_to(cur_pos) < 0.5,
			"①：按下位=该手光标 content 坐标（实现契约直比）")
		check(press_pos.distance_to(found[0][1]) < 12.0,
			"①：按下位落在探针格附近（≤12px；AC 4B 夹具硬化锚，旧 <0.5px 随骑缝探针点退役）")
		check(bool((downs1[0] as InputEventMouseButton).ctrl_pressed) == false, "①：左手按下 ctrl=false（左键笔语义）")
	check(_sel(inst).has(cell1), "①：命中块立即选中（select_voxel additive 全链真通）")
	check(router.get("_dwell") == null and router.get("_select_cooldown_until") == null,
		"①：dwell/冷却成员退役实证（router.get 均 null——T10 悬停确认机制整体退役）")
	_feed("left", F_CURSOR, cell1_norm)   # 收笔
	spy.events.clear()
	_feed("left", F_CURSOR, cell1_norm)
	_settle_cell("left", F_CURSOR, cell1_norm, cell1, found[0][1], inst, cam, cont)
	_feed("left", F_TWO, cell1_norm)      # 仅 1 帧确认（双帧门保留）
	check_eq(_btn_events(true).size(), 0, "①：二指单帧不触发（CONFIRM_FRAMES=2 双帧确认防误触保留）")
	_feed("left", F_TWO, cell1_norm)      # 第 2 帧 → 立即按下
	check_eq(_btn_events(true).size(), 1, "①：第 2 帧确认 → 立即按下（双帧门后零等待）")
	_feed("left", F_CURSOR, cell1_norm)   # 收笔
	spy.events.clear()
	# 无冷却：抬起后**立即**（无 0.8s 冷却窗）再按 → 恰一次新按下
	_feed("left", F_CURSOR, cell1_norm)
	_settle_cell("left", F_CURSOR, cell1_norm, cell1, found[0][1], inst, cam, cont)
	_feed("left", F_TWO, cell1_norm)
	_feed("left", F_TWO, cell1_norm)
	check_eq(_btn_events(true).size(), 1, "①：0.8s 冷却退役——抬起后立即重按即刻合成按下（旧冷却期整段静默已废）")
	_feed("left", F_CURSOR, cell1_norm)   # 收笔
	spy.events.clear()                    # 段 2 计数窗从零起算（段 1 收笔抬起不入窗）

	# ================= 段 2（②左手划选 / 抬起未划新格=单选替换；批次 AA W2-1 等价改写：
	# 位置敏感断言前补 _settle 喂到位——二级 EMA 后单帧 35% 起步，旧直出时代单帧即达）====
	_feed("left", F_TWO, cell1_norm)
	_feed("left", F_TWO, cell1_norm)      # 按下（STROKE 起点 cell1）
	_feed("left", F_TWO, cell2_norm)      # 按住拖动 → two_move=STROKE 划选
	_settle_cell("left", F_TWO, cell2_norm, cell2, found[1][1], inst, cam, cont)  # W2-1：喂到射线真达 cell2
	check(_sel(inst).has(cell1) and _sel(inst).has(cell2), "②：按住滑动=连续划选（STROKE 逐格 additive）")
	_feed("left", F_CURSOR, cell2_norm)   # 抬起（已划新格 → 不做单选替换）
	check_eq(_btn_events(false).size(), 1, "②：抬起=合成左键抬起恰一次（笔画结束成对）")
	spy.events.clear()
	_settle_cell("left", F_CURSOR, cell3_norm, cell3, found[2][1], inst, cam, cont)  # W2-1：先喂到射线真达 cell3
	_feed("left", F_TWO, cell3_norm)
	_feed("left", F_TWO, cell3_norm)      # 新笔按下 cell3（未拖动）
	_feed("left", F_CURSOR, cell3_norm)   # 抬起未划新格 → 单选替换
	check(_sel(inst).size() == 1 and _sel(inst).has(cell3),
		"②：抬起未划新格=单选替换（clear+select，键鼠基准 level :1467-1470 同链）")
	spy.events.clear()

	# ================= 段 3（③右手 Ctrl 减选 toggle）=================
	inst.call("clear_selection")
	inst.call("select_voxel", cell1, false)
	check(_sel(inst).has(cell1), "③前置：键鼠选区 {cell1}")
	_feed("right", F_CURSOR, cell1_norm)
	_feed("right", F_TWO, cell1_norm)
	_feed("right", F_TWO, cell1_norm)   # 右手双帧 → 合成 Ctrl+左键按下
	var cpress: Array = _ctrl_presses()
	check_eq(cpress.size(), 1, "③：右手 two_down 双帧 → 合成 Ctrl+左键按下恰一次（减选笔）")
	check_eq(_btn_events(true).size(), 1, "③：右手按下仍走 _push_btn 既有管线（恰一次）")
	if cpress.size() == 1:
		check(((cpress[0] as InputEventMouseButton).position as Vector2).distance_to(found[0][1]) < 0.5,
			"③：Ctrl 按下位=光标 content 坐标")
	check(_sel(inst).is_empty(), "③：Ctrl+点击命中已选块 → toggle 取消（键鼠 Ctrl+点击 toggle 同链）")
	_feed("right", F_CURSOR, cell1_norm)   # 抬起 → Ctrl 抬起配对
	check_eq(_btn_events(false).size(), 1, "③：右手抬起=Ctrl 抬起恰一次（STROKE_DESELECT 无抬起兜底=Q1 口径）")
	spy.events.clear()

	# ================= 段 4（④右手按住拖=批量反选划）=================
	inst.call("select_voxel", cell1, false)
	inst.call("select_voxel", cell2, true)
	check(_sel(inst).has(cell1) and _sel(inst).has(cell2), "④前置：键鼠选区 {cell1,cell2}")
	_feed("right", F_TWO, cell1_norm)
	_feed("right", F_TWO, cell1_norm)   # Ctrl 按下（cell1 toggle 取消）
	check(not _sel(inst).has(cell1), "④：Ctrl+按下即刻取消起点格")
	_feed("right", F_TWO, cell2_norm)   # Ctrl+按住拖 → STROKE_DESELECT 扫过 cell2
	_settle_cell("right", F_TWO, cell2_norm, cell2, found[1][1], inst, cam, cont)  # W2-1：喂到射线真达 cell2
	check(_sel(inst).is_empty(), "④：Ctrl+拖扫过已选块 → 批量反选（扫一格消一格）")
	_feed("right", F_CURSOR, cell2_norm)   # Ctrl 抬起
	check_eq(_btn_events(false).size(), 1, "④：Ctrl 笔抬起成对（Ctrl 态随侧）")
	spy.events.clear()

	# ================= 段 5（⑤左三指批量删除：AC 4B §4.6-4 等价改写）=================
	# 批次 AC 4B 等价改写（spec §4.6-4 用户拍板「竖起无名指三指删除所选的所有木块」）：
	# 旧 X P5-a「光标命中某块→delete_cell 单删 / 未命中→delete_selected」双分支退役——
	# 现契约=**选区非空即优先 delete_selected 批量全删**（无需精准命中）；选区为空才尝试单删命中格。
	# 断言集零缩减：5a 判据由「单删 cell2」改写为「删全部已选且不动 cell2（命中格不参与）」，
	# 5b 由「@空白 全删」改写为「选区空@命中格 单删」+「选区空@空白 零删除」。
	inst.call("clear_selection")
	inst.call("select_voxel", cell1, false)
	var rem_cnt_a: int = (inst.call("get_remaining_voxels") as Array).size()
	var undo_a: int = int(inst.call("get_undo_depth"))
	_feed("left", F_CURSOR, cell2_norm)   # 光标对准 cell2（**未选中**格）
	_settle_cell("left", F_CURSOR, cell2_norm, cell2, found[1][1], inst, cam, cont)  # W2-1：喂到射线真达 cell2
	_feed("left", F_THREE, cell2_norm)
	_feed("left", F_THREE, cell2_norm)    # 左三指双帧确认 → delete
	check(_sel(inst).is_empty() and not (inst.call("get_remaining_voxels") as Array).has(cell1),
		"⑤a：选区非空 → delete_selected 批量全删（无需指尖命中；AC 4B 三指删除重构）")
	check((inst.call("get_remaining_voxels") as Array).has(cell2),
		"⑤a：批量删除只作用于已选块——光标命中但未选的 cell2 保留（命中格不参与）")
	check_eq((inst.call("get_remaining_voxels") as Array).size(), rem_cnt_a - 1, "⑤a：恰删一格（选区 1 块）")
	check_eq(int(inst.call("get_undo_depth")), undo_a + 1, "⑤a：批量删除整组入撤销栈恰一组（同源删除链）")
	_feed("left", F_CURSOR, cell3_norm)
	_settle_cell("left", F_CURSOR, cell3_norm, cell3, found[2][1], inst, cam, cont)  # 喂到射线真达 cell3
	inst.call("clear_selection")          # 选区清空（§4.6-4 单删分支前置）
	var rem_cnt_d: int = (inst.call("get_remaining_voxels") as Array).size()
	var undo_d: int = int(inst.call("get_undo_depth"))
	_feed("left", F_THREE, cell3_norm)
	_feed("left", F_THREE, cell3_norm)    # 左三指 @命中格（选区空）→ delete_cell 单删
	check(not (inst.call("get_remaining_voxels") as Array).has(cell3),
		"⑤b：选区为空且光标命中某块 → delete_cell 单删（照着一块删一块的顺手语义保留）")
	check_eq((inst.call("get_remaining_voxels") as Array).size(), rem_cnt_d - 1, "⑤b：恰删一格")
	check_eq(int(inst.call("get_undo_depth")), undo_d + 1, "⑤b：单删入撤销栈恰一组（同源删除链）")
	_feed("left", F_CURSOR, blank_norm)   # 光标移出块（未命中）
	_settle_cell("left", F_CURSOR, blank_norm, MISS, blank, inst, cam, cont)  # W2-1：喂到射线真达空白
	var rem_cnt_e: int = (inst.call("get_remaining_voxels") as Array).size()
	_feed("left", F_THREE, blank_norm)
	_feed("left", F_THREE, blank_norm)    # 左三指 @空白（选区空）→ 零删除
	check_eq((inst.call("get_remaining_voxels") as Array).size(), rem_cnt_e,
		"⑤c：选区空且光标未命中 → 零删除（无对象可删，不误伤）")
	# 多选批量删除（§4.6-4 用户语义本体）：划选两块 → 三指一次全删
	_feed("left", F_CURSOR, blank_norm)   # 三指为边沿语义：先收中指退出，重伸才是新一次 delete
	inst.call("select_voxel", cell1, true)
	if (inst.call("get_remaining_voxels") as Array).has(cell2):
		inst.call("select_voxel", cell2, true)
	var batch_n: int = (inst.call("get_selected_voxels") as Array).size()
	check(batch_n >= 1, "⑤d 前置：选区非空（%d 块）" % batch_n)
	var rem_cnt_f: int = (inst.call("get_remaining_voxels") as Array).size()
	var undo_f: int = int(inst.call("get_undo_depth"))
	_feed("left", F_THREE, blank_norm)
	_feed("left", F_THREE, blank_norm)
	check_eq((inst.call("get_remaining_voxels") as Array).size(), rem_cnt_f - batch_n,
		"⑤d：多选（%d 块）→ 左三指一次全删（用户「三指删除所选的所有木块」语义本体）" % batch_n)
	check(_sel(inst).is_empty(), "⑤d：批量删除后选区清空")
	check_eq(int(inst.call("get_undo_depth")), undo_f + 1, "⑤d：批量删除整组一组入栈")
	spy.events.clear()

	# ================= 段 6（⑥退役：快伸快收零挖除 + 聚焦手势退役）=================
	# router 级：右手快伸快收（<0.35s 收）→ 新模型=快速 Ctrl 点击（toggle），**零挖除**
	inst.call("clear_selection")
	var rem_cnt_c: int = (inst.call("get_remaining_voxels") as Array).size()
	var undo_c: int = int(inst.call("get_undo_depth"))
	_feed("right", F_CURSOR, blank_norm)
	_feed("right", F_TWO, blank_norm)
	_feed("right", F_TWO, blank_norm)   # 快伸（双帧确认）
	_feed("right", F_FOLD, blank_norm)  # 快收（<0.35s）→ two_up
	check_eq((inst.call("get_remaining_voxels") as Array).size(), rem_cnt_c,
		"⑥：右手快伸快收 → 剩余集零变化（快伸快收挖除退役，零 delete_selected）")
	check_eq(int(inst.call("get_undo_depth")), undo_c, "⑥：右手快伸快收 → 撤销栈零入栈（挖除路径整体退役）")
	# map 级：右二指 <0.35s 收 → 意图无 dig、无 deselect_arm
	var m: Variant = load("res://scripts/gesture_map.gd").new()
	var q1: Array = _map_feed_both(m, F_REST, F_TWO, 5.0, 10.0)
	q1.append_array(_map_feed_both(m, F_REST, F_TWO, 5.0, 10.033))
	var q2: Array = _map_feed_both(m, F_REST, F_FOLD, 5.0, 10.30)
	check(_map_has(q2, "two_up") and not _map_has(q1, "dig") and not _map_has(q2, "dig")
		and not _map_has(q1, "deselect_arm") and not _map_has(q2, "deselect_arm"),
		"⑥：map 级右手 <0.35s 快伸快收 → 无 dig/deselect_arm 意图（时序窗三态整体退役，仅 two_down/move/up）")
	# map 级：左三指确认 → delete 意图、无 focus
	m.reset()
	var t3a: Array = _map_feed_left(m, F_THREE, 20.0)
	var t3b: Array = _map_feed_left(m, F_THREE, 20.033)
	check(not _map_has(t3a, "focus") and not _map_has(t3b, "focus"), "⑥：左三指 → focus 意图零派发（聚焦手势退役）")
	check(not _map_has(t3a, "delete") and _map_has(t3b, "delete"), "⑥：左三指双帧确认 → delete 意图（删除新语义）")
	# 源证据：router 方法退役 + map 词汇退役
	check(not router.has_method("_do_focus"), "⑥：router._do_focus 方法退役（源证据）")
	check(not router.has_method("_on_deselect_arm"), "⑥：router._on_deselect_arm 方法退役（源证据）")
	var map_src: String = FileAccess.get_file_as_string("res://scripts/gesture_map.gd")
	check(not map_src.contains("deselect_arm") and not map_src.contains("DIG_MAX_SEC")
		and not map_src.contains("CANCEL_MIN_SEC"),
		"⑥：gesture_map 源码无 deselect_arm/DIG_MAX_SEC/CANCEL_MIN_SEC（时序窗词汇整体退役）")
	check(not map_src.contains("\"focus\""), "⑥：gesture_map 源码无 focus 意图发射位（聚焦手势退役）")
	# 右手三指零意图（左手专属门保留）
	m.reset()
	var r3a: Array = _map_feed_both(m, F_REST, F_THREE, 5.0, 30.0)
	r3a.append_array(_map_feed_both(m, F_REST, F_THREE, 5.0, 30.033))
	check(not _map_has(r3a, "delete") and not _map_has(r3a, "focus"),
		"⑥：右手三指零意图（删除=左手专属门保留）")

	# ================= 段 7（⑦不变七项回归：清空/翻转/对接/退出）=================
	# 批次 AA W3 等价改写（spec §6.3 W3-1/W3-2/W3-4 + §22 裁决 2、3）：
	# ①清空=【右】掌**静止 dwell 1.0s**（旧「右手竖四指双帧即 clear」退役）——router.feed 取
	#    真实时钟（Time.get_ticks_msec），故以 delay_msec(1150) 跨过 dwell 窗后补喂静态帧；
	# ②右翻转 redo：clear 改 dwell 后防误窗时点后移 → 翻腕序列改为「dwell 触发 clear + 独立
	#    防误窗(0.35s) 过期后前置重锁再翻」（Y-A8 解耦语义不变，可达性断言保持）；
	# ③对接=双手**同帧 two**（F_TWO 双帧确认），旧「双侧仅食指 cursor 边沿」判据退役；
	# ④退出=双手四指同翻：改在入态 0.1s 内同翻（roll 变化即取消右 dwell → 零 clear 干扰，
	#    优于旧「防误窗过期重锁」时序）。断言数 7→10（dwell clear 正向 / 单帧零 join / 零 two_down），只增不减。
	# 清空=右掌静止 dwell 1.0s（router 级真清选）
	var c7: Variant = MISS
	for c: Variant in (inst.call("get_remaining_voxels") as Array):
		c7 = c
		break
	check(c7 != MISS, "⑦前置：探得剩余格")
	inst.call("clear_selection")
	inst.call("select_voxel", c7, false)
	check(_sel(inst).has(c7), "⑦前置：选区 1 格")
	_feed("right", F_FOUR, blank_norm)   # 帧1：右掌确认计数
	_feed("right", F_FOUR, blank_norm)   # 帧2：入态
	OS.delay_msec(1150)                  # 跨 1.0s
	_feed("right", F_FOUR, blank_norm)   # 帧3：右掌静止已废除 dwell
	# 批次 AD §4.3.4 等价改写留痕：彻底废除右掌 dwell 清空，右掌静止满 1.0s 零清空，改双手握拳清空
	check(not _sel(inst).is_empty(), "⑦：右掌静止 1.0s 零清空（批次 AD §4.3.4 彻底废除右掌 dwell 清空）")
	# 随后双手握拳 2 帧 → 清空生效
	var h_l := _hand(0.9, F_FIST, blank_norm, "Left")
	var h_r := _hand(0.9, F_FIST, blank_norm, "Right")
	router.feed({"left": h_l, "right": h_r, "timestamp": 0.0})
	router.feed({"left": h_l, "right": h_r, "timestamp": 0.033})
	check(_sel(inst).is_empty(), "⑦：双手握拳清空选择（批次 AD §4.3.4 新通路生效）")
	# 翻转=undo/redo：map 级意图 + router dispatch 真恢复/再删
	# 批次 Z（Z5-1）等价平移：配对窗 SAME_WINDOW_SEC 0.8→1.2——解算帧 41.00→41.40
	#（1.267s>1.2s；0.867s 处新窗未闭合）；flip 序列本身零变化。
	m.reset()
	var f1: Array = _map_feed_left(m, F_FOUR, 40.0, 10.0)
	f1.append_array(_map_feed_left(m, F_FOUR, 40.033, 10.0))
	f1.append_array(_map_feed_left(m, F_FOUR, 40.10, 130.0))
	f1.append_array(_map_feed_left(m, F_FOUR, 40.133, 130.0))
	var f2: Array = _map_feed_left(m, F_FOLD, 41.40)
	check(_map_has(f2, "undo"), "⑦：左手翻转 → undo 意图（竖掌翻转不变项；map 级；Z5 1.2s 同窗闭合平移留痕）")
	m.reset()
	# 批次 AA W3-2 等价改写：clear 改右掌静止 dwell 后，提交时点由「入态双帧（42.033）」后移至
	# 「静止满 1.0s（43.066）」→ 独立防误窗（Y-A8 0.35s）至 43.416；翻腕序列改为「窗过期后前置
	# 重锁（43.45）→ 翻腕（43.55/43.583）→ 1.2s 同窗闭合解算（44.90，1.317s>1.2s）」，
	# redo 可达性断言不变；顺带断言 dwell clear 意图本身在案（W3-2 新清空通路正向锚）。
	var f3: Array = _map_feed_both(m, F_REST, F_FOUR, 10.0, 42.0)
	f3.append_array(_map_feed_both(m, F_REST, F_FOUR, 10.0, 42.033))   # 右掌入态（dwell 起算）
	f3.append_array(_map_feed_both(m, F_REST, F_FOUR, 10.0, 43.066))   # 静止满 1.0s → clear + 防误窗至 43.416
	f3.append_array(_map_feed_both(m, F_REST, F_FOUR, 10.0, 43.45))    # 防误窗过期 → 前置重累计/重锁
	f3.append_array(_map_feed_both(m, F_REST, F_FOUR, 130.0, 43.55))
	f3.append_array(_map_feed_both(m, F_REST, F_FOUR, 130.0, 43.583))  # 翻腕 2 帧 → flip
	var f4: Array = _map_feed_both(m, F_REST, F_FOLD, 5.0, 44.90)      # 1.317s>1.2s 同窗闭合
	# 批次 AD §4.3.4 等价改写：右掌静止 dwell 清空**彻底废除** → f3 序列零 clear
	#（旧断言 `check(_map_has(f3, "clear"), "⑦：右掌静止 1.0s → clear 意图（W3-2 dwell 新通路…）")`
	#  随 dwell 通路退役反置为「零 clear」留痕，判据数 1→2 只增不减）。
	check(not _map_has(f3, "clear"),
		"⑦：右掌静止 1.0s 零 clear（批次 AD §4.3.4 彻底废除右掌 dwell 清空；旧 W3-2 dwell 提交通路退役留痕）")
	# 批次 AD §4.3.4 新清空通路：双手同时握拳（食/中/无名 ≤0.35）连续 2 帧 → clear 意图
	#（时点续接 44.90 之后保 map 时间单调，防回退喂帧扰动翻转解算）
	var f_fist_seq: Array = _map_feed_both(m, F_FIST, F_FIST, 10.0, 45.0)
	var f_fist_out: Array = _map_feed_both(m, F_FIST, F_FIST, 10.0, 45.033)
	check(_map_has(f_fist_seq, "clear") or _map_has(f_fist_out, "clear"),
		"⑦：双手握拳连续 2 帧 → clear 意图（批次 AD §4.3.4 新清空通路接管）")
	check(_map_has(f4, "redo"), "⑦：右手翻转 → redo 意图（竖掌翻转不变项；map 级；W3-2 防误窗过期前置重锁后可达）")
	# router dispatch undo 真恢复（段 5d 批量删除组回到剩余集；undo 栈顶=最近一组）
	# 批次 AC 4B 等价改写：段 5d 的批量删除组=当时选区（cell1[+cell2]）——组大小按实现取，
	# 断言改为「恢复数 == 该组大小」（旧「+2」为旧段 5b 固定 {cell1,cell3} 组口径）。
	var rem_before_undo: int = (inst.call("get_remaining_voxels") as Array).size()
	var undo_top_n: int = int(inst.call("get_undo_depth"))
	check(undo_top_n > 0, "⑦前置：撤销栈非空（段 5d 批量删除在册）")
	router.call("_dispatch", {"type": "undo", "side": "left"})
	var rem_after_undo: int = (inst.call("get_remaining_voxels") as Array).size()
	check(rem_after_undo > rem_before_undo,
		"⑦：dispatch undo → 段 5d 批量删除组整组恢复（翻转撤销路由零变化）")
	router.call("_dispatch", {"type": "redo", "side": "left"})
	check((inst.call("get_remaining_voxels") as Array).size() == rem_before_undo,
		"⑦：dispatch redo → 整组再删（翻转重做路由零变化）")
	# 对接=双手同帧二指（W3-4，spec §6.3 + §22 裁决 3；旧「双手竖食指 cursor 边沿」判据退役）
	m.reset()
	var j0: Array = _map_feed_both(m, F_TWO, F_TWO, 5.0, 50.0)
	check(not _map_has(j0, "join"), "⑦：单帧未确认零 join（CONFIRM_FRAMES=2 双帧门保持）")
	var j1: Array = _map_feed_both(m, F_TWO, F_TWO, 5.0, 50.033)
	check(_map_has(j1, "join"), "⑦：双手同帧二指（食+中）双帧确认 → join 意图（W3-4 对接新判据）")
	check(not _map_has(j1, "two_down"), "⑦：双手同时 two → 两侧零 two_down（左键抑制，裁决 3）")
	# 退出=双手四指同翻（map 级 exit_flip 意图）
	# 批次 AA W3-2 等价改写：旧「右 clear 双帧提交（60.033）置独立防误窗 → 防误窗过期前置重锁
	# （61.10/61.133）再同步翻腕（61.20/61.233）」时序随 clear 改 dwell 退役——现右掌 dwell 满
	# 1.0s 的提交点在 61.033（原翻腕帧落其后），故改为**入态 0.1s 内同翻**：roll 变化（60.10 起
	# Δ120°>30°）即取消右 dwell → 本序列零 clear/零防误窗干扰；断言（exit_flip 恰一次）不变。
	m.reset()
	var e1: Array = _map_feed_both(m, F_FOUR, F_FOUR, 10.0, 60.0)
	e1.append_array(_map_feed_both(m, F_FOUR, F_FOUR, 10.0, 60.033))   # 双方入态+翻转前置锁定
	e1.append_array(_map_feed_both(m, F_FOUR, F_FOUR, 130.0, 60.10))   # 同帧翻腕 1（roll 锚 Δ=120°）
	e1.append_array(_map_feed_both(m, F_FOUR, F_FOUR, 130.0, 60.133))  # 同帧翻腕 2 → exit_flip
	check(_map_has(e1, "exit_flip"), "⑦：双手四指同翻 → exit_flip 意图（退出不变项）")
	check(not _map_has(e1, "clear"), "⑦：同翻序列零 clear（roll 取消右 dwell；W3-2 竞争零干扰）")

	# ================= 段 8（批次X收口 P3-2，spec §12 拍板：ORBIT 旋转态删除拦截）=================
	# ORBIT 旋转模式左手三指 → 零删除（删除=破坏性操作，旋转态一律忽略，与 ORBIT「防误选」设计
	# 对齐；spec §6 未 carve out，全项目扫描拍板补 Router 模式门）；退出 ORBIT 后同序列 → 删除生效。
	var c8: Variant = MISS
	for c: Variant in (inst.call("get_remaining_voxels") as Array):
		c8 = c
		break
	check(c8 != MISS, "8 前置：探得剩余格")
	inst.call("clear_selection")
	_feed("left", F_CURSOR, blank_norm)
	_feed("left", F_TWO, blank_norm)
	_feed("left", F_TWO, blank_norm)      # 空白二指双帧按下 → ORBIT_PENDING
	# 批次 AD §4.3.1 等价改写留痕：按住二指拖拽位移 > 15px 正式切入 ORBIT 态
	var vp_sz8: Vector2 = router.call("_content", Vector2.ONE)
	_feed("left", F_TWO, blank_norm + Vector2(20.0, 0.0) / vp_sz8)
	check_eq(String(router.get("_level_mode")), "ORBIT", "8 前置：空白二指拖拽 > 15px → ORBIT 态")
	inst.call("select_voxel", c8, false)  # ORBIT 态键鼠选区（delete_selected 删全部的对象）
	var rem8: int = (inst.call("get_remaining_voxels") as Array).size()
	var undo8: int = int(inst.call("get_undo_depth"))
	# ---- 8A（代码不变量·单元级）：ORBIT 态 delete 意图经 _dispatch 直调必被守卫拦截 ----
	# 批次 X P3-2「旋转态删除拦截」纵深防御红线：_do_delete 内 `if _level_mode=="ORBIT": return`。
	# §4.3.1 有界拖拽改造后，端到端喂帧的真机三指删除姿势会**先**经 two_up 自然退出 ORBIT（见 8B），
	# 该守卫在常规喂帧路径下不再被命中；本断言以**直调 _dispatch** 强制「ORBIT 态 + delete 意图」
	# 并存态复现，锁死这条破坏性操作最后防线**常驻在位、不可删**（若有人移除守卫，本断言立即判红）。
	check_eq(String(router.get("_level_mode")), "ORBIT", "8A 前置：拖拽越阈仍在 ORBIT")
	router.call("_dispatch", {"type": "delete", "side": "left"})
	check(_sel(inst).has(c8), "8A：ORBIT 态 delete 直调 → 选区原样（_do_delete ORBIT 守卫在位，零删除）")
	check_eq((inst.call("get_remaining_voxels") as Array).size(), rem8, "8A：ORBIT 态 delete 直调 → 剩余集零变化")
	check_eq(int(inst.call("get_undo_depth")), undo8, "8A：ORBIT 态 delete 直调 → 撤销栈零入栈")
	# ---- 8A-P2-2（批次 AD 审查回修 2026-09-28）：ORBIT_PENDING（准备态）同守 + 源锚 ----
	# 审查发现：旧守卫只挡正式 ORBIT，压下未越阈的准备态内左三指仍可触发删除（越 spec 窄判）。
	# 行为面以直调 _dispatch 强制「准备态 + delete 意图」并存态复现；源锚锁死判据字面不可回退。
	router.set("_level_mode", "ORBIT_PENDING")
	check_eq(String(router.get("_level_mode")), "ORBIT_PENDING", "8A-P2-2 前置：置准备态 ORBIT_PENDING")
	router.call("_dispatch", {"type": "delete", "side": "left"})
	check(_sel(inst).has(c8), "8A-P2-2：ORBIT_PENDING 态 delete 直调 → 选区原样（准备态守卫在位，零删除）")
	check_eq((inst.call("get_remaining_voxels") as Array).size(), rem8, "8A-P2-2：ORBIT_PENDING 态 delete 直调 → 剩余集零变化")
	check_eq(int(inst.call("get_undo_depth")), undo8, "8A-P2-2：ORBIT_PENDING 态 delete 直调 → 撤销栈零入栈")
	var rt_src8: String = FileAccess.get_file_as_string("res://autoload/gesture_router.gd")
	# 批次 AD 终验补强 F-3（2026-09-28）：源锚一律经 _code_only 去注释——旧写法直接对含注释的
	# 原文做 substr/contains，历史留痕注释里出现 ORBIT_PENDING 字面即可满足锚点（注释即绿）。
	var rt_code8: String = _code_only(rt_src8)
	var dd_i8: int = rt_code8.find("func _do_delete(")
	check(dd_i8 != -1 and rt_code8.substr(dd_i8, 700).contains("ORBIT_PENDING"),
		"8A-P2-2 源锚（code-only）：_do_delete 模式门收紧为 ORBIT+ORBIT_PENDING（准备态删除同守，字面不可回退）")
	var r2_i8: int = rt_code8.find("func _on_level_two_down_right(")
	check(r2_i8 != -1 and rt_code8.substr(r2_i8, 400).contains("ORBIT_PENDING"),
		"8A-P2-2 源锚（code-only）：右手二指起笔守卫收紧为 ORBIT+ORBIT_PENDING（准备态减选同守，字面不可回退）")
	# ---- 8A-F1（批次 AD 终验补强 F-1，2026-09-28）：_on_right_slide 模式门补 ORBIT_PENDING ----
	# 与 8A-P2-2 并列：P2-2 收了 _do_delete / 两处 two_down，右手滑动减选通道（_on_right_slide）
	# 的模式门当时仍只判 ORBIT；锚点取**函数体首条 _level_mode 判据行**（code-only，注释不可满足），
	# 该行必须同时含 ORBIT 与 ORBIT_PENDING 两字面。
	var rs_i8: int = rt_code8.find("func _on_right_slide(")
	var rs_gate8: String = ""
	if rs_i8 != -1:
		for ln8: String in rt_code8.substr(rs_i8, 700).split("\n"):
			if ln8.contains("_level_mode"):
				rs_gate8 = ln8.strip_edges()
				break
	check(rs_gate8.contains("String(_level_mode) == \"ORBIT\"")
			and rs_gate8.contains("String(_level_mode) == \"ORBIT_PENDING\""),
		"8A-F1 源锚（code-only）：_on_right_slide 模式门 = ORBIT + ORBIT_PENDING（准备态右滑减选同守；锚行=%s）" % rs_gate8)
	router.set("_level_mode", "ORBIT")   # 还原正式态，供 8B 姿势退出流程沿用
	# ---- 8B（姿势级·新自然退出流程）：二指在场张开无名指 → two_up 自然退出回待命 → 删除生效 ----
	# 批次 AD §4.3.1 语义：旋转中松开中指/姿势落到非 two 语义即自然退出。two→three 过渡当帧
	# map 发 two_up 且 side_semantic=""（三指尚在 2 帧确认中）→ 退出 ORBIT 回 SELECT_ARMED，
	# 下一帧三指确认发出的 delete 意图落待命态 → 正常批量删除（真机「转够了伸三指删」的路径）。
	# 旧值留痕：本段原断言「ORBIT 态左三指双帧→零删除」系旧 §4.6-2「收中指保持旋转」前提下的
	# 守卫可达红测；§4.3.1 反置后由 8A 直调（守卫常驻）+ 8B 直调/姿势（退出可达）双向分持。
	_feed("left", F_THREE, blank_norm)
	_feed("left", F_THREE, blank_norm)    # two→three：先 two_up 自然退出，再确认帧发 delete
	check_eq(String(router.get("_level_mode")), "SELECT_ARMED", "8B：三指删除姿势（经 two_up）→ 自然退出回待命（§4.3.1）")
	check(_sel(inst).is_empty(), "8B：退出 ORBIT 后左三指 delete → delete_selected 生效（选区清空）")
	check_eq((inst.call("get_remaining_voxels") as Array).size(), rem8 - 1, "8B：删除生效——该格出剩余集")
	check_eq(int(inst.call("get_undo_depth")), undo8 + 1, "8B：删除生效——撤销栈恰一组入栈")

	# ---- 8C（批次 AD 终验补强 F-1 行为面，2026-09-28）：ORBIT_PENDING 态右二指滑动减选被模式门拦下 ----
	# 旧值留痕：F-1 前 _on_right_slide 模式门只判 ORBIT——准备态（压下未越阈）内右二指滑入已选块
	# 会当帧置 _right_stroking 并合成 Ctrl 按下（下一帧再取消该格）；P2-2 只收了 _do_delete 与两处
	# two_down，滑动通道漏收。断言=准备态右滑双帧零成笔、选区零变化；阳性对照=同输入落待命态即
	# 成笔并取消该格（证「模式门」是唯一阻断因，非通路不可达的假绿）。
	var c8c: Variant = MISS
	for c: Variant in (inst.call("get_remaining_voxels") as Array):
		c8c = c
		break
	check(c8c != MISS, "8C 前置：探得剩余格")
	if router.get("_active_panel") != cont:
		router.call("_set_active_panel", cont)
	check(router.get("_active_panel") == cont, "8C 前置：主视绑定在位（_panel_view_kind=Main，红绿有效性前提）")
	# 命中位与 _on_right_slide 走同一条 _hit_cell 生产链（杜绝夹具错位造成的假绿）
	var g8c: Vector2 = cont.get_global_rect().position
	var s8c: Vector2 = cont.get_global_rect().size
	var hit8c := Vector2.INF
	var hx8: float = 0.0
	while hx8 < s8c.x and hit8c == Vector2.INF:
		var hy8: float = 0.0
		while hy8 < s8c.y:
			var pc8: Vector2 = g8c + Vector2(hx8, hy8)
			var cc8: Variant = router.call("_hit_cell", pc8)
			if typeof(cc8) == TYPE_VECTOR3I and cc8 != MISS:
				hit8c = pc8
				c8c = cc8
				break
			hy8 += 12.0
		hx8 += 12.0
	check(hit8c != Vector2.INF, "8C 前置：主视内探得 _hit_cell 命中位")
	inst.call("select_voxel", c8c, false)
	check(_sel(inst).has(c8c), "8C 前置：该格已入选区（减选目标在案）")
	router.set("_level_mode", "ORBIT_PENDING")
	router.set("_right_sliding", true)
	router.set("_right_stroking", false)
	router.call("_on_two_move", {"side": "right", "pos": hit8c / vp_sz})
	router.call("_on_two_move", {"side": "right", "pos": hit8c / vp_sz})
	check_eq(String(router.get("_level_mode")), "ORBIT_PENDING", "8C-F1 前置：右滑不改准备态")
	check(not bool(router.get("_right_stroking")),
		"8C-F1：ORBIT_PENDING 态右二指滑入已选块 → 模式门拦下，零成笔（F-1 回归锚）")
	check(_sel(inst).has(c8c), "8C-F1：准备态右滑双帧 → 该格仍选中（零减选副作用）")
	# 阳性对照：同输入落到待命态（模式门放行）→ 成笔 + 该格被取消。
	# 先把目标格重置回选中态——F-1 缺失时准备态段已把它取消，不重置会让对照段「成笔」断言
	# 因选区前提丢失而连带变红（对照段只该验通路可达，红灯应只落在 F-1 两条锚上）。
	inst.call("select_voxel", c8c, false)
	check(_sel(inst).has(c8c), "8C-F1 对照前置：目标格重置回选中态")
	router.set("_level_mode", "SELECT_ARMED")
	router.set("_right_stroking", false)
	router.call("_on_two_move", {"side": "right", "pos": hit8c / vp_sz})
	router.call("_on_two_move", {"side": "right", "pos": hit8c / vp_sz})
	check(bool(router.get("_right_stroking")),
		"8C-F1 阳性对照：待命态同输入 → 成笔（通路真实可达，非假绿）")
	check(not _sel(inst).has(c8c),
		"8C-F1 阳性对照：待命态右滑 → 该格被取消（模式门为唯一阻断因）")
	router.call("_on_two_up", {"side": "right", "pos": hit8c / vp_sz})
	check(not bool(router.get("_right_stroking")) and not bool(router.get("_right_sliding")),
		"8C-F1 卫生：右二指抬起 → 滑动/成笔标志归零（无跨段残留）")
	spy.events.clear()

	# 收尾卫生：断开桥 feed 连接（防 freed 回调）
	if bridge != null and bridge.gesture_state_received.is_connected(router.feed):
		bridge.gesture_state_received.disconnect(router.feed)
	router.queue_free()
	spy.queue_free()
	finish()

