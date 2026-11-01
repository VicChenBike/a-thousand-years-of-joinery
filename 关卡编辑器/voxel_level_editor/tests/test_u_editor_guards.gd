extends "res://tests/test_base.gd"
## 批次 U 判定用例（U-E 域）：U12②零裁剪强制确认／③清栈精化／④超域计数四标签／
## ⑤block_size 归一／⑥孤儿残留提示。spec §4-U12。
## 批次 V（V-E1，规格 §9.1/§9.2）等价替换留痕：段 2 清栈源证据/段 3 越界计域/段 4 归一/段 6
## 单域应用栈语义随「四域彻底独立」逐条等价改写（逐段头注留痕，只增不减）。
## ②③⑥ 的调用方分支以「源证据」断言（加载 editor_main.gd 源码 contains 判据——
## test_gesture_hud 段 4 源证据先例）；行为面以 level_project/voxel_edit_ops 可直测件承载。

const S := preload("res://scripts/voxel_edit_ops.gd")
const LP := preload("res://scripts/level_project.gd")
const EM := preload("res://scenes/editor_main.gd")
## R1 审查 P1-1 回修（20260918）真实路径段夹具：沙盒根+editor_main.tscn 实例化
## （对齐 test_sanity W4-1 先例：TEMP 一次性沙盒、零触碰真实 levels/；ensure_initialized 传
## 工程自带测试夹具=零读游戏侧默认源，plan §11 P3 纪律同款）。
const SLOTS := preload("res://scripts/level_slots.gd")
const FIXTURE := "res://tests/fixtures/level_chapter1_hemudu.json"

var _sandbox_root: String = ""
var _ed_u: Control = null

func _initialize() -> void:
	print("== test_u_editor_guards ==")
	_seg1_confirm()
	_seg2_stacks()
	_seg3_over_domain()
	_seg4_block_size()
	_seg5_orphan()
	await _seg6_size_apply_real_path()   # R1 审查 P1-1 回修（20260918）：真实路径段
	finish()

# ---- 段 1. U12② 零裁剪强制确认（6 checks）----
func _seg1_confirm() -> void:
	# 判定函数表驱动：零裁剪+零覆盖→直执(true 一致)；零裁剪+有覆盖→弹确认；有裁剪→弹确认（既有）。
	# 磁盘实况对齐留痕（计划 UE-2 注①「API 名对齐、断言目标不变」授权）：zero_diff_all 的 affected
	# 值=该 tag 新尺寸（Vector3i，editor_main 两处调用点实况 {tag:d}），函数内部经
	# LevelProjectScript.solid_cells(尺寸) 取目标实心集——计划内嵌测试块误传实心格字典（与计划内嵌
	# 实现块语义冲突），夹具按实现块口径改传尺寸：solid_same=2×1×1 域（恰等于旧集=零覆盖）、
	# solid_more=3×1×1 域（3 格⊃旧集 2 格=有覆盖）。断言目标不变。
	var a := {Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true}
	check(bool(EM.zero_diff_all({0: a.duplicate(), 1: a.duplicate()},
		{0: Vector3i(2, 1, 1), 1: Vector3i(2, 1, 1)})),
		"U12②：全部 affected 页旧集==目标实心集 → 直执（零裁剪零覆盖）")
	check(not bool(EM.zero_diff_all({0: a.duplicate(), 1: a.duplicate()},
		{0: Vector3i(3, 1, 1), 1: Vector3i(2, 1, 1)})),
		"U12②：任一页有覆盖（旧集≠实心集）→ 强制弹确认（「无裁剪但有覆盖」不再跳过）")
	check(not bool(EM.zero_diff_all({0: {}, 1: a.duplicate()},
		{0: Vector3i(2, 1, 1), 1: Vector3i(2, 1, 1)})),
		"U12②：空旧集 vs 非空实心集 → 弹确认（size 不等短路）")
	var src: String = FileAccess.get_file_as_string("res://scenes/editor_main.gd")
	check(src.contains("zero_diff_all") and src.contains("_size_dialog.popup_centered()"),
		"U12②：调用方两处 else 支落地源证据（零裁剪路径经判据分流入确认框）")
	check(src.contains("不再过第二道闸") or src.contains("confirmed 直执"),
		"U12②：confirmed 回调直执 _execute_size_apply 源证据（防重入成环——P2-4）")
	var cnt: int = src.count("zero_diff_all(") - 1   # 减定义处自身
	check(cnt >= 2, "U12②：单组件应用与全局应用两处 else 支均接入判据（调用点 %d 处）" % cnt)

# ---- 段 2. U12③ 清栈精化（8 checks）----
func _seg2_stacks() -> void:
	# 行为面：清栈后 undo/redo 边界（voxel_edit_ops 本体零改动——清栈由 editor_main 侧直操双栈成员）
	var a := S.new()
	a.undo_stack.append({"removed": {"x": true}, "added": []})
	a.undo_stack.append({"removed": {}, "added": {"y": true}})
	a.undo_stack.append({"removed": {}, "added": {"z": true}})   # 本次 compound（栈顶）
	a.redo_stack.append({"removed": {}, "added": {"r": true}})
	var top: Variant = a.undo_stack.back()
	a.undo_stack.clear()
	if top != null:
		a.undo_stack.append(top)   # 与 editor_main U12③ 发起标签同式
	a.redo_stack.clear()
	check_eq(a.undo_stack.size(), 1, "U12③：发起标签撤销栈重置为仅含本次 compound")
	# 磁盘实况对齐留痕（计划 UE-2 注①「夹具变量名/API 名对齐类」授权）：Session.undo() 会把弹出
	# 单元转入重做栈（voxel_edit_ops.gd:107 redo_stack.append）——「发起标签重做栈清空」判据必须在
	# undo 之前断言（清栈块终态）；undo 后重做栈恰应含本次 compound（Ctrl+Y 可重做本次应用）。
	check(not a.can_redo(), "U12③：发起标签重做栈清空")
	a.undo()
	check(not a.can_undo(), "U12③：Ctrl+Z 恰回退本次应用、更早历史不可达（undo 返回值语义不依赖——双审回修⑨以 can_undo 状态断言）")
	var b := S.new()
	b.undo_stack.append({"removed": {"old": true}, "added": []})
	b.undo_stack.clear()
	b.redo_stack.clear()
	check(not b.can_undo() and not b.can_redo(), "U12③：非发起标签全清（应用后 Ctrl+Z 失效属预期，代价已注明）")
	var c := S.new()
	c.undo_stack.append({"removed": {"o1": true}, "added": []})
	c.redo_stack.append({"removed": {}, "added": {"o2": true}})
	c.undo_stack.clear()
	c.redo_stack.clear()
	check(c.undo_stack.is_empty() and c.redo_stack.is_empty(), "U12③：他标签双栈全清（越界回放根除）")
	var src: String = FileAccess.get_file_as_string("res://scenes/editor_main.gd")
	check(src.contains("撤销栈重置为仅含本次 compound") and src.contains("undo_stack.clear()"),
		"U12③：_execute_size_apply 尾清栈块源证据（显式推翻「保留撤销栈（线性历史）」旧决策，注释改写）")
	check(not src.contains("保留既有撤销栈（线性历史，"),
		"U12③：旧决策注释「原地清写 cells（不调 setup）：保留既有撤销栈（线性历史，…）」已改写废止")
	# 批次 V（V-E1，规格 §9.2）等价替换留痕：旧断言「src.contains("plan_tags.has(")」锚「非发起全清」
	# 循环（plan_tags 外标签双栈全清）——批次 V 四域独立后该循环退役删除（非受影响域撤销历史保留，
	# 用户主诉修复本体），清栈只触 plan_tags（受影响域）；等价改写为「清栈循环键于 plan_tags」源证据
	# +「plan_tags 外清栈循环已删除」反证（含旧循环特征注释片段不得再现）。
	check(src.contains("for tag_i: Variant in plan_tags:") and not src.contains("if not plan_tags.has(t_all):"),
		"U12③：清栈按 plan_tags 分流（仅受影响域＋发起留 compound；批次 V §9.2 收窄——plan_tags 外全清循环退役，等价替换）")

# ---- 段 3. U12④ 超域计数四标签（4→5 checks）----
# 磁盘实况对齐留痕（计划 UE-2 注①授权）：LP.get_voxel_set 返回**拷贝**（strings_to_set 重建），
# 计划兜底支 `p.get_voxel_set(tag)[far]=true` 写入即弃不改模型（断言恒假）→ 改走既有注入先例
# test_level_project.gd E 组 set_voxel_set 同族 API；put_cell/set_cell 磁盘不存在，删除死支。
# 另计划逐标签单查在 2³ 域下 target 注入点即域外格 → clip 后 kept=0、over=0 恒红（判据不可满足），
# 改「界内格+域外格」共注保 over≥1 且逐标签累计>0（断言目标不变：四标签各自计入超域格）。
# 批次 V（V-E1，规格 §9.1）语义同步留痕：计数改 per-domain——各格集按「所属域自身尺寸」计越界
# （blocks/bs、target/target_size、join/join.size、final/final.size）。本段四域均=2³（new_project
# 同值落域）时与旧 block_size 全域口径数值等价（四条既有断言零改写保绿），per-domain 分流行为由
# 尾部 +1 条「tag1 域放大→target 界内不再计超、其余三域计数不变」区分断言承载。
func _seg3_over_domain() -> void:
	var p: Variant = LP.new()
	p.new_project(Vector3i(2, 2, 2))   # block_size=2³（超域判据域；批次 V 起四域各自落域，初始同值 2³）
	var bs := Vector3i(2, 2, 2)
	_inject_over_domain(p, 0, bs)   # blocks 超域
	check(int(p.count_over_domain_cells()) > 0, "U12④：blocks 超域格计入（扫描集扩展）")
	_inject_over_domain(p, 1, bs)   # target 超域
	check(int(p.count_over_domain_cells()) > 0, "U12④：target 超域格计入")
	_inject_over_domain(p, 2, bs)   # join 超域（回归）
	check(int(p.count_over_domain_cells()) > 0, "U12④：join 超域计入（既有回归）")
	_inject_over_domain(p, 3, bs)   # final 超域（回归）
	check(int(p.count_over_domain_cells()) > 0, "U12④：final 超域计入（既有回归）")
	# 批次 V（V-E1，规格 §9.1）per-domain 分流断言：tag1 域放大到 8³ → target 界内格不再计超
	# （超域计数 −1），blocks/join/final 三域计数不受 target_size 影响（仍各计 1）。
	var over_all: int = int(p.count_over_domain_cells())
	check(bool(p.set_size_for_tag(LP.TAG_TARGET, Vector3i(8, 8, 8))), "V-E1：tag1 域放大写生效（前置）")
	check(int(p.count_over_domain_cells()) == over_all - 1,
		"V-E1：per-domain 计数分流（target 按 target_size 计，blocks/join/final 不受影响——旧全按 block_size 恒 4 必红）")

func _inject_over_domain(p: Variant, tag: int, bs: Vector3i) -> void:
	# 累积注入：界内锚格 (0,0,0)（随四标签保留，保 over 严格>0）＋该标签域外格 (bs.x+3,0,0)；
	# 夹具构造以 test_level_project.gd E 组既有先例（set_voxel_set）为准。
	var far := Vector3i(bs.x + 3, 0, 0)
	var cells: Dictionary = p.get_voxel_set(tag)
	cells[Vector3i(0, 0, 0)] = true
	cells[far] = true
	p.set_voxel_set(tag, cells)

# ---- 段 4. U12⑤ 缺 block_size 归一（4→5 checks；双审回修 P1-6 直写实名：载入=load_from_text(:273)、
# 保存=save_to_text(:301)、payload 体素键=blocks 非 cells）----
func _seg4_block_size() -> void:
	var p: Variant = LP.new()
	# 磁盘实况对齐留痕（计划 UE-2 注①授权）：load_from_text 结构门要求 format_version==1
	# （test_level_project.gd F1 夹具先例同款），payload 补齐；blocks/target_shapes 对齐契约数组形态。
	# 本段锚=block_size 缺失场景（消除与游戏侧 level_library.gd:128-129 拒载的静默不一致）。
	var payload := {"format_version": 1, "name": "t", "chapter": 1,
		"pieces": [{"name": "p", "blocks": [], "target_shapes": [[]]}]}
	var ret: Variant = p.load_from_text(JSON.stringify(payload))
	check(ret == true or ret == OK, "U12⑤：缺 block_size 载入不失败（显式归一）")
	check(p.get_block_size() == Vector3i(1, 1, 1), "U12⑤：归一 1×1×1")
	var warns: Array = p.get("load_warnings") if p.get("load_warnings") != null else []
	check(warns.size() >= 1 and String(warns[0]).contains("block_size"),
		"U12⑤：状态栏警告逐字锚「警告：关卡缺少 block_size，已按 1×1×1 归一补写（保存后与游戏侧兼容）」")
	var saved: String = p.save_to_text()
	check(String(saved).contains("block_size"), "U12⑤：保存回写 block_size（显式进模型，再载入游戏侧可读）")
	# 批次 V（V-E1，规格 §9.1）增补（+1）：target_size 载入零迁移红线——旧档（无 target_size）载入
	# 不警告不补写（回落语义天然兼容），保存亦不引入键（_size_fill_or_keep_target「键缺=不落键」
	# 落定行为，与 block_size U12⑤ 显式归一口径刻意不同：见 level_project.gd 落定注释）。
	check(not String(saved).contains("target_size"),
		"V-E1：旧档保存不引入 target_size 键（零迁移不回写污染，规格 §9.1 落定行为）")

# ---- 段 5. U12⑥ 孤儿残留提示（2 checks）----
func _seg5_orphan() -> void:
	var src: String = FileAccess.get_file_as_string("res://scenes/editor_main.gd")
	check(src.contains(".bak") and src.contains(".tmp"),
		"U12⑥：槽位加载孤儿残留检测源证据（<slot>.json.bak / <slot>.json.tmp 存在性检测）")
	check(src.contains("检测到未完成的保存残留"),
		"U12⑥：状态栏提示逐字锚「检测到未完成的保存残留（.bak/.tmp），槽位内容可能为旧版本」（只提示不自动删除）")

# ---- 段 6. 批次 V（V-E1，规格 §9.2）单域应用栈语义——真实路径驱动（11→12 checks）----
## 等价替换留痕（批次 V §9.2，逐条旧→新）：本段原锚「R1 审查 P1-1 回修（20260918）：tag0/1 联动
## 发起时对侧页（tag1）双栈全清」——批次 V 四域彻底独立后「同料联动」语义退役：单组件应用
## affected 恒={active_tag}，plan_tags 外标签**撤销历史保留**（用户主诉「撤销历史被清」的修复
## 本体）。逐条等价替换：
##   旧「tag1（联动对侧页）undo/redo 双栈全清」→ 新「tag1 撤销栈完好（dig 单元保留）且功能可用
##   （switch_tag+真实 _apply_undo 还原格群）」；
##   旧「plan_tags 外 tag2/3 双栈空（『非发起全清』处置不回归）」→ 新「plan_tags 外双栈保持原状」
##   （语义从「清空」改「不动」；本场景 tag2/3 未编辑数值等价恒空，已编辑场景的「保留」断言由
##   test_v_editor_size_domains P6 承载）；
##   旧「tag1 重生差集由 compound.removed_by_tag[1] 承载（removed 0/added 99，双栈全清无损）」→
##   新「compound 只含发起域 old/new（old_sizes/removed_by_tag 恒单键 0——tag1 零接触，无重生差集
##   可承载，单域回放无损）」。
## 本段与段 2 的差别：段 2=mock 同式复刻+源证据；本段实例化 editor_main.tscn 走真实驱动链
## （switch_tag→真实 dig 入栈→真实 _on_apply_size_one_pressed→_on_size_confirmed→
## _execute_size_apply→switch_tag 回 tag1 断言双栈），不得用 mock 复刻清栈逻辑。
func _seg6_size_apply_real_path() -> void:
	_init_sandbox_u()
	_seed_333_u()
	var ed: Control = await _fresh_editor_u()
	var sessions: Dictionary = ed.get("sessions")
	var tag0: RefCounted = sessions[0]
	var tag1: RefCounted = sessions[1]
	check(int(tag0.cells.size()) == 27 and int(tag1.cells.size()) == 27,
		"段6：editor 就绪基线 blocks/target 各 27 格（3³ 种子沙盒装载）")
	# 前置：切 tag1 真实挖 1 格 → 真实入栈 1 个撤销单元（非 mock 注入，生产 dig 通道）
	ed.call("switch_tag", 1)
	ed.call("_on_dig_requested", [Vector3i(0, 0, 0)])
	check(int(tag1.undo_stack.size()) == 1 and tag1.redo_stack.is_empty(),
		"段6：前置 tag1 真实 dig 入栈 1 单元（switch_tag+_on_dig_requested 真实链）")
	# tag0 发起单组件应用 3³→5³：零裁剪有覆盖 → U12② 强制确认 → confirmed 直执行行体
	ed.call("switch_tag", 0)
	(ed.get("size_x") as SpinBox).value = 5.0
	(ed.get("size_y") as SpinBox).value = 5.0
	(ed.get("size_z") as SpinBox).value = 5.0
	ed.call("_on_apply_size_one_pressed")
	var dlg: ConfirmationDialog = ed.get("_size_dialog")
	check(dlg != null and dlg.visible and (ed.get("_pending_apply") as Dictionary).has("plan_tags"),
		"段6：真实路径入确认框（零裁剪有覆盖→U12② 强制确认，_pending_apply 已挂 plan_tags）")
	ed.call("_on_size_confirmed")   # → _execute_size_apply(affected={0:5³}, plan_tags=[0], active_tag=0)
	check_eq(ed.get("project").call("get_block_size"), Vector3i(5, 5, 5),
		"段6：应用生效 block_size=5³（真实执行体证据）")
	# 发起标签（active tag0）：维持现状——undo 仅含本次 compound、redo 空
	var top0: Variant = tag0.undo_stack.back()
	check(int(tag0.undo_stack.size()) == 1 and top0 != null and (top0 as Dictionary).has("compound"),
		"段6：发起标签 tag0 undo 恰 1 且栈顶=本次 compound（active_tag 维持现状）")
	check(not bool(tag0.can_redo()), "段6：发起标签 tag0 重做栈空")
	# 核心修复断言（批次 V §9.2）：切到 tag1（真实 switch_tag 链）→ 其他标签撤销历史保留且功能可用
	# （旧实现「联动对侧页双栈全清」随同料联动退役——等价替换见段头留痕；单域应用不改 tag1 域
	# 尺寸/格群，其旧单元回放前提恒成立，保留即安全）
	ed.call("switch_tag", 1)
	check(ed.call("_active_session") == tag1,
		"段6：切换到 tag1（真实 switch_tag 链，_active_session 对位）")
	check(int(tag1.undo_stack.size()) == 1 and bool(tag1.can_undo()),
		"段6：tag1（plan_tags 外）撤销栈完好——历史保留（批次 V §9.2 核心修复断言，旧「联动对侧页全清」断言等价替换）")
	check(int(tag1.cells.size()) == 26,
		"段6：tag1 格群零操作（单域应用不重生对侧页，旧联动重生 125 必红）")
	ed.call("_apply_undo")
	check(int(tag1.cells.size()) == 27,
		"段6：tag1 历史功能可用（真实 _apply_undo 还原 dig 前 27 格——用户主诉「撤销历史被清」修复证据）")
	# plan_tags 外标签保持原状（批次 V §9.2：清栈只触受影响域；tag2/3 本场景未编辑，双栈恒空）
	var tag2: RefCounted = sessions[2]
	var tag3: RefCounted = sessions[3]
	check(tag2.undo_stack.is_empty() and tag2.redo_stack.is_empty() \
		and tag3.undo_stack.is_empty() and tag3.redo_stack.is_empty(),
		"段6：plan_tags 外 tag2/3 双栈保持原状（未编辑恒空；已编辑「保留」断言由 test_v P6 承载）")
	# 复合单元只含发起域 old/new（批次 V §9.2 单域结构；旧 removed_by_tag[1] 承载断言随联动退役）
	var cp: Dictionary = (tag0.undo_stack.back() as Dictionary)["compound"]
	check((cp["old_sizes"] as Dictionary).size() == 1 and (cp["old_sizes"] as Dictionary).has(0) \
		and (cp["new_sizes"] as Dictionary).size() == 1 and (cp["new_sizes"] as Dictionary).has(0) \
		and (cp["removed_by_tag"] as Dictionary).size() == 1 \
		and (cp["removed_by_tag"] as Dictionary).has(0),
		"段6：compound 恒单域（old_sizes/new_sizes/removed_by_tag 单键 0，批次 V §9.2；旧 by_tag[1] 承载断言等价替换）")
	_cleanup_sandbox_u()

# ---- 段 6 夹具（对齐 test_sanity W4-1 沙盒先例：TEMP 一次性根+env 注入+seed/fresh+尾清理）----
func _init_sandbox_u() -> void:
	var base := OS.get_environment("TEMP")
	if base.is_empty():
		base = "/tmp"
	base = base.replace("\\", "/")
	_sandbox_root = base.path_join("voxel_editor_guards_%d" % Time.get_ticks_msec()) + "/"
	OS.set_environment("VOXEL_EDITOR_SLOTS_ROOT", _sandbox_root)
	SLOTS.ensure_initialized(_sandbox_root, FIXTURE)   # 建槽目录（save_slot_text 不自建）

func _seed_333_u() -> void:
	var p: RefCounted = LP.new()
	p.call("new_project", Vector3i(3, 3, 3))
	# 骨架默认 target_shapes=[[]]（level_slots._write_skeleton 口径）——段 6 场景需 tag1 有真实
	# 旧格集（真实 dig 入栈），target 预填与 blocks 同款 27 格实心（set_voxel_set=段 3 注入先例）。
	p.call("set_voxel_set", 1, p.call("get_voxel_set", 0))
	SLOTS.apply_auto_meta(p, 1)
	check(bool(SLOTS.save_slot_text(1, p.call("save_to_text"), _sandbox_root)),
		"段6：沙盒槽 1 播种 3³ 骨架成功（夹具健康前置）")
	SLOTS.save_meta(1, _sandbox_root)

func _fresh_editor_u() -> Control:
	_ed_u = (load("res://scenes/editor_main.tscn") as PackedScene).instantiate()
	add_child(_ed_u)
	await process_frame   # --script 模式 add_child 不立即进树（_ready 延后一帧，G6 惯例）
	return _ed_u

func _cleanup_sandbox_u() -> void:
	if _ed_u != null:
		_ed_u.free()
		_ed_u = null
	if _sandbox_root.is_empty():
		return
	_remove_dir_recursive_u(_sandbox_root)
	_sandbox_root = ""

func _remove_dir_recursive_u(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	da.list_dir_begin()
	var item := da.get_next()
	while item != "":
		if item != "." and item != "..":
			var full := path.path_join(item)
			if da.current_is_dir():
				_remove_dir_recursive_u(full)
			else:
				DirAccess.remove_absolute(full)
		item = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(path)