class_name EditorInteraction
extends Node
## 关卡编辑器·视图层：键鼠交互（规格 §7.1/§7.2）。复制自游戏 level_scene.gd 交互族
## （基线 b0cc039：R5 拾取 1166-1227 / R6 主视图交互 1268-1428）并改造：
## - 剥离 _input_locked/锐眼/聚焦/见证者机器（编辑器无此四者）；
## - 选择语义作用于「当前标签体素集」：占位集/尺寸/中心由编排层经 set_pick_context 注入（活引用）；
## - 不直接改模型：只发信号 dig_requested/add_requested/selection_changed/hover_changed/
##   place_target_changed，由 editor_main 落到 VoxelEditSession（规格 §6.2/§6.3）；
## - 新增添加模式两级拾取·体素优先·四分支（spec P1-1 重写口径，§7.2）；
## - 键盘（Ctrl+Z/Y/Shift+Z/Esc）归编排层 _unhandled_input（试玩态键位切换在编排层）。
## 相机：主视口 EDIT 透视轨道（修复批二 F1/F2，常量与口径见下方 :26-31 新注释块）；VIEW 只读面板
## 保持正交等轴测体系（ORTHO_DIST/相机 size/滚轮改 size，N 批「旋转缩放解耦」口径：包围球统一跨度、
## 与朝向无关）。⚠ 相机更新只在输入回调与构建路径，严禁 _process（坑 10）。
## 审查⑦回修 P1-1：轨道距离自适应 max(ORTHO_DIST, 包围球半径+1.0)——32³ 满块半径≈27.7>20 时
## 恒距会把最近角推到 near 平面之后（BoxMesh 背面剔除透见背景呈风筝形缺口），自适应后最近角
## 深度恒=r+1−r=1.0>near；小集（3³ r≈2.6）仍取 20 行为不变。
## 测试接缝：状态机以 cell 为入参的公开方法（stroke_begin/ctrl_click/right_delete/add_*）供无头直驱；
## gui_input 粘合层（事件→坐标→cell）由 T2-6 窗口走查验证。

signal dig_requested(cells: Array)            # 右键原地抬起：删除选中组（Array[Vector3i]）
signal add_requested(cells: Array)            # 添加模式放置：单击=1 格；拖动连放=整段合并（T5）
signal selection_changed                      # 选区变化（编排层刷新状态栏）
signal hover_changed(cell: Vector3i)          # 悬停格变化（NO_CELL=移出/拖拽让位）
signal place_target_changed(cell: Vector3i)   # 添加模式放置目标变化（NO_CELL=非法不预览）

## 相机：主视口 EDIT 透视轨道（修复批二 F1，Blender/3D Max 式标准工具视角：projection=PERSPECTIVE、
## fov 52、初始 yaw30°/pitch28°，滚轮推拉轨道距离 dist∈[min_dist, max_dist]，min_dist 与格集包围球
## 半径挂钩防穿模）；VIEW 只读面板保持原正交等轴测体系（ORTHO_DIST/相机 size/滚轮改 size）零改动。
## 修复批二 F2：look_target 恒=当前标签格集 AABB 中心（世界系，扣视图中心偏移）——相机注视点与取景
## 半径跟随格集实际位置，与容器尺寸无关（根治旧格群贴最小角被甩出视口）。⚠ 相机更新只在输入回调与
## 构建路径，严禁 _process（坑 10）。
const NO_CELL := Vector3i(-1, -1, -1)
const ORBIT_YAW0_DEG := 30.0
const ORBIT_PITCH0_DEG := 28.0
const ORBIT_SPEED := 0.005
const PITCH_LIMIT_DEG := 80.0
const PERSP_FOV_DEG := 52.0          # F1：主视口透视 fov（建议区间 50~55）
const PERSP_NEAR := 0.1
const PERSP_FIT_SAFETY := 1.15       # F1：初始 dist = 半径 / tan(fov/2) × 安全系数
const PERSP_ZOOM_IN := 0.9           # F1：滚轮推拉（dist×0.9 推近）
const PERSP_ZOOM_OUT := 1.1
const PERSP_DIST_MAX_MUL := 4.0      # 推远上限=拟合距离×4（与既有 ORTHO_SIZE_MAX_MUL 同量级）
const PERSP_MIN_MARGIN := 0.5        # 最近距离下限=半径+0.5（防相机进入包围球穿模）
const ORTHO_DIST := 20.0
const ORTHO_NEAR := 0.1
const ORTHO_FAR := 100.0
const ORTHO_ZOOM_IN := 0.9
const ORTHO_ZOOM_OUT := 1.1
const ORTHO_SIZE_MAX_MUL := 4.0
const VIEW_FIT_MARGIN := 24.0
const CLICK_SLOP_PX := 2.0

enum Mode { DIG, ADD }
## 绑定模式（T3 修复批）：EDIT=现有全交互；VIEW=只读预览（仅轨道旋转/滚轮缩放，零拾取零编辑信号）。
enum BindMode { EDIT, VIEW }
enum DragMode { NONE, STROKE, ORBIT, ADD_STROKE }

var _container: SubViewportContainer = null
var _viewport: SubViewport = null
var _camera: Camera3D = null
var _view: Node = null              # 当前 EditorVoxelView（编排层注入；视图层内部协作）
var _bind_mode: int = BindMode.EDIT
var _look_target: Vector3 = Vector3.ZERO   # 相机注视目标（EDIT 缺省 ZERO=既有行为不变；VIEW 注入集中心）
var _occupied: Dictionary = {}      # 当前标签体素集（活引用，编排层在标签切换/会话重建时注入）
var _pick_size: Vector3i = Vector3i(1, 1, 1)
var _pick_center: Vector3 = Vector3.ZERO
var _mode: int = Mode.DIG
var _selected: Dictionary = {}      # 选区：Vector3i → true
var _drag_mode: int = DragMode.NONE
var _left_pressed := false
var _middle_pressed := false
var _right_pressed := false
var _right_orbit := false
var _right_moved := 0.0
var _orbit_moved := 0.0
var _stroke_new_seen := false
var _stroke_start_cell := NO_CELL
var _last_motion_pos := Vector2.ZERO
var _orbit_yaw := deg_to_rad(ORBIT_YAW0_DEG)
var _orbit_pitch := deg_to_rad(ORBIT_PITCH0_DEG)
var _ortho_size := -1.0
var _ortho_floor := -1.0            # 审查回修批 P1-1：VIEW 可注入夹持下限（<0=回落 _fit_ortho_size 原口径）
var _dist := -1.0                   # F1：EDIT 透视轨道距离（<0=未初始化，按包围球拟合）
var _diameter := 0.0
var _pending_add: Dictionary = {}   # 拖动连放缓冲（T5：整段一个撤销单元）

# ---------- 装配与上下文 ----------
func bind(container: SubViewportContainer, viewport: SubViewport, camera: Camera3D, mode: int = BindMode.EDIT) -> void:
	_container = container
	_viewport = viewport
	_camera = camera
	_bind_mode = mode
	if _container != null:
		if _container.gui_input.is_connected(_on_gui_input):
			_container.gui_input.disconnect(_on_gui_input)   # 防重入双通道（T3：进出试玩反复 bind）
		_container.gui_input.connect(_on_gui_input)

## 解绑（T3）：断 gui_input 并清空引用/状态，退出试玩时调用。
func unbind() -> void:
	if _container != null and _container.gui_input.is_connected(_on_gui_input):
		_container.gui_input.disconnect(_on_gui_input)
	_container = null
	_viewport = null
	_camera = null
	_view = null
	_occupied = {}
	_diameter = 0.0
	_ortho_size = -1.0
	_ortho_floor = -1.0
	_dist = -1.0
	_drag_mode = DragMode.NONE
	_left_pressed = false
	_middle_pressed = false
	_right_pressed = false

func set_view(view: Node) -> void:
	_view = view

## 相机注视目标（T3 VIEW 注入集中心−视图偏移；EDIT 不调用→保持 ZERO 既有行为）。
func set_look_target(target: Vector3) -> void:
	_look_target = target

## 夹持下限注入（审查回修批 P1-1）：VIEW 播种时注入同源下限（包围球直径=零边距口径），令首次
## 拖拽/滚轮不被本层 24px 口径下限夹高（根除跳变）；<0 或 EDIT 不调用=回落 _fit_ortho_size 原行为。
func set_ortho_floor(floor_size: float) -> void:
	_ortho_floor = floor_size

## 从当前相机反解轨道位姿与 ortho 档位（T3：首次拖拽/滚轮零跳变）。
func sync_from_camera() -> void:
	if _camera == null:
		return
	var rel: Vector3 = _camera.position - _look_target
	var dist := rel.length()
	if dist > 0.001:
		var dir := rel / dist
		_orbit_yaw = atan2(dir.x, dir.z)
		_orbit_pitch = asin(clampf(dir.y, -1.0, 1.0))
	_ortho_size = _camera.size

## 占位集/尺寸/中心注入（活引用：Session.cells 原地增删后拾取即时生效）。
func set_pick_context(occupied: Dictionary, size: Vector3i, center: Vector3) -> void:
	_occupied = occupied
	_pick_size = size
	_pick_center = center
	_diameter = _sphere_diameter_of(occupied)

## F1 拟合有效直径（审查回修批 P1-1）：空集（_diameter≤0，当前标签无格）时以 block_size 对角线
## （容器包围球直径，取自 set_pick_context 注入的 _pick_size）代入——保证空标签取景距离落在容器外，
## 相机不钻入容器内部；非空集恒等于 _diameter（既有行为不变）。
func _fit_diameter() -> float:
	if _diameter > 0.0:
		return _diameter
	return Vector3(_pick_size).length()

func set_mode(add_mode: bool) -> void:
	_mode = Mode.ADD if add_mode else Mode.DIG
	clear_selection()
	_pending_add = {}
	if _view != null:
		_view.call("clear_place_preview")

## 取景：keep_zoom=false 重算初始档（标签切换/重建后），true 只更新直径并夹限（操作后）。
## F2：look_target 由编排层注入为格集 AABB 中心；本层只按直径更新 dist（EDIT）或 size（VIEW）。
func refresh_view(keep_zoom: bool = true) -> void:
	_diameter = _sphere_diameter_of(_occupied)
	if _bind_mode == BindMode.EDIT:
		if _dist <= 0.0 or not keep_zoom or _diameter <= 0.0:
			_dist = _fit_persp_dist(_fit_diameter())   # P1-1：空集按 block_size 对角线拟合（容器外）
	else:
		if _ortho_size <= 0.0 or not keep_zoom or _diameter <= 0.0:
			_ortho_size = _fit_ortho_size(_diameter)
	_update_camera()

func get_selected() -> Array:
	return _selected.keys()

# ---------- 相机（⚠ 仅输入回调与构建路径调用，坑 10） ----------
## EDIT=透视轨道（F1/F2）；VIEW=正交只读（零改动，仍用 _ortho_size/_ortho_floor 体系）。
func _update_camera() -> void:
	if _camera == null:
		return
	if _bind_mode == BindMode.VIEW:
		_update_camera_view()
		return
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = PERSP_FOV_DEG
	_camera.near = PERSP_NEAR
	# F1：far 随距离自适应（近处小集不浪费深度精度，远处大集不裁）——dist+包围球直径×3 + 10。
	_camera.far = maxf(100.0, _dist + _diameter * 3.0 + 10.0)
	var dist: float = _clamp_persp_dist(_dist)
	_camera.position = _look_target + dist * Vector3(
		sin(_orbit_yaw) * cos(_orbit_pitch),
		sin(_orbit_pitch),
		cos(_orbit_yaw) * cos(_orbit_pitch))
	_camera.look_at(_look_target, Vector3.UP)

## VIEW 正交轨道（T3/审查回修批 P1-1 体系原样保留）：距离自适应 max(ORTHO_DIST, 半径+1.0)，
## size 按 _ortho_size 夹持——VIEW 只读面板不受 F1 透视改动影响。
func _update_camera_view() -> void:
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = ORTHO_NEAR
	_camera.far = ORTHO_FAR
	var dist := maxf(ORTHO_DIST, _diameter * 0.5 + 1.0)
	var pos := _look_target + dist * Vector3(
		sin(_orbit_yaw) * cos(_orbit_pitch),
		sin(_orbit_pitch),
		cos(_orbit_yaw) * cos(_orbit_pitch))
	_camera.position = pos
	_camera.look_at(_look_target, Vector3.UP)
	if _ortho_size > 0.0 and _diameter > 0.0:
		_ortho_size = clampf(_ortho_size, _fit_ortho_floor(), _diameter * ORTHO_SIZE_MAX_MUL)
		_camera.size = _ortho_size

## F1：初始透视距离=包围球半径/tan(fov/2)×安全系数（半径=_diameter/2）；空集返回下限。
func _fit_persp_dist(d: float) -> float:
	if d <= 0.0:
		return _dist_floor()
	return maxf(_dist_floor(), (d * 0.5) / tan(deg_to_rad(PERSP_FOV_DEG) * 0.5) * PERSP_FIT_SAFETY)

## F1：最近距离下限=半径+余量（防穿模）；P1-1：空集以 block_size 对角线为有效直径代入，
## 下限≥容器半对角线+余量（相机恒在容器外）。
func _dist_floor() -> float:
	return _fit_diameter() * 0.5 + PERSP_MIN_MARGIN

## F1：推远上限=拟合距离×4（与 ORTHO_SIZE_MAX_MUL 同量级；下限恒 ≤ 上限）。
## P1-1：空集亦以 _fit_diameter() 参与，避免 0.5 下限口径把空集 dist 夹回容器内。
func _dist_ceiling() -> float:
	return maxf(_fit_persp_dist(_fit_diameter()), 1.0) * PERSP_DIST_MAX_MUL

## 轨道距离夹持（未初始化时先拟合；P1-1：空集按 _fit_diameter 拟合）。
func _clamp_persp_dist(dist: float) -> float:
	var d: float = dist if dist > 0.0 else _fit_persp_dist(_fit_diameter())
	return clampf(d, _dist_floor(), _dist_ceiling())

## 初始取景/缩放下限（N 批统一口径：跨度=包围球直径，与朝向无关；视口未布局兜底 d×2）。
func _fit_ortho_size(d: float) -> float:
	if d <= 0.0:
		return 0.0
	var vs := Vector2(_viewport.size) if _viewport != null else Vector2.ZERO
	if vs.y < 1.0 or vs.x < 1.0:
		return d * 2.0
	var span := Vector2(d, d)
	return maxf(span.x * vs.y / maxf(vs.x - 2.0 * VIEW_FIT_MARGIN, 1.0),
		span.y * vs.y / maxf(vs.y - 2.0 * VIEW_FIT_MARGIN, 1.0))

## 夹持下限（审查回修批 P1-1）：floor≥0 用注入的同源下限（VIEW 零边距口径=包围球直径），
## 否则回落本层 _fit_ortho_size 原口径。修复批二 F1 后仅 VIEW 正交分支消费（EDIT 走透视 _dist）。
func _fit_ortho_floor() -> float:
	return _ortho_floor if _ortho_floor >= 0.0 else _fit_ortho_size(_diameter)

func _sphere_diameter_of(cells: Dictionary) -> float:
	if cells.is_empty():
		return 0.0
	var mn := Vector3i(1 << 29, 1 << 29, 1 << 29)
	var mx := Vector3i(-(1 << 29), -(1 << 29), -(1 << 29))
	for c: Variant in cells:
		var p: Vector3i = c
		mn.x = mini(mn.x, p.x)
		mn.y = mini(mn.y, p.y)
		mn.z = mini(mn.z, p.z)
		mx.x = maxi(mx.x, p.x)
		mx.y = maxi(mx.y, p.y)
		mx.z = maxi(mx.z, p.z)
	return Vector3(Vector3(mx) - Vector3(mn) + Vector3.ONE).length()

# ---------- gui_input 粘合层（R6 :1268-1381 结构随迁，事件→状态机） ----------
func _on_gui_input(event: InputEvent) -> void:
	if _bind_mode == BindMode.VIEW:
		_on_gui_input_view(event)
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		_on_motion(mm.position)
		if _container != null:
			_container.accept_event()
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if mb.pressed:
			_on_wheel(mb.button_index == MOUSE_BUTTON_WHEEL_UP)
			if _container != null:
				_container.accept_event()
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_on_left_press(mb.position, mb.ctrl_pressed)
		elif _left_pressed:
			_on_left_release()
		if _container != null:
			_container.accept_event()
	elif mb.button_index == MOUSE_BUTTON_MIDDLE:
		if mb.pressed:
			_middle_pressed = true
			_drag_mode = DragMode.ORBIT
			_orbit_moved = 0.0
			_last_motion_pos = mb.position
		elif _middle_pressed:
			_middle_pressed = false
			_drag_mode = DragMode.NONE
		if _container != null:
			_container.accept_event()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			if _drag_mode == DragMode.NONE and not _left_pressed and not _middle_pressed:
				_right_pressed = true
				_right_moved = 0.0
				_right_orbit = false
				_drag_mode = DragMode.ORBIT
				_last_motion_pos = mb.position
		elif _right_pressed:
			_right_pressed = false
			_drag_mode = DragMode.NONE
			if not _right_orbit:
				_finish_right_delete()   # 右键原地抬起=删除选中组（R6 :1363-1381 分流）
		if _container != null:
			_container.accept_event()

func _on_motion(pos: Vector2) -> void:
	if _left_pressed or _middle_pressed or _right_pressed:
		_emit_hover(NO_CELL)   # 拖拽/划选中点光让位（§7.1）
	elif _mode == Mode.ADD:
		var target := _place_target_at(pos)
		place_target_changed.emit(target)
		_emit_hover(target)    # 添加模式悬停坐标=放置目标
	else:
		_emit_hover(_pick_at(pos))
	if _left_pressed and _mode == Mode.DIG and _drag_mode == DragMode.STROKE:
		var hit := _pick_at(pos)
		if hit != NO_CELL and not _selected.has(hit):   # 幂等追加（R6 :1280-1286）
			_select(hit, true)
			_stroke_new_seen = true
	elif _left_pressed and _mode == Mode.ADD and _drag_mode == DragMode.ADD_STROKE:
		var target2 := _place_target_at(pos)
		if target2 != NO_CELL and not _pending_add.has(target2):
			_pending_add[target2] = true
			place_target_changed.emit(target2)
	elif _drag_mode == DragMode.ORBIT and (_left_pressed or _middle_pressed or _right_pressed):
		if _right_pressed and not _left_pressed and not _middle_pressed:
			_right_moved += (pos - _last_motion_pos).length()
			if _right_moved <= CLICK_SLOP_PX and not _right_orbit:
				_last_motion_pos = pos
				return   # 未超阈值：仍是「原地右键点击」候选（R6 :1290-1294）
			_right_orbit = true
		var rel := pos - _last_motion_pos
		_orbit_moved += rel.length()
		_orbit_yaw -= rel.x * ORBIT_SPEED
		_orbit_pitch = clampf(_orbit_pitch + rel.y * ORBIT_SPEED,
			-deg_to_rad(PITCH_LIMIT_DEG), deg_to_rad(PITCH_LIMIT_DEG))
		_update_camera()
	_last_motion_pos = pos

## VIEW 只读预览粘合层（T3）：仅轨道旋转（左/中/右键拖拽）与滚轮缩放；不 raycast、不改会话、
## 不发任何编辑信号、不产生选区。滚轮复用 _on_wheel；拖拽直接改 yaw/pitch 后 _update_camera。
func _on_gui_input_view(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null:
		if _drag_mode == DragMode.ORBIT and (_left_pressed or _middle_pressed or _right_pressed):
			var rel: Vector2 = mm.position - _last_motion_pos
			_orbit_yaw -= rel.x * ORBIT_SPEED
			_orbit_pitch = clampf(_orbit_pitch + rel.y * ORBIT_SPEED,
				-deg_to_rad(PITCH_LIMIT_DEG), deg_to_rad(PITCH_LIMIT_DEG))
			_update_camera()
		_last_motion_pos = mm.position
		if _container != null:
			_container.accept_event()
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if mb.pressed:
			_on_wheel(mb.button_index == MOUSE_BUTTON_WHEEL_UP)
			if _container != null:
				_container.accept_event()
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		_left_pressed = mb.pressed
	elif mb.button_index == MOUSE_BUTTON_MIDDLE:
		_middle_pressed = mb.pressed
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_right_pressed = mb.pressed
	if mb.pressed:
		_drag_mode = DragMode.ORBIT
		_last_motion_pos = mb.position
	elif not _left_pressed and not _middle_pressed and not _right_pressed:
		_drag_mode = DragMode.NONE
	if _container != null:
		_container.accept_event()

func _on_wheel(up: bool) -> void:
	if _bind_mode == BindMode.EDIT:
		if _diameter <= 0.0:
			return
		_dist = _clamp_persp_dist(_dist * (PERSP_ZOOM_IN if up else PERSP_ZOOM_OUT))
		_update_camera()
		return
	# VIEW：正交 size 缩放（原体系零改动）
	if _diameter <= 0.0 or _ortho_size <= 0.0:
		return
	_ortho_size = clampf(
		_ortho_size * (ORTHO_ZOOM_IN if up else ORTHO_ZOOM_OUT),
		_fit_ortho_floor(), _diameter * ORTHO_SIZE_MAX_MUL)
	_update_camera()

func _on_left_press(pos: Vector2, ctrl: bool) -> void:
	_left_pressed = true
	_orbit_moved = 0.0
	_stroke_new_seen = false
	_last_motion_pos = pos
	if _mode == Mode.ADD:
		var target := _place_target_at(pos)
		if target != NO_CELL:
			_drag_mode = DragMode.ADD_STROKE
			_pending_add = {target: true}
			place_target_changed.emit(target)
		else:
			_drag_mode = DragMode.ORBIT   # 非法格起手=旋转
		return
	var hit := _pick_at(pos)
	if hit != NO_CELL:
		if ctrl:
			_select(hit, true)            # Ctrl+点击 additive 切换（R6 :1326-1329）
			_drag_mode = DragMode.NONE
		else:
			_drag_mode = DragMode.STROKE
			_stroke_start_cell = hit
			if not _selected.has(hit):    # P3-1：按下扫过已选格不 toggle 取消（R6 :1333-1336）
				_select(hit, true)
	else:
		_drag_mode = DragMode.ORBIT

func _on_left_release() -> void:
	_left_pressed = false
	if _drag_mode == DragMode.STROKE:
		if not _stroke_new_seen:
			clear_selection()             # 全程未划出新格→单选替换（R6 :1342-1345）
			_select(_stroke_start_cell, false)
	elif _drag_mode == DragMode.ORBIT and _orbit_moved < CLICK_SLOP_PX:
		clear_selection()                 # 空白单击=清空选区（R6 :1346-1347）
	elif _drag_mode == DragMode.ADD_STROKE:
		if not _pending_add.is_empty():
			add_requested.emit(_pending_add.keys())   # 整段合并一次发包（T5）
		_pending_add = {}
	_drag_mode = DragMode.NONE

# ---------- 选区（R6 :1029-1060 语义随迁，高亮经注入的视图执行） ----------
func _select(cell: Vector3i, additive: bool) -> void:
	if additive:
		if _selected.has(cell):
			_selected.erase(cell)
			if _view != null:
				_view.call("set_voxel_highlight", cell, false)
		else:
			_selected[cell] = true
			if _view != null:
				_view.call("set_voxel_highlight", cell, true)
	else:
		clear_selection()
		_selected[cell] = true
		if _view != null:
			_view.call("set_voxel_highlight", cell, true)
	selection_changed.emit()

func clear_selection() -> void:
	for cell_v: Variant in _selected.keys():
		if _view != null:
			_view.call("set_voxel_highlight", cell_v, false)
	_selected.clear()
	selection_changed.emit()

func _finish_right_delete() -> void:
	if _selected.is_empty():
		return   # 空选不发包（操作提示由常驻 ModeLabel 承担，与游戏划选话术不同源）
	var cells: Array = _selected.keys()
	dig_requested.emit(cells)
	clear_selection()

func _emit_hover(cell: Vector3i) -> void:
	hover_changed.emit(cell)

# ---------- 拾取包装（坐标→SubViewport 坐标→相机射线，R6 :1384-1398 随迁） ----------
func _pick_at(pos: Vector2) -> Vector3i:
	if _camera == null or _occupied.is_empty():
		return NO_CELL
	var vp_pos := _to_viewport_pos(pos)
	return ray_to_cell(_camera.project_ray_origin(vp_pos), _camera.project_ray_normal(vp_pos),
		_occupied, _pick_size, _pick_center)

func _place_target_at(pos: Vector2) -> Vector3i:
	if _camera == null:
		return NO_CELL
	var vp_pos := _to_viewport_pos(pos)
	return pick_place_cell(_camera.project_ray_origin(vp_pos), _camera.project_ray_normal(vp_pos),
		_occupied, _pick_size, _pick_center)

func _to_viewport_pos(local: Vector2) -> Vector2:
	if _container != null and _container.stretch:
		return local / float(_container.stretch_shrink)
	if _viewport != null and _container != null and _container.size.x > 0.0 and _container.size.y > 0.0:
		return Vector2(local.x * _viewport.size.x / _container.size.x, local.y * _viewport.size.y / _container.size.y)
	return local

# ---------- 测试接缝（无头直驱；正常路径经 gui_input 粘合层） ----------
func stroke_begin(cell: Vector3i) -> void:
	_drag_mode = DragMode.STROKE
	_stroke_start_cell = cell
	_stroke_new_seen = false
	_left_pressed = true
	if not _selected.has(cell):
		_select(cell, true)

func stroke_move(cell: Vector3i) -> void:
	if cell != NO_CELL and not _selected.has(cell):
		_select(cell, true)
		_stroke_new_seen = true

func stroke_end_single() -> void:
	# 测试接缝语义=「按单选收尾」：无条件 clear+select（gui 实路径的「未划出新格才单选替换」
	# 条件判断由 _on_left_release 承载，此处不复刻——接缝只锁状态机终态，供断言链稳定消费）。
	clear_selection()
	_select(_stroke_start_cell, false)
	_left_pressed = false
	_drag_mode = DragMode.NONE

func ctrl_click(cell: Vector3i) -> void:
	_select(cell, true)

func right_delete() -> void:
	_finish_right_delete()

func add_begin(cell: Vector3i) -> void:
	_drag_mode = DragMode.ADD_STROKE
	_left_pressed = true
	_pending_add = {cell: true}

func add_move(cell: Vector3i) -> void:
	if cell != NO_CELL:
		_pending_add[cell] = true

func add_end() -> void:
	if not _pending_add.is_empty():
		add_requested.emit(_pending_add.keys())
	_pending_add = {}
	_left_pressed = false
	_drag_mode = DragMode.NONE

# ==================== R5 拾取数学（static，无头可测） ====================

## R5 原样复制（level_scene.gd:1166-1215）：slab 射线-AABB 最近命中，未命中 NO_CELL。
static func ray_to_cell(origin: Vector3, dir: Vector3, cells: Dictionary, size: Vector3i, center: Vector3 = Vector3.INF) -> Vector3i:
	var d := dir
	if d.length_squared() < 1e-12 or cells.is_empty():
		return NO_CELL
	d = d.normalized()
	var ctr := center
	if ctr == Vector3.INF:
		ctr = cells_center(cells)
	var best_t := INF
	var best := NO_CELL
	for c: Variant in cells:
		var cell := Vector3i(c)
		if cell.x < 0 or cell.x >= size.x or cell.y < 0 or cell.y >= size.y or cell.z < 0 or cell.z >= size.z:
			continue
		var bmin: Vector3 = Vector3(cell) - ctr
		var bmax: Vector3 = bmin + Vector3.ONE
		var t0 := -INF
		var t1 := INF
		var ok := true
		for axis: int in 3:
			var o := origin[axis]
			var dd := d[axis]
			var lo := bmin[axis]
			var hi := bmax[axis]
			if absf(dd) < 1e-12:
				if o < lo or o > hi:
					ok = false
					break
			else:
				var inv := 1.0 / dd
				var ta := (lo - o) * inv
				var tb := (hi - o) * inv
				if ta > tb:
					var tmp := ta
					ta = tb
					tb = tmp
				t0 = maxf(t0, ta)
				t1 = minf(t1, tb)
				if t0 > t1:
					ok = false
					break
		if not ok or t1 < 0.0:
			continue
		var t_enter := maxf(t0, 0.0)
		if t_enter < best_t:
			best_t = t_enter
			best = cell
	return best

## R5 扩展（规格 R5 改造要点「返回命中轴与方向符号以推面法向」）：同数学返回
## {cell, axis, sign}——axis=进入轴（t0 最大者的轴），sign=射线方向在该轴符号；
## 命中面外法向 = 该轴单位向量 × (−sign)。未命中 {NO_CELL, -1, 0}。
static func ray_to_hit(origin: Vector3, dir: Vector3, cells: Dictionary, size: Vector3i, center: Vector3 = Vector3.INF) -> Dictionary:
	var d := dir
	if d.length_squared() < 1e-12 or cells.is_empty():
		return {"cell": NO_CELL, "axis": -1, "sign": 0}
	d = d.normalized()
	var ctr := center
	if ctr == Vector3.INF:
		ctr = cells_center(cells)
	var best_t := INF
	var best := NO_CELL
	var best_axis := -1
	for c: Variant in cells:
		var cell := Vector3i(c)
		if cell.x < 0 or cell.x >= size.x or cell.y < 0 or cell.y >= size.y or cell.z < 0 or cell.z >= size.z:
			continue
		var bmin: Vector3 = Vector3(cell) - ctr
		var bmax: Vector3 = bmin + Vector3.ONE
		var t0 := -INF
		var t1 := INF
		var enter_axis := -1
		var ok := true
		for axis: int in 3:
			var o := origin[axis]
			var dd := d[axis]
			var lo := bmin[axis]
			var hi := bmax[axis]
			if absf(dd) < 1e-12:
				if o < lo or o > hi:
					ok = false
					break
			else:
				var inv := 1.0 / dd
				var ta := (lo - o) * inv
				var tb := (hi - o) * inv
				if ta > tb:
					var tmp := ta
					ta = tb
					tb = tmp
				if ta > t0:
					t0 = ta
					enter_axis = axis
				t1 = minf(t1, tb)
				if t0 > t1:
					ok = false
					break
		if not ok or t1 < 0.0:
			continue
		var t_enter := maxf(t0, 0.0)
		if t_enter < best_t:
			best_t = t_enter
			best = cell
			best_axis = enter_axis
	if best == NO_CELL:
		return {"cell": NO_CELL, "axis": -1, "sign": 0}
	return {"cell": best, "axis": best_axis, "sign": signi(d[best_axis])}

## R5 原样复制（level_scene.gd:1218-1227）。
static func cells_center(cells: Dictionary) -> Vector3:
	var mn := Vector3i(1 << 29, 1 << 29, 1 << 29)
	var mx := Vector3i(-(1 << 29), -(1 << 29), -(1 << 29))
	for c: Variant in cells:
		var p := Vector3i(c)
		mn.x = mini(mn.x, p.x)
		mn.y = mini(mn.y, p.y)
		mn.z = mini(mn.z, p.z)
		mx.x = maxi(mx.x, p.x)
		mx.y = maxi(mx.y, p.y)
		mx.z = maxi(mx.z, p.z)
	if mx.x < 0:
		return Vector3.ZERO
	return (Vector3(mn) + Vector3(mx) + Vector3.ONE) * 0.5

## AABB slab 求交（盒已含 center 平移，世界系 [bmin,bmax]）：返回 {hit, t_enter, axis}；
## 起点在盒内时 t_enter=0；axis=进入轴（t0 最大者），全平行命中时 -1。
static func ray_box_entry(origin: Vector3, dir: Vector3, bmin: Vector3, bmax: Vector3) -> Dictionary:
	var d := dir.normalized()
	var t0 := -INF
	var t1 := INF
	var enter_axis := -1
	for axis: int in 3:
		var dd := d[axis]
		var lo := bmin[axis]
		var hi := bmax[axis]
		if absf(dd) < 1e-12:
			if origin[axis] < lo or origin[axis] > hi:
				return {"hit": false, "t_enter": 0.0, "axis": -1}
		else:
			var inv := 1.0 / dd
			var ta := (lo - origin[axis]) * inv
			var tb := (hi - origin[axis]) * inv
			if ta > tb:
				var tmp := ta
				ta = tb
				tb = tmp
			if ta > t0:
				t0 = ta
				enter_axis = axis
			t1 = minf(t1, tb)
			if t0 > t1:
				return {"hit": false, "t_enter": 0.0, "axis": -1}
	if t1 < 0.0:
		return {"hit": false, "t_enter": 0.0, "axis": -1}
	return {"hit": true, "t_enter": maxf(t0, 0.0), "axis": enter_axis}

## 添加模式两级拾取·体素优先·四分支（规格 §7.2 P1-1 口径，唯一确定规则）：
## 第一级（分支1）：对当前体素集 ray_to_hit——命中界内已有体素 → 沿命中面外法向取相邻格；
##   相邻格越界或已有体素 → 拒绝（最近命中语义下外扩外壳格恒先于内部格命中，故第一级只需体素集）。
## 第二级（分支2/3）：第一级未命中才进空域判定——
##   分支2 射线与 block_size 包围盒有交 → 入射首格直接放置（该格必空：有体素第一级必已命中；
##     入射点沿射线方向再进 1e-4 防边界 floor 落到盒外）；
##   分支3 包围盒无交但与外扩 1 格外壳盒有交 → 外壳格沿进入面内法向折算相邻界内格；
##     折算格越界或已有体素 → 拒绝（规格明文；几何上环带斜射线的折算落点均越界，按规格拒绝）；
##   分支4 全未命中 → 拒绝（NO_CELL）。
## 空集起步自洽（规格 §7.2 末条）：分支2 的入射首格 = 分支3 意义上的「外壳格内法向相邻界内格」，
## 两口径落点同格，界内必空故必然可放。
static func pick_place_cell(origin: Vector3, dir: Vector3, occupied: Dictionary, size: Vector3i, center: Vector3) -> Vector3i:
	var d := dir
	if d.length_squared() < 1e-12:
		return NO_CELL
	d = d.normalized()
	# 第一级：体素优先
	var hit := ray_to_hit(origin, d, occupied, size, center)
	if hit["cell"] != NO_CELL:
		var axis: int = hit["axis"]
		if axis < 0:
			return NO_CELL
		var n := Vector3i.ZERO
		n[axis] = -int(hit["sign"])   # 面外法向 = 射线方向符号取反
		var target: Vector3i = hit["cell"] + n
		if target.x < 0 or target.x >= size.x or target.y < 0 or target.y >= size.y or target.z < 0 or target.z >= size.z:
			return NO_CELL
		if occupied.has(target):
			return NO_CELL
		return target
	# 第二级：空域判定（block 包围盒 [0,size]-center）
	var bmin := Vector3.ZERO - center
	var bmax := Vector3(size) - center
	var inner: Dictionary = ray_box_entry(origin, d, bmin, bmax)
	if inner["hit"]:
		var p := origin + d * (float(inner["t_enter"]) + 1e-4) + center
		var cell := Vector3i(floori(p.x), floori(p.y), floori(p.z))
		cell = Vector3i(clampi(cell.x, 0, size.x - 1), clampi(cell.y, 0, size.y - 1), clampi(cell.z, 0, size.z - 1))
		if occupied.has(cell):
			return NO_CELL   # 理论不可达（有体素第一级必命中）；防御
		return cell
	# 分支3：外扩 1 格外壳
	var outer: Dictionary = ray_box_entry(origin, d, bmin - Vector3.ONE, bmax + Vector3.ONE)
	if not outer["hit"]:
		return NO_CELL   # 分支4
	var oaxis: int = outer["axis"]
	if oaxis < 0:
		return NO_CELL
	var q := origin + d * (float(outer["t_enter"]) + 1e-4) + center
	var shell := Vector3i(floori(q.x), floori(q.y), floori(q.z))
	var inward := 0
	if shell[oaxis] < 0:
		inward = 1
	elif shell[oaxis] >= size[oaxis]:
		inward = -1
	else:
		return NO_CELL   # 切向掠入（进入轴上外壳格并不在外侧）→ 拒绝
	var target3 := shell
	target3[oaxis] += inward
	if target3.x < 0 or target3.x >= size.x or target3.y < 0 or target3.y >= size.y or target3.z < 0 or target3.z >= size.z:
		return NO_CELL
	if occupied.has(target3):
		return NO_CELL
	return target3
