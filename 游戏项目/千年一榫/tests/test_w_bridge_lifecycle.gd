extends "res://tests/test_base.gd"
## 批次 W W4（2026-09-20 规格 §5）——桥子进程生命周期 TDD 红测先行。
## 段口径：
##   A（P1-2）：子进程存活检测——注入死 pid → 判死 → pid 清 -1 + UNAVAILABLE + 退避调度置位；
##     自身 pid 判活不变；stop 对已死 pid 只清不 kill（Windows PID 复用防误杀）；spawn 退避门。
##   B（P1-3）：9876/9877 绑定失败重试——占用期 bind 失败不置 _udp_initialized（允许重入）、
##     失败计数+指数退避调度；释放端口后经 _retry_binds 自动恢复绑定（回 LOADING）；
##     超过最大重试次数停止调度；get_udp_port() 在无 override 时恒 9876（P2-3a 回归锁）。
## 无头纪律：全程不真拉起子进程（headless 判据）；测试端口用 197xx 高位避免与 9876 竞争
## （bridge_ports 环境性失败甄别先例）；override 在 add_child 前注入（_ready 即按测试端口绑）；
## user:// 零触碰。

const BR_SCRIPT := "res://autoload/gesture_bridge.gd"
const PORT_A := 19760   # 段 A 实例端口（无占用，正常绑定）
const PORT_B := 19762   # 段 B/D 9876 域
const PORT_B_JPEG := 19763
const PORT_C := 19770   # 段 C 自动重拉实例端口（control=19772 须空闲供 probe 判 false）

## 控制端口抓包器（绑 override+2，drain 收集命令行；test_w_camera_button 同款内联类）
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
	## 批次 AC 补：命令存在性查询（本文件旧夹具只有 count_prefix；与其他测试 CtrlSniffer 同族）
	func has_cmd(c: String) -> bool:
		drain()
		return cmds.has(c)

func _make_bridge(port: int) -> Node:
	var b: Node = (load(BR_SCRIPT) as GDScript).new()
	b.set("_udp_port_override", port)
	b.set("udp_bind_retry_base", 0.05)   # 无头缩短退避等待
	add_child(b)
	return b

func _initialize() -> void:
	print("== test_w_bridge_lifecycle ==")
	# ---- 段 A（P1-2）：存活检测 ----
	var br: Node = _make_bridge(PORT_A)
	await process_frame
	# 批次 AF 终审备案族（语言钉扎先例=6411fae o_catalog_shop）：autoload _ready 推迟至树激活，
	# 须等一帧后钉 zh——用户真实存档现 language=en，不钉则文案断言呈 en 态假红。
	# 编译窗安全：经节点查找而非全局名（--script 模式 autoload 全局名编译期未注册）。
	var i18n_node: Variant = get_root().get_node_or_null("I18n")
	if i18n_node != null:
		i18n_node.call("set_language", "zh")
	# A1 活 pid（自身进程）→ 不判死
	br.set("_process_pid", OS.get_process_id())
	br._set_state(1)   # READY
	br.call("_check_process_alive")
	check_eq(int(br.get("_process_pid")), OS.get_process_id(), "A1：活 pid（自身）不判死不清")
	check_eq(int(br.get_load_state()), 1, "A1：READY 态保持")
	# A2 死 pid → 判死 → pid 清 -1 + UNAVAILABLE + 退避置位
	br._set_state(1)
	br.set("_process_pid", 999999999)
	var now0: float = float(br.call("_now"))
	br.call("_check_process_alive")
	check_eq(int(br.get("_process_pid")), -1, "A2：死 pid 判死后清 -1")
	check_eq(int(br.get_load_state()), 2, "A2：判死后转 UNAVAILABLE")
	check(float(br.get("_respawn_block_until")) > now0, "A2：退避调度置位（_respawn_block_until > now）")
	# A3 死 pid stop：只清 pid 不 kill（防 PID 复用误杀）——零崩溃且 pid 清零
	br.set("_process_pid", 999999999)
	br.call("stop_gesture_process")
	check_eq(int(br.get("_process_pid")), -1, "A3：stop 对已死 pid 只清不 kill（pid 清 -1）")
	check(bool(br.call("is_camera_intentionally_released")), "A3：stop 主动关标志语义保持")
	# A4 spawn 退避门：退避窗内 start_gesture_process 拒拉
	br.set("_respawn_block_until", float(br.call("_now")) + 5.0)
	check_eq(bool(br.call("start_gesture_process")), false, "A4：退避窗内 spawn 被拒（防风暴）")
	# A5 退避门外（无头环境 start 仍因 headless 判据返回 false，但门已放行）
	br.set("_respawn_block_until", -1.0)
	check_eq(bool(br.call("start_gesture_process")), false, "A5：无头环境 start 不真拉起（既有判据保持）")

	# ---- 段 B（P1-3）：9876 域绑定失败重试 ----
	# B1 端口被占 → _ready 即 bind 失败：不置 _udp_initialized、失败计数+退避调度
	var helper := PacketPeerUDP.new()
	check_eq(int(helper.bind(PORT_B)), 0, "B 前置：helper 占用测试端口")
	var br2: Node = _make_bridge(PORT_B)
	await process_frame
	check(bool(br2.get("_udp_initialized")) == false, "B1：bind 失败不置 _udp_initialized（允许重入）")
	check_eq(int(br2.get("_udp_bind_fail_count")), 1, "B1：失败计数置位（_ready 初绑即失败）")
	check(float(br2.get("_udp_bind_next_at")) > 0.0, "B1：指数退避调度置位")
	check(br2.get("_udp") == null, "B1：_udp 置空")
	# B2 释放端口 → 退避到点 → _retry_binds 重绑成功回 LOADING
	helper.close()
	br2.set("_udp_bind_next_at", float(br2.call("_now")) - 0.001)   # 退避到点（测试缩短等待）
	br2.call("_retry_binds", float(br2.call("_now")))
	check(bool(br2.get("_udp_initialized")), "B2：端口释放后重绑成功（_udp_initialized 置位）")
	# 审查 P1-A①：强化断言——验真 bind 成功路径（套接字真实在位且绑定测试端口，防 initialized 弱断言）
	check(br2.get("_udp") != null and int((br2.get("_udp") as PacketPeerUDP).get_local_port()) == PORT_B,
		"B2：重绑成功验真（_udp 在位且 local_port==测试端口）")
	check_eq(int(br2.get("_udp_bind_fail_count")), 0, "B2：成功后失败计数清零")
	check_eq(int(br2.get_load_state()), 0, "B2：重绑成功回 LOADING（探测周期重启）")
	# B3 JPEG 域同款：占用失败 → 释放恢复（先卸 br2._ready 已成功绑定的 JPEG 套接字；
	# 审查 P1-A①：置 null 前显式 close() 旧套接字——防句柄滞留占端口致占位断言链错位）
	var old_jpeg: Variant = br2.get("_jpeg_udp")
	if old_jpeg is PacketPeerUDP:
		(old_jpeg as PacketPeerUDP).close()
	br2.set("_jpeg_initialized", false)
	br2.set("_jpeg_udp", null)
	var helper2 := PacketPeerUDP.new()
	check_eq(int(helper2.bind(PORT_B_JPEG)), 0, "B3 前置：helper 占用 JPEG 测试端口")
	br2.call("_init_jpeg_udp")   # frame 端口=override+1=19763 被占 → 失败
	check(bool(br2.get("_jpeg_initialized")) == false, "B3：JPEG bind 失败不置 _jpeg_initialized")
	check(br2.get("_jpeg_udp") == null, "B3：失败后 _jpeg_udp 置空（重入干净）")
	helper2.close()
	br2.set("_jpeg_bind_next_at", float(br2.call("_now")) - 0.001)
	br2.call("_retry_binds", float(br2.call("_now")))
	check(bool(br2.get("_jpeg_initialized")) and br2.get("_jpeg_udp") != null
		and int((br2.get("_jpeg_udp") as PacketPeerUDP).get_local_port()) == PORT_B_JPEG,
		"B3：JPEG 端口释放后重绑成功（验真 local_port==测试端口）")
	# B4 超过最大重试次数停止调度
	var old_udp: Variant = br2.get("_udp")
	if old_udp is PacketPeerUDP:
		(old_udp as PacketPeerUDP).close()   # 审查 P1-A①：置 null 前显式 close（句柄卫生）
	br2.set("_udp_initialized", false)
	br2.set("_udp", null)
	br2.set("_udp_bind_fail_count", 6)   # 已超上限
	br2.set("_udp_bind_next_at", float(br2.call("_now")) - 0.001)
	br2.call("_retry_binds", float(br2.call("_now")))
	check(bool(br2.get("_udp_initialized")) == false, "B4：超过最大重试次数不再调度重绑")
	# B5 回归锁：无 override 时 get_udp_port 恒 9876（P2-3a 单一真源）
	var br3: Node = (load(BR_SCRIPT) as GDScript).new()
	add_child(br3)
	await process_frame
	check_eq(int(br3.call("get_udp_port")), 9876, "B5：无 override get_udp_port 恒 9876（P2-3a 不回归）")
	check_eq(int(br3.call("get_frame_port")), 9877, "B5：9877 派生不变")
	check_eq(int(br3.call("get_control_port")), 9878, "B5：9878 派生不变")

	# ---- 段 C（审查 P1-B）：子进程真死自动重拉闭环（UNAVAILABLE + probe false 互补分支）----
	# AF 同步批（2026-11-01）「设置门放行」前置钉住（内存级，零落盘——本文件纪律「user://
	# 零触碰」）：批次 AA（aarev P1-1）在 _spawn（含 hook 计数替身路径）/ensure_camera_open/
	# start_gesture_process 三入口统一加 `_settings_allow_camera()` 单一漏斗门（gesture_input ∨
	# gesture_camera_enabled；Q3 双关=自愈重拉/显式开启零副作用早退）。用户存档 Q3 双关时本测
	# 段 C spawn 闭环/段 D ensure 链全部分支在门处 return false 不可达（非代码回归；「主动关
	# 不得复活/自愈不开镜」生产语义正确）。钉位实证：--script 模式 SaveManager._ready（load_game
	# 整体替换 _data 引用）推迟至本文件首个 await process_frame（段 A）触发的树激活——钉必须在
	# 该 await **之后**（否则被冲，C2 透视打印实证）；_ready 只跑一次，此后 _data 稳定。改
	# SaveManager._data.settings.gesture_input=true，进程退出即弃（不写盘）。
	var sm_lifecycle: Node = get_root().get_node("SaveManager")
	if sm_lifecycle != null:
		var sm_data: Dictionary = sm_lifecycle.get("_data")
		if typeof(sm_data.get("settings")) != TYPE_DICTIONARY:
			sm_data["settings"] = {}
		(sm_data["settings"] as Dictionary)["gesture_input"] = true
	# probe bind 成功=9878 已释放=python 不在（旧口径零动作→UNAVAILABLE 永久滞留）；
	# 修复后：编辑器形态 ∧ 退避窗外 → _spawn()（无头经 _spawn_hook 探缝断言被调用）。
	var br_c: Node = _make_bridge(PORT_C)
	await process_frame
	var spawn_calls: Array = []
	br_c.set("_spawn_hook", func() -> bool:
		spawn_calls.append(true)
		return true)
	br_c.set("_process_pid", 999999999)
	br_c.call("_check_process_alive")   # 死 pid 判死 → UNAVAILABLE + 退避置位
	check_eq(int(br_c.get_load_state()), 2, "C 前置：死 pid 判死转 UNAVAILABLE")
	# C1 退避窗内：不 spawn
	br_c.set("_respawn_block_until", float(br_c.call("_now")) + 5.0)
	br_c.call("_process", 0.016)
	check_eq((spawn_calls as Array).size(), 0, "C1：退避窗内自动重拉被拒（防风暴门）")
	# C2 退避窗外：_spawn 被调用恰一次 → 重拉成功回 LOADING
	br_c.set("_respawn_block_until", -1.0)
	br_c.set("_last_retry_at", -1000.0)   # 重试周期到点（5s 门直通）
	br_c.call("_process", 0.016)
	check_eq((spawn_calls as Array).size(), 1, "C2：probe false + 退避窗外 → spawn 被调用（真死自动重拉闭环，W7 清单⑧开发态落点）")
	check_eq(int(br_c.get_load_state()), 0, "C2：重拉成功回 LOADING")
	# C3 重拉失败（hook 返回 false）→ 保持 UNAVAILABLE 等下轮（重拉后又死：确定性置回 UNAVAILABLE）
	br_c.set("_process_pid", 999999999)
	br_c.call("_check_process_alive")   # 重拉实例再死 → UNAVAILABLE（真实序列：spawn→死→重拉）
	br_c.set("_respawn_block_until", -1.0)   # 判死重新置位的 2s 防风暴退避（生产行为正确）跨过
	br_c.set("_last_retry_at", -1000.0)
	br_c.set("_spawn_hook", func() -> bool:
		spawn_calls.append(true)
		return false)
	br_c.call("_process", 0.016)
	check_eq((spawn_calls as Array).size(), 2, "C3：失败重试轮 _spawn 再次被调用")
	check_eq(int(br_c.get_load_state()), 2, "C3：spawn 失败保持 UNAVAILABLE（不假 LOADING）")
	br_c.set("_spawn_hook", Callable())
	br_c = null

	# ---- 段 D（审查 P2-A）：探测在飞超时回收 + P2-B② LOADING 幂等（B 桥续用）----
	var snif2 := CtrlSniffer.new()
	check_eq(int(snif2.bind(PORT_B + 2)), 0, "D 前置：B 桥控制端口抓包器就位（兼 probe 占位使 ensure 过早退门）")
	# D1（P2-B②→批次 Y ㉕ → 批次 AC 等价改写）：LOADING + 枚举未知（init#1 未达）→
	# ensure 显式开启**不吞**（返回 true 且确有出包动作）——㉕ 核心不变量保持；
	# 批次 AC（2026-09-27，spec §4.2-3/D2）把出包内容由「盲发 SWITCH_CAMERA:0」改为
	# 「GET_CAMERAS 拉取 + 握手重武装」：枚举未达时盲发 0 在荣耀手机机器上=盲开手机
	# 摄像头（弹窗根因），批次 AC 拍板废止。断言数 1→3 只增不减。
	br2._set_state(0)   # LOADING
	br2.set("_camera_enum", {})
	br2.set("_last_enum_request_ms", -1000000)
	br2.set("_preferred_handshake_armed", false)
	br2.set("_preferred_next_at_ms", -1)
	var rd1: bool = bool(br2.call("ensure_camera_open"))
	check_eq(rd1, true, "D1 前置：ensure 返回 true（显式开启未被吞——㉕ 核心不变量保持）")
	check_eq(snif2.count_prefix("SWITCH_CAMERA"), 0,
		"AC/AD 等价替换（旧 ㉕「照发 SWITCH_CAMERA:0」）：LOADING+枚举空 → 零盲发 SWITCH（实际 %s）" % [snif2.cmds])
	check_eq(snif2.count_prefix("START_CAMERA_BY_NAME"), 0,
		"AD：LOADING+枚举空 → 零启动指令盲发（待 init#1 才下发；实际 %s）" % [snif2.cmds])
	check(snif2.has_cmd("GET_CAMERAS"),
		"AC：LOADING+枚举空 → GET_CAMERAS 拉取（init#1 到达后按记忆名/非手机首项自动开；实际 %s）" % [snif2.cmds])
	check(str(br2.get("_preferred_handshake_armed")) == "true",
		"AC：LOADING+枚举空 → 握手重武装（显式开启意图经握手/枚举链继续兑现）")
	snif2.cmds.clear()   # 段间隔离（抓包为累计数组）
	# D2（P2-B②→批次 Y Y-A18 等价改写）：LOADING + 枚举已知 + 目标==当前 + 流已开 → no-op
	#（no-op 门以「摄像头流开启真值」判定——注入流已开；流未开时照发，见 test_y_bridge_camera_truth 段D）
	br2.set("camera_stream_open", true)
	br2.set("_camera_enum", {"cameras": [{"id": 0, "name": "HD Camera"}, {"id": 1, "name": "Virtual Cam"}],
		"current_camera": 0})
	rd1 = bool(br2.call("ensure_camera_open"))
	check_eq(snif2.count_prefix("START_CAMERA_BY_NAME"), 0,
		"Y-A18/AD：LOADING+流开+目标==当前 → no-op 零启动指令（实际 %s）" % [snif2.cmds])
	# D3（P2-B②）：LOADING + 目标≠当前（用户显式切设备）→ 照发
	br2.set("_camera_enum", {"cameras": [{"id": 0, "name": "HD Camera"}, {"id": 1, "name": "Virtual Cam"}],
		"current_camera": 1})
	rd1 = bool(br2.call("ensure_camera_open"))
	check_eq(snif2.count_prefix("START_CAMERA_BY_NAME"), 1,
		"P2-B②/AD 等价改写：LOADING+目标≠当前 → 启动指令照发（切设备语义保持；实际 %s）" % [snif2.cmds])
	# D4（P2-A）：探测在飞丢弃 → 超时回收放行
	snif2.cmds.clear()
	br2.set("probe_timeout_ms", 6000)
	br2.call("send_probe_matrix", 1)
	check_eq(snif2.count_prefix("PROBE_MATRIX"), 1, "P2-A：首个探测发出（在飞）")
	br2.call("send_probe_matrix", 1)
	check_eq(snif2.count_prefix("PROBE_MATRIX"), 1, "P2-A：超时窗内新探测被丢弃（互斥保持）")
	br2.set("_probe_sent_at_ms", int(Time.get_ticks_msec()) - 7000)   # 注入超时（>默认 6s 档）
	br2.call("send_probe_matrix", 1)
	check_eq(snif2.count_prefix("PROBE_MATRIX"), 1 + 1, "P2-A：超时回收 → 新探测放行（UDP 丢包自愈）")
	check_eq(bool(br2.get("_probe_in_flight")), true, "P2-A：回收后新探测重新置位在飞标志")
	snif2.close()
	snif2 = null

	finish()
