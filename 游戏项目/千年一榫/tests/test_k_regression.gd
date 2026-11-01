extends "res://tests/test_base.gd"
## K-H（KH-1）跨批冒烟测试：批次 K（K-A~K-G）合流后的全局契约抽查。
## 契约来源：spec §十二/§十五 K-H、plan KH-1 断言清单。
## 纪律：新增组件一律 load() 比较（P2-5 class_name 时序防御）；场景 instantiate 不入树
## （_ready 不触发，避免 autoload/手势依赖）；toast spy 用独立 game 实例，不污染 autoload。

const SCENES := {
	"main": "res://scenes/main.tscn",
	"main_menu": "res://scenes/menu/main_menu.tscn",
	"settings": "res://scenes/settings/settings_panel.tscn",
	"shop": "res://scenes/shop/shop_panel.tscn",
	"talk": "res://scenes/dialog/talk_scene.tscn",
	"catalog": "res://scenes/catalog/catalog_scene.tscn",
	"level": "res://scenes/level/level_scene.tscn",
	"opening_movie": "res://scenes/movie/opening_movie.tscn",
}
const GLASS_SCRIPT := "res://scenes/shared/glass_dialog.gd"

func _initialize() -> void:
	print("== test_k_regression ==")

	# ---- 1) 8 场景路径存在 + instantiate（不入树）成功 ----
	var insts: Dictionary = {}
	for key: String in SCENES:
		var path: String = String(SCENES[key])
		var ok_exists: bool = ResourceLoader.exists(path)
		check(ok_exists, "KH-1 场景存在：%s（%s）" % [key, path])
		if ok_exists:
			var inst: Node = (load(path) as PackedScene).instantiate()
			check(inst != null, "KH-1 场景可实例化：%s" % key)
			if inst != null:
				insts[key] = inst
			else:
				continue
	# Main GlobalUI 挂接抽查（K-A/K-C：光晕/三钮/toast/关闭确认弹窗）
	if insts.has("main"):
		var m: Node = insts["main"]
		check(m.get_node_or_null("GlobalUI/ToastCenter") != null, "K-H：Main/GlobalUI/ToastCenter 存在（K4-2）")
		check(m.get_node_or_null("GlobalUI/GlowLayer") != null, "K-H：Main/GlobalUI/GlowLayer 存在（K9）")
		check(m.get_node_or_null("GlobalUI/WindowButtons") != null, "K-H：Main/GlobalUI/WindowButtons 存在（K8-4）")
		# 批次V规格§3.2（V-C6）等价替换留痕（原 K-H P2-1：ExitConfirmDialog 为 GlassDialog 实例断言，
		# 镜像 V-C5 对 main_menu.tscn 弹窗退役的处置）：窗口×确认弹窗节点退役，关闭确认改经
		# Game.confirm → TopStrip 统一确认条（文案/回调断言归 test_v_quit_and_boot.gd；
		# 本处锁「节点退役+脚本已接线+组件文件本体保留」）。
		check(m.get_node_or_null("GlobalUI/ExitConfirmDialog") == null,
			"批次V§3.2：窗口×确认弹窗节点已退役（确认改经统一弹条）")
		var main_src_kh: String = FileAccess.get_file_as_string("res://scenes/main.gd")
		check(main_src_kh.contains("Game.confirm"), "批次V§3.2：main.gd 已接线 Game.confirm")
		check(ResourceLoader.exists(GLASS_SCRIPT), "批次V§3.2：旧弹窗组件文件本体保留不删（settle_scene 先例）")
	# 主菜单抽查（K2-6 单设置入口 + K4-1 弹窗替换）
	if insts.has("main_menu"):
		var mm: Node = insts["main_menu"]
		check(mm.get_node_or_null("LeftPanel/SettingsButton") == null, "K-H：主菜单左列无第二设置入口（K2-6；L-B 删 VBox 后路径同步）")
		# 批次V规格§3.2（V-C5）等价替换留痕（原 K4-1：NewGameDialog 为 GlassDialog 实例断言）：
		# 主菜单确认弹窗节点退役，新游戏确认改经 Game.confirm → TopStrip 统一确认条
		#（接线/文案/回调断言归 test_v_confirm_migration.gd；本处锁「节点退役+脚本已接线」）。
		var mm_src: String = FileAccess.get_file_as_string("res://scenes/menu/main_menu.gd")
		check(mm.get_node_or_null("NewGameDialog") == null, "批次V§3.2：主菜单确认弹窗节点已退役（确认改经统一弹条）")
		check(mm_src.contains("Game.confirm"), "批次V§3.2：main_menu.gd 已接线 Game.confirm")
	# 图鉴抽查（K7-7 单层视频；M-F 等价替换留痕 2026-09-08：全屏层按 M-F 验收回归为
	# CanvasLayer 结构、ControlBar 迁为 VideoPreview 悬浮子层——行为语义不变、路径同步）
	if insts.has("catalog"):
		var ca: Node = insts["catalog"]
		check(ca.get_node_or_null("VideoFullscreenLayer") is CanvasLayer,
			"K-H→M-F：VideoFullscreenLayer 回归（CanvasLayer，K7-7「已删」断言按 M-F 验收反转）")
		check(ca.get_node_or_null("Body/CenterMount/VideoPreview/ControlBar/BarRow/PlayPauseBtn") != null,
			"K-H→M-F：ControlBar/PlayPauseBtn 存在（悬浮层新路径，行为语义不变）")
	# 关卡抽查（K6-7 聚焦钮 + K4-2 FailToast 迁移）
	if insts.has("level"):
		var lv: Node = insts["level"]
		check(lv.get_node_or_null("TopBar/Buttons/FocusButton") is Button, "K-H：TopBar/Buttons/FocusButton 存在（K6-7）")
		check(lv.get_node_or_null("FailToast") == null, "K-H：FailToast 节点不存在（K4-2 已迁 Game.toast）")

	# ---- 2) 批次 K 六组件可加载 ----
	for comp: String in ["res://scripts/window_manager.gd", "res://scripts/focus_fx.gd",
		"res://scenes/shared/glass_dialog.gd", "res://scenes/shared/toast_center.gd",
		"res://scenes/shared/window_buttons.tscn", "res://assets/shaders/hover_glow.gdshader"]:
		check(ResourceLoader.exists(comp) and load(comp) != null, "K-H 组件可加载：%s" % comp)

	# ---- 3) 跨批契约抽查 ----
	var cat: GDScript = load("res://data/skin_catalog.gd")
	check_eq((cat.call("get_skins") as Array).size(), 47, "K-H：SkinCatalog 共 47 项（5 原创+42 占位）")
	var sm: Node = root.get_node("SaveManager")
	for api: String in ["set_preferred_skin", "apply_contextual_skin", "restore_preferred_skin", "unlock_origin_skin"]:
		check(sm.has_method(api), "K-H：SaveManager 契约 API %s（K-D）" % api)

	# ---- 4) toast spy 注入断言文案（Game.toast → ToastCenter.push 转发链） ----
	var game: Node = load("res://autoload/game.gd").new()
	add_child(game)
	var spy: Node = load("res://tests/fixtures/toast_spy.gd").new()
	add_child(spy)
	game.call("attach_toast", spy)
	game.call("toast", "无法对接", "warn")
	var calls: Array = spy.call("get_calls")
	check_eq(calls.size(), 1, "K-H：Game.toast 转发 spy 收到 1 条")
	if calls.size() == 1:
		check_eq(String(calls[0][0]), "无法对接", "K-H：toast 文案透传（K4-2/K-G 迁移链）")
		check_eq(String(calls[0][1]), "warn", "K-H：toast level 透传")
	game.queue_free()
	spy.queue_free()

	finish()
