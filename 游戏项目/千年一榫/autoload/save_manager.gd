extends Node
## SaveManager：单存档 + 自动保存；天赋值/皮肤/重玩计数/首次标记。依据 spec 7.1~7.3。

signal settings_changed
signal talent_changed(new_total: int)
signal skin_changed(equipped_id: String)
signal progress_changed

const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const BAK_PATH := "user://save.json.bak"  # P0-6（批次 W 规格 §2）：.bak 回退档（save_game 腾位序产物）
# N9（2026-09-09 spec §6.11）：save_version 1→2——新增「挖除断点」progress.level_progress
# （按章存 deleted_cells 差集）；v1 旧档 load_game 无损迁移（缺字段补默认值，见 load_game 迁移留痕）。
const SAVE_VERSION := 2
const SKIN_PRICE := 205
const DEFAULT_UDP_PORT := 9876  # 基准端口 P：手势 JSON=P、摄像头 JPEG=P+1、控制=P+2（批次 R spec §3.3 定稿）
const REPLAY_AWARD_LIMIT := 3
# W9-1（批次 AA 规格 §12 P2-2）：Game.State.LEVEL 镜像常量（enum 序 BOOT/MM/MOVIE/TALK/
# LEVEL/SETTLE/CATALOG = 4）。SaveManager 加载序先于 Game，为避免依赖 autoload 全局名注册时序
# 不引用 `Game.` 标识符，改用本镜像常量 + get_node_or_null("Game")（既有 _warn_future_readonly
# 同款口径）；真值由 tests/test_aa_defects.gd W9-1-s5 断言 == Game.State.LEVEL（防枚举序漂移）。
const STATE_LEVEL := 4

var _data: Dictionary = {}
# P0-8（批次 W 规格 §2）：未来版本只读锁——parsed_ver>SAVE_VERSION 置位，内存默认档运行、
# save_game() 早退不覆写不重置（主档与 .bak 原样保留等升级），ready 后经 Game.toast 延帧提示。
var _future_readonly: bool = false
# P0-8：迁移函数表（下标=from_ver，逐级链式调用至 SAVE_VERSION；_init 装配实例 Callable）。
var _MIGRATIONS: Array = []
# P0-8：未来版本只读锁的用户可见提示文案（规格 §2 原文）。
const FUTURE_READONLY_TOAST := "存档来自更新版本，本次运行进度不会保存"

func _init() -> void:
	# 下标=from_ver（规格 §2 P0-8）：v0 无迁移（首档即 v1）→ 下标 0 恒 null 占位；
	# _MIGRATIONS[1]=v1→v2。未来版本在表尾追加 _migrate_vN_to_vNp1（下标=N）。
	_MIGRATIONS = [null, Callable(self, "_migrate_v1_to_v2")]

func _ready() -> void:
	load_game()
	# 退出前自动保存兜底（无头模式下可能无窗口，须判空）；W9-1（批次 AA 规格 §12 P2-2）：
	# close_requested 改接统一收口 _on_close_requested——与 main.gd:_quit_now_shared 逐条同构
	# （save_game 先、LEVEL 态显式 flush_checkpoint 后），保证「Alt+F4/任务栏关闭/系统关机」与
	# 「自绘 × 确认退出」两条退出路径的断点落盘等级一致（红测 test_aa_defects W9-1 段）。
	var w: Window = get_tree().root.get_window()
	if w != null:
		w.close_requested.connect(_on_close_requested)

## W9-1（批次 AA 规格 §12 P2-2）窗口系统级关闭收口：与 main.gd:_quit_now_shared 同序同构。
## 系统级关闭（Alt+F4/任务栏关闭/系统关机）不经自绘 × 确认链，故至少保证两条硬底线：
## ①全局 save_game 兜底；②LEVEL 态显式 flush_checkpoint（2s 防抖窗内的未落断点立即落盘，
## 消除「关闭前 2 秒内挖除丢失」窗口）。_settled 守卫由 flush_checkpoint 内建（通关态不重写）。
func _on_close_requested() -> void:
	save_game()
	if not is_inside_tree():
		return
	var parent_node: Node = get_parent()
	var game: Variant = parent_node.get_node_or_null("Game") if parent_node != null else null
	if game == null:
		return  # Game 未就绪（极端时序）：只保留全局 save_game 兜底，不中止
	if int(game.call("current_state")) != STATE_LEVEL:
		return
	var lvl: Variant = game.call("get_current_scene")
	if lvl != null and (lvl as Node).has_method("flush_checkpoint"):
		lvl.call("flush_checkpoint")

# ---------- 基础 ----------
func _default_data() -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		# N10（2026-09-09）：progress 新增 watched_opening（看过开场动画）——图鉴门控判据②，
		# 与易失旁路 flag 解耦（用户五路径实测：通关/看过动画后 flag 被开发工具误清致图鉴打不开）。
		# N9（2026-09-09 spec §6.11）：progress 新增 level_progress——挖除断点，按章存
		# {"<chapter>": {"deleted_cells": ["x,y,z",...]}}（deleted_cells=初始 blocks−当前 remaining，
		# 只存删了哪些格；键缺省/空数组=「没动记没改」，通关时该章键删除=断点作废）。
		"progress": {"cleared": [], "next_chapter": 1, "watched_opening": false, "level_progress": {}},
		"settings": {
			"gesture_input": true, "kb_input": true,
			"gesture_hud_visible": true, "gesture_hud_offset": [0, 0],
			# 批次 R（spec §8.4）+2 字段：摄像头子开关（Q2/Q3 语义）与控制台说明栏折叠记忆
			"gesture_camera_enabled": true, "gesture_panel_folded": false,
			# 批次 V-D（2026-09-19 规格 §6.2/§8，派遣口径）：摄像头设备记忆三键（V3/V17）。
			# 防御性缺省：未记忆 ""/设备默认 ""/默认 0；旧档缺键经 load_game 归一补齐（见该处留痕），
			# 类型防御同处——save_version 维持 2 不动迁移记账（规格 §1.2-8）。
			"gesture_camera_device": "", "gesture_camera_res": "", "gesture_camera_fps": 0,
			# I18n（游戏内中英文切换）：界面语言 "zh"/"en"，缺省 zh；归一化见 _normalize_loaded_data
			# （_safe_language 同族防御——非法值/null 回 zh；save_version 维持 2 不触发迁移记账，
			# 旧档缺键经归一补齐，与 gesture_camera_* 三键同款口径）。
			"language": "zh",
			"volume": {"master": 1.0, "music": 1.0, "sfx": 1.0},
			# P2-3a（批次 W 规格 §3）：udp_port **deprecated 退役**——不再被任何消费方读取
			# （gesture_bridge.get_udp_port() 恒常量 9876 派生，与 launcher 环境变量默认语义恒
			# 一致；旧实现读本键、存档被改后双方互不通）。键保留不删不迁移（旧档兼容 + 防未知
			# 键告警，load_game 归一照旧），仅退役消费；历史脏值无副作用。
			"udp_port": 0,
		},
		"talent": 500,  # A7（J1-4）：初始天赋值 0→500，便于体验锐眼（50/0.5s）扣费
		# K-D（K3-5）：初始即拥有并穿戴「开头」原创皮肤；preferred=玩家自选（默认开头），与 equipped 对齐。
		"skins": {"owned": ["skin_default", "skin_origin_kaitou"], "equipped": "skin_origin_kaitou", "preferred": "skin_origin_kaitou"},
		"replay_award_counts": {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0},
	}

func load_game() -> void:
	_future_readonly = false
	_data = _default_data()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed: Variant = _read_and_parse_save(SAVE_PATH)
	var parsed_ver: int = _parsed_save_version(parsed)
	# P0-8（批次 W 规格 §2）版本裁决：parsed_ver>SAVE_VERSION 一律只读锁，主档与 .bak 同判，
	# **不**进 .bak 回退——v3 主档若被 v2 可载的 .bak 顶掉，升级回退时用户新数据反被旧档覆盖
	# 并写回；未来版本必须保主档原样等升级。内存用默认档运行、save_game() 早退零写盘。
	if parsed_ver > SAVE_VERSION:
		_enter_future_readonly()
		return
	# N9：接受 v1~v2（v1 旧档迁移后继续用，不再直接重置——无损升级是验收硬指标）
	if parsed_ver >= 1:
		_data = parsed
		_normalize_loaded_data()
		_apply_migrations(parsed_ver)
		_clear_bak_best_effort()  # P0-6 验收③：主档载入成功 → .bak 冗余即清
		return
	# P0-6：主档解析失败/打不开/parsed_ver<1 → 改读 SAVE_PATH+".bak"（主档文件保持原样不删不改写）
	push_warning("主档损坏或版本非法（ver=%d），尝试回退 .bak" % parsed_ver)
	if not FileAccess.file_exists(BAK_PATH):
		push_warning("无 .bak 可回退，使用默认存档")
		return
	var bak_parsed: Variant = _read_and_parse_save(BAK_PATH)
	var bak_ver: int = _parsed_save_version(bak_parsed)
	if bak_ver > SAVE_VERSION:
		_enter_future_readonly()  # .bak 同判：未来版本备份同样只读锁（验收④：.bak 原样保留）
		return
	if bak_ver >= 1:
		_data = bak_parsed
		_normalize_loaded_data()
		_apply_migrations(bak_ver)
		push_warning("已从 .bak 恢复存档，回写修复主档")
		if save_game():
			_clear_bak_best_effort()  # 修复成功：.bak 已升级为主档，冗余即清；失败则保留待下次恢复
		else:
			push_warning(".bak 回写主档失败（.bak 保留，下次启动再试恢复）")
	else:
		push_warning(".bak 亦损坏或版本非法，重置为默认存档")

## P0-6 读入+解析助手：打不开/解析失败统一返回 null（调用方按「不可载」处理，坑⑪安全）。
func _read_and_parse_save(path: String) -> Variant:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("存档打开失败：%s" % path)
		return null
	var text: String = f.get_as_text()
	f.close()
	return JSON.parse_string(text)

## P0-6/P0-8 版本判读：非字典/键缺/null → -1（<1=不可载）；int("2") 字符串版本口径与旧实现一致。
## W9-3（批次 AA 规格 §12 P3-4）类型防御：`int(v)` 对 Array/Dictionary/Bool 等非数值类型属
## 「Nonexistent 'int' constructor」族运行期中止（4.7 探针实证）——load_game 会在此中止、_data
## 停在默认档，留下「默认档覆盖真实档」的下次写盘窗口。故非 int/float/合法数字串一律回落 -1
## （=走 .bak/默认档路径）+ push_warning 留痕，绝不中止。
func _parsed_save_version(parsed: Variant) -> int:
	if typeof(parsed) != TYPE_DICTIONARY:
		return -1
	var v: Variant = (parsed as Dictionary).get("save_version", -1)
	if v == null:
		return -1
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT:
		return int(v)
	if typeof(v) == TYPE_STRING and (v as String).strip_edges().is_valid_int():
		return int(v)
	push_warning("存档 save_version 类型非法（%s），按损坏档处理" % type_string(typeof(v)))
	return -1

## P0-6：.bak 清理（best-effort；失败仅告警不影响本次运行）。
func _clear_bak_best_effort() -> void:
	if FileAccess.file_exists(_bak_abs()) and DirAccess.remove_absolute(_bak_abs()) != OK:
		push_warning(".bak 清理失败（忽略，不影响本次运行）")

func _bak_abs() -> String:
	## :137 bak_abs 派生口径单源复用（save_game 腾位序与 load_game .bak 回退同源）。
	return ProjectSettings.globalize_path(BAK_PATH)

## 修复批 P2-①：安全数值封装（与 _parsed_save_version 同族防御，作用面=载入归一全读点）。
## int() 对 null/Array/Dictionary/Bool 属 4.7「Nonexistent 'int' constructor」运行期中止族
## （红测实证：中止 _normalize_loaded_data 后 _data 半归一、get_talent 连环炸）——
## 只收 int/float/合法整数串（JSON 数字回读恒 float），其余一律回落缺省，绝不中止。
static func _safe_int(v: Variant, def: int) -> int:
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT:
		return int(v)
	if typeof(v) == TYPE_STRING and (v as String).strip_edges().is_valid_int():
		return int(v)
	return def

## 修复批 P2-①：安全布尔封装——bool() 对 null 属同族中止（main.gd boot 传染点原形
## bool(_boot_settings.get("gesture_input",true)) 在键存在值为 null 时缺省不生效即炸）。
## 只收 bool 直通 / int 0·1 兼容手写档，其余回落缺省。
static func _safe_bool(v: Variant, def: bool) -> bool:
	if typeof(v) == TYPE_BOOL:
		return v
	if typeof(v) == TYPE_INT:
		return v != 0
	return def

## I18n：安全语言封装——只收 "zh"/"en" 字符串字面量，其余一律回 "zh"（_safe_bool 同族
## 风格：绝不中止；null/"fr"/错类型全落缺省）。实现复用 I18n._norm_lang 单源语义
## （此处独立静态实现——save_manager 加载序先于 I18n，不引用其全局名，与 STATE_LEVEL
## 镜像常量同款时序口径）。
static func _safe_language(v: Variant) -> String:
	if typeof(v) == TYPE_STRING and ((v as String) == "zh" or (v as String) == "en"):
		return v as String
	return "zh"

## 载入归一（全版本普适段，原 load_game 内联段收编）：JSON 数字 int 归一 + 容器类型防御
## （P0-7：progress/replay_award_counts/skins 对齐 settings 防御先例——脏类型**整体回落该域
## 默认值**+push_warning，绝不中止）+ settings 防御归一（原 :94-113 原样）+ v2 字段幂等归一。
## watched_opening/level_progress/skins-K-D 归一为**全版本普适**（既有 N9-A19/A27 断言锁定
## v2 档 load 归一 + 坑⑦ null 防护），不随迁移链只在 v1 生效；迁移体内显式重放同款助手（幂等）。
## 修复批 P2-①（2026-09-26，独立审查确认）：本函数内全部数值/布尔读取改经 _safe_int/
## _safe_bool 安全封装（裸 int()/bool() 对 JSON null/错类型属 4.7「Nonexistent constructor」
## 运行期中止族——红测实证 int(null) 中止本函数后 _data 停在半归一态、下游 get_talent/
## boot 门控连环炸）；并补 gesture_input/gesture_hud_visible 归一（原完全不在清单，
## 键存在值为 null 时 main.gd boot 的 .get 缺省不生效 → bool(null) 中止 boot 后半黑屏卡 BOOT）。
func _normalize_loaded_data() -> void:
	var p_v: Variant = _data.get("progress", null)
	if typeof(p_v) != TYPE_DICTIONARY:
		push_warning("存档 progress 域类型非法，整体回落默认")
		p_v = _default_data()["progress"]
		_data["progress"] = p_v
	var p: Dictionary = p_v
	# JSON 数字统一按 float 解析，读回后还原契约要求的 int 类型（spec 7.1 字段表）。
	# P2-①：容器非 Array 整域回默认；逐项只收 int/float/合法整数串（null/bool/脏串丢弃，
	# 绝不 int(null) 中止——红测 test_fix_save_normalize A3 锁定 [1,2]）。
	var cleared: Array = []
	var cleared_raw: Variant = p.get("cleared", [])
	if cleared_raw is Array:
		for c: Variant in cleared_raw:
			if typeof(c) == TYPE_INT:
				cleared.append(c)
			elif typeof(c) == TYPE_FLOAT:
				cleared.append(int(c))
			elif typeof(c) == TYPE_STRING and (c as String).strip_edges().is_valid_int():
				cleared.append(int(c))
	p["cleared"] = cleared
	p["next_chapter"] = _safe_int(p.get("next_chapter", 1), 1)
	_normalize_progress_v2_fields(p)
	_data["progress"] = p  # 回写防御：手写档缺 progress 键时补齐（默认档含该键）
	_data["talent"] = _safe_int(_data.get("talent", 500), 500)  # 回读兜底与 _default_data 一致（J1-4）
	var counts_v: Variant = _data.get("replay_award_counts", null)
	if typeof(counts_v) != TYPE_DICTIONARY:
		push_warning("存档 replay_award_counts 域类型非法，整体回落默认")
		counts_v = _default_data()["replay_award_counts"]
		_data["replay_award_counts"] = counts_v
	var counts: Dictionary = counts_v
	for k: String in counts.keys():
		counts[k] = _safe_int(counts[k], 0)
	# 设置域容器防御（V-D，4.7 坑 2：dict 取键一律 .get——手写档缺 settings 键/类型不对时
	# 无效下标会中止调用方 _initialize；容器失效即整体回落默认设置档，逐字段归一重建）。
	var s: Variant = _data.get("settings", null)
	if typeof(s) != TYPE_DICTIONARY:
		s = _default_data()["settings"]
	_data["settings"] = s
	s["udp_port"] = _safe_int(s.get("udp_port", 0), 0)
	# 批次 R（spec §8.4）：两新字段防御归一（旧档缺键补默认；save_version 维持 2 不触发迁移记账）
	s["gesture_camera_enabled"] = _safe_bool(s.get("gesture_camera_enabled", true), true)
	s["gesture_panel_folded"] = _safe_bool(s.get("gesture_panel_folded", false), false)
	# 修复批 P2-①：补两键归一（原完全不在清单）——归一后恒 TYPE_BOOL，传染点
	# main.gd boot/HUD 门读到的一定是 bool（bool(null) 中止族根除）。
	s["gesture_input"] = _safe_bool(s.get("gesture_input", true), true)
	s["gesture_hud_visible"] = _safe_bool(s.get("gesture_hud_visible", true), true)
	# 批次 V-D（规格 §6.2/§8 派遣口径）：摄像头设备记忆三键防御归一——旧档缺键补缺省；
	# 类型不对回落缺省（device/res 仅 String；fps 接受 int/float——JSON 往返数字恒 float，
	# int() 归一，字符串/布尔等非法值回落 0）。未知键保守保留不误伤（update_settings 合并
	# 路径对三键透明）。
	var dev: Variant = s.get("gesture_camera_device", "")
	s["gesture_camera_device"] = dev if typeof(dev) == TYPE_STRING else ""
	var res_v: Variant = s.get("gesture_camera_res", "")
	s["gesture_camera_res"] = res_v if typeof(res_v) == TYPE_STRING else ""
	var fps_v: Variant = s.get("gesture_camera_fps", 0)
	s["gesture_camera_fps"] = int(fps_v) if (typeof(fps_v) == TYPE_INT or typeof(fps_v) == TYPE_FLOAT) else 0
	# I18n：language 归一——旧档缺键补 "zh"；非 "zh"/"en" 字符串（含 null/脏类型）回 "zh"
	#（_safe_bool 同族防御，绝不中止；save_version 维持 2 不触发迁移记账）。
	s["language"] = _safe_language(s.get("language", "zh"))
	# W9-6（批次 AA 规格 §12 P3-7）：settings.volume 域级回落——归一段对 progress/skins/
	# replay_award_counts 均有域级防御，唯独 volume 缺失（audio_manager.apply_volumes 的
	# typed Dictionary 赋值遇 `[]` 会「Trying to assign Array to Dictionary」中止）。
	# 口径（规格 §12 P3-7 原文）：非字典 → 整域回落默认；子键非数值 → 该键默认 1.0。
	var vol_v: Variant = s.get("volume", null)
	if typeof(vol_v) != TYPE_DICTIONARY:
		push_warning("存档 settings.volume 域类型非法，整体回落默认")
		vol_v = (_default_data()["settings"] as Dictionary)["volume"]
	var vol: Dictionary = vol_v
	var vol_def: Dictionary = (_default_data()["settings"] as Dictionary)["volume"]
	for vk: String in ["master", "music", "sfx"]:
		var vv: Variant = vol.get(vk, vol_def.get(vk, 1.0))
		if typeof(vv) != TYPE_INT and typeof(vv) != TYPE_FLOAT:
			vol[vk] = float(vol_def.get(vk, 1.0))
		else:
			vol[vk] = float(vv)
	s["volume"] = vol
	var skins_v: Variant = _data.get("skins", null)
	if typeof(skins_v) != TYPE_DICTIONARY:
		push_warning("存档 skins 域类型非法，整体回落默认")
		skins_v = _default_data()["skins"]
		_data["skins"] = skins_v
	_normalize_skins_kd(skins_v)

## v2 字段幂等归一（原 :82/:87 内联段收编）：N10 watched_opening 缺省 false（null 判空防坑⑦）+
## N9 level_progress 防御归一（条目去重/排序/非法丢弃）。v1 由迁移体语义调用、v2+ 作普适防御。
func _normalize_progress_v2_fields(p: Dictionary) -> void:
	var w_v: Variant = p.get("watched_opening", false)
	p["watched_opening"] = false if w_v == null else bool(w_v)
	p["level_progress"] = _normalize_level_progress(p.get("level_progress", {}))

## K-D skins 幂等归一（原 :114-126 内联段收编，坑⑦⑩ 防护加固）：先 equipped 有效性回退，
## 再 preferred=equipped（缺/空/非字符串回落），owned 补开头原创（幂等）。
## 调用前置：skins 容器已由普适段防御为 Dictionary。
func _normalize_skins_kd(skins: Dictionary) -> void:
	var owned_v: Variant = skins.get("owned", [])
	var owned_arr: Array = owned_v if (owned_v is Array) else []
	if not owned_arr.has(skins.get("equipped", "")):
		skins["equipped"] = "skin_default"
	var equipped_v: Variant = skins.get("equipped", "skin_default")
	var equipped_s: String = equipped_v if typeof(equipped_v) == TYPE_STRING else "skin_default"
	var pref_v: Variant = skins.get("preferred", "")
	var pref_s: String = pref_v if typeof(pref_v) == TYPE_STRING else ""
	if pref_s == "":
		skins["preferred"] = equipped_s
	if not owned_arr.has("skin_origin_kaitou"):
		owned_arr.append("skin_origin_kaitou")
	skins["owned"] = owned_arr

# ---------- P0-8：save_version 迁移框架（批次 W 规格 §2） ----------
func _migrate_v1_to_v2() -> void:
	## v1→v2 迁移体（规格 §2 P0-8 口径：watched_opening + level_progress 归一/版本记账 +
	## skins K-D，自 load_game 内联迁移段收编）。归一助手与普适防御段共用（幂等——v1 载入时
	## 普适段已归一过，此处显式重放=迁移体语义自洽）；真正的版本动作=版本记账升 2，
	## 下次落盘即 v2 格式（文件是否立刻回写交由后续自然保存承担，与 preferred 迁移先例一致）。
	var p: Dictionary = _data.get("progress", {})
	_normalize_progress_v2_fields(p)
	_data["progress"] = p
	var sk: Dictionary = _data.get("skins", {})
	_normalize_skins_kd(sk)
	_data["skins"] = sk
	_data["save_version"] = SAVE_VERSION  # 版本记账（原 :88）

## P0-8 迁移链执行（调用前置：parsed_ver 已判 ∈[1,SAVE_VERSION]）；未来版本在表尾追加迁移体。
func _apply_migrations(from_ver: int) -> void:
	for v: int in range(maxi(from_ver, 1), SAVE_VERSION):
		if v >= _MIGRATIONS.size() or _MIGRATIONS[v] == null:
			push_warning("缺少 save_version %d→%d 迁移体，数据保持原样" % [v, v + 1])
			continue
		(_MIGRATIONS[v] as Callable).call()

# ---------- P0-8：未来版本只读锁（W0 §一 P0-6 裁决） ----------
func _enter_future_readonly() -> void:
	_future_readonly = true
	_data = _default_data()  # 内存用默认档运行（磁盘零触碰——主档与 .bak 原样保留等升级）
	push_warning("存档版本高于当前程序（ver>%d），本次运行只读不落盘" % SAVE_VERSION)
	if is_inside_tree():
		_notify_future_readonly()  # 延帧协程（fire-and-forget；Game/Toast 通道就绪后下发）
	else:
		_warn_future_readonly()

## P0-8 用户可见提示通道：延帧等 Game/main 注入 toast 体系后再下发（SaveManager autoload
## 时序先于 Game，ToastCenter/TopStrip 由 main.gd 注入更晚）；Game 不可达时降级 push_warning
## 落 Godot 日志（信息可达性，不静默丢弃）。
func _notify_future_readonly() -> void:
	if not is_inside_tree():
		return
	for i: int in range(3):
		await get_tree().process_frame
	_warn_future_readonly()

func _warn_future_readonly() -> void:
	# P2-1 回修（W1 独立审查）：绝对路径 get_node 在「active scene tree 未激活」（--script
	# 无头 _initialize 阶段）报引擎 ERROR 噪声——经父节点相对定位（gesture_bridge.get_udp_port
	# 先例：autoload/测试实例的父节点恒为 root）；不在树内（协程迟到恢复等）早退降级日志双保险。
	if not is_inside_tree():
		push_warning(FUTURE_READONLY_TOAST + "（不在场景树内，降级日志）")
		return
	var parent_node: Node = get_parent()
	var game: Node = parent_node.get_node_or_null("Game") if parent_node != null else null
	if game != null and game.has_method("toast"):
		game.call("toast", I18n.t(FUTURE_READONLY_TOAST), "warn", 5.0, true)   # I18n：玩家可见通道 t()（日志通道保持原文）
	else:
		push_warning(FUTURE_READONLY_TOAST + "（Game 未就绪，降级日志）")

## 单文件原子写（V-D，规格 §8.1；镜像编辑器 level_slots.gd:168-191 成熟序）：
## 写同目录 tmp → rename 覆盖 save.json → rename 失败时旧档改名 .bak 腾位 → rename tmp →
## 成功清 .bak / 失败回滚 .bak（本 Godot 4.7 实证：正常保存 rename 直换成功，.bak 序仅在
## rename 失败〔目标被目录占位/句柄锁定等〕时启用；tests/test_v_save_domain.gd 头注探针留痕）。
## 任何失败路径：旧档保全、残留尽力清理、push_warning（既有错误通知通道）并返回 false；
## 全程不抛异常。save.json 被同名目录占位（编辑器 P2-4 同款注入）→ 确定性 false。
func save_game() -> bool:
	if _future_readonly:
		# P0-8：未来版本只读锁——早退不覆写不重置（主档与 .bak 原样保留等升级，规格 §9-5
		# 「锁存时 save_game 零写盘」红线）；静默返回 false（用户提示已由 _enter_future_readonly
		# 一次性经 Game.toast 下发，防每次自动保存重复刷警告）。
		return false
	var save_abs: String = ProjectSettings.globalize_path(SAVE_PATH)
	var tmp_abs: String = save_abs + ".tmp"
	var bak_abs: String = _bak_abs()  # P0-6：bak_abs 派生口径单源复用（与 load_game 回退同源）
	if DirAccess.dir_exists_absolute(save_abs):
		push_warning("存档写入失败（save.json 被同名目录占位）")
		return false
	var text := JSON.stringify(_data, "\t")
	if not _write_text_flushed(tmp_abs, text):
		DirAccess.remove_absolute(tmp_abs)  # 残留尽力清（目录占位清不掉时留待人工，旧档未动）
		push_warning("存档写入失败（tmp 落盘失败，旧档未动）")
		return false
	if DirAccess.rename_absolute(tmp_abs, save_abs) != OK:
		# rename 失败 → .bak 腾位序（旧档先改名，消除「先删旧再改名」的丢档窗口；
		# 腾位失败即放弃，旧档未动）
		if FileAccess.file_exists(bak_abs) and DirAccess.remove_absolute(bak_abs) != OK:
			DirAccess.remove_absolute(tmp_abs)
			push_warning("存档写入失败（.bak 残留无法清理，旧档未动）")
			return false
		if DirAccess.rename_absolute(save_abs, bak_abs) != OK:
			DirAccess.remove_absolute(tmp_abs)
			push_warning("存档写入失败（旧档改名失败，旧档未动）")
			return false
		if DirAccess.rename_absolute(tmp_abs, save_abs) != OK:
			# W9-4（批次 AA 规格 §12 P3-5）：回滚 rename 返回值必判——回滚也失败时 save.json 与
			# .bak 双双不在原位，此时**保留 tmp 不删**（唯一完好副本）+ 告警留痕，绝不静默吞；
			# 只有回滚成功才清 tmp（既有「保底不留半截」语义在成功分支保持）。
			if DirAccess.rename_absolute(bak_abs, save_abs) != OK:
				push_warning("存档写入失败（tmp 换名失败且回滚 .bak 失败，已保留 tmp 副本待人工处理）")
				return false
			DirAccess.remove_absolute(tmp_abs)
			push_warning("存档写入失败（tmp 换名失败，已回滚旧档）")
			return false
		DirAccess.remove_absolute(bak_abs)  # 成功路径 .bak 即清（best-effort）
	return true

static func _write_text_flushed(path: String, text: String) -> bool:
	## 写入并校验落盘错误（P3-5a，规格 §7：错误读取移到 close() 之后——旧序在缓冲写盘前
	## 取 err 恒 OK，缓冲/落盘阶段失败不可见；镜像 level_slots._write_text 同构同修）。
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return f.get_error() == OK

# ---------- 首次标记 ----------
func is_first_launch() -> bool:
	return not FileAccess.file_exists(FLAG_PATH)

func mark_first_launch() -> void:
	var f: FileAccess = FileAccess.open(FLAG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("1")
		f.close()

# ---------- N10 图鉴门控 / V-D 主菜单判据（2026-09-19） ----------
func has_any_progress() -> bool:
	## V-D（规格 §8.3）：「有任何进度」三分支纯查询——主菜单载入/继续按钮判据单源，
	## 供后续路替换 main_menu.gd is_first_launch() 单判据（本路不动 main_menu.gd）。
	## 判据与图鉴门控同源（can_open_catalog 委托至此，防两处漂移）：
	## ①first_launch 标记存在（主菜单点开始游戏写过；易失旁路，可能被开发工具误清）；
	## ②progress.watched_opening（开场动画看过，opening_movie._finish 首次路径置位）；
	## ③progress.cleared 非空（通关记录，level_scene._goto_settle advance_progress 写入）。
	## 任一成立即 true；新档（三者全空）false。纯存档查询、与 Game 状态无关。
	if not is_first_launch():
		return true
	var p: Dictionary = _data.get("progress", {})
	if bool(p.get("watched_opening", false)):
		return true
	return not (p.get("cleared", []) as Array).is_empty()

func can_open_catalog() -> bool:
	## 图鉴门控（N10，2026-09-09 用户五条实测路径修复）：settings_panel._refresh_catalog_entry
	## 唯一判据。新档（三分支全空）仍禁用（用户认可：未看过开场动画不给进图鉴）。
	## V-D 起判据委托 has_any_progress() 同源（主菜单判据统一，规格 §8.3）。
	return has_any_progress()

func mark_opening_watched() -> void:
	## 开场动画「看过」置位并自动保存（幂等）。写点=opening_movie._finish 首次路径
	## （播完/跳过/资源缺失兜底三条退出路径同经 _finish）；回看模式不置位
	## （回看经图鉴进入，门控必已开）。不发 progress_changed（图鉴列表/主菜单按钮不消费该字段，
	## 防无谓重建）。
	var p: Dictionary = _data["progress"]
	if bool(p.get("watched_opening", false)):
		return
	p["watched_opening"] = true
	save_game()

func reset_for_new_game() -> void:
	# J3-2（C2 主菜单「新游戏」确认后清档，本批唯一命名，勿再造别名）：
	# 存档数据回默认（含初始天赋 500）并落盘 + 删除 first_launch 标记——
	# 清档后应重新走开场动画，标记不保留。
	# N10：watched_opening 随默认档回 false（图鉴门控同步关回，重看开场后经 mark_opening_watched 重置位）。
	# N9：level_progress（挖除断点）随默认档回 {}——新字段同步清理（整档重置覆盖，无残留断点）。
	# P2-3c（批次 W 规格 §3）：settings 域（音量/手势/摄像头记忆）**原引用**保留——「新游戏」
	# 只重置进度/皮肤/剧情域；旧实现 _data=_default_data() 把 settings 一并重置且不走
	# update_settings、不发 settings_changed（音频失同步的根因：apply_volumes 只靠该信号驱动）。
	# 现把旧 settings 子字典原引用搬入新档：值未变、无消费方需要通知 → 不调 update_settings、
	# 不发信号（发信号反而触发音频重应用）；其余域（progress/skins/talent/replay）为全新默认。
	var keep_settings: Dictionary = _default_data()["settings"]  # 极端态（_data 空/缺键）防御缺省
	var old_settings: Variant = _data.get("settings", null)
	if typeof(old_settings) == TYPE_DICTIONARY:
		keep_settings = old_settings
	_data = _default_data()
	_data["settings"] = keep_settings
	save_game()  # P0-8：未来版本只读锁下早退 false（零写盘）
	# P2-2 回修（W1 独立审查）：锁存时同步跳过 flag 删除——「只读不落盘」语义延伸到易失
	# 标记，磁盘零触碰口径（防锁存清档把 first_launch.flag 抹掉）。
	if not _future_readonly:
		var flag_abs: String = ProjectSettings.globalize_path(FLAG_PATH)
		if FileAccess.file_exists(FLAG_PATH):
			DirAccess.remove_absolute(flag_abs)
	# 批次 AA（P3-a，W5-P3-1）：显式清图鉴返回栈——新游戏=导航根重置（防御深度：现行主菜单
	# 入口经 goto_state(MAIN_MENU) 规则②已清栈，此处防未来新增非主菜单入口的新游戏路径
	# 栈残留）。父节点相对定位（本文件 W9-1 既有口径，不引用 Game. 标识符）+ has_method 守卫。
	var parent_node_ng: Node = get_parent()
	var game_ng: Node = parent_node_ng.get_node_or_null("Game") if parent_node_ng != null else null
	if game_ng != null and game_ng.has_method("clear_catalog_return"):
		game_ng.call("clear_catalog_return")

# ---------- 进度 ----------
func get_progress() -> Dictionary:
	return _data["progress"]

func advance_progress(chapter: int) -> void:
	var p: Dictionary = _data["progress"]
	var cleared: Array = p["cleared"]
	if not cleared.has(chapter):
		cleared.append(chapter)
		cleared.sort()
	p["next_chapter"] = maxi(int(p["next_chapter"]), mini(chapter + 1, 6))
	progress_changed.emit()
	unlock_origin_skin(chapter)  # K-D 解锁点位②：通关兜底解锁该章原创（幂等，spec §7.3/§7.4 表）
	save_game()

# ---------- N9 挖除断点（2026-09-09 spec §6.11：schema v2） ----------
func get_level_progress(chapter: int) -> Array:
	## 该章挖除断点（deleted_cells 数组，"x,y,z" 字符串）。无记录/未动 → 空数组（「没改」语义）。
	## 返回副本，防调用方直改内部数据（一致性：断点只经 set_level_progress 落档）。
	var lp: Dictionary = _data.get("progress", {}).get("level_progress", {})
	var entry: Dictionary = lp.get(str(chapter), {})
	var cells: Array = entry.get("deleted_cells", [])
	return (cells as Array).duplicate()

func set_level_progress(chapter: int, deleted_cells: Array) -> void:
	## 写该章挖除断点并自动保存（既有「变更即存」惯例）。空数组=清除断点（删键）——
	## 通关清账（level_scene._goto_settle 显式调用）与「挖了又全撤销=没改」同一语义。
	## 幂等省写：与现值一致/本无断点且写入为空时不落盘——未动关卡存档零新增数据、
	## level_scene._exit_tree 兜底检查点对未动关卡不产生 I/O 与脏写。
	var p: Dictionary = _data.get("progress", {})
	var lp: Dictionary = p.get("level_progress", {})
	var key := str(chapter)
	var cells := _normalize_deleted_cells(deleted_cells)
	if cells.is_empty():
		if not lp.has(key):
			return  # 未动且本无断点 → 不落盘（未动关卡存档无新增数据，spec §6.11 验收）
		lp.erase(key)
	else:
		var prev: Array = (lp.get(key, {}) as Dictionary).get("deleted_cells", [])
		if (prev as Array) == cells:
			return  # 幂等：断点内容未变不重复写
		lp[key] = {"deleted_cells": cells}
	p["level_progress"] = lp
	_data["progress"] = p
	save_game()

static func _parse_strict_int(s: String) -> Variant:
	## 严格整型解析（审查 B P3-1 防御纵深）：非纯整数（"abc"/""/"3.5"/"1,a"）或 int64 越界
	## → 返回 null（调用方丢弃该项）；其余经 int() 归一（"007"→7 数值不变，属合法归一非改写）。
	## 动机：int() 对 "abc"/"" 静默回 0、对超长数字串溢出饱和——都会把脏数据改写成看似合法的
	## 坐标/章键，与「非法项丢弃」注释矛盾；游戏自身写盘恒为合法串，仅手写档可触发。
	var t := s.strip_edges()
	if not t.is_valid_int():
		return null
	# 越界防饱和：int64 上界 9223372036854775807（负向 |min| 多 1），按位数+逐位比较判界
	var neg := t.begins_with("-")
	var digits := t.lstrip("+-").lstrip("0")
	var cap := "9223372036854775808" if neg else "9223372036854775807"
	if digits.length() > cap.length() or (digits.length() == cap.length() and digits > cap):
		return null
	return int(t)

static func _normalize_deleted_cells(cells: Array) -> Array:
	## 断点条目归一：兼容 Vector3i/"x,y,z" 字符串，统一 "x,y,z" 整型串、去重、字典序排序
	## （确定性导出便于 diff/断言；审查定论：字符串字典序即可，非数值序，不改）；非法项丢弃
	## （防脏数据膨胀存档）。审查 B P3-1：任一段非纯整数/int64 越界 → 整项丢弃
	## （不静默 int() 改写成 "1,0,3"），与本注释「非法项丢弃」对齐（手写档防御纵深）。
	var out: Dictionary = {}
	for v: Variant in cells:
		var s := ""
		if v is Vector3i:
			s = "%d,%d,%d" % [v.x, v.y, v.z]
		elif v is String:
			var parts: PackedStringArray = (v as String).split(",")
			if parts.size() != 3:
				continue
			var vals: Array = []
			var valid := true
			for p: String in parts:
				var n: Variant = _parse_strict_int(p)
				if n == null:
					valid = false
					break
				vals.append(n)
			if not valid:
				continue
			s = "%d,%d,%d" % vals
		else:
			continue
		out[s] = true
	var arr: Array = out.keys()
	arr.sort()
	return arr

static func _normalize_level_progress(lp: Variant) -> Dictionary:
	## level_progress 容器归一（load 迁移/防御共用）：仅保留 {chapter: {deleted_cells:[...]}}
	## 形态的有效条目；键统一 str(int)；空条目丢弃（键缺省=没动）。
	## 审查 B P3-1：章键非纯整数/int64 越界 → 整条目丢弃（不静默 str(int("abc"))="0" 伪造键）。
	var out: Dictionary = {}
	if typeof(lp) != TYPE_DICTIONARY:
		return out
	for k: Variant in (lp as Dictionary).keys():
		var entry_v: Variant = (lp as Dictionary)[k]
		if typeof(entry_v) != TYPE_DICTIONARY:
			continue
		var key_n: Variant = _parse_strict_int(String(k))
		if key_n == null:
			continue
		var raw: Variant = (entry_v as Dictionary).get("deleted_cells", [])
		var cells := _normalize_deleted_cells(raw if raw is Array else [])
		if cells.is_empty():
			continue
		out[str(key_n)] = {"deleted_cells": cells}
	return out

# ---------- 设置 ----------
func get_settings() -> Dictionary:
	return _data["settings"]

func update_settings(patch: Dictionary) -> void:
	var s: Dictionary = _data["settings"]
	for k: String in patch.keys():
		if typeof(s.get(k)) == TYPE_DICTIONARY and typeof(patch[k]) == TYPE_DICTIONARY:
			(s[k] as Dictionary).merge(patch[k], true)
		else:
			s[k] = patch[k]
	settings_changed.emit()
	save_game()

# ---------- 天赋值 ----------
func get_talent() -> int:
	return int(_data["talent"])

func add_talent(n: int) -> void:
	_data["talent"] = get_talent() + n
	talent_changed.emit(get_talent())
	save_game()

func spend_talent(n: int) -> bool:
	if n < 0 or get_talent() < n:
		return false
	_data["talent"] = get_talent() - n
	talent_changed.emit(get_talent())
	save_game()
	return true

# ---------- 皮肤 ----------
func get_skins() -> Dictionary:
	return _data["skins"]

func buy_skin(id: String) -> bool:
	if SkinCatalog.is_origin(id):
		return false  # K-D 纵深防御：原创皮肤随剧情解锁、不可购买（即便误调 API 也拒绝扣费）
	var skins: Dictionary = _data["skins"]
	var owned: Array = skins["owned"]
	if owned.has(id):
		return false
	# 修复批 P3（2026-09-26，独立审查确认）：旧实现 spend_talent（内部 save_game 落盘①）后
	# owned.append 再 save_game（落盘②）——两阶段落盘，中间崩溃=扣 205 无货。合并为
	# 一次内存变更 + 一次 save_game（红测 test_fix_save_buy_skin 断言购买成功恰一次落盘）。
	# 余额不足分支语义与 spend_talent 同口径（SKIN_PRICE>0 恒正，其 n<0 分支不可达不复制）；
	# talent_changed→skin_changed 信号序与旧实现一致。
	if get_talent() < SKIN_PRICE:
		return false
	_data["talent"] = get_talent() - SKIN_PRICE
	owned.append(id)
	talent_changed.emit(get_talent())
	skin_changed.emit(String(skins["equipped"]))
	save_game()
	return true

func equip_skin(id: String) -> bool:
	return set_preferred_skin(id)  # K-D（spec §7.3）兼容收口：旧签名保留，玩家主动穿戴=preferred 同步

func set_preferred_skin(id: String) -> bool:
	## 玩家主动穿戴（商店/任何穿戴入口）：preferred=equipped=id；未拥有返回 false。
	var skins: Dictionary = _data.get("skins", {})
	if skins.is_empty() or not (skins.get("owned", []) as Array).has(id):
		return false
	skins["preferred"] = id
	skins["equipped"] = id
	skin_changed.emit(id)
	save_game()
	return true

func apply_contextual_skin(chapter: int) -> void:
	## 进关/关前剧情自动穿戴该章原创（不动 preferred）；未 owned 跳过（防御，正常流不触发，spec §7.4）。
	var skins: Dictionary = _data.get("skins", {})
	if skins.is_empty():
		return  # 存档尚未加载（防御：goto_state 早于 load_game 的极端时序）
	var origin := SkinCatalog.get_origin_skin(chapter)
	if origin.is_empty():
		return
	var id := String(origin["id"])
	if not (skins.get("owned", []) as Array).has(id):
		return
	# W9-5（批次 AA 规格 §12 P3-6）：equipped 未变则不落盘——状态迁移链（game.gd goto_state）
	# 每次进/出态都会调本函数与 restore_preferred_skin，无条件 save_game 会放大为 1~2 次写盘/
	# 纹理重载；与现值一致时零 emit 零写盘（正向路径〔换装〕仍落盘，见 test_aa_defects W9-5 段）。
	if String(skins.get("equipped", "")) == id:
		return
	skins["equipped"] = id
	skin_changed.emit(id)
	save_game()

func restore_preferred_skin() -> void:
	## 关卡结束/主菜单/图鉴换回玩家自选（Q2 决策，spec §7.4）。
	var skins: Dictionary = _data.get("skins", {})
	if skins.is_empty():
		return
	var id := String(skins.get("preferred", "skin_default"))
	# W9-5（批次 AA 规格 §12 P3-6）：equipped 未变则不落盘（同 apply_contextual_skin 口径）。
	if String(skins.get("equipped", "")) == id:
		return
	skins["equipped"] = id
	skin_changed.emit(id)
	save_game()

func unlock_origin_skin(chapter: int) -> void:
	## 原创皮肤随剧情解锁入 owned（幂等；不 emit 购买语义，随 progress 变化，spec §7.3）。
	var skins: Dictionary = _data.get("skins", {})
	if skins.is_empty():
		return
	var origin := SkinCatalog.get_origin_skin(chapter)
	if origin.is_empty():
		return
	var id := String(origin["id"])
	var owned: Array = skins.get("owned", [])
	if not owned.has(id):
		owned.append(id)
		skins["owned"] = owned
		save_game()

# ---------- 重玩发奖计数 ----------
func get_replay_count(chapter: int) -> int:
	return int(_data["replay_award_counts"].get(str(chapter), 0))

func consume_replay_award(chapter: int) -> bool:
	var key: String = str(chapter)
	var counts: Dictionary = _data["replay_award_counts"]
	var c: int = int(counts.get(key, 0))
	if c >= REPLAY_AWARD_LIMIT:
		return false
	counts[key] = c + 1
	save_game()
	return true
