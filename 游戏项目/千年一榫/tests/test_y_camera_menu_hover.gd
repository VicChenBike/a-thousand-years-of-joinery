extends "res://tests/test_base.gd"
## 批次 Y Y2（2026-09-22 规格 §2 Y-A15）——摄像头下拉 hover 直达帧率列 TDD 红测先行。段口径：
##   A：当前设备行 hover → res+fps 双列同现（回归锚：当前设备行 hover 即可开 fps 列）；
##   B（Y-A15）：保活并集扩为 设备行∪分辨率列∪帧率列——鼠标落在相邻设备行上 → 行间过渡
##     不收起（红：旧谓词仅 res∪fps 两 box）；
##   C（Y-A15）：非当前设备行等待态不再吞已开的 fps 列——hover 非当前行（无探测缓存，
##     「检测中…」）时已开的 fps 列保持在场（红：旧实现 _close_res 级联吞列）；
##   D：probe_result 到达 → 等待态刷新 + fps 列按该设备重建（帧率项可点闭环）；
##   E：鼠标离开三域并集 → 收起语义不变（负例）。
## 夹具=test_x_eye_menu_gesture 段A 手法（bridge autoload 直注缓存；零写档零出包）。

const CoordSpace := preload("res://scripts/coord_space.gd")

# ===== 清档纪律（段D 帧率项点击写档 gesture_camera_fps；前缀独立 ycmh）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_BK_PREFIX := "user://_ycmh_backup_"
const DISC_WATCHED: Array = ["user://save.json", "user://save.json.tmp", "user://save.json.bak"]
var _pre_save_text := ""

func _backup_user() -> void:
	# 自愈（规范第 5 条，test_w_camera_button 先例）：上次强杀残留的备份先还原到磁盘再重备份
	for p0: String in DISC_WATCHED:
		var bk0: String = DISC_BK_PREFIX + p0.get_file()
		var abs_bk0: String = ProjectSettings.globalize_path(bk0)
		if FileAccess.file_exists(abs_bk0):
			var abs_p0: String = ProjectSettings.globalize_path(p0)
			if FileAccess.file_exists(abs_p0):
				DirAccess.remove_absolute(abs_p0)
			DirAccess.copy_absolute(abs_bk0, abs_p0)
			DirAccess.remove_absolute(abs_bk0)
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(ProjectSettings.globalize_path(p), ProjectSettings.globalize_path(bk))
	if FileAccess.file_exists(ProjectSettings.globalize_path(DISC_SAVE_PATH)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DISC_SAVE_PATH))
	root.get_node("SaveManager").call("load_game")

func _restore_user() -> void:
	for p: String in DISC_WATCHED:
		var abs_p: String = ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs_p):
			DirAccess.remove_absolute(abs_p)
		var bk: String = DISC_BK_PREFIX + p.get_file()
		var abs_bk: String = ProjectSettings.globalize_path(bk)
		if FileAccess.file_exists(abs_bk):
			DirAccess.copy_absolute(abs_bk, abs_p)
			DirAccess.remove_absolute(abs_bk)
	var real_sm: Node = root.get_node_or_null("SaveManager")
	if real_sm != null:
		real_sm.load_game()
	var post: String = FileAccess.get_file_as_string(ProjectSettings.globalize_path(DISC_SAVE_PATH)) if FileAccess.file_exists(ProjectSettings.globalize_path(DISC_SAVE_PATH)) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_y_camera_menu_hover ==")
	_backup_user()
	var bridge: Node = root.get_node("GestureBridge")
	bridge.set("_camera_enum", {"cameras": [{"id": 0, "name": "CamA"}, {"id": 1, "name": "CamB"}], "current_camera": 0})
	bridge.set("_camera_matrix", {"resolutions": [[1280, 720], [640, 480]], "fps_options": [30, 60]})
	bridge.set("_probe_matrix_cache", {})
	bridge.set("_camera_errors", [])
	var menu: Control = (load("res://scenes/settings/camera_menu.gd") as GDScript).new()
	root.add_child(menu)
	await process_frame
	menu.call("open_menu")
	var rows: Array = menu.get("_rows")
	check_eq((rows as Array).size(), 2, "段前置：设备列表 2 行")

	# ================= 段 A：当前设备行 hover → res+fps 双列同现（回归锚） =================
	menu.call("_open_res_sub", 0, rows[0])
	await process_frame
	var res_sub0: Variant = menu.get("_res_sub")
	var fps_sub0: Variant = menu.get("_fps_sub")
	check(res_sub0 != null, "Y-A15 前置：当前设备行 hover → res 列在场")
	check(fps_sub0 != null, "Y-A15：当前设备行 hover 即可开 fps 列（当前设备矩阵直出）")

	# ================= 段 B：保活并集扩为 设备行∪分辨率列∪帧率列 =================
	# 鼠标落在相邻设备行（rows[1]）上 → 谓词保活（行间过渡不收起；红：旧谓词仅 res∪fps）
	var row1_rect: Rect2 = (rows[1] as Control).get_global_rect()
	check(row1_rect.size.x > 0.0, "段B 前置：设备行全局矩形非退化（无头布局落位）")
	check(bool(menu.call("_res_sub_contains_mouse", row1_rect.get_center())),
		"Y-A15：保活并集含设备行——鼠标在相邻设备行 → 保活（行间过渡不收起）")
	# 负例仍成立：远点不保活
	check(not bool(menu.call("_res_sub_contains_mouse", row1_rect.get_center() + Vector2(5000, 5000))),
		"Y-A15：远离三域并集的远点 → 不保活（负例）")

	# ================= 段 C：非当前设备行等待态不吞已开的 fps 列 =================
	# hover 非当前设备行（id 1，无探测缓存 → 「检测中…」等待态）：旧实现 _close_res 级联收 fps
	# → 已开的 fps 列被吞成空。新口径：等待态只重建 res 列，fps 列保持在场。
	menu.call("_open_res_sub", 1, rows[1])
	await process_frame
	var wait_txts: Array = []
	for c1: Variant in ((menu.get("_res_box") as Container).get_children()):
		if c1 is Button:
			wait_txts.append(String((c1 as Button).text))
	check(wait_txts.has("检测中…"), "段C 前置：非当前设备行无缓存 → res 列「检测中…」等待态")
	check(menu.get("_fps_sub") != null, "Y-A15：非当前设备行等待态 → 已开的 fps 列不被吞（跨行直达帧率列不中断）")

	# ================= 段 D：probe_result 到达 → 刷新 + fps 列按该设备重建（可点闭环） =================
	var lsn := PacketPeerUDP.new()
	var lsn_ok: bool = lsn.bind(int(bridge.get_control_port())) == OK
	if lsn_ok:
		while lsn.get_available_packet_count() > 0:
			lsn.get_packet()
	bridge.set("_probe_in_flight", false)   # 互斥标志复位（test_t_camera_device W6 甄别手法）
	bridge.simulate_packet(JSON.stringify({"type": "probe_result", "id": 1, "ok": true,
		"resolutions": [[1280, 720]], "fps_options": [30, 60]}))
	await process_frame
	menu.call("_on_probe_result", 1, true, [[1280, 720]], [30, 60])
	await process_frame
	var res_txts: Array = []
	for c2: Variant in ((menu.get("_res_box") as Container).get_children()):
		if c2 is Button:
			res_txts.append(String((c2 as Button).text))
	check(res_txts.has("1280x720"), "Y-A15：probe_result 到达 → 等待态刷新为矩阵列出")
	check(menu.get("_fps_sub") != null, "Y-A15：probe_result 到达 → fps 列按该设备重建（在场）")
	# 帧率项可点闭环：点 fps 列首项 → SET_FPS:1:<n> 照发
	if menu.get("_fps_sub") != null and lsn_ok:
		var fps_box: Control = menu.get("_fps_box")
		var fb: Button = (fps_box.get_child(0) as Button)
		var fps_val: int = int(fb.get_meta("fps_value"))
		fb.pressed.emit()
		var saw := false
		for i: int in 10:
			if lsn.get_available_packet_count() > 0:
				if String(lsn.get_packet().get_string_from_utf8()) == "SET_FPS:1:%d" % fps_val:
					saw = true
					break
			await process_frame
		check(saw, "Y-A15：直达路径帧率项可点 → SET_FPS:1:<n> 照发（验收闭环）")
	if lsn_ok:
		lsn.close()

	# ================= 段 E：鼠标离开三域并集 → 收起语义不变（负例） =================
	menu.call("_close_res_if_outside", row1_rect.get_center() + Vector2(5000, 5000))
	check(menu.get("_res_sub") == null and menu.get("_fps_sub") == null,
		"Y-A15：鼠标离开设备行∪res∪fps 三域 → 全收（移出即收语义不变；_close_res 级联保留）")

	menu.free()
	finish()
