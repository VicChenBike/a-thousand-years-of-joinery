extends "res://tests/test_base.gd"
## 修复批（存档与系统域）P2-①：存档类型防御不完整——TDD 红测先行。
## 病灶（独立审查确认）：
##   save_manager._normalize_loaded_data（:184-217）只对 save_version 做了 typeof 防御，
##   其余数值/布尔读取仍走 int(...)/bool(...) 裸转换——JSON null/错类型触发 4.7
##   「Nonexistent constructor」运行期中止族，load_game 中断、_data 停在
##   半归一态；gesture_input/gesture_hud_visible 完全不在归一清单（defaults :77-78）。
##   传染点 scenes/main.gd boot：bool(_boot_settings.get("gesture_input", true)) 在键存在
##   值为 null 时 .get 缺省不生效 → bool(null) 中止 → boot 后半（LevelLibrary 扫描/进主
##   菜单）被跳过 → 黑屏卡 BOOT。
## 判定口径（三段）：
##   S 结构先行（红态先拿到干净 FAIL，再进脏载入段防挂死丢证据）：
##     save_manager 存在 _safe_int/_safe_bool 安全封装 + normalize 内补
##     s["gesture_input"]/s["gesture_hud_visible"] 归一；main.gd 存在 _safe_boot_flag
##     且 boot 读取经其封装。
##   A 脏档 load 不报错且回默认：talent=null→500、next_chapter="x"→1、cleared 含
##     null/脏串→逐项丢弃、udp_port=null→0、counts 含 null→0、
##     gesture_camera_enabled/gesture_panel_folded=null→缺省 bool、watched_opening=null→false。
##   B 传染点闭合：归一后 gesture_input/gesture_hud_visible 恒 TYPE_BOOL（boot 读到的
##     一定是 bool）+ boot 表达式复刻安全求值 + _safe_boot_flag 动态调用（null/0/false 直通）。
## 清档纪律：test_w_save_resilience 同款四件组备份/还原 + 真实 autoload 重同步 +
##   逐字节等价自检（EVID 行）。零摄像头零窗口（纯无头 --script）。

const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"
const SM_PATH := "res://autoload/save_manager.gd"
const MAIN_GD := "res://scenes/main.gd"
const BK_PREFIX := "user://_fixs_norm_backup_"
const WATCHED: Array = [SAVE_PATH, FLAG_PATH, TMP_PATH, BAK_PATH]
const AUTOLOAD_NAMES: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]

var _sm_seq: int = 0
var _pre_save_text: String = ""

func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _del(p: String) -> void:
	var a: String = _abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _write_file(p: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _read_file(p: String) -> String:
	return FileAccess.get_file_as_string(p)

func _selfheal() -> void:
	## 崩溃自愈（红态挂死被杀后遗留备份 → 下次跑测先还原真实档案再重备份）
	var healed: int = 0
	for p: String in WATCHED:
		var bk := BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			_del(p)
			DirAccess.copy_absolute(_abs(bk), _abs(p))
			DirAccess.remove_absolute(_abs(bk))
			healed += 1
	if healed > 0:
		print("EVID|selfheal|fixs_norm|restored=%d" % healed)

func _backup_user() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		_pre_save_text = _read_file(SAVE_PATH)
	for p: String in WATCHED:
		if FileAccess.file_exists(p):
			var bk := BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_abs(p), _abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	for c: Node in root.get_children():
		if not AUTOLOAD_NAMES.has(String(c.name)):
			c.free()
	for p: String in WATCHED:
		_del(p)
		var bk := BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_abs(bk), _abs(p))
			DirAccess.remove_absolute(_abs(bk))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()
	var post: String = _read_file(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|fixs_norm|files=%d" % WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _new_sm() -> Node:
	_sm_seq += 1
	var sm: Node = (load(SM_PATH) as GDScript).new()
	sm.name = "SM_FIXS_%d" % _sm_seq
	get_root().add_child(sm)
	sm.load_game()
	return sm

func _initialize() -> void:
	print("== test_fix_save_normalize ==")

	# ===== S 段：结构锚（红态先拿到干净 FAIL，再进脏载入段） =====
	var sm_src: String = FileAccess.get_file_as_string(SM_PATH)
	check(sm_src.contains("static func _safe_int"), "S1 save_manager 存在 _safe_int 安全数值封装（int() 裸转换退役）")
	check(sm_src.contains("static func _safe_bool"), "S2 save_manager 存在 _safe_bool 安全布尔封装（bool() 裸转换退役）")
	check(sm_src.contains("s[\"gesture_input\"] = _safe_bool"), "S3 normalize 补 gesture_input 归一（原完全不在清单）")
	check(sm_src.contains("s[\"gesture_hud_visible\"] = _safe_bool"), "S4 normalize 补 gesture_hud_visible 归一（原完全不在清单）")
	var main_src: String = FileAccess.get_file_as_string(MAIN_GD)
	check(main_src.contains("static func _safe_boot_flag"), "S5 main.gd 存在 _safe_boot_flag 安全封装（传染点二重防御）")
	check(main_src.contains("_safe_boot_flag(_boot_settings.get"), "S6 main.gd boot 读取经 _safe_boot_flag（裸 bool() 退役）")

	# ===== A/B 段：脏档 load 不报错且回默认（修复前：int(null)/bool(null) 中止族 →
	# 本段 SCRIPT ERROR 中止 → S 段 FAIL + 挂死 = 红证据） =====
	_selfheal()
	_backup_user()
	for p: String in WATCHED:
		_del(p)
	var dirty: Dictionary = {
		"save_version": 2,
		"talent": null,
		"progress": {"cleared": [1, null, "x", "2"], "next_chapter": "x",
			"watched_opening": null, "level_progress": {}},
		"settings": {
			"gesture_input": null, "kb_input": true, "gesture_hud_visible": null,
			"gesture_hud_offset": [0, 0], "volume": {"master": 1.0, "music": 1.0, "sfx": 1.0},
			"gesture_camera_enabled": null, "gesture_panel_folded": null,
			"gesture_camera_device": "", "gesture_camera_res": "", "gesture_camera_fps": 0,
			"udp_port": null,
		},
		"replay_award_counts": {"1": null, "2": 3.0},
		"skins": {"owned": ["skin_default", "skin_origin_kaitou"],
			"equipped": "skin_origin_kaitou", "preferred": "skin_origin_kaitou"},
	}
	_write_file(SAVE_PATH, JSON.stringify(dirty))
	var sm: Node = _new_sm()  # 修复前 load_game 内中止 → 此后断言不执行（红=挂死）
	print("EVID|dirty_loaded|fixs_norm")  # 修复后必达（load 未中止的哨兵行）

	# A 段：逐项回默认
	check_eq(sm.get_talent(), 500, "A1 talent=null → 500 默认")
	var prog: Dictionary = sm.get_progress()
	check_eq(int(prog.get("next_chapter", -9)), 1, "A2 next_chapter=\"x\" → 1 默认")
	check_eq((prog.get("cleared", [9]) as Array), [1, 2], "A3 cleared 含 null/脏串 → 逐项丢弃保留 [1,2]")
	check_eq(bool(prog.get("watched_opening", true)), false, "A4 watched_opening=null → false")
	var bs: Dictionary = sm.get_settings()
	check_eq(int(bs.get("udp_port", -9)), 0, "A5 udp_port=null → 0")
	check_eq(typeof(bs.get("gesture_camera_enabled")), TYPE_BOOL, "A6 gesture_camera_enabled 归一为 bool")
	check_eq(bool(bs.get("gesture_camera_enabled")), true, "A6b gesture_camera_enabled=null → true 缺省")
	check_eq(typeof(bs.get("gesture_panel_folded")), TYPE_BOOL, "A7 gesture_panel_folded 归一为 bool")
	check_eq(bool(bs.get("gesture_panel_folded")), false, "A7b gesture_panel_folded=null → false 缺省")
	check_eq(sm.get_replay_count(1), 0, "A8 counts 含 null → 0")
	check_eq(sm.get_replay_count(2), 3, "A8b counts 正常项无损（3）")

	# B 段：传染点闭合（boot 读到的一定是 bool）
	check_eq(typeof(bs.get("gesture_input")), TYPE_BOOL, "B1 gesture_input 归一后恒 TYPE_BOOL（原不在清单）")
	check_eq(bool(bs.get("gesture_input")), true, "B1b gesture_input=null → true 缺省")
	check_eq(typeof(bs.get("gesture_hud_visible")), TYPE_BOOL, "B2 gesture_hud_visible 归一后恒 TYPE_BOOL")
	check_eq(bool(bs.get("gesture_hud_visible")), true, "B2b gesture_hud_visible=null → true 缺省")
	# boot 表达式复刻（main.gd:176-177 传染点原形）：修复后恒安全求值
	var boot_ok: bool = bool(sm.get_settings().get("gesture_input", true)) \
		or bool(sm.get_settings().get("gesture_camera_enabled", true))
	check_eq(boot_ok, true, "B3 boot 门控表达式复刻安全求值（不触发 bool(null) 中止）")

	# _safe_boot_flag 动态调用（静态函数经脚本资源直调；不可调时退回源码锚已在 S5/S6）
	var mgd: GDScript = load(MAIN_GD)
	if mgd != null and mgd.has_method("_safe_boot_flag"):
		check_eq(mgd.call("_safe_boot_flag", null, true), true, "B4 _safe_boot_flag(null) → 缺省 true")
		check_eq(mgd.call("_safe_boot_flag", false, true), false, "B4b _safe_boot_flag(false) → false 直通")
		check_eq(mgd.call("_safe_boot_flag", 0, true), false, "B4c _safe_boot_flag(0) → false（int 兼容）")
		check_eq(mgd.call("_safe_boot_flag", "junk", true), true, "B4d _safe_boot_flag(脏串) → 缺省 true")
	else:
		check(main_src.contains("static func _safe_boot_flag"), "B4 静态动态调用不可用 → 源码锚兜底")

	finish()
