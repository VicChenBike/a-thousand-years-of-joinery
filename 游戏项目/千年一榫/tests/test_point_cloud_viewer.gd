extends "res://tests/test_base.gd"
## 批次 H 判定用例：PointCloudViewer 图鉴点云查看器组件（TDD 先写；实现前全 [FAIL] 属预期红灯）。
## 契约来源：批次 H 任务单（组件接口节）+ spec 4.6/9.1/3.12：
##   接口：build(pointcloud: Resource)（接收 PointCloudData；MultiMesh 实例变换只在 build 时
##        写入一次，旋转/缩放走节点 transform 不逐实例更新）、clear()、
##        set_rot_y_deg(deg) / rot_y_deg 属性 / rotate_by(dx, dy)、zoom_by(factor)、
##        reset_view()、get_instance_count() -> int（无数据返回 0）；
##   交互：左键拖拽绕 Y 旋转 + 轻度俯仰（夹紧）、滚轮缩放（限幅）；
##   降级：pointcloud 为 null/空/非点云类型 → 显示「点云加载失败」占位，不报错不崩溃；
##   颜色：colors 与 points 等长时 MultiMesh.use_colors=true 逐实例着色，否则回退。
## 无 headless 渲染要求：只测逻辑（instance_count / 接口不崩 / 降级占位）。

const VIEWER_SCRIPT := "res://scripts/point_cloud_viewer.gd"
const REAL_POINTS_PATH := "res://assets/models/points/石器_points.res"  # 第 1 关真实点云（30000 点）

func _make_cloud(n: int) -> PointCloudData:
	# 小型确定性点云（优先小数据构造，避免全量加载 30000 点拖慢测试）
	var d := PointCloudData.new()
	for i: int in n:
		d.points.append(Vector3(fmod(i * 7.0, 10.0) - 5.0, fmod(i * 3.0, 6.0) - 3.0, fmod(i * 11.0, 8.0) - 4.0))
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

func _find_node_named(node: Node, target: String) -> Node:
	if node.name == target:
		return node
	for c: Node in node.get_children():
		var found: Node = _find_node_named(c, target)
		if found != null:
			return found
	return null

func _find_label_with(node: Node, needle: String) -> Label:
	if node is Label and (node as Label).text.contains(needle):
		return node
	for c: Node in node.get_children():
		var found: Label = _find_label_with(c, needle)
		if found != null:
			return found
	return null

func _initialize() -> void:
	print("== test_point_cloud_viewer ==")
	var vs: Script = load(VIEWER_SCRIPT) as Script
	check(vs != null, "组件脚本可加载: scripts/point_cloud_viewer.gd")
	if vs == null:
		finish()
		return

	# ---- 1. build：小型构造点云 → 实例数 = 点数；MultiMesh 颜色开启 ----
	var viewer: Control = vs.new()
	add_child(viewer)
	check(int(viewer.get("mouse_filter")) == 0, "viewer 自身 mouse_filter=STOP（接收拖拽/滚轮，不外溢）")
	check(int(viewer.call("get_instance_count")) == 0, "无数据时 get_instance_count()=0")
	viewer.call("build", _make_cloud(64))
	check(int(viewer.call("get_instance_count")) > 0, "build 后 get_instance_count()>0")
	check_eq(int(viewer.call("get_instance_count")), 64, "build 后实例数=点数（64）")
	var mmi: MultiMeshInstance3D = _find_mmi(viewer)
	check(mmi != null and mmi.multimesh != null, "build 后存在 MultiMeshInstance3D + MultiMesh")
	check(mmi != null and mmi.multimesh != null and mmi.multimesh.use_colors, "colors 等长 → MultiMesh.use_colors=true（逐实例着色）")
	check(mmi != null and mmi.multimesh != null and mmi.multimesh.mesh != null
		and (mmi.multimesh.mesh as Mesh).get_aabb().size.x <= 0.02 + 0.0001,
		"点尺寸 ≤0.02 量级（点间距清晰，spec 3.12）")

	# ---- 2. 旋转/缩放接口：调用不崩、属性可读写、reset_view 复位 ----
	# M-Hb：build 末尾 reset_view 现为 3/4 初始视角（INIT_YAW=30 起算）——增量语义断言前
	# 显式归零，rotate_by 的「增量」口径与初始视角解耦。
	viewer.set("rot_y_deg", 0.0)
	viewer.call("rotate_by", 30.0, 5.0)
	check(absf(float(viewer.get("rot_y_deg")) - 30.0) < 0.001, "rotate_by(30,5) → rot_y_deg=30")
	viewer.call("rotate_by", -100.0, 200.0)  # 超界俯仰应被夹紧、Y 可负向累计，不崩
	check(absf(float(viewer.get("rot_y_deg")) - (-70.0)) < 0.001, "连续 rotate_by 累计（30-100=-70），不崩")
	viewer.set("rot_y_deg", 45.0)
	check(absf(float(viewer.get("rot_y_deg")) - 45.0) < 0.001, "rot_y_deg 属性可直接赋值")
	viewer.call("set_rot_y_deg", 90.0)
	check(absf(float(viewer.get("rot_y_deg")) - 90.0) < 0.001, "set_rot_y_deg(90) 生效")
	viewer.call("zoom_by", 2.0)
	check(float(viewer.get("_distance")) < float(viewer.get("DEFAULT_DISTANCE")), "zoom_by(2) → 相机拉近（距离变小）")
	viewer.call("zoom_by", 0.0001)  # 非正常倍率也不崩、被限幅
	viewer.call("reset_view")
	# M-Hb 走查回修（2026-09-08）：初始视角改 3/4 等轴测——正面看扁长构件=「横带」缺陷
	# （J6 12_catalog_ch1.png 即已如此），复位口径从 0/0 改 INIT_YAW/INIT_TILT。
	check(absf(float(viewer.get("rot_y_deg")) - float(viewer.get("INIT_YAW_DEG"))) < 0.001,
		"reset_view → 偏航复位=INIT_YAW_DEG（M-Hb 初始 3/4 视角）")
	check(absf(float(viewer.get("_rot_x_deg")) - float(viewer.get("INIT_TILT_DEG"))) < 0.001,
		"reset_view → 俯仰复位=INIT_TILT_DEG（M-Hb 初始 3/4 视角）")
	check(absf(float(viewer.get("_distance")) - float(viewer.get("DEFAULT_DISTANCE"))) < 0.001, "reset_view → 视距复位")
	var cnt_after_view: int = int(viewer.call("get_instance_count"))
	check_eq(cnt_after_view, 64, "旋转/缩放不改动实例数（实例变换只在 build 写一次）")

	# ---- 3. 重建（图鉴切换章节路径）：build 新数据 → 实例数切换为新点数 ----
	viewer.call("build", _make_cloud(32))
	check_eq(int(viewer.call("get_instance_count")), 32, "再次 build 切换数据 → 实例数=新点数（32）")

	# ---- 4. clear：实例数归零 ----
	viewer.call("clear")
	check_eq(int(viewer.call("get_instance_count")), 0, "clear 后 get_instance_count()=0")

	# ---- 5. 降级：null / 空 points / 类型不符 → 占位「点云加载失败」不崩 ----
	viewer.call("build", null)
	check_eq(int(viewer.call("get_instance_count")), 0, "build(null) → 实例数 0，不崩")
	var fail1: Label = _find_label_with(viewer, "点云加载失败")
	check(fail1 != null and fail1.visible, "build(null) → 显示「点云加载失败」占位")
	var empty: PointCloudData = PointCloudData.new()
	viewer.call("build", empty)
	check_eq(int(viewer.call("get_instance_count")), 0, "build(空 points) → 实例数 0，不崩")
	check(_find_label_with(viewer, "点云加载失败") != null and _find_label_with(viewer, "点云加载失败").visible,
		"build(空 points) → 显示「点云加载失败」占位")
	viewer.call("build", Resource.new())  # 非 PointCloudData 资源
	check_eq(int(viewer.call("get_instance_count")), 0, "build(类型不符资源) → 实例数 0，不崩")
	viewer.call("clear")
	check(_find_label_with(viewer, "点云加载失败") != null and not _find_label_with(viewer, "点云加载失败").visible,
		"clear 后降级占位隐藏")

	# ---- 6. 真实资源验证一次：石器_points.res（30000 点级，覆盖真实数据形状）----
	if ResourceLoader.exists(REAL_POINTS_PATH):
		var real: PointCloudData = load(REAL_POINTS_PATH)
		check(real != null and not real.points.is_empty(), "真实点云资源可加载（石器_points.res）")
		viewer.call("build", real)
		check_eq(int(viewer.call("get_instance_count")), real.points.size(),
			"build(真实点云) → 实例数=points.size()（%d）" % real.points.size())
		var has_color: bool = real.colors.size() == real.points.size()
		var mmi2: MultiMeshInstance3D = _find_mmi(viewer)
		check(mmi2 != null and mmi2.multimesh != null and mmi2.multimesh.use_colors == has_color,
			"真实点云 use_colors 与颜色数组等长性一致")
	else:
		check(false, "真实点云资源可加载（石器_points.res）")

	# ---- 7. 布局回归（2026-08-27 走查缺陷）：入树后 _ready 的 FULL_RECT 必须真正铺满父容器 ----
	# 修复前：_ready 里 set_anchors_preset(PRESET_FULL_RECT) 只重设 anchors、offsets 被改写以
	#   维持当前矩形 → 0 尺寸控件保持 (0,0)，viewer 塌缩、SubViewport 仅 2x2，点云不可见。
	# 修复后：set_anchors_and_offsets_preset 重置 anchors+offsets → 铺满 500x400 容器。
	var host := Control.new()
	host.name = "LayoutHost"
	host.size = Vector2(500, 400)
	add_child(host)
	var viewer2: Control = vs.new()
	host.add_child(viewer2)
	await process_frame
	check(viewer2.size.x > 100 and viewer2.size.y > 100,
		"布局：入树后 viewer 铺满父容器（期望 500x400，实际 %s；修复前塌缩 (0,0)）" % str(viewer2.size))
	viewer2.call("build", _make_cloud(16))
	await process_frame
	var box: SubViewportContainer = _find_node_named(viewer2, "CloudContainer") as SubViewportContainer
	check(box != null and box.size.x > 100 and box.size.y > 100,
		"布局：CloudContainer(SubViewportContainer) 铺满 viewer（实际 %s）" % (str(box.size) if box != null else "缺失"))
	var vp: SubViewport = null
	if box != null and box.get_child_count() > 0:
		vp = box.get_child(0) as SubViewport
	check(vp != null and vp.size.x > 100 and vp.size.y > 100,
		"布局：SubViewport 随容器展开（实际 %s；修复前仅 2x2）" % (str(vp.size) if vp != null else "缺失"))
	host.queue_free()

	# ---- 8. 材质回归（2026-08-27 走查缺陷 11_catalog 黑块）：点云材质必须 unshaded ----
	# CloudWorld 内无任何光源：受光 StandardMaterial3D 在无光环境渲染为纯黑 → 点云不可见。
	# 修复=shading_mode==UNSHADED（点云颜色即最终色，不需要光照）；且 MultiMesh 逐实例颜色
	#须经 material.vertex_color_use_as_albedo 才进入 albedo（否则逐实例色被忽略）。
	viewer.call("build", _make_cloud(16))
	# M 批等价替换（2026-09-08 M-Ga）：点云材质升级为内嵌涟漪 ShaderMaterial（shader vertex
	# 位移路线），显示口径语义等价——旧 shading_mode==UNSHADED ↔ render_mode unshaded；
	# 旧 vertex_color_use_as_albedo=true ↔ shader COLOR→ALBEDO 透传（u_use_vertex_color=1）。
	var cloud_mat: Material = viewer.call("get_cloud_material")
	check(cloud_mat is ShaderMaterial, "材质：get_cloud_material() 取到 surface 0 的 ShaderMaterial（M 批等价替换：涟漪 ShaderMaterial）")
	check(cloud_mat != null and String((cloud_mat as ShaderMaterial).shader.code).contains("unshaded"),
		"材质：render_mode unshaded（无光源 SubViewport 直接显色，旧 shading_mode==UNSHADED 等价）")
	check(cloud_mat != null and absf(float((cloud_mat as ShaderMaterial).get_shader_parameter("u_use_vertex_color")) - 1.0) < 0.0001,
		"材质：u_use_vertex_color=1（COLOR 逐实例色进 ALBEDO，旧 vertex_color_use_as_albedo 等价）")

	# ---- 9. J5-2（G3）：tint_color/tint_strength/point_size @export 接口生效护栏 ----
	# 接口由 J4-2 先落（本批 J5 不动 viewer 本体），此段为行为护栏补齐。
	# 4.7 无头环境 MultiMesh 逐实例色 CPU 读回恒 0（J4-2 实证，引擎读侧限制非实现缺陷），
	# 故不写 get_instance_color 断言；tint 生效证据链=属性分量 + use_colors 门 + 材质标志
	# （lerp 代码路径在 build 内，最终金黄观感归 J6 真机截图走查）。
	viewer.set("tint_color", Color(0.96, 0.77, 0.26, 1))
	viewer.set("point_size", 0.024)
	viewer.call("build", _make_cloud(16))
	var tc9: Variant = viewer.get("tint_color")
	check(tc9 is Color and (tc9 as Color).a > 0 and absf((tc9 as Color).r - 0.96) < 0.02
		and absf((tc9 as Color).g - 0.77) < 0.02 and absf((tc9 as Color).b - 0.26) < 0.02,
		"G3：tint_color 金黄可设（≈#F5C542，色分量判定）")
	var ts9: Variant = viewer.get("tint_strength")
	check(typeof(ts9) == TYPE_FLOAT and absf(float(ts9) - 0.85) < 0.001,
		"G3：tint_strength 缺省=0.85（计划定值，TODO J5 走查后微调）")
	# 注：build 重建后旧 CloudContainer 为 queue_free（当帧仍在树内），_find_mmi 深度优先
	# 可能取到旧子树 → 经 _pivot 直取当前 build 的 PointCloud（viewer build 维护 _pivot）。
	var pivot9: Node = viewer.get("_pivot") as Node
	var mmi9: MultiMeshInstance3D = pivot9.get_node_or_null("PointCloud") as MultiMeshInstance3D if pivot9 != null else null
	check(mmi9 != null and mmi9.multimesh != null and mmi9.multimesh.use_colors,
		"G3：有逐实例色数据 → use_colors=true（tint 走 lerp 路径的门）")
	var mesh9: Mesh = mmi9.multimesh.mesh if mmi9 != null and mmi9.multimesh != null else null
	check(mesh9 != null and absf(mesh9.get_aabb().size.x - 0.024) < 0.0005,
		"G3：point_size=0.024 生效（mesh 级可读回，不受实例数据无头读回限制）")
	var mat9: Material = viewer.call("get_cloud_material")
	# M 批等价替换（M-Ga）：UNSHADED+vertex_color 断言改涟漪 ShaderMaterial 口径（语义等价）
	check(mat9 is ShaderMaterial
		and String((mat9 as ShaderMaterial).shader.code).contains("unshaded")
		and absf(float((mat9 as ShaderMaterial).get_shader_parameter("u_use_vertex_color")) - 1.0) < 0.0001,
		"G3：tint 路径下材质仍 unshaded+逐实例色透传（M 批等价替换，274085a 口径不回退）")
	# 回退路径：无 colors 数据 → tint 直接作材质统一 albedo（金黄兜底）
	var nocolor := PointCloudData.new()
	for i: int in 8:
		nocolor.points.append(Vector3(i, 0, 0))
	nocolor.aabb_center = Vector3(3.5, 0, 0)
	nocolor.aabb_size = Vector3(8, 1, 1)
	viewer.call("build", nocolor)
	var mat10: Material = viewer.call("get_cloud_material")
	# M 批等价替换（M-Ga）：回退 albedo_color=tint → u_use_vertex_color=0 + u_fallback_color=tint
	check(mat10 is ShaderMaterial
		and absf(float((mat10 as ShaderMaterial).get_shader_parameter("u_use_vertex_color"))) < 0.0001
		and absf(((mat10 as ShaderMaterial).get_shader_parameter("u_fallback_color") as Color).r - 0.96) < 0.02
		and ((mat10 as ShaderMaterial).get_shader_parameter("u_fallback_color") as Color).a > 0,
		"G3：无 colors 数据 → u_fallback_color=tint 金黄兜底（M 批等价替换，统一色回退路径）")
	# 不 tint 默认口径：tint_color 默认 alpha=0（图鉴原色数据行为不回退，J4-2 接口约定）
	var viewer_d: Control = vs.new()
	add_child(viewer_d)
	var tc_def: Variant = viewer_d.get("tint_color")
	check(tc_def is Color and (tc_def as Color).a == 0.0, "G3：tint_color 默认 alpha=0=不 tint（接口约定）")
	viewer_d.queue_free()

	viewer.queue_free()
	finish()
