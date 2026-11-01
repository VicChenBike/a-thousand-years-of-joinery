extends Node
## I18n：游戏内中英文切换 autoload（中文原文即键）。
## 契约（任务书 §架构）：
##   ①中文原文即键——t(zh)：zh 语言原样返回 zh（既有全量测试 zh 基线零扰动）；en 查合并表，
##     未命中返回中文 + 每键恰一次 push_warning（_warned_keys 去重；get_warned_keys/
##     get_warned_count 观测口供无头测试断言）。
##   ②表 = assets/i18n/ui_en.json（{"_说明":[…术语表…],"翻译":{中文键: English}}，本批新建）
##     + assets/i18n/content_en.json（**只读**——另一实施者并行产出域：可能不存在→跳过不炸；
##     格式兼容两种形态：含「翻译」键取之，否则整对象视为词条表；"_" 前缀元数据键跳过）。
##     合并序=content_en 先、ui_en 后（**ui_en=UI 契约权威**，同键覆盖 content_en——
##     两表大量重叠〔实测 253 键；O-2 勘误 2026-11-01：初版注释误记 251，实以脚本核对
##     ui 318×content 259 交集=253〕，UI 文案以本批 ui_en 定稿为准；content_en 独有键照常生效）。
##   ③set_language/get_language + language_changed(lang) 信号；实时刷新（设置面板/主菜单
##     按钮/HUD 行组）由消费方订阅；其余场景 _ready 取值（重进生效）。
##   ④语言持久化=SaveManager settings.language（"zh"/"en"，缺省 zh；归一化防御在 save_manager
##     侧——本件 _ready 只读不写档，切换落盘由设置面板切换回调经 update_settings 承担）。
##   ⑤带参文案调用点用 % 格式化（键=整句模板，如 t("还需翻转 %d 次") % n）。
## 红线：不触碰 剧情对话/*.json 与 opening_movie.*（他人在改）；tscn 静态文字由各场景
## _ready 经 t() 覆写，本件不读 tscn。

signal language_changed(lang: String)

const UI_EN_PATH := "res://assets/i18n/ui_en.json"
const CONTENT_EN_PATH := "res://assets/i18n/content_en.json"

var _lang: String = "zh"
var _merged: Dictionary = {}        # 中文键 → English
var _warned_keys: Dictionary = {}   # 缺词告警去重（键 → true）
var _warned_count: int = 0          # 累计告警次数（观测口，测试断言「每键一次」用）

func _ready() -> void:
	_load_tables()
	_lang = _norm_lang(_read_saved_language())

## 启动语言恢复：读 SaveManager 内存档 settings.language（缺档/空档/字段缺→zh）。
## 手法=兄弟节点相对定位 + 私有成员 .get（save_manager._warn_future_readonly 先例；
## autoload _ready 推迟至树激活的 --script 时序下 SaveManager._data 可能为空——空档回 zh）。
func _read_saved_language() -> Variant:
	var parent_node: Node = get_parent()
	var sm: Node = parent_node.get_node_or_null("SaveManager") if parent_node != null else null
	if sm == null:
		return "zh"
	var data: Variant = sm.get("_data")
	if typeof(data) != TYPE_DICTIONARY or (data as Dictionary).is_empty():
		return "zh"
	var settings: Variant = (data as Dictionary).get("settings", null)
	if typeof(settings) != TYPE_DICTIONARY:
		return "zh"
	return (settings as Dictionary).get("language", "zh")

## 词条表加载（_ready 与测试显式调用两用；幂等重载）。
func _load_tables() -> void:
	_merged = {}
	_merge_file(CONTENT_EN_PATH)   # 并行实施者域：缺文件静默跳过（见 _merge_file）；先加载
	_merge_file(UI_EN_PATH)        # 后加载=UI 契约权威——同键覆盖 content_en（两表重叠 253 键实证；O-2 勘误：旧注 251 系误记）

## 单文件合并。缺文件=跳过（content_en.json 可能尚未落盘，机制对其落盘与否都正确）；
## 解析失败/非对象=告警跳过不中止；词条值非字符串丢弃（防脏数据污染表）。
func _merge_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("I18n 词条表打开失败：%s" % path)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("I18n 词条表格式非法（非 JSON 对象）：%s" % path)
		return
	var table: Variant = (parsed as Dictionary).get("翻译", parsed)
	if typeof(table) != TYPE_DICTIONARY:
		return
	for k: Variant in (table as Dictionary).keys():
		var key := String(k)
		if key.begins_with("_"):
			continue   # "_说明" 等元数据键跳过
		var v: Variant = (table as Dictionary)[k]
		if typeof(v) == TYPE_STRING:
			_merged[key] = v

## 核心查询：中文原文即键。zh 恒直通；en 命中返回英文；未命中返回中文+每键一次告警。
func t(zh: String) -> String:
	if _lang != "en" or zh.is_empty():
		return zh
	if _merged.has(zh):
		return String(_merged[zh])
	if not _warned_keys.has(zh):
		_warned_keys[zh] = true
		_warned_count += 1
		push_warning("I18n 缺英文词条：%s" % zh)
	return zh

## 切换语言（同值 no-op 零 emit；切换重置缺词告警去重——新语言会话重新登记）。
func set_language(lang: String) -> void:
	var n := _norm_lang(lang)
	if n == _lang:
		return
	_lang = n
	_warned_keys = {}
	_warned_count = 0
	language_changed.emit(n)

func get_language() -> String:
	return _lang

# ---------- 观测口（无头测试断言「未命中回退+一次性告警」用；生产零消费） ----------
func get_warned_keys() -> Array:
	return _warned_keys.keys()

func get_warned_count() -> int:
	return _warned_count

## 语言归一：只收 "zh"/"en" 字符串，其余（null/脏串/错类型）一律回 "zh"
##（save_manager._safe_bool 同族防御——绝不中止）。
static func _norm_lang(v: Variant) -> String:
	if typeof(v) == TYPE_STRING and ((v as String) == "zh" or (v as String) == "en"):
		return v as String
	return "zh"
