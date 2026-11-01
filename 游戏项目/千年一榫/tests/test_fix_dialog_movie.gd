extends "res://tests/test_base.gd"
## 对话/开场动画域审查缺陷修复 TDD 测试（独占文件：scenes/dialog/talk_controller.gd、
## scenes/movie/opening_movie.gd）：
##   P3 对话 speaker 类型守卫——`String(d.get("speaker",""))` 对显式 null/数组 4.7 运行期中止
##      （Nonexistent 'String' constructor）整段解析断链；修法=typeof 判 string 才用，否则回退 ""
##      落入既有「speaker 非法」分支整轮跳过并告警（不中止、后继轮保留）；
##   P3 opening_movie.gd `stream.get_length()`——4.7 VideoStream 无此 API（调用即 SCRIPT ERROR
##      中止 _ready → finished 连接与 play 都不执行）；修法=删除回退行，总时长只走
##      player.get_stream_length()。
## 纪律：解析段走 call_deferred 包裹（错误隔离在 deferred 链，防红跑 _initialize 中止挂死）；
## 零触碰 save.json；talk_controller 实例不入树（.new() 直用 + free，_parse_dialog_doc 无树依赖）。

const TC_SRC := "res://scenes/dialog/talk_controller.gd"
const MOVIE_TSCN := "res://scenes/movie/opening_movie.tscn"
const OM_SRC := "res://scenes/movie/opening_movie.gd"

# ---- deferred 桥：错误隔离在本包装调用内（旧实现在 _parse_dialog_doc 内中止 →
#      本链断 → _parse_ran 恒 false / 结果保持初值，判红；新实现正常走完）----
var _parse_ran: bool = false
var _parse_result: Array = []

func _do_parse(tc: Node, parsed: Variant, path: String) -> void:
	_parse_result = tc.call("_parse_dialog_doc", parsed, path)
	_parse_ran = true

func _reset_parse() -> void:
	_parse_ran = false
	_parse_result = []

func _initialize() -> void:
	print("== test_fix_dialog_movie ==")
	var tc: Node = (load(TC_SRC) as GDScript).new()  # 不入树（_parse_dialog_doc 无树依赖）

	# ==================== 段 1：P3 speaker 类型守卫 ====================
	print("-- 段1 P3 speaker 守卫 --")
	# 1a 显式 null speaker：坏轮跳过、后继「晷」轮保留
	_reset_parse()
	call_deferred("_do_parse", tc,
		{"rounds": [{"speaker": null, "texts": ["坏轮句子"]},
			{"speaker": "晷", "texts": ["有效句A"]}]},
		"res://tests/fixtures/_fixlvl_null.json")
	await process_frame
	await process_frame
	check(_parse_ran,
		"P3-6a：speaker=null 不中止解析（红=旧 String(null) 运行期中止 deferred 链；ran=%s）" % str(_parse_ran))
	if _parse_ran:
		check_eq(_parse_result.size(), 1,
			"P3-6b：null speaker 坏轮跳过、后继有效轮保留（实测 %d）" % _parse_result.size())
		if _parse_result.size() == 1:
			check_eq(String((_parse_result[0] as Dictionary).get("speaker", "")), "晷",
				"P3-6b2：保留轮 speaker=晷")
	# 1b 数组 speaker：同族守卫
	_reset_parse()
	call_deferred("_do_parse", tc,
		{"rounds": [{"speaker": ["晷"], "texts": ["数组轮"]},
			{"speaker": "我", "texts": ["有效句B"]}]},
		"res://tests/fixtures/_fixlvl_arr.json")
	await process_frame
	await process_frame
	check(_parse_ran,
		"P3-6c：speaker=数组 不中止解析（红=旧同族中止；ran=%s）" % str(_parse_ran))
	if _parse_ran:
		check_eq(_parse_result.size(), 1, "P3-6d：数组 speaker 坏轮跳过、后继「我」轮保留")
		if _parse_result.size() == 1:
			check_eq(String((_parse_result[0] as Dictionary).get("speaker", "")), "我",
				"P3-6d2：保留轮 speaker=我")
	# 1c 回归：全合法档直接解析（两实现均应通过）
	var ok_direct: Variant = tc.call("_parse_dialog_doc",
		{"rounds": [{"speaker": "晷", "texts": ["仅一句"]}]}, "res://tests/fixtures/_fixlvl_ok.json")
	check(ok_direct is Array and (ok_direct as Array).size() == 1,
		"P3-6e：全合法档解析回归（1 句）")
	# 1d 告警留痕（doc_warnings 收口）
	var warns: Variant = tc.get("doc_warnings")
	check(warns is Array and (warns as Array).size() >= 2,
		"P3-6f：坏轮告警登记 doc_warnings（实测 %d 条）" %
			((warns as Array).size() if warns is Array else -1))
	tc.free()

	# ==================== 段 2：P3 opening_movie get_length 回退行 ====================
	print("-- 段2 P3 opening_movie --")
	var om_src: String = FileAccess.get_file_as_string(OM_SRC)
	check(not om_src.contains("stream.get_length()"),
		"P3-8a：stream.get_length() 回退行已删（4.7 不存在 API；红=源码仍含）")
	check(om_src.contains("player.get_stream_length()"),
		"P3-8b：总时长只走 player.get_stream_length()")
	var movie: Node = (load(MOVIE_TSCN) as PackedScene).instantiate()
	add_child(movie)
	await process_frame
	var pl: Variant = movie.get_node_or_null("VideoStreamPlayer")
	check(pl is VideoStreamPlayer and (pl as VideoStreamPlayer).stream != null,
		"P3-8c：流装载在位（_ready 走到挂流）")
	if pl is VideoStreamPlayer:
		check((pl as VideoStreamPlayer).finished.get_connections().size() >= 1,
			"P3-8d：finished 已连接（_ready 未被中止）")
	check(float(movie.get("_total_time")) >= 0.0,
		"P3-8e：_total_time 已赋值（实测 %.2f）" % float(movie.get("_total_time")))
	movie.queue_free()
	await process_frame
	finish()
