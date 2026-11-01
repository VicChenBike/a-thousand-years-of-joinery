extends "res://tests/test_base.gd"
## 批次 Y Y2（2026-09-22 规格 §2 Y-A17/Y-A18/Y-A19/Y-A20/㉓/㉔）——设置面板摄像头按钮
## 真值驱动重构 TDD 红测先行。段口径：
##   A（Y-A17）：OPENING 收口一律以「摄像头流开启真值」为准——READY 边沿不再收口亮
##     （假死 READY 永亮根除），camera_opened 事件到达才收口转亮；
##   B（Y-A18+批次 Z Z4-④ 等价改写）：OPENING 8s 超时/相机错误终态——超时即重拉枚举+
##     失败收口退出 OPENING（回落切设备抢句柄路径退役：attempt 零迁移、零「已切换到」谎报；
##     camera_error 命中目标→收口、非命中→仅提示保持 OPENING），不永挂「打开中…」；
##   C（㉔/Y-A17）：「无法关闭」info 收窄到流真实开启——假死 READY 点按=打开（进 OPENING），
##     流开点按才 info；文案逐字不变（批次V规格§3.3① 单源保留）；
##   D（㉓/Y-A23）：非打开中期 camera_error（切换设备失败）toast 文案与事实一致
##     「摄像头切换失败，可稍后重试」（旧「未能重新打开」错位废止）；
##   E（Y-A19）：Q3→Q2 解禁通路——手势关+摄像头关钮恒可点（0 摄像头除外），
##     点按单开摄像头（Q2 分支 ensure 序）；
##   F（Y-A20）：0 摄像头确认 → 手势交互/摄像头两按钮 disabled 置灰+提示条；
##     重枚举到设备自动恢复可点。
## 清档纪律：user:// 备份还原（前缀 yscf）；零摄像头纪律：全程无头不真拉起。

const PANEL_SCENE := "res://scenes/settings/settings_panel.tscn"
const SAVE_PATH := "user://save.json"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"
const BK_PREFIX := "user://_yscf_backup_"
const WATCHED: Array = [SAVE_PATH, TMP_PATH, BAK_PATH]
const INFO_TEXT := "手势交互需要摄像头，无法关闭"
const SWITCH_FAIL_TOAST := "摄像头切换失败，可稍后重试"
const ZERO_CAM_INFO := "未检测到摄像头，手势交互无法使用"
const CAM_OPEN_FAIL_TOAST := "摄像头打开失败，请检查设备后重试"

## TopStrip 替身（test_v_settings_camera_flow 同款）：记录 push_info/push_confirm/toast 改道
class StripSpy extends Node:
	var info_calls: Array = []
	var confirm_calls: Array = []
	func push_info(text: String, seconds: float = 3.0) -> void:
		info_calls.append([text, seconds])
	func push_confirm(text: String, on_confirmed: Callable = Callable(),
			on_canceled: Callable = Callable()) -> void:
		confirm_calls.append([text, on_confirmed, on_canceled])

var _bridge: Node = null
var _save: Node = null
var _game: Node = null
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
	_save.call("load_game")

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

func _make_panel() -> Node:
	var panel: Node = (load(PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await process_frame
	await process_frame
	return panel

func _initialize() -> void:
	print("== test_y_settings_camera_flow ==")
	_save = get_root().get_node("SaveManager")
	_game = get_root().get_node("Game")
	_bridge = get_root().get_node("GestureBridge")
	_backup_user()
	var spy := StripSpy.new()
	add_child(spy)
	_game.attach_strip(spy)

	# ================= 段 A（Y-A17）：OPENING 收口一律以流真值为准 =================
	_save.update_settings({"gesture_input": true, "gesture_camera_enabled": true})
	var p1: Node = await _make_panel()
	var ct1: Button = p1.get_node("Panel/VBox/OptionsBox/CameraRow/CameraToggle")
	var gt1: Button = p1.get_node("Panel/VBox/OptionsBox/GestureToggle")
	check(ct1 != null and gt1 != null, "段A 前置：摄像头/手势钮在位")
	# A1 点击未开摄像头（UNAVAILABLE+主动关）→ OPENING
	_bridge._set_state(2)
	_bridge.set("_intentional_stop", true)
	await process_frame
	ct1.set_pressed_no_signal(false)
	ct1.toggled.emit(false)
	await process_frame
	check(str(p1.get("_cam_opening")) == "true", "A1 前置：点击未开 → OPENING")
	# A2 READY 边沿（假死 READY：链路在而流未开）→ 不收口（红：旧实现 READY 即收口亮）
	_bridge._set_state(1)
	await process_frame
	check(str(p1.get("_cam_opening")) == "true", "Y-A17：假死 READY 边沿 → OPENING 保持（收口一律以流真值为准）")
	check(bool(ct1.disabled), "Y-A17：假死 READY 下按钮仍在打开中禁用态（不假亮）")
	# A3 camera_opened 事件到达 → 收口转亮
	_bridge.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "HD Camera"}))
	await process_frame
	check(str(p1.get("_cam_opening")) != "true", "Y-A17：camera_opened 事件 → OPENING 收口")
	check(not bool(ct1.disabled) and bool(ct1.button_pressed) and String(ct1.text) == "摄像头",
		"Y-A17：收口转亮（pressed+enabled+文案=摄像头）")
	p1.queue_free()
	await process_frame

	# ================= 段 B（Y-A18）：OPENING 8s 超时兜底回落 =================
	_bridge._set_state(2)
	_bridge.set("_intentional_stop", true)
	_bridge.set("camera_stream_open", false)   # 复位段A注入的开流真值（本段=流未开语义）
	_bridge.set("_camera_enum", {"cameras": [{"id": 0, "name": "HD Camera"}, {"id": 1, "name": "Virtual Cam"}], "current_camera": 0})
	_bridge.set("_camera_errors", [])
	# 常驻服务夹具（9878 占位=probe ready，test_t_camera_device 段1 手法）：ensure 序照发 SWITCH
	#（attempt id 记账前提），超时回落链全真模拟
	var resident_b := PacketPeerUDP.new()
	var resident_b_ok: bool = resident_b.bind(int(_bridge.get_control_port())) == OK
	check(resident_b_ok, "段B 前置：9878 常驻服务夹具绑定成功（并行占用单跑甄别）")
	var p2: Node = await _make_panel()
	var ct2: Button = p2.get_node("Panel/VBox/OptionsBox/CameraRow/CameraToggle")
	ct2.set_pressed_no_signal(false)
	ct2.toggled.emit(false)
	await process_frame
	check(str(p2.get("_cam_opening")) == "true", "B1 前置：重入 OPENING")
	# B2 注入超时（累计 7.95s 再走 0.1s 帧跨过 8s）→ 批次 Z Z4-④ 等价改写：超时即失败收口
	#（重拉枚举保留；回落切设备抢句柄退役——attempt 零迁移、不发 SWITCH、终态 toast 照发）
	p2.set("_cam_opening_total", 7.95)
	var info_mark_b2: int = spy.info_calls.size()
	var attempt_before_b2: int = int(p2.get("_cam_open_attempt_id"))
	(p2 as Node).call("_process", 0.1)
	await process_frame
	check(str(p2.get("_cam_opening")) != "true", "Z4-④：8s 超时 → 失败收口退出 OPENING（回落链退役，不永挂打开中）")
	check_eq(int(p2.get("_cam_open_attempt_id")), attempt_before_b2,
		"Z4-④：超时 attempt 零迁移（不切首可用设备，零回落 SWITCH；现值 %d）" % int(p2.get("_cam_open_attempt_id")))
	check(spy.info_calls.size() > info_mark_b2, "Z4-④：超时终态 toast 照发（信息可达性）")
	if spy.info_calls.size() > info_mark_b2:
		check_eq(String(spy.info_calls[spy.info_calls.size() - 1][0]), CAM_OPEN_FAIL_TOAST,
			"Z4-④：超时终态 toast=「摄像头打开失败，请检查设备后重试」（回落链文案退役）")
	check(not bool(ct2.disabled) and String(ct2.text) == "摄像头", "Z4-④：超时收口后钮复位可点")
	# B3 OPENING 中 camera_error：非命中本次目标 → 仅提示保持 OPENING；命中 → 收口终态
	ct2.set_pressed_no_signal(false)
	ct2.toggled.emit(false)
	await process_frame
	check(str(p2.get("_cam_opening")) == "true", "B3 前置：重入 OPENING")
	var info_mark_b3: int = spy.info_calls.size()
	_bridge.call("_handle_meta", {"type": "camera_error", "id": 1, "reason": "open-fail"}, "camera_error")
	await process_frame
	check(str(p2.get("_cam_opening")) == "true", "Z4-④：非命中错误（id≠attempt）→ 保持 OPENING 仅提示（旧再回落链退役）")
	var saw_switch_fail_b3 := false
	for kb: int in range(info_mark_b3, spy.info_calls.size()):
		if String(spy.info_calls[kb][0]) == SWITCH_FAIL_TOAST:
			saw_switch_fail_b3 = true
	check(saw_switch_fail_b3, "Z4-④：非命中错误 → 面板切换失败提示照发（文案与事实一致）")
	var attempt_b3: int = int(p2.get("_cam_open_attempt_id"))
	_bridge.call("_handle_meta", {"type": "camera_error", "id": attempt_b3, "reason": "open-fail"}, "camera_error")
	await process_frame
	check(str(p2.get("_cam_opening")) != "true", "Z4-④：命中错误（id==attempt）→ 失败收口退出 OPENING（终态）")
	check_eq(int(p2.get("_cam_open_attempt_id")), attempt_b3, "Z4-④：收口 attempt 零迁移（零回落 SWITCH）")
	check(not bool(ct2.disabled) and String(ct2.text) == "摄像头", "Z4-④：收口后钮复位可点")
	# B4 无可用设备场景 → 超时即报错复位
	ct2.set_pressed_no_signal(false)
	ct2.toggled.emit(false)
	await process_frame
	check(str(p2.get("_cam_opening")) == "true", "B4 前置：重入 OPENING")
	p2.set("_cam_open_attempt_id", 0)
	p2.set("_cam_opening_total", 7.95)
	_bridge.set("_camera_errors", [0, 1])   # 全部设备已失败
	(p2 as Node).call("_process", 0.1)
	await process_frame
	check(str(p2.get("_cam_opening")) != "true", "Y-A18：无可用设备 → 超时即退出 OPENING（不永挂打开中）")

	# B5（批次 Y 扫描回修 P2-3）：8s 超时回落不重发同一失败设备——attempt=-1（ensure 序未记账/
	# 未收到 camera_error 的超时路径）且枚举单设备（current_camera=该设备）时，旧回落过滤
	# cid != -1 恒真 → 把同一失败设备再 SWITCH 一遍并谎报「已切换到 xxx」；修复后回落候选
	# 追加排除枚举 current_camera（仅 failed_id 未知时）→ 同设备不再重发，直接全失败终态。
	_bridge.set("_camera_enum", {"cameras": [{"id": 0, "name": "HD Camera"}], "current_camera": 0})
	_bridge.set("_camera_errors", [])
	ct2.set_pressed_no_signal(false)
	ct2.toggled.emit(false)
	await process_frame
	check(str(p2.get("_cam_opening")) == "true", "B5 前置：重入 OPENING")
	check_eq(str(p2.get("_cam_open_attempt_id")), "0", "B5 前置：ensure 序记账首发目标 id=0")
	p2.set("_cam_open_attempt_id", -1)   # 模拟记账缺口（ensure 早退路径的 attempt 缺省值）
	var info_mark_b5: int = spy.info_calls.size()
	p2.set("_cam_opening_total", 7.95)
	(p2 as Node).call("_process", 0.1)
	await process_frame
	check(str(p2.get("_cam_opening")) != "true",
		"P2-3：attempt 未知+单设备枚举 → 超时回落不重发同设备（直接全失败终态退出 OPENING，旧实现重发后多挂 8s）")
	var lied_b5 := false
	for k5: int in range(info_mark_b5, spy.info_calls.size()):
		if String(spy.info_calls[k5][0]).begins_with("已切换到"):
			lied_b5 = true
	check(not lied_b5, "P2-3：不谎报「已切换到 xxx」（同设备 SWITCH 未发生）")
	check(spy.info_calls.size() > info_mark_b5, "P2-3：全失败终态报错提示照发（信息可达性）")
	if spy.info_calls.size() > info_mark_b5:
		check_eq(String(spy.info_calls[spy.info_calls.size() - 1][0]), CAM_OPEN_FAIL_TOAST,
			"P2-3：终态提示=「摄像头打开失败」toast（文案与事实一致）")

	if resident_b_ok:
		resident_b.close()
	p2.queue_free()
	await process_frame

	# ================= 段 C（㉔/Y-A17）：「无法关闭」info 收窄到流真实开启 =================
	_save.update_settings({"gesture_input": true, "gesture_camera_enabled": true})
	var p3: Node = await _make_panel()
	var ct3: Button = p3.get_node("Panel/VBox/OptionsBox/CameraRow/CameraToggle")
	# C1 假死 READY（READY+流未开）点按 → 打开（OPENING），不弹「无法关闭」
	_bridge._set_state(1)
	_bridge.set("_intentional_stop", false)
	_bridge.set("camera_stream_open", false)
	await process_frame
	var info_mark_c1: int = spy.info_calls.size()
	ct3.set_pressed_no_signal(false)
	ct3.toggled.emit(false)
	await process_frame
	check_eq(spy.info_calls.size(), info_mark_c1, "㉔：假死 READY 点按 → 不弹「无法关闭」（文案与事实一致）")
	check(str(p3.get("_cam_opening")) == "true", "㉔：假死 READY 点按 → 打开（进 OPENING）")
	p3.set("_cam_opening", false)   # 复位（后续段不受扰）
	# C2 流真实开启点按 → info 逐字（批次V规格§3.3① 单源不变）
	_bridge.set("camera_stream_open", true)
	var info_mark_c2: int = spy.info_calls.size()
	ct3.set_pressed_no_signal(false)
	ct3.toggled.emit(false)
	await process_frame
	check_eq(spy.info_calls.size(), info_mark_c2 + 1, "Y-A17：流开启点按 → Game.info 恰 1 次")
	if spy.info_calls.size() > info_mark_c2:
		check_eq(String(spy.info_calls[info_mark_c2][0]), INFO_TEXT, "㉔：info 文案逐字不变（批次V规格§3.3① 单源）")
	check(bool(ct3.button_pressed), "㉔：流开启点按 → 亮态复位")
	p3.queue_free()
	await process_frame

	# ================= 段 D（㉓）：切换设备失败 toast 文案与事实一致 =================
	_save.update_settings({"gesture_input": true, "gesture_camera_enabled": true})
	var p4: Node = await _make_panel()
	var info_mark_d: int = spy.info_calls.size()
	_bridge.set("camera_stream_open", false)
	_bridge.call("_handle_meta", {"type": "camera_error", "id": 1, "reason": "设备被占用"}, "camera_error")
	await process_frame
	check(spy.info_calls.size() > info_mark_d, "㉓前置：非打开中期 camera_error → 统一提示照发（V16 既有语义）")
	# 桥侧统一提示与面板提示同条栈到达（序=桥先面板后）——按文案扫描断言面板条目
	var found_d := false
	for k: int in range(info_mark_d, spy.info_calls.size()):
		if String(spy.info_calls[k][0]) == SWITCH_FAIL_TOAST:
			found_d = true
	check(found_d, "㉓：切换设备失败 toast 文案与事实一致「摄像头切换失败，可稍后重试」（旧「未能重新打开」错位废止）")
	p4.queue_free()
	await process_frame

	# ================= 段 E（Y-A19）：Q3→Q2 解禁通路 =================
	_save.update_settings({"gesture_input": false, "gesture_camera_enabled": false})
	_bridge.set("camera_stream_open", false)   # 复位前段注入的开流真值（本段=流未开语义）
	_bridge.set("_camera_enum", {"cameras": [{"id": 0, "name": "HD Camera"}, {"id": 1, "name": "Virtual Cam"}], "current_camera": 0})
	var p5: Node = await _make_panel()
	var gt5: Button = p5.get_node("Panel/VBox/OptionsBox/GestureToggle")
	var ct5: Button = p5.get_node("Panel/VBox/OptionsBox/CameraRow/CameraToggle")
	check(not bool(ct5.disabled), "Y-A19：手势关+摄像头关 → 摄像头钮恒可点（旧态③置灰废止；0 摄像头除外）")
	# E1 点按单开摄像头 → Q2 分支 ensure 序（存档回写 true）
	var lsn5 := PacketPeerUDP.new()
	var lsn5_ok: bool = lsn5.bind(int(_bridge.get_control_port())) == OK
	check(lsn5_ok, "E 前置：9878 回环监听绑定成功（并行占用单跑甄别）")
	while lsn5.get_available_packet_count() > 0:
		lsn5.get_packet()
	ct5.set_pressed_no_signal(true)
	ct5.toggled.emit(true)   # Q3 点摄像头钮 → 单开摄像头
	await process_frame
	check_eq(bool(_save.get_settings().get("gesture_camera_enabled", false)), true, "Y-A19：Q3 点开摄像头 → 存档 gesture_camera_enabled=true（Q3→Q2 迁移）")
	check(bool(ct5.button_pressed), "Y-A19：Q3 点开摄像头 → 钮亮态（Q2 视觉）")
	if lsn5_ok:
		var saw_switch := false
		for i: int in 8:
			if lsn5.get_available_packet_count() > 0:
				var cmd: String = lsn5.get_packet().get_string_from_utf8()
				if cmd.begins_with("SWITCH_CAMERA") or cmd.begins_with("START_CAMERA_BY_NAME"):
					saw_switch = true
					break
			await process_frame
		check(saw_switch, "Y-A19（AD 等价改写）：Q3 点开摄像头 → ensure 序开镜指令照发（单开通路真实可达）")
	if lsn5_ok:
		lsn5.close()
	# E2 手势钮重开不受扰（Q2→Q1 迁移回归锚）
	gt5.set_pressed_no_signal(true)
	gt5.toggled.emit(true)
	await process_frame
	check(not bool(ct5.disabled) and bool(ct5.button_pressed), "Y-A19：Q2 → Q1 迁移不变（手势重开强制开）")
	p5.queue_free()
	await process_frame

	# ================= 段 F（Y-A20→批次 AB2 等价改写）：0 摄像头确认 → 双钮视觉置灰仍可点；
	# 恢复自动复原。旧「disabled 真禁用」断言随 AB2 拍板语义退役（置灰=视觉置灰仍可点，
	# 点击弹「无硬件摄像头支持」提示条）——断言数 3→6 只增不减，原语义（置灰/恢复）逐条保留。
	# （启动态 0 摄像头 TopStrip 提示条断言归 test_y_zero_camera_gate 段B——提示条消费点=
	# main.gd Game.info 路由，本文件无 main 实例；面板职责=双钮置灰可点/恢复/点击提示条。）
	_save.update_settings({"gesture_input": true, "gesture_camera_enabled": true})
	var p6: Node = await _make_panel()
	var gt6: Button = p6.get_node("Panel/VBox/OptionsBox/GestureToggle")
	var ct6: Button = p6.get_node("Panel/VBox/OptionsBox/CameraRow/CameraToggle")
	check(not bool(gt6.disabled) and not bool(ct6.disabled), "F 前置：有设备态双钮可点")
	var sp_ab: GDScript = load("res://scenes/settings/settings_panel.gd")
	var cm_ab: Dictionary = sp_ab.get_script_constant_map()
	# 批次 AB-3：恒深档（旧 is_dark() 探测随深浅主题机制删除退役；AB2 gray probe 留痕）
	var zg_bg: Color = cm_ab.get("ZERO_GRAY_BG_DARK", Color(-1, -1, -1, -1))   # AB-3 恒深档
	var zg_font: Color = cm_ab.get("ZERO_GRAY_FONT", Color(-1, -1, -1, -1))
	_bridge.simulate_packet(JSON.stringify({"type": "init", "cameras": [], "current_camera": 0}))
	await process_frame
	check(not bool(gt6.disabled) and not bool(ct6.disabled),
		"Y-A20→AB2 等价改写：枚举确认 0 设备 → 双钮 disabled=false（视觉置灰仍可点，旧真禁用退役）")
	var gt6_sb: StyleBoxFlat = gt6.get_theme_stylebox("normal") as StyleBoxFlat
	var ct6_sb: StyleBoxFlat = ct6.get_theme_stylebox("normal") as StyleBoxFlat
	check(gt6_sb != null and ct6_sb != null and gt6_sb.bg_color == zg_bg and ct6_sb.bg_color == zg_bg \
		and gt6.get_theme_color("font_color") == zg_font and ct6.get_theme_color("font_color") == zg_font,
		"AB2：0 摄像头 → 双钮置灰样式在位（零摄像头灰档灰底+灰字）")
	var f_mark: int = spy.info_calls.size()
	gt6.button_pressed = true   # 置灰态点击路径（toggled 触发）
	await process_frame
	check(spy.info_calls.size() > f_mark \
		and String(spy.info_calls[spy.info_calls.size() - 1][0]) == "无硬件摄像头支持",
		"AB2：0 摄像头点手势钮 → 「无硬件摄像头支持」提示条（TopStrip info=对接失败弹条同通道）")
	check_eq(bool(_save.get_settings().get("gesture_input", true)), false,
		"AB2：0 摄像头 → 手势交互状态强制置关写档（主会话拍板口径）")
	# 恢复设备 → 自动复原可点（原断言保持）+ 置灰样式解除
	_bridge.simulate_packet(JSON.stringify({"type": "init", "cameras": [{"id": 0, "name": "HD Camera"}], "current_camera": 0}))
	await process_frame
	check(not bool(gt6.disabled) and not bool(ct6.disabled), "Y-A20：重枚举到设备 → 双钮自动恢复可点")
	check(gt6.get_theme_color("font_color") != zg_font and ct6.get_theme_color("font_color") != zg_font \
		and (gt6.get_theme_stylebox("normal") as StyleBoxFlat).bg_color != zg_bg,
		"AB2：重枚举到设备 → 置灰样式解除（字色/底色复常）")
	p6.queue_free()
	await process_frame

	_game.attach_strip(null)
	spy.queue_free()
	await process_frame
	finish()
