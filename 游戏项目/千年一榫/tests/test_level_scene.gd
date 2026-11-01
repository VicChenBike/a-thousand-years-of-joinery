extends "res://tests/test_base.gd"
## 批次 D 判定用例：第 1 关关卡数据 + 关卡场景骨架（TDD 先写，实现前全 [FAIL] 属预期）。
## 契约来源：批次 D 任务单（与 技术文档/接口规范_关卡数据.md §2~§5 一致）：
##   关卡数据：levels_data/level_chapter1_hemudu.json——format_version=1、level_id=chapter1_editor
##     （批次 Z Z2：编辑器 levels/level_1 五件套一次性快照导入，元数据按五件套 level.json 实况）、
##     chapter=1；LevelLibrary.validate_level 通过（ok=true、0 条警告）；
##     scan_directory(res://levels_data) 后 get_level(1) 非空且 title 非空；
##     可玩性：初始实心体素与 target 差 ≥ 8（有挖除量）；
##     批次 Z（Z2 用户拍板「final 原样导入」）：final_answer ≠ target ∪ join（330≠243）——
##     旧 union 硬断言放宽为「final 非空 + 尺寸合法（各维 1~32、体素界内过滤后非空）」。
##   体素辅助脚本：scripts/level_voxel_view.gd——build_voxels(voxels,size,material)/clear_voxels/
##     get_voxel_count()；非法坐标跳过。
##   关卡场景：scenes/level/level_scene.tscn（=Game.SCENE_PATHS[LEVEL] 路径）：
##     Background(TextureRect，纹理=bg_chapter1.png)；三面板 TargetView(左上·目标)/
##     JoinView(右上·固定件)/MainView(中央·木料)，各含 ViewportContainer(SubViewportContainer)
##     →SubViewport→Camera3D+VoxelView；TopBar（Title/Talent/Timer+锐眼/对接/退出，
##     「对接」主按钮视觉更大）；HintLabel；WitnessPortrait（左下见证者占位）。
##   交互契约：set_context({"chapter":1}) 先于 add_child（Game 路由约定，同 T14）；
##     数据加载后 MainView=blocks、TargetView=final_answer.voxels（批次 Z Z1 换源 final，target 零渲染）、
##     JoinView=join_part.voxels；get_built_voxel_count() 暴露总构建体素数（测试钩子）。
## 环境说明：--script 无头模式 7 个 autoload 已注册，经 /root/<Name> 动态引用
## （T08/T10/T14 实测）；主脚本不能用全局标识符/class_name，故一律 load()/call()。

const SCENE_PATH := "res://scenes/level/level_scene.tscn"
const LEVEL_JSON := "res://levels_data/level_chapter1_hemudu.json"
const VOXEL_VIEW_SCRIPT := "res://scripts/level_voxel_view.gd"
const BG_PATH := "res://assets/backgrounds/bg_chapter1.png"

# ===== 批次 W 清档纪律补齐（W6 全量回归甄别：P1-1「select_voxel 后聚焦钮解禁」受 user://
# 残留 level_progress 断点档泄入——预挖体素（如 (0,0,0) 已删）致选区落空，W6 定性「测试隔离
# 缺口」成立）。对齐 tools/README_走查清档规范.md 与 test_level_interaction「移走 save.json
# 单跑」先例 + test_w_save_resilience 自愈先例：起测前残留备份先还原→重新备份→清域（断点/
# 旗标归零，P1-1 确定性前置），终测 finish 统一还原 + save.json 逐字节等价自检。=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_w6ls_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
var _pre_save_text: String = ""

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _backup_user() -> void:
	for p0: String in DISC_WATCHED:
		var bk0: String = DISC_BK_PREFIX + p0.get_file()
		if FileAccess.file_exists(_disc_abs(bk0)):
			if FileAccess.file_exists(_disc_abs(p0)):
				DirAccess.remove_absolute(_disc_abs(p0))
			DirAccess.copy_absolute(_disc_abs(bk0), _disc_abs(p0))
			DirAccess.remove_absolute(_disc_abs(bk0))
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(_disc_abs(p)):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)
			DirAccess.remove_absolute(_disc_abs(p))   # 清域（断点/旗标归零，select_voxel 确定性）

func _restore_user() -> void:
	for c: Node in root.get_children():
		if not ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager", "GestureBridge",
				"LevelLibrary", "Game", "GestureRouter", "I18n"].has(String(c.name)):
			c.free()   # 先 free 测试挂载节点（level._exit_tree 兜底写档先落盘，规范第 6 条）
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(_disc_abs(p)):
			DirAccess.remove_absolute(_disc_abs(p))
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(_disc_abs(bk)):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(_disc_abs(bk))
	var real_sm: Node = root.get_node_or_null("SaveManager")
	if real_sm != null:
		real_sm.load_game()   # 内存重同步（防后续 save_game 把测试态写回真实档案）
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")

func finish() -> void:
	_restore_user()
	super.finish()

func _read_json(p: String) -> Variant:
	var f: FileAccess = FileAccess.open(p, FileAccess.READ)
	if f == null:
		return null
	var v: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return v

func _initialize() -> void:
	print("== test_level_scene ==")
	_backup_user()   # 清档纪律（见上块注）：断点残留隔离，P1-1 select_voxel 确定性前置
	get_root().get_node("SaveManager").call("load_game")   # 清域后内存重同步（空档默认值）
	var lib: Variant = get_root().get_node("LevelLibrary")

	# ---- 1. 关卡数据契约（任务 1）----
	check(FileAccess.file_exists(LEVEL_JSON), "levels_data/level_chapter1_hemudu.json 存在")
	var raw_v: Variant = _read_json(LEVEL_JSON)
	var raw: Dictionary = raw_v if typeof(raw_v) == TYPE_DICTIONARY else {}
	check(not raw.is_empty(), "关卡 JSON 可解析为字典")
	if raw.is_empty():
		finish()
		return
	check_eq(int(raw.get("format_version", -1)), 1, "format_version=1（规范 §2）")
	check_eq(String(raw.get("level_id", "")), "chapter1_editor", "level_id=chapter1_editor（批次 Z 编辑器五件套实况；旧值 chapter1_hemudu 等价替换留痕）")
	check_eq(int(raw.get("chapter", -1)), 1, "chapter=1")
	check(not String(raw.get("title", "")).is_empty(), "title 非空")
	check(not String(raw.get("era", "")).is_empty(), "era 非空")

	var vr: Dictionary = lib.validate_level(raw)
	check(bool(vr.get("ok", false)), "validate_level 通过（ok=true）")
	check_eq((vr.get("warnings", [] ) as Array).size(), 0, "validate_level 0 条严重警告")
	# 独立实例复验（与 test_level_library 同约定：LevelLibrary.new() 可脱离 autoload 使用）
	var lib2: Node = (load("res://autoload/level_library.gd") as GDScript).new()
	add_child(lib2)
	var vr2: Dictionary = lib2.validate_level(raw)
	check(bool(vr2.get("ok", false)), "LevelLibrary.new() 独立实例 validate_level 通过")
	lib2.queue_free()

	lib.scan_directory("res://levels_data")
	var lvl: Dictionary = lib.get_level(1)
	check(not lvl.is_empty(), "scan_directory(res://levels_data) 后 get_level(1) 非空")
	check(not String(lvl.get("title", "")).is_empty(), "get_level(1) title 非空")
	if lvl.is_empty():
		finish()
		return
	var piece: Dictionary = ((lvl["data"] as Dictionary)["pieces"] as Array)[0]
	var blocks: Array = piece.get("blocks", [])
	var target: Array = (piece.get("target_shapes", [[]]) as Array)[0]
	var join_voxels: Array = (piece.get("join_part", {}) as Dictionary).get("voxels", [])
	var final_voxels: Array = (piece.get("final_answer", {}) as Dictionary).get("voxels", [])
	check(blocks.size() >= 1, "blocks（初始实心体素）非空")
	check(blocks.size() <= 200, "体素总数 ≤ 200（设计约束）")
	check(blocks.size() - target.size() >= 8, "initial 与 target 差 ≥ 8（有挖除量，可玩）")
	# 批次 Z（Z2，用户拍板「final 原样导入」）：编辑器五件套 final=330 ≠ target∪join（243）——
	# 旧硬断言「final_answer = target ∪ join」放宽为「非空 + 尺寸合法（各维 1~32、体素界内
	# 过滤后非空）」（接口规范 §5「语义上 = target ∪ join（供校验，不强制）」口径回归）。
	# 断言数 3→5 只增不减；交叠断言改实况钉值 39（新数值取自新数据实况）。
	var fset: Dictionary = {}
	for v: Variant in final_voxels:
		fset[v] = true
	check(final_voxels.size() > 0, "final_answer 非空（Z2 放宽口径①，替换旧 union 断言）")
	check_eq(fset.size(), final_voxels.size(), "final_answer 无重复坐标")
	var f_sz: Dictionary = (piece.get("final_answer", {}) as Dictionary).get("size", {})
	var f_dim_ok: bool = true
	for axis: String in ["x", "y", "z"]:
		var fv: int = int(f_sz.get(axis, 0))
		if fv < 1 or fv > 32:
			f_dim_ok = false
	check(f_dim_ok, "final_answer.size 各维 1~32（Z2 放宽口径②：%s）" % str(f_sz))
	var f_in_bounds: bool = true
	for v: Variant in final_voxels:
		var pf: PackedStringArray = String(v).split(",")
		if pf.size() != 3:
			f_in_bounds = false
			continue
		var cf_x := int(pf[0]); var cf_y := int(pf[1]); var cf_z := int(pf[2])
		if cf_x < 0 or cf_x >= int(f_sz.get("x", 0)) or cf_y < 0 or cf_y >= int(f_sz.get("y", 0)) \
				or cf_z < 0 or cf_z >= int(f_sz.get("z", 0)):
			f_in_bounds = false
	check(f_in_bounds and final_voxels.size() > 0,
		"final_answer 体素全部界内（final_answer.size 域过滤后非空，Z2 放宽口径③）")
	var tset: Dictionary = {}
	for v: Variant in target:
		tset[v] = true
	var overlap: int = 0
	for v: Variant in join_voxels:
		if tset.has(v):
			overlap += 1
	# Z2 等价改写：旧占位关 overlap==0（榫头嵌入卯眼孔位）→ 五件套实况 target∩join=39 格——
	# evaluate_join 判定 success 先于干涉（level_scene.gd 等价优先），交叠不影响可通关。
	check_eq(overlap, 39, "第 1 关 target∩join 交叠=39 格（五件套实况钉值；success 判定优先于干涉）")

	# ---- 2. LevelVoxelView 辅助脚本契约 ----
	var vv_script: Variant = load(VOXEL_VIEW_SCRIPT)
	check(vv_script != null, "scripts/level_voxel_view.gd 可加载")
	if vv_script == null:
		finish()
		return
	var vv: Node = (vv_script as GDScript).new()
	add_child(vv)
	vv.call("build_voxels", ["0,0,0", "1,0,0", "99,0,0"], Vector3i(8, 3, 8), StandardMaterial3D.new())
	check_eq(int(vv.call("get_voxel_count")), 2, "build_voxels 构建 2 个合法体素（越界坐标跳过）")
	vv.call("clear_voxels")
	check_eq(int(vv.call("get_voxel_count")), 0, "clear_voxels 清空体素")
	vv.queue_free()

	# ---- 3. 关卡场景骨架（任务 2）----
	check(ResourceLoader.exists(SCENE_PATH), "level_scene.tscn 存在（=Game.SCENE_PATHS[LEVEL]）")
	if not ResourceLoader.exists(SCENE_PATH):
		finish()
		return
	var packed: PackedScene = load(SCENE_PATH)
	check(packed != null, "level_scene.tscn 可加载")
	var inst: Node = (packed as PackedScene).instantiate()
	check(inst != null, "关卡场景可实例化（headless 下 SubViewport/Camera3D/体素节点不报错）")
	if inst == null:
		finish()
		return
	inst.call("set_context", {"chapter": 1})  # Game 路由约定：先 set_context 再入树
	add_child(inst)
	await process_frame

	check(inst is Control, "关卡场景根节点为 Control（全屏）")
	check(inst.get_node_or_null("TargetView") != null, "TargetView 面板存在（左上·目标）")
	check(inst.get_node_or_null("JoinView") != null, "JoinView 面板存在（右上·固定件）")
	check(inst.get_node_or_null("MainView") != null, "MainView 面板存在（中央·木料）")
	check(inst.get_node_or_null("TargetView/ViewportContainer") is SubViewportContainer, "TargetView 含 SubViewportContainer")
	check(inst.get_node_or_null("JoinView/ViewportContainer") is SubViewportContainer, "JoinView 含 SubViewportContainer")
	check(inst.get_node_or_null("MainView/ViewportContainer") is SubViewportContainer, "MainView 含 SubViewportContainer")
	check(inst.get_node_or_null("TargetView/ViewportContainer/SubViewport/Camera3D") is Camera3D, "TargetView 视口含 Camera3D")
	check(inst.get_node_or_null("JoinView/ViewportContainer/SubViewport/Camera3D") is Camera3D, "JoinView 视口含 Camera3D")
	check(inst.get_node_or_null("MainView/ViewportContainer/SubViewport/Camera3D") is Camera3D, "MainView 视口含 Camera3D")

	var bg: TextureRect = inst.get_node_or_null("Background")
	check(bg is TextureRect, "根背景 Background(TextureRect) 存在")
	if bg != null:
		check(bg.texture != null and bg.texture.resource_path.ends_with("bg_chapter1.png"), "背景纹理路径为 bg_chapter1.png")

	# ---- J2-1（批次 J / A1）：背景径向渐晕（四边渐亮、四角暗角），不吃输入 ----
	var vg: Node = inst.get_node_or_null("Vignette")
	check(vg is TextureRect, "A1：关卡背景渐晕层存在（TextureRect）")
	check(vg != null and (((vg as TextureRect).texture is GradientTexture2D) or (vg as TextureRect).material != null),
		"A1：渐晕层带径向渐变纹理")
	check(vg != null and (vg as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE, "A1：渐晕层不吃输入")
	# J6-P2-5（渐晕随 theme_changed 即时重建）断言随批次 AB-3 深浅主题机制删除退役——
	# 等价改写为「恒深档角部色护栏」：渐晕纹理 edge 色==Color(0,0,0,0.55)（旧深档值逐一未变）。
	if vg != null:
		var vg_tex: GradientTexture2D = (vg as TextureRect).texture as GradientTexture2D
		var edge_col: Color = vg_tex.gradient.get_color(1) if vg_tex != null else Color()
		check(edge_col.is_equal_approx(Color(0.0, 0.0, 0.0, 0.55)),
			"AB-3 等价改写：渐晕角部恒深档黑 0.55（旧深档值不变；theme_changed 重建机制退役）")

	# ---- J2-2（批次 J / A2）：三面板去棕色实心底板（透明或极淡，alpha<0.25）----
	for panel_name: String in ["TargetView", "JoinView", "MainView"]:
		var pnl: Panel = inst.get_node_or_null(panel_name) as Panel
		check(pnl != null, "A2：%s 仍为 Panel 节点（保留节点类型）" % panel_name)
		if pnl != null:
			var sb: StyleBoxFlat = pnl.get_theme_stylebox("panel") as StyleBoxFlat
			check(sb == null or sb.bg_color.a < 0.25, "A2：%s 无实心底板（透明/极淡）" % panel_name)

	# ---- J2-2（批次 J / A5）：顶栏三按钮上排避让右上设置 + 提示行贴屏幕底部 ----
	# K-H（P1 回修）：K-A 把全局设置钮左移到 -240..-132 后，旧 -128 避让失效——
	# 顶栏「退出」被常驻设置钮压盖不可点（走查 14_KG 实证真点击打开的是设置面板）。
	# 避让下界收紧到 -260（钮右缘 ≤ W-260 < 设置钮左缘 W-240，留 20px 间隙）。
	# 【P1-1 修订 2026-09-08】设置钮现行几何已是 -124..-16（x 1028~1136，test_window_k
	# L-B/L1 新几何契约断言），旧 ≤-260 口径过时保守；顶栏「剩余体素」计数视觉缺失回修
	# （NG-Hb-1 终审）把 TopBar 右端扩到 -132——Buttons shrink_end 贴 TopBar 右缘，
	# 按钮右端 ≤ W-132=1020 < 设置钮左缘 1028，仍留 8px 间隙不压盖（v2 复拍实证）。
	var tb: Control = inst.get_node_or_null("TopBar") as Control
	check(tb != null and tb.offset_right <= -132, "A5/K-H+P1-1：顶栏右缘避让常驻设置钮区（≤-132，按钮右端≤1020<设置钮左缘1028 留 8px）")
	var hint_ctl: Control = inst.get_node_or_null("HintLabel") as Control
	check(hint_ctl != null and hint_ctl.anchor_top > 0.85, "A5：提示行移到屏幕底部")

	# ---- M-A（spec §3.1/§4.2，2026-09-07）：顶栏图标清理——J2-2 旧图标断言按新验收反转留痕 ----
	var eye_icon_btn: Button = inst.get_node_or_null("TopBar/Buttons/EyeButton") as Button
	var join_icon_btn: Button = inst.get_node_or_null("TopBar/Buttons/JoinButton") as Button
	var exit_icon_btn: Button = inst.get_node_or_null("TopBar/Buttons/ExitButton") as Button
	check(eye_icon_btn != null and eye_icon_btn.icon == null, "M-A：锐眼按钮图标已删（icon==null，J2-2 反转留痕）")
	check(join_icon_btn != null and join_icon_btn.icon == null, "M-A：对接按钮图标已删（icon==null，J2-2 反转留痕）")
	check(exit_icon_btn != null and exit_icon_btn.icon == null, "M-A：退出按钮图标已删（icon==null，J2-2 反转留痕）")

	check(inst.get_node_or_null("TopBar/TitleLabel") is Label, "顶部标题 Label 存在")
	check(inst.get_node_or_null("TopBar/TalentLabel") is Label, "天赋值 Label 存在")
	check(inst.get_node_or_null("TopBar/TimerLabel") is Label, "计时 Label 存在")
	check_eq(String((inst.get_node_or_null("TopBar/TimerLabel") as Label).text), "00:00", "计时骨架静态显示 00:00")
	var join_btn: Button = inst.get_node_or_null("TopBar/Buttons/JoinButton")
	var eye_btn: Button = inst.get_node_or_null("TopBar/Buttons/EyeButton")
	var exit_btn: Button = inst.get_node_or_null("TopBar/Buttons/ExitButton")
	check(eye_btn != null and eye_btn.text == "锐眼", "「锐眼」按钮存在")
	check(join_btn != null and join_btn.text == "对接", "「对接」按钮存在")
	check(exit_btn != null and exit_btn.text == "退出", "「退出」按钮存在")
	if join_btn != null and eye_btn != null:
		check(join_btn.custom_minimum_size.x > eye_btn.custom_minimum_size.x, "「对接」为主按钮视觉（更大）")
	var hint: Label = inst.get_node_or_null("HintLabel")
	check(hint is Label, "提示 Label 存在")
	if hint != null:
		check(not hint.text.is_empty(), "提示文本非空（批次 E 生效前占位）")
		# J6-P2-8：提示行固定浅色字+深描边（背景恒为深色章节图，深浅两主题都可读；
		# 描边做法同 J2-2 面板标题：font_outline_color 黑 0.7 + outline_size≥3）
		check(hint.has_theme_color_override("font_outline_color")
			and int(hint.get_theme_constant("outline_size")) >= 3,
			"J6-P2-8：HintLabel 深描边（outline_size≥3，同 J2-2 标题做法）")
		var hfc: Color = hint.get_theme_color("font_color")
		check(hfc.get_luminance() > 0.7, "J6-P2-8：HintLabel 固定浅色字（亮度>0.7，深背景图可读）")
	# J6r3-3：顶栏三标签维持固定浅色字+黑描边（M-E 未动）；
	# 三面板 Title 按 M-E⑤（spec §3.5 拍板 #3）等价替换：随主题柔和色（α0.82~0.85）、
	# 字号 16、描边 2、文案精简——不再吃顶栏同款「浅色+黑描边≥3」口径。
	for lbl_path: String in ["TopBar/TitleLabel", "TopBar/TalentLabel", "TopBar/TimerLabel"]:
		var lb: Label = inst.get_node_or_null(lbl_path) as Label
		check(lb != null and lb.has_theme_color_override("font_color")
			and (lb.get_theme_color("font_color") as Color).get_luminance() > 0.7
			and lb.has_theme_color_override("font_outline_color")
			and int(lb.get_theme_constant("outline_size")) >= 3,
			"J6r3-3：%s 固定浅色字+黑描边（两主题可读，M-E 未动）" % lbl_path)
	# N12-3（用户 2026-09-10「直接去掉那个文字」）等价替换留痕：M-E⑤ 三面板标签收缩为两侧
	# （Target/Join 保留），中央窗 MainView/Title「木料」标签删除（下方新增不存在断言）。
	var me_title_text := {"TargetView/Title": "最终成品", "JoinView/Title": "对接固定件"}  # 批次 Z Z1：左上「对照成品」→「最终成品」（等价替换留痕）
	for lbl_path2: String in ["TargetView/Title", "JoinView/Title"]:
		var lb2: Label = inst.get_node_or_null(lbl_path2) as Label
		check(lb2 != null and lb2.has_theme_color_override("font_color")
			and (lb2.get_theme_color("font_color") as Color).a >= 0.80
			and int(lb2.get_theme_constant("outline_size")) == 2
			and lb2.get_theme_font_size("font_size") == 16,
			"M-E⑤：%s 随主题柔和字（α≥0.80）+描边 2+字号 16（等价替换 J6r3-3）" % lbl_path2)
		check(lb2 != null and String(lb2.text) == String(me_title_text[lbl_path2]),
			"M-E⑤：%s 文案精简「%s」（等价替换留痕）" % [lbl_path2, me_title_text[lbl_path2]])
	check(inst.get_node_or_null("MainView/Title") == null,
		"N12-3：MainView/Title「木料」标签已删除（节点不存在；两侧标签保留）")
	var witness: TextureRect = inst.get_node_or_null("WitnessPortrait")
	check(witness is TextureRect, "左下古今见证者占位(TextureRect) 存在")
	if witness != null:
		check(witness.texture != null, "见证者立绘纹理非空（默认 default_witness.png）")

	# ---- 4. set_context 后数据加载与体素构建（任务 4 核心断言）----
	check(String((inst.get_node_or_null("TopBar/TitleLabel") as Label).text).contains(String(lvl["title"])), "标题显示关卡 title（含章节号）")
	check(String((inst.get_node_or_null("TopBar/TalentLabel") as Label).text).contains("天赋"), "天赋值 Label 显示天赋")
	var built: int = int(inst.call("get_built_voxel_count"))
	check(built > 0, "set_context({chapter:1}) 不崩溃且数据已加载（get_built_voxel_count>0）")
	var main_vv: Node = inst.get_node_or_null("MainView/ViewportContainer/SubViewport/VoxelView")
	var target_vv: Node = inst.get_node_or_null("TargetView/ViewportContainer/SubViewport/VoxelView")
	var join_vv: Node = inst.get_node_or_null("JoinView/ViewportContainer/SubViewport/VoxelView")
	check(main_vv != null and target_vv != null and join_vv != null, "三视图各含 VoxelView 节点")
	if main_vv != null:
		check_eq(int(main_vv.call("get_voxel_count")), blocks.size(), "MainView 体素数 = blocks（初始实心）")
	if target_vv != null:
		# 批次 Z Z1：左上「最终成品」渲染 final_answer（target 关卡内零渲染，只做判定）——
		# 旧断言「= target_shapes[0]」按 Z1 终态等价替换为 final 计数（330 实况）。
		check_eq(int(target_vv.call("get_voxel_count")), final_voxels.size(),
			"TargetView（Z1 最终成品）体素数 = final_answer（%d）" % final_voxels.size())
	if join_vv != null:
		check_eq(int(join_vv.call("get_voxel_count")), join_voxels.size(), "JoinView 体素数 = join_part.voxels")

	# ---- KG-2（批次 K / K6-1/2，spec §10.1/§10.2）：相机拉近限界 + 环境光/补光 + 木纹 roughness ----
	# ---- KG-2 → M-E① 等价替换（spec §3.5）：透视距离常量废止 → 正交等轴测常量 ----
	# K6-1 旧口径 CAM_DIST0=6.0/[4.5,14] 已随 M-E 物理删除（相机在包围球内系裁切根因）
	check_eq(float(inst.get("ORTHO_DIST")), 20.0, "M-E①：ORTHO_DIST=20.0（三视图距离固定）")
	check_eq(float(inst.get("ORTHO_NEAR")), 0.1, "M-E①：ORTHO_NEAR=0.1")
	check_eq(float(inst.get("ORTHO_FAR")), 100.0, "M-E①：ORTHO_FAR=100.0")
	check_eq(float(inst.get("MAIN_FILL_W0")), 0.75,
		"回修4 A：MAIN_FILL_W0=0.75（主初始块投影宽占窗宽目标；等价替换直径×1.25 旧口径）")
	check_eq(float(inst.get("SIDE_FILL_W0")), 0.70,
		"回修4 A：SIDE_FILL_W0=0.70（侧初始宽占比目标；等价替换直径×0.85 旧口径）")
	check(inst.has_method("_ortho_size_min_for"),
		"回修4 A：限幅下限=窗口适配动态函数（等价替换固定倍数 ORTHO_SIZE_MIN_MUL，最大档不穿帮）")
	check_eq(float(inst.get("VIEW_FIT_MARGIN")), 8.0, "回修4 A：VIEW_FIT_MARGIN=8（最大档四周留边 px）")
	check_eq(float(inst.get("ORTHO_SIZE_MAX_MUL")), 4.0, "M-E①：ORTHO_SIZE_MAX_MUL=4.0（缩放上限）")
	# N12b P3-2（审查 A 回修）：SuccessSeg 死枚举处置——HOLD_SPREAD 声明后从未赋值（持续+散开
	# 由 N3 全屏管线相位承载，level 侧 tween 间隔等待，无独立 seg 值），枚举值删除；编号钉死
	# 0/2/3 保持 test_n4_success_flow 段钩子数值契约（0 凝聚/2 聚合/3 回看）不变。
	var seg_map: Variant = inst.get_script().get_script_constant_map().get("SuccessSeg")
	check(seg_map is Dictionary and (seg_map as Dictionary).get("CONDENSE", -1) == 0
		and (seg_map as Dictionary).get("AGGREGATE", -1) == 2
		and (seg_map as Dictionary).get("REVIEW", -1) == 3
		and not (seg_map as Dictionary).has("HOLD_SPREAD"),
		"N12b P3-2：SuccessSeg={CONDENSE:0,AGGREGATE:2,REVIEW:3} 且无 HOLD_SPREAD（死枚举已删，编号钉死保 N4 契约）")
	for view_name: String in ["TargetView", "JoinView", "MainView"]:
		var we: Node = inst.get_node_or_null(view_name + "/ViewportContainer/SubViewport/WorldEnvironment")
		check(we is WorldEnvironment, "K6-2：%s 视口含 WorldEnvironment（环境光补光）" % view_name)
		var env: Environment = (we as WorldEnvironment).environment if we is WorldEnvironment else null
		check(env != null and env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR,
			"K6-2：%s 环境光为 AMBIENT_SOURCE_COLOR" % view_name)
		check(env != null and env.ambient_light_energy > 0.0,
			"K6-2：%s ambient_light_energy>0（任何角度不乌黑）" % view_name)
		var fill: Node = inst.get_node_or_null(view_name + "/ViewportContainer/SubViewport/FillLight")
		check(fill is DirectionalLight3D, "K6-2：%s 含 FillLight 反向补光灯" % view_name)
		check(fill != null and is_equal_approx((fill as DirectionalLight3D).light_energy, 0.4),
			"K6-2：%s FillLight energy=0.4（底部补光层次）" % view_name)
	var matl: StandardMaterial3D = inst.get("_mat_light") as StandardMaterial3D
	check(matl != null and is_equal_approx(matl.roughness, 0.55), "K6-2：木纹材质 roughness 0.7→0.55（层次感）")

	# ---- KG-4（K6-3/7/8 + K4-1/K4-2，spec §10.3/§10.5/§10.6）：三面板 3D 化 + 聚焦钮 + toast 迁移 ----
	check(inst.get_node_or_null("TopBar/Buttons/FocusButton") is Button, "K6-7：TopBar 聚焦按钮存在")
	var focus_b: Button = inst.get_node_or_null("TopBar/Buttons/FocusButton") as Button
	check(focus_b != null and focus_b.text == "聚焦", "K6-7：聚焦按钮文本「聚焦」")
	check(not inst.has_method("_make_fail_toast"), "K4-2：旧 toast 构造 _make_fail_toast 已删")
	check(inst.get_node_or_null("FailToast") == null, "K4-2：FailToast 节点不存在（已迁 Game.toast）")
	# M-E 回修2 B（用户实测推翻 M-E-3「完全不可交互」拍板，等价反转留痕）：
	# 侧面板交互恢复——划选/旋转/缩放路径回归；「误触多选无法取消」由单击空白清选解决
	check(not inst.has_method("_side_pick_nearest"), "回修3 D：48px 就近拾取已物理删除（根因修复留痕）")
	check(inst.has_method("_on_side_view_gui_input"), "回修2 B：_on_side_view_gui_input 接线恢复")
	check(inst.get("_side_selected") is Dictionary
		and (inst.get("_side_selected") as Dictionary).has("Target")
		and (inst.get("_side_selected") as Dictionary).has("Join"),
		"回修2 B：_side_selected 真实选区结构保留（聚焦消费面）")
	# M-E① 侧相机断言保留（非聚焦域，仅从原 fx 循环拆出——N批等价替换留痕）
	for side_name: String in ["TargetView", "JoinView"]:
		var scam: Camera3D = inst.get_node_or_null(side_name + "/ViewportContainer/SubViewport/Camera3D") as Camera3D
		inst.call("_update_side_camera", side_name.trim_suffix("View"))
		check(scam != null and absf(scam.position.length() - 20.0) < 0.01,
			"M-E①：%s 侧相机距离固定 20（等价替换 K6-3 4.5）" % side_name)
		check(scam != null and int(scam.projection) == int(Camera3D.PROJECTION_ORTHOGONAL),
			"M-E①：%s 侧相机正交投影" % side_name)
	# N批等价替换（spec §6.4/§五 4~5）：旧「三视口各挂 FocusFX 实例」断言废止——聚焦重写为
	# 单节点全屏层（场景子节点 FocusFX，CanvasLayer 0；N12b P3-1 注释漂移回修：旧注释 85 已
	# 随 N3 走查定稿 LAYER=0 修正，体内断言早已锁 0）。
	var fx_node: CanvasLayer = inst.get_node_or_null("FocusFX") as CanvasLayer
	check(fx_node != null, "K6-7→N3：场景子节点挂全屏聚焦控制器 FocusFX（N批等价替换）")
	check(fx_node != null and fx_node.layer == 0,
		"N3：全屏层 layer=0（走查定稿：GlobalUI=1/SuccessOverlay=0（P批波2 结算覆盖层避让设置面板）在其上，spec 暂定 85→0 走查可调，N批等价替换）")
	var fxm_h: Node = inst.get("_fx_main")
	check(fxm_h != null and fxm_h == fx_node and fxm_h == inst.get("_fx_target") and fxm_h == inst.get("_fx_join"),
		"N3：三句柄=同一全屏控制器（通道引用，N批等价替换）")
	var fx_chs: Dictionary = fx_node.get("_channels") if fx_node != null else {}
	check(fx_chs.get("Main", {}).get("vp") == inst.get("main_viewport")
		and fx_chs.get("Target", {}).get("vp") == inst.get("target_viewport")
		and fx_chs.get("Join", {}).get("vp") == inst.get("join_viewport"),
		"N3：三通道分别绑定 Main/Target/Join 视口（位置换算单处实现前提）")
	var fx_cont: Control = null
	if fx_node != null:
		for c0: Node in fx_node.get_children():
			if c0 is SubViewportContainer:
				fx_cont = c0
	check(fx_cont != null and fx_cont.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"N3：全屏层容器 mouse_filter=IGNORE（纯视觉层不拦截顶栏钮，N批等价替换）")
	# M-E 回修2 B（反转留痕）：Target 容器恢复接收事件——滚轮独立缩放生效且夹限幅；
	# 滚轮不产生选区副作用（count 恒 0）
	var tcont: SubViewportContainer = inst.get_node_or_null("TargetView/ViewportContainer") as SubViewportContainer
	var tcam: Camera3D = inst.get_node_or_null("TargetView/ViewportContainer/SubViewport/Camera3D") as Camera3D
	if tcont != null and tcam != null:
		check(tcont.mouse_filter != Control.MOUSE_FILTER_IGNORE,
			"回修2 B：Target 容器恢复接收事件（等价反转 M-E③ IGNORE 断言）")
		var tsize0: float = tcam.size
		var wev := InputEventMouseButton.new()
		wev.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wev.pressed = true
		for i: int in 30:
			tcont.gui_input.emit(wev)
		check(tcam.size > tsize0 and tcam.size <= 100.0,
			"回修2 B：Target 滚轮 30 次独立缩放生效（size %s→%s，夹限幅内）" % [str(tsize0), str(tcam.size)])
		check(is_equal_approx(tcam.position.length(), 20.0),
			"回修2 B：缩放后位姿长度仍固定 20（距离与缩放解耦）")
		check(inst.call("get_side_selected_count") == 0,
			"回修2 B：滚轮无选区副作用（count==0）")
	# 批次V规格§3.2（V-C5）等价替换留痕（原 K4-1 第三处闭环：关卡退出确认弹窗为 GlassDialog
	# 动态实例断言）：退出确认迁移 Game.confirm → TopStrip 统一确认条，动态弹窗节点退役
	#（文案/回调断言归 test_v_confirm_migration.gd；本处锁「节点退役 + 脚本已接线」）。
	check(inst.get_node_or_null("ExitDialog") == null,
		"批次V§3.2：关卡退出确认动态弹窗节点已退役（确认改经统一弹条）")
	var lssrc: String = FileAccess.get_file_as_string("res://scenes/level/level_scene.gd")
	check(lssrc.contains("Game.confirm"), "批次V§3.2：level_scene.gd 退出确认已接线 Game.confirm")
	# P1-1（审查回修）：主视图选区变动须即时刷新聚焦钮（真机可达性——按钮此前主视图路径永久灰态）
	if focus_b != null:
		check(focus_b.disabled, "P1-1：初始无选区聚焦钮 disabled")
		inst.call("select_voxel", Vector3i(0, 0, 0), false)
		check(not focus_b.disabled, "P1-1：主视图 select_voxel 后聚焦钮解禁（真机可点路径）")
		inst.call("clear_selection")
		check(focus_b.disabled, "P1-1：主视图 clear_selection 后聚焦钮恢复 disabled")
		inst.call("select_voxel", Vector3i(0, 0, 0), false)
		inst.call("delete_selected")
		check(focus_b.disabled, "P1-1：delete_selected 清空选区后聚焦钮恢复 disabled")

	inst.queue_free()
	finish()
