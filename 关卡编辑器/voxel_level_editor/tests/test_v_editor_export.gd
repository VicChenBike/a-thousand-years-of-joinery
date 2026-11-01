extends "res://tests/test_base.gd"
## 批次 W（W5，N16 拍板 9）编辑器去导出化——本文件自批次 V「导出契约 JSON」测试**等价改写**：
## 导出链路整体退役（按钮/处理器/LevelSlots.export_contract_text/last_export_error/EXPORT_NAME/
## level_export.json 磁盘产物全删），旧 63 条导出断言（P1~P8）随被测对象退役删除，等价改写为——
##   W1 无导出入口：LevelSlots 无 export_contract_text 方法/last_export_error 静态变量；
##      editor_main 实例无 TopBar/BtnExportContract 节点、无 _on_export_contract_pressed 方法；
##      真实工作区 E/levels/level_1/level_export.json 不存在（回归锁：不得再生成）。
##   W2 五件套实时自动保存仍在（N16 拍板「编辑器产出=五件套实时自动保存，保留不动」）：
##      沙盒实例化 editor_main → 模拟挖除一格 → blocks.json 实时落盘且内容正确、
##      level.json 元数据零变化、FileNameLabel「已保存」反馈在、session_meta 可解析。
## 改写留痕（20260920，spec §6 N16）：被删断言=旧 P1（导出文件/target_size 落键）、P2（四域一致）、
## P3（导出零触碰）、P4（顶层透传）、P5（pieces_tail 还原）、P6（异值保留/不裁剪）、P7（失败报因）、
## P8（按钮接线/点击落盘）——被测功能随 N16 拍板整体退役，非等价语义改写而是功能移除的伴随删改；
## 五件套保存语义由本文件 W2 段 + test_level_slots/test_v_editor_split/test_sanity 既有断言承接。
## 磁盘纪律：root 参数注入 TEMP 一次性子目录（test_level_slots P7 裁决先例），真实 levels/ 零触碰
## （W1 的真实 level_export.json 缺席断言为只读检查）。Godot 4.7 坑对齐：字典取键一律 .get 防御。

const LS := preload("res://scripts/level_slots.gd")
const LP := preload("res://scripts/level_project.gd")
const FIXTURE := "res://tests/fixtures/level_chapter1_hemudu.json"

## Script 基类型变量（has_method/get 动态派发——const preload 静态解析下对类直调实例方法
## 系 Parse Error，旧件 P 段同款手法；仅服务 W1 的「成员已删」断言）
var _ls_dyn: Script = preload("res://scripts/level_slots.gd")

const F_LEVEL := "level.json"
const F_BLOCKS := "blocks.json"
const F_TARGET := "target.json"
const F_JOIN := "join.json"
const F_FINAL := "final.json"
const F_EXPORT := "level_export.json"
const F_META := "session_meta.json"
const WORK_FILES: Array[String] = [F_LEVEL, F_BLOCKS, F_TARGET, F_JOIN, F_FINAL]

var _sandbox: String = ""
var _ed: Control = null

func _initialize() -> void:
	print("== test_v_editor_export（批次 W 等价改写：编辑器无导出入口 + 五件套实时保存回归） ==")
	_w1_no_export_entry()
	await _w2_five_file_autosave_alive()
	_cleanup()
	finish()

# ---------- 沙盒 helper（P7 裁决：TEMP 一次性子目录，严禁写工程树内路径） ----------
func _make_sandbox() -> String:
	var base := OS.get_environment("TEMP")
	if base.is_empty():
		base = "/tmp"
	base = base.replace("\\", "/")
	return base.path_join("voxel_editor_wnoexp_%d" % Time.get_ticks_msec()) + "/"

func _cleanup() -> void:
	if _ed != null:
		_ed.free()
		_ed = null
	OS.set_environment("VOXEL_EDITOR_SLOTS_ROOT", "")
	OS.set_environment("VOXEL_EDITOR_DEFAULT_SOURCE", "")
	if not _sandbox.is_empty():
		_remove_dir_recursive(_sandbox)
		_sandbox = ""

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

func _file_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

# ============ W1 无导出入口（N16 拍板 9：按钮/方法/生成函数/磁盘产物全不在） ============
func _w1_no_export_entry() -> void:
	check(_ls_dyn.has_method("export_contract_text") == false,
		"W1a: LevelSlots 无 export_contract_text 方法（导出生成函数已删，红：批次 V 在）")
	check(_ls_get("last_export_error") == null,
		"W1b: LevelSlots 无 last_export_error 静态变量（导出报因变量已删，红：批次 V 在）")
	check(FileAccess.file_exists("res://levels/level_1/" + F_EXPORT) == false,
		"W1c: 真实工作区 E/levels/level_1/level_export.json 不存在（N16②：已生成的产物已删除；只读检查零触碰）")
	check(not str(LS.README_TEXT).contains("level_export"),
		"W1d: README_TEXT 常量无导出描述（第 7 条随导出退役删除，红：批次 V 在）")
	var disk_readme := _file_text("res://levels/README_请勿接入主游戏.md")
	check(not disk_readme.is_empty() and not disk_readme.contains("level_export"),
		"W1e: 磁盘 README_请勿接入主游戏.md 无 level_export 导出描述（E 内 README 同步改稿）")

## 静态变量动态读（4.7：变量被删后 .get 返回 null；str(null) 不中止——坑⑦⑩判空纪律）
func _ls_get(prop: String) -> Variant:
	return _ls_dyn.get(prop)

# ============ W2 五件套实时自动保存仍在（N16 拍板：产出保留不动） ============
func _w2_five_file_autosave_alive() -> void:
	_sandbox = _make_sandbox()
	var root: String = LS.ensure_initialized(_sandbox, FIXTURE)
	check(root == _sandbox, "W2a: 沙盒预初始化成功（前置）")
	OS.set_environment("VOXEL_EDITOR_SLOTS_ROOT", _sandbox)
	_ed = (load("res://scenes/editor_main.tscn") as PackedScene).instantiate() as Control
	add_child(_ed)
	await process_frame   # --script 模式 add_child 后 _ready 延后一帧（G6 惯例）
	check(_ed.get_node_or_null("TopBar/BtnExportContract") == null,
		"W2b: editor_main 无 BtnExportContract 按钮（顶栏去导出钮，红：批次 V 在）")
	check(_ed.has_method("_on_export_contract_pressed") == false,
		"W2c: editor_main 无 _on_export_contract_pressed 处理器（导出链路已删，红：批次 V 在）")
	# 五件套在场（槽位工作区完整）
	var five_ok := true
	for name: String in WORK_FILES:
		if not FileAccess.file_exists(_sandbox + "level_1/" + name):
			five_ok = false
	check(five_ok, "W2d: level_1 五件套在盘（实时保存产出形态）")
	# 模拟挖除一格 → 自动保存实时落盘
	var blocks_before := _file_text(_sandbox + "level_1/" + F_BLOCKS)
	var level_before := _file_text(_sandbox + "level_1/" + F_LEVEL)
	check(not blocks_before.is_empty(), "W2e: 挖除前 blocks.json 非空（前置）")
	var before_files: Dictionary = {}
	for name: String in WORK_FILES:
		before_files[name] = _file_text(_sandbox + "level_1/" + name)
	_ed.call("_on_dig_requested", [Vector3i(0, 0, 0)])   # 夹具 8×3×8 实心 192 格，(0,0,0) 可挖
	var blocks_after := _file_text(_sandbox + "level_1/" + F_BLOCKS)
	check(not blocks_after.is_empty() and blocks_after != blocks_before,
		"W2f: 挖除后 blocks.json 实时重写（自动保存仍在，红：保存链路断则文件不变）")
	var parsed: Variant = JSON.parse_string(blocks_after)
	var blocks_arr: Array = (parsed as Dictionary).get("blocks", []) if parsed is Dictionary else []
	check_eq(blocks_arr.size(), 191, "W2g: blocks 域 192→191 格（挖除生效且内容正确）")
	check_eq(_file_text(_sandbox + "level_1/" + F_LEVEL), before_files[F_LEVEL],
		"W2h: level.json 元数据逐字节不变（挖除只动 blocks 域，五文件拆分写序保持）")
	var others_ok: bool = _file_text(_sandbox + "level_1/" + F_TARGET) == before_files[F_TARGET] \
		and _file_text(_sandbox + "level_1/" + F_JOIN) == before_files[F_JOIN] \
		and _file_text(_sandbox + "level_1/" + F_FINAL) == before_files[F_FINAL]
	check(others_ok, "W2i: target/join/final 域文件内容逐字节不变（确定性序列化——无关域内容不受挖除影响）")
	check(((_ed.get_node("TopBar/FileNameLabel") as Label).text).contains("已保存"),
		"W2j: FileNameLabel「已保存」反馈在（自动保存 UI 链路保持）")
	var meta: Variant = JSON.parse_string(_file_text(_sandbox + F_META))
	check(meta is Dictionary and int((meta as Dictionary).get("last_slot", -1)) == 1,
		"W2k: session_meta.json 可解析且 last_slot==1（保存伴随元数据健康）")
	# 批次 W 补强断言（五件套拆分契约与元数据原子写在自动保存流中的健康度，只增不减对账）：
	var level_doc: Variant = JSON.parse_string(_file_text(_sandbox + "level_1/" + F_LEVEL))
	check(level_doc is Dictionary and not (level_doc as Dictionary).has("pieces"),
		"W2l: level.json 挖除后仍为元数据（无 pieces 键，拆分契约保持）")
	var domains_ok := true
	for name2: String in [F_TARGET, F_JOIN, F_FINAL]:
		if not (JSON.parse_string(_file_text(_sandbox + "level_1/" + name2)) is Dictionary):
			domains_ok = false
	check(domains_ok, "W2m: target/join/final 三域文件挖除后均为合法 JSON 对象（五件套健康）")
	check(not FileAccess.file_exists(_sandbox + "level_1/" + F_EXPORT),
		"W2n: 编辑操作后亦无 level_export.json（导出不再生成，红：旧链路会旁路落盘）")
	var meta_residue := FileAccess.file_exists(_sandbox + F_META + ".tmp") \
		or FileAccess.file_exists(_sandbox + F_META + ".bak")
	check(not meta_residue,
		"W2o: 自动保存流 session_meta 零 .tmp/.bak 残留（P3-4c 原子写成功态不留中间件）")
