extends "res://tests/test_base.gd"
## 批次 Q（spec §三/§五/§七）：Q1 主视图 Ctrl+左键取消选择（单点取消=现状 toggle 回归锁+划选
## 反选新增 DragMode.STROKE_DESELECT）+ Q3 聚焦守卫（聚焦态点空白不清选区不退聚焦、侧面板
## 整面板旋转热区、唯一退出=取消聚焦钮）。段 1~5=Q1（spec §七 1~6），段 6~12=Q3（§七 10~15）。
## 清档前奏（test_m_level_camera 先例）：实例化 level_scene 即在 _exit_tree 写检查点，起手/末尾各清一次档。
const SCENE_PATH := "res://scenes/level/level_scene.tscn"
const MISS := Vector3i(-1, -1, -1)
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
func _sel_has(inst: Node, c: Vector3i) -> bool:
	return (inst.call("get_selected_voxels") as Array).has(c)
func _cleanup_save() -> void:
	for p: String in ["user://save.json", "user://first_launch.flag"]:
		var abs_p: String = ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs_p):
			DirAccess.remove_absolute(abs_p)
## 自 from 沿其 y 行向右 8px 步进探针，收集前 n_dist 个互异命中格 [cell, 屏幕位]（与缩放态无关）。
## 去重须对照「已收格集」seen——计划初版误写 found.has(c)（found 装 [cell,pos] 对，与
## Vector3i 永不相等 → 去重失效、三探针坍缩同格，红灯 6/17 实证），按注释「互异」契约修正。
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
# ===== 清档纪律（tools/README_走查清档规范.md，批次V回修②B 补齐，test_v_save_domain 同款）=====
# 起测前备份 user:// 真实档案（save.json/first_launch.flag 及可触及的 .tmp/.bak 四件组），
# 终测统一经 finish() 收口还原：先同步 free 测试挂载节点（level._exit_tree 兜底写档等
# 「退出写回」先落测试域磁盘，规范第 6 条），再逐件还原 + SaveManager load_game 重同步内存
# + 逐字节等价断言 + EVID 证据行。备份路径必须带全 user:// 前缀（相对路径在 FileAccess/
# DirAccess 间解析漂移 → 备份链静默失效，test_n10 先例）；每文件独立备份前缀防崩溃残留互踩。
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_r2b_qli_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _pre_save_text: String = ""   # 起测前真实 save.json 原文（还原等价自检基准）

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _disc_del(p: String) -> void:
	var a: String = _disc_abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _backup_user() -> void:
	# 规范第 1 条：任何删/写档操作之前备份真实档案（有档才备份；还原「有备份才回拷」幂等，
	# 起测前不存在的档案终测后仍不存在——测试自建残留一律清零）
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	# 防退出写回（规范第 6 条）：先同步 free 测试挂载的非 autoload 节点——level._exit_tree
	# 兜底写档（N9）若拖到进程退出树序，会在还原之后把测试态写回真实档案；提前 free 令
	# 兜底写档落测试域磁盘，紧随其后的逐件还原即将其覆盖。
	for c: Node in root.get_children():
		if not DISC_AUTOLOADS.has(String(c.name)):
			c.free()
	# 规范第 2 条：逐件还原 + load_game 重同步内存（防后续 save_game 把测试态写回真实档案）
	for p: String in DISC_WATCHED:
		_disc_del(p)
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(_disc_abs(bk))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()
	# 纪律自检：还原后 save.json 与起测前逐字节等价（起测前无档 ↔ 还原后无档）
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|qli|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	_backup_user()
	_cleanup_save()
	get_root().get_node("SaveManager").call("load_game")  # autoload 直取（test_shop_panel.gd:50 先例）
	# 枚举经 get_script_constant_map().get() 读（动态访问未定义常量会挂死 --script）
	var dm: Dictionary = (load("res://scenes/level/level_scene.gd") as Script).get_script_constant_map().get("DragMode", {})
	var dm_none: int = int(dm.get("NONE", -1))
	var dm_orbit: int = int(dm.get("ORBIT", -1))
	var dm_desel: int = int(dm.get("STROKE_DESELECT", -1))
	check(dm_none == 0 and int(dm.get("STROKE", -1)) == 1 and dm_orbit == 2 and dm_desel == 3,
		"Q1 前置：NONE/STROKE/ORBIT=0/1/2 不变+追加 STROKE_DESELECT=3（红灯期即红）")
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
	check(cont != null and vps != null and cam != null and vps.size.x > 1, "Q1 前置：容器/视口/相机存在")
	var probes: Array = _probe_cells(inst, cam, Vector2(vps.size.x * 0.5, vps.size.y * 0.5), 3) if (cont != null and vps != null and cam != null and vps.size.x > 1) else []
	check_eq(probes.size(), 3, "Q1 前置：水平探针命中 3 互异格（probes[i]=[cell,屏幕位]，x 递增）")
	if probes.size() < 3:
		inst.queue_free()
		_cleanup_save()
		finish()
		return
	# 段 1（spec §七 1）：toggle 语义回归；末两行为段 2 前置（前两格双选）
	inst.call("select_voxel", probes[0][0], true)
	check(_sel_has(inst, probes[0][0]), "toggle：未选格 additive=true → 加入选区")
	inst.call("select_voxel", probes[0][0], true)
	check(not _sel_has(inst, probes[0][0]), "toggle：已选格 additive=true → 移出选区")
	inst.call("select_voxel", probes[0][0], true)
	inst.call("select_voxel", probes[1][0], true)
	# 段 2（spec §七 2/3，R1+R2）：Ctrl+按下已选格 → 取消该格+进反选划选态；motion 扫过右邻格亦取消
	var ev_down := _mb(MOUSE_BUTTON_LEFT, true, probes[0][1])
	ev_down.ctrl_pressed = true
	cont.gui_input.emit(ev_down)
	check(not _sel_has(inst, probes[0][0]) and _sel_has(inst, probes[1][0]), "R1：Ctrl+按下已选格仅取消该格，其余保留")
	check_eq(int(inst.get("_drag_mode")), dm_desel, "R2 下入：按下后 _drag_mode=STROKE_DESELECT")
	cont.gui_input.emit(_mm_at(probes[1][1]))
	check(not _sel_has(inst, probes[0][0]) and not _sel_has(inst, probes[1][0]), "R2 主路径：反选划选扫过已选格 → 亦取消")
	cont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, probes[1][1]))
	check_eq(int(inst.get("_drag_mode")), dm_none, "R4 边界：反选划选抬起无兜底，_drag_mode 回 NONE")
	check_eq(bool(inst.get("_stroke_new_seen")), false, "R4 边界：反选路径不写 _stroke_new_seen")
	# 段 3（spec §七 4，R2 边界）：扫过未选格不追加；范围外已选格保留；段 4（§七 5，R4）：原地点抬不触发单选替换
	# 先 clear 再双选（同段 4 setup 口径）：select_voxel additive=true 是 toggle，段 2 红灯期
	# motion 无操作（正是被测缺陷）p1 仍选中，直接 toggle 会误删——红灯期级联 +2 红实证修正
	inst.call("clear_selection")
	inst.call("select_voxel", probes[0][0], true)
	inst.call("select_voxel", probes[1][0], true)
	var ev_down2 := _mb(MOUSE_BUTTON_LEFT, true, probes[0][1])
	ev_down2.ctrl_pressed = true
	cont.gui_input.emit(ev_down2)
	cont.gui_input.emit(_mm_at(probes[2][1]))
	check(not _sel_has(inst, probes[2][0]), "R2 边界：反选划选扫过未选格不追加")
	check(_sel_has(inst, probes[1][0]), "R2 边界：划选范围外已选格保留")
	cont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, probes[2][1]))
	check_eq((inst.call("get_selected_voxels") as Array).size(), 1, "R2 边界：全程选区仅剩未扫过的 1 格")
	inst.call("clear_selection")
	inst.call("select_voxel", probes[0][0], true)
	var ev_down3 := _mb(MOUSE_BUTTON_LEFT, true, probes[0][1])
	ev_down3.ctrl_pressed = true
	cont.gui_input.emit(ev_down3)
	cont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, probes[0][1]))
	check(not _sel_has(inst, probes[0][0]) and (inst.call("get_selected_voxels") as Array).is_empty()
		and int(inst.get("_drag_mode")) == dm_none and not bool(inst.get("_stroke_new_seen")),
		"R4：原地点击已选格=取消该格，抬起无单选替换兜底（不反向加回）、mode 回 NONE、_stroke_new_seen 恒 false")
	# 段 5（spec §七 6，R3 现状回归）：Ctrl+按下未选格→追加+点选态；Ctrl+按下空白→ORBIT
	var ev_down4 := _mb(MOUSE_BUTTON_LEFT, true, probes[0][1])
	ev_down4.ctrl_pressed = true
	cont.gui_input.emit(ev_down4)
	check(_sel_has(inst, probes[0][0]) and int(inst.get("_drag_mode")) == dm_none, "R3：Ctrl+按下未选格 → 追加选中且维持点选态 NONE")
	cont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, probes[0][1]))
	var empty_pos := Vector2(10, 10)  # 4c 先例：角落空白起点；命中木料则上移兜底
	if inst.call("get_cell_hit", cam.project_ray_origin(empty_pos), cam.project_ray_normal(empty_pos)) != MISS:
		empty_pos = Vector2(10, 2)
	var ev_down5 := _mb(MOUSE_BUTTON_LEFT, true, empty_pos)
	ev_down5.ctrl_pressed = true
	cont.gui_input.emit(ev_down5)
	cont.gui_input.emit(_mm_at(empty_pos + Vector2(30, 0)))
	check_eq(int(inst.get("_drag_mode")), dm_orbit, "R3：Ctrl+按下空白 → ORBIT 旋转态（现状）")
	cont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, empty_pos + Vector2(30, 0)))
	inst.call("clear_selection")
	# ==================== 段 6~12：批次 Q3 聚焦守卫（spec §五/§七 10~15；直驱先例 test_n_focus_fullscreen :322/:359） ====================
	var tvv: Node = inst.get_node_or_null("TargetView/ViewportContainer/SubViewport/VoxelView")
	var tcont: SubViewportContainer = inst.get_node_or_null("TargetView/ViewportContainer") as SubViewportContainer
	var tvp: SubViewport = inst.get_node_or_null("TargetView/ViewportContainer/SubViewport") as SubViewport
	var tcam: Camera3D = inst.get_node_or_null("TargetView/ViewportContainer/SubViewport/Camera3D")
	var side_pos := Vector2(-1, -1)
	if tvv != null and tcont != null and tvp != null and tcam != null and tvp.size.x > 20:
		for px: int in range(6, int(tvp.size.x) - 6, 6):
			if inst.call("_raycast_side_at", "Target", Vector2(px, tvp.size.y * 0.5), tvv, tcam) != MISS:
				side_pos = Vector2(px, tvp.size.y * 0.5)
				break
	check(side_pos.x >= 0.0, "Q3 前置：Target 容器/视口/相机在位，面板中线探得几何命中位（聚焦态拾取仍命中=问题 B 前提）")
	var side_cell: Variant = inst.call("_raycast_side_at", "Target", side_pos, tvv, tcam)
	var t_cells: Array = tvv.call("get_built_cells")
	var side_sel: Vector3i = t_cells[0] if side_cell != t_cells[0] else t_cells[1]
	inst.call("_select_side_cell", "Target", side_sel, tvv, true)
	inst.call("select_voxel", probes[0][0], true)
	check(inst.get("_side_selected")["Target"].has(side_sel) and _sel_has(inst, probes[0][0]),
		"Q3 前置：侧选 1+主选 1（_toggle_focus 空选区不激活故先备选区；focus_btn 不 disabled 前提）")
	# 段 6（spec §七 10，F1）：聚焦态主视空白点抬 → 不清选区/不退聚焦/mode 回 NONE
	inst.call("_toggle_focus")
	check(bool(inst.get("_focus_active")), "Q3：_toggle_focus 激活聚焦（_focus_active 于 :1509 同步置位）")
	cont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, true, empty_pos))
	cont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, empty_pos))
	check(_sel_has(inst, probes[0][0]) and bool(inst.get("_focus_active")) and int(inst.get("_drag_mode")) == dm_none, "F1：聚焦态空白点抬不清选区、不退聚焦、mode 回 NONE")
	# 段 7（spec §七 11）：聚焦态主视空白拖拽 → 旋转保留
	var yaw_q: float = float(inst.get("_orbit_yaw"))
	cont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, true, empty_pos))
	cont.gui_input.emit(_mm_at(empty_pos + Vector2(30, 0)))
	cont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, empty_pos + Vector2(30, 0)))
	check(not is_equal_approx(float(inst.get("_orbit_yaw")), yaw_q) and bool(inst.get("_focus_active")) and _sel_has(inst, probes[0][0]), "F1：聚焦态空白拖拽旋转保留（yaw 变化），选区/聚焦保持")
	# 段 8（spec §七 12，F3=问题 B 修复）：聚焦态侧视按下（几何命中位）→ 一律 ORBIT(2)；拖拽 _side_yaw 变化
	var yaw_t: float = float(inst.get("_side_yaw")["Target"])
	tcont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, true, side_pos))
	tcont.gui_input.emit(_mm_at(side_pos + Vector2(30, 0)))
	check(int(inst.get("_side_pressed")["Target"]) == 2 and not inst.get("_side_selected")["Target"].has(side_cell) and not is_equal_approx(float(inst.get("_side_yaw")["Target"]), yaw_t), "F3：按下命中位拦为 ORBIT(2)（红=1）、不误选该格、拖拽 _side_yaw 变化（旋转生效）")
	tcont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, side_pos + Vector2(30, 0)))
	# 段 9（spec §七 13，F1）：聚焦态侧视点抬（位移 0）→ 不清该侧选区（Edit H 落点）
	tcont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, true, side_pos))
	tcont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, side_pos))
	check(inst.get("_side_selected")["Target"].has(side_sel) and int(inst.call("get_side_selected_count")) == 1 and bool(inst.get("_focus_active")) and int(inst.get("_side_pressed")["Target"]) == 0, "F1：聚焦态侧视点抬不清侧选区（红=单选替换错换格）、不退聚焦、状态复位")
	# 段 10（spec §5.3 矩阵）：聚焦态 Ctrl+按下已选格 → Q1 反选分支不可达（守卫在分流上游）
	# 断言在 release 之前读 _drag_mode（计划初版 release 在断言前——抬起路径恒置 NONE，断言永假，
	# 走码裁决：按下态断言「不 toggle 且进 ORBIT」语义不变，release 移至断言后）
	var ev_q := _mb(MOUSE_BUTTON_LEFT, true, probes[0][1])
	ev_q.ctrl_pressed = true
	cont.gui_input.emit(ev_q)
	check(_sel_has(inst, probes[0][0]) and int(inst.get("_drag_mode")) == dm_orbit, "Q1×Q3：聚焦态 Ctrl+按下不 toggle 且进 ORBIT（STROKE_DESELECT 不可达）")
	cont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, probes[0][1]))
	# 段 11（spec §七 15 F4 + §八风险 4）：聚焦态 Esc 无操作；focus_btn 可达不困死
	var ev_esc := InputEventKey.new()
	ev_esc.keycode = KEY_ESCAPE
	ev_esc.pressed = true
	inst.call("_unhandled_input", ev_esc)
	check(_sel_has(inst, probes[0][0]) and bool(inst.get("_focus_active")), "F4：聚焦态 Esc 被拦（选区/聚焦不变）")
	var qbtn: Button = inst.get_node_or_null("TopBar/Buttons/FocusButton")
	check(qbtn != null and not qbtn.disabled and qbtn.text == "取消聚焦", "风险 4 保险：聚焦态 focus_btn 可点（disabled=false+「取消聚焦」=唯一退出路径可达）")
	# 段 12（spec §七 14，F2）：唯一退出=取消聚焦；退出后选区保留、空白单击恢复清选
	inst.call("_toggle_focus")
	check(not bool(inst.get("_focus_active")) and _sel_has(inst, probes[0][0]) and int(inst.call("get_side_selected_count")) == 1, "F2：退出聚焦选区保留（主/侧不变）")
	cont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, true, empty_pos))
	cont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, empty_pos))
	check((inst.call("get_selected_voxels") as Array).is_empty(), "F2：退出后空白单击恢复清选语义（现状回归）")
	inst.queue_free()
	_cleanup_save()
	finish()
