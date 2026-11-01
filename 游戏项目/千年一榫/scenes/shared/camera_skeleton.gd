extends Control
## 批次 U（U6，spec §4-U6/§6.3）：摄像头画面手部骨架叠加——23 段连接＋21 关节点，
## pillarbox 换算（keep-aspect-centered 内衬矩形），左手蓝/右手红。
## 批次 V（V12，spec §5.1）：本件 _draw 内增绘「手部活动区域」细琥珀虚线参考框
## （[0.5±1/(2g)]² 归一区间经 pillarbox 换算，增益运行期读 gesture_map 常量；
## 零新增节点/挂载点，随骨架同款纹理缺失早退门不绘制）。
## 批次 X（X1，spec §3）：参考框改 overshoot 语义 half=(0.5+m)/g（框=映射区大一圈），
## m=gesture_map.CURSOR_OVERSHOOT 经新增 map_cursor_overshoot 同源读取（零静态引用纪律不变）；
## cursor_zone_rect 第四参缺省=0.0 保旧行为等价（旧调用与既有测试零破坏）。
## mouse_filter=2（IGNORE）随 CameraWindow 穿透；挂 CameraWindow 下随窗缩放（U5⑨）自动跟随。
## 归一化基准（实施首任务读码复核结论，spec §4-U6-4）：landmarks 与 JPEG 画面同源镜像——
## 唯一 flip 点在 hand_tracking_server.py 采集线程 cv.flip(frame,1)（计划稿 :1145-1147，
## 磁盘实况漂移至 :1200，语义同一条），先于检测（_process_frame）与 JPEG 编码（:1145 一带
## _jpeg_sender 循环）→ landmarks 归一坐标与画面同基准，直接映射。
## 数据源：bridge 手势 JSON 最新帧 gestures payload（gesture_state_received 既有载荷，
## hand dict 内 landmarks=21 点归一 [x,y] 数组，hand_tracking_server.py :797 透传）；
## src_size 取当前纹理实际尺寸（非硬编码 4:3，防非 4:3 相机）；纹理缺失不绘制（无对位依据不猜）。
## ⚠ 编译窗纪律：本件会被测试 const preload 于 --script 主脚本编译期加载——全文件零 autoload
## 全局名静态引用（同 hover_tip.gd 头注，U-D 实证坑）。

# 批次 W（P3-1）：色彩单源表（值不变）。
const Palette := preload("res://scripts/palette.gd")
const SKELETON_REDRAW_MAX_FPS := 30
const SKELETON_COLOR_LEFT := Palette.SKELETON_BLUE    # 左手蓝（P3-1 单源，值不变；与光标蓝异值不并档）
const SKELETON_COLOR_RIGHT := Color(1.0, 0.35, 0.30)   # 右手红
const SKELETON_LINE_W := 1.2   # 批次 W（N6，规格 §5）：骨架变细起步档 2.0→1.2（走查可微调）
const SKELETON_TIP_R := 4.0    # 批次 W（N6）：指尖圆 7.0→4.0
const SKELETON_JOINT_R := 2.5  # 批次 W（N6）：关节圆 4.0→2.5
const ZONE_COLOR := Color("#D9A441")           # 批次V §5.1：手部活动区域参考框琥珀（ORBIT 环同色）
const ZONE_LINE_W := 1.5                        # 参考框细线宽
const ZONE_DASH := 6.0                          # 参考框虚线段长（px）
## 批次 AA（W1-10，spec §4.3/§4.7）：骨架防重容差——与 python 侧 HAND_SAME_HAND_LM_TOL 同源
## （逐点最大偏差，归一坐标）【暂定值·待用户复验】
const SAME_HAND_LM_TOL := 0.02
## HAND_CONNECTIONS——照 MediaPipe 官方 Hand Landmarker 23 段连接定义照录
## 23 段（拇指/食指/中指/无名指/小指各 4 段＋掌骨 3 段）；需求原文「25 段」系计数偏差（spec 勘误）。
const HAND_CONNECTIONS := [
	[0, 1], [1, 2], [2, 3], [3, 4],            # 拇指 4
	[0, 5], [5, 6], [6, 7], [7, 8],            # 食指 4
	[0, 9], [9, 10], [10, 11], [11, 12],       # 中指 4
	[0, 13], [13, 14], [14, 15], [15, 16],     # 无名指 4
	[0, 17], [17, 18], [18, 19], [19, 20],     # 小指 4
	[5, 9], [9, 13], [13, 17],                 # 掌骨 3
]
const TIP_INDEXES := [4, 8, 12, 16, 20]        # 指尖圆 r=7；其余 16 关节 r=4

var _hands: Dictionary = {}   # "left"/"right" → PackedVector2Array（归一坐标原样缓存）
var _dirty := false
var _accum := 0.0

## keep-aspect-centered 内衬矩形（纯函数无头可测；无效尺寸回退满窗——纹理缺失时调用方不绘制）
static func pillarbox_rect(win: Vector2, src: Vector2) -> Rect2:
	if win.x <= 0.0 or win.y <= 0.0 or src.x <= 0.0 or src.y <= 0.0:
		return Rect2(Vector2.ZERO, win)
	var s: float = minf(win.x / src.x, win.y / src.y)
	var inner := Vector2(roundf(src.x * s), roundf(src.y * s))
	var pos := Vector2(roundf((win.x - inner.x) * 0.5), roundf((win.y - inner.y) * 0.5))
	return Rect2(pos, inner)

## 手部活动区域参考框矩形（批次V §5.1，纯函数无头可测）：光标增益 g 下源画面中可达的归一
## 区间经 pillarbox 内衬矩形换算到窗内像素矩形，随增益自适应；
## 批次 X P2（spec §3）：增第四参 overshoot（缺省=0.0）——框=映射区大一圈，
## 公式 half=(0.5+overshoot)/gain；g≤0 无效回退整个内衬矩形（不猜值，同 pillarbox_rect 风格）。
## 批次 AC（领域四 §4.4-1，2026-09-27 用户截图红圈→蓝框拍板）：**纵向顶边直接顶住画面顶部**
## ——旧码纵向沿用 0.5 居中（y0=0.5−half、高 2half），用户食指尖指到框上部时手掌/手腕已出画面
## 底边或被迫抬腕。新纵向语义：y0 = 0.0、h = 2half → 归一纵向覆盖 [0, 2half]（默认参数
## gain=2.5/m=0.15 下 half=0.26 → [0.0, 0.52]），画面下半 [0.52, 1.0] 完整留给手掌与手腕。
## 横向保持居中（x0 = 0.5−half、w = 2half）不变——与 `apply_cursor_gain` 的纵向中心
## c_y=(0.5+m)/gain 严格互为反函数（见手势映射同批改动）。
static func cursor_zone_rect(win: Vector2, src: Vector2, gain: float, overshoot: float = 0.0) -> Rect2:
	var inner := pillarbox_rect(win, src)
	if gain <= 0.0:
		return inner
	var half := (0.5 + overshoot) / gain
	return Rect2(inner.position + Vector2(0.5 - half, 0.0) * inner.size,
		Vector2(2.0 * half, 2.0 * half) * inner.size)

## 参考框增益同源读取（批次V §5.1）：运行期 load 读 gesture_map.CURSOR_GAIN 常量——本件被
## 测试 const preload 于 --script 编译窗加载，须守「零全局名静态引用」头注纪律，故不走
## class_name 直引；加载失败回 0 → cursor_zone_rect 回退满内衬（不猜值）。
static func map_cursor_gain() -> float:
	var s: Variant = load("res://scripts/gesture_map.gd")
	if s == null:
		return 0.0
	return float(s.get_script_constant_map().get("CURSOR_GAIN", 0.0))

## 参考框 overshoot 同源读取（批次 X P2，spec §3）：同 map_cursor_gain 零静态引用纪律——
## 运行期 load 读 gesture_map.CURSOR_OVERSHOOT；加载失败回 0 → cursor_zone_rect 退化为旧框
## [0.5±1/(2g)]²（缺省语义=旧行为等价，不猜值）。
static func map_cursor_overshoot() -> float:
	var s: Variant = load("res://scripts/gesture_map.gd")
	if s == null:
		return 0.0
	return float(s.get_script_constant_map().get("CURSOR_OVERSHOOT", 0.0))

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)   # 相对 CameraWindow 满锚（父为 TextureRect 非停靠表件——防坑 3 不适用于子件相对布局）

## bridge 手势 JSON 最新帧入口（gesture_hud._on_state 转发）；该侧 null=手离场自动清空
func set_hands(left: Variant, right: Variant) -> void:
	_hands.clear()
	_store("left", left)
	_store("right", right)
	_dedup_same_hand()   # 批次 AA（W1-10）：渲染防重护栏（单一漏斗，_draw 消费的即已判重）
	_dirty = true

## 批次 AA（W1-10，spec §4.3）：同源判重——两个点集逐点最大偏差 < 容差即判同一只手。
## 供 set_hands 落地「同一只手不同时出现在 left/right」（包内异常同源 → 只绘一份，优先 left）。
static func is_same_hand(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	if a.size() != b.size() or a.size() == 0:
		return false
	var max_dev := 0.0
	for i: int in a.size():
		max_dev = maxf(max_dev, absf(a[i].x - b[i].x))
		max_dev = maxf(max_dev, absf(a[i].y - b[i].y))
		if max_dev >= SAME_HAND_LM_TOL:
			return false
	return true

## 防重护栏本体：左右两侧 landmark 重合（同源）→ 丢弃 right、保留 left（spec 口径「优先 left」）。
func _dedup_same_hand() -> void:
	if not (_hands.has("left") and _hands.has("right")):
		return
	var l: PackedVector2Array = _hands["left"]
	var r: PackedVector2Array = _hands["right"]
	if is_same_hand(l, r):
		_hands.erase("right")

func clear_hands() -> void:
	_hands.clear()
	_dirty = true

func _store(side: String, hand: Variant) -> void:
	if typeof(hand) != TYPE_DICTIONARY:
		return
	var lms: Variant = hand.get("landmarks", null)   # 防坑 5：.get 防御
	if typeof(lms) != TYPE_ARRAY or (lms as Array).size() != 21:
		return
	var pts := PackedVector2Array()
	for p: Variant in lms:
		# R2①-P2-5：typeof 守卫——非数组（或不足 2 元）点放弃整手存储（骨架连线与 21 点
		# 一一对应，逐点 continue 会索引错位画错线；整手不入 _hands 由 _draw 端 has 门跳过）
		if typeof(p) != TYPE_ARRAY or (p as Array).size() < 2:
			return
		var a: Array = p
		pts.append(Vector2(float(a[0]), float(a[1])))
	_hands[side] = pts

func _process(delta: float) -> void:
	_accum = maxf(_accum - delta, 0.0)
	if _dirty and _accum <= 0.0:
		_accum = 1.0 / float(SKELETON_REDRAW_MAX_FPS)
		_dirty = false
		queue_redraw()   # 节流 30fps 防重绘风暴（U6-3）

func _draw() -> void:
	var cam_win := get_parent() as TextureRect
	var tex := cam_win.texture if cam_win != null else null
	if tex == null:
		return   # 纹理缺失不绘制（spec §11-6）
	var src := Vector2(tex.get_size())
	var inner := pillarbox_rect(size, src)
	# 批次V §5.1：手部活动区域参考框（细琥珀虚线，随增益自适应；绘制于骨架之下）。
	# 批次 X P2（spec §3）：overshoot 传 gesture_map.CURSOR_OVERSHOOT 实值——框=映射区大一圈，
	# 与 apply_cursor_gain 扩边钳制域 [-m,1+m] 互为反函数；纹理缺失已在上方早退（同款门，spec §11-6）。
	var zone := cursor_zone_rect(size, src, map_cursor_gain(), map_cursor_overshoot())
	var tl := zone.position
	var tr := zone.position + Vector2(zone.size.x, 0.0)
	var br := zone.position + zone.size
	var bl := zone.position + Vector2(0.0, zone.size.y)
	draw_dashed_line(tl, tr, ZONE_COLOR, ZONE_LINE_W, ZONE_DASH)
	draw_dashed_line(tr, br, ZONE_COLOR, ZONE_LINE_W, ZONE_DASH)
	draw_dashed_line(br, bl, ZONE_COLOR, ZONE_LINE_W, ZONE_DASH)
	draw_dashed_line(bl, tl, ZONE_COLOR, ZONE_LINE_W, ZONE_DASH)
	for side: String in ["left", "right"]:
		if not _hands.has(side):
			continue
		var col := SKELETON_COLOR_LEFT if side == "left" else SKELETON_COLOR_RIGHT
		var pts: PackedVector2Array = _hands[side]
		var px := PackedVector2Array()
		for p: Vector2 in pts:
			px.append(inner.position + p * inner.size)   # 归一 → 内衬矩形像素（同源镜像直映射）
		for c: Array in HAND_CONNECTIONS:
			draw_line(px[c[0]], px[c[1]], col, SKELETON_LINE_W, true)
		for i: int in 21:
			if TIP_INDEXES.has(i):
				draw_circle(px[i], SKELETON_TIP_R, col)
			else:
				draw_circle(px[i], SKELETON_JOINT_R, col)
