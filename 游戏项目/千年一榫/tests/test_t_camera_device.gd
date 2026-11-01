extends "res://tests/test_base.gd"
## 批次 T 判定用例（T-F 域，P1-4 归属单化）：T11 摄像头独立开关（Q2 spawn）+ toast 双分支
## + S14 toast 行为承接（原 test_gesture_ui_cleanup 段 3 移交留痕）+ T12 下拉状态机/子列/置灰
## + send_control 命令逐字 + T13 悬浮跟随说明窗。协议层断言不在此文件（bridge_ports 段 14~17）。
## 计数对账（批次 U 前终值 54；plan §8 TF-2 复点 43 + RV-2 段 9b=7 + NG-1 段 10 追加 2 + FV-1 段 9b 追加 2；
## 批次 U 等价替换净 0＋新增 21：段 2b Q3 RELEASE=2 + 批次 U 段=19（PROBE_TIMEOUT/夹具/检测中/
## PROBE_MATRIX:1/1s 节流/矩阵列出/失败文本/置灰/id==current=9 + 3 参命令=3 + 不吞点击=2 + 四象限=4 + 两态文本=1）
## → 合计 75；走查移交项①（2026-09-18）段 1 追加 2（9878 前置夹具 + Q2→SWITCH_CAMERA:1 行为断言）→ 合计 77。

const PANEL_SCENE := "res://scenes/settings/settings_panel.tscn"
const MAIN_SCENE := "res://scenes/main.tscn"
const CAM_TIP_TEXT := "摄像头保持开启，以便您随时重新打开手势交互（摄像头启动需要数秒）。也可在此手动关闭。"
const CAM_TIP_MAX_WIDTH := 320.0   # spec §4-T13：说明窗最大宽（NG-1 宽钳断言口径，与 settings_panel 同值）

## 批次 V-B2 等价替换夹具：TopStrip 替身（记录 push_info 调用参数）——段 5 S14 移交断言的
## 落点等价迁移（Game.toast centered=true 自批次 V-C1 单点改道 TopStrip.push_info，ToastCenter
## 中央锚点盒不再承接 → 旧 _center_box 断言恒空断裂，test_v_top_strip.gd 同款替身手法）。
## 批次 V-C6（规格§4.2）：补 push_confirm 记录——段 2 摄像头钮三态流确认条捕获用。
class StripProbe extends Node:
	var pushes: Array = []
	var confirm_calls: Array = []   # 每项 [text, on_confirmed, on_canceled]
	func push_info(text: String, seconds: float = 3.0) -> void:
		pushes.append([text, seconds])
	func push_confirm(text: String, on_confirmed: Callable = Callable(),
			on_canceled: Callable = Callable()) -> void:
		confirm_calls.append([text, on_confirmed, on_canceled])

func _cleanup() -> void:
	var p: String = ProjectSettings.globalize_path("user://save.json")
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)

func _init_panel() -> Control:
	var panel: Control = (load(PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await process_frame
	return panel

# ---- 批次 U（U-D Step 2）：9878 回环监听 helpers（UA-4 同款私有副本）＋合成点击 ----
# ⚠ 编译窗纪律（U-D 实证）：本文件经 --script 于 autoload 全局名注册前编译——helpers 不得
# 静态引用 GestureBridge（U-A test_u_bridge_protocol 先例=实例引用）；_bridge 由 _initialize 注入。
var _bridge: Node = null

func _ctrl_listener() -> PacketPeerUDP:
	var l := PacketPeerUDP.new()
	if l.bind(int(_bridge.get_control_port())) != OK:
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

## 双审回修 P1-2：合成左键点击（press+release）经 push_input 注入 gui_input 管线
##（4.7 无 Viewport.gui_find_control；gesture_cursor_layer push_input 先例）
func _click_at(pos: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	get_root().push_input(down, true)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	get_root().push_input(up, true)

## 批次 U（UD-5 Step 4）测试 helper：遍历面板子树计 HoverTip 实例数（按 script 比对）
func sp_hovertip_count(panel_node: Node) -> int:
	var n := 0
	for c: Variant in panel_node.find_children("*", "PanelContainer", true, false):
		if (c as Node).get_script() == load("res://scenes/shared/hover_tip.gd"):
			n += 1
	return n

# ===== 清档纪律（tools/README_走查清档规范.md，批次V回修②B 补齐，test_v_save_domain 同款）=====
# 起测前备份 user:// 真实档案（save.json/first_launch.flag 及可触及的 .tmp/.bak 四件组），
# 终测统一经 finish() 收口还原：先同步 free 测试挂载节点（level._exit_tree 兜底写档等
# 「退出写回」先落测试域磁盘，规范第 6 条），再逐件还原 + SaveManager load_game 重同步内存
# + 逐字节等价断言 + EVID 证据行。备份路径必须带全 user:// 前缀（相对路径在 FileAccess/
# DirAccess 间解析漂移 → 备份链静默失效，test_n10 先例）；每文件独立备份前缀防崩溃残留互踩。
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_r2b_tcd_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _pre_save_text: String = ""   # 起测前真实 save.json 原文（还原等价自检基准）

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _disc_del(p: String) -> void:
	var a: String = _disc_abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _backup_user() -> void:
	# 规范第 1 条：任何删/写档操作之前备份真实档案（有档才备份；还原「有备份才回拷」幂等，
	# 起测前不存在的档案终测后仍不存在——测试自建残留一律清零）
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	# 防退出写回（规范第 6 条）：先同步 free 测试挂载的非 autoload 节点——level._exit_tree
	# 兜底写档（N9）若拖到进程退出树序，会在还原之后把测试态写回真实档案；提前 free 令
	# 兜底写档落测试域磁盘，紧随其后的逐件还原即将其覆盖。
	for c: Node in root.get_children():
		if not DISC_AUTOLOADS.has(String(c.name)):
			c.free()
	# 规范第 2 条：逐件还原 + load_game 重同步内存（防后续 save_game 把测试态写回真实档案）
	for p: String in DISC_WATCHED:
		_disc_del(p)
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(_disc_abs(bk))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()
	# 纪律自检：还原后 save.json 与起测前逐字节等价（起测前无档 ↔ 还原后无档）
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|tcd|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_t_camera_device ==")
	_backup_user()
	var save: Variant = get_root().get_node("SaveManager")
	var bridge: Variant = get_root().get_node("GestureBridge")
	_bridge = bridge   # 批次 U：helpers 注入（编译窗纪律——helpers 不得静态引用 autoload 全局名）
	var game: Variant = get_root().get_node("Game")
	_cleanup()
	save.load_game()
	bridge._set_state(1)
	# ---- 段 1. T11 Q2：手势关+摄像头关 → 单独点开摄像头 → spawn 被调用 + 存档 true（2 checks）
	#      ＋走查移交项①（2026-09-18）：Q2 统一入口行为断言（+2 checks）——bind 9878 模拟常驻服务
	#      （probe ready 形态）＋无头 start 恒 false＝打包形态全真模拟；u10/u11 实证缺口（直调
	#      start_gesture_process 旁路在打包形态不发 SWITCH_CAMERA → RELEASE 后经 Q2 不重开）
	#      的红灯断言落点（test_u_bridge_protocol 段 5b 同款 probe 夹具手法）。----
	var panel: Control = await _init_panel()
	var gt: Button = panel.get_node("Panel/VBox/OptionsBox/GestureToggle")
	var ct: Button = panel.get_node("Panel/VBox/OptionsBox/CameraRow/CameraToggle")
	gt.set_pressed_no_signal(false)
	gt.toggled.emit(false)          # Q3 态（手势关+摄像头关）
	ct.set_pressed_no_signal(false)
	ct.toggled.emit(false)
	var resident_q2 := _ctrl_listener()   # bind 9878 → _probe_python_ready()==true（bind 失败=并行环境占用，单跑甄别 §1.4）
	check(resident_q2 != null, "U移交①前置：9878 回环监听绑定成功（probe ready 形态夹具）")
	bridge._simulate_start_ok = false   # 打包形态判据：无头/导出 start 恒 false（U4 接缝显式复位）
	bridge._camera_enum = {"cameras": [{"id": 0, "name": "CamA"}, {"id": 1, "name": "CamB"}], "current_camera": 1}
	bridge._intentional_stop = true   # start_gesture_process 入口清标志 → 以此作「start 被调用」探针
	ct.set_pressed_no_signal(true)
	ct.toggled.emit(true)             # Q2 进入：点开摄像头
	check_eq(bool(bridge.get("_intentional_stop")), false,
		"T11：手势关+摄像头开 → start_gesture_process 被调用（探针=入口清 _intentional_stop，唯一清除点；ensure_camera_open 内部同入口承接）")
	check_eq(bool(save.get_settings()["gesture_camera_enabled"]), true, "T11：Q2 存档 gesture_camera_enabled=true")
	await _wait_available(resident_q2, 4)
	var cmds_q2 := _recv_cmds(resident_q2)
	# 批次 AD（spec §4.2.2-3）等价替换留痕：ensure_camera_open 选择序再升级——无记忆
	#（String ""=未记忆）→ 下发**空载荷**启动指令，降级首项下沉 Python 侧。旧口径
	#「SWITCH_CAMERA:0/1 盲发数字」废止；断言语义（Q2 经统一入口照发开镜指令）不变。
	check(cmds_q2.has("START_CAMERA_BY_NAME:"),
		"AD 等价替换（旧 U移交①/V-B2「SWITCH_CAMERA:0」）：Q2 开摄像头 → 空载荷启动指令（打包形态 start false+probe ready；实际 %s）" % [cmds_q2])
	check_eq(cmds_q2.count("SWITCH_CAMERA:0"), 0,
		"AD 反向护栏：Q2 通路零 SWITCH_CAMERA 数字命令（禁止依赖 CAP 索引；实际 %s）" % [cmds_q2])
	if resident_q2 != null:
		resident_q2.close()
	# ---- 段 2. T11 Q3：点关 → 三态流关闭确认条（批次V规格§4.2 等价替换，V-C4 移交，7 checks；
	#      旧「点关即直关」两断言（:124 UNAVAILABLE / :125 存档 false）废止——手势关+摄像头开
	#      点关改 Game.confirm 关闭确认条：点关→confirm 弹出（文案逐字）+零副作用（桥态/存档不变）；
	#      手动触发 recorded on_confirmed → RELEASE+UNAVAILABLE+存档 false）----
	var strip2 := StripProbe.new()
	game.attach_strip(strip2)   # 捕获 Game.confirm 委托（未挂接兜底路径 test_v_game_confirm 已覆盖）
	var st_before2: int = int(bridge.get_load_state())
	ct.set_pressed_no_signal(false)
	ct.toggled.emit(false)
	check_eq(int(bridge.get_load_state()), st_before2,
		"V-C4 等价替换（旧 T11：点关即 UNAVAILABLE）：点关 → 确认前桥态不变（零副作用）")
	check_eq(bool(save.get_settings()["gesture_camera_enabled"]), true,
		"V-C4 等价替换（旧 T11：点关即存档 false）：点关 → 确认前存档不变（零副作用）")
	check_eq(strip2.confirm_calls.size(), 1, "V-C4 等价替换：点关 → Game.confirm 关闭确认条恰 1 条")
	if strip2.confirm_calls.size() == 1:
		check_eq(String(strip2.confirm_calls[0][0]), "摄像头关闭后，下次开启手势交互需要重新等待数秒启动。",
			"V-C4 等价替换：关闭确认文案逐字（批次V规格§3.3②）")
		(strip2.confirm_calls[0][1] as Callable).call()   # 手动触发 recorded on_confirmed（模拟条内「确认」）
	check_eq(int(bridge.get_load_state()), 2,
		"V-C4 等价替换：确认 → request_camera_release → UNAVAILABLE（LoadState.UNAVAILABLE=2）")
	check_eq(bool(save.get_settings()["gesture_camera_enabled"]), false,
		"V-C4 等价替换：确认 → 存档 gesture_camera_enabled=false")
	game.attach_strip(null)   # 摘除替身（段 3~4 基线：未挂接态与改前一致）
	strip2.free()
	# ---- 批次 U（U4-②，spec §4-U4）：Q3=RELEASE_CAMERA（2 checks）----
	var lq3 := _ctrl_listener()
	bridge.request_camera_release()
	await _wait_available(lq3, 4)
	var cmds_q3 := _recv_cmds(lq3)
	check(cmds_q3.has("RELEASE_CAMERA"), "U4：Q3 → 控制通道逐字 RELEASE_CAMERA（旧 SHUTDOWN 废止；实际 %s）" % [cmds_q3])
	check(not cmds_q3.has("SHUTDOWN"), "U4：Q3 不发 SHUTDOWN（stop_gesture_process 不再调用，进程与三端口常驻）")
	if lq3 != null:
		lq3.close()
	# ---- 段 3. T11 Q1 回归（2 checks）----
	gt.set_pressed_no_signal(true)
	gt.toggled.emit(true)
	# 批次 U 等价替换（U1，spec §4-U1-1）：两态文案统一「摄像头」＋Q1 亮态不再 disabled
	check((not ct.disabled) and String(ct.text) == "摄像头" and bool(ct.button_pressed),
		"U1：Q1 亮态可点、文本「摄像头」（旧 disabled＋「跟随手势」废止）")
	check(bool(panel.get_node("Panel/VBox/OptionsBox/CameraRow/ArrowBtn").visible),
		"T12：箭头钮不随 Q1 置灰（常显，spec §4-12-1）")
	panel.queue_free()
	await process_frame
	# ---- 段 4. T11 toast 双分支 helper（3 checks）----
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(main)
	await process_frame
	await process_frame
	check(main.has_method("_unavailable_toast_text"), "T11：main.gd _unavailable_toast_text helper 存在（T-A 契约）")
	check_eq(String(main.call("_unavailable_toast_text")), "摄像头暂未打开，已切换键鼠操作",
		"T11：gesture_input=true → 全文案（键鼠降级语义）")
	save.update_settings({"gesture_input": false})
	check_eq(String(main.call("_unavailable_toast_text")), "摄像头暂未打开",
		"T11：gesture_input=false → 短文案（仅摄像头态无降级语义）")
	save.update_settings({"gesture_input": true})
	# ---- 段 5. S14 toast 行为承接（原 ui_cleanup 段 3 移交留痕，10 checks——复核终改④；P1-4 修正：
	# 沿用 ui_cleanup 同款 _center_box 私有成员 + 三层取 Label（ToastCenter→卡→盒→Label），
	# 并补承接「consume 标志已被 main 消费」断言——原段 3 实数 10 条的完整等价移交）。
	# 批次 V-B2 等价替换留痕（批次 V-C1 波及，spec §3.4）：Game.toast(centered=true) 单点改道
	# TopStrip.push_info（独立层 63）→ ToastCenter 中央锚点盒不再承接中央提示，旧 _center_box
	# 断言恒空（基线实测 SCRIPT ERROR 挂死）。落点等价迁移：StripProbe 替身经 Game.attach_strip
	# 注入捕获 push_info 调用（text/seconds 双参），断言条数 10 条不变。
	var strip_probe := StripProbe.new()
	game.attach_strip(strip_probe)
	main.set("_gesture_unavailable_toasted", false)
	# T-F 落地适配（ui_cleanup 段 3 同款手法）：段 2 的 Q3 stop 已把 bridge 置 UNAVAILABLE(2)，
	# 直置 _set_state(2) 会因「状态未变不发信号」成 no-op；且 main._process 每帧 flush pending
	# （main.gd :134-135）已发过一张卡——先清中央盒再复位 READY，使下方 UNAVAILABLE 迁移真实发生。
	(main.get_node("GlobalUI/ToastCenter") as Node).call("clear_all")
	bridge._set_state(1)
	bridge._set_state(2)   # UNAVAILABLE（主菜单态）
	await process_frame
	check_eq(strip_probe.pushes.size(), 1, "S14（等价替换）：UNAVAILABLE → TopStrip info 条恰 1 条（旧：中央锚点盒恰 1 卡）")
	if strip_probe.pushes.size() >= 1:   # 坑1 防御：红态不越界
		check_eq(String(strip_probe.pushes[0][0]), "摄像头暂未打开，已切换键鼠操作",
			"S14（等价替换）：toast 文案终态（默认设置=全文案分支）")
	bridge._set_state(0)
	await process_frame
	bridge._set_state(2)
	await process_frame
	check_eq(strip_probe.pushes.size(), 1, "S14（等价替换）：重复 UNAVAILABLE 不再发（一次/episode 去重沿用）")
	main.set("_gesture_unavailable_toasted", false)
	# T-F 落地适配（ui_cleanup :106 同款）：上块 toast 卡 2.5s 内未过期，先清盒再验「主动关零 toast」。
	(main.get_node("GlobalUI/ToastCenter") as Node).call("clear_all")
	bridge._set_state(1)   # 复位 READY（同上——防状态已在 UNAVAILABLE 时 _set_state(2) 成 no-op）
	bridge._intentional_stop = true
	bridge._set_state(2)
	await process_frame
	check(not bool(main.get("_gesture_unavailable_toasted")), "S14（移交）：主动关（Q3）→ 不置 toast 标志")
	check_eq(bool(bridge.consume_intentional_stop()), false, "S14（移交）：标志已被 main 消费（取走即清，P1-4 补承接）")
	check_eq(strip_probe.pushes.size(), 1, "S14（等价替换）：主动关 → 零 toast（info 条仍 1 条不新增）")
	main.set("_gesture_unavailable_toasted", false)
	game.goto_state(game.State.CATALOG)
	bridge._set_state(1)   # 复位 READY（同上）
	bridge._set_state(2)
	await process_frame
	check(bool(main.get("_gesture_unavailable_pending")) and not bool(main.get("_gesture_unavailable_toasted")),
		"S14（移交）：非主菜单发生 → 置待发标志（P2-3 口径沿用）")
	check_eq(strip_probe.pushes.size(), 1, "S14（等价替换）：非主菜单期零 toast（info 条仍 1 条不新增）")
	game.goto_state(game.State.MAIN_MENU)
	main.call("_flush_pending_unavailable_toast")
	check_eq(strip_probe.pushes.size(), 2, "S14（等价替换）：回主菜单 → 补发一张（info 条第 2 条）")
	if strip_probe.pushes.size() >= 2:
		check_eq(String(strip_probe.pushes[1][0]), "摄像头暂未打开，已切换键鼠操作",
			"S14（等价替换）：补发 toast 同文案（P1-4 补承接，默认设置=全文案分支）")
	game.attach_strip(null)   # 摘除替身（复位路由）
	strip_probe.free()
	main.queue_free()
	await process_frame
	# ---- 段 6. ArrowBtn 结构（3 checks）----
	var panel2: Control = await _init_panel()
	var ab: Button = panel2.get_node("Panel/VBox/OptionsBox/CameraRow/ArrowBtn")
	check(ab != null and ab.custom_minimum_size == Vector2(24, 24), "T12：ArrowBtn 24×24（ExclaimBtn 原位替换）")
	check_eq(String(ab.text), "▾", "T12：文本「▾」朝下箭头（大于号旋转朝下视觉等价物）")
	check(panel2.get_node_or_null("Panel/VBox/OptionsBox/CameraRow/ExclaimBtn") == null,
		"T12/T13：ExclaimBtn 已删（等价替换留痕）")
	# ---- 段 7. CameraMenu 状态机（6 checks）----
	# 批次 U 等价替换①（UD-6 迁层留痕）：宿主迁独立层 65 → 路径 CameraMenuPopup/… 前增 CameraMenuLayer/
	var menu: Control = panel2.get_node("CameraMenuLayer/CameraMenuPopup/CameraMenu")
	check(menu != null, "T12：CameraMenuPopup/CameraMenu 已挂载（settings_panel.tscn）")
	bridge._camera_enum = {"cameras": [{"id": 0, "name": "CamX"}, {"id": 1, "name": "CamY"}], "current_camera": 0}
	bridge._camera_matrix = {"resolutions": [[1280, 720], [640, 480]], "fps_options": [30]}
	bridge._camera_errors = []
	menu.call("open_menu")   # 缓存有值 → 直进 LOADED（P1-1 零等待）
	check_eq(int(menu.get("state")), 2, "T12：缓存直进 LOADED（MenuState.LOADED=2，不经 LOADING/不等 8s）")
	check_eq((menu.get("_rows") as Array).size(), 2, "T12：设备列表 2 行")
	bridge._camera_enum = {}
	var menu2: Control = (load(PANEL_SCENE).instantiate().get_node("CameraMenuLayer/CameraMenuPopup/CameraMenu"))
	check_eq(int(menu2.get("state")), 1, "T12：无缓存初始 LOADING（MenuState.LOADING=1）")
	menu2.set("_open_at", Time.get_ticks_msec() / 1000.0 - 9.0)
	menu2.call("_check_timeout")
	check_eq(int(menu2.get("state")), 0, "T12：8s 超时 → EMPTY（MenuState.EMPTY=0，ENUM_TIMEOUT）")
	check_eq(String((menu2.get("_root_box").get_child(0) as Label).text), "未检测到摄像头",
		"T12：EMPTY 文案逐字")
	menu2.free()
	# T-F 落地适配：段 7 为 menu2 初始态检查清空了 _camera_enum，但 menu2 的 LOADING 初值实读成员
	# 初始化器（未入树不跑 open_menu）——此处恢复缓存夹具，供段 8 重建列表/段 9 open_menu 依
	# P1-1 契约直读缓存（plan 段 8/9 的 open_menu 重建与取行前置条件）。
	bridge._camera_enum = {"cameras": [{"id": 0, "name": "CamX"}, {"id": 1, "name": "CamY"}], "current_camera": 0}
	# ---- 段 8. hover 子列与置灰（6 checks）----
	menu.call("_open_res_sub", 0, (menu.get("_rows")[0] as Control))
	var res_sub: PopupPanel = menu.get("_res_sub")
	# P2⑤：无头下 PopupPanel（独立 Window）popup 后 visible 可能恒 false（无头窗口虚拟化）——
	# 若实跑出现该形态属平台语义非缺陷：备案改断 _res_sub != null + 子项结构（实施时按实测定）
	check(res_sub != null and (res_sub.visible or DisplayServer.get_name() == "headless"),
		"T12：hover 设备项 → 分辨率子列弹出（无头 Window 虚拟化豁免备案见上注）")
	var res_texts: Array = []
	for c: Node in res_sub.get_child(0).get_children():
		if c is Button:
			res_texts.append(String((c as Button).text))
	check(res_texts == ["1280x720", "640x480"], "T12：分辨率子列逐项 W×H 逐字")
	bridge._camera_matrix = {"resolutions": [], "fps_options": [30]}
	menu.call("_open_res_sub", 0, (menu.get("_rows")[0] as Control))
	var res_sub2: PopupPanel = menu.get("_res_sub")
	var lone: Button = res_sub2.get_child(0).get_child(0)
	# 批次 U 等价替换（U2，磁盘实况：UD-7 后「不支持」概念并入检测失败态——ok 缺省视为 true
	# 但 resolutions 空仍走失败单行；旧「不支持」文案废止）
	check_eq(String(lone.text), "检测失败（设备无法打开）", "U2：resolutions 空 → 单行「检测失败（设备无法打开）」（旧「不支持」等价替换）")
	check(lone.disabled, "U2：检测失败置灰不可点（旧「不支持」置灰语义沿用）")
	bridge._camera_errors = [1]
	menu.call("open_menu")   # 重建列表（error id=1 → CamY 行置灰）
	var row1: Button = (menu.get("_rows")[1] as Button)
	check(row1.disabled and String(row1.text).contains("无法打开"),
		"T12：camera_error 设备整行 disabled+后缀「无法打开」")
	bridge._camera_errors = []
	bridge._camera_matrix = {"resolutions": [[1280, 720]], "fps_options": []}
	menu.call("_open_res_sub", 0, (menu.get("_rows")[0] as Control))
	menu.call("_open_fps_sub", 0, (menu.get("_rows")[0] as Control))   # 批次 X P3-b 签名等价替换：(cam_id, 设备行锚)
	check(menu.get("_fps_sub") == null, "T12：fps_options 空 → 帧率子列不弹出（降级口径）")
	# ---- 段 9. send_control 命令逐字（4 checks；9878 回环监听，端口竞争单跑甄别 §1.4）----
	var listener := PacketPeerUDP.new()
	check_eq(listener.bind(bridge.get_control_port()), 0, "T12 前置：9878 回环监听绑定成功（占用即环境性失败）")
	bridge._camera_matrix = {"resolutions": [[1280, 720]], "fps_options": [60]}
	menu.call("open_menu")
	# 批次 V-B2 等价替换留痕（V4，spec §6.1）：rows[0]（id0==current_camera）系当前设备行——
	# 点按 no-op 化（不发 SWITCH、零写档、不闪）；旧断言「rows[0] 点击 → SWITCH_CAMERA:0 逐字」
	# 迁移为「当前行零发送 + 非当前行 rows[1] → SWITCH_CAMERA:1 逐字」，断言数 1→3（只增不减）。
	# 存档零写入判据用前后快照（V-D 落地后 device 键恒在场（String ""=未记忆），「键不出现」判据失效）
	var dev_before9: Variant = save.get_settings().get("gesture_camera_device", "ABSENT")
	(menu.get("_rows")[0] as Button).pressed.emit()          # 点当前设备项 ×2（V4 no-op）
	(menu.get("_rows")[0] as Button).pressed.emit()
	var cmd0 := ""
	for i: int in 30:
		if listener.get_available_packet_count() > 0:
			cmd0 = listener.get_packet().get_string_from_utf8()
			break
		await process_frame
	check_eq(cmd0, "", "V4：点当前设备项连点 → no-op 零发送（SWITCH_CAMERA 不发出；批次 V-B2 新增）")
	check_eq(str(save.get_settings().get("gesture_camera_device", "ABSENT")), str(dev_before9),
		"V4：同设备连点存档零写入（gesture_camera_device 值不变；批次 V-B2 新增）")
	(menu.get("_rows")[1] as Button).pressed.emit()          # 点非当前设备项 → 照发
	var cmd0b := ""
	for i: int in 30:
		if listener.get_available_packet_count() > 0:
			cmd0b = listener.get_packet().get_string_from_utf8()
			break
		await process_frame
	check_eq(cmd0b, "START_CAMERA_BY_NAME:%s" % str(save.get_settings().get("gesture_camera_device", "")),
		"AD 等价替换（旧 T12/V-B2「SWITCH_CAMERA:1」）：点非当前设备项 → 按写档显示名逐字下发启动指令（行点击写档 gesture_camera_device=显示名；实际 %s）" % [cmd0b])
	var res_btn: Button = null
	menu.call("_open_res_sub", 0, (menu.get("_rows")[0] as Control))
	for c: Node in (menu.get("_res_sub") as PopupPanel).get_child(0).get_children():
		if c is Button and String((c as Button).text) == "1280x720":
			res_btn = c
	res_btn.pressed.emit()
	var cmd1 := ""
	for i: int in 30:
		if listener.get_available_packet_count() > 0:
			cmd1 = listener.get_packet().get_string_from_utf8()
			break
		await process_frame
	check_eq(cmd1, "SET_RESOLUTION:0:1280x720", "T12/U2：点分辨率 → SET_RESOLUTION:0:1280x720 逐字（批次 U 等价替换：3 参 <id>:<w>x<h>，旧 2 参废止）")
	bridge._camera_matrix = {"resolutions": [[1280, 720]], "fps_options": [60]}
	menu.call("_open_res_sub", 0, (menu.get("_rows")[0] as Control))
	menu.call("_open_fps_sub", 0, (menu.get("_rows")[0] as Control))   # 批次 X P3-b 签名等价替换（重建 fps 列重算选中态）
	var fps_btn: Button = (menu.get("_fps_sub").get_child(0).get_child(0) as Button)
	fps_btn.pressed.emit()
	var cmd2 := ""
	for i: int in 30:
		if listener.get_available_packet_count() > 0:
			cmd2 = listener.get_packet().get_string_from_utf8()
			break
		await process_frame
	check_eq(cmd2, "SET_FPS:0:60", "T12/U2：点帧率 → SET_FPS:0:60 逐字（批次 U 等价替换：3 参 <id>:<n>，旧 2 参废止）")
	listener.close()
	# ---- 段 9b. RV-2 回修锁（P1-1 预热 + P1-2 谓词收起，7 checks；窗口实弹另证
	#      tf_spike2c：warp 真实鼠标入箱 KEEPALIVE=true/移出 CLOSED=true/父弹窗全程存活）----
	bridge._camera_enum = {}
	bridge._intentional_stop = true
	menu.call("open_menu")   # 无缓存 → LOADING 分支（P1-1 预热路径）
	check_eq(int(menu.get("state")), 1, "T12 P1-1：无缓存 open_menu → LOADING（预热分支）")
	check_eq(bool(bridge.get("_intentional_stop")), false, "T12 P1-1：无缓存开下拉 → start_gesture_process 被调用（探针=入口清 _intentional_stop，spec §4-T12-2）")
	menu.call("_open_res_sub", 0, (panel2.get_node("Panel") as Control))   # 锚仅用于定位算术，用面板节点规避 LOADING 态空 _rows
	await process_frame
	await process_frame   # 等 popup 子树布局（无头 box 全局矩形非零，探针实测 P(4,4) S(92,92)）
	var res_box: Control = menu.get("_res_box")
	check(res_box != null, "T12 P1-2：_res_box 内容容器已存引（谓词矩形数据源；PopupPanel 系 Window 无 get_global_rect）")
	var brect: Rect2 = res_box.get_global_rect()
	check(menu.call("_res_sub_contains_mouse", brect.position + brect.size * 0.5),
		"T12 P1-2：矩形内点（中心）→ 谓词含（保活分支前提）")
	check(not menu.call("_res_sub_contains_mouse", brect.position + brect.size * 0.5 + Vector2(5000, 5000)),
		"T12 P1-2：矩形外点 → 谓词不含（负例）")
	menu.call("_close_res_if_outside", brect.position + brect.size * 0.5)
	check(menu.get("_res_sub") != null, "T12 P1-2：鼠标在子列内 → 帧末谓词保活（行→子列 hover 途经 mouse_exited 不再自毁子列，RV-2 P1-2 (b) 案）")
	menu.call("_close_res_if_outside", brect.position + brect.size * 0.5 + Vector2(5000, 5000))
	check(menu.get("_res_sub") == null, "T12 P1-2：鼠标在子列外 → 移出即收（原口径保持）")
	# FV-1 P2-1：close_res 连带收 fps + fps 层同享谓词保活（2 checks；连带收起后行→fps 直穿
	# 途经 res 按钮 mouse_exited 时鼠标已在 fps 子列，谓词必须扩为 res 框∪fps 框防 fps 不可达）
	# 批次 U 夹具适配：段 9b 头部清空过 _camera_enum——_open_fps_sub 的 current 回落判定需枚举
	# 夹具在场（否则 0 号直读路径判定失效、fps 列为空返回致 _fps_box=null），此处恢复（:206 同款手法）。
	bridge._camera_enum = {"cameras": [{"id": 0, "name": "CamX"}, {"id": 1, "name": "CamY"}], "current_camera": 0}
	menu.call("_open_res_sub", 0, (panel2.get_node("Panel") as Control))
	await process_frame
	await process_frame
	menu.call("_open_fps_sub", 0, (panel2.get_node("Panel") as Control))   # 批次 X P3-b 签名等价替换（设备行锚= res 子列同锚）
	await process_frame
	await process_frame   # fps box 布局同 res box（无头虚拟窗口下矩形非零）
	var fps_box: Control = menu.get("_fps_box")
	var frect: Rect2 = fps_box.get_global_rect()
	menu.call("_close_res_if_outside", frect.position + frect.size * 0.5)
	check(menu.get("_res_sub") != null and menu.get("_fps_sub") != null,
		"T12 FV-1：鼠标在 fps 子列 → 谓词保活（连带收起后行→fps 直穿不误杀，res+fps 双活）")
	menu.call("_close_res")
	check(menu.get("_res_sub") == null and menu.get("_fps_sub") == null,
		"T12 FV-1：close_res 连带收 fps（移出分辨率列/切设备行不残留孤儿）")
	# ---- 批次 U（U2/U3，子菜单惰性探测＋3 参命令＋象限门控，19 checks）----
	# 磁盘实况适配留痕：①计划原文本段重声明 var menu——与段 7 既有同名冲突（GDScript 同函数
	# 作用域禁止重复声明），复用段 7 的 menu（路径已同）；②段 9 既有 res_btn/fps_btn/res_texts
	# 声明——本段同名变量加 _u 后缀避让；③段 9b 清空过 _camera_enum——id==current 直读分支前
	# 恢复夹具（:145-148 T-F 落地适配同款手法）。
	check_eq(float(menu.PROBE_TIMEOUT), 8.0, "U2：PROBE_TIMEOUT=8.0s 常量锚（spec §5）")
	# 三态①「检测中…」：缓存空 → hover 非 current 设备行
	bridge._probe_matrix_cache.clear()
	# 批次 W4-N9 等价改写（W6 回归甄别）：前序段对非 current id 的 _open_res_sub 探测置位
	# 桥侧探测在飞互斥标志且测试内无 probe_result 回包（生产由 P2-A 超时/回包回收）——本段
	# 「缓存空 → 检测中…+发出」验证需先显式回收在飞标志；互斥/超时语义本体由
	# test_w_camera_button A3/A4 与 test_w_bridge_lifecycle D4 锁定。
	get_root().get_node("GestureBridge").set("_probe_in_flight", false)
	get_root().get_node("GestureBridge").set("_probe_sent_at_ms", -1)
	menu._on_enum([{"id": 0, "name": "A"}, {"id": 1, "name": "B"}], 0)
	await process_frame
	var rows: Array = menu._rows
	check_eq(rows.size(), 2, "U2：设备列表两行（夹具）")
	var l5 := _ctrl_listener()
	menu._open_res_sub(1, rows[1])
	await process_frame
	var pending_texts: Array = []
	for b5: Variant in menu._res_box.get_children():
		pending_texts.append(String((b5 as Button).text))
	check(pending_texts.has("检测中…"), "U2：id≠current 无缓存 → 「检测中…」（惰性异步探测）")
	await _wait_available(l5, 4)
	var cmds_probe := _recv_cmds(l5)
	check(cmds_probe.has("PROBE_MATRIX:1"), "U2：PROBE_MATRIX:1 命令逐字（实际 %s）" % [cmds_probe])
	menu._close_res()
	# 批次 AD-5d（P2-B）夹具适配：本断言专测「同 id 1s 节流」→ 先复位一次性探测账，使二次
	# hover 的拦截**只能**来自节流（否则会话账会顶替节流、断言退化为恒真假绿；断言语义不变）。
	menu.set("_auto_probe_attempted", {})
	menu._open_res_sub(1, rows[1])
	var thr_ok: bool = true
	await _wait_available(l5, 4)
	for c5: String in _recv_cmds(l5):
		if c5 == "PROBE_MATRIX:1":
			thr_ok = false
	check(thr_ok, "U2：同 id 1s 内节流——二次 hover 不重发 PROBE_MATRIX（PROBE_REQUEST_THROTTLE_MS=1000）")
	if l5 != null:
		l5.close()
	# 三态②矩阵列出：probe_result 到达 → 刷新
	bridge.simulate_packet(JSON.stringify({"type": "probe_result", "id": 1, "ok": true, "resolutions": [[1280, 720], [640, 480]], "fps_options": [30, 60]}))
	await process_frame
	menu._open_res_sub(1, rows[1])
	await process_frame
	var res_texts_u: Array = []
	for b6: Variant in menu._res_box.get_children():
		res_texts_u.append(String((b6 as Button).text))
	check(res_texts_u.has("1280x720") and res_texts_u.has("640x480"), "U2：probe_result 到达 → 矩阵列出（检测中消失）")
	# 三态③检测失败：ok=false → 置灰单行
	bridge.simulate_packet(JSON.stringify({"type": "probe_result", "id": 2, "ok": false}))
	menu._open_res_sub(2, rows[0])
	await process_frame
	var fail_btn: Button = menu._res_box.get_child(0)
	check_eq(String(fail_btn.text), "检测失败（设备无法打开）", "U2：ok=false → 「检测失败（设备无法打开）」")
	check(bool(fail_btn.disabled), "U2：检测失败置灰（PROBE_TIMEOUT 超时同态）")
	menu._close_res()
	# id==current 分支（双审 P2-6 → 批次 AD-5c 条件探测等价改写，旧值留痕）：
	# 旧断言「直读 init#2 全局矩阵零探测」（not has(PROBE_MATRIX:0)）随 AD-5b 播种（全局仅
	# 1 档）废止——缓存不充分（≤1 档）即按需发 PROBE_MATRIX:0；「充分（≥2 档）→ 零探测」的
	# P2-6 原意保持，断言迁至 test_ad_batch5b M2-6（防自探自败由 Python 侧 pid==current
	# live 复用路径消解）。断言前显式复位菜单节流/桥在飞/探测缓存/**一次性探测账**（批次 AD-5d
	# P2-B 新增——前序段已对 id==current 自动探过，不复位则会话账吞掉本请求致假红）——不复位则发送
	# 与否取决于前序段的互斥与节流副作用（假红/假绿）。
	bridge._camera_enum = {"cameras": [{"id": 0, "name": "A"}, {"id": 1, "name": "B"}], "current_camera": 0}
	bridge._camera_matrix = {"resolutions": [[1280, 720]], "fps_options": [60]}   # 旧夹具值（1 档=播种形态→不充分）
	bridge._probe_matrix_cache.erase(0)   # 只清 current id 条目——整表 clear 会连带清掉 id=1 的既有 probe 结果（后文 3 参命令段依赖）
	bridge._probe_in_flight = false
	bridge._probe_sent_at_ms = -1
	menu.set("_probe_requested_at", {})
	menu.set("_auto_probe_attempted", {})
	var l6 := _ctrl_listener()
	menu._open_res_sub(0, rows[0])
	await _wait_available(l6, 4)
	var cmds_cur := _recv_cmds(l6)
	check(cmds_cur.has("PROBE_MATRIX:0"), "U2：id==current 缓存不充分（≤1 档）→ 按需发 PROBE_MATRIX:0（AD-5c 条件探测；旧「零探测」断言废止留痕；实际 %s）" % [cmds_cur])
	if l6 != null:
		l6.close()
	menu._close_res()
	# 3 参命令逐字（3 checks）
	var lr := _ctrl_listener()
	var res_btn_u: Button = null
	menu._open_res_sub(1, rows[1])
	await process_frame
	for b7: Variant in menu._res_box.get_children():
		if String((b7 as Button).text) == "1280x720":
			res_btn_u = b7
	res_btn_u.pressed.emit()
	await _wait_available(lr, 4)
	check(_recv_cmds(lr).has("SET_RESOLUTION:1:1280x720"), "U2：3 参 SET_RESOLUTION:1:1280x720 逐字")
	menu._open_fps_sub(1, rows[1])   # 批次 X P3-b 签名等价替换：(cam_id, 设备行锚)（旧 3 参 res 行锚废止）
	await process_frame
	var fps_btn_u: Button = menu._fps_box.get_child(0)
	fps_btn_u.pressed.emit()
	await _wait_available(lr, 4)
	check(_recv_cmds(lr).has("SET_FPS:1:30"), "U2：3 参 SET_FPS:1:30 逐字（完成后 _send_init2 既有）")
	bridge.send_control("SET_RESOLUTION:640x480")
	await _wait_available(lr, 4)
	check(_recv_cmds(lr).has("SET_RESOLUTION:640x480"), "U2：2 参旧式保留兼容（语义=对当前设备）")
	if lr != null:
		lr.close()
	menu._close_res()
	# CamTip 不吞点击（2 checks；双审回修 P1-2：push_input 实弹替代 gui_find_control）——段 6 由 test_u_hover_tip 深测，此处守 settings 侧联动
	var ct2: Button = panel2.get_node("Panel/VBox/OptionsBox/CameraRow/CameraToggle")
	var clicked3: Array = []
	ct2.pressed.connect(func() -> void: clicked3.append(1))
	# 批次 W4-N5 等价改写（W6 回归甄别）：手势开时点击摄像头钮，桥非 READY 态 → 打开进
	# OPENING（旧语义=「无法关闭」info+复位亮态）——本段意图为「点击可达（CamTip 不吞点击）」，
	# 注入 READY+未主动关使点击回归旧路径（Q2 切换语义由 test_v_settings_camera_flow 行①-④
	# 真值表锁定）；注入前快照、断言后还原。
	var _gb2_state: int = int(_bridge.get_load_state())
	var _gb2_released: bool = bool(_bridge.get("_intentional_stop"))
	_bridge.set("_intentional_stop", false)
	_bridge._set_state(1)   # READY
	# 批次 Y（Y-A17/㉔）等价注入：info 路径判据=「摄像头流真实开启」——注入开启真值使点击
	# 回归 info 路径（否则流未开 → 打开进 OPENING，:568 文案断言会被「打开中」污染）
	_bridge.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "CamX"}))
	await process_frame
	_click_at(ct2.get_global_rect().get_center())
	await process_frame
	check(clicked3.size() >= 1, "U2：CamTip 迁移后摄像头开关合成点击命中（tip 矩形下按钮可点击；N5 下桥 READY=info 路径零态变，W6 等价改写留痕）")
	check(sp_hovertip_count(panel2) >= 1, "U2：settings_panel 挂 HoverTip（CamTip 私有件废止）")
	_bridge._set_state(_gb2_state)
	_bridge.set("_intentional_stop", _gb2_released)
	# 四象限×悬浮组合表（4 checks）＋两态文本（1；双审回修④删 arrow 留痕恒真断言——arrow 绑定删除
	# 留痕由 UD-6 Step 5 源码级删除＋走查 g 项实弹覆盖）
	var tip_node: PanelContainer = null
	for n11: Variant in panel2.find_children("*", "PanelContainer", true, false):
		if (n11 as Node).get_script() == load("res://scenes/shared/hover_tip.gd"):
			tip_node = n11
	for quad: Array in [[true, true, false], [false, true, true], [true, false, false], [false, false, false]]:
		save.update_settings({"gesture_input": quad[0], "gesture_camera_enabled": quad[1]})
		var shown: bool = bool(tip_node._enabled.call())
		check_eq(shown, bool(quad[2]), "U3：Q 态 input=%s cam=%s → tip %s（表驱动）" % [quad[0], quad[1], quad[2]])
	check_eq(String(ct2.text), "摄像头", "U1：Q2 态文本「摄像头」（两态统一）")
	save.update_settings({"gesture_input": false, "gesture_camera_enabled": false})   # 点击副作用还原（Q4 基线）
	# ---- 段 10. T13 悬浮说明窗（批次 U 等价替换：CamTip 私有件废止 → HoverTip 共享组件，7 checks 净 0）----
	# 旧断言→等价目标对照：①挂载且默认隐藏→HoverTip 同判；②_on_camera_hover(true)→显示→
	# Q2 谓词＋provider 注入逐帧判定（UD-6 后生产路径无 _on_camera_hover 可调）；③文案逐字→
	# 子 Label；④autowrap→子 Label；⑤宽钳→mouse_filter IGNORE（宽钳行为由 HoverTip MAX_WIDTH
	# 承接、test_u_hover_tip 段 2 已锁）；⑥_tip_should_show 负例→provider 远点隐藏（无保活矩形）；
	# ⑦GlassDialog 源残留断言原样保留。本段置于四象限表之后（setup 覆写不反噬生产谓词断言）。
	var tip_ref: GDScript = load("res://scenes/shared/hover_tip.gd")
	var tip: PanelContainer = null
	for n10: Variant in panel2.find_children("*", "PanelContainer", true, false):
		if (n10 as Node).get_script() == tip_ref:
			tip = n10
			break
	check(tip != null and not tip.visible, "T13（等价）：HoverTip 挂载且默认隐藏（旧 CamTip 节点废止）")
	check_eq(int(tip.mouse_filter), Control.MOUSE_FILTER_IGNORE,
		"U7-4：mouse_filter 等价断言（旧 CamTip mouse_filter=0 STOP 根因废止 → IGNORE）")
	check_eq(String((tip.get_child(0) as Label).text), CAM_TIP_TEXT,
		"U7-4：CamTip 文案逐字保留（挂接点 CamTip/CamTipLabel → HoverTip 子 Label，旧路径留痕）")
	check_eq(int((tip.get_child(0) as Label).autowrap_mode), int(TextServer.AUTOWRAP_WORD_SMART),
		"U7-4：autowrap 等价断言（旧 CamTipLabel autowrap_mode=3；PanelContainer 宽钳由 HoverTip MAX_WIDTH 承接）")
	# Q2 态 + 指针在摄像头开关上 → 显示（Q2 前置经 update_settings 注入，provider 合成光标位）
	var ct10: Button = panel2.get_node("Panel/VBox/OptionsBox/CameraRow/CameraToggle")
	var ct_rect: Rect2 = ct10.get_global_rect()
	save.update_settings({"gesture_input": false, "gesture_camera_enabled": true})
	tip.setup(ct10, CAM_TIP_TEXT, Callable(), func() -> Variant: return ct_rect.get_center())
	tip._process(0.016)
	await process_frame
	check(tip.visible, "U3/U7-4：Q2 态指针悬浮摄像头开关 → tip 显示（旧 hover→显示 等价）")
	tip.setup(ct10, CAM_TIP_TEXT, Callable(), func() -> Variant: return Vector2(5, 5))
	tip._process(0.016)
	await process_frame
	check(not tip.visible, "U2-1：指针移出宿主 → 隐藏（旧 _tip_should_show 双区域保活负例等价——无保活矩形）")
	save.update_settings({"gesture_input": true, "gesture_camera_enabled": true})   # 还原默认档（Q1 基线）
	var src: String = FileAccess.get_file_as_string("res://scenes/settings/settings_panel.gd")
	check(not src.contains("_on_exclaim_pressed") and not src.contains("_cam_dialog"),
		"T13：旧 GlassDialog 说明框路径已删（_on_exclaim_pressed/_cam_dialog 残留断言）")
	panel2.queue_free()
	await process_frame
	finish()
