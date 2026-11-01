extends "res://tests/test_base.gd"
## 批次 Z Z1（编辑器面板映射修正·编辑器侧）红测：试玩态三面板口径映射。
## 契约来源：批次 Z spec §1（三者同改·用户拍板）：
##   A 试玩左上「对照成品（标准答案）」标题→「最终成品」、副标题→「对接完成形态（仅供参照，
##     不参与判定）」（改前必红）；右上「对接固定件」标题/副标题零变化（等价锚）。
##   B 渲染数据源 target→final：Target 面板 build_set(sessions[3]，get_size_for_tag(3))——
##     造数 target={(0,0,0)} / final={(2,2,2)} / join={(1,0,0)} 三集互异，面板 built 集合
##     必须==final 且 !=target（改前==target 必红）；Join==sessions[2]、Main==试玩会话（零变化锚）。
##   C 取景相机随 final 集：反解相机注视点（沿 −basis.z 行进 |pos−look|）必须落在
##     cells_center(final)−视图中心（容差 0.05）——按 target 取景时注视点偏离 ≈0.35（改前必红）。
##     ⚠ 造数红线（首跑实证空转假绿）：target/final 的 look 点若共线于等轴测对角线（如单格
##     (0,0,0) vs (2,2,2) → look=∓(1,1,1)），两条视线重合、任何度量都无法分辨取景对象——
##     故 target 取 L 形（look 离对角线）、final 取角格；退出试玩复位同式（改前必红）。
##   D 只读交互绑定随面板：_view_interaction_target 绑 TargetPanel/VC 且模式=VIEW（等价锚）。
##   E 判定仍读 target（零改动回归）：target=L 形 3 格、final=单格（体素数不等 ⇒ 48 变换
##     永不等价，判别非空转）：试玩挖剩==target L 形 → 对接 → 常驻成功横幅——若判定误改读
##     final（单格）必判 unfit/wrong、横幅不亮（红）。渲染=final 与判定=target 同场互证。
##   F 编辑态 target tab 保留（spec §1-5）：退出试玩 → switch_tag(1) → tab 可见、主标题含
##     target、主视口渲染 sessions[1]（编辑功能零回归）。
## 沙盒夹具照抄 test_sanity W4-1：VOXEL_EDITOR_SLOTS_ROOT→TEMP 一次性根，零触碰真实 levels/。
## Godot 4.7 实证：--script 无头 add_child 后须 await process_frame 才进树。

const FIXTURE := "res://tests/fixtures/level_chapter1_hemudu.json"
const SLOTS := preload("res://scripts/level_slots.gd")
const EI := preload("res://scripts/editor_interaction.gd")

var _sandbox_root: String = ""

func _init_sandbox() -> void:
	var base := OS.get_environment("TEMP")
	if base.is_empty():
		base = "/tmp"
	base = base.replace("\\", "/")
	_sandbox_root = base.path_join("voxel_editor_z1pf_%d" % Time.get_ticks_msec()) + "/"
	OS.set_environment("VOXEL_EDITOR_SLOTS_ROOT", _sandbox_root)
	SLOTS.ensure_initialized(_sandbox_root, FIXTURE)

func _seed_333(slot: int) -> void:
	var LP := preload("res://scripts/level_project.gd")
	var p: RefCounted = LP.new()
	p.call("new_project", Vector3i(3, 3, 3))
	SLOTS.apply_auto_meta(p, slot)
	SLOTS.save_slot_text(slot, p.call("save_to_text"), _sandbox_root)

func _cleanup_sandbox() -> void:
	if _sandbox_root.is_empty():
		return
	_remove_dir_recursive(_sandbox_root)

func _remove_dir_recursive(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	da.list_dir_begin()
	var item := da.get_next()
	while item != "":
		if item != "." and item != "..":
			var full := path.path_join(item)
			if da.current_is_dir():
				_remove_dir_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		item = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(path)

## 视图 built 集合（Vector3i 键字典）。
func _built_of(view: Node) -> Dictionary:
	var d: Dictionary = {}
	for c: Variant in (view.call("get_built_cells") as Array):
		d[Vector3i(c)] = true
	return d

## 相机注视点反解（look_at 语义：自 position 沿 −basis.z 行进 |position−look| 的点）。
func _implied_look(cam: Camera3D, look: Vector3) -> Vector3:
	return cam.position - cam.transform.basis.z * (cam.position - look).length()

func _initialize() -> void:
	print("== test_z_panel_final（编辑器侧） ==")
	_init_sandbox()
	_seed_333(1)
	SLOTS.save_meta(1, _sandbox_root)
	var ed: Control = (load("res://scenes/editor_main.tscn") as PackedScene).instantiate()
	add_child(ed)
	await process_frame   # --script 模式 add_child 后一帧才进树（_ready 消费沙盒槽位）
	var LP := preload("res://scripts/level_project.gd")
	var sessions: Dictionary = ed.get("sessions")
	# 造数：三面板数据源互异且判别力满配（见头注 C/E 红线——look 共线与 48 等价两大空转陷阱）：
	# target=L 形 3 格（look 离等轴测对角线）/ final=角格单格 / join=单格，三集两两不等。
	var target_cells: Dictionary = {Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true, Vector3i(0, 0, 1): true}
	var final_cells: Dictionary = {Vector3i(2, 2, 2): true}
	(sessions[LP.TAG_TARGET] as RefCounted).setup(target_cells)
	(sessions[LP.TAG_FINAL] as RefCounted).setup(final_cells)
	(sessions[LP.TAG_JOIN] as RefCounted).setup({Vector3i(1, 0, 0): true})

	ed.call("_enter_playtest")
	await process_frame

	# ---- A 标题/副标题三者同改（右上零变化等价锚）----
	var t_title := ed.get_node_or_null("TargetPanel/Title") as Label
	var t_sub := ed.get_node_or_null("TargetPanel/SubTitle") as Label
	var j_title := ed.get_node_or_null("JoinPanel/Title") as Label
	var j_sub := ed.get_node_or_null("JoinPanel/SubTitle") as Label
	check(t_title != null and t_sub != null and j_title != null and j_sub != null, "前置：双面板标题/副标题节点在场")
	if t_title != null:
		check_eq(String(t_title.text), "最终成品", "Z1-A 试玩左上标题=「最终成品」（改前=对照成品（标准答案）必红）")
	if t_sub != null:
		check_eq(String(t_sub.text), "对接完成形态（仅供参照，不参与判定）",
			"Z1-Ab 试玩左上副标题=「对接完成形态（仅供参照，不参与判定）」（改前必红）")
	if j_title != null:
		check_eq(String(j_title.text), "对接固定件", "Z1-Ac 右上标题=「对接固定件」（零变化等价锚）")
	if j_sub != null:
		check(String(j_sub.text).contains("固定件") and String(j_sub.text).contains("干涉"),
			"Z1-Ad 右上副标题零变化（固定件/干涉口径保持，等价锚）")

	# ---- B 渲染数据源 target→final（右上/中央零变化等价锚）----
	var t_view: Node = ed.get_node_or_null("TargetPanel/VC/SubViewport/VoxelView")
	var j_view: Node = ed.get_node_or_null("JoinPanel/VC/SubViewport/VoxelView")
	var m_view: Node = ed.get_node_or_null("MainPanel/VC/SubViewport/VoxelView")
	check(t_view != null and j_view != null and m_view != null, "前置：三面板 VoxelView 在场")
	if t_view != null:
		var t_built := _built_of(t_view)
		check_eq(t_built, (sessions[LP.TAG_FINAL] as RefCounted).cells,
			"Z1-B 试玩左上渲染 final 域（sessions[3]；改前==sessions[1] 必红）")
		check(t_built != (sessions[LP.TAG_TARGET] as RefCounted).cells,
			"Z1-Bb 左上不再渲染 target 集（反向护栏）")
	if j_view != null:
		check_eq(_built_of(j_view), (sessions[LP.TAG_JOIN] as RefCounted).cells,
			"Z1-Bc 右上渲染 join 集（sessions[2]，零变化等价锚）")
	if m_view != null:
		var ps: RefCounted = ed.get("_playtest_session")
		check_eq(_built_of(m_view), ps.cells, "Z1-Bd 中央=试玩会话（blocks 域，零变化等价锚）")

	# ---- C 取景相机随 final 集（进/出试玩两段；改前按 target 取景注视点必红）----
	var t_cam := ed.get_node_or_null("TargetPanel/VC/SubViewport/Camera3D") as Camera3D
	check(t_cam != null, "前置：Target 相机在场")
	if t_cam != null and t_view != null:
		var look_final: Vector3 = EI.cells_center((sessions[LP.TAG_FINAL] as RefCounted).cells) \
			- (t_view.call("get_center_offset") as Vector3)
		check(_implied_look(t_cam, look_final).distance_to(look_final) < 0.05,
			"Z1-C 进试玩 Target 相机按 final 集取景（反解注视点==cells_center(final)−视图中心，容差 0.05；改前按 target 偏离≈0.35 必红）")

	# ---- D 只读交互绑定随面板（VIEW 模式等价锚）----
	var tvi: Node = ed.get("_view_interaction_target")
	check(tvi != null and tvi.get("_container") == ed.get_node("TargetPanel/VC") \
		and int(tvi.get("_bind_mode")) == EI.BindMode.VIEW,
		"Z1-D Target VIEW 只读交互绑定在场（绑 TargetPanel/VC、模式=VIEW，等价锚）")

	# ---- E 判定仍读 target（零改动回归；渲染=final 与判定=target 同场互证）----
	var dig: Array = []
	for x: int in range(3):
		for y: int in range(3):
			for z: int in range(3):
				var cell := Vector3i(x, y, z)
				if not target_cells.has(cell):
					dig.append(cell)   # 27−24=3，剩 L 形==target（final 单格 48 变换永不等价）
	ed.call("_on_dig_requested", dig)
	ed.call("_on_join_pressed")
	var banner := ed.get_node_or_null("PlaytestBanner") as Label
	check(banner != null and banner.visible \
		and String(banner.text) == "试玩成功：与标准答案一致（试玩不落档，退出还原编辑态）",
		"Z1-E 对接 success 常驻横幅（evaluate/playtest_judge 仍读 sessions[1]=target；误改读 final 必 wrong 红）")

	# ---- C2 退出复位按 final（改前按 target 必红）----
	ed.call("_do_exit_playtest")
	await process_frame
	if t_cam != null and t_view != null:
		var look_final2: Vector3 = EI.cells_center((sessions[LP.TAG_FINAL] as RefCounted).cells) \
			- (t_view.call("get_center_offset") as Vector3)
		check(_implied_look(t_cam, look_final2).distance_to(look_final2) < 0.05,
			"Z1-C2 退出试玩 Target 相机按 final 集复位（反解注视点容差 0.05；改前按 target 必红）")
	check(not (ed.get_node("TargetPanel") as Control).visible and not (ed.get_node("JoinPanel") as Control).visible,
		"Z1-C2b 退出双面板隐藏（既有布局语义保持，等价锚）")

	# ---- F 编辑态 target tab 保留（spec §1-5）----
	ed.call("switch_tag", LP.TAG_TARGET)
	await process_frame
	var tab_target := ed.get_node_or_null("LeftPanel/LeftScroll/LeftVBox/TabTarget") as Button
	check(tab_target != null and tab_target.visible, "Z1-F 编辑态「标准答案 target」标签页仍可见（编辑功能保留）")
	var main_title := ed.get_node_or_null("MainPanel/MainTitle") as Label
	check(main_title != null and String(main_title.text).contains("target"),
		"Z1-Fb 切到 target 页主标题含 target（标签页可进入，等价锚）")
	if m_view != null:
		check_eq(_built_of(m_view), (sessions[LP.TAG_TARGET] as RefCounted).cells,
			"Z1-Fc 编辑态 target 页主视口渲染 sessions[1]（编辑查看 target 功能零回归）")

	ed.free()
	_cleanup_sandbox()
	finish()
