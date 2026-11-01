extends "res://tests/test_base.gd"
## 批次 Z Z3（spec §3-8 验收⑦，复验红测锁）：**立绘按剧情解锁**——
##   `autoload/game.gd.goto_state`：进 **TALK/LEVEL** 时先 unlock 该章原创（点位①，幂等）再
##   **强制穿戴时代立绘**（不动 preferred）；出到 **SETTLE/MAIN_MENU/CATALOG** 还原玩家自选
##   `preferred`。行为已实现（K-D Q2 单点收口），本件为**行为锁**（防回归；护栏真实性=临时
##   删 game.gd 强制穿戴守卫见红，见交付报告）。
## 驱动：全经**生产路由** Game.attach 容器 + goto_state（非直调 SaveManager API——那层已由
##   test_skin_origin/test_save_manager 锁过，本件锁的是 goto_state 接线层）。
## 前置：玩家自选 preferred=skin_01（非默认），证「强制穿戴」与「自选」确实分离。
## 清档纪律：goto_state 穿戴/解锁均写档 → user:// 备份还原（独立前缀 zpsl，规范六条）。

const ST_MAIN_MENU := 1
const ST_TALK := 3
const ST_LEVEL := 4
const ST_SETTLE := 5
const ST_CATALOG := 6

const PREFERRED_ID := "skin_01"             # 玩家自选（测试前置购置+穿戴）
const CH2_ORIGIN := "skin_origin_song"      # 第 2 关（宋）时代原创
const CH1_ORIGIN := "skin_origin_kaitou"    # 第 1 关（开头）时代原创
const TALENT_SETUP := 1000
const SKIN_PRICE := 205

# ===== 清档纪律（tools/README_走查清档规范.md）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_zpsl_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _pre_save_text: String = ""

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _disc_del(p: String) -> void:
	var a: String = _disc_abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _backup_user() -> void:
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))

func _restore_user() -> void:
	for c: Node in root.get_children():
		if not DISC_AUTOLOADS.has(String(c.name)):
			c.free()
	for p: String in DISC_WATCHED:
		_disc_del(p)
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|zpsl|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _equipped(save: Variant) -> String:
	return String((save.get_skins())["equipped"])

func _preferred(save: Variant) -> String:
	return String((save.get_skins())["preferred"])

func _initialize() -> void:
	print("== test_z_portrait_story_lock ==")
	_backup_user()
	var save: Variant = root.get_node("SaveManager")
	var game: Variant = root.get_node("Game")
	var lib: Variant = root.get_node("LevelLibrary")
	lib.call("scan_directory")

	# 清档 + 前置：玩家自选 preferred=skin_01（非默认——强制/自选分离才有区分度）
	for p: String in DISC_WATCHED:
		_disc_del(p)
	save.load_game()
	save.spend_talent(save.get_talent())
	save.add_talent(TALENT_SETUP)
	check(bool(save.buy_skin(PREFERRED_ID)), "前置：购入 %s（价 %d）" % [PREFERRED_ID, SKIN_PRICE])
	check(bool(save.equip_skin(PREFERRED_ID)), "前置：玩家自选穿戴 %s" % PREFERRED_ID)
	check_eq(_preferred(save), PREFERRED_ID, "前置：preferred==%s" % PREFERRED_ID)
	check_eq(_equipped(save), PREFERRED_ID, "前置：equipped==%s" % PREFERRED_ID)

	var container: Control = Control.new()
	container.size = Vector2(1152, 648)
	add_child(container)
	game.attach(container, null)
	game.goto_state(ST_MAIN_MENU)
	await process_frame

	# ==================== 1. TALK（关前对话，chapter=2）：强制时代立绘 + 不动 preferred ====================
	game.goto_state(ST_TALK, {"mode": "after_level", "chapter": 2})
	await process_frame
	check_eq(int(game.current_state()), ST_TALK, "1：进入 TALK(chapter=2)")
	check(_equipped(save) == CH2_ORIGIN,
		"1：TALK 强制穿戴第 2 关时代立绘 %s（实测 %s；红：守卫删除则仍为自选）" % [CH2_ORIGIN, _equipped(save)])
	check_eq(_preferred(save), PREFERRED_ID, "1：强制穿戴不动 preferred（仍=%s）" % PREFERRED_ID)
	check((save.get_skins()["owned"] as Array).has(CH2_ORIGIN),
		"1：进 TALK 先解锁该章原创（点位① 幂等；%s ∈ owned）" % CH2_ORIGIN)

	# ==================== 2. LEVEL（chapter=2）：同样强制 ====================
	game.goto_state(ST_LEVEL, {"chapter": 2})
	await process_frame
	check_eq(int(game.current_state()), ST_LEVEL, "2：进入 LEVEL(chapter=2)")
	check(_equipped(save) == CH2_ORIGIN,
		"2：LEVEL 强制穿戴时代立绘（实测 %s）" % _equipped(save))
	check_eq(_preferred(save), PREFERRED_ID, "2：LEVEL 不动 preferred")

	# ==================== 3. MAIN_MENU：还原 preferred ====================
	game.goto_state(ST_MAIN_MENU)
	await process_frame
	check(_equipped(save) == PREFERRED_ID,
		"3：出到 MAIN_MENU 还原玩家自选（实测 %s；红：守卫删除则卡在时代立绘）" % _equipped(save))
	check_eq(_preferred(save), PREFERRED_ID, "3：还原不改 preferred")

	# ==================== 4. TALK→CATALOG：强制→还原 ====================
	game.goto_state(ST_TALK, {"mode": "after_level", "chapter": 2})
	await process_frame
	check(_equipped(save) == CH2_ORIGIN, "4：再进 TALK 再强制（实测 %s）" % _equipped(save))
	game.goto_state(ST_CATALOG)
	await process_frame
	check_eq(int(game.current_state()), ST_CATALOG, "4：进入 CATALOG")
	check(_equipped(save) == PREFERRED_ID,
		"4：出到 CATALOG 还原玩家自选（实测 %s）" % _equipped(save))

	# ==================== 5. TALK→SETTLE：强制→还原 ====================
	game.goto_state(ST_TALK, {"mode": "after_level", "chapter": 2})
	await process_frame
	check(_equipped(save) == CH2_ORIGIN, "5：进 TALK 强制（实测 %s）" % _equipped(save))
	game.goto_state(ST_SETTLE, {"chapter": 2, "grade": "良好", "elapsed": 61, "talent": 80, "replay": false})
	await process_frame
	await process_frame
	check_eq(int(game.current_state()), ST_SETTLE, "5：进入 SETTLE（边缘路径 level 重建）")
	check(_equipped(save) == PREFERRED_ID,
		"5：出到 SETTLE 还原玩家自选（实测 %s）" % _equipped(save))

	# ==================== 6. 第 1 关章位抽查（TALK ch1 → 开头原创；MAIN_MENU 还原） ====================
	game.goto_state(ST_TALK, {"mode": "after_level", "chapter": 1})
	await process_frame
	check(_equipped(save) == CH1_ORIGIN,
		"6：TALK(chapter=1) 强制开头原创（实测 %s）" % _equipped(save))
	game.goto_state(ST_MAIN_MENU)
	await process_frame
	check(_equipped(save) == PREFERRED_ID, "6：MAIN_MENU 还原自选（实测 %s）" % _equipped(save))

	# ==================== 7. 源级接线锁：goto_state 内 TALK/LEVEL 强制 + 三态还原分支在位 ====================
	var gsrc: String = FileAccess.get_file_as_string("res://autoload/game.gd")
	check(gsrc.contains("apply_contextual_skin"), "7：game.gd 含 apply_contextual_skin 调用（TALK/LEVEL 强制接线）")
	check(gsrc.contains("restore_preferred_skin"), "7：game.gd 含 restore_preferred_skin 调用（三态还原接线）")

	await process_frame
	finish()
