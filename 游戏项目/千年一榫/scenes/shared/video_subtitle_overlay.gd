extends Label
## 视频英文字幕共享覆盖层（批次 AF 修复②，2026-11-01）。
## 来源：开场动画英文字幕覆盖层（opening_movie 专属实现）抽共享——图鉴内嵌播放器
## （catalog_scene 开场回看）与 opening_movie 同源共用，消「图鉴回放无英文字幕」病灶。
## 契约（任务书修复②）：
##   输入=VideoStreamPlayer + 字幕 JSON 路径（setup()）；几何锚定 KEEP_ASPECT_CENTERED
##   内容矩形（content_rect_for 纯函数，黑边解算）；样式=白字黑描边、中文烧录字幕下方
##   （比例档：顶 0.893/框高 0.107/框宽 0.72/字号 0.037×内容高）；**中英双语常显**
##   （纯 stream_position 时间驱动，不接语言开关、不随语言状态变化——间隙/越界即隐）；
##   mouse_filter=IGNORE（绝不吞任何控件热区）。
## 挂载形态二态兼容（几何基准自动判别）：
##   - 播放器**子节点**（catalog 内嵌播放器）：position=播放器局部系，reparent 全屏
##     （_set_fullscreen 单播放器升降）自动跟随，嵌入/全屏两形态同贴内容矩形；
##   - 播放器**兄弟节点**（opening_movie 场景树静态件）：position 补 player.position 偏移
##     （旧 opening_movie 实现同口径平移）。
## 字幕数据格式：{"_说明":[…], "subtitles":[{start,end,en}]}，秒、半开区间 [start,end)、
## 单调不减互不重叠（破坏顺序条目跳过防查表歧义）。数据缺失/非法=空表恒隐不炸。
## 可选避让：avoid 控件（如 opening_movie 的「跳过」钮）与字幕带纵向重叠时收窄字幕宽度
##（保持水平居中不压热区）；同父判定（不同父的矩形不同系，不比对）。

const DEFAULT_ASPECT := 16.0 / 9.0   # 开场动画片源 1280×720

# 覆盖层几何（全部相对视频内容矩形，比例值——opening_movie 定档原值平移，单一真源在本件）
const SUB_TOP_RATIO := 0.893    # 字幕顶部：中文烧录字幕（字形底边实测 0.887）下方空隙
const SUB_HEIGHT_RATIO := 0.107 # 字幕框高：至内容底 1.000
const SUB_WIDTH_RATIO := 0.72   # 字幕框宽（水平居中）
const SUB_FONT_RATIO := 0.037   # 基准字号 = 内容高 × 0.037（648 高 → 24px；两行容于空隙）
const SUB_FONT_MIN := 16
const SUB_FONT_MAX := 48
const AVOID_GAP := 8.0          # 与避让控件热区的间隙（像素）

var _player: VideoStreamPlayer = null
var _avoid: Control = null
var _aspect: float = DEFAULT_ASPECT
var _subs: Array = []           # {start,end,en}，start 升序
var _subs_loaded: bool = false
var _subs_path: String = ""

func _init() -> void:
	# 样式缺省（catalog 代码挂载无 tscn 兜底；opening_movie tscn 同值覆写幂等）：
	# 白字+黑描边、居中、自动换行兜底、两行上限、鼠标穿透。
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_color_override("font_color", Color(1, 1, 1, 1))
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	add_theme_constant_override("outline_size", 3)
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_TOP
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	max_lines_visible = 2
	text = ""

## 接线（幂等可重入）：绑定播放器 + 可选避让控件 + 宽高比，并按需载入字幕数据。
func setup(player: VideoStreamPlayer, json_path: String, avoid: Control = null,
		aspect: float = DEFAULT_ASPECT) -> void:
	_player = player
	_avoid = avoid
	_aspect = aspect if aspect > 0.0 else DEFAULT_ASPECT
	load_subtitles(json_path)

## 载入字幕 JSON（按路径幂等；缺失/非法=空表恒隐，不影响播放）。
## 独立成方法：门面（opening_movie._load_subtitles）可在 @onready 就绪前先行预载（测试路径）。
func load_subtitles(json_path: String) -> void:
	if _subs_loaded and _subs_path == json_path:
		return
	_subs_loaded = true
	_subs_path = json_path
	_subs.clear()
	if not FileAccess.file_exists(json_path):
		push_warning("英文字幕数据缺失：%s" % json_path)
		return
	var f: FileAccess = FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		push_warning("英文字幕数据打不开：%s" % json_path)
		return
	var raw: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_warning("英文字幕数据非法（非 JSON 对象）：%s" % json_path)
		return
	var arr: Variant = (parsed as Dictionary).get("subtitles", null)
	if not (arr is Array):
		push_warning("英文字幕数据非法（subtitles 非数组）：%s" % json_path)
		return
	var prev_end := 0.0
	for e: Variant in arr:
		if not (e is Dictionary):
			continue
		var d: Dictionary = e
		if not (d.has("start") and d.has("end") and d.has("en")):
			continue
		var s: float = float(d["start"])
		var t: float = float(d["end"])
		var en: String = String(d["en"])
		if s < 0.0 or s >= t or en.strip_edges() == "":
			continue
		# 数据契约（区间单调不减、互不重叠）：破坏顺序的条目跳过，避免查表歧义。
		if s < prev_end:
			push_warning("英文字幕区间重叠，跳过：%s" % en)
			continue
		prev_end = t
		_subs.append({"start": s, "end": t, "en": en})

func subtitle_count() -> int:
	return _subs.size()

func subtitle_entry(i: int) -> Dictionary:
	if i < 0 or i >= _subs.size():
		return {}
	return _subs[i]

## 按播放时刻查当前英文（二分；半开区间 [start, end)）。无字幕（间隙/越界/负值）→ 空串。
func subtitle_at(t: float) -> String:
	if _subs.is_empty() or t < 0.0:
		return ""
	var lo := 0
	var hi := _subs.size() - 1
	while lo <= hi:
		var mid: int = (lo + hi) >> 1
		var e: Dictionary = _subs[mid]
		var s: float = float(e["start"])
		var t_end: float = float(e["end"])
		if t < s:
			hi = mid - 1
		elif t >= t_end:
			lo = mid + 1
		else:
			return String(e["en"])
	return ""

## 纯时间驱动显隐（与语言模式无关）：有字幕即显、间隙/越界即隐。
func refresh_subtitle_at(t: float) -> void:
	var s := subtitle_at(t)
	text = s
	visible = s != ""

## KEEP_ASPECT_CENTERED 内容矩形解算（实例方法，按 setup 注入的宽高比）：
## 返回片源在 box 内的居中内容区（含黑边偏移）。播放器 expand=true 恒拉伸铺满自身 rect，
## 故字幕须锚在内容区而非控件区。
func content_rect_for(box: Vector2) -> Rect2:
	return content_rect_for_box(box, _aspect)

## 纯函数版（无实例依赖，门面/测试直用）。
static func content_rect_for_box(box: Vector2, aspect: float) -> Rect2:
	if box.x <= 0.0 or box.y <= 0.0:
		return Rect2()
	var w: float = box.x
	var h: float = w / aspect
	if h > box.y:
		h = box.y
		w = h * aspect
	return Rect2(Vector2((box.x - w) * 0.5, (box.y - h) * 0.5), Vector2(w, h))

## 单帧刷新（布局 + 时间查表）——显式公共入口（测试直驱/宿主直调两用）；
## _process 每帧自驱同走本方法。播放器未接线（setup 未调）时静默待命。
func refresh_frame() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_layout()
	var cur := -1.0
	if _player.stream != null:
		# stream_position 在未播放/暂停时可能为 0 或负数，统一夹到 0（负值再交给查表判空）。
		cur = maxf(_player.stream_position, 0.0)
	refresh_subtitle_at(cur)

## 逐帧自驱：几何随播放器矩形/窗口缩放重算 + 按播放进度换字幕（挂载方零参与）。
func _process(_delta: float) -> void:
	refresh_frame()

## 几何落位：内容矩形解算 → 中文烧录字幕下方空隙带 → 可选避让收窄 → 字号随内容高缩放。
func _layout() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var box: Vector2 = _player.size
	if box.x <= 0.0 or box.y <= 0.0:
		return
	var content: Rect2 = content_rect_for(box)
	# 挂载形态判别：子节点=播放器局部系（reparent 全屏自动跟随）；兄弟节点=补播放器原点。
	var base: Vector2 = Vector2.ZERO if get_parent() == _player else _player.position
	var origin: Vector2 = base + content.position
	var center_x: float = origin.x + content.size.x * 0.5
	var top: float = origin.y + content.size.y * SUB_TOP_RATIO
	var height: float = content.size.y * SUB_HEIGHT_RATIO
	var width: float = content.size.x * SUB_WIDTH_RATIO
	# 与避让控件纵向重叠时收窄字幕宽度（保持水平居中），保证不压其热区。
	# 同父判定：get_rect() 为各自父系坐标，异父矩形不可比（异父=放弃避让，保守不收窄）。
	if _avoid != null and is_instance_valid(_avoid) and _avoid.get_parent() == get_parent():
		var avoid_rect: Rect2 = _avoid.get_rect()
		if avoid_rect.position.y < top + height and avoid_rect.end.y > top:
			var limit_x: float = avoid_rect.position.x - AVOID_GAP
			var half_w: float = limit_x - center_x
			if half_w > 0.0:
				width = minf(width, half_w * 2.0)
			else:
				width = minf(width, limit_x - origin.x)
		width = maxf(width, 0.0)
	position = Vector2(center_x - width * 0.5, top)
	size = Vector2(width, height)
	var fs: int = int(round(content.size.y * SUB_FONT_RATIO))
	fs = clampi(fs, SUB_FONT_MIN, SUB_FONT_MAX)
	if get_theme_font_size("font_size") != fs:
		add_theme_font_size_override("font_size", fs)
