class_name GestureCursorLayer
extends CanvasLayer
## 批次 R：光标 A/B 光圈层 + 合成事件工厂（spec §2.4 组件表/§4.2 合成事件坐标口径行）。
## 合成 InputEventMouse* 一律 content 坐标；push() 以 push_input(ev, true) 注入既有 gui_input
## 管线（hover/点选/划选/STROKE_DESELECT/ORBIT/滚轮全部自然复用）。
## 2 秒无任何该手光标事件自动隐藏对应光圈，再次移动即恢复（§4.2 光标隐藏行，A/B 独立计时）。
## 纯视觉层：mouse_filter=IGNORE，不拦截任何输入；layer=101 顶层显示（批次 Z Z6-P3-4：
## 旧 100 与 GlowLayer(100) 同 index → Godot 文档同 index 前后序 non-deterministic，上移
## 101 消歧、恒压光斑层；toast 属 GlobalUI=1，「toast 出现时短暂盖过控制台可接受」同理对光标成立）。

# 批次 W（P3-1）：色彩单源表（值不变）。
const Palette := preload("res://scripts/palette.gd")
const HIDE_AFTER_SEC := 2.0
# 批次 Z（Z6-P2-2，spec §6）：手势合成事件标记键——synth_* 工厂产出的 InputEvent 一律挂此
# meta，消费方（scenes/main.gd 拖窗分支）据此显式跳过：手势合成按下+动移不再触发
# _win_dragging（「手势点击+另一手动鼠标 → 窗口跳位」根除；真实键鼠事件无此标记零变化）。
const SYNTH_META := "gesture_synth"
const COLOR_A := Palette.CURSOR_BLUE   # 光标 A 蓝（P3-1 单源，值不变；N15 后语义独立不并骨架蓝）
const COLOR_B := Palette.CURSOR_RED   # 光标 B 红（P3-1 单源，值不变）
const RING_RADIUS := 16.0

class Ring extends Control:
	## 自绘光圈：外环 + 中心点（内嵌类不引外层常量，色/径经成员注入）
	var ring_color := Color.WHITE
	var ring_radius := 16.0

	func _draw() -> void:
		draw_arc(Vector2(ring_radius, ring_radius), ring_radius, 0.0, TAU, 40, ring_color, 3.0, true)
		draw_circle(Vector2(ring_radius, ring_radius), 3.0, ring_color)

var _rings := {}            # side → Ring
var _last_event_at := {}    # side → float（秒）
var _last_pos := {}         # S12：side → 最近可见光圈中心（content 坐标，get_pointer_pos 消费）

func _ready() -> void:
	layer = 101   # Z6-P3-4：> GlowLayer(100) 消同 index 序 non-determinism（头注）
	for side: String in ["left", "right"]:
		var ring: Ring = Ring.new()
		ring.ring_color = COLOR_A if side == "left" else COLOR_B
		ring.ring_radius = RING_RADIUS
		ring.custom_minimum_size = Vector2(RING_RADIUS * 2.0, RING_RADIUS * 2.0)
		ring.size = Vector2(RING_RADIUS * 2.0, RING_RADIUS * 2.0)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.visible = false
		add_child(ring)
		_rings[side] = ring
		_last_event_at[side] = -1000.0

## 显示/移动某手光圈（content 坐标）。每次调用刷新该手 2s 隐藏计时。
func show_cursor(side: String, content_pos: Vector2) -> void:
	var ring: Ring = _rings.get(side)
	if ring == null:
		return
	ring.visible = true
	ring.position = content_pos - Vector2(ring.ring_radius, ring.ring_radius)
	_last_pos[side] = content_pos   # S12：记录最近可见光圈中心（get_pointer_pos 消费）
	_last_event_at[side] = Time.get_ticks_msec() / 1000.0

func hide_cursor(side: String) -> void:
	var ring: Ring = _rings.get(side)
	if ring != null:
		ring.visible = false

## 批次 W（N15，拍板 10）：ORBIT 光标染色 API（set_ring_color/reset_ring_color）随琥珀环删除
## 整体退役——光标环恒左蓝右红（COLOR_A/COLOR_B _ready 初始化后永不再改，零动态染色路径）。

## S12（批次 S spec §3-12/§5.4）：最近更新的可见光圈中心（content 坐标）；全部不可见 → null。
## main.gd 光斑 u_mouse_px 数据源消费（键鼠路径不受影响：null → 真实鼠标原路径）。
## 同帧双侧更新平局裁决：>= 比较 + ["left","right"] 迭代序 → 后迭代侧（right）胜出（测试段 14 固化）。
func get_pointer_pos() -> Variant:
	var best_side := ""
	var best_at := -1.0e9
	for side: String in ["left", "right"]:
		var ring: Ring = _rings.get(side)
		if ring != null and ring.visible and _last_pos.has(side) \
				and float(_last_event_at[side]) >= best_at:
			best_at = float(_last_event_at[side])
			best_side = side
	if best_side == "":
		return null
	return _last_pos[best_side]

func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for side: String in _rings.keys():
		var ring: Ring = _rings[side]
		if ring.visible and now - float(_last_event_at[side]) > HIDE_AFTER_SEC:
			ring.visible = false

# ---------- 合成事件工厂（content 坐标，全工程唯一口径 spec §4.2） ----------

func synth_motion(content_pos: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = content_pos
	ev.global_position = content_pos
	ev.set_meta(SYNTH_META, true)   # Z6-P2-2：合成事件标记（main 拖窗分支跳过）
	return ev

## 左键按下/抬起（ctrl=true 用于右手取消模式复用批次 Q STROKE_DESELECT，§5.4）
func synth_button(content_pos: Vector2, pressed: bool, ctrl: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.ctrl_pressed = ctrl
	ev.position = content_pos
	ev.global_position = content_pos
	ev.set_meta(SYNTH_META, true)   # Z6-P2-2：合成事件标记（main 拖窗分支跳过）
	return ev

## 滚轮步进（dir=+1 → WHEEL_UP 推近放大 / -1 → WHEEL_DOWN，§5.3 注 3）
func synth_wheel(content_pos: Vector2, dir: int) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if dir > 0 else MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	ev.position = content_pos
	ev.global_position = content_pos
	ev.set_meta(SYNTH_META, true)   # Z6-P2-2：合成事件标记（main 拖窗分支跳过）
	return ev

## 注入既有管线：in_local_coords=true = content 坐标（spec §4.2 终态，禁止混用像素坐标）
func push(ev: InputEvent) -> void:
	var vp := get_viewport()
	if vp != null:
		vp.push_input(ev, true)
