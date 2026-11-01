extends Control
## 图鉴（批次 H 补全主体 → 批次 K-F 重构 → 批次 M-F 视频播放器网页化重做 → 批次 O-P1 五修）。
## 依据 spec 4.6/9.2 + 批次 M spec §3.6：
## 三列主体 Body：左信息框 LeftInfo(L2 毛玻璃：VBox→RefFrame(参考图画框,O1)→RefImage(入框等比居中)
##   +FourPoints(RichTextLabel 四要点))｜中央 CenterMount(PointCloudViewer/VideoPreview 互斥)
##   ｜右侧 RightBox(PanelContainer 毛玻璃背板 → RightInner：避让 Spacer44 + RightToggle 收起钮
##   + RightScroll→RightList 关卡列表)；
## 顶部 TitleBar「图鉴」标题条 + Background/Vignette 章节主题渐晕底（K7-1 替代灰底）；
## 底部 BottomBar「进入关卡/退出」。
## O-P1（2026-09-10 用户反馈五修之图鉴三项）：
##   O1 参考图边缘渐变羽化层删除（用户：红圈渐变删掉），RefImage 外包 RefFrame(PanelContainer)
##     画框——运行时随主题生成 StyleBoxFlat（边框 2px+圆角+阴影+4px 衬边，与图鉴卡同族做法）；
##   O2 「开场动画（回看）」项：左上 RefImage 显示开场末段参考图 ref_opening_hand.jpg
##     （项目前期素材原图复制），左下四要点区改自由短文案 OPENING_INTRO（该项无时间/地点/类型/
##     历史意义四要点，短文案防超出卡片）；章节态四要点表格保持，双向切换联动；
##   O5 退出路由 → 批次 AA / W5-1 升级**返回栈**：Game.pop_catalog_return() 出栈取最近
##     来源（goto_state 目标==CATALOG 时入栈快照旧态与旧 ctx，多跳链逐层弹出）——
##     退出时 LEVEL 来源且 ctx 含 chapter → 回 LEVEL（透传 replay 位保持左下退出钮
##     语义）；P3 MOVIE/TALK 来源全透传；P批波2（2026-09-10）SETTLE 来源透传回 SETTLE
##     （结算已由 level 覆盖层承载，经 game.gd 特判边缘路径重建 level 直显结算——原降级
##     MAIN_MENU 待办兑现；结算字段随入栈合并 settle_snapshot）；其余兜底 MAIN_MENU；
##     出栈即消费防串味（N9 断点恢复链保证回关卡=重进关卡+断点还原，预期行为）。
## M-F（spec §3.6）变更：ControlBar 从页面级常驻 HBox 降为 **VideoPreview 内悬浮层**
##   （PanelContainer 半透黑金底 α0.55 圆角 8，下沿内贴）：默认隐藏，鼠标进入视频 rect 淡入、
##   离开 0.5s 淡出、暂停时常显；含播放/暂停合一钮 + 时间轴 + 时间戳 + 全屏钮/缩小钮（新增）。
##   全屏进出 = **reparent 单播放器**升入 VideoFullscreenLayer(CanvasLayer layer=90，挂
##   GlobalUI(1) 之上、GlowLayer(100) 之下；根 Control 显式赋主题——CanvasLayer 主题不传播)，
##   全屏黑底铺满视口、视频按 16:9 fit；全屏控制条「点击/晃动浮现(_fs_wake)、2.5s 无操作隐藏」，
##   缩小钮退出回嵌入态。播控语义全沿用且**严禁顺手清理**（4.7 视频坑规避链）：
##   PREVIEW_SETTLE_FRAMES=3 首帧定格放行、stream_position 写读、get_stream_length()
##   （4.7 无 seek()/pause()/Theora.get_length()、get_fps() 无头挂死）、play 后显式 paused=false。
##   删黄条：视频选中态 CenterPad 隐藏（spec 根因：CenterPad 全衬底外露）；点云态恢复。
##   右侧列表半透 + 设置钮避让：RightBox 毛玻璃背板深 0.75/浅 0.78、圆角 16、顶缘高光边；
##   顶部 44px 避让间隔 → 列表首行全局顶 ≥108（右上设置钮区下缘之下）。
## 回修3（2026-09-08 用户实测三反馈）：
##   ① 嵌入态播控不可靠根因：控制条显隐判据依赖 mouse_entered/exited 信号——引擎 hover 通知
##      不冒泡祖先链，鼠标悬停条内子控件（播放钮/滑块）上时 ControlBar/VideoPreview 双双收不到
##      entered，_bar_hover/_bar_pointer_inside 同 false → 播放中 0.5s 淡出 → 瞄准中消失、拖完
##      滑块松手即失效。修复=位置法兜底 _pointer_on_bar/_pointer_on_video（鼠标全局位置落在
##      条/视频 rect 内即视为悬停，信号旗标短路缓存，无头/信号双路径兼容）。
##      次根因：_toggle_play 恢复播放仅置 paused=false——播放器停止态（播完 finished/reparent
##      离树）下不起播 →「点了没反应」。修复=is_playing()==false 时显式 play() + 回写 _video_pos。
##   ② 删冗余「播放」钮：视频选中态 BottomBar/EnterButton 隐藏（控制条悬浮播控已覆盖），
##      章节态恢复「进入关卡」；「退出」保留；_on_enter_level 仅章节路由。
##   ③ 播放/暂停钮符号化：运行时像素自绘 ▶/⏸ 图标（不依赖字体字形）替代文字（text 恒空），
##      文字说明转入 tooltip，随 paused 状态切换；全屏/缩小钮一并符号化统一。
## K-F（K7）既有：删「退出预览」按钮（预览即播放）；左占位文字删（K7-2）；L2 卡毛玻璃
##   12px 内边距（K7-3）；参考图入框（K7-4）；默认选中开场动画（K7-5，_ready 末 _select_video(null)）。
## 保留：点云旋转缩放（viewer 本体零改动）、四要点联动、重玩入口（LEVEL replay:true）。

# 四要点占位文案（spec 3.9/10.2：时间/地点/类型/历史意义，正式版每段约 100 字）。
# TODO（铁律/待用户审核）：以下为简明史实短句占位（本批约定：非台词、不写剧情），
# 正式文案由 AI 撰写并经用户审核后替换（spec 10.2、十三 #15）。
const FOUR_POINTS := {
	1: "【河姆渡榫卯木构件】\n时间：距今约七千年的新石器时代（河姆渡文化）。\n地点：浙江余姚河姆渡遗址。\n类型：木构榫卯建筑构件。\n历史意义：迄今发现最早的榫卯实物之一，被视为中国木构技术的源头。",
	2: "【保国寺瓜棱柱斗拱】\n时间：北宋（11 世纪初）。\n地点：浙江宁波保国寺。\n类型：木构斗拱与瓜棱柱。\n历史意义：江南现存最早的木构建筑之一，体现宋代榫卯技艺的成熟。",
	3: "【真如寺梁架榫卯】\n时间：元代（14 世纪）。\n地点：上海真如寺。\n类型：木构梁架榫卯。\n历史意义：元代木构梁架的珍贵实物，见证榫卯在民间建筑中的延续。",
	4: "【明式黄花梨圈椅】\n时间：明代（15~17 世纪）。\n地点：江南地区。\n类型：黄花梨木家具（圈椅）。\n历史意义：明式家具代表作，榫卯工艺在日用器物上的高峰。",
	5: "【参数化木构节点】\n时间：当代。\n地点：数字设计与工程实践。\n类型：参数化设计木构节点。\n历史意义：榫卯传统与数字制造结合，探索木构建筑的当代形态。",
}

@onready var ref_image: TextureRect = $Body/LeftInfo/VBox/RefFrame/RefImage  # O1：迁入 RefFrame 画框
@onready var ref_frame: PanelContainer = $Body/LeftInfo/VBox/RefFrame  # O1：参考图画框（随主题刷新）
@onready var four_points: RichTextLabel = $Body/LeftInfo/VBox/FourPoints
@onready var center_mount: Control = $Body/CenterMount
@onready var center_pad: Panel = $Body/CenterMount/CenterPad  # J5-1（G2）极淡内衬（M-F：视频态隐藏）
# plan 步骤 3 要求 RightList 由 ScrollContainer 包裹（右侧列表滚动）；K-F 起再套 RightBox。
# M-F：RightBox 改 PanelContainer 毛玻璃背板，内容迁入 RightInner（避让 Spacer + 收起钮 + 滚动列表）。
@onready var right_box: PanelContainer = $Body/RightBox
@onready var right_list: VBoxContainer = $Body/RightBox/RightInner/RightScroll/RightList
@onready var enter_btn: Button = $BottomBar/EnterButton
@onready var exit_btn: Button = $BottomBar/ExitButton
# K-F（K7-7）：视频单层播放——唯一预览播放器常驻中央（旧 CenterMount 内 VideoScrub/VideoPlayBtn/
# VideoExitBtn 已删）。M-F：控制三件套随悬浮层迁入 VideoPreview 子层，新增全屏钮/缩小钮。
@onready var video_preview: VideoStreamPlayer = $Body/CenterMount/VideoPreview
@onready var control_bar: PanelContainer = $Body/CenterMount/VideoPreview/ControlBar
@onready var play_pause_btn: Button = $Body/CenterMount/VideoPreview/ControlBar/BarRow/PlayPauseBtn
@onready var time_slider: HSlider = $Body/CenterMount/VideoPreview/ControlBar/BarRow/TimeSlider
@onready var time_label: Label = $Body/CenterMount/VideoPreview/ControlBar/BarRow/TimeLabel
@onready var fullscreen_btn: Button = $Body/CenterMount/VideoPreview/ControlBar/BarRow/FullscreenBtn
@onready var shrink_btn: Button = $Body/CenterMount/VideoPreview/ControlBar/BarRow/ShrinkBtn
@onready var right_toggle: Button = $Body/RightBox/RightInner/RightToggle
@onready var right_scroll: ScrollContainer = $Body/RightBox/RightInner/RightScroll

# 批次 W（P3-1）：色彩单源表（值不变；d 项拍板值级变化见对照表）。
const Palette := preload("res://scripts/palette.gd")
# J5-1（G2）：选中项高亮金黄（§0.5 标题金黄 #F5C542 同族）
const GOLD := Palette.MAIN_GOLD   # P3-1：主金单源（值不变，α1 同值）
# J5-3（G4）：开场动画视频源（工程内既有素材；opening_movie 首次播放路径不变）
const MOVIE_STREAM := "res://assets/animations/开场动画.ogv"
# AF 修复②（实机反馈批，2026-11-01）：开场回看英文字幕数据——与 opening_movie 同源共享
const OPENING_SUBTITLE_JSON := "res://assets/animations/opening_subtitles_en.json"
# O2：开场动画回看项配图（项目前期素材开场末段原图复制；手从画面上方伸向镜头纯黑底）
const OPENING_REF := "res://assets/reference_images/ref_opening_hand.jpg"
# O2：开场项左下自由短文案（该项无时间/地点/类型/历史意义四要点；温和口语、防超出卡片）
const OPENING_INTRO := "一段跨越七千年的相遇：当古老的手从画面深处伸来，与今日的手即将相触，见证之旅由此展开。通关之后，也可随时回到这里重温这段开场。"
# J6r3-1：预览首帧定格放行帧数——play() 后先让播放器跑几帧（首解码帧上屏）再暂停；
# 同帧 play+paused 会停在解码前导致预览黑屏（复走查 r_09/r_10 NG 根因）。K-F 保留不清理。
const PREVIEW_SETTLE_FRAMES := 3
# ---- M-F（spec §3.6，暂定值走查微调）----
# 批次 AB-3：*_LIGHT 浅档常量随深浅主题机制删除退役，深档为唯一值。
const RIGHT_BG_DARK := Color(0.12, 0.08, 0.03, 0.75)   # 右侧背板深档（70~80% 半透口径）
const BAR_BG_DARK := Color(0.08, 0.05, 0.02, 0.55)     # 悬浮控制条黑金底
const BAR_HIDE_DELAY := 0.5    # 嵌入态：鼠标离开视频 rect 后 0.5s 淡出
const FS_HIDE_DELAY := 2.5     # 全屏态：2.5s 无操作隐藏
## 批次 AA（W8-1，spec §11.4-1/§11.7 风险 3）：全屏进出同步通知——GestureHUD 订阅后当帧
## apply_dock（消除 0.25s 兜底轮询窗内的短暂叠压；HUD 侧懒接线 gesture_hud._sync_fs_watch）。
## 仅「状态真正翻转」时 emit（_set_fullscreen 首行同值守卫），消费方无需再比对变化沿。
signal video_fullscreen_changed(on: bool)
const FS_LAYER_ID := 62        # 全屏层层级（批次 Z Z6-P2-1：90→62——旧 90 压 TopStrip=63/
                               # HUD=64/GestureHUDLayer，全屏黑底盖住确认条（点不到→单槽被占）
                               # 与状态区；62=GlobalUI=1 之上、TopStrip 之下，弹条/状态区恒可见可点）
                               # GlowLayer=100 之下不变；tscn 静态值同步 62（运行时兜底同源）
const RIGHT_AVOID_SPACER := 44.0  # 右栏顶部避让间隔（设置钮区让位）

var _selected: Dictionary = {}
var _viewer: Control = null  # 中央 PointCloudViewer（批次 H，懒挂载）
var _selected_btn: Button = null  # J5-1（G2）当前高亮的列表项
# K-F（K7-7）：单层视频播放状态（原 _full_duration/_full_pos 全屏态改名平移）。
# _video_duration=0 表示未知（无头/解码未起，兜底 --:--）；
# _video_pos=时间轴播放位（seek 权威状态，无头读不回真实播放位时仍可由拖拽驱动）。
var _video_duration: float = 0.0
var _video_pos: float = 0.0
var _preview_pause_frames: int = 0  # J6r3-1：预览首帧定格倒计时（>0=放行解码中）
# ---- M-F：悬浮控制条显隐状态机 + 全屏进出 ----
var _bar_hover: bool = false          # 嵌入态：鼠标悬于视频 rect 内
var _bar_pointer_inside: bool = false # 回修1：鼠标悬于控制条上（全屏态保活判据，与嵌入态 _bar_hover 对称）
var _bar_hide_countdown: float = -1.0  # >0=淡出倒计时（BAR_HIDE_DELAY）；<0=不计时
var _is_fullscreen: bool = false      # 全屏态
var _fs_idle: float = 0.0             # 全屏无操作秒数（≥FS_HIDE_DELAY 隐藏控制条）
var _fs_bar_active: bool = false      # 全屏控制条活跃旗标（wake 置位、超时复位）
var _fs_layer: CanvasLayer = null     # 全屏层（挂场景内，CanvasLayer 高于 GlobalUI）
var _fs_root: Control = null          # 全屏根（黑底铺满视口；显式主题）
var _fs_host: Control = null          # 嵌入态宿主（CenterMount，恢复用）
# 回修3-③：自绘符号图标（▶/⏸/⛶/wyn）——运行时像素生成，不依赖字体字形；_update_play_btn 随态切换
var _icon_play: ImageTexture = null   # 播放（实心右向三角）
var _icon_pause: ImageTexture = null  # 暂停（双竖杠）
var _icon_fullscreen: ImageTexture = null  # 全屏（四角外扩括号）
var _icon_shrink: ImageTexture = null      # 缩小（四角内收括号）

func _ready() -> void:
	# I18n：tscn 静态文字经 t() 覆写（标题/退出钮；tooltip 由 _setup_video 经 t() 统一写）。
	($TitleBar/Title as Label).text = I18n.t("图鉴")
	exit_btn.text = I18n.t("退出")
	enter_btn.pressed.connect(_on_enter_level)
	enter_btn.disabled = true
	exit_btn.pressed.connect(_on_exit_pressed)  # O5：退出读 catalog_return 来源记忆路由
	right_toggle.pressed.connect(_on_right_toggle)  # K7-7：侧边栏收起/展开
	center_mount.resized.connect(_fit_video_rect)  # K7-7：中央列尺寸变化（收起侧栏/窗口拉伸）重配 16:9
	_setup_video()  # 默认选中前置依赖：stream 挂载与播控信号连接须先于 _select_video
	_setup_fullscreen_layer()  # M-F：全屏层（CanvasLayer + 黑底根）先行建好，默认不可见
	# M-F：悬浮控制条驱动——hover 进入/离开视频 rect；全屏钮/缩小钮互斥切换
	video_preview.mouse_entered.connect(_on_video_mouse_entered)
	video_preview.mouse_exited.connect(_on_video_mouse_exited)
	fullscreen_btn.pressed.connect(func() -> void: _set_fullscreen(true))
	shrink_btn.pressed.connect(func() -> void: _set_fullscreen(false))
	_fs_root.gui_input.connect(_on_fs_gui_input)  # 全屏点击/晃动 → 控制条浮现
	# 回修1（2026-09-08 用户实测「全屏要点好几下」）：控制条自身 hover/gui_input 接入——
	# 鼠标悬停控制条期间视为活跃（idle 不累积，瞄准不消失）；条空白区交互同样 wake。
	control_bar.mouse_entered.connect(_on_bar_pointer_entered)
	control_bar.mouse_exited.connect(_on_bar_pointer_exited)
	control_bar.gui_input.connect(_on_bar_gui_input)
	# 回修2（2026-09-08 用户实测「可点项是静止箭头」）：全场景可点项统一手型光标
	for b: Button in [play_pause_btn, fullscreen_btn, shrink_btn, right_toggle, enter_btn, exit_btn]:
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# K7-5：默认选中开场动画——进图鉴即有选中、中央定格首帧，不再空荡。
	# 审查回修 P2-1：须在 _rebuild_list() **之前**调用——_select_video(null) 自身无按钮可高亮，
	# 而 _rebuild_list 尾部 J6-P2-4 分支（sel_kind=="video"）会对新建回看项自动重套金黄高亮。
	_select_video(null)
	_rebuild_list()
	SaveManager.progress_changed.connect(_rebuild_list)
	# J5-1（G2）→ O1：画框/内衬/文字色挂载即生成（批次 AB-3：恒深档，主题切换刷新退役）。
	# K7-1/3：渐晕底 + L2 卡片毛玻璃同批生成。
	_apply_catalog_palette()
	# 批次 AB-3：theme_changed 订阅随深浅主题机制删除退役（_apply_catalog_palette 挂载直挂，恒深档）。

## J6：主题切换 → 重刷图鉴配色——批次 AB-3 随深浅主题机制删除退役（调色域在 _ready 直挂，恒深档）。

## J6 信号卫生硬化：显式断开连接在 autoload（常驻）上的信号。
func _exit_tree() -> void:
	if SaveManager.progress_changed.is_connected(_rebuild_list):
		SaveManager.progress_changed.disconnect(_rebuild_list)

## K-F（K7-7）：单层播放器初始化——视频源=工程既有开场动画.ogv（预览播放器唯一，
## 全屏层已删，不再双播放器共享 stream）。时间轴/合一按钮/播完信号挂控制条三件套。
func _setup_video() -> void:
	var stream: VideoStream = load(MOVIE_STREAM) if ResourceLoader.exists(MOVIE_STREAM) else null
	video_preview.stream = stream
	if stream != null:
		# 4.7 无头实证（J5-3 探针）：VideoStreamTheora 无 get_length()、get_fps() 无头挂死，
		# 总时长统一走 player.get_stream_length()（未播放即可读，实测 59.56s）
		var d: float = video_preview.get_stream_length()
		if is_finite(d) and d > 0.0:
			_video_duration = d
			time_slider.max_value = d
	play_pause_btn.pressed.connect(_toggle_play)
	time_slider.value_changed.connect(_on_time_slider_changed)  # 时间轴拖拽 seek/快进
	video_preview.finished.connect(_on_video_finished)  # 播完定格回首帧
	# 回修3-③：控制条按钮符号化——▶/⏸/⛶/缩小 自绘图标（text 置空，文字说明转 tooltip）
	_icon_play = _make_icon("play")
	_icon_pause = _make_icon("pause")
	_icon_fullscreen = _make_icon("fullscreen")
	_icon_shrink = _make_icon("shrink")
	play_pause_btn.text = ""
	play_pause_btn.icon = _icon_play
	play_pause_btn.tooltip_text = I18n.t("播放")
	fullscreen_btn.text = ""
	fullscreen_btn.icon = _icon_fullscreen
	fullscreen_btn.tooltip_text = I18n.t("全屏")
	shrink_btn.text = ""
	shrink_btn.icon = _icon_shrink
	shrink_btn.tooltip_text = I18n.t("缩小")
	# AF 修复②（实机反馈批，2026-11-01）：开场回看英文字幕覆盖层——共享组件
	# （scenes/shared/video_subtitle_overlay.gd，opening_movie 同源同档）挂载为 VideoPreview
	# **子节点**：①reparent 全屏（_set_fullscreen 单播放器升降）自动跟随，嵌入/全屏两形态
	# 同贴内容矩形（本播放器矩形恒 16:9=_fit_video_rect，内容矩形=播放器矩形）；②add_child
	# 尾挂=绘制序在 ControlBar 之上（白字黑描边在黑金条上可读，条自动隐藏后纯画面）；
	# ③mouse_filter=IGNORE（组件 _init 内建）不夺播控热区；④纯 stream_position 时间驱动
	# 常显（不接语言开关，与 opening_movie 同口径）；中文烧录字幕下方空隙带几何由组件托管。
	var subtitle_overlay: Label = (load("res://scenes/shared/video_subtitle_overlay.gd") as GDScript).new()
	subtitle_overlay.name = "VideoSubtitleOverlay"
	video_preview.add_child(subtitle_overlay)
	subtitle_overlay.call("setup", video_preview, OPENING_SUBTITLE_JSON)

## K-F（K7-1/2/3）：图鉴配色相关运行时资源统一生成/刷新（随主题深浅切换）。
func _apply_catalog_palette() -> void:
	_make_vignette()
	_apply_glass_cards()
	_apply_ref_frame()  # O1：参考图画框（原 G1 羽化层已删，随主题重生成样式）
	_apply_center_pad()
	_apply_four_points_color()
	_apply_right_panel()      # M-F-④：右侧列表毛玻璃背板（70~80% 半透）
	_apply_control_bar_style()  # M-F-①：悬浮控制条黑金半透背板

## K7-1：径向渐晕纹理挂 Vignette 层——中心全透明露出主题底、四边向角部渐暗
## （与关卡 J2-1/level_scene._make_vignette 同族做法，替换原不符主题的灰底）。
func _make_vignette() -> void:
	var vg := get_node_or_null("Vignette") as TextureRect
	if vg == null:
		return
	var grad := Gradient.new()  # 默认 2 锚点：offset 0 / 1
	grad.set_color(0, Color(0, 0, 0, 0))  # 中心：全透明
	# 批次 AB-3：深浅主题机制删除，角部压暗恒深档黑 0.55。
	grad.set_color(1, Color(0.0, 0.0, 0.0, 0.55))  # 边缘/四角：压暗
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL  # 径向填充
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	vg.texture = tex

## K7-3：L2 卡层毛玻璃（标题条/左信息框）运行时生成（spec §3.3 L2 + §3.1 卡片档）：
## 深 bg(0.243,0.173,0.086,0.45)、圆角 16、顶缘高光 2px、方向光影 shadow(3,5)/12、
## 12px 内边距透气（用户反馈「左框不透气」修复点）。批次 AB-3：恒深档。
func _apply_glass_cards() -> void:
	for n: String in ["TitleBar", "Body/LeftInfo"]:
		var card := get_node_or_null(n) as PanelContainer
		if card == null:
			continue
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.243, 0.173, 0.086, 0.45)
		sb.set_corner_radius_all(16)
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.border_width_top = 2  # 顶缘高光边（光源左上）
		sb.border_color = Color(Palette.STROKE_GOLD, 0.3)   # P3-1：描边金单源（值不变）
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 12
		sb.shadow_offset = Vector2(3, 5)
		sb.set_content_margin_all(12.0)
		card.add_theme_stylebox_override("panel", sb)

## O1（2026-09-10 用户反馈）：参考图画框——原 G1 径向渐变羽化覆盖层整体删除（红圈渐变），
## 改为 RefImage 外包 RefFrame(PanelContainer)：运行时随主题生成 StyleBoxFlat（边框 2px+
## 圆角 10+阴影 12/(3,5)+4px 衬边，深浅两档与图鉴 L2 卡/右侧背板同族配色协调）。
## 照片素材自带摄影棚暗背景属素材本体不动；衬边在等比留白区露出画框底色成「装裱」观感。
func _apply_ref_frame() -> void:
	if ref_frame == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.12, 0.05, 0.85)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(Palette.MAIN_GOLD, 0.5)   # P3-1：主金单源（值不变）
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(3, 5)
	sb.set_content_margin_all(4.0)
	ref_frame.add_theme_stylebox_override("panel", sb)

## G2：中央展示区极淡内衬（alpha≤0.15 非实心，与页面底区分展示区；IGNORE 不吃输入，
## 点云拖拽/滚轮仍由 viewer 根控件接收）。
func _apply_center_pad() -> void:
	if center_pad == null:
		return
	var pad := StyleBoxFlat.new()
	pad.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.10)
	pad.corner_radius_top_left = 12
	pad.corner_radius_top_right = 12
	pad.corner_radius_bottom_left = 12
	pad.corner_radius_bottom_right = 12
	center_pad.add_theme_stylebox_override("panel", pad)

## G2：四要点文字色（取主题 Label 文字色显式覆写 RichTextLabel；不改任何文案内容）。
## 批次 AB-3：深浅切换刷新退役，恒取深色主题 Label 字色。
func _apply_four_points_color() -> void:
	var th: Theme = ThemeManager.current_theme()
	if th == null:
		return
	four_points.add_theme_color_override("default_color", th.get_color("font_color", "Label"))

## M-F-④（spec §3.6 目标 4）：右侧列表毛玻璃背板——深 bg(0.12,0.08,0.03,0.75)/
## 浅 bg(1,0.94,0.80,0.78)、圆角 16、顶缘高光边（暂定值，走查微调）。坑 10：
## RightBox 已是 PanelContainer（非 Panel 子类），按实际类型取 panel stylebox 覆写。
func _apply_right_panel() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = RIGHT_BG_DARK
	sb.set_corner_radius_all(16)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_width_top = 2  # 顶缘高光边（光源左上）
	sb.border_color = Color(Palette.STROKE_GOLD, 0.3)   # P3-1：描边金单源（值不变）
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(3, 5)
	sb.set_content_margin_all(10.0)
	right_box.add_theme_stylebox_override("panel", sb)

## M-F-①（spec §3.6 目标 1）：悬浮控制条黑金半透背板 α0.55、圆角 8（暂定值）。
func _apply_control_bar_style() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BAR_BG_DARK
	sb.set_corner_radius_all(8)
	sb.border_width_top = 1
	sb.border_color = Color(1, 0.9, 0.6, 0.25)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	control_bar.add_theme_stylebox_override("panel", sb)

## G2：选中项高亮——列表按钮挂金黄描边毛玻璃样式（normal/hover/pressed 递亮），
## 前一选中项复位主题默认样式。仅视觉高亮，不改选中/路由逻辑。
func _highlight_selected(btn: Button) -> void:
	if _selected_btn != null and is_instance_valid(_selected_btn):
		for style: String in ["normal", "hover", "pressed", "disabled"]:
			_selected_btn.remove_theme_stylebox_override(style)
	_selected_btn = btn
	if btn == null:
		return
	# L-A（LA-3，spec §5.4）：三态 alpha 随主题 Button 半透明档归一 0.55/0.85/0.85
	# （旧 0.20/0.32/0.44 与主题不同构，构成根因④「多套浓度」矛盾面）。
	btn.add_theme_stylebox_override("normal", _gold_style(0.55))
	btn.add_theme_stylebox_override("hover", _gold_style(0.85))
	btn.add_theme_stylebox_override("pressed", _gold_style(0.85))

func _gold_style(bg_alpha: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(GOLD.r, GOLD.g, GOLD.b, bg_alpha)
	s.set_border_width_all(2)
	s.border_color = GOLD
	s.set_corner_radius_all(10)
	s.content_margin_left = 12
	s.content_margin_right = 12
	# L-A（LA-3，spec §5.4 归一口径）：投影对齐主题 Button normal 档 (3,5)/8 黑 0.35
	# （高亮钮与全页其余钮同光源语义，消除「部分钮无投影」的第二套光影）。
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 8
	s.shadow_offset = Vector2(3, 5)
	return s

func _rebuild_list() -> void:
	for child: Node in right_list.get_children():
		# 修复批 P3（2026-09-26）：先 remove_child 再 queue_free——queue_free 节点帧末才摘除，
		# 旧序帧内列表子件数=2M（6→12 一帧闪跳/滚动条跳变）。get_children() 返回副本可安全边遍历边摘。
		right_list.remove_child(child)
		child.queue_free()
	# J6-P2-4：记住当前选中，重建后若选中未变 → 对对应新按钮重套高亮（防高亮丢失）
	var sel_kind: String = String(_selected.get("kind", ""))
	var sel_ch: int = int(_selected.get("chapter", 0))
	var chapter_btns: Dictionary = {}  # 已通关 ch → 新按钮（重建后重套高亮用）
	var cleared: Array = SaveManager.get_progress()["cleared"]
	for ch: int in range(1, 6):
		var btn: Button = Button.new()
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND  # 回修2：可点项手型光标
		var lvl: Dictionary = LevelLibrary.get_level(ch)
		# I18n：title 为关卡数据中文标题（原文即键）；未通关行=模板键（词条表 Level %d · To be continued）。
		var title: String = I18n.t(String(lvl.get("title", I18n.t("第%d关") % ch))) if not lvl.is_empty() else I18n.t("第%d关") % ch
		if cleared.has(ch):
			btn.text = title
			btn.pressed.connect(func() -> void: _select_chapter(ch, btn))
			chapter_btns[ch] = btn
		else:
			btn.text = I18n.t("第%d关 未完待续") % ch
			btn.disabled = true
		right_list.add_child(btn)
	# 开场动画回看项
	var video_btn: Button = Button.new()
	video_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND  # 回修2：可点项手型光标
	video_btn.text = I18n.t("开场动画（回看）")
	video_btn.pressed.connect(func() -> void: _select_video(video_btn))
	right_list.add_child(video_btn)
	_selected_btn = null  # J5-1：列表重建后旧按钮已释放，高亮引用复位
	# J6-P2-4：选中未变 → 重套高亮到对应新按钮（video 项恒可点；chapter 仅在仍已通关时）
	if sel_kind == "video":
		_highlight_selected(video_btn)
	elif sel_kind == "chapter" and chapter_btns.has(sel_ch):
		_highlight_selected(chapter_btns[sel_ch])

func _select_chapter(ch: int, btn: Button = null) -> void:
	_selected = {"kind": "chapter", "chapter": ch}
	enter_btn.disabled = false
	enter_btn.visible = true  # 回修3-②：章节态恢复「进入关卡」（视频态隐藏见 _select_video）
	enter_btn.text = I18n.t("进入关卡")  # J5-3（G4）：章节态底部按钮语义（视频态冗余播放钮已删）
	_highlight_selected(btn)  # J5-1（G2）：选中项金黄描边高亮
	_show_video_preview(false)  # J5-3（G4）：改选章节时收起视频预览
	# 左栏联动：参考图 + 四要点占位（spec 4.6/9.2）
	var path: String = LevelLibrary.get_reference_image_path(ch)
	ref_image.texture = load(path) if ResourceLoader.exists(path) else null
	# I18n：四要点显示点 t()（FOUR_POINTS 常量表=中文键不动；zh 直通/en 命中词条）。
	four_points.text = I18n.t(String(FOUR_POINTS.get(ch, "（四要点文案待补充）")))
	# 中央联动：点云按章节重建（spec 9.1/9.2；数据缺失时 viewer 自行降级占位）
	_mount_cloud(ch)

## 中央点云挂载（懒创建一次，切换章节时同一 viewer 重建，避免节点反复增删）。
## J5-2（G3）金黄设参：tint_color/tint_strength/point_size @export 接口由 J4-2 先落，
## 本任务仅图鉴侧调参（viewer 本体零改动）——金黄 #F5C542（§0.5）、强度 0.85
## （计划暂定值 TODO J6 走查后微调）、点尺寸 0.005（J6-P1-3/J6r3-2 回修档）。
func _mount_cloud(ch: int) -> void:
	if _viewer == null:
		_viewer = load("res://scripts/point_cloud_viewer.gd").new()
		_viewer.name = "PointCloudViewer"
		_viewer.set("tint_color", GOLD)
		_viewer.set("tint_strength", 0.85)
		# J6-P1-3/J6r3-2 回修：0.024 走查实证实心金条（截图 12）→ 0.008；复走查 4x
		# 放大判 0.008 主体仍融合 → 与结算实例同降 0.005 档（可显单点）。TODO 后续复走查微调。
		_viewer.set("point_size", 0.005)
		center_mount.add_child(_viewer)
	_viewer.visible = true  # J5-3（G4）：视频预览收起后恢复点云显示
	var points_path: String = LevelLibrary.get_points_path(ch)
	_viewer.call("build", load(points_path) if ResourceLoader.exists(points_path) else null)
	# 批次 R（spec §5.1/§5.7）：点云态注册手势面板（选中后二指旋转/掌推拉缩放直调 viewer）
	add_to_group("gesture_panel")

func _select_video(btn: Button = null) -> void:
	_selected = {"kind": "video"}
	enter_btn.visible = false  # 回修3-②：删冗余「播放」钮（2026-09-08 用户反馈，控制条悬浮播控已覆盖）
	enter_btn.disabled = false  # 隐藏非禁用（可用性口径不回归；章节态恢复显示时直接可用）
	_highlight_selected(btn)  # J5-1（G2）：选中项金黄描边高亮
	_show_video_preview(true)  # J5-3（G4）：中间区域显示内嵌视频播放器（预览即播放层）
	# O2：开场项左栏联动——配图=开场末段参考图、左下=自由短文案（该项无四要点表格，
	# 双向切换与章节态互斥恢复：_select_chapter 各自覆写 ref_image/four_points）。
	ref_image.texture = load(OPENING_REF) if ResourceLoader.exists(OPENING_REF) else null
	four_points.text = I18n.t(OPENING_INTRO)

## 回修3-②：BottomBar 仅承接章节「进入关卡」路由（视频态按钮已隐藏，播控唯一入口=控制条
## 悬浮合一钮；防御性排除视频态手动 emit——不翻转播放态、不路由）。
func _on_enter_level() -> void:
	if _selected.is_empty() or String(_selected.get("kind", "")) != "chapter":
		return
	Game.goto_state(Game.State.LEVEL, {"chapter": int(_selected["chapter"]), "replay": true})

## O5（2026-09-10 用户 bug：关卡内设置→图鉴→关闭→回了主菜单，应回关卡）→ 批次 AA / W5-1
## （规格 §8.3/§8.4，2026-09-25）：单槽记忆升级**有界返回栈**，退出时
## `Game.pop_catalog_return()` **出栈取最近来源**（旧「读单槽+先复位」退役；pop 自带镜像
## 同步=消费后复位防串味，空栈返回 {} 由末行兜底）。路由分支逐条保持 O5/P3/P批波2 语义：
##   LEVEL 来源且快照 ctx 含 chapter → goto_state(LEVEL, 快照ctx)（透传 replay 位，
##     保持左下退出钮语义；N9 断点恢复链保证回关卡=重进关卡+断点还原）；
##   P3（批次 P 波 1）：MOVIE/TALK 来源 → goto_state(旧态, 快照ctx) 全透传（用户口径
##     「什么时候打开就退回去」：MOVIE 重播开场动画、TALK 重进对应章节对话，属可接受行为）；
##   P批波2（2026-09-10）：SETTLE 来源透传回 SETTLE——结算显示已由 level 覆盖层承载
##     （level._goto_settle 主路径零切换），goto_state(SETTLE) 经 game.gd 特判按边缘路径
##     重建 level 直显结算 UI（ctx 由入栈时合并 settle_snapshot，含 grade/elapsed/talent，
##     见 game.gd _push_catalog_return）；
##   其余（MAIN_MENU/BOOT/无记忆）兜底 MAIN_MENU（旧契约保持；多跳链下栈底 origin
##     逐层弹出即「从图鉴哪来回哪去」的治本通道——旧单槽被关卡覆盖造成的
##     LEVEL↔CATALOG 乒乓随出栈语义根除）。
func _on_exit_pressed() -> void:
	var ret: Dictionary = Game.pop_catalog_return()
	if int(ret.get("state", -1)) == Game.State.LEVEL:
		var ctx: Dictionary = ret.get("ctx", {}) if ret.get("ctx", {}) is Dictionary else {}
		if ctx.has("chapter"):
			Game.goto_state(Game.State.LEVEL, ctx)
			return
	# P3（批次 P 波 1）：MOVIE/TALK 来源透传回原态——快照 ctx 原样传回（出栈已消费），
	# 与 LEVEL 透传同构，做到「什么时候打开图鉴就退回到哪里」。
	var src_state: int = int(ret.get("state", -1))
	if src_state == Game.State.OPENING_MOVIE or src_state == Game.State.TALK:
		var ctx_ret: Dictionary = ret.get("ctx", {}) if ret.get("ctx", {}) is Dictionary else {}
		Game.goto_state(src_state, ctx_ret)
		return
	# P批波2（2026-09-10）：SETTLE 来源透传回 SETTLE——goto_state(SETTLE) 经 game.gd 特判
	# 按边缘路径重建 level 直显结算 UI（ctx 含 chapter/settle，W6 快照字段随入栈合并）。
	# MAIN_MENU/无记忆兜底 MAIN_MENU（旧契约保持）。
	if src_state == Game.State.SETTLE:
		var ctx_settle: Dictionary = ret.get("ctx", {}) if ret.get("ctx", {}) is Dictionary else {}
		Game.goto_state(Game.State.SETTLE, ctx_settle)
		return
	Game.goto_state(Game.State.MAIN_MENU)

## 批次 R（spec §5.1）：手势面板最小契约——中央点云查看区全局矩形
func gesture_panel_rect() -> Rect2:
	return center_mount.get_global_rect()

## 批次 R（spec §5.7）：点云面板可选契约——返回中央 PointCloudViewer（无/懒建前返回 null）
func get_gesture_viewer() -> Control:
	return _viewer

# ==================== K-F（K7-7）：视频单层播放（预览即播放） ====================

## K7-7：4.7 实证 VideoStreamPlayer 无视 stretch_mode、恒拉伸铺满自身 rect 绘制
## （窗口自查 kf_03 实证 516×464 盒内 16:9 片源被竖拉）→ 运行时把 rect 配成
## 宿主容器内最大 16:9 居中盒（同 KEEP_ASPECT_CENTERED 观感）。无头不排布
## （size 恒 0）时安全跳过；点云 viewer 铺满同列不受影响（互斥显隐）。
## M-F：宿主按全屏态二分——全屏 = _fs_root（视口 rect），嵌入 = CenterMount。
func _fit_video_rect() -> void:
	var host: Control = _fs_root if _is_fullscreen and _fs_root != null else center_mount
	if host == null:
		return
	var box: Vector2 = host.size
	if box.x <= 0.0 or box.y <= 0.0:
		return
	var w: float = box.x
	var h: float = w * 9.0 / 16.0
	if h > box.y:
		h = box.y
		w = h * 16.0 / 9.0
	video_preview.size = Vector2(w, h)
	video_preview.position = (box - video_preview.size) * 0.5

## 视频选中态显隐：中央预览+悬浮控制条；显示时清空并隐藏点云（J5-3 骨架保留）。
## M-F-③：显示时 CenterPad 隐藏（黄条根除——CenterPad 全衬底在 16:9 fit 后上下外露），
## 点云态恢复；M-F-②：切离视频态时若在全屏先退出（防御：全屏层随视频态收起）。
func _show_video_preview(show: bool) -> void:
	video_preview.visible = show
	if show:
		remove_from_group("gesture_panel")  # 批次 R（spec §11.1-6）：视频态移出组 → 手势静默
		center_pad.visible = false  # M-F-③：删黄条（视频矩形即播放器本体）
		_fit_video_rect()
		_show_bar(true)  # 进入视频态控制条先显（默认定格暂停态本就常显，统一口径）
		if _viewer != null:
			_viewer.call("clear")
			_viewer.visible = false
		# J6r3-1 规避实现保留（4.7 实证）：定格位 0.5s（片源 0s 为纯黑淡入，探针标定
		# 0s 亮度 0.003≈黑屏、0.5s=0.374 已显画面）→ play() 后显式 paused=false 防 hide
		# 残留 → 放行 PREVIEW_SETTLE_FRAMES 帧由 _process 倒计时收口定格。
		if video_preview.stream != null:
			video_preview.stream_position = 0.5
			video_preview.play()
			video_preview.paused = false
			_preview_pause_frames = PREVIEW_SETTLE_FRAMES
			_video_pos = 0.5
			time_slider.set_value_no_signal(0.5)
			_update_time_label()
	else:
		if _is_fullscreen:
			_set_fullscreen(false)  # M-F-②：切离视频态先退出全屏（防孤儿 reparent）
		center_pad.visible = true  # M-F-③：点云态恢复内衬
		_preview_pause_frames = 0
		video_preview.paused = true  # 收起预览即停播（防隐藏后仍在解码）
		_show_bar(false)

## 播放/暂停合一按钮（4.7 无 pause() 方法，paused 属性制）。
## 回修3-①次根因：恢复播放不能只置 paused=false——播放器停止态（播完 finished / reparent
## 离树）下 paused=false 不会起播，即用户实测「点了没反应」。is_playing()==false 时显式
## play() 兜底并回写 _video_pos 权威播放位（play() 会把播放位归零）。
func _toggle_play() -> void:
	if video_preview.stream == null:
		return
	if video_preview.paused:
		video_preview.paused = false
		if not video_preview.is_playing():
			video_preview.play()
			video_preview.stream_position = _video_pos
	else:
		video_preview.paused = true
	_update_play_btn()
	_update_bar_linger()  # M-F：播/停切换即时裁决控制条（播放中无 hover → 启动淡出）

## 合一按钮符号互切（回修3-③）：播放中=暂停双杠 ⏸、暂停中=播放三角 ▶（paused 属性为权威，
## text 恒空，文字说明在 tooltip）。
func _update_play_btn() -> void:
	var playing: bool = video_preview.stream != null and not video_preview.paused
	play_pause_btn.icon = _icon_pause if playing else _icon_play
	play_pause_btn.tooltip_text = I18n.t("暂停") if playing else I18n.t("播放")

## 时间轴拖动 → stream_position 写入 + _video_pos 权威状态（复用 _seek_full 语义）。
func _seek_video(pos: float) -> void:
	pos = clampf(pos, 0.0, _video_duration) if _video_duration > 0.0 else maxf(pos, 0.0)
	_video_pos = pos
	time_slider.set_value_no_signal(pos)
	if video_preview.stream != null:
		# 4.7 实证：无 seek() 方法，播放位以 stream_position 属性设置（无头亦可写读）。
		video_preview.stream_position = pos
	_update_time_label()

func _on_time_slider_changed(v: float) -> void:
	_seek_video(v)

func _update_time_label() -> void:
	var total_txt := "--:--" if _video_duration <= 0.0 else _fmt_time(_video_duration)
	time_label.text = "%s / %s" % [_fmt_time(_video_pos), total_txt]

## 播完 → 定格回 0.5s 首帧、按钮回「播放」态。
func _on_video_finished() -> void:
	_video_pos = 0.5
	if video_preview.stream != null:
		video_preview.stream_position = 0.5
	video_preview.paused = true
	time_slider.set_value_no_signal(0.5)
	_update_play_btn()
	_update_time_label()

## 侧边栏收起/展开（K7-7）：RightScroll 显隐，HBox 下中央区自动扩展。
func _on_right_toggle() -> void:
	right_scroll.visible = not right_scroll.visible
	right_toggle.text = "«" if right_scroll.visible else "»"

# ==================== M-F（spec §3.6）：悬浮控制条 + 全屏进出 ====================

## M-F：全屏层接线——结构静态于 tscn（VideoFullscreenLayer(CanvasLayer)/FsRoot/FsBlack，
## 跨批锚点与走查可见），此处只做运行时绑定：层级常量兜底同步、显式主题（坑 11：
## CanvasLayer 主题不传播）、resize 重配、宿主记录。
## 单播放器 reparent 方案：video_preview 连同悬浮控制条整体升入/回落，播控状态零分裂。
func _setup_fullscreen_layer() -> void:
	_fs_layer = $VideoFullscreenLayer
	_fs_layer.layer = FS_LAYER_ID  # 运行时常量兜底（防 tscn 静态值漂移双源）
	_fs_root = _fs_layer.get_node("FsRoot") as Control
	_fs_root.theme = ThemeManager.current_theme()  # 坑 11：新层根 Control 显式赋主题
	_fs_root.resized.connect(_fit_video_rect)
	_fs_host = center_mount

## M-F-②：全屏进出——reparent 单播放器（含控制条子层）。4.7 实证：reparent（离树/回树）
## 会把 VideoStreamPlayer 播放位重置 0 → 用既有规避链「stream_position 写读」在 reparent
## 前快照、reparent 后回写恢复（paused 同步显式置位，防 hide 残留坑）；播控状态由此跨进出
## 零丢失。按钮互斥（嵌入=全屏钮、全屏=缩小钮）；宿主 rect 重配 16:9。
func _set_fullscreen(on: bool) -> void:
	if on == _is_fullscreen:
		return
	if video_preview.stream == null:
		return  # 防御：无源不进全屏
	_is_fullscreen = on
	_fs_idle = 0.0
	var was_paused: bool = video_preview.paused
	var pos: float = video_preview.stream_position  # 快照播放位（规避链：stream_position 可写读）
	if on:
		_fs_layer.visible = true  # 层级显隐（CanvasLayer.visible 控制整层绘制+输入）
		_fs_root.visible = true
		video_preview.reparent(_fs_root)
	else:
		_fs_layer.visible = false
		_fs_root.visible = false
		video_preview.reparent(_fs_host)
	# reparent 重置兜底回写：播放位恢复 + 播放态显式续播（paused=false 防 hide 残留）
	video_preview.stream_position = pos
	if not was_paused:
		video_preview.play()
		video_preview.paused = false
	_fit_video_rect()
	fullscreen_btn.visible = not on
	shrink_btn.visible = on
	_fs_bar_active = on  # 进全屏控制条先显（网页播放器同款），2.5s 无操作再隐
	_update_bar_linger()
	# 批次 AA（W8-1）：全屏态同步通知（首行同值守卫保证只在真正翻转时 emit）——HUD 当帧重排，
	# 与 gesture_hud._fs_poll 0.25s 兜底轮询构成「同步优先 + 轮询兜底」双通道（spec §11.7 风险 3）
	video_fullscreen_changed.emit(on)

## 批次 Z（Z6-P2-1，spec §6）：全屏在场谓词（GestureRouter exit_flip 门消费）——全屏期
## 四指同翻不推进退出倒数（黑底层下倒数/确认不可见却照跑的根除）。未建层/裸实例恒 false。
func is_video_fullscreen() -> bool:
	return _is_fullscreen

## M-F-②：全屏点击/晃动浮现（_fs_root.gui_input 驱动；idle 归零 + 活跃置位）。
func _fs_wake() -> void:
	if not _is_fullscreen:
		return
	_fs_idle = 0.0
	_fs_bar_active = true
	_update_bar_linger()

func _on_fs_gui_input(ev: InputEvent) -> void:
	var wake: bool = ev is InputEventMouseMotion
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		wake = true
	if wake:
		_fs_wake()

## M-F-①：hover 进入视频 rect → 控制条淡入（idle/淡出计时归零）。
func _on_video_mouse_entered() -> void:
	_bar_hover = true
	_bar_hide_countdown = -1.0
	_update_bar_linger()

## M-F-①：hover 离开 → 延迟淡出裁决（暂停时常显兜底在 _update_bar_linger）。
func _on_video_mouse_exited() -> void:
	_bar_hover = false
	_update_bar_linger()

## 回修3-①：控制条显隐统一裁决——常显条件（悬停视频/条/全屏活跃/暂停/无源/视频隐藏）
## 任一成立则显示并停表；否则启动 BAR_HIDE_DELAY(0.5s) 淡出倒计时（由 _process 收口）。
## 悬停判据用位置法 helper（信号旗标短路缓存）——引擎 hover 通知不冒泡祖先链，鼠标悬停
## 条内子控件（播放钮/滑块）上时信号双盲区，纯信号判据会误淡出（嵌入态播控不可靠根因）。
func _update_bar_linger() -> void:
	var always: bool = _pointer_on_video() or _pointer_on_bar() or _fs_bar_active \
		or video_preview.paused or video_preview.stream == null or not video_preview.visible
	if always:
		_bar_hide_countdown = -1.0
		control_bar.visible = video_preview.visible
	else:
		_bar_hide_countdown = BAR_HIDE_DELAY

## 回修3-①：鼠标是否悬停于视频 rect 内（信号旗标短路 + 鼠标全局位置兜底）。
## 引擎 mouse_entered 只通知 hover 命中控件本身（不冒泡祖先），纯信号法在鼠标位于
## 子控件（控制条/按钮/滑块）上时会误判「已离开」；位置法以 rect 覆盖为准，双路径兼容。
func _pointer_on_video() -> bool:
	if _bar_hover:
		return true
	if not video_preview.is_visible_in_tree():
		return false
	return video_preview.get_global_rect().has_point(video_preview.get_global_mouse_position())

## 回修3-①：鼠标是否悬停于控制条内（同上口径；条内按钮/滑块上时信号盲区由位置法兜住）。
func _pointer_on_bar() -> bool:
	if _bar_pointer_inside:
		return true
	if not control_bar.is_visible_in_tree():
		return false
	return control_bar.get_global_rect().has_point(control_bar.get_global_mouse_position())

## 回修1：鼠标移入控制条 → 活跃保活（idle 归零 + 常显裁决）。
func _on_bar_pointer_entered() -> void:
	_bar_pointer_inside = true
	_bar_hide_countdown = -1.0
	_update_bar_linger()

## 回修1：鼠标离开控制条 → 复位（全屏态播放中恢复 idle 倒计时，与视频 hover 离开对称）。
func _on_bar_pointer_exited() -> void:
	_bar_pointer_inside = false
	_update_bar_linger()

## 回修1：控制条空白区点击/移动 → wake（PanelContainer STOP 消费事件，_fs_root 收不到；
## 只在全屏态生效，嵌入态由视频 hover 覆盖）。
func _on_bar_gui_input(ev: InputEvent) -> void:
	if _is_fullscreen and (ev is InputEventMouseMotion
			or (ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed)):
		_fs_wake()

## M-F-①：控制条直接显隐（进入视频态先显 / 切离视频态必隐）。
func _show_bar(v: bool) -> void:
	_bar_hide_countdown = -1.0
	control_bar.visible = v

## 控制条时间标记「mm:ss / mm:ss」（复用 J3-3 格式口径；就地实现避免跨场景耦合）。
func _fmt_time(s: float) -> String:
	return "%02d:%02d" % [int(s / 60.0), int(s) % 60]

# ==================== 回修3-③：控制条按钮符号化（自绘像素图标） ====================
# 用户反馈「不能改成直接符号式的吗？▶/⏸，非要是文字按钮吗」。方案：运行时 Image 像素绘制
# （实心三角=播放、双竖杠=暂停、四角括号=全屏/缩小），ImageTexture 挂 Button.icon——
# 不依赖字体字形（NotoSansSC 对 U+23F8 ⏸ 等符号覆盖不可保证），深浅主题同清晰（黑金条底恒深色）。

const ICON_PX := 20                        # 图标边长（px）
const ICON_COLOR := Color(0.95, 0.88, 0.70, 1.0)  # 浅金白（黑金控制条上两种主题均清晰）

## 按 kind 生成符号图标：play=实心右向三角｜pause=双竖杠｜fullscreen=四角外扩括号｜
## shrink=四角内收括号（同族几何、位置内移表达「收拢」语义）。
func _make_icon(kind: String) -> ImageTexture:
	var img := Image.create(ICON_PX, ICON_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := ICON_COLOR
	match kind:
		"play":
			# 等腰实心三角，尖朝右：x∈[5,16]，中线 y≈9.5 最宽
			for y in range(3, 17):
				var t: float = absf(float(y) - 9.5) / 7.0
				var xe: int = clampi(int(5.0 + 12.0 * (1.0 - t)), 5, 17)
				_icon_rect(img, 5, y, xe, y, c)
		"pause":
			# 双竖杠：x∈[4,7] 与 [12,15]，y∈[3,16]
			for y in range(3, 17):
				_icon_rect(img, 4, y, 7, y, c)
				_icon_rect(img, 12, y, 15, y, c)
		"fullscreen":
			_icon_corners(img, 2, 6, c)   # 边距 2、臂长 6 → 外扩
		"shrink":
			_icon_corners(img, 7, 3, c)   # 边距 7、臂长 3 → 内收
	return ImageTexture.create_from_image(img)

## 像素矩形填充（含端点；调用方保证坐标在 0..ICON_PX-1 内）。
func _icon_rect(img: Image, x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			img.set_pixel(x, y, c)

## 四角 L 括号（臂长 arm、线宽 2）：m=边距（2=外扩全屏、7=内收缩小）。
func _icon_corners(img: Image, m: int, arm: int, c: Color) -> void:
	var e: int = ICON_PX - 1
	# 左上 / 右上 / 左下 / 右下（横臂+竖臂各一条 2px 粗线）
	_icon_rect(img, m, m, m + arm, m + 1, c)
	_icon_rect(img, m, m, m + 1, m + arm, c)
	_icon_rect(img, e - m - arm, m, e - m, m + 1, c)
	_icon_rect(img, e - m - 1, m, e - m, m + arm, c)
	_icon_rect(img, m, e - m - 1, m + arm, e - m, c)
	_icon_rect(img, m, e - m - arm, m + 1, e - m, c)
	_icon_rect(img, e - m - arm, e - m - 1, e - m, e - m, c)
	_icon_rect(img, e - m - 1, e - m - arm, e - m, e - m, c)

func _process(delta: float) -> void:
	# M-F-①：嵌入态淡出倒计时收口（0.5s 到点隐藏）；回修3-①：收口前以位置法复核——
	# 鼠标已回视频/条 rect（信号盲区下 entered 未达）则保显，防瞄准瞬间消失点击落空。
	if _bar_hide_countdown > 0.0:
		_bar_hide_countdown -= delta
		if _bar_hide_countdown <= 0.0:
			_bar_hide_countdown = -1.0
			if _pointer_on_video() or _pointer_on_bar():
				_update_bar_linger()  # 复核悬停成立 → 保显（停表重裁决）
			else:
				control_bar.visible = false
	# M-F-②：全屏 idle 计时——2.5s 无操作且非暂停 → 控制条立即隐藏（超时即收，不再吃
	# 嵌入态 0.5s 二次延迟）；暂停时常显兜底（网页播放器同款语义）。
	# 回修1：鼠标悬停控制条期间视为活跃（idle 归零）——否则 motion 被条/按钮 STOP 消费
	# 到不了 _fs_root，idle 持续累积，用户瞄准按钮时条消失 → 点击落空 →「要点好几下」。
	# 回修3-①：保活判据改位置法 _pointer_on_bar()（信号盲区：鼠标在条内子控件上时
	# ControlBar 收不到 entered，纯信号判据仍会在瞄准按钮时超时隐藏）。
	if _is_fullscreen:
		_fs_idle += delta
		if _pointer_on_bar():
			_fs_idle = 0.0
		if _fs_idle >= FS_HIDE_DELAY and _fs_bar_active:
			_fs_bar_active = false
			if not video_preview.paused:
				_bar_hide_countdown = -1.0
				control_bar.visible = false
	if _preview_pause_frames > 0:  # J6r3-1 首帧定格倒计时（保留规避实现）
		_preview_pause_frames -= 1
		if _preview_pause_frames == 0:
			video_preview.paused = true
			_update_play_btn()
	if _selected.get("kind") != "video" or not video_preview.visible or video_preview.paused:
		return
	var cur := video_preview.stream_position
	if cur > _video_pos + 0.001:  # 只采纳超前播放位防覆写 seek 权威状态（现规则平移）
		_video_pos = cur
		time_slider.set_value_no_signal(cur)
	_update_time_label()
