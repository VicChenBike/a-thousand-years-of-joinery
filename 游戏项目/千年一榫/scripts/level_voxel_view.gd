class_name LevelVoxelView
extends Node3D
## 关卡体素渲染辅助（批次 D）：把格式 A 体素坐标数组渲染为等距 3D 小方块。
## 关卡场景三视图（TargetView/JoinView/MainView）各挂一个实例。
## 体素包围盒中心自动平移到本节点原点，便于相机固定等距视角对准原点。
## 批次 E 扩展：cell→节点映射（挖除交互按格索引），隐藏/显示、选中高亮（材质切换）、
## 计数只计体素（挂非体素子节点不失真）；get_center_offset/get_built_cells 供拾取几何使用。
## 批次 G 扩展（锐眼红绿差集，spec 7.4）：set_voxel_mark=多余体素红色 mark；
## show_ghosts/clear_ghosts=缺少体素绿色半透明幻影块（独立节点，不入 cell 映射、不影响计数）。

# 批次 W（P3-1）：色彩单源表（值不变）。
const Palette := preload("res://scripts/palette.gd")
const VOXEL_INSET := 0.94  # 每体素方块内缩比例，留缝隙便于辨认单个体素
const HIGHLIGHT_COLOR := Color(Palette.PICK_GREEN, 0.92)  # 选中高亮：半透绿（P3-1 单源，值不变）
const MARK_COLOR := Palette.EYE_MARK_RED      # 锐眼·多余体素：红（P3-1 单源，值不变）
const GHOST_COLOR := Palette.GHOST_GREEN      # 锐眼·缺少体素：绿（P3-1 单源，值不变）
const WIRE_COLOR := Color(0.1, 0.07, 0.03, 0.5)  # 批次 J（A3/J2-5）：体素网格线描边深褐半透

var _cell_nodes: Dictionary = {}  # Vector3i(cell) → MeshInstance3D（构建时记录，重建清空）
var _center_offset: Vector3 = Vector3.ZERO  # 构建时的包围盒中心平移量（拾取几何需与渲染一致）
var _default_material: Material = null  # 构建传入的默认材质
var _highlight_material: StandardMaterial3D = null  # 选中高亮材质（懒创建，全视图共享）
var _mark_material: StandardMaterial3D = null       # 锐眼·多余体素红色材质（懒创建）
var _ghost_material: StandardMaterial3D = null      # 锐眼·缺少体素绿色幻影材质（懒创建）
var _ghost_box: BoxMesh = null                      # 幻影共享网格（懒创建）
var _ghost_nodes: Dictionary = {}  # Vector3i(cell) → 幻影 MeshInstance3D（show_ghosts 重建）
var _wire_mesh: ImmediateMesh = null                # 体素线框共享网格（懒创建，12 边 24 顶点）
var _wire_material: StandardMaterial3D = null       # 线框共享材质（懒创建）

## 依格式 A 体素数组构建方块：每体素一个 BoxMesh+MeshInstance3D（共享 mesh 资源）。
## size 为包围盒尺寸（Vector3i），用于越界过滤；material 为体素材质。
func build_voxels(voxels: Array, size: Vector3i, material: Material) -> void:
	clear_voxels()
	_cell_nodes.clear()
	_ghost_nodes.clear()  # 重建后包围盒中心可能变化，幻影需按新中心重算（由调用方重打）
	_default_material = material
	var box := BoxMesh.new()
	box.size = Vector3.ONE * VOXEL_INSET
	var mn := Vector3i(size.x, size.y, size.z)
	var mx := Vector3i(-1, -1, -1)
	var pts: Array[Vector3] = []
	for v: Variant in voxels:
		var p := _parse_voxel(String(v))
		if p.x < 0 or p.x >= size.x or p.y < 0 or p.y >= size.y or p.z < 0 or p.z >= size.z:
			continue  # 非法/越界坐标跳过（与 LevelLibrary 过滤规则一致）
		pts.append(Vector3(p))
		mn.x = mini(mn.x, p.x); mn.y = mini(mn.y, p.y); mn.z = mini(mn.z, p.z)
		mx.x = maxi(mx.x, p.x); mx.y = maxi(mx.y, p.y); mx.z = maxi(mx.z, p.z)
	if pts.is_empty():
		return
	# 包围盒中心（体素占 [p, p+1]）平移至原点
	var center := (Vector3(mn) + Vector3(mx) + Vector3.ONE) * 0.5
	_center_offset = center
	for p: Vector3 in pts:
		var cell := Vector3i(p)
		if _cell_nodes.has(cell):
			continue  # 重复坐标跳过：映射键唯一，计数不失真
		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = material
		mi.position = p + Vector3(0.5, 0.5, 0.5) - center
		# 批次 J（J2-5，A3 可选 P2）：网格线描边——每体素挂线框子节点（父隐子隐，
		# 不入 _cell_nodes 映射、不影响计数与拾取；共享 mesh/材质，开销小）
		var wire := MeshInstance3D.new()
		wire.name = "Wire"
		wire.mesh = _get_wire_mesh(box.size)
		wire.material_override = _get_wire_material()
		mi.add_child(wire)
		add_child(mi)
		_cell_nodes[cell] = mi

func clear_voxels() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.free()
	_cell_nodes.clear()
	_ghost_nodes.clear()  # 幻影节点也是子节点，一并释放后同步清映射（防悬空引用）

## 只计体素（批次 E 语义修正）：取映射大小，挂非体素子节点不失真。
func get_voxel_count() -> int:
	return _cell_nodes.size()

## 取体素节点；cell 不存在（越界/未构建）返回 null。
func get_voxel_node(cell: Vector3i) -> MeshInstance3D:
	var n: Variant = _cell_nodes.get(cell)
	if n is MeshInstance3D:
		return n
	return null

## 隐藏体素（挖除=隐藏而非释放，便于撤销恢复）；cell 不存在时静默忽略。
func hide_voxel(cell: Vector3i) -> void:
	var n := get_voxel_node(cell)
	if n != null:
		n.visible = false

## 恢复显示体素（撤销）；cell 不存在时静默忽略。
func show_voxel(cell: Vector3i) -> void:
	var n := get_voxel_node(cell)
	if n != null:
		n.visible = true

## 选中高亮切换：true=半透绿高亮材质（批次 J/A3），false=恢复构建时默认材质；cell 不存在时静默忽略。
## 与锐眼 ghost 绿区分：选中 alpha 0.92 较实、ghost alpha 0.45 较淡（幻影不受光照）。
func set_voxel_highlight(cell: Vector3i, on: bool) -> void:
	var n := get_voxel_node(cell)
	if n == null:
		return
	if on:
		if _highlight_material == null:
			_highlight_material = StandardMaterial3D.new()
			_highlight_material.albedo_color = HIGHLIGHT_COLOR
			_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # 半透绿需 ALPHA 生效
			_highlight_material.roughness = 0.4
			_highlight_material.emission_enabled = true
			_highlight_material.emission = HIGHLIGHT_COLOR * 0.35  # 绿自发光 ×0.35（§0.5 A3）
		n.material_override = _highlight_material
	else:
		n.material_override = _default_material

## 锐眼·多余体素红色 mark 切换（批次 G，spec 7.4）：true=红材质，false=恢复默认材质。
## 与选中高亮共用 material_override 槽位——上层（level_scene）保证选中格高亮优先、
## 关闭/重算时按选区状态恢复。cell 不存在时静默忽略。
func set_voxel_mark(cell: Vector3i, on: bool) -> void:
	var n := get_voxel_node(cell)
	if n == null:
		return
	if on:
		if _mark_material == null:
			_mark_material = StandardMaterial3D.new()
			_mark_material.albedo_color = MARK_COLOR
			_mark_material.roughness = 0.4
			_mark_material.emission_enabled = true
			_mark_material.emission = MARK_COLOR * 0.4
		n.material_override = _mark_material
	else:
		n.material_override = _default_material

## 锐眼·缺少体素绿色幻影（批次 G）：整组替换式重建——先清旧幻影再按 cells 新建；
## 与 target 对齐但被玩家挖掉的格位显示半透明绿块，提示「这里不该挖/需恢复」。
## 幻影为独立节点：不入 _cell_nodes 映射（get_voxel_count 不失真）、不参与拾取。
func show_ghosts(cells: Array) -> void:
	clear_ghosts()
	if cells.is_empty():
		return
	if _ghost_material == null:
		_ghost_material = StandardMaterial3D.new()
		_ghost_material.albedo_color = GHOST_COLOR
		_ghost_material.albedo_color.a = 0.45
		_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # 幻影不受光照、始终醒目
		_ghost_material.no_depth_test = true  # 半透明体防被相邻体素遮挡
	if _ghost_box == null:
		_ghost_box = BoxMesh.new()
		_ghost_box.size = Vector3.ONE * VOXEL_INSET
	for v: Variant in cells:
		var cell := Vector3i(v)
		var n := get_voxel_node(cell)
		if n != null and n.visible:
			continue  # 该格实体仍在显示中（remaining 含它）不重复显示幻影；
			# 已挖除（隐藏节点）的格正是幻影要提示的位置，须显示
		var mi := MeshInstance3D.new()
		mi.mesh = _ghost_box
		mi.material_override = _ghost_material
		mi.position = Vector3(cell) + Vector3(0.5, 0.5, 0.5) - _center_offset  # 与体素同式定位
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_ghost_nodes[cell] = mi

## 清除全部幻影（锐眼关闭/重算时调用）。
func clear_ghosts() -> void:
	for c: Node in _ghost_nodes.values():
		remove_child(c)
		c.free()
	_ghost_nodes.clear()

## 当前幻影格位（Vector3i 数组）。
func get_ghost_cells() -> Array:
	return _ghost_nodes.keys()

## 取幻影节点；cell 无幻影返回 null。
func get_ghost_node(cell: Vector3i) -> MeshInstance3D:
	var n: Variant = _ghost_nodes.get(cell)
	if n is MeshInstance3D:
		return n
	return null

## 批次 J（J2-5，A3 可选 P2）：体素 12 条棱的线框共享网格（PRIMITIVE_LINES，24 顶点）。
## size 为方块边长（VOXEL_INSET 内缩后），线框与 BoxMesh 同尺寸同心（子节点局部原点）。
func _get_wire_mesh(size: Vector3) -> ImmediateMesh:
	if _wire_mesh != null:
		return _wire_mesh
	var h := size * 0.5
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	# 沿 X 的 4 条棱
	im.surface_add_vertex(Vector3(-h.x, -h.y, -h.z)); im.surface_add_vertex(Vector3(h.x, -h.y, -h.z))
	im.surface_add_vertex(Vector3(-h.x, -h.y, h.z)); im.surface_add_vertex(Vector3(h.x, -h.y, h.z))
	im.surface_add_vertex(Vector3(-h.x, h.y, -h.z)); im.surface_add_vertex(Vector3(h.x, h.y, -h.z))
	im.surface_add_vertex(Vector3(-h.x, h.y, h.z)); im.surface_add_vertex(Vector3(h.x, h.y, h.z))
	# 沿 Y 的 4 条棱
	im.surface_add_vertex(Vector3(-h.x, -h.y, -h.z)); im.surface_add_vertex(Vector3(-h.x, h.y, -h.z))
	im.surface_add_vertex(Vector3(h.x, -h.y, -h.z)); im.surface_add_vertex(Vector3(h.x, h.y, -h.z))
	im.surface_add_vertex(Vector3(-h.x, -h.y, h.z)); im.surface_add_vertex(Vector3(-h.x, h.y, h.z))
	im.surface_add_vertex(Vector3(h.x, -h.y, h.z)); im.surface_add_vertex(Vector3(h.x, h.y, h.z))
	# 沿 Z 的 4 条棱
	im.surface_add_vertex(Vector3(-h.x, -h.y, -h.z)); im.surface_add_vertex(Vector3(-h.x, -h.y, h.z))
	im.surface_add_vertex(Vector3(h.x, -h.y, -h.z)); im.surface_add_vertex(Vector3(h.x, -h.y, h.z))
	im.surface_add_vertex(Vector3(-h.x, h.y, -h.z)); im.surface_add_vertex(Vector3(-h.x, h.y, h.z))
	im.surface_add_vertex(Vector3(h.x, h.y, -h.z)); im.surface_add_vertex(Vector3(h.x, h.y, h.z))
	im.surface_end()
	_wire_mesh = im
	return im

## 线框共享材质：unshaded（不受光照稳定可见）+ 深褐半透（J2-5 规格 Color(0.1,0.07,0.03,0.5)）。
func _get_wire_material() -> StandardMaterial3D:
	if _wire_material == null:
		_wire_material = StandardMaterial3D.new()
		_wire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wire_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_wire_material.albedo_color = WIRE_COLOR
	return _wire_material

## 构建时的包围盒中心平移量（体素世界位置 = cell + 0.5 - center，拾取几何须同式）。
func get_center_offset() -> Vector3:
	return _center_offset

## 已构建体素坐标（Vector3i 数组，与渲染一一对应）。
func get_built_cells() -> Array:
	return _cell_nodes.keys()

## 格式 A 坐标解析："x,y,z" → Vector3i；非法格式返回 (-1,-1,-1)（由调用方跳过）。
func _parse_voxel(s: String) -> Vector3i:
	var parts: PackedStringArray = s.split(",")
	if parts.size() != 3:
		return Vector3i(-1, -1, -1)
	return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
