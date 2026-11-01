extends "res://tests/test_base.gd"
## M-C（spec §3.3，2026-09-07）：光标光晕重做——HTML 原型先行定档移植。
## ① 定档参数断言（linker THEME_PARAMS/PANEL_PARAMS + main.gd 收口常量，参数表见
##   tools_m_prototype/参数定档.md，与 spec §3.3 暂定值一致）；
## ② shader 源码口径断言（u_specular 镜射根除 / 高斯衰减 / diff2 平面法线保留）；
## ③ hover_glow 新档（加色 k=0.16 uniform 化 / 半径 85）；
## ④ linker 行为断言（按钮档新参数 + glow_max 分级保留 + 主题翻转）；
## ⑤ main.gd 双源收口（_process 每帧写入 GlowRect 材质 + 常量与 shader 默认值同值锚定）；
## ⑥ M-B 成果保持（容器档口径 / lum_w / 无 d_rect）。
## 无头断言=源码/参数证据链；观感=窗口截图判定（walkthrough_20260907M/MC_自查）。

const LM_SHADER := "res://assets/shaders/ui_material.gdshader"
const HG_SHADER := "res://assets/shaders/hover_glow.gdshader"

func _initialize() -> void:
	print("== test_m_cursor_glow ==")
	_sec_params()
	_sec_ui_material()
	_sec_hover_glow()
	await _sec_linker()
	_sec_main_dual_source()
	_sec_mb_keep()
	finish()

# ---- ① 定档参数表（tools_m_prototype/参数定档.md；spec §3.3 暂定值经 HTML 原型复核采纳）----
func _sec_params() -> void:
	var lk: GDScript = load("res://scripts/ui_light_linker.gd")
	check(lk != null, "M-C：ui_light_linker 可加载")
	var tp: Dictionary = lk.THEME_PARAMS
	check(not tp.has("u_specular"), "M-C 定档：THEME_PARAMS 已移除 u_specular（镜射根除，参数层）")
	check_eq(tp.get("u_mouse_radius", 0.0), 140.0, "M-C 定档：按钮档点半径 160→140（HTML 定档）")
	# 批次 AB-3：能量/覆写由 [深,浅] 双档数组收敛为深档标量（值=旧深档，未变）。
	var en: Variant = tp.get("u_mouse_energy", null)
	check(en is float and absf(float(en) - 0.30) < 0.001,
		"AB-3 等价改写：按钮档能量=0.30（深档标量单值，旧 [0.30,0.26] 双档退役）")
	var pp: Dictionary = lk.PANEL_PARAMS
	check_eq(pp.get("u_mouse_radius", 0.0), 280.0, "M-C 定档：容器档点半径 200→280（HTML 定档）")
	var pen: Variant = pp.get("u_mouse_energy", null)
	check(pen is float and absf(float(pen) - 0.30) < 0.001,
		"AB-3 等价改写：容器档能量=0.30（深档标量单值，旧 [0.30,0.28] 双档退役）")

# ---- ② ui_material 源码口径：镜射根除 + 高斯衰减 + diff2 保留 ----
func _sec_ui_material() -> void:
	var sh: Shader = load(LM_SHADER) as Shader
	check(sh != null and sh.get_mode() == 1, "M-C：ui_material 可加载且 canvas_item 模式")
	if sh == null: return
	var src := String(sh.get_code())
	check(not src.contains("u_specular"), "M-C 删镜射：u_specular uniform 不存在（spec §3.3 验收 1；m03 射线=镜射×伪法线径向相干根除）")
	check(not src.contains("spec_mask"), "M-C 删镜射：容器档镜射禁用旗标 spec_mask 一并删除（M-B 过渡旗标完成使命，M 批等价替换）")
	check(not src.contains("normalize(L2 + vec3(0.0, 0.0, 1.0))"),
		"M-C 删镜射：Blinn 半程向量式 normalize(L2+(0,0,1)) 不存在（镜射项形态根除）")
	check(src.contains("exp(-d2 * d2 / (u_mouse_radius * u_mouse_radius))"),
		"M-C 手电筒化：点光衰减改高斯 exp(−d²/r²)（与 hover_glow 同族，spec §3.3 验收 1）")
	check(not src.contains("1.0 + pow(d2 / u_mouse_radius"),
		"M-C 手电筒化：旧 invsq 衰减式 1/(1+(d/r)²) 已移除（防双曲线残留）")
	check(src.contains("float diff2 = clamp(L2.z"), "M-C：diff2 平面法线漫反射保留（批次 L-D 二轮修4 口径不回归）")
	check(src.contains("u_light_color * diff2 * atten * u_hover"),
		"M-C：点光叠加式=u_light_color×diff2×atten×u_hover（纯径向，无镜射分量）")
	check(src.contains("SCREEN_UV * u_viewport_size"),
		"M-C：点光坐标 SCREEN_UV×u_viewport_size 口径保留（spec §六坑 5，main.gd 每帧刷链路配套）")

# ---- ③ hover_glow 新档：加色 0.16 uniform 化 + 半径 85 + 高斯保留 ----
func _sec_hover_glow() -> void:
	var sh: Shader = load(HG_SHADER) as Shader
	check(sh != null and sh.get_mode() == 1, "M-C：hover_glow 可加载且 canvas_item 模式")
	if sh == null: return
	var src := String(sh.get_code())
	check(src.contains("uniform float u_glow_k = 0.16"),
		"M-C 降强保字：加色系数 uniform 化 u_glow_k=0.16（0.26→0.16，spec §3.3 验收红线配套）")
	check(not src.contains("* 0.26"), "M-C 降强保字：旧加色字面量 *0.26 不存在（防双源）")
	check(src.contains("uniform float u_glow_radius_btn = 85.0"),
		"M-C：按钮档径向半径默认 65→85（保留中心亮→边缘暗形状，HTML 定档）")
	check(src.contains("uniform float u_glow_radius_panel = 110.0"),
		"M-C：容器档径向半径 110 保持（L-D 定档不动）")
	check(src.contains("u_glow_color * glow * u_glow_k"),
		"M-C：加色式消费 u_glow_k uniform（main.gd 可写、测试可锚）")
	check(src.contains("exp(-d * d / (rad * rad))"),
		"M-C：光斑高斯衰减 exp(−d²/r²) 保留（形状不回归）")
	check(src.contains("clamp(u_mouse_px, rc.xy, rc.xy + rc.zw)"),
		"M-C：per-rect 最近点中心保留（L-D 二轮修3 邻近联动不回归）")

# ---- ④ linker 行为：按钮档新参数写入 + glow_max 分级保留 + 主题翻转 ----
func _sec_linker() -> void:
	var container: Control = Control.new()
	container.size = Vector2(1152.0, 648.0)  # 钉设计视口（spec §六坑 1）
	add_child(container)
	var linker: Node = load("res://scripts/ui_light_linker.gd").new()
	add_child(linker)
	var mm: Node = (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate()
	container.add_child(mm)
	await process_frame
	await process_frame
	var start: Button = mm.find_child("StartButton", true, false) as Button
	check(start != null and start.material is ShaderMaterial, "M-C：StartButton 挂 ui_material（挂载链健康）")
	if start != null and start.material is ShaderMaterial:
		var m: ShaderMaterial = start.material
		check_eq(float(m.get_shader_parameter("u_mouse_radius")), 140.0,
			"M-C：按钮档材质写入点半径 140（linker THEME_PARAMS→材质链）")
		# 批次 AB-3：is_dark 探测与 theme_changed 翻转断言随机制退役——等价改写：
		# 按钮档能量恒深档 0.30 + 信号不存在反向锁（翻转通道无复辟可能）。
		check_eq(float(m.get_shader_parameter("u_mouse_energy")), 0.30,
			"AB-3 等价改写：按钮档能量恒深 0.30（旧 theme_changed 深档终态值不变）")
		var tm: Node = root.get_node("ThemeManager")
		check(not tm.has_signal("theme_changed"),
			"AB-3 反向锁：ThemeManager 无 theme_changed 信号（全量重写链无触发通道）")
	# 退出钮 glow_max 分级保留（M-C 只换档值，分级逻辑不动）
	var quit_btn: Button = mm.find_child("QuitButton", true, false) as Button
	var start_m: ShaderMaterial = start.material as ShaderMaterial if start != null else null
	if quit_btn != null and quit_btn.material is ShaderMaterial and start_m != null:
		var qm: ShaderMaterial = quit_btn.material
		var ratio := 0.30 / 0.75   # 批次 AB-3：恒深档（旧浅档 0.70/0.26 分支退役）
		check_eq(float(qm.get_shader_parameter("u_mouse_energy")),
			0.30 * ratio,
			"M-C：退出钮能量=深档×glow_max 分级（%.4f，分级逻辑保留；AB-3 恒深）" % ratio)
		check(float(qm.get_shader_parameter("u_mouse_energy")) < float(start_m.get_shader_parameter("u_mouse_energy")),
			"M-C：退出钮能量 < 普通钮（档位差单向性保持）")
	# 容器档 EllipsePanel 半径 280
	var epanel: Control = mm.get_node_or_null("LeftPanel/EllipsePanel") as Control
	if epanel != null and epanel.material is ShaderMaterial:
		check_eq(float((epanel.material as ShaderMaterial).get_shader_parameter("u_mouse_radius")), 280.0,
			"M-C：容器档材质写入点半径 280（PANEL_PARAMS→材质链）")
	container.queue_free()

# ---- ⑤ main.gd 双源收口：常量真值 + _process 写入链 + shader 默认值同值锚定 ----
func _sec_main_dual_source() -> void:
	var mains: GDScript = load("res://scenes/main.gd")
	check(mains != null, "M-C：main.gd 可加载")
	if mains == null: return
	var cmap: Dictionary = mains.get_script_constant_map()
	check(cmap.has("HOVER_GLOW_RADIUS_BTN") and absf(float(cmap["HOVER_GLOW_RADIUS_BTN"]) - 85.0) < 0.001,
		"M-C 收口：main.HOVER_GLOW_RADIUS_BTN=85（收口真值常量）")
	check(cmap.has("HOVER_GLOW_RADIUS_PANEL") and absf(float(cmap["HOVER_GLOW_RADIUS_PANEL"]) - 110.0) < 0.001,
		"M-C 收口：main.HOVER_GLOW_RADIUS_PANEL=110")
	check(cmap.has("HOVER_GLOW_K") and absf(float(cmap["HOVER_GLOW_K"]) - 0.16) < 0.001,
		"M-C 收口：main.HOVER_GLOW_K=0.16")
	var msrc := String((mains as Script).get_source_code())
	check(msrc.contains("func _push_glow_radii"), "M-C 收口：main._push_glow_radii 写入函数存在")
	check(msrc.contains("_push_glow_radii(mat)"), "M-C 收口：_process 每帧调用写入（消除批次 L 双写不联动）")
	# 常量与 shader 默认值同值锚定（防再次漂移）
	var hg: Shader = load(HG_SHADER) as Shader
	var hsrc := String(hg.get_code()) if hg != null else ""
	check(hsrc.contains("uniform float u_glow_radius_btn = %.1f" % float(cmap.get("HOVER_GLOW_RADIUS_BTN", 0.0))),
		"M-C 收口：main 常量 btn 与 hover_glow 默认值同值（85，双源锚定）")
	check(hsrc.contains("uniform float u_glow_radius_panel = %.1f" % float(cmap.get("HOVER_GLOW_RADIUS_PANEL", 0.0))),
		"M-C 收口：main 常量 panel 与 hover_glow 默认值同值（110，双源锚定）")
	check(hsrc.contains("uniform float u_glow_k = %s" % _fmt2(float(cmap.get("HOVER_GLOW_K", 0.0)))),
		"M-C 收口：main 常量 k 与 hover_glow 默认值同值（0.16，双源锚定）")
	# 行为证据：_push_glow_radii 写入后材质持有新值（普通方法无 @onready 依赖，可不入树直调）
	var inst: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	check(inst != null, "M-C 收口：main.tscn 可实例化（不入树）")
	var probe := ShaderMaterial.new()
	probe.shader = hg
	if inst != null:
		inst.call("_push_glow_radii", probe)
		check_eq(float(probe.get_shader_parameter("u_glow_radius_btn")), 85.0,
			"M-C 收口：_push_glow_radii 后材质持有 u_glow_radius_btn=85（写入链行为证据）")
		check_eq(float(probe.get_shader_parameter("u_glow_radius_panel")), 110.0,
			"M-C 收口：_push_glow_radii 后材质持有 u_glow_radius_panel=110")
		check_eq(float(probe.get_shader_parameter("u_glow_k")), 0.16,
			"M-C 收口：_push_glow_radii 后材质持有 u_glow_k=0.16")
		inst.free()

func _fmt2(v: float) -> String:
	return "%.2f" % v

# ---- ⑥ M-B/M-A 成果保持（容器档口径 / lum_w / 无 d_rect）----
func _sec_mb_keep() -> void:
	var sh: Shader = load(LM_SHADER) as Shader
	if sh == null: return
	var src := String(sh.get_code())
	check(src.contains("is_container"), "M-C 保持：容器档旗标 is_container（M-B 口径不回归）")
	check(src.contains("flat_lit"), "M-C 保持：容器档平坦受光 flat_lit（M-B 删双色圆口径不回归）")
	check(src.contains("lum_w"), "M-C 保持：lum_w 暗像素亮度权重（M-A 字可读口径不回归）")
	check(not src.contains("d_rect"), "M-C 保持：shape_d 无 d_rect 窄条（M-B 凸块根除不回归）")
	var hg: Shader = load(HG_SHADER) as Shader
	if hg != null:
		var hsrc := String(hg.get_code())
		check(hsrc.contains("sd_ellipse"), "M-C 保持：hover_glow 椭圆 SDF 掩码（容器档光斑形状不回归）")
