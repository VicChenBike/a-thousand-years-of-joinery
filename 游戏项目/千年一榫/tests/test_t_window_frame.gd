extends "res://tests/test_base.gd"
## 批次 T 判定用例（T-A 域）：T17 真透明圆角窗口 + T18 四角斜角等比缩放。
## 覆盖：project.godot 透明两设置 + min 800×450（段 1，4 checks）；rounded_frame 常量（段 2，11；
## 批次 U U9 等价替换 7→11：FRAME_STROKE_COLOR 单源 70% 透明灰＋旧四常量删除锁＋DWM_STROKE_COLOR 源码级删除锁）；
## Frame/热区结构（段 3，10）；main.tscn 挂载与内缩 + main.gd 源证据（段 4，8）；
## corner_resize 纯函数表驱动（段 5，10）+ 四角 pos 不变式（P1-3 终版公式，防按错误口径自洽假绿）；
## 批次 U：window_decoration_hidden 表驱动（段 6，4）＋U10 数值表 main.tscn 四元素 offsets（段 7，9；
## UB-5 已由 4bc6fe1 提前落地；P0 追加口径③（用户 2026-09-19 截图反馈）clearance+8px 终值
## 与 set_decoration_hidden 接线源锁并入本段）。
## 无头守卫：窗口 API 全走 WindowManager 纯函数（headless 不触 DisplayServer 写路径）。
## 计划裁决 J3：CORNER_HOT=18（spec 20 与窗口钮内缩后 2px 重叠带不相容，保守取 18 保「两两不相交」）。
## 【备案形态 J5】透明兼容 spike 判 FAIL（gl_compatibility 无逐像素透明；证据归档
## AI工作记录/walkthrough_20260916T/spike/）——段 1 前两条与段 4 透明源两条改备案口径：
## 透明两设置不置 true、main.gd 无透明初始化，外框走 RoundedFrame FALLBACK_INNER 内侧装饰框。

const MAIN_SCENE := "res://scenes/main.tscn"

func _initialize() -> void:
	print("== test_t_window_frame ==")
	# ---- 段 1. project.godot（4 checks）----
	# 备案形态两键不存在 → get_setting 须带 default=false（4.7 实证：bool(null) 报
	# 「Nonexistent 'bool' constructor」中止 _initialize——T-C 域坑同源，red_run_temp.txt :17）
	check_eq(bool(ProjectSettings.get_setting("display/window/per_pixel_transparent_allowed", false)), false,
		"T17 备案 J5：per_pixel_transparent_allowed 不置 true（spike 判 FAIL，gl_compatibility 无逐像素透明）")
	check_eq(bool(ProjectSettings.get_setting("display/window/size/transparent", false)), false,
		"T17 备案 J5：window/size/transparent 不置 true（备案形态窗口本体不透明）")
	check_eq(int(ProjectSettings.get_setting("display/window/size/min_width")), 800,
		"T18：min_width 720→800（等价替换留痕：旧值随 T17 内缩口径废止，spec §4-18-4）")
	check_eq(int(ProjectSettings.get_setting("display/window/size/min_height")), 450,
		"T18：min_height 405→450（等价替换留痕同上；16:9 维持）")
	# ---- 段 2. rounded_frame.gd 常量（7 checks）----
	var rf: Script = load("res://scenes/shared/rounded_frame.gd")
	check(rf != null, "scenes/shared/rounded_frame.gd 可加载")
	if rf == null:
		finish()
		return
	check(bool(is_equal_approx(float(rf.get("FRAME_INSET")), 10.0)), "T17：FRAME_INSET=10.0（v2 起内容全出血不再消费，留档常量）")
	check(bool(is_equal_approx(float(rf.get("FRAME_RADIUS")), 8.0)), "v2：FRAME_RADIUS=8（用户 2026-09-19 二次截图反馈-v2：对齐 Win11 DWMWCP_ROUND 原生圆角；旧 18 留痕；备案态 drawer 取 0=直角贴边环）")
	check(bool(is_equal_approx(float(rf.get("FRAME_STROKE")), 2.0)), "T17：FRAME_STROKE=2.0")
	# 批次 U 等价替换（U9-1，spec §4-U9-1/§5）：FRAME_COLOR_DARK/LIGHT 主题双档废止 →
	# FRAME_STROKE_COLOR 单源统一 70% 透明灰（旧值 (0.42,0.34,0.22,0.65)/(0.55,0.45,0.30,0.75) 留痕）。
	# 取色经 Variant 哨兵（批次 T 实证规律⑦族：null 直 as Color 后调方法=运行期中止，红灯要 FAIL 不要 crash）
	var u_stroke: Variant = rf.get("FRAME_STROKE_COLOR")
	check(u_stroke is Color and (u_stroke as Color).is_equal_approx(Color(0.55, 0.55, 0.55, 0.30)),
		"U9：FRAME_STROKE_COLOR=(0.55,0.55,0.55,0.30) 两路线描边单源")
	check(rf.get("FRAME_COLOR_DARK") == null and rf.get("FRAME_COLOR_LIGHT") == null,
		"U9：FRAME_COLOR_DARK/LIGHT 旧常量删除（双审 P2-15 单源化）")
	check(rf.get("HIGHLIGHT_ALPHA") == null, "U9：HIGHLIGHT_ALPHA 删除（白高光弧废止，U9-3）")
	check(rf.get("PANEL_BG_DARK") == null and rf.get("FALLBACK_CORNER_COLOR") == null,
		"v2：PANEL_BG_DARK 与 FALLBACK_CORNER_COLOR 均删除（用户 2026-09-19 二次截图反馈-v2：一切带状/角外填充废止——深黑包裹层方案推翻，内容全出血；旧值 (0.42,0.34,0.22,1.0)/(0.06,0.06,0.06,1.0) 留痕）")
	var rf_src: String = FileAccess.get_file_as_string("res://scenes/shared/rounded_frame.gd")
	check(not rf_src.contains("DWM_STROKE_COLOR"),
		"U9：DWM_STROKE_COLOR 旧常量源码级删除锁（grep 不含旧名——双审 P2-15 单源化，双审回修⑥补）")
	check(not rf_src.contains("draw_colored_polygon") and not rf_src.contains("draw_rect("),
		"v2：rounded_frame 零带状填充源码级删除锁（只保留 _draw_frame_path 描边环；用户二次截图反馈-v2）")
	check(bool(is_equal_approx(float(rf.get("CORNER_HOT")), 18.0)), "T18：CORNER_HOT=18（裁决 J3）")
	# ---- 段 2.2 批次 U（U9-6）：全屏/最大化隐藏装饰判据（4 checks；纯函数无头可测）----
	# 磁盘实况裁决（4.7 探针实测，ClassDB.class_get_enum_constants("Window","Mode")）：
	# 排他全屏枚举成员名=MODE_EXCLUSIVE_FULLSCREEN（计划稿写 MODE_FULLSCREEN_EXCLUSIVE 系文档名，
	# 4.7 Parse Error「Cannot find member」→ 按实况更正，值同为 4）。
	var rf2: GDScript = load("res://scenes/shared/rounded_frame.gd")
	check(bool(rf2.window_decoration_hidden(Window.MODE_WINDOWED)) == false, "U9-6：WINDOWED → 装饰可见")
	check(bool(rf2.window_decoration_hidden(Window.MODE_MAXIMIZED)) == true, "U9-6：MAXIMIZED → 隐藏（判据 mode >= MODE_MAXIMIZED）")
	check(bool(rf2.window_decoration_hidden(Window.MODE_FULLSCREEN)) == true, "U9-6：FULLSCREEN → 隐藏")
	check(bool(rf2.window_decoration_hidden(Window.MODE_EXCLUSIVE_FULLSCREEN)) == true, "U9-6：EXCLUSIVE_FULLSCREEN → 隐藏（完备性，双审 P2-15；4.7 成员名实况更正留痕）")
	# ---- 段 3. RoundedFrame 结构（9 checks）----
	var layer: CanvasLayer = rf.new()
	add_child(layer)
	await process_frame
	check_eq(int(layer.layer), 128, "T17：CanvasLayer layer=128（GlobalUI=1/Glow=100/光标=100 之上）")
	var frame: Control = layer.get_node_or_null("Frame") as Control
	check(frame != null and frame.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"T17：Frame 自绘件存在且 mouse_filter=IGNORE（描边区外全穿透）")
	var hots: Array = []
	for i: int in 4:
		var h: Control = layer.get_node_or_null("Frame/Hot%d" % i) as Control
		check(h != null and h.mouse_filter == Control.MOUSE_FILTER_STOP and h.has_meta("interactive"),
			"T18：热区 Hot%d 存在 + STOP + meta(interactive)（拖窗命中排除，循环展开 4）" % i)
		if h != null:
			hots.append(h)
	var sz_ok := hots.size() == 4
	for h: Control in hots:
		sz_ok = sz_ok and (h.size.round() as Vector2).is_equal_approx(Vector2(18, 18))
	check(sz_ok, "T18：四热区均 18×18（CORNER_HOT）")
	var cursor_ok := hots.size() == 4
	for i: int in hots.size():
		var want: int = Control.CURSOR_FDIAGSIZE if (i == 0 or i == 3) else Control.CURSOR_BDIAGSIZE
		cursor_ok = cursor_ok and int((hots[i] as Control).mouse_default_cursor_shape) == want
	check(cursor_ok, "T18：TL/BR=CURSOR_FDIAGSIZE、TR/BL=CURSOR_BDIAGSIZE（循环展开 4）")
	var pairs_ok := true
	for i: int in hots.size():
		for j: int in range(i + 1, hots.size()):
			if (hots[i] as Control).get_rect().intersects((hots[j] as Control).get_rect()):
				pairs_ok = false   # C(4,2)=6 对比较合 1 条 check
	check(pairs_ok, "T18：四热区两两不相交（C(4,2)=6 对展开）")
	# RV-1 P0-1 回修源证据（S13 先例）：gui_input.bind 尾随追加序 → 处理器签名必须 (ev, corner)；
	# 无头 gui_input 不发射，结构断言测不出倒置（假绿），只能源证据锁签名。
	check(FileAccess.get_file_as_string("res://scenes/shared/rounded_frame.gd")
		.contains("func _on_corner_input(ev: InputEvent, corner: int)"),
		"T18：_on_corner_input 签名 (ev, corner)（gui_input bind 尾随追加序，RV-1 P0-1 源证据）")
	# ---- 段 4. main.tscn 挂载/内缩 + main.gd 源证据（8 checks）----
	var main_inst: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	var rf_node: Node = main_inst.get_node_or_null("RoundedFrame")
	check(rf_node != null and int(rf_node.get("layer")) == 128, "T17：main.tscn 挂载 RoundedFrame(layer=128)")
	var sc: Control = main_inst.get_node_or_null("SceneContainer") as Control
	check(sc != null and bool(is_equal_approx(sc.offset_left, 0.0)) and bool(is_equal_approx(sc.offset_top, 0.0)),
		"v2：SceneContainer 呼吸边距归零 offsets 左/上=0（用户 2026-09-19 二次截图反馈-v2：内容全出血；旧 +10 留痕）")
	check(sc != null and bool(is_equal_approx(sc.offset_right, 0.0)) and bool(is_equal_approx(sc.offset_bottom, 0.0)),
		"v2：SceneContainer 呼吸边距归零 offsets 右/下=0（旧 −10 留痕）")
	var gui: CanvasLayer = main_inst.get_node_or_null("GlobalUI") as CanvasLayer
	check(gui != null and (gui.offset as Vector2).is_equal_approx(Vector2.ZERO),
		"v2：GlobalUI(CanvasLayer).offset=(0,0)（内容全出血；旧 (10,10) 留痕——父级平移废止后节点本地 offset 即窗相对）")
	var src: String = FileAccess.get_file_as_string("res://scenes/main.gd")
	check(not src.contains("transparent_bg = true") and not src.contains("set_default_clear_color(Color(0, 0, 0, 0))"),
		"T17 备案 J5：main.gd 无透明初始化（root transparent_bg/清屏 α0 不落码，窗口本体不透明）")
	check(src.contains("J5 备案形态"),
		"T17 备案 J5：main.gd 备案留痕注释存在（spike FAIL → RoundedFrame FALLBACK_INNER 内侧装饰框）")
	check(src.contains("get_window().min_size = Vector2i(800, 450)"),
		"T18：main.gd 运行期 min_size 800×450（旧 720×405 等价替换留痕）")
	check(src.contains("_unavailable_toast_text()"),
		"T11：main.gd toast 文案 helper 存在（双分支语义归 T-F 断言，P1-4）")
	main_inst.free()
	# ---- 段 5. corner_resize 纯函数表驱动（10 checks）----
	var wm: Script = load("res://scripts/window_manager.gd")
	check(wm != null, "window_manager.gd 可加载（缺失则段 5 其余 9 项不可用）")
	if wm == null:
		layer.queue_free()
		finish()
		return
	var r: Dictionary = wm.corner_resize(Vector2i(1152, 648), 3, Vector2(115.2, 64.8), Vector2i(2560, 1440), Vector2i(100, 100))
	check((r["size"] as Vector2i) == Vector2i(1267, 713),
		"T18：BR(3) 拖 (115.2,64.8) → 1267×713（s≈1.1 对角投影，先锁比例 P2-9）")
	check((r["pos"] as Vector2i) == Vector2i(100, 100), "T18：BR 拖拽对角 TL 固定 → pos 不动")
	r = wm.corner_resize(Vector2i(1152, 648), 0, Vector2(-115.2, -64.8), Vector2i(2560, 1440), Vector2i(100, 100))
	check((r["size"] as Vector2i) == Vector2i(1037, 583), "T18：TL(0) 反向拖 → 1037×583（s≈0.9）")
	check((r["pos"] as Vector2i) == Vector2i(215, 165), "T18：TL 拖拽对角 BR 固定 → pos=BR_start−new_size")
	r = wm.corner_resize(Vector2i(1152, 648), 3, Vector2(-2000, -2000), Vector2i(2560, 1440), Vector2i(100, 100))
	check((r["size"] as Vector2i) == Vector2i(800, 450), "T18：超缩 → 钳 800×450（s_min 整体系数两维同乘，恒 16:9）")
	check((r["pos"] as Vector2i) == Vector2i(100, 100), "T18：下限钳制后 BR 对角 TL 仍 (100,100)")
	r = wm.corner_resize(Vector2i(1152, 648), 3, Vector2(4000, 4000), Vector2i(1920, 1080), Vector2i(100, 100))
	check((r["size"] as Vector2i) == Vector2i(1920, 1080), "T18：超放 → 钳工作区上限 1920×1080")
	var r9: Dictionary = wm.corner_resize(Vector2i(1152, 648), 1, Vector2(53.0, 47.0), Vector2i(2560, 1440), Vector2i(100, 100))
	var ns: Vector2i = r9["size"]
	check(absf(float(ns.x) * 9.0 / 16.0 - float(ns.y)) <= 1.0, "T18：取整后恒 16:9（公差 ≤1px）")
	var inv_ok := true
	for corner: int in [0, 1, 2, 3]:
		var rr: Dictionary = wm.corner_resize(Vector2i(1152, 648), corner, Vector2(120.0, 70.0), Vector2i(2560, 1440), Vector2i(100, 100))
		var off: Vector2 = wm.corner_offset(corner)
		var c_start := Vector2(100, 100) + Vector2((1.0 - off.x) * 1152.0, (1.0 - off.y) * 648.0)
		var sz: Vector2i = rr["size"]
		var lhs := Vector2(rr["pos"] as Vector2i) + Vector2((1.0 - off.x) * float(sz.x), (1.0 - off.y) * float(sz.y))
		if not lhs.is_equal_approx(c_start):
			inv_ok = false
	check(inv_ok, "T18：四角 pos 不变式 pos_new+(1−off)逐轴×new_size==C_start 全列成立（循环展开 4 角；P1-3 防假绿写死）")
	layer.queue_free()
	# ---- 段 7. 批次 U（U10 数值表 + P0 追加口径③ + v2 补偿，spec §4-U10，9 checks）----
	# v2（用户 2026-09-19 二次截图反馈-v2）：GlobalUI offset 归零后节点本地 offset 即窗相对，
	# 四元素本地 offsets +10 反向补偿，窗相对终态不变（右缘 W−24、WB 顶 12、Toast/加载提示
	# 距缘 ≥20，环内缘 clearance ≥6px 维持 P0③ 口径；P0③ 未补偿本地值留痕）。
	# 钉设计视口（批次 L 实证坑：无头 expand 撑大；窗相对断言依赖 1152 宽）。
	root.size = Vector2i(1152, 648)
	var main_node: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(main_node)
	await process_frame
	await process_frame
	# 磁盘实况裁决（4.7 无头实测）：Control.get_global_transform 链止于 CanvasLayer（非 CanvasItem），
	# 不含 CanvasLayer.offset——窗相对语义换算=canvas rect ＋ GlobalUI.offset（v2 后 offset=(0,0)，
	# 换算退化为恒等，公式保留以双兼容）。
	var gui_off: Vector2 = (main_node.get_node("GlobalUI") as CanvasLayer).offset
	var wb: Control = main_node.get_node("GlobalUI/WindowButtons")
	check(wb.offset_left == -132.0 and wb.offset_top == 12.0 and wb.offset_right == -24.0 and wb.offset_bottom == 44.0,
		"v2：WindowButtons 本地 offsets==(−132,12,−24,44)（窗相对右缘 W−24、顶 12 不变；P0③ 未补偿 (−142,2,−34,34) 留痕）")
	check_eq(float(wb.get_global_rect().end.x) + gui_off.x, 1152.0 - 24.0, "v2：WindowButtons 窗相对右缘 W−24（canvas rect+GlobalUI offset 换算）")
	var sb3: Control = main_node.get_node("GlobalUI/SettingsButton")
	check(sb3.offset_left == -132.0 and sb3.offset_top == 52.0 and sb3.offset_right == -24.0 and sb3.offset_bottom == 84.0,
		"v2：SettingsButton 本地 offsets==(−132,52,−24,84)（窗相对顶 52 不变；P0③ (−142,42,−34,74) 留痕）")
	check_eq(float(sb3.get_global_rect().end.x) + gui_off.x, 1152.0 - 24.0, "v2：SettingsButton 窗相对右缘 W−24")
	var tc: Control = main_node.get_node("GlobalUI/ToastCenter")
	check_eq(float(tc.offset_right), -24.0, "v2：ToastCenter offset_right 终值 −24（窗相对 W−24；P0③ −34 留痕）")
	check_eq(float(tc.get_global_rect().end.x) + gui_off.x, 1152.0 - 24.0, "v2：ToastCenter 窗相对右缘 W−24（描边带零遮挡）")
	var lt: Control = main_node.get_node("GlobalUI/GestureLoadingTip")
	check(lt.offset_left == -268.0 and lt.offset_top == -122.0 and lt.offset_right == -24.0 and lt.offset_bottom == -90.0,
		"v2：GestureLoadingTip 本地 offsets==(−268,−122,−24,−90)（右缘 W−24、尺寸 244×32 不变；批次 AA 终态验收备案① 上移 70px 让位结算「下一关」钮，净隙 6px；旧 (−268,−52,−24,−20) 留痕）")
	check_eq(float(lt.get_global_rect().end.x) + gui_off.x, 1152.0 - 24.0, "v2：GestureLoadingTip 窗相对右缘 W−24")
	var src_u: String = FileAccess.get_file_as_string("res://scenes/main.gd")
	check(src_u.contains("set_decoration_hidden"),
		"P0①：main.gd maximize_toggled → RoundedFrame.set_decoration_hidden 接线存在（borderless get_mode 恒报 WINDOWED，K-H/4.7 双实证——用户 2026-09-19 截图反馈）")
	# R2②-P2-3：_poll_dwm_flag_async 每秒 tick 顺带刷新装饰层隐藏态（mode+_maxed 综合判定）
	# ——Aero Snap 拖拽最大化不走 maximize_toggled 信号，15s 轮询窗内收敛；源码锁锁「轮询函数
	# 体内含综合判定与 set_decoration_hidden 第二调用点」。
	check(src_u.count("set_decoration_hidden") >= 2 and src_u.contains("window_decoration_hidden"),
		"R2②-P2-3：_poll_dwm_flag_async 轮询顺带刷新装饰层隐藏（window_decoration_hidden(mode)+_maxed 综合判定；Aero Snap 拖拽最大化 15s 内收敛）")
	main_node.queue_free()
	await process_frame
	# ---- 批次 U 段（U11，spec §4-U11，3 checks；UC-4 之后串行并入本文件——双审 P2-10）----
	var ls: Node = (load("res://scenes/level/level_scene.tscn") as PackedScene).instantiate()
	get_root().add_child(ls)
	await process_frame
	var title: Label = ls.get_node("TopBar/TitleLabel")
	check_eq(int(title.text_overrun_behavior), TextServer.OVERRUN_TRIM_ELLIPSIS,
		"U11：TitleLabel text_overrun_behavior==TRIM_ELLIPSIS（clip_text 硬截断废止，tscn 属性值 3）")
	var vb: Label = ls.get_node("TopBar/VoxelLabel")
	check_eq(float(title.size_flags_stretch_ratio), 2.0, "U11：TitleLabel stretch_ratio=2.0")
	check_eq(float(vb.size_flags_stretch_ratio), 1.0, "U11：VoxelLabel stretch_ratio=1.0（2:1）")
	ls.queue_free()
	await process_frame
	finish()
