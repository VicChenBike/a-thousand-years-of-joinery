extends "res://tests/test_base.gd"
## 批次 U 判定用例（U-A 域）：probe_result 缓存/超时语义、RELEASE_CAMERA、ensure_camera_open
## （短路判据复核终版，修双审 P2-15）、GET_CAMERAS 增强、混流负例。spec §4-U2/U4/§6。
## 夹具：test_gesture_bridge_ports.gd 同款——load().new()＋get_root().add_child()＋显式 _init_udp()；
## 9878 常驻服务模拟=测试内 PacketPeerUDP bind（占端口即 _probe_python_ready()==true）；
## 控制命令捕获=同款 listener bind 9878 收回包。
## ⚠ 并行环境：9876 被占属环境性失败，单跑必绿（批次 M/N12c 先例）。

const Bridge := preload("res://autoload/gesture_bridge.gd")

var bridge: Node
var save: Node

func _ctrl_listener() -> PacketPeerUDP:
	var l := PacketPeerUDP.new()
	var err: Error = l.bind(int(bridge.get_control_port()))
	if err != OK:
		return null
	return l

func _wait_available(peer: PacketPeerUDP, frames: int) -> void:
	for i: int in frames:
		if peer != null and peer.get_available_packet_count() > 0:
			return
		await process_frame

func _recv_cmds(listener: PacketPeerUDP) -> Array:
	var out: Array = []
	while listener != null and listener.get_available_packet_count() > 0:
		out.append(listener.get_packet().get_string_from_utf8())
	return out

## AF 同步批（2026-11-01）环境噪音过滤版收包：本机若另驻游戏/编辑器实例（用户存档同为手势/
## 摄像头双关 Q3 态），其桥 _ready 的 _q3_release_camera_once 会向 127.0.0.1:9878 广播
## RELEASE_CAMERA（外来包时刻漂移实锤），与本测试「本实例 ensure/start 链路出包」断言正交。
## 本测试内 RELEASE_CAMERA 唯一期望包=段 4 request_camera_release 直发（l4 口径不滤）；
## 其余收包段统一按黑名单剔除并留痕（负例断言 SWITCH_CAMERA:0 的查证有效性保持——
## 外来 RELEASE 剔除后仍可检出假想盲发，无空转假绿）。
func _recv_cmds_noise_free(listener: PacketPeerUDP) -> Array:
	var out: Array = []
	while listener != null and listener.get_available_packet_count() > 0:
		var pkt: String = listener.get_packet().get_string_from_utf8()
		if pkt == "RELEASE_CAMERA":
			print("[env-noise] 收到外来 RELEASE_CAMERA（外部进程 Q3 兜底噪音，不计入本实例出包断言）")
			continue
		out.append(pkt)
	return out

func _initialize() -> void:
	print("== test_u_bridge_protocol ==")
	save = get_root().get_node("SaveManager")
	save.load_game()
	# AF 同步批（2026-11-01）「设置门放行」前置钉住（内存级，零落盘）：批次 AA（aarev P1-1）
	# 在 ensure_camera_open/start_gesture_process 入口加 `_settings_allow_camera()` 单一漏斗门
	#（gesture_input ∨ gesture_camera_enabled；Q3 双关=直调路径零副作用早退）。用户存档 Q3
	# 双关时本测试段 5 U4/AD 全部分支在门处 return false 不可达（非代码回归；「主动关不得
	# 复活」生产语义正确）。改 SaveManager._data.settings.gesture_input=true 钉住放行前提——
	# 不落盘（本测试无备份还原纪律，update_settings 会写用户真实 save.json），进程退出即弃；
	# 钉住须先于 Bridge.new()（新实例 _ready 的 Q3 兜底读同一名值，放行即跳过零发包）。
	var sm_data: Dictionary = save.get("_data")
	if typeof(sm_data.get("settings")) == TYPE_DICTIONARY:
		(sm_data["settings"] as Dictionary)["gesture_input"] = true
	bridge = Bridge.new()
	get_root().add_child(bridge)
	bridge.name = "GestureBridgeUProtocolTest"
	bridge._init_udp()
	bridge._init_jpeg_udp()

	# ---- 段 1. probe_result 分流＋缓存 getter（11 checks）----
	var probe_sigs: Array = []
	bridge.probe_result_received.connect(func(id: int, ok: bool, res: Array, fps: Array) -> void: probe_sigs.append([id, ok, res, fps]))
	bridge.simulate_packet(JSON.stringify({"type": "probe_result", "id": 1, "ok": true, "resolutions": [[1920, 1080], [1280, 720]], "fps_options": [30, 60]}))
	check_eq(int(probe_sigs[0][0]), 1, "U2：信号载荷 id==1")
	check_eq(bool(probe_sigs[0][1]), true, "U2：信号载荷 ok==true")
	check_eq(probe_sigs[0][2], [[1920.0, 1080.0], [1280.0, 720.0]], "U2：信号载荷 resolutions 大分辨率表保真")
	check_eq(probe_sigs[0][3], [30.0, 60.0], "U2：信号载荷 fps_options 保真")
	var m1: Dictionary = bridge.get_probe_matrix(1)
	check_eq(bool(m1.get("ok", false)), true, "U2：get_probe_matrix(1) 缓存同值 ok")
	check_eq(m1.get("resolutions", []), [[1920.0, 1080.0], [1280.0, 720.0]], "U2：get_probe_matrix(1) 缓存同值 resolutions")
	check_eq(bridge.get_probe_matrix(99), {}, "U2：未命中 id 返回空 Dictionary（P1-1 缓存模式）")
	bridge.simulate_packet(JSON.stringify({"type": "probe_result", "id": 2, "ok": false}))
	var m2: Dictionary = bridge.get_probe_matrix(2)
	check_eq(bool(m2.get("ok", true)), false, "U2：ok=false 缓存 ok==false")
	check_eq((m2.get("resolutions", [-1]) as Array).size(), 0, "U2：ok=false 缓存 resolutions 空")
	var st1: int = bridge.get_load_state()
	var lpt_before: float = float(bridge._last_packet_time)
	bridge.simulate_packet(JSON.stringify({"type": "probe_result", "id": 3, "ok": true, "resolutions": [[640, 480]], "fps_options": [30]}))
	check_eq(int(bridge.get_load_state()), st1, "U2：probe_result 不迁移状态机")
	check_eq(float(bridge._last_packet_time), lpt_before, "U2：probe_result 不重置 _last_packet_time（手势链路 5s 超时判据不被污染）")

	# ---- 段 2. 超时语义（2 checks；PROBE_TIMEOUT 常量本体锚在 test_t_camera_device 段 9——双审回修④删恒真式断言，桥侧以「未回包即无缓存」闭环）----
	var menu_scene: PackedScene = load("res://scenes/settings/settings_panel.tscn")
	check(menu_scene != null, "U2：settings_panel 场景可加载（下拉超时测试宿主就绪）")
	check_eq(bridge.get_probe_matrix(77), {}, "U2：请求后不回包 → 缓存恒空（超时态=缓存缺失，UI 层置「检测失败」）")

	# ---- 段 3. 混流负例（2 checks）----
	var got_state: Array = []
	bridge.gesture_state_received.connect(func(d: Dictionary) -> void: got_state.append(d))
	bridge._set_state(0)   # LOADING
	for i: int in 5:
		bridge.simulate_packet(JSON.stringify({"type": "probe_result", "id": 10 + i, "ok": true, "resolutions": [[640, 480]], "fps_options": [30]}))
		bridge.simulate_packet(JSON.stringify({"left": null, "right": null, "timestamp": float(i)}))
	check_eq(got_state.size(), 5, "U2：混流 10 包手势帧照常派发 5 次")
	check_eq(int(bridge.get_load_state()), 1, "U2：混流后状态机 LOADING→READY 正常")

	# ---- 段 4. RELEASE_CAMERA（4 checks）----
	var l4 := _ctrl_listener()
	bridge.request_camera_release()
	await _wait_available(l4, 4)
	# 批次 AF 终审备案族（语言钉扎先例=6411fae o_catalog_shop）：autoload _ready 推迟至树激活，
	# 须等一帧后钉 zh——用户真实存档现 language=en，不钉则文案断言呈 en 态假红。
	# 编译窗安全：经节点查找而非全局名（--script 模式 autoload 全局名编译期未注册）。
	var i18n_node: Variant = get_root().get_node_or_null("I18n")
	if i18n_node != null:
		i18n_node.call("set_language", "zh")
	var cmds4 := _recv_cmds(l4)
	check(cmds4.has("RELEASE_CAMERA"), "U4：request_camera_release → 控制通道逐字 RELEASE_CAMERA（实际 %s）" % [cmds4])
	check_eq(int(bridge.get_load_state()), 2, "U4：RELEASE 后状态=UNAVAILABLE（stop 即刻语义）")
	check_eq(bool(bridge.consume_intentional_stop()), true, "U4：_intentional_stop 置位可消费（S13 防 UNAVAILABLE 误报 toast 语义）")
	check(not cmds4.has("SHUTDOWN"), "U4：RELEASE 路径不发 SHUTDOWN（进程保留，不调 stop_gesture_process）")
	if l4 != null:
		l4.close()

	# ---- 段 5. ensure_camera_open（短路判据复核终版，9 checks）----
	# 5a. start false＋probe 不可用（9878 空闲）→ 短路 return false 不发 SWITCH
	var r5a: bool = bridge.ensure_camera_open()
	check_eq(bool(r5a), false, "U4：start false＋probe 不可用 → 短路 return false（9878 空闲=无常驻服务）")
	# 5b. start false＋probe ready（测试内 PacketPeerUDP bind 9878 模拟常驻服务；该套接字兼任命令捕获口）
	var resident := PacketPeerUDP.new()
	check_eq(int(resident.bind(int(bridge.get_control_port()))), int(OK), "U4：测试内 bind 9878 模拟常驻服务（probe ready 态；bind 失败=并行环境占用，单跑甄别）")
	bridge._simulate_start_ok = false
	# 批次 AC：枚举未达路径补发 GET_CAMERAS——先复位拉取节流哨兵（前段 init#1 派发/READY 边沿
	# 已自动发过拉取，1s 节流会吞本段出包；test_fixpack 段 6 同款复位手法）＋显式清枚举缓存
	# （前段注入过 init#1；本段口径=「枚举缓存缺失」形态请先自证前置）。
	bridge._last_enum_request_ms = -1000000
	bridge._camera_enum = {}
	bridge._preferred_handshake_armed = false
	bridge._preferred_next_at_ms = -1
	var r5b: bool = bridge.ensure_camera_open()
	await _wait_available(resident, 4)
	var cmds5b := _recv_cmds_noise_free(resident)
	check_eq(bool(r5b), true, "U4：start false＋probe ready（9878 被占=常驻服务）→ return true 照发（打包形态常态）")
	# 批次 AC（2026-09-27，spec §4.2-3/D2）等价改写留痕（断言数 1→3 只增不减）：
	# 旧口径「枚举缓存缺失 → 盲发 SWITCH_CAMERA:0」= 实机在荣耀手机于 CAP 0 的机器上盲开
	# 手机摄像头（弹窗+指示灯闪烁根因），批次 AC 拍板废止。新口径：枚举未达 → 零 SWITCH，
	# 改走「重新武装启动指令（无记忆名亦发空载荷 START_CAMERA_BY_NAME:）+ GET_CAMERAS 拉取」，
	# 待 init#1 到达由 _handle_meta 自动按记忆名/非手机首项开启。
	check_eq(cmds5b.count("SWITCH_CAMERA:0"), 0,
		"AC 等价替换（旧 U4「last_id 回落 0」）：枚举缓存缺失 → 零盲发 SWITCH_CAMERA:0（实际 %s）" % [cmds5b])
	check(cmds5b.has("GET_CAMERAS"),
		"AC：枚举未达 → 拉取枚举 GET_CAMERAS（init#1 到达后自动开；实际 %s）" % [cmds5b])
	check(str(bridge.get("_preferred_handshake_armed")) == "true",
		"AC：枚举未达 → 握手重新武装（武装=W4-1 既有下发收口 _tick 的前态；红态=未武装）")
	bridge._preferred_next_at_ms = -1
	bridge._process(0.016)
	await _wait_available(resident, 4)
	var cmds5b2 := _recv_cmds_noise_free(resident)
	var hs5b := 0
	for c: String in cmds5b2:
		if c.begins_with("START_CAMERA_BY_NAME:"):
			hs5b += 1
	check(hs5b >= 1,
		"AD 等价改写：武装后到点补发启动指令恰一次（唤起 Python 按存档名/降级首项启动；实际 %s）" % [cmds5b2])
	# 5c. 预注枚举缓存 → 按设备名下发启动指令（AD §4.2.2-3）
	# 批次 V-B2 等价替换留痕（V3，spec §6.2）：ensure_camera_open last_id 选择序重写——
	# ①记忆设备在枚举→用之；②否则枚举第一项；③空回落 0。旧口径「current_camera=2 保留」废止
	#（V3 拍板「无记忆→首设备默认选中」）；本测试存档无 gesture_camera_device 键（V-D 落地前 .get
	# 缺省 -1=无记忆，落地后缺省亦 -1）→ 两态确定性同值。期望旧 SWITCH_CAMERA:2/0 → 空载荷启动指令
	#（枚举第一项 id=0），断言条数不变、行为口径等价迁移。
	bridge.simulate_packet(JSON.stringify({"type": "init", "cameras": [{"id": 0, "name": "A"}, {"id": 2, "name": "B"}], "current_camera": 2}))
	bridge.ensure_camera_open()
	await _wait_available(resident, 4)
	var cmds5c := _recv_cmds_noise_free(resident)
	check(cmds5c.has("START_CAMERA_BY_NAME:"), "AD 等价替换（旧 U4/V-B2「无记忆 → 枚举第一项 SWITCH_CAMERA:0」）：无记忆 → 空载荷启动指令（降级首项下沉 Python；实际 %s）" % [cmds5c])
	# 5d. start true（测试接缝）→ 照发
	bridge._simulate_start_ok = true
	var r5d: bool = bridge.ensure_camera_open()
	await _wait_available(resident, 4)
	var cmds5d := _recv_cmds_noise_free(resident)
	check_eq(bool(r5d), true, "U4：start true → return true 照发（表驱动第三态）")
	check(cmds5d.has("START_CAMERA_BY_NAME:"), "AD 等价替换（旧 U4：SWITCH_CAMERA:2）：start true 照发启动指令（逐字设备名/空载荷）")
	# 5e. 幂等与串格式
	bridge.ensure_camera_open()
	await _wait_available(resident, 4)
	var cmds5e := _recv_cmds_noise_free(resident)
	check(cmds5e.has("START_CAMERA_BY_NAME:"), "AD 等价替换（旧 U4：SWITCH_CAMERA:2）：幂等——再次调用每次一发（Python 同设备零 release/reopen 兜底，spec §4-U4-③）")
	var fmt_ok: bool = true
	var fmt_seen: int = 0
	for c: String in cmds5b + cmds5c + cmds5d + cmds5e:
		# 批次 AD（spec §4.2.2-3）等价改写：格式判据由「SWITCH_CAMERA:<单数字>」迁移为
		# 「START_CAMERA_BY_NAME:<设备名>」逐字格式（设备名可空=降级首项；无尾随空格契约）。
		if c.begins_with("START_CAMERA_BY_NAME:"):
			fmt_seen += 1
			var tail: String = c.substr(len("START_CAMERA_BY_NAME:"))
			if tail != tail.strip_edges() or tail.contains("
"):
				fmt_ok = false
	check(fmt_ok and fmt_seen > 0, "AD：START_CAMERA_BY_NAME:<名> 逐字格式（无尾随空格/换行；实测 %d 条）" % fmt_seen)
	bridge._simulate_start_ok = false
	resident.close()

	# ---- 段 6. GET_CAMERAS 增强（2 checks）----
	# 磁盘实况修正留痕：request_camera_enum 有 1000ms 节流（ENUM_REQUEST_THROTTLE_MS，批次 R 既有
	# 防御行为）——段 2/段 3 的 init#1 派发使状态机转 READY 时拉取模式已自动发过一次 GET_CAMERAS，
	# 段 6 显式调用距其 <1s 即被节流吞掉（本机 UDP 回环毫秒级送达时曾致本段红）。按公开语义复位
	# 节流哨兵（-1000000=从未发过的初始值，段 11 先例同款直写内部成员手法）再断言，30 条计数不变。
	bridge._last_enum_request_ms = -1000000
	var l6 := _ctrl_listener()
	bridge.request_camera_enum()
	await _wait_available(l6, 4)
	var cmds6 := _recv_cmds_noise_free(l6)
	check(cmds6.has("GET_CAMERAS"), "U2：request_camera_enum → GET_CAMERAS（既有，回归锚）")
	bridge.simulate_packet(JSON.stringify({"type": "init", "resolutions": [[1280, 720]], "fps_options": [30]}))
	check((bridge.get_camera_matrix() as Dictionary).has("resolutions"), "U2：GET_CAMERAS 后补发 init#2 → 矩阵缓存非空（桥层不再恒空）")
	if l6 != null:
		l6.close()

	finish()
