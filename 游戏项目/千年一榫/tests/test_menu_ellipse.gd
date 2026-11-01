extends "res://tests/test_base.gd"
## M-B（spec §3.2 主菜单专项·椭圆几何重做，拍板 #5/#7）——本文件为 M 批**整体重写版**：
## 旧 L-B/L-D「贴弧布局（arc_layout 等 y 间隙 155/155 + 弧心 (W-rx,H/2) rx380/ry280）」口径
## 全部废止，等价替换为「左贴弧 + stacked_layout 垂直均匀居中」新口径（各断言消息留痕
## 「M 批等价替换」；旧 arc_layout 函数已从 main_menu.gd 删除，留痕见其头部注释）。
## 新几何（拍板 #5）：半椭圆=右半支、弧心在面板左边缘 (0, H/2)、ry=H/2=324（端点严格过
## (0,0) 与 (0,648)）、rx=440（暂定值，走查微调）；LeftPanel anchor_right 0.34→0.42。
## 新布局（拍板 #7）：三钮垂直等间隙均布、整组对 H/2 居中、列中心 x=0.42*rx、钮 200×56。
## 标题重摆（spec §3.2-6）：与按钮列同轴、底边距带顶 ≥24px、字号 64 起 4px 步降档
## 至 16 角点（标题 4+三钮 12，u²+v²≤0.99）校验通过（校验即权威）+ 深墨棕描边。
## 结构：①纯函数段（stacked_layout/title_box/corners_in_ellipse/端点校验/常量/透明度）；
## ②场景段（钉设计视口 1152×648——headless expand 坑，一切布局绝对值断言先钉再断）。
const MM_GD := "res://scenes/menu/main_menu.gd"
const WM_GD := "res://scripts/window_manager.gd"
# 设计视口与 M-B 定参（与实现 main_menu.gd 常量同源；rx440/ry324=拍板 #5 暂定档）
const W := 1152.0; const H := 648.0
const RX := 440.0; const RY := 324.0
const BTN_W := 200.0; const BTN_H := 56.0
const COL_X := 0.42 * 440.0          # 按钮列水平中心 = 0.42*rx = 184.8
const BAND_TOP := 0.32 * 648.0       # y 带上缘 207.36
const BAND_BOTTOM := 0.78 * 648.0    # y 带下缘 505.44
const TITLE_GAP := 24.0              # 标题底边距带顶

## shader sd_ellipse 的 GDScript 等价复算（端点校验用，不含钳制——端点 d≈0 远离钳制平台）
func _sd_ellipse_ref(p: Vector2, c: Vector2, ab: Vector2) -> float:
	var q := (p - c) / ab
	return (q.length() - 1.0) * ab.x * ab.y \
		/ maxf(Vector2(ab.y * q.x, ab.x * q.y).length(), 1e-4)

func _initialize() -> void:
	print("== test_menu_ellipse ==")
	# 红灯防挂死 guard（L-B 先例延续）：--script 模式 _initialize 内运行时报错会中断执行
	# → 先经 has_method/get_script_constant_map 判定 M-B 未实现符号，命中记一条红立即退出。
	var mm: GDScript = load(MM_GD)
	if mm == null or not mm.has_method("stacked_layout") \
			or not mm.get_script_constant_map().has("ELLIPSE_RX") \
			or not mm.get_script_constant_map().has("ARC_COLOR_DARK"):
		check(false, "M-B：红灯 guard——main_menu.gd 缺 stacked_layout/ELLIPSE_RX/ARC_COLOR_*（M-B 实现前预期红）")
		finish()
		return
	_sec_constants(mm)
	_sec_layout_math(mm)
	await _sec_scene(mm)  # 内含 await process_frame，必须 await（否则 finish 提前）
	finish()

# ---- ⓪ 常量与透明度（拍板 #5 440/324、钮 200×56、70% 不透明） ----
func _sec_constants(mm: GDScript) -> void:
	var cmap: Dictionary = mm.get_script_constant_map()
	check_eq(cmap["ELLIPSE_RX"], 440.0, "M-B：常量 ELLIPSE_RX==440（弧顶深度拍板 #5 暂定档）")
	check_eq(cmap["ELLIPSE_RY"], 324.0, "M-B：常量 ELLIPSE_RY==324（设计视口参考值=H/2；运行时 ry 恒由容器实际高×0.5 推导）")
	check_eq(cmap["BTN_W"], 200.0, "M-B：BTN_W==200（拍板 #7 加大，原 160，M 批等价替换）")
	check_eq(cmap["BTN_H"], 56.0, "M-B：BTN_H==56（拍板 #7 加大，原 52，M 批等价替换）")
	# α 用容差断言（Color float32 精度：0.70 存为 0.6999999880，== 比较假红）
	check(absf((cmap["ARC_COLOR_DARK"] as Color).a - 0.70) < 0.001,
		"M-B：ARC_COLOR_DARK α==0.70（70% 不透明拍板，原 0.68 等价替换；容差断言防 float32 假红）")
	check(not cmap.has("ARC_COLOR_LIGHT"),
		"AB-3 反向锁：ARC_COLOR_LIGHT 浅档常量随深浅主题机制删除退役（无复辟）")
	# N5（2026-09-09 用户反馈：圆弧调深棕）：RGB 调深精确档断言（N 批等价替换留痕：M-B 金褐
	# (0.55,0.42,0.16)/(0.96,0.86,0.60)→深棕 (0.30,0.20,0.10)/暖棕褐 (0.72,0.60,0.35)；α 不变仍 0.70）。
	# α 语义核实（N5 读码结论）：StyleBox bg_color.a=0.70 → ui_material 容器档 col.a 仅乘
	# smoothstep(1.5,-1.5,d)（椭圆内部恒 1.0，α 全额保留）→ 渲染即 70% 实/30% 透出背景。
	var acd: Color = cmap["ARC_COLOR_DARK"] as Color
	check(absf(acd.r - 0.30) < 0.004 and absf(acd.g - 0.20) < 0.004 and absf(acd.b - 0.10) < 0.004,
		"N5：ARC_COLOR_DARK RGB==深棕 (0.30,0.20,0.10)（M-B 金褐 0.55/0.42/0.16 调深，N 批等价替换）")
	# N5 浅档 RGB 断言随批次 AB-3 退役；深档唯一真值已在上一条锁（ARC_COLOR_DARK）。
	check(cmap.has("ARC_COLOR_DARK"), "AB-3：ARC_COLOR_DARK 为弧形色唯一真值")
	check(not cmap.has("PAD_ARC") and not cmap.has("Y_TOP") and not cmap.has("Y_BOT_MARGIN"),
		"M-B：贴弧布局专用常量（PAD_ARC/Y_TOP/Y_BOT_MARGIN）已随 arc_layout 废止删除")

# ---- ① 纯函数段：stacked_layout + title_box + corners_in_ellipse + 端点校验 ----
func _sec_layout_math(mm: GDScript) -> void:
	check(mm.has_method("stacked_layout"), "M-B：main_menu.gd 提供 stacked_layout 纯函数（M 批等价替换原 arc_layout）")
	check(not mm.has_method("arc_layout"), "M-B：arc_layout 贴弧算法已废止删除（M 批等价替换留痕）")
	var centers: Array = mm.stacked_layout(W, H, BTN_W, BTN_H, 3)
	check_eq(centers.size(), 3, "M-B：stacked_layout 返回 3 中心")
	# x 恒等 0.42*rx=184.8（拍板 #7 椭圆视觉中轴，暂定值）
	for i in 3:
		check(absf((centers[i] as Vector2).x - COL_X) <= 0.5,
			"M-B：钮%d 列中心 x=%.1f==0.42*rx=%.1f（恒等，容差 0.5）" % [i + 1, (centers[i] as Vector2).x, COL_X])
	# 垂直等间隙（≤0.5px）+ 间隙值=带高/n（防参数漂移）
	var dy01: float = (centers[1] as Vector2).y - (centers[0] as Vector2).y
	var dy12: float = (centers[2] as Vector2).y - (centers[1] as Vector2).y
	check(absf(dy01 - dy12) <= 0.5, "M-B：三钮 y 间隙相等（%.3f/%.3f，差 ≤0.5px，M 批等价替换原等 y 155/155 断言）" % [dy01, dy12])
	var gap_expect: float = (BAND_BOTTOM - BAND_TOP) / 3.0
	check(absf(dy01 - gap_expect) <= 0.5, "M-B：间隙值=%.2f==带高/n=%.2f（[0.32H,0.78H] 带内均布推导，防参数漂移）" % [dy01, gap_expect])
	# 整组对 H/2 居中（≤0.5px）
	var group_cy: float = ((centers[0] as Vector2).y + (centers[2] as Vector2).y) * 0.5
	check(absf(group_cy - H * 0.5) <= 0.5, "M-B：整组中心 y=%.2f==H/2=%.1f（垂直居中，容差 0.5px）" % [group_cy, H * 0.5])
	# 带内（[0.32H, 0.78H]）
	var in_band := true
	for c: Vector2 in centers:
		if c.y < BAND_TOP - 0.5 or c.y > BAND_BOTTOM + 0.5: in_band = false
	check(in_band, "M-B：三钮 y 中心全部落在 [0.32H,0.78H]=[%.1f,%.1f] 带内" % [BAND_TOP, BAND_BOTTOM])
	# title_box 纯函数：底边=带顶-24、水平中心=0.42*rx
	var tbox: Rect2 = mm.title_box(H, 240.0, 84.0)
	check(absf((tbox.position.y + tbox.size.y) - (BAND_TOP - TITLE_GAP)) <= 0.5,
		"M-B：title_box 底边=%.1f==带顶-24=%.1f（标题置于带上方 ≥24px）" % [tbox.position.y + tbox.size.y, BAND_TOP - TITLE_GAP])
	check(absf(tbox.get_center().x - COL_X) <= 0.5, "M-B：title_box 水平中心==0.42*rx（与按钮列同轴）")
	# corners_in_ellipse 行为双用例（全内部 true / 明显越界 false）
	var inner: Array[Rect2] = [Rect2(COL_X - 100.0, H * 0.5 - 20.0, 200.0, 40.0)]
	check(bool(mm.corners_in_ellipse(inner, H, RX, RY)), "M-B：corners_in_ellipse 全内部盒→true")
	var outside: Array[Rect2] = [Rect2(RX + 10.0, H * 0.5 - 20.0, 40.0, 40.0)]
	check(not bool(mm.corners_in_ellipse(outside, H, RX, RY)), "M-B：corners_in_ellipse 弧外盒（x>rx）→false")
	# 端点校验（验收标准 2）：弧线在 y=0 与 y=H 处 x=0——sd_ellipse 端点 d≈0（容差 1.5px）
	check(absf(_sd_ellipse_ref(Vector2(0, 0), Vector2(0, RY), Vector2(RX, RY))) <= 1.5,
		"M-B：弧线端点 (0,0) 处 sd_ellipse≈0（端点严格顶满左上角，容差 1.5px）")
	check(absf(_sd_ellipse_ref(Vector2(0, H), Vector2(0, RY), Vector2(RX, RY))) <= 1.5,
		"M-B：弧线端点 (0,H) 处 sd_ellipse≈0（端点严格顶满左下角，容差 1.5px）")
	check(absf(_sd_ellipse_ref(Vector2(RX, RY), Vector2(0, RY), Vector2(RX, RY))) <= 1.5,
		"M-B：弧顶 (rx,H/2)=(440,324) 处 sd_ellipse≈0（右半支最深点=rx）")
	# 左贴弧参考系真值：端点 (0,0) 归一化半径恰为 1（形状数学锚，防参考系写错）
	var u0 := 0.0 / RX; var v0 := (0.0 - H * 0.5) / RY
	check(absf(u0 * u0 + v0 * v0 - 1.0) <= 0.001, "M-B：端点 (0,0) u²+v²==1（左贴弧参考系锚真值，弧心 (0,H/2)）")

# ---- ② 场景段（钉设计视口 1152×648，headless expand 坑先例照抄 L-D 版写法） ----
func _sec_scene(mm: GDScript) -> void:
	var container: Control = Control.new()
	container.size = Vector2(W, H)  # 显式钉设计视口（不 PRESET_FULL_RECT——headless expand 撑 1152×1152 坑）
	add_child(container)
	var linker: Node = load("res://scripts/ui_light_linker.gd").new()
	add_child(linker)
	var scene: PackedScene = load("res://scenes/menu/main_menu.tscn") as PackedScene
	var mn: Node = scene.instantiate()
	container.add_child(mn)
	await process_frame
	await process_frame
	await process_frame
	var lp: Control = mn.get_node_or_null("LeftPanel") as Control
	check(lp != null and absf(lp.anchor_right - 0.42) < 0.001,
		"M-B：LeftPanel anchor_right==0.42（宽 483.8≥弧顶+AA 余量，原 0.34，M 批等价替换）")
	check(lp != null and absf(lp.size.x - W * 0.42) <= 0.5,
		"M-B：LeftPanel 实宽=%.1f==0.42*1152（≥rx440+AA，弧线完整绘制空间）" % (lp.size.x if lp != null else 0.0))
	# 三钮尺寸（拍板 #7 加大）
	var btns: Array[Button] = []
	for nm: String in ["StartButton", "LoadButton", "QuitButton"]:
		var b: Button = mn.get_node_or_null("LeftPanel/" + nm) as Button
		check(b != null and b.custom_minimum_size == Vector2(BTN_W, BTN_H),
			"M-B：%s custom_minimum_size==(200,56)（拍板 #7，原 160×52，M 批等价替换）" % nm)
		if b != null: btns.append(b)
	check_eq(btns.size(), 3, "M-B：三钮齐全")
	# 运行时布局 == stacked_layout（resized 联动）+ 间隙/居中/带内（实际尺寸复算）
	if lp != null and btns.size() == 3 and lp.size.x > 0.0:
		var hh := lp.size.y
		var centers: Array = mm.stacked_layout(lp.size.x, hh, BTN_W, BTN_H, 3)
		for i in 3:
			var bc: Vector2 = btns[i].position + Vector2(BTN_W, BTN_H) * 0.5
			check(bc.distance_to(centers[i]) <= 1.0, "M-B：运行时钮%d 中心==stacked_layout(实际尺寸)（resized 联动）" % (i + 1))
		var dy01: float = (centers[1] as Vector2).y - (centers[0] as Vector2).y
		var dy12: float = (centers[2] as Vector2).y - (centers[1] as Vector2).y
		check(absf(dy01 - dy12) <= 0.5, "M-B：运行时三钮 y 间隙相等（实际布局，≤0.5px）")
		var gc: float = ((centers[0] as Vector2).y + (centers[2] as Vector2).y) * 0.5
		check(absf(gc - hh * 0.5) <= 0.5, "M-B：运行时整组中心 y==H/2（实际布局）")
	# 标题重摆（spec §3.2-6）
	var tl: Label = mn.get_node_or_null("LeftPanel/Title") as Label
	check(tl != null and not tl.clip_text, "M-B：标题 clip_text==false（保留，不再硬裁切）")
	if tl != null and lp != null and lp.size.x > 0.0:
		var hh := lp.size.y
		var fs: int = tl.get_theme_font_size("font_size")
		check(fs <= 64, "M-B：标题字号 %d≤64（64 起步档，M 批等价替换原 40 断言）" % fs)
		check((64 - fs) % 4 == 0, "M-B：标题字号降档步长 4px（64-%d 为 4 的倍数，校验即权威）" % fs)
		check(tl.has_theme_constant("outline_size") or tl.get_theme_constant("outline_size") > 0,
			"M-B：标题描边 outline_size override 生效")
		check_eq(tl.get_theme_constant("outline_size"), 10, "M-B：标题 outline_size==10（深墨棕描边暂定档）")
		var oc := tl.get_theme_color("font_outline_color")
		check(oc != null and oc.r < 0.2 and oc.g < 0.15 and oc.b < 0.1,
			"M-B：标题描边色为深墨棕（r<0.2/g<0.15/b<0.1）")
		var tfont: Font = tl.get_theme_font("font")
		var tw := tfont.get_string_size(tl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var lh := tfont.get_height(fs)
		var tbox: Rect2 = mm.title_box(hh, tw, lh)
		check(absf(tl.position.x + tl.size.x * 0.5 - COL_X) <= 1.0,
			"M-B：运行时标题水平中心==0.42*rx（与按钮列同轴，容差 1px）")
		check(absf(tl.position.y + tl.size.y - (hh * 0.32 - TITLE_GAP)) <= 1.0,
			"M-B：运行时标题底边==带顶-24（容差 1px）")
		check(tl.position.y >= 0.0, "M-B：标题盒顶 ≥0（不出屏）")
		# 16 角点（标题 4+三钮 12）复算 + 实现校验函数直调（验收标准 1）
		var rects: Array[Rect2] = [tbox]
		var centers: Array = mm.stacked_layout(lp.size.x, hh, BTN_W, BTN_H, 3)
		for c: Vector2 in centers:
			rects.append(Rect2(c - Vector2(BTN_W, BTN_H) * 0.5, Vector2(BTN_W, BTN_H)))
		var worst := 0.0
		for r: Rect2 in rects:
			for corner: Vector2 in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
				var u := corner.x / RX
				var v := (corner.y - hh * 0.5) / (hh * 0.5)
				worst = maxf(worst, u * u + v * v)
		check(worst <= 0.99, "M-B：16 角点最紧 u²+v²=%.4f ≤0.99（标题 4+三钮 12，校验即权威）" % worst)
		check_eq(bool(mn.call("_check_layout_corners_in_ellipse")), true, "M-B：_check_layout_corners_in_ellipse() 直调返回 true（16 角点全入内缩椭圆）")
	# EllipsePanel meta + 面板材质 u_ellipse（左贴弧口径，验收标准 2）
	var ep: Panel = mn.get_node_or_null("LeftPanel/EllipsePanel") as Panel
	check(ep != null, "M-B：EllipsePanel 容器存在")
	if ep != null:
		check_eq(str(ep.get_meta("ellipse_params")), str(Vector2(RX, RY)),
			"M-B：EllipsePanel meta ellipse_params==(440,324)（一处定参；ry 分量=设计视口半高）")
		check_eq(str(ep.get_meta("glow_mask")), "ellipse", "M-B：meta glow_mask==ellipse（容器档掩码，保留）")
		check_eq(str(ep.get_meta("ui_material")), "panel", "M-B：meta ui_material==panel（面板档材质，保留）")
		var asb: StyleBoxFlat = ep.get_theme_stylebox("panel") as StyleBoxFlat
		check(asb != null and absf(asb.bg_color.a - 0.70) < 0.001,
			"M-B：容器 StyleBox α==0.70（70% 不透明，M 批等价替换原 [0.60,0.70] 档断言）")
		check(asb != null and asb.corner_radius_top_right == 0 and asb.border_width_top == 0 and asb.shadow_size == 0,
			"M-B：StyleBox 圆角/边框/阴影归零（形状由材质 SDF 承担，保留）")
		if ep.material is ShaderMaterial:
			var pm: ShaderMaterial = ep.material
			check_eq(pm.get_shader_parameter("u_ellipse"), Vector4(0.0, RY, RX, RY),
				"M-B：面板材质 u_ellipse==(0,H/2,440,H/2)（左贴弧口径，M 批等价替换原 (W-rx,H/2,380,280)）")
			check_eq(int(pm.get_shader_parameter("u_ellipse_use")), 1, "M-B：u_ellipse_use=1（D 形 SDF 裁剪生效，保留）")
	var qb: Button = mn.get_node_or_null("LeftPanel/QuitButton") as Button
	check(qb != null and float(qb.get_meta("glow_max")) == 0.30, "M-B：quit_btn meta glow_max==0.30（退出钮档，保留）")
	# window_manager 椭圆掩码同口径（验收标准 2：linker 与 window_manager 两处同值）
	var wm: GDScript = load(WM_GD)
	check_eq(wm.ELLIPSE_DEFAULT, Vector2(RX, RY), "M-B：wm.ELLIPSE_DEFAULT==(440,324)（meta 缺省同值，M 批等价替换原 (380,280)）")
	if ep != null:
		var gtp: Dictionary = wm.glow_targets_for(ep)
		# hover_glow 修复批（2026-09-18 追加）：_push 产出改设备系——期望=content 恒量
		# (0,RY,RX,RY) 经同一视口拉伸映射（与 coord_space.gd 头注 3 口径一致）。
		var sxf_me: Transform2D = ep.get_viewport().get_screen_transform()
		var want_ell_me: Vector4 = Vector4((sxf_me * Vector2(0.0, RY)).x, (sxf_me * Vector2(0.0, RY)).y,
			RX * sxf_me.get_scale().x, RY * sxf_me.get_scale().y)
		if (gtp["ellipses"] as Array).size() > 0:
			var e0: Vector4 = gtp["ellipses"][0]
			# ep 铺满 LeftPanel（container 在 root 原点）→ 全局左缘 x=0、全局中心 y=324（content）
			check_eq(e0, want_ell_me,
				"M-B+修复批：wm 掩码 ellipse==(设备左缘,设备中心y,440×sx,H/2×sy)（左贴弧口径设备化）")
		var gtq: Dictionary = wm.glow_targets_for(qb)
		if (gtq["ellipses"] as Array).size() > 1:
			var e1: Vector4 = gtq["ellipses"][1]
			check_eq(e1, want_ell_me, "M-B+修复批：按钮 hover 采集的容器掩码与容器自采同值（两处消费同参，设备系）")
	# ⑨ main.tscn SettingsButton（M-A 回归锚，L-B 先例保留：不入树实例断言）
	var mi: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var st: Button = mi.get_node_or_null("GlobalUI/SettingsButton") as Button
	check(st != null and st.icon == null, "M-B：SettingsButton 无图标（M-A 回归锚，保留）")
	# 批次 U-C P0 追加口径③ + v2 补偿等价替换（用户 2026-09-19 截图反馈 clearance+8px →
	# 窗相对 W−24/顶 52；二次截图反馈-v2 GlobalUI offset 归零后本地 +10 反向补偿维持窗相对）：
	# M-B 旧锚 (-124,48,-16,84) 在 U-B U10 漏改（曾预存红灯实证）→ 现按终值 (−132,52,−24,84) 锁死。
	check(st != null and absf(st.offset_left + 132.0) < 0.5 and absf(st.offset_top - 52.0) < 0.5 \
		and absf(st.offset_right + 24.0) < 0.5 and absf(st.offset_bottom - 84.0) < 0.5,
		"v2：SettingsButton 几何==(-132,52,-24,84)（M-B 旧锚/P0③ 值留痕，见上注释）")
	mi.free()
	container.queue_free()
