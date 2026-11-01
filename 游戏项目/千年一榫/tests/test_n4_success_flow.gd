extends "res://tests/test_base.gd"
## N4（批次 N / spec §6.6 + §6.7）：成功动画四段式重做——判定用例（TDD 红灯先行）。
## 契约（spec §6.6 方案口径 1~6 + §九风险 9~12 + 任务单 2026-09-09 追加）：
##   ①四段相位机：凝聚（三视图分组统一 实体→粒子面）→持续→突然散开→聚合（同批粒子接力
##     聚成屏幕单一金色建模）→回看（自转+玩家拖拽旋转，末段对位结算位姿）；
##     总时长 ∈[2.5,4]s（spec 8.4 硬约束）；段钩子 get_success_seg()。
##   ②分组凝聚：复用 N3 全屏三色管线（activate_channel_all 全量凝聚接口），废止 Fisher-Yates
##     逐体素随机序；凝聚段起点=体素实体在屏（风险 9；deactivate_immediate 先行语义保持）。
##   ③粒子贯穿：聚合段起点=散开末帧三通道逐点屏幕位接力（relay_sample 纯函数，计数以文物
##     点云为准）；同帧移交（N3 层 release_particles 清散点且不还原体素，风险 10）。
##   ④同位续接：对位参数只读单点 read_settle_align（instantiate 结算场景读 CenterMount 锚点
##     + live 读 viewer 构建参数，实例不入树用后即 free；不改结算文件）；防御断言
##     mount_rect_ok（rect 非零且在屏内）；失配回退=覆盖层建模淡出（_align_fading）软衔接。
##   ⑤路由零改动守护：_goto_settle 评级/天赋值/advance_progress/SETTLE 路由语义不变；
##     _skip_success_animation 行为不回归；GRADE_TIME_*/CHAPTER_PERFECT_TALENT 不动。
## 坑纪律（spec 铁律 5）：无头 MultiMesh 色/transform 读回恒 0 → 属性证据链
##   （instance_count/材质标志/自持数组）；--script 模式 class_name 时序 → load()+call()（P2-5）；
##   布局断言先钉设计视口 1152×648（expand 容器伪象实证坑）。

const FX_SCRIPT := "res://scripts/focus_fx.gd"
const VOX_SCRIPT := "res://scripts/level_voxel_view.gd"
const LS_SCRIPT := "res://scenes/level/level_scene.gd"
const LEVEL_SCENE := "res://scenes/level/level_scene.tscn"
const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const ST_SETTLE := 5
const DESIGN := Vector2(1152, 648)

var game: Variant
var save: Variant
var lib: Variant

func _cleanup_files() -> void:
	for p: String in [SAVE_PATH, FLAG_PATH]:
		var abs: String = ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs):
			DirAccess.remove_absolute(abs)

func _reset_save() -> void:
	_cleanup_files()
	save.load_game()

func _target_cells() -> Array:
	var lvl: Dictionary = lib.get_level(1)
	check(not lvl.is_empty(), "前置：第 1 关关卡数据已扫描（levels_data）")
	if lvl.is_empty():
		return []
	var pieces: Array = (lvl["data"] as Dictionary)["pieces"]
	return (pieces[0] as Dictionary)["target_shapes"][0]

func _make_level(ch: int) -> Node:
	var inst: Node = (load(LEVEL_SCENE) as PackedScene).instantiate()
	inst.call("set_context", {"chapter": ch})
	add_child(inst)
	await process_frame
	await process_frame
	return inst

func _count_hidden(inst: Node) -> int:
	var vv: Node = inst.get_node_or_null("MainView/ViewportContainer/SubViewport/VoxelView")
	if vv == null:
		return -1
	var hid := 0
	for c: Variant in (vv.call("get_built_cells") as Array):
		var n: MeshInstance3D = vv.call("get_voxel_node", Vector3i(c))
		if n != null and not n.visible:
			hid += 1
	return hid

func _find_mmi(node: Node) -> MultiMeshInstance3D:
	for c: Node in node.get_children():
		if c is MultiMeshInstance3D:
			return c as MultiMeshInstance3D
		var found: MultiMeshInstance3D = _find_mmi(c)
		if found != null:
			return found
	return null

func _in_subtree(node: Node, sub_root_name: String) -> bool:
	var cur: Node = node
	while cur != null:
		if cur.name == sub_root_name:
			return true
		cur = cur.get_parent()
	return false

func _p3arr_or_empty(v: Variant) -> PackedVector3Array:
	return v if v is PackedVector3Array else PackedVector3Array()

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
const DISC_BK_PREFIX := "user://_r2b_n4_backup_"
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
	print("EVID|user_restore|n4|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_n4_success_flow ==")
	_backup_user()
	Engine.max_fps = 60  # 无上限帧率会让逐帧动画空转（同 test_m 口径），测试限 60fps
	game = get_root().get_node("Game")
	save = get_root().get_node("SaveManager")
	lib = get_root().get_node("LevelLibrary")
	lib.scan_directory("res://levels_data")

	var fx_s: Script = load(FX_SCRIPT) as Script
	var ls_s: Script = load(LS_SCRIPT) as Script
	check(fx_s != null and ls_s != null, "N4 前置：focus_fx.gd / level_scene.gd 可加载")
	if fx_s == null or ls_s == null:
		finish()
		return
	var fcmap: Dictionary = fx_s.get_script_constant_map()
	var lcmap: Dictionary = ls_s.get_script_constant_map()

	# ==================== A. FocusFX N4 复用扩展（spec §6.6 方案口径 2/3；「N批：N4复用扩展」）====================
	check_eq(int(fcmap.get("PHASE_HOLD", -1)), 5,
		"N4①：PHASE_HOLD=5（持续段新相位；IDLE~RETURN 0~4 N3 契约不变）")
	check_eq(int(fcmap.get("PHASE_IDLE", -1)), 0, "N4①：PHASE_IDLE=0（N3 语义保持）")
	check_eq(int(fcmap.get("PHASE_CONDENSE", -1)), 1, "N4①：PHASE_CONDENSE=1（N3 语义保持）")
	check_eq(int(fcmap.get("PHASE_SPREAD", -1)), 2, "N4①：PHASE_SPREAD=2（N3 语义保持）")
	check_eq(int(fcmap.get("PHASE_STEADY", -1)), 3, "N4①：PHASE_STEADY=3（N3 语义保持）")
	check_eq(int(fcmap.get("PHASE_RETURN", -1)), 4, "N4①：PHASE_RETURN=4（N3 语义保持）")
	var fx_probe: Node = (fx_s as GDScript).new()
	check(fx_probe.get("n4_condense_time") != null and fx_probe.get("n4_hold_time") != null \
		and fx_probe.get("n4_spread_time") != null,
		"N4①：相位时长覆盖入口存在（n4_condense/hold/spread_time，默认值≤0/0 走 N3 常量）")
	check(fx_probe.has_method("activate_channel_all") and fx_probe.has_method("release_particles"),
		"N4②③：activate_channel_all（全量分组凝聚）/ release_particles（粒子移交清场）接口存在")
	fx_probe.free()

	# 组装小视口世界（同 test_m 口径：正交 cam.size=6）
	var world := Node3D.new()
	add_child(world)
	var vp := SubViewport.new()
	vp.size = Vector2i(100, 80)
	world.add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 6.0
	cam.position = Vector3(0, 0, 20)
	vp.add_child(cam)
	var vv: Node = (load(VOX_SCRIPT) as GDScript).new()
	vv.name = "VoxelView"
	vp.add_child(vv)
	vv.call("build_voxels", ["0,0,0", "1,0,0", "2,0,0", "3,0,0"], Vector3i(4, 1, 1), StandardMaterial3D.new())
	var fx: Node = (fx_s as GDScript).new()
	fx.name = "FocusFX"
	world.add_child(fx)
	fx.call("bind_channel", "Main", vp)
	await process_frame
	var built: Array = vv.call("get_built_cells")

	# A-1 activate_channel_all：全量凝聚（无选区分割=分组统一；face 点数=22×全部体素）
	check_eq(bool(fx.call("activate_channel_all", "Main", built)), true,
		"N4②：activate_channel_all（remaining=全部构建格）激活成功")
	check_eq(int(fx.call("get_phase")), int(fcmap.get("PHASE_CONDENSE", -1)),
		"N4②：全量激活后进入 CONDENSE（凝聚段体素实体在屏=风险 9 口径）")
	var v_unsel: MeshInstance3D = vv.call("get_voxel_node", Vector3i(2, 0, 0))
	check(v_unsel != null and v_unsel.visible == true,
		"N4②：凝聚期体素仍可见（实体→点云面过渡；M批/Gb 立即逐格 hide 时序废止）")
	var fx_chs: Dictionary = fx.get("_channels")
	var face_all: PackedVector2Array = fx_chs.get("Main", {}).get("face", PackedVector2Array())
	check_eq(face_all.size(), 7 * 4,
		"O批等价替换（2026-09-10 用户反馈②降密）：全量凝聚 face 点数=DOTS_PER_VOXEL 7×全部体素 28（原 22 档废止；无选区分割，非 Fisher-Yates 随机序）")
	# A-2 持续段（PHASE_HOLD）+ 时长覆盖入口生效
	var fx2: Node = (fx_s as GDScript).new()
	fx2.name = "FocusFX2"
	world.add_child(fx2)
	fx2.call("bind_channel", "Main", vp)
	fx2.set("n4_condense_time", 0.05)
	fx2.set("n4_hold_time", 0.4)
	fx2.set("n4_spread_time", 0.05)
	await process_frame
	check_eq(bool(fx2.call("activate_channel_all", "Main", built)), true, "N4①：覆盖档下再次激活成功")
	await create_timer(0.12).timeout  # > condense 0.05，< hold 0.4
	check_eq(int(fx2.call("get_phase")), int(fcmap.get("PHASE_HOLD", -1)),
		"N4①：凝聚完成 → HOLD 持续段（n4_hold_time 覆盖生效）")
	check_eq(float(fx2.call("get_spread_progress")), 0.0,
		"N4①：持续段散开进度=0（get_spread_progress HOLD 分支）")
	check(v_unsel != null and v_unsel.visible == false,
		"N4②：凝聚完成后体素隐藏（点云面接管=无空窗跳变）")
	await create_timer(0.5).timeout  # > hold 0.4，进入 spread 0.05
	check(int(fx2.call("get_phase")) >= int(fcmap.get("PHASE_STEADY", -1)),
		"N4①：持续完成 → 散开（n4_spread_time 覆盖 0.05）→ 稳态")
	# A-3 release_particles：粒子移交清场（不还原体素——风险 10 生命周期移交）
	fx2.call("release_particles")
	check_eq(int(fx2.call("get_phase")), int(fcmap.get("PHASE_IDLE", -1)), "N4③：release_particles → IDLE")
	var mmi2: MultiMeshInstance3D = _find_mmi(fx2)
	check(mmi2 == null or mmi2.multimesh == null, "N4③：release 后 MultiMesh 清空（散点不再渲染）")
	check(v_unsel != null and v_unsel.visible == false,
		"N4③：release 后体素保持隐藏（成功流程体素归属成功动画，不还原——与 deactivate_immediate 分歧点）")
	var chs2: Dictionary = fx2.get("_channels")
	var face_after: PackedVector2Array = chs2.get("Main", {}).get("face", PackedVector2Array())
	check(face_after.is_empty() and not bool(fx2.call("is_channel_active", "Main")),
		"N4③：release 后通道态清空（face 数组空+active=false）")
	fx2.call("release_particles")  # 幂等
	check_eq(int(fx2.call("get_phase")), int(fcmap.get("PHASE_IDLE", -1)), "N4③：release 幂等（已 IDLE 不崩）")
	# A-4 deactivate_immediate 成功动画入口语义保持（spec 风险 2 锁定）
	fx.call("deactivate_immediate")  # A-1 激活的凝聚先复位（回 IDLE 前提，幂等安全）
	check_eq(bool(fx.call("activate_channel_all", "Main", built)), true, "N4：fx 再激活（为 immediate 断言备场）")
	fx.call("deactivate_immediate")
	check_eq(int(fx.call("get_phase")), int(fcmap.get("PHASE_IDLE", -1)),
		"N4：deactivate_immediate 立即复位 IDLE（成功动画入口语义保持，spec 风险 2）")
	check(v_unsel != null and v_unsel.visible == true,
		"N4：deactivate_immediate 还原体素（N3 语义保持——聚焦退场路径不变）")
	fx.call("deactivate_immediate")
	check_eq(int(fx.call("get_phase")), int(fcmap.get("PHASE_IDLE", -1)), "N4：deactivate_immediate 幂等不崩")
	world.queue_free()

	# ==================== B. 四段时长常量与段钩子（spec §6.6 方案口径 1；spec 8.4 硬约束）====================
	var a_c: float = float(lcmap.get("ANIM_CONDENSE", -1.0))
	var a_h: float = float(lcmap.get("ANIM_HOLD", -1.0))
	var a_sp: float = float(lcmap.get("ANIM_SPREAD", -1.0))
	var a_a: float = float(lcmap.get("ANIM_AGGREGATE", -1.0))
	var a_r: float = float(lcmap.get("ANIM_REVIEW", -1.0))
	check_eq(a_c, 0.25, "O批等价替换（2026-09-10 用户口径③凝聚持续 0.5s 后平衡时长）：ANIM_CONDENSE=0.25（N批 0.3 废止留痕）")
	check_eq(a_h, 0.5, "O批：ANIM_HOLD=0.5（凝聚点云面稳态持续 0.5s=FOCUS_HOLD_TIME，用户口径③；N批 0.15 废止留痕）")
	check_eq(a_sp, 1.2, "P批波2等价替换（2026-09-10 用户口径 P-C 散开放慢+滞空）：ANIM_SPREAD=1.2（散开=屏外环域+滞空缓动；O批 0.5 废止留痕）")
	check_eq(a_a, 1.1, "P批波2等价替换：ANIM_AGGREGATE=1.1（聚合=结算挂载位；O批 1.3 随总时长重排废止留痕）")
	check_eq(a_r, 0.9, "P批波2等价替换：ANIM_REVIEW=0.9（回看全程自转直入结算；O批 1.0 废止留痕）")
	var seg_sum: float = a_c + a_h + a_sp + a_a + a_r
	check(seg_sum >= 2.5 and seg_sum <= 4.0,
		"N4①：四段总时长 %.2f ∈ [2.5,4.0]s（spec 8.4 硬约束：凝聚+持续+散开+聚合+回看）" % seg_sum)
	# P批波2等价替换：ANIM_ALIGN=0.3（回看末对位窗口）随「不回正不重建」架构废止——
	# 回看段全程自转，建模以玩家姿态直入结算（结算 UI 由 level 覆盖层承载）。
	check(lcmap.get("ANIM_ALIGN", null) == null,
		"P批波2等价替换：ANIM_ALIGN 对位窗口常量已废止（回看全程自转，建模保持玩家姿态直入结算不回正）")
	check_eq(float(lcmap.get("SPIN_SPEED_DEG", -1.0)), 20.0, "N4④：SPIN_SPEED_DEG=20（回看自转，M-Gb 语义保持）")
	var tint_v: Variant = lcmap.get("CLOUD_TINT")
	check(tint_v is Color and (tint_v as Color) == Color(0.96, 0.77, 0.26),
		"N4③：CLOUD_TINT=#F5C542（聚合金色建模口径保持，对齐 settle GOLD_TINT）")
	check_eq(float(lcmap.get("CLOUD_TINT_STRENGTH", -1.0)), 0.85, "N4③：CLOUD_TINT_STRENGTH=0.85（tint 强度保持）")
	check(float(lcmap.get("CLOUD_DELAY_MAX", -1.0)) > 0.0, "N4③：CLOUD_DELAY_MAX 保留（聚合逐点分层延迟）")
	var inst_probe: Node = (ls_s as GDScript).new()
	check(inst_probe.has_method("get_success_seg") and inst_probe.has_method("read_settle_align"),
		"N4：段钩子/对位单点接口存在（get_success_seg/read_settle_align；relay_sample 纯函数 C 段直测）")
	inst_probe.free()

	# ==================== C. 同位续接对位：只读单点 + 纯函数（spec §6.6 方案口径 4；风险 12）====================
	# C-1 纯函数：结算投影匹配 fov（fov_overlay = 2·atan(tan(fov/2)·vsz_h/mount_h)）
	var fov_match: float = float(ls_s.call("settle_match_fov", 45.0, 388.8, 648.0))
	check(absf(fov_match - 69.2) < 0.5,
		"N4④：settle_match_fov(45,388.8,648)≈69.2°（覆盖层全屏相机投影匹配结算挂载视口，实际 %.3f）" % fov_match)
	var fov_eq: float = float(ls_s.call("settle_match_fov", 45.0, 648.0, 648.0))
	check(absf(fov_eq - 45.0) < 0.001,
		"N4④：settle_match_fov 等高恒等（mount_h==vsz_h → fov 不变，公式自洽；实际 %.6f）" % fov_eq)
	var ppu_a: float = 648.0 / (2.0 * 2.8 * tan(deg_to_rad(fov_match * 0.5)))
	var ppu_b: float = 388.8 / (2.0 * 2.8 * tan(deg_to_rad(22.5)))
	check(absf(ppu_a - ppu_b) < 0.01,
		"N4④：投影匹配一致性（覆盖层 px/世界单位 %.4f == 结算挂载 %.4f——同位续接的数学前提）" % [ppu_a, ppu_b])
	# C-2 纯函数：挂载 rect 防御断言（非零且在屏内）
	check_eq(bool(ls_s.call("mount_rect_ok", Rect2(0, 0, 0, 0), DESIGN)), false,
		"N4④：mount_rect_ok 零矩形 → false（防御断言，风险 12）")
	check_eq(bool(ls_s.call("mount_rect_ok", Rect2(-600, -300, 2400, 1400), DESIGN)), false,
		"N4④：mount_rect_ok 越屏矩形 → false（防御断言）")
	check_eq(bool(ls_s.call("mount_rect_ok", Rect2(207.4, 38.9, 737.3, 388.8), DESIGN)), true,
		"N4④：mount_rect_ok 合法矩形 → true（settle CenterMount 实锚点 0.18/0.06/0.82/0.66×1152×648）")
	# C-3 纯函数：逐点采样接力（计数以文物点云为准）
	var flat := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)])
	var relay5: PackedVector2Array = ls_s.call("relay_sample", flat, 5)
	check_eq(relay5.size(), 5, "N4③：relay_sample 输出数=文物点数 n（计数以文物点云为准）")
	var relay_ok := relay5.size() == 5 and relay5[0] == Vector2(0, 0) and relay5[1] == Vector2(10, 0) \
		and relay5[2] == Vector2(20, 0) and relay5[3] == Vector2(0, 0) and relay5[4] == Vector2(10, 0)
	check(relay_ok, "N4③：relay_sample 循环采样确定性（i%m 取散开末帧位——逐点接力）")
	var relay_empty: PackedVector2Array = ls_s.call("relay_sample", PackedVector2Array(), 3)
	check_eq(relay_empty.size(), 0, "N4③：relay_sample 空散点群防御（返回空=聚合段回退原地成形）")
	# C-4 只读单点：真实结算场景对位参数（instantiate 用后即 free；不改结算文件）
	_reset_save()
	var inst0: Node = await _make_level(1)
	var align: Dictionary = inst0.call("read_settle_align", DESIGN)
	check(bool(align.get("ok", false)), "N4④：read_settle_align ok=true（结算场景可读，防御断言通过）")
	check(align.get("ok", false) and absf(float(align.get("dist", -1.0)) - 2.8) < 0.01 \
		and absf(float(align.get("fov", -1.0)) - 45.0) < 0.01,
		"N4④：对位参数=结算实读（dist≈2.8 / fov≈45——live 读 viewer 构建参数，只读单点）")
	check(align.get("ok", false) and absf(float(align.get("yaw", -1.0)) - 30.0) < 0.01 \
		and absf(float(align.get("pitch", -1.0)) - 22.0) < 0.01,
		"N4④：对位姿态=结算初始朝向（yaw≈30/pitch≈22，回看段末转向目标）")
	check(align.get("ok", false) and absf(float(align.get("fit", -1.0)) - 2.2) < 0.01 \
		and float(align.get("px_per_world", 0.0)) > 100.0,
		"N4④：归一化口径实读（fit≈2.2 对角线 / px_per_world≈167 px每世界单位——覆盖层建模同尺度重建）")
	var mrect: Rect2 = align.get("rect", Rect2())
	check(mrect.size.x > 100.0 and mrect.size.y > 100.0 and bool(ls_s.call("mount_rect_ok", mrect, DESIGN)),
		"N4④：挂载 rect 非零且在屏内（CenterMount 锚点×设计视口，%s）" % str(mrect))
	inst0.queue_free()

	# ==================== D. 全流程四段走通（分组凝聚→散开→接力聚合→回看对位→路由守护）====================
	_reset_save()
	var talent0: int = int(save.get_talent())
	var inst: Node = await _make_level(1)
	var target: Array = _target_cells()
	var jb: Button = inst.get_node_or_null("TopBar/Buttons/JoinButton")
	check(jb is Button and not target.is_empty(), "N4 前置：JoinButton 与 target 就绪")
	if jb != null and not target.is_empty():
		inst.set("anim_time_scale", 8.0)
		inst.call("set_remaining_for_test", target)
		jb.pressed.emit()  # → _begin_success → 四段式
		# D-1 同帧：分组凝聚已激活（三通道同帧统一凝聚）+ 体素实体在屏（风险 9）
		var fxl: Node = inst.get("_fx_layer")
		check(fxl != null and bool(fxl.call("is_channel_active", "Main")) \
			and bool(fxl.call("is_channel_active", "Target")) and bool(fxl.call("is_channel_active", "Join")),
			"N4②：_begin_success 同帧三通道全量激活（Main/Target/Join 分组统一凝聚；deactivate_immediate 先行语义保持）")
		var rem_arr: Array = inst.call("get_remaining_voxels")
		var mvv: Node = inst.get_node_or_null("MainView/ViewportContainer/SubViewport/VoxelView")
		var v0: MeshInstance3D = mvv.call("get_voxel_node", Vector3i(rem_arr[0])) if (mvv != null and rem_arr.size() > 0) else null
		check(v0 != null and v0.visible == true, "N4②：凝聚段起点=体素实体在屏（风险 9：不得沿袭立即逐格 hide）")
		check_eq(int(inst.call("get_success_seg")), 0, "N4①：段钩子=0 凝聚段（get_success_seg）")
		# D-2 覆盖层骨架：透视匹配相机 + 建模挂独立 SpinPivot（坑 9）+ 材质证据链
		var ocam: Camera3D = inst.get_node_or_null("SuccessOverlay/AnimContainer/AnimViewport/AnimWorld/AnimCam") as Camera3D
		var align_d: Dictionary = inst.get("_align")
		var vsz_run: Vector2 = inst.get("_cloud_vsz")
		# 无头 expand 伪象（实证坑）：headless visible rect=1152×1152 方形——以运行时 _cloud_vsz
		# 为基准断言（mount_h/vsz_h 比例恒定 → fov 与分辨率无关；真实窗口口径归窗口走查复核）。
		var fov_exp: float = float(ls_s.call("settle_match_fov", float(align_d.get("fov", 45.0)),
			float(align_d.get("mount_h", 388.8)), vsz_run.y))
		check(ocam != null and ocam.projection == Camera3D.PROJECTION_PERSPECTIVE \
			and absf(ocam.fov - fov_exp) < 0.5,
			"N4④：覆盖层相机=透视且 fov 匹配结算挂载投影（%.3f° vs 期望 %.3f°，同位续接前提；M-Gb 正交口径等价替换留痕）" % [ocam.fov, fov_exp])
		var cloud: Node = inst.get_node_or_null("SuccessOverlay/AnimContainer/AnimViewport/AnimWorld/SpinPivot/SuccessCloud")
		check(cloud is MultiMeshInstance3D and (cloud as MultiMeshInstance3D).visible == false,
			"N4③：SuccessCloud 挂独立 SpinPivot 且聚合段前隐藏（坑 9+防起点剧透）")
		var spin: Node = inst.get_node_or_null("SuccessOverlay/AnimContainer/AnimViewport/AnimWorld/SpinPivot")
		check(spin != null and not _in_subtree(spin, "MainView"),
			"N4④：SpinPivot 独立于 MainView 轨道相机链（坑 9 纪律保持）")
		if cloud is MultiMeshInstance3D:
			var cmm: MultiMesh = (cloud as MultiMeshInstance3D).multimesh
			check(cmm != null and int(cmm.instance_count) > 1000 and cmm.use_colors,
				"N4③：建模=文物点云全量（instance_count %d，use_colors 坑 13 先于 count）" % (int(cmm.instance_count) if cmm != null else 0))
			# O批等价替换（2026-09-10 用户口径①⑦建模圆点化）：M批 StandardMaterial3D
			# （UNSHADED+TRANSPARENCY_ALPHA）→ viewer 同源圆点 ShaderMaterial——
			# unshaded ↔ render_mode unshaded；TRANSPARENCY_ALPHA ↔ blend_mix+逐实例色 α 衰减
			# （失配回退淡出前提保持，风险 12）；圆点=QuadMesh+手动 billboard+圆盘 alpha。
			var cmat: Material = (cloud as MultiMeshInstance3D).material_override
			check(cmat is ShaderMaterial and (cmat as ShaderMaterial).shader != null \
				and String((cmat as ShaderMaterial).shader.code).contains("unshaded") \
				and String((cmat as ShaderMaterial).shader.code).contains("blend_mix") \
				and (cloud as MultiMeshInstance3D).multimesh.mesh is QuadMesh,
				"O批等价替换：材质 unshaded+blend_mix（黑膜修复/失配回退淡出前提保持）+mesh QuadMesh 圆点化")
			var tgts: PackedVector3Array = _p3arr_or_empty(inst.get("_cloud_targets"))
			var fit: float = float(align_d.get("fit", 2.2))
			var all_near := tgts.size() == int(cmm.instance_count)
			for t0: Vector3 in tgts:
				if t0.length() > fit:
					all_near = false
					break
			check(all_near, "N4③：聚合目标收敛于建模本体（settle fit 口径归一，半径 ≤ %.2f 世界单位）" % fit)
		# D-3 推进过凝聚+持续+散开（(0.25+0.5+1.2)/8≈0.244s，P批波2 时长档）→ 聚合段接力
		await create_timer(0.3).timeout
		check_eq(int(inst.call("get_success_seg")), 2, "N4③：段钩子=2 聚合段（散开末帧已接力）")
		var fxl2: Node = inst.get("_fx_layer")
		var fmmi: MultiMeshInstance3D = _find_mmi(fxl2) if fxl2 != null else null
		check(fmmi == null or fmmi.multimesh == null, "N4③：N3 层散点已移交清场（release_particles，风险 10）")
		var cloud2: MultiMeshInstance3D = inst.get_node_or_null("SuccessOverlay/AnimContainer/AnimViewport/AnimWorld/SpinPivot/SuccessCloud") as MultiMeshInstance3D
		check(cloud2 != null and cloud2.visible == true, "N4③：聚合段建模可见（同帧接管=无空窗黑场）")
		var starts: PackedVector3Array = _p3arr_or_empty(inst.get("_cloud_starts"))
		var tgts2: PackedVector3Array = _p3arr_or_empty(inst.get("_cloud_targets"))
		var diff_n := 0
		for i: int in mini(starts.size(), tgts2.size()):
			if not starts[i].is_equal_approx(tgts2[i]):
				diff_n += 1
		check(starts.size() > 0 and (cloud2 == null or starts.size() == int(cloud2.multimesh.instance_count)) \
			and diff_n > mini(starts.size(), tgts2.size()) / 2,
			"N4③：聚合起点=散开末帧逐点接力（starts 与文物点云等长且已改写为散开末帧位 %d/%d，计数以文物点云为准）" % [diff_n, starts.size()])
		var rem_n: int = (inst.call("get_remaining_voxels") as Array).size()
		check_eq(_count_hidden(inst), rem_n, "N4②：凝聚完成后剩余积木块全部隐藏（分组统一隐藏，非逐格随机）")
		var topbar: CanvasItem = inst.get_node_or_null("TopBar")
		check(topbar != null and topbar.modulate.a < 1.0, "N4：消散段 UI modulate.a < 1（UI 淡出保持）")
		# D-4 自然完成 → 回看段位姿数学（P批波2：全程自转，建模保持姿态直入结算）
		await create_timer(0.45).timeout  # 累计 0.75 > 总 3.95/8≈0.494（P批波2 时长档）
		check_eq(int(game.current_state()), ST_SETTLE, "N4⑤：四段动画自然完成 → 结算（mark_settle_entered 记账 SETTLE 态）")
		check_eq(int(save.get_talent()), talent0 + 100, "N4⑤：天赋值照常发放（首通 +100，评级口径零改动）")
		var cleared: Array = (save.get_progress().get("cleared", []) as Array)
		check(cleared.has(1), "N4⑤：SaveManager.advance_progress 照常推进（cleared 含第 1 关）")
		check(topbar != null and absf(topbar.modulate.a) < 0.001, "N4：动画完成 UI modulate.a 降至 0（全 UI 消散保持）")
		# D-5 回看段位姿数学（P批波2等价替换：回看=全程自转窗口 0.9s（对位窗口废止），
		# 建模保持自转/拖拽姿态直入结算不回正——结算 UI 由 level 覆盖层承载）
		inst.call("_begin_review")
		inst.call("_review_progress", 0.375)  # 自转窗口中点（回看全程 0.9s 的 37.5% → +6.75°）
		var spin2: Node3D = inst.get_node_or_null("SuccessOverlay/AnimContainer/AnimViewport/AnimWorld/SpinPivot")
		check(spin2 != null and absf(spin2.rotation.y - deg_to_rad(36.75)) < 0.01,
			"P批波2等价替换：回看自转（yaw=结算 30°+SPIN_SPEED_DEG 20×ANIM_REVIEW 0.9×0.375=36.75°；O批 37.5° 断言随时长重排/对位废止等价替换留痕）")
		inst.call("_review_progress", 1.0)  # 回看终点（P批波2：无对位窗口——姿态保持直入结算）
		var align2: Dictionary = inst.get("_align")
		var kpp: float = float(align2.get("px_per_world", 1.0))
		var center: Vector2 = align2.get("center", Vector2.ZERO)
		var vsz2: Vector2 = inst.get("_cloud_vsz")
		var mount_w := Vector3((center.x - vsz2.x * 0.5) / kpp, (vsz2.y * 0.5 - center.y) / kpp, 0.0)
		check(spin2 != null and spin2.position.distance_to(mount_w) < 0.01,
			"N4④：建模位=结算挂载位（SpinPivot 常驻 CenterMount 中心世界位，O批位置统一保持）")
		check(spin2 != null and absf(spin2.rotation.y - deg_to_rad(48.0)) < 0.01 \
			and absf(spin2.rotation.x - deg_to_rad(float(align2.get("pitch", 22.0)))) < 0.01,
			"P批波2等价替换：回看终点姿态=自转累计（yaw=30°+20°/s×0.9s=48°）不回正——建模保持姿态直入结算（旧「对位终点=结算初始朝向 30/22」断言随架构重做废止留痕）")
		# D-5b 回看拖拽通道（spec §6.6 方案口径 5：专用轻量输入通道；拖拽接管停自转、对位窗口冻结）
		# （本组为通道单元断言：自然完成流程 _settled=true 会短路拖拽守卫——单元解锁后验证，
		#  生产守卫本体零改动；真实拖拽观感归窗口走查）
		inst.set("_settled", false)
		var ospeed: float = float(lcmap.get("ORBIT_SPEED", 0.005))
		inst.call("_begin_review")
		var mb_d := InputEventMouseButton.new()
		mb_d.button_index = MOUSE_BUTTON_LEFT
		mb_d.pressed = true
		inst.call("_review_unhandled_input", mb_d)
		var mm_d := InputEventMouseMotion.new()
		mm_d.relative = Vector2(60, -20)
		inst.call("_review_unhandled_input", mm_d)
		var yaw_d: float = inst.get("_rev_yaw")
		check(bool(inst.get("_rev_dragging")) and not bool(inst.get("_rev_auto")) \
			and absf(yaw_d - (deg_to_rad(30.0) + 60.0 * ospeed)) < 0.01,
			"N4④：回看拖拽按下+移动 → 拖拽态+接管停自转（yaw=30°+60px×ORBIT_SPEED 作用于 SpinPivot）")
		inst.call("_review_progress", 0.2)
		check(absf(float(inst.get("_rev_yaw")) - yaw_d) < 1e-9,
			"N4④：接管后自动自转停（_review_progress 不再推进 yaw，无操作才自转缺省）")
		var mb_u := InputEventMouseButton.new()
		mb_u.button_index = MOUSE_BUTTON_LEFT
		mb_u.pressed = false
		inst.call("_review_unhandled_input", mb_u)
		check_eq(bool(inst.get("_rev_dragging")), false, "N4④：拖拽抬起 → 拖拽态结束")
		inst.call("_review_progress", 1.0)  # 回看终点（P批波2：全程可拖拽，无对位冻结窗口）
		var yaw_a: float = inst.get("_rev_yaw")
		var mb_d3 := InputEventMouseButton.new()
		mb_d3.button_index = MOUSE_BUTTON_LEFT
		mb_d3.pressed = true
		inst.call("_review_unhandled_input", mb_d3)  # 重新按住（前组抬起已复位拖拽态）
		var mm_d2 := InputEventMouseMotion.new()
		mm_d2.relative = Vector2(100, 0)
		inst.call("_review_unhandled_input", mm_d2)
		check(absf(float(inst.get("_rev_yaw")) - (yaw_a + 100.0 * ospeed)) < 1e-6,
			"P批波2等价替换：回看段全程可拖拽（旧「对位窗口冻结拖拽」断言随对位废止删除——拖拽接管停自转语义保持）")
		# D-6 P批波2等价替换：失配回退路径（风险 12）随对位机制废止删除——对位参数收敛为
		# 单一真相源常量表后无失配态，_align_fading/_align_started 运行态已从场景脚本移除，
		# 建模恒成形直入结算（软衔接由覆盖层承载不存在硬切）。
		check(inst.get("_align_fading") == null and inst.get("_align_started") == null,
			"P批波2等价替换：失配回退/对位运行态已删（_align_fading/_align_started 不存在——对位废止，建模保持玩家姿态直入结算）")
		inst.queue_free()

		# ==================== E. skip 钩子行为不回归（spec 8.4 不可跳过语义的测试直驱路径保持）====================
		_reset_save()
		var talent1: int = int(save.get_talent())
		var inst3: Node = await _make_level(1)
		var jb3: Button = inst3.get_node_or_null("TopBar/Buttons/JoinButton")
		if jb3 != null:
			inst3.set("anim_time_scale", 8.0)
			inst3.call("set_remaining_for_test", target)
			jb3.pressed.emit()
			inst3.call("_skip_success_animation")  # 同帧打断（覆盖层/通道/tween 已建）
			await process_frame
			check_eq(int(game.current_state()), ST_SETTLE, "N4⑤：skip 钩子仍直达结算（P批波2 mark_settle_entered 记账 SETTLE 态）")
			check_eq(int(save.get_talent()), talent1 + 100, "N4⑤：skip 路径天赋值照常发放（首通 +100）")
			var topbar3: CanvasItem = inst3.get_node_or_null("TopBar")
			# P批波2等价替换：skip=直达结算 UI——游玩 UI 保持消散态（结算由覆盖层承载），旧
			# 「modulate 复原 WHITE+释放覆盖层」随场景切换路径废止。
			check(topbar3 != null and absf(topbar3.modulate.a) < 0.001,
				"N4⑤ P批波2等价替换：skip 后游玩 UI 保持消散态（无残留淡出中间态，结算 UI 接管）")
			var settle_ui3: Control = inst3.get_node_or_null("SuccessOverlay/SettleUI")
			check(settle_ui3 != null and settle_ui3.visible,
				"P批波2⑦：skip=直达结算 UI（跳过动画不跳过结算，覆盖层 SettleUI 显现）")
			var fxl3: Node = inst3.get("_fx_layer")
			check(fxl3 == null or int(fxl3.call("get_phase")) == 0, "N4⑤：skip 后 N3 层清场复位 IDLE（无残留散点）")
		inst3.queue_free()

	# ==================== F. 评级/天赋值常量守护（禁止触碰区复核）====================
	check_eq(float(lcmap.get("GRADE_TIME_PERFECT", -1.0)), 180.0, "N4⑤：GRADE_TIME_PERFECT=180 守护（禁止触碰区）")
	check_eq(float(lcmap.get("GRADE_TIME_GOOD", -1.0)), 360.0, "N4⑤：GRADE_TIME_GOOD=360 守护（禁止触碰区）")
	var cpt: Variant = lcmap.get("CHAPTER_PERFECT_TALENT")
	check(cpt is Array and (cpt as Array) == [100, 200, 400, 800, 1600],
		"N4⑤：CHAPTER_PERFECT_TALENT 守护（禁止触碰区）")

	Engine.max_fps = 0
	_cleanup_files()
	finish()
