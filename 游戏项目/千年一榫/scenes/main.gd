extends Control
## main.tscn 根：挂载全局 UI、把容器交给 Game、应用主题、监听手势加载提示。

@onready var scene_container: Control = $SceneContainer
@onready var global_ui: CanvasLayer = $GlobalUI
@onready var settings_button: Button = $GlobalUI/SettingsButton
@onready var loading_tip: Label = $GlobalUI/GestureLoadingTip
@onready var hud_mount: Control = $GestureHUDLayer/GestureHUDMount   # 批次 U（U5⑧）：迁层 GestureHUDLayer(64)
@onready var glow_rect: ColorRect = $GlobalUI/GlowLayer/GlowRect  # K-A（K9）光斑载体
# 批次 V（V-C6，spec §3.2）：窗口×确认旧弹窗节点随本批退役（main.tscn 同步删除）——
# 确认改经 Game.confirm 统一确认条（_on_window_close），旧组件文件本体保留不删（settle_scene 先例）。

var _hud_instance: Control
var ui_light_linker: Node  # L-A（L7，spec §5.6）：统一光影材质驱动（main 实例化，非 autoload）
var _hover_ctrl: Control  # L-A（L6-1）：当前挂有点光的 hover 目标（离开写 0 归零衰减）
var _gesture_unavailable_toasted := false  # 批次 R（spec §8.3-3）：UNAVAILABLE 主菜单 toast 每进程一次
var _gesture_unavailable_pending := false  # 附带回修 P2-3：UNAVAILABLE 非主菜单发生 → 回主菜单补 toast 一次
var _zero_camera_strip_shown := false      # 批次 Y（Y-A20）：0 摄像头提示条去重（重枚举到设备自动复位）
var _gesture_exit_dialog: Control  # 批次 R（spec §6.2）：手势退出倒数弹窗实例
var _cursor_layer: CanvasLayer  # S12（批次 S）：光标层成员化——光斑数据源 get_pointer_pos 消费
# 批次 Z（Z5-7）：右下加载点循环状态（LOADING 期推进，READY/UNAVAILABLE 即冻结）
var _loading_dots_active := false
var _loading_dot_idx := 0
var _loading_dot_accum := 0.0

# ---- M-C（spec §3.3-4，2026-09-07）：hover 光斑径向半径/加色「双源收口」真值常量 ----
# 批次 L 遗留：window_manager.GLOW_RADIUS_* 常量（走查定档记录）与 hover_glow.gdshader
# uniform 默认值双写不联动（改常量不改变渲染）。本批收口：真值=本常量组（与 shader
# uniform 默认值一致，test_m_cursor_glow 锚定同值防漂移），_process 每帧经
# _push_glow_radii 写入 GlowRect 材质，运行时生效值恒等于本常量，改常量即生效。
# 档值来源：HTML 原型定档（tools_m_prototype/参数定档.md，与 spec §3.3 暂定值一致）。
const HOVER_GLOW_RADIUS_BTN := 85.0    # 按钮档径向半径（L-D 65→85）
const HOVER_GLOW_RADIUS_PANEL := 110.0 # 容器档径向半径（L-D 定档保持）
const HOVER_GLOW_K := 0.16             # 加色比例（L-D 0.26→0.16 降强保字）

const CoordSpace := preload("res://scripts/coord_space.gd")  # 窗口缩放坐标修复批：content↔device 纯函数（口径契约见其头注）
const SettingsPanel := preload("res://scenes/settings/settings_panel.gd")  # 批次 Y 扫描回修 P2-1：0 摄像头文案单源（ZERO_CAMERA_INFO 常量唯一出处，硬编码句退役）

const DWM_FLAG_POLL_SEC := 1.0    # 批次 U（U9-5，spec §5）：dwm_round.flag 轮询间隔
const DWM_FLAG_WAIT_SEC := 15.0   # 批次 U（U9-5）：等 flag 上限（超时静默保持备案形态；直启降级口径）
# 修复批 P2-②（2026-09-26，独立审查确认）：装饰态持续慢轮询间隔——与「等 flag」拆分后
# 永久运行（1s 低频：每 tick 仅两次属性读+一次同值写，无 CPU 压力；调优带 1~2s）。
const DWM_DECOR_POLL_SEC := 1.0

# 批次 Z（Z5-7，spec §5-7 拍板）：右下角手势加载提示——「手势交互加载中」+ 3→2→1 点递减
# 循环（0.4s 步进；数组序即推进序：正向索引取模 = 3→2→1→3，非 0→1→2 递增）。单点常量处，
# 消费点（_update_loading_tip/_tick_loading_dots/各测试）一律经常量引用、不锁字面量；
# 旧静态文案「手势交互正在加载中」退役留痕。
const LOAD_TIP_TEXT := "手势交互加载中"
const LOAD_TIP_DOTS := [LOAD_TIP_TEXT + "...", LOAD_TIP_TEXT + "..", LOAD_TIP_TEXT + "."]
const LOAD_TIP_DOTS_SEC := 0.4

func _push_glow_radii(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("u_glow_radius_btn", HOVER_GLOW_RADIUS_BTN)
	mat.set_shader_parameter("u_glow_radius_panel", HOVER_GLOW_RADIUS_PANEL)
	mat.set_shader_parameter("u_glow_k", HOVER_GLOW_K)

func _ready() -> void:
	Game.attach(scene_container, global_ui, $GestureHUDLayer)   # 批次 U（U5⑧）：HUD 层登记（open_overlay 避让参数零改动）
	ThemeManager.apply_theme(self)
	# 批次 AB-3：深浅主题机制删除——theme_changed 订阅/回调退役，全局恒深色。
	# J6-P2-1：窗口图标（走查 NG：标题栏/任务栏无图标）。--script/无头模式无窗口服务，
	# DisplayServer.get_name()=="headless" 时跳过防报错；icon.png 为工程既有应用图标（J1-6）。
	# 4.7 实证：window_set_icon 参数类型为 Image（非 Texture2D），故取 .get_image()。
	if DisplayServer.get_name() != "headless":
		var icon_tex: Texture2D = load("res://icon.png")
		if icon_tex != null:
			DisplayServer.window_set_icon(icon_tex.get_image())
	# K-C（K4-2）：全局 toast 注入 Game（K-D 商店/K-G 关卡经 Game.toast 转发）；
	# CanvasLayer 主题边界纪律（坑 5/§3.4）：ToastCenter 为 GlobalUI 直属，显式赋主题。
	Game.attach_toast($GlobalUI/ToastCenter)
	($GlobalUI/ToastCenter as Control).theme = ThemeManager.current_theme()
	# 批次 V（V-C1，spec §3.1 P0-1 审查修订）：TopStrip 全局统一弹条——独立 CanvasLayer
	# layer=63（高于 GlobalUI=1 全部运行时 overlay 面板、低于 GestureHUDLayer=64 与
	# CameraMenuLayer=65）。禁挂 GlobalUI：open_overlay 把覆盖层 add_child 到 GlobalUI 同父
	# 后加树序会遮条（V8 病灶同源）。CanvasLayer 无 theme（坑 6）→ 条挂载即显式赋主题
	#（上两行 ToastCenter 同款）；挂后 Game.attach_strip 接线（§3.4 中央 toast 单点改道消费方）。
	var strip_layer := CanvasLayer.new()
	strip_layer.name = "TopStripLayer"
	strip_layer.layer = 63
	add_child(strip_layer)
	var top_strip: Control = load("res://scenes/shared/top_strip.gd").new()
	top_strip.name = "TopStrip"
	strip_layer.add_child(top_strip)
	top_strip.theme = ThemeManager.current_theme()
	Game.attach_strip(top_strip)
	# J6-P1-1 延伸（同根因）：GlobalUI 为 CanvasLayer，主题不向下传播（探针实证），
	# 其直属 SettingsButton/LoadingTip 与 HUD 一样需显式赋主题（走查截图 10/11 灰底按钮）。
	settings_button.theme = ThemeManager.current_theme()
	loading_tip.theme = ThemeManager.current_theme()
	# I18n：tscn 静态文字经 t() 覆写（常驻 GlobalUI 件——随 language_changed 实时重刷）。
	settings_button.text = I18n.t("设置")
	loading_tip.text = I18n.t(LOAD_TIP_DOTS[_loading_dot_idx])
	if not I18n.language_changed.is_connected(_on_language_changed):
		I18n.language_changed.connect(_on_language_changed)
	settings_button.pressed.connect(func() -> void: Game.open_overlay("settings"))
	# 手势加载提示
	_update_loading_tip(GestureBridge.get_load_state())
	GestureBridge.load_state_changed.connect(_update_loading_tip)
	# 修复3（批次Z走查 P2）：手势总开关变化时重算加载提示显隐（只处理 LOADING 态，避免
	# 旁路消费 UNAVAILABLE 态的 consume_intentional_stop/toast 副作用）。
	SaveManager.settings_changed.connect(_on_settings_changed_loading_tip)
	# BGM
	AudioManager.apply_volumes()
	AudioManager.start_bgm()
	# 手势状态区
	_hud_instance = preload("res://scenes/shared/gesture_hud.tscn").instantiate()
	hud_mount.add_child(_hud_instance)
	# GlobalUI 为 CanvasLayer，主题不跨层传播（探针实测）：挂载时显式赋主题（spec 4.0 全界面统一）
	_hud_instance.theme = ThemeManager.current_theme()
	_refresh_hud()
	# 批次 R（spec §2.4/§4.2）：光标层挂载（CanvasLayer；load() 规避 class_name 时序，
	# ui_light_linker.gd :85 同款）；注入 Router 供其合成事件（content 坐标 push_input(ev,true)）
	_cursor_layer = load("res://scripts/gesture_cursor_layer.gd").new()
	_cursor_layer.name = "GestureCursorLayer"
	add_child(_cursor_layer)
	GestureRouter.set_cursor_layer(_cursor_layer)
	# J6 信号卫生硬化（J3/J4/J5 审查留痕）：lambda 改命名方法，_exit_tree 显式断开
	GestureBridge.load_state_changed.connect(_on_load_state_for_hud)
	SaveManager.settings_changed.connect(_refresh_hud)
	# 批次 Y（Y-A20，spec §2/§5 carve-out 5）：HUD 三真值门与 0 摄像头提示条接线（摄像头相关段）
	# ——流开启真值边沿/HUD 开关写入经 _refresh_hud 重算三真值；init#1 到达驱动 0 设备提示条。
	GestureBridge.camera_stream_changed.connect(_on_camera_stream_for_hud)
	GestureBridge.camera_enum_received.connect(_on_camera_enum_for_zero_strip)
	# 批次 T（T17）：J5 备案形态——TA-1 spike 判 FAIL（gl_compatibility 渲染器无逐像素透明，
	# 证据归档 AI工作记录/walkthrough_20260916T/spike/）→ 窗口本体不透明，root 透明化与
	# α0 清屏均不落码；外框走 RoundedFrame FALLBACK_INNER 内侧装饰框（备案差异：圆角外为
	# 窗体内填充非桌面，走查报告按 plan §3 TA-1 步骤 8 标注）。
	# K-A（KA-2，spec §4.3 疑点 1）：4.7 无工程设置实效的最小尺寸键，运行期兜底；
	# K-A（K9）：光斑层只在窗口模式启用（无头守卫同 main.gd 图标先例，spec §4.2）。
	if DisplayServer.get_name() != "headless":
		get_window().min_size = Vector2i(800, 450)   # 批次 T T18 MIN_SIZE 联动（旧 720×405 等价替换留痕）
		glow_rect.visible = true
	# K-A（K8-4）：自绘三按钮接线。K-C（P2-1）→ 批次 V（V-C6，spec §3.2）：close_pressed 不再
	# 直接退出，改经 _on_window_close → Game.confirm 统一确认条（窗口×确认旧弹窗节点随本批
	# 退役，main.tscn），确认回调=_quit_now_shared，与主菜单退出同流程。WindowButtons 为
	# GlobalUI(CanvasLayer) 直属子，主题不跨层传播（J6-P1-1/spec §3.4/坑5）→ 显式赋主题。
	var window_buttons: Node = $GlobalUI/WindowButtons
	window_buttons.theme = ThemeManager.current_theme()
	window_buttons.connect("minimize_pressed", func() -> void:
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED))
	# 批次 U P0 追加口径①（用户 2026-09-19 截图反馈）：无边框窗口 window_get_mode() 恒报
	# WINDOWED（K-H 实证、4.7 复现）→ window_buttons._maxed 本地状态机为最大化权威，
	# 经此把真值透传给 RoundedFrame 隐藏装饰层与四角热区；window_decoration_hidden(mode)
	# 纯函数通道保留（覆盖 FULLSCREEN 等真实上报态）。
	window_buttons.connect("maximize_toggled", func(is_max: bool) -> void:
		($RoundedFrame as Node).call("set_decoration_hidden", is_max))
	window_buttons.connect("close_pressed", _on_window_close)
	# 窗口缩放坐标修复3（2026-09-18）：DWM 原生圆角联动——launcher.py 在拉起游戏前检测
	# Win11 DWM 原生圆角已生效时设环境变量 QNSX_DWM_ROUND=1 → RoundedFrame 进入 DWM 形态
	#（停画四角不透明三角、描边改 50% 不透明灰）；未设（直启 EXE 降级场景）→ J5 备案形态
	# 一字不变。main 只做环境读取+标志传递，形态判断内聚 rounded_frame.gd（set_dwm_round）。
	($RoundedFrame as Node).call("set_dwm_round", OS.get_environment("QNSX_DWM_ROUND") == "1")
	# 批次 U（U9-5，spec §4-U9-5）：双通道消费——①env 直读（手工预设即时 DWM 形态，保留）；
	# ②launcher 标记文件轮询（enable 成功写入 user://dwm_round.flag，发现即 set_dwm_round(true)
	# ＋用后即删；DWM_FLAG_WAIT_SEC=15s 超时静默保持备案态；陈旧标记备案接受——launcher 每次
	# 启动预清重写，双审 P2-8）。
	_poll_dwm_flag_async()
	# 批次 R（spec §6.2）：手势退出倒数弹窗（只读）挂载 + Router 倒数信号接线；
	# CanvasLayer 主题不跨层传播（坑清单 3）→ 挂载即显式赋主题。
	# 修复6（批次Z走查 P2 评估=安全）：由 GlobalUI 迁独立 ExitDialogLayer（layer=66）——
	# 旧挂载点 GlobalUI(层1) 低于 TopStrip(63)，4.5s 倒数窗内恰来一条对接失败 info 时
	# TopStrip 盖倒数条；66>63 修复遮挡，且 ≠101 光标/100 光晕/64 HUD/65 下拉/128 外框
	# （消同 index 序 non-determinism，与 Z6-P3-4 光标层提 101 现状协调）；父同为
	# CanvasLayer 全屏锚点→几何零变化，主题仍挂载显式赋值，TALK/SETTLE 偏移读 Game 态与父无关。
	var exit_layer := CanvasLayer.new()
	exit_layer.name = "ExitDialogLayer"
	exit_layer.layer = 66
	add_child(exit_layer)
	_gesture_exit_dialog = (load("res://scenes/shared/gesture_exit_dialog.tscn") as PackedScene).instantiate()
	_gesture_exit_dialog.theme = ThemeManager.current_theme()
	exit_layer.add_child(_gesture_exit_dialog)
	GestureRouter.countdown_started.connect(_on_gesture_countdown_started)
	GestureRouter.countdown_changed.connect(_on_gesture_countdown_changed)
	GestureRouter.countdown_cancelled.connect(_on_gesture_countdown_cancelled)
	GestureRouter.exit_confirmed.connect(_on_gesture_exit_confirmed)
	# L-A（L7）：统一光影材质驱动（load() 规避 class_name 时序；扫描+node_added 动态挂载）
	ui_light_linker = load("res://scripts/ui_light_linker.gd").new()
	add_child(ui_light_linker)
	_apply_glow_color()  # L-C（spec §5.5）：光晕色初始化（批次 AB-3：恒深档金白）
	# ---- boot 阶段（原 boot.tscn 职责，见任务架构决定）----
	# 批次 R（spec §8.3-1）：拉起门控跟随摄像头开关而非手势开关——Q1/Q2/Q4 有效态均拉起
	#（Q2 手势关+摄像头开时子进程照常运行、JSON 照收仅不路由）；仅 Q3（手势关+摄像头手动关）不拉起
	# 修复批 P2-①（2026-09-26，独立审查确认）：读取改经 _safe_boot_flag 二重防御——load 归一
	# 已保证两键恒 bool，但键存在值为 null 时 .get 缺省不生效，裸 bool(null) 会中止本 _ready
	# 后半（LevelLibrary 扫描/进主菜单被跳过 → 黑屏卡 BOOT）。红测 test_fix_save_normalize 锁定。
	var _boot_settings: Dictionary = SaveManager.get_settings()
	if _safe_boot_flag(_boot_settings.get("gesture_input"), true) \
			or _safe_boot_flag(_boot_settings.get("gesture_camera_enabled"), true):
		GestureBridge.start_gesture_process()   # 拉起手势子进程（所有人，含二次进入）
	LevelLibrary.scan_directory()            # 扫描关卡
	Game.goto_state(Game.State.MAIN_MENU)    # 路由主菜单（首次/二次由「开始游戏」分流）
	_boot_info_async()   # 批次 V（V19，spec §3.3③）：启动提示条（首次/再次都弹，不写档不判首启）

## 批次 V（V19，spec §3.3③）：启动提示条——每次游戏启动（首次/再次都弹）经 Game.info 顶部成条
## 「本游戏支持手势交互和键鼠交互」（4s 自灭档，验收 V19；不写档、不判首启、无条件弹）。
## 短暂延迟（一帧+0.3s）确保 TopStrip 挂接（_ready 前段 attach_strip）与主菜单路由完成后再弹
##（坑 5 --script 时序同源）；节点离树（测试 queue_free）即静默终止（_poll_dwm_flag_async 同款守卫）。
func _boot_info_async() -> void:
	await get_tree().process_frame
	await get_tree().create_timer(0.3).timeout
	if not is_inside_tree():
		return
	Game.info(I18n.t("本游戏支持手势交互和键鼠交互"), 4.0)

## 修复批 P2-①：boot 门控安全读取（传染点二重防御，与 save_manager._safe_bool 同族口径）。
## 只收 bool 直通 / int 0·1 兼容，其余（null/脏串/容器）回落缺省——bool(null) 中止族根除。
static func _safe_boot_flag(v: Variant, def: bool) -> bool:
	if typeof(v) == TYPE_BOOL:
		return v
	if typeof(v) == TYPE_INT:
		return v != 0
	return def

## S12（批次 S spec §3-12/§5.4）：光斑数据源——手势光标可见时用光标 content 坐标（get_pointer_pos），
## 否则真实鼠标（键鼠零变化）。u_mouse_px 与 hover 控件同源（合成 motion 更新 GUI hover，探针实证
## spec §2-12），按钮 per-rect 光斑与容器椭圆光斑随手势光标点亮。
## hover_glow 修复批（2026-09-18 追加）探针结论：本函数=Viewport.get_screen_transform()×content
## =**窗口相对设备像素**（probe2 实测 vp_xf origin=(0,0)、窗口在桌面 (704,500) 时不含桌面原点项），
## 与 hover_glow.gdshader 的 FRAGCOORD（渲染目标像素=窗口相对）恒同系——无需参数化。实机留待项：
## 若未来引擎版本给 Viewport.get_screen_transform() 引入桌面原点语义（4.4+ 曾有疑虑），须重验
## 本口径（届时 u_rects/u_ellipses/window_manager._push 同步受影响）。
func _resolve_pointer_px() -> Vector2:
	var vp := get_viewport()
	if _cursor_layer != null:
		var gp: Variant = _cursor_layer.call("get_pointer_pos")
		if gp != null:
			return vp.get_screen_transform() * (gp as Vector2)
	return vp.get_screen_transform() * vp.get_mouse_position()

## 窗口缩放坐标修复1（2026-09-18）：ui_material 族光斑数据源——content 逻辑系口径。
## ui_material.gdshader 端 spx=SCREEN_UV×u_viewport_size 在 u_viewport_size=visible_rect
## （恒 1152×648，逐轴拉伸实证 probe2 D1）时恒等于 content 坐标——故 u_mouse_screen 必须
## 喂 content；旧实现喂设备值（_resolve_pointer_px）致 s≠1 光核失配（s<1 光核左移、s>1
## 溢出压框线）。与 _resolve_pointer_px（hover_glow 设备系，保持不动）双轨并存，禁止混用
##（口径契约见 scripts/coord_space.gd 头注）。口径选择纯函数可无头单测（test_fix_window_scale 段2/5）。
func _resolve_pointer_content() -> Vector2:
	var gp: Variant = _cursor_layer.call("get_pointer_pos") if _cursor_layer != null else null
	return CoordSpace.hover_pointer_content(gp, get_viewport().get_mouse_position())

# ---- K-A（KA-2，K8-2/3）：16:9 窗口化校正 + F11 全屏切换 ----
var _aspect_poll := 0.0
var _glow_strength := 0.0  # K-A（K9）HoverTracker 光斑强度（0→1）
func _process(delta: float) -> void:
	_flush_pending_unavailable_toast()
	_tick_loading_dots(delta)   # 批次 Z（Z5-7）：右下加载提示 3→2→1 点循环（0.4s 步进）
	_aspect_poll += delta
	if _aspect_poll >= 0.25:
		_aspect_poll = 0.0
		# 批次 Z（Z6-P1-2，spec §6）：16:9 强制门改综合真值——无边框最大化 get_mode 恒
		# WINDOWED，旧裸判 window_get_mode 使最大化窗每 0.25s 被强改 16:9（非 16:9 屏留黑边）。
		WindowManager.enforce_aspect(_window_non_windowed())  # 0.25s 低频轮询防抖（spec §4.3 取轮询案，防 size_changed 递归）
	# L-A（L6-1/L7）+L-C（L6-3~L6-5）：光晕收敛采集（多目标邻接+分级）+ hover 目标材质点光
	var hovered := get_viewport().gui_get_hovered_control()
	var is_t := hovered != null and WindowManager.is_glow_target(hovered)
	_glow_strength = move_toward(_glow_strength, 1.0 if is_t else 0.0, delta / 0.12)
	var vp := get_viewport()
	var mouse_px: Vector2 = _resolve_pointer_px()
	if glow_rect.visible and glow_rect.material is ShaderMaterial:
		var mat := glow_rect.material as ShaderMaterial
		mat.set_shader_parameter("u_strength", _glow_strength)
		mat.set_shader_parameter("u_mouse_px", mouse_px)  # K-A 校准沿用：FRAGCOORD 与鼠标 y 同向
		_push_glow_radii(mat)  # M-C（spec §3.3-4）：径向半径/加色每帧写入（双源收口）
		# L-C（spec §7.1）：多掩码写入（矩形档+容器档椭圆参数）+分级强度；
		# 0.12s 淡入淡出作用于总幅 u_strength（各 rect 强度分量由 glow_targets_for 给出）；
		# hovered 非 glow 目标时传 null 采集 → 空采集 → u_rect_count=0。
		var gt: Dictionary = WindowManager.glow_targets_for(hovered if is_t else null)
		var rects: Array = gt["rects"]
		var cnt := mini(rects.size(), WindowManager.MAX_RECTS)
		mat.set_shader_parameter("u_rect_count", cnt)
		if cnt > 0:
			var v4s: Array = []
			for r: Rect2 in rects:
				v4s.append(Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
			mat.set_shader_parameter("u_rects", v4s)
			mat.set_shader_parameter("u_rect_strength", gt["strengths"])
			mat.set_shader_parameter("u_mask_type", gt["mask_types"])
			mat.set_shader_parameter("u_ellipses", gt["ellipses"])
	if ui_light_linker != null:
		# L-D 二轮修4：视口尺寸每帧随窗口刷新（linker 内部按值变化才写）——shader 点光
		# 坐标=SCREEN_UV*u_viewport_size，须与 u_mouse_px 同口径（content 坐标，y 同向）。
		ui_light_linker.call("set_viewport_size", vp.get_visible_rect().size)
		if is_t:
			if _hover_ctrl != null and _hover_ctrl != hovered:
				ui_light_linker.call("set_hover", _hover_ctrl, Vector2.ZERO, 0.0)
			# L-D 二轮修4：直接传屏幕像素 mouse_px（原 affine_inverse 局部换算与新口径不符已删）
			# 窗口缩放坐标修复1（2026-09-18）：set_hover 改传 content 口径（_resolve_pointer_content）
			# ——ui_material 族全 content 系（shader spx=SCREEN_UV×u_viewport_size=content）；原设备值
			# 与逻辑采样失配因子 s。hover_glow 的 u_mouse_px（:149 设备系）保持不动。
			ui_light_linker.call("set_hover", hovered, _resolve_pointer_content(), _glow_strength)
		elif _hover_ctrl != null:
			ui_light_linker.call("set_hover", _hover_ctrl, Vector2.ZERO, 0.0)
	_hover_ctrl = hovered if is_t else null

## 批次 T（T11，spec §4-11-toast）：UNAVAILABLE toast 文案双分支——手势开=「已切换键鼠操作」
##（键鼠降级提示有意义）；仅开摄像头（手势关）=「摄像头暂未打开」（无降级语义）。一次/episode
## 去重与 consume_intentional_stop 抑制沿用不变（gesture_bridge.gd :257-260）。
func _unavailable_toast_text() -> String:
	if bool(SaveManager.get_settings().get("gesture_input", true)):
		return I18n.t("摄像头暂未打开，已切换键鼠操作")
	return I18n.t("摄像头暂未打开")

## I18n：语言切换实时重刷（常驻 GlobalUI 两件：设置钮/加载提示；main.gd 与进程同生命周期，无需退订）。
func _on_language_changed(_lang: String) -> void:
	settings_button.text = I18n.t("设置")
	loading_tip.text = I18n.t(LOAD_TIP_DOTS[_loading_dot_idx])

## 附带回修 P2-3（S14 改文案/落点）：UNAVAILABLE 曾在非主菜单发生 → 回主菜单补 toast 一次。
## 抽出成方法以便无头直测（_process 其余逻辑依赖窗口服务）。
func _flush_pending_unavailable_toast() -> void:
	if _gesture_unavailable_pending and not _gesture_unavailable_toasted \
			and Game.current_state() == Game.State.MAIN_MENU:
		_gesture_unavailable_pending = false
		_gesture_unavailable_toasted = true
		Game.toast(_unavailable_toast_text(), "warn", 2.5, true)   # S14 中央锚点盒；批次 T11 文案双分支

func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and (key.keycode == KEY_F11 or key.physical_keycode == KEY_F11):
		WindowManager.set_fullscreen(not WindowManager.is_fullscreen())  # K8-3 F11 全局监听
		# P2-1 回修：F11 全屏切换后回显三钮 □/❐ 字形（全屏非 maximized，refresh 归 □）
		var wb: Node = get_node_or_null("GlobalUI/WindowButtons")
		if wb != null:
			wb.call("refresh_state")

# ---- K-A（KA-4，K8-4）：无边框拖窗——热区 IGNORE 不拦截，全局原始按下 + 交互控件命中排除 ----
## 批次 AC（2026-09-27 领域七，spec §4.7）：拖窗升级为 Godot 4 原生系统级接口。
## 病灶：旧实现「MouseMotion 逐帧 DisplayServer.window_set_position(mouse - grab)」构成
## 位置反馈环——窗口移动改变鼠标相对客户区坐标、进而改变下一帧的 mouse_get_position()，
## 且受游戏帧率与 DWM 合成节拍双重钳制，实机呈现沉重迟滞。
## 现方案：物理左键按下即调用 DisplayServer.window_start_drag()，Windows 后端转
## SendMessage(WM_SYSCOMMAND, SC_MOVE | HTCAPTION)（display_server_windows.cpp:4965-4993）
## 交由 OS 窗口管理器进入原生模态移动循环，以硬件刷新率平滑跟手，本进程零逐帧参与。
## 守卫链（无头早退/合成事件早退/最大化全屏门/交互控件命中/立绘可见区）全部原样保留。
var _win_dragging := false   # 仅作「本帧处于原生拖拽会话」的可观测标记（无逐帧位移计算）

## 批次 Z（Z6-P1-2，spec §6）：非「可拖拽窗口化」态综合判据（拖窗门与 enforce_aspect 共用
## 单漏斗）——无边框窗口 get_mode 恒报 WINDOWED，最大化须并入 WindowButtons._maxed 本地状态
## 机与 RoundedFrame 装饰隐藏标志双通道（复用本文件批次 U P0①/R2②-P2-3 自己的
## 双通道口径），收敛到 WindowManager.drag_gate_closed 纯函数（无头红测可断言）。
## 后果回修：旧裸判 window_get_mode 时「最大化后拖任意非交互区 → 窗口被拖离最大化位」。
## 修复4（批次Z走查 P2 建议修）：第三通道入参由 window_decoration_hidden(mode)（=mode>=MAXIMIZED，
## 与通道① mode!=WINDOWED 逻辑蕴含、死通道）改读 _decoration_force_hidden 显式标志——
## maximize_toggled 即时写 + 1s 轮询刷新的状态机真值，与 mode/_maxed 真正正交（覆盖
## 装饰层已被强制隐藏而 mode/_maxed 未及反映的窗口期与 WindowButtons 缺位场景）。
func _window_non_windowed() -> bool:
	var mode: int = DisplayServer.window_get_mode()
	var wb_maxed := false
	var wb := get_node_or_null("GlobalUI/WindowButtons")
	if wb != null:
		wb_maxed = bool(wb.get("_maxed"))
	var deco := false
	var rf := get_node_or_null("RoundedFrame")
	if rf != null:
		var flag: Variant = rf.get("_decoration_force_hidden")
		deco = bool(flag) if flag != null else false
	return WindowManager.drag_gate_closed(mode, wb_maxed, deco)

func _input(event: InputEvent) -> void:
	if DisplayServer.get_name() == "headless": return
	# 批次 Z（Z6-P2-2，spec §6）：手势合成事件显式跳过拖窗分支——gesture_cursor_layer 合成
	# 按下/移动带 SYNTH_META 标记，旧码对合成与真实输入无判别 → 「手势点击 + 另一手/同人动
	# 鼠标」时 _win_dragging 被合成按下置位、窗口跳位。仅跳过合成事件，键鼠原始路径零变化。
	if event.has_meta(GestureCursorLayer.SYNTH_META): return
	# 批次 Z（Z6-P1-2）：拖窗门改综合真值（最大化/全屏态不得启动拖窗）。
	if _window_non_windowed(): return
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			# 批次 AC（领域七，spec §4.7）：双击不触发原生拖拽——window_start_drag 走
			# SC_MOVE|HTCAPTION 的系统标题栏语义，双击会被 OS 解释为「双击标题栏最大化」，
			# 与自绘三钮 WindowButtons._maxed 状态机（无边框下 get_mode 恒报 WINDOWED）
			# 脱同步。首击已入 OS 模态移动循环，第二击直接忽略即可。
			if mb.double_click:
				return
			var hovered := get_viewport().gui_get_hovered_control()
			if hovered != null and WindowManager.is_interactive_control(hovered):
				return  # 放行场景按钮（P1-2 契约①：关卡/商店顶栏点击不受影响）
			# 批次 Y（Y-C9④，spec §9.2）：立绘可见区命中→不启动拖窗。选型留痕：关卡立绘
			# mouse_filter=IGNORE（批次 W P1-7a 拾取带修复保持），meta("interactive") 白名单
			# 对 gui_get_hovered_control 不可达——改经当前场景谓词显式豁免（carve-out：本段
			# 为 main.gd 在批次 Y5 的唯一改动，倒数/退出接线段未触碰）。
			var cur_sc: Node = Game.get_current_scene()
			if cur_sc != null and cur_sc.has_method("is_point_over_witness_visible") \
					and bool(cur_sc.call("is_point_over_witness_visible", get_viewport().get_mouse_position())):
				return
			# 批次 AC（领域七，spec §4.7）：交 OS 原生拖拽（WM_SYSCOMMAND/SC_MOVE）。
			# 旧版 `_win_grab = mouse_get_position() - window_get_position()` 抓取与在
			# MouseMotion 中逐帧 window_set_position(...) 的反馈环整段退役——本处只发一次
			# 系统调用，之后由 DWM/OS 窗口管理器接管（Windows 后端会顺手合成一次左键抬起，
			# 见 display_server_windows.cpp 的 is_mouse_button_pressed 循环，故本进程无需
			# 自行补发释放事件；真实抬起仍照常走下方 else 分支清标记）。
			_win_dragging = true
			DisplayServer.window_start_drag()
		else:
			_win_dragging = false
	# 批次 AC（领域七）：旧 `elif event is InputEventMouseMotion and _win_dragging:
	# DisplayServer.window_set_position(...)` 逐帧位移分支整段退役——原生拖拽期窗口跟手
	# 由 OS 模态移动循环完成，本进程对 MouseMotion 零处理（上方 else 分支已在按下释放时
	# 清标记；Windows 后端在拖拽结束时合成一次左键抬起，见 display_server_windows.cpp）。

# ---- K-C（KC-3）→ 批次 V（V-C6，spec §3.2）：close → Game.confirm 统一确认条 → 确认才真退出 ----
## 窗口×确认旧弹窗节点随本批退役（main.tscn）；窗口×与主菜单退出同经
## Game.confirm("退出《千年一榫》？", _quit_now_shared)——文案与既有弹窗正文逐字一致（旧弹窗
## 标题「退出」/按钮「退出/取消」的确认语义由统一确认条「确认/取消」承载）；确认=真退出，
## 取消/×=零副作用（TopStrip 侧承接）。
func _on_window_close() -> void:
	Game.confirm(I18n.t("退出《千年一榫》？"), _quit_now_shared)

func _quit_now_shared() -> void:
	# 与主菜单退出同流程（main_menu.gd:_quit_now 同构）：批次 V（V18，spec §8.2）退出兜底保存
	# ——stop/quit 前显式 SaveManager.save_game()（本函数=窗口×确认与所有确认退出共用的真退出
	# 函数，覆盖退出前未落盘的内存变更；close_requested 自动保存 save_manager.gd:23-25 保留），
	# 再停手势子进程再 quit（K-H WA-⑤ 验收口径）。
	SaveManager.save_game()
	# P2-12b（批次 W 规格 §3）：LEVEL 态退出前显式落一次关卡检查点——消除对 level_scene
	# _exit_tree 兜底时序的依赖（get_tree().quit() 拆树时序未验证；N11 flush_checkpoint 复用：
	# 幂等省写，未动关卡零 I/O；_settled 守卫防把通关态重写成断点）。SETTLE 态结算覆盖层期间
	# _goto_settle 已删键清脏，无需重落。
	if Game.current_state() == Game.State.LEVEL:
		var lvl: Node = Game.get_current_scene()
		if lvl != null and lvl.has_method("flush_checkpoint"):
			lvl.call("flush_checkpoint")
	GestureBridge.stop_gesture_process()
	get_tree().quit()

## L-C（spec §5.5/§7.1）：光晕色（深金白）写入 GlowRect 材质。
## 启动即写一次；批次 AB-3：深浅主题机制删除——深档金白 (1.0,0.95,0.8) 为唯一值（浅冷白退役）。
func _apply_glow_color() -> void:
	if glow_rect.material is ShaderMaterial:
		(glow_rect.material as ShaderMaterial).set_shader_parameter("u_glow_color", Vector3(1.0, 0.95, 0.8))

func _on_load_state_for_hud(_s: int) -> void:
	_refresh_hud()

# ---- 批次 Y（Y-A20，spec §2/§5 carve-out 5）：HUD 三真值门 + 0 摄像头提示条（摄像头相关段） ----
## 流开启真值边沿 → 三真值重算（流开启/关闭即刷新 HUD 可见性，不再仅随 load_state/settings）。
func _on_camera_stream_for_hud(_open: bool, _device_id: int) -> void:
	_refresh_hud()

## 枚举确认 0 设备 → TopStrip 提示条「未检测到摄像头，手势交互无法使用」（Game.info 路由）；
## 重枚举到设备自动复位（再次 0 设备确认可再提示，每次确认一条不刷屏）。
func _on_camera_enum_for_zero_strip(_cameras: Array, _current: int) -> void:
	var cams: Array = (GestureBridge.get_camera_enum() as Dictionary).get("cameras", [])
	if cams.is_empty():
		if not _zero_camera_strip_shown:
			_zero_camera_strip_shown = true
			Game.info(SettingsPanel.ZERO_CAMERA_INFO, 4.0)   # 批次 Y 扫描回修 P2-1：文案单源（settings_panel 常量，逐字不变）
	else:
		_zero_camera_strip_shown = false
	_refresh_hud()

## J6 信号卫生硬化：断开挂在 autoload（常驻）上的命名连接，防场景释放后回调 freed 实例。
func _exit_tree() -> void:
	if GestureBridge.load_state_changed.is_connected(_on_load_state_for_hud):
		GestureBridge.load_state_changed.disconnect(_on_load_state_for_hud)
	# 批次 Y（Y-A20）：三真值门/0 摄像头提示条信号卫生（同上硬化口径）
	if GestureBridge.camera_stream_changed.is_connected(_on_camera_stream_for_hud):
		GestureBridge.camera_stream_changed.disconnect(_on_camera_stream_for_hud)
	if GestureBridge.camera_enum_received.is_connected(_on_camera_enum_for_zero_strip):
		GestureBridge.camera_enum_received.disconnect(_on_camera_enum_for_zero_strip)
	if GestureBridge.load_state_changed.is_connected(_update_loading_tip):
		GestureBridge.load_state_changed.disconnect(_update_loading_tip)
	if SaveManager.settings_changed.is_connected(_on_settings_changed_loading_tip):
		SaveManager.settings_changed.disconnect(_on_settings_changed_loading_tip)
	if SaveManager.settings_changed.is_connected(_refresh_hud):
		SaveManager.settings_changed.disconnect(_refresh_hud)
	# 批次 R：Router 倒数信号卫生（J3/J4/J5 审查留痕同款硬化）
	if GestureRouter.countdown_started.is_connected(_on_gesture_countdown_started):
		GestureRouter.countdown_started.disconnect(_on_gesture_countdown_started)
	if GestureRouter.countdown_changed.is_connected(_on_gesture_countdown_changed):
		GestureRouter.countdown_changed.disconnect(_on_gesture_countdown_changed)
	if GestureRouter.countdown_cancelled.is_connected(_on_gesture_countdown_cancelled):
		GestureRouter.countdown_cancelled.disconnect(_on_gesture_countdown_cancelled)
	if GestureRouter.exit_confirmed.is_connected(_on_gesture_exit_confirmed):
		GestureRouter.exit_confirmed.disconnect(_on_gesture_exit_confirmed)

# ---- 批次 R（spec §6.2）：倒数弹窗驱动（Router 信号 → 只读窗正文刷新/关闭） ----
func _on_gesture_countdown_started(remaining: int) -> void:
	_gesture_exit_dialog.call("show_countdown", remaining)

func _on_gesture_countdown_changed(remaining: int) -> void:
	_gesture_exit_dialog.call("update_countdown", remaining)

func _on_gesture_countdown_cancelled(_reason: String) -> void:
	_gesture_exit_dialog.call("close_countdown")

func _on_gesture_exit_confirmed() -> void:
	_gesture_exit_dialog.call("close_countdown")   # 翻转 #4：关弹窗 → Router 执行 §6.3 分流

## 批次 Z（Z5-7）：加载点推进器——仅 LOADING 活跃期累计步进（0.4s 换档：3→2→1→3 循环）；
## READY/UNAVAILABLE 冻结（_loading_dots_active=false 直返，文本零推进）。
## 从 _process 拆出独立方法供中途帧断言直测（0.39s 不推进 / 0.41s 推进，防空转假绿）。
func _tick_loading_dots(delta: float) -> void:
	if not _loading_dots_active:
		return
	_loading_dot_accum += delta
	if _loading_dot_accum >= LOAD_TIP_DOTS_SEC:
		_loading_dot_accum = 0.0
		_loading_dot_idx = (_loading_dot_idx + 1) % LOAD_TIP_DOTS.size()
		loading_tip.text = I18n.t(LOAD_TIP_DOTS[_loading_dot_idx])

func _update_loading_tip(state: int) -> void:
	match state:
		GestureBridge.LoadState.LOADING:
			# 修复3（批次Z走查 P2，Q3=手势关+摄像头关）：手势总开关关闭 → 加载提示无意义
			#（Q3 boot 门不 start_gesture_process → 桥状态滞留 LOADING，旧码无条件显示致
			# 开机右下永久「手势交互加载中」+点循环）。仅显示层门控，不改桥状态机——
			# 备选①（boot 未 start 置 UNAVAILABLE）会走 UNAVAILABLE toast + 5s 自动重拉分支，
			# 有误拉起 python/摄像头对抗 Q3「真的关掉」意图的风险，弃用。
			if not bool(SaveManager.get_settings().get("gesture_input", true)):
				loading_tip.visible = false
				_loading_dots_active = false
				return
			loading_tip.text = I18n.t(LOAD_TIP_DOTS[0])   # Z5-7：动态点起点（3 点档）
			loading_tip.visible = true
			_loading_dots_active = true
			_loading_dot_idx = 0
			_loading_dot_accum = 0.0
		GestureBridge.LoadState.READY:
			loading_tip.visible = false
			_loading_dots_active = false   # Z5-7：收口即冻结
		GestureBridge.LoadState.UNAVAILABLE:
			# A6（J1-3）：键鼠恒可用，「不可用」提示无意义 → 直接隐藏（节点保留，LOADING 仍用）
			loading_tip.visible = false
			_loading_dots_active = false   # Z5-7：收口即冻结
			# S14（批次 S）：主动关（Q3）≠故障——consume_intentional_stop 为 true 时跳过 toast 与
			# pending 标记（标志取走即清，一次性语义由 bridge 侧保证）
			if GestureBridge.consume_intentional_stop():
				return
			# 批次 R 去重标志沿用（一次/episode）；S14 文案/落点改「摄像头暂未打开」顶部中央
			if not _gesture_unavailable_toasted:
				if Game.current_state() == Game.State.MAIN_MENU:
					_gesture_unavailable_toasted = true
					Game.toast(_unavailable_toast_text(), "warn", 2.5, true)   # 批次 T11 文案双分支
				else:
					_gesture_unavailable_pending = true

## 修复3（批次Z走查 P2）：手势总开关切换 → 重算加载提示（仅 LOADING 态重放，避开
## UNAVAILABLE 分支的 consume_intentional_stop 取走即清副作用；READY 态提示本就隐藏无需处理）。
func _on_settings_changed_loading_tip() -> void:
	if GestureBridge.get_load_state() == GestureBridge.LoadState.LOADING:
		_update_loading_tip(GestureBridge.LoadState.LOADING)

func _refresh_hud() -> void:
	if _hud_instance == null:
		return
	# 批次 R（spec §7.3）：控制台可见=手势开关开 且 显示区开关开（加载中/不可用占位由控制台自绘，
	# 不再要求 READY；停靠表按当前状态重算）
	var s: Dictionary = SaveManager.get_settings()
	# 批次 Y（Y-A20，spec §2 定档）：HUD 全隐可见门升级三真值 gesture_hud_visible ∧ gesture_input
	# ∧ camera_stream_open——第三真值=桥摄像头流开启真值（§3.2；0 摄像头/流未开=false→全隐），
	# 边沿经 _on_camera_stream_for_hud 驱动重算。第三支后置于 apply_dock（HUD 自身门保持两真值
	# 承担子件配置裁剪——若入 HUD 门会经早退跳过停靠几何配置），AND 收口在此处唯一落点。
	_hud_instance.visible = bool(s.get("gesture_hud_visible", true)) \
		and bool(s.get("gesture_input", true))
	if _hud_instance.has_method("apply_dock"):
		_hud_instance.call("apply_dock")
	_hud_instance.visible = bool(_hud_instance.visible) \
		and GestureBridge.is_camera_stream_open()
	# S16（批次 S spec §3-16）：关「手势交互」→ 同步清理全部手势 UI（光标圈即时隐、倒数弹窗关、
	# Router 全量复位含 tracker/描边/面板/armed）；_refresh_hud 挂 settings_changed（:74），开关切换即触发。
	if not bool(s.get("gesture_input", true)):
		if _cursor_layer != null:
			_cursor_layer.call("hide_cursor", "left")
			_cursor_layer.call("hide_cursor", "right")
		if _gesture_exit_dialog != null:
			_gesture_exit_dialog.call("close_countdown")
		GestureRouter.reset_runtime()

## 批次 U（U9-5）＋修复批 P2-②（2026-09-26，独立审查确认）：dwm_round.flag 轮询与装饰态
## 刷新**拆分**——旧实现二者耦合在同一循环：15s 超时（DWM_FLAG_WAIT_SEC）循环结束、或 flag
## 命中即 return → _decoration_force_hidden 不再刷新 → 运行 >15s 后 Aero Snap 最大化
## （无边框 get_mode 恒报 WINDOWED，K-H 实证）下拖窗门/16:9 门半失效（drag_gate_closed
## 第三通道读的就是 _decoration_force_hidden）。现：①等 flag 最多 15s（命中即 break 收束
## 等待段，陈旧标记备案接受——launcher 每次启动预清重写）；②装饰态刷新抽出
## _refresh_decoration_state 并经 DWM_DECOR_POLL_SEC 持续慢轮询（永久，见函数尾段）。
## await process_frame 时序坑不适用（create_timer 驱动）。
func _poll_dwm_flag_async() -> void:
	var path := "user://dwm_round.flag"
	var waited := 0.0
	while waited < DWM_FLAG_WAIT_SEC:
		# R1-P2-7（批次 U 收尾审计顺带修）：场景切换/测试 queue_free 后节点离树，轮询立即退出——
		# 防离树后下一轮 get_tree() 为 null（create_timer 崩）或继续触碰子节点。守卫置于循环顶
		#（await 求值 get_tree() 之前）才真正闭合窗口；节点已释放时协程随宿主消亡不恢复，无此窗口。
		if not is_inside_tree():
			return
		await get_tree().create_timer(DWM_FLAG_POLL_SEC).timeout
		waited += DWM_FLAG_POLL_SEC
		# R2②-P2-3（Aero Snap 缝隙收敛）：每 tick 顺带刷装饰态（旧口径保留于等 flag 段，
		# 见 _refresh_decoration_state 头注——真值与信号路径一致，重复写同值无副作用）。
		_refresh_decoration_state()
		if FileAccess.file_exists(path):
			($RoundedFrame as Node).call("set_dwm_round", true)
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			break  # 修复批 P2-②：只结束「等 flag」；装饰态刷新转入下方持续慢轮询（旧码此处 return）
	# 修复批 P2-②：装饰态持续慢轮询（永久，DWM_DECOR_POLL_SEC）——等 flag 的 15s 上限不再
	# 连带终止装饰刷新；Aero Snap 拖拽最大化任何时候都在 1s 内收敛到拖窗门/16:9 门，拖回还原
	# 同路径恢复。离树守卫同上（协程随宿主消亡不恢复）。
	while true:
		if not is_inside_tree():
			return
		await get_tree().create_timer(DWM_DECOR_POLL_SEC).timeout
		_refresh_decoration_state()

## 修复批 P2-②：装饰态刷新单点（轮询两段共用；测试 test_fix_save_dwm_decor 可不入树直调
## 断言 _decoration_force_hidden 状态翻转）。R2②-P2-3 真值口径原样收编：按「mode 真实上报态
## （FULLSCREEN 等）＋窗口钮 _maxed 本地状态机（borderless get_mode 恒报 WINDOWED，4.7 实证，
## 拖拽到屏缘系统最大化不走 maximize_toggled）」综合判定刷新装饰层隐藏。
## 注记：DisplayServer 真窗口 mode 通道无头桩不到 → 真实 Snap 最大化收敛需真机复验
## （结构与状态机断言已由 test_fix_save_dwm_decor 锁定）。
func _refresh_decoration_state() -> void:
	var wb_ref: Node = get_node_or_null("GlobalUI/WindowButtons")
	var snap_max: bool = bool(wb_ref != null and bool(wb_ref.get("_maxed"))) \
		or bool(($RoundedFrame as Node).call("window_decoration_hidden", DisplayServer.window_get_mode()))
	($RoundedFrame as Node).call("set_decoration_hidden", snap_max)
