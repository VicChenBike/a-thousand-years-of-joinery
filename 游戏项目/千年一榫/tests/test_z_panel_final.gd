extends "res://tests/test_base.gd"
## 批次 Z Z1（编辑器面板映射修正·主游戏侧）红测：关卡左上面板「最终成品 final」口径
## + 标准答案 target 关卡内零渲染 + 判定侧零改动回归。
## 契约来源：项目内部设计文档 §1（三者同改·用户拍板）：
##   ①左上视图体素集合 == 该关 final_answer.voxels（**相对断言**，不依赖具体数值；
##     改前视图渲染 target_shapes[0]，当前数据 final≠target → 必红）；
##     配前置护栏 final 集合 != target 集合（数据若未来相等则断言空转，先判红提醒重审）。
##   ②左上标题文本 ==「最终成品」、右上 ==「对接固定件」（右上零变化等价锚）。
##   ③零 target 渲染消费点——读 level_scene.gd 源码：含 build_voxels 的行不得引用
##     target_shapes/_target_shape0；且必须存在 build_voxels+final_answer 行（数据源落 final
##     的正向锚）+ **Target 视图自身 build 行数据源含 final_answer**（Z1③e，Z-A 回修 P2-2 补锚；
##     该行锚**非完备**——中间变量重建 target 渲染可绕过，靠 Z1① 实例断言兜底，注释已显式记录）。
##     配套**保留锚**：_target_shape0 缓存赋值与 _on_join_pressed 的 target_shapes
##     读取必须在场——判定与锐眼差集都依赖它，被误删同样判红（判定侧零改动的反向护栏）。
##   ④对接判定回归：evaluate_join(remaining=该关 target 集, target_shapes, join) == "success"
##     （evaluate_join/_on_join_pressed 零改动；经场景实例静态调用，test_level_flow 同款先例）。
##   ⑤键鼠路径零回归：三视图容器在场 + 主视图/两侧视图 gui_input 与对接钮 pressed 绑定未破
##     （信号查连接必须 Signal.get_connections——4.7 get_incoming_connections 不列脚本运行时连接）。
## Godot 4.7 实证：--script 无头 _initialize 阶段节点不在树——set_context 先于
## add_child、其后 await process_frame（T14/test_level_scene 先例）；实例化 level_scene 即在
## _exit_tree 写检查点——清档纪律照抄 test_level_scene（备份→清域→终测还原→逐字节自检）。

const SCENE_PATH := "res://scenes/level/level_scene.tscn"
const LEVEL_JSON := "res://levels_data/level_chapter1_hemudu.json"

# ===== 清档纪律（照抄 test_level_scene 同款：断点残留隔离，_exit_tree 检查点不污染真实档）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_z1pf_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
var _pre_save_text: String = ""

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _backup_user() -> void:
	for p0: String in DISC_WATCHED:
		var bk0: String = DISC_BK_PREFIX + p0.get_file()
		if FileAccess.file_exists(_disc_abs(bk0)):
			if FileAccess.file_exists(_disc_abs(p0)):
				DirAccess.remove_absolute(_disc_abs(p0))
			DirAccess.copy_absolute(_disc_abs(bk0), _disc_abs(p0))
			DirAccess.remove_absolute(_disc_abs(bk0))
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(_disc_abs(p)):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)
			DirAccess.remove_absolute(_disc_abs(p))   # 清域（断点归零，进关重放确定性）

func _restore_user() -> void:
	for c: Node in root.get_children():
		if not ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager", "GestureBridge",
				"LevelLibrary", "Game", "GestureRouter", "I18n"].has(String(c.name)):
			c.free()   # 先 free 测试挂载节点（level._exit_tree 兜底写档先落盘，规范第 6 条）
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(_disc_abs(p)):
			DirAccess.remove_absolute(_disc_abs(p))
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(_disc_abs(bk)):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
	var real_sm: Node = root.get_node_or_null("SaveManager")
	if real_sm != null:
		real_sm.load_game()   # 内存重同步（防后续 save_game 把测试态写回真实档案）
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")

func finish() -> void:
	_restore_user()
	super.finish()

# ---------- helpers ----------
## 元素归一（"x,y,z" 串 / Array / Vector3i）→ 规范键 "x,y,z"；非法跳过（字典键去重）。
func _key_of(v: Variant) -> String:
	if v is String:
		var parts: PackedStringArray = (v as String).split(",")
		if parts.size() != 3:
			return ""
		return "%d,%d,%d" % [int(parts[0]), int(parts[1]), int(parts[2])]
	if v is Array and (v as Array).size() == 3:
		return "%d,%d,%d" % [int((v as Array)[0]), int((v as Array)[1]), int((v as Array)[2])]
	if v is Vector3i:
		var c: Vector3i = v
		return "%d,%d,%d" % [c.x, c.y, c.z]
	if v is Vector3:
		var cv: Vector3 = v
		return "%d,%d,%d" % [int(cv.x), int(cv.y), int(cv.z)]
	return ""

func _set_of(arr: Array) -> Dictionary:
	var d: Dictionary = {}
	for v: Variant in arr:
		var k := _key_of(v)
		if k != "":
			d[k] = true
	return d

## Signal.get_connections 查连接（4.7 实证：get_incoming_connections 不列脚本运行时连接）。
func _sig_has(sig: Signal, method: String) -> bool:
	for c in sig.get_connections():
		if (c["callable"] as Callable).get_method() == method:
			return true
	return false

func _initialize() -> void:
	print("== test_z_panel_final ==")
	_backup_user()   # 清档纪律（见头注）
	get_root().get_node("SaveManager").call("load_game")

	# ---- 关卡数据（经 LevelLibrary 净化后的实况——与视图构建同源）----
	var lib: Variant = get_root().get_node("LevelLibrary")
	var lvl: Dictionary = lib.call("get_level", 1)
	if lvl.is_empty():
		lib.call("scan_directory", "res://levels_data")   # level_scene._load_level 同款兜底
		lvl = lib.call("get_level", 1)
	check(not lvl.is_empty(), "前置：LevelLibrary 第 1 关可取")
	if lvl.is_empty():
		finish()
		return
	var piece: Dictionary = ((lvl["data"] as Dictionary)["pieces"] as Array)[0]
	var target_shapes: Array = piece.get("target_shapes", [])
	var t0: Array = target_shapes[0] if not target_shapes.is_empty() else []
	var final_voxels: Array = (piece.get("final_answer", {}) as Dictionary).get("voxels", [])
	var join_vox: Array = (piece.get("join_part", {}) as Dictionary).get("voxels", [])
	var t_set := _set_of(t0)
	var f_set := _set_of(final_voxels)
	var j_set := _set_of(join_vox)
	check(not t_set.is_empty() and not f_set.is_empty(), "前置：target/final 均非空")
	check(t_set != f_set, "前置：final 与 target 集合不等（断言①防空转护栏——数据若相等须重审本测）")

	# ---- ③ 零 target 渲染消费点（源码断言，与实例化无关，先做）----
	var src: String = FileAccess.get_file_as_string("res://scenes/level/level_scene.gd")
	check(src.length() > 0, "前置：level_scene.gd 源码可读")
	var bad_lines: Array = []
	for ln: String in src.split("\n"):
		if ln.contains("build_voxels") and (ln.contains("_target_shape0") or ln.contains("target_shapes")):
			bad_lines.append(ln.strip_edges())
	check(bad_lines.is_empty(),
		"Z1③ 关卡内零 target 渲染消费点——build_voxels 行不得引用 target_shapes/_target_shape0（命中 %d 行：%s）"
		% [bad_lines.size(), str(bad_lines)])
	var has_final_build := false
	for ln2: String in src.split("\n"):
		if ln2.contains("build_voxels") and ln2.contains("final_answer"):
			has_final_build = true
	check(has_final_build, "Z1③b 左上视图数据源落 final——存在 build_voxels 行引用 final_answer（正向锚）")
	# Z1③e 正向锚（Z-A 回修 P2-2）：**Target 视图** build 调用行的数据源表达式必须含 final_answer
	# （把「存在任一 final_answer 的 build 行」收紧到「Target 视图自己的 build 行」）。
	# ⚠ 本锚**非完备**——若将来有人用中间变量重建 target 渲染（如 `var cells = ...; target_vv.call(
	# "build_voxels", cells, …)`），本源码行锚识别不到；该缺口**依赖 Z1① 实例断言兜底**
	# （左上视图 get_built_cells 集合 == final_answer.voxels，运行期真值，任何换源写法都会被它抓到）。
	var target_build_line := ""
	for ln3: String in src.split("\n"):
		if ln3.contains("target_vv") and ln3.contains("build_voxels"):
			target_build_line = ln3.strip_edges()   # 取最后一条命中（Target 视图构建行）
	check(target_build_line.contains("final_answer"),
		"Z1③e 正向锚：Target 视图 build_voxels 行数据源含 final_answer（行空=锚失配必红；实际行：%s）"
		% (target_build_line if target_build_line != "" else "<未命中任何 target_vv+build_voxels 行>"))
	check(src.contains("_target_shape0 = (piece[\"target_shapes\"] as Array)[0]"),
		"Z1③c 保留锚：_target_shape0=target_shapes[0] 缓存仍在（判定/锐眼差集依赖，不得随渲染换源误删）")
	check(src.contains("var targets: Array = piece.get(\"target_shapes\", [])"),
		"Z1③d 保留锚：_on_join_pressed 仍读 target_shapes（判定侧零改动）")

	# ---- ①②④⑤ 场景实例化（T14 约定：set_context 先于 add_child，其后等一帧）----
	var packed: PackedScene = load(SCENE_PATH)
	var inst: Node = packed.instantiate()
	if inst == null:
		check(false, "前置：level_scene 可实例化")
		finish()
		return
	inst.call("set_context", {"chapter": 1})
	add_child(inst)
	await process_frame

	# ① 左上视图体素集合 == final_answer.voxels
	var tvv: Node = inst.get_node_or_null("TargetView/ViewportContainer/SubViewport/VoxelView")
	check(tvv != null, "前置：TargetView VoxelView 在场")
	if tvv != null:
		var built := _set_of(tvv.call("get_built_cells") as Array)
		check_eq(built, f_set,
			"Z1① 左上视图体素集合 == 该关 final_answer.voxels（数据源 final；改前==target 必红）")
		check(built != t_set, "Z1①b 左上视图不再渲染 target 集（反向护栏）")

	# ② 标题：左上「最终成品」/ 右上「对接固定件」（右上零变化等价锚）
	var t_title := inst.get_node_or_null("TargetView/Title") as Label
	var j_title := inst.get_node_or_null("JoinView/Title") as Label
	check(t_title != null and j_title != null, "前置：两侧标题节点在场")
	if t_title != null:
		check_eq(String(t_title.text), "最终成品", "Z1② 左上标题=「最终成品」（改前=对照成品必红）")
	if j_title != null:
		check_eq(String(j_title.text), "对接固定件", "Z1②b 右上标题=「对接固定件」（零变化等价锚）")

	# ④ 右上视图零变化 + 对接判定回归
	var jvv: Node = inst.get_node_or_null("JoinView/ViewportContainer/SubViewport/VoxelView")
	if jvv != null:
		check_eq(_set_of(jvv.call("get_built_cells") as Array), j_set,
			"Z1④ 右上视图==join_part.voxels（右上数据零变化等价锚）")
	var remaining: Dictionary = {}
	for k: String in t_set.keys():
		remaining[k] = true
	check_eq(String(inst.call("evaluate_join", remaining, target_shapes, join_vox)), "success",
		"Z1④b 对接判定回归：remaining==target → success（evaluate_join 仍读 target_shapes，判定零改动）")

	# ⑤ 键鼠路径零回归：三视图容器 + gui_input/pressed 绑定未破
	var main_cont: Node = inst.get_node_or_null("MainView/ViewportContainer")
	var t_cont: Node = inst.get_node_or_null("TargetView/ViewportContainer")
	var j_cont: Node = inst.get_node_or_null("JoinView/ViewportContainer")
	check(main_cont is SubViewportContainer and t_cont is SubViewportContainer and j_cont is SubViewportContainer,
		"Z1⑤ 三视图 SubViewportContainer 节点在场")
	if main_cont is SubViewportContainer:
		check(_sig_has((main_cont as SubViewportContainer).gui_input, "_on_main_view_gui_input"),
			"Z1⑤b 主视图 gui_input→_on_main_view_gui_input 绑定未破")
	if t_cont is SubViewportContainer:
		check(_sig_has((t_cont as SubViewportContainer).gui_input, "_on_side_view_gui_input"),
			"Z1⑤c 左上侧视图 gui_input→_on_side_view_gui_input 绑定未破")
	if j_cont is SubViewportContainer:
		check(_sig_has((j_cont as SubViewportContainer).gui_input, "_on_side_view_gui_input"),
			"Z1⑤d 右上侧视图 gui_input→_on_side_view_gui_input 绑定未破")
	var join_btn := inst.get_node_or_null("TopBar/Buttons/JoinButton") as Button
	check(join_btn != null and _sig_has(join_btn.pressed, "_on_join_pressed"),
		"Z1⑤e 对接钮 pressed→_on_join_pressed 绑定未破")
	check(inst.call("get_side_selected_count") == 0, "Z1⑤f 侧视选区结构可用（零选区基线）")

	inst.free()   # 立即触发 _exit_tree 检查点写盘（随后 _restore_user 覆盖还原）
	finish()
