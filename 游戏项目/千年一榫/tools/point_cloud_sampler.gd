extends SceneTree
## 离线点云采样：GLB → 面积加权随机采样 → PointCloudData(.res)
## 用法：--headless --script res://tools/point_cloud_sampler.gd -- <目标点数,默认30000>

const DEFAULT_COLOR := Color("#FFD54A")
const MODELS := ["石器", "宋", "元", "明", "现代"]

func _initialize() -> void:
	var target_points: int = 30000
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		target_points = args[0].to_int()
	# res:// 路径不能直接用于绝对路径 API，须先全局化
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/models/points"))
	for name_: String in MODELS:
		_sample_one(name_, target_points)
	print("sampling done")
	quit(0)

func _sample_one(model_name: String, target_points: int) -> void:
	var glb_path: String = "res://assets/models/%s.glb" % model_name
	if not ResourceLoader.exists(glb_path):
		print("[SKIP] 缺失 %s" % glb_path)
		return
	var root: Node = (load(glb_path) as PackedScene).instantiate()
	var surfaces: Array[Dictionary] = []  # {mesh: ArrayMesh, surface_index, area, xform, material}
	_collect(root, Transform3D(), surfaces)
	root.free()
	var total_area: float = 0.0
	for s: Dictionary in surfaces:
		total_area += float(s["area"])
	if total_area <= 0.0:
		print("[SKIP] %s 面积为 0" % model_name)
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20260825
	var points: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var min_v: Vector3 = Vector3.INF
	var max_v: Vector3 = -Vector3.INF
	for i: int in target_points:
		# 按面积选面
		var pick: float = rng.randf() * total_area
		var chosen: Dictionary = surfaces[0]
		for s: Dictionary in surfaces:
			pick -= float(s["area"])
			if pick <= 0.0:
				chosen = s
				break
		var p: Vector3 = _random_point_on_surface(chosen, rng)
		points.append(p)
		colors.append(_sample_color(chosen, p))
		min_v = min_v.min(p)
		max_v = max_v.max(p)
	var data: PointCloudData = PointCloudData.new()
	data.points = points
	data.colors = colors
	data.aabb_center = (min_v + max_v) * 0.5
	data.aabb_size = max_v - min_v
	var out: String = "res://assets/models/points/%s_points.res" % model_name
	ResourceSaver.save(data, out)
	print("[OK] %s → %d 点" % [model_name, points.size()])

func _collect(node: Node, xform: Transform3D, out: Array[Dictionary]) -> void:
	var t: Transform3D = xform * node.transform
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		var mesh: Mesh = mi.mesh
		if mesh is ArrayMesh:
			var am: ArrayMesh = mesh
			for si: int in am.get_surface_count():
				var arrays: Array = am.surface_get_arrays(si)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var area: float = 0.0
				var step: int = 3
				var count: int = idx.size() if idx.size() > 0 else verts.size()
				var k: int = 0
				while k + 2 < count:
					var i0: int = idx[k] if idx.size() > 0 else k
					var i1: int = idx[k + 1] if idx.size() > 0 else k + 1
					var i2: int = idx[k + 2] if idx.size() > 0 else k + 2
					var a: Vector3 = t * verts[i0]
					var b: Vector3 = t * verts[i1]
					var c: Vector3 = t * verts[i2]
					area += (b - a).cross(c - a).length() * 0.5
					k += step
				out.append({"mesh": am, "surface_index": si, "area": area, "xform": t, "material": am.surface_get_material(si)})
	for child: Node in node.get_children():
		_collect(child, t, out)

func _random_point_on_surface(s: Dictionary, rng: RandomNumberGenerator) -> Vector3:
	var am: ArrayMesh = s["mesh"]
	var arrays: Array = am.surface_get_arrays(int(s["surface_index"]))
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var tri_count: int = (idx.size() if idx.size() > 0 else verts.size()) / 3
	var tri: int = rng.randi() % maxi(tri_count, 1)
	var i0: int = idx[tri * 3] if idx.size() > 0 else tri * 3
	var i1: int = idx[tri * 3 + 1] if idx.size() > 0 else tri * 3 + 1
	var i2: int = idx[tri * 3 + 2] if idx.size() > 0 else tri * 3 + 2
	var r1: float = rng.randf()
	var r2: float = rng.randf()
	if r1 + r2 > 1.0:
		r1 = 1.0 - r1
		r2 = 1.0 - r2
	var xform: Transform3D = s["xform"]
	return xform * (verts[i0] + (verts[i1] - verts[i0]) * r1 + (verts[i2] - verts[i0]) * r2)

func _sample_color(s: Dictionary, _p: Vector3) -> Color:
	# 尝试材质 albedo；失败 → 默认亮黄（spec 9.1 降级路径）
	var mat: Material = s["material"]
	if mat is BaseMaterial3D:
		var bm: BaseMaterial3D = mat
		if bm.albedo_color != Color.WHITE or bm.albedo_texture != null:
			return bm.albedo_color if bm.albedo_color.a > 0.0 else DEFAULT_COLOR
	return DEFAULT_COLOR
