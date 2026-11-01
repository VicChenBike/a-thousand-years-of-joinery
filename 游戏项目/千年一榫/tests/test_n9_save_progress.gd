extends "res://tests/test_base.gd"
## 批次 N9（spec §6.11）：存档系统 v2——通关断点 + 挖除进度持久化。TDD 先写（红）。
## 契约来源：spec §6.11 + 用户 2026-09-09 实测反馈（关内退出进度丢；挖除进度不持久化）。
##   1) schema v2：save_version 1→2；v1 旧档 load_game 无损迁移（缺字段补默认值，
##      skins.preferred 迁移先例 / N10 watched_opening 先例；迁移留痕注释）。
##   2) 挖除差集字段：progress.level_progress = {"<chapter>": {"deleted_cells": ["x,y,z",...]}}；
##      deleted_cells = 初始 blocks − 当前 _remaining（只存删了哪些格）；没动 = 空数组/键缺省
##      （天然满足「没动记没改」，未动关卡存档无新增数据）；API：
##      set_level_progress(chapter, deleted) / get_level_progress(chapter)，变更自动保存
##      （既有「变更即存」惯例），幂等省写（内容未变不重复落盘）。
##   3) 写档检查点：level_scene 退出确认路径（_on_exit_confirmed）与 _exit_tree（兜底）先写
##      挖除断点再路由；_goto_settle 记账链路不动（advance_progress 照旧）+ 通关清该章断点
##      （通关即整章完成，挖除断点作废）；_settled 守卫防 _exit_tree 把通关态重写成断点。
##   4) 重放恢复：进关 _build_views 后该章存有非空 deleted_cells → 经既有删除管线
##      （select_voxel→delete_selected）逐格重放；撤销栈红线定稿：重放后 _undo_stack/_redo_stack
##      清空（存档断点即进关基线，撤销历史不跨会话；基线以下回退无入口即无矛盾）。
##      主菜单「载入存档」/图鉴 replay 进关同走 level_scene._ready 重放路径（入口无关）。
## 环境说明：--script 无头模式 autoload 经 /root/<Name> 动态引用；SaveManager 文件/迁移用例
##   经独立实例（test_save_manager 先例）+ 手写 user:// JSON；关卡用例实树实例化（_ready 生效）。

const LS_SCRIPT := "res://scenes/level/level_scene.gd"
const LEVEL_SCENE := "res://scenes/level/level_scene.tscn"
const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const SM_SCRIPT := "res://autoload/save_manager.gd"
# 第 1 关实构建格（批次 Z 五件套 12×3×5 实况：0,0,0 可删、7,2,4 存在——旧 z=7 越界等价替换留痕）
const CELL_A := Vector3i(0, 0, 0)
const CELL_B := Vector3i(7, 2, 4)
const CELL_C := Vector3i(3, 1, 4)
const ST_MAIN_MENU := 1
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

func _new_sm(name: String) -> Node:
	var sm: Node = (load(SM_SCRIPT) as GDScript).new()
	sm.name = name
	get_root().add_child(sm)
	sm.load_game()
	return sm

func _make_level(ch: int, replay: bool = false) -> Node:
	var inst: Node = (load(LEVEL_SCENE) as PackedScene).instantiate()
	inst.call("set_context", {"chapter": ch, "replay": replay})
	add_child(inst)
	await process_frame
	return inst

func _read_save_json() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return v if v is Dictionary else {}

func _sorted_remaining(inst: Node) -> Array:
	var arr: Array = (inst.call("get_remaining_voxels") as Array).duplicate()
	arr.sort()
	return arr

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
const DISC_BK_PREFIX := "user://_r2b_n9_backup_"
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
	print("EVID|user_restore|n9|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_n9_save_progress ==")
	_backup_user()
	Engine.max_fps = 60
	game = get_root().get_node("Game")
	save = get_root().get_node("SaveManager")
	lib = get_root().get_node("LevelLibrary")
	_cleanup_files()
	save.load_game()
	lib.scan_directory("res://levels_data")

	# ================= A. schema v2 / 迁移 / level_progress API（独立实例 + 文件） =================
	_cleanup_files()
	var sm: Node = _new_sm("SM_N9_A")
	var smc: Script = load(SM_SCRIPT)
	check_eq(int(smc.get_script_constant_map().get("SAVE_VERSION", -1)), 2,
		"N9-A1：SAVE_VERSION 常量=2（schema v2）")
	# 红灯防挂死（test_main_menu 先例）：核心 API 未实现时记失败并提前收口，不触发未定义方法调用
	if not (sm.has_method("set_level_progress") and sm.has_method("get_level_progress")):
		check(false, "N9-A0：SaveManager level_progress API 存在（set/get）")
		print("N9 RED：SaveManager API 未实现——提前收口（防挂死）")
		Engine.max_fps = 0
		finish()
		return
	check(true, "N9-A0：SaveManager level_progress API 存在（set/get）")
	var prog: Dictionary = sm.get_progress()
	check(prog.get("level_progress", null) is Dictionary and (prog["level_progress"] as Dictionary).is_empty(),
		"N9-A2：默认档 progress.level_progress 存在且为空（未动=无记录）")
	check_eq((sm.call("get_level_progress", 1) as Array), [], "N9-A3：get_level_progress 缺省=空数组（没改）")

	sm.call("set_level_progress", 1, ["7,2,7", "0,0,0"])
	check_eq((sm.call("get_level_progress", 1) as Array), ["0,0,0", "7,2,7"],
		"N9-A4：set/get roundtrip（自动排序归一）")
	check(FileAccess.file_exists(SAVE_PATH), "N9-A5：set_level_progress 变更即存（自动落盘）")
	var on_disk: Dictionary = _read_save_json()
	var lp_disk: Dictionary = (on_disk.get("progress", {}) as Dictionary).get("level_progress", {})
	check_eq(int(on_disk.get("save_version", -1)), 2, "N9-A6：落盘文件 save_version=2")
	check_eq(((lp_disk.get("1", {}) as Dictionary).get("deleted_cells", []) as Array), ["0,0,0", "7,2,7"],
		"N9-A7：落盘 JSON 含 level_progress[1].deleted_cells（差集字段）")

	sm.call("set_level_progress", 1, ["1,0,0", "0,0,0", "1,0,0", "bad", "1,2"])
	check_eq((sm.call("get_level_progress", 1) as Array), ["0,0,0", "1,0,0"],
		"N9-A8：写入归一——去重/排序/非法项丢弃（bad、两段坐标）")

	sm.call("set_level_progress", 2, [])
	check_eq((sm.call("get_level_progress", 2) as Array), [], "N9-A9：set(chapter,空)=清断点（没改语义）")
	check(not ((sm.get_progress()["level_progress"] as Dictionary).has("2")),
		"N9-A10：空断点删键不占存储（键缺省=没动）")

	_cleanup_files()
	var sm2: Node = _new_sm("SM_N9_B")
	sm2.call("set_level_progress", 1, ["0,0,0"])
	check(FileAccess.file_exists(SAVE_PATH), "N9-A11 前置：断点已落盘")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	sm2.call("set_level_progress", 1, ["0,0,0"])
	check(not FileAccess.file_exists(SAVE_PATH), "N9-A11：幂等省写——断点内容未变不重复落盘")

	_cleanup_files()
	var sm3: Node = _new_sm("SM_N9_C")
	sm3.call("set_level_progress", 3, [])
	check(not FileAccess.file_exists(SAVE_PATH), "N9-A12：未动关卡（空断点且本无键）零落盘（存档无新增数据）")

	# v1→v2 无损迁移（K-D legacy 先例结构 + 手工构造）
	_cleanup_files()
	var legacy: Dictionary = {
		"save_version": 1,
		"progress": {"cleared": [1, 2], "next_chapter": 3},
		"settings": {"gesture_input": true, "kb_input": true, "gesture_hud_visible": true,
			"gesture_hud_offset": [0, 0], "volume": {"master": 1.0, "music": 1.0, "sfx": 1.0}, "udp_port": 0},
		"talent": 777,
		"skins": {"owned": ["skin_default", "skin_07"], "equipped": "skin_07"},
		"replay_award_counts": {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0},
	}
	var lf: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	lf.store_string(JSON.stringify(legacy))
	lf.close()
	var sm4: Node = _new_sm("SM_N9_D")
	check_eq((sm4.get_progress()["cleared"] as Array), [1, 2], "N9-A13：v1 迁移——cleared 无损保留")
	check_eq(int(sm4.get_progress()["next_chapter"]), 3, "N9-A14：v1 迁移——next_chapter 无损保留")
	check_eq(sm4.get_talent(), 777, "N9-A15：v1 迁移——talent 无损保留")
	check_eq(sm4.get_skins()["equipped"], "skin_07", "N9-A16：v1 迁移——skins 无损保留（K-D 先例迁移不回归）")
	check_eq((sm4.get_progress()["level_progress"] as Dictionary), {},
		"N9-A17：v1 迁移——level_progress 缺字段补默认 {}（无损迁移留痕）")
	sm4.save_game()
	var sm5: Node = _new_sm("SM_N9_E")
	check_eq((sm5.get_progress()["cleared"] as Array), [1, 2], "N9-A18：迁移后落盘→重读无损（v1 档升级 v2 roundtrip）")

	var v2_nolp: Dictionary = _read_save_json()
	(v2_nolp["progress"] as Dictionary).erase("level_progress")
	var vf: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	vf.store_string(JSON.stringify(v2_nolp))
	vf.close()
	var sm6: Node = _new_sm("SM_N9_F")
	check((sm6.get_progress().get("level_progress", null) is Dictionary),
		"N9-A19：v2 档缺 level_progress 字段 → 防御性补默认（load 归一）")

	sm6.call("set_level_progress", 1, ["0,0,0"])
	sm6.call("set_level_progress", 2, ["1,0,0"])
	sm6.reset_for_new_game()
	check_eq((sm6.call("get_level_progress", 1) as Array), [], "N9-A20：reset_for_new_game 清除断点（章 1）")
	check_eq((sm6.call("get_level_progress", 2) as Array), [], "N9-A21：reset_for_new_game 清除断点（章 2）")
	check_eq(sm6.get_progress()["level_progress"], {}, "N9-A22：reset_for_new_game 后 level_progress 回空（新字段同步清理）")

	sm6.call("set_level_progress", 1, ["0,0,0"])
	sm6.advance_progress(2)
	check_eq((sm6.call("get_level_progress", 1) as Array), ["0,0,0"],
		"N9-A23：advance_progress（记账链路）不动他章断点（清账只由通关路径显式触发）")

	# —— 审查 B P3-1：非数字坐标防御（解析失败丢弃而非 int() 静默改写；章键同理） ——
	# 游戏自身写盘恒为合法串，仅手写档可触发；行为对齐 _normalize_deleted_cells 注释「非法项丢弃」。
	_cleanup_files()
	var sm7: Node = _new_sm("SM_N9_G")
	sm7.call("set_level_progress", 1, ["0,0,0", "1,a,3", "abc", "1,,3", ""])
	check_eq((sm7.call("get_level_progress", 1) as Array), ["0,0,0"],
		"N9-A24：非数字段（1,a,3）/空段（1,,3）/非数字项（abc）/空串项丢弃——不静默 int() 成 1,0,3")
	sm7.call("set_level_progress", 2, [Vector3i(3, 1, 4), "7,2,7"])
	check_eq((sm7.call("get_level_progress", 2) as Array), ["3,1,4", "7,2,7"],
		"N9-A25：合法串/Vector3i 不受防御影响（归一 roundtrip 照旧）")
	sm7.call("set_level_progress", 3, ["99999999999999999999,0,0"])
	check_eq((sm7.call("get_level_progress", 3) as Array), [],
		"N9-A26：int64 越界段丢弃（溢出饱和=静默改写数值，与非法同责）")

	# 手写档章键防御：level_progress 键 "abc"/"" 经 str(int()) 会静默伪造成 "0" 键 → 须整体丢弃
	_cleanup_files()
	var v2_badkey: Dictionary = {
		"save_version": 2,
		"progress": {"cleared": [], "next_chapter": 1, "watched_opening": false,
			"level_progress": {"abc": {"deleted_cells": ["0,0,0"]},
				"": {"deleted_cells": ["1,0,0"]}, "1": {"deleted_cells": ["7,2,7"]}}},
		"settings": {"gesture_input": true, "kb_input": true, "gesture_hud_visible": true,
			"gesture_hud_offset": [0, 0], "volume": {"master": 1.0, "music": 1.0, "sfx": 1.0}, "udp_port": 0},
		"talent": 500,
		"skins": {"owned": ["skin_default"], "equipped": "skin_default", "preferred": "skin_default"},
		"replay_award_counts": {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0},
	}
	var bf: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	bf.store_string(JSON.stringify(v2_badkey))
	bf.close()
	var sm8: Node = _new_sm("SM_N9_H")
	var lp8: Dictionary = sm8.get_progress()["level_progress"]
	check(not (lp8.has("abc") or lp8.has("") or lp8.has("0")),
		"N9-A27：手写档非整数章键（abc/空串）整体丢弃——不静默 str(int()) 伪造 \"0\" 键")
	check_eq((lp8.get("1", {}) as Dictionary).get("deleted_cells", []), ["7,2,7"],
		"N9-A28：手写档合法章键照旧保留（无损迁移不受防御影响）")

	# ================= B. level_scene 差集导出（autoload SaveManager + 实关卡） =================
	_reset_save()
	var inst: Node = await _make_level(1)
	check(inst.call("has_method", "_export_deleted_cells"), "N9-B1：level_scene 具备差集导出钩子")
	if inst.call("has_method", "_export_deleted_cells"):
		check_eq((inst.call("_export_deleted_cells") as Array), [], "N9-B2：未动导出=空数组（没改）")
		var rem0: int = (inst.call("get_remaining_voxels") as Array).size()
		inst.call("select_voxel", CELL_A, true)
		check_eq(int(inst.call("delete_selected")), 1, "N9-B3 前置：删格 A")
		inst.call("select_voxel", CELL_B, true)
		inst.call("delete_selected")
		var exp2: Array = (inst.call("_export_deleted_cells") as Array)
		check_eq(exp2, ["0,0,0", "7,2,4"], "N9-B3：删 2 格导出=差集（blocks−remaining，排序字符串）")
		check_eq((inst.call("get_remaining_voxels") as Array).size(), rem0 - 2, "N9-B3 前置：剩余数同步 −2")
		# 重复删除：已删格再选再删幂等，导出不变不重复
		inst.call("select_voxel", CELL_A, true)
		check_eq(int(inst.call("delete_selected")), 0, "N9-B4 前置：对已删格重复删除=0（幂等）")
		check_eq((inst.call("_export_deleted_cells") as Array), ["0,0,0", "7,2,4"],
			"N9-B4：重复删除不产生重复条目（差集语义）")
		# 撤销后导出：挖了又全撤销 = 没改
		check(inst.call("undo") == true, "N9-B5 前置：撤销恢复 B")
		check_eq((inst.call("_export_deleted_cells") as Array), ["0,0,0"], "N9-B5：撤销后导出只剩未恢复格")
		check(inst.call("undo") == true, "N9-B6 前置：撤销恢复 A")
		check_eq((inst.call("_export_deleted_cells") as Array), [], "N9-B6：全撤销后导出=空（挖了又全撤销=没改）")
		# 撤销一半：导出=剩余被删格
		inst.call("select_voxel", CELL_C, true)
		inst.call("delete_selected")
		inst.call("select_voxel", CELL_A, true)
		inst.call("delete_selected")
		check_eq((inst.call("_export_deleted_cells") as Array), ["0,0,0", "3,1,4"],
			"N9-B7：部分撤销后导出=当前真实差集")
	inst.queue_free()
	await process_frame

	# ================= C. 退出写档检查点（确认路径 + _exit_tree 兜底） =================
	_reset_save()
	var inst2: Node = await _make_level(1)
	inst2.call("select_voxel", CELL_A, true)
	inst2.call("delete_selected")
	inst2.call("select_voxel", CELL_B, true)
	inst2.call("delete_selected")
	inst2.call("_ask_exit", ST_MAIN_MENU, "测试退出")
	inst2.call("_on_exit_confirmed")
	await process_frame
	check_eq(int(game.current_state()), ST_MAIN_MENU, "N9-C1 前置：退出确认路由 MAIN_MENU（路由语义不变）")
	check_eq((save.call("get_level_progress", 1) as Array), ["0,0,0", "7,2,4"],
		"N9-C1：退出确认路径先写挖除断点（_on_exit_confirmed 检查点）")
	var c_disk: Dictionary = _read_save_json()
	check_eq((((c_disk.get("progress", {}) as Dictionary).get("level_progress", {}) as Dictionary)
		.get("1", {}) as Dictionary).get("deleted_cells", []), ["0,0,0", "7,2,4"],
		"N9-C2：检查点已落盘到 user://save.json")
	inst2.queue_free()
	await process_frame

	_reset_save()
	var inst3: Node = await _make_level(1)
	inst3.call("select_voxel", CELL_C, true)
	inst3.call("delete_selected")
	inst3.queue_free()  # 不经退出确认 → _exit_tree 兜底写档
	await process_frame
	check_eq((save.call("get_level_progress", 1) as Array), ["3,1,4"],
		"N9-C3：_exit_tree 兜底检查点（防直接切场景丢档）")

	# ================= D. 通关清断点（_goto_settle 记账链路不动 + 清账） =================
	_reset_save()
	save.call("set_level_progress", 1, ["0,0,0"])  # 预置旧断点（模拟上会话遗留）
	var inst4: Node = await _make_level(1)
	var target: Array = ((lib.get_level(1)["data"] as Dictionary)["pieces"][0] as Dictionary)["target_shapes"][0]
	inst4.call("set_remaining_for_test", target)
	var jb: Button = inst4.get_node_or_null("TopBar/Buttons/JoinButton")
	check(jb is Button, "N9-D 前置：JoinButton 存在")
	if jb != null:
		jb.pressed.emit()
		inst4.call("_skip_success_animation")
		await process_frame
		check_eq(int(game.current_state()), ST_SETTLE, "N9-D1 前置：通关路由 SETTLE（结算路由不变）")
		check((save.get_progress()["cleared"] as Array).has(1), "N9-D1：advance_progress 照旧推进（cleared 含第 1 关）")
		check_eq((save.call("get_level_progress", 1) as Array), [],
			"N9-D2：通关清该章断点（挖除进度已无意义，通关=整章完成）")
	inst4.queue_free()
	await process_frame
	check_eq((save.call("get_level_progress", 1) as Array), [],
		"N9-D3：_settled 守卫——结算后场景释放不把通关态重写成断点")

	# ================= E. 重放恢复 + 撤销栈红线 =================
	_reset_save()
	save.call("set_level_progress", 1, ["0,0,0", "7,2,4"])
	var inst5: Node = await _make_level(1)  # 主菜单「载入存档」普通进关（无 replay 键）
	var rem_all: Array = _sorted_remaining(inst5)
	var init_cnt: int = rem_all.size()
	check(not rem_all.has(CELL_A) and not rem_all.has(CELL_B),
		"N9-E1：进关重放——存档断点格移出剩余集（remaining=blocks−deleted_cells）")
	check_eq((inst5.call("get_remaining_voxels") as Array).size(), init_cnt, "N9-E1 前置：计数口径自洽")
	var main_vv: Node = inst5.get_node_or_null("MainView/ViewportContainer/SubViewport/VoxelView")
	check(main_vv != null, "N9-E2 前置：MainView VoxelView 存在")
	if main_vv != null:
		var na: MeshInstance3D = main_vv.call("get_voxel_node", CELL_A)
		var nb: MeshInstance3D = main_vv.call("get_voxel_node", CELL_B)
		check(na is MeshInstance3D and not na.visible, "N9-E2：重放经渲染管线——断点格 A 已隐藏")
		check(nb is MeshInstance3D and not nb.visible, "N9-E2：重放经渲染管线——断点格 B 已隐藏")
	check_eq(int(inst5.call("get_undo_depth")), 0, "N9-E3：重放后撤销栈为空（红线定稿：基线=存档态）")
	check(inst5.call("undo") == false, "N9-E4：红线——重放后立即撤销被拒（不得回退到与存档矛盾态）")
	# 重放基线上再挖新格：撤销只回到基线，不越过基线
	inst5.call("select_voxel", CELL_C, true)
	check_eq(int(inst5.call("delete_selected")), 1, "N9-E5 前置：重放会话内再删新格 C")
	check(inst5.call("undo") == true, "N9-E5 前置：会话内操作可撤销")
	check_eq(_sorted_remaining(inst5).has(CELL_C), true, "N9-E5：撤销恢复新格 C")
	check(not _sorted_remaining(inst5).has(CELL_A), "N9-E6：撤销不越过重放基线（断点格 A 仍处删除态=与存档一致）")
	# 重放会话退出 → 断点滚动更新（重放 2 格 + 本会话净变化）
	inst5.call("select_voxel", CELL_C, true)
	inst5.call("delete_selected")
	inst5.queue_free()  # _exit_tree 兜底写档
	await process_frame
	check_eq((save.call("get_level_progress", 1) as Array), ["0,0,0", "3,1,4", "7,2,4"],
		"N9-E7：重放会话退出——断点滚动更新（重放格+新格并入同一差集）")

	# 未动关卡（无断点）：重放零操作 + 不产生断点
	_reset_save()
	var inst6: Node = await _make_level(1)
	check_eq(int(inst6.call("get_undo_depth")), 0, "N9-E8：无断点进关撤销栈为空（重放零操作）")
	if inst6.call("has_method", "_export_deleted_cells"):
		check_eq((inst6.call("_export_deleted_cells") as Array), [], "N9-E8 前置：未动导出空")
	else:
		check(false, "N9-E8 前置：未动导出空（导出钩子缺失）")
	inst6.queue_free()
	await process_frame
	check_eq((save.call("get_level_progress", 1) as Array), [], "N9-E9：未动关卡离场不产生断点键（存档无新增数据）")

	# 图鉴 replay 进关同样恢复（同一 _ready 重放路径，入口无关）
	_reset_save()
	save.call("set_level_progress", 1, ["0,0,0"])
	var inst7: Node = await _make_level(1, true)
	check(not (_sorted_remaining(inst7) as Array).has(CELL_A), "N9-E10：图鉴 replay 进关同样重放恢复")
	inst7.queue_free()
	await process_frame

	Engine.max_fps = 0
	_cleanup_files()
	finish()
