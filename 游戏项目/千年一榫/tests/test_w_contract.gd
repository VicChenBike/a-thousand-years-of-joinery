extends "res://tests/test_base.gd"
## 批次 W（W6）P2-11 跨工程端到端契约测试（N13）——把「编辑器产出」喂给主游戏 LevelLibrary.validate_level。
## 根因（W0）：无任何测试把编辑器产物喂给 validate_level——两半各自绿、接口断裂不会被发现。
##
## 产物形态（对齐规格 P2-11）：E/levels/level_1~5/ 五件套（level.json 元数据 + blocks/target/join/final
## 四域分档）→ 按编辑器组装逻辑重组为完整契约文档后喂 validate_level，断言零 reject；
## 某槽 level.json 经完整契约文档判定已是整合文档则直接喂（对应编辑器无拆分态形态）。
## 防误用（规格原文）：五件分域文件挨个直接喂属错误做法——本测试的负路径组（D 组）与
## 红阶段实证（镜像组装漏 target 域→validate 拒载「target_shapes 为空」→红）证明断言非恒真。
##
## 组装口径对齐方式（规格允许的等价实现路线）：E/scripts/level_slots.gd 的 _assemble_doc 系
## 编辑器工程内脚本（其第 21 行 `const LP := preload("res://scripts/level_project.gd")` 为编辑器
## 工程内资源路径），跨工程动态加载编译必炸；且 levels/README_请勿接入主游戏.md 约定两工程
## 互不 import——故在测试内实现等价组装（_mirror_assemble_doc，与 _assemble_doc 逐语义对齐），
## 并以三层防漂移锁死两端口径：A 组行为级对齐断言（合成档锁合并语义）+ B 组编辑器源码锚点
## 漂移绊线（只读 token 校验）+ C 组内容槽零 reject 硬门槛。
##
## skip 语义（红线）：主游戏测试不得依赖编辑器存在——levels 根不可达/某槽五件套缺失或不完整/
## 空骨架槽（编辑器空槽设计态）/未成品槽（任一域源头为空）→ 输出 [SKIPPED] 记录并计为通过的
## check，绝不计 FAIL，保证在无编辑器的克隆/打包环境全量回归不假红。内容槽（三域源头皆有
## 内容）被 validate 拒载=真契约断裂→FAIL。
## user:// 纪律：本测试零写档（只读 FileAccess + 内存组装，零 user:// 触碰）。

const LIB_SCRIPT := "res://autoload/level_library.gd"

## 编辑器 levels 根（默认=res:// 上溯两级 + 关卡编辑器/voxel_level_editor/levels/）。
## 环境变量缝（skip 语义验证用，零写档模拟缺失态）：设 VOXEL_EDITOR_LEVELS_ROOT_FOR_TEST
## 指向替代根（可为不存在的路径）——仅本测试消费，编辑器工程不受影响。
const EDITOR_LEVELS_ENV := "VOXEL_EDITOR_LEVELS_ROOT_FOR_TEST"

const SLOTS: Array[int] = [1, 2, 3, 4, 5]
const FILE_LEVEL := "level.json"
## 四域拆分文件名（与编辑器 level_slots.gd SPLIT_FILES 同名同序；B 组源码锚点绊线兜底防漂移）。
const SPLIT_FILES: Array[String] = ["blocks.json", "target.json", "join.json", "final.json"]
const FIVE_FILES: Array[String] = [FILE_LEVEL, "blocks.json", "target.json", "join.json", "final.json"]
## 编辑器源码锚点（漂移绊线 token：函数签名 + 四域键名 + tail 透传键 + 五文件名）。
const SLOT_SOURCE_TOKENS: Array[String] = [
	"static func _assemble_doc", "static func _is_full_contract_doc",
	"join_part", "final_answer", "pieces_tail", "target_size", "target_shapes",
	"\"blocks.json\"", "\"target.json\"", "\"join.json\"", "\"final.json\"", "\"level.json\"",
]

var _skip_count: int = 0

func _initialize() -> void:
	print("== test_w_contract ==")
	var lib: Node = (load(LIB_SCRIPT) as GDScript).new()
	root.add_child(lib)
	var levels_root := _resolve_levels_root()
	print("[levels 根] %s" % (levels_root if not levels_root.is_empty() else "（空→全槽 skip）"))
	_a_mirror_assemble_semantics()
	_b_editor_source_drift_guard(levels_root)
	_c_slots_end_to_end(lib, levels_root)
	_d_negative_path(lib, levels_root)
	if _skip_count > 0:
		print("SKIPPED: %d 项（明细见上方 [SKIPPED] 行——主游戏测试不依赖编辑器存在）" % _skip_count)
	finish()

# ---------- 槽位根解析 ----------
func _resolve_levels_root() -> String:
	var env := OS.get_environment(EDITOR_LEVELS_ENV)
	if not env.is_empty():
		return env if env.ends_with("/") else env + "/"
	var game_root := ProjectSettings.globalize_path("res://")
	if game_root.is_empty():
		return ""
	# res://（游戏工程根）上溯两级=工作区根，再进编辑器工程 levels/（导出态/克隆无编辑器→不存在→全槽 skip）。
	return game_root.simplify_path().path_join("../../关卡编辑器/voxel_level_editor/levels/").simplify_path()

# ---------- 组装口径镜像（与 E/scripts/level_slots.gd _assemble_doc/_is_full_contract_doc 对齐） ----------
## 完整契约文档判定镜像（对齐 _is_full_contract_doc）：pieces 为非空数组且首项为对象。
func _mirror_is_full_contract_doc(doc: Dictionary) -> bool:
	var pieces: Variant = doc.get("pieces", null)
	return pieces is Array and not (pieces as Array).is_empty() and (pieces as Array)[0] is Dictionary

## 逆向组装镜像（对齐 _assemble_doc）：meta + 四域子文档 → 完整契约文档。
## 合并语义逐条：①blocks 域键全量入 piece（piece 级键集守恒）→②target 域键（target_shapes/
## target_size）入 piece →③join/final 非空文档才回填 join_part/final_answer 键（「缺键」状态
## 守恒）→④meta 全键上提（pieces_tail 摘除）→⑤pieces=[piece]+tail 回拼。
func _mirror_assemble_doc(meta: Dictionary, blocks_doc: Dictionary, target_doc: Dictionary,
		join_doc: Dictionary, final_doc: Dictionary) -> Dictionary:
	var piece: Dictionary = {}
	for k: Variant in blocks_doc:
		piece[k] = blocks_doc[k]
	for k: Variant in target_doc:
		piece[k] = target_doc[k]
	if not join_doc.is_empty():
		piece["join_part"] = join_doc
	if not final_doc.is_empty():
		piece["final_answer"] = final_doc
	var doc: Dictionary = {}
	for k: Variant in meta:
		if str(k) != "pieces_tail":
			doc[k] = meta[k]
	var pieces: Array = [piece]
	var tail: Variant = meta.get("pieces_tail", null)
	if tail is Array:
		for extra: Variant in tail:
			pieces.append(extra)
	doc["pieces"] = pieces
	return doc

# ---------- A 组：组装口径对齐断言（合成档，行为级锁 _assemble_doc 合并语义） ----------
## 合成五域子文档集（[meta, blocks, target, join, final]，与编辑器 _SAVE_ORDER 拆分序一一对应）。
func _synth_parts() -> Array:
	var meta: Dictionary = {
		"format_version": 1.0, "chapter": 9.0, "title": "契约测试合成档",
		"era": "", "theme": "wood",
	}
	var blocks_doc: Dictionary = {
		"piece_id": "p1", "name": "合成块",
		"block_size": {"x": 2.0, "y": 2.0, "z": 2.0}, "initial_voxels": true,
		"blocks": ["0,0,0", "1,1,1"],
	}
	var target_doc: Dictionary = {
		"target_size": {"x": 3.0, "y": 3.0, "z": 3.0},
		"target_shapes": [["1,1,1", "2,2,2"]],
	}
	var join_doc: Dictionary = {"size": {"x": 2.0, "y": 2.0, "z": 2.0}, "voxels": ["1,1,1"]}
	var final_doc: Dictionary = {"size": {"x": 2.0, "y": 2.0, "z": 2.0}, "voxels": ["0,0,0", "1,1,1"]}
	return [meta, blocks_doc, target_doc, join_doc, final_doc]

func _a_mirror_assemble_semantics() -> void:
	var parts: Array = _synth_parts()
	var doc: Dictionary = _mirror_assemble_doc(parts[0], parts[1], parts[2], parts[3], parts[4])
	var pieces: Array = doc.get("pieces", []) as Array
	check(pieces.size() == 1 and pieces[0] is Dictionary, "A1: 组装后 pieces 恰为单 piece（元数据无 pieces_tail 时）")
	if pieces.is_empty() or not (pieces[0] is Dictionary):
		return
	var piece: Dictionary = pieces[0]
	# 合并语义①②：blocks 域与 target 域键上提到 piece 级（键集守恒）。
	check(piece.get("piece_id", "") == "p1" and piece.has("blocks") and piece.has("block_size"),
		"A2: blocks 域键全量入 piece（piece_id/blocks/block_size 键集守恒）")
	check(piece.has("target_shapes") and piece.has("target_size"),
		"A3: target 域键入 piece（target_shapes/target_size）——红阶段漏此步即 validate 拒载「target_shapes 为空」")
	# 合并语义③：join/final 文档内容回填为 join_part/final_answer 键（内容恒等）。
	check(piece.get("join_part", {}) == parts[3], "A4: join.json 内容回填 piece.join_part（内容恒等）")
	check(piece.get("final_answer", {}) == parts[4], "A5: final.json 内容回填 piece.final_answer（内容恒等）")
	# 合并语义④：meta 全键上提 doc 顶层。
	check(doc.get("format_version", 0) == 1.0 and doc.get("chapter", 0) == 9.0
		and doc.get("title", "") == "契约测试合成档" and not doc.has("pieces_tail"),
		"A6: meta 全键上提 doc 顶层且 pieces_tail 不残留（摘除语义）")
	# 合并语义③的缺键守恒半边：空 join/final 文档不回填键。
	var doc_empty: Dictionary = _mirror_assemble_doc(parts[0], parts[1], parts[2], {}, {})
	var p0_empty: Dictionary = (doc_empty.get("pieces", [{}]) as Array)[0]
	check(not p0_empty.has("join_part") and not p0_empty.has("final_answer"),
		"A7: 空 join/final 文档不回填键（「缺键」状态守恒，对齐 _assemble_doc 口径）")
	# 合并语义⑤：pieces_tail（多 piece 透传留档）回拼 pieces 尾部。
	var meta_tail: Dictionary = (parts[0] as Dictionary).duplicate(true)
	var tail_piece: Dictionary = {"piece_id": "p2", "block_size": {"x": 1.0, "y": 1.0, "z": 1.0}, "blocks": []}
	meta_tail["pieces_tail"] = [tail_piece]
	var doc_tail: Dictionary = _mirror_assemble_doc(meta_tail, parts[1], parts[2], parts[3], parts[4])
	var pieces_tail: Array = doc_tail.get("pieces", []) as Array
	check(pieces_tail.size() == 2 and (pieces_tail[1] as Dictionary).get("piece_id", "") == "p2"
		and not doc_tail.has("pieces_tail"),
		"A8: pieces_tail 回拼 pieces 尾部且键自身摘除（G9 多 piece 透传语义）")
	# 完整契约文档判定镜像（对齐 _is_full_contract_doc 真值表）。
	check(_mirror_is_full_contract_doc(doc), "A9a: 有合法 pieces 的整合文档→判定 true（直喂分支判据）")
	check(not _mirror_is_full_contract_doc({"format_version": 1.0}), "A9b: 无 pieces 键的元数据档→判定 false")
	check(not _mirror_is_full_contract_doc({"pieces": []}), "A9c: pieces 空数组→判定 false")
	check(not _mirror_is_full_contract_doc({"pieces": [1]}), "A9d: pieces 首项非对象→判定 false")

# ---------- B 组：编辑器源码锚点漂移绊线（只读；编辑器缺失→skip 不 fail） ----------
func _b_editor_source_drift_guard(levels_root: String) -> void:
	var src_path := levels_root.path_join("../scripts/level_slots.gd").simplify_path()
	if not FileAccess.file_exists(src_path):
		_skip("B组: 编辑器源码不可读（%s 不存在→主游戏测试不依赖编辑器存在）" % src_path)
		return
	var src := FileAccess.get_file_as_string(src_path)
	var missing: Array[String] = []
	for token: String in SLOT_SOURCE_TOKENS:
		if not src.contains(token):
			missing.append(token)
	check(missing.is_empty(),
		"B组: 编辑器 level_slots.gd 组装口径锚点齐备（缺=%s）——镜像组装与 _assemble_doc 对齐的漂移绊线"
			% (missing if not missing.is_empty() else "无"))
	# 文件名契约：本测试 FIVE_FILES 与编辑器 FILE_* 常量同名（漂移→文件查找落空→C 组全 skip+本绊线红）。
	for name: String in FIVE_FILES:
		check(src.contains("\"%s\"" % name), "B组: 编辑器源码锚定文件名 %s（五件套命名两端口径一致）" % name)

# ---------- C 组：槽位 1~5 端到端（五件套→组装→validate_level 零 reject） ----------
func _c_slots_end_to_end(lib: Node, levels_root: String) -> void:
	for slot: int in SLOTS:
		_one_slot(lib, levels_root, slot)

func _one_slot(lib: Node, levels_root: String, slot: int) -> void:
	var loaded: Dictionary = _load_slot_doc(levels_root, slot)
	if not bool(loaded.get("ok", false)):
		_skip("slot %d: %s" % [slot, String(loaded.get("reason", ""))])
		return
	var doc: Dictionary = loaded.get("doc", {}) as Dictionary
	var path_used := String(loaded.get("path", ""))
	print("[slot %d] 组装路径=%s" % [slot, path_used])
	# 源头数据态分类（防组装漂移假 skip：空域判定读源头文件内容，不读组装结果）。
	var empty_domains: Array = loaded.get("empty_domains", []) as Array
	if empty_domains.size() == 3:
		_skip("slot %d: 空骨架槽（编辑器空槽设计态，target/join/final 三域源头皆空）" % slot)
		return
	if not empty_domains.is_empty():
		_skip("slot %d: 未成品槽（%s 域在源头为空——编辑器进行中内容，validate 拒载属空域正确语义非契约断裂）"
			% [slot, "+".join(empty_domains)])
		return
	# 内容槽：硬门槛——validate_level 必须放行（P2-11 核心断言：编辑器产物→主游戏校验零 reject）。
	var r: Dictionary = lib.validate_level(doc)
	var reject := String(r.get("reject", ""))
	check(bool(r.get("ok", false)),
		"C组 slot %d: 编辑器产物（%s 路径）组装后喂 validate_level 通过（零 reject，加载合法）" % [slot, path_used])
	check_eq(reject, "", "C组 slot %d: reject 文案为空" % slot)
	if bool(r.get("ok", false)):
		var warns: Array = r.get("warnings", []) as Array
		print("[slot %d] 警告 %d 条（越界净化不拒载）" % [slot, warns.size()])
	if slot == 1:
		check(not bool(loaded.get("meta_is_full", true)),
			"C组 slot 1: level.json 为元数据形态（非整合文档）→ 走 _assemble_doc 拆分重组路径（规格产物形态口径）")

## 单槽读盘+组装：返回 {ok, doc, path, empty_domains, meta_is_full} 或 {ok:false, reason}。
func _load_slot_doc(levels_root: String, slot: int) -> Dictionary:
	var dir := levels_root.path_join("level_%d/" % slot)
	for name: String in FIVE_FILES:
		if not FileAccess.file_exists(dir + name):
			return {"ok": false, "reason": "五件套缺 %s（%s）" % [name, dir]}
	var meta_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + FILE_LEVEL))
	if not (meta_v is Dictionary):
		return {"ok": false, "reason": "level.json 解析失败（非字典）"}
	var meta := meta_v as Dictionary
	var any_split := false
	for name: String in SPLIT_FILES:
		if FileAccess.file_exists(dir + name):
			any_split = true
			break
	if not any_split:
		# 无拆分态：level.json 经完整契约文档判定为整合文档→直接喂（对齐规格 P2-11 括注）。
		if _mirror_is_full_contract_doc(meta):
			var piece0: Dictionary = (meta.get("pieces", []) as Array)[0] as Dictionary
			return {"ok": true, "doc": meta, "path": "direct",
				"empty_domains": _source_empty_domains(
					_shapes_empty(piece0.get("target_shapes", null)),
					_voxels_empty((piece0.get("join_part", {}) as Dictionary).get("voxels", null)),
					_voxels_empty((piece0.get("final_answer", {}) as Dictionary).get("voxels", null))),
				"meta_is_full": true}
		return {"ok": false, "reason": "无拆分文件且 level.json 非整合文档（无产物）"}
	# 拆分态：四域齐备才组装（缺档/坏档→skip，对齐红线「不完整即 skip」；
	# 编辑器 _assemble_slot_text 的宽容缺省/旧档 gap 补齐语义不复刻——由编辑器侧测试覆盖）。
	var parts: Array = []
	for name: String in SPLIT_FILES:
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + name))
		if not (v is Dictionary):
			return {"ok": false, "reason": "%s 解析失败（非字典）" % name}
		parts.append(v as Dictionary)
	var doc := _mirror_assemble_doc(meta, parts[0], parts[1], parts[2], parts[3])
	return {"ok": true, "doc": doc, "path": "assemble",
		"empty_domains": _source_empty_domains(
			_shapes_empty((parts[1] as Dictionary).get("target_shapes", null)),
			_voxels_empty((parts[2] as Dictionary).get("voxels", null)),
			_voxels_empty((parts[3] as Dictionary).get("voxels", null))),
		"meta_is_full": false}

## 源头空域清单（顺序=target/join/final；"blocks" 域现状不拒载不计入，读码实况对齐
## test_v_level_library_domains P5 注）。
func _source_empty_domains(target_empty: bool, join_empty: bool, final_empty: bool) -> Array[String]:
	var out: Array[String] = []
	if target_empty:
		out.append("target")
	if join_empty:
		out.append("join")
	if final_empty:
		out.append("final")
	return out

func _shapes_empty(v: Variant) -> bool:
	if not (v is Array) or (v as Array).is_empty():
		return true
	var first: Variant = (v as Array)[0]
	return not (first is Array) or (first as Array).is_empty()

func _voxels_empty(v: Variant) -> bool:
	return not (v is Array) or (v as Array).is_empty()

# ---------- D 组：负路径（越界格注入→validate 拒载——证明该测试真的在测校验器而非恒真） ----------
func _d_negative_path(lib: Node, levels_root: String) -> void:
	# 对照半边：合成档（同 A 组五域）组装后 validate 放行——负路径结果可归因于注入本身。
	var parts: Array = _synth_parts()
	var doc: Dictionary = _mirror_assemble_doc(parts[0], parts[1], parts[2], parts[3], parts[4])
	check(bool((lib.validate_level(doc) as Dictionary).get("ok", false)),
		"D1: 对照半边——未注入的合成组装档 validate 放行（负路径非恒真前提）")
	# 负路径（合成档）：final 域整体替换为单个越界格（z=99 超出 final_answer.size.z=2）→
	# 过滤后为空→validate 拒载。
	var broken: Dictionary = doc.duplicate(true)
	((broken.get("pieces", [{}]) as Array)[0] as Dictionary)["final_answer"] = {
		"size": {"x": 2.0, "y": 2.0, "z": 2.0}, "voxels": ["0,0,99"],
	}
	var rb: Dictionary = lib.validate_level(broken)
	check(not bool(rb.get("ok", true)), "D2: 注入越界格（z 超 final_answer.size）→ validate 拒载（校验器真实生效）")
	check(String(rb.get("reject", "")).contains("final_answer"), "D3: 拒载原因指向 final_answer 域（过滤后为空）")
	# 负路径（真实档，若在手）：对 slot 1 真实组装文档做同款注入（无编辑器→skip 留痕）。
	var loaded: Dictionary = _load_slot_doc(levels_root, 1)
	if not bool(loaded.get("ok", false)):
		_skip("D组真实档: slot 1 文档不可得（%s）" % String(loaded.get("reason", "")))
		return
	var real_doc: Dictionary = loaded.get("doc", {}) as Dictionary
	var real_piece: Dictionary = (real_doc.get("pieces", [{}]) as Array)[0] as Dictionary
	if not (real_piece.get("final_answer", null) is Dictionary):
		_skip("D组真实档: slot 1 无 final_answer 域（空域档）")
		return
	var real_broken: Dictionary = real_doc.duplicate(true)
	((real_broken.get("pieces", [{}]) as Array)[0] as Dictionary)["final_answer"] = {
		"size": (real_piece.get("final_answer", {}) as Dictionary).get("size", {}),
		"voxels": ["0,0,99"],
	}
	var rr: Dictionary = lib.validate_level(real_broken)
	check(not bool(rr.get("ok", true)),
		"D4: 真实组装档注入越界格→ validate 拒载（编辑器产物侧校验器真实生效）")

# ---------- 基础设施 ----------
func _skip(msg: String) -> void:
	_skip_count += 1
	print("[SKIPPED] %s" % msg)
	check(true, "SKIPPED %s" % msg)
