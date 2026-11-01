extends "res://tests/test_base.gd"
## T08 判定用例：主菜单契约无头测试（TDD 先写）。
## 契约来源：实施计划 T08 + 2026-08-26 用户 UI 修正指示（布局按设计稿 image8）
##   + 批次 K-KC-3 主菜单修复（spec §6.1，K2-1~2-6/K4-1/K8 落位）：
##   布局（K2 修订版，批次 L-B 再修订）：左侧竖向菜单区（标题下移进宽弧区、去 clip_text，
##     椭圆容器 EllipsePanel——原 ArcPanel，三钮 160 等长等 φ 贴弧直挂 LeftPanel，VBox 已删）；
##     右侧大面积背景图区域（大厅背景）；K2-5 删左下手势提示面板（清单由全局 GestureHUD 承载）；
##     K2-6/Q3 删左列「设置」按钮——唯一设置入口=GlobalUI 右上角常驻（main.tscn 断言见 test_window_k）。
##     右下左右手置信度显示区由全局手势 HUD 负责（本场景不做、不遮挡，不在本测试重复断言）。
##   按钮：StartButton（开始游戏）、LoadButton（加载存档）、QuitButton（退出）。
##   K2-2 半圆重做（L-B 修订：ArcPanel→EllipsePanel，形状改面板档材质 SDF D 形椭圆弧，
##     StyleBox corner/border/shadow 归零仅留半透明底色，alpha 档 0.42/0.38→0.68/0.65）、
##     mouse_filter=PASS（K9 hover 可判定）+ hover_glow meta；
##   K2-1 标题（L-B 修订：字号 48→40，clip_text 硬裁切删除，L4）。
##   K4-1→批次V规格§3.2（V-C5 等价替换留痕）：NewGameDialog/ExitDialog 节点退役，新游戏/退出
##     确认改经 Game.confirm → TopStrip 统一确认条（本文件以 StripSpy 夹具承接文案与回调断言，
##     旧「GlassDialog 实例 script 比较/节点可见性/正文 Label」断言等价替换为「spy 收到逐字文案
##     + 回调透传」；未挂接兜底路径归 test_v_game_confirm）。
##   背景：固定加载大厅背景 res://assets/backgrounds/bg_menu.png（不再用 get_background_path(ch)，
##     那是关卡内背景：现代/宋/元/明）；图片不存在时纯色兜底（隐藏 TextureRect）。
##   按钮两态（C2 / 批次J3-J3-2 修订，替换旧「开始游戏二次分流」语义）：
##     无存档（首次标记仍在）：StartButton=「开始游戏」（enabled）+ LoadButton=「加载存档」（灰禁用，tooltip「暂无存档」）。
##       点开始 = mark_first_launch() + goto_state(OPENING_MOVIE)。
##     有存档（非首次标记）：StartButton=「新游戏」+ LoadButton=「载入存档」（不再出现「开始游戏」文本）。
##       断点继续语义整体由 LoadButton 承接：goto_state(LEVEL, {chapter:next_chapter, replay:false})；
##       next_chapter>5（已全通关）→ goto_state(CATALOG)。
##       点新游戏 = 弹统一确认条（Game.confirm，批次V§3.2）防误触，确认前不清档不路由；
##       确认后 = SaveManager.reset_for_new_game()（数据回默认〔含天赋500〕+删 first_launch 标记，
##       清档重走开场）→ 主菜单侧重建标记（P1-1 修：与首次流程「先 mark 再进动画」对称，
##       新周目保持有档态）+ goto_state(OPENING_MOVIE)。
##   退出按钮两态下常驻保留；K8→批次V§3.2：点退出=弹统一确认条（Game.confirm，
##     「退出《千年一榫》？」，与窗口关闭按钮同流程），确认后 GestureBridge.stop_gesture_process()
##     + get_tree().quit()（quit 行为留编辑器手动清单，无头环境只验弹条与连接，不触发 on_confirmed）。
## 环境说明：--script 无头模式下 7 个 autoload 均已自动实例化（探针实测），但 --script 主脚本
## 的编译早于 autoload 注册，不能直接写全局标识符（编译报 Identifier not found，探针实测），
## 故经 /root/<Name> 取 Variant 动态引用。枚举值与 T07 测试一致：
##   BOOT=0 MAIN_MENU=1 OPENING_MOVIE=2 TALK=3 LEVEL=4 SETTLE=5 CATALOG=6。

const SCENE_PATH := "res://scenes/menu/main_menu.tscn"
const FLAG_PATH := "user://first_launch.flag"
const SAVE_PATH := "user://save.json"
const BG_MENU_PATH := "res://assets/backgrounds/bg_menu.png"

const ST_MAIN_MENU := 1
const ST_OPENING_MOVIE := 2
const ST_LEVEL := 4
const ST_CATALOG := 6

## 批次V规格§3.2（V-C5）夹具：TopStrip 替身——记录 Game.confirm 委托来的 push_confirm 调用
##（test_v_game_confirm 同款形态）；确认/取消由测试直接调用记录到的回调（模拟条内按钮触发）。
class StripSpy extends Node:
	var confirm_calls: Array = []   # 每项 [text, on_confirmed, on_canceled]
	func push_confirm(text: String, on_confirmed: Callable = Callable(),
			on_canceled: Callable = Callable()) -> void:
		confirm_calls.append([text, on_confirmed, on_canceled])
	func get_confirm_calls() -> Array:
		return confirm_calls

var ssp: Node

func _cleanup() -> void:
	var flag_abs: String = ProjectSettings.globalize_path(FLAG_PATH)
	var save_abs: String = ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(flag_abs):
		DirAccess.remove_absolute(flag_abs)
	if FileAccess.file_exists(save_abs):
		DirAccess.remove_absolute(save_abs)

# ===== 清档纪律（tools/README_走查清档规范.md，批次V回修②B 补齐，test_v_save_domain 同款）=====
# 起测前备份 user:// 真实档案（save.json/first_launch.flag 及可触及的 .tmp/.bak 四件组），
# 终测统一经 finish() 收口还原：先同步 free 测试挂载节点（level._exit_tree 兜底写档等
# 「退出写回」先落测试域磁盘，规范第 6 条），再逐件还原 + SaveManager load_game 重同步内存
# + 逐字节等价断言 + EVID 证据行。备份路径必须带全 user:// 前缀（相对路径在 FileAccess/
# DirAccess 间解析漂移 → 备份链静默失效，test_n10 先例）；每文件独立备份前缀防崩溃残留互踩。
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_r2b_mm_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _pre_save_text: String = ""   # 起测前真实 save.json 原文（还原等价自检基准）

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _disc_del(p: String) -> void:
	var a: String = _disc_abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _backup_user() -> void:
	# 规范第 1 条：任何删/写档操作之前备份真实档案（有档才备份；还原「有备份才回拷」幂等，
	# 起测前不存在的档案终测后仍不存在——测试自建残留一律清零）
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	# 防退出写回（规范第 6 条）：先同步 free 测试挂载的非 autoload 节点——level._exit_tree
	# 兜底写档（N9）若拖到进程退出树序，会在还原之后把测试态写回真实档案；提前 free 令
	# 兜底写档落测试域磁盘，紧随其后的逐件还原即将其覆盖。
	for c: Node in root.get_children():
		if not DISC_AUTOLOADS.has(String(c.name)):
			c.free()
	# 规范第 2 条：逐件还原 + load_game 重同步内存（防后续 save_game 把测试态写回真实档案）
	for p: String in DISC_WATCHED:
		_disc_del(p)
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(_disc_abs(bk))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()
	# 纪律自检：还原后 save.json 与起测前逐字节等价（起测前无档 ↔ 还原后无档）
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|mm|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_main_menu ==")
	_backup_user()
	var save: Variant = get_root().get_node("SaveManager")
	var game: Variant = get_root().get_node("Game")
	var lib: Variant = get_root().get_node("LevelLibrary")
	var bridge: Variant = get_root().get_node("GestureBridge")
	# 批次V规格§3.2（V-C5）：主菜单两处确认迁移 Game.confirm → 统一确认条——spy 夹具注册到
	# autoload Game（注册路径；未挂接兜底路径归 test_v_game_confirm）
	ssp = StripSpy.new()
	add_child(ssp)
	game.call("attach_strip", ssp)

	# 环境重置：删标记与存档，内存数据回默认（next_chapter=1）
	_cleanup()
	save.load_game()

	# ---- 1. 场景文件存在且可实例化，节点结构与契约一致（image8 布局）----
	check(ResourceLoader.exists(SCENE_PATH), "main_menu.tscn 存在")
	if not ResourceLoader.exists(SCENE_PATH):
		finish()
		return
	var container: Control = Control.new()
	add_child(container)
	var menu: Node = load(SCENE_PATH).instantiate()
	container.add_child(menu)
	await process_frame  # _ready 延迟至下一帧（T03 实测经验）
	# 批次 AF 终审备案族（语言钉扎先例=6411fae o_catalog_shop）：autoload _ready 推迟至树激活，
	# 须等一帧后钉 zh——用户真实存档现 language=en，不钉则标题等文案断言呈 en 态假红。
	# 编译窗安全：经节点查找而非全局名（_script 模式 autoload 全局名编译期未注册）。
	var i18n_node: Variant = get_root().get_node_or_null("I18n")
	if i18n_node != null:
		i18n_node.call("set_language", "zh")

	check(menu is Control, "根节点为 Control")
	check(menu.get_node_or_null("Background") is TextureRect, "Background(TextureRect) 存在")
	# image8：标题与按钮在左侧竖向面板内
	var left_panel: Node = menu.get_node_or_null("LeftPanel")
	check(left_panel is Control, "LeftPanel(左侧竖向菜单区) 存在且为 Control")
	if left_panel != null:
		check((left_panel as Control).anchor_left == 0.0, "LeftPanel 锚定左侧")
		check((left_panel as Control).anchor_top == 0.0, "LeftPanel 锚定顶部")
		check((left_panel as Control).anchor_bottom == 1.0, "LeftPanel 上下撑满（竖向通栏）")
		check(absf((left_panel as Control).anchor_right - 0.42) < 0.001,
			"M-B：LeftPanel anchor_right==0.42（宽 483.8≥弧顶 440+AA，原 0.34，M 批等价替换）")
	var title_label: Node = menu.get_node_or_null("LeftPanel/Title")
	check(title_label is Label, "Title(Label) 在 LeftPanel 上方")
	if title_label != null:
		check_eq((title_label as Label).text, "千年一榫", "标题文本为「千年一榫」（zh 钉扎态直通）")
	# ---- J3-1（C1）：标题马善政书法金黄放大 + 左栏弧形毛玻璃底衬 ----
	if title_label != null:
		var tl: Label = title_label as Label
		check(tl.has_theme_font_override("font"), "C1：标题用马善政override字体（场景自带 ttf ext_resource）")
		var tfont: Font = tl.get_theme_font("font")
		check(tfont != null and String(tfont.resource_path).ends_with("MaShanZheng-Regular.ttf"), "C1：标题override字体指向马善政")
		check_eq(tl.get_theme_font_size("font_size"), 64, "M-B：标题字号 64（tscn 起步档；运行时 _fit_title 4px 步降档至 16 角点校验通过，原 40 断言 M 批等价替换）")
		check(tl.get_theme_constant("outline_size") == 10, "M-B：标题描边 outline_size==10（深墨棕描边，保证金底可读）")
		check(tl.has_theme_color_override("font_outline_color"), "M-B：标题描边色 override 存在")
		check(not tl.clip_text, "L-B：标题 clip_text=false（硬裁切已删，L4 根因主消除点）")
		# 原 K2-1「offset 落弧形安全区」断言（:97）删除——L-B 标题区重构（offset 88/-24/176），
		# 不裁切语义由 test_menu_ellipse ⑥「font.get_string_size(文本)≤标签盒宽」可计算断言承接（spec §6.3）。
		check(tl.has_theme_color_override("font_color"), "C1：标题金黄字色 override（#F5C542 近似渐变填充）")
		check(tl.has_theme_color_override("font_shadow_color"), "C1：标题棕投影 override（#8B5A1B 近似渐变）")
	var arc: Node = menu.get_node_or_null("LeftPanel/EllipsePanel")
	check(arc is Panel, "L-B：左栏椭圆容器 EllipsePanel 存在（ArcPanel 更名）")
	if arc != null:
		check((arc as Control).mouse_filter == Control.MOUSE_FILTER_PASS, "K9：EllipsePanel mouse_filter=PASS（hover 可判定）")
		check((arc as Panel).has_meta("hover_glow"), "K9：EllipsePanel 已挂 hover_glow meta")
		var asb: StyleBoxFlat = (arc as Control).get_theme_stylebox("panel") as StyleBoxFlat
		check(asb != null and absf(asb.bg_color.a - 0.70) < 0.001, "M-B：容器 alpha==0.70（70% 不透明拍板，原 [0.60,0.70] 档断言 M 批等价替换）")
		# N5（2026-09-09 用户反馈：圆弧调深棕）：底色取值收敛到两常量之一（深/浅主题各一），
		# 调深后仍单一参数源（α 断言上条不变，RGB 档值断言在 test_menu_ellipse 常量段）。
		var n5_cmap: Dictionary = (load("res://scenes/menu/main_menu.gd") as GDScript).get_script_constant_map()
		var n5_sb: Color = asb.bg_color
		check(n5_sb.is_equal_approx(n5_cmap["ARC_COLOR_DARK"] as Color),
			"AB-3 等价改写：容器 StyleBox 底色恒 ARC_COLOR_DARK（深浅机制删除，深棕为唯一参数源）")
		check(asb != null and asb.corner_radius_top_right == 0 and asb.corner_radius_bottom_right == 0, "L-B：StyleBox 圆角归零（形状由材质 SDF 承担，spec §6.1）")
		check(asb != null and asb.border_width_top == 0, "L-B：StyleBox 边框归零（顶缘高光由材质 rim 承担，spec §6.1）")
		check(asb != null and asb.shadow_size == 0, "L-B：StyleBox shadow_size==0（外投影由材质 SDF 承担，spec §6.1）")
	# L-B（spec §6.2）：VBox 已删，三钮直挂 LeftPanel 等 φ 绝对定位（旧 K2-6 容器结构断言反转）
	var vbox: Node = menu.get_node_or_null("LeftPanel/VBox")
	check(vbox == null, "L-B：VBox 已删（三钮直挂 LeftPanel 绝对定位）")
	var start_btn: Node = menu.get_node_or_null("LeftPanel/StartButton")
	var load_btn: Node = menu.get_node_or_null("LeftPanel/LoadButton")
	var quit_btn: Node = menu.get_node_or_null("LeftPanel/QuitButton")
	check(start_btn is Button, "StartButton(Button) 存在（直挂 LeftPanel）")
	check(load_btn is Button, "LoadButton(加载存档 Button) 直挂 LeftPanel 存在（L-B 贴弧布局 + Q&A12）")
	check(menu.get_node_or_null("LeftPanel/SettingsButton") == null, "K2-6/Q3：主菜单左列无第二设置入口（唯一入口=右上角 GlobalUI）")
	check(quit_btn is Button, "QuitButton(Button) 存在（直挂 LeftPanel）")
	# K2-6「恰好 3 钮+顺序」语义承接：LeftPanel 直挂子节点中 Button 相对顺序不变
	var btn_names: Array = []
	if left_panel != null:
		for c: Node in (left_panel as Control).get_children():
			if c is Button:
				btn_names.append(String(c.name))
	check_eq(btn_names, ["StartButton", "LoadButton", "QuitButton"], "L-B：LeftPanel 内三钮恰好且保序（承接 K2-6 VBox 子断言）")
	if start_btn != null:
		check_eq((start_btn as Button).text, "开始游戏", "StartButton 文本")
	if load_btn != null:
		check_eq((load_btn as Button).text, "加载存档", "LoadButton 文本")
	if quit_btn != null:
		check_eq((quit_btn as Button).text, "退出", "QuitButton 文本")
	# L-B（L3 等长，spec §6.2）→ M-B（拍板 #7 加大 200×56，M 批等价替换原 160 等长断言）
	if start_btn != null:
		check_eq((start_btn as Button).custom_minimum_size, Vector2(200, 56), "M-B：StartButton 尺寸 200×56（拍板 #7，M 批等价替换）")
	if load_btn != null:
		check_eq((load_btn as Button).custom_minimum_size, Vector2(200, 56), "M-B：LoadButton 尺寸 200×56（拍板 #7，M 批等价替换）")
	if quit_btn != null:
		check_eq((quit_btn as Button).custom_minimum_size, Vector2(200, 56), "M-B：QuitButton 尺寸 200×56（拍板 #7，M 批等价替换）")
	# M-A（spec §3.1/§4.2，2026-09-07）：7 处按钮图标清理——J3-5 旧图标断言按新验收反转留痕。
	if start_btn != null:
		check((start_btn as Button).icon == null, "M-A：开始/新游戏按钮图标已删（icon==null，J3-5 C2+ 反转留痕）")
	if load_btn != null:
		check((load_btn as Button).icon == null, "M-A：加载/载入存档按钮图标已删（icon==null，J3-5 C2+ 反转留痕）")
	# K2-5：左下「手势交互操作提示」面板已删除（清单仍由全局 GestureHUD 承载，功能不丢）
	check(menu.get_node_or_null("LeftPanel/GestureTipPanel") == null, "K2-5：左下手势提示面板已删除")

	# ---- 2. 背景固定为大厅背景图（2026-08-26 修正：不再用关卡章节背景）----
	var bg: Node = menu.get_node_or_null("Background")
	if bg != null:
		check(ResourceLoader.exists(BG_MENU_PATH), "前置：大厅背景资源已存在（T13 素材导入）")
		check((bg as TextureRect).visible == true, "背景存在时 Background 显示")
		var tex: Texture2D = (bg as TextureRect).texture
		check(tex != null and tex.resource_path == BG_MENU_PATH, "清单·背景：Background 贴图固定为 bg_menu.png（大厅背景，非章节背景）")

	# ---- 3. 无存档态（C2 两态之一）：开始游戏亮 + 加载存档灰禁，不路由 ----
	if load_btn != null:
		check(bool(save.is_first_launch()), "前置：标记已删，处于无存档状态")
		check_eq((start_btn as Button).text, "开始游戏", "C2：无存档态 StartButton 文本=开始游戏（enabled）")
		check_eq((load_btn as Button).text, "加载存档", "C2：无存档态 LoadButton 文本=加载存档")
		check_eq((load_btn as Button).disabled, true, "清单5：无存档时加载存档按钮禁用")
		var state_before_load: int = int(game.current_state())
		(load_btn as Button).pressed.emit()
		check_eq(int(game.current_state()), state_before_load, "清单5：无存档点加载存档不路由（禁用态兜底）")

	# ---- 4. 首次进入分流：无标记 → 创建标记 + 路由 OPENING_MOVIE ----
	check(bool(save.is_first_launch()), "前置：仍处于首次进入")
	check(int(game.current_state()) != ST_OPENING_MOVIE, "前置：当前不在开场动画状态")
	var s4_confirms: int = (ssp.call("get_confirm_calls") as Array).size()
	if start_btn != null:
		(start_btn as Button).pressed.emit()
	check(FileAccess.file_exists(FLAG_PATH), "清单1：点开始后标记文件已创建")
	check(not bool(save.is_first_launch()), "清单1：创建后 is_first_launch 为 false")
	check_eq(int(game.current_state()), ST_OPENING_MOVIE, "清单1：状态路由至 OPENING_MOVIE")
	check_eq((ssp.call("get_confirm_calls") as Array).size(), s4_confirms,
		"批次V§3.2：无档开始=直接开场（不弹确认条，分流语义保持）")

	# ---- 5. 有存档两态（C2）：断点继续路由由 LoadButton 承接；StartButton=新游戏只弹确认框 ----
	save.advance_progress(1)  # next_chapter: 1 → 2；progress_changed 触发两态刷新
	check_eq(int(save.get_progress()["next_chapter"]), 2, "前置：推进后 next_chapter==2")
	check_eq((start_btn as Button).text, "新游戏", "C2：有存档时开始游戏→新游戏（无「开始游戏」文本）")
	check_eq((load_btn as Button).text, "载入存档", "C2：有存档时 LoadButton 文本=载入存档")
	check_eq((load_btn as Button).disabled, false, "C2：有存档时载入存档可用")
	# 批次 AA W9-7 前置（规格 §12 P3-8）：_resume_from_save 现按「目标章节数据存在性」零路由
	# （防 next_chapter 指向缺档章节时落进空场占位关）——本测试此前从未扫描关卡库，补扫描使
	# 「有档即路由」断言在真实前提（第 2 关数据在库）下成立；同时锁死前置本身（防静默漂移）。
	lib.call("scan_directory", "res://levels_data")
	check(not lib.call("get_level", int(save.get_progress()["next_chapter"])).is_empty(),
		"W9-7 前置：目标章节（next_chapter）关卡数据在库")
	(load_btn as Button).pressed.emit()
	check_eq(int(game.current_state()), ST_LEVEL, "C2：有档点载入存档路由至 LEVEL（断点继续，原清单2语义）")
	check_eq(int(game.context().get("chapter", -1)), 2, "C2：断点继续 ctx.chapter==2")
	check(bool(game.is_replay()) == false, "C2：断点继续 ctx.replay==false（非重玩）")
	# 新游戏（StartButton 有档态）点击 = 只弹统一确认条防误触，不清档不路由
	# 批次V规格§3.2（V-C5）等价替换留痕：NewGameDialog 节点退役，确认请求经 Game.confirm →
	# TopStrip.push_confirm 承载；旧「GlassDialog 实例 script 比较/节点可见性/正文 Label」断言
	# 等价替换为「spy 收到逐字文案 + 回调透传」（红灯期防挂死闸门随节点退役一并退役）。
	var ng_calls: int = (ssp.call("get_confirm_calls") as Array).size()
	var st_before_new: int = int(game.current_state())
	(start_btn as Button).pressed.emit()
	var ng_recs: Array = ssp.call("get_confirm_calls")
	check_eq(ng_recs.size(), ng_calls + 1, "批次V§3.2：有档点新游戏弹出统一确认条（Game.confirm 恰 1 条）")
	var ng_ok: Callable = Callable()
	if ng_recs.size() == ng_calls + 1:
		var ng_rec: Array = ng_recs[ng_recs.size() - 1]
		check_eq(String(ng_rec[0]), "新游戏将清除当前存档，确定重新开始吗？", "K4-1→批次V§3.2：确认文案逐字沿用现占位（TODO 待用户，不新编）")
		check((ng_rec[1] as Callable).is_valid(), "批次V§3.2：确认回调透传有效（清档+进开场）")
		check(not (ng_rec[2] as Callable).is_valid(), "批次V§3.2：取消缺省空回调（零副作用语义保持）")
		ng_ok = ng_rec[1]
	check_eq(int(game.current_state()), st_before_new, "C2：确认前不路由（仅弹条）")
	check_eq(int(save.get_progress()["next_chapter"]), 2, "C2：确认前存档进度不变（未清档）")

	# ---- 6. 新游戏确认：reset_for_new_game 清档（含删标记）→ 路由 OPENING_MOVIE 重走开场 ----
	# 批次V§3.2 等价替换：旧 dlg.emit_signal("confirmed") 改由 spy 记录的 on_confirmed 回调驱动
	#（模拟统一确认条「确认」钮触发）。
	if ng_ok.is_valid():
		ng_ok.call()
	check_eq(int(save.get_talent()), 500, "C2：确认后天赋回默认 500（清档）")
	check_eq(int(save.get_progress()["next_chapter"]), 1, "C2：确认后进度重置（next_chapter==1）")
	check(not bool(save.is_first_launch()), "C2：确认后 first_launch 标记已重建（新周目=有档态，载入存档可用；开场重播由路由保证）")
	check_eq(int(game.current_state()), ST_OPENING_MOVIE, "C2：确认后路由至 OPENING_MOVIE")

	# ---- 7. 已全部通关分流：next_chapter>5 → 载入存档引导去图鉴（新游戏语义见 §5/§6）----
	save.mark_first_launch()  # 幂等确保「有存档」态（P1-1 修后 §6 确认时标记已重建）
	save.advance_progress(5)  # next_chapter → 6；再次触发两态刷新
	check_eq(int(save.get_progress()["next_chapter"]), 6, "前置：第5关后 next_chapter==6")
	check_eq((start_btn as Button).text, "新游戏", "C2：全通关有档态仍为两态文本")
	(load_btn as Button).pressed.emit()
	check_eq(int(game.current_state()), ST_CATALOG, "清单7：全通关后载入存档 → 路由 CATALOG")

	# ---- 8.（K2-6 删除）左列设置按钮已移除：唯一入口=GlobalUI 右上角常驻（断言见 §1/K-C 清单与 test_window_k）----

	# ---- 9. 退出按钮（K8→批次V§3.2）：连接存在；点击弹统一确认条（不直接 quit），确认后 stop+quit ----
	if quit_btn != null:
		var conns2: Array = (quit_btn as Button).pressed.get_connections()
		check(conns2.size() >= 1, "清单4：QuitButton.pressed 已连接")
		# K8：点退出=弹「退出《千年一榫》？」确认（与窗口关闭同流程）→ 批次V§3.2 迁移 Game.confirm
		#（ExitDialog 节点退役，文案逐字断言由 spy 承接）。无头环境绝不触发 on_confirmed（会真 quit）。
		var q_calls: int = (ssp.call("get_confirm_calls") as Array).size()
		var st_before_quit: int = int(game.current_state())
		(quit_btn as Button).pressed.emit()
		var q_recs: Array = ssp.call("get_confirm_calls")
		check_eq(q_recs.size(), q_calls + 1, "K8→批次V§3.2：点退出弹出统一确认条（不直接退出）")
		if q_recs.size() == q_calls + 1:
			var q_rec: Array = q_recs[q_recs.size() - 1]
			check_eq(String(q_rec[0]), "退出《千年一榫》？", "K8：退出确认文案逐字（spec §4.3 定稿文案）")
			check((q_rec[1] as Callable).is_valid(), "K8：确认回调已接线（stop+quit，无头环境不触发）")
			var q_cancel: Callable = q_rec[2]
			if q_cancel.is_valid():
				q_cancel.call()   # 取消路径（本场景缺省空回调）——零副作用
		check_eq(int(game.current_state()), st_before_quit, "K8：确认/取消前状态不变")
	bridge.stop_gesture_process()
	check(true, "清单4：GestureBridge.stop_gesture_process() 调用安全（无进程时不崩溃）")

	# ---- 10. 背景与进度解耦：next_chapter=6 时实例化不崩溃，背景仍为大厅背景 ----
	var menu2: Node = load(SCENE_PATH).instantiate()
	container.add_child(menu2)
	await process_frame
	var bg2: Node = menu2.get_node_or_null("Background")
	if bg2 != null:
		var tex2: Texture2D = (bg2 as TextureRect).texture
		check(tex2 != null and tex2.resource_path == BG_MENU_PATH, "清单8：任意进度下背景恒为大厅背景（不再随章节变化）")
	else:
		check(false, "清单8：menu2 Background 存在")

	_cleanup()
	game.call("attach_strip", null)   # 批次V§3.2：卸下统一确认条 spy，还原 autoload 挂接态
	ssp.queue_free()
	finish()
