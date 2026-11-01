extends "res://tests/test_base.gd"
## 修复批红测 5（P3，手势域）：bridge 防重入门不查进程存活。
## 病灶：gesture_bridge.gd start_gesture_process（:877-883）`_process_pid >= 0` 即判活
## 直接 return true——python 已死（pid 陈旧）时永不重拉、且把死进程当活实例复用。
## 修法：pid>=0 时加 `OS.is_process_running(_process_pid)` 判活（4.7 API 名已在本文件
## :355/:539/:930 三处既有用法核实）；死则清 pid 走重拉链路。
## 红断言：注入死 pid → start_gesture_process 返回 false 且 _process_pid 被清为 -1（改前返回 true 且 pid 残留）。
## 反向护栏：注入活 pid（本进程自身）→ 返回 true 且 pid 保留（防改过头杀健康实例）。
## 无头安全：清 pid 后走 editor+headless 分支 `DisplayServer.get_name()=="headless"` 直接 return false
## （:903-904，探针实测 HAS_EDITOR=true/DS=headless），零真 spawn 零摄像头。
## 零磁盘写：设置门经 SaveManager._data 内存引用直改，终段还原 + save.json 逐字节自证。
const BRIDGE_SRC := "res://autoload/gesture_bridge.gd"
const SAVE_PATH := "user://save.json"
var _pre_save_text := ""
var _orig_gi := true
var _orig_ce := true

## null/异型安全布尔读（bool(null) 4.7 无构造器中止坑防御）
func _to_bool(v: Variant, d: bool) -> bool:
	if typeof(v) == TYPE_BOOL:
		return v
	if typeof(v) == TYPE_INT:
		return int(v) != 0
	if typeof(v) == TYPE_STRING:
		return String(v) == "true" or String(v) == "1"
	return d

func _initialize() -> void:
	print("== test_fix_gesture_bridge_pid ==")
	if FileAccess.file_exists(SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(SAVE_PATH)
	await process_frame
	var save: Node = root.get_node("SaveManager")
	check(save != null, "前置：SaveManager 在位")
	if save == null:
		finish()
		return
	var settings_v: Variant = save.call("get_settings")
	check(typeof(settings_v) == TYPE_DICTIONARY, "前置：get_settings 返回字典")
	if typeof(settings_v) != TYPE_DICTIONARY:
		finish()
		return
	var settings: Dictionary = settings_v
	# 判空防御（4.7 实证规律⑦：bool(null) 无构造器中止 _initialize——并行跑测期存档态可能缺键）
	_orig_gi = _to_bool(settings.get("gesture_input"), true)
	_orig_ce = _to_bool(settings.get("gesture_camera_enabled"), true)
	# 设置门放行（OR 双键任一开即允许；内存直改零写盘）——用户档可能为 Q3 双关态
	settings["gesture_input"] = true
	# 独立桥实例（端口隔离，绝不动 autoload 桥；无头下 start 恒不真 spawn）
	var sub := GDScript.new()
	sub.source_code = """
extends "res://autoload/gesture_bridge.gd"
"""
	var err: int = int(sub.reload())
	check_eq(err, 0, "前置：桥测试子类编译成功")
	if err != int(OK):
		finish()
		return
	var br: Node = sub.new()
	br.set("_udp_port_override", 20410)
	add_child(br)
	await process_frame

	# ---- 反向护栏：活 pid（本进程自身）→ 复用返回 true、pid 保留 ----
	var alive_pid: int = OS.get_process_id()
	br.set("_process_pid", alive_pid)
	var ret_alive: bool = bool(br.call("start_gesture_process"))
	check_eq(ret_alive, true, "反向护栏：活 pid → start 返回 true（已有活实例复用）")
	check_eq(int(br.get("_process_pid")), alive_pid, "反向护栏：活 pid → pid 保留（不误清）")

	# ---- 红测：死 pid → 返回 false 且 pid 被清（改前 return true + pid 残留） ----
	# 生成确定性死进程：cmd /c exit 立即退出，轮询至 OS.is_process_running==false
	var dead_pid: int = OS.create_process("cmd.exe", ["/c", "exit"])
	check(dead_pid > 0, "前置：短命进程已创建（死 pid 样本）")
	var waited := 0
	while dead_pid > 0 and OS.is_process_running(dead_pid) and waited < 300:
		await process_frame
		waited += 1
	check(dead_pid <= 0 or not OS.is_process_running(dead_pid),
		"前置：死 pid 样本已退出（等待 %d 帧）" % waited)
	br.set("_process_pid", dead_pid)
	br.set("_respawn_block_until", -1.0)
	var ret_dead: bool = bool(br.call("start_gesture_process"))
	check_eq(ret_dead, false,
		"P3 红测：死 pid → start 返回 false（改前把死进程当活实例 return true）")
	check_eq(int(br.get("_process_pid")), -1,
		"P3 红测：死 pid → _process_pid 被清（改前 pid 残留导致后续永不重拉）")

	# ---- 源锚（防御纵深，锁修法形态） ----
	var src: String = FileAccess.get_file_as_string(BRIDGE_SRC)
	var i: int = src.find("func start_gesture_process(")
	var seg: String = src.substr(i, 900) if i >= 0 else ""
	check(seg.contains("is_process_running"),
		"源锚：start_gesture_process 防重入门含 OS.is_process_running 存活判定")

	# 收尾：还原内存设置 + pid + save.json 逐字节自证
	br.set("_process_pid", -1)
	settings["gesture_input"] = _orig_gi
	settings["gesture_camera_enabled"] = _orig_ce
	br.free()
	var post: String = FileAccess.get_file_as_string(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：save.json 起测/终测逐字节等价（本测试零写盘）")
	finish()
