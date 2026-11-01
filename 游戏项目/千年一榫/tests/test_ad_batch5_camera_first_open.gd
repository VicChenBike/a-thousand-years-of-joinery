extends "res://tests/test_base.gd"
## 批次 AD-5（F-1/F-2/F-3/F-4）——摄像头首开卡死与频闪（桥侧 + HUD 侧无头断言）。
## 段口径（对应需求 §4.1~§4.4；零真摄像头、零写档、高位端口）：
##   A（F-2）：三路 `START_CAMERA_BY_NAME` **共享同一节流记账**——
##     A1 restore→handshake 同目标 gap 内只发一条（跨源去重）；
##     A2 handshake→restore 同理（反向）；
##     A3 显式 ensure(force) 不被抑制（批次 AD「用户点开必须照发」可达性保持）。
##   B（F-3）：`camera_opened` 后存档 `gesture_camera_res=""`/`gesture_camera_fps=0`
##     → 零 SET_RESOLUTION / 零 SET_FPS 追发；反向护栏：真值在档时两发照常（防守卫过紧）。
##   C（F-4）：流真值开→关 → 摄像头窗显「摄像头连接中…」占位且**不清空 HUD**
##     （窗仍可见 / 纹理恰清 1 次 / 占位可见）；新帧到达解除；主动关与 UNAVAILABLE
##     两条既有文案回归锚不受影响。
## 夹具纪律：A/B 段桥为**子类替身**（覆写 `_probe_python_ready`/`_read_save_settings`
## 返回内存字典 → 零写档、零 spawn）；C 段只读 autoload 桥状态并在收尾复位。
## 无头纪律（坑1/坑10）：成员取值经 Variant 判空，红态不崩不挂死。

const BR_SCRIPT := "res://autoload/gesture_bridge.gd"
const HUD_SCENE := "res://scenes/shared/gesture_hud.tscn"

# 自有桥实例高位端口（每实例占 base/base+1/base+2 三口，取 4 间隔零交集；
# 与 autoload 桥 override(20696) 及真实 9876/9877/9878 零交集）
const PORT_A1 := 20680   # A1 restore 先发
const PORT_A2 := 20684   # A2 handshake 先发 + A3 ensure 反向
const PORT_B1 := 20688   # B1 空 res/fps 不追发
const PORT_B2 := 20692   # B2 真值在档照发（反向护栏）
const PORT_HUD := 20696  # C 段 autoload 桥注入（避免触碰真实端口）

# 9878(override+2) 回环监听（test_aa_camera_lifecycle 同款）
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

## 成员读防御（坑1：bool(null) 中止 _initialize——红态成员缺失不崩）
func _member_true(o: Object, member: String) -> bool:
	return str(o.get(member)) == "true"

func _member_str(o: Object, member: String) -> String:
	var v: Variant = o.get(member)
	return str(v) if v != null else ""

## 子类桥（probe/mock 设置双覆写）：零写档、零 spawn、bind 探测可注入。
func _make_bridge(port: int, settings: Dictionary) -> Node:
	var sub := GDScript.new()
	sub.source_code = """
extends "res://autoload/gesture_bridge.gd"
var probe_ret := false
var fake_settings: Dictionary = {}
func _probe_python_ready() -> bool:
	return probe_ret
func _read_save_settings() -> Dictionary:
	return fake_settings
"""
	var err: int = int(sub.reload())
	check_eq(err, 0, "AD-5 前置：测试子类脚本编译成功")
	if err != int(OK):
		return null
	var b: Node = sub.new()
	b.set("_udp_port_override", port)
	b.set("fake_settings", settings)
	b.set("probe_ret", true)
	add_child(b)
	await process_frame
	return b

func _release_bridge(b: Node) -> void:
	if b != null and is_instance_valid(b):
		b.free()

## 注入「恢复路径可发」的全部前置（枚举 + 无流 + 节流复位）
func _arm_restore(b: Node, cams: Array, cur: int) -> void:
	b.set("_camera_enum", {"cameras": cams, "current_camera": cur})
	b.set("camera_stream_open", false)
	b.set("camera_stream_device_id", -1)
	b.set("_camera_release_intent", false)
	b.set("_preferred_restore_last_ms", -1000000)

## 注入「握手 tick 可发」的全部前置
func _arm_handshake(b: Node, dev_name: String) -> void:
	b.set("_preferred_handshake_armed", true)
	b.set("_preferred_device_name", dev_name)
	b.set("_preferred_handshake_deadline_ms", int(Time.get_ticks_msec()) + 20000)
	b.set("_preferred_next_at_ms", int(Time.get_ticks_msec()) - 1)
	b.set("preferred_handshake_interval_ms", 1)
	b.set("_camera_release_intent", false)

func _initialize() -> void:
	print("== test_ad_batch5_camera_first_open（批次 AD-5：F-2 三路共享节流 / F-3 空 res/fps 不追发 / F-4 连接中占位） ==")
	var gb: Node = get_root().get_node("GestureBridge")
	gb.set("_udp_port_override", PORT_HUD)
	await _a_shared_throttle()
	await _b_res_fps_followup_guard()
	await _c_reconnect_placeholder()
	finish()

# ================= 段 A（F-2）：三路下发共享同一节流记账 =================
func _a_shared_throttle() -> void:
	print("-- A 三路 START_CAMERA_BY_NAME 共享节流（F-2） --")
	var cams: Array = [{"id": 0, "name": "Phone"}, {"id": 2, "name": "HD Cam"}]
	var settings: Dictionary = {"gesture_input": true,
		"gesture_camera_enabled": true, "gesture_camera_device": "HD Cam"}

	# A1：restore 先发 → 同目标 handshake tick 在 gap 内 → 抑制（跨源去重）
	var br1: Node = await _make_bridge(PORT_A1, settings)
	var snif1 := CtrlSniffer.new()
	check_eq(int(snif1.bind(PORT_A1 + 2)), 0, "A1 前置：控制端口抓包器就位")
	_arm_restore(br1, cams, 0)
	br1.call("_ensure_preferred_camera_restore")
	check_eq(snif1.count_prefix("START_CAMERA_BY_NAME:HD Cam"), 1,
		"A1-1 前置：restore 路径照发（既有语义回归锚）")
	_arm_handshake(br1, "HD Cam")
	br1.call("_process", 0.016)
	check_eq(snif1.count_prefix("START_CAMERA_BY_NAME:HD Cam"), 1,
		"A1-2：restore 已发同目标 → handshake tick 同帧/近距重复被共享账本抑制"
		+ "（红态=2；实际 %d）" % snif1.count_prefix("START_CAMERA_BY_NAME:HD Cam"))
	check_eq(_member_str(br1, "_start_send_last_src"), "restore",
		"A1-3：账本来源=restore（跨源去重观测缝）")
	snif1.close()
	_release_bridge(br1)

	# A2：反向——handshake 先发 → restore 在 gap 内 → 抑制；A3 显式 ensure 不被抑制
	var br2: Node = await _make_bridge(PORT_A2, settings)
	var snif2 := CtrlSniffer.new()
	check_eq(int(snif2.bind(PORT_A2 + 2)), 0, "A2 前置：控制端口抓包器就位")
	_arm_restore(br2, cams, 0)
	_arm_handshake(br2, "HD Cam")
	br2.call("_process", 0.016)
	check_eq(snif2.count_prefix("START_CAMERA_BY_NAME:HD Cam"), 1,
		"A2-1 前置：handshake tick 照发（既有语义回归锚）")
	br2.call("_ensure_preferred_camera_restore")   # 节流已注入复位，账本仍在 gap 内
	check_eq(snif2.count_prefix("START_CAMERA_BY_NAME:HD Cam"), 1,
		"A2-2：handshake 已发同目标 → restore 重复被共享账本抑制（红态=2；实际 %d）"
		% snif2.count_prefix("START_CAMERA_BY_NAME:HD Cam"))
	# A3 反向护栏：显式 ensure 走 force=true —— 用户点开必须照发（不被账本抑制）
	br2.set("_simulate_start_ok", true)
	br2.set("camera_stream_open", false)
	var ok_ensure: bool = bool(br2.call("ensure_camera_open"))
	check_eq(ok_ensure, true, "A3 前置：ensure 返回 true")
	check_eq(snif2.count_prefix("START_CAMERA_BY_NAME:HD Cam"), 2,
		"A3：显式 ensure 不受共享节流抑制（批次 AD「用户点开必须照发」可达性保持；"
		+ "红态=1 被吞；实际 %d）" % snif2.count_prefix("START_CAMERA_BY_NAME:HD Cam"))
	check_eq(_member_str(br2, "_start_send_last_src"), "ensure",
		"A3b：ensure 发出后照常记账（其后自动两路在其 gap 内被抑制）")
	snif2.close()
	_release_bridge(br2)

# ================= 段 B（F-3）：空 res/fps 不下发 SET_* =================
func _b_res_fps_followup_guard() -> void:
	print("-- B camera_opened 后空 res/fps 不追发（F-3） --")
	var cams: Array = [{"id": 2, "name": "HD Cam"}]
	# B1：存档 res 空 + fps=0 → 零 SET_RESOLUTION / 零 SET_FPS（本批 F-3 主断言）
	var s1: Dictionary = {"gesture_input": true, "gesture_camera_enabled": true,
		"gesture_camera_device": "HD Cam", "gesture_camera_res": "", "gesture_camera_fps": 0}
	var br1: Node = await _make_bridge(PORT_B1, s1)
	var snif1 := CtrlSniffer.new()
	check_eq(int(snif1.bind(PORT_B1 + 2)), 0, "B1 前置：控制端口抓包器就位")
	br1.set("_camera_enum", {"cameras": cams, "current_camera": -1})
	br1.set("camera_stream_open", false)
	br1.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 2, "name": "HD Cam"}))
	check_eq(snif1.count_prefix("SET_RESOLUTION"), 0,
		"B1-1：gesture_camera_res=\"\" → 零 SET_RESOLUTION 追发（实际 %s）" % [snif1.cmds])
	check_eq(snif1.count_prefix("SET_FPS"), 0,
		"B1-2：gesture_camera_fps=0 → 零 SET_FPS 追发（实际 %s）" % [snif1.cmds])
	check_eq(int(br1.get("camera_stream_device_id")), 2,
		"B1-3 前置：camera_opened 事件已消费（真值在位，守卫非空转）")
	snif1.close()
	_release_bridge(br1)
	# B2 反向护栏：真值在档 → 两发照常（守卫不得过紧到连合法值也吞）
	var s2: Dictionary = {"gesture_input": true, "gesture_camera_enabled": true,
		"gesture_camera_device": "HD Cam", "gesture_camera_res": "640x480",
		"gesture_camera_fps": 30}
	var br2: Node = await _make_bridge(PORT_B2, s2)
	var snif2 := CtrlSniffer.new()
	check_eq(int(snif2.bind(PORT_B2 + 2)), 0, "B2 前置：控制端口抓包器就位")
	br2.set("_camera_enum", {"cameras": cams, "current_camera": -1})
	br2.set("camera_stream_open", false)
	br2.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 2, "name": "HD Cam"}))
	check(snif2.has_cmd("SET_RESOLUTION:2:640x480"),
		"B2-1 反向护栏：res 在档 → SET_RESOLUTION 照发（实际 %s）" % [snif2.cmds])
	check(snif2.has_cmd("SET_FPS:2:30"),
		"B2-2 反向护栏：fps 在档 → SET_FPS 照发（实际 %s）" % [snif2.cmds])
	snif2.close()
	_release_bridge(br2)

# ================= 段 C（F-4）：重连期「连接中」占位态 =================
func _c_reconnect_placeholder() -> void:
	print("-- C 摄像头窗重连期「连接中」占位（F-4） --")
	var gb: Node = get_root().get_node("GestureBridge")
	gb.set("_camera_enum", {"cameras": [{"id": 2, "name": "HD Cam"}], "current_camera": 2})
	gb.set("_intentional_stop", false)
	var theme_mgr: Node = get_root().get_node("ThemeManager")
	theme_mgr.set("_dark_theme", load("res://themes/theme_dark.tres"))
	var hud: Control = (load(HUD_SCENE) as PackedScene).instantiate()
	add_child(hud)
	await process_frame
	await process_frame
	var img: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	# 前置：READY + 已有帧（首帧到达后 hint/bg 隐藏——与用户实机「画面出现」形态一致）
	gb._set_state(int(gb.LoadState.READY))
	hud.call("_on_camera_frame", tex)
	check(hud.camera_window.texture != null, "C0 前置：画面已就位")
	hud.camera_window.visible = true   # 不依赖存档手势开关（零写档纪律）
	# C1：流真值开→关（重连/释放在飞）→ 纹理恰清 1 次 + 窗不隐 + 占位显「连接中…」
	var clears_before := int(hud.get("_texture_clear_count"))
	gb.camera_stream_changed.emit(false, 2)
	check_eq(int(hud.get("_texture_clear_count")), clears_before + 1,
		"C1-1：流关 → 陈旧纹理恰清 1 次（红态=0 仍留僵死旧画面）")
	check(hud.camera_window.texture == null, "C1-2：不留僵死旧帧")
	check_eq(bool(hud.camera_window.visible), true,
		"C1-3：重连期摄像头窗不隐（HUD 不整片消失；红态=窗被清掉）")
	check_eq(bool(hud.camera_hint.visible), true,
		"C1-4：占位文案可见（红态=hint 停留在首帧时的隐藏态 → 窗内空无一物）")
	check_eq(_member_true(hud, "_reconnect_placeholder"), true,
		"C1-5：「连接中」占位置位（观测缝）")
	check_eq(String(hud.camera_hint.text), "摄像头连接中…",
		"C1-6：文案=「摄像头连接中…」（红态=旧「启动中…」/空串；实际 %s）"
		% hud.camera_hint.text)
	check_eq(bool(hud.camera_bg.visible), true, "C1-7：占位底可见")
	# C2：新帧到达 → 解除连接中态、画面让位
	hud.call("_on_camera_frame", tex)
	check_eq(_member_true(hud, "_reconnect_placeholder"), false,
		"C2-1：新帧到达清除「连接中」标志")
	check_eq(bool(hud.camera_hint.visible), false, "C2-2：新帧到达占位让位（S13 语义不变）")
	# C3 回归锚：主动关门文案仍最优先（既有 W-N3 E3 锚）
	gb.camera_stream_changed.emit(false, 2)
	gb.set("_intentional_stop", true)
	check(String(hud.call("_camera_placeholder_text")).contains("已关闭"),
		"C3：主动关仍报「摄像头已关闭」（既有文案回归锚；实际 %s）"
		% String(hud.call("_camera_placeholder_text")))
	gb.set("_intentional_stop", false)
	# C4 回归锚：UNAVAILABLE 文案不受「连接中」标志影响（既有 W-N3 E5 锚）
	gb._set_state(int(gb.LoadState.UNAVAILABLE))
	check_eq(String(hud.call("_camera_placeholder_text")), "摄像头暂未打开",
		"C4：UNAVAILABLE 枚举非空仍「摄像头暂未打开」（既有文案回归锚；实际 %s）"
		% String(hud.call("_camera_placeholder_text")))
	# C5 回归锚：READY 无帧且未经历流关 → 仍「启动中…」（既有 W-N3 E6 锚）
	gb._set_state(int(gb.LoadState.READY))
	hud.set("_reconnect_placeholder", false)
	check(String(hud.call("_camera_placeholder_text")).contains("启动中"),
		"C5：READY 无帧默认「启动中…」（既有文案回归锚；实际 %s）"
		% String(hud.call("_camera_placeholder_text")))
	hud.queue_free()
	# 收尾复位 autoload 桥（进程即退，仍按纪律清位）
	gb.set("_camera_enum", {})
	gb.set("camera_stream_open", false)
	gb.set("camera_stream_device_id", -1)
