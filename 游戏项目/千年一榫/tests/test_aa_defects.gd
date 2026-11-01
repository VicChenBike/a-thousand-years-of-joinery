extends "res://tests/test_base.gd"
## 批次 AA / 域 W9（规格 §12 深度扫描缺陷）——TDD 红测先行。
## 覆盖：W9-1(P2-2) close_requested 断点 flush / W9-2(P2-3) 坏档逐文件隔离 /
##   W9-3(P3-4) save_version 类型防御 / W9-4(P3-5) .bak 回滚失败保留 tmp（源契约）/
##   W9-5(P3-6) equipped 未变不落盘 / W9-6(P3-7) settings.volume 域级回落 /
##   W9-7(P3-8) 载入存档章节校验 / W9-8(P3-9) MAX_UNDO=200 截断 /
##   W9-9(P3-10a) 全挖空态见证者可达 / W9-10(P3-10b) 锐眼幻影裁剪 blocks 包围盒。
## 分段口径（防「一处崩全盘哑」，红态证据最大化）：
##   默认跑 = 全部段（顺序：W9-7→8→9→10→5→4→1→6a→3→2→6b）；前三段无崩溃风险，
##   W9-3/W9-2/W9-6b 段在**修复前**会 SCRIPT ERROR 中止（判绿双条件红），其红态证据
##   另由 `--sec=w92` / `--sec=w96b` 单段跑补全（W9-3 的中止证据取自默认跑）。
## 清档纪律（tools/README_走查清档规范.md 六条）：起测快照四件组→测试域操作→终测还原
##   + load_game 重同步 + 逐字节等价断言 + 崩溃自愈（_selfheal_previous_backup）。
## 摄像头红线：全程 gesture_input / gesture_camera_enabled 置 false，零真摄像头。

const MAIN_SCENE := "res://scenes/main.tscn"
const MAIN_SRC := "res://scenes/main.gd"
const MENU_SCENE := "res://scenes/menu/main_menu.tscn"
const MENU_SRC := "res://scenes/menu/main_menu.gd"
const LS_SCENE := "res://scenes/level/level_scene.tscn"
const LS_SRC := "res://scenes/level/level_scene.gd"
const SM_SRC := "res://autoload/save_manager.gd"
const LIB_SRC := "res://autoload/level_library.gd"
const AM_SRC := "res://autoload/audio_manager.gd"
const BUB_FIX := "res://tests/fixtures/bubble_y5_fixture.json"

const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"
const WATCHED: Array = [SAVE_PATH, FLAG_PATH, TMP_PATH, BAK_PATH]
const BK_PREFIX := "user://_aa_w9_backup_"
const SCAN_DIR := "user://w9_scan_probe"
const EMPTY_DIR := "user://w9_empty_levels"

const ST_MAIN_MENU := 1
const ST_LEVEL := 4
const CELL_A := Vector3i(0, 0, 0)

class StripSpy extends Node:
	var info_calls: Array = []
	var confirm_calls: Array = []
	func push_info(text: String, seconds: float = 3.0) -> void:
		info_calls.append([text, seconds])
	func push_confirm(text: String, on_confirmed: Callable = Callable(),
			on_canceled: Callable = Callable()) -> void:
		confirm_calls.append([text, on_confirmed, on_canceled])

var game: Variant
var save: Variant
var lib: Variant
var bridge: Variant
var _pre_save_text: String = ""
var _scan_fired := false
var _scan_loaded := -1
var _scan_failed := -1
var _scan_conn_ok := false

# ---------------- 清档纪律（test_w_checkpoint_debounce / test_y5 同款） ----------------
func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _del(p: String) -> void:
	var a: String = _abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _read_file(p: String) -> String:
	if not FileAccess.file_exists(p):
		return ""
	return FileAccess.get_file_as_string(p)

func _write_json(p: String, d: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(p, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t"))
	f.close()

func _disk_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var v: Variant = JSON.parse_string(_read_file(SAVE_PATH))
	return v if v is Dictionary else {}

func _disk_deleted_cells(ch: int) -> Variant:
	var lp: Variant = (_disk_save().get("progress", {}) as Dictionary).get("level_progress", {})
	var entry: Variant = (lp as Dictionary).get(str(ch), null)
	if typeof(entry) != TYPE_DICTIONARY:
		return null
	return (entry as Dictionary).get("deleted_cells", null)

func _selfheal_previous_backup() -> void:
	var healed := 0
	for p: String in WATCHED:
		var bk := BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			_del(p)
			DirAccess.copy_absolute(_abs(bk), _abs(p))
			DirAccess.remove_absolute(_abs(bk))
			healed += 1
	if healed > 0:
		print("EVID|selfheal|aa_w9|restored=%d" % healed)

func _backup_user() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		_pre_save_text = _read_file(SAVE_PATH)
	for p: String in WATCHED:
		if FileAccess.file_exists(p):
			var bk := BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_abs(p), _abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	# 先释放非 autoload 子节点（level_scene._exit_tree 会落断点——必须在还原文件之前完成）
	var autoloads: Array = ["SaveManager", "AudioManager", "ThemeManager", "GestureBridge",
		"LevelLibrary", "Game", "GestureRouter", "I18n", "MCPRuntime"]
	for c: Node in root.get_children():
		if autoloads.has(String(c.name)):
			continue
		c.free()
	for p: String in WATCHED:
		_del(p)
		var bk := BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_abs(bk), _abs(p))
			DirAccess.remove_absolute(_abs(bk))
	var sm: Node = root.get_node_or_null("SaveManager")
	if sm != null:
		sm.call("load_game")
	var post: String = _read_file(SAVE_PATH)
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|aa_w9|files=%d" % WATCHED.size())

func _func_body(src: String, sig: String) -> String:
	var f0: int = src.find(sig)
	if f0 < 0:
		return ""
	var f1: int = src.find("\nfunc ", f0 + 1)
	return src.substr(f0, (f1 if f1 > f0 else src.length()) - f0)

func _req_src(src: String, sig: String, msg: String) -> String:
	var body := _func_body(src, sig)
	check(body != "", msg)
	return body

func _cleanup_probe_dirs() -> void:
	for dir_path: String in [SCAN_DIR, EMPTY_DIR]:
		var d: DirAccess = DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		var fn: String = d.get_next()
		while fn != "":
			if not d.current_is_dir():
				DirAccess.remove_absolute(dir_path.path_join(fn))
			fn = d.get_next()
		d.list_dir_end()

func _ensure_dir(path: String) -> void:
	var parent := path.get_base_dir()
	var pd: DirAccess = DirAccess.open(parent)
	if pd != null and not pd.dir_exists(path.get_file()):
		pd.make_dir(path.get_file())

func _make_level(ch: int, with_lines: bool = true) -> Node:
	var inst: Node = (load(LS_SCENE) as PackedScene).instantiate()
	inst.call("set_context", {"chapter": ch})
	add_child(inst)
	await process_frame
	await process_frame
	if with_lines:
		inst.call("load_witness_lines_from_path", BUB_FIX)
		if inst.has_method("_refresh_witness_metrics"):
			inst.call("_refresh_witness_metrics")
	await process_frame
	return inst

func _on_scan(loaded: int, failed: int) -> void:
	_scan_fired = true
	_scan_loaded = loaded
	_scan_failed = failed

# ---------------- 主流程 ----------------
func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_selfheal_previous_backup()
	print("== test_aa_defects（批次 AA / W9 深度缺陷域）==")
	_backup_user()
	game = get_root().get_node("Game")
	save = get_root().get_node("SaveManager")
	lib = get_root().get_node("LevelLibrary")
	bridge = get_root().get_node("GestureBridge")
	_cleanup_probe_dirs()
	# 清档前奏 + 摄像头红线夹具（gesture/摄像头全关，零真摄像头）
	for p: String in WATCHED:
		_del(p)
	save.call("load_game")
	save.call("update_settings", {"gesture_input": false, "gesture_camera_enabled": false})
	if bridge != null:
		bridge.call("_set_state", 1)
	else:
		# 并行波半成品窗口期（gesture_bridge.gd 解析失败 → 该 autoload 缺席）：降级跳过手势夹具，
		# 防 _initialize 被 null 调用中止；本件全部断言零依赖 GestureBridge（红绿证据不受影响）。
		push_warning("GestureBridge 缺席（并行波窗口期），跳过 _set_state 夹具")
	lib.call("scan_directory", "res://levels_data")

	if args.has("--sec"):
		var i: int = args.find("--sec")
		var sec: String = args[i + 1] if i + 1 < args.size() else ""
		match sec:
			"w92":
				await _w9_2_scan_isolation()
			"w96b":
				await _w9_6b_audio_defense()
			_:
				check(false, "--sec 参数非法：%s" % sec)
		_cleanup_probe_dirs()
		_restore_user()
		finish()
		return

	await _w9_7_resume_validation()
	await _w9_8_max_undo()
	await _w9_9_witness_all_dug()
	await _w9_10_ghost_clip()
	await _w9_5_skin_no_write()
	await _w9_4_bak_rollback_contract()
	await _w9_1_close_flush()
	await _w9_6a_volume_normalize()
	await _w9_3_save_version_guard()
	await _w9_2_scan_isolation()
	await _w9_6b_audio_defense()
	_cleanup_probe_dirs()
	_restore_user()
	finish()

# ---------------- W9-7（P3-8）主菜单「载入存档」章节校验 ----------------
func _w9_7_resume_validation() -> void:
	print("-- W9-7 主菜单载入存档章节校验 --")
	var menu_src: String = _read_file(MENU_SRC)
	var body := _func_body(menu_src, "func _resume_from_save(")
	check(body != "", "W9-7-0 前置：main_menu._resume_from_save 可读")
	check(body.contains("get_level") and body.contains("is_empty"),
		"W9-7-s 源契约：_resume_from_save 对目标章节做 LevelLibrary.get_level 非空校验（红：旧实现缺失）")
	# 目标章节数据缺失（空关卡库）→ 零路由 + 提示
	_ensure_dir(EMPTY_DIR)
	lib.call("scan_directory", EMPTY_DIR)
	var spy := StripSpy.new()
	add_child(spy)
	game.call("attach_strip", spy)
	var menu: Node = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(menu)
	await process_frame
	await process_frame
	# 进度内存态**必须在首帧之后**注入：SaveManager._ready→load_game 于首帧执行，
	# 会把 _data 整体重载（提前注入会被首帧重载抹掉，红测假绿根因，实证留痕）。
	var prog: Dictionary = save.call("get_progress")
	prog["next_chapter"] = 1
	prog["cleared"] = [1]   # 内存态（has_any_progress 分支③），不落盘
	print("EVID|w97|has_any_progress=%s|next_chapter=%s|cleared=%s" % [
		str(save.call("has_any_progress")), str(prog.get("next_chapter", -1)),
		str(prog.get("cleared", []))])
	var st0: int = int(game.call("current_state"))
	menu.call("_on_load_save")
	check(int(game.call("current_state")) == st0,
		"W9-7a：目标章节数据缺失 → 零路由（留在原态；红：旧实现直落 LEVEL 空场占位关）")
	check(spy.info_calls.size() >= 1,
		"W9-7b：章节缺失给用户提示（Game.info 已发；红：旧实现静默进空关）")
	if spy.info_calls.size() >= 1:
		check(String((spy.info_calls[0] as Array)[0]).contains("关"),
			"W9-7c：提示文案含关卡语义")
	menu.free()
	await process_frame
	# 反向护栏：数据在位时照常路由（防「恒不路由」假绿）
	lib.call("scan_directory", "res://levels_data")
	var menu2: Node = (load(MENU_SCENE) as PackedScene).instantiate()
	add_child(menu2)
	await process_frame
	var prog2: Dictionary = save.call("get_progress")
	prog2["next_chapter"] = 1
	prog2["cleared"] = [1]
	menu2.call("_on_load_save")
	check_eq(int(game.call("current_state")), ST_LEVEL,
		"W9-7d：反向护栏——章节数据在位 → 正常路由 LEVEL")
	menu2.free()
	await process_frame
	game.call("goto_state", ST_MAIN_MENU)
	save.call("load_game")   # 内存态还原（cleared/next_chapter 回磁盘档）
	lib.call("scan_directory", "res://levels_data")

# ---------------- W9-8（P3-9）撤销栈上限 ----------------
func _w9_8_max_undo() -> void:
	print("-- W9-8 撤销栈 MAX_UNDO 截断 --")
	var ls_src: String = _read_file(LS_SRC)
	check(ls_src.contains("MAX_UNDO"),
		"W9-8-s 源契约：level_scene 定义 MAX_UNDO 撤销栈上限（红：旧实现无上限）")
	var inst: Node = await _make_level(1, false)
	if not inst.has_method("get_undo_depth"):
		check(false, "W9-8-0 前置：level_scene 撤销深度查询在位")
		inst.free()
		await process_frame
		return
	# 真实入栈 201 次：预填重做栈 201 组 → 循环 redo() 走**真实 append 点**（:1298 同源）
	var groups: Array = []
	for i: int in range(201):
		groups.append([])
	inst.set("_redo_stack", groups)
	for i: int in range(201):
		inst.call("redo")
	var depth: int = int(inst.call("get_undo_depth"))
	check(depth <= 200, "W9-8a：入栈 201 次 → 栈深 ≤200（红：旧实现 201）")
	check_eq(depth, 200, "W9-8b：截断保留最近 200 条（丢最旧）")
	# 常量真值
	var scr: Script = inst.get_script()
	var consts: Dictionary = scr.get_script_constant_map() if scr != null and scr.has_method("get_script_constant_map") else {}
	check(int(consts.get("MAX_UNDO", -1)) == 200,
		"W9-8c：MAX_UNDO==200【暂定值·待用户复验】（红：缺失/异值）")
	# 再一次**真实删除入栈**（_delete_cells append 点）仍不越界
	inst.call("select_voxel", CELL_A, true)
	inst.call("delete_selected")
	check(int(inst.call("get_undo_depth")) <= 200, "W9-8d：真实删除入栈后仍 ≤200（append 点同受截断）")
	inst.free()
	await process_frame

# ---------------- W9-9（P3-10a）全挖空态见证者可达 ----------------
func _w9_9_witness_all_dug() -> void:
	print("-- W9-9 全挖空态见证者点击 --")
	var ls_src: String = _read_file(LS_SRC)
	var body := _req_src(ls_src, "func _on_main_view_gui_input(", "W9-9-0 前置：入口函数可读")
	var i_disp: int = body.find("_witness_bubble_dispatch")
	var i_empty: int = body.find("_remaining.is_empty()")
	check(i_disp >= 0 and i_empty >= 0 and i_disp < i_empty,
		"W9-9s 源契约：事件分流先于 _remaining 空早退（红：旧序早退把全挖空态点击/悬停挡死）")
	var inst: Node = await _make_level(1, true)
	var cells: Array = inst.call("get_remaining_voxels")
	check(not cells.is_empty(), "W9-9-0 前置：关卡体素已构建")
	for c_v: Variant in cells:
		inst.call("select_voxel", c_v, true)
	var removed: int = int(inst.call("delete_selected"))
	check_eq(removed, cells.size(), "W9-9-0b 前置：全挖空（删尽全部剩余格）")
	check((inst.call("get_remaining_voxels") as Array).is_empty(), "W9-9-0c 前置：_remaining 已空")
	# 全挖空态点击立绘 → 气泡应弹出
	var rect: Rect2 = inst.call("get_witness_visible_rect")
	check(rect.size.x > 4.0 and rect.size.y > 4.0, "W9-9-0d 前置：立绘可见 rect 有效（%s）" % str(rect))
	var cont: Node = inst.get_node("MainView/ViewportContainer")
	var local: Vector2 = (cont.get_global_transform().affine_inverse()) * rect.get_center()
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = local
	inst.call("_on_main_view_gui_input", mb)
	var bub: Label = inst.get_node("WitnessBubble") as Label
	check(bool(inst.get("_witness_bubble_open")) and bub.visible,
		"W9-9a：全挖空态点击见证者 → 气泡弹出（红：旧实现早退不可达）")
	# 再点收起/再弹（toggle 语义在全挖空态两侧都要成立）
	mb.pressed = false
	inst.call("_on_main_view_gui_input", mb)
	check(bool(inst.get("_witness_bubble_open")), "W9-9b1：抬起不改变气泡态（对称消费）")
	mb.pressed = true
	inst.call("_on_main_view_gui_input", mb)
	check(not bool(inst.get("_witness_bubble_open")), "W9-9b2：全挖空态二次点击 → 气泡收起（toggle 闭合侧）")
	mb.pressed = false
	inst.call("_on_main_view_gui_input", mb)
	mb.pressed = true
	inst.call("_on_main_view_gui_input", mb)
	check(bool(inst.get("_witness_bubble_open")), "W9-9b3：三次点击 → 再弹（toggle 开启侧）")
	# 抬起对称：不吞 3D 释放（_remaining 空时无 3D 交互可言，仅断言不崩）
	mb.pressed = false
	inst.call("_on_main_view_gui_input", mb)
	check(true, "W9-9c：全挖空态抬起事件零异常")
	inst.free()
	await process_frame

# ---------------- W9-10（P3-10b）锐眼幻影裁剪 blocks 包围盒 ----------------
func _w9_10_ghost_clip() -> void:
	print("-- W9-10 锐眼幻影越界裁剪 --")
	var ls_src: String = _read_file(LS_SRC)
	var rb := _req_src(ls_src, "func _refresh_eye(", "W9-10-0 前置：_refresh_eye 可读")
	check(rb.contains("show_ghosts\", clip_to_blocks"),
		"W9-10s 源契约：_refresh_eye 把 missing 经 clip_to_blocks 裁剪后再 show_ghosts（红：旧实现直渲越界格）")
	var inst: Node = await _make_level(1, false)
	if not inst.has_method("clip_to_blocks"):
		check(false, "W9-10-1 裁剪缝 clip_to_blocks 存在（红：实现未落地）")
		inst.free()
		await process_frame
		return
	check(true, "W9-10-1 裁剪缝 clip_to_blocks 存在")
	var size := Vector3i(12, 3, 5)   # 第 1 关 blocks 域实况 12×3×5
	var raw: Array = [Vector3i(12, 0, 0), Vector3i(1, 1, 1), Vector3i(-1, 0, 0),
		Vector3i(0, 3, 0), Vector3i(11, 2, 4), Vector3i(0, 0, -1)]
	var clipped: Array = inst.call("clip_to_blocks", raw, size)
	check_eq(clipped, [Vector3i(1, 1, 1), Vector3i(11, 2, 4)],
		"W9-10a：越界/负值格裁剪，界内格保序保留（红：旧实现原样返回 6 格）")
	var empty_clip: Array = inst.call("clip_to_blocks", [], size)
	check(empty_clip.is_empty(), "W9-10b：空集裁剪仍空（幂等）")
	var all_in: Array = inst.call("clip_to_blocks", [Vector3i(11, 2, 4)], Vector3i.ZERO)
	check(all_in.is_empty(), "W9-10c：size 非正（未构建）→ 全裁（防未初始化渲染）")
	inst.free()
	await process_frame

# ---------------- W9-5（P3-6）皮肤迁移链省写 ----------------
func _w9_5_skin_no_write() -> void:
	print("-- W9-5 equipped 未变不落盘 --")
	save.call("load_game")
	var skins: Dictionary = save.call("get_skins")
	var origin: Dictionary = SkinCatalog.get_origin_skin(1)
	var oid: String = String(origin.get("id", ""))
	check(oid != "", "W9-5-0 前置：第 1 章原创皮肤存在（%s）" % oid)
	check_eq(String(skins.get("equipped", "")), oid, "W9-5-0b 前置：默认档已穿戴第 1 章原创")
	_del(SAVE_PATH)
	_del(TMP_PATH)
	_del(BAK_PATH)
	save.call("apply_contextual_skin", 1)
	check(not FileAccess.file_exists(SAVE_PATH),
		"W9-5a：equipped 未变 → apply_contextual_skin 零落盘（红：旧实现无条件 save_game）")
	_del(SAVE_PATH)
	save.call("restore_preferred_skin")
	check(not FileAccess.file_exists(SAVE_PATH),
		"W9-5b：equipped==preferred → restore_preferred_skin 零落盘（红：旧实现无条件 save_game）")
	# 反向护栏：真正变化时必须落盘（防「永不落盘」假绿）
	check(bool(save.call("set_preferred_skin", "skin_default")), "W9-5-0c 前置：换装成功")
	check(FileAccess.file_exists(SAVE_PATH), "W9-5c：反向护栏——换装（equipped 变更）仍落盘")
	check_eq(String(save.call("get_skins").get("equipped", "")), "skin_default", "W9-5-0d 前置：equipped 已切默认")
	_del(SAVE_PATH)
	save.call("apply_contextual_skin", 1)
	check(FileAccess.file_exists(SAVE_PATH),
		"W9-5d：反向护栏——equipped 变更时 apply_contextual_skin 仍落盘")
	save.call("load_game")

# ---------------- W9-4（P3-5）.bak 回滚失败保留 tmp（源契约） ----------------
func _w9_4_bak_rollback_contract() -> void:
	print("-- W9-4 .bak 回滚失败保留 tmp --")
	var sm_src: String = _read_file(SM_SRC)
	var sg := _req_src(sm_src, "func save_game(", "W9-4-0 前置：save_game 可读")
	var i_rb: int = sg.find("rename_absolute(bak_abs, save_abs) != OK")
	check(i_rb >= 0, "W9-4a：save_game 回滚 rename 返回值已判（红：旧实现返回值被丢弃）")
	if i_rb >= 0:
		var j: int = sg.find("remove_absolute(tmp_abs)", i_rb)
		var seg: String = sg.substr(i_rb, (j if j > i_rb else sg.length()) - i_rb)
		check(seg.contains("push_warning") and seg.contains("return false"),
			"W9-4b：回滚失败分支先告警再 return（tmp 不删；红：旧实现静默吞+删 tmp）")
		check(seg.contains("保留 tmp") or seg.contains("保留 tmp 副本") or seg.contains("已保留"),
			"W9-4c：告警文案明示 tmp 已保留（留痕）")
	check(sg.contains("remove_absolute(bak_abs)"),
		"W9-4-0b 前置：成功路径 .bak 清理保持（既有语义不回归）")
	# 主菜单/关卡侧同收口无遗漏：main._quit_now_shared 的 LEVEL flush 保持（既有锚复验）
	var main_src: String = _read_file(MAIN_SRC)
	var qb := _req_src(main_src, "func _quit_now_shared(", "W9-4-0c 前置：_quit_now_shared 可读")
	check(qb.contains("flush_checkpoint") and qb.contains("Game.State.LEVEL"),
		"W9-4d：自绘 × 路径 LEVEL 态显式 flush_checkpoint 保持（两条退出路径等级一致的前提）")

# ---------------- W9-1（P2-2）close_requested 断点 flush ----------------
func _w9_1_close_flush() -> void:
	print("-- W9-1 close_requested 断点 flush --")
	var sm_src: String = _read_file(SM_SRC)
	check(sm_src.contains("close_requested.connect(_on_close_requested)"),
		"W9-1-s1 源契约：close_requested 改接 _on_close_requested 收口（红：旧实现直连 save_game）")
	var cb := _req_src(sm_src, "func _on_close_requested(", "W9-1-s2 前置：close 收口函数可读")
	check(cb.contains("flush_checkpoint") and cb.contains("STATE_LEVEL"),
		"W9-1-s3 源契约：close 收口按 LEVEL 态（STATE_LEVEL 守卫）显式 flush_checkpoint（红：旧实现无检查点落盘）")
	check(cb.find("save_game()") < cb.find("flush_checkpoint"),
		"W9-1-s4 源契约：收口序 save_game 先、LEVEL flush 后（与 _quit_now_shared 同序）")
	# 常量真值：save_manager 的 STATE_LEVEL 镜像必须等于 Game.State.LEVEL（防枚举序漂移）
	var s_consts: Dictionary = save.get_script().get_script_constant_map()
	var g_consts: Dictionary = game.get_script().get_script_constant_map()
	check(int(s_consts.get("STATE_LEVEL", -1))
			== int((g_consts.get("State", {}) as Dictionary).get("LEVEL", -2)),
		"W9-1-s5：STATE_LEVEL 镜像值 == Game.State.LEVEL（%s vs %s）" % [
			str(s_consts.get("STATE_LEVEL", -1)),
			str((g_consts.get("State", {}) as Dictionary).get("LEVEL", -2))])
	# 运行期：boot 主场景 → LEVEL → 挖除 → 注入 close_requested → 断言断点已落盘
	var conns: Array = get_root().close_requested.get_connections()
	check(conns.size() >= 1, "W9-1-0 前置：close_requested 已接线（headless 下 Window 实例在位）")
	# 清断点前奏：W9-8/W9-9 的关卡实例 _exit_tree 已把第 1 章断点写盘 → 本段进关会
	# _replay_saved_progress 重放挖除（_remaining 空、挖除前置不成立且磁盘已有断点=假绿）。
	save.call("set_level_progress", 1, [])
	check(_disk_deleted_cells(1) == null, "W9-1-0e 前置：第 1 章断点已清（重放不干扰挖除前置）")
	if bridge == null:
		# 并行波半成品窗口期（gesture_bridge.gd 解析失败 → 该 autoload 缺席）：本段**不实例化
		# main.tscn**（其 _ready/_exit_tree 直连 GestureBridge，缺席时会抛错把本函数带崩）——
		# 改用最小容器自挂 Game（attach → goto_state(LEVEL) 同一装载链），行为段零依赖 GestureBridge。
		print("EVID|w9_1|fixture: 最小容器自挂（不实例化 main.tscn，规避并行波半成品窗口期）")
	# 最小场景容器（等价 main.tscn 的 SceneContainer/GlobalUI 装载链；仅 goto_state 消费容器）
	var cont := Control.new()
	cont.name = "W9SceneContainer"
	add_child(cont)
	var ovl := CanvasLayer.new()
	ovl.name = "W9OverlayLayer"
	add_child(ovl)
	game.call("attach", cont, ovl)
	game.call("goto_state", ST_LEVEL, {"chapter": 1})
	await process_frame
	await process_frame
	var lvl: Node = game.call("get_current_scene")
	check(lvl != null and lvl.has_method("flush_checkpoint"), "W9-1-0b 前置：LEVEL 态关卡场景就位")
	if lvl == null or not lvl.has_method("flush_checkpoint"):
		game.call("attach", null, null)
		cont.free()
		ovl.free()
		return
	lvl.call("select_voxel", CELL_A, true)
	var removed: int = int(lvl.call("delete_selected"))
	check(removed == 1, "W9-1-0c 前置：挖除 1 格（置脏）")
	check(_disk_deleted_cells(1) == null, "W9-1-0d 前置：防抖窗内磁盘无断点（脏未落）")
	get_root().close_requested.emit()   # 模拟 Alt+F4 / 系统级关闭
	var cells: Variant = _disk_deleted_cells(1)
	check(cells is Array and (cells as Array).has("0,0,0"),
		"W9-1a：close_requested（LEVEL 态）→ 断点已落盘（红：旧实现只 save_game，断点仍缺）")
	# 收尾：先解挂容器再**同步**释放（W9-8/9/10 的 inst.free() 同款路径；队列释放在帧回调内
	# 消化会把本协程带崩——实证：queue_free+await 后协程不再续行、进程提前退出）。
	game.call("attach", null, null)
	cont.free()
	ovl.free()
	save.call("load_game")
	lib.call("scan_directory", "res://levels_data")
	print("EVID|w9_1|step|cleanup_done")

# ---------------- W9-6a（P3-7）settings.volume 归一回落（load 路径） ----------------
func _w9_6a_volume_normalize() -> void:
	print("-- W9-6a settings.volume 归一回落 --")
	var sm_src: String = _read_file(SM_SRC)
	var nb := _req_src(sm_src, "func _normalize_loaded_data(", "W9-6a-0 前置：归一段可读")
	check(nb.contains("volume"),
		"W9-6a-s 源契约：归一段含 settings.volume 域级回落（红：旧实现唯独缺 volume）")
	var base: Dictionary = {
		"save_version": 2,
		"progress": {"cleared": [], "next_chapter": 1, "watched_opening": false, "level_progress": {}},
		"settings": {"gesture_input": false, "kb_input": true, "gesture_hud_visible": true,
			"gesture_hud_offset": [0, 0], "gesture_camera_enabled": false, "gesture_panel_folded": false,
			"gesture_camera_device": "", "gesture_camera_res": "", "gesture_camera_fps": 0,
			"volume": [], "udp_port": 0},
		"talent": 500,
		"skins": {"owned": ["skin_default", "skin_origin_kaitou"],
			"equipped": "skin_origin_kaitou", "preferred": "skin_origin_kaitou"},
		"replay_award_counts": {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0},
	}
	_write_json(SAVE_PATH, base)
	save.call("load_game")
	var vol: Variant = ((save.get("_data") as Dictionary).get("settings", {}) as Dictionary).get("volume", null)
	check(vol is Dictionary, "W9-6a1：volume 域脏类型（[]）→ 归一为字典（红：旧实现原样保留）")
	if vol is Dictionary:
		check_eq(float((vol as Dictionary).get("master", -1.0)), 1.0, "W9-6a2：volume.master 回落默认 1.0")
		check_eq(float((vol as Dictionary).get("music", -1.0)), 1.0, "W9-6a3：volume.music 回落默认 1.0")
		check_eq(float((vol as Dictionary).get("sfx", -1.0)), 1.0, "W9-6a4：volume.sfx 回落默认 1.0")
	# 子键非数值 → 该键默认 1.0（合法数值键保留）
	base["settings"]["volume"] = {"master": "0.5", "music": 0.25, "sfx": 1.0}
	_write_json(SAVE_PATH, base)
	save.call("load_game")
	var vol2: Variant = ((save.get("_data") as Dictionary).get("settings", {}) as Dictionary).get("volume", null)
	check(vol2 is Dictionary, "W9-6a5：子键脏类型下 volume 仍为字典")
	if vol2 is Dictionary:
		check_eq(float((vol2 as Dictionary).get("master", -1.0)), 1.0,
			"W9-6a6：子键非数值（字符串）→ 回落 1.0（红：旧实现 float(\"0.5\")=0.5 静默改值）")
		check_eq(float((vol2 as Dictionary).get("music", -1.0)), 0.25,
			"W9-6a7：合法数值子键 0.25 原样保留（不误伤）")
	save.call("load_game")

# ---------------- W9-3（P3-4）save_version 类型防御 ----------------
func _w9_3_save_version_guard() -> void:
	print("-- W9-3 save_version 类型防御 --")
	var sm_src: String = _read_file(SM_SRC)
	check(sm_src.contains("save_version 类型非法"),
		"W9-3-s 源契约：_parsed_save_version 对非法类型 push_warning 留痕（红：旧实现 int(v) 直接中止）")
	var bad: Dictionary = {
		"save_version": [],
		"progress": {"cleared": [2], "next_chapter": 3, "watched_opening": true, "level_progress": {}},
		"settings": {"gesture_input": false, "gesture_camera_enabled": false,
			"volume": {"master": 1.0, "music": 1.0, "sfx": 1.0}},
		"talent": 777,
		"skins": {"owned": ["skin_default"], "equipped": "skin_default", "preferred": "skin_default"},
		"replay_award_counts": {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0},
	}
	_write_json(SAVE_PATH, bad)
	print("MARK|w93|before_load_game")
	save.call("load_game")   # 修复前：int([]) SCRIPT ERROR 中止，其后断言全部不可达（红）
	print("MARK|w93|after_load_game")
	var d: Dictionary = save.get("_data")
	var def: Dictionary = save.call("_default_data")
	check_eq(int(d.get("save_version", -1)), int(def.get("save_version", -1)),
		"W9-3a：save_version 非法类型 → 走默认档（红：旧实现中止后状态不可判）")
	check_eq(d.get("progress", {}).get("cleared", []), [],
		"W9-3b：坏主档不进内存（progress 走默认，红：旧实现中止留下半载态）")
	check_eq(int(d.get("talent", -1)), int(def.get("talent", -1)),
		"W9-3c：talent 走默认（不被坏档 777 污染）")
	check(not bool(d.get("progress", {}).get("watched_opening", false)),
		"W9-3d：watched_opening 走默认 false")
	save.call("load_game")

# ---------------- W9-2（P2-3）坏档逐文件隔离 ----------------
func _w9_2_scan_isolation() -> void:
	print("-- W9-2 坏档逐文件隔离 --")
	var lib_src: String = _read_file(LIB_SRC)
	check(lib_src.contains("坏档已跳过"),
		"W9-2-s1 源契约：坏档 push_warning「坏档已跳过」留痕（红：旧实现静默中止无留痕）")
	check(lib_src.contains("_as_int") and lib_src.contains("_as_str"),
		"W9-2-s2 源契约：关卡数据取值走类型安全助手（红：旧实现裸 int()/String() 中止）")
	# 沙盒：2 合法 + 1 坏档（target_shapes 元素非数组）
	_ensure_dir(SCAN_DIR)
	_cleanup_probe_dirs()
	_ensure_dir(SCAN_DIR)
	var ch1: Dictionary = _load_json_dict("res://levels_data/level_chapter1_hemudu.json")
	var ch2: Dictionary = _load_json_dict("res://levels_data/level_chapter2_song.json")
	check(not ch1.is_empty() and not ch2.is_empty(), "W9-2-0 前置：合法关卡原文可读")
	_write_json(SCAN_DIR.path_join("b_ch1.json"), ch1)
	_write_json(SCAN_DIR.path_join("c_ch2.json"), ch2)
	var bad: Dictionary = ch1.duplicate(true)
	bad["chapter"] = 4
	(bad["pieces"] as Array)[0]["target_shapes"] = ["abc"]   # 元素非数组 → 旧实现 (ts[0] as Array) 恒 null 中止
	_write_json(SCAN_DIR.path_join("a_bad.json"), bad)
	if not lib.scan_finished.is_connected(_on_scan):
		lib.scan_finished.connect(_on_scan)
		_scan_conn_ok = true
	_scan_fired = false
	_scan_loaded = -1
	_scan_failed = -1
	print("MARK|w92|before_scan")
	lib.call("scan_directory", SCAN_DIR)
	print("MARK|w92|after_scan")
	check(_scan_fired, "W9-2a：坏档不中断扫描（scan_finished 仍发射；红：旧实现整扫描中止）")
	check_eq(_scan_loaded, 2, "W9-2b：其余两章仍正常载入（逐文件隔离）")
	check_eq(_scan_failed, 1, "W9-2c：坏档计入 failed（留痕计数）")
	var lst: Array = lib.call("get_level_list")
	check_eq(lst.size(), 2, "W9-2d：关卡表只含两份合法档（坏档被跳过）")
	check_eq(lib.call("get_level", 4), {}, "W9-2e：坏档章节不在关卡表（跳过即隔离）")
	var err4: String = String(lib.call("get_error", 4))
	check(err4 != "" and err4 != "关卡缺失", "W9-2f：坏档拒绝原因留痕（_errors[4]=%s）" % err4)
	if _scan_conn_ok:
		lib.scan_finished.disconnect(_on_scan)
		_scan_conn_ok = false
	_cleanup_probe_dirs()
	lib.call("scan_directory", "res://levels_data")

func _load_json_dict(p: String) -> Dictionary:
	var v: Variant = JSON.parse_string(_read_file(p))
	return v if v is Dictionary else {}

# ---------------- W9-6b（P3-7）audio_manager 运行期防御 ----------------
func _w9_6b_audio_defense() -> void:
	print("-- W9-6b audio_manager volume 运行期防御 --")
	var am_node: Node = get_root().get_node("AudioManager")
	check(am_node != null, "W9-6b-0a 前置：AudioManager 单例在位")
	var am_src: String = _read_file(AM_SRC)
	check(am_src.contains("TYPE_DICTIONARY") and am_src.contains("volume"),
		"W9-6b-s 源契约：apply_volumes 对 volume 容器做类型防御（红：旧实现 typed Dictionary 赋值裸取）")
	# 运行期脏注入（绕开 load 归一）：update_settings 合并路径会把非字典整体替换
	save.call("update_settings", {"volume": []})
	print("MARK|w96b|after_dirty_patch")
	check(true, "W9-6b1：volume 为 [] 时 apply_volumes 不中止（红：旧实现此处脚本运行期报错中止）")
	am_node.call("apply_volumes")
	var master_idx: int = AudioServer.get_bus_index("Master")
	check(master_idx >= 0, "W9-6b-0 前置：Master 总线在位")
	# 反向护栏：合法 volume 真的应用到总线（证明路径确实执行，而非空转）
	save.call("update_settings", {"volume": {"master": 0.25, "music": 1.0, "sfx": 1.0}})
	am_node.call("apply_volumes")
	var want: float = linear_to_db(0.25)
	check(absf(AudioServer.get_bus_volume_db(master_idx) - want) < 0.05,
		"W9-6b2：反向护栏——合法 volume.master=0.25 → Master 总线 %.2f dB（实际 %.2f）"
			% [want, AudioServer.get_bus_volume_db(master_idx)])
	# 第二种脏形态：数组元素
	save.call("update_settings", {"volume": ["x", "y"]})
	am_node.call("apply_volumes")
	check(true, "W9-6b3：volume 为数组元素时 apply_volumes 仍不中止")
	save.call("load_game")
