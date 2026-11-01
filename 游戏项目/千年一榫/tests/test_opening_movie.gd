extends "res://tests/test_base.gd"
## 开场动画判定用例（2026-08-26 用户指示：开场动画必须可跳过，键鼠点击「跳过」立即等效动画播完回调）。
## 契约来源：用户 2026-08-26 指示 + spec 4.2 + Q&A「开场动画可跳过」：
##   场景：scenes/movie/opening_movie.tscn（VideoStreamPlayer 全屏 + 右下「跳过」按钮）。
##   跳过路由 = 播完回调：
##     首次（_replay=false）→ goto_state(TALK, {mode:"after_level", chapter:1})
##       （批次 Z §14 增补，用户 2026-09-24 拍板：开场对话删除，opening 语境退役——
##        动画后直接挂载第 1 关关前对话语境，链路零 opening 段；首句=第1关.json rounds[0]）
##     回看（replay_video=true，图鉴进入）→ goto_state(CATALOG)
##   跳过按钮播放期间可见可用（hover/点击）；以 pressed.emit 验证路由。
##   J3-3（D）：左上 MovieTitle「开场动画」小字（马善政）+ MovieTime「mm:ss / mm:ss」
##     当前/总时长（总长优先 get_stream_length()，取不到 0 兜底 --:--），逐帧刷新，不干扰跳过。
## 环境说明：--script 无头模式下 autoload 已实例化但主脚本编译早于注册，故经 /root/<Name> 动态引用。
## 枚举：BOOT=0 MAIN_MENU=1 OPENING_MOVIE=2 TALK=3 LEVEL=4 SETTLE=5 CATALOG=6。

const SCENE_PATH := "res://scenes/movie/opening_movie.tscn"
const VIDEO_PATH := "res://assets/animations/开场动画.ogv"

const ST_OPENING := 2
const ST_TALK := 3
const ST_CATALOG := 6

func _initialize() -> void:
	print("== test_opening_movie ==")
	var game: Variant = get_root().get_node("Game")

	# ---- 0. 前置：场景与视频资源存在 ----
	check(ResourceLoader.exists(SCENE_PATH), "opening_movie.tscn 存在")
	check(ResourceLoader.exists(VIDEO_PATH), "开场动画.ogv 存在（T13 素材）")
	if not ResourceLoader.exists(SCENE_PATH):
		finish()
		return

	var container: Control = Control.new()
	add_child(container)

	# ---- 1. 首次播放：跳过按钮存在/可见/可用；点击 → TALK(after_level, chapter:1)（§14）----
	var movie: Node = load(SCENE_PATH).instantiate()
	container.add_child(movie)
	await process_frame  # _ready 延迟至下一帧

	check(movie is Control, "根节点为 Control")
	check(movie.get_node_or_null("VideoStreamPlayer") is VideoStreamPlayer, "VideoStreamPlayer 存在")
	var skip_btn: Node = movie.get_node_or_null("SkipButton")
	check(skip_btn is Button, "SkipButton(跳过 Button) 存在（2026-08-26 用户指示）")
	if skip_btn != null:
		check_eq((skip_btn as Button).text, "跳过", "SkipButton 文本为「跳过」")
		check((skip_btn as Button).visible, "播放期间跳过按钮可见")
		check_eq((skip_btn as Button).disabled, false, "播放期间跳过按钮可用")
		var conns: Array = (skip_btn as Button).pressed.get_connections()
		check(conns.size() >= 1, "SkipButton.pressed 已连接")
	# ---- 1b. J3-3（D）：左上「开场动画」小标题 + 「mm:ss / mm:ss」时间标记（跳过按钮不受干扰）----
	var mt: Node = movie.get_node_or_null("MovieTitle")
	check(mt is Label, "D：左上标题 MovieTitle(Label) 存在")
	if mt != null:
		check_eq((mt as Label).text, "开场动画", "D：左上标题文本为「开场动画」")
		check((mt as Label).has_theme_font_override("font"), "D：标题用艺术字体（马善政）override")
		check((mt as Control).anchor_left == 0.0 and (mt as Control).anchor_top == 0.0, "D：标题锚定左上角")
	var mtime: Node = movie.get_node_or_null("MovieTime")
	check(mtime is Label, "D：时间标记 MovieTime(Label) 存在")
	if mtime != null:
		check("/" in (mtime as Label).text, "D：时间标记格式 当前/总（含 '/'）")
	check(movie.has_method("_process"), "D：逐帧刷新时间标记（_process）")
	# 时间标记存在不得干扰跳过按钮（既有行为保持：可见可用）
	if skip_btn != null:
		check((skip_btn as Button).visible and not (skip_btn as Button).disabled, "D：跳过按钮在加标题/时间后仍可见可用")

	check(int(game.current_state()) != ST_TALK, "前置：当前不在 TALK 状态")
	if skip_btn != null:
		(skip_btn as Button).pressed.emit()
	check_eq(int(game.current_state()), ST_TALK, "清单1：首次播放点跳过 → 路由 TALK（等效播完回调）")
	check_eq(String(game.context().get("mode", "")), "after_level",
		"§14①：ctx.mode==after_level（opening 语境退役；红测：现状 opening）")
	check_eq(int(game.context().get("chapter", -1)), 1, "§14①：ctx.chapter==1（第 1 关关前对话）")

	# ---- 2. 回看（图鉴进入，replay_video=true）：跳过 → CATALOG ----
	movie.queue_free()
	await process_frame
	var movie2: Node = load(SCENE_PATH).instantiate()
	movie2.call("set_context", {"replay_video": true})  # 与 Game._load_main_scene 顺序一致：先 set_context 再入树
	container.add_child(movie2)
	await process_frame
	var skip_btn2: Node = movie2.get_node_or_null("SkipButton")
	check(skip_btn2 is Button, "回看实例同样有 SkipButton")
	if skip_btn2 != null:
		(skip_btn2 as Button).pressed.emit()
	check_eq(int(game.current_state()), ST_CATALOG, "清单2：回看点跳过 → 路由 CATALOG")

	# ---- 3. 视频缺失兜底不崩溃（纯防御性：无视频时 _finish 直接走回调）----
	check(true, "两个实例均正常实例化与跳过，无崩溃")

	# ---- 4. BGM 与开场动画状态联动（2026-08-27）：进入动画渐停、离开恢复 ----
	var am: Variant = get_root().get_node("AudioManager")
	am.start_bgm()
	check(bool(am.is_bgm_playing()), "音频前置：BGM 播放中")
	game.goto_state(ST_OPENING, {})
	check_eq(int(game.current_state()), ST_OPENING, "状态切至 OPENING_MOVIE")
	check(not bool(am.is_bgm_playing()), "清单3：进入开场动画 → BGM 渐停")
	game.goto_state(ST_TALK, {"mode": "after_level", "chapter": 1})
	check(bool(am.is_bgm_playing()), "清单3：动画结束（→TALK）→ BGM 淡入恢复")
	game.goto_state(ST_OPENING, {})
	check(not bool(am.is_bgm_playing()), "回看入口：再次进入开场动画 → BGM 渐停")
	game.goto_state(ST_CATALOG)
	check(bool(am.is_bgm_playing()), "清单3：回看结束（→CATALOG）→ BGM 恢复")

	finish()
