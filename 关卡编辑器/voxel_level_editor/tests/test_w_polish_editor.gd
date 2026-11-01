extends "res://tests/test_base.gd"
## 批次 W6 结构治理波·编辑器侧（规格 §7 P3-5 a/e/f）：
##   a  level_slots._write_text get_error 时机移到 close() 后（与 G/save_manager 同构同修）；
##   e  editor_view 线框网格缓存按尺寸键控（旧单一缓存忽略 size 入参）；
##   f  editor_main 试玩「锁定变暗」modulate 乘算改背景自变暗（文字不降对比、modulate 不动）。
## TDD 红态：标注「红：」的断言在旧代码下必 FAIL。
## 磁盘纪律：沙盒=TEMP 一次性子目录（test_w_editor 先例），真实 levels/ 与 user:// 零触碰。

var _ls: Script = preload("res://scripts/level_slots.gd")   # Script 型动态派发（test_w_editor 先例；class_name 常量直取会走静态解析）

var _sandboxes: Array[String] = []

func _initialize() -> void:
	print("== test_w_polish_editor（批次 W6 编辑器侧：P3-5 a/e/f） ==")
	OS.set_environment("VOXEL_EDITOR_SLOTS_ROOT", "")
	await _a_write_text_error_timing()
	await _e_wire_mesh_size_key()
	await _f_locked_panel_no_modulate()
	_cleanup()
	finish()

func _make_sandbox(tag: String) -> String:
	var base := OS.get_environment("TEMP")
	if base.is_empty():
		base = "/tmp"
	var dir: String = base.replace("\\", "/").path_join("voxel_editor_w6_%s_%d" % [tag, Time.get_ticks_msec()]) + "/"
	_sandboxes.append(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	return dir

func _cleanup() -> void:
	for path: String in _sandboxes:
		var da := DirAccess.open(path)
		if da == null:
			continue
		da.list_dir_begin()
		var item := da.get_next()
		while item != "":
			if item != "." and item != "..":
				var full := path.path_join(item)
				if da.current_is_dir():
					var inner := DirAccess.open(full)
					if inner != null:
						inner.list_dir_begin()
						var it2 := inner.get_next()
						while it2 != "":
							if it2 != "." and it2 != "..":
								inner.remove(it2)
							it2 = inner.get_next()
					DirAccess.remove_absolute(full)
				else:
					DirAccess.remove_absolute(full)
			item = da.get_next()
		da.list_dir_end()
		DirAccess.remove_absolute(path)

# ---------- a（P3-5a）：_write_text get_error 时机 ----------
func _a_write_text_error_timing() -> void:
	var src := String(FileAccess.get_file_as_string("res://scripts/level_slots.gd"))
	var i0 := src.find("static func _write_text(")
	check(i0 >= 0, "a1 前置: level_slots._write_text 存在")
	if i0 < 0:
		return
	var body := src.substr(i0)   # _write_text 为文件尾段（同构次序留痕：save_manager 同断言）
	check(body.find("close()") < body.find("get_error()"),
		"a2（红）: _write_text close() 先于 get_error()（旧序缓冲/flush 错误不可见）")
	# 行为回归锚：有效写 true+内容往返（沙盒路径）
	var sb := _make_sandbox("a")
	var fpath: String = sb + "probe_write.txt"
	var ok: bool = bool(_ls.callv("_write_text", [fpath, "w6"]))
	check(ok and FileAccess.file_exists(fpath)
		and String(FileAccess.get_file_as_string(fpath)) == "w6",
		"a3: _write_text 有效写返回 true 且内容往返一致（行为回归锚）")

# ---------- e（P3-5e）：线框网格缓存按尺寸键控 ----------
func _e_wire_mesh_size_key() -> void:
	var vv: Node = (load("res://scripts/editor_view.gd") as GDScript).new()
	root.add_child(vv)
	await process_frame
	var m1: Variant = vv.call("_get_wire_mesh", Vector3(0.94, 0.94, 0.94))
	var m2: Variant = vv.call("_get_wire_mesh", Vector3(0.94, 0.94, 0.94))
	check(m1 is ImmediateMesh and m1 == m2,
		"e1: 同尺寸两次取线框命中同一缓存（缓存语义回归锚）")
	var m3: Variant = vv.call("_get_wire_mesh", Vector3(1.5, 1.2, 0.9))
	check(m3 is ImmediateMesh and m3 != m1,
		"e2（红）: 不同尺寸返回不同网格（旧实现单一缓存忽略 size 入参→沿用首个尺寸几何）")
	vv.free()
	await process_frame

# ---------- f（P3-5f）：试玩锁定变暗不再 modulate 乘算 ----------
func _f_locked_panel_no_modulate() -> void:
	var root_env := _make_sandbox("f")
	OS.set_environment("VOXEL_EDITOR_SLOTS_ROOT", root_env)
	var ed: Control = (load("res://scenes/editor_main.tscn") as PackedScene).instantiate() as Control
	add_child(ed)
	await process_frame
	var lp: Panel = ed.get_node("LeftPanel") as Panel
	check(lp != null, "f1 前置: LeftPanel 存在")
	ed.call("_set_editing_ui_locked", true)
	await process_frame
	check_eq(lp.modulate, Color.WHITE,
		"f2（红）: 锁定态 left_panel.modulate 保持 WHITE（旧 LOCKED_PANEL_MODULATE 整体乘算连文字一起降对比）")
	check(lp.self_modulate != Color.WHITE,
		"f3（红）: 锁定态变暗经 self_modulate 落在面板背景自身（D-7 视觉差保留；文字不降对比）")
	ed.call("_set_editing_ui_locked", false)
	await process_frame
	check_eq(lp.self_modulate, Color.WHITE,
		"f4: 解锁态 self_modulate 复原 WHITE（往返）")
	ed.free()
	await process_frame
	OS.set_environment("VOXEL_EDITOR_SLOTS_ROOT", "")
