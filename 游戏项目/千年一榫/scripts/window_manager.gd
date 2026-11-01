class_name WindowManager
extends Node
## K-A（K8/K9）：窗口系统纯逻辑收口，全部静态方法；窗口 API 无头守卫。
## 跨批公共契约：K-B 全屏开关 / K-C 关闭接线 / K-G 拖窗命中排除均复用本类。
const MIN_SIZE := Vector2i(800, 450); const ASPECT_TOLERANCE := 0.01
# 批次 T（T18，spec §4-18-4）：MIN_SIZE 720×405→800×450（16:9 维持；等价替换留痕）。
# corner 编码（文档约定，0=TL/1=TR/2=BL/3=BR）：角偏移 off 逐轴取 0/1，对角=1−off。
static func aspect_correction(size: Vector2i) -> Vector2i:
	var want_h := int(round(float(size.x) * 9.0 / 16.0))  # 以宽为锚 16:9（spec §4.3 定稿）
	return Vector2i(size.x, clampi(want_h, MIN_SIZE.y, 1 << 30))
static func is_fullscreen() -> bool:
	if DisplayServer.get_name() == "headless": return false
	return DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED
static func set_fullscreen(on: bool) -> void:
	if DisplayServer.get_name() == "headless": return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
static func enforce_aspect(blocked: bool = false) -> void:
	## 批次 Z（Z6-P1-2，spec §6）：窗口态判据升级综合真值——调用方（main._process 每 0.25s）
	## 传入 _window_non_windowed()（无边框最大化 get_mode 恒 WINDOWED 的双通道补真，见
	## drag_gate_closed）。blocked=true 直接跳过 16:9 强制（最大化/全屏态不得被改尺寸留黑边）；
	## 参数缺省 false 保旧调用签名兼容。
	if DisplayServer.get_name() == "headless": return
	if blocked or DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED: return
	var s := DisplayServer.window_get_size()
	if s.x < MIN_SIZE.x or s.y < MIN_SIZE.y:
		DisplayServer.window_set_size(MIN_SIZE)  # 800x450 仍 16:9
		return
	if absf(float(s.y) / float(s.x) - 9.0 / 16.0) > ASPECT_TOLERANCE:
		DisplayServer.window_set_size(WindowManager.aspect_correction(s))
static func drag_gate_closed(mode: int, wb_maxed: bool, decoration_hidden: bool) -> bool:
	## 批次 Z（Z6-P1-2，spec §6）：拖窗门/16:9 强制门「综合真值」纯函数（无头可测）——
	## 无边框窗口下 DisplayServer.window_get_mode() 恒报 WINDOWED（K-H 实证、4.7 复现，
	## window_buttons.gd:115-118 与 main.gd 双通道口径自证），故最大化判定并入三通道：
	## ①mode 真实上报非 WINDOWED（FULLSCREEN/MAXIMIZED 正常上报态）；
	## ②WindowButtons._maxed 本地状态机（无边框最大化的权威，K-H P1 状态机）；
	## ③RoundedFrame._decoration_force_hidden 显式标志（修复4 批次Z走查改读——旧值
	## window_decoration_hidden(mode)=mode>=MAXIMIZED 与通道①逻辑蕴含系死通道、注释
	## 宣称的「三通道纵深」不成立；现读 set_decoration_hidden 状态机真值：maximize_toggled
	## 即时写 + 1s 轮询刷新，覆盖装饰层已隐而 mode/_maxed 未及反映的窗口期与
	## WindowButtons 缺位场景，名实相符）。
	## 任一成立 → 视为非「可自由拖拽/可改尺寸的窗口化」态。
	return mode != DisplayServer.WINDOW_MODE_WINDOWED or wb_maxed or decoration_hidden
static func is_interactive_control(c: Control) -> bool:
	## 拖窗命中排除（P1-2 契约①）：可交互控件或其 Control 祖先不启动拖窗。
	var cur := c
	while cur != null:
		if cur is Button or cur is Slider or cur is TextureButton or cur is SubViewportContainer: return true
		if cur.has_meta("interactive"): return true
		cur = cur.get_parent() as Control
	return false
static func is_glow_target(c: Control) -> bool:
	## K9 悬停光晕判定：Button/TextureButton 或挂 meta("hover_glow") 的控件（含祖先）。
	var cur := c
	while cur != null:
		if cur is Button or cur is TextureButton: return true
		if cur.has_meta("hover_glow"): return true
		cur = cur.get_parent() as Control
	return false

# ---- L-C（L6-3~L6-5，spec §7.1 定稿）：光晕邻接采集 + 亮度分级 ----
# 批次 AB-3：深浅主题机制删除——原 *_DARK/*_LIGHT 双档常量收敛为深档单值（值=旧深档，逐一未变）。
const GLOW_MAX_NORMAL := 0.75
# L-D 走查定档（spec §14-11 档内）：退出档 0.40/0.38→0.30/0.30，理由见 main_menu.gd
# _apply_arc_panel 注释（与普通钮亮度差从 ~14% 扩大到 ~30%，L6-5「明显低于」）。
const GLOW_MAX_QUIT := 0.30
const GLOW_MAX_PANEL := 0.30
const GLOW_MAX_WINDOW := 0.55        # 窗口三钮/全局设置钮
const NEIGHBOR_COEF := 0.35;         const QUIT_NEIGHBOR_COEF := 0.30
# 径向半径唯一真值源 = scenes/main.gd.HOVER_GLOW_RADIUS_BTN/PANEL（M-C 双源收口定稿：
# main.gd._push_glow_radii 每帧把按钮档 85 / 容器档 110 写入 GlowRect 材质，改常量即生效）。
# 原 GLOW_RADIUS_BTN=65 / GLOW_RADIUS_PANEL=110（L-D 批注「与 shader 默认同源」）在 M-C
# 半径 65→85 后失效为双源残留，已删除——勿在本文件重建半径常量，测试经 main.gd 常量表断言。
const MAX_RECTS := 8
const ELLIPSE_DEFAULT := Vector2(440.0, 324.0)  # meta 缺省（一处定参在 main_menu.gd；M-B 左贴弧 rx440/ry324=设计视口半高）
const CoordSpace := preload("res://scripts/coord_space.gd")  # hover_glow 修复批：content→device 纯函数收口

static func glow_targets_for(hovered: Control) -> Dictionary:
	## 邻接规则（spec §7.1 定稿+工程事实修正）：①A 自身；②A 的挂 meta("glow_mask","ellipse")
	## 容器（祖先链∪同父兄弟中的椭圆面板——主菜单三钮与 EllipsePanel 同级直挂 LeftPanel，
	## spec §6.2 定稿结构，故「祖先容器」按「祖先或同父」落地，容器区域光走椭圆 SDF 掩码档）；
	## ③同父兄弟 Button/TextureButton/挂 meta("hover_glow") 控件（与 A 中心距离升序，
	## 排除 ② 已采集容器防重复入列）。截断优先级=主目标>容器>近邻（spec §11-2），合计 ≤8。
	var rects: Array[Rect2] = []
	var strengths: Array[float] = []
	var mask_types: Array[int] = []
	var ellipses: Array[Vector4] = []
	if hovered == null:
		return {"rects": rects, "strengths": strengths, "mask_types": mask_types, "ellipses": ellipses}
	# 批次 AB-3：深浅主题机制删除——档级不再探测系统深浅，深档单值（_glow_max_of 单参）。
	_push(hovered, _glow_max_of(hovered), rects, strengths, mask_types, ellipses)  # ①主
	var anc := _find_ellipse_container(hovered)                                     # ②容器（祖先∪同父）
	if anc != null and rects.size() < MAX_RECTS:
		_push(anc, _glow_max_of(anc), rects, strengths, mask_types, ellipses)
	var parent := hovered.get_parent()                                                   # ③近邻兄弟
	if parent is Control:
		var h_center: Vector2 = _global_center(hovered)
		var cands: Array[Control] = []
		for ch: Node in (parent as Control).get_children():
			if ch is Control and ch != hovered and ch != anc \
					and (ch is Button or ch is TextureButton or (ch as Control).has_meta("hover_glow")):
				cands.append(ch)
		cands.sort_custom(func(a: Control, b: Control) -> bool:
			return _global_center(a).distance_to(h_center) < _global_center(b).distance_to(h_center))
		var max_main := _glow_max_of(hovered)
		for nb: Control in cands:
			if rects.size() >= MAX_RECTS: break
			# 邻居系数按邻居自身档位（spec §7.1 表「作为邻居被联动系数」列）：
			# 退出档邻居（显式 meta glow_max≤GLOW_MAX_QUIT=0.30（L-D 定档后与容器档同值），
			# 不做文本匹配）0.30，其余 0.35；强度=主目标档上限×该系数。
			# 走查遗留风险登记（L-D）：本判据是「meta 值 ≤ 退出档」的隐式识别，退出档与容器档
			# 现同为 0.30——容器已由 `ch != anc` 排除，但**若将来有按钮显式挂 glow_max≤0.30**
			# 会被按退出邻居系数处理；建议改显式 meta("glow_tier")（超 §14 暂定值档，交主会话拍板）。
			var ncoef := QUIT_NEIGHBOR_COEF if (nb.has_meta("glow_max") and float(nb.get_meta("glow_max")) <= GLOW_MAX_QUIT) else NEIGHBOR_COEF
			_push(nb, max_main * ncoef, rects, strengths, mask_types, ellipses)  # 邻居=主目标上限×邻居自身系数
	return {"rects": rects, "strengths": strengths, "mask_types": mask_types, "ellipses": ellipses}

static func _glow_max_of(c: Control) -> float:
	## 批次 AB-3：深浅主题机制删除——dark 参数与浅档 glow_max_light meta 分流退役，深档为唯一真值。
	if c.has_meta("glow_max"):
		# 显式覆写优先（spec §7.1 挂载方式：退出钮 0.40/容器 0.30，meta 随 L-B 落地）。
		return float(c.get_meta("glow_max"))
	if _is_ellipse_container(c): return GLOW_MAX_PANEL
	if _is_window_chrome(c): return GLOW_MAX_WINDOW  # 窗口三钮/全局设置钮（GlobalUI 直属系）
	return GLOW_MAX_NORMAL

static func _is_ellipse_container(c: Control) -> bool:
	return c.has_meta("glow_mask") and str(c.get_meta("glow_mask")) == "ellipse"

static func _is_window_chrome(c: Control) -> bool:
	## GlobalUI 直属系识别：父链向上不再遇 Control 即达 CanvasLayer（窗口三钮/设置钮/弹窗系）。
	var cur: Node = c.get_parent()
	while cur is Control:
		cur = cur.get_parent()
	return cur is CanvasLayer

static func _find_ellipse_container(c: Control) -> Control:
	## 容器采集（spec §7.1 祖先容器+工程事实修正）：先沿祖先链查，再查同父兄弟中的椭圆面板
	## （主菜单三钮直挂 LeftPanel、EllipsePanel 与按钮同级——spec §6.2 定稿结构）。
	var cur := c.get_parent()
	while cur is Control:
		if _is_ellipse_container(cur): return cur
		cur = cur.get_parent()
	var p := c.get_parent()
	if p is Control:
		for ch: Node in (p as Control).get_children():
			if ch is Control and ch != c and _is_ellipse_container(ch): return ch
	return null

static func _global_center(c: Control) -> Vector2:
	## hover_glow 修复批（2026-09-18 追加）：排序中心与 shader 消费口径同化设备系——
	## per-rect 最近点/距离均在设备像素发生（hover_glow.gdshader clamp/distance），
	## 邻居「距离升序」按设备距离排才与渲染空间一致（CanvasItem.get_screen_transform()
	## 不含拉伸=content，再过视口拉伸变换；设备中心=stretch×(content origin+半尺寸)）。
	var xf: Transform2D = _vp_stretch_of(c)
	return xf * (c.get_screen_transform().origin + c.size * 0.5)

static func _vp_stretch_of(c: Control) -> Transform2D:
	## 控件所在视口的拉伸变换（content→渲染设备像素，含逐轴 scale；headless 下为虚拟
	## 缩放——测试经同一变换取期望值，与生产恒同构）。
	return c.get_viewport().get_screen_transform()

static func _push(c: Control, strength: float, rects: Array[Rect2], strengths: Array[float],
		mask_types: Array[int], ellipses: Array[Vector4]) -> void:
	## 目标入列：所有档均填 rects 定界；容器档 mask_type=1 且 ellipses=(弧心,rx,ry)
	## （与面板材质同源参数，spec §5.5）；非容器档 mask_type=0、ellipse 填 Vector4.ZERO。
	## M-B（spec §3.2-2）：椭圆掩码改左贴弧口径——x=容器全局左缘（弧心在面板左边缘）、
	## y=全局中心 y、ry=容器实际高×0.5（端点顶满上下角），与面板材质 u_ellipse 两处消费同值。
	## hover_glow 修复批（2026-09-18 追加）：产出空间 content→**设备系**。FRAGCOORD/
	## u_mouse_px 是渲染目标像素（窗口相对设备 px），而 Control.get_screen_transform()
	## 不含拉伸（实证=根 content 系，CanvasItem 版与 Viewport 版同名异义）——旧产出
	## s≠1 时矩形/椭圆掩码整体偏移（用户「光斑在按钮左侧」直接元凶之一）。现 pos/size/
	## 椭圆心/rx 全经视口拉伸变换换算，rect 纯函数收口 CoordSpace.rect_device_from_content
	##（逐轴 scale，expand 下 sx≠sy 恒正确）。假设备案：光斑目标均在主窗口视口画布
	##（GlobalUI 及其子层/场景 Control），无 Popup 内嵌 Window 宿主目标——若将来把
	## glow 目标挂进嵌入式弹窗，须改用根窗口变换链（见 coord_space.gd 头注 4/5）。
	var vp_xf: Transform2D = _vp_stretch_of(c)
	var d_rect: Rect2 = CoordSpace.rect_device_from_content(
		Rect2(c.get_screen_transform().origin, c.size), vp_xf)
	rects.append(d_rect)
	strengths.append(strength)
	if _is_ellipse_container(c):
		mask_types.append(1)
		var ep: Vector2 = c.get_meta("ellipse_params") if c.has_meta("ellipse_params") else ELLIPSE_DEFAULT
		# 审查收尾微批 P2-8②（2026-09-18）：rx 的逐轴拉伸比改由视口变换 get_scale() 直接取
		#（rect_device_from_content 内部同源推导，正常控件下逐位一致；消除零尺寸控件的
		# 病态分母 0/0.0001 推导——零尺寸时 get_scale() 仍为真实缩放比，语义更稳）。
		ellipses.append(Vector4(d_rect.position.x, d_rect.position.y + d_rect.size.y * 0.5,
			ep.x * vp_xf.get_scale().x, d_rect.size.y * 0.5))
	else:
		mask_types.append(0)
		ellipses.append(Vector4.ZERO)

# ---- 批次 T（T18，spec §4-18-2/§6.3，P1-3 终版）：四角斜角等比缩放纯函数（无头可测） ----

## 被拖角的窗口内偏移（逐轴 0/1）：TL=(0,0)、TR=(1,0)、BL=(0,1)、BR=(1,1)
static func corner_offset(corner: int) -> Vector2:
	match corner:
		0: return Vector2(0.0, 0.0)
		1: return Vector2(1.0, 0.0)
		2: return Vector2(0.0, 1.0)
		_: return Vector2(1.0, 1.0)

## 等比缩放：尺寸与位置一个纯函数同出（P1-3）。
## 尺寸：delta=drag_vec 沿对角单位向量投影（正=放大，调用方按角向定向）→ s0=1+delta/对角线长；
## 钳制次序（P2-9）：先锁比例、后整体钳 s 区间（两维同乘同一 s，永不独立钳）→ 恒 16:9（取整公差 ≤1px）。
## 位置：被拖角的对角屏幕坐标恒定 —— pos_new = C_start − (1−off)逐轴×new_size（C_start=固定对角起始屏幕坐标）。
static func corner_resize(start_size: Vector2i, corner: int, drag_vec: Vector2,
		max_size: Vector2i, start_pos: Vector2i) -> Dictionary:
	var off := corner_offset(corner)
	var diag_unit := Vector2(start_size).normalized()
	var delta := drag_vec.dot(diag_unit)
	var s0 := 1.0 + delta / maxf(float(start_size.length()), 1.0)
	var s_min := maxf(float(MIN_SIZE.x) / float(start_size.x), float(MIN_SIZE.y) / float(start_size.y))
	var s_max := maxf(minf(float(max_size.x) / float(start_size.x), float(max_size.y) / float(start_size.y)), s_min)
	var s := clampf(s0, s_min, s_max)
	var new_size := Vector2i(int(round(float(start_size.x) * s)), int(round(float(start_size.y) * s)))
	var c_start := Vector2(start_pos) + Vector2((1.0 - off.x) * float(start_size.x), (1.0 - off.y) * float(start_size.y))
	var new_pos := Vector2i((c_start - Vector2((1.0 - off.x) * float(new_size.x), (1.0 - off.y) * float(new_size.y))).round())
	return {"size": new_size, "pos": new_pos}

## 落窗薄封装（headless 守卫；先 size 后 position 防闪跳）
static func apply_resized_window(pos: Vector2i, size: Vector2i) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(pos)
