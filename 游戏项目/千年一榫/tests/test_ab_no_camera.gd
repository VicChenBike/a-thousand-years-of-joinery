extends "res://tests/test_base.gd"
## 批次 AB2（2026-09-25）：「电脑没有摄像头」完整分支 TDD 红测先行。
## 用户需求逐条落实（主会话拍板口径：置灰=视觉置灰仍可点；无摄像头强制手势交互置关写档）。
## 段口径：
##   A（启动链路核实）：ensure_camera_open 记忆设备名优先→列表首项（已实现部分补断言，Y-A16/W2 语义锚）；
##   B（列表为空）：0 设备确认 → ①双钮视觉置灰但 disabled=false 可点（B2）；②HUD 三件套全隐（B3，
##     经 B4 强制写关联动）；③手势交互状态强制置关且存档已写盘（B4）；④点手势钮弹「无硬件摄像头支持」
##     提示条（B5，Game.info→TopStrip info 条=对接失败弹条同组件同锚点）；
##   C（外接摄像头重载）：①点摄像头钮 → GET_CAMERAS 重枚举（C6）+同款提示条；②仍空保持置灰（C7）；
##   ③有设备 → 记忆名恢复/否则首项自动开（C8，zero→非 zero 边沿）；④置灰解除（C9）；手势开关
##   不自动置回开（保持用户意图，C9b 拍板锚）；
##   D（边界）：①空列表下拉占位行（D10）+开下拉重枚举；②空列表**用户点击路径**零 spawn/零
##   SWITCH_CAMERA（D11，_intentional_stop/_camera_release_intent 原样=证明 start_gesture_process
##   未被调用；回修2 口径收敛——watchdog respawn 路径不在此口径内，按意图门语义断言，见 E 段
##   hook 计数替身闭合旧无头不可达零断言）；③反复点击节流（D12，1s 内至多一次 GET_CAMERAS）；
##   ④反向护栏：有设备不得置灰/隐藏（g）。
##   E（批次 AB2 R1 审查回修1/2/3，2026-09-26）：①zero 确认边沿 → 恰一次 RELEASE_CAMERA
##   （E1，就地释放兜住假阴性 python 首开）；②无重枚举意图 → zero 态 respawn 零调用（E2，
##   watchdog 改发 GET_CAMERAS 试探）；③有重枚举意图 → respawn 允许恰一次（E3 正向护栏）；
##   ④意图收到枚举结果即清除（E4）；⑤C6/C8 链新门下零回归（E5，复用段 C 断言）；⑥灰档几何
##   与常态档逐项相等·仅换色（E6，回修3 补投影）。respawn 断言经 _spawn_hook 计数替身无头可达
##  （回修2：旧 watchdog respawn 路径无头不可达致零断言，现以 hook 计数闭合）。
## 清档纪律：user:// 备份还原（前缀 abnc，test_y_zero_camera_gate 同款四件组）；零摄像头纪律：
##   全程无头，设备枚举一律 simulate_packet 注入，绝无真实摄像头触碰。

const PANEL_SCENE := "res://scenes/settings/settings_panel.tscn"
const PANEL_SCRIPT := "res://scenes/settings/settings_panel.gd"
const BR_SCRIPT := "res://autoload/gesture_bridge.gd"
const HUD_SCENE := "res://scenes/shared/gesture_hud.tscn"
const SAVE_PATH := "user://save.json"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"
const FLAG_PATH := "user://first_launch.flag"
const BK_PREFIX := "user://_abnc_backup_"
const WATCHED: Array = [SAVE_PATH, TMP_PATH, BAK_PATH, FLAG_PATH]
const AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
const NO_HW_INFO := "无硬件摄像头支持"          # AB2-B5：点击置灰钮提示条（样式=对接失败弹条同源）
const ZERO_PLACEHOLDER := "未检测到摄像头"       # D10：下拉占位行（批次 W 既有文案锚）

## TopStrip 替身（test_y_settings_camera_flow StripSpy 同款）：push_info=对接失败弹条同通道
##（Game.toast(centered=true)→TopStrip.push_info，TopStrip info 条=同一组件同一样式档）。
class StripSpy extends Node:
	var info_calls: Array = []
	func push_info(text: String, seconds: float = 3.0) -> void:
		info_calls.append([text, seconds])

var _save: Node = null
var _bridge: Node = null
var _game: Node = null
var _pre_save_text := ""

func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _backup_user() -> void:
	for p0: String in WATCHED:
		var bk0 := BK_PREFIX + p0.get_file()
		if FileAccess.file_exists(_abs(bk0)):
			if FileAccess.file_exists(_abs(p0)):
				DirAccess.remove_absolute(_abs(p0))
			DirAccess.copy_absolute(_abs(bk0), _abs(p0))
			DirAccess.remove_absolute(_abs(bk0))
	if FileAccess.file_exists(_abs(SAVE_PATH)):
		_pre_save_text = FileAccess.get_file_as_string(SAVE_PATH)
	for p: String in WATCHED:
		if FileAccess.file_exists(p):
			var bk := BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_abs(p), _abs(bk))
	if FileAccess.file_exists(_abs(SAVE_PATH)):
		DirAccess.remove_absolute(_abs(SAVE_PATH))
	_save.call("load_game")

func _restore_user() -> void:
	for c: Node in root.get_children():
		if not AUTOLOADS.has(String(c.name)):
			c.free()
	for p: String in WATCHED:
		if FileAccess.file_exists(_abs(p)):
			DirAccess.remove_absolute(_abs(p))
		var bk := BK_PREFIX + p.get_file()
		if FileAccess.file_exists(_abs(bk)):
			DirAccess.copy_absolute(_abs(bk), _abs(p))
			DirAccess.remove_absolute(_abs(bk))
	var real_sm: Node = root.get_node_or_null("SaveManager")
	if real_sm != null:
		real_sm.load_game()
	var post: String = FileAccess.get_file_as_string(_abs(SAVE_PATH)) if FileAccess.file_exists(_abs(SAVE_PATH)) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")

func finish() -> void:
	_restore_user()
	super.finish()

## 桥态复位（段间隔离；摄像头红线：仅注入，绝无真实设备触碰）
func _reset_bridge(zero: bool) -> void:
	_bridge.set("_camera_enum", {"cameras": [], "current_camera": 0} if zero else {})
	_bridge.set("_camera_enum_zero", zero)
	_bridge.set("_reattach_intent", false)   # 回修1：段间清意图锁存（防泄入后续段）
	_bridge.set("camera_stream_open", false)
	_bridge.set("camera_stream_device_id", -1)
	_bridge.set("_intentional_stop", false)
	_bridge.set("_camera_release_intent", false)
	_bridge.set("_last_switch_camera_id", -1)
	_bridge.set("_simulate_start_ok", false)

## 9878 控制端口监听器（test_fixpack_camera_enum F2 同款回环手法；收包→字符串数组）
class CtrlListener extends PacketPeerUDP:
	func wait_cmds(frames: int) -> Array:
		var cmds: Array = []
		for i: int in frames:
			while get_available_packet_count() > 0:
				cmds.append(get_packet().get_string_from_utf8())
			await Engine.get_main_loop().process_frame
		while get_available_packet_count() > 0:
			cmds.append(get_packet().get_string_from_utf8())
		return cmds

func _switch_cmds(cmds: Array) -> Array:
	## 批次 AD（spec §4.2.2-3）等价改写：开镜指令家族含新协议 START_CAMERA_BY_NAME:<名>
	## 与兼容旧协议 SWITCH_CAMERA:<id>——本谓词统一收集（名不变=调用点零改）。
	var out: Array = []
	for c: Variant in cmds:
		if String(c).begins_with("SWITCH_CAMERA") or String(c).begins_with("START_CAMERA_BY_NAME"):
			out.append(String(c))
	return out

## 同步排空监听器→命令字符串数组（E 段专用：simulate/_process 均同步发包，无需协程窗）。
func _drain_cmds(l: PacketPeerUDP) -> Array:
	var out: Array = []
	while l.get_available_packet_count() > 0:
		out.append(l.get_packet().get_string_from_utf8())
	return out

func _count_prefix(cmds: Array, p: String) -> int:
	var n: int = 0
	for c: Variant in cmds:
		if String(c).begins_with(p):
			n += 1
	return n

## 成员字符串读（回修断言防「成员缺失=null」崩 _initialize：一律 str() 比较，红态干净）。
func _member_str(o: Object, m: String) -> String:
	return str(o.get(m))

func _make_panel() -> Node:
	var panel: Node = (load(PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await process_frame
	await process_frame
	return panel

func _zero_gray_map() -> Dictionary:
	var sp: GDScript = load(PANEL_SCRIPT)
	var cm: Dictionary = sp.get_script_constant_map()
	# 批次 AB-3：深浅主题机制删除——恒深档（旧 is_dark() 探测随功能退役，
	# 与生产 _apply_zero_gray_overlay 唯一真值 ZERO_GRAY_BG_DARK 同口径；探针 ab2 gray probe 留痕）
	return {
		"bg": cm.get("ZERO_GRAY_BG_DARK", null),   # AB-3 恒深档（浅支随机制删除退役）
		"font": cm.get("ZERO_GRAY_FONT", null),
	}

func _is_gray(btn: Button) -> bool:
	var m: Dictionary = _zero_gray_map()
	if m["bg"] == null or m["font"] == null:
		return false
	var sb: StyleBoxFlat = btn.get_theme_stylebox("normal") as StyleBoxFlat
	return sb != null and sb.bg_color == Color(m["bg"]) \
		and btn.get_theme_color("font_color") == Color(m["font"])

## 同步排空监听器残留包（替代 fire-and-forget wait_cmds 清窗——协程恢复序竞态会吞掉
## 随后同步发出的 GET_CAMERAS，C6b/D10b 假红根因）。
func _drain(l: PacketPeerUDP) -> void:
	while l.get_available_packet_count() > 0:
		l.get_packet()

func _initialize() -> void:
	print("== test_ab_no_camera ==")
	_save = root.get_node("SaveManager")
	_bridge = root.get_node("GestureBridge")
	_game = root.get_node("Game")
	await process_frame   # 树激活：autoload _ready 完成后再驱动 goto_state
	# --script 无头 Game._state 恒 BOOT——预置 MAIN_MENU（只改状态机不切场景，
	# 批次 N 坑⑨），否则 apply_dock_state 的 BOOT 门把 HUD 恒隐（B3 因果链失真）。
	_game.call("goto_state", _game.State.MAIN_MENU)
	_backup_user()
	var spy := StripSpy.new()
	root.add_child(spy)
	_game.attach_strip(spy)

	# ================= 段 A（A1 启动链路核实：记忆名优先→首项） =================
	_save.update_settings({"gesture_input": true, "gesture_camera_enabled": true})
	_reset_bridge(false)
	_bridge.set("_simulate_start_ok", true)
	_bridge.set("_camera_enum", {"cameras": [{"id": 0, "name": "CamA"}, {"id": 1, "name": "CamB"}], "current_camera": 0})
	var lsn_a := CtrlListener.new()
	check_eq(int(lsn_a.bind(_bridge.get_control_port())), 0, "段A 前置：9878 回环监听绑定成功")
	# A1a 记忆名命中 → SWITCH 到记忆设备（W2/Y-A16 既有语义锚，AB2 补断言）
	_save.update_settings({"gesture_camera_device": "CamB"})
	_drain(lsn_a)   # 同步清窗（防协程竞态吞包）
	_bridge.call("ensure_camera_open")
	var cmds_a: Array = await lsn_a.wait_cmds(6)
	check(_switch_cmds(cmds_a).has("START_CAMERA_BY_NAME:CamB"),
		"AB2-A1a（AD 等价改写）：记忆名「CamB」在列 → ensure 按名下发启动指令（旧断言为 SWITCH_CAMERA:1；实际 %s）" % [cmds_a])
	# A1b 无记忆 → 列表首项
	_save.update_settings({"gesture_camera_device": ""})
	_bridge.call("ensure_camera_open")
	var cmds_a2: Array = await lsn_a.wait_cmds(6)
	check(_switch_cmds(cmds_a2).has("START_CAMERA_BY_NAME:"),
		"AB2-A1b（AD 等价改写）：未记忆设备 → 空载荷启动指令（降级首项下沉 Python；旧断言为 SWITCH_CAMERA:0；实际 %s）" % [cmds_a2])
	lsn_a.close()

	# ================= 段 B（列表为空：置灰可点/全隐/强制写关/提示条） =================
	_reset_bridge(false)
	_save.update_settings({"gesture_input": true, "gesture_camera_enabled": true, "gesture_camera_device": ""})
	# HUD 挂载并先置「可见」前态（流开启真值 true；证明 zero→隐藏的**转变**而非恒隐）
	var hud: Control = (load(HUD_SCENE) as PackedScene).instantiate()
	root.add_child(hud)
	await process_frame
	await process_frame
	_bridge.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "CamA"}))
	await process_frame
	hud.call("apply_dock")   # 流边沿不自动重排 hud 单实例（main.gd 才订阅重算），显式驱动前态
	check(bool(hud.visible), "段B 前置：流开启+手势开 → HUD 可见（转变前态成立）")
	# 注入 init#1 空列表（0 设备确认边沿）——绝无真实枚举，纯注入；流真值保持 true：
	# 旧实现此处 HUD 仍显（无强制写关），新实现经 B4 写关把 HUD 压隐（B3 红测的因果链）
	_bridge.simulate_packet(JSON.stringify({"type": "init", "cameras": [], "current_camera": 0}))
	await process_frame
	# B4a 内存置关
	check_eq(bool(_save.get_settings().get("gesture_input", true)), false,
		"AB2-B4a：0 设备确认 → 手势交互状态强制置关（内存）")
	# B4b 存档已写盘（update_settings→save_game 即时落盘）
	var disk: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	var disk_gesture: Variant = (disk as Dictionary).get("settings", {}).get("gesture_input", true) \
		if typeof(disk) == TYPE_DICTIONARY else true
	check_eq(bool(disk_gesture), false,
		"AB2-B4b：0 设备确认 → 手势交互置关已写入磁盘存档（settings.gesture_input=false）")
	# B3 HUD 三件套全隐（说明栏/状态条/摄像头窗——整组隐藏=三者全隐单一真值）
	check_eq(bool(hud.visible), false, "AB2-B3a：0 摄像头强制写关 → HUD 整组隐藏")
	check(not hud.get_node("CameraWindow").is_visible_in_tree() \
		and not hud.get_node("StatusRow").is_visible_in_tree() \
		and not hud.get_node("GuidePanel").is_visible_in_tree(),
		"AB2-B3b：摄像头窗/左右手状态条/说明栏 is_visible_in_tree 全 false")
	# B2 面板双钮视觉置灰但可点
	var panel: Node = await _make_panel()
	var gt: Button = panel.get_node("Panel/VBox/OptionsBox/GestureToggle")
	var ct: Button = panel.get_node("Panel/VBox/OptionsBox/CameraRow/CameraToggle")
	check(gt != null and ct != null, "段B 前置：手势/摄像头钮在位")
	check(not bool(gt.disabled) and not bool(ct.disabled),
		"AB2-B2a：0 摄像头 → 双钮 disabled=false（视觉置灰仍可点，旧真禁用退役）")
	check(_is_gray(gt) and _is_gray(ct),
		"AB2-B2b：0 摄像头 → 双钮置灰样式在位（灰底+灰字）")
	# B5 点手势钮 → 「无硬件摄像头支持」提示条（TopStrip info 条=对接失败弹条同组件同锚点）
	_bridge.set("_intentional_stop", true)   # 侧证：若误调 start_gesture_process 会被清零
	_bridge.set("_camera_release_intent", true)
	lsn_a = CtrlListener.new()
	lsn_a.bind(_bridge.get_control_port())
	_drain(lsn_a)   # 同步清窗（防协程竞态吞包）
	gt.set_pressed_no_signal(false)   # 先压视觉到关（模拟存档关态），再点击——保证 toggled 真触发
	gt.button_pressed = true   # 触发 toggled（点击路径）
	await process_frame
	check(spy.info_calls.size() > 0 and String(spy.info_calls[spy.info_calls.size() - 1][0]) == NO_HW_INFO,
		"AB2-B5a：0 摄像头点手势钮 → 「无硬件摄像头支持」提示条（TopStrip push_info=对接失败弹条同通道）")
	check_eq(bool(gt.button_pressed), false, "AB2-B5b：点手势钮 → 视觉回弹（不落开态）")
	check_eq(bool(_save.get_settings().get("gesture_input", true)), false,
		"AB2-B5c：点手势钮 → 存档仍为关（不触四象限写档）")
	check_eq(bool(_bridge.get("_intentional_stop")), true,
		"AB2-B5d：点手势钮 → _intentional_stop 原样（证明 start_gesture_process 未被调用=零 spawn）")
	check(_switch_cmds(await lsn_a.wait_cmds(4)).is_empty(),
		"AB2-B5e：点手势钮 → 零 SWITCH_CAMERA 出包")

	# ================= 段 C（重枚举：点摄像头钮→GET_CAMERAS；恢复→记忆名/首项自动开） =================
	# C6 点摄像头钮 → 重枚举 + 同款提示条
	_bridge.set("_last_enum_request_ms", -1000000)   # 复位节流（注入惯例）
	_drain(lsn_a)   # 同步清窗（防协程竞态吞包）
	ct.set_pressed_no_signal(false)   # 先压视觉到关再点击，保证 toggled 真触发
	ct.button_pressed = true   # 触发 toggled（点击路径）
	await process_frame
	var cmds_c: Array = await lsn_a.wait_cmds(6)
	check(spy.info_calls.size() > 0 and String(spy.info_calls[spy.info_calls.size() - 1][0]) == NO_HW_INFO,
		"AB2-C6a：0 摄像头点摄像头钮 → 同款「无硬件摄像头支持」提示条")
	check(cmds_c.has("GET_CAMERAS"),
		"AB2-C6b：0 摄像头点摄像头钮 → GET_CAMERAS 重枚举出包（实际 %s）" % [cmds_c])
	check(_switch_cmds(cmds_c).is_empty() and bool(_bridge.get("_intentional_stop")),
		"AB2-C6c：点摄像头钮 → 零 SWITCH_CAMERA 且 start 未被调用（D11 前半）")
	# D12 节流：1s 内第二击零出包
	_bridge.set("_last_enum_request_ms", int(Time.get_ticks_msec()))   # 刚发过（同秒内）
	ct.button_pressed = true
	await process_frame
	check(_switch_cmds(await lsn_a.wait_cmds(4)).is_empty(),
		"AB2-D12a：1s 内重复点摄像头钮 → 节流零重复出包（零 SWITCH 顺带锚定）")
	# C7 仍为空 → 保持置灰
	_bridge.simulate_packet(JSON.stringify({"type": "init", "cameras": [], "current_camera": 0}))
	await process_frame
	check(bool(_bridge.call("is_camera_enum_zero")) and _is_gray(gt) and _is_gray(ct) \
		and not bool(gt.disabled) and not bool(ct.disabled),
		"AB2-C7：重枚举仍空 → 0 确认保持+置灰保持+仍可点")
	# C8a 重枚举到设备（记忆名命中）→ 自动开记忆设备（zero→非 zero 边沿）
	_save.update_settings({"gesture_camera_device": "CamB"})
	_bridge.set("_simulate_start_ok", true)
	_bridge.set("_intentional_stop", false)
	_bridge.set("_camera_release_intent", false)
	_bridge.set("_camera_enum", {"cameras": [], "current_camera": 0})
	_bridge.simulate_packet(JSON.stringify({"type": "init",
		"cameras": [{"id": 0, "name": "CamA"}, {"id": 1, "name": "CamB"}], "current_camera": 0}))
	await process_frame
	var cmds_c8: Array = await lsn_a.wait_cmds(6)
	check(_switch_cmds(cmds_c8).has("START_CAMERA_BY_NAME:CamB"),
		"AB2-C8a（AD 等价改写）：重枚举到设备（记忆名 CamB 在列）→ 按名下发启动指令（旧断言为 SWITCH_CAMERA:1；实际 %s）" % [cmds_c8])
	# C9a 置灰解除
	check(not _is_gray(gt) and not _is_gray(ct) and not bool(gt.disabled) and not bool(ct.disabled),
		"AB2-C9a：恢复设备 → 双钮置灰解除（样式与 disabled 复常）")
	# C9b 手势开关不自动置回开（保持用户意图拍板：恢复=开摄像头，不替用户开手势）
	check_eq(bool(gt.button_pressed), false, "AB2-C9b-1：恢复设备 → 手势开关保持关（不自动置开）")
	check_eq(bool(_save.get_settings().get("gesture_input", true)), false,
		"AB2-C9b-2：恢复设备 → 存档 gesture_input 仍 false（用户手动开启）")
	# C8b 无记忆 → 自动开首项
	_reset_bridge(true)
	_save.update_settings({"gesture_camera_device": ""})
	_bridge.set("_simulate_start_ok", true)
	_bridge.simulate_packet(JSON.stringify({"type": "init", "cameras": [{"id": 0, "name": "CamA"}], "current_camera": 0}))
	await process_frame
	var cmds_c8b: Array = await lsn_a.wait_cmds(6)
	check(_switch_cmds(cmds_c8b).has("START_CAMERA_BY_NAME:"),
		"AB2-C8b（AD 等价改写）：无记忆重枚举到设备 → 空载荷启动指令（旧断言为 SWITCH_CAMERA:0；实际 %s）" % [cmds_c8b])

	# ================= 段 D（边界：占位行/零 SWITCH 直调/开下拉重枚举/反向护栏） =================
	_reset_bridge(true)
	_save.update_settings({"gesture_input": false, "gesture_camera_enabled": true})
	var panel2: Node = await _make_panel()
	var gt2: Button = panel2.get_node("Panel/VBox/OptionsBox/GestureToggle")
	var menu_holder: Node = panel2.get_node("CameraMenuLayer/CameraMenuPopup/CameraMenu")
	# D11 直接调 ensure（0 确认态）→ false + 零 SWITCH + 锁存原样（未触碰任何开镜路径）
	_bridge.set("_simulate_start_ok", true)
	_bridge.set("_intentional_stop", true)
	_bridge.set("_camera_release_intent", true)
	_drain(lsn_a)   # 同步清窗（防协程竞态吞包）
	var ok_d: bool = bool(_bridge.call("ensure_camera_open"))
	check_eq(ok_d, false, "AB2-D11a：0 设备确认态 ensure_camera_open → false（旧回落 0 漏门根除）")
	check(_switch_cmds(await lsn_a.wait_cmds(4)).is_empty() \
		and bool(_bridge.get("_intentional_stop")) and bool(_bridge.get("_camera_release_intent")),
		"AB2-D11b：0 设备确认态 ensure → 零 SWITCH 且 release/主动关锁存原样（短路先于副作用）")
	# D10 空列表下拉占位行 + 开下拉重枚举（点击摄像头列表按钮=重枚举机会）
	_bridge.set("_last_enum_request_ms", -1000000)
	_drain(lsn_a)   # 同步清窗（防协程竞态吞包）
	menu_holder.call("open_menu")
	await process_frame
	var cmds_d: Array = await lsn_a.wait_cmds(6)
	var box: Node = menu_holder.get("_root_box")
	var texts: Array = []
	for ch: Node in box.get_children():
		texts.append(String(ch.text) if ch is Label or ch is Button else "")
	check(texts.has(ZERO_PLACEHOLDER),
		"AB2-D10a：0 摄像头开下拉 → 「未检测到摄像头」占位行（非空白非报错；实际 %s）" % [texts])
	check(cmds_d.has("GET_CAMERAS"),
		"AB2-D10b：0 摄像头开下拉（摄像头列表按钮）→ GET_CAMERAS 重枚举（实际 %s）" % [cmds_d])
	check(_switch_cmds(cmds_d).is_empty(),
		"AB2-D10c：开下拉 → 零 SWITCH_CAMERA 零 spawn（D11）")
	menu_holder.call("_close_subs")
	# g 反向护栏：有设备态不得置灰/隐藏/拦截
	_reset_bridge(false)
	_save.update_settings({"gesture_input": true, "gesture_camera_enabled": true})
	_bridge.set("_camera_enum", {"cameras": [{"id": 0, "name": "CamA"}], "current_camera": 0})
	var panel3: Node = await _make_panel()
	var gt3: Button = panel3.get_node("Panel/VBox/OptionsBox/GestureToggle")
	var ct3: Button = panel3.get_node("Panel/VBox/OptionsBox/CameraRow/CameraToggle")
	check(not _is_gray(gt3) and not _is_gray(ct3) and not bool(gt3.disabled) and not bool(ct3.disabled),
		"AB2-g1：有摄像头 → 双钮不置灰可点（防改过头）")
	var info_mark: int = spy.info_calls.size()
	gt3.button_pressed = true
	await process_frame
	check(spy.info_calls.size() == info_mark,
		"AB2-g2：有摄像头点手势钮 → 无「无硬件」提示（正常四象限路径）")
	check_eq(bool(_save.get_settings().get("gesture_input", false)), true,
		"AB2-g3：有摄像头点手势钮 → 存档照常写开（四象限不受扰）")
	var hud3: Control = (load(HUD_SCENE) as PackedScene).instantiate()
	root.add_child(hud3)
	await process_frame
	_bridge.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "CamA"}))
	await process_frame
	hud3.call("apply_dock")   # 流边沿不自动重排 hud 单实例，显式驱动（段B 前置同款）
	check(bool(hud3.visible), "AB2-g4：有摄像头+流开启+手势开 → HUD 可见（三真值不受零门误伤）")

	# ================= 段 E（批次 AB2 R1 审查回修1/2/3）：zero 边沿 RELEASE / zero 态
	# respawn 意图门（hook 计数替身，回修2 补旧无头不可达零断言）/ 灰档几何逐项相等 =========
	# 自有桥实例（高位 override 20330，9876~9878 零触碰；probe mock 子类同款
	# test_aa_camera_lifecycle 段A）；设备枚举/状态一律 simulate_packet 注入，绝无真实摄像头。
	var sub_e := GDScript.new()
	sub_e.source_code = """
extends "res://autoload/gesture_bridge.gd"
var probe_ret: bool = false
func _probe_python_ready() -> bool:
	return probe_ret
"""
	check_eq(int(sub_e.reload()), 0, "段E 前置：probe mock 子类编译成功")
	_save.update_settings({"gesture_input": true, "gesture_camera_enabled": true})
	var br_e: Node = sub_e.new()
	br_e.set("_udp_port_override", 20330)
	root.add_child(br_e)
	await process_frame
	var lsn_e := CtrlListener.new()
	check_eq(int(lsn_e.bind(20332)), 0, "段E 前置：自有桥控制端口抓包器就位（兼 probe 占用形态）")
	var cnt_e := {"n": 0}
	br_e.set("_spawn_hook", func() -> bool:
		cnt_e["n"] += 1
		return true)
	# E1 zero 确认边沿 → 恰一次 RELEASE_CAMERA（回修1：就地释放意图兜假阴性 python 首开）
	br_e.simulate_packet(JSON.stringify({"type": "init", "cameras": [], "current_camera": 0}))
	var cmds_e1: Array = _drain_cmds(lsn_e)
	check_eq(_count_prefix(cmds_e1, "RELEASE_CAMERA"), 1,
		"R1回修1/E1a：zero 确认边沿 → RELEASE_CAMERA 恰一次（红态=0；实际 %s）" % [cmds_e1])
	# 非边沿（已 zero 再收空枚举）→ 不重复发（边沿语义，防逐包刷 9878）
	br_e.simulate_packet(JSON.stringify({"type": "init", "cameras": [], "current_camera": 0}))
	cmds_e1 = _drain_cmds(lsn_e)
	check_eq(_count_prefix(cmds_e1, "RELEASE_CAMERA"), 0,
		"R1回修1/E1b：zero 保持态再收空枚举 → 零重复 RELEASE（边沿语义）")
	# B4 联动保持：手势强制写关（回修1 不弱化既有语义）
	check_eq(bool(_save.get_settings().get("gesture_input", true)), false,
		"R1回修1/E1c：zero 边沿 → B4 强制写关保持（OR 门仍开=摄像头键 true，respawn 面由意图门独立收口）")
	# E2 无重枚举意图 → zero 态 respawn 零调用（回修2：hook 计数替身断旧不可达路径）+改发试探
	br_e.set("probe_ret", false)   # python 不在 → UNAVAILABLE 互补分支（真死重拉形态）
	br_e.set("_process_pid", 999999999)
	br_e.call("_check_process_alive")   # 判死 → UNAVAILABLE + 退避
	br_e.set("_respawn_block_until", -1.0)
	br_e.set("_last_retry_at", -1000.0)
	br_e.set("_last_enum_request_ms", -1000000)
	br_e.call("_process", 0.016)
	check_eq(int(cnt_e["n"]), 0,
		"R1回修1/E2a：zero ∧ 无意图 → respawn 零调用（含 hook 替身一并短路；红态=1；实际 %d）" % int(cnt_e["n"]))
	var cmds_e2: Array = _drain_cmds(lsn_e)
	check_eq(_count_prefix(cmds_e2, "GET_CAMERAS"), 1,
		"R1回修1/E2b：门拒 respawn → 改发零 spawn 重枚举试探 GET_CAMERAS（红态=0；实际 %s）" % [cmds_e2])
	check_eq(_count_prefix(cmds_e2, "SWITCH_CAMERA"), 0, "R1回修1/E2c：试探路径零 SWITCH_CAMERA（D11 口径不扩体）")
	# E3 有重枚举意图（用户点摄像头钮=公开入口 request_camera_enum）→ respawn 允许恰一次（正向护栏）
	br_e.call("request_camera_enum")   # 公开入口：置意图 + GET_CAMERAS
	check_eq(_member_str(br_e, "_reattach_intent"), "true",
		"R1回修1/E3a：公开 request_camera_enum（C6/D10 用户触达）→ 意图锁存置位（红态=null/false）")
	_drain_cmds(lsn_e)   # 清 E3a 顺带包
	br_e.call("_set_state", 2)   # UNAVAILABLE（E2 固定代码路径本态=UNAVAILABLE；HEAD 红态路径
	# 被 _spawn 成功带进 LOADING→此处显式复位，保证红/绿两态同走 respawn 互补分支、E3b 判据纯粹）
	br_e.set("_respawn_block_until", -1.0)
	br_e.set("_last_retry_at", -1000.0)
	br_e.call("_process", 0.016)
	check_eq(int(cnt_e["n"]), 1,
		"R1回修1/E3b：zero ∧ 有意图 → respawn 放行恰一次（C6/C8 链不破坏·防改过头；红态=0；实际 %d）" % int(cnt_e["n"]))
	# E4 意图在收到枚举结果（init#1 cameras）后清除（一次点击只兑一次 respawn 机会）
	br_e.simulate_packet(JSON.stringify({"type": "init", "cameras": [], "current_camera": 0}))
	check_eq(_member_str(br_e, "_reattach_intent"), "false",
		"R1回修1/E4a：枚举结果到达 → 意图清除（红态=true/成员缺失）")
	br_e.call("_set_state", 2)   # UNAVAILABLE（重拉后又死形态，复位意图门复验）
	br_e.set("_respawn_block_until", -1.0)
	br_e.set("_last_retry_at", -1000.0)
	br_e.set("_last_enum_request_ms", -1000000)
	br_e.call("_process", 0.016)
	check_eq(int(cnt_e["n"]), 1,
		"R1回修1/E4b：意图清除后再轮 watchdog → 回归零 respawn（恰一次兑现；红态=2）")
	# E5 C6/C8 链零回归源锚 + 行为锚：段 C 既有断言（点击→GET_CAMERAS→重枚举→SWITCH 自动开）
	# 全绿即链通（本文件段 C 在回修后代码上照常通过）；此处补「桥内部自动拉取不置意图」锚。
	var bsrc_e: String = FileAccess.get_file_as_string(BR_SCRIPT)
	check(bsrc_e.contains("_pull_camera_enum"),
		"R1回修1/E5a：源锚——桥内部拉取（READY 边沿/事件刷新/试探）走 _pull_camera_enum 与用户意图置位分离")
	var br_e2: Node = sub_e.new()
	br_e2.set("_udp_port_override", 20334)
	root.add_child(br_e2)
	await process_frame
	var lsn_e2 := CtrlListener.new()
	check_eq(int(lsn_e2.bind(20336)), 0, "段E 前置：E5b 抓包器就位")
	br_e2.call("_set_state", 1)   # READY 边沿（枚举缓存空）→ 自动拉取
	var cmds_e5: Array = _drain_cmds(lsn_e2)
	check_eq(_count_prefix(cmds_e5, "GET_CAMERAS"), 1,
		"R1回修1/E5b：READY 边沿自动拉取 GET_CAMERAS 恰一次（行为不回归）")
	check_eq(_member_str(br_e2, "_reattach_intent"), "false",
		"R1回修1/E5c：自动拉取不置重枚举意图（防自动路径自我解锁 respawn 门）")
	lsn_e2.close()
	br_e2.free()
	# E6（回修3/P3-1）：灰档几何与常态档逐项相等·仅换色（红态=灰档 shadow_* 三项为 0/默认）
	_reset_bridge(true)
	var panel_e: Node = await _make_panel()
	var gt_e: Button = panel_e.get_node("Panel/VBox/OptionsBox/GestureToggle")
	var ht_e: Button = panel_e.get_node("Panel/VBox/OptionsBox/HudToggle")
	ht_e.set_pressed_no_signal(false)   # 常态档取「关态」盒（同灰档无金边可比几何全项）
	panel_e.call("_apply_toggle_style")
	var gsb: StyleBoxFlat = gt_e.get_theme_stylebox("normal") as StyleBoxFlat
	var nsb: StyleBoxFlat = ht_e.get_theme_stylebox("normal") as StyleBoxFlat
	check(gsb != null and nsb != null, "段E 前置：灰档/常态档 normal 盒在位")
	if gsb != null and nsb != null:
		# 几何读取一律属性式（get_corner_radius_all 系 setter-only，实例读取会 SCRIPT ERROR
		# 中断 _initialize——4.7 探针实证；四角恒等由 setter 写入侧保证）。
		check_eq(int(gsb.corner_radius_top_left), int(nsb.corner_radius_top_left), "R1回修3/E6a-1：圆角左上逐项相等")
		check_eq(int(gsb.corner_radius_bottom_right), int(nsb.corner_radius_bottom_right), "R1回修3/E6a-2：圆角右下逐项相等")
		check_eq(float(gsb.content_margin_left), float(nsb.content_margin_left), "R1回修3/E6b：左边距相等（18）")
		check_eq(float(gsb.content_margin_right), float(nsb.content_margin_right), "R1回修3/E6c：右边距相等（18）")
		check_eq(float(gsb.content_margin_top), float(nsb.content_margin_top), "R1回修3/E6d：上边距相等（10）")
		check_eq(int(gsb.shadow_size), int(nsb.shadow_size), "R1回修3/E6e：shadow_size 相等（红态=灰档 0 vs 常态 8）")
		check_eq(str(gsb.shadow_offset), str(nsb.shadow_offset), "R1回修3/E6f：shadow_offset 相等（3,5）")
		check_eq(str(gsb.shadow_color), str(nsb.shadow_color), "R1回修3/E6g：shadow_color 相等")
		check(gsb.bg_color != nsb.bg_color, "R1回修3/E6h：底色与常态档不同（仅换色语义）")
	# E7（回修2 口径收敛源锚）：面板 zero 点击注释口径=「用户点击路径零 spawn」；
	# respawn 路径语义=意图门（E2/E3 已行为锁定）。锚 _spawn 源含意图门。
	check(bsrc_e.contains("if _camera_enum_zero and not _reattach_intent:"),
		"R1回修1/E7：源锚——_spawn 漏斗含「zero ∧ 无意图拒 respawn」第二道门")
	br_e.set("_spawn_hook", Callable())
	lsn_e.close()
	br_e.free()
	panel_e.queue_free()
	_reset_bridge(false)
	_save.update_settings({"gesture_input": true})   # 段E B4 联动写关复位（防泄入收尾断言）
	await process_frame


	# ================= 收尾复位 =================
	hud.free()
	hud3.free()
	panel.queue_free()
	panel2.queue_free()
	panel3.queue_free()
	await process_frame
	lsn_a.close()
	_reset_bridge(false)
	_bridge.set("_simulate_start_ok", false)
	_game.attach_strip(null)
	spy.free()
	finish()
