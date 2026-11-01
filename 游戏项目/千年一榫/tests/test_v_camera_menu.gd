extends "res://tests/test_base.gd"
## 批次 V-B2（V1/V2/V3/V4/V16/V17，spec §6.1/§6.2/§6.4）：摄像头菜单棕化+选中态+同设备 no-op
## +矩阵等待态 8s 超时+成功清灰+选择写档+桥设备记忆优先+camera_error 提示
##（批次 Z Z4-④：桥自动回落抢句柄退役——恒零回落 SWITCH）。TDD 红→绿。
## 夹具（test_u_bridge_protocol 同款手法）：菜单段用 GestureBridge autoload（camera_menu 静态引用
## 该单例，直操其私有缓存注入枚举/矩阵）；桥段用 Bridge.new() 独立实例＋_simulate_start_ok 接缝；
## 控制命令捕获=9878 回环 listener bind。零摄像头纪律：全程无头，不真拉起手势子进程。
## ⚠ 并行环境：9876/9877 被占属环境性假红，单跑甄别（批次 M/N12c 先例）。
## 清档纪律（tools/README_走查清档规范.md，批次V回修②P1-1 补齐）：起测前备份 user:// 真实
## 档案（save.json 及本测试可触及的 .tmp/.bak），终测逐字节还原并断言等价 + EVID 证据行；
## 还原后真实 autoload SaveManager load_game 重同步内存（规范第 2 条）。零摄像头。

const Bridge := preload("res://autoload/gesture_bridge.gd")

const SAVE_PATH := "user://save.json"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"
# 备份路径必须带全 user:// 前缀（test_n10/test_v_save_domain 先例）——实测相对路径在
# FileAccess/DirAccess 间解析不一致（copy 落工程根进程 cwd、file_exists 又随 API 漂移），
# 前缀缺失=备份链静默失效。
const BK_PREFIX := "user://_vcm_backup_"
# 走查规范备份组（本测试不触碰 first_launch.flag——无 mark_first_launch 路径，不入组）
const WATCHED_PATHS: Array = [SAVE_PATH, TMP_PATH, BAK_PATH]

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
	print("EVID|user_restore|v_camera_menu|files=%d" % WATCHED_PATHS.size())

## 内联夹具：TopStrip 替身（记录 push_info 调用参数；Game.attach_strip 注入链路验证用，
## test_v_top_strip 同款手法）——Game.toast(centered=true) 改道消费方。
class StripProbe extends Node:
	var pushes: Array = []
	func push_info(text: String, seconds: float = 3.0) -> void:
		pushes.append([text, seconds])

var save: Node
var game: Node
var bridge: Node   # autoload 实例（菜单段数据源）

## 9878 回环监听（bind 失败=并行环境占用，单跑甄别）
func _ctrl_listener() -> PacketPeerUDP:
	var l := PacketPeerUDP.new()
	if l.bind(int(bridge.get_control_port())) != OK:
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

func _drain(listener: PacketPeerUDP) -> void:
	while listener != null and listener.get_available_packet_count() > 0:
		listener.get_packet()

func _make_menu() -> Control:
	var m: Control = (load("res://scenes/settings/camera_menu.gd") as GDScript).new()
	add_child(m)
	await process_frame
	return m

## 递归收集子树内全部 Label 文本（LOADING 行 Label 在 HBox 内，直取子级取不到）
func _label_texts(node: Node) -> Array:
	var out: Array = []
	for c: Variant in node.get_children():
		if c is Label:
			out.append(String((c as Label).text))
		out.append_array(_label_texts(c as Node))
	return out

func _initialize() -> void:
	print("== test_v_camera_menu ==")
	save = get_root().get_node("SaveManager")
	game = get_root().get_node("Game")
	bridge = get_root().get_node("GestureBridge")
	_backup_user()                     # 清档纪律：任何删/写档前备份真实档案
	for p: String in WATCHED_PATHS:
		_del(p)                        # 沙盒基线：真实档案已备份，测试域内全清
	save.load_game()

	# ================= 段 A. 删「加载完了」+ LOADING/EMPTY 保留（V1，spec §6.1）=================
	bridge._camera_enum = {"cameras": [{"id": 0, "name": "CamA"}, {"id": 1, "name": "CamB"}], "current_camera": 0}
	bridge._camera_matrix = {}
	bridge._camera_errors = []
	var menu: Control = await _make_menu()
	menu.call("open_menu")   # 缓存有值 → 直进 LOADED
	check_eq(int(menu.get("state")), 2, "V1：缓存直进 LOADED（MenuState.LOADED=2）")
	var head_texts: Array = _label_texts(menu.get("_root_box") as Node)
	check(not head_texts.has("加载完了"), "V1：LOADED 态无「加载完了」常驻文案（旧 head Label 删除；实际 %s）" % [head_texts])
	check_eq((menu.get("_rows") as Array).size(), 2, "V1：设备列表 2 行（删 head 后行构建不受影响）")
	var menu2: Control = await _make_menu()
	bridge._camera_enum = {}
	menu2.call("open_menu")   # 无缓存 → LOADING
	check_eq(int(menu2.get("state")), 1, "V1：无缓存 LOADING 保留（MenuState.LOADING=1）")
	var loading_txts: Array = _label_texts(menu2.get("_root_box") as Node)
	check(loading_txts.has("正在加载"), "V1：LOADING「正在加载」文案逐字保留（转圈态；实际 %s）" % [loading_txts])
	menu2.set("_open_at", Time.get_ticks_msec() / 1000.0 - 9.0)
	menu2.call("_check_timeout")
	check_eq(int(menu2.get("state")), 0, "V1：8s 超时 → EMPTY 保留（ENUM_TIMEOUT）")
	check_eq(String(((menu2.get("_root_box") as Container).get_child(0) as Label).text), "未检测到摄像头",
		"V1：EMPTY「未检测到摄像头」文案逐字保留")
	menu2.free()

	# ================= 段 B. 三级子列棕化：PopupPanel 主题/面板 StyleBox 显式注入（V2，spec §6.1）=================
	bridge._camera_enum = {"cameras": [{"id": 0, "name": "CamA"}, {"id": 1, "name": "CamB"}], "current_camera": 0}
	bridge._camera_matrix = {"resolutions": [[1280, 720], [640, 480]], "fps_options": [30, 60]}
	menu.call("open_menu")
	menu.call("_open_res_sub", 0, (menu.get("_rows")[0] as Control))
	var res_sub: PopupPanel = menu.get("_res_sub")
	check(res_sub != null and res_sub.theme != null, "V2：res 子列 PopupPanel 显式注入主题非空（坑4：Window 不跨主题传播；旧代码 theme=null）")
	check(res_sub != null and res_sub.has_theme_stylebox_override("panel"),
		"V2：res 子列面板 StyleBox 显式覆盖（棕档；旧代码无覆盖）")
	menu.call("_open_fps_sub", 0, (menu.get("_rows")[0] as Control))   # 批次 X P3-b 签名等价替换：(cam_id, anchor_row) 设备行阶梯锚（旧 3 参 (res, cam_id, res行) 废止）
	var fps_sub: PopupPanel = menu.get("_fps_sub")
	check(fps_sub != null and fps_sub.theme != null, "V2：fps 子列 PopupPanel 显式注入主题非空")
	check(fps_sub != null and fps_sub.has_theme_stylebox_override("panel"), "V2：fps 子列面板 StyleBox 显式覆盖")
	# 批次 AB-3：theme_changed 跟随断言随深浅主题机制删除退役——等价改写：句柄注入即
	# current_theme()（恒深色），信号无复辟反向锁。
	# ⚠ 编译窗纪律（U-D 实证）：本文件经 --script 于 autoload 全局名注册前编译——不得静态引用
	# ThemeManager（test_t_camera_device helpers 同款规避），经根节点定位。
	var tm: Node = get_root().get_node("ThemeManager")
	check(res_sub.theme == (tm as Node).call("current_theme"),
		"AB-3 等价改写：res 子列主题==ThemeManager.current_theme()（恒深色）")
	check(fps_sub.theme == (tm as Node).call("current_theme"), "AB-3：fps 子列同口径（恒深色）")
	check(not (tm as Node).has_signal("theme_changed"),
		"AB-3 反向锁：ThemeManager 无 theme_changed 信号（跟随订阅无复辟）")
	# 行按钮显式字体色（棕主题深浅双档：未选灰化）
	var row_unsel: Button = menu.get("_rows")[1]
	check(row_unsel.has_theme_color_override("font_color"), "V2：设备行显式字体色在场（旧代码无覆盖）")
	menu.call("_close_subs")

	# ================= 段 C. 选中态常亮高亮+同设备 no-op（V2/V4，spec §6.1）=================
	# 选中=枚举 current_camera 行：金棕淡底 StyleBox+字色提亮；未选灰化。
	# 批次 X P3-a（spec §4）判据改「几何一致+色差」：选中/未选 margin 逐值相等+size 逐值相等
	# （「变细」根除）+仅色差；旧「选中 override 在场/未选无覆盖」两判据废止留痕（未选行现注入
	# 灰底 override——探针 p3a_gray_probe_run1.log 对齐「全屏显示」常态档）。
	var row_sel: Button = menu.get("_rows")[0]     # id0==current_camera=0
	row_unsel = menu.get("_rows")[1]
	await process_frame
	await process_frame   # 行容器排序落位后再比几何（VBox deferred 排序，实证规律）
	var sb_sel_c: StyleBox = row_sel.get_theme_stylebox("normal")
	var sb_unsel_c: StyleBox = row_unsel.get_theme_stylebox("normal")
	var m_eq_c: bool = sb_sel_c != null and sb_unsel_c != null
	for s3: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		m_eq_c = m_eq_c and sb_sel_c.get_content_margin(s3) == sb_unsel_c.get_content_margin(s3)
	check(m_eq_c, "P3-a：选中/未选设备行 content margin 逐值相等（「变细」根除）")
	check_eq(row_sel.size, row_unsel.size, "P3-a：选中/未选设备行 size 逐值相等（几何一致）")
	# 4.7 API 注：Control 无 get_theme_color_override（Godot 3 遗名）——get_theme_color(name) 无参
	# theme_type 时优先返回本控件覆盖值，旧代码（无覆盖）回 theme 值 → 红/绿两态判据均成立。
	var c_sel: Variant = row_sel.get_theme_color("font_color")
	var c_unsel: Variant = row_unsel.get_theme_color("font_color")
	check(c_sel is Color and c_unsel is Color and not (c_sel as Color).is_equal_approx(c_unsel as Color),
		"V2/V4：选中行字色提亮≠未选行灰化（双覆盖且异色）")
	var bg_sel_c: Color = (sb_sel_c as StyleBoxFlat).bg_color if sb_sel_c is StyleBoxFlat else Color.BLACK
	var bg_unsel_c: Color = (sb_unsel_c as StyleBoxFlat).bg_color if sb_unsel_c is StyleBoxFlat else Color.WHITE
	check(not bg_sel_c.is_equal_approx(bg_unsel_c),
		"P3-a：选中/未选仅色差（金棕 vs 灰；实际 %s / %s）" % [bg_sel_c, bg_unsel_c])
	var lsn := _ctrl_listener()
	_drain(lsn)
	var dev_before: Variant = save.get_settings().get("gesture_camera_device", "ABSENT")
	for i: int in 3:
		row_sel.pressed.emit()   # 点同一设备（当前设备）×3
	await _wait_available(lsn, 4)
	var noop_cmds := _recv_cmds(lsn)
	var sw_noop := 0
	for cmd: String in noop_cmds:
		if String(cmd).begins_with("SWITCH_CAMERA"):
			sw_noop += 1
	check_eq(sw_noop, 0, "V4：同设备行连点 3 次 → SWITCH_CAMERA 发送次数 0（no-op；实际 %s）" % [noop_cmds])
	check_eq(save.get_settings().get("gesture_camera_device", "ABSENT"), dev_before,
		"V4：同设备连点存档零写入（gesture_camera_device 不出现/不变）")
	# 非当前设备行照发（行为回归锚：no-op 仅限同设备）
	row_unsel.pressed.emit()
	await _wait_available(lsn, 4)
	check(_recv_cmds(lsn).has("SWITCH_CAMERA:1"), "V4：非当前设备行点击照发 SWITCH_CAMERA:1（no-op 不误伤异设备）")

	# ================= 段 D. 分辨率/帧率子列同口径：选中态+写档+no-op（V2/V4/V17，spec §6.1/§6.2）=================
	bridge._camera_matrix = {"resolutions": [[1280, 720], [640, 480]], "fps_options": [30, 60]}
	menu.call("open_menu")
	menu.call("_open_res_sub", 0, (menu.get("_rows")[0] as Control))
	var res_btn640: Button = null
	var res_btn1280: Button = null
	for c3: Variant in ((menu.get("_res_sub") as PopupPanel).get_child(0) as Container).get_children():
		if c3 is Button and String((c3 as Button).text) == "640x480":
			res_btn640 = c3
		if c3 is Button and String((c3 as Button).text) == "1280x720":
			res_btn1280 = c3
	check(res_btn640 != null and res_btn1280 != null, "V17 前置：分辨率子列两行在场")
	_drain(lsn)
	res_btn640.pressed.emit()   # 选择 640x480（首次：非 no-op）
	await _wait_available(lsn, 4)
	check(_recv_cmds(lsn).has("SET_RESOLUTION:0:640x480"), "V17：分辨率选择 → SET_RESOLUTION:0:640x480 照发")
	check_eq(String(save.get_settings().get("gesture_camera_res", "")), "640x480",
		"V17：选择即写档 gesture_camera_res=640x480（键名/值）")
	menu.call("_open_res_sub", 0, (menu.get("_rows")[0] as Control))   # 重建子列（选中态随记忆重算）
	# 重建后旧按钮已随旧 _res_sub 队列释放——两钮引用必须重取（防 freed 实例调用）
	res_btn640 = null
	res_btn1280 = null
	for c4: Variant in ((menu.get("_res_sub") as PopupPanel).get_child(0) as Container).get_children():
		if c4 is Button and String((c4 as Button).text) == "640x480":
			res_btn640 = c4
		if c4 is Button and String((c4 as Button).text) == "1280x720":
			res_btn1280 = c4
	# 批次 X P3-a 判据改「几何一致+色差」：选中（记忆值匹配）行 vs 未选行 margin 逐值相等+size 相等+仅色差
	await process_frame
	await process_frame   # 子列行排序落位后再比几何
	var sb_res_sel: StyleBox = res_btn640.get_theme_stylebox("normal")
	var sb_res_unsel: StyleBox = res_btn1280.get_theme_stylebox("normal")
	var m_eq_res: bool = sb_res_sel != null and sb_res_unsel != null
	for s4: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		m_eq_res = m_eq_res and sb_res_sel.get_content_margin(s4) == sb_res_unsel.get_content_margin(s4)
	check(m_eq_res, "P3-a：分辨率子列选中/未选行 margin 逐值相等（「变细」根除）")
	check_eq(res_btn640.size, res_btn1280.size, "P3-a：分辨率子列选中/未选行 size 逐值相等（几何一致）")
	var bg_res_sel: Color = (sb_res_sel as StyleBoxFlat).bg_color if sb_res_sel is StyleBoxFlat else Color.BLACK
	var bg_res_unsel: Color = (sb_res_unsel as StyleBoxFlat).bg_color if sb_res_unsel is StyleBoxFlat else Color.WHITE
	check(not bg_res_sel.is_equal_approx(bg_res_unsel),
		"P3-a：分辨率子列选中/未选仅色差（实际 %s / %s）" % [bg_res_sel, bg_res_unsel])
	res_btn640.pressed.emit()   # 再点已选值
	await _wait_available(lsn, 4)
	var res_noop := false
	for cmd2: String in _recv_cmds(lsn):
		if String(cmd2).begins_with("SET_RESOLUTION"):
			res_noop = true
	check(not res_noop, "V4：分辨率子列同口径——再点已选值不重发 SET_RESOLUTION（no-op）")
	check_eq(String(save.get_settings().get("gesture_camera_res", "")), "640x480", "V4：已选值再点存档零写入")
	res_btn1280.pressed.emit()   # 改选另一值仍生效
	await _wait_available(lsn, 4)
	check(_recv_cmds(lsn).has("SET_RESOLUTION:0:1280x720"), "V4：改选不同值照发 SET_RESOLUTION:0:1280x720")
	check_eq(String(save.get_settings().get("gesture_camera_res", "")), "1280x720", "V17：改选写档 gesture_camera_res=1280x720")
	# 帧率子列
	menu.call("_open_fps_sub", 0, (menu.get("_rows")[0] as Control))   # 批次 X P3-b 签名等价替换
	var fps_btn30: Button = null
	for c5: Variant in ((menu.get("_fps_sub") as PopupPanel).get_child(0) as Container).get_children():
		if c5 is Button and String((c5 as Button).text) == "30":
			fps_btn30 = c5
	check(fps_btn30 != null and fps_btn30.has_theme_color_override("font_color"), "V2：帧率子列行显式字体色在场")
	_drain(lsn)
	fps_btn30.pressed.emit()
	await _wait_available(lsn, 4)
	check(_recv_cmds(lsn).has("SET_FPS:0:30"), "V17：帧率选择 → SET_FPS:0:30 照发")
	check_eq(int(save.get_settings().get("gesture_camera_fps", 0)), 30, "V17：选择即写档 gesture_camera_fps=30（键名/值）")
	menu.call("_open_fps_sub", 0, (menu.get("_rows")[0] as Control))   # 批次 X P3-b 签名等价替换（重建重算选中态）
	fps_btn30 = null
	var fps_btn60: Button = null
	for c6: Variant in ((menu.get("_fps_sub") as PopupPanel).get_child(0) as Container).get_children():
		if c6 is Button and String((c6 as Button).text) == "30":
			fps_btn30 = c6
		if c6 is Button and String((c6 as Button).text) == "60":
			fps_btn60 = c6
	# 批次 X P3-a 判据改「几何一致+色差」（旧「选中行 override 在场」废止留痕）
	await process_frame
	await process_frame   # 子列行排序落位后再比几何
	var sb_fps_sel: StyleBox = fps_btn30.get_theme_stylebox("normal")
	var sb_fps_unsel: StyleBox = fps_btn60.get_theme_stylebox("normal")
	var m_eq_fps: bool = sb_fps_sel != null and sb_fps_unsel != null
	for s5: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		m_eq_fps = m_eq_fps and sb_fps_sel.get_content_margin(s5) == sb_fps_unsel.get_content_margin(s5)
	check(m_eq_fps, "P3-a：帧率子列选中/未选行 margin 逐值相等（「变细」根除）")
	check_eq(fps_btn30.size, fps_btn60.size, "P3-a：帧率子列选中/未选行 size 逐值相等（几何一致）")
	var bg_fps_sel: Color = (sb_fps_sel as StyleBoxFlat).bg_color if sb_fps_sel is StyleBoxFlat else Color.BLACK
	var bg_fps_unsel: Color = (sb_fps_unsel as StyleBoxFlat).bg_color if sb_fps_unsel is StyleBoxFlat else Color.WHITE
	check(not bg_fps_sel.is_equal_approx(bg_fps_unsel),
		"P3-a：帧率子列选中/未选仅色差（实际 %s / %s）" % [bg_fps_sel, bg_fps_unsel])
	_drain(lsn)
	fps_btn30.pressed.emit()
	await _wait_available(lsn, 4)
	var fps_noop := false
	for cmd3: String in _recv_cmds(lsn):
		if String(cmd3).begins_with("SET_FPS"):
			fps_noop = true
	check(not fps_noop, "V4：帧率子列同口径——再点已选值不重发 SET_FPS（no-op）")
	if lsn != null:
		lsn.close()

	# ================= 段 E. 矩阵等待态 8s 超时统一裁决（V16，spec §6.4）=================
	bridge._camera_enum = {"cameras": [{"id": 0, "name": "A"}, {"id": 1, "name": "B"}], "current_camera": 0}
	bridge._camera_matrix = {}
	bridge._probe_matrix_cache.clear()
	bridge._camera_errors = []
	menu.call("open_menu")
	var rows: Array = menu.get("_rows")
	var lsn2 := _ctrl_listener()
	# E1：id≠current 已发 PROBE 的等待行——8s 超时转「检测失败」（既有语义回归锚）
	menu.call("_open_res_sub", 1, rows[1])
	await _wait_available(lsn2, 4)
	check(_recv_cmds(lsn2).has("PROBE_MATRIX:1"), "V16 前置：id≠current 无缓存 → PROBE_MATRIX:1 照发")
	menu.set("_wait_started_ms", Time.get_ticks_msec() - 9000)   # 注入 9s 前等待起点（_open_at 同款注入口径）
	menu.call("_process", 0.016)
	var e1_txt := ""
	var e1_disabled := false
	for n1: Variant in ((menu.get("_res_box") as Container).get_children()):
		if n1 is Button:
			e1_txt = String((n1 as Button).text)
			e1_disabled = bool((n1 as Button).disabled)
	check_eq(e1_txt, "检测失败（设备无法打开）", "V16：已发 PROBE 等待行 8s 超时 → 检测失败文案")
	check(e1_disabled, "V16：超时行置灰不可点")
	menu.call("_close_res")
	# E2（本批根治点）：id==current 矩阵等待行 8s 统一裁决（等待态建立/超时转败语义不变）。
	# 批次 AD-5c 等价改写（旧值留痕）：旧断言「零探测（防「自探自败」，双审 P2-6 沿用）」
	#（not probe0）被条件探测取代——current 缓存不充分（0 档）→ 与其它设备行同链路发
	# PROBE_MATRIX:0；P2-6「自探自败」由 Python 侧 pid==current live 复用路径消解
	#（不另开句柄不抢流、探测后恢复、绝不 release），不再靠「零探测」规避。
	# 断言前显式复位桥在飞/菜单节流：E1 的探测在飞会经互斥漏斗丢弃本请求 → 不复位则
	# 断言因副作用假绿（旧语义的假象残留）。
	_drain(lsn2)
	bridge._probe_in_flight = false
	bridge._probe_sent_at_ms = -1
	menu.set("_probe_requested_at", {})
	menu.call("_open_res_sub", 0, rows[0])
	await _wait_available(lsn2, 4)
	check(_recv_cmds(lsn2).has("PROBE_MATRIX:0"),
		"V16：id==current 矩阵等待态按需发 PROBE_MATRIX:0（AD-5c 条件探测；旧「零探测」断言废止留痕）")
	var wts: Variant = menu.get("_wait_started_ms")
	# 哨兵口径注：判 -1 而非 >0——进程启动早期 ms 时间戳可为小值（>=0 与 -1 哨兵同族实证修正）
	check(wts is int and int(wts) != -1, "V16：_show_wait_state 记录等待起始时刻（成员级时间戳在场）")
	menu.set("_wait_started_ms", Time.get_ticks_msec() - 9000)
	menu.call("_process", 0.016)
	var e2_txt := ""
	for n2: Variant in ((menu.get("_res_box") as Container).get_children()):
		if n2 is Button:
			e2_txt = String((n2 as Button).text)
	check_eq(e2_txt, "检测失败（设备无法打开）", "V16：id==current 矩阵等待行 8s 超时转败（旧口径恒「检测中…」死等——本批根治）")
	if lsn2 != null:
		lsn2.close()
	menu.call("_close_subs")
	menu.free()

	# ================= 段 F. 成功清灰（V16，spec §6.4「只增不减」废止）=================
	var menu3: Control = await _make_menu()
	bridge._camera_enum = {"cameras": [{"id": 0, "name": "A"}, {"id": 1, "name": "B"}], "current_camera": 0}
	bridge._camera_errors = []
	menu3.call("open_menu")
	bridge.simulate_packet(JSON.stringify({"type": "camera_error", "id": 1}))
	check_eq(bridge.get_camera_errors(), [1], "V16 前置：camera_error id=1 → 置灰数据源累积")
	menu3.call("_apply_enum", [{"id": 0, "name": "A"}, {"id": 1, "name": "B"}] as Array, 0)
	var row1: Button = (menu3.get("_rows")[1] as Button)
	check(row1.disabled and String(row1.text).contains("无法打开"), "V16 前置：错误设备行置灰+「无法打开」")
	bridge.simulate_packet(JSON.stringify({"type": "init", "cameras": [{"id": 0, "name": "A"}, {"id": 1, "name": "B"}], "current_camera": 1}))
	check_eq(bridge.get_camera_errors(), [], "V16：init#1（切换/开启成功必发）→ current_camera 从 _camera_errors 移除（清灰；旧口径只增不减废止）")
	row1 = (menu3.get("_rows")[1] as Button)
	check(not bool(row1.disabled) and not String(row1.text).contains("无法打开"),
		"V16：清灰后菜单行随 init#1 重建恢复可点（置灰可恢复）")
	menu3.free()

	# ================= 段 G. 桥设备记忆优先（V3，spec §6.2 三分支）+res/fps 追发（V17）=================
	var bridge2: Node = Bridge.new()
	get_root().add_child(bridge2)
	bridge2.name = "GestureBridgeVMemTest"
	bridge2._init_udp()
	bridge2._init_jpeg_udp()
	bridge2._simulate_start_ok = true   # 测试接缝：视 start 已成功（U4 表驱动第三态）
	var lsn3 := _ctrl_listener()
	# G1 无记忆（V-D 落地契约：gesture_camera_device 系 String 型，""=未记忆）→ 枚举第一项
	#（旧口径 current_camera 保留废止，V3 拍板「无记忆→首设备」）
	save.update_settings({"gesture_camera_device": ""})
	bridge2._camera_enum = {"cameras": [{"id": 0, "name": "A"}, {"id": 2, "name": "B"}], "current_camera": 2}
	_drain(lsn3)
	bridge2.ensure_camera_open()
	await _wait_available(lsn3, 4)
	check(_recv_cmds(lsn3).has("START_CAMERA_BY_NAME:"),
		"AD 等价替换（旧 V3「无记忆 → 枚举第一项 SWITCH_CAMERA:0」）：无记忆 → 空载荷启动指令（降级首项下沉 Python）")
	# G2 记忆设备在枚举中 → 用记忆设备（String 型写入=菜单写档同型，桥解析器双态兼容）
	save.update_settings({"gesture_camera_device": "B"})
	bridge2._camera_enum = {"cameras": [{"id": 0, "name": "A"}, {"id": 1, "name": "B"}], "current_camera": 0}
	_drain(lsn3)
	bridge2.ensure_camera_open()
	await _wait_available(lsn3, 4)
	check(_recv_cmds(lsn3).has("START_CAMERA_BY_NAME:B"),
		"AD：记忆设备名命中枚举 → 逐字下发实名（记忆优先；旧断言为 SWITCH_CAMERA:1）")
	# G3 记忆设备不在枚举 → 回落枚举第一项
	save.update_settings({"gesture_camera_device": "Ghost"})
	bridge2._camera_enum = {"cameras": [{"id": 0, "name": "A"}, {"id": 1, "name": "B"}], "current_camera": 1}
	_drain(lsn3)
	bridge2.ensure_camera_open()
	await _wait_available(lsn3, 4)
	check(_recv_cmds(lsn3).has("START_CAMERA_BY_NAME:Ghost"),
		"AD：记忆名不在枚举 → 按名原样下发（降级首项下沉 Python；旧断言为 SWITCH_CAMERA:0）")
	# G4 枚举缓存空 → 批次 AC 等价改写（2026-09-27，spec §4.2-3/D2）：旧口径「回落 0 盲发
	# SWITCH_CAMERA:0」= 实机盲开 CAP 0 的荣耀 Magic7 跨屏摄像头（手机弹窗+指示灯闪烁根因），
	# 批次 AC 拍板废止。新口径：枚举未达 → 零 SWITCH，改走握手重发（无记忆名亦发空载荷）
	# ＋ GET_CAMERAS 拉取，待 init#1 到达由 _handle_meta 自动按记忆名/非手机首项开启。
	save.update_settings({"gesture_camera_device": "1"})
	bridge2._camera_enum = {}
	bridge2._last_enum_request_ms = -1000000   # 复位拉取节流（本段出包断言前置）
	bridge2._preferred_handshake_armed = false
	bridge2._preferred_next_at_ms = -1
	_drain(lsn3)
	bridge2.ensure_camera_open()
	await _wait_available(lsn3, 4)
	var g4_cmds: Array = _recv_cmds(lsn3)
	var g4_sw := 0
	var g4_sc := 0
	for c: String in g4_cmds:
		if c.begins_with("SWITCH_CAMERA"):
			g4_sw += 1
		if c.begins_with("START_CAMERA_BY_NAME"):
			g4_sc += 1
	check_eq(g4_sw, 0,
		"AC/AD 等价替换（旧 V3「缓存空回落 0」）：枚举未达 → 零盲发 SWITCH_CAMERA（实际 %s）" % [g4_cmds])
	check_eq(g4_sc, 0,
		"AD：枚举未达 → 零启动指令盲发（待 init#1 才下发；实际 %s）" % [g4_cmds])
	check(g4_cmds.has("GET_CAMERAS"),
		"AC：枚举未达 → GET_CAMERAS 拉取（init#1 到达后自动开；实际 %s）" % [g4_cmds])
	check(str(bridge2.get("_preferred_handshake_armed")) == "true",
		"AC：枚举未达 → 握手重新武装（旧回落链废止后的官方路径）")
	bridge2._preferred_next_at_ms = -1
	bridge2._process(0.016)
	await _wait_available(lsn3, 4)
	var g4_hs := 0
	for c: String in _recv_cmds(lsn3):
		if c.begins_with("START_CAMERA_BY_NAME"):
			g4_hs += 1
	check(g4_hs >= 1,
		"AD：武装后到点补发启动指令（含空载荷形态）唤起 Python 按存档名/降级首项启动")
	# G5 记忆 res/fps 非空/非0 且设备匹配 → SWITCH 后按序追发
	save.update_settings({"gesture_camera_device": "B", "gesture_camera_res": "640x480", "gesture_camera_fps": 30})
	bridge2._camera_enum = {"cameras": [{"id": 0, "name": "A"}, {"id": 1, "name": "B"}], "current_camera": 0}
	_drain(lsn3)
	bridge2.ensure_camera_open()
	await _wait_available(lsn3, 6)
	var g5 := _recv_cmds(lsn3)
	var i_sw := g5.find("START_CAMERA_BY_NAME:B")
	var i_res := g5.find("SET_RESOLUTION:1:640x480")
	var i_fps := g5.find("SET_FPS:1:30")
	check(i_sw >= 0 and i_res >= 0 and i_fps >= 0, "V17：记忆 res/fps 非空 → 追发 SET_RESOLUTION/SET_FPS（实际 %s）" % [g5])
	check(i_sw < i_res and i_res < i_fps, "V17：追发序=启动指令→SET_RESOLUTION→SET_FPS（Python 控制命令串行语义）")
	# G6 设备不匹配（记忆设备≠本次开启设备）→ 不追发（防跨设备串值）
	save.update_settings({"gesture_camera_device": "1", "gesture_camera_res": "640x480", "gesture_camera_fps": 30})
	bridge2._camera_enum = {}   # 枚举空 → 开启设备回落 0 ≠ 记忆设备 1
	_drain(lsn3)
	bridge2.ensure_camera_open()
	await _wait_available(lsn3, 6)
	var g6 := _recv_cmds(lsn3)
	var g6_bad := false
	for cmd5: String in g6:
		if String(cmd5).begins_with("SET_RESOLUTION") or String(cmd5).begins_with("SET_FPS"):
			g6_bad = true
	check(not g6_bad, "V17：设备不匹配 → 不追发 res/fps（实际 %s）" % [g6])
	if lsn3 != null:
		lsn3.close()
	bridge2.free()

	# ================= 段 H. camera_error 统一提示+last_good 回落（V16，spec §6.4）=================
	var probe := StripProbe.new()
	game.attach_strip(probe)   # 注入 TopStrip 替身（真实条由 main 挂载，此处捕获改道路由）
	var bridge3: Node = Bridge.new()
	get_root().add_child(bridge3)
	bridge3.name = "GestureBridgeVFallbackTest"
	bridge3._init_udp()
	bridge3._init_jpeg_udp()
	bridge3._simulate_start_ok = true
	# H1 last_good 记录时机：init#1 到达即以 current_camera 更新（开启成功信号）。
	# 坑1 防御：旧代码无该成员 → get 返回 null，str(null)="null"≠期望 → 红态不崩。
	check_eq(str(bridge3.get("_last_good_camera_id")), "-1", "V16：last_good 初值 -1（未成功过）")
	bridge3.simulate_packet(JSON.stringify({"type": "init", "cameras": [{"id": 0, "name": "A"}, {"id": 1, "name": "B"}], "current_camera": 1}))
	check_eq(str(bridge3.get("_last_good_camera_id")), "1", "V16：init#1（开启成功）→ last_good=current_camera=1")
	bridge3.simulate_packet(JSON.stringify({"type": "init", "cameras": [{"id": 0, "name": "A"}, {"id": 1, "name": "B"}], "current_camera": 0}))
	check_eq(str(bridge3.get("_last_good_camera_id")), "0", "V16：init#1 随最新 current_camera 更新（last_good=0）")
	# H2 错误 id==当前设备 → 只提示（批次 Z Z4-④ 等价改写：桥自动回落 SWITCH 到 last_good
	# 「旧设备」的抢句柄路径退役——切换/开启失败后旧设备零 open，spec §4-4 退役口径；
	# 提示可达性与 reason 文案承接 V16/回修②P1-2 提示态分支）。
	bridge3._camera_enum = {"cameras": [{"id": 0, "name": "A"}, {"id": 1, "name": "B"}], "current_camera": 1}
	var lsn4 := _ctrl_listener()
	_drain(lsn4)
	bridge3.simulate_packet(JSON.stringify({"type": "camera_error", "id": 1, "reason": "设备被占用"}))
	await _wait_available(lsn4, 4)
	var h2 := _recv_cmds(lsn4)
	check_eq(h2.count("SWITCH_CAMERA:0"), 0,
		"Z4-④：错误 id==当前设备 → 零回落 SWITCH（抢句柄退役；实际 %s）" % [h2])
	check(probe.pushes.size() >= 1 and String(probe.pushes[0][0]).begins_with("摄像头启动失败"),
		"Z4-④：camera_error → Game.toast(centered) 改道 TopStrip info 条提示态文案（实际 %s）" % [probe.pushes])
	if probe.pushes.size() >= 1:   # 坑1 防御：红态（无条）时不越界取数，FAIL 而非 SCRIPT ERROR 中止
		check_eq(String(probe.pushes[0][0]), "摄像头启动失败：设备被占用",
			"Z4-④：提示文案逐字「摄像头启动失败：<reason>」（回落态文案随回落退役）")
	# H3 重复错误 → 仍零回落（旧 5s 节流概念随回落一并退役：恒不回落，无窗口语义）
	bridge3.simulate_packet(JSON.stringify({"type": "camera_error", "id": 1}))
	await _wait_available(lsn4, 4)
	check_eq(_recv_cmds(lsn4).count("SWITCH_CAMERA:0"), 0, "Z4-④：第二次错误 → 零回落 SWITCH（恒不回落）")
	if probe.pushes.size() >= 2:   # 无 reason 错误 → 提示文案逐字
		check_eq(String(probe.pushes[1][0]), "摄像头启动失败",
			"Z4-④：无 reason 错误 → 提示文案逐字「摄像头启动失败」")
	# H4 任意时刻第三错 → 回落不随时间窗复活（退役无节流窗语义）
	bridge3.simulate_packet(JSON.stringify({"type": "camera_error", "id": 1}))
	await _wait_available(lsn4, 4)
	check_eq(_recv_cmds(lsn4).count("SWITCH_CAMERA:0"), 0, "Z4-④：任意时刻第三错 → 回落不复活（零 SWITCH）")
	if probe.pushes.size() >= 3:
		check_eq(String(probe.pushes[2][0]), "摄像头启动失败",
			"Z4-④：第三错提示文案逐字（只提示不回落口径恒定）")
	# H5 非 current 设备错误 → 只提示不回落（原语义不变）
	_drain(lsn4)
	bridge3.simulate_packet(JSON.stringify({"type": "camera_error", "id": 0}))
	await _wait_available(lsn4, 4)
	check(_recv_cmds(lsn4).is_empty(), "V16：非当前设备错误 → 不触发回落（仅提示）")
	check_eq(probe.pushes.size(), 4, "V16：任何 camera_error 均提示（4 错 4 条，提示可达性不回落省略）")
	if probe.pushes.size() >= 4:
		check_eq(String(probe.pushes[3][0]), "摄像头启动失败",
			"V16 回修②P1-2：非当前设备错误=提示态文案逐字（仅提示不回落）")
	if lsn4 != null:
		lsn4.close()
	bridge3.free()
	game.attach_strip(null)   # 摘除替身（复位路由）
	probe.free()

	# ================= 收尾：清档纪律还原（备份→测试→逐字节还原+EVID，规范第 2 条） =================
	_restore_user()
	finish()
