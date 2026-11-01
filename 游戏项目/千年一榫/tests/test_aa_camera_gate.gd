extends "res://tests/test_base.gd"
## 批次 AA 终审回修波（aarev）红测四件（TDD 先红后绿；无头零摄像头零真 spawn）：
##   段 A/B/C/D/E（回修1 P1-1 摄像头设置门）：Q3（gesture_input=false ∧ gesture_camera_enabled=false，
##     键名以 SaveManager settings 域实读为准）下——
##     A: UNAVAILABLE 自愈重拉分支零 _spawn 调用（hook 计数替身；改前=1 红）；
##     B: _ensure_preferred_camera_restore 零 SWITCH_CAMERA + ensure_camera_open 全 no-op
##        （return false / 零 SWITCH / 不清 release 意图锁存；改前=发 SWITCH 红）；
##     C: Q3 启动显式 RELEASE_CAMERA 恰一次（_q3_release_camera_once + 会话内哨兵；改前缺方法红）；
##     D/E: Q1/Q2（任一开）反向护栏——spawn 尝试 / 恢复 SWITCH / ensure SWITCH 照常（防改过头）。
##   段 F（回修2 P1-2 TopStrip 进店偏移）：条已存在（MAIN_MENU 偏移 70）→ Game.open_overlay("shop")
##     → 条顶下移 ≥96（商店顶排三件占 y∈[16,90]，96>90 结构零相交；改前=70 红）；关店回落 70；
##     settings overlay 不误改偏移（反向护栏）。
##   段 G（回修3 P3-1 退出噪声守卫）：Router 不在树内时 _on_bridge_state_for_reset 首行早退
##     （_prev_bridge_state 不被改写=守卫生效行为证据，改前=被改写红；根因=树外绝对路径
##     get_node_or_null 触发引擎 ERROR 噪声，早退后 get_node 不再触达）。
## 夹具纪律：自有桥实例走高位 override 端口（20300 段位，与真实 9876/9877/9878 及其他测试零交集）；
##   子类覆写 _probe_python_ready（bind 探测 mock）；_spawn_hook 计数替身（绝不真 spawn）；
##   user:// 四件组备份-还原（前缀 aacg，终态逐字节等价断言）；
##   坑 1/坑 10：成员取值经 Variant 判空（_member_true/_member_int），红态不崩不挂死。

const BR_SCRIPT := "res://autoload/gesture_bridge.gd"
const TS_SCRIPT := "res://scenes/shared/top_strip.gd"
const RT_SCRIPT := "res://autoload/gesture_router.gd"

# 高位端口段位（20300 段；sniffer 绑 override+2；与其他测试 20280~20294 段零交集）
const PORT_AUTO := 20300   # 真实 autoload 桥隔离（防生产端口触碰）
const PORT_A := 20310      # 段A Q3 spawn 零
const PORT_B := 20312      # 段B Q3 restore/ensure 零（sniffer 20314）
const PORT_C := 20316      # 段C RELEASE 恰一次（sniffer 20318）
const PORT_D := 20320      # 段D Q1 spawn 反向
const PORT_E := 20322      # 段E Q2 restore/ensure 反向（sniffer 20324）

# ===== 清档纪律（aacm 同款，前缀 aacg）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_aacg_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
var _pre_save_text: String = ""
var _sniffers: Array = []

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _backup_user() -> void:
	for p0: String in DISC_WATCHED:
		var bk0: String = DISC_BK_PREFIX + p0.get_file()
		if FileAccess.file_exists(_disc_abs(bk0)):
			if FileAccess.file_exists(_disc_abs(p0)):
				DirAccess.remove_absolute(_disc_abs(p0))
			DirAccess.copy_absolute(_disc_abs(bk0), _disc_abs(p0))
			DirAccess.remove_absolute(bk0)
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

## 源函数体切片（func 名 → 到下一个顶层 "\nfunc " 为止；源锚断言用）
func _fn_body(src: String, fname: String) -> String:
	var i: int = src.find("func %s(" % fname)
	if i < 0:
		return ""
	var nxt: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (nxt - i) if nxt > i else src.length() - i)

## 成员布尔/整型读防御（坑 1：bool(null) 中止 _initialize——红态成员缺失不崩）
func _member_true(o: Object, member: String) -> bool:
	return str(o.get(member)) == "true"
func _member_int(o: Object, member: String) -> int:
	var v: Variant = o.get(member)
	if v == null:
		return 0
	return int(v)

## 9878(override+2) 回环监听（test_aa_camera_lifecycle CtrlSniffer 同款）
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

## Q1~Q3 四象限设置一键写档（SaveManager settings 域实键名）
func _set_quadrant(save: Node, gesture_on: bool, camera_on: bool) -> void:
	save.call("update_settings", {"gesture_input": gesture_on, "gesture_camera_enabled": camera_on})

## spawn 计数 hook（返回 false=不真拉起，仅计数）
func _hook(counter: Dictionary) -> Callable:
	return func() -> bool:
		counter["n"] = int(counter.get("n", 0)) + 1
		return false

func _initialize() -> void:
	print("== test_aa_camera_gate ==")
	_backup_user()
	var save: Node = get_root().get_node("SaveManager")
	check(save != null, "前置：SaveManager 在位")
	if save == null:
		finish()
		return
	# 真实 autoload 桥端口隔离（防本测试任何路径触碰生产端口 9876/9877/9878）
	var gb_auto: Node = get_root().get_node("GestureBridge")
	gb_auto.set("_udp_port_override", PORT_AUTO)

	# 探针子类：_probe_python_ready 可注入（bind 探测 mock；绝不真探测真实端口）
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
	check_eq(reload_err, 0, "前置：桥测试子类编译成功")
	if reload_err != int(OK):
		finish()
		return

	# ================= 段 A（回修1-A）：Q3 下 UNAVAILABLE 自愈重拉零 _spawn =================
	_set_quadrant(save, false, false)   # Q3 双关
	var st_a: Dictionary = save.call("get_settings")
	check(bool(st_a.get("gesture_input", true)) == false and bool(st_a.get("gesture_camera_enabled", true)) == false,
		"段A 前置：Q3（双关）已在 SaveManager settings 生效")
	var br_a: Node = sub.new()
	br_a.set("_udp_port_override", PORT_A)
	add_child(br_a)
	await process_frame
	var cnt_a := {"n": 0}
	br_a.set("probe_ret", false)          # python 不在 → UNAVAILABLE 互补分支（真死重拉）
	br_a.set("_spawn_hook", _hook(cnt_a))
	br_a.call("_set_state", 2)            # UNAVAILABLE（等价 LOADING 超时判死后态）
	br_a.set("_last_retry_at", -1000.0)   # 重试周期立即到点
	br_a.call("_process", 0.016)
	check_eq(int(cnt_a.get("n", 0)), 0,
		"回修1/A1：Q3（双关）下自愈重拉分支零 _spawn 调用（改前=1，红；实测 %d）" % int(cnt_a.get("n", 0)))
	check_eq(int(br_a.call("get_load_state")), 2, "回修1/A2：spawn 被门后状态保持 UNAVAILABLE（不假死 READY）")
	var bsrc: String = FileAccess.get_file_as_string(BR_SCRIPT)
	check(_fn_body(bsrc, "_spawn").contains("_settings_allow_camera"),
		"回修1/A3：源锚——_spawn 漏斗首行含设置门（单一真值判定）")
	check(_fn_body(bsrc, "start_gesture_process").contains("_settings_allow_camera"),
		"回修1/A4：源锚——start_gesture_process 首行含设置门（covers camera_menu 预热等直调路径）")

	# ================= 段 B（回修1-B）：Q3 下恢复/ensure 全 no-op =================
	save.call("update_settings", {"gesture_camera_device": "HD"})   # 记忆设备（Q3 仍在档）
	var br_b: Node = sub.new()
	br_b.set("_udp_port_override", PORT_B)
	add_child(br_b)
	await process_frame
	var snif_b := CtrlSniffer.new()
	_sniffers.append(snif_b)
	check_eq(int(snif_b.bind(PORT_B + 2)), 0, "段B 前置：控制端口抓包器就位")
	br_b.set("probe_ret", true)   # 打包形态「python 常驻」语义（ensure 短路判据需 probe ready）
	br_b.set("_camera_release_intent", false)
	br_b.set("_camera_enum", {"cameras": [{"id": 0, "name": "Magic7"}, {"id": 2, "name": "HD"}], "current_camera": 0})
	br_b.set("camera_stream_open", false)
	br_b.set("camera_stream_device_id", -1)
	br_b.set("_preferred_restore_last_ms", -1000000)
	br_b.set("last_switch_camera_id", -1)
	br_b.call("_ensure_preferred_camera_restore")
	check_eq(snif_b.count_prefix("SWITCH_CAMERA"), 0,
		"回修1/B1：Q3（摄像头关）下恢复路径零 SWITCH_CAMERA（改前=1，红；实测 %d）" % snif_b.count_prefix("SWITCH_CAMERA"))
	check_eq(int(br_b.get("last_switch_camera_id")), -1, "回修1/B1b：恢复路径未写 last_switch_camera_id")
	br_b.set("_camera_release_intent", true)   # 模拟「用户已主动关」锁存在位
	var ok_b: bool = bool(br_b.call("ensure_camera_open"))
	check_eq(ok_b, false, "回修1/B2：Q3 下 ensure_camera_open 直接 false（改前=true，红）")
	check_eq(snif_b.count_prefix("SWITCH_CAMERA"), 0,
		"回修1/B2b：Q3 下 ensure 零 SWITCH 副作用（改前=发 SWITCH，红）")
	check(_member_true(br_b, "_camera_release_intent"),
		"回修1/B3：被门 ensure 不清 release 意图锁存（门在清锁存之前早退）")
	check(_fn_body(bsrc, "_ensure_preferred_camera_restore").contains("_settings_allow_camera"),
		"回修1/B4：源锚——_ensure_preferred_camera_restore 首行含设置门")
	check(_fn_body(bsrc, "ensure_camera_open").contains("_settings_allow_camera"),
		"回修1/B5：源锚——ensure_camera_open 首行含设置门")

	# ================= 段 C（回修1-C）：Q3 启动 RELEASE_CAMERA 恰一次 =================
	var br_c: Node = sub.new()
	br_c.set("_udp_port_override", PORT_C)
	add_child(br_c)
	await process_frame   # _ready 已随入树触发（Q3 在档 → 自动首发；监听未挂=包丢弃，不影响计数）
	var snif_c := CtrlSniffer.new()
	_sniffers.append(snif_c)
	check_eq(int(snif_c.bind(PORT_C + 2)), 0, "段C 前置：控制端口抓包器就位")
	if br_c.has_method("_q3_release_camera_once"):
		br_c.set("_q3_release_sent", false)   # 复位哨兵（_ready 期首发未被监听，此处直测方法语义）
		br_c.call("_q3_release_camera_once")
		check_eq(snif_c.count_prefix("RELEASE_CAMERA"), 1,
			"回修1/C1：Q3 启动 RELEASE_CAMERA 恰一次（改前缺方法，红；实测 %d）" % snif_c.count_prefix("RELEASE_CAMERA"))
		br_c.call("_q3_release_camera_once")
		check_eq(snif_c.count_prefix("RELEASE_CAMERA"), 1, "回修1/C2：重复调用仍恰一次（会话内哨兵）")
		check(_fn_body(bsrc, "_ready").contains("_q3_release_camera_once"),
			"回修1/C3：源锚——_ready 尾部接入启动兜底（Q3 跨重启释放）")
	else:
		check(false, "回修1/C1：_q3_release_camera_once 方法缺失（红）")
		check(false, "回修1/C3：_ready 未接入启动兜底（红）")

	# ================= 段 D（回修1-D）：Q1 反向护栏——spawn 照常 =================
	_set_quadrant(save, true, false)   # Q1（手势开，摄像头关）
	var br_d: Node = sub.new()
	br_d.set("_udp_port_override", PORT_D)
	add_child(br_d)
	await process_frame
	var cnt_d := {"n": 0}
	br_d.set("probe_ret", false)
	br_d.set("_spawn_hook", _hook(cnt_d))
	br_d.call("_set_state", 2)
	br_d.set("_last_retry_at", -1000.0)
	br_d.call("_process", 0.016)
	check_eq(int(cnt_d.get("n", 0)), 1,
		"回修1/D1：Q1（任一开）反向护栏——自愈重拉 spawn 尝试恰 1（防改过头；实测 %d）" % int(cnt_d.get("n", 0)))

	# ================= 段 E（回修1-E）：Q2 反向护栏——恢复/ensure SWITCH 照常 =================
	_set_quadrant(save, false, true)   # Q2（手势关，摄像头开）
	save.call("update_settings", {"gesture_camera_device": "HD"})
	var br_e: Node = sub.new()
	br_e.set("_udp_port_override", PORT_E)
	add_child(br_e)
	await process_frame
	var snif_e := CtrlSniffer.new()
	_sniffers.append(snif_e)
	check_eq(int(snif_e.bind(PORT_E + 2)), 0, "段E 前置：控制端口抓包器就位")
	br_e.set("probe_ret", true)
	br_e.set("_camera_release_intent", false)
	br_e.set("_camera_enum", {"cameras": [{"id": 0, "name": "Magic7"}, {"id": 2, "name": "HD"}], "current_camera": 0})
	br_e.set("camera_stream_open", false)
	br_e.set("camera_stream_device_id", -1)
	br_e.set("_preferred_restore_last_ms", -1000000)
	br_e.set("last_switch_camera_id", -1)
	br_e.call("_ensure_preferred_camera_restore")
	check_eq(snif_e.count_prefix("START_CAMERA_BY_NAME:HD"), 1,
		"回修1/E1（AD 等价改写）：Q2（摄像头开）反向护栏——恢复按名下发启动指令照发（防改过头；实测 %d）" % snif_e.count_prefix("START_CAMERA_BY_NAME:HD"))
	br_e.set("_simulate_start_ok", true)
	br_e.set("last_switch_camera_id", -1)
	var ok_e: bool = bool(br_e.call("ensure_camera_open"))
	check_eq(ok_e, true, "回修1/E2 前置：Q2 ensure 返回 true")
	check(snif_e.has_cmd("START_CAMERA_BY_NAME:HD"), "回修1/E2（AD 等价改写）：Q2 ensure 按名下发启动指令照发（防改过头）")

	# ================= 段 F（回修2）：TopStrip 条已存在 → 进店重算偏移 =================
	_set_quadrant(save, true, true)   # 复位默认（后续设置面板打开走 Q1 安全线）
	var game: Node = get_root().get_node("Game")
	check(game != null, "段F 前置：Game 在位")
	game.call("close_overlay")
	var ol := CanvasLayer.new()
	ol.name = "AacgOverlayLayer"
	root.add_child(ol)
	game.set("_overlay_layer", ol)   # 无头未 attach：注入覆盖层容器（test_aa_dock_placement 同款）
	var strip: Node = (load(TS_SCRIPT) as GDScript).new()
	add_child(strip)
	await process_frame
	await process_frame
	strip.call("push_info", "回修2红测条", 30.0)
	# 入场滑入 0.25s tween 期间 position.y 逐帧反写 offset_top（test_v_top_strip 0.5s 等待同款
	# 口径）——几何断言前放行动画时长，否则读到飞行中值（红测首轮实证 4.59/7.5）。
	await create_timer(0.5).timeout
	check_eq(float(strip.get("offset_top")), 70.0, "回修2/F1 前置：MAIN_MENU（无覆盖层）条顶 70")
	game.call("open_overlay", "shop")   # 条已存在时进店（回修2 病灶场景）
	await process_frame
	var off_f: float = float(strip.get("offset_top"))
	check(off_f >= 96.0,
		"回修2/F2：条已存在→进店后条顶下移 ≥96（SHOP_TOP_OFFSET；改前=70 红；实测 %.1f）" % off_f)
	var band := Rect2(0.0, 16.0, strip.get_viewport_rect().size.x, 74.0)   # 商店顶排三件占带 y∈[16,90]
	var srect := Rect2(strip.global_position, strip.size)
	check(not srect.intersects(band),
		"回修2/F3：条与商店顶排三件零相交（条顶 y=%.1f > 90）" % strip.global_position.y)
	game.call("close_overlay")
	await process_frame
	check_eq(float(strip.get("offset_top")), 70.0, "回修2/F4：关店回落 70（overlay_changed(false) 重算）")
	game.call("open_overlay", "settings")
	await process_frame
	check_eq(float(strip.get("offset_top")), 70.0, "回修2/F5：settings overlay 不改偏移（反向护栏）")
	game.call("close_overlay")
	await process_frame

	# ================= 段 G（回修3）：Router 树外早退守卫 =================
	var router: Node = (load(RT_SCRIPT) as GDScript).new()
	add_child(router)
	await process_frame
	router.set("_prev_bridge_state", -1)
	router.call("_on_bridge_state_for_reset", 1)   # LOADING：树内记账路径
	check_eq(_member_int(router, "_prev_bridge_state"), 1, "回修3/G1 前置：树内调用状态记账正常")
	root.remove_child(router)   # 模拟退出期树已拆（_exit_tree 后回调仍可达的时序）
	router.call("_on_bridge_state_for_reset", 2)   # UNAVAILABLE：树外调用（退出期真实形态）
	check_eq(_member_int(router, "_prev_bridge_state"), 1,
		"回修3/G2：不在树内首行早退（_prev_bridge_state 不被改写；改前=2 红）")
	var rsrc: String = FileAccess.get_file_as_string(RT_SCRIPT)
	check(_fn_body(rsrc, "_on_bridge_state_for_reset").contains("is_inside_tree"),
		"回修3/G3：源锚——_on_bridge_state_for_reset 首行含 is_inside_tree 守卫（树外零 get_node 绝对路径触达）")
	router.free()

	finish()

func finish() -> void:
	for s: Variant in _sniffers:
		if s is PacketPeerUDP:
			(s as PacketPeerUDP).close()
	for c: Node in root.get_children():
		if not ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager", "GestureBridge",
				"LevelLibrary", "Game", "GestureRouter", "I18n"].has(String(c.name)):
			c.free()
	_restore_user()
	super.finish()
