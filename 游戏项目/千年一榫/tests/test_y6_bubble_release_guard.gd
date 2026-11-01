extends "res://tests/test_base.gd"
## 批次 Y 扫描回修 P1（BUG 扫描结论）——气泡事件分流「抬起消费」不校验按下归属
## → 虚拟按键卡死。红测先行。
## 缺陷复现序列：左/右键「按下」落在体素/空白（进 3D 链置 _left_pressed/_right_pressed）
## → motion 横跨立绘可见区（拖拽放行守卫不消费）→ 「抬起」落点命中立绘可见 rect
## → 旧实现 :1466 `elif not mb.pressed and hit` 无条件吞掉抬起 → level_scene 永远收不到
## 抬起 → 划选/ORBIT 卡死、右键候选态残留（_drag_mode 停在 ORBIT）。
## 修法（一行闭合对称性）：抬起分支补 `and not (_left_pressed or _middle_pressed or
## _right_pressed)`——按下被立绘消费时这些标志必 false（对称抬起照旧吞掉，回归锁④）；
## 3D 链按下时必 true（不吞，抬起照常送达 3D 链收尾，本文件①②③红→绿）。
## 回归锁：test_y5_bubble_dispatch 全件复跑（按下在立绘→抬起在立绘→气泡 toggle 语义）。
## 清档纪律：user:// 备份还原（前缀 y6brg，test_y5_bubble_dispatch 同款四件组）。

const LEVEL_SCENE := "res://scenes/level/level_scene.tscn"
const FIXTURE := "res://tests/fixtures/bubble_y5_fixture.json"
const MISS := Vector3i(-1, -1, -1)
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_y6brg_backup_"
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
	print("EVID|user_restore|y6brg|files=%d" % DISC_WATCHED.size())

var inst: Node

func _make_level(ch: int) -> void:
	inst = (load(LEVEL_SCENE) as PackedScene).instantiate()
	inst.call("set_context", {"chapter": ch})
	add_child(inst)
	await process_frame
	await process_frame
	inst.call("load_witness_lines_from_path", FIXTURE)
	inst.call("_refresh_witness_metrics")
	await process_frame

func _free_level() -> void:
	if inst != null and is_instance_valid(inst):
		inst.free()
	inst = null
	await process_frame

func _press(pos: Vector2, pressed: bool) -> void:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.position = pos
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

func _selected() -> Dictionary:
	return inst.get("_selected")

func _probe_cells() -> Array:
	## 主视中线步进探 2 互异命中格（test_y5_bubble_dispatch 同款）
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

func _initialize() -> void:
	print("== test_y6_bubble_release_guard ==")
	_backup_user()
	# 清档前奏：删档保证第 1 关满态起测（探针确定性前提，test_y5_bubble_dispatch 同款）
	for p: String in [DISC_SAVE_PATH, DISC_TMP_PATH, DISC_BAK_PATH]:
		if FileAccess.file_exists(_disc_abs(p)):
			DirAccess.remove_absolute(_disc_abs(p))
	root.get_node("SaveManager").call("load_game")
	var lib: Node = root.get_node("LevelLibrary")
	lib.call("scan_directory")
	await _make_level(1)

	var bub: Label = inst.get_node("WitnessBubble")
	check(bub is Label and bub.visible == false, "前置：气泡节点在位且初始隐藏")
	var rect: Rect2 = inst.call("get_witness_visible_rect")
	check(rect.size.x > 4.0 and rect.size.y > 4.0, "前置：立绘可见 rect 有效（%s）" % str(rect))
	var inside: Vector2 = rect.get_center()
	check(bool(inst.call("is_point_over_witness_visible", inside)), "前置：rect 中心命中立绘可见区")
	var probes := _probe_cells()
	check(probes.size() == 2, "前置：主视中线探针探得 2 互异命中格")
	var cont: SubViewportContainer = inst.get_node("MainView/ViewportContainer")
	var blank: Vector2 = cont.get_global_rect().position + Vector2(6.0, 6.0)
	check(not bool(inst.call("is_point_over_witness_visible", blank)), "前置：左上角空白点不在立绘可见区")

	if rect.size.x > 4.0 and probes.size() == 2:
		var cell_a: Vector3i = probes[0][0]
		var pos_a: Vector2 = probes[0][1]
		var dm_none: int = inst.DragMode.NONE

		# ==================== ① 左键划选：按下体素→motion 横穿立绘→抬起在立绘 ====================
		# 按下在体素进 3D 链（_left_pressed=true/STROKE），拖拽中 motion 经放行守卫横穿立绘带，
		# 抬起落点命中立绘可见区——抬起必须送达 3D 链收尾（_left_pressed 复位/_drag_mode=NONE）。
		_press(pos_a, true)
		check_eq((_selected() as Dictionary).size(), 1, "①前置：体素按下即选中起始格（3D 链接管）")
		check(bool(inst.get("_left_pressed")), "①前置：3D 链按下 _left_pressed=true")
		_motion(inside)   # 拖拽中 motion 横穿立绘带（放行守卫，不消费）
		_press(inside, false)   # 抬起落点在立绘可见区
		check(not bool(inst.get("_left_pressed")), "P1①：抬起在立绘区但按下归属 3D 链 → 抬起送达收尾（_left_pressed 复位，旧实现被 ：1466 吞掉=卡死）")
		check_eq(int(inst.get("_drag_mode")), dm_none, "P1①：划选态收尾（_drag_mode=NONE，旧实现残留 STROKE）")
		check((_selected() as Dictionary).has(cell_a), "P1①：起始格保留（划选收尾语义不回退）")
		check(bub.visible == false, "P1①：跨立绘笔画全程不弹气泡（按下未命中立绘）")
		await _free_level()

		# ==================== ② 左键 ORBIT：空白按下→motion 入立绘→抬起在立绘 ====================
		await _make_level(1)
		bub = inst.get_node("WitnessBubble")
		_press(blank, true)
		check(bool(inst.get("_left_pressed")), "②前置：空白按下 ORBIT（_left_pressed=true）")
		_motion(inside)
		_press(inside, false)
		check(not bool(inst.get("_left_pressed")), "P1②：ORBIT 抬起在立绘区 → 送达收尾（_left_pressed 复位）")
		check_eq(int(inst.get("_drag_mode")), dm_none, "P1②：旋转态收尾（_drag_mode=NONE）")
		check_eq((_selected() as Dictionary).size(), 0, "P1②：轨道旋转不清选区（空选区原语义）")
		check(bub.visible == false, "P1②：ORBIT 跨立绘不弹气泡")
		await _free_level()

		# ==================== ③ 右键候选：空白按下→motion 入立绘→抬起在立绘 ====================
		# 右键候选态残留危害：_right_pressed 残留 + _drag_mode 停留 ORBIT（下一次抬起行为失真）。
		await _make_level(1)
		bub = inst.get_node("WitnessBubble")
		var remaining0: int = (inst.get("_remaining") as Dictionary).size()
		_right(blank, true)
		check(bool(inst.get("_right_pressed")), "③前置：右键空白按下进候选态（_right_pressed=true）")
		_motion(inside)   # 位移 >2px → 候选升级 ORBIT（motion 经 3D 链）
		check(bool(inst.get("_right_orbit")), "③前置：位移超阈值候选升级旋转（_right_orbit=true）")
		_right(inside, false)
		check(not bool(inst.get("_right_pressed")), "P1③：右键抬起在立绘区 → 送达收尾（_right_pressed 复位，旧实现残留=候选态卡死）")
		check_eq(int(inst.get("_drag_mode")), dm_none, "P1③：候选态收尾（_drag_mode=NONE）")
		check_eq((inst.get("_remaining") as Dictionary).size(), remaining0, "P1③：已成旋转的右键抬起不删除（删除语义零回归）")
		check(bub.visible == false, "P1③：右键跨立绘不弹气泡（右/中键按下仅消费不 toggle，语义不回退）")
		# 残留危害锁：修复后再次自由抬起不得有候选态残留副作用（空选区删除=内部提示零删格）
		_right(blank, false)
		check(not bool(inst.get("_right_pressed")), "P1③：后续自由抬起无残留副作用")
		check_eq((inst.get("_remaining") as Dictionary).size(), remaining0, "P1③：后续自由抬起零删格（空选区）")
		await _free_level()

		# ==================== ④ 回归锁：按下在立绘→抬起在立绘→气泡 toggle 对称消费不回退 ====================
		await _make_level(1)
		bub = inst.get_node("WitnessBubble")
		_press(inside, true)
		check(bub.visible == true, "回归④：左键按下立绘 → 气泡弹出（旧口径保持）")
		check(not bool(inst.get("_left_pressed")), "回归④：立绘按下被消费（3D 链标志不置位）")
		_press(inside, false)
		check(bub.visible == true, "回归④：立绘按下→立绘抬起 → 对称消费（气泡保持，toggle 不被抬起误关）")
		check(not bool(inst.get("_left_pressed")), "回归④：对称抬起被消费且标志不复位污染")
		_press(inside, true)
		check(bub.visible == false, "回归④：显示期间再点 → 关闭（toggle 语义零回退）")
		_press(inside, false)
		await _free_level()

	inst = null
	_restore_user()
	finish()
