extends "res://tests/test_base.gd"
## test_sanity：工程健康 + 静态断言 + 视图/拾取数学/编排直驱（规格 §11.2 行 4 的扩展口径）。
## 组随任务串行追加：G0 环境(T1-2) → G1 R1冒烟(T1-3) → G2 场景骨架(T1-7) → G3 视图(T2-2)
## → G4 拾取四分支(T2-3) → G5 交互状态机(T2-3) → G6 编排接线(T2-4) → G7 尺寸批量(T2-5) → G8 试玩(T3-2)
## → G9 审查⑤回修回归(T2-6 走查 D-1/D-3) → G10 试玩侧视相机+观感回修(T3-3 走查 D-4/D-5/D-6/D-7)
## → G11 审查⑥回修回归(P2-2 层号上界同步/P2-3 试玩加块守卫/P3-3 试玩态标题)
## → G12 审查⑦回修回归(P1-1 主/侧视相机 near 裁剪·轨道距离自适应 + P2-1 弹窗中文标题)
## → G13 布局双态(T1 修复批：EDIT 主视口全高 / PLAYTEST 现状逐像素不动)
## → G15 VIEW 只读预览交互(T3 修复批：试玩上两面板拖拽旋转/滚轮缩放，零编辑信号，退出复位)。

const FIXTURE := "res://tests/fixtures/level_chapter1_hemudu.json"
const FIXTURE_TWO := "res://tests/fixtures/two_pieces.json"
## 20260916 槽位化批 W4-1（spec §3.4-7/§3.4-8）：沙盒夹具基建——环境变量沙盒根 + seed/fresh_editor
## 组间重播夹具。测试进程经 VOXEL_EDITOR_SLOTS_ROOT 指向 TEMP 一次性子目录，零触碰真实 levels/。
const SLOTS := preload("res://scripts/level_slots.gd")

var _sandbox_root: String = ""
var _ed_current: Control = null

## 每进程一次（spec §3.4-7）：TEMP 下一次性根 + 环境变量注入 + 预初始化
## （预填源显式注入 fixtures 夹具——测试进程零读游戏侧，plan §11 P3）。
func _init_sandbox() -> void:
	var base := OS.get_environment("TEMP")
	if base.is_empty():
		base = "/tmp"
	base = base.replace("\\", "/")
	_sandbox_root = base.path_join("voxel_editor_sanity_%d" % Time.get_ticks_msec()) + "/"
	OS.set_environment("VOXEL_EDITOR_SLOTS_ROOT", _sandbox_root)
	SLOTS.ensure_initialized(_sandbox_root, FIXTURE)

## 覆写指定槽 level.json（spec §3.4-8 seed_slot）。
func _seed_slot(slot: int, text: String) -> void:
	SLOTS.save_slot_text(slot, text, _sandbox_root)

## 覆写 session_meta.json（spec §3.4-8 seed_meta）。
func _seed_meta(last_slot: int) -> void:
	SLOTS.save_meta(last_slot, _sandbox_root)

## free 旧实例 → re-instantiate → add_child → await process_frame（_ready 读被重播的沙盒）。
## 注意：本函数为协程，调用侧 `var ed: Control = await _fresh_editor()`；旧实例 free 由本 helper
## 统一管理（转写组尾部的 ed.free() 随 W4-1 删除）。
func _fresh_editor() -> Control:
	if _ed_current != null:
		_ed_current.free()
		_ed_current = null
	_ed_current = (load("res://scenes/editor_main.tscn") as PackedScene).instantiate()
	add_child(_ed_current)
	await process_frame   # --script 模式 add_child 不立即进树（_ready 延后一帧，G6 惯例随迁）
	return _ed_current

## 3³ 骨架种子（spec §3.4-8：除 G2 外编排组一律 3³ 种子沙盒）：
## LP.new()+new_project(3³) → SLOTS.apply_auto_meta(p, slot) → save_to_text → _seed_slot。
func _seed_333(slot: int) -> void:
	var LP := preload("res://scripts/level_project.gd")
	var p: RefCounted = LP.new()
	p.call("new_project", Vector3i(3, 3, 3))
	SLOTS.apply_auto_meta(p, slot)
	_seed_slot(slot, p.call("save_to_text"))

## W5 走查回修辅助（G6 接线断言）：信号连接表含目标方法名。
## ⚠ 口径留痕：必须用 Signal.get_connections()——Node.get_incoming_connections() 在 Godot 4.7
## **不列脚本运行时连接**（槽位钮/标签钮 pressed 连接全部缺失显示），tests/probe_conn_temp.gd
## 探针实证（走查判定表异象记录），勿改用后者否则断言恒假。
func _sig_has_connection(sig: Signal, method: String) -> bool:
	for c in sig.get_connections():
		if (c["callable"] as Callable).get_method() == method:
			return true
	return false

## 测试尾 best-effort 递归清理（plan §11 P7：TEMP 一次性子目录，严禁留垃圾/写工程树）。
func _cleanup_sandbox() -> void:
	if _sandbox_root.is_empty():
		return
	_remove_dir_recursive(_sandbox_root)

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

func _initialize() -> void:
	_init_sandbox()   # W4-1：沙盒根注入（spec §3.4-7），首行执行
	_g0_environment()
	_g1_join_xform_smoke()
	await _g2_scene_skeleton()   # W4-4 P8：G2 async 化（_fresh_editor 夹具，_ready 消费沙盒槽位）
	_g3_voxel_view()
	_g4_pick_math()
	_g5_interaction_state()
	await _g6_orchestration()
	await _g7_size_and_bulk()
	await _g8_playtest()
	await _g9_review5_fixes()
	await _g10_playtest_side_cameras()
	await _g11_review6_fixes()
	await _g12_review7_fixes()
	await _g13_layout_dual_state()
	await _g15_view_interaction()
	await _g16_p11_view_zoom_floor()
	await _g17_p21_playtest_locked_apply()
	await _g18_p24_cross_tag_compound()
	await _g19_perspective_and_center_framing()
	await _g20_size_regen_and_container_bounds()
	await _g21_batch2_review_fixes()
	await _g22_slot_orchestration()   # W4-2 新增
	await _g23_autosave()             # W4-3 新增
	await _g24_single_domain()        # W4-4 新增
	await _g25_w5_walkthrough_fixes() # W5 走查 NG 回修新增
	await _g26_isolation()            # 隔离性修复批 20260917 新增
	_cleanup_sandbox()
	finish()

# ============ G7 D2 尺寸草稿+应用+复合撤销（T2b 修复批，32→34 checks；规格 §3.3/§3.2） ============
## 20260916 槽位化批 W3 等价改写留痕：入口 _on_apply_size_pressed→_on_apply_size_all_pressed
## （全局语义=旧全量语义，spec §3.2-5）；节点断言换 SizeApplyRow 双钮；复合单元断言改 P0-1 新结构。
func _g7_size_and_bulk() -> void:
	# W4-1 转写（spec §3.4-8）：原 instantiate+add_child+await 三行 → 3³ 种子沙盒 + fresh_editor 重播。
	_seed_333(1)
	_seed_meta(1)
	var ed: Control = await _fresh_editor()
	var LP := preload("res://scripts/level_project.gd")
	var blocks := LP.TAG_BLOCKS
	var target := LP.TAG_TARGET
	var draft_spin: SpinBox = ed.get("size_x") as SpinBox
	draft_spin.value = 5.0
	check_eq(ed.get("project").call("get_block_size"), Vector3i(3, 3, 3), "G7: 改框不写 block_size（草稿零触发）")
	check_eq((ed.get("sessions") as Dictionary)[blocks].cells.size(), 27, "G7: 改框不动 blocks 集")
	check(not (ed.get("_size_dialog") as ConfirmationDialog).visible, "G7: 改框不弹确认框")
	check_eq(ed.get("_size_draft"), Vector3i(5, 3, 3), "G7: 草稿随改框更新 5×3×3")
	# 等价改写留痕（spec §6.4 G7 行）：原 :53「BtnApplySize 节点存在」→ 双钮节点存在 + 旧节点消失（三条合一）。
	check(ed.get_node_or_null("LeftPanel/LeftScroll/LeftVBox/SizeApplyRow") != null \
		and ed.get_node_or_null("LeftPanel/LeftScroll/LeftVBox/SizeApplyRow/BtnApplySizeOne") != null \
		and ed.get_node_or_null("LeftPanel/LeftScroll/LeftVBox/SizeApplyRow/BtnApplySizeAll") != null \
		and ed.get_node_or_null("LeftPanel/LeftScroll/LeftVBox/BtnApplySize") == null,
		"G7: SizeApplyRow 双钮存在（单组件左/全局右）且旧 BtnApplySize 消失（原 :53 等价改写）")
	draft_spin.value = 3.0
	ed.call("_on_apply_size_all_pressed")   # 等价改写：原 _on_apply_size_pressed → 全局应用（同值 noop 判定=四域全等，此态恰全等 3³）
	check_eq(ed.get("project").call("get_block_size"), Vector3i(3, 3, 3), "G7: 同草稿值点应用无效（block_size 不变）")
	check(not (ed.get("_size_dialog") as ConfirmationDialog).visible, "G7: 同值无效不弹窗")
	draft_spin.value = 5.0
	ed.call("switch_tag", target)
	# 等价改写留痕（spec §3.2-7）：原 :60「草稿重置为当前 block_size」→ 草稿==当前域尺寸 get_size_for_tag(1)。
	check(ed.get("_size_draft") == (ed.get("project") as RefCounted).call("get_size_for_tag", target),
		"G7: 切标签草稿重置为当前域尺寸（原 :60 当前 block_size→当前域 get_size_for_tag(1)，§3.2-7）")
	# ---- B 零裁剪：直接生效 + 复合撤销（一次 undo 还原尺寸） ----
	ed.call("switch_tag", blocks)
	(ed.get("size_x") as SpinBox).value = 4.0
	ed.call("_on_apply_size_all_pressed")   # 等价改写：全局应用（affected 四域、regen、复合单元语义不变）
	# 批次 U（U12②，双审 P2-4）等价替换留痕：零裁剪放大=「无裁剪但有覆盖」（重生实心集≠旧集）
	# → 强制弹确认（原「零裁剪不弹确认框」断言反转）；confirmed 回调直执执行体（不过第二道闸）。
	check((ed.get("_size_dialog") as ConfirmationDialog).visible,
		"G7: 零裁剪放大弹确认框（U12②「无裁剪但有覆盖」不再跳过，双审 P2-4；原「零裁剪不弹确认框」断言反转）")
	ed.call("_on_size_confirmed")
	var sess: RefCounted = (ed.get("sessions") as Dictionary)[blocks]
	check_eq(ed.get("project").call("get_block_size"), Vector3i(4, 3, 3), "G7: 零裁剪放大经确认应用写 block_size=4×3×3（U12②）")
	check_eq(sess.cells.size(), 36, "G7: blocks 标签零裁剪放大=按新尺寸重生实心 4×3×3=36（修复批二 F3 新语义）")
	check(not sess.undo_stack.is_empty() and (sess.undo_stack.back() as Dictionary).has("compound"), "G7: 应用入复合撤销单元（发起标签 blocks 栈）")
	# P0-1 新结构断言（W3 新增 2 条，spec §6.4 G7 行）：复合单元分域键 + by_tag 对结构。
	var unit_g7: Dictionary = sess.undo_stack.back()
	var cp_g7: Dictionary = unit_g7["compound"]
	check(cp_g7.has("old_sizes") and cp_g7.has("new_sizes") and cp_g7.has("removed_by_tag"),
		"G7: 复合单元 P0-1 新键（old_sizes/new_sizes/removed_by_tag）")
	check((cp_g7["removed_by_tag"][0] as Dictionary).has("removed") \
		and (cp_g7["removed_by_tag"][0] as Dictionary).has("added"),
		"G7: removed_by_tag 每项={removed, added} 对（P0-1，旧 by_tag[0]=[] 特例退役）")
	var size_hint: String = (ed.get_node("StatusBar/StatusRow/ContractLabel") as Label).text
	check(size_hint.contains("尺寸→4×3×3") and size_hint.contains("已重生实心 36"), "G7: 状态栏反馈新尺寸+重生实心 36 格（F3 新语义）")
	var size_toast: Label = ed.get_node("PlaytestToast")
	check(size_toast.visible and size_toast.text.contains("尺寸→4×3×3"), "G7: toast 反馈新尺寸")
	ed.call("_apply_undo")
	check_eq(ed.get("project").call("get_block_size"), Vector3i(3, 3, 3), "G7: 一次 undo 还原尺寸")
	check_eq(sess.cells.size(), 27, "G7: undo 后 blocks 仍 27")
	ed.call("_apply_redo")
	check_eq(ed.get("project").call("get_block_size"), Vector3i(4, 3, 3), "G7: 一次 redo 重做尺寸")
	# ---- C 有裁剪：确认明细 + 复合回放 ----
	ed.call("switch_tag", target)
	ed.call("_on_add_requested", [Vector3i(3, 3, 3)])
	(ed.get("size_x") as SpinBox).value = 3.0
	(ed.get("size_y") as SpinBox).value = 3.0
	(ed.get("size_z") as SpinBox).value = 3.0
	ed.call("_on_apply_size_all_pressed")   # 等价改写：全局应用（确认框仍列四标签明细，现状口径）
	var size_dlg: ConfirmationDialog = ed.get("_size_dialog")
	check(size_dlg.visible, "G7: 有裁剪弹确认框")
	check((size_dlg.dialog_text as String).contains("标准答案"), "G7: 确认框列明标准答案裁剪明细")
	ed.call("_on_size_confirmed")
	var t_session: RefCounted = (ed.get("sessions") as Dictionary)[target]
	check_eq(t_session.cells.size(), 27, "G7: 确认后 target 重生实心 3³=27（隔离性修复批 R4：全局应用四页全部重生，原「越界格被裁=0」断言反转重算）")
	check_eq((ed.get("sessions") as Dictionary)[blocks].cells.size(), 27, "G7: 确认后 blocks 集不丢格")
	check((ed.get_node("StatusBar/StatusRow/ContractLabel") as Label).text.contains("尺寸→3×3×3"), "G7: 状态栏反馈 3×3×3")
	ed.call("_apply_undo")
	check_eq(ed.get("project").call("get_block_size"), Vector3i(4, 3, 3), "G7: 一次 undo 同时还原尺寸=4×3×3")
	# 数值链重算留痕（隔离性修复批 R4）：spec §4.2 原判「:198 undo 回旧 1 格（数值不变）」基于旧链
	# 前提（B 段全局应用只重生 blocks、target 仍空故 C 段加 1 格）——R4 下 B 段 redo 已使 target 重生
	# 实心 36，C 段加 (3,3,3) 后应用前旧集=37 格，undo 回应用前旧集 37（复合单元定稿差集对回放）。
	check_eq(t_session.cells.size(), 37, "G7: undo 回应用前旧集 37 格（36 实心+(3,3,3)；隔离性修复批 R4 数值链重算，原「回旧 1 格」基于旧不重生链）")
	ed.call("_apply_redo")
	check_eq(ed.get("project").call("get_block_size"), Vector3i(3, 3, 3), "G7: redo 重做尺寸=3×3×3")
	check_eq(t_session.cells.size(), 27, "G7: redo 重做 target 重生实心 27（原「重做裁剪=0」断言反转，隔离性修复批 R4）")
	ed.call("_on_solid_pressed")
	check_eq(t_session.cells.size(), 27, "G7: 一键实心 3³")
	ed.call("_on_clear_pressed")
	check(t_session.cells.is_empty(), "G7: 一键清空")
	ed.call("_on_copy_base_pressed")
	check_eq(t_session.cells.size(), 27, "G7: 复制初始块=blocks 深拷贝（§7.3）")
	check(t_session.undo_stack.size() >= 1, "G7: 复制初始块入栈一个单元")
	ed.call("_apply_undo")
	check(t_session.cells.is_empty(), "G7: 复制可整步撤销")
	ed.call("_on_mode_changed", true)
	check(ed.get("is_add_mode") == true and (ed.get_node("StatusBar/StatusRow/ModeLabel") as Label).text.contains("添加"), "G7: 添加模式切换+状态栏")
	# T4 删除留痕：整层挖除/填充与层号上界共 5 条断言随批量区全删（axis_option/layer_spin 引用全清）。

# ============ G8 试玩模式（T3-2，16 checks；规格 §8.1/§8.2/§8.3） ============
func _g8_playtest() -> void:
	var LP := preload("res://scripts/level_project.gd")
	# W4-1 转写（spec §3.4-8）：三实例全部转 3³ 种子沙盒 + fresh_editor（ed/ed2/ed3）。
	_seed_333(1)
	_seed_meta(1)
	var ed: Control = await _fresh_editor()
	# 等价改写留痕（spec §6.4 G8 行/§11 P5）：原 :141/:158「dirty 标记不污染」→「试玩进出槽位
	# level.json 文本零变化」（dirty 随自动保存退役、快照 dirty 项删除，P2⑤；退出重写=load→save
	# 幂等序列化，P5 裁决——非矛盾，字节级等价）。
	var disk_g8_before: String = SLOTS.load_slot_text(1, _sandbox_root)
	ed.call("_enter_playtest")
	check(ed.get("_in_playtest") == true, "G8: 进入试玩态")
	check((ed.get_node("TopBar/BtnJoin") as Button).visible, "G8: 对接按钮出现")
	check((ed.get_node("TargetPanel") as Control).visible, "G8: 左上对照成品面板出现（§8.2）")
	check((ed.get_node("JoinPanel") as Control).visible, "G8: 右上对接固定件面板出现")
	check_eq((ed.get_node("StatusBar/StatusRow/CountLabel") as Label).text, "27 / 27", "G8: 试玩计数=blocks 全集")
	ed.call("_on_dig_requested", [Vector3i(0, 0, 0), Vector3i(1, 1, 1)])
	check_eq(ed.get("_playtest_session").cells.size(), 25, "G8: 试玩挖除落到临时会话")
	check_eq((ed.get("sessions") as Dictionary)[LP.TAG_BLOCKS].cells.size(), 27, "G8: 编辑会话零污染（隔离是主防线）")
	ed.call("_apply_undo")
	check_eq(ed.get("_playtest_session").cells.size(), 27, "G8: 试玩独立栈 undo")
	ed.call("_on_dig_requested", [Vector3i(0, 0, 0), Vector3i(1, 1, 1), Vector3i(2, 2, 2)])
	ed.call("_on_join_pressed")
	var toast: Label = ed.get_node("PlaytestToast")
	check(toast.visible and toast.text == "答案错误：当前形状与目标不一致", "G8: wrong 分支文案（照抄游戏原文）")
	ed.call("_do_exit_playtest")
	check(ed.get("_in_playtest") == false, "G8: 退出试玩态")
	check(not (ed.get_node("TargetPanel") as Control).visible and not (ed.get_node("JoinPanel") as Control).visible, "G8: 退出还原双面板隐藏")
	check(not (ed.get_node("TopBar/BtnJoin") as Button).visible, "G8: 对接按钮隐藏")
	check_eq((ed.get("sessions") as Dictionary)[LP.TAG_BLOCKS].cells.size(), 27, "G8: 编辑数据从快照整体还原")
	check(SLOTS.load_slot_text(1, _sandbox_root) == disk_g8_before,
		"G8: 试玩进出槽位 level.json 文本零变化（原 :158 dirty 断言等价改写，P2⑤/P5）")
	_seed_333(1)
	_seed_meta(1)
	var ed2: Control = await _fresh_editor()
	(ed2.get("sessions") as Dictionary)[LP.TAG_TARGET].setup(LP.solid_cells(Vector3i(3, 3, 3)))
	ed2.call("_enter_playtest")
	ed2.call("_on_join_pressed")
	# 批次 Y6（Y-D4，spec §9.4）等价改写留痕：success 反馈由 2.5s toast 升级为常驻通关横幅
	# PlaytestBanner（进试玩新局/退出试玩才清除）——断言随通道升级等价改写：横幅立现且文案
	# 沿用原 success 语义原文；伴随断言 toast 通道不再被 success 消费（unfit/wrong 仍 toast）。
	var banner2: Label = ed2.get_node("PlaytestBanner")
	check(banner2.visible and banner2.text == "试玩成功：与标准答案一致（试玩不落档，退出还原编辑态）",
		"G8: success 常驻通关横幅文案（Y-D4 通道升级等价改写；原「success 分支 toast 文案」随通道退役）")
	# 注：此刻 toast 仍显示「进入试玩」提示（2.5s 自愈未过期），通道未被 success 消费的确定性
	# 判据=toast 文本非 success 文案（不可断言 toast.visible=false——进入提示尚在自愈窗口内）。
	check((ed2.get_node("PlaytestToast") as Label).text != "试玩成功：与标准答案一致（试玩不落档，退出还原编辑态）",
		"G8: success 未消费 2.5s toast 通道（Y-D4 等价改写伴随断言）")
	# 场景 C：unfit 分支（与 join 原坐标干涉且不等价：target=Z 向多米诺 2 格，试玩剩余=L 形 3 格）
	_seed_333(1)
	_seed_meta(1)
	var ed3: Control = await _fresh_editor()
	(ed3.get("sessions") as Dictionary)[LP.TAG_TARGET].setup({Vector3i(2, 2, 2): true, Vector3i(2, 2, 1): true})
	(ed3.get("sessions") as Dictionary)[LP.TAG_JOIN].setup({Vector3i(1, 0, 0): true})
	ed3.call("_enter_playtest")
	ed3.get("_playtest_session").setup({Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true, Vector3i(0, 1, 0): true})
	ed3.call("_on_join_pressed")
	var toast3: Label = ed3.get_node("PlaytestToast")
	check(toast3.visible and toast3.text == "无法对接：木料与固定件干涉，请调整挖除位置", "G8: unfit 分支文案（照抄游戏原文）")

# ============ G9 审查⑤回修回归（T2-6 走查，9 checks；D-1 打开误弹/误脏 + D-3 幻影清理） ============
## 夹具 two_pieces.json 为 2×2×2（默认工程 3×3×3）：槽位加载即逐轴静默写 SpinBox，未修实现会在
## 中间态（新x,旧y,旧z）误触发 _on_size_draft_changed 改写草稿（blocks 页连带误弹尺寸确认框）。
## 两条路径各用独立实例——单实例复用时 SpinBox 已被首次加载对齐，第二次写同值不触发 value_changed，
## 直通路径断言会失效（红跑实证）。
## 20260916 槽位化批 W4-4 等价改写（spec §6.4 G9 行）：原 `_do_open(FIXTURE_TWO)` 打开回归 →
## 「沙盒槽位 2 写入夹具内容（_seed_slot）→ _switch_slot(2)」；原 :202/:217 dirty 断言（dirty 退役）
## → 「FileNameLabel『第二关 · 已加载』」+「内存态==盘上态」按体素域对账（block_size/blocks 会话数；
## apply_auto_meta 元数据窗口期差异属 spec §3.5-1 P2-6 预期，不比全文）。
func _g9_review5_fixes() -> void:
	var LP := preload("res://scripts/level_project.gd")
	var blocks := LP.TAG_BLOCKS
	var target := LP.TAG_TARGET
	# 路径①（实例 A）：blocks 页加载 2×2×2 槽位档——静默写尺寸不得误弹确认框
	_seed_slot(2, FileAccess.get_file_as_string(FIXTURE_TWO))
	_seed_meta(1)
	var ed_a: Control = await _fresh_editor()
	ed_a.call("_switch_slot", 2)
	var dlg: ConfirmationDialog = ed_a.get("_size_dialog")
	check(dlg != null and not dlg.visible, "G9: 槽位加载非当前尺寸档不误弹尺寸确认框（D-1）")
	var proj: RefCounted = ed_a.get("project")
	check_eq(proj.call("get_block_size"), Vector3i(2, 2, 2), "G9: 模型块尺寸=夹具 2×2×2")
	check_eq((ed_a.get("sessions") as Dictionary)[blocks].cells.size(), 8, "G9: blocks 会话载入 8 格实心")
	# 等价改写：原「打开未编辑不置 dirty」→ FileNameLabel 已加载（dirty 退役，spec §3.4-6）。
	check((ed_a.get_node("TopBar/FileNameLabel") as Label).text.contains("第二关 · 已加载"),
		"G9: 加载后 FileNameLabel=第二关 · 已加载（原 :202 dirty 断言等价改写）")
	# 等价改写：内存态==盘上态（体素域对账；元数据窗口期差异属 P2-6 预期，不比全文）。
	var disk_g9 := LP.new()
	var disk_ok: bool = disk_g9.load_from_text(SLOTS.load_slot_text(2, _sandbox_root))
	check(disk_ok and disk_g9.call("get_block_size") == Vector3i(2, 2, 2) \
		and (disk_g9.call("get_voxel_set", blocks) as Dictionary).size() == 8,
		"G9: 内存态==盘上态（block_size/blocks 体素域对账，原 :202/:217 dirty 断言等价改写）")
	check(not (dlg.dialog_text as String).contains("2×2×3"), "G9: 确认框文本不含中间态尺寸（新x,旧y,旧z）")
	# D-3：添加模式放置后清理幻影预览（不动）
	ed_a.call("_on_mode_changed", true)
	var view: Node = ed_a.get_node("MainPanel/VC/SubViewport/VoxelView")
	view.call("show_place_preview", Vector3i(0, 0, 0))
	ed_a.call("_on_add_requested", [Vector3i(0, 0, 0)])
	check(not bool(view.call("has_place_preview")), "G9: 添加模式放置后幻影预览清理（D-3）")
	# 路径②（实例 B）：非 blocks 页加载——直通路径不覆写加载提示（原「打开提示」口径随迁）
	_seed_slot(2, FileAccess.get_file_as_string(FIXTURE_TWO))
	_seed_meta(1)
	var ed_b: Control = await _fresh_editor()
	ed_b.call("switch_tag", target)
	ed_b.call("_switch_slot", 2)
	# 等价改写：原 :217「target 页打开同样不置 dirty」→ 加载成功语义由 FileNameLabel 承载（dirty 退役）。
	check((ed_b.get_node("TopBar/FileNameLabel") as Label).text.contains("第二关 · 已加载"),
		"G9: target 页加载同样成功（原 :217 dirty 断言等价改写）")
	var hint: String = (ed_b.get_node("StatusBar/StatusRow/ContractLabel") as Label).text
	check(hint.contains("piece") and not hint.contains("尺寸→"), "G9: 状态栏保持加载提示（双 piece）而非尺寸变更提示")

# ============ G10 试玩侧视相机布置+走查观感回修（T3-3，19→20 checks；D-4/D-5/D-6/D-7+W5 toast 锁） ============
## 红态依据（M3 走查 AI工作记录/walkthrough_20260912_editor/m3/）：TargetPanel/JoinPanel 相机
## tscn 无 transform（pos=(0,0,0)、ortho size=1）→ 试玩面板渲染体素内部特写、join 少体素时
## 格子出视锥面板全空（w11b/w12d）；toast 锚点 0.075~0.13 与 TargetPanel 标题带交叠（w12a）；
## 退出弹窗默认英文标题「Please Confirm...」（w13a）；锁定表单 editable=false 无观感差异。
## 相机还原断言口径（报告说明）：相机不进快照——退出后面板隐藏即无取景态；_enter_playtest
## 每次按当时体素集重新布置，故以「重进按新 join 集重取景」断言还原语义。
func _g10_playtest_side_cameras() -> void:
	var LP := preload("res://scripts/level_project.gd")
	# W4-1 转写（spec §3.4-8/P6 扩列）：两实例转 3³ 种子沙盒 + fresh_editor。
	_seed_333(1)
	_seed_meta(1)
	var ed: Control = await _fresh_editor()
	# 准备（走查 W11/W12 会话口径变体）：target=初始块挖 3 对角格（AABB 仍 3³）；join=单格
	# (2,0,0)——离等轴测对角线偏轴：若相机仍 look_at 原点，该格出视锥（「面板空」根因，证伪力最强）。
	var target_cells: Dictionary = (ed.get("sessions") as Dictionary)[LP.TAG_BLOCKS].cells.duplicate()
	target_cells.erase(Vector3i(0, 0, 0))
	target_cells.erase(Vector3i(1, 1, 1))
	target_cells.erase(Vector3i(2, 2, 2))
	(ed.get("sessions") as Dictionary)[LP.TAG_TARGET].setup(target_cells)
	(ed.get("sessions") as Dictionary)[LP.TAG_JOIN].setup({Vector3i(2, 0, 0): true})
	# 批次 Z Z1 等价改写留痕：左上面板渲染换源 final——取景断言对象随数据源迁移，final 喂同款
	# 24 格集（AABB 仍 3³，look/target 断言数值口径不变；target 同喂保留=「不再由 target 驱动」
	# 的隐性对照，精确判别由 tests/test_z_panel_final.gd C/C2 承载）。
	(ed.get("sessions") as Dictionary)[LP.TAG_FINAL].setup(target_cells.duplicate())
	ed.call("_enter_playtest")
	var tcam: Camera3D = ed.get_node("TargetPanel/VC/SubViewport/Camera3D")
	var jcam: Camera3D = ed.get_node("JoinPanel/VC/SubViewport/Camera3D")
	check_eq(tcam.projection, Camera3D.PROJECTION_ORTHOGONAL, "G10: Target 相机正交投影")
	check_eq(jcam.projection, Camera3D.PROJECTION_ORTHOGONAL, "G10: Join 相机正交投影")
	check(tcam.position != Vector3.ZERO, "G10: Target 相机非原点（D-4 内部特写根因）")
	check(jcam.position != Vector3.ZERO, "G10: Join 相机非原点")
	var iso: Vector3 = Vector3(11.547005, 11.547005, 11.547005)   # 20×(sin45°·cos35.264°, sin35.264°, cos45°·cos35.264°)
	check(tcam.position.distance_to(iso) < 0.01, "G10: Target 相机=游戏等轴测轨道位（ORTHO_DIST 20，level_scene.gd:1545 口径）")
	check(jcam.position.distance_to(iso) < 0.01, "G10: Join 相机=游戏等轴测轨道位（ORTHO_DIST 20）")
	check(tcam.size > 1.0, "G10: Target ortho size 按包围盒适配 >1")
	check(jcam.size > 1.0, "G10: Join ortho size 按包围盒适配 >1（join 单格也成立）")
	# look_at 体素集中心（游戏「集居中取景」同语义；编辑器视图中心定锚 block_size 中心，故目标
	# =集 AABB 中心−中心偏移）：Target 24 格中心→局部原点；join 单格 (2,0,0) 中心→局部 (1,-1,-1)。
	# 相机 +Z 轴 =（位姿−目标）归一（look_at 语义）。
	var tdir: Vector3 = iso.normalized()
	check(absf(tcam.transform.basis.z.dot(tdir) - 1.0) < 0.001, "G10: Target look_at=体素集中心（等轴测视轴）")
	var jdir: Vector3 = Vector3(10.547005, 12.547005, 12.547005).normalized()
	check(absf(jcam.transform.basis.z.dot(jdir) - 1.0) < 0.001, "G10: Join look_at=体素集中心（离轴格居中=空面板根因证伪）")
	check(jcam.is_position_in_frustum(Vector3(1, -1, -1)), "G10: join 格中心在 Join 相机视锥内（w12d 空面板直接证伪）")
	# D-7：试玩锁定左面板变暗——批次 W（P3-5f）等价改写留痕：变暗由整树 modulate 乘算（文字一并
	# 降对比，W0 §P3-5f）改为 self_modulate 只落面板背景（文字对比度保持，D-7 视觉差保留）。
	check_eq((ed.get_node("LeftPanel") as Control).self_modulate, Color(1, 1, 1, 0.55), "G10: 试玩锁定左面板 self_modulate 变暗（D-7；P3-5f 等价改写：modulate→self_modulate）")
	# D-6：退出确认弹窗中文标题（默认 Please Confirm...）
	check_eq((ed.get("_exit_playtest_dialog") as ConfirmationDialog).title, "退出试玩", "G10: 退出弹窗中文标题（D-6）")
	# D-5 原口径（toast 顶部带 0.02~0.06）已被 W5 走查 NG-1/NG-2 取代：W4 顶栏五槽位钮改造后
	# 顶部无可安放区（toast 与第四/第五关钮实体重叠撞色）→ 下移底部中央 anchor=(0.32,0.885)~
	# (0.68,0.925)：不压顶栏（0~0.075）/左面板（右缘 0.27）/状态栏（0.95 起），仅浮主视口下缘。
	var toast: Label = ed.get_node("PlaytestToast")
	check(absf(toast.anchor_left - 0.32) < 0.0001 and absf(toast.anchor_top - 0.885) < 0.0001 \
		and absf(toast.anchor_right - 0.68) < 0.0001 and absf(toast.anchor_bottom - 0.925) < 0.0001,
		"W5: toast 锚点防回退锁=底部中央 (0.32,0.885)~(0.68,0.925) 四值（NG-1/NG-2，取代 D-5 顶带口径）")
	ed.call("_do_exit_playtest")
	check(not (ed.get_node("TargetPanel") as Control).visible and not (ed.get_node("JoinPanel") as Control).visible, "G10: 退出双面板隐藏（相机不入快照：面板隐藏即无取景态）")
	check_eq((ed.get_node("LeftPanel") as Control).modulate, Color(1, 1, 1, 1), "G10: 退出左面板 modulate 还原（D-7）")
	# 还原口径断言：重进按当时体素集再次布置——join 换为另一离轴单格 (0,2,2)（局部中心 (-1,1,1)）
	(ed.get("sessions") as Dictionary)[LP.TAG_JOIN].setup({Vector3i(0, 2, 2): true})
	ed.call("_enter_playtest")
	var jcam2: Camera3D = ed.get_node("JoinPanel/VC/SubViewport/Camera3D")
	var jdir2: Vector3 = Vector3(12.547005, 10.547005, 10.547005).normalized()
	check(jcam2.position.distance_to(iso) < 0.01 and absf(jcam2.transform.basis.z.dot(jdir2) - 1.0) < 0.001, "G10: 重进按新 join 集重新布置（还原=重进重取景口径）")
	# tscn 兜底位姿（D-4 第二修点：非试玩路径不出现原点特写）——全新实例未进试玩，相机自带等轴测朝向
	_seed_333(1)
	_seed_meta(1)
	var ed0: Control = await _fresh_editor()
	var tcam0: Camera3D = ed0.get_node("TargetPanel/VC/SubViewport/Camera3D")
	var jcam0: Camera3D = ed0.get_node("JoinPanel/VC/SubViewport/Camera3D")
	check(tcam0.position.distance_to(iso) < 0.01 and absf(tcam0.transform.basis.z.dot(iso.normalized()) - 1.0) < 0.01, "G10: tscn 兜底 Target 相机=等轴测朝向（非试玩路径无原点特写）")
	check(jcam0.position.distance_to(iso) < 0.01 and absf(jcam0.transform.basis.z.dot(iso.normalized()) - 1.0) < 0.01, "G10: tscn 兜底 Join 相机=等轴测朝向")
	check(not (ed0.get_node("PlaytestToast") as Label).visible, "W5: toast 缺省 visible=false（NG-1/NG-2 锚点锁配套，防回退）")

# ============ G11 审查⑥回修回归（P2-3 试玩加块守卫 + P3-3 试玩态标题，6 checks） ============
## 红态依据（审查⑥对 559a1fb 前代码独立复核）：试玩 _on_add_requested 无 _in_playtest 守卫——
## 进入前处于添加模式（模式按钮锁定但模式不重置）时左键仍可向试玩会话加体素（§8.1 试玩=挖除）；
## 试玩中主标题/ModeLabel 仍显示进入前标签名。
## T4 删除留痕：P2-2 层号上界两实例断言（原 5 条）随批量区节点/函数全删。
func _g11_review6_fixes() -> void:
	# W4-1 转写（spec §3.4-8/P6 扩列）：3³ 种子沙盒 + fresh_editor（25 格绝对计数依赖 3³ 启动态）。
	_seed_333(1)
	_seed_meta(1)
	var ed2: Control = await _fresh_editor()
	ed2.call("_enter_playtest")
	ed2.call("_on_dig_requested", [Vector3i(0, 0, 0), Vector3i(1, 1, 1)])
	check_eq(ed2.get("_playtest_session").cells.size(), 25, "G11: 前置 试玩挖除 2 格剩 25")
	ed2.call("_on_add_requested", [Vector3i(0, 0, 0), Vector3i(1, 1, 1)])   # 先挖后加回=未修时会话净增 2 格
	check_eq(ed2.get("_playtest_session").cells.size(), 25, "G11: 试玩中 add 请求不落会话（P2-3）")
	check_eq((ed2.get_node("MainPanel/MainTitle") as Label).text, "试玩中（以初始木块挖除）", "G11: 试玩中主标题=试玩文案（P3-3）")
	check_eq((ed2.get_node("StatusBar/StatusRow/ModeLabel") as Label).text, "试玩中（以初始木块挖除）", "G11: 试玩中模式标签=试玩文案（P3-3）")
	ed2.call("_do_exit_playtest")
	check_eq((ed2.get_node("MainPanel/MainTitle") as Label).text, "初始木块 blocks", "G11: 退出主标题还原进入前标签名（P3-3）")
	check_eq((ed2.get_node("StatusBar/StatusRow/ModeLabel") as Label).text, "挖除｜初始木块 blocks", "G11: 退出模式标签还原（P3-3 复用 _refresh_status）")

# ============ G12 审查⑦回修回归（P1-1 主/侧视相机 near 裁剪 + P2-1 弹窗中文标题，13 checks） ============
## 红态依据（审查⑦对 e001a75 独立复核）：主相机轨道距离恒 ORTHO_DIST=20（editor_interaction.gd
## _update_camera），32³ 满块包围球半径=32√3/2≈27.7 → 最近角深度 20−27.7=−7.7 在相机平面之后，
## BoxMesh 背面剔除透见背景呈风筝形缺口（m4/32cube_06/02c/08 实证，T4-2 自评 §6 暗斑排除系证据错位）；
## 同根因随 D-4 复制进侧视相机（editor_main.gd _update_side_camera 恒 SIDE_ORTHO_DIST=20，约 23³ 起
## 侧面板同样缺块）。断言口径（审查⑦指定）：对 32×32×32 满块断言主相机与侧相机的最近角深度
## dist−r > near（0.1）——红态 dist 恒 20 时必红；另锁 far 全程不裁（dist+r<100）与小集行为不变
## （3³ 时 dist 仍=ORTHO_DIST 20，自适应仅大集触发）。主相机走生产路径 _execute_size_apply→
## _apply_change→refresh_view→_update_camera；侧相机直驱 _update_side_camera（D-4 生产布置函数，
## 避免 3×32768 视图节点重建——32³ 满载 target/join 的实弹观感复验由 m4/ 32cube_fix_* 走查承担）。
## P2-1：新建/尺寸确认弹窗补中文 title（对齐 D-6 口径，默认「Please Confirm...」与中文 UI 不符）。
func _g12_review7_fixes() -> void:
	var LP := preload("res://scripts/level_project.gd")
	var EI := load("res://scripts/editor_interaction.gd")
	var EM: GDScript = load("res://scenes/editor_main.gd")
	# W4-1 转写（spec §3.4-8）：3³ 种子沙盒 + fresh_editor（3³ 相机拟合半径/距离断言依赖 3³ 启动态）。
	_seed_333(1)
	_seed_meta(1)
	var ed: Control = await _fresh_editor()
	# 等价改写留痕（spec §6.4 G12 行）：原 :333「_new_dialog 中文标题」→ _new_dialog 随新建流程退役
	# （spec §3.6-2 删除清单），改消失断言；尺寸弹窗中文标题保留（P2-1/D-6 口径）。
	check(ed.get("_new_dialog") == null, "G12: _new_dialog 已随新建流程退役（原 :333 中文标题断言等价改写）")
	check_eq((ed.get("_size_dialog") as ConfirmationDialog).title, "调整尺寸", "G12: 尺寸确认弹窗中文标题（P2-1/D-6 口径）")
	# 小集 3³：主相机初始轨道距离=透视拟合值 r/tan(fov/2)×1.15（修复批二 F1；红态为正交档距 20）
	var mcam: Camera3D = ed.get_node("MainPanel/VC/SubViewport/Camera3D")
	var r3m: float = Vector3(3, 3, 3).length() * 0.5
	var fit3m: float = r3m / tan(deg_to_rad(mcam.fov) * 0.5) * 1.15
	check_eq(mcam.projection, Camera3D.PROJECTION_PERSPECTIVE, "G12: 主相机透视投影（修复批二 F1）")
	check(absf(mcam.position.length() - fit3m) < 0.01, "G12: 主相机 3³ 初始 dist=透视拟合值（F1）")
	# P1-1 主相机：32³ 尺寸应用（D2 生产路径 SpinBox 草稿→_on_apply_size_all_pressed→refresh_view→
	# _update_camera）+ 一键实心。等价改写留痕（spec §6.4 G12 行）：原 :329 入口 _on_apply_size_pressed
	# → 全局应用（32³/32768/dist 断言主体不变）。
	var solid32: Dictionary = LP.solid_cells(Vector3i(32, 32, 32))
	(ed.get("size_x") as SpinBox).value = 32.0
	(ed.get("size_y") as SpinBox).value = 32.0
	(ed.get("size_z") as SpinBox).value = 32.0
	ed.call("_on_apply_size_all_pressed")
	# 批次 U（U12②，双审 P2-4）等价替换留痕：32³ 放大=「无裁剪但有覆盖」→ 强制确认后执行（原零裁剪直执）。
	ed.call("_on_size_confirmed")
	check_eq(ed.get("project").call("get_block_size"), Vector3i(32, 32, 32), "G12: 零裁剪应用经确认写 block_size=32³（D2 生产路径，U12②）")
	check_eq((ed.get("sessions") as Dictionary)[LP.TAG_BLOCKS].cells.size(), 32768, "G12: blocks 标签应用=按 32³ 重生实心 32768（修复批二 F3 新语义）")
	ed.call("_on_solid_pressed")
	check_eq((ed.get("sessions") as Dictionary)[LP.TAG_BLOCKS].cells.size(), 32768, "G12: 一键实心 32³=生产路径幂等（供直径 32√3 断言）")
	var inter: Node = ed.get("interaction")
	var dia_main: float = inter.get("_diameter")   # 主视口径直径来源=_sphere_diameter_of（既有 fit 逻辑同源）
	var r_main: float = dia_main * 0.5
	check(absf(dia_main - Vector3(32, 32, 32).length()) < 0.001, "G12: 主视口径 包围球直径=32√3≈55.43")
	var dist_main: float = mcam.position.length()   # look_at(ZERO) 且模型居中原点，position 模长=轨道距离
	check(dist_main - r_main > 0.1, "G12: 主相机 32³ 最近角深度 dist−r>near=0.1（P1-1；红态 dist 恒 20→−7.7）")
	check(dist_main + r_main < 100.0, "G12: 主相机 32³ 最远角深度 dist+r<far=100（far 不裁）")
	# P1-1 侧相机：target/join 各喂 32³ 满块，直驱 _update_side_camera（D-4 布置函数）。
	# 视图中心定锚与生产同口径：先 build_set 空集令 _center_offset=block_size 中心（零节点开销，
	# 32³ 满载实弹观感由 m4/ 32cube_fix_* 走查承担）——look_at 目标=集 AABB 中心−视图中心偏移=原点。
	var VV := load("res://scripts/editor_view.gd")
	var mat: Material = VV.make_wood_material(VV.WOOD_LIGHT)
	var tview: Node = ed.get_node("TargetPanel/VC/SubViewport/VoxelView")
	var jview: Node = ed.get_node("JoinPanel/VC/SubViewport/VoxelView")
	tview.call("build_set", {}, Vector3i(32, 32, 32), mat)
	jview.call("build_set", {}, Vector3i(32, 32, 32), mat)
	ed.call("_update_side_camera", "Target", solid32)
	ed.call("_update_side_camera", "Join", solid32)
	var dia_side: float = EM._cells_sphere_diameter(solid32)   # 侧视口径直径来源=_cells_sphere_diameter
	var r_side: float = dia_side * 0.5
	check(absf(dia_side - Vector3(32, 32, 32).length()) < 0.001, "G12: 侧视口径 包围球直径=32√3≈55.43")
	var tcam: Camera3D = ed.get_node("TargetPanel/VC/SubViewport/Camera3D")
	var jcam: Camera3D = ed.get_node("JoinPanel/VC/SubViewport/Camera3D")
	var t_look: Vector3 = EI.cells_center(solid32) - (tview.call("get_center_offset") as Vector3)
	var j_look: Vector3 = EI.cells_center(solid32) - (jview.call("get_center_offset") as Vector3)
	var dist_t: float = tcam.position.distance_to(t_look)   # look_at 目标=集 AABB 中心（实现同式）
	var dist_j: float = jcam.position.distance_to(j_look)
	check(dist_t - r_side > 0.1, "G12: 侧相机 Target 32³ 最近角深度 dist−r>near=0.1（P1-1 同根因 D-4 路径）")
	check(dist_j - r_side > 0.1, "G12: 侧相机 Join 32³ 最近角深度 dist−r>near=0.1（P1-1 同根因 D-4 路径）")
	check(dist_t + r_side < 100.0 and dist_j + r_side < 100.0, "G12: 侧相机 32³ 最远角深度 dist+r<far=100（far 不裁）")

# ============ G13 布局双态（T1 修复批，10 checks；D1 编辑态全高 / D3 试玩态逐像素不动） ============
## 红态依据：MainPanel 锚点固定 0.27~0.995 × 0.43~0.945（tscn），Target/Join 隐藏后上带闲置；
## 单一权威 _apply_layout(EDIT|PLAYTEST) 收敛两态，代码为唯一权威。锚点值断言用属性值（坑 2）。
func _g13_layout_dual_state() -> void:
	var scene: PackedScene = load("res://scenes/editor_main.tscn")
	var ed: Control = scene.instantiate()
	add_child(ed)
	await process_frame   # --script 模式 add_child 不立即进树（_ready 延后一帧，G6 惯例随迁）
	var main_panel: Control = ed.get_node("MainPanel")
	var tpanel: Control = ed.get_node("TargetPanel")
	var jpanel: Control = ed.get_node("JoinPanel")
	# EDIT 态（_ready 后统一进 EDIT）
	check(absf(main_panel.anchor_left - 0.27) < 0.0001 and absf(main_panel.anchor_top - 0.075) < 0.0001, "G13: EDIT 态 MainPanel 左上锚=0.27/0.075（顶带让位）")
	check(absf(main_panel.anchor_right - 0.995) < 0.0001 and absf(main_panel.anchor_bottom - 0.945) < 0.0001, "G13: EDIT 态 MainPanel 右下锚=0.995/0.945（右侧全高）")
	check(not tpanel.visible, "G13: EDIT 态 TargetPanel 隐藏")
	check(not jpanel.visible, "G13: EDIT 态 JoinPanel 隐藏")
	# PLAYTEST 态
	ed.call("_enter_playtest")
	check(absf(main_panel.anchor_top - 0.43) < 0.0001, "G13: PLAYTEST 态 MainPanel 回下带 top=0.43")
	check(absf(tpanel.anchor_left - 0.27) < 0.0001 and absf(tpanel.anchor_top - 0.075) < 0.0001 \
		and absf(tpanel.anchor_right - 0.59) < 0.0001 and absf(tpanel.anchor_bottom - 0.42) < 0.0001, "G13: PLAYTEST 态 TargetPanel 锚点=0.27/0.075/0.59/0.42（现状逐像素）")
	check(absf(jpanel.anchor_left - 0.61) < 0.0001 and absf(jpanel.anchor_top - 0.075) < 0.0001 \
		and absf(jpanel.anchor_right - 0.995) < 0.0001 and absf(jpanel.anchor_bottom - 0.42) < 0.0001, "G13: PLAYTEST 态 JoinPanel 锚点=0.61/0.075/0.995/0.42（现状逐像素）")
	check(tpanel.visible and jpanel.visible, "G13: PLAYTEST 态 双面板可见")
	# 退出回 EDIT
	ed.call("_do_exit_playtest")
	check(absf(main_panel.anchor_top - 0.075) < 0.0001, "G13: 退出试玩 MainPanel 回 top=0.075（EDIT 全高）")
	check(not tpanel.visible and not jpanel.visible, "G13: 退出试玩双面板隐藏")
	ed.free()

# ============ G15 VIEW 只读预览交互（T3 修复批，11 checks；D3 试玩上两面板可旋转缩放、零编辑信号） ============
## 红态：editor_main 无 _view_interaction_target/_view_interaction_join（取 null 报错中止）。
## 视图实例用直调 _on_gui_input 伪造事件（坑 5），断言拖拽/滚轮改相机但零编辑信号，退出解绑并复位。
func _g15_view_interaction() -> void:
	var scene: PackedScene = load("res://scenes/editor_main.tscn")
	var LP := preload("res://scripts/level_project.gd")
	var EI := preload("res://scripts/editor_interaction.gd")
	var ed: Control = scene.instantiate()
	add_child(ed)
	await process_frame   # --script 模式 add_child 不立即进树（_ready 延后一帧，G6 惯例随迁）
	(ed.get("sessions") as Dictionary)[LP.TAG_TARGET].setup(LP.solid_cells(Vector3i(3, 3, 3)))
	(ed.get("sessions") as Dictionary)[LP.TAG_JOIN].setup({Vector3i(2, 0, 0): true})
	# 批次 Z Z1 等价改写留痕：左上面板渲染/取景换源 final——本组退出复位断言（D3「退出两侧相机
	# 复位等轴测机位」）的对象随数据源迁移到 final 集（solid 3³ 同款，look=集中心−视图中心=原点，
	# 断言数值口径不变；漏喂 final 时退出复位走空集早退、相机残留拖拽位姿必红——本行即护栏夹具前提）。
	(ed.get("sessions") as Dictionary)[LP.TAG_FINAL].setup(LP.solid_cells(Vector3i(3, 3, 3)))
	ed.call("_enter_playtest")
	var tvi: Node = ed.get("_view_interaction_target")
	var jvi: Node = ed.get("_view_interaction_join")
	check(tvi != null and tvi.get("_container") != null and int(tvi.get("_bind_mode")) == EI.BindMode.VIEW, "G15: Target VIEW 实例已绑容器且模式=VIEW")
	check(jvi != null and jvi.get("_container") != null and int(jvi.get("_bind_mode")) == EI.BindMode.VIEW, "G15: Join VIEW 实例已绑容器且模式=VIEW")
	var tcam: Camera3D = ed.get_node("TargetPanel/VC/SubViewport/Camera3D")
	var jcam: Camera3D = ed.get_node("JoinPanel/VC/SubViewport/Camera3D")
	var size_before: float = tcam.size
	for _i: int in 2:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		tvi.call("_on_gui_input", wheel)
	check(tcam.size > size_before * 1.1, "G15: VIEW 滚轮缩放放大 Target 相机 size")
	var tpos_before: Vector3 = tcam.position
	var mid_down := InputEventMouseButton.new()
	mid_down.button_index = MOUSE_BUTTON_MIDDLE
	mid_down.pressed = true
	mid_down.position = Vector2(100, 100)
	tvi.call("_on_gui_input", mid_down)
	var mid_move := InputEventMouseMotion.new()
	mid_move.position = Vector2(160, 130)
	tvi.call("_on_gui_input", mid_move)
	check(tcam.position.distance_to(tpos_before) > 0.001, "G15: VIEW 中键拖拽旋转改变 Target 相机位姿")
	var dug: Array = []
	var added: Array = []
	tvi.connect("dig_requested", func(cells: Array) -> void: dug.append_array(cells))
	tvi.connect("add_requested", func(cells: Array) -> void: added.append_array(cells))
	var r_down := InputEventMouseButton.new()
	r_down.button_index = MOUSE_BUTTON_RIGHT
	r_down.pressed = true
	r_down.position = Vector2(10, 10)
	tvi.call("_on_gui_input", r_down)
	var r_move := InputEventMouseMotion.new()
	r_move.position = Vector2(60, 10)
	tvi.call("_on_gui_input", r_move)
	var r_up := InputEventMouseButton.new()
	r_up.button_index = MOUSE_BUTTON_RIGHT
	r_up.pressed = false
	r_up.position = Vector2(60, 10)
	tvi.call("_on_gui_input", r_up)
	check(dug.is_empty() and added.is_empty(), "G15: VIEW 右键拖拽零编辑信号")
	check((tvi.call("get_selected") as Array).is_empty(), "G15: VIEW 无拾取无选区")
	var remain_before: int = (ed.get("_playtest_session") as RefCounted).cells.size()
	ed.call("_on_dig_requested", [Vector3i(0, 0, 0)])
	check_eq((ed.get("_playtest_session") as RefCounted).cells.size(), remain_before - 1, "G15: 主视口隔离——试玩挖除仅落主会话")
	ed.call("_do_exit_playtest")
	check(tvi.get("_container") == null and jvi.get("_container") == null, "G15: 退出试玩两 VIEW 实例解绑（_container=null）")
	var iso: Vector3 = Vector3(11.547005, 11.547005, 11.547005)
	check(tcam.position.distance_to(iso) < 0.01 and jcam.position.distance_to(iso) < 0.01, "G15: 退出两侧相机复位标准等轴测机位（D3）")
	check(tcam.size > 1.0 and jcam.size > 1.0, "G15: 退出两侧相机 ortho size 复位取景值（D3 属性级）")
	check((ed.get_node("TargetPanel/Title") as Label).mouse_filter == Control.MOUSE_FILTER_IGNORE, "G15: 预览面板 Title 标签 mouse_filter=IGNORE 兜底")
	ed.free()

# ============ G16 审查回修批 P1-1：VIEW 缩放口径同源化（3 checks） ============
## 红态依据（审查对 0597f7a 独立复核）：editor_interaction._update_camera 夹持下限恒为
## _fit_ortho_size（VIEW_FIT_MARGIN=24 口径），而进试玩播种 sync_from_camera 取相机当前 size
## （editor_main._side_fit_ortho_size，SIDE_FILL_W0=0.70/SIDE_FIT_MARGIN=8 口径）——24px 口径
## 下限 > 播种值（约 +17%），首次拖拽/滚轮即被夹高（画面突然缩小）且 zoom in 回不到标准档。
## 断言口径：拖拽/滚轮均伪造 gui_input（坑 5）；播种后拖拽两侧 size 零跳变；滚轮一档 zoom in
## 严格小于播种值、再一档 zoom out 回到 ≈播种值（±0.05）。缩放轮询用 Join 单格实例（播种值小，
## 1% 往返误差落在 ±0.05 内）。
func _g16_p11_view_zoom_floor() -> void:
	var scene: PackedScene = load("res://scenes/editor_main.tscn")
	var LP := preload("res://scripts/level_project.gd")
	var ed: Control = scene.instantiate()
	add_child(ed)
	await process_frame   # --script 模式 add_child 不立即进树（_ready 延后一帧，G6 惯例随迁）
	# 复现真实 GUI 面板几何（宽扁 397×236；无头默认布局为高窄 391×423，会把两口径大小关系反转）。
	# stretch=false 固定 SubViewport 自身尺寸，免容器布局改写。
	var tvc: SubViewportContainer = ed.get_node("TargetPanel/VC")
	var jvc: SubViewportContainer = ed.get_node("JoinPanel/VC")
	var tvp: SubViewport = ed.get_node("TargetPanel/VC/SubViewport")
	var jvp: SubViewport = ed.get_node("JoinPanel/VC/SubViewport")
	tvc.stretch = false
	jvc.stretch = false
	tvp.size = Vector2i(397, 236)
	jvp.size = Vector2i(470, 236)
	(ed.get("sessions") as Dictionary)[LP.TAG_TARGET].setup(LP.solid_cells(Vector3i(3, 3, 3)))
	(ed.get("sessions") as Dictionary)[LP.TAG_JOIN].setup({Vector3i(2, 0, 0): true})
	# 批次 Z Z1 等价改写留痕：左上面板渲染/取景换源 final——Target 侧「首次拖拽零跳变」走
	# 真实播种路径的夹具前提（final 同喂 solid 3³；漏喂则 final 空集、Target 侧断言空转）。
	(ed.get("sessions") as Dictionary)[LP.TAG_FINAL].setup(LP.solid_cells(Vector3i(3, 3, 3)))
	ed.call("_enter_playtest")
	var tvi: Node = ed.get("_view_interaction_target")
	var jvi: Node = ed.get("_view_interaction_join")
	var tcam: Camera3D = ed.get_node("TargetPanel/VC/SubViewport/Camera3D")
	var jcam: Camera3D = ed.get_node("JoinPanel/VC/SubViewport/Camera3D")
	var t_seed: float = tcam.size
	var j_seed: float = jcam.size
	# (a) 首次拖拽（旋转）两侧相机 size 零跳变
	_drag_orbit(tvi, Vector2(100, 100), Vector2(160, 130))
	_drag_orbit(jvi, Vector2(100, 100), Vector2(160, 130))
	check(absf(tcam.size - t_seed) <= 0.01 and absf(jcam.size - j_seed) <= 0.01,
		"G16: 首次拖拽零跳变——两侧相机 size 变化 ≤0.01（P1-1）")
	# (b) 滚轮一档 zoom in 严格小于播种值；再一档 zoom out 回到 ≈播种值
	var j_before_wheel: float = jcam.size
	_wheel_once(jvi, true)
	var j_zoomed_in: float = jcam.size
	check(j_zoomed_in < j_before_wheel - 0.0001, "G16: 滚轮 zoom in 一档 size 严格小于播种值（P1-1）")
	_wheel_once(jvi, false)
	check(absf(jcam.size - j_seed) <= 0.05, "G16: 再 zoom out 一档回到 ≈播种值 ±0.05（P1-1）")
	ed.call("_do_exit_playtest")
	ed.free()

## 伪造一段中键按下→拖动→抬起（VIEW 轨道旋转）。
func _drag_orbit(vi: Node, down_pos: Vector2, move_pos: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_MIDDLE
	down.pressed = true
	down.position = down_pos
	vi.call("_on_gui_input", down)
	var move := InputEventMouseMotion.new()
	move.position = move_pos
	vi.call("_on_gui_input", move)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_MIDDLE
	up.pressed = false
	up.position = move_pos
	vi.call("_on_gui_input", up)

## 伪造一次滚轮（up=true 为 WHEEL_UP=zoom in）。
func _wheel_once(vi: Node, up: bool) -> void:
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP if up else MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	vi.call("_on_gui_input", wheel)

# ============ G17 审查回修批 P2-1：试玩锁定补尺寸应用按钮（1→2 checks） ============
## 红态（原 :534 随迁）：_locked_controls() 未含尺寸应用按钮，试玩中该按钮不 disabled。
## 等价改写留痕（spec §6.4 G17 行）：原 :541「btn_apply_size disabled」→ 双钮各自 disabled（一拆二，+1）。
func _g17_p21_playtest_locked_apply() -> void:
	var scene: PackedScene = load("res://scenes/editor_main.tscn")
	var ed: Control = scene.instantiate()
	add_child(ed)
	await process_frame   # --script 模式 add_child 不立即进树（_ready 延后一帧，G6 惯例随迁）
	ed.call("_enter_playtest")
	check((ed.get("btn_apply_size_one") as Button).disabled, "G17: 试玩中「仅当前组件应用」按钮 disabled（P2-1）")
	check((ed.get("btn_apply_size_all") as Button).disabled, "G17: 试玩中「全局应用」按钮 disabled（P2-1）")
	ed.free()

# ============ G18 审查回修批 P2-4：跨标签复合撤销还原护栏（5→7 checks） ============
## 缺口：R2 核心痛点=在一次尺寸收缩里把「发起标签以外」的标签格子连带裁剪，undo 时一并还原。
## 等价改写留痕（spec §6.4 G18 行 P1-2 数值重算 + 隔离性修复批 20260917 R4 数值链重算）：
## 旧 43 格造格依赖「join 页应用不重生 blocks」——regen 同域新口径下失效，造格路径重设计为 dig 构造：
## 3³ 下 blocks 页 dig (0,0,0)（剩 26）→ target 加 (2,2,2) 1 格 → join 加 (2,0,0) 1 格
## → join 页 _on_apply_size_all_pressed 2×2×2 收缩。
## 新数值锚（隔离性修复批 R4 重算：全局应用四页全部「裁剪+重生实心」，逐域差集对）：
## blocks 重生实心 2³=8；by_tag[0]={removed:19, added:1}（旧 26 格中越界 19 格、(0,0,0) 被重生补回故
## added=1）；by_tag[1]={1,8}、by_tag[2]={1,8}（发起标签，顶层单元={removed:[(2,0,0)], added:8 实心格}，
## P0-1——顶层=发起标签裁剪+重生定稿差集对）；by_tag[3]={0,8}。
func _g18_p24_cross_tag_compound() -> void:
	var LP := preload("res://scripts/level_project.gd")
	# W4-1 转写（spec §3.4-8/P6 同款裁决扩列）：3³ 种子沙盒 + fresh_editor——dig 造格 26 格绝对计数
	# 依赖 3³ 启动态（计划转换清单漏列 G18，按 P6 G10/G11 扩列同一理由补齐，报告留痕）。
	_seed_333(1)
	_seed_meta(1)
	var ed: Control = await _fresh_editor()
	var blocks: RefCounted = (ed.get("sessions") as Dictionary)[LP.TAG_BLOCKS]
	var target: RefCounted = (ed.get("sessions") as Dictionary)[LP.TAG_TARGET]
	var join: RefCounted = (ed.get("sessions") as Dictionary)[LP.TAG_JOIN]
	# 造格（P1-2 重设计）：blocks 页挖 (0,0,0) 剩 26 → target 加 (2,2,2) → join 加 (2,0,0)
	ed.call("_on_dig_requested", [Vector3i(0, 0, 0)])
	ed.call("switch_tag", LP.TAG_TARGET)
	ed.call("_on_add_requested", [Vector3i(2, 2, 2)])
	ed.call("switch_tag", LP.TAG_JOIN)
	ed.call("_on_add_requested", [Vector3i(2, 0, 0)])
	ed.call("_sync_sessions_to_project")
	# 护栏有效性前置（替换旧 :575 的 43 格断言并留痕 P1-2 重设计原因）
	check(blocks.cells.size() == 26 and target.cells.size() == 1 and join.cells.size() == 1,
		"G18: 前置 blocks 26+target 1+join 1（dig 造格，护栏有效性前置；旧 43 格造格依赖 join 页应用不重生 blocks——regen 同域新口径下失效，P1-2 重设计）")
	# join 页改框 2×2×2 → 全局应用（裁剪路径，确认回调）
	(ed.get("size_x") as SpinBox).value = 2.0
	(ed.get("size_y") as SpinBox).value = 2.0
	(ed.get("size_z") as SpinBox).value = 2.0
	ed.call("_on_apply_size_all_pressed")
	ed.call("_on_size_confirmed")
	# ① 收缩后：blocks 重生实心 2³=8、target/join 重生实心 2³=8、block_size=2³
	# 【隔离性修复批 R4 反转留痕】原「target/join 被裁空（0 格）」断言反转：全局应用四页全部重生实心。
	check(blocks.cells.size() == 8 and ed.get("project").call("get_block_size") == Vector3i(2, 2, 2) \
		and target.cells.size() == 8 and join.cells.size() == 8,
		"G18: ①收缩后 blocks 重生实心 2³=8 且 target/join 重生实心 2³=8（block_size=2³，隔离性修复批 R4，原「被裁空」断言反转，P2-4）")
	# ② 结构断言（P0-1）：顶层单元=发起标签 join 自身 diff（裁剪+重生定稿差集对）；removed_by_tag 每项={removed, added} 对
	var unit_g18: Dictionary = join.undo_stack.back()
	var cp_g18: Dictionary = unit_g18["compound"]
	check((unit_g18["removed"] as Array) == [Vector3i(2, 0, 0)] and (unit_g18["added"] as Array).size() == 8,
		"G18: ②顶层单元=发起标签 join 自身 diff {removed:[(2,0,0)], added:8 实心格}（P0-1；隔离性修复批：发起标签 diff=裁剪+重生定稿差集对，原 added:[] 断言反转）")
	check((cp_g18["removed_by_tag"][0] as Dictionary).has("removed") \
		and (cp_g18["removed_by_tag"][0]["removed"] as Array).size() == 19 \
		and (cp_g18["removed_by_tag"][0]["added"] as Array).size() == 1 \
		and (cp_g18["removed_by_tag"][1]["removed"] as Array).size() == 1 \
		and (cp_g18["removed_by_tag"][1]["added"] as Array).size() == 8 \
		and (cp_g18["removed_by_tag"][2]["removed"] as Array).size() == 1 \
		and (cp_g18["removed_by_tag"][2]["added"] as Array).size() == 8 \
		and (cp_g18["removed_by_tag"][3]["removed"] as Array).size() == 0 \
		and (cp_g18["removed_by_tag"][3]["added"] as Array).size() == 8,
		"G18: ②by_tag 对结构+数值锚（R4 重算）：by_tag[0]={19,1}（重生差集对）、by_tag[1]={1,8}、by_tag[2]={1,8}（发起标签）、by_tag[3]={0,8}（四页全重生，P0-1）")
	# ③ join 一次 undo → 四域尺寸回 3³ + blocks 26 + target 1 + join 1 全还原
	ed.call("_apply_undo")
	var sizes_ok: bool = true
	for tag: int in [LP.TAG_BLOCKS, LP.TAG_TARGET, LP.TAG_JOIN, LP.TAG_FINAL]:
		if ed.get("project").call("get_size_for_tag", tag) != Vector3i(3, 3, 3):
			sizes_ok = false
	check(sizes_ok and blocks.cells.size() == 26 and target.cells.size() == 1 and join.cells.size() == 1,
		"G18: ③join 一次 undo 四域尺寸回 3³ + blocks 26+target 1+join 1 全还原（P2-4 分域还原）")
	# ④ redo 复现收缩后状态
	ed.call("_apply_redo")
	check(blocks.cells.size() == 8 and ed.get("project").call("get_block_size") == Vector3i(2, 2, 2),
		"G18: ④redo 复现收缩后状态（blocks 8、尺寸 2³，P2-4）")
	# ⑤ 再一轮 undo/redo 幂等（数值锚 R4 重算：与①一致，四页全重生实心 2³）
	ed.call("_apply_undo")
	ed.call("_apply_redo")
	check(blocks.cells.size() == 8 and target.cells.size() == 8 and join.cells.size() == 8,
		"G18: ⑤重复一轮 undo/redo 幂等（R4 重算：四页全重生实心 2³，原「target/join 0 格」断言反转，P2-4）")

## 格集全等（键集合逐一同值；Dictionary == 语义不作依赖）。
func _same_cell_set(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k: Variant in b:
		if not a.has(k):
			return false
	return true

# ============ G19 修复批二 F1/F2：主视口透视相机 + 格集 AABB 中心取景 ============
## 红态依据（用户实测反馈 20260913 + p02 实锤）：主相机 projection=1（正交）、look_target 恒 ZERO
## （EDIT 从不注入），尺寸放大后旧格群贴容器最小角渲染、相机仍注视容器中心 → 格群被甩出视口。
## 修复口径：EDIT 主相机=透视（fov 50~55），look_target=当前标签格集 AABB 中心（世界系，扣视图
## 中心偏移），轨道距离 dist 由包围球半径/ tan(fov/2)×1.15 拟合、滚轮推拉 dist；VIEW 侧视仍正交。
func _g19_perspective_and_center_framing() -> void:
	var LP := preload("res://scripts/level_project.gd")
	# W4-1 转写（spec §3.4-8）：3³ 种子沙盒 + fresh_editor（r3=3³ 包围球半径断言依赖 3³ 启动态）。
	_seed_333(1)
	_seed_meta(1)
	var ed: Control = await _fresh_editor()
	var inter: Node = ed.get("interaction")
	var mcam: Camera3D = ed.get_node("MainPanel/VC/SubViewport/Camera3D")
	var mvp: SubViewport = ed.get_node("MainPanel/VC/SubViewport")
	# F1：透视投影 + fov 区间 + 默认标准工具视角（yaw=30/pitch=28，见常量）
	check_eq(mcam.projection, Camera3D.PROJECTION_PERSPECTIVE, "G19: 主相机透视投影（F1）")
	check(mcam.fov >= 50.0 and mcam.fov <= 55.0, "G19: 主相机 fov 50~55（F1，实际 %.2f）" % mcam.fov)
	check(inter.get("_orbit_yaw") != null and absf(rad_to_deg(float(inter.get("_orbit_yaw"))) - 30.0) < 0.01,
		"G19: 初始 yaw=30°（标准工具视角，F1）")
	check(absf(rad_to_deg(float(inter.get("_orbit_pitch"))) - 28.0) < 0.01, "G19: 初始 pitch=28°（F1）")
	# F1：初始轨道距离=包围球半径/tan(fov/2)×1.15（半径=格集包围球，look_target=原点故位姿模长=dist）
	var r3: float = Vector3(3, 3, 3).length() * 0.5
	var fit3: float = r3 / tan(deg_to_rad(mcam.fov) * 0.5) * 1.15
	check(absf(mcam.position.length() - fit3) < 0.01,
		"G19: 初始 dist=包围球半径/tan(fov/2)×1.15（F1，期望 %.4f 实际 %.4f）" % [fit3, mcam.position.length()])
	# F1：滚轮=推拉距离（zoom in dist 变小、zoom out 变大），投影恒透视
	var dist_before: float = float(inter.get("_dist"))
	inter.call("_on_wheel", true)
	check(float(inter.get("_dist")) < dist_before - 0.0001, "G19: 滚轮 zoom in 推近 dist（F1）")
	inter.call("_on_wheel", false)
	check(absf(float(inter.get("_dist")) - dist_before) < 0.1, "G19: 滚轮 zoom out 回到原 dist（F1；乘法往返 0.99 容差）")
	check_eq(mcam.projection, Camera3D.PROJECTION_PERSPECTIVE, "G19: 滚轮后仍透视（F1）")
	# F2：默认 3³ 实心居中 → look_target=世界原点（集 AABB 中心 − 视图中心偏移 = 0）
	check((inter.get("_look_target") as Vector3).length() < 0.001, "G19: 默认 3³ look_target=集 AABB 中心（原点，F2）")
	# F1 拾取适配：透视相机下 unproject 已知最近格 (2,2,2) 中心→ _pick_at 命中同格（射线来自
	# project_ray_origin/normal，投影无关；本断言为透视拾取判红护栏；须在挖除前跑，3³ 满载最近命中）
	var off: Vector3 = ed.get_node("MainPanel/VC/SubViewport/VoxelView").call("get_center_offset")
	var world222: Vector3 = Vector3(2.5, 2.5, 2.5) - off
	var scr: Vector2 = mcam.unproject_position(world222)
	if mvp.size.x < 1.0:
		print("[SKIP] G19: SubViewport 未布局，透视拾取断言退化")
	else:
		check_eq(inter.call("_pick_at", scr), Vector3i(2, 2, 2), "G19: 透视相机下 unproject 反查拾取命中 (2,2,2)（F1 拾取适配）")
		var far_scr := Vector2(-10000.0, -10000.0)
		check_eq(inter.call("_pick_at", far_scr), Vector3i(-1, -1, -1), "G19: 视口外射线拾取 NO_CELL（F1）")
	# F2：挖掉 x=2 整面（9 格）→ 余集 AABB=0..1×0..2×0..2，中心 world=(1,1.5,1.5)−(1.5,1.5,1.5)=(−0.5,0,0)
	var face: Array = []
	for y: int in range(3):
		for z: int in range(3):
			face.append(Vector3i(2, y, z))
	ed.call("_on_dig_requested", face)
	var expect_lt := Vector3(-0.5, 0.0, 0.0)
	check((inter.get("_look_target") as Vector3).distance_to(expect_lt) < 0.001,
		"G19: look_target 随集 AABB 中心移动（期望 %s 实际 %s，F2）" % [str(expect_lt), str(inter.get("_look_target"))])
	# F2：look_at 语义——相机 +Z 轴指向由注视目标到相机的方向（Godot look_at：basis.z = pos−target）
	var back: Vector3 = mcam.position - (inter.get("_look_target") as Vector3)
	check(mcam.transform.basis.z.dot(back.normalized()) > 0.999, "G19: 相机 +Z=注视目标反方向（look_at，F2）")
	# F1：VIEW 侧视不受影响仍正交（进试玩后 Target 相机 projection=1）
	ed.call("_enter_playtest")
	var tcam: Camera3D = ed.get_node("TargetPanel/VC/SubViewport/Camera3D")
	check_eq(tcam.projection, Camera3D.PROJECTION_ORTHOGONAL, "G19: VIEW 面板相机仍正交（F1 主视口专属）")
	ed.call("_do_exit_playtest")

# ============ G20 修复批二 F3：容器线框常显 + blocks 应用尺寸重生实心 ============
## 红态依据（用户实测反馈 f1 截图 + p02）：零裁剪时格子不变且无容器边界显示 → 尺寸应用无视觉表达；
## 容器线框仅空集显示。修复口径：①容器包围盒线框始终按 block_size 全范围绘制（独立于格集）；
## ②blocks 标签（active_tag==0）应用尺寸后自动按新尺寸重生实心、并入复合撤销单元（一次 Ctrl+Z 同
## 还原尺寸+旧格集）；确认弹窗注明重生文案；零裁剪重生路径状态栏/toast 也有反馈。其他标签只裁剪+线框。
func _g20_size_regen_and_container_bounds() -> void:
	var LP := preload("res://scripts/level_project.gd")
	# W4-1 转写（spec §3.4-8）：3³ 种子沙盒 + fresh_editor（前置默认 3³=27 断言依赖 3³ 启动态）。
	_seed_333(1)
	_seed_meta(1)
	var ed: Control = await _fresh_editor()
	var blocks: RefCounted = (ed.get("sessions") as Dictionary)[LP.TAG_BLOCKS]
	var join: RefCounted = (ed.get("sessions") as Dictionary)[LP.TAG_JOIN]
	var view: Node = ed.get_node("MainPanel/VC/SubViewport/VoxelView")
	# (a) 零裁剪放大 blocks：3³→5×10×4 直接重生实心 200 格（无确认框）+ 容器线框=新尺寸
	# 等价改写留痕（spec §6.4 G20 行）：入口 _on_apply_size_pressed→_on_apply_size_all_pressed（全局语义，下同）。
	check_eq(blocks.cells.size(), 27, "G20: 前置默认 3³=27 格")
	(ed.get("size_x") as SpinBox).value = 5.0
	(ed.get("size_y") as SpinBox).value = 10.0
	(ed.get("size_z") as SpinBox).value = 4.0
	ed.call("_on_apply_size_all_pressed")
	# 批次 U（U12②，双审 P2-4）等价替换留痕：零裁剪放大=「无裁剪但有覆盖」→ 强制弹确认
	# （原「零裁剪放大不弹确认框（直接重生）」断言反转）；confirmed 直执执行体。
	check((ed.get("_size_dialog") as ConfirmationDialog).visible,
		"G20: 零裁剪放大弹确认框（U12②「无裁剪但有覆盖」不再跳过，双审 P2-4；原「不弹确认框」断言反转）")
	ed.call("_on_size_confirmed")
	check_eq(ed.get("project").call("get_block_size"), Vector3i(5, 10, 4), "G20: block_size=5×10×4")
	check_eq(blocks.cells.size(), 200, "G20: blocks 标签应用放大=按新尺寸重生实心 200 格（F3）")
	var hint1: String = (ed.get_node("StatusBar/StatusRow/ContractLabel") as Label).text
	check(hint1.contains("已重生实心") and hint1.contains("200"), "G20: 零裁剪重生路径状态栏反馈（含已重生实心/200，F3）")
	check(not blocks.undo_stack.is_empty() and (blocks.undo_stack.back() as Dictionary).has("compound"),
		"G20: 重生应用入复合撤销单元（F3）")
	check(bool(view.call("has_bounds")) and view.call("get_bounds_size") == Vector3i(5, 10, 4),
		"G20: 非空集也常显容器线框且尺寸=block_size 5×10×4（F3）")
	# (b) 一次 undo 同还原尺寸 3³ + 旧 27 格
	ed.call("_apply_undo")
	check_eq(ed.get("project").call("get_block_size"), Vector3i(3, 3, 3), "G20: 一次 undo 还原尺寸 3³（F3）")
	check_eq(blocks.cells.size(), 27, "G20: 一次 undo 同还原旧 27 格（重生 173 格撤销，F3）")
	check(view.call("get_bounds_size") == Vector3i(3, 3, 3), "G20: undo 后容器线框随尺寸回 3³（F3）")
	# (c) redo 复现重生 200 格
	ed.call("_apply_redo")
	check_eq(blocks.cells.size(), 200, "G20: 一次 redo 重做重生实心 200 格（F3）")
	# (d) 非 blocks（join）单组件应用放大：只动 join 域（join_part.size），block_size 域与 blocks 格子零操作
	# 【回归锁改写 ×2+数值链重算留痕，spec §6.4 G20(d) 行+隔离性修复批 20260917】：旧 :716 get_block_size==6×10×4
	# （四域共享语义正是本批「全局串改」bug）→ 新 get_size_for_tag(2)==6×10×4 且 get_block_size==5×10×4；
	# 数值链重算（隔离性修复批 R3/R4）：(c) 全局 redo 已把 join 重生实心 200（R4），add (0,0,0) 幂等无操作；
	# 应用 6×10×4 join 页重生实心 240（R3 单组件本页重生）；线框=本页域（R6）。
	ed.call("switch_tag", LP.TAG_JOIN)
	ed.call("_on_add_requested", [Vector3i(0, 0, 0)])
	check_eq(join.cells.size(), 200, "G20: join 加 1 格前置（数值链重算：(c) 全局 redo 已重生 join 实心 200，add 幂等无操作，隔离性修复批 R4 留痕）")
	(ed.get("size_x") as SpinBox).value = 6.0
	ed.call("_on_apply_size_one_pressed")
	# 批次 U（U12②）等价替换留痕：join 域放大=「无裁剪但有覆盖」（旧集 200≠实心 240）→ 强制确认后执行。
	ed.call("_on_size_confirmed")
	check(ed.get("project").call("get_size_for_tag", LP.TAG_JOIN) == Vector3i(6, 10, 4) \
		and ed.get("project").call("get_block_size") == Vector3i(5, 10, 4),
		"G20: join 页单组件应用=join 域 6×10×4 且 block_size 仍 5×10×4（旧共享语义即本批 bug，修复回归锁；U12② 经确认执行）")
	check_eq(join.cells.size(), 240, "G20: 非 blocks 标签应用放大=join 页重生实心 6×10×4=240（隔离性修复批 R3：单组件本页重生实心，原「join 仍 1 格不重生」断言反转）")
	check_eq(blocks.cells.size(), 200, "G20: 非 blocks 应用不影响 blocks 集（仍 200，F3）")
	check(view.call("get_bounds_size") == Vector3i(6, 10, 4), "G20: 容器线框=get_size_for_tag(2)=6×10×4（隔离性修复批 R6：线框随本页域，原「跟随 block_size 不跟随 join 域」断言反转）")
	# (e) blocks 有裁剪：先经 blocks→6×12×6 应用重生实心（零裁剪放大），再收缩回 3³
	ed.call("switch_tag", LP.TAG_BLOCKS)
	(ed.get("size_x") as SpinBox).value = 6.0
	(ed.get("size_y") as SpinBox).value = 12.0
	(ed.get("size_z") as SpinBox).value = 6.0
	ed.call("_on_apply_size_all_pressed")   # blocks 重生 6×12×6=432（y/z 均放大，零裁剪）
	# 批次 U（U12②）等价替换留痕：6×12×6 放大=「无裁剪但有覆盖」→ 强制确认后执行。
	ed.call("_on_size_confirmed")
	check_eq(blocks.cells.size(), 432, "G20: blocks 经 6×12×6 重生 432 格（前置放大；U12② 经确认执行）")
	(ed.get("size_x") as SpinBox).value = 3.0
	(ed.get("size_y") as SpinBox).value = 3.0
	(ed.get("size_z") as SpinBox).value = 3.0
	ed.call("_on_apply_size_all_pressed")
	var dlg: ConfirmationDialog = ed.get("_size_dialog")
	check(dlg.visible, "G20: blocks 有裁剪弹确认框")
	check((dlg.dialog_text as String).contains("重生实心"), "G20: 确认框注明重生实心文案（F3；隔离性修复批 REGEN_NOTE 泛化为「受影响组件」，原「初始木块将按新尺寸重生实心」等价改写为 contains(重生实心)）")
	ed.call("_on_size_confirmed")
	check_eq(blocks.cells.size(), 27, "G20: 有裁剪确认后 blocks 重生实心 3³=27（覆盖旧挖除，F3）")
	# (f) undo 同还原尺寸 6×12×6 + 432 格
	ed.call("_apply_undo")
	check(ed.get("project").call("get_block_size") == Vector3i(6, 12, 6) and blocks.cells.size() == 432,
		"G20: 有裁剪重生一次 undo 同还原尺寸 6×12×6+432 格（F3）")
	# (g) 质量护栏：重生原地清写 cells（不调 setup）+ U12③ 清栈精化。
	# 批次 U（U12③，双审 P2-7）等价替换留痕：显式推翻「重生保留既有撤销栈（挖除单元仍在）」旧断言
	# ——发起标签撤销栈重置为仅含本次 compound（越界回放根除优先；代价=更早历史不可达属预期）。
	ed.call("_on_dig_requested", [Vector3i(0, 0, 0)])
	(ed.get("size_x") as SpinBox).value = 4.0
	(ed.get("size_y") as SpinBox).value = 4.0
	(ed.get("size_z") as SpinBox).value = 4.0
	ed.call("_on_apply_size_all_pressed")
	ed.call("_on_size_confirmed")
	check_eq(blocks.undo_stack.size(), 1, "G20: 重生清栈后发起标签撤销栈=仅含本次 compound（U12③，原「保留既有撤销栈 n_before+2」断言反转）")
	check_eq(blocks.cells.size(), 64, "G20: 4³ 重生实心 64 格（覆盖前置挖除，F3）")

# ============ G21 修复批二审查回修批（P1-1/P2-2/P2-3，12 checks） ============
## P1-1：空标签（无格）透视取景须按 block_size 包围球拟合，相机落在容器外、容器线框不贴脸；
## P2-2：复合 undo/redo 回放后（尺寸/异构格集定稿）相机须重挂 look_target/dist；
## P2-3：复合回放后 SpinBox/_size_draft 随 block_size 回滚（undo 后三态一致，误点应用不吞 undo）。
func _g21_batch2_review_fixes() -> void:
	var LP := preload("res://scripts/level_project.gd")
	var IScr := preload("res://scripts/editor_interaction.gd")
	# W4-1 转写（spec §3.4-8）：3³ 种子沙盒 + fresh_editor（diag=3³ 对角线断言依赖 3³ 启动态）。
	_seed_333(1)
	_seed_meta(1)
	var ed: Control = await _fresh_editor()
	var inter: Node = ed.get("interaction")
	var mcam: Camera3D = ed.get_node("MainPanel/VC/SubViewport/Camera3D")
	var blocks: RefCounted = (ed.get("sessions") as Dictionary)[LP.TAG_BLOCKS]
	# ---- P1-1：三个空标签（target/join/final）取景须在 3³ 容器外 ----
	var diag: float = Vector3(3, 3, 3).length()
	for tag: int in [LP.TAG_TARGET, LP.TAG_JOIN, LP.TAG_FINAL]:
		ed.call("switch_tag", tag)
		var expect_fit: float = float(inter.call("_fit_persp_dist", diag))
		var dist_now: float = float(inter.get("_dist"))
		var lt_now: Vector3 = inter.get("_look_target")
		check(dist_now >= expect_fit - 0.01 and mcam.position.distance_to(lt_now) >= diag - 0.01,
			"G21: 空标签 %d 透视取景在容器外（P1-1，dist %.3f/拟合 %.3f/机距 %.3f/对角线 %.3f）"
			% [tag, dist_now, expect_fit, mcam.position.distance_to(lt_now), diag])
	ed.call("switch_tag", LP.TAG_TARGET)
	var lt_empty: Vector3 = inter.get("_look_target")
	check(mcam.position.distance_to(lt_empty) - diag * 0.5 >= mcam.near,
		"G21: 空标签相机到最近容器角深度 ≥ near（线框完整不贴脸，P1-1）")
	ed.call("switch_tag", LP.TAG_BLOCKS)
	ed.call("_on_clear_pressed")
	check(float(inter.get("_dist")) >= float(inter.call("_fit_persp_dist", diag)) - 0.01
		and mcam.position.distance_to(inter.get("_look_target") as Vector3) >= diag - 0.01,
		"G21: 一键清空 blocks 后透视取景在容器外（P1-1）")
	# ---- P2-2/P2-3：新工程 → 挖整面偏移格群中心 → 应用尺寸重生 → 复合 undo/redo ----
	# 等价改写留痕（spec §6.4 G21 行/plan §11 P1、P4）：原 :796/:824 入口 _on_apply_size_pressed
	# → 全局应用（undo/redo 相机重挂与三态断言主体等价）；原 :830 `ed.call("_do_new")`（新建回默认）
	# → 当前槽重载（_do_new 随新建流程退役，spec §3.5-4）。前置注记：上行 _on_clear_pressed 已把
	# 空 blocks 自动保存进槽 1——重载前须 _seed_333(1) 重播 3³ 骨架，「盘上 3³ + 槽位重载」才与
	# 旧「内存 new_project(3³)」等价（blocks 回 27）。
	_seed_333(1)
	check(ed.call("_load_slot_into_project", ed.get("_current_slot")),
		"G21: 当前槽重载成功（原 :830 _do_new 等价改写：盘上 3³ 重播+槽位重载=新建回默认语义）")
	var face: Array = []
	for y: int in range(3):
		for z: int in range(3):
			face.append(Vector3i(2, y, z))
	ed.call("_on_dig_requested", face)
	check_eq(blocks.cells.size(), 18, "G21: 前置挖除 x=2 整面后 blocks=18 格（格群中心偏移）")
	(ed.get("size_x") as SpinBox).value = 5.0
	(ed.get("size_y") as SpinBox).value = 5.0
	(ed.get("size_z") as SpinBox).value = 5.0
	ed.call("_on_apply_size_all_pressed")
	# 批次 U（U12②）等价替换留痕：3³→5³ 放大=「无裁剪但有覆盖」→ 强制确认后执行。
	ed.call("_on_size_confirmed")
	check_eq(ed.get("project").call("get_block_size"), Vector3i(5, 5, 5), "G21: blocks 应用 5³ 重生实心（前置；U12② 经确认执行）")
	# (a) 复合 undo：尺寸回 3³、格集回 18 格，look_target 与相机须一致（P2-2）
	ed.call("_apply_undo")
	var bs_u: Vector3i = ed.get("project").call("get_block_size")
	var expect_lt: Vector3 = IScr.cells_center(blocks.cells) - Vector3(bs_u) * 0.5
	var lt_u: Vector3 = inter.get("_look_target")
	check(bs_u == Vector3i(3, 3, 3) and lt_u.distance_to(expect_lt) < 0.001,
		"G21: 复合 undo 后 look_target=回放后格集中心（P2-2，期望 %s 实际 %s）" % [str(expect_lt), str(lt_u)])
	check(absf(mcam.position.distance_to(expect_lt) - float(inter.get("_dist"))) < 0.01,
		"G21: 复合 undo 相机重挂 look_target（机距==dist，P2-2，dist %.3f 机距 %.3f）"
		% [float(inter.get("_dist")), mcam.position.distance_to(expect_lt)])
	# (b) 复合 redo：尺寸回 5³，相机随新格集中心（P2-2）
	ed.call("_apply_redo")
	var bs_r: Vector3i = ed.get("project").call("get_block_size")
	var expect_lt_r: Vector3 = IScr.cells_center(blocks.cells) - Vector3(bs_r) * 0.5
	check(bs_r == Vector3i(5, 5, 5)
		and absf(mcam.position.distance_to(expect_lt_r) - float(inter.get("_dist"))) < 0.01,
		"G21: 复合 redo 相机重挂新格集中心（P2-2）")
	# (c) P2-3：redo 后三态=新尺寸 5³
	check_eq((ed.get("size_x") as SpinBox).value, 5.0, "G21: 复合 redo 后 size_x 同步新尺寸（P2-3）")
	check(ed.get("_size_draft") == Vector3i(5, 5, 5), "G21: 复合 redo 后 _size_draft=新尺寸（P2-3）")
	# (d) P2-3：undo 后三态=旧尺寸 3³
	ed.call("_apply_undo")
	check_eq((ed.get("size_x") as SpinBox).value, 3.0, "G21: 复合 undo 后 size_x 回旧尺寸（P2-3）")
	check(ed.get("_size_draft") == Vector3i(3, 3, 3), "G21: 复合 undo 后 _size_draft=旧尺寸（P2-3）")
	# (e) P2-3 行为契约：控件已对齐 → 误点应用=NOOP，不吞用户 undo
	# （noop 口径按 plan §11 P4 裁决=§3.2-5 全局四域全等；本态 undo 自全局应用、old_sizes 四域同为 3³，
	# 与「草稿 vs get_size_for_tag(0)」两口径判定同真，无观测差异。）
	var depth_before: int = blocks.undo_stack.size()
	ed.call("_on_apply_size_all_pressed")
	check_eq(blocks.undo_stack.size(), depth_before, "G21: undo 后误点应用不入栈（不吞 undo，P2-3）")
	check((ed.get_node("StatusBar/StatusRow/ContractLabel") as Label).text.contains("尺寸未变化"),
		"G21: undo 后误点应用提示尺寸未变化（P2-3）")

# ============ G6 编排接线直驱（T2-4，19→24 checks；视图方法经 has_method 守卫在无头也生效；W5 补连接断言） ============
func _g6_orchestration() -> void:
	# W4-1 转写（spec §3.4-8）：3³ 种子沙盒 + fresh_editor（就绪 27 格/25 计数依赖 3³ 启动态）。
	_seed_333(1)
	_seed_meta(1)
	var ed: Control = await _fresh_editor()
	var blocks := preload("res://scripts/level_project.gd").TAG_BLOCKS
	var target := preload("res://scripts/level_project.gd").TAG_TARGET
	check_eq((ed.get("sessions") as Dictionary)[blocks].cells.size(), 27, "G6: 就绪默认 3×3×3 实心会话")
	ed.call("_on_dig_requested", [Vector3i(0, 0, 0), Vector3i(1, 0, 0)])
	check_eq((ed.get("sessions") as Dictionary)[blocks].cells.size(), 25, "G6: dig_requested 落到会话")
	check_eq((ed.get_node("StatusBar/StatusRow/CountLabel") as Label).text, "25 / 27", "G6: 状态栏计数实时刷新")
	check_eq((ed.get("sessions") as Dictionary)[blocks].undo_stack.size(), 1, "G6: 撤销栈 1 单元")
	ed.call("_apply_undo")
	check_eq((ed.get("sessions") as Dictionary)[blocks].cells.size(), 27, "G6: undo 整组恢复")
	check_eq((ed.get_node("StatusBar/StatusRow/CountLabel") as Label).text, "27 / 27", "G6: undo 后计数刷新")
	ed.call("_apply_redo")
	check_eq((ed.get("sessions") as Dictionary)[blocks].cells.size(), 25, "G6: redo 再删")
	ed.call("switch_tag", target)
	check(ed.get("active_tag") == target and (ed.get_node("MainPanel/MainTitle") as Label).text.contains("target"), "G6: 标签切换标题随变")
	check((ed.get_node("LeftPanel/LeftScroll/LeftVBox/BtnCopyBase") as Button).visible, "G6: target 页显示复制初始块按钮")
	ed.call("_on_add_requested", [Vector3i(2, 2, 2)])
	check_eq((ed.get("sessions") as Dictionary)[target].cells.size(), 1, "G6: add_requested 落到 target 会话")
	ed.call("_apply_undo")
	check_eq((ed.get("sessions") as Dictionary)[target].cells.size(), 0, "G6: target 页 undo 回空")
	ed.call("_on_add_requested", [Vector3i(2, 2, 2)])
	ed.call("_sync_sessions_to_project")
	var proj: RefCounted = ed.get("project")
	check_eq(proj.call("get_voxel_set", target).size(), 1, "G6: 会话同步进模型（保存前置）")
	# 等价改写留痕（spec §6.4 G6 行）：原 :905-911「_on_title_changed/_on_chapter_changed 写模型联动」
	# （六处理器随元数据 UI 退役，spec §3.5-2）→ LevelSlots.apply_auto_meta 自动元数据断言（D5 单点）。
	SLOTS.apply_auto_meta(proj, 2)
	check_eq(int(proj.call("get_field", "chapter", -1)), 2, "G6: apply_auto_meta chapter==2（原 :909 chapter 下拉写入等价改写）")
	check_eq(str(proj.call("get_field", "title", "")), "第二关", "G6: apply_auto_meta title=第二关（原 :906 标题写入等价改写）")
	check_eq(str(proj.call("get_field", "level_id", "")), "chapter2_editor", "G6: apply_auto_meta level_id=chapter2_editor（原 :910 自动跟随等价改写）")
	check_eq(str(proj.call("get_piece").get("name", "")), "主体", "G6: apply_auto_meta name 空补主体（原 :907 部件名联动等价改写）")
	# 等价改写留痕（spec §3.5-4/§6.4 G6 行）：原 :912 `_do_new`（新建回默认实心）→ 槽位切换承接
	# （_seed_333(2) 重播 3³ 骨架 + _switch_slot(2) 加载=等价语义）。
	_seed_333(2)
	ed.call("_switch_slot", 2)
	check_eq((ed.get("sessions") as Dictionary)[blocks].cells.size(), 27, "G6: 切槽位 2 加载 3³ 骨架回默认实心（原 _do_new 等价改写）")
	# 等价改写留痕（spec §3.5-3/§6.4 G6 行）：原 :914 FileNameLabel=="未命名" → 「第N关 · 已加载」。
	check((ed.get_node("TopBar/FileNameLabel") as Label).text.contains("第二关"),
		"G6: FileNameLabel=第二关 · 已加载（原「未命名」等价改写）")
	# W5 走查回修（判定表异象暴露的测试盲区）：接线段此前无信号连接断言——补 4+1 条
	# pressed.get_connections() 断言。⚠ 必须 Signal.get_connections()：Node.get_incoming_connections()
	# 在 Godot 4.7 不列脚本运行时连接（探针 tests/probe_conn_temp.gd 实证，判定表异象记录）。
	check(_sig_has_connection((ed.get_node("LeftPanel/LeftScroll/LeftVBox/TabBlocks") as Button).pressed, "switch_tag"),
		"W5: TabBlocks pressed→switch_tag 连接存在（get_connections 口径）")
	check(_sig_has_connection((ed.get_node("LeftPanel/LeftScroll/LeftVBox/TabJoin") as Button).pressed, "switch_tag"),
		"W5: TabJoin pressed→switch_tag 连接存在（get_connections 口径）")
	check(_sig_has_connection((ed.get_node("LeftPanel/LeftScroll/LeftVBox/SizeApplyRow/BtnApplySizeOne") as Button).pressed, "_on_apply_size_one_pressed"),
		"W5: BtnApplySizeOne pressed→_on_apply_size_one_pressed 连接存在（get_connections 口径）")
	check(_sig_has_connection((ed.get_node("LeftPanel/LeftScroll/LeftVBox/SizeApplyRow/BtnApplySizeAll") as Button).pressed, "_on_apply_size_all_pressed"),
		"W5: BtnApplySizeAll pressed→_on_apply_size_all_pressed 连接存在（get_connections 口径）")
	# 五槽位钮代表断言（editor_main.gd _wire_topbar：五钮 pressed→_switch_slot.bind(n) 已核）
	var _slots_wired := true
	for i in range(1, 6):
		if not _sig_has_connection((ed.get_node("TopBar/BtnSlot%d" % i) as Button).pressed, "_switch_slot"):
			_slots_wired = false
	check(_slots_wired, "W5: 五槽位钮 pressed→_switch_slot 连接全存在（代表断言，get_connections 口径）")

# ============ G22 槽位编排（20260916 槽位化批 W4-2 新增，14→16 checks；spec §3.6/§6.4） ============
## 红态（旧实现）：_switch_slot/_sync_slot_buttons/五槽位钮/STATUS_SLOT_LOAD_FAIL 不存在——脚本错误或 FAIL。
## 断言面=切槽四态表（spec §3.6-3）：_ready 续接 last_slot、先存后载、目标失败保持当前槽+钮弹回、
## 试玩禁切（锁定清单对齐）、重复点击 noop、save_meta 失败非阻断（P2-5/plan §11 P9）+ 当前槽写盘
## 失败中止切换（审查③ P2-2）+ 重启回退上一槽。
func _g22_slot_orchestration() -> void:
	# ① _ready 续接 last_slot：种 meta last_slot=3（槽 3=3³ 骨架）→ fresh_editor
	_seed_333(3)
	_seed_meta(3)
	var ed: Control = await _fresh_editor()
	check(int(ed.get("_current_slot")) == 3, "G22: _ready 续接 meta.last_slot=3")
	check((ed.get_node("TopBar/FileNameLabel") as Label).text.contains("第三关"), "G22: FileNameLabel=第三关 · 已加载")
	# ② 切槽先存后载：当前槽（3）挖 1 格 → 切槽 2 → 槽 3 盘上 blocks=26
	ed.call("_on_dig_requested", [Vector3i(0, 0, 0)])
	ed.call("_switch_slot", 2)
	var parsed1: Variant = JSON.parse_string(SLOTS.load_slot_text(3, _sandbox_root))
	check(parsed1 is Dictionary and ((parsed1["pieces"] as Array)[0]["blocks"] as Array).size() == 26,
		"G22: 切槽先存当前槽（槽 3，26 格落盘）")
	check((ed.get_node("TopBar/BtnSlot2") as Button).button_pressed, "G22: 五钮互斥高亮迁移到目标槽")
	# ③ 目标槽坏档：保持当前槽 + 钮弹回（SLOTS.save_slot_text 覆写坏档亦走 .bak 兜底序）
	SLOTS.save_slot_text(3, "not json", _sandbox_root)
	ed.call("_switch_slot", 3)
	check(int(ed.get("_current_slot")) == 2, "G22: 目标槽加载失败保持当前槽")
	check(not (ed.get_node("TopBar/BtnSlot3") as Button).button_pressed, "G22: 失败目标钮弹回 false 高亮")
	check((ed.get_node("StatusBar/StatusRow/ContractLabel") as Label).text.contains("槽位加载失败"),
		"G22: STATUS_SLOT_LOAD_FAIL 提示")
	# ④ 重复点击 noop
	var label_before: String = (ed.get_node("TopBar/FileNameLabel") as Label).text
	ed.call("_switch_slot", 2)
	check((ed.get_node("TopBar/FileNameLabel") as Label).text == label_before, "G22: 重复点击当前槽 noop")
	# ⑤ 试玩中禁切（守卫第一行 return）+ 五钮 disabled（锁定清单对齐，spec §3.6-4）
	ed.call("_enter_playtest")
	ed.call("_switch_slot", 3)
	check(int(ed.get("_current_slot")) == 2 and ed.get("_in_playtest") == true, "G22: 试玩中切槽无操作")
	check((ed.get_node("TopBar/BtnSlot1") as Button).disabled, "G22: 试玩中五槽位钮 disabled（锁定清单对齐）")
	ed.call("_do_exit_playtest")
	check((ed.get_node("TopBar/BtnSlot2") as Button).button_pressed, "G22: 退出试玩 _sync_slot_buttons 按 _current_slot 重高亮（R8 对策）")
	# ⑤b 当前槽写盘失败中止切换（审查③ P2-2，注入法复用 G23⑦ 同款）：当前槽=2 的 level.json
	#    换同名目录 → _switch_slot(3) 在 _autosave_current 处失败 → 中止切换+目标钮弹回+提示
	var slot2_path: String = _sandbox_root.path_join("level_2/level.json")
	var f2 := FileAccess.open(slot2_path, FileAccess.READ)
	var good2: String = f2.get_as_text()
	f2.close()
	DirAccess.remove_absolute(slot2_path)
	DirAccess.make_dir_absolute(slot2_path)
	ed.call("_switch_slot", 3)
	check(int(ed.get("_current_slot")) == 2 and not (ed.get_node("TopBar/BtnSlot3") as Button).button_pressed,
		"G22: 当前槽写盘失败中止切换+目标钮未按下（审查③ P2-2）")
	check((ed.get_node("StatusBar/StatusRow/ContractLabel") as Label).text.contains("自动保存失败"),
		"G22: 当前槽写盘失败 STATUS_AUTOSAVE_FAIL 提示（审查③ P2-2）")
	#    恢复写路径（后续 ⑥ 切槽 4 需当前槽 2 写盘成功）
	DirAccess.remove_absolute(slot2_path)
	SLOTS.save_slot_text(2, good2, _sandbox_root)
	# ⑥ save_meta 失败非阻断（P2-5/§11 P9）：session_meta.json 换同名目录 → 切槽 4 成功、
	#    重启（load_meta 缺省）回退上一可解析槽位
	var meta_path: String = _sandbox_root.path_join("session_meta.json")
	DirAccess.remove_absolute(meta_path)
	DirAccess.make_dir_absolute(meta_path)
	ed.call("_switch_slot", 4)
	check(int(ed.get("_current_slot")) == 4, "G22: save_meta 失败不回滚切换（P2-5）")
	check((ed.get_node("StatusBar/StatusRow/ContractLabel") as Label).text.contains("自动保存失败"),
		"G22: save_meta 失败仅 status_hint 提示（STATUS_AUTOSAVE_FAIL，P2-5/§11 P9）")
	_seed_333(1)
	var ed2: Control = await _fresh_editor()
	check(int(ed2.get("_current_slot")) == 1, "G22: meta 坏档重启按 load_meta 缺省 last_slot=1 加载（续接点回退上一槽）")
	# 夹具卫生（后续组 _seed_meta 需要文件可写）：移除占位目录
	DirAccess.remove_absolute(meta_path)

# ============ G23 自动保存（20260916 槽位化批 W4-3 新增，10 checks；spec §3.4/§6.4） ============
## 红态（旧实现）：_autosave_current 不存在、操作尾不落盘——盘上内容断言 FAIL 或脚本错误。
## 七挂接点抽样（dig/add/undo/solid）+ 试玩不落档（首行 _in_playtest 守卫）+ 退出等价重写（P5 幂等）
## + 写失败注入（P2-4：level.json 换同名目录确定性触发 FileAccess/mkdir 失败）+ 覆写兜底防回退
## （审查②遗留②：test_level_slots S5 组不属本波文件域，断言移置本组对账，报告留痕取舍）。
func _g23_autosave() -> void:
	_seed_333(1)
	_seed_meta(1)
	var ed: Control = await _fresh_editor()
	var slot1: String = _sandbox_root.path_join("level_1/level.json")
	# ① 挖除尾落盘：27 → 26
	ed.call("_on_dig_requested", [Vector3i(0, 0, 0)])
	var p1: Variant = JSON.parse_string(SLOTS.load_slot_text(1, _sandbox_root))
	check(p1 is Dictionary and ((p1["pieces"] as Array)[0]["blocks"] as Array).size() == 26,
		"G23: 挖除整段一笔后盘上 26 格")
	# ② 添加尾落盘（切 target 加 1 格）
	ed.call("switch_tag", 1)
	ed.call("_on_add_requested", [Vector3i(0, 0, 0)])
	var p2: Variant = JSON.parse_string(SLOTS.load_slot_text(1, _sandbox_root))
	check(p2 is Dictionary and ((p2["pieces"] as Array)[0]["target_shapes"][0] as Array).size() == 1,
		"G23: 添加尾落盘 target 1 格")
	# ③ undo 尾落盘回 0 格（挂接点=栈回放后）
	ed.call("_apply_undo")
	var p3: Variant = JSON.parse_string(SLOTS.load_slot_text(1, _sandbox_root))
	check(p3 is Dictionary and ((p3["pieces"] as Array)[0]["target_shapes"][0] as Array).is_empty(),
		"G23: undo 尾盘上 target 回空")
	# ④ 一键实心尾落盘（实心/清空/复制基底挂接点抽样）
	ed.call("_on_solid_pressed")
	var p4: Variant = JSON.parse_string(SLOTS.load_slot_text(1, _sandbox_root))
	check(p4 is Dictionary and ((p4["pieces"] as Array)[0]["target_shapes"][0] as Array).size() == 27,
		"G23: 一键实心尾盘上 target 27")
	# ⑤ 试玩中不落档（_autosave_current 首行 _in_playtest 守卫封死，P2⑤/R2）
	var before_play: String = SLOTS.load_slot_text(1, _sandbox_root)
	ed.call("switch_tag", 0)
	ed.call("_enter_playtest")
	ed.call("_on_dig_requested", [Vector3i(1, 1, 1)])
	check(SLOTS.load_slot_text(1, _sandbox_root) == before_play, "G23: 试玩挖除盘上零变化（守卫）")
	# ⑥ 退出试玩等价重写（幂等，spec §3.4-3/§11 P5）
	ed.call("_do_exit_playtest")
	check(SLOTS.load_slot_text(1, _sandbox_root) == before_play, "G23: 退出试玩等价重写字节级一致（load→save 往返确定性）")
	# ⑦ 写失败注入（P2-4）：level.json 换同名目录 → 操作不中断 + 状态提示
	var f := FileAccess.open(slot1, FileAccess.READ)
	var good_text: String = f.get_as_text()
	f.close()
	DirAccess.remove_absolute(slot1)
	DirAccess.make_dir_absolute(slot1)
	ed.call("_on_dig_requested", [Vector3i(0, 0, 1)])
	check_eq((ed.get("sessions") as Dictionary)[0].cells.size(), 25, "G23: 写失败时操作照常生效（不中断）")
	check((ed.get_node("StatusBar/StatusRow/ContractLabel") as Label).text.contains("自动保存失败"),
		"G23: STATUS_AUTOSAVE_FAIL 提示（P2-4 同名目录注入确定性触发）")
	# 恢复写路径
	DirAccess.remove_absolute(slot1)
	SLOTS.save_slot_text(1, good_text, _sandbox_root)
	# 覆写兜底（审查②遗留②）：覆写已存在 level.json 走「旧文件 .bak→rename tmp→清 .bak」序
	# 仍成功且内容替换（save_slot_text 兜底路径防回退断言）。
	check(SLOTS.save_slot_text(1, good_text, _sandbox_root) \
		and SLOTS.load_slot_text(1, _sandbox_root) == good_text,
		"G23: 覆写已存在 level.json 成功且内容替换（save_slot_text 兜底路径防回退，审查②遗留②）")
	# ⑧ 恢复后再挖除 → 落盘 26−1−1=24 格
	ed.call("_on_dig_requested", [Vector3i(1, 0, 1)])
	var p8: Variant = JSON.parse_string(SLOTS.load_slot_text(1, _sandbox_root))
	check(p8 is Dictionary and ((p8["pieces"] as Array)[0]["blocks"] as Array).size() == 24,
		"G23: 恢复写路径后下次操作自动保存成功（盘上 24 格）")

# ============ G24 单组件应用分域（20260916 槽位化批 W4-4 新增，21→22 checks；spec §3.2-8 矩阵/§6.4） ============
## 红态定义=对 W3 之前旧全量实现必红（W3 已实现故落地即绿，沿 G18 先例作判红护栏固化并留痕）。
## 隔离性修复批 20260917 反转留痕（spec §4.1）：P1-1 连带裁剪废除（R1）——join 零接触/by_tag 无键
## 五处断言反转；①补 join 页重生实心 36（R3，+1）。
## 批次 V（V-E1，规格 §9.1/§9.2）等价替换留痕：「tag0/1 同料联动+两页重生+联动文案」语义随四域
## 彻底独立退役——②「两页重生→target 零操作」、④「blocks 重生→blocks 零操作+本页重生」、
## ④b「跨标签回放→单域回放」、②⑥联动文案→单域文案、by_tag 收窄单键；覆盖：tag2/tag3 单组件
## 只动本域+本页重生实心、tag0/tag1 单域应用（tag0 写不波及 tag1 域/格群/历史，反向亦然）、
## noop 分域判定、确认框明细单域单行（无对接件/标准答案行）、P0-1 对结构。
func _g24_single_domain() -> void:
	_seed_333(1)
	_seed_meta(1)
	var ed: Control = await _fresh_editor()
	var proj: RefCounted = ed.get("project")
	# ① tag2 页单组件：只动 join 域（矩阵行 3）
	ed.call("switch_tag", 2)
	ed.call("_on_add_requested", [Vector3i(0, 0, 0)])
	(ed.get("size_x") as SpinBox).value = 4.0
	(ed.get("size_y") as SpinBox).value = 3.0
	(ed.get("size_z") as SpinBox).value = 3.0
	ed.call("_on_apply_size_one_pressed")
	# 批次 U（U12②）等价替换留痕：join 域 3³→4×3×3 放大=「无裁剪但有覆盖」→ 强制确认后执行。
	ed.call("_on_size_confirmed")
	check_eq(proj.call("get_size_for_tag", 2), Vector3i(4, 3, 3), "G24: tag2 单组件只写 join 域 4×3×3（U12② 经确认执行）")
	check_eq(proj.call("get_block_size"), Vector3i(3, 3, 3), "G24: block 域逐字节不动（bug 反向保证）")
	check_eq(proj.call("get_size_for_tag", 3), Vector3i(3, 3, 3), "G24: final 域不动")
	check_eq((ed.get("sessions") as Dictionary)[0].cells.size(), 27, "G24: blocks 集零操作（regen=false）")
	check_eq((ed.get("sessions") as Dictionary)[2].cells.size(), 36,
		"G24: tag2 发起 join 页重生实心 4×3×3=36（隔离性修复批 R3：单组件本页重生实心，新增断言）")
	# ② tag0 页单组件 2³：同域联动两页重生实心 + join/final 零接触（矩阵行 1；P1-1 连带裁剪废除）；plan 含裁剪→有确认框
	ed.call("switch_tag", 2)
	ed.call("_on_add_requested", [Vector3i(2, 0, 0)])   # join 第二格观察点（①已按 R3 重生 join 实心 36，此 add 为界内幂等格）
	ed.call("switch_tag", 0)
	# join 零接触基准（隔离性修复批 R1；数值链重算留痕：spec §4.1 原写「(0,0,0),(2,0,0) 两格逐字节
	# 保留」基于旧链前提（①不重生 join）——R3 下①已使 join 重生实心 4×3×3=36，②的零接触断言改按
	# 「应用前逐域快照」逐字节比对，语义不变（应用前后 join 集逐字节一致））。
	var join_snap_24: Dictionary = (ed.get("sessions") as Dictionary)[2].cells.duplicate()
	var final_snap_24: Dictionary = (ed.get("sessions") as Dictionary)[3].cells.duplicate()
	(ed.get("size_x") as SpinBox).value = 2.0
	(ed.get("size_y") as SpinBox).value = 2.0
	(ed.get("size_z") as SpinBox).value = 2.0
	ed.call("_on_apply_size_one_pressed")
	# 批次 V（V-E1，规格 §9.2）等价替换留痕：tag0 发起确认框=「仅当前组件域」通用单域文案
	# （STATUS_SIZE_CONFIRM_ONE）——STATUS_SIZE_CONFIRM_LINK「同一块料」联动文案随四域彻底独立
	# 退役删除，plan_tags=[0] 明细恒单行（无对接件行）。原「同料联动文案」断言（隔离性修复批 R1/R2）
	# 反转为「联动文案不得再现」。
	var dlg24_one: ConfirmationDialog = ed.get("_size_dialog")
	check(dlg24_one.visible and (dlg24_one.dialog_text as String).contains("仅当前组件") \
		and not (dlg24_one.dialog_text as String).contains("同一块料") \
		and not (dlg24_one.dialog_text as String).contains("对接件"),
		"G24: tag0 发起确认框=单域文案且无对接件行（批次 V §9.2 联动文案退役，原「同料联动文案」断言等价替换）")
	ed.call("_on_size_confirmed")
	check_eq((ed.get("sessions") as Dictionary)[0].cells.size(), 8, "G24: blocks 重生实心 2³=8")
	check_eq(proj.call("get_block_size"), Vector3i(2, 2, 2), "G24: block 域=2³")
	# 批次 V（V-E1，规格 §9.2）等价替换留痕：旧断言「target 重生实心 2³=8（两页重生）」锚同料联动
	# 语义（affected={0,1}）——批次 V 单域应用只重生发起页，反转改写为「target 零操作保持空集」。
	check((ed.get("sessions") as Dictionary)[1].cells.is_empty(),
		"G24: target 零操作保持应用前空集（批次 V §9.2 单域不重生对侧页，旧「两页重生=8」断言等价替换）")
	check(_same_cell_set((ed.get("sessions") as Dictionary)[2].cells, join_snap_24) \
		and _same_cell_set((ed.get("sessions") as Dictionary)[3].cells, final_snap_24),
		"G24: join/final 零接触：cells 逐字节快照保留（含 (0,0,0)/(2,0,0)，隔离性修复批 R1：超域数据保留不删，原「连带裁剪 P1-1」断言反转）")
	check_eq(proj.call("get_size_for_tag", 2), Vector3i(4, 3, 3), "G24: join size 字段不动（P1-1：只裁体素不改 size）")
	check_eq(proj.call("get_size_for_tag", 3), Vector3i(3, 3, 3), "G24: final size 字段不动")
	# 批次 V（V-E1）：tag0 写不波及 tag1 域（target_size 未被本波触碰，读值回落 block_size 3³）。
	check_eq(proj.call("get_size_for_tag", 1), Vector3i(3, 3, 3), "G24: tag1 域尺寸不动（批次 V §9.2 单域）")
	# ③ P0-1 结构：顶层=发起标签 diff + by_tag 对结构（旧集 3³ 实心 27 → 新实心 2³=8：removed=19、added=0）
	var unit24: Dictionary = (ed.get("sessions") as Dictionary)[0].undo_stack.back()
	check((unit24["removed"] as Array).size() == 19 and (unit24["added"] as Array).is_empty(),
		"G24: 顶层单元=发起标签（blocks）重生差集 removed 19/added 0（P0-1）")
	var cp24: Dictionary = unit24["compound"]
	# 批次 V（V-E1）等价替换留痕：旧断言「by_tag 无键 2/3」锚 {0,1} 两域联动——批次 V 复合单元只含
	# 发起域，by_tag 恒单键 0（无键 1/2/3），断言收窄等价改写。
	check(not (cp24["removed_by_tag"] as Dictionary).has(1) \
		and not (cp24["removed_by_tag"] as Dictionary).has(2) \
		and not (cp24["removed_by_tag"] as Dictionary).has(3),
		"G24: by_tag 恒单键 0（无键 1/2/3，批次 V §9.2 复合单元只含发起域，原「无键 2/3」断言等价替换）")
	# ④ tag1 发起单域重生（批次 V §9.2 留痕断言，矩阵行 2）；有裁剪→确认（目标页空集→零裁剪有覆盖）
	_seed_333(1)
	_seed_meta(1)
	var ed2: Control = await _fresh_editor()
	ed2.call("switch_tag", 1)
	(ed2.get("size_x") as SpinBox).value = 2.0
	(ed2.get("size_y") as SpinBox).value = 2.0
	(ed2.get("size_z") as SpinBox).value = 2.0
	ed2.call("_on_apply_size_one_pressed")
	ed2.call("_on_size_confirmed")
	# 批次 V（V-E1，规格 §9.2）等价替换留痕：旧断言「tag1 发起同域重生 blocks=8」锚 affected={0,1}
	# 两页联动——批次 V 单域只重生发起页，反转改写为「blocks 零操作 27 + 本页（target）重生 8」。
	check_eq((ed2.get("sessions") as Dictionary)[0].cells.size(), 27,
		"G24: tag1 发起 blocks 零操作=27（批次 V §9.2 单域不重生对侧页，旧「两页联动重生 blocks=8」断言等价替换）")
	check_eq((ed2.get("sessions") as Dictionary)[1].cells.size(), 8,
		"G24: tag1 发起本页（标准答案）重生实心 2³=8（批次 V §9.2）")
	check_eq((ed2.get("project") as RefCounted).call("get_block_size"), Vector3i(3, 3, 3),
		"G24: tag1 发起 block_size 逐字节不变（批次 V §9.1 target_size 独立字段，旧联动写 2³ 必红）")
	# ④b tag1 发起单域回放还原（固化组断言；批次 V §9.2 等价替换留痕）：旧锚「by_tag[0] 重生差集对
	# 加回 blocks + old_sizes 还原 block_size」——批次 V 复合单元只含发起域（tag1），undo 经 Session
	# 常规通道（顶层=tag1 自身差集对：added 8 实心格）+ _replay_compound 单域回放——target 格群还原
	# 空集、old_sizes 还原 target_size=3³；blocks/block_size 全程零接触（数值恒 27/3³，语义从
	# 「跨标签回放还原」改「单域零接触保持」）；redo 复现收缩（target_size=2³ + 重生 8）。
	ed2.call("_apply_undo")
	check_eq((ed2.get("sessions") as Dictionary)[0].cells.size(), 27,
		"G24: tag1 发起 undo blocks 保持 27（单域回放零接触，旧「跨标签回放 by_tag[0] 加回」断言等价替换）")
	check((ed2.get("sessions") as Dictionary)[1].cells.is_empty(),
		"G24: tag1 发起 undo 本页格群还原空集（单域回放，批次 V §9.2）")
	check_eq((ed2.get("project") as RefCounted).call("get_size_for_tag", 1), Vector3i(3, 3, 3),
		"G24: tag1 发起 undo 尺寸按域还原 target_size=3³（old_sizes 单域回放，批次 V §9.2）")
	check_eq((ed2.get("project") as RefCounted).call("get_block_size"), Vector3i(3, 3, 3),
		"G24: tag1 发起 undo block_size 逐字节不变（单域回放不波及，批次 V §9.2）")
	ed2.call("_apply_redo")
	check_eq((ed2.get("sessions") as Dictionary)[1].cells.size(), 8,
		"G24: tag1 发起 redo 复现本页重生 8（new_sizes 单域回放+added 重放，批次 V §9.2）")
	check_eq((ed2.get("sessions") as Dictionary)[0].cells.size(), 27,
		"G24: tag1 发起 redo blocks 保持 27（单域零接触，旧「复现收缩 blocks=8」断言等价替换）")
	# ⑤ noop 分域判定：tag2 页草稿==当前域尺寸
	ed2.call("switch_tag", 2)
	var depth_before: int = (ed2.get("sessions") as Dictionary)[2].undo_stack.size()
	ed2.call("_on_apply_size_one_pressed")
	check_eq((ed2.get("sessions") as Dictionary)[2].undo_stack.size(), depth_before, "G24: 单组件 noop 不入栈")
	check((ed2.get_node("StatusBar/StatusRow/ContractLabel") as Label).text.contains("尺寸未变化"), "G24: noop 提示")
	# ⑥ 确认框明细按 plan 列示（批次 V（V-E1，规格 §9.2）等价替换留痕：单组件 affected 恒=
	# {active_tag}——明细恒单行「初始木块」，原「tag0/1 发起仅列初始木块/标准答案两行+同料联动文案」
	# 锚两域联动语义，随联动退役反转为「无标准答案行、无联动文案」）；tag0 页改框 1×1×1→单组件
	# （3³ 种子下 blocks=27 实心改框 1×1×1 后 plan 对 tag0 裁 26 格——plan_tags=[0] 仅一行）
	ed2.call("switch_tag", 0)
	(ed2.get("size_x") as SpinBox).value = 1.0
	(ed2.get("size_y") as SpinBox).value = 1.0
	(ed2.get("size_z") as SpinBox).value = 1.0
	ed2.call("_on_apply_size_one_pressed")
	var dlg24: ConfirmationDialog = ed2.get("_size_dialog")
	check(dlg24.visible and (dlg24.dialog_text as String).contains("仅当前组件") \
		and (dlg24.dialog_text as String).contains("初始木块") \
		and not (dlg24.dialog_text as String).contains("标准答案") \
		and not (dlg24.dialog_text as String).contains("同一块料"),
		"G24: tag0 发起确认框=单域文案且仅初始木块一行（批次 V §9.2，原「同料联动文案+两行明细」断言等价替换）")
	ed2.call("_on_size_confirmed")
	check_eq((ed2.get("sessions") as Dictionary)[0].cells.size(), 1, "G24: 确认后 blocks 重生 1×1×1=1 格")

# ============ G25 W5 走查 NG 回修（20260916 槽位化批 W5 回修新增，3 checks；判定表 NG-3） ============
## 红态（走查判定表 NG-3/w10b 截图）：五槽位钮 custom_minimum_size.x=76 < 实测需宽——
## 「第N关」22 号字 text 宽 66 + normal margins 36=102 / pressed margins 38=104（钮属性五钮逐项
## 对比无差异，根因=渲染宽度计算 76px 装不下三字，按下态钮尤甚，走查显示「第三」）。
## 探针 probe_w5_width_temp.gd 实测留痕（临时件不入库）。断言面：text 完整 + 五钮等宽 + 实测 fit 锁。
func _g25_w5_walkthrough_fixes() -> void:
	_seed_333(1)
	_seed_meta(1)
	var ed: Control = await _fresh_editor()
	var slots: Array[Button] = []
	for i in range(1, 6):
		slots.append(ed.get_node("TopBar/BtnSlot%d" % i))
	check(slots[0].text == "第一关" and slots[1].text == "第二关" and slots[2].text == "第三关" \
		and slots[3].text == "第四关" and slots[4].text == "第五关",
		"G25: 五槽位钮 text 完整（第一关~第五关逐钮，NG-3）")
	var eq_w: bool = slots[0].custom_minimum_size.x == slots[1].custom_minimum_size.x \
		and slots[1].custom_minimum_size.x == slots[2].custom_minimum_size.x \
		and slots[2].custom_minimum_size.x == slots[3].custom_minimum_size.x \
		and slots[3].custom_minimum_size.x == slots[4].custom_minimum_size.x
	check(eq_w, "G25: 五槽位钮 custom_minimum_size 等宽（NG-3）")
	# 实测 fit 锁（按下态 margins 为最坏口径）：text 宽 + pressed 左右 margins ≤ 钮宽，76px 旧值必红
	var fit := true
	for b in slots:
		var ts: Vector2 = b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size"))
		var sb: StyleBox = b.get_theme_stylebox("pressed")
		if b.custom_minimum_size.x < ts.x + sb.get_content_margin(SIDE_LEFT) + sb.get_content_margin(SIDE_RIGHT):
			fit = false
	check(fit, "G25: 五钮钮宽容纳三字（实测 text+pressed margins ≤ min width，NG-3 防回退）")

# ============ G26 隔离组（隔离性修复批 20260917 新增，17 checks；spec §3 R1~R7/§4.3；u08 回修 +2） ============
## 红态定义=对隔离性修复批前实现对红：① join/final 零接触红（P1-1 连带裁剪删格）、② join 页重生实心红
## （tag2/3 应用不重生）、④ 一键实心本页域红（旧 :748 get_block_size 错域）、⑤ 线框/分母/试玩面板红
## （错域显示族恒用 block_size）、⑥ 契约提示红（contract_hint 无超域分支）；
## ① size 字段/② 三页隔离与确认框文案/③ 复合撤销在旧实现下亦绿（防回退语义断言）。
func _g26_isolation() -> void:
	var LP := preload("res://scripts/level_project.gd")
	# ---- ① tag1 发起单组件应用：join/final 零接触（R1；含超域 (5,0,0)/(2,2,2) 保留观察点） ----
	_seed_333(1)
	_seed_meta(1)
	var ed: Control = await _fresh_editor()
	ed.call("switch_tag", LP.TAG_JOIN)
	ed.call("_on_add_requested", [Vector3i(5, 0, 0)])   # 超域格：超出 3³ block 域（R1 保留不删观察点）
	ed.call("switch_tag", LP.TAG_FINAL)
	ed.call("_on_add_requested", [Vector3i(2, 2, 2)])   # 超域格：将超出应用后 2³ 新 block 域
	ed.call("switch_tag", LP.TAG_TARGET)
	var snap0: Dictionary = (ed.get("sessions") as Dictionary)[LP.TAG_BLOCKS].cells.duplicate()
	var snap1: Dictionary = (ed.get("sessions") as Dictionary)[LP.TAG_TARGET].cells.duplicate()
	var snap2: Dictionary = (ed.get("sessions") as Dictionary)[LP.TAG_JOIN].cells.duplicate()
	var snap3: Dictionary = (ed.get("sessions") as Dictionary)[LP.TAG_FINAL].cells.duplicate()
	var sizes_before: Dictionary = {}
	for tag: int in [0, 1, 2, 3]:
		sizes_before[tag] = (ed.get("project") as RefCounted).call("get_size_for_tag", tag)
	(ed.get("size_x") as SpinBox).value = 2.0
	(ed.get("size_y") as SpinBox).value = 2.0
	(ed.get("size_z") as SpinBox).value = 2.0
	ed.call("_on_apply_size_one_pressed")
	ed.call("_on_size_confirmed")   # blocks 27 实心有裁剪 → 确认框
	check(_same_cell_set((ed.get("sessions") as Dictionary)[LP.TAG_JOIN].cells, snap2) \
		and _same_cell_set((ed.get("sessions") as Dictionary)[LP.TAG_FINAL].cells, snap3),
		"G26: ① tag1 发起单组件应用 join/final cells 逐字节快照不变（含超域格保留，R1）")
	check((ed.get("project") as RefCounted).call("get_size_for_tag", LP.TAG_JOIN) == sizes_before[2] \
		and (ed.get("project") as RefCounted).call("get_size_for_tag", LP.TAG_FINAL) == sizes_before[3],
		"G26: ① tag1 发起单组件应用 join/final size 字段逐字节不变（R1）")
	# ---- ③ tag1 发起应用后一次撤销：四页 cells+四域尺寸全还原（R7 单一复合单元） ----
	ed.call("_apply_undo")   # 发起页=tag1（active_tag=1），复合单元在 sessions[1]
	var sessions_dict: Dictionary = ed.get("sessions")
	var pages_ok: bool = true
	for pair: Array in [[LP.TAG_BLOCKS, snap0], [LP.TAG_TARGET, snap1], [LP.TAG_JOIN, snap2], [LP.TAG_FINAL, snap3]]:
		if not _same_cell_set((sessions_dict[pair[0]] as RefCounted).cells, pair[1]):
			pages_ok = false
	check(pages_ok, "G26: ③ tag1 发起应用后一次 undo 四页 cells 逐字节全还原（R7）")
	var sizes_ok: bool = true
	for tag: int in [0, 1, 2, 3]:
		if (ed.get("project") as RefCounted).call("get_size_for_tag", tag) != sizes_before[tag]:
			sizes_ok = false
	check(sizes_ok, "G26: ③ tag1 发起应用后一次 undo 四域尺寸全还原（R7）")
	# ---- ② tag2 发起单组件应用（有裁剪路径）：其余三页逐字节不变（R3） ----
	ed.call("switch_tag", LP.TAG_JOIN)
	(ed.get("size_x") as SpinBox).value = 4.0
	(ed.get("size_y") as SpinBox).value = 3.0
	(ed.get("size_z") as SpinBox).value = 3.0
	ed.call("_on_apply_size_one_pressed")   # join (5,0,0) 超出 4×3×3 → 裁 1 格 → 弹确认框
	var dlg26: ConfirmationDialog = ed.get("_size_dialog")
	check(dlg26.visible and (dlg26.dialog_text as String).contains("仅当前组件"),
		"G26: ② tag2 裁剪确认框文案=STATUS_SIZE_CONFIRM_ONE（「仅当前组件域」措辞仅再用于 tag2/3，R3）")
	ed.call("_on_size_confirmed")
	check_eq((sessions_dict[LP.TAG_JOIN] as RefCounted).cells.size(), 36,
		"G26: ② tag2 发起 join 页裁剪后重生实心 4×3×3=36（R3 本页重生实心）")
	check(_same_cell_set((sessions_dict[LP.TAG_BLOCKS] as RefCounted).cells, snap0) \
		and _same_cell_set((sessions_dict[LP.TAG_TARGET] as RefCounted).cells, snap1) \
		and _same_cell_set((sessions_dict[LP.TAG_FINAL] as RefCounted).cells, snap3),
		"G26: ② tag2 发起应用 blocks/target/final 三页 cells 逐字节不变（R3 组件隔离）")
	check((ed.get("project") as RefCounted).call("get_size_for_tag", LP.TAG_BLOCKS) == sizes_before[0] \
		and (ed.get("project") as RefCounted).call("get_size_for_tag", LP.TAG_TARGET) == sizes_before[1] \
		and (ed.get("project") as RefCounted).call("get_size_for_tag", LP.TAG_FINAL) == sizes_before[3],
		"G26: ② tag2 发起应用其余三页 size 字段逐字节不变（R3）")
	# ---- ④ 一键实心本页域（R5：solid_cells(get_size_for_tag(active_tag))） ----
	ed.call("_on_solid_pressed")
	check(_same_cell_set((sessions_dict[LP.TAG_JOIN] as RefCounted).cells, LP.solid_cells(Vector3i(4, 3, 3))),
		"G26: ④ tag2 页一键实心=join 域满域 4×3×3=36（R5，旧 get_block_size 错域填 27 必红）")
	ed.call("switch_tag", LP.TAG_BLOCKS)
	ed.call("_on_solid_pressed")
	check(_same_cell_set((sessions_dict[LP.TAG_BLOCKS] as RefCounted).cells, LP.solid_cells(Vector3i(3, 3, 3))),
		"G26: ④ tag0 页一键实心=block_size 满域 3³=27（R5）")
	# ---- ⑤ 错域显示：tag2 页线框/计数分母 + 试玩三面板各自域（R6） ----
	ed.call("switch_tag", LP.TAG_JOIN)
	var main_view: Node = ed.get_node("MainPanel/VC/SubViewport/VoxelView")
	check_eq(main_view.call("get_bounds_size"), Vector3i(4, 3, 3),
		"G26: ⑤ tag2 页容器线框=本页域 4×3×3（R6 _sync_bounds，旧恒 block_size 3³ 必红）")
	check_eq((ed.get_node("StatusBar/StatusRow/CountLabel") as Label).text, "36 / 36",
		"G26: ⑤ tag2 页计数分母=本域体积 36（R6 _refresh_status，旧分母 27 必红）")
	ed.call("switch_tag", LP.TAG_BLOCKS)
	ed.call("_enter_playtest")
	var off_main: Vector3 = ed.get_node("MainPanel/VC/SubViewport/VoxelView").call("get_center_offset")
	var off_target: Vector3 = ed.get_node("TargetPanel/VC/SubViewport/VoxelView").call("get_center_offset")
	var off_join: Vector3 = ed.get_node("JoinPanel/VC/SubViewport/VoxelView").call("get_center_offset")
	check(off_main == Vector3(1.5, 1.5, 1.5) and off_target == Vector3(1.5, 1.5, 1.5) \
		and off_join == Vector3(2.0, 1.5, 1.5),
		"G26: ⑤ 试玩三面板 build_set 各自域（main/target=block 3³ 中心、join=本域 4×3×3 中心，R6 _enter_playtest，旧 join=3³ 中心必红）")
	ed.call("_do_exit_playtest")
	# ---- ⑥ join 超域格 → 契约提示（R1：数据保留+知情，显示走 _autosave_current 既有机制） ----
	_seed_333(1)
	_seed_meta(1)
	var ed6: Control = await _fresh_editor()
	ed6.call("switch_tag", LP.TAG_TARGET)
	ed6.call("_on_add_requested", [Vector3i(0, 0, 0)])
	ed6.call("switch_tag", LP.TAG_JOIN)
	ed6.call("_on_add_requested", [Vector3i(0, 0, 0)])
	ed6.call("_on_add_requested", [Vector3i(5, 0, 0)])   # 超出 3³ block 域
	ed6.call("switch_tag", LP.TAG_FINAL)
	ed6.call("_on_add_requested", [Vector3i(1, 1, 1)])
	ed6.call("switch_tag", LP.TAG_BLOCKS)
	(ed6.get("size_x") as SpinBox).value = 4.0
	(ed6.get("size_y") as SpinBox).value = 3.0
	(ed6.get("size_z") as SpinBox).value = 3.0
	ed6.call("_on_apply_size_one_pressed")   # 零裁剪但有覆盖 → U12② 强制确认（原「零裁剪 → 直接执行」注释随行为反转废止）
	# 批次 U（U12②）等价替换留痕：blocks 27 实心/放大 4×3×3=36 → 确认后执行（confirmed 直执不过第二道闸）。
	ed6.call("_on_size_confirmed")
	# u08 回修（20260917）：应用产生超域（join (5,0,0) 超出新 block 域 4×3×3）→ toast 知情通道
	# 补知（状态栏契约门被应用反馈占用=「应用反馈不再吞没知情提示」；红态=旧实现 toast 停留在
	# 应用反馈文案 STATUS_SIZE_REGEN_ONE，不含「超出」）。
	var toast26: Label = ed6.get_node("PlaytestToast")
	check(toast26.visible and (toast26.text as String).contains("超出"),
		"G26: ⑥ tag0 发起应用产生超域后 show_toast 知情提示弹出（u08 回修，toast 可见且文案含「超出」）")
	# 批次 V（V-E1，规格 §9.1）等价替换留痕：HINT_OVER_DOMAIN 文案随 per-domain 计数语义同步——
	# 旧「…超出初始木块域」→ 新「…超出所属组件域尺寸」（本场景计数不变 N=1：join (5,0,0) 超
	# join_part.size 域 3³ 一格；blocks 已重生 4×3×3 界内）。
	check((toast26.text as String).contains("1 格超出所属组件域尺寸"),
		"G26: ⑥ toast 文案=HINT_OVER_DOMAIN 带超域格数 N=1（计数与 contract_hint 同源，u08 回修；批次 V §9.1 per-domain 文案等价替换）")
	var p26: Variant = JSON.parse_string(SLOTS.load_slot_text(1, _sandbox_root))
	check(p26 is Dictionary and ((p26["pieces"] as Array)[0]["join_part"]["voxels"] as Array).has("5,0,0") \
		and ((p26["pieces"] as Array)[0]["join_part"]["voxels"] as Array).size() == 2,
		"G26: ⑥ join 超域格应用后照实落盘保留（R1 数据保留，旧 P1-1 连带裁剪必红）")
	var ed6b: Control = await _fresh_editor()   # 重载（状态栏空闲）→ 首次自动保存按既有机制带出契约提示
	ed6b.call("_autosave_current")
	check((ed6b.get_node("StatusBar/StatusRow/ContractLabel") as Label).text.contains("超出所属组件域尺寸"),
		"G26: ⑥ ContractLabel 显示「N 格超出所属组件域尺寸」契约提示（R1，旧实现无超域分支必红；批次 V §9.1 per-domain 文案等价替换）")

# ============ G4 两级拾取·四分支数学（T2-3，10 checks；纯静态可无头） ============
## 坐标系注意：center=(1.5,1.5,1.5)，cell (1,1,1) 占世界 [−0.5,0.5]³（体素定位=cell+0.5−center），
## 故射线锚点用世界坐标 (5,0,0) 打 (1,1,1) 的 +X 面；(0.6,10,0.6) 避开 1 号格 x 板带打包围盒顶面。
func _g4_pick_math() -> void:
	var I := load("res://scripts/editor_interaction.gd")
	var no := Vector3i(-1, -1, -1)
	var size := Vector3i(3, 3, 3)
	var center := Vector3(1.5, 1.5, 1.5)
	var occ1: Dictionary = {Vector3i(1, 1, 1): true}
	check_eq(I.ray_to_cell(Vector3(5, 0, 0), Vector3(-1, 0, 0), occ1, size, center), Vector3i(1, 1, 1), "G4: slab 拾取命中体素")
	check_eq(I.ray_to_cell(Vector3(5, 0, 0), Vector3(-1, 0, 0), {}, size, center), no, "G4: 空集拾取 NO_CELL")
	var hit: Dictionary = I.ray_to_hit(Vector3(5, 0, 0), Vector3(-1, 0, 0), occ1, size, center)
	check(int(hit["axis"]) == 0 and int(hit["sign"]) == -1, "G4: 命中详情 进入轴 X/方向 -1")
	check_eq(I.pick_place_cell(Vector3(5, 0, 0), Vector3(-1, 0, 0), occ1, size, center), Vector3i(2, 1, 1), "G4: 分支1 面外法向相邻格")
	check_eq(I.pick_place_cell(Vector3(5, 0, 0), Vector3(-1, 0, 0), {Vector3i(2, 1, 1): true}, size, center), no, "G4: 分支1 相邻格越界拒绝")
	check_eq(I.pick_place_cell(Vector3(-5, 0, 0), Vector3(1, 0, 0), {Vector3i(1, 1, 1): true, Vector3i(0, 1, 1): true}, size, center), no, "G4: 分支1 相邻格越界拒绝（最近命中先中 0,1,1，折算 -1,1,1 越界）")
	check_eq(I.pick_place_cell(Vector3(0.6, 10, 0.6), Vector3(0, -1, 0), occ1, size, center), Vector3i(2, 2, 2), "G4: 分支2 包围盒入射首格")
	check_eq(I.pick_place_cell(Vector3(5, 0, 0), Vector3(-1, 0, 0), {}, size, center), Vector3i(2, 1, 1), "G4: 分支2 空集起步=入射首格（§7.2 口径自洽）")
	check_eq(I.pick_place_cell(Vector3(0.6, 10, 2.0), Vector3(0, -1, 0), {}, size, center), no, "G4: 分支3 外壳环折算越界拒绝")
	check_eq(I.pick_place_cell(Vector3(10, 10, 10), Vector3(0, -1, 0), {}, size, center), no, "G4: 分支4 全未命中拒绝")

# ============ G5 交互状态机直驱（T2-3，10 checks；gui 粘合层走 T2-6 窗口走查） ============
func _g5_interaction_state() -> void:
	var I := load("res://scripts/editor_interaction.gd")
	var VV := load("res://scripts/editor_view.gd")
	var view: Node = VV.new()
	add_child(view)
	var mat: Material = VV.make_wood_material(VV.WOOD_LIGHT)
	var full: Dictionary = {}
	for x: int in range(3):
		for y: int in range(3):
			for z: int in range(3):
				full[Vector3i(x, y, z)] = true
	view.call("build_set", full, Vector3i(3, 3, 3), mat)
	var inter: Node = I.new()
	add_child(inter)
	inter.set_view(view)
	var dug: Array = []
	var added: Array = []
	# GDScript lambda 按值捕获局部变量，函数体内赋值（=）不外溢 → 改为就地变异捕获的
	# Array 引用（append_array）；本组每链恰一次 emit，捕获语义与计划原意（=）等价。
	inter.dig_requested.connect(func(cells: Array) -> void: dug.append_array(cells))
	inter.add_requested.connect(func(cells: Array) -> void: added.append_array(cells))
	var n00: MeshInstance3D = view.call("get_voxel_node", Vector3i(0, 0, 0))
	inter.call("stroke_begin", Vector3i(0, 0, 0))
	check((inter.call("get_selected") as Array).size() == 1 and n00.material_override != mat, "G5: 划选起点选中+高亮")
	inter.call("stroke_move", Vector3i(1, 0, 0))
	check_eq((inter.call("get_selected") as Array).size(), 2, "G5: 划选追加第 2 格")
	inter.call("stroke_end_single")
	check_eq((inter.call("get_selected") as Array).size(), 1, "G5: stroke_end_single 单选收尾=仅起点格保留（接缝语义）")
	inter.call("ctrl_click", Vector3i(0, 0, 0))
	check((inter.call("get_selected") as Array).is_empty(), "G5: Ctrl+点击 toggle 反选")
	inter.call("ctrl_click", Vector3i(0, 0, 0))
	check_eq((inter.call("get_selected") as Array).size(), 1, "G5: Ctrl+点击 toggle 选中")
	inter.call("right_delete")
	check(dug.size() == 1 and dug[0] == Vector3i(0, 0, 0), "G5: 右键原地→dig_requested(选中组)")
	check((inter.call("get_selected") as Array).is_empty() and n00.material_override == mat, "G5: 删除后清选区+高亮恢复")
	inter.call("set_mode", true)
	check((inter.call("get_selected") as Array).is_empty(), "G5: 切添加模式清选区")
	inter.call("add_begin", Vector3i(2, 1, 1))
	inter.call("add_move", Vector3i(1, 1, 1))
	inter.call("add_end")
	check(added.size() == 2 and added[0] == Vector3i(2, 1, 1) and added[1] == Vector3i(1, 1, 1), "G5: 拖动连放合并一次 add_requested（T5）")
	inter.call("set_mode", false)
	check((inter.call("get_selected") as Array).is_empty(), "G5: 切回挖除模式清选区")
	view.free()
	inter.free()

# ============ G3 视图属性断言（T2-2，20 checks；无头渲染读回恒 0 → 只做属性分量断言，坑 1） ============
func _g3_voxel_view() -> void:
	var VV := load("res://scripts/editor_view.gd")
	check(VV != null, "G3: editor_view.gd 可加载")
	var view: Node = VV.new()
	add_child(view)
	var mat: Material = VV.make_wood_material(VV.WOOD_LIGHT)
	check(mat is StandardMaterial3D, "G3: 木纹材质类型")
	check(mat.albedo_texture != null, "G3: 木纹含噪声纹理（R4）")
	check(absf(mat.roughness - 0.55) < 0.001, "G3: roughness 0.55（R4；属性 32 位 float 读回，容差断言）")
	check_eq(mat.uv1_scale, Vector3(1.0, 0.15, 1.0), "G3: uv1_scale 横纹（R4）")
	var cells3: Dictionary = {Vector3i(0, 0, 0): true, Vector3i(1, 1, 1): true, Vector3i(2, 2, 2): true}
	view.call("build_set", cells3, Vector3i(3, 3, 3), mat)
	check_eq(int(view.call("get_voxel_count")), 3, "G3: build_set 3 格")
	check_eq(view.call("get_center_offset"), Vector3(1.5, 1.5, 1.5), "G3: 中心恒=block_size 中心")
	check_eq((view.call("get_built_cells") as Array).size(), 3, "G3: built_cells 3 格")
	var n0: MeshInstance3D = view.call("get_voxel_node", Vector3i(0, 0, 0))
	check(n0 != null and n0.visible, "G3: 体素节点可见")
	view.call("hide_voxel", Vector3i(0, 0, 0))
	check(not n0.visible, "G3: 挖除=隐藏（R3 :89-98 语义）")
	view.call("show_voxel", Vector3i(0, 0, 0))
	check(n0.visible, "G3: 撤销恢复=显示")
	view.call("set_voxel_highlight", Vector3i(0, 0, 0), true)
	check(n0.material_override != mat, "G3: 高亮切换材质")
	view.call("set_voxel_highlight", Vector3i(0, 0, 0), false)
	check(n0.material_override == mat, "G3: 取消高亮恢复默认材质")
	view.call("add_voxel", Vector3i(1, 0, 0))
	check_eq(int(view.call("get_voxel_count")), 4, "G3: add_voxel 新建节点（添加模式）")
	view.call("build_set", {}, Vector3i(3, 3, 3), mat)
	check_eq(int(view.call("get_voxel_count")), 0, "G3: 空集构建 0 格")
	check_eq(view.call("get_center_offset"), Vector3(1.5, 1.5, 1.5), "G3: 空集中心仍=尺寸中心（拾取基准稳定）")
	view.call("show_place_preview", Vector3i(0, 0, 0))
	check(bool(view.call("has_place_preview")), "G3: 放置预览显示（§7.2 幻影）")
	view.call("clear_place_preview")
	check(not bool(view.call("has_place_preview")), "G3: 预览可清除")
	view.call("show_bounds", Vector3i(3, 3, 3))
	check(bool(view.call("has_bounds")), "G3: 包围盒线框显示（§7.2 空集起步）")
	view.call("clear_bounds")
	check(not bool(view.call("has_bounds")), "G3: 包围盒可清除")
	view.free()

# ============ G2 场景骨架（T1-7；20260916 槽位化批 W4-4 等价改写：五槽位钮替三钮+元数据区退役+P8 async 化） ============
func _g2_scene_skeleton() -> void:
	var scene: PackedScene = load("res://scenes/editor_main.tscn")
	check(scene != null, "G2: editor_main.tscn 可加载")
	# P8 async 化（plan §8 W4-4/§11 P8）：原 instantiate+add_child 静态断言 → _fresh_editor 夹具
	# （_ready 消费沙盒槽位 1=夹具预填 8×3×8，_init_sandbox 已就绪）；依赖 _ready 态的尺寸断言
	# 由静态默认 3.0 改动态（见下）。
	var root: Control = await _fresh_editor()
	# 等价改写留痕（spec §6.4 G2 行）：原清单 TopBar/BtnNew/BtnOpen/BtnSave → 五槽位钮；
	# ChapterRow/ChapterOption 与 TitleRow/TitleEdit 移出清单（元数据 UI 退役，消失断言见下）。
	for path: String in [
		"TopBar/BtnSlot1", "TopBar/BtnSlot2", "TopBar/BtnSlot3", "TopBar/BtnSlot4", "TopBar/BtnSlot5",
		"TopBar/BtnPlaytest", "TopBar/BtnJoin",
		"LeftPanel/LeftScroll/LeftVBox/TabBlocks", "LeftPanel/LeftScroll/LeftVBox/TabTarget",
		"LeftPanel/LeftScroll/LeftVBox/TabJoin", "LeftPanel/LeftScroll/LeftVBox/TabFinal",
		"LeftPanel/LeftScroll/LeftVBox/SizeRow/SizeX", "LeftPanel/LeftScroll/LeftVBox/OpsRow/BtnSolid",
		"LeftPanel/LeftScroll/LeftVBox/OpsRow/BtnClear", "LeftPanel/LeftScroll/LeftVBox/BtnCopyBase",
		"LeftPanel/LeftScroll/LeftVBox/ModeRow/BtnDigMode", "LeftPanel/LeftScroll/LeftVBox/ModeRow/BtnAddMode",
	]:
		check(root.get_node_or_null(path) != null, "G2: 节点存在 %s" % path)
	# 等价改写（spec §3.5-2/§3.6-2 退役清单）：三钮+元数据七节点消失断言（合并 1 条，
	# 原清单内 BtnNew/BtnOpen/BtnSave/ChapterOption/TitleEdit 反向化）。
	check(root.get_node_or_null("TopBar/BtnNew") == null \
		and root.get_node_or_null("TopBar/BtnOpen") == null \
		and root.get_node_or_null("TopBar/BtnSave") == null \
		and root.get_node_or_null("LeftPanel/LeftScroll/LeftVBox/MetaLabel") == null \
		and root.get_node_or_null("LeftPanel/LeftScroll/LeftVBox/ChapterRow") == null \
		and root.get_node_or_null("LeftPanel/LeftScroll/LeftVBox/TitleRow") == null \
		and root.get_node_or_null("LeftPanel/LeftScroll/LeftVBox/EraRow") == null \
		and root.get_node_or_null("LeftPanel/LeftScroll/LeftVBox/DescRow") == null \
		and root.get_node_or_null("LeftPanel/LeftScroll/LeftVBox/NameRow") == null \
		and root.get_node_or_null("LeftPanel/LeftScroll/LeftVBox/LevelIdRow") == null,
		"G2: 顶栏三钮与元数据七节点消失（新建/打开/另存+FileDialog 退役）")
	# T4 删除留痕：批量操作区节点/函数/layer_cells 全量等价删除（规格 §5.2④ 消失断言）。
	check(root.get_node_or_null("LeftPanel/LeftScroll/LeftVBox/BulkLabel") == null \
		and root.get_node_or_null("LeftPanel/LeftScroll/LeftVBox/BulkAxisRow") == null \
		and root.get_node_or_null("LeftPanel/LeftScroll/LeftVBox/BulkBtnRow") == null, "G2: 批量区节点已删除（T4）")
	var bulk_fns_gone := true
	for fn: String in ["_layer_set", "_on_layer_dig_pressed", "_on_layer_fill_pressed", "_on_axis_changed", "_sync_layer_spin_max"]:
		if root.has_method(fn):
			bulk_fns_gone = false
	check(bulk_fns_gone, "G2: 编排层批量函数组 has_method 全 false（T4）")
	check(not (preload("res://scripts/voxel_edit_ops.gd") as GDScript).has_method("layer_cells"), "G2: 会话层 layer_cells 已删除（T4）")
	check(root.get_node_or_null("MainPanel/VC/SubViewport/VoxelView") != null, "G2: 主视口 VoxelView 存在")
	check(root.get_node_or_null("TargetPanel/VC/SubViewport/VoxelView") != null, "G2: 目标视口 VoxelView 存在")
	check(root.get_node_or_null("JoinPanel/VC/SubViewport/VoxelView") != null, "G2: 对接视口 VoxelView 存在")
	var vp: SubViewport = root.get_node("MainPanel/VC/SubViewport")
	check(vp.own_world_3d, "G2: 主视口独立 3D 世界（R8）")
	var cam: Camera3D = root.get_node("MainPanel/VC/SubViewport/Camera3D")
	# 修复批二 F1：主视口改透视（Blender/3D Max 式标准工具视角）。tscn 兜底值须=透视，
	# _ready 构建路径亦会写回；此处锁 tscn 兜底（未进构建路径时的初始态，与 G2 其余 tscn 断言同口径）。
	check_eq(cam.projection, Camera3D.PROJECTION_PERSPECTIVE, "G2: 主相机透视（修复批二 F1）")
	check(not (root.get_node("TargetPanel") as Control).visible, "G2: 目标面板初始隐藏（T11）")
	check(not (root.get_node("JoinPanel") as Control).visible, "G2: 对接面板初始隐藏（T11）")
	check(not (root.get_node("TopBar/BtnJoin") as Button).visible, "G2: 对接按钮初始隐藏")
	check((root.get_node("LeftPanel/LeftScroll/LeftVBox/TabBlocks") as Button).button_pressed, "G2: blocks 标签默认选中")
	# 等价改写留痕（spec §6.4 G2 行，P8）：原 :1019「SizeX 默认 3.0」静态断言 → 动态值
	# 「SpinBox 值==当前槽 block_size.x」（夹具预填 8×3×8 → 8.0）。
	check_eq((root.get_node("LeftPanel/LeftScroll/LeftVBox/SizeRow/SizeX") as SpinBox).value, 8.0,
		"G2: SpinBox 值==当前槽 block_size.x（夹具预填 8×3×8；原静态默认 3.0 等价改写，P8 async 化）")
	# 等价改写留痕（spec §6.4 G2 行）：原 :1020-1023 chapter 下拉三断言（item_count/首末项文本）退役
	# → ChapterRow 消失并入上方消失断言 + _ready 后自动元数据值断言（D5 apply_auto_meta）。
	var proj_g2: RefCounted = root.get("project")
	check(int(proj_g2.call("get_field", "chapter", -1)) == 1 \
		and str(proj_g2.call("get_field", "title", "")) == "第一关" \
		and str(proj_g2.call("get_field", "level_id", "")) == "chapter1_editor",
		"G2: _ready 后自动元数据 chapter==1/title=第一关/level_id=chapter1_editor（原 chapter 下拉三断言等价改写）")
	check((root.get_node("LeftPanel/LeftScroll/LeftVBox/TabBlocks") as Button).toggle_mode, "G2: 标签按钮 toggle 态")
	var main_script: Script = root.get_script()
	check(main_script != null and main_script.resource_path.ends_with("editor_main.gd"), "G2: 根节点挂编排脚本")

# ============ G1 JoinXform 照抄冒烟（T1-3，5 checks） ============
func _g1_join_xform_smoke() -> void:
	const JX := preload("res://scripts/join_transform.gd")
	check_eq(JX.TRANSFORM_COUNT, 48, "G1: 48 变换计数")
	check_eq(JX.det_of(0), 1, "G1: 0 号变换=恒等旋转 det+1")
	check_eq(JX.det_of(1), -1, "G1: 1 号变换=镜像 det-1")
	var l_shape: Dictionary = {Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true, Vector3i(0, 1, 0): true}
	var l_moved: Dictionary = {Vector3i(5, 2, 3): true, Vector3i(6, 2, 3): true, Vector3i(5, 3, 3): true}
	check(JX.are_equivalent(l_shape, l_moved), "G1: 平移归一后 L 形等价")
	var l_extra: Dictionary = {Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true, Vector3i(0, 1, 0): true, Vector3i(2, 0, 0): true}
	check(not JX.are_equivalent(l_shape, l_extra), "G1: 多一格不等价")

# ============ G0 工程环境（T1-2，14 checks） ============
func _g0_environment() -> void:
	var pg := FileAccess.get_file_as_string("res://project.godot")
	check(pg.contains("res://addons/auto_reload/plugin.cfg"), "G0: project.godot 启用 auto_reload 插件")
	check(pg.contains("res://addons/godot_mcp_editor/plugin.cfg"), "G0: project.godot 启用 godot_mcp_editor 插件")
	check(pg.contains("res://addons/godot_mcp_runtime/plugin.cfg"), "G0: project.godot 启用 godot_mcp_runtime 插件")
	check(pg.contains("MCPRuntime="), "G0: project.godot 含 MCPRuntime autoload")
	check(pg.contains("gl_compatibility"), "G0: project.godot 渲染 gl_compatibility")
	var th: Theme = load("res://themes/theme_dark.tres")
	check(th != null, "G0: theme_dark.tres 可加载")
	var fv := th.default_font as FontVariation
	check(fv != null, "G0: 主题 default_font 为 FontVariation")
	check(fv.variation_opentype.has(2003265652) and absf(float(fv.variation_opentype[2003265652]) - 400.0) < 0.001, "G0: FontVariation wght=400（4.7 int-tag 实证规律）")
	check(FileAccess.file_exists("res://fonts/MaShanZheng-Regular.ttf"), "G0: MaShanZheng 字体存在")
	check(FileAccess.file_exists("res://fonts/NotoSansSC[wght].ttf"), "G0: NotoSansSC 变量字体存在")
	var fx := FileAccess.get_file_as_string(FIXTURE)
	check(fx.length() > 1000, "G0: 第 1 关夹具非空")
	check(fx.begins_with("{\r\n"), "G0: 夹具 CRLF 开头（无 BOM）")
	check(fx.ends_with("}\r\n"), "G0: 夹具 CRLF 尾换行")
	var two: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_TWO))
	check(two is Dictionary and (two["pieces"] as Array).size() == 2, "G0: 双 piece 夹具含 2 个 piece")
