extends "res://tests/test_base.gd"
## 批次 E 判定用例：体素渲染扩展 + 键鼠挖除交互（右键删除 / 撤销重做）。
## K-G（批次 K / K6-5，spec §10.4）：多选由「Ctrl+点击逐点」改为「按住左键划动连续拾取」，
## Ctrl 修饰判定废除（select_voxel 手势接口 additive 第二参保留）；空白按住拖动旋转（§10.4）。
## TDD 先写（实现前全 [FAIL] 属预期红灯）。
## 契约来源：批次 E 任务单（用户已确认交互规范）：
##   LevelVoxelView 扩展（scripts/level_voxel_view.gd）：
##     cell→MeshInstance3D 映射（build_voxels 重建清空）；hide_voxel/show_voxel（set_visible）；
##     set_voxel_highlight（默认木色 ↔ 选中半透绿（批次 J/A3，原亮黄），material_override 切换）；
##     get_voxel_node(cell)（缺失返回 null）；get_voxel_count 只计体素（挂非体素子节点不失真）；
##     get_center_offset/get_built_cells（供拾取几何与初始 _remaining 使用）。
##   关卡场景挖除（scenes/level/level_scene.gd，MainView 玩家视图）：
##     static ray_to_cell(origin,dir,cells,size[,center]) -> Vector3i：slab 射线-AABB 最近命中，
##       未命中哨兵 NO_CELL=(-1,-1,-1)（ZERO 可能是合法体素，必须显式哨兵）；纯数学不依赖 Physics；
##     选区（K6-5 划选状态机）：单击=单选替换；按住左键划动=连续拾取追加；空白单击/Esc=清空；
##       空白按住拖动=轨道旋转（与划选互斥）；越界或已删除体素忽略；
##     删除：右键删除选中组（空选提示不崩）；只能删除当前仍存在体素（重复删除幂等）；
##     撤销/重做：undo()=Ctrl+Z、redo()=Ctrl+Y（兼 Ctrl+Shift+Z），组粒度、栈空安全不崩；
##     对外钩子：select_voxel/clear_selection/delete_selected/undo/redo/get_selected_voxels/
##       get_remaining_voxels/get_cell_hit/get_undo_depth/get_redo_depth；
##     HintLabel：M-E⑥（spec §3.5 拍板 #8）等价替换——提示行=精简键鼠模板「左键划选 ·
##       Ctrl+点击多选 · …」（Ctrl+点击 多选话术按拍板 #8 回归提示行），剩余体素计数挪
##       TopBar/VoxelLabel（删除/撤销实时刷新），对接引导迁 JoinButton.tooltip。
## M-E（spec §3.5）等价替换总注：透视相机位姿/距离/滚轮缩放断言按正交口径等价替换——
##   初始 yaw -35°→45°、pitch 22°→35.264°、距离 6（滚轮 [4.5,14]）→固定 20（无滚轮缩距）、
##   滚轮改 ortho size 语义（×0.9/×1.1，回修4 A：限幅下限=窗口适配动态下限，最大档不穿帮）；投影=PROJECTION_ORTHOGONAL。
## 环境说明（同 test_level_scene 实测）：--script 无头模式 autoload 经 /root/<Name> 动态引用；
## 主脚本不能用全局标识符/class_name，一律 load()/call()；静态方法经 Script 对象 .call() 调用（已探针验证）。

const SCENE_PATH := "res://scenes/level/level_scene.tscn"
const LS_SCRIPT := "res://scenes/level/level_scene.gd"
const VOX_SCRIPT := "res://scripts/level_voxel_view.gd"
const MISS := Vector3i(-1, -1, -1)

# ===== 清档纪律（tools/README_走查清档规范.md，批次V收口补齐，test_v_save_domain/test_n_focus_fullscreen 同款）=====
# 全量回归实证（v_regression_full_20260919）：本机真实 save.json 挖除断点经 level.
# _replay_saved_progress 泄入关卡致本件 17/168 环境性假红；且关卡实例 _exit_tree 兜底写档（N9）
# 会把测试态写回真实档案。起测前备份 user:// 真实档案（save.json/first_launch.flag），起测清
# 测试域基线+SaveManager 内存重同步；终测统一经 finish() 收口：先同步 free 测试挂载节点（令
# 退出写回落测试域磁盘，规范第 6 条），再逐件还原+load_game 重同步内存+逐字节等价断言+EVID
# 证据行。备份路径必须带全 user:// 前缀（相对路径在 FileAccess/DirAccess 间解析漂移→备份链
# 静默失效，test_n10 先例）；独立前缀 _rli_ 防跨件备份残留互踩。
const RLI_SAVE_PATH := "user://save.json"
const RLI_FLAG_PATH := "user://first_launch.flag"
const RLI_BK_PREFIX := "user://_rli_backup_"
const RLI_WATCHED: Array = [RLI_SAVE_PATH, RLI_FLAG_PATH]
const RLI_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _rli_pre_save_text: String = ""   # 起测前真实 save.json 原文（还原等价自检基准）

func _rli_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _backup_user() -> void:
	# 规范第 1 条：任何删/写档操作之前备份真实档案（有档才备份；还原「有备份才回拷」幂等，
	# 起测前不存在的档案终测后仍不存在——测试自建残留一律清零）
	if FileAccess.file_exists(RLI_SAVE_PATH):
		_rli_pre_save_text = FileAccess.get_file_as_string(RLI_SAVE_PATH)
	for p: String in RLI_WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = RLI_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_rli_abs(p), _rli_abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	# 防退出写回（规范第 6 条）：先同步 free 测试挂载的非 autoload 节点——level._exit_tree
	# 兜底写档若拖到还原之后会把测试态写回真实档案；提前 free 令兜底写档落测试域磁盘，
	# 紧随其后的逐件还原即将其覆盖。
	for c: Node in root.get_children():
		if not RLI_AUTOLOADS.has(String(c.name)):
			c.free()
	# 规范第 2 条：逐件还原 + load_game 重同步内存（防后续 save_game 把测试态写回真实档案）
	for p: String in RLI_WATCHED:
		var a: String = _rli_abs(p)
		if FileAccess.file_exists(a):
			DirAccess.remove_absolute(a)
		var bk: String = RLI_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_rli_abs(bk), _rli_abs(p))
			DirAccess.remove_absolute(_rli_abs(bk))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()
	# 纪律自检：还原后 save.json 与起测前逐字节等价（起测前无档 ↔ 还原后无档）
	var post: String = FileAccess.get_file_as_string(RLI_SAVE_PATH) if FileAccess.file_exists(RLI_SAVE_PATH) else ""
	check_eq(post, _rli_pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|level_interaction|files=%d" % RLI_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _script_has_method(s: Script, m: String) -> bool:
	# 注意：Script.get_method_list() 不含静态方法，has_method 可以找到（实测）
	return s.has_method(m)

func _missing_methods(obj: Object, names: Array) -> Array:
	var missing: Array = []
	for m: Variant in names:
		if not obj.has_method(String(m)):
			missing.append(String(m))
	return missing

func _has_cell(arr: Array, c: Vector3i) -> bool:
	return arr.has(c)

func _fget(obj: Object, prop: String) -> float:
	# 安全读取数值属性：缺失（尚未实现）返回远离合法域的哨兵值，保证断言干净判红不崩
	var v: Variant = obj.get(prop)
	return float(v) if v != null else 999999.0

func _mb(btn: int, is_pressed: bool, pos: Vector2) -> InputEventMouseButton:
	# 直接构造鼠标按钮事件喂给 ViewportContainer.gui_input（无头无法走真实输入管线）
	var ev := InputEventMouseButton.new()
	ev.button_index = btn as MouseButton
	ev.pressed = is_pressed
	ev.position = pos
	ev.global_position = pos
	return ev

func _mm_at(pos: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	return ev

func _key(keycode: int, ctrl: bool, shift: bool) -> InputEventKey:
	# 直接构造按键事件喂给 _unhandled_input（无头模式无法走真实输入管线，且不改 project.godot 输入映射）
	var ev := InputEventKey.new()
	ev.keycode = keycode as Key
	ev.physical_keycode = keycode as Key
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	return ev

func _initialize() -> void:
	print("== test_level_interaction ==")
	_backup_user()                     # 清档纪律：任何删/写档前备份真实档案
	# 起测清档基线（test_n_focus_fullscreen 同款）：测试域档案全清+SaveManager 内存重同步——
	# 否则本机真实 save.json 挖除断点经 level._replay_saved_progress 泄入关卡（v_regression_
	# full_20260919 实测 17/168 环境红根因）。
	for p: String in RLI_WATCHED:
		var a: String = _rli_abs(p)
		if FileAccess.file_exists(a):
			DirAccess.remove_absolute(a)
	var rli_sm: Node = get_root().get_node_or_null(NodePath("SaveManager"))
	if rli_sm != null:
		rli_sm.load_game()
	var ls: Script = load(LS_SCRIPT) as Script
	var vox_s: Script = load(VOX_SCRIPT) as Script
	check(ls != null, "level_scene.gd 可加载")
	check(vox_s != null, "level_voxel_view.gd 可加载")
	if ls == null or vox_s == null:
		finish()
		return

	# ---- 1. 纯几何：static ray_to_cell（slab 射线-AABB 最近命中，纯数学不依赖 Physics）----
	# 体素集（相对坐标）：A(0,0,0) B(1,0,0) C(2,0,0) D(0,1,0)，size=8x3x8；
	# 自动中心与 build_voxels 一致：mn=(0,0,0) mx=(2,1,0) → center=(1.5,1.0,0.5)。
	var has_ray := _script_has_method(ls, "ray_to_cell")
	check(has_ray, "静态接口存在: level_scene.ray_to_cell")
	if has_ray:
		var cells: Dictionary = {
			Vector3i(0, 0, 0): true, Vector3i(1, 0, 0): true,
			Vector3i(2, 0, 0): true, Vector3i(0, 1, 0): true,
		}
		var size := Vector3i(8, 3, 8)
		# 水平穿三格射线（x 从负向正）：最近命中 (0,0,0)，同时证明哨兵不与合法格 ZERO 冲突
		check_eq(ls.call("ray_to_cell", Vector3(-10, -0.5, 0), Vector3(1, 0, 0), cells, size),
			Vector3i(0, 0, 0), "水平射线按 t 最近命中 (0,0,0)（合法格 ZERO 可命中）")
		var cells_wo_a: Dictionary = {
			Vector3i(1, 0, 0): true, Vector3i(2, 0, 0): true, Vector3i(0, 1, 0): true,
		}
		check_eq(ls.call("ray_to_cell", Vector3(-10, -0.5, 0), Vector3(1, 0, 0), cells_wo_a, size),
			Vector3i(1, 0, 0), "移除 (0,0,0) 后同射线命中 (1,0,0)")
		check_eq(ls.call("ray_to_cell", Vector3(10, -0.5, 0), Vector3(-1, 0, 0), cells, size),
			Vector3i(2, 0, 0), "反方向射线按 t 最近命中 (2,0,0)")
		check_eq(ls.call("ray_to_cell", Vector3(0, 10, 0), Vector3(0, 1, 0), cells, size),
			MISS, "场上方远离射线未命中 → 哨兵 (-1,-1,-1)")
		check_eq(ls.call("ray_to_cell", Vector3(100, 100, 100), Vector3(0, 0, -1), cells, size),
			MISS, "远处越界射线未命中 → 哨兵")
		# 斜穿：对角线穿过 A(0,0,0) 内部后再进 D(0,1,0) 内部，两端分别先命中近格（无共角歧义）
		var diag := Vector3(1, 1, 1).normalized()
		check_eq(ls.call("ray_to_cell", Vector3(-0.9, 0.5, 0.1) - diag * 20.0, diag, cells, size),
			Vector3i(0, 0, 0), "斜穿射线先命中近格 (0,0,0)")
		check_eq(ls.call("ray_to_cell", Vector3(-0.9, 0.5, 0.1) + diag * 20.0, -diag, cells, size),
			Vector3i(0, 1, 0), "同对角线反向先命中 (0,1,0)")
		check_eq(ls.call("ray_to_cell", Vector3.ZERO, Vector3.ZERO, cells, size),
			MISS, "零方向向量安全返回哨兵不崩")
		check_eq(ls.call("ray_to_cell", Vector3.ZERO, Vector3(0, 1, 0), {}, size),
			MISS, "空体素集安全返回哨兵不崩")
		# 显式 center 参数（删除后包围盒中心锁定为构建时值的关键，level_scene 以此调用）
		# 单格 {(2,0,0)}：自动中心=(2.5,0.5,0.5)，世界 AABB x∈[-0.5,0.5]，从上方 x=-0.2 打入可命中；
		# 若换成构建时全量中心 (1.5,1.0,0.5)，AABB 平移到 x∈[0.5,1.5]，同射线则未命中。
		var one: Dictionary = {Vector3i(2, 0, 0): true}
		var o_top := Vector3(-0.2, 5.0, 0.0)
		check_eq(ls.call("ray_to_cell", o_top, Vector3(0, -1, 0), one, size),
			Vector3i(2, 0, 0), "自动中心（单格 mn=mx）命中 (2,0,0)")
		check_eq(ls.call("ray_to_cell", o_top, Vector3(0, -1, 0), one, size, Vector3(1.5, 1.0, 0.5)),
			MISS, "显式 center 参与几何计算（换中心则未命中）")

	# ---- 2. LevelVoxelView 扩展（cell→node 映射 / hide/show / 高亮 / 计数语义）----
	var vox_need := ["build_voxels", "clear_voxels", "get_voxel_count", "hide_voxel", "show_voxel",
		"set_voxel_highlight", "get_voxel_node", "get_center_offset", "get_built_cells"]
	var vox_missing := _missing_methods(vox_s.new(), vox_need)
	var vox_ok := vox_missing.is_empty()
	if vox_ok:
		var vv: Node = (vox_s as GDScript).new()
		add_child(vv)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.82, 0.64, 0.38)
		var sample: Array = ["0,0,0", "1,0,0", "0,1,0"]
		vv.call("build_voxels", sample, Vector3i(8, 3, 8), mat)
		check_eq(int(vv.call("get_voxel_count")), 3, "build_voxels 后计数=3")
		var n0: MeshInstance3D = vv.call("get_voxel_node", Vector3i(0, 0, 0))
		check(n0 is MeshInstance3D, "get_voxel_node(0,0,0) 返回 MeshInstance3D")
		check(vv.call("get_voxel_node", Vector3i(5, 5, 5)) == null, "get_voxel_node 缺失格返回 null")
		check(n0 != null and n0.material_override == mat, "默认材质=构建传入材质（material_override）")
		# 计数语义修正：挂非体素子节点不得失真
		vv.add_child(Node3D.new())
		check_eq(int(vv.call("get_voxel_count")), 3, "挂非体素子节点后计数仍=3（只计体素）")
		# 隐藏/显示
		vv.call("hide_voxel", Vector3i(0, 0, 0))
		check(n0 != null and n0.visible == false, "hide_voxel 后节点 visible=false")
		check_eq(int(vv.call("get_voxel_count")), 3, "隐藏不改计数（体素仍在）")
		vv.call("show_voxel", Vector3i(0, 0, 0))
		check(n0 != null and n0.visible == true, "show_voxel 后节点 visible=true")
		vv.call("hide_voxel", Vector3i(7, 7, 7))
		vv.call("show_voxel", Vector3i(-1, -1, -1))
		check(true, "hide/show 不存在的体素安全不崩")
		# 高亮（材质切换）
		vv.call("set_voxel_highlight", Vector3i(1, 0, 0), true)
		var n1: MeshInstance3D = vv.call("get_voxel_node", Vector3i(1, 0, 0))
		var hm: StandardMaterial3D = n1.material_override if n1 != null else null
		check(hm != null and hm != mat, "高亮后材质切换为高亮材质")
		# 批次 J（A3）：选中高亮由亮黄改半透绿（参考用户截图），emission 绿×0.35
		check(hm != null and hm.albedo_color.g > 0.6 and hm.albedo_color.r < 0.6, "A3：选中高亮为绿色系")
		check(hm != null and hm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "A3：高亮材质半透（ALPHA）")
		check(hm != null and hm.emission_enabled and absf(hm.emission.g - hm.albedo_color.g * 0.35) < 0.01,
			"A3：高亮自发光=绿×0.35")
		var n0b: MeshInstance3D = vv.call("get_voxel_node", Vector3i(0, 0, 0))
		check(n0b != null and n0b.material_override == mat, "未选中格仍为默认材质（逐格独立）")
		vv.call("set_voxel_highlight", Vector3i(1, 0, 0), false)
		check(n1 != null and n1.material_override == mat, "取消高亮恢复默认材质")
		vv.call("set_voxel_highlight", Vector3i(9, 9, 9), true)
		check(true, "高亮不存在的体素安全不崩")
		# J2-5（A3 可选 P2，本批实施）：体素网格线描边——体素节点含线框子节点
		var n_wire: MeshInstance3D = vv.call("get_voxel_node", Vector3i(0, 0, 0))
		var wire_found: bool = false
		var wire_lines_ok: bool = false
		if n_wire != null:
			for ch: Node in n_wire.get_children():
				var cmi := ch as MeshInstance3D
				if cmi != null and cmi.mesh is ImmediateMesh:
					wire_found = true
					# 12 条边 = PRIMITIVE_LINES 24 顶点（ImmediateMesh 无 surface_get_array_len，
					# 用 surface_get_arrays 取顶点数组计数）
					var arrs: Array = (cmi.mesh as ImmediateMesh).surface_get_arrays(0)
					wire_lines_ok = (arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() == 24
					break
		check(wire_found, "J2-5：体素节点含线框（ImmediateMesh）子节点")
		check(wire_lines_ok, "J2-5：线框为 12 条边（24 顶点 PRIMITIVE_LINES）")
		# center/built_cells（拾取几何联动）
		var center: Variant = vv.call("get_center_offset")
		check(center == Vector3(1.0, 1.0, 0.5), "get_center_offset=包围盒中心 (1,1,0.5)（与构建平移一致）")
		var built: Array = vv.call("get_built_cells")
		check_eq(built.size(), 3, "get_built_cells=3 格")
		check(built.has(Vector3i(0, 1, 0)), "get_built_cells 含 (0,1,0)")
		# 重建清空映射（不留陈旧键）
		vv.call("build_voxels", ["2,2,2"], Vector3i(8, 3, 8), mat)
		check_eq(int(vv.call("get_voxel_count")), 1, "重建后计数=1")
		check(vv.call("get_voxel_node", Vector3i(0, 0, 0)) == null, "重建后旧格映射清空")
		check(vv.call("get_voxel_node", Vector3i(2, 2, 2)) is MeshInstance3D, "重建后新格可取节点")
		# 重复坐标输入：映射键唯一，不产生幽灵计数
		vv.call("build_voxels", ["0,0,0", "0,0,0"], Vector3i(8, 3, 8), mat)
		check_eq(int(vv.call("get_voxel_count")), 1, "重复坐标去重计数=1（映射语义正确）")
		# clear 清空映射
		vv.call("clear_voxels")
		check_eq(int(vv.call("get_voxel_count")), 0, "clear_voxels 后计数=0")
		check(vv.call("get_voxel_node", Vector3i(0, 0, 0)) == null, "clear 后 get_voxel_node 返回 null")
		vv.queue_free()
	else:
		for m: String in vox_missing:
			check(false, "接口存在: level_voxel_view.%s" % m)

	# ---- 3. 关卡场景挖除交互 ----
	var scene_need := ["select_voxel", "clear_selection", "delete_selected", "undo", "redo",
		"get_selected_voxels", "get_remaining_voxels", "get_cell_hit", "get_undo_depth", "get_redo_depth"]
	check(ResourceLoader.exists(SCENE_PATH), "level_scene.tscn 存在")
	var packed: PackedScene = load(SCENE_PATH) if ResourceLoader.exists(SCENE_PATH) else null
	check(packed != null, "level_scene.tscn 可加载")
	var inst: Node = (packed as PackedScene).instantiate() if packed != null else null
	check(inst != null, "关卡场景可实例化")
	if inst == null:
		finish()
		return
	inst.call("set_context", {"chapter": 1})  # Game 路由约定：先 set_context 再入树
	add_child(inst)
	await process_frame

	var missing := _missing_methods(inst, scene_need)
	if not missing.is_empty():
		for m: String in missing:
			check(false, "接口存在: level_scene.%s" % m)
		finish()
		return
	check(true, "交互接口齐全（select/clear/delete/undo/redo/查询×4）")

	var main_vv: Node = inst.get_node_or_null("MainView/ViewportContainer/SubViewport/VoxelView")
	var target_vv: Node = inst.get_node_or_null("TargetView/ViewportContainer/SubViewport/VoxelView")
	check(main_vv != null and target_vv != null, "MainView/TargetView 各含 VoxelView")

	# 基线：剩余=全集 180，选区空，双栈空；undo/redo 空栈安全
	check_eq((inst.call("get_remaining_voxels") as Array).size(), 180, "初始剩余体素=180（blocks 全集）")
	check_eq((inst.call("get_selected_voxels") as Array).size(), 0, "初始选区为空")
	check_eq(int(inst.call("get_undo_depth")), 0, "初始撤销栈空")
	check_eq(int(inst.call("get_redo_depth")), 0, "初始重做栈空")
	var hint: Label = inst.get_node_or_null("HintLabel")
	var vox_lbl: Label = inst.get_node_or_null("TopBar/VoxelLabel")
	check(hint is Label, "提示 Label 存在")
	check(vox_lbl is Label, "M-E⑥：TopBar/VoxelLabel 存在（计数挪顶栏）")
	if hint != null:
		# M-E⑥ 等价替换（原 K6-5「无 Ctrl+点击 字样」反转留痕）：拍板 #8 新口径=
		# 精简模板含「Ctrl+点击多选」+计数/对接引导移出提示行；回修4 文案等价替换：
		# 「Ctrl+Z/Y 撤销重做→Ctrl+Z/Y 撤/重做」（全句精简适配主题字体 18px 单行）
		# 2026-09-11 用户文案修订：「撤/重做→撤/取消撤回」（仅界面文案，undo/redo 逻辑不变）
		check(hint.text.contains("左键划选") and hint.text.contains("Ctrl+点击多选")
			and hint.text.contains("Ctrl+Z/Y 撤/取消撤回") and not hint.text.contains("剩余体素"),
			"M-E⑥+回修4：提示行=精简键鼠模板（Ctrl 多选话术回归，计数移出）")
	# 空栈边界（注：undo/redo 空栈会按设计覆写提示为操作引导，故提示断言先于本段）
	check(inst.call("undo") == false, "空栈 undo 返回 false 不崩")
	check(inst.call("redo") == false, "空栈 redo 返回 false 不崩")

	# 拾取与渲染坐标一致性：MainView 体素节点世界位姿 → 射线反查命中同一格（初次删除前锁定中心）
	# (0,0,0) 节点世界位=(-5.5,-1,-2.0)（批次 Z 12×3×5 实况）；从其左侧 6 单位（块外）沿 +x 打入，
	# y/z 唯一落在 y=0 行、z=0 列，最先命中 (0,0,0) 自身（其世界 AABB x∈[-6,-5]）
	var n_pick: MeshInstance3D = main_vv.call("get_voxel_node", Vector3i(0, 0, 0))
	check(n_pick is MeshInstance3D, "MainView 可取 (0,0,0) 体素节点")
	if n_pick != null:
		var o_hit: Vector3 = n_pick.global_position + Vector3(-6, 0, 0)
		var hit: Variant = inst.call("get_cell_hit", o_hit, Vector3(1, 0, 0))
		check_eq(hit, Vector3i(0, 0, 0), "get_cell_hit 与渲染坐标一致（+x 射线命中 (0,0,0)）")
		check_eq(inst.call("get_cell_hit", o_hit, Vector3(-1, 0, 0)), MISS, "反向离开射线未命中")

	# 相机射线 smoke：MainView 相机视口中心应对准木料（get_cell_hit 包装 ray_to_cell）
	# 注意用 SubViewport.size 求中心（与 project_ray_* 同一坐标系；无头窗口布局退化时容器尺寸不可靠）
	var vp_main: SubViewport = inst.get_node_or_null("MainView/ViewportContainer/SubViewport")
	var cam: Camera3D = inst.get_node_or_null("MainView/ViewportContainer/SubViewport/Camera3D")
	check(vp_main is SubViewport and cam is Camera3D, "MainView 含视口与相机")
	if vp_main is SubViewport and cam is Camera3D and vp_main.size.x > 1 and vp_main.size.y > 0:
		var vpos := Vector2(vp_main.size.x * 0.5, vp_main.size.y * 0.5)
		var cdir: Vector3 = cam.project_ray_normal(vpos)
		check(inst.call("get_cell_hit", cam.project_ray_origin(vpos), cdir) != MISS,
			"视口中心相机射线命中木料（get_cell_hit 包装）")

	# 选区语义（手势接口契约不变，T26）：单选替换 / additive 划选追加切换 / 越界忽略 / 清空
	inst.call("select_voxel", Vector3i(0, 0, 0), false)
	var sel: Array = inst.call("get_selected_voxels")
	check_eq(sel.size(), 1, "普通点击单选 1 格")
	check(_has_cell(sel, Vector3i(0, 0, 0)), "选区含 (0,0,0)")
	check(n_pick != null and n_pick.material_override != main_vv.call("get_voxel_node", Vector3i(1, 0, 0)).material_override,
		"选中格材质≠未选中格（高亮生效）")
	inst.call("select_voxel", Vector3i(1, 0, 0), true)
	check_eq((inst.call("get_selected_voxels") as Array).size(), 2, "划选追加至 2 格（additive 接口）")
	inst.call("select_voxel", Vector3i(1, 0, 0), true)
	check_eq((inst.call("get_selected_voxels") as Array).size(), 1, "划选扫过同一格二次=切换取消（回 1 格）")
	var n1v: MeshInstance3D = main_vv.call("get_voxel_node", Vector3i(1, 0, 0))
	check(n1v != null and n1v.visible == true, "切换取消不改变可见性")
	inst.call("select_voxel", Vector3i(2, 0, 2), false)
	sel = inst.call("get_selected_voxels")
	check_eq(sel.size(), 1, "普通点击替换选区（单格）")
	check(_has_cell(sel, Vector3i(2, 0, 2)), "选区替换为 (2,0,2)")
	var n_pick_c: MeshInstance3D = main_vv.call("get_voxel_node", Vector3i(0, 0, 0))
	var n_sel: MeshInstance3D = main_vv.call("get_voxel_node", Vector3i(2, 0, 2))
	check(n_pick_c != null and n_sel != null and n_pick_c.material_override != n_sel.material_override,
		"替换后旧格取消高亮、新格高亮")
	var sel_before: int = (inst.call("get_selected_voxels") as Array).size()
	inst.call("select_voxel", Vector3i(99, 0, 0), false)
	check_eq((inst.call("get_selected_voxels") as Array).size(), sel_before, "越界体素选择被忽略")
	inst.call("clear_selection")
	check_eq((inst.call("get_selected_voxels") as Array).size(), 0, "clear_selection 清空选区")

	# 删除：3 格 → remaining=177、撤销栈入组、节点隐藏、提示同步；空选/已删幂等安全
	inst.call("select_voxel", Vector3i(0, 0, 0), false)
	inst.call("select_voxel", Vector3i(1, 0, 0), true)  # additive=划选追加语义（手势版保留）
	inst.call("select_voxel", Vector3i(0, 1, 0), true)
	check_eq(int(inst.call("delete_selected")), 3, "删除选中组返回删除数 3")
	check_eq((inst.call("get_remaining_voxels") as Array).size(), 177, "删除后剩余=177")
	check_eq(int(inst.call("get_undo_depth")), 1, "删除后撤销栈长度=1")
	check_eq(int(inst.call("get_redo_depth")), 0, "删除后重做栈清空")
	for c: Vector3i in [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0)]:
		var nd: MeshInstance3D = main_vv.call("get_voxel_node", c)
		check(nd != null and nd.visible == false, "已删格 %s 节点 visible=false" % [c])
	if vox_lbl != null:
		check(vox_lbl.text.contains("177 / 180"), "M-E⑥：删除 3 格后顶栏计数同步 177 / 180（等价替换原 hint 177 断言）")
	check_eq(int(inst.call("get_built_voxel_count")), 632, "删除为隐藏：构建总数 632 不变（180+330+122；批次 Z 实况——左上 Z1 渲染 final=330）")
	check_eq(int(inst.call("delete_selected")), 0, "空选区删除返回 0 不崩")
	check_eq(int(inst.call("get_undo_depth")), 1, "空选删除不入栈")
	inst.call("select_voxel", Vector3i(0, 0, 0), false)
	check_eq((inst.call("get_selected_voxels") as Array).size(), 0, "已删除体素不可再选中")
	check_eq(int(inst.call("delete_selected")), 0, "对已删体素重复删除幂等（0）")
	inst.call("select_voxel", Vector3i(99, 0, 0), false)
	check_eq(int(inst.call("delete_selected")), 0, "越界体素删除安全（0）")

	# 撤销/重做：组粒度恢复/再删、栈清空规则、边界安全
	check(inst.call("undo") == true, "undo 成功返回 true")
	check_eq((inst.call("get_remaining_voxels") as Array).size(), 180, "undo 后剩余恢复 180")
	var n_undo: MeshInstance3D = main_vv.call("get_voxel_node", Vector3i(0, 0, 0))
	check(n_undo != null and n_undo.visible == true, "undo 后节点 visible=true")
	check_eq(int(inst.call("get_undo_depth")), 0, "undo 后撤销栈空")
	check_eq(int(inst.call("get_redo_depth")), 1, "undo 后重做栈=1")
	if vox_lbl != null:
		check(vox_lbl.text.contains("180 / 180"), "M-E⑥：undo 后顶栏计数恢复 180 / 180（等价替换原 hint 180 断言）")
	inst.call("select_voxel", Vector3i(0, 0, 0), false)
	inst.call("select_voxel", Vector3i(1, 0, 0), true)
	check_eq(int(inst.call("delete_selected")), 2, "undo 后重删（新删除清空 redo）返回 2")
	check_eq(int(inst.call("get_redo_depth")), 0, "新删除清空重做栈")
	check_eq((inst.call("get_remaining_voxels") as Array).size(), 178, "重删后剩余=178")
	check(inst.call("redo") == false, "redo 栈已被新删除清空 → false")
	check(inst.call("undo") == true, "undo 重删组")
	check_eq((inst.call("get_remaining_voxels") as Array).size(), 180, "undo 恢复 180")
	check(inst.call("redo") == true, "redo 再删返回 true")
	check_eq((inst.call("get_remaining_voxels") as Array).size(), 178, "redo 后剩余=178")
	var n_redo: MeshInstance3D = main_vv.call("get_voxel_node", Vector3i(1, 0, 0))
	check(n_redo != null and n_redo.visible == false, "redo 后节点重新隐藏")
	check_eq(int(inst.call("get_redo_depth")), 0, "redo 后重做栈空")
	check(inst.call("redo") == false, "redo 空栈安全 false")
	check(inst.call("undo") == true, "再 undo 恢复")
	check(inst.call("undo") == false, "undo 空栈安全 false")
	check_eq((inst.call("get_remaining_voxels") as Array).size(), 180, "全部恢复 180")
	# 组粒度：先删 2 格再删 1 格 → 两次 undo 分组恢复
	inst.call("select_voxel", Vector3i(0, 0, 0), false)
	inst.call("select_voxel", Vector3i(1, 0, 0), true)
	inst.call("delete_selected")
	inst.call("select_voxel", Vector3i(2, 0, 0), false)
	inst.call("delete_selected")
	check_eq((inst.call("get_remaining_voxels") as Array).size(), 177, "两次删除后剩余 177")
	check_eq(int(inst.call("get_undo_depth")), 2, "两次删除撤销栈=2")
	inst.call("undo")
	check_eq((inst.call("get_remaining_voxels") as Array).size(), 178, "第一组 undo 恢复到 178（组粒度）")
	inst.call("undo")
	check_eq((inst.call("get_remaining_voxels") as Array).size(), 180, "第二组 undo 恢复到 180")
	check_eq(int(inst.call("get_redo_depth")), 2, "两次 undo 后重做栈=2")

	# 键盘：Esc 清空 / Ctrl+Z 撤销 / Ctrl+Y 重做 / Ctrl+Shift+Z 重做 / 无修饰键不触发
	inst.call("select_voxel", Vector3i(0, 0, 0), false)
	inst.call("select_voxel", Vector3i(1, 0, 0), true)
	inst.call("_unhandled_input", _key(KEY_ESCAPE, false, false))
	check_eq((inst.call("get_selected_voxels") as Array).size(), 0, "Esc 清空选区")
	inst.call("select_voxel", Vector3i(0, 0, 0), false)
	inst.call("select_voxel", Vector3i(1, 0, 0), true)
	inst.call("delete_selected")
	check_eq((inst.call("get_remaining_voxels") as Array).size(), 178, "键盘用例前置：删 2 格剩 178")
	inst.call("_unhandled_input", _key(KEY_Z, true, false))
	check_eq((inst.call("get_remaining_voxels") as Array).size(), 180, "Ctrl+Z 撤销删除")
	inst.call("_unhandled_input", _key(KEY_Z, true, true))
	check_eq((inst.call("get_remaining_voxels") as Array).size(), 178, "Ctrl+Shift+Z 亦可重做")
	inst.call("_unhandled_input", _key(KEY_Z, true, false))
	check_eq((inst.call("get_remaining_voxels") as Array).size(), 180, "Ctrl+Z 再次撤销（重填重做栈）")
	inst.call("_unhandled_input", _key(KEY_Y, true, false))
	check_eq((inst.call("get_remaining_voxels") as Array).size(), 178, "Ctrl+Y 重做删除")
	inst.call("select_voxel", Vector3i(2, 0, 2), false)  # 未被删过的格，选中应成功
	inst.call("_unhandled_input", _key(KEY_Z, false, false))
	check_eq((inst.call("get_selected_voxels") as Array).size(), 1, "无修饰键 Z 不触发撤销（选区不受影响）")
	check_eq((inst.call("get_remaining_voxels") as Array).size(), 178, "无修饰键 Z 不改变剩余数")
	inst.call("clear_selection")

	# undo 恢复的体素可再次选中删除（存在性判定正确）
	inst.call("select_voxel", Vector3i(3, 0, 0), false)
	check_eq((inst.call("get_selected_voxels") as Array).size(), 1, "恢复后体素可再选中")
	check_eq(int(inst.call("delete_selected")), 1, "恢复后体素可再删除")

	# 其它视图不受挖除影响
	check_eq(int(target_vv.call("get_voxel_count")), 330, "TargetView（Z1 最终成品=final）体素数不受挖除影响（330，批次 Z 实况）")

	# ---- J2-4（批次 J / A3）：MainView 轨道相机 + 程序化木纹 + 拖拽/拾取互斥 + 滚轮缩放 ----
	# 4a. 默认位姿（M-E① 等价替换：yaw -35→45°、pitch 22→35.264°、距离 6→固定 20 正交）
	check(inst.has_method("_update_main_camera"), "A3：轨道相机更新入口存在")
	var yaw0: float = _fget(inst, "_orbit_yaw")
	var pitch0: float = _fget(inst, "_orbit_pitch")
	check(absf(rad_to_deg(yaw0) - 45.0) < 0.05, "M-E①：初始 yaw=45°（真等轴测；等价替换 A3 -35°）")
	check(absf(rad_to_deg(pitch0) - 35.264) < 0.05, "M-E①：初始 pitch≈35.264°（等价替换 A3 22°）")
	if cam is Camera3D:
		check(absf(cam.position.length() - 20.0) < 0.01,
			"M-E①：相机距离固定 20（等价替换 K6-1 ≈6；裁切根因根除）")
		check(int(cam.projection) == int(Camera3D.PROJECTION_ORTHOGONAL),
			"M-E①：投影=PROJECTION_ORTHOGONAL（正交等轴测风）")

	# 4b. 程序化木纹：浅/深两材质均带 albedo 噪声纹理
	var ml: StandardMaterial3D = inst.get("_mat_light") as StandardMaterial3D
	var md: StandardMaterial3D = inst.get("_mat_dark") as StandardMaterial3D
	check(ml != null and ml.albedo_texture != null, "A3：浅木材质带程序化木纹贴图")
	check(md != null and md.albedo_texture != null, "A3：深木材质带程序化木纹贴图")

	# 4c~4f 经 ViewportContainer.gui_input 真实信号路径喂事件
	var cont: SubViewportContainer = inst.get_node_or_null("MainView/ViewportContainer") as SubViewportContainer
	check(cont != null, "A3 前置：MainView ViewportContainer 存在")
	if cont != null and cam is Camera3D:
		var vps: SubViewport = inst.get_node_or_null("MainView/ViewportContainer/SubViewport") as SubViewport
		var center := Vector2(vps.size.x * 0.5, vps.size.y * 0.5)  # 视口中心（相机对准原点必命中木料）
		# 4c. K6-6 空白拖动旋转：按下（空白起点）→ motion 位移 → 抬起：yaw 改变且不拾取
		var yaw_b: float = _fget(inst, "_orbit_yaw")
		# 事件坐标=容器局部坐标=视口坐标（stretch=true、stretch_shrink=1，同场景 _to_viewport_pos）
		var empty_press := Vector2(10, 10)
		var hit_corner: Vector3i = inst.call("get_cell_hit",
			cam.project_ray_origin(empty_press), cam.project_ray_normal(empty_press))
		if hit_corner != MISS:
			empty_press = Vector2(10, 2)  # 近邻角落仍命中木料时上移取空白（拉近后木料占屏更大）
		cont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, true, empty_press))
		cont.gui_input.emit(_mm_at(empty_press + Vector2(30, 0)))
		cont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, empty_press + Vector2(30, 0)))
		check(not is_equal_approx(_fget(inst, "_orbit_yaw"), yaw_b), "K6-6：空白按住拖动改 yaw（旋转生效）")
		check((inst.call("get_selected_voxels") as Array).is_empty(), "K6-6：空白拖动抬起不误拾取/不清选（选区仍空）")
		# 4d. K6-5 划选多选：按下命中木料→连续 motion 追加→抬起；划选与旋转互斥、只选不删
		var hit_c: Vector3i = inst.call("get_cell_hit", cam.project_ray_origin(center), cam.project_ray_normal(center))
		check(hit_c != MISS, "K6-5 前置：视口中心射线命中木料（划选起点）")
		if hit_c != MISS:
			var rem_n: int = (inst.call("get_remaining_voxels") as Array).size()
			var yaw_b2: float = _fget(inst, "_orbit_yaw")
			# 步进 60px×3：无头视口实测 679×447（K-A display 配置），拉近 dist=6 后
			# 体素屏幕宽 ≈49px、4c 旋转后更大——20px 步进为亚体素不落拍（plan 假设旧 100px 视口）
			cont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, true, center))
			cont.gui_input.emit(_mm_at(center + Vector2(60, 0)))
			cont.gui_input.emit(_mm_at(center + Vector2(120, 0)))
			cont.gui_input.emit(_mm_at(center + Vector2(180, 0)))
			cont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, center + Vector2(180, 0)))
			check((inst.call("get_selected_voxels") as Array).size() >= 2, "K6-5：按住左键划动连续拾取（选区 ≥2 格）")
			check(is_equal_approx(_fget(inst, "_orbit_yaw"), yaw_b2), "K6-5：体素上划选不触发旋转（划选/旋转互斥）")
			check_eq((inst.call("get_remaining_voxels") as Array).size(), rem_n, "K6-5：划选只选不删（remaining 不变）")
			inst.call("clear_selection")
		# 4e. 单击拾取：按下=抬起同点（未超阈值）→ 拾取选中且相机不转
		var yaw_b3: float = _fget(inst, "_orbit_yaw")
		cont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, true, center))
		cont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, center))
		check(is_equal_approx(_fget(inst, "_orbit_yaw"), yaw_b3), "A3：单击不旋转")
		check_eq((inst.call("get_selected_voxels") as Array).size(), 1, "A3：单击抬起=拾取选中（中心命中木料）")
		inst.call("clear_selection")
		# 4f. 滚轮缩放（M-E① 等价替换：_cam_dist [4.5,14] 距离语义 → ortho size 语义
		#     ×0.9/×1.1；回修4 A：限幅下限=「当前朝向窗口适配动态下限」——废除直径×0.30
		#     固定倍数，最大放大档=块投影完整落在窗口内（四周留 ≥8px 边距）不穿帮）
		var size0: float = _fget(inst, "_ortho_size_main")
		var d_main := Vector3(inst.get("_voxel_size")).length()
		cont.gui_input.emit(_mb(MOUSE_BUTTON_WHEEL_UP, true, center))
		var s1: float = _fget(inst, "_ortho_size_main")
		check(s1 <= size0 + 0.0001 and s1 > 0.0,
			"M-E①：滚轮上 size 不放大（×0.9；触及当前朝向极限档时被钳回）")
		check(inst.has_method("_ortho_size_min_for"), "回修4 A：动态下限函数存在（滚轮/旋转共用口径）")
		for i: int in 40:
			cont.gui_input.emit(_mb(MOUSE_BUTTON_WHEEL_DOWN, true, center))
		check(absf(_fget(inst, "_ortho_size_main") - d_main * 4.0) < 0.01,
			"M-E①：滚轮放大越界夹在直径×4.0（等价替换 K6-1 夹 14）")
		for i: int in 60:
			cont.gui_input.emit(_mb(MOUSE_BUTTON_WHEEL_UP, true, center))
		var smin_l: float = float(inst.call("_ortho_size_min_for", "Main",
			float(inst.get("_orbit_yaw")), float(inst.get("_orbit_pitch"))))
		check(absf(_fget(inst, "_ortho_size_main") - smin_l) < 0.01,
			"回修4 A：滚轮到底=夹在当前朝向动态下限（%.3f；最大档块投影完整留边）" % smin_l)

		# 5a. M-E④ 等价替换留痕（原 K6-5「Ctrl 修饰废除」）：Ctrl 切换判定已回归按下路径
		#     （additive 切换）；抬起路径仍无 Ctrl 特判=单选替换语义不变
		var ev_press := _mb(MOUSE_BUTTON_LEFT, true, center)
		var ev_release := _mb(MOUSE_BUTTON_LEFT, false, center)
		ev_release.ctrl_pressed = true
		cont.gui_input.emit(ev_press)
		cont.gui_input.emit(ev_release)
		check_eq((inst.call("get_selected_voxels") as Array).size(), 1,
			"M-E④：抬起带 ctrl 无特判=单选替换（切换判定在按下路径）")
		inst.call("clear_selection")
		# 5b. 空选删除：动态提示为「划选」话术（M-E⑥ 模板下仍保留）
		inst.call("delete_selected")
		check(hint != null and hint.text.contains("划选"),
			"K6-5：空选删除提示「请先按住左键划选…」话术保留")
		# 5c. 主视图滚轮放大 30 次：夹紧不超过直径×4.0（M-E① 等价替换 K6-4 限界 14）
		for i: int in 30:
			cont.gui_input.emit(_mb(MOUSE_BUTTON_WHEEL_DOWN, true, center))
		check(_fget(inst, "_ortho_size_main") <= d_main * 4.0 + 0.0001,
			"M-E①：放大 30 次限界 size<=直径×4.0")
		# 5d. P1-2 契约①（无头等价）：关卡顶栏按钮均为可交互控件，不启动无边框拖窗
		var wm_s: Script = load("res://scripts/window_manager.gd") as Script
		check(wm_s != null, "K6：window_manager.gd 可加载（拖窗契约抽查前置）")
		if wm_s != null:
			for bpath: String in ["TopBar/Buttons/EyeButton", "TopBar/Buttons/JoinButton", "TopBar/Buttons/ExitButton"]:
				var bb: Node = inst.get_node_or_null(bpath)
				check(bb != null and bool(wm_s.call("is_interactive_control", bb)),
					"P1-2 契约①：%s 命中 is_interactive_control（关卡 3D 输入不拖窗）" % bpath)
		# 6a. P3-1（审查回修）：划选按下扫过已选格不 toggle 取消（与 motion 的 not-has 守卫同语义，spec §10.4）
		# M-E 调参留痕：motion 步进 60→30px——正交 size 已被 5c 推到上限（直径×4），
		# 1 体素水平投影≈8.7px、块半宽≈52px，60px 会越出块外（扫空→抬起落单选替换分支）
		inst.call("clear_selection")
		var hit_a: Vector3i = inst.call("get_cell_hit", cam.project_ray_origin(center), cam.project_ray_normal(center))
		if hit_a != MISS:
			inst.call("select_voxel", hit_a, false)  # 先单选该格
			cont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, true, center))  # 再按下同格（修复前=toggle 取消起点格）
			cont.gui_input.emit(_mm_at(center + Vector2(30, 0)))
			cont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, center + Vector2(30, 0)))
			var sel6a: Array = inst.call("get_selected_voxels")
			check(sel6a.has(hit_a) and sel6a.size() >= 2,
				"P3-1：划选按下已选格不取消（起点保留+扫出新格追加）")
			inst.call("clear_selection")
		# 6b. N批等价替换（spec §6.4/§五 4~5）：_toggle_focus 最小集成——单控制器三通道同权激活/
		#     完整倒放恢复 + _begin_success 强制退聚焦（deactivate_immediate 调用链语义零改动）
		inst.call("select_voxel", Vector3i(5, 1, 2), false)
		var sside: Dictionary = inst.get("_side_selected")
		var tvv2: Node = inst.get_node_or_null("TargetView/ViewportContainer/SubViewport/VoxelView")
		var jvv2: Node = inst.get_node_or_null("JoinView/ViewportContainer/SubViewport/VoxelView")
		var tb: Array = tvv2.call("get_built_cells")
		var jb: Array = jvv2.call("get_built_cells")
		sside["Target"][tb[0]] = true
		sside["Join"][jb[0]] = true
		inst.call("_toggle_focus")
		var fxm: Node = inst.get("_fx_main")
		check(fxm != null and fxm == inst.get("_fx_target") and fxm == inst.get("_fx_join"),
			"N3：三句柄=同一全屏控制器（通道引用，spec §五 5）")
		check(bool(fxm.call("is_channel_active", "Main")) and bool(fxm.call("is_channel_active", "Target")) \
			and bool(fxm.call("is_channel_active", "Join")),
			"P2-2→N3：主+左上+右上三通道同权激活（三色共存，N批等价替换）")
		check(bool(fxm.call("is_active")), "P2-2→N3：聚焦中控制器活跃（is_active 面保留）")
		var n_hid: MeshInstance3D = main_vv.call("get_voxel_node", Vector3i(7, 2, 4))
		var n_hidt: MeshInstance3D = tvv2.call("get_voxel_node", tb[1])
		check(n_hid != null and n_hid.visible == true,
			"N3：凝聚期主视图未选中格仍可见（实体→点云面过渡，修瞬时 hide 卡顿）")
		await create_timer(0.35).timeout  # > CONDENSE_TIME 0.25
		check(n_hid != null and n_hid.visible == false,
			"P2-2→N3：凝聚完成后主视图未选中格隐藏（点云面接管，M批等价替换）")
		check(n_hidt != null and n_hidt.visible == false,
			"P2-2→N3：凝聚完成后侧视图未选中格隐藏（同权，M批等价替换）")
		inst.call("_toggle_focus")
		check(not bool(fxm.call("is_active")),
			"P2-2→N3：再切聚焦 → 控制器退出（RETURN 完整倒放，N批等价替换）")
		# N3 等价替换（spec §6.4 目标 2）：deactivate=完整倒放（散点收拢→点云面→实体还原 0.6s），
		# 体素在倒放完成后恢复——原「收回 0.4s」断言按时长等价替换并留痕。
		await create_timer(0.75).timeout
		check(n_hid != null and n_hid.visible == true and n_hidt != null and n_hidt.visible == true,
			"P2-2：倒放完成后主/侧隐藏格全恢复（可恢复；M-Gb→N3 等价替换）")
		# _begin_success 强制退聚焦（防回归挂点；N批等价替换（spec §6.6 四段式）：deactivate_immediate
		# 先行立即复位后，成功凝聚三通道同帧接管 → 相位=CONDENSE；聚焦隐藏格已被 immediate 还原
		# （n_hid 重见=复位实证），随即由成功凝聚保持于屏（凝聚段体素在屏，风险 9）——调用链零改动）
		inst.call("_toggle_focus")
		await create_timer(0.35).timeout  # 推进过凝聚段（体素已隐藏态下验证 immediate）
		check(bool(fxm.call("is_active")), "P2-2 前置：重新聚焦激活")
		var fx_cm: Dictionary = (load("res://scripts/focus_fx.gd") as Script).get_script_constant_map()
		var fx_condense: int = int(fx_cm.get("PHASE_CONDENSE", -1))
		inst.call("_begin_success")
		check(bool(inst.get("_focus_active")) == false and int(fxm.call("get_phase")) == fx_condense,
			"P2-2→N4：_begin_success 强制退聚焦（_focus_active=false；immediate 先行复位后成功凝聚接管，N批等价替换留痕）")
		check(n_hid != null and n_hid.visible == true and bool(inst.get("_success_started")),
			"N3→N4：deactivate_immediate 先行立即复位（聚焦隐藏格还原至在屏，调用链零改动——旧 IDLE 后置断言等价替换）")
		inst.call("_skip_success_animation")
		inst.call("clear_selection")

	# ---- 7. 批次 R（spec §11.2）：合成事件经 push_input(ev, true) 的 STROKE_DESELECT 端到端 ----
	# 手势右笔取消模式复用批次 Q1 Ctrl+左键路径（§5.4）；本段验证 content 坐标合成事件
	# 经真实输入管线（Viewport.push_input）路由到 ViewportContainer.gui_input 并触发反选。
	# 实例口径注记（偏离 plan 原文「复用 inst」）：前置 P2-2 段已 _begin_success/_skip_
	# success_animation（_input_locked=true + 结算覆盖层在场），gui_input 首行锁守卫会拦死
	# 复用路径（死段）——改用全新实例 inst_re 承载本段，端到端意图（真管线 push_input）不变。
	var packed_re: PackedScene = load(SCENE_PATH) as PackedScene
	var inst_re: Node = (packed_re as PackedScene).instantiate() if packed_re != null else null
	check(inst_re != null, "R-E 前置：level_scene.tscn 二次实例化（独立干净态）")
	if inst_re != null:
		inst_re.call("set_context", {"chapter": 1})
		add_child(inst_re)
		await process_frame
		await process_frame
		var cont_re: SubViewportContainer = inst_re.get_node("MainView/ViewportContainer")
		var sub_re: SubViewport = inst_re.get_node("MainView/ViewportContainer/SubViewport")
		var cam_re: Camera3D = inst_re.get_node_or_null("MainView/ViewportContainer/SubViewport/Camera3D")
		check(cont_re != null and cam_re != null, "R-E 前置：主视容器与相机在位")
		var vpos_re := Vector2(sub_re.size.x * 0.5, sub_re.size.y * 0.5)
		var hit_re: Vector3i = inst_re.call("get_cell_hit",
			cam_re.project_ray_origin(vpos_re), cam_re.project_ray_normal(vpos_re))
		check(hit_re != MISS, "R-E 前置：视口中心命中木料")
		if hit_re != MISS:
			inst_re.call("select_voxel", hit_re, false)   # 先选中该格
			# content 坐标 = 容器全局位 + 容器局部位（stretch=canvas_items 下 global_position
			# 即 content 坐标；容器局部=视口坐标，stretch_shrink=1，与场景 _to_viewport_pos 同口径）
			var content_pos: Vector2 = (cont_re as Control).global_position + vpos_re
			var ev_p := InputEventMouseButton.new()
			ev_p.button_index = MOUSE_BUTTON_LEFT
			ev_p.pressed = true
			ev_p.ctrl_pressed = true
			ev_p.position = content_pos
			ev_p.global_position = content_pos
			inst_re.get_viewport().push_input(ev_p, true)   # in_local_coords=true（spec §4.2 终态）
			var ev_r := InputEventMouseButton.new()
			ev_r.button_index = MOUSE_BUTTON_LEFT
			ev_r.pressed = false
			ev_r.ctrl_pressed = true
			ev_r.position = content_pos
			ev_r.global_position = content_pos
			inst_re.get_viewport().push_input(ev_r, true)
			check(not ((inst_re.call("get_selected_voxels") as Array).has(hit_re)),
				"批次 R：push_input 合成 Ctrl+按下 → 命中已选块即刻取消（STROKE_DESELECT 端到端）")
			check((inst_re.call("get_selected_voxels") as Array).is_empty(), "R-E：选区已空（无残留）")

	# ---- 8. 批次 R（R-C 9e5a698 端到端固化）：无 cursor_move 直接伸二指 → 屏外哨兵无动作 ----
	# 左手跳过光标态直接二指（2 帧确认）→ two_down 到达 Router 时 _last_cursor_pos 缺 "left"
	# 键 → 取 .get 缺省屏外哨兵 (-1,-1) → _panel_at 不命中 → panel==null 无动作（§5.2）。
	# 回归防护：若该取值回退为缺失键直接下标，本段 feed 运行时报错中断（R-C 自查回修口径）。
	var bridge_re: Node = get_root().get_node_or_null("GestureBridge")
	var router_re: Node = load("res://autoload/gesture_router.gd").new()
	router_re.name = "GestureRouterProbeRE"
	add_child(router_re)
	router_re.call("_setup")
	if bridge_re != null:
		bridge_re.call("_set_state", 1)  # READY（feed 守卫链前提，§9.1；与点云路由测试同口径）
	var h_two_re := _re_hand([0.1, 0.9, 0.9, 0.1, 0.1], Vector2(0.5, 0.5))
	router_re.call("feed", {"left": h_two_re, "right": null, "timestamp": 0.0})
	router_re.call("feed", {"left": h_two_re, "right": null, "timestamp": 0.0})  # 第 2 帧 → two_down
	check(router_re.get("_active_panel") == null,
		"批次 R：无 cursor_move 直接伸二指 → 不激活任何面板（屏外哨兵无动作，9e5a698 端到端固化）")
	if inst_re != null:
		check((inst_re.call("get_selected_voxels") as Array).is_empty(),
			"批次 R：无 cursor_move 二指笔无选区效应（§5.2 静默）")
	router_re.call("feed", {"left": _re_hand([0.1, 0.9, 0.1, 0.1, 0.1], Vector2(0.5, 0.5)),
		"right": null, "timestamp": 0.0})  # 光标帧 → feed 链存活探针
	check((router_re.get("_last_cursor_pos") as Dictionary).has("left"),
		"批次 R：无 cursor_move 笔后 feed 链仍存活（cursor_move 正常记账）")
	router_re.call("feed", {"left": _re_hand([0.1, 0.1, 0.1, 0.1, 0.1], Vector2(0.5, 0.5)),
		"right": null, "timestamp": 0.0})  # 全收指收笔（two_up 兜底清态卫生）
	router_re.queue_free()
	if inst_re != null:
		inst_re.queue_free()

	inst.queue_free()
	finish()

## 批次 R 第 8 段夹具：合成左手手 dict（spec §3.3 字段表最小集；lm8=食指尖、腕0/食根5/小根17
## 供掌面朝镜判定；布点取左掌朝镜 cz<0 分支，与 test_gesture_map 旋向口径一致）。
func _re_hand(fingers: Array, tip: Vector2) -> Dictionary:
	var lm: Array = []
	for i: int in 21:
		lm.append([0.5, 0.5, 0.0])
	lm[0] = [tip.x - 0.05, tip.y + 0.2, 0.0]
	lm[5] = [lm[0][0] + 0.05, lm[0][1] - 0.06, 0.0]   # 左掌朝镜：cz<0
	lm[17] = [lm[0][0] - 0.05, lm[0][1] - 0.05, 0.0]
	lm[8] = [tip.x, tip.y, 0.0]
	lm[9] = [lm[0][0], lm[0][1] - 0.2, 0.0]
	return {
		"gesture": "", "gesture_id": 0, "confidence": 0.9,
		"hand_x": tip.x, "hand_y": tip.y, "hand_z": 0.0,
		"hand_rotation_x": 5.0, "hand_rotation_y": 0.0, "hand_rotation_z": 0.0,
		"fingers": fingers, "pinch_distance": 0.5, "hand_index": 0, "handedness": "Left",
		"landmarks": lm, "fps": 30.0, "is_detected": true, "timestamp": 0.0, "palm_size": 0.2}
