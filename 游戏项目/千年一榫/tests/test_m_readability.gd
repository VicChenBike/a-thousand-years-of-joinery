extends "res://tests/test_base.gd"
## M-A（批次 M spec §3.1，2026-09-07）：全局可读性 + 图标清理判定用例（TDD 先红后绿）。
## 契约（spec §3.1 验收标准 1/2 + §4.1 色值口径 + §4.2 图标清理清单）：
##   ① 7 处按钮图标清零：main_menu StartButton(icon_01)/LoadButton(icon_02)、
##     level_scene EyeButton(icon_10)/JoinButton(icon_09)/ExitButton(icon_06)、
##     settings_panel CatalogEntry(icon_05)/ShopEntry(icon_04)——设置页两处
##     TextureButton 改普通 Button（文字「图鉴」「商店」并入，删除旁挂 Label，
##     路由回调零改动）；三 tscn 内 ui_icons ext_resource 引用为 0（目录保留不删）。
##   ② 主题禁用态收敛（暂定值）：深 font_disabled_color=Color(0.96,0.90,0.78,0.80)
##     （N12：原 M-A 深墨棕 (0.102,0.071,0.031,0.80) 与 N5 深棕底撞色，随字色方案反转留痕）、
##     浅 Color(0.227,0.165,0.063,0.60)；禁用底色 α 深 0.45/浅 0.40（保持金色相）；
##     按钮文字深色主题=米黄浅金浅字（N12）、浅色主题=深棕常显色、禁用仅降透明度；按钮圆角 10→12。
##   ③ 窗口三钮字形色接口：深米黄浅金 (0.96,0.90,0.78)/浅深棕（N12：随主题按钮字色方案）、
##     随 theme_changed 刷新；三钮底色与 N5 按钮深棕档对齐（N12-2）。
##   ④ 立体微修：shader rim 0.35→0.20、linker THEME_PARAMS u_frost 深 0.04/浅 0.035。
##   ⑤ 设置页双入口 pressed 路由不报错（Game.attach + open_overlay 轻量路由）。
## 已知坑遵循（spec §六）：headless expand 伪象（本测试不依赖布局尺寸）；跨脚本常量
## 一律 load().get() 判空 guard（坑 7）；CanvasLayer 主题不传播（坑 11，三钮显式接线）。

const TSCN_MENU := "res://scenes/menu/main_menu.tscn"
const TSCN_LEVEL := "res://scenes/level/level_scene.tscn"
const TSCN_SETTINGS := "res://scenes/settings/settings_panel.tscn"
const ST_CATALOG := 6

func _color_close(a: Color, b: Color, tol: float = 0.004) -> bool:
	return absf(a.r - b.r) < tol and absf(a.g - b.g) < tol and absf(a.b - b.b) < tol and absf(a.a - b.a) < tol

func _initialize() -> void:
	print("== test_m_readability ==")
	_sec_icons_scene_text()
	await _sec_icons_instances()
	_sec_theme_disabled()
	await _sec_window_buttons_glyph()
	_sec_shader_linker()
	await _sec_settings_route()
	finish()

## ①-1 三个 tscn 源文本 ui_icons 引用清零（ext_resource 与 icon=/texture_normal= 残留一并防）
func _sec_icons_scene_text() -> void:
	for pair: Array in [["main_menu.tscn", TSCN_MENU], ["level_scene.tscn", TSCN_LEVEL], ["settings_panel.tscn", TSCN_SETTINGS]]:
		var src := FileAccess.get_file_as_string(String(pair[1]))
		check(src.length() > 0, "M-A①：%s 可读" % pair[0])
		check(not src.contains("ui_icons"), "M-A①：%s 内 ui_icons ext_resource 引用为 0（图标清单 §4.2）" % pair[0])
	var src_set := FileAccess.get_file_as_string(TSCN_SETTINGS)
	check(not src_set.contains("TextureButton") and not src_set.contains("texture_normal"),
		"M-A①：settings_panel.tscn 无 TextureButton/texture_normal 残留（入口改普通 Button）")

## ①-2 实例断言：7 处按钮 icon==null / 设置页双入口为 Button
func _sec_icons_instances() -> void:
	var menu: Node = (load(TSCN_MENU) as PackedScene).instantiate()
	check(menu != null, "M-A①：main_menu.tscn 实例化成功（无悬空 ext_resource）")
	if menu != null:
		for n: String in ["StartButton", "LoadButton"]:
			var b: Button = menu.get_node_or_null("LeftPanel/" + n) as Button
			check(b != null and b.icon == null, "M-A①：%s icon==null（图标已删，按钮与功能保留）" % n)
		menu.free()
	var level: Node = (load(TSCN_LEVEL) as PackedScene).instantiate()
	check(level != null, "M-A①：level_scene.tscn 实例化成功（无悬空 ext_resource）")
	if level != null:
		for n: String in ["EyeButton", "JoinButton", "ExitButton"]:
			var b: Button = level.get_node_or_null("TopBar/Buttons/" + n) as Button
			check(b != null and b.icon == null, "M-A①：%s icon==null（顶栏图标已删）" % n)
		level.free()
	var st: Node = (load(TSCN_SETTINGS) as PackedScene).instantiate()
	check(st != null, "M-A①：settings_panel.tscn 实例化成功（无悬空 ext_resource）")
	if st != null:
		# 批次 AC 4A（spec §4.9，2026-09-27 用户追加需求）：商店改名「衣橱」——旧断言 "商店" 等价改写
		#（节点名 ShopEntry 与状态枚举 SHOP 不变，仅 UI 文本）。
		for pair: Array in [["CatalogEntry", "图鉴"], ["ShopEntry", "衣橱"]]:
			var p := "Panel/VBox/EntryBox/" + String(pair[0])
			var n: Node = st.get_node_or_null(p)
			var is_plain_button: bool = n is Button and not (n is TextureButton)
			var b: Button = n as Button
			check(is_plain_button, "M-A①：%s 为普通 Button（TextureButton 已改，M 批反转留痕）" % pair[0])
			check(b != null and b.icon == null and b.get("texture_normal") == null,
				"M-A①：%s 无任何贴图（icon/texture_normal 均 null）" % pair[0])
			check(b != null and String((b as Button).text) == String(pair[1]),
				"M-A①：%s 文本并入「%s」（旁挂 Label 已删）" % [pair[0], pair[1]])
			var label_name := "CatalogLabel" if String(pair[0]) == "CatalogEntry" else "ShopLabel"
			check(st.get_node_or_null("Panel/VBox/EntryBox/" + label_name) == null,
				"M-A①：旁挂 %s 已删除（文字并入按钮）" % label_name)
		st.free()

## ② 主题禁用态收敛（spec §3.1/§4.1 暂定值；批次 AB-3：浅色档断言随浅主题删除退役，深色档原样保留）
func _sec_theme_disabled() -> void:
	var dark: Theme = load("res://themes/theme_dark.tres")
	check(dark != null, "M-A②：深色主题可加载（AB-3 唯一主题）")
	if dark == null:
		return
	var d_fc: Color = dark.get_color("font_disabled_color", "Button")
	check(_color_close(d_fc, Color(0.96, 0.90, 0.78, 0.80), 0.002),
		"N12：深色 font_disabled_color=(0.96,0.90,0.78,0.80)（米黄浅金随字色方案反转；M-A 深墨棕档与 N5 深棕底撞色，N12 留痕）")
	# M-A 回修（用户验收反馈「常态金字叠金底看不清」）→ N12 二次反转（2026-09-10 用户反馈
	# 「按钮调深后字撞了看不清」）：深色常态字色四态改米黄浅金浅字压 N5 深棕底。
	for pair2: Array in [["深", dark, Color(0.96, 0.90, 0.78)]]:
		for st: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			var c2: Color = (pair2[1] as Theme).get_color(st, "Button")
			check(_color_close(Color(c2.r, c2.g, c2.b, 1.0), pair2[2], 0.002) and absf(c2.a - 1.0) < 0.01,
				"N12：%s色 Button %s=新字色方案常显口径 (%s)（M-A 深墨棕口径 N12 反转留痕）" % [pair2[0], st, str(pair2[2])])
	# 统一规则：深主题禁用字色 rgb == 常显字色 rgb（仅 α 降），防「禁用换浅色系」回归
	var d_normal: Color = dark.get_color("font_color", "Button")
	check(_color_close(Color(d_fc.r, d_fc.g, d_fc.b, d_normal.a), d_normal, 0.002),
		"M-A②：深色禁用字色与常显字色同 rgb（禁用仅降透明度）")
	# 禁用底色：深档 α=0.45（浅档 0.40/暖棕两支随批次 AB-3 浅主题删除退役）
	var d_sb: StyleBoxFlat = dark.get_stylebox("disabled", "Button") as StyleBoxFlat
	check(d_sb != null and absf(d_sb.bg_color.a - 0.45) < 0.01,
		"M-A②：深色禁用底 α=0.45（金 α0.3→0.45，N12 起深底配浅字可读对）")
	check(d_sb != null and absf(d_sb.bg_color.r - 0.38) < 0.004 and absf(d_sb.bg_color.g - 0.27) < 0.004,
		"N5：深色禁用底调深棕档 (0.38,0.27,0.10)（M-A②「保持金色相 (0.788,0.635,0.153)」断言 N 批等价替换）")
	# 按钮圆角 10→12（四态；浅主题循环支随 AB-3 退役）
	for pair: Array in [["深", dark]]:
		var label: String = pair[0]
		var th: Theme = pair[1]
		for st: String in ["normal", "hover", "pressed", "disabled"]:
			var sb: StyleBoxFlat = th.get_stylebox(st, "Button") as StyleBoxFlat
			check(sb != null and sb.corner_radius_top_left == 12,
				"M-A②：%s色 Button %s 圆角 12（10→12 暂定值）" % [label, st])

## ③ 窗口三钮字形色接口 + theme_changed 刷新（spec §3.1/§4.1；坑 11 CanvasLayer 显式接线）
func _sec_window_buttons_glyph() -> void:
	var wb_script: Script = load("res://scenes/shared/window_buttons.gd")
	check(wb_script != null, "M-A③：window_buttons.gd 可加载")
	if wb_script == null:
		return
	# 批次 AB-3：GLYPH_COLOR_DARK/LIGHT 双常量收敛为 GLYPH_COLOR 单值（深档值未变），
	# 浅档常量反向锁退役。
	var cd: Variant = wb_script.get("GLYPH_COLOR")
	check(cd is Color and _color_close(cd, Color(0.96, 0.90, 0.78), 0.002),
		"AB-3 等价改写：GLYPH_COLOR=米黄浅金 (0.96,0.90,0.78)（旧深档值不变）")
	check(wb_script.get("GLYPH_COLOR_LIGHT") == null,
		"AB-3 反向锁：GLYPH_COLOR_LIGHT 浅档常量退役（无复辟）")
	var wb: Node = (load("res://scenes/shared/window_buttons.tscn") as PackedScene).instantiate()
	add_child(wb)
	await process_frame
	check(wb.get_child_count() == 3, "M-A③：三按钮已生成")
	# 批次 AB-3：glyph_color() 收敛为无参（深档单值）；theme_changed 翻转/刷新断言随信号退役
	#——等价改写：入树三态字色恒米黄浅金 + 源内无 theme_changed 接线反向锁。
	var expect_now: Color = wb_script.call("glyph_color")
	var all_ok := wb.get_child_count() == 3
	for i: int in range(wb.get_child_count()):
		var b: Button = wb.get_child(i) as Button
		all_ok = all_ok and b != null and b.has_theme_color_override("font_color") \
			and _color_close(b.get_theme_color("font_color"), expect_now)
	check(all_ok, "M-A③：入树后三钮字形色覆写（不依赖主题传播；AB-3 恒深档单值）")
	if wb.get_child_count() == 3:
		var b0: Button = wb.get_child(0) as Button
		check(_color_close(b0.get_theme_color("font_color"), Color(0.96, 0.90, 0.78)),
			"AB-3 等价改写：三钮字形色=米黄浅金（旧深档终态值不变）")
		check(_color_close(b0.get_theme_color("font_hover_color"), Color(0.96, 0.90, 0.78)) \
			and _color_close(b0.get_theme_color("font_pressed_color"), Color(0.96, 0.90, 0.78)),
			"M-A 回修 P3-1：hover/pressed 态字形色同档覆写（消除悬停明暗反转）")
	var src := FileAccess.get_file_as_string("res://scenes/shared/window_buttons.gd")
	# 去注释行后判接线（留痕注释允许记载旧措辞；AB-3 反向锁只对代码生效）。
	var code := PackedStringArray()
	for ln: String in src.split("\n"):
		if not String(ln).strip_edges().begins_with("#"):
			code.append(ln)
	check(not "\n".join(code).contains("theme_changed"), "AB-3 反向锁：window_buttons.gd 代码行无 theme_changed 接线（机制删除）")
	wb.free()

## ④ 立体微修：shader rim 0.20 + 暗像素方向光衰减（常态字色洗白回修）+ linker u_frost 新档
func _sec_shader_linker() -> void:
	var src := FileAccess.get_file_as_string("res://assets/shaders/ui_material.gdshader")
	check(src.contains("* rim * 0.20"), "M-A④：rim 系数 0.35→0.20（受光缘亮线收敛）")
	check(not src.contains("* rim * 0.35"), "M-A④：旧 rim 0.35 无残留")
	# M-A 回修（用户验收反馈）：方向光对暗像素衰减——深墨棕文字不再被恒定 +0.48 提亮洗成灰金
	check(src.contains("lum_w"), "M-A 回修：shader 含暗像素亮度权重 lum_w（文字不受方向光洗白）")
	check(src.contains("* u_dir_energy * lum_w"),
		"M-A 回修：方向光项乘 lum_w（金底立体光保留、深字恢复本色）")
	var linker_script: Script = load("res://scripts/ui_light_linker.gd")
	var params: Variant = linker_script.get("THEME_PARAMS") if linker_script != null else null
	# 批次 AB-3：u_frost 由 [深,浅] 双档数组收敛为深档标量 0.04（值=旧深档，未变）。
	if params is Dictionary and (params as Dictionary).has("u_frost"):
		var frost: Variant = (params as Dictionary)["u_frost"]
		check(frost is float and absf(float(frost) - 0.04) < 0.001,
			"AB-3 等价改写：THEME_PARAMS u_frost=0.04（深档标量单值，旧 [0.04,0.035] 双档退役）")
	else:
		check(false, "M-A④：THEME_PARAMS.u_frost 可读（guard 失败即报告）")

## ⑤ 设置页双入口 pressed 路由不报错（TextureButton→Button 后接线保持，参照 test_settings_panel 口径）
func _sec_settings_route() -> void:
	var save: Variant = root.get_node("SaveManager")
	var game: Variant = root.get_node("Game")
	if save == null or game == null:
		check(false, "M-A⑤：SaveManager/Game autoload 缺失，路由断言不可用")
		return
	var container: Control = Control.new()
	add_child(container)
	var overlay: CanvasLayer = CanvasLayer.new()
	add_child(overlay)
	game.call("attach", container, overlay)
	await process_frame
	game.call("open_overlay", "settings")
	await process_frame
	if overlay.get_child_count() == 0:
		check(false, "M-A⑤：open_overlay('settings') 未创建覆盖层")
		return
	var panel: Node = overlay.get_child(overlay.get_child_count() - 1)
	var shop: Button = panel.get_node_or_null("Panel/VBox/EntryBox/ShopEntry") as Button
	var catalog: Button = panel.get_node_or_null("Panel/VBox/EntryBox/CatalogEntry") as Button
	check(shop != null and shop.pressed.get_connections().size() >= 1,
		"M-A⑤：ShopEntry.pressed 已连接（改 Button 后路由回调零改动）")
	check(catalog != null and catalog.pressed.get_connections().size() >= 1,
		"M-A⑤：CatalogEntry.pressed 已连接")
	var st0: int = int(game.call("current_state"))
	# 模拟点击不报错：商店入口 → 覆盖层路由（不改主状态）
	if shop != null:
		shop.pressed.emit()
		await process_frame
		check_eq(int(game.call("current_state")), st0, "M-A⑤：ShopEntry.pressed.emit() 执行无异常且不改主状态")
		check(bool(game.call("has_open_overlay")), "M-A⑤：点商店入口 → 商店覆盖层已打开")
		game.call("close_overlay")
		await process_frame
	# 图鉴入口模拟点击 → CATALOG（first_launch 置灰时 emit 仍路由，功能保留验证）
	var panel2: Node = await _reopen(game, overlay)
	var catalog2: Button = null
	if panel2 != null:
		catalog2 = panel2.get_node_or_null("Panel/VBox/EntryBox/CatalogEntry") as Button
	check(catalog2 != null, "M-A⑤：重开设置面板可达（复开路由）")
	if catalog2 != null:
		catalog2.pressed.emit()
		await process_frame
		check_eq(int(game.call("current_state")), ST_CATALOG, "M-A⑤：CatalogEntry.pressed.emit() → CATALOG 状态")
	container.queue_free()

func _reopen(game: Variant, overlay: CanvasLayer) -> Node:
	game.call("open_overlay", "settings")
	await process_frame
	if overlay.get_child_count() == 0:
		return null
	return overlay.get_child(overlay.get_child_count() - 1)
