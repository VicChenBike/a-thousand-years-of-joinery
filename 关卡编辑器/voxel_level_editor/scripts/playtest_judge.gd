extends RefCounted
## 关卡编辑器·纯逻辑层：试玩对接三分支判定（规格 §6.2 行 3 / §8.3）。
## 判定序逐行照抄游戏 evaluate_join（level_scene.gd:1941-1952，基线 b0cc039）：
## ①剩余集为空 → wrong（空块无物可接，保证非 success）；
## ②与任一 target 经 48 种正交变换等价（平移归一，JoinXform.are_equivalent）→ success
##   ——**等价优先于干涉**（翻转/镜像挖法与固定件干涉不误判，level_scene.gd:1935-1936 实况）；
## ③与 join_voxels **在原坐标**有交集 → unfit（无法对接：与固定件干涉，不平移归一）；
## ④否则 → wrong（答案错误：能放上但形状不是答案）。
## 元素兼容 Vector3i/Vector3/"x,y,z" 字符串；非法元素跳过。判定瞬时完成、无容差、无次数限制。
## 不做 final_answer 语义校验（契约不强制、用户拍板 3 不做自动联动）。

const JoinXform := preload("res://scripts/join_transform.gd")
const RESULT_SUCCESS := "success"
const RESULT_UNFIT := "unfit"
const RESULT_WRONG := "wrong"

const _BAD_CELL := Vector3i(1 << 21, 1 << 21, 1 << 21)

static func judge(remaining: Dictionary, target_shapes: Array, join_voxels: Array) -> String:
	var p := _cell_set(remaining.keys())
	if p.is_empty():
		return RESULT_WRONG
	for shape_v: Variant in target_shapes:
		if shape_v is Array and JoinXform.are_equivalent(p, _cell_set(shape_v)):
			return RESULT_SUCCESS
	var j := _cell_set(join_voxels)
	for k: Variant in p:
		if j.has(k):
			return RESULT_UNFIT
	return RESULT_WRONG

## 坐标元素归一化为 Vector3i 集合（level_scene.gd:1957-1963 随迁）。
static func _cell_set(cells: Array) -> Dictionary:
	var out: Dictionary = {}
	for v: Variant in cells:
		var c := _parse_cell(v)
		if c != _BAD_CELL:
			out[c] = true
	return out

static func _parse_cell(v: Variant) -> Vector3i:
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
