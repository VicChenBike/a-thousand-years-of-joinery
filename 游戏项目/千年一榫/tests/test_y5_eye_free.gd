extends "res://tests/test_base.gd"
## 批次 Y（Y-C4，spec §9.2 拍板 7）：第 5 关锐眼免费——红测双断言：
## ①第 5 关使用锐眼扣费=0（天赋值前后不变，激活态正常、流程不变）；
## ②第 1 关照旧扣费（1.0s 档=100，既有计费零改动）。
## 集中落点：level_scene 常量 EYE_FREE_CHAPTER + 谓词 is_eye_free_chapter + 计费口 eye_cost_for_chapter
## （清批次 G 既有 TODO「第 5 关免费常驻」，spec 7.4 遗留 #7）。
## 清档纪律：tools/README_走查清档规范.md（_start_eye→spend_talent→save_game 写档，先备份后还原）。

const LEVEL_SCENE := "res://scenes/level/level_scene.tscn"
const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_r_y5_eye_backup_"
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
		_disc_del_silent(p)
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(_disc_abs(bk))
	var sm: Node = root.get_node_or_null("SaveManager")
	if sm != null:
		sm.call("load_game")
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|y5eye|files=%d" % DISC_WATCHED.size())

func _disc_del_silent(p: String) -> void:
	var a: String = _disc_abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _make_level(ch: int) -> Node:
	var inst: Node = (load(LEVEL_SCENE) as PackedScene).instantiate()
	inst.call("set_context", {"chapter": ch})
	add_child(inst)
	await process_frame
	await process_frame
	return inst

func _initialize() -> void:
	print("== test_y5_eye_free ==")
	_backup_user()
	var save: Node = root.get_node("SaveManager")
	save.call("load_game")
	var lib: Node = root.get_node("LevelLibrary")
	lib.call("scan_directory")

	# ---- 红测断言①：第 5 关锐眼免费（扣费=0）----
	var inst5: Node = await _make_level(5)
	check(not inst5.call("is_input_locked"), "第 5 关前置：场景在位且未锁定")
	save.call("add_talent", 1000)
	var t0: int = int(save.call("get_talent"))
	var started5: bool = bool(inst5.call("_start_eye", 1.0))
	check(started5 == true, "第 5 关：锐眼开启成功返回 true")
	check(bool(inst5.call("is_eye_active")) == true, "第 5 关：开启后处于激活态（流程不变）")
	check_eq(int(save.call("get_talent")), t0, "第 5 关：扣费=0（免费，天赋值前后不变）")
	var hud5: Label = inst5.get_node_or_null("TopBar/TalentLabel")
	check(hud5 != null and String(hud5.text).contains(str(t0)), "第 5 关：天赋值 HUD 仍显示 %d" % t0)
	inst5.call("_finish_eye")
	inst5.free()
	await process_frame

	# ---- 红测断言②：第 1 关照旧扣费 ----
	var inst1: Node = await _make_level(1)
	save.call("add_talent", 1000)
	var t1: int = int(save.call("get_talent"))
	var started1: bool = bool(inst1.call("_start_eye", 1.0))
	check(started1 == true, "第 1 关：锐眼开启成功返回 true")
	check_eq(int(save.call("get_talent")), t1 - 100, "第 1 关：照旧扣费=100（1.0s 档，既有计费零改动）")
	check(bool(inst1.call("is_eye_active")) == true, "第 1 关：激活态正常")
	inst1.call("_finish_eye")
	inst1.free()
	await process_frame

	# ---- 集中常量/谓词（走查调档单点）----
	var cmap: Dictionary = (load("res://scenes/level/level_scene.gd") as GDScript).get_script_constant_map()
	check(cmap.has("EYE_FREE_CHAPTER") and int(cmap["EYE_FREE_CHAPTER"]) == 5,
		"集中常量：EYE_FREE_CHAPTER=5")
	var ls: GDScript = load("res://scenes/level/level_scene.gd")
	check_eq(int(ls.call("eye_cost_for_chapter", 5, 1.0)), 0, "计费口：eye_cost_for_chapter(5, 1.0)=0")
	check_eq(int(ls.call("eye_cost_for_chapter", 1, 1.0)), 100, "计费口：eye_cost_for_chapter(1, 1.0)=100")
	check_eq(int(ls.call("eye_cost", 1.0)), 100, "回归：原 eye_cost(1.0)=100 逐字节不变")
	check(bool(ls.call("is_eye_free_chapter", 5)) == true
		and bool(ls.call("is_eye_free_chapter", 1)) == false, "谓词：is_eye_free_chapter(5)=true/(1)=false")

	_restore_user()
	finish()
