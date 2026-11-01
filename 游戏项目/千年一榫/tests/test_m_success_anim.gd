extends "res://tests/test_base.gd"
## M-Gb（批次 M / spec §3.7 目标行为 1~5）：成功动画三段式重做 + 点云聚散收回/裁切/黑膜修复。
## 追3 涟漪（§3.7 第 6 条）已由 M-Ga（test_m_ripple.gd）承接，本文件不含。
## 契约（spec §3.7 + 用户原话「UI 全消散成点→四面八方聚成金光建模→可回看旋转」）：
##   ①黑膜修复：覆盖层 SuccessCloud 材质 UNSHADED + vertex_color_use_as_albedo（use_color 时）
##     + 金黄 tint（CLOUD_TINT=#F5C542、CLOUD_TINT_STRENGTH=0.85，对齐 point_cloud_viewer 口径）；
##     use_colors 先于 instance_count（坑 13）。
##   ②聚散收回：FocusFX 相位机——M批 PHASE_IDLE/SPREAD/RETURN + RETURN_TIME=0.4 口径已随
##     N3 全屏三色重写废止，A 段按 N3 新状态机等价替换留痕（IDLE/CONDENSE/SPREAD/STEADY/RETURN、
##     RETURN_TIME=0.6、deactivate 幂等、RETURN 期 activate 打断重激活、
##     deactivate_immediate 成功动画入口立即复位幂等均语义保留）。
##   ③发散裁切：M批 _spread_scale/EDGE_FADE_FRAC 单视图口径随重写废止（A 段等价替换为
##     N3 compute_camera_distance 透视基准 + ShaderMaterial 证据链）。
##   ④三段式→N4 四段式（N批等价替换留痕，spec §3.7 行为 4 → §6.6）：M-Gb 三段常量
##     ANIM_DISSOLVE=0.9/ANIM_AGGREGATE=1.5/ANIM_SPIN=1.2 废止，改四段 ANIM_CONDENSE=0.3/
##     ANIM_HOLD=0.15/ANIM_SPREAD=0.55/ANIM_AGGREGATE=1.5/ANIM_REVIEW=1.2（和∈[2.5,4]）+
##     SPIN_SPEED_DEG=20；覆盖层 _begin_success 立即建立；UI modulate 淡出至 0（skip 复原）；
##     积木块隐藏改由 N3 管线凝聚完成统一接管（非逐体素随机序）；聚合目标=settle fit 口径
##     建模本体；覆盖层相机改透视+结算投影匹配（N4 同位续接）；SpinPivot 独立节点（坑 9）。
##   ⑤_skip_success_animation 行为不回归（SETTLE 路由/发奖口径）。
## 坑纪律（spec §六 6/9/13）：MultiMesh 无头读回恒 0 → 全部属性证据链
## （instance_count/材质标志/自持 Packed 数组）；相机 tween 纪律；use_colors 先于 instance_count。

const FX_SCRIPT := "res://scripts/focus_fx.gd"
const VOX_SCRIPT := "res://scripts/level_voxel_view.gd"
const LS_SCRIPT := "res://scenes/level/level_scene.gd"
const LEVEL_SCENE := "res://scenes/level/level_scene.tscn"
const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const ST_SETTLE := 5

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
	return inst

## MainView 剩余体素中已隐藏的个数（逐体素隐藏进度证据）。
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
const DISC_BK_PREFIX := "user://_r2b_msa_backup_"
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
	print("EVID|user_restore|msa|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_m_success_anim ==")
	_backup_user()
	Engine.max_fps = 60  # 有头外无上限帧率会让逐帧动画 tween 空转，测试限 60fps
	game = get_root().get_node("Game")
	save = get_root().get_node("SaveManager")
	lib = get_root().get_node("LevelLibrary")
	lib.scan_directory("res://levels_data")

	var fx_s: Script = load(FX_SCRIPT) as Script
	var ls_s: Script = load(LS_SCRIPT) as Script
	check(fx_s != null and ls_s != null, "M-Gb 前置：focus_fx.gd / level_scene.gd 可加载")
	if fx_s == null or ls_s == null:
		finish()
		return

	# ==================== A. FocusFX 全屏三色状态机（N批等价替换：spec §3.7→§6.4/§五 4~7）====================
	# N批等价替换总注：M-Gb 单视图 CPU 金点口径（PHASE 三相/RETURN_TIME=0.4/EDGE_FADE_FRAC/
	# SPREAD_MARGIN/compute_spread_scale/SPREAD_MIN/SPREAD_MAX）随全屏三色重写废止；
	# 本段按 N3 新契约（凝聚→散开→稳态→完整倒放 + GPU uniform 驱动）等价重写并留痕。
	var cmap: Dictionary = fx_s.get_script_constant_map()
	check_eq(int(cmap.get("PHASE_IDLE", -1)), 0, "M-Gb②→N3：PHASE_IDLE=0（等价替换留痕）")
	check_eq(int(cmap.get("PHASE_CONDENSE", -1)), 1, "N3：PHASE_CONDENSE=1（凝聚=实体→点云面，N批新增）")
	check_eq(int(cmap.get("PHASE_SPREAD", -1)), 2, "M-Gb②→N3：PHASE_SPREAD=2（散开，等价替换留痕）")
	check_eq(int(cmap.get("PHASE_STEADY", -1)), 3, "N3：PHASE_STEADY=3（稳态闪烁/漂移，N批新增）")
	check_eq(int(cmap.get("PHASE_RETURN", -1)), 4, "M-Gb②→N3：PHASE_RETURN=4（收回=完整倒放）")
	check_eq(float(cmap.get("RETURN_TIME", -1.0)), 0.6,
		"M-Gb②→N3：RETURN_TIME=0.4→0.6 等价替换留痕（完整倒放=收拢0.4+还原0.2）")
	check_eq(float(cmap.get("CONDENSE_TIME", -1.0)), 0.25, "N3：CONDENSE_TIME=0.25（spec §6.4 暂定）")
	check_eq(float(cmap.get("SPREAD_TIME", -1.0)), 1.2,
		"P批波2等价替换（2026-09-10 用户口径 P-C 散开放慢+滞空）：SPREAD_TIME=1.2（聚焦散开；N3 0.9 档废止留痕）")
	check_eq(int(cmap.get("LAYER", -1)), 0,
		"M-Gb③→N3：全屏层 LAYER=0（EDGE_FADE_FRAC/SPREAD_MARGIN 单视图口径随重写废止；层号 spec 暂定 85→走查定稿 0，N批等价替换留痕）")

	# 组装小视口世界（正交 cam.size=6 → 凝聚面半边长=size.y/cam.size 比例换算，透视全屏层独立）
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
	check_eq(int(fx.call("get_phase")), int(cmap.get("PHASE_IDLE", -1)), "M-Gb②：初始 get_phase()==IDLE")
	check_eq(bool(fx.call("activate", [Vector3i(0, 0, 0), Vector3i(1, 0, 0)], built)), true,
		"M-Gb②：activate（legacy API=主通道）成功（selected 非空）")
	check_eq(int(fx.call("get_phase")), int(cmap.get("PHASE_CONDENSE", -1)),
		"N3：激活后 get_phase()==CONDENSE（先凝聚，M批直入 SPREAD 等价替换留痕）")
	check_eq(bool(fx.call("is_active")), true, "M-Gb②：凝聚期 is_active()==true")
	check_eq(bool(fx.call("activate", [Vector3i(0, 0, 0)], built)), false,
		"M-Gb②：活跃期重复 activate 返回 false（幂等）")
	var n_unsel: MeshInstance3D = vv.call("get_voxel_node", Vector3i(2, 0, 0))
	check(n_unsel != null and n_unsel.visible == true,
		"N3：凝聚期未选中体素仍可见（实体→点云面过渡，M批「激活即隐藏」等价替换留痕）")
	# O批等价替换（2026-09-10 用户口径③凝聚持续 0.5s）：凝聚完成后先进 HOLD 再入 SPREAD
	await create_timer(0.35).timeout  # > CONDENSE_TIME 0.25，< 0.25+FOCUS_HOLD 0.5
	check_eq(int(fx.call("get_phase")), int(cmap.get("PHASE_HOLD", -1)),
		"O批等价替换：凝聚完成 → HOLD 持续段（点云面稳态 0.5s；原直入 SPREAD 断言废止）")
	check(n_unsel != null and n_unsel.visible == false,
		"N3：凝聚完成体素隐藏（点云面接管=无空窗跳变，spec §6.4）")
	await create_timer(0.55).timeout  # 累计 0.9 > 0.25+0.5
	check_eq(int(fx.call("get_phase")), int(cmap.get("PHASE_SPREAD", -1)),
		"N3：持续完成 → SPREAD 相位（散开目标=屏外，O批③留痕）")
	# N3 等价替换：M批 compute_spread_scale（单视图正交钳制）废止 → 透视相机距离纯函数
	# （焦点平面可见高=view_h → dist=(h/2)/tan(fov/2)，648/45°≈782.27）
	var dist_pure: float = float(fx_s.call("compute_camera_distance", 648.0, 45.0))
	check(absf(dist_pure - 782.27) < 0.5,
		"M-Gb③→N3：compute_camera_distance 透视基准≈782.27（等价替换 compute_spread_scale，实际 %.2f）" % dist_pure)
	check(float(fx_s.call("compute_camera_distance", 0.0, 45.0)) > 0.0,
		"M-Gb③→N3：度量无效防御回退>0（等价替换 compute_spread_scale 回退=1 口径）")
	# N3 材质证据链：ShaderMaterial（GPU/uniform 驱动）+ use_colors/use_custom_data（M批 TRANSPARENCY_ALPHA 口径废止）
	var mmi: MultiMeshInstance3D = _find_mmi(fx)
	check(mmi != null, "M-Gb②：激活后子树含 MultiMeshInstance3D")
	if mmi != null:
		check(mmi.multimesh != null and mmi.multimesh.use_colors and mmi.multimesh.use_custom_data,
			"N3④：use_colors+use_custom_data=true（三色逐实例+GPU 散开通道，坑 13 先于 instance_count）")
		var smat: Material = mmi.material_override
		check(smat is ShaderMaterial and (smat as ShaderMaterial).shader != null \
			and (smat as ShaderMaterial).shader.code.contains("u_spread") \
			and (smat as ShaderMaterial).shader.code.contains("INSTANCE_CUSTOM"),
			"N3④：ShaderMaterial uniform 驱动（禁逐帧 CPU 重建点阵红线；M批 TRANSPARENCY_ALPHA 断言等价替换）")
	# N3：通道自持数组证据链（M批 _cur_pos 等价替换——位置混合移入 GPU，自持 face/target 屏幕位）
	var fx_chs: Dictionary = fx.get("_channels")
	var face_m: PackedVector2Array = fx_chs.get("Main", {}).get("face", PackedVector2Array())
	check(face_m.size() == 7 * 2,
		"O批等价替换：通道 face 自持数组与点数等长 14（7 点/格；原 44=22点档废止；M批 _cur_pos 等价替换留痕）")
	# ② deactivate → RETURN 完整倒放：倒放完成前体素不可见
	fx.call("deactivate")
	check_eq(int(fx.call("get_phase")), int(cmap.get("PHASE_RETURN", -1)), "M-Gb②：deactivate 后 get_phase()==RETURN")
	check_eq(bool(fx.call("is_active")), false, "M-Gb②：RETURN 期 is_active()==false（对外已失活）")
	check(n_unsel != null and n_unsel.visible == false,
		"M-Gb②：倒放完成前体素 visible==false（spec 验收 1）")
	fx.call("deactivate")
	check_eq(int(fx.call("get_phase")), int(cmap.get("PHASE_RETURN", -1)),
		"M-Gb②：RETURN 期重复 deactivate 幂等（相位不变）")
	# ② RETURN 期 activate=打断快进收尾后重新激活（selected 同首次 2 格 → 44 点）
	check_eq(bool(fx.call("activate", [Vector3i(0, 0, 0), Vector3i(1, 0, 0)], built)), true,
		"M-Gb②：RETURN 期 activate 打断收回并重新激活（返回 true）")
	check_eq(int(fx.call("get_phase")), int(cmap.get("PHASE_CONDENSE", -1)), "N3：打断后回到 CONDENSE 相位")
	fx.call("deactivate")
	# ② 推进 > RETURN_TIME 0.6：倒放完成 → IDLE + 体素恢复 + MultiMesh 清空
	await create_timer(0.75).timeout
	check_eq(int(fx.call("get_phase")), int(cmap.get("PHASE_IDLE", -1)), "M-Gb②：倒放完成 get_phase()==IDLE")
	check(n_unsel != null and n_unsel.visible == true,
		"M-Gb②：倒放完成后体素 visible==true（完整倒放=实体还原，spec 验收 1）")
	var mmi2: MultiMeshInstance3D = _find_mmi(fx)
	check(mmi2 == null or mmi2.multimesh == null, "M-Gb②：倒放完成后 MultiMesh 清空（无残留点阵）")
	# ② 完成后再激活成功（状态机闭环）
	check_eq(bool(fx.call("activate", [Vector3i(0, 0, 0)], built)), true, "M-Gb②：倒放完成后再激活成功")
	fx.call("deactivate_immediate")
	check_eq(int(fx.call("get_phase")), int(cmap.get("PHASE_IDLE", -1)),
		"M-Gb②：deactivate_immediate 立即复位 IDLE（成功动画入口专用）")
	fx.call("deactivate_immediate")  # 已 IDLE，重复调用幂等
	check_eq(int(fx.call("get_phase")), int(cmap.get("PHASE_IDLE", -1)),
		"M-Gb②：deactivate_immediate 幂等不崩（相位保持 IDLE）")
	world.queue_free()

	# ==================== B. 四段式常量与覆盖层证据链（M-Gb④ → N批等价替换：spec §3.7→§6.6）====================
	var lcmap: Dictionary = ls_s.get_script_constant_map()
	var a_c: float = float(lcmap.get("ANIM_CONDENSE", -1.0))
	var a_h: float = float(lcmap.get("ANIM_HOLD", -1.0))
	var a_sp2: float = float(lcmap.get("ANIM_SPREAD", -1.0))
	var a_a: float = float(lcmap.get("ANIM_AGGREGATE", -1.0))
	var a_r: float = float(lcmap.get("ANIM_REVIEW", -1.0))
	check_eq(a_c, 0.25, "O批等价替换（2026-09-10 用户口径③凝聚持续 0.5s 后平衡）：ANIM_CONDENSE=0.25（N批 0.3 废止留痕）")
	check_eq(a_h, 0.5, "O批：ANIM_HOLD=0.5（凝聚点云面稳态持续 0.5s=FOCUS_HOLD_TIME；N批 0.15 废止留痕）")
	check_eq(a_sp2, 1.2, "P批波2等价替换（2026-09-10 用户口径 P-C 散开放慢+滞空）：ANIM_SPREAD=1.2（散开=屏外环域+滞空缓动；O批 0.5 废止留痕）")
	check_eq(a_a, 1.1, "P批波2等价替换：ANIM_AGGREGATE=1.1（聚合=挂载位；O批 1.3 随总时长重排废止留痕）")
	check_eq(a_r, 0.9, "P批波2等价替换：ANIM_REVIEW=0.9（回看全程自转直入结算；O批 1.0+ANIM_ALIGN 对位废止留痕）")
	check(a_c + a_h + a_sp2 + a_a + a_r >= 2.5 and a_c + a_h + a_sp2 + a_a + a_r <= 4.0,
		"M-Gb④→N4：四段时长和 %.2f ∈ [2.5,4.0]s（spec 8.4 硬约束）" % (a_c + a_h + a_sp2 + a_a + a_r))
	check_eq(float(lcmap.get("SPIN_SPEED_DEG", -1.0)), 20.0, "M-Gb④→N4：SPIN_SPEED_DEG=20（回看自转，spec 暂定）")
	var tint_v: Variant = lcmap.get("CLOUD_TINT")
	check(tint_v is Color and (tint_v as Color) == Color(0.96, 0.77, 0.26),
		"M-Gb①：CLOUD_TINT=#F5C542（金黄，对齐 point_cloud_viewer）")
	check_eq(float(lcmap.get("CLOUD_TINT_STRENGTH", -1.0)), 0.85,
		"M-Gb①：CLOUD_TINT_STRENGTH=0.85（tint 强度，spec 暂定）")

	_reset_save()
	var inst: Node = await _make_level(1)
	var target: Array = _target_cells()
	var jb: Button = inst.get_node_or_null("TopBar/Buttons/JoinButton")
	check(jb is Button and not target.is_empty(), "M-Gb④ 前置：JoinButton 与 target 就绪")
	if jb != null and not target.is_empty():
		inst.set("anim_time_scale", 8.0)
		inst.call("set_remaining_for_test", target)
		jb.pressed.emit()  # → _begin_success：覆盖层立即建立（M-Gb 行为变化：原缩小段后建）
		var overlay: Node = inst.get_node_or_null("SuccessOverlay")
		check(overlay != null, "M-Gb④：覆盖层 _begin_success 立即存在（消散段撒点即需全屏层）")
		var cloud: Node = inst.get_node_or_null("SuccessOverlay/AnimContainer/AnimViewport/AnimWorld/SpinPivot/SuccessCloud")
		check(cloud is MultiMeshInstance3D, "M-Gb④：SuccessCloud 挂独立 SpinPivot 下（坑 9）")
		if cloud is MultiMeshInstance3D:
			var cmm: MultiMesh = (cloud as MultiMeshInstance3D).multimesh
			check(cmm != null and int(cmm.instance_count) > 1000,
				"M-Gb①：instance_count==点云点数（真实数据，%d）" % (int(cmm.instance_count) if cmm != null else 0))
			check(cmm != null and cmm.use_colors, "M-Gb①：use_colors==true（与 instance_count 同帧成立=先于设置，坑 13）")
			# O批等价替换（2026-09-10 用户口径①⑦建模圆点化）：M批 StandardMaterial3D 断言
			# （UNSHADED+vertex_color）→ viewer 同源圆点 ShaderMaterial（unshaded+COLOR 透传）。
			var cmat: Material = (cloud as MultiMeshInstance3D).material_override
			check(cmat is ShaderMaterial and (cmat as ShaderMaterial).shader != null \
				and String((cmat as ShaderMaterial).shader.code).contains("unshaded") \
				and String((cmat as ShaderMaterial).shader.code).contains("COLOR"),
				"M-Gb① O批等价替换：覆盖层材质 unshaded+COLOR 透传（黑膜修复口径不回退；圆点 ShaderMaterial 载体）")
		# 坑 9：SpinPivot 不与轨道相机共节点（父链不含 MainView）
		var spin: Node = inst.get_node_or_null("SuccessOverlay/AnimContainer/AnimViewport/AnimWorld/SpinPivot")
		check(spin != null and not _in_subtree(spin, "MainView"),
			"M-Gb④：SpinPivot 独立于 MainView 轨道相机链（建模自转不与相机打架）")
		# 覆盖层透视相机（N批等价替换：M-Gb「正交相机」→ N4 结算投影匹配透视，同位续接前提）
		var ocam: Camera3D = inst.get_node_or_null("SuccessOverlay/AnimContainer/AnimViewport/AnimWorld/AnimCam") as Camera3D
		var align_m: Dictionary = inst.get("_align")
		var vsz_m: Vector2 = inst.get("_cloud_vsz")
		var fov_exp_m: float = float(ls_s.call("settle_match_fov", float(align_m.get("fov", 45.0)),
			float(align_m.get("mount_h", 388.8)), vsz_m.y))
		check(ocam != null and ocam.projection == Camera3D.PROJECTION_PERSPECTIVE \
			and absf(ocam.fov - fov_exp_m) < 0.5,
			"M-Gb④→N4：覆盖层相机=透视+结算投影匹配（%.3f°，旧正交口径等价替换；无头伪象以运行时 vsz 为基准）" % (ocam.fov if ocam != null else -1.0))
		# 聚合目标=建模本体（N批等价替换：M-Gb「边缘环起点」口径废止——N4 起点为散开末帧接力，
		# 断言改为目标收敛性；接力起点行为断言在 test_n4_success_flow.gd）
		var starts_m: PackedVector3Array = _p3arr_or_empty(inst.get("_cloud_starts"))
		var targets_m: PackedVector3Array = _p3arr_or_empty(inst.get("_cloud_targets"))
		var fit_m: float = float(align_m.get("fit", 2.2))
		var all_near_m := targets_m.size() == starts_m.size()
		for t0: Vector3 in targets_m:
			if t0.length() > fit_m:
				all_near_m = false
				break
		check(all_near_m, "M-Gb④→N4：聚合目标全部收敛于建模本体（settle fit 口径归一，半径 ≤ %.2f 世界单位）" % fit_m)
		# 凝聚/散开撒点由 N3 全屏三色管线承载（N批等价替换：M-Gb DissolveDots 消散撒点废止；
		# 三通道同帧激活=分组统一凝聚，Target/Join 木块同样粒子化）
		var fxl_m: Node = inst.get("_fx_layer")
		check(fxl_m != null and bool(fxl_m.call("is_channel_active", "Main")) \
			and bool(fxl_m.call("is_channel_active", "Target")) and bool(fxl_m.call("is_channel_active", "Join")),
			"M-Gb④→N4：凝聚/散开由 N3 三通道承载（全屏三色；旧 DissolveDots 撒点 MultiMesh 等价替换）")
		# ①凝聚段：UI 淡出启动、体素凝聚完成才统一隐藏（N批等价替换：M-Gb「逐体素随机序中途
		# >0」→ N4「凝聚段体素在屏（同帧断言，time_scale 8 下逐帧断言有竞态）、凝聚完成统一隐藏」，
		# 风险 9；同帧口径与 test_n4_success_flow D-1 一致）
		var hid_pre := _count_hidden(inst)
		check_eq(hid_pre, 0, "M-Gb④→N4：凝聚起点（同帧）积木块仍在屏（实体→点云面过渡，非逐格隐藏）")
		await process_frame
		var topbar: CanvasItem = inst.get_node_or_null("TopBar")
		check(topbar != null and topbar.modulate.a < 1.0, "M-Gb④→N4：凝聚段 TopBar modulate.a < 1（UI 淡出已启动）")
		# 自然完成：四段总时长 (0.25+0.5+1.2+1.1+0.9)/8≈0.494s（P批波2 时长档：散开放慢+滞空）
		await create_timer(0.7).timeout
		check_eq(int(game.current_state()), ST_SETTLE, "M-Gb④：四段动画自然完成 → 路由 SETTLE")
		check(topbar != null and absf(topbar.modulate.a) < 0.001,
			"M-Gb④：动画完成 UI modulate.a 降至 0（全 UI 消散）")
		# ④回看自转行为断言（P批波2等价替换：回看=全程自转窗口 0.9s（对位窗口废止），_review_progress(0.375)
		# → 30°+20°×0.9×0.375=36.75°；O批 37.5° 断言随 ANIM_REVIEW 0.9/对位废止等价替换留痕；坑 9：独立 SpinPivot）
		var spin_n: Node3D = inst.get_node_or_null("SuccessOverlay/AnimContainer/AnimViewport/AnimWorld/SpinPivot")
		inst.call("_begin_review")
		inst.call("_review_progress", 0.375)
		check(spin_n != null and absf(spin_n.rotation.y - deg_to_rad(36.75)) < 0.01,
			"M-Gb④→N4 P批波2等价替换：_review_progress(0.375) → SpinPivot.rotation.y≈36.75°（结算 30°基准+自转 20°/s×0.9s×0.375）")
		var remaining_n: int = (inst.call("get_remaining_voxels") as Array).size()
		check_eq(_count_hidden(inst), remaining_n,
			"M-Gb④：动画完成剩余积木块全部隐藏（消散彻底 %d/%d）" % [remaining_n, remaining_n])
		inst.queue_free()

	# ==================== C. skip 钩子行为不回归（spec §3.7 验收 2）====================
	_reset_save()
	var talent0: int = int(save.get_talent())
	var inst3: Node = await _make_level(1)
	var jb3: Button = inst3.get_node_or_null("TopBar/Buttons/JoinButton")
	if jb3 != null and not target.is_empty():
		inst3.set("anim_time_scale", 8.0)
		inst3.call("set_remaining_for_test", target)
		jb3.pressed.emit()
		inst3.call("_skip_success_animation")  # 同帧打断（覆盖层/modulate tween 已建）
		await process_frame
		check_eq(int(game.current_state()), ST_SETTLE, "M-Gb⑤：skip 钩子仍直达结算（P批波2 记账 SETTLE 态）")
		check_eq(int(save.get_talent()), talent0 + 100, "M-Gb⑤：skip 路径天赋值照常发放（首通 +100）")
		var topbar3: CanvasItem = inst3.get_node_or_null("TopBar")
		# P批波2等价替换：skip=直达结算 UI——游玩 UI 保持隐藏（结算由覆盖层承载），旧
		# 「modulate 复原 WHITE+释放覆盖层+切 settle 场景」随架构重做废止。
		check(topbar3 != null and absf(topbar3.modulate.a) < 0.001,
			"M-Gb⑤ P批波2等价替换：skip 后游玩 UI 保持消散态（结算 UI 接管显示）")
		check(inst3.get_node_or_null("SuccessOverlay/SettleUI") != null
			and (inst3.get_node_or_null("SuccessOverlay/SettleUI") as Control).visible,
			"P批波2：skip 直达结算 UI（SuccessOverlay/SettleUI 显现）")
	inst3.queue_free()

	Engine.max_fps = 0
	_cleanup_files()
	finish()

## 递归查找子树中的 MultiMeshInstance3D（同 test_focus_fx 口径，不约定节点名）。
func _find_mmi(node: Node) -> MultiMeshInstance3D:
	for c: Node in node.get_children():
		if c is MultiMeshInstance3D:
			return c as MultiMeshInstance3D
		var found: MultiMeshInstance3D = _find_mmi(c)
		if found != null:
			return found
	return null

## node 的祖先链中是否出现名为 sub_root_name 的节点（坑 9 断言：SpinPivot 不得在 MainView 链）。
func _in_subtree(node: Node, sub_root_name: String) -> bool:
	var cur: Node = node
	while cur != null:
		if cur.name == sub_root_name:
			return true
		cur = cur.get_parent()
	return false

## Variant → PackedVector3Array（null/类型不符防御为空数组；--script 模式属性缺失时不挂死）。
func _p3arr_or_empty(v: Variant) -> PackedVector3Array:
	return v if v is PackedVector3Array else PackedVector3Array()
