extends "res://tests/test_base.gd"
## L-C（spec §9 L-C 行）：①glow_targets_for 邻接采集+分级真值（普通 0.75/退出 0.30/容器 0.30
## +椭圆掩码/邻居 0.35（退出钮作邻居 0.30）/≤8 截断+主目标优先近邻优先）；②GlowRect 材质
## uniform 写读链；③半径分档。
## 红灯防挂死纪律（LC-1 要求）：常量/静态方法未落地时，取缺失成员会触发 4.7 运行时错误、
## --script 模式下可能中断流程 → 先经 get_script_constant_map()/get_script_method_list()
## 判定存在性，缺失即 check(false) 后 finish() 安全退出（红灯可退出、不挂死）。

## spec §7.1 定稿分级表（键=常量名，值=定稿真值）；系数 + 截断上限
## L-D 走查定档：退出档 0.40/0.38→0.30/0.30（spec §14-11 档内 ±0.1；截图实测原 0.40 档下
## 退出钮与普通钮亮度差仅 ~14%，L6-5「明显低于」不达 → 档位差拉满到 0.75/0.30=2.5）
## M-C 收口（2026-09-08 中期审查回修）：半径常量 GLOW_RADIUS_BTN/PANEL 已从 window_manager
## 删除（真值源=main.gd.HOVER_GLOW_RADIUS_*=85/110），本表不再含半径键，半径改断 main.gd。
## 批次 AB-3（深浅主题机制删除）：原 *_DARK/*_LIGHT 双档 6 键收敛为单值 3 键（值=旧深档
## 0.75/0.30/0.30，逐一未变；浅档 0.70/0.30/0.28 随功能退役）。
const GLOW_CONSTS := {
	"GLOW_MAX_NORMAL": 0.75,
	"GLOW_MAX_QUIT": 0.30,
	"GLOW_MAX_PANEL": 0.30,
	"GLOW_MAX_WINDOW": 0.55,
	"NEIGHBOR_COEF": 0.35, "QUIT_NEIGHBOR_COEF": 0.30,
	"MAX_RECTS": 8,
}

func _initialize() -> void:
	print("== test_glow_grade ==")
	var wm: GDScript = load("res://scripts/window_manager.gd")
	check(wm != null, "L-C：window_manager.gd 可加载（分级常量/采集静态方法宿主）")
	if wm == null:
		finish()
		return
	# ---- 红灯防挂死 guard：常量缺失 → 逐条 check(false) 后 finish ----
	var cmap: Dictionary = wm.get_script_constant_map()
	var missing: Array = []
	for key: String in GLOW_CONSTS:
		if not cmap.has(key): missing.append(key)
	if not missing.is_empty():
		for key: String in missing:
			check(false, "L-C：window_manager 缺分级常量 %s（LC-2 未实现）" % key)
		finish()
		return
	# ---- 分级常量硬真值（spec §7.1 定稿表，深/浅；经 constant_map 取值防运行时报错） ----
	for key: String in GLOW_CONSTS:
		check_eq(cmap[key], GLOW_CONSTS[key], "L-C：分级常量 %s==%s（spec §7.1 定稿表）" % [key, GLOW_CONSTS[key]])
	# ---- M-C 收口等价替换：常量删除，真值源=main.gd（HOVER_GLOW_RADIUS_*=85/110，经
	# _push_glow_radii 每帧写入 GlowRect 材质；与 test_m_cursor_glow 同口径互证，替代原
	# window_manager.GLOW_RADIUS_BTN==65/PANEL==110 断言，防 65 失效值复辟） ----
	var mcmap: Dictionary = (load("res://scenes/main.gd") as GDScript).get_script_constant_map()
	check(mcmap.has("HOVER_GLOW_RADIUS_BTN") and absf(float(mcmap["HOVER_GLOW_RADIUS_BTN"]) - 85.0) < 0.001,
		"M-C 收口等价替换：常量删除，真值源=main.gd（HOVER_GLOW_RADIUS_BTN==85，每帧写入）")
	check(mcmap.has("HOVER_GLOW_RADIUS_PANEL") and absf(float(mcmap["HOVER_GLOW_RADIUS_PANEL"]) - 110.0) < 0.001,
		"M-C 收口等价替换：常量删除，真值源=main.gd（HOVER_GLOW_RADIUS_PANEL==110，每帧写入）")
	# ---- 红灯防挂死 guard：静态方法缺失 → check(false) 后 finish ----
	var has_fn := false
	for m: Dictionary in wm.get_script_method_list():
		if String(m["name"]) == "glow_targets_for": has_fn = true
	if not has_fn:
		check(false, "L-C：window_manager 缺静态方法 glow_targets_for（LC-2 未实现）")
		finish()
		return
	# ① 主菜单实例（M-B：容器改**显式钉设计视口 1152×648**——原 PRESET_FULL_RECT 在 headless
	# expand 下撑 1152×1152，容器档 ellipses 绝对值断言 (全局左缘,中心y,440,H/2) 的 H/2 必须 324，
	# M 批等价替换；meta 随 L-B 落地）
	var container: Control = Control.new()
	container.size = Vector2(1152.0, 648.0)
	add_child(container)
	var mm: Node = (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate()
	container.add_child(mm)
	await process_frame
	await process_frame
	await process_frame
	# 批次 AB-3：恒深档（is_dark() 探测随深浅主题机制删除退役）
	var dark: bool = true
	print("L-C 判定档（批次 AB-3 恒深）：dark=%s" % dark)
	var start: Button = mm.find_child("StartButton", true, false) as Button
	var quit: Button = mm.find_child("QuitButton", true, false) as Button
	var panel: Control = mm.get_node_or_null("LeftPanel/EllipsePanel") as Control
	check(start != null and quit != null and panel != null, "L-C：主菜单三钮+椭圆容器就绪")
	# hover_glow 修复批（2026-09-18 追加）：_push 产出改设备系——期望值统一经同一视口拉伸
	# 变换映射（无头=虚拟缩放，窗口=逐轴 s；与生产恒同构，见 scripts/coord_space.gd 头注 3）。
	var glow_sxf: Transform2D = panel.get_viewport().get_screen_transform()
	# 普通钮 hover：主 0.75(浅0.70) + 容器 0.30(mask_type=1) + 两兄弟（LoadButton 0.75×0.35、
	# QuitButton 0.75×0.30——邻居系数按邻居自身档位，spec §7.1 表「作为邻居被联动系数」列；
	# 容器由祖先∪同父规则采集一次，邻居采集排除容器防重复）
	var gt: Dictionary = wm.glow_targets_for(start)
	var rects: Array = gt["rects"]
	check_eq(rects.size(), 4, "L-C：普通钮 hover 目标数=主1+容器1+兄弟2（容器不重复采集）")
	check_eq((gt["strengths"] as Array).size(), rects.size(), "L-C：strengths 与 rects 等长对齐")
	check_eq((gt["mask_types"] as Array).size(), rects.size(), "L-C：mask_types 与 rects 等长对齐")
	check_eq((gt["ellipses"] as Array).size(), rects.size(), "L-C：ellipses 与 rects 等长对齐")
	if rects.size() == 4:
		check_eq(float(gt["strengths"][0]), 0.75, "L-C：主目标=普通钮档上限（AB-3 恒深单值）")
		check_eq(int(gt["mask_types"][0]), 0, "L-C：主目标为矩形掩码档（mask_type=0）")
		check_eq(float(gt["strengths"][1]), 0.30, "L-C：容器区域档 0.30（AB-3 恒深单值，浅 0.28 退役）")
		check_eq(int(gt["mask_types"][1]), 1, "L-C：容器档 mask_type=1（椭圆 SDF 掩码）")
		var ell: Vector4 = gt["ellipses"][1]
		check(ell.z > 0.0 and ell.w > 0.0, "L-C：容器档 ellipse=(弧心,rx,ry) 参数有效（与面板材质同源）")
		# M-B（spec §3.2-2）：椭圆掩码 Vector4 改左贴弧口径——x=容器全局左缘、y=全局中心 y、
		# (rx,ry)=(440,H/2)，与面板材质 u_ellipse 两处消费同值（单一几何参数源 spec §1.4-1）。
		# hover_glow 修复批：产出改设备系，期望=content 常量经同一视口拉伸映射（下同）。
		var want_ell: Vector4 = Vector4((glow_sxf * Vector2(0.0, 324.0)).x, (glow_sxf * Vector2(0.0, 324.0)).y,
			440.0 * glow_sxf.get_scale().x, 324.0 * glow_sxf.get_scale().y)
		check_eq(ell, want_ell,
			"M-B+修复批：容器掩码 ellipse==(设备左缘0,设备中心y,rx×sx,ry×sy)（左贴弧口径设备化，content 恒量 (0,324,440,324)×拉伸）")
		check_eq(float(gt["strengths"][2]), 0.75 * 0.35, "L-C：普通钮邻居=主目标上限×0.35（≈0.26，亮度差≥2.5 倍）")
		check_eq(float(gt["strengths"][3]), 0.75 * 0.30, "L-C：退出钮作为邻居=主目标上限×0.30（spec §7.1 表）")
		check(gt["strengths"][0] / gt["strengths"][2] >= 2.5 and gt["strengths"][0] / gt["strengths"][3] >= 2.5,
			"L-C：主目标与邻居亮度差 ≥2.5 倍（主次可分辨，L6-3）")
	# 退出钮 hover：0.30（浅 0.30，L-D 走查定档）
	var gtq: Dictionary = wm.glow_targets_for(quit)
	check((gtq["rects"] as Array).size() > 0, "L-C：退出钮采集非空")
	if (gtq["rects"] as Array).size() > 0:
		check_eq(float(gtq["strengths"][0]), 0.30, "L-C/L-D：退出钮主档 0.30（浅同值）不过曝")
		check(gtq["strengths"][0] <= 0.5, "L-C：退出钮 hover 受控（≤0.50 封顶，L6-5 不过曝）")
		check(gtq["strengths"][0] / 0.75 <= 0.45,
			"L-D：退出档/普通档 ≤0.45（深 0.40 浅 0.43 → 档位亮度差 ≥2.2 倍，L6-5「明显低于普通钮」）")
	check(quit != null and float(quit.get_meta("glow_max")) == 0.30, "L-C：退出钮=显式 meta glow_max（不做文本匹配）")
	# 容器 hover：主=容器档且椭圆掩码
	var gtp: Dictionary = wm.glow_targets_for(panel)
	if (gtp["rects"] as Array).size() > 0:
		check_eq(int(gtp["mask_types"][0]), 1, "L-C：容器自身 hover 为椭圆掩码档")
		check_eq(float(gtp["strengths"][0]), 0.30, "L-C：容器 hover 主档 0.30 克制微光")
	# ② GlowRect 材质 uniform 写读链（模拟 main.gd 采集写入口径）
	var mi: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var rect_node: ColorRect = mi.get_node("GlobalUI/GlowLayer/GlowRect")
	var m: ShaderMaterial = rect_node.material as ShaderMaterial
	m.set_shader_parameter("u_rect_count", 2)
	check_eq(int(m.get_shader_parameter("u_rect_count")), 2, "L-C：GlowRect u_rect_count 写读")
	m.set_shader_parameter("u_rects", [Vector4(1, 2, 3, 4), Vector4(5, 6, 7, 8)])
	check((m.get_shader_parameter("u_rects") as Array).size() == 2, "L-C：u_rects 数组写入读回")
	m.set_shader_parameter("u_rect_strength", [0.75, 0.30])
	check_eq(float((m.get_shader_parameter("u_rect_strength") as Array)[1]), 0.30, "L-C：u_rect_strength 写读（分级值）")
	m.set_shader_parameter("u_mask_type", [0, 1])
	check_eq(int((m.get_shader_parameter("u_mask_type") as Array)[1]), 1, "L-C：u_mask_type 写读（容器档=1）")
	m.set_shader_parameter("u_ellipses", [Vector4.ZERO, Vector4(0.0, 324.0, 440.0, 324.0)])
	check((m.get_shader_parameter("u_ellipses") as Array).size() == 2, "L-C：u_ellipses 写读（M-B：示意值更新为左贴弧新口径，写读链语义不变）")
	mi.free()
	# ③ 截断+排序：1 主+10 兄弟（挂 hover_glow meta）→ size==8、主目标优先、近邻优先
	var holder: Control = Control.new()
	container.add_child(holder)
	var main_btn := Button.new()
	holder.add_child(main_btn)
	for i in 10:
		var nb := Control.new()
		nb.set_meta("hover_glow", true)
		nb.position = Vector2(100.0 * float(i + 1), 0.0)
		holder.add_child(nb)
	var gtc: Dictionary = wm.glow_targets_for(main_btn)
	check_eq((gtc["rects"] as Array).size(), 8, "L-C：目标数≤MAX_RECTS(8) 截断（1 主+10 兄弟→8）")
	if (gtc["rects"] as Array).size() == 8:
		check_eq(float(gtc["strengths"][0]), 0.75, "L-C：截断时主目标优先（index 0）")
		var r1: Rect2 = gtc["rects"][1]
		# hover_glow 修复批：rects 设备系——最近兄弟 content x=100 经同一视口拉伸映射
		check(absf(r1.position.x - (glow_sxf * Vector2(100.0, 0.0)).x) < 0.01,
			"L-C：截断按近邻距离升序（index1=最近兄弟 content x=100 的设备映射）")
	container.queue_free()
	finish()
