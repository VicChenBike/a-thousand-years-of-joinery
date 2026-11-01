class_name LevelProject
extends RefCounted
## 关卡编辑器·纯逻辑层：format_version=1 关卡数据模型 + JSON 读写 + 实心生成（规格 §6.2 行 1）。
## 单一数据源 = _data 原始 Dictionary（解析序保留，不做破坏性重构）——未知字段、pieces[1..]、
## 透传字段（theme/anim_time/grid_size_unused/match_offset/initial_voxels）原样保留（规格 §9.5）。
## 序列化四步（规格 §9.3，T1-5 实现）：2 空格 stringify → CRLF 回填 → 尾换行回填 → 无 BOM 写出。
## 零场景依赖、零 autoload 依赖（未来并入游戏的迁移接口，规格 §6.1）。
## 命名注意：不使用 get_meta/set_meta（与 Object 内建冲突），元数据读写为 get_field/set_field。

const FORMAT_VERSION := 1
const DIM_MIN := 1
const DIM_MAX := 32
const CHAPTER_MIN := 1
const CHAPTER_MAX := 5

# 四件套体素集标签（get_voxel_set/set_voxel_set 的 which 参数）
const TAG_BLOCKS := 0
const TAG_TARGET := 1
const TAG_JOIN := 2
const TAG_FINAL := 3

const _BAD_CELL := Vector3i(1 << 21, 1 << 21, 1 << 21)

# 保存侧契约提示文案（规格 §9.4 表，T10 口径，非阻断不拦截）
const HINT_TARGET_EMPTY := "提示：target_shapes[0] 为空，游戏将拒载（target_shapes 为空）"
const HINT_JOIN_EMPTY := "提示：join_part.voxels 为空，游戏将拒载"
const HINT_FINAL_EMPTY := "提示：final_answer.voxels 为空，游戏将拒载"
const HINT_ALL_OK := "已保存（契约提示：全部通过）"
## 隔离性修复批 20260917（R1）：join/final 超域保留知情提示——编辑器对超出 block_size 域的
## join_part/final_answer 体素「保留数据不删、照实落盘」；游戏加载侧按接口规范 §8.2 净化
## （静默跳过超域格）→ 以 N 告知用户（不自动删除，保数据知情权）。展示走编辑器既有
## _autosave_current 契约提示机制（内容变化才刷新）。
## 批次 V（V-E1，规格 §9.1）文案语义同步：计数改 per-domain（各格集按「所属域自身尺寸」计越界，
## 见 count_over_domain_cells）——旧「对接件/最终成品…初始木块域」枚举措辞随之退役（U12④ 扫描集
## 扩四标签时文案未同步的历史欠账一并清偿），改按所属组件域口径。
const HINT_OVER_DOMAIN := "有 %d 格超出所属组件域尺寸，游戏加载时将被裁剪"
## 批次 Y6（Y-D3，spec §9.4）：可挖出性两条软提示（非阻断不拦截，置于既有空集/超域分支之后，
## 优先级：空集 > 超域 > 不可通关 > final 不一致）——
## ①「不可通关」：target 格数>blocks 格数，或 target 归一 bbox 无法被 blocks 域容纳（拍板字面
##   口径的知情提示；不替代 48 变换等价的试玩判定，playtest_judge 仍是唯一判定真值）；
## ②「final 不一致」：final_answer 格集合 ≠ target_shapes[0] ∪ join_part.voxels（同坐标集合
##   语义去重比对；接口规范 §5：final 语义=target∪join 的合成，供校验不强制）。
const HINT_UNDIGGABLE := "该关可能不可通关：标准答案挖不出（超出初始木块范围）"
const HINT_FINAL_MISMATCH := "最终成品与 标准答案∪对接件 不一致（契约供校验，不强制）"

var _data: Dictionary = {}           # 原始关卡数据（键序=解析序）
var _crlf: bool = true               # 文本风格记录①：行尾是否 CRLF（规格 §9.2）
var _ends_with_newline: bool = true  # 文本风格记录②：是否以换行结尾
var _loaded_piece_count: int = 1     # 打开时 piece 总数（多 piece 状态栏提示用，§9.2）
var load_warnings: Array = []        # 批次 U（U12⑤）：载入非致命警告累积（状态栏消费，每次载入重置）

# ---------- 尺寸与实心（规格 §7.3 / §9.1 T1） ----------
static func is_valid_size(v: Vector3i) -> bool:
	return v.x >= DIM_MIN and v.x <= DIM_MAX \
		and v.y >= DIM_MIN and v.y <= DIM_MAX \
		and v.z >= DIM_MIN and v.z <= DIM_MAX

## 界内全格集合（行优先 x 递增再 y 再 z，与契约 §3 格式 A 编码序一致）。
static func solid_cells(size: Vector3i) -> Dictionary:
	var out: Dictionary = {}
	for x: int in range(size.x):
		for y: int in range(size.y):
			for z: int in range(size.z):
				out[Vector3i(x, y, z)] = true
	return out

## 坐标串化："x,y,z"（契约 §3 格式 A）。
static func cell_to_string(c: Vector3i) -> String:
	return "%d,%d,%d" % [c.x, c.y, c.z]

## 坐标解析：Vector3i/Vector3/"x,y,z" → Vector3i；非法返回 _BAD_CELL（调用方跳过）。
static func parse_cell(v: Variant) -> Vector3i:
	if v is Vector3i:
		return v
	if v is Vector3:
		return Vector3i(v)
	if v is String:
		var parts: PackedStringArray = (v as String).split(",")
		if parts.size() != 3:
			return _BAD_CELL
		return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
	return _BAD_CELL

## 字符串数组 → Vector3i 集合（非法元素跳过，去重靠字典键）。
static func strings_to_set(arr: Array) -> Dictionary:
	var out: Dictionary = {}
	for v: Variant in arr:
		var c := parse_cell(v)
		if c != _BAD_CELL:
			out[c] = true
	return out

## Vector3i 集合 → 字符串数组（含非法键防御跳过）。
static func _set_to_strings(cells: Dictionary) -> Array:
	var out: Array = []
	for k: Variant in cells:
		var c: Vector3i = k
		if c != _BAD_CELL:
			out.append(cell_to_string(c))
	return out

## 尺寸越界收缩裁剪（规格 §7.3 / 审查回修 P2-2：尺寸变更对四体素集统一裁剪的纯函数半部）。
static func clip_out_of_bounds(cells: Dictionary, size: Vector3i) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in cells:
		var c: Vector3i = k
		if c.x >= 0 and c.x < size.x and c.y >= 0 and c.y < size.y and c.z >= 0 and c.z < size.z:
			out[c] = true
	return out

## level_id 自动生成（T2：chapter{N}_untitled，N 夹紧 1~5，契约 §8.2 chapter>5 无消费入口）。
static func auto_level_id(chapter: int) -> String:
	return "chapter%d_untitled" % clampi(chapter, CHAPTER_MIN, CHAPTER_MAX)

# ---------- 新建（规格 §9.1：默认 3×3×3 实心、元数据全默认、键序与第 1 关一致） ----------
func new_project(size: Vector3i) -> bool:
	if not is_valid_size(size):
		return false
	_data = {
		"format_version": FORMAT_VERSION,
		"level_id": auto_level_id(1),
		"chapter": 1,
		"title": "",
		"era": "",
		"theme": "wood",
		"description": "",
		"anim_time": 100,
		"grid_size_unused": 0,
		"pieces": [{
			"piece_id": "p1",
			"name": "",
			"block_size": {"x": size.x, "y": size.y, "z": size.z},
			# 批次 V（V-E1，规格 §9.1）：标准答案独立尺寸域——新建即落 target_size=block_size，
			# tag1 页从此写独立字段（不再与 block_size 同料联动）。
			"target_size": {"x": size.x, "y": size.y, "z": size.z},
			"initial_voxels": true,
			"blocks": _set_to_strings(solid_cells(size)),
			"target_shapes": [[]],
			"join_part": {"size": {"x": size.x, "y": size.y, "z": size.z}, "voxels": []},
			"final_answer": {"size": {"x": size.x, "y": size.y, "z": size.z}, "voxels": []},
			"match_offset": {"x": 0, "y": 0, "z": 0},
		}],
	}
	_crlf = true
	_ends_with_newline = true
	_loaded_piece_count = 1
	return true

# ---------- 元数据（顶层字段透传读写） ----------
func get_field(key: String, fallback: Variant = null) -> Variant:
	return _data.get(key, fallback)

func set_field(key: String, value: Variant) -> void:
	_data[key] = value

# ---------- piece 与四件套访问器（规格 §3.2：只读写 pieces[0] / target_shapes[0]） ----------
func get_piece() -> Dictionary:
	var pieces: Array = _data.get("pieces", [])
	if pieces.is_empty() or not (pieces[0] is Dictionary):
		return {}
	return pieces[0]

func get_piece_count() -> int:
	return _loaded_piece_count

func get_block_size() -> Vector3i:
	var bs: Dictionary = get_piece().get("block_size", {})
	return Vector3i(int(bs.get("x", 1)), int(bs.get("y", 1)), int(bs.get("z", 1)))

func set_block_size(v: Vector3i) -> bool:
	if not is_valid_size(v):
		return false
	get_piece()["block_size"] = {"x": v.x, "y": v.y, "z": v.z}
	return true

## 分域尺寸读（规格 §3.1-1 → 批次 V §9.1 四域彻底分流）：tag0→block_size；tag1→target_size
## （缺失回落 block_size——「回落链」= 整缺返回 block_size、部分缺轴逐轴回落、非法轴值夹紧
## DIM_MIN~DIM_MAX）；tag2→join_part.size；tag3→final_answer.size。缺失回落口径：目标 size 字典
## 缺失/空/缺任一轴 → 逐轴回落 block_size 对应轴值（旧文件三处同值时天然等价，零数据丢失）。
## 批次 V 红线：tag1 读路径**零物化**（不补建 target_size 键、不回写）——旧档（无 target_size）
## 读入即回落，往返零 diff 保留（对位 _ensure_join_final 读路径会补建结构的差异点，本域刻意更严）。
## join/final 读路径经 _ensure_join_final 宽容补建，与 get_voxel_set 同纪律（现状保持）。
func get_size_for_tag(tag: int) -> Vector3i:
	if tag == TAG_TARGET:
		var bs_t := get_block_size()
		var ts: Variant = get_piece().get("target_size", null)
		if not (ts is Dictionary):
			return bs_t   # 批次 V：整缺回落 block_size（零迁移，读路径零写入）
		var d_t: Dictionary = ts
		return Vector3i(
			clampi(int(d_t.get("x", bs_t.x)), DIM_MIN, DIM_MAX),
			clampi(int(d_t.get("y", bs_t.y)), DIM_MIN, DIM_MAX),
			clampi(int(d_t.get("z", bs_t.z)), DIM_MIN, DIM_MAX))
	if tag == TAG_JOIN or tag == TAG_FINAL:
		var key := "join_part" if tag == TAG_JOIN else "final_answer"
		var bs := get_block_size()
		var sz: Dictionary = _ensure_join_final(key)["size"]
		return Vector3i(
			clampi(int(sz.get("x", bs.x)), DIM_MIN, DIM_MAX),
			clampi(int(sz.get("y", bs.y)), DIM_MIN, DIM_MAX),
			clampi(int(sz.get("z", bs.z)), DIM_MIN, DIM_MAX))
	return get_block_size()

## 分域尺寸写（规格 §3.1-1 → 批次 V §9.1 四域彻底分流）：先 is_valid_size 校验（每维 1~32，
## 与契约 §5 一致）；tag0→set_block_size；tag1→独立写 pieces[0].target_size 完整三轴（不再联动
## block_size——「同料联动」正是批次 V 主诉根因）；tag2/3→_ensure_join_final(key)["size"] 完整三轴。
## 非法尺寸返回 false 且零改动（对位 set_block_size 口径）。
func set_size_for_tag(tag: int, v: Vector3i) -> bool:
	if not is_valid_size(v):
		return false
	if tag == TAG_TARGET:
		get_piece()["target_size"] = {"x": v.x, "y": v.y, "z": v.z}
		return true
	if tag == TAG_JOIN or tag == TAG_FINAL:
		var key := "join_part" if tag == TAG_JOIN else "final_answer"
		_ensure_join_final(key)["size"] = {"x": v.x, "y": v.y, "z": v.z}
		return true
	return set_block_size(v)

func get_total_capacity() -> int:
	var bs := get_block_size()
	return bs.x * bs.y * bs.z

## 四件套体素数组承载体（缺字段宽容补建；target_shapes 永远只暴露 [0]）。
func _ensure_tag_voxels(which: int) -> Array:
	var piece := get_piece()
	match which:
		TAG_BLOCKS:
			if not (piece.get("blocks") is Array):
				piece["blocks"] = []
			return piece["blocks"]
		TAG_TARGET:
			if not (piece.get("target_shapes") is Array):
				piece["target_shapes"] = [[]]
			var shapes: Array = piece["target_shapes"]
			if shapes.is_empty():
				shapes.append([])
			if not (shapes[0] is Array):
				shapes[0] = []
			return shapes[0]
		TAG_JOIN:
			return _ensure_join_final("join_part")["voxels"]
		TAG_FINAL:
			return _ensure_join_final("final_answer")["voxels"]
	return []

func _ensure_join_final(key: String) -> Dictionary:
	var piece := get_piece()
	if not (piece.get(key) is Dictionary):
		piece[key] = {"size": {}, "voxels": []}
	var d: Dictionary = piece[key]
	if not (d.get("size") is Dictionary):
		d["size"] = {}
	if not (d.get("voxels") is Array):
		d["voxels"] = []
	return d

## 读四件套体素集（Vector3i → true；非法串跳过）。
func get_voxel_set(which: int) -> Dictionary:
	return strings_to_set(_ensure_tag_voxels(which))

## 写四件套体素集（target 只写 [0]，数组结构完整保留——规格 §3.2 拍板 1/8）。
func set_voxel_set(which: int, cells: Dictionary) -> void:
	var arr := _set_to_strings(cells)
	var piece := get_piece()
	match which:
		TAG_BLOCKS:
			piece["blocks"] = arr
		TAG_TARGET:
			if not (piece.get("target_shapes") is Array):
				piece["target_shapes"] = [[]]
			var shapes: Array = piece["target_shapes"]
			if shapes.is_empty():
				shapes.append([])
			shapes[0] = arr
		TAG_JOIN:
			_ensure_join_final("join_part")["voxels"] = arr
		TAG_FINAL:
			_ensure_join_final("final_answer")["voxels"] = arr

## 尺寸收缩预演·分域口径（规格 §3.1-3；原 plan_shrink 四域同尺寸口径退役，20260916 槽位化批）：
## sizes 键=标签（0..3）、值=该标签新尺寸；返回 {标签 0..3: Dictionary(Vector3i→true)} = 该标签
## 按「自己的域尺寸」越界将被裁的格集；sizes 未含的标签=本波不变更 → 空集（零裁剪）。
## 读 get_voxel_set 四访问器（宽容补建读路径），内部复用 clip_out_of_bounds（cells−kept=removed，
## 与旧 plan_shrink 循环体同构，仅 new_size 来源改为 sizes[which]）。无副作用：不改 _data/block_size。
## 不校验 is_valid_size（调用方把关，同旧口径）。等价性锚：四域同值入参与旧 plan_shrink 语义
## 完全等价（test_level_project F5-2 锚定断言兜底）。
func plan_shrink_domains(sizes: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for which: int in [TAG_BLOCKS, TAG_TARGET, TAG_JOIN, TAG_FINAL]:
		var removed: Dictionary = {}
		if sizes.has(which):
			var cells := get_voxel_set(which)
			var nsz: Vector3i = sizes[which]
			var kept := clip_out_of_bounds(cells, nsz)
			for k: Variant in cells:
				if not kept.has(k):
					removed[k] = true
		out[which] = removed
	return out

# ---------- 打开（规格 §9.2：最小结构门 + 文本风格记录） ----------
## 仅「能否装载为工程」之门：format_version==1 且 pieces 非空数组且首项为对象；
## 其余字段缺失一律宽容（缺 target_shapes → 空集照开）。失败返回 false（调用方状态栏提示）。
func load_from_text(text: String) -> bool:
	load_warnings.clear()   # 批次 U（U12⑤）：每次载入重置警告累积
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return false
	var d: Dictionary = parsed
	if int(d.get("format_version", -1)) != FORMAT_VERSION:
		return false
	var pieces_v: Variant = d.get("pieces", null)
	if not (pieces_v is Array) or (pieces_v as Array).is_empty():
		return false
	if not ((pieces_v as Array)[0] is Dictionary):
		return false
	_data = d
	_crlf = text.contains("\r\n")
	_ends_with_newline = text.ends_with("\n")
	_loaded_piece_count = (pieces_v as Array).size()
	# 批次 U（U12⑤，spec §4-U12-⑤）：缺/非法 block_size 显式归一——警告＋按 1×1×1 显式回写进
	# 模型（消除与游戏侧 level_library.gd:128-129 拒载「体素尺寸越界」的静默不一致；
	# get_block_size 既有缺省回落本就是 1×1×1，此处补的是「显式进模型可保存回写」半边）。
	var piece: Dictionary = (pieces_v as Array)[0]
	var _bs_v: Variant = piece.get("block_size", null)
	if _bs_v == null or typeof(_bs_v) != TYPE_DICTIONARY \
			or not (_bs_v as Dictionary).has_all(["x", "y", "z"]):
		load_warnings.append("警告：关卡缺少 block_size，已按 1×1×1 归一补写（保存后与游戏侧兼容）")
		piece["block_size"] = {"x": 1, "y": 1, "z": 1}
	return true

# ---------- 另存（规格 §9.3 四步确定性序列化——往返零 diff 的实现基础） ----------
## ① JSON.stringify(_data, "  ", false)（2 空格、无注释无尾逗号无 BOM；第 3 参 sort_keys=false
##    保解析键序——Godot 4.7 默认 true 会按字母重排键，违背「键序=解析序」，引擎实证留痕）；
## ② 尾换行回填（先按记录补 "\n"）；③ CRLF 回填（"\n" 全量替换 "\r\n"——stringify 永不输出 \r，
##    先补尾换行再统一替换保证两者一致）；④ 调用方经 FileAccess.store_string 写出（无 BOM 无行尾翻译）。
## T6（规格 §7.3 → 20260916 槽位化批 §3.1-2 改写）：原「join/final size 强制同步 = block_size」
## 已退役（三处归一正是「全局串改」bug 根因）——改缺失补齐口径：仅 size 字典为空时按
## get_size_for_tag 落值（老文件本就缺失时补的值=block_size，与旧行为等价），已有独立值永不覆盖。
## 引擎实证修正（§0.3-11）：4.7 的 JSON.parse_string 把一切数值回析为 float（"8"→8.0），
## 「int 保持 int」并非 stringify 免费所得——保存前先 _normalize_json_ints 就地把整值 float 还原为 int。
func save_to_text() -> String:
	# 分域改写（规格 §3.1-2）：删旧「join/final size 强制同步=block_size」两行（旧 :263-264），
	# 改缺失补齐口径（_size_fill_or_keep）。先 join 后 final 的写序保留，键序不漂移。
	# 批次 V（V-E1，规格 §9.1）：target 域同步接入 _size_fill_or_keep 口径（见 _size_fill_or_keep_target）。
	_ensure_join_final("join_part")["size"] = _size_fill_or_keep("join_part", TAG_JOIN)
	_ensure_join_final("final_answer")["size"] = _size_fill_or_keep("final_answer", TAG_FINAL)
	_size_fill_or_keep_target()
	_normalize_json_ints(_data)
	var text := JSON.stringify(_data, "  ", false)
	if _ends_with_newline:
		text += "\n"
	if _crlf:
		text = text.replace("\n", "\r\n")
	return text

## 缺失补齐 helper（规格 §3.1-2）：join_part/final_answer 的 size 字典为空 → 按 get_size_for_tag(tag)
## 取值（缺失回落 block_size）落完整三轴；已有独立值 → 原样返回（永不覆盖）。
func _size_fill_or_keep(key: String, tag: int) -> Dictionary:
	var sz: Dictionary = _ensure_join_final(key)["size"]
	if sz.is_empty():
		var v := get_size_for_tag(tag)
		return {"x": v.x, "y": v.y, "z": v.z}
	return sz

## 批次 V（V-E1，规格 §9.1）：target 域的 _size_fill_or_keep 同口径扩展——
## ① 已有非空 target_size → 原样保留（永不覆盖，同 join/final）；
## ② target_size 为空字典 → 按 get_size_for_tag(1)（缺失回落值）落完整三轴（空字典补齐）；
## ③ target_size 键整缺 → **不补写**（落定行为，写明与 join/final 先例的刻意差异）：
##    join/final 先例是「缺结构 → _ensure 补建 + save 补齐值」（老档保存后即含该键）；target 域
##    若照搬，旧档一经编辑器打开+自动保存即被追加 target_size 键=回写污染，违背批次 V「旧档
##    零迁移、读入回落且不得立即回写」红线，且破坏既有「旧档往返逐字节零 diff」硬门槛
##    （test_level_project B 组夹具往返断言、test_sanity G26 ⑥ 落盘比对均锚定）。故本域取
##    「键缺=不落键」最小写入口径：回落语义由读路径（get_size_for_tag(1)→block_size）天然兼容，
##    游戏侧消费缺失 target_size 亦按回落 bs（规格 §9.5），全链零迁移。
func _size_fill_or_keep_target() -> void:
	var piece := get_piece()
	var ts: Variant = piece.get("target_size", null)
	if ts is Dictionary and (ts as Dictionary).is_empty():
		var v := get_size_for_tag(TAG_TARGET)
		piece["target_size"] = {"x": v.x, "y": v.y, "z": v.z}

# ---------- 保存侧契约提示（规格 §9.4：非阻断一行提示，零拦截零弹窗） ----------
## 对齐游戏拒载原因文案（契约 §8.2 拒绝项）；定位=「人工观察校验」的辅助信息，不是校验门禁。
## 隔离性修复批 20260917（R1）：三条空集提示之后新增超域分支——join_part.voxels +
## final_answer.voxels 中超出 block_size 域的格数 N>0 时返回 HINT_OVER_DOMAIN（超域保留知情）。
## 批次 V（V-E1，规格 §9.1）：超域分支计数改 per-domain（见 count_over_domain_cells），
## 文案常量同步为「超出所属组件域尺寸」口径。
func contract_hint() -> String:
	if get_voxel_set(TAG_TARGET).is_empty():
		return HINT_TARGET_EMPTY
	if get_voxel_set(TAG_JOIN).is_empty():
		return HINT_JOIN_EMPTY
	if get_voxel_set(TAG_FINAL).is_empty():
		return HINT_FINAL_EMPTY
	var over := count_over_domain_cells()
	if over > 0:
		return HINT_OVER_DOMAIN % over
	# 批次 Y6（Y-D3，spec §9.4）：可挖出性两条软提示（非阻断；至此 target/join/final 均非空）。
	if not _target_diggable():
		return HINT_UNDIGGABLE
	if not _final_matches_union():
		return HINT_FINAL_MISMATCH
	return HINT_ALL_OK

## Y-D3 ①：target 可挖出性预判（软提示口径，非判定真值）——target 格数>blocks 格数，或
## target 平移归一 bbox（min 角到原点后 max−min+1）任一维越出 block_size 对应维 → false。
## 调用前置：target 非空（contract_hint 空集分支已先行）。
func _target_diggable() -> bool:
	var t := get_voxel_set(TAG_TARGET)
	var b := get_voxel_set(TAG_BLOCKS)
	if t.size() > b.size():
		return false
	var bs := get_block_size()
	var mn := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var mx := Vector3i(-(1 << 30), -(1 << 30), -(1 << 30))
	for c_v: Variant in t:
		var c: Vector3i = c_v
		mn.x = mini(mn.x, c.x); mn.y = mini(mn.y, c.y); mn.z = mini(mn.z, c.z)
		mx.x = maxi(mx.x, c.x); mx.y = maxi(mx.y, c.y); mx.z = maxi(mx.z, c.z)
	var dims := mx - mn + Vector3i.ONE
	return dims.x <= bs.x and dims.y <= bs.y and dims.z <= bs.z

## Y-D3 ②：final 与 target∪join 的同坐标格集合一致性（集合语义，键去重、无序比较）——
## final 集与并集基数相等且并集 ⊆ final ⇔ 集合相等。调用前置：三方均非空（空集分支已先行）。
func _final_matches_union() -> bool:
	var u := get_voxel_set(TAG_TARGET)
	for c_v: Variant in get_voxel_set(TAG_JOIN):
		u[c_v] = true
	var f := get_voxel_set(TAG_FINAL)
	if f.size() != u.size():
		return false
	for k: Variant in u:
		if not f.has(k):
			return false
	return true

## u08 回修（20260917）：join/final 超出 block_size 域的格数 N——contract_hint 超域分支与编辑器
## 尺寸应用执行尾的 toast 知情提示（editor_main.gd _execute_size_apply）共用同一计数，避免逻辑双写。
## 批次 U（U12④）：扫描集扩展为四标签（blocks/target/join/final）——blocks/target 超域一并计入。
## 批次 V（V-E1，规格 §9.1）：计数改 per-domain——各格集按「所属域自身尺寸」计越界：
## blocks/bs、target/target_size（回落时即 block_size）、join/join_part.size、final/final_answer.size。
## 语义收益：本计数=「游戏加载时将被裁剪的格数」的精确预言（游戏侧按域净化后逐域裁剪，§9.5），
## 旧口径（全按 block_size）在 join/final/target 域尺寸大于 block_size 时会虚报。
func count_over_domain_cells() -> int:
	var over: int = 0
	# 批次 U（U12④，spec §4-U12-④）：扫描集 [JOIN,FINAL] → [BLOCKS,TARGET,JOIN,FINAL]——
	# contract_hint 超域提示与尺寸应用尾 toast 共用本计数（既有注释口径）同步生效。
	# 批次 V（V-E1）：每格集配对其所属域尺寸（get_size_for_tag 分流读，per-domain）。
	for which: int in [TAG_BLOCKS, TAG_TARGET, TAG_JOIN, TAG_FINAL]:
		var src := get_voxel_set(which)
		var dom := get_size_for_tag(which)
		over += src.size() - clip_out_of_bounds(src, dom).size()
	return over

# ---------- 试玩快照（规格 §8.1：进入试玩对元数据做内存深拷贝；T3-2 增补） ----------
func snapshot_data() -> Dictionary:
	return _data.duplicate(true)

func restore_data(d: Dictionary) -> void:
	_data = d

## 整值 float → int 的就地深归一化（数组/字典递归；非整值 float、bool、String 原样保留）。
## 上限 2^53：超过后 float 本就无法精确表整，还原反而失真，故跳过。
static func _normalize_json_ints(v: Variant) -> void:
	if v is Array:
		var arr: Array = v
		for i: int in range(arr.size()):
			var e: Variant = arr[i]
			if e is float:
				var f: float = e
				if f == floorf(f) and absf(f) <= 9007199254740992.0:
					arr[i] = int(f)
			elif e is Array or e is Dictionary:
				_normalize_json_ints(e)
	elif v is Dictionary:
		var d: Dictionary = v
		for k: Variant in d:
			var e: Variant = d[k]
			if e is float:
				var f: float = e
				if f == floorf(f) and absf(f) <= 9007199254740992.0:
					d[k] = int(f)
			elif e is Array or e is Dictionary:
				_normalize_json_ints(e)
