class_name PointCloudViewer
extends Control
## 中央点云查看器组件（批次 H 图鉴接入；批次 J4-2 起结算场景亦复用，删除原内联实现）。
## 依据 spec 4.6/9.1：
## MultiMesh 点渲染——实例变换只在 build() 时写入一次（数万点），旋转/缩放作用于
## pivot/camera 节点 transform，不逐实例更新，面向图鉴 360° 查看；
## 交互：左键拖拽绕 Y 旋转（+X 轻度俯仰，夹紧防翻转）+ 滚轮缩放（限幅）；
## 降级：pointcloud 为 null/空/类型不符 → 显示「点云加载失败」占位，不报错不崩溃。
## 逐实例可调参数（J4-2 @export 化，避免影响图鉴默认行为，各场景按实例设置）：
##   camera_distance（图鉴默认 3.2 / 结算 2.8 略近显大）、point_size（默认 0.02，见下限档）、
##   tint_color + tint_strength（金黄覆盖色 lerp，图鉴/结算设 #F5C542；alpha=0 不 tint）。
## 适配尺度/点尺寸口径与批次 F 结算原实现保持一致（对角线约 2.2、点 0.02 量级）。
## O批（2026-09-10 用户反馈⑦+①）：点云圆点化+尺寸调档——方块点网格废止，改 QuadMesh
##   圆点面片（4 顶点）+ 手动 billboard（shader 顶点阶段剥离 model 旋转、按实例世界原点在
##   视空间展开=任意轨道视角恒面向相机，兼容性渲染器零 render_mode 依赖）+ fragment 圆盘
##   alpha（UV 距心 smoothstep 软边缘）；新增 DOT_SIZE_MIN 世界尺寸下限档 ∈[0.010,0.015] 定
##   0.012——图鉴/结算实设 0.005（catalog_scene:418 / settle_scene:73 字面量，本组件外）经
##   build() 下限同源上调，亚像素噪点团（每点约 0.9px 抖动噪点）根因消除；高于下限的实例档
##   不受限（单向下限）。M 批遗留「0.006~0.007 更颗粒」口径一并废止，走查定稿留痕。
## O批（2026-09-10 用户反馈⑦「鼠标与点云建模交互去掉」）：M-Ga/N6 点云悬停涟漪交互整套移除
##   （其内嵌 shader/专用 uniform/状态推进/命中拾取/uniform 写入方法/证据链钩子/debug 注入
##   钩子与 _process 逐帧悬停判定全删，符号级断言见涟漪判定用例（O批：悬停交互移除））；
##   **拖拽旋转（rotate_by）与滚轮缩放（zoom_by）保留**（Q&A 13 玩家可旋转既有确认需求）。材质显示口径不回退：ShaderMaterial unshaded + COLOR 逐实例色透传
##   （274085a 黑膜修复口径）+ u_fallback_color 兜底。

const FIT_SIZE := 2.2            # 点云适配后包围盒对角线长度（与结算实现同口径）
const DEFAULT_DISTANCE := 3.2    # 缺省相机视距（camera_distance 导出项的默认回退值）
const MIN_DISTANCE := 0.8        # 缩放下限（最近）
const MAX_DISTANCE := 8.0        # 缩放上限（最远）
const DEFAULT_POINT_SIZE := 0.02 # 缺省点尺寸（point_size 导出项默认；build 经 DOT_SIZE_MIN 下限）
const DOT_SIZE_MIN := 0.012      # O批：圆点世界尺寸下限档（0.010~0.015 起步走查定 0.012；
                                 # 0.005 亚像素噪点档废止——图鉴金噪点+结算建模颗粒感共同根因）
const DEFAULT_TINT_STRENGTH := 0.85  # 缺省 tint 混合强度（批次 J 计划定值；J5-2 走查后微调）
const TILT_LIMIT_DEG := 75.0     # 俯仰夹紧（防翻转过顶）
## M-Hb 走查 NG 回修（2026-09-08）：初始视角改 3/4 等轴测风——历史口径 rot=0 正面看，
## 扁长构件（河姆渡条形 y 仅 ±0.1）初始态呈「一条横带」（J6 12_catalog_ch1.png 即已如此，
## M-Ga/M-Hb 复现），无建模观感。偏航 30°+俯仰 22° 后顶面结构可辨，图鉴/结算两处受益。
const INIT_YAW_DEG := 30.0       # 初始偏航（绕 Y）
const INIT_TILT_DEG := 22.0      # 初始俯仰（轻度，<TILT_LIMIT）
const FAIL_TEXT := "点云加载失败"

## O批点云圆点着色器（内嵌，避免新增 shader 文件；_get_cloud_shader() 懒共享单实例）。
## render_mode unshaded（无光环境直接显色，274085a 口径）+ blend_mix（圆盘软边缘前提）；
## vertex 阶段手动 billboard：以实例世界原点（MODEL_MATRIX[3]，含 MultiMesh 逐实例变换与
## pivot 轨道旋转）为锚，把 model→view 旋转部分替换为恒等——面片在视空间 XY 展开，任意
## 轨道视角下恒面向相机（不依赖 billboard_enabled 与 MultiMesh 的兼容性组合）；
## fragment 阶段圆盘 alpha（UV 距心 smoothstep 软边缘）× 逐实例 α（v_col.a，供覆盖层
## 失配回退淡出复用同源 shader）；ALBEDO = 逐实例色（u_use_vertex_color=1）或统一回退色
##（=0，等价旧 albedo 兜底）。
const CLOUD_SHADER_CODE := "
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled;
uniform float u_use_vertex_color = 1.0;
uniform vec4 u_fallback_color = vec4(1.0);
varying vec4 v_col;
void vertex() {
	v_col = COLOR;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(1.0, 0.0, 0.0, 0.0),
		vec4(0.0, 1.0, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), MODEL_MATRIX[3]);
}
void fragment() {
	float disc = 1.0 - smoothstep(0.36, 0.5, length(UV - vec2(0.5)));
	ALBEDO = mix(u_fallback_color.rgb, v_col.rgb, u_use_vertex_color);
	ALPHA = disc * v_col.a;
}
"

## 当前绕 Y 旋转角（度）。直接赋值也会即时应用到视图。
@export var rot_y_deg: float = 0.0:
	set(v):
		rot_y_deg = v
		_apply_view()

## 相机视距（J4-2 @export 化）：默认 DEFAULT_DISTANCE 保图鉴视角不变；结算实例设 2.8 略近显大。
@export var camera_distance: float = DEFAULT_DISTANCE
## 点尺寸（J4-2 @export 化）：圆点面片边长（世界单位），build 经 DOT_SIZE_MIN 单向下限
## （O批：图鉴/结算实设 0.005 上调至下限档，消除亚像素噪点团）。
@export var point_size: float = DEFAULT_POINT_SIZE
## tint 覆盖色（J4-2 @export 化，J5-2 复用）：alpha=0 表示不 tint（数据原色）；
## 金黄场景实例设 Color(0.96, 0.77, 0.26, 1)（#F5C542，§0.5）。
@export var tint_color: Color = Color(1, 1, 1, 0)
## tint 混合强度（逐实例色 lerp 到 tint_color 的系数）。计划定值 0.85，TODO(J5-2) 走查后微调。
@export var tint_strength: float = DEFAULT_TINT_STRENGTH

var _pivot: Node3D = null            # 旋转载体（整棵子树转，点实例 transform 不动）
var _cam: Camera3D = null
var _viewport_box: SubViewportContainer = null
var _fail_label: Label = null
var _rot_x_deg: float = 0.0          # 轻度俯仰（拖拽 dy，夹紧）
var _distance: float = DEFAULT_DISTANCE
var _dragging: bool = false
var _instance_count: int = 0
var _cloud_mat: ShaderMaterial = null   # 当前点云材质（clear 时置空；测试/走查证据链钩子）

static var _cloud_shader: Shader = null  # 圆点 shader 懒共享（避免每次 build 重复编译）

func _init() -> void:
	# 批次 Z（Z6-P1-1，spec §6）：点云根挂拖窗豁免契约 meta("interactive")——本组件
	# mouse_filter=STOP + _gui_input 自持拖拽旋转/滚轮缩放，无 meta 时 main._input 命中
	# 失败即 _win_dragging=true → 图鉴/结算「按住点云拖动（意图旋转）」连带拖走窗口。
	# 契约键与 talk_scene.tscn 根/WitnessPortrait（metadata/interactive=true）同源，
	# _init 置位保证未入树（无头直测 new()）与入树两态一致。
	set_meta("interactive", true)

func _ready() -> void:
	# 自身 STOP：接收拖拽/滚轮并吃掉事件，不干扰容器内其他控件（子控件 IGNORE 不遮挡）
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 实例级视距（J4-2 @export）：入树时按 camera_distance 初始化（set 早于 add_child 生效）
	_distance = camera_distance
	# 已入树（_ready 阶段）：set_anchors_preset 只重设 anchors、offsets 被改写以维持当前
	# 矩形 → 0 尺寸控件保持塌缩（2026-08-27 走查缺陷：viewer=(0,0)、SubViewport=2x2）。
	# set_anchors_and_offsets_preset 同时重置 anchors+offsets，入树前后均正确铺满父容器。
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ensure_fail_label()

## 圆点 shader 懒共享单实例（build 可能多次调用，避免重复编译）。
static func _get_cloud_shader() -> Shader:
	if _cloud_shader == null:
		var sh := Shader.new()
		sh.code = CLOUD_SHADER_CODE
		_cloud_shader = sh
	return _cloud_shader

## 载入点云数据（PointCloudData）。重复调用=切换数据（先清旧，视角复位重看）。
## 数据缺失走降级占位（不抛错）。
func build(pointcloud: Resource) -> void:
	clear()
	var data := pointcloud as PointCloudData
	if data == null or data.points.is_empty():
		_show_fail()
		return
	_ensure_scene()
	var pts := data.points
	var n := pts.size()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# O批圆点化：QuadMesh（4 顶点）替代方块点网格；点径经 DOT_SIZE_MIN 单向
	# 下限（图鉴/结算实设 0.005 同源上调；备选极小 SphereMesh 高段数×数万点性能红线否决）。
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * maxf(point_size, DOT_SIZE_MIN)
	# 材质：内嵌圆点 ShaderMaterial——render_mode unshaded（等价旧 SHADING_MODE_UNSHADED，
	# 无光环境直接显色，2026-08-27 走查黑块修复口径）；逐实例色经 COLOR→ALBEDO 透传（等价
	# 旧 vertex_color_use_as_albedo=true，274085a 不回退）；billboard/圆盘在 shader 内完成
	#（CPU 每帧零工作——O批移除涟漪后本组件无 _process）。
	var mat := ShaderMaterial.new()
	mat.shader = _get_cloud_shader()
	quad.material = mat
	mm.mesh = quad
	var use_color: bool = data.colors.size() == n
	mm.use_colors = use_color  # 须在 instance_count 之前设置
	mm.instance_count = n
	# 金黄 tint（J4-2 @export 接口，J5-2 复用）：与逐实例色兼容——
	# 有逐实例色时 build 阶段把每色 lerp 向 tint（shader COLOR 透传显示，274085a 口径不变）；
	# 无逐实例色时 tint 走 u_fallback_color（shader ALBEDO 兜底，等价旧 albedo_color=tint）。
	var use_tint: bool = tint_color.a > 0.0
	mat.set_shader_parameter("u_use_vertex_color", 1.0 if use_color else 0.0)
	mat.set_shader_parameter("u_fallback_color",
		tint_color if (use_tint and not use_color) else Color(1, 1, 1, 1))
	var sf := FIT_SIZE / maxf(data.aabb_size.length(), 0.001)
	for i: int in n:
		mm.set_instance_transform(i, Transform3D(Basis(), (pts[i] - data.aabb_center) * sf))
		if use_color:
			var c := data.colors[i]
			if use_tint:
				c = c.lerp(tint_color, tint_strength)
			mm.set_instance_color(i, c)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "PointCloud"
	mmi.multimesh = mm
	_pivot.add_child(mmi)
	_instance_count = n
	_cloud_mat = mat
	reset_view()  # 每次选中新文物从正面视角看起

## 清空点云与降级占位（实例数归 0）。
func clear() -> void:
	_instance_count = 0
	_pivot = null
	_cam = null
	_cloud_mat = null
	if _viewport_box != null and is_instance_valid(_viewport_box):
		_viewport_box.queue_free()
	_viewport_box = null
	if _fail_label != null and is_instance_valid(_fail_label):
		_fail_label.visible = false

func get_instance_count() -> int:
	return _instance_count

## 测试/调试钩子：当前点云 mesh surface 0 的材质（无点云/未构建返回 null）。
## build/clear 维护 _pivot 指向当前子树，无 queue_free 残留歧义。
func get_cloud_material() -> Material:
	if _pivot == null or not is_instance_valid(_pivot):
		return null
	var mmi := _pivot.get_node_or_null("PointCloud") as MultiMeshInstance3D
	if mmi == null or mmi.multimesh == null or mmi.multimesh.mesh == null:
		return null
	var mesh := mmi.multimesh.mesh as Mesh
	if mesh.get_surface_count() == 0:
		return null
	return mesh.surface_get_material(0)

func set_rot_y_deg(deg: float) -> void:
	rot_y_deg = deg  # 走属性 setter → _apply_view

## 拖拽增量：dx 绕 Y 旋转，dy 轻度俯仰（夹紧）。
func rotate_by(dx_deg: float, dy_deg: float) -> void:
	rot_y_deg += dx_deg
	_rot_x_deg = clampf(_rot_x_deg + dy_deg, -TILT_LIMIT_DEG, TILT_LIMIT_DEG)
	_apply_view()

## 缩放：factor>1 拉近（滚轮上），<1 远离；限幅防穿模/飘远。
func zoom_by(factor: float) -> void:
	if factor <= 0.0:
		return
	_distance = clampf(_distance / factor, MIN_DISTANCE, MAX_DISTANCE)
	_apply_view()

func reset_view() -> void:
	rot_y_deg = INIT_YAW_DEG   # M-Hb：初始 3/4 视角（正面=横带缺陷，见 INIT_YAW_DEG 注）
	_rot_x_deg = INIT_TILT_DEG
	_distance = camera_distance  # 复位到本实例缺省视距（J4-2 @export，图鉴=DEFAULT_DISTANCE）
	_apply_view()

## 旋转/缩放只改节点 transform（MultiMesh 实例数组保持只读，性能口径见类注释）。
func _apply_view() -> void:
	if _pivot != null and is_instance_valid(_pivot):
		_pivot.rotation_degrees = Vector3(_rot_x_deg, rot_y_deg, 0.0)
	if _cam != null and is_instance_valid(_cam):
		_cam.position = Vector3(0.0, 0.0, _distance)

## 左键拖拽旋转 + 滚轮缩放（鼠标口径；手势缩放后续批次经 GestureBridge 接入）。
## O批：悬停交互移除后本处理器为唯一输入通道（拖拽/缩放保留，Q&A 13）。
func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		_dragging = mb.pressed
		accept_event()
		return
	if mb != null and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(1.1)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / 1.1)
			accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		rotate_by(motion.relative.x * 0.5, motion.relative.y * 0.2)
		accept_event()

## 3D 场景骨架：SubViewport（透明底）+ 相机 + 旋转 pivot。
func _ensure_scene() -> void:
	if _viewport_box != null and is_instance_valid(_viewport_box):
		return
	_viewport_box = SubViewportContainer.new()
	_viewport_box.name = "CloudContainer"
	_viewport_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)  # 此时未入树，等价 offset 归零，统一用重置型 API
	_viewport_box.stretch = true
	_viewport_box.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 输入归根控件处理
	var vp := SubViewport.new()
	vp.name = "CloudViewport"
	vp.transparent_bg = true
	var world := Node3D.new()
	world.name = "CloudWorld"
	_cam = Camera3D.new()
	_cam.position = Vector3(0.0, 0.0, camera_distance)
	# M-Hb 走查回修（2026-09-08）：默认 vfov 75 下云仅占视口约 22%（探针实测：视口 737px、
	# 云带约 180px）——收 45° 后占比倍增且更接近等轴测「模型感」（m06 参考图口径）。
	_cam.fov = 45.0
	world.add_child(_cam)
	_pivot = Node3D.new()
	_pivot.name = "CloudPivot"
	world.add_child(_pivot)
	vp.add_child(world)
	_viewport_box.add_child(vp)
	add_child(_viewport_box)

## 降级占位：数据缺失时可见（fail-safe，不报错）。
func _ensure_fail_label() -> void:
	if _fail_label != null and is_instance_valid(_fail_label):
		return
	_fail_label = Label.new()
	_fail_label.name = "FailLabel"
	_fail_label.text = I18n.t(FAIL_TEXT)   # I18n：显示点 t()（zh 直通/en 命中词条）
	_fail_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)  # 同上：重置 anchors+offsets，入树后严格居中
	_fail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fail_label.visible = false
	add_child(_fail_label)

func _show_fail() -> void:
	_ensure_fail_label()
	_fail_label.visible = true
