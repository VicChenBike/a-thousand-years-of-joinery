extends "res://tests/test_base.gd"
## 批次 Z Z2（关卡数据域，spec §2）红测：第 1 关编辑器五件套一次性快照导入 + 第 2~5 关新写
## 数据锁定 + 表现系统参数化复验。契约来源：批次 Z spec §2（验收断言方向①~④）+ 接口规范 §2~§5。
## 批次 AB（2026-09-25）等价改写：第 2~5 关替换为用户在关卡编辑器亲手做的正式关（levels/level_2~5
## 五件套实况：blocks 114/132/123/288、target 105/102/105/134、join 60/174/118/232、final 165/276/219/366）。
## 改写点（断言数只增不减、判别力不减）：③ era 实况=编辑器 level.json 原样（用户未填 era→空串导入，
## 「主题时代」判别力由 ⑥ ERA_MODEL 章节映射断言承担）；⑦ 旧「final == target ∪ (join+match_offset)」
## 对新关不成立（编辑器 final=独立绘制的最终成品参照域，与第 1 关 330≠243 同族合法态、接口规范 §5
## 「原样导入口径」）→ 等价替换为 final 格数 / target∩final / join∩final 三重指纹钉值（1→3 条）。
## 断言组（任务单断言①~⑤ + spec §2-5 表现系统复验）：
##   ① 第 1 关：validate_level 零 reject + 零警告 + 四域格数 180/160/122/330 + 四域尺寸
##     12×3×5 / 12×3×5 / 3×7×7 / 12×7×8 + chapter=1 + level_id=chapter1_editor（五件套实况）。
##   ② 五关可自关卡库进入（get_level 非空 + validate 零 reject）+ target ⊆ blocks +
##     evaluate_join(remaining=target, target_shapes, join) == "success"（可通关；48 变换等价
##     单一真相源 level_scene.evaluate_join）+ 挖除格可达（target 挖得出：挖除集 blocks−target
##     须经自身连通至包围盒表面，贪心挖掘全程无卡死——可玩性前置）。
##   ③ 五关形状集合两两不等（block_size+四域体素集指纹，C(5,2)=10 对逐对断言）+ era 实况
##     （第 1 关新石器时代 / 第 2~5 关 宋/元/明/现代——spec §2-3 主题时代互不相同）。
##   ④ 每关四域「非空 + 尺寸合法（各维 1~32、体素按域界内）」——替换旧「final=target∪join」
##     union 硬断言口径（用户拍板「final 原样导入」，第 1 关 final=330≠243）。
##   ⑦ （批次 Z Z-A 回修 P2-1）每关 final_answer **不是全实心块**：①final 与 blocks 逐格不等
##     ②final 至少一维尺寸 > blocks 对应维 ③final 格数 > blocks 格数 ④final 格数 < 其包围盒
##     体积（非全实心）——改前第 2~5 关 final 逐格==blocks（60/60、60/60、54/54、64/64）四条全红；
##     另第 2~5 关加 ⑤final == target ∪ (join + match_offset)（对接完成形态语义锚；第 1 关为
##     用户自有数据、spec §12 遗留②拍板 final=330≠union=243，**豁免此条**、零改动）。
##   ⑤ 键鼠路径零回归：逐关进关（set_context 先于 add_child + await process_frame）→ 三视图
##     构建数==数据实况（main=blocks / 左上=final——批次 Z Z1 换源 / 右上=join）→ 背景按
##     chapter 切换 → 选格→挖除（剩余-1）→撤销→恢复全量且节点可见（select/delete/undo 钩子）。
##   ⑥ 表现系统复验（参数化，spec §2-5「已实现只复验不新增」）：背景图/图鉴参考图/五时代胜利
##     点云按 chapter 在库 + 粒子接线（release_particles）在场 + 天赋值表 100/200/400/800/1600
##     + EYE_FREE_CHAPTER=5 谓词与计费口 + 重玩发奖五章键与 3 次限额（第 4 次不发）。
## 环境（实证规律）：--script 无头 level_scene 必须运行期 load（const preload 于
##   编译期炸 autoload，test_y5_level_data 先例）；实例化 level_scene 即写 user:// 检查点 →
##   清档纪律照抄 test_level_scene（自愈先还原→备份→清域→终测还原→逐字节自检）。

const LS_SCRIPT := "res://scenes/level/level_scene.gd"
const LEVEL_SCENE := "res://scenes/level/level_scene.tscn"
const CHAPTERS: Array = [1, 2, 3, 4, 5]

# ===== 清档纪律（照抄 test_level_scene：断点残留隔离，level._exit_tree 兜底写档不污染真实档）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_zlz_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _pre_save_text: String = ""

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _backup_user() -> void:
	for p0: String in DISC_WATCHED:
		var bk0: String = DISC_BK_PREFIX + p0.get_file()
		if FileAccess.file_exists(_disc_abs(bk0)):
			if FileAccess.file_exists(_disc_abs(p0)):
				DirAccess.remove_absolute(_disc_abs(p0))
			DirAccess.copy_absolute(_disc_abs(bk0), _disc_abs(p0))
			DirAccess.remove_absolute(_disc_abs(bk0))
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(_disc_abs(p)):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)
			DirAccess.remove_absolute(_disc_abs(p))   # 清域（断点/旗标归零，进关确定性）

func _restore_user() -> void:
	for c: Node in root.get_children():
		if not DISC_AUTOLOADS.has(String(c.name)):
			c.free()   # 先 free 测试挂载节点（level._exit_tree 兜底写档先落盘，规范第 6 条）
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(_disc_abs(p)):
			DirAccess.remove_absolute(_disc_abs(p))
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(_disc_abs(bk)):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(_disc_abs(bk))
	var real_sm: Node = root.get_node_or_null("SaveManager")
	if real_sm != null:
		real_sm.load_game()   # 内存重同步（防后续 save_game 把测试态写回真实档案）
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|z_level_data|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

# ===== 基础夹具 =====
var _ls: Variant = null

func _ls_script() -> Variant:
	if _ls == null:
		_ls = load(LS_SCRIPT)
	return _ls

func _cells(arr: Array) -> Dictionary:
	var out := {}
	for v: Variant in arr:
		out[String(v)] = true
	return out

func _parse(s: String) -> Vector3i:
	var p: PackedStringArray = s.split(",")
	return Vector3i(int(p[0]), int(p[1]), int(p[2]))

func _piece_of(data: Dictionary) -> Dictionary:
	var pieces_v: Variant = data.get("pieces", null)
	if not (pieces_v is Array) or (pieces_v as Array).is_empty() \
			or not ((pieces_v as Array)[0] is Dictionary):
		return {}
	return (pieces_v as Array)[0] as Dictionary

## 域尺寸解析：key="block_size"/"target_size"（piece 顶层）或 "join_part"/"final_answer"（嵌套 .size）；
## 缺字典/缺轴逐轴回落 block_size（接口规范 §3 批次 V 回落链同口径；全缺回 0 → _size_legal 判红）。
func _dom_sz(piece: Dictionary, key: String) -> Dictionary:
	var bs_v: Variant = piece.get("block_size", null)
	var bs: Dictionary = bs_v if bs_v is Dictionary else {}
	var raw: Variant = null
	if key == "join_part" or key == "final_answer":
		var dom_v: Variant = piece.get(key, null)
		if dom_v is Dictionary:
			raw = (dom_v as Dictionary).get("size", null)
	else:
		raw = piece.get(key, null)
	var d: Dictionary = raw if raw is Dictionary else {}
	return {
		"x": int(d.get("x", int(bs.get("x", 0)))),
		"y": int(d.get("y", int(bs.get("y", 0)))),
		"z": int(d.get("z", int(bs.get("z", 0)))),
	}

func _size_legal(sz: Dictionary) -> bool:
	for axis: String in ["x", "y", "z"]:
		var v: int = int(sz.get(axis, 0))
		if v < 1 or v > 32:
			return false
	return true

func _eq_sz(v: Variant, x: int, y: int, z: int) -> bool:
	if not (v is Dictionary):
		return false
	return int((v as Dictionary).get("x", -1)) == x \
		and int((v as Dictionary).get("y", -1)) == y \
		and int((v as Dictionary).get("z", -1)) == z

## 体素按域界内（0 ≤ c < 域尺寸对应维；元素恒为 "x,y,z" 串，数据坏则判红不崩）。
func _all_in(arr: Array, sz: Dictionary) -> bool:
	if not _size_legal(sz):
		return false
	for v: Variant in arr:
		var p: PackedStringArray = String(v).split(",")
		if p.size() != 3:
			return false
		var c := Vector3i(int(p[0]), int(p[1]), int(p[2]))
		if c.x < 0 or c.x >= int(sz.get("x", 0)) \
				or c.y < 0 or c.y >= int(sz.get("y", 0)) \
				or c.z < 0 or c.z >= int(sz.get("z", 0)):
			return false
	return true

## 「target 挖得出」贪心可达性：挖除集 carve=blocks−target 每格必须经挖除格自身连通至
## 包围盒表面（全实心 blocks 下=存在暴露面即可挖；逐轮挖一格推进，无进展即卡死=false）。
func _carve_reachable(blocks_arr: Array, target_arr: Array) -> bool:
	var present := {}
	for v: Variant in blocks_arr:
		present[_parse(String(v))] = true
	var tset := {}
	for v: Variant in target_arr:
		tset[_parse(String(v))] = true
	var carve := {}
	for k: Variant in present:
		if not tset.has(k):
			carve[k] = true
	if carve.is_empty():
		return true
	var dirs: Array = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]
	var left: int = carve.size()
	while left > 0:
		var progressed := false
		for k_v: Variant in carve.keys():
			var k: Vector3i = k_v
			for d_v: Variant in dirs:
				var n := Vector3i(k.x + int(d_v[0]), k.y + int(d_v[1]), k.z + int(d_v[2]))
				if not present.has(n):   # 邻格不在（界外或已挖）→ 暴露面 → 可挖
					carve.erase(k)
					present.erase(k)
					left -= 1
					progressed = true
					break
			if progressed:
				break
		if not progressed:
			return false
	return true

func _sorted_join(arr: Array) -> String:
	var a: Array = []
	for v: Variant in arr:
		a.append(String(v))
	a.sort()
	return "|".join(PackedStringArray(a))

## 形状指纹：block_size + blocks + target_shapes（多 shape 以 "§" 分隔）+ join + final 的
## 规范化串——四域任一不同即指纹不同（「形状集合两两不等」的可判定口径）。
func _fingerprint(piece: Dictionary) -> String:
	var s := "bs:%s;" % str(_dom_sz(piece, "block_size"))
	s += "b:%s;" % _sorted_join(piece.get("blocks", []) if piece.get("blocks", null) is Array else [])
	var ts_v: Variant = piece.get("target_shapes", null)
	var t_part := ""
	if ts_v is Array:
		for shape_v: Variant in (ts_v as Array):
			if shape_v is Array:
				t_part += _sorted_join(shape_v) + "§"
	s += "t:%s;" % t_part
	var jp_v: Variant = piece.get("join_part", null)
	s += "j:%s;" % ( _sorted_join((jp_v as Dictionary).get("voxels", []) \
		if (jp_v is Dictionary and (jp_v as Dictionary).get("voxels", null) is Array) else []) )
	var fa_v: Variant = piece.get("final_answer", null)
	s += "f:%s" % ( _sorted_join((fa_v as Dictionary).get("voxels", []) \
		if (fa_v is Dictionary and (fa_v as Dictionary).get("voxels", null) is Array) else []) )
	return s

func _initialize() -> void:
	print("== test_z_level_data ==")
	_backup_user()
	get_root().get_node("SaveManager").call("load_game")   # 清域后内存重同步（空档默认值）
	var lib: Node = get_root().get_node("LevelLibrary")
	lib.call("scan_directory", "res://levels_data")
	var ls: Variant = _ls_script()
	check(ls != null, "level_scene.gd 运行期可加载（静态 evaluate_join 承载前置）")
	if ls == null:
		finish()
		return

	# ============ ① 第 1 关五件套快照钉值（spec §2 验收①） ============
	var lvl1: Dictionary = lib.call("get_level", 1)
	check(not lvl1.is_empty(), "①-1：第 1 关已入关卡库（可自关卡库进入）")
	var data1: Dictionary = lvl1["data"] if not lvl1.is_empty() else {}
	var v1: Dictionary = lib.call("validate_level", data1)
	check(bool(v1.get("ok", false)) and String(v1.get("reject", "")) == "",
		"①-2：第 1 关 validate_level 零 reject（%s）" % String(v1.get("reject", "<no-key>")))
	check_eq((v1.get("warnings", []) as Array).size(), 0, "①-3：第 1 关 validate_level 零警告（四域零越界）")
	check_eq(int(data1.get("chapter", -1)), 1, "①-4：第 1 关 chapter=1")
	check_eq(String(data1.get("level_id", "")), "chapter1_editor",
		"①-5：level_id=chapter1_editor（编辑器五件套 level.json 实况；一次性快照导入）")
	var p1: Dictionary = _piece_of(data1)
	check(not p1.is_empty(), "①-6：pieces[0] 存在")
	if not p1.is_empty():
		var b1: Array = p1.get("blocks", []) if p1.get("blocks", null) is Array else []
		var t1: Array = ((p1.get("target_shapes", [[]]) as Array)[0]) as Array
		var j1: Array = ((p1.get("join_part", {}) as Dictionary).get("voxels", []) as Array)
		var f1: Array = ((p1.get("final_answer", {}) as Dictionary).get("voxels", []) as Array)
		check_eq(b1.size(), 180, "①-7：第 1 关 blocks=180 格（五件套实况）")
		check_eq(t1.size(), 160, "①-8：第 1 关 target=160 格")
		check_eq(j1.size(), 122, "①-9：第 1 关 join=122 格")
		check_eq(f1.size(), 330, "①-10：第 1 关 final=330 格（≠target∪join=243，用户拍板原样导入）")
		check(_eq_sz(p1.get("block_size", null), 12, 3, 5), "①-11：block_size=12×3×5")
		check(_eq_sz(p1.get("target_size", null), 12, 3, 5), "①-12：target_size=12×3×5")
		var j1_v: Variant = p1.get("join_part", null)
		check(_eq_sz((j1_v as Dictionary).get("size", null) if j1_v is Dictionary else null, 3, 7, 7),
			"①-13：join_part.size=3×7×7")
		var f1_v: Variant = p1.get("final_answer", null)
		check(_eq_sz((f1_v as Dictionary).get("size", null) if f1_v is Dictionary else null, 12, 7, 8),
			"①-14：final_answer.size=12×7×8")

	# ============ ②③④ 逐关：装载/可达/形状互异/era/四域合法（spec §2 验收①~③） ============
	# 批次 AB：era=编辑器 level.json 实况原样导入——第 1 关「新石器时代」（旧导入件既有），
	# 第 2~5 关用户未填 era（空串，零消费字段：生产代码无 era 读取点，显示走 title/ERA_MODEL 资产映射）。
	var era_expect := {1: "新石器时代", 2: "", 3: "", 4: "", 5: ""}
	var fingerprints := {}
	for ch_v: Variant in CHAPTERS:
		var ch: int = int(ch_v)
		var lvl: Dictionary = lib.call("get_level", ch)
		check(not lvl.is_empty(), "② 第 %d 关：可自关卡库进入（get_level 非空）" % ch)
		if lvl.is_empty():
			continue
		var data: Dictionary = lvl["data"]
		check_eq(int(data.get("chapter", -1)), ch, "② 第 %d 关：chapter 域一致" % ch)
		var vr: Dictionary = lib.call("validate_level", data)
		var vrok: bool = bool(vr.get("ok", false)) and String(vr.get("reject", "")) == ""
		check(vrok, "② 第 %d 关：validate_level 零 reject（%s）" % [ch, String(vr.get("reject", "<no-key>"))])
		check_eq(String(data.get("era", "")), String(era_expect.get(ch, "<none>")),
			"③ 第 %d 关：era=%s（主题时代实况）" % [ch, String(era_expect.get(ch, "<none>"))])
		if not vrok:
			continue
		var piece: Dictionary = _piece_of(data)
		if piece.is_empty():
			check(false, "② 第 %d 关：pieces[0] 存在" % ch)
			continue
		var blocks_arr: Array = piece.get("blocks", []) if piece.get("blocks", null) is Array else []
		var target_arr: Array = ((piece.get("target_shapes", [[]]) as Array)[0]) as Array
		var join_arr: Array = ((piece.get("join_part", {}) as Dictionary).get("voxels", []) as Array)
		var final_arr: Array = ((piece.get("final_answer", {}) as Dictionary).get("voxels", []) as Array)
		# ---- ④ 四域「非空 + 尺寸合法（各维 1~32、体素按域界内）」（替换旧 union 硬断言口径）----
		var bs_sz := _dom_sz(piece, "block_size")
		check(blocks_arr.size() >= 1, "④ 第 %d 关：blocks 非空（%d 格）" % [ch, blocks_arr.size()])
		check(_size_legal(bs_sz), "④ 第 %d 关：block_size 各维 1~32（%s）" % [ch, str(bs_sz)])
		check(_all_in(blocks_arr, bs_sz), "④ 第 %d 关：blocks 体素全部界内（block_size 域）" % ch)
		var ts_sz := _dom_sz(piece, "target_size")
		check(target_arr.size() >= 1, "④ 第 %d 关：target 非空（%d 格）" % [ch, target_arr.size()])
		check(_size_legal(ts_sz), "④ 第 %d 关：target_size 各维 1~32（%s；缺省回落 block_size）" % [ch, str(ts_sz)])
		check(_all_in(target_arr, ts_sz), "④ 第 %d 关：target 体素全部界内（target 域）" % ch)
		var js_sz := _dom_sz(piece, "join_part")
		check(join_arr.size() >= 1, "④ 第 %d 关：join 非空（%d 格）" % [ch, join_arr.size()])
		check(_size_legal(js_sz), "④ 第 %d 关：join_part.size 各维 1~32（%s）" % [ch, str(js_sz)])
		check(_all_in(join_arr, js_sz), "④ 第 %d 关：join 体素全部界内（join 域）" % ch)
		var fs_sz := _dom_sz(piece, "final_answer")
		check(final_arr.size() >= 1, "④ 第 %d 关：final 非空（%d 格）" % [ch, final_arr.size()])
		check(_size_legal(fs_sz), "④ 第 %d 关：final_answer.size 各维 1~32（%s）" % [ch, str(fs_sz)])
		check(_all_in(final_arr, fs_sz), "④ 第 %d 关：final 体素全部界内（final 域）" % ch)
		# ---- ⑦ final ≠ 全实心块（Z-A 回修 P2-1：左上「最终成品」须是有榫卯结构的拼合形态）----
		var bset7 := _cells(blocks_arr)
		var fset7 := _cells(final_arr)
		check(fset7 != bset7,
			"⑦ 第 %d 关：final_answer ≠ blocks（逐格不等；全实心块必红）" % ch)
		var bigger7 := false
		var axis7: String = ""
		for a7: String in ["x", "y", "z"]:
			if int(fs_sz.get(a7, 0)) > int(bs_sz.get(a7, 0)):
				bigger7 = true
				axis7 = a7
		check(bigger7,
			"⑦ 第 %d 关：final_answer 至少一维尺寸 > blocks（%s vs %s，超维=%s）"
			% [ch, str(fs_sz), str(bs_sz), axis7 if axis7 != "" else "<无>"])
		check(final_arr.size() > blocks_arr.size(),
			"⑦ 第 %d 关：final 格数(%d) > blocks 格数(%d)" % [ch, final_arr.size(), blocks_arr.size()])
		var vol7: int = int(fs_sz.get("x", 0)) * int(fs_sz.get("y", 0)) * int(fs_sz.get("z", 0))
		check(final_arr.size() < vol7,
			"⑦ 第 %d 关：final 非全实心（格数 %d < 包围盒体积 %d）" % [ch, final_arr.size(), vol7])
		# ---- ⑦⑤ final 指纹钉值（批次 AB 等价改写：1 条 union 等式 → 3 条实况钉值，1→3 只增不减）----
		# 旧断言「final == target ∪ (join + match_offset)」系批次 Z 占位关的对接完成形态语义锚；
		# 新关 final=编辑器 final 域独立绘制的「最终成品参照」（用户实况与 union 不等、target⊄final），
		# 与第 1 关 330≠243 同族合法态（接口规范 §5「final 原样导入」拍板）→ 改为三重指纹钉值锁
		# final 域内容不被静默改动（任一格增删即红，判别力不低于 union 等式）。实况值：
		# final 格数 165/276/219/366；target∩final 87/18/5/8；join∩final 60/30/10/43（第 2~5 关）。
		if ch >= 2:
			var fp_expect := {
				"count": {2: 165, 3: 276, 4: 219, 5: 366},
				"t_inter": {2: 87, 3: 18, 4: 5, 5: 8},
				"j_inter": {2: 60, 3: 30, 4: 10, 5: 43},
			}
			check_eq(final_arr.size(), int(fp_expect["count"].get(ch, -1)),
				"⑦ 第 %d 关：final 格数=%d（编辑器 final 域实况钉值，替换旧 union 等式）"
					% [ch, int(fp_expect["count"].get(ch, -1))])
			var tf_inter: int = 0
			var tset7 := _cells(target_arr)
			for kt: Variant in tset7:
				if fset7.has(kt):
					tf_inter += 1
			check_eq(tf_inter, int(fp_expect["t_inter"].get(ch, -1)),
				"⑦ 第 %d 关：target∩final 交叠=%d 格（final 参照域实况钉值）" % [ch, tf_inter])
			var jf_inter: int = 0
			for kj: Variant in join_arr:
				if fset7.has(String(kj)):
					jf_inter += 1
			check_eq(jf_inter, int(fp_expect["j_inter"].get(ch, -1)),
				"⑦ 第 %d 关：join∩final 交叠=%d 格（对接部位在成品中的痕迹钉值）" % [ch, jf_inter])
		# ---- ② target ⊆ blocks / 可通关 / target 挖得出 ----
		var tset := _cells(target_arr)
		var subset := true
		for k: Variant in tset:
			if not _cells(blocks_arr).has(k):
				subset = false
		check(subset, "② 第 %d 关：target ⊆ blocks（可挖成判定依据）" % ch)
		check(_carve_reachable(blocks_arr, target_arr),
			"② 第 %d 关：target 挖得出（挖除集经自身连通至表面，贪心无卡死）" % ch)
		var joined: String = String(ls.call("evaluate_join", tset, piece.get("target_shapes", []), join_arr))
		# 回修 P3 注记：本断言**判别力弱**（remaining 由 target 构造，平移归一恒等变换必 success，
		# 属恒真断言，仅锁「判定链未断」）；**可通关性证据链以上方 `_carve_reachable`（挖得出）
		# + `target ⊆ blocks`（可挖成判定依据）为准**——两者才具判别力。
		check_eq(joined, "success", "② 第 %d 关：evaluate_join(remaining=target) == success（可通关；判别力弱，证据链以 _carve_reachable + target⊆blocks 为准）" % ch)
		# ---- ③ 形状指纹登记（循环后逐对断言）----
		fingerprints[ch] = _fingerprint(piece)

	# ---- ③ 形状集合两两不等：C(5,2)=10 对逐对断言（任一对相等即该对判红） ----
	for i: int in CHAPTERS.size():
		for jj: int in range(i + 1, CHAPTERS.size()):
			var ca: int = int(CHAPTERS[i])
			var cb: int = int(CHAPTERS[jj])
			check(String(fingerprints.get(ca, "")) != String(fingerprints.get(cb, "")),
				"③：第 %d 关与第 %d 关形状集合不等（四域指纹，spec §2 形状互不相同）" % [ca, cb])

	# ============ ⑤ 键鼠路径零回归：逐关进关 → 三视图 == 数据 → 背景切换 → 挖除/撤销 ============
	for ch2_v: Variant in CHAPTERS:
		var ch2: int = int(ch2_v)
		var lvlE: Dictionary = lib.call("get_level", ch2)
		if lvlE.is_empty():
			check(false, "⑤ 第 %d 关：关卡库条目缺失（跳过进关）" % ch2)
			continue
		var pieceE: Dictionary = _piece_of(lvlE["data"])
		if pieceE.is_empty():
			check(false, "⑤ 第 %d 关：pieces[0] 缺失（跳过进关）" % ch2)
			continue
		var bE: Array = pieceE.get("blocks", []) if pieceE.get("blocks", null) is Array else []
		var tE: Array = ((pieceE.get("target_shapes", [[]]) as Array)[0]) as Array
		var jE: Array = ((pieceE.get("join_part", {}) as Dictionary).get("voxels", []) as Array)
		var fE: Array = ((pieceE.get("final_answer", {}) as Dictionary).get("voxels", []) as Array)
		var inst: Node = (load(LEVEL_SCENE) as PackedScene).instantiate()
		inst.call("set_context", {"chapter": ch2})   # Game 路由约定：先 set_context 再入树
		add_child(inst)
		await process_frame
		var vv_m: Node = inst.get_node_or_null("MainView/ViewportContainer/SubViewport/VoxelView")
		var vv_t: Node = inst.get_node_or_null("TargetView/ViewportContainer/SubViewport/VoxelView")
		var vv_j: Node = inst.get_node_or_null("JoinView/ViewportContainer/SubViewport/VoxelView")
		check(vv_m != null and vv_t != null and vv_j != null, "⑤ 第 %d 关：三视图 VoxelView 在场" % ch2)
		if vv_m != null and vv_t != null and vv_j != null:
			check_eq(int(vv_m.call("get_voxel_count")), bE.size(),
				"⑤ 第 %d 关：主视图构建数==blocks（%d）" % [ch2, bE.size()])
			check_eq(int(vv_t.call("get_voxel_count")), fE.size(),
				"⑤ 第 %d 关：左上「最终成品」构建数==final（Z1 换源，%d）" % [ch2, fE.size()])
			check_eq(int(vv_j.call("get_voxel_count")), jE.size(),
				"⑤ 第 %d 关：右上对接固定件构建数==join（%d）" % [ch2, jE.size()])
			check_eq(int(inst.call("get_built_voxel_count")), bE.size() + fE.size() + jE.size(),
				"⑤ 第 %d 关：三视图构建总数==blocks+final+join（%d）" % [ch2, bE.size() + fE.size() + jE.size()])
		var bg: TextureRect = inst.get_node_or_null("Background") as TextureRect
		check(bg != null and bg.texture != null
			and String(bg.texture.resource_path).ends_with("bg_chapter%d.png" % ch2),
			"⑤ 第 %d 关：背景按 chapter 切换（%s）" % [ch2, String(bg.texture.resource_path) if bg != null and bg.texture != null else "null"])
		var rem: Array = inst.call("get_remaining_voxels") as Array
		check_eq(rem.size(), bE.size(), "⑤ 第 %d 关：初始剩余==blocks（%d）" % [ch2, bE.size()])
		if not rem.is_empty():
			var cell_v: Variant = rem[0]
			var cell: Vector3i = cell_v if cell_v is Vector3i else _parse(String(cell_v))
			inst.call("select_voxel", cell, false)
			check_eq((inst.call("get_selected_voxels") as Array).size(), 1, "⑤ 第 %d 关：选格成功（键鼠 select）" % ch2)
			check_eq(int(inst.call("delete_selected")), 1, "⑤ 第 %d 关：挖除 1 格（键鼠 delete）" % ch2)
			check_eq((inst.call("get_remaining_voxels") as Array).size(), bE.size() - 1,
				"⑤ 第 %d 关：挖除后剩余-1（%d）" % [ch2, bE.size() - 1])
			check(inst.call("undo") == true, "⑤ 第 %d 关：撤销成功（键鼠 undo）" % ch2)
			check_eq((inst.call("get_remaining_voxels") as Array).size(), bE.size(),
				"⑤ 第 %d 关：撤销恢复全量（%d）" % [ch2, bE.size()])
			if vv_m != null:
				var nd: Node = vv_m.call("get_voxel_node", cell)
				check(nd != null and bool(nd.get("visible")), "⑤ 第 %d 关：撤销后节点可见" % ch2)
		inst.queue_free()
		await process_frame

	# ============ ⑥ 表现系统参数化复验（spec §2-5：背景/点云/粒子/天赋/图鉴发奖，只复验不新增） ============
	for ch3_v: Variant in CHAPTERS:
		var ch3: int = int(ch3_v)
		var bgp: String = String(lib.call("get_background_path", ch3))
		check(bgp.ends_with("bg_chapter%d.png" % ch3) and ResourceLoader.exists(bgp),
			"⑥ 第 %d 关：关卡背景在库（%s）" % [ch3, bgp])
		var refp: String = String(lib.call("get_reference_image_path", ch3))
		check(ResourceLoader.exists(refp), "⑥ 第 %d 关：图鉴参考图在库（%s）" % [ch3, refp])
		var ptp: String = String(lib.call("get_points_path", ch3))
		check(ptp.get_file() != "" and ResourceLoader.exists(ptp),
			"⑥ 第 %d 关：胜利点云按时代在库（%s）" % [ch3, ptp])
	# 批次 AB：era 字段走编辑器原样（第 2~5 关空串），「章节↔主题时代」判别力由 ERA_MODEL
	# 资产映射断言承担（LevelLibrary.ERA_MODEL 单源：模型/点云文件名逐章核对，互不相同）。
	var era_model_expect := {1: "石器", 2: "宋", 3: "元", 4: "明", 5: "现代"}
	for ch6b_v: Variant in CHAPTERS:
		var ch6b: int = int(ch6b_v)
		check(String(lib.call("get_model_path", ch6b)).contains(String(era_model_expect.get(ch6b, ""))),
			"⑥ 第 %d 关：ERA_MODEL 模型映射=%s（章节主题时代互不相同判别力，era 字段空串导入后的等价承担）"
				% [ch6b, String(era_model_expect.get(ch6b, ""))])
		check(String(lib.call("get_points_path", ch6b)).contains(String(era_model_expect.get(ch6b, ""))),
			"⑥ 第 %d 关：ERA_MODEL 点云映射=%s（同上）" % [ch6b, String(era_model_expect.get(ch6b, ""))])
	var talent_expect := {1: 100, 2: 200, 3: 400, 4: 800, 5: 1600}
	for ch4_v: Variant in CHAPTERS:
		var ch4: int = int(ch4_v)
		check_eq(int(ls.call("talent_for_grade", ch4, "perfect")), int(talent_expect.get(ch4, -1)),
			"⑥ 第 %d 关：完美档天赋值=%d（100/200/400/800/1600 表）" % [ch4, int(talent_expect.get(ch4, -1))])
	var lscm: Dictionary = (ls as Script).get_script_constant_map()
	check(int(lscm.get("EYE_FREE_CHAPTER", -1)) == 5, "⑥：EYE_FREE_CHAPTER=5（第 5 关锐眼免费既有实现）")
	check(bool(ls.call("is_eye_free_chapter", 5)) and not bool(ls.call("is_eye_free_chapter", 1)),
		"⑥：锐眼免费谓词——第 5 关 true / 第 1 关 false")
	check_eq(int(ls.call("eye_cost_for_chapter", 5, 1.0)), 0, "⑥：第 5 关锐眼 1.0s 计费=0（免费）")
	check_eq(int(ls.call("eye_cost_for_chapter", 1, 1.0)), 100, "⑥：第 1 关锐眼 1.0s 计费=100（回归）")
	var ls_src := FileAccess.get_file_as_string(LS_SCRIPT)
	check(ls_src.contains("release_particles"),
		"⑥：成功动画粒子接线在场（release_particles 消费点，参数化复验）")
	var sm: Node = get_root().get_node("SaveManager")
	for ch5_v: Variant in CHAPTERS:
		check_eq(int(sm.call("get_replay_count", int(ch5_v))), 0,
			"⑥ 第 %d 关：起测清档后重玩计数=0（replay_award_counts 五章键在档）" % int(ch5_v))
	var awarded := 0
	for i2: int in 4:
		if bool(sm.call("consume_replay_award", 5)):
			awarded += 1
	check_eq(awarded, 3, "⑥：图鉴重玩发奖——前 3 次发放、第 4 次 0（REPLAY_AWARD_LIMIT=3，第 5 关实跑）")

	finish()
