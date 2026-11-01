extends RefCounted
## 批次 N1（spec §5.1/§6.1）：对接判定与锐眼差集共用的 48 种正交变换等价工具——单一真相源。
## 纯静态、无场景依赖；level_scene.evaluate_join / diff_vs_target 一律经本文件实现，
## 防止两处口径漂移导致「锐眼显示差异但实际能通关」的误导（用户 2026-09-09 拍板红线）。
##
## 数学口径：
## - 48 变换 = 全部 3×3 带符号置换矩阵：输出第 i 轴分量 = signs[i] × 输入第 perm[i] 轴分量。
##   6 个排列 × 8 个符号组合；det = 排列奇偶 × ∏signs：det=+1 的 24 个为旋转、det=−1 的
##   24 个为镜像（含旋转镜像）。枚举序确定：idx = 排列序 × 8 + 符号序，恒等 = 0 号。
## - 平移归一：集合包围盒最小角平移到原点——旋转/镜像必须在归一坐标系下比较才有定义，
##   语义即「木块不分正反，形状一致即通关」（位置无关）。
## - 等价判定 are_equivalent：双方归一后，任一变换把一方归一集映到另一方归一集 → 等价。
## - 最佳变换差集 best_diff：取 missing 数最小的变换（并列取 extra 更小者，仍并列取枚举序
##   首个，保证确定性）；extra/missing 经逆变换映射回玩家木料当前坐标系（红 mark/绿 ghost
##   落在玩家实际可操作格上）；等价形状 → 红绿皆空。
##
## 契约：入参 Dictionary 键必须已归一为 Vector3i（level_scene._cell_set 负责字符串/Vector3
## 转换），值忽略（集合语义）。

const TRANSFORM_COUNT := 48

## 排列表（输出轴 i 取输入轴 PERMS[idx/8][i] 分量），奇偶性：偶/奇/奇/偶/偶/奇。
const PERMS := [
	Vector3i(0, 1, 2),
	Vector3i(0, 2, 1),
	Vector3i(1, 0, 2),
	Vector3i(1, 2, 0),
	Vector3i(2, 0, 1),
	Vector3i(2, 1, 0),
]

## 符号表（每轴 ±1），idx%8 选择；全 +1 为不反射。
const SIGNS := [
	Vector3i(1, 1, 1), Vector3i(1, 1, -1), Vector3i(1, -1, 1), Vector3i(1, -1, -1),
	Vector3i(-1, 1, 1), Vector3i(-1, 1, -1), Vector3i(-1, -1, 1), Vector3i(-1, -1, -1),
]

## 第 idx 号变换的排列（输出轴 i ← 输入轴 perm[i]）。
static func perm_of(idx: int) -> Vector3i:
	return PERMS[idx >> 3]

## 第 idx 号变换的轴符号（±1）。
static func signs_of(idx: int) -> Vector3i:
	return SIGNS[idx % 8]

## 变换行列式：+1 旋转 / −1 镜像（排列奇偶 × 符号积）。
static func det_of(idx: int) -> int:
	var p := perm_of(idx)
	var inv := 0
	var arr: Array = [p.x, p.y, p.z]
	for i: int in 3:
		for j: int in range(i + 1, 3):
			if arr[i] > arr[j]:
				inv += 1
	var s := signs_of(idx)
	var parity := 1 if inv % 2 == 0 else -1
	return parity * s.x * s.y * s.z

## 正变换：out[i] = signs[i] × c[perm[i]]。
static func apply_transform(c: Vector3i, idx: int) -> Vector3i:
	var p := perm_of(idx)
	var s := signs_of(idx)
	var v: Array = [c.x, c.y, c.z]
	return Vector3i(s.x * v[p.x], s.y * v[p.y], s.z * v[p.z])

## 逆变换：y_i = signs[i] × x_{perm[i]} ⇒ x_{perm[i]} = signs[i] × y_i（符号自逆）。
static func apply_inverse(c: Vector3i, idx: int) -> Vector3i:
	var p := perm_of(idx)
	var s := signs_of(idx)
	var v: Array = [c.x, c.y, c.z]
	var out: Array = [0, 0, 0]
	out[p.x] = s.x * v[0]
	out[p.y] = s.y * v[1]
	out[p.z] = s.z * v[2]
	return Vector3i(out[0], out[1], out[2])

## 集合最小角（包围盒负向角；空集未定义，调用方保证非空或先行判空）。
static func min_corner(cells: Dictionary) -> Vector3i:
	var mn := Vector3i(1 << 30, 1 << 30, 1 << 30)
	for k: Variant in cells:
		var c: Vector3i = k
		mn = Vector3i(mini(mn.x, c.x), mini(mn.y, c.y), mini(mn.z, c.z))
	return mn

## 平移归一：包围盒最小角平移到原点（空集返回空集）。
static func normalize_cells(cells: Dictionary) -> Dictionary:
	if cells.is_empty():
		return {}
	var mn := min_corner(cells)
	var out: Dictionary = {}
	for k: Variant in cells:
		var c: Vector3i = k
		out[c - mn] = true
	return out

## 变换整个集合（不归一；键为 Vector3i）。
static func transform_cells(cells: Dictionary, idx: int) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in cells:
		out[apply_transform(k, idx)] = true
	return out

## 变换后归一（等价比较的标准形式）。
static func transformed_normalized(cells: Dictionary, idx: int) -> Dictionary:
	return normalize_cells(transform_cells(cells, idx))

## 集合相等（无序、键去重）。
static func sets_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k: Variant in a:
		if not b.has(k):
			return false
	return true

## 等价判定：双方平移归一后，经 48 变换之一集合相等 → true。
## 两个空集视为等价（数学一致性）；单空非空 → false；尺寸不同直接 false（变换不改格数）。
static func are_equivalent(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	if a.is_empty():
		return true
	var na := normalize_cells(a)
	var nb := normalize_cells(b)
	for idx: int in TRANSFORM_COUNT:
		if sets_equal(transformed_normalized(na, idx), nb):
			return true
	return false

## 最佳变换差集（锐眼红绿口径，spec §6.1）：
## 在 48 变换中取「missing 数最小」（并列取 extra 更小者，仍并列取枚举序首个）的变换，
## 在该变换下计算 player 相对 target 的多余（extra）/缺少（missing），均映射回玩家木料
## 当前坐标系。返回 {extra: Array[Vector3i], missing: Array[Vector3i], transform: int}。
## 边界：任一方为空 → 退回原坐标直出（无变换可归一；extra/missing = 非空一方全部原键），
## 与旧口径 diff_vs_target 的空集行为一致。
static func best_diff(player: Dictionary, target: Dictionary) -> Dictionary:
	if player.is_empty() or target.is_empty():
		var ex0: Array = []
		var ms0: Array = []
		for k: Variant in player:
			ex0.append(k)
		for k: Variant in target:
			ms0.append(k)
		return {"extra": ex0, "missing": ms0, "transform": 0}
	var np := normalize_cells(player)
	var nt := normalize_cells(target)
	var minp := min_corner(player)
	# 扫全部 48 变换，取 (missing, extra) 字典序最小者；idx 升序扫描保证「仍并列取枚举序首个」。
	var best_idx := 0
	var best_missing := 1 << 30
	var best_extra := 1 << 30
	for idx: int in TRANSFORM_COUNT:
		var tp := transformed_normalized(np, idx)
		var ex := 0
		var ms := 0
		for k: Variant in tp:
			if not nt.has(k):
				ex += 1
		for k: Variant in nt:
			if not tp.has(k):
				ms += 1
		if ms < best_missing or (ms == best_missing and ex < best_extra):
			best_missing = ms
			best_extra = ex
			best_idx = idx
			if ms == 0 and ex == 0:
				break  # 完全等价：枚举序最前的等价变换即最佳，提前收
	# 以最佳变换重算差集并映射回玩家坐标系：
	# - 玩家归一格 c → 变换归一系位置 f = M(c) − m_tp；f ∉ nt ⇒ c 为多余，extra 玩家原坐标 = c + minp；
	# - target 归一格 m 无处匹配 ⇒ 缺少，missing 玩家系 = M⁻¹(m + m_tp) + minp（m + m_tp 为
	#   该变换下未命中的原始变换位，逆变换还原为玩家归一格再加回玩家平移）。
	var tp_raw := transform_cells(np, best_idx)
	var m_tp := min_corner(tp_raw)
	var extra: Array = []
	var missing: Array = []
	for k: Variant in np:
		var c: Vector3i = k
		var f: Vector3i = apply_transform(c, best_idx) - m_tp
		if not nt.has(f):
			extra.append(c + minp)
	for m_v: Variant in nt:
		var m: Vector3i = m_v
		if not tp_raw.has(m + m_tp):
			missing.append(apply_inverse(m + m_tp, best_idx) + minp)
	return {"extra": extra, "missing": missing, "transform": best_idx}
