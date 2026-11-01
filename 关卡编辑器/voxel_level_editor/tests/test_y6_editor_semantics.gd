extends "res://tests/test_base.gd"
## test_y6_editor_semantics：批次 Y6（spec §9.4，Y-D1~Y-D5）——
## Y-D1 level_1 五件套数据修复锚：target/final 内容对调画像（target=160 格挖除形/12×3×5 域、
##   final=330 格拼合形/12×7×8 域、blocks=180、join=122 不动）+ 整值规范化（全文档零整值 float）
##   + 规范化往返零 diff（装配→load_from_text→save_to_text→_split_doc 逐文件字节对账）。
## Y-D2 语义副标注节点锚：三域 tab 副标注（TabTargetSub/TabJoinSub/TabFinalSub）+
##   试玩对照面板副标注（TargetPanel/SubTitle、JoinPanel/SubTitle）。
## Y-D3 contract_hint 可挖出性两条软提示（非阻断）：①target 格数>blocks 或归一 bbox 越出
##   blocks 域→「该关可能不可通关…」；②final≠target∪join（格集合不等）→「最终成品与
##   标准答案∪对接件 不一致…」。反例触发 + 合法关卡零误报 + 空集/超域既有分支优先级不变。
## Y-D4 试玩反馈增强：success 由 2.5s toast 升级常驻通关横幅 PlaytestBanner（进试玩新局或
##   退出试玩才清除，红测含 >2.5s 常驻断言）；btn_join hover 提示补「对称/旋转/镜像均认可」。
## Y-D5 跨工程防漂移锚：编辑器 scripts/join_transform.gd 与主游戏 游戏项目/千年一榫/scripts/
##   join_transform.gd 逐字节一致（不可达时降级哈希常量比对+告警；负控证「改动一侧即红」）。
## 磁盘纪律（对齐 test_w_editor）：沙盒一律 TEMP 一次性子目录，真实 levels/ 只读零写入；
## 红期新常量经字面量/LP.get 动态读取（缺失=null 断言干净失败零 SCRIPT ERROR），新节点
## get_node_or_null 红期缺席不崩。Godot 4.7 坑对齐：.get 防御取键、Variant
## 判空后强转、add_child 后 await process_frame。

const LS := preload("res://scripts/level_slots.gd")
const LP := preload("res://scripts/level_project.gd")

const JT_PATH := "res://scripts/join_transform.gd"
## Y-D5 降级哈希常量（2026-09-23 两工程文件 sha256 实测一致值；仅主游戏侧文件不可达时启用比对）
const GAME_JT_SHA256 := "701dcc2e463dbf4c91ef53003d01f93196b0da88f54a31fe53937ba609c165f8"
## Y-D3 两条提示文案字面量（与 level_project.gd 常量逐字一致；红期常量缺席按字面量比对）
const HINT_UNDIGGABLE_TEXT := "该关可能不可通关：标准答案挖不出（超出初始木块范围）"
const HINT_FINAL_MISMATCH_TEXT := "最终成品与 标准答案∪对接件 不一致（契约供校验，不强制）"

const SLOT1_DIR := "res://levels/level_1/"
const FIVE_FILES: Array[String] = ["level.json", "blocks.json", "target.json", "join.json", "final.json"]

var _sandboxes: Array[String] = []
var _ed_last: Control = null

func _initialize() -> void:
	print("== test_y6_editor_semantics（批次 Y6：Y-D1/Y-D2/Y-D3/Y-D4/Y-D5） ==")
	OS.set_environment("VOXEL_EDITOR_SLOTS_ROOT", "")
	OS.set_environment("VOXEL_EDITOR_DEFAULT_SOURCE", "")
	_a_yd1_data_anchor()
	_b_yd3_contract_hints()
	_c_yd5_cross_project_anchor()
	await _d_yd4_playtest_banner()
	_e_yd2_sub_labels()
	_cleanup()
	finish()

# ---------- 沙盒 / 通用 helper ----------
func _make_sandbox(tag: String) -> String:
	var base := OS.get_environment("TEMP")
	if base.is_empty():
		base = "/tmp"
	base = base.replace("\\", "/")
	var dir: String = base.path_join("voxel_editor_y6_%s_%d" % [tag, Time.get_ticks_msec()]) + "/"
	_sandboxes.append(dir)
	return dir

func _remove_dir_recursive(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	da.list_dir_begin()
	var item := da.get_next()
	while item != "":
		if item != "." and item != "..":
			var full := path.path_join(item)
			if da.current_is_dir():
				_remove_dir_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		item = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(path)

func _cleanup() -> void:
	if _ed_last is Node:
		(_ed_last as Node).free()
	_ed_last = null
	OS.set_environment("VOXEL_EDITOR_SLOTS_ROOT", "")
	OS.set_environment("VOXEL_EDITOR_DEFAULT_SOURCE", "")
	for dir: String in _sandboxes:
		_remove_dir_recursive(dir)
	_sandboxes.clear()

## 全文档递归统计「整值 float」个数（Y-D1 规范化直接断言；口径=level_project._normalize_json_ints）。
func _int_float_count(v: Variant) -> int:
	var n := 0
	if v is Array:
		for e: Variant in v:
			if e is float and float(e) == floorf(float(e)):
				n += 1
			elif e is Array or e is Dictionary:
				n += _int_float_count(e)
	elif v is Dictionary:
		for k: Variant in v:
			var e: Variant = v[k]
			if e is float and float(e) == floorf(float(e)):
				n += 1
			elif e is Array or e is Dictionary:
				n += _int_float_count(e)
	return n

## 集合归一 bbox 三维（min 角平移后 max−min+1；空集返回 ZERO——调用方保证非空）。
func _norm_bbox_dims(cells: Dictionary) -> Vector3i:
	var mn := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var mx := Vector3i(-(1 << 30), -(1 << 30), -(1 << 30))
	for c_v: Variant in cells:
		var c: Vector3i = c_v
		mn.x = mini(mn.x, c.x); mn.y = mini(mn.y, c.y); mn.z = mini(mn.z, c.z)
		mx.x = maxi(mx.x, c.x); mx.y = maxi(mx.y, c.y); mx.z = maxi(mx.z, c.z)
	if mx.x < 0:
		return Vector3i.ZERO
	return mx - mn + Vector3i.ONE

func _real_levels_root() -> String:
	return ProjectSettings.globalize_path("res://levels/")

# ============ A 组（Y-D1）：level_1 五件套数据修复锚 ============
func _a_yd1_data_anchor() -> void:
	# A1 五件在盘且可解析
	var docs: Dictionary = {}
	for name: String in FIVE_FILES:
		var text := FileAccess.get_file_as_string(SLOT1_DIR + name)
		check(not text.is_empty(), "A1: level_1/%s 在盘非空" % name)
		var parsed: Variant = JSON.parse_string(text)
		check(parsed is Dictionary, "A1: level_1/%s 可解析为对象" % name)
		if parsed is Dictionary:
			docs[name] = parsed
	if docs.size() != FIVE_FILES.size():
		return
	# A2 整值规范化（文本级口径）：逐文件「归一重序列化==原字节」——4.7 JSON.parse_string 把一切
	# 数值回析为 float（引擎实证），解析后数 float 恒误报；真口径=盘上无 x.0 形态整值 token，
	# 即对文本 parse→_normalize_json_ints→stringify 幂等（重序列化逐字节等于原文）。
	for name: String in FIVE_FILES:
		var text2 := FileAccess.get_file_as_string(SLOT1_DIR + name)
		var d2: Variant = JSON.parse_string(text2)
		if not (d2 is Dictionary):
			check(false, "A2: %s 解析失败" % name)
			continue
		LP._normalize_json_ints(d2)
		var canon: String = JSON.stringify(d2, "  ", false) + "\n"
		check(canon == text2, "A2: %s 整值规范化（归一重序列化=原字节；canon len=%d 盘 len=%d）"
			% [name, canon.length(), text2.length()])
	# A3 规范化往返零 diff：装配文本→load_from_text→save_to_text→_split_doc→逐文件 stringify
	# 与盘上字节对账（编辑器自动保存写路径的确定性再现，规格 §9.3 四步序列化口径）。
	var assembled_v: Variant = LS.load_slot_text(1, _real_levels_root())
	check(assembled_v is String and not (assembled_v as String).is_empty(),
		"A3: 真实槽 1 装配文本非空")
	var p: RefCounted = LP.new()
	check(bool(p.call("load_from_text", assembled_v)), "A3: 装配文本过结构门")
	var save_text: String = p.call("save_to_text")
	var doc_v: Variant = JSON.parse_string(save_text)
	check(doc_v is Dictionary, "A3: save_to_text 可回析")
	if doc_v is Dictionary:
		var parts: Array = LS._split_doc(doc_v)
		check_eq(parts.size(), 5, "A3: 拆分五份")
		for i: int in FIVE_FILES.size():
			var expect: String = JSON.stringify(parts[i], "  ", false) + "\n"
			var actual: String = FileAccess.get_file_as_string(SLOT1_DIR + FIVE_FILES[i])
			check(actual == expect, "A3: %s 往返零 diff（规范化逐字节对账；len 盘=%d/算=%d）"
				% [FIVE_FILES[i], actual.length(), expect.length()])
	# A4 对调画像：target=160（12×3×5 域）/blocks=180/final=330（12×7×8 域）/join=122 不动
	var b_doc: Dictionary = docs["blocks.json"]
	var t_doc: Dictionary = docs["target.json"]
	var j_doc: Dictionary = docs["join.json"]
	var f_doc: Dictionary = docs["final.json"]
	var b_set: Dictionary = LP.strings_to_set(b_doc.get("blocks", []))
	var t_arr: Array = (t_doc.get("target_shapes", []) as Array)[0] as Array
	var t_set: Dictionary = LP.strings_to_set(t_arr)
	var j_set: Dictionary = LP.strings_to_set(j_doc.get("voxels", []))
	var f_set: Dictionary = LP.strings_to_set(f_doc.get("voxels", []))
	check_eq(t_set.size(), 160, "A4: 标准答案=160 格挖除形（原 final 内容）")
	check_eq(b_set.size(), 180, "A4: 初始木块=180 格（12×3×5 实心）")
	check_eq(f_set.size(), 330, "A4: 最终成品=330 格拼合形（原 target 内容）")
	check_eq(j_set.size(), 122, "A4: 对接件=122 格（内容不动）")
	check_eq(t_arr.size(), t_set.size(), "A4: target 无重复格")
	check_eq((j_doc.get("voxels", []) as Array).size(), j_set.size(), "A4: join 无重复格")
	var bs: Dictionary = b_doc.get("block_size", {})
	var b_dom := Vector3i(int(bs.get("x", 1)), int(bs.get("y", 1)), int(bs.get("z", 1)))
	check_eq(b_dom, Vector3i(12, 3, 5), "A4: blocks 域=12×3×5（整值）")
	var ts: Dictionary = t_doc.get("target_size", {})
	var t_dom := Vector3i(int(ts.get("x", 1)), int(ts.get("y", 1)), int(ts.get("z", 1)))
	check_eq(t_dom, Vector3i(12, 3, 5), "A4: target_size=12×3×5（整值，随对调内容落域）")
	var fs: Dictionary = f_doc.get("size", {})
	check_eq(Vector3i(int(fs.get("x", 1)), int(fs.get("y", 1)), int(fs.get("z", 1))),
		Vector3i(12, 7, 8), "A4: final size=12×7×8（整值，随对调内容落域）")
	check(t_set.size() <= b_set.size(), "A4: target 格数(160)≤blocks 格数(180)（可挖出性自查①）")
	var t_dims := _norm_bbox_dims(t_set)
	check(t_dims.x <= b_dom.x and t_dims.y <= b_dom.y and t_dims.z <= b_dom.z,
		"A4: target 归一 bbox %s 可被 blocks 域 %s 容纳（自查②）" % [t_dims, b_dom])
	var js: Dictionary = j_doc.get("size", {})
	check_eq(Vector3i(int(js.get("x", 1)), int(js.get("y", 1)), int(js.get("z", 1))),
		Vector3i(3, 7, 7), "A4: join 域=3×7×7 不动（自查③）")
	# A5 修后真实关零误报：contract_hint 不触发「不可通关」提示（Y-D3 提示①对合法关零误报实证）
	var p5: RefCounted = LP.new()
	check(bool(p5.call("load_from_text", assembled_v)), "A5: 真实装配文本再载过门")
	var hint_r: String = p5.call("contract_hint")
	check(hint_r != HINT_UNDIGGABLE_TEXT,
		"A5: 修后真实关不触发不可通关提示（实际=%s）" % hint_r)

# ============ B 组（Y-D3）：contract_hint 两条可挖出性软提示 ============
func _b_yd3_contract_hints() -> void:
	# B1 红锚：两常量在场（红期经实例动态取常量得 null，干净失败零 SCRIPT ERROR）
	var probe: RefCounted = LP.new()
	check(probe.get("HINT_UNDIGGABLE") != null, "B1: HINT_UNDIGGABLE 常量在场（红：Y-D3 未实施）")
	check(probe.get("HINT_FINAL_MISMATCH") != null, "B1: HINT_FINAL_MISMATCH 常量在场（红：Y-D3 未实施）")
	# B2 反例①a：target 格数 > blocks 格数 → 不可通关提示
	var p2: RefCounted = LP.new()
	p2.call("new_project", Vector3i(2, 2, 2))
	p2.call("set_voxel_set", LP.TAG_BLOCKS, {Vector3i(0, 0, 0): true})
	p2.call("set_voxel_set", LP.TAG_TARGET, {Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true})
	p2.call("set_voxel_set", LP.TAG_JOIN, {Vector3i(0, 0, 0): true})
	p2.call("set_voxel_set", LP.TAG_FINAL, {Vector3i(0, 0, 0): true})
	check_eq(p2.call("contract_hint"), HINT_UNDIGGABLE_TEXT,
		"B2: target 格数(2)>blocks 格数(1)→不可通关提示（反例触发）")
	# B3 反例①b：归一 bbox 越出 blocks 域（target 独立域 4×1×1 界内、blocks 域 2³ 容不下）
	var p3: RefCounted = LP.new()
	p3.call("new_project", Vector3i(2, 2, 2))
	p3.call("set_size_for_tag", LP.TAG_TARGET, Vector3i(4, 1, 1))
	p3.call("set_voxel_set", LP.TAG_TARGET,
		{Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true, Vector3i(2, 0, 0): true, Vector3i(3, 0, 0): true})
	p3.call("set_voxel_set", LP.TAG_JOIN, {Vector3i(0, 0, 0): true})
	p3.call("set_voxel_set", LP.TAG_FINAL, {Vector3i(0, 0, 0): true})
	check_eq(p3.call("contract_hint"), HINT_UNDIGGABLE_TEXT,
		"B3: target 归一 bbox(4×1×1) 越 blocks 域(2³)→不可通关提示（反例触发）")
	# B4 反例②：final≠target∪join（格集合不等）→ 语义提示
	var p4: RefCounted = LP.new()
	p4.call("new_project", Vector3i(2, 2, 2))
	p4.call("set_voxel_set", LP.TAG_TARGET, {Vector3i(0, 0, 0): true})
	p4.call("set_voxel_set", LP.TAG_JOIN, {Vector3i(0, 0, 0): true})
	p4.call("set_voxel_set", LP.TAG_FINAL, {Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true})
	check_eq(p4.call("contract_hint"), HINT_FINAL_MISMATCH_TEXT,
		"B4: final≠target∪join→不一致提示（反例触发；不可通关两查均过在前）")
	# B5 合法零误报：final==target∪join 且 target 可挖出 → 全部通过
	var p5: RefCounted = LP.new()
	p5.call("new_project", Vector3i(2, 2, 2))
	p5.call("set_voxel_set", LP.TAG_TARGET, {Vector3i(0, 0, 0): true})
	p5.call("set_voxel_set", LP.TAG_JOIN, {Vector3i(0, 0, 0): true})
	p5.call("set_voxel_set", LP.TAG_FINAL, {Vector3i(0, 0, 0): true})
	check_eq(p5.call("contract_hint"), LP.HINT_ALL_OK,
		"B5: 合法关（final=target∪join、target 界内可挖）零误报 ALL_OK")
	# B6 优先级回归：空集提示仍最优先、超域分支仍先于新两提示（既有口径零回退）
	p4.call("set_voxel_set", LP.TAG_TARGET, {})
	check_eq(p4.call("contract_hint"), LP.HINT_TARGET_EMPTY,
		"B6: target 空集提示仍优先于新两提示（优先级回归）")
	var p6: RefCounted = LP.new()
	p6.call("new_project", Vector3i(2, 2, 2))
	p6.call("set_voxel_set", LP.TAG_TARGET, {Vector3i(0, 0, 0): true})
	p6.call("set_voxel_set", LP.TAG_JOIN, {Vector3i(0, 0, 0): true, Vector3i(3, 0, 0): true})
	p6.call("set_voxel_set", LP.TAG_FINAL, {Vector3i(0, 0, 0): true})
	check_eq(p6.call("contract_hint"), "有 1 格超出所属组件域尺寸，游戏加载时将被裁剪",
		"B6: 超域提示仍先于新两提示（优先级回归）")

# ============ C 组（Y-D5）：跨工程防漂移锚 ============
func _resolve_game_jt_path() -> String:
	var d := ProjectSettings.globalize_path("res://").trim_suffix("/")
	for i: int in range(6):
		var candidate := d.path_join("游戏项目/千年一榫/scripts/join_transform.gd")
		if FileAccess.file_exists(candidate):
			return candidate
		var parent := d.get_base_dir()
		if parent == d or parent.length() < 4 or parent.ends_with(":"):
			break
		d = parent
	return ""

func _c_yd5_cross_project_anchor() -> void:
	var ed_bytes := FileAccess.get_file_as_string(JT_PATH)
	check(not ed_bytes.is_empty(), "C: 编辑器 join_transform.gd 可读")
	var game_path := _resolve_game_jt_path()
	if game_path.is_empty():
		# 降级路径（spec §9.4 Y-D5）：主游戏侧文件不可达 → 哈希常量比对 + 告警留痕
		push_warning("Y-D5 降级：主游戏 join_transform.gd 不可达，改哈希常量比对")
		print("[WARN] Y-D5 降级：主游戏侧 join_transform.gd 不可达（运行环境隔离），改哈希常量比对+告警")
		var sha := FileAccess.get_sha256(ProjectSettings.globalize_path(JT_PATH))
		check_eq(sha, GAME_JT_SHA256, "C(降级): 编辑器 join_transform.gd sha256=锚常量（漂移可检）")
	else:
		var game_bytes := FileAccess.get_file_as_string(game_path)
		check(game_bytes == ed_bytes,
			"C1: 编辑器与主游戏 join_transform.gd 逐字节一致（Y-D5 锚；len 游=%d/编=%d）"
				% [game_bytes.length(), ed_bytes.length()])
		check_eq(FileAccess.get_sha256(game_path),
			FileAccess.get_sha256(ProjectSettings.globalize_path(JT_PATH)),
			"C2: 双侧 sha256 一致（逐字节比对双背书）")
	# 负控（「人为改动一侧即红」的可自证形态，真件零触碰）：单常量篡改 → 判不等
	var sb := _make_sandbox("yd5neg")
	DirAccess.make_dir_recursive_absolute(sb)
	var tampered: String = ed_bytes.replace("TRANSFORM_COUNT := 48", "TRANSFORM_COUNT := 47")
	check(tampered != ed_bytes, "C3: 负控预备——篡改副本与原件不同")
	var f := FileAccess.open(sb.path_join("join_transform_tampered.gd"), FileAccess.WRITE)
	f.store_string(tampered)
	f.close()
	check(FileAccess.get_file_as_string(sb.path_join("join_transform_tampered.gd")) != ed_bytes,
		"C3: 负控——单点改动即被判不等（锚测试有效性自证）")

# ============ D 组（Y-D4）：试玩 success 常驻通关横幅 + 对接按钮 hover 提示 ============
func _fresh_editor() -> Control:
	var ed: Control = (load("res://scenes/editor_main.tscn") as PackedScene).instantiate() as Control
	add_child(ed)
	await process_frame
	return ed

func _d_yd4_playtest_banner() -> void:
	# 沙盒槽 1 预填=真实 level_1（装配文本走 save_slot_text 五件套写盘；真实 levels/ 零触碰）
	var sb := _make_sandbox("yd4")
	DirAccess.make_dir_recursive_absolute(sb)
	DirAccess.make_dir_recursive_absolute(sb.path_join("level_1"))   # save_slot_text 不建槽目录，须先建
	var assembled_v: Variant = LS.load_slot_text(1, _real_levels_root())
	check(assembled_v is String and not (assembled_v as String).is_empty(),
		"D: 真实 level_1 装配文本非空")
	if not (assembled_v is String):
		return
	check(bool(LS.save_slot_text(1, assembled_v, sb)), "D: 沙盒槽 1 预填真实 level_1")
	OS.set_environment("VOXEL_EDITOR_SLOTS_ROOT", sb)
	var ed: Control = await _fresh_editor()
	_ed_last = ed
	check_eq((ed.get("project") as RefCounted).call("get_voxel_set", 1).size(), 160,
		"D: 编辑器载入修后标准答案 160 格")
	# 进试玩→模拟把 blocks 挖成 target（挖除 blocks−target 的 20 格）→「对接」判定
	ed.call("_enter_playtest")
	await process_frame
	var sess_dict: Dictionary = ed.get("sessions")
	var tgt: Dictionary = sess_dict[1].cells
	var ps: Variant = ed.get("_playtest_session")
	check(ps != null, "D: 试玩会话在场")
	if ps == null:
		return
	var cur: Dictionary = ps.cells
	var to_dig: Dictionary = {}
	for c_v: Variant in cur:
		var c: Vector3i = c_v
		if not tgt.has(c):
			to_dig[c] = true
	check_eq(to_dig.size(), 20, "D: 待挖格数=blocks(180)−target(160)=20")
	var res: Dictionary = ps.call("dig", to_dig)
	ed.call("_apply_change", res)
	(ed.get("playtest_toast") as Label).visible = false   # 清「进试玩」提示残留，判定通道断言确定性
	ed.call("_on_join_pressed")
	var banner: Label = ed.get_node_or_null("PlaytestBanner") as Label
	check(banner != null, "D1: 通关横幅节点 PlaytestBanner 在场（红：Y-D4 未实施缺席）")
	check(not (ed.get("playtest_toast") as Label).visible,
		"D2: success 不再走 2.5s toast 通道（红：旧实现即时 toast）")
	if banner != null:
		check(banner.visible and banner.text.contains("试玩成功"),
			"D3: success 横幅立现且文案含「试玩成功」")
	# 常驻锚：越过旧 toast 2.5s 自愈窗口后横幅仍在
	await create_timer(2.7).timeout
	if banner != null:
		check(banner.visible, "D4: 横幅常驻 >2.5s（不吃 toast 自愈，进新局/退出才清除）")
	check(not (ed.get("playtest_toast") as Label).visible, "D5: 2.7s 后 toast 保持隐藏")
	# 退出试玩清除
	ed.call("_do_exit_playtest")
	await process_frame
	if banner != null:
		check(not banner.visible, "D6: 退出试玩清除横幅")
	# 进试玩新局清除
	ed.call("_enter_playtest")
	await process_frame
	if banner != null:
		check(not banner.visible, "D7: 进试玩新局清除横幅")
	check((ed.get("btn_join") as Button).tooltip_text.contains("镜像"),
		"D8: 对接按钮 hover 提示含「对称/旋转/镜像均认可」口径")
	ed.call("_do_exit_playtest")   # 还原编辑态（E 组复用本实例）
	await process_frame

# ============ E 组（Y-D2）：三域 tab 与试玩对照面板语义副标注 ============
func _e_yd2_sub_labels() -> void:
	var ed: Control = _ed_last
	check(ed != null, "E: 复用 D 段编辑器实例")
	if ed == null:
		return
	var tt: Label = ed.get_node_or_null("LeftPanel/LeftScroll/LeftVBox/TabTargetSub") as Label
	var tj: Label = ed.get_node_or_null("LeftPanel/LeftScroll/LeftVBox/TabJoinSub") as Label
	var tf: Label = ed.get_node_or_null("LeftPanel/LeftScroll/LeftVBox/TabFinalSub") as Label
	check(tt != null and tt.text.contains("玩家要挖成的形状"),
		"E1: target tab 副标注=「玩家要挖成的形状」（红：Y-D2 未实施缺席）")
	check(tt != null and tt.text.contains("判定依据"), "E1b: target tab 副标注含「判定依据」")
	check(tj != null and tj.text.contains("固定件"), "E2: join tab 副标注=「固定件」")
	check(tj != null and tj.text.contains("干涉"), "E2b: join tab 副标注含「对接干涉判定用」")
	check(tf != null and tf.text.contains("对接完成形态"), "E3: final tab 副标注含「对接完成形态」")
	check(tf != null and tf.text.contains("仅供参照不参与判定"),
		"E3b: final tab 副标注含「仅供参照不参与判定」")
	var ts: Label = ed.get_node_or_null("TargetPanel/SubTitle") as Label
	var js: Label = ed.get_node_or_null("JoinPanel/SubTitle") as Label
	# 批次 Z Z1 等价改写留痕（spec §1 三者同改·用户拍板）：原断言「玩家要挖成的形状/判定依据」
	# （Y-D2 副标注）→ 试玩左上面板换源 final：副标注=「对接完成形态（仅供参照，不参与判定）」；
	# 标题与渲染数据源由 tests/test_z_panel_final.gd 承载；target tab 副标注（E1/E1b）不变——
	# 编辑态 target 页保留（spec §1-5）。
	check(ts != null and ts.text.contains("对接完成形态"),
		"E4: 试玩左上「最终成品」面板副标注=对接完成形态（Z1 换源 final，落位）")
	check(ts != null and ts.text.contains("仅供参照，不参与判定"),
		"E4b: 试玩左上副标注含「仅供参照，不参与判定」（Z1，原「判定依据」口径按 spec §1 反转）")
	check(js != null and js.text.contains("固定件"), "E5: 试玩对照面板（对接件）副标注落位")
	check(js != null and js.text.contains("干涉"), "E5b: 试玩对照面板副标注含「对接干涉判定用」")
	check(tt != null and tt.visible and ts != null and ts.visible, "E6: 副标注可见（主标题不动只加小字）")
