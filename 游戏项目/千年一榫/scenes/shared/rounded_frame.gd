extends CanvasLayer
## 批次 T（spec §4-17/§4-18）：窗口自绘外框 + 四角等比缩放热区。
## layer=128（GlobalUI=1/GlowLayer=100/光标层=100 之上）；mouse_filter：Frame=IGNORE 全穿透，
## 仅四角热区 STOP。数学委托 WindowManager（纯函数可无头测）。
##
## 批次 U-C v2（用户 2026-09-19 二次截图反馈，推翻 P0 追加口径②）：窗口即游戏内容全出血
##（main.tscn SceneContainer/GlobalUI 呼吸边距归零），本件**只画一圈沿窗缘内侧 2px 的
## FRAME_STROKE_COLOR 半透明灰描边环**——旧「呼吸带深黑包裹层＋四角扇形填充」一切带状/
## 角外填充整体废止（用户实测包裹层覆盖范围大于圆角=穿帮；旧常量概念删除，
## test_t_window_frame 源码级删除锁 grep 本文件不含任何多边形/矩形填充 API 字面名，
## 故本注释亦不落其名，同前述旧描边色常量纪律）。
## 四角透出桌面由 OS 级圆角承担：Win11=DWMWCP_ROUND 原生弧、Win10/其余=launcher
## SetWindowRgn 区域裁剪（gesture_runtime/launcher.py v2）；渲染器侧无逐像素透明
##（gl_compatibility，批次 T TA-1 spike 实证）不再补画。环圆角半径随形态：
## DWM/region 圆角信号=FRAME_RADIUS(8，对齐 Win11 原生弧)；直启备案（无信号）=0 直角贴边。
##
## spike 备案开关（TA-1 判 FAIL 时置 true 并按备案口径实施，默认 false）：
const FALLBACK_INNER := true
## ↑ v2 语义=描边环恒沿窗缘内侧 inset 2px 绘制（J5 备案「内侧装饰框」口径延续；
##   旧「呼吸带填充」分支随 v2 零填充废止，常量保留作备案概念锚）。

const FRAME_INSET := 10.0     # v2 起内容全出血不再消费（main.tscn 归零），留档常量（test 锚）
const FRAME_RADIUS := 8.0     # v2：圆角形态环半径（对齐 Win11 DWMWCP_ROUND 原生弧；旧 18 留痕）
const FRAME_STROKE := 2.0
# 窗口缩放坐标修复3（2026-09-18）：DWM 原生圆角联动形态——跨域契约：launcher.py 拉起游戏后
# 按 PID 对顶层窗口调 DwmSetWindowAttribute（33=ROUND、34=COLOR_NONE），**成功才**写标记文件
# user://dwm_round.flag（批次 U U9-4：enable 成功才落信号，launcher 侧 env 自动注入废止——
# 预检与实装竞态根除；手工预设 QNSX_DWM_ROUND=1 透传保留，main.gd env 直读即时进圆角形态）。
# main.gd 双通道消费（env 直读＋15s 标记轮询）后经 set_dwm_round 透传。
# v2（用户二次截图反馈）：enable 成功路径另追加 SetWindowRgn 圆角区域裁剪（Win10 靠 region
# 也出圆角，region/DWM 任一成功落 dwm_round.flag）→ 圆角形态两路线（Win11 属性叠加 region、
# Win10 纯 region）游戏侧统一画半径 8 圆角环与 OS 裁切弧贴合；无信号（直启 EXE 降级）→
# 备案形态：环半径 0 直角贴边（窗口本体直角，环也直角）。
# 批次 U（U9-1/U9-2/U9-3，spec §4-U9/§5）：两路线描边单源统一 70% 透明灰——旧主题深/浅双档
#（备案路线随主题）与 50% 灰双源、黄棕不透明四角填充、白高光弧一并删除（双审 P2-15 单源化；
# test_t_window_frame 源码级删除锁 grep 本文件不含旧常量字面名，故本注释亦不落旧名）。
const FRAME_STROKE_COLOR := Color(0.55, 0.55, 0.55, 0.30)

const CORNER_HOT := 18.0      # 计划裁决 J3：spec 20 与窗口钮内缩后 2px 重叠带不相容，保守取 18
const SPIN_NONE := -1         # 拖拽中角哨兵

const WM := preload("res://scripts/window_manager.gd")

var dwm_round := false   # 圆角形态开关（main.gd 读环境变量/标记轮询后经 set_dwm_round 透传；判断内聚本件）
var _decoration_force_hidden := false   # 批次 U P0 追加口径①（用户 2026-09-19 截图反馈）：
## 无边框窗口 window_get_mode() 恒报 WINDOWED（K-H 实证、4.7 复现：set_mode(MAXIMIZED) 后仍 0），
## 最大化真值经 main.gd 由 window_buttons.maximize_toggled(_maxed) 透传；mode 轮询通道保留
##（覆盖 FULLSCREEN 等真实上报态，refresh_state 同款口径）。

## main.gd 接线口（P0 追加口径①）：显式最大化/还原真值 → 整层隐藏/恢复（四角热区随层失效）。
func set_decoration_hidden(on: bool) -> void:
	_decoration_force_hidden = on
	_apply_decoration_visibility()

func _apply_decoration_visibility() -> void:
	# 判据双通道：①window_decoration_hidden(mode)（FULLSCREEN 等真实上报态）＋②显式标志
	#（borderless MAXIMIZED，get_mode 不可靠）。任一成立即隐藏。
	visible = not (window_decoration_hidden(DisplayServer.window_get_mode()) or _decoration_force_hidden)

## 形态判断内聚口（main.gd 只透传标志）：非圆角形态（直启备案）判据（供无头单测）。
## v2 语义注记：两形态差异只剩环半径（备案 0 直角贴边 vs 圆角形态 8）——旧「四角扇区填充
## 与否」概念随 v2 零填充废止，函数名保留（test_fix_window_scale 段8 断言锚）。
func _uses_fallback_corners() -> bool:
	return not dwm_round

## main.gd 接线口：置位/复位圆角形态（已入树后可重入；同步 drawer 半径/色并重绘）。
func set_dwm_round(on: bool) -> void:
	dwm_round = on
	if _drawer != null:
		_drawer.dwm = on
		_drawer.radius = 0.0 if not on else FRAME_RADIUS   # v2：环半径随形态（备案 0 直角贴边）
		_drawer.col = _stroke_color()
		_drawer.queue_redraw()

## 描边色单源：两路线恒 70% 透明灰（批次 U U9-1：旧主题深/浅档与 50% 灰分流废止，双审 P2-15）。
func _stroke_color() -> Color:
	return FRAME_STROKE_COLOR   # 批次 U（U9-1）：两路线单源恒灰

class FrameDrawer extends Control:
	## 圆角矩形描边：4 圆弧 + 4 直边，整体 inset 2px（沿窗缘内侧）。
	## v2：零填充——旧呼吸带包裹层/四角扇形两填充函数整体删除（源码级删除锁）；
	## radius 语义按形态：圆角形态（DWM/region 信号）=FRAME_RADIUS(8)；直启备案=0 直角贴边
	##（_draw_frame_path 内 rr=maxf(r−inset,1) 下限 1px，视觉即直角）。
	var radius := 0.0
	var stroke := 2.0
	var col := FRAME_STROKE_COLOR
	var dwm := false

	func _draw_frame_path(r: float, c: Color, w: float, inset := 0.0) -> void:
		var rr := maxf(r - inset, 1.0)
		var o := inset
		var sz := size
		draw_arc(Vector2(rr + o, rr + o), rr, PI, 1.5 * PI, 16, c, w, true)
		draw_arc(Vector2(sz.x - rr - o, rr + o), rr, 1.5 * PI, TAU, 16, c, w, true)
		draw_arc(Vector2(sz.x - rr - o, sz.y - rr - o), rr, 0.0, 0.5 * PI, 16, c, w, true)
		draw_arc(Vector2(rr + o, sz.y - rr - o), rr, 0.5 * PI, PI, 16, c, w, true)
		draw_line(Vector2(rr + o, o), Vector2(sz.x - rr - o, o), c, w, true)
		draw_line(Vector2(rr + o, sz.y - o), Vector2(sz.x - rr - o, sz.y - o), c, w, true)
		draw_line(Vector2(o, rr + o), Vector2(o, sz.y - rr - o), c, w, true)
		draw_line(Vector2(sz.x - o, rr + o), Vector2(sz.x - o, sz.y - rr - o), c, w, true)

	func _draw() -> void:
		# 批次 U（U9-3）：两条白色高光弧删除（白高光弧常量废止）；描边两路线同几何同色。
		# v2（用户 2026-09-19 二次截图反馈）：一切带状/角外填充废止，只画描边环——深黑包裹层
		# 方案整体推翻（用户实测其覆盖范围大于圆角=穿帮），四角透出桌面由 OS 级圆角
		#（DWM 属性/launcher SetWindowRgn）承担，渲染器不再补画。
		_draw_frame_path(radius, col, stroke, 2.0)   # 备案延续：描边环 inset 2px 贴窗缘内侧

var _drawer: FrameDrawer
var _drag_corner := SPIN_NONE
var _drag_start_size := Vector2i.ZERO
var _drag_start_pos := Vector2i.ZERO
var _drag_start_mouse := Vector2i.ZERO

func _ready() -> void:
	layer = 128
	_drawer = FrameDrawer.new()
	_drawer.name = "Frame"
	_drawer.radius = 0.0 if not dwm_round else FRAME_RADIUS   # v2：备案直角贴边/圆角形态 8
	_drawer.stroke = FRAME_STROKE
	_drawer.dwm = dwm_round            # 修复3：先置标志后入树的时序兼容（set_dwm_round 可先于 _ready）
	_drawer.col = _stroke_color()
	_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_drawer)
	# 四角热区：0=TL/1=TR/2=BL/3=BR（角编码与 WindowManager.corner_offset 文档约定一致）
	for i: int in 4:
		var h := Control.new()
		h.name = "Hot%d" % i
		h.size = Vector2(CORNER_HOT, CORNER_HOT)
		h.mouse_filter = Control.MOUSE_FILTER_STOP
		h.set_meta("interactive", true)   # WindowManager.is_interactive_control 排除拖窗
		h.gui_input.connect(_on_corner_input.bind(i))
		match i:
			0:
				h.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
				h.set_anchors_preset(Control.PRESET_TOP_LEFT)
			1:
				h.mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
				h.anchor_left = 1.0
				h.anchor_right = 1.0
				h.offset_left = -CORNER_HOT
				h.offset_right = 0.0
				h.offset_top = 0.0
				h.offset_bottom = CORNER_HOT
			2:
				h.mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
				h.anchor_top = 1.0
				h.anchor_bottom = 1.0
				h.offset_top = -CORNER_HOT
				h.offset_bottom = 0.0
				h.offset_left = 0.0
				h.offset_right = CORNER_HOT
			3:
				h.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
				h.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
				h.offset_left = -CORNER_HOT
				h.offset_top = -CORNER_HOT
				# 4.7 实证（ta4_anchor_probe_temp.gd）：preset 语义=保持视觉矩形（重算全部
				# offsets），BR 只覆写 left/top 会残留 right/bottom 旧值 → 尺寸 36×36（在树）
				# 或 0×0（无父）；四 offset 全显式才恒 18×18（plan 代码块自查修正）。
				h.offset_right = 0.0
				h.offset_bottom = 0.0
		_drawer.add_child(h)
	# 批次 AB-3：theme_changed 订阅随深浅主题机制删除退役（描边色单源恒灰）。

## 批次 AB-3：主题翻转回调随深浅主题机制删除退役（_stroke_color 单源恒灰，挂载时定值）。

## 拖角缩放：drag_vec 按角向定向（放大为正）：off=(1,1) BR 同向；TL 反向；TR 反 x；BL 反 y
## 签名序=RV-1 P0-1 回修：gui_input.connect(_on_corner_input.bind(i)) 的 bind 为尾随追加
##（signal 实参 ev 在前、bound corner 在后），处理器实收 (ev, corner)——旧 (corner, ev) 在窗口
## 模式抛「Cannot convert argument 1 from InputEventMouseButton to int」（level_scene.gd 先例序）。
func _on_corner_input(ev: InputEvent, corner: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var mb := ev as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_drag_corner = corner
			_drag_start_size = DisplayServer.window_get_size()
			_drag_start_pos = DisplayServer.window_get_position()
			_drag_start_mouse = DisplayServer.mouse_get_position()
		else:
			_drag_corner = SPIN_NONE
	elif ev is InputEventMouseMotion and _drag_corner != SPIN_NONE:
		var off := WM.corner_offset(_drag_corner)
		# P1-2 修正：方向系数=(2*off−1) 逐轴——off=(1,1) 的 BR 同向(+1,+1)（拖右下=放大）、
		# off=(0,0) 的 TL 反向(−1,−1)（拖左上鼠标 delta 为负 → oriented 为正=放大）、
		# TR(1,0)=(+1,−1)（拖右上 → 放大）、BL(0,1)=(−1,+1)（拖左下 → 放大）。
		# 旧式 (1.0−2.0*off) 使 BR 拖右下得负 delta=缩小，方向全反。
		var oriented := Vector2(DisplayServer.mouse_get_position() - _drag_start_mouse) \
			* Vector2(2.0 * off.x - 1.0, 2.0 * off.y - 1.0)
		var usable: Vector2i = DisplayServer.screen_get_usable_rect().size
		var r: Dictionary = WM.corner_resize(_drag_start_size, _drag_corner, oriented, usable, _drag_start_pos)
		WM.apply_resized_window(r["pos"], r["size"])

## 批次 U（U9-6，spec §4-U9-6/§6.3）：全屏/最大化隐藏装饰层——判据 mode >= WINDOW_MODE_MAXIMIZED
##（覆盖 MAXIMIZED/FULLSCREEN/EXCLUSIVE_FULLSCREEN 完备性，双审 P2-15；磁盘实况：4.7 枚举成员名
## 系 MODE_EXCLUSIVE_FULLSCREEN=4，本判据只引用 MODE_MAXIMIZED 不受成员名差异影响）；纯函数无头可测；
## 四角 18×18 热区随层一并失效；还原自动恢复（_process 轮询判据）。
static func window_decoration_hidden(mode: int) -> bool:
	return mode >= Window.MODE_MAXIMIZED

func _process(_delta: float) -> void:
	# U9-6：窗口 mode 轮询（4.7 无头实测 window_get_mode()=MINIMIZED(1) < MAXIMIZED → 恒可见，
	# 无头测试安全）。P0 追加口径①：判据双通道合一（mode 真实上报态＋borderless 显式最大化标志）。
	_apply_decoration_visibility()
