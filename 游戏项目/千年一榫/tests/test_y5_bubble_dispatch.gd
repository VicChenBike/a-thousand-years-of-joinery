extends "res://tests/test_base.gd"
## 批次 Y（Y-C7/Y-C9，spec §9.2 拍板 8）：见证者点击气泡恢复——事件分流双路径红测
## + 批次 W 拾取带修复回归锁 + 四隐患清偿断言。
## 设计：立绘 mouse_filter 维持 IGNORE（不回滚 STOP），MainView/ViewportContainer gui_input
## 入口按「落点∈立绘可见 rect（浮动/呼吸实时 + portrait_metrics used_rect 精化）」分流：
## 命中→气泡 toggle 并消费事件；未命中→原 3D 拾取链不动（批次 W P1-7a 不回退）。
## 双路径：①键鼠物理事件（root.push_input）；②手势合成光标（gesture_cursor_layer synth_*
## 经 push_input 同管线——批次 W4 关卡 UI 手势单击同源推送通道，自然命中 MainView 分流）。
## 台词源：tests/fixtures 夹具注入（剧情对话/ 归 Y4 域，本套件不触）。

const LEVEL_SCENE := "res://scenes/level/level_scene.tscn"
const LS := "res://scenes/level/level_scene.gd"
const FIXTURE := "res://tests/fixtures/bubble_y5_fixture.json"
const MISS := Vector3i(-1, -1, -1)
# 清档纪律（tools/README_走查清档规范.md）：关卡实例 _exit_tree 会落挖除断点（N9），
# 多轮运行残留 deleted_cells 会污染探针（已实证：残留 4 格致探针格已删、划选断言失真）。
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_r_y5bub_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]

var _pre_save_text: String = ""

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _backup_user() -> void:
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	for c: Node in root.get_children():
		if not DISC_AUTOLOADS.has(String(c.name)):
			c.free()
	for p: String in DISC_WATCHED:
		var a: String = _disc_abs(p)
		if FileAccess.file_exists(a):
			DirAccess.remove_absolute(a)
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(_disc_abs(bk))
	var sm: Node = root.get_node_or_null("SaveManager")
	if sm != null:
		sm.call("load_game")
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|y5bub|files=%d" % DISC_WATCHED.size())

var inst: Node
var lib: Node

func _make_level(ch: int) -> void:
	inst = (load(LEVEL_SCENE) as PackedScene).instantiate()
	inst.call("set_context", {"chapter": ch})
	add_child(inst)
	await process_frame
	await process_frame
	inst.call("load_witness_lines_from_path", FIXTURE)
	inst.call("_refresh_witness_metrics")
	await process_frame

func _press(pos: Vector2, pressed: bool, ctrl: bool = false) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.position = pos
	mb.ctrl_pressed = ctrl
	root.push_input(mb, true)

func _right(pos: Vector2, pressed: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_RIGHT
	mb.pressed = pressed
	mb.position = pos
	root.push_input(mb, true)

func _motion(pos: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = pos
	mm.relative = Vector2(1.0, 0.0)
	root.push_input(mm, true)

func _selected_count() -> int:
	var sel: Dictionary = inst.get("_selected")
	return sel.size()

func _probe_cells() -> Array:
	## 主视中线步进探 2 互异命中格（test_t_level_mode 同款；返回 [[cell, 全局位], …]）
	var cont: SubViewportContainer = inst.get_node("MainView/ViewportContainer")
	var vps: SubViewport = inst.get_node("MainView/ViewportContainer/SubViewport")
	var cam: Camera3D = inst.get_node("MainView/ViewportContainer/SubViewport/Camera3D")
	var found: Array = []
	var seen: Array = []
	var x := vps.size.x * 0.5
	while found.size() < 2 and x < vps.size.x:
		var c: Vector3i = inst.call("get_cell_hit", cam.project_ray_origin(Vector2(x, vps.size.y * 0.5)),
			cam.project_ray_normal(Vector2(x, vps.size.y * 0.5)))
		if c != MISS and not seen.has(c):
			seen.append(c)
			found.append([c, cont.get_global_rect().position + Vector2(x, vps.size.y * 0.5)])
		x += 8.0
	return found

func _req(method: String) -> bool:
	## 红测护栏：实现未落地时以 [FAIL] 记账并跳过后续段（防脚本中止掩盖其余断言）
	if not inst.has_method(method):
		check(false, "红测（实现未落地）：level_scene 缺方法 %s" % method)
		return false
	return true

func _initialize() -> void:
	print("== test_y5_bubble_dispatch ==")
	_backup_user()
	# 清档前奏：删档保证第 1 关 192 格满态起测（探针/划选断言确定性前提）
	for p: String in [DISC_SAVE_PATH, DISC_TMP_PATH, DISC_BAK_PATH]:
		if FileAccess.file_exists(_disc_abs(p)):
			DirAccess.remove_absolute(_disc_abs(p))
	root.get_node("SaveManager").call("load_game")
	lib = root.get_node("LevelLibrary")
	lib.call("scan_directory")
	await _make_level(1)

	var bub: Label = inst.get_node("WitnessBubble")
	check(bub is Label and bub.visible == false, "前置：气泡节点在位且初始隐藏")
	check_eq((inst.call("get_witness_lines_pool") as Array).size(), 4, "前置：夹具台词池已注入（4 条）")

	# ==================== ① 键鼠路径：点击立绘弹气泡 ====================
	var rect: Rect2 = Rect2()
	if _req("get_witness_visible_rect"):
		rect = inst.call("get_witness_visible_rect")
		check(rect.size.x > 4.0 and rect.size.y > 4.0,
			"立绘可见 rect 有效（used_rect 精化，%s）" % str(rect))
		var inside: Vector2 = rect.get_center()
		_press(inside, true)
		check(bub.visible == true, "键鼠①：左键按下立绘 → 气泡弹出（事件分流命中消费）")
		check(String(bub.text) != "", "键鼠①：气泡文本来自台词池（洗牌袋，「%s」）" % String(bub.text))
		_press(inside, false)
		_press(inside, true)
		check(bub.visible == false, "键鼠①：显示期间再点立绘 → 气泡关闭（toggle）")
		_press(inside, false)
		_press(inside, true)
		check(bub.visible == true, "键鼠①：再次点击 → 再弹（旧设计 ded6fa8 口径）")
		# 4 秒自动隐藏（WITNESS_BUBBLE_SECONDS=4.0）
		inst.call("_tick_witness", 4.1)
		check(bub.visible == false, "键鼠①：4s 后自动隐藏（_tick_witness 超时链）")
		# 消费验证：点立绘不触发 3D 选区/清空（事件被分流吃掉）
		_press(inside, true)
		_press(inside, false)
		check_eq(_selected_count(), 0, "键鼠①：点立绘不产生 3D 选区（事件已消费）")

	# ==================== ② 手势路径：合成光标点击立绘弹气泡 ====================
	var layer: Node = load("res://scripts/gesture_cursor_layer.gd").new()
	add_child(layer)
	await process_frame
	if rect.size.x > 4.0:
		inst.call("_hide_witness_bubble")  # 状态复位（①末弹出态→隐藏，保证② toggle 断言基准）
		var gpos: Vector2 = rect.get_center()
		layer.call("push", layer.call("synth_motion", gpos))
		layer.call("push", layer.call("synth_button", gpos, true, false))
		check(bub.visible == true, "手势②：合成光标左键按下立绘 → 气泡弹出（synth 经 push_input 命中分流）")
		layer.call("push", layer.call("synth_button", gpos, false, false))
		check(String(bub.text) != "", "手势②：文本来自台词池（「%s」）" % String(bub.text))
		layer.call("push", layer.call("synth_button", gpos, true, false))
		check(bub.visible == false, "手势②：再点 → 关闭（toggle 双路径对称）")
		layer.call("push", layer.call("synth_button", gpos, false, false))
		layer.free()

	# ==================== ③ 回归锁：未命中立绘的拾取/挖除/划选/轨道旋转 ====================
	var probes := _probe_cells()
	if probes.size() == 2:
		var cell_a: Vector3i = probes[0][0]
		var pos_a: Vector2 = probes[0][1]
		var cell_b: Vector3i = probes[1][0]
		var pos_b: Vector2 = probes[1][1]
		var blank: Vector2 = (inst.get_node("MainView/ViewportContainer") as SubViewportContainer)\
			.get_global_rect().position + Vector2(6.0, 6.0)
		var remaining0: int = (inst.get("_remaining") as Dictionary).size()

		# ③-a 单选替换（未命中路径原语义）
		_press(pos_a, true)
		_press(pos_a, false)
		check_eq(_selected_count(), 1, "回归③-a：点体素=单选（未命中分流，原链不动）")
		check(bub.visible == false, "回归③-a：点体素不弹气泡")
		_press(blank, true)
		_press(blank, false)
		check_eq(_selected_count(), 0, "回归③-a：空白单击清空选区（原语义保持）")

		# 批次 Z Z2 等价改写（执行序 a→c→d→b→e；五段断言集与计数零增减）：新数据 12×3×5 中线
		# 实况下探针首两互异格恰为 (7,2,4)@(7,2,3)（后者在前者射线正后方、屏距仅 8px）——原序
		# ③-b 先删 A 后，③-c/③-d 的 pos_a 抬起命中变为后列格 B（stroke_start=B、motion 无新格
		# → 抬起单选替换 → 恒 1 格必红）。等价重排=划选两段（c/d）先行于完整木料（仪器化实证：
		# 完整块下 8px 位移划选恰 2 格），删除语义段（b）后置——b 的左键按下+原地抬起=单选替换
		# 保证选区恰 {A}，右键删除断言语义不变（旧数据 8×3×8 探针间距侥幸避开该耦合）。
		# ③-c 划选：左键按下拖到另一格抬起 → 2 格选中（中间步进点可能落邻格，不插探针外 motion）
		_press(blank, true)
		_press(blank, false)
		check_eq(_selected_count(), 0, "回归③-c 前置：清空选区")
		_press(pos_a, true)
		_motion(pos_b)
		_press(pos_b, false)
		check_eq(_selected_count(), 2, "回归③-c：划选 2 格（笔画链零回归）")
		check(bub.visible == false, "回归③-c：划选路径不弹气泡")

		# ③-d 关键锁：划选横穿立绘可见区不中断（批次 W P1-7a 修复不回退）
		_press(blank, true)
		_press(blank, false)
		check_eq(_selected_count(), 0, "回归③-d 前置：清空选区")
		if rect.size.x > 4.0:
			_press(pos_a, true)
			_motion(rect.get_center())      # 笔画横穿立绘可见区
			_motion(pos_b)
			_press(pos_b, false)
			check_eq(_selected_count(), 2, "回归③-d：划选横穿立绘带不中断（拖拽进行中分流不消费 motion）")
			check(bub.visible == false, "回归③-d：笔画横穿不弹气泡（仅点击命中才 toggle）")

		# ③-b 挖除：左键选中 + 右键原地抬起删除（批次 Z Z2 重排后置——划选两段已跑完）
		_press(pos_a, true)
		_press(pos_a, false)
		_right(pos_a, true)
		_right(pos_a, false)
		check_eq((inst.get("_remaining") as Dictionary).size(), remaining0 - 1,
			"回归③-b：右键抬起删除选中格（挖除链零回归）")
		check(bub.visible == false, "回归③-b：挖除路径不弹气泡")

		# ③-e 轨道旋转：空白右键拖拽（未命中路径）
		_press(blank, true)
		_press(blank, false)
		var yaw0: float = float(inst.get("_orbit_yaw"))
		_right(blank, true)
		for i: int in 6:
			_motion(blank + Vector2(6.0 * (i + 1), 2.0 * (i + 1)))
		_right(blank + Vector2(36.0, 12.0), false)
		check(absf(float(inst.get("_orbit_yaw")) - yaw0) > 0.01, "回归③-e：空白右键拖拽旋转相机（轨道链零回归）")
		check(bub.visible == false, "回归③-e：轨道旋转不弹气泡")
	else:
		check(false, "回归③：主视中线探针未探得 2 格（探针前置失败）")

	# ==================== ④ Y-C9 四隐患清偿断言 ====================
	# ④-1 tscn 与代码 mouse_filter 口径对齐（消除劈叉）→ **批次 AD §4.3.5 等价改写**：
	# MainView 锚点收窄至 0.115 避让立绘（重叠带根因消失）→ WitnessPortrait 由 IGNORE(2)
	# 恢复 STOP(0)（tscn 静态与代码运行时双口径同改，「劈叉消除」判据语义零变化）。
	# 旧值留痕：`seg.contains("mouse_filter = 2")` / `check_eq(int(...), 2, "…IGNORE=2…")`。
	var tscn_src := String(FileAccess.get_file_as_string("res://scenes/level/level_scene.tscn"))
	var wpos := tscn_src.find("[node name=\"WitnessPortrait\"")
	if wpos >= 0:
		var seg := tscn_src.substr(wpos, tscn_src.find("[node", wpos + 1) - wpos)
		check(seg.contains("mouse_filter = 0"), "AD §4.3.5：tscn WitnessPortrait mouse_filter=0（与代码 STOP 对齐，消除劈叉；旧 IGNORE=2 随锚点收窄退役）")
	else:
		check(false, "④-1：tscn 未找到 WitnessPortrait 节点段")
	check_eq(int(inst.get_node("WitnessPortrait").get("mouse_filter")), 0, "AD §4.3.5：运行时立绘 mouse_filter=STOP（口径一致；旧 IGNORE=2 留痕）")

	# ④-2 _tick_bubble_hover 孤儿链随恢复复活（hover 光晕能量渐入/渐出）
	if _req("get_witness_visible_rect") and rect.size.x > 4.0:
		inst.call("_show_witness_bubble")
		inst.call("_bubble_hover_probe", rect.get_center(), 0.25)
		check(float(inst.get("_bubble_hover_energy")) > 0.5,
			"④-2：气泡可见+光标在立绘 rect → hover 光晕能量渐入（实测 %.2f）" % float(inst.get("_bubble_hover_energy")))
		inst.call("_bubble_hover_probe", rect.get_center() + Vector2(600.0, 0.0), 0.25)
		check(float(inst.get("_bubble_hover_energy")) < float(0.25 * 8.0),
			"④-2：光标移出 → 能量渐出（能量按速率衰减，实测 %.2f）" % float(inst.get("_bubble_hover_energy")))
		inst.call("_hide_witness_bubble")
		inst.call("_bubble_hover_probe", rect.get_center(), 0.25)
		check(float(inst.get("_bubble_hover_energy")) <= 2.0 + 0.001,
			"④-2：气泡不可见 → 命中判定恒 false（能量不再升）")

	# ④-3 立绘左缘误拖窗豁免：场景谓词 + main.gd 拖窗判定接线
	if _req("is_point_over_witness_visible") and rect.size.x > 4.0:
		check(bool(inst.call("is_point_over_witness_visible", rect.get_center() + Vector2(0.5, 0.5))) == true,
			"④-3：立绘可见区中心命中谓词=true")
		check(bool(inst.call("is_point_over_witness_visible", Vector2(640, 120))) == false,
			"④-3：屏中远点命中谓词=false")
		check(bool(inst.call("is_point_over_witness_visible", Vector2(2.0, 640.0))) == false,
			"④-3：窗口左缘 x≈2（立绘透明带/盒外）命中谓词=false（不豁免拖窗）")
	var main_src := String(FileAccess.get_file_as_string("res://scenes/main.gd"))
	check(main_src.contains("is_point_over_witness_visible"),
		"④-3：main.gd 拖窗判定已接线立绘可见区豁免（最小 carve-out，Y-C9④）")
	check(inst.get_node("WitnessPortrait").has_meta("interactive"),
		"④-4：立绘 meta(interactive) 保留（分流选型下经谓词显式豁免拖窗，留痕见交付报告）")

	inst.free()
	await process_frame
	_restore_user()
	finish()
