extends "res://tests/test_base.gd"
## 深色主题唯一真值护栏（批次 AB-3：用户拍板**彻底删除深浅色主题机制**）。
## 旧双主题断言（浅色可加载/覆盖/毛玻璃/字色族等）随浅色功能删除而退役（授权例外）；
## 本件改为锁三件事：
##   A) theme_light.tres 不存在、theme_dark.tres 可加载且关键控件覆盖齐全；
##   B) ThemeManager 退化为「深色 Theme 单一提供者」——无 theme_changed 信号 / 无 is_dark /
##      无 refresh / 无轮询 Timer / 无 _light_theme；current_theme()/apply_theme() 恒深；
##   C) 深色主题质感锚定（J1/J6/K-A/N12 历批深色档断言原样保留，防「删浅色顺带动深色」）。

func _initialize() -> void:
	print("== test_theme（批次 AB-3：深色唯一真值护栏） ==")
	# ---------- A) 资源域：浅色退役、深色在位 ----------
	var dark: Theme = load("res://themes/theme_dark.tres")
	check(dark != null, "深色主题可加载")
	check(not ResourceLoader.exists("res://themes/theme_light.tres"),
		"AB-3：theme_light.tres 已删除（浅色调色板退役）")

	# 关键控件类型在深色主题下覆盖齐全（按钮/面板/滑条/标签/进度条/复选框）
	var types: Array[String] = ["Button", "Panel", "HSlider", "Label", "ProgressBar", "CheckBox"]
	for t: String in types:
		var d_cov: bool = dark.has_stylebox("normal", t) or dark.has_stylebox("slider", t) \
			or dark.has_stylebox("grabber_area", t) or dark.has_color("font_color", t) or dark.has_font("font", t)
		check(d_cov, "深色主题覆盖类型 %s" % t)

	# ---------- B) ThemeManager 退化契约（先红：旧实现仍带信号/轮询/浅档） ----------
	var tm: Node = load("res://autoload/theme_manager.gd").new()
	tm.name = "ThemeManagerAB3Probe"
	get_root().add_child(tm)
	var fake_root: Control = Control.new()
	get_root().add_child(fake_root)
	await process_frame
	tm.apply_theme(fake_root)
	check(fake_root.theme != null, "apply_theme 已赋主题")
	check(fake_root.theme == load("res://themes/theme_dark.tres"), "AB-3：apply_theme 恒赋深色主题")
	var script: Script = tm.get_script() as Script
	var methods: Array = []
	for m: Dictionary in script.get_script_method_list():
		methods.append(String(m.get("name")))
	check(not methods.has("is_dark"), "AB-3：ThemeManager 无 is_dark（系统深浅探测退役）")
	check(not methods.has("refresh"), "AB-3：ThemeManager 无 refresh（主题切换入口退役）")
	check(not script.get_script_property_list().any(
		func(p: Dictionary) -> bool: return String(p.get("name")) == "_light_theme"),
		"AB-3：ThemeManager 无 _light_theme（浅色 Theme 缓存退役）")
	check(not script.get_script_property_list().any(
		func(p: Dictionary) -> bool: return String(p.get("name")) == "_poll_timer"),
		"AB-3：ThemeManager 无 _poll_timer（跟随系统轮询装置退役）")
	var has_signal_theme_changed := false
	for s: Dictionary in script.get_script_signal_list():
		if String(s.get("name")) == "theme_changed":
			has_signal_theme_changed = true
	check(not has_signal_theme_changed, "AB-3：ThemeManager 无 theme_changed 信号（切换广播退役）")
	check(tm.call("current_theme") == load("res://themes/theme_dark.tres"),
		"AB-3：current_theme() 恒等于 theme_dark.tres")
	tm.queue_free()
	fake_root.queue_free()

	# ---------- C) 深色质感锚定（J1-1/J6/K-A/N12 深色档断言保留） ----------
	# J1-1/J6-P1-2：开源字体 NotoSansSC[wght].ttf 经 FontVariation 锁 400（「回」字护栏同批保留）
	const WGHT_TAG := 2003265652  # 'wght' 四字符 tag 大端打包为 int
	var df: Font = dark.default_font
	check(df is FontVariation, "深色主题 default_font 为 FontVariation（P1-A 锁字重）")
	if df is FontVariation:
		var fv: FontVariation = df as FontVariation
		var bf: Font = fv.base_font
		check(bf != null and String(bf.resource_path).ends_with("NotoSansSC[wght].ttf"),
			"深色主题 default_font base=NotoSansSC")
		check_eq(float(fv.variation_opentype.get(WGHT_TAG, 0.0)), 400.0,
			"深色主题 default_font wght=400（variation_opentype）")
	if dark.default_font != null:
		var ok_chars: bool = true
		for c: String in "回图设榫商店图鉴新游戏载入存档锐眼对接退出":
			if not dark.default_font.has_char(c.unicode_at(0)):
				ok_chars = false
		check(ok_chars, "J6-P1-2：default_font 覆盖「回」等 UI 高频字")

	# J1-2：毛玻璃近似（Panel/PanelContainer/Button 深色档）
	var d_panel: StyleBoxFlat = dark.get_stylebox("panel", "Panel")
	check(d_panel.bg_color.a < 0.9, "深色 Panel 底色半透明（毛玻璃近似）")
	check(d_panel.shadow_size >= 8, "深色 Panel 带柔投影")
	check(d_panel.border_width_top >= 1, "深色 Panel 带高光渐变边")
	for st: String in ["normal", "hover", "pressed"]:
		var dbs: StyleBoxFlat = dark.get_stylebox(st, "Button")
		check(dbs.bg_color.a < 0.9 and dbs.shadow_size > 0, "深色 Button %s 毛玻璃（半透明+投影）" % st)
	var d_dis: StyleBoxFlat = dark.get_stylebox("disabled", "Button")
	check(d_dis.shadow_size == 0, "K-A：深色 Button disabled 无阴影")
	var d_pc: StyleBoxFlat = dark.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	check(d_pc != null and d_pc.bg_color.a < 0.9, "深色主题 PanelContainer 半透明样式已定义")

	# N12/K-A：深色常态字色米黄浅金 + 禁用字色同族（原深色档断言保留）
	var nc: Color = dark.get_color("font_color", "Button")
	check(absf(nc.r - 0.96) < 0.003 and absf(nc.g - 0.90) < 0.003 and absf(nc.b - 0.78) < 0.003,
		"N12：深色 Button 常态字色=米黄浅金 (0.96,0.90,0.78)")
	var d_fc: Color = dark.get_color("font_disabled_color", "Button")
	check(absf(d_fc.r - 0.96) < 0.003 and absf(d_fc.g - 0.90) < 0.003 and absf(d_fc.b - 0.78) < 0.003 \
		and absf(d_fc.a - 0.80) < 0.01, "N12：深色 font_disabled_color=米黄浅金 α0.80")
	check(absf(d_dis.bg_color.a - 0.45) < 0.01, "M-A：深色禁用底 α0.45")
	# K-A：圆角/方向影/按压反馈（深色档）
	var nb: StyleBoxFlat = dark.get_stylebox("normal", "Button") as StyleBoxFlat
	check_eq(nb.corner_radius_top_left, 12, "M-A：深色 Button normal 圆角 12")
	check_eq(nb.shadow_offset, Vector2(3, 5), "K-A：深色 Button normal 方向阴影 (3,5)")
	var pb: StyleBoxFlat = dark.get_stylebox("pressed", "Button") as StyleBoxFlat
	check_eq(pb.shadow_offset, Vector2(0, 1), "K-A：深色 Button pressed 按压 offset (0,1)")
	check_eq(pb.shadow_size, 6, "K-A：深色 Button pressed 按压 size 6")
	# K-A：L1 面板毛玻璃（深色档）
	for node_type: String in ["Panel", "PanelContainer"]:
		var sp: StyleBoxFlat = dark.get_stylebox("panel", node_type) as StyleBoxFlat
		if sp != null:
			check(sp.bg_color.a > 0.4 and sp.bg_color.a < 0.7, "K-A：深色 %s 毛玻璃底 alpha∈(0.4,0.7)" % node_type)
			check_eq(sp.border_width_top, 2, "K-A：深色 %s 顶缘高光边 2px" % node_type)
			check_eq(sp.corner_radius_top_left, 16, "K-A：深色 %s 圆角 16" % node_type)
			check_eq(sp.shadow_size, 16, "K-A：深色 %s 面板柔投影 16" % node_type)
	finish()
