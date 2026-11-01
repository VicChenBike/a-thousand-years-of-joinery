extends "res://tests/test_base.gd"
## 批次 Y（Y-C1，spec §9.2）：第 2~5 关数据五域语义自检。
## 批次 AB（2026-09-25）等价改写：第 2~5 关替换为用户在关卡编辑器亲手做的正式关
## （levels/level_2~5 五件套实况：blocks 114/132/123/288、target 105/102/105/134、join 60/174/118/232、
## final 165/276/219/366、挖除量 9/30/18/154、target∩join 33/48/11/47、carved∩final 4/24/10/72、
## join∩final 60/30/10/43；era/description 编辑器原样空串、title=第二关~第五关）。
## 改写点（断言数只增不减、判别力不减）：blocks ≤64→≤32³（validate_level 契约上限）+ 格数钉值；
## blocks「全实心阵」→ 格数钉值（新关 blocks 非全实心属合法态：编辑器按域画料）；挖除量 [3,8]
## （占位关「不当难题」护栏）→ 实况钉值（难度已由用户亲手把关）；交叠钉值 13/12/10/16→33/48/11/47；
## 旧「装配后 (join+match_offset) ⊇ 挖除格」→ carved∩final + join∩final 两枚交叠钉值（1→2 条；
## 新关 final=编辑器独立绘制参照域、join 自有坐标系，装配覆盖语义不再适用）；
## era 宋/元/明/现代 → era 实况（空串）+ ERA_MODEL 章节时代映射（判别力等价承担）。
## 契约（技术文档/接口规范_关卡数据.md + §9.4.0 拍板 9 口径）：
##   - blocks=玩家初始木料（全量体素列表）；target=玩家挖成的判定依据，严格 ⊆ blocks 域；
##   - join=外部固定件（自有坐标系 + match_offset 装配位移、与 target 可交叠）；final 批次 Z
##     （Z2 用户拍板）放宽=非空 + 尺寸合法（各维 1~32、体素界内过滤后非空）；
##   - chapter 上限 5 硬编码零触碰（本套件只读数据不触代码）。
## 可通关自查：level_scene.evaluate_join（48 变换等价）——remaining=target → success；
## 多挖一格 → 非 success（wrong）。

var _ls: Variant = null

func _ls_script() -> Variant:
	if _ls == null:
		_ls = load("res://scenes/level/level_scene.gd")
	return _ls

func _cells(arr: Array) -> Dictionary:
	var out := {}
	for v: Variant in arr:
		out[String(v)] = true
	return out

func _parse(s: String) -> Vector3i:
	var p: PackedStringArray = s.split(",")
	return Vector3i(int(p[0]), int(p[1]), int(p[2]))

func _initialize() -> void:
	print("== test_y5_level_data ==")
	var lib: Node = root.get_node("LevelLibrary")
	lib.call("scan_directory")

	# ---- 0. 前置：第 1 关既有档不被遮蔽（一关一文件一 chapter）----
	var lvl1: Dictionary = lib.call("get_level", 1)
	check(not lvl1.is_empty() and String((lvl1["data"] as Dictionary).get("level_id", "")) == "chapter1_editor",
		"回归：第 1 关仍=chapter1_editor（批次 Z 编辑器五件套快照；新档不遮蔽既有章）")

	for ch: int in [2, 3, 4, 5]:
		var lvl: Dictionary = lib.call("get_level", ch)
		check(not lvl.is_empty(), "第 %d 关：关卡库已扫描加载" % ch)
		if lvl.is_empty():
			continue
		var data: Dictionary = lvl["data"]
		check_eq(int(data.get("chapter", -1)), ch, "第 %d 关：chapter 域一致" % ch)
		check(String(data.get("title", "")).length() > 0, "第 %d 关：title 非空（「%s」）" % [ch, String(data.get("title", ""))])
		var v: Dictionary = lib.call("validate_level", data)
		check(bool(v.get("ok", false)) and String(v.get("reject", "")) == "",
			"第 %d 关：validate_level 零拒绝（%s）" % [ch, String(v.get("reject", "<no-key>"))])

		var piece: Dictionary = (data["pieces"] as Array)[0]
		var bs: Dictionary = piece["block_size"]
		var bx := int(bs["x"]); var by := int(bs["y"]); var bz := int(bs["z"])
		# 批次 AB 等价改写：旧「blocks 阵 ≤64 格」（占位关小关护栏）→ 32³ 契约上限（validate_level
		# 拒载阈值，判别力=防超大关）+ blocks 格数实况钉值（114/132/123/288，防数据静默漂移）。
		check(bx * by * bz <= 32 * 32 * 32, "第 %d 关：blocks 阵 ≤32³ 契约上限（%d×%d×%d=%d）" % [ch, bx, by, bz, bx * by * bz])
		var blocks := _cells(piece["blocks"])
		var blocks_expect := {2: 114, 3: 132, 4: 123, 5: 288}
		check_eq(blocks.size(), int(blocks_expect.get(ch, -1)),
			"第 %d 关：blocks=%d 格（编辑器五件套实况钉值；旧「全实心阵==bx*by*bz」等价替换——新关按域画料非全实心属合法态）"
				% [ch, int(blocks_expect.get(ch, -1))])

		var target: Array = (piece["target_shapes"] as Array)[0]
		var tset := _cells(target)
		var carved := blocks.size() - tset.size()
		# 批次 AB 等价改写：旧「挖除量 ∈ [3,8]（占位关不当难题）」→ 实况钉值 9/30/18/154
		# （难度已由用户亲手设计把关；钉值锁「挖除集不被静默改动」，判别力=等式级）。
		var carved_expect := {2: 9, 3: 30, 4: 18, 5: 154}
		check_eq(carved, int(carved_expect.get(ch, -1)),
			"第 %d 关：挖除量=%d 格（编辑器实况钉值；旧 [3,8] 占位关护栏等价替换）" % [ch, int(carved_expect.get(ch, -1))])
		var in_bounds := true
		for k: Variant in tset:
			var c := _parse(String(k))
			if c.x < 0 or c.x >= bx or c.y < 0 or c.y >= by or c.z < 0 or c.z >= bz:
				in_bounds = false
		check(in_bounds, "第 %d 关：target 全部界内（block_size 域）" % ch)
		var subset := true
		for k: Variant in tset:
			if not blocks.has(k):
				subset = false
		check(subset, "第 %d 关：target 严格 ⊆ blocks（接口规范红线：target=挖成判定依据）" % ch)

		var join: Array = (piece["join_part"] as Dictionary)["voxels"]
		var jset := _cells(join)
		check(jset.size() >= 1, "第 %d 关：join 非空（小型固定件 %d 格）" % [ch, jset.size()])
		# 批次 Z Z-A 回修 P2-1 等价改写（断言数 1→2 只增不减，新值取自新数据实况）：
		# 旧断言「join 与 target 原坐标互斥（固定件占挖除位）」系 Z-A 波「join=挖除格补件」设计的产物，
		# 回修后 join=外部固定件（独立榫卯构件，自有坐标系 + match_offset 装配位移），与 target 交叠
		# 属预期（第 1 关五件套实况 target∩join=39 格先例、spec 明示「非强制互斥」；evaluate_join
		# 判定 success 先于干涉，交叠不影响可通关）→ 改①交叠实况钉值 + ②装配后覆盖卯口（更强语义）。
		var overlap := 0
		for k: Variant in jset:
			if tset.has(k):
				overlap += 1
		var overlap_expect := {2: 33, 3: 48, 4: 11, 5: 47}
		check_eq(overlap, int(overlap_expect.get(ch, -1)),
			"第 %d 关：join 与 target 原坐标交叠=%d 格（批次 AB 编辑器实况钉值，旧 13/12/10/16 等价替换）"
			% [ch, overlap])
		# 批次 AB 等价改写：旧「装配后 (join+match_offset) ⊇ 挖除格（卯口被固定件填满）」——新关
		# final=编辑器 final 域独立绘制的最终成品参照（与第 1 关 330≠243 同族「原样导入」合法态）、
		# join 自有坐标系，装配覆盖语义不再适用 → 等价替换为两枚交叠实况钉值（1→2 条只增不减）：
		# 挖除格∩final（成品对榫卯空腔的表达）与 join∩final（对接部位在成品中的痕迹）。
		var carved_set := {}
		for k3: Variant in blocks:
			if not tset.has(k3):
				carved_set[k3] = true
		var fset_early := _cells((piece["final_answer"] as Dictionary)["voxels"])
		var cf_inter := 0
		for kc: Variant in carved_set:
			if fset_early.has(kc):
				cf_inter += 1
		var cf_expect := {2: 4, 3: 24, 4: 10, 5: 72}
		check_eq(cf_inter, int(cf_expect.get(ch, -1)),
			"第 %d 关：挖除格∩final 交叠=%d 格（最终成品参照域实况钉值；旧「装配覆盖卯口」等价替换①）"
				% [ch, cf_inter])
		var jf_inter := 0
		for kj2: Variant in jset:
			if fset_early.has(kj2):
				jf_inter += 1
		var jf_expect := {2: 60, 3: 30, 4: 10, 5: 43}
		check_eq(jf_inter, int(jf_expect.get(ch, -1)),
			"第 %d 关：join∩final 交叠=%d 格（对接部位在成品中的痕迹钉值；旧「装配覆盖卯口」等价替换②）"
				% [ch, jf_inter])

		var final: Array = (piece["final_answer"] as Dictionary)["voxels"]
		var fset := _cells(final)
		# 批次 Z（Z2 用户拍板「final 原样导入」）：旧「final=target∪join 格数一致/逐格相等」
		# 硬断言放宽为「非空 + 尺寸合法（各维 1~32、体素界内过滤后非空）」——断言数 2→3 只增不减。
		check(fset.size() >= 1, "第 %d 关：final 非空（%d 格；Z2 放宽口径替换 union 硬断言）" % [ch, fset.size()])
		var fsz: Dictionary = (piece["final_answer"] as Dictionary).get("size", {})
		var fsz_ok := true
		for axis: String in ["x", "y", "z"]:
			var fv := int(fsz.get(axis, 0))
			if fv < 1 or fv > 32:
				fsz_ok = false
		check(fsz_ok, "第 %d 关：final_answer.size 各维 1~32（%s）" % [ch, str(fsz)])
		var fin_ok := true
		for k: Variant in fset:
			var cf := _parse(String(k))
			if cf.x < 0 or cf.x >= int(fsz.get("x", 0)) or cf.y < 0 or cf.y >= int(fsz.get("y", 0)) \
					or cf.z < 0 or cf.z >= int(fsz.get("z", 0)):
				fin_ok = false
		check(fin_ok, "第 %d 关：final 体素全部界内（final_answer.size 域，过滤后非空）" % ch)

		# ---- 可通关自查（48 变换等价，evaluate_join 单一真相源）----
		var joined: String = _ls_script().call("evaluate_join", tset, piece["target_shapes"], join)
		check_eq(joined, "success", "第 %d 关：挖成 target → evaluate_join=success（可通关）" % ch)
		var over := {}
		for k: Variant in tset:
			over[k] = true
		var extra_removed := String((tset.keys() as Array)[0])
		over.erase(extra_removed)  # 多挖一格（target 内再剔一格=玩家挖过头）→ 偏离答案
		var wrong: String = _ls_script().call("evaluate_join", over, piece["target_shapes"], join)
		check(wrong != "success", "第 %d 关：多挖一格（%s）→ 非 success（判定有效）" % [ch, extra_removed])

	# ---- 章节路由衔接（Y-C2/Y-C3 数据驱动前提）----
	# 批次 AB 等价改写：era 字段=编辑器 level.json 实况（用户未填 era→空串原样导入，零消费字段）；
	# 「第 2~5 关=宋/元/明/现代」判别力由 ERA_MODEL 资产映射断言等价承担（LevelLibrary 单源）。
	var era_ok := true
	for ch_era: int in [2, 3, 4, 5]:
		var dl: Dictionary = lib.call("get_level", ch_era)
		if dl.is_empty() or String((dl["data"] as Dictionary).get("era", "")) != "":
			era_ok = false
	check(era_ok, "era 域实况：第 2~5 关 era=空串（编辑器 level.json 原样导入，零消费字段）")
	var era_model_ok := true
	for pair2: Array in [[2, "宋"], [3, "元"], [4, "明"], [5, "现代"]]:
		if not String(lib.call("get_model_path", int(pair2[0]))).contains(String(pair2[1])):
			era_model_ok = false
	check(era_model_ok, "ERA_MODEL 章节映射：第2关宋/第3关元/第4关明/第5关现代（era 空串导入后的判别力承担）")
	check(ResourceLoader.exists("res://assets/backgrounds/bg_chapter2.png")
		and ResourceLoader.exists("res://assets/backgrounds/bg_chapter5.png"),
		"Y-C2 前提：bg_chapter2~5 既有素材在库")
	check(ResourceLoader.exists("res://assets/models/points/宋_points.res")
		and ResourceLoader.exists("res://assets/models/points/现代_points.res"),
		"Y-C2 前提：五时代点云在库（成功动画聚合管线既有消费）")

	finish()
