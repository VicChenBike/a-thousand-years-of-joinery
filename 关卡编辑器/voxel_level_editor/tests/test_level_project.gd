extends "res://tests/test_base.gd"
## test_level_project：数据模型与 IO（规格 §11.2 行 1）。
## 组随任务追加：A 新建/模型(T1-4) → B 打开门/四步序列化/往返零 diff(T1-5) → C 透传/契约提示(T1-6)
## → D snapshot_data/restore_data(T3-2)。

const LP := preload("res://scripts/level_project.gd")
const FIXTURE := "res://tests/fixtures/level_chapter1_hemudu.json"
const FIXTURE_TWO := "res://tests/fixtures/two_pieces.json"

func _initialize() -> void:
	_group_a_new_project()
	_group_b_io_roundtrip()
	_group_c_passthrough()
	_group_d_snapshot()
	_group_e_plan_shrink()
	_group_f_size_domains()
	finish()

# ============ 组 E：尺寸收缩预演纯函数（T2a 修复批 10 checks 等价改写；规格 §3.3/§5.2 → 20260916 批 §6.3 E 行） ============
## 等价改写留痕：原 plan_shrink(new_size) 四域同尺寸口径（旧 :21-42）→ plan_shrink_domains({tag: 新尺寸})
## 分域口径，语义对「四域同值入参」完全等价（另有 F5-2 锚定断言兜底）。
## 红态：level_project.gd 无 plan_shrink_domains 方法（调用即脚本错误）。断言口径：
## blocks=3³ 实心、target={(0,0,0),(2,2,2),(5,0,0)}、join={(2,0,0),(-1,0,0)}、final 空集。
func _group_e_plan_shrink() -> void:
	var p := LP.new()
	p.new_project(Vector3i(3, 3, 3))
	p.set_voxel_set(LP.TAG_TARGET, {Vector3i(0, 0, 0): true, Vector3i(2, 2, 2): true, Vector3i(5, 0, 0): true})
	p.set_voxel_set(LP.TAG_JOIN, {Vector3i(2, 0, 0): true, Vector3i(-1, 0, 0): true})
	var plan: Dictionary = p.plan_shrink_domains({
		LP.TAG_BLOCKS: Vector3i(2, 2, 2), LP.TAG_TARGET: Vector3i(2, 2, 2),
		LP.TAG_JOIN: Vector3i(2, 2, 2), LP.TAG_FINAL: Vector3i(2, 2, 2),
	})
	check(plan.size() == 4 and plan.has(0) and plan.has(1) and plan.has(2) and plan.has(3), "E: 返回键含 0..3 四标签")
	check_eq((plan[0] as Dictionary).size(), 19, "E: blocks 裁 19 格（3³ 实心 → 2³ 保留 8）")
	check((plan[0] as Dictionary).has(Vector3i(2, 2, 2)), "E: blocks 被裁集含 (2,2,2)")
	check_eq((plan[1] as Dictionary).size(), 2, "E: target 裁 2 格")
	check_eq((plan[2] as Dictionary).size(), 2, "E: join 裁 2 格")
	check((plan[2] as Dictionary).has(Vector3i(-1, 0, 0)), "E: join 被裁集含负坐标 (-1,0,0)")
	check((plan[3] as Dictionary).is_empty(), "E: final 空集→裁 0 格")
	check_eq(p.get_block_size(), Vector3i(3, 3, 3), "E: 调用后 block_size 不变（纯函数无副作用）")
	check(p.get_voxel_set(LP.TAG_BLOCKS).size() == 27 and p.get_voxel_set(LP.TAG_TARGET).size() == 3 \
		and p.get_voxel_set(LP.TAG_JOIN).size() == 2, "E: 调用后三集不变（无副作用）")
	# 零裁剪：8×8×8 四标签全空集。口径适配留痕——join 的 (-1,0,0) 在任意合法尺寸（DIM_MIN=1）
	# 下都越界，故先复位 join 为界内格再做零裁剪断言，保规格 §5.2「零裁剪→各标签空集」语义。
	p.set_voxel_set(LP.TAG_JOIN, {Vector3i(2, 0, 0): true})
	var plan8: Dictionary = p.plan_shrink_domains({
		LP.TAG_BLOCKS: Vector3i(8, 8, 8), LP.TAG_TARGET: Vector3i(8, 8, 8),
		LP.TAG_JOIN: Vector3i(8, 8, 8), LP.TAG_FINAL: Vector3i(8, 8, 8),
	})
	check((plan8[0] as Dictionary).is_empty() and (plan8[1] as Dictionary).is_empty() \
		and (plan8[2] as Dictionary).is_empty() and (plan8[3] as Dictionary).is_empty(), "E: plan_shrink(8,8,8) 四标签全空集（零裁剪）")

# ============ 组 F：尺寸分域访问器（20260916 槽位化批新增，18 checks；规格 §3.1/§6.3 F 行） ============
## F1 回落 5（含前置 1）/ F2 分域互不干扰 5 / F3 三异值往返 4（回归锁）/ F4 缺失补齐 2 / F5 分域预演 2
## / F6 tag1 分流 4（批次 V-E1 新增，规格 §9.1）。
## 红态：level_project.gd 无 get_size_for_tag/set_size_for_tag/plan_shrink_domains 方法（调用即脚本错误）。
func _group_f_size_domains() -> void:
	# F1 回落：最小结构装载 → join/final size 字典空 → 整缺回落 block_size（此处 (1,1,1)）
	var pm := LP.new()
	check(pm.load_from_text("{\"format_version\":1,\"pieces\":[{}]}"), "F1: 最小结构可装载（前置）")
	check_eq(pm.get_size_for_tag(LP.TAG_JOIN), Vector3i(1, 1, 1), "F1: join size 缺失回落 block_size")
	check_eq(pm.get_size_for_tag(LP.TAG_FINAL), Vector3i(1, 1, 1), "F1: final size 缺失回落 block_size")
	pm._ensure_join_final("join_part")["size"] = {"x": 4}   # 部分轴（最小结构无 join_part，经 _ensure_join_final 补建——B 组旧 :139 同款惯例）
	check_eq(pm.get_size_for_tag(LP.TAG_JOIN), Vector3i(4, 1, 1), "F1: 部分轴缺失逐轴回落")
	pm._ensure_join_final("join_part")["size"] = {"x": 0, "y": 40, "z": 3}   # 非法夹紧 1~32
	var clamp_v: Vector3i = pm.get_size_for_tag(LP.TAG_JOIN)
	check(clamp_v.x == 1 and clamp_v.y == 32 and clamp_v.z == 3, "F1: 非法轴值夹紧 1~32")
	# F2 分域互不干扰
	var p2 := LP.new()
	p2.new_project(Vector3i(3, 3, 3))
	check(p2.set_size_for_tag(LP.TAG_JOIN, Vector3i(4, 4, 4)), "F2: join 域合法写生效")
	check_eq(p2.get_size_for_tag(LP.TAG_JOIN), Vector3i(4, 4, 4), "F2: join 域读回 4³")
	check_eq(p2.get_size_for_tag(LP.TAG_BLOCKS), Vector3i(3, 3, 3), "F2: block 域不受 join 写影响")
	check(p2.set_size_for_tag(LP.TAG_FINAL, Vector3i(5, 2, 3)) \
		and p2.get_size_for_tag(LP.TAG_FINAL) == Vector3i(5, 2, 3) \
		and p2.get_size_for_tag(LP.TAG_BLOCKS) == Vector3i(3, 3, 3), "F2: final 域独立写读")
	check(not p2.set_size_for_tag(LP.TAG_JOIN, Vector3i(0, 1, 1)) \
		and p2.get_size_for_tag(LP.TAG_JOIN) == Vector3i(4, 4, 4), "F2: 非法尺寸拒绝且不改动（对位 A:185）")
	# F3 三异值往返（回归锁：旧 save 强制同步下必红）
	var p3 := LP.new()
	p3.new_project(Vector3i(3, 3, 3))
	p3.set_size_for_tag(LP.TAG_JOIN, Vector3i(4, 4, 4))
	p3.set_size_for_tag(LP.TAG_FINAL, Vector3i(5, 2, 3))
	var p3b := LP.new()
	check(p3b.load_from_text(p3.save_to_text()), "F3: 三异值档往返可装载")
	check_eq(p3b.get_size_for_tag(LP.TAG_JOIN), Vector3i(4, 4, 4), "F3: join=4³ 独立往返（回归锁）")
	check_eq(p3b.get_size_for_tag(LP.TAG_FINAL), Vector3i(5, 2, 3), "F3: final=5×2×3 独立往返（回归锁）")
	check_eq(p3b.get_size_for_tag(LP.TAG_BLOCKS), Vector3i(3, 3, 3), "F3: block 域往返不受牵连")
	# F4 缺失补齐
	var p4 := LP.new()
	p4.new_project(Vector3i(3, 3, 3))
	p4.set_size_for_tag(LP.TAG_JOIN, Vector3i(4, 4, 4))
	p4.get_piece()["join_part"]["size"] = {}   # 手工清空 size 字典
	var out4: Dictionary = JSON.parse_string(p4.save_to_text())
	# 偏离计划留痕：4.7 JSON 回析数值恒 float（同 :90-93 口径），期望字面量按回析口径写 float。
	check_eq((out4["pieces"] as Array)[0]["join_part"]["size"], {"x": 3.0, "y": 3.0, "z": 3.0}, "F4: size 字典空→save 按 block_size 补齐（等价旧行为）")
	var out5: Dictionary = JSON.parse_string(p3.save_to_text())
	check_eq((out5["pieces"] as Array)[0]["final_answer"]["size"], {"x": 5.0, "y": 2.0, "z": 3.0}, "F4: 已有独立值 save 永不覆盖")
	# F5 分域预演
	var pf := LP.new()
	pf.new_project(Vector3i(3, 3, 3))
	pf.set_voxel_set(LP.TAG_JOIN, {Vector3i(2, 0, 0): true})
	var plan_one: Dictionary = pf.plan_shrink_domains({LP.TAG_JOIN: Vector3i(1, 1, 1)})
	check((plan_one[LP.TAG_JOIN] as Dictionary).size() == 1 \
		and (plan_one[LP.TAG_BLOCKS] as Dictionary).is_empty() \
		and (plan_one[LP.TAG_TARGET] as Dictionary).is_empty(), "F5: 分域预演只裁目标域")
	var plan_all: Dictionary = pf.plan_shrink_domains({0: Vector3i(2, 2, 2), 1: Vector3i(2, 2, 2), 2: Vector3i(2, 2, 2), 3: Vector3i(2, 2, 2)})
	check_eq((plan_all[0] as Dictionary).size(), 19, "F5: 四域同值入参与旧 plan_shrink 等价（锚=旧 E:28）")
	# F6 tag1 分流（批次 V-E1，规格 §9.1 新增，4 checks）：旧 F 组只锚 join/final/block 三域，
	# 未覆盖 tag1（旧语义 tag1==block_size 同料联动，无可断言的独立行为）。批次 V 四域彻底独立后
	# 增补模型级分流断言（编辑器编排级覆盖见 test_v_editor_size_domains P1/P2/P4）。
	var p6 := LP.new()
	p6.new_project(Vector3i(3, 3, 3))
	check(p6.set_size_for_tag(LP.TAG_TARGET, Vector3i(2, 5, 3)) \
		and p6.get_size_for_tag(LP.TAG_TARGET) == Vector3i(2, 5, 3), "F6: tag1 尺寸写 target_size 独立生效")
	check_eq(p6.get_block_size(), Vector3i(3, 3, 3), "F6: tag1 写不波及 block 域（同料联动退役）")
	check_eq(p6.get_piece().get("target_size", null), {"x": 2, "y": 5, "z": 3}, "F6: tag1 落 pieces[0].target_size 独立键")
	var p6b := LP.new()
	check(p6b.load_from_text(p6.save_to_text()) and p6b.get_size_for_tag(LP.TAG_TARGET) == Vector3i(2, 5, 3) \
		and p6b.get_block_size() == Vector3i(3, 3, 3), "F6: tag1 独立值往返（target_size 缺失回落链对位 F1/F3）")

# ============ 组 D：试玩快照/还原（T3-2，2 checks；审查⑥ P2-4 增嵌套深拷贝 2 条 → 4 checks） ============
func _group_d_snapshot() -> void:
	var p := LP.new()
	p.load_from_text(FileAccess.get_file_as_string(FIXTURE))
	var snap: Dictionary = p.snapshot_data()
	p.set_field("title", "改动")
	# P2-4（审查⑥）强化：嵌套字段改动——快照若误为浅拷贝，restore 后嵌套值随动不还原
	# （原组仅改顶层 title，对浅拷贝不敏感）。现实现 snapshot_data=_data.duplicate(true)
	# 心证确认（level_project.gd 试玩快照节），两条新断言直接绿，未临时改代码制造红态。
	p.get_piece()["name"] = "快照后改名"
	p.get_piece()["blocks"][0] = "9,9,9"
	p.restore_data(snap)
	check_eq(p.get_field("title", ""), "河姆渡榫卯木构件", "D: restore 还原标题")
	check_eq(p.get_piece().get("name", ""), "榫头梁与卯眼固定件", "D: restore 还原嵌套 piece.name（P2-4 深拷贝）")
	check_eq(p.get_piece()["blocks"][0], "0,0,0", "D: restore 还原嵌套 blocks 首格（P2-4 深拷贝）")
	check_eq(p.save_to_text(), FileAccess.get_file_as_string(FIXTURE), "D: 还原后仍往返零 diff")

# ============ 组 C：pieces[1..] 透传/target 只写[0]/元数据保真/契约提示（T1-6，20→24 checks；隔离性修复批 20260917 契约提示超域分支 +4） ============
func _group_c_passthrough() -> void:
	var two := FileAccess.get_file_as_string(FIXTURE_TWO)
	var p := LP.new()
	check(p.load_from_text(two), "C: 双 piece 夹具通过结构门")
	check_eq(p.get_piece_count(), 2, "C: piece 计数=2")
	var before: Dictionary = JSON.parse_string(two)
	var after: Dictionary = JSON.parse_string(p.save_to_text())
	check_eq((after["pieces"] as Array).size(), 2, "C: 保存后 pieces 数组长度不变")
	check_eq(after["pieces"][1], before["pieces"][1], "C: pieces[1] 保存后原样透传（语义相等）")
	var p2 := LP.new()
	p2.new_project(Vector3i(2, 2, 2))
	var shapes: Array = p2.get_piece()["target_shapes"]
	shapes.append(["7,7,7"])
	p2.set_voxel_set(LP.TAG_TARGET, {Vector3i(0, 0, 0): true})
	var shapes2: Array = p2.get_piece()["target_shapes"]
	check_eq(shapes2.size(), 2, "C: target_shapes 数组结构保留（只写 [0]）")
	check_eq(shapes2[1], ["7,7,7"], "C: target_shapes[1] 不被改动")
	check_eq(shapes2[0], ["0,0,0"], "C: target_shapes[0] 被替换")
	var p3 := LP.new()
	check(p3.load_from_text(FileAccess.get_file_as_string(FIXTURE)), "C: 第 1 关打开")
	p3.set_voxel_set(LP.TAG_BLOCKS, p3.get_voxel_set(LP.TAG_BLOCKS))
	p3.set_field("title", "改名")
	var pout: Dictionary = JSON.parse_string(p3.save_to_text())
	check_eq(pout["theme"], "wood", "C: theme 透传保留")
	check_eq(pout["era"], "新石器时代", "C: era 透传保留")
	check_eq(pout["anim_time"], 100, "C: anim_time 透传保留")
	check_eq(pout["description"], "河姆渡遗址榫卯木构件示意：在实心木料上挖出带榫头的梁，与带卯眼的固定件对接，感受七千年前的榫卯智慧。", "C: description 透传保留")
	check_eq(pout["level_id"], "chapter1_hemudu", "C: level_id 透传保留")
	# 偏离计划留痕：Godot 4.7 的 JSON 回析数值恒为 float 且 Dictionary 对 int/float 严格不等，
	# 期望字面量按回析口径写 float（同步语义不变：match_offset 三轴 = 0；标量 anim_time 的
	# 100.0 == 100 数值比较为真，无需适配）。
	check_eq(pout["pieces"][0]["match_offset"], {"x": 0.0, "y": 0.0, "z": 0.0}, "C: match_offset 透传保留")
	var p4 := LP.new()
	p4.new_project(Vector3i(2, 2, 2))
	check_eq(p4.contract_hint(), LP.HINT_TARGET_EMPTY, "C: 契约提示 target 空")
	p4.set_voxel_set(LP.TAG_TARGET, {Vector3i(0, 0, 0): true})
	check_eq(p4.contract_hint(), LP.HINT_JOIN_EMPTY, "C: 契约提示 join 空")
	p4.set_voxel_set(LP.TAG_JOIN, {Vector3i(0, 0, 0): true})
	check_eq(p4.contract_hint(), LP.HINT_FINAL_EMPTY, "C: 契约提示 final 空")
	p4.set_voxel_set(LP.TAG_FINAL, {Vector3i(0, 0, 0): true})
	check_eq(p4.contract_hint(), LP.HINT_ALL_OK, "C: 契约提示全部通过")
	# 隔离性修复批 20260917（R1）：contract_hint 超域分支——join/final 体素超出 block_size 域的格数 N>0
	# 时提示超域知情文案，优先级在三条空集提示之后。期望文案按常量口径写字面量（红阶段
	# 常量尚不存在，避免动态查错打断断言流；绿阶段与 level_project.gd HINT_OVER_DOMAIN 逐字一致）。
	# 批次 V（V-E1，规格 §9.1）等价替换留痕：HINT_OVER_DOMAIN 文案随 per-domain 计数语义同步——
	# 旧「对接件/最终成品有 %d 格超出初始木块域」→ 新「有 %d 格超出所属组件域尺寸」（枚举+域口径
	# 退役；本两条断言目标不变=超域计数 N 与优先级，仅文案字面量按新常量改写）。
	var p4o := LP.new()
	p4o.new_project(Vector3i(2, 2, 2))
	p4o.set_voxel_set(LP.TAG_TARGET, {Vector3i(0, 0, 0): true})
	p4o.set_voxel_set(LP.TAG_JOIN, {Vector3i(0, 0, 0): true, Vector3i(3, 0, 0): true})
	p4o.set_voxel_set(LP.TAG_FINAL, {Vector3i(0, 0, 0): true})
	check_eq(p4o.contract_hint(), "有 1 格超出所属组件域尺寸，游戏加载时将被裁剪",
		"C: 契约提示 join 超域返回 N=1（隔离性修复批 R1；批次 V §9.1 文案 per-domain 等价替换）")
	p4o.set_voxel_set(LP.TAG_FINAL, {Vector3i(0, 0, 0): true, Vector3i(3, 3, 3): true})
	check_eq(p4o.contract_hint(), "有 2 格超出所属组件域尺寸，游戏加载时将被裁剪",
		"C: 契约提示 final 超域累计 N=2（隔离性修复批 R1；批次 V §9.1 文案 per-domain 等价替换）")
	p4o.set_voxel_set(LP.TAG_JOIN, {Vector3i(0, 0, 0): true})
	p4o.set_voxel_set(LP.TAG_FINAL, {Vector3i(0, 0, 0): true})
	check_eq(p4o.contract_hint(), LP.HINT_ALL_OK, "C: 契约提示全部界内返回 ALL_OK（隔离性修复批 R1）")
	p4o.set_voxel_set(LP.TAG_JOIN, {Vector3i(3, 0, 0): true})
	p4o.set_voxel_set(LP.TAG_TARGET, {})
	check_eq(p4o.contract_hint(), LP.HINT_TARGET_EMPTY,
		"C: 契约提示空集提示优先于超域分支（隔离性修复批 R1 优先级口径）")
	var mixed: Dictionary = {Vector3i(0, 0, 0): true, Vector3i(3, 0, 0): true, Vector3i(0, -1, 0): true, Vector3i(0, 0, 5): true}
	var clipped: Dictionary = LP.clip_out_of_bounds(mixed, Vector3i(3, 3, 3))
	check(clipped.size() == 1 and clipped.has(Vector3i(0, 0, 0)), "C: 越界收缩裁剪只留界内格")
	check_eq(LP.clip_out_of_bounds(LP.solid_cells(Vector3i(3, 3, 3)), Vector3i(3, 3, 3)).size(), 27, "C: 界内全集裁剪无损")

# ============ 组 B：打开最小结构门/风格记录/四步序列化/往返零 diff（T1-5，22 checks） ============
func _group_b_io_roundtrip() -> void:
	var text := FileAccess.get_file_as_string(FIXTURE)
	check(text.length() > 1000, "B: 夹具读入非空")
	check(text.contains("\r\n"), "B: 夹具 CRLF")
	var p := LP.new()
	check(p.load_from_text(text), "B: 第 1 关通过最小结构门")
	check_eq(p.get_block_size(), Vector3i(8, 3, 8), "B: block_size=8×3×8")
	check_eq(p.get_voxel_set(LP.TAG_BLOCKS).size(), 192, "B: blocks=192 格全实心")
	check_eq(p.get_total_capacity(), 192, "B: 容量 192")
	check_eq(p.get_piece_count(), 1, "B: 单 piece")
	check_eq(p.save_to_text(), text, "B: 往返逐字节零 diff（规格 §9.5 硬门槛）")
	var lf_text := text.replace("\r\n", "\n")
	var p2 := LP.new()
	check(p2.load_from_text(lf_text), "B: LF 版本可打开")
	check_eq(p2.save_to_text(), lf_text, "B: LF 风格回填（风格记录①）")
	var nt := lf_text.trim_suffix("\n")
	var p3 := LP.new()
	check(p3.load_from_text(nt), "B: 无尾换行版本可打开")
	check_eq(p3.save_to_text(), nt, "B: 无尾换行回填（风格记录②）")
	var p4 := LP.new()
	check(not p4.load_from_text("{\"format_version\":2,\"pieces\":[{}]}"), "B: 版本≠1 拒开")
	check(not p4.load_from_text("{\"pieces\":[{}]}"), "B: 缺 format_version 拒开")
	check(not p4.load_from_text("{\"format_version\":1}"), "B: pieces 缺失拒开")
	check(not p4.load_from_text("{\"format_version\":1,\"pieces\":[]}"), "B: pieces 空拒开")
	check(not p4.load_from_text("{\"format_version\":1,\"pieces\":[\"str\"]}"), "B: pieces[0] 非对象拒开")
	check(p4.load_from_text("{\"format_version\":1,\"pieces\":[{}]}"), "B: 最小合法结构可装载（宽容）")
	check(p4.get_voxel_set(LP.TAG_TARGET).is_empty(), "B: 缺 target_shapes 照开为空集")
	check(not p4.load_from_text("not json at all"), "B: 非法 JSON 拒开")
	# B 组等价改写留痕（规格 §6.3 B 行）：旧断言「保存时 join size 强制同步=block_size（T6）」
	# （旧 :137-144，1 条）退役——强制同步正是本批根因；等价改写为「各域已有独立值保存后原样保留」
	# 三异值断言（join 9³ / final 8×8×8 / block 3³，1→3 条净 +2）。
	# 【回归锁：旧实现必红】旧 save 强制同步把 9³/8³ 归一 3³，前两条在旧实现下必 FAIL。
	# 偏离计划留痕：Godot 4.7 的 JSON 回析数值恒为 float 且 Dictionary 对 int/float 严格不等，
	# 期望字面量按回析口径写 float（同 :90-93 口径）。
	var p5 := LP.new()
	p5.new_project(Vector3i(3, 3, 3))
	p5._ensure_join_final("join_part")["size"] = {"x": 9, "y": 9, "z": 9}
	p5._ensure_join_final("final_answer")["size"] = {"x": 8, "y": 8, "z": 8}
	var saved: Dictionary = JSON.parse_string(p5.save_to_text())
	var piece5: Dictionary = (saved["pieces"] as Array)[0]
	check_eq(piece5["join_part"]["size"], {"x": 9.0, "y": 9.0, "z": 9.0}, "B: join size 独立值保存后原样保留（回归锁，旧同步行为必红）")
	check_eq(piece5["final_answer"]["size"], {"x": 8.0, "y": 8.0, "z": 8.0}, "B: final size 独立值保存后原样保留（回归锁，旧同步行为必红）")
	check_eq(piece5["block_size"], {"x": 3.0, "y": 3.0, "z": 3.0}, "B: block 域保存往返不受牵连（三异值各自原样）")
	# B 组新增 1 条（护栏）：load_from_text 接受 join/final size 各异值的文件（结构门不因分域收紧）。
	var p4b := LP.new()
	check(p4b.load_from_text("{\"format_version\":1,\"pieces\":[{\"join_part\":{\"size\":{\"x\":9,\"y\":9,\"z\":9}},\"final_answer\":{\"size\":{\"x\":8,\"y\":8,\"z\":8}}}]}"), "B: 结构门接受 join/final size 异值文件（分域不收紧门禁）")
	var p6 := LP.new()
	p6.new_project(Vector3i(2, 2, 2))
	var out: Dictionary = JSON.parse_string(p6.save_to_text())
	check_eq(int(out["format_version"]), 1, "B: 新档 stringify 顶层可回析")

# ============ 组 A：新建工程/实心/元数据默认/尺寸/访问器（T1-4，35 checks） ============
func _group_a_new_project() -> void:
	check(LP.is_valid_size(Vector3i(1, 1, 1)), "A: 下界 1 合法")
	check(LP.is_valid_size(Vector3i(32, 32, 32)), "A: 上界 32 合法")
	check(not LP.is_valid_size(Vector3i(0, 3, 3)), "A: 0 维非法")
	check(not LP.is_valid_size(Vector3i(33, 1, 1)), "A: 33 维非法")
	check_eq(LP.solid_cells(Vector3i(1, 1, 1)).size(), 1, "A: 1×1×1 实心=1 格")
	check_eq(LP.solid_cells(Vector3i(32, 32, 32)).size(), 32768, "A: 32³ 实心=32768 格")
	var p := LP.new()
	check(p.new_project(Vector3i(3, 3, 3)), "A: 新建 3×3×3 成功")
	check(not p.new_project(Vector3i(0, 3, 3)), "A: 新建拒绝 0 维")
	check(not p.new_project(Vector3i(33, 1, 1)), "A: 新建拒绝越界")
	check(p.new_project(Vector3i(1, 1, 32)), "A: 新建接受 1×1×32")
	check(p.new_project(Vector3i(3, 3, 3)), "A: 重建 3×3×3 成功")
	check_eq(p.get_block_size(), Vector3i(3, 3, 3), "A: block_size 读回")
	check_eq(p.get_voxel_set(LP.TAG_BLOCKS).size(), 27, "A: 3×3×3 实心 blocks=27 格")
	check_eq(p.get_field("format_version", -1), 1, "A: format_version=1")
	check_eq(p.get_field("level_id", ""), "chapter1_untitled", "A: level_id 默认（T2）")
	check_eq(p.get_field("chapter", -1), 1, "A: chapter 默认 1")
	check_eq(p.get_field("theme", ""), "wood", "A: theme 默认 wood")
	check_eq(p.get_field("anim_time", -1), 100, "A: anim_time 默认 100")
	check_eq(p.get_field("grid_size_unused", -1), 0, "A: grid_size_unused 默认 0")
	var piece: Dictionary = p.get_piece()
	check_eq(piece.get("piece_id", ""), "p1", "A: piece_id 恒 p1")
	check(piece.get("initial_voxels", false) == true, "A: initial_voxels 恒 true")
	var shapes: Array = piece.get("target_shapes", [])
	check(shapes.size() == 1 and (shapes[0] as Array).is_empty(), "A: target_shapes=[[]] 单答案占位")
	check_eq(piece.get("join_part", {}).get("size", {}), {"x": 3, "y": 3, "z": 3}, "A: join size=block_size")
	check_eq(piece.get("final_answer", {}).get("size", {}), {"x": 3, "y": 3, "z": 3}, "A: final size=block_size")
	check_eq(piece.get("match_offset", {}), {"x": 0, "y": 0, "z": 0}, "A: match_offset 默认 0,0,0")
	check_eq(p.get_piece_count(), 1, "A: 新建 1 个 piece")
	check_eq(p.get_total_capacity(), 27, "A: 容量=尺寸积")
	p.set_field("title", "测试标题")
	check_eq(p.get_field("title", ""), "测试标题", "A: set_field/get_field 透传写读")
	check(p.set_block_size(Vector3i(4, 5, 6)) and p.get_block_size() == Vector3i(4, 5, 6), "A: set_block_size 合法生效")
	check(not p.set_block_size(Vector3i(0, 1, 1)) and p.get_block_size() == Vector3i(4, 5, 6), "A: set_block_size 非法拒绝且不改动")
	check_eq(LP.auto_level_id(3), "chapter3_untitled", "A: auto_level_id 生成")
	check_eq(LP.auto_level_id(9), "chapter5_untitled", "A: auto_level_id 夹紧 1~5")
	var rt: Dictionary = LP.strings_to_set(["1,2,3", "0,0,0"])
	check_eq(rt.size(), 2, "A: 字符串坐标集解析 2 格")
	check_eq(LP.strings_to_set(["bad", "1,1,1"]).size(), 1, "A: 非法坐标串跳过")
	check_eq(LP.cell_to_string(Vector3i(1, 2, 3)), "1,2,3", "A: 坐标串化格式")
