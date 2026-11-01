extends "res://tests/test_base.gd"
## 批次 W W2（2026-09-20 规格 §3）——存档与设置域 TDD 红测先行。
## 契约来源：批次 W 规格 §3（P2-3a/P2-3b/P2-3c/N10/支撑项）+ W0 §一 P2-3/N10/N11。
## 五段口径：
##   A（P2-3a）udp_port 单一真源：gesture_bridge.get_udp_port() 恒常量 9876 派生（P/P+1/P+2
##     派生不变）——存档 settings.udp_port 退役不再消费（键不删不迁移，磁盘档仍保留）；
##     存档端口被改（9999）后桥仍绑 9876，与 launcher（环境变量默认 9876）语义恒一致。
##   B（P2-3b 桥消费集成）摄像头设备记忆升级「显示名字符串匹配」——注入记忆名档
##     ensure_camera_open 命中同名设备 id；注入旧档数字残留 "3"（不在枚举）→ 回落首可用设备；
##     记忆名不在枚举 → 回落首设备且不追发 res/fps（V17 防跨设备串值语义等价迁移）。
##   C（P2-3c）reset_for_new_game 保留 settings 域——settings 子字典**原引用**搬入新档
##     （is_same 判定），音量/摄像头记忆不变、不发 settings_changed（音频不重应用）；
##     progress/skins/talent 复位默认。
##   D（N10）摄像头配置即改即存——三键（设备名/分辨率/帧率）update_settings 后 save.json
##     即时含值 + 新实例 load_game 无损读回（重启恢复语义；恢复链路命令序由 B 段锁定）。
##   E（支撑项）桥只读态 API is_camera_intentionally_released()——置位期间恒真（不消费标志
##     本身）、start_gesture_process 后转 false；consume 一次性语义不变。
## 清档纪律（tools/README_走查清档规范.md，test_w_save_resilience 同款）：起测前备份 user://
##   真实档案四件组（save.json/flag/.tmp/.bak），终测统一还原+load_game 重同步+逐字节等价断言；
##   崩溃自愈（上次强杀残留备份先还原再重备份）。零摄像头（全程无头，不真拉起子进程）。

const SM_SCRIPT := "res://autoload/save_manager.gd"
const BR_SCRIPT := "res://autoload/gesture_bridge.gd"
const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"
# 备份路径必须带全 user:// 前缀（test_v_save_domain 先例）；前缀独立防与其他测试互踩。
const BK_PREFIX := "user://_w2_save_domain_"
const WATCHED_PATHS: Array = [SAVE_PATH, FLAG_PATH, TMP_PATH, BAK_PATH]

var _sm_seq: int = 0
var _pre_save_text: String = ""  # 起测前真实 save.json 原文（还原等价自检基准）

func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _del(p: String) -> void:
	var a: String = _abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _read_file(p: String) -> String:
	return FileAccess.get_file_as_string(p)

func _disk_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var v: Variant = JSON.parse_string(_read_file(SAVE_PATH))
	return v if v is Dictionary else {}

func _selfheal_previous_backup() -> void:
	## 崩溃自愈（test_w_save_resilience 先例）：上次运行若中途被杀，本前缀备份滞留 user://
	## 且沙盒残留未还原——直接重备份会把残留物覆盖进备份。先还原真实档案再重备份。
	var healed: int = 0
	for p: String in WATCHED_PATHS:
		var bk := BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			_del(p)
			DirAccess.copy_absolute(_abs(bk), _abs(p))
			DirAccess.remove_absolute(_abs(bk))
			healed += 1
	if healed > 0:
		print("EVID|selfheal|w_save_domain|restored=%d" % healed)

func _backup_user() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		_pre_save_text = _read_file(SAVE_PATH)
	for p: String in WATCHED_PATHS:
		if FileAccess.file_exists(p):
			var bk := BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_abs(p), _abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	## 规范第 2 条：所有退出路径统一收口还原；还原后真实 autoload load_game 重同步内存。
	for p: String in WATCHED_PATHS:
		_del(p)
		var bk := BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_abs(bk), _abs(p))
			DirAccess.remove_absolute(_abs(bk))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()  # 防进程退出 close_requested → save_game 把测试态写回真实档案
	var post: String = _read_file(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|w_save_domain|files=%d" % WATCHED_PATHS.size())

func _new_sm() -> Node:
	## 独立实例先例（test_v_save_domain/test_w_save_resilience）：--script 无头 autoload _ready
	## 不触发，add_child 后显式 load_game 初始化 _data。
	_sm_seq += 1
	var sm: Node = (load(SM_SCRIPT) as GDScript).new()
	sm.name = "SM_W2_%d" % _sm_seq
	get_root().add_child(sm)
	sm.load_game()
	return sm

## 控制命令监听（9878，test_v_camera_menu 段 G 夹具形态）：收 ensure_camera_open 发出的命令串。
func _ctrl_listener() -> PacketPeerUDP:
	var l := PacketPeerUDP.new()
	l.bind(9878)
	return l

func _drain(l: PacketPeerUDP) -> void:
	while l.get_available_packet_count() > 0:
		l.get_packet()

func _recv_cmds(l: PacketPeerUDP) -> Array:
	var out: Array = []
	while l.get_available_packet_count() > 0:
		out.append(l.get_packet().get_string_from_utf8())
	return out

func _wait_available(l: PacketPeerUDP, frames: int) -> void:
	for i: int in frames:
		if l.get_available_packet_count() > 0:
			return
		await process_frame

func _initialize() -> void:
	print("== test_w_save_domain（批次 W2：P2-3a/P2-3b/P2-3c/N10/支撑项） ==")
	_selfheal_previous_backup()
	_backup_user()
	for p: String in WATCHED_PATHS:
		_del(p)  # 沙盒基线：真实档案已备份，测试域内四件全清

	var save: Node = get_root().get_node("SaveManager")
	save.load_game()  # --script 模式显式初始化（test_gesture_bridge_ports 先例）

	await _a_udp_port_single_source(save)
	await _b_camera_memory_by_name(save)
	await _c_reset_keeps_settings()
	await _d_camera_keys_save_immediately(save)
	await _e_intentionally_released_api()
	# 收口前复位测试态（还原组逐字节等价兜底）
	save.update_settings({"gesture_camera_device": "", "gesture_camera_res": "", "gesture_camera_fps": 0})
	_restore_user()
	finish()

# ================= 段 A（P2-3a）：udp_port 单一真源 =================
func _a_udp_port_single_source(save: Node) -> void:
	var bridge: Node = (load(BR_SCRIPT) as GDScript).new()
	bridge.name = "GB_W2_A"
	get_root().add_child(bridge)
	# A1 基准：默认档（udp_port=0）→ 恒 9876
	check_eq(int(bridge.get_udp_port()), 9876, "A1：默认档 → 基准端口 9876（回归锚）")
	# A2 修复点：存档端口被改（旧档脏值/历史遗留场景）→ 桥仍恒 9876（红：旧实现读存档返回 9999）
	save.update_settings({"udp_port": 9999})
	check_eq(int(bridge.get_udp_port()), 9876,
		"A2：存档 udp_port=9999 → 桥仍绑 9876（P2-3a 常量派生单一真源，不再消费存档）")
	check_eq(int(bridge.get_frame_port()), 9877, "A3：JPEG=P+1=9877（派生不变）")
	check_eq(int(bridge.get_control_port()), 9878, "A4：控制=P+2=9878（派生不变）")
	# A5 存档键不删不迁移：磁盘档仍保留 udp_port 键（deprecated 留痕语义）
	var disk: Dictionary = _disk_save()
	var s_disk: Variant = disk.get("settings", null)
	check(typeof(s_disk) == TYPE_DICTIONARY and int((s_disk as Dictionary).get("udp_port", -1)) == 9999,
		"A5：存档键 udp_port 保留不删（磁盘档含 9999，deprecated 仅退役消费）")
	# A6 源码证据链：get_udp_port 函数体不再读取存档 settings（消费退役源码级锁定）
	var src: String = _read_file(BR_SCRIPT)
	var f0: int = src.find("func get_udp_port(")
	var f1: int = src.find("func get_frame_port(")
	var body := src.substr(f0, f1 - f0) if f0 >= 0 and f1 > f0 else ""
	check(body != "" and not body.contains("udp_port\"") and not body.contains("get_settings"),
		"A6：get_udp_port 函数体零存档消费（源码证据链，P2-3a 退役落点）")
	check(src.contains("const DEFAULT_UDP_PORT := 9876") and body.contains("DEFAULT_UDP_PORT"),
		"A7：常量 DEFAULT_UDP_PORT=9876 单源在场且 get_udp_port 恒返回之（源码证据链）")
	save.update_settings({"udp_port": 0})  # 复位测试态（还原组逐字节等价兜底）
	bridge.free()

# ================= 段 B（P2-3b 桥消费集成 + N10 恢复链路） =================
func _b_camera_memory_by_name(save: Node) -> void:
	var bridge: Node = (load(BR_SCRIPT) as GDScript).new()
	bridge.name = "GB_W2_B"
	get_root().add_child(bridge)
	bridge._simulate_start_ok = true   # 测试接缝（U4）：视 start 已成功，无头零 spawn
	var lsn := _ctrl_listener()
	# B1 修复点：记忆名档命中同名设备 id（红：旧实现按 int 解析非数字串得 -1 → 回落首设备）
	save.update_settings({"gesture_camera_device": "HD Camera", "gesture_camera_res": "", "gesture_camera_fps": 0})
	bridge._camera_enum = {"cameras": [{"id": 0, "name": "Cam A"}, {"id": 3, "name": "HD Camera"}], "current_camera": 0}
	_drain(lsn)
	bridge.ensure_camera_open()
	await _wait_available(lsn, 4)
	check(_recv_cmds(lsn).has("START_CAMERA_BY_NAME:HD Camera"),
		"B1（AD 等价改写）：记忆名「HD Camera」→ 逐字按名下发启动指令（旧断言为 SWITCH_CAMERA:3）")
	# B2 N10 恢复链路：记忆 res/fps 非空且设备命中 → SWITCH 后按序追发（含帧率记忆）
	save.update_settings({"gesture_camera_device": "HD Camera", "gesture_camera_res": "1280x720", "gesture_camera_fps": 30})
	_drain(lsn)
	bridge.ensure_camera_open()
	await _wait_available(lsn, 6)
	var b2 := _recv_cmds(lsn)
	var i_sw := b2.find("START_CAMERA_BY_NAME:HD Camera")
	var i_res := b2.find("SET_RESOLUTION:3:1280x720")
	var i_fps := b2.find("SET_FPS:3:30")
	check(i_sw >= 0 and i_res >= 0 and i_fps >= 0, "B2：N10 恢复链路——记忆 res/fps 按名字命中设备追发（实际 %s）" % [b2])
	check(i_sw < i_res and i_res < i_fps, "B3：追发序=启动指令→SET_RESOLUTION→SET_FPS（V17 串行语义保持）")
	# B4 spec 验收：注入旧档数字残留 "3"（枚举无 id 3）→ 旧 int 语义解释一次 → 不在枚举 → 回落首可用设备
	# 批次 W4-N9 等价改写（W6 回归甄别）：ensure 的 no-op 门（READY/LOADING ∧ 目标==当前，
	# 跨场景去重发）会拦下「回落目标==current_camera」的同目标重发——本段回落解析正确性改自
	# UNAVAILABLE 态驱动（RELEASE 后 Q1 重开语义：门旁路、全链照发）；no-op 本体由 B9 锁定。
	save.update_settings({"gesture_camera_device": "3", "gesture_camera_res": "", "gesture_camera_fps": 0})
	bridge._camera_enum = {"cameras": [{"id": 0, "name": "Cam A"}, {"id": 1, "name": "Cam B"}], "current_camera": 0}
	bridge._set_state(2)   # UNAVAILABLE（旁路 N9 no-op 门；非主动关，门只拦 READY/LOADING 同目标）
	_drain(lsn)
	bridge.ensure_camera_open()
	await _wait_available(lsn, 4)
	check(_recv_cmds(lsn).has("START_CAMERA_BY_NAME:3"),
		"B4（AD 等价改写）：数字残留不再按 CAP 索引解释 → 按名原样下发（降级首项下沉 Python；旧断言为 SWITCH_CAMERA:0）")
	# B5 旧数字残留命中：枚举含 id 1 → 按旧语义解释命中（兼容语义回归锚）
	save.update_settings({"gesture_camera_device": "1"})
	_drain(lsn)
	bridge.ensure_camera_open()
	await _wait_available(lsn, 4)
	check(_recv_cmds(lsn).has("START_CAMERA_BY_NAME:1"),
		"B5（AD 等价改写）：数字残留按名原样下发（数字语义退役，绝不命中 CAP 索引；旧断言为 SWITCH_CAMERA:1）")
	# B6 记忆名不在枚举 → 回落首设备 + 不追发 res/fps（防跨设备串值，V17 G6 语义等价迁移；
	# 同 B4：UNAVAILABLE 态驱动旁路 N9 no-op 门——回落目标==current 时 READY/LOADING 态被
	# 跨场景去重发拦截属正确语义，命令级验证走 UNAVAILABLE 旁路）
	save.update_settings({"gesture_camera_device": "Ghost Cam", "gesture_camera_res": "640x480", "gesture_camera_fps": 30})
	bridge._set_state(2)
	_drain(lsn)
	bridge.ensure_camera_open()
	await _wait_available(lsn, 6)
	var b6 := _recv_cmds(lsn)
	check(b6.has("START_CAMERA_BY_NAME:Ghost Cam"), "B6（AD 等价改写）：记忆名不在枚举 → 按名原样下发（降级首项下沉 Python；实际 %s）" % [b6])
	var b6_bad := false
	for cmd: String in b6:
		if cmd.begins_with("SET_RESOLUTION") or cmd.begins_with("SET_FPS"):
			b6_bad = true
	check(not b6_bad, "B7：已记忆但未命中 → 不追发 res/fps（防跨设备串值，V17 语义等价迁移）")
	# B8 枚举缓存空 → 批次 AC 等价改写（2026-09-27，spec §4.2-3/D2）：旧口径「回落 0 盲发
	# SWITCH_CAMERA:0」= 实机盲开 CAP 0 荣耀 Magic7（手机弹窗根因），批次 AC 拍板废止。
	# 新口径：枚举未达 → 零 SWITCH + GET_CAMERAS 拉取 + 握手重武装；记忆照旧保留
	#（init#1 到达后由 _handle_meta 按记忆名/非手机首项开启）。断言数 1→3 只增不减。
	save.update_settings({"gesture_camera_device": "HD Camera"})
	bridge._camera_enum = {}
	bridge._last_enum_request_ms = -1000000
	bridge._preferred_handshake_armed = false
	bridge._set_state(2)
	_drain(lsn)
	bridge.ensure_camera_open()
	await _wait_available(lsn, 4)
	var b8 := _recv_cmds(lsn)
	var b8_sw := 0
	var b8_sc := 0
	for cmd: String in b8:
		if cmd.begins_with("SWITCH_CAMERA"):
			b8_sw += 1
		if cmd.begins_with("START_CAMERA_BY_NAME"):
			b8_sc += 1
	check_eq(b8_sw, 0, "AC/AD 等价替换（旧 B8「回落 0」）：枚举缓存空 → 零盲发 SWITCH_CAMERA（实际 %s）" % [b8])
	check_eq(b8_sc, 0, "AD：枚举缓存空 → 零启动指令盲发（待 init#1；实际 %s）" % [b8])
	check(b8.has("GET_CAMERAS"), "AC：枚举缓存空 → GET_CAMERAS 拉取（实际 %s）" % [b8])
	check(str(bridge.get("_preferred_handshake_armed")) == "true",
		"AC：枚举缓存空 → 握手重新武装（旧回落链废止后的官方路径）")
	# B9（W4-N9 语义锁定，W6 回归甄别补）：READY + 回落目标==当前设备 → ensure no-op 零命令
	#（跨场景去重发——B4-B8 命令级断言自 UNAVAILABLE 旁路驱动，两态语义互补成对锁定）
	# 批次 Y（Y-A18）等价注入：no-op 门以「摄像头流开启真值」判定——注入流已开（单元级直写）
	bridge._set_state(1)   # READY
	bridge.set("camera_stream_open", true)
	save.update_settings({"gesture_camera_device": "Cam A", "gesture_camera_res": "", "gesture_camera_fps": 0})
	bridge._camera_enum = {"cameras": [{"id": 0, "name": "Cam A"}, {"id": 1, "name": "Cam B"}], "current_camera": 0}
	# 批次 AC：B8 武装过握手（枚举未达路径），本段判据=no-op 门零命令——先解除武装，
	# 防 _process tick 的握手重发混入命令计数（隔离注入，判据纯粹）。
	bridge.set("_preferred_handshake_armed", false)
	bridge.set("_preferred_next_at_ms", -1)
	_drain(lsn)
	bridge.ensure_camera_open()
	await _wait_available(lsn, 4)
	check(_recv_cmds(lsn).is_empty(), "B9：READY+回落目标==当前 → ensure no-op 零命令（W4-N9 跨场景去重发）")
	lsn.close()
	bridge.free()

# ================= 段 C（P2-3c）：reset_for_new_game 保留 settings 域 =================
func _c_reset_keeps_settings() -> void:
	var sm: Node = _new_sm()
	sm.update_settings({"volume": {"master": 0.37}, "gesture_camera_device": "HD Camera"})
	sm.mark_first_launch()  # 预置 flag（reset 既有删标记语义回归锚）
	# 预置进度/皮肤偏移（复位断言基准）
	var p: Dictionary = sm.get_progress()
	(p["cleared"] as Array).append(3)
	sm.get_skins()["preferred"] = "skin_default"
	sm.add_talent(50)
	var settings_ref: Dictionary = sm.get_settings()  # 引用捕获（is_same 判据）
	var sig_count: Array = []                          # lambda 计数（坑 8：成员容器）
	sm.settings_changed.connect(func() -> void: sig_count.append(1))
	sm.reset_for_new_game()
	check(is_same(sm.get_settings(), settings_ref),
		"C1：reset 后 settings 键原引用保留（is_same；红：旧实现 _data=_default_data() 整体重建）")
	check_eq(float((sm.get_settings()["volume"] as Dictionary).get("master", -1.0)), 0.37,
		"C2：音量不变（新游戏不清设置——用户反馈根因）")
	check_eq(String(sm.get_settings().get("gesture_camera_device", "")), "HD Camera",
		"C3：摄像头设备记忆保留")
	check_eq(sig_count.size(), 0, "C4：不发 settings_changed（音频不重应用；update_settings 合并语义多余）")
	check_eq(sm.get_talent(), 500, "C5：talent 复位默认 500")
	check_eq((sm.get_progress()["cleared"] as Array), [], "C6：progress.cleared 复位（进度域照旧重置）")
	check_eq((sm.get_progress()["level_progress"] as Dictionary), {}, "C7：level_progress 复位空（N9-A22 等价锚）")
	check_eq(String(sm.get_skins().get("preferred", "")), "skin_origin_kaitou",
		"C8：skins 复位默认（preferred=开头原创）")
	check(sm.is_first_launch(), "C9：first_launch 标记已删除（is_first_launch 回 true，既有语义回归锚）")
	# C10 落盘混合档：磁盘 save.json 含保留音量 + 复位进度
	var disk: Dictionary = _disk_save()
	var s_disk: Variant = disk.get("settings", null)
	var p_disk: Variant = disk.get("progress", null)
	check(typeof(s_disk) == TYPE_DICTIONARY
		and float((s_disk as Dictionary).get("volume", {}).get("master", -1.0)) == 0.37,
		"C10：落盘档 settings 含保留音量 0.37（混合档落盘）")
	check(typeof(p_disk) == TYPE_DICTIONARY and ((p_disk as Dictionary).get("cleared", [9]) as Array).is_empty(),
		"C11：落盘档 progress.cleared 已复位空")
	# C12 未来版本只读锁共存：锁存时 reset 不落盘（W1 P2-2 语义不回归——锁存跳过 flag 删除保持）
	sm2_lock_check()
	sm.free()

func sm2_lock_check() -> void:
	## C12：锁存时 reset_for_new_game 的 settings 保留逻辑与 W1 只读锁共存（零写盘零删 flag）。
	var sm: Node = _new_sm()
	sm.update_settings({"volume": {"master": 0.5}})
	sm.mark_first_launch()
	sm.set("_future_readonly", true)  # 注入锁存（W1 P0-8；_data 保持已载内存态）
	var pre: String = _read_file(SAVE_PATH)
	sm.reset_for_new_game()
	check_eq(_read_file(SAVE_PATH), pre, "C12：锁存时 reset 零写盘（W1 P0-6④ 断言等价复验）")
	check(FileAccess.file_exists(FLAG_PATH), "C13：锁存时 reset 不删 first_launch.flag（W1 P2-2 不回归）")
	sm.set("_future_readonly", false)
	sm.free()

# ================= 段 D（N10）：摄像头三键即改即存 + 重启恢复读回 =================
func _d_camera_keys_save_immediately(save: Node) -> void:
	# D1 三键 update_settings 后磁盘档即时含值（即改即存——V17 写档路径 + 设备键=名字新契约）
	save.update_settings({"gesture_camera_device": "HD Camera", "gesture_camera_res": "1280x720", "gesture_camera_fps": 30})
	var disk: Dictionary = _disk_save()
	var s_disk: Variant = disk.get("settings", null)
	var ok1: bool = typeof(s_disk) == TYPE_DICTIONARY
	if ok1:
		var sd: Dictionary = s_disk
		ok1 = String(sd.get("gesture_camera_device", "")) == "HD Camera" \
			and String(sd.get("gesture_camera_res", "")) == "1280x720" \
			and int(sd.get("gesture_camera_fps", -1)) == 30
	check(ok1, "D1：三键改后 save.json 即时含值（device=名字/res/fps；红期 res/fps 无既有写点不完整）")
	# D2 重启恢复：新实例 load_game 无损读回（JSON float→int 归一后 fps==30）
	var sm2: Node = _new_sm()
	check_eq(String(sm2.get_settings().get("gesture_camera_device", "")), "HD Camera", "D2：重启读回设备名无损")
	check_eq(String(sm2.get_settings().get("gesture_camera_res", "")), "1280x720", "D3：重启读回分辨率无损")
	check_eq(int(sm2.get_settings().get("gesture_camera_fps", -1)), 30, "D4：重启读回帧率（float→int 归一）")
	sm2.free()

# ================= 段 E（支撑项）：桥只读态 API =================
func _e_intentionally_released_api() -> void:
	var bridge: Node = (load(BR_SCRIPT) as GDScript).new()
	bridge.name = "GB_W2_E"
	get_root().add_child(bridge)
	# 红期防挂死（坑⑪同族，test_w_save_resilience _lock_of 先例）：方法未实现时记失败提前收口，
	# 不触发未定义方法调用中止（--script 无头运行期 Missing method 报错即中止调用函数）。
	if not bridge.has_method("is_camera_intentionally_released"):
		check(false, "E0：is_camera_intentionally_released 只读态 API 存在（红）")
		bridge.free()
		return
	check(true, "E0：is_camera_intentionally_released 只读态 API 存在")
	# E1 未置位 → false
	check_eq(bool(bridge.is_camera_intentionally_released()), false, "E1：未主动关 → 查询 false")
	# E2 置位（request_camera_release 生产路径）→ 恒真（连查两次不消费）
	bridge.request_camera_release()
	check_eq(bool(bridge.is_camera_intentionally_released()), true, "E2：置位 → 查询 true")
	check_eq(bool(bridge.is_camera_intentionally_released()), true, "E3：只读查询不消费标志（二次仍 true）")
	# E4 start_gesture_process 入口清标志 → 查询转 false（无头 start 返回 false 但入口清零先行）
	bridge.start_gesture_process()
	check_eq(bool(bridge.is_camera_intentionally_released()), false, "E4：start 后查询 false（N5 按钮态判据源）")
	# E5 consume 一次性语义不变（S13 回归锚）
	bridge._intentional_stop = true
	check_eq(bool(bridge.consume_intentional_stop()), true, "E5：consume 取走=true（一次性语义不变）")
	check_eq(bool(bridge.consume_intentional_stop()), false, "E6：consume 二次=false（取走即清）")
	check_eq(bool(bridge.is_camera_intentionally_released()), false, "E7：consume 后查询 false（一致性）")
	bridge.free()
