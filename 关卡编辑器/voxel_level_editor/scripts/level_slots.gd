class_name LevelSlots
extends RefCounted
## 槽位纯逻辑类（规格 §3.3）：固定 5 槽目录 + 续接元数据 + 首启初始化 + README 落盘。
## 零场景依赖零 autoload 依赖（对齐 level_project.gd 纯逻辑层惯例），可无头单测。
## 双路径策略（§3.3-3）：slots_root() 开发态=globalize_path("res://levels/")、导出态=exe 旁；
## 写探针兜底：主路径建目录失败回退另一路径一次，两路皆败返回 ""（调用方状态栏提示）。
## 所有静态方法带可选 root 参数（""=slots_root()），测试经参数注入沙盒（规格 §6.1，P7 裁决）。
## 预填只读承诺（§3.3-5/§九 R5）：source 仅 FileAccess.get_file_as_string 读入，永不获取写句柄；
## 初始化成功后运行期不再读游戏侧任何路径。
## 批次 V（V-E2，规格 §9.3）：每关拆分文件制——level_N/ = level.json（顶层元数据，无 pieces）
## + blocks.json + target.json + join.json + final.json（四域各自独立原子写）；旧单文件档在
## load_slot_text 载入时自动迁移（四域先写 → 旧档改名 level_legacy.json.bak 留档 → 元数据落盘，
## 任一步失败旧档原样保留）；session_meta.json 位置与语义不变；level_project.gd 数据模型零改动。
## 批次 W（W5，20260920）：①N16 去导出化（拍板 9）——导出契约 JSON 链路整体退役（export_contract_text/
## last_export_error/EXPORT_NAME/README 第 7 条全删；编辑器产出=五件套实时自动保存，保留不变）；
## ②P1-9（拍板 6）slots_root 三级解析：开发态 res://levels/（不变）→ 导出态 exe 同级可写
## （mkdir+写探针文件验证真实可写，甄别「目录在场但只读」安装态）→ 皆败回退 user://levels/；
## ③P2-4a _default_source 逐级上溯健壮解析 + 落空显式提示（last_prefill_note，不静默降级）；
## ④P3-4c session_meta.json 原子写（tmp+rename，对齐关卡 JSON 同款序）。

const LP := preload("res://scripts/level_project.gd")

const SLOT_MIN := 1
const SLOT_MAX := 5
const CN_NUMS: Array[String] = ["一", "二", "三", "四", "五"]
const README_NAME := "README_请勿接入主游戏.md"
const META_NAME := "session_meta.json"

# ---------- 批次 V（V-E2，规格 §9.3）拆分文件目录契约 ----------
## level_N/ 五文件：level.json=顶层元数据（format_version/level_id/chapter/title/era/theme/
## description/anim_time + 其余顶层未列键（如 grid_size_unused）原样透传，无 pieces 键）；
## blocks.json=pieces[0] 除四域专属键外的全部键（piece_id/name/block_size/blocks/initial_voxels/
## match_offset/未知透传键——piece 级键集守恒，迁移往返零 diff 的基础）；target.json=
## target_shapes（+target_size 仅当源有该键，键缺不落键——E1 口径沿用）；join.json=join_part
## 内容；final.json=final_answer 内容。
const FILE_LEVEL := "level.json"
const FILE_BLOCKS := "blocks.json"
const FILE_TARGET := "target.json"
const FILE_JOIN := "join.json"
const FILE_FINAL := "final.json"
## 四域拆分文件名（存在性=「拆分态」判据；level.json 不在其列——单靠元数据不算拆分态）。
const SPLIT_FILES: Array[String] = [FILE_BLOCKS, FILE_TARGET, FILE_JOIN, FILE_FINAL]
## 常规保存写序（规格 §9.3）：level→blocks→target→join→final（level.json 元数据先行）。
const _SAVE_ORDER: Array[String] = [FILE_LEVEL, FILE_BLOCKS, FILE_TARGET, FILE_JOIN, FILE_FINAL]
## 迁移留档名（旧单文件改名归档；与 _atomic_write_text 的 per-file .bak 名 <file>.bak 刻意区分，
## 防止元数据覆写兜底序的瞬态 level.json.bak 与留档混淆/互踩——任务拍板名，规格 §9.3 的
## level.json.bak 会与该兜底名冲突，故取专名）。
const LEGACY_BAK_NAME := "level_legacy.json.bak"
## blocks.json 缺失且无旧档可补时的宽容缺省（1×1×1 空集，load_from_text 侧 block_size 校验通过）。
static func _default_blocks_doc() -> Dictionary:
	return {"block_size": {"x": 1, "y": 1, "z": 1}, "blocks": []}

## 最近一次写盘失败的文件绝对路径（""=无）。调用方（editor_main _autosave_current）据此
## 状态栏「报具体文件」（任务口径：任一失败中止并报具体文件）；每次 save/迁移入口清零。
static var last_error_file: String = ""

## 批次 W（W5，P2-4a）：最近一次「预填源不可用→空骨架降级」的显式提示文案（""=无）——
## 解析/读取失败不得静默降级；editor_main._ready 据此状态栏提示。ensure_initialized 入口清零。
static var last_prefill_note: String = ""
const NOTE_SOURCE_MISSING := "内置示例不可用（未找到第 1 关模板），已用空骨架"

## D7 注释文件全文（规格 §3.7 草案逐字；随首启初始化写入并随仓提交）。
## 批次 V（V-E2）：第 2 条同步拆分文件制与迁移语义（与 levels/README_请勿接入主游戏.md 同文）。
const README_TEXT := """# ⚠ 请勿接入主游戏（写给主游戏 agent 的目录说明）

本目录（关卡编辑器/voxel_level_editor/levels/）是关卡编辑器的槽位工作区，
**不是**主游戏的关卡数据源。

1. 主游戏关卡装载（LevelLibrary 扫描 游戏项目/千年一榫/levels_data/）**不得扫描、
   复制或消费本目录任何文件**——本目录文件名（level_N/*）不符合接口规范 §1
   交付命名约定（level_chapter{N}_{关卡名}.json），亦未经过接入验收。
2. 目录结构（批次 V 拆分文件制，规格 §9.3）：level_1/ ~ level_5/ 各为一个关卡工作目录——
   level.json=顶层元数据（format_version/chapter/title/era/theme/description/anim_time 等，
   无 pieces 键）、blocks.json=初始木块域、target.json=标准答案域、join.json=对接固定件域、
   final.json=最终成品域（内容为 format_version=1 契约格式的分域数据，但属暂存态）；
   批次 V 之前的旧单文件档在编辑器首次载入时自动迁移为五文件，旧档改名
   level_legacy.json.bak 留档（迁移原子：任一步失败旧档原样保留，下次载入重迁移）；
   session_meta.json 是编辑器续接进度（last_slot），与游戏无关；本 README 由编辑器首启自动写入。
3. 本目录内容会被编辑器**每次编辑操作实时覆盖**（自动保存），不是稳定数据。
4. 编辑器关卡正式接入主游戏**尚未开放**（批次 W 拍板 9/N16：主游戏与编辑器完全解耦，
   「编辑器关卡搭桥导入主游戏」留待未来独立批次实施；批次 V 的「导出契约 JSON」链路已随
   N16 退役删除）。在用户明确下达接入指示前，请勿自动执行任何接入动作，
   也请勿把本目录任何文件拷入主游戏。
5. 编辑器工程与游戏工程仅共享 JSON 契约（技术文档/接口规范_关卡数据.md），
   互不 import、互不读写对方工程文件。
6. 关卡命名与章号遮蔽风险（批次 U U12⑦）：官名建议 ≤16 字（批次 U U11：主游戏 TopBar
   标题 TRIM_ELLIPSIS 省略号截断为纵深防御，过长仍损观感）。**遮蔽风险**——五槽 chapter
   强制=槽位号（`scripts/level_slots.gd` `apply_auto_meta`），与 `游戏项目/千年一榫/levels_data/`
   同章号关卡在游戏侧 `level_library.gd get_level` 按 chapter 首个命中——正式关卡勿占用
   1~5 章号，或先行合入 levels_data。
   （退役留痕，批次 W N16：原第 7 条「导出主游戏契约 JSON」描述随导出链路退役删除。）

（批次 Z 留痕）level_1 已于批次 Z（2026-09-24）经用户明示一次性人工导入主游戏
`levels_data/level_chapter1_hemudu.json`；本目录仍不构成实时联动，后续改动仍须人工再导。
（批次 AB-1 留痕）level_2~5 五件套已于批次 AB-1（2026-09-26，用户明示）经人工一次性导入主游戏
`levels_data/level_chapter2_song.json`~`level_chapter5_modern.json`（替换原 AI 占位关）；本目录仍不构成实时联动。
"""

# ---------- 槽位根（三级解析 + 写探针，规格 §3.3-3 + 批次 W P1-9 拍板 6） ----------
## 生效槽位根（以 "/" 结尾）；诸候选皆败返回 ""。
## 批次 W（W5，P1-9 拍板 6）三级解析：开发态 res://levels/（不变）→ 导出态 exe 同级可写
## （便携优先）→ 皆败回退 _user_levels_root()（OS.get_user_data_dir()/levels/，用户可写目录）。
## 写探针：工程内 levels/ 为开发态受信路径（目录在场即可用）；其余候选一律 mkdir + 写探针
## 文件 + 即清——甄别「目录已存在但只读」（Program Files 安装态旧二态探针的甄别盲区）。
## 审查②遗留③（沿用）：环境变量 VOXEL_EDITOR_SLOTS_ROOT（spec §3.4-7 规定名）非空且 editor 态
## → 直接作为槽位根返回（尾 "/" 归一，不探针不建目录——编排层测试注入沙盒）；release 导出态
## 不读 env（防用户 shell 残留变量静默改槽位根）。
## 测试缝：_candidates_for/_resolve_from_candidates/_probe_root/user 根派生均为静态纯函数
## （test_w_editor W1 段注入直测，user 候选零 IO）。
static func slots_root() -> String:
	var env := OS.get_environment("VOXEL_EDITOR_SLOTS_ROOT")
	if not env.is_empty() and OS.has_feature("editor"):
		return env if env.ends_with("/") else env + "/"
	return _resolve_from_candidates(_candidate_roots())

## 候选根表：exported=true=导出态（exe 同级便携优先 → user 目录回退，2 级）；
## false=开发态（工程内 levels/ → exe 同级 → user 目录回退，3 级——dev 首位恒不变）。
static func _candidates_for(exported: bool) -> Array:
	var dev := ProjectSettings.globalize_path("res://levels/")
	var exe := OS.get_executable_path().get_base_dir().path_join("levels/")
	var user := _user_levels_root()
	if exported:
		return [exe, user]
	return [dev, exe, user]

static func _candidate_roots() -> Array:
	return _candidates_for(not OS.has_feature("editor"))

## 用户可写回退根（纯派生零 IO；P1-9 拍板 6「只读回退用户目录」）。
static func _user_levels_root() -> String:
	return OS.get_user_data_dir().path_join("levels/")

## 逐候选探针解析：首个探针通过者即生效根；皆败返回 ""。
## 工程内 levels/（开发态首位）仅做在场判定，其余候选写探针验证真实可写性。
static func _resolve_from_candidates(candidates: Array) -> String:
	var dev := ProjectSettings.globalize_path("res://levels/")
	for candidate: Variant in candidates:
		var c := str(candidate)
		if _probe_root(c, c != dev):
			return c
	return ""

## 探针：目录不在场先建（建失败=不可用）；write_probe=true 再写探针文件并即清
## （FileAccess 写失败=该路径实际只读）。探针文件名 .slots_probe，用后即清（残留无害）。
static func _probe_root(path: String, write_probe: bool = false) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		if DirAccess.make_dir_recursive_absolute(path) != OK:
			return false
	if not write_probe:
		return true
	var probe := path.path_join(".slots_probe")
	if not _write_text(probe, "probe"):
		return false
	DirAccess.remove_absolute(probe)
	return true

# ---------- 首启初始化 / 补齐（规格 §3.3-4 六步 + P2-7 重初始化判定） ----------
## root=""→slots_root()；source=""→默认游戏侧源（P3 裁决：§3.3-4「source 默认…」明文）。
## 重初始化判定（P2-7）：levels/ 目录缺失或五槽全缺 → 全量初始化
## （②建五目录 ③level_1 从 source 预填 ④level_2..5 空骨架 ⑤save_meta(1) ⑥写 README，
## level_1 预填恢复即「全删=显式重置」语义，游戏侧唯一合法回读场景）；
## 仅部分槽缺失 → 仅补齐缺失槽（空骨架，不回读游戏侧，N==1 亦空骨架）。
## 已初始化（五槽全在）→ 直接返回，以 levels/ 为准零触碰（S3 幂等）。
## 建目录/写盘失败返回 ""（调用方状态栏提示）。
## 批次 V（V-E2）：槽「在盘」判定=level.json 或任一域拆分文件存在（_slot_has_data）——
## 拆分态下仅删 level.json（元数据）不触发骨架重写，防拆分数据被覆盖丢档。
static func ensure_initialized(root: String = "", source: String = "") -> String:
	last_prefill_note = ""   # 批次 W P2-4a：每次初始化入口清零（不残留上次提示）
	var r := _resolve_root(root)
	if r.is_empty():
		return ""
	var src := source
	if src.is_empty():
		src = _default_source()
	var missing: Array[int] = []
	for n: int in range(SLOT_MIN, SLOT_MAX + 1):
		if not _slot_has_data(r, n):
			missing.append(n)
	if missing.is_empty():
		return r   # 已初始化：以 levels/ 为准，零触碰零回读
	var full := missing.size() == SLOT_MAX - SLOT_MIN + 1
	for n: int in missing:
		if DirAccess.make_dir_recursive_absolute(r + _slot_dir(n)) != OK:
			return ""
	if full:
		if not _prefill_slot(r, SLOT_MIN, src):
			return ""
		for n: int in range(2, SLOT_MAX + 1):
			if not _write_skeleton(r, n):
				return ""
		if not save_meta(SLOT_MIN, r):
			return ""
		if not _write_text(r + README_NAME, README_TEXT):
			return ""
	else:
		for n: int in missing:
			if not _write_skeleton(r, n):
				return ""
	return r

## 槽位在盘判定（批次 V §9.3 拆分态口径）：level.json 或任一域拆分文件存在即视为已初始化。
static func _slot_has_data(r: String, slot: int) -> bool:
	if FileAccess.file_exists(r + _slot_json(slot)):
		return true
	for name: String in SPLIT_FILES:
		if FileAccess.file_exists(r + _slot_file(slot, name)):
			return true
	return false

static func _resolve_root(root: String) -> String:
	var r := root
	if r.is_empty():
		r = slots_root()
	if r.is_empty():
		return ""
	if not r.ends_with("/"):
		r += "/"
	return r

## 默认预填源（批次 W W5，P2-4a 健壮解析）：自 res:// 工程根逐级上溯（最多 6 级）探测
## 游戏侧第 1 关模板，返回首个命中的规范绝对路径（无 .. 透传）；全部落空返回 ""（调用方
## 空骨架降级，并经 last_prefill_note 显式提示——**不得静默**）。旧 ../../ 相对拼接退役
## （导出态 globalize 后必落空且路径含 .. 不规范）。env 注入缝 VOXEL_EDITOR_DEFAULT_SOURCE
## （editor 态消费，对齐 VOXEL_EDITOR_SLOTS_ROOT 先例；供导出态模拟/编排层测试注入）。
static func _default_source() -> String:
	var env := OS.get_environment("VOXEL_EDITOR_DEFAULT_SOURCE")
	if not env.is_empty() and OS.has_feature("editor"):
		return env
	return _default_source_from(ProjectSettings.globalize_path("res://"))

## 自 base_dir 逐级上溯探测默认源（纯函数可注入直测，test_w_editor W2c 导出态落空模拟）。
## 命中判据=<base>/游戏项目/千年一榫/levels_data/level_chapter1_hemudu.json 存在。
static func _default_source_from(base_dir: String) -> String:
	var probe_rel := "游戏项目/千年一榫/levels_data/level_chapter1_hemudu.json"
	var d := base_dir.trim_suffix("/")
	for i: int in range(6):
		var candidate := d.path_join(probe_rel)
		if FileAccess.file_exists(candidate):
			return candidate
		var parent := d.get_base_dir()
		if parent == d or parent.length() < 4 or parent.ends_with(":"):
			break   # 到达盘根/无法再上溯
		d = parent
	return ""

static func _slot_dir(slot: int) -> String:
	return "level_%d/" % clampi(slot, SLOT_MIN, SLOT_MAX)

static func _slot_json(slot: int) -> String:
	return _slot_dir(slot) + FILE_LEVEL

## 槽内文件路径派生（level_N/<file_name>；root 归一由调用方 _resolve_root 保证）。
static func _slot_file(slot: int, file_name: String) -> String:
	return _slot_dir(slot) + file_name

## ③ level_1 预填：source 读入（只读）→ load_from_text → apply_auto_meta → 拆分落盘。
## 源缺失/坏档 → 降级空骨架（S7，spec §九 R5），初始化整体不失败；批次 W P2-4a：降级
## 非静默——置 last_prefill_note 显式提示（src="" 与坏路径同判 text.is_empty()）。
static func _prefill_slot(r: String, slot: int, src: String) -> bool:
	var text := ""
	if not src.is_empty():
		text = FileAccess.get_file_as_string(src)
	var p := LP.new()
	if text.is_empty() or not p.load_from_text(text):
		last_prefill_note = NOTE_SOURCE_MISSING
		return _write_skeleton(r, slot)   # 降级：空骨架
	apply_auto_meta(p, slot)
	return save_slot_text(slot, p.save_to_text(), r)

## ④ 空骨架（spec §3.3-4 拍板①）：new_project(3³) + apply_auto_meta 拆分落盘五文件——
## block_size 3³、blocks 27 格实心、target_shapes=[[]]、join_part/final_answer 空集、
## era=""/description=""、theme="wood"、name="主体"（空补）、piece_id="p1"。
static func _write_skeleton(r: String, slot: int) -> bool:
	var p := LP.new()
	p.new_project(Vector3i(3, 3, 3))
	apply_auto_meta(p, slot)
	return save_slot_text(slot, p.save_to_text(), r)

# ---------- 单槽读写（规格 §3.3-4 API 表 + 批次 V §9.3 拆分/迁移） ----------
## 读槽（规格 §9.3 载入判据三序，P1-3 审查修订版）：
## ①任一域拆分文件存在 → **以拆分为准**内存拼装为完整契约文档文本返回；拆分不全且旧
##   level.json 仍含 pieces 数据 → 以旧文件补齐缺失域（level_legacy.json.bak 不参与读）；
##   缺失域且无旧档可补 → 宽容补建（blocks=1×1×1 空集、target/join/final=空域，
##   level_project 读路径 _ensure 宽容语义兜底）。
## ②全无拆分文件且旧 level.json 存在 → 自动迁移：load_from_text 载入 → save_to_text 规范化
##   （整值 float 还原 int、join/final size 缺失补齐——E1 既有保存语义；target_size 键缺不落键
##   随之保留）→ **写序=先写四域拆分文件 → 旧单文件改名 level_legacy.json.bak 留档 → 最后写
##   level.json 元数据**（终态与规格 §9.3「写元数据成功后立即改名」一致；物理序取「改名先于
##   覆写」——元数据覆写后旧单文件已不存在、无从改名，且此序保证任一步失败旧档原样保留，
##   杜绝「元数据已覆写、留档未落」丢档窗口，P1-3 迁移原子性口径）。任一步失败返回原文本
##   （旧档未动，下次载入可重迁移）；成功返回规范化完整文本。
## ③皆无 → 返回 ""（调用方空骨架降级，现状语义）。
## 多 piece 旧档：pieces[0] 拆四域，pieces[1..] 以 pieces_tail 键随 level.json 元数据透传留档
## （装配时回拼——G9 双 piece 提示语义，spec §3.6-2；编辑器语义只编辑 pieces[0]，spec §3.2）。
static func load_slot_text(slot: int, root: String = "") -> String:
	var r := _resolve_root(root)
	if r.is_empty():
		return ""
	var dir := r + _slot_dir(slot)
	var level_path := dir + FILE_LEVEL
	var has_split := false
	for name: String in SPLIT_FILES:
		if FileAccess.file_exists(dir + name):
			has_split = true
			break
	if has_split:
		return _assemble_slot_text(dir, _gap_piece_of(level_path))
	if FileAccess.file_exists(level_path):
		var text := _read_text(level_path)
		var migrated := _try_migrate(slot, r, text)
		if not migrated.is_empty():
			return migrated
		return text
	return ""

## 旧档补齐源：level.json 可解析且含完整 pieces 结构 → 返回 pieces[0]；否则空 dict（无补齐源）。
static func _gap_piece_of(level_path: String) -> Dictionary:
	var old_doc: Variant = _read_json(level_path)
	if not (old_doc is Dictionary) or not _is_full_contract_doc(old_doc as Dictionary):
		return {}
	var gp: Variant = ((old_doc as Dictionary)["pieces"] as Array)[0]
	if gp is Dictionary:
		return gp
	return {}

## 迁移（判据②）：成功返回规范化完整文本；任一步失败返回 ""（调用方回退原文本）。
static func _try_migrate(slot: int, r: String, old_text: String) -> String:
	var p := LP.new()
	if not p.load_from_text(old_text):
		return ""   # 坏档：迁移中止（旧档原样保留；调用方 load_from_text 再拒 → STATUS_SLOT_LOAD_FAIL）
	var doc_v: Variant = JSON.parse_string(p.save_to_text())
	if not (doc_v is Dictionary) or not _is_full_contract_doc(doc_v as Dictionary):
		return ""
	var parts: Array = _split_doc(doc_v as Dictionary)
	var dir := r + _slot_dir(slot)
	last_error_file = ""
	for i: int in range(SPLIT_FILES.size()):
		var path := dir + SPLIT_FILES[i]
		if not _atomic_write_text(path, JSON.stringify(parts[i + 1], "  ", false) + "\n"):
			last_error_file = path
			return ""   # 四域写失败中止：旧单文件原样保留（已写域留给判据①补齐/续存收敛）
	var bak := dir + LEGACY_BAK_NAME
	if FileAccess.file_exists(bak) and DirAccess.remove_absolute(bak) != OK:
		return ""   # 旧留档无法腾位（重迁移场景）：中止，旧档原样保留
	if DirAccess.rename_absolute(r + _slot_json(slot), bak) != OK:
		return ""   # 留档失败：中止，旧档原样保留（四域已写，下次载入判据①拼装零丢失）
	if not _atomic_write_text(r + _slot_json(slot), JSON.stringify(parts[0], "  ", false) + "\n"):
		last_error_file = r + _slot_json(slot)
		DirAccess.rename_absolute(bak, r + _slot_json(slot))   # 回滚留档：旧单文件原样保留
		return ""
	return p.save_to_text()

## 完整契约文档判定：pieces 为非空数组且首项为对象（与 load_from_text 结构门同口径）。
static func _is_full_contract_doc(doc: Dictionary) -> bool:
	var pieces: Variant = doc.get("pieces", null)
	return pieces is Array and not (pieces as Array).is_empty() and (pieces as Array)[0] is Dictionary

## 写槽（批次 V §9.3）：text=完整契约文档 → 拆分五文件依序 level→blocks→target→join→final
## 逐文件原子写（_atomic_write_text：tmp+rename+.bak 兜底序）；任一失败即中止返回 false
## （last_error_file=失败文件路径；已写成功的文件保留最新内容，载入侧判据①宽容拼装）。
## 非完整契约文档（坏 JSON/缺 pieces）→ 拆分前旧单文件语义兼容写：原样落 level.json 并清除
## 四域拆分文件（避免旧拆分内容遮蔽本次写入语义；test_sanity G22③ 坏档注入/G23⑧ 单文件
## 往返对账）。
static func save_slot_text(slot: int, text: String, root: String = "") -> bool:
	var r := _resolve_root(root)
	if r.is_empty():
		return false
	last_error_file = ""
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary and _is_full_contract_doc(parsed as Dictionary):
		return _save_doc_split(slot, parsed as Dictionary, r)
	_remove_split_files(r, slot)
	if not _atomic_write_text(r + _slot_json(slot), text):
		last_error_file = r + _slot_json(slot)
		return false
	return true

## 五文件拆分写（_SAVE_ORDER 序；parts=[meta,blocks,target,join,final] 与序一一对应）。
static func _save_doc_split(slot: int, doc: Dictionary, r: String) -> bool:
	var parts: Array = _split_doc(doc)
	last_error_file = ""
	for i: int in range(_SAVE_ORDER.size()):
		var path := r + _slot_file(slot, _SAVE_ORDER[i])
		if not _atomic_write_text(path, JSON.stringify(parts[i], "  ", false) + "\n"):
			last_error_file = path
			return false
	return true

## 拆分：完整契约文档 → [meta, blocks, target, join, final] 五份子文档。
## 键序=原文档出现序（装配定点性质：split(assemble(split(D)))==split(D)，load→save 字节稳定）。
## 多 piece 保留（G9 双 piece 提示语义，spec §3.6-2）：pieces[1..] 非空时以 pieces_tail 键随
## level.json 透传留档（装配时回拼 pieces=[piece0]+tail）——单 piece 档不产生该键，
## level.json 仍无 pieces 键（任务断言①口径）。
static func _split_doc(doc: Dictionary) -> Array:
	var piece: Dictionary = {}
	var p0: Variant = (doc["pieces"] as Array)[0]
	if p0 is Dictionary:
		piece = p0
	var meta: Dictionary = {}
	for k: Variant in doc:
		if str(k) != "pieces":
			meta[k] = doc[k]
	var tail: Array = (doc["pieces"] as Array).slice(1)
	if not tail.is_empty():
		meta["pieces_tail"] = tail
	var domain_parts: Array = _split_piece(piece)
	var parts: Array = [meta, domain_parts[0], domain_parts[1], domain_parts[2], domain_parts[3]]
	# 批次 Y6（Y-D1，spec §9.4）：拆分件整值规范化——save_to_text 虽经 _normalize_json_ints 还原
	# int，但 save_slot_text 的 parse→stringify 往返会把一切数值再次回析为 float（4.7 实证），
	# 拆分件若不在此归一，五件套整值语义字段（chapter/format_version/各尺寸等）恒以 x.0 落盘。
	# 逐件深归一（LP._normalize_json_ints 同源口径，幂等不重排键序）后由调用方 stringify——
	# 迁移写盘（_try_migrate）与常规五件套写盘（_save_doc_split）两处调用点一并覆盖，
	# 规范形态（整值 int）成为「装配定点性质：split(assemble(split(D)))==split(D)」的稳定不动点。
	for part: Variant in parts:
		LP._normalize_json_ints(part)
	return parts

## piece → [blocks, target, join, final] 四域子文档：
## blocks.json 承接 piece 除四域专属键外的全部键（键序保留）；target.json 承接
## target_shapes/target_size（仅当源有该键——键缺不落键）；join/final 承接同名对象内容
## （对象缺/非 dict → 空文档）。空文档域在装配时不回填键（「缺键」状态守恒）。
static func _split_piece(piece: Dictionary) -> Array:
	var blocks_doc: Dictionary = {}
	var target_doc: Dictionary = {}
	for k: Variant in piece:
		var key := str(k)
		if key == "join_part" or key == "final_answer":
			continue
		if key == "target_size" or key == "target_shapes":
			target_doc[key] = piece[k]
		else:
			blocks_doc[key] = piece[k]
	var join_v: Variant = piece.get("join_part", null)
	var final_v: Variant = piece.get("final_answer", null)
	var join_doc: Dictionary = {}
	if join_v is Dictionary:
		join_doc = join_v
	var final_doc: Dictionary = {}
	if final_v is Dictionary:
		final_doc = final_v
	return [blocks_doc, target_doc, join_doc, final_doc]

## 装配：元数据 + 四域子文档 → 完整契约文档（pieces[0] 四数组+尺寸形态；
## level_project 数据模型零改动——装配结果即 load_from_text 的合法输入）。
## pieces_tail（多 piece 透传留档，见 _split_doc）回拼 pieces 尾部后从元数据中摘除。
## join/final 空文档不回填键（与「缺键」状态守恒；target 键缺不落键同口径）。
static func _assemble_doc(meta: Dictionary, blocks_doc: Dictionary, target_doc: Dictionary,
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

## 判据①拼装：逐域读文件（缺失/坏档 → 旧档补齐 → 宽容缺省），序列化为完整契约文本。
## level.json 缺失/坏档 → 最小元数据 {"format_version":1}（chapter/title/level_id 由编辑器
## apply_auto_meta 载入后自动补齐，spec §3.5-1）。
static func _assemble_slot_text(dir: String, gap_piece: Dictionary) -> String:
	var meta: Dictionary = {}
	var meta_v: Variant = _read_json(dir + FILE_LEVEL)
	if meta_v is Dictionary:
		meta = meta_v
	else:
		meta = {"format_version": LP.FORMAT_VERSION}
	var gap: Array = _split_piece(gap_piece) if not gap_piece.is_empty() else [{}, {}, {}, {}]
	var parts: Array = []
	var idx := 0
	for name: String in SPLIT_FILES:
		var v: Variant = _read_json(dir + name)
		if v is Dictionary:
			parts.append(v)                                   # 以拆分为准
		elif not gap_piece.is_empty():
			parts.append(gap[idx])                            # 旧文件补齐缺失域
		elif idx == 0:
			parts.append(_default_blocks_doc())               # 宽容缺省：blocks=1×1×1 空集
		elif idx == 1:
			parts.append({"target_shapes": [[]]})             # 宽容缺省：target 空形状（target_size 键缺不落键）
		else:
			parts.append({})                                  # 宽容缺省：join/final=空域（save 侧 _ensure 补齐收敛）
		idx += 1
	var doc := _assemble_doc(meta, parts[0], parts[1], parts[2], parts[3])
	return JSON.stringify(doc, "  ", false) + "\n"

## 清除四域拆分文件（旧单文件语义兼容写的伴随动作；文件不存在时静默跳过）。
static func _remove_split_files(r: String, slot: int) -> void:
	for name: String in SPLIT_FILES:
		var path := r + _slot_file(slot, name)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

# ---------- 批次 W（W5，N16 拍板 9）导出契约 JSON 链路退役留痕 ----------
## 原「导出主游戏契约 JSON」整段（EXPORT_NAME 常量 / last_export_error 静态变量 /
## export_contract_text 生成函数，批次 V V-E3 版本落盘 level_N/level_export.json）随
## 用户拍板 9「删按钮+停生成」整体退役删除（接口规范 §8.6 退役由主会话统一改稿）。
## 编辑器产出=五件套实时自动保存（上方 save_slot_text/_save_doc_split），保留不变。

# ---------- 续接元数据（session_meta.json，规格 §3.3-2/§3.4-5） ----------
## {"last_slot": int}；缺失/坏 JSON/越界 → 缺省 {"last_slot": 1}。
static func load_meta(root: String = "") -> Dictionary:
	var r := _resolve_root(root)
	if not r.is_empty():
		var f := FileAccess.open(r + META_NAME, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				var n := int((parsed as Dictionary).get("last_slot", SLOT_MIN))
				if n >= SLOT_MIN and n <= SLOT_MAX:
					return {"last_slot": n}
	return {"last_slot": SLOT_MIN}

static func save_meta(last_slot: int, root: String = "") -> bool:
	var r := _resolve_root(root)
	if r.is_empty():
		return false
	# 批次 W（W5，P3-4c）：直写改原子写（tmp+rename+兜底序，对齐关卡 JSON 同款序）——
	# 根除「session_meta.json 非原子直写，坏档续接回退首槽」：失败路径旧档逐字节保留。
	return _atomic_write_text(r + META_NAME,
		JSON.stringify({"last_slot": clampi(last_slot, SLOT_MIN, SLOT_MAX)}))

# ---------- 自动元数据（规格 §3.5-1 规则表，单点实现；初始化与每次槽位加载后调用） ----------
## 强制写：chapter=槽位号（夹紧 1~5）/title=第N关（中文数字一~五）/level_id=chapter{N}_editor；
## 空补：pieces[0].name（空→「主体」）、piece_id（缺失→"p1"）；不动：era/theme/description。
static func apply_auto_meta(p: RefCounted, slot: int) -> void:
	var n := clampi(slot, SLOT_MIN, SLOT_MAX)
	p.set_field("chapter", n)
	p.set_field("title", "第%s关" % CN_NUMS[n - 1])
	p.set_field("level_id", "chapter%d_editor" % n)
	var piece: Dictionary = p.get_piece()
	if piece.is_empty():
		return
	if str(piece.get("name", "")) == "":
		piece["name"] = "主体"
	if not piece.has("piece_id"):
		piece["piece_id"] = "p1"

# ---------- 内部写盘 ----------
## 单文件原子写（原 save_slot_text 序泛化，规格 §9.3 逐文件原子）：tmp+rename；rename 失败走
## 「旧文件先改名 .bak 腾位 → rename tmp → 成功后清 .bak」兜底序（审查②遗留②：消除
## 「remove 成功后 rename 失败」丢档窗口，.bak 序失败时可回滚，任何分支不留半截内容）。
## 目标被同名目录占位（P2-4 写失败注入场景）→ 确定性 false。
static func _atomic_write_text(path: String, text: String) -> bool:
	if DirAccess.dir_exists_absolute(path):
		return false   # 目标被同名目录占位 → 明确错误态
	var tmp := path + ".tmp"
	if not _write_text(tmp, text):
		return false
	if DirAccess.rename_absolute(tmp, path) != OK:
		var bak := path + ".bak"
		if FileAccess.file_exists(bak) and DirAccess.remove_absolute(bak) != OK:
			DirAccess.remove_absolute(tmp)   # 残留 .bak 无法清 → 放弃本次写（旧档未动）
			return false
		if DirAccess.rename_absolute(path, bak) != OK:
			DirAccess.remove_absolute(tmp)
			return false
		if DirAccess.rename_absolute(tmp, path) != OK:
			# W9-4（批次 AA 规格 §12 P3-5，主游戏 save_game 同构同修）：回滚 rename 返回值必判——
			# 回滚也失败时 path 与 .bak 双双不在原位，此时**保留 tmp 不删**（唯一完好副本）+
			# push_warning 留痕，绝不静默吞；只有回滚成功才清 tmp（既有「不留半截」语义保持）。
			if DirAccess.rename_absolute(bak, path) != OK:
				push_warning("关卡槽位写入失败（tmp 换名失败且回滚 .bak 失败，已保留 tmp 副本待人工处理）")
				return false
			DirAccess.remove_absolute(tmp)   # 回滚成功 → 清 tmp（旧档已回位）
			return false
		DirAccess.remove_absolute(bak)   # .bak 处理后清理（best-effort）
	return true

static func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t

## 防御解析（spec §14 坑 2）：文件缺失/不可读/坏 JSON 一律返回 null，调用方 is Dictionary 判型。
static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(_read_text(path))

static func _write_text(path: String, text: String) -> bool:
	## 批次 W（P3-5a，规格 §7）：错误读取移到 close() 之后——旧序在缓冲写盘前取 err 恒 OK，
	## 缓冲/落盘阶段失败不可见；与 G/save_manager._write_text_flushed 同构同修。
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return f.get_error() == OK
