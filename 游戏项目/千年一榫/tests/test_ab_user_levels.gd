extends "res://tests/test_base.gd"
## 批次 AB-4：玩家自定义关卡「搭桥」测试（**扫描载入路径 + 预留 UI 挂点，零玩家可见入口**）。
##
## 覆盖六组断言（任务书口径）：
##   U 组：user://user_levels 目录口径 + 合并扫描（2 合法 + 1 坏档 → 隔离：坏档跳过 + 告警 +
##         不影响其余关卡 + scan_finished 恒发）——沿用 W9-2（批次 AA）逐文件隔离纪律；
##   N 组：用户关卡与内置关卡**不互相遮蔽**（同 chapter → 内置优先；`get_level` 永不返回用户关
##         → 主进度零消费用户关，即「功能在游戏内不可达」）；
##   S 组：来源标记 source="builtin"|"user"（+ 既有 is_user_created 标记保留）；
##   A 组：载入 API 可用（get_user_level_list / get_user_level / is_user_level_id /
##         get_merged_level_list / get_user_error / write_user_level / 默认目录常量）；
##   R 组：**反向护栏**——用户目录为空/不存在时，内置表与合并视图与改动前逐字节一致
##         （内置关卡数/顺序/内容零变化）；
##   C 组（可选推荐项）：编辑器五件套 → 游戏侧契约 JSON 转换函数（与 AB-1 导入脚本同口径）；
##         编辑器工程缺失时按 test_w_contract 的 skip 语义计通过 check，不假红。
##
## user:// 纪律：本测试只在 `user://ab4_user_levels_probe/` 探测目录内读写，终测彻底删除；
## 对正式 `user://user_levels/` 仅断言「不存在时静默 + 零落盘」，**不写正式目录**；零触碰 save.json。
## 节点生命周期：被测 LevelLibrary 实例不入树（`new()` 直用 + `free()`），避免「in-tree free」噪声。

const LIB_SCRIPT := "res://autoload/level_library.gd"
const PROBE := "user://ab4_user_levels_probe"
const USER_DIR := "user://user_levels"
const EDU_LEVELS_ENV := "VOXEL_EDITOR_LEVELS_ROOT_FOR_TEST"
const BUILTIN_COUNT := 5

var _scan_fired: bool = false
var _scan_loaded: int = -1
var _scan_failed: int = -1
var _emit_count: int = 0

func _on_scan(loaded: int, failed: int) -> void:
	_scan_fired = true
	_scan_loaded = loaded
	_scan_failed = failed
	_emit_count += 1

# ---------- 夹具工具（沙盒专用，零触碰 save.json） ----------
func _read_file(p: String) -> String:
	var f: FileAccess = FileAccess.open(p, FileAccess.READ)
	if f == null:
		return ""
	var t: String = f.get_as_text()
	f.close()
	return t

func _load_json_dict(p: String) -> Dictionary:
	var v: Variant = JSON.parse_string(_read_file(p))
	return v if v is Dictionary else {}

func _write_json(p: String, d: Dictionary) -> void:
	var f: FileAccess = FileAccess.open(p, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d, "  ", false) + "\n")
		f.close()

func _ensure_dir(path: String) -> void:
	var parent := path.get_base_dir()
	var pd: DirAccess = DirAccess.open(parent)
	if pd != null and not pd.dir_exists(path.get_file()):
		pd.make_dir(path.get_file())

func _remove_path(p: String) -> void:
	if p.is_empty():
		return
	if DirAccess.dir_exists_absolute(p):
		# 4.7 实证两连败写法皆弃：实例 `d.remove_recursive(...)` →「Nonexistent function
		# 'remove_recursive' in base 'DirAccess'」；静态 `DirAccess.remove_recursive(...)` →
		#「Static function not found」。改工程既有口径（test_aa_camera_gate 等）：
		# 逐文件 DirAccess.remove_absolute 递归删，最后删空目录本身。
		var d: DirAccess = DirAccess.open(p)
		if d != null:
			d.list_dir_begin()
			var fn: String = d.get_next()
			while fn != "":
				if d.current_is_dir():
					_remove_path(p.path_join(fn))
				else:
					DirAccess.remove_absolute(p.path_join(fn))
				fn = d.get_next()
			d.list_dir_end()
		DirAccess.remove_absolute(p)
	elif FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)

func _purge_probe() -> void:
	_remove_path(PROBE)

## 合成一份**最小合法**关卡档（不依赖既有夹具内容，避免夹具漂移连带红）。
func _mk_level(ch: int, id: String) -> Dictionary:
	return {
		"format_version": 1,
		"level_id": id,
		"chapter": ch,
		"title": "自定义_%d" % ch,
		"era": "",
		"pieces": [{
			"piece_id": "p1",
			"name": "主体",
			"block_size": {"x": 4, "y": 3, "z": 4},
			"blocks": ["0,0,0", "1,0,0", "2,0,0", "3,0,0", "0,1,0", "1,1,0", "2,1,0", "3,1,0",
				"0,2,0", "1,2,0", "2,2,0", "3,2,0"],
			"target_shapes": [["1,0,1", "2,0,1", "1,1,1", "2,1,1", "1,2,1", "2,2,1"]],
			"join_part": {"size": {"x": 4, "y": 3, "z": 4},
				"voxels": ["1,0,1", "2,0,1", "1,1,1", "2,1,1", "1,2,1", "2,2,1"]},
			"final_answer": {"size": {"x": 4, "y": 3, "z": 4},
				"voxels": ["1,0,0", "2,0,0", "1,1,0", "2,1,0", "1,0,1", "2,0,1",
					"1,1,1", "2,1,1"]},
		}],
	}

## 合成一份**坏档**（target_shapes 组元素非数组 → validate_level 走 reject，W9-2 同族形态）。
func _mk_bad_level(ch: int, id: String) -> Dictionary:
	var d: Dictionary = _mk_level(ch, id)
	(d["pieces"] as Array)[0]["target_shapes"] = ["abc"]
	return d

func _new_lib() -> Node:
	return (load(LIB_SCRIPT) as GDScript).new()

func _connect(lib: Node) -> void:
	if not lib.scan_finished.is_connected(_on_scan):
		lib.scan_finished.connect(_on_scan)
	_scan_fired = false
	_scan_loaded = -1
	_scan_failed = -1
	_emit_count = 0

func _disconnect(lib: Node) -> void:
	if lib.scan_finished.is_connected(_on_scan):
		lib.scan_finished.disconnect(_on_scan)

## 脚本常量安全读取（GDScript const 不进 property_list，须走 get_script_constant_map，4.7 实测）。
func _const(obj: Object, prop: String) -> Variant:
	var s: Script = obj.get_script()
	if s == null:
		return null
	var cm: Dictionary = s.get_script_constant_map()
	return cm[prop] if cm.has(prop) else null

func _dump(v: Variant) -> String:
	return JSON.stringify(v)

# ---------- U 组：user 目录扫描 + 合并 + 坏档隔离 ----------
func _u_merge_isolation() -> void:
	print("-- U 组：user_levels 合并扫描与坏档逐文件隔离 --")
	_purge_probe()
	_ensure_dir(PROBE)
	_write_json(PROBE.path_join("ab4_u_a.json"), _mk_level(2, "ab4_u_a"))
	_write_json(PROBE.path_join("ab4_u_b.json"), _mk_level(3, "ab4_u_b"))
	_write_json(PROBE.path_join("ab4_u_bad.json"), _mk_bad_level(4, "ab4_u_bad"))
	var lib: Node = _new_lib()
	_connect(lib)
	check(lib.has_method("scan_all"), "U0：存在合并扫描入口 scan_all（红：旧实现无本 API）")
	if lib.has_method("scan_all"):
		lib.call("scan_all", "res://levels_data", PROBE)
	check(_scan_fired, "U1：含坏档的合并扫描仍发射 scan_finished（隔离纪律，W9-2 同源）")
	check_eq(_emit_count, 1, "U2：一次合并扫描只发一次 scan_finished（不重复发射）")
	if lib.has_method("scan_all"):
		check_eq(_scan_loaded, BUILTIN_COUNT + 2, "U3：loaded=内置 5 + 用户合法 2（坏档不计数）")
		check_eq(_scan_failed, 1, "U4：failed=1（坏档计入留痕计数）")
	var ul: Array = lib.call("get_user_level_list")
	check_eq(ul.size(), 2, "U5：用户关卡表只含 2 份合法档（坏档被跳过）")
	var ids: Array[String] = []
	for e: Dictionary in ul:
		ids.append(String(e.get("level_id", "")))
	check(ids.has("ab4_u_a") and ids.has("ab4_u_b") and not ids.has("ab4_u_bad"),
		"U6：坏档不入用户关卡表，两份合法档在表（%s）" % ",".join(ids))
	if lib.has_method("get_user_error"):
		check(String(lib.call("get_user_error", "ab4_u_bad")).contains("target_shapes"),
			"U7：坏档拒绝原因按 level_id 留痕（get_user_error）")
		check_eq(String(lib.call("get_user_error", "ab4_u_a")), "", "U8：合法用户关无错误留痕")
	else:
		check(false, "U7：存在按 level_id 的坏档原因留痕 API（红：旧实现无）")
		check(false, "U8：合法用户关无错误留痕（红：旧实现无）")
	# 内置关卡不受影响（同一 lib 实例）
	check_eq((lib.call("get_level_list") as Array).size(), BUILTIN_COUNT,
		"U9：内置 5 关不受用户坏档影响（逐文件隔离不外溢）")
	check(not (lib.call("get_level_list") as Array).any(
		func(x: Dictionary) -> bool: return String(x.get("level_id", "")).begins_with("ab4_u")),
		"U10：用户档不泄入内置表（分表存放）")
	_disconnect(lib)
	lib.free()

# ---------- N 组：不互相遮蔽 ----------
func _n_no_shadowing() -> void:
	print("-- N 组：用户关卡与内置关卡不互相遮蔽 --")
	_purge_probe()
	_ensure_dir(PROBE)
	# 与内置 chapter=2 同章的用户关 + 一个不占新章的合法用户关（id 唯一）
	_write_json(PROBE.path_join("ab4_shadow.json"), _mk_level(2, "ab4_shadow_ch2"))
	_write_json(PROBE.path_join("ab4_free.json"), _mk_level(3, "ab4_free_ch3"))
	var lib: Node = _new_lib()
	_connect(lib)
	if lib.has_method("scan_all"):
		lib.call("scan_all", "res://levels_data", PROBE)
	var ul: Array = lib.call("get_user_level_list")
	check_eq(ul.size(), 2, "N1：同章用户关不因内置同章关被丢弃（各自独立成表）")
	# 内置 get_level 恒取内置档：chapter=2 仍是内置 level_chapter2_song（level_id=chapter2_editor）
	var b2: Dictionary = lib.call("get_level", 2)
	check_eq(String(b2.get("level_id", "")), "chapter2_editor",
		"N2：get_level(2) 仍返回内置关（用户同章关不遮蔽主进度）")
	check_eq(String(b2.get("title", "")), "第二关", "N3：get_level(2) 内容未被用户档污染")
	check_eq((lib.call("get_level_list") as Array).size(), BUILTIN_COUNT,
		"N4：内置关卡表不因用户关增长（零污染）")
	var found: bool = false
	for e: Dictionary in ul:
		if String(e.get("level_id", "")) == "ab4_shadow_ch2":
			found = true
	check(found, "N5：同章用户关仍在用户表（内置不遮蔽用户）")
	if lib.has_method("is_user_level_id"):
		check(bool(lib.call("is_user_level_id", "ab4_shadow_ch2")), "N6：is_user_level_id 认可用户关")
		check(not bool(lib.call("is_user_level_id", "chapter2_editor")), "N7：is_user_level_id 对内置关为假")
	else:
		check(false, "N6：存在 is_user_level_id 判定 API（红：旧实现无）")
		check(false, "N7：is_user_level_id 对内置关为假（红：旧实现无）")
	if lib.has_method("get_merged_level_list"):
		var ml: Array = lib.call("get_merged_level_list")
		check_eq(ml.size(), BUILTIN_COUNT + 2, "N8：合并视图=内置 5 + 用户 2（共存不遮蔽）")
		# 同 chapter 排序：内置在前、用户在后（优先级规则=内置优先，确定性）
		var order: Array[String] = []
		for e: Dictionary in ml:
			if int(e.get("chapter", 0)) == 2:
				order.append(String(e.get("source", "?")))
		check_eq(",".join(order), "builtin,user", "N9：同 chapter 时内置排在前（合并序规则=内置优先）")
	else:
		check(false, "N8：存在合并视图 API（红：旧实现无）")
		check(false, "N9：同 chapter 内置优先（红：旧实现无）")
	if lib.has_method("get_user_level"):
		var g: Dictionary = lib.call("get_user_level", "ab4_free_ch3")
		check(not g.is_empty() and String(g.get("level_id", "")) == "ab4_free_ch3",
			"N10：get_user_level(id) 按 id 取回用户关")
		# 4.7 合法写法：String(Dictionary) 属「No constructor of String matches …」Parse Error 族
		# （实证规律；本文件首跑红态 :220 即此）。改为类型守卫 + has 键判定，
		# 断言不弱化反而更强：既要求 data 是字典，又要求其含 pieces 键。
		var gdata_v: Variant = g.get("data", null)
		check(typeof(gdata_v) == TYPE_DICTIONARY and (gdata_v as Dictionary).has("pieces"),
			"N10b：取回条目携带完整 data（可交 level_scene 消费）")
		check_eq(_dump(lib.call("get_user_level", "no_such_id")), "{}", "N11：未知 id 返回空字典")
	else:
		check(false, "N10：存在 get_user_level(id) 载入 API（红：旧实现无）")
		check(false, "N10b：取回条目携带完整 data（红：旧实现无）")
		check(false, "N11：未知 id 返回空字典（红：旧实现无）")
	_disconnect(lib)
	lib.free()

# ---------- S 组：来源标记 ----------
func _s_source_marks() -> void:
	print("-- S 组：来源标记 source --")
	_purge_probe()
	_ensure_dir(PROBE)
	_write_json(PROBE.path_join("ab4_s1.json"), _mk_level(2, "ab4_s1"))
	var lib: Node = _new_lib()
	_connect(lib)
	if lib.has_method("scan_all"):
		lib.call("scan_all", "res://levels_data", PROBE)
	var bl: Array = lib.call("get_level_list")
	var mark_bad: Array[String] = []
	for e: Dictionary in bl:
		if String(e.get("source", "")) != "builtin":
			mark_bad.append(String(e.get("level_id", "?")))
	check_eq(_dump(mark_bad), "[]", "S1：内置关卡全部标记 source=\"builtin\"（违例=%s）" % ",".join(mark_bad))
	var ul: Array = lib.call("get_user_level_list")
	var umark_bad: Array[String] = []
	for e2: Dictionary in ul:
		if String(e2.get("source", "")) != "user":
			umark_bad.append(String(e2.get("level_id", "?")))
	check_eq(_dump(umark_bad), "[]", "S2：用户关卡全部标记 source=\"user\"")
	check_eq(ul.size(), 1, "S2b：本轮用户表恰 1 关（前置成立）")
	if ul.size() > 0:
		var u0: Dictionary = ul[0]
		check(bool(u0.get("is_user_created", false)), "S3：用户关卡保留既有 is_user_created=true 标记")
		check(bool((u0.get("data", {}) as Dictionary).get("is_user_created", false)),
			"S3b：data 体内同样带 is_user_created=true（向后兼容既有口径）")
		var b0: Dictionary = bl[0]
		check(not bool(b0.get("is_user_created", false)), "S4：内置条目不带 is_user_created")
	else:
		check(false, "S3：用户关卡保留 is_user_created 标记（红：用户表空）")
		check(false, "S3b：data 体内带 is_user_created（红：用户表空）")
		check(false, "S4：内置条目不带 is_user_created（红：前置失败）")
	_disconnect(lib)
	lib.free()

# ---------- A 组：载入 API 与默认目录口径 ----------
func _a_api_and_dir() -> void:
	print("-- A 组：载入 API / 默认目录口径 / 写盘 helper --")
	var lib: Node = _new_lib()
	check(lib.has_method("scan_all"), "A1：scan_all（合并扫描）就位")
	for m: String in ["get_user_level_list", "get_user_level", "is_user_level_id",
			"get_merged_level_list", "get_user_error", "write_user_level"]:
		check(lib.has_method(m), "A2：载入/写盘 API `%s` 就位" % m)
	var dflt: Variant = _const(lib, "USER_LEVEL_DIR")
	check(dflt != null, "A3：USER_LEVEL_DIR 常量在位")
	if dflt != null:
		var d: String = String(dflt)
		check(d.begins_with("user://"), "A4：默认用户关卡目录落 user://（打包态 res:// 只读）：实际=%s" % d)
		check(d.ends_with("user_levels"), "A5：默认目录名沿用既有约定 user_levels：实际=%s" % d)
	else:
		check(false, "A4：默认目录口径 user://（红：常量缺失）")
		check(false, "A5：默认目录名 user_levels（红：常量缺失）")
	# 默认目录：不存在（本机实况）时静默返回、不崩、零落盘
	var exists_before: bool = DirAccess.dir_exists_absolute(USER_DIR)
	lib.call("scan_directory")
	lib.call("scan_user_directory")
	check_eq(DirAccess.dir_exists_absolute(USER_DIR), exists_before,
		"A6：只读扫描零落盘（不擅自创建 user://user_levels）")
	check_eq((lib.call("get_user_level_list") as Array).size(), 0, "A7：默认目录不存在时用户表为空（预留态静默）")
	# write_user_level 到探测目录 → 可被扫描读回（闭环）
	_purge_probe()
	_ensure_dir(PROBE)
	if lib.has_method("write_user_level"):
		check(bool(lib.call("write_user_level", _mk_level(2, "ab4_w1"), PROBE)),
			"A8：write_user_level 落盘成功（探测目录）")
		check(FileAccess.file_exists(PROBE.path_join("ab4_w1.json")), "A9：落盘文件名=level_id.json")
		_connect(lib)
		if lib.has_method("scan_all"):
			lib.call("scan_all", "res://levels_data", PROBE)
		var got: Dictionary = lib.call("get_user_level", "ab4_w1")
		check(not got.is_empty(), "A10：写盘 → 再扫描 → 按 id 读回闭环")
		if not got.is_empty():
			check_eq(int((got.get("data", {}) as Dictionary).get("chapter", 0)), 2,
				"A11：读回档内容（chapter）与写入一致")
			# 非法档拒绝写盘（不落脏档）
			var bad_doc: Dictionary = _mk_level(2, "ab4_wbad")
			bad_doc["format_version"] = 99
			check(not bool(lib.call("write_user_level", bad_doc, PROBE)),
				"A12：write_user_level 先校验后落盘（非法档拒写、不留脏档）")
			check(not FileAccess.file_exists(PROBE.path_join("ab4_wbad.json")),
				"A13：拒写的脏档确实不在盘上")
		else:
			check(false, "A11：读回内容一致（红：读回失败）")
			check(false, "A12：先校验后落盘（红：读回失败）")
			check(false, "A13：脏档不在盘（红：读回失败）")
		_disconnect(lib)
	else:
		check(false, "A8：write_user_level 落盘（红：旧实现无）")
		check(false, "A9：落盘文件名口径（红：旧实现无）")
		check(false, "A10：写读闭环（红：旧实现无）")
		check(false, "A11：读回内容一致（红：旧实现无）")
		check(false, "A12：先校验后落盘（红：旧实现无）")
		check(false, "A13：脏档不在盘（红：旧实现无）")
	lib.free()
	_purge_probe()

# ---------- R 组：反向护栏（默认态零变化） ----------
func _r_default_zero_change() -> void:
	print("-- R 组：用户目录为空时行为与改动前完全一致 --")
	_purge_probe()
	_ensure_dir(PROBE)   # 空目录（验「空」而非「无」）
	# 参照实例：走旧口径 scan_directory（内置表）
	var ref: Node = _new_lib()
	_connect(ref)
	ref.call("scan_directory", "res://levels_data")
	var ref_emit: int = _emit_count
	var ref_loaded: int = _scan_loaded
	var ref_failed: int = _scan_failed
	var ref_json: String = _dump(ref.call("get_level_list"))
	var ref_merged: String = _dump(ref.call("get_merged_level_list")) if ref.has_method("get_merged_level_list") else ""
	_disconnect(ref)
	ref.free()
	check_eq(ref_emit, 1, "R0：单扫描仍恰发一次 scan_finished（旧口径不变）")
	check_eq(ref_loaded, BUILTIN_COUNT, "R0b：单扫描 loaded=5（旧口径不变）")
	check_eq(ref_failed, 0, "R0c：单扫描 failed=0（旧口径不变）")
	# 新实例：走合并扫描（用户目录为空）
	var lib: Node = _new_lib()
	_connect(lib)
	if lib.has_method("scan_all"):
		lib.call("scan_all", "res://levels_data", PROBE)
	check_eq(_emit_count, 1, "R1：空用户目录仍只发一次 scan_finished")
	check_eq(_scan_loaded, BUILTIN_COUNT, "R2：loaded=5（内置全量，与改动前同）")
	check_eq(_scan_failed, 0, "R3：failed=0（与改动前同）")
	var lst: Array = lib.call("get_level_list")
	check_eq(lst.size(), BUILTIN_COUNT, "R4：内置关卡数零变化")
	var merged: Array = lib.call("get_merged_level_list") if lib.has_method("get_merged_level_list") else []
	# 逐字节对账：合并扫描后的内置表 == 单扫描内置表（同码对照，锁死「用户通道零侵入」）
	var same_bytes: bool = (_dump(lst) == ref_json)
	check(same_bytes, "R5：内置关卡表逐字节一致（数/序/内容/source/path/data 零变化）")
	if not same_bytes:
		print("  [diff] ref=%s" % ref_json.left(400))
		print("  [diff] new=%s" % _dump(lst).left(400))
	check_eq(_dump(merged), ref_merged, "R6：空用户目录时合并视图 == 内置视图（无幽灵行）")
	check_eq((lib.call("get_user_level_list") as Array).size(), 0, "R7：用户关卡表为空")
	# get_level 逐章与「旧口径单扫描」参照实例一致
	var ref2: Node = _new_lib()
	ref2.call("scan_directory", "res://levels_data")
	var ch_ok: bool = true
	var ch_bad: Array[String] = []
	for ch2: int in range(1, 6):
		var a: Dictionary = lib.call("get_level", ch2)
		var b: Dictionary = ref2.call("get_level", ch2)
		if _dump(a) != _dump(b):
			ch_ok = false
			# 4.7 合法写法：String(int) 同属 Parse Error 族（首跑红态 :376）。改格式化串，等价。
			ch_bad.append("%d" % ch2)
	check(ch_ok, "R9：get_level(1..5) 与改动前口径逐章一致（违例章=%s）" % ",".join(ch_bad))
	ref2.free()
	# 兜底重扫口径（main.gd 启动扫描 / level_scene 缺章兜底）：单参 scan_directory 向后兼容
	lib.call("scan_directory", "res://levels_data")
	check_eq((lib.call("get_level_list") as Array).size(), BUILTIN_COUNT,
		"R10：单参 scan_directory 向后兼容（既有调用点零改动）")
	_disconnect(lib)
	lib.free()
	_purge_probe()

# ---------- C 组：编辑器五件套 → 游戏侧契约 JSON 转换 ----------
func _c_five_piece_convert() -> void:
	print("-- C 组：编辑器五件套 → 游戏侧关卡 JSON 转换函数 --")
	var lib: Node = _new_lib()
	if not lib.has_method("convert_editor_level"):
		check(false, "C1：存在 convert_editor_level（五件套→契约 JSON，红：旧实现无）")
		lib.free()
		return
	check(true, "C1：convert_editor_level 就位")
	var levels_root: String = _resolve_editor_levels_root()
	if levels_root.is_empty() or not DirAccess.dir_exists_absolute(levels_root):
		check(true, "C2：[SKIPPED] 编辑器 levels/ 根不可达（打包/克隆环境无编辑器）→ 计通过不假红")
		print("[SKIPPED] 编辑器 levels 根缺失：%s" % levels_root)
		lib.free()
		return
	var ch1: Dictionary = _load_json_dict("res://levels_data/level_chapter1_hemudu.json")
	var pc_ref: Dictionary = ((ch1.get("pieces", []) as Array)[0] if not ch1.is_empty() else {}) as Dictionary
	var any_slot: bool = false
	for n: int in range(1, 6):
		var dir: String = levels_root.path_join("level_%d" % n)
		if not DirAccess.dir_exists_absolute(dir):
			continue
		var doc: Dictionary = lib.call("convert_editor_level", dir)
		if doc.is_empty():
			continue   # 空骨架槽/未成品槽=编辑器设计态（test_w_contract 同 skip 语义）
		any_slot = true
		var res: Dictionary = lib.call("validate_level", doc)
		check(bool(res.get("ok", false)), "C2-%d：level_%d 五件套转换 → validate_level 零 reject（%s）" % [
			n, n, String(res.get("reject", ""))])
		var top_ok: bool = true
		for k: String in ["format_version", "level_id", "chapter", "title", "era",
				"theme", "description", "anim_time", "grid_size_unused", "pieces"]:
			if not doc.has(k):
				top_ok = false
		check(top_ok, "C3-%d：level_%d 顶层键集合=契约 10 键（与第 1 关导入件同构）" % [n, n])
		if not pc_ref.is_empty():
			var pc: Dictionary = (doc["pieces"] as Array)[0]
			var piece_ok: bool = true
			for k2: String in pc_ref.keys():
				if not pc.has(k2):
					piece_ok = false
			check(piece_ok, "C4-%d：level_%d piece 键集合覆盖第 1 关导入件键集" % [n, n])
		check_eq(int(doc.get("chapter", 0)), n, "C5-%d：level_%d 转换保真 chapter" % [n, n])
		var pcs: Array = doc.get("pieces", [])
		var bs: Dictionary = ((pcs[0] if not pcs.is_empty() else {}) as Dictionary).get("block_size", {})
		var tsz: Dictionary = ((pcs[0] if not pcs.is_empty() else {}) as Dictionary).get("target_size", {})
		check(not tsz.is_empty() and _dump(tsz) == _dump(bs),
			"C6-%d：level_%d target_size 显式补齐=block_size（AB-1 导入脚本同口径）" % [n, n])
	if not any_slot:
		check(true, "C2b：[SKIPPED] 编辑器五件套槽全空 → 计通过不假红")
	lib.free()

func _resolve_editor_levels_root() -> String:
	var env: String = OS.get_environment(EDU_LEVELS_ENV)
	if not env.is_empty():
		return env
	var game_root: String = ProjectSettings.globalize_path("res://")
	if game_root.is_empty():
		return ""
	return game_root.simplify_path().path_join("../../关卡编辑器/voxel_level_editor/levels/").simplify_path()

func _initialize() -> void:
	print("== test_ab_user_levels ==")
	var had_user_dir: bool = DirAccess.dir_exists_absolute(USER_DIR)
	_u_merge_isolation()
	_n_no_shadowing()
	_s_source_marks()
	_a_api_and_dir()
	_r_default_zero_change()
	_c_five_piece_convert()
	_purge_probe()
	check_eq(DirAccess.dir_exists_absolute(USER_DIR), had_user_dir,
		"Z1：终测未改动 user://user_levels 存在性（探测目录零污染正式目录）")
	check(not DirAccess.dir_exists_absolute(PROBE), "Z2：探测目录已彻底删除")
	finish()
