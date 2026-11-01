extends "res://tests/test_base.gd"
## 批次 V（V-E2）编辑器每关拆分文件测试（规格 §9.3 目录契约/迁移写序 + §9.6 测试 4/5）。
## 红态定义=对拆分前实现必红：
##   P1 新存档五文件契约——旧实现只写 level.json 单文件 → 五文件存在/无 pieces 键断言红；
##   P2 旧单文件迁移——旧实现载入不改盘 → level_legacy.json.bak/五文件/往返零 diff 断言红；
##   P3 target_size 键缺不落键——拆分落盘沿用 E1 口径（迁移后 target.json 无该键、回落仍成立）；
##   P4A 迁移写失败中止（blocks.json 同名目录注入）→ 旧 level.json 原样完整零丢失；
##   P4B 半迁移恢复（四域已写、元数据未写）→ 判据①旧文件补齐 + 续存收敛完整拆分态；
##   P5 缺一域文件宽容补建 → 载入成功 + 续存收敛五文件；
##   P6 逐文件原子性（单文件失败不影响其他域已写内容，重试收敛）。
## 磁盘纪律：root 参数注入 TEMP 一次性子目录（test_level_slots P7 裁决先例），真实 levels/ 零触碰；
## 全部断言走既有 API（load_slot_text/save_slot_text）+ 文件系统观测，零新增 API 依赖（TDD 红期可编译）。
## Godot 4.7 坑对齐（spec §14）：JSON 回析数值恒 float（两侧同经 parse，dict == 逐键相等）；
## 字典取键一律 .get 防御（坑 2）；强转前 is 判型（坑 1）。

const LS := preload("res://scripts/level_slots.gd")
const LP := preload("res://scripts/level_project.gd")
const FIXTURE := "res://tests/fixtures/level_chapter1_hemudu.json"   # 游戏侧 v1 单文件逐字节副本（旧档标本，只读）

const F_LEVEL := "level.json"
const F_BLOCKS := "blocks.json"
const F_TARGET := "target.json"
const F_JOIN := "join.json"
const F_FINAL := "final.json"

var _sandboxes: Array[String] = []
var _sandbox_seq: int = 0

func _initialize() -> void:
	print("== test_v_editor_split ==")
	_p1_new_save_five_files()
	_p2_migrate_roundtrip_zero_diff()
	_p3_target_size_key_absent()
	_p4a_migration_write_fail_abort()
	_p4b_half_migrated_recovery()
	_p5_missing_domain_tolerance()
	_p6_per_file_atomicity()
	_cleanup_sandboxes()
	finish()

# ---------- 沙盒 helper（P7 裁决：TEMP 一次性子目录，严禁写工程树内路径） ----------
func _make_sandbox(tag: String) -> String:
	var base := OS.get_environment("TEMP")
	if base.is_empty():
		base = "/tmp"
	base = base.replace("\\", "/")
	_sandbox_seq += 1
	var dir: String = base.path_join("voxel_editor_vsplit_%s_%d_%d" % [tag, Time.get_ticks_msec(), _sandbox_seq]) + "/"
	_sandboxes.append(dir)
	return dir

func _cleanup_sandboxes() -> void:
	for dir: String in _sandboxes:
		_remove_dir_recursive(dir)

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

# ---------- 观测 helper ----------
## 槽目录内五文件路径（root 尾已含 /）。
func _slot_file(root: String, slot: int, file_name: String) -> String:
	return root + ("level_%d/" % slot) + file_name

func _file_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

func _file_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(_file_text(path))
	return parsed as Dictionary if parsed is Dictionary else {}

func _has_five_files(root: String, slot: int) -> bool:
	for name: String in [F_LEVEL, F_BLOCKS, F_TARGET, F_JOIN, F_FINAL]:
		if not FileAccess.file_exists(_slot_file(root, slot, name)):
			return false
	return true

## 旧单文件槽播种：直接 FileAccess 原样写 level.json（不经 save_slot_text——模拟拆分前历史槽）。
func _seed_legacy(root: String, slot: int, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(root + ("level_%d/" % slot))
	var f := FileAccess.open(_slot_file(root, slot, F_LEVEL), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return f.get_error() == OK

## 经模型续存（生产 _autosave_current 同构：load → load_from_text → save_to_text → save_slot_text）。
func _save_via_model(root: String, slot: int) -> bool:
	var p := LP.new()
	var text: String = LS.load_slot_text(slot, root)
	if text.is_empty() or not p.load_from_text(text):
		return false
	return LS.save_slot_text(slot, p.save_to_text(), root)

# ============ P1 新存档五文件齐且各自可独立解析、level.json 无 pieces 键（规格 §9.3 目录契约） ============
func _p1_new_save_five_files() -> void:
	var root: String = LS.ensure_initialized(_make_sandbox("p1"), FIXTURE)
	check(not root.is_empty(), "P1: 初始化返回有效根（前置）")
	var all_five := true
	for n: int in range(1, 6):
		all_five = all_five and _has_five_files(root, n)
	check(all_five, "P1: level_1..5 五槽五文件齐（旧实现仅 level.json 必红）")
	# level_1（游戏侧夹具预填）：五文件各自独立解析 + 域键契约。
	var meta1 := _file_json(_slot_file(root, 1, F_LEVEL))
	check(not meta1.is_empty() and not meta1.has("pieces"),
		"P1: level_1/level.json 可独立解析且无 pieces 键（元数据归位）")
	check_eq(int(meta1.get("format_version", -1)), 1, "P1: level_1/level.json format_version==1")
	var blocks1 := _file_json(_slot_file(root, 1, F_BLOCKS))
	check_eq((blocks1.get("block_size", {}) as Dictionary), {"x": 8.0, "y": 3.0, "z": 8.0},
		"P1: level_1/blocks.json block_size==8×3×8（独立可解析）")
	check_eq((blocks1.get("blocks", []) as Array).size(), 192, "P1: level_1/blocks.json blocks==192 格")
	var target1 := _file_json(_slot_file(root, 1, F_TARGET))
	check((target1.get("target_shapes", null) is Array) and not target1.has("target_size"),
		"P1: level_1/target.json 有 target_shapes 且无 target_size（夹具源无该键→键缺不落键）")
	var join1 := _file_json(_slot_file(root, 1, F_JOIN))
	check((join1.get("size", {}) as Dictionary) == {"x": 8.0, "y": 3.0, "z": 8.0} \
		and (join1.get("voxels", null) is Array) and not (join1.get("voxels", []) as Array).is_empty(),
		"P1: level_1/join.json size==8×3×8 且 voxels 非空（独立可解析）")
	var final1 := _file_json(_slot_file(root, 1, F_FINAL))
	check((final1.get("size", {}) as Dictionary) == {"x": 8.0, "y": 3.0, "z": 8.0} \
		and (final1.get("voxels", null) is Array), "P1: level_1/final.json size+voxels 齐（独立可解析）")
	# level_2（空骨架）：new_project 语义自带 target_size → target.json 有该键（仅当源有该键的双向口径）。
	var meta2 := _file_json(_slot_file(root, 2, F_LEVEL))
	check(not meta2.is_empty() and not meta2.has("pieces"), "P1: level_2/level.json 无 pieces 键")
	var target2 := _file_json(_slot_file(root, 2, F_TARGET))
	check_eq((target2.get("target_size", {}) as Dictionary), {"x": 3.0, "y": 3.0, "z": 3.0},
		"P1: level_2/target.json target_size==3³（源有该键则落键）")
	check_eq((_file_json(_slot_file(root, 2, F_BLOCKS)).get("block_size", {}) as Dictionary),
		{"x": 3.0, "y": 3.0, "z": 3.0}, "P1: level_2/blocks.json block_size==3³（空骨架）")

# ============ P2 旧单文件载入→迁移→五文件+bak 留档+往返零 diff（规格 §9.3 判据②/P2-3） ============
func _p2_migrate_roundtrip_zero_diff() -> void:
	var root := _make_sandbox("p2")
	var fixture_text: String = FileAccess.get_file_as_string(FIXTURE)
	check(_seed_legacy(root, 1, fixture_text), "P2: 旧单文件槽播种成功（前置）")
	var old_dict: Dictionary = JSON.parse_string(fixture_text) as Dictionary
	# 载入即迁移。
	var loaded: String = LS.load_slot_text(1, root)
	check(not loaded.is_empty(), "P2: 迁移载入返回非空（前置）")
	var re_dict: Variant = JSON.parse_string(loaded)
	check(re_dict is Dictionary and re_dict == old_dict,
		"P2: 迁移往返零 diff（内存合回 dict 与旧文件原始 dict 逐键相等，含 grid_size_unused 顶层透传键）")
	# 盘上五文件 + legacy bak 留档。
	check(_has_five_files(root, 1), "P2: 迁移后五文件齐（旧实现零迁移必红）")
	var bak_path := _slot_file(root, 1, "level_legacy.json.bak")
	check(FileAccess.file_exists(bak_path) and _file_text(bak_path) == fixture_text,
		"P2: level_legacy.json.bak 存在且与旧单文件逐字节相同（留档）")
	var meta := _file_json(_slot_file(root, 1, F_LEVEL))
	check(not meta.is_empty() and not meta.has("pieces"), "P2: 迁移后 level.json 为纯元数据（无 pieces）")
	check_eq((_file_json(_slot_file(root, 1, F_BLOCKS)).get("blocks", []) as Array).size(), 192,
		"P2: 迁移后 blocks.json 192 格（数据搬家零丢失）")
	# 再载入：拆分态装配（幂等）。
	var re2: Variant = JSON.parse_string(LS.load_slot_text(1, root))
	check(re2 is Dictionary and re2 == old_dict, "P2: 迁移后再载入装配 dict 仍与原档逐键相等（幂等）")
	# 多 piece 保留（pieces_tail 透传留档——G9 双 piece 提示语义，spec §3.6-2）。
	var root2 := _make_sandbox("p2b")
	var two_dict: Dictionary = (old_dict as Dictionary).duplicate(true)
	var piece2: Dictionary = ((two_dict["pieces"] as Array)[0] as Dictionary).duplicate(true)
	piece2["piece_id"] = "p2"
	(two_dict["pieces"] as Array).append(piece2)
	var two_text := JSON.stringify(two_dict)
	_seed_legacy(root2, 1, two_text)
	var re3: Variant = JSON.parse_string(LS.load_slot_text(1, root2))
	check(re3 is Dictionary and re3 == two_dict,
		"P2: 双 piece 旧档迁移往返零 diff（pieces[1..] 经 pieces_tail 透传留档，键集守恒）")
	check_eq((JSON.parse_string(_file_text(_slot_file(root2, 1, F_LEVEL))) as Dictionary).get("pieces_tail", null),
		JSON.parse_string(two_text)["pieces"].slice(1),
		"P2: level.json 以 pieces_tail 留档 pieces[1..]（无 pieces 键）")

# ============ P3 target_size 键缺不落键 + 异值保留（E1 口径沿用，规格 §9.3） ============
func _p3_target_size_key_absent() -> void:
	# ① 源无 target_size（夹具即无）：迁移后 target.json 无该键、合回 piece 无该键、E1 回落仍成立。
	var root := _make_sandbox("p3a")
	var fixture_text: String = FileAccess.get_file_as_string(FIXTURE)
	_seed_legacy(root, 1, fixture_text)
	LS.load_slot_text(1, root)
	check(not _file_json(_slot_file(root, 1, F_TARGET)).has("target_size"),
		"P3: 旧档（无 target_size）迁移后 target.json 无 target_size 键（键缺不落键）")
	var p := LP.new()
	check(p.load_from_text(LS.load_slot_text(1, root)), "P3: 迁移档可经 LevelProject 装载（前置）")
	check(p.get_piece().get("target_size", null) == null, "P3: 合回模型 piece 无 target_size 键（零物化）")
	check(p.get_size_for_tag(LP.TAG_TARGET) == Vector3i(8, 3, 8),
		"P3: get_size_for_tag(1) 缺失回落 block_size==8×3×8（E1 回落链仍成立）")
	# ② 源有异值 target_size：迁移后原值保留。
	var root2 := _make_sandbox("p3b")
	var old_dict: Dictionary = (JSON.parse_string(fixture_text) as Dictionary).duplicate(true)
	var piece0: Dictionary = (old_dict["pieces"] as Array)[0]
	piece0["target_size"] = {"x": 5, "y": 6, "z": 7}
	_seed_legacy(root2, 1, JSON.stringify(old_dict))
	LS.load_slot_text(1, root2)
	check_eq((_file_json(_slot_file(root2, 1, F_TARGET)).get("target_size", {}) as Dictionary),
		{"x": 5.0, "y": 6.0, "z": 7.0}, "P3: 源有异值 target_size → 迁移后原值保留（5×6×7）")
	var p2 := LP.new()
	p2.load_from_text(LS.load_slot_text(1, root2))
	check(p2.get_size_for_tag(LP.TAG_TARGET) == Vector3i(5, 6, 7), "P3: 异值 target_size 独立读回 5×6×7")

# ============ P4A 迁移写失败中止（blocks.json 同名目录注入）→ 旧档原样完整（规格 §9.3 P1-3） ============
func _p4a_migration_write_fail_abort() -> void:
	var root := _make_sandbox("p4a")
	var fixture_text: String = FileAccess.get_file_as_string(FIXTURE)
	_seed_legacy(root, 1, fixture_text)
	DirAccess.make_dir_recursive_absolute(_slot_file(root, 1, F_BLOCKS))   # blocks.json 路径置同名目录
	var loaded: String = LS.load_slot_text(1, root)
	check(loaded == fixture_text, "P4A: 写失败中止 → 返回旧档原文（零丢失）")
	check(_file_text(_slot_file(root, 1, F_LEVEL)) == fixture_text,
		"P4A: 旧 level.json 原样完整（迁移中止零改写）")
	check(not FileAccess.file_exists(_slot_file(root, 1, F_TARGET)) \
		and not FileAccess.file_exists(_slot_file(root, 1, F_JOIN)) \
		and not FileAccess.file_exists(_slot_file(root, 1, F_FINAL)),
		"P4A: target/join/final 零落盘（首个域失败即中止）")
	check(not FileAccess.file_exists(_slot_file(root, 1, "level_legacy.json.bak")),
		"P4A: 无 level_legacy.json.bak（未到留档步骤）")
	# 清除注入后重载 → 迁移成功收敛。
	DirAccess.remove_absolute(_slot_file(root, 1, F_BLOCKS))
	LS.load_slot_text(1, root)
	check(FileAccess.file_exists(_slot_file(root, 1, "level_legacy.json.bak")) and _has_five_files(root, 1),
		"P4A: 注入清除后重载迁移成功（五文件+bak，重试收敛）")

# ============ P4B 半迁移恢复（四域已写、元数据未写）→ 判据①旧文件补齐 + 续存收敛（P1-3） ============
func _p4b_half_migrated_recovery() -> void:
	var root := _make_sandbox("p4b")
	var fixture_text: String = FileAccess.get_file_as_string(FIXTURE)
	_seed_legacy(root, 1, fixture_text)
	var old_dict: Dictionary = JSON.parse_string(fixture_text) as Dictionary
	# 模拟半迁移：完整迁移后把元数据 level.json 撤下、legacy bak 改回 level.json
	# → 盘面=四域拆分文件 + 旧单文件（含 pieces）=「四域已写、元数据未写」中断态。
	check(_save_via_model(root, 1), "P4B: 前置迁移完成（经模型续存）")
	DirAccess.remove_absolute(_slot_file(root, 1, F_LEVEL))
	check(DirAccess.rename_absolute(_slot_file(root, 1, "level_legacy.json.bak"), _slot_file(root, 1, F_LEVEL)) == OK,
		"P4B: 半迁移态模拟成功（旧档回归 level.json，前置；Error OK=0 需显式判等）")
	# 再载入：判据①以拆分为准 + 旧文件在（数据零丢失）。
	var recovered: Variant = JSON.parse_string(LS.load_slot_text(1, root))
	check(recovered is Dictionary and recovered == old_dict,
		"P4B: 半迁移态重载恢复完整数据（合回 dict 与旧档逐键相等，判据①口径）")
	# 续存（经模型）→ 收敛完整拆分态。
	check(_save_via_model(root, 1), "P4B: 续存成功（前置）")
	check(not _file_json(_slot_file(root, 1, F_LEVEL)).has("pieces"), "P4B: 收敛后 level.json 无 pieces（元数据态）")
	check(_has_five_files(root, 1) and not FileAccess.file_exists(_slot_file(root, 1, "level_legacy.json.bak")),
		"P4B: 收敛后五文件齐且无残留 bak（完整拆分态）")
	var re2: Variant = JSON.parse_string(LS.load_slot_text(1, root))
	check(re2 is Dictionary and re2 == old_dict, "P4B: 收敛后重载 dict 仍与原档逐键相等（零丢失终态）")

# ============ P5 缺一域文件的宽容补建（规格 §9.3 判据①宽容分支） ============
func _p5_missing_domain_tolerance() -> void:
	# ① 缺 join.json：载入成功、其余域完好、join 空域；续存后 join.json 重建收敛。
	var root := _make_sandbox("p5a")
	var fixture_text: String = FileAccess.get_file_as_string(FIXTURE)
	_seed_legacy(root, 1, fixture_text)
	var old_dict: Dictionary = JSON.parse_string(fixture_text) as Dictionary
	check(_save_via_model(root, 1), "P5: 前置迁移完成（经模型续存）")
	DirAccess.remove_absolute(_slot_file(root, 1, F_JOIN))
	var p := LP.new()
	var text: String = LS.load_slot_text(1, root)
	check(not text.is_empty() and p.load_from_text(text), "P5: 缺 join.json 载入成功（宽容补建不拒载）")
	var expected: Dictionary = old_dict.duplicate(true)
	((expected["pieces"] as Array)[0] as Dictionary).erase("join_part")
	var recovered: Variant = JSON.parse_string(text)
	check(recovered is Dictionary and recovered == expected,
		"P5: 缺 join.json 补建后合回 dict 与原档逐键相等（仅 join 域随文件缺失丢失，其余键集守恒）")
	check(p.get_voxel_set(LP.TAG_JOIN).is_empty(), "P5: join 域宽容补建为空集")
	check_eq(p.get_voxel_set(LP.TAG_BLOCKS).size(), 192, "P5: blocks 域完好 192 格（其余域零波及）")
	check(_save_via_model(root, 1) and _has_five_files(root, 1), "P5: 续存后五文件齐（join.json 重建收敛）")
	var join_back := _file_json(_slot_file(root, 1, F_JOIN))
	check((join_back.get("size", {}) as Dictionary) == {"x": 8.0, "y": 3.0, "z": 8.0} \
		and (join_back.get("voxels", []) as Array).is_empty(),
		"P5: 重建 join.json size 回落 block_size==8×3×8、voxels 空（缺失补齐口径）")
	# ② 缺 target.json：补建后 target_shapes 回归空集、target_size 键缺不落键（E1 口径贯穿宽容补建）。
	var root2 := _make_sandbox("p5b")
	_seed_legacy(root2, 1, fixture_text)
	check(_save_via_model(root2, 1), "P5: 前置迁移完成（p5b，经模型续存）")
	DirAccess.remove_absolute(_slot_file(root2, 1, F_TARGET))
	var p2 := LP.new()
	check(p2.load_from_text(LS.load_slot_text(1, root2)), "P5: 缺 target.json 载入成功（宽容补建）")
	p2.get_voxel_set(LP.TAG_TARGET)   # 读路径物化 target_shapes（编辑器载入实况同构）
	check(_save_via_model(root2, 1), "P5: p5b 续存成功（前置）")
	var target_back := _file_json(_slot_file(root2, 1, F_TARGET))
	check(target_back.has("target_shapes") and not target_back.has("target_size"),
		"P5: 补建 target.json 有 target_shapes 且无 target_size（键缺不落键贯穿宽容补建）")

# ============ P6 逐文件原子性（单文件失败不影响其他域已写内容，重试收敛；写序 level→blocks→target→join→final） ============
func _p6_per_file_atomicity() -> void:
	var root := _make_sandbox("p6")
	var fixture_text: String = FileAccess.get_file_as_string(FIXTURE)
	_seed_legacy(root, 1, fixture_text)
	check(_save_via_model(root, 1), "P6: 前置迁移完成（经模型续存）")
	# 模型改三处：title（level.json 域）、blocks 挖 1 格（blocks.json 域）→ 与盘上旧值可区分。
	var p := LP.new()
	check(p.load_from_text(LS.load_slot_text(1, root)), "P6: 模型装载成功（前置）")
	p.set_field("title", "手改六")
	var cells: Dictionary = p.get_voxel_set(LP.TAG_BLOCKS)
	var one: Variant = null
	for k: Variant in cells:
		one = k
		break
	if one != null:
		cells.erase(one)
	p.set_voxel_set(LP.TAG_BLOCKS, cells)
	var join_before: String = _file_text(_slot_file(root, 1, F_JOIN))
	var final_before: String = _file_text(_slot_file(root, 1, F_FINAL))
	# 注入：target.json 文件换同名目录 → 保存中止于第三个文件。
	DirAccess.remove_absolute(_slot_file(root, 1, F_TARGET))
	DirAccess.make_dir_recursive_absolute(_slot_file(root, 1, F_TARGET))
	check(not LS.save_slot_text(1, p.save_to_text(), root),
		"P6: target.json 写失败 → save_slot_text 返回 false（逐文件原子中止）")
	check_eq(_file_json(_slot_file(root, 1, F_LEVEL)).get("title", ""), "手改六",
		"P6: level.json 已更新（写序首位，失败前已写成功的保留最新）")
	check_eq((_file_json(_slot_file(root, 1, F_BLOCKS)).get("blocks", []) as Array).size(), 191,
		"P6: blocks.json 已更新 191 格（失败前已写成功的保留最新）")
	check(_file_text(_slot_file(root, 1, F_JOIN)) == join_before \
		and _file_text(_slot_file(root, 1, F_FINAL)) == final_before,
		"P6: join.json/final.json 字节不变（中止点之后的域零触碰）")
	# 恢复写路径重试 → 收敛完整拆分态。
	DirAccess.remove_absolute(_slot_file(root, 1, F_TARGET))
	check(LS.save_slot_text(1, p.save_to_text(), root), "P6: 恢复后重试保存成功")
	check(_has_five_files(root, 1), "P6: 重试后五文件齐（收敛）")
	var p2 := LP.new()
	p2.load_from_text(LS.load_slot_text(1, root))
	check_eq(str(p2.get_field("title", "")), "手改六", "P6: 重试收敛后 title 落盘（重载装配口径）")
	check_eq(p2.get_voxel_set(LP.TAG_BLOCKS).size(), 191, "P6: 重试收敛后 blocks 191 格（终态一致）")
	# 报具体文件（任务口径）：last_error_file 记录最近写盘失败路径，成功保存清零。
	check_eq(LS.last_error_file, "", "P6: 重试成功后 last_error_file 清零")
	var p3 := LP.new()
	p3.load_from_text(LS.load_slot_text(1, root))
	DirAccess.remove_absolute(_slot_file(root, 1, F_TARGET))   # 先删文件再置同名目录（make_dir 对已存在文件失败）
	DirAccess.make_dir_recursive_absolute(_slot_file(root, 1, F_TARGET))
	LS.save_slot_text(1, p3.save_to_text(), root)
	check(String(LS.last_error_file).ends_with("target.json"),
		"P6: last_error_file 报告失败文件 target.json（状态栏「报具体文件」数据源）")
