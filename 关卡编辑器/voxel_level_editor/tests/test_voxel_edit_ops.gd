extends "res://tests/test_base.gd"
## test_voxel_edit_ops：编辑操作与撤销栈（规格 §11.2 行 2）。
## 覆盖：dig/add/set_cells 集合结果、no-op 不入栈、undo/redo 往返等价、redo 分支作废
## （level_scene.gd:1085 同口径）、四标签栈独立（A 标签 undo 不影响 B）、单元合并
## （一次拖动连放=一个单元，T5）、批量四操作复合（整层挖除/填充/实心/清空）。

const S := preload("res://scripts/voxel_edit_ops.gd")
const LP := preload("res://scripts/level_project.gd")

func _initialize() -> void:
	_dig_add_noop()
	_set_cells_mixed()
	_undo_redo_roundtrip()
	_redo_invalidation()
	_stack_independence()
	_unit_merge()
	_bulk_ops()
	_compound_unit()
	_group_x_compound_arbitrary_keys()
	finish()

## 数组[Vector3i] → 格集（组8 复合撤销单元 removed_by_tag 的 Array→Dictionary 构造）。
func _arr_to_set(arr: Array) -> Dictionary:
	var out: Dictionary = {}
	for c: Variant in arr:
		out[c] = true
	return out

# ============ 组 8：复合撤销单元 remove_no_stack/push_compound（T2a 修复批，14 checks） ============
## 红态：voxel_edit_ops.gd 无 remove_no_stack/push_compound（调用即脚本错误）。行为契约（规格 §3.3）：
## 单元={"removed": Array[发起标签被裁格], "added": [], "compound": {...}}；remove_no_stack 直接移除
## 不入栈、报告与 dig 同构；push_compound 仅入栈+清重做栈，不解释 compound、不改 cells；单元只进发起
## 标签（A）栈，B 标签栈零写入；undo/redo 随单元在双栈原样往返（compound 键保全）。
func _compound_unit() -> void:
	var a = S.new()
	var b = S.new()
	a.setup(LP.solid_cells(Vector3i(3, 3, 3)))
	b.setup({Vector3i(2, 0, 0): true, Vector3i(3, 0, 0): true})
	# A 裁 x=2 平面 9 格（3²），B 裁 2 格（两格 x≥2）
	var a_rm: Dictionary = {}
	for y: int in range(3):
		for z: int in range(3):
			a_rm[Vector3i(2, y, z)] = true
	var b_rm: Dictionary = {Vector3i(2, 0, 0): true, Vector3i(3, 0, 0): true}
	check_eq(a_rm.size(), 9, "组8: A 裁 x=2 平面 9 格")
	check_eq(b_rm.size(), 2, "组8: B 裁 2 格")
	var ra: Dictionary = a.remove_no_stack(a_rm)
	check_eq((ra["hidden"] as Array).size(), 9, "组8: remove_no_stack A 实删 9 格")
	var rb: Dictionary = b.remove_no_stack(b_rm)
	check((rb["hidden"] as Array).size() == 2 and b.cells.is_empty(), "组8: remove_no_stack B 实删 2 格且 B 清空")
	# 前置 dig((0,0,0)) 制造撤销单元（A→17），redo 分支纪律由 push_compound 复核
	a.dig({Vector3i(0, 0, 0): true})
	var by_tag: Dictionary = {0: ra["hidden"], 1: [], 2: [], 3: []}
	a.push_compound({"removed": ra["hidden"], "added": [],
		"compound": {"old_size": Vector3i(3, 3, 3), "new_size": Vector3i(2, 2, 2), "removed_by_tag": by_tag}})
	check_eq(a.undo_stack.size(), 2, "组8: push_compound 后发起栈深 2（dig+compound）")
	check_eq(a.cells.size(), 17, "组8: push_compound 不改 cells（27−9−1=17）")
	check(not a.can_redo(), "组8: push_compound 后 can_redo=false（清重做栈）")
	check_eq(b.undo_stack.size(), 0, "组8: 单元只进发起标签栈，B 栈深 0")
	var u: Dictionary = a.undo()
	check((u["shown"] as Array).size() == 9 and a.cells.size() == 26, "组8: 一次 undo → 26 格且报告 shown=9")
	check(b.cells.is_empty(), "组8: B 会话不自动回放（仍 0 格）")
	check(a.redo_stack.size() == 1 and (a.redo_stack[0] as Dictionary).has("compound"), "组8: redo 栈顶含 compound 键")
	var r: Dictionary = a.redo()
	check((r["hidden"] as Array).size() == 9 and a.cells.size() == 17 \
		and (a.undo_stack[1] as Dictionary).has("compound"), "组8: 一步 redo → 17 格且报告 hidden=9、undo 栈顶仍含 compound")
	check_eq(b.undo_stack.size(), 0, "组8: 全程 B 栈深恒 0")
	# 空载荷单元（removed/added 全空）入栈且 undo/redo 往返 cells 不变（零裁剪应用也入栈，D2 无条件口径）
	var e = S.new()
	e.setup({Vector3i(0, 0, 0): true})
	e.push_compound({"removed": [], "added": [], "compound": {"old_size": Vector3i(3, 3, 3), "new_size": Vector3i(3, 3, 3), "removed_by_tag": {}}})
	e.undo()
	e.redo()
	check(e.undo_stack.size() == 1 and e.cells.size() == 1 and e.redo_stack.is_empty(), "组8: 空载荷单元入栈且 undo/redo 往返 cells 不变（尺寸-only 可撤销）")

# ============ 组 X：复合单元任意键往返保全（本批 W3 新增，2 checks；规格 §6.5） ============
## 固化依据：Session.undo/redo（:99-120）只解释顶层 removed/added 键，compound 键随双栈原样往返
## （voxel_edit_ops.gd:55-56 注释口径）。P0-1 分域回放（editor_main._replay_compound）依赖
## compound.old_sizes/new_sizes/removed_by_tag 原样保全，本组锁该前提。
## 红态定义：对「Session 会丢 compound 任意键」的假想旧实现必红；Session 实现零改动，
## 预期直接绿——按无头实证坑 §1.2-4 免于临时改代码，固化组红态如实留痕于提交体（沿 G18 先例）。
func _group_x_compound_arbitrary_keys() -> void:
	var s = S.new()
	s.setup({Vector3i(0, 0, 0): true})
	s.push_compound({
		"removed": [Vector3i(0, 0, 0)], "added": [],
		"compound": {
			"old_sizes": {0: Vector3i(3, 3, 3)},
			"new_sizes": {0: Vector3i(2, 2, 2)},
			"removed_by_tag": {1: {"removed": [Vector3i(1, 1, 1)], "added": [Vector3i(2, 2, 2)]}},
			"regen": true,
		}})
	s.undo()
	s.redo()
	var unit_back: Dictionary = s.undo_stack.back()
	check_eq(unit_back["compound"]["old_sizes"], {0: Vector3i(3, 3, 3)}, "X: compound.old_sizes {tag:Vector3i} 往返保全")
	var pair_back: Dictionary = unit_back["compound"]["removed_by_tag"][1]
	check(pair_back["removed"] == ([Vector3i(1, 1, 1)] as Array) \
		and pair_back["added"] == ([Vector3i(2, 2, 2)] as Array),
		"X: removed_by_tag[1] 为 {removed, added} 对且值往返保全（P0-1 结构前提）")

func _cells_of(res: Dictionary, key: String) -> int:
	return (res[key] as Array).size()

# ============ 组 1：dig/add 与 no-op 不入栈（8 checks） ============
func _dig_add_noop() -> void:
	var s = S.new()
	s.setup({Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true, Vector3i(2, 0, 0): true})
	# 计划适配留痕（T2-1）：计划原文此处挖 (0,0,0)，与下文 add 断言「已存在 0,0,0 幂等」自相矛盾
	# （0,0,0 已被该 dig 移除，add 必实增 2 格）。就地适配为挖 (1,0,0)，dig/add 断言语义与
	# 组 1 共 8 checks 计数均不变；voxel_edit_ops.gd 实现侧零改动。
	var res: Dictionary = s.dig({Vector3i(1, 0, 0): true, Vector3i(9, 9, 9): true})
	check_eq(_cells_of(res, "hidden"), 1, "组1: dig 实删 1 格（不存在的 9,9,9 忽略）")
	check_eq(s.cells.size(), 2, "组1: dig 后剩 2 格")
	check_eq(s.undo_stack.size(), 1, "组1: dig 入栈 1 单元")
	var res2: Dictionary = s.dig({Vector3i(5, 5, 5): true})
	check(res2["hidden"].is_empty() and s.undo_stack.size() == 1, "组1: 空挖 no-op 不入栈")
	var res3: Dictionary = s.add({Vector3i(5, 5, 5): true, Vector3i(0, 0, 0): true})
	check_eq(_cells_of(res3, "shown"), 1, "组1: add 实增 1 格（已存在 0,0,0 幂等）")
	check_eq(s.cells.size(), 3, "组1: add 后 3 格")
	var res4: Dictionary = s.add({Vector3i(5, 5, 5): true})
	check(res4["shown"].is_empty() and s.undo_stack.size() == 2, "组1: 重复 add no-op 不入栈")
	check(s.can_undo(), "组1: can_undo")

# ============ 组 2：set_cells 混合单元（5 checks） ============
func _set_cells_mixed() -> void:
	var s = S.new()
	var a := Vector3i(1, 1, 1)
	var b := Vector3i(0, 0, 0)
	var c := Vector3i(2, 2, 2)
	s.setup({a: true})
	var res: Dictionary = s.set_cells({b: true, c: true})
	check_eq(_cells_of(res, "hidden"), 1, "组2: set_cells 移除旧集差")
	check_eq(_cells_of(res, "shown"), 2, "组2: set_cells 新增新集差")
	check(s.cells.size() == 2 and s.cells.has(b) and s.cells.has(c), "组2: 覆盖到目标集")
	check_eq(s.undo_stack.size(), 1, "组2: 一个混合单元")
	s.set_cells({b: true, c: true})
	check_eq(s.undo_stack.size(), 1, "组2: 同目标 no-op 不入栈")

# ============ 组 3：undo/redo 往返等价（9 checks） ============
func _undo_redo_roundtrip() -> void:
	var s = S.new()
	s.setup(LP.solid_cells(Vector3i(3, 3, 3)))
	# T4 删除留痕：原 S.layer_cells(3³,1,0) 换为内联字面构建 (x,0,z) 层 9 格（layer_cells 已随批量区删除）。
	var layer: Dictionary = {}
	for x: int in range(3):
		for z: int in range(3):
			layer[Vector3i(x, 0, z)] = true
	var res: Dictionary = s.dig(layer)
	check_eq(s.cells.size(), 18, "组3: 整层挖除后 18 格")
	check_eq(_cells_of(res, "hidden"), 9, "组3: 整层 9 格")
	check_eq(s.undo_stack.size(), 1, "组3: 一个单元")
	var u: Dictionary = s.undo()
	check_eq(s.cells.size(), 27, "组3: undo 恢复 27 格")
	check_eq(_cells_of(u, "shown"), 9, "组3: undo 报告 9 格恢复")
	var r: Dictionary = s.redo()
	check_eq(s.cells.size(), 18, "组3: redo 再删至 18 格")
	check_eq(_cells_of(r, "hidden"), 9, "组3: redo 报告 9 格隐藏")
	var s2 = S.new()
	s2.setup({})
	var u2: Dictionary = s2.undo()
	check(u2["hidden"].is_empty() and u2["shown"].is_empty(), "组3: 空栈 undo 安全零报告")
	check(not s2.can_undo(), "组3: 空栈 can_undo=false")

# ============ 组 4：redo 分支作废（4 checks，level_scene.gd:1085 口径） ============
func _redo_invalidation() -> void:
	var s = S.new()
	var a := Vector3i(0, 0, 0)
	var b := Vector3i(1, 0, 0)
	s.setup({a: true, b: true})
	s.dig({a: true})
	s.undo()
	check(s.can_redo(), "组4: undo 后有 redo 分支")
	s.dig({b: true})
	check(not s.can_redo(), "组4: 新操作清重做栈")
	var r: Dictionary = s.redo()
	check(r["hidden"].is_empty() and r["shown"].is_empty(), "组4: redo 零效果")
	check(s.cells.size() == 1 and s.cells.has(a), "组4: 状态=仅剩 A")

# ============ 组 5：四标签栈独立（6 checks，规格 §6.4） ============
func _stack_independence() -> void:
	var sa = S.new()
	var sb = S.new()
	var a := Vector3i(0, 0, 0)
	var b := Vector3i(1, 1, 1)
	sa.setup({a: true})
	sb.setup({b: true})
	sa.dig({a: true})
	check_eq(sa.cells.size(), 0, "组5: A 挖空")
	check_eq(sb.cells.size(), 1, "组5: B 集不受影响")
	sa.undo()
	check_eq(sa.cells.size(), 1, "组5: A undo 自恢复")
	check_eq(sb.undo_stack.size(), 0, "组5: B 栈深 0（A 的 undo 不影响 B）")
	check(not sb.can_undo(), "组5: B 无可撤销")
	check_eq(sb.cells.size(), 1, "组5: B 集仍 1 格")

# ============ 组 6：单元合并——一次拖动连放=一个单元（T5，5 checks） ============
func _unit_merge() -> void:
	var s = S.new()
	s.setup({})
	var drag: Dictionary = {}
	for x: int in range(5):
		drag[Vector3i(x, 0, 0)] = true
	s.add(drag)
	check_eq(s.undo_stack.size(), 1, "组6: 整段拖动=1 个撤销单元")
	check_eq(s.cells.size(), 5, "组6: 5 格就位")
	s.undo()
	check(s.cells.is_empty(), "组6: 一步 undo 整组回退")
	check_eq(s.redo_stack.size(), 1, "组6: 重做栈持 1 单元")
	s.redo()
	check_eq(s.cells.size(), 5, "组6: 一步 redo 整组重放")

# ============ 组 7：批量复合操作（3 checks；T4 删除留痕：7 条 layer_cells 批量断言随 layer_cells 删除） ============
## 保留实心/清空两操作（不依赖 layer_cells）。
func _bulk_ops() -> void:
	var s3 = S.new()
	s3.setup({})
	s3.set_cells(LP.solid_cells(Vector3i(2, 2, 2)))
	check_eq(s3.cells.size(), 8, "组7: 一键实心=8 格")
	s3.undo()
	check(s3.cells.is_empty(), "组7: 实心可一步撤销")
	var s4 = S.new()
	s4.setup(LP.solid_cells(Vector3i(2, 2, 2)))
	s4.set_cells({})
	check(s4.cells.is_empty() and s4.undo_stack.size() == 1, "组7: 一键清空=1 个撤销单元")
