class_name EditorVoxelView
extends Node3D
## 关卡编辑器·视图层：单视图体素渲染。复制自游戏 LevelVoxelView（基线 b0cc039，
## scripts/level_voxel_view.gd:1-234，规格 R3）并按编辑器口径改造，改造点逐条：
## ① build_voxels(格式 A 字符串数组) → build_set(Vector3i 集合)：编辑器全链 Vector3i（省逐帧字符串解析），
##    且包围盒中心恒 = block_size 中心（size×0.5）不随体素集缩放漂移——拾取几何/预览/包围盒共用基准
##    （游戏版中心随实际格集变化，编辑器带空集与增量添加，必须定锚）。
## ② 新增 add_voxel（添加模式放置：无节点则新建，有节点则显示）。
## ③ 新增 show_bounds/clear_bounds（block_size 包围盒线框+底面网格，规格 §7.2 空集起步）。
## ④ 新增 show_place_preview/clear_place_preview（放置预览幻影，复用原幻影材质做法 :139-165）。
## ⑤ 新增 set_hover/clear_hover（悬停点光跟随，规格 §7.1；渐入渐出省略为定值能量——暂定简化，可走查微调）。
## ⑥ 去除锐眼专用件（set_voxel_mark/show_ghosts 族——编辑器无锐眼）。
## 保留：VOXEL_INSET 0.94、选中高亮材质（:102-116）、逐体素线框描边（J2-5 :62-66/:187-219）、
## hide/show 挖除恢复语义（:89-98）、get_center_offset/get_built_cells（:222/:226）。
## R4：程序化木纹材质 make_wood_material 静态函数随迁（level_scene.gd:484-499 原样复制），
## WOOD_LIGHT/WOOD_DARK 基色（level_scene.gd:59-60）。

const VOXEL_INSET := 0.94
const HIGHLIGHT_COLOR := Color(0.30, 0.85, 0.40, 0.92)
const WIRE_COLOR := Color(0.1, 0.07, 0.03, 0.5)
const PREVIEW_COLOR := Color(0.3, 1.0, 0.35)
const WOOD_LIGHT := Color(0.62, 0.44, 0.24)
const WOOD_DARK := Color(0.36, 0.24, 0.13)
const HOVER_LIGHT_COLOR := Color(1.0, 0.87, 0.58)
const HOVER_LIGHT_ENERGY := 1.5
const HOVER_LIGHT_RANGE := 3.0
const HOVER_LIGHT_LIFT := 1.6

var _cell_nodes: Dictionary = {}          # Vector3i → MeshInstance3D
var _center_offset: Vector3 = Vector3.ZERO
var _default_material: Material = null
var _highlight_material: StandardMaterial3D = null
var _preview_material: StandardMaterial3D = null
var _preview_box: BoxMesh = null
var _preview_node: MeshInstance3D = null
var _bounds_node: MeshInstance3D = null
var _bounds_size: Vector3i = Vector3i.ZERO   # F3：当前容器线框尺寸（编排层/测试读回，随 show_bounds 更新）
var _voxel_box: BoxMesh = null
var _wire_meshes: Dictionary = {}   # 批次 W（P3-5e）：Vector3(size) → ImmediateMesh（按尺寸键控；旧单一缓存忽略 size 入参）
var _wire_material: StandardMaterial3D = null
var _hover_light: OmniLight3D = null

# ---------- R4 程序化木纹（level_scene.gd:484-499 原样复制，仅改静态化） ----------
static func make_wood_material(base_color: Color) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.08
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.width = 128
	tex.height = 128
	tex.seamless = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base_color
	mat.albedo_texture = tex
	mat.roughness = 0.55
	mat.metallic = 0.0
	mat.uv1_scale = Vector3(1.0, 0.15, 1.0)
	return mat

# ---------- 构建（改造①：Vector3i 集合入口，中心定锚） ----------
## 编辑器构建入口：清空重建，中心恒 = size×0.5。空集合法（join/final 从零搭建）。
func build_set(cells: Dictionary, size: Vector3i, material: Material) -> void:
	clear_voxels()
	_default_material = material
	_center_offset = Vector3(size) * 0.5
	for k: Variant in cells:
		_spawn_voxel(k)

func clear_voxels() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.free()
	_cell_nodes.clear()
	_preview_node = null   # 预览/包围盒/点光同为子节点，一并释放后清引用（防悬空）
	_bounds_node = null
	_bounds_size = Vector3i.ZERO   # P3：释放线框时清尺寸，get_bounds_size 读回与 has_bounds 一致
	_hover_light = null

func _spawn_voxel(cell: Vector3i) -> void:
	if _cell_nodes.has(cell):
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _get_voxel_box()
	mi.material_override = _default_material
	mi.position = Vector3(cell) + Vector3(0.5, 0.5, 0.5) - _center_offset
	var wire := MeshInstance3D.new()
	wire.name = "Wire"
	wire.mesh = _get_wire_mesh(Vector3.ONE * VOXEL_INSET)
	wire.material_override = _get_wire_material()
	mi.add_child(wire)
	add_child(mi)
	_cell_nodes[cell] = mi

## 添加模式放置（改造②）：有节点则显示（曾被挖除），无节点则按当前材质新建。
func add_voxel(cell: Vector3i) -> void:
	var n := get_voxel_node(cell)
	if n != null:
		n.visible = true
		return
	if _default_material == null:
		return
	_spawn_voxel(cell)

func get_voxel_count() -> int:
	return _cell_nodes.size()

func get_voxel_node(cell: Vector3i) -> MeshInstance3D:
	var n: Variant = _cell_nodes.get(cell)
	if n is MeshInstance3D:
		return n
	return null

# ---------- 挖除/恢复（R3 :89-98 语义原样） ----------
func hide_voxel(cell: Vector3i) -> void:
	var n := get_voxel_node(cell)
	if n != null:
		n.visible = false

func show_voxel(cell: Vector3i) -> void:
	var n := get_voxel_node(cell)
	if n != null:
		n.visible = true

# ---------- 选中高亮（R3 :102-116 原样） ----------
func set_voxel_highlight(cell: Vector3i, on: bool) -> void:
	var n := get_voxel_node(cell)
	if n == null:
		return
	if on:
		if _highlight_material == null:
			_highlight_material = StandardMaterial3D.new()
			_highlight_material.albedo_color = HIGHLIGHT_COLOR
			_highlight_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_highlight_material.roughness = 0.4
			_highlight_material.emission_enabled = true
			_highlight_material.emission = HIGHLIGHT_COLOR * 0.35
		n.material_override = _highlight_material
	else:
		n.material_override = _default_material

# ---------- 放置预览幻影（改造④，复用幻影材质做法 :139-165） ----------
func show_place_preview(cell: Vector3i) -> void:
	clear_place_preview()
	if _preview_material == null:
		_preview_material = StandardMaterial3D.new()
		_preview_material.albedo_color = PREVIEW_COLOR
		_preview_material.albedo_color.a = 0.45
		_preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_preview_material.no_depth_test = true
	if _preview_box == null:
		_preview_box = BoxMesh.new()
		_preview_box.size = Vector3.ONE * VOXEL_INSET
	var mi := MeshInstance3D.new()
	mi.mesh = _preview_box
	mi.material_override = _preview_material
	mi.position = Vector3(cell) + Vector3(0.5, 0.5, 0.5) - _center_offset
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_preview_node = mi

func clear_place_preview() -> void:
	if _preview_node != null:
		remove_child(_preview_node)
		_preview_node.free()
		_preview_node = null

func has_place_preview() -> bool:
	return _preview_node != null

# ---------- block_size 容器包围盒线框 + 底面网格（改造③，规格 §7.2 空集起步） ----------
## F3：编排层尺寸应用/重建时恒以 block_size 调用本函数（容器线框常显，独立于格集），
## 尺寸应用后立即反映新尺寸；_bounds_size 供状态/测试读回。
func show_bounds(size: Vector3i) -> void:
	clear_bounds()
	_bounds_size = size
	var h := Vector3(size) * 0.5
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	# 12 条棱（盒范围 [-h, h]，与 _get_wire_mesh 同式放大）
	im.surface_add_vertex(Vector3(-h.x, -h.y, -h.z)); im.surface_add_vertex(Vector3(h.x, -h.y, -h.z))
	im.surface_add_vertex(Vector3(-h.x, -h.y, h.z)); im.surface_add_vertex(Vector3(h.x, -h.y, h.z))
	im.surface_add_vertex(Vector3(-h.x, h.y, -h.z)); im.surface_add_vertex(Vector3(h.x, h.y, -h.z))
	im.surface_add_vertex(Vector3(-h.x, h.y, h.z)); im.surface_add_vertex(Vector3(h.x, h.y, h.z))
	im.surface_add_vertex(Vector3(-h.x, -h.y, -h.z)); im.surface_add_vertex(Vector3(-h.x, h.y, -h.z))
	im.surface_add_vertex(Vector3(h.x, -h.y, -h.z)); im.surface_add_vertex(Vector3(h.x, h.y, -h.z))
	im.surface_add_vertex(Vector3(-h.x, -h.y, h.z)); im.surface_add_vertex(Vector3(-h.x, h.y, h.z))
	im.surface_add_vertex(Vector3(h.x, -h.y, h.z)); im.surface_add_vertex(Vector3(h.x, h.y, h.z))
	im.surface_add_vertex(Vector3(-h.x, -h.y, -h.z)); im.surface_add_vertex(Vector3(-h.x, -h.y, h.z))
	im.surface_add_vertex(Vector3(h.x, -h.y, -h.z)); im.surface_add_vertex(Vector3(h.x, -h.y, h.z))
	im.surface_add_vertex(Vector3(-h.x, h.y, -h.z)); im.surface_add_vertex(Vector3(-h.x, h.y, h.z))
	im.surface_add_vertex(Vector3(h.x, h.y, -h.z)); im.surface_add_vertex(Vector3(h.x, h.y, h.z))
	# 底面网格（y=-h 平面，x/z 每 1 格一线）
	var xi := -h.x
	while xi <= h.x + 0.001:
		im.surface_add_vertex(Vector3(xi, -h.y, -h.z))
		im.surface_add_vertex(Vector3(xi, -h.y, h.z))
		xi += 1.0
	var zi := -h.z
	while zi <= h.z + 0.001:
		im.surface_add_vertex(Vector3(-h.x, -h.y, zi))
		im.surface_add_vertex(Vector3(h.x, -h.y, zi))
		zi += 1.0
	im.surface_end()
	_bounds_node = MeshInstance3D.new()
	_bounds_node.name = "BoundsWire"
	_bounds_node.mesh = im
	_bounds_node.material_override = _get_wire_material()
	add_child(_bounds_node)

func clear_bounds() -> void:
	if _bounds_node != null:
		remove_child(_bounds_node)
		_bounds_node.free()
		_bounds_node = null
	_bounds_size = Vector3i.ZERO

func has_bounds() -> bool:
	return _bounds_node != null

## F3：当前容器线框尺寸（未显示时 ZERO）。
func get_bounds_size() -> Vector3i:
	return _bounds_size

# ---------- 悬停点光（改造⑤，规格 §7.1；常量随迁 level_scene.gd:963-966） ----------
func set_hover(cell: Vector3i) -> void:
	if _hover_light == null:
		_hover_light = OmniLight3D.new()
		_hover_light.light_color = HOVER_LIGHT_COLOR
		_hover_light.light_energy = HOVER_LIGHT_ENERGY
		_hover_light.omni_range = HOVER_LIGHT_RANGE
		_hover_light.omni_attenuation = 1.3
		_hover_light.shadow_enabled = true
		add_child(_hover_light)
	var cell_center := Vector3(cell) + Vector3(0.5, 0.5, 0.5) - _center_offset
	_hover_light.position = cell_center + _hover_dir(cell_center) * HOVER_LIGHT_LIFT
	_hover_light.visible = true

func clear_hover() -> void:
	if _hover_light != null:
		_hover_light.visible = false

func is_hover_visible() -> bool:
	return _hover_light != null and _hover_light.visible

func _hover_dir(cell_center: Vector3) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3(0.3, 1.0, 0.3).normalized()
	return (cam.position - cell_center).normalized()

# ---------- 共享资源与查询（R3 原样） ----------
func _get_voxel_box() -> BoxMesh:
	if _voxel_box == null:
		_voxel_box = BoxMesh.new()
		_voxel_box.size = Vector3.ONE * VOXEL_INSET
	return _voxel_box

func _get_wire_mesh(size: Vector3) -> ImmediateMesh:
	# 批次 W（P3-5e，规格 §7）：按尺寸键控——同尺寸命中缓存、异尺寸各建各的（旧实现首建后
	# 恒返回首个尺寸几何，size 入参被忽略）。Vector3 作键按值哈希，逐分量等值命中。
	var cached: Variant = _wire_meshes.get(size, null)
	if cached is ImmediateMesh:
		return cached
	var h := size * 0.5
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(Vector3(-h.x, -h.y, -h.z)); im.surface_add_vertex(Vector3(h.x, -h.y, -h.z))
	im.surface_add_vertex(Vector3(-h.x, -h.y, h.z)); im.surface_add_vertex(Vector3(h.x, -h.y, h.z))
	im.surface_add_vertex(Vector3(-h.x, h.y, -h.z)); im.surface_add_vertex(Vector3(h.x, h.y, -h.z))
	im.surface_add_vertex(Vector3(-h.x, h.y, h.z)); im.surface_add_vertex(Vector3(h.x, h.y, h.z))
	im.surface_add_vertex(Vector3(-h.x, -h.y, -h.z)); im.surface_add_vertex(Vector3(-h.x, h.y, -h.z))
	im.surface_add_vertex(Vector3(h.x, -h.y, -h.z)); im.surface_add_vertex(Vector3(h.x, h.y, -h.z))
	im.surface_add_vertex(Vector3(-h.x, -h.y, h.z)); im.surface_add_vertex(Vector3(-h.x, h.y, h.z))
	im.surface_add_vertex(Vector3(h.x, -h.y, h.z)); im.surface_add_vertex(Vector3(h.x, h.y, h.z))
	im.surface_add_vertex(Vector3(-h.x, -h.y, -h.z)); im.surface_add_vertex(Vector3(-h.x, -h.y, h.z))
	im.surface_add_vertex(Vector3(h.x, -h.y, -h.z)); im.surface_add_vertex(Vector3(h.x, -h.y, h.z))
	im.surface_add_vertex(Vector3(-h.x, h.y, -h.z)); im.surface_add_vertex(Vector3(-h.x, h.y, h.z))
	im.surface_add_vertex(Vector3(h.x, h.y, -h.z)); im.surface_add_vertex(Vector3(h.x, h.y, h.z))
	im.surface_end()
	_wire_meshes[size] = im
	return im

func _get_wire_material() -> StandardMaterial3D:
	if _wire_material == null:
		_wire_material = StandardMaterial3D.new()
		_wire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wire_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_wire_material.albedo_color = WIRE_COLOR
	return _wire_material

func get_center_offset() -> Vector3:
	return _center_offset

func get_built_cells() -> Array:
	return _cell_nodes.keys()
