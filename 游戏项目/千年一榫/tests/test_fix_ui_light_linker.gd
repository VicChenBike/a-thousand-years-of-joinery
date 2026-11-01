extends "res://tests/test_base.gd"
## 修复批测试 3（P3，UI 域）：UILightLinker _attach resized 连接守卫。
## 审查原判（P3）：`is_connected(_write_size)`（裸方法）查 `_write_size.bind(c)`（带 bind）守卫恒失效。
## ⚠ 探针证伪（tests/zz_probe_dupconnect_temp.gd，4.7 实证，已删）：
##   - 无连接时 is_connected(裸) = false；bound 连接在位时 is_connected(裸) = **true**
##     （4.7 Signal.is_connected 按 object+method 匹配、忽略 binds）→ 守卫实际有效，
##     重复 connect 由引擎同判据拦截（"already connected" ERROR，计数仍 1）。
## 因此本测试为**回归锁定**（先于同形 Callable 加固存在即绿）：同节点离树→重入树→ _attach 两次
## 后 resized 恰 1 条连接、材质重挂；加固后（同形 `_write_size.bind(c)` 断言）语义零变化保持绿。
const LINKER_SCRIPT := "res://scripts/ui_light_linker.gd"

func _initialize() -> void:
	print("== test_fix_ui_light_linker ==")
	await process_frame
	var linker: Node = (load(LINKER_SCRIPT) as GDScript).new()
	add_child(linker)
	await process_frame
	var b := Button.new()
	root.add_child(b)
	await process_frame
	await process_frame   # node_added → 延帧 _rescan_deferred → _attach
	check(b.material is ShaderMaterial, "前置：按钮已挂 ui 材质（首次 _attach）")
	check_eq(b.resized.get_connections().size(), 1, "前置：resized 恰 1 条连接")
	# 离树（_on_node_removed 清 _mats 登记，连接保留）→ 重入树（node_added → 二次 _attach）
	root.remove_child(b)
	await process_frame
	root.add_child(b)
	await process_frame
	await process_frame
	check(b.material is ShaderMaterial, "重入树：材质重挂（_attach 重建）")
	check_eq(b.resized.get_connections().size(), 1,
		"回归锁定：同节点离树重入 _attach 两次 → resized 恰 1 条连接（守卫防重复）")
	# 连接真在工作：改尺寸 → u_rect_size 跟随（防守卫改过头变成永不连接）
	var mat0: ShaderMaterial = b.material as ShaderMaterial
	b.size = Vector2(137.0, 53.0)
	await process_frame
	var sz: Variant = mat0.get_shader_parameter("u_rect_size")
	check(sz is Vector2 and (sz as Vector2).x > 0.0,
		"连接有效性：resized 触发后 u_rect_size 已写入（守卫不阻断首连）")
	b.free()
	linker.free()
	finish()
