extends "res://tests/test_base.gd"
## 批次 AA / 域 W5（导航返回栈）判定用例（TDD 红灯先行，2026-09-25）。
## 契约来源：规格 §8.3~§8.6 + 主任务书 W5-1~W5-5：
##   R5-a 主复现链：TALK→设置→CATALOG→LEVEL→退出关卡→CATALOG→图鉴退出 → **必须回 TALK**
##       （现状红 = 单槽被 LEVEL 覆盖 → 图鉴退出回 LEVEL → LEVEL↔CATALOG 永久乒乓）；
##   R5-b/c/d 多跳源覆盖：SETTLE / MOVIE / MAIN_MENU 为源（origin→CATALOG→LEVEL→退→CATALOG→退→origin）；
##   R5-e 深度上界 8【暂定值·待用户复验】：溢出丢最旧（队头出队），栈深恒 ≤8 且不丢最新；
##   R5-f BOOT 不入栈：BOOT→CATALOG→退出 → 栈空 → 兜底 MAIN_MENU；
##   R5-g 覆盖层零残留：任一 goto_state 后 is_settings_open()/is_shop_open() == false（close_overlay 防御）；
##   规则面：入栈仅 old==CATALOG 且 old∉{BOOT} 且非「图鉴进关再回图鉴」；出栈=图鉴退出；
##       清栈=goto MAIN_MENU（导航根）；**跳往非 CATALOG 目标不再无条件清栈**（旧 else 分支退役）；
##   兼容面：catalog_return 保持 Dictionary 栈顶镜像（存量件单跳契约零回归）。
## 规格内部张力处置留痕：§8.4 字面入栈规则（old∉{BOOT,CATALOG} 即 push）在主复现链下仍产生
##   LEVEL↔CATALOG 乒乓（退出关卡回图鉴会把 LEVEL 压栈顶 → 图鉴退出弹回 LEVEL，§8.5-1 末态
##   TALK 不可达）。故入栈规则增补第三条跳过条件=「old==LEVEL 且该关由图鉴进入（_level_from_catalog
##   标记）」——该关属图鉴行程的内嵌分支，其来源仍由栈中更早的 origin 条目承担（对齐 §8.5-1/
##   §8.6-R5-a 的验收末态）。此为满足验收口径的最小必要偏离，报告已登记。
## 坑纪律：红期字段/方法可能不存在 → 一律 `"x" in obj` / has_method /
##   obj.get(key) 防御访问（4.7 实测三者对缺失项均安全返回 false/null，不中止 _initialize）；
##   无头夹具 add_child/goto_state 后 await process_frame 再取节点；消息串含 % 转义 %%。

const CATALOG_GD := "res://scenes/catalog/catalog_scene.gd"
const GAME_GD := "res://autoload/game.gd"
const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"
const BK_PREFIX := "user://_aa_nav_backup_"
## 清档观察组 = 规范四件组（tools/README_走查清档规范.md 六条，test_catalog_scene 同构）：
## save.json / first_launch.flag / save.json.tmp / save.json.bak 逐件备份→终测逐件还原。
const WATCHED: Array = [SAVE_PATH, FLAG_PATH, TMP_PATH, BAK_PATH]

const ST_BOOT := 0
const ST_MAIN_MENU := 1
const ST_MOVIE := 2
const ST_TALK := 3
const ST_LEVEL := 4
const ST_SETTLE := 5
const ST_CATALOG := 6

var game: Variant
var save: Variant
var lib: Variant
var container: Control

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

func _settle() -> void:
	await process_frame
	await process_frame

## 返回栈深度（红期 API 缺席 → -1，断言自然判红不崩）。
func _depth() -> int:
	if game.has_method("catalog_return_depth"):
		return int(game.call("catalog_return_depth"))
	if "catalog_return_stack" in game:
		var v: Variant = game.get("catalog_return_stack")
		if v is Array:
			return (v as Array).size()
	return -1

## 返回栈快照副本（红期字段缺席 → []）。
func _stack() -> Array:
	if "catalog_return_stack" in game:
		var v: Variant = game.get("catalog_return_stack")
		if v is Array:
			return (v as Array).duplicate(true)
	return []

## 出栈（红期方法缺席 → {}）。
func _pop() -> Dictionary:
	if game.has_method("pop_catalog_return"):
		var r: Variant = game.call("pop_catalog_return")
		if r is Dictionary:
			return r
	return {}

## 图鉴退出（驱动 BottomBar 退出钮，与存量件同手法）。
func _exit_catalog() -> void:
	var panel: Node = container.get_child(container.get_child_count() - 1)
	(panel.get_node("BottomBar/ExitButton") as Button).pressed.emit()
	await process_frame
	await process_frame

func _initialize() -> void:
	print("== test_aa_nav_return ==")
	_backup_user()
	game = get_root().get_node("Game")
	save = get_root().get_node("SaveManager")
	lib = get_root().get_node("LevelLibrary")
	save.load_game()
	lib.scan_directory("res://levels_data")
	container = Control.new()
	add_child(container)
	var overlay: CanvasLayer = CanvasLayer.new()
	add_child(overlay)
	game.attach(container, overlay)

	# ==================== S1. 栈面 API 存在性（W5-1/W5-5 字段契约） ====================
	print("-- S1 栈面 API --")
	check("catalog_return_stack" in game and game.get("catalog_return_stack") is Array,
		"W5-1：Game.catalog_return_stack 返回栈字段存在（Array）")
	check(game.has_method("pop_catalog_return") and game.has_method("catalog_return_depth")
		and game.has_method("clear_catalog_return"),
		"W5-1：出栈/深度/清栈 API 存在（pop_catalog_return/catalog_return_depth/clear_catalog_return）")
	check(game.get("catalog_return") is Dictionary,
		"W5-5 兼容面：catalog_return 保持 Dictionary 栈顶镜像（存量单跳件零回归）")
	var gsrc: String = FileAccess.get_file_as_string(GAME_GD)
	check(gsrc.contains("CATALOG_RETURN_MAX_DEPTH"),
		"W5-1：深度上界常量 CATALOG_RETURN_MAX_DEPTH 集中定义（暂定值 8，禁散落魔改）")

	# ==================== S2. BOOT 不入栈（R5-f） ====================
	print("-- S2 BOOT 不入栈 --")
	game.set("_state", ST_BOOT)
	game.goto_state(ST_CATALOG)
	await _settle()
	check_eq(_depth(), 0, "R5-f：BOOT→CATALOG 不入栈（深度 0）")
	var cr_b: Variant = game.get("catalog_return")
	check(cr_b is Dictionary and (cr_b as Dictionary).is_empty(),
		"R5-f：BOOT 来源不入栈 → 栈顶镜像空（旧实现把 BOOT 压槽=红）")
	await _exit_catalog()
	check_eq(int(game.current_state()), ST_MAIN_MENU,
		"R5-f：BOOT→CATALOG→退出 → 兜底 MAIN_MENU（栈空）")

	# ==================== S3. 主复现链（R5-a）+ 覆盖层零残留（R5-g） ====================
	print("-- S3 主复现链 --")
	game.goto_state(ST_TALK, {"mode": "after_level", "chapter": 1})
	await _settle()
	game.open_overlay("settings")
	await _settle()
	check(bool(game.is_settings_open()), "R5-g 前置：TALK 态设置覆盖层已打开")
	# 设置 → 图鉴（生产 settings._on_catalog；此处直跳同构 + 验证 goto_state 关层防御）
	game.goto_state(ST_CATALOG)
	await _settle()
	check(not bool(game.is_settings_open()),
		"R5-g：goto_state(CATALOG) 后设置覆盖层零残留（W5-2 close_overlay 防御；旧实现残留=红）")
	check(_depth() >= 0, "前置：返回栈 API 在场（深度查询非 -1）")
	check_eq(_depth(), 1, "W5-1：TALK 来源进图鉴压栈（深度 1）")
	# 图鉴 → 之前玩过的关卡（重玩入口）
	game.goto_state(ST_LEVEL, {"chapter": 1, "replay": true})
	await _settle()
	# 关卡退出回图鉴（_on_exit_confirmed 同构；批次 AA 回修4/W5-P2-1 起生产路径带
	# from_level_exit 标记——game.gd 依标记跳过入栈，本处与生产同构传标记）
	game.goto_state(ST_CATALOG, {"from_level_exit": true})
	await _settle()
	check_eq(_depth(), 1,
		"W5-1：关卡回图鉴不再覆盖/清栈（旧覆盖语义快照变 LEVEL=红；栈仍持 TALK 深度 1）")
	# 图鉴退出 → 必须回 TALK（用户死循环根治判定点）
	await _exit_catalog()
	check_eq(int(game.current_state()), ST_TALK,
		"R5-a：图鉴退出回 TALK（末态判定点；现状红=LEVEL 乒乓）")
	check_eq(_depth(), 0, "R5-a：出栈消费后栈空")
	check_eq(String(game.context().get("mode", "")), "after_level",
		"R5-a：TALK ctx.mode 透传（快照 ctx 完整传回）")
	check_eq(int(game.context().get("chapter", 0)), 1,
		"R5-a：TALK ctx.chapter 透传")
	game.close_overlay()

	# ==================== S4. 多跳源覆盖（R5-b/c/d） ====================
	print("-- S4 多跳源覆盖 --")
	# --- SETTLE 源 ---
	game.goto_state(ST_MAIN_MENU)
	await _settle()
	game.goto_state(ST_SETTLE, {"chapter": 1, "grade": "完美"})
	await _settle()
	game.goto_state(ST_CATALOG)
	await _settle()
	game.goto_state(ST_LEVEL, {"chapter": 1, "replay": true})
	await _settle()
	# 关卡退出回图鉴（回修4 生产同构：带 from_level_exit 标记）
	game.goto_state(ST_CATALOG, {"from_level_exit": true})
	await _settle()
	check_eq(_depth(), 1, "R5-b：SETTLE 源多跳全程深度恒 1（关卡分支不入栈）")
	await _exit_catalog()
	check_eq(int(game.current_state()), ST_SETTLE,
		"R5-b：SETTLE 源 → 多跳返回 SETTLE（旧覆盖语义回 LEVEL=红）")
	# --- MOVIE 源 ---
	game.goto_state(ST_MAIN_MENU)
	await _settle()
	game.goto_state(ST_MOVIE, {"replay_video": true})
	await _settle()
	game.goto_state(ST_CATALOG)
	await _settle()
	game.goto_state(ST_LEVEL, {"chapter": 1, "replay": true})
	await _settle()
	game.goto_state(ST_CATALOG, {"from_level_exit": true})
	await _settle()
	await _exit_catalog()
	check_eq(int(game.current_state()), ST_MOVIE,
		"R5-c：MOVIE 源 → 多跳返回 OPENING_MOVIE（旧覆盖语义回 LEVEL=红）")
	check(bool(game.context().get("replay_video", false)),
		"R5-c：MOVIE ctx.replay_video 透传")
	# --- MAIN_MENU 源 ---
	game.goto_state(ST_MAIN_MENU)
	await _settle()
	game.goto_state(ST_CATALOG)
	await _settle()
	game.goto_state(ST_LEVEL, {"chapter": 1, "replay": true})
	await _settle()
	game.goto_state(ST_CATALOG, {"from_level_exit": true})
	await _settle()
	await _exit_catalog()
	check_eq(int(game.current_state()), ST_MAIN_MENU,
		"R5-d：MAIN_MENU 源 → 多跳返回 MAIN_MENU（旧覆盖语义回 LEVEL=红）")

	# ==================== S5. LIFO 双入栈出栈顺序（语义表：出栈=最近来源） ====================
	print("-- S5 LIFO 顺序 --")
	game.goto_state(ST_MAIN_MENU)
	await _settle()
	game.goto_state(ST_TALK, {"mode": "after_level", "chapter": 3})
	await _settle()
	game.goto_state(ST_CATALOG)
	await _settle()
	check_eq(_depth(), 1, "S5 前置：TALK 入栈深度 1")
	game.goto_state(ST_LEVEL, {"chapter": 3, "replay": true})
	await _settle()
	game.mark_settle_entered()   # 主路径记账同款置 SETTLE（不经 goto_state）
	game.goto_state(ST_CATALOG)
	await _settle()
	check_eq(_depth(), 2, "W5-1：SETTLE 二次入栈深度 2（旧单槽=红）")
	var e1: Dictionary = _pop()
	check_eq(int(e1.get("state", -1)), ST_SETTLE, "LIFO：先出栈=后入栈的 SETTLE")
	var e2: Dictionary = _pop()
	check_eq(int(e2.get("state", -1)), ST_TALK, "LIFO：后出栈=先入栈的 TALK")
	check_eq(_depth(), 0, "LIFO：双出栈后深度 0")

	# ==================== S6. 深度上界与丢最旧（R5-e） ====================
	print("-- S6 溢出丢最旧 --")
	game.goto_state(ST_MAIN_MENU)
	await _settle()
	# 栈面单元用例：来源态/上下文直写（_state/_context 绕场景装载）——若经 goto_state(TALK)
	# 逐跳，chapter>5 对话缺台词会自行分流回主菜单触发规则②清栈（场景链副作用，非栈语义）。
	# 入栈仍走 goto_state(CATALOG) 真实入口；直写夹具与 test_z_defects 的 _state 注入同款。
	for i: int in 12:
		game.set("_context", {"mode": "after_level", "chapter": i + 1})
		game.set("_state", ST_TALK)
		game.goto_state(ST_CATALOG)
		await process_frame
	await _settle()
	check_eq(_depth(), 8, "R5-e：连续 12 次入栈 → 栈深恒 8（上界=CATALOG_RETURN_MAX_DEPTH）")
	var stk: Array = _stack()
	var bottom_ctx: Dictionary = {}
	var top_ctx: Dictionary = {}
	if not stk.is_empty() and stk[0] is Dictionary:
		bottom_ctx = (stk[0] as Dictionary).get("ctx", {}) if (stk[0] as Dictionary).get("ctx", {}) is Dictionary else {}
	if not stk.is_empty() and stk[stk.size() - 1] is Dictionary:
		var top_e: Dictionary = stk[stk.size() - 1]
		top_ctx = top_e.get("ctx", {}) if top_e.get("ctx", {}) is Dictionary else {}
	check_eq(int(bottom_ctx.get("chapter", -1)), 5,
		"R5-e：溢出丢最旧（队头出队——栈底应为第 5 次入栈 chapter5，chapter1~4 已丢）")
	check_eq(int(top_ctx.get("chapter", -1)), 12,
		"R5-e：不丢最新（栈顶=第 12 次入栈 chapter12）")

	# ==================== S7. 清栈与不清栈规则（语义表逐条） ====================
	print("-- S7 清栈规则 --")
	game.goto_state(ST_MAIN_MENU)
	await _settle()
	check_eq(_depth(), 0, "规则②：goto MAIN_MENU 清栈（导航根，历史无意义）")
	game.goto_state(ST_TALK, {"mode": "after_level", "chapter": 1})
	await _settle()
	game.goto_state(ST_CATALOG)
	await _settle()
	check_eq(_depth(), 1, "S7 前置：入栈深度 1")
	game.goto_state(ST_MOVIE, {})
	await _settle()
	check_eq(_depth(), 1,
		"W5-1：跳往非 CATALOG 目标不再无条件清栈（旧 else: catalog_return={} 退役；MOVIE 跳转栈保留）")
	game.goto_state(ST_CATALOG)
	await _settle()
	check_eq(_depth(), 2, "W5-1：MOVIE 来源入栈（深度 2，多跳可叠加）")
	# 商店覆盖层零残留（R5-g 第二只眼）
	game.goto_state(ST_MAIN_MENU)
	await _settle()
	game.open_overlay("shop")
	await _settle()
	check(bool(game.is_shop_open()), "R5-g 前置：商店覆盖层已打开")
	game.goto_state(ST_CATALOG)
	await _settle()
	check(not bool(game.is_shop_open()),
		"R5-g：goto_state(CATALOG) 后商店覆盖层零残留（W5-2 防御；旧实现残留=红）")
	game.close_overlay()

	# ==================== S8. 单跳语义零回归（O5/P3 存量契约护栏） ====================
	print("-- S8 单跳零回归 --")
	game.goto_state(ST_MAIN_MENU)
	await _settle()
	game.goto_state(ST_LEVEL, {"chapter": 2, "replay": true})
	await _settle()
	game.goto_state(ST_CATALOG)
	await _settle()
	check_eq(_depth(), 1, "O5 护栏：LEVEL 单跳来源入栈（非图鉴进入的关卡可返回）")
	await _exit_catalog()
	check_eq(int(game.current_state()), ST_LEVEL,
		"O5 单跳零回归：LEVEL 来源 → 图鉴退出回关卡（5a 同构）")
	check_eq(int(game.context().get("chapter", -1)), 2, "O5 单跳零回归：ctx.chapter 透传=2")
	check(bool(game.context().get("replay", false)), "O5 单跳零回归：replay 位透传=true")
	var cr: Variant = game.get("catalog_return")
	check(cr is Dictionary and (cr as Dictionary).is_empty(),
		"O5 单跳零回归：消费后栈顶镜像 catalog_return 复位空（防串味，存量件契约）")
	# TALK 单跳透传（P3 同构）
	game.goto_state(ST_MAIN_MENU)
	await _settle()
	game.goto_state(ST_TALK, {"mode": "after_level", "chapter": 4})
	await _settle()
	game.goto_state(ST_CATALOG)
	await _settle()
	await _exit_catalog()
	check_eq(int(game.current_state()), ST_TALK, "P3 单跳零回归：TALK 来源退出回对话")
	check_eq(int(game.context().get("chapter", 0)), 4, "P3 单跳零回归：ctx.chapter 透传=4")

	# ==================== S9. 嵌套链（批次 AA 回修4 / W5-P2-1：关卡内设置→图鉴须可返回关卡） ====================
	print("-- S9 嵌套链（回修4） --")
	# 链：MAIN_MENU→CATALOG（入栈 MM）→LEVEL（图鉴进入，flag=true）→【关卡内设置→图鉴：
	#     settings_panel._on_catalog 生产调用 goto_state(CATALOG) **不置标记**】（应入栈 LEVEL）
	#     →图鉴退出→必须回该 LEVEL（O5 语义恢复）→再退出→回 MAIN_MENU。
	# 红态锚（W5 引入的语义回归）：第三条跳过条件过度泛化（不区分「关卡退出」与「关卡内设置」）
	#   → LEVEL 不入栈 → 图鉴退出回 MAIN_MENU 而非该关卡。
	game.goto_state(ST_MAIN_MENU)
	await _settle()
	game.goto_state(ST_CATALOG)
	await _settle()
	check_eq(_depth(), 1, "S9 前置：MAIN_MENU 来源入栈（深度 1）")
	game.goto_state(ST_LEVEL, {"chapter": 1, "replay": true})
	await _settle()
	# 关卡内设置→图鉴（settings_panel._on_catalog 同构：零标记直跳）
	game.goto_state(ST_CATALOG)
	await _settle()
	check_eq(_depth(), 2,
		"回修4/S9①：关卡内设置→图鉴（零标记）→ LEVEL 入栈（红态=1，跳过条件过度泛化吞入栈）")
	await _exit_catalog()
	check_eq(int(game.current_state()), ST_LEVEL,
		"回修4/S9②：图鉴退出必须回该 LEVEL（嵌套链末态判定点；红态=MAIN_MENU）")
	check_eq(int(game.context().get("chapter", -1)), 1, "回修4/S9③：回关 ctx.chapter 透传=1")
	check(bool(game.context().get("replay", false)), "回修4/S9④：回关 ctx.replay 位透传=true")
	# 收尾：经关卡退出路径（带标记）回图鉴 → 再退出图鉴 → 弹栈底 MAIN_MENU
	#（S9② 后身处 LEVEL 场景，图鉴退出驱动件只在 CATALOG 态在场——先带标记回图鉴再退出，
	# 与生产「关卡退出钮→图鉴→退出」链路同构）
	game.goto_state(ST_CATALOG, {"from_level_exit": true})
	await _settle()
	check_eq(_depth(), 1,
		"回修4/S9⑤ 前置：带标记关卡退出仍跳过入栈（深度 1，栈底=MAIN_MENU）")
	await _exit_catalog()
	check_eq(int(game.current_state()), ST_MAIN_MENU,
		"回修4/S9⑤：栈耗尽 → 图鉴退出回 MAIN_MENU（栈底弹尽，清栈规则①/兜底口径零回归）")
	# 对照组：关卡自己的「退出(回图鉴)」按钮路径（from_level_exit=true）仍跳过入栈（乒乓阻断保持）
	# 链：MAIN_MENU→CATALOG（入栈 MM，深度 1）→LEVEL（图鉴进入 flag=true）→带标记回图鉴
	#     →跳过入栈（栈顶仍=MM 而非 LEVEL）→退出→MAIN_MENU（主复现链末态语义零回归）。
	game.goto_state(ST_CATALOG)
	await _settle()
	check_eq(_depth(), 1, "回修4/S9⑥ 前置：MAIN_MENU 来源入栈（深度 1）")
	game.goto_state(ST_LEVEL, {"chapter": 2, "replay": true})
	await _settle()
	game.goto_state(ST_CATALOG, {"from_level_exit": true})
	await _settle()
	var s9_stk: Array = _stack()
	var s9_top_state := -1
	if not s9_stk.is_empty() and s9_stk[s9_stk.size() - 1] is Dictionary:
		s9_top_state = int((s9_stk[s9_stk.size() - 1] as Dictionary).get("state", -1))
	check(s9_top_state == ST_MAIN_MENU,
		"回修4/S9⑥：关卡退出→图鉴（带标记）仍跳过入栈——栈顶保持 MAIN_MENU（红态=LEVEL 入栈=乒乓）")
	await _exit_catalog()
	check_eq(int(game.current_state()), ST_MAIN_MENU,
		"回修4/S9⑦：带标记跳过入栈 → 图鉴退出回 MAIN_MENU（主复现链末态语义零回归）")

	# ==================== S10. 防御深度（P3-a 新游戏清栈 / P3-b 栈顶镜像快照） ====================
	print("-- S10 P3-a/P3-b 防御深度 --")
	# P3-b：catalog_return 镜像=快照（引用别名退役）——直改栈内条目不得串镜像
	game.set("_context", {"mode": "after_level", "chapter": 1})
	game.set("_state", ST_TALK)
	game.goto_state(ST_CATALOG)
	await process_frame
	var stk_p3b: Variant = game.get("catalog_return_stack")
	var alias_bad := false
	if stk_p3b is Array and not (stk_p3b as Array).is_empty():
		var top_entry: Dictionary = (stk_p3b as Array).back()
		if top_entry is Dictionary:
			(top_entry as Dictionary)["ctx"] = {"mode": "mutated"}
			var mirror: Variant = game.get("catalog_return")
			if mirror is Dictionary:
				var mctx: Variant = (mirror as Dictionary).get("ctx", {})
				alias_bad = (mctx is Dictionary and String((mctx as Dictionary).get("mode", "")) == "mutated")
	check(not alias_bad,
		"P3-b：catalog_return 镜像为快照——直改栈内条目不串镜像（红态=引用别名被外部写穿）")
	game.call("pop_catalog_return")
	# P3-a：reset_for_new_game 显式清返回栈（防未来非主菜单入口的新游戏路径栈残留）
	game.set("_context", {"mode": "after_level", "chapter": 2})
	game.set("_state", ST_TALK)
	game.goto_state(ST_CATALOG)
	await process_frame
	check_eq(_depth(), 1, "P3-a 前置：入栈深度 1")
	save.call("reset_for_new_game")
	check_eq(_depth(), 0,
		"P3-a：reset_for_new_game 消费侧显式清返回栈（红态=栈残留）")

	_restore_user()
	finish()
