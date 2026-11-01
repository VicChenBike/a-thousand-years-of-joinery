class_name GlassDialog
extends Control
## K-C（K4-1）：通用毛玻璃确认弹窗（替代默认 Window/ConfirmationDialog）。L3（spec §3.3）：
## bg 深 Color(0.30,0.22,0.09,0.72)/浅 Color(0.99,0.92,0.72,0.75)，圆角 14/顶缘高光 2px/shadow 16（弹窗档）；关闭不 queue_free 可复用。
## 跨批契约（plan KC-1 定稿）：signal confirmed/canceled；setup/open_centered/close/set_body；
## 仅确认钮发 confirmed；遮罩/Esc/取消钮发 canceled；全屏遮罩 STOP 锁下层输入。
## K-D 商店 ConfirmDialog / K-G 关卡退出弹窗 / 主菜单新游戏+退出均复用本组件。
signal confirmed; signal canceled
# 批次 W（P3-1）：色彩单源表（值不变）。
const Palette := preload("res://scripts/palette.gd")
@onready var _dim: ColorRect = $Dim; @onready var _card: PanelContainer = $Card
@onready var _ok_btn: Button = $Card/VBox/ButtonRow/OkButton; @onready var _cancel_btn: Button = $Card/VBox/ButtonRow/CancelButton
func _ready() -> void:
	visible = false; _dim.gui_input.connect(_on_dim_gui_input)
	_ok_btn.pressed.connect(func() -> void:
		close(); confirmed.emit())
	_cancel_btn.pressed.connect(func() -> void:
		close(); canceled.emit())
	_apply_glass()
	# 批次 AB-3：theme_changed 订阅随深浅主题机制删除退役（玻璃样式挂载直挂，恒深档）。

func _apply_glass() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.30, 0.22, 0.09, 0.72)
	sb.set_corner_radius_all(14); sb.border_width_top = 2
	sb.border_width_left = 1; sb.border_width_right = 1; sb.border_width_bottom = 1
	sb.border_color = Color(Palette.STROKE_GOLD, 0.45)   # P3-1：描边金单源（值不变；AB-3 恒深档）
	sb.shadow_color = Color(0, 0, 0, 0.45); sb.shadow_size = 16; sb.shadow_offset = Vector2(3, 5)
	sb.set_content_margin_all(20.0)
	_card.add_theme_stylebox_override("panel", sb)
	var title := _card.get_node("VBox/Title") as Label
	title.add_theme_font_override("font", load("res://fonts/MaShanZheng-Regular.ttf")); title.add_theme_font_size_override("font_size", 24)
func setup(title: String, body: String, ok_text: String = "确认",
		cancel_text: String = "取消", show_cancel: bool = true) -> void:
	(_card.get_node("VBox/Title") as Label).text = title
	set_body(body)
	# I18n：按钮文案经 t()（调用方传入 zh 原文键 → en 命中词条；自定义文案未命中回退原文）。
	_ok_btn.text = I18n.t(ok_text); _cancel_btn.text = I18n.t(cancel_text); _cancel_btn.visible = show_cancel
func set_body(body: String) -> void:
	(_card.get_node("VBox/Body") as Label).text = body
func open_centered() -> void:
	visible = true
	_play_slide_in()   # 批次 W（N2）：自上方滑入入场（终态=锚定居中现状位）

## 批次 W（N2）：入场动效——Card 起点=目标位上方（卡高+14），0.25s 滑入 + modulate 淡入；
## 直接 tween position（Card 为普通 Control 子件无容器布局覆写；坑⑧ 不涉 set_anchors_preset）；
## 终值=开窗瞬间锚定派生位 → 「终态位置与现状一致」。close() 无退场动效（规格只约入场）。
func _play_slide_in() -> void:
	if _card_tween != null and _card_tween.is_valid():
		_card_tween.kill()
	var final_y := _card.position.y
	var h := maxf(_card.size.y, _card.get_combined_minimum_size().y)
	_card.position.y = final_y - (h + 14.0)
	_card.modulate.a = 0.0
	_card_tween = _card.create_tween()
	_card_tween.set_parallel(true)
	_card_tween.tween_property(_card, "position:y", final_y, 0.25)
	_card_tween.tween_property(_card, "modulate:a", 1.0, 0.25)

var _card_tween: Tween = null

func close() -> void: visible = false
func _on_dim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		close(); canceled.emit()
func _unhandled_input(event: InputEvent) -> void:
	if not visible: return
	if event.is_action_pressed("ui_cancel"):
		close(); canceled.emit()
		get_viewport().set_input_as_handled()

## 批次 AB-3：theme_changed 断开随深浅主题机制删除退役。
