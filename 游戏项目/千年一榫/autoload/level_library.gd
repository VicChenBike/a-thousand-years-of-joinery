extends Node
## LevelLibrary：levels_data 扫描/校验/章节列表/资产映射。依据 spec 7.6 + 接口规范。

signal scan_finished(loaded_count: int, failed_count: int)

const ERA_MODEL := {1: "石器", 2: "宋", 3: "元", 4: "明", 5: "现代"}

## 玩家自定义关卡目录（批次 AB-4「搭桥」起为**可写 user://** 口径）。
## 口径变更理由（AB-4 拍板，见接口规范 §13②）：AB 批之前该常量指 `res://levels_data/user_levels`
## （只读预留、目录从未落地、零消费方）；打包态下 `res://` 是只读 PCK，玩家自制关卡**不可能**写入
## 工程目录 → 玩家可写档必须落 `user://`。现口径与游戏存档（`user://save.json`）同根，导出预设
## （export_presets.cfg `include_filter`）**无需任何追加**（该处只排除 *.md/*.gd 等源文件，不排除
## user:// 路径——user:// 本就不进包）。旧值以 `_LEGACY` 常量留档，不再被任何代码消费。
const USER_LEVEL_DIR := "user://user_levels"
## 历史预留值（AB-4 前的 res:// 口径）——仅留档防考古误用，代码不消费。
const USER_LEVEL_DIR_LEGACY := "res://levels_data/user_levels"

var _levels: Array[Dictionary] = []
var _user_levels: Array[Dictionary] = []
var _errors: Dictionary = {}
## 用户关卡坏档留痕（键=level_id，缺 id 回落文件名）。**与 _errors 分表**：_errors 属内置进度域
## （get_error(chapter) 有既有语义，不得混入用户档原因）；_user_errors 供未来 UI 显示原因。
var _user_errors: Dictionary = {}

func scan_directory(dir: String = "res://levels_data") -> void:
	## 既有对外口径（main.gd:180 启动扫描 / level_scene 缺章兜底重扫 / tests 多处）——行为零改动，
	## 只是把「扫描并填表」下沉到 _scan_builtin_dir、由本函数统一发射 scan_finished。
	var r: Dictionary = _scan_builtin_dir(dir)
	scan_finished.emit(int(r["loaded"]), int(r["failed"]))

## 扫描内置关卡目录并填 `_levels`（**不发射** scan_finished；发射由调用方 scan_directory /
## scan_all 负责，保证「一次扫描恰一次发射」）。返回 {loaded:int, failed:int}。
func _scan_builtin_dir(dir: String) -> Dictionary:
	_levels.clear()
	_errors.clear()
	var loaded: int = 0
	var failed: int = 0
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		push_warning("关卡目录不存在: %s" % dir)
		return {"loaded": 0, "failed": 0}
	d.list_dir_begin()
	var fn: String = d.get_next()
	while fn != "":
		if not d.current_is_dir() and fn.ends_with(".json"):
			var full: String = dir.path_join(fn)
			# W9-2（批次 AA 规格 §12 P2-3）：**逐文件隔离**——单个坏档只影响自身（跳过 +
			# push_warning 留痕 + _errors 记原因），其余章节照常载入、scan_finished 照常发射。
			# GDScript 无 try/catch，隔离由三道防线合围：①_read_json 非字典一律归 {}；
			# ②validate_level 对**任意**输入是全函数（取值全走类型安全助手 _as_int/_as_str 与
			# typeof 容器守卫，旧实现的裸 int()/String()/typed 赋值/`(ts[0] as Array)` 四族
			# 运行期中止路径全部封死）；③本循环对失败逐文件告警计数，不中断迭代。
			# 旧缺陷实证：一个 target_shapes:["abc"] 的文件 → validate_level 内 Invalid cast 中止
			# → 本函数随之中止 → 其后所有关卡不载入、scan_finished 不发射（红测 W9-2 段）。
			var data: Dictionary = _read_json(full)
			if data.is_empty():
				failed += 1
				push_warning("坏档已跳过（非字典或不可解析）: %s" % full)
			else:
				var res: Dictionary = validate_level(data)
				if bool(res.get("ok", false)):
					var lvl_v: Variant = res.get("level", null)
					var lvl: Dictionary = lvl_v if typeof(lvl_v) == TYPE_DICTIONARY else {}
					_levels.append({
						"chapter": _as_int(lvl.get("chapter", 1), 1),
						"level_id": _as_str(lvl.get("level_id", ""), ""),
						"title": _as_str(lvl.get("title", ""), ""),
						"era": _as_str(lvl.get("era", ""), ""),
						"path": full,
						"data": lvl,
						"source": "builtin",
					})
					loaded += 1
				else:
					var reject: String = _as_str(res.get("reject", ""), "关卡数据非法")
					_errors[_as_int(data.get("chapter", 0), 0)] = reject
					failed += 1
					push_warning("坏档已跳过: %s（原因：%s）" % [full, reject])
		fn = d.get_next()
	d.list_dir_end()
	_levels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _as_int(a["chapter"], 0) < _as_int(b["chapter"], 0))
	return {"loaded": loaded, "failed": failed}

## W9-2（批次 AA 规格 §12 P2-3）类型安全取整：任意 Variant → int。int(Array)/int(Dictionary)
## 属「Nonexistent 'int' constructor」运行期中止（4.7 探针实证），故仅接受 int/float/纯整数串，
## 其余回落 fallback（绝不中止）。与旧 `int(v)` 对合法值（数值/整数串）行为逐字节等价。
static func _as_int(v: Variant, fallback: int) -> int:
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_FLOAT:
		return int(v)
	if typeof(v) == TYPE_STRING and (v as String).strip_edges().is_valid_int():
		return int(v)
	return fallback

## W9-2 类型安全取串：String(Array) 同属中止族（4.7 探针实证），非字符串回落 fallback。
static func _as_str(v: Variant, fallback: String) -> String:
	if typeof(v) == TYPE_STRING:
		return v
	return fallback

## 预留：扫描玩家自定义关卡目录（AB-4 搭桥；接口规范 §13：同格式 + source="user" 标记，
## 并保留既有 is_user_created=true 口径向后兼容）。
## 本期**零玩家可见入口**：本函数只读、不发射 scan_finished（发射口径由 scan_directory/scan_all
## 负责，与改动前一致——scan_user_directory 单独调用时既不发射也不计内置 loaded/failed）。
## 目录不存在时静默返回（玩家未造关 = 正常态，不擅自建目录）。
## 容错纪律=**与 scan_directory 的 W9-2 完全一致**：坏档逐文件隔离（跳过 + push_warning 告警 +
## _user_errors 按 level_id 留痕 + failed 计数），不影响其余用户档，更不影响内置表。
func scan_user_directory(dir: String = USER_LEVEL_DIR) -> void:
	scan_user_directory_ret(dir)

## 同 scan_user_directory，但返回 {loaded, failed}（scan_all 汇总口径用；两入口共用同一实现，
## 避免「扫描双份逻辑漂移」）。
func scan_user_directory_ret(dir: String = USER_LEVEL_DIR) -> Dictionary:
	_user_levels.clear()
	_user_errors.clear()
	var loaded: int = 0
	var failed: int = 0
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		return {"loaded": 0, "failed": 0}
	d.list_dir_begin()
	var fn: String = d.get_next()
	while fn != "":
		if not d.current_is_dir() and fn.ends_with(".json"):
			var full: String = dir.path_join(fn)
			var data: Dictionary = _read_json(full)
			var rid: String = _as_str(data.get("level_id", ""), fn)  # 留痕键：缺 id 回落文件名
			if data.is_empty():
				failed += 1
				_user_errors[rid] = "非字典或不可解析"
				push_warning("坏档已跳过（user_levels）: %s（原因：%s）" % [full, _user_errors[rid]])
			else:
				var res: Dictionary = validate_level(data)
				if bool(res.get("ok", false)):
					var lvl_v: Variant = res.get("level", null)
					if typeof(lvl_v) != TYPE_DICTIONARY:
						failed += 1
						_user_errors[rid] = "validate 返回 level 非字典"
						push_warning("坏档已跳过（user_levels）: %s（原因：%s）" % [full, _user_errors[rid]])
					else:
						var lvl: Dictionary = lvl_v
						lvl["is_user_created"] = true
						_user_levels.append({
							"chapter": _as_int(lvl.get("chapter", 1), 1),
							"level_id": _as_str(lvl.get("level_id", ""), ""),
							"title": _as_str(lvl.get("title", ""), ""),
							"era": _as_str(lvl.get("era", ""), ""),
							"path": full,
							"data": lvl,
							"source": "user",
							"is_user_created": true,
						})
						loaded += 1
				else:
					# W9-2 同族留痕：坏档跳过 + 告警 + 按 level_id 记原因（与 scan_directory
					# 逐文件隔离口径一致；坏档不入 _user_levels，也不触碰 _levels/_errors）。
					var reject: String = _as_str(res.get("reject", ""), "关卡数据非法")
					failed += 1
					_user_errors[rid] = reject
					push_warning("坏档已跳过（user_levels）: %s（原因：%s）" % [full, reject])
		fn = d.get_next()
	d.list_dir_end()
	_user_levels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _as_int(a["chapter"], 0) < _as_int(b["chapter"], 0))
	return {"loaded": loaded, "failed": failed}

## AB-4「搭桥」合并扫描入口：内置目录 + 用户目录一次扫完，**恰发射一次** scan_finished
## （loaded/failed 为两表合计；用户坏档与内置坏档同池计数、分表留痕）。
## ★预留 UI 挂点：未来「自定义关卡」功能接入时，启动侧只需把 main.gd:180 的
##   `LevelLibrary.scan_directory()` 改为本函数（一行），UI 列表读 get_merged_level_list()
##   或 get_user_level_list()，进关仍走 get_level(chapter)（内置优先语义不变）。本期不改 main.gd。
func scan_all(builtin_dir: String = "res://levels_data", user_dir: String = USER_LEVEL_DIR) -> void:
	var rb: Dictionary = _scan_builtin_dir(builtin_dir)
	var ru: Dictionary = scan_user_directory_ret(user_dir)
	scan_finished.emit(int(rb["loaded"]) + int(ru["loaded"]), int(rb["failed"]) + int(ru["failed"]))

func _read_json(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var t: String = f.get_as_text()
	f.close()
	var v: Variant = JSON.parse_string(t)
	return v if typeof(v) == TYPE_DICTIONARY else {}

func get_level_list() -> Array:
	return _levels

## 预留：玩家自定义关卡列表（本期无入口 UI 消费）。★预留 UI 挂点：未来自定义关卡列表 UI 直接读本函数。
func get_user_level_list() -> Array:
	return _user_levels

## AB-4「搭桥」合并视图（只读副本）：内置 5 关 + 用户关共存，按 chapter 升序；**同 chapter 内置在前**
## （确定性序=「内置优先」拍板口径，与 get_level 的内置优先语义一致：主进度永不消费用户关，
## 同章用户关不遮蔽内置关、也不被内置关挤出列表）。
## ★预留 UI 挂点：未来「关卡选择/自定义关卡」UI 若要一张表混排展示，直接读本函数并按
##   entry["source"] 分组渲染；进关路由内置关仍走 get_level(chapter)，用户关走 get_user_level(id)。
func get_merged_level_list() -> Array:
	var merged: Array = _levels.duplicate(true)
	for u: Dictionary in _user_levels:
		merged.append(u.duplicate(true))
	merged.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ca: int = _as_int(a.get("chapter", 0), 0)
		var cb: int = _as_int(b.get("chapter", 0), 0)
		if ca != cb:
			return ca < cb
		# 同 chapter：builtin 排前（内置优先，稳定序由两表拼接先后天然给出）
		return _as_str(a.get("source", ""), "") == "builtin" and _as_str(b.get("source", ""), "") != "builtin")
	return merged

## AB-4「搭桥」按 level_id 取用户关卡条目（只读深拷贝；未知 id 返回 {}）。
## ★预留 UI 挂点：未来「点击用户关卡卡片→进关」即调本函数取 entry，把 entry["data"] 交 level_scene。
func get_user_level(level_id: String) -> Dictionary:
	for u: Dictionary in _user_levels:
		if _as_str(u.get("level_id", ""), "") == level_id:
			return u.duplicate(true)
	return {}

## AB-4「搭桥」判定 level_id 是否属用户关卡（未来 UI 分组/路由防呆：内置关 id 一律 false）。
func is_user_level_id(level_id: String) -> bool:
	return not get_user_level(level_id).is_empty()

## AB-4「搭桥」用户关坏档原因留痕（键=level_id；无记录返回 ""）。与 _errors 分表——
## _errors 属内置进度域（get_error(chapter) 既有语义不得混入用户档原因）。
## ★预留 UI 挂点：未来「加载失败关卡列表」直接按 id 读本函数显示原因。
func get_user_error(level_id: String) -> String:
	return _as_str(_user_errors.get(level_id, ""), "")

## AB-4「搭桥」写盘 helper（预留：未来「保存自制关卡」按钮的落盘通道，本期零 UI 消费）。
## 纪律=**先 validate_level 后落盘**——非法档拒写返回 false（绝不留脏档在盘）；合法档序列化为
## 契约单 JSON 写 <dir>/<level_id>.json（UTF-8、缩进 2、尾换行，与 AB-1 导入件字节口径一致）。
## 注：写入后须重扫（scan_all/scan_user_directory）才进内存表——本函数只负责原子落盘。
func write_user_level(doc: Dictionary, dir: String = USER_LEVEL_DIR) -> bool:
	var res: Dictionary = validate_level(doc)
	if not bool(res.get("ok", false)):
		push_warning("write_user_level 拒写（未通过校验）: %s" % _as_str(res.get("reject", ""), "关卡数据非法"))
		return false
	var level_id: String = _as_str(doc.get("level_id", ""), "")
	if level_id.is_empty():
		push_warning("write_user_level 拒写：level_id 为空")
		return false
	# P3-4（审查缺陷）：id 白名单 `^[A-Za-z0-9_-]+$`——旧序只查空串，`../` 可穿越出目标目录
	# 落盘任意位置；违者 push_warning + return false，零落盘。
	var id_re := RegEx.new()
	id_re.compile("^[A-Za-z0-9_-]+$")
	if id_re.search(level_id) == null:
		push_warning("write_user_level 拒写：level_id 含非法字符（仅允许 A-Za-z0-9_-）: %s" % level_id)
		return false
	var da: DirAccess = DirAccess.open(dir)
	if da == null:
		# 目录不存在时才创建（扫描路径不建目录；本函数是显式写盘动作，建目录属预期语义）
		var mk: int = DirAccess.make_dir_recursive_absolute(dir)
		if mk != OK:
			push_warning("write_user_level 目录创建失败: %s（err=%d）" % [dir, mk])
			return false
	# P3-4：tmp+rename 原子序（参考 save_manager.save_game）——写一半的 JSON 绝不暴露给扫描。
	var final_abs: String = ProjectSettings.globalize_path(dir.path_join(level_id + ".json"))
	var tmp_abs: String = final_abs + ".tmp"
	var f: FileAccess = FileAccess.open(tmp_abs, FileAccess.WRITE)
	if f == null:
		push_warning("write_user_level 打开写句柄失败: %s" % tmp_abs)
		return false
	f.store_string(JSON.stringify(doc, "  ", false) + "\n")
	f.close()
	if f.get_error() != OK:
		DirAccess.remove_absolute(tmp_abs)
		push_warning("write_user_level tmp 落盘失败（旧档未动）: %s" % tmp_abs)
		return false
	if DirAccess.rename_absolute(tmp_abs, final_abs) != OK:
		# 目标在位时部分平台 rename 拒绝 → 腾位序（先删旧档再改名；用户关卡可再次写入重建，
		# 丢档窗口远小于「半截 JSON 被读走」）。删/改名失败即放弃并保留 tmp（唯一完好副本）。
		if FileAccess.file_exists(final_abs) and DirAccess.remove_absolute(final_abs) != OK:
			DirAccess.remove_absolute(tmp_abs)
			push_warning("write_user_level 换名失败（旧档无法腾位，已清 tmp）: %s" % final_abs)
			return false
		var ren2: int = DirAccess.rename_absolute(tmp_abs, final_abs)
		if ren2 != OK:
			push_warning("write_user_level 换名失败（已保留 tmp 待人工）: %s（err=%d）" % [tmp_abs, ren2])
			return false
	return true

func get_level(chapter: int) -> Dictionary:
	for lvl: Dictionary in _levels:
		if int(lvl["chapter"]) == chapter:
			return lvl
	return {}

func get_error(chapter: int) -> String:
	return String(_errors.get(chapter, "关卡缺失"))

func validate_level(dict: Dictionary) -> Dictionary:
	## 关卡校验（W9-2 起为**全函数**：对任意 JSON 形态输入不产生运行期中止路径，全部取值走
	## 类型安全助手 _as_int/_as_str 与 typeof/is 容器守卫——坏档一律走 reject 分支被调用方
	## 逐文件隔离，绝不把 scan_directory 一起带崩）。
	var warnings: Array[String] = []
	if _as_int(dict.get("format_version", -1), -1) != 1:
		return {"ok": false, "reject": "关卡文件版本不兼容", "warnings": warnings, "level": {}}
	var level: Dictionary = dict.duplicate(true)
	var chapter: int = _as_int(level.get("chapter", 0), 0)
	if chapter < 1 or chapter > 5:
		warnings.append("chapter 越界，按 1 处理")
		level["chapter"] = 1
	# W9-2：容器类型守卫——旧实现 `var pieces: Array = level.get(...)` / `var bs: Dictionary =
	# piece.get(...)` 等 typed 赋值对脏类型属「Trying to assign …」运行期中止（4.7 探针实证）。
	if not (level.get("pieces") is Array):
		return {"ok": false, "reject": "关卡数据缺失", "warnings": warnings, "level": {}}
	var pieces: Array = level.get("pieces")
	if pieces.is_empty():
		return {"ok": false, "reject": "关卡数据缺失", "warnings": warnings, "level": {}}
	var clean_pieces: Array = []
	for piece_v: Variant in pieces:
		if typeof(piece_v) != TYPE_DICTIONARY:
			continue
		var piece: Dictionary = piece_v
		# W9-2：block_size 非字典 → 整体按缺省 {}（轴取值 0 → 下方 v<1 拒绝，口径与旧实现
		# 「block_size 越界即拒」一致；旧实现此处 typed 赋值直接中止）。
		var bs_v: Variant = piece.get("block_size", {})
		var bs: Dictionary = bs_v if typeof(bs_v) == TYPE_DICTIONARY else {}
		for axis: String in ["x", "y", "z"]:
			var v: int = _as_int(bs.get(axis, 0), 0)
			if v < 1 or v > 32:
				return {"ok": false, "reject": "体素尺寸越界", "warnings": warnings, "level": {}}
		# 批次 V（规格 §9.5）：四域各自尺寸——target↔target_size（缺失回落 block_size）、
		# join↔join_part.size、final↔final_answer.size（缺字典/缺轴逐轴回落 block_size，
		# 与编辑器 get_size_for_tag 回落链同口径）。已有值每维 1~32 校验（与上方 block_size
		# 口径对齐），越界拒绝且错误信息注明域；缺失回落路径零新增校验（旧格式档零回归）。
		var t_sz: Dictionary = _domain_size(piece.get("target_size", null), bs)
		# W9-2：join_part / final_answer 非字典 → 拒绝（旧实现 typed 赋值中止）
		var jp_v: Variant = piece.get("join_part", {})
		if not (jp_v is Dictionary):
			return {"ok": false, "reject": "join_part 格式非法", "warnings": warnings, "level": {}}
		var jp: Dictionary = jp_v
		var j_sz: Dictionary = _domain_size(jp.get("size", null), bs)
		var fa_v: Variant = piece.get("final_answer", {})
		if not (fa_v is Dictionary):
			return {"ok": false, "reject": "final_answer 格式非法", "warnings": warnings, "level": {}}
		var fa: Dictionary = fa_v
		var f_sz: Dictionary = _domain_size(fa.get("size", null), bs)
		for dom: Array in [["target_size", t_sz], ["join_part.size", j_sz], ["final_answer.size", f_sz]]:
			var dom_sz: Dictionary = dom[1]
			for axis: String in ["x", "y", "z"]:
				var dv: int = _as_int(dom_sz.get(axis, 0), 0)
				if dv < 1 or dv > 32:
					return {"ok": false, "reject": "体素尺寸越界（%s 域）" % dom[0], "warnings": warnings, "level": {}}
		# 净化体素坐标（各域按各自域尺寸裁剪，越界跳过并警告；blocks 域仍锚 block_size 现状）
		if piece.has("blocks") and not (piece["blocks"] is Array):
			return {"ok": false, "reject": "blocks 格式非法", "warnings": warnings, "level": {}}
		_clean_voxels(piece, "blocks", bs, warnings)
		# W9-2 核心：target_shapes 容器与**逐组元素**类型守卫——旧实现 `var ts: Array =
		# piece.get(...)`（typed 赋值）、`(ts[0] as Array).is_empty()`（字符串元素 → Invalid cast）、
		# `_filter_voxels(ts[i], …)`（typed 形参）三处对 `target_shapes:["abc"]` 形态全部中止，
		# 进而把 scan_directory 一起带崩（红测 W9-2 段实证：scan_finished 不发射）。
		var ts_v: Variant = piece.get("target_shapes", [])
		if not (ts_v is Array):
			return {"ok": false, "reject": "target_shapes 格式非法", "warnings": warnings, "level": {}}
		var ts: Array = ts_v
		if ts.is_empty():
			return {"ok": false, "reject": "target_shapes 为空", "warnings": warnings, "level": {}}
		for i: int in ts.size():
			if not (ts[i] is Array):
				return {"ok": false, "reject": "target_shapes 格式非法（第 %d 组非数组）" % i,
					"warnings": warnings, "level": {}}
		if (ts[0] as Array).is_empty():
			return {"ok": false, "reject": "target_shapes 为空", "warnings": warnings, "level": {}}
		for i: int in ts.size():
			ts[i] = _filter_voxels(ts[i], t_sz, warnings)
		# P3-3（审查缺陷）：空集检查**过滤后再判一次**——旧序只在过滤前判 `ts[0].is_empty()`，
		# target 全越界被滤空后仍 ok:true。全组皆空 → reject（与 join/final「过滤后为空」口径
		# 对齐）；单组滤空但其余组仍有格 → 接受（evaluate 按任一 shape 等价即 success）。
		var ts_left := false
		for i: int in ts.size():
			if not (ts[i] as Array).is_empty():
				ts_left = true
				break
		if not ts_left:
			return {"ok": false, "reject": "target_shapes 过滤后为空", "warnings": warnings, "level": {}}
		var jpv_v: Variant = jp.get("voxels", [])
		if not (jpv_v is Array):
			return {"ok": false, "reject": "join_part.voxels 格式非法", "warnings": warnings, "level": {}}
		var jpv: Array = jpv_v
		if jpv.is_empty():
			return {"ok": false, "reject": "join_part.voxels 为空", "warnings": warnings, "level": {}}
		jp["voxels"] = _filter_voxels(jpv, j_sz, warnings)
		if (jp["voxels"] as Array).is_empty():
			return {"ok": false, "reject": "join_part 过滤后为空", "warnings": warnings, "level": {}}
		var fav_v: Variant = fa.get("voxels", [])
		if not (fav_v is Array):
			return {"ok": false, "reject": "final_answer 格式非法", "warnings": warnings, "level": {}}
		var fav: Array = fav_v
		if fav.is_empty():
			return {"ok": false, "reject": "final_answer 为空", "warnings": warnings, "level": {}}
		fa["voxels"] = _filter_voxels(fav, f_sz, warnings)
		if (fa["voxels"] as Array).is_empty():
			return {"ok": false, "reject": "final_answer 过滤后为空", "warnings": warnings, "level": {}}
		clean_pieces.append(piece)
	if clean_pieces.is_empty():
		return {"ok": false, "reject": "关卡数据缺失", "warnings": warnings, "level": {}}
	level["pieces"] = clean_pieces
	return {"ok": true, "reject": "", "warnings": warnings, "level": level}

## 批次 V（规格 §9.5）分域尺寸解析：v=target_size / join_part.size / final_answer.size 的原始值
## （Variant，可能缺失/非字典/缺轴）→ 完整 {x,y,z}；缺字典整缺回落 bs、缺轴逐轴回落 bs 对应轴
## （与编辑器 LevelProject.get_size_for_tag 回落链同口径）。旧档（无 target_size/size 键）天然
## 回落 block_size，全链行为与按域前逐字节等价。
func _domain_size(v: Variant, bs: Dictionary) -> Dictionary:
	var d: Dictionary = v if typeof(v) == TYPE_DICTIONARY else {}
	# W9-2：轴取值走 _as_int（脏类型回落 fallback，不中止；合法数值行为与旧 int() 逐字节等价）
	return {
		"x": _as_int(d.get("x", _as_int(bs.get("x", 0), 0)), 0),
		"y": _as_int(d.get("y", _as_int(bs.get("y", 0), 0)), 0),
		"z": _as_int(d.get("z", _as_int(bs.get("z", 0), 0)), 0),
	}

func _clean_voxels(piece: Dictionary, key: String, bs: Dictionary, warnings: Array[String]) -> void:
	if piece.has(key):
		# W9-2：调用方已保证 blocks 是 Array（validate_level 容器守卫），此处再留一道类型兜底
		if not (piece[key] is Array):
			piece[key] = []
			return
		piece[key] = _filter_voxels(piece[key], bs, warnings)

func _filter_voxels(arr: Array, bs: Dictionary, warnings: Array[String]) -> Array:
	var out: Array = []
	var mx: int = _as_int(bs.get("x", 0), 0)
	var my: int = _as_int(bs.get("y", 0), 0)
	var mz: int = _as_int(bs.get("z", 0), 0)
	for v: Variant in arr:
		# W9-2：非字符串体素项跳过并告警（旧实现 `String(v)` 对 Array/字典属中止族）
		if typeof(v) != TYPE_STRING:
			warnings.append("非法体素类型已跳过: %s" % type_string(typeof(v)))
			continue
		var s: String = v
		var parts: PackedStringArray = s.split(",")
		if parts.size() != 3:
			warnings.append("非法体素格式已跳过: %s" % s)
			continue
		var x: int = _as_int(parts[0], -1); var y: int = _as_int(parts[1], -1)
		var z: int = _as_int(parts[2], -1)
		if x < 0 or y < 0 or z < 0:
			warnings.append("非法体素坐标已跳过: %s" % s)
			continue
		if x >= mx or y >= my or z >= mz:
			warnings.append("体素坐标越界已跳过: %s" % s)
			continue
		out.append(s)
	return out

# ---------- 章节资产映射 ----------
func get_model_path(chapter: int) -> String:
	return "res://assets/models/%s.glb" % String(ERA_MODEL.get(chapter, "石器"))

## AB-4「搭桥」（可选推荐项落地）：编辑器五件套目录 → 游戏侧契约单 JSON 文档（逻辑=AB-1 导入
## 脚本 `ab1_import_editor_levels_temp.py` 与 test_w_contract 镜像组装 `_mirror_assemble_doc` 的
## GDScript 等价实现；键集合与第 1 关导入件 level_chapter1_hemudu.json 逐键一致）。
## 消费口径（接口规范 §8.6/§13）：level.json=元数据、blocks.json→piece 主体（含 match_offset 原样、
## target_size 显式补齐=block_size——编辑器无独立 target_size，契约回落同款显式写）、
## target.json→target_shapes、join.json→join_part{size,voxels}、final.json→final_answer{size,voxels}。
## 容错口径=**skip 语义**（与 test_w_contract 一致，不假红不中止）：五件套缺任一 / 解析失败 /
## 空骨架槽（target/join/final 任一域源头为空=编辑器进行中内容）→ 返回 {}；
## 产物是否合法仍由调用方过 validate_level 把关（双保险，本函数不做判定）。
## ★预留 UI 挂点：未来玩家从编辑器工程目录「导入关卡」时，UI 调
##   `convert_editor_level(<编辑器 level_N 目录>)` → `write_user_level(doc)` → `scan_all()` 三步即闭环。
func convert_editor_level(editor_level_dir: String) -> Dictionary:
	var files: Array[String] = ["level.json", "blocks.json", "target.json", "join.json", "final.json"]
	var docs: Array[Dictionary] = []
	for fn: String in files:
		var p: String = editor_level_dir.path_join(fn)
		if not FileAccess.file_exists(p):
			return {}  # 缺档=skip（对齐 test_w_contract「不完整即 skip」红线）
		var d: Dictionary = _read_json(p)
		if d.is_empty():
			return {}  # 解析失败/非字典=skip
		docs.append(d)
	var meta: Dictionary = docs[0]
	var blk: Dictionary = docs[1]
	var tgt: Dictionary = docs[2]
	var jn: Dictionary = docs[3]
	var fnl: Dictionary = docs[4]
	# 源头空域判定（读源文件内容而非组装结果，test_w_contract 同口径）：空骨架槽/未成品槽 → {}
	var ts_v: Variant = tgt.get("target_shapes", [])
	if not (ts_v is Array) or (ts_v as Array).is_empty():
		return {}
	var ts_first: Variant = (ts_v as Array)[0]
	if not (ts_first is Array) or (ts_first as Array).is_empty():
		return {}
	if not (jn.get("voxels", []) is Array) or (jn.get("voxels", []) as Array).is_empty():
		return {}
	if not (fnl.get("voxels", []) is Array) or (fnl.get("voxels", []) as Array).is_empty():
		return {}
	var bs_v: Variant = blk.get("block_size", {})
	if not (bs_v is Dictionary):
		return {}
	var bs: Dictionary = bs_v
	var piece: Dictionary = {
		"piece_id": _as_str(blk.get("piece_id", ""), "p1"),
		"name": _as_str(blk.get("name", ""), ""),
		"block_size": {"x": _as_int(bs.get("x", 0), 0), "y": _as_int(bs.get("y", 0), 0), "z": _as_int(bs.get("z", 0), 0)},
		"initial_voxels": bool(blk.get("initial_voxels", false)) if typeof(blk.get("initial_voxels", false)) == TYPE_BOOL else false,
		"blocks": blk.get("blocks", []) if blk.get("blocks", null) is Array else [],
		"match_offset": _editor_vec3_dict(blk.get("match_offset", {})),
		"target_shapes": ts_v,
		"target_size": {"x": _as_int(bs.get("x", 0), 0), "y": _as_int(bs.get("y", 0), 0), "z": _as_int(bs.get("z", 0), 0)},
		"join_part": {"size": _editor_vec3_dict(jn.get("size", {})), "voxels": jn.get("voxels", [])},
		"final_answer": {"size": _editor_vec3_dict(fnl.get("size", {})), "voxels": fnl.get("voxels", [])},
	}
	return {
		"format_version": 1,
		"level_id": _as_str(meta.get("level_id", ""), ""),
		"chapter": _as_int(meta.get("chapter", 1), 1),
		"title": _as_str(meta.get("title", ""), ""),
		"era": _as_str(meta.get("era", ""), ""),
		"theme": _as_str(meta.get("theme", "wood"), "wood"),
		"description": _as_str(meta.get("description", ""), ""),
		"anim_time": _as_int(meta.get("anim_time", 100), 100),
		"grid_size_unused": 0,
		"pieces": [piece],
	}

## 五件套尺寸/偏移三元组归一：非字典或脏类型逐轴回落 0（int 化，AB-1 脚本 int() 同口径）。
func _editor_vec3_dict(v: Variant) -> Dictionary:
	var d: Dictionary = v if typeof(v) == TYPE_DICTIONARY else {}
	return {"x": _as_int(d.get("x", 0), 0), "y": _as_int(d.get("y", 0), 0), "z": _as_int(d.get("z", 0), 0)}

func get_points_path(chapter: int) -> String:
	return "res://assets/models/points/%s_points.res" % String(ERA_MODEL.get(chapter, "石器"))

func get_background_path(chapter: int) -> String:
	# 2026-08-26 用户指示：所有背景/大厅/关卡图片一律 PNG（bg_chapter5 已从 jpg 转 png）。
	return "res://assets/backgrounds/bg_chapter%d.png" % chapter

func get_reference_image_path(chapter: int) -> String:
	# 2026-08-26 用户指示：所有图片一律 PNG（ref_chapter1~4 已从 jpg 转 png）。
	return "res://assets/reference_images/ref_chapter%d.png" % chapter
