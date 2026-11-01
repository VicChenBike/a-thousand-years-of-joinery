class_name VoxelEditSession
extends RefCounted
## 关卡编辑器·纯逻辑层：单个体素集 + 独立双撤销栈（规格 §6.2 行 2 / §6.4）。
## 泛化自游戏单删组模型（level_scene.gd:223-224 元素=Array[Vector3i]、:1084 整组入栈、
## :1085 新操作清重做栈），撤销单元结构 = {removed: Array[Vector3i], added: Array[Vector3i]}——
## 挖除=仅 removed、添加=仅 added、覆盖/批量=混合。
## 所有操作返回 {"hidden": Array[Vector3i], "shown": Array[Vector3i]}：hidden=该操作后应隐藏的格、
## shown=应显示（或新建）的格——编排层据此统一驱动视图（规格 §6.3，视图层与纯逻辑层互不持引用）。
## 0 格变动的操作不入栈（与游戏 delete_selected removed.is_empty 早退同口径，level_scene.gd:1082-1083）。
## 栈深上限 MAX_UNDO（批次 AA 规格 §12 P3-9，**取代**原「栈深无上限（规格 §6.4）」口径）：
## 超出丢最旧、保留最近 MAX_UNDO 条【暂定值·待用户复验】，与主游戏 level_scene.MAX_UNDO 同值。
## 跨标签不共享（每标签一个 Session 实例即独立栈）。

## W9-8（批次 AA §12 P3-9）撤销栈上限【暂定值·待用户复验】：所有入栈点（dig/add/set_cells/
## push_compound/redo）统一经 _push_undo 截断，栈深恒 ≤ MAX_UNDO。
const MAX_UNDO := 200

var cells: Dictionary = {}      # 当前体素集：Vector3i → true
var undo_stack: Array = []      # Array[{removed, added}]
var redo_stack: Array = []

## 撤销栈唯一入栈口（W9-8）：append 后按 MAX_UNDO 截断（丢最旧、留最近 N 条）。
func _push_undo(unit: Dictionary) -> void:
	undo_stack.append(unit)
	while undo_stack.size() > MAX_UNDO:
		undo_stack.pop_front()

## 设置初始集并清双栈（打开/新建/标签重建时调用）。
func setup(initial: Dictionary) -> void:
	cells = {}
	for k: Variant in initial:
		cells[k] = true
	undo_stack = []
	redo_stack = []

func can_undo() -> bool:
	return not undo_stack.is_empty()

func can_redo() -> bool:
	return not redo_stack.is_empty()

## 挖除：只删实际存在的格；0 格变动不入栈。
func dig(remove_set: Dictionary) -> Dictionary:
	var removed: Array = []
	for k: Variant in remove_set:
		var c: Vector3i = k
		if cells.has(c):
			cells.erase(c)
			removed.append(c)
	if removed.is_empty():
		return {"hidden": [], "shown": []}
	_push_undo({"removed": removed, "added": []})
	redo_stack.clear()
	return {"hidden": removed, "shown": []}

## 直接移除指定格且不入撤销栈（T2a 修复批：复合撤销应用体——四会话一律走本路径，单元由编排层
## push_compound 只推发起标签栈，防 double-push/其他标签栈污染）。报告与 dig 同构。
func remove_no_stack(remove_set: Dictionary) -> Dictionary:
	var removed: Array = []
	for k: Variant in remove_set:
		var c: Vector3i = k
		if cells.has(c):
			cells.erase(c)
			removed.append(c)
	return {"hidden": removed, "shown": []}

## 复合撤销单元入栈（T2a 修复批）：仅入栈+清重做栈，不解释 compound、不改 cells。复合单元由
## Session.undo/redo 常规通道随双栈原样往返（compound 键保全），编排层弹栈前 peek 后回放尺寸/格集。
func push_compound(unit: Dictionary) -> void:
	_push_undo(unit)
	redo_stack.clear()

## 添加：只加实际新增的格（重复格幂等）；0 格变动不入栈。一次拖动连放=调用方合并为
## 一个集合一次调用（T5 整段一个撤销单元）。
func add(add_set: Dictionary) -> Dictionary:
	var added: Array = []
	for k: Variant in add_set:
		var c: Vector3i = k
		if not cells.has(c):
			cells[c] = true
			added.append(c)
	if added.is_empty():
		return {"hidden": [], "shown": []}
	_push_undo({"removed": [], "added": added})
	redo_stack.clear()
	return {"hidden": [], "shown": added}

## 覆盖式设置到 target（一键实心/一键清空/复制初始块/尺寸重生成共用）：差集混合单元。
func set_cells(target: Dictionary) -> Dictionary:
	var removed: Array = []
	var added: Array = []
	for k: Variant in cells:
		var c: Vector3i = k
		if not target.has(c):
			removed.append(c)
	for k: Variant in target:
		var c: Vector3i = k
		if not cells.has(c):
			added.append(c)
	if removed.is_empty() and added.is_empty():
		return {"hidden": [], "shown": []}
	for c: Variant in removed:
		cells.erase(c)
	for c: Variant in added:
		cells[c] = true
	_push_undo({"removed": removed, "added": added})
	redo_stack.clear()
	return {"hidden": removed, "shown": added}

## 撤销：弹出最近单元逆做（removed 恢复、added 移除），转入重做栈；空栈安全零报告。
func undo() -> Dictionary:
	if undo_stack.is_empty():
		return {"hidden": [], "shown": []}
	var unit: Dictionary = undo_stack.pop_back()
	for c: Variant in unit["removed"]:
		cells[c] = true
	for c: Variant in unit["added"]:
		cells.erase(c)
	redo_stack.append(unit)
	return {"hidden": unit["added"], "shown": unit["removed"]}

## 重做：弹出最近撤销单元顺做（removed 再删、added 再加），转回撤销栈；空栈安全零报告。
func redo() -> Dictionary:
	if redo_stack.is_empty():
		return {"hidden": [], "shown": []}
	var unit: Dictionary = redo_stack.pop_back()
	for c: Variant in unit["removed"]:
		cells.erase(c)
	for c: Variant in unit["added"]:
		cells[c] = true
	_push_undo(unit)
	return {"hidden": unit["removed"], "shown": unit["added"]}
