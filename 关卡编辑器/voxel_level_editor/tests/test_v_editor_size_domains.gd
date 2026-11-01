extends "res://tests/test_base.gd"
## 批次 V（V-E1）编辑器四域尺寸独立测试（规格 §9.1 数据模型 / §9.2 应用按钮 / §9.4 测试矩阵尺寸部分）。
## 红态定义=对批次 V 前实现必红：
##   P1 真值表——set_size_for_tag(1) 旧实现写 block_size（tag0/1 同料联动）→ 分流断言红；
##   P2 主诉直断言——改 tag1 尺寸后 tag0 的 block_size 字典与 blocks 格群逐字节不变（旧联动必红）；
##   P4 回落与不回写——target_size 缺失回落 block_size、读路径零物化、保存不引入键（旧实现无此字段）；
##   P5 per-domain 越界计数——旧实现全部格集按 block_size 计越界 → target 域独立计数断言红；
##   P6/P7/P8/P9——「仅应用到当前组件」affected 恒={active_tag}（旧 {0,1} 联动）、其他标签撤销栈
##   保留（旧清栈全清）、复合单元单域 old/new（旧两域）、全局应用写各自域字段（旧 tag1 写 block_size）。
## 磁盘纪律：VOXEL_EDITOR_SLOTS_ROOT 指向 TEMP 一次性子目录，零触碰真实 levels/（test_sanity W4-1 先例）。
## Godot 4.7 坑对齐（spec §14）：无头不断言视口几何（尺寸断言全走数据面）；Vector3i 恒 == 比较；
## JSON 回析数值恒 float，期望字面量按回析口径写 float（test_level_project :94 既有口径）；
## 字典取键一律 .get 防御（spec §14 坑 2）。

const LP := preload("res://scripts/level_project.gd")
const SLOTS := preload("res://scripts/level_slots.gd")
const FIXTURE := "res://tests/fixtures/level_chapter1_hemudu.json"

var _sandbox_root: String = ""
var _ed_v: Control = null

func _initialize() -> void:
	print("== test_v_editor_size_domains ==")
	_p1_tag_dispatch_table()
	_p2_tag1_independence()
	_p3_join_final_untouched()
	_p4_target_size_fallback()
	_p5_over_domain_per_domain()
	await _p6_single_apply_preserves_other_stacks()
	await _p7_tag1_initiator_independence()
	await _p8_compound_single_domain_replay()
	await _p9_global_apply_own_fields()
	finish()

# ============ P1 四标签 setter/getter 分流真值表（规格 §9.1） ============
func _p1_tag_dispatch_table() -> void:
	var p: Variant = LP.new()
	p.new_project(Vector3i(3, 3, 3))
	# 四域异值逐个写入；每写一域即断言「其余三域读值逐字节不变」（真值表逐行）。
	var sizes: Dictionary = {
		LP.TAG_BLOCKS: Vector3i(2, 3, 4),
		LP.TAG_TARGET: Vector3i(5, 6, 7),
		LP.TAG_JOIN: Vector3i(8, 9, 10),
		LP.TAG_FINAL: Vector3i(11, 12, 13),
	}
	for tag: int in [LP.TAG_BLOCKS, LP.TAG_TARGET, LP.TAG_JOIN, LP.TAG_FINAL]:
		var before: Dictionary = {}
		for other: int in [0, 1, 2, 3]:
			if other != tag:
				before[other] = p.get_size_for_tag(other)
		check(bool(p.set_size_for_tag(tag, sizes[tag])), "P1: tag%d 合法尺寸写生效" % tag)
		check(p.get_size_for_tag(tag) == sizes[tag], "P1: tag%d 读回 %s（分流）" % [tag, str(sizes[tag])])
		var others_ok: bool = true
		for other: int in before:
			if p.get_size_for_tag(other) != before[other]:
				others_ok = false
		check(others_ok, "P1: 写 tag%d 后其余三域读值逐字节不变" % tag)
	# 落点字段各归各域（不新增顶层结构：全在 pieces[0] 内键）。
	var piece: Dictionary = p.get_piece()
	check_eq(piece.get("block_size", {}), {"x": 2, "y": 3, "z": 4}, "P1: tag0 落 block_size")
	check_eq(piece.get("target_size", null), {"x": 5, "y": 6, "z": 7}, "P1: tag1 落 target_size（独立字段）")
	check_eq((piece.get("join_part", {}) as Dictionary).get("size", {}), {"x": 8, "y": 9, "z": 10}, "P1: tag2 落 join_part.size")
	check_eq((piece.get("final_answer", {}) as Dictionary).get("size", {}), {"x": 11, "y": 12, "z": 13}, "P1: tag3 落 final_answer.size")
	# 非法尺寸拒绝且四域零改动（对位既有 F2 口径，扩四标签）。
	var reject_ok: bool = not bool(p.set_size_for_tag(LP.TAG_TARGET, Vector3i(0, 1, 1))) \
		and p.get_size_for_tag(LP.TAG_TARGET) == sizes[LP.TAG_TARGET] \
		and p.get_size_for_tag(LP.TAG_BLOCKS) == sizes[LP.TAG_BLOCKS]
	check(reject_ok, "P1: 非法尺寸拒绝且零改动（tag1 对位既有口径）")

# ============ P2 改 tag1 不波及 tag0（用户主诉直接断言）+ 反向（规格 §9.1） ============
func _p2_tag1_independence() -> void:
	var p: Variant = LP.new()
	p.new_project(Vector3i(3, 3, 3))
	p.set_voxel_set(LP.TAG_TARGET, {Vector3i(0, 0, 0): true, Vector3i(2, 2, 2): true})
	# 正向：改 tag1 尺寸 → tag0 的 block_size 字典与 blocks 格群逐字节不变。
	var bs_dict_before: Dictionary = (p.get_piece().get("block_size", {}) as Dictionary).duplicate(true)
	var blocks_before: Dictionary = p.get_voxel_set(LP.TAG_BLOCKS)
	var target_cells_before: Dictionary = p.get_voxel_set(LP.TAG_TARGET)
	check(bool(p.set_size_for_tag(LP.TAG_TARGET, Vector3i(2, 2, 2))), "P2: tag1 尺寸写生效（前置）")
	check((p.get_piece().get("block_size", {}) as Dictionary) == bs_dict_before,
		"P2: 改 tag1 后 tag0 的 block_size 字典逐字节不变（用户主诉直断言，旧联动写 block_size 必红）")
	check(p.get_voxel_set(LP.TAG_BLOCKS) == blocks_before, "P2: 改 tag1 后 blocks 格群逐字节不变")
	check(p.get_voxel_set(LP.TAG_TARGET) == target_cells_before, "P2: 改 tag1 尺寸不动 target 格群（尺寸写与体素零耦合）")
	check_eq(p.get_piece().get("target_size", null), {"x": 2, "y": 2, "z": 2}, "P2: 改 tag1 落 target_size 独立字段")
	# 反向：改 tag0 尺寸 → tag1 的 target_size 字典/读值与 target 格群逐字节不变。
	var p2: Variant = LP.new()
	p2.new_project(Vector3i(3, 3, 3))
	p2.set_size_for_tag(LP.TAG_TARGET, Vector3i(2, 2, 2))
	var ts_dict_before: Dictionary = (p2.get_piece().get("target_size", {}) as Dictionary).duplicate(true)
	var target_cells_before2: Dictionary = p2.get_voxel_set(LP.TAG_TARGET)
	check(bool(p2.set_size_for_tag(LP.TAG_BLOCKS, Vector3i(4, 4, 4))), "P2: tag0 尺寸写生效（前置）")
	check((p2.get_piece().get("target_size", {}) as Dictionary) == ts_dict_before,
		"P2: 改 tag0 后 target_size 字典逐字节不变（反向主诉直断言）")
	check(p2.get_size_for_tag(LP.TAG_TARGET) == Vector3i(2, 2, 2), "P2: 改 tag0 后 get_size_for_tag(1) 仍 2³")
	check(p2.get_voxel_set(LP.TAG_TARGET) == target_cells_before2, "P2: 改 tag0 尺寸不动 target 格群")

# ============ P3 join/final 不受 tag0/tag1 尺寸写影响（规格 §9.1 四域彻底分流） ============
func _p3_join_final_untouched() -> void:
	var p: Variant = LP.new()
	p.new_project(Vector3i(3, 3, 3))
	p.set_voxel_set(LP.TAG_JOIN, {Vector3i(0, 0, 0): true})
	var join_size_before: Vector3i = p.get_size_for_tag(LP.TAG_JOIN)
	var final_size_before: Vector3i = p.get_size_for_tag(LP.TAG_FINAL)
	var join_cells_before: Dictionary = p.get_voxel_set(LP.TAG_JOIN)
	p.set_size_for_tag(LP.TAG_TARGET, Vector3i(2, 2, 2))
	p.set_size_for_tag(LP.TAG_BLOCKS, Vector3i(4, 4, 4))
	check(p.get_size_for_tag(LP.TAG_JOIN) == join_size_before \
		and p.get_size_for_tag(LP.TAG_FINAL) == final_size_before,
		"P3: tag0/tag1 尺寸写后 join/final 域尺寸逐字节不变")
	check(p.get_voxel_set(LP.TAG_JOIN) == join_cells_before, "P3: tag0/tag1 尺寸写后 join 格群逐字节不变")

# ============ P4 target_size 缺失回落 block_size + 旧档零迁移不回写（规格 §9.1） ============
func _p4_target_size_fallback() -> void:
	# ① 旧档（无 target_size）载入：读=回落 block_size；读路径零物化；保存不引入键（零迁移）。
	var p: Variant = LP.new()
	var old_doc := "{\"format_version\":1,\"pieces\":[{\"block_size\":{\"x\":8,\"y\":3,\"z\":8}}]}"
	check(bool(p.load_from_text(old_doc)), "P4: 旧档（无 target_size）可装载")
	check(p.get_size_for_tag(LP.TAG_TARGET) == Vector3i(8, 3, 8),
		"P4: 旧档 get_size_for_tag(1)==block_size（缺失回落链）")
	check(p.get_piece().get("target_size", null) == null,
		"P4: 回落读路径零物化（不得立即回写进模型）")
	var saved1: Dictionary = JSON.parse_string(p.save_to_text())
	check(not ((saved1["pieces"] as Array)[0] as Dictionary).has("target_size"),
		"P4: 旧档保存不引入 target_size 键（零迁移，往返零 diff 保留——批次 V 落定行为）")
	# ② 空字典补齐（_size_fill_or_keep 同口径：空 → 按回落值落完整三轴）。
	var p2: Variant = LP.new()
	var empty_doc := "{\"format_version\":1,\"pieces\":[{\"block_size\":{\"x\":2,\"y\":2,\"z\":2},\"target_size\":{}}]}"
	check(bool(p2.load_from_text(empty_doc)), "P4: 空字典档可装载（前置）")
	check(p2.get_size_for_tag(LP.TAG_TARGET) == Vector3i(2, 2, 2), "P4: 空字典读回落 block_size")
	var saved2: Dictionary = JSON.parse_string(p2.save_to_text())
	check_eq((saved2["pieces"] as Array)[0].get("target_size", null), {"x": 2.0, "y": 2.0, "z": 2.0},
		"P4: 空字典保存按回落值补齐（_size_fill_or_keep 同口径）")
	# ③ 已有独立值永不覆盖。
	var p3: Variant = LP.new()
	var val_doc := "{\"format_version\":1,\"pieces\":[{\"block_size\":{\"x\":3,\"y\":3,\"z\":3},\"target_size\":{\"x\":5,\"y\":6,\"z\":7}}]}"
	check(bool(p3.load_from_text(val_doc)), "P4: 异值档可装载（前置）")
	var saved3: Dictionary = JSON.parse_string(p3.save_to_text())
	check_eq((saved3["pieces"] as Array)[0].get("target_size", null), {"x": 5.0, "y": 6.0, "z": 7.0},
		"P4: 已有独立值保存永不覆盖")
	# ④ 四域异值往返回归锁（写 → 存 → 载 → 读）。
	var p4: Variant = LP.new()
	p4.new_project(Vector3i(3, 3, 3))
	p4.set_size_for_tag(LP.TAG_TARGET, Vector3i(2, 5, 3))
	p4.set_size_for_tag(LP.TAG_BLOCKS, Vector3i(4, 4, 4))
	var p4b: Variant = LP.new()
	check(bool(p4b.load_from_text(p4.save_to_text())), "P4: 四域异值档往返可装载")
	check(p4b.get_size_for_tag(LP.TAG_TARGET) == Vector3i(2, 5, 3), "P4: target_size=2×5×3 独立往返（回归锁）")
	check(p4b.get_size_for_tag(LP.TAG_BLOCKS) == Vector3i(4, 4, 4), "P4: block 域往返不受牵连")
	# ⑤ new_project 写出 target_size（键在 pieces[0] 内，不新增顶层结构）。
	var p5: Variant = LP.new()
	p5.new_project(Vector3i(3, 3, 3))
	check_eq(p5.get_piece().get("target_size", null), {"x": 3, "y": 3, "z": 3}, "P4: new_project 写出 target_size=block_size")

# ============ P5 越界计域 per-domain（规格 §9.1：tag1 按自身域计数，tag0 不受 target_size 影响） ============
func _p5_over_domain_per_domain() -> void:
	var p: Variant = LP.new()
	p.new_project(Vector3i(2, 2, 2))   # 四域初始均 2³
	p.set_voxel_set(LP.TAG_BLOCKS, {Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true})   # 界内
	p.set_voxel_set(LP.TAG_TARGET, {Vector3i(0, 0, 0): true, Vector3i(4, 0, 0): true})   # (4,0,0) 超 2³
	check(int(p.count_over_domain_cells()) == 1, "P5: target 超自身域计 1（blocks 界内不计）")
	p.set_size_for_tag(LP.TAG_TARGET, Vector3i(5, 2, 2))   # target 域放大 → (4,0,0) 界内
	check(int(p.count_over_domain_cells()) == 0,
		"P5: tag1 域放大后 target 超域清零（按 target_size 计，旧按 block_size 恒 1 必红）")
	p.set_size_for_tag(LP.TAG_BLOCKS, Vector3i(1, 1, 1))   # block 域收缩 → blocks (1,0,0) 超域
	check(int(p.count_over_domain_cells()) == 1,
		"P5: tag0 域收缩后 blocks 计 1 且 target 不受影响（仍 0——两域计数互不波及）")
	p.set_size_for_tag(LP.TAG_TARGET, Vector3i(1, 1, 1))   # target 域收缩 → (4,0,0) 再越界
	check(int(p.count_over_domain_cells()) == 2, "P5: 两域各计各的超域（累计 2，per-domain 口径）")
	# contract_hint 超域文案语义同步（spec §9.1）：三域非空后走超域分支，文案=per-domain 语义。
	# N=2：blocks (1,0,0) 超 block 域 1 格 + target (4,0,0) 超 target 域 1 格（上一行收缩后的实况）。
	p.set_voxel_set(LP.TAG_JOIN, {Vector3i(0, 0, 0): true})
	p.set_voxel_set(LP.TAG_FINAL, {Vector3i(0, 0, 0): true})
	check_eq(p.contract_hint(), "有 2 格超出所属组件域尺寸，游戏加载时将被裁剪",
		"P5: contract_hint 超域文案=per-domain 语义（「有 N 格超出所属组件域尺寸」）")

# ============ P6 编辑器「仅当前组件」单域应用：其他三标签撤销栈完好可 undo（用户主诉「撤销历史被清」） ============
func _p6_single_apply_preserves_other_stacks() -> void:
	_init_sandbox_v()
	_seed_333_v()
	var ed: Control = await _fresh_editor_v()
	var proj: RefCounted = ed.get("project")
	var sessions: Dictionary = ed.get("sessions")
	# 三页各造 1 个撤销单元（真实 add 通道）。
	ed.call("switch_tag", 1)
	ed.call("_on_add_requested", [Vector3i(0, 0, 0)])
	ed.call("switch_tag", 2)
	ed.call("_on_add_requested", [Vector3i(1, 0, 0)])
	ed.call("switch_tag", 3)
	ed.call("_on_add_requested", [Vector3i(2, 2, 2)])
	check(int((sessions[1] as RefCounted).undo_stack.size()) == 1 \
		and int((sessions[2] as RefCounted).undo_stack.size()) == 1 \
		and int((sessions[3] as RefCounted).undo_stack.size()) == 1, "P6: 前置 tag1/2/3 各入栈 1 单元")
	# tag0 发起单组件应用 3³→5³：零裁剪有覆盖 → 强制确认 → confirmed 直执。
	ed.call("switch_tag", 0)
	(ed.get("size_x") as SpinBox).value = 5.0
	(ed.get("size_y") as SpinBox).value = 5.0
	(ed.get("size_z") as SpinBox).value = 5.0
	ed.call("_on_apply_size_one_pressed")
	var dlg: ConfirmationDialog = ed.get("_size_dialog")
	check(dlg != null and dlg.visible, "P6: 单组件应用入确认框（U12② 口径保持）")
	ed.call("_on_size_confirmed")
	# 应用生效且只动本域。
	check_eq(proj.call("get_block_size"), Vector3i(5, 5, 5), "P6: block_size=5³（发起域生效）")
	check(int((sessions[0] as RefCounted).cells.size()) == 125, "P6: 发起页 blocks 重生实心 125")
	check(int((sessions[1] as RefCounted).cells.size()) == 1 \
		and int((sessions[2] as RefCounted).cells.size()) == 1 \
		and int((sessions[3] as RefCounted).cells.size()) == 1,
		"P6: 其他三页格群零操作（affected 恒={active_tag}，旧 {0,1} 联动重生 target 必红）")
	# 用户主诉：其他三标签撤销栈完好（旧实现全清必红）且功能可用。
	check(int((sessions[1] as RefCounted).undo_stack.size()) == 1 \
		and bool((sessions[1] as RefCounted).can_undo()), "P6: tag1 撤销栈完好（历史保留，旧全清必红）")
	check(int((sessions[2] as RefCounted).undo_stack.size()) == 1 \
		and bool((sessions[2] as RefCounted).can_undo()), "P6: tag2 撤销栈完好")
	check(int((sessions[3] as RefCounted).undo_stack.size()) == 1 \
		and bool((sessions[3] as RefCounted).can_undo()), "P6: tag3 撤销栈完好")
	ed.call("switch_tag", 1)
	ed.call("_apply_undo")
	check(int((sessions[1] as RefCounted).cells.size()) == 0, "P6: tag1 历史功能可用（undo 后格群还原）")
	ed.call("switch_tag", 2)
	ed.call("_apply_undo")
	check(int((sessions[2] as RefCounted).cells.size()) == 0, "P6: tag2 历史功能可用（undo 后格群还原）")
	# 复合撤销单元只含本域 old/new（单域结构）。
	ed.call("switch_tag", 0)
	var unit: Dictionary = (sessions[0] as RefCounted).undo_stack.back()
	var cp: Dictionary = unit.get("compound", {})
	check((cp.get("old_sizes", {}) as Dictionary).size() == 1 \
		and (cp.get("old_sizes", {}) as Dictionary).has(0),
		"P6: 复合单元 old_sizes 只含发起域 tag0（旧 {0,1} 两域必红）")
	check((cp.get("new_sizes", {}) as Dictionary).size() == 1 \
		and (cp.get("new_sizes", {}) as Dictionary).has(0),
		"P6: 复合单元 new_sizes 只含发起域 tag0")
	check((cp.get("removed_by_tag", {}) as Dictionary).size() == 1 \
		and (cp.get("removed_by_tag", {}) as Dictionary).has(0),
		"P6: removed_by_tag 只含发起域 tag0（旧含键 1 必红）")
	_cleanup_sandbox_v()

# ============ P7 编辑器 tag1 发起单域：tag0 域/格群/历史全不动 + 草稿按域回填（规格 §9.1/§9.2） ============
func _p7_tag1_initiator_independence() -> void:
	_init_sandbox_v()
	_seed_333_v()
	var ed: Control = await _fresh_editor_v()
	var proj: RefCounted = ed.get("project")
	var sessions: Dictionary = ed.get("sessions")
	# tag0 造 1 个撤销单元（真实 dig）。
	ed.call("_on_dig_requested", [Vector3i(0, 0, 0)])
	check(int((sessions[0] as RefCounted).undo_stack.size()) == 1, "P7: 前置 tag0 dig 入栈 1 单元")
	# tag1 发起单组件 2³：目标页空集 → 零裁剪有覆盖 → 强制确认。
	ed.call("switch_tag", 1)
	(ed.get("size_x") as SpinBox).value = 2.0
	(ed.get("size_y") as SpinBox).value = 2.0
	(ed.get("size_z") as SpinBox).value = 2.0
	ed.call("_on_apply_size_one_pressed")
	var dlg: ConfirmationDialog = ed.get("_size_dialog")
	check(dlg != null and dlg.visible and not (dlg.dialog_text as String).contains("同一块料"),
		"P7: tag1 发起确认框退役同料联动文案（批次 V §9.2，LINK 文案退役）")
	ed.call("_on_size_confirmed")
	# tag0 三不動：域尺寸、格群、撤销历史。
	check_eq(proj.call("get_block_size"), Vector3i(3, 3, 3), "P7: tag1 发起后 block_size 逐字节不变（旧联动写 2³ 必红）")
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(2, 2, 2), "P7: tag1 写 target_size=2³（独立字段）")
	check(int((sessions[0] as RefCounted).cells.size()) == 26, "P7: blocks 格群零操作（26 格，不重生对侧页）")
	check(int((sessions[0] as RefCounted).undo_stack.size()) == 1, "P7: tag0 撤销栈完好（历史保留）")
	# 草稿/SpinBox 按域回填（规格 §9.2：tag1 页显示 target_size 实际值）。
	check((ed.get("size_x") as SpinBox).value == 2.0, "P7: tag1 页 SpinBox=target_size 实际值 2（§9.2 草稿随域）")
	ed.call("switch_tag", 0)
	check((ed.get("size_x") as SpinBox).value == 3.0, "P7: 切 tag0 页 SpinBox=block_size 3（草稿随域回填）")
	check(ed.get("_size_draft") == Vector3i(3, 3, 3), "P7: 切 tag0 页草稿=3³")
	# tag0 历史功能可用：undo 还原 dig。
	ed.call("_apply_undo")
	check(int((sessions[0] as RefCounted).cells.size()) == 27, "P7: tag0 历史功能可用（undo 后 27 格还原）")
	# tag1 页 undo/redo 三态一致（单域回放）。
	ed.call("switch_tag", 1)
	ed.call("_apply_undo")
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(3, 3, 3), "P7: tag1 undo 后 target_size 回落原值 3³")
	check(int((sessions[1] as RefCounted).cells.size()) == 0, "P7: tag1 undo 后格群还原空集")
	check_eq(proj.call("get_block_size"), Vector3i(3, 3, 3), "P7: tag1 undo 不波及 block_size")
	ed.call("_apply_redo")
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(2, 2, 2), "P7: tag1 redo 复现 target_size=2³")
	check(int((sessions[1] as RefCounted).cells.size()) == 8, "P7: tag1 redo 复现重生实心 8")
	# 分域 noop 判定：tag1 草稿==target_size 实际值 → noop 不入栈。
	ed.call("_on_apply_size_one_pressed")
	check((ed.get_node("StatusBar/StatusRow/ContractLabel") as Label).text.contains("尺寸未变化"),
		"P7: tag1 分域 noop 判定（草稿==get_size_for_tag(1)）")
	_cleanup_sandbox_v()

# ============ P8 编辑器复合撤销单域回放：undo/redo 三态一致（规格 §9.2） ============
func _p8_compound_single_domain_replay() -> void:
	_init_sandbox_v()
	_seed_333_v()
	var ed: Control = await _fresh_editor_v()
	var proj: RefCounted = ed.get("project")
	var sessions: Dictionary = ed.get("sessions")
	ed.call("_on_dig_requested", [Vector3i(0, 0, 0)])   # blocks 26
	(ed.get("size_x") as SpinBox).value = 2.0
	(ed.get("size_y") as SpinBox).value = 2.0
	(ed.get("size_z") as SpinBox).value = 2.0
	ed.call("_on_apply_size_one_pressed")   # 有裁剪（27 实心 → 2³）→ 确认框
	ed.call("_on_size_confirmed")
	check_eq(proj.call("get_block_size"), Vector3i(2, 2, 2), "P8: 应用后 block_size=2³")
	check(int((sessions[0] as RefCounted).cells.size()) == 8, "P8: 应用后 blocks 重生 8")
	var state_a_bs: Vector3i = proj.call("get_block_size")
	var state_a_cells: int = (sessions[0] as RefCounted).cells.size()
	ed.call("_apply_undo")   # undo：单域回放
	check_eq(proj.call("get_block_size"), Vector3i(3, 3, 3), "P8: undo 后 block_size=3³（单域 old_sizes 回放）")
	check(int((sessions[0] as RefCounted).cells.size()) == 26, "P8: undo 后 blocks=26（定稿差集对回放）")
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(3, 3, 3), "P8: undo 不波及 tag1 域（单域回放）")
	var state_b_bs: Vector3i = proj.call("get_block_size")
	var state_b_cells: int = (sessions[0] as RefCounted).cells.size()
	ed.call("_apply_redo")   # redo：复现
	check_eq(proj.call("get_block_size"), Vector3i(2, 2, 2), "P8: redo 后 block_size=2³")
	check(int((sessions[0] as RefCounted).cells.size()) == 8, "P8: redo 后 blocks=8")
	ed.call("_apply_undo")   # 再 undo：三态一致（undo 态两次全等）
	check(proj.call("get_block_size") == state_b_bs and (sessions[0] as RefCounted).cells.size() == state_b_cells,
		"P8: 二次 undo 与首次 undo 全等（三态一致）")
	check(state_a_bs == Vector3i(2, 2, 2) and state_a_cells == 8, "P8: 三态锚留存（应用态 2³/8）")
	_cleanup_sandbox_v()

# ============ P9 编辑器全局应用：四域写各自字段 + 全局清栈语义保持（规格 §9.2） ============
func _p9_global_apply_own_fields() -> void:
	_init_sandbox_v()
	_seed_333_v()
	var ed: Control = await _fresh_editor_v()
	var proj: RefCounted = ed.get("project")
	var sessions: Dictionary = ed.get("sessions")
	ed.call("switch_tag", 1)
	ed.call("_on_add_requested", [Vector3i(0, 0, 0)])   # tag1 造历史（全局应用后应被清=U12③ 全局分支不回归）
	ed.call("switch_tag", 0)
	(ed.get("size_x") as SpinBox).value = 4.0
	(ed.get("size_y") as SpinBox).value = 3.0
	(ed.get("size_z") as SpinBox).value = 3.0
	ed.call("_on_apply_size_all_pressed")
	ed.call("_on_size_confirmed")
	# 四域各归各字段（关键：tag1 写 target_size，不再只写 block_size）。
	check_eq(proj.call("get_size_for_tag", 0), Vector3i(4, 3, 3), "P9: tag0 域=4×3×3")
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(4, 3, 3), "P9: tag1 域=4×3×3")
	check_eq(proj.call("get_size_for_tag", 2), Vector3i(4, 3, 3), "P9: tag2 域=4×3×3")
	check_eq(proj.call("get_size_for_tag", 3), Vector3i(4, 3, 3), "P9: tag3 域=4×3×3")
	var piece: Dictionary = proj.call("get_piece")
	check_eq(piece.get("target_size", null), {"x": 4, "y": 3, "z": 3},
		"P9: 全局应用 tag1 落 target_size 独立字段（旧只写 block_size 必红）")
	check_eq((piece.get("join_part", {}) as Dictionary).get("size", {}), {"x": 4, "y": 3, "z": 3}, "P9: join_part.size 落域字段")
	check_eq((piece.get("final_answer", {}) as Dictionary).get("size", {}), {"x": 4, "y": 3, "z": 3}, "P9: final_answer.size 落域字段")
	check_eq(piece.get("block_size", {}), {"x": 4, "y": 3, "z": 3}, "P9: block_size 落域字段")
	# 全局清栈语义保持（四域语义：非发起页全清）。
	check((sessions[1] as RefCounted).undo_stack.is_empty(), "P9: 全局应用非发起页 tag1 清栈（U12③ 全局分支保持）")
	var cp: Dictionary = ((sessions[0] as RefCounted).undo_stack.back() as Dictionary).get("compound", {})
	check((cp.get("old_sizes", {}) as Dictionary).size() == 4, "P9: 全局复合单元 old_sizes 四域")
	check((cp.get("removed_by_tag", {}) as Dictionary).size() == 4, "P9: 全局复合单元 removed_by_tag 四域")
	# 四域 noop 全等判定保持：同草稿再点全局 → STATUS_SIZE_NOOP。
	ed.call("_on_apply_size_all_pressed")
	check((ed.get_node("StatusBar/StatusRow/ContractLabel") as Label).text.contains("尺寸未变化"),
		"P9: 全局 noop 四域全等判定保持")
	_cleanup_sandbox_v()

# ---- 沙盒夹具（对齐 test_u_editor_guards 段 6 先例：TEMP 一次性根 + env 注入 + seed/fresh + 尾清理）----
func _init_sandbox_v() -> void:
	var base := OS.get_environment("TEMP")
	if base.is_empty():
		base = "/tmp"
	base = base.replace("\\", "/")
	_sandbox_root = base.path_join("voxel_editor_vsize_%d" % Time.get_ticks_msec()) + "/"
	OS.set_environment("VOXEL_EDITOR_SLOTS_ROOT", _sandbox_root)
	SLOTS.ensure_initialized(_sandbox_root, FIXTURE)   # 建槽目录（save_slot_text 不自建）

func _seed_333_v() -> void:
	var p: RefCounted = LP.new()
	p.call("new_project", Vector3i(3, 3, 3))
	SLOTS.apply_auto_meta(p, 1)
	check(bool(SLOTS.save_slot_text(1, p.call("save_to_text"), _sandbox_root)),
		"沙盒：槽 1 播种 3³ 骨架成功（夹具健康前置）")
	SLOTS.save_meta(1, _sandbox_root)

func _fresh_editor_v() -> Control:
	if _ed_v != null:
		_ed_v.free()
		_ed_v = null
	_ed_v = (load("res://scenes/editor_main.tscn") as PackedScene).instantiate()
	add_child(_ed_v)
	await process_frame   # --script 模式 add_child 不立即进树（_ready 延后一帧，G6 惯例）
	return _ed_v

func _cleanup_sandbox_v() -> void:
	if _ed_v != null:
		_ed_v.free()
		_ed_v = null
	if _sandbox_root.is_empty():
		return
	_remove_dir_recursive_v(_sandbox_root)
	_sandbox_root = ""

func _remove_dir_recursive_v(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	da.list_dir_begin()
	var item := da.get_next()
	while item != "":
		if item != "." and item != "..":
			var full := path.path_join(item)
			if da.current_is_dir():
				_remove_dir_recursive_v(full)
			else:
				DirAccess.remove_absolute(full)
		item = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(path)
