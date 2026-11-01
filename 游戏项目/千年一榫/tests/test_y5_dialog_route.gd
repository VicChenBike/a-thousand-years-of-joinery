extends "res://tests/test_base.gd"
## 批次 Y（Y-C6 补充，用户 2026-09-23 拍板）：对话挂载点对齐——
##   批次 Z §14 增补（用户 2026-09-24 拍板）：开场对话删除 → 开场动画（含跳过）直接挂
##   第 1 关关前对话语境（after_level, chapter=1，链路零 opening 段）→ 第1关.json 播完 → 进入第 1 关；
##   通关第 N 关 → 播第 N+1 关对话（第N+1关.json）→ 进入第 N+1 关。
## 现状（Y4 5b5c7eb）：after_level(n)=「通关第 n 关后播第 n 关对话→进 n+1」——与用户定义相反，
## 红测锁定新映射后实施：挂载点章节号整体前移一位（结算→下一章对话→下一关 分流骨架沿用）。
## 清档纪律：goto_state 触发 K-D 自动穿戴写档，先备份后还原。

const TALK_SCENE := "res://scenes/dialog/talk_scene.tscn"
const LEVEL_SCENE := "res://scenes/level/level_scene.tscn"
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_r_y5dlg_backup_"
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
	print("EVID|user_restore|y5dlg|files=%d" % DISC_WATCHED.size())

func _make_talk(ctx: Dictionary) -> Node:
	var t: Node = (load(TALK_SCENE) as PackedScene).instantiate()
	t.call("set_context", ctx)
	add_child(t)
	await process_frame
	await process_frame
	return t

func _initialize() -> void:
	print("== test_y5_dialog_route ==")
	_backup_user()
	var game: Node = root.get_node("Game")
	var lib: Node = root.get_node("LevelLibrary")
	lib.call("scan_directory")

	# ==================== 1. 开场链（§14①）：开场动画点跳过 → TALK(after_level,1) → 播完进第 1 关 ====================
	var movie: Node = (load("res://scenes/movie/opening_movie.tscn") as PackedScene).instantiate()
	add_child(movie)
	await process_frame
	var skip_btn: Button = movie.get_node_or_null("SkipButton") as Button
	check(skip_btn != null, "开场链前置：opening_movie SkipButton 在位")
	if skip_btn != null:
		skip_btn.pressed.emit()
	check_eq(int(game.current_state()), int(game.State.TALK),
		"开场链（§14①）：开场动画点跳过 → TALK 对话（非直进关卡）")
	check_eq(String(game.context().get("mode", "")), "after_level",
		"开场链（§14①）：挂载语境=after_level（opening 段退役；红：现状 opening）")
	check_eq(int(game.context().get("chapter", 0)), 1, "开场链（§14①）：第 1 关对话（chapter=1）")
	var t_open: Node = await _make_talk(game.context())
	var open_lines: Variant = t_open.get("_lines")
	check(open_lines is Array and (open_lines as Array).size() == 51,
		"开场链（§14⑤）：直挂 第1关.json 51 句（实测 %s）" % str((open_lines as Array).size() if open_lines is Array else "null"))
	if open_lines is Array and (open_lines as Array).size() > 0:
		check_eq(String((open_lines[0] as Dictionary).get("text", "")), "等——这是哪儿？刚才还站着，一眨眼，满天是光。",
			"开场链（§14③）：对话首句逐字=用户正式文案第 1 句")
	t_open.call("_finish")
	check_eq(int(game.current_state()), int(game.State.LEVEL),
		"开场链（§14①）：after_level(1) 对话播完 → 进入第 1 关（LEVEL）")
	check_eq(int(game.context().get("chapter", 0)), 1, "开场链（§14①）：进入 chapter=1")
	movie.queue_free()
	t_open.free()
	await process_frame

	# ==================== 2. 第 N 关对话播完 → 进入第 N 关 ====================
	var t2: Node = await _make_talk({"mode": "after_level", "chapter": 2})
	t2.call("_finish")
	check_eq(int(game.current_state()), int(game.State.LEVEL), "第 2 关对话播完 → LEVEL（进第 2 关）")
	check_eq(int(game.context().get("chapter", 0)), 2,
		"第 2 关对话播完 → 进入第 2 关（红：现状进 chapter=3）")
	t2.free()
	await process_frame

	# ==================== 3. 结算「下一关」挂载：通关第 N 关 → 播第 N+1 关对话 ====================
	var lvl1: Node = (load(LEVEL_SCENE) as PackedScene).instantiate()
	lvl1.call("set_context", {"chapter": 1})
	add_child(lvl1)
	await process_frame
	await process_frame
	lvl1.set("_settled", true)
	lvl1.call("_on_settle_next_pressed")
	check_eq(int(game.current_state()), int(game.State.TALK), "通关第 1 关 → 下一关分流=TALK（骨架沿用）")
	check_eq(int(game.context().get("chapter", 0)), 2,
		"通关第 1 关 → 播第 2 关对话（挂载 chapter=N+1，红：现状=N）")
	check_eq(String(game.context().get("mode", "")), "after_level", "通关挂载语境=after_level")
	lvl1.free()
	await process_frame

	# ==================== 4. 对话背景/立绘章位（新映射下=即将进入的关卡） ====================
	var t3: Node = await _make_talk({"mode": "after_level", "chapter": 2})
	var bg: TextureRect = t3.get_node_or_null("Background")
	check(bg != null and bg.texture != null
		and String(bg.texture.resource_path).ends_with("bg_chapter2.png"),
		"背景章位：第 2 关对话背景=bg_chapter2（即将进入的关；红：现状 bg_chapter3）")
	var pp: String = String(t3.get("portrait_path"))
	check(pp.contains("宋"), "立绘章位：第 2 关对话立绘=宋时代（即将进入的关，实测 %s）" % pp)
	t3.free()
	await process_frame

	# ==================== 5. 链路完备性（Y-C5 前提：第 2~5 关数据已入库） ====================
	for ch: int in [2, 3, 4, 5]:
		check(not (lib.call("get_level", ch) as Dictionary).is_empty(),
			"链路完备：第 %d 关关卡数据在库（通关第 %d 关可播第 %d 关对话并进关）" % [ch, ch - 1, ch])
	check(FileAccess.file_exists("res://剧情对话/第2关.json")
		and FileAccess.file_exists("res://剧情对话/第5关.json"),
		"链路完备：剧情对话 第2~5关.json 在库（Y4 域交付，只读）")

	# ==================== 6. 既有契约回归（批次 P3 catalog_return 透传不受映射影响） ====================
	game.goto_state(int(game.State.TALK), {"mode": "after_level", "chapter": 3})
	game.goto_state(int(game.State.CATALOG))
	check_eq(int(game.get("catalog_return")["state"]), int(game.State.TALK),
		"回归：进图鉴快照 TALK 来源（O5 既有契约）")
	game.goto_state(int(game.State.TALK), game.get("catalog_return")["ctx"])
	check_eq(String(game.context().get("mode", "")), "after_level", "回归：图鉴回 TALK ctx 透传 mode（P3 契约）")
	check_eq(int(game.context().get("chapter", 0)), 3, "回归：图鉴回 TALK ctx 透传 chapter（P3 契约）")

	_restore_user()
	finish()
