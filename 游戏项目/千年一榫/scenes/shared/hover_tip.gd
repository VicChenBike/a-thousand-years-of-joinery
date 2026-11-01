extends PanelContainer
## 批次 U（U7，spec §4-U7/§6.3）：共享悬停提示组件——键鼠＋手势光标双路径，绝不吞点击。
## - mouse_filter=2（IGNORE）：CamTip 三因吞点击（STOP/压光标/z_index）根因之一同治（U2/U3）；
## - 锚定=光标右下 TIP_OFFSET=(18,20)：永不压光标本体与其正下方控件；
## - 逐帧跟随；消失=指针离开宿主矩形（无保活矩形——U2-1 判据删除）；
## - setup(host, text, enabled, pointer_provider)：enabled 象限/状态谓词每帧判定、false 强制隐藏
##   （双审 P2-12；摄像头钮 Q2 门控经此单一落点，U3×U7-4 一处实现）；
## - 双路径（spec U7-2）：pointer_provider 可注入（测试合成光标）；缺省=GestureCursorLayer
##  .get_pointer_pos()（手势光标，content 系真全局坐标）→ null 回落 get_global_mouse_position()
##   （键鼠路径；键鼠 hover 语义由宿主矩形相交判定统一承载，mouse_entered/exited 信号不参与——
##   与逐帧谓词判定语义等价且免双路径状态同步，备案）。
## 同系比较硬纪律（防坑 6）：宿主判定一律 host.get_global_rect()（含 GlobalUI +10 的真全局位），
## 与零偏移层光标位/鼠标位同系，禁止跨系手工加减。
## 视觉：玻璃风格沿用 CamTip（深档 StyleBoxFlat、圆角 10、字 12；批次 AB-3：衬底恒深档）。
## ⚠ 编译窗纪律（U-D 实证）仍然有效：本件会被测试 const preload 于 --script 主脚本编译期加载，
## 全文件零 autoload 全局名静态引用（批次 AB-3 后主题判定已删，本纪律保留为防回归口径）。

const TIP_OFFSET := Vector2(18, 20)
const FONT_SIZE := 12
const MAX_WIDTH := 320.0

var _host: Control = null
var _enabled: Callable = Callable()
var _pointer_provider: Callable = Callable()
var _label: Label
var _cached_layer: Node = null   # R2①-P2-5：GestureCursorLayer 引用缓存（首次命中后免逐帧 find_child 全树递归）

## 衬底样式构建（批次 AB-3：深浅双档坍缩为恒深档——由 _init 构建一次，样式生命周期=组件生命周期）。
## 每次新建 StyleBox 后重挂 override——改旧实例属性不触发重绘，重建为玻璃组件同款口径。
func _apply_theme() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.12, 0.06, 0.92)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10.0)
	add_theme_stylebox_override("panel", sb)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200
	visible = false
	_apply_theme()
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(300, 0)
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	add_child(_label)

## 注册式绑定（一 host 一 tip）：text 逐字；enabled 缺省恒显；pointer_provider 缺省双路径默认源
func setup(host: Control, text: String, enabled: Callable = Callable(), pointer_provider: Callable = Callable()) -> void:
	_host = host
	_label.text = text
	_enabled = enabled
	_pointer_provider = pointer_provider

## 双路径光标位（Variant：Vector2 或 null=本帧无手势光标 → 键鼠回落）
func _pointer() -> Variant:
	if _pointer_provider.is_valid():
		return _pointer_provider.call()
	if _host != null and is_instance_valid(_host) and _host.is_inside_tree():
		# R2①-P2-5：缓存命中且仍有效 → 免 find_child 全树递归（level_scene 三实例每帧 3 次
		# 全树搜的性能税根除）；缓存失效（释放/离树）时重查一次；从未命中（缓存 null）沿用
		# 逐帧查找原行为——layer 常驻，正常路径首帧命中后恒走缓存。行为与旧版逐字等价。
		var layer: Node = _cached_layer
		if layer == null or not is_instance_valid(layer) or not layer.is_inside_tree():
			layer = _host.get_tree().get_root().find_child("GestureCursorLayer", true, false)
			if layer != null:
				_cached_layer = layer
		if layer != null:
			var gp: Variant = layer.call("get_pointer_pos")
			if gp != null:
				return gp
	return _host.get_global_mouse_position()

func _process(_delta: float) -> void:
	if _host == null or not is_instance_valid(_host) or not _host.is_visible_in_tree():
		visible = false
		return
	if _enabled.is_valid() and not bool(_enabled.call()):
		visible = false   # 象限/状态谓词 false 强制隐藏（双审 P2-12，U3×U7-4 单一落点）
		return
	var p: Variant = _pointer()
	if p == null:
		visible = false
		return
	var pos: Vector2 = p
	if not _host.get_global_rect().has_point(pos):
		visible = false   # 指针离开宿主矩形（无保活矩形判据——U2-1）
		return
	visible = true
	global_position = pos + TIP_OFFSET   # 光标右下偏移（永不压光标本体与其正下方控件）
	# 批次 W（P3-6d，规格 §7）：只钳宽不清高——旧实现 y=0 依赖 PanelContainer 最小尺寸兜底
	# （脆弱无断言）；改保留现有高度，宽度钳制语义不变（test_w_polish E5/E6 断言）。
	size = Vector2(minf(size.x, MAX_WIDTH), size.y)
