extends "res://tests/test_base.gd"
## 批次 AD（2026-09-27）批次二「真实摄像头生命周期重构」专项回归（spec §4.2）。
## 段口径（红态=改前；全部零真开镜/零 spawn：设备枚举与桥态一律 simulate_packet/成员注入）：
##   A（黑名单硬编码彻底移除，spec §4.2.1）：
##     A1 桥侧 `VIRTUAL_OR_PHONE_KEYWORDS` / `is_virtual_or_phone_camera_name` /
##        `_pick_non_phone_camera_id` 三个符号**彻底不在位**（代码行判定，留痕注释不计）；
##     A2 Python 侧同名黑名单符号与关键词亦不在位（源码锚，剥注释行判定）；
##     A3 反向护栏：物理设备名仍可被查名解析命中（黑名单退役≠选择失效）。
##   B（Godot 依设备名称字符串启动，spec §4.2.2-2/3）：
##     B1 有记忆名 → `START_CAMERA_BY_NAME:<实名>` 逐字下发（禁止 CAP 索引数字）；
##     B2 无记忆名 → 照发**空载荷** `START_CAMERA_BY_NAME:`（无尾随内容，Python 降级首项）；
##     B3 `_resolve_target_camera_id` 忽略大小写与首尾空格命中；纯数字残留**不再**按 CAP
##        索引解释（→ -1，走首项降级）；
##     B4 `_first_camera_entry_id` 纯函数：首项可解析 id；脏条目顺延；空/全脏 → -1；
##     B5 `ensure_camera_open` 有枚举 → 按名下发启动指令（零 SWITCH_CAMERA 数字命令）；
##        数字命令 `SWITCH_CAMERA:<id>` 仍由显式设备行点击路径保留（协议零破坏）。
##   C（0 摄像头安全响应，spec §4.2.2-4 + §7.2）：
##     C1 init#1 cameras=[] 且 current_camera=-1 → `_camera_enum_zero` 置真 + 零启动指令下发；
##     C2 zero 态 `ensure_camera_open` 短路（零 START_CAMERA_BY_NAME/零 SWITCH_CAMERA）；
##     C3 current_camera=-1（未启动）不触发 restore 补发（无目标）；
##     C4 反向护栏：有设备态照常下发启动指令（防改过头）。
## 清档纪律：user:// 备份还原四件组（前缀 adb2，test_ac_batch2_camera 同款逐字节自证）；
##   面板/桥 _ready 会触档（SaveManager），备份-还原覆盖之。
## 无头纪律（坑1/坑10）：成员/节点取值一律 Variant 判空 + str 比较，红态不崩不挂死。
## 治具端口/资源纪律（2026-09-28 审查 P2 回修）：各段桥实例基址 30 步进互斥（旧 10 步进 +
##   偏移复用致 20660/20670 自撞 push_error「UDP 绑定失败」）；每段用毕即 `_release_bridge`
##   即时 free（桥侧无 `_cleanup`，socket 收口在 `_exit_tree`），端口零残留、跨段零串扰。

const BR_SCRIPT := "res://autoload/gesture_bridge.gd"
const PY_SERVER := "res://gesture_runtime/hand_tracking_server.py"
const PY_SELECTOR := "res://gesture_runtime/camera_selector.py"

const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_adb2_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]

# 自有桥实例高位端口（单测串行跑；与 9876/9877/9878 及他测 override 零交集；
# 每实例实测占用 override..override+2（桥 P/P+1 收包 + 抓包器 P+2），故基址一律 30 步进
#（相邻段净隙 ≥ 27 端口）——段内偏移（+2/+10/+12 任一笔）都不可能触达邻段占用面）
const PORT_B1 := 20640   # 段B1 有记忆名下发（sniffer +2）
const PORT_B2 := 20670   # 段B2 无记忆名空载荷（sniffer +2）；B5 独立基址见 PORT_B5
const PORT_B5 := 20700   # 段B5 ensure 有枚举按名下发（sniffer +2；旧=PORT_B2+10 与 PORT_C 自撞）
const PORT_C := 20730    # 段C zero 态短路（sniffer +2）
const PORT_C4 := 20760   # 段C4 反向护栏有设备态（sniffer +2；旧=PORT_C+10 与 PORT_MISC 自撞）
const PORT_C5 := 20790   # 段C5 release 锁存门（sniffer +2）
const PORT_MISC := 20820 # 段A3/B3/B4 纯函数与 autoload 注入位（无端口监听需求）

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
	## 任一命令以 prefix 开头（逐字命令在 cmds 里的存在性）
	func any_prefix(prefix: String) -> bool:
		drain()
		for c: Variant in cmds:
			if String(c).begins_with(prefix):
				return true
		return false

func _src(p: String) -> String:
	return FileAccess.get_file_as_string(p)

## 剥整行注释后再断语句（留痕注释会引用被退役标识符；test_ac_batch2_camera 同款口径）
func _code_only(src: String) -> String:
	var out: Array[String] = []
	for ln: String in src.split("\n"):
		if ln.strip_edges().begins_with("#"):
			continue
		out.append(ln)
	return "\n".join(out)

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

## 治具资源即时释放（2026-09-28 审查 P2 回修）：桥实例 free 即走 _exit_tree → _udp/_jpeg_udp
## 双 socket close，端口当场归还（实测：free 后原 override 与 override+1 重 bind 均 err=0）；
## 不 free 则端口滞留至进程退出，后续段 bind 失败刷 push_error「UDP 绑定失败」。
## 桥侧无独立 `_cleanup` 方法（`has_method("_cleanup")` 实测否）——仍以守卫前探调用一次，
## 防未来桥引入清理钩子时治具漏调；守卫不成立则零调用零报错（无头零 SCRIPT ERROR 红线）。
func _release_bridge(br: Node) -> void:
	if not is_instance_valid(br):
		return
	if br.has_method("_cleanup"):
		br.call("_cleanup")
	br.free()

## 等待目标命令到达（UDP 回环毫秒级但需让帧轮转；他测同款手法）
func _wait_cmd(snif: CtrlSniffer, target: String, frames: int = 30) -> bool:
	for i: int in frames:
		if snif.has_cmd(target):
			return true
		await process_frame
	return snif.has_cmd(target)

## 等待任一以 prefix 开头的命令到达
func _wait_any_prefix(snif: CtrlSniffer, prefix: String, frames: int = 30) -> bool:
	for i: int in frames:
		if snif.any_prefix(prefix):
			return true
		await process_frame
	return snif.any_prefix(prefix)

# ================= 段 A（黑名单硬编码彻底移除，spec §4.2.1） =================
func _section_a() -> void:
	print("-- A 黑名单硬编码彻底移除（spec §4.2.1） --")
	var br_src: String = _src(BR_SCRIPT)
	var br_code: String = _code_only(br_src)
	var sel_src: String = _src(PY_SELECTOR)
	var srv_src: String = _src(PY_SERVER)
	check(not br_src.is_empty(), "A0 前置：gesture_bridge.gd 可读")
	check(not sel_src.is_empty(), "A0 前置：camera_selector.py 可读")
	check(not srv_src.is_empty(), "A0 前置：hand_tracking_server.py 可读")

	check(not br_code.contains("VIRTUAL_OR_PHONE_KEYWORDS"),
		"A1 桥侧黑名单关键词常量彻底退役（红态=仍在位）")
	check(not br_code.contains("is_virtual_or_phone_camera_name"),
		"A1 桥侧黑名单判定函数彻底退役（红态=仍在位）")
	check(not br_code.contains("_pick_non_phone_camera_id"),
		"A1 桥侧非手机首选函数彻底退役（红态=仍在位）")

	var sel_code: String = _code_only(sel_src)
	check(not sel_code.contains("VIRTUAL_OR_PHONE_CAMERA_KEYWORDS"),
		"A2 Python 侧黑名单关键词元组彻底退役")
	check(not sel_code.contains("is_virtual_or_phone_camera"),
		"A2 Python 侧黑名单判定函数彻底退役")
	check(not sel_code.contains("pick_auto_camera"),
		"A2 Python 侧自动缺省选择彻底退役（无自选设备通路）")
	check(not sel_code.contains("def rotate_backend_chain")
		and not sel_code.contains("rotate_backend_chain("),
		"A2 Python 侧后端轮换链彻底退役（定义与调用双无；AD §4.2.3 单后端）")
	var srv_code: String = _code_only(srv_src)
	check(not srv_code.contains("is_virtual_or_phone_camera")
		and not srv_code.contains("pick_auto_camera"),
		"A2 server 侧无黑名单/自动选择引用")
	for kw: String in ["magic", "荣耀", "honor", "obs", "vcam", "droidcam", "iriun", "跨屏", "互联"]:
		check(not sel_code.to_lower().contains(kw),
			"A2 camera_selector 代码行不含黑名单关键词「%s」" % kw)

	# A3 反向护栏：物理设备名仍可被查名解析命中
	var probe: Node = (load(BR_SCRIPT) as GDScript).new()
	var cams: Array = [{"id": 0, "name": "Integrated Camera"}, {"id": 3, "name": "USB2.0 HD UVC WebCam"}]
	check_eq(int(probe.call("_resolve_target_camera_id", cams, "USB2.0 HD UVC WebCam")), 3,
		"A3 物理设备名仍可被查名解析命中（黑名单退役≠选择失效）")
	probe.free()

# ================= 段 B（Godot 依设备名称字符串启动，spec §4.2.2-2/3） =================
func _section_b() -> void:
	print("-- B Godot 依设备名称字符串启动（spec §4.2.2-2/3） --")
	var save: Node = get_root().get_node("SaveManager")
	var src: String = _src(BR_SCRIPT)
	var code: String = _code_only(src)

	check(code.contains("START_CAMERA_BY_NAME:"),
		"B0 桥侧启动指令主协议逐字在位（红态=只发 SET_PREFERRED_CAMERA:）")
	check(code.contains("_first_camera_entry_id"),
		"B0 首项物理设备 id 纯函数在位（未命中/空名降级目标解析）")

	var probe: Node = (load(BR_SCRIPT) as GDScript).new()
	var cams2: Array = [{"id": 0, "name": "HD Camera"}, {"id": 3, "name": "USB Camera"}]
	check_eq(int(probe.call("_resolve_target_camera_id", cams2, "hd camera")), 0,
		"B3 记忆名忽略大小写命中 → id 0")
	check_eq(int(probe.call("_resolve_target_camera_id", cams2, "  USB CAMERA  ")), 3,
		"B3 记忆名首尾空格不敏感 → id 3")
	check_eq(int(probe.call("_resolve_target_camera_id", cams2, "3")), -1,
		"B3 纯数字残留不再按 CAP 索引解释（→ -1，走首项降级；禁止依赖 CAP 索引）")
	check_eq(int(probe.call("_resolve_target_camera_id", cams2, "9")), -1,
		"B3 数字不在枚举亦不命中（防脏值伪命中）")
	check_eq(int(probe.call("_resolve_target_camera_id", cams2, "Ghost Cam")), -1,
		"B3 名字不在枚举 → -1")
	check_eq(int(probe.call("_resolve_target_camera_id", cams2, "")), -1, "B3 空名 → -1")
	check_eq(int(probe.call("_resolve_target_camera_id", cams2, "   ")), -1, "B3 纯空格 → -1")
	check_eq(int(probe.call("_first_camera_entry_id", cams2)), 0, "B4 首项 id 解析 → 0")
	check_eq(int(probe.call("_first_camera_entry_id", [{"name": "No Id"}, {"id": 5, "name": "B"}])), 5,
		"B4 脏条目（无 id）顺延取下一可解析条目 → 5")
	check_eq(int(probe.call("_first_camera_entry_id", [{"name": "No Id"}])), -1,
		"B4 全脏条目 → -1（零盲发）")
	check_eq(int(probe.call("_first_camera_entry_id", [])), -1, "B4 空列表 → -1")
	probe.free()

	# B1 有记忆名 → START_CAMERA_BY_NAME:<实名> 逐字下发
	save.update_settings({"gesture_camera_device": "USB Camera",
		"gesture_camera_enabled": true, "gesture_input": true})
	var br1: Node = await _make_bridge(PORT_B1)
	var snif1 := CtrlSniffer.new()
	check_eq(int(snif1.bind(PORT_B1 + 2)), 0, "段B1 前置：控制端口抓包器就位")
	br1.set("preferred_handshake_interval_ms", 1)
	br1.set("_spawn_hook", func() -> bool: return true)
	br1.set("_camera_enum", {"cameras": [{"id": 0, "name": "HD Camera"},
		{"id": 3, "name": "USB Camera"}], "current_camera": -1})
	br1.call("_spawn")
	br1.set("_preferred_next_at_ms", int(Time.get_ticks_msec()) - 1)
	br1.call("_process", 0.016)
	check(await _wait_cmd(snif1, "START_CAMERA_BY_NAME:USB Camera"),
		"B1 有记忆名 → 逐字下发 START_CAMERA_BY_NAME:USB Camera（实际 %s）" % [snif1.cmds])
	check(not snif1.any_prefix("SWITCH_CAMERA:"),
		"B1 下发期零 SWITCH_CAMERA 数字命令（禁止依赖 CAP 索引；实际 %s）" % [snif1.cmds])
	_release_bridge(br1)   # 审查 P2：段B1 用毕即释放（20640/20641 当场归还，防跨段滞留）

	# B2 无记忆名 → 空载荷 START_CAMERA_BY_NAME:
	save.update_settings({"gesture_camera_device": ""})
	var br2: Node = await _make_bridge(PORT_B2)
	var snif2 := CtrlSniffer.new()
	check_eq(int(snif2.bind(PORT_B2 + 2)), 0, "段B2 前置：控制端口抓包器就位")
	br2.set("preferred_handshake_interval_ms", 1)
	br2.set("_spawn_hook", func() -> bool: return true)
	br2.call("_spawn")
	br2.set("_preferred_next_at_ms", int(Time.get_ticks_msec()) - 1)
	br2.call("_process", 0.016)
	check(await _wait_cmd(snif2, "START_CAMERA_BY_NAME:"),
		"B2 无记忆名 → 照发空载荷逐字 START_CAMERA_BY_NAME:（无尾随内容；实际 %s）" % [snif2.cmds])
	_release_bridge(br2)   # 审查 P2：段B2 用毕即释放

	# B5 ensure_camera_open 有枚举 → 按名下发启动指令（零 SWITCH_CAMERA 数字命令）
	var br5: Node = await _make_bridge(PORT_B5)
	var snif5 := CtrlSniffer.new()
	check_eq(int(snif5.bind(PORT_B5 + 2)), 0, "段B5 前置：控制端口抓包器就位")
	save.update_settings({"gesture_camera_device": "USB Camera",
		"gesture_camera_enabled": true, "gesture_input": true})
	br5.set("_simulate_start_ok", true)
	br5.set("_camera_enum", {"cameras": [{"id": 0, "name": "HD Camera"},
		{"id": 3, "name": "USB Camera"}], "current_camera": -1})
	br5.call("ensure_camera_open")
	check(await _wait_cmd(snif5, "START_CAMERA_BY_NAME:USB Camera"),
		"B5 ensure 有枚举 → 按名下发启动指令（实际 %s）" % [snif5.cmds])
	check(not snif5.any_prefix("SWITCH_CAMERA:"),
		"B5 ensure 下发的启动指令不为 SWITCH_CAMERA 数字（实际 %s）" % [snif5.cmds])
	_release_bridge(br5)   # 审查 P2：段B5 用毕即释放（旧漏释放致 20660 滞留 → 段C 起测即绑定失败）

# ================= 段 C（0 摄像头安全响应，spec §4.2.2-4/§7.2） =================
func _section_c() -> void:
	print("-- C 0 摄像头安全响应（spec §4.2.2-4/§7.2） --")
	var save: Node = get_root().get_node("SaveManager")
	save.update_settings({"gesture_camera_device": "HD Camera",
		"gesture_camera_enabled": true, "gesture_input": true})
	var br: Node = await _make_bridge(PORT_C)
	var snif := CtrlSniffer.new()
	check_eq(int(snif.bind(PORT_C + 2)), 0, "段C 前置：控制端口抓包器就位")
	br.set("_simulate_start_ok", true)

	# C1 init#1 空列表 + current_camera=-1 → zero 确认 + 零启动指令
	br.simulate_packet(JSON.stringify({"type": "init", "cameras": [], "current_camera": -1}))
	await process_frame
	check(_member_true(br, "_camera_enum_zero"),
		"C1 init#1 cameras=[] → _camera_enum_zero 置真（0 摄像头确认；红态=未置真）")
	check_eq(int((br.get("_camera_enum") as Dictionary).get("current_camera", 0)), -1,
		"C1 current_camera=-1 未启动哨兵入缓存（非 0 误报）")
	await process_frame
	check_eq(snif.count_prefix("START_CAMERA_BY_NAME"), 0,
		"C1 zero 态启动指令零下发（实际 %s）" % [snif.cmds])
	check_eq(snif.count_prefix("SWITCH_CAMERA"), 0,
		"C1 zero 态 SWITCH_CAMERA 零下发（绝不盲开设备 0；实际 %s）" % [snif.cmds])

	# C2 zero 态 ensure 短路
	br.call("ensure_camera_open")
	await process_frame
	check_eq(snif.count_prefix("START_CAMERA_BY_NAME"), 0,
		"C2 zero 态 ensure 短路：零 START_CAMERA_BY_NAME（实际 %s）" % [snif.cmds])
	check_eq(snif.count_prefix("SWITCH_CAMERA"), 0,
		"C2 zero 态 ensure 短路：零 SWITCH_CAMERA（实际 %s）" % [snif.cmds])

	# C3 current_camera=-1（未启动）不触发 restore 补发（无目标）
	br.set("_camera_release_intent", false)
	br.set("_simulate_start_ok", true)
	br.call("_ensure_preferred_camera_restore")
	await process_frame
	check_eq(snif.count_prefix("START_CAMERA_BY_NAME"), 0,
		"C3 current_camera=-1 未启动态不触发 restore 补发（实际 %s）" % [snif.cmds])
	_release_bridge(br)   # 审查 P2：C1~C3 用毕即释放，新建 br4 前置（端口零残留、段内零串扰）

	# C4 反向护栏：有设备态照常下发启动指令（防改过头）
	var br4: Node = await _make_bridge(PORT_C4)
	var snif4 := CtrlSniffer.new()
	check_eq(int(snif4.bind(PORT_C4 + 2)), 0, "段C4 前置：控制端口抓包器就位")
	br4.set("_simulate_start_ok", true)
	br4.set("_camera_enum", {"cameras": [{"id": 2, "name": "HD Camera"}], "current_camera": -1})
	br4.call("ensure_camera_open")
	check(await _wait_cmd(snif4, "START_CAMERA_BY_NAME:HD Camera"),
		"C4 反向护栏：有设备态照常按名下发启动指令（实际 %s）" % [snif4.cmds])
	_release_bridge(br4)   # 审查 P2：段C4 用毕即释放（旧漏释放致 20670 滞留 → 撞 autoload override）

	# C5 用户主动关闭锁存 → 自动补发路径零下发（AD：AC 的 release 拦截上提到桥侧；
	# Python 侧命令现为「显式开启」语义不得被拦，故锁存必须由本桥自动路径承担）
	save.update_settings({"gesture_camera_device": "HD Camera"})
	var br5: Node = await _make_bridge(PORT_C5)
	var snif5 := CtrlSniffer.new()
	check_eq(int(snif5.bind(PORT_C5 + 2)), 0, "段C5 前置：控制端口抓包器就位")
	br5.set("_simulate_start_ok", true)
	br5.set("_camera_enum", {"cameras": [{"id": 2, "name": "HD Camera"}], "current_camera": -1})
	br5.set("_camera_release_intent", true)   # 用户主动关闭锁存
	br5.set("_preferred_restore_last_ms", -1000000)
	br5.call("_ensure_preferred_camera_restore")
	check_eq(snif5.count_prefix("START_CAMERA_BY_NAME"), 0,
		"C5：release 锁存 → 自动恢复路径零下发（用户关掉的摄像头不得被自动复活；实际 %s）" % [snif5.cmds])
	# 握手重发调度同门（锁存期零自动补发）
	br5.set("_preferred_handshake_armed", true)
	br5.set("_preferred_handshake_deadline_ms", int(Time.get_ticks_msec()) + 20000)
	br5.set("_preferred_next_at_ms", int(Time.get_ticks_msec()) - 1)
	br5.set("_preferred_device_name", "HD Camera")
	br5.call("_process", 0.016)
	check_eq(snif5.count_prefix("START_CAMERA_BY_NAME"), 0,
		"C5：release 锁存 → 握手重发调度同门零下发（实际 %s）" % [snif5.cmds])
	# 反向护栏：清锁存（用户显式再开）→ 自动路径恢复可达
	br5.set("_camera_release_intent", false)
	br5.call("_ensure_preferred_camera_restore")
	check(await _wait_cmd(snif5, "START_CAMERA_BY_NAME:HD Camera"),
		"C5 反向护栏：清锁存后自动恢复照发（显式再开路径可达；实际 %s）" % [snif5.cmds])
	_release_bridge(br5)   # 审查 P2：段C5 用毕即释放（20790/20791 归还，段C 端口零残留）

# ================= 段 D（Python 侧冷启动与单后端源码锚，spec §4.2.2-1/§4.2.3） =================
func _section_d() -> void:
	print("-- D Python 侧冷启动与单后端源码锚（spec §4.2.2-1/§4.2.3） --")
	var srv_src: String = _src(PY_SERVER)
	var sel_src: String = _src(PY_SELECTOR)
	var srv_code: String = _code_only(srv_src)
	var sel_code: String = _code_only(sel_src)

	check(srv_code.contains('"current_camera": -1'),
		"D1 冷启动 init#1 current_camera 恒发 -1 未启动哨兵（红态=auto 缺省 id）")
	check(srv_code.contains("return None"),
		"D1 启动前序返回恒 None（无首开目标，零开镜）")
	check(not srv_code.contains("def _wait_for_preference")
		and not srv_code.contains("self._wait_for_preference("),
		"D1 握手等待窗定义与调用彻底退役（启动零阻塞）")
	check(not srv_code.contains("def _choose_initial_camera_id")
		and not srv_code.contains("self._choose_initial_camera_id("),
		"D1 首开选择定义与调用彻底退役（设备启停等 Godot 指令）")
	check(not srv_code.contains("PREFERRED_WAIT_SEC ="),
		"D1 等待窗常量彻底退役")
	check(srv_code.contains("pick_camera_by_name"),
		"D2 查名直启纯函数调用在位")
	check(srv_code.contains("START_CAMERA_BY_NAME:") and srv_code.contains("SET_PREFERRED_CAMERA:"),
		"D2 新命令主协议 + 旧命令兼容同路在位")
	check(sel_code.contains("def pick_camera_by_name("),
		"D2 camera_selector 查名直启纯函数在位")
	check(sel_code.contains("cv.CAP_DSHOW") and not sel_code.contains("CAP_MSMF"),
		"D3 单后端 CAP_DSHOW 直启且 CAP_MSMF 轮换彻底退役")
	check(sel_code.contains("CAP_PROP_FOURCC") and sel_code.contains("CAP_PROP_BUFFERSIZE"),
		"D3 MJPG + BUFFERSIZE 固定配置在位")

func _initialize() -> void:
	print("== test_ad_batch2_camera ==")
	_backup_user()
	var gb_auto: Node = get_root().get_node("GestureBridge")
	gb_auto.set("_udp_port_override", PORT_MISC)

	_section_a()
	await _section_b()
	await _section_c()
	_section_d()

	finish()
