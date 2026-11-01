extends "res://tests/test_base.gd"
## 批次 AF 中英切换·4 项实机反馈修复（TDD 红测先行，2026-11-01）。
## 反馈与修复口径（任务书）：
##   ① 设置按钮部分情况不切换——常驻 GlobalUI 设置钮（main.gd）任意状态（含设置面板
##      开→切→关、FINALE/LEVEL 态）切语言即时刷新（本件红→绿+守护）。
##   ② 图鉴开场回放无英文字幕——抽共享组件 scenes/shared/video_subtitle_overlay.gd
##     （输入=VideoStreamPlayer+字幕 JSON 路径；几何锚定 KEEP_ASPECT_CENTERED 内容矩形；
##      白字黑描边/中文烧录字幕下方/双语常显/mouse_filter=IGNORE）；opening_movie 与
##      图鉴内嵌播放器（catalog_scene）共用；全屏形态常显且贴内容矩形。
##   ③ 对话中途切语言当前句不刷新——talk_controller 订阅 language_changed 即时重绘
##      当前句正文/双名牌/跳过钮/「点击 / 空格继续」提示。
##   ④ 跳过剧情按钮没翻译——根因=opening_movie.tscn「跳过」为纯静态文本从未 t() 覆写
##      且 ui_en.json 缺「跳过」「开场动画」键（MovieTitle 同病）；t() 覆写+补键修复。
## 细查固化段：t() 字面量键全命中合并表（en 模式零中文回退漏键）+ 消费键 en 值零 CJK
## 残留（豁免作品名「千年一榫」）。
## 清档纪律：test_af_i18n 同款备份/还原+逐字节自检；测试档 gesture 双关（零 spawn 零
## 摄像头红线）。零摄像头零窗口（纯无头 --script）。

const SUB_GD := "res://scenes/shared/video_subtitle_overlay.gd"
const SUB_JSON := "res://assets/animations/opening_subtitles_en.json"
const MOVIE_TSCN := "res://scenes/movie/opening_movie.tscn"
const MOVIE_GD := "res://scenes/movie/opening_movie.gd"
const CATALOG_TSCN := "res://scenes/catalog/catalog_scene.tscn"
const CATALOG_GD := "res://scenes/catalog/catalog_scene.gd"
const TALK_TSCN := "res://scenes/dialog/talk_scene.tscn"
const TALK_GD := "res://scenes/dialog/talk_controller.gd"
const MAIN_TSCN := "res://scenes/main.tscn"
const MAIN_GD := "res://scenes/main.gd"
const UI_EN_PATH := "res://assets/i18n/ui_en.json"
const CONTENT_EN_PATH := "res://assets/i18n/content_en.json"

const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const TALK_TMP := "user://_af_fixes_talk.json"
const BK_PREFIX := "user://_af_fixes_backup_"
const WATCHED: Array = [SAVE_PATH, FLAG_PATH, TALK_TMP]
const AUTOLOAD_NAMES: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
const ST_MAIN_MENU := 1
const ST_LEVEL := 4
const ST_FINALE := 7

var _pre_save_text := ""

func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _del(p: String) -> void:
	var a: String = _abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _selfheal() -> void:
	var healed: int = 0
	for p: String in WATCHED:
		var bk := BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			_del(p)
			DirAccess.copy_absolute(_abs(bk), _abs(p))
			DirAccess.remove_absolute(_abs(bk))
			healed += 1
	if healed > 0:
		print("EVID|selfheal|af_fixes|restored=%d" % healed)

func _backup_user() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(SAVE_PATH)
	for p: String in WATCHED:
		if FileAccess.file_exists(p):
			var bk := BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_abs(p), _abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)
			DirAccess.remove_absolute(_abs(p))

func _restore_user() -> void:
	for c: Node in root.get_children():
		if not AUTOLOAD_NAMES.has(String(c.name)):
			c.free()
	# 还原「有界双试」：防未决异步存档（防抖 Timer/延迟收口）在复制后落盘的竞态——
	# 首试读回不等则再试一次（红线：同一命令最多重试 2 次），仍不等才记红。
	var post := ""
	for attempt: int in range(2):
		for p: String in WATCHED:
			_del(p)
			var bk := BK_PREFIX + p.get_file()
			if FileAccess.file_exists(bk):
				DirAccess.copy_absolute(_abs(bk), _abs(p))
		post = FileAccess.get_file_as_string(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else ""
		if post == _pre_save_text:
			break
	for p: String in WATCHED:
		var bk2 := BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk2):
			DirAccess.remove_absolute(_abs(bk2))
	var real_sm: Node = root.get_node_or_null("SaveManager")
	if real_sm != null:
		real_sm.load_game()
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|af_fixes|files=%d" % WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

## 写测试档：gesture 双关（零 spawn 红线）+ 无 language 键（缺省 zh 判定）。
func _write_test_save() -> void:
	var data: Dictionary = {
		"save_version": 2,
		"progress": {"cleared": [], "next_chapter": 1, "watched_opening": false, "level_progress": {}},
		"settings": {"gesture_input": false, "gesture_camera_enabled": false, "gesture_hud_visible": true},
		"talent": 500,
		"skins": {"owned": ["skin_default"], "equipped": "skin_default"},
	}
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()

func _sync_sm() -> void:
	var sm: Node = root.get_node_or_null("SaveManager")
	if sm != null:
		sm.load_game()

func _initialize() -> void:
	print("== test_af_i18n_fixes ==")
	_selfheal()
	_backup_user()
	_write_test_save()
	_sync_sm()
	var i18n: Node = root.get_node_or_null("I18n")
	var game: Node = root.get_node_or_null("Game")
	var bridge: Node = root.get_node_or_null("GestureBridge")
	if bridge != null:
		bridge.call("_set_state", 1)   # READY 基线（test_v_quit_and_boot 同款，抑制 UNAVAILABLE 噪声）
	check(i18n != null, "AF2-0：I18n autoload 可达")
	check(game != null, "AF2-0：Game autoload 可达")
	_s_section()
	if i18n == null or game == null:
		finish()
		return
	await _section_1_settings_button(i18n, game)
	await _section_2_subtitles(i18n)
	await _section_3_talk(i18n)
	_section_4_scan()
	i18n.call("set_language", "zh")
	await process_frame
	finish()   # 内部唯一一次 _restore_user

# ================================================================ S 段：结构锚
func _s_section() -> void:
	var mov_src: String = FileAccess.get_file_as_string(MOVIE_GD) if FileAccess.file_exists(MOVIE_GD) else ""
	check(mov_src.contains("I18n.t(\"跳过\")"), "AF2-S1：opening_movie 跳过钮 t() 覆写（④）")
	check(mov_src.contains("I18n.t(\"开场动画\")"), "AF2-S2：opening_movie 标题 t() 覆写（④）")
	check(FileAccess.file_exists(SUB_GD), "AF2-S3：共享组件 scenes/shared/video_subtitle_overlay.gd 在位（②）")
	var ui: Variant = JSON.parse_string(FileAccess.get_file_as_string(UI_EN_PATH)) if FileAccess.file_exists(UI_EN_PATH) else null
	var tbl: Dictionary = (ui as Dictionary).get("翻译", {}) if ui is Dictionary else {}
	for pair: Array in [["跳过", "Skip"], ["开场动画", "Opening Movie"], ["效果：", "Effect:"],
			["未检出摄像头", "No camera detected"], ["神通谱", "Divine Powers"]]:
		check_eq(String(tbl.get(String(pair[0]), "")), String(pair[1]),
			"AF2-S4：ui_en 补键 %s→%s" % [String(pair[0]), String(pair[1])])
	var cat_src: String = FileAccess.get_file_as_string(CATALOG_GD) if FileAccess.file_exists(CATALOG_GD) else ""
	check(cat_src.contains("video_subtitle_overlay.gd"), "AF2-S5：catalog 接入共享组件（源码锚，②）")
	var talk_src: String = FileAccess.get_file_as_string(TALK_GD) if FileAccess.file_exists(TALK_GD) else ""
	check(talk_src.contains("language_changed.is_connected(_on_language_changed)"),
		"AF2-S6：talk_controller 订阅 language_changed（③源码锚）")
	check(talk_src.contains("func _exit_tree"), "AF2-S7：talk_controller _exit_tree 显式退订（③信号卫生锚）")
	var main_src: String = FileAccess.get_file_as_string(MAIN_GD) if FileAccess.file_exists(MAIN_GD) else ""
	check(main_src.contains("I18n.language_changed.is_connected(_on_language_changed)"),
		"AF2-S8：main.gd 常驻件订阅在位（①结构性守护）")

# ============================================ ① 设置钮任意状态即时刷新
func _section_1_settings_button(i18n: Node, game: Node) -> void:
	i18n.call("set_language", "zh")
	var main1: Node = (load(MAIN_TSCN) as PackedScene).instantiate()
	add_child(main1)
	await process_frame
	await process_frame
	var sb: Button = main1.get_node_or_null("GlobalUI/SettingsButton") as Button
	check(sb != null, "AF2-1A：GlobalUI/SettingsButton 可达")
	if sb == null:
		main1.free()
		return
	check_eq(String(sb.text), "设置", "AF2-1B：zh 基线（_ready t() 直通）")
	check(i18n.is_connected("language_changed", Callable(main1, "_on_language_changed")),
		"AF2-1C：main 订阅 language_changed 在位（freed 重连丢失防线锚）")
	i18n.call("set_language", "en")
	check_eq(String(sb.text), "Settings", "AF2-1D：MAIN_MENU 态切 en → 同帧即时刷新")
	# 面板开→切→关（用户实机主链路）
	game.call("open_overlay", "settings")
	await process_frame
	check(bool(game.call("is_settings_open")), "AF2-1E：设置面板已开（前置）")
	var panel: Node = game.get("_overlay_instance")
	var tl: Label = null
	if panel != null:
		tl = panel.get_node_or_null("Panel/VBox/Title") as Label
	check(tl != null, "AF2-1F：面板标题节点可达")
	if tl != null:
		check_eq(String(tl.text), "Settings", "AF2-1G：面板 en 挂载基线（重开即英文）")
	i18n.call("set_language", "zh")
	check_eq(String(sb.text), "设置", "AF2-1H：面板开着切 zh → 常驻钮同帧刷回（不早退）")
	if tl != null:
		check_eq(String(tl.text), "设置", "AF2-1I：面板标题同步刷回（订阅链并行无早退）")
	game.call("close_overlay")
	await process_frame
	i18n.call("set_language", "en")
	check_eq(String(sb.text), "Settings", "AF2-1J：关面板后再切 → 即时刷新")
	# FINALE 态
	game.call("goto_state", ST_FINALE)
	await process_frame
	await process_frame
	check_eq(int(game.call("current_state")), ST_FINALE, "AF2-1K：FINALE 态已入（前置）")
	i18n.call("set_language", "zh")
	check_eq(String(sb.text), "设置", "AF2-1L：FINALE 态切 zh → 即时刷新")
	# LEVEL 态（重玩档，进度空 → 纯装载）
	game.call("goto_state", ST_LEVEL, {"chapter": 1, "replay": true})
	await process_frame
	await process_frame
	check_eq(int(game.call("current_state")), ST_LEVEL, "AF2-1M：LEVEL 态已入（前置）")
	i18n.call("set_language", "en")
	check_eq(String(sb.text), "Settings", "AF2-1N：LEVEL 态切 en → 即时刷新")
	game.call("goto_state", ST_MAIN_MENU)
	await process_frame
	main1.queue_free()
	await process_frame

# ============================================ ② 共享字幕组件 + 两处接入
func _section_2_subtitles(i18n: Node) -> void:
	# ---- ②B 组件单元（不入树；兄弟形态=补 player.position 口径） ----
	var comp: GDScript = load(SUB_GD) as GDScript
	if comp != null:
		var player: VideoStreamPlayer = VideoStreamPlayer.new()
		var ov: Label = comp.new()
		ov.call("setup", player, SUB_JSON)
		check_eq(int(ov.call("subtitle_count")), 28, "AF2-2B：组件载入 28 条字幕（幂等单源）")
		check_eq(String(ov.call("subtitle_at", -1.0)), "", "AF2-2C：负时刻防御空串")
		var e0: Dictionary = ov.call("subtitle_entry", 0)
		check_eq(String(ov.call("subtitle_at", 2.9)), String(e0.get("en", "")),
			"AF2-2D：2.9s 命中首条（查表语义与 opening_movie 门面同源）")
		player.size = Vector2(1024, 768)
		ov.call("refresh_frame")
		var content: Rect2 = ov.call("content_rect_for", player.size)
		check(absf(content.size.y - 576.0) < 0.5, "AF2-2E：4:3 盒内容高 576（黑边解算纯函数）")
		var lr := Rect2(ov.position, ov.size)
		check(content.encloses(lr), "AF2-2F：字幕矩形在内容矩形内（兄弟形态）")
		if content.size.y > 0.0:
			var ratio: float = (lr.position.y - content.position.y) / content.size.y
			check(ratio >= 0.88 and ratio <= 0.96,
				"AF2-2G：字幕顶位于内容高度 %.3f（中文烧录字幕下方档）" % ratio)
		check(int(ov.mouse_filter) == int(Control.MOUSE_FILTER_IGNORE), "AF2-2H：组件 mouse_filter=IGNORE")
		# 避让（兄弟形态：右下角热区纵向重叠 → 收窄）
		var avoid: Button = Button.new()
		avoid.position = Vector2(880, 640)
		avoid.size = Vector2(120, 44)
		var ov2: Label = comp.new()
		ov2.call("setup", player, SUB_JSON, avoid)
		ov2.call("refresh_frame")
		var lr2 := Rect2(ov2.position, ov2.size)
		check(lr2.size.x < lr.size.x - 0.5 and not lr2.intersects(avoid.get_rect()),
			"AF2-2I：与热区纵向重叠 → 收窄避让（矩形不相交）")
		ov.free()
		ov2.free()
		player.free()
		avoid.free()
	# ---- ②J opening_movie 接入（en 挂载） ----
	i18n.call("set_language", "en")
	var container: Control = Control.new()
	container.size = Vector2(1280, 720)
	add_child(container)
	var movie: Node = (load(MOVIE_TSCN) as PackedScene).instantiate()
	container.add_child(movie)
	await process_frame
	await process_frame
	var lbl: Label = movie.get_node_or_null("EnglishSubtitle") as Label
	check(lbl != null and lbl.has_method("setup"), "AF2-2J：EnglishSubtitle 已挂共享组件脚本（setup 在位）")
	check(int(movie.call("subtitle_count")) > 0, "AF2-2K：门面 subtitle_count 委托组件")
	var skipb: Button = movie.get_node_or_null("SkipButton") as Button
	check_eq(String(skipb.text) if skipb != null else "", "Skip", "AF2-2L：④ en 态跳过钮=Skip（t() 覆写）")
	var mt: Label = movie.get_node_or_null("MovieTitle") as Label
	check_eq(String(mt.text) if mt != null else "", "Opening Movie", "AF2-2M：④ en 态标题=Opening Movie")
	var mplayer: VideoStreamPlayer = movie.get_node_or_null("VideoStreamPlayer") as VideoStreamPlayer
	if mplayer != null and lbl != null:
		var mc: Rect2 = movie.call("content_rect_for", mplayer.size)
		var mcg := Rect2(mplayer.global_position + mc.position, mc.size)
		check(mcg.encloses(lbl.get_global_rect()), "AF2-2N：开场覆盖层几何在内容矩形内（宿主 1280×720）")
	if lbl != null:
		movie.call("refresh_subtitle_at", 2.9)
		check(lbl.visible and lbl.text != "", "AF2-2O：进入字幕区间显字（门面委托）")
		movie.call("refresh_subtitle_at", 4.5)
		check(not lbl.visible, "AF2-2P：间隙隐藏（门面委托）")
	movie.queue_free()
	container.queue_free()
	await process_frame
	# ---- ②Q zh 复读（直通原样） ----
	i18n.call("set_language", "zh")
	var movie2: Node = (load(MOVIE_TSCN) as PackedScene).instantiate()
	add_child(movie2)
	await process_frame
	var sk2: Button = movie2.get_node_or_null("SkipButton") as Button
	check_eq(String(sk2.text) if sk2 != null else "", "跳过", "AF2-2Q：zh 直通原样（跳过）")
	movie2.queue_free()
	await process_frame
	# ---- ②R 图鉴内嵌播放器接入（嵌入态+全屏态） ----
	var cat: Node = (load(CATALOG_TSCN) as PackedScene).instantiate()
	add_child(cat)
	await process_frame
	await process_frame
	var vp2: VideoStreamPlayer = cat.get_node_or_null("Body/CenterMount/VideoPreview") as VideoStreamPlayer
	check(vp2 != null and vp2.visible, "AF2-2R：图鉴默认选中开场动画（视频态前置，K7-5）")
	var cov: Label = null
	if vp2 != null:
		cov = vp2.get_node_or_null("VideoSubtitleOverlay") as Label
	check(cov != null and cov.has_method("setup"), "AF2-2S：内嵌播放器字幕覆盖层在位（共享组件）")
	if cov != null and vp2 != null:
		check(int(cov.mouse_filter) == int(Control.MOUSE_FILTER_IGNORE), "AF2-2T：覆盖层鼠标穿透（不夺播控热区）")
		var cb2: Control = vp2.get_node_or_null("ControlBar") as Control
		check(cb2 != null and cov.get_index() > cb2.get_index(), "AF2-2U：覆盖层绘制于控制条之上")
		cat.call("_seek_video", 2.9)
		await process_frame
		await process_frame
		check(cov.visible and cov.text != "", "AF2-2V：回看 seek 入区间 → 覆盖层显字")
		var pr := Rect2(vp2.global_position, vp2.size)
		check(pr.encloses(cov.get_global_rect()), "AF2-2W：嵌入态几何贴内容矩形（播放器矩形=16:9 内容矩形）")
		# 全屏形态
		cat.call("_set_fullscreen", true)
		await process_frame
		await process_frame
		check(bool(cat.get("_is_fullscreen")), "AF2-2X：全屏态已入（前置）")
		check(cov.get_parent() == vp2, "AF2-2Y：reparent 后覆盖层随播放器（子件跟随）")
		var pr2 := Rect2(vp2.global_position, vp2.size)
		check(pr2.encloses(cov.get_global_rect()), "AF2-2Z：全屏形态几何贴内容矩形")
		check(cov.visible, "AF2-2AA：全屏形态字幕常显（与控制条共存）")
		# 控制条超时隐藏仅在播放态可达（暂停态控制条按设计常显，网页播放器语义）——
		# 复播后 idle 越限 → 条隐藏 → 字幕仍常显（不随条隐藏的铁口径）。
		cat.call("_toggle_play")   # 从 2.9s 续播
		cat.set("_fs_idle", 3.0)
		await process_frame
		await process_frame
		var cb3: Control = vp2.get_node_or_null("ControlBar") as Control
		check(cb3 != null and not cb3.visible, "AF2-2AB：全屏播放态 2.5s 无操作 → 控制条隐藏（前置）")
		check(cov.visible, "AF2-2AC：控制条隐藏后字幕仍常显（不随条隐藏）")
		cat.call("_set_fullscreen", false)
		await process_frame
	cat.queue_free()
	await process_frame

# ============================================ ③ TALK 中途切语言即时重绘
func _section_3_talk(i18n: Node) -> void:
	var doc: Dictionary = {"_说明": ["AF2 临时测试档"], "rounds": [
		{"speaker": "晷", "speaker_en": "Gui", "texts": ["晷的第一句台词，用于打字机测试。"],
			"texts_en": ["Gui line one for typewriter."]},
		{"speaker": "我", "texts": ["我的回答。"], "texts_en": ["My reply."]},
	]}
	var ft: FileAccess = FileAccess.open(TALK_TMP, FileAccess.WRITE)
	ft.store_string(JSON.stringify(doc))
	ft.close()
	i18n.call("set_language", "zh")
	var tc: Node = (load(TALK_TSCN) as PackedScene).instantiate()
	add_child(tc)
	await process_frame
	tc.call("load_dialog", TALK_TMP)
	tc.call("_show_line", 0)
	tc.call("_advance")   # 打字中 → 快进完整显示
	var txt: Label = tc.get_node("DialogPanel/VBox/TextLabel") as Label
	var nl: Label = tc.get_node("NameTagLeft/NameLabel") as Label
	var nr: Label = tc.get_node("NameTagRight/NameLabel") as Label
	var sk: Button = tc.get_node("SkipButton") as Button
	var hint: Label = tc.get_node("HintLabel") as Label
	check(txt != null and sk != null and hint != null, "AF2-3A：TALK 显示节点可达（前置）")
	if txt == null or sk == null or hint == null:
		tc.free()
		_del(TALK_TMP)
		return
	check_eq(String(txt.text), "晷的第一句台词，用于打字机测试。", "AF2-3B：zh 基线（快进后完整句）")
	# 中途切 en → 当前句/名牌/跳过钮/提示 全量即时重绘
	i18n.call("set_language", "en")
	check_eq(String(txt.text), "Gui line one for typewriter.", "AF2-3C：当前句即时重绘（en）")
	check_eq(String(nl.text), "Gui", "AF2-3D：名牌即时重绘（speaker_en）")
	check_eq(String(sk.text), "Skip Story", "AF2-3E：跳过钮即时重绘（en 词条既有）")
	check_eq(String(hint.text), "Click / Space to continue", "AF2-3F：继续提示即时重绘")
	# 刷回 zh
	i18n.call("set_language", "zh")
	check_eq(String(txt.text), "晷的第一句台词，用于打字机测试。", "AF2-3G：当前句即时刷回中文")
	# 打字中途切语言（更短文案立即收口；更长文案继续推进）
	tc.call("_show_line", 1)
	i18n.call("set_language", "en")   # 打字中切换（zh 5 字 → en 9 字符）
	await create_timer(0.4).timeout   # 30 字/秒 × 0.4s = 12 字 ≥ 9 → 完整
	check_eq(String(txt.text), "My reply.", "AF2-3H：打字中途切语言 → 新文案推进至完整")
	check_eq(String(nr.text), "Me", "AF2-3I：打字中途切语言 → 名牌同步")
	tc.call("_show_line", 0)
	i18n.call("set_language", "zh")   # 打字中切回（en 28 字符 → zh 15 字，更短）
	await create_timer(0.7).timeout
	check_eq(String(txt.text), "晷的第一句台词，用于打字机测试。", "AF2-3J：打字中途切更短语言 → 立即收口完整")
	tc.free()
	_del(TALK_TMP)

# ============================================ ⑤ 细查固化：字面量键覆盖 + 残留扫描
func _collect_gd_paths(dir_path: String, out: Array) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full := dir_path + "/" + name
		if dir.current_is_dir():
			if name != "." and name != ".." and name != "addons" and name != "tests":
				_collect_gd_paths(full, out)
		elif name.ends_with(".gd"):
			out.append(full)
		name = dir.get_next()
	dir.list_dir_end()

func _has_cjk(s: String) -> bool:
	for i: int in s.length():
		var c: int = s.unicode_at(i)
		if c >= 0x4E00 and c <= 0x9FFF:
			return true
	return false

func _section_4_scan() -> void:
	var merged: Dictionary = {}
	for path: String in [CONTENT_EN_PATH, UI_EN_PATH]:
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				var tbl: Variant = (parsed as Dictionary).get("翻译", parsed)
				if tbl is Dictionary:
					for k: Variant in (tbl as Dictionary).keys():
						var key := String(k)
						if not key.begins_with("_"):
							var v: Variant = (tbl as Dictionary)[k]
							if typeof(v) == TYPE_STRING:
								merged[key] = String(v)
	var files: Array = []
	_collect_gd_paths("res://scenes", files)
	_collect_gd_paths("res://scripts", files)
	_collect_gd_paths("res://autoload", files)
	var re: RegEx = RegEx.new()
	re.compile("I18n\\.t\\(\"([^\"]+)\"\\)")
	var uniq: Dictionary = {}
	for fp: String in files:
		var src: String = FileAccess.get_file_as_string(fp)
		for m: RegExMatch in re.search_all(src):
			uniq[m.get_string(1)] = true
	var missing: Array = []
	var residue: Array = []
	for k: String in uniq.keys():
		if not merged.has(k):
			missing.append(k)
		elif _has_cjk(String(merged[k]).replace("千年一榫", "")):
			residue.append(k)
	check(missing.is_empty(), "AF2-4A：t() 字面量 %d 键全命中合并表（缺=%s）" % [uniq.size(), str(missing)])
	check(residue.is_empty(), "AF2-4B：消费键 en 值零 CJK 残留（残留=%s）" % str(residue))
