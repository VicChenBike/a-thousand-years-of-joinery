extends "res://tests/test_base.gd"
## L-A（spec §9 L-A 行）：①ui_material 资源/关键字/默认值；②linker 挂载（启动扫描+动态）；
## ③面板档参数档位；④主题翻转；⑤主题四态归一+window_buttons 金色归黑+半透明档。
## 无头断言=属性/参数证据链；观感=窗口截图判定（LD-3 走查）。
const LM_SHADER := "res://assets/shaders/ui_material.gdshader"

func _initialize() -> void:
	print("== test_light_material ==")
	_sec_shader()
	_sec_theme_states()
	await _sec_linker()  # 内含 await process_frame，必须 await（否则 finish 提前）
	finish()

func _sec_shader() -> void:
	var sh: Shader = load(LM_SHADER) as Shader
	check(sh != null, "L7：ui_material.gdshader 可加载（无头可编译代理）")
	check(sh != null and sh.get_mode() == 1, "L7：ui_material 解析为 canvas_item（get_mode=1）")
	if sh != null:
		var src := String(sh.get_code())
		# L-D 二轮修4：第二点光改屏幕口径——u_mouse_local（局部 UV 口径，实测不可见）更名
		# u_mouse_screen（屏幕像素），配套 u_viewport_size（SCREEN_UV*u_viewport_size 还原屏幕坐标）。
		for kw: String in ["u_light_dir", "u_mouse_screen", "u_viewport_size", "u_frost",
				"u_rect_size", "u_hover", "u_dir_energy", "u_inner_shadow", "u_ellipse",
				"u_panel_mode"]:
			check(src.contains(kw), "L7：shader 源码含 %s" % kw)
		# M-C（spec §3.3，2026-09-07）：u_specular 关键词断言删除并反转留痕——镜射项
		# uniform/旗标/半程向量式全链根除（m03 射线=镜射×SDF 伪法线径向相干根因），
		# 新增正向口径断言见 test_m_cursor_glow.gd（高斯衰减/diff2 保留）。
		check(not src.contains("u_specular"),
			"M-C 删镜射（留痕反转）：原 L7 关键词 u_specular 已随镜射项删除（M 批等价替换）")
		check(src.contains("SCREEN_UV * u_viewport_size"),
			"L-D：点光坐标=SCREEN_UV*u_viewport_size（修4 屏幕口径，与 u_mouse_screen 同系）")
		check(src.contains("uniform vec2 u_viewport_size = vec2(1152.0, 648.0)"),
			"L-D：u_viewport_size uniform 默认 (1152,648)（设计视口）")
		check(not src.contains("u_mouse_local"),
			"L-D：旧 u_mouse_local 局部口径已移除（防口径残留双源）")
		check(src.contains("uniform float u_dir_energy = 0.55"), "L7：深档默认 u_dir_energy=0.55（spec §5.4）")
		check(src.contains("uniform vec2 u_light_dir = vec2(-0.85, -0.5)"), "L7：光源方向默认 (-0.85,-0.5)")
		check(src.contains("uniform float u_frost = 0.06"), "L7：磨砂默认 0.06")
		check(src.contains("const float BEVEL = 6.0"), "L7：斜面带宽 BEVEL=6")
		# ---- M-B（spec §3.2-2/3，2026-09-07）：凸块根除 + 容器档光照口径收敛 ----
		check(not src.contains("d_rect"),
			"M-B：shape_d 已删 d_rect 通高左缘窄条并集（m01 左上/左下凸块根因根除，M 批等价替换）")
		check(src.contains("is_container"),
			"M-B：容器档光照旗标 is_container 存在（伪法线衍生禁用口径，旗标等价重构无 early-return）")
		check(src.contains("flat_lit"),
			"M-B：容器档平坦受光常量项 flat_lit（法线恒 (0,0,1)×光向，删双色圆：钳制平台外环伪法线环带随禁用消失；用专属标识符防 vec3(0,0,1) 字面量假绿——Blinn 半程向量同串）")
		# M-C（2026-09-07）：spec_mask 断言反转留痕——M-B 过渡期「容器档禁镜射」旗标，
		# 本批镜射连根删（按钮档一并），旗标完成使命移除；正向口径见 test_m_cursor_glow。
		check(not src.contains("spec_mask"),
			"M-C 删镜射（留痕反转）：容器档镜射禁用旗标 spec_mask 随镜射项根除一并删除（M 批等价替换）")
		check(src.contains("uniform vec4 u_ellipse = vec4(0.0, 324.0, 440.0, 324.0)"),
			"M-B：u_ellipse uniform 缺省=左贴弧 (0,H/2,440,324)（M 批等价替换原 (11.7,324,380,280)）")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("u_dir_energy", 0.42)
	check_eq(float(mat.get_shader_parameter("u_dir_energy")), 0.42, "L7：uniform set/get 往返可写")

func _sec_theme_states() -> void:
	# ⑤ 主题四态归一（spec §5.4）：normal/hover/pressed shadow_offset==(3,5)；disabled 仅断言 size==0
	# 批次 AB-3：浅主题分支随深浅主题机制删除退役，深色档断言值逐条原样保留。
	for pair in [["深", "res://themes/theme_dark.tres"]]:
		var th: Theme = load(String(pair[1]))
		var label: String = pair[0]
		check(th != null, "L-A：%s主题可加载" % label)
		if th == null: continue
		var nb := th.get_stylebox("normal", "Button") as StyleBoxFlat
		var hb := th.get_stylebox("hover", "Button") as StyleBoxFlat
		var pb := th.get_stylebox("pressed", "Button") as StyleBoxFlat
		var db := th.get_stylebox("disabled", "Button") as StyleBoxFlat
		check(nb != null and nb.shadow_offset == Vector2(3, 5) and nb.shadow_size == 8, "L-A：%s normal (3,5)/8" % label)
		check(hb != null and hb.shadow_offset == Vector2(3, 5) and hb.shadow_size == 8, "L-A：%s hover 归一 (3,5)/8（10→8）" % label)
		# L-A（LA-3）：金色 omni 发光删除——r/b 双通道阈值（浅色旧金 (0.95,0.8,0.32) 的 b=0.32<0.4，
		# 仅 b 阈值存在假防御；r>0.9 正是旧金特征，r<0.4 正向承接方可判归黑）。
		check(hb != null and hb.shadow_color.r < 0.4 and hb.shadow_color.b < 0.4,
			"L-A：%s hover 无金色发光（r<0.4 且 b<0.4，防浅色金 b<0.4 假防御）" % label)
		check(pb != null and pb.shadow_offset == Vector2(0, 1) and pb.shadow_size == 6, "L-A：%s pressed (0,1)/6" % label)
		check(db != null and db.shadow_size == 0, "L-A：%s disabled shadow_size==0（仅断言 size）" % label)
		check(nb != null and absf(nb.bg_color.a - 0.55) < 0.01, "L-A：%s normal alpha 0.55" % label)
		check(hb != null and absf(hb.bg_color.a - 0.85) < 0.01, "L-A：%s hover alpha 0.85" % label)
		check(db != null and absf(db.bg_color.a - 0.45) < 0.01,
			"M-A：%s disabled 底色 α 新档（深 0.45，L-A 0.3 等价替换；AB-3 浅档 0.40 退役）" % label)
		# N5（2026-09-09 用户反馈：按钮全部调深）：normal 底色精确档断言（N 批等价替换原 L-A
		# 「浅 r>0.9/深 r<0.9」亮金防串档口径）——深 (0.38,0.27,0.10) 深棕/浅 (0.72,0.55,0.08) 暖棕，
		# 深浅分档防串档意图保留：深 normal 明度 < 浅 normal 明度（见循环尾 d_nb/l_nb 对比断言）。
		if nb != null:
			check(absf(nb.bg_color.r - 0.38) < 0.004 and absf(nb.bg_color.g - 0.27) < 0.004 and absf(nb.bg_color.b - 0.10) < 0.004,
				"N5：深 normal 底==深棕 (0.38,0.27,0.10)（暗金 0.788/0.635/0.153 调深，N 批等价替换原 r<0.9 断言）")
		# N5：hover/pressed/disabled 底色 RGB 同步调深（α 档断言上/下条不变，M-A 金色相 RGB 档 N 批等价替换）
		if hb != null:
			check(absf(hb.bg_color.r - 0.34) < 0.004 and absf(hb.bg_color.g - 0.24) < 0.004 and absf(hb.bg_color.b - 0.09) < 0.004,
				"N5：深 hover 底==深棕 (0.34,0.24,0.09)（原暗金 0.709/0.572/0.138 调深，N 批等价替换）")
		if pb != null:
			check(absf(pb.bg_color.r - 0.38) < 0.004 and absf(pb.bg_color.g - 0.27) < 0.004 and absf(pb.bg_color.b - 0.10) < 0.004,
				"N5：深 pressed 底==深棕 (0.38,0.27,0.10)（原暗金 0.788/0.635/0.153 调深，N 批等价替换）")
		if db != null:
			check(absf(db.bg_color.r - 0.38) < 0.004 and absf(db.bg_color.g - 0.27) < 0.004 and absf(db.bg_color.b - 0.10) < 0.004,
				"N5：深 disabled 底==深棕 (0.38,0.27,0.10)（原暗金调深，N 批等价替换）")
	# N5「深浅分档防串档」对照断言随批次 AB-3 浅色主题删除退役——等价改写：深 normal 底明度
	# 阈值锚定（Rec.601 加权 <0.35 暗档，旧深档值不变）+ theme_light.tres 退役留痕。
	var d_nb: StyleBoxFlat = (load("res://themes/theme_dark.tres") as Theme).get_stylebox("normal", "Button") as StyleBoxFlat
	var _lum := func(c: Color) -> float: return c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	check(d_nb != null and _lum.call(d_nb.bg_color) < 0.35,
		"AB-3 等价改写：深 normal 底明度 <0.35（暗档锚定，旧深浅对照断言随浅档退役）")
	check(not ResourceLoader.exists("res://themes/theme_light.tres"),
		"AB-3：theme_light.tres 退役留痕（浅档无复辟）")
	var wb: Node = load("res://scenes/shared/window_buttons.gd").new()
	var sn: StyleBoxFlat = wb._small_sb(false, false)
	var sh2: StyleBoxFlat = wb._small_sb(true, false)
	var sp: StyleBoxFlat = wb._small_sb(false, true)
	check(sn != null and sn.shadow_offset == Vector2(3, 5) and sn.shadow_size == 4, "L-A：窗口钮 normal (3,5)/4（(2,3) 归一）")
	check(sh2 != null and sh2.shadow_offset == Vector2(3, 5) and sh2.shadow_size == 6, "L-A：窗口钮 hover (3,5)/6")
	check(sh2 != null and sh2.shadow_color.r < 0.4 and sh2.shadow_color.b < 0.4, "L-A：窗口钮 hover 金色归黑（r<0.4 且 b<0.4）")
	check(sp != null and sp.shadow_offset == Vector2(0, 1) and sp.shadow_size == 3, "L-A：窗口钮 pressed (0,1)/3 小元素例外档")
	# N12-2（2026-09-10 用户反馈：窗口三钮还是以前的色）：三钮底色与 N5 主题按钮深棕档对齐
	#（M-A 亮金 (0.788,0.635,0.153) 底 N12 等价替换留痕）；α 档沿用
	# normal 0.55 / hover·pressed 0.85（与主题 Button 四态 α 档同构，L-A 原断言不变）。
	# 批次 AB-3：_is_dark 档位成员与浅档分支随深浅主题机制删除退役——深档为唯一真值，
	# 反向锁：_is_dark 成员不得复辟。
	check(not (wb.get_script() as Script).get_script_property_list().any(
			func(p: Dictionary) -> bool: return String(p.get("name", "")) == "_is_dark"),
		"AB-3 反向锁：window_buttons 无 _is_dark 主题档成员（深浅切换入口退役）")
	var sn_d: StyleBoxFlat = wb._small_sb(false, false)
	var sh2_d: StyleBoxFlat = wb._small_sb(true, false)
	var sp_d: StyleBoxFlat = wb._small_sb(false, true)
	check(sn_d != null and absf(sn_d.bg_color.r - 0.38) < 0.004 and absf(sn_d.bg_color.g - 0.27) < 0.004 \
		and absf(sn_d.bg_color.b - 0.10) < 0.004 and absf(sn_d.bg_color.a - 0.55) < 0.01,
		"N12-2：深色窗口钮 normal 底==深棕 (0.38,0.27,0.10) α0.55（==theme_dark Button normal 档）")
	check(sh2_d != null and absf(sh2_d.bg_color.r - 0.34) < 0.004 and absf(sh2_d.bg_color.g - 0.24) < 0.004 \
		and absf(sh2_d.bg_color.b - 0.09) < 0.004 and absf(sh2_d.bg_color.a - 0.85) < 0.01,
		"N12-2：深色窗口钮 hover 底==深棕 (0.34,0.24,0.09) α0.85（==theme_dark Button hover 档）")
	check(sp_d != null and absf(sp_d.bg_color.r - 0.38) < 0.004 and absf(sp_d.bg_color.g - 0.27) < 0.004 \
		and absf(sp_d.bg_color.b - 0.10) < 0.004 and absf(sp_d.bg_color.a - 0.85) < 0.01,
		"N12-2：深色窗口钮 pressed 底==深棕 (0.38,0.27,0.10) α0.85（==theme_dark Button pressed 档）")
	# AB-3 浅色窗口钮三支断言随浅主题删除退役——等价改写：档位注入已不可能（无 _is_dark 成员，
	# set 即报错），深档值恒定性 + 浅档常量反向锁 + GLYPH_COLOR 单值锚定。
	var sn_again: StyleBoxFlat = wb._small_sb(false, false)
	check(sn_again != null and sn_again.bg_color.is_equal_approx(sn_d.bg_color),
		"AB-3 等价改写：窗口钮底色无档位可注入（重复取样式恒深档，单源真值）")
	var wbs_const: Dictionary = (wb.get_script() as Script).get_script_constant_map()
	check(not wbs_const.has("BG_NORMAL_LIGHT") and not wbs_const.has("GLYPH_COLOR_LIGHT"),
		"AB-3 反向锁：window_buttons 浅档常量退役无复辟（BG_NORMAL_LIGHT/GLYPH_COLOR_LIGHT）")
	check(wbs_const.has("GLYPH_COLOR") and (wbs_const["GLYPH_COLOR"] as Color).is_equal_approx(Color(0.96, 0.90, 0.78)),
		"AB-3：GLYPH_COLOR 深档单值 (0.96,0.90,0.78)（值=旧深档，未变）")
	wb.free()

func _sec_linker() -> void:
	# ②/③/④ 挂载链（组合实例化 linker+main_menu.tscn——main.tscn 不入树防手势子进程；
	# spec §9 L-A ② 按此口径落地：linker 先入树、主菜单后入树 → 走 node_added 动态路径）
	# M-B（2026-09-07）：容器改**显式钉设计视口 1152×648**（原 PRESET_FULL_RECT——headless
	# expand 坑会把容器撑 1152×1152，u_ellipse 绝对值断言 (0,H/2,440,H/2) 的 H/2 必须为 324）；
	# u_rect_size 断言为相对断言（材质值==控件 size），钉视口后语义不变（M 批等价替换）。
	var container: Control = Control.new()
	container.size = Vector2(1152.0, 648.0)
	add_child(container)
	var linker: Node = load("res://scripts/ui_light_linker.gd").new()
	add_child(linker) # linker 先入树，主菜单后入树 → 走 node_added 动态路径
	var mm: Node = (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate()
	container.add_child(mm)
	await process_frame
	await process_frame
	var start: Button = mm.find_child("StartButton", true, false) as Button
	check(start != null and start.material is ShaderMaterial, "L7：StartButton 挂 ui_material（node_added 动态路径）")
	if start != null and start.material is ShaderMaterial:
		var m: ShaderMaterial = start.material
		check(String(m.shader.resource_path) == LM_SHADER, "L7：材质 shader 路径==ui_material.gdshader")
		check_eq(m.get_shader_parameter("u_rect_size"), start.size, "L7：u_rect_size==按钮实际尺寸")
	var dyn := Button.new()
	container.add_child(dyn)
	await process_frame
	check(dyn.material is ShaderMaterial, "L7：运行中动态 add_child Button 同样挂上 ui_material")
	# L-D 二轮修4：set_viewport_size 行为链（main.gd _process 每帧刷新 → 材质 uniform 跟随）
	if dyn.material is ShaderMaterial:
		linker.call("set_viewport_size", Vector2(800.0, 450.0))
		check_eq(dyn.material.get_shader_parameter("u_viewport_size"), Vector2(800.0, 450.0),
			"L-D：set_viewport_size 后已挂材质 u_viewport_size 跟随刷新（修4 屏幕口径配套）")
		linker.call("set_viewport_size", Vector2(1152.0, 648.0))
		check_eq(dyn.material.get_shader_parameter("u_viewport_size"), Vector2(1152.0, 648.0),
			"L-D：set_viewport_size 回写设计视口（可重复调用幂等）")
	# 批次V规格§3.2（V-C5）等价替换留痕（原：经主菜单 NewGameDialog 节点取 GlassDialog 卡片）：
	# 主菜单确认弹窗节点退役；GlassDialog 组件文件本体保留（main.gd 等仍复用）——卡片材质链
	# 断言改直例化组件场景承载（断言语义不变：组件档材质链契约；linker node_added 动态路径同样生效）。
	# GlassDialog 卡片=PanelContainer 类型（glass_dialog.tscn:23 实证；面板类基类非 Panel，
	# 计划稿 `as Panel` 恒 null，按主会话指示改 `as PanelContainer` 口径）
	var gdlg: Node = (load("res://scenes/shared/glass_dialog.tscn") as PackedScene).instantiate()
	container.add_child(gdlg)
	await process_frame
	var card: Control = null
	var c0: Node = gdlg.get_node_or_null("Card")
	if c0 is PanelContainer:
		card = c0 as Control
	check(card != null and card.material is ShaderMaterial, "L7→批次V§3.2：GlassDialog 卡片默认挂面板档材质（spec §5.1，组件保留直例化承载）")
	if card != null and card.material is ShaderMaterial:
		var pm: ShaderMaterial = card.material
		check_eq(int(pm.get_shader_parameter("u_panel_mode")), 1, "L7：卡片 u_panel_mode=1（面板档）")
		check_eq(int(pm.get_shader_parameter("u_ellipse_use")), 0, "L7：卡片 u_ellipse_use=0（圆角矩形形状，非 D 形）")
	gdlg.queue_free()
	# M-B（spec §3.2-2）：linker 椭圆写入口径改左贴弧——u_ellipse==(0,H/2,rx,ry=H/2)，
	# 与 window_manager 掩码两处消费同值（单一几何参数源，spec §1.4-1）。
	var epanel: Control = mm.get_node_or_null("LeftPanel/EllipsePanel") as Control
	if epanel != null and epanel.material is ShaderMaterial:
		var em: ShaderMaterial = epanel.material
		check_eq(em.get_shader_parameter("u_ellipse"), Vector4(0.0, 324.0, 440.0, 324.0),
			"M-B：linker 写入 u_ellipse==(0,H/2,440,H/2) 左贴弧口径（设计视口 H=648，M 批等价替换原 (W-rx,H/2,380,280)）")
		check_eq(int(em.get_shader_parameter("u_ellipse_use")), 1,
			"M-B：EllipsePanel u_ellipse_use=1（容器档口径收敛作用对象）")
	var tm: Node = root.get_node("ThemeManager")
	if start != null and start.material is ShaderMaterial:
		var m2: ShaderMaterial = start.material
		# 批次 AB-3：theme_changed 发射/翻转断言随信号退役——等价改写为深档单值材质参数锚定
		#（旧 theme_changed 后「深 0.55/0.04」终态值逐一保留为唯一真值 + 无主题概念反向锁）。
		check_eq(float(m2.get_shader_parameter("u_dir_energy")), 0.55,
			"AB-3 等价改写：u_dir_energy 恒深档 0.55（旧 theme_changed 深档终态值不变）")
		check_eq(float(m2.get_shader_parameter("u_frost")), 0.04,
			"AB-3 等价改写：u_frost 恒深档 0.04（旧浅档 0.035 随功能退役）")
		check(not (tm.get_script() as Script).get_script_signal_list().any(
			func(s: Dictionary) -> bool: return String(s.get("name", "")) == "theme_changed"),
			"AB-3 反向锁：ThemeManager 无 theme_changed 信号（翻转断言无复辟可能）")
	# L-D 二轮（L6-5 退出钮档位差补全）+ M-C 换档：按钮档点光按 glow_max meta 分级——退出钮
	# ratio=0.30/GLOW_MAX_NORMAL(0.75 深/0.70 浅)=0.40/0.4286；普通钮无 meta=1.0 不变。
	# M-C：能量基值 [0.50,0.45]→[0.30,0.26]（HTML 定档）；原「退出钮 u_specular 同步分级」
	# 断言随镜射根除删除（M-C 删镜射留痕，见 _sec_shader 段反转断言）。
	var quit2: Button = mm.find_child("QuitButton", true, false) as Button
	if quit2 != null and quit2.material is ShaderMaterial:
		var qm: ShaderMaterial = quit2.material
		var exp_ratio := 0.30 / 0.75   # 批次 AB-3：恒深档（旧浅档 0.70/0.26 分支退役）
		check_eq(float(qm.get_shader_parameter("u_mouse_energy")),
			0.30 * exp_ratio,
			"M-C：退出钮点光能量按 glow_max 分级（深档 0.30×%.3f，L-D 0.50 档等价替换；AB-3 恒深）" % exp_ratio)
		check(float(qm.get_shader_parameter("u_mouse_energy")) < float((start.material as ShaderMaterial).get_shader_parameter("u_mouse_energy")),
			"L-D：退出钮点光能量 < 普通钮（档位差单向性）")
	container.queue_free()
