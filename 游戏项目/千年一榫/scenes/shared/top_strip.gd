class_name TopStrip
extends PanelContainer
## 批次 V（V-C1，spec §3.1/§3.2/§3.4）：全局统一弹条——顶部居中单槽 info/confirm 双模式。
## 挂载=独立 CanvasLayer layer=63（main.gd 代码创建；禁挂 GlobalUI——open_overlay 把覆盖层
## add_child 到 GlobalUI 同父后加树序会遮条，V8 病灶同源；高于 GlobalUI=1 全部运行时 overlay
## 面板、低于 GestureHUDLayer=64 与 CameraMenuLayer=65）。CanvasLayer 无 theme（§14 坑 6）
## → 挂载即显式注入 ThemeManager.current_theme()（批次 AB-3：theme_changed 订阅重刷随深浅
## 主题机制删除退役，恒深档；push 惰性兜底）。
## 几何：复用 toast_center 中央锚点盒口径——anchor 左右 0.5 水平居中、offset_top=TOP_OFFSET(70)、
## grow 双向；条宽随内容 min MIN_WIDTH(320)、max=视口宽−2×MARGIN(14)（autowrap+超宽钳制，
## 坑 3 锚定直接赋值不走 set_anchors_preset）。批次 Y（Y-A1）：水平几何改 _refit_width 无状态
## 恒对称重推导单漏斗（push/resized/视口 size_changed 三入口；探针实证旧 grow-BOTH 反算
## offsets 残留 + reset_size 非对称反算=贴左根因，证据 AI工作记录/批次Y_走查_20260922/）。
## 视觉：棕主题弹窗档 GlassDialog L3 同族（深 Color(0.30,0.22,0.09,0.72)/浅 Color(0.99,0.92,0.72,0.75)、
## 圆角 14、shadow 16）；条 set_meta("ui_material","panel")、内嵌按钮 set_meta("hover_glow",true)
##（UILightLinker 对 node_added 动态挂材质链、hover_glow 体系自动覆盖 Button，§12-4 meta 显式兜底）。
## API（跨批契约）：push_info(text, seconds=3.0)——info 模式文本+自动消失、无按钮；
## push_confirm(text, on_confirmed, on_canceled=Callable())——confirm 模式常驻直至用户选择，
## 条内嵌「确认」「取消」两 Button + 右上「×」钮；确认→on_confirmed 并收起；取消或 ×→on_canceled
##（空回调静默收起；零副作用=不调 on_confirmed）；signal confirmed/canceled 供测试断言。
## 单槽策略（confirm 优先，spec §3.1 槽位拍板；批次 W P2-7 顶替语义修订见 push_confirm 头注：
## 旧 confirm 被新 confirm 顶替时旧 on_canceled 补调恰一次）：
## confirm 活动期新 info 入单槽队列（批次 Z Z6-P2-10：旧「直接丢弃」废止——confirm 收起后
## 补播最新一条，显示期间条文案不受扰）；info 活动期新 confirm 顶掉 info；info 到时自灭释放槽位。
## 批次 Z（Z6-P1-5/P2-9）：push_confirm 自增句柄序号 _confirm_seq，active_confirm_seq() 供
## Game.get_active_confirm_seq 转发——面板 _exit_tree 据此只收自家确认（误杀他源/僵尸条根除）。
## 跨态收起（批次 V 审查①P2-4，spec §3.2/§8）：订阅 Game.state_changed（_ready 订阅/_exit_tree
## 退订）——场景切换时 confirm 常驻条自动按取消收起（on_canceled 回调执行、零副作用=不调
## on_confirmed），条不跨场景残留；info 不受影响（自有计时自灭）；防重入=_mode 判据守卫。
## 4.7 坑注记：回调一律 is_valid() 判空后再调（坑 1）；info 计时器按值捕获递增 seq（坑 8 lambda
## 按值捕获）防旧计时器误关新条；不触碰存档/桥——取消路径纯 UI 收起。

signal confirmed
signal canceled

const TOP_OFFSET := 70.0      # 中央盒顶（toast_center.CENTER_TOP 同值，几何单源迁入本组件）
const LEVEL_TOP_OFFSET := 6.0 # 批次 W（P1-5，拍板 2）：LEVEL 态条顶贴边——条顶移入顶栏（高 60）
                              # 高度内短暂覆盖顶栏标签，2.5s info 自愈；与主菜单视觉语言一致
const SHOP_TOP_OFFSET := 96.0 # 批次 AA（W8-3，spec §11.4-2【暂定值·待用户复验】）：SHOP 态条顶下移——
                              # 商店顶排三件（cam/status/hint 底 90）占 y∈[16,90]，旧 TOP_OFFSET 70 与
                              # 三件实叠 20px 且 HUD 层 64 > 弹条层 63 会把确认文案盖死（购买确认条
                              # 商店内高频）；96 > 90 → 结构零相交。机制同 LEVEL_TOP_OFFSET（per-state
                              # 偏移表加 SHOP 支），直接赋 offset_top/offset_bottom 不走 set_anchors_preset。
const MARGIN := 14.0          # 视口左右安全边距（spec §3.1 max=视口宽−2×14）
const MIN_WIDTH := 320.0      # 条最小宽（spec §3.1）
const ROW_SEPARATION := 10.0  # Row 内 MsgLabel↔BtnRow 间距（_build 与 _apply_content_width 单源）
const CONFIRM_MSG_MIN_W := 240.0  # NG-2：MsgLabel 最小宽保障——confirm 按钮行不把文案挤成竖窄条
const INFO_SECONDS_DEFAULT := 3.0
const SLIDE_TIME := 0.25      # 批次 W（N2）：自上方滑入+淡入统一时长（规格 0.2~0.3s 档）
const SLIDE_GAP := 14.0       # 批次 W（N2）：滑入起点=目标位上方（条高+14）
# 批次 W（P3-1）：色彩单源表（值不变）。
const Palette := preload("res://scripts/palette.gd")
const DARK_BG := Color(0.30, 0.22, 0.09, 0.72)   # GlassDialog L3 弹窗档底（spec §3.1）
const DARK_BORDER := Color(Palette.STROKE_GOLD, 0.45)   # P3-1：描边金单源（值不变）
const DARK_FONT := Palette.STROKE_GOLD   # P3-1：消息金=描边金全 α（值不变；提示金两档留走查定档）
# 批次 AB-3：LIGHT_BG/LIGHT_BORDER/LIGHT_FONT 浅档随深浅主题机制删除退役，深档为唯一值。

var _msg_label: Label
var _btn_row: HBoxContainer
var _ok_btn: Button
var _cancel_btn: Button
var _close_btn: Button
var _ok_cb: Callable = Callable()
var _cancel_cb: Callable = Callable()
var _mode := ""          # "" / "info" / "confirm"
var _info_seq := 0       # 递增序号：仅最新一条 info 的计时器可收起（防旧计时器误关新条）
var _confirm_seq := 0    # 批次 Z（Z6-P1-5/P2-9）：push_confirm 每次自增——confirm 句柄序号，
                         # active_confirm_seq() 活动期读出，面板 _exit_tree 据此只收自家确认
var _queued_info: Array = []   # Z6-P2-10：confirm 期排队的最新 info [text, seconds]（收起补播）
var _fade_tween: Tween = null

func _ready() -> void:
	_build()
	_apply_geometry()
	_refresh_theme()
	# 批次 AB-3：theme_changed 订阅随深浅主题机制删除退役（_refresh_theme 挂载直挂，恒深档）。
	# 批次 V（审查①P2-4，spec §3.2/§8）：跨态收起订阅（_exit_tree 显式退订，J6 信号卫生同款）
	if not Game.state_changed.is_connected(_on_game_state_changed):
		Game.state_changed.connect(_on_game_state_changed)
	# 批次 AA 终审回修2（aarev P1-2）：覆盖层开合 → per-state 偏移重算——open_overlay/close_overlay
	# 只发 overlay_changed 不发 state_changed（game.gd :238/:261），旧口径仅 _show 内调
	# _apply_state_offset → 「进店前已存在的条」停在旧偏移（MAIN_MENU 70/LEVEL 6），与商店顶排
	# 三件（y∈[16,90]）实叠（窗口走查实测 169.5×20 与 105.5×18 两处）。本订阅使条在店开合当帧
	# 单点重算（SHOP 96 / 关店回落），W8-3 只覆盖「条在 SHOP 态内新推」半场景的缺口闭合。
	if not Game.overlay_changed.is_connected(_on_overlay_changed):
		Game.overlay_changed.connect(_on_overlay_changed)
	# I18n：语言切换 → 按钮文案实时重刷（_exit_tree 显式退订，J6 信号卫生同款）。
	if not I18n.language_changed.is_connected(_on_language_changed):
		I18n.language_changed.connect(_on_language_changed)
	# 批次 Y（Y-A1，spec §2/§5 规则 6）：视口尺寸变化重推导订阅——弹条在场时改窗口尺寸
	#（expand 拉伸下可视矩形变化）须重算钳制域与对称 offsets（探针 p4/p7 实证旧码无此入口）；
	# _exit_tree 显式退订（J6 信号卫生同款）。
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_refit_width):
		vp.size_changed.connect(_refit_width)
	visible = false

func _build() -> void:
	name = "TopStrip"
	set_meta("ui_material", "panel")   # UILightLinker 面板档识别挂点（spec §3.1/ui_light_linker.gd:44）
	custom_minimum_size = Vector2(MIN_WIDTH, 0)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", int(ROW_SEPARATION))
	add_child(row)
	_msg_label = Label.new()
	_msg_label.name = "MsgLabel"
	_msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# NG-2：autowrap Label 最小宽 0 会被按钮行挤至 ≈60px 一字一行（w08 实证）；240 保底
	# （confirm 下根最小宽=240+按钮行 234+sep 10+边距 26=510，视口内；info 下条 min 320 内无感）
	_msg_label.custom_minimum_size = Vector2(CONFIRM_MSG_MIN_W, 0.0)
	_msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_msg_label)
	_btn_row = HBoxContainer.new()
	_btn_row.name = "BtnRow"
	_btn_row.add_theme_constant_override("separation", 8)
	row.add_child(_btn_row)
	# I18n：确认/取消按钮文案经 t()（× 为符号不翻译）；常驻件订阅 language_changed 实时重刷
	#（切换语言时挂起确认条按钮同步换文案；消息文本由调用方触发点取值，不回溯改写）。
	_ok_btn = _make_button("OkButton", I18n.t("确认"), _btn_row)
	_cancel_btn = _make_button("CancelButton", I18n.t("取消"), _btn_row)
	# 批次 W（N1）：× 移到条标题行常显——旧件藏于 info 模式隐藏的 BtnRow 内（用户截图不可见
	# 不可点）；现挂 Row 尾位（confirm 下为最右「右上 ×」语义；info 下随 MsgLabel 右侧常显），
	# 点击仅收条零副作用（与取消等价语义不变，test_v_top_strip 段 A5 回归承接）。
	# × 取紧凑档：全尺寸按钮（主题最小高 53）会把 info 条行高 30→53、条高 50→73，P1-5 贴边
	# （offset 6）时条底越过 TargetView 顶 64 破坏零相交硬断言（W3 实测）。custom_minimum_size
	# 只是下限不缩引擎内建最小高（W3 探针实证 close.min=(52,44)）——须小 margins 样式盒真降：
	# 字号 16+margin 4 → min 高 ≈30，行高回落 30 → info 条高 50 与旧况一致；confirm 行高仍由
	# 确认/取消钮 53 主导不变。样式=浅玻璃小圆角（W7 走查定档）。
	_close_btn = _make_button("CloseButton", "×", row)
	_close_btn.add_theme_font_size_override("font_size", 16)
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(1, 1, 1, 0.08)
	csb.set_corner_radius_all(6)
	csb.set_content_margin_all(4.0)
	for st: String in ["normal", "hover", "pressed"]:
		_close_btn.add_theme_stylebox_override(st, csb)
	_ok_btn.pressed.connect(_on_ok_pressed)
	_cancel_btn.pressed.connect(_on_cancel_pressed)
	_close_btn.pressed.connect(_on_cancel_pressed)   # × 与「取消」等价（spec §3.1）

func _make_button(bname: String, text: String, parent: Container) -> Button:
	var b := Button.new()
	b.name = bname
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	# NG-2：按钮垂直 SHRINK_CENTER——默认 FILL 会随 autowrap MsgLabel 的膨胀最小高被纵向拉伸
	# 成 ≈330px 高块（w08 实证）；SHRINK_CENTER 后钮高=自身最小高（主题 Button 档 53px）居中。
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.set_meta("hover_glow", true)   # hover_glow 体系显式兜底挂点（§12-4；Button 本身已命中判定）
	parent.add_child(b)
	return b

func _apply_geometry() -> void:
	# 坑 3：set_anchors_preset 反算 offsets 残留 → 锚点/偏移全量直接赋值（toast_center 中央盒同款）
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = 0.0
	offset_right = 0.0
	offset_top = TOP_OFFSET
	offset_bottom = TOP_OFFSET
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_END
	resized.connect(_refit_width)

## 批次 Y（Y-A1，spec §2）：水平几何**无状态恒对称重推导**单漏斗——
## target_w=clamp(内容所需宽, MIN_WIDTH, 视口宽−2×MARGIN)，**恒写对称 offsets（∓target/2）**
## 与 custom_minimum_size（二者恒一致）。居中不再依赖历史状态：
## 旧实现探针定谳（AI工作记录/批次Y_走查_20260922/y3_probe_topstrip_定谳.md）——
## ①custom_min 被 clampf 收到 ==max_w，旧 _clamp_width 的 `>` 比较对溢出场景恒 false=死代码，
##   offsets 实际全由 grow-BOTH 布局展开一次性反算写入；②min 回缩后不重算 → 全宽残留条；
##   ③残留态 reset_size 以旧 position 反算 offsets → 非对称 → 条贴左（center_err=-402 实测）。
## 等值收敛守卫防 resized 往返抖动（原 _clamped 标志位职责等价替换，赋同值零副作用）。
func _refit_width() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var max_w := vp.get_visible_rect().size.x - MARGIN * 2.0
	if max_w <= 0.0:
		return
	var target_w := clampf(_content_inner_w(), MIN_WIDTH, max_w)
	custom_minimum_size = Vector2(target_w, custom_minimum_size.y)
	var new_left := -target_w * 0.5
	var new_right := target_w * 0.5
	if is_equal_approx(offset_left, new_left) and is_equal_approx(offset_right, new_right):
		return   # 已收敛（防 resized 链往返重算抖动）
	offset_left = new_left
	offset_right = new_right

## 内容所需宽（主题字体单行实测+×钮/按钮行/边距，_apply_content_width 旧 inner 计算原样迁入）
func _content_inner_w() -> float:
	var text_w := 0.0
	var font: Font = _msg_label.get_theme_font("font")
	if font != null:
		text_w = font.get_string_size(_msg_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			_msg_label.get_theme_font_size("font_size")).x
	var inner := text_w
	# 批次 W（N1）：× 移至标题行常显——CloseButton 最小宽恒计入；BtnRow 仅 confirm（visible）计入
	if _close_btn != null:
		inner += _close_btn.get_combined_minimum_size().x + ROW_SEPARATION
	if _btn_row.visible:
		inner += _btn_row.get_combined_minimum_size().x + ROW_SEPARATION
	var sb: StyleBox = get_theme_stylebox("panel")
	if sb != null:
		inner += sb.get_content_margin(SIDE_LEFT) + sb.get_content_margin(SIDE_RIGHT)
	return inner

# ---------- 契约 API ----------

## info 模式：文本 + seconds 后自动消失（默认 3.0，spec §3.1 跨批契约），无按钮。
func push_info(text: String, seconds: float = INFO_SECONDS_DEFAULT) -> void:
	if _mode == "confirm":
		# 批次 Z（Z6-P2-10，spec §6）：confirm 活动期新 info 不再静默丢弃——改入单槽队列
		#（只留最新一条，后到覆盖），confirm 收起（确认/取消/×/跨态/dismiss 全路径经
		# _collapse）后立即补播。confirm 期间的文案显示零扰动（单槽 confirm 优先显示语义
		# 保持，test_v_top_strip A7 断言零变化）。
		_queued_info = [text, seconds]
		return
	_btn_row.visible = false   # 批次 W（N2 时序修正）：先定按钮行可见性再 _show——reset_size 在
	                           # _show 内取最小尺寸，旧序（先 _show 后隐藏）会把含钮 min 高固化
	_show(text)
	_mode = "info"
	_apply_content_width()
	_info_seq += 1
	var seq := _info_seq   # lambda 按值捕获（坑 8）：旧计时器醒来时 seq 已过期即 no-op
	if is_inside_tree() and seconds >= 0.0:
		get_tree().create_timer(seconds).timeout.connect(func() -> void:
			if seq == _info_seq and _mode == "info" and visible:
				_collapse())

## confirm 模式：常驻直至用户选择；确认→on_confirmed 并收起；取消或 ×→on_canceled
##（空回调静默收起）。批次 W（P2-7，规格 §5；**推翻批次 V spec §3.1「新 confirm 到来替换
## 旧 confirm（旧回调不执行）」顶替语义**）：新 confirm 顶替前快照旧 _cancel_cb 补调恰一次
## ——存量 cancel 均为「恢复挂起状态」语义（level_scene._pending_exit_state 等），补调即统一
## 闭环不泄漏。幂等守卫（先清槽再调）：old 回调链内的同帧重入（push_confirm/
## dismiss_active_confirm/_on_game_state_changed）不会双重补调——槽已清，重入读到空 Callable。
func push_confirm(text: String, on_confirmed: Callable = Callable(),
		on_canceled: Callable = Callable()) -> void:
	_info_seq += 1   # 顶掉 info 活动期挂着的计时器（confirm 优先）
	_confirm_seq += 1   # 批次 Z（Z6-P1-5/P2-9）：句柄序号自增（active_confirm_seq 消费）
	var old_cancel := _cancel_cb
	_cancel_cb = Callable()   # 先清槽（幂等守卫）
	if old_cancel.is_valid():
		old_cancel.call()
	_ok_cb = on_confirmed
	_cancel_cb = on_canceled
	_btn_row.visible = true   # 批次 W（N2 时序修正）：与 push_info 同序——先定可见性再 _show
	_show(text)
	_mode = "confirm"
	_apply_content_width()

## 批次 Z（Z6-P1-5/P2-9，spec §6）：confirm 句柄序号读口——confirm 活动期返回当前
## _confirm_seq，否则 -1。Game.get_active_confirm_seq 转发；settings/shop 面板 _exit_tree
## 比对「push 时记下的自有序号」决定是否 dismiss（误杀他源确认/僵尸条两向根除）。
func active_confirm_seq() -> int:
	return _confirm_seq if _mode == "confirm" else -1

## NG-2：条宽按内容自适应——目标宽=文案所需宽（主题字体单行实测）+按钮行最小宽（仅 confirm，
## info 模式 BtnRow 隐藏不参与），与 MIN_WIDTH 取大、视口宽−2×MARGIN 取小（_refit_width 同口径，
## 超宽仍 autowrap 折行）；MsgLabel 另有 CONFIRM_MSG_MIN_W 保底，短文案 confirm 由子件最小宽
## 自然托底。批次 Y（Y-A1）：实现收敛到 _refit_width 单漏斗（恒对称 offsets，无状态重推导）。
func _apply_content_width() -> void:
	_refit_width()

## 批次 V 回修② P2-2：外部收口入口——覆盖层/面板关闭时挂起 confirm 残留清理。仅 confirm
## 模式生效：on_canceled 回调执行+按取消收起（复用 _on_cancel_pressed 同一语义路径：零副作用=
## 不调 on_confirmed，空回调静默收起）；info 不动（自有计时自灭，_mode 判据天然分流）；防重入：
## 首次收起后 _collapse 已把 _mode 复位 ""，同帧重复调用/嵌套重入 no-op；若 on_canceled 内
## 重入再推新 confirm，本调用不二次收起（与跨态收起 _on_game_state_changed 同款守卫口径）。
func dismiss_active_confirm() -> void:
	if _mode != "confirm":
		return
	_on_cancel_pressed()

# ---------- 内部 ----------

func _show(text: String) -> void:
	_refresh_theme()   # 惰性兜底：挂载早于 autoload 主题就绪（--script 时序）时随首次 push 补挂
	_msg_label.text = text
	visible = true
	_apply_state_offset()   # 批次 W（P1-5，拍板 2）：push 时查 Game 当前态——LEVEL 贴边 6 / 其它 70
	_refit_width()   # 批次 Y（Y-A1）：水平几何无状态重推导（恒对称 offsets，贴左根因修复）
	if is_inside_tree():
		_play_slide_in()   # 批次 W（N2）：自目标位上方滑入 0.25s + 淡入（坑⑧：直接 tween position）

## 批次 W（P1-5）：per-state 顶部偏移——LEVEL 态 offset_top=LEVEL_TOP_OFFSET(6)，其它态维持
## TOP_OFFSET(70)。直接赋 offset_top/offset_bottom 不走 set_anchors_preset（坑⑧）；水平居中
## 锚点链不动。confirm 同口径（拍板 2：允许短暂覆盖顶栏标签，confirm 本就是退出确认）。
## 批次 AA（W8-3，spec §11.4-2）：per-state 偏移表加 **SHOP 支**（96）——商店覆盖层开时条顶下移
## 至顶排三件底 90 之下；优先级高于 LEVEL（SHOP 覆盖层可叠在任一状态上，同 gesture_hud
## 「sho 分支优先于 match」的键分流口径）。
func _apply_state_offset() -> void:
	var off := TOP_OFFSET
	var game: Node = get_node_or_null("/root/Game")
	# 动态取枚举（test_v_hud_gate 同款实例枚举访问；get_node_or_null 防 --script 降级）
	if game != null and game.has_method("is_shop_open") and bool(game.call("is_shop_open")):
		off = SHOP_TOP_OFFSET
	elif game != null and int(game.call("current_state")) == int(game.State.LEVEL):
		off = LEVEL_TOP_OFFSET
	offset_top = off
	offset_bottom = off

## 批次 W（N2）：入场动效——起点=目标位上方（条高+14），0.25s 滑入至目标位 + modulate 0→1
## 淡入。直接 tween position:y（终态=锚定+offsets 现状位，锚点零污染；坑⑧ 不涉 set_anchors_preset）。
## reset_size 根除陈旧尺寸：min 缩小后 Control 不自动回缩（W3 探针实证 size 73 > min 64 残留），
## 终态尺寸=当前内容最小尺寸；tween 终值直接取 offset_top（anchor_top=0 → position.y==offset_top，
## 不读布局防未排序零值）。confirm 同口径（拍板 2：允许短暂覆盖顶栏标签）。
func _play_slide_in() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	reset_size()
	# 批次 Y（Y-A1）：reset_size 保持旧 position 反算全部 offsets（坑⑧同源）——残留态下会写出
	# 非对称 offsets（探针 p7 实证贴左根因），重推导单漏斗补一次对称复位；y 偏移随之重取。
	_apply_state_offset()
	_refit_width()
	var final_y := offset_top
	position.y = final_y - (size.y + SLIDE_GAP)
	modulate.a = 0.0
	_fade_tween = create_tween()
	_fade_tween.set_parallel(true)
	_fade_tween.tween_property(self, "position:y", final_y, SLIDE_TIME)
	_fade_tween.tween_property(self, "modulate:a", 1.0, SLIDE_TIME)

func _collapse() -> void:
	visible = false
	_mode = ""
	_ok_cb = Callable()     # 回调复位：防陈旧引用持有（P1-1 取消回调复位口径同源）
	_cancel_cb = Callable()
	# 批次 Z（Z6-P2-10）：confirm 收起后补播排队 info（先清槽再入队；push_info 判
	# _mode=="confirm" 已假 → 递归恒单层，队列已空不会连环）。
	if not _queued_info.is_empty():
		var q: Array = _queued_info
		_queued_info = []
		push_info(String(q[0]), float(q[1]))

func _on_ok_pressed() -> void:
	var cb := _ok_cb
	_collapse()
	confirmed.emit()
	if cb.is_valid():       # 坑 1：空回调判空（Callable() 缺省=静默收起零副作用）
		cb.call()

func _on_cancel_pressed() -> void:
	var cb := _cancel_cb
	_collapse()
	canceled.emit()
	if cb.is_valid():
		cb.call()

## 批次 V（审查①P2-4，spec §3.2/§8）：跨态收起——场景切换（Game.state_changed）时 confirm
## 常驻条自动按取消收起：on_canceled 回调执行（零副作用=不调 on_confirmed）+条收起，防 confirm
## 条跨场景残留；info 不受影响（自有计时自灭，_mode 判据天然分流）。防重入：首次收起后
## _collapse 已把 _mode 复位 ""，同帧重复 state_changed（场景切换瞬间重复触发/嵌套 emit）只
## 生效一次；若 on_canceled 内重入再推新 confirm，后续真实场景切换仍按同一语义收起。
func _on_game_state_changed(_from_state: int, _to_state: int) -> void:
	# 修复批 P2（2026-09-26）：存活 info 也按新状态重算 per-state 偏移——info 不跨态收起
	#（自有计时自灭，既有语义），但 offset 若停在旧态值（LEVEL 6 / SHOP 96）会压新态的
	# 窗口三钮/顶排三件（弹条层 63 吞点击）。复用 _apply_state_offset 单漏斗；confirm 路径
	# 随后收起，先重算对隐藏条为无害空转。
	_apply_state_offset()
	if _mode != "confirm":
		return
	_on_cancel_pressed()

## 批次 AA 终审回修2（aarev P1-2）：覆盖层开合当帧重算 per-state 偏移（info/confirm 两模式
## 都重算——confirm 常驻条进店同样要避开顶排三件）。直接调 _apply_state_offset 单漏斗，
## 不改 state 语义、不触碰 _mode/_collapse 链；关店（overlay_changed(false)）自然回落。
func _on_overlay_changed(_opened: bool) -> void:
	_apply_state_offset()

## J6 信号卫生硬化（跨态收起订阅随本批新增，同款退订）：防场景释放后 freed 实例回调。
## 批次 Y（Y-A1）：视口 size_changed 重推导订阅同步退订。
## I18n：语言切换重刷落点（确认/取消两钮；挂起条与 info 消息不回溯）。
func _on_language_changed(_lang: String) -> void:
	_ok_btn.text = I18n.t("确认")
	_cancel_btn.text = I18n.t("取消")

func _exit_tree() -> void:
	if I18n.language_changed.is_connected(_on_language_changed):
		I18n.language_changed.disconnect(_on_language_changed)
	if Game.state_changed.is_connected(_on_game_state_changed):
		Game.state_changed.disconnect(_on_game_state_changed)
	# 批次 AA 终审回修2：overlay_changed 订阅同步退订（J6 信号卫生同款）。
	if Game.overlay_changed.is_connected(_on_overlay_changed):
		Game.overlay_changed.disconnect(_on_overlay_changed)
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_refit_width):
		vp.size_changed.disconnect(_refit_width)

func _refresh_theme() -> void:
	var t: Theme = ThemeManager.current_theme()   # CanvasLayer 层界显式注入（坑 6，main.gd:54 同款）
	if t != null:
		theme = t
	_apply_glass()

func _apply_glass() -> void:
	# GlassDialog L3 弹窗档同族（glass_dialog.gd:_apply_glass 同款档值，spec §3.1；批次 AB-3 恒深档）
	var sb := StyleBoxFlat.new()
	sb.bg_color = DARK_BG
	sb.set_corner_radius_all(14)
	sb.border_width_top = 2
	sb.border_width_left = 1; sb.border_width_right = 1; sb.border_width_bottom = 1
	sb.border_color = DARK_BORDER
	sb.shadow_color = Color(0, 0, 0, 0.45); sb.shadow_size = 16; sb.shadow_offset = Vector2(3, 5)
	sb.content_margin_left = 16.0; sb.content_margin_right = 10.0
	sb.content_margin_top = 10.0; sb.content_margin_bottom = 10.0
	add_theme_stylebox_override("panel", sb)
	if _msg_label != null:
		_msg_label.add_theme_color_override("font_color", DARK_FONT)
