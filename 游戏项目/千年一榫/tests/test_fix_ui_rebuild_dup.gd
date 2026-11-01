extends "res://tests/test_base.gd"
## 修复批红测 7（P3，UI 域）：商店/图鉴重建同帧双份子件。
## 病灶：shop_panel.gd `_build_grid`（:65-67）与 catalog_scene.gd `_rebuild_list`（:360-362）
## queue_free 旧卡后同帧 add_child 新卡——queue_free 节点在帧末才摘除，帧内容器子件数=2N
## （列表/网格瞬时双倍：布局抖动、滚动条跳变、一帧闪跳）。
## 修法：先 remove_child 再 queue_free（立即摘除，帧内容器子件数=N）。
## 红断言：_ready 建完 N 后同帧（零 await）再重建 → get_child_count()==N（改前=2N）。
## 纯内存：不写档（商店/图鉴 _ready 只读存档；终段 save.json 逐字节自证）。
const SHOP_SCENE := "res://scenes/shop/shop_panel.tscn"
const CATALOG_SCENE := "res://scenes/catalog/catalog_scene.tscn"
const SAVE_PATH := "user://save.json"
var _pre_save_text := ""

func _initialize() -> void:
	print("== test_fix_ui_rebuild_dup ==")
	if FileAccess.file_exists(SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(SAVE_PATH)
	await process_frame

	# ================= 商店：_build_grid 同帧双建 =================
	var n1 := -1
	var shop: Node = (load(SHOP_SCENE) as PackedScene).instantiate()
	add_child(shop)
	await process_frame
	var grid: Container = shop.get_node("Content/GridPanel/Scroll/SkinGrid")
	check(grid != null, "前置：商店网格在位")
	if grid != null:
		n1 = grid.get_child_count()
		check(n1 > 0, "前置：_ready 已建卡（n=%d）" % n1)
		shop.call("_build_grid")   # 同帧重建（皮肤变更信号同款路径，零 await）
		var n2: int = grid.get_child_count()
		check_eq(n2, n1,
			"P3 红测：同帧 _build_grid → 网格子件=N（改前旧卡 queue_free 未摘除=2N，n=%d）" % n2)
		# 末帧再验（queue_free 冲刷后仍为 N——防只在帧内对）
		await process_frame
		check_eq(grid.get_child_count(), n1, "帧末：子件数收敛 N（无重复残留）")
	shop.free()

	# ================= 图鉴：_rebuild_list 同帧双建 =================
	var m1 := -1
	var cat: Node = (load(CATALOG_SCENE) as PackedScene).instantiate()
	add_child(cat)
	await process_frame
	var right_list: Container = cat.get_node("Body/RightBox/RightInner/RightScroll/RightList")
	check(right_list != null, "前置：图鉴右列表在位")
	if right_list != null:
		m1 = right_list.get_child_count()
		check(m1 > 0, "前置：_ready 已建列表（m=%d）" % m1)
		cat.call("_rebuild_list")   # 同帧重建（progress_changed 信号同款路径，零 await）
		var m2: int = right_list.get_child_count()
		check_eq(m2, m1,
			"P3 红测：同帧 _rebuild_list → 列表子件=M（改前旧项 queue_free 未摘除=2M，m=%d）" % m2)
		await process_frame
		check_eq(right_list.get_child_count(), m1, "帧末：列表子件收敛 M（无重复残留）")
	cat.free()

	# 存档逐字节自证（零写盘）
	var post: String = FileAccess.get_file_as_string(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：save.json 起测/终测逐字节等价（本测试零写盘）")
	finish()
