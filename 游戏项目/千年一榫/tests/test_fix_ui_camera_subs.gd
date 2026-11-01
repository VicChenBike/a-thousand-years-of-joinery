extends "res://tests/test_base.gd"
## 修复批红测 2（P2，UI 域）：摄像头下拉枚举重建留孤儿子列。
## 病灶：camera_menu.gd `_apply_enum`（:196）只 `_clear_box()` 重建 _root_box，
## `_res_sub/_fps_sub`（挂 self :389/:420）不回收——菜单开着时 init#1 到达 →
## 孤儿子列继续 popup（锚行已被 queue_free），帧末谓词（:484-500）依赖锚行 mouse_exited 永不触发。
## 修法：_apply_enum 重建前显式 _close_subs()。
## 红断言：开着 res+fps 双子列 → 模拟枚举重建 → 两子列指针 null / 旧 res 列不可见。
## 夹具=test_y_camera_menu_hover 段A 手法（bridge autoload 直注缓存；零写档零出包）。

func _initialize() -> void:
	print("== test_fix_ui_camera_subs ==")
	var bridge: Node = root.get_node("GestureBridge")
	check(bridge != null, "前置：GestureBridge 在位")
	if bridge == null:
		finish()
		return
	bridge.set("_camera_enum", {"cameras": [{"id": 0, "name": "CamA"}, {"id": 1, "name": "CamB"}], "current_camera": 0})
	bridge.set("_camera_matrix", {"resolutions": [[1280, 720], [640, 480]], "fps_options": [30, 60]})
	bridge.set("_probe_matrix_cache", {})
	bridge.set("_camera_errors", [])
	bridge.set("_camera_enum_zero", false)
	var menu: Control = (load("res://scenes/settings/camera_menu.gd") as GDScript).new()
	root.add_child(menu)
	await process_frame
	menu.call("open_menu")
	var rows: Array = menu.get("_rows")
	check_eq(rows.size(), 2, "前置：设备列表 2 行（缓存直进 LOADED）")
	# 开子列（当前设备行 → res+fps 双列同现）
	menu.call("_open_res_sub", 0, rows[0])
	await process_frame
	check(menu.get("_res_sub") != null, "前置：res 子列在场")
	check(menu.get("_fps_sub") != null, "前置：fps 子列在场")
	var old_res: Variant = menu.get("_res_sub")
	var old_fps: Variant = menu.get("_fps_sub")
	# 模拟菜单开着时 init#1 枚举重建（生产：python 重枚举/init#1 实时刷新路径）
	menu.call("_apply_enum", [{"id": 0, "name": "CamA"}, {"id": 1, "name": "CamB"}], 0)
	check(menu.get("_res_sub") == null,
		"P2 红测：枚举重建 → res 子列已收（改前指针残留=孤儿子列）")
	check(menu.get("_fps_sub") == null,
		"P2 红测：枚举重建 → fps 子列已收（改前指针残留=孤儿子列）")
	if old_res != null and is_instance_valid(old_res):
		check_eq(bool(old_res.get("visible")), false,
			"P2 红测：旧 res 子列不再可见（改前仍 popup 挂屏）")
	if old_fps != null and is_instance_valid(old_fps):
		check_eq(bool(old_fps.get("visible")), false,
			"P2 红测：旧 fps 子列不再可见")
	check_eq((menu.get("_rows") as Array).size(), 2, "重建后设备行仍 2 行（清箱重建正常）")
	await process_frame   # queue_free 冲刷后再 free（防父连带释放与延迟删除竞态）
	menu.free()
	finish()
