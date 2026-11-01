extends "res://tests/test_base.gd"
## 批次 N1：对接判定 48 种正交变换全等价 + 锐眼差集最佳变换同步（TDD 先写，实现前全 [FAIL] 属预期红灯）。
## 契约来源：批次 N 规格 §6.1/§6.2（项目内部设计文档）
## + 用户 2026-09-09 拍板 #1：
##   1) scripts/join_transform.gd = 判定与锐眼的单一真相源（纯静态、无场景依赖）：
##      - 48 变换枚举：24 旋转（det=+1）+ 24 镜像（det=−1），含恒等；枚举序确定（恒等=0 号）；
##      - are_equivalent(a,b)：双方平移归一（各自包围盒最小角→原点）后经 48 变换之一集合相等 → true；
##      - best_diff(player,target)：按「missing 数最小的最佳变换」（并列取 extra 更小者，
##        仍并列取枚举序首个，保证确定性）计算差集；extra/missing 经逆变换映射回玩家木料
##        当前坐标系（红 mark/绿 ghost 落在玩家实际可操作格上）；等价形状 → 红绿皆空。
##   2) evaluate_join 判定顺序（关键）：remaining 空 → wrong；等价（48 变换）→ success
##      （即使此时与 join_voxels 在原坐标交叠也算 success——用户实测翻转形状与固定件干涉
##      被误判「无法对接」场景）；否则 remaining ∩ join_voxels ≠ ∅（原坐标）→ unfit；
##      否则 wrong。
## 测试覆盖（spec §6.1 测试计划）：48 变换枚举完备无重复 / 绕水平轴翻转与镜像等价 / 非等价
## 仍 wrong、干涉仍 unfit、等价但干涉 → success / 差集最佳变换下逆变换映射回玩家坐标系
## （具体格坐标断言）/ 空集·单格·满块边界 / 平移归一（挖除后位置偏移仍等价）。

const JT_SCRIPT := "res://scripts/join_transform.gd"
const LS_SCRIPT := "res://scenes/level/level_scene.gd"

func _axis_of(v: Vector3i) -> int:
	if v.x != 0:
		return 0
	if v.y != 0:
		return 1
	return 2

func _initialize() -> void:
	print("== test_n_join_transform ==")
	var jt: Script = load(JT_SCRIPT)
	check(jt != null, "join_transform.gd 可加载（批次 N1 新增单一真相源）")
	if jt == null:
		finish()
		return
	var ls: Script = load(LS_SCRIPT)
	check(ls != null, "level_scene.gd 可加载（evaluate_join 语义复验）")
	var cmap: Dictionary = jt.get_script_constant_map()

	# ---- 1. 48 变换枚举完备且无重复（24 旋转 det=+1 + 24 镜像 det=−1，含恒等）----
	check(cmap.has("TRANSFORM_COUNT") and int(cmap["TRANSFORM_COUNT"]) == 48,
		"枚举：TRANSFORM_COUNT == 48（24 旋转 + 24 镜像）")
	var n_rot: int = 0
	var n_mir: int = 0
	for idx: int in range(48):
		var d: int = int(jt.call("det_of", idx))
		if d == 1:
			n_rot += 1
		elif d == -1:
			n_mir += 1
	check_eq(n_rot, 24, "枚举：det=+1 旋转恰 24 个")
	check_eq(n_mir, 24, "枚举：det=−1 镜像恰 24 个")
	check_eq(int(jt.call("det_of", 0)), 1, "枚举：0 号为旋转（det=+1，恒等）")
	check(jt.call("apply_transform", Vector3i(3, -2, 5), 0) == Vector3i(3, -2, 5),
		"枚举：0 号 = 恒等变换")
	var all_unit: bool = true
	var all_axes: bool = true
	var sigs: Dictionary = {}
	for idx: int in range(48):
		var ex: Vector3i = jt.call("apply_transform", Vector3i(1, 0, 0), idx)
		var ey: Vector3i = jt.call("apply_transform", Vector3i(0, 1, 0), idx)
		var ez: Vector3i = jt.call("apply_transform", Vector3i(0, 0, 1), idx)
		for v: Vector3i in [ex, ey, ez]:
			if absi(v.x) + absi(v.y) + absi(v.z) != 1:
				all_unit = false
		var ax: int = _axis_of(ex)
		var ay: int = _axis_of(ey)
		var az: int = _axis_of(ez)
		if ax == ay or ay == az or ax == az:
			all_axes = false
		sigs["%d,%d,%d|%d,%d,%d|%d,%d,%d" % [ex.x, ex.y, ex.z, ey.x, ey.y, ey.z, ez.x, ez.y, ez.z]] = true
	check(all_unit, "枚举：每个变换把基向量映到 ±基向量（符号置换矩阵）")
	check(all_axes, "枚举：三列打到三个不同轴（可逆置换）")
	check_eq(sigs.size(), 48, "枚举：48 变换两两不同（矩阵签名无重复）")
	var rt_ok: bool = true
	for idx: int in range(48):
		var probe := Vector3i(3, -2, 5)
		var back: Vector3i = jt.call("apply_inverse", jt.call("apply_transform", probe, idx), idx)
		if back != probe:
			rt_ok = false
	check(rt_ok, "枚举：apply_inverse∘apply_transform = 恒等（48 个全部可逆）")

	# ---- 2. are_equivalent：平移归一 + 48 变换等价判定 ----
	# L 三格基准形（2×2 缺一角）
	var T: Dictionary = {Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true, Vector3i(1, 1, 0): true}
	check(jt.call("are_equivalent", T, T.duplicate()) == true, "等价：自身恒等 → true")
	# 绕水平轴翻转（凸凹互换）：y 取反后自然平移
	var flip_y: Dictionary = {Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true, Vector3i(1, -1, 0): true}
	check(jt.call("are_equivalent", flip_y, T) == true, "等价：绕水平轴翻转（凸凹互换）→ true")
	# 镜像：x 取反
	var mir_x: Dictionary = {Vector3i(0, 0, 0): true, Vector3i(-1, 0, 0): true, Vector3i(-1, 1, 0): true}
	check(jt.call("are_equivalent", mir_x, T) == true, "等价：镜像（x 取反）→ true")
	# 绕 z 轴 90° 旋转：(x,y)→(−y,x)
	var rot_z: Dictionary = {Vector3i(0, 0, 0): true, Vector3i(0, 1, 0): true, Vector3i(-1, 1, 0): true}
	check(jt.call("are_equivalent", rot_z, T) == true, "等价：绕 z 轴 90° 旋转 → true")
	# 平移偏移（位置无关）
	var shifted: Dictionary = {Vector3i(5, 7, 2): true, Vector3i(6, 7, 2): true, Vector3i(6, 8, 2): true}
	check(jt.call("are_equivalent", shifted, T) == true, "等价：平移偏移（位置无关）→ true")
	# 组合：翻转 + 平移
	var combo: Dictionary = {Vector3i(3, 1, 0): true, Vector3i(4, 1, 0): true, Vector3i(4, 0, 0): true}
	check(jt.call("are_equivalent", combo, T) == true, "等价：翻转+平移组合 → true")
	# 非等价：同为 3 格但形状不同（直线 vs L）
	var line3: Dictionary = {Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true, Vector3i(2, 0, 0): true}
	check(jt.call("are_equivalent", line3, T) == false, "等价：直线 3 格 vs L 3 格 → false")
	# 非等价：尺寸不同
	check(jt.call("are_equivalent", {Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true}, T) == false,
		"等价：尺寸不同 → false")
	# 手性三脚架：偶角关节 vs 镜像奇角关节（旋转群不可达、镜像可达——48 变换含镜像故等价）
	var tripod_even: Dictionary = {Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true,
		Vector3i(0, 1, 0): true, Vector3i(0, 0, 1): true}
	var tripod_mir: Dictionary = {Vector3i(1, 0, 0): true, Vector3i(0, 0, 0): true,
		Vector3i(1, 1, 0): true, Vector3i(1, 0, 1): true}
	check(jt.call("are_equivalent", tripod_mir, tripod_even) == true,
		"等价：手性形状镜像（纯旋转不可达）48 变换含镜像 → true")
	# 空集 / 单格边界
	check(jt.call("are_equivalent", {}, {}) == true, "等价：空对空 → true")
	check(jt.call("are_equivalent", {Vector3i(9, 9, 9): true}, {Vector3i(-3, 4, 1): true}) == true,
		"等价：单格异位 → true（平移归一）")
	check(jt.call("are_equivalent", {Vector3i(0, 0, 0): true}, {}) == false, "等价：空对非空 → false")

	# ---- 3. evaluate_join 判定顺序（经 level_scene 纯静态复验，spec §6.1）----
	if ls != null:
		var tgt_lshape: Array = [["0,0,0", "1,0,0", "1,1,0"]]
		var jn_far: Array = ["7,7,7"]
		check_eq(String(ls.call("evaluate_join", flip_y, tgt_lshape, jn_far)), "success",
			"判定：绕水平轴翻转（凸凹互换）→ success")
		check_eq(String(ls.call("evaluate_join", mir_x, tgt_lshape, jn_far)), "success",
			"判定：镜像形状 → success")
		check_eq(String(ls.call("evaluate_join", shifted, tgt_lshape, jn_far)), "success",
			"判定：同形异位（平移归一）→ success")
		# 等价但与 join_voxels 干涉 → success（用户实测场景：翻转挖法与固定件干涉此前被误判 unfit）
		check_eq(String(ls.call("evaluate_join", flip_y, tgt_lshape, ["0,0,0", "1,0,0"])), "success",
			"判定：等价优先于干涉——翻转形状与固定件交叠仍 success（用户实测场景）")
		check_eq(String(ls.call("evaluate_join", line3, tgt_lshape, jn_far)), "wrong",
			"判定：非等价（直线 vs L）且无干涉 → wrong")
		check_eq(String(ls.call("evaluate_join", line3, tgt_lshape, ["0,0,0"])), "unfit",
			"判定：非等价且与固定件干涉 → unfit")
		check_eq(String(ls.call("evaluate_join", {}, tgt_lshape, [])), "wrong",
			"判定：空 remaining → wrong")
		check_eq(String(ls.call("evaluate_join", flip_y, [["9,9,9"], ["0,0,0", "1,0,0", "1,1,0"]], jn_far)), "success",
			"判定：多解 target_shapes 第二项经翻转命中 → success")

	# ---- 4. best_diff：最佳变换差集 + 逆变换映射回玩家坐标系 ----
	# 4a. 等价形状 → 红绿皆空（防「显示差异但实际能通关」误导）
	var d_eq: Dictionary = jt.call("best_diff", flip_y, T)
	check_eq((d_eq["extra"] as Array).size(), 0, "差集：等价形状 extra 为空")
	check_eq((d_eq["missing"] as Array).size(), 0, "差集：等价形状 missing 为空")
	# 4b. 恒等最佳：2 格线 vs 3 格线 → missing=[(2,0,0)]（沿玩家线延伸方向）
	var d_line: Dictionary = jt.call("best_diff",
		{Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true},
		{Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true, Vector3i(2, 0, 0): true})
	check((d_line["missing"] as Array).size() == 1 and (d_line["missing"] as Array).has(Vector3i(2, 0, 0)),
		"差集：缺 1 格 missing=[(2,0,0)]（恒等最佳，无需映射）")
	check_eq((d_line["extra"] as Array).size(), 0, "差集：缺 1 格无多余")
	# 4c. 多余格直出：T ∪ {(9,9,9)} → extra=[(9,9,9)]、missing 空（missing=0 已最优，恒等为首）
	var merged_t9: Dictionary = T.duplicate()
	merged_t9[Vector3i(9, 9, 9)] = true
	var d_extra: Dictionary = jt.call("best_diff", merged_t9, T)
	check((d_extra["extra"] as Array).size() == 1 and (d_extra["extra"] as Array).has(Vector3i(9, 9, 9)),
		"差集：多余 1 格 extra=[(9,9,9)]（玩家系直出）")
	check_eq((d_extra["missing"] as Array).size(), 0, "差集：多余 1 格 missing 空")
	# 4d. 强制镜像最佳（手性三脚架缺关节格）：missing 逆变换映射回玩家坐标系。
	# player = 镜像三脚架去掉关节 (1,0,0) → 恒等差集很差（missing=3），最佳变换为 x 镜像，
	# target 关节 (0,0,0) 的缺失处映射回玩家系 = (1,0,0)（玩家挖掉的关节位，绿 ghost 落此）。
	var P5: Dictionary = {Vector3i(0, 0, 0): true, Vector3i(1, 1, 0): true, Vector3i(1, 0, 1): true}
	var d_mir: Dictionary = jt.call("best_diff", P5, tripod_even)
	check_eq((d_mir["extra"] as Array).size(), 0, "差集·映射：镜像最佳下无多余格")
	check((d_mir["missing"] as Array).size() == 1 and (d_mir["missing"] as Array).has(Vector3i(1, 0, 0)),
		"差集·映射：missing 逆变换映射回玩家系 (1,0,0)（关节位，绿 ghost 落玩家可操作格）")
	check(int(d_mir["transform"]) != 0, "差集·映射：最佳变换非恒等（强制镜像情形）")
	# 确定性：并列取枚举序首个——重复调用结果一致
	var d_mir2: Dictionary = jt.call("best_diff", P5, tripod_even)
	check((d_mir2["missing"] as Array) == (d_mir["missing"] as Array)
		and (d_mir2["extra"] as Array) == (d_mir["extra"] as Array)
		and int(d_mir2["transform"]) == int(d_mir["transform"]),
		"差集·映射：重复调用结果确定（missing 最小→extra 更小→枚举序首个）")
	# 4d'. 并列决断真实钉住（P2-1 回修）：player=3 连线 vs target=角在原点的 L 三格。
	# 最优计数必为 (ms,ex)=(1,1)——ms=0 或 ex=0 都要求两形等价（3=3 格），而线≠L。
	# 手工枚举验证并列真实存在且映射可区分：idx 0（恒等）与 idx 4（(x,y,z)→(−x,y,z) x 镜像）
	# 把连线归一后都映成 x 向 3 连线，与 L0 恰好共享 (0,0,0)/(1,0,0) 两格，均得 (1,1)；
	# 但未命中目标格 (0,1,0) 逆映射回玩家系不同：idx 0 → (0,1,0)，idx 4 → (2,1,0)
	# （x 镜像把 x=0 翻到 x=2，(0,1,0) 不在镜像对称面上）。规格 §6.1「仍并列取枚举序首个」
	# → best_diff 必须返回 idx 0 的映射，而非任何更靠后并列变换的映射。
	var L0: Dictionary = {Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true, Vector3i(0, 1, 0): true}
	var n_line: Dictionary = jt.call("normalize_cells", line3)
	var n_l0: Dictionary = jt.call("normalize_cells", L0)
	var tie_ok := true
	for i_tie: int in [0, 4]:
		var tp_t: Dictionary = jt.call("transformed_normalized", n_line, i_tie)
		var ex_t: int = 0
		var ms_t: int = 0
		for k_t: Variant in tp_t:
			if not n_l0.has(k_t):
				ex_t += 1
		for k_t: Variant in n_l0:
			if not tp_t.has(k_t):
				ms_t += 1
		if ex_t != 1 or ms_t != 1:
			tie_ok = false
	check(tie_ok, "差集·并列钉住：idx 0 与 idx 4 两个不同变换均取得最优 (ms,ex)=(1,1)（并列真实存在）")
	# 并列变换 idx 4 若被选中，missing 映射 =(2,1,0)（按 §6.1 逆变换式独立对具体格计算），
	# 与 idx 0 的 (0,1,0) 不同 → 该形状对足以区分「取枚举序首个」与「取其他并列变换」。
	var tp4_raw: Dictionary = jt.call("transform_cells", n_line, 4)
	var m_tp4: Vector3i = jt.call("min_corner", tp4_raw)
	var miss4 := Vector3i(99, 99, 99)
	for k4: Variant in n_l0:
		var m4: Vector3i = k4
		if not tp4_raw.has(m4 + m_tp4):
			miss4 = jt.call("apply_inverse", m4 + m_tp4, 4)
	check(miss4 == Vector3i(2, 1, 0),
		"差集·并列钉住：并列变换 idx 4 的 missing 映射 =(2,1,0)≠idx 0 的 (0,1,0)（并列映射坐标可区分）")
	var d_tie: Dictionary = jt.call("best_diff", line3, L0)
	check_eq(int(d_tie["transform"]), 0, "差集·并列钉住：仍并列取枚举序首个 → transform=0（恒等，非更靠后并列变换）")
	check((d_tie["missing"] as Array).size() == 1 and (d_tie["missing"] as Array).has(Vector3i(0, 1, 0)),
		"差集·并列钉住：missing=[(0,1,0)]（枚举序首个变换的玩家系映射，绿 ghost 落玩家可补角格）")
	check((d_tie["extra"] as Array).size() == 1 and (d_tie["extra"] as Array).has(Vector3i(2, 0, 0)),
		"差集·并列钉住：extra=[(2,0,0)]（玩家系线端多余格，红 mark 落玩家可操作格）")
	# 4e. extra 逆变换映射：镜像三脚架加一格杂散 (0,1,0) → 最佳变换为镜像，extra 映射回玩家杂散格
	var P8: Dictionary = {
		Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true, Vector3i(1, 1, 0): true,
		Vector3i(1, 0, 1): true, Vector3i(0, 1, 0): true}
	var d_ex8: Dictionary = jt.call("best_diff", P8, tripod_even)
	check_eq((d_ex8["missing"] as Array).size(), 0, "差集·映射：镜像最佳下 missing 为空")
	check((d_ex8["extra"] as Array).size() == 1 and (d_ex8["extra"] as Array).has(Vector3i(0, 1, 0)),
		"差集·映射：extra 逆变换映射回玩家系 (0,1,0)（红 mark 落玩家实际多余格）")
	# 4f. 平移归一：同一形状位置偏移后挖缺 1 格，missing 仍正确映射回玩家系
	var d_sh: Dictionary = jt.call("best_diff",
		{Vector3i(4, 2, 1): true, Vector3i(5, 2, 1): true},
		{Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true, Vector3i(2, 0, 0): true})
	check((d_sh["missing"] as Array).size() == 1 and (d_sh["missing"] as Array).has(Vector3i(6, 2, 1)),
		"差集·平移：缺格映射回玩家系 (6,2,1)（沿玩家线延伸方向）")
	# 4g. 空集边界（退回原坐标直出旧口径）
	var d_e1: Dictionary = jt.call("best_diff", {}, tripod_even)
	check_eq((d_e1["extra"] as Array).size(), 0, "差集·空玩家：extra 空")
	check_eq((d_e1["missing"] as Array).size(), 4, "差集·空玩家：missing=target 全部（原坐标）")
	var d_e2: Dictionary = jt.call("best_diff", tripod_even, {})
	check_eq((d_e2["extra"] as Array).size(), 4, "差集·空目标：extra=player 全部（原坐标）")
	check_eq((d_e2["missing"] as Array).size(), 0, "差集·空目标：missing 空")

	# ---- 5. 平移归一 / 单格 / 满块边界 ----
	var nrm: Dictionary = jt.call("normalize_cells", {Vector3i(2, 3, 4): true, Vector3i(5, 1, 6): true})
	check(nrm.size() == 2 and nrm.has(Vector3i(0, 2, 0)) and nrm.has(Vector3i(3, 0, 2)),
		"归一：包围盒最小角平移到原点")
	check_eq((jt.call("normalize_cells", {}) as Dictionary).size(), 0, "归一：空集 → 空集")
	var full: Dictionary = {}
	for x: int in 2:
		for y: int in 2:
			for z: int in 2:
				full[Vector3i(x, y, z)] = true
	check(jt.call("are_equivalent", full, full) == true, "满块：2×2×2 自身等价")
	var full_shift_flip: Dictionary = {}
	for x: int in 2:
		for y: int in 2:
			for z: int in 2:
				full_shift_flip[Vector3i(10 - x, 20 + y, 30 - z)] = true
	check(jt.call("are_equivalent", full_shift_flip, full) == true, "满块：2×2×2 平移+镜像后仍等价")
	var d_full: Dictionary = jt.call("best_diff", full_shift_flip, full)
	check_eq((d_full["extra"] as Array).size() + (d_full["missing"] as Array).size(), 0,
		"满块：等价差集红绿皆空")

	finish()
