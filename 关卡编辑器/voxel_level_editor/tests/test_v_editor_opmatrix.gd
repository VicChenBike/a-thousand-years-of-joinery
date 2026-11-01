extends "res://tests/test_base.gd"
## 批次 V（V-E4）编辑器操作顺序测试矩阵（规格 §9.6 ①②③ 收官 + §10/§14 纪律；用户主诉
## 「不同操作顺序会不会出问题/改一个牵连另一个/撤销历史被清」的终局断言件）。
## 矩阵 11 序列（≥10）：
##   序① blocks 改尺寸→target 改尺寸→undo/redo 交叉→终态四域各自正确；
##   序② 全局应用→单域改→undo→redo；
##   序③ 单域改→全局应用→undo/redo（全局复合单元回放四域）；
##   序④ 跨标签编辑终极断言——blocks 挖格→target 域尺寸操作→回 blocks：blocks 撤销历史
##       在 target 域操作后完好可用（用户「撤销历史被清」主诉直断言）→undo 尺寸→undo 挖格→redo 全链；
##   序⑤ 试玩内挖除/加块→退出试玩→编辑态格群/四域尺寸/撤销栈逐字节不变（内存快照+磁盘零 diff 双断言）；
##   序⑥ 试玩进出→尺寸应用→undo 链行为；
##   序⑦ 切槽位→草稿/撤销栈/载入数据隔离（切走再切回不串）；
##   序⑧ 切槽位中途自动保存→另一槽零污染（五文件逐字节）；
##   序⑨ 迁移后槽（V-E2 产物）上抽二复验（序①交叉链 + 序⑤试玩隔离）；
##   序⑩ copy_base 审视（V-E1 遗留风险点）：四域独立后 blocks→目标域复制按「目标域尺寸为权威」
##       裁剪落格（源域超界格裁剪），域尺寸零携带、源域零污染、撤销单元可用；
##   序⑪（规格 §9.6-1 具名）tag1 改→tag0/2/3 零变化 + undo 后 target_size 复原。
## 磁盘纪律：VOXEL_EDITOR_SLOTS_ROOT 指向 TEMP 一次性子目录，真实 levels/ 零触碰
## （test_v_editor_size_domains/test_v_editor_split 同款沙盒手法）。
## Godot 4.7 坑对齐（spec §14）：无头不断言视口几何（全走数据面）；字典取键一律 .get 防御（坑 2）；
## Vector3i 恒 == 比较；GDScript lambda 按值捕获不用于断言（坑 8）。

const LP := preload("res://scripts/level_project.gd")
const SLOTS := preload("res://scripts/level_slots.gd")
const FIXTURE := "res://tests/fixtures/level_chapter1_hemudu.json"   # 旧单文件标本（只读，序⑨ 迁移播种用）

const FIVE_FILES: Array = ["level.json", "blocks.json", "target.json", "join.json", "final.json"]

var _sandbox_root: String = ""
var _ed_v: Control = null

func _initialize() -> void:
	print("== test_v_editor_opmatrix ==")
	_init_sandbox()
	await _seq1_blocks_target_undo_redo_cross()
	await _seq2_global_then_single_then_undo_redo()
	await _seq3_single_then_global_then_undo()
	await _seq4_cross_tag_history_survival()
	await _seq5_playtest_isolation_byte_snapshots()
	await _seq6_playtest_roundtrip_undo_chain()
	await _seq7_slot_switch_isolation()
	await _seq8_slot_switch_autosave_no_pollution()
	await _seq9_migrated_slot_reverify()
	await _seq10_copy_base_domain_clipping()
	await _seq11_tag1_change_others_untouched()
	_cleanup_sandbox()
	finish()

# ==================== 沙盒夹具（TEMP 一次性根；test_v_editor_size_domains 同款） ====================
func _init_sandbox() -> void:
	var base := OS.get_environment("TEMP")
	if base.is_empty():
		base = "/tmp"
	base = base.replace("\\", "/")
	_sandbox_root = base.path_join("voxel_editor_vopmx_%d" % Time.get_ticks_msec()) + "/"
	OS.set_environment("VOXEL_EDITOR_SLOTS_ROOT", _sandbox_root)
	SLOTS.ensure_initialized(_sandbox_root, FIXTURE)   # 建五槽目录（save_slot_text 不自建）
	check(not _sandbox_root.is_empty(), "沙盒：TEMP 沙盒根建立（真实 levels/ 零触碰前提）")

func _seed_slot_333(slot: int) -> void:
	var p: RefCounted = LP.new()
	p.call("new_project", Vector3i(3, 3, 3))
	SLOTS.apply_auto_meta(p, slot)
	check(bool(SLOTS.save_slot_text(slot, p.call("save_to_text"), _sandbox_root)),
		"沙盒：槽 %d 播种 3³ 骨架成功（夹具健康前置）" % slot)
	SLOTS.save_meta(1, _sandbox_root)   # last_slot 钉 1：fresh editor 恒载槽 1

func _seed_slot_custom(slot: int, size: Vector3i, title: String) -> void:
	var p: RefCounted = LP.new()
	p.call("new_project", size)
	p.call("set_field", "title", title)
	SLOTS.apply_auto_meta(p, slot)
	check(bool(SLOTS.save_slot_text(slot, p.call("save_to_text"), _sandbox_root)),
		"沙盒：槽 %d 播种 %s 成功（夹具健康前置）" % [slot, str(size)])
	SLOTS.save_meta(1, _sandbox_root)

## 旧单文件槽播种（V-E2 拆分前历史槽；test_v_editor_split _seed_legacy 同款）：
## 清掉拆分五件套后原样写 level.json。
func _seed_slot_legacy(slot: int, text: String) -> bool:
	var dir: String = _sandbox_root + ("level_%d/" % slot)
	for name: String in ["blocks.json", "target.json", "join.json", "final.json", "level_legacy.json.bak"]:
		var fp := dir + name
		if FileAccess.file_exists(fp):
			DirAccess.remove_absolute(fp)
	var f := FileAccess.open(dir + "level.json", FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return f.get_error() == OK

func _fresh_editor() -> Control:
	if _ed_v != null:
		_ed_v.free()
		_ed_v = null
	_ed_v = (load("res://scenes/editor_main.tscn") as PackedScene).instantiate()
	add_child(_ed_v)
	await process_frame   # --script 模式 add_child 不立即进树（_ready 延后一帧，G6 惯例）
	return _ed_v

func _cleanup_sandbox() -> void:
	if _ed_v != null:
		_ed_v.free()
		_ed_v = null
	if _sandbox_root.is_empty():
		return
	_remove_dir_recursive(_sandbox_root)
	OS.set_environment("VOXEL_EDITOR_SLOTS_ROOT", "")
	_sandbox_root = ""

func _remove_dir_recursive(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	da.list_dir_begin()
	var item := da.get_next()
	while item != "":
		if item != "." and item != "..":
			var full := path.path_join(item)
			if da.current_is_dir():
				_remove_dir_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		item = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(path)

# ==================== 观测 helper ====================
## 撤销/重做单元深拷贝（逐字节比较用；compound 复合键保全）。
func _dup_units(arr: Array) -> Array:
	var out: Array = []
	for u: Variant in arr:
		var unit: Dictionary = u
		var cp: Dictionary = {
			"removed": (unit.get("removed", []) as Array).duplicate(),
			"added": (unit.get("added", []) as Array).duplicate(),
		}
		if unit.has("compound"):
			cp["compound"] = (unit.get("compound", {}) as Dictionary).duplicate(true)
		out.append(cp)
	return out

## 编辑态内存快照：四域格群/双栈/四域尺寸/项目全量数据（序⑤/⑨ 逐字节不变断言基准）。
func _memory_snapshot(ed: Control) -> Dictionary:
	var proj: RefCounted = ed.get("project")
	var sessions: Dictionary = ed.get("sessions")
	var cells: Dictionary = {}
	var undo: Dictionary = {}
	var redo: Dictionary = {}
	var sizes: Dictionary = {}
	for tag: int in [0, 1, 2, 3]:
		var sess: RefCounted = sessions[tag]
		cells[tag] = (sess.cells as Dictionary).duplicate(true)
		undo[tag] = _dup_units(sess.undo_stack)
		redo[tag] = _dup_units(sess.redo_stack)
		sizes[tag] = proj.call("get_size_for_tag", tag)
	return {"cells": cells, "undo": undo, "redo": redo, "sizes": sizes,
		"data": proj.call("snapshot_data")}

## 槽目录五文件文本快照（磁盘零 diff 断言基准；缺文件记哨兵 "<absent>"）。
func _disk_snapshot(slot: int) -> Dictionary:
	var out: Dictionary = {}
	var dir: String = _sandbox_root + ("level_%d/" % slot)
	for name: String in FIVE_FILES:
		var fp := dir + name
		out[name] = FileAccess.get_file_as_string(fp) if FileAccess.file_exists(fp) else "<absent>"
	return out

func _disk_equal(a: Dictionary, b: Dictionary) -> bool:
	for name: String in FIVE_FILES:
		if String(a.get(name, "<missing>")) != String(b.get(name, "<missing2>")):
			return false
	return true

func _sessions_of(ed: Control) -> Dictionary:
	return ed.get("sessions")

func _apply_one(ed: Control, size: Vector3i) -> void:
	## 单组件应用三步（起草稿→点应用→确认框确认）；调用方自证 active_tag 与确认框在场。
	(ed.get("size_x") as SpinBox).value = float(size.x)
	(ed.get("size_y") as SpinBox).value = float(size.y)
	(ed.get("size_z") as SpinBox).value = float(size.z)
	ed.call("_on_apply_size_one_pressed")
	var dlg: ConfirmationDialog = ed.get("_size_dialog")
	check(dlg != null and dlg.visible, "前置：单组件应用入确认框（U12② 强制确认口径）")
	ed.call("_on_size_confirmed")

func _apply_all(ed: Control, size: Vector3i) -> void:
	(ed.get("size_x") as SpinBox).value = float(size.x)
	(ed.get("size_y") as SpinBox).value = float(size.y)
	(ed.get("size_z") as SpinBox).value = float(size.z)
	ed.call("_on_apply_size_all_pressed")
	var dlg: ConfirmationDialog = ed.get("_size_dialog")
	check(dlg != null and dlg.visible, "前置：全局应用入确认框（U12② 强制确认口径）")
	ed.call("_on_size_confirmed")

# ==================== 序① blocks 改尺寸→target 改尺寸→undo/redo 交叉→终态四域各自正确 ====================
func _seq1_blocks_target_undo_redo_cross() -> void:
	_seed_slot_333(1)
	var ed: Control = await _fresh_editor()
	var proj: RefCounted = ed.get("project")
	var sessions: Dictionary = _sessions_of(ed)
	# 步 1：blocks 域 3³→5³（单组件，确认框路径）。
	ed.call("switch_tag", 0)
	_apply_one(ed, Vector3i(5, 5, 5))
	check_eq(proj.call("get_size_for_tag", 0), Vector3i(5, 5, 5), "序①：blocks 应用后=5³")
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(3, 3, 3), "序①：blocks 改尺寸后 target 域零牵连（用户主诉反向）")
	check(int((sessions[0] as RefCounted).cells.size()) == 125, "序①：blocks 重生实心 125")
	# 步 2：target 域 3³→2³。
	ed.call("switch_tag", 1)
	_apply_one(ed, Vector3i(2, 2, 2))
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(2, 2, 2), "序①：target 应用后=2³（独立字段）")
	check_eq(proj.call("get_size_for_tag", 0), Vector3i(5, 5, 5), "序①：target 改尺寸后 blocks 域零牵连（用户主诉正向）")
	check(int((sessions[1] as RefCounted).cells.size()) == 8, "序①：target 重生实心 8")
	# 步 3：undo/redo 交叉——先 target 后 blocks，逐态互验。
	ed.call("_apply_undo")   # target undo
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(3, 3, 3), "序①：target undo 后尺寸复原 3³")
	check(int((sessions[1] as RefCounted).cells.size()) == 0, "序①：target undo 后格群还原空集")
	check_eq(proj.call("get_size_for_tag", 0), Vector3i(5, 5, 5), "序①：target undo 不波及 blocks 尺寸（交叉序）")
	ed.call("_apply_redo")   # target redo
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(2, 2, 2), "序①：target redo 复现 2³")
	ed.call("switch_tag", 0)
	ed.call("_apply_undo")   # blocks undo（在 target 域操作往返之后——历史完好性前置）
	check_eq(proj.call("get_size_for_tag", 0), Vector3i(3, 3, 3), "序①：blocks undo 后尺寸复原 3³")
	check(int((sessions[0] as RefCounted).cells.size()) == 27, "序①：blocks undo 后格群还原 27")
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(2, 2, 2), "序①：blocks undo 不波及 target 尺寸（交叉序）")
	ed.call("_apply_redo")   # blocks redo
	check_eq(proj.call("get_size_for_tag", 0), Vector3i(5, 5, 5), "序①：blocks redo 复现 5³")
	check(int((sessions[0] as RefCounted).cells.size()) == 125, "序①：blocks redo 复现实心 125")
	# 终态四域各自正确（四域异值终态锁：block 5³ / target 2³ / join 3³ / final 3³）。
	var piece: Dictionary = proj.call("get_piece")
	check_eq(proj.call("get_size_for_tag", 2), Vector3i(3, 3, 3), "序①：终态 join 域=3³（全程零操作零牵连）")
	check_eq(proj.call("get_size_for_tag", 3), Vector3i(3, 3, 3), "序①：终态 final 域=3³（全程零操作零牵连）")
	check_eq(piece.get("block_size", {}), {"x": 5, "y": 5, "z": 5}, "序①：终态 block_size 落域字段 5³")
	check_eq(piece.get("target_size", null), {"x": 2, "y": 2, "z": 2}, "序①：终态 target_size 独立字段 2³")
	check(int((sessions[2] as RefCounted).cells.size()) == 0 and int((sessions[3] as RefCounted).cells.size()) == 0,
		"序①：终态 join/final 格群空集（零牵连）")

# ==================== 序② 全局应用→单域改→undo→redo ====================
func _seq2_global_then_single_then_undo_redo() -> void:
	_seed_slot_333(1)
	var ed: Control = await _fresh_editor()
	var proj: RefCounted = ed.get("project")
	var sessions: Dictionary = _sessions_of(ed)
	# 前置：tag1 造 1 个撤销单元（全局应用将按 U12③ 清非发起页栈）。
	ed.call("switch_tag", 1)
	ed.call("_on_add_requested", [Vector3i(0, 0, 0)])
	check(int((sessions[1] as RefCounted).undo_stack.size()) == 1, "序②：前置 tag1 入栈 1 单元")
	# 步 1：全局应用 4×3×3（四域各写各字段）。
	ed.call("switch_tag", 0)
	_apply_all(ed, Vector3i(4, 3, 3))
	for tag: int in [0, 1, 2, 3]:
		check_eq(proj.call("get_size_for_tag", tag), Vector3i(4, 3, 3), "序②：全局应用后 tag%d 域=4×3×3" % tag)
	check(int((sessions[0] as RefCounted).cells.size()) == 36, "序②：全局应用后 blocks 重生 36")
	check((sessions[1] as RefCounted).undo_stack.is_empty(), "序②：全局应用清非发起页 tag1 栈（U12③ 全局分支保持）")
	# 步 2：单域改——join 域 4×3×3→2³。
	ed.call("switch_tag", 2)
	_apply_one(ed, Vector3i(2, 2, 2))
	check_eq(proj.call("get_size_for_tag", 2), Vector3i(2, 2, 2), "序②：join 单域改后=2³")
	check_eq(proj.call("get_size_for_tag", 0), Vector3i(4, 3, 3), "序②：join 单域改不波及 blocks（单域应用 affected={2}）")
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(4, 3, 3), "序②：join 单域改不波及 target")
	# 步 3：undo——join 回 4×3×3，其余域零变化。
	ed.call("_apply_undo")
	check_eq(proj.call("get_size_for_tag", 2), Vector3i(4, 3, 3), "序②：undo 后 join 复原 4×3×3")
	check(int((sessions[2] as RefCounted).cells.size()) == 36, "序②：undo 后 join 格群重生还原 36")
	check_eq(proj.call("get_size_for_tag", 0), Vector3i(4, 3, 3), "序②：join undo 不波及 blocks")
	# 步 4：redo——join 复现 2³。
	ed.call("_apply_redo")
	check_eq(proj.call("get_size_for_tag", 2), Vector3i(2, 2, 2), "序②：redo 后 join 复现 2³")
	# 终态：blocks/target/final=4×3×3（36/36/36），join=2³（8）。
	check(int((sessions[0] as RefCounted).cells.size()) == 36 and int((sessions[1] as RefCounted).cells.size()) == 36
		and int((sessions[2] as RefCounted).cells.size()) == 8 and int((sessions[3] as RefCounted).cells.size()) == 36,
		"序②：终态四域格群 {36,36,8,36}")

# ==================== 序③ 单域改→全局应用→undo/redo（全局复合单元回放四域） ====================
func _seq3_single_then_global_then_undo() -> void:
	_seed_slot_333(1)
	var ed: Control = await _fresh_editor()
	var proj: RefCounted = ed.get("project")
	var sessions: Dictionary = _sessions_of(ed)
	# 步 1：单域改——blocks 3³→5³。
	_apply_one(ed, Vector3i(5, 5, 5))
	check_eq(proj.call("get_size_for_tag", 0), Vector3i(5, 5, 5), "序③：前置 blocks 单域改=5³")
	# 步 2：全局应用 4×3×3（四域统一，发起页 tag0）。
	_apply_all(ed, Vector3i(4, 3, 3))
	for tag: int in [0, 1, 2, 3]:
		check_eq(proj.call("get_size_for_tag", tag), Vector3i(4, 3, 3), "序③：全局应用后 tag%d 域=4×3×3" % tag)
	var cp: Dictionary = ((sessions[0] as RefCounted).undo_stack.back() as Dictionary).get("compound", {})
	check((cp.get("old_sizes", {}) as Dictionary).size() == 4, "序③：全局复合单元 old_sizes 四域（含单域改后的 5³ 旧值）")
	# 步 3：undo——全局单元回放四域（blocks 复原到 5³ 而非 3³：old_sizes 记单域改后实况）。
	ed.call("_apply_undo")
	check_eq(proj.call("get_size_for_tag", 0), Vector3i(5, 5, 5), "序③：undo 回放 blocks=5³（单域改后旧值，全局单元四域回放）")
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(3, 3, 3), "序③：undo 回放 target=3³")
	check_eq(proj.call("get_size_for_tag", 2), Vector3i(3, 3, 3), "序③：undo 回放 join=3³")
	check_eq(proj.call("get_size_for_tag", 3), Vector3i(3, 3, 3), "序③：undo 回放 final=3³")
	check(int((sessions[0] as RefCounted).cells.size()) == 125, "序③：undo 回放 blocks 格群=125（5³ 实心）")
	check(int((sessions[1] as RefCounted).cells.size()) == 0 and int((sessions[2] as RefCounted).cells.size()) == 0
		and int((sessions[3] as RefCounted).cells.size()) == 0, "序③：undo 回放 target/join/final 格群=空集（3³ 空域旧值）")
	check((sessions[0] as RefCounted).undo_stack.is_empty(), "序③：undo 后发起页栈空（全局单元已消费）")
	# 步 4：redo——四域复现 4×3×3。
	ed.call("_apply_redo")
	for tag: int in [0, 1, 2, 3]:
		check_eq(proj.call("get_size_for_tag", tag), Vector3i(4, 3, 3), "序③：redo 复现 tag%d 域=4×3×3" % tag)
	check(int((sessions[0] as RefCounted).cells.size()) == 36, "序③：redo 复现 blocks 重生 36")

# ==================== 序④ 跨标签编辑终极断言：blocks 历史在 target 域操作后完好可用 ====================
func _seq4_cross_tag_history_survival() -> void:
	_seed_slot_333(1)
	var ed: Control = await _fresh_editor()
	var proj: RefCounted = ed.get("project")
	var sessions: Dictionary = _sessions_of(ed)
	# 步 1：blocks 挖 1 格（撤销历史 1 单元）。
	ed.call("_on_dig_requested", [Vector3i(0, 0, 0)])
	check(int((sessions[0] as RefCounted).cells.size()) == 26 and int((sessions[0] as RefCounted).undo_stack.size()) == 1,
		"序④：前置 blocks 挖格 26/入栈 1")
	# 步 2：切 target 域改尺寸（跨标签操作）。
	ed.call("switch_tag", 1)
	_apply_one(ed, Vector3i(2, 2, 2))
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(2, 2, 2), "序④：target 域尺寸操作生效（前置）")
	# 步 3：回 blocks——用户主诉终极断言：blocks 撤销历史在 target 域操作后完好可用。
	ed.call("switch_tag", 0)
	check(int((sessions[0] as RefCounted).undo_stack.size()) == 1 and bool((sessions[0] as RefCounted).can_undo()),
		"序④：blocks 撤销历史在 target 域操作后完好（用户「撤销历史被清」主诉直断言）")
	check(int((sessions[0] as RefCounted).cells.size()) == 26, "序④：blocks 格群未被 target 域操作牵连（仍 26）")
	# 步 4：undo 尺寸（target 域）。
	ed.call("switch_tag", 1)
	ed.call("_apply_undo")
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(3, 3, 3), "序④：undo 尺寸——target 复原 3³")
	# 步 5：undo 挖格（blocks 域）——跨标签两域 undo 序交替。
	ed.call("switch_tag", 0)
	ed.call("_apply_undo")
	check(int((sessions[0] as RefCounted).cells.size()) == 27, "序④：undo 挖格——blocks 还原 27")
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(3, 3, 3), "序④：blocks undo 挖格不波及 target 尺寸")
	# 步 6：redo 全链（挖格→尺寸反向重放）。
	ed.call("_apply_redo")
	check(int((sessions[0] as RefCounted).cells.size()) == 26, "序④：redo 全链——blocks 挖格复现 26")
	ed.call("switch_tag", 1)
	ed.call("_apply_redo")
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(2, 2, 2), "序④：redo 全链——target 复现 2³")
	check(int((sessions[1] as RefCounted).cells.size()) == 8, "序④：redo 全链——target 重生 8")
	# 终态四域：{3³:26, 2³:8, 3³:0, 3³:0}。
	check_eq(proj.call("get_size_for_tag", 0), Vector3i(3, 3, 3), "序④：终态 blocks=3³")
	check_eq(proj.call("get_size_for_tag", 2), Vector3i(3, 3, 3), "序④：终态 join=3³（零牵连）")
	check_eq(proj.call("get_size_for_tag", 3), Vector3i(3, 3, 3), "序④：终态 final=3³（零牵连）")

# ==================== 序⑤ 试玩内挖除/加块→退出试玩→编辑态逐字节不变（内存+磁盘双断言） ====================
func _seq5_playtest_isolation_byte_snapshots() -> void:
	_seed_slot_333(1)
	var ed: Control = await _fresh_editor()
	var sessions: Dictionary = _sessions_of(ed)
	# 编辑态造历史：blocks 挖 1 格、target 加 1 格（各自撤销栈各 1 单元）。
	ed.call("_on_dig_requested", [Vector3i(0, 0, 0)])
	ed.call("switch_tag", 1)
	ed.call("_on_add_requested", [Vector3i(1, 1, 1)])
	check(int((sessions[0] as RefCounted).undo_stack.size()) == 1 and int((sessions[1] as RefCounted).undo_stack.size()) == 1,
		"序⑤：前置 blocks/target 各入栈 1 单元")
	ed.call("_autosave_current")   # 编辑态落盘（dig/add 内部已自动保存，幂等补一次）
	# 双基准：内存快照 + 磁盘五文件快照。
	var mem_before: Dictionary = _memory_snapshot(ed)
	var disk_before: Dictionary = _disk_snapshot(1)
	# 试玩内挖除 + 加块（加块在试玩被守卫封死=零操作断言）。
	ed.call("_enter_playtest")
	check(bool(ed.get("_in_playtest")), "序⑤：进入试玩态（前置）")
	var ps: RefCounted = ed.get("_playtest_session")
	ed.call("_on_dig_requested", [Vector3i(0, 1, 0), Vector3i(1, 1, 1), Vector3i(2, 0, 2)])
	check(int(ps.cells.size()) == 23, "序⑤：试玩内挖除 3 格落到临时会话（26-3=23）")
	var ps_size_before: int = ps.cells.size()
	ed.call("_on_add_requested", [Vector3i(0, 0, 0)])
	check(int(ps.cells.size()) == ps_size_before, "序⑤：试玩内加块被守卫封死（零操作，§8.1 试玩=挖除）")
	# 退出试玩。
	ed.call("_do_exit_playtest")
	check(not bool(ed.get("_in_playtest")), "序⑤：退出试玩态（前置）")
	# 双断言 A：内存逐字节不变（格群/四域尺寸/撤销栈/重做栈/项目全量数据）。
	var mem_after: Dictionary = _memory_snapshot(ed)
	check(mem_after["cells"] == mem_before["cells"], "序⑤：退出试玩后四域格群逐字节不变（内存快照）")
	check(mem_after["sizes"] == mem_before["sizes"], "序⑤：退出试玩后四域尺寸逐字节不变（内存快照）")
	check(mem_after["undo"] == mem_before["undo"], "序⑤：退出试玩后撤销栈逐字节不变（内存快照；用户「撤销历史被清」主诉——试玩进出清历史必红）")
	check(mem_after["redo"] == mem_before["redo"], "序⑤：退出试玩后重做栈逐字节不变（内存快照）")
	check(mem_after["data"] == mem_before["data"], "序⑤：退出试玩后项目全量数据逐字节不变（snapshot_data 对账）")
	# 双断言 B：磁盘零 diff（退出自动保存=load→save 幂等序列化，字节级等价）。
	var disk_after: Dictionary = _disk_snapshot(1)
	check(_disk_equal(disk_before, disk_after), "序⑤：试玩进出磁盘五文件零 diff（逐字节）")
	# 历史功能可用性收口：blocks undo 仍能还原挖格（不只是栈结构在场）。
	ed.call("switch_tag", 0)
	ed.call("_apply_undo")
	check(int((sessions[0] as RefCounted).cells.size()) == 27, "序⑤：试玩往返后 blocks 历史功能可用（undo 还原 27）")

# ==================== 序⑥ 试玩进出→尺寸应用→undo 链行为 ====================
func _seq6_playtest_roundtrip_undo_chain() -> void:
	_seed_slot_333(1)
	var ed: Control = await _fresh_editor()
	var proj: RefCounted = ed.get("project")
	var sessions: Dictionary = _sessions_of(ed)
	ed.call("_on_dig_requested", [Vector3i(1, 1, 1)])   # 编辑历史 1 单元
	# 试玩进出（不含挖除——纯往返）。
	ed.call("_enter_playtest")
	ed.call("_on_dig_requested", [Vector3i(0, 0, 0)])
	ed.call("_do_exit_playtest")
	check(int((sessions[0] as RefCounted).undo_stack.size()) == 1 and bool((sessions[0] as RefCounted).can_undo()),
		"序⑥：试玩纯往返后编辑撤销历史完好（可 undo 前提）")
	# 尺寸应用（试玩退出后）：blocks 3³→5³。
	_apply_one(ed, Vector3i(5, 5, 5))
	check_eq(proj.call("get_size_for_tag", 0), Vector3i(5, 5, 5), "序⑥：试玩退出后尺寸应用生效 5³")
	check(int((sessions[0] as RefCounted).cells.size()) == 125, "序⑥：应用后重生实心 125")
	# undo 链行为：undo→复原；redo→复现；再 undo→复原（三态一致）。
	ed.call("_apply_undo")
	check_eq(proj.call("get_size_for_tag", 0), Vector3i(3, 3, 3), "序⑥：undo 后尺寸复原 3³（试玩往返不吞历史）")
	check(int((sessions[0] as RefCounted).cells.size()) == 26, "序⑥：undo 后格群还原 26（含试玩前挖格）")
	ed.call("_apply_redo")
	check_eq(proj.call("get_size_for_tag", 0), Vector3i(5, 5, 5), "序⑥：redo 复现 5³")
	ed.call("_apply_undo")
	check_eq(proj.call("get_size_for_tag", 0), Vector3i(3, 3, 3), "序⑥：再 undo 复原 3³（链式三态一致）")
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(3, 3, 3), "序⑥：全链 target 域零牵连")

# ==================== 序⑦ 切槽位→草稿/撤销栈/载入数据隔离（切走再切回不串） ====================
func _seq7_slot_switch_isolation() -> void:
	_seed_slot_333(1)
	_seed_slot_custom(2, Vector3i(2, 2, 2), "第二关")   # 槽 2 异构内容 2³
	var ed: Control = await _fresh_editor()
	var proj: RefCounted = ed.get("project")
	var sessions: Dictionary = _sessions_of(ed)
	# 槽 1 编辑：挖 1 格 + 草稿改 5³（草稿不落盘=切槽必丢的隔离面）。
	ed.call("_on_dig_requested", [Vector3i(0, 0, 0)])
	(ed.get("size_x") as SpinBox).value = 5.0
	check(ed.get("_size_draft") == Vector3i(5, 3, 3), "序⑦：前置槽 1 草稿=5×3×3")
	# 切走：槽 2 载入隔离态。
	ed.call("_switch_slot", 2)
	check_eq(proj.call("get_block_size"), Vector3i(2, 2, 2), "序⑦：切槽 2 载入 2³（载入数据隔离——不串槽 1 的 3³）")
	check(int((sessions[0] as RefCounted).cells.size()) == 8, "序⑦：槽 2 blocks=8 实心（2³）")
	check(ed.get("_size_draft") == Vector3i(2, 2, 2), "序⑦：草稿随载入重置 2³（槽 1 草稿 5×3×3 不串入）")
	check((ed.get("size_x") as SpinBox).value == 2.0, "序⑦：SpinBox 回填载入尺寸 2")
	check((sessions[0] as RefCounted).undo_stack.is_empty(), "序⑦：切槽后撤销栈为空（新工程新历史，槽 1 历史不串入）")
	# 切回：槽 1 数据=其盘上态（挖格已随切槽自动保存），草稿回 3³。
	ed.call("_switch_slot", 1)
	check_eq(proj.call("get_block_size"), Vector3i(3, 3, 3), "序⑦：切回槽 1 载入 3³")
	check(int((sessions[0] as RefCounted).cells.size()) == 26, "序⑦：槽 1 挖格随切槽自动保存并载回（26，切走再切回数据不丢不串）")
	check(ed.get("_size_draft") == Vector3i(3, 3, 3), "序⑦：草稿回填槽 1 尺寸 3³（无槽 2 残留）")
	check((sessions[0] as RefCounted).undo_stack.is_empty(), "序⑦：切回后撤销栈为空（盘上即权威，不复活旧历史）")
	# 槽间内存态与各自盘上态对账。
	var p2: RefCounted = LP.new()
	check(bool(p2.call("load_from_text", SLOTS.load_slot_text(2, _sandbox_root))), "序⑦：槽 2 盘上档可装载（前置）")
	check_eq(p2.call("get_block_size"), Vector3i(2, 2, 2), "序⑦：槽 2 盘上档=2³（切槽往返零写入串扰）")

# ==================== 序⑧ 切槽位中途自动保存→另一槽零污染（五文件逐字节） ====================
func _seq8_slot_switch_autosave_no_pollution() -> void:
	_seed_slot_333(1)
	_seed_slot_custom(2, Vector3i(2, 2, 2), "第二关")
	var ed: Control = await _fresh_editor()
	var proj: RefCounted = ed.get("project")
	var sessions: Dictionary = _sessions_of(ed)
	var b1: Dictionary = _disk_snapshot(2)   # 槽 2 基线 A（未经过编辑器 apply_auto_meta 的原盘态）
	# 槽 1 编辑 + 切槽（切槽中途自动保存写的是槽 1，槽 2 必须零污染）。
	ed.call("_on_dig_requested", [Vector3i(2, 2, 2)])
	ed.call("_switch_slot", 2)
	check(_disk_equal(_disk_snapshot(2), b1), "序⑧：切到槽 2 后槽 2 五文件逐字节零污染（切槽自动保存只写被切离槽）")
	check_eq(proj.call("get_block_size"), Vector3i(2, 2, 2), "序⑧：槽 2 载入正常（前置）")
	# 切回槽 1（此时自动保存写槽 2——apply_auto_meta 内存口径落盘，属载入后保存的既有语义），
	# 之后再次切入槽 2：槽 2 相对「切离时盘态」零变化。
	ed.call("_switch_slot", 1)
	var b2: Dictionary = _disk_snapshot(2)   # 槽 2 基线 B（切离时盘态）
	ed.call("_on_dig_requested", [Vector3i(1, 1, 1)])
	ed.call("_switch_slot", 2)
	check(_disk_equal(_disk_snapshot(2), b2), "序⑧：第二次切入槽 2 仍零污染（五文件逐字节==切离时盘态）")
	check(_disk_equal(_disk_snapshot(2), b1) or String(_file_text_of(2, "level.json")).contains("第二关"),
		"序⑧：槽 2 盘面内容仍为槽 2 自身数据（无槽 1 内容串写）")
	# 被切离槽（槽 1）编辑确已落盘（切槽自动保存的正面证据）。
	check(int((sessions[0] as RefCounted).cells.size()) == 8, "序⑧：槽 2 载入 8 格（前置自证）")
	ed.call("_switch_slot", 1)
	check(int((sessions[0] as RefCounted).cells.size()) == 25, "序⑧：槽 1 两次挖格随两次切槽自动保存（27-2=25）")
	var p1: RefCounted = LP.new()
	check(bool(p1.call("load_from_text", SLOTS.load_slot_text(1, _sandbox_root))), "序⑧：槽 1 盘上档可装载（前置）")
	check_eq(p1.call("get_voxel_set", LP.TAG_BLOCKS).size(), 25, "序⑧：槽 1 盘上档 25 格（自动保存正面证据）")

func _file_text_of(slot: int, file_name: String) -> String:
	var fp := _sandbox_root + ("level_%d/" % slot) + file_name
	return FileAccess.get_file_as_string(fp) if FileAccess.file_exists(fp) else ""

# ==================== 序⑨ 迁移后槽（V-E2 产物）上抽二复验（序①交叉链 + 序⑤试玩隔离） ====================
func _seq9_migrated_slot_reverify() -> void:
	_seed_slot_333(1)
	# 槽 3 播种旧单文件（清拆分产物→原样 level.json）。
	var fixture_text: String = FileAccess.get_file_as_string(FIXTURE)
	check(_seed_slot_legacy(3, fixture_text), "序⑨：槽 3 播种旧单文件成功（前置）")
	var ed: Control = await _fresh_editor()
	var proj: RefCounted = ed.get("project")
	var sessions: Dictionary = _sessions_of(ed)
	ed.call("_switch_slot", 3)   # 载入即迁移（V-E2）
	check(FileAccess.file_exists(_sandbox_root + "level_3/level_legacy.json.bak"),
		"序⑨：迁移后 .bak 留档在场（V-E2 产物自证）")
	for name: String in FIVE_FILES:
		check(FileAccess.file_exists(_sandbox_root + "level_3/" + name), "序⑨：迁移后 %s 在场（五文件契约）" % name)
	check_eq(proj.call("get_block_size"), Vector3i(8, 3, 8), "序⑨：迁移档载入 block_size=8×3×8（前置）")
	# 复验 A（序①交叉链在迁移档上）：blocks 8×3×8→5³→undo→redo，undo/redo 链可用。
	# 注：迁移档无 target_size 键（E1 零迁移口径），tag1 读=live 回落 block_size——
	# blocks 应用 5³ 后 target 读值随回落变 5³ 属 E1 落定行为（test_v_editor_size_domains P4 锁定），
	# 非跨域污染；undo/redo 链复原后读值同步回落 8×3×8。
	_apply_one(ed, Vector3i(5, 5, 5))
	check_eq(proj.call("get_size_for_tag", 0), Vector3i(5, 5, 5), "序⑨A：迁移档 blocks 应用=5³")
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(5, 5, 5),
		"序⑨A：迁移档 target 读值=回落 block_size（E1 零迁移 live 回落口径，非独立写）")
	ed.call("_apply_undo")
	check_eq(proj.call("get_size_for_tag", 0), Vector3i(8, 3, 8), "序⑨A：undo 复原 8×3×8（迁移档撤销链可用）")
	check_eq(int(proj.call("get_voxel_set", LP.TAG_BLOCKS).size()), 192, "序⑨A：undo 后 blocks 还原 192 格（迁移数据零丢失）")
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(8, 3, 8), "序⑨A：undo 后 target 读值回落复原 8×3×8")
	ed.call("_apply_redo")
	check_eq(proj.call("get_size_for_tag", 0), Vector3i(5, 5, 5), "序⑨A：redo 复现 5³")
	# 复验 B（序⑤试玩隔离在迁移档上）：试玩挖除→退出→内存+磁盘逐字节不变。
	ed.call("_autosave_current")
	var mem_before: Dictionary = _memory_snapshot(ed)
	var disk_before: Dictionary = _disk_snapshot(3)
	ed.call("_enter_playtest")
	ed.call("_on_dig_requested", [Vector3i(0, 0, 0), Vector3i(7, 2, 7)])
	ed.call("_do_exit_playtest")
	var mem_after: Dictionary = _memory_snapshot(ed)
	check(mem_after["cells"] == mem_before["cells"] and mem_after["sizes"] == mem_before["sizes"],
		"序⑨B：迁移档试玩往返格群/尺寸逐字节不变")
	check(mem_after["undo"] == mem_before["undo"], "序⑨B：迁移档试玩往返撤销栈逐字节不变")
	check(_disk_equal(_disk_snapshot(3), disk_before), "序⑨B：迁移档试玩往返磁盘五文件零 diff")
	check(FileAccess.file_exists(_sandbox_root + "level_3/level_legacy.json.bak"),
		"序⑨B：试玩往返后 .bak 仍留档（迁移产物不被编辑流触碰）")

# ==================== 序⑩ copy_base 审视：目标域尺寸裁剪落格 + 零跨域携带 ====================
func _seq10_copy_base_domain_clipping() -> void:
	_seed_slot_333(1)
	var ed: Control = await _fresh_editor()
	var proj: RefCounted = ed.get("project")
	var sessions: Dictionary = _sessions_of(ed)
	var btn: Button = ed.get("btn_copy_base")
	# 前置：blocks 4³ 挖 1 格（63 格，含 2³ 外格 (3,0,0)）；target 2³ 挖 1 格（7 格）。
	_apply_one(ed, Vector3i(4, 4, 4))
	ed.call("_on_dig_requested", [Vector3i(3, 3, 3)])
	check(int((sessions[0] as RefCounted).cells.size()) == 63, "序⑩：前置 blocks=63 格（4³-1）")
	ed.call("switch_tag", 1)
	_apply_one(ed, Vector3i(2, 2, 2))
	ed.call("_on_dig_requested", [Vector3i(0, 0, 0)])
	check(int((sessions[1] as RefCounted).cells.size()) == 7, "序⑩：前置 target=7 格（2³-1）")
	# 守卫面：tag0 页按钮隐藏 + tag0 调用零操作。
	ed.call("switch_tag", 0)
	check(btn != null and not btn.visible, "序⑩：blocks 页无复制初始块按钮（§7.3 语义保持）")
	var s0_before: int = (sessions[0] as RefCounted).cells.size()
	var st0_before: int = (sessions[0] as RefCounted).undo_stack.size()
	ed.call("_on_copy_base_pressed")
	check(int((sessions[0] as RefCounted).cells.size()) == s0_before and (sessions[0] as RefCounted).undo_stack.size() == st0_before,
		"序⑩：active_tag==0 调用零操作（守卫保持）")
	# 主体：target 页复制基底——目标域尺寸为权威，源域超界格裁剪。
	ed.call("switch_tag", 1)
	check(btn != null and btn.visible, "序⑩：target 页复制按钮可见（前置）")
	ed.call("_on_copy_base_pressed")
	var expected: Dictionary = {}
	for c: Variant in sessions[0].cells:
		var cell: Vector3i = c
		if cell.x < 2 and cell.y < 2 and cell.z < 2:
			expected[cell] = true
	check_eq((sessions[1] as RefCounted).cells, expected, "序⑩：复制后 target 格群=blocks∩target域（源域超界格裁剪，旧全量复制必红）")
	check(not (sessions[1] as RefCounted).cells.has(Vector3i(3, 0, 0)), "序⑩：超界格 (3,0,0) 未流入 target 域（跨域污染直断言）")
	check_eq(int(proj.call("count_over_domain_cells")), 0, "序⑩：复制后全项目超域计数=0（游戏加载零裁剪意外）")
	# 零跨域携带：源域/目标域尺寸与源域格群零变化。
	check_eq(proj.call("get_size_for_tag", 0), Vector3i(4, 4, 4), "序⑩：copy_base 不携带域尺寸——block_size 逐字节不变")
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(2, 2, 2), "序⑩：copy_base 不携带域尺寸——target_size 逐字节不变")
	check_eq(proj.call("get_size_for_tag", 2), Vector3i(3, 3, 3), "序⑩：copy_base 零触碰 join 域")
	check_eq(proj.call("get_size_for_tag", 3), Vector3i(3, 3, 3), "序⑩：copy_base 零触碰 final 域")
	check_eq((sessions[0] as RefCounted).cells.size(), 63, "序⑩：源域 blocks 格群零污染（63 不变）")
	# 撤销单元可用：undo 还原复制前 7 格，redo 复现裁剪后 8 格。
	ed.call("_apply_undo")
	check_eq((sessions[1] as RefCounted).cells.size(), 7, "序⑩：undo 还原复制前 target=7 格")
	ed.call("_apply_redo")
	check_eq((sessions[1] as RefCounted).cells.size(), 8, "序⑩：redo 复现裁剪后 target=8 格")
	# 幂等：再点一次=零差集不入栈（重复点击=再次覆盖语义，同集零单元）。
	var st_before: int = (sessions[1] as RefCounted).undo_stack.size()
	ed.call("_on_copy_base_pressed")
	check((sessions[1] as RefCounted).undo_stack.size() == st_before and (sessions[1] as RefCounted).cells.size() == 8,
		"序⑩：同集重复复制零差集不入栈（幂等语义保持）")
	# 试玩守卫：试玩中调用零操作。
	ed.call("_enter_playtest")
	var ps: RefCounted = ed.get("_playtest_session")
	var ps_before: int = ps.cells.size()
	ed.call("_on_copy_base_pressed")
	check(ps != null and ps.cells.size() == ps_before, "序⑩：试玩中 copy_base 零操作（_in_playtest 守卫保持）")
	ed.call("_do_exit_playtest")

# ==================== 序⑪ tag1 改→tag0/2/3 零变化 + undo 后 target_size 复原（规格 §9.6-1 具名） ====================
func _seq11_tag1_change_others_untouched() -> void:
	_seed_slot_333(1)
	var ed: Control = await _fresh_editor()
	var proj: RefCounted = ed.get("project")
	var sessions: Dictionary = _sessions_of(ed)
	# 基线：四域格群/尺寸逐字节留痕。
	var mem_before: Dictionary = _memory_snapshot(ed)
	# tag1 发起 5×4×3。
	ed.call("switch_tag", 1)
	_apply_one(ed, Vector3i(5, 4, 3))
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(5, 4, 3), "序⑪：tag1 应用后=5×4×3")
	check(int((sessions[1] as RefCounted).cells.size()) == 60, "序⑪：tag1 重生实心 60")
	# tag0/2/3 三域逐字节零变化（尺寸+格群+撤销栈）。
	var mem_after: Dictionary = _memory_snapshot(ed)
	check_eq(proj.call("get_size_for_tag", 0), Vector3i(3, 3, 3), "序⑪：tag1 改后 tag0 尺寸零变化")
	check_eq(proj.call("get_size_for_tag", 2), Vector3i(3, 3, 3), "序⑪：tag1 改后 tag2 尺寸零变化")
	check_eq(proj.call("get_size_for_tag", 3), Vector3i(3, 3, 3), "序⑪：tag1 改后 tag3 尺寸零变化")
	for tag: int in [0, 2, 3]:
		var sess: RefCounted = sessions[tag]
		check((sess.cells as Dictionary) == (mem_before["cells"] as Dictionary)[tag],
			"序⑪：tag1 改后 tag%d 格群逐字节不变" % tag)
		check(_dup_units(sess.undo_stack) == (mem_before["undo"] as Dictionary)[tag],
			"序⑪：tag1 改后 tag%d 撤销栈逐字节不变" % tag)
	# undo 后 target_size 复原。
	ed.call("_apply_undo")
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(3, 3, 3), "序⑪：undo 后 target_size 复原 3³")
	check(int((sessions[1] as RefCounted).cells.size()) == 0, "序⑪：undo 后 target 格群还原空集")
	check_eq(proj.call("get_size_for_tag", 0), Vector3i(3, 3, 3), "序⑪：undo 后 tag0 仍 3³（零牵连）")
	# redo 复现。
	ed.call("_apply_redo")
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(5, 4, 3), "序⑪：redo 复现 5×4×3")
