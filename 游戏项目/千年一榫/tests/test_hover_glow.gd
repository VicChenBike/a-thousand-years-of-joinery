extends "res://tests/test_base.gd"
## K-A（KA-3，spec §4.2）：悬停光晕——①shader 资源可加载且可编译；
## ②main.tscn GlowLayer/GlowRect 载体挂接（CanvasLayer layer=100、ColorRect
## mouse_filter=IGNORE、ShaderMaterial 挂 shader、初始 visible=false 窗口模式由
## main.gd 启用）；③WindowManager.is_glow_target 判定链经场景实例复核（判定真值
## KA-2 已测，此处验挂接）。光斑观感/坐标=窗口截图判定（K-H WA-⑥）。
## 新增组件一律 load() 引用（P2-5/T14 时序防御）。

func _initialize() -> void:
	print("== test_hover_glow ==")
	# ① shader 资源（4.7 语法：hint_screen_texture）。
	# 探针实证：Godot 4.7 Shader 无 can_compile()（该 API 属 Material 层，Shader 类不可调），
	# spec §4.2 定义无头「可编译」代理=load() 非 null；本批强化为解析断言：
	# get_mode()==MODE_CANVAS_ITEM(1) 证 canvas_item 着色器类型解析成功 +
	# 源码含 hint_screen_texture（4.x 屏幕采样语法，3.x SCREEN_TEXTURE 已移除）。
	var sh: Shader = load("res://assets/shaders/hover_glow.gdshader") as Shader
	check(sh != null, "K9：hover_glow.gdshader 可加载（spec §4.2 无头可编译代理）")
	check(sh != null and sh.get_mode() == 1,
		"K9：shader 解析为 canvas_item 模式（get_mode=1，可编译证据）")
	check(sh != null and String(sh.get_code()).contains("hint_screen_texture"),
		"K9：shader 源码含 hint_screen_texture（4.x 屏幕采样语法）")

	# ② main.tscn 载体结构（instantiate 不入树，_ready 不触发，无头安全）
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	check(main_scene != null, "K9：main.tscn 可加载")
	var inst: Node = null
	var layer: CanvasLayer = null
	var rect: ColorRect = null
	if main_scene != null:
		inst = main_scene.instantiate()
		layer = inst.get_node_or_null("GlobalUI/GlowLayer") as CanvasLayer
		rect = inst.get_node_or_null("GlobalUI/GlowLayer/GlowRect") as ColorRect
	check(layer != null, "K9：GlobalUI/GlowLayer 存在且为 CanvasLayer")
	check(rect != null and rect.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"K9：GlowRect 为 ColorRect 且 mouse_filter=IGNORE（不挡输入）")
	var mat: ShaderMaterial = rect.material as ShaderMaterial if rect != null else null
	check(mat != null and mat.shader != null, "K9：GlowRect 挂 ShaderMaterial 且 shader 非空")
	check(layer != null and layer.layer == 100, "K9：GlowLayer layer=100（最顶层）")
	check(rect != null and not rect.visible, "K9：GlowRect 初始 visible=false（窗口模式由 main.gd 启用）")

	# ③ 判定链接入复核（load() 引用）：Button 命中、光晕载体 GlowRect 自身不命中
	var chain_ok: bool = false
	if inst != null:
		var wm: Script = load("res://scripts/window_manager.gd")
		chain_ok = wm != null and wm.is_glow_target(Button.new()) \
			and rect != null and not wm.is_glow_target(rect)
	check(chain_ok, "K9：is_glow_target 对 Button 命中且光晕载体 GlowRect 自身不命中")

	# ④ L-A（spec §5.5）：收敛改造 uniforms 存在（写入读回；载体结构与 is_glow_target 判定链保留）
	# 注：本段须在 inst.free() 之前执行——rect 是 inst 子节点，free 后访问即访问已释放对象
	# （计划稿「free 之后」为笔误，实测会读 freed 节点，语义不变仅前移，已在批次报告登记）。
	# 实证补强（4.7）：Material 参数字典对未声明 uniform 也照存照取（计划稿「get 返回 null」
	# 前提与实证不符，6 条写读断言会假绿）→ 存在性/默认值以「shader 源码声明」为真证据链，
	# 写读回环保留作为「材质层可写」辅证（LA-1 _sec_shader 同款口径）。
	var sh_src: String = String(sh.get_code()) if sh != null else ""
	for decl: String in ["uniform vec4 u_rects[8]", "uniform int u_rect_count = 0",
			"uniform float u_rect_strength[8]", "uniform float u_fade_radius = 12.0",
			"uniform float u_glow_radius_btn = 85.0", "uniform float u_glow_radius_panel = 110.0",
			"uniform vec4 u_ellipses[8]", "uniform int u_mask_type[8]"]:
		check(sh_src.contains(decl), "L-A：hover_glow 源码声明 %s（spec §5.5 收敛 uniforms）" % decl)
	var mat2: ShaderMaterial = rect.material as ShaderMaterial if rect != null else null
	if mat2 != null:
		mat2.set_shader_parameter("u_rects", [Vector4.ZERO])
		check(mat2.get_shader_parameter("u_rects") != null, "L-A：GlowRect uniform u_rects[8] 存在")
		mat2.set_shader_parameter("u_rect_strength", [1.0])
		check(mat2.get_shader_parameter("u_rect_strength") != null, "L-A：GlowRect uniform u_rect_strength[8] 存在")
		mat2.set_shader_parameter("u_rect_count", 1)
		check_eq(int(mat2.get_shader_parameter("u_rect_count")), 1, "L-A：GlowRect uniform u_rect_count 存在")
		mat2.set_shader_parameter("u_ellipses", [Vector4.ZERO])
		check(mat2.get_shader_parameter("u_ellipses") != null, "L-A：GlowRect uniform u_ellipses[8] 存在（容器档椭圆 SDF 掩码）")
		mat2.set_shader_parameter("u_mask_type", [0])
		check(mat2.get_shader_parameter("u_mask_type") != null, "L-A：GlowRect uniform u_mask_type[8] 存在")
		mat2.set_shader_parameter("u_glow_radius_btn", 85.0)
		check_eq(float(mat2.get_shader_parameter("u_glow_radius_btn")), 85.0,
			"M-C：径向半径按钮档 85（65→85 新档，HTML 定档；L-D 65 档等价替换留痕）")
		mat2.set_shader_parameter("u_glow_radius_panel", 110.0)
		check_eq(float(mat2.get_shader_parameter("u_glow_radius_panel")), 110.0,
			"L-A/L-D：径向半径容器档 110（§14-13 走查定档 140→110，与源码默认值一致）")
		mat2.set_shader_parameter("u_glow_k", 0.16)
		check_eq(float(mat2.get_shader_parameter("u_glow_k")), 0.16,
			"M-C：加色系数 uniform u_glow_k=0.16（0.26 字面量 uniform 化降强保字）")
	check(sh != null and String(sh.get_code()).contains("sd_ellipse"),
		"L-A：hover_glow 源码含椭圆 SDF（容器档掩码，弧外楔形区恒 0）")
	# L-D 二轮修3（用户 L4 邻近联动）：per-rect 最近点光斑中心——源码证据链=clamp(u_mouse_px,
	# rect_min, rect_max) 形态出现且在 per-rect 循环内计算 d（旧单一中心 distance(FRAGCOORD,u_mouse_px)
	# 循环外共享口径已删，邻居钮 28:1 不可辨）。
	check(sh != null and String(sh.get_code()).contains("clamp(u_mouse_px, rc.xy, rc.xy + rc.zw)"),
		"L-D：hover_glow 源码含 per-rect 最近点中心 clamp(u_mouse_px, rect_min, rect_max)（修3 邻近联动）")
	if inst != null:
		inst.free()

	# ⑤ L-C：glow_targets_for 契约（签名/四键/null 安全；真值在 test_glow_grade.gd）
	var wmc: GDScript = load("res://scripts/window_manager.gd")
	var gt: Dictionary = wmc.glow_targets_for(null)
	check(gt.has("rects") and gt.has("strengths") and gt.has("mask_types") and gt.has("ellipses"),
		"L-C：glow_targets_for(null) 返回四键契约字典")
	check((gt["rects"] as Array).is_empty(), "L-C：null 目标返回空采集（无头安全）")
	finish()
