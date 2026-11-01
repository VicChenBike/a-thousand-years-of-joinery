extends "res://tests/test_base.gd"
## 关卡玩法域审查缺陷修复 TDD 测试（独占文件：scenes/level/level_scene.gd）：
##   P1 侧视 Ctrl+点击被抬起兜底摧毁（_on_side_view_gui_input Ctrl 分支不写 seen →
##      抬起「未 seen && start 是格」清整侧选区+单选旧起点，把 toggle 结果抹掉）；
##   P2 锐眼差集错域过滤（diff_vs_target 对 p、t 同用 target_size 过滤 → blocks 域
##      ≥target_size 的玩家格被剔出差集；修法=p 按 block_size、t 按 target_size 分域）；
##   P3 全挖空态拦掉旋转/缩放（_remaining 空 blanket return 在滚轮/轨道之前；W9-9 意图
##      只拦拾取/删除链）；
##   P3 关卡 title 类型守卫（_apply_hud String(_level.title) 对 null/数组 4.7 运行期中止）。
## 环境：--script 无头；实例化 level_scene 即在 _exit_tree 写检查点 → 清档纪律照抄
## test_q_level_interactions（起测备份→清域→终测还原→逐字节自检，前缀 flg）。
## title 守卫段走 call_deferred 包裹：旧实现 String(null) 中止的是 deferred 链而非
## _initialize（防红跑挂死，坑「_initialize 中止不退出」）。

const SCENE_PATH := "res://scenes/level/level_scene.tscn"
const LS_SRC := "res://scenes/level/level_scene.gd"
const MISS := Vector3i(-1, -1, -1)

# ---- deferred 桥（P3 title 段）：错误隔离在 deferred 调用内 ----
var _hud_ran: bool = false

func _do_apply_hud(inst: Node) -> void:
	inst.call("_apply_hud")
	_hud_ran = true

func _mb(btn: int, is_pressed: bool, pos: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = btn as MouseButton
	ev.pressed = is_pressed
	ev.position = pos
	ev.global_position = pos
	return ev

func _mm_at(pos: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	return ev

func _probe_cells(inst: Node, cam: Camera3D, from: Vector2, n_dist: int) -> Array:
	var found: Array = []
	var seen: Array = []
	var x := from.x
	while found.size() < n_dist and x < 1200.0:
		var c: Variant = inst.call("get_cell_hit", cam.project_ray_origin(Vector2(x, from.y)),
			cam.project_ray_normal(Vector2(x, from.y)))
		if c != MISS and not seen.has(c):
			seen.append(c)
			found.append([c, Vector2(x, from.y)])
		x += 8.0
	return found

# ===== 清档纪律（test_q_level_interactions 同款，前缀 flg）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_flg_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _pre_save_text: String = ""

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _cleanup_save() -> void:
	for p: String in ["user://save.json", "user://first_launch.flag"]:
		var abs_p: String = ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs_p):
			DirAccess.remove_absolute(abs_p)

func _disc_del(p: String) -> void:
	var a: String = _disc_abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _backup_user() -> void:
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	for c: Node in root.get_children():
		if not DISC_AUTOLOADS.has(String(c.name)):
			c.free()
	for p: String in DISC_WATCHED:
		_disc_del(p)
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(_disc_abs(bk))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_fix_level_gameplay ==")
	_backup_user()
	_cleanup_save()
	get_root().get_node("SaveManager").call("load_game")
	var gds: Script = load(LS_SRC)
	var dm: Dictionary = gds.get_script_constant_map().get("DragMode", {})
	var dm_orbit: int = int(dm.get("ORBIT", -1))
	var inst: Node = (load(SCENE_PATH) as PackedScene).instantiate() if load(SCENE_PATH) != null else null
	check(inst != null, "关卡场景可实例化")
	if inst == null:
		finish()
		return
	inst.call("set_context", {"chapter": 1})
	add_child(inst)
	await process_frame
	var cont: SubViewportContainer = inst.get_node_or_null("MainView/ViewportContainer") as SubViewportContainer
	var vps: SubViewport = inst.get_node_or_null("MainView/ViewportContainer/SubViewport") as SubViewport
	var cam: Camera3D = inst.get_node_or_null("MainView/ViewportContainer/SubViewport/Camera3D")
	check(cont != null and vps != null and cam != null and vps.size.x > 1, "前置：主视容器/视口/相机存在")
	var probes: Array = _probe_cells(inst, cam, Vector2(vps.size.x * 0.5, vps.size.y * 0.5), 3) if (cont != null and vps != null and cam != null and vps.size.x > 1) else []
	check_eq(probes.size(), 3, "前置：主视水平探针命中 3 互异格")
	if probes.size() < 3:
		inst.queue_free()
		_cleanup_save()
		finish()
		return

	# ==================== 段 1：P1 侧视 Ctrl+点击不被抬起兜底摧毁 ====================
	print("-- 段1 P1 侧视 Ctrl+点击 --")
	var tvv: Node = inst.get_node_or_null("TargetView/ViewportContainer/SubViewport/VoxelView")
	var tcont: SubViewportContainer = inst.get_node_or_null("TargetView/ViewportContainer") as SubViewportContainer
	var tvp: SubViewport = inst.get_node_or_null("TargetView/ViewportContainer/SubViewport") as SubViewport
	var tcam: Camera3D = inst.get_node_or_null("TargetView/ViewportContainer/SubViewport/Camera3D")
	var side_hits: Array = []  # [[cell, pos], …] 互异两格
	var seen_c: Array = []
	if tvv != null and tcont != null and tvp != null and tcam != null and tvp.size.x > 20:
		for fy: float in [0.35, 0.5, 0.65, 0.25, 0.75, 0.15, 0.85]:
			var y := tvp.size.y * fy
			for px: int in range(4, int(tvp.size.x) - 4, 4):
				var c: Variant = inst.call("_raycast_side_at", "Target", Vector2(px, y), tvv, tcam)
				if c != MISS and not seen_c.has(c):
					seen_c.append(c)
					side_hits.append([c, Vector2(px, y)])
					if side_hits.size() >= 2:
						break
			if side_hits.size() >= 2:
				break
	check(side_hits.size() >= 2, "P1 前置：Target 视图探得 2 互异格")
	if side_hits.size() < 2:
		inst.queue_free()
		_cleanup_save()
		finish()
		return
	var cellA: Vector3i = side_hits[0][0]
	var cellB: Vector3i = side_hits[1][0]
	var posA: Vector2 = side_hits[0][1]
	var posB: Vector2 = side_hits[1][1]
	# 前置：普通单击 A → 单选 A（既有语义保持）
	tcont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, true, posA))
	tcont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, posA))
	var sel0: Dictionary = inst.get("_side_selected")["Target"]
	check(sel0.has(cellA) and int(inst.call("get_side_selected_count")) == 1,
		"P1 前置：普通单击 A=单选 A（count=1）")
	# 核心红测：Ctrl+单击 B → A+B 均选中
	var ev_c1 := _mb(MOUSE_BUTTON_LEFT, true, posB)
	ev_c1.ctrl_pressed = true
	tcont.gui_input.emit(ev_c1)
	tcont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, posB))
	var sel1: Dictionary = inst.get("_side_selected")["Target"]
	check(sel1.has(cellA) and sel1.has(cellB) and int(inst.call("get_side_selected_count")) == 2,
		"P1：Ctrl+单击 B → A+B 均选中（红=旧抬起兜底清整侧只留旧起点 A；实测 count=%d hasA=%s hasB=%s）" % [
			int(inst.call("get_side_selected_count")), str(sel1.has(cellA)), str(sel1.has(cellB))])
	# 守卫：再 Ctrl+单击 B → 移除 B、A 保留（普通语义不回退）
	var ev_c2 := _mb(MOUSE_BUTTON_LEFT, true, posB)
	ev_c2.ctrl_pressed = true
	tcont.gui_input.emit(ev_c2)
	tcont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, posB))
	var sel2: Dictionary = inst.get("_side_selected")["Target"]
	check(sel2.has(cellA) and not sel2.has(cellB) and int(inst.call("get_side_selected_count")) == 1,
		"P1-守：再 Ctrl+单击 B → 移除 B、A 保留（count=1）")

	# ==================== 段 2：P2 锐眼差集分域过滤 ====================
	print("-- 段2 P2 锐眼差集分域 --")
	# 2a 纯函数：target_size(2,2,2) < block_size(4,4,4)，p 含越 target 域玩家格 (3,0,0)
	var arity := -1
	for m_v: Variant in gds.get_script_method_list():
		if typeof(m_v) == TYPE_DICTIONARY and String((m_v as Dictionary).get("name", "")) == "diff_vs_target":
			arity = ((m_v as Dictionary).get("args", []) as Array).size()
	var p2: Dictionary = {Vector3i(0, 0, 0): true, Vector3i(3, 0, 0): true}
	var t2: Array = [Vector3i(0, 0, 0)]
	var d2: Dictionary
	if arity >= 4:
		d2 = gds.call("diff_vs_target", p2, t2, Vector3i(2, 2, 2), Vector3i(4, 4, 4))
	else:
		# 旧实现唯一口径：p 也按 target 域 size 过滤（被测缺陷本身）
		d2 = gds.call("diff_vs_target", p2, t2, Vector3i(2, 2, 2))
	check((d2["extra"] as Array).has(Vector3i(3, 0, 0)),
		"P2-2a：越 target 域玩家格 (3,0,0) 参与差集 extra（红=旧按 target_size 剔除；arity=%d, extra=%s）" % [
			arity, str(d2["extra"])])
	# 2a 反向：t 仍按 target 域过滤（(5,0,0) 越 2³ 域 → 不进 missing）
	var d2b: Dictionary
	if arity >= 4:
		d2b = gds.call("diff_vs_target", {Vector3i(0, 0, 0): true}, ["0,0,0", "5,0,0"],
			Vector3i(2, 2, 2), Vector3i(4, 4, 4))
	else:
		d2b = gds.call("diff_vs_target", {Vector3i(0, 0, 0): true}, ["0,0,0", "5,0,0"], Vector3i(2, 2, 2))
	check(not (d2b["missing"] as Array).has(Vector3i(5, 0, 0)),
		"P2-2a2：t 按 target 域过滤回归（越域答案格不进 missing；实测 missing=%s）" % str(d2b["missing"]))
	# 2b 行为：_refresh_eye 分域——第 1 关（blocks 12×3×5）改 target_size=(1,1,1) +
	# target=单格 (0,0,0) → 越 target 域的玩家格 (1,0,0) 必须标红
	var orig_shape: Variant = inst.get("_target_shape0")
	var orig_tsz: Variant = inst.get("_target_size")
	var vsz: Variant = inst.get("_voxel_size")
	check(vsz is Vector3i and (vsz as Vector3i) == Vector3i(12, 3, 5),
		"P2 前置：_voxel_size=blocks 域 12×3×5（实测 %s）" % str(vsz))
	var rem_now: Dictionary = inst.get("_remaining")
	check(rem_now.has(Vector3i(0, 0, 0)) and rem_now.has(Vector3i(1, 0, 0)),
		"P2 前置：第 1 关 remaining 0-based 实心含 (0,0,0)/(1,0,0)")
	inst.call("clear_selection")
	inst.set("_target_shape0", [Vector3i(0, 0, 0)])
	inst.set("_target_size", Vector3i(1, 1, 1))
	inst.set("_eye_active", true)
	inst.call("_refresh_eye")
	var marked: Dictionary = inst.get("_eye_marked")
	check(marked.has(Vector3i(1, 0, 0)),
		"P2-2b：_refresh_eye 标红越 target 域玩家格 (1,0,0)（红=旧 p 被 target_size=(1,1,1) 剔除→_eye_marked 空；实测 size=%d）" % marked.size())
	inst.call("_finish_eye")
	inst.set("_target_shape0", orig_shape)
	inst.set("_target_size", orig_tsz)

	# ==================== 段 3：P3 全挖空态旋转/缩放照常、拾取/删除仍拦 ====================
	print("-- 段3 P3 全挖空态 --")
	var saved_rem: Dictionary = (inst.get("_remaining") as Dictionary).duplicate(true)
	inst.set("_remaining", {})
	var ortho0: float = float(inst.get("_ortho_size_main"))
	check(ortho0 > 0.0, "P3-5 前置：_ortho_size_main>0（实测 %.4f）" % ortho0)
	# 用 WHEEL_DOWN（放大 ×1.1）——初始 ortho 贴合动态下限，WHEEL_UP ×0.9 会被 clampf
	# 钳回下限看不出变化（绿跑实测 13.7053→13.7053 的钳制伪红根因）。
	inst.call("_on_main_view_gui_input", _mb(MOUSE_BUTTON_WHEEL_DOWN, true, Vector2(50, 50)))
	var ortho1: float = float(inst.get("_ortho_size_main"))
	check(not is_equal_approx(ortho0, ortho1),
		"P3-5a：全挖空态滚轮缩放生效（红=旧 blanket return 拦死；%.4f→%.4f）" % [ortho0, ortho1])
	var empty_pos := Vector2(10, 10)
	if inst.call("get_cell_hit", cam.project_ray_origin(empty_pos), cam.project_ray_normal(empty_pos)) != MISS:
		empty_pos = Vector2(10, 2)
	var yaw0: float = float(inst.get("_orbit_yaw"))
	inst.call("_on_main_view_gui_input", _mb(MOUSE_BUTTON_LEFT, true, empty_pos))
	inst.call("_on_main_view_gui_input", _mm_at(empty_pos + Vector2(30, 0)))
	var yaw1: float = float(inst.get("_orbit_yaw"))
	check(not is_equal_approx(yaw0, yaw1),
		"P3-5b：全挖空态左键拖拽轨道旋转生效（红=旧拦死；yaw %.4f→%.4f）" % [yaw0, yaw1])
	inst.call("_on_main_view_gui_input", _mb(MOUSE_BUTTON_LEFT, false, empty_pos + Vector2(30, 0)))
	# 拾取链仍被拦：点在体素几何位 → 不进划选（强制 NO_CELL→ORBIT）、零选中
	inst.call("clear_selection")
	inst.call("_on_main_view_gui_input", _mb(MOUSE_BUTTON_LEFT, true, probes[0][1]))
	check_eq(int(inst.get("_drag_mode")), dm_orbit,
		"P3-5c：全挖空态点体素位=ORBIT 不进划选（拾取链拦截下沉保持）")
	inst.call("_on_main_view_gui_input", _mb(MOUSE_BUTTON_LEFT, false, probes[0][1]))
	check((inst.call("get_selected_voxels") as Array).is_empty(),
		"P3-5d：全挖空态零选中（拾取链拦截保持）")
	# 删除分支仍拦（不崩、不误删）
	inst.call("_on_main_view_gui_input", _mb(MOUSE_BUTTON_RIGHT, true, probes[0][1]))
	inst.call("_on_main_view_gui_input", _mb(MOUSE_BUTTON_RIGHT, false, probes[0][1]))
	check((inst.call("get_selected_voxels") as Array).is_empty(),
		"P3-5e：全挖空态右键删除分支被拦（零选中、事件零异常）")
	inst.set("_remaining", saved_rem)

	# ==================== 段 4：P3 title 类型守卫（deferred 隔离红跑） ====================
	print("-- 段4 P3 title 守卫 --")
	inst.set("_level", {"title": null})
	_hud_ran = false
	call_deferred("_do_apply_hud", inst)  # 桥在测试脚本自身（inst 上无此方法）
	await process_frame
	await process_frame
	check(_hud_ran,
		"P3-7a：title=null 时 _apply_hud 不中止（红=旧 String(null) 运行期中止 deferred 链）")
	var tl: Label = inst.get_node_or_null("TopBar/TitleLabel") as Label
	var tl_text: String = tl.text if tl != null else "<null>"
	check(tl != null and tl_text == "第1关 第1关",
		"P3-7b：title 非字符串回退缺省口径（期望「第1关 第1关」，实测「%s」）" % tl_text)

	inst.queue_free()
	_cleanup_save()
	finish()
