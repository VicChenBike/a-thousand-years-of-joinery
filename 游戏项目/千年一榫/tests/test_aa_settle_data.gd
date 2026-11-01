extends "res://tests/test_base.gd"
## 批次 AA / 域 W6（结算数据在边缘路径丢失）判定用例（TDD 红灯先行，2026-09-25）。
## 契约来源：规格 §9.3~§9.5 + 主任务书 W6-1~W6-5：
##   R6-a 主红：生产链路 `_goto_settle` 记账 → 绕行 CATALOG → 图鉴退出回 SETTLE，
##       三个 Label（评分/耗时/获得天赋值）**非「——」**且与快照值一致
##       （现状红 = _settle_data 只落场景局部，图鉴快照 ctx 无 grade/elapsed/talent → 全显「——」）；
##   R6-b 断链留痕：人为清空 settle_snapshot 且 ctx 无结算字段 → 三 Label「——」**且**产生
##       push_warning 留痕（判据=告警文本含约定标记 SETTLE_DATA_BREAK；现状静默降级零留痕=红）；
##   R6-c 恰一次：_settled 守卫下重复 _goto_settle 不改写快照、不重复发奖推进；
##   R6-d 生命周期：进入 MAIN_MENU / TALK（新游戏链路同构）清空 settle_snapshot（零残留）；
##       进入 CATALOG 保留（绕行通道，否则边缘路径必断链）；
##   §8.4 入栈合并：SETTLE 来源入栈快照 ctx 必须携带结算字段（图鉴快照不丢链）。
## 数据来源纪律（W6-4 同规）：断言值一律取**生产真实链路产出**（_goto_settle 写入的
##   Game.settle_snapshot / level._settle_data），禁止手工伪造 {grade,elapsed,talent} ctx
##   （test_p_settle 旧 305 手工 ctx 曾掩盖断链，本件立项即为堵该洞）。
## 坑纪律：红期字段/成员可能不存在 → `"x" in obj` / obj.get(key)
##   防御访问（4.7 实测安全返回 false/null 不中止 _initialize）；无头夹具 goto_state/场景
##   实例化后 await process_frame；_enter_settle_direct 内部 await 一帧 → 用 0.5s 定时器兜底。

const LS_SCRIPT := "res://scenes/level/level_scene.gd"
const GAME_GD := "res://autoload/game.gd"
const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"
const BK_PREFIX := "user://_aa_settle_backup_"
## 清档观察组 = 规范四件组（tools/README_走查清档规范.md 六条，test_catalog_scene 同构）：
## save.json / first_launch.flag / save.json.tmp / save.json.bak 逐件备份→终测逐件还原。
const WATCHED: Array = [SAVE_PATH, FLAG_PATH, TMP_PATH, BAK_PATH]

const ST_MAIN_MENU := 1
const ST_TALK := 3
const ST_LEVEL := 4
const ST_SETTLE := 5
const ST_CATALOG := 6

const BREAK_MARKER := "SETTLE_DATA_BREAK"

var game: Variant
var save: Variant
var lib: Variant
var container: Control
var ls_s: Script

func _backup_user() -> void:
	# 四件组逐件备份（起测前不存在的件不落备份 → 还原时自然回到「不存在」态=逐字节等价）。
	for p: String in WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(ProjectSettings.globalize_path(p), ProjectSettings.globalize_path(bk))

func _restore_user() -> void:
	# 四件组逐件还原：先删测试期产物，再把「起测前存在」的备份回拷并清备份（无备份=保持不存在）。
	for p: String in WATCHED:
		var abs_p: String = ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs_p):
			DirAccess.remove_absolute(abs_p)
		var bk: String = BK_PREFIX + p.get_file()
		var abs_bk: String = ProjectSettings.globalize_path(bk)
		if FileAccess.file_exists(abs_bk):
			DirAccess.copy_absolute(abs_bk, abs_p)
			DirAccess.remove_absolute(abs_bk)
	if save != null:
		save.load_game()

func _reset_save() -> void:
	# 清档前奏（test_p_settle 同款 + tmp/bak 一并清）：四件组全清 → 内存重读默认档
	#（防残留 .bak 在主档缺失时被 load_game 回退复活，破坏「fresh save」前置）。
	for p: String in WATCHED:
		var abs_p: String = ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs_p):
			DirAccess.remove_absolute(abs_p)
	save.load_game()

func _snapshot() -> Dictionary:
	if "settle_snapshot" in game:
		var v: Variant = game.get("settle_snapshot")
		if v is Dictionary:
			return v
	return {}

func _target_cells() -> Array:
	var lvl: Dictionary = lib.get_level(1)
	if lvl.is_empty():
		return []
	var pieces: Array = (lvl["data"] as Dictionary)["pieces"]
	return (pieces[0] as Dictionary)["target_shapes"][0]

func _make_level_routed(ch: int) -> Node:
	game.goto_state(ST_LEVEL, {"chapter": ch})
	for _i: int in 3:
		await process_frame
	return game.get_current_scene()

func _exit_catalog() -> void:
	var panel: Node = container.get_child(container.get_child_count() - 1)
	(panel.get_node("BottomBar/ExitButton") as Button).pressed.emit()
	await process_frame
	await process_frame

func _labels(edge: Node) -> Array:
	# 逐节点判空（红期边缘实例可能处于游玩态——SettleUI/子标签未建，禁 null.text 直取中止）
	var ui: Control = edge.get_node_or_null("SuccessOverlay/SettleUI")
	if ui == null:
		return ["", "", ""]
	var out: Array = []
	for n: String in ["GradeLabel", "ElapsedLabel", "TalentLabel"]:
		var lb: Label = ui.get_node_or_null(n) as Label
		out.append(String(lb.text) if lb != null else "")
	return out

func _initialize() -> void:
	print("== test_aa_settle_data ==")
	_backup_user()
	game = get_root().get_node("Game")
	save = get_root().get_node("SaveManager")
	lib = get_root().get_node("LevelLibrary")
	ls_s = load(LS_SCRIPT)
	save.load_game()
	lib.scan_directory("res://levels_data")
	container = Control.new()
	add_child(container)
	var overlay: CanvasLayer = CanvasLayer.new()
	add_child(overlay)
	game.attach(container, overlay)
	var gsrc: String = FileAccess.get_file_as_string(GAME_GD)
	var lsrc: String = FileAccess.get_file_as_string(LS_SCRIPT)

	# ==================== S1. 生产链路记账：_goto_settle → Game.settle_snapshot ====================
	print("-- S1 生产记账 --")
	check("settle_snapshot" in game and game.get("settle_snapshot") is Dictionary,
		"W6-1：Game.settle_snapshot 结算快照字段存在（Dictionary）")
	check(gsrc.contains("settle_snapshot"), "W6-1：game.gd 含 settle_snapshot 留痕")
	_reset_save()
	var talent0: int = int(save.get_talent())
	var target: Array = _target_cells()
	check(not target.is_empty(), "前置：第 1 关 target 就绪")
	if target.is_empty():
		_restore_user()
		finish()
		return
	var lvl: Node = await _make_level_routed(1)
	check(lvl != null, "前置：经 Game 路由的 level 实例就绪")
	if lvl == null:
		_restore_user()
		finish()
		return
	var jb: Button = lvl.get_node_or_null("TopBar/Buttons/JoinButton")
	lvl.set("anim_time_scale", 8.0)
	lvl.call("set_remaining_for_test", target)
	jb.pressed.emit()
	lvl.call("_skip_success_animation")
	await process_frame
	check_eq(int(game.current_state()), ST_SETTLE, "前置：完成第 1 关 → 记账 SETTLE（主路径）")
	var snap: Dictionary = _snapshot()
	check(not snap.is_empty(),
		"W6-1：_goto_settle 把结算快照写入 Game.settle_snapshot（红期字段缺席/未记账=红）")
	check_eq(String(snap.get("grade", "")), "完美",
		"W6-1：快照 grade=完美（生产产出：第 1 关秒完 ≤3min 档）")
	check(snap.has("chapter") and snap.has("grade") and snap.has("score")
		and snap.has("elapsed") and snap.has("talent") and snap.has("replay"),
		"W6-1：快照字段齐套 {chapter,grade,score,elapsed,talent,replay}（规格 §9.3 W6-1 契约）")
	check_eq(int(snap.get("talent", -1)), 100, "W6-1：快照 talent=100（第 1 关首通完美档）")
	check_eq(int(save.get_talent()), talent0 + 100, "R6-c：天赋值恰发放一次（首通 +100）")

	# ---- R6-c：_settled 守卫下重复记账不改写快照、不重复推进 ----
	var snap_before: Dictionary = snap.duplicate(true)
	lvl.call("_goto_settle")          # 重复记账尝试（_settled 守卫）
	lvl.call("_skip_success_animation")
	check(_snapshot() == snap_before,
		"R6-c：重复 _goto_settle 不改写 settle_snapshot（_settled 恰一次守卫）")
	check_eq(int(save.get_talent()), talent0 + 100, "R6-c：重复调用不再发奖（恰一次）")

	# ==================== S2. 主路径直显三 Label（护栏：数据面=快照面同源） ====================
	print("-- S2 主路径标签 --")
	var sdata: Dictionary = lvl.get("_settle_data") if lvl.get("_settle_data") is Dictionary else {}
	var fmt_elapsed: String = String(ls_s.call("format_time", float(sdata.get("elapsed", 0.0))))
	var labs: Array = _labels(lvl)
	check(not String(labs[0]).contains("——") and String(labs[0]).contains(String(sdata.get("grade", ""))),
		"护栏：主路径评分 Label=真实评级（非「——」）")
	check(not String(labs[1]).contains("——") and String(labs[1]).contains(fmt_elapsed),
		"护栏：主路径耗时 Label=format_time(_settle_data.elapsed)（非「——」）")
	check(not String(labs[2]).contains("——") and String(labs[2]).contains(str(int(sdata.get("talent", -1)))),
		"护栏：主路径天赋值 Label=真实值（非「——」）")

	# ==================== S3. 绕行 CATALOG → 回 SETTLE（R6-a 主红） ====================
	print("-- S3 绕行回结算 --")
	var cleared0: Array = (save.get_progress()["cleared"] as Array).duplicate()
	var talent_rt: int = int(save.get_talent())
	game.goto_state(ST_CATALOG)
	await process_frame
	await process_frame
	check(not _snapshot().is_empty(),
		"W6-5：进入 CATALOG 保留 settle_snapshot（绕行通道；清空=边缘路径必断链）")
	var ret: Variant = game.get("catalog_return")
	var ret_d: Dictionary = ret if ret is Dictionary else {}
	check_eq(int(ret_d.get("state", -1)), ST_SETTLE, "前置：SETTLE 来源入栈（栈顶镜像）")
	var ret_ctx: Dictionary = ret_d.get("ctx", {}) if ret_d.get("ctx", {}) is Dictionary else {}
	check(ret_ctx.has("grade") and ret_ctx.has("elapsed") and ret_ctx.has("talent"),
		"§8.4/W6-1：入栈快照 ctx 合并结算字段 grade/elapsed/talent（图鉴快照不丢链；旧 ctx 仅 chapter=红）")
	await _exit_catalog()
	await create_timer(0.5).timeout   # _enter_settle_direct 内部 await 一帧的兜底窗
	var edge: Node = game.get_current_scene()
	check_eq(int(game.current_state()), ST_SETTLE, "前置：图鉴退出透传回 SETTLE")
	check(edge != null and edge.get_script() == ls_s and bool(edge.get("_settle_mode")),
		"前置：边缘路径重建 level 直显结算（_settle_mode 置位）")
	var snap2: Dictionary = _snapshot()
	var labs2: Array = _labels(edge) if edge != null else ["", "", ""]
	check(not String(labs2[0]).contains("——") and snap2.has("grade")
		and String(labs2[0]).contains(String(snap2.get("grade", ""))),
		"R6-a：绕行回结算·评分非「——」且=快照评级（现状红=「评分：——」/快照缺席）")
	check(not String(labs2[1]).contains("——") and snap2.has("elapsed")
		and String(labs2[1]).contains(String(ls_s.call("format_time", float(snap2.get("elapsed", 0.0))))),
		"R6-a：绕行回结算·耗时非「——」且=format_time(快照 elapsed)（现状红=「耗时：——」）")
	check(not String(labs2[2]).contains("——") and snap2.has("talent")
		and String(labs2[2]).contains(str(int(snap2.get("talent", -1)))),
		"R6-a：绕行回结算·天赋值非「——」且=快照 talent（现状红=「获得天赋值：——」）")
	check((save.get_progress()["cleared"] as Array) == cleared0,
		"R6-c：绕行回结算不重复推进（cleared 与记账时点一致）")
	check_eq(int(save.get_talent()), talent_rt, "R6-c：绕行回结算不重复发奖（talent 一致）")

	# ==================== S4. 快照生命周期（R6-d 零残留） ====================
	print("-- S4 快照生命周期 --")
	game.goto_state(ST_MAIN_MENU)
	await process_frame
	await process_frame
	check(_snapshot().is_empty(),
		"R6-d/R6-5：进入 MAIN_MENU 清空 settle_snapshot（导航根；残留=红）")
	if "settle_snapshot" in game:
		game.set("settle_snapshot", {"chapter": 1, "grade": "完美"})   # 合成在场态测清除面
	game.goto_state(ST_TALK, {"mode": "after_level", "chapter": 1})
	await process_frame
	await process_frame
	check(_snapshot().is_empty(),
		"R6-d：新游戏/对话链路（TALK 目标）清空 settle_snapshot——零残留")

	# ==================== S5. 断链留痕（R6-b） ====================
	print("-- S5 断链留痕 --")
	if "settle_snapshot" in game:
		game.set("settle_snapshot", {})   # 快照清空（S4 后本已空，显式钉死）
	game.goto_state(ST_SETTLE, {"chapter": 1})   # ctx 无 grade/elapsed/talent（生产边缘 ctx 同构）
	await create_timer(0.5).timeout
	var edge2: Node = game.get_current_scene()
	check(edge2 != null and edge2.get_script() == ls_s, "R6-b 前置：断链态边缘路径重建就绪")
	if edge2 != null:
		var labs3: Array = _labels(edge2)
		check(String(labs3[0]).contains("——") and String(labs3[1]).contains("——")
			and String(labs3[2]).contains("——"),
			"R6-b：双通道全缺 → 三 Label 兜底「——」（兜底口径保持）")
		var blog: Variant = edge2.get("_settle_break_log")
		check(blog is Array and not (blog as Array).is_empty()
			and String((blog as Array)[0]).contains(BREAK_MARKER),
			"R6-b：断链产生留痕告警（_settle_break_log 非空且含标记 %s；现状静默降级=红）" % BREAK_MARKER)
	check(lsrc.contains(BREAK_MARKER),
		"R6-b 源契约：level_scene 断链告警含约定标记 %s（push_warning 留痕判据）" % BREAK_MARKER)

	_restore_user()
	finish()
