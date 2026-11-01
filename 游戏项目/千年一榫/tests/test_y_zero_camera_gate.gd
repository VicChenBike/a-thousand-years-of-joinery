extends "res://tests/test_base.gd"
## 批次 Y Y2（2026-09-22 规格 §2 Y-A20 + §5 carve-out 5）——0 摄像头路径与 HUD 三真值门
## TDD 红测先行。段口径：
##   A（Y-A20）：main.gd HUD 全隐可见门定档=三真值 gesture_hud_visible ∧ gesture_input ∧
##     camera_stream_open——流未开（含 0 摄像头）→ 全隐；camera_opened 事件 → 恢复显；
##   B（Y-A20）：枚举确认 0 设备 → TopStrip 提示条「未检测到摄像头，手势交互无法使用」
##     （Game.info 路由）；重枚举到设备自动复位（再次 0 设备可再提示）；
##   C：桥 0 设备确认语义——is_camera_enum_zero 仅 init#1 确认空列表为真（缓存空=未知，
##     不得误判 0 设备置灰）。
## 清档纪律：user:// 备份还原（前缀 yzcg，test_gesture_hud 同款四件组）；零摄像头。

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_yzcg_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
const ZERO_CAM_INFO := "未检测到摄像头，手势交互无法使用"
var _pre_save_text := ""

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _backup_user() -> void:
	# 自愈（规范第 5 条，test_w_camera_button 先例）：上次强杀残留的备份先还原到磁盘再重备份
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
		if FileAccess.file_exists(p):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
	if FileAccess.file_exists(_disc_abs(DISC_SAVE_PATH)):
		DirAccess.remove_absolute(_disc_abs(DISC_SAVE_PATH))
	root.get_node("SaveManager").call("load_game")

func _restore_user() -> void:
	for c: Node in root.get_children():
		if not DISC_AUTOLOADS.has(String(c.name)):
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
		real_sm.load_game()
	var post: String = FileAccess.get_file_as_string(_disc_abs(DISC_SAVE_PATH)) if FileAccess.file_exists(_disc_abs(DISC_SAVE_PATH)) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")

func finish() -> void:
	_restore_user()
	super.finish()

## TopStrip 替身（test_v_camera_menu StripProbe 同款）
class StripProbe extends Node:
	var pushes: Array = []
	func push_info(text: String, seconds: float = 3.0) -> void:
		pushes.append([text, seconds])

func _initialize() -> void:
	print("== test_y_zero_camera_gate ==")
	_backup_user()
	var save: Node = root.get_node("SaveManager")
	var bridge: Node = root.get_node("GestureBridge")
	var game: Node = root.get_node("Game")

	# ================= 段 C：桥 0 设备确认语义（先于 main 挂载，防信号串扰） =================
	bridge.set("_camera_enum", {})
	if bridge.has_method("is_camera_enum_zero"):
		check_eq(str(bridge.call("is_camera_enum_zero")), "false",
			"Y-A20：枚举缓存空=未知（init#1 未达）→ 非 0 设备确认（不得误判置灰）")
		bridge.simulate_packet(JSON.stringify({"type": "init", "cameras": [], "current_camera": 0}))
		check_eq(str(bridge.call("is_camera_enum_zero")), "true",
			"Y-A20：init#1 确认空列表 → 0 设备确认（is_camera_enum_zero=true）")
		bridge.simulate_packet(JSON.stringify({"type": "init", "cameras": [{"id": 0, "name": "A"}], "current_camera": 0}))
		check_eq(str(bridge.call("is_camera_enum_zero")), "false",
			"Y-A20：init#1 到达有设备 → 0 设备确认解除")
	else:
		check(false, "Y-A20：is_camera_enum_zero() 方法缺失（红）")
	bridge.set("_camera_enum", {})

	# ================= 段 A+B：main.tscn 三真值门 + 0 摄像头提示条 =================
	save.update_settings({"gesture_input": true, "gesture_hud_visible": true, "gesture_camera_enabled": true})
	var probe := StripProbe.new()
	root.add_child(probe)
	var main: Node = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	# main._ready 会自挂真实 TopStrip（attach_strip 覆盖）——替身须在其后重挂方可捕获 Game.info
	game.attach_strip(probe)
	var hud: Control = main.get_node("GestureHUDLayer/GestureHUDMount").get_child(0)
	check(hud != null, "段A 前置：HUD 实例在位")
	# A1 流未开（冷启动常态/0 摄像头）→ 全隐（红：旧双真值门流未开仍显）
	bridge._set_state(1)   # READY（链路在；流未开）
	main.call("_refresh_hud")
	check_eq(bool(hud.visible), false,
		"Y-A20：三真值门——链路 READY 而流未开 → HUD 全隐（开启真值第三支）")
	# A2 camera_opened 事件 → 恢复显（信号驱动 _refresh_hud）
	bridge.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "HD Camera"}))
	await process_frame
	check_eq(bool(hud.visible), true,
		"Y-A20：camera_opened → 流开启真值 true → HUD 恢复显（三真值齐备）")
	# A3 camera_closed 事件 → 再隐
	bridge.simulate_packet(JSON.stringify({"type": "camera_closed", "id": 0, "reason": "release"}))
	await process_frame
	check_eq(bool(hud.visible), false, "Y-A20：camera_closed → 流真值 false → HUD 全隐")
	# A3b（审查② P1-2）：场景切换旁路——流关闭下 Game 状态切换驱动 apply_dock_state
	#（_on_game_state_changed 路径的单元级直驱）不得复活整组（三真值 AND 于 apply_dock_state
	# 收口幂等闭合；旧实现两真值门此处复活且无自愈事件）
	hud.apply_dock_state(game.State.LEVEL, false, false)
	check_eq(bool(hud.visible), false, "审查②P1-2：流关闭+场景切换 apply_dock_state → HUD 保持隐藏（旁路复活根除）")
	# A3c：流恢复 → apply_dock_state 正常显（AND 幂等不误伤恢复路径）
	bridge.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "HD Camera"}))
	await process_frame
	hud.apply_dock_state(game.State.LEVEL, false, false)
	check_eq(bool(hud.visible), true, "审查②P1-2：流开启+场景切换 → HUD 正常显（AND 幂等不误伤）")
	# 复位 A4 前态（流关闭），原 A4 流程前提保持
	bridge.simulate_packet(JSON.stringify({"type": "camera_closed", "id": 0, "reason": "release"}))
	await process_frame
	check_eq(bool(hud.visible), false, "审查②P1-2 前置复位：流关闭 → HUD 隐（A4 流程前提）")
	# A4 手势开关关 → 恒隐（原两真值保持）
	bridge.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "HD Camera"}))
	await process_frame
	save.update_settings({"gesture_input": false})
	await process_frame
	check_eq(bool(hud.visible), false, "Y-A20：手势开关关 → HUD 恒隐（第一真值保持）")
	save.update_settings({"gesture_input": true})
	bridge.simulate_packet(JSON.stringify({"type": "camera_closed", "id": 0, "reason": "switch"}))
	await process_frame
	# A5 显示区开关关 → 恒隐
	bridge.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "HD Camera"}))
	await process_frame
	save.update_settings({"gesture_hud_visible": false})
	await process_frame
	check_eq(bool(hud.visible), false, "Y-A20：显示区开关关 → HUD 恒隐（第二真值保持）")
	save.update_settings({"gesture_hud_visible": true})
	await process_frame
	check_eq(bool(hud.visible), true, "Y-A20：三真值全开 → HUD 显（复位）")

	# ================= 段 B：0 摄像头提示条（Game.info 路由）+ 自动复位 =================
	var mark_b1: int = probe.pushes.size()
	bridge.simulate_packet(JSON.stringify({"type": "init", "cameras": [], "current_camera": 0}))
	await process_frame
	check(probe.pushes.size() > mark_b1, "Y-A20：枚举确认 0 设备 → TopStrip 提示条发出")
	if probe.pushes.size() > mark_b1:
		check_eq(String(probe.pushes[probe.pushes.size() - 1][0]), ZERO_CAM_INFO,
			"Y-A20：提示条文案逐字「未检测到摄像头，手势交互无法使用」")
	# 恢复设备 → 提示复位（不再重复）；再次 0 设备可再提示（每次 0 确认提示一次）
	var mark_b2: int = probe.pushes.size()
	bridge.simulate_packet(JSON.stringify({"type": "init", "cameras": [{"id": 0, "name": "A"}], "current_camera": 0}))
	await process_frame
	bridge.simulate_packet(JSON.stringify({"type": "init", "cameras": [], "current_camera": 0}))
	await process_frame
	check(probe.pushes.size() > mark_b2, "Y-A20：恢复后再确认 0 设备 → 提示条可再发（复位语义）")

	# ================= 段 B2（批次 Y 扫描回修 P2-1）：0 摄像头文案单源 =================
	# 旧况双源：settings_panel.ZERO_CAMERA_INFO 常量从未被引用、main.gd _on_camera_enum_for_zero_strip
	# 硬编码同一句——改文案漏改一处即漂移。守卫：main.gd 必须引用单源常量且硬编码句退役；
	# 文案逐字不变由段 B 逐字断言（ZERO_CAM_INFO）佐证。
	var main_src := String(FileAccess.get_file_as_string("res://scenes/main.gd"))
	check(main_src.contains("ZERO_CAMERA_INFO"),
		"P2-1：main.gd 0 摄像头提示文案引用单源常量 ZERO_CAMERA_INFO（旧硬编码句退役）")
	check(not main_src.contains("Game.info(\"未检测到摄像头"),
		"P2-1：main.gd 不再硬编码 0 摄像头提示句（双源漂移根除）")

	main.queue_free()
	await process_frame
	game.attach_strip(null)
	probe.free()
	# 收尾复位桥态（防同进程后续污染；本文件单跑自洽）
	bridge.set("camera_stream_open", false)
	bridge._set_state(0)
	save.update_settings({"gesture_input": true, "gesture_hud_visible": true, "gesture_camera_enabled": true})
	finish()
