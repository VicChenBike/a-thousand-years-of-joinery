extends "res://tests/test_base.gd"
## 窗口缩放坐标修复批（2026-09-18）：四项修复的判定用例。
## 修复1 悬停光斑 ui_material 族统一 content 逻辑系（main.gd/level_scene.gd）；
## 修复2 摄像头菜单/主弹窗锚定统一 popup_anchor_px 单一漏斗（content 口径锁死）；
## 修复3 DWM 圆角形态开关（QNSX_DWM_ROUND 环境变量 → rounded_frame 形态）；
## 修复4 cameras dict 条目适配（.get 加固/旧字符串兼容）+ LOADED 空列表占位行。
## 坐标语义依据：逻辑论证+生产反证+窗口探针实测（1348×758 渲染像素实测；探针为临时件
## 已清理，结论留痕于 scripts/coord_space.gd 头注与 AI工作记录/打包版实测修复批_探针证据
## 摘要_20260918.md）。
## 计数对账：段1=3、段2=2、段3=2、段4=3、段5=4、段6=4、段7=3、段8=10、段9=9、段10=9、
## 段11=2、段12=3、段13=4、段14=2 → 合计 60。

const PANEL_SCENE := "res://scenes/settings/settings_panel.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const CAMERA_MENU_GD := "res://scenes/settings/camera_menu.gd"
const LEVEL_GD := "res://scenes/level/level_scene.gd"
const FRAME_GD := "res://scenes/shared/rounded_frame.gd"
const CS := "res://scripts/coord_space.gd"
const ENV_KEY := "QNSX_DWM_ROUND"

func _cleanup() -> void:
	var p: String = ProjectSettings.globalize_path("user://save.json")
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)

func _init_panel() -> Control:
	var panel: Control = (load(PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await process_frame
	await process_frame
	return panel

# ===== 清档纪律（tools/README_走查清档规范.md，批次V回修②B 补齐，test_v_save_domain 同款）=====
# 起测前备份 user:// 真实档案（save.json/first_launch.flag 及可触及的 .tmp/.bak 四件组），
# 终测统一经 finish() 收口还原：先同步 free 测试挂载节点（level._exit_tree 兜底写档等
# 「退出写回」先落测试域磁盘，规范第 6 条），再逐件还原 + SaveManager load_game 重同步内存
# + 逐字节等价断言 + EVID 证据行。备份路径必须带全 user:// 前缀（相对路径在 FileAccess/
# DirAccess 间解析漂移 → 备份链静默失效，test_n10 先例）；每文件独立备份前缀防崩溃残留互踩。
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_r2b_fws_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _pre_save_text: String = ""   # 起测前真实 save.json 原文（还原等价自检基准）

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _disc_del(p: String) -> void:
	var a: String = _disc_abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _backup_user() -> void:
	# 规范第 1 条：任何删/写档操作之前备份真实档案（有档才备份；还原「有备份才回拷」幂等，
	# 起测前不存在的档案终测后仍不存在——测试自建残留一律清零）
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	# 防退出写回（规范第 6 条）：先同步 free 测试挂载的非 autoload 节点——level._exit_tree
	# 兜底写档（N9）若拖到进程退出树序，会在还原之后把测试态写回真实档案；提前 free 令
	# 兜底写档落测试域磁盘，紧随其后的逐件还原即将其覆盖。
	for c: Node in root.get_children():
		if not DISC_AUTOLOADS.has(String(c.name)):
			c.free()
	# 规范第 2 条：逐件还原 + load_game 重同步内存（防后续 save_game 把测试态写回真实档案）
	for p: String in DISC_WATCHED:
		_disc_del(p)
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(_disc_abs(bk))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()
	# 纪律自检：还原后 save.json 与起测前逐字节等价（起测前无档 ↔ 还原后无档）
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|fws|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_fix_window_scale ==")
	_backup_user()
	root.size = Vector2i(1152, 648)   # 实证坑：钉设计视口（防无头 expand 撑大）
	_cleanup()
	var save: Variant = get_root().get_node("SaveManager")
	save.load_game()
	var cs: GDScript = load(CS)

	# ---- 段 1. device_from_content 纯函数：s=0.9/1.0/1.16975 三档换算正确（3 checks）----
	for s: float in [0.9, 1.0, 1.16975]:
		var xf := Transform2D(Vector2(s, 0.0), Vector2(0.0, s), Vector2(37.0, 11.0))
		var got: Vector2 = cs.call("device_from_content", Vector2(200.0, 150.0), xf)
		check(got.is_equal_approx(Vector2(37.0 + 200.0 * s, 11.0 + 150.0 * s)),
			"段1：device_from_content s=%.5f → (37+200s, 11+150s) 逐分量（实际 %s）" % [s, got])

	# ---- 段 2. hover_pointer_content 口径选择（2 checks）----
	check_eq(cs.call("hover_pointer_content", Vector2(300.0, 200.0), Vector2(50.0, 60.0)), Vector2(300.0, 200.0),
		"段2：光标可见（非 null）→ 取光标 content 坐标（键鼠零感知不回落）")
	check_eq(cs.call("hover_pointer_content", null, Vector2(50.0, 60.0)), Vector2(50.0, 60.0),
		"段2：光标不可见（null）→ 回落真实鼠标 content 坐标")

	# ---- 段 3. popup_anchor_px 纯函数：content 锚 + 偏移，Vector2i 截断与旧式逐位一致（2 checks）----
	check_eq(cs.call("popup_anchor_px", Vector2(818.7, 229.2), Vector2(280.0, 0.0)), Vector2i(1098, 229),
		"段3：popup_anchor_px(origin+offset) 截断=Vector2i 旧式口径（1098,229）")
	check_eq(cs.call("popup_anchor_px", Vector2(807.0, 234.5), Vector2.ZERO), Vector2i(807, 234),
		"段3：零偏移（主弹窗锚=origin）恒等旧式 Vector2i(origin)")

	# ---- 段 4. set_hover content 回读：ui_light_linker 写入 u_mouse_screen 与传入 content 逐分量一致（3 checks）----
	var linker: Node = load("res://scripts/ui_light_linker.gd").new()
	add_child(linker)
	await process_frame
	var btn: Button = Button.new()
	add_child(btn)
	await process_frame
	await process_frame
	var mat: ShaderMaterial = btn.material as ShaderMaterial
	check(mat != null and mat.shader != null and String(mat.shader.resource_path).ends_with("ui_material.gdshader"),
		"段4 前置：ui_light_linker 已给 Button 挂 ui_material（node_added 动态挂载）")
	linker.call("set_hover", btn, Vector2(123.4, 567.8), 0.75)
	var got_px: Variant = mat.get_shader_parameter("u_mouse_screen")
	check(got_px is Vector2 and (got_px as Vector2).is_equal_approx(Vector2(123.4, 567.8)),
		"段4：set_hover(content) → u_mouse_screen 回读逐分量一致（content 口径锁死，实际 %s）" % [got_px])
	check(absf(float(mat.get_shader_parameter("u_hover")) - 0.75) < 0.0001, "段4：u_hover 回读一致")

	# ---- 段 5. main.gd content 链：_resolve_pointer_content 手势光标可见 → 光标 content 值（4 checks）----
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(main)
	await process_frame
	await process_frame
	check(main.has_method("_resolve_pointer_content"), "段5：main.gd _resolve_pointer_content helper 存在")
	var cursor_layer: Node = main.get("_cursor_layer")
	check(cursor_layer != null, "段5：光标层已挂载（数据源前提）")
	cursor_layer.call("show_cursor", "left", Vector2(300.0, 200.0))
	var resolved: Variant = main.call("_resolve_pointer_content")
	check(resolved is Vector2 and (resolved as Vector2).is_equal_approx(Vector2(300.0, 200.0)),
		"段5：光标可见 → content 值原样（不经 get_screen_transform 拉伸，实际 %s）" % [resolved])
	# 经 linker 落材质（消费端逐分量锁）
	var btn2: Button = Button.new()
	main.add_child(btn2)
	await process_frame
	await process_frame
	main.get("ui_light_linker").call("set_hover", btn2, main.call("_resolve_pointer_content"), 1.0)
	var m2: ShaderMaterial = btn2.material as ShaderMaterial
	check(m2 != null and (m2.get_shader_parameter("u_mouse_screen") as Vector2).is_equal_approx(Vector2(300.0, 200.0)),
		"段5：main 链 set_hover(u_mouse_screen) == 光标 content 值逐分量")
	main.queue_free()
	await process_frame

	# ---- 段 6. level_scene 见证者命中判定 content 口径：假 rect+假鼠标（4 checks）----
	var lvl_gd: GDScript = load(LEVEL_GD)
	var wit_rect := Rect2(100.0, 100.0, 200.0, 150.0)
	check(lvl_gd.call("bubble_hover_hit", wit_rect, Vector2(150.0, 120.0), true) == true,
		"段6：content 鼠标在 witness.get_global_rect() 内 + 气泡可见 → 命中")
	check(lvl_gd.call("bubble_hover_hit", wit_rect, Vector2(500.0, 500.0), true) == false,
		"段6：content 鼠标在 rect 外 → 未命中（负例）")
	check(lvl_gd.call("bubble_hover_hit", wit_rect, Vector2(150.0, 120.0), false) == false,
		"段6：气泡不可见 → 未命中（非悬停不出现）")
	var src_lvl: String = FileAccess.get_file_as_string(LEVEL_GD)
	check(src_lvl.contains("bubble_hover_hit(") and src_lvl.count("bubble_hover_hit(") >= 2,
		"段6：_tick_bubble_hover 实际调用纯函数（非死码结构锁）")

	# ---- 段 7. 锚定统一漏斗接线：camera_menu 双子列 + settings_panel 主弹窗（3 checks）----
	var bridge: Variant = get_root().get_node("GestureBridge")
	bridge._camera_enum = {"cameras": [{"id": 0, "name": "CamX"}, {"id": 1, "name": "CamY"}], "current_camera": 0}
	bridge._camera_matrix = {"resolutions": [[1280, 720], [640, 480]], "fps_options": [30]}
	bridge._camera_errors = []
	var panel: Control = await _init_panel()
	# 批次 U-D（c63260a）CameraMenuPopup 迁入 CameraMenuLayer——本文件段 7 节点路径等价替换
	#（旧 "CameraMenuPopup/CameraMenu" 系 U-D 迁层前旧路，迁层后 get_node 报 Node not found 且
	# SCRIPT ERROR 中断 _initialize 协程致无 finish() 无头挂死，uc_v2 涟漪回跑实锤）。
	var menu: Control = panel.get_node("CameraMenuLayer/CameraMenuPopup/CameraMenu")
	menu.call("open_menu")
	var row0: Control = menu.get("_rows")[0]
	row0.size = Vector2(280.0, 26.0)   # 批次 X P3-b：钉行几何（该夹具无头行宽退化 8px → res 左缘 16 −
		# 旧 114 档为负 → popup() 装配钳位回拉 x=0 的夹具伪影；生产布局 res 左缘 ≫114 无钳位。
		# 钉真实菜单行宽 280 保公式断言不受退化几何扰动，探针 seg7_fps_anchor_probe_temp 实证；
		# 114=Z6-P2-11 重定档（渲染宽 100+右安全边距 14，x7b 探针见 camera_menu.gd 常量注）
	menu.call("_open_res_sub", 0, row0)
	var res_sub: PopupPanel = menu.get("_res_sub")
	var want_res := Vector2i(row0.get_screen_transform().origin + Vector2(row0.size.x, 0.0))
	check_eq(res_sub.position, want_res,
		"段7：res 子列锚 = 锚控行 content origin+宽（popup_anchor_px 漏斗，content 口径恒等旧式）")
	# 批次 Z（Z6-P2-11）等价改写：fps 锚旧「x=res 左缘−FPS_COL_TOTAL_W、y=设备行底缘」——
	# 旧行为与锚行下方设备行恒相交（点设备名右半命中 fps 按钮写 gesture_camera_fps）。新锚
	# 「x=res 左缘−(渲染宽+14 显式坐标)、y=菜单底缘+VGAP」与全部设备行零相交；popup_anchor_px
	# 单一漏斗不变（锚控件改菜单根）。同帧断言（pin 后无 await），菜单尺寸两时点同值恒等。
	var fps_sub: PopupPanel = menu.get("_fps_sub")
	check(fps_sub != null, "段7 前置：_open_res_sub → fps 列同时同现（P3-b 双列）")
	if fps_sub != null:
		var menu_root: Control = menu
		var want_fx: int = int(res_sub.position.x) \
			- int(float(menu.get("FPS_COL_RENDER_W")) + float(menu.get("FPS_COL_MARGIN")))
		var want_fy: int = (load(CS) as GDScript).popup_anchor_px(menu_root.get_screen_transform().origin,
			Vector2(0.0, menu_root.size.y + float(menu.get("FPS_COL_VGAP")))).y
		check_eq(fps_sub.position, Vector2i(want_fx, want_fy),
			"段7：fps 子列新锚同漏斗（x=res 左缘−渲染宽−14、y=菜单底缘+VGAP；实际 %s）" % [fps_sub.position])
		check(res_sub.position.x - (fps_sub.position.x
				+ int(float(menu.get("FPS_COL_RENDER_W")))) >= int(float(menu.get("FPS_COL_MARGIN"))),
			"段7/Z6-P2-11：fps 右缘→res 列左缘安全边距 ≥14px（右安全边距拍板）")
	var arrow: Control = panel.get_node("Panel/VBox/OptionsBox/CameraRow/ArrowBtn")
	panel.call("_on_arrow_pressed")
	check_eq((panel.get_node("CameraMenuLayer/CameraMenuPopup") as PopupPanel).position,
		Vector2i(arrow.get_screen_transform().origin),
		"段7：settings_panel:159 主弹窗锚=箭头钮 content origin（审计通过收口漏斗）")
	panel.queue_free()
	await process_frame

	# ---- 段 8. DWM 圆角形态开关（9 checks）----
	var cs_frame: GDScript = load(FRAME_GD)
	# 8a 备案形态（无环境变量、未置标志）
	var f1: Node = cs_frame.new()
	add_child(f1)
	await process_frame
	check(bool(f1.get("dwm_round")) == false and bool(f1.get("_drawer").get("dwm")) == false,
		"段8a：无 QNSX_DWM_ROUND → 备案形态（dwm_round/drawer.dwm 均 false）")
	check(bool(f1.call("_uses_fallback_corners")) == true, "段8a：备案形态（无信号；v2 零填充后两形态差异=环半径 0 直角贴边 vs 8 圆角——旧「画四角扇区」概念废止）")
	# 批次 U 等价替换（U9-1）：备案描边色=主题深/浅档 → FRAME_STROKE_COLOR 恒灰单源（旧口径留痕）；
	# 常量取值经 Variant 哨兵（红灯要 FAIL 不要 null 调方法中止——批次 T 实证规律⑦族）
	var col0: Color = f1.get("_drawer").get("col")
	var want_col: Variant = (cs_frame as GDScript).get("FRAME_STROKE_COLOR")
	check(want_col is Color and col0.is_equal_approx(want_col),
		"段8a：备案描边色=FRAME_STROKE_COLOR 恒灰 70%% 透明（旧主题双档废止，实际 %s）" % [col0])
	f1.queue_free()
	await process_frame
	# 8b DWM 形态（形态开关内聚 rounded_frame；环境变量→标志的接线由 main.gd 负责，8d 实测）
	var f2: Node = cs_frame.new()
	add_child(f2)
	await process_frame
	f2.call("set_dwm_round", true)
	check(bool(f2.get("dwm_round")) == true and bool(f2.get("_drawer").get("dwm")) == true,
		"段8b：set_dwm_round(true) → DWM 形态（标志贯通 drawer）")
	check(bool(f2.call("_uses_fallback_corners")) == false, "段8b：DWM 形态（圆角信号；v2 环半径 8 对齐 Win11 原生弧——旧「停画四角三角」概念废止）")
	# 批次 U 等价替换（U9-1）：DWM 50% 不透明灰双源废止 → 单源恒灰 70% 透明（旧值 (0.55,0.55,0.55,0.50) 留痕）
	var dwm_col: Variant = f2.get("_drawer").get("col")
	check(dwm_col is Color and (dwm_col as Color).is_equal_approx(Color(0.55, 0.55, 0.55, 0.30)),
		"段8b：DWM 描边色=FRAME_STROKE_COLOR 恒灰 70%% 透明 (0.55,0.55,0.55,0.30)（旧 50%% 不透明灰废止，实际 %s）" % [dwm_col])
	# 批次 AB-3：_on_theme 回调随 theme_changed 退役——反向锁：回调无复辟 + 描边色仍单源恒灰。
	check(not f2.has_method("_on_theme"),
		"AB-3 反向锁：rounded_frame._on_theme 随深浅主题机制删除退役（无复辟）")
	check((f2.get("_drawer").get("col") as Color).is_equal_approx(Color(0.55, 0.55, 0.55, 0.30)),
		"段8b：描边色单源恒灰保持（批次 U U9-1 等价替换；AB-3 无主题翻转通道）")
	# 复位可重入 → 回备案形态
	f2.call("set_dwm_round", false)
	check(bool(f2.call("_uses_fallback_corners")) == true, "段8b：set_dwm_round(false) → 回备案形态（可重入）")
	f2.queue_free()
	await process_frame
	# 8d main.gd 环境读取+标志传递
	OS.set_environment(ENV_KEY, "1")
	var main2: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(main2)
	await process_frame
	await process_frame
	check(bool(main2.get_node("RoundedFrame").get("dwm_round")) == true,
		"段8d：main.gd 读 QNSX_DWM_ROUND=1 → RoundedFrame.dwm_round=true（只透传，判断内聚 rounded_frame）")
	main2.queue_free()
	await process_frame
	OS.unset_environment(ENV_KEY)
	var main3: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(main3)
	await process_frame
	await process_frame
	check(bool(main3.get_node("RoundedFrame").get("dwm_round")) == false,
		"段8d：无环境变量（直启 EXE 降级）→ 备案形态 false")
	main3.queue_free()
	await process_frame

	# ---- 段 9. cameras dict 契约：normalize/透传/渲染/meta id（9 checks）----
	var cm_gd: GDScript = load(CAMERA_MENU_GD)
	var e1: Dictionary = cm_gd.call("normalize_cam_entry", {"id": 2, "name": "USB Cam"})
	check(int(e1.get("id", -99)) == 2 and String(e1.get("name", "")) == "USB Cam",
		"段9：dict 条目 {id,name} → 原样出（新契约）")
	var e2: Dictionary = cm_gd.call("normalize_cam_entry", {"name": "NoID"})
	check(int(e2.get("id", -99)) == -1 and String(e2.get("name", "")) == "NoID",
		"段9：dict 缺 id → id=-1 防御（.get 硬纪律，不中止）")
	var e3: Dictionary = cm_gd.call("normalize_cam_entry", {"id": 3})
	check(int(e3.get("id", -99)) == 3 and String(e3.get("name", "")) == "",
		"段9：dict 缺 name → name=\"\" 防御")
	var e4: Dictionary = cm_gd.call("normalize_cam_entry", "3")
	check(int(e4.get("id", -99)) == 3 and String(e4.get("name", "")) == "3",
		"段9：旧字符串条目 \"3\" → id=3/name=\"3\"（向下兼容不崩）")
	var e5: Dictionary = cm_gd.call("normalize_cam_entry", 4)
	check(int(e5.get("id", -99)) == 4 and String(e5.get("name", "")) == "4",
		"段9：int 条目 → id=4/name=\"4\"（兼容容错）")
	# bridge _handle_meta 原样透传（只读确认：dict 条目透传即兼容）
	bridge.simulate_packet("{\"type\":\"init\",\"cameras\":[{\"id\":0,\"name\":\"A\"}],\"current_camera\":0}")
	var enum_cache: Dictionary = bridge.get_camera_enum()
	var entries: Array = enum_cache.get("cameras", [])
	check(entries.size() == 1 and typeof(entries[0]) == TYPE_DICTIONARY and int((entries[0] as Dictionary).get("id", -99)) == 0,
		"段9：bridge _handle_meta dict 条目原样透传（无需改，只读确认锁）")
	# 渲染 + cam_id meta（SWITCH_CAMERA:<id> 与 meta 同源变量）
	var panel2: Control = await _init_panel()
	var menu2: Control = panel2.get_node("CameraMenuLayer/CameraMenuPopup/CameraMenu")
	menu2.call("_apply_enum", [{"id": 0, "name": "CamX"}, {"id": 1, "name": "CamY"}], 0)
	var rows: Array = menu2.get("_rows")
	check_eq(rows.size(), 2, "段9：dict 列表 → 2 行")
	check_eq(String((rows[0] as Button).text), "[0] CamX", "段9：渲染 name（[0] CamX）")
	check_eq(int((rows[1] as Button).get_meta("cam_id", -99)), 1, "段9：行 meta cam_id=点击下发 SWITCH_CAMERA:<id> 同源 id")
	panel2.queue_free()
	await process_frame

	# ---- 段 10. LOADED 空列表占位行 + 刷新不被阻塞（9 checks）----
	var panel3: Control = await _init_panel()
	var menu3: Control = panel3.get_node("CameraMenuLayer/CameraMenuPopup/CameraMenu")
	menu3.call("_apply_enum", [], 0)
	check_eq(int(menu3.get("state")), 2, "段10：LOADED 且 cameras 空 → 状态保持 LOADED（区别于 8s 超时 EMPTY=0）")
	var box3: Control = menu3.get("_root_box")
	check(box3 != null and box3.get_child_count() == 1, "段10：占位单行")
	if box3 != null and box3.get_child_count() >= 1:
		check_eq(String((box3.get_child(0) as Label).text), "未检测到摄像头", "段10：占位文案逐字（与 EMPTY 同源）")
	check_eq((menu3.get("_rows") as Array).size(), 0, "段10：空列表零设备行")
	menu3.call("_apply_enum", [{"id": 5, "name": "Late"}], 0)
	check_eq(int(menu3.get("state")), 2, "段10：占位后 init 到达 → 仍 LOADED 可刷新")
	check_eq((menu3.get("_rows") as Array).size(), 1, "段10：刷新重建设备行（占位不阻塞后续列表）")
	check_eq(String(((menu3.get("_rows") as Array)[0] as Button).text), "[5] Late", "段10：刷新行渲染 dict 条目")
	# open_menu 缓存路径空列表
	bridge._camera_enum = {"cameras": [], "current_camera": 0}
	menu3.call("open_menu")
	check_eq(int(menu3.get("state")), 2, "段10：open_menu 缓存空列表 → LOADED 占位（不进 LOADING 不等超时）")
	check_eq(String((menu3.get("_root_box").get_child(0) as Label).text), "未检测到摄像头",
		"段10：open_menu 缓存空列表 → 占位文案逐字")
	panel3.queue_free()
	await process_frame

	# ---- 段 11. 旧式锚定零回归（无头 identity 下 res/fps/主弹窗行为与旧式逐位一致，2 checks）----
	bridge._camera_enum = {"cameras": [{"id": 0, "name": "CamX"}, {"id": 1, "name": "CamY"}], "current_camera": 0}
	var panel4: Control = await _init_panel()
	var menu4: Control = panel4.get_node("CameraMenuLayer/CameraMenuPopup/CameraMenu")
	menu4.call("open_menu")
	var r0: Control = menu4.get("_rows")[0]
	menu4.call("_open_res_sub", 0, r0)
	var rs: PopupPanel = menu4.get("_res_sub")
	check(rs != null and rs.position == Vector2i(r0.get_screen_transform().origin + Vector2(r0.size.x, 0.0)),
		"段11：res 子列落点与旧式公式逐位一致（headless identity 下零视觉回归）")
	check(menu4.get("_res_box") != null, "段11：_res_box 内容容器引保持（谓词收起数据源不回归）")
	panel4.queue_free()
	await process_frame

	# ---- 段 12. rect_device_from_content 纯函数：s=0.9/1.0/1.16975 三档逐分量（3 checks）----
	for s2: float in [0.9, 1.0, 1.16975]:
		var xf12 := Transform2D(Vector2(s2, 0.0), Vector2(0.0, s2), Vector2(31.0, 7.0))
		var r12: Rect2 = cs.call("rect_device_from_content", Rect2(Vector2(100.0, 50.0), Vector2(280.0, 40.0)), xf12)
		var want12 := Rect2(Vector2(31.0 + 100.0 * s2, 7.0 + 50.0 * s2), Vector2(280.0 * s2, 40.0 * s2))
		check(r12.position.is_equal_approx(want12.position) and r12.size.is_equal_approx(want12.size),
			"段12：rect_device_from_content s=%.5f → (origin+pos×s, size×s) 逐分量（实际 %s）" % [s2, r12])

	# ---- 段 13. window_manager._push 产出设备系：u_rects/u_ellipses == content×视口拉伸（4 checks）----
	# 无头下视口拉伸 scale≠1（虚拟窗口 64×64/visible 1152²）→ 与旧 content 原值可区分，断言有甄别力。
	var wm: GDScript = load("res://scripts/window_manager.gd")
	var tgt: Control = Control.new()
	tgt.position = Vector2(200.0, 150.0)
	tgt.size = Vector2(120.0, 40.0)
	add_child(tgt)
	await process_frame
	var xf13: Transform2D = tgt.get_viewport().get_screen_transform()
	var want_rect13: Rect2 = cs.call("rect_device_from_content", Rect2(Vector2(200.0, 150.0), Vector2(120.0, 40.0)), xf13)
	var gt13: Dictionary = wm.call("glow_targets_for", tgt)
	var r13: Rect2 = (gt13["rects"] as Array)[0]
	check(r13.position.is_equal_approx(want_rect13.position) and r13.size.is_equal_approx(want_rect13.size),
		"段13：u_rects[0]==content×视口拉伸（设备系，实际 %s 期望 %s）" % [r13, want_rect13])
	check_eq(int((gt13["mask_types"] as Array)[0]), 0, "段13：矩形档 mask_type=0（回归锁）")
	var ell_ct: Control = Control.new()
	ell_ct.position = Vector2.ZERO
	ell_ct.size = Vector2(880.0, 600.0)
	ell_ct.set_meta("glow_mask", "ellipse")
	ell_ct.set_meta("ellipse_params", Vector2(440.0, 324.0))
	add_child(ell_ct)
	await process_frame
	var xf13b: Transform2D = ell_ct.get_viewport().get_screen_transform()
	var want_r13b: Rect2 = cs.call("rect_device_from_content", Rect2(Vector2.ZERO, Vector2(880.0, 600.0)), xf13b)
	var want_e13: Vector4 = Vector4(want_r13b.position.x, want_r13b.position.y + want_r13b.size.y * 0.5,
		440.0 * xf13b.get_scale().x, want_r13b.size.y * 0.5)
	var gt13b: Dictionary = wm.call("glow_targets_for", ell_ct)
	var e13: Vector4 = (gt13b["ellipses"] as Array)[0]
	check(e13.is_equal_approx(want_e13),
		"段13：容器椭圆==(设备左缘,设备中心y,rx×sx,设备ry)（设备系左贴弧，实际 %s 期望 %s）" % [e13, want_e13])
	check_eq(int((gt13b["mask_types"] as Array)[0]), 1, "段13：容器档 mask_type=1（回归锁）")
	tgt.queue_free()
	ell_ct.queue_free()
	await process_frame

	# ---- 段 14. hover_glow 第三处供给点：level 气泡光晕 u_rects 设备系（2 checks）----
	get_root().get_node("SaveManager").load_game()
	var container2: Control = Control.new()
	container2.size = Vector2(1152.0, 648.0)
	add_child(container2)
	var lvl2: Control = (load("res://scenes/level/level_scene.tscn") as PackedScene).instantiate()
	lvl2.call("set_context", {"chapter": 1, "replay": false})
	container2.add_child(lvl2)
	await process_frame
	await process_frame
	lvl2.set_process(false)
	lvl2.call("_ensure_bubble_glow_layer")
	lvl2.call("_bubble_hover_probe", Vector2(150.0, 120.0), 0.2)
	var bub2: Label = lvl2.get_node("WitnessBubble")
	var br2: Rect2 = bub2.get_global_rect()
	var xf14: Transform2D = lvl2.get_viewport().get_screen_transform()
	var want_rect14: Rect2 = cs.call("rect_device_from_content", br2, xf14)
	var gnode2: ColorRect = lvl2.get_node_or_null("WitnessBubbleGlow")
	check(gnode2 != null and (gnode2.material as ShaderMaterial) != null, "段14 前置：气泡光晕覆盖层+材质就绪")
	if gnode2 != null:
		var v14: Variant = ((gnode2.material as ShaderMaterial).get_shader_parameter("u_rects") as Array)[0]
		var v4: Vector4 = v14 as Vector4
		check(v4 != null and absf(v4.x - want_rect14.position.x) < 0.01 and absf(v4.y - want_rect14.position.y) < 0.01
			and absf(v4.z - want_rect14.size.x) < 0.01 and absf(v4.w - want_rect14.size.y) < 0.01,
			"段14：气泡 u_rects==content×视口拉伸（设备系分流锁死，实际 %s 期望 %s）" % [v4, want_rect14])
	container2.queue_free()
	lvl2.queue_free()
	await process_frame

	finish()
