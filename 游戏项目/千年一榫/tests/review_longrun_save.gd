extends "res://tests/test_base.gd"
## 批次 AA 终审（review 专用，不入回归分母）：方向1d 存档长跑量化（300 次原子写）。
## 验证：2s 防抖之外的直接写路径反复落盘不坏档、save_version 稳定、无 tmp/bak 残留、
## JSON 每轮可解析、类型防御（坏档隔离）。存档四件组备份-还原。

const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"
const BK_PREFIX := "user://_review_sv_backup_"
const WATCHED: Array = [SAVE_PATH, FLAG_PATH, TMP_PATH, BAK_PATH]

var _bk_made := {}

func _backup_user() -> void:
	for p: String in WATCHED:
		var abs_p := ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs_p):
			DirAccess.copy_absolute(abs_p, ProjectSettings.globalize_path(BK_PREFIX + p.get_file()))
			_bk_made[p] = true

func _restore_user() -> void:
	for p: String in WATCHED:
		var abs_p := ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs_p):
			DirAccess.remove_absolute(abs_p)
		var bk := ProjectSettings.globalize_path(BK_PREFIX + p.get_file())
		if _bk_made.has(p) and FileAccess.file_exists(bk):
			DirAccess.copy_absolute(bk, abs_p)
			DirAccess.remove_absolute(bk)

func _initialize() -> void:
	await process_frame
	await process_frame
	_backup_user()
	var save: Node = get_root().get_node_or_null("SaveManager")
	check(save != null, "前置：/root/SaveManager 在位")
	if save == null:
		finish()
		return

	# ---------- 300 次交替断点写（每次 save_game 原子写全档） ----------
	var ok_all := true
	var ver_stable := true
	var write_fails := 0
	var prev_len := -1
	for i: int in 300:
		var ch := (i % 5) + 1
		var cells: Array = []
		for k: int in (i % 7) + 1:
			cells.append("%d,%d,%d" % [k, k % 3, k % 5])
		save.call("set_level_progress", ch, cells)
		# 每轮读盘验证
		var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f == null:
			write_fails += 1
			ok_all = false
			break
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) != TYPE_DICTIONARY:
			write_fails += 1
			ok_all = false
			break
		var d: Dictionary = parsed
		if int(d.get("save_version", -1)) != 2:
			ver_stable = false
			break
	check(ok_all, "300 次断点写全程落盘可解析（失败=%d）" % write_fails)
	check(ver_stable, "save_version 全程稳定为 2")

	# 残留检查：无 tmp、无 bak
	check(not FileAccess.file_exists(TMP_PATH), "无 save.json.tmp 残留")
	check(not FileAccess.file_exists(BAK_PATH), "无 save.json.bak 残留")

	# 载入往返：load_game 后断点内容一致
	var before: Array = save.call("get_level_progress", 3)
	save.call("load_game")
	var after: Array = save.call("get_level_progress", 3)
	check_eq(after, before, "load_game 往返断点内容一致（域=%s）" % str(before))

	# ---------- 坏档隔离回归（W9-2 同款口径在长跑后仍成立） ----------
	var save_abs := ProjectSettings.globalize_path(SAVE_PATH)
	var broken := save_abs + ".review_broken.json"
	var fw: FileAccess = FileAccess.open(broken, FileAccess.WRITE)
	fw.store_string("{broken json no end")
	fw.close()
	# 直接污染主档验证 .bak 链不在本件范围（不破坏用户档）；只验 _parsed_save_version 类型防御纯函数
	var bad_parse: int = save.call("_parsed_save_version", [1, 2, 3])
	check_eq(bad_parse, -1, "W9-3：save_version 数组载荷防御回落 -1（不中止）")
	var bad_parse2: int = save.call("_parsed_save_version", {"save_version": {"a": 1}})
	check_eq(bad_parse2, -1, "W9-3：save_version 对象载荷防御回落 -1")
	DirAccess.remove_absolute(broken)

	# 未来版本只读锁
	var was_ro: bool = save.get("_future_readonly")
	check_eq(was_ro, false, "长跑后未来版本锁未误置")

	# ---------- Alt+F4 收口（W9-1）：close_requested 处理器在位 ----------
	var w: Window = root.get_window()
	var sigs: Array = w.get_signal_connection_list("close_requested")
	var found := false
	for c: Variant in sigs:
		var cb: Callable = (c as Dictionary).get("callable", Callable())
		if cb.is_valid() and cb.get_object() == save:
			found = true
	check(found, "W9-1：SaveManager._on_close_requested 已接窗口 close_requested")

	_restore_user()
	finish()
