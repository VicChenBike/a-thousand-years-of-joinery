extends "res://tests/test_base.gd"
## 批次 G 判定用例：第 1 关润色——锐眼（差集显示/扣费/自动关闭）+ 见证者（皮肤刷新/浮动/气泡）
## + 重玩左下退出按钮 / TopBar 退出接线。TDD 先写（实现前全 [FAIL] 属预期红灯）。
## 契约来源：批次 G 任务单（已确认决策）+ spec 7.4（锐眼）/ 8.6 与 3.2（见证者）/ 3.10 与 5.1（重玩退出）：
##   锐眼：EyeButton → 时长菜单 0.5/1.0/1.5/2.0/2.5/3.0 秒（缺省 1.0）→ 一次性扣费
##     cost = int(50 × 时长 / 0.5)；余额不足 → 提示「天赋值不足」且不动（K4-2 批次 K 起
##     经 Game.toast 右上角，HintLabel 回归纯提示——本文件用 toast_spy 断言，spec §10.6）；
##     红绿差集：多余（remaining 有 target 无）= 红色 mark；缺少（target 有 remaining 无）= 绿色半透明 ghost；
##     开启期间挖除/撤销/重做实时重算；到时自动关闭（恢复 mark 与 ghost）；
##     开启中再次点击按钮 = 重新弹菜单，选中后旧效果先清再重开（本批选定行为，见交付报告）。
##   纯函数：static diff_vs_target(remaining, target[, size]) -> {extra: Array, missing: Array}。
##   见证者：监听 SaveManager.skin_changed 刷新立绘（修批次 D P3：只在 _ready 应用一次）；
##     _process 正弦上下浮动 + 缩放呼吸（纯装饰）；点击弹「……」气泡（台词留空铁律，TODO 待用户台词），
##     再点击关闭或到时自动隐藏；气泡 mouse_filter=IGNORE 不挡手势 HUD/设置按钮。
##   重玩退出：context.replay=true → 左下 ExitReplayButton → 确认「返回图鉴？」→ CATALOG；
##     replay=false → 维持 TopBar ExitButton（本批接线）→ 确认「返回主菜单？」→ MAIN_MENU；
##     成功动画输入锁定期间退出/锐眼禁用 + 处理器守卫（信号直发也不生效）。
## 测试对「到时自动关闭」不等待 3 秒真实时间（任务单约定）：两条路径——
##   ① 直接驱动 _finish_eye() 钩子；② 可控短时长（0.05s）走真实 _process 倒计时。

const LS_SCRIPT := "res://scenes/level/level_scene.gd"
const LEVEL_SCENE := "res://scenes/level/level_scene.tscn"
const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"

# Game.State 枚举（与 test_level_flow 一致）：BOOT=0 MAIN_MENU=1 OPENING_MOVIE=2 TALK=3 LEVEL=4 SETTLE=5 CATALOG=6
const ST_MAIN_MENU := 1
const ST_SETTLE := 5
const ST_CATALOG := 6

const EYE_EXTRA_CELL := "9,0,0"    # 第 1 关挖除格（∈blocks、∉target_shapes[0]；批次 Z 五件套实况——旧 6,0,1 现属 target 故等价替换）→ extra 样本
const EYE_MISSING_CELL := "0,0,0"  # 第 1 关 target_shapes[0] 首格 → missing 样本

## 批次V规格§3.2（V-C5）夹具：TopStrip 替身——记录 Game.confirm 委托来的 push_confirm 调用
##（test_v_game_confirm 同款形态）；确认/取消由测试直接调用记录到的回调（模拟条内按钮触发）。
class StripSpy extends Node:
	var confirm_calls: Array = []   # 每项 [text, on_confirmed, on_canceled]
	func push_confirm(text: String, on_confirmed: Callable = Callable(),
			on_canceled: Callable = Callable()) -> void:
		confirm_calls.append([text, on_confirmed, on_canceled])
	func get_confirm_calls() -> Array:
		return confirm_calls

var game: Variant
var save: Variant
var lib: Variant
var ssp: Node

func _cleanup_files() -> void:
	for p: String in [SAVE_PATH, FLAG_PATH]:
		var abs: String = ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs):
			DirAccess.remove_absolute(abs)

func _reset_save() -> void:
	_cleanup_files()
	save.load_game()

func _target_cells() -> Array:
	var lvl: Dictionary = lib.call("get_level", 1)
	check(not lvl.is_empty(), "前置：第 1 关关卡数据已扫描（levels_data）")
	if lvl.is_empty():
		return []
	var pieces: Array = (lvl["data"] as Dictionary)["pieces"]
	return (pieces[0] as Dictionary)["target_shapes"][0]

func _parse(s: String) -> Vector3i:
	var p: PackedStringArray = s.split(",")
	return Vector3i(int(p[0]), int(p[1]), int(p[2]))

func _make_level(ch: int, replay: bool = false) -> Node:
	var inst: Node = (load(LEVEL_SCENE) as PackedScene).instantiate()
	inst.call("set_context", {"chapter": ch, "replay": replay})
	add_child(inst)
	await process_frame
	return inst

func _click() -> InputEventMouseButton:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = Vector2(10, 10)
	return mb

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
const DISC_BK_PREFIX := "user://_r2b_lex_backup_"
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
	print("EVID|user_restore|lex|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_level_extra ==")
	_backup_user()
	Engine.max_fps = 60
	game = get_root().get_node("Game")
	save = get_root().get_node("SaveManager")
	lib = get_root().get_node("LevelLibrary")
	# K4-2（spec §10.6）：锐眼「天赋值不足」等失败提示已迁 Game.toast——经 toast_spy 夹具断言
	var tspy: Node = (load("res://tests/fixtures/toast_spy.gd") as GDScript).new()
	add_child(tspy)
	game.call("attach_toast", tspy)
	# 批次V规格§3.2（V-C5）：关卡退出确认迁移 Game.confirm → 统一确认条——spy 夹具注册到
	# autoload Game（注册路径；未挂接兜底路径归 test_v_game_confirm）
	ssp = StripSpy.new()
	add_child(ssp)
	game.call("attach_strip", ssp)
	_cleanup_files()
	save.load_game()
	lib.call("scan_directory", "res://levels_data")

	var ls: Script = load(LS_SCRIPT) as Script
	check(ls != null, "level_scene.gd 可加载")
	if ls == null:
		finish()
		return
	var cmap: Dictionary = ls.get_script_constant_map()

	# ---- 1. 纯函数 diff_vs_target（锐眼差集：多余=extra / 缺少=missing）----
	var has_diff: bool = ls.has_method("diff_vs_target")
	check(has_diff, "静态接口存在: level_scene.diff_vs_target")
	if has_diff:
		var tgt: Array = ["0,0,0", "1,0,0", "2,0,0"]
		# 全等（键型/顺序无关，Vector3i 键 vs 字符串 shape）→ 空差
		var d0: Dictionary = ls.call("diff_vs_target",
			{Vector3i(2, 0, 0): true, Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true}, tgt)
		check_eq((d0["extra"] as Array).size(), 0, "差集·全等：extra 为空")
		check_eq((d0["missing"] as Array).size(), 0, "差集·全等：missing 为空")
		# 缺少（target 有 remaining 无）
		var d1: Dictionary = ls.call("diff_vs_target", {Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true}, tgt)
		check_eq((d1["extra"] as Array).size(), 0, "差集·缺少只：无多余")
		check((d1["missing"] as Array).has(Vector3i(2, 0, 0)), "差集·缺少只：target 有 remaining 无 → missing")
		# 多余只（remaining 有 target 无）
		var d2: Dictionary = ls.call("diff_vs_target", {Vector3i(0, 0, 0): true, Vector3i(5, 0, 0): true}, tgt)
		check((d2["extra"] as Array).has(Vector3i(5, 0, 0)), "差集·多余只：remaining 有 target 无 → extra")
		check_eq((d2["missing"] as Array).size(), 2, "差集·多余只：missing 恰 2 格")
		# 混合
		# N批等价替换：diff_vs_target 改按 48 变换「最佳变换差集」口径（spec §6.1）——
		# 平移归一后 target 单格 "1,0,0" 与 player 的 (0,0,0) 匹配 → missing 空；
		# 旧断言「missing 含 (1,0,0)/extra 恰 2 格」按逐坐标精确比较旧口径废止留痕。
		var d3: Dictionary = ls.call("diff_vs_target", {Vector3i(0, 0, 0): true, Vector3i(9, 9, 9): true}, ["1,0,0"])
		check((d3["extra"] as Array).has(Vector3i(9, 9, 9)), "差集·混合：extra 含 (9,9,9)（真实多余格）")
		check_eq((d3["extra"] as Array).size(), 1, "差集·混合：extra 恰 1 格（N批平移归一后 (0,0,0) 与 target 匹配）")
		check_eq((d3["missing"] as Array).size(), 0, "差集·混合：missing 空（target 单格已被匹配，N批等价替换）")
		# 去重 + 非法字符串跳过（target 含重复坐标与无法解析元素）
		var d4: Dictionary = ls.call("diff_vs_target", {"0,0,0": true}, ["0,0,0", "0,0,0", "bad"])
		check_eq((d4["extra"] as Array).size(), 0, "差集：重复坐标去重")
		check_eq((d4["missing"] as Array).size(), 0, "差集：非法字符串跳过不崩")
		# 非法坐标（≥size / 负值）：传入关卡包围盒尺寸时按 spec 越界过滤规则剔除
		var d5: Dictionary = ls.call("diff_vs_target",
			{"8,0,0": true, "-1,0,0": true}, ["0,3,0", "0,0,8"], Vector3i(8, 3, 8))
		check_eq((d5["extra"] as Array).size(), 0, "差集·越界过滤：extra 剔除（≥size/负值）")
		check_eq((d5["missing"] as Array).size(), 0, "差集·越界过滤：missing 剔除（≥size/负值）")
		# N批等价替换（行为反转留痕）：平移归一后同形异位 → 等价 → 差集红绿皆空；
		# 旧断言「extra 含 (8,0,0)」按原坐标直算旧口径废止——等价形状不再显示误导差异。
		var d6: Dictionary = ls.call("diff_vs_target", {"8,0,0": true}, ["0,0,0"])
		check_eq((d6["extra"] as Array).size(), 0, "差集·平移等价：同形异位 extra 为空（N批反转旧口径）")
		check_eq((d6["missing"] as Array).size(), 0, "差集·平移等价：同形异位 missing 为空（N批反转旧口径）")
		# 空对空
		var d7: Dictionary = ls.call("diff_vs_target", {}, [])
		check_eq((d7["extra"] as Array).size(), 0, "差集·空对空：extra 为空")
		check_eq((d7["missing"] as Array).size(), 0, "差集·空对空：missing 为空")
		# N批新增：等价形状（绕水平轴翻转+平移）→ 差集红绿皆空（spec §6.2：锐眼等价挖法无红无绿）
		var tgt_eq: Array = ["0,0,0", "1,0,0", "1,1,0"]
		var flip_eq: Dictionary = {Vector3i(0, 2, 0): true, Vector3i(1, 2, 0): true, Vector3i(1, 1, 0): true}
		var d_eq: Dictionary = ls.call("diff_vs_target", flip_eq, tgt_eq)
		check_eq((d_eq["extra"] as Array).size(), 0, "差集·等价：翻转+平移挖法 extra 为空（N批新增）")
		check_eq((d_eq["missing"] as Array).size(), 0, "差集·等价：翻转+平移挖法 missing 为空（N批新增）")
		# 缺省（未传 size）不过滤语义保留（N批等价替换：改用非等价形状承载旧 d6 断言属性）——
		# 越界格不被剔除，玩家 2 格相距 8 的形状无法与 2 连格等价 → 真实差异照常报出
		var d_nf: Dictionary = ls.call("diff_vs_target",
			{Vector3i(0, 0, 0): true, Vector3i(8, 0, 0): true}, ["0,0,0", "1,0,0"])
		check((d_nf["extra"] as Array).has(Vector3i(8, 0, 0)), "差集·缺省不过滤：未传 size 越界格保留参与比较")
		# N批新增（spec §6.2 走查口径无头化）：真实第 1 关 target 整体绕水平轴翻转的挖法 →
		# 等价 → 锐眼差集红绿皆空（不出现「显示差异但实际能通关」误导）
		var lvl_eq: Dictionary = lib.call("get_level", 1)
		if not lvl_eq.is_empty():
			var tgt1_eq: Array = ((lvl_eq["data"] as Dictionary)["pieces"][0] as Dictionary)["target_shapes"][0]
			var flip1_eq: Dictionary = {}
			for s_eq: String in tgt1_eq:
				var pp_eq: PackedStringArray = s_eq.split(",")
				flip1_eq["%s,%d,%s" % [pp_eq[0], -int(pp_eq[1]), pp_eq[2]]] = true
			var d_eq1: Dictionary = ls.call("diff_vs_target", flip1_eq, tgt1_eq)
			check_eq((d_eq1["extra"] as Array).size(), 0, "差集·真实关卡：第 1 关目标整体翻转挖法 extra 为空（N批新增）")
			check_eq((d_eq1["missing"] as Array).size(), 0, "差集·真实关卡：第 1 关目标整体翻转挖法 missing 为空（N批新增）")

	# ---- 2. 锐眼计费与常量（spec 7.4：50 天赋值 / 0.5 秒，一次性扣）----
	check(cmap.has("EYE_DURATIONS") and (cmap["EYE_DURATIONS"] as Array).size() == 6,
		"锐眼：时长档位常量 6 档")
	check(cmap.has("EYE_DURATIONS") and float((cmap["EYE_DURATIONS"] as Array)[0]) == 0.5
		and float((cmap["EYE_DURATIONS"] as Array)[5]) == 3.0, "锐眼：档位范围 0.5~3.0 秒")
	check(float(cmap.get("EYE_DEFAULT_DURATION", 0.0)) == 1.0, "锐眼：缺省时长 1.0 秒")
	var has_cost: bool = ls.has_method("eye_cost")
	check(has_cost, "静态接口存在: level_scene.eye_cost")
	if has_cost:
		check_eq(int(ls.call("eye_cost", 0.5)), 50, "计费：0.5s → 50")
		check_eq(int(ls.call("eye_cost", 1.0)), 100, "计费：1.0s → 100")
		check_eq(int(ls.call("eye_cost", 1.5)), 150, "计费：1.5s → 150")
		check_eq(int(ls.call("eye_cost", 2.5)), 250, "计费：2.5s → 250")
		check_eq(int(ls.call("eye_cost", 3.0)), 300, "计费：3.0s → 300")

	# ---- 3. 锐眼开启：扣费 + 红绿差集（多余=红 mark / 缺少=绿 ghost）----
	_reset_save()
	save.add_talent(1000)
	var inst1: Node = await _make_level(1)
	var target: Array = _target_cells()
	check(target.size() > 0, "锐眼前置：target_shapes[0] 非空")
	var main_vv: Node = inst1.get_node_or_null("MainView/ViewportContainer/SubViewport/VoxelView")
	check(main_vv != null, "锐眼前置：MainView VoxelView 存在")
	var ref_cell: Vector3i = _parse(String(target[5]))
	var n_ref: MeshInstance3D = main_vv.call("get_voxel_node", ref_cell)
	var mat_def: Material = n_ref.material_override if n_ref != null else null
	var t_before: int = int(save.get_talent())
	var wrong_set: Array = target.slice(1)
	wrong_set.append(EYE_EXTRA_CELL)
	inst1.call("set_remaining_for_test", wrong_set)
	inst1.call("_hide_cell", _parse(EYE_MISSING_CELL))  # set_remaining_for_test 不改可见性：补隐藏被挖格（与真实删除路径一致，幻影位置依赖它）
	var started: bool = inst1.call("_start_eye", 1.0)
	check(started == true, "锐眼：开启成功返回 true")
	check(inst1.call("is_eye_active") == true, "锐眼：开启后处于激活态")
	check_eq(int(save.get_talent()), t_before - 100, "锐眼：扣费=100（1.0s 档，前后差）")
	var talent_label: Label = inst1.get_node_or_null("TopBar/TalentLabel")
	check(talent_label != null and String(talent_label.text).contains(str(t_before - 100)),
		"锐眼：天赋值 HUD 同步刷新")
	var n_extra: MeshInstance3D = main_vv.call("get_voxel_node", _parse(EYE_EXTRA_CELL))
	var mark_mat: StandardMaterial3D = n_extra.material_override if n_extra != null else null
	if started and main_vv != null:
		check(n_extra is MeshInstance3D, "锐眼前置：extra 体素节点存在")
		check(mark_mat != null and mark_mat != mat_def, "锐眼：extra 体素切换为 mark 材质")
		check(mark_mat != null and mark_mat.albedo_color.r > 0.9 and mark_mat.albedo_color.g < 0.5,
			"锐眼：mark 为红色系（多余=红）")
		check(n_ref != null and n_ref.material_override == mat_def, "锐眼：与 target 一致的格不受影响")
		var ghosts: Array = main_vv.call("get_ghost_cells")
		check_eq((ghosts as Array).size(), 1, "锐眼：missing 恰 1 格")
		check((ghosts as Array).has(_parse(EYE_MISSING_CELL)), "锐眼：ghost 位于缺失格 %s" % EYE_MISSING_CELL)
		var g_node: MeshInstance3D = main_vv.call("get_ghost_node", _parse(EYE_MISSING_CELL))
		check(g_node is MeshInstance3D and g_node.visible, "锐眼：绿 ghost 节点存在且可见")
		if g_node != null:
			var gm: StandardMaterial3D = g_node.material_override
			check(gm != null and gm.albedo_color.g > 0.8 and gm.albedo_color.r < 0.7,
				"锐眼：ghost 为绿色系（缺少=绿）")
			check(gm != null and gm.albedo_color.a < 0.99, "锐眼：ghost 半透明（幻影）")
		check_eq(int(main_vv.call("get_voxel_count")), 180, "锐眼：ghost 不计入体素数（仍 180，批次 Z 实况）")

	# ---- 3b. 开启期间挖除/撤销/重做 → 实时重算差集 ----
	if started:
		inst1.call("select_voxel", _parse(EYE_EXTRA_CELL), false)
		check(n_extra.material_override != mark_mat, "锐眼·重算：选中 extra 格暂以高亮显示（让位绿色选中）")
		inst1.call("clear_selection")
		check(n_extra.material_override == mark_mat, "锐眼·重算：Esc/清空选区后 extra 格重新标红")
		inst1.call("select_voxel", _parse(EYE_EXTRA_CELL), false)
		check(n_extra.material_override != mark_mat, "锐眼·重算：再选中又让位高亮")
		inst1.call("delete_selected")
		check(n_extra.material_override == mat_def, "锐眼·重算：删除多余格后 mark 清除（恢复默认）")
		check_eq((main_vv.call("get_ghost_cells") as Array).size(), 1, "锐眼·重算：删除多余格不产生新 ghost")
		check(inst1.call("undo") == true, "锐眼·重算：撤销恢复多余格")
		check(n_extra.material_override == mark_mat, "锐眼·重算：撤销后 extra 重新标红")
		check(inst1.call("redo") == true, "锐眼·重算：重做再删多余格")
		check(n_extra.material_override == mat_def, "锐眼·重算：重做后 mark 再次清除")

	# ---- 3c. 直接驱动 _finish_eye（不等真实时间的关闭路径；选中格高亮互不破坏）----
	if started:
		inst1.call("select_voxel", ref_cell, false)  # 选中未标记格（高亮）
		inst1.call("_finish_eye")
		check(inst1.call("is_eye_active") == false, "锐眼：_finish_eye 后退出激活态")
		check(n_extra.material_override == mat_def, "锐眼·关闭：mark 恢复默认材质")
		check(n_ref.material_override != mat_def, "锐眼·关闭：选中格高亮保留（与 mark 互不破坏）")
		check((main_vv.call("get_ghost_cells") as Array).is_empty(), "锐眼·关闭：ghost 全部清除")

	# ---- 3d. 激活中再次开启：旧效果先清、重新扣费（本批选定行为）----
	var t_mid: int = int(save.get_talent())
	check(inst1.call("_start_eye", 0.5) == true, "锐眼·重开：激活中可直接重开（返回 true）")
	check(inst1.call("is_eye_active") == true, "锐眼·重开：仍处于激活态")
	check_eq(int(save.get_talent()), t_mid - 50, "锐眼·重开：按新时长重新扣费（0.5s=50）")
	check_eq((main_vv.call("get_ghost_cells") as Array).size(), 1, "锐眼·重开：ghost 无重复累积")

	# ---- 3e. P3-1 修复：激活中重开但余额不足 → 先扣费后清旧，失败保留旧效果继续显示 ----
	# （修复前：先 _finish_eye 清旧再扣费，扣费失败会把已付费的剩余差集显示一并丢失）
	save.spend_talent(int(save.get_talent()))  # 天赋值清零 → 重开必扣费失败
	var hint_p31: Label = inst1.get_node_or_null("HintLabel")
	check(inst1.call("_start_eye", 0.5) == false, "P3-1：余额不足时激活态重开失败返回 false")
	check(inst1.call("is_eye_active") == true, "P3-1：失败后旧激活态保留（扣费失败不提前清旧）")
	check_eq((main_vv.call("get_ghost_cells") as Array).size(), 1, "P3-1：旧 ghost 差集显示保留（继续显示）")
	var p31_calls: Array = tspy.call("get_calls")
	var p31_last: Array = p31_calls[p31_calls.size() - 1] if not p31_calls.is_empty() else []
	check(not p31_last.is_empty() and String(p31_last[0]).contains("天赋值不足"),
		"P3-1+K4-2：重开扣费失败提示「天赋值不足」改走 Game.toast（旧效果未被破坏）")
	check(hint_p31 != null and not String(hint_p31.text).contains("天赋值不足"),
		"K4-2：hint_label 不再承载「天赋值不足」错误长文案（回归纯提示）")
	inst1.call("_finish_eye")
	inst1.queue_free()

	# ---- 4. 锐眼余额不足：提示「天赋值不足」且不清扣、无效果 ----
	_reset_save()  # J1-4 后默认天赋=500，须显式归零构造「余额不足」前置
	save.spend_talent(int(save.get_talent()))
	var inst2: Node = await _make_level(1)
	var hint2: Label = inst2.get_node_or_null("HintLabel")
	var t2: int = int(save.get_talent())
	var spy_n2: int = (tspy.call("get_calls") as Array).size()
	check(inst2.call("_start_eye", 0.5) == false, "锐眼·余额不足：开启失败返回 false")
	check(inst2.call("is_eye_active") == false, "锐眼·余额不足：不进入激活态")
	var s4: Array = tspy.call("get_calls")
	check(s4.size() == spy_n2 + 1 and String(s4[s4.size() - 1][0]).contains("天赋值不足"),
		"锐眼·余额不足：提示「天赋值不足」经 Game.toast（K4-2 toast 口径）")
	check(hint2 != null and not String(hint2.text).contains("天赋值不足"),
		"K4-2：锐眼失败不改 hint_label（回归纯提示）")
	check_eq(int(save.get_talent()), t2, "锐眼·余额不足：不清扣（余额不变）")
	var mv2: Node = inst2.get_node_or_null("MainView/ViewportContainer/SubViewport/VoxelView")
	check((mv2.call("get_ghost_cells") as Array).is_empty(), "锐眼·余额不足：无 ghost 残留")
	inst2.queue_free()

	# ---- 5. 到时自动关闭：可控短时长（0.05s）走真实 _process 倒计时 ----
	_reset_save()
	save.add_talent(1000)
	var inst3: Node = await _make_level(1)
	var mv3: Node = inst3.get_node_or_null("MainView/ViewportContainer/SubViewport/VoxelView")
	var target3: Array = _target_cells()
	var wrong3: Array = target3.slice(1)
	wrong3.append(EYE_EXTRA_CELL)
	inst3.call("set_remaining_for_test", wrong3)
	inst3.call("_hide_cell", _parse(EYE_MISSING_CELL))  # 同 3 节：补隐藏被挖格（真实删除路径一致）
	check(inst3.call("_start_eye", 0.05) == true, "锐眼·自动关闭：短时长（0.05s）开启成功")
	check(inst3.call("is_eye_active") == true, "锐眼·自动关闭：开启中")
	await create_timer(0.6).timeout
	check(inst3.call("is_eye_active") == false, "锐眼·自动关闭：到时自动关闭（_process 倒计时）")
	check((mv3.call("get_ghost_cells") as Array).is_empty(), "锐眼·自动关闭：ghost 已清除")
	var nx3: MeshInstance3D = mv3.call("get_voxel_node", _parse(EYE_EXTRA_CELL))
	var nr3: MeshInstance3D = mv3.call("get_voxel_node", _parse(String(target3[5])))
	check(nx3 != null and nr3 != null and nx3.material_override == nr3.material_override,
		"锐眼·自动关闭：mark 恢复默认材质")

	# ---- 6. 锐眼时长菜单：6 档、选择即按档扣费开启 ----
	# 批次 X P4（spec §5）适配：PopupMenu（独立 Window 子视口）→ 主视口自绘面板
	# eye_duration_panel.gd——弹出断言节点形态等价替换（Variant 取用防旧/新实例型别碰撞）。
	var t3b: int = int(save.get_talent())
	inst3.call("_open_eye_menu")
	var menu_v: Variant = inst3.get("_eye_menu")
	check(menu_v is PanelContainer, "锐眼·菜单：点击按钮弹出时长菜单（P4：主视口自绘面板）")
	check(menu_v != null and bool((menu_v as Control).visible), "锐眼·菜单：面板在场可见")
	var eye_btns: Variant = menu_v.get("_buttons") if menu_v != null else null
	if eye_btns is Array and (eye_btns as Array).size() >= 6:
		check_eq((eye_btns as Array).size(), 6, "锐眼·菜单：6 个时长选项")
		check(String((eye_btns[0] as Button).text).begins_with("0.5"), "锐眼·菜单：首项 0.5 秒档")
		check(String((eye_btns[5] as Button).text).begins_with("3.0"), "锐眼·菜单：末项 3.0 秒档")
	inst3.call("_on_eye_duration_selected", 2)  # 1.5s 档 → 150
	check(inst3.call("is_eye_active") == true, "锐眼·菜单：选择 1.5s 后开启")
	check_eq(int(save.get_talent()), t3b - 150, "锐眼·菜单：按档扣费 150")
	# P2-1（审查回修）：锐眼→聚焦方向互斥——聚焦激活中开锐眼强制退聚焦（spec §10.5 双向）
	save.add_talent(1000)
	var fcell3: Vector3i = _parse(String(target3[5]))
	inst3.call("select_voxel", fcell3, false)
	inst3.call("_toggle_focus")
	var fxm3: Node = inst3.get("_fx_main")
	check(bool(fxm3.call("is_active")), "P2-1 前置：主视图聚焦激活")
	check(inst3.call("_start_eye", 0.5) == true, "P2-1：聚焦中开锐眼成功（正常扣费）")
	check(bool(fxm3.call("is_active")) == false and bool(inst3.get("_focus_active")) == false,
		"P2-1：开锐眼强制退聚焦（互斥双向）")
	inst3.call("clear_selection")
	inst3.call("_finish_eye")
	inst3.queue_free()

	# ---- 7. 见证者：skin_changed → 立绘刷新（修批次 D P3）----
	# K-D 后全新档默认 equipped=skin_origin_kaitou，故显式穿回 skin_default 以校验缺省立绘兜底分支。
	_reset_save()
	save.equip_skin("skin_default")
	var instw: Node = await _make_level(1)
	var wit: TextureRect = instw.get_node_or_null("WitnessPortrait")
	check(wit is TextureRect, "见证者前置：WitnessPortrait 存在")
	check(String(instw.call("get_witness_texture_path")).contains("default_witness"),
		"见证者：缺省立绘（skin_default）")
	var tex0: Texture2D = wit.texture
	var skins: Dictionary = save.get_skins()
	(skins["owned"] as Array).append("skin_02")
	check(save.equip_skin("skin_02") == true, "见证者前置：穿戴 skin_02")
	check(String(instw.call("get_witness_texture_path")).contains("skin_02"),
		"见证者：skin_changed 后立绘路径刷新为皮肤")
	check(wit.texture != tex0, "见证者：纹理对象已切换（非缺省立绘）")

	# ---- 8. 见证者：点击气泡（批次 Y Y-C7/Y-C8：事件分流恢复点击链 + 洗牌袋台词）----
	# 批次 W（P1-7a）等价改写：立绘本体让出与 MainView 的拾取重叠带——STOP→IGNORE；批次 Y
	# Y-C7 起点击链经 MainView gui_input 事件分流恢复（不回滚 STOP）。
	# 批次 AD §4.3.5 等价改写（立绘点击恢复）：MainView 锚点收窄至 0.115（< 立绘右缘 0.11 的
	# 避让界）后两者**不再物理重叠**，重叠带根因消失 → 立绘恢复 MOUSE_FILTER_STOP(0) 并直连
	# gui_input 点击弹泡（旧「IGNORE + MainView 分流」两难随收窄退役）。断言数 1→2（只增不减）：
	# ①filter=STOP（旧 IGNORE 留痕反置）②gui_input 点击链已连接（§4.3.5 立绘可点击性判据语义保持）。
	check(int(wit.get("mouse_filter")) == 0,
		"AD §4.3.5：立绘 mouse_filter=STOP（MainView 锚点收窄 0.115 避让后重叠带根因消失；旧 W P1-7a「IGNORE」随收窄退役留痕）")
	check(wit.gui_input.is_connected(Callable(instw, "_on_witness_gui_input")),
		"AD §4.3.5：立绘 gui_input 已连 _on_witness_gui_input（键鼠/手势合成点击同路可达；旧 Y-C7「MainView 分流」职责移交）")
	var bubble: Label = instw.get_node_or_null("WitnessBubble")
	check(bubble is Label, "见证者：气泡节点存在")
	check(bubble.visible == false, "见证者：气泡初始隐藏")
	# M-D：显式确保可见头顶度量就绪（resized/call_deferred 链路外的确定性保障）
	instw.call("_refresh_witness_metrics")
	# 批次 W（P3-3c）等价改写留痕：_on_witness_gui_input 随 gui_input 死连接退役（P1-7a 后
	# 不可达），开/合断言改直调 _show/_hide_witness_bubble（同一被调函数，值断言逐字不变）。
	# 批次 Y（Y-C8）：台词源=洗牌袋（剧情对话/气泡_第N关.json，Y4 域交付）；本套件注入
	# tests/fixtures 夹具保确定性——不在 剧情对话/ 建改任何文件；旧 WITNESS_BUBBLE_LINES
	# 顺序轮换断言随数组退役（旧 8 条逐字留痕见 level_scene 常量段；≤20 字等回修2 E 文案
	# 风格规则仅约束旧试写稿，正式文案由用户提供不受此限）。
	instw.call("load_witness_lines_from_path", "res://tests/fixtures/bubble_y5_fixture.json")
	var pool_x: Variant = instw.call("get_witness_lines_pool")
	check(pool_x is Array and (pool_x as Array).size() == 4, "见证者：夹具台词池已注入（Y-C8 洗牌袋，4 条）")
	instw.call("_show_witness_bubble")
	check(bubble.visible == true, "见证者：点击 → 气泡弹出")
	check(pool_x is Array and String(bubble.text) in (pool_x as Array),
		"见证者：气泡文本∈洗牌袋台词池（当前=%s）" % String(bubble.text))
	check(int(bubble.get("vertical_alignment")) == VERTICAL_ALIGNMENT_CENTER,
		"回修2 F：气泡文字盒内垂直居中（用户反馈贴底观感怪异）")
	check(bubble.size.y <= 48.0, "回修2 F：气泡盒高紧凑（短句 ≤48px，实际 %.0f；Y-C8 长句 fit_content 自适应向上长高，盒底贴头不变）" % bubble.size.y)
	check(int(bubble.get("mouse_filter")) == 2, "见证者：气泡不挡输入（IGNORE，不挡手势 HUD/设置）")
	check(int(bubble.get("autowrap_mode")) != 0,
		"Y-C8：气泡 autowrap（正式长句换行自适应；fit_content 属性本构建不存在——bool(null) 坑留痕，盒底贴头语义保持）")
	# M-D 落位留痕（等价替换，只增不减）：原批次 G 气泡段无位置断言，本批锚定「气泡贴可见头顶」
	# 语义防回归——气泡全局底 == 见证者可见头顶全局 y − 4（±2px，portrait_metrics used_rect
	# 口径，level_scene._sync_bubble_y 同源数学；完整几何断言收敛于 test_m_portrait_fit 段 D；
	# 回修 2026-09-08：GAP 8→4 配合文字贴盒底，视觉文字底距头顶 ≤15px）。
	var pmd: GDScript = load("res://scripts/portrait_metrics.gd")
	var md_m: Dictionary = pmd.call("measure", String(instw.call("get_witness_texture_path")))
	var md_f: Dictionary = pmd.call("fit_in_box", md_m["size"], md_m["rect_px"], wit.size)
	var md_head: float = wit.global_position.y + float(md_f["head_local_y"]) * wit.scale.y
	var md_gap: float = (bubble.global_position.y + bubble.size.y) - (md_head - 4.0)
	check(absf(md_gap) <= 2.0, "M-D：气泡弹出即贴可见头顶−4px（±2px，拍板 M4-4，实测差 %.2f）" % md_gap)
	instw.call("_hide_witness_bubble")
	check(bubble.visible == false, "见证者：再次点击 → 气泡关闭")
	instw.call("_show_witness_bubble")
	check(bubble.visible == true, "见证者：再点击 → 气泡再弹")
	instw.set_process(false)
	instw.call("_process", 10.0)
	check(bubble.visible == false, "见证者：超时气泡自动隐藏")
	instw.queue_free()

	# ---- 9. 见证者：上下浮动 + 缩放呼吸（确定性驱动：set_process(false) 后手动喂 delta）----
	var instf: Node = await _make_level(1)
	instf.set_process(false)
	var witf: TextureRect = instf.get_node_or_null("WitnessPortrait")
	var amp: float = float(cmap.get("WITNESS_FLOAT_AMP", 0.0))
	var breath: float = float(cmap.get("WITNESS_BREATH_AMP", 0.0))
	check(amp > 0.0 and breath > 0.0, "见证者：浮动/呼吸幅度为正常数（纯装饰）")
	instf.set("_witness_float_phase", 0.0)
	instf.call("_process", 0.0)
	var base: Vector2 = instf.get("_witness_base_pos")
	check(is_equal_approx(witf.position.y, base.y), "见证者：phase=0 → 位置=基准（确定性前提）")
	instf.call("_process", 0.6)
	var phase: float = float(instf.get("_witness_float_phase"))
	check(absf(phase - 1.2) < 0.001, "见证者：相位按 delta×speed 推进（0.6s×2.0=1.2 rad）")
	check(absf(witf.position.y - (base.y + sin(1.2) * amp)) < 0.01,
		"见证者：y = 基准 + 幅度×sin(phase)（上下浮动）")
	var expect_s: float = 1.0 + sin(2.4) * breath
	check(absf(witf.scale.x - expect_s) < 0.001, "见证者：scale = 1 + 呼吸幅度×sin(2×phase)（缩小放大）")
	instf.queue_free()

	# ---- 10. 重玩模式：左下 ExitReplayButton → 确认「返回图鉴？」→ CATALOG ----
	_reset_save()
	var insta: Node = await _make_level(1, true)
	var rb: Button = insta.get_node_or_null("ExitReplayButton")
	check(rb is Button, "重玩：ExitReplayButton 节点存在")
	check(rb != null and rb.visible, "重玩：context.replay=true → 左下退出按钮可见")
	var l10_before: int = (ssp.call("get_confirm_calls") as Array).size()
	if rb != null:
		rb.pressed.emit()
	# 批次V规格§3.2（V-C5）等价替换留痕（原 K4-1/J6-P2-9：ExitDialog=GlassDialog 节点实例/
	# 节点可见性/Body 正文含「图鉴」/Title 中文「退出」断言）：关卡退出确认改经 Game.confirm →
	# 统一确认条（顶部成条无标题位），正文/标题断言等价替换为「spy 收到逐字文案 + 回调透传」。
	var l_recs: Array = ssp.call("get_confirm_calls")
	check_eq(l_recs.size(), l10_before + 1, "批次V§3.2：重玩点击 → 统一确认条弹出（Game.confirm 恰 1 条）")
	var l_ok: Callable = Callable()
	var l_cancel: Callable = Callable()
	if l_recs.size() == l10_before + 1:
		var l_rec: Array = l_recs[l_recs.size() - 1]
		check_eq(String(l_rec[0]), "返回图鉴？", "批次V§3.2：重玩确认文案逐字「返回图鉴？」（原正文含「图鉴」断言等价替换升格逐字）")
		check((l_rec[1] as Callable).is_valid(), "批次V§3.2：确认回调透传有效（挂起目标路由）")
		check((l_rec[2] as Callable).is_valid(), "批次V§3.2：取消回调透传有效（挂起路由作废语义）")
		l_ok = l_rec[1]
	if l_ok.is_valid():
		l_ok.call()
	check_eq(int(game.current_state()), ST_CATALOG, "重玩：确认 → Game 路由 CATALOG（spec 3.10/Q&A10）")
	insta.queue_free()

	# ---- 11. 正常模式：TopBar ExitButton（本批接线）→ 确认「返回主菜单？」→ MAIN_MENU ----
	var instn: Node = await _make_level(1, false)
	var rb2: Button = instn.get_node_or_null("ExitReplayButton")
	check(rb2 != null and rb2.visible == false, "正常：context.replay=false → 左下退出按钮隐藏（维持现状）")
	var eb: Button = instn.get_node_or_null("TopBar/Buttons/ExitButton")
	var l11_before: int = (ssp.call("get_confirm_calls") as Array).size()
	if eb != null:
		eb.pressed.emit()
	var l11_recs: Array = ssp.call("get_confirm_calls")
	check_eq(l11_recs.size(), l11_before + 1, "批次V§3.2：正常点击退出 → 统一确认条弹出（Game.confirm 恰 1 条）")
	if l11_recs.size() == l11_before + 1:
		var l11_rec: Array = l11_recs[l11_recs.size() - 1]
		check_eq(String(l11_rec[0]), "返回主菜单？", "批次V§3.2：正常退出文案逐字「返回主菜单？」（原正文含「主菜单」断言等价替换升格逐字）")
		if (l11_rec[1] as Callable).is_valid():
			(l11_rec[1] as Callable).call()
	check_eq(int(game.current_state()), ST_MAIN_MENU, "正常：确认 → Game 路由 MAIN_MENU")
	instn.queue_free()

	# ---- 12. 输入锁定互斥：成功动画期间退出/锐眼禁用 + 处理器守卫 ----
	_reset_save()
	save.add_talent(1000)
	var instl: Node = await _make_level(1, true)
	var target_l: Array = _target_cells()
	instl.call("set_remaining_for_test", target_l)
	var jb: Button = instl.get_node_or_null("TopBar/Buttons/JoinButton")
	if jb != null:
		jb.pressed.emit()
	check(instl.call("is_input_locked") == true, "锁定互斥前置：对接成功锁定输入")
	var eye_b: Button = instl.get_node_or_null("TopBar/Buttons/EyeButton")
	check(eye_b != null and eye_b.disabled, "锁定互斥：锐眼按钮禁用")
	var ex_b: Button = instl.get_node_or_null("TopBar/Buttons/ExitButton")
	check(ex_b != null and ex_b.disabled, "锁定互斥：TopBar 退出禁用")
	var rl_b: Button = instl.get_node_or_null("ExitReplayButton")
	check(rl_b != null and rl_b.disabled, "锁定互斥：重玩退出禁用")
	eye_b.pressed.emit()  # 信号直发绕过 disabled → 验证处理器守卫
	var menu_l: Variant = instl.get("_eye_menu")   # P4：面板型别 PopupMenu→PanelContainer，Variant 取用留痕
	check(menu_l == null or (menu_l is Control and not bool((menu_l as Control).visible)),
		"锁定互斥：锐眼菜单不弹出（守卫）")
	var l12_before: int = (ssp.call("get_confirm_calls") as Array).size()
	rl_b.pressed.emit()
	check_eq((ssp.call("get_confirm_calls") as Array).size(), l12_before,
		"批次V§3.2：锁定互斥退出确认不弹出（守卫，无新确认条）")
	instl.call("_skip_success_animation")
	await process_frame
	check_eq(int(game.current_state()), ST_SETTLE, "锁定互斥收尾：跳过动画正常结算（不影响既有闭环）")
	instl.queue_free()

	Engine.max_fps = 0
	_cleanup_files()
	game.call("attach_strip", null)   # 批次V§3.2：卸下统一确认条 spy，还原 autoload 挂接态
	ssp.queue_free()
	finish()
