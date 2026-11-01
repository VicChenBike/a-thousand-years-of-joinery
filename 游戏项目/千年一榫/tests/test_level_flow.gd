extends "res://tests/test_base.gd"
## 批次 F 判定用例：对接判定 + 成功动画 + 结算流程 + 主菜单「开始游戏」接线（TDD 先写）。
## 契约来源：批次 F 任务单 + spec（数值以 spec 为准）：
##   判定三分支（spec 5.2）：level_scene.gd 纯静态
##   evaluate_join(remaining, target_shapes, join_voxels) -> String：
##     remaining 与任一 target_shape 集合精确相等（无序、去重）→ "success"；
##     （口径注：N 批起 success 判定已升级为 48 变换等价，见 test_n_join_transform）
##     否则 remaining ∩ join_voxels ≠ ∅ → "unfit"（无法对接：与固定件干涉）；
##     否则 → "wrong"（答案错误）；空 remaining → "wrong"（保证非 success）。
##     元素兼容 Vector3i / "x,y,z" 字符串（_remaining 键为 Vector3i，关卡数据为字符串）。
##   JoinButton（spec 5.2 JUDGE）：success → 锁定输入 + 成功动画（木料缩小→相机拉远→点云聚合，
##     spec 8.4：不可跳过、速度较快、首/重玩都播）→ SETTLE；
##     unfit → 「无法对接」/ wrong → 「答案错误」（K4-2 批次 K 起改右上角 Game.toast，
##     hint_label 回归纯提示；不改模块状态，可继续挖/撤销；文案级断言归 KH-1 spy）。
##   计时/评级/天赋值（spec 8.5，2026-08-27 核对原文）：完美 ≤3 分钟（180s）全额、
##     良好 ≤6 分钟（360s）80%、及格（完成即有，>360s）60%；
##     第 1~5 关完美档天赋值 100/200/400/800/1600（任务单备注「第 1 章基础 60」与 spec 冲突，以 spec 为准）；
##     重玩第 1~3 次仍正常发放、第 4 次起 0（spec 8.5/Q&A14，SaveManager.consume_replay_award）。
##   结算（spec 4.8/5.1）：评分（完美/良好/及格）+ 耗时 mm:ss + 获得天赋值 N；
##     中央文物点云可拖拽旋转；「下一关」：无下一关数据 → MAIN_MENU；重玩 → CATALOG；有 → TALK（关后剧情）。
##   P2 回归（批次 E 审查）：删→撤销→选→重做→删→撤销 后该格材质恢复默认（无高亮残留）。
##   主菜单（spec 5.1 + J3-2 两态 C2）：有存档（非首次）点「载入存档」→ LEVEL（下一未通关章节，断点继续）。
## 环境说明：同既有测试——--script 无头模式 autoload 经 /root/<Name> 动态引用；
## 静态方法经 Script.call()；不直接写全局标识符。

const LS_SCRIPT := "res://scenes/level/level_scene.gd"
const LEVEL_SCENE := "res://scenes/level/level_scene.tscn"
const SETTLE_SCENE := "res://scenes/settle/settle_scene.tscn"
const MENU_SCENE := "res://scenes/menu/main_menu.tscn"
const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"

# Game.State 枚举（与 test_main_menu 一致）：BOOT=0 MAIN_MENU=1 OPENING_MOVIE=2 TALK=3 LEVEL=4 SETTLE=5 CATALOG=6
const ST_MAIN_MENU := 1
const ST_TALK := 3
const ST_LEVEL := 4
const ST_SETTLE := 5
const ST_CATALOG := 6

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
	# 第 1 关 target_shapes[0]（160 格字符串坐标，批次 Z 五件套实况；旧值 78 等价替换留痕），玩家挖到 remaining == target 即成功
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

## 递归查找 PointCloudViewer（J4-2 起结算点云由 viewer 组件提供，路径断言改递归降脆性）
func _find_viewer(node: Node) -> Control:
	if node != null and node.get_script() == load("res://scripts/point_cloud_viewer.gd"):
		return node as Control
	for c: Node in node.get_children():
		var found: Control = _find_viewer(c)
		if found != null:
			return found
	return null

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
const DISC_BK_PREFIX := "user://_r2b_lfl_backup_"
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
	print("EVID|user_restore|lfl|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_level_flow ==")
	_backup_user()
	Engine.max_fps = 60  # 有头外无上限帧率会让逐帧点云聚合 tween 空转，测试限 60fps
	game = get_root().get_node("Game")
	save = get_root().get_node("SaveManager")
	lib = get_root().get_node("LevelLibrary")
	_cleanup_files()
	save.load_game()
	lib.scan_directory("res://levels_data")

	var ls: Script = load(LS_SCRIPT) as Script
	check(ls != null, "level_scene.gd 可加载")
	if ls == null:
		finish()
		return

	# ---- 1. evaluate_join 全分支（纯静态，规格 5.2 集合语义）----
	var ej: bool = ls.has_method("evaluate_join")
	check(ej, "静态接口存在: level_scene.evaluate_join")
	if ej:
		var t: Dictionary = {Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true}
		var tgt: Array = [["0,0,0", "1,0,0"]]
		var jn: Array = ["5,2,7"]
		check_eq(String(ls.call("evaluate_join", t, tgt, jn)), "success",
			"判定：remaining==target（Vector3i 键 vs 字符串 shape）→ success")
		check_eq(String(ls.call("evaluate_join", t, [["1,0,0", "0,0,0"]], jn)), "success",
			"判定：集合顺序无关 → success")
		check_eq(String(ls.call("evaluate_join", t, [["9,9,9"], ["1,0,0", "0,0,0"]], jn)), "success",
			"判定：多解 target_shapes 任一匹配 → success")
		check_eq(String(ls.call("evaluate_join", t, [["0,0,0", "1,0,0", "0,0,0"]], jn)), "success",
			"判定：shape 重复坐标按集合去重 → success")
		check_eq(String(ls.call("evaluate_join", {"0,0,0": true, "1,0,0": true}, tgt, jn)), "success",
			"判定：remaining 字符串键与 Vector3i 键统一比较 → success")
		var jn_vec: Array = [Vector3i(5, 2, 7)]
		check_eq(String(ls.call("evaluate_join", t, tgt, jn_vec)), "success",
			"判定：join_voxels 兼容 Vector3i 元素 → 不干涉")
		check_eq(String(ls.call("evaluate_join", t, tgt, ["0,0,0", "1,0,0"])), "success",
			"判定：成功优先于干涉（P=T 时即便与 join 同格也 success，数据 F=T∪J 下不发生）")
		check_eq(String(ls.call("evaluate_join", {Vector3i(1, 1, 0): true}, tgt, ["1,1,0"]), ), "unfit",
			"判定：remaining∩join≠∅ 且非 target → unfit（无法对接）")
		check_eq(String(ls.call("evaluate_join", {"0,0,0": true}, [["0,0,0", "1,0,0"]], ["0,0,0"]), ), "unfit",
			"判定：不足 target 且与 join 同格 → unfit（优先于 wrong）")
		check_eq(String(ls.call("evaluate_join", {Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true, Vector3i(2, 0, 0): true}, tgt, ["3,3,3"]), ), "wrong",
			"判定：多留一格（不干涉）→ wrong（答案错误）")
		check_eq(String(ls.call("evaluate_join", {Vector3i(0, 0, 0): true}, tgt, ["7,7,7"]), ), "wrong",
			"判定：少挖一格（不干涉）→ wrong")
		check_eq(String(ls.call("evaluate_join", {Vector3i(4, 4, 4): true}, tgt, []), ), "wrong",
			"判定：无交集且非 target → wrong")
		check_eq(String(ls.call("evaluate_join", {}, tgt, []), ), "wrong",
			"判定：空 remaining → wrong（保证非 success）")
		check_eq(String(ls.call("evaluate_join", t, [], []), ), "wrong",
			"判定：无 target 数据时非 success（兜底）")
		check_eq(String(ls.call("evaluate_join", t, [["bad"], ["0,0,0", "1,0,0"]], []), ), "success",
			"判定：非法坐标元素跳过不崩溃（另一 shape 命中）")

	# ---- 1b. N批：48 变换全等价用例（spec §6.1，用户 2026-09-09 拍板 #1：木块不分正反，形状一致即通关）----
	# 绕水平轴翻转（凸凹互换）/ 镜像挖法 → success（旧口径逐坐标精确相等误判 wrong/unfit，行为反转留痕）；
	# 等价但与 join_voxels 在原坐标交叠仍 success（用户实测场景）；非等价仍 wrong；
	# 真实第 1 关 target 整体翻转/镜像亦判 success（负坐标由平移归一承担）。
	var tgt_n: Array = [["0,0,0", "1,0,0", "1,1,0"]]
	var flip_n: Dictionary = {Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true, Vector3i(1, -1, 0): true}
	var mir_n: Dictionary = {Vector3i(0, 0, 0): true, Vector3i(-1, 0, 0): true, Vector3i(-1, 1, 0): true}
	check_eq(String(ls.call("evaluate_join", flip_n, tgt_n, ["7,7,7"])), "success",
		"N批：绕水平轴翻转（凸凹互换）→ success（旧口径误判 wrong，行为反转留痕）")
	check_eq(String(ls.call("evaluate_join", mir_n, tgt_n, ["7,7,7"])), "success",
		"N批：镜像形状 → success（旧口径误判 wrong，行为反转留痕）")
	check_eq(String(ls.call("evaluate_join", flip_n, tgt_n, ["0,0,0", "1,0,0"])), "success",
		"N批：等价优先于干涉——翻转形状与固定件交叠仍 success（用户实测场景）")
	check_eq(String(ls.call("evaluate_join", {Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true, Vector3i(2, 0, 0): true}, tgt_n, ["7,7,7"]), ), "wrong",
		"N批：非等价形状（直线 vs L）仍 wrong")
	var lvl_n: Dictionary = lib.get_level(1)
	if not lvl_n.is_empty():
		var tgt1_n: Array = ((lvl_n["data"] as Dictionary)["pieces"][0] as Dictionary)["target_shapes"][0]
		var flip1: Dictionary = {}
		var mir1: Dictionary = {}
		for s_n: String in tgt1_n:
			var pp: PackedStringArray = s_n.split(",")
			flip1["%s,%d,%s" % [pp[0], -int(pp[1]), pp[2]]] = true  # 绕水平轴（x/z 平面）翻转 y
			mir1["%d,%s,%s" % [-int(pp[0]), pp[1], pp[2]]] = true   # 镜像 x
		check_eq(String(ls.call("evaluate_join", flip1, [tgt1_n], [])), "success",
			"N批：第 1 关目标整体绕水平轴翻转 → success")
		check_eq(String(ls.call("evaluate_join", mir1, [tgt1_n], [])), "success",
			"N批：第 1 关目标整体镜像 → success")

	# ---- 2. 计分纯函数（spec 8.5 数值核对）----
	var has_grade: bool = ls.has_method("grade_for_time") and ls.has_method("talent_for_grade")
	check(has_grade, "静态接口存在: grade_for_time / talent_for_grade")
	if has_grade:
		check_eq(String(ls.call("grade_for_time", 0.0)), "perfect", "评级：0s → perfect")
		check_eq(String(ls.call("grade_for_time", 180.0)), "perfect", "评级：边界 180s → perfect（≤3 分钟）")
		check_eq(String(ls.call("grade_for_time", 180.5)), "good", "评级：>180s → good")
		check_eq(String(ls.call("grade_for_time", 360.0)), "good", "评级：边界 360s → good（≤6 分钟）")
		check_eq(String(ls.call("grade_for_time", 361.0)), "pass", "评级：>360s → pass（完成即有）")
		check_eq(String(ls.call("grade_for_time", 10000.0)), "pass", "评级：超长耗时 → pass")
		check_eq(int(ls.call("talent_for_grade", 1, "perfect")), 100, "天赋值：第1关完美=100（spec 8.5）")
		check_eq(int(ls.call("talent_for_grade", 1, "good")), 80, "天赋值：第1关良好=80（80%）")
		check_eq(int(ls.call("talent_for_grade", 1, "pass")), 60, "天赋值：第1关及格=60（60%）")
		check_eq(int(ls.call("talent_for_grade", 3, "perfect")), 400, "天赋值：第3关完美=400")
		check_eq(int(ls.call("talent_for_grade", 3, "good")), 320, "天赋值：第3关良好=320")
		check_eq(int(ls.call("talent_for_grade", 5, "perfect")), 1600, "天赋值：第5关完美=1600")
		check_eq(int(ls.call("talent_for_grade", 5, "good")), 1280, "天赋值：第5关良好=1280")
		check_eq(int(ls.call("talent_for_grade", 5, "pass")), 960, "天赋值：第5关及格=960")
		check_eq(String(ls.call("grade_name", "perfect")), "完美", "评级名：perfect→完美")
		check_eq(String(ls.call("grade_name", "good")), "良好", "评级名：good→良好")
		check_eq(String(ls.call("grade_name", "pass")), "及格", "评级名：pass→及格")
	var has_fmt: bool = ls.has_method("format_time")
	check(has_fmt, "静态接口存在: format_time")
	if has_fmt:
		check_eq(String(ls.call("format_time", 0.0)), "00:00", "计时：0s → 00:00")
		check_eq(String(ls.call("format_time", 65.0)), "01:05", "计时：65s → 01:05")
		check_eq(String(ls.call("format_time", 3725.0)), "62:05", "计时：3725s → 62:05（mm 不封顶）")

	# ---- 3. P2 回归：删→撤销→选→重做→删→撤销 后无高亮残留 ----
	_reset_save()
	var inst: Node = await _make_level(1)
	if inst != null and (inst.call("get_remaining_voxels") as Array).size() > 0:
		var main_vv: Node = inst.get_node_or_null("MainView/ViewportContainer/SubViewport/VoxelView")
		var n_a: MeshInstance3D = main_vv.call("get_voxel_node", Vector3i(0, 0, 0))
		var n_ref: MeshInstance3D = main_vv.call("get_voxel_node", Vector3i(7, 2, 4))
		check(n_a is MeshInstance3D and n_ref is MeshInstance3D, "P2 前置：目标格与参照格节点存在")
		if n_a != null and n_ref != null:
			var mat_def: Material = n_ref.material_override  # 从未被触碰的默认材质
			inst.call("select_voxel", Vector3i(0, 0, 0), false)
			inst.call("delete_selected")
			check(n_a.material_override != mat_def or not n_a.visible, "P2 前置：删除后 A 移出/隐藏")
			check(inst.call("undo") == true, "P2：撤销恢复 A")
			check(n_a.material_override == mat_def, "P2：撤销后 A 为默认材质")
			inst.call("select_voxel", Vector3i(0, 0, 0), true)  # Ctrl 追加选中（复现选区+高亮）
			check(n_a.material_override != mat_def, "P2 前置：选中 A 高亮")
			check(inst.call("redo") == true, "P2：重做再删 A")
			check_eq((inst.call("get_selected_voxels") as Array).size(), 0,
				"P2 修复(方案B)：重做后 A 移出选区（无幽灵选中）")
			check(n_a.material_override == mat_def, "P2 修复(方案B)：重做后 A 高亮清除")
			check_eq(int(inst.call("delete_selected")), 0, "P2：右键删除空选区安全（0）")
			check(n_a.material_override == mat_def, "P2 修复(方案A)：删除路径无高亮残留")
			check(inst.call("undo") == true, "P2：再撤销恢复 A")
			check(n_a.visible, "P2：最终 A 可见")
			check(n_a.material_override == mat_def, "P2 回归：删→撤销→选→重做→删→撤销 后材质恢复默认（无高亮残留）")
	inst.queue_free()

	# ---- 4. 对接流程：unfit / wrong 反馈 + 成功动画 + SETTLE 路由 + 结算数值 ----
	# K4-2（spec §10.6）：失败提示已迁右上角 Game.toast——本批经 toast_spy 夹具验「转发到达」
	# （计数口径；文案级断言归 KH-1 spy，plan KG-4 TDD 定稿）。
	_reset_save()
	var tspy: Node = (load("res://tests/fixtures/toast_spy.gd") as GDScript).new()
	add_child(tspy)
	game.call("attach_toast", tspy)
	var talent0: int = int(save.get_talent())
	var inst2: Node = await _make_level(1)
	var hint: Label = inst2.get_node_or_null("HintLabel")
	var join_btn: Button = inst2.get_node_or_null("TopBar/Buttons/JoinButton")
	check(hint is Label and join_btn is Button, "对接流程前置：HintLabel/JoinButton 存在")
	var target: Array = _target_cells()
	check(target.size() > 0, "对接流程前置：target_shapes[0] 非空")
	if hint != null and join_btn != null and not target.is_empty():
		# J2-3（批次 J / A4）→ M-E（spec §3.5 拍板 #3/#8）→ U-D（c63260a）三次等价替换留痕：
		# 对接引导句从提示行移出 → M-E 起由 JoinButton.tooltip_text 承载 → 批次 U-D 起原生
		# tooltip 移除（防与 HoverTip 双提示），文案由 HoverTip 组件逐字承接（level_scene
		# U7-3 接入段「对接：按标准答案判定对接」——批次 Z 终审 P2 等价替换：旧「对照成品」
		# →「按标准答案判定对接」，判定基准=target；面板标题左上已随批次 Z Z1 改「最终成品」，
		# 中央窗「木料」标签 N12-3 起删除）。断言跟随终态：原生 tooltip 空 + 源码 HoverTip
		# 接入与文案锁死（源码断言先例=window_k P2-1）。
		var lvl_src_tip: String = FileAccess.get_file_as_string("res://scenes/level/level_scene.gd")
		check(String(join_btn.tooltip_text).is_empty() and lvl_src_tip.contains("hover_tip.gd")
			and lvl_src_tip.contains("对接：按标准答案判定对接"),
			"M-E⑥：对接引导句由 HoverTip 承载（U-D 原生 tooltip 已移除防双提示，等价替换；批次Z终审P2标准答案口径）")
		# 批次 Z 终审 P2（+1 断言，只增不减）：HINT_JOIN_GUIDE 新口径正向锚 + 全源码旧名零残留反向锚
		check(lvl_src_tip.contains("挖出与标准答案一致的形状后对接")
			and not lvl_src_tip.contains("对照成品"),
			"批次Z终审P2：HINT_JOIN_GUIDE=「挖出与标准答案一致的形状后对接」且 level_scene.gd 旧名「对照成品」零残留")
		check(not String(hint.text).contains("挖出与"),
			"M-E⑥：提示行不再承载对接引导句（精简为纯键鼠模板）")
		check_eq(String((inst2.get_node_or_null("TargetView/Title") as Label).text), "最终成品",
			"批次 Z Z1：TargetView 标签改「最终成品」（M-E⑤「对照成品」旧文案等价替换留痕）")
		check_eq(String((inst2.get_node_or_null("JoinView/Title") as Label).text), "对接固定件",
			"M-E⑤：JoinView 标签精简「对接固定件」（等价替换 A4 旧文案）")
		# N12-3（用户 2026-09-10「直接去掉那个文字」）等价替换留痕：中央窗 MainView/Title
		# 「木料」标签删除（旧断言「text==木料」按新口径等价替换为节点不存在断言）。
		check(inst2.get_node_or_null("MainView/Title") == null,
			"N12-3：MainView/Title「木料」标签已删除（节点不存在；M-E⑤ 旧文案断言等价替换）")
		# 4a. unfit：实心木料直接对接 → 与固定件干涉（K4-2：失败走 toast，hint 回归纯提示）
		var ft: Label = inst2.get_node_or_null("FailToast") as Label
		check(ft == null, "K4-2：FailToast 节点不存在（屏幕中上红长文案已删，迁 Game.toast）")
		join_btn.pressed.emit()
		check(not String(hint.text).contains("无法对接"),
			"K4-2：对接失败 hint_label 回归纯提示（不再承载「无法对接」错误长文案）")
		check(hint.modulate == Color.WHITE, "K4-2：失败不再改警示色（红色系随 toast 体系收口）")
		check(hint.get_theme_font_size("font_size") < 24, "K4-2：提示保持常态字号（失败大字号已删）")
		check(String(hint.text).contains("左键划选") and not String(hint.text).contains("剩余体素"),
			"M-E⑥：hint 回归纯键鼠精简模板（剩余计数挪顶栏，等价替换 K4-2 常驻计数断言）")
		var vox_lbl_flow: Label = inst2.get_node_or_null("TopBar/VoxelLabel")
		check(vox_lbl_flow is Label and String(vox_lbl_flow.text).contains("180"),
			"M-E⑥：剩余计数由顶栏 VoxelLabel 承载（180 / 180，批次 Z 实况等价改写）")
		check((tspy.call("get_calls") as Array).size() >= 1,
			"K4-2：unfit 失败经 Game.toast 转发至 ToastCenter（spy 计数）")
		check_eq(int(game.current_state()), 0, "对接·unfit 不路由（状态机仍 BOOT 占位，未进 SETTLE）")
		check_eq((inst2.call("get_remaining_voxels") as Array).size(), 180,
			"对接·unfit 不改模块状态（剩余仍 180，可继续挖；批次 Z 实况等价改写）")
		check(inst2.call("is_input_locked") == false, "对接·unfit 后未锁定输入")
		# 4b. wrong：挖到 target 差一格（无干涉）→ 答案错误（K4-2：toast 口径，连续点对接→堆叠多条）
		var wrong_set: Array = target.slice(1)
		inst2.call("set_remaining_for_test", wrong_set)
		var spy_n: int = (tspy.call("get_calls") as Array).size()
		join_btn.pressed.emit()
		check(not String(hint.text).contains("答案错误"),
			"K4-2：wrong 失败 hint_label 不再承载「答案错误」长文案")
		check((tspy.call("get_calls") as Array).size() == spy_n + 1,
			"K4-2：wrong 失败再 push 一条 toast（堆叠语义）")
		check_eq(int(game.current_state()), 0, "对接·wrong 不路由")
		check_eq((inst2.call("get_remaining_voxels") as Array).size(), wrong_set.size(),
			"对接·wrong 后可继续挖（剩余集未被改动）")
		# 4c. 成功：挖到 == target → 动画 → SETTLE（anim_time_scale 加速，测试可达）
		# M-Gb（spec §3.7 行为 4）→ N4（spec §6.6）→ O批（2026-09-10 用户口径③凝聚持续 0.5s 后
		# 平衡）等价替换留痕：成功动画四段式（凝聚 0.25+持续 0.5+散开 0.5+聚合 1.3+回看 1.0=3.55s，
		# 仍满足 spec 8.4 [2.5,4]s）；散开目标=屏外环域、聚合=结算挂载位、三通道+建模全金（O批③④⑤）。
		var lscm_f: Dictionary = (load(LS_SCRIPT) as Script).get_script_constant_map()
		var anim_sum: float = float(lscm_f.get("ANIM_CONDENSE", -1.0)) \
			+ float(lscm_f.get("ANIM_HOLD", -1.0)) + float(lscm_f.get("ANIM_SPREAD", -1.0)) \
			+ float(lscm_f.get("ANIM_AGGREGATE", -1.0)) + float(lscm_f.get("ANIM_REVIEW", -1.0))
		check(absf(anim_sum - 3.95) < 0.001,
			"P批波2等价替换（2026-09-10 用户口径 P-C 散开放慢+滞空）：四段式时长和≈3.95s ∈[2.5,4.0]（O批 3.55s 口径随散开放慢 0.5→1.2 重排废止留痕）")
		inst2.set("anim_time_scale", 8.0)
		inst2.call("set_remaining_for_test", target)
		check_eq(int(inst2.call("get_undo_depth")), 0, "测试钩子 set_remaining_for_test：不动撤销栈")
		join_btn.pressed.emit()
		check(inst2.call("is_input_locked") == true, "对接·成功即锁定输入（防连点）")
		# K4-2：成功路径——FailToast 组件已整体删除；提示保持纯提示常态
		check(ft == null, "K4-2：成功路径 FailToast 同样不存在（组件已删）")
		check(hint.get_theme_font_size("font_size") < 24, "成功路径提示字号保持常态")
		await process_frame
		check(inst2.get_node_or_null("SuccessOverlay") != null, "成功动画：全屏覆盖层存在（M-Gb 起立即建立，点云聚合段）")
		var cloud: Node = inst2.get_node_or_null("SuccessOverlay/AnimContainer/AnimViewport/AnimWorld/SpinPivot/SuccessCloud")
		check(cloud is MultiMeshInstance3D, "成功动画：MultiMesh 点云实例存在（M-Gb 起挂独立 SpinPivot 下，坑 9）")
		if cloud is MultiMeshInstance3D:
			check(int((cloud as MultiMeshInstance3D).multimesh.instance_count) > 1000,
				"成功动画：点云已加载真实数据（instance_count=%d）" % int((cloud as MultiMeshInstance3D).multimesh.instance_count))
		await create_timer(0.6).timeout  # 总时长≈(0.25+0.5+1.2+1.1+0.9)/8≈0.49s 后自然完成（P批波2 时长档）
		check_eq(int(game.current_state()), ST_SETTLE, "成功动画完 → 结算（P批波2 mark_settle_entered 记账 SETTLE 态）")
		check(game.get_current_scene() == null or game.get_current_scene() == inst2,
			"P批波2：主路径零切换（结算 UI 就地淡入，未发生 _load_main_scene 场景重建——本测试 level 为直启实例，get_current_scene 保持路由前状态）")
		# P批波2等价替换：结算数据面从 Game.goto_state(SETTLE) ctx 改为 level._settle_data
		# （主路径不再切场景，Game._context 保持 level 进场 ctx）
		var sdata: Dictionary = inst2.get("_settle_data")
		check_eq(int(sdata.get("chapter", -1)), 1, "结算数据 chapter==1")
		check_eq(String(sdata.get("grade", "")), "完美", "结算数据 grade==完美（耗时极短）")
		check_eq(int(sdata.get("score", -1)), 100, "结算数据 score==100（第1关完美，spec 8.5）")
		check_eq(int(sdata.get("talent", -1)), 100, "结算数据 talent==100")
		check(bool(sdata.get("replay", true)) == false, "结算数据 replay==false（首通）")
		var settle_ui_flow: Control = inst2.get_node_or_null("SuccessOverlay/SettleUI")
		check(settle_ui_flow != null and settle_ui_flow.visible, "P批波2：结算 UI 在覆盖层内显现（评级/耗时/天赋值/下一关/退出）")
		check_eq(int(save.get_talent()), talent0 + 100, "天赋值发放：余额 +100（前后差，spec 8.5）")
		var prog: Dictionary = save.get_progress()
		check((prog["cleared"] as Array).has(1), "进度：cleared 已含第 1 关")
		check_eq(int(prog["next_chapter"]), 2, "进度：next_chapter 推进到 2")
		check(FileAccess.file_exists(SAVE_PATH), "结算后存档落盘（SaveManager 自动保存）")
		# 提示复位：动画期间提示不再停留在失败文案
		check(not String(hint.text).contains("答案错误") and not String(hint.text).contains("无法对接"),
			"成功路径不再显示失败提示")
	inst2.queue_free()

	# ---- 5. 成功动画测试钩子 _skip_success_animation（无头测试可达性）----
	_reset_save()
	var talent1: int = int(save.get_talent())
	var inst3: Node = await _make_level(1)
	var jb3: Button = inst3.get_node_or_null("TopBar/Buttons/JoinButton")
	if jb3 != null and not target.is_empty():
		inst3.call("set_remaining_for_test", target)
		jb3.pressed.emit()
		check(inst3.call("is_input_locked") == true, "skip 钩子前置：已锁定")
		inst3.call("_skip_success_animation")
		await process_frame
		check_eq(int(game.current_state()), ST_SETTLE, "测试钩子 _skip_success_animation：直达结算（P批波2 记账 SETTLE 态）")
		check_eq(int(save.get_talent()), talent1 + 100, "skip 路径天赋值照常发放（首通）")
		# P批波2等价替换：结算数据面从 Game ctx 改为 level._settle_data（skip 直达结算 UI 不切场景）
		check_eq(int((inst3.get("_settle_data") as Dictionary).get("score", -1)), 100,
			"skip 路径结算数据 score==100")
	inst3.queue_free()

	# ---- 6. 重玩发奖口径（spec 8.5/Q&A14）：该关重玩第 4 次起不再发放 ----
	for i: int in 3:
		save.consume_replay_award(1)  # 重玩计数 → 3（前 3 次重玩可发）
	var talent2: int = int(save.get_talent())
	var inst4: Node = await _make_level(1)
	var jb4: Button = inst4.get_node_or_null("TopBar/Buttons/JoinButton")
	if jb4 != null and not target.is_empty():
		inst4.call("set_remaining_for_test", target)
		jb4.pressed.emit()
		inst4.call("_skip_success_animation")
		await process_frame
		check_eq(int(game.current_state()), ST_SETTLE, "重玩第 4 次：仍正常进入结算")
		check_eq(int(save.get_talent()), talent2, "重玩第 4 次：天赋值不再发放（前后差 0）")
		# P批波2等价替换：结算数据面从 Game ctx 改为 level._settle_data
		var sdata4: Dictionary = inst4.get("_settle_data")
		check_eq(int(sdata4.get("score", -1)), 0, "重玩第 4 次：结算获得天赋值显示 0")
		check(bool(sdata4.get("replay", false)) == true, "重玩结算数据 replay==true")
		check_eq(int(save.get_progress()["next_chapter"]), 2, "重玩不回退进度（next_chapter 仍 2）")
	inst4.queue_free()

	# ---- 7. 结算场景：评级/耗时/天赋值显示 + 点云可旋转 + 下一关分流 ----
	var settle: Node = (load(SETTLE_SCENE) as PackedScene).instantiate()
	settle.call("set_context", {"chapter": 1, "grade": "完美", "score": 100, "elapsed": 125.0, "talent": 100})
	add_child(settle)
	await process_frame
	var s_label: Label = settle.get_node_or_null("ScoreLabel")
	var e_label: Label = settle.get_node_or_null("ElapsedLabel")
	var t_label: Label = settle.get_node_or_null("TalentLabel")
	check(s_label is Label and String(s_label.text) == "评分：完美", "结算显示「评分：完美」")
	check(e_label is Label and String(e_label.text) == "耗时：02:05", "结算显示「耗时：02:05」")
	check(t_label is Label and String(t_label.text) == "获得天赋值：100", "结算显示「获得天赋值：100」")
	# J4-2（F2）：结算点云改由 PointCloudViewer 提供（旧内联 _gui_input 绕 Y 拖拽已删）。
	# 行为语义不丢：点云存在+已加载数据+可旋转（viewer.rotate_by 替代旧事件直驱），另补可缩放。
	var sviewer: Control = _find_viewer(settle.get_node_or_null("CenterMount"))
	check(sviewer != null, "结算中央：文物点云经 PointCloudViewer 挂载（spec 4.8/J4-2）")
	if sviewer != null:
		check(int(sviewer.call("get_instance_count")) > 1000, "结算点云已加载该关文物数据")
		var rot0: float = float(sviewer.get("rot_y_deg"))
		sviewer.call("rotate_by", 20.0, 0.0)
		check(absf(float(sviewer.get("rot_y_deg")) - (rot0 + 20.0)) < 0.001, "结算点云可旋转（viewer.rotate_by）")
		var dist0: float = float(sviewer.get("_distance"))
		sviewer.call("zoom_by", 1.2)
		check(float(sviewer.get("_distance")) < dist0, "结算点云可缩放（viewer.zoom_by 拉近）")
	settle.queue_free()

	# 「下一关」分流（批次 Y Y-C1 数据入库等价改写）：chapter=1 有第 2 关数据 → TALK（关后剧情，
	# 用户 2026-09-23 拍板挂载点对齐：通关第 N 关 → 播第 N+1 关对话 → 进第 N+1 关）；
	# 「无下一关数据 → MAIN_MENU」分支改由 chapter=5 代理（get_level(6) 恒空，test_p_settle 同口径）。
	var settle2: Node = (load(SETTLE_SCENE) as PackedScene).instantiate()
	settle2.call("set_context", {"chapter": 1, "grade": "良好", "score": 80, "elapsed": 200.0, "talent": 80})
	add_child(settle2)
	await process_frame
	var nb: Button = settle2.get_node_or_null("NextButton")
	check(nb is Button, "结算「下一关」按钮存在")
	if nb != null:
		nb.pressed.emit()
		await process_frame
		check_eq(int(game.current_state()), ST_TALK, "「下一关」：第 2 关数据已在库（Y-C1）→ TALK 关后剧情")
	settle2.queue_free()
	# 无下一关数据代理章=5：MAIN_MENU（终点分支保持）
	var settle2b: Node = (load(SETTLE_SCENE) as PackedScene).instantiate()
	settle2b.call("set_context", {"chapter": 5, "grade": "良好", "score": 80, "elapsed": 200.0, "talent": 80})
	add_child(settle2b)
	await process_frame
	var nb2b: Button = settle2b.get_node_or_null("NextButton")
	if nb2b != null:
		nb2b.pressed.emit()
		await process_frame
		check_eq(int(game.current_state()), ST_MAIN_MENU, "「下一关」：无下一关数据（chapter=5 代理，get_level(6) 恒空）→ MAIN_MENU")
	settle2b.queue_free()
	await process_frame
	# 重玩结算 → CATALOG（spec 5.1）
	var settle3: Node = (load(SETTLE_SCENE) as PackedScene).instantiate()
	settle3.call("set_context", {"chapter": 1, "grade": "及格", "score": 0, "elapsed": 400.0, "talent": 0, "replay": true})
	add_child(settle3)
	await process_frame
	var nb3: Button = settle3.get_node_or_null("NextButton")
	if nb3 != null:
		nb3.pressed.emit()
		await process_frame
		check_eq(int(game.current_state()), ST_CATALOG, "重玩结算「下一关」→ CATALOG（spec 5.1）")
	settle3.queue_free()

	# ---- 8. 主菜单两态（J3-2/C2）：有档点「载入存档」=断点继续 → LEVEL（键鼠闭环入口）----
	save.mark_first_launch()  # 非首次（有存档标记）
	check_eq(int(save.get_progress()["next_chapter"]), 2, "主菜单前置：next_chapter==2（第 4~6 步推进后）")
	var container: Control = Control.new()
	add_child(container)
	var menu: Node = (load(MENU_SCENE) as PackedScene).instantiate()
	container.add_child(menu)
	await process_frame
	# L-B 路径同步（计划外最小修复，主会话审查项）：VBox 已删三钮直挂 LeftPanel（spec §6.2）；
	# 不改断言语义——旧路径返回 null 会令 :369 空引用中断 _initialize → --script 进程挂死。
	var start_btn: Button = menu.get_node_or_null("LeftPanel/StartButton")
	var load_btn: Button = menu.get_node_or_null("LeftPanel/LoadButton")
	check(start_btn is Button and load_btn is Button, "主菜单前置：StartButton/LoadButton 存在")
	check_eq(String(start_btn.text), "新游戏", "C2：闭环主菜单有档态 StartButton 文本=新游戏（无「开始游戏」）")
	load_btn.pressed.emit()
	check_eq(int(game.current_state()), ST_LEVEL, "有存档点载入存档 → LEVEL（键鼠闭环入口，C2 断点继续由 LoadButton 承接）")
	check_eq(int(game.context().get("chapter", -1)), 2, "入口 chapter==存档下一未通关章节（2）")
	check(bool(game.is_replay()) == false, "入口 replay==false（断点继续）")
	menu.queue_free()
	container.queue_free()

	Engine.max_fps = 0
	_cleanup_files()
	finish()
