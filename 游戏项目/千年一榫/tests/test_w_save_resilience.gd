extends "res://tests/test_base.gd"
## 批次 W W1（2026-09-20 规格 §2 P0-6/P0-7/P0-8）——TDD 红测先行。
## 契约来源：批次 W 规格 §2（save_manager.gd 存档韧性三件）+ W0 §一 P0-6/P0-7/P0-8。
## 五块口径：
##   ①P0-6 .bak 回退：主档「解析失败/打不开/parsed_ver<1」→ 改读 SAVE_PATH+".bak"——
##     .bak 可载则采用并立即 save_game 修复主档（成功后 .bak 已升级即清）；.bak 亦坏才
##     _default_data；主档载入成功路径清 .bak（验收③）。主档文件在任何失败路径不删不改写。
##   ②P0-6/P0-8 版本裁决：parsed_ver>SAVE_VERSION 一律只读锁（主档与 .bak 同判，**不**进
##     .bak 回退）——防 v2 可载 .bak 顶掉 v3 新数据并写回；内存默认档运行、save_game() 早退
##     零写盘（规格 §9-5 双路径红线）、.bak 原样保留（验收④）、reset_for_new_game 同受锁保护。
##   ③P0-7 三键类型防御：progress/replay_award_counts/skins 非 Dictionary（含 JSON null）
##     整体回落该域默认值+push_warning，绝不中止（对齐 settings :96-99 先例口径）。
##   ④P0-8 migration 框架：_MIGRATIONS 函数表（下标=from_ver 逐级链式调用）；v1→v2 迁移体
##     =watched_opening+level_progress 归一/版本记账+skins K-D；既有 v1 迁移断言语义在本文件
##     复锁（N9-A13~A18 等价）。v2 档缺 level_progress 的防御归一为全版本普适段（既有
##     N9-A19 断言锁定，实现须保留——普适幂等归一，不随迁移链只在 v1 生效）。
##   ⑤P0-8 提示通道：FUTURE_READONLY_TOAST 常量文案=规格原文；_notify_future_readonly（延帧
##     Game.toast 协程）/_warn_future_readonly（同步降级口）存在且无头直调不炸。
## 清档纪律（tools/README_走查清档规范.md + test_v_save_domain 先例）：起测前备份 user://
##   真实档案（save.json/flag 及本测试可触及的 .tmp/.bak 全四件），终测还原并打印 EVID 证据行；
##   真实 autoload SaveManager 若在树则 load_game 重同步内存（规范第 2 条）。零摄像头。

const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"
const SM_SCRIPT := "res://autoload/save_manager.gd"
# 备份路径必须带全 user:// 前缀（test_v_save_domain 先例——相对路径在 FileAccess/DirAccess
# 间解析漂移，前缀缺失=备份链静默失效）。
const BK_PREFIX := "user://_w_save_backup_"
# 走查规范备份四件组（含测试可自建的 tmp/bak，还原后 user:// 与起测前逐字节等价）
const WATCHED_PATHS: Array = [SAVE_PATH, FLAG_PATH, TMP_PATH, BAK_PATH]
# 规格 §2 P0-8 原文文案（提示通道断言基准）
const SPEC_FUTURE_TOAST := "存档来自更新版本，本次运行进度不会保存"

var _sm_seq: int = 0
var _pre_save_text: String = ""  # 起测前真实 save.json 原文（还原等价自检基准）

func _lock_of(sm: Node) -> bool:
	## 红期防挂死（坑⑪同族，test_n9 红灯先例）：被测脚本尚未实现 _future_readonly 时，
	## 直接动态属性访问会报「Invalid get index」中止 _initialize → quit 永不执行挂死；
	## Object.get() 缺属性返回 null（无错误），与 true 精确比较不触发 bool(null) 强转（坑⑦）。
	return sm.get("_future_readonly") == true

func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _del(p: String) -> void:
	var a: String = _abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _write_file(p: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _read_file(p: String) -> String:
	return FileAccess.get_file_as_string(p)

func _selfheal_previous_backup() -> void:
	## 崩溃自愈（W1 事故留痕驱动）：上次运行若中途被杀（红期挂死/强杀），本测试前缀的备份
	## 滞留 user:// 且沙盒残留未被还原——若直接重备份会把残留物覆盖进备份、真实档案永久丢失。
	## 正常完成必清空备份（见 _restore_user），故起测首步发现遗留备份即先还原真实档案再重备份。
	## 并行纪律（规范第 5 条）注记：本前缀仅本测试使用，无并发同名备份；错峰执行由派遣层保证。
	var healed: int = 0
	for p: String in WATCHED_PATHS:
		var bk := BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			_del(p)
			DirAccess.copy_absolute(_abs(bk), _abs(p))
			DirAccess.remove_absolute(_abs(bk))
			healed += 1
	if healed > 0:
		print("EVID|selfheal|w_save_resilience|restored=%d" % healed)

func _backup_user() -> void:
	# 规范第 1 条：任何删/写档操作之前备份真实档案（test_v_save_domain 先例，全 user:// 路径）
	if FileAccess.file_exists(SAVE_PATH):
		_pre_save_text = _read_file(SAVE_PATH)
	for p: String in WATCHED_PATHS:
		if FileAccess.file_exists(p):
			var bk := BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_abs(p), _abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	# 规范第 2 条：所有退出路径统一收口还原；还原后真实 autoload load_game 重同步内存
	for p: String in WATCHED_PATHS:
		_del(p)
		var bk := BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_abs(bk), _abs(p))
			DirAccess.remove_absolute(_abs(bk))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()  # 防进程退出 close_requested → save_game 把测试态写回真实档案
	# 纪律自检：还原后 save.json 与起测前逐字节等价（起测前无档 ↔ 还原后无档）
	var post: String = _read_file(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|w_save_resilience|files=%d" % WATCHED_PATHS.size())

func _new_sm() -> Node:
	# 独立实例先例（test_v_save_domain/test_n9）：--script 无头 autoload _ready 不触发，
	# add_child 后显式 load_game 初始化 _data
	_sm_seq += 1
	var sm: Node = (load(SM_SCRIPT) as GDScript).new()
	sm.name = "SM_W_%d" % _sm_seq
	get_root().add_child(sm)
	sm.load_game()
	return sm

func _full_v2(talent: int, cleared: Array) -> Dictionary:
	## 完整 v2 档基线（游戏真实写盘形态，含全量 settings 键）
	return {
		"save_version": 2,
		"progress": {"cleared": cleared, "next_chapter": 1, "watched_opening": false, "level_progress": {}},
		"settings": {"gesture_input": true, "kb_input": true, "gesture_hud_visible": true,
			"gesture_hud_offset": [0, 0], "volume": {"master": 1.0, "music": 1.0, "sfx": 1.0},
			"gesture_camera_enabled": true, "gesture_panel_folded": false,
			"gesture_camera_device": "", "gesture_camera_res": "", "gesture_camera_fps": 0,
			"udp_port": 0},
		"talent": talent,
		"skins": {"owned": ["skin_default", "skin_origin_kaitou"],
			"equipped": "skin_origin_kaitou", "preferred": "skin_origin_kaitou"},
		"replay_award_counts": {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0},
	}

func _initialize() -> void:
	print("== test_w_save_resilience ==")
	_selfheal_previous_backup()
	_backup_user()
	for p: String in WATCHED_PATHS:
		_del(p)  # 沙盒基线：真实档案已备份，测试域内四件全清

	# ===== 一、P0-6：.bak 回退 =====
	# 1a 主档坏 + .bak 好 → 恢复 .bak 数据 + 立即回写修复主档（验收①）
	_write_file(SAVE_PATH, "{ broken json")
	_write_file(BAK_PATH, JSON.stringify(_full_v2(777, [2])))
	var sm1a: Node = _new_sm()
	check_eq(sm1a.get_talent(), 777, "P0-6①：主档坏+.bak 好 → 恢复 .bak 数据（talent 777）")
	check_eq((sm1a.get_progress()["cleared"] as Array), [2], "P0-6①：.bak progress 域无损恢复")
	var main_text_1a: String = _read_file(SAVE_PATH)
	var main_reparsed: Variant = JSON.parse_string(main_text_1a)
	check(typeof(main_reparsed) == TYPE_DICTIONARY, "P0-6①：主档已被 .bak 数据回写修复（可解析）")
	if typeof(main_reparsed) == TYPE_DICTIONARY:
		check_eq(int((main_reparsed as Dictionary).get("talent", -1)), 777, "P0-6①：修复后主档 talent=777")
	check(not FileAccess.file_exists(BAK_PATH), "P0-6①：修复成功后 .bak 已升级为主档、冗余即清")

	# 1b 两者皆坏 → 默认档（验收②；主档不删不改写）
	_write_file(SAVE_PATH, "{ broken json")
	_write_file(BAK_PATH, "also { broken")
	var old_main_1b: String = _read_file(SAVE_PATH)
	var sm1b: Node = _new_sm()
	check_eq(sm1b.get_talent(), 500, "P0-6②：主档与 .bak 皆坏 → 默认档（talent 500）")
	check_eq(_read_file(SAVE_PATH), old_main_1b, "P0-6②：双坏路径主档文件不删不改写")

	# 1c 主档好 → .bak 被清（验收③）
	var sm1c: Node = _new_sm()
	check_eq(sm1c.save_game(), true, "P0-6③ 前置：主档落盘成功")
	_write_file(BAK_PATH, "stale bak")
	var sm1c2: Node = _new_sm()
	check_eq(sm1c2.get_talent(), 500, "P0-6③：主档好 → 正常载入")
	check(not FileAccess.file_exists(BAK_PATH), "P0-6③：主档载入成功路径 .bak 被清")

	# 1d 主档 v3 + .bak v2 → 默认档+锁置位+.bak 原样保留（验收④；P0-6/P0-8 裁决：不进 .bak 回退）
	_write_file(SAVE_PATH, JSON.stringify({"save_version": 3, "talent": 999,
		"progress": {"cleared": [5], "next_chapter": 6, "watched_opening": true, "level_progress": {}}}))
	_write_file(BAK_PATH, JSON.stringify(_full_v2(888, [1])))
	var old_bak_1d: String = _read_file(BAK_PATH)
	var old_main_1d: String = _read_file(SAVE_PATH)
	var sm1d: Node = _new_sm()
	check_eq(sm1d.get_talent(), 500, "P0-6④：主档 v3+.bak v2 → 内存默认档（talent 500，不被 .bak 顶掉）")
	check(_lock_of(sm1d), "P0-6④：未来版本只读锁置位")
	check_eq(_read_file(BAK_PATH), old_bak_1d, "P0-6④：.bak 原样保留（逐字节不动）")
	check_eq(_read_file(SAVE_PATH), old_main_1d, "P0-6④：主档 v3 原样保留（等升级，不重置）")
	check_eq(sm1d.save_game(), false, "P0-6④：锁存时 save_game 早退返回 false")
	check_eq(_read_file(SAVE_PATH), old_main_1d, "P0-6④：锁存时 save_game 零写盘（主档逐字节不变）")
	check(not FileAccess.file_exists(TMP_PATH), "P0-6④：锁存时 save_game 零写盘（无 .tmp 残留）")
	sm1d.mark_first_launch()  # P2-2 回修断言前置：预置 flag（锁存清档场景）
	check(FileAccess.file_exists(FLAG_PATH), "P2-2 前置：flag 已落位")
	sm1d.reset_for_new_game()
	check_eq(_read_file(SAVE_PATH), old_main_1d, "P0-6④：锁存时 reset_for_new_game 也不覆写主档")
	check(FileAccess.file_exists(FLAG_PATH), "P2-2：锁存时 reset_for_new_game 不删 first_launch.flag（只读不落盘语义延伸）")

	# 1e 主档缺 + .bak 存在 → 默认档不回退（边界锁定：回退触发面=解析失败/打不开/ver<1，
	#     缺档不在列——首次启动无档语义保持，防手工删档后 .bak 意外复活旧进度）
	_del(SAVE_PATH)
	_write_file(BAK_PATH, JSON.stringify(_full_v2(666, [1])))
	var old_bak_1e: String = _read_file(BAK_PATH)
	var sm1e: Node = _new_sm()
	check_eq(sm1e.get_talent(), 500, "P0-6：主档缺+.bak 在 → 默认档（缺档不在回退触发面）")
	check(not _lock_of(sm1e), "P0-6：缺档路径不置未来版本锁")
	check_eq(_read_file(BAK_PATH), old_bak_1e, "P0-6：缺档路径 .bak 原样保留")

	# 1f .bak v3 + 主档坏 → 同判锁（主档与 .bak 同判，未来版本备份同样只读）
	_write_file(SAVE_PATH, "{ broken json")
	_write_file(BAK_PATH, JSON.stringify({"save_version": 3, "talent": 999}))
	var old_bak_1f: String = _read_file(BAK_PATH)
	var sm1f: Node = _new_sm()
	check(_lock_of(sm1f), "P0-6：.bak v3 同判 → 只读锁置位")
	check_eq(sm1f.get_talent(), 500, "P0-6：.bak v3 → 内存默认档")
	check_eq(_read_file(BAK_PATH), old_bak_1f, "P0-6：.bak v3 原样保留")

	# ===== 二、P0-7：三键脏类型整体回落默认（progress/replay_award_counts/skins） =====
	# 2a progress 脏类型
	_del(SAVE_PATH)
	_del(BAK_PATH)
	_write_file(SAVE_PATH, JSON.stringify({"save_version": 2, "progress": 5, "talent": 321}))
	var sm2a: Node = _new_sm()
	check_eq(sm2a.get_talent(), 321, "P0-7：progress 脏类型不中止 load_game（其余字段保留）")
	var prog_2a: Variant = sm2a.get_progress()
	check(typeof(prog_2a) == TYPE_DICTIONARY, "P0-7：progress=5 → 域整体回落默认 Dictionary")
	if typeof(prog_2a) == TYPE_DICTIONARY:
		var p2a: Dictionary = prog_2a
		check_eq(int(p2a.get("next_chapter", -1)), 1, "P0-7：progress 回落默认（next_chapter=1）")
		check_eq(int((p2a.get("cleared", [9]) as Array).size()), 0, "P0-7：progress 回落默认（cleared 空）")
		check(p2a.get("level_progress", null) is Dictionary, "P0-7：progress 回落默认（level_progress={}）")
	# 2b skins 脏类型
	_write_file(SAVE_PATH, JSON.stringify({"save_version": 2, "skins": "x", "talent": 500}))
	var sm2b: Node = _new_sm()
	var skins_2b: Variant = sm2b.get_skins()
	check(typeof(skins_2b) == TYPE_DICTIONARY, "P0-7：skins=\"x\" → 域整体回落默认 Dictionary")
	if typeof(skins_2b) == TYPE_DICTIONARY:
		var s2b: Dictionary = skins_2b
		check_eq(String(s2b.get("equipped", "")), "skin_origin_kaitou", "P0-7：skins 回落默认（equipped=开头）")
		check((s2b.get("owned", []) as Array).has("skin_default"), "P0-7：skins 回落默认（owned 含默认皮肤）")
	# 2c replay_award_counts 脏类型
	_write_file(SAVE_PATH, JSON.stringify({"save_version": 2, "replay_award_counts": 1}))
	var sm2c: Node = _new_sm()
	check_eq(sm2c.get_replay_count(1), 0, "P0-7：replay_award_counts=1 → 回落默认（计数 0）")
	var counts_2c: Variant = sm2c._data.get("replay_award_counts", null)
	check(typeof(counts_2c) == TYPE_DICTIONARY, "P0-7：replay_award_counts 回落默认 Dictionary（含键回写防后续直取炸）")
	# 2d 三脏齐发 + settings 旧防御同档共存 → 全部回落、load 不炸
	_write_file(SAVE_PATH, JSON.stringify({"save_version": 2, "progress": 5, "skins": "x",
		"replay_award_counts": 1, "settings": "dirty", "talent": 123}))
	var sm2d: Node = _new_sm()
	check_eq(sm2d.get_talent(), 123, "P0-7：三脏齐发 load_game 不炸（talent 保留）")
	check(typeof(sm2d.get_progress()) == TYPE_DICTIONARY, "P0-7：三脏齐发 progress 回落")
	check(typeof(sm2d.get_skins()) == TYPE_DICTIONARY, "P0-7：三脏齐发 skins 回落")
	check_eq(sm2d.get_replay_count(3), 0, "P0-7：三脏齐发 counts 回落")
	check_eq(bool(sm2d.get_settings().get("gesture_input", false)), true, "P0-7：settings=\"dirty\" 沿用既有防御回落默认")
	# 2e progress=null（JSON null，坑⑦族）→ 回落默认
	_write_file(SAVE_PATH, JSON.stringify({"save_version": 2, "progress": null}))
	var sm2e: Node = _new_sm()
	check(typeof(sm2e.get_progress()) == TYPE_DICTIONARY, "P0-7：progress=null → 回落默认（null 判空不炸）")

	# ===== 三、P0-8：migration 框架 + 未来版本拒载 =====
	# 3a v1 档经迁移链升 v2 字段齐（N9-A13~A18 等价复锁）
	_del(SAVE_PATH)
	_del(BAK_PATH)
	_write_file(SAVE_PATH, JSON.stringify({
		"save_version": 1,
		"progress": {"cleared": [1, 2], "next_chapter": 3},
		"talent": 250,
		"skins": {"owned": ["skin_default", "skin_07"], "equipped": "skin_07"},
		"replay_award_counts": {"1": 1},
	}))
	var sm3a: Node = _new_sm()
	check_eq(int(sm3a._data.get("save_version", -1)), 2, "P0-8：v1 档迁移后 save_version=2（版本记账）")
	check_eq((sm3a.get_progress()["cleared"] as Array), [1, 2], "P0-8：v1 迁移——cleared 无损保留")
	check_eq(int(sm3a.get_progress()["next_chapter"]), 3, "P0-8：v1 迁移——next_chapter 无损保留")
	check_eq(sm3a.get_talent(), 250, "P0-8：v1 迁移——talent 无损保留")
	check_eq(bool(sm3a.get_progress()["watched_opening"]), false, "P0-8：v1 迁移——watched_opening 缺字段补默认 false")
	check_eq((sm3a.get_progress()["level_progress"] as Dictionary), {}, "P0-8：v1 迁移——level_progress 缺字段补默认 {}")
	check_eq(String(sm3a.get_skins()["preferred"]), "skin_07", "P0-8：v1 迁移——skins preferred=equipped（K-D 先例）")
	check((sm3a.get_skins()["owned"] as Array).has("skin_origin_kaitou"), "P0-8：v1 迁移——owned 补开头原创")
	check_eq(int(sm3a._data.get("replay_award_counts", {}).get("1", -1)), 1, "P0-8：v1 迁移——replay 计数无损保留")
	sm3a.save_game()
	var disk_3a: Variant = JSON.parse_string(_read_file(SAVE_PATH))
	check(typeof(disk_3a) == TYPE_DICTIONARY and int((disk_3a as Dictionary).get("save_version", -1)) == 2,
		"P0-8：迁移后落盘即 v2 格式（roundtrip）")
	# 3b v1 档带脏 level_progress 串 → 迁移归一为 {}
	_write_file(SAVE_PATH, JSON.stringify({
		"save_version": 1,
		"progress": {"cleared": [], "next_chapter": 1, "watched_opening": true, "level_progress": "garbage"},
	}))
	var sm3b: Node = _new_sm()
	check_eq(bool(sm3b.get_progress()["watched_opening"]), true, "P0-8：v1 迁移——显式 watched=true 无损保留")
	check_eq((sm3b.get_progress()["level_progress"] as Dictionary), {}, "P0-8：v1 迁移——脏 level_progress 归一丢弃")
	# 3c v2 档缺 level_progress → 防御性补默认（全版本普适归一；既有 N9-A19 同口径）
	_write_file(SAVE_PATH, JSON.stringify({
		"save_version": 2,
		"progress": {"cleared": [1], "next_chapter": 2, "watched_opening": false},
		"talent": 55,
	}))
	var sm3c: Node = _new_sm()
	check(sm3c.get_progress().get("level_progress", null) is Dictionary,
		"P0-8：v2 档缺 level_progress → 防御性补默认（普适归一，不随迁移链只在 v1 生效）")
	# 3d 迁移框架与未来版本提示通道（§2 P0-8）
	var smc: Script = load(SM_SCRIPT)
	check_eq(String(smc.get_script_constant_map().get("FUTURE_READONLY_TOAST", "<缺>")), SPEC_FUTURE_TOAST,
		"P0-8：FUTURE_READONLY_TOAST 常量=规格原文（用户可见提示文案）")
	var mig: Variant = sm3c.get("_MIGRATIONS")
	check(mig is Array and (mig as Array).size() >= 2, "P0-8：_MIGRATIONS 迁移函数表已装配（下标=from_ver，含 v1 槽位）")
	if mig is Array and (mig as Array).size() >= 2:
		check((mig as Array)[1] is Callable, "P0-8：_MIGRATIONS[1] 为可调用迁移体（下标=from_ver，[0]=v0 占位 null）")
	if sm3c.has_method("_warn_future_readonly"):
		sm3c.call("_warn_future_readonly")  # 同步降级口无头直调不炸（Game 未挂接 toast → 内部降级日志）
		check(true, "P0-8：_warn_future_readonly 同步直调不炸")
	else:
		check(false, "P0-8：_warn_future_readonly 同步降级口存在（红期防挂死按 has_method 守卫）")
	check(sm3c.has_method("_notify_future_readonly"), "P0-8：延帧提示协程 _notify_future_readonly 存在")
	# 3e 正常档 save_game 照常（规格 §9-5 双路径红线）
	_del(SAVE_PATH)
	_del(BAK_PATH)
	var sm3e: Node = _new_sm()
	check(not _lock_of(sm3e), "P0-8：正常档不置锁")
	check_eq(sm3e.save_game(), true, "P0-8：正常档 save_game 照常 true")
	sm3e.add_talent(33)
	check_eq(int(JSON.parse_string(_read_file(SAVE_PATH)).get("talent", -1)), 533,
		"P0-8：正常档变更即存落盘生效（500+33）")

	# ===== 收口：还原真实档案（规范第 2 条）+ 真实 autoload 重同步 =====
	_restore_user()
	finish()
