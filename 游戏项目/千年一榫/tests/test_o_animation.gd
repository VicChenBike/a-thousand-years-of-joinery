extends "res://tests/test_base.gd"
## 批次 O-P2（O3）聚焦/成功动画全面精修——判定用例（TDD 红灯先行；2026-09-10 用户反馈截图×2
## 证据：AI工作记录/反馈截图_20260910/聚散方形粗点遮屏.png、图鉴红圈渐变_黄涂金点团.png）。
## 契约（用户口径 2026-09-10「批次 O-P2 聚焦/成功动画全面精修」）：
##   ①散点圆点化+细腻化：focus_fx 点 mesh 非 BoxMesh（QuadMesh+fragment 圆盘 alpha，边缘软过渡；
##     备选 SphereMesh 因高段数×数千点在 gl_compatibility 有压力被性能红线否决）；点径档
##     DOT_SIZE=2.8px（×缩放 0.9~1.25 → 2.5~3.5px 细腻带，7px 方块档废止）；密度
##     DOTS_PER_VOXEL ∈[6,8]（定 7，22 档废止）。
##   ②凝聚持续 0.5s：FOCUS_HOLD_TIME=0.5（聚焦路径默认，n4_hold_time≤0 时回退生效）与
##     ANIM_HOLD=0.5（成功路径覆盖值）两处口径一致；HOLD 期散开进度=0（回放倒放语义不变）。
##   ③散开目标=屏外：spread_target_screen 全部落设计视口外（散开观感=向外逃出屏幕，屏内不再
##     遮屏）；确定性保留；四象限（离心向）覆盖；角向密度>边向密度（离角偏置语义屏外等价保留）。
##   ④成功动画全金：activate_channel 增色彩覆写参数——override_color.a>0 时覆写通道色（成功
##     动画三通道凝聚/散开全程金黄，用户「无论左上右上中间全都金黄色」）；缺省 alpha=0 不覆写
##     =聚焦三色（金/绿/红，用户「聚焦的时候区分左上角和右上角的颜色」）语义不变。
##   ⑤建模位置统一：聚合段目标位=结算建模挂载位——_review_center==_mount_world（覆盖层构建时
##     定格，原「聚合在屏幕中心、结算在挂载位」双位跳变废止）；relay 接力起点=屏外散点位
##     （pivot-local 换算：起点=散点屏幕位−SpinPivot 平移）。
##   ⑥悬停交互移除：viewer 源码无 RIPPLE/u_ripple/_ripple 符号（grep 级断言）；
##     rotate_by/zoom_by 保留（Q&A 13 玩家可旋转既有确认需求）。
##   ⑦点云圆点+尺寸调档：viewer mesh QuadMesh+手动 billboard+圆盘 alpha；DOT_SIZE_MIN∈[0.010,
##     0.015] 下限档生效（point_size=0.005 亚像素噪点旧档废止→0.012；高于下限的实例档不受限）
##     ——图鉴/结算/成功动画聚合三处同源生效（catalog/settle 0.005 实设经 build 下限同源上调）。
## 坑纪律（spec 铁律 5）：无头 MultiMesh 色/transform 读回恒 0 → 属性证据链
##   （instance_count/材质标志/自持数组/_mm_colors 生成侧）；--script class_name 时序 →
##   load()+call()（P2-5）；观感终判=窗口截图走查（walkthrough_20260910O/o2）。

const FX_SCRIPT := "res://scripts/focus_fx.gd"
const VOX_SCRIPT := "res://scripts/level_voxel_view.gd"
const VS_SCRIPT := "res://scripts/point_cloud_viewer.gd"
const LS_SCRIPT := "res://scenes/level/level_scene.gd"
const LEVEL_SCENE := "res://scenes/level/level_scene.tscn"
const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const ST_SETTLE := 5
const GOLD := Color(0.96, 0.77, 0.26)  # 全金口径（=FocusFX.GOLD=level CLOUD_TINT=#F5C542）

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
	check(not lvl.is_empty(), "O 前置：第 1 关关卡数据已扫描（levels_data）")
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

func _find_mmi(node: Node) -> MultiMeshInstance3D:
	for c: Node in node.get_children():
		if c is MultiMeshInstance3D:
			return c as MultiMeshInstance3D
		var found: MultiMeshInstance3D = _find_mmi(c)
		if found != null:
			return found
	return null

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
const DISC_BK_PREFIX := "user://_r2b_oan_backup_"
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
	print("EVID|user_restore|oan|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_o_animation ==")
	_backup_user()
	Engine.max_fps = 60
	game = get_root().get_node("Game")
	save = get_root().get_node("SaveManager")
	lib = get_root().get_node("LevelLibrary")
	lib.scan_directory("res://levels_data")

	var fx_s: Script = load(FX_SCRIPT) as Script
	var vox_s: Script = load(VOX_SCRIPT) as Script
	var vs_s: Script = load(VS_SCRIPT) as Script
	var ls_s: Script = load(LS_SCRIPT) as Script
	check(fx_s != null and vox_s != null and vs_s != null and ls_s != null,
		"O 前置：focus_fx/level_voxel_view/point_cloud_viewer/level_scene 可加载")
	if fx_s == null or vox_s == null or vs_s == null or ls_s == null:
		finish()
		return
	var fcmap: Dictionary = fx_s.get_script_constant_map()
	var lcmap: Dictionary = ls_s.get_script_constant_map()
	var vcmap: Dictionary = vs_s.get_script_constant_map()

	# ==================== A. 常量档：点径/密度/持续 0.5s/时长分配 ====================
	check_eq(int(fcmap.get("DOTS_PER_VOXEL", -1)), 7,
		"O①：DOTS_PER_VOXEL=7（∈[6,8] 细腻档；22 遮屏档废止，O批等价替换留痕）")
	var dsz: float = float(fcmap.get("DOT_SIZE", -1.0))
	check(dsz >= 2.5 and dsz <= 3.5,
		"O①：DOT_SIZE=%.1f ∈[2.5,3.5]px 细腻圆点基准（7px 方块档废止）" % dsz)
	var smin: float = float(fcmap.get("DOT_SCALE_MIN", -1.0))
	var smax: float = float(fcmap.get("DOT_SCALE_MAX", -1.0))
	check(dsz * smin >= 2.2 and dsz * smax <= 3.6,
		"O①：逐点缩放后点径带 [%.2f,%.2f]px ⊂[2.2,3.6]（细腻非方块网格感）" % [dsz * smin, dsz * smax])
	check_eq(float(fcmap.get("FOCUS_HOLD_TIME", -1.0)), 0.5,
		"O②：FOCUS_HOLD_TIME=0.5（聚焦凝聚点云面稳态持续 0.5s；N批默认 0 直入散开口径废止留痕）")
	var a_c: float = float(lcmap.get("ANIM_CONDENSE", -1.0))
	var a_h: float = float(lcmap.get("ANIM_HOLD", -1.0))
	var a_sp: float = float(lcmap.get("ANIM_SPREAD", -1.0))
	var a_a: float = float(lcmap.get("ANIM_AGGREGATE", -1.0))
	var a_r: float = float(lcmap.get("ANIM_REVIEW", -1.0))
	check_eq(a_h, float(fcmap.get("FOCUS_HOLD_TIME", -1.0)),
		"O②：ANIM_HOLD==FOCUS_HOLD_TIME==0.5（聚焦/成功两处凝聚持续口径一致）")
	check_eq(a_c, 0.25, "O⑧：ANIM_CONDENSE=0.25（加持续后平衡，N批 0.3 等价替换留痕）")
	check_eq(a_sp, 1.2, "P批波2等价替换（2026-09-10 用户口径 P-C 散开放慢+滞空）：ANIM_SPREAD=1.2（屏外散开+滞空缓动；O批 0.5 废止留痕）")
	check_eq(a_a, 1.1, "P批波2等价替换：ANIM_AGGREGATE=1.1（聚合=挂载位；O批 1.3 随总时长重排废止留痕）")
	check_eq(a_r, 0.9, "P批波2等价替换：ANIM_REVIEW=0.9（回看全程自转直入结算；O批 1.0 废止留痕）")
	var seg_sum: float = a_c + a_h + a_sp + a_a + a_r
	check(seg_sum >= 2.5 and seg_sum <= 4.0,
		"O⑧：成功动画总时长 %.2f ∈[2.5,4]s（spec 8.4 红线保持：0.25+0.5+1.2+1.1+0.9）" % seg_sum)
	# P批波2等价替换：ANIM_ALIGN=0.3（回看末对位窗口）随「不回正不重建」架构废止留痕
	check(lcmap.get("ANIM_ALIGN", null) == null,
		"P批波2等价替换：ANIM_ALIGN 对位窗口常量已废止（回看全程自转，建模保持玩家姿态直入结算不回正）")
	var fx_src: String = FileAccess.get_file_as_string(FX_SCRIPT)
	check(not fx_src.contains("BoxMesh"),
		"O①：focus_fx 源码无 BoxMesh（方形点废止，圆点化证据链）")

	# ==================== B. spread_target_screen 屏外域（纯函数，O③）====================
	check(fcmap.has("SPREAD_OUT_MARGIN") and float(fcmap["SPREAD_OUT_MARGIN"]) > 0.1 \
		and float(fcmap["SPREAD_OUT_MARGIN"]) <= 0.5,
		"O③：SPREAD_OUT_MARGIN 屏外环域外扩档存在（0.1~0.5）")
	var vsz := Vector2(1152, 648)
	var rnd_a := RandomNumberGenerator.new()
	rnd_a.seed = 20260910
	var rnd_b := RandomNumberGenerator.new()
	rnd_b.seed = 20260910
	var det_same := true
	var all_off := true
	var quadrant := {"tl": false, "tr": false, "bl": false, "br": false}
	var corner_n := 0
	var edge_n := 0
	var center := vsz * 0.5
	# 角对角线方向（1152×648：atan(324/576)≈29.36°）与边中方向（0/90/180/270°）±15° 扇区
	var ca := absf(atan2(vsz.y * 0.5, vsz.x * 0.5))
	for i: int in 2400:
		var t_a: Vector2 = fx_s.call("spread_target_screen", Vector2(576, 324), rnd_a, vsz)
		var t_b: Vector2 = fx_s.call("spread_target_screen", Vector2(576, 324), rnd_b, vsz)
		if (t_a - t_b).length() > 0.001:
			det_same = false
		# O③核心判定：全部严格落屏外（原「全部 clamp 屏内」契约反转，等价替换留痕）
		if t_a.x >= 0.0 and t_a.x <= vsz.x and t_a.y >= 0.0 and t_a.y <= vsz.y:
			all_off = false
		if t_a.x < center.x and t_a.y < center.y: quadrant["tl"] = true
		if t_a.x >= center.x and t_a.y < center.y: quadrant["tr"] = true
		if t_a.x < center.x and t_a.y >= center.y: quadrant["bl"] = true
		if t_a.x >= center.x and t_a.y >= center.y: quadrant["br"] = true
		var ang := absf(Vector2(1, 0).angle_to((t_a - center).normalized()))
		for base: float in [ca, PI - ca]:
			var d := absf(angle_difference(ang, base))
			if d < deg_to_rad(15.0):
				corner_n += 1
		for base: float in [0.0, PI * 0.5, PI, PI * 1.5]:
			var d2 := absf(angle_difference(ang, base))
			if d2 < deg_to_rad(15.0):
				edge_n += 1
	check(det_same, "O③：spread_target_screen 同种子确定性保留（静态预生成可复现）")
	check(all_off, "O③：散点目标 2400 采样全部落设计视口外（散开=逃出屏幕，原 clamp 屏内等价替换留痕）")
	check(quadrant["tl"] and quadrant["tr"] and quadrant["bl"] and quadrant["br"],
		"O③：四象限（离心向）均有目标（散开方向覆盖全周）")
	check(corner_n > edge_n,
		"O③：角向密度>边向密度（%d vs %d，离角偏置语义屏外等价保留：四角方向为主）" % [corner_n, edge_n])

	# ==================== C. 聚焦凝聚 HOLD 0.5s + 圆点 mesh（rig 属性证据链）====================
	var world := Node3D.new()
	add_child(world)
	var vp := SubViewport.new()
	vp.size = Vector2i(160, 120)
	world.add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 6.0
	cam.position = Vector3(0, 0, 20)
	vp.add_child(cam)
	var vv: Node = (vox_s as GDScript).new()
	vv.name = "VoxelView"
	vp.add_child(vv)
	vv.call("build_voxels", ["0,0,0", "1,0,0", "2,0,0", "3,0,0"], Vector3i(4, 1, 1), StandardMaterial3D.new())
	var fx: Node = (fx_s as GDScript).new()
	fx.name = "FocusFXO"
	world.add_child(fx)
	fx.call("bind_channel", "Main", vp)
	await process_frame
	var built: Array = vv.call("get_built_cells")

	check_eq(bool(fx.call("activate_channel_all", "Main", built)), true, "O② 前置：全量激活成功")
	check_eq(int(fx.call("get_phase")), int(fcmap.get("PHASE_CONDENSE", -1)), "O② 前置：进入 CONDENSE")
	await create_timer(0.35).timeout  # > CONDENSE 0.25，< 0.25+HOLD 0.5
	check_eq(int(fx.call("get_phase")), int(fcmap.get("PHASE_HOLD", -1)),
		"O②：凝聚完成 → HOLD 持续段（点云面稳态 0.5s；原直入 SPREAD 等价替换留痕）")
	check_eq(float(fx.call("get_spread_progress")), 0.0, "O②：HOLD 期散开进度=0（倒放从点云面还原语义不变）")
	await create_timer(0.55).timeout  # 累计 0.9 > 0.25+0.5
	check_eq(int(fx.call("get_phase")), int(fcmap.get("PHASE_SPREAD", -1)),
		"O②：持续 0.5s 完成 → SPREAD（散开屏外，O③）")
	var mmi: MultiMeshInstance3D = _find_mmi(fx)
	check(mmi != null and mmi.multimesh != null and (mmi.multimesh.mesh is QuadMesh),
		"O①：focus 点 mesh=QuadMesh（4 顶点圆点面片；BoxMesh 废止 SphereMesh 性能红线否决——选型报告）")
	check(mmi != null and mmi.multimesh != null and absf((mmi.multimesh.mesh as Mesh).get_aabb().size.x - dsz) < 0.001,
		"O①：QuadMesh 边长=DOT_SIZE 档（%.1fpx）" % dsz)
	if mmi != null and mmi.multimesh != null:
		var smat: Material = mmi.material_override
		check(smat is ShaderMaterial and (smat as ShaderMaterial).shader != null \
			and (smat as ShaderMaterial).shader.code.contains("smoothstep") \
			and (smat as ShaderMaterial).shader.code.contains("UV"),
			"O①：focus shader 含圆盘 alpha（UV 距心 smoothstep 软边缘）")
		check((smat as ShaderMaterial).shader.code.contains("u_spread") \
			and (smat as ShaderMaterial).shader.code.contains("INSTANCE_CUSTOM") \
			and (smat as ShaderMaterial).shader.code.contains("TIME"),
			"O①：GPU uniform/TIME 驱动红线不回退（禁逐帧 CPU 重建点阵）")
		check(int(mmi.multimesh.instance_count) == built.size() * int(fcmap.get("DOTS_PER_VOXEL", -1)),
			"O①：密度档生效（instance_count=%d 点 × %d 体素）" % [int(mmi.multimesh.instance_count), built.size()])

	# ==================== D. 全金覆写参数（O④）：缺省三色保持 / 覆写全金 ====================
	check(fcmap.get("CHANNEL_COLORS", {}).get("Main", Color()) == GOLD \
		and fcmap.get("CHANNEL_COLORS", {}).get("Target", Color()) == Color(0.30, 0.85, 0.40) \
		and fcmap.get("CHANNEL_COLORS", {}).get("Join", Color()) == Color(0.90, 0.25, 0.20),
		"O④：CHANNEL_COLORS 金/绿/红不变（聚焦区分左上/右上颜色语义保持）")
	var fx2: Node = (fx_s as GDScript).new()
	fx2.name = "FocusFXO2"
	world.add_child(fx2)
	fx2.call("bind_channel", "Join", vp)
	fx2.call("deactivate_immediate")  # 前置复位（幂等）
	check_eq(bool(fx2.call("activate_channel", "Join", [built[0]], built)), true, "O④ 前置：Join 缺省激活")
	var ch2: Dictionary = (fx2.get("_channels") as Dictionary).get("Join", {})
	check_eq(ch2.get("color", Color()), Color(0.90, 0.25, 0.20),
		"O④：缺省不覆写 → Join 通道保持红色（聚焦三色语义不回退）")
	var fx3: Node = (fx_s as GDScript).new()
	fx3.name = "FocusFXO3"
	world.add_child(fx3)
	fx3.call("bind_channel", "Join", vp)
	check_eq(bool(fx3.call("activate_channel", "Join", [built[0]], built, false, GOLD)), true,
		"O④ 前置：Join 覆写金激活（override_color 参数生效）")
	var ch3: Dictionary = (fx3.get("_channels") as Dictionary).get("Join", {})
	check_eq(ch3.get("color", Color()), GOLD, "O④：override_color.a>0 → 通道色覆写为金黄（成功动画全金）")
	await process_frame
	await process_frame  # _build_mesh call_deferred 完成
	var cols_v: Variant = fx3.get("_mm_colors")
	var cols: PackedColorArray = cols_v if cols_v is PackedColorArray else PackedColorArray()
	# Join 通道 rem=4 格−选中 1 格=3 格 ×7 点=21（每体素 DOTS_PER_VOXEL 点）
	var all_gold: bool = cols.size() == (built.size() - 1) * int(fcmap.get("DOTS_PER_VOXEL", -1))
	for c0: Color in cols:
		if not c0.is_equal_approx(GOLD):
			all_gold = false
	check(all_gold, "O④：_mm_colors 生成侧全金（覆写写入逐点色证据链；成功动画全金口径）")

	# ==================== E. viewer：涟漪移除 + 交互保留 + 圆点化 + 尺寸调档（O⑥⑦）====================
	var vsrc: String = FileAccess.get_file_as_string(VS_SCRIPT)
	var low := vsrc.to_lower()
	check(not low.contains("ripple"),
		"O⑥：viewer 源码无 ripple 符号（RIPPLE_*/u_ripple_*/_ripple_* 整套移除，grep 级断言）")
	var vprobe: Control = (vs_s as GDScript).new()
	check(not vprobe.has_method("_ripple_tick") and not vprobe.has_method("_ripple_pick") \
		and not vprobe.has_method("_write_ripple_uniforms") and not vprobe.has_method("get_ripple_strength"),
		"O⑥：涟漪方法面已移除（_ripple_tick/_ripple_pick/_write_ripple_uniforms/get_ripple_strength）")
	check(vprobe.get("debug_mouse") == null and vprobe.get("debug_force_out") == null,
		"O⑥：悬停注入钩子随交互一并移除（debug_mouse/debug_force_out）")
	check(vprobe.has_method("rotate_by") and vprobe.has_method("zoom_by") and vprobe.has_method("reset_view"),
		"O⑥：rotate_by/zoom_by/reset_view 保留（拖拽旋转+滚轮缩放，Q&A 13 既有确认需求）")
	vprobe.free()
	var dmin: float = float(vcmap.get("DOT_SIZE_MIN", -1.0))
	check(dmin >= 0.010 and dmin <= 0.015,
		"O⑦：DOT_SIZE_MIN=%.3f ∈[0.010,0.015] 世界尺寸下限档（0.005 亚像素噪点档废止）" % dmin)
	var viewer: Control = (vs_s as GDScript).new()
	add_child(viewer)
	viewer.set("point_size", 0.005)  # 图鉴/结算实设档（catalog_scene:418 / settle_scene:73 同源）
	var cloud := PointCloudData.new()
	for i: int in 16:
		cloud.points.append(Vector3(fmod(i * 7.0, 10.0) - 5.0, fmod(i * 3.0, 6.0) - 3.0, fmod(i * 11.0, 8.0) - 4.0))
		cloud.colors.append(Color(0.9, 0.8, 0.4))
	cloud.aabb_center = Vector3.ZERO
	cloud.aabb_size = Vector3(10, 6, 8)
	viewer.call("build", cloud)
	var vmesh: Mesh = (viewer.get("_pivot") as Node).get_node("PointCloud").multimesh.mesh
	check(vmesh is QuadMesh and absf(vmesh.get_aabb().size.x - dmin) < 0.0005,
		"O⑦：viewer mesh=QuadMesh 且 point_size=0.005 经下限档上调至 %.3f（圆点实体感，亚像素噪点团根因消除）" % dmin)
	var vmat: Material = viewer.call("get_cloud_material")
	check(vmat is ShaderMaterial and String((vmat as ShaderMaterial).shader.code).contains("unshaded") \
		and String((vmat as ShaderMaterial).shader.code).contains("MODEL_MATRIX") \
		and String((vmat as ShaderMaterial).shader.code).contains("smoothstep"),
		"O⑦：viewer shader=unshaded+手动 billboard（MODEL_MATRIX 平移保留）+圆盘 alpha（旋转视角恒面向相机）")
	check(not vsrc.contains("BoxMesh"), "O⑦：viewer 源码无 BoxMesh（3D 世界点同步圆点化）")
	viewer.set("point_size", 0.024)
	viewer.call("build", cloud)
	var vmesh2: Mesh = (viewer.get("_pivot") as Node).get_node("PointCloud").multimesh.mesh
	check(vmesh2 != null and absf(vmesh2.get_aabb().size.x - 0.024) < 0.0005,
		"O⑦：高于下限的实例档不受限（0.024 原样生效，max 口径单向下限）")
	viewer.queue_free()

	# ==================== F. 成功流程集成：全金/位置统一/接力/路由守护（O④⑤）====================
	_reset_save()
	var inst: Node = await _make_level(1)
	var target: Array = _target_cells()
	var jb: Button = inst.get_node_or_null("TopBar/Buttons/JoinButton")
	check(jb is Button and not target.is_empty(), "O 前置：JoinButton 与 target 就绪")
	if jb != null and not target.is_empty():
		inst.set("anim_time_scale", 8.0)
		inst.call("set_remaining_for_test", target)
		jb.pressed.emit()
		await process_frame
		await process_frame
		# O④：成功动画凝聚段三通道全金（_mm_colors 生成侧证据链）
		var fxl: Node = inst.get("_fx_layer")
		var cols2_v: Variant = fxl.get("_mm_colors") if fxl != null else null
		var cols2: PackedColorArray = cols2_v if cols2_v is PackedColorArray else PackedColorArray()
		var gold_ok: bool = cols2.size() > 0
		for c1: Color in cols2:
			if not c1.is_equal_approx(GOLD):
				gold_ok = false
		check(gold_ok, "O④：成功动画凝聚散点全金（三通道覆写，%d 点；无论左上/右上/中间）" % cols2.size())
		# O⑤：聚合段目标位=结算建模挂载位（覆盖层构建时定格）
		var rc: Vector3 = inst.get("_review_center")
		var mw: Vector3 = inst.get("_mount_world")
		check(rc.is_equal_approx(mw) and mw.length() > 0.0,
			"O⑤：_review_center==_mount_world（聚合=结算挂载位，原屏幕中心聚合等价替换留痕）")
		var align_d: Dictionary = inst.get("_align")
		check(float(align_d.get("point_size", 0.0)) >= dmin - 0.0001,
			"O⑦：对位 point_size 经下限档（结算 0.005 实读→%.3f，成功动画聚合建模同源上调）"
				% float(align_d.get("point_size", 0.0)))
		# 覆盖层建模：圆点 mesh + 全金逐点色 + 同源 shader
		var cmmi: MultiMeshInstance3D = inst.get_node_or_null(
			"SuccessOverlay/AnimContainer/AnimViewport/AnimWorld/SpinPivot/SuccessCloud") as MultiMeshInstance3D
		check(cmmi != null and cmmi.multimesh != null and (cmmi.multimesh.mesh is QuadMesh),
			"O⑦：SuccessCloud mesh=QuadMesh（成功动画建模圆点化）")
		if cmmi != null and cmmi.multimesh != null:
			var cmat: Material = (cmmi as MultiMeshInstance3D).material_override
			check(cmat is ShaderMaterial and String((cmat as ShaderMaterial).shader.code).contains("unshaded"),
				"O⑦：SuccessCloud 材质=viewer 同源圆点 ShaderMaterial（M批 StandardMaterial3D 断言等价替换）")
		var cc_v: Variant = inst.get("_cloud_colors")
		var ccols: PackedColorArray = cc_v if cc_v is PackedColorArray else PackedColorArray()
		var cgold: bool = ccols.size() > 0
		for c3: Color in ccols:
			if not c3.is_equal_approx(GOLD):
				cgold = false
		check(cgold, "O④：聚合建模逐点色全金（原 lerp 0.85 部分金口径废止，用户「全部点金黄色」）")
		# 推进过凝聚+持续+散开（(0.25+0.5+1.2)/8≈0.244s，P批波2 时长档）→ 聚合段接力（起点=屏外散点位）
		await create_timer(0.3).timeout
		check_eq(int(inst.call("get_success_seg")), 2, "O⑤：段钩子=2 聚合段（散开末帧已接力）")
		var starts: PackedVector3Array = _p3arr_or_empty(inst.get("_cloud_starts"))
		var tgts: PackedVector3Array = _p3arr_or_empty(inst.get("_cloud_targets"))
		var spin_p: Node3D = inst.get_node_or_null(
			"SuccessOverlay/AnimContainer/AnimViewport/AnimWorld/SpinPivot") as Node3D
		var relay_ok := starts.size() == tgts.size() and starts.size() > 0 and spin_p != null
		var diff_n := 0
		for i2: int in mini(starts.size(), tgts.size()):
			if not starts[i2].is_equal_approx(tgts[i2]):
				diff_n += 1
		relay_ok = relay_ok and diff_n > starts.size() / 2
		check(relay_ok, "O⑤：relay 接力起点已按 pivot-local 换算写入（屏外散点位−挂载位平移，%d/%d 改写）"
			% [diff_n, starts.size()])
		inst.call("_skip_success_animation")
		await process_frame
		check_eq(int(game.current_state()), ST_SETTLE, "O：skip 收尾路由 SETTLE（结算路由零改动红线）")
	inst.queue_free()
	_cleanup_files()
	Engine.max_fps = 0
	finish()
