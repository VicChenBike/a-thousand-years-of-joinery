extends "res://tests/test_base.gd"
## 批次 AA（W4 摄像头生命周期域，spec §7）——桥侧/HUD 侧红测（无头零真摄像头）。
## 段口径（对应 spec §7.3/§7.5）：
##   A（W4-1 / R4-a 桥侧半测）：设备启动指令时序——探到 9878 已 bind（_probe_python_ready）
##     才发 START_CAMERA_BY_NAME:<存档设备名>；bind 前零发送；30s 窗内 1s 间隔重发；三档启动
##     耗时注入（8s / 15s 档=窗内 bind→照发；35s 档=窗过期→不发、转恢复路径兜底）；收到
##     camera_opened 且 id 匹配记忆设备即止发。
##   B（W4-6 / 开机自动恢复）：主恢复路径移到开机——首个 9876 包（READY 边沿）+ init#1
##     自动补发 SWITCH 切到记忆设备（不开设置面板）；3s 节流防刷；camera_opened 匹配即
##     停；python 开错设备（opened≠记忆）→ 补发 SWITCH 兜底。
##   C（R4-j 护栏）：开设置面板 ensure 幂等再确认——流开+目标==当前 → 零 SWITCH/零追发。
##   D（W4-7）：res/fps 递进恢复仅在「打开设备==记忆设备」时应用（匹配→追发；失配→不追发）。
##   E（W4-10 / R4-i）：HUD 清屏条件收窄——UNAVAILABLE↔LOADING 振荡期间流真值仍开 →
##     清屏次数 ≤1（纹理保留）；流真值开→关 → 恰清 1 次；READY+有纹理+流开 → 占位即隐。
## 夹具纪律：全程无头；自有桥实例走高位 override 端口（9876/9877/9878 零触碰）；
## 子类覆写 _probe_python_ready（bind 探测 mock）；user:// 备份还原（前缀 aacm）。
## 无头纪律（坑1/坑10）：成员取值经 Variant 判空（str 比较/null 守卫），红态不崩不挂死。

const BR_SCRIPT := "res://autoload/gesture_bridge.gd"
const HUD_SCENE := "res://scenes/shared/gesture_hud.tscn"

# 自有桥实例高位端口（单测串行跑；与真实端口及其他测试零交集）
const PORT_A := 20280   # 段A 握手时序
const PORT_B := 20282   # 段B 开机恢复
const PORT_C := 20284   # 段C 幂等再确认
const PORT_D := 20286   # 段D res/fps 锁死
const PORT_F := 20294   # 段F release 意图门（批次 AA 回修1 / W4-P2-1；+2/+10/+12 与 autoload override 20290~20292 错开）

# ===== 清档纪律（zcam/ybct 同款，前缀 aacm）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_aacm_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
var _pre_save_text: String = ""

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
		if FileAccess.file_exists(_disc_abs(p)):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(_disc_abs(p)):
			DirAccess.remove_absolute(_disc_abs(p))
	get_root().get_node("SaveManager").call("load_game")

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

## 9878(override+2) 回环监听（sniffer 同款）
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

## 成员布尔读防御（坑1：bool(null) 中止 _initialize——红态成员缺失不崩）
func _member_true(o: Object, member: String) -> bool:
	return str(o.get(member)) == "true"

## 整型成员读防御（成员缺失 null → 0）
func _member_int(o: Object, member: String) -> int:
	var v: Variant = o.get(member)
	if v == null:
		return 0
	return int(v)

func _initialize() -> void:
	print("== test_aa_camera_lifecycle ==")
	_backup_user()
	var save: Node = get_root().get_node("SaveManager")
	# 9876/9878 真端口防触碰：autoload 桥注入高位 override
	var gb_auto: Node = get_root().get_node("GestureBridge")
	gb_auto.set("_udp_port_override", 20290)

	# ================= 段 A（W4-1 / R4-a 桥侧）：握手时序——bind 前不发 =================
	# 子类覆写 _probe_python_ready（bind 探测 mock；spawn 后 _begin 只武装不发）
	var sub := GDScript.new()
	sub.source_code = """
extends "res://autoload/gesture_bridge.gd"
var probe_ret: bool = false
var probe_calls: int = 0
func _probe_python_ready() -> bool:
	probe_calls += 1
	return probe_ret
"""
	var reload_err: int = int(sub.reload())
	check_eq(reload_err, 0, "段A 前置：测试子类脚本编译成功")
	if reload_err != int(OK):
		finish()
		return
	save.update_settings({"gesture_camera_device": "HD Cam"})
	var br_a: Node = sub.new()
	br_a.set("_udp_port_override", PORT_A)
	add_child(br_a)
	await process_frame
	var snif_a := CtrlSniffer.new()
	check_eq(int(snif_a.bind(PORT_A + 2)), 0, "段A 前置：控制端口抓包器就位")
	br_a.set("preferred_handshake_interval_ms", 1)   # 重发间隔注入（可注入缝）
	br_a.set("_spawn_hook", func() -> bool: return true)
	var ok_a: bool = bool(br_a.call("_spawn"))
	check_eq(ok_a, true, "段A 前置：spawn hook 成功")
	# A1：spawn 后**未探到 bind** → 零启动指令（旧实现 spawn 即发 → 红）
	check_eq(snif_a.count_prefix("START_CAMERA_BY_NAME"), 0,
		"W4-1/A1：bind 未确认（probe=false）时 spawn 后零下发（旧实现即发=根因②，红）")
	# A2：bind 仍未确认 → tick 照旧零下发（bind 前的包必被内核丢弃，不发=唯一正确语义）
	br_a.set("probe_ret", false)
	for i: int in 3:
		br_a.set("_preferred_next_at_ms", int(Time.get_ticks_msec()) - 1)
		br_a.call("_process", 0.016)
	check_eq(snif_a.count_prefix("START_CAMERA_BY_NAME"), 0,
		"W4-1/A2：probe=false（python 未 bind）期间反复 tick 零下发")
	# A3（8s 档）：窗内 probe 转 true → 发送（30s 窗已耗 8s 的注入等价形态）
	br_a.set("probe_ret", true)
	br_a.set("_preferred_handshake_deadline_ms", int(Time.get_ticks_msec()) + 22000)
	br_a.set("_preferred_next_at_ms", int(Time.get_ticks_msec()) - 1)
	br_a.call("_process", 0.016)
	check_eq(snif_a.count_prefix("START_CAMERA_BY_NAME"), 1,
		"W4-1/A3-8s：启动耗时 8s（窗内）bind 确认后首发出（9878 握手）")
	check(snif_a.has_cmd("START_CAMERA_BY_NAME:HD Cam"),
		"AD/A3-8s：首发逐字 START_CAMERA_BY_NAME:HD Cam（按设备名启动；实际 %s）" % [snif_a.cmds])
	# A3（15s 档）：到点重发（1s 间隔注入后 next 到期）
	br_a.set("_preferred_handshake_deadline_ms", int(Time.get_ticks_msec()) + 15000)
	br_a.set("_preferred_next_at_ms", int(Time.get_ticks_msec()) - 1)
	br_a.call("_process", 0.016)
	check_eq(snif_a.count_prefix("START_CAMERA_BY_NAME"), 2,
		"W4-1/A3-15s：启动耗时 15s（窗内）按间隔重发")
	check(_member_true(br_a, "_preferred_handshake_armed"),
		"W4-1/A3：窗内重发期 armed=true（红态=成员缺失/过早止发）")
	# 止发：camera_opened 且 id 匹配记忆设备（记忆名 HD Cam → 枚举解析）
	br_a.set("_camera_enum", {"cameras": [{"id": 0, "name": "Phone"}, {"id": 2, "name": "HD Cam"}], "current_camera": 0})
	br_a.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 2, "name": "HD Cam"}))
	check(not _member_true(br_a, "_preferred_handshake_armed"),
		"W4-1/A4：camera_opened 且 id 匹配记忆设备 → 握手止发")
	br_a.set("_preferred_next_at_ms", int(Time.get_ticks_msec()) - 1)
	br_a.call("_process", 0.016)
	check_eq(snif_a.count_prefix("START_CAMERA_BY_NAME"), 2,
		"W4-1/A4：匹配后 tick 零新增下发（止发判据保持）")
	# A5（35s 档）：窗过期后 bind 才确认 → 不再下发（30s 是重发上限；转恢复路径兜底）
	var br_a2: Node = sub.new()
	br_a2.set("_udp_port_override", PORT_A + 100)
	add_child(br_a2)
	await process_frame
	var snif_a2 := CtrlSniffer.new()
	check_eq(int(snif_a2.bind(PORT_A + 102)), 0, "段A5 前置：抓包器就位")
	br_a2.set("preferred_handshake_interval_ms", 1)
	br_a2.set("probe_ret", true)
	br_a2.set("_spawn_hook", func() -> bool: return true)
	br_a2.call("_spawn")
	br_a2.set("_preferred_handshake_deadline_ms", int(Time.get_ticks_msec()) - 5000)   # 已用 35s > 30s 上限
	br_a2.set("_preferred_next_at_ms", int(Time.get_ticks_msec()) - 1)
	br_a2.call("_process", 0.016)
	check_eq(snif_a2.count_prefix("START_CAMERA_BY_NAME"), 0,
		"W4-1/A5-35s：启动耗时 35s（超 30s 重发上限）→ 零下发（上限口径）")
	check(not _member_true(br_a2, "_preferred_handshake_armed"),
		"W4-1/A5：窗过期 → 握手自动收束（armed=false）")
	# 35s 档兜底：READY+init 后由开机恢复路径补启动指令（移交 A5 的兜底闭环）
	br_a2.set("_camera_enum", {"cameras": [{"id": 0, "name": "Phone"}, {"id": 2, "name": "HD Cam"}], "current_camera": 0})
	br_a2.simulate_packet('{"timestamp":1.0,"left":null,"right":null}')
	check(snif_a2.has_cmd("START_CAMERA_BY_NAME:HD Cam"),
		"W4-1/A5：超窗未握手 → READY 边沿由开机恢复路径补发启动指令（兜底达成；实际 %s）" % [snif_a2.cmds])
	snif_a.close()
	snif_a2.close()
	br_a.free()
	br_a2.free()

	# ================= 段 B（W4-6）：开机自动恢复（不开设置面板） =================
	var br_b: Node = (load(BR_SCRIPT) as GDScript).new()
	br_b.set("_udp_port_override", PORT_B)
	add_child(br_b)
	await process_frame
	var snif_b := CtrlSniffer.new()
	check_eq(int(snif_b.bind(PORT_B + 2)), 0, "段B 前置：控制端口抓包器就位")
	save.update_settings({"gesture_camera_device": "HD Cam"})
	br_b.set("_camera_enum", {"cameras": [{"id": 0, "name": "Phone"}, {"id": 2, "name": "HD Cam"}], "current_camera": 0})
	# 首个 9876 包（READY 边沿）→ 自动补发启动指令切记忆设备（旧实现零下发=红）
	br_b.simulate_packet('{"timestamp":1.0,"left":null,"right":null}')
	check_eq(int(br_b.get_load_state()), int(br_b.LoadState.READY), "B 前置：首包 → READY")
	check_eq(snif_b.count_prefix("START_CAMERA_BY_NAME:HD Cam"), 1,
		"W4-6/B1：READY 边沿（不开面板）→ 自动按名下发启动指令（红态=0，恢复错挂在开面板）")
	# 节流：3s 内重复 READY 边沿零重发
	br_b._set_state(0)
	br_b.simulate_packet('{"timestamp":2.0,"left":null,"right":null}')
	check_eq(snif_b.count_prefix("START_CAMERA_BY_NAME:HD Cam"), 1,
		"W4-6/B2：恢复 3s 节流——重复 READY 边沿零重发")
	# camera_opened 匹配 → 恢复停发（satisfied）
	br_b.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 2, "name": "HD Cam"}))
	br_b.set("_preferred_restore_last_ms", -1000000)   # 节流复位（注入）
	br_b._set_state(0)
	br_b.simulate_packet('{"timestamp":3.0,"left":null,"right":null}')
	check_eq(snif_b.count_prefix("START_CAMERA_BY_NAME:HD Cam"), 1,
		"W4-6/B3：camera_opened 匹配记忆设备 → 恢复停发（satisfied 零下发）")
	# python 开错设备（closed→opened id=0）→ 节流复位后补发 SWITCH 兜底。
	# 批次 AA 回修1（W4-P2-1）**等价改写**：closed 的 reason 由 "release" 改 "device_lost"
	# ——旧稿的 release 关闭恰把「用户主动关闭后仍补发」这一错误行为断言成预期（该行为
	# 随回修1 退役，release 新语义见段 F）；device_lost（非用户关闭）保留 B4 原护栏意图
	# =「非用户关闭的开错设备仍恢复记忆设备」，判据与期望值零弱化（count 2 不变：
	# closed 事件自身恢复与 opened(id=0) 兜底同前缀计入）。
	br_b.simulate_packet(JSON.stringify({"type": "camera_closed", "id": 2, "reason": "device_lost"}))
	br_b.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "Phone"}))
	check_eq(snif_b.count_prefix("START_CAMERA_BY_NAME:HD Cam"), 2,
		"W4-6/B4：非 release 关闭后 camera_opened≠记忆设备 → 补发启动指令兜底（红态=1）")
	snif_b.close()
	br_b.free()

	# ================= 段 C（R4-j）：开设置面板 ensure 幂等再确认 =================
	var br_c: Node = (load(BR_SCRIPT) as GDScript).new()
	br_c.set("_udp_port_override", PORT_C)
	add_child(br_c)
	await process_frame
	var snif_c := CtrlSniffer.new()
	check_eq(int(snif_c.bind(PORT_C + 2)), 0, "段C 前置：抓包器就位")
	save.update_settings({"gesture_camera_device": "HD Cam", "gesture_camera_res": "1280x720", "gesture_camera_fps": 30})
	br_c.set("_camera_enum", {"cameras": [{"id": 0, "name": "Phone"}, {"id": 2, "name": "HD Cam"}], "current_camera": 2})
	br_c._set_state(1)   # READY
	br_c.set("camera_stream_open", true)   # 流已开（记忆设备）
	var rd_c: bool = bool(br_c.call("ensure_camera_open"))
	check_eq(rd_c, true, "C 前置：ensure 返回 true")
	check_eq(snif_c.count_prefix("START_CAMERA_BY_NAME"), 0,
		"R4-j/C1：开面板幂等再确认——流开+目标==当前 → 零启动指令")
	check_eq(snif_c.count_prefix("SWITCH_CAMERA"), 0,
		"R4-j/C1b：幂等门内零 SWITCH_CAMERA（双通路零下发）")
	check_eq(snif_c.count_prefix("SET_RESOLUTION"), 0,
		"R4-j/C2：幂等门内零 res 追发")
	check_eq(snif_c.count_prefix("SET_FPS"), 0,
		"R4-j/C3：幂等门内零 fps 追发")
	snif_c.close()
	br_c.free()

	# ================= 段 D（W4-7）：res/fps 仅在设备匹配时应用 =================
	var br_d: Node = (load(BR_SCRIPT) as GDScript).new()
	br_d.set("_udp_port_override", PORT_D)
	add_child(br_d)
	await process_frame
	var snif_d := CtrlSniffer.new()
	check_eq(int(snif_d.bind(PORT_D + 2)), 0, "段D 前置：抓包器就位")
	save.update_settings({"gesture_camera_device": "HD Cam", "gesture_camera_res": "1280x720", "gesture_camera_fps": 30})
	br_d.set("_camera_enum", {"cameras": [{"id": 0, "name": "Phone"}, {"id": 2, "name": "HD Cam"}], "current_camera": 0})
	# D1：开启设备≠记忆设备（事件边沿 false→true）→ 事件路径零追发（防跨设备串值）
	br_d.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "Phone"}))
	var d1_bad: bool = snif_d.count_prefix("SET_RESOLUTION") > 0 or snif_d.count_prefix("SET_FPS") > 0
	check(not d1_bad, "W4-7/D1：camera_opened≠记忆设备 → 零 res/fps 追发")
	# D2：ensure 流关 → 按名下发启动指令 + 匹配才追发 res/fps（正向锁）
	br_d.set("camera_stream_open", false)
	snif_d.cmds.clear()
	br_d.call("ensure_camera_open")
	check(snif_d.has_cmd("START_CAMERA_BY_NAME:HD Cam"),
		"W4-7/D2：ensure → 按名下发启动指令（AD 等价改写：旧断言为 SWITCH_CAMERA:2）")
	check(snif_d.has_cmd("SET_RESOLUTION:2:1280x720"), "W4-7/D2：设备匹配 → 记忆 res 追发")
	check(snif_d.has_cmd("SET_FPS:2:30"), "W4-7/D2：设备匹配 → 记忆 fps 追发")
	# D3：记忆名不在枚举 → 本桥零自选，按名原样下发（目标由 Python 降级承担）→ 不追发 res/fps
	# 批次 AD（spec §4.2.1/§4.2.2-4）等价改写留痕：AC「回落非手机物理设备」自选链随黑名单
	# 一并退役——不再按类型猜测设备，未命中名由 Python 侧 pick_camera_by_name 降级列表首项。
	# 断言条数不变、口径逐条迁移。
	save.update_settings({"gesture_camera_device": "Ghost Not In List"})
	snif_d.cmds.clear()
	br_d.set("_last_enum_request_ms", -1000000)
	br_d.call("ensure_camera_open")
	check(snif_d.has_cmd("START_CAMERA_BY_NAME:Ghost Not In List"),
		("AD 等价替换（旧 AC「回落非手机设备 2」）：记忆失配 → 按名原样下发，"
		+ "降级首项下沉 Python（实际 %s）") % [snif_d.cmds])
	check(not snif_d.any_prefix("SWITCH_CAMERA:"),
		"AD 反向护栏：零 SWITCH_CAMERA 数字命令（禁止依赖 CAP 索引；实际 %s）" % [snif_d.cmds])
	var d3_bad: bool = snif_d.count_prefix("SET_RESOLUTION") > 0 or snif_d.count_prefix("SET_FPS") > 0
	check(not d3_bad, "W4-7/D3：记忆失配 → 零 res/fps 追发（旧值不套异设备）")
	snif_d.close()
	br_d.free()

	# ================= 段 E（W4-10 / R4-i）：HUD 清屏条件收窄 =================
	# 批次 AB-3：深浅主题机制删除——_light_theme/_last_dark 注入退役（--script 下 autoload
	# _ready 推迟，显式注入 _dark_theme 保 current_theme() 可用，口径不变）。
	var theme_mgr: Node = get_root().get_node("ThemeManager")
	theme_mgr.set("_dark_theme", load("res://themes/theme_dark.tres"))
	var hud: Control = (load(HUD_SCENE) as PackedScene).instantiate()
	add_child(hud)
	await process_frame
	await process_frame
	var img: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	(hud.get("camera_window") as TextureRect).texture = tex
	gb_auto.set("camera_stream_open", true)   # 流真值仍开（链路抖动、摄像头未关）
	# 振荡 6 次边沿（UNAVAILABLE↔LOADING×3）→ 清屏 ≤1 且纹理保留（旧实现每边沿清=红）
	hud.call("_on_load_state", int(gb_auto.LoadState.UNAVAILABLE))
	hud.call("_on_load_state", int(gb_auto.LoadState.LOADING))
	hud.call("_on_load_state", int(gb_auto.LoadState.UNAVAILABLE))
	hud.call("_on_load_state", int(gb_auto.LoadState.LOADING))
	hud.call("_on_load_state", int(gb_auto.LoadState.UNAVAILABLE))
	hud.call("_on_load_state", int(gb_auto.LoadState.LOADING))
	var clear_n := _member_int(hud, "_texture_clear_count")
	check(hud.get("_texture_clear_count") != null,
		"W4-10/E0：清屏计数成员在位（红态=成员缺失）")
	check(clear_n <= 1,
		"W4-10/E1：UNAVAILABLE↔LOADING 振荡×3（流真值开）清屏次数 ≤1（红态=6；实际 %d）" % clear_n)
	check(hud.get("camera_window") != null and (hud.get("camera_window") as TextureRect).texture != null,
		"W4-10/E2：流真值开 → 振荡期间纹理保留（不清屏）")
	# 流真值开→关 → 恰清 1 次
	gb_auto.set("camera_stream_open", false)
	hud.call("_on_load_state", int(gb_auto.LoadState.UNAVAILABLE))
	check_eq(_member_int(hud, "_texture_clear_count"), 1,
		"W4-10/E3：流真值开→关 → 恰清 1 次（红态=成员缺失 0 或累计 >1）")
	check((hud.get("camera_window") as TextureRect).texture == null,
		"W4-10/E4：流真值关 → 纹理清空（陈旧帧不留）")
	# READY + 有纹理 + 流真值开 → 占位即隐（恢复后画面 1 次即出）
	var tex2 := ImageTexture.create_from_image(img)
	(hud.get("camera_window") as TextureRect).texture = tex2
	gb_auto.set("camera_stream_open", true)
	hud.call("_on_load_state", int(gb_auto.LoadState.READY))
	check(not (hud.get("camera_bg") as ColorRect).visible,
		"W4-10/E5：READY+有纹理+流开 → 占位底隐（画面 1 次即出，红态=底仍压旧态）")
	hud.queue_free()
	await process_frame
	gb_auto.set("camera_stream_open", false)   # 成员复位（防泄入后续测试）

	# ================= 段 F（批次 AA 回修1 / W4-P2-1）：release 意图锁存——用户主动关闭后零恢复 =================
	print("-- 段F release 意图门 --")
	save.update_settings({"gesture_camera_device": "HD Cam"})
	var br_f: Node = (load(BR_SCRIPT) as GDScript).new()
	br_f.set("_udp_port_override", PORT_F)
	add_child(br_f)
	await process_frame
	var snif_f := CtrlSniffer.new()
	check_eq(int(snif_f.bind(PORT_F + 2)), 0, "段F 前置：抓包器就位")
	br_f.set("_camera_enum", {"cameras": [{"id": 0, "name": "Phone"}, {"id": 2, "name": "HD Cam"}], "current_camera": 0})
	# F1 基线：opened≠记忆设备（Phone 开错）→ 恢复补发（W4-6 既有语义，回修1 不改；
	# AD 等价改写：补发命令改按设备名 START_CAMERA_BY_NAME:HD Cam）
	br_f.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "Phone"}))
	check_eq(snif_f.count_prefix("START_CAMERA_BY_NAME:HD Cam"), 1,
		"回修1/F1 基线：camera_opened≠记忆设备 → 补发启动指令（W4-6 语义保持）")
	# F2 用户主动关闭（release）→ 意图锁存置位
	br_f.simulate_packet(JSON.stringify({"type": "camera_closed", "id": 0, "reason": "release"}))
	check(_member_true(br_f, "_camera_release_intent"),
		"回修1/F2：camera_closed(reason=release) → release 意图锁存置位（红态=成员缺失/false）")
	# F3：release 后 READY 边沿再入恢复路径 → 门住零补发（修复前节流复位后必补发=红；
	# 用户症状「被明确关掉的摄像头 3s 后自动重开」的直接判定点）
	br_f.set("_preferred_restore_last_ms", -1000000)   # 节流复位注入（隔离 F1 的 3s 节流窗）
	br_f._set_state(0)
	br_f.simulate_packet('{"timestamp":4.0,"left":null,"right":null}')
	check_eq(snif_f.count_prefix("START_CAMERA_BY_NAME:HD Cam"), 1,
		"回修1/F3：release 关闭后 READY 边沿 → 恢复零补发（用户主动关优先于恢复记忆；红态=2）")
	# F4：release 后 init#1（枚举到达入口）→ 恢复同样被门住（三入口统一短路）
	br_f.set("_preferred_restore_last_ms", -1000000)
	br_f.simulate_packet(JSON.stringify({"type": "init", "cameras": [{"id": 0, "name": "Phone"}, {"id": 2, "name": "HD Cam"}], "current_camera": 0}))
	check_eq(snif_f.count_prefix("START_CAMERA_BY_NAME:HD Cam"), 1,
		"回修1/F4：release 关闭后 init#1 入口 → 恢复零补发（红态=2）")
	# F5：显式再开（ensure_camera_open）→ 锁存清除（后续恢复路径恢复可达）
	br_f.set("_simulate_start_ok", true)
	var ok_f: bool = bool(br_f.call("ensure_camera_open"))
	check_eq(ok_f, true, "回修1/F5 前置：ensure_camera_open 返回 true")
	check(not _member_true(br_f, "_camera_release_intent"),
		"回修1/F5：显式再开（ensure_camera_open）→ release 意图锁存清除")
	snif_f.close()
	br_f.free()

	# ---- 段F-b（反向护栏）：非 release 关闭（device_lost）→ 开错设备仍补发恢复 ----
	var br_f2: Node = (load(BR_SCRIPT) as GDScript).new()
	br_f2.set("_udp_port_override", PORT_F + 10)
	add_child(br_f2)
	await process_frame
	var snif_f2 := CtrlSniffer.new()
	check_eq(int(snif_f2.bind(PORT_F + 12)), 0, "段F-b 前置：抓包器就位")
	br_f2.set("_camera_enum", {"cameras": [{"id": 0, "name": "Phone"}, {"id": 2, "name": "HD Cam"}], "current_camera": 2})
	br_f2.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 2, "name": "HD Cam"}))
	br_f2.simulate_packet(JSON.stringify({"type": "camera_closed", "id": 2, "reason": "device_lost"}))
	br_f2.set("_preferred_restore_last_ms", -1000000)
	br_f2.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "Phone"}))
	check_eq(snif_f2.count_prefix("START_CAMERA_BY_NAME:HD Cam"), 1,
		"回修1/F-b 反向护栏：非 release（device_lost）→ 开错设备（opened id=0）仍补发恢复（红态=0）")
	check(not _member_true(br_f2, "_camera_release_intent"),
		"回修1/F-b：device_lost 不置 release 意图锁存（锁存仅 release 意图触发）")
	snif_f2.close()
	br_f2.free()

	save.update_settings({"gesture_camera_device": "", "gesture_camera_res": "", "gesture_camera_fps": 0})
	finish()
