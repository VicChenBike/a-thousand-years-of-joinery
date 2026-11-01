class_name WindowButtons
extends HBoxContainer
## K-A（K8-4）：无边框自绘三按钮（最小化/最大化还原/关闭）。先主题字形文本，K-H 后可换图标。
## 关闭不直接 quit——发 close_pressed 由 main.gd 接住（K-A 暂直接退出，K-C 换 GlassDialog）。
## M-A/N12/N12-2：字形色米黄浅金 (0.96,0.90,0.78)、三钮底色对齐深棕 Button 档。
## 批次 AB-3（用户拍板）：深浅主题机制彻底删除——GLYPH_COLOR_LIGHT/BG_*_LIGHT 浅档、
## _is_dark 档位缓存与 theme_changed 订阅/回调全部退役，深档为唯一真值（UI 观感零变化：
## 深色系统下旧实现本就走深档分支，值逐一未变）。
signal minimize_pressed; signal maximize_toggled(is_maximized: bool); signal close_pressed
# 批次 W（P3-1）：色彩单源表（值不变）。
const Palette := preload("res://scripts/palette.gd")
const GLYPH_COLOR := Color(0.96, 0.90, 0.78)
# N12-2：三钮底色与深棕 Button 档对齐（== theme_dark.tres Button normal/hover/pressed 底色档）；
# α 四态档与主题 Button 同构（normal 0.55 / hover·pressed 0.85，_small_sb 内落）。
const BG_NORMAL := Color(0.38, 0.27, 0.10)
const BG_HOVER := Color(0.34, 0.24, 0.09)
const BG_PRESSED := Color(0.38, 0.27, 0.10)
static func glyph_color() -> Color:
	return GLYPH_COLOR
var _max_btn: Button
func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_make_button("—", func() -> void: minimize_pressed.emit())
	_max_btn = _make_button("□", _on_max)
	_make_button("×", func() -> void: close_pressed.emit())
	_apply_styleboxes()
	_apply_glyph_colors()
	refresh_state()
func _apply_glyph_colors() -> void:
	var c := glyph_color()
	for ch: Node in get_children():
		if ch is Button:
			var b := ch as Button
			b.add_theme_color_override("font_color", c)
			# M-A 回修 P3-1（2026-09-07）：hover/pressed 态同档字形色——三钮 hover 底更亮，
			# 若回落主题 hover 字色会造成悬停瞬间明暗反转。
			b.add_theme_color_override("font_hover_color", c)
			b.add_theme_color_override("font_pressed_color", c)
func _make_button(glyph: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = glyph; b.custom_minimum_size = Vector2(32, 32)
	# P1-1 回修（审查实证：主题 22px 字+18/18 边距把 32 钮撑到 ~59px、三钮 178px 左溢
	# 压盖 SettingsButton）：小号字形+紧凑 StyleBox 覆盖，真正落成 spec §4.3「32×32 圆角按钮」。
	b.add_theme_font_size_override("font_size", 14)
	b.focus_mode = Control.FOCUS_NONE  # 防 Esc/空格误聚焦（spec §4.3）
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.set_meta("hover_glow", true)  # K9 光晕接入
	b.pressed.connect(handler); add_child(b)
	return b
func _apply_styleboxes() -> void:
	## N12-2：三钮四态 StyleBox 统一挂载（批次 AB-3：单主题单档，挂载一次）。
	for ch: Node in get_children():
		if ch is Button:
			var b := ch as Button
			b.add_theme_stylebox_override("normal", _small_sb(false, false))
			b.add_theme_stylebox_override("hover", _small_sb(true, false))
			b.add_theme_stylebox_override("pressed", _small_sb(false, true))
func _small_sb(hover: bool, pressed: bool) -> StyleBoxFlat:
	## P1-1：窗口 chrome 三钮小号样式（圆角 8/边距 5~6，光影方向与全局同族但按小元素收档）。
	## N12-2：底色取深棕 Button 对应档（弃 M-A 亮金）；批次 AB-3：恒深档。
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(8)
	sb.bg_color = BG_HOVER if hover else (BG_PRESSED if pressed else BG_NORMAL)
	sb.bg_color.a = 0.85 if (hover or pressed) else 0.55
	sb.border_width_top = 1
	sb.border_color = Color(Palette.STROKE_GOLD, 0.35)   # P3-1：描边金单源（值不变）
	if hover:
		sb.set_content_margin_all(5.0)
		# L-A（LA-3，spec §5.4）：金色 omni 发光归黑——发光全部由材质点光与光晕层承载，
		# 窗口三小钮不再自带第二套发光；方向影归档 (3,5)（光源左上）。
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 6; sb.shadow_offset = Vector2(3, 5)
	elif pressed:
		sb.set_content_margin_all(6.0)  # 按压内缩 1px（全局 pressed 同语义）
		sb.shadow_color = Color(0, 0, 0, 0.35)
		# L-A（spec §5.4 注记）：pressed (0,1)/3=小元素按压反馈例外档（下沉 1px 表意按压），
		# 非全局 (3,5) 归一对象，保留。
		sb.shadow_size = 3; sb.shadow_offset = Vector2(0, 1)
	else:
		sb.set_content_margin_all(5.0)
		sb.shadow_color = Color(0, 0, 0, 0.35)
		sb.shadow_size = 4; sb.shadow_offset = Vector2(3, 5)  # L-A：(2,3)→(3,5) 方向影归一
	return sb
var _maxed := false  # K-H（P1 回修）：本地最大化状态机（见 _on_max 注释）
var _pre_max_geom: Array = []  # [pos: Vector2i, size: Vector2i] 进入最大化前的几何
func _on_max() -> void:
	if DisplayServer.get_name() == "headless": return
	# K-H 走查实证（P1）：无边框窗口 window_get_mode() 恒报 WINDOWED(0)——
	# ①以 get_mode 为判据时「还原」永不可达且字形不亮；
	# ②set_mode(WINDOWED) 在无边框态是 no-op，最大化后不会缩回。
	# → 用本地 _maxed 状态机 + 显式几何保存/还原（尺寸仍经 enforce_aspect 归一到 16:9，符合 K8-2）。
	if not _maxed:
		_pre_max_geom = [DisplayServer.window_get_position(), DisplayServer.window_get_size()]
		_maxed = true
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	else:
		_maxed = false
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		if _pre_max_geom.size() == 2:  # 显式还原到最大化前几何（set_mode 在无边框下不缩回）
			DisplayServer.window_set_position(_pre_max_geom[0])
			DisplayServer.window_set_size(_pre_max_geom[1])
	maximize_toggled.emit(_maxed); refresh_state()
func refresh_state() -> void:
	## 按当前窗口状态回显「□/❐」互切字形（全屏切换后亦调用，非窗口态=❐ 同旧口径）。
	## K-H：无边框态 get_mode 不报 MAXIMIZED（实证），_maxed 为权威；全屏为瞬态只影响显示不回写。
	if _max_btn == null: return
	var maximized: bool = _maxed
	if DisplayServer.get_name() != "headless":
		var m: int = DisplayServer.window_get_mode()
		if m == DisplayServer.WINDOW_MODE_MAXIMIZED or m != DisplayServer.WINDOW_MODE_WINDOWED:
			maximized = true  # 全屏等非窗口态（旧行为保持），不写回 _maxed
	_max_btn.text = "❐" if maximized else "□"
