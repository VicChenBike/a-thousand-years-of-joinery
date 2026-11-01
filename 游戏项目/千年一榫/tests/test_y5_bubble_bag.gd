extends "res://tests/test_base.gd"
## 批次 Y（Y-C8，spec §9.2）：见证者气泡台词洗牌袋抽取器（scripts/bubble_lines_bag.gd）。
## 契约：整轮不重复、轮尽重洗、池大小任意；缺文件/空池/非法 JSON/类型错防御
## =next_line() 返回空串（不弹）+push_warning 登记不崩；默认路径=剧情对话/气泡_第N关.json
## （台词文件归 Y4 文件域，本套件用 tests/fixtures 夹具，不在 剧情对话/ 建改任何文件）。
## 红测先行：实现前本套件全 [FAIL] 属预期（preload 路径不存在直接红灯）。

const BAG := preload("res://scripts/bubble_lines_bag.gd")

func _initialize() -> void:
	print("== test_y5_bubble_bag ==")

	# ---- 1. 池加载（对象 {_说明, lines} 形态=Y4 交付口径）----
	var bag: RefCounted = BAG.new()
	bag.seed_for_test(20260923)
	check(bag.load_path("res://tests/fixtures/bubble_y5_fixture.json") == true,
		"加载：合法对象档返回 true")
	check_eq(bag.pool_size(), 4, "加载：池大小=4")
	check_eq((bag.pool() as Array).size(), 4, "加载：pool() 返回全池副本")

	# ---- 2. 整轮不重复：一轮抽取=池的全排列（无重复、全覆盖）----
	var drawn: Array = []
	for i: int in bag.pool_size():
		drawn.append(bag.next_line())
	var uniq := {}
	for d: Variant in drawn:
		uniq[d] = true
	check_eq(uniq.size(), 4, "洗牌袋：一轮抽取无重复（4 抽 4 异）")
	for d: Variant in drawn:
		check((bag.pool() as Array).has(d), "洗牌袋：抽取句∈池（「%s」）" % str(d))
	check_eq(drawn.size(), 4, "洗牌袋：轮内抽取数=池大小")

	# ---- 3. 轮尽重洗：第二轮再抽仍=全排列 ----
	var drawn2: Array = []
	for i: int in bag.pool_size():
		drawn2.append(bag.next_line())
	var uniq2 := {}
	for d: Variant in drawn2:
		uniq2[d] = true
	check_eq(uniq2.size(), 4, "洗牌袋：轮尽重洗后第二轮仍无重复（4 抽 4 异）")
	var same_order := true
	for i: int in 4:
		if str(drawn[i]) != str(drawn2[i]):
			same_order = false
	check(not same_order, "洗牌袋：轮尽重洗为重排而非复位（两轮序非恒等；种子固定下逐位相同概率 1/24）")

	# ---- 4. 轮内连续两抽必不同（池≥2 时整轮不重复的直接推论）----
	var bag_b: RefCounted = BAG.new()
	bag_b.seed_for_test(7)
	bag_b.load_path("res://tests/fixtures/bubble_y5_fixture.json")
	var all_pairs_distinct := true
	for i: int in 8:
		var a: String = bag_b.next_line()
		var b: String = bag_b.next_line()
		if a == b:
			all_pairs_distinct = false
	check(all_pairs_distinct, "洗牌袋：连续两抽恒不同（轮内不重复，8 对）")

	# ---- 5. 池大小 1：轮尽重洗退化为恒抽取唯一句 ----
	var bag1: RefCounted = BAG.new()
	check(bag1.load_path("res://tests/fixtures/bubble_y5_fixture_array.json") == true,
		"宽容形态：顶层数组档可加载")
	check_eq(bag1.pool_size(), 2, "宽容形态：顶层数组池大小=2")

	# ---- 6. 防御：缺文件=不弹+告警不崩 ----
	var bag_m: RefCounted = BAG.new()
	check(bag_m.load_path("res://tests/fixtures/bubble_y5_missing__.json") == false,
		"防御：缺文件返回 false")
	check_eq(bag_m.next_line(), "", "防御：缺文件 next_line()=空串（不弹）")
	check((bag_m.load_warnings as Array).size() >= 1, "防御：缺文件登记 push_warning（load_warnings≥1）")

	# ---- 7. 防御：空池 ----
	var bag_e: RefCounted = BAG.new()
	check(bag_e.load_path("res://tests/fixtures/bubble_y5_empty.json") == false,
		"防御：空池返回 false")
	check_eq(bag_e.next_line(), "", "防御：空池 next_line()=空串（不弹）")
	check((bag_e.load_warnings as Array).size() >= 1, "防御：空池登记告警")

	# ---- 8. 防御：lines 类型错 / 非法 JSON ----
	var bag_t: RefCounted = BAG.new()
	check(bag_t.load_path("res://tests/fixtures/bubble_y5_bad_type.json") == false,
		"防御：lines 非数组返回 false")
	check_eq(bag_t.next_line(), "", "防御：lines 类型错 next_line()=空串")
	var bag_x: RefCounted = BAG.new()
	check(bag_x.load_path("res://tests/fixtures/bubble_y5_broken.json") == false,
		"防御：非法 JSON（解析失败）返回 false")
	check_eq(bag_x.next_line(), "", "防御：非法 JSON next_line()=空串")

	# ---- 9. 净化：非字符串元素过滤（混合数组只收 String）----
	var bag_mix: RefCounted = BAG.new()
	check(bag_mix.load_path("res://tests/fixtures/bubble_y5_mixed.json") == true,
		"净化：混合元素档可加载（跳过非 String）")
	check_eq(bag_mix.pool_size(), 1, "净化：混合数组仅收 1 条 String（「混合句」）")
	check_eq(bag_mix.next_line(), "混合句", "净化：抽取内容=混合句")

	# ---- 10. 默认路径公式（第 N 关读 剧情对话/气泡_第N关.json）----
	check_eq(String(BAG.path_for_chapter(1)), "res://剧情对话/气泡_第1关.json",
		"路径公式：第 1 关→剧情对话/气泡_第1关.json")
	check_eq(String(BAG.path_for_chapter(5)), "res://剧情对话/气泡_第5关.json",
		"路径公式：第 5 关→剧情对话/气泡_第5关.json")

	# ---- 11. 未加载即抽取（防御链路兜底）----
	var bag_n: RefCounted = BAG.new()
	check_eq(bag_n.next_line(), "", "防御：未加载即抽取=空串（不弹不崩）")

	finish()
