extends Control
## 开场动画：首次开始游戏播放；图鉴回看复用。依据 spec 4.2。
## D（批次 J3-J3-3）：左上「开场动画」小字标题 + 「mm:ss / mm:ss」当前/总长时间标记（逐帧刷新）。
## 可跳过（2026-08-26 用户指示）：右下「跳过」按钮，点击立即等效动画播完回调——
##   首次（_replay=false）→ TALK(after_level, chapter:1)（批次 Z §14，用户 2026-09-24 拍板：
##   开场对话删除，链路零 opening 语境——直接挂第 1 关关前对话，首句=第1关.json rounds[0]）；
##   回看（replay_video=true）→ CATALOG（零变化）。
## 播放期间右下角「手势交互正在加载中」由 main 全局层显示，无需本场景处理。
##
## AF（批次 AF，用户 2026-11-01 拍板）：视频不剪辑，中文原文已烧在画面内；游戏在播放时
## 实时渲染英文字幕覆盖层（EnglishSubtitle），数据见 assets/animations/opening_subtitles_en.json。
## AF 修复②（实机反馈批，2026-11-01）：覆盖层抽共享组件 scenes/shared/video_subtitle_overlay.gd
##   （图鉴内嵌播放器开场回看同源共用）——本件保留门面（_load_subtitles/subtitle_count/
##   subtitle_entry/subtitle_at/refresh_subtitle_at/content_rect_for，test_af_opening_subtitle
##   48 checks 契约语义不变），数据/查表/几何全权委托组件；EnglishSubtitle 节点挂组件脚本，
##   兄弟形态挂载（position 补 player.position 偏移，组件自动判别），每帧几何由组件
##   _process 自驱（本件 _process 只管时间标记）。
## AF 修复④（实机反馈批）：tscn 静态文字「跳过」/「开场动画」旧为纯静态 zh（en 模式残留
##   中文、词条缺失）——_ready 经 t() 覆写 + ui_en.json 补键。

const SUBTITLE_PATH := "res://assets/animations/opening_subtitles_en.json"
const VIDEO_ASPECT := 16.0 / 9.0  # 开场动画片源 1280×720

@onready var player: VideoStreamPlayer = $VideoStreamPlayer
@onready var skip_btn: Button = $SkipButton
@onready var time_label: Label = $MovieTime
@onready var subtitle_overlay: Label = $EnglishSubtitle   # AF 修复②：共享组件脚本（video_subtitle_overlay.gd）
@onready var title_label: Label = $MovieTitle             # AF 修复④：标题 t() 覆写载体

func set_context(ctx: Dictionary) -> void:
	# replay_video=true 表示图鉴回看（行为相同，播完回图鉴）
	_replay = bool(ctx.get("replay_video", false))

var _replay: bool = false
var _finishing: bool = false
var _total_time: float = 0.0  # D（J3-3）：总时长（秒），0 表示未知（时间标记兜底 --:--）

func _ready() -> void:
	_load_subtitles()
	# AF 修复②：组件接线（幂等——_load_subtitles 已预载数据，此处补播放器绑定与避让控件）。
	if subtitle_overlay != null and subtitle_overlay.has_method("setup"):
		subtitle_overlay.call("setup", player, SUBTITLE_PATH, skip_btn, VIDEO_ASPECT)
	# AF 修复④：tscn 静态文字经 t() 覆写（zh 直通原样；en 命中词条表——跳过钮/标题）。
	skip_btn.text = I18n.t("跳过")
	title_label.text = I18n.t("开场动画")
	skip_btn.pressed.connect(_on_skip)
	var stream: VideoStream = null
	if ResourceLoader.exists("res://assets/animations/开场动画.ogv"):
		stream = load("res://assets/animations/开场动画.ogv")
	if stream == null:
		push_warning("开场动画缺失，跳过")
		_update_time_label()
		_finish()
		return
	player.stream = stream
	# D（J3-3）：总时长只走 player.get_stream_length()（播放器统一接口，起播时最可靠）；
	# P3-8（审查缺陷/已知 TODO 清偿）：旧的 VideoStream 属性级时长兜底已删——4.7 无该 API
	# （调用即 SCRIPT ERROR 中止 _ready → finished 连接与 play 都不执行、开场动画卡死）。
	# 总长 0 → 时间标记显示 --:--（_update_time_label 既有兜底）。
	_total_time = player.get_stream_length()
	player.finished.connect(_finish)
	player.play()
	_update_time_label()

func _process(_delta: float) -> void:
	# D（J3-3）：逐帧刷新「当前 / 总长」时间标记；仅只读播放器状态，不干扰跳过按钮。
	# AF 修复②：字幕几何/显隐改由共享组件 _process 自驱（本件零参与）。
	_update_time_label()

func _fmt_time(s: float) -> String:
	return "%02d:%02d" % [int(s / 60.0), int(s) % 60]

func _update_time_label() -> void:
	if time_label == null:
		return
	# Godot 4 播放时刻为 stream_position 属性（秒）；position 是 Control 坐标、
	# get_playback_position() 为 3.x API，均不可用（计划括注按此实际 API 落地）。
	var cur: float = maxf(player.stream_position, 0.0)
	var total_txt: String = "--:--" if _total_time <= 0.0 else _fmt_time(_total_time)
	time_label.text = "%s / %s" % [_fmt_time(cur), total_txt]

# ==================== AF 修复②：英文字幕门面（全权委托共享组件） ====================

## 组件引用兜底：@onready 在 _ready 前为 null——门面可被「实例化后、入树前」调用（测试路径）。
func _overlay() -> Node:
	if subtitle_overlay == null:
		subtitle_overlay = get_node("EnglishSubtitle")
	return subtitle_overlay

## 载入英文字幕 JSON（幂等；委托组件 load_subtitles——按路径幂等，缺失/非法恒隐不炸）。
func _load_subtitles() -> void:
	_overlay().call("load_subtitles", SUBTITLE_PATH)

func subtitle_count() -> int:
	return int(_overlay().call("subtitle_count"))

func subtitle_entry(i: int) -> Dictionary:
	var d: Variant = _overlay().call("subtitle_entry", i)
	return d if d is Dictionary else {}

## 按播放时刻查当前英文（二分；半开区间 [start, end)）。无字幕（间隙/越界/负值）→ 空串。
func subtitle_at(t: float) -> String:
	return String(_overlay().call("subtitle_at", t))

## 纯时间驱动显隐（与语言模式无关）：有字幕即显、间隙/越界即隐（委托组件）。
func refresh_subtitle_at(t: float) -> void:
	_overlay().call("refresh_subtitle_at", t)

## KEEP_ASPECT_CENTERED 内容矩形解算：返回 16:9 片源在 box 内的居中内容区（含黑边偏移）。
## 播放器 expand=true 恒拉伸铺满自身 rect，故字幕须锚在内容区而非控件区（纯函数委托组件）。
func content_rect_for(box: Vector2) -> Rect2:
	var r: Variant = _overlay().call("content_rect_for", box)
	return r if r is Rect2 else Rect2()

# ==================== 跳过 / 结束 ====================

func _on_skip() -> void:
	# 跳过 = 立即等效动画播完回调（首次→第 1 关关前对话；回看→图鉴）
	_finish()

func _finish() -> void:
	if _finishing:
		return
	_finishing = true
	# N10（2026-09-09）：首次看过开场动画持久化置位（幂等）——播完（finished 信号）/跳过按钮/
	# 资源缺失兜底三条退出路径同经 _finish，一处收口；回看模式（_replay=true，经图鉴进入，
	# 门控必已开）不置位。图鉴门控判据②（save_manager.can_open_catalog）。
	if not _replay:
		SaveManager.mark_opening_watched()
	if _replay:
		Game.goto_state(Game.State.CATALOG)
	else:
		# 批次 Z §14（用户 2026-09-24 拍板）：开场对话删除——首次路径直接挂第 1 关关前对话
		# 语境（after_level, chapter=1，链路零 opening 段）；回看路径（上方 CATALOG）零变化。
		Game.goto_state(Game.State.TALK, {"mode": "after_level", "chapter": 1})
