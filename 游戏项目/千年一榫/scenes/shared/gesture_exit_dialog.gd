extends Control
## 手势退出倒数弹条（批次 R 新建；批次 Y Y-A2 重形态，spec §2-②拍板）：屏幕正中卡片退役，
## 改**顶部居中长条**（视觉复用 TopStrip 样式语言：同主题注入/玻璃弹窗档圆角 14/描边金/
## 主题字体；独立节点不占 TopStrip 单槽）。玻璃弹条由 main.gd 挂 GlobalUI 并订阅 GestureRouter
## 倒数信号（信号合同不变：show_countdown/update_countdown/close_countdown 三方法名保留）。
## 旧全屏 Dim 遮罩随卡片形态退役（TopStrip 同款无遮罩、mouse_filter=IGNORE 不锁下层）。

@onready var _card: PanelContainer = $Card

const Palette := preload("res://scripts/palette.gd")
# 批次 Z（Z5-6，spec §5-6 拍板）：几何与「对接失败条」（TopStrip）**完全一致**——常量单源
# 直取 TopStrip（关卡内贴顶栏 LEVEL_TOP_OFFSET=6 / 其它态 TOP_OFFSET=70，水平居中锚点同款），
# 不再本地镜像数值（镜像漂移由 test_z_gesture_thresholds 段 4 运行时等值断言锁）。
const Strip := preload("res://scenes/shared/top_strip.gd")
const TOP_OFFSET := Strip.TOP_OFFSET              # 非关卡态顶部偏移（=TopStrip 对接失败条同值）
const LEVEL_TOP_OFFSET := Strip.LEVEL_TOP_OFFSET  # 关卡内贴顶栏（=TopStrip 对接失败条同值 6）
const MIN_WIDTH := 320.0   # TopStrip 同款条最小宽

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_glass()

func _apply_glass() -> void:
	## TopStrip._apply_glass 同款 StyleBox 值（GlassDialog L3 弹窗档：圆角14/顶缘高光2/shadow16/
	## content margins 16/10/10/10——批次 Y Y-A2 与 TopStrip 视觉语言对齐；批次 AB-3 恒深档）
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.30, 0.22, 0.09, 0.72)
	sb.set_corner_radius_all(14)
	sb.border_width_top = 2
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(Palette.STROKE_GOLD, 0.45)   # P3-1：描边金单源（值不变）
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 16
	sb.shadow_offset = Vector2(3, 5)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	_card.add_theme_stylebox_override("panel", sb)
	var body := _card.get_node("VBox/Body") as Label
	# TopStrip 同款主题字体与字色（主题 FontVariation + 描边金字色；旧 MaShanZheng 标题随
	# 单行长条形态退役；批次 AB-3：恒深档金字）
	body.add_theme_color_override("font_color", Palette.STROKE_GOLD)

## 批次 Z（Z5-6）：per-state 顶部偏移——与 TopStrip._apply_state_offset 完全一致
##（LEVEL 态 offset_top=LEVEL_TOP_OFFSET(6) 贴顶栏，其它态 TOP_OFFSET(70)）。
## 直接赋 offset_top/offset_bottom 不走 set_anchors_preset（坑⑧）；水平居中锚点链不动。
func _apply_state_offset() -> void:
	var off := TOP_OFFSET
	var game: Node = get_node_or_null("/root/Game")
	if game != null and int(game.call("current_state")) == int(game.State.LEVEL):
		off = LEVEL_TOP_OFFSET
	_card.offset_top = off
	_card.offset_bottom = off

## 首显（批次 Y Y-A2：翻转 #1 当帧，Tracker 即时 emit，0.6s 延迟退役）：「还需翻转 3 次」
func show_countdown(remaining: int) -> void:
	set_body(I18n.t("还需翻转 %d 次") % remaining)
	if not visible:
		visible = true
		_play_slide_in()   # 批次 W（N2）：首显自上方滑入（刷新翻转不重播，防倒数中抖动）
	else:
		visible = true
		_apply_state_offset()   # 批次 Z（Z5-6）：刷新态同口径贴合（跨态残留偏移复位）

## 批次 W（N2）：入场动效——Card 起点=目标位上方（条高+14），0.25s 滑入 + modulate 淡入；
## 直接 tween position（Card 无容器布局覆写；坑⑧ 不涉锚点）；批次 Y（Y-A1 同族）：reset_size
## 后重申锚定偏移（顶部居中锚点 0.5/offset_top 按 Game 态取 TopStrip 同源常量），防历史状态残留偏移。
func _play_slide_in() -> void:
	if _card_tween != null and _card_tween.is_valid():
		_card_tween.kill()
	_card.reset_size()
	_apply_state_offset()   # 批次 Z（Z5-6）：TopStrip 同源 per-state 偏移（关卡内 6 / 其它 70）
	var final_y := _card.position.y
	var h := maxf(_card.size.y, _card.get_combined_minimum_size().y)
	_card.position.y = final_y - (h + 14.0)
	_card.modulate.a = 0.0
	_card_tween = _card.create_tween()
	_card_tween.set_parallel(true)
	_card_tween.tween_property(_card, "position:y", final_y, 0.25)
	_card_tween.tween_property(_card, "modulate:a", 1.0, 0.25)

var _card_tween: Tween = null

## 刷新（翻转 #2/#3，批次 Y Y-A2：当帧立即刷新且数字减 1）：「还需翻转 N 次」
func update_countdown(remaining: int) -> void:
	set_body(I18n.t("还需翻转 %d 次") % remaining)
	_apply_state_offset()   # 批次 Z（Z5-6）：刷新同步几何（与 TopStrip per-state 口径一致）

func close_countdown() -> void:
	visible = false

func set_body(body: String) -> void:
	(_card.get_node("VBox/Body") as Label).text = body

func _unhandled_input(_event: InputEvent) -> void:
	pass  # 只读不可点：不响应 Esc/点击（§6.2——取消仅经 Tracker 超时/离场自动触发）

## 批次 AB-3：theme_changed 断开随深浅主题机制删除退役。
