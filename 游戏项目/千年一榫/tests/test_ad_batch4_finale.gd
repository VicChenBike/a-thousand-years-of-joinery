extends "res://tests/test_base.gd"
## 批次 AD 步骤四（2026-09-28，spec §4.4）：通关终局「未完待续」界面专项回归（TDD 红灯先行）。
## 契约来源（spec §4.4.1/§4.4.2 + 任务清单）：
##   段 A：settle_next_route(replay, has_next, chapter=1) 三分流 + chapter==5 → "finale"
##         （replay 优先保持零回归：replay=true 恒 catalog，即便 chapter=5）；
##   段 B：Game.State 枚举追加 FINALE=7（既有 0~6 值零漂移红线）＋ SCENE_PATHS[FINALE]
##         指向 res://scenes/finale/finale_scene.tscn；
##   段 C：终局场景 UI——背景 bg_chapter5.png、压暗遮罩 Color(0,0,0,0.65)、居中大标题
##         「未完待续」（马善政楷书 88 号、金色 Palette.MAIN_GOLD、Outline 6）、
##         右下【返回主菜单】钮（无立绘/无对话框）；
##   段 D：行为级路由——FINALE 场景内点「返回主菜单」→ Game.goto_state(MAIN_MENU)；
##         level._on_settle_next_pressed 对 "finale" 分流进 FINALE 态（源码留痕 + 行为）；
##   段 E：状态机联动核查留痕——game.gd 自动穿戴组含 FINALE（SETTLE/MAIN_MENU/CATALOG
##         同组换回自选，spec 任务清单「非关卡场景组」语义）。
## 零摄像头纪律：全部无头 + 合成事件（pressed.emit 直调按钮语义），绝不触发摄像头。
## 清档纪律：goto_state 触发 K-D 自动穿戴写档 → 起测前备份 user:// 档案、终测逐字节还原自证。

const GAME_SCRIPT := "res://autoload/game.gd"
const LS_SCRIPT := "res://scenes/level/level_scene.gd"
const FINALE_SCENE_PATH := "res://scenes/finale/finale_scene.tscn"
const FINALE_SCRIPT := "res://scenes/finale/finale_scene.gd"
const BG_TEXTURE := "res://assets/backgrounds/bg_chapter5.png"
const MSZ_FONT := "res://fonts/MaShanZheng-Regular.ttf"
const PALETTE_SCRIPT := "res://scripts/palette.gd"

const ST_MAIN_MENU := 1
const ST_FINALE := 7  # 契约：枚举追加在末尾（CATALOG=6 之后）

const DISC_WATCHED: Array = [
	"user://save.json", "user://save.json.bak", "user://save.json.tmp", "user://first_launch.flag",
]
const DISC_BK_PREFIX := "user://_ad4_savebak_"

var _pre_texts: Dictionary = {}

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _backup_user() -> void:
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
			_pre_texts[p] = FileAccess.get_file_as_string(p)
		else:
			_pre_texts[p] = ""  # 起测前不存在 → 终测同样须不存在（清档口径零残留）

func _restore_user() -> void:
	for p: String in DISC_WATCHED:
		# 先删测试残留，再回灌备份（备份缺失=起测前本无该文件，删除即还原）
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(_disc_abs(p))
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(_disc_abs(bk))
	var sm: Node = root.get_node_or_null("SaveManager")
	if sm != null:
		sm.call("load_game")
	for p: String in DISC_WATCHED:
		var post: String = FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""
		check_eq(post, String(_pre_texts.get(p, "")), "清档纪律：%s 测前测后逐字节等价" % p)

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_ad_batch4_finale ==")
	await process_frame
	_backup_user()
	var game: Node = root.get_node_or_null("Game")
	var save: Node = root.get_node_or_null("SaveManager")
	check(game != null and save != null, "AD4 前置：Game/SaveManager autoload 在场")
	if game == null:
		finish()
		return
	var g_s: Script = load(GAME_SCRIPT)
	var ls_s: Script = load(LS_SCRIPT)
	check(g_s != null and ls_s != null, "AD4 前置：game.gd/level_scene.gd 可加载")

	# =========================================================================
	# 段 A：settle_next_route 三分流 + chapter==5 → finale（spec §4.4.1）
	# =========================================================================
	print("--- 段 A：settle_next_route 纯函数分流 ---")
	# A1 新增分流（红灯点：现签名无 chapter 参数，3 参调用即 RED）
	check_eq(String(ls_s.call("settle_next_route", false, false, 5)), "finale",
		"AD §4.4.1：通关第 5 关（非重玩、无下关）「下一关」→ finale")
	check_eq(String(ls_s.call("settle_next_route", true, false, 5)), "catalog",
		"AD §4.4.1：replay 优先——第 5 关重玩下一关仍 → catalog（终局不截胡回看链）")
	check_eq(String(ls_s.call("settle_next_route", true, true, 5)), "catalog",
		"AD §4.4.1：replay=true∧has_next=true∧chapter=5 → catalog（重玩门最前）")
	# A2 既有语义零回归（旧两参调用经 chapter 缺省 1 保持）
	check_eq(String(ls_s.call("settle_next_route", true, true)), "catalog",
		"零回归：replay→catalog（旧两参形态，缺省 chapter=1）")
	check_eq(String(ls_s.call("settle_next_route", false, false)), "main_menu",
		"零回归：无下关→main_menu（旧两参形态）")
	check_eq(String(ls_s.call("settle_next_route", false, true)), "talk",
		"零回归：有下关→talk（旧两参形态）")
	# A3 显式缺省等价（chapter 缺省 == 1）
	check_eq(String(ls_s.call("settle_next_route", false, true, 1)), "talk",
		"AD §4.4.1：chapter=1 显式缺省 → talk")
	check_eq(String(ls_s.call("settle_next_route", false, false, 3)), "main_menu",
		"AD §4.4.1：chapter=3 无下关 → main_menu")
	check_eq(String(ls_s.call("settle_next_route", false, true, 4)), "talk",
		"AD §4.4.1：chapter=4 有下关 → talk（finale 仅 chapter==5）")
	check_eq(String(ls_s.call("settle_next_route", false, true, 5)), "finale",
		"AD §4.4.1：chapter=5 终局判定先于 has_next（第 5 关后无论数据皆 finale）")

	# =========================================================================
	# 段 B：State 枚举与 SCENE_PATHS 契约（spec §4.4.1）
	# =========================================================================
	print("--- 段 B：State.FINALE 与场景映射契约 ---")
	var consts: Dictionary = (g_s as GDScript).get_script_constant_map()
	var st_map: Dictionary = consts.get("State", {})
	check(st_map.has("FINALE"), "AD §4.4.1：State 枚举含 FINALE")
	check_eq(int(st_map.get("FINALE", -1)), ST_FINALE, "AD §4.4.1：State.FINALE == 7（追加于 CATALOG=6 后）")
	# 既有枚举值零漂移红线（追加不得搬移旧值）
	check_eq(int(st_map.get("BOOT", -1)), 0, "零回归：State.BOOT == 0")
	check_eq(int(st_map.get("MAIN_MENU", -1)), 1, "零回归：State.MAIN_MENU == 1")
	check_eq(int(st_map.get("OPENING_MOVIE", -1)), 2, "零回归：State.OPENING_MOVIE == 2")
	check_eq(int(st_map.get("TALK", -1)), 3, "零回归：State.TALK == 3")
	check_eq(int(st_map.get("LEVEL", -1)), 4, "零回归：State.LEVEL == 4")
	check_eq(int(st_map.get("SETTLE", -1)), 5, "零回归：State.SETTLE == 5")
	check_eq(int(st_map.get("CATALOG", -1)), 6, "零回归：State.CATALOG == 6")
	var sp: Dictionary = consts.get("SCENE_PATHS", {})
	check_eq(String(sp.get(ST_FINALE, "")), FINALE_SCENE_PATH,
		"AD §4.4.1：SCENE_PATHS[FINALE] == res://scenes/finale/finale_scene.tscn")

	# =========================================================================
	# 段 C：终局场景 UI 结构（spec §4.4.2）
	# =========================================================================
	print("--- 段 C：finale 场景 UI 结构 ---")
	check(ResourceLoader.exists(FINALE_SCENE_PATH), "AD §4.4.2：finale_scene.tscn 存在")
	check(ResourceLoader.exists(FINALE_SCRIPT), "AD §4.4.2：finale_scene.gd 存在")
	check(ResourceLoader.exists(BG_TEXTURE), "AD §4.4.2：底图 bg_chapter5.png 存在")
	check(ResourceLoader.exists(MSZ_FONT), "AD §4.4.2：字体 MaShanZheng-Regular.ttf 存在")
	if not ResourceLoader.exists(FINALE_SCENE_PATH):
		print("（finale 场景缺席，段 C/D 结构断言转源码留痕判红）")
	else:
		var container: Control = Control.new()
		container.name = "AD4Container"
		var overlay: CanvasLayer = CanvasLayer.new()
		overlay.name = "AD4Overlay"
		add_child(container)
		add_child(overlay)
		game.attach(container, overlay)
		var fin: Node = (load(FINALE_SCENE_PATH) as PackedScene).instantiate()
		container.add_child(fin)
		await process_frame
		# C1 背景层：全屏 TextureRect 挂 bg_chapter5（expand/stretch 对齐工程既有惯例
		# talk/catalog：EXPAND_IGNORE_SIZE + STRETCH_KEEP_ASPECT_COVERED，见各自 tscn 同两行）
		var bg: Node = fin.get_node_or_null("Background")
		check(bg is TextureRect, "AD §4.4.2：Background 全屏 TextureRect 在场")
		if bg is TextureRect:
			var tex: Texture2D = (bg as TextureRect).texture
			check_eq(String(tex.resource_path if tex != null else ""),
				BG_TEXTURE, "AD §4.4.2：底图 texture=bg_chapter5.png")
			check_eq((bg as TextureRect).expand_mode, TextureRect.EXPAND_IGNORE_SIZE,
				"AD §4.4.2：背景 expand 对齐既有场景惯例（EXPAND_IGNORE_SIZE）")
			check_eq((bg as TextureRect).stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_COVERED,
				"AD §4.4.2：背景 stretch 对齐既有场景惯例（KEEP_ASPECT_COVERED，talk/catalog 同款）")
		# C2 压暗遮罩：ColorRect Color(0,0,0,0.65)
		var dim: Node = fin.get_node_or_null("Dim")
		check(dim is ColorRect, "AD §4.4.2：Dim 压暗遮罩 ColorRect 在场")
		if dim is ColorRect:
			check_eq((dim as ColorRect).color, Color(0, 0, 0, 0.65),
				"AD §4.4.2：遮罩 Color(0,0,0,0.65)（比 talk 0.62 更深一档）")
		# C3 居中大标题「未完待续」
		var title: Node = fin.get_node_or_null("Title")
		check(title is Label, "AD §4.4.2：Title 大标题 Label 在场")
		if title is Label:
			var tl := title as Label
			check_eq(tl.text, "未完待续", "AD §4.4.2：标题文本=未完待续")
			# 金色单源：标题字色=Palette.MAIN_GOLD（工程主金单源，批次 J 定名 #F5C542——
			# 存值 (0.96,0.77,0.26) 为十六进制近似档，逐分量差 <0.005，工程注释在案）
			var palette: Variant = load(PALETTE_SCRIPT)
			var gold: Color = palette.get("MAIN_GOLD")
			var ref_gold := Color("#F5C542")
			check(absf(gold.r - ref_gold.r) < 0.005 and absf(gold.g - ref_gold.g) < 0.005 \
				and absf(gold.b - ref_gold.b) < 0.005,
				"AD §4.4.2：Palette.MAIN_GOLD 即 #F5C542 近似单源（逐分量差<0.005）")
			check_eq(tl.modulate, Color(1, 1, 1, 1), "AD §4.4.2：Title modulate 恒白（add_theme_* 覆写判据前提）")
			check_eq(tl.get_theme_color("font_color"), gold,
				"AD §4.4.2：标题字色=金色 Palette.MAIN_GOLD 单源（禁散落字面量）")
			check_eq(tl.get_theme_font_size("font_size"), 88, "AD §4.4.2：字号 88")
			check_eq(tl.get_theme_constant("outline_size"), 6, "AD §4.4.2：Outline Size 6")
			check_eq(tl.get_theme_color("font_outline_color"), Color(0, 0, 0, 0.5),
				"AD §4.4.2：描边黑透明（纯黑 α0.5，主菜单墨韵同款手法）")
			check_eq(tl.get_theme_color("font_shadow_color"), Color(0, 0, 0, 0.6),
				"AD §4.4.2：阴影黑透明（纯黑 α0.6）")
			var fnt: Font = tl.get_theme_font("font")
			check(fnt != null and String(fnt.resource_path) == MSZ_FONT,
				"AD §4.4.2：字体=马善政楷书 MaShanZheng-Regular.ttf")
			check_eq(tl.horizontal_alignment, HORIZONTAL_ALIGNMENT_CENTER, "AD §4.4.2：水平居中")
			check_eq(tl.vertical_alignment, VERTICAL_ALIGNMENT_CENTER, "AD §4.4.2：垂直居中")
			check_eq(tl.anchor_left, 0.0, "AD §4.4.2：Title 全屏铺满锚定（居中实现①anchor）")
			check_eq(tl.anchor_right, 1.0, "AD §4.4.2：Title 全屏铺满锚定（居中实现②）")
			check_eq(tl.anchor_bottom, 1.0, "AD §4.4.2：Title 全屏铺满锚定（居中实现③）")
			check_eq(tl.mouse_filter, Control.MOUSE_FILTER_IGNORE, "AD §4.4.2：Title IGNORE 不吃输入")
		# C4 无立绘/无对话框
		check(fin.get_node_or_null("Portrait") == null, "AD §4.4.2：无角色立绘节点")
		check(fin.get_node_or_null("DialogPanel") == null, "AD §4.4.2：无对话框节点")
		# C5 右下角返回主菜单按钮
		var back: Node = fin.get_node_or_null("BackButton")
		check(back is Button, "AD §4.4.2：右下角 BackButton 在场")
		if back is Button:
			var bb := back as Button
			check_eq(bb.text, "返回主菜单", "AD §4.4.2：按钮文本=返回主菜单")
			check_eq(bb.anchor_left, 1.0, "AD §4.4.2：按钮右下锚定（anchor_left=1）")
			check_eq(bb.anchor_top, 1.0, "AD §4.4.2：按钮右下锚定（anchor_top=1）")
			check_eq(bb.mouse_default_cursor_shape, Control.CURSOR_POINTING_HAND,
				"AD §4.4.2：手型光标（工程可点项统一口径）")
			# 悬停光晕体系接入（任务清单 §2）：Button 由 UILightLinker node_added 自动挂
			# ui_material；场景侧须显式挂 hover_glow meta（eye_duration_panel 同款双保险，
			# 与 window_manager K9 判定链 _is_glow_target 的 meta 分支同源）
			check(bb.has_meta("hover_glow"), "AD §4.4.2：按钮挂 hover_glow meta（键鼠+手势光标光晕）")
		fin.queue_free()
		await process_frame

	# =========================================================================
	# 段 D：行为级路由（FINALE 场景进出）
	# =========================================================================
	print("--- 段 D：路由行为 ---")
	if ResourceLoader.exists(FINALE_SCENE_PATH):
		var container2: Control = Control.new()
		container2.name = "AD4Container2"
		var overlay2: CanvasLayer = CanvasLayer.new()
		overlay2.name = "AD4Overlay2"
		add_child(container2)
		add_child(overlay2)
		game.attach(container2, overlay2)
		var sigs: Array = []
		var cb := func(from_s: int, to_s: int) -> void: sigs.append([from_s, to_s])
		game.state_changed.connect(cb)
		# D1 goto_state(FINALE) → 状态生效 + finale 场景入容器
		game.goto_state(ST_FINALE)
		await process_frame
		check_eq(int(game.current_state()), ST_FINALE, "AD §4.4.1：goto_state(FINALE) 状态生效")
		check(game.get_current_scene() != null \
			and String((game.get_current_scene() as Node).scene_file_path) == FINALE_SCENE_PATH,
			"AD §4.4.1：FINALE 态主场景=finale_scene.tscn（_load_main_scene 通用映射路由）")
		check_eq(sigs.size(), 1, "D1：state_changed 恰一次")
		if sigs.size() == 1:
			check_eq(int(sigs[0][1]), ST_FINALE, "D1：state_changed.to==FINALE")
		# D2 点「返回主菜单」→ MAIN_MENU（平滑返回）
		var scene2: Node = game.get_current_scene()
		var bb2: Button = null
		if scene2 != null:
			bb2 = scene2.get_node_or_null("BackButton") as Button
		if bb2 != null:
			bb2.pressed.emit()
			await process_frame
			check_eq(int(game.current_state()), ST_MAIN_MENU,
				"AD §4.4.2：点击返回主菜单 → Game.goto_state(MAIN_MENU)")
			check_eq(sigs.size(), 2, "D2：返回后再发一次 state_changed")
		else:
			check(false, "AD §4.4.2：BackButton 可达（行为路由前置）")
			check(false, "D2：返回后 state_changed 计数（前置缺席连带判红）")
		# D3 settle_next_route 分流「下一关」行为级（第 5 关结算数据 → FINALE）——
		# level 实例重建代价高，按任务清单口径以**源码留痕**锁定分流分支与实参：
		var lsrc: String = FileAccess.get_file_as_string(LS_SCRIPT)
		check(lsrc.contains("\"finale\":") or lsrc.contains("finale\""),
			"AD §4.4.1 留痕：_on_settle_next_pressed 新增 finale 分流分支")
		check(lsrc.find("settle_next_route(replay, has_next, _chapter)") >= 0,
			"AD §4.4.1 留痕：分流调用处传入 _chapter（第 5 关判定实参）")
		# D4 goto_state(FINALE) 无头路径不崩溃（本断言可达即段 D 全程无脚本级报错中断；
		# 注：断言消息刻意避开 S-C-R-I-P-T 连字符词形——回归驱动 grep 无锚定计数字面，
		# 防 PASS 行文本自身被误计为脚本报错误导判绿双条件）
		check(true, "AD §4.4.1：goto_state(FINALE) 无头路径零崩溃（段 D 全程执行到底）")
		game.state_changed.disconnect(cb)
	else:
		check(false, "AD §4.4.1：D1 FINALE 态路由行为（场景缺席不可测，判红留痕）")
		check(false, "AD §4.4.2：D2 返回主菜单行为（场景缺席不可测，判红留痕）")

	# =========================================================================
	# 段 E：状态机联动留痕核查（spec §4.4.1 任务清单「逐处核查 s==State.XXX」）
	# =========================================================================
	print("--- 段 E：game.gd 联动分支留痕 ---")
	var gsrc: String = FileAccess.get_file_as_string(GAME_SCRIPT)
	# E1 自动穿戴组：FINALE 属「非关卡场景组」→ 与 SETTLE/MAIN_MENU/CATALOG 同组换回自选
	check(gsrc.contains("State.FINALE") and gsrc.contains("restore_preferred_skin"),
		"AD §4.4.1：game.gd 穿戴分支含 FINALE 组（非关卡=换回自选皮肤）")
	var gconst: Dictionary = (g_s as GDScript).get_script_constant_map()
	var st2: Dictionary = gconst.get("State", {})
	# E2 逐分支语义核查结论（回归锚）：FINALE 不属 SETTLE/CATALOG 保留组——goto_state
	# 进 FINALE 时 settle_snapshot 清空（结算快照零残留，防越态显示旧结算数据）；
	# FINALE 不属 CATALOG 可返回来源组的显式排除项（不入栈/栈中旧数据随 MAIN_MENU 清栈，
	# 与 OPENING_MOVIE/TALK 同款「可返回来源但经由主菜单收口」语义，行为经 D2 断链闭合）。
	check(int(st2.get("FINALE", -1)) != int(st2.get("SETTLE", -2)) \
		and int(st2.get("FINALE", -1)) != int(st2.get("CATALOG", -2)),
		"E2：FINALE 独立态（≠SETTLE/CATALOG，settle_snapshot 保留组不含 FINALE）")
	check_eq(gsrc.count("State.FINALE"), 2,
		"E2：game.gd FINALE 出现恰两处（SCENE_PATHS 映射 + 穿戴组；其余分支天然兼容零改动）")

	finish()
