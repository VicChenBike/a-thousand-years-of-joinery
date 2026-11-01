class_name BubbleLinesBag
extends RefCounted
## 批次 Y（Y-C8，spec §9.2 拍板 8）：见证者气泡台词洗牌袋抽取器。
## 契约：整轮不重复（轮内每句恰抽一次）、轮尽重洗（袋空即重灌+重排）、池大小任意
## （1 句也可，退化为恒抽取唯一句）；缺文件/空池/非法 JSON/类型错防御=next_line() 返回
## 空串（上层不弹气泡）+ push_warning 告警不崩（告警同步登记 load_warnings 供无头断言）。
## 台词文件：res://剧情对话/气泡_第N关.json（Y4 域交付，格式={_说明, lines:[字符串数组]}；
## 顶层数组宽容兼容）。替换旧顺序轮换 WITNESS_BUBBLE_LINES[_witness_bubble_line % 8]
## （level_scene.gd 旧 8 条数组退役留痕注释保留）。
## 测试：tests/test_y5_bubble_bag.gd（夹具=tests/fixtures/bubble_y5_*.json，不入 剧情对话/）。

const DEFAULT_PATH_FMT := "res://剧情对话/气泡_第%d关.json"

var _pool: Array = []            # 句子池（本轮基准，全 String）
var _bag: Array = []             # 洗牌袋（轮内待抽；空=轮尽→重灌重排）
var _rng := RandomNumberGenerator.new()
var load_warnings: Array = []    # 防御告警登记（与 push_warning 同步，无头断言用）

func _init() -> void:
	_rng.randomize()

## 测试/走查钩子：固定随机种子（洗牌序确定，断言可复现）。
func seed_for_test(seed_val: int) -> void:
	_rng.seed = seed_val

## 章节默认路径（唯一真值；level_scene 经此取档，不重复落常量）。
static func path_for_chapter(chapter: int) -> String:
	return DEFAULT_PATH_FMT % clampi(chapter, 1, 5)

## 加载台词文件。返回 true=池非空可用；false=缺文件/解析失败/格式错/空池（均已告警）。
func load_path(path: String) -> bool:
	load_warnings.clear()
	_pool.clear()
	_bag.clear()
	if not FileAccess.file_exists(path):
		_warn("气泡台词文件缺失，见证者气泡停用（不弹不崩）: %s" % path)
		return false
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		# 顶层数组宽容兼容（字符串数组直排形态）
		if parsed != null and typeof(parsed) == TYPE_ARRAY:
			return _accept_lines(parsed, path)
		_warn("气泡台词文件解析失败或顶层非对象/数组: %s" % path)
		return false
	var raw: Variant = (parsed as Dictionary).get("lines", null)
	if raw == null or typeof(raw) != TYPE_ARRAY:
		_warn("气泡台词文件缺 lines 数组（需 {\"_说明\":…, \"lines\":[…]}）: %s" % path)
		return false
	return _accept_lines(raw, path)

func _accept_lines(raw: Array, path: String) -> bool:
	for v: Variant in raw:
		if typeof(v) == TYPE_STRING and String(v) != "":
			_pool.append(String(v))
	if _pool.is_empty():
		_warn("气泡台词池为空（无有效字符串句）: %s" % path)
		return false
	return true

func pool_size() -> int:
	return _pool.size()

## 当前池副本（测试断言用；改内池防外泄）。
func pool() -> Array:
	return _pool.duplicate()

func remaining_in_round() -> int:
	return _bag.size()

## 抽取一句：整轮不重复、轮尽重洗（Fisher-Yates）。池空 → ""（上层不弹）。
func next_line() -> String:
	if _pool.is_empty():
		return ""
	if _bag.is_empty():
		_bag = _pool.duplicate()
		for i: int in range(_bag.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var tmp: String = _bag[i]
			_bag[i] = _bag[j]
			_bag[j] = tmp
	return String(_bag.pop_back())

func _warn(msg: String) -> void:
	load_warnings.append(msg)
	push_warning(msg)
