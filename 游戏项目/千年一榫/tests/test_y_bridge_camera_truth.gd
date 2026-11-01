extends "res://tests/test_base.gd"
## 批次 Y Y2（2026-09-22 规格 §2 Y-A17/Y-A18/Y-A16/Y-A21/㉕ + §3.2/§3.3）——桥侧摄像头
## 开启真值重构 TDD 红测先行。段口径：
##   A（Y-A17）：camera_opened/camera_closed 带内事件消费——真值缓存+边沿信号（先写缓存后
##     emit）；不进状态机、不重置 _last_packet_time（probe_result 先例口径）；
##   B（Y-A17）：心跳 camera_open 电平字段周期校准兜底——丢事件时电平纠偏真值；
##     老包（无 camera_open 键）零回归不改真值；
##   C（Y-A18）：摄像头事件（开启/关闭）后刷新设备枚举缓存（GET_CAMERAS 重拉）；
##   D（Y-A18）：ensure_camera_open no-op 门以流真值判定——流开+目标==当前 → 零 SWITCH；
##     流关（假死 READY/RELEASE 后）→ 照发 SWITCH（陈旧 current_camera 不再卡死）；
##   E（㉕/Y-A25 → AC/AD）：LOADING+枚举空不再吞显式开启（重武装启动指令 + GET_CAMERAS）；
##   F（Y-A16 → AD §4.2.2-3）：START_CAMERA_BY_NAME 启动指令——spawn 后 tick 才首发、间隔重发、
##     init#1 到达即止；无记忆不下发；camera_opened 设备==记忆设备 → res/fps 记忆追发；
##   G（Y-A21）：打包 spawn 通路纯函数判定（外置运行时+嵌入式解释器三态）。
## 抓包：测试桥实例注入高位端口 override，控制端口=override+2 上绑监听套接字逐包核对。
## 无头纪律：不真拉起子进程；新 API 哨兵守卫（has_signal/has_method/str 比较——坑1 防御，
## test_x A4 红灯守卫先例：旧实现下发红检不崩不挂死）。
## user:// 备份还原（前缀 ybct，设备记忆三键写档兜底）。

const BR_SCRIPT := "res://autoload/gesture_bridge.gd"
const SAVE_PATH := "user://save.json"
const BK_PREFIX := "user://_ybct_backup_"
const WATCHED: Array = [SAVE_PATH, "user://save.json.tmp", "user://save.json.bak"]
var _pre_save_text := ""

func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _backup_user() -> void:
	# 自愈（规范第 5 条，test_w_camera_button 先例）：上次强杀残留的备份先还原到磁盘再重备份
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
		if FileAccess.file_exists(_abs(p)):
			var bk := BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_abs(p), _abs(bk))
	if FileAccess.file_exists(_abs(SAVE_PATH)):
		DirAccess.remove_absolute(_abs(SAVE_PATH))
	get_root().get_node("SaveManager").call("load_game")

func _restore_user() -> void:
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

## 控制端口抓包器（test_w_camera_button 同款内联类）
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

## 成员布尔读防御（坑1：bool(null) 中止 _initialize——str 比较红态不崩）
func _member_true(o: Object, member: String) -> bool:
	return str(o.get(member)) == "true"

func _make_bridge(port: int) -> Node:
	var b: Node = (load(BR_SCRIPT) as GDScript).new()
	b.set("_udp_port_override", port)
	add_child(b)
	await process_frame
	return b

func _initialize() -> void:
	print("== test_y_bridge_camera_truth ==")
	_backup_user()
	var save: Node = get_root().get_node("SaveManager")

	# ================= 段 A（Y-A17）：camera_opened/closed 事件消费 =================
	var br: Node = await _make_bridge(19780)
	var events: Array = []
	if br.has_signal("camera_stream_changed"):
		br.camera_stream_changed.connect(func(open: bool, device_id: int) -> void:
			events.append([open, device_id]))
	else:
		check(false, "Y-A17：camera_stream_changed 信号缺失（红）")
	var st0: int = int(br.get_load_state())
	var lpt0: float = float(br.get("_last_packet_time"))
	br.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 1, "name": "B", "width": 1280, "height": 720, "fps": 30.0}))
	check(_member_true(br, "camera_stream_open"), "Y-A17：camera_opened 事件 → 开启真值 true")
	check_eq(str(br.get("camera_stream_device_id")), "1", "Y-A17：事件设备 id 记账（camera_stream_device_id=1）")
	check_eq(events.size(), 1, "Y-A17：边沿信号恰 1 次")
	if events.size() >= 1:
		check_eq(str(events[0][0]), "true", "Y-A17：信号载荷 open=true")
		check_eq(str(events[0][1]), "1", "Y-A17：信号载荷 device_id=1")
	check_eq(int(br.get_load_state()), st0, "Y-A17：事件不进状态机（状态不变）")
	check_eq(float(br.get("_last_packet_time")), lpt0, "Y-A17：事件不重置 _last_packet_time（5s 断链判据不被污染）")
	# 公开只读态查询（设置面板/0 摄像头门消费入口）
	if br.has_method("is_camera_stream_open"):
		check_eq(str(br.call("is_camera_stream_open")), "true", "Y-A17：is_camera_stream_open() 公开真值查询=true")
	else:
		check(false, "Y-A17：is_camera_stream_open() 方法缺失（红）")
	br.simulate_packet(JSON.stringify({"type": "camera_closed", "id": 1, "reason": "switch"}))
	check_eq(str(br.get("camera_stream_open")), "false", "Y-A17：camera_closed 事件 → 真值 false")
	check_eq(events.size(), 2, "Y-A17：开→关 边沿信号 2 次")
	if events.size() >= 2:
		check_eq(str(events[1][0]), "false", "Y-A17：第二次信号 open=false")
	# 重复 closed（真值已 false）→ 边沿不再发（幂等）
	br.simulate_packet(JSON.stringify({"type": "camera_closed", "id": 1, "reason": "release"}))
	check_eq(events.size(), 2, "Y-A17：重复 closed 不再发边沿（真值未翻转）")
	br.free()

	# ================= 段 B（Y-A17）：心跳 camera_open 电平兜底 + 老包零回归 =================
	var br2: Node = await _make_bridge(19782)
	# B1 电平纠偏拉起（丢事件场景：事件未达，心跳 camera_open=true 先到）
	br2.simulate_packet(JSON.stringify({"left": null, "right": null, "timestamp": 1.0, "camera_open": true}))
	check(_member_true(br2, "camera_stream_open"), "Y-A17：心跳 camera_open=true → 真值拉起（防 UDP 丢事件真值卡死）")
	check_eq(int(br2.get_load_state()), 1, "Y-A17：电平包保留链路 READY 语义（心跳空包保活不废止——假真值废除仅指开启语义）")
	# B2 老包零回归：无 camera_open 键的帧包不改真值
	br2.simulate_packet(JSON.stringify({"left": {"gesture": "two", "confidence": 0.9}, "right": null, "timestamp": 2.0}))
	check(_member_true(br2, "camera_stream_open"), "Y-A17：老协议包（无 camera_open 键）零回归——真值不变")
	# B3 电平校准回收：camera_open=false → 真值翻回 false（边沿广播）
	var ev2: Array = []
	if br2.has_signal("camera_stream_changed"):
		br2.camera_stream_changed.connect(func(open: bool, _id: int) -> void: ev2.append(open))
	br2.simulate_packet(JSON.stringify({"left": null, "right": null, "timestamp": 3.0, "camera_open": false}))
	check_eq(str(br2.get("camera_stream_open")), "false", "Y-A17：心跳 camera_open=false → 真值校准回收")
	check_eq(ev2, [false], "Y-A17：电平纠偏同样广播边沿信号")
	br2.free()

	# ================= 段 C（Y-A18）：摄像头事件后刷新枚举缓存（GET_CAMERAS 重拉） =================
	var br3: Node = await _make_bridge(19784)
	var snif3 := CtrlSniffer.new()
	check_eq(int(snif3.bind(19784 + 2)), 0, "段C 前置：控制端口抓包器就位")
	br3.set("_last_enum_request_ms", -1000000)   # 复位节流（公开语义复位，test_u 段6 先例手法）
	br3.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "A"}))
	check(snif3.has_cmd("GET_CAMERAS"), "Y-A18：camera_opened（切换/重连成功）→ GET_CAMERAS 重拉枚举缓存")
	br3.set("_last_enum_request_ms", -1000000)
	snif3.cmds.clear()
	br3.simulate_packet(JSON.stringify({"type": "camera_closed", "id": 0, "reason": "release"}))
	check(snif3.has_cmd("GET_CAMERAS"), "Y-A18：camera_closed（RELEASE/设备丢失）→ GET_CAMERAS 重拉枚举缓存")
	snif3.close()
	br3.free()

	# ================= 段 D（Y-A18）：no-op 门以流真值判定 =================
	var br4: Node = await _make_bridge(19786)
	var snif4 := CtrlSniffer.new()
	check_eq(int(snif4.bind(19786 + 2)), 0, "段D 前置：控制端口抓包器就位")
	var cams: Array = [{"id": 0, "name": "A"}, {"id": 1, "name": "B"}]
	br4.set("_camera_enum", {"cameras": cams, "current_camera": 0})
	br4._set_state(1)   # READY
	br4.set("camera_stream_open", true)   # 流已开（事件直达形态；单元级注入）
	var rd: bool = bool(br4.call("ensure_camera_open"))
	check_eq(rd, true, "D1 前置：ensure 返回 true")
	check_eq(snif4.count_prefix("START_CAMERA_BY_NAME"), 0,
		"Y-A18：流已开+目标==当前 → no-op 零启动指令（真值判定）")
	check_eq(snif4.count_prefix("SWITCH_CAMERA"), 0,
		"Y-A18：no-op 双通路零 SWITCH_CAMERA（AD：抓包覆盖两条通路）")
	# D2 假死 READY：链路 READY 而流未开（camera_closed 已达）→ 照发启动指令（陈旧 current_camera 不卡死）
	br4.set("camera_stream_open", false)
	snif4.cmds.clear()
	rd = bool(br4.call("ensure_camera_open"))
	check_eq(rd, true, "D2 前置：ensure 返回 true")
	check_eq(snif4.count_prefix("START_CAMERA_BY_NAME"), 1,
		"Y-A18：假死 READY（流未开+目标==当前）→ 启动指令照发（no-op 门以流真值判定；实际 %s）" % [snif4.cmds])
	# D3 RELEASE 后重开：主动关标志在 ensure 入口被 start 清掉也不能破坏门——启动指令照发
	br4.set("_intentional_stop", true)
	snif4.cmds.clear()
	rd = bool(br4.call("ensure_camera_open"))
	check_eq(rd, true, "D3 前置：ensure 返回 true")
	check_eq(snif4.count_prefix("START_CAMERA_BY_NAME"), 1,
		"Y-A18：RELEASE 后（主动关标志入口快照）→ 启动指令照发（_intentional_stop 语义不被入口清标志破坏；实际 %s）" % [snif4.cmds])
	check_eq(str(br4.call("is_camera_intentionally_released")), "false", "D3：start 入口清标志语义保持（Q4 重启路径不变）")
	snif4.close()
	br4.free()

	# ================= 段 E（㉕/Y-A25 → 批次 AC 等价改写）：LOADING+枚举空不吞显式开启 =================
	# 批次 AC（2026-09-27，spec §4.2-3/D2）等价改写留痕：㉕ 的**核心不变量**=「显式开启不被
	# 静默吞掉」（ensure 返回 true 且确有出包动作），本批保持；但出包内容由「盲发
	# SWITCH_CAMERA:0」改为「握手重武装 + GET_CAMERAS 拉取」——枚举未达时盲发 0 在荣耀手机
	# 机器上=盲开手机摄像头（弹窗根因），批次 AC 拍板废止。断言数 1→3 只增不减。
	var br5: Node = await _make_bridge(19788)
	var snif5 := CtrlSniffer.new()
	check_eq(int(snif5.bind(19788 + 2)), 0, "段E 前置：控制端口抓包器就位")
	br5._set_state(0)   # LOADING
	br5.set("_camera_enum", {})
	br5.set("_last_enum_request_ms", -1000000)
	br5.set("_preferred_handshake_armed", false)
	br5.set("_preferred_next_at_ms", -1)
	var re: bool = bool(br5.call("ensure_camera_open"))
	check_eq(re, true, "E 前置：ensure 返回 true（显式开启未被吞——㉕ 核心不变量保持）")
	snif5.drain()
	check_eq(snif5.count_prefix("SWITCH_CAMERA"), 0,
		"AC 等价替换（旧 ㉕「照发 SWITCH_CAMERA:0」）：LOADING+枚举空 → 零盲发 SWITCH（实际 %s）" % [snif5.cmds])
	check(snif5.has_cmd("GET_CAMERAS"),
		"AC：LOADING+枚举空 → GET_CAMERAS 拉取（init#1 到达后按记忆名/非手机首项自动开；实际 %s）" % [snif5.cmds])
	check(str(br5.get("_preferred_handshake_armed")) == "true",
		"AC：LOADING+枚举空 → 握手重武装（显式开启意图经握手/枚举链继续兑现）")
	snif5.close()
	br5.free()

	# ================= 段 F（Y-A16；W4-1/AC/AD §4.2.2-3 等价改写）：START_CAMERA_BY_NAME 启动指令 =================
	# W4-1 语义变更（有意，spec §7.3）：①下发统一收口 _tick + 「探到 9878 已 bind 才发」门
	#（spawn 只武装不发）；②重试窗 4×0.25s → 30s 内 1s 间隔【暂定值·待用户复验】；
	#③止发判据「init#1 到达即止」→「camera_opened 且 id 匹配记忆设备 / 窗过期」。
	#旧断言（spawn 即发、余量 3、init#1 止发）随语义退役，等价改写留痕、断言数不减。
	var br6: Node = await _make_bridge(19790)
	var snif6 := CtrlSniffer.new()
	check_eq(int(snif6.bind(19790 + 2)), 0, "段F 前置：控制端口抓包器就位")
	save.update_settings({"gesture_camera_device": "Virtual Cam"})
	br6.set("preferred_handshake_interval_ms", 1)   # 无头缩短重发间隔（可注入）
	var spawn_calls: Array = []
	br6.set("_spawn_hook", func() -> bool:
		spawn_calls.append(true)
		return true)
	var ok6: bool = bool(br6.call("_spawn"))
	check_eq(ok6, true, "F1 前置：spawn hook 成功")
	check_eq(spawn_calls.size(), 1, "F1 前置：hook 被调用 1 次")
	check_eq(snif6.count_prefix("START_CAMERA_BY_NAME"), 0,
		"W4-1/F1：spawn 后未 tick 零下发（下发收口 _tick+bind 探测门；旧 spawn 即发留痕）")
	# F2：tick 且 probe 通过（sniffer 已绑 98790+2 → bind 探测=在）→ 首发 + armed
	br6.set("_preferred_next_at_ms", int(Time.get_ticks_msec()) - 1)
	br6.call("_process", 0.016)
	check(snif6.has_cmd("START_CAMERA_BY_NAME:Virtual Cam"),
		"W4-1/F2：探到 9878 已 bind → 首发 START_CAMERA_BY_NAME:<存档设备名>（9878 握手）")
	check(_member_true(br6, "_preferred_handshake_armed"),
		"W4-1/F2：重发期 armed=true（红态=成员缺失）")
	# F3：30s 窗内按 1s 间隔到点重发（原「4 次上限」口径随 W4-1 改写）
	snif6.cmds.clear()
	br6.set("_preferred_next_at_ms", int(Time.get_ticks_msec()) - 1)
	br6.call("_process", 0.016)
	check_eq(snif6.count_prefix("START_CAMERA_BY_NAME"), 1, "W4-1/F3：窗内到点重发第 2 次")
	br6.set("_preferred_next_at_ms", int(Time.get_ticks_msec()) - 1)
	br6.call("_process", 0.016)
	check_eq(snif6.count_prefix("START_CAMERA_BY_NAME"), 2, "W4-1/F3：持续按间隔重发（30s 窗内无次数硬上限）")
	# F4：30s 重发上限到 → 不再下发（上限口径，spec §7.7）
	br6.set("_preferred_handshake_deadline_ms", int(Time.get_ticks_msec()) - 1)
	br6.set("_preferred_next_at_ms", int(Time.get_ticks_msec()) - 1)
	snif6.cmds.clear()
	br6.call("_process", 0.016)
	check_eq(snif6.count_prefix("START_CAMERA_BY_NAME"), 0,
		"W4-1/F4：30s 重发上限到 → 零下发（armed 收束）")
	# F5：init#1 到达**不再**止发（旧「init#1 即止」口径退役——枚举到达≠首开完成）
	br6.set("_preferred_handshake_armed", true)
	br6.set("_preferred_handshake_deadline_ms", int(Time.get_ticks_msec()) + 20000)
	br6.set("_preferred_next_at_ms", int(Time.get_ticks_msec()) - 1)
	snif6.cmds.clear()
	br6.simulate_packet(JSON.stringify({"type": "init", "cameras": cams, "current_camera": 0}))
	br6.call("_process", 0.016)
	check_eq(snif6.count_prefix("START_CAMERA_BY_NAME"), 1,
		"W4-1/F5：init#1 到达后照常重发（枚举到达≠首开完成；旧 init 即止退役留痕）")
	# F6：camera_opened 且 id 匹配记忆设备 → 止发（新止发判据）
	br6.set("_camera_enum", {"cameras": [{"id": 0, "name": "A"}, {"id": 1, "name": "Virtual Cam"}], "current_camera": 0})
	br6.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 1, "name": "Virtual Cam"}))
	check(not _member_true(br6, "_preferred_handshake_armed"),
		"W4-1/F6：camera_opened 且 id 匹配记忆设备 → 握手止发")
	br6.set("_preferred_next_at_ms", int(Time.get_ticks_msec()) - 1)
	br6.call("_process", 0.016)
	check_eq(snif6.count_prefix("START_CAMERA_BY_NAME"), 1,
		"W4-1/F6：匹配后零新增下发（止发判据保持）")
	# F7 无记忆不下发
	var br7: Node = await _make_bridge(19796)
	var snif7 := CtrlSniffer.new()
	check_eq(int(snif7.bind(19796 + 2)), 0, "F7 前置：抓包器就位")
	save.update_settings({"gesture_camera_device": ""})
	br7.set("_spawn_hook", func() -> bool: return true)
	var ok7: bool = bool(br7.call("_spawn"))
	check_eq(ok7, true, "F7 前置：spawn hook 成功")
	br7.set("_preferred_next_at_ms", int(Time.get_ticks_msec()) - 1)
	br7.call("_process", 0.016)
	# 批次 AC（2026-09-27，spec §4.2-3 等价改写）：旧口径「无记忆设备名 → 不下发握手」使
	# Python 侧 5.0s 握手窗干等满窗（冷启动延迟）。新口径：无记忆亦发**空载荷**
	# START_CAMERA_BY_NAME:（逐字无尾随内容），Python 收到即按「未命中/空名 → 列表首项」
	# 降级启动——零额外等待。断言数 1→2 只增不减。
	check_eq(snif7.count_prefix("START_CAMERA_BY_NAME"), 1,
		"AD 等价替换（旧「无记忆不下发握手」）：无记忆设备名 → 照发空载荷启动指令恰一次（实际 %s）" % [snif7.cmds])
	check(snif7.has_cmd("START_CAMERA_BY_NAME:"),
		"AD：空载荷逐字 START_CAMERA_BY_NAME:（无尾随内容；Python 按降级首项启动；实际 %s）" % [snif7.cmds])
	# F8 camera_opened 设备==记忆设备 → res/fps 记忆追发（开机首开恢复链，零新协议）
	save.update_settings({"gesture_camera_device": "Virtual Cam", "gesture_camera_res": "640x480", "gesture_camera_fps": 30})
	br7.set("_camera_enum", {"cameras": [{"id": 0, "name": "A"}, {"id": 1, "name": "Virtual Cam"}], "current_camera": 0})
	snif7.cmds.clear()
	br7.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 1, "name": "Virtual Cam"}))
	check(snif7.has_cmd("SET_RESOLUTION:1:640x480"), "Y-A16：camera_opened 设备==记忆设备 → SET_RESOLUTION 记忆追发")
	check(snif7.has_cmd("SET_FPS:1:30"), "Y-A16：camera_opened 设备==记忆设备 → SET_FPS 记忆追发")
	# F9 设备不匹配 → 不追发（防跨设备串值，V17 语义等价）
	snif7.cmds.clear()
	br7.simulate_packet(JSON.stringify({"type": "camera_closed", "id": 1, "reason": "release"}))
	br7.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "A"}))
	var f6_bad: bool = snif7.count_prefix("SET_RESOLUTION") > 0 or snif7.count_prefix("SET_FPS") > 0
	check(not f6_bad, "Y-A16：开启设备≠记忆设备 → 不追发 res/fps（防跨设备串值）")
	snif6.close()
	snif7.close()
	br6.free()
	br7.free()

	# ================= 段 G（Y-A21）：打包 spawn 通路纯函数判定 =================
	var brg: Node = await _make_bridge(19794)
	if brg.has_method("_packaged_spawn_plan"):
		var plan_missing: Dictionary = brg.call("_packaged_spawn_plan", "C:/game", false, false)
		check_eq(bool(plan_missing.get("spawnable", true)), false, "Y-A21：运行时缺失 → 不可 spawn（明确不可用，不假死 READY）")
		check_eq(String(plan_missing.get("reason", "")), "runtime_missing", "Y-A21：缺失原因=runtime_missing")
		var plan_no_py: Dictionary = brg.call("_packaged_spawn_plan", "C:/game", true, false)
		check_eq(bool(plan_no_py.get("spawnable", true)), false, "Y-A21：嵌入式解释器缺失 → 不可 spawn")
		check_eq(String(plan_no_py.get("reason", "")), "interpreter_missing", "Y-A21：缺失原因=interpreter_missing")
		var plan_ok: Dictionary = brg.call("_packaged_spawn_plan", "C:/game", true, true)
		check_eq(bool(plan_ok.get("spawnable", false)), true, "Y-A21：外置运行时+解释器在位 → 可 spawn（打包 respawn 通路注册）")
		check_eq(String(plan_ok.get("script", "")), "C:/game/gesture_runtime/main.py", "Y-A21：脚本路径=exe 同级 gesture_runtime/main.py（外置布局实证 export_presets.cfg exclude）")
		check_eq(String(plan_ok.get("interpreter", "")), "C:/game/gesture_runtime/python/python.exe", "Y-A21：解释器=嵌入式 python/python.exe（打包布局实证）")
	else:
		check(false, "Y-A21：_packaged_spawn_plan 纯函数缺失（红）")
	brg.free()

	# ================= 段 H（审查② P1-1）：打包 spawn 在场门（probe ready 不 spawn） =================
	# 行为级子类测（GDScript.new()+reload）：覆写 _probe_python_ready（mock）与
	# _packaged_spawn_plan（static 覆写恒可 spawn，消除无头 exe 目录无运行时的环境噪声）与
	# _packaged_spawn_exec（create_process 拦截替身）——旧实现无在场门 → probe 零调用红。
	var sub := GDScript.new()
	sub.source_code = """
extends "res://autoload/gesture_bridge.gd"
var probe_calls: int = 0
var probe_ret: bool = false
var exec_calls: Array = []
func _probe_python_ready() -> bool:
	probe_calls += 1
	return probe_ret
static func _packaged_spawn_plan(_exe_dir: String, _runtime_main_exists: bool, _interpreter_exists: bool) -> Dictionary:
	return {"spawnable": true, "script": "S", "interpreter": "I", "reason": ""}
func _packaged_spawn_exec(plan: Dictionary) -> bool:
	exec_calls.append(plan)
	return true
"""
	var reload_err: int = int(sub.reload())
	check_eq(reload_err, 0, "段H 前置：测试子类脚本编译成功")
	if reload_err == int(OK):
		var sb: Node = sub.new()
		sb.set("_udp_port_override", 19798)
		add_child(sb)
		await process_frame
		# H1 probe ready（python 在场）→ 在场门前置：仅探测不 spawn（probe 恰一次、exec 零调用）
		sb.set("probe_ret", true)
		var h1: bool = bool(sb.call("_spawn_packaged"))
		check_eq(h1, false, "审查②P1-1：probe ready（在场）→ 仅探测不 spawn（返回 false）")
		check_eq(int(sb.get("probe_calls")), 1, "审查②P1-1：在场门先于文件存在性判定（probe 恰一次调用；旧实现零调用红）")
		check_eq((sb.get("exec_calls") as Array).size(), 0, "审查②P1-1：probe ready → create_process 零调用（launcher 健康实例不被接管重启/摄像头闪断根除）")
		# H2 probe false（python 真死）→ 照常 spawn（exec 恰一次，respawn 通路不回退）
		sb.set("probe_ret", false)
		var h2: bool = bool(sb.call("_spawn_packaged"))
		check_eq(h2, true, "审查②P1-1：probe false（真死）→ 照常 spawn（exec 替身返回 true 透传）")
		check_eq(int(sb.get("probe_calls")), 2, "审查②P1-1：真死路径 probe 复验恰一次（累计 2）")
		check_eq((sb.get("exec_calls") as Array).size(), 1, "审查②P1-1：真死 → create_process 恰一次（打包 respawn 通路不回退）")
		sb.free()
	else:
		check(false, "审查②P1-1：_spawn_packaged 在场门缺失（probe 零调用，红）")
		check(false, "审查②P1-1：真死 spawn exec 缝缺失（红）")
	sub = null   # GDScript 系 RefCounted 资源——禁止 .free()（崩溃实证），引用置空交由 GC

	save.update_settings({"gesture_camera_device": "", "gesture_camera_res": "", "gesture_camera_fps": 0})
	finish()
