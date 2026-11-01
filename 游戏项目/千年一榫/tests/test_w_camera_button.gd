extends "res://tests/test_base.gd"
## 批次 W W4（2026-09-20 规格 §5）——摄像头按钮真实状态机（N5 拍板 5）+ 跨场景去重发（N9）。
## 段口径：
##   A（N9）：ensure_camera_open 已连接（READY）且目标设备==当前设备 → 不重发 SWITCH（no-op
##     直亮，抓包零命令）；目标≠当前 → 恰一发；PROBE_MATRIX 探测与主流互斥（在飞丢弃、回包
##     恢复、SWITCH 抢占）。
##   B（N5）：按钮亮=桥 READY 且摄像头开；点击→OPENING（禁用+「打开中」文案）→READY 收口转亮；
##     camera_error 命中目标 → 批次 Z Z4-④ 回落抢句柄退役：失败收口退出 OPENING（attempt 零迁移）；
##     四象限路径「关手势→关摄像头→开手势→按钮能开摄像头」全链通。
## 抓包：测试桥实例注入高位端口 override，控制端口=override+2 上绑监听套接字逐包核对。
## 无头纪律：不真拉起子进程；user:// 备份还原（前缀 w4cb，面板四象限写档兜底）。

const BR_SCRIPT := "res://autoload/gesture_bridge.gd"
const PANEL_SCENE := "res://scenes/settings/settings_panel.tscn"
const TEST_PORT := 19730

# ===== 清档纪律（test_gesture_settings_save 同款，前缀独立 w4cb）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_w4cb_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
var _pre_save_text: String = ""

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _backup_user() -> void:
	# 自愈（规范第 5 条）：上次强杀残留的备份先还原到磁盘，再重新备份——防陈旧备份污染还原等价自检
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
		if FileAccess.file_exists(_disc_abs(p)):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(_disc_abs(p)):
			DirAccess.remove_absolute(_disc_abs(p))
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(_disc_abs(bk)):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(_disc_abs(bk))
	var real_sm: Node = root.get_node_or_null("SaveManager")
	if real_sm != null:
		real_sm.load_game()
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")

func finish() -> void:
	for c: Node in root.get_children():
		if not ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager", "GestureBridge",
				"LevelLibrary", "Game", "GestureRouter", "I18n"].has(String(c.name)):
			c.free()
	_restore_user()
	super.finish()

## 控制端口抓包器（绑 override+2，drain 收集命令行）
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

func _initialize() -> void:
	print("== test_w_camera_button ==")
	_backup_user()
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(_disc_abs(p)):
			DirAccess.remove_absolute(_disc_abs(p))
	get_root().get_node("SaveManager").call("load_game")

	# ---- 段 A（N9）：ensure 去重发 + 探测互斥（测试桥实例 + 控制端口抓包）----
	var br: Node = (load(BR_SCRIPT) as GDScript).new()
	br.set("_udp_port_override", TEST_PORT)
	add_child(br)
	await process_frame
	var snif := CtrlSniffer.new()
	check_eq(int(snif.bind(TEST_PORT + 2)), 0, "A 前置：控制端口抓包器就位")
	var cams: Array = [{"id": 0, "name": "HD Camera"}, {"id": 1, "name": "Virtual Cam"}]
	# A1 已连接且目标==当前 → no-op（零命令）
	# 批次 Y（Y-A18）：no-op 门以「摄像头流开启真值」判定——注入流已开（事件直达形态）。
	br.set("camera_stream_open", true)
	br.set("_camera_enum", {"cameras": cams, "current_camera": 0})
	br._set_state(1)   # READY
	var r1: bool = bool(br.call("ensure_camera_open"))
	check_eq(r1, true, "A1：ensure 返回 true（no-op 直亮）")
	check_eq(snif.count_prefix("START_CAMERA_BY_NAME"), 0,
		"N9①/AD：READY+流开+目标==当前 → 零启动指令（跨场景去重发；Y-A18 真值判定）")
	check_eq(snif.count_prefix("SWITCH_CAMERA"), 0, "N9①/AD：no-op 双通路零 SWITCH_CAMERA")
	# A2 目标≠当前 → 恰一发
	br.set("_camera_enum", {"cameras": cams, "current_camera": 1})
	r1 = bool(br.call("ensure_camera_open"))
	check_eq(r1, true, "A2 前置：ensure 返回 true")
	check_eq(snif.count_prefix("START_CAMERA_BY_NAME"), 1,
		"N9①/AD 等价改写：目标≠当前 → 启动指令恰一发（实际 %s）" % [snif.cmds])
	check_eq(int(br.get("last_switch_camera_id")), 0, "A2：last_switch_camera_id 记账（N5 回落判定消费）")
	# A3 探测互斥：在飞丢弃 → 回包恢复
	snif.cmds.clear()
	br.call("send_probe_matrix", 1)
	check_eq(snif.count_prefix("PROBE_MATRIX"), 1, "N9②：首个探测发出")
	br.call("send_probe_matrix", 1)
	check_eq(snif.count_prefix("PROBE_MATRIX"), 1, "N9②：探测在飞期间新探测被丢弃（互斥）")
	br.call("simulate_packet", "{\"type\":\"probe_result\",\"id\":1,\"ok\":true,\"resolutions\":[\"1280x720\"],\"fps_options\":[30]}")
	snif.cmds.clear()
	br.call("send_probe_matrix", 1)
	check_eq(snif.count_prefix("PROBE_MATRIX"), 1, "N9②：回包到达后恢复（可再探测）")
	# A4 SWITCH 主流命令抢占探测
	br.call("send_probe_matrix", 0)   # 在飞
	snif.cmds.clear()
	br.call("send_control", "SWITCH_CAMERA:0")
	br.call("send_probe_matrix", 1)
	check_eq(snif.count_prefix("PROBE_MATRIX"), 1, "N9②：SWITCH 主流命令抢占探测（后续探测恢复可达）")
	br = null   # RefCounted 置空释放（free 对 RefCounted 报错中止 _initialize——w_gesture_state 先例）
	snif.close()
	snif = null

	# ---- 段 B（N5）：按钮真实状态机（真实 autoload 信号驱动）----
	var gb: Node = get_root().get_node("GestureBridge")
	var panel: Control = (load(PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await process_frame
	var cam_t: Button = panel.get_node("Panel/VBox/OptionsBox/CameraRow/CameraToggle")
	var ges_t: Button = panel.get_node("Panel/VBox/OptionsBox/GestureToggle")
	check(cam_t != null and ges_t != null, "B 前置：摄像头/手势钮在位")
	# B1 亮=READY 且摄像头开（手势开分支）——批次 Y（Y-A17）：亮/收口以流开启真值为准，
	# 经 camera_opened 事件注入（真实路径）
	gb.set("_intentional_stop", false)
	gb._set_state(1)
	gb.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "HD Camera"}))
	await process_frame
	check(bool(cam_t.button_pressed) and not bool(cam_t.disabled) and String(cam_t.text) == "摄像头",
		"N5①：READY+摄像头开 → 钮亮（pressed+enabled+文案=摄像头）")
	# B2 手势开+未开（UNAVAILABLE+released）→ 点击=OPENING（禁用+打开中）
	gb._set_state(2)
	gb.set("_intentional_stop", true)
	gb.set("camera_stream_open", false)   # 批次 Y：复位 B1 开流真值（本步=未开语义）
	await process_frame
	cam_t.set_pressed_no_signal(false)
	cam_t.emit_signal("toggled", false)
	await process_frame
	check(bool(panel.get("_cam_opening")), "N5②：点击未开摄像头 → 进入 OPENING 态")
	check(bool(cam_t.disabled) and String(cam_t.text).begins_with(String(panel.CAM_OPENING_TEXT)),
		"N5②：OPENING 态=禁用+「%s」文案（点阵动画起点；Z5-7 单点常量引用，字面量断言退役）" % String(panel.CAM_OPENING_TEXT))
	# B3 流开启收口转亮（批次 Y Y-A17：READY 边沿不再收口，camera_opened 事件才收口）
	gb.set("_intentional_stop", false)
	gb._set_state(1)
	gb.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "HD Camera"}))
	await process_frame
	check(not bool(cam_t.disabled) and String(cam_t.text) == "摄像头" and bool(cam_t.button_pressed),
		"N5③：OPENING → camera_opened 收口转亮（打开成功才亮；Y-A17 真值收口）")
	# B4（批次 Z Z4-④ 等价改写）：OPENING 中 camera_error 命中目标 → 回落抢句柄退役——
	# 不再迁移 attempt 切其他设备（旧设备/首可用设备零 SWITCH），直接失败收口退出 OPENING。
	# （经 _handle_meta 真实路径：错误 id 入 _camera_errors 置灰集 + 发 camera_error_received）
	gb._set_state(2)
	gb.set("_intentional_stop", true)
	gb.set("camera_stream_open", false)   # 批次 Y：复位 B1 开流真值（本步=未开语义）
	await process_frame
	cam_t.set_pressed_no_signal(false)
	cam_t.emit_signal("toggled", false)
	await process_frame
	check(bool(panel.get("_cam_opening")), "B4 前置：重入 OPENING")
	gb.set("_camera_enum", {"cameras": [{"id": 0, "name": "HD Camera"}, {"id": 1, "name": "Virtual Cam"}],
		"current_camera": 0})
	var attempt_b4: int = int(panel.get("_cam_open_attempt_id"))
	gb.call("_handle_meta", {"type": "camera_error", "id": 0, "reason": "open-fail"}, "camera_error")   # 目标 0 失败
	await process_frame
	check(int(panel.get("_cam_open_attempt_id")) != 1,
		"Z4-④：camera_error 命中目标 → attempt 不迁移到首可用设备（回落切设备退役；现值 %d）" % int(panel.get("_cam_open_attempt_id")))
	check(bool(panel.get("_cam_opening")) == false, "Z4-④：camera_error 命中目标 → 失败收口退出 OPENING")
	check(not bool(cam_t.disabled) and String(cam_t.text) == "摄像头", "Z4-④：失败收口后钮复位可点")
	check(attempt_b4 == int(panel.get("_cam_open_attempt_id")), "Z4-④：attempt 记账零迁移（零回落 SWITCH 语义）")
	# B5 再收尾错误（面板已不在打开中期）→ 状态不再漂移、钮态保持复位
	gb.call("_handle_meta", {"type": "camera_error", "id": 1, "reason": "open-fail"}, "camera_error")
	await process_frame
	check(bool(panel.get("_cam_opening")) == false, "N5⑤：非打开中期错误 → 不再进入/残留 OPENING")
	check(not bool(cam_t.disabled) and String(cam_t.text) == "摄像头", "N5⑤：钮态保持复位可点")
	# B5b（审查 P2-B①）：OPENING 中 UNAVAILABLE 边沿 → 解除 OPENING（spawn 失败/断流时
	# 按钮复位可再点，不再无限「打开中…」；READY 收口与 camera_error 回落链不受影响）
	cam_t.set_pressed_no_signal(false)
	cam_t.emit_signal("toggled", false)
	await process_frame
	check(bool(panel.get("_cam_opening")), "B5b 前置：重入 OPENING")
	gb._set_state(0)   # LOADING 边沿（OPENING 保持）
	gb._set_state(2)   # UNAVAILABLE 边沿（spawn 失败/断流）
	await process_frame
	check(bool(panel.get("_cam_opening")) == false,
		"P2-B①：OPENING 中 UNAVAILABLE 边沿 → 解除 OPENING（不再无限打开中）")
	check(not bool(cam_t.disabled) and String(cam_t.text) == "摄像头", "P2-B①：按钮复位可点")

	# B6 四象限路径：关手势→关摄像头→开手势→按钮能开摄像头
	# 批次 Y（Y-A19）：Q3 摄像头钮恒可点（旧态③置灰废止，Q3→Q2 解禁通路）
	cam_t.set_pressed_no_signal(false)   # 叙事前置：摄像头钮处于关位（用户已关摄像头）
	ges_t.set_pressed_no_signal(false)
	ges_t.emit_signal("toggled", false)
	await process_frame
	check(not bool(cam_t.disabled), "Y-A19：关手势+摄像头关 → 钮恒可点（旧「置灰点不开」废止；0 摄像头除外）")
	ges_t.set_pressed_no_signal(true)
	ges_t.emit_signal("toggled", true)
	await process_frame
	check(not bool(cam_t.disabled), "N5⑥-2：开手势 → 钮进入可点态（四象限修正）")
	check(not bool(panel.get("_cam_opening")), "N5⑥-2：Q1 ensure 幂等不误入 OPENING")
	cam_t.set_pressed_no_signal(false)
	cam_t.emit_signal("toggled", false)
	await process_frame
	check(bool(panel.get("_cam_opening")), "N5⑥-3：开手势后点击钮 → 能触发打开（OPENING）")
	gb.set("_intentional_stop", false)
	gb._set_state(1)
	gb.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "HD Camera"}))
	await process_frame
	check(not bool(cam_t.disabled) and bool(cam_t.button_pressed), "N5⑥-4：camera_opened → 亮（四步路径全链通；Y-A17 真值收口）")

	finish()
