extends "res://tests/test_base.gd"
## 批次 V（V-E3）主游戏按域校验/净化/渲染测试（规格 §9.5 + 任务硬性口径 3~5）。
## 红态定义=对按域前实现必红（全部走既有 validate_level / 场景实例化 API，红期可编译零中止）：
##   P1 四域各自尺寸裁剪真值表——超「各自域」的格被裁、他域不受影响（旧实现全按 block_size 必红）；
##   P2 target_size 缺失回落 block_size（等价锚：旧档行为不变，红期即绿）；
##   P3 join/final size 字段被消费——join.size≠block_size 的档不再按 block_size 裁剪（红）；
##   P4 各域 size 每维 1~32 校验 + 错误信息注明域（红；block_size 域文案「体素尺寸越界」保持为等价锚）；
##   P5 拒载语义按域保持（等价锚：target/join/final 空/过滤后空拒载文案逐字保持；blocks 空=现状不拒载，
##      读码实况对齐——validate_level 现状无 blocks 空拒载分支，任务括注「blocks 空仍拒载」与代码
##      实况不符，按「不得改变既有行为」口径以代码为准并在实施报告留痕）；
##   P6 旧格式档（无 target_size）与现状逐字节等价（等价锚：hemudu 实档四域格数+ok+零警告逐项钉值；
##      另有 tests/probe_domains_temp.gd 改前/改后 dump diff=0 行佐证）；
##   P7 三视图按域渲染——注入 chapter=9 四域异值关实例化 level_scene：Join 视图构建
##      join_part.size 界内格（超 block_size 格红：旧实现 build_voxels 全按 block_size 必红）；
##      Target 视图按 **final_answer.size** 域构建 final 界内格且**不再渲染 target 格**
##      （批次 Z Z1 spec §1 换源，红：旧实现渲染 target_shapes 按 target_size 过滤）；
##      _voxel_size 仍锚 blocks 域（挖除/拾取/锐眼差集现状不变，等价锚）；侧视拾取尺寸按域
##      缓存（_view_sizes，Z1：Target=final 域，红）。
## 清档纪律：本测试零触碰 user://（纯校验+场景实例化，SaveManager 仅读 chapter=9 空断点）；
## 场景注入关卡 chapter=9 避让现网 1~5，测毕弹出还原。Godot 4.7 坑对齐（spec §14）：
## JSON 回析数值恒 float；字典取键一律 .get 防御（坑 2）；场景断言先 set_context 再 add_child
## （T14 约定，test_level_scene 先例）。

const LIB_SCRIPT := "res://autoload/level_library.gd"
const SCENE_PATH := "res://scenes/level/level_scene.tscn"

func _initialize() -> void:
	print("== test_v_level_library_domains ==")
	_p1_per_domain_clip_truth_table()
	_p2_target_size_missing_fallback()
	_p3_join_final_size_consumed()
	_p4_domain_size_validation()
	_p5_reject_semantics_preserved()
	_p6_legacy_doc_byte_equivalence()
	await _p7_scene_per_domain_build()
	finish()

# ---------- helper ----------
func _new_lib() -> Node:
	var ll: Node = (load(LIB_SCRIPT) as GDScript).new()
	get_root().add_child(ll)
	return ll

## 四域异值构造档（可逐字段覆盖）：block_size 2×1×1 / target_size 4×4×4 / join.size 3×1×1 /
## final.size 2×1×1 为缺省；override 键=块内键覆盖。
func _domain_doc(overrides: Dictionary = {}) -> Dictionary:
	var piece: Dictionary = {
		"piece_id": "p1",
		"block_size": {"x": 2, "y": 1, "z": 1},
		"target_size": {"x": 4, "y": 4, "z": 4},
		"initial_voxels": true,
		"blocks": ["0,0,0", "1,0,0", "2,0,0"],
		"target_shapes": [["3,0,0", "1,0,0", "9,0,0"]],
		"join_part": {"size": {"x": 3, "y": 1, "z": 1}, "voxels": ["2,0,0", "1,0,0", "5,0,0"]},
		"final_answer": {"size": {"x": 2, "y": 1, "z": 1}, "voxels": ["1,0,0", "2,0,0", "8,0,0"]},
	}
	for k: Variant in overrides:
		piece[str(k)] = overrides[k]
	return {"format_version": 1, "chapter": 1, "title": "域测试", "pieces": [piece]}

func _piece_of(result: Dictionary) -> Dictionary:
	var lvl: Dictionary = result.get("level", {})
	var pieces: Array = lvl.get("pieces", [])
	if pieces.is_empty() or not (pieces[0] is Dictionary):
		return {}
	return pieces[0]

func _set_of(arr: Array) -> Dictionary:
	var d: Dictionary = {}
	for v: Variant in arr:
		if v is Vector3i:   # get_built_cells 返回 Vector3i 数组（validate 侧为 "x,y,z" 串）——双形态归一
			var c: Vector3i = v
			d["%d,%d,%d" % [c.x, c.y, c.z]] = true
		else:
			d[String(v)] = true
	return d

# ============ P1 四域各自尺寸裁剪真值表（超各自域的格被裁、他域不受影响） ============
func _p1_per_domain_clip_truth_table() -> void:
	var ll := _new_lib()
	var r: Dictionary = ll.validate_level(_domain_doc())
	check(bool(r.get("ok", false)), "P1: 四域异值档通过校验（载入不拒载）")
	var piece := _piece_of(r)
	check(not piece.is_empty(), "P1: 净化后 piece 存在（前置）")
	if piece.is_empty():
		return
	# 真值表逐格：blocks 域（block_size 2×1×1）——"2,0,0" 超本域被裁；"0,0,0"/"1,0,0" 留。
	var bs := _set_of(piece.get("blocks", []))
	check(bs == {"0,0,0": true, "1,0,0": true},
		"P1: blocks 按 block_size 裁剪——(2,0,0) 被裁、(0,0,0)/(1,0,0) 保留（红：其余域不受 block 域联动）")
	# target 域（target_size 4×4×4）——"3,0,0" 超 block 域但界内本域 → 保留（按域核心断言）；
	# "9,0,0" 超本域被裁；"1,0,0" 留。
	var ts := _set_of((piece.get("target_shapes", [[]]) as Array)[0])
	check(ts == {"3,0,0": true, "1,0,0": true},
		"P1: target 按 target_size 裁剪——(3,0,0) 界内保留、(9,0,0) 被裁（红：旧实现按 block_size 裁掉 (3,0,0)）")
	# join 域（join.size 3×1×1）——"2,0,0" 超 block 域但界内本域 → 保留；"5,0,0" 裁。
	var js := _set_of((piece.get("join_part", {}) as Dictionary).get("voxels", []))
	check(js == {"2,0,0": true, "1,0,0": true},
		"P1: join 按 join_part.size 裁剪——(2,0,0) 界内保留、(5,0,0) 被裁（红：旧实现按 block_size 裁掉 (2,0,0)）")
	# final 域（final.size 2×1×1）——"2,0,0" 超 final 域被裁（他域 join 保留同格=互不影响对照）；
	# "8,0,0" 裁；"1,0,0" 留。
	var fs := _set_of((piece.get("final_answer", {}) as Dictionary).get("voxels", []))
	check(fs == {"1,0,0": true},
		"P1: final 按 final_answer.size 裁剪——(2,0,0)/(8,0,0) 被裁（join 域保留同格 (2,0,0)=逐域独立互不影响）")
	# 警告计数：blocks 1 + target 1 + join 1 + final 2 = 5（每裁一格一条，零额外警告）。
	check_eq((r.get("warnings", []) as Array).size(), 5,
		"P1: 越界净化警告 5 条（逐格一条，按域计数；旧实现 7 条必红）")

# ============ P2 target_size 缺失回落 block_size（等价锚：旧档零回归） ============
func _p2_target_size_missing_fallback() -> void:
	var ll := _new_lib()
	var doc := _domain_doc({"target_size": null})   # 键值 null → 实现侧等同键缺（回落）
	var piece0: Dictionary = doc["pieces"][0]
	piece0.erase("target_size")   # 整缺：旧格式档口径
	var r: Dictionary = ll.validate_level(doc)
	check(bool(r.get("ok", false)), "P2: 无 target_size 旧档载入 ok（缺失回落不拒载）")
	var piece := _piece_of(r)
	check(_set_of((piece.get("target_shapes", [[]]) as Array)[0]) == {"1,0,0": true},
		"P2: 缺 target_size 时 target 按 block_size 回落裁剪——(3,0,0) 被裁（等价锚：与现状逐字节等价）")
	check(_set_of((piece.get("join_part", {}) as Dictionary).get("voxels", []))
		== {"2,0,0": true, "1,0,0": true},
		"P2: 同档 join.size=3 仍被消费——(2,0,0) 保留（target 回落不影响 join 域独立口径）")

# ============ P3 join/final size 字段被消费（size≠block_size 档不再按 block_size 裁剪） ============
func _p3_join_final_size_consumed() -> void:
	var ll := _new_lib()
	# 同格 (2,0,0) 对照真值：join.size=2×1×1 → 裁；join.size=3×1×1 → 留（size 字段有效消费）。
	var r_small: Dictionary = ll.validate_level(_domain_doc({
		"join_part": {"size": {"x": 2, "y": 1, "z": 1}, "voxels": ["2,0,0", "1,0,0"]}}))
	check(_set_of((_piece_of(r_small).get("join_part", {}) as Dictionary).get("voxels", [])) == {"1,0,0": true},
		"P3: join.size=2×1×1 时 (2,0,0) 被裁（对照半边）")
	var r_big: Dictionary = ll.validate_level(_domain_doc())
	check(_set_of((_piece_of(r_big).get("join_part", {}) as Dictionary).get("voxels", []))
		== {"2,0,0": true, "1,0,0": true},
		"P3: join.size=3×1×1 时 (2,0,0) 保留——join.size 被消费，不再按 block_size 裁剪（红）")
	# final 对照：final.size=4×1×1 时 (2,0,0)/(3,0,0) 保留。
	var r_final: Dictionary = ll.validate_level(_domain_doc({
		"final_answer": {"size": {"x": 4, "y": 1, "z": 1}, "voxels": ["1,0,0", "2,0,0", "3,0,0"]}}))
	check(_set_of((_piece_of(r_final).get("final_answer", {}) as Dictionary).get("voxels", []))
		== {"1,0,0": true, "2,0,0": true, "3,0,0": true},
		"P3: final.size=4×1×1 时 (2,0,0)/(3,0,0) 保留——final.size 被消费（红）")

# ============ P4 各域 size 每维 1~32 校验 + 错误信息注明域 ============
func _p4_domain_size_validation() -> void:
	var ll := _new_lib()
	# target_size 越界 → 拒载且注明域。
	var r1: Dictionary = ll.validate_level(_domain_doc({"target_size": {"x": 0, "y": 4, "z": 4}}))
	check(not bool(r1.get("ok", true)), "P4: target_size 轴 0 → 拒载（红：旧实现无此校验）")
	check(String(r1.get("reject", "")).contains("target_size"), "P4: 拒载原因注明 target_size 域")
	var r2: Dictionary = ll.validate_level(_domain_doc({
		"join_part": {"size": {"x": 33, "y": 1, "z": 1}, "voxels": ["1,0,0"]}}))
	check(not bool(r2.get("ok", true)), "P4: join_part.size 轴 33 → 拒载")
	check(String(r2.get("reject", "")).contains("join_part"), "P4: 拒载原因注明 join_part.size 域")
	var r3: Dictionary = ll.validate_level(_domain_doc({
		"final_answer": {"size": {"x": 2, "y": 0, "z": 1}, "voxels": ["1,0,0"]}}))
	check(not bool(r3.get("ok", true)), "P4: final_answer.size 轴 0 → 拒载")
	check(String(r3.get("reject", "")).contains("final_answer"), "P4: 拒载原因注明 final_answer.size 域")
	# block_size 域：现状文案保持（等价锚）。
	var r4: Dictionary = ll.validate_level(_domain_doc({"block_size": {"x": 0, "y": 1, "z": 1}}))
	check(not bool(r4.get("ok", true)), "P4: block_size 轴 0 → 拒载（现状）")
	check_eq(String(r4.get("reject", "")), "体素尺寸越界", "P4: block_size 域拒载文案保持现状逐字（等价锚）")
	# 缺 size 的旧档（target_size 整缺 + join/final 无 size 键）→ 零新增校验（旧档零回归锚）。
	var legacy := _domain_doc()
	var lp: Dictionary = legacy["pieces"][0]
	lp.erase("target_size")
	lp["join_part"] = {"voxels": ["1,0,0"]}
	lp["final_answer"] = {"voxels": ["1,0,0"]}
	check(bool(ll.validate_level(legacy).get("ok", false)),
		"P4: 旧格式档（size 键全缺）零新增校验零拒载（缺失回落 block_size）")

# ============ P5 拒载语义按域保持（等价锚：文案逐字保持现状） ============
func _p5_reject_semantics_preserved() -> void:
	var ll := _new_lib()
	var r1: Dictionary = ll.validate_level(_domain_doc({"target_shapes": [[]]}))
	check_eq(String(r1.get("reject", "")), "target_shapes 为空", "P5: target 空拒载文案逐字保持")
	var r2: Dictionary = ll.validate_level(_domain_doc({"target_shapes": [["1,0,0"], []]}))
	check_eq(bool(r2.get("ok", false)), true,
		"P5: target 首形状非空（后续空形状）仍载入（现状：仅首形状空拒载）")
	var r3: Dictionary = ll.validate_level(_domain_doc({"join_part": {"size": {"x": 3, "y": 1, "z": 1}, "voxels": []}}))
	check_eq(String(r3.get("reject", "")), "join_part.voxels 为空", "P5: join 空拒载文案逐字保持")
	var r4: Dictionary = ll.validate_level(_domain_doc({"join_part": {"size": {"x": 3, "y": 1, "z": 1}, "voxels": ["99,0,0"]}}))
	check_eq(String(r4.get("reject", "")), "join_part 过滤后为空", "P5: join 过滤后空拒载文案逐字保持")
	var r5: Dictionary = ll.validate_level(_domain_doc({"final_answer": {"size": {"x": 2, "y": 1, "z": 1}, "voxels": []}}))
	check_eq(String(r5.get("reject", "")), "final_answer 为空", "P5: final 空拒载文案逐字保持")
	var r6: Dictionary = ll.validate_level(_domain_doc({"final_answer": {"size": {"x": 2, "y": 1, "z": 1}, "voxels": ["99,0,0"]}}))
	check_eq(String(r6.get("reject", "")), "final_answer 过滤后为空", "P6: final 过滤后空拒载文案逐字保持")
	# blocks 空 → 现状不拒载（读码实况：validate_level 无 blocks 空拒载分支，既有行为保持）。
	var r7: Dictionary = ll.validate_level(_domain_doc({"blocks": []}))
	check_eq(bool(r7.get("ok", false)), true, "P5: blocks 空不拒载（现状行为保持，读码实况对齐并留痕）")

# ============ P6 现网档钉值（批次 Z：编辑器五件套一次性快照导入；target_size 自带） ============
func _p6_legacy_doc_byte_equivalence() -> void:
	var ll := _new_lib()
	var f: FileAccess = FileAccess.open("res://levels_data/level_chapter1_hemudu.json", FileAccess.READ)
	check(f != null, "P6: 现网 hemudu 档可读（前置）")
	if f == null:
		return
	var doc: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var r: Dictionary = ll.validate_level(doc)
	check(bool(r.get("ok", false)), "P6: hemudu 档载入 ok（现网档零回归硬门槛，批次 Z 五件套快照）")
	check_eq((r.get("warnings", []) as Array).size(), 0, "P6: hemudu 档零警告（档内无越界格，净化零触发；批次 Z 五件套实况）")
	var piece := _piece_of(r)
	check_eq((piece.get("blocks", []) as Array).size(), 180, "P6: hemudu blocks 180 格（批次 Z 五件套实况钉值）")
	check_eq(((piece.get("target_shapes", [[]]) as Array)[0] as Array).size(), 160, "P6: hemudu target 160 格（批次 Z 实况）")
	check_eq(((piece.get("join_part", {}) as Dictionary).get("voxels", []) as Array).size(), 122, "P6: hemudu join 122 格（批次 Z 实况）")
	check_eq(((piece.get("final_answer", {}) as Dictionary).get("voxels", []) as Array).size(), 330, "P6: hemudu final 330 格（批次 Z 实况；≠target∪join 属用户拍板原样导入）")
	check_eq(int((piece.get("block_size", {}) as Dictionary).get("x", -1)), 12, "P6: hemudu block_size 12×3×5（批次 Z 实况；旧 8×3×8 等价替换留痕）")
	check(piece.has("target_size")
		and int((piece.get("target_size", {}) as Dictionary).get("x", -1)) == 12
		and int((piece.get("target_size", {}) as Dictionary).get("y", -1)) == 3
		and int((piece.get("target_size", {}) as Dictionary).get("z", -1)) == 5,
		"P6: hemudu 档自带 target_size=12×3×5 且净化保持同值（批次 Z 实况；旧「无键不新增」断言等价替换留痕——旧档回落口径见接口规范 §3）")

# ============ P7 三视图按域渲染（场景实例化，chapter=9 避让现网） ============
func _p7_scene_per_domain_build() -> void:
	var lib: Node = get_root().get_node("LevelLibrary")
	var cleaned: Dictionary = (lib.validate_level(_domain_doc()) as Dictionary)["level"]
	# 注入扫描结果形态条目（scan_directory 同构：entry.chapter=9 避让现网 1~5；data=净化后档）。
	lib._levels.append({
		"chapter": 9, "level_id": "chapter9_v_domain_test", "title": "按域渲染测试",
		"era": "", "path": "test://v_domain", "data": cleaned,
	})
	var inst: Node = (load(SCENE_PATH) as PackedScene).instantiate()
	inst.call("set_context", {"chapter": 9})
	add_child(inst)
	await process_frame
	# 三视图构建断言（_build_views 传参口径的可观测结果）。
	var mvv: Node = inst.get_node_or_null("MainView/ViewportContainer/SubViewport/VoxelView")
	var tvv: Node = inst.get_node_or_null("TargetView/ViewportContainer/SubViewport/VoxelView")
	var jvv: Node = inst.get_node_or_null("JoinView/ViewportContainer/SubViewport/VoxelView")
	check(mvv != null and tvv != null and jvv != null, "P7: 三视图 VoxelView 就位（前置）")
	if mvv != null and tvv != null and jvv != null:
		check(_set_of(mvv.call("get_built_cells")) == {"0,0,0": true, "1,0,0": true},
			"P7: 主视图=blocks 界内 2 格（block 域 2×1×1，现状口径）")
		var tbuilt := _set_of(tvv.call("get_built_cells"))
		# 批次 Z Z1 等价改写留痕：原断言「Target 按 target_size 构建——(3,0,0) 界内被构建」——
		# spec §1 用户拍板左上换源 final：(1,0,0)=final 界内构建、(2,0,0)/(8,0,0)=超 final 域被滤、
		# (3,0,0)=target 格零渲染（反向直断言，比旧断言多锁「target 不进渲染」）。
		check(tbuilt.has("1,0,0") and not tbuilt.has("2,0,0") and not tbuilt.has("8,0,0") \
			and not tbuilt.has("3,0,0"),
			"P7: 对照成品视图按 final_answer.size 构建（Z1 换源 final 域）——(1,0,0) 界内构建、target 格 (3,0,0) 不渲染（红：旧实现渲染 target_shapes 按 target_size 过滤）")
		var jbuilt := _set_of(jvv.call("get_built_cells"))
		check(jbuilt.has("2,0,0") and jbuilt.has("1,0,0") and not jbuilt.has("5,0,0"),
			"P7: 对接固定件视图按 join_part.size 构建——(2,0,0) 界内被构建（红：旧实现按 block_size 过滤不构建）")
		# 等价锚：挖除/拾取/锐眼差集锚 blocks 域（_voxel_size 现状不变）。
		check_eq(inst.get("_voxel_size"), Vector3i(2, 1, 1),
			"P7: _voxel_size 仍锚 block_size（挖除/锐眼差集现状不变，等价锚）")
		# 侧视拾取尺寸按域缓存（_raycast_side_at 等价适配的数据源；红：旧实现无此成员）。
		# 批次 Z Z1 等价改写留痕：原 Target=target_size(4×4×4) → Target=final_answer.size(2×1×1)
		# （左上渲染换源 final 域，拾取过滤与渲染同源）；Join=3×1×1 零变化。
		var vsizes: Variant = inst.get("_view_sizes")
		check(vsizes is Dictionary \
			and (vsizes as Dictionary).get("Target", Vector3i.ZERO) == Vector3i(2, 1, 1) \
			and (vsizes as Dictionary).get("Join", Vector3i.ZERO) == Vector3i(3, 1, 1),
			"P7: 侧视拾取尺寸按域缓存 Target=2×1×1〔final 域，Z1〕/Join=3×1×1（_raycast_side_at 按域适配，红）")
	inst.free()
	# 还原注入（清档纪律：不污染本进程后续与真实扫描结果）。
	for i: int in range((lib._levels as Array).size() - 1, -1, -1):
		if String((lib._levels[i] as Dictionary).get("level_id", "")) == "chapter9_v_domain_test":
			(lib._levels as Array).remove_at(i)
