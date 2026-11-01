extends Control
## 设置面板（覆盖层）。K/K1 重构（spec §5.1/§5.2）→ 批次 R 改造（spec §8.1/§8.2）：
## 删「键鼠交互开关」及「至少保留一种输入方式」同关校验（键鼠物理上永远可用，§14-②）；
## 手势交互=父项开关，摄像头=子项（缩进 32px + L 形连接线）；摄像头子开关四象限状态机；
## 批次 T（T12/T13）：感叹号说明框（GlassDialog）废止 → ArrowBtn 常显下拉（CameraMenuPopup/
## CameraMenu 设备选择）+ 摄像头钮/箭头钮悬浮跟随说明窗 CamTip。存档不再写 kb_input（保留不消费）。
## 批次 V（V-C4，spec §3.3①②/§4.2）：Q1 拦截钩子退役（Q1 单句 toast 常量与 q1 观测成员删除，
## 「关手势→摄像头强制回开」旧拦截行为彻底废除）→ 摄像头钮三态流：态① 手势开=Game.info 成条
## +复位亮态不触桥；态② 手势关+摄像头开=Game.confirm 关闭确认条（确认才进 _apply_camera_quadrant
## Q3 分支，取消/× 零副作用+复位亮态）；态③ 双关=disabled 置灰。CameraMenuPopup 主弹窗棕化
## （V-B2 移交项：坑4 显式注入主题+棕档 panel StyleBox，复用 camera_menu._apply_popup_theme）。

@onready var catalog_entry: Button = $Panel/VBox/EntryBox/CatalogEntry
@onready var shop_entry: Button = $Panel/VBox/EntryBox/ShopEntry
@onready var gesture_toggle: Button = $Panel/VBox/OptionsBox/GestureToggle
@onready var camera_row: HBoxContainer = $Panel/VBox/OptionsBox/CameraRow
@onready var camera_toggle: Button = $Panel/VBox/OptionsBox/CameraRow/CameraToggle
@onready var arrow_btn: Button = $Panel/VBox/OptionsBox/CameraRow/ArrowBtn
@onready var cam_menu_popup: PopupPanel = $CameraMenuLayer/CameraMenuPopup   # 批次 U（U2-2，双审 P1-1）：宿主迁独立层 65（高于 HUD 64 与 GlobalUI 内面板）
@onready var cam_menu: PanelContainer = $CameraMenuLayer/CameraMenuPopup/CameraMenu
@onready var hud_toggle: Button = $Panel/VBox/OptionsBox/HudToggle
@onready var fullscreen_toggle: Button = $Panel/VBox/OptionsBox/FullscreenToggle
# I18n：语言行（FullscreenToggle 之后）——标签固定 "Language"（不翻译）+ OptionButton
#（简体中文/English）。切换即 I18n.set_language + 写档；language_changed → _refresh_texts 实时重刷。
@onready var language_option: OptionButton = $Panel/VBox/OptionsBox/LanguageRow/LanguageOption
@onready var warning_label: Label = $Panel/VBox/WarningLabel
@onready var close_btn: Button = $Panel/VBox/ButtonBox/CloseButton
@onready var _toggles: Array = [gesture_toggle, camera_toggle, hud_toggle, fullscreen_toggle]

const WM := preload("res://scripts/window_manager.gd")  # P2-5：--script 模式 class_name 时序防御（T14）
const CoordSpace := preload("res://scripts/coord_space.gd")  # 窗口缩放坐标修复2：锚定单一漏斗

# 点亮式两态（批次 P 定稿口径原样保留）
# 批次 W（P3-1）：色彩单源表（值不变）。
# 批次 AB-3：*_LIGHT 浅档常量随深浅主题机制删除退役，深档为唯一值。
const Palette := preload("res://scripts/palette.gd")
const TOGGLE_OFF_BG_DARK := Color(0.35, 0.30, 0.22, 0.35)
const TOGGLE_ON_BG_DARK := Color(0.38, 0.27, 0.10, 0.85)
const TOGGLE_ON_HOVER_DARK := Color(0.34, 0.24, 0.09, 0.85)
const TOGGLE_OFF_FONT := Color(0.85, 0.80, 0.70, 0.8)
const TOGGLE_ON_FONT_DARK := Color(0.96, 0.90, 0.78, 1)
const TOGGLE_BORDER_GOLD := Color(Palette.STROKE_GOLD, 0.4)   # P3-1：描边金单源（值不变）
const TOGGLE_CORNER_RADIUS := 12
# 批次 AB2 R1 审查回修3（P3-1）：投影几何单源常量——常态档与零摄像头灰档共用
#（旧漏：灰档只复制圆角/边距漏阴影 → 0 态按钮丢投影，几何与常态档不一致）。
const TOGGLE_SHADOW_COLOR := Color(0, 0, 0, 0.35)
const TOGGLE_SHADOW_SIZE := 8
const TOGGLE_SHADOW_OFFSET := Vector2(3, 5)
const CAM_TIP_MAX_WIDTH := 320.0   # spec §4-T13：说明窗最大宽（NG-1 走查 f 项回修：宽钳+高随内容自动；批次 U 后仅作历史锚点保留，宽钳由 HoverTip MAX_WIDTH 承接）

# 批次 U（spec §5）：重开失败降级/LEVEL 态面板顶缘避让（顶栏底 70＋6 间隙；面板底 76+560=636 ≤648）
# 批次 V（V-C4，spec §4.2）：Q1 单句 toast 常量与 q1 观测成员随拦截钩子一并退役
#（态① 信息改由 Game.info「手势交互需要摄像头，无法关闭」顶部成条承担，文案归 §3.3① 单源）。
const REOPEN_FAIL_TOAST := "摄像头未能重新打开，可稍后重试"   # 批次 Y（㉓）：退役留痕——文案职责由 CAM_SWITCH_FAIL_TOAST 承接
const OVERLAY_TOP_FLOOR := 76.0
const CAM_TIP_TEXT := "摄像头保持开启，以便您随时重新打开手势交互（摄像头启动需要数秒）。也可在此手动关闭。"
# 批次 W（N5，拍板 5，规格 §5）：摄像头按钮真实状态机文案/常量——亮=桥 READY 且摄像头开；
# 点击→OPENING（禁用+「打开中…」点阵动画）；回落提示/全失败报错（Game.info/toast 单源）。
const CAM_BTN_TEXT := "摄像头"
# 批次 AC（2026-09-27 领域八，spec §4.8）：手势交互开关文案单源——按钮文案加 `(Beta)` 角标
#（手势运行时仍属测试阶段，给用户明确预期）。tscn 与 _ready 回写共用本常量，防两处字面量漂移。
const GESTURE_BTN_TEXT := "手势交互 (Beta)"
# 批次 Z（Z5-7，spec §5-7 拍板）：OPENING 加载态文案与点循环单点常量——「摄像头正在加载中」
# + **3→2→1 点递减循环**（0.4s 步进；数组序即推进序：正向 (find+1)%3 索引推进 = 3→2→1→3，
# 非 0→1→2 递增）。消费点（_begin_camera_open / _process 点阵 / 各测试）一律经常量引用、
# 不锁字面量；CAM_OPENING_TEXT 为无点基座（归一文案单源）。
const CAM_OPENING_TEXT := "摄像头正在加载中"
const CAM_OPENING_DOTS := ["摄像头正在加载中...", "摄像头正在加载中..", "摄像头正在加载中."]
const CAM_OPENING_DOTS_SEC := 0.4
# CAM_SWITCHED_INFO「已切换到 %s」随批次 Z（Z4-④）面板 8s/error 回落链退役删除
#（回落切设备不再发生，「已切换到」提示失去事实依据；旧值留痕：var CAM_SWITCHED_INFO := "已切换到 %s"）。
const CAM_OPEN_FAIL_TOAST := "摄像头打开失败，请检查设备后重试"
# 批次 Y（㉓/Y-A23，spec §2）：切换设备失败 toast 文案与事实一致——旧「摄像头未能重新打开，
# 可稍后重试」与「用户切设备失败」事实错位，改「切换失败」口径（REOPEN_FAIL_TOAST 退役留痕）。
const CAM_SWITCH_FAIL_TOAST := "摄像头切换失败，可稍后重试"
# 批次 Y（Y-A18，spec §2）：「打开中」OPENING 态约 8s 超时兜底回落（§4-4 常量集中可调）——
# 假死 READY（链路在而流不开）下 8s 内必有终态（回落重开或报错复位），不再永挂「打开中…」。
const CAM_OPENING_TIMEOUT_SEC := 8.0
# 批次 Y（Y-A20，spec §2）：0 摄像头提示条文案（Game.info 路由，TopStrip 承接）。
const ZERO_CAMERA_INFO := "未检测到摄像头，手势交互无法使用"
# 批次 AB2（2026-09-25，「电脑没有摄像头」分支，主会话拍板口径）：0 摄像头确认态——
# 双钮**视觉置灰但仍可点击**（点击弹「无硬件摄像头支持」提示条，样式=对接失败弹条同源：
# Game.info → Game.toast(centered=true) → TopStrip.push_info 顶部统一弹条同一组件同锚点）；
# 旧 Y-A20「disabled 真禁用」语义退役留痕。灰档几何与 _apply_toggle_style 档完全一致
#（同圆角 12/边距 18/10/投影 8·(3,5)，仅换底色与字色；回修3/P3-1 补投影三属性），深浅双档随主题。
const NO_HARDWARE_CAMERA_INFO := "无硬件摄像头支持"
const ZERO_GRAY_BG_DARK := Color(0.26, 0.24, 0.20, 0.50)
const ZERO_GRAY_FONT := Color(0.60, 0.60, 0.60, 1.0)

# 批次 W（N5）：OPENING 态机成员——_cam_opening 活跃期按钮禁用+文案动画；
# _cam_open_attempt_id=本次 ensure 的目标设备（camera_error 命中即回落）。
# 批次 Y（Y-A18）：_cam_opening_total=OPENING 累计时长（8s 超时判据；与点阵动画步进累加器分离）。
var _cam_opening := false
var _cam_open_attempt_id := -1
var _cam_opening_accum := 0.0
# I18n 解耦②：点循环下标驱动（旧「按按钮文本反查点阵下标」文本判据退役——en 词条化后
# 按钮文本随语言变，文本反查恒回 0 档；计时/下标驱动与语言解耦）。
var _cam_opening_dot_idx := 0
var _cam_opening_total := 0.0
# 批次 Z（Z6-P2-9，spec §6）：本面板推过的 confirm 句柄序号（Game.confirm 返回值记位）——
# _exit_tree 仅在「自己那条仍活动」时 dismiss，根除旧无条件 Game.dismiss_confirm() 把关卡
# 退出等他源挂起确认静默收走的误杀（关设置面板 → 关卡退出确认消失）。
var _my_confirm_seq := -1

func _ready() -> void:
	var s: Dictionary = SaveManager.get_settings()
	# 批次 AC（领域八）：文案单源回写——tscn 与代码双保险，杜绝字面量漂移（无逻辑分支依赖此文本）。
	# I18n：回写经 t()（zh 直通原样；en 命中词条表），language_changed → _refresh_texts 再刷。
	gesture_toggle.text = I18n.t(GESTURE_BTN_TEXT)
	gesture_toggle.button_pressed = bool(s.get("gesture_input", true))
	camera_toggle.button_pressed = bool(s.get("gesture_camera_enabled", true))
	hud_toggle.button_pressed = bool(s.get("gesture_hud_visible", true))
	fullscreen_toggle.button_pressed = WM.is_fullscreen()
	fullscreen_toggle.visible = DisplayServer.get_name() != "headless"
	# I18n：Language 行初始化（按存档 language 选中）+ 切换连接——切换即 I18n.set_language
	# ＋写档（update_settings → settings_changed 幂等无害）；首次缺省 zh 由 OptionButton
	# tscn 静态 selected=0（简体中文）兜底。
	language_option.select(0 if I18n.get_language() == "zh" else 1)
	language_option.item_selected.connect(_on_language_selected)
	if not I18n.language_changed.is_connected(_on_language_changed):
		I18n.language_changed.connect(_on_language_changed)
	var vol: Dictionary = s.get("volume", {})
	$Panel/VBox/VolumeGrid/MasterBox/Slider.value = float(vol.get("master", 1.0))
	$Panel/VBox/VolumeGrid/MusicBox/Slider.value = float(vol.get("music", 1.0))
	$Panel/VBox/VolumeGrid/SfxBox/Slider.value = float(vol.get("sfx", 1.0))
	warning_label.text = ""
	_refresh_catalog_entry()
	shop_entry.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	catalog_entry.set_meta("hover_glow", true)
	shop_entry.set_meta("hover_glow", true)
	catalog_entry.pressed.connect(_on_catalog)
	shop_entry.pressed.connect(func() -> void: Game.open_overlay("shop"))
	close_btn.pressed.connect(_on_close)
	# 批次 R：手势/摄像头开关 → 四象限状态机（同关校验已随 KbToggle 删除，§8.1）
	# 批次 AB2：手势钮点击改具名入口——0 摄像头确认态点击弹「无硬件摄像头支持」提示条
	#（不触四象限），有摄像头态走既有四象限语义零变化。
	gesture_toggle.toggled.connect(_on_gesture_toggle_toggled)
	# 批次 V（V-C4，spec §4.2）：Q1 拦截钩子退役 → 摄像头钮三态流（_on_camera_toggle_toggled）：
	# 态① 手势开=info 条+复位亮态不触桥；态② 手势关+摄像头开=confirm 确认条；态③ 双关=置灰
	#（由 _apply_camera_quadrant 手势关分支承载）。设置变更信号流（SaveManager.settings_changed）不变。
	camera_toggle.toggled.connect(_on_camera_toggle_toggled)
	hud_toggle.toggled.connect(func(_on: bool) -> void: _save_settings())
	# 批次 T（T12）：箭头钮 → 下拉弹窗（批次 U（U3）：CamTip 悬浮绑定删除——迁移 HoverTip，
	# 仅 Q2 且悬浮开关本体显示，arrow 不再绑定）
	arrow_btn.pressed.connect(_on_arrow_pressed)
	fullscreen_toggle.toggled.connect(func(on: bool) -> void:
		WM.set_fullscreen(on)
		var p: Node = get_parent()
		var wb: Node = p.get_node_or_null("WindowButtons") if p != null else null
		if wb != null:
			wb.call("refresh_state"))
	for n: String in ["MasterBox", "MusicBox", "SfxBox"]:
		$Panel/VBox/VolumeGrid.get_node(n + "/Slider").value_changed.connect(_on_volume_changed)
	# 批次 AB-3：theme_changed 订阅随深浅主题机制删除退役（V-C4 棕化由下行挂载直刷）。
	_apply_toggle_style()
	_apply_camera_menu_popup_theme()   # V-C4（V-B2 移交项）：挂载即棕化 CameraMenuPopup
	_apply_camera_quadrant()   # 开面板即按存档四象限校准（Q4 有效态含自动重启）
	_refresh_volume_labels()
	# I18n：挂载即按当前语言刷一遍静态文案（en 档重进设置=英文；zh 档 t() 直通零变化）。
	_refresh_texts()
	# 批次 U（U7-4/U3，spec §4-U7-4）：CamTip 私有件废止 → HoverTip 共享组件（文案逐字沿用全文）；
	# Q2 门控经 enabled 谓词单一落点（双审 P2-12）：仅「手势关＋摄像头开」（Q3=双关，双审 P2-2）；
	# Q1 信息自批次 V-C4 起由三态流态① Game.info 成条承担、Q4 双关不显示。
	var hover_tip: PanelContainer = (load("res://scenes/shared/hover_tip.gd") as GDScript).new()
	add_child(hover_tip)
	hover_tip.setup(camera_toggle, I18n.t(CAM_TIP_TEXT),
		func() -> bool:
			var st: Dictionary = SaveManager.get_settings()   # 磁盘实况适配：外层 _ready 已有 s——lambda 体同名重声明报 Parse Error，改名 st
			return (not bool(st.get("gesture_input", true))) and bool(st.get("gesture_camera_enabled", false)))
	# 批次 U（U4-⑥）：RELEASE 后重开失败（camera_error 回传）→ toast 降级不崩
	if not GestureBridge.camera_error_received.is_connected(_on_camera_error_reopen):
		GestureBridge.camera_error_received.connect(_on_camera_error_reopen)
	# 批次 W（N5）：按钮态随桥连接态刷新（load_state_changed）——READY 才亮、OPENING→READY
	# 收口；camera_error 既有订阅（_on_camera_error_reopen）内扩展回落链。
	# 批次 Y（Y-A17/Y-A20）：收口与亮灭改以摄像头流开启真值为准（camera_stream_changed）；
	# 0 摄像头确认 → 手势交互/摄像头两按钮 disabled 置灰（重枚举到设备自动恢复）。
	if not GestureBridge.load_state_changed.is_connected(_on_bridge_state_changed):
		GestureBridge.load_state_changed.connect(_on_bridge_state_changed)
	if not GestureBridge.camera_stream_changed.is_connected(_on_camera_stream_changed):
		GestureBridge.camera_stream_changed.connect(_on_camera_stream_changed)
	if not GestureBridge.camera_enum_received.is_connected(_on_camera_enum_zero_gate):
		GestureBridge.camera_enum_received.connect(_on_camera_enum_zero_gate)
	# 批次 U（U5⑧，spec §4-U5-⑧）：LEVEL 态面板顶缘钳制 ≥ OVERLAY_TOP_FLOOR=76（窗相对；
	# 顶栏底 70＋6 间隙；面板底 76+560=636 ≤648）——顶栏「对接固定件」标签与锐眼/对接/聚焦/退出
	# 四钮完整可见（recovered_05/09 复拍对照口径）。非 LEVEL 态居中默认不变。
	if Game.current_state() == Game.State.LEVEL:
		var p: PanelContainer = $Panel
		p.anchor_top = 0.0
		p.anchor_bottom = 0.0
		p.offset_top = OVERLAY_TOP_FLOOR
		p.offset_bottom = OVERLAY_TOP_FLOOR + 560.0

## 批次 AB2（B5）：0 摄像头确认态点手势钮 → 弹「无硬件摄像头支持」提示条（Game.info →
## TopStrip info 条=对接失败弹条同组件同锚点）＋视觉回弹；不触四象限/桥/存档（存档已由
## 桥 B4 强制写关）。有摄像头态走既有四象限（Q1/Q2/Q3 语义零变化）。
func _on_gesture_toggle_toggled(_on: bool) -> void:
	if GestureBridge.is_camera_enum_zero():
		# 批次 AC（领域二，spec §4.2-4）：0 摄像头态**强制置灭**（旧实现按存档真值回写，
		# 存档 gesture_input=true 时点击后按钮回亮，与「无硬件」事实相反）＋置灰同步＋提示条。
		# 重枚举机会归摄像头钮（_on_camera_toggle_toggled 的 request_camera_enum，spec §4.2-4
		# 明文「点击摄像头按钮同时调用」）——本入口零 spawn 零出包（AB2 D11 口径不扩体）。
		gesture_toggle.set_pressed_no_signal(false)
		camera_toggle.set_pressed_no_signal(false)
		_apply_zero_camera_gate()
		Game.info(I18n.t(NO_HARDWARE_CAMERA_INFO))
		return
	_apply_camera_quadrant()

## 批次 V（V-C4，spec §4.2）：摄像头钮三态流（Q1 拦截钩子退役后的接替者，toggled 回调）。
## 态① 手势开（Q1 恒亮）：Game.info「手势交互需要摄像头，无法关闭」顶部成条自动消失（3s）
## ＋set_pressed_no_signal(true) 复位亮态——不写存档、不发命令（不触碰桥）。
## 态② 手势关+摄像头开：Game.confirm 关闭确认条——确认才进 _apply_camera_quadrant Q3 分支
## （RELEASE+写档 false）；取消/×（与取消等价）→ 零副作用＋复位亮态（toggled 信号已把视觉翻转
## 为关，不复位则按钮态与 gesture_camera_enabled 存档值失同步——P1-1 审查修订）。
## 态③ 手势关+摄像头关：钮 disabled 置灰不可点（_apply_camera_quadrant 手势关分支承载），
## 无点击入口；on=true 分支仅防御兜底（Q2「摄像头钮独立生效」语义保留）。
## 批次 W（N5，拍板 5）：手势开分支的「亮」改为摄像头流开启真值投影——批次 Y（Y-A17）起
## 以 GestureBridge.is_camera_stream_open() 为准（链路 READY 不再承担开启语义，假死 READY
## 不再假亮）；流未开（未开/主动关/设备丢失）→ 点击进 OPENING 态（禁用+「打开中…」+ensure
## 序），camera_opened 事件才收口转亮；旧「无法关闭」info 仅在流真实已开时出现（未开时点按
## 钮=打开，不再误提示）。
func _on_camera_toggle_toggled(on: bool) -> void:
	# 批次 AB2（C6/B5/D11/D12）：0 摄像头确认态点摄像头钮 → **重枚举**（GET_CAMERAS，
	# request_camera_enum 1s 节流内建；批次 AB2 R1 回修1：本入口顺带置「用户显式重枚举
	# 意图」锁存——zero 态 watchdog respawn 放行凭据，见 gesture_bridge._spawn 意图门）
	# ＋同款「无硬件摄像头支持」提示条＋视觉回弹；
	# 不进四象限/OPENING（零 SWITCH_CAMERA 零 spawn——回修2 口径：D11「空列表零 spawn」
	# 限定=**用户点击路径**零 spawn；watchdog respawn 路径按意图门语义，无意图零 respawn、
	# 有意图恰一次，断言见 test_ab_no_camera 段 E2/E3）；zero 态另有 R1 回修1 的确认边沿
	# RELEASE_CAMERA 兜底（桥侧 _handle_meta，假阴性 python 首开就地释放）。
	# 重枚举结果两分支：仍空 → _on_camera_enum_zero_gate 保持置灰（C7）；有设备 → 桥
	# zero 边沿自动开（记忆名优先/否则首项，C8）＋置灰自动解除（C9）。
	if GestureBridge.is_camera_enum_zero():
		# 批次 AC（领域二，spec §4.2-4）：0 摄像头态**双钮强制置灭**（旧实现按存档
		# gesture_camera_enabled=true 回写亮态）+重枚举请求+提示条；不进四象限/OPENING。
		camera_toggle.set_pressed_no_signal(false)
		gesture_toggle.set_pressed_no_signal(false)
		GestureBridge.request_camera_enum()
		_apply_zero_camera_gate()
		Game.info(I18n.t(NO_HARDWARE_CAMERA_INFO))
		return
	if gesture_toggle.button_pressed:
		camera_toggle.set_pressed_no_signal(true)
		# 批次 Y（Y-A17/㉔）：「无法关闭」info 收窄到「摄像头流真实开启」——假死 READY
		#（链路 READY 而流未开）点按=打开（进 OPENING），文案不再与事实相反；流开时点按
		# 文案逐字不变（批次V规格§3.3① 单源）。
		if GestureBridge.is_camera_stream_open():
			Game.info(I18n.t("手势交互需要摄像头，无法关闭"))
			return
		# 摄像头未实际打开（四象限修正：关手势→关摄像头→开手势→按钮能开摄像头）——
		# 点击=打开（ensure 序：记忆设备名优先，失败回落，流开启才收口亮）。
		_begin_camera_open()
		return
	if on:
		_apply_camera_quadrant()
		return
	# Z6-P2-9：记位本面板这条 confirm 的句柄序号（_exit_tree 据此只收自家确认）
	_my_confirm_seq = Game.confirm(I18n.t("摄像头关闭后，下次开启手势交互需要重新等待数秒启动。"),
		_on_camera_close_confirmed, _on_camera_close_canceled)

## 批次 Z（Z4-⑤/Z6-P1-4，spec §4-6/§6-P1-4）：**设备选择状态机单一入口**——设置下拉
## 设备行点击（camera_menu 经 _settings_panel_owner 定位本面板）唯一通路，不得绕过四象限
## 直发 SWITCH（P1-4：旧路径按钮显示「关」但摄像头实际开启的状态漂移根除）。
## 职责三合一（spec §4-6 定档）：①写档同步 gesture_camera_enabled=true（Q3→Q2 落档）+
## 记忆设备名（V17 选择即写档语义迁入本入口）；②点亮摄像头按钮（pressed+亮态样式）；
## ③进 OPENING 加载态（_begin_camera_open：禁用+点循环文案+ensure 序，camera_opened 才收口）。
## id 参数用于「显示名解析失配兜底」：桥 ensure 按记忆名解析的目标 ≠ 行 id（重名/枚举漂移）
## 时强制改发 SWITCH_CAMERA:<id> 并同步 attempt 记账，保证点击行=实际打开行。
func select_camera_device(id: int, device_name: String) -> void:
	SaveManager.update_settings({
		"gesture_camera_device": device_name,
		"gesture_camera_enabled": true,
	})
	camera_toggle.set_pressed_no_signal(true)   # ② 点亮（视觉真值随 ensure 结果由 OPENING 收口）
	camera_toggle.text = I18n.t(CAM_BTN_TEXT)
	camera_toggle.disabled = false
	_apply_toggle_style()
	_begin_camera_open()                        # ③ OPENING 加载态 + ensure 单漏斗
	if id >= 0 and int(GestureBridge.last_switch_camera_id) != id:
		# 显示名解析失配兜底：以用户点击的行 id 为准（单入口内补偿，不新开获取通路）
		GestureBridge.last_switch_camera_id = id
		GestureBridge.send_control("SWITCH_CAMERA:%d" % id)
	_cam_open_attempt_id = int(GestureBridge.last_switch_camera_id)
	_apply_zero_camera_gate()   # 0 摄像头置灰口径同步（有行可点时恒 false，幂等）

## 批次 W（N5）：进入 OPENING 态并启动 ensure 序（记忆设备名优先经桥 _resolve_target_camera_id；
## 目标 id 记位供 camera_error 收口判定；本方法不直接解析设备——解析单源在桥 ensure_camera_open，
## 面板经 last_switch_camera_id 读回）。
func _begin_camera_open() -> void:
	_cam_opening = true
	_cam_opening_accum = 0.0
	_cam_opening_total = 0.0   # 批次 Y（Y-A18）：8s 超时累计器归零
	_cam_open_attempt_id = -1
	_cam_opening_dot_idx = 0   # I18n 解耦②：点循环下标归零（3 点档起步）
	camera_toggle.set_pressed_no_signal(true)
	camera_toggle.disabled = true
	camera_toggle.text = I18n.t(CAM_OPENING_DOTS[0])
	_apply_toggle_style()
	GestureBridge.ensure_camera_open()
	_cam_open_attempt_id = int(GestureBridge.last_switch_camera_id)
	# 批次 W 审查 P2-B①：同步窗补漏——编辑器窗口形态下 ensure 返回后桥仍 UNAVAILABLE
	#（spawn 失败/无 py：不会再有 READY/camera_error 边沿可达）→ 立即解除 OPENING（与
	# UNAVAILABLE 边沿出口同语义）；无头（测试语义）与打包形态（launcher 代拉）不经此出口。
	if OS.has_feature("editor") and DisplayServer.get_name() != "headless" \
			and int(GestureBridge.get_load_state()) == int(GestureBridge.LoadState.UNAVAILABLE):
		_exit_opening(false)

## 批次 Y（Y-A17/Y-A18）：OPENING 终态收口单一漏斗——lit=true 转亮（流开启收口），
## lit=false 复位可点（超时回落全失败/UNAVAILABLE 边沿等出口）。
func _exit_opening(lit: bool) -> void:
	_cam_opening = false
	camera_toggle.disabled = false
	camera_toggle.text = I18n.t(CAM_BTN_TEXT)
	if lit:
		camera_toggle.set_pressed_no_signal(true)
	_apply_toggle_style()

## 批次 Y（Y-A17，spec §3.2）：流开启真值边沿投影——
## ①打开中收口一律以流真值为准：camera_opened 到达才收口转亮（READY 边沿不再收口，
##   假死 READY 永亮根除）；
## ②非打开中期 Q2/Q3 态流断开（设备丢失/释放）→ 钮回未开可点态（Q3→Q2 单开通路，
##   Y-A19）；Q1 态保持强制开视觉（点按可重开）。
func _on_camera_stream_changed(open: bool, _device_id: int) -> void:
	if not is_inside_tree():
		return
	if open and _cam_opening:
		_exit_opening(true)
	elif not open and not _cam_opening and not gesture_toggle.button_pressed:
		camera_toggle.set_pressed_no_signal(false)
		camera_toggle.disabled = false   # Y-A19：恒可点（0 摄像头由 _apply_zero_camera_gate 收口）
		_apply_toggle_style()

## 批次 W（N5）：桥连接态投影——批次 Y（Y-A17）起 READY 边沿不再承担「打开完成」语义
##（收口改由 camera_stream_changed(open=true) 承担）；UNAVAILABLE 边沿出口保留（P2-B①）。
func _on_bridge_state_changed(state: int) -> void:
	if not is_inside_tree():
		return
	if _cam_opening and state == int(GestureBridge.LoadState.UNAVAILABLE):
		# 批次 W 审查 P2-B①：UNAVAILABLE 边沿解除 OPENING——spawn 失败/断流时按钮复位可
		# 再点（不再无限「打开中…」；camera_error 回落链与流开启收口不受影响）。
		_exit_opening(false)
	elif not _cam_opening and gesture_toggle.button_pressed \
			and state != int(GestureBridge.LoadState.READY):
		# 手势开+桥转非 READY（断流/释放）：钮保持可点（点按可重开），文案复位
		camera_toggle.text = I18n.t(CAM_BTN_TEXT)
		camera_toggle.set_pressed_no_signal(true)
		_apply_toggle_style()

## 批次 W（N5）：OPENING 态点阵动画（可测方案=文案循环，0.4s 步进）。
## 批次 Y（Y-A18）：8s 超时兜底（_cam_opening_total 累计，常量 CAM_OPENING_TIMEOUT_SEC）
## 批次 Z（Z4-④ 等价改写）：超时处置=重拉枚举缓存 + 失败收口退出 OPENING——旧「回落列表
## 第一个可用设备再 SWITCH」抢句柄链退役（切换失败后旧设备/其他设备零 open；spec §4-4）。
func _process(delta: float) -> void:
	if not _cam_opening:
		return
	_cam_opening_accum += delta
	_cam_opening_total += delta
	if _cam_opening_accum >= CAM_OPENING_DOTS_SEC:
		_cam_opening_accum = 0.0
		_cam_opening_dot_idx = (_cam_opening_dot_idx + 1) % CAM_OPENING_DOTS.size()
		camera_toggle.text = I18n.t(CAM_OPENING_DOTS[_cam_opening_dot_idx])
	if _cam_opening_total >= CAM_OPENING_TIMEOUT_SEC:
		GestureBridge.request_camera_enum()   # Y-A18：收口前刷新设备枚举缓存（GET_CAMERAS）
		_fail_camera_open()

## 批次 Z（Z4-④，spec §4-4）：OPENING 失败收口单一漏斗（超时/命中本次目标的 camera_error
## 共用）——退出 OPENING、钮复位可点、报错 toast；**零设备切换**（旧「面板回落切设备」抢句柄
## 路径退役：失败后不再向任何其他设备发 SWITCH，「已切换到」谎报随之根除）。
func _fail_camera_open() -> void:
	_cam_opening = false
	camera_toggle.disabled = false
	camera_toggle.text = I18n.t(CAM_BTN_TEXT)
	Game.toast(I18n.t(CAM_OPEN_FAIL_TOAST), "warn", 3.0, true)
	_apply_toggle_style()
	_apply_zero_camera_gate()   # 失败收口后 0 摄像头置灰口径同步（幂等）

## 态②确认回调：走既有「关摄像头」路径——_apply_camera_quadrant 按当前钮态/手势态裁决（读
## camera_toggle.button_pressed=false → Q3 分支 RELEASE+写档 false）；若确认前手势已被重开则
## 自然落入 Q1 强制开分支，不会产生「手势开着却释放摄像头」的倒挂。
func _on_camera_close_confirmed() -> void:
	_apply_camera_quadrant()

## 态②取消/×回调（× 与取消等价，spec §3.1）：零副作用（存档与桥零触碰）＋复位亮态。
func _on_camera_close_canceled() -> void:
	camera_toggle.set_pressed_no_signal(true)

## 批次 V（V-C4，V-B2 移交项）：CameraMenuPopup 主弹窗棕化——PopupPanel 系 Window 主题不跨
## Window 传播（坑4）→ theme 显式赋当前主题＋panel StyleBox 棕档覆盖。棕档档值经 camera_menu
## _apply_popup_theme 同方法注入（has_method 守卫，P2-5 纪律）：主弹窗与三级子列视觉单源同族
##（批次 AB-3：theme_changed 订阅重刷随深浅主题机制删除退役，挂载直刷恒深档）。
func _apply_camera_menu_popup_theme() -> void:
	if cam_menu != null and is_instance_valid(cam_menu) and cam_menu.has_method("_apply_popup_theme"):
		cam_menu.call("_apply_popup_theme", cam_menu_popup)

func _refresh_catalog_entry() -> void:
	## 图鉴入口光标与可点性严格联动（回修3/N10 口径原样保留）
	var unlocked: bool = SaveManager.can_open_catalog()
	catalog_entry.disabled = not unlocked
	catalog_entry.mouse_default_cursor_shape = \
		Control.CURSOR_POINTING_HAND if unlocked else Control.CURSOR_FORBIDDEN

func _apply_toggle_style() -> void:
	for btn: Button in _toggles:
		var on := btn.button_pressed
		var sb := StyleBoxFlat.new()
		var sb_hover := StyleBoxFlat.new()
		for box: StyleBoxFlat in [sb, sb_hover]:
			if on:
				box.bg_color = TOGGLE_ON_BG_DARK
				box.set_border_width_all(2)
				box.border_color = TOGGLE_BORDER_GOLD
			else:
				box.bg_color = TOGGLE_OFF_BG_DARK
			box.set_corner_radius_all(TOGGLE_CORNER_RADIUS)
			box.set_content_margin_all(10.0)
			box.content_margin_left = 18.0
			box.content_margin_right = 18.0
			box.shadow_color = TOGGLE_SHADOW_COLOR   # 回修3（P3-1）：投影几何单源常量化
			box.shadow_size = TOGGLE_SHADOW_SIZE     #（与 _apply_zero_gray_overlay 灰档同源）
			box.shadow_offset = TOGGLE_SHADOW_OFFSET
		if on:
			sb_hover.bg_color = TOGGLE_ON_HOVER_DARK
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb_hover)
		btn.add_theme_stylebox_override("pressed", sb_hover)
		btn.add_theme_stylebox_override("disabled", sb)  # Q1 子开关禁用态=关式灰卡
		btn.add_theme_color_override("font_color",
			TOGGLE_ON_FONT_DARK if on else TOGGLE_OFF_FONT)
	# 批次 AB2：0 摄像头确认态 → 灰档覆写（单漏斗——任何路径重刷样式都不丢置灰观感；
	# 置灰解除时本分支不进，_apply_toggle_style 既有档自然恢复）
	if GestureBridge.is_camera_enum_zero():
		_apply_zero_gray_overlay()
	# 批次 U（U7-4）：CamTip StyleBox 注入段删除——说明窗视觉由 HoverTip 组件自持（CamTip 私有件废止）

## 批次 AB2：零摄像头灰档（视觉置灰仍可点）——几何与上方 _apply_toggle_style 档完全一致
##（同圆角 12/content_margin 18/10/**同投影 shadow 8/offset(3,5)/色 黑α0.35**，仅换底色与字色），
## 四态同盒注入防 hover/pressed 破灰。
## 批次 AB2 R1 审查回修3（P3-1）：旧漏——本函数只复制圆角与边距、漏阴影 → 0 态按钮丢投影
## 与常态档几何不一致。投影三属性改经 TOGGLE_SHADOW_* 单源常量两档共用（值与常态档逐字节同源），
## 逐项相等由 test_ab_no_camera 新段（灰档/常态档几何逐项断言）锁定。
func _apply_zero_gray_overlay() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = ZERO_GRAY_BG_DARK
	sb.set_corner_radius_all(TOGGLE_CORNER_RADIUS)
	sb.set_content_margin_all(10.0)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.shadow_color = TOGGLE_SHADOW_COLOR   # 回修3：投影三属性补齐（与常态档同源）
	sb.shadow_size = TOGGLE_SHADOW_SIZE
	sb.shadow_offset = TOGGLE_SHADOW_OFFSET
	for btn: Button in [gesture_toggle, camera_toggle]:
		for st: String in ["normal", "hover", "pressed", "disabled"]:
			btn.add_theme_stylebox_override(st, sb)
		btn.add_theme_color_override("font_color", ZERO_GRAY_FONT)

## 摄像头子开关四象限状态机（spec §8.2 终态，每次变化即落盘）
## 批次 Y（Y-A19，spec §2）：摄像头钮恒可点（0 摄像头除外）——Q3（手势关+摄像头关）不再
## 置灰禁点，点按单开摄像头（Q3→Q2 解禁通路）；置灰唯一来源=0 摄像头确认
##（_apply_zero_camera_gate 统一收口）。
func _apply_camera_quadrant() -> void:
	var gesture_on := gesture_toggle.button_pressed
	if gesture_on:
		# Q1（含 Q4 迁移，批次 U U1/U4）：两态文案统一「摄像头」＋亮态可点（Q1 点击拦截反馈
		# 由三态流态① Game.info 成条承担）；强制开语义不变：存档 true＋ensure_camera_open
		#（「进程常驻但摄像头已释放」的 Q4→Q1 迁移也能真正重开设备）
		camera_toggle.set_pressed_no_signal(true)
		camera_toggle.disabled = false
		camera_toggle.text = I18n.t(CAM_BTN_TEXT)   # 批次 Z：文案单源（消费点经 I18n.t）
		SaveManager.update_settings({"gesture_camera_enabled": true})
		GestureBridge.ensure_camera_open()
		_save_settings()
	else:
		# 手势关：Q2（摄像头钮独立生效）/ Q3（手动关，只释放摄像头）
		# 批次 Y（Y-A19）：Q3 态钮保持可点（旧 disabled 置灰废止）——点按单开摄像头
		#（toggled(true) → Q2 分支 ensure 序）。
		camera_toggle.text = I18n.t(CAM_BTN_TEXT)   # 批次 Z：文案单源
		camera_toggle.disabled = false
		var camera_on := camera_toggle.button_pressed
		SaveManager.update_settings({"gesture_camera_enabled": camera_on})
		if camera_on:
			# 批次 T（T11）/走查移交项①回修：统一入口 ensure_camera_open（Q2 根因修复
			# ＋打包形态 SWITCH 照发），与 Q1 分支同源（返回值不消费：失败反馈由
			# camera_error_received → _on_camera_error_reopen 承担）。
			GestureBridge.ensure_camera_open()
		else:
			# 批次 U（U4-②）：Q3=request_camera_release——只释放摄像头，进程与三端口常驻。
			GestureBridge.request_camera_release()
		_save_settings()
	# 批次 Y（Y-A20）：0 摄像头确认 → 双钮置灰统一收口（重枚举到设备自动恢复）。
	_apply_zero_camera_gate()

## 批次 AB2（2026-09-25，「电脑没有摄像头」分支，主会话拍板口径改写）：0 摄像头路径——
## 枚举确认 0 设备 → 手势交互/摄像头两按钮**视觉置灰但仍可点击**（点击弹「无硬件摄像头支持」
## 提示条，见 _on_gesture_toggle_toggled/_on_camera_toggle_toggled zero 分支）；旧 Y-A20
## 「disabled 真禁用」退役留痕（真禁用下用户无法「再点击一次摄像头按钮」触发重枚举）。
## zero 态双钮视觉同步存档真值（手势已被桥 B4 强制写关 → 视觉落关）。恢复：重枚举到设备
##（camera_enum_received 驱动 _on_camera_enum_zero_gate）自动解除置灰（样式复常）。
## 批次 Z（Z4-⑥）：OPENING 加载态叠加保持——_cam_opening 期间摄像头钮恒禁用（加载禁
## 重复点）；0 摄像头态不会进 OPENING（点击被 zero 分支短路），两态互斥不冲突。
func _apply_zero_camera_gate() -> void:
	var zero: bool = GestureBridge.is_camera_enum_zero()
	if zero:
		# 批次 AC（领域二，spec §4.2-4/D2）：**0 摄像头态强制双钮置灭**——旧实现在此按
		# SaveManager 真值回写（gesture_camera_enabled 缺省 true → 摄像头钮恒亮），
		# 与「无硬件摄像头」事实相反。新口径：zero 态一律 set_pressed_no_signal(false)
		# （视觉落关、不触四象限/不写档——桥 B4 已把手势键强制写关），随后置灰覆写。
		gesture_toggle.set_pressed_no_signal(false)
		camera_toggle.set_pressed_no_signal(false)
		gesture_toggle.disabled = false   # AB2：视觉置灰仍可点（disabled 视觉态=灰档样式承担）
		# 修复批 P3（2026-09-26）：zero 分支不再无条件 disabled=false——与 Z4-⑥「_cam_opening
		# 期间摄像头钮恒禁用」叠加（0 设备确认与 OPENING 可在开镜中拔设备时同帧相交），
		# 与非 zero 分支 :477 同口径 _cam_opening 门。
		camera_toggle.disabled = _cam_opening
	else:
		gesture_toggle.disabled = false
		camera_toggle.disabled = _cam_opening
	_apply_toggle_style()

## 批次 Y（Y-A20）：枚举到达 → 0 设备置灰/恢复自动收口（含面板初次挂载后到达的 init#1）。
func _on_camera_enum_zero_gate(_cameras: Array, _current: int) -> void:
	if not is_inside_tree():
		return
	_apply_zero_camera_gate()

## T12（spec §4-12-1）：箭头钮 → PopupPanel 以按钮全局左上角为锚向下展开（宽 280 常量在 camera_menu）
## 窗口缩放坐标修复2（2026-09-18）审计结论：本锚原式 Vector2i(arrow_btn.get_screen_transform().origin)
## 系纯 content 单系（无设备值/逻辑值混乘），坐标语义本就正确（逻辑论证+生产反证+窗口探针实测；
## 探针为临时件已清理，结论留痕于 scripts/coord_space.gd 头注与 AI工作记录/打包版实测修复批_
## 探针证据摘要_20260918.md：生产链路 arrow=(807,234.5) content 值、主弹窗渲染恰落其上）——
## 仅收口到 CoordSpace.popup_anchor_px 统一漏斗与 camera_menu 双子列同源，行为零变化。
func _on_arrow_pressed() -> void:
	if cam_menu_popup.visible:
		cam_menu_popup.hide()
		return
	cam_menu.call("open_menu")
	cam_menu_popup.position = CoordSpace.popup_anchor_px(arrow_btn.get_screen_transform().origin, Vector2.ZERO)
	cam_menu_popup.popup()

## 批次 U（U4-⑥，spec §4-U4-6）：RELEASE 后重开失败 → 提示降级不崩（设置面板在场才提示）。
## 批次 Z（Z4-④ 等价改写）：OPENING 态收到 camera_error 命中本次目标 → 失败收口退出
##（旧回落链切其他设备退役，零抢句柄）；非命中/非 OPENING 期保持既有降级提示。
## 批次 Y（㉓/Y-A23）：非打开中期提示文案与事实一致——「切换失败」口径（旧「摄像头未能重新
## 打开，可稍后重试」与切换设备失败事实错位，CAM_SWITCH_FAIL_TOAST 承接）。
func _on_camera_error_reopen(id: int) -> void:
	if _cam_opening and (id == _cam_open_attempt_id or _cam_open_attempt_id < 0):
		_fail_camera_open()
		return
	if is_visible_in_tree():
		Game.toast(I18n.t(CAM_SWITCH_FAIL_TOAST), "warn", 3.0, true)   # centered=true 单点改道 TopStrip（V-C1 口径）

## 批次 V 回修② P2-2：面板关闭=用户放弃挂起的摄像头关闭确认（态② Game.confirm 常驻条）——
## confirm 条按取消收起（on_canceled=复位亮态回调，零副作用：不触桥不写档；info 条不受扰）。
## 挂 _exit_tree 覆盖关闭钮/ui_cancel/close_overlay 三条退出路径（覆盖层释放必经）；
## Game.dismiss_confirm 对 strip 未挂接/替身缺方法静默（无头/测试兼容）。
## 批次 Z（Z6-P2-9，spec §6）：收口改**句柄比对**——仅当「本面板推的那条 confirm 仍活动」
## 才 dismiss；旧无条件 dismiss 会把关卡退出等他源挂起确认一并收走（红测锁定）。自有序列
## 未推过（-1）/已被他源顶替（序号不等）均不收，回修②P2-2 自家确认语义零回归。
func _exit_tree() -> void:
	if _my_confirm_seq >= 0 and int(Game.call("get_active_confirm_seq")) == _my_confirm_seq:
		Game.dismiss_confirm()
	# 批次 W（P3-3b）：theme_changed 具名断开随深浅主题机制删除退役（批次 AB-3）。

## 存档（批次 R：不再写 kb_input——字段保留不消费，旧档无损兼容 §8.1）
func _save_settings() -> void:
	SaveManager.update_settings({
		"gesture_input": gesture_toggle.button_pressed,
		"gesture_hud_visible": hud_toggle.button_pressed,
	})
	_apply_toggle_style()

## I18n：Language 行切换回调——切换即 I18n.set_language（触发 language_changed → 面板/
## 主菜单/HUD 实时重刷）+ 写档 language（update_settings 自带落盘与信号）。
func _on_language_selected(idx: int) -> void:
	var lang := "zh" if idx == 0 else "en"
	I18n.set_language(lang)
	SaveManager.update_settings({"language": I18n.get_language()})

## I18n：面板静态文案实时重刷（language_changed 订阅落点）。tscn 静态文字全部经 t()
## 覆写（zh 直通=原样；en 命中词条表）；摄像头钮文案保持状态机口径（OPENING 点循环由
## _process 下一拍覆写，此处统一按 CAM_BTN_TEXT 刷新）。CamTip 共享组件文案不重刷
##（重进设置面板生效——任务口径「其余 _ready 取值」同类）。
func _on_language_changed(_lang: String) -> void:
	_refresh_texts()

func _refresh_texts() -> void:
	($Panel/VBox/Title as Label).text = I18n.t("设置")
	catalog_entry.text = I18n.t("图鉴")
	shop_entry.text = I18n.t("衣橱")
	gesture_toggle.text = I18n.t(GESTURE_BTN_TEXT)
	camera_toggle.text = I18n.t(CAM_BTN_TEXT)
	hud_toggle.text = I18n.t("显示手势状态区")
	fullscreen_toggle.text = I18n.t("全屏显示")
	close_btn.text = I18n.t("关闭")
	arrow_btn.tooltip_text = I18n.t("摄像头选项")
	for pair: Array in [["MasterBox", "总音量"], ["MusicBox", "音乐"], ["SfxBox", "音效"]]:
		var box: Node = $Panel/VBox/VolumeGrid.get_node(String(pair[0]))
		(box.get_node("Name") as Label).text = I18n.t(String(pair[1]))
	_apply_toggle_style()

func _on_volume_changed(_v: float) -> void:
	SaveManager.update_settings({"volume": {
		"master": $Panel/VBox/VolumeGrid/MasterBox/Slider.value,
		"music": $Panel/VBox/VolumeGrid/MusicBox/Slider.value,
		"sfx": $Panel/VBox/VolumeGrid/SfxBox/Slider.value,
	}})
	AudioManager.apply_volumes()
	_refresh_volume_labels()

func _refresh_volume_labels() -> void:
	for n: String in ["MasterBox", "MusicBox", "SfxBox"]:
		var box := $Panel/VBox/VolumeGrid.get_node(n)
		(box.get_node("Value") as Label).text = "%d%%" % int(round((box.get_node("Slider") as HSlider).value * 100))

func _on_catalog() -> void:
	Game.close_overlay()
	Game.goto_state(Game.State.CATALOG)

func _on_close() -> void:
	Game.close_overlay()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_close()
		get_viewport().set_input_as_handled()

## 批次 AB-3：主题翻转回调随深浅主题机制删除退役（V-C4 棕化重刷由各 _apply_* 在 _ready 直挂承担）。
