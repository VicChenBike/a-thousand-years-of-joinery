extends "res://tests/test_base.gd"
## 批次 W W2（2026-09-20 规格 §3 N11/P2-12b，拍板 3 防抖 2 秒）——TDD 红测先行。
## 契约来源：批次 W 规格 §3 N11/P2-12b + W0 §二 N11 + 拍板 3（防抖 2 秒+退出/切场景/窗口×
## 立即兜底；通关只记通关删进度键）。
## 段口径：
##   S（既有语义回归锚）：退出确认写点①（_on_exit_confirmed 先落断点再路由）与 _exit_tree
##     兜底②——N9-C1/C3 既有断言的本文件轻量复验（实现不得回归）。
##   A（N11 防抖缝）：挖除/撤销/重做改动路径置 _checkpoint_dirty_at；防抖判定缝
##     _checkpoint_debounce_due(now_ms)——改动后 2s 内不触发（注入 now+1999）、≥2s 触发
##     （注入 now+2000；无头直接调判定方法驱动，不依赖真实等待）。
##   B（N11 自动落盘）：脏时间戳注入「2.5s 前」→ _process 一帧 → 检查点落盘（memory+磁盘）+清脏。
##   C（N11/P2-12b 显式落盘缝）：flush_checkpoint()——立即落+清脏；未动关卡幂等省写零 I/O。
##   D（通关共存）：通关删键语义保持（N9-D2 等价锚）+通关清脏+结算后 flush 不把通关态重写成
##     断点（_settled 守卫）+_exit_tree 兜底仍守卫。
##   E（P2-12b 窗口×路径）：main.gd _quit_now_shared 源码序断言（flush_checkpoint 在
##     stop_gesture_process 之前+LEVEL 态守卫）+子进程探针（-- --probe-quit-level）——
##     boot→切 LEVEL→删格→调 _quit_now_shared（quit 前显式落检查点）→父进程验磁盘档含该章
##     progress 键（_exit_tree 兜底保留：两写点幂等一致，探针验用户可见结局，源码断言验接线）。
## 锁存共存注记：未来版本只读锁（W1 P0-8）下 set_level_progress→save_game() 早退静默零写盘
##   （save_manager.gd :282-286 无警告分支）——防抖路径锁存下零警告刷屏（源码序断言 E 段锁定）。
## 清档纪律（tools/README_走查清档规范.md，test_w_save_domain 同款）：备份四件组→测试域操作→
##   终测统一还原+load_game 重同步+逐字节等价断言+自愈先还原再重备份。零摄像头。

const LS_SCENE := "res://scenes/level/level_scene.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const MAIN_SRC := "res://scenes/main.gd"
const LEVEL_SRC := "res://scenes/level/level_scene.gd"
const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"
const BK_PREFIX := "user://_w2_ckpt_"
const WATCHED_PATHS: Array = [SAVE_PATH, FLAG_PATH, TMP_PATH, BAK_PATH]
const CELL_A := Vector3i(0, 0, 0)
const CELL_B := Vector3i(7, 2, 4)  # 批次 Z 五件套 12×3×5 实况（旧 z=7 越界等价替换留痕）
const ST_MAIN_MENU := 1
const ST_LEVEL := 4  # Game.State.LEVEL（enum 序：BOOT/MM/MOVIE/TALK/LEVEL/SETTLE/CATALOG）

var game: Variant
var save: Variant
var lib: Variant
var _pre_save_text: String = ""

func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _del(p: String) -> void:
	var a: String = _abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _read_file(p: String) -> String:
	return FileAccess.get_file_as_string(p)

func _disk_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var v: Variant = JSON.parse_string(_read_file(SAVE_PATH))
	return v if v is Dictionary else {}

func _disk_deleted_cells(ch: int) -> Variant:
	var lp: Variant = (_disk_save().get("progress", {}) as Dictionary).get("level_progress", {})
	var entry: Variant = (lp as Dictionary).get(str(ch), null)
	if typeof(entry) != TYPE_DICTIONARY:
		return null
	return (entry as Dictionary).get("deleted_cells", null)

func _selfheal_previous_backup() -> void:
	var healed: int = 0
	for p: String in WATCHED_PATHS:
		var bk := BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			_del(p)
			DirAccess.copy_absolute(_abs(bk), _abs(p))
			DirAccess.remove_absolute(_abs(bk))
			healed += 1
	if healed > 0:
		print("EVID|selfheal|w_checkpoint_debounce|restored=%d" % healed)

func _backup_user() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		_pre_save_text = _read_file(SAVE_PATH)
	for p: String in WATCHED_PATHS:
		if FileAccess.file_exists(p):
			var bk := BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_abs(p), _abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	for p: String in WATCHED_PATHS:
		_del(p)
		var bk := BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_abs(bk), _abs(p))
			DirAccess.remove_absolute(_abs(bk))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()
	var post: String = _read_file(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|w_checkpoint_debounce|files=%d" % WATCHED_PATHS.size())

func _cleanup_files() -> void:
	for p: String in [SAVE_PATH, FLAG_PATH]:
		_del(p)

func _reset_save() -> void:
	_cleanup_files()
	save.load_game()

func _make_level(ch: int) -> Node:
	var inst: Node = (load(LS_SCENE) as PackedScene).instantiate()
	inst.call("set_context", {"chapter": ch})
	add_child(inst)
	await process_frame
	return inst

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--probe-quit-level"):
		await _probe_quit_level()
		return
	print("== test_w_checkpoint_debounce（批次 W2：N11 防抖 2s / P2-12b 退出落盘） ==")
	_selfheal_previous_backup()
	_backup_user()
	Engine.max_fps = 60
	game = get_root().get_node("Game")
	save = get_root().get_node("SaveManager")
	lib = get_root().get_node("LevelLibrary")
	_cleanup_files()
	save.load_game()
	lib.scan_directory("res://levels_data")

	await _s_existing_write_points()
	await _a_dirty_mark_and_debounce_seam()
	await _b_debounce_flush_via_process()
	await _c_flush_checkpoint_seam()
	await _d_settle_coexistence()
	await _e_quit_path()
	_cleanup_files()
	Engine.max_fps = 0
	_restore_user()
	finish()

# ================= 段 S：既有写点回归锚（N9-C 等价轻复验） =================
func _s_existing_write_points() -> void:
	# S1 退出确认写点①：先落断点再路由（N9-C1 既有语义，实现不得回归）
	_reset_save()
	var inst: Node = await _make_level(1)
	inst.call("select_voxel", CELL_A, true)
	inst.call("delete_selected")
	inst.call("_ask_exit", ST_MAIN_MENU, "测试退出")
	inst.call("_on_exit_confirmed")
	await process_frame
	check_eq(int(game.current_state()), ST_MAIN_MENU, "S1 前置：退出确认路由 MAIN_MENU（语义不变）")
	check_eq((save.call("get_level_progress", 1) as Array), ["0,0,0"],
		"S1：退出确认写点①落断点保持（N9-C1 等价锚）")
	inst.queue_free()
	await process_frame
	# S2 _exit_tree 兜底②（N9-C3 既有语义）
	_reset_save()
	var inst2: Node = await _make_level(1)
	inst2.call("select_voxel", CELL_C2(), true)
	inst2.call("delete_selected")
	inst2.queue_free()
	await process_frame
	check_eq((save.call("get_level_progress", 1) as Array), ["3,1,4"],
		"S2：_exit_tree 兜底写点②保持（N9-C3 等价锚）")
	_reset_save()

func CELL_C2() -> Vector3i:
	return Vector3i(3, 1, 4)

# ================= 段 A：脏标记 + 防抖判定缝 =================
func _a_dirty_mark_and_debounce_seam() -> void:
	var inst: Node = await _make_level(1)
	if not (inst.has_method("_checkpoint_debounce_due") and inst.has_method("flush_checkpoint")):
		check(false, "A0：防抖判定缝 _checkpoint_debounce_due 存在（红）")
		check(false, "A0：显式落盘缝 flush_checkpoint 存在（红）")
		inst.queue_free()
		await process_frame
		_reset_save()
		return
	check(true, "A0：防抖/落盘两缝存在")
	check(int(inst.get("_checkpoint_dirty_at")) == -1, "A1：进关初始无脏（_checkpoint_dirty_at=-1）")
	check_eq(bool(inst.call("_checkpoint_debounce_due")), false, "A2：无脏 → 判定恒 false")
	# A3 挖除置脏（同步断言：无 await，无自然帧穿插）
	inst.call("select_voxel", CELL_A, true)
	var removed: int = int(inst.call("delete_selected"))
	check_eq(removed, 1, "A3 前置：删格 A")
	var dirty: int = int(inst.get("_checkpoint_dirty_at"))
	check(dirty >= 0, "A3：挖除置脏 _checkpoint_dirty_at≥0（-1=哨兵已清除；进程启动极早期可为 0）")
	# A4 2s 内不触发（注入 now=dirty+1999；不依赖真实等待）
	check_eq(bool(inst.call("_checkpoint_debounce_due", dirty + 1999)), false,
		"A4：改动后 1999ms → 判定 false（2s 内不落）")
	# A5 ≥2s 触发（注入 now=dirty+2000）
	check_eq(bool(inst.call("_checkpoint_debounce_due", dirty + 2000)), true,
		"A5：改动后 2000ms → 判定 true（≥2s 触发）")
	# A6 2s 内磁盘/memory 无该章断点键（防抖未到点不落盘）
	check_eq((save.call("get_level_progress", 1) as Array), [], "A6：防抖窗内 memory 无该章断点")
	check(_disk_deleted_cells(1) == null, "A6：防抖窗内磁盘无该章 progress 键")
	# A7/A8 撤销/重做同样置脏（时间戳单调不回退）
	var d0: int = int(inst.get("_checkpoint_dirty_at"))
	inst.call("undo")
	check(int(inst.get("_checkpoint_dirty_at")) >= d0, "A7：撤销置脏（时间戳不早于改动前）")
	d0 = int(inst.get("_checkpoint_dirty_at"))
	inst.call("redo")
	check(int(inst.get("_checkpoint_dirty_at")) >= d0, "A8：重做置脏（时间戳不早于撤销前）")
	inst.queue_free()
	await process_frame
	_reset_save()

# ================= 段 B：防抖到点经 _process 自动落盘 =================
func _b_debounce_flush_via_process() -> void:
	var inst: Node = await _make_level(1)
	if not inst.has_method("_checkpoint_debounce_due"):
		inst.queue_free()
		await process_frame
		_reset_save()
		return
	inst.call("select_voxel", CELL_A, true)
	inst.call("delete_selected")
	inst.call("select_voxel", CELL_B, true)
	inst.call("delete_selected")
	# 注入「2.5s 前」脏时间戳（无头不真等 2.5s）
	inst.set("_checkpoint_dirty_at", Time.get_ticks_msec() - 2500)
	inst.call("_process", 0.016)  # 一帧推进：防抖分支到点 → flush_checkpoint
	check_eq((save.call("get_level_progress", 1) as Array), ["0,0,0", "7,2,4"],
		"B1：≥2s 无新改动 → _process 自动落检查点（memory 断点=两格差集）")
	var disk_cells: Variant = _disk_deleted_cells(1)
	check(disk_cells is Array and (disk_cells as Array) == ["0,0,0", "7,2,4"],
		"B2：检查点落盘到 user://save.json（磁盘档含 level_progress[1]）")
	check(int(inst.get("_checkpoint_dirty_at")) == -1, "B3：落盘后清脏（不再重复触发）")
	inst.queue_free()
	await process_frame
	_reset_save()

# ================= 段 C：显式落盘缝 flush_checkpoint =================
func _c_flush_checkpoint_seam() -> void:
	var inst: Node = await _make_level(1)
	if not inst.has_method("flush_checkpoint"):
		inst.queue_free()
		await process_frame
		_reset_save()
		return
	inst.call("select_voxel", CELL_A, true)
	inst.call("delete_selected")
	inst.call("flush_checkpoint")
	check_eq((save.call("get_level_progress", 1) as Array), ["0,0,0"],
		"C1：flush_checkpoint 立即落断点（memory）")
	check(_disk_deleted_cells(1) is Array, "C2：flush_checkpoint 立即落盘（磁盘档含键）")
	check(int(inst.get("_checkpoint_dirty_at")) == -1, "C3：flush 后清脏")
	inst.queue_free()
	await process_frame
	# C4 幂等省写：未动关卡 flush 零新增（N9-A12 语义在 flush 路径保持）
	_reset_save()
	var inst2: Node = await _make_level(1)
	inst2.call("flush_checkpoint")
	check_eq((save.call("get_level_progress", 1) as Array), [], "C4：未动关卡 flush → 无断点（没改语义）")
	check(not ((save.get_progress()["level_progress"] as Dictionary).has("1")),
		"C5：未动关卡 flush 不产生断点键（存档无新增数据）")
	inst2.queue_free()
	await process_frame
	_reset_save()

# ================= 段 D：通关共存（删键保持 + 清脏 + _settled 守卫） =================
func _d_settle_coexistence() -> void:
	_reset_save()
	save.call("set_level_progress", 1, ["0,0,0"])  # 预置旧断点（模拟上会话遗留）
	var inst: Node = await _make_level(1)
	if not inst.has_method("flush_checkpoint"):
		inst.queue_free()
		await process_frame
		_reset_save()
		return
	# 会话内先挖一格（置脏）再通关
	inst.call("select_voxel", CELL_B, true)
	inst.call("delete_selected")
	check(int(inst.get("_checkpoint_dirty_at")) > 0, "D0 前置：通关前有脏标记")
	var target: Array = ((lib.get_level(1)["data"] as Dictionary)["pieces"][0] as Dictionary)["target_shapes"][0]
	inst.call("set_remaining_for_test", target)
	var jb: Button = inst.get_node_or_null("TopBar/Buttons/JoinButton")
	check(jb is Button, "D1 前置：JoinButton 存在")
	if jb != null:
		jb.pressed.emit()
		inst.call("_skip_success_animation")
		await process_frame
		check_eq(int(game.current_state()), 5, "D1 前置：通关路由 SETTLE（语义不变）")
		check_eq((save.call("get_level_progress", 1) as Array), [],
			"D2：通关删键语义保持（N9-D2 等价锚：通关=断点作废）")
		check(int(inst.get("_checkpoint_dirty_at")) == -1,
			"D3：通关清脏（防后续防抖把通关态重写成断点）")
		inst.call("flush_checkpoint")
		check_eq((save.call("get_level_progress", 1) as Array), [],
			"D4：结算后 flush_checkpoint 零复活（_settled 守卫）")
	inst.queue_free()
	await process_frame
	check_eq((save.call("get_level_progress", 1) as Array), [],
		"D5：结算后场景释放 _exit_tree 兜底仍守卫（N9-D3 等价锚）")
	_reset_save()

# ================= 段 E：P2-12b 窗口×路径（源码序 + 子进程探针） =================
func _func_body(src: String, sig: String) -> String:
	var f0: int = src.find(sig)
	if f0 < 0:
		return ""
	var f1: int = src.find("\nfunc ", f0 + 1)
	return src.substr(f0, (f1 if f1 > f0 else src.length()) - f0)

func _e_quit_path() -> void:
	# E1 源码序断言（test_v_quit_and_boot V18 同款源码证据链）：_quit_now_shared 在 stop 前
	# 显式落关卡检查点（LEVEL 态守卫），消除对 _exit_tree 时序的依赖。
	var src: String = _read_file(MAIN_SRC)
	var body := _func_body(src, "func _quit_now_shared(")
	check(body != "", "E1 前置：main.gd _quit_now_shared 可读")
	check(body.contains("flush_checkpoint"),
		"E2：_quit_now_shared 调 level_scene.flush_checkpoint（红：旧实现缺失）")
	check(body.contains("Game.State.LEVEL"),
		"E3：_quit_now_shared 限 LEVEL 态落检查点（状态守卫在场）")
	check(body.find("flush_checkpoint") >= 0
		and body.find("flush_checkpoint") < body.find("stop_gesture_process"),
		"E4：flush_checkpoint 先于 stop_gesture_process（quit 前落盘序）")
	check(body.find("SaveManager.save_game()") < body.find("flush_checkpoint"),
		"E5：全局 save_game 先于关卡检查点（V18 兜底语义保持在前）")
	# E6 锁存共存源码注记：level 防抖路径经 set_level_progress→save_game——W1 P0-8 锁存早退
	# 无警告分支在场（源码证据链：save_game 早退先于任何 push_warning）
	var sm_src: String = _read_file("res://autoload/save_manager.gd")
	var sg := _func_body(sm_src, "func save_game(")
	check(sg.contains("if _future_readonly:") and sg.find("if _future_readonly:") < sg.find("push_warning"),
		"E6：未来版本只读锁 save_game 早退先于警告分支（防抖路径锁存下零警告刷屏，W1 语义）")
	# E7 子进程探针（进程内调 _quit_now_shared 会真退当前测试进程 → 自举复用本文件；
	# test_v_quit_and_boot --probe-quit-save 同款）。判据：boot→切 LEVEL→删格→quit 后磁盘档
	# 含该章 progress 键（_exit_tree 兜底保留，两写点幂等一致——探针验用户可见结局）。
	_cleanup_files()  # 探针基线：磁盘无档（boot 走首启流，goto LEVEL 后的写点=检查点路径）
	var out: Array = []
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/test_w_checkpoint_debounce.gd", "--", "--probe-quit-level"])
	var code: int = OS.execute(OS.get_executable_path(), args, out, true, true)
	check_eq(code, 0, "E7：窗口×路径探针子进程按预期收口（_quit_now_shared → quit，exit 0）")
	var cells: Variant = _disk_deleted_cells(1)
	check(cells is Array and (cells as Array).has("0,0,0"),
		"E8：窗口×退出路径检查点已写（磁盘档 level_progress[1] 含删格 0,0,0；红：旧实现依赖 _exit_tree 时序且 boot 自动保存基线下写点不可判）")
	_reset_save()

## 子进程探针（-- --probe-quit-level）：boot 主场景 → 切 LEVEL → 删格 → _quit_now_shared
## （预期：save_game → flush_checkpoint〔LEVEL 态〕→ stop → quit，exit 0）。失败路径 quit(3)
## 由父进程判红，不悬挂。--script 时序：autoload _ready 延迟首帧（test_v_quit_and_boot 同款留痕）。
func _probe_quit_level() -> void:
	await process_frame
	var sm: Node = get_root().get_node("SaveManager")
	var game_node: Node = get_root().get_node("Game")
	var bridge_node: Node = get_root().get_node("GestureBridge")
	sm.call("load_game")
	# 防手势子进程拉起（test_v 同款夹具；update_settings 自动落盘属测试域）
	save = sm
	save.update_settings({"gesture_input": false, "gesture_camera_enabled": false})
	bridge_node.call("_set_state", 1)
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	get_root().add_child(main)
	await process_frame
	await process_frame
	# 切 LEVEL 态（main boot 已 attach 场景容器 → goto_state 真实装载关卡场景）
	game_node.call("goto_state", ST_LEVEL, {"chapter": 1})
	await process_frame
	await process_frame
	var lvl: Node = game_node.call("get_current_scene")
	if lvl == null or not (lvl as Node).has_method("flush_checkpoint"):
		print("PROBE|FAIL|level_scene 未就位或 flush_checkpoint 缺失（红）")
		quit(3)
		return
	if ((lvl as Node).call("get_remaining_voxels") as Array).is_empty():
		print("PROBE|FAIL|关卡体素未构建（levels_data 缺失？）")
		quit(3)
		return
	(lvl as Node).call("select_voxel", Vector3i(0, 0, 0), true)
	var removed: int = int((lvl as Node).call("delete_selected"))
	if removed <= 0:
		print("PROBE|FAIL|删格失败（探针前置不成立）")
		quit(3)
		return
	print("PROBE|dirty|cells_deleted=%d|state=%d" % [removed, int(game_node.call("current_state"))])
	main.call("_quit_now_shared")   # 预期进程在此结束（exit 0）
	# 兜底：实现回退未 quit 时 5s 后以码 3 退出（父进程判红，不悬挂）
	await create_timer(5.0).timeout
	quit(3)
