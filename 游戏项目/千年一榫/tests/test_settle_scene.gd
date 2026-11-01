extends "res://tests/test_base.gd"
## 批次 D 判定用例：结算场景骨架 → P批波2（2026-09-10）退役语义改写（等价替换留痕）。
## ⚠ P批波2 结算架构重做：结算 UI 已合并进 level_scene 覆盖层（SuccessOverlay/SettleUI，
## 主路径零重建零回正零切换，见 tests/test_p_settle.gd）——settle_scene 退役不再被路由
## （goto_state(SETTLE) 经 game.gd 特判改载 level 场景注入 settle:true 走边缘路径）。
## 本文件改写为「退役留痕」口径：①资产链完整（tscn/gd 保留不删、可加载可实例化——
## 防 asset 断链）；②不再被路由（Game 特判+mark_settle_entered 契约）；③既有骨架/显示/
## 点云/分流断言保留（场景文件未改、独立直启仍功能完整——回归面只增不减）。
## 环境说明：--script 无头模式 autoload 已注册，经 /root/<Name> 动态引用（T08/T14 实测）。

const SCENE_PATH := "res://scenes/settle/settle_scene.tscn"
const BG_PATH := "res://assets/backgrounds/bg_chapter1.png"
const GAME_SCRIPT := "res://autoload/game.gd"
const LEVEL_GD := "res://scenes/level/level_scene.gd"

const ST_MAIN_MENU := 1
const ST_LEVEL := 4
const ST_SETTLE := 5

## 递归查找 CenterMount 下挂载的 PointCloudViewer（按脚本判定，同 test_catalog 口径，J4-2/F2）
func _find_viewer(node: Node) -> Control:
	if node.get_script() == load("res://scripts/point_cloud_viewer.gd"):
		return node as Control
	for c: Node in node.get_children():
		var found: Control = _find_viewer(c)
		if found != null:
			return found
	return null

## 递归查找 MultiMeshInstance3D（点云实体，路径经 viewer 子树，J4-2/F2）
func _find_mmi(node: Node) -> MultiMeshInstance3D:
	if node is MultiMeshInstance3D:
		return node as MultiMeshInstance3D
	for c: Node in node.get_children():
		var found: MultiMeshInstance3D = _find_mmi(c)
		if found != null:
			return found
	return null

func _initialize() -> void:
	print("== test_settle_scene ==")
	var game: Variant = get_root().get_node("Game")

	# ---- 1. 场景加载与骨架节点 ----
	check(ResourceLoader.exists(SCENE_PATH), "settle_scene.tscn 存在（=Game.SCENE_PATHS[SETTLE]）")
	if not ResourceLoader.exists(SCENE_PATH):
		finish()
		return
	var packed: PackedScene = load(SCENE_PATH)
	check(packed != null, "settle_scene.tscn 可加载")
	var inst: Node = (packed as PackedScene).instantiate()
	check(inst != null, "结算场景可实例化")
	if inst == null:
		finish()
		return

	# 默认（未注入 context）：占位显示
	add_child(inst)
	await process_frame
	check(inst is Control, "结算场景根节点为 Control（全屏）")
	check(inst.get_node_or_null("CenterMount") is Control, "CenterMount(Control) 点云挂载占位存在（批次 F）")
	var score: Label = inst.get_node_or_null("ScoreLabel")
	var elapsed: Label = inst.get_node_or_null("ElapsedLabel")
	var talent: Label = inst.get_node_or_null("TalentLabel")
	check(score is Label, "ScoreLabel 存在")
	check(elapsed is Label, "ElapsedLabel 存在")
	check(talent is Label, "TalentLabel 存在")
	if score != null:
		check(String(score.text).contains("——"), "未注入时评分显示占位「——」")
	var next_btn: Button = inst.get_node_or_null("NextButton")
	check(next_btn is Button, "「下一关」按钮存在")
	check(next_btn != null and next_btn.text == "下一关", "按钮文本为「下一关」")
	var bg: TextureRect = inst.get_node_or_null("Background")
	check(bg is TextureRect and bg.texture != null, "结算背景 TextureRect 有纹理")
	if bg != null and bg.texture != null:
		check(bg.texture.resource_path.ends_with("bg_chapter1.png"), "背景为既有素材 bg_chapter1.png")
	# F1（J4-2）：背景压暗层（黑 0.62 半透，位于 Background 之上、内容之下）
	var dim: ColorRect = inst.get_node_or_null("Dim") as ColorRect
	check(dim != null, "F1：结算背景压暗层 Dim(ColorRect) 存在")
	if dim != null:
		check(dim.color.r < 0.2 and dim.color.a >= 0.6 and dim.color.a <= 0.7,
			"F1：压暗层为半透黑（结算定值 0.62）")
		check(dim.mouse_filter == Control.MOUSE_FILTER_IGNORE, "F1：压暗层不吃输入")
	# F2（J4-2）：CenterMount 展示区扩大（0.25,0.08)-(0.75,0.62) → (0.18,0.06)-(0.82,0.66)
	var cm: Control = inst.get_node_or_null("CenterMount") as Control
	if cm != null:
		check(cm.anchor_left < 0.2 and cm.anchor_top < 0.07 and cm.anchor_right > 0.8 and cm.anchor_bottom > 0.65,
			"F2：结算点云展示区 CenterMount 已扩大")
	inst.queue_free()

	# ---- 2. set_context 注入 {chapter,score,elapsed,talent} 后显示 ----
	var inst2: Node = (packed as PackedScene).instantiate()
	inst2.call("set_context", {"chapter": 1, "score": 88, "elapsed": 65, "talent": 3})
	add_child(inst2)
	await process_frame
	var s2: Label = inst2.get_node_or_null("ScoreLabel")
	var e2: Label = inst2.get_node_or_null("ElapsedLabel")
	var t2: Label = inst2.get_node_or_null("TalentLabel")
	check(s2 != null and String(s2.text).contains("88"), "注入后评分显示 88")
	check(e2 != null and String(e2.text).contains("01:05"), "耗时 65 秒显示 01:05")
	check(t2 != null and String(t2.text).contains("天赋值：3"), "天赋值显示 3")

	# ---- 2.5 J4-2（F2）：中央点云改为复用 PointCloudViewer 组件（金黄 tint、可旋转缩放）----
	# 旧内联实现（_build_cloud 手搭 CloudContainer 子树 + 根 _gui_input 绕 Y 拖拽）已删除；
	# 节点路径变化：CenterMount/PointCloudViewer/CloudContainer/CloudViewport/CloudWorld/CloudPivot/PointCloud
	# → 断言统一改递归查找（仿 test_catalog _find_viewer 口径，降低脆性）。
	# 材质回归（274085a，2026-08-27 走查缺陷 10_settle 黑块）保留：必须 UNSHADED+vertex_color_use_as_albedo。
	var center: Control = inst2.get_node_or_null("CenterMount") as Control
	var viewer: Control = _find_viewer(center) if center != null else null
	check(viewer != null, "F2：结算中央点云复用 PointCloudViewer 组件")
	if viewer != null:
		check(String(viewer.name) == "PointCloudViewer", "F2：viewer 节点名规范（PointCloudViewer）")
		check(int(viewer.call("get_instance_count")) > 1000,
			"F2：结算点云已加载该关文物数据（%d 点）" % int(viewer.call("get_instance_count")))
		var mmi: MultiMeshInstance3D = _find_mmi(viewer)
		check(mmi != null and String(mmi.name) == "PointCloud", "F2：viewer 子树含 PointCloud(MultiMeshInstance3D)")
		if mmi != null:
			check(String(viewer.get_path_to(mmi)) == "CloudContainer/CloudViewport/CloudWorld/CloudPivot/PointCloud",
				"F2：点云新路径 CloudContainer/.../CloudPivot/PointCloud（viewer 自带 pivot）")
		var cloud_mat: Material = viewer.call("get_cloud_material")
		# M 批等价替换（2026-09-08 M-Ga）：材质升级为涟漪 ShaderMaterial，显示口径语义等价
		# （旧 shading_mode==UNSHADED ↔ render_mode unshaded；旧 vertex_color_use_as_albedo ↔ COLOR 透传）
		check(cloud_mat is ShaderMaterial, "F2：点云 surface 0 材质为 ShaderMaterial（M 批等价替换：涟漪 ShaderMaterial）")
		check(cloud_mat != null and String((cloud_mat as ShaderMaterial).shader.code).contains("unshaded"),
			"F2：结算材质 unshaded（M 批等价替换，274085a 回归口径：无光源 SubViewport 直接显色）")
		check(cloud_mat != null and absf(float((cloud_mat as ShaderMaterial).get_shader_parameter("u_use_vertex_color")) - 1.0) < 0.0001,
			"F2：u_use_vertex_color=1（M 批等价替换，旧 vertex_color_use_as_albedo：tint 走逐实例色 lerp）")
		# 金黄 tint 定值断言（§0.5 #F5C542=(0.96,0.77,0.26)）：色分量判定，不用裸 !=null 永真式
		var tc: Variant = viewer.get("tint_color")
		check(tc is Color and (tc as Color).a > 0 and absf((tc as Color).r - 0.96) < 0.02
			and absf((tc as Color).g - 0.77) < 0.02 and absf((tc as Color).b - 0.26) < 0.02,
			"F2：点云金黄 tint 已设（≈#F5C542）")
		var ts: Variant = viewer.get("tint_strength")
		check(typeof(ts) == TYPE_FLOAT and absf(float(ts) - 0.85) < 0.001, "F2：tint 强度=0.85（计划定值，J5-2 走查微调）")
		# J6r3-2 → O批等价替换（2026-09-10 用户口径⑦圆点化+尺寸调档，plan 批次 O-P2）：结算实设
		# point_size=0.005 亚像素噪点档废止——settle_scene 字面量零改动（红线），有效点径经 viewer
		# DOT_SIZE_MIN 下限同源上调 0.012（图鉴金噪点+结算建模颗粒感共同根因消除，走查定稿留痕）。
		var ps_j6: Variant = viewer.get("point_size")
		check(typeof(ps_j6) == TYPE_FLOAT and absf(float(ps_j6) - 0.005) < 0.0005,
			"O批等价替换：结算实设 point_size=0.005 保留（settle_scene 字面量零改动；原「0.004~0.006 档」口径废止）")
		var ps_mmi: MultiMeshInstance3D = _find_mmi(viewer)
		var dmin_j6: float = float((load("res://scripts/point_cloud_viewer.gd") as Script).get_script_constant_map().get("DOT_SIZE_MIN", -1.0))
		check(ps_mmi != null and ps_mmi.multimesh != null and ps_mmi.multimesh.mesh != null
			and (ps_mmi.multimesh.mesh as Mesh).get_class() == "QuadMesh" \
			and absf((ps_mmi.multimesh.mesh as Mesh).get_aabb().size.x - dmin_j6) < 0.0005,
			"O批等价替换：结算点云圆点 QuadMesh 有效边长=DOT_SIZE_MIN %.3f（mesh 级读回；原 BoxMesh 0.005 断言随圆点化废止）" % dmin_j6)
		# 注（J4-2 实证，2026-08-28）：不在此读 MultiMesh 逐实例色做金黄生效判定——
		# Godot 4.7 无头环境下 MultiMesh 为**孤立对象时 CPU 侧读回恒 0**（最小复现：
		# set_instance_color/set_instance_transform/`color_array` 写入后读回均 (0,0,0)，无越界报错），
		# 属引擎/无头后端限制而非实现缺陷（同写路径在窗口渲染显示原色已由 274085a 走查截图实证）。
		# tint 生效证据链=属性定值（上）+ 材质 vertex_color_use_as_albedo（上）+ build 内 lerp 代码路径；
		# 最终金黄观感归 J6 真机截图走查复核（此口径已在批次返回报告记录，供 J5-2 避坑）。
		check(mmi != null and mmi.multimesh != null and mmi.multimesh.use_colors,
			"F2：tint 逐实例 lerp 落点已启用（use_colors=true，原色数据等长）")
		# 缩放能力（viewer 自带，替代旧仅绕 Y 拖拽）：视距可减小且不塌回默认
		var dist0: float = float(viewer.get("_distance"))
		viewer.call("zoom_by", 1.2)
		check(float(viewer.get("_distance")) < dist0, "F2：点云可滚轮缩放（zoom_by 拉近生效）")
	else:
		for _i: int in 9:
			check(false, "F2：viewer 缺失，关联断言记红")

	# ---- 3. 「下一关」stub：无下一关数据 → 回主菜单（批次 F 接真实流程；退役后本场景
	# 独立直启路径行为不变——分流语义已迁 level_scene.settle_next_route，此处为遗留资产面）----
	var nb: Button = inst2.get_node_or_null("NextButton")
	if nb != null:
		nb.pressed.emit()
		await process_frame
		check_eq(int(game.current_state()), ST_MAIN_MENU, "第 1 关无下一关数据：「下一关」回主菜单（退役资产独立直启行为保持）")
	inst2.queue_free()

	# ---- 4. P批波2 退役留痕（结算架构重做：结算 UI 合并进 level 覆盖层，本场景不再被路由）----
	print("-- 4 P批波2 退役留痕 --")
	var g_src: String = FileAccess.get_file_as_string(GAME_SCRIPT)
	check(g_src.contains("mark_settle_entered") and g_src.contains("\"settle\""),
		"P批波2：game.gd 含 SETTLE 特判留痕（mark_settle_entered 主路径记账 + ctx.settle 边缘路径注入）")
	var l_src: String = FileAccess.get_file_as_string(LEVEL_GD)
	check(l_src.contains("settle_next_route") and l_src.contains("_show_settle_ui"),
		"P批波2：level_scene.gd 承载结算 UI（settle_next_route 三分流迁入 + _show_settle_ui 淡入演出）")
	check(FileAccess.get_file_as_string("res://scenes/settle/settle_scene.gd").contains("退役"),
		"P批波2：settle_scene.gd 头部退役标注留痕（不再被路由）")
	var game_sm: Node = get_root().get_node("Game")
	check(game_sm.has_method("mark_settle_entered"), "P批波2：Game.mark_settle_entered 契约方法存在")
	# 行为面：goto_state(SETTLE) 不再加载本场景——改载 level（边缘路径，attach 后验证）
	var container: Control = Control.new()
	add_child(container)
	var overlay_layer: CanvasLayer = CanvasLayer.new()
	add_child(overlay_layer)
	game_sm.attach(container, overlay_layer)
	game_sm.call("goto_state", ST_SETTLE, {"chapter": 1, "grade": "完美", "elapsed": 65, "talent": 100})
	await process_frame
	await process_frame
	var routed: Node = game_sm.call("get_current_scene")
	check(routed != null and (routed as Node).get_script() == load(LEVEL_GD),
		"P批波2：goto_state(SETTLE) 改载 level 场景（本场景不再被路由，边缘路径重建）")
	check(int(game_sm.call("current_state")) == ST_SETTLE,
		"P批波2：SETTLE 态语义保持（状态机记账 SETTLE，主路径由 level.mark_settle_entered 承接）")
	container.queue_free()

	finish()
