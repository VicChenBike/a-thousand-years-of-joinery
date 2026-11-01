extends "res://tests/test_base.gd"
## 批次 AA / 域 W9（规格 §12）编辑器侧同构件红测——TDD 先行。
## 覆盖：W9-8(P3-9) 撤销栈 MAX_UNDO=200 截断（voxel_edit_ops 同构件）、
##   W9-4(P3-5) _atomic_write_text `.bak` 回滚失败保留 tmp + 告警（源契约，主游戏 save_game 同构）。
## 摄像头红线：零摄像头；清档纪律：本件不触 user:// 存档（编辑器槽位元数据亦零写入）。

const S := preload("res://scripts/voxel_edit_ops.gd")
const LEVEL_SLOTS_SRC := "res://scripts/level_slots.gd"

func _func_body(src: String, sig: String) -> String:
	var f0: int = src.find(sig)
	if f0 < 0:
		return ""
	var f1: int = src.find("\nstatic func ", f0 + 1)
	var f2: int = src.find("\nfunc ", f0 + 1)
	var f1b: int = f1 if f1 > f0 else src.length()
	var f2b: int = f2 if f2 > f0 else src.length()
	return src.substr(f0, mini(f1b, f2b) - f0)

func _cells(n: int) -> Dictionary:
	## n 个互异格（10×30 平面，z=0；n≤300）
	var out: Dictionary = {}
	for i: int in range(n):
		out[Vector3i(i % 10, i / 10, 0)] = true
	return out

func _initialize() -> void:
	print("== test_aa_w9_editor（批次 AA / W9 编辑器侧）==")
	_w9_8_max_undo_dig()
	_w9_8_max_undo_compound()
	_w9_8_max_undo_const()
	_w9_4_bak_rollback_contract()
	finish()

# ---------- W9-8（P3-9）撤销栈上限：真实 dig 入栈 300 次 ----------
func _w9_8_max_undo_dig() -> void:
	print("-- W9-8 编辑器 dig 撤销栈截断 --")
	var s = S.new()
	s.setup(_cells(300))
	check_eq(s.undo_stack.size(), 0, "前置：setup 后栈空")
	for i: int in range(300):
		s.dig({Vector3i(i % 10, i / 10, 0): true})
	check(s.undo_stack.size() <= 200, "W9-8a（编）：入栈 300 次 → 栈深 ≤200（红：旧实现 300）")
	check_eq(s.undo_stack.size(), 200, "W9-8b（编）：截断后恒 200")
	# 丢最旧：保留段首条应为第 101 次 dig（索引 100），末条为第 300 次
	if s.undo_stack.size() == 200:
		var first_unit: Dictionary = s.undo_stack[0]
		var last_unit: Dictionary = s.undo_stack[s.undo_stack.size() - 1]
		check_eq((first_unit["removed"] as Array), [Vector3i(0, 10, 0)],
			"W9-8c（编）：丢最旧——保留段首条=第 101 次 dig（0,10,0）")
		check_eq((last_unit["removed"] as Array), [Vector3i(9, 29, 0)],
			"W9-8d（编）：保留段末条=第 300 次 dig（9,29,0）")
	# 截断后撤销链仍可用（弹栈不越界）
	check(bool(s.can_undo()), "W9-8e（编）：截断后仍可撤销")
	s.undo()
	check_eq(s.undo_stack.size(), 199, "W9-8f（编）：撤销一次 → 199")
	check(bool(s.can_redo()), "W9-8g（编）：撤销转入重做栈")
	# 重做回栈同样受上限约束（redo→undo append 点）
	for i: int in range(2):
		s.redo()
	check(s.undo_stack.size() <= 200, "W9-8h（编）：redo 回栈仍 ≤200")

# ---------- W9-8（P3-9）push_compound 入栈点同受截断 ----------
func _w9_8_max_undo_compound() -> void:
	print("-- W9-8 编辑器 push_compound 截断 --")
	var s = S.new()
	s.setup(_cells(4))
	for i: int in range(201):
		s.push_compound({"removed": [], "added": [], "compound": {"tag": "A", "i": i}})
	check(s.undo_stack.size() <= 200, "W9-8i（编）：push_compound 入栈 201 次 → ≤200（红：旧实现 201）")
	check_eq(s.undo_stack.size(), 200, "W9-8j（编）：push_compound 截断后恒 200")
	if s.undo_stack.size() == 200:
		var last_c: Dictionary = s.undo_stack[s.undo_stack.size() - 1]
		check_eq(int((last_c.get("compound", {}) as Dictionary).get("i", -1)), 200,
			"W9-8k（编）：保留最近一条（i=200）")
	# set_cells / add append 点同源受控（一次覆盖入栈后仍不越界）
	s.setup(_cells(300))
	s.set_cells(_cells(150))
	check(s.undo_stack.size() <= 200, "W9-8l（编）：set_cells 入栈后仍 ≤200")
	s.setup(_cells(4))
	for i: int in range(205):
		s.add({Vector3i(i, 9, 9): true})
	check(s.undo_stack.size() <= 200, "W9-8m（编）：add 入栈 205 次后仍 ≤200")

# ---------- W9-8（P3-9）MAX_UNDO 常量真值 ----------
func _w9_8_max_undo_const() -> void:
	print("-- W9-8 编辑器 MAX_UNDO 常量 --")
	var consts: Dictionary = {}
	var probe: RefCounted = S.new()
	var scr: Script = probe.get_script()
	if scr != null:
		consts = scr.get_script_constant_map()
	check_eq(int(consts.get("MAX_UNDO", -1)), 200,
		"W9-8n（编）：MAX_UNDO==200【暂定值·待用户复验】（红：缺失/异值）")
	var src: String = FileAccess.get_file_as_string("res://scripts/voxel_edit_ops.gd")
	check(src.contains("MAX_UNDO"),
		"W9-8o（编）：源码声明 MAX_UNDO 上限（红：旧实现头注「栈深无上限」）")
	check(not src.contains("栈深无上限（规格 §6.4）") or src.contains("MAX_UNDO"),
		"W9-8p（编）：「栈深无上限」旧口径已废止留痕")

# ---------- W9-4（P3-5）.bak 回滚失败保留 tmp（源契约） ----------
func _w9_4_bak_rollback_contract() -> void:
	print("-- W9-4 编辑器 .bak 回滚失败保留 tmp --")
	var src: String = FileAccess.get_file_as_string(LEVEL_SLOTS_SRC)
	var body: String = _func_body(src, "static func _atomic_write_text(")
	check(body != "", "W9-4-0 前置：level_slots._atomic_write_text 可读")
	var i_rb: int = body.find("rename_absolute(bak, path) != OK")
	check(i_rb >= 0, "W9-4a（编）：回滚 rename 返回值已判（红：旧实现返回值被丢弃）")
	if i_rb >= 0:
		var j: int = body.find("remove_absolute(tmp)", i_rb)
		var seg: String = body.substr(i_rb, (j if j > i_rb else body.length()) - i_rb)
		check(seg.contains("push_warning") and seg.contains("return false"),
			"W9-4b（编）：回滚失败分支先告警再 return，tmp 不删（红：旧实现静默吞+删 tmp）")
		check(seg.contains("保留 tmp") or seg.contains("已保留"),
			"W9-4c（编）：告警文案明示 tmp 已保留（留痕）")
	check(body.contains("remove_absolute(bak)"),
		"W9-4d（编）：成功路径 .bak 清理保持（既有语义不回归）")
