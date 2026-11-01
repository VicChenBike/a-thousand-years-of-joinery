extends "res://tests/test_base.gd"
## 批次 V（V-C4，spec §3.3①②/§4.2）判定用例（TDD 先红后绿）：设置面板 Q1 钩子退役
## + 摄像头钮三态流 + CameraMenuPopup 主弹窗棕化（V-B2 移交项）。
## 契约：
##   ① Q1 拦截钩子退役：Q1_TOAST_TEXT 常量 / q1_last_toast 观测成员全删（源码+实例双证据，
##     旧「关手势→摄像头强制回开」拦截语义废除；SaveManager.settings_changed 信号流不变）；
##   ② 三态真值表（手势 × 摄像头 → 弹条模式/置灰）：
##     态① 手势开+摄像头开 → Game.info「手势交互需要摄像头，无法关闭」成条自动消失（3s）
##        + set_pressed_no_signal(true) 复位亮态；存档/桥/控制通道零触碰；
##     态② 手势关+摄像头开 → Game.confirm「摄像头关闭后，下次开启手势交互需要重新等待数秒启动。」
##        ——确认路径：RELEASE_CAMERA 逐字+UNAVAILABLE+主动关标志+存档 gesture_camera_enabled=false
##        +按钮维持关态（承接态③置灰）；取消/× 路径：零副作用+set_pressed_no_signal(true) 复位亮态；
##     态③ 手势关+摄像头关 → camera_toggle.disabled 置灰不可点；手势重开 → 置灰解除+强制开
##        （Q4→Q1 迁移通道不变）；
##   ③ CameraMenuPopup 主弹窗棕化：theme 显式注入非空+panel StyleBox 棕档（camera_menu
##     _apply_popup_theme 同源档值，坑4：PopupPanel 系 Window 主题不跨 Window 传播）+
##     主题变更跟随重刷。
## 4.7 坑对齐：取值一律 .get 防御（坑2）、无 bool(null) 强转（坑1）、--script 时序
## await process_frame（坑6）；控制通道零发送断言经 9878 回环监听（test_t_camera_device
## _ctrl_listener 同款手法）；autoload 一律 get_root().get_node 实例引用（编译窗纪律）。
## 清档纪律（tools/README_走查清档规范.md，批次V回修②P1-1 补齐）：起测前备份 user:// 真实
## 档案（save.json 及本测试可触及的 .tmp/.bak），终测逐字节还原并断言等价 + EVID 证据行；
## 还原后真实 autoload SaveManager load_game 重同步内存（规范第 2 条）。零摄像头。

const PANEL_SCENE := "res://scenes/settings/settings_panel.tscn"
const PANEL_SRC := "res://scenes/settings/settings_panel.gd"
const SAVE_PATH := "user://save.json"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"
# 备份路径必须带全 user:// 前缀（test_n10/test_v_save_domain 先例）——实测相对路径在
# FileAccess/DirAccess 间解析不一致（copy 落工程根进程 cwd、file_exists 又随 API 漂移），
# 前缀缺失=备份链静默失效。
const BK_PREFIX := "user://_vscf_backup_"
# 走查规范备份组（本测试不触碰 first_launch.flag——无 mark_first_launch 路径，不入组）
const WATCHED_PATHS: Array = [SAVE_PATH, TMP_PATH, BAK_PATH]
const INFO_TEXT := "手势交互需要摄像头，无法关闭"
const CONFIRM_TEXT := "摄像头关闭后，下次开启手势交互需要重新等待数秒启动。"

## TopStrip 替身（test_v_game_confirm 同款）：记录 push_info/push_confirm 调用参数；
## 确认/取消路径由测试直接调用记录到的回调（模拟 strip 按钮触发）。
class StripSpy extends Node:
	var info_calls: Array = []    # 每项 [text, seconds]
	var confirm_calls: Array = [] # 每项 [text, on_confirmed, on_canceled]
	func push_info(text: String, seconds: float = 3.0) -> void:
		info_calls.append([text, seconds])
	func push_confirm(text: String, on_confirmed: Callable = Callable(),
			on_canceled: Callable = Callable()) -> void:
		confirm_calls.append([text, on_confirmed, on_canceled])

var _bridge: Node = null
var _pre_save_text: String = ""  # 起测前真实 save.json 原文（还原等价自检基准）

func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _del(p: String) -> void:
	var a: String = _abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _read_file(p: String) -> String:
	return FileAccess.get_file_as_string(p)

func _backup_user() -> void:
	# 规范第 1 条：任何删/写档操作之前备份真实档案（test_v_save_domain 同款实现）
	if FileAccess.file_exists(SAVE_PATH):
		_pre_save_text = _read_file(SAVE_PATH)
	for p: String in WATCHED_PATHS:
		if FileAccess.file_exists(p):
			var bk := BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_abs(p), _abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	# 规范第 2 条：所有退出路径统一收口还原；还原后真实 autoload load_game 重同步内存
	for p: String in WATCHED_PATHS:
		_del(p)
		var bk := BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_abs(bk), _abs(p))
			DirAccess.remove_absolute(_abs(bk))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()  # 防进程退出 close_requested → save_game 把测试态写回真实档案
	# 纪律自检：还原后 save.json 与起测前逐字节等价（起测前无档 ↔ 还原后无档）
	var post: String = _read_file(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|v_settings_camera_flow|files=%d" % WATCHED_PATHS.size())

func _make_panel() -> Node:
	var panel: Node = (load(PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await process_frame
	await process_frame
	return panel

## 9878 回环监听（test_t_camera_device _ctrl_listener 同款；null=并行环境占用，零命令断言降级
## 由桥状态快照兜底——前置 check 显式记录）
func _ctrl_listener() -> PacketPeerUDP:
	var l := PacketPeerUDP.new()
	if l.bind(int(_bridge.get_control_port())) != OK:
		return null
	return l

func _drain(l: PacketPeerUDP) -> Array:
	var out: Array = []
	while l != null and l.get_available_packet_count() > 0:
		out.append(l.get_packet().get_string_from_utf8())
	return out

func _wait_packets(l: PacketPeerUDP, frames: int) -> void:
	for i: int in frames:
		if l != null and l.get_available_packet_count() > 0:
			return
		await process_frame

## 桥触碰快照（load_state/主动关标志/枚举缓存/错误缓存——三态流各路径触碰面全覆盖）
func _bridge_snapshot() -> Array:
	return [int(_bridge.get_load_state()), bool(_bridge.get("_intentional_stop")),
		str(_bridge.get("_camera_enum")), str(_bridge.get("_camera_errors"))]

func _initialize() -> void:
	print("== test_v_settings_camera_flow ==")
	var save: Variant = get_root().get_node("SaveManager")
	var game: Variant = get_root().get_node("Game")
	var theme_mgr: Variant = get_root().get_node("ThemeManager")
	theme_mgr._dark_theme = load("res://themes/theme_dark.tres")
	# 批次 AB-3：_light_theme/_last_dark 注入随深浅主题机制删除退役（恒深档）。
	_bridge = get_root().get_node("GestureBridge")
	_backup_user()                     # 清档纪律：任何删/写档前备份真实档案
	for p: String in WATCHED_PATHS:
		_del(p)                        # 沙盒基线：真实档案已备份，测试域内全清
	save.load_game()
	var spy := StripSpy.new()
	add_child(spy)
	game.attach_strip(spy)   # Game.info/confirm → spy（V-C3a 委托链）

	# ================= 段 1. Q1 拦截钩子退役（源码证据链） =================
	var src: String = FileAccess.get_file_as_string(PANEL_SRC)
	check(src.length() > 0, "段1前置：settings_panel.gd 可读")
	check(not src.contains("Q1_TOAST_TEXT"), "V-C4①：Q1_TOAST_TEXT 常量已删（批次V规格§4.2 退役留痕）")
	check(not src.contains("q1_last_toast"), "V-C4①：q1_last_toast 观测成员已删（批次V规格§4.2 退役留痕）")
	check(not src.contains("gesture_toggle.button_pressed:\n\t\t\tcamera_toggle.set_pressed_no_signal(true)\n\t\t\tq1_last_toast"),
		"V-C4①：旧「关手势→强制回开」拦截钩子体已删（语义废除）")

	# ================= 段 2. 真值表行①（手势开+摄像头开 → info 条+复位亮态+零触碰） =================
	save.update_settings({"gesture_input": true, "gesture_camera_enabled": true})
	var p1: Node = await _make_panel()
	var ct1: Button = p1.get_node("Panel/VBox/OptionsBox/CameraRow/CameraToggle")
	check(bool(ct1.button_pressed) and not bool(ct1.disabled), "行①前置：摄像头钮亮态可点（Q1 态）")
	var lsn1 := _ctrl_listener()
	# 批次 W4-N5 等价改写（W6 回归甄别）：「无法关闭」info 条收窄到「摄像头真实已开」态
	#（桥 READY ∧ 未主动关；桥非 READY 时点击=打开进 OPENING，见 test_w_camera_button N5②）——
	# 本段行①语义「手势开+摄像头开」在 N5 下按新真值源注入 READY，断言组原样保持；
	# 注入前快照、:167 桥状态零变化断言后还原（行②自设 UNAVAILABLE，不受前态影响）。
	var _gb_pre_state: int = int(_bridge.get_load_state())
	var _gb_pre_released: bool = bool(_bridge.get("_intentional_stop"))
	_bridge.set("_intentional_stop", false)
	_bridge._set_state(1)   # READY
	# 批次 Y（Y-A17/㉔）：「无法关闭」info 收窄到「摄像头流真实开启」——经 camera_opened 事件
	# 注入开启真值（N5 下等价注入形态升级：链路 READY ∧ 流开）
	_bridge.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "HD Camera"}))
	await process_frame
	check(true, "行①前置（N5/Y2）：桥注入 READY+流开启真值（摄像头真实已开语义）")
	check(lsn1 != null, "行①前置：9878 回环监听绑定成功（并行占用时零命令断言降级快照兜底）")
	_drain(lsn1)   # 排干面板 _ready 期 init 噪声（Q1→ensure_camera_open 探测形态依赖 9878 占用态）
	var snap1: Array = _bridge_snapshot()
	var save1: Dictionary = save.get_settings().duplicate()
	ct1.set_pressed_no_signal(false)
	ct1.toggled.emit(false)   # 用户点摄像头钮（态①）
	await process_frame
	check_eq(spy.info_calls.size(), 1, "行①：点击 → Game.info 顶部成条恰 1 次")
	if spy.info_calls.size() >= 1:
		check_eq(String(spy.info_calls[0][0]), INFO_TEXT, "行①：info 文案逐字「手势交互需要摄像头，无法关闭」")
		check_eq(float(spy.info_calls[0][1]), 3.0, "行①：自动消失缺省 seconds=3.0（成条自灭）")
	check_eq(spy.confirm_calls.size(), 0, "行①：零 confirm（info/confirm 分流正确）")
	check(bool(ct1.button_pressed), "行①：亮态复位（set_pressed_no_signal(true)，防与存档失同步）")
	check_eq(save.get_settings(), save1, "行①：存档零写档（settings 全字典不变，含 gesture_camera_enabled=true）")
	check_eq(_bridge_snapshot(), snap1, "行①：桥状态零变化（load_state/主动关标志/枚举/错误缓存）")
	check_eq(_drain(lsn1), [], "行①：控制通道零命令（不触碰桥）")
	check(p1.get("q1_last_toast") == null, "行①：实例级证据——q1_last_toast 成员不存在（get null，旧 U1 观测断言等价替换留痕）")
	if lsn1 != null:
		lsn1.close()
	_bridge._set_state(_gb_pre_state)      # N5 注入还原（原状态/主动关标志，行②自设态不受扰）
	_bridge.set("_intentional_stop", _gb_pre_released)

	# ================= 段 3. CameraMenuPopup 主弹窗棕化（V-B2 移交项，挂 p1） =================
	var popup: PopupPanel = p1.get_node("CameraMenuLayer/CameraMenuPopup")
	check(popup.theme != null, "V-C4③：CameraMenuPopup theme 显式注入非空（坑4：Window 不跨主题传播）")
	check(popup.has_theme_stylebox_override("panel"), "V-C4③：panel StyleBox 棕档覆盖在场")
	var sb: StyleBoxFlat = popup.get_theme_stylebox("panel") as StyleBoxFlat
	check(sb != null, "V-C4③：panel 覆盖取回为 StyleBoxFlat")
	# 批次 AB-3：恒深档棕底（is_dark() 与浅档色随深浅主题机制删除退役，深档值不变）。
	var exp_a := Color(0.24, 0.17, 0.08, 0.96)
	if sb != null:
		check(sb.bg_color.is_equal_approx(exp_a), "V-C4③：棕档底色恒深档（camera_menu._apply_popup_theme 同源）")
	# 旧「主题变更跟随重刷」断言（翻转 _last_dark + emit theme_changed）随深浅主题机制删除退役
	# ——等价改写为反向锁：信号无复辟 + popup.theme==current_theme()（挂载直注恒定）。
	check(not theme_mgr.has_signal("theme_changed"),
		"AB-3 反向锁：ThemeManager 无 theme_changed 信号（跟随重刷机制无复辟）")
	check(popup.theme == theme_mgr.current_theme(),
		"AB-3 等价改写：popup.theme==current_theme()（挂载直注，恒深色）")
	await process_frame
	p1.queue_free()
	await process_frame

	# ================= 段 4. 真值表行②（手势关+摄像头开 → confirm 条；确认路径） =================
	save.update_settings({"gesture_input": false, "gesture_camera_enabled": true})
	var p2: Node = await _make_panel()
	var gt2: Button = p2.get_node("Panel/VBox/OptionsBox/GestureToggle")
	var ct2: Button = p2.get_node("Panel/VBox/OptionsBox/CameraRow/CameraToggle")
	check(bool(ct2.button_pressed) and not bool(ct2.disabled), "行②前置：摄像头亮态可点（Q2 独立生效态）")
	var info_mark: int = spy.info_calls.size()
	ct2.set_pressed_no_signal(false)
	ct2.toggled.emit(false)   # 用户点摄像头钮（态②）
	await process_frame
	check_eq(spy.info_calls.size(), info_mark, "行②：零 info（confirm 分流正确）")
	check_eq(spy.confirm_calls.size(), 1, "行②：点击 → Game.confirm 确认条恰 1 次")
	if spy.confirm_calls.size() >= 1:
		check_eq(String(spy.confirm_calls[0][0]), CONFIRM_TEXT, "行②：confirm 文案逐字")
	check_eq(bool(save.get_settings().get("gesture_camera_enabled", true)), true,
		"行②：未确认前存档不落 false（零副作用前置）")
	# ---- 确认路径：RELEASE+写档 false+按钮维持关态（承接态③置灰）----
	var lsn4 := _ctrl_listener()
	_drain(lsn4)
	if spy.confirm_calls.size() >= 1:
		(spy.confirm_calls[0][1] as Callable).call()   # 模拟 TopStrip「确认」按钮
	await _wait_packets(lsn4, 4)
	check_eq(int(_bridge.get_load_state()), 2, "行②确认：request_camera_release → UNAVAILABLE（LoadState.UNAVAILABLE=2）")
	check_eq(bool(_bridge.get("_intentional_stop")), true, "行②确认：主动关标志置位（RELEASE 语义）")
	check(_drain(lsn4).has("RELEASE_CAMERA"), "行②确认：控制通道逐字 RELEASE_CAMERA")
	check_eq(bool(save.get_settings().get("gesture_camera_enabled", true)), false,
		"行②确认：存档 gesture_camera_enabled=false 已写档")
	check(not bool(ct2.button_pressed), "行②确认：按钮维持关态（不回弹）")
	# 批次 Y（Y-A19）：Q3 态钮恒可点（旧「态③置灰承接」废止——Q3→Q2 解禁通路）
	check(not bool(ct2.disabled), "行②确认（Y2 等价改写）：手势关+摄像头关 → 钮可点（Q3 点按单开摄像头；旧置灰废止）")
	if lsn4 != null:
		lsn4.close()
	p2.queue_free()
	await process_frame

	# ================= 段 5. 真值表行②（取消路径：零副作用+复位亮态） =================
	save.update_settings({"gesture_input": false, "gesture_camera_enabled": true})
	var p3: Node = await _make_panel()
	var ct3: Button = p3.get_node("Panel/VBox/OptionsBox/CameraRow/CameraToggle")
	check(bool(ct3.button_pressed) and not bool(ct3.disabled), "行②取消前置：摄像头亮态可点")
	var lsn5 := _ctrl_listener()
	_drain(lsn5)
	var snap5: Array = _bridge_snapshot()
	var save5: Dictionary = save.get_settings().duplicate()
	ct3.set_pressed_no_signal(false)
	ct3.toggled.emit(false)   # 用户点摄像头钮（态②）
	await process_frame
	check_eq(spy.confirm_calls.size(), 2, "行②取消：确认条第 2 次（新面板新条）")
	if spy.confirm_calls.size() >= 2:
		(spy.confirm_calls[1][2] as Callable).call()   # 模拟 TopStrip「取消」/×（等价）
	await process_frame
	check(bool(ct3.button_pressed), "行②取消：亮态复位（set_pressed_no_signal(true)，防与存档失同步）")
	check(not bool(ct3.disabled), "行②取消：按钮保持可点（仍是态②）")
	check_eq(save.get_settings(), save5, "行②取消：存档零写档（settings 全字典不变）")
	check_eq(_bridge_snapshot(), snap5, "行②取消：桥状态零变化（存档与桥零触碰）")
	check_eq(_drain(lsn5), [], "行②取消：控制通道零命令（存档与桥零触碰）")
	if lsn5 != null:
		lsn5.close()
	p3.queue_free()
	await process_frame

	# ================= 段 6. 真值表行③（手势关+摄像头关 → disabled 置灰；重开解除） =================
	save.update_settings({"gesture_input": false, "gesture_camera_enabled": false})
	var p4: Node = await _make_panel()
	var gt4: Button = p4.get_node("Panel/VBox/OptionsBox/GestureToggle")
	var ct4: Button = p4.get_node("Panel/VBox/OptionsBox/CameraRow/CameraToggle")
	# 批次 Y（Y-A19）等价改写：Q3 钮恒可点（旧「disabled 置灰」废止）——点按单开摄像头（Q3→Q2）
	check(not bool(ct4.disabled), "行③（Y2 等价改写）：手势关+摄像头关 → 钮可点（Q3→Q2 解禁）")
	check(not bool(ct4.button_pressed), "行③：钮态关（与存档一致）")
	check_eq(bool(save.get_settings().get("gesture_camera_enabled", true)), false, "行③：存档保持 false")
	ct4.set_pressed_no_signal(true)
	ct4.toggled.emit(true)   # Q3 点摄像头钮 → 单开摄像头（Q3→Q2 迁移）
	await process_frame
	check_eq(bool(save.get_settings().get("gesture_camera_enabled", false)), true,
		"Y-A19：Q3 点开摄像头 → 存档回写 true（单开通路真实可达）")
	# Q4→Q1 迁移通道不变：手势重开 → 置灰解除+强制开
	gt4.set_pressed_no_signal(true)
	gt4.toggled.emit(true)
	check(not bool(ct4.disabled) and bool(ct4.button_pressed), "行③→Q1 迁移：手势重开 → 强制开（迁移通道不变）")
	check_eq(bool(save.get_settings().get("gesture_camera_enabled", false)), true, "行③→Q1 迁移：存档回写 true")
	p4.queue_free()
	await process_frame

	# ================= 段 7. 回修②P2-2：面板退出 → confirm 残留按取消收起（零副作用） =================
	# 挂真实 TopStrip 承接端到端链路：面板 _exit_tree → Game.dismiss_confirm() →
	# TopStrip.dismiss_active_confirm()（仅 confirm 模式：on_canceled 回调执行+按取消收起；
	# info 不动；防重入）。移除面板用 remove_child 触发 NOTIFICATION_EXIT_TREE（实例保持有效，
	# 取消回调复位亮态可观测）；零副作用=存档/桥/控制通道零触碰。
	save.update_settings({"gesture_input": false, "gesture_camera_enabled": true})
	var strip7: Node = (load("res://scenes/shared/top_strip.gd") as GDScript).new()
	add_child(strip7)
	await process_frame
	await process_frame
	game.attach_strip(strip7)
	var p5: Node = await _make_panel()
	var ct5: Button = p5.get_node("Panel/VBox/OptionsBox/CameraRow/CameraToggle")
	check(bool(ct5.button_pressed) and not bool(ct5.disabled), "段7前置：摄像头亮态可点（态②）")
	var lsn7 := _ctrl_listener()
	_drain(lsn7)
	var snap7: Array = _bridge_snapshot()
	var save7: Dictionary = save.get_settings().duplicate()
	ct5.set_pressed_no_signal(false)
	ct5.toggled.emit(false)   # 用户点摄像头钮（态②）→ confirm 挂起
	await process_frame
	check_eq(String(strip7.get("_mode")), "confirm", "段7前置：confirm 条挂起（真实 TopStrip 承接）")
	check_eq(bool(strip7.visible), true, "段7前置：confirm 条可见")
	# 面板退出（remove_child → NOTIFICATION_EXIT_TREE → _exit_tree → Game.dismiss_confirm）
	p5.get_parent().remove_child(p5)
	await process_frame
	check_eq(bool(strip7.visible), false, "回修②P2-2：面板退出 → confirm 条按取消收起（不残留）")
	check_eq(String(strip7.get("_mode")), "", "回修②P2-2：条槽位复位（_mode=\"\"，回调引用已复位）")
	check(bool(ct5.button_pressed), "回修②P2-2：取消回调复位亮态（on_canceled 执行——零副作用语义同取消路径）")
	check_eq(save.get_settings(), save7, "回修②P2-2：零副作用——存档零写档（settings 全字典不变）")
	check_eq(_bridge_snapshot(), snap7, "回修②P2-2：零副作用——桥状态零变化（存档与桥零触碰）")
	check_eq(_drain(lsn7), [], "回修②P2-2：零副作用——控制通道零命令（不触桥）")
	if lsn7 != null:
		lsn7.close()
	p5.free()
	game.attach_strip(spy)   # 复位 spy 挂接（收尾一致）
	strip7.queue_free()
	await process_frame

	game.attach_strip(null)   # 摘除替身（复位路由，test_t_camera_device 段5 同款收尾）
	spy.queue_free()
	await process_frame
	_restore_user()           # 清档纪律还原（备份→测试→逐字节还原+EVID，规范第 2 条）
	finish()
