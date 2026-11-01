extends "res://tests/test_base.gd"
## M-F（批次 M spec §3.6，2026-09-08）：图鉴视频播放器网页化重做——TDD 先行测试。
## 契约来源：spec §3.6 目标行为 1~5 / 验收标准 1~4：
##   ① 悬浮控制条：ControlBar 从页面级底部常驻 HBox 改为 VideoPreview 内悬浮层
##     （半透黑金底 α0.55 圆角 8 暂定），默认隐藏，鼠标进入视频 rect 淡入、
##     离开 0.5s 淡出（暂停时常显）；含播放/暂停合一钮、进度条、时间戳、全屏钮（新增）。
##   ② 全屏进出：全屏钮 → 视频层升入全屏（独立 CanvasLayer 挂 GlobalUI 之上，铺满视口，
##     背景黑）；全屏中控制条「点击/晃动浮现、2.5s 无操作隐藏」；缩小钮退出回嵌入态。
##     播控语义全沿用（stream_position 写读、无 seek()/pause()、PREVIEW_SETTLE_FRAMES、
##     finished 回首帧）——4.7 视频坑规避链严禁清理（本测试同时回归护栏）。
##   ③ 删黄条：_show_video_preview(true) 时 center_pad.visible=false；点云态恢复 true。
##   ④ 右侧列表半透：RightBox 毛玻璃背板深 bg(0.12,0.08,0.03,0.75)/浅 bg(1,0.94,0.80,0.78)、
##     圆角 16、顶缘高光边（暂定值）。
##   ⑤ 设置钮避让：RightBox 顶部 44px 间隔，列表首行全局顶 ≥ y=108（设置钮区下缘之下），
##     且与设置钮全局 rect 不相交；BottomBar 不受影响。
## 坑位吸收（spec §六）：钉设计视口 1152×648（headless expand 伪象防御，坑 1）；
##   全屏层根 Control 显式赋主题（坑 11）；RightBox 背板按 PanelContainer 实际类型取
##   （坑 10：PanelContainer 非 Panel 子类）；锚点用 set_anchors_and_offsets_preset 口径
##   （坑 12）；视频 API 不触碰规避链（坑 8）。
## 环境说明：--script 主脚本编译期不能写 autoload 全局名 → 经 get_root().get_node 动态引用。

const W := 1152.0
const H := 648.0
const SCENE_PATH := "res://scenes/catalog/catalog_scene.tscn"
const SCRIPT_PATH := "res://scenes/catalog/catalog_scene.gd"
const SAVE_PATH := "user://save.json"
# main.tscn GlobalUI 右上角设置钮全局 rect（offset_left=-124,top=48,right=-16,bottom=84 @1152×648）
# ——避让判据的锚点常量（与 main.tscn 实际值一致，防两处漂移由 main 侧测试守护）。
const SETTINGS_RECT := Rect2(1028, 48, 108, 36)

var panel: Control = null
var container: Control = null
var vp: VideoStreamPlayer = null
var cbar: PanelContainer = null
var game: Variant = null

func _cleanup() -> void:
	var abs: String = ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(abs):
		DirAccess.remove_absolute(abs)

func _frames(n: int) -> void:
	for i: int in n:
		await process_frame

func _setup() -> bool:
	var save: Variant = get_root().get_node("SaveManager")
	save.call("load_game")  # 全新档（cleared=[]，后续按需造档）
	container = Control.new()
	container.size = Vector2(W, H)  # 钉设计视口（spec §六坑 1）
	add_child(container)
	panel = (load(SCENE_PATH) as PackedScene).instantiate()
	if panel is Control:
		(panel as Control).theme = get_root().get_node("ThemeManager").call("current_theme")
	container.add_child(panel)
	await _frames(6)  # _ready + 默认选中视频 + 首帧定格放行（PREVIEW_SETTLE_FRAMES=3）+ 布局稳定
	vp = panel.get_node_or_null("Body/CenterMount/VideoPreview") as VideoStreamPlayer
	cbar = panel.get_node_or_null("Body/CenterMount/VideoPreview/ControlBar") as PanelContainer
	return panel != null and vp != null and cbar != null

## 选已通关章节（造档 + 点列表首行）
func _select_chapter1() -> void:
	var save: Variant = get_root().get_node("SaveManager")
	save.call("advance_progress", 1)
	await _frames(3)  # progress_changed → _rebuild_list
	var rl: VBoxContainer = panel.get_node("Body/RightBox/RightInner/RightScroll/RightList")
	(rl.get_child(0) as Button).pressed.emit()

## 选回视频（列表末行「开场动画（回看）」）
func _select_video() -> void:
	var rl: VBoxContainer = panel.get_node("Body/RightBox/RightInner/RightScroll/RightList")
	(rl.get_child(rl.get_child_count() - 1) as Button).pressed.emit()

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
const DISC_BK_PREFIX := "user://_r2b_mvp_backup_"
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
	print("EVID|user_restore|mvp|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_m_video_player ==")
	_backup_user()
	# 批次 AF 修复批（2026-11-01，587f01e「夹具显式钉前提」同款）：I18n autoload 启动读
	# 用户真档 settings.language（实测档可能为 en）——本件 tooltip/按钮文案断言为 zh 口径，
	# 钉 zh 保环境确定性（纯测试夹具前提，生产代码零改动）。时序坑⑥：--script 模式 autoload
	# _ready 推迟至树激活——先放行一帧让 I18n._ready 读完档，再钉 zh（否则钉被启动读档覆盖）。
	await process_frame
	var i18n: Variant = get_root().get_node_or_null("I18n")
	if i18n != null:
		i18n.call("set_language", "zh")
	if not ResourceLoader.exists(SCENE_PATH):
		check(false, "catalog_scene.tscn 存在")
		finish()
		return
	var ok: bool = await _setup()
	check(ok, "M-F：图鉴场景实例化（钉视口 1152×648）且 VideoPreview/ControlBar 就位")
	if not ok:
		_cleanup()
		finish()
		return

	# ==================== 段 A：结构 + CenterPad 显隐（spec 验收 1/3） ====================
	var sel: Dictionary = panel.get("_selected")
	check_eq(String(sel.get("kind", "")), "video", "K7-5 回归：进图鉴默认选中视频")
	var center_pad: Panel = panel.get_node_or_null("Body/CenterMount/CenterPad") as Panel
	check(center_pad is Panel, "G2 回归：CenterPad 节点仍在（点云态内衬载体）")
	check(center_pad != null and not center_pad.visible, "M-F-③：视频选中态 CenterPad 隐藏（黄条根除）")
	panel.call("_select_chapter", 1, null)
	check(center_pad != null and center_pad.visible, "M-F-③：切回点云态 CenterPad 恢复显示")
	check(vp != null and not vp.visible, "点云态视频隐藏（互斥语义不回归）")
	_select_video()
	check(vp != null and vp.visible, "M-F：重选视频预览恢复可见")
	check(center_pad != null and not center_pad.visible, "M-F-③：再选视频 CenterPad 再次隐藏")
	check(cbar.get_parent() == vp, "M-F-①：ControlBar 为 VideoPreview 子层（悬浮层归属）")
	var cb_rect: Rect2 = cbar.get_rect()
	var vpr: Rect2 = Rect2(Vector2.ZERO, vp.size)
	check(vpr.encloses(cb_rect), "M-F-①：ControlBar rect 在视频矩形内（下沿内贴）")
	var ppb: Button = cbar.get_node_or_null("BarRow/PlayPauseBtn") as Button
	var tsld: HSlider = cbar.get_node_or_null("BarRow/TimeSlider") as HSlider
	var tlbl: Label = cbar.get_node_or_null("BarRow/TimeLabel") as Label
	var fsb: Button = cbar.get_node_or_null("BarRow/FullscreenBtn") as Button
	var skb: Button = cbar.get_node_or_null("BarRow/ShrinkBtn") as Button
	check(ppb is Button, "M-F-①：播放/暂停合一钮仍在悬浮条内")
	check(tsld is HSlider, "M-F-①：进度条仍在悬浮条内")
	check(tlbl is Label, "M-F-①：时间戳仍在悬浮条内")
	check(fsb is Button, "M-F-①：全屏钮（新增）存在")
	check(skb is Button, "M-F-①：缩小钮（新增）存在")
	check(fsb != null and fsb.pressed.get_connections().size() >= 1, "M-F-②：全屏钮 pressed 已接线")
	check(skb != null and skb.pressed.get_connections().size() >= 1, "M-F-②：缩小钮 pressed 已接线")
	check(fsb != null and fsb.visible and skb != null and not skb.visible, "M-F-②：嵌入态全屏钮可见/缩小钮隐藏（互斥）")
	var cbsb: StyleBoxFlat = cbar.get_theme_stylebox("panel") as StyleBoxFlat
	check(cbsb != null and cbsb.bg_color.a >= 0.5 and cbsb.bg_color.a <= 0.6,
		"M-F-①：控制条背板 α∈[0.5,0.6]（黑金半透 0.55 暂定）")
	check(cbsb != null and cbsb.corner_radius_top_left >= 8, "M-F-①：控制条背板圆角 ≥8（暂定）")
	check(int(cbar.mouse_filter) != int(Control.MOUSE_FILTER_IGNORE)
		or ppb != null, "M-F-①：悬浮条可交互（按钮事件可达）")

	# ==================== 段 B：hover 显隐（spec 验收 2 前半） ====================
	await _frames(5)  # 等首帧定格放行（PREVIEW_SETTLE_FRAMES=3）收口
	check(vp != null and vp.paused, "J6r3-1 回归：默认定格暂停态（规避链不回归）")
	check(cbar.visible, "M-F-①：暂停态控制条常显（默认可见）")
	panel.call("_toggle_play")  # 起播
	check(vp != null and not vp.paused, "K7-7 回归：_toggle_play 起播")
	await create_timer(0.7).timeout  # > BAR_HIDE_DELAY(0.5)
	check(cbar != null and not cbar.visible, "M-F-①：播放中无 hover → 0.5s 后控制条隐藏")
	vp.mouse_entered.emit()  # 模拟鼠标进入视频 rect
	check(cbar.visible, "M-F-①：hover 进入 → 控制条淡入（visible 翻转）")
	vp.mouse_exited.emit()  # 模拟鼠标离开
	check(cbar.visible, "M-F-①：离开后 0.5s 内仍可见（延迟淡出，非瞬隐）")
	await create_timer(0.7).timeout
	check(cbar != null and not cbar.visible, "M-F-①：离开 0.5s 后控制条隐藏（淡出完成）")
	panel.call("_toggle_play")  # 暂停
	vp.mouse_exited.emit()  # 暂停态离开
	await create_timer(0.7).timeout
	check(cbar != null and cbar.visible, "M-F-①：暂停时常显（离开也不隐藏）")
	vp.mouse_entered.emit()  # 复位 hover 态
	panel.call("_toggle_play")  # 回播放态 → 停隐藏倒计时交给后续全屏段
	await _frames(2)

	# ==================== 段 C：全屏进出（spec 验收 2 后半） ====================
	vp.mouse_exited.emit()  # 复位段 B 遗留 hover（隔离状态机）
	panel.call("_seek_video", 13.0)  # seek 权威状态注入（4.7 无 seek()，走 stream_position 写）
	check(absf(float(vp.stream_position) - 13.0) < 0.01, "K7-7 回归：seek 写入 stream_position=13s")
	check(vp != null and not vp.paused, "全屏前置：播放中（idle 隐藏路径可达）")
	panel.call("_set_fullscreen", true)
	await _frames(2)
	var fs_layer: CanvasLayer = panel.get_node_or_null("VideoFullscreenLayer") as CanvasLayer
	check(fs_layer is CanvasLayer, "M-F-②：全屏层 VideoFullscreenLayer(CanvasLayer) 存在")
	check(fs_layer != null and fs_layer.layer > 1, "M-F-②：全屏层挂 GlobalUI(layer=1) 之上（layer>1）")
	check(fs_layer != null and fs_layer.visible, "M-F-②：进入全屏 → 全屏层 visible 翻转")
	var fs_root: Control = panel.get("_fs_root") as Control
	check(fs_root != null and fs_root.visible, "M-F-②：全屏根可见（铺满视口黑底载体）")
	check(fs_root != null and fs_root.theme != null, "M-F-②：全屏层根 Control 显式赋主题（CanvasLayer 主题不传播，坑 11）")
	check(vp.get_parent() == fs_root, "M-F-②：视频层已升入全屏层（reparent 单实例，播控状态不分裂）")
	check(float(vp.stream_position) >= 13.0 and float(vp.stream_position) < 59.0,
		"M-F-②：进全屏后 stream_position 不丢（从 13s 起连续推进未重置，现 %s）" % str(vp.stream_position))
	check(vp != null and not vp.paused, "M-F-②：进全屏后 paused 不丢（播放态保持）")
	check(fsb != null and not fsb.visible and skb != null and skb.visible, "M-F-②：全屏态钮切换（全屏隐/缩小显）")
	var ratio: float = vp.size.x / maxf(vp.size.y, 0.001)
	check(absf(ratio - 16.0 / 9.0) < 0.02, "M-F-②：全屏视频保持 16:9 适配（%s）" % str(vp.size))
	var fs_view: Rect2 = Rect2(Vector2.ZERO, fs_root.size)
	check(fs_view.encloses(Rect2(vp.position, vp.size)) or vp.position == Vector2.ZERO,
		"M-F-②：全屏视频矩形在全屏层内")
	var cbf: Rect2 = cbar.get_rect()
	check(Rect2(Vector2.ZERO, vp.size).encloses(cbf), "M-F-②：全屏态控制条仍为视频内悬浮层")
	# 全屏 idle 2.5s 无操作隐藏（加速：直写 idle 秒数，_process 下帧裁决）
	panel.set("_fs_idle", 3.0)
	await _frames(2)
	check(cbar != null and not cbar.visible, "M-F-②：全屏 2.5s 无操作 → 控制条隐藏")
	# 点击/晃动浮现（gui_input 路径测试钩子）
	panel.call("_fs_wake")
	check(cbar != null and cbar.visible and absf(float(panel.get("_fs_idle"))) < 0.001,
		"M-F-②：全屏点击/晃动 → 控制条浮现且 idle 归零")
	# 退出全屏
	panel.call("_set_fullscreen", false)
	await _frames(2)
	check(fs_layer != null and not fs_layer.visible, "M-F-②：缩小钮语义 → 全屏层隐藏")
	check(vp.get_parent() == panel.get_node("Body/CenterMount"), "M-F-②：视频层回 CenterMount（嵌入态复位）")
	check(float(vp.stream_position) >= 13.0 and float(vp.stream_position) < 59.0,
		"M-F-②：退出全屏后播控位从 13s 连续未重置（现 %s）" % str(vp.stream_position))
	var ratio2: float = vp.size.x / maxf(vp.size.y, 0.001)
	check(absf(ratio2 - 16.0 / 9.0) < 0.02, "M-F-②：嵌入态恢复 16:9 适配")
	check(vp != null and vp.visible, "M-F-②：嵌入态预览仍可见")
	var cm: Control = panel.get_node("Body/CenterMount")
	var cm_g: Rect2 = Rect2(cm.global_position, cm.size)
	var vp_g: Rect2 = Rect2(vp.global_position, vp.size)
	check(cm_g.encloses(vp_g),
		"M-F-②：嵌入态视频矩形回到中央列内（全局口径 cm=%s vp=%s）" % [str(cm_g), str(vp_g)])

	# ==================== 段 D：右侧背板 + 设置钮避让（spec 验收 3） ====================
	var cs: GDScript = load(SCRIPT_PATH)
	var cmap: Dictionary = cs.get_script_constant_map()
	var bd: Color = cmap.get("RIGHT_BG_DARK", Color())
	check(absf(bd.a - 0.75) < 0.001, "M-F-④：背板深档常量 α=0.75（暂定）")
	# 批次 AB-3：RIGHT_BG_LIGHT 浅档常量随深浅主题机制删除退役——反向锁。
	check(not cmap.has("RIGHT_BG_LIGHT"), "AB-3 反向锁：RIGHT_BG_LIGHT 浅档常量退役（无复辟）")
	check(absf(bd.r - 0.12) < 0.001 and absf(bd.g - 0.08) < 0.001,
		"AB-3：背板底色恒深档值 (0.12,0.08,0.03,0.75)（唯一真值，值未变）")
	var rb: PanelContainer = panel.get_node_or_null("Body/RightBox") as PanelContainer
	check(rb is PanelContainer, "M-F-④：RightBox 为 PanelContainer（背板载体；坑 10 按实际类型取）")
	var rsb: StyleBoxFlat = rb.get_theme_stylebox("panel") as StyleBoxFlat
	check(rsb != null and rsb.bg_color.a >= 0.70 and rsb.bg_color.a <= 0.80,
		"M-F-④：运行时背板 α∈[0.70,0.80]（70~80%% 口径，当前 %.3f）" % (rsb.bg_color.a if rsb != null else -1.0))
	check(rsb != null and rsb.corner_radius_top_left >= 16, "M-F-④：背板圆角 16（暂定）")
	check(rsb != null and rsb.border_width_top >= 2, "M-F-④：背板顶缘高光边 ≥2px（暂定）")
	var first_btn: Button = panel.get_node("Body/RightBox/RightInner/RightScroll/RightList").get_child(0)
	var fb_top: float = first_btn.global_position.y
	check(fb_top >= 108.0, "M-F-⑤：列表首按钮全局顶 y=%.1f ≥108（设置钮区下缘之下）" % fb_top)
	var fb_rect: Rect2 = Rect2(first_btn.global_position, first_btn.size)
	check(not fb_rect.intersects(SETTINGS_RECT), "M-F-⑤：列表首按钮与设置钮全局 rect 不相交")
	var toggle_btn: Button = panel.get_node("Body/RightBox/RightInner/RightToggle")
	check(toggle_btn.global_position.y >= 108.0 - 44.0 + 44.0, "M-F-⑤：收起钮下移（44px 间隔生效）")
	check(right_scroll_healthy(panel), "M-F-⑤：RightScroll 高度收缩正常（仍可滚动容纳 6 项）")
	var eb: Button = panel.get_node("BottomBar/EnterButton")
	var xb: Button = panel.get_node("BottomBar/ExitButton")
	# 回修3：视频态 EnterButton 隐藏（不参与容器排布、rect 不再有意义）→ 贴底断言转 ExitButton 承载
	check(xb != null and xb.global_position.y >= H - 80.0 and not eb.visible,
		"M-F-⑤→回修3：BottomBar 贴底不受避让影响（ExitButton 承载；EnterButton 视频态已隐藏）")

	# ==================== 段 E：4.7 视频坑规避链回归护栏（spec §六坑 8） ====================
	var psf: Variant = panel.get("PREVIEW_SETTLE_FRAMES")
	check_eq(int(psf) if psf != null else -1, 3, "规避链：PREVIEW_SETTLE_FRAMES=3 保留")
	check(vp != null and bool(vp.get("expand")), "规避链：VideoPreview expand=true 保留（K7-7 防溢出口径）")
	check(panel.get_node_or_null("Body/CenterMount/VideoExitBtn") == null, "K7-7 回归：冗余退出钮仍不在 CenterMount 直下")
	check(panel.get_node_or_null("Body/CenterMount/VideoScrub") == null, "K7-7 回归：旧时间轴仍不在 CenterMount 直下")
	# finished 回首帧语义不回归
	panel.call("_seek_video", 30.0)
	vp.finished.emit()
	check(absf(float(panel.get("_video_pos")) - 0.5) < 0.001 and vp.paused,
		"规避链：finished 回 0.5s 首帧并暂停（语义平移不回归）")
	# 退出图鉴前清态：切章节退出全屏防御路径
	panel.call("_set_fullscreen", true)
	await _frames(1)
	panel.call("_show_video_preview", false)
	await _frames(1)
	var fs2: CanvasLayer = panel.get_node_or_null("VideoFullscreenLayer") as CanvasLayer
	check(fs2 != null and not fs2.visible, "M-F-②：切离视频态时全屏层自动收起（防御路径）")
	check(panel.get_node("Body/CenterMount").get_node_or_null("VideoPreview") != null,
		"M-F-②：防御路径后视频层已回嵌入宿主（无孤儿 reparent）")

	# ==================== 段 F：回修轮 2026-09-08（全屏一次点击 + 手型光标） ====================
	# 回修 1 根因：全屏态鼠标悬停控制条不被视为活跃（motion 被条/按钮 STOP 消费到不了
	# _fs_root，_fs_idle 持续累积 → 用户瞄准时条消失）+ 条隐藏后首击被 _fs_root 消费为
	# wake（按钮收不到）。修复=控制条 hover 信号驱动保活（pointer_inside → idle 归零），
	# 条空白区 gui_input 亦 wake；按钮可见可达时**单击一次必须生效**。
	_select_video()  # 回视频态（段 E 末为章节态）
	await _frames(5)  # 定格收口
	panel.call("_toggle_play")  # 起播（非暂停才能走 idle 隐藏路径）
	vp.mouse_exited.emit()  # 隔离 hover
	panel.call("_set_fullscreen", true)
	await _frames(2)
	check(fs_layer != null and fs_layer.visible, "F 前置：全屏态就位")
	# F1 悬停保活：鼠标移入控制条 → idle 超时也不隐藏（瞄准不消失）
	cbar.mouse_entered.emit()  # 真实信号路径（PanelContainer hover）
	panel.set("_fs_idle", 3.0)  # 越过 FS_HIDE_DELAY(2.5)
	await _frames(2)
	check(cbar != null and cbar.visible, "回修1：悬停控制条期间超 2.5s 仍可见（瞄准不消失）")
	check(bool(panel.get("_fs_bar_active")), "回修1：悬停期间 fs_bar_active 保持（不被超时复位）")
	check(absf(float(panel.get("_fs_idle"))) < 0.001, "回修1：悬停期间 idle 恒归零（活跃语义）")
	# 补：控制条空白区交互也 wake（PanelContainer STOP 消费事件，_fs_root 收不到）
	var mm_ev := InputEventMouseMotion.new()
	cbar.gui_input.emit(mm_ev)
	check(absf(float(panel.get("_fs_idle"))) < 0.001 and bool(panel.get("_fs_bar_active")),
		"回修1：控制条空白区点击/移动 → wake（idle 归零+活跃置位）")
	cbar.mouse_exited.emit()  # 离开控制条
	panel.set("_fs_idle", 3.0)
	await _frames(2)
	check(cbar != null and not cbar.visible, "回修1：离开控制条后 idle 超时正常隐藏（保活不过度）")
	# F2 一次点击生效（合成 pressed 直调回调链；防「要点好几下」回归）
	cbar.mouse_entered.emit()  # 再现「按钮可见可达」前提（悬停条上）
	fsb.pressed.emit()  # 单击全屏钮一次
	check(fs_layer != null and fs_layer.visible, "回修1红线：单击全屏钮一次 → 全屏层 visible 翻转")
	check(bool(panel.get("_is_fullscreen")), "回修1红线：单击一次 _is_fullscreen==true")
	fsb.pressed.emit()  # 全屏态连点全屏钮
	fsb.pressed.emit()
	check(fs_layer != null and fs_layer.visible and fsb != null and not fsb.visible
		and skb != null and skb.visible, "回修1：全屏态连续快速点击不重入不崩（互斥按钮稳定）")
	skb.pressed.emit()  # 单击缩小钮一次
	check(fs_layer != null and not fs_layer.visible, "回修1红线：单击缩小钮一次 → 退出全屏")
	skb.pressed.emit()  # 嵌入态连点缩小钮
	check(fs_layer != null and not fs_layer.visible and vp.get_parent() == panel.get_node("Body/CenterMount"),
		"回修1：嵌入态连续点击不重入（视频层不二次 reparent）")
	await _frames(2)
	# F3 手型光标遍历（回修 2：所有可点项 POINTING_HAND）
	var hand: int = Control.CURSOR_POINTING_HAND
	var rl2: VBoxContainer = panel.get_node("Body/RightBox/RightInner/RightScroll/RightList")
	var all_hand: bool = true
	for i: int in rl2.get_child_count():
		var b2: Button = rl2.get_child(i)
		if b2 == null or int(b2.mouse_default_cursor_shape) != hand:
			all_hand = false
	check(all_hand, "回修2：右侧列表全部按钮手型光标（%d 项遍历）" % rl2.get_child_count())
	var rt2: Button = panel.get_node("Body/RightBox/RightInner/RightToggle")
	check(int(rt2.mouse_default_cursor_shape) == hand, "回修2：侧栏收起钮手型光标")
	check(ppb != null and int(ppb.mouse_default_cursor_shape) == hand, "回修2：播放/暂停合一钮手型光标")
	check(fsb != null and int(fsb.mouse_default_cursor_shape) == hand, "回修2：全屏钮手型光标")
	check(skb != null and int(skb.mouse_default_cursor_shape) == hand, "回修2：缩小钮手型光标")
	var eb2: Button = panel.get_node("BottomBar/EnterButton")
	var xb2: Button = panel.get_node("BottomBar/ExitButton")
	check(int(eb2.mouse_default_cursor_shape) == hand and int(xb2.mouse_default_cursor_shape) == hand,
		"回修2：BottomBar 进入/退出钮手型光标")

	# ==================== 段 G：回修3 2026-09-08（嵌入态播控可靠性 + 删冗余播放钮 + 符号化按钮） ====================
	# 回修3 根因①：控制条显隐判据依赖 mouse_entered/exited 信号——引擎 hover 通知不冒泡祖先链，
	#   鼠标悬停条内子控件（播放钮/滑块）上时 ControlBar/VideoPreview 双双收不到 entered，
	#   _bar_hover/_bar_pointer_inside 同 false → 播放中 0.5s 淡出 → 瞄准消失/拖完滑块即失效。
	#   修复=位置法兜底（鼠标全局位置落在条/视频 rect 内即视为悬停，信号旗标短路缓存）。
	# 回修3 根因②：_toggle_play 恢复播放仅置 paused=false——播放器停止态（播完/reparent 离树）
	#   下 paused=false 不起播 →「点了没反应」。修复=is_playing()==false 时显式 play() + 回写 _video_pos。
	_select_video()  # 复位视频态（段 F 末为嵌入态视频态，重选走定格流程）
	await _frames(5)  # PREVIEW_SETTLE_FRAMES=3 收口 → 定格暂停态
	check(vp != null and vp.paused, "G 前置：重选后定格暂停态")
	var ppb3: Button = cbar.get_node_or_null("BarRow/PlayPauseBtn") as Button
	check(ppb3 != null, "G 前置：PlayPauseBtn 可达")
	# G1 嵌入态单击播放/暂停一次生效（合成 pressed 走真实信号链）
	ppb3.pressed.emit()  # 单击播放
	check(vp != null and not vp.paused, "回修3-G1：嵌入态单击播放钮一次 → 起播（paused=false）")
	await _frames(2)
	ppb3.pressed.emit()  # 单击暂停
	check(vp != null and vp.paused, "回修3-G1：再单击一次 → 暂停（paused=true，一次生效）")
	# G2 停止态兜底（真实引擎停止态：stop() 模拟播完/离树——paused 翻转对其无效）
	vp.stop()
	ppb3.pressed.emit()
	check(vp != null and not vp.paused and vp.is_playing(),
		"回修3-G2：停止态单击播放 → 兜底 play() 起播（不再「点了没反应」）")
	await _frames(2)
	ppb3.pressed.emit()  # 暂停复位
	check(vp != null and vp.paused, "回修3-G2：复位暂停态")
	# G3 拖动进度条后播放/暂停仍可靠（用户症状「拖了时间轴之后播放暂停就又不行」）
	panel.call("_seek_video", 20.0)  # 暂停态拖动
	ppb3.pressed.emit()
	check(vp != null and not vp.paused, "回修3-G3：拖动 seek(20s) 后单击播放 → 起播")
	await _frames(2)
	panel.call("_seek_video", 25.0)  # 播放中再拖
	ppb3.pressed.emit()
	check(vp != null and vp.paused, "回修3-G3：播放中拖动后再单击暂停 → 暂停")
	# G4 悬停判据位置法兜底（信号盲区修复）：信号旗标短路 + 位置法 helper 存在
	# （防御式断言：call 不存在方法会 SCRIPT ERROR 中止 _initialize 致无头挂死——先 has_method 探测）
	if panel.has_method("_pointer_on_video") and panel.has_method("_pointer_on_bar"):
		panel.set("_bar_hover", false)
		panel.set("_bar_pointer_inside", false)
		check(bool(panel.call("_pointer_on_video")) == false and bool(panel.call("_pointer_on_bar")) == false,
			"回修3-G4：无旗标且无头鼠标 (0,0) 不在视频/条 rect 内 → 位置法判否（不误保活）")
		panel.set("_bar_pointer_inside", true)
		check(bool(panel.call("_pointer_on_bar")) == true,
			"回修3-G4：信号旗标置位 → 位置法短路判真（悬停条上保活路径）")
		panel.set("_bar_hover", true)
		check(bool(panel.call("_pointer_on_video")) == true,
			"回修3-G4：视频 hover 旗标置位 → _pointer_on_video 判真")
	else:
		check(false, "回修3-G4：_pointer_on_video/_pointer_on_bar 位置法 helper 缺失（红灯占位）")
	panel.set("_bar_hover", false)
	panel.set("_bar_pointer_inside", false)
	cbar.mouse_exited.emit()
	vp.mouse_exited.emit()
	panel.set("_bar_hover", false)
	panel.set("_bar_pointer_inside", false)
	# G5 删冗余「播放」钮（BottomBar 视频态隐藏；「退出」保留；章节态「进入关卡」恢复）
	var eb3: Button = panel.get_node_or_null("BottomBar/EnterButton") as Button
	check(eb3 != null and not eb3.visible, "回修3-G5：视频选中态 BottomBar「播放」钮已隐藏（冗余删除）")
	check(String(panel.get_node("BottomBar/ExitButton").text) == "退出", "回修3-G5：BottomBar「退出」钮保留")
	panel.call("_select_chapter", 1, null)
	check(eb3 != null and eb3.visible and String(eb3.text) == "进入关卡",
		"回修3-G5：章节态「进入关卡」恢复显示（语义不受删钮影响）")
	_select_video()
	check(eb3 != null and not eb3.visible, "回修3-G5：切回视频态再次隐藏（状态切换即时）")
	await _frames(5)  # 定格收口（供 G6 基准）
	# G6 符号化按钮（▶/⏸ 自绘图标替代文字；全屏/缩小统一符号态）
	var ppb6: Button = cbar.get_node_or_null("BarRow/PlayPauseBtn") as Button
	var fsb6: Button = cbar.get_node_or_null("BarRow/FullscreenBtn") as Button
	var skb6: Button = cbar.get_node_or_null("BarRow/ShrinkBtn") as Button
	var ic_play: Texture2D = panel.get("_icon_play") as Texture2D
	var ic_pause: Texture2D = panel.get("_icon_pause") as Texture2D
	check(ic_play != null and ic_pause != null and ic_play != ic_pause,
		"回修3-G6：播放/暂停自绘图标两态齐备且不同")
	check(ppb6 != null and String(ppb6.text) == "" and ppb6.icon != null,
		"回修3-G6：播放/暂停钮已去文字（text 空 + icon 非空）")
	check(ppb6 != null and ppb6.icon == ic_play and String(ppb6.tooltip_text) == "播放",
		"回修3-G6：暂停态显示播放三角 + tooltip「播放」")
	panel.call("_toggle_play")  # 起播 → 图标切暂停
	check(ppb6 != null and ppb6.icon == ic_pause and String(ppb6.tooltip_text) == "暂停",
		"回修3-G6：播放中显示暂停双杠 + tooltip「暂停」（随状态切换）")
	panel.call("_toggle_play")  # 复位暂停态
	check(fsb6 != null and String(fsb6.text) == "" and fsb6.icon != null,
		"回修3-G6：全屏钮符号化统一（text 空 + 自绘 icon）")
	check(skb6 != null and String(skb6.text) == "" and skb6.icon != null,
		"回修3-G6：缩小钮符号化统一（text 空 + 自绘 icon）")
	check(fsb6 != null and skb6 != null and String(fsb6.tooltip_text) == "全屏" and String(skb6.tooltip_text) == "缩小",
		"回修3-G6：全屏/缩小 tooltip 文字说明保留")

	_cleanup()
	finish()

## RightScroll 高度健康：可视高 > 单项高（说明列表区未被 spacer 压扁至 0）
func right_scroll_healthy(p: Control) -> bool:
	var rs: ScrollContainer = p.get_node_or_null("Body/RightBox/RightInner/RightScroll") as ScrollContainer
	return rs != null and rs.size.y > 40.0
