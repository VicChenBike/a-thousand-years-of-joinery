extends PanelContainer
## 批次 X P4（spec §5，20260921）：锐眼时长选择自绘面板——PopupMenu（独立 Window 子视口）替换件。
##
## 根因（无头探针实证，AI工作记录/批次X_走查_20260921/p4_popupmenu_probe_run1.log）：
## gesture_router._hovered_ui_interactive 只看主视口 gui_get_hovered_control() 祖先链——
## PopupMenu 系 Window 子视口内容在主视口 hover 判定恒不可见（探针 [3] hovered=null/链无
## BaseButton）→ armed 永不置位 → 手势零点击；主视口普通 Button 对照组 hover/合成单击全通
##（探针 [1][2]）。
##
## 改法（拍板）：主视口内 PanelContainer+按钮列——手势命中=主视口 Button 祖先链（无需注册），
## 键鼠同链天然可用。主题经树传播继承关卡主题；按钮=Button（生产侧 UILightLinker node_added
## 自动挂批次 W 光影材质；hover_glow meta 显式兜底=camera_menu 行同款）。
##
## 关闭路径三态：①点选任一项 → duration_selected（点选即收，走 level_scene
## _on_eye_duration_selected 同源扣费链）；②Esc——_unhandled_input 逆树序派发，本面板系
## 运行期尾挂子节点先于 level_scene 根到达，面板在场时 Esc 先消费于关面板，不落 level_scene
## _unhandled_input 的 Esc=清选分支；③点面板外——_input 阶段消费外点（模态语义，PopupMenu
## 点外关闭同款），并吞同次抬起防穿透 3D 视图/其他控件。
##
## 键盘可达：开启即聚焦缺省档（PopupMenu set_focused_item 等价），↑↓ 移焦、Enter 点选。

signal duration_selected(idx: int)

var _buttons: Array[Button] = []
var _default_idx := 0
var _swallow_next_release := false   # 点外关闭后吞同次抬起（防释放穿透 3D 视图/其他控件）

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP   # 面板体点击不穿透不关闭（PopupMenu 面板体同款）

## 构建菜单项（幂等重建：每次开启重算文案/聚焦；即释放防同帧新旧混列）。
## durations=时长档数组、default_idx=缺省聚焦档、label_of(i)=项文案（含扣费数值，调用方同源）。
func build(durations: Array, default_idx: int, label_of: Callable) -> void:
	for c: Node in get_children():
		c.free()
	_buttons.clear()
	var box := VBoxContainer.new()
	box.name = "Items"
	add_child(box)
	for i: int in durations.size():
		var b := Button.new()
		b.text = String(label_of.call(i))
		b.add_theme_font_size_override("font_size", 16)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.set_meta("hover_glow", true)   # UILightLinker hover_glow 显式兜底（camera_menu 行同款）
		var idx := i
		b.pressed.connect(func() -> void: duration_selected.emit(idx))
		box.add_child(b)
		_buttons.append(b)
	_default_idx = clampi(default_idx, 0, _buttons.size() - 1) if not _buttons.is_empty() else 0

## 锚=eye_btn 全局矩形左下（正下方拍板口径）；reset_size=PanelContainer 收敛到子树最小尺寸
##（自锚点向下扩展，不遮 TopBar）。开启即聚焦缺省档。
func open_at(anchor: Vector2) -> void:
	global_position = anchor
	_swallow_next_release = false
	reset_size()
	show()
	if not _buttons.is_empty():
		_buttons[_default_idx].grab_focus()

func close() -> void:
	hide()

func _input(event: InputEvent) -> void:
	## 点外关闭（模态）：任一鼠标按下落于面板矩形外 → 关闭并消费+吞同次抬起。
	## armed 合成点击在面板内（菜单项）不拦截——本处先于 GUI 到达，仅借道判定不消费。
	## 事件位取 make_input_local（合成事件无先导 motion 时 get_global_mouse_position 会读到
	## 陈旧内部位——B4 点外注入路径实证口径）。
	if not visible:
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if not mb.pressed:
		if _swallow_next_release:
			_swallow_next_release = false
			get_viewport().set_input_as_handled()
		return
	var local_ev := make_input_local(mb)
	if Rect2(Vector2.ZERO, size).has_point(local_ev.position):   # 零基准本地矩形（get_rect() 系父系含偏移，勿用）
		return
	close()
	_swallow_next_release = true
	get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	## Esc 先消费于关面板（面板在场时）：_unhandled_input 逆树序派发——本面板先于 level_scene
	## 根到达，set_input_as_handled 后 level 的 Esc=清选分支不可达（spec §5 Esc 优先级定档）。
	if not visible:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
