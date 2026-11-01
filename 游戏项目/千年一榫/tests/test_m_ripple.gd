extends "res://tests/test_base.gd"
## 批次 M-Ga/N6 点云悬停涟漪判定用例 → **O批（2026-09-10 用户反馈⑦「鼠标与点云建模交互去掉」）
## 等价重写：悬停交互整套移除**——断言按移除语义反转留痕（「O批：悬停交互移除」）。
## 契约来源：用户口径 2026-09-10（悬停涟漪推开整套移除；拖拽旋转与滚轮缩放保留——Q&A 13
## 玩家可旋转是既有确认需求）。原 M-Ga/N6 涟漪契约（shader 顶点位移/静态推开场/渐入渐出）
## 随本批废止，本文件按移除语义反转重写并留痕（总 checks 只增不减由 test_o_animation 承接）。
##   ①源码级：viewer 源码无 ripple 符号（RIPPLE_* 常量/RIPPLE_SHADER_CODE/u_ripple_* uniform/
##     _ripple_tick/_ripple_pick/_write_ripple_uniforms/get_ripple_* 全无——grep 级断言）；
##   ②接口级：无涟漪方法与 debug_mouse/debug_force_out 注入钩子；_process 逐帧悬停判定随之移除；
##   ③交互保留：左键拖拽旋转（rotate_by）+ 滚轮缩放（zoom_by）+ reset_view 原样可用；
##   ④材质显示口径不回退：ShaderMaterial unshaded + COLOR 逐实例色透传（u_use_vertex_color）
##     + u_fallback_color 兜底（274085a 黑膜修复口径）；O批圆点化（QuadMesh+手动 billboard+
##     圆盘 alpha）+ DOT_SIZE_MIN 下限档（0.005 亚像素档废止 → 0.012）；
##   ⑤结构稳定：build/clear/重复 build 不受移除影响（instance_count 证据链）。
## 结算侧同口径：settle 复用 PointCloudViewer 组件 → 移除与圆点化自动继承（断言同款）。
## 坑 6 口径不变：MultiMesh 无头逐实例读回恒 0 → 属性证据链，观感归窗口走查。

const VIEWER_SCRIPT := "res://scripts/point_cloud_viewer.gd"
const SETTLE_SCENE := "res://scenes/settle/settle_scene.tscn"
const REAL_POINTS_PATH := "res://assets/models/points/石器_points.res"  # 30000 点真实点云
const GOLD_TINT := Color(0.96, 0.77, 0.26, 1)  # #F5C542（图鉴/结算口径）

func _make_cloud(n: int, with_color: bool = true) -> PointCloudData:
	var d := PointCloudData.new()
	for i: int in n:
		d.points.append(Vector3(fmod(i * 7.0, 10.0) - 5.0, fmod(i * 3.0, 6.0) - 3.0, fmod(i * 11.0, 8.0) - 4.0))
		if with_color:
			d.colors.append(Color(0.9, 0.8, 0.4))
	d.aabb_center = Vector3.ZERO
	d.aabb_size = Vector3(10, 6, 8)
	return d

func _find_mmi(node: Node) -> MultiMeshInstance3D:
	if node is MultiMeshInstance3D:
		return node
	for c: Node in node.get_children():
		var found: MultiMeshInstance3D = _find_mmi(c)
		if found != null:
			return found
	return null

func _find_viewer(node: Node) -> Control:
	if node != null and node.get_script() == load(VIEWER_SCRIPT):
		return node as Control
	for c: Node in node.get_children():
		var found: Control = _find_viewer(c)
		if found != null:
			return found
	return null

## 建 600x450 定尺寸宿主（坑 1：无头断言前钉布局尺寸）。
func _make_hosted_viewer(vs: Script) -> Control:
	var host := Control.new()
	host.size = Vector2(600, 450)
	add_child(host)
	var viewer: Control = vs.new()
	host.add_child(viewer)
	await process_frame
	await process_frame
	return viewer

func _initialize() -> void:
	print("== test_m_ripple ==")
	var vs: Script = load(VIEWER_SCRIPT) as Script
	check(vs != null, "组件脚本可加载: scripts/point_cloud_viewer.gd")
	if vs == null:
		finish()
		return

	# ---- 1. O批：涟漪符号源码级全无（移除语义反转；M-Ga/N6 契约废止留痕）----
	var src: String = FileAccess.get_file_as_string(VIEWER_SCRIPT)
	var low := src.to_lower()
	check(not low.contains("ripple"), "O批：源码无 ripple 符号（RIPPLE_*/u_ripple_*/_ripple_* 整套移除）")
	var cmap: Dictionary = vs.get_script_constant_map()
	check(not cmap.has("RIPPLE_AMP") and not cmap.has("RIPPLE_SIGMA") and not cmap.has("RIPPLE_BLEND_IN") \
		and not cmap.has("RIPPLE_BLEND_OUT") and not cmap.has("RIPPLE_FOLLOW") and not cmap.has("RIPPLE_BALL_R") \
		and not cmap.has("RIPPLE_SHADER_CODE"),
		"O批：涟漪常量组与内嵌 shader 常量全无（M-Ga→N6→O批 移除留痕）")
	var probe: Control = (vs as GDScript).new()
	check(not probe.has_method("_ripple_tick") and not probe.has_method("_ripple_pick") \
		and not probe.has_method("_write_ripple_uniforms"),
		"O批：涟漪推进/拾取/uniform 写入方法全无（_process 悬停判定随之移除）")
	check(not probe.has_method("get_ripple_strength") and not probe.has_method("get_ripple_hit") \
		and not probe.has_method("get_ripple_time"),
		"O批：涟漪证据链钩子 get_ripple_* 全无")
	check(probe.get("debug_mouse") == null and probe.get("debug_force_out") == null,
		"O批：debug_mouse/debug_force_out 悬停注入钩子移除（无消费方）")
	check(probe.has_method("rotate_by") and probe.has_method("zoom_by") and probe.has_method("reset_view"),
		"O批：交互保留——rotate_by/zoom_by/reset_view 齐备（拖拽旋转+滚轮缩放不随涟漪移除）")
	probe.free()

	# ---- 2. build 后材质证据链：ShaderMaterial unshaded + 逐实例色透传（274085a 口径不回退）----
	# O批圆点化：QuadMesh + 手动 billboard + 圆盘 alpha（smoothstep 软边缘）；DOT_SIZE_MIN 下限档。
	var dmin: float = float(cmap.get("DOT_SIZE_MIN", -1.0))
	check(dmin >= 0.010 and dmin <= 0.015, "O批：DOT_SIZE_MIN 下限档 ∈[0.010,0.015]（0.005 亚像素档废止）")
	var code: String = String(cmap.get("CLOUD_SHADER_CODE", ""))
	check(code.contains("shader_type spatial") and code.contains("unshaded"),
		"O批：点云 shader：spatial + unshaded（无光环境直接显色口径不回退，274085a）")
	check(code.contains("COLOR") and code.contains("u_use_vertex_color") and code.contains("u_fallback_color"),
		"O批：点云 shader：逐实例色透传 + 统一色兜底（等价旧 vertex_color_use_as_albedo/albedo_color）")
	check(code.contains("MODEL_MATRIX") and code.contains("smoothstep") and code.contains("UV"),
		"O批：点云 shader：手动 billboard（MODEL_MATRIX 平移）+ 圆盘 alpha（UV 距心 smoothstep 软边缘）")

	var viewer: Control = await _make_hosted_viewer(vs)
	viewer.set("point_size", 0.005)  # 图鉴/结算实设档（同源下调验证）
	viewer.call("build", _make_cloud(64))
	var mat: Material = viewer.call("get_cloud_material")
	check(mat is ShaderMaterial, "材质：get_cloud_material() 为 ShaderMaterial（显示口径载体不回退）")
	if mat is ShaderMaterial:
		var sm: ShaderMaterial = mat
		check(sm.shader != null and sm.shader.code == code, "材质：shader 源码 = viewer 内嵌 CLOUD_SHADER_CODE")
		check(absf(float(sm.get_shader_parameter("u_use_vertex_color")) - 1.0) < 0.0001,
			"材质：u_use_vertex_color=1（COLOR 逐实例色进 ALBEDO）")
	var pivot: Node = viewer.get("_pivot") as Node
	var mmi: MultiMeshInstance3D = pivot.get_node_or_null("PointCloud") as MultiMeshInstance3D if pivot != null else null
	check(mmi != null and mmi.multimesh != null and int(mmi.multimesh.instance_count) == 64,
		"结构：instance_count==64（移除涟漪不改动 MultiMesh 结构）")
	check(mmi != null and mmi.multimesh != null and mmi.multimesh.use_colors,
		"结构：use_colors 仍 true（逐实例着色口径不变）")
	check(mmi != null and mmi.multimesh != null and mmi.multimesh.mesh is QuadMesh \
		and absf((mmi.multimesh.mesh as Mesh).get_aabb().size.x - dmin) < 0.0005,
		"O批：mesh=QuadMesh 且 0.005 实设经下限档上调至 %.3f（圆点实体感）" % dmin)

	# ---- 3. _process 移除后多帧推进零副作用（原悬停判定链已拆；结构/实例数恒定）----
	for i: int in 30:
		await process_frame
	check(int(viewer.call("get_instance_count")) == 64, "O批：多帧推进后 instance_count 仍 64（无逐帧 CPU 工作）")
	check(viewer.call("get_cloud_material") == mat, "O批：多帧推进后材质链稳定（无涟漪 uniform 写入点）")

	# ---- 4. 真实 30000 点：build 结构稳定（坑 6：属性证据链，不读回逐实例数据）----
	if ResourceLoader.exists(REAL_POINTS_PATH):
		var real: PointCloudData = load(REAL_POINTS_PATH)
		viewer.call("build", real)
		check_eq(int(viewer.call("get_instance_count")), 30000, "真实点云 build → 30000 点")
		check(int(viewer.call("get_instance_count")) == 30000, "O批：移除涟漪后真实点云构建链路无损")
	else:
		check(false, "真实点云资源可加载（石器_points.res）")

	# ---- 5. 无逐实例色回退路径：u_use_vertex_color=0 + u_fallback_color=tint（等价旧 albedo 兜底）----
	viewer.set("tint_color", GOLD_TINT)
	viewer.set("tint_strength", 0.85)
	var nocolor := PointCloudData.new()
	for i: int in 8:
		nocolor.points.append(Vector3(i, 0, 0))
	nocolor.aabb_center = Vector3(3.5, 0, 0)
	nocolor.aabb_size = Vector3(8, 1, 1)
	viewer.call("build", nocolor)
	var mat_nc: Material = viewer.call("get_cloud_material")
	check(mat_nc is ShaderMaterial and absf(float((mat_nc as ShaderMaterial).get_shader_parameter("u_use_vertex_color"))) < 0.0001,
		"回退路径：无 colors → u_use_vertex_color=0")
	var fb: Variant = (mat_nc as ShaderMaterial).get_shader_parameter("u_fallback_color")
	check(fb is Color and absf((fb as Color).r - 0.96) < 0.02 and absf((fb as Color).g - 0.77) < 0.02,
		"回退路径：u_fallback_color=tint 金黄（旧 albedo_color 兜底等价）")
	check_eq(int(viewer.call("get_instance_count")), 8, "回退路径：instance_count 正常")

	# ---- 6. 交互保留行为断言：拖拽旋转 + 滚轮缩放 + 复位（Q&A 13 既有确认需求）----
	var viewer2: Control = await _make_hosted_viewer(vs)
	viewer2.call("build", _make_cloud(32))
	viewer2.set("rot_y_deg", 0.0)
	viewer2.call("rotate_by", 30.0, 5.0)
	check(absf(float(viewer2.get("rot_y_deg")) - 30.0) < 0.001, "O批：rotate_by(30,5) → rot_y_deg=30（拖拽旋转保留）")
	var d0: float = float(viewer2.get("_distance"))
	viewer2.call("zoom_by", 2.0)
	check(float(viewer2.get("_distance")) < d0, "O批：zoom_by(2) → 拉近（滚轮缩放保留）")
	viewer2.call("zoom_by", 0.0001)  # 非正常倍率不崩、限幅
	viewer2.call("reset_view")
	check(absf(float(viewer2.get("rot_y_deg")) - float(viewer2.get("INIT_YAW_DEG"))) < 0.001,
		"O批：reset_view 复位（视角口径不回退）")
	check_eq(int(viewer2.call("get_instance_count")), 32, "O批：旋转/缩放不改动实例数（实例变换只在 build 写一次）")
	viewer2.queue_free()

	# ---- 7. clear 清链：材质空 + 实例归零 ----
	viewer.call("clear")
	check(viewer.call("get_cloud_material") == null, "clear 后材质链清空")
	check_eq(int(viewer.call("get_instance_count")), 0, "clear 后实例数归零")
	viewer.queue_free()

	# ---- 8. 结算页同口径：settle 复用 viewer → 涟漪移除与圆点化自动继承 ----
	if ResourceLoader.exists(SETTLE_SCENE):
		var packed: PackedScene = load(SETTLE_SCENE)
		var inst: Node = (packed as PackedScene).instantiate()
		inst.call("set_context", {"chapter": 1, "grade": "良好", "elapsed": 61, "talent": 80})
		add_child(inst)
		await process_frame
		await process_frame
		var sv: Control = _find_viewer(inst)
		check(sv != null, "结算页存在 PointCloudViewer（组件复用）")
		if sv != null:
			var smat: Material = sv.call("get_cloud_material")
			check(smat is ShaderMaterial and String((smat as ShaderMaterial).shader.code).contains("unshaded"),
				"结算页：点云材质 ShaderMaterial unshaded（圆点 shader 同源）")
			check(not sv.has_method("_ripple_tick") and not sv.has_method("get_ripple_strength"),
				"O批：结算页无涟漪方法（移除自动继承，悬停无交互）")
			check(sv.has_method("rotate_by") and sv.has_method("zoom_by"),
				"O批：结算页 rotate_by/zoom_by 保留（Q&A 13）")
			check(int(sv.call("get_instance_count")) > 1000,
				"结算页：点云已加载（%d 点）" % int(sv.call("get_instance_count")))
			var spivot: Node = sv.get("_pivot") as Node
			var smmi: MultiMeshInstance3D = spivot.get_node_or_null("PointCloud") as MultiMeshInstance3D if spivot != null else null
			check(smmi != null and smmi.multimesh != null and smmi.multimesh.mesh is QuadMesh \
				and absf((smmi.multimesh.mesh as Mesh).get_aabb().size.x - dmin) < 0.0005,
				"O批：结算页实设 0.005 经下限档上调（结算建模颗粒感同源消除）")
		inst.queue_free()
	else:
		check(false, "结算场景可加载")

	finish()
