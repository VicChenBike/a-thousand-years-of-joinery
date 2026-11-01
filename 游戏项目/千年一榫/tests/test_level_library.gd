extends "res://tests/test_base.gd"

const FIX := "res://tests/fixtures/"

func _load_dict(p: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var t: String = f.get_as_text()
	f.close()
	var v: Variant = JSON.parse_string(t)
	return v if typeof(v) == TYPE_DICTIONARY else {}

func _initialize() -> void:
	print("== test_level_library ==")
	var ll: Node = load("res://autoload/level_library.gd").new()
	# SceneTree 本身无 add_child，挂到根窗口（与 test_theme/test_save_manager 同一约定）
	get_root().add_child(ll)
	ll.name = "LevelLibrary"

	# 1 合法文件通过
	var r: Dictionary = ll.validate_level(_load_dict(FIX + "valid_chapter1.json"))
	check(r["ok"], "合法文件通过校验")
	check_eq((r["warnings"] as Array).size(), 0, "合法文件无警告")

	# 2 版本不兼容 → 拒绝
	r = ll.validate_level(_load_dict(FIX + "bad_version.json"))
	check(not r["ok"], "版本不兼容被拒绝")
	check(String(r["reject"]).contains("版本"), "拒绝原因含版本提示")

	# 3 chapter 越界 → 按 1 处理并警告
	r = ll.validate_level(_load_dict(FIX + "bad_chapter.json"))
	check(r["ok"], "chapter 越界不拒绝")
	check((r["warnings"] as Array).size() >= 1, "chapter 越界有警告")
	check_eq((r["level"] as Dictionary).get("chapter", -1), 1, "chapter 越界按 1 处理")

	# 4 pieces 空 → 拒绝
	r = ll.validate_level(_load_dict(FIX + "empty_pieces.json"))
	check(not r["ok"], "pieces 空被拒绝")

	# 5 block_size 越界 → 拒绝
	r = ll.validate_level(_load_dict(FIX + "bad_blocksize.json"))
	check(not r["ok"], "block_size 越界被拒绝")

	# 6 体素坐标越界 → 跳过并警告（不拒绝）
	r = ll.validate_level(_load_dict(FIX + "out_of_bounds_voxel.json"))
	check(r["ok"], "坐标越界不拒绝")
	check((r["warnings"] as Array).size() >= 1, "坐标越界有警告")

	# 7 target 空 → 拒绝
	r = ll.validate_level(_load_dict(FIX + "empty_target.json"))
	check(not r["ok"], "target 空被拒绝")

	# 8 final 空 → 拒绝
	r = ll.validate_level(_load_dict(FIX + "empty_final.json"))
	check(not r["ok"], "final_answer 空被拒绝")

	# 8b 过滤后空集复检（边界用例，R3 审查点新增；不依赖夹具文件，直接内联构造）：
	# join_part 体素全部越界 → _filter_voxels 过滤后为空集 → 校验失败
	var d8b: Dictionary = {"format_version": 1, "chapter": 1, "pieces": [{"piece_id": "p1", "block_size": {"x": 8, "y": 3, "z": 8}, "target_shapes": [["1,0,1", "2,0,1"]], "join_part": {"voxels": ["99,0,0"]}, "final_answer": {"voxels": ["1,0,1", "2,0,1", "99,0,0"]}}]}
	check(not (ll.validate_level(d8b) as Dictionary)["ok"], "join_part 过滤后为空集 → 拒绝")
	# final_answer 体素全部越界 → 过滤后为空集 → 同样拒绝
	var d8c: Dictionary = {"format_version": 1, "chapter": 1, "pieces": [{"piece_id": "p1", "block_size": {"x": 8, "y": 3, "z": 8}, "target_shapes": [["1,0,1", "2,0,1"]], "join_part": {"voxels": ["5,0,1"]}, "final_answer": {"voxels": ["99,0,0"]}}]}
	check(not (ll.validate_level(d8c) as Dictionary)["ok"], "final_answer 过滤后为空集 → 拒绝")

	# 9 章节资产映射
	check(String(ll.get_model_path(1)).contains("石器"), "第1关映射石器")
	check(String(ll.get_model_path(5)).contains("现代"), "第5关映射现代")

	# 9b 背景图统一 PNG（2026-08-26 用户指示：所有背景一律 PNG；bg_chapter5 已从 jpg 转 png）
	for ch: int in range(1, 6):
		check(String(ll.get_background_path(ch)).ends_with(".png"), "第%d章背景路径扩展名为 .png" % ch)

	# 9c 参考图统一 PNG（2026-08-26 用户指示：图片一律 PNG；ref_chapter1~4 已从 jpg 转 png）
	for ch: int in range(1, 6):
		var ref_path: String = String(ll.get_reference_image_path(ch))
		check(ref_path.ends_with(".png"), "第%d章参考图路径扩展名为 .png" % ch)
		check(ResourceLoader.exists(ref_path), "第%d章参考图文件存在并可导入: %s" % [ch, ref_path])

	# 10 扫描真实目录（可能为空或含测试关卡，验证不崩溃 + 排序）
	ll.scan_directory(FIX)
	var lst: Array = ll.get_level_list()
	check(lst.size() >= 1, "扫描到至少 1 个合法关卡")
	if lst.size() >= 2:
		check(int(lst[0]["chapter"]) <= int(lst[1]["chapter"]), "按 chapter 升序")

	# 11 user_levels 预留读入（接口规范 §6：同格式校验 + is_user_created 标记；本期无入口 UI）
	ll.scan_user_directory(FIX)
	var ul: Array = ll.get_user_level_list()
	check(ul.size() >= 1, "user_levels 扫描到至少 1 个合法关卡")
	var u0: Dictionary = ul[0] if ul.size() > 0 else {}
	check(bool(u0.get("is_user_created", false)), "用户关卡标记 is_user_created=true")

	# 12 错误提示：未加载关卡返回明确错误而非静默（接口规范 §6「缺失即显示关卡缺失」）
	check_eq(ll.get_level(99), {}, "不存在的章节返回空字典")
	check_eq(ll.get_error(99), "关卡缺失", "不存在的章节错误提示为「关卡缺失」")

	finish()
