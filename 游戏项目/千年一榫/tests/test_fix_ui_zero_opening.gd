extends "res://tests/test_base.gd"
## 修复批红测 6（P3，UI 域）：零摄像头确认与 OPENING 禁用矛盾。
## 病灶：settings_panel.gd `_apply_zero_camera_gate` zero 分支（:473-474）无条件
## `camera_toggle.disabled = false`——与 Z4-⑥「_cam_opening 期间摄像头钮恒禁用」冲突：
## 枚举确认 0 设备的同帧若处于 OPENING（开镜中拔设备等），摄像头钮被解禁可重复点。
## 修法：zero 分支 `camera_toggle.disabled = _cam_opening`（非 zero 分支 :477 本就如此）。
## 红断言：zero 态 + _cam_opening=true → 摄像头钮 disabled=true（改前 false）。
## 反向护栏：zero 态 + 无 OPENING → disabled=false（AB2「视觉置灰仍可点」语义保持）。
## 零磁盘写：面板 _ready 若有写档风险，经存档备份-还原兜底（aacg 模式精简版）。
const PANEL_SCENE := "res://scenes/settings/settings_panel.tscn"
const DISC_SAVE_PATH := "user://save.json"
const DISC_BK_PREFIX := "user://_fxog_backup_"
const DISC_WATCHED: Array = ["user://save.json", "user://save.json.tmp", "user://save.json.bak", "user://first_launch.flag"]
var _pre_save_text := ""

func _backup_user() -> void:
	for p0: String in DISC_WATCHED:
		var bk0: String = DISC_BK_PREFIX + p0.get_file()
		if FileAccess.file_exists(ProjectSettings.globalize_path(bk0)):
			if FileAccess.file_exists(ProjectSettings.globalize_path(p0)):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p0))
			DirAccess.copy_absolute(ProjectSettings.globalize_path(bk0), ProjectSettings.globalize_path(p0))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(bk0))
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(p), ProjectSettings.globalize_path(DISC_BK_PREFIX + p.get_file()))
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	root.get_node("SaveManager").call("load_game")

func _restore_user() -> void:
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(bk), ProjectSettings.globalize_path(p))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(bk))
	var sm: Node = root.get_node_or_null("SaveManager")
	if sm != null:
		sm.load_game()
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_fix_ui_zero_opening ==")
	_backup_user()
	var bridge: Node = root.get_node("GestureBridge")
	check(bridge != null, "前置：GestureBridge 在位")
	if bridge == null:
		finish()
		return
	# 0 摄像头确认态（零 spawn 零出包：空列表注入）
	bridge.set("_camera_enum", {"cameras": [], "current_camera": 0})
	bridge.set("_camera_enum_zero", true)
	var panel: Node = (load(PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await process_frame
	await process_frame
	var gt: Button = panel.get_node("Panel/VBox/OptionsBox/GestureToggle")
	var ct: Button = panel.get_node("Panel/VBox/OptionsBox/CameraRow/CameraToggle")
	check(gt != null and ct != null, "前置：双钮在位")
	if gt == null or ct == null:
		finish()
		return
	# 反向护栏 1：zero 态、无 OPENING → 双钮 disabled=false（AB2 视觉置灰仍可点，保持）
	check_eq(bool(gt.disabled), false, "护栏：zero 无 OPENING → 手势钮可点（AB2 语义保持）")
	check_eq(bool(ct.disabled), false,
		"护栏：zero 无 OPENING → 摄像头钮可点（AB2 语义保持，改前改后均 false）")
	# 红测：zero 态 + OPENING → 摄像头钮禁用（Z4-⑥ 与 zero 分支矛盾处）
	panel.set("_cam_opening", true)
	panel.call("_apply_zero_camera_gate")
	check_eq(bool(ct.disabled), true,
		"P3 红测：zero + _cam_opening → 摄像头钮 disabled=true（改前无条件 false 违反 Z4-⑥）")
	check_eq(bool(gt.disabled), false, "P3 负例：手势钮不受 OPENING 禁用（Z4-⑥ 只禁摄像头钮）")
	# 收口复原：退出 OPENING → 回落 AB2 可点语义
	panel.set("_cam_opening", false)
	panel.call("_apply_zero_camera_gate")
	check_eq(bool(ct.disabled), false, "复原：退出 OPENING → 摄像头钮回可点")
	panel.free()
	finish()
