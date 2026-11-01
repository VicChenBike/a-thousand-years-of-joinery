extends "res://tests/test_base.gd"
## N10（批次 N，2026-09-09 用户五条实测路径）图鉴门控修复判定用例（TDD 红灯先行）。
## 根因（调研实锤）：图鉴门控唯一判据原为 settings_panel._refresh_catalog_entry 的
## SaveManager.is_first_launch()（易失旁路 flag 文件），与 save.json 真实进度零耦合——
## 开发工具清 flag 后「玩完退出主菜单 / 通关后回主菜单 / 结算页」均被误判禁用。
## 契约（plan N10）：
##   ①save_manager 新增纯查询 can_open_catalog()：flag 存在 OR progress.watched_opening
##     OR progress.cleared 非空，三分支任一即可开（新档三者全空仍禁用=用户认可路径1）；
##   ②save_manager 新增 mark_opening_watched()：置位 watched_opening 并自动保存（幂等）；
##     watched_opening 缺省迁移；N9 后 SAVE_VERSION=2，本文件夹具仍以 v1 档验证向后兼容（load 接受、功能无损）；默认档/watched 默认 false，
##     reset_for_new_game 清档回 false（清档重走开场，门控同步关回）；
##   ③settings_panel._refresh_catalog_entry 改用 can_open_catalog()（disabled=!can_open_catalog()）；
##   ④opening_movie._finish 首次路径（非回看）置位 mark_opening_watched——播完/跳过/资源缺失
##     兜底三条退出路径同经 _finish；回看模式（replay_video=true，图鉴进入）不置位。
## 用户五路径等价断言映射：
##   路径1 新档未看动画：flag 无+watched false+cleared 空 → 门控关（面板 disabled）；
##   路径2 关卡内（主菜单点开始写过 flag）：仅 flag → 可开；
##   路径3 玩完退出主菜单（工具误清 flag，看过动画）：仅 watched_opening → 可开；
##   路径4 通关后回主菜单（flag/watched 均失）：仅 cleared 非空 → 可开；
##   路径5 结算页设置面板：门控为纯存档查询、与 Game 状态无关（SETTLE/MAIN_MENU 态同判据）→ 可开。
## 环境说明：--script 模式 7 autoload 在 /root/<Name>（P2-5 动态引用）；枚举 SETTLE=5/CATALOG=6；
##   本测试自防护：起测前备份 user:// 真实档案、终测还原（tools/README_走查清档规范.md 同规）。

const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const BK_SAVE := "user://_n10_backup_save.json"
const BK_FLAG := "user://_n10_backup_flag.flag"
const PANEL_PATH := "res://scenes/settings/settings_panel.tscn"
const MOVIE_PATH := "res://scenes/movie/opening_movie.tscn"
const ST_SETTLE := 5
const ST_CATALOG := 6
const ST_TALK := 3

func _del(p: String) -> void:
	var abs: String = ProjectSettings.globalize_path(p)
	if FileAccess.file_exists(abs):
		DirAccess.remove_absolute(abs)

func _backup_user() -> void:
	# 起测前备份真实档案（本测试会大量写档/删档，规范同 tools/README_走查清档规范.md）
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(BK_SAVE))
	if FileAccess.file_exists(FLAG_PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(FLAG_PATH), ProjectSettings.globalize_path(BK_FLAG))

func _restore_user() -> void:
	# 还原真实档案（备份不存在=起测前本就无档 → 删除测试残留恢复原状）；再 load_game 重同步内存
	for pair: Array in [[BK_SAVE, SAVE_PATH], [BK_FLAG, FLAG_PATH]]:
		_del(String(pair[1]))
		if FileAccess.file_exists(String(pair[0])):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(String(pair[0])), ProjectSettings.globalize_path(String(pair[1])))
		_del(String(pair[0]))
	var sm: Node = get_root().get_node_or_null("SaveManager")
	if sm != null:
		sm.load_game()

func _legacy_json(watched: Variant, cleared: Array) -> String:
	# 旧档夹具（K-D 迁移测试同款基座）：watched=null 表示旧档无该字段（缺省迁移场景）
	var d: Dictionary = {
		"save_version": 1,
		"progress": {"cleared": cleared, "next_chapter": 2},
		"settings": {"gesture_input": true, "kb_input": true, "gesture_hud_visible": true, "gesture_hud_offset": [0, 0], "volume": {"master": 1.0, "music": 1.0, "sfx": 1.0}, "udp_port": 0},
		"talent": 320,
		"skins": {"owned": ["skin_default", "skin_07"], "equipped": "skin_07"},
		"replay_award_counts": {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0},
	}
	if watched != null:
		(d["progress"] as Dictionary)["watched_opening"] = watched
	return JSON.stringify(d)

func _fresh_save(save: Variant) -> void:
	# 回到「新档」基线：删两文件 + 内存重读默认
	_del(SAVE_PATH)
	_del(FLAG_PATH)
	save.load_game()

func _open_panel(game: Variant, overlay: CanvasLayer) -> Node:
	game.open_overlay("settings")
	await process_frame
	if overlay.get_child_count() == 0:
		return null
	return overlay.get_child(overlay.get_child_count() - 1)

func _red_placeholders(n: int) -> void:
	for i: int in range(n):
		check(false, "红灯占位 %d：can_open_catalog/mark_opening_watched/watched_opening 未实现" % (i + 1))

func _initialize() -> void:
	print("== test_n10_catalog_gate ==")
	var save: Variant = get_root().get_node("SaveManager")
	var game: Variant = get_root().get_node("Game")
	_backup_user()

	# ================= A 组：SaveManager 门控判据（判据层，五路径等价断言之基座） =================
	check(save.has_method("can_open_catalog"), "N10：SaveManager.can_open_catalog 纯查询 API 存在")
	check(save.has_method("mark_opening_watched"), "N10：SaveManager.mark_opening_watched 置位 API 存在")
	if not (save.has_method("can_open_catalog") and save.has_method("mark_opening_watched")):
		_red_placeholders(33)
		_restore_user()
		finish()
		return

	# ---- A1 路径1：新档（flag 无 + watched false + cleared 空）→ 门控关 ----
	_fresh_save(save)
	check(not bool(save.can_open_catalog()), "路径1：新档三分支全空 → 门控关")
	var p0: Dictionary = save.get_progress()
	check(p0.has("watched_opening") and not bool(p0["watched_opening"]), "默认档 progress.watched_opening 字段存在且 false（缺省即迁移）")

	# ---- A2 分支①仅 flag（路径2 关卡内：主菜单点开始游戏写过 flag）----
	save.mark_first_launch()
	check(bool(save.can_open_catalog()), "分支①：仅 flag 存在 → 可开（路径2）")
	_del(FLAG_PATH)
	check(not bool(save.can_open_catalog()), "分支①：flag 删除后回落关（三分支相互独立）")

	# ---- A3 分支②仅 watched（路径3 玩完退出主菜单：工具误清 flag 后看过动画仍可开）----
	save.mark_opening_watched()
	check(bool(save.can_open_catalog()), "分支②：仅 watched_opening=true → 可开（路径3）")
	check(bool(save.get_progress()["watched_opening"]), "mark_opening_watched 置位 progress.watched_opening")
	check(FileAccess.file_exists(SAVE_PATH), "mark_opening_watched 自动保存（save.json 落盘）")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	check(typeof(parsed) == TYPE_DICTIONARY and bool(parsed["progress"]["watched_opening"]),
		"落盘 JSON progress.watched_opening==true（断电级持久化）")
	save.mark_opening_watched()
	check(bool(save.get_progress()["watched_opening"]), "mark_opening_watched 幂等（重复调用保持 true）")

	# ---- A4 重载持久化（模拟重启；flag 已删、仅 watched 支撑门控）----
	_del(FLAG_PATH)
	var sm2: Node = load("res://autoload/save_manager.gd").new()
	add_child(sm2)
	sm2.name = "N10SMReload"
	sm2.load_game()
	check(bool(sm2.get_progress()["watched_opening"]), "重载后 watched_opening 保持 true（持久化）")
	check(bool(sm2.can_open_catalog()), "重载后门控仍开（flag 无、仅 watched 兜底——工具清 flag 不再丢图鉴）")
	sm2.queue_free()

	# ---- A5 分支③仅 cleared（路径4 通关后：flag/watched 均失仍可开）+ reset 清档语义 ----
	save.load_game()  # 内存回同步（watched=true 态）
	save.reset_for_new_game()  # 清档：默认档（watched 回 false）+ 删 flag + 落盘
	check(not bool(save.get_progress()["watched_opening"]), "reset_for_new_game 后 watched_opening 回 false（清档重走开场）")
	check(not bool(save.can_open_catalog()), "reset_for_new_game 后门控关回（新档语义，与路径1 等价）")
	save.advance_progress(1)  # 通关写点（level_scene._goto_settle 同款）：不写 flag、不置 watched
	check(bool(save.can_open_catalog()), "分支③：cleared=[1] 非空 → 可开（路径4）")
	check(not bool(save.get_progress()["watched_opening"]), "分支③独立性：watched 仍 false、纯通关记录支撑门控")

	# ---- A6 旧档缺字段迁移（save_version=1 不动，preferred 先例）----
	var lf: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	lf.store_string(_legacy_json(null, [2]))  # 旧档：无 watched 字段、有通关记录
	lf.close()
	var sm3: Node = load("res://autoload/save_manager.gd").new()
	add_child(sm3)
	sm3.name = "N10SMLegacyA"
	sm3.load_game()
	check(not bool(sm3.get_progress()["watched_opening"]), "旧档迁移 a：无 watched 字段 → 缺省迁移 false（不误开）")
	check(bool(sm3.can_open_catalog()), "旧档迁移 a：cleared 非空 → 门控开（通关旧档不再误判禁用）")
	sm3.queue_free()
	lf = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	lf.store_string(_legacy_json(true, []))  # 旧档：显式 watched=true、无通关
	lf.close()
	var sm4: Node = load("res://autoload/save_manager.gd").new()
	add_child(sm4)
	sm4.name = "N10SMLegacyB"
	sm4.load_game()
	check(bool(sm4.get_progress()["watched_opening"]), "旧档迁移 b：显式 watched=true 无损保留")
	check(bool(sm4.can_open_catalog()), "旧档迁移 b：watched=true → 门控开")
	sm4.queue_free()
	_fresh_save(save)

	# ================= B 组：设置面板联动（用户路径面板层） =================
	var container: Control = Control.new()
	add_child(container)
	var overlay: CanvasLayer = CanvasLayer.new()
	add_child(overlay)
	game.attach(container, overlay)
	await process_frame
	check(ResourceLoader.exists(PANEL_PATH), "前置：settings_panel.tscn 存在")
	if not ResourceLoader.exists(PANEL_PATH):
		_restore_user()
		finish()
		return

	# ---- B1 路径1 面板：新档 → disabled + 禁止光标 ----
	var panel: Node = await _open_panel(game, overlay)
	check(panel != null, "前置：新档态可打开设置覆盖层")
	if panel != null:
		var ce: Button = panel.get_node_or_null("Panel/VBox/EntryBox/CatalogEntry") as Button
		check(ce != null and ce.disabled and int(ce.mouse_default_cursor_shape) == int(Control.CURSOR_FORBIDDEN),
			"路径1 面板：新档 → 图鉴入口 disabled+禁止光标")
	# ---- B2 路径3 面板：仅 watched（flag 无）→ enabled + 手型光标 ----
	if panel != null:
		save.mark_opening_watched()
		panel.call("_refresh_catalog_entry")
		var ce2: Button = panel.get_node_or_null("Panel/VBox/EntryBox/CatalogEntry") as Button
		check(ce2 != null and not ce2.disabled and int(ce2.mouse_default_cursor_shape) == int(Control.CURSOR_POINTING_HAND),
			"路径3 面板：仅 watched_opening（flag 无）→ enabled+手型（主菜单/结算页同面板即开）")
		game.close_overlay()
		await process_frame

	# ---- B3/B4 路径4+5 面板：仅 cleared + 状态无关性（SETTLE→MAIN_MENU 两态同判据）----
	save.reset_for_new_game()
	save.advance_progress(2)  # 构造纯通关态：flag 无、watched false、cleared=[2]
	check(not FileAccess.file_exists(FLAG_PATH) and not bool(save.get_progress()["watched_opening"]),
		"路径4 前置：纯通关态构造成功（flag 无+watched false）")
	game.goto_state(ST_SETTLE, {"chapter": 2, "grade": "良好", "elapsed": 61, "talent": 80, "replay": false})
	var panel_s: Node = await _open_panel(game, overlay)
	check(panel_s != null, "路径5：结算态可打开设置覆盖层（GlobalUI 常驻入口）")
	if panel_s != null:
		var ce3: Button = panel_s.get_node_or_null("Panel/VBox/EntryBox/CatalogEntry") as Button
		check(ce3 != null and not ce3.disabled, "路径5 面板：结算态 + 仅 cleared → enabled（门控与状态无关）")
	game.close_overlay()
	await process_frame
	game.goto_state(1, {})  # MAIN_MENU：通关后回主菜单（用户路径4 状态）
	var panel_m: Node = await _open_panel(game, overlay)
	if panel_m != null:
		var ce4: Button = panel_m.get_node_or_null("Panel/VBox/EntryBox/CatalogEntry") as Button
		check(ce4 != null and not ce4.disabled and int(ce4.mouse_default_cursor_shape) == int(Control.CURSOR_POINTING_HAND),
			"路径4 面板：通关后回主菜单 → enabled+手型（原 BUG 场景修复）")
	# ---- B5 复位防回归：清档回新档 → disabled ----
	if panel_m != null:
		save.reset_for_new_game()
		panel_m.call("_refresh_catalog_entry")
		var ce5: Button = panel_m.get_node_or_null("Panel/VBox/EntryBox/CatalogEntry") as Button
		check(ce5 != null and ce5.disabled, "B5：清档回新档 → disabled（门控可关回）")
	game.close_overlay()
	await process_frame

	# ================= C 组：opening_movie 写点实链（路径3 数据来源） =================
	_fresh_save(save)
	check(ResourceLoader.exists(MOVIE_PATH), "前置：opening_movie.tscn 存在")
	if ResourceLoader.exists(MOVIE_PATH):
		# C1 回看模式不置位：replay_video=true → 跳过路由 CATALOG 且 watched 保持 false
		var mv1: Node = load(MOVIE_PATH).instantiate()
		mv1.call("set_context", {"replay_video": true})
		container.add_child(mv1)
		await process_frame
		var skip1: Button = mv1.get_node_or_null("SkipButton") as Button
		check(skip1 != null, "前置：回看实例 SkipButton 存在")
		if skip1 != null:
			skip1.pressed.emit()
			check(int(game.current_state()) == ST_CATALOG and not bool(save.get_progress()["watched_opening"]),
				"C1：回看模式跳过 → 路由 CATALOG 且 watched_opening 不置位（回看不当作首看）")
		# C2 首次模式跳过置位：新实例无 context → 跳过路由 TALK 且 watched 置 true（自动落盘）
		var mv2: Node = load(MOVIE_PATH).instantiate()
		container.add_child(mv2)
		await process_frame
		var skip2: Button = mv2.get_node_or_null("SkipButton") as Button
		if skip2 != null:
			skip2.pressed.emit()
			check(int(game.current_state()) == ST_TALK and bool(save.get_progress()["watched_opening"]),
				"C2：首次模式跳过 → 路由 TALK 且 watched_opening 置 true（写点实链）")
		# C3 三条退出路径汇聚 _finish（源码留痕：播完信号/跳过/资源缺失兜底同经 _finish 置位）
		var src: String = FileAccess.get_file_as_string("res://scenes/movie/opening_movie.gd")
		check(src.find("player.finished.connect(_finish)") >= 0, "C3：播完路径汇聚 _finish（源码）")
		check(src.find("_finish()") >= 0 and src.find("SaveManager.mark_opening_watched()") >= 0,
			"C3：_finish 内首次路径置位 mark_opening_watched（跳过/资源缺失兜底同经此点）")
		check(src.find("if not _replay:") >= 0 and src.find("SaveManager.mark_opening_watched()") < src.find("Game.goto_state(Game.State.CATALOG"),
			"C3：置位受 if not _replay 守卫且先于路由（回看模式不置位）")

	# ================= 收尾：清残留 + 还原真实档案 =================
	game.close_overlay()
	await process_frame
	_restore_user()
	finish()
