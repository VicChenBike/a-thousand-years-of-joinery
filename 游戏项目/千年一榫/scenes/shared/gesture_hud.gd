extends Control
## 手势控制台三件套（批次 S 重排，spec §3~§4）：摄像头窗 / 状态条 / 说明栏。
## 批次 S：容器化布局（S1，不再手摆子件 y）；主菜单左下三联组+整组折叠（S3）；每状态独立落位
## （§4.1 停靠表终态，S4）；16:9 窗体（S2）；状态块 96×86 三行 clip+紧凑单行（S6）；底衬/字色
## 提级（S7）；LOADING/UNAVAILABLE 即清纹理只显占位（S13）；SHOP 覆盖层整组隐藏（S4）；
## 12 行文案精简（S15）。
## 穿透（§7.1 沿用）：根及全部子控件 mouse_filter=IGNORE；仅 FoldBtn/FoldRestore/LvToggleBtn 三钮 STOP。

# 批次 W（P3-1）：色彩单源表（值不变）。
const Palette := preload("res://scripts/palette.gd")
const LEFT_BG_COLOR := Color("#3E2C16")    # 左手块底色（沿用批次 R）
const RIGHT_BG_COLOR := Color("#5A4019")   # 右手块底色
const HAND_LEFT_COLOR := Color("#3E7BBD")  # 手别字色左=蓝（沿用）
const HAND_RIGHT_COLOR := Color("#C0504D") # 手别字色右=红（沿用）
const CONF_GREEN := Palette.CONF_GREEN       # 置信度 >0.8（P3-1 单源，值不变）
const CONF_YELLOW := Color("#D9A441")      # 置信度 >0.5
const CONF_RED := Palette.CURSOR_RED         # 其余（P3-1 单源，值不变）
const NO_HAND_GRAY := Palette.NO_HAND_GRAY   # 批次 T T3：未检出灰提亮（P3-1 单源，值不变）
# 批次 S 的行置灰机制（灰行降不透明度常量）整体废止（T1 动态集合后无不可用行，T3 根因闭环）
# 批次 AB-3：PANEL_BG_LIGHT/TEXT_LIGHT 浅档随深浅主题机制删除退役，深档为唯一值。
const PANEL_BG_DARK := Color(0.20, 0.15, 0.07, 0.85)   # 底衬深档（T3；旧 α0.78 留痕）
const TEXT_DARK := Palette.TEXT_DARK_HUD        # HUD 字色（T3 提亮；P3-1 单源，值不变）

## 13 条规范行（批次 AA W3-5 文案表定稿逐字，spec §6.4——序号即显示序号，跨场景不重排；
## 行数仍 13 = 11 条手势 + 1 图例行 + 1 参考框行；手别标注经 gesture_map/router 门控核实照实
## 标注：移动/单击/缩放/撤销双手皆可、减选=右、清空=双手握拳（批次 AD §4.3.4）、旋转与删除=左、对接与退出=双手；
## LEVEL 双列列宽 170 硬预算（clip_text=true 不截断红线），**LEVEL 内指名用简写**
## （食=食指、中=中指、无名=无名指），**全称由图例行（ROW_LEGEND）给出**、非 LEVEL 状态的
## 全局行组用全称；宽度实测定档见 test_aa_gesture_remap 段 5d。
## 批次 AA W3-7 处置：ROW_CLICK 死常量（批次 V §7.1 起零消费）**退役删除**，其语义并入新增
## ROW_CLICK_SELECT；ROW_ACTIVATE/ROW_SELECT 随「单击/选块」合并为同一行一并退役。
const ROW_MOVE := "1 移动光标【左/右】食指"
const ROW_CLICK_SELECT := "2 单击/选块【左/右】食+中"
const ROW_CANCEL := "3 减选【右】食+中"
const ROW_ROTATE := "4 旋转视角【左】食+中"
const ROW_ZOOM := "5 缩放【左/右】手掌推拉"
const ROW_DIG := "6 删除/挖除【左】食+中+无名"
const ROW_CLEAR := "7 清空选择【双手】握拳"   # 批次 AD §4.3.4 文案同步：清空通路改双手握拳，
                                       # 旧「【右】掌静止1秒」（右掌 dwell）随 dwell 清空彻底废除退役
                                       #（旧文案留痕：本行原值 "7 清空选择【右】掌静止1秒"）
const ROW_UNDO := "8 撤销/重做【左/右】掌翻转"
const ROW_JOIN := "9 对接尝试【双手】食+中"
const ROW_EXIT := "10 退出【双手】四指同翻"
const ROW_FOCUS := "11 聚焦/锐眼 走屏幕按钮"
## 批次 AA（W3-5，spec §6.4-A 序 12）：图例行——LEVEL 简写的全称承载处（小指本批无手势不入表）。
const ROW_LEGEND := "食=食指 中=中指 无名=无名指"
## 批次 Y（Y-A14，spec §2）：参考框说明行——「框=推荐活动区」口径（拍板三：参考框仅视觉参考，
## 判定维持全画面不变）。入 LEVEL 行组（列高预算 7×15=105≤110 实测复核；全局行组受
## SHOP/SETTINGS 88px 行高预算约束不入，几何约束留痕）。
const ROW_FRAME := "参考框=推荐活动区"
## 批次 V（V9/V14，spec §7.1）：全局提示行组——无序号独立文案，不复用带序号 LEVEL 系常量
## 批次 X（P5-c）→批次 AA（W3-5）：ROW_G_CLICK 改全称「食指+中指」（本组是全称图例承载处，
## 手势语义随 W3-4 单击=食+中同步）；其余三行零改动。
const ROW_HANDS := "左/右手状态 状态条实时显示"
const ROW_G_MOVE := "移动光标 【左/右】竖起食指"
const ROW_G_CLICK := "单击确认 【左/右】食指+中指"
const ROW_G_EXIT := "退出 【双手】四指同翻"
const GLOBAL_HINT_ROWS := [ROW_HANDS, ROW_G_MOVE, ROW_G_CLICK, ROW_G_EXIT]
## 场景→行集合映射（spec §4-1 表七态；批次 V §7.1 重排：七个非关卡状态统一含四全局行组，
## LEVEL 13 条随批次 AA W3-5 重排）。旧值留痕：MAIN_MENU=[ROW_MOVE,ROW_CLICK,ROW_EXIT]、
## OPENING_MOVIE/TALK=[ROW_MOVE,ROW_CLICK]、CATALOG=[ROW_MOVE,ROW_CLICK,ROW_ROTATE,ROW_ZOOM,ROW_EXIT]、
## SETTINGS=[ROW_MOVE,ROW_CLICK,ROW_EXIT]、SETTLE=["单击=选钮 · 二指拖=转 · 掌=缩放"]、
## LEVEL（批次 X P5-c 13 行）=[1 移动光标竖起食指/3 激活面板/4 选块划选/5 旋转/6 缩放视角左手/
## 7 竖三指/8 取消/9 竖四指/10 聚焦/11 撤销/12 竖食指对接/13 退出/参考框]
const SCENE_HINTS := {
	"MAIN_MENU": GLOBAL_HINT_ROWS,
	"OPENING_MOVIE": GLOBAL_HINT_ROWS,
	"TALK": GLOBAL_HINT_ROWS,
	"LEVEL": [ROW_MOVE, ROW_CLICK_SELECT, ROW_CANCEL, ROW_ROTATE, ROW_ZOOM, ROW_DIG,
		ROW_CLEAR, ROW_UNDO, ROW_JOIN, ROW_EXIT, ROW_FOCUS, ROW_LEGEND, ROW_FRAME],   # 批次 AA（W3-5，spec §6.4-A）：11 手势 + 图例 + 参考框（原 12 手势 + 参考框，「激活面板/选块」并入单击行）
	"CATALOG": GLOBAL_HINT_ROWS + [ROW_ROTATE, ROW_ZOOM],   # 点云观察两行保留（批次 V §7.1）
	"CATALOG_FS": GLOBAL_HINT_ROWS + [ROW_ROTATE, ROW_ZOOM],   # 批次 AA（W8-1，spec §11.4-1）：全屏视频子态行组=嵌入态同源（hint 300×120 预算 6×19=114≤120）
	"SHOP": GLOBAL_HINT_ROWS,   # 批次 V（V14，spec §7.1）：旧 2 专用短行常量退役（["食指=光标","中指=单击"] 留痕）
	"SETTINGS": GLOBAL_HINT_ROWS,
	"SETTLE": GLOBAL_HINT_ROWS + ["点选钮【左/右】·拖转/掌缩放【左/右】"],   # 批次 AA（W3-5，spec §6.4-C）：掌缩放随 W3-1 双手通用 →【左/右】（SETTLE hint 224→240 同步，见 _dock_cfg）
}
const SCENE_HINTS_FALLBACK := GLOBAL_HINT_ROWS   # 批次 V：FALLBACK=GLOBAL（旧 [ROW_MOVE, ROW_CLICK, ROW_EXIT] 留痕）
## 字号/行高（spec §4-2/§5；J1/J2：行高为 min 值容器实高按字体实高适配——批次 T 探针实测
## font14→22px，回填 J2：MAIN 94/MOVIE 44/SHOP·SETTINGS 66）。
## 批次 X（P1-b，spec §2）：字号三族 +1~2 档（用户「说明栏偏小」，LEVEL 10px 为主诉主体）；
## 行高 min 常量零改动，有效行高随字体实高浮动。「行距压缩」落点=行字体行框压缩（_hint_row_font
## spacing_top −1/bottom −2，实测 h15 23→20/h14 22→19/h12 18→15，probe p1_probe_fontshave_temp）
## ——Label 级 line_spacing 对单行行 no-op，字体级行框压缩为唯一有效机制；行标签显式挂字体后
## 无头测试（旧=内置 fallback 字体）与生产（旧=Noto 主题）同语境，两语境实高分叉根除。
## cfg hint 尺寸零变化复核（实测口径）：MAIN 28+4×20=108≤116、SHOP/SETTINGS/UNKNOWN 4×20=80≤88、
## LEVEL 6×15=90≤110、CATALOG 6×19=114≤120、SETTLE 5×15=75≤140——红线件
## test_t_dock_expand/test_u_dock_anchors（后者经 main.tscn 带 Noto 主题）逐格断言零扰动。
const HINT_FONT_MAIN := 15
const HINT_ROW_H_MAIN := 20.0
const HINT_FONT_LEVEL := 12
const HINT_ROW_H_LEVEL := 15.0
# 批次 U（U5，spec §5）：停靠锚定常量（窗相对 content px 口径；SHOP 说明栏列距 8.0 例外随表列明）
const EDGE_MARGIN := 14.0
const GROUP_GAP := 6.0
const GROUP_GAP_H := 12.0
const COLUMN_TOP := 106.0   # R2 双审回修 A（用户「UI 重叠不允许」铁律）：98→106——设置钮底缘
# 102 × 旧顶 98 实叠 4px 根除（4px）＋余 4px 随组对齐；右上竖排组（MOVIE/TALK/SETTINGS/
# UNKNOWN；LEVEL 批次 V 起改 LEVEL_DOCK_TOP 同源下移）cam/status/hint 整体下移 8px
#（_dock_cfg 各键 my 同步 +8，组内 GROUP_GAP=6 不变）
# 批次 V（V14，spec §7.1）：旧 SHOP 2 专用短行常量退役（["食指=光标","中指=单击"] 留痕）——
# SHOP 并入四全局行组（SCENE_HINTS["SHOP"]）；_hint_folded 会话级折叠字典沿用（U5②）
# 批次 U（U5⑨）：摄像头窗最小尺寸表（16:9 整数倍——含奇数高 99/81/63，不声明偶数取整，双审 P2-3）
# 批次 U（U5⑨）：摄像头窗最小尺寸表（16:9 整数倍——含奇数高 99/81/63，不声明偶数取整，双审 P2-3）
const MIN_SIZES := {
	"MAIN_MENU": Vector2(176, 99), "OPENING_MOVIE": Vector2(144, 81), "TALK": Vector2(144, 81),
	"LEVEL": Vector2(144, 81), "CATALOG": Vector2(112, 63), "SETTLE": Vector2(144, 81),
	"SHOP": Vector2(128, 72), "SETTINGS": Vector2(128, 72), "UNKNOWN": Vector2(144, 81),
	# 批次 AA（W8-1，spec §11.4-1）：CATALOG 全屏视频子态独立键——最小尺寸与嵌入态同值
	#（144×81 为 112×63 的 16:9 整数倍，缩放因子下限同源；R8-h 三处键集合一致断言覆盖）
	"CATALOG_FS": Vector2(112, 63),
}
# 批次 V（V15，spec §7.3）：LEVEL 停靠组下移顶——JoinView 底 266（锚 0.4105×648）+18 间隙；
# status/hint my 经 LEVEL_DOCK_TOP 同源式推导（_dock_cfg LEVEL 分支），底界在键鼠提示条顶 621 之上
const LEVEL_DOCK_TOP := 284.0
# 批次 V（V13，spec §7.2）：折叠竖条宽档——规格 30∈[28,32] 档，五竖条态统一
#（批次 X P1-a 起仅 MAIN_MENU/CATALOG/SHOP/SETTLE/UNKNOWN 五态走竖条，四态改横条见下）
const FOLD_BAR_W := 30.0
# 批次 X（P1-a，spec §2）：四态折叠横条——OPENING_MOVIE/TALK/LEVEL/SETTINGS 折叠后改横条
#（120×30，横排「▲ 手势说明」同组整组条内居中、▲=folded 语义不变、位置在原 hint 锚点处、
# ax=R 者贴右缘）；其余五态（MAIN_MENU/CATALOG/SHOP/SETTLE/UNKNOWN）维持竖条零变化。
# key 名与 _dock_cfg 分支键同源（SETTINGS 经 _ 落分支，apply_dock_state key 字符串一致）。
const HORIZONTAL_FOLD_KEYS := ["OPENING_MOVIE", "TALK", "LEVEL", "SETTINGS"]
const H_FOLD_W := 120.0
const H_FOLD_H := 30.0
const H_FOLD_GROUP_GAP := 4.0   # 横条组内 ▲ 钮与「手势说明」标题间距

const HINT_FONT_CATALOG := 14
const HINT_ROW_H_CATALOG := 17.0
# 批次 AA（W8-1，spec §11.4-1 暂定值）：全屏谓词兜底轮询间隔 0.25s（【暂定值·待用户复验】）
const FS_POLL_INTERVAL := 0.25
## 批次 AA（W8-2，spec §11.4-2「行高/字号定档」）：SHOP 顶排专属字号/行高档——4 全局行在
## 15/20 档下内容最小高 4×20=80 > 顶排 hint 高 74（80 会把面板撑回 80、底缘 96 越过格网顶 92），
## 故换 14/17 档；与 CATALOG 同族（单源同名式，两档常量并列便于一次调参）。
const HINT_FONT_SHOP := 14
const HINT_ROW_H_SHOP := 17.0
const STATUS_FONT := 13
const SETTLE_FONT := 12

@onready var camera_window: TextureRect = $CameraWindow
@onready var camera_hint: Label = $CameraWindow/CameraHint
@onready var camera_bg: ColorRect = $CameraWindow/CameraBg
@onready var status_row: VBoxContainer = $StatusRow
@onready var left_panel: Panel = $StatusRow/LeftPanel
@onready var right_panel: Panel = $StatusRow/RightPanel
@onready var status_panel: PanelContainer = $StatusPanel
@onready var status_line: Label = $StatusPanel/StatusLineBox/StatusLine
@onready var guide_panel: PanelContainer = $GuidePanel
@onready var guide_vbox: VBoxContainer = $GuidePanel/GuideVBox
@onready var guide_header: HBoxContainer = $GuidePanel/GuideVBox/GuideHeader
@onready var guide_title: Label = $GuidePanel/GuideVBox/GuideHeader/GuideTitle
@onready var guide_list: GridContainer = $GuidePanel/GuideVBox/GuideList
@onready var fold_btn: Button = $GuidePanel/GuideVBox/GuideHeader/FoldBtn
@onready var hint_fold_btn: Button = $HintFoldBtn
var skeleton: Control = null   # 批次 U（U6）：骨架子件（UD-4 挂载；_ready 内挂 CameraWindow/CameraSkeleton）
var fold_title: Label = null   # 批次 V（V13，spec §7.2）：折叠竖条竖排「手势说明」标签（_ready 代码构建，根 overlay 定位）
# 批次 X（P1-b）：说明栏行字体——Noto w400 变体 + 行框压缩（spec「行距压缩」唯一有效机制；
# _ready 构建，_build_list 挂各行）。top −1/bottom −2 实测 shave −3px（见字号注释块实测复核）。
var _hint_row_font: FontVariation = null
## 批次 AA（W8-2，spec §11.4-2）：SHOP 顶排专属行字体——与 _hint_row_font 同源（Noto w400 变体、
## 行框压缩），仅 spacing_bottom −2→−3 把 font14 行实高 19→18（实测 get_height(14)：(-1,-2)=19 /
## (-1,-3)=18），使 4 行内容最小高 4×18=72 ≤ 顶排 hint 高 74（底 90 < 格网顶 92）。规格
## 「内容最小高 4×18=72」的定稿值即本档；非 SHOP 状态沿用 _hint_row_font 零变化。
var _hint_row_font_shop: FontVariation = null

## 行字体按场景选档（_build_list 单点消费）
func _row_font_for(scene_key: String) -> Font:
	if scene_key == "SHOP" and _hint_row_font_shop != null:
		return _hint_row_font_shop
	return _hint_row_font

var _folded := false      # 批次 U（U5②）：主菜单说明栏折叠（gesture_panel_folded 语义收窄=只收说明栏，旧档无损兼容）
var _hint_folded: Dictionary = {}   # 批次 U（U5②）：各状态说明栏折叠（会话级不写档；主菜单走 _folded/存档键）
var _dock_st := -1
var _dock_settings_open := false
var _dock_shop_open := false
var _dock_poll := 0.0
# 批次 AA（W8-1，spec §11.4-1「全屏态识别机制」）：全屏谓词 0.25s 节流兜底轮询（变化沿才重排）
# + video_fullscreen_changed 同步通知（§11.7 风险 3：同步优先、轮询兜底）双通道。
# _fs_watch=当前已接信号的图鉴场景实例（懒接线：换场景即断旧接新，_exit_tree 显式退订）。
var _fs_poll := 0.0
var _fs_on := false
var _fs_watch: Node = null
# 批次 U（U5④偏离①配套）：LEVEL 顶部 20px 收起钮行空隙载体——HintFoldBtn overlay 不占布局行，
# 空隙经 GuideVBox stylebox content_margin_top 动态给（_ready 挂 override，apply_dock_state 按键调）
var _vbox_pad := StyleBoxEmpty.new()

func _ui_text() -> Color:
	return TEXT_DARK

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# I18n：tscn 静态初值经 t() 覆写（左/右手块/状态行/摄像头窗占位；后续运行时由
	# _on_state/_refresh_camera_placeholder 动态刷新——消费点均已接 t()）。
	($StatusRow/LeftPanel/VBox/LeftTag as Label).text = I18n.t("左手")
	($StatusRow/LeftPanel/VBox/LeftLabel as Label).text = I18n.t("未检出")
	($StatusRow/LeftPanel/VBox/LeftConf as Label).text = I18n.t("未检出")
	($StatusRow/RightPanel/VBox/RightTag as Label).text = I18n.t("右手")
	($StatusRow/RightPanel/VBox/RightLabel as Label).text = I18n.t("未检出")
	($StatusRow/RightPanel/VBox/RightConf as Label).text = I18n.t("未检出")
	status_line.text = I18n.t("左") + " " + I18n.t("未检出") + " ｜ " + I18n.t("右") + " " + I18n.t("未检出")
	camera_hint.text = I18n.t("摄像头启动中…")
	# 批次 V（V13，spec §7.2）：折叠标题「手势说明」标签（代码构建；挂根 overlay 定位——若挂
	# GuidePanel 下会被 PanelContainer 最小尺寸钳制把 30 宽竖条撑爆，hint_fold_btn 同款思路）；
	# 先建后 _apply_panel_bg() 接管字色（批次 AB-3：恒深档）。批次 X（P1-a）起双态：
	# 竖条态旋转 90° 竖排（apply_dock_state 几何）、横条态不旋转横排同组随排，创建处恒 rotation=PI/2
	# 仅竖条态首帧缺省（每次 apply_dock_state 按态覆写）。
	fold_title = Label.new()
	fold_title.name = "FoldTitle"
	fold_title.text = I18n.t("手势说明")
	fold_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fold_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fold_title.add_theme_font_size_override("font_size", 14)
	fold_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fold_title.rotation = PI / 2.0
	add_child(fold_title)
	_apply_panel_bg()
	_apply_hand_backgrounds()
	# 批次 X（P1-b）：行字体构建（先于 _build_list）——变量字体裸 FontFile 取
	# fvar 默认实例（NotoSansSC 默认=Thin100），须显式提 wght 400（tag=0x77676874=2003265652）。
	_hint_row_font = FontVariation.new()
	_hint_row_font.base_font = load("res://fonts/NotoSansSC[wght].ttf")
	_hint_row_font.variation_opentype = {2003265652: 400}
	_hint_row_font.spacing_top = -1
	_hint_row_font.spacing_bottom = -2
	# 批次 AA（W8-2）：SHOP 顶排专属行字体（同源仅 spacing_bottom 多压 1px → 行实高 19→18）
	_hint_row_font_shop = FontVariation.new()
	_hint_row_font_shop.base_font = load("res://fonts/NotoSansSC[wght].ttf")
	_hint_row_font_shop.variation_opentype = {2003265652: 400}
	_hint_row_font_shop.spacing_top = -1
	_hint_row_font_shop.spacing_bottom = -3
	guide_vbox.add_theme_stylebox_override("panel", _vbox_pad)   # 批次 U：LEVEL 顶部钮行空隙载体
	_build_list("MAIN_MENU")
	_folded = bool(SaveManager.get_settings().get("gesture_panel_folded", false))
	fold_btn.pressed.connect(_on_fold_pressed)
	hint_fold_btn.pressed.connect(_on_hint_fold_pressed)
	# 批次 U（U6，spec §4-U6-5）：骨架子件挂 CameraWindow 下（随窗缩放自动跟随；IGNORE 穿透）
	var sk: Control = (load("res://scenes/shared/camera_skeleton.gd") as GDScript).new()
	sk.name = "CameraSkeleton"
	camera_window.add_child(sk)
	skeleton = sk
	GestureBridge.gesture_state_received.connect(_on_state)
	GestureBridge.camera_frame_received.connect(_on_camera_frame)
	GestureBridge.load_state_changed.connect(_on_load_state)
	# 批次 AA（W4-10）：流真值开→关 边沿即清陈旧纹理（「设备/流真值变化时清」的另一半——
	# camera_closed 不改桥状态，若不订阅则陈旧帧会留到下一次状态边沿才清）。
	GestureBridge.camera_stream_changed.connect(_on_camera_stream_truth)
	SaveManager.settings_changed.connect(_refresh_visibility)
	# I18n：语言切换实时重刷——行组重建（apply_dock 内 _build_list 同 key）+折叠标题+摄像头窗占位。
	# 状态条（左/右手块）由下一次 gesture_state_received 数据驱动刷新（HUD 不缓存手部数据）。
	if not I18n.language_changed.is_connected(_on_language_changed):
		I18n.language_changed.connect(_on_language_changed)
	var game: Node = get_node_or_null("/root/Game")
	if game != null and not game.state_changed.is_connected(_on_game_state_changed):
		game.state_changed.connect(_on_game_state_changed)
	# 批次 Z（Z6-P2-8，spec §6）：覆盖层开合即时重排——Game.open/close_overlay 补轻量信号
	# overlay_changed，当帧 apply_dock；旧仅 0.5s 低频轮询 → 开设置后 ≤0.5s 内 HUD 仍按
	# LEVEL 停靠压在面板上（HUD 层 64 > 覆盖层 1）。_dock_poll 轮询保留作兜底。
	if game != null and game.has_signal("overlay_changed") \
			and not game.overlay_changed.is_connected(_on_overlay_changed):
		game.overlay_changed.connect(_on_overlay_changed)
	apply_dock()

func _exit_tree() -> void:
	# J6 信号卫生（批次 N 硬化口径，沿用批次 R）：断开挂在 autoload/常驻节点上的命名连接
	if GestureBridge.gesture_state_received.is_connected(_on_state):
		GestureBridge.gesture_state_received.disconnect(_on_state)
	if GestureBridge.camera_frame_received.is_connected(_on_camera_frame):
		GestureBridge.camera_frame_received.disconnect(_on_camera_frame)
	if GestureBridge.load_state_changed.is_connected(_on_load_state):
		GestureBridge.load_state_changed.disconnect(_on_load_state)
	if GestureBridge.camera_stream_changed.is_connected(_on_camera_stream_truth):
		GestureBridge.camera_stream_changed.disconnect(_on_camera_stream_truth)
	if SaveManager.settings_changed.is_connected(_refresh_visibility):
		SaveManager.settings_changed.disconnect(_refresh_visibility)
	if I18n.language_changed.is_connected(_on_language_changed):
		I18n.language_changed.disconnect(_on_language_changed)
	# Z6-P2-8：overlay_changed 具名断开（挂在 autoload Game 上，须显式退订）
	var game: Node = get_node_or_null("/root/Game")
	if game != null and game.has_signal("overlay_changed") \
			and game.overlay_changed.is_connected(_on_overlay_changed):
		game.overlay_changed.disconnect(_on_overlay_changed)
	# 批次 AA（W8-1）：全屏信号懒接线显式退订（挂图鉴场景上，随场景释放自动断，双保险）
	_disconnect_fs_watch()

## 批次 Z（Z6-P2-8，spec §6）：覆盖层开合 → 当帧停靠重排（apply_dock 单漏斗；
## 0.5s _dock_poll 轮询保留兜底）。
func _on_overlay_changed(_opened: bool) -> void:
	apply_dock()

## 批次 W（P3-3b）：主题翻转回调——批次 AB-3 随深浅主题机制删除退役。
func _on_game_state_changed(_from: int, _to: int) -> void:
	apply_dock()

## 左右手块底色（沿用批次 R §7.1 终态）
func _apply_hand_backgrounds() -> void:
	for pair: Array in [[left_panel, LEFT_BG_COLOR], [right_panel, RIGHT_BG_COLOR]]:
		var sb: StyleBoxFlat = StyleBoxFlat.new()
		sb.bg_color = pair[1]
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(4)
		(pair[0] as Panel).add_theme_stylebox_override("panel", sb)

## S7：面板底衬（GuidePanel/StatusPanel 共通，圆角 8）+ 三钮样式（底色=面板底色 α+0.12、
## content_margin 2、字号 12）+ 字色显式化（深 #F2E6C8；批次 AB-3：恒深档）
func _apply_panel_bg() -> void:
	var base := PANEL_BG_DARK
	var sb := StyleBoxFlat.new()
	sb.bg_color = base
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 6.0
	sb.content_margin_right = 6.0
	sb.content_margin_top = 0.0    # §4.3 行高口径：198=头部 24+12 行拉伸，垂直边距必须为 0
	sb.content_margin_bottom = 0.0
	guide_panel.add_theme_stylebox_override("panel", sb)
	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = base
	sb2.set_corner_radius_all(8)
	sb2.content_margin_left = 4.0
	sb2.content_margin_top = 0.0
	sb2.content_margin_right = 8.0
	sb2.content_margin_bottom = 0.0
	status_panel.add_theme_stylebox_override("panel", sb2)
	var btn_bg := Color(base.r, base.g, base.b, base.a + 0.12)
	for b: Button in [fold_btn, hint_fold_btn]:
		var sbb := StyleBoxFlat.new()
		sbb.bg_color = btn_bg
		sbb.set_corner_radius_all(6)
		sbb.set_content_margin_all(2.0)
		b.add_theme_stylebox_override("normal", sbb)
		b.add_theme_stylebox_override("hover", sbb)
		b.add_theme_stylebox_override("pressed", sbb)
		b.add_theme_font_size_override("font_size", 14)   # 批次 T T2：折叠钮字号 12→14（28×28 内可容）
	# 批次 U（U5②）：收起钮 20×20 款式锁定——默认字号 16 会把 Button min 高撑到 24（超旧折叠态
	# 面板 24 高），单独降 12（行高 17+margin 1.5×2=20 恰满 custom_minimum_size，20×20 款式；
	# 批次 V §7.2 竖条化后折叠态不再 24 高，20×20 款式沿用=竖条顶钮口径）
	hint_fold_btn.add_theme_font_size_override("font_size", 12)
	var sbb_hf := StyleBoxFlat.new()
	sbb_hf.bg_color = btn_bg
	sbb_hf.set_corner_radius_all(6)
	sbb_hf.set_content_margin_all(1.5)
	for state: String in ["normal", "hover", "pressed"]:
		hint_fold_btn.add_theme_stylebox_override(state, sbb_hf)
	var txt := _ui_text()
	guide_title.add_theme_color_override("font_color", txt)
	status_line.add_theme_color_override("font_color", txt)
	if fold_title != null:   # 批次 V（V13）：竖排标题字色随主题（_ready 先建后调故理论非空，判空防御）
		fold_title.add_theme_color_override("font_color", txt)
	for row: Node in guide_list.get_children():
		if row is Label:
			(row as Label).add_theme_color_override("font_color", txt)

## 按场景键重建行集合（T1：SCENE_HINTS 动态裁剪；置灰机制废止后全行恒亮）。
## 行清理须 remove_child 后再 queue_free（queue_free 延迟到帧末，get_children() 同帧仍含旧行，
## 会让 apply_dock_state 连续切换时行数翻倍——plan 代码块自查修正，批次 T TE-2）。
func _build_list(scene_key: String) -> void:
	for child: Node in guide_list.get_children():
		guide_list.remove_child(child)
		child.queue_free()
	var rows: Array = SCENE_HINTS.get(scene_key, SCENE_HINTS_FALLBACK)
	var font: int = HINT_FONT_MAIN
	var row_h: float = HINT_ROW_H_MAIN
	# 批次 U（偏离②）：GuideList VBoxContainer→GridContainer——LEVEL 双列（每列 6 行，
	# 行优先填充阅读顺序连续）；其余状态 columns=1 行为与旧 VBox 逐行等价
	guide_list.columns = 2 if scene_key == "LEVEL" else 1
	if scene_key == "LEVEL":
		font = HINT_FONT_LEVEL
		row_h = HINT_ROW_H_LEVEL
	elif scene_key == "CATALOG" or scene_key == "CATALOG_FS":
		# 批次 AA（W8-1）：CATALOG_FS 与嵌入态同字号/行高（行组同源，仅停靠位不同）
		font = HINT_FONT_CATALOG
		row_h = HINT_ROW_H_CATALOG
	elif scene_key == "SHOP":
		# 批次 AA（W8-2，spec §11.4-2 行高/字号定档）：SHOP 顶排专属 14/17 档
		font = HINT_FONT_SHOP
		row_h = HINT_ROW_H_SHOP
	elif scene_key == "SETTLE":
		font = SETTLE_FONT
		row_h = 28.0
	for text: String in rows:
		var l: Label = Label.new()
		l.text = I18n.t(text)   # I18n：行文案消费点（zh 直通/en 命中词条表）
		# 批次 U（U5④）：LEVEL 双列列宽 170（规格 176 未计 PanelContainer content_margin 6×2，
		# 170×2+列距 16=356=368−12 恰满不撑爆——§4-U5 表 368×110 逐格断言优先，规格数字差留痕）
		l.custom_minimum_size = Vector2(170.0 if scene_key == "LEVEL" else 0.0, row_h)
		l.clip_text = true
		# 批次 V 走查回修 NG-1（w03/w11+probe 实证）：非 LEVEL 行 min 宽 (0,row_h)+clip_text=true
		# → Label 最小宽 0~1px → GridContainer 单列列宽塌至 1px 文字不可视（V9 全局行被掩蔽）。
		# EXPAND_FILL 撑满说明栏净宽（面板宽由 _dock_cfg hint size 锚定给出，352/224/300 等）；
		# LEVEL 双列 170 min 已恰满（170×2+16=356=368−12），expand 零多余空间几何零变化；
		# 折叠竖条无副作用（折叠态 guide_list.visible=false 隐藏件不参与最小尺寸，竖条 30 宽不变）。
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_size_override("font_size", font)
		l.add_theme_font_override("font", _row_font_for(scene_key))   # 批次 X（P1-b）：行字体行框压缩+测试/生产同语境；批次 AA W8-2：SHOP 专属压缩档
		l.add_theme_color_override("font_color", _ui_text())
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		guide_list.add_child(l)

## I18n：语言切换实时重刷落点（language_changed 订阅；_exit_tree 显式退订）。
## 行组直连 _build_list(_current_key())——不走 apply_dock（其可见门在 BOOT/总开关关等态
## 提前退出行重建，语言切换须无条件刷行；停靠布局本就不随语言变化）。
func _on_language_changed(_lang: String) -> void:
	fold_title.text = I18n.t("手势说明")
	_refresh_camera_placeholder()
	_build_list(_current_key())

func _process(delta: float) -> void:
	# 0.5s 低频轮询「覆盖层开合/游戏状态变化」（沿用批次 R；Game.open/close_overlay 无信号）。
	# 批次 W（P2-9，规格 §5）：轮询比对加入 Game 当前状态——mark_settle_entered() 只改 _state
	# 不发 state_changed，旧轮询恒漏 SETTLE 迁移致 HUD 顶着 LEVEL 布局；状态差即 apply_dock 重排。
	_dock_poll += delta
	if _dock_poll >= 0.5:
		_dock_poll = 0.0
		var game: Node = get_node_or_null("/root/Game")
		var st := _dock_st
		var so := false
		var sho := false
		if game != null:
			st = int(game.call("current_state"))
			so = bool(game.call("is_settings_open"))
			sho = bool(game.call("is_shop_open"))
		if st != _dock_st or so != _dock_settings_open or sho != _dock_shop_open:
			apply_dock()
	# 批次 AA（W8-1，spec §11.4-1）：全屏谓词 0.25s 节流兜底轮询——仅**变化沿** apply_dock
	#（无变化零重排；与上段 0.5s 覆盖层/状态轮询同构）。同步通知优先（video_fullscreen_changed
	# 经 _sync_fs_watch 懒接线），本段只兜「信号未接/场景未挂」的边角。无头测试经
	# hud.set("_fs_poll", -100000.0) 冻结（同 _dock_poll 先例）。
	_fs_poll += delta
	if _fs_poll >= FS_POLL_INTERVAL:
		_fs_poll = 0.0
		var fs_on := _is_video_fullscreen()
		if fs_on != _fs_on:
			_fs_on = fs_on
			apply_dock()
	_sync_fs_watch()

## 停靠表七分支（批次 T spec §4-14 终态；纯函数无头直测；J2：说明栏高度按字体实高推导，
## 探针实测 font14→22px 回填：MAIN 94/MOVIE·TALK 44/SHOP·SETTINGS·UNKNOWN 66）。
## 显隐统一门：BOOT / 总开关关 → 隐藏（SHOP 整组隐藏废止，改左上三件套 T15）。
func apply_dock_state(st: int, settings_open: bool, shop_open: bool) -> void:
	_dock_st = st
	_dock_settings_open = settings_open
	_dock_shop_open = shop_open
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	# 批次 V（V7，spec §4.1）：可见门单一真值——整组可见 ⇔ gesture_hud_visible ∧ gesture_input
	#（旧 OR 半支「or camera_enabled」废除留痕：手势关+摄像头开=整组隐；摄像头设备保持后台运行
	# Q2 语义不变，Router 停+光标清由 main.gd 既有清理链承担）；.get 全带默认值（防坑 2 bool(null)）。
	# 批次 Y（Y-A20）注：三真值门第三支（camera_stream_open）消费点=main.gd _refresh_hud
	#（spec §5 carve-out 5 定档）——本门保持两真值且置于 apply_dock 前段（早退承担子件配置裁剪，
	# 第三支若入本门会连带跳过子件配置、破坏停靠几何），由 main 门在 apply_dock 后置 AND 收口。
	visible = st != Game.State.BOOT \
		and bool(SaveManager.get_settings().get("gesture_hud_visible", true)) \
		and bool(SaveManager.get_settings().get("gesture_input", true))
	if not visible:
		return
	camera_window.visible = false
	status_row.visible = false
	status_panel.visible = false
	guide_panel.visible = false
	guide_header.visible = false
	hint_fold_btn.visible = false
	fold_btn.visible = false
	var key := ""
	if settings_open:
		key = "SETTINGS"
	elif shop_open:
		key = "SHOP"
	else:
		match st:
			Game.State.MAIN_MENU: key = "MAIN_MENU"
			Game.State.OPENING_MOVIE: key = "OPENING_MOVIE"
			Game.State.TALK: key = "TALK"
			Game.State.LEVEL: key = "LEVEL"
			Game.State.CATALOG: key = "CATALOG"
			Game.State.SETTLE: key = "SETTLE"
			_:
				# P1-5 修正（spec §4-1 风险行「未知状态兜底显示 MOVE/CLICK/EXIT 三行」）：未知
				# Game.State 不再全隐——改走 UNKNOWN 兜底三件套（_dock_cfg），_build_list("UNKNOWN")
				# 经 SCENE_HINTS.get 落 SCENE_HINTS_FALLBACK 三行，兜底真实可达；BOOT 仍由上方
				# visible 门拦截（全隐契约不变）。
				key = "UNKNOWN"
	# 批次 AA（W8-1，spec §11.4-1）：CATALOG 全屏视频子态分流——图鉴回看不切 MOVIE 态，
	# 嵌入态沿用底部现位（零改动）；点 ⛶ 后播放器 reparent 进 VideoFullscreenLayer（layer 62，
	# HUD 64 压其上系 Z6-P2-1 有意设计）时改落左上三件套（ControlBar/▶ 播放键零遮挡）。
	# 谓词经 Game.get_current_scene() 查询（同 gesture_router.gd:402-409 口径），非图鉴场景恒 false。
	if key == "CATALOG" and _is_video_fullscreen():
		key = "CATALOG_FS"
	# 批次 U（U5②）：整组折叠早退废止——fold_restore 删除，折叠语义收窄为「只收说明栏本体」
	#（摄像头窗/状态条永不动；主菜单沿用存档键 gesture_panel_folded，语义收窄 §12 列明）
	var cfg := _dock_cfg(key)
	var win := size   # HUD 根满锚于 GestureHUDLayer（offset 零）→ 根尺寸即窗口 content 尺寸（U5① 窗相对口径）
	# U5⑨：摄像头窗等比缩放——factor=clamp(min(avail/base), min/base, 1.0)；仅缩摄像头窗
	var cam_desc: Dictionary = cfg["cam"]
	var base: Vector2 = cam_desc["size"]
	var min_size: Vector2 = MIN_SIZES.get(key, base)
	var f := camera_scale_factor(_avail_for(key, win), base, min_size)
	if f < 1.0:
		cam_desc = cam_desc.duplicate()
		cam_desc["size"] = Vector2(roundf(base.x * f), roundf(base.y * f))
		# 缩到最小仍不足 → 说明栏自动进收起态兜底（U5⑨）
		var av := _avail_for(key, win)
		if av.y < min_size.y or av.x < min_size.x:
			if key != "MAIN_MENU":
				_hint_folded[key] = true
	# 批次 W（N3，规格 §4）：摄像头窗占位常驻——HUD 停靠组可见时恒 visible。旧 V7 子件门
	# 「整组 ∧ gesture_camera_enabled」废止留痕：门控链存在 falsy 路径（精确源依 save.json
	# 形态而定——save_manager 默认值 true 与「真·空档首启应显窗」并存，W3 探针在无头首启
	# 模拟复现窗隐，勿按单一根因回溯排查）；恒显后该门控依赖整体移除，任何设置态都不能隐藏
	# 占位区，窗内文案按桥连接态自述（_refresh_camera_placeholder）。
	camera_window.visible = true
	_refresh_camera_placeholder()
	_apply_item(camera_window, cam_desc)
	status_row.visible = bool(cfg["status_row"])
	status_panel.visible = not bool(cfg["status_row"])
	if status_row.visible:
		_apply_item(status_row, cfg["status"])
	else:
		_apply_item(status_panel, cfg["status"])
	var folded: bool = _folded if key == "MAIN_MENU" else bool(_hint_folded.get(key, false))
	guide_panel.visible = true   # 说明栏本体可收、收起钮常显 → 面板容器不整隐（U5②）
	_apply_item(guide_panel, cfg["hint"])
	# 批次 V（V13，spec §7.2）：折叠竖条化——header/FoldBtn 仅「展开态主菜单」显示（旧 P0-1
	#「header 恒显承载 FoldBtn」方案随竖条退役留痕：竖条内 header 无处落位；展开钮统一为竖条
	# 顶部 hint_fold_btn，所有场景可再展开，死路不回退）。主菜单 FoldBtn 展开态入口保留
	#（写档折叠），折叠态 hint_fold_btn 回调归一 _on_fold_pressed 存档语义（见 _on_hint_fold_pressed）。
	guide_header.visible = key == "MAIN_MENU" and not folded
	fold_btn.visible = key == "MAIN_MENU" and not folded   # 主菜单沿用 FoldBtn（28×28），语义=只收说明栏
	hint_fold_btn.visible = folded or key != "MAIN_MENU"   # 折叠态全场景统一竖条顶钮＋非主菜单顶缘钮（U5②）
	# 批次 U（U5④）：LEVEL 顶部 20px 收起钮行空隙——偏离① overlay 钮不占布局行，经 GuideVBox
	# stylebox content_margin_top 实现（规格「收起钮行 20＋6 行×15=110」语义保持）
	_vbox_pad.content_margin_top = 20.0 if key == "LEVEL" else 0.0
	hint_fold_btn.text = "▲" if folded else "▼"
	# 批次 W（P3-5b，规格 §7）：行集合重建与停靠布局解耦——_build_list 无条件先建（与 key 同源），
	# 折叠/展开两分支只负责可见性与尺寸；旧「折叠分支不重建」分支相反序根除（折叠切态首帧行
	# 集合滞后于 key）。折叠态 guide_list 为隐藏件不参与最小尺寸钳制（V13 口径），先建无副作用；
	# 展开态「先建表后设尺寸」顺序保持（TE-4 实证最小尺寸钳制口径不变）。
	_build_list(key)
	guide_list.visible = not folded
	if folded:
		if HORIZONTAL_FOLD_KEYS.has(key):
			# 批次 X（P1-a，spec §2）：四态横条 120×30——锚定五元组不动，ax=R 者贴右缘（经描述符
			# 携新尺寸重走 _apply_item，非 size 单赋值左上贴靠）；guide_list/header 已隐 →
			# 最小尺寸钳制不干扰。横条高 30 ≤ 四态净空（_avail_for 实测复核，test_x_fold_bar 段4）。
			var h_hint: Dictionary = (cfg["hint"] as Dictionary).duplicate()
			h_hint["size"] = Vector2(H_FOLD_W, H_FOLD_H)
			_apply_item(guide_panel, h_hint)
		else:
			# 批次 V（V13，spec §7.2）：折叠态=竖条——宽 30（∈[28,32] 档）、高随场景 cfg hint 高，
			# 锚定五元组不动；旧横条 (原宽,24) 废除留痕。五态（MAIN_MENU/CATALOG/SHOP/SETTLE/
			# UNKNOWN）维持零变化（批次 X P1-a）。guide_list/header 已隐 → 最小尺寸钳制不干扰。
			guide_panel.size = Vector2(FOLD_BAR_W, (cfg["hint"]["size"] as Vector2).y)
	else:
		guide_panel.size = cfg["hint"]["size"]
	# HintFoldBtn overlay 定位（HUD 本地系==窗相对：根满锚 GestureHUDMount 且层 offset 零；
	# 同帧 position/size 即时值，无跨帧坑）——展开态=面板右上内缘 6px（既有）；折叠态分两态：
	# 竖条=顶部居中（V13 ▲/▼ 贴顶既有公式）；横条（批次 X P1-a）=「▲ 手势说明」同组横排、
	# ▲ 居左、整组条内居中、钮垂直居中（消除竖条态 ▲ 居顶与横排阅读顺序的张力，同组排列天然
	# 不重叠）。FoldTitle：竖条态全条矩形旋转 90°（pivot 中心）+ 文本居中 → 视觉竖排；横条态
	# 不旋转横排（宽取 Label 最小宽实测值，中心让位顶部钮行公式仅竖条态）；展开态隐藏。
	if folded:
		if HORIZONTAL_FOLD_KEYS.has(key):
			fold_title.visible = true
			fold_title.rotation = 0.0
			fold_title.pivot_offset = Vector2.ZERO
			fold_title.size = Vector2(maxf(fold_title.get_minimum_size().x, 1.0), H_FOLD_H)
			var group_w := 20.0 + H_FOLD_GROUP_GAP + fold_title.size.x
			var group_x := guide_panel.position.x + (guide_panel.size.x - group_w) * 0.5
			hint_fold_btn.position = Vector2(group_x, guide_panel.position.y + (H_FOLD_H - 20.0) * 0.5)
			fold_title.position = Vector2(group_x + 20.0 + H_FOLD_GROUP_GAP, guide_panel.position.y)
		else:
			hint_fold_btn.position = guide_panel.position + Vector2((FOLD_BAR_W - 20.0) * 0.5, 2.0)
			fold_title.visible = true
			fold_title.size = Vector2(guide_panel.size.y, guide_panel.size.x)
			fold_title.position = guide_panel.position \
				+ Vector2(guide_panel.size.x * 0.5, (22.0 + guide_panel.size.y) * 0.5) - fold_title.size * 0.5
			fold_title.pivot_offset = fold_title.size * 0.5
			fold_title.rotation = PI / 2.0
	else:
		fold_title.visible = false
		# 批次 AA（W8-2/W8-4，spec §11.4-2「收起钮重推」）：SHOP 展开态原公式
		# guide_panel.position+(w−26, −22) 是为旧停靠位 (16,88) 让位格网设计（批次 W P1-7c）；
		# 顶排新位 y=16 下该式得 y=−6 **越出视口顶部** → 改锚说明栏**内右上角**，与全场景通式
		# 合并为单式（(616+300−26, 16+2)=(890,18)，20×20 钮整体在 hint 内、×三件/×TopBar/
		# ×格网零相交）。P1-7c 的几何红线（×GridPanel 零相交）由 test_w_ui_polish F1 继续守。
		hint_fold_btn.position = guide_panel.position + Vector2(guide_panel.size.x - 26.0, 2.0)
	# 批次 Y 审查② P1-2：三真值门第三支收口——子件配置完成后 AND 流开启真值（幂等：与
	# main.gd _refresh_hud 既有第三支 AND 双路径一致；状态切换 _on_game_state_changed → 本
	# 函数的旁路在此闭合——流关闭/0 摄像头下切场景不再复活整组且无自愈事件）。早退分支
	#（BOOT/开关关）visible 已 false 不经此行语义不变；本行在子件配置之后，停靠几何配置
	# 不被跳过（若置于门内会早退跳过配置打崩停靠几何——Y2 波实证备案）。
	visible = visible and GestureBridge.is_camera_stream_open()

## 停靠描述符构造（批次 U，spec §6.3）：ax∈L/R、ay∈T/B；mx/my=距对应窗缘横/纵边距（双审 P1-2）；size=content px
func _d(ax: String, ay: String, mx: float, my: float, w: float, h: float) -> Dictionary:
	return {"ax": ax, "ay": ay, "mx": mx, "my": my, "size": Vector2(w, h)}

## 停靠表终态（批次 U 锚定化，spec §4-U5 表逐格/§6.3）：窗相对口径。旧 648 基线绝对坐标表废止
##（MAIN_MENU cam 旧 Rect2(16,462,320,180) 等——+10 系统性错位与 LEVEL 漂移同根除，§4-U5①⑤）。
func _dock_cfg(key: String) -> Dictionary:
	match key:
		"MAIN_MENU":
			return {"cam": _d("L", "B", 16, 14, 320, 180),
				"status": _d("L", "B", 348, 14, 96, 180),
				"status_row": true,
				"hint": _d("L", "B", 456, 14, 352, 116)}   # 批次 V（§7.1）：GLOBAL 4 行 → header 28+4×22=116（旧 3 行 94 留痕）
		"OPENING_MOVIE", "TALK":
			# R2 回修 A：status/hint my 随 COLUMN_TOP 106 整组下移 8px（旧 230/260 留痕）
			# 批次 V（§7.1）：GLOBAL 4 行 → hint 4×22=88（旧 2 行 44 留痕）
			return {"cam": _d("R", "T", EDGE_MARGIN, COLUMN_TOP, 224, 126),
				"status": _d("R", "T", EDGE_MARGIN, 238, 224, 24),
				"status_row": false,
				"hint": _d("R", "T", EDGE_MARGIN, 268, 224, 88)}
		"LEVEL":
			# 批次 V（V15，spec §7.3）：停靠组下移避让 JoinView(620,64)-(1140,266)——cam 顶
			# LEVEL_DOCK_TOP=284（JoinView 底 266+18）；status/hint my 同源式推导（416/446）；
			# 旧 cam my=COLUMN_TOP 106/status 238/hint 268 留痕。hint 368×110 双列不变（U5④）
			return {"cam": _d("R", "T", EDGE_MARGIN, LEVEL_DOCK_TOP, 224, 126),
				"status": _d("R", "T", EDGE_MARGIN, LEVEL_DOCK_TOP + 126.0 + GROUP_GAP, 224, 24),
				"status_row": false,
				"hint": _d("R", "T", EDGE_MARGIN, LEVEL_DOCK_TOP + 126.0 + GROUP_GAP + 24.0 + GROUP_GAP, 368, 110)}
		"CATALOG":
			return {"cam": _d("L", "B", 16, 44, 144, 81),
				"status": _d("L", "B", 16, 14, 144, 24),
				"status_row": false,
				# 批次 W（P3-6b，规格 §7）：重叠校正落 tscn 侧（Body 底边 -120→-134，说明栏顶 H-134
				# 恰贴）——HUD 侧高度 120→106 方案经探针证伪：说明栏内容最小高 6×18=108（font13
				# 实高>行高 17），106 被容器撑回 108 且底缘越界至 H-12（test_gesture_console_dock
				# 实跑 FAIL 实证）；停靠表几何不变（test_gesture_console_dock 矩形断言锚保持）。
				"hint": _d("L", "B", 172, 14, 300, 120)}   # 批次 V（§7.1）：GLOBAL+旋转/缩放=6 行×20=120（旧 5 行 100 留痕）
		"CATALOG_FS":
			# 批次 AA（W8-1，spec §11.4-1 定稿 + §22 裁决 1 强约束）：图鉴**全屏视频子态**独立停靠键。
			# 三件纵向叠置左列（cam→status→hint 自上而下，组内 GROUP_GAP=6）；右缘 16+300=316 ≤ 320
			# 静态不变式 → 与 TopStrip 任何宽度档（info 左缘 416 / confirm 档左缘 321）结构零相交；
			# 底缘 251 ≤ 260 → 与全屏 ControlBar (8,600)-(1144,640) 零相交（图 1 播放键遮挡根除）。
			# 嵌入态（非全屏）仍走上方 CATALOG 分支零变化。
			return {"cam": _d("L", "T", 16, 14, 144, 81),
				"status": _d("L", "T", 16, 101, 144, 24),
				"status_row": false,
				"hint": _d("L", "T", 16, 131, 300, 120)}   # 6 行×19=114 ≤ 120（HINT_FONT_CATALOG 档实测）
		"SETTLE":
			# 批次 V（§7.1）：GLOBAL 4 行+点云行=5 行×28=140 → B 锚自底向上重排
			#（hint my 14 不变；status my 160=14+140+6；cam my 190=160+24+6；旧 48/78 留痕）
			# 批次 AA（W3-5，spec §6.4-C）：hint 宽 224→**240**——定稿点云行「…掌缩放【左/右】」
			# 实测 219px > 224−12=212 净宽（规格「≈206 ≤224」估计值未计 PanelContainer
			# content_margin 6×2，同批次 U LEVEL 176→170 同族勘误），按 §6.4-B「面板加宽」逃生舱
			# 抬到 240（净宽 228，实测 219 有 9px 余量）；cam/status 仍 224、几何零交叉（垂直分层）。
			# 同源改点：test_t_hint_rows 段 7 宽度锚 212→228（净宽口径同步）。
			return {"cam": _d("L", "B", 24, 190, 224, 126),
				"status": _d("L", "B", 24, 160, 224, 24),
				"status_row": false,
				"hint": _d("L", "B", 24, 14, 240, 140)}
		"SHOP":
			# 批次 AA（W8-2，spec §11.4-2 顶部横排改版；用户「平排给它排过去」）：三件横排顶带，
			# 让位商店首行卡立绘（旧 cam (16,88) 压第 1 列立绘上部 ≈95px、hint 盖第 2 列，自 V14 一直存在）。
			# 带界 y∈[16,90]（Content 格网顶 92 固定）、x∈[288,1016]（WindowButtons 1024 起，留 8 净隙）；
			# cam 缩至 128×72（=MIN_SIZES["SHOP"]），hint 高 74（4 行×18=72 ≤ 74，底 90 < 92）。
			# **左界 344 而非规格 288 的实证偏离（实施期实测，回报主会话）**：规格「TopBar 右缘 ≈270~280」
			# 系未挂主题语境（Label font 16）实测；生产主题 themes/theme_dark.tres `Label/font_sizes/
			# font_size=20` → BalanceLabel「天赋值：500」实宽 114 → ExitButton x154~294（实测占用右缘
			# 294 > 288，cam 若落 288 会盖退出钮 6px）。取 344 = 占用右缘 294 + 50 净隙（天赋值 6 位数内
			# 恒不相交），仍满足静态不变式 left ≥ 288 与带界 x∈[288,1016]（行右缘 916 ≤ 1016）。
			# 批次 AA（W8-P3-6 口径更正留痕）：**344 = 生产硬编码**（上列主题实测推导的定值），
			# 「运行期自适应判据 occ.end.x + 8 ≤ cam.left」只存在于测试 tests/test_aa_dock_placement.gd
			# （段 3/4 按运行期 TopBar 实测校验）——**生产不自动跟随**：若主题字号 / 天赋值位数 /
			# 退出钮布局变更，需人工按上式重算并改本值（测试判据会先行判红兜底）。
			return {"cam": _d("L", "T", 344, 16, 128, 72),
				"status": _d("L", "T", 480, 16, 128, 24),
				"status_row": false,
				"hint": _d("L", "T", 616, 16, 300, 74)}   # 批次 V（§7.1）：GLOBAL 4 行（旧 2 短行 44 留痕）；W8-2 专属 14/17 档 4×18=72 ≤ 74
		"UNKNOWN":
			return {"cam": _d("R", "T", EDGE_MARGIN, COLUMN_TOP, 224, 126),
				"status": _d("R", "T", EDGE_MARGIN, 238, 224, 24),
				"status_row": false,
				"hint": _d("R", "T", EDGE_MARGIN, 268, 224, 88)}   # 批次 V（§7.1）：FALLBACK=GLOBAL 4 行 → 88（旧 3 行 66 留痕）
		_:   # SETTINGS
			# R2 回修 A：status/hint my 随 COLUMN_TOP 106 整组下移 8px（旧 203/233 留痕）
			# 批次 V-E4：hint my 241→256——摄像头下拉 LOADING 态加自绘转圈行（24×24，批次 V-B2）
			# 后弹窗内容增高 24→48，底缘 252 与旧顶缘 241 真重叠 11px（test_u_dock_anchors 段 7b
			# 「下拉开×SETTINGS 说明栏不相交」即红实证）；说明栏让位下移 +15（重叠 11px+4px 净隙，
			# R2 回修 A 同式），下拉开×说明栏矩形级不相交判据恢复 deterministically 成立。
			return {"cam": _d("R", "T", EDGE_MARGIN, COLUMN_TOP, 176, 99),
				"status": _d("R", "T", EDGE_MARGIN, 211, 176, 24),
				"status_row": false,
				"hint": _d("R", "T", EDGE_MARGIN, 256, 224, 88)}   # 批次 V（§7.1）：GLOBAL 4 行 → 88（旧 3 行×22=66 留痕，双审 P2-15）；V-E4：my 旧 241 留痕

## 锚定落位（U5①，防坑 3：禁止 set_anchors_preset——预设会重写 offsets）：直接赋四值组，窗口尺寸无关
func _apply_item(item: Control, d: Dictionary) -> void:
	var sz: Vector2 = d["size"]
	if d["ax"] == "L":
		item.anchor_left = 0.0
		item.anchor_right = 0.0
		item.offset_left = float(d["mx"])
		item.offset_right = float(d["mx"]) + sz.x
	else:
		item.anchor_left = 1.0
		item.anchor_right = 1.0
		item.offset_left = -(float(d["mx"]) + sz.x)
		item.offset_right = -float(d["mx"])
	if d["ay"] == "T":
		item.anchor_top = 0.0
		item.anchor_bottom = 0.0
		item.offset_top = float(d["my"])
		item.offset_bottom = float(d["my"]) + sz.y
	else:
		item.anchor_top = 1.0
		item.anchor_bottom = 1.0
		item.offset_top = -(float(d["my"]) + sz.y)
		item.offset_bottom = -float(d["my"])

## 等比缩放因子（U5⑨ 纯函数，spec §4-U5-⑨ 式）：16:9 恒等 ±1px，无偶数取整（双审 P2-3）
static func camera_scale_factor(avail: Vector2, base: Vector2, min_size: Vector2) -> float:
	if base.x <= 0.0 or base.y <= 0.0:
		return 1.0
	return clampf(minf(avail.x / base.x, avail.y / base.y), min_size.x / base.x, 1.0)

## 每状态摄像头窗可用净空（U5⑨「窗尺寸−边距−其余件占位」逐状态式；横=其余列占位+边距，纵=锚定边到对侧净空）
func _avail_for(key: String, win: Vector2) -> Vector2:
	match key:
		"MAIN_MENU":
			# 底行三列：cam 右侧=状态条 96+GAP_H+说明栏 352+GAP_H+右缘 EDGE_MARGIN
			return Vector2(win.x - 16.0 - 96.0 - GROUP_GAP_H - 352.0 - GROUP_GAP_H - EDGE_MARGIN, win.y - 14.0)
		"CATALOG":
			# cam 下方=状态条 24+GAP+14；右侧=说明栏列 300+GAP_H+右缘
			return Vector2(win.x - 16.0 - 300.0 - GROUP_GAP_H - EDGE_MARGIN, win.y - 44.0 - 24.0 - GROUP_GAP - 14.0)
		"CATALOG_FS":
			# 批次 AA（W8-1，§11.4-1）：三件纵向叠置左列——横=左边距 16 起的整幅净宽（右侧全屏黑底
			# 无列占位），纵=顶边距 14 起扣 status 24+GAP、hint 120+GAP 与底边距 14（同源式，随 cfg 走）；
			# 1152×648 下 (1122,464) ≥ MIN_SIZES (112,63) → 缩放因子钳 1.0，144×81 原尺寸落位。
			return Vector2(win.x - 16.0 - EDGE_MARGIN,
				win.y - 14.0 - 24.0 - GROUP_GAP - 120.0 - GROUP_GAP - 14.0)
		"SETTLE":
			# 批次 V（§7.1）：GLOBAL 5 行重排后 cam my=190（14+140+6+24+6，_dock_cfg SETTLE 同源）
			return Vector2(win.x - 24.0 - EDGE_MARGIN, win.y - 190.0 - 14.0)
		"SHOP":
			# 批次 AA（W8-2，§11.4-2 顶排同源式）：横=带内左缘 344 起扣 status 128+GAP 8+hint 300+GAP 8
			# 与右缘边距；纵=格网顶 92 − 带顶 16 = 76（Content offset_top=92 与窗高无关，带高恒定）
			# → 76 ≥ MIN_SIZES SHOP 72：不触发 U5⑨「缩到最小自动收起说明栏」兜底；窗口收窄时
			# av.x = win.x−802 先于 av.y 触底，横排带宽不足即自动收起（逐状态净空式，与 cfg 同源）。
			return Vector2(win.x - 344.0 - 128.0 - 8.0 - 300.0 - 8.0 - EDGE_MARGIN, 92.0 - 16.0)
		"LEVEL":
			# 批次 V（V15，spec §7.3）：LEVEL 从右上竖排组公式脱离，改 LEVEL_DOCK_TOP 同源式
			return Vector2(win.x - EDGE_MARGIN * 2.0, win.y - LEVEL_DOCK_TOP - 14.0)
		_:
			# 右上竖排（MOVIE/TALK/SETTINGS/UNKNOWN）：横向独占、纵向=COLUMN_TOP 到窗底留 14
			#（R2 回修 A：式引用 COLUMN_TOP 常量随 106 自动生效，无硬编码残留）
			return Vector2(win.x - EDGE_MARGIN * 2.0, win.y - COLUMN_TOP - 14.0)

func apply_dock() -> void:
	var game: Node = get_node_or_null("/root/Game")
	var st: int = 0
	var so := false
	var sho := false
	if game != null:
		st = int(game.call("current_state"))
		so = bool(game.call("is_settings_open"))
		sho = bool(game.call("is_shop_open"))
	apply_dock_state(st, so, sho)

## 批次 AA（W8-1，spec §11.4-1「全屏态识别机制」）：CATALOG 全屏视频子态谓词——经
## Game.get_current_scene() 查询（同 gesture_router.gd:402-409 口径）；仅图鉴场景实现
## is_video_fullscreen()（catalog_scene.gd），非图鉴场景/未挂场景/裸实例恒 false（判空防御，
## 防坑 7/10：不做 bool(null)/String(null) 强转）。
func _is_video_fullscreen() -> bool:
	var sc: Node = _current_scene_node()
	if sc == null or not sc.has_method("is_video_fullscreen"):
		return false
	return bool(sc.call("is_video_fullscreen"))

## 当前场景实例（Game.get_current_scene 的判空/判型封装——Variant→Node 安全下沉到单点）
func _current_scene_node() -> Node:
	var game: Node = get_node_or_null("/root/Game")
	if game == null:
		return null
	var sc_v: Variant = game.call("get_current_scene")
	if sc_v is Node:
		return sc_v as Node
	return null

## 批次 AA（W8-1，spec §11.7 风险 3）：video_fullscreen_changed 同步通知懒接线——每帧比对当前
## 场景，换场景即断旧接新（信号挂在图鉴场景上，随场景释放自动断，此处补显式退订防悬垂）；
## HUD 释放时 _exit_tree 调 _disconnect_fs_watch（J6 信号卫生）。同步优先、0.25s 轮询兜底。
func _sync_fs_watch() -> void:
	if _fs_watch != null and not is_instance_valid(_fs_watch):
		_fs_watch = null   # 场景已释放：句柄作废（信号随实例销毁，无需再断）
	var sc: Node = _current_scene_node()
	if sc == _fs_watch:
		return
	_disconnect_fs_watch()
	if sc != null and sc.has_signal("video_fullscreen_changed"):
		sc.connect("video_fullscreen_changed", _on_video_fullscreen_changed)
		_fs_watch = sc

func _disconnect_fs_watch() -> void:
	if _fs_watch != null and is_instance_valid(_fs_watch) \
			and _fs_watch.has_signal("video_fullscreen_changed") \
			and _fs_watch.is_connected("video_fullscreen_changed", _on_video_fullscreen_changed):
		_fs_watch.disconnect("video_fullscreen_changed", _on_video_fullscreen_changed)
	_fs_watch = null

## 全屏进出同步重排（_set_fullscreen 内 emit → 当帧 apply_dock，消除 0.25s 兜底窗内的短暂叠压）
func _on_video_fullscreen_changed(_on: bool) -> void:
	apply_dock()

func _on_fold_pressed() -> void:
	_folded = not _folded
	SaveManager.update_settings({"gesture_panel_folded": _folded})  # 整组折叠写档（§3-3）
	apply_dock()

## 批次 U（U5②）：说明栏顶缘收起钮回调（每状态会话级；主菜单走 _on_fold_pressed 存档键）。
## 批次 V（V13，spec §7.2）：主菜单折叠态竖条 ▲/▼ 钮归一 FoldBtn 存档语义——主菜单折叠态由
## _folded（gesture_panel_folded 写档）驱动，会话级 _hint_folded 对其无效；不归一则竖条上点击
## 无效（折叠死路回潮），故主菜单一律路由 _on_fold_pressed（折叠/展开均写档，记忆机制不变）。
func _on_hint_fold_pressed() -> void:
	var key := _current_key()
	if key == "MAIN_MENU":
		_on_fold_pressed()
		return
	_hint_folded[key] = not bool(_hint_folded.get(key, false))
	apply_dock()

## 当前停靠键（收起钮回调取键用；与 apply_dock_state 的 key 分流同源）
func _current_key() -> String:
	var game: Node = get_node_or_null("/root/Game")
	var st: int = 0
	var so := false
	var sho := false
	if game != null:
		st = int(game.call("current_state"))
		so = bool(game.call("is_settings_open"))
		sho = bool(game.call("is_shop_open"))
	if so:
		return "SETTINGS"
	if sho:
		return "SHOP"
	var key := "UNKNOWN"
	match st:
		Game.State.MAIN_MENU: key = "MAIN_MENU"
		Game.State.OPENING_MOVIE: key = "OPENING_MOVIE"
		Game.State.TALK: key = "TALK"
		Game.State.LEVEL: key = "LEVEL"
		Game.State.CATALOG: key = "CATALOG"
		Game.State.SETTLE: key = "SETTLE"
		_: key = "UNKNOWN"
	# 批次 AA（W8-1）：与 apply_dock_state 的 CATALOG 分流同源（收起钮回调取键不得落后于停靠表）
	if key == "CATALOG" and _is_video_fullscreen():
		key = "CATALOG_FS"
	return key

func _refresh_visibility() -> void:
	## 显隐总开关（§7.3）：批次 S 起统一门收敛进 apply_dock_state，此处仅重算（重开恢复）
	apply_dock()

func _on_state(data: Dictionary) -> void:
	## 识别状态条（S6）：主菜单双块三行 / 紧凑单行 / 竖条三口径同源刷新
	var left_v: Variant = data.get("left", {})
	var right_v: Variant = data.get("right", {})
	var ltxt := _refresh_hand(left_panel, left_v if typeof(left_v) == TYPE_DICTIONARY else {}, "left")
	var rtxt := _refresh_hand(right_panel, right_v if typeof(right_v) == TYPE_DICTIONARY else {}, "right")
	status_line.text = ltxt + " ｜ " + rtxt
	# 批次 U（U6）：骨架数据噪（归一点集；该侧 null=手离场自动清空；.get 防御——防坑 5）
	if skeleton != null:
		skeleton.set_hands(data.get("left", null), data.get("right", null))

## 批次 AA（W2-10，spec §5.3）：状态条显示名与游戏动作同源映射——语义层
## （GestureMap._classify，fingers 通道权威）→ 中文动作名；替代 python
## `_classify_gesture` 的 gesture 名（0.6/0.7 严阈双轨口径，与运行时判定脱钩，spec §5.2 R2-6）。
## 批次 AA（W3-1/W3-2）旧口径留痕："four"（右四指=清空）语义随「右手 palm→立即 clear」退役后，
## 右掌与左掌同走 "palm"（缩放），清空曾由右掌静止 1.0s dwell 承担。
## 批次 AD（§4.3.4，2026-09-28 审查回修）：右掌 dwell 清空通路**彻底废除**（_feed_palm_dwell 退役
## no-op 桩），清空改由**双手握拳**承担（GestureMap._feed_dual_fist_clear → clear side="both"）；
## 状态条在掌态恒显「缩放」的口径不变（palm 语义只剩缩放，与清空解耦更彻底）。
const SEMANTIC_NAMES := {"": "待命", "cursor": "光标", "two": "二指",
	"three": "三指", "palm": "缩放"}

## 该侧语义显示名（_refresh_hand 行 2 消费；Router 未就位/无语义 → "待命"）
func semantic_display_name(side: String) -> String:
	var sem := ""
	if is_inside_tree():
		var rt: Node = get_node_or_null("/root/GestureRouter")
		if rt != null and rt.has_method("side_semantic"):
			sem = String(rt.call("side_semantic", side))
	return I18n.t(String(SEMANTIC_NAMES.get(sem, sem)))

## 刷新单手块三行（行 1 手别字/行 2 语义动作名/行 3 置信度），返回紧凑行侧段文本（S6）
func _refresh_hand(panel: Panel, h: Dictionary, tag: String) -> String:
	# I18n 解耦③：tag=逻辑键 "left"/"right"（节点名 sfx/颜色/语义查询全走逻辑键）；
	# 显示名（左手/右手/左/右）经 I18n.t 分离——en 词条化后判定不再依赖中文文本。
	var sfx := "Left" if tag == "left" else "Right"
	var tag_label: Label = panel.get_node("VBox/%sTag" % sfx)
	var name_label: Label = panel.get_node("VBox/%sLabel" % sfx)
	var conf_label: Label = panel.get_node("VBox/%sConf" % sfx)
	var gesture := String(h.get("gesture", ""))
	# is_detected 缺省=true（兼容无该键的手 dict）；空包 gesture="None" 同判未检出（沿用批次 R）
	var detected := bool(h.get("is_detected", true)) and not gesture.is_empty() and gesture != "None"
	tag_label.text = I18n.t("左手") if tag == "left" else I18n.t("右手")
	tag_label.add_theme_color_override("font_color",
		HAND_LEFT_COLOR if tag == "left" else HAND_RIGHT_COLOR)
	# 批次 T TE-4：竖条 bar 同步段废止（BarColumn 节点删除，紧凑行 status_line 语义不变）
	if detected:
		var conf := float(h.get("confidence", 0.0))
		# 批次 AA（W2-10）：显示名改语义层动作名（与 _classify 同源；gesture 名仅作
		# 检出门保留，不再显示——旧「行 2 显 python gesture 名」双轨口径退役留痕）
		var disp := semantic_display_name(tag)
		name_label.text = disp
		conf_label.text = "%d%%" % int(round(conf * 100.0))
		# 批次 W（P3-1e）：恢复主题继承字色（清灰档覆盖——同 label 在检出/未检出间翻转）
		conf_label.remove_theme_color_override("font_color")
		conf_label.self_modulate = CONF_GREEN if conf > 0.8 else (CONF_YELLOW if conf > 0.5 else CONF_RED)
		var dtag := I18n.t("左") if tag == "left" else I18n.t("右")
		return "%s %s %d%%" % [dtag, disp, int(round(conf * 100.0))]
	name_label.text = I18n.t("未检出")
	conf_label.text = I18n.t("未检出")
	# 批次 W（P3-1e，规格 §7）：灰档改字色直写（NO_HAND_GRAY 值不变）——旧 self_modulate 与
	# 主题字色相乘（深档≈#B0A998、浅档≈#20170B），两主题置灰不一（W0 §P3-1e）；直写后两主题
	# 恒为 #B5B5B5（深档 Δ≤4% 通道级微变、浅档为缺陷本体的修正，对照表留痕）。
	conf_label.self_modulate = Color.WHITE
	conf_label.add_theme_color_override("font_color", NO_HAND_GRAY)
	var dtag2 := I18n.t("左") if tag == "left" else I18n.t("右")
	return "%s %s" % [dtag2, I18n.t("未检出")]

func _on_camera_frame(texture: ImageTexture) -> void:
	camera_window.texture = texture
	camera_hint.visible = false
	camera_bg.visible = false  # 首帧到达：占位让位画面（S13 READY「有纹理才隐占位」）
	_reconnect_placeholder = false   # 批次 AD-5：画面回来 → 解除「连接中」占位态

## 批次 AD-5（F-4，需求 §4.4）：重连期「连接中」占位态标志——流真值开→关（重连/释放/
## 切换在飞）时置真，新帧到达清假。用于把「僵死旧画面/纯空白」换成明确占位文案，
## 用户不再误读为「卡死了十来秒」。
var _reconnect_placeholder := false

## 批次 W（N3）：摄像头窗占位文案——按桥连接态自述（消费批次 W2 §3 支撑项只读态 API
## is_camera_intentionally_released）。优先级：主动关=「摄像头已关闭」> 重连期
##（流真值开→关后未回帧）=「摄像头连接中…」> LOADING/READY 无帧=「摄像头启动中…」>
## UNAVAILABLE 枚举空=「未检出摄像头」> UNAVAILABLE 其余=「摄像头暂未打开」
## （既有文案回归锚）。「启动中」优先于「未检出」：首启枚举未到达的 LOADING 窗不得误报未检出。
## AD-5：「连接中」只在 READY/LOADING 分支内生效——UNAVAILABLE 各支文案（E4/E5 回归锚）
## 与主动关门（E3）零变化。
func _camera_placeholder_text() -> String:
	if GestureBridge.is_camera_intentionally_released():
		return I18n.t("摄像头已关闭")
	match int(GestureBridge.get_load_state()):
		GestureBridge.LoadState.LOADING, GestureBridge.LoadState.READY:
			if _reconnect_placeholder:
				return I18n.t("摄像头连接中…")
			return I18n.t("摄像头启动中…")
		_:
			pass
	var cams: Variant = (GestureBridge.get_camera_enum() as Dictionary).get("cameras", [])
	if typeof(cams) == TYPE_ARRAY and (cams as Array).is_empty():
		return I18n.t("未检出摄像头")
	return I18n.t("摄像头暂未打开")

## 批次 W（N3）：占位区刷新（bg+hint 恒在、文案按状态）。READY 已有帧（画面覆盖占位）时
## 早退不打扰——hint/bg 隐藏态保持，不清纹理不清帧。
func _refresh_camera_placeholder() -> void:
	if int(GestureBridge.get_load_state()) == int(GestureBridge.LoadState.READY) \
			and camera_window.texture != null:
		return
	camera_bg.visible = true
	camera_hint.text = _camera_placeholder_text()
	camera_hint.visible = true

## 批次 AA（W4-10，spec §7.3）：清屏计数（可断言观测成员——R4-i「振荡清屏 ≤1」判定锚）。
var _texture_clear_count := 0

## W4-10 清屏唯一漏斗：置空纹理并计数（所有清屏路径必经本方法，防散落直赋）。
func _clear_camera_texture() -> void:
	camera_window.texture = null
	_texture_clear_count += 1

## 批次 AA（W4-10，spec §7.3/验收 9）：状态边沿条件清屏——仅「无有效纹理」或
## 「流真值已关」时清；流真值仍开（链路抖动 UNAVAILABLE↔LOADING 振荡、切换在飞，
## python 主循环阻塞致 9876 短暂无包）保留纹理，根治「每个状态边沿清一次画面」
## 的黑屏抖动（R4-8：5s 重试探活 × 状态边沿反复清屏）。
func _clear_camera_texture_conditional() -> void:
	if camera_window.texture == null:
		return   # 无有效纹理：无可清
	if not GestureBridge.is_camera_stream_open():
		_clear_camera_texture()   # 流真值已关（设备/流真值变化）→ 清陈旧帧

## 批次 AA（W4-10）：流真值边沿回调——开→关 即清陈旧纹理（关→开 不动，等新帧）。
## 批次 AD-5（F-4，需求 §4.4）：开→关 另置「连接中」占位态并**就地刷新占位区**——
## 重连期摄像头窗显明确占位文案，而非僵死旧画面或纯空白（原实现只清纹理不显占位，
## hint/bg 停留在首帧时的隐藏态 → 窗内空无一物，被误读为「画面+HUD 全部消失」）。
func _on_camera_stream_truth(open: bool, _device_id: int) -> void:
	if not open:
		_reconnect_placeholder = true
		_clear_camera_texture()
		_refresh_camera_placeholder()   # AD-5：清纹理后纹理为 null，占位早退门不拦截

func _on_load_state(state: int) -> void:
	match state:
		GestureBridge.LoadState.LOADING, GestureBridge.LoadState.UNAVAILABLE:
			# S13（§3-13）：无新帧期间只显占位；批次 AA（W4-10）清屏条件收窄（见上）
			_clear_camera_texture_conditional()
			camera_bg.visible = true
			camera_hint.text = _camera_placeholder_text()   # W-N3：统一文案漏斗（按 state 自述）
			camera_hint.visible = true
		GestureBridge.LoadState.READY:
			camera_hint.visible = bool(camera_window.texture == null)
			if camera_window.texture != null and GestureBridge.is_camera_stream_open():
				# 批次 AA（W4-10）：有纹理且流真值开 → 占位底即隐（恢复后画面 1 次即出，
				# 不再让 0.85α 占位底压陈旧帧等到下一帧才让位）
				camera_bg.visible = false
			if camera_hint.visible:
				# W-N3：READY 无帧过渡文案按状态复位（防旧态文案残留；与 W6 P3-6c 同域顺手闭合）
				camera_hint.text = _camera_placeholder_text()
