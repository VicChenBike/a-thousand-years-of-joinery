extends "res://tests/test_base.gd"
## 开场动画英文字幕覆盖层用例（批次 AF，用户 2026-11-01 拍板：不剪辑视频，
## 在游戏播放动画时实时渲染英文字幕；中文原文已烧在视频画面内）。
## 契约：
##   1. assets/animations/opening_subtitles_en.json：{"_说明":[双语两行], "subtitles":[{start,end,en}]}，
##      秒为单位、区间单调不减且互不重叠（半开区间 [start,end)）、条数 > 0、末条 end ≤ 视频时长 + 0.5。
##   2. 查表函数 subtitle_at(t)：0/首条中点/间隙/末条尾/超时长 五类边界正确（间隙返回空串）。
##   3. opening_movie.tscn 内 EnglishSubtitle(Label)：存在、白色、字号落在可读区间、
##      贴在视频内容矩形内（KEEP_ASPECT_CENTERED 黑边解算 content_rect_for）、
##      位于「跳过」按钮之下（树序在前）且不遮其热区（mouse_filter=IGNORE + 矩形不相交）。
##   4. 覆盖层不受语言模式影响：同一时间点无论中/英语言态都常显（本用例以「有字幕即显、
##      间隙即隐」的纯时间驱动断言，脚本内无语言开关分支）。
## 说明：本用例不真播放视频（无头下不解码），只测数据、纯函数与节点几何。
##   --script 无头模式 _initialize 阶段节点不在树内，add_child 后 await process_frame 再断言。

const JSON_PATH := "res://assets/animations/opening_subtitles_en.json"
const SCENE_PATH := "res://scenes/movie/opening_movie.tscn"
const VIDEO_DURATION := 59.56  # 开场动画.ogv 实测时长（秒）
const VIDEO_ASPECT := 16.0 / 9.0

var _subs: Array = []

func _initialize() -> void:
	print("== test_af_opening_subtitle ==")
	_test_json()
	_test_lookup()
	await _test_scene()
	finish()

# ---------------------------------------------------------------- ① 字幕数据
func _test_json() -> void:
	check(ResourceLoader.exists(JSON_PATH) or FileAccess.file_exists(JSON_PATH),
		"AF-1：英文字幕 JSON 存在")
	var f: FileAccess = FileAccess.open(JSON_PATH, FileAccess.READ)
	if f == null:
		return
	var raw: String = f.get_as_text()
	f.close()
	check(not raw.begins_with("\uFEFF"), "AF-1：JSON 无 BOM")
	var parsed: Variant = JSON.parse_string(raw)
	check(parsed is Dictionary, "AF-1：JSON 合法（parse_string 返回 Dictionary）")
	if not (parsed is Dictionary):
		return
	var root: Dictionary = parsed
	check(root.has("_说明"), "AF-1：含 _说明 字段")
	var note: Variant = root.get("_说明", null)
	if note is Array:
		check((note as Array).size() >= 2, "AF-1：_说明 为双语各一行（≥2 行）")
	var arr: Variant = root.get("subtitles", null)
	check(arr is Array, "AF-1：subtitles 为数组")
	if not (arr is Array):
		return
	_subs = arr
	check(_subs.size() > 0, "AF-1：字幕条数 > 0（实际 %d 条）" % _subs.size())

	var prev_end := 0.0
	var first_start := -1.0
	var last_end := -1.0
	var ok_shape := true
	var ok_mono := true
	var ok_len := true
	var ok_utf := true
	for i in _subs.size():
		var e: Variant = _subs[i]
		if not (e is Dictionary):
			ok_shape = false
			continue
		var d: Dictionary = e
		if not (d.has("start") and d.has("end") and d.has("en")):
			ok_shape = false
			continue
		var s: float = float(d["start"])
		var t: float = float(d["end"])
		var en: String = String(d["en"])
		if s < 0.0 or s >= t:
			ok_shape = false
		if s < prev_end:
			ok_mono = false
		if en.strip_edges() == "":
			ok_utf = false
		if en.length() > 90:
			ok_len = false
		prev_end = t
		if first_start < 0.0:
			first_start = s
		last_end = t
	check(ok_shape, "AF-1：每条含 start/end/en 且 0 ≤ start < end")
	check(ok_mono, "AF-1：区间单调不减、互不重叠（start_i ≥ end_(i-1)）")
	check(ok_utf, "AF-1：每条英文非空")
	check(ok_len, "AF-1：每条英文 ≤ 90 字符（过长则按原文案拆句）")
	check(first_start >= 0.0, "AF-1：首条 start ≥ 0")
	check(last_end <= VIDEO_DURATION + 0.5,
		"AF-1：末条 end ≤ 视频时长 + 0.5（末条 end=%.2f，时长=%.2f）" % [last_end, VIDEO_DURATION])

# ---------------------------------------------------------------- ② 查表边界
func _test_lookup() -> void:
	var scene: PackedScene = load(SCENE_PATH) as PackedScene
	if scene == null:
		check(false, "AF-2：opening_movie.tscn 可加载")
		return
	var probe: Node = scene.instantiate()
	if not probe.has_method("subtitle_at"):
		check(false, "AF-2：脚本提供查表函数 subtitle_at(t)")
		probe.free()
		return
	probe.call("_load_subtitles")
	var n: int = int(probe.call("subtitle_count"))
	check(n > 0, "AF-2：脚本内已载入字幕（%d 条）" % n)
	check_eq(String(probe.call("subtitle_at", 0.0)), "", "AF-2：t=0（首条之前）→ 空串")
	var first: Dictionary = probe.call("subtitle_entry", 0)
	var mid: float = (float(first["start"]) + float(first["end"])) * 0.5
	check_eq(String(probe.call("subtitle_at", mid)), String(first["en"]),
		"AF-2：首条中点 → 首条英文")
	check_eq(String(probe.call("subtitle_at", 4.50)), "", "AF-2：间隙（4.50s）→ 空串")
	check_eq(String(probe.call("subtitle_at", float(first["end"])), ), "",
		"AF-2：半开区间上界（首条 end）→ 空串")
	var last: Dictionary = probe.call("subtitle_entry", n - 1)
	var tail: float = (float(last["start"]) + float(last["end"])) * 0.5
	check_eq(String(probe.call("subtitle_at", tail)), String(last["en"]),
		"AF-2：末条中点 → 末条英文")
	check_eq(String(probe.call("subtitle_at", 70.0)), "", "AF-2：超时长（70s）→ 空串")
	check_eq(String(probe.call("subtitle_at", -1.0)), "", "AF-2：负时间（防御）→ 空串")
	# 覆盖层时间驱动（与语言模式无关）：有字幕即显、间隙即隐
	check(probe.has_method("refresh_subtitle_at"), "AF-2：脚本提供 refresh_subtitle_at(t)（纯时间驱动）")
	probe.free()

# ---------------------------------------------------------------- ③ 节点与几何
func _test_scene() -> void:
	var scene: PackedScene = load(SCENE_PATH) as PackedScene
	check(scene != null, "AF-3：opening_movie.tscn 存在可加载")
	if scene == null:
		return
	var movie: Node = scene.instantiate()
	# _ready 之前的「场景默认态」：覆盖层节点默认可见（不随语言态隐藏）
	var label_before: Node = movie.get_node_or_null("EnglishSubtitle")
	check(label_before is Label, "AF-3：EnglishSubtitle(Label) 存在")
	if label_before is Label:
		check((label_before as Label).visible, "AF-3：场景默认态覆盖层可见（非语言开关控制）")
	var container: Control = Control.new()
	container.size = Vector2(1280, 720)  # 与片源同尺寸，使播放器/覆盖层有确定几何
	add_child(container)
	container.add_child(movie)
	await process_frame  # _ready 于下一帧执行
	await process_frame  # 布局与查表再刷一帧

	var label: Label = movie.get_node_or_null("EnglishSubtitle") as Label
	var player: VideoStreamPlayer = movie.get_node_or_null("VideoStreamPlayer") as VideoStreamPlayer
	var skip_btn: Button = movie.get_node_or_null("SkipButton") as Button
	check(player != null, "AF-3：VideoStreamPlayer 仍在（覆盖层不替换播放器）")
	check(skip_btn != null, "AF-3：跳过按钮仍在（覆盖层不破坏既有控件）")
	if label == null:
		return

	# 白色字、字号可读、自动换行兜底
	var col: Color = label.get_theme_color("font_color")
	check(col.r > 0.9 and col.g > 0.9 and col.b > 0.9, "AF-3：字幕为白色（实际 %s）" % str(col))
	var fs: int = label.get_theme_font_size("font_size")
	check(fs >= 16 and fs <= 48, "AF-3：字号在可读区间 16..48（实际 %d）" % fs)
	check(label.autowrap_mode != TextServer.AUTOWRAP_OFF, "AF-3：开启自动换行（超宽折行不溢出）")
	check(label.max_lines_visible >= 1, "AF-3：限制最大行数（不无限增高）")
	check(label.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"AF-3：覆盖层鼠标穿透（不吞跳过按钮点击）")

	# 树序：覆盖层在跳过按钮之前 → 绘制在按钮之下
	var idx_label: int = label.get_index()
	var idx_skip: int = skip_btn.get_index() if skip_btn != null else -1
	check(idx_skip > idx_label, "AF-3：覆盖层树序在跳过按钮之前（绘制于其下层）")

	# 不遮跳过按钮热区
	if skip_btn != null:
		check(not label.get_global_rect().intersects(skip_btn.get_global_rect()),
			"AF-3：字幕矩形不与跳过按钮热区相交（label=%s skip=%s）"
			% [str(label.get_global_rect()), str(skip_btn.get_global_rect())])

	# 贴视频内容矩形（16:9 黑边解算），且确实落在内容区
	if player != null and movie.has_method("content_rect_for"):
		var box: Vector2 = player.size
		check(box.x > 0.0 and box.y > 0.0, "AF-3：播放器有尺寸（%s）" % str(box))
		var content: Rect2 = movie.call("content_rect_for", box)
		var content_global := Rect2(player.global_position + content.position, content.size)
		check(content_global.encloses(label.get_global_rect()),
			"AF-3：字幕矩形完全落在视频内容矩形内（content=%s label=%s）"
			% [str(content_global), str(label.get_global_rect())])
		# 位于中文烧录字幕（内容高度 0.888 以下）之下
		var ratio: float = (label.get_global_rect().position.y - content_global.position.y) / content_global.size.y
		check(ratio >= 0.88 and ratio <= 0.96,
			"AF-3：字幕落在中文字幕下方空隙（顶部位于内容高度 %.3f）" % ratio)

	# KEEP_ASPECT_CENTERED 解算纯函数：三种盒型
	if movie.has_method("content_rect_for"):
		var r169: Rect2 = movie.call("content_rect_for", Vector2(1920, 1080))
		check(r169.size.x == 1920 and r169.size.y == 1080 and r169.position == Vector2.ZERO,
			"AF-3：16:9 盒 → 内容铺满（无黑边）")
		var r43: Rect2 = movie.call("content_rect_for", Vector2(1920, 1200))
		check_eq(round(r43.size.y), 1080.0, "AF-3：4:3 盒 → 内容高按宽定 1080")
		check_eq(round(r43.position.y), 60.0, "AF-3：4:3 盒 → 上下各 60 黑边（垂直居中）")
		var r_sq: Rect2 = movie.call("content_rect_for", Vector2(1000, 1000))
		check_eq(round(r_sq.size.y), 563.0, "AF-3：方盒 → 内容高 562.5（按 16:9 定）")
		check(r_sq.position.x == 0.0 and round(r_sq.position.y) == 219.0,
			"AF-3：方盒 → 左右无黑边、上下各 218.75 黑边")

	# 版式容量：最长英文行在选定字号下的单行宽度 ≤ 字幕框宽（避免折成 3 行溢出空隙）
	var fnt: Font = label.get_theme_font("font")
	if fnt != null:
		var widest := 0.0
		var widest_line := ""
		for e in _subs:
			if not (e is Dictionary):
				continue
			var txt: String = String((e as Dictionary)["en"])
			var w: float = fnt.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if w > widest:
				widest = w
				widest_line = txt
		var line_h: float = fnt.get_height(fs)
		print("  [diag] 字号=%d 行高=%.1f 框=%s 最宽行=%.1f (%s)"
			% [fs, line_h, str(label.size), widest, widest_line])
		check(widest <= label.size.x,
			"AF-3：最长英文行 %.0fpx ≤ 字幕框宽 %.0fpx（单行不折）" % [widest, label.size.x])
		check(line_h * 2.0 <= label.size.y + 0.5,
			"AF-3：两行行高 %.0fpx ≤ 字幕框高 %.0fpx（两行仍容于空隙）" % [line_h * 2.0, label.size.y])

	# 时间驱动显隐（同一时间点在两种语言态下都常显 → 无语言分支）
	if movie.has_method("refresh_subtitle_at"):
		movie.call("refresh_subtitle_at", 2.90)
		check(label.visible and label.text != "", "AF-3：进入字幕区间 → 覆盖层显示且非空文本")
		movie.call("refresh_subtitle_at", 4.50)
		check(not label.visible and label.text == "", "AF-3：字幕间隙 → 覆盖层隐藏（空隙不留白字）")
		movie.call("refresh_subtitle_at", 2.90)
		check(label.visible, "AF-3：再次进入区间 → 覆盖层恢复显示（常显，不受语言态影响）")
		movie.call("refresh_subtitle_at", 70.0)
		check(not label.visible, "AF-3：超时长 → 覆盖层隐藏（防御越界）")

	movie.queue_free()
	container.queue_free()
