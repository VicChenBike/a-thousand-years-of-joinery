extends "res://tests/test_base.gd"
## test_playtest_judge：三分支判定（规格 §11.2 行 3）。
## 期望值以游戏 evaluate_join（level_scene.gd:1941-1952，基线 b0cc039）实测输出为金标准
## 固化进本文件（编辑器工程内自持，不跨工程引用）。判定序：空→wrong → 48 变换等价任一
## target→success（等价优先于干涉，level_scene.gd:1935-1936 实况）→ 与 join 原坐标有交集
## →unfit → 否则 wrong。

const J := preload("res://scripts/playtest_judge.gd")
const JX := preload("res://scripts/join_transform.gd")

func _initialize() -> void:
	_empty_and_basic()
	_equivalence_cases()
	_priority_and_branches()
	finish()

func _l_dict() -> Dictionary:
	return {Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true, Vector3i(0, 1, 0): true}

# ============ 组 1：空集与元素兼容（5 checks） ============
func _empty_and_basic() -> void:
	var l_arr: Array = ["0,0,0", "1,0,0", "0,1,0"]
	check_eq(J.judge({}, [l_arr], []), "wrong", "组1: 空集→wrong（空块无物可接）")
	check_eq(J.judge(_l_dict(), [], []), "wrong", "组1: target 数组空→wrong")
	check_eq(J.judge(_l_dict(), [[]], []), "wrong", "组1: target 空形状→wrong")
	check_eq(J.judge(_l_dict(), [l_arr], []), "success", "组1: 字符串坐标元素兼容")
	check_eq(J.judge({}, [], ["0,0,0"]), "wrong", "组1: 空集优先于一切分支（含 join 非空）")

# ============ 组 2：48 变换等价（3 checks） ============
func _equivalence_cases() -> void:
	var moved: Dictionary = {Vector3i(2, 3, 1): true, Vector3i(3, 3, 1): true, Vector3i(2, 4, 1): true}
	check_eq(J.judge(moved, [["0,0,0", "1,0,0", "0,1,0"]], []), "success", "组2: 平移归一后等价→success")
	var mirrored: Dictionary = {Vector3i(1, 0, 0): true, Vector3i(0, 0, 0): true, Vector3i(1, 1, 0): true}
	check_eq(J.judge(mirrored, [["0,0,0", "1,0,0", "0,1,0"]], []), "success", "组2: 镜像等价→success（24 镜像族）")
	var all_tf := true
	for idx: int in [1, 7, 23, 47]:
		var tf: Dictionary = JX.transform_cells(_l_dict(), idx)
		if J.judge(tf, [["0,0,0", "1,0,0", "0,1,0"]], []) != "success":
			all_tf = false
	check(all_tf, "组2: 变换族抽样 1/7/23/47 全等价→success")

# ============ 组 3：等价优先于干涉 + unfit/wrong 分支（6 checks） ============
func _priority_and_branches() -> void:
	var moved: Dictionary = {Vector3i(2, 3, 1): true, Vector3i(3, 3, 1): true, Vector3i(2, 4, 1): true}
	var join_overlap: Array = ["3,3,1", "9,9,9"]
	check_eq(J.judge(moved, [["0,0,0", "1,0,0", "0,1,0"]], join_overlap), "success", "组3: 等价优先于干涉（与 join 相交仍 success，level_scene.gd:1935-1936 实况）")
	var two_shapes: Array = [["0,0,0", "1,0,0", "0,1,0"], ["7,7,7", "8,7,7", "7,8,7"]]
	var second: Dictionary = {Vector3i(7, 7, 7): true, Vector3i(8, 7, 7): true, Vector3i(7, 8, 7): true}
	check_eq(J.judge(second, two_shapes, []), "success", "组3: 遍历全部 target_shapes（多答案判定侧支持）")
	var r2: Dictionary = {Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true}
	check_eq(J.judge(r2, [["5,5,5"]], ["1,0,0", "2,0,0"]), "unfit", "组3: 原坐标交集→unfit（干涉）")
	var vec3_keys: Dictionary = {Vector3(2, 3, 1): true, Vector3(3, 3, 1): true, Vector3(2, 4, 1): true}
	check_eq(J.judge(vec3_keys, [["0,0,0", "1,0,0", "0,1,0"]], []), "success", "组3: Vector3 元素兼容")
	check_eq(J.judge({Vector3i(5, 5, 5): true}, [["0,0,0", "1,0,0", "0,1,0"]], ["9,9,9"]), "wrong", "组3: 不等价不干涉→wrong")
	check_eq(J.judge(r2, [["5,5,5"]], ["3,0,0"]), "wrong", "组3: 归一后相交但原坐标不相交→wrong（unfit 只看原坐标）")
