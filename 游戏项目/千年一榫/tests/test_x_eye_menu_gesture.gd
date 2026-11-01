extends "res://tests/test_base.gd"
## 批次 X X2 波（spec §4 P3 + §5 P4，20260921）TDD 红测先行。
## 波内定档留痕：P3 双列阶梯断言并入本件（spec §1.3「test_x_camera_dock 并入既有件亦可」）。
## 段口径：
##   A（P3-a 选中态几何一致只换色 + P3-b 双列阶梯同现）：
##     A1 选中/未选 margin 逐值相等 + 行 size 逐值相等 + 仅色差（未选灰底=探针对齐
##        settings_panel TOGGLE_OFF 档，探针 log=p3a_gray_probe_run1.log）；
##     A2 hover 设备行 → res 列（旧式锚不变）+ fps 列同现阶梯锚（x=res 左缘−固定宽档、
##        y=设备行底缘）；fps 列固定宽档；
##     A3 res 行滑动只刷新 fps 列内容（同实例=零重弹、同位=不移位；现契约下集合恒同一——
##        Python 仅对当前分辨率探 fps_options 平铺数组，禁止逐档探测）；res 行 mouse_entered
##        不再连锁弹 fps（旧路径删除：fps 列收起后 res 行 hover 零重弹）；
##     A4 保活谓词两列并集复核 + _close_res 连带收 fps（关闭时机语义不变）。
##   B（P4 锐眼时长菜单手势可点）：
##     B1 键鼠回归：点击 EyeButton → 主视口自绘面板弹出（PopupMenu 退役）；
##     B2 手势链路：two_down 双帧确认 → armed → 抬起命中菜单项 → 时长生效 + 天赋值扣费；
##     B3 面板在场时 Esc 先消费于关面板（不落 level Esc=清选，选区保留）；
##     B4 点外关闭（外点被消费、选区不受扰）；
##     B5 右手菜单项点击（N7 按钮管线 per-side 天然支持）。
## 手势夹具/清档纪律沿用 test_w_gesture_level（真 level_scene + SpyLayer + user:// 备份还原，
## 独立前缀 x4em）。

const SCENE_PATH := "res://scenes/level/level_scene.tscn"
const MISS := Vector3i(-1, -1, -1)
const CS := preload("res://scripts/coord_space.gd")

# ===== 清档纪律（test_w_gesture_level 同款，独立前缀 x4em）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_x4em_backup_"
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

# ===== 手势夹具（test_w_gesture_level 同款 + 右手侧）=====
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

func _btn_presses() -> Array:
	var out: Array = []
	for ev: Variant in spy.events:
		var mb := ev as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			out.append(mb)
	return out

func _mouse_click(pos: Vector2) -> void:
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.position = pos
	d.global_position = pos
	get_root().push_input(d, true)
	var u := InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = pos
	u.global_position = pos
	get_root().push_input(u, true)

func _ctl_visible(v: Variant) -> bool:
	## PopupMenu 系 Window 不能 as Control（恒 null）——可见性判读统一走本 helper（红灯期安全）
	return v is Control and bool((v as Control).visible)

func _esc_key() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	get_root().push_input(ev, true)

func _initialize() -> void:
	print("== test_x_eye_menu_gesture ==")

	# ================= 段 A. P3 摄像头下拉（夹具=test_v 手法；零写档零出包）=================
	var bridge: Node = root.get_node("GestureBridge")
	bridge.set("_camera_enum", {"cameras": [{"id": 0, "name": "CamA"}, {"id": 1, "name": "CamB"}], "current_camera": 0})
	bridge.set("_camera_matrix", {"resolutions": [[1280, 720], [640, 480]], "fps_options": [30, 60]})
	bridge.set("_camera_errors", [])
	var menu: Control = (load("res://scenes/settings/camera_menu.gd") as GDScript).new()
	root.add_child(menu)
	await process_frame
	menu.call("open_menu")
	var rows: Array = menu.get("_rows")
	check_eq(rows.size(), 2, "段A 前置：设备列表 2 行")

	# ---- A1. P3-a：选中/未选 几何一致（margin 逐值+size 逐值）只换色 ----
	var row_sel: Button = rows[0]
	var row_unsel: Button = rows[1]
	await process_frame
	await process_frame   # 容器排序落位后再比几何（VBox deferred 排序，实证规律）
	var sb_sel: StyleBox = row_sel.get_theme_stylebox("normal")
	var sb_unsel: StyleBox = row_unsel.get_theme_stylebox("normal")
	check(sb_sel != null and sb_unsel != null, "P3-a 前置：两行常态 StyleBox 可解析")
	if sb_sel != null and sb_unsel != null:
		var m_eq: bool = true
		for s2: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			m_eq = m_eq and sb_sel.get_content_margin(s2) == sb_unsel.get_content_margin(s2)
		check(m_eq, "P3-a：选中/未选 content margin 逐值相等（「变细」根除；旧选中档 6/6/2/2 vs 主题档留痕）")
		check_eq(row_sel.size, row_unsel.size, "P3-a：同一容器内选中行/未选行 size 逐值相等")
	var bg_sel: Variant = (sb_sel as StyleBoxFlat).bg_color if sb_sel is StyleBoxFlat else null
	var bg_unsel: Variant = (sb_unsel as StyleBoxFlat).bg_color if sb_unsel is StyleBoxFlat else null
	check(bg_sel is Color and bg_unsel is Color and not (bg_sel as Color).is_equal_approx(bg_unsel as Color),
		"P3-a：选中/未选 仅色差（金棕 vs 灰；实际 %s / %s）" % [bg_sel, bg_unsel])
	# 批次 AB-3：浅档常量 DIM_BG_LIGHT/SEL_BG_LIGHT 随深浅主题机制删除退役——判据改深档单源。
	check(menu.get("DIM_BG_LIGHT") == null and menu.get("SEL_BG_LIGHT") == null,
		"AB-3 反向锁：DIM_BG_LIGHT/SEL_BG_LIGHT 浅档常量退役（无复辟）")
	var dim_gray: Variant = menu.get("DIM_BG_DARK")
	check(dim_gray is Color and (bg_unsel as Color).is_equal_approx(dim_gray as Color),
		"P3-a：未选=灰——灰底恒深档 (0.35,0.30,0.22,0.35)（AB-3 唯一真值；实际 %s）" % [bg_unsel])
	check((bg_sel as Color).is_equal_approx(menu.get("SEL_BG_DARK") as Color),
		"P3-a：选中=现 SEL_BG 金棕淡底保留（回归锚，深档唯一真值）")

	# ---- A2. P3-b：hover 设备行 → res+fps 双列同现阶梯锚 ----
	# 批次 Z（Z6-P2-11）等价改写：fps 锚旧「x=res 左缘−FPS_COL_TOTAL_W、y=设备行底缘」与
	# 锚行下方设备行恒相交（点设备名右半命中 fps 按钮写 gesture_camera_fps 而非切设备）→
	# 新「x=res 左缘−渲染宽−14 显式坐标、y=菜单底缘+VGAP（与全部设备行零相交的无碰撞带）」；
	# popup_anchor_px 单一漏斗不变（锚控件由锚行改菜单根）。
	menu.call("_open_res_sub", 0, rows[0])
	var res_sub: PopupPanel = menu.get("_res_sub")
	check(res_sub != null, "P3-b 前置：res 列弹出（旧式锚不变，见断言下）")
	check_eq(res_sub.position, Vector2i((rows[0] as Control).get_screen_transform().origin
		+ Vector2((rows[0] as Control).size.x, 0.0)),
		"P3-b：res 列锚=设备行右缘同 y（旧公式逐位不变）")
	var fps_v: Variant = menu.get("_fps_sub")
	check(fps_v != null, "P3-b：hover 设备行 → fps 列同时同现（红：旧路径仅 res 行 hover 连锁弹）")
	if fps_v != null:
		var fps_sub: PopupPanel = fps_v
		var w_v: Variant = menu.get("FPS_COL_RENDER_W")
		var m_v: Variant = menu.get("FPS_COL_MARGIN")
		var g_v: Variant = menu.get("FPS_COL_VGAP")
		if (w_v is float or w_v is int) and (m_v is float or m_v is int) and (g_v is float or g_v is int):
			var want_x: int = int(res_sub.position.x) - int(float(w_v) + float(m_v))
			var want_y: int = CS.popup_anchor_px(menu.get_screen_transform().origin,
				Vector2(0.0, menu.size.y + float(g_v))).y
			check_eq(fps_sub.position, Vector2i(want_x, want_y),
				"P3-b/Z6-P2-11：fps 列新锚 x=res 左缘−渲染宽−14、y=菜单底缘+VGAP（零压设备行；实际 %s）"
					% [fps_sub.position])
			# 批次 X 走查 NG① 锁等价改写（批次 Z Z6-P2-11）：fps 列实际渲染宽=Window 默认
			# 100×100（x7b 探针实证，内容 min 不驱动窗口尺寸）——锁①渲染宽档 ≥ 实际渲染宽
			# （res 列零叠压，紧贴其左边拍板）；锁②右安全边距 ≥14px（Z6-P2-11 拍板 6→14；
			# 旧 [4,8] 档随安全边距重定档放宽为 ≥14）。
			check(float(w_v) >= float(fps_sub.size.x),
				"P3-b NG① 锁：FPS_COL_RENDER_W %s ≥ fps 列实际渲染宽 %d（res 零叠压；实际锚 %s）"
					% [w_v, fps_sub.size.x, fps_sub.position])
			var ng1_gap: int = int(float(w_v) + float(m_v)) - fps_sub.size.x
			check(ng1_gap >= 14,
				"Z6-P2-11：fps 右安全边距 %dpx ≥14（渲染宽+安全边距定档口径）" % ng1_gap)
		else:
			check(false, "P3-b：FPS_COL_RENDER_W/MARGIN/VGAP 常量缺失（红）")
		var btn_w: Variant = menu.get("FPS_COL_BTN_W")
		var fps_box: Control = menu.get("_fps_box")
		var w_ok: bool = btn_w is float or btn_w is int
		for c: Node in fps_box.get_children():
			w_ok = w_ok and c is Button and (c as Button).custom_minimum_size.x == float(btn_w)
		check(w_ok and fps_box.get_child_count() > 0, "P3-b：fps 列行固定宽档（内容刷新不移位前提；实际 %s）" % [btn_w])

	# ---- A3. res 行滑动只刷新 fps 列（零重弹/不移位/契约同集合）+ 旧连锁弹路径删除 ----
	var res_btns: Array = []
	for c3: Node in (menu.get("_res_box") as Container).get_children():
		if c3 is Button:
			res_btns.append(c3)
	check_eq(res_btns.size(), 2, "A3 前置：res 列两行")
	var fps_before: Variant = menu.get("_fps_sub")
	var id_before: int = (fps_before as Object).get_instance_id() if fps_before != null else -1
	var pos_before: Variant = (fps_before as PopupPanel).position if fps_before != null else null
	(res_btns[1] as Button).mouse_entered.emit()   # 滑到另一 res 行
	await process_frame
	await process_frame
	var fps_after: Variant = menu.get("_fps_sub")
	check(fps_after != null and (fps_after as Object).get_instance_id() == id_before,
		"P3-b：res 行滑动 → fps 列同实例（零重弹；红：旧路径重建新 PopupPanel）")
	check(fps_after != null and pos_before != null and (fps_after as PopupPanel).position == pos_before,
		"P3-b：res 行滑动 → fps 列不移位（实际 %s）" % [(fps_after as PopupPanel).position if fps_after != null else null])
	if fps_after != null:
		var texts: Array = []
		for c4: Node in (menu.get("_fps_box") as Container).get_children():
			if c4 is Button:
				texts.append(String((c4 as Button).text))
		check(texts == ["30", "60"], "P3-b：刷新后 fps 列内容=当前契约平铺集（同一集合；实际 %s）" % [texts])
	menu.call("_close_fps")
	check(menu.get("_fps_sub") == null, "A3 前置：fps 列已收起")
	(res_btns[1] as Button).mouse_entered.emit()   # 旧路径在此应弹——删除后必须零反应
	await process_frame
	await process_frame
	check(menu.get("_fps_sub") == null,
		"P3-b：res 行 mouse_entered 不再连锁弹 fps（旧路径删除实证；红：旧实现此处重弹）")

	# ---- A4. 保活谓词两列并集复核 + 连带收起语义不变 ----
	# 红灯守卫：_open_fps_sub 新签名（cam_id, anchor_row）在旧实现（3 参）下 call 即 SCRIPT ERROR
	# 中断协程（无头挂死）——以 FPS_COL_BTN_W 常量哨兵判新旧实现，旧实现发 3 条红检不执行调用。
	if menu.get("FPS_COL_BTN_W") != null:
		menu.call("_open_fps_sub", 0, rows[0])
		await process_frame
		await process_frame
		var fps_box2: Control = menu.get("_fps_box")
		check(fps_box2 != null, "A4 前置：fps 列在场（重建路径）")
		if fps_box2 != null:
			var frect: Rect2 = fps_box2.get_global_rect()
			check(menu.call("_res_sub_contains_mouse", frect.position + frect.size * 0.5),
				"P3-b：保活谓词=两列并集——鼠标在 fps 列 → 保活（FV-1 P2-1 口径复核）")
		menu.call("_close_res")
		check(menu.get("_res_sub") == null and menu.get("_fps_sub") == null,
			"P3-b：_close_res 连带收 fps（关闭时机语义不变）")
	else:
		check(false, "A4 前置：fps 列在场（重建路径）——_open_fps_sub 新签名未就位（红）")
		check(false, "P3-b：保活谓词=两列并集——_open_fps_sub 新签名未就位（红）")
		check(false, "P3-b：_close_res 连带收 fps——_open_fps_sub 新签名未就位（红）")
	menu.free()

	# ================= 段 B. P4 锐眼时长菜单手势可点 =================
	_backup_user()
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(_disc_abs(p)):
			DirAccess.remove_absolute(_disc_abs(p))
	root.get_node("SaveManager").call("load_game")
	var game: Node = root.get_node("Game")
	bridge._set_state(1)
	router = load("res://autoload/gesture_router.gd").new()
	root.add_child(router)
	await process_frame
	bridge._set_state(1)
	router._setup()
	spy = SpyLayer.new()
	root.add_child(spy)
	await process_frame
	router.set_cursor_layer(spy)
	var inst: Node = (load(SCENE_PATH) as PackedScene).instantiate()
	check(inst != null, "P4 前置：关卡场景可实例化")
	inst.call("set_context", {"chapter": 1})
	root.add_child(inst)
	game._current_scene = inst
	await process_frame
	await process_frame
	game.goto_state(game.State.LEVEL)
	await process_frame
	var save: Node = root.get_node("SaveManager")
	save.call("add_talent", 1000)   # 扣费链路余量兜底（默认 500 基础上叠加）
	var eye_btn: Button = inst.get_node_or_null("TopBar/Buttons/EyeButton")
	check(eye_btn != null, "P4 前置：锐眼钮在位")

	# ---- B1. 键鼠回归：点击 EyeButton → 主视口自绘面板弹出 ----
	_mouse_click(eye_btn.get_global_rect().get_center())
	await process_frame
	await process_frame
	var menu_v: Variant = inst.get("_eye_menu")
	check(menu_v is PanelContainer, "P4：EyeButton 点击 → 主视口自绘面板（红：旧 PopupMenu 独立 Window 子视口）")
	check(_ctl_visible(menu_v), "P4：面板在场可见")
	var btns: Variant = menu_v.get("_buttons") if menu_v != null else null
	check(btns is Array and (btns as Array).size() == 6, "P4：面板 6 档时长（PopupMenu 6 项等价）")
	if btns is Array and (btns as Array).size() >= 6:
		check(String((btns[0] as Button).text).begins_with("0.5"), "P4：首项 0.5 秒档（旧文案逐字等价）")
		check(String((btns[5] as Button).text).begins_with("3.0"), "P4：末项 3.0 秒档（旧文案逐字等价）")
	var _gm_c: Dictionary = load("res://scripts/gesture_map.gd").get_script_constant_map()
	var gain: float = float(_gm_c.get("CURSOR_GAIN", 3.5))
	## 批次 AC §4.4-2：逆映射纵向基准上移 c_y=(0.5+m)/g（与 apply_cursor_gain 互逆）。
	var cy_e: float = (0.5 + float(_gm_c.get("CURSOR_OVERSHOOT", 0.15))) / gain
	var vp_sz: Vector2 = root.get_visible_rect().size
	var inv := func(gpos: Vector2) -> Vector2:
		return (gpos / vp_sz - Vector2(0.5, 0.5)) / gain + Vector2(0.5, cy_e)

	# ---- B2. 手势链路：two_down 双帧 → armed → 抬起命中第 3 档（1.5s/150）→ 时长生效+扣费 ----
	var t0: int = int(save.call("get_talent"))
	if btns is Array and (btns as Array).size() >= 3:
		var item: Button = btns[2]
		var item_c: Vector2 = item.get_global_rect().get_center()
		router.set("_level_mode", "SELECT_ARMED")
		router.set("_click_arm_dedup_at", -100.0)   # 测试注入：清 T5 互斥窗（B1 键鼠点击后 >0.1s 等价）
		var f_cursor: Array = [0.1, 0.9, 0.1, 0.1, 0.1]
		var f_two: Array = [0.1, 0.9, 0.9, 0.1, 0.1]
		_feed("left", f_cursor, inv.call(item_c))
		_feed("left", f_two, inv.call(item_c))
		_feed("left", f_two, inv.call(item_c))
		check(bool((router.get("_menu_click_armed") as Dictionary).get("left", false)),
			"P4：悬停菜单项 → armed 置位（红：PopupMenu 子视口 hovered 恒 null，探针 [3] 实锤）")
		check_eq(_btn_presses().size(), 1, "P4：armed 合成按下真入主视口恰一次")
		_feed("left", f_cursor, inv.call(item_c))   # 抬起 → 菜单项点击
		await process_frame
		await process_frame
		check(bool(inst.call("is_eye_active")), "P4：命中菜单项 → 时长生效（1.5s 档激活）")
		check_eq(int(save.call("get_talent")), t0 - 150, "P4：按档扣费 150（选中后先扣费路径不变）")
		check(not _ctl_visible(menu_v), "P4：点选即收（PopupMenu 点选即收同款语义）")
	else:
		check(false, "P4：菜单项按钮数组缺失（红）")
		check(false, "P4：手势链路断言未达（红）")
		check(false, "P4：扣费断言未达（红）")
		check(false, "P4：点选即收断言未达（红）")
	inst.call("_finish_eye")

	# ---- B3. 面板在场时 Esc 先消费于关面板（不落 Esc=清选）----
	var cam: Camera3D = inst.get_node_or_null("MainView/ViewportContainer/SubViewport/Camera3D")
	var vps: SubViewport = inst.get_node_or_null("MainView/ViewportContainer/SubViewport")
	var cell: Variant = MISS
	if cam != null and vps != null:
		var x := vps.size.x * 0.5
		while x < vps.size.x:
			var c5: Variant = inst.call("get_cell_hit", cam.project_ray_origin(Vector2(x, vps.size.y * 0.5)),
				cam.project_ray_normal(Vector2(x, vps.size.y * 0.5)))
			if c5 != MISS:
				cell = c5
				break
			x += 8.0
	check(cell != MISS, "B3 前置：探得 1 命中格")
	inst.call("select_voxel", cell, false)
	check((inst.call("get_selected_voxels") as Array).has(cell), "B3 前置：选区 1 格")
	inst.call("_open_eye_menu")
	await process_frame
	await process_frame
	var menu_b3: Variant = inst.get("_eye_menu")
	check(_ctl_visible(menu_b3), "B3 前置：面板在场")
	_esc_key()
	await process_frame
	await process_frame
	check(not _ctl_visible(menu_b3), "P4：Esc → 面板关闭")
	check((inst.call("get_selected_voxels") as Array).has(cell),
		"P4：Esc 先消费于关面板——选区保留（红：落 level Esc=清选则选区被清）")

	# ---- B4. 点外关闭（外点被消费、选区不受扰）----
	inst.call("_open_eye_menu")
	await process_frame
	await process_frame
	var menu_b4: Variant = inst.get("_eye_menu")
	var mrect: Rect2 = (menu_b4 as Control).get_global_rect() if menu_b4 is Control else Rect2()
	var outside := Vector2(80.0, vp_sz.y - 40.0)
	if mrect.has_point(outside):
		outside = Vector2(80.0, 8.0)
	_mouse_click(outside)
	await process_frame
	await process_frame
	check(not _ctl_visible(menu_b4), "P4：点面板外 → 面板关闭")
	check((inst.call("get_selected_voxels") as Array).has(cell),
		"P4：外点被面板消费——不穿透 3D 视图（选区不受扰；PopupMenu 点外语义同款）")

	# ---- B5. 右手菜单项点击（N7 按钮管线 per-side 天然支持）----
	inst.call("_open_eye_menu")
	await process_frame
	await process_frame
	var em5: Variant = inst.get("_eye_menu")
	var btns5: Variant = em5.get("_buttons") if em5 is Control else null
	var t1: int = int(save.call("get_talent"))
	if btns5 is Array and (btns5 as Array).size() >= 2:
		var item5: Button = btns5[1]
		var item5_c: Vector2 = item5.get_global_rect().get_center()
		router.set("_level_mode", "SELECT_ARMED")
		router.set("_click_arm_dedup_at", -100.0)
		var f_cursor5: Array = [0.1, 0.9, 0.1, 0.1, 0.1]
		var f_two5: Array = [0.1, 0.9, 0.9, 0.1, 0.1]
		_feed("right", f_cursor5, inv.call(item5_c))
		_feed("right", f_two5, inv.call(item5_c))
		_feed("right", f_two5, inv.call(item5_c))
		check(bool((router.get("_menu_click_armed") as Dictionary).get("right", false)),
			"P4：右手悬停菜单项 → armed 置位（per-side 天然支持）")
		_feed("right", f_cursor5, inv.call(item5_c))   # 抬起
		await process_frame
		await process_frame
		check(bool(inst.call("is_eye_active")), "P4：右手命中菜单项 → 1.0s 档生效")
		check_eq(int(save.call("get_talent")), t1 - 100, "P4：右手点选按档扣费 100")
	else:
		check(false, "P4：右手菜单项按钮缺失（红）")
		check(false, "P4：右手扣费断言未达（红）")
	inst.call("_finish_eye")
	inst.call("clear_selection")

	# 收尾卫生：断开桥 feed 连接（防 freed 回调）
	var bridge2: Node = root.get_node("GestureBridge")
	if bridge2 != null and bridge2.gesture_state_received.is_connected(router.feed):
		bridge2.gesture_state_received.disconnect(router.feed)
	router.queue_free()
	spy.queue_free()
	finish()
