extends "res://tests/test_base.gd"
## 批次 AC（2026-09-27）Wave AC-2「摄像头生命周期与首选握手」专项回归（spec §4.2，领域二）。
## 批次 AD（2026-09-27，spec §4.2）等价改写留痕：黑名单硬编码与自动缺省选择已由 AD 拍板
## **彻底退役**（不再按名称猜测设备类型、不再有本桥自选设备通路）；设备启停改由存档设备名
## `START_CAMERA_BY_NAME:<名>` 查名直启驱动。本文件断言口径按 AD 逐条迁移（条数不减）：
##   A（Python 侧源码协议锚，纯文件读取）：
##     A1 AD：`PREFERRED_WAIT_SEC` 等待窗常量彻底退役（冷启动零阻塞）；
##     A2 `_handshake_received` 状态位在位 + 设备启动指令置位点；
##     A3 AD：`pick_camera_by_name` 查名直启纯函数在位（未命中/空名 → 列表首项）；
##     A4 GET_CAMERAS 空名单重扫（_rescan_cameras_on_demand + _enum_probe_started 复位）；
##     A5 AD：黑名单元组/纯函数/`pick_auto_camera` 彻底退役（负向锚）。
##   B（Godot 桥启动指令时序，spec §4.2.2-3）：
##     B1 无记忆名亦武装启动指令且 tick 后发出 **空载荷** `START_CAMERA_BY_NAME:`
##        ——Python 按降级首项启动，零额外等待；
##     B2 有记忆名照发实名（既有语义等价迁移）；
##     B3 AD：`_resolve_target_camera_id` 忽略大小写/首尾空格命中；数字残留不再按 CAP 索引；
##     B4 AD：`_first_camera_entry_id` 首项物理设备 id 纯函数（含脏条目/空列表防御）；
##     B5 ensure_camera_open 枚举未达（cams 空）不盲发 SWITCH_CAMERA:0，
##        改走启动指令重发 + GET_CAMERAS 拉取；
##     B6 有枚举时按下发启动指令（红态=取首项 0=手机）；
##     B7 反向护栏：显式设备行 id 仍照发（不误伤用户点击）。
##   C（无摄像头分支与热插拔重扫，spec §4.2-4）：
##     C1 zero 态强制 gesture_toggle/camera_toggle 双双置灭（set_pressed_no_signal(false)）；
##     C2 zero 态置灰样式在位且仍可点（AB2「视觉置灰仍可点」语义保持，点击弹提示条）；
##     C3 zero 态点钮 → 「无硬件摄像头支持」提示条 + 视觉回弹不落开态；
##     C4 0 摄像头点摄像头钮 → GET_CAMERAS（重扫请求）零 spawn 零 SWITCH；
##     C5 open_menu（下拉刷新，ArrowBtn 路径）→ 经桥 GET_CAMERAS 重扫（热插拔识别）；
##     C6 反向护栏：有设备态不得被迫置灭/置灰。
## 清档纪律：user:// 备份还原四件组（前缀 acb2，test_ac_batch1_infra 同款逐字节自证）；
##   面板 _ready 会触档（SaveManager），备份-还原覆盖之。
## 无头纪律（坑1/坑10）：成员/节点取值一律 Variant 判空 + str 比较，红态不崩不挂死。

const BR_SCRIPT := "res://autoload/gesture_bridge.gd"
const PANEL_SCENE := "res://scenes/settings/settings_panel.tscn"
const MENU_SCRIPT := "res://scenes/settings/camera_menu.gd"
const PANEL_GD := "res://scenes/settings/settings_panel.gd"
const PY_SERVER := "res://gesture_runtime/hand_tracking_server.py"
const PY_SELECTOR := "res://gesture_runtime/camera_selector.py"

const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_acb2_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const NO_HW_INFO := "无硬件摄像头支持"

# 自有桥实例高位端口（单测串行跑；与 9876/9877/9878 及他测 override 零交集；
# 每实例占用 override..override+6 段，故各段基址间隔 ≥10 防自撞）
const PORT_H1 := 20440   # 段B1/B2 握手时序（子实例 +4/+6）
const PORT_H2 := 20450   # 段B5/B6 ensure 防盲发（+2）
const PORT_H3 := 20460   # 段C4/C5 重扫（+4）

var _pre_save_text: String = ""

## 9879 控制端口回环监听（CtrlSniffer 同款）
class CtrlSniffer extends PacketPeerUDP:
	var cmds: Array = []
	func drain() -> void:
		while get_available_packet_count() > 0:
			cmds.append(get_packet().get_string_from_utf8())
	func count_prefix(prefix: String) -> int:
		drain()
		var n: int = 0
		for c: Variant in cmds:
			if String(c).begins_with(prefix):
				n += 1
		return n
	func has_cmd(c: String) -> bool:
		drain()
		return cmds.has(c)
	## 批次 AD：任一命令以 prefix 开头（数字命令负向护栏用）
	func any_prefix(prefix: String) -> bool:
		drain()
		for c: Variant in cmds:
			if String(c).begins_with(prefix):
				return true
		return false

## TopStrip 替身（ab_no_camera StripSpy 同款）：Game.info → TopStrip.push_info 同通道
class StripSpy extends Node:
	var info_calls: Array = []
	func push_info(text: String, seconds: float = 3.0) -> void:
		info_calls.append([text, seconds])

func _src(p: String) -> String:
	return FileAccess.get_file_as_string(p)

## 剥整行注释后再断语句（留痕注释会引用被退役标识符；test_ac_batch1_infra 同款口径）
func _code_only(src: String) -> String:
	var out: Array[String] = []
	for ln: String in src.split("\n"):
		if ln.strip_edges().begins_with("#"):
			continue
		out.append(ln)
	return "\n".join(out)

func _fn_body(src: String, fname: String) -> String:
	var i: int = src.find("func %s(" % fname)
	if i < 0:
		return ""
	var j: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (j if j > 0 else src.length()) - i)

## Python 源码函数体抽取（`def name(...)` 至下一个顶层 `def `/`class `/文件尾）——
## 段 A 的 Python 协议锚用（GDScript 的 func 抽取器不适用）。
func _py_fn_body(src: String, fname: String) -> String:
	var i: int = src.find("def %s(" % fname)
	if i < 0:
		return ""
	var j: int = src.find("\ndef ", i + 1)
	for marker: String in ["\ndef ", "\nclass ", "\nasync def "]:
		var k: int = src.find(marker, i + 1)
		if k >= 0 and (j < 0 or k < j):
			j = k
	return src.substr(i, (j if j > 0 else src.length()) - i)

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _backup_user() -> void:
	for p0: String in DISC_WATCHED:
		var bk0: String = DISC_BK_PREFIX + p0.get_file()
		if FileAccess.file_exists(_disc_abs(bk0)):
			if FileAccess.file_exists(_disc_abs(p0)):
				DirAccess.remove_absolute(_disc_abs(p0))
			DirAccess.copy_absolute(_disc_abs(bk0), _disc_abs(p0))
			DirAccess.remove_absolute(_disc_abs(bk0))
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if not FileAccess.file_exists(p):
			continue
		var bk: String = DISC_BK_PREFIX + p.get_file()
		DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
		if not FileAccess.file_exists(bk):
			check(false, "存档纪律：%s 备份落位失败（保留活档不删）" % p)
			continue
		DirAccess.remove_absolute(_disc_abs(p))
	var sm: Node = root.get_node_or_null("SaveManager")
	if sm != null:
		sm.call("load_game")

func _restore_user() -> void:
	for c: Node in root.get_children():
		if not ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager", "GestureBridge",
				"LevelLibrary", "Game", "GestureRouter", "I18n"].has(String(c.name)):
			c.free()
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(_disc_abs(p)):
			DirAccess.remove_absolute(_disc_abs(p))
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(_disc_abs(bk)):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(_disc_abs(bk))
	var real_sm: Node = root.get_node_or_null("SaveManager")
	if real_sm != null:
		real_sm.call("load_game")
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")

func finish() -> void:
	_restore_user()
	super.finish()

## 成员布尔读防御（坑1：bool(null) 中止 _initialize——红态成员缺失不崩）
func _member_true(o: Object, member: String) -> bool:
	return str(o.get(member)) == "true"

func _make_bridge(port: int) -> Node:
	var br: Node = (load(BR_SCRIPT) as GDScript).new()
	br.set("_udp_port_override", port)
	root.add_child(br)
	await process_frame
	return br

func _make_panel() -> Node:
	var panel: Node = (load(PANEL_SCENE) as PackedScene).instantiate()
	root.add_child(panel)
	await process_frame
	await process_frame
	return panel

func _is_gray(btn: Button) -> bool:
	var sp: GDScript = load(PANEL_GD)
	var cm: Dictionary = sp.get_script_constant_map()
	var zg_bg: Variant = cm.get("ZERO_GRAY_BG_DARK", null)
	var zg_font: Variant = cm.get("ZERO_GRAY_FONT", null)
	if zg_bg == null or zg_font == null:
		return false
	var sb: StyleBoxFlat = btn.get_theme_stylebox("normal") as StyleBoxFlat
	return sb != null and sb.bg_color == Color(zg_bg) \
		and btn.get_theme_color("font_color") == Color(zg_font)

## 等待目标命令到达（UDP 回环毫秒级但需让帧轮转；他测 _wait_available 同款手法）
func _wait_cmd(snif: CtrlSniffer, target: String, frames: int = 30) -> bool:
	for i: int in frames:
		if snif.has_cmd(target):
			return true
		await process_frame
	return snif.has_cmd(target)

# ================= 段 A（Python 侧源码协议锚） =================
func _section_a() -> void:
	print("-- A Python 侧摄像头协议锚（spec §4.2-1/2/4） --")
	var server_src: String = _src(PY_SERVER)
	var sel_src: String = _src(PY_SELECTOR)
	check(not server_src.is_empty(), "A0 前置：hand_tracking_server.py 可读")
	check(not sel_src.is_empty(), "A0 前置：camera_selector.py 可读")
	var srv_code: String = _code_only(server_src)
	var sel_code: String = _code_only(sel_src)

	check(not srv_code.contains("PREFERRED_WAIT_SEC ="),
		"A1 AD 等价改写：等待窗常量彻底退役（冷启动零阻塞；旧 AC 断言为 ==5.0s）")
	check(_code_only(_py_fn_body(server_src, "_startup_sequence")).contains("_handshake_received")
		or _py_fn_body(server_src, "_start_camera_by_name").contains("_handshake_received")
		or _code_only(_py_fn_body(server_src, "_execute_control_command")).contains("_handshake_received = True"),
		"A2 设备启动指令置握手已达状态位（命令漏斗内）")
	check(server_src.contains("self._handshake_received: bool = False")
		or server_src.contains("self._handshake_received = False"),
		"A2 握手已达状态位成员在 __init__ 初始化（红态=成员缺失）")
	var pref_body: String = _code_only(_py_fn_body(server_src, "_execute_control_command"))
	check(pref_body.contains("self._handshake_received = True"),
		"A2 设备启动指令/SWITCH_CAMERA 置握手已达（红态=0）")
	check(server_src.contains("START_CAMERA_BY_NAME:") and server_src.contains("SET_PREFERRED_CAMERA:"),
		"A2 新命令主协议 + 旧命令兼容分支在位（协议零破坏）")
	check(_code_only(_py_fn_body(server_src, "_start_camera_by_name")).contains(
			"pick_camera_by_name"),
		"A3 AD 等价改写：查名直启漏斗经 pick_camera_by_name 解析目标（旧断言为 _choose_initial_camera_id）")
	check(server_src.contains("def pick_camera_by_name") or sel_src.contains("def pick_camera_by_name"),
		"A3 查名直启纯函数在位（未命中/空名 → 列表首项）")
	check(server_src.contains("int(auto_cam_id) if auto_cam_id is not None else -1")
		or server_src.contains('"current_camera": -1'),
		"A3 未启动态 init#1 current_camera=-1 哨兵（Godot 侧可识别无设备）")
	check(srv_code.contains("_rescan_cameras_on_demand"),
		"A4 GET_CAMERAS 空名单按需重扫入口在位（红态=只重发空名单）")
	check(_code_only(_py_fn_body(server_src, "_rescan_cameras_on_demand")).contains("_enum_probe_started = False")
		or _code_only(_py_fn_body(server_src, "_rescan_cameras_on_demand")).contains("_enumerate_cameras_step"),
		"A4 重扫复位一次性探针门/重跑枚举步（热插拔识别根因修复）")
	check(server_src.contains("_enum_probe_started = False"),
		"A4 一次性探针门可复位（红态=跑过一次永不重扫）")

	# A5（AD 等价改写：正向断言 → 负向退役锚，条数不减）
	check(not sel_code.contains("VIRTUAL_OR_PHONE_CAMERA_KEYWORDS"),
		"A5 AD：黑名单关键词元组彻底退役（旧 AC 断言为在位）")
	check(not sel_code.contains("def is_virtual_or_phone_camera("),
		"A5 AD：黑名单判定纯函数彻底退役")
	check(not sel_code.contains("def pick_auto_camera("),
		"A5 AD：自动缺省选择彻底退役（无本进程自选设备通路）")
	check(sel_src.contains("def pick_camera_by_name("),
		"A5 AD：查名直启纯函数取代自动选择（Optional[int] 语义保持）")
	var pick_code: String = _code_only(_py_fn_body(sel_src, "pick_camera_by_name"))
	check(pick_code.contains("return None"),
		"A5 空列表返回 None（保持未启动，绝不盲开）")
	check(not sel_code.contains("def rotate_backend_chain(")
		and not sel_code.contains("rotate_backend_chain("),
		"A5 AD：后端轮换链彻底退役（单后端 CAP_DSHOW 直启）")

# ================= 段 B（Godot 桥启动指令时序） =================
func _section_b() -> void:
	print("-- B Godot 桥启动指令时序（spec §4.2.2-3） --")
	var src: String = _src(BR_SCRIPT)
	var code: String = _code_only(src)

	check(code.contains("START_CAMERA_BY_NAME:"),
		"B0 桥侧启动指令主协议逐字在位（红态=只发 SET_PREFERRED_CAMERA:）")

	# B3/B4 纯函数（静态，无桥实例即可直测——经 GDScript 直调 script 常量/方法）
	var br_probe: Node = (load(BR_SCRIPT) as GDScript).new()
	check(not br_probe.has_method("is_virtual_or_phone_camera_name"),
		"B3 AD 等价改写：黑名单纯函数彻底退役（旧 AC 断言为在位）")
	check(not code.contains("VIRTUAL_OR_PHONE_KEYWORDS"),
		"B3 AD：黑名单关键词常量彻底退役")
	check(br_probe.has_method("_resolve_target_camera_id"),
		"B3 查名解析纯函数 _resolve_target_camera_id 在位")
	check(br_probe.has_method("_first_camera_entry_id"),
		"B4 AD：首项物理设备 id 纯函数 _first_camera_entry_id 在位（取代非手机首选）")
	check(not br_probe.has_method("_pick_non_phone_camera_id"),
		"B4 AD：非手机首选纯函数彻底退役（不再按类型自选设备）")
	if br_probe.has_method("_resolve_target_camera_id"):
		var cams_nm: Array = [{"id": 0, "name": "HD Camera"}, {"id": 2, "name": "USB Camera"}]
		check_eq(int(br_probe.call("_resolve_target_camera_id", cams_nm, "usb camera")), 2,
			"B3 记忆名忽略大小写命中 → id 2")
		check_eq(int(br_probe.call("_resolve_target_camera_id", cams_nm, "  HD Camera  ")), 0,
			"B3 记忆名首尾空格不敏感 → id 0")
		check_eq(int(br_probe.call("_resolve_target_camera_id", cams_nm, "2")), -1,
			"B3 AD：数字残留不再按 CAP 索引解释（→ -1，走首项降级）")
		check_eq(int(br_probe.call("_resolve_target_camera_id", cams_nm, "Ghost Cam")), -1,
			"B3 名字不在枚举 → -1")
		check_eq(int(br_probe.call("_resolve_target_camera_id", cams_nm, "")), -1,
			"B3 空记忆名 → -1（未记忆）")
		check_eq(int(br_probe.call("_resolve_target_camera_id", cams_nm, "   ")), -1,
			"B3 纯空格记忆名 trim 后 → -1")
		check_eq(int(br_probe.call("_resolve_target_camera_id", [], "HD Camera")), -1,
			"B3 枚举缓存空 → -1")
	if br_probe.has_method("_first_camera_entry_id"):
		var cams_mixed: Array = [{"id": 0, "name": "荣耀Magic7 前置摄像头"},
			{"id": 2, "name": "HD Camera"}]
		check_eq(int(br_probe.call("_first_camera_entry_id", cams_mixed)), 0,
			"B4 首项 id 解析 → 0（降级目标=列表首项，与 Python pick_camera_by_name 同源）")
		var cams_dirty: Array = [{"name": "No Id"}, {"id": 5, "name": "B"}]
		check_eq(int(br_probe.call("_first_camera_entry_id", cams_dirty)), 5,
			"B4 脏条目顺延取下一可解析条目 → 5")
		check_eq(int(br_probe.call("_first_camera_entry_id", [{"name": "No Id"}])), -1,
			"B4 全脏条目 → -1（调用方零下发）")
		check_eq(int(br_probe.call("_first_camera_entry_id", [])), -1,
			"B4 空名单 → -1（绝不盲发 CAP 索引）")
	br_probe.free()

	# B1/B2 启动指令时序（自有桥实例 + 高位端口抓包）
	var sub := GDScript.new()
	sub.source_code = """
extends "res://autoload/gesture_bridge.gd"
var probe_ret: bool = false
func _probe_python_ready() -> bool:
	return probe_ret
"""
	check_eq(int(sub.reload()), 0, "段B 前置：probe mock 子类编译成功")
	if int(sub.reload()) != int(OK):
		return

	var save: Node = root.get_node("SaveManager")
	# B1 无记忆名：照样武装并发出 **空载荷** 启动指令（红态=早退零下发）
	save.update_settings({"gesture_camera_device": ""})
	var br1: Node = sub.new()
	br1.set("_udp_port_override", PORT_H1)
	root.add_child(br1)
	await process_frame
	var snif1 := CtrlSniffer.new()
	check_eq(int(snif1.bind(PORT_H1 + 2)), 0, "段B1 前置：控制端口抓包器就位")
	br1.set("probe_ret", true)
	br1.set("preferred_handshake_interval_ms", 1)
	br1.set("_spawn_hook", func() -> bool: return true)
	br1.call("_spawn")
	check(_member_true(br1, "_preferred_handshake_armed"),
		"B1 无记忆名亦武装启动指令（红态=armed=false 早退）")
	br1.set("_preferred_next_at_ms", int(Time.get_ticks_msec()) - 1)
	br1.call("_process", 0.016)
	check(snif1.has_cmd("START_CAMERA_BY_NAME:"),
		"B1 空载荷 START_CAMERA_BY_NAME: 发出（Python 降级首项零干等；实际 %s）" % [snif1.cmds])
	check(not snif1.has_cmd("START_CAMERA_BY_NAME: "),
		"B1 空载荷无尾随空格（逐字契约；实际 %s）" % [snif1.cmds])

	# B2 有记忆名：照发实名（既有语义等价迁移）
	var br2: Node = sub.new()
	br2.set("_udp_port_override", PORT_H1 + 4)
	root.add_child(br2)
	await process_frame
	var snif2 := CtrlSniffer.new()
	check_eq(int(snif2.bind(PORT_H1 + 6)), 0, "段B2 前置：抓包器就位")
	save.update_settings({"gesture_camera_device": "HD Camera"})
	br2.set("probe_ret", true)
	br2.set("preferred_handshake_interval_ms", 1)
	br2.set("_spawn_hook", func() -> bool: return true)
	br2.call("_spawn")
	br2.set("_preferred_next_at_ms", int(Time.get_ticks_msec()) - 1)
	br2.call("_process", 0.016)
	check(snif2.has_cmd("START_CAMERA_BY_NAME:HD Camera"),
		"B2 有记忆名照发实名（实际 %s）" % [snif2.cmds])

	# B5/B6 ensure_camera_open 防盲发（自有桥实例 20442）
	var br3: Node = sub.new()
	br3.set("_udp_port_override", PORT_H2)
	root.add_child(br3)
	await process_frame
	var snif3 := CtrlSniffer.new()
	check_eq(int(snif3.bind(PORT_H2 + 2)), 0, "段B5 前置：抓包器就位")
	br3.set("probe_ret", true)          # python 常驻（打包形态常态）
	br3.set("_simulate_start_ok", false)   # 走 probe ready 分支
	br3.set("_preferred_handshake_armed", false)
	br3.set("_preferred_next_at_ms", -1)
	br3.set("preferred_handshake_interval_ms", 1)
	save.update_settings({"gesture_camera_device": ""})
	br3.set("_camera_enum", {})          # 枚举未达（缓存空）
	br3.set("_camera_enum_zero", false)
	br3.set("_camera_release_intent", false)
	save.update_settings({"gesture_input": true, "gesture_camera_enabled": true})
	snif3.cmds.clear()
	var ok5: bool = bool(br3.call("ensure_camera_open"))
	check_eq(ok5, true, "B5 前置：ensure 返回 true（常驻服务形态）")
	check_eq(snif3.count_prefix("SWITCH_CAMERA"), 0,
		"B5 枚举未达 → 零盲发 SWITCH_CAMERA:0（红态=1=荣耀手机；实际 %s）" % [snif3.cmds])
	check_eq(snif3.count_prefix("START_CAMERA_BY_NAME"), 0,
		"B5 枚举未达 → 零启动指令盲发（实际 %s）" % [snif3.cmds])
	check(snif3.count_prefix("GET_CAMERAS") >= 1,
		"B5 枚举未达 → 改发 GET_CAMERAS 拉取枚举（实际 %s）" % [snif3.cmds])
	check(_member_true(br3, "_preferred_handshake_armed"),
		"B5 枚举未达 → 启动指令重新武装（init#1 到达后按记忆名/首项自动开）")
	br3.set("_preferred_next_at_ms", int(Time.get_ticks_msec()) - 1)
	br3.call("_process", 0.016)
	check_eq(snif3.count_prefix("START_CAMERA_BY_NAME"), 1,
		"B5 枚举未达 → 补发启动指令恰一次（空载荷；实际 %s）" % [snif3.cmds])

	# B6 有枚举 → 按记忆名/首项下发启动指令（不再由本桥按类型自选设备）
	br3.set("_camera_enum", {"cameras": [{"id": 0, "name": "荣耀Magic7 前置摄像头"},
		{"id": 2, "name": "HD Camera"}], "current_camera": -1})
	snif3.cmds.clear()
	br3.set("_simulate_start_ok", true)
	save.update_settings({"gesture_camera_device": "HD Camera"})
	br3.call("ensure_camera_open")
	check_eq(snif3.count_prefix("START_CAMERA_BY_NAME"), 1,
		"B6 有枚举 → 恰一发启动指令（实际 %s）" % [snif3.cmds])
	check(snif3.has_cmd("START_CAMERA_BY_NAME:HD Camera"),
		"B6 记忆名命中 HD → 逐字下发该设备名（实际 %s）" % [snif3.cmds])
	check(not snif3.any_prefix("SWITCH_CAMERA:"),
		"B6 启动指令路径零 SWITCH_CAMERA 数字命令（禁止依赖 CAP 索引；实际 %s）" % [snif3.cmds])
	# 无记忆名 → 空载荷（由 Python 降级列表首项，本桥不再自选）
	save.update_settings({"gesture_camera_device": ""})
	snif3.cmds.clear()
	br3.call("ensure_camera_open")
	check(snif3.has_cmd("START_CAMERA_BY_NAME:"),
		"B6 无记忆名 → 空载荷启动指令（降级首项下沉 Python；实际 %s）" % [snif3.cmds])
	# B7 反向护栏：显式（记忆名命中手机）仍照发——用户明确指定时允许打开
	save.update_settings({"gesture_camera_device": "荣耀Magic7 前置摄像头"})
	br3.set("_camera_enum", {"cameras": [{"id": 0, "name": "荣耀Magic7 前置摄像头"},
		{"id": 2, "name": "HD Camera"}], "current_camera": 2})
	snif3.cmds.clear()
	br3.call("ensure_camera_open")
	check(snif3.has_cmd("START_CAMERA_BY_NAME:荣耀Magic7 前置摄像头"),
		"B7 反向护栏：用户显式指定手机设备（记忆名命中）→ 照发该设备名（不越权拦截；实际 %s）" % [snif3.cmds])

	# B8 枚举未达登记的显式开启意图，init#1 到达兑现（非手机首选）
	#（spec §4.2-3：显式开启不因枚举迟到而丢失；旧实现盲发 0 已废止）
	save.update_settings({"gesture_camera_device": ""})
	br3.set("_camera_enum", {})
	br3.set("_camera_enum_zero", false)
	br3.set("camera_stream_open", false)
	br3.set("_open_on_next_enum", false)
	br3.set("_last_enum_request_ms", -1000000)
	br3.set("_simulate_start_ok", true)
	snif3.cmds.clear()
	br3.call("ensure_camera_open")
	check(_member_true(br3, "_open_on_next_enum"),
		"B8：枚举未达 → 显式开启意图登记（_open_on_next_enum=true；红态=成员缺失）")
	check_eq(snif3.count_prefix("START_CAMERA_BY_NAME"), 0,
		"B8：登记期零启动指令（待 init#1；实际 %s）" % [snif3.cmds])
	snif3.cmds.clear()
	br3.simulate_packet(JSON.stringify({"type": "init",
		"cameras": [{"id": 0, "name": "荣耀Magic7 前置摄像头"}, {"id": 2, "name": "HD Camera"}],
		"current_camera": -1}))
	check(snif3.has_cmd("START_CAMERA_BY_NAME:"),
		"B8：init#1 到达 → 兑现意图下发启动指令（无记忆=空载荷，Python 降级首项；实际 %s）" % [snif3.cmds])
	check(not _member_true(br3, "_open_on_next_enum"),
		"B8：意图一次性兑现（防重入）")
	check(not snif3.any_prefix("SWITCH_CAMERA:"),
		"B8 反向护栏：兑现路径零 SWITCH_CAMERA 数字命令（禁止依赖 CAP 索引；实际 %s）" % [snif3.cmds])

	snif1.close()
	snif2.close()
	snif3.close()
	br1.free()
	br2.free()
	br3.free()

# ================= 段 C（无摄像头分支 + 热插拔重扫） =================
func _section_c() -> void:
	print("-- C 无摄像头分支与热插拔重扫（spec §4.2-4） --")
	var bridge: Node = root.get_node("GestureBridge")
	var game: Node = root.get_node_or_null("Game")
	if game == null:
		check(false, "段C 前置：Game autoload 在位")
		return
	var spy := StripSpy.new()
	root.add_child(spy)
	game.call("attach_strip", spy)

	# 0 摄像头确认态（零 spawn 零出包：空列表注入）
	bridge.set("_camera_enum", {"cameras": [], "current_camera": 0})
	bridge.set("_camera_enum_zero", true)
	bridge.set("camera_stream_open", false)
	bridge.set("_camera_release_intent", false)
	bridge.set("_intentional_stop", false)
	bridge.set("_reattach_intent", false)
	var save: Node = root.get_node("SaveManager")
	# 存档两键**开**（红态=按存档回写亮态 → 双钮未置灭）——证明置灭由 0 摄像头门强制
	save.update_settings({"gesture_input": true, "gesture_camera_enabled": true})
	var panel: Node = await _make_panel()
	var gt: Button = panel.get_node_or_null("Panel/VBox/OptionsBox/GestureToggle") as Button
	var ct: Button = panel.get_node_or_null("Panel/VBox/OptionsBox/CameraRow/CameraToggle") as Button
	check(gt != null and ct != null, "段C 前置：手势/摄像头双钮在位")
	if gt == null or ct == null:
		return

	# C1 zero 态强制双钮置灭（存档为开也不得点亮）
	check_eq(bool(gt.button_pressed), false,
		"AC-C1：0 摄像头 → 手势钮强制置灭（存档开也不得亮；红态=true）")
	check_eq(bool(ct.button_pressed), false,
		"AC-C1：0 摄像头 → 摄像头钮强制置灭（存档开也不得亮；红态=true）")
	# C2 置灰样式在位 + 仍可点（AB2 语义保持）
	check(_is_gray(gt) and _is_gray(ct), "AC-C2：0 摄像头 → 双钮置灰样式在位")
	check(not bool(gt.disabled) and not bool(ct.disabled),
		"AC-C2：置灰仍可点（AB2「视觉置灰仍可点」语义保持）")
	# C3 点钮 → 提示条 + 视觉回弹
	var mark: int = spy.info_calls.size()
	gt.button_pressed = true
	await process_frame
	check(spy.info_calls.size() > mark
		and String(spy.info_calls[spy.info_calls.size() - 1][0]) == NO_HW_INFO,
		"AC-C3：0 摄像头点手势钮 → 「无硬件摄像头支持」提示条（实际 %s）" % [spy.info_calls])
	check_eq(bool(gt.button_pressed), false, "AC-C3：点手势钮 → 视觉回弹不落开态")
	panel.queue_free()
	await process_frame

	# C4 0 摄像头点摄像头钮 → GET_CAMERAS 零 spawn 零 SWITCH（重扫请求通路）
	# 面板经 autoload 桥出包，故抓包监听 autoload 控制端口（他测同款：占用即环境性失败，单跑甄别）。
	var snif_auto := CtrlSniffer.new()
	var bound_ok: bool = int(snif_auto.bind(int(bridge.call("get_control_port")))) == 0
	check(bound_ok, "段C4 前置：autoload 控制端口抓包器就位（占用即环境性失败，单跑甄别）")
	if bound_ok:
		bridge.set("_last_enum_request_ms", -1000000)   # 复位节流
		bridge.set("_camera_enum_zero", true)
		bridge.set("_camera_enum", {"cameras": [], "current_camera": 0})
		bridge.set("_reattach_intent", false)
		snif_auto.cmds.clear()
		var panel2: Node = await _make_panel()
		var ct2: Button = panel2.get_node_or_null("Panel/VBox/OptionsBox/CameraRow/CameraToggle") as Button
		check(ct2 != null, "段C4 前置：摄像头钮在位")
		if ct2 != null:
			ct2.set_pressed_no_signal(false)
			snif_auto.cmds.clear()
			ct2.button_pressed = true
			var got_c4: bool = await _wait_cmd(snif_auto, "GET_CAMERAS")
			check(got_c4,
				"AC-C4：0 摄像头点摄像头钮 → GET_CAMERAS 重扫请求（实际 %s）" % [snif_auto.cmds])
		var sw_c4 := 0
		var sc_c4 := 0
		for c: Variant in snif_auto.cmds:
			if String(c).begins_with("SWITCH_CAMERA"):
				sw_c4 += 1
			if String(c).begins_with("START_CAMERA_BY_NAME"):
				sc_c4 += 1
		check_eq(sw_c4, 0, "AC-C4：重扫路径零 SWITCH_CAMERA（待命不盲开）")
		check_eq(sc_c4, 0, "AD-C4：重扫路径零 START_CAMERA_BY_NAME（0 摄像头待命不启动）")
		panel2.queue_free()
		await process_frame

		# C5 open_menu（下拉刷新/ArrowBtn 路径）→ GET_CAMERAS 重扫
		# 先置有缓存形态（红态=缓存直读分支零出包），验证批次 AC 新口径「刷新亦重扫」。
		bridge.set("_last_enum_request_ms", -1000000)
		bridge.set("_camera_enum_zero", false)
		bridge.set("_camera_enum", {"cameras": [{"id": 0, "name": "HD Camera"}], "current_camera": 0})
		snif_auto.cmds.clear()
		var menu: Control = (load(MENU_SCRIPT) as GDScript).new()
		root.add_child(menu)
		await process_frame
		menu.call("open_menu")
		var got_c5: bool = await _wait_cmd(snif_auto, "GET_CAMERAS")
		check(got_c5,
			"AC-C5：下拉刷新（open_menu，缓存非空）→ GET_CAMERAS 重扫（热插拔识别；实际 %s）" % [snif_auto.cmds])
		check_eq(int(menu.get("state")), 2,
			"AC-C5 反向护栏：缓存直读分支仍直进 LOADED（重扫不影响既有零等待语义）")
		var sw_c5 := 0
		for c: Variant in snif_auto.cmds:
			if String(c).begins_with("SWITCH_CAMERA"):
				sw_c5 += 1
		check_eq(sw_c5, 0, "AC-C5：重扫路径零 SWITCH_CAMERA（零 spawn 零开镜）")
		menu.free()
		await process_frame

		# C6 反向护栏：重枚举到设备 → 双钮不被迫置灭/置灰
		bridge.set("_camera_enum", {"cameras": [{"id": 0, "name": "HD Camera"}], "current_camera": 0})
		bridge.set("_camera_enum_zero", false)
		save.update_settings({"gesture_input": true, "gesture_camera_enabled": true})
		var panel3: Node = await _make_panel()
		var gt3: Button = panel3.get_node_or_null("Panel/VBox/OptionsBox/GestureToggle") as Button
		var ct3: Button = panel3.get_node_or_null("Panel/VBox/OptionsBox/CameraRow/CameraToggle") as Button
		check(gt3 != null and ct3 != null, "段C6 前置：双钮在位")
		if gt3 != null and ct3 != null:
			check(not _is_gray(gt3) and not _is_gray(ct3),
				"AC-C6 反向护栏：有设备 → 双钮不置灰（防改过头）")
			check_eq(bool(gt3.button_pressed), true,
				"AC-C6 反向护栏：有设备+存档开 → 手势钮照常亮（零门不得误灭）")
		panel3.queue_free()
		await process_frame
		snif_auto.close()

	game.call("attach_strip", null)
	spy.free()

func _initialize() -> void:
	print("== test_ac_batch2_camera ==")
	_backup_user()
	_section_a()
	await _section_b()
	await _section_c()
	finish()
