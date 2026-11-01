extends "res://tests/test_base.gd"
## test_level_slots：槽位纯逻辑类（规格 §3.3/§6.2 S1~S7）。
## 沙盒纪律：root/source 经参数注入临时目录（P7 裁决：TEMP（空回退 /tmp）下一次性子目录，
## 测试尾 best-effort 递归清理），真实 levels/ 与游戏侧零触碰。
## 红态（W2-1）：被测类不存在——preload "res://scripts/level_slots.gd" 即脚本加载错误，退出码非 0。
## 批次 V 等价替换留痕（V-E2，规格 §9.3 每关拆分文件，20260919）：
##   S2 骨架语义——单文件骨架 → 五文件拆分骨架（新增五文件齐 + target_size 键缺不落键断言）；
##   S4 槽「在盘」判据——level.json 存在 → level.json 或任一域拆分文件存在（删单文件不再触发
##   骨架重写，防拆分数据被覆盖；「槽缺失」等价口径=五文件全缺）；
##   S4b 全删重置——删 level.json ×5 → 删五文件 ×5；
##   S5 读写往返——save/load 字节级零 diff（单文件语义）→ 装配口径（load→模型→save 五文件落盘
##   →重载 dict 逐键相等；load_slot_text 返回内存合回的完整契约文本，spec §9.3 判据①）。
##   断言数只增不减（36 → 40）。

const LS := preload("res://scripts/level_slots.gd")
const LP := preload("res://scripts/level_project.gd")
const FIXTURE := "res://tests/fixtures/level_chapter1_hemudu.json"   # 游戏侧 levels_data 第 1 关的逐字节副本（已入库，只读）
const README_NAME := "README_请勿接入主游戏.md"
## 批次 V（§9.3）拆分文件名（S2/S4/S4b 五文件口径用）。
const SPLIT_FILES: Array[String] = ["blocks.json", "target.json", "join.json", "final.json"]

var _sandboxes: Array[String] = []
var _sandbox_seq: int = 0

func _initialize() -> void:
	_s1_dual_path()
	_s2_first_init()
	_s3_idempotent()
	_s4_single_slot_repair()
	_s4b_full_reset()
	_s5_roundtrip()
	_s6_auto_meta()
	_s7_missing_source()
	_cleanup_sandboxes()
	finish()

# ---------- 沙盒 helper（P7：TEMP 一次性子目录，严禁写工程树内路径） ----------
func _make_sandbox(tag: String) -> String:
	var base := OS.get_environment("TEMP")
	if base.is_empty():
		base = "/tmp"
	base = base.replace("\\", "/")
	_sandbox_seq += 1
	var dir: String = base.path_join("voxel_editor_slots_%s_%d_%d" % [tag, Time.get_ticks_msec(), _sandbox_seq]) + "/"
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

## 装载槽位工程为 LevelProject 实例；装载失败返回未装载实例（字段读默认值，断言自然 FAIL 不崩）。
func _load_proj(slot: int, root: String) -> LevelProject:
	var t: String = LS.load_slot_text(slot, root)
	var p := LP.new()
	if t.is_empty() or not p.load_from_text(t):
		return p
	return p

## 槽内五文件全在判定（批次 V §9.3 拆分口径；S2/S4/S4b 用）。
func _has_five_files(root: String, slot: int) -> bool:
	if not FileAccess.file_exists(root + ("level_%d/level.json" % slot)):
		return false
	for name: String in SPLIT_FILES:
		if not FileAccess.file_exists(root + ("level_%d/" % slot) + name):
			return false
	return true

## 删除槽内全部五文件（批次 V §9.3 的「槽缺失」等价口径，S4/S4b 用）。
func _remove_slot_files(root: String, slot: int) -> void:
	DirAccess.remove_absolute(root + ("level_%d/level.json" % slot))
	for name: String in SPLIT_FILES:
		var path := root + ("level_%d/" % slot) + name
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

func _tamper_title(slot: int, root: String, new_title: String) -> bool:
	var p := _load_proj(slot, root)
	p.set_field("title", new_title)
	return LS.save_slot_text(slot, p.save_to_text(), root)

# ============ S1 双路径（2 checks；规格 §3.3-3/§6.2 S1） ============
func _s1_dual_path() -> void:
	# 开发态（编辑器二进制含 --script 无头跑亦为 true，spec §3.3-3 实证口径）主路径=工程内 levels/
	check_eq(LS.slots_root(), ProjectSettings.globalize_path("res://levels/"),
		"S1: 开发态 slots_root()==globalize_path(res://levels/)")
	# root 参数注入生效：任意自定义目录可读写（沙盒根，非工程树内路径）
	var r := _make_sandbox("s1")
	var got: String = LS.ensure_initialized(r, FIXTURE)
	check(got == r and not LS.load_slot_text(1, got).is_empty(),
		"S1: 注入根生效（返回值==注入根尾/归一且 level_1 可读写）")

# ============ S2 首启初始化（14 checks；规格 §3.3-4/§6.2 S2） ============
func _s2_first_init() -> void:
	var root: String = LS.ensure_initialized(_make_sandbox("s2"), FIXTURE)
	var dirs_ok := true
	for n: int in range(1, 6):
		dirs_ok = dirs_ok and DirAccess.dir_exists_absolute(root + ("level_%d/" % n))
	check(dirs_ok, "S2: level_1..5 五目录齐")
	var p1 := _load_proj(1, root)
	check_eq(int(p1.get_field("chapter", -1)), 1, "S2: level_1 chapter==1（自动元数据改写）")
	check_eq(str(p1.get_field("title", "")), "第一关", "S2: level_1 title=第一关")
	check_eq(str(p1.get_field("level_id", "")), "chapter1_editor", "S2: level_1 level_id=chapter1_editor")
	check_eq(str(p1.get_field("era", "")), "新石器时代", "S2: level_1 era 游戏侧原值保留")
	check_eq(str(p1.get_piece().get("name", "")), "榫头梁与卯眼固定件", "S2: pieces[0].name 游戏侧原值保留")
	check_eq(p1.get_voxel_set(LP.TAG_BLOCKS).size(), 192, "S2: blocks 格数==源 JSON 192（8×3×8）")
	check_eq(int(p1.get_field("format_version", -1)), 1, "S2: format_version==1（过 load_from_text 门禁）")
	var p2 := _load_proj(2, root)
	check_eq(p2.get_block_size(), Vector3i(3, 3, 3), "S2: level_2 空骨架 block_size 3³")
	check_eq(p2.get_voxel_set(LP.TAG_BLOCKS).size(), 27, "S2: level_2 空骨架 blocks 27 格实心")
	check_eq(str(p2.get_field("title", "")), "第二关", "S2: level_2 title=第二关")
	var p5 := _load_proj(5, root)
	check(str(p5.get_field("level_id", "")) == "chapter5_editor" and str(p5.get_field("era", "")) == "" \
		and str(p5.get_field("theme", "")) == "wood" and str(p5.get_piece().get("name", "")) == "主体",
		"S2: level_5 空骨架（chapter5_editor/era 空/theme wood/name 主体）")
	var meta_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(root + "session_meta.json"))
	check(meta_v is Dictionary and int((meta_v as Dictionary).get("last_slot", -1)) == 1,
		"S2: session_meta.json last_slot==1")
	var readme := FileAccess.get_file_as_string(root + README_NAME)
	check(FileAccess.file_exists(root + README_NAME) and readme.contains("请勿接入主游戏"),
		"S2: README 存在且含「请勿接入主游戏」")
	# 批次 V（§9.3）等价替换留痕：骨架从单文件 → 五文件拆分（新增 3 断言）。
	var five_ok := true
	for n: int in range(1, 6):
		five_ok = five_ok and _has_five_files(root, n)
	check(five_ok, "S2: level_1..5 五槽五文件齐（批次 V 拆分骨架，单文件口径必红）")
	var target1: Variant = JSON.parse_string(FileAccess.get_file_as_string(root + "level_1/target.json"))
	check(target1 is Dictionary and not (target1 as Dictionary).has("target_size"),
		"S2: level_1/target.json 无 target_size 键（预填源无该键→键缺不落键，E1 口径沿用）")
	var target2: Variant = JSON.parse_string(FileAccess.get_file_as_string(root + "level_2/target.json"))
	check(target2 is Dictionary and (target2 as Dictionary).get("target_size", null) == {"x": 3.0, "y": 3.0, "z": 3.0},
		"S2: level_2/target.json target_size==3³（new_project 自带该键→落键）")

# ============ S3 幂等（2 checks；spec §3.3-5/§6.2 S3）【回归锁：无「已初始化跳过」守卫必红】 ============
func _s3_idempotent() -> void:
	var root: String = LS.ensure_initialized(_make_sandbox("s3"), FIXTURE)
	var t1ok := _tamper_title(1, root, "手改")
	var t2ok := _tamper_title(2, root, "手改二")
	LS.ensure_initialized(root, FIXTURE)   # 二次初始化：以 levels/ 为准
	var p1 := _load_proj(1, root)
	var p2 := _load_proj(2, root)
	check(t1ok and str(p1.get_field("title", "")) == "手改",
		"S3: level_1 篡改不被还原（以 levels/ 为准，不回读游戏侧）")
	check(t2ok and str(p2.get_field("title", "")) == "手改二",
		"S3: level_2 篡改不被还原（空骨架槽同样不重写）")

# ============ S4 单槽缺失补齐（4 checks；spec §3.3-6/§6.2 S4）【批次 V 等价替换留痕】 ============
## 拆分后槽「在盘」判据=level.json 或任一域拆分文件存在：删 level.json 单文件不再触发骨架重写
## （防拆分数据被覆盖丢档，§9.3）；「槽缺失」等价口径=五文件全缺 → 重建空骨架。
func _s4_single_slot_repair() -> void:
	var root: String = LS.ensure_initialized(_make_sandbox("s4"), FIXTURE)
	var t1ok := _tamper_title(1, root, "手改S4")
	DirAccess.remove_absolute(root + "level_3/level.json")
	LS.ensure_initialized(root, FIXTURE)   # 拆分态：域文件在 → 槽仍在盘，不重写
	check(not FileAccess.file_exists(root + "level_3/level.json") \
		and FileAccess.file_exists(root + "level_3/blocks.json"),
		"S4: 仅删 level_3/level.json 不触发骨架重写（域文件在槽即活，拆分数据防覆盖）")
	_remove_slot_files(root, 3)
	LS.ensure_initialized(root, FIXTURE)   # 五文件全缺=槽缺失 → 仅补缺失槽（不回读游戏侧）
	var p3 := _load_proj(3, root)
	var p1 := _load_proj(1, root)
	check(str(p3.get_field("title", "")) == "第三关" and p3.get_voxel_set(LP.TAG_BLOCKS).size() == 27,
		"S4: 删 level_3 五文件后重建为空骨架（第三关/27 格，非游戏侧数据）")
	check(t1ok and str(p1.get_field("title", "")) == "手改S4",
		"S4: 其余槽不受影响且不回读游戏侧（level_1 篡改保留）")

# ============ S4b 全删重初始化（3 checks；spec §3.3-6 P2-7/§6.2 S4b）【批次 V 等价替换留痕】 ============
## 删法等价替换：删 level_N/level.json ×5 → 删五文件 ×5（拆分口径的「全缺=显式重置」）。
func _s4b_full_reset() -> void:
	var root: String = LS.ensure_initialized(_make_sandbox("s4b"), FIXTURE)
	for n: int in range(1, 6):
		_remove_slot_files(root, n)
	LS.ensure_initialized(root, FIXTURE)   # 五槽全缺=显式重置 → 全量重初始化（游戏侧唯一合法回读场景）
	var p1 := _load_proj(1, root)
	check(str(p1.get_field("title", "")) == "第一关" and p1.get_voxel_set(LP.TAG_BLOCKS).size() == 192,
		"S4b: level_1 从游戏侧源重新预填（第一关/192 格）")
	var p2 := _load_proj(2, root)
	check(p2.get_block_size() == Vector3i(3, 3, 3) and p2.get_voxel_set(LP.TAG_BLOCKS).size() == 27,
		"S4b: level_2 空骨架（3³/27 格）")
	var meta_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(root + "session_meta.json"))
	check(meta_v is Dictionary and int((meta_v as Dictionary).get("last_slot", -1)) == 1,
		"S4b: meta last_slot 复位 1")

# ============ S5 读写往返（4 checks；spec §3.3-4 API 表/§6.2 S5）【批次 V 等价替换留痕】 ============
## 原断言「save_slot_text/load_slot_text 字节级零 diff」系单文件语义，随拆分退役；等价改为装配口径：
## load_slot_text 返回内存合回的完整契约文本（spec §9.3 判据①），save_slot_text 拆分五文件落盘，
## 往返以「重载 dict 逐键相等 + 五文件齐」锚定（字节级确定性由拆分装配定点性质保证，见
## test_v_editor_split P2/P6）。
func _s5_roundtrip() -> void:
	var root: String = LS.ensure_initialized(_make_sandbox("s5"), FIXTURE)
	var t: String = LS.load_slot_text(1, root)
	var p := LP.new()
	var rt_ok: bool = not t.is_empty() and p.load_from_text(t) \
		and LS.save_slot_text(1, p.save_to_text(), root) and _has_five_files(root, 1)
	var t2 := LS.load_slot_text(1, root)
	var p2 := LP.new()
	rt_ok = rt_ok and p2.load_from_text(t2)
	check(rt_ok and JSON.parse_string(t2) == JSON.parse_string(t),
		"S5: load→模型→save→load 装配口径往返 dict 逐键相等且五文件齐（原字节级零 diff 等价替换）")
	check(LS.save_meta(3, root) and int(LS.load_meta(root).get("last_slot", -1)) == 3,
		"S5: save_meta(3)/load_meta 往返 last_slot==3")
	check_eq(LS.load_meta(_make_sandbox("s5c")), {"last_slot": 1},
		"S5: load_meta 缺失文件返回缺省 {last_slot:1}")
	var bad_root := _make_sandbox("s5d")
	DirAccess.make_dir_recursive_absolute(bad_root)
	var f := FileAccess.open(bad_root + "session_meta.json", FileAccess.WRITE)
	f.store_string("not json {{{")
	f.close()
	check_eq(LS.load_meta(bad_root), {"last_slot": 1},
		"S5: load_meta 坏 JSON 返回缺省 {last_slot:1}")

# ============ S6 apply_auto_meta（6 checks；spec §3.5-1/§6.2 S6） ============
func _s6_auto_meta() -> void:
	var p := LP.new()
	p.new_project(Vector3i(3, 3, 3))
	p.set_field("chapter", 9)
	p.set_field("title", "手改")
	p.set_field("level_id", "xxx")
	p.set_field("era", "青铜")
	p.set_field("theme", "jade")
	p.set_field("description", "手写描述")
	p.get_piece()["name"] = "自定义名"
	LS.apply_auto_meta(p, 2)
	check_eq(int(p.get_field("chapter", -1)), 2, "S6: chapter 强制覆盖手改值")
	check_eq(str(p.get_field("title", "")), "第二关", "S6: title 强制覆盖手改值")
	check_eq(str(p.get_field("level_id", "")), "chapter2_editor", "S6: level_id 强制覆盖手改值")
	check_eq(str(p.get_piece().get("name", "")), "自定义名", "S6: name 非空不动")
	var p2 := LP.new()
	p2.new_project(Vector3i(3, 3, 3))   # name 默认空串
	LS.apply_auto_meta(p2, 1)
	check_eq(str(p2.get_piece().get("name", "")), "主体", "S6: name 空补「主体」")
	check(str(p.get_field("era", "")) == "青铜" and str(p.get_field("theme", "")) == "jade" \
		and str(p.get_field("description", "")) == "手写描述", "S6: era/theme/description 原样保留")

# ============ S7 源缺失降级（3 checks；spec §九 R5/§6.2 S7） ============
func _s7_missing_source() -> void:
	var root: String = LS.ensure_initialized(_make_sandbox("s7"), "res://tests/fixtures/__no_such_source.json")
	check(not root.is_empty() and root.ends_with("/"), "S7: source 缺失 → 初始化不崩且返回有效根")
	var p1 := _load_proj(1, root)
	check(str(p1.get_field("title", "")) == "第一关" and p1.get_voxel_set(LP.TAG_BLOCKS).size() == 27,
		"S7: level_1 降级为空骨架（第一关/27 格）")
	var meta_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(root + "session_meta.json"))
	check(meta_v is Dictionary and int((meta_v as Dictionary).get("last_slot", -1)) == 1,
		"S7: meta last_slot==1")
