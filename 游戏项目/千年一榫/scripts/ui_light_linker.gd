class_name UILightLinker
extends Node
## L-A（L7，spec §5.6 定稿）：统一光影材质驱动——启动扫描+node_added 动态挂载 ui_material
## （按钮/面板档）、维护 u_rect_size、hover 目标 u_mouse_local/u_hover。
## 批次 AB-3：深浅主题机制删除——theme_changed 全量重写退役、THEME_PARAMS/PANEL_PARAMS
## 双档 [深,浅] 收敛为深档单值（全局恒深，观感与旧深色档逐一相同）。
## canvas_item 无 per-instance uniform（4.7 实证）→ 每控件独立 ShaderMaterial 实例。
const SHADER_PATH := "res://assets/shaders/ui_material.gdshader"
const ELLIPSE_RX := 440.0  # 面板档缺省椭圆参数（M-B 拍板 #5 左贴弧：弧顶深度 440；一处定参在 main_menu.gd，挂 meta 后以 meta 为准）
const ELLIPSE_RY := 324.0  # 设计视口参考值（=648/2）；运行时 ry 恒由容器实际高×0.5 推导（端点顶满上下角）
const THEME_PARAMS := {
	"u_light_dir": Vector2(-0.85, -0.5), "u_dir_energy": 0.55,
	"u_light_color": Vector3(1.0, 0.96, 0.88),
	# M-C（spec §3.3，2026-09-07，HTML 原型定档 tools_m_prototype/参数定档.md）：
	# u_specular 删除（镜射根除——m03「朝左下射线」=镜射×SDF 伪法线径向相干，spec §3.3 根因 1）；
	# u_mouse_energy [0.50,0.45]→[0.30,0.26]（手电筒化降能量）；u_mouse_radius 160→140（按钮档）。
	# 原 L-D「u_specular 分级」随镜射根除删除，glow_max 分级只作用于能量。
	"u_mouse_energy": 0.30, "u_mouse_radius": 140.0,
	"u_inner_shadow": 0.25,
	# M-A（spec §3.1，2026-09-07）：磨砂噪声收敛——金底斜向亮斑（m02）观感微修，[0.06,0.05]→[0.04,0.035]。
	"u_frost": 0.04,
	"u_edge_glow_color": Vector3(1.0, 0.922, 0.706),
}  # 批次 AB-3：值为深档标量（原 [深, 浅] 双档数组收敛，spec §5.4 定稿表深列）
const PANEL_PARAMS := {  # 面板档覆写（spec §5.3 面板档参数表；批次 AB-3：深档单值）
	"u_dir_energy": 0.35, "u_frost": 0.05, "u_inner_shadow": 0.20,
	# M-C：容器档点半径 200→280（手电筒化，HTML 定档）；能量 0.30（spec 未点名，批次 L 定稿）。
	"u_mouse_energy": 0.30, "u_mouse_radius": 280.0, "u_panel_mode": 1,
}
var _base_shader: Shader
var _mats := {}  # Control -> ShaderMaterial（登记，供遍历维护）
# L-D 二轮修4：点光屏幕口径的视口尺寸源（shader uniform 默认 (1152,648) 同值；
# main.gd _process 每帧随 get_visible_rect().size 刷新，_attach 新材质即用最新缓存）
var _viewport_size := Vector2(1152.0, 648.0)

func _ready() -> void:
	_base_shader = load(SHADER_PATH)
	_scan_and_attach()
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)   # 批次 W（P3-6a）：离树即清登记

func _panel_mode_of(c: Control) -> bool:
	# 面板档识别（统一口径）：显式 meta("ui_material","panel") 或 GlassDialog 卡片（spec §5.1
	# 可选项默认挂载；glass_dialog.gd 零触碰，由 linker 识别）
	# 契约（L-C 复核登记）：下方识别依赖 glass_dialog.tscn Card 节点名，改名需同步本处
	# （同族结构契约还有 WindowManager._is_window_chrome 的 GlobalUI/CanvasLayer 层级依赖）。
	if c.has_meta("ui_material"): return str(c.get_meta("ui_material")) == "panel"
	return c.name == "Card" and c.get_parent() != null \
		and (c.get_parent() as Node).get_script() == load("res://scenes/shared/glass_dialog.gd")

func _is_ui_target(n: Node) -> bool:
	if n is Button or n is TextureButton: return true
	return n is Control and _panel_mode_of(n)

func _attach(c: Control) -> void:
	if c == null or _mats.has(c) or _base_shader == null: return
	var mat := ShaderMaterial.new()
	mat.shader = _base_shader
	var panel := _panel_mode_of(c)
	c.material = mat
	_mats[c] = mat
	_write_theme_uniforms(mat, c, panel)
	_write_size(c)
	mat.set_shader_parameter("u_viewport_size", _viewport_size)  # L-D 二轮修4：屏幕口径点光配套
	# 修复批 P3（2026-09-26）：守卫改同形 Callable 断言——连接形态是 _write_size.bind(c)，
	# 断言须同参构造（4.7 实证 is_connected 按 object+method 匹配忽略 binds，裸方法查带 bind
	# 连接也命中，故本改语义零变化=显式化加固；探针 tests/zz_probe_dupconnect_temp 已删留痕）。
	if not c.resized.is_connected(_write_size.bind(c)):
		c.resized.connect(_write_size.bind(c))

func _write_theme_uniforms(mat: ShaderMaterial, c: Control, panel: bool) -> void:
	for key: String in THEME_PARAMS:
		mat.set_shader_parameter(key, THEME_PARAMS[key])
	if panel:
		for key: String in PANEL_PARAMS:
			mat.set_shader_parameter(key, PANEL_PARAMS[key])
		var use_ellipse: bool = _is_ellipse_container(c)  # meta("glow_mask","ellipse") 才做 D 形裁剪
		mat.set_shader_parameter("u_ellipse_use", 1 if use_ellipse else 0)
		# M-B（spec §3.2-2）：u_ellipse 改左贴弧口径 (0, H/2, rx, ry=H/2)——弧心=面板左缘、
		# 端点顶满上下角；ry 由容器实际高推导（meta.ry 仅为设计视口参考，防窗口高变化失配）。
		# 与 window_manager 掩码 Vector4 两处消费同值（单一几何参数源，spec §1.4-1）。
		var ep: Vector2 = c.get_meta("ellipse_params") if c.has_meta("ellipse_params") else Vector2(ELLIPSE_RX, ELLIPSE_RY)
		mat.set_shader_parameter("u_ellipse", Vector4(0.0, c.size.y * 0.5, ep.x, c.size.y * 0.5))
	else:
		# L-D 二轮（退出钮档位差补全，L6-5）：按钮档点光能量按 glow_max meta 分级——
		# 比例=自身档/普通钮光斑档（GLOW_MAX_NORMAL，与 window_manager.glow_targets_for
		# 同源常量；退出钮 0.30/0.75=0.40、普通钮无 meta=1.0 不变）。首轮走查实测退出钮与新游戏
		# hover 的 peak 亮度差仅 ~2%（点光无分级，稀释了光斑 2.5 倍档差）；分级后退出钮点光
		# 贡献 ×0.4（DECOMP 中心 0.417→0.167），peak 亮度差拉开到 ≥25%。
		# M-C：原 u_specular 同步分级写入随镜射根除删除，分级只作用于能量。
		var wm: GDScript = load("res://scripts/window_manager.gd")
		var gmax := float(c.get_meta("glow_max")) if c.has_meta("glow_max") else -1.0
		var ratio := 1.0
		if gmax >= 0.0:
			ratio = clampf(gmax / float(wm.GLOW_MAX_NORMAL), 0.0, 1.0)
		mat.set_shader_parameter("u_mouse_energy", float(THEME_PARAMS["u_mouse_energy"]) * ratio)

func _is_ellipse_container(c: Control) -> bool:
	return c.has_meta("glow_mask") and str(c.get_meta("glow_mask")) == "ellipse"

func _write_size(c: Control) -> void:
	if _mats.has(c) and is_instance_valid(c):
		(_mats[c] as ShaderMaterial).set_shader_parameter("u_rect_size", c.size)
		if _panel_mode_of(c) and _is_ellipse_container(c):
			# M-B：左贴弧口径 (0, H/2, rx, ry=H/2)，resized 时随实际高刷新（防失配）
			var ep: Vector2 = c.get_meta("ellipse_params") if c.has_meta("ellipse_params") else Vector2(ELLIPSE_RX, ELLIPSE_RY)
			(_mats[c] as ShaderMaterial).set_shader_parameter("u_ellipse", Vector4(0.0, c.size.y * 0.5, ep.x, c.size.y * 0.5))

func _scan_and_attach() -> void:
	_walk(get_tree().root)

func _walk(n: Node) -> void:
	if n is Control and _is_ui_target(n): _attach(n)
	for ch: Node in n.get_children(): _walk(ch)

func _on_node_added(n: Node) -> void:
	# 动态覆盖（spec §5.6 定稿）：node_added 时场景脚本 _ready 未跑、meta 可能未挂 → 延帧重扫。
	# 批次 W（P3-6a/W4-P3-D 同源核对）：强引用直传在「入树同帧即 free」时，延迟调用于参数
	# 转换期即报「Cannot convert argument 1 from Object to Object」（函数体 is_instance_valid
	# 不可达——W7 移交清单 n8_final_verify.log ×8 实证），改弱引用传递，释放后 get_ref() 为
	# null 静默跳过（签名同源确认：_rescan_deferred.call_deferred(n) 即报错点）。
	_rescan_deferred.call_deferred(weakref(n))

func _rescan_deferred(w: Variant) -> void:
	var nv: Variant = w.get_ref() if w is WeakRef else null
	if nv is Node and (nv as Node).is_inside_tree():
		var n: Node = nv
		if n is Control and _is_ui_target(n): _attach(n)
		for ch: Node in n.get_children(): _walk(ch)

## 批次 W（P3-6a，规格 §7）：节点离树即清 _mats 登记——场景切换/free 后不再累积失效键
## （泄漏根除+每帧/全量遍历范围收敛至活材质）；重入树经 node_added 重挂（_attach 幂等重建）。
func _on_node_removed(n: Node) -> void:
	_mats.erase(n)

func set_hover(c: Control, mouse_px: Vector2, hover: float) -> void:
	# 仅 hover 目标每帧写（main.gd _process 调用）；离开目标由 main.gd 写 0 归零衰减。
	# L-D 二轮修4：mouse_px 改**屏幕像素口径**（原局部坐标 u_mouse_local 与 shader 屏幕口径
	# 不符 → 第二点光不可见；main.gd 现直接传 get_screen_transform()*get_mouse_position()，
	# 与 shader 端 SCREEN_UV*u_viewport_size 同一坐标系）。
	if c != null and _mats.has(c) and is_instance_valid(c):
		var m: ShaderMaterial = _mats[c]
		m.set_shader_parameter("u_mouse_screen", mouse_px)
		m.set_shader_parameter("u_hover", hover)

## L-D 二轮修4：视口尺寸随窗口变化刷新全部已挂材质（main.gd _process 每帧调用，
## 内部按值变化才写，避免每帧全量 set）；_attach 新材质沿用最新缓存。
func set_viewport_size(size: Vector2) -> void:
	if size == _viewport_size:
		return
	_viewport_size = size
	for c: Control in _mats.keys():
		if is_instance_valid(c):
			(_mats[c] as ShaderMaterial).set_shader_parameter("u_viewport_size", size)
