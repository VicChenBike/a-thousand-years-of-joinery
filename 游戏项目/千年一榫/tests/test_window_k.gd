extends "res://tests/test_base.gd"
## K-A（KA-2，spec §4.3）：窗口系统逻辑层断言——①project.godot [display] 段
## （canvas_items/expand/16:9 基准 1152×648/无边框可缩放下）；②16:9 校正纯数学；
## ③拖窗交互控件命中排除真值（P1-2 契约①）；④K9 悬停光晕判定真值。
## 新增组件一律 load() 引用，不写全局类名（T14 实证 class_name 注册时序防御）。

func _initialize() -> void:
	print("== test_window_k ==")
	# ① [display] 段工程设置（KA-2 写入；无头下 ProjectSettings 仍可断言）
	check_eq(int(ProjectSettings.get_setting("display/window/size/viewport_width")), 1152,
		"K8-2：viewport_width=1152（16:9 基准）")
	check_eq(int(ProjectSettings.get_setting("display/window/size/viewport_height")), 648,
		"K8-2：viewport_height=648")
	check_eq(int(ProjectSettings.get_setting("display/window/size/window_width_override")), 1152,
		"K8-1：窗口宽 override=1152")
	check_eq(int(ProjectSettings.get_setting("display/window/size/window_height_override")), 648,
		"K8-1：窗口高 override=648")
	check_eq(String(ProjectSettings.get_setting("display/window/stretch/mode")), "canvas_items",
		"K8-1：stretch/mode=canvas_items（拉伸跟随缩放）")
	check_eq(String(ProjectSettings.get_setting("display/window/stretch/aspect")), "expand",
		"K8-3：stretch/aspect=expand（常见比例全屏铺满不畸形）")
	check_eq(bool(ProjectSettings.get_setting("display/window/size/borderless")), true,
		"K8-4：borderless=true（无边框自绘三按钮前提）")
	check_eq(bool(ProjectSettings.get_setting("display/window/size/resizable")), true,
		"K8-1：resizable=true（可拖拽缩放）")

	# ②③④ window_manager.gd 纯逻辑（静态方法，load() 后经脚本资源直调，4.7 探针实证）
	var wm: Script = load("res://scripts/window_manager.gd")
	if wm == null:
		check(false, "scripts/window_manager.gd 可加载（缺失则②③④共 10 项断言不可用）")
	else:
		# ② 16:9 校正纯数学：以宽为锚（spec §4.3 定稿），最小高 405 夹紧
		check_eq(wm.aspect_correction(Vector2i(1000, 800)), Vector2i(1000, 563),
			"K8-2：1000x800→以宽为锚 1000x563（round(1000*9/16)）")
		check_eq(wm.aspect_correction(Vector2i(1600, 900)), Vector2i(1600, 900),
			"K8-2：1600x900 已 16:9 不变")
		check_eq(wm.aspect_correction(Vector2i(1280, 600)), Vector2i(1280, 720),
			"K8-2：1280x600→1280x720（含低于最小高时仍按宽锚校正）")
		# 批次 T（T18，spec §5）：MIN_SIZE 800×450。等价替换留痕：本文件旧断言无 720×405 直接依赖
		# （aspect_correction 两例结果 563/720 均不低于 450 不受影响——计划裁决 J4 核查记录）。
		check((wm.get("MIN_SIZE") as Vector2i) == Vector2i(800, 450),
			"T18：MIN_SIZE=(800,450)（旧 720×405 废止留痕）")
		# ③ 拖窗命中排除（P1-2 契约①：可交互控件不启动拖窗，场景按钮不受影响）
		check(wm.is_interactive_control(Button.new()),
			"K8-4：Button 判可交互（不拖窗）")
		check(wm.is_interactive_control(HSlider.new()),
			"K8-4：HSlider 判可交互（不拖窗）")
		check(wm.is_interactive_control(SubViewportContainer.new()),
			"K8-4：SubViewportContainer 判可交互（关卡 3D 输入不拖窗）")
		check(not wm.is_interactive_control(Label.new()),
			"K8-4：Label 判非交互（空白按下可拖窗）")
		# ④ K9 光晕判定：Button/TextureButton 自动生效 + meta("hover_glow") 接入
		check(wm.is_glow_target(Button.new()),
			"K9：Button 为光晕目标")
		var glow_panel: Panel = Panel.new()
		glow_panel.set_meta("hover_glow", true)
		check(wm.is_glow_target(glow_panel),
			"K9：挂 hover_glow meta 的 Panel 为光晕目标")
		check(not wm.is_glow_target(Label.new()),
			"K9：Label 非光晕目标")

	# ⑤ KA-4 自绘三按钮 + 无边框拖窗挂接（P2-5：load() 方式，不引用全局类名）
	var wb_scene: PackedScene = load("res://scenes/shared/window_buttons.tscn")
	check(wb_scene != null, "K8-4：window_buttons.tscn 可加载")
	if wb_scene != null:
		var wb: Node = wb_scene.instantiate()
		add_child(wb)  # 三按钮在 _ready() 内代码生成，必须入树（无头可行）
		await process_frame  # --script 下 _ready 延迟至入树后下一帧（T03 探针实证惯例）
		check(wb.get_child_count() == 3, "K8-4：最小化/最大化/关闭三按钮已生成")
		check(wb.has_signal("minimize_pressed") and wb.has_signal("maximize_toggled") \
			and wb.has_signal("close_pressed"), "K8-4：三信号齐备（close_pressed 不直接 quit，契约）")
		var focus_ok: bool = wb.get_child_count() == 3
		for i: int in range(wb.get_child_count()):
			var b: Button = wb.get_child(i) as Button
			focus_ok = focus_ok and b != null and b.focus_mode == Control.FOCUS_NONE
		check(focus_ok, "K8-4：三按钮均 focus_mode=FOCUS_NONE（防 Esc/空格误聚焦）")
		check(wm != null and wb.get_child_count() == 3 and wm.is_glow_target(wb.get_child(0)),
			"K9：首按钮经 is_glow_target 命中（光晕 meta 接入）")
		# P1-1 回修防回归：三钮+间距总宽不得超预留槽 108px（offset -124..-16），
		# 否则 HBox 最小宽左溢压盖 SettingsButton（审查截图 01/02 实证 178px 事故）。
		check(wb.get_combined_minimum_size().x <= 108.0,
			"P1-1：三钮总宽<=预留 108px（小号样式覆盖生效，不左溢压盖设置按钮）")
		# K-H（P1 回修）防回归：无边框窗口 get_mode() 不报 MAXIMIZED（走查实证 2560x1440 下仍 0）
		# → 本地状态机 _maxed 须独立驱动字形回显（还原不再死路、字形不再漏亮）
		var mb2: Button = wb.get_child(1) as Button
		wb.set("_maxed", true)
		wb.call("refresh_state")
		check(mb2.text == "❐", "K-H：_maxed=true → 字形❐（本地状态机回显，不依赖 get_mode）")
		wb.set("_maxed", false)
		wb.call("refresh_state")
		check(mb2.text == "□", "K-H：_maxed=false → 字形□（还原态回显）")
		# M-A（spec §3.1/§4.1，2026-09-07）：三钮字形对比度——按主题显式覆写字形色接口。
		# N12（2026-09-10 用户反馈）等价替换留痕：字形色随 N12 主题按钮字色方案——
		# 深米黄浅金 (0.96,0.90,0.78)（原米白金 0.77 尾值微调同档）、浅深棕 (0.227,0.165,0.063)
		# （原深墨棕 0.102，与浅主题按钮字色同族）；三钮底色同步对齐 N5 主题深棕档（N12-2）。
		var wb_script: Script = load("res://scenes/shared/window_buttons.gd")
		# 批次 AB-3：深浅双常量收敛为单值（深档值逐一未变），浅档常量/翻转回调反向锁退役。
		var glyph: Variant = wb_script.get("GLYPH_COLOR")
		check(glyph is Color and (glyph as Color).is_equal_approx(Color(0.96, 0.90, 0.78)),
			"AB-3 等价改写：GLYPH_COLOR=米黄浅金 (0.96,0.90,0.78)（旧深档值不变）")
		check(wb_script.get("GLYPH_COLOR_LIGHT") == null and wb_script.get("BG_NORMAL_LIGHT") == null,
			"AB-3 反向锁：GLYPH_COLOR_LIGHT/BG_NORMAL_LIGHT 浅档常量退役（无复辟）")
		# N12-2：三钮底色常量与 N5 主题按钮深棕档对齐（AB-3 唯一档）
		var bg_n: Variant = wb_script.get("BG_NORMAL")
		check(bg_n is Color and (bg_n as Color).is_equal_approx(Color(0.38, 0.27, 0.10)),
			"N12-2：BG_NORMAL==深棕 (0.38,0.27,0.10)（==theme_dark Button normal 底，弃亮金 0.788；AB-3 单值）")
		if mb2 != null:
			check(mb2.has_theme_color_override("font_color") and mb2.get_theme_color("font_color").is_equal_approx(Color(0.96, 0.90, 0.78)),
				"AB-3 等价改写：三钮字形色恒米黄浅金（旧 theme_changed(true) 深档终态值不变）")
		wb.free()
	var main_inst: Node = load("res://scenes/main.tscn").instantiate()  # 不入树，_ready 不触发
	var wb_mount: Node = main_inst.get_node_or_null("GlobalUI/WindowButtons")
	var drag_zone: Control = main_inst.get_node_or_null("GlobalUI/WindowDragZone") as Control
	var settings: Control = main_inst.get_node_or_null("GlobalUI/SettingsButton") as Control
	check(wb_mount != null, "K8-4：main.tscn GlobalUI/WindowButtons 已挂载（右上角常驻）")
	check(drag_zone != null and drag_zone.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"K8-4：WindowDragZone 存在且 mouse_filter=IGNORE（热区不拦截事件，P1-2 方案）")
	# L-B/L1（用户 2026-09-06 反馈拍板）：设置钮移到窗口三钮**正下方**——L1 用户需求有意
	# 推翻 K 批「左移避让」约束（spec §6.5 定稿几何 (-124,48,-16,84)），原两条避让断言
	# （K8-4 offset_right<=-132 / P1-1 右缘<=WindowButtons 左缘）删除，由下列新几何契约承接。
	# U-C P0（452aa7b，用户 2026-09-19 截图反馈四元素 clearance 口径）等价替换留痕：
	# 设置钮几何 (-16,48)→(-24,52)（W-24 顶52，与 WindowButtons 右缘对齐、上避 8px），
	# test_u_dock_anchors/test_menu_ellipse 同批已锁值，此处旧契约断言补同步（收口甄别）。
	check(settings != null and absf(settings.offset_right + 24.0) < 0.5 and absf(settings.offset_top - 52.0) < 0.5,
		"L-B/L1：SettingsButton 几何契约（offset_right=-24、offset_top=52；U-C P0 口径等价替换）")
	if settings != null and wb_mount is Control:
		var wb_c: Control = wb_mount as Control
		check(settings.offset_right == wb_c.offset_right and settings.offset_top >= wb_c.offset_bottom,
			"L-B/L1：SettingsButton 右缘与 WindowButtons 对齐、顶缘≥其底缘（正下方对齐不重叠）")
	else:
		check(false, "L-B/L1：SettingsButton 正下方对齐断言前置（节点缺失）")
	# P2-1 回修：main.gd F11 分支须调用 set_fullscreen 后 refresh_state 回显字形
	var main_src: String = FileAccess.get_file_as_string("res://scenes/main.gd")
	check(main_src.contains("set_fullscreen") and main_src.contains("refresh_state"),
		"P2-1：main.gd F11 全屏切换后调 refresh_state 回显 □/❐")
	# K-C（KC-3）→ 批次V规格§3.2（V-C6）等价替换留痕（原 K-C：GlobalUI/ExitConfirmDialog 为
	# GlassDialog 实例断言，镜像 V-C5 对 main_menu.tscn 弹窗退役的处置——本件与 test_k_regression
	# :42 系同一断言的两处重复，规格 §10 必破清单漏列本件，实施偏差备案）：窗口×确认弹窗节点
	# 退役，关闭确认改经 Game.confirm → TopStrip 统一确认条（文案/回调断言归
	# test_v_quit_and_boot.gd；接线断言见下条保持不变）。
	check(main_inst.get_node_or_null("GlobalUI/ExitConfirmDialog") == null,
		"批次V§3.2：GlobalUI/ExitConfirmDialog 节点已退役（窗口×确认改经 Game.confirm 统一弹条）")
	check(main_src.contains('connect("close_pressed", _on_window_close)') \
		and main_src.contains("func _on_window_close(") and main_src.contains("func _quit_now_shared("),
		"K-C：close_pressed 改接 _on_window_close 弹确认弹窗，confirmed → _quit_now_shared（不再直接退出）")
	main_inst.free()
	finish()
