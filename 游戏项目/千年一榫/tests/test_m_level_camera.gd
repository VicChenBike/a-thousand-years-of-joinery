extends "res://tests/test_base.gd"
## 批次 M-E 判定用例：关卡 3D 正交等轴测大幅重构（spec §3.5，拍板 #3/#6/#8 + 用户追加追2）。
## TDD 先写（实现前相机/热区/HUD/悬停相关断言 FAIL 属预期红灯）。
## 契约（spec §3.5 目标行为 1~8 / 验收 1~5）：
##   ①正交相机：三视图 Camera3D projection=PROJECTION_ORTHOGONAL、near=0.1/far=100、
##     距离固定 20（根除「透视相机进入包围球→近平面裁切」）；MainView 初始 yaw=45°/
##     pitch=35.264°（真等轴测，参考 m06）；滚轮缩放改 ortho size 语义（×0.9/×1.1），
##     【M-E 回修4 A】限幅=按窗口尺寸与块投影包围盒动态推导（废除固定直径倍数下限）：
##     最大放大档=块投影完整落在窗口内（四周留 ≥8px 边距）→ 任何朝向/任何窗口尺寸不穿帮；
##     初始取景=块投影宽占视口宽目标（主 0.75/侧 0.70）与垂直完整约束取 max（宽扁窗下
##     垂直先撑满=「尽可能放到最大」的正确诠释）；
##   ①b【M-E 回修4 B→N批 等价替换留痕 2026-09-09 → N12-4 再放大 2026-09-10】三窗几何两度：
##     N批 侧窗 440×148@y64/主窗 1060×400@x46,y216 已按 N12-4 用户「侧窗尽可能再放大（中央
##     够大）」再度扩大为：侧窗 520×202@y64（垂直吃掉 4px 间隙+主窗让渡、水平对称向中缝扩）、
##     主窗 1060×346@x46,y270（高度让渡仍占满中带）；三标签改叠加窗口内部左上角（字号 16
##     不放大；N12-3 中央窗「木料」标签删除，两侧保留）；旧避让断言按新口径等价替换（见
##     段 6/段 9/段 11 留痕）；中央块与侧面板块初始视觉尺寸比断言 ≥2.5→≥1.8（N12-4 取代）；
##   ①d【N批 N7 旋转缩放解耦 2026-09-09 用户追加 bug：旋转时木块自己缩小】动态下限与
##     初始取景从「当前朝向投影」改为「任意朝向最坏投影」统一值（正交投影任意朝向 span ≤
##     包围球直径）——旋转全程 ortho size 恒定零跳变（旧「当前朝向投影下限」随 yaw/pitch
##     实时顶大即本 bug 根因，废止）；滚轮缩放自由度保留；
##   ①c【M-E 回修4 C】右键交互分流：按下后位移 >2px=拖拽旋转；原地抬起（无位移）=删除
##     （删除语义完全不变，仅延后到抬起判定）；中键/空白左键拖拽旋转保留。
##   ②热区扩大：三 Panel mouse_filter=IGNORE（子容器照常收事件）；MainView 新增中键
##     任意位置拖拽=旋转（体素上方也可转，抬起不清选区/不拾取）；
##   ③侧面板可交互（回修2 用户反转原「完全不可交互」拍板）：Target/Join 容器恢复接收事件
##     （可选/旋转/缩放）、_on_side_view_gui_input 接线恢复、侧拾取改 _raycast_side_at 射线精确（回修3 D）；
##   ④Ctrl 多选恢复：Ctrl+点击=对命中格 additive 切换（读 ctrl_pressed），与划选并存；
##   ⑤标签：两侧 Title 叠加窗口内部左上角，文案「最终成品（批次 Z Z1 换源 final）/对接固定件」（N12-3 中央窗「木料」
##     标签已删，用户口径直接去掉该文字），字号 16、描边 2、颜色随主题（α 0.82~0.85 柔和）；
##   ⑥提示行精简：底部常驻一行键鼠模板（不含剩余体素/对接引导）；TopBar 新增 VoxelLabel
##     「剩余体素：N / M」随删除/撤销/重做实时刷新；对接引导迁 JoinButton.tooltip_text；
##   ⑦追2 悬停高亮：主视图 motion 命中体素→金色壳 marker 置位（get_hover_cell() 测试钩子），
##     移开复位；与选中绿/锐眼红/幻影绿色系区分，纯视觉层不干扰拾取逻辑。
## 环境注意（spec §六坑 1/6/9）：钉设计视口 1152×648（M-D 先例 container.size）；事件经
## ViewportContainer.gui_input 合成喂入（无头无真实输入管线）；全部属性证据链断言。

const SCENE_PATH := "res://scenes/level/level_scene.tscn"
const W := 1152.0
const H := 648.0
const MISS := Vector3i(-1, -1, -1)

func _mb(btn: int, pressed: bool, pos: Vector2, ctrl := false) -> InputEventMouseButton:
	# 合成鼠标按钮事件（无头无真实输入管线，同 test_level_interaction 先例）
	var ev := InputEventMouseButton.new()
	ev.button_index = btn as MouseButton
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	ev.ctrl_pressed = ctrl
	return ev

func _mm_at(pos: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	return ev

func _fget(obj: Object, prop: String) -> float:
	# 缺失属性返回远离合法域哨兵（断言干净判红不崩）
	var v: Variant = obj.get(prop)
	return float(v) if v != null else 999999.0

func _cnum(inst: Object, prop: String) -> float:
	# 常量读取守卫：属性未实现（红灯期 get 返回 null）时 float(null) 会
	# SCRIPT ERROR 中断 _initialize（spec §六坑 7 同源）——此处判空回哨兵，判红不崩。
	var v: Variant = inst.get(prop)
	return float(v) if v != null else -999999.0

# ---- M-E 回修4 测试侧独立数学（与实现同式双盲互验；口径见各断言） ----
const FIT_MARGIN := 8.0   # 最大放大档四周留边（px，与实现 VIEW_FIT_MARGIN 同值）

## 块 AABB（世界尺寸）在某朝向下的屏幕投影跨度（yaw/pitch 弧度）。
## 水平=x|cos y|+z|sin y|；垂直=(x|sin y|+z|cos y|)|sin p|+y|cos p|。
func _span_at(aabb: Vector3, yaw: float, pitch: float) -> Vector2:
	return Vector2(
		aabb.x * absf(cos(yaw)) + aabb.z * absf(sin(yaw)),
		(aabb.x * absf(sin(yaw)) + aabb.z * absf(cos(yaw))) * absf(sin(pitch)) + aabb.y * absf(cos(pitch)))

## 动态下限（不穿帮）：KEEP_HEIGHT 下 size ≥ span 向双向留边换算的 max。
## 【N批留痕】旧「当前朝向」口径——随 N7 旋转缩放解耦废止，仅留作新旧对照不再消费。
func _smin(span: Vector2, vp: Vector2) -> float:
	return maxf(span.x * vp.y / maxf(vp.x - 2.0 * FIT_MARGIN, 1.0),
		span.y * vp.y / maxf(vp.y - 2.0 * FIT_MARGIN, 1.0))

## 初始取景（双向完整+宽占比目标取 max）。
## 【N批留痕】旧「当前朝向」口径——随 N7 统一取景废止，仅留作新旧对照不再消费。
func _size0_fit(span: Vector2, vp: Vector2, fill_w: float) -> float:
	var by_w := span.x / (fill_w * (vp.x / vp.y))
	return maxf(by_w, span.y * vp.y / maxf(vp.y - 2.0 * FIT_MARGIN, 1.0))

# ---- N批（N7 旋转缩放解耦）测试侧统一口径数学（与实现同式双盲互验） ----
## 统一动态下限：包围球直径 D 作水平/垂直双向保守跨度（正交投影下任意朝向 span ≤ D，
## Cauchy-Schwarz），与 yaw/pitch 无关——旋转全程 ortho size 恒定的数学根据。
func _smin_unif(d: float, vp: Vector2) -> float:
	return maxf(d * vp.y / maxf(vp.x - 2.0 * FIT_MARGIN, 1.0),
		d * vp.y / maxf(vp.y - 2.0 * FIT_MARGIN, 1.0))

## 统一口径初始取景 = max(最坏投影宽占窗宽目标 fill_w，最坏垂直完整约束)。
func _size0_fit_unif(d: float, vp: Vector2, fill_w: float) -> float:
	var by_w := d / (fill_w * (vp.x / vp.y))
	return maxf(by_w, _smin_unif(d, vp))

func _call0(inst: Object, m: String, fail_v: Variant) -> Variant:
	# 无参方法调用守卫：方法未实现（红灯期）call() 会 SCRIPT ERROR 中断——
	# has_method 判空回 fail_v（断言自然判红，不崩不中断）。
	if inst.has_method(m):
		return inst.call(m)
	return fail_v

# ===== 清档纪律（tools/README_走查清档规范.md，批次V回修②B 补齐，test_v_save_domain 同款）=====
# 起测前备份 user:// 真实档案（save.json/first_launch.flag 及可触及的 .tmp/.bak 四件组），
# 终测统一经 finish() 收口还原：先同步 free 测试挂载节点（level._exit_tree 兜底写档等
# 「退出写回」先落测试域磁盘，规范第 6 条），再逐件还原 + SaveManager load_game 重同步内存
# + 逐字节等价断言 + EVID 证据行。备份路径必须带全 user:// 前缀（相对路径在 FileAccess/
# DirAccess 间解析漂移 → 备份链静默失效，test_n10 先例）；每文件独立备份前缀防崩溃残留互踩。
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_r2b_mlc_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _pre_save_text: String = ""   # 起测前真实 save.json 原文（还原等价自检基准）

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _disc_del(p: String) -> void:
	var a: String = _disc_abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _backup_user() -> void:
	# 规范第 1 条：任何删/写档操作之前备份真实档案（有档才备份；还原「有备份才回拷」幂等，
	# 起测前不存在的档案终测后仍不存在——测试自建残留一律清零）
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	# 防退出写回（规范第 6 条）：先同步 free 测试挂载的非 autoload 节点——level._exit_tree
	# 兜底写档（N9）若拖到进程退出树序，会在还原之后把测试态写回真实档案；提前 free 令
	# 兜底写档落测试域磁盘，紧随其后的逐件还原即将其覆盖。
	for c: Node in root.get_children():
		if not DISC_AUTOLOADS.has(String(c.name)):
			c.free()
	# 规范第 2 条：逐件还原 + load_game 重同步内存（防后续 save_game 把测试态写回真实档案）
	for p: String in DISC_WATCHED:
		_disc_del(p)
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(_disc_abs(bk))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()
	# 纪律自检：还原后 save.json 与起测前逐字节等价（起测前无档 ↔ 还原后无档）
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|mlc|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_m_level_camera ==")
	_backup_user()
	# N批等价替换（N9，2026-09-09）：本测试断言「初始未挖」基准（180/180、undo=0；批次 Z 实况回填），而 N9 起进关
	# 会按存档挖除断点重放（spec §6.11）——前序测试文件遗留的 user://save.json 断点会改变初始
	# 剩余数（跨进程污染实证：test_level_scene 遗留 1 格断点 → 本测试 179/180 误报）。
	# 故对齐 test_level_flow 先例，起手清存档文件并重同步内存；断言本体零改动（165 checks 不变）。
	for p: String in ["user://save.json", "user://first_launch.flag"]:
		var n9_abs: String = ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(n9_abs):
			DirAccess.remove_absolute(n9_abs)
	var n9_sm: Node = get_root().get_node_or_null("SaveManager")
	if n9_sm != null:
		n9_sm.call("load_game")
	check(ResourceLoader.exists(SCENE_PATH), "level_scene.tscn 存在")
	var packed: PackedScene = load(SCENE_PATH) if ResourceLoader.exists(SCENE_PATH) else null
	var inst: Node = (packed as PackedScene).instantiate() if packed != null else null
	check(inst != null, "关卡场景可实例化")
	if inst == null:
		finish()
		return
	inst.call("set_context", {"chapter": 1})
	# 钉设计视口（spec §六坑 1：headless expand 会把 FULL_RECT 容器撑 1152×1152）
	var container: Control = Control.new()
	container.size = Vector2(W, H)
	add_child(container)
	container.add_child(inst)
	await process_frame
	await process_frame

	var main_vp: SubViewport = inst.get_node_or_null("MainView/ViewportContainer/SubViewport")
	var main_cam: Camera3D = inst.get_node_or_null("MainView/ViewportContainer/SubViewport/Camera3D")
	var tgt_cam: Camera3D = inst.get_node_or_null("TargetView/ViewportContainer/SubViewport/Camera3D")
	var join_cam: Camera3D = inst.get_node_or_null("JoinView/ViewportContainer/SubViewport/Camera3D")
	check(main_vp is SubViewport and main_cam is Camera3D, "MainView 含视口与相机")
	check(tgt_cam is Camera3D and join_cam is Camera3D, "Target/Join 视口含相机")
	if main_cam == null or tgt_cam == null or join_cam == null:
		finish()
		return

	# ==================== 段 1：正交等轴测相机参数（spec 验收 1） ====================
	# 1a. 三相机投影=正交（M-E 核心拍板 #6）
	for pair: Array in [["MainView", main_cam], ["TargetView", tgt_cam], ["JoinView", join_cam]]:
		check(int(pair[1].projection) == int(Camera3D.PROJECTION_ORTHOGONAL),
			"M-E①：%s 相机 projection==PROJECTION_ORTHOGONAL（等轴测风）" % pair[0])
	# 1b. 近/远平面定值（包围球恒在锥内，裁切根除）
	for pair2: Array in [["MainView", main_cam], ["TargetView", tgt_cam], ["JoinView", join_cam]]:
		check(absf(pair2[1].near - 0.1) < 0.001, "M-E①：%s 相机 near=0.1" % pair2[0])
		check(absf(pair2[1].far - 100.0) < 0.001, "M-E①：%s 相机 far=100" % pair2[0])
	# 1c. 距离固定 20（三视图统一；原 Main 6<包围球半径 9 系裁切根因）
	for pair3: Array in [["MainView", main_cam], ["TargetView", tgt_cam], ["JoinView", join_cam]]:
		check(absf(pair3[1].position.length() - 20.0) < 0.01,
			"M-E①：%s 相机距离固定 20（position 长度）" % pair3[0])
	# 1d. MainView 初始 yaw=45°/pitch=35.264°（真等轴测；原 -35/22 奇葩角）
	check(absf(rad_to_deg(_fget(inst, "_orbit_yaw")) - 45.0) < 0.05, "M-E①：初始 yaw=45°（真等轴测）")
	check(absf(rad_to_deg(_fget(inst, "_orbit_pitch")) - 35.264) < 0.05,
		"M-E①：初始 pitch≈35.264°（atan 1/√2）")
	check(absf(_cnum(inst, "SIDE_YAW0_DEG") - 45.0) < 0.001, "M-E①：侧视图初始 yaw=45°（三视图统一）")
	check(absf(_cnum(inst, "SIDE_PITCH0_DEG") - 35.264) < 0.01, "M-E①：侧视图初始 pitch≈35.264°")
	# 1e. ortho size：>0 且按「窗口尺寸×块投影包围盒」适配（回修4 A：初始取景=宽占比目标
	#     与垂直完整约束取 max；废除固定直径倍数口径）
	for pair4: Array in [["MainView", main_cam], ["TargetView", tgt_cam], ["JoinView", join_cam]]:
		check(pair4[1].size > 0.0, "M-E①：%s 相机 ortho size>0（按窗口适配设定）" % pair4[0])
	var d_main := Vector3(inst.get("_voxel_size")).length()  # 12×3×5 → 对角线≈13.34（上限基准仍用；批次 Z 实况回填）
	var aabb_main: Vector3 = inst.get("_view_aabb_size")["Main"] if inst.get("_view_aabb_size") is Dictionary else Vector3.ZERO
	var aabb_tgt: Vector3 = inst.get("_view_aabb_size")["Target"] if inst.get("_view_aabb_size") is Dictionary else Vector3.ZERO
	var vp_m := Vector2(main_vp.size) if main_vp != null else Vector2.ZERO
	var tgt_vp_e: SubViewport = inst.get_node_or_null("TargetView/ViewportContainer/SubViewport")
	var vp_t := Vector2(tgt_vp_e.size) if tgt_vp_e != null else Vector2.ZERO
	check(aabb_main.x > 0.0 and aabb_tgt.x > 0.0, "回修4 A：_view_aabb_size 三视图 AABB 尺寸缓存就绪")
	check(vp_m.x > 1.0 and vp_t.x > 1.0, "回修4 A：视口已布局（像素尺寸有效，deferred 取景生效）")
	if aabb_main.x > 0.0 and aabb_tgt.x > 0.0 and vp_m.x > 1.0:
		# N批 旋转缩放解耦 等价替换留痕：初始取景从「当前朝向适配」（旧 _size0_fit）改为
		# 「任意朝向最坏投影（包围球直径）统一口径」——旋转全程 size 恒定；初始视野略保守，
		# N2 窗口极致扩大已补偿放大体验。
		var s0m := _size0_fit_unif(aabb_main.length(), vp_m, 0.75)
		check(absf(main_cam.size - s0m) < 0.05,
			"N7：Main 初始 size=任意朝向统一适配值（期望 %.3f，实际 %.3f）" % [s0m, main_cam.size])
		var s0t := _size0_fit_unif(aabb_tgt.length(), vp_t, 0.70)
		check(absf(tgt_cam.size - s0t) < 0.05,
			"N7：Target 初始 size=任意朝向统一适配值（期望 %.3f，实际 %.3f）" % [s0t, tgt_cam.size])
	var side_sizes: Dictionary = inst.get("_ortho_size_side") if inst.get("_ortho_size_side") is Dictionary else {}
	check(tgt_cam is Camera3D and absf(tgt_cam.size - float(side_sizes.get("Target", -1.0))) < 0.001,
		"M-E①：Target 相机 size 与 _ortho_size_side 同步")
	check(absf(join_cam.size - float(side_sizes.get("Join", -1.0))) < 0.001,
		"M-E①：Join 相机 size 与 _ortho_size_side 同步")
	check(absf(_cnum(inst, "MAIN_FILL_W0") - 0.75) < 0.001, "回修4 A：MAIN_FILL_W0=0.75（主初始块投影宽占视口宽目标）")
	check(absf(_cnum(inst, "SIDE_FILL_W0") - 0.70) < 0.001, "回修4 A：SIDE_FILL_W0=0.70（侧初始宽占比目标）")
	check(absf(_cnum(inst, "VIEW_FIT_MARGIN") - 8.0) < 0.001, "回修4 A：VIEW_FIT_MARGIN=8（最大档四周留边 px）")
	check(inst.has_method("_ortho_size_min_for"), "回修4 A：动态下限函数 _ortho_size_min_for 存在（废除固定直径倍数）")
	check(absf(_cnum(inst, "ORTHO_SIZE_MAX_MUL") - 4.0) < 0.001, "M-E①：ORTHO_SIZE_MAX_MUL=4.0（直径倍数上限保留）")

	# ==================== 段 2：热区扩大（spec 目标行为 2） ====================
	for pn: String in ["TargetView", "JoinView", "MainView"]:
		var pnl: Control = inst.get_node_or_null(pn) as Control
		check(pnl != null and pnl.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"M-E②：%s Panel mouse_filter=IGNORE（吞点击根除）" % pn)
	var tcont: SubViewportContainer = inst.get_node_or_null("TargetView/ViewportContainer") as SubViewportContainer
	var jcont: SubViewportContainer = inst.get_node_or_null("JoinView/ViewportContainer") as SubViewportContainer
	var mcont: SubViewportContainer = inst.get_node_or_null("MainView/ViewportContainer") as SubViewportContainer
	# 【回修2 B 反转留痕】用户实测推翻 M-E-3「侧面板完全不可交互」拍板——容器恢复接收事件
	check(tcont != null and tcont.mouse_filter != Control.MOUSE_FILTER_IGNORE,
		"回修2 B：Target 容器恢复接收事件（可选/可旋转/可缩放）")
	check(jcont != null and jcont.mouse_filter != Control.MOUSE_FILTER_IGNORE,
		"回修2 B：Join 容器恢复接收事件")
	check(mcont != null and mcont.mouse_filter != Control.MOUSE_FILTER_IGNORE,
		"M-E②：Main 容器仍收事件（划选/旋转主战场）")

	# ==================== 段 3：侧面板交互恢复（回修2 B，反转留痕「用户实测推翻完全不可交互拍板」） ====================
	check(not inst.has_method("_side_pick_nearest"), "回修3 D：48px 就近拾取路径物理删除（小视口吞旋转根因）")
	check(inst.has_method("_raycast_side_at"), "回修3 D：侧分流/划选改射线精确拾取")
	check(inst.has_method("_on_side_view_gui_input"), "回修2 B：_on_side_view_gui_input 接线恢复")
	check(inst.has_method("get_side_selected_count"), "回修2 B：get_side_selected_count() 钩子存在（语义=真实计数）")
	var tgt_cam_size0: float = tgt_cam.size if tgt_cam != null else -1.0
	# 3a. 滚轮独立缩放：Target 容器滚轮 → size 变化且位姿长度仍=ORTHO_DIST（正交位姿不破）
	if tcont != null and tgt_cam != null:
		tcont.gui_input.emit(_mb(MOUSE_BUTTON_WHEEL_DOWN, true, Vector2(40, 40)))
		await process_frame
		check(tgt_cam.size > tgt_cam_size0 + 0.001,
			"回修2 B：Target 滚轮独立缩放生效（size %s→%s）" % [str(tgt_cam_size0), str(tgt_cam.size)])
		check(absf(tgt_cam.position.length() - 20.0) < 0.01,
			"回修2 B：缩放后位姿长度仍固定 20（距离与缩放解耦）")
	# 3b. 划选 → 选区置位 → 空白单击清空（误触防护出口）+ 聚焦钮消费侧选区
	var focus_b3: Button = inst.get_node_or_null("TopBar/Buttons/FocusButton") as Button
	if tcont != null:
		var tgt_vp: SubViewport = inst.get_node_or_null("TargetView/ViewportContainer/SubViewport")
		var tgt_cam2: Camera3D = inst.get_node_or_null("TargetView/ViewportContainer/SubViewport/Camera3D")
		if tgt_vp != null and tgt_cam2 != null and tgt_vp.size.x > 1:
			var c_t := Vector2(tgt_vp.size.x * 0.5, tgt_vp.size.y * 0.5)
			# 批次 Z Z1 等价改写：Target 视图域尺寸=_view_sizes["Target"]（final_answer.size，
			# 与 _raycast_side_at 同源消费）——旧传 _voxel_size（blocks 域）在新数据 blocks/final
			# 异尺寸（12×3×5 vs 12×7×8）下按 blocks 域过滤格，致测试命中格与点光跟格错位
			# （旧数据三域同尺寸 8×3×8 时两参数等价，掩盖该耦合）。
			var vsz_v: Variant = inst.get("_view_sizes")
			var tdom: Variant = (vsz_v as Dictionary).get("Target", inst.get("_voxel_size")) \
				if vsz_v is Dictionary else inst.get("_voxel_size")
			var hit_t: Vector3i = inst.call("ray_to_cell",
				tgt_cam2.project_ray_origin(c_t), tgt_cam2.project_ray_normal(c_t),
				inst.call("_cells_dict", inst.get("_view_cells")["Target"]),
				tdom, inst.get("_view_centers")["Target"])
			check(hit_t != MISS, "回修2 B 前置：Target 视口中心射线命中目标块（拾取几何=渲染几何）")
			if hit_t != MISS:
				tcont.gui_input.emit(_mm_at(c_t))  # 无按键 motion → 悬停点光跟随（追2 D）
				await process_frame
				var tlight2: OmniLight3D = (inst.get("_hover_lights") as Dictionary).get("Target") as OmniLight3D
				var t_center: Vector3 = Vector3(hit_t) + Vector3(0.5, 0.5, 0.5) - (inst.get("_view_centers")["Target"] as Vector3)
				check(tlight2 is OmniLight3D and tlight2.visible
					and tlight2.position.distance_to(t_center) <= 2.0,
					"回修2 D：Target 悬停点光跟随命中格（距格心 ≤2.0，含抬高偏移）")
				tcont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, true, c_t))
				tcont.gui_input.emit(_mm_at(c_t))  # motion 中就近拾取追加（起点已选中，幂等）
				tcont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, c_t))
				await process_frame
				var cnt1: int = int(inst.call("get_side_selected_count"))
				check(cnt1 >= 1, "回修2 B：Target 划选后选区计数 ≥1（真实选区，实际 %d）" % cnt1)
				check(focus_b3 != null and not focus_b3.disabled,
					"回修2 B：侧选区使聚焦钮解禁（_update_focus_btn 消费恢复）")
				# 空白单击=清空该侧选区
				tcont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, true, Vector2(6, 6)))
				tcont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, Vector2(6, 6)))
				await process_frame
				check(int(inst.call("get_side_selected_count")) == 0,
					"回修2 B：单击空白清空该侧选区（误触防护出口可用）")
				check(focus_b3 != null and focus_b3.disabled,
					"回修2 B：清空后聚焦钮回灰（消费面联动）")
				inst.call("clear_selection")  # 清主视图可能残留（4 段前置环境干净）
	# 3c. 侧视图旋转：空白左键拖拽 → 侧 yaw 变化（独立轨道角）
	if tcont != null:
		var yaw_t0: float = float((inst.get("_side_yaw") as Dictionary)["Target"])
		tcont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, true, Vector2(8, 8)))
		tcont.gui_input.emit(_mm_at(Vector2(8, 8) + Vector2(30, 0)))
		tcont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, Vector2(8, 8) + Vector2(30, 0)))
		var yaw_t1: float = float((inst.get("_side_yaw") as Dictionary)["Target"])
		check(absf(yaw_t1 - yaw_t0) > 0.001, "回修2 B：Target 空白拖拽旋转（独立轨道角生效）")
		inst.call("_update_side_camera", "Target")  # 复位位姿（yaw 保持，position 恢复 20 口径）

	# ==================== 段 4：Ctrl 多选恢复 + 中键拖拽旋转（spec 目标行为 2/4） ====================
	if mcont != null and main_vp != null and main_vp.size.x > 1:
		var center := Vector2(main_vp.size.x * 0.5, main_vp.size.y * 0.5)
		var hit_c: Vector3i = inst.call("get_cell_hit",
			main_cam.project_ray_origin(center), main_cam.project_ray_normal(center))
		check(hit_c != MISS, "M-E④ 前置：视口中心射线命中木料（正交取景块居中）")
		if hit_c != MISS:
			# 4a. Ctrl+点击=命中格 additive 切换
			mcont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, true, center, true))
			mcont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, center, true))
			var sel: Array = inst.call("get_selected_voxels")
			check(sel.size() == 1 and sel.has(hit_c), "M-E④：Ctrl+点击命中格后选区含该格（additive 切换）")
			mcont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, true, center, true))
			mcont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, center, true))
			check((inst.call("get_selected_voxels") as Array).is_empty(),
				"M-E④：再次 Ctrl+点击同格=切换取消（选区清空）")
			# 4b. 无 Ctrl 普通单击=单选替换（划选状态机不回归）
			mcont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, true, center))
			mcont.gui_input.emit(_mb(MOUSE_BUTTON_LEFT, false, center))
			check((inst.call("get_selected_voxels") as Array).size() == 1,
				"M-E④：无 Ctrl 单击=单选替换（原语义保留）")
			# 4c. 中键任意位置拖拽=旋转（体素上方也可转；抬起不清选区/不拾取）
			var yaw_b: float = _fget(inst, "_orbit_yaw")
			mcont.gui_input.emit(_mb(MOUSE_BUTTON_MIDDLE, true, center))
			mcont.gui_input.emit(_mm_at(center + Vector2(40, 0)))
			mcont.gui_input.emit(_mb(MOUSE_BUTTON_MIDDLE, false, center + Vector2(40, 0)))
			check(absf(_fget(inst, "_orbit_yaw") - yaw_b) > 0.001,
				"M-E②：中键体素上方拖拽改 _orbit_yaw（旋转生效）")
			var sel_mid: Array = inst.call("get_selected_voxels")
			check(sel_mid.size() == 1 and sel_mid.has(hit_c),
				"M-E②：中键拖拽抬起不清选区/不拾取（划选逻辑不干扰）")
			inst.call("clear_selection")
			# 4d. 中键空白拖拽同样旋转（任意位置语义；横向位移驱动 yaw）
			var yaw_b2: float = _fget(inst, "_orbit_yaw")
			mcont.gui_input.emit(_mb(MOUSE_BUTTON_MIDDLE, true, Vector2(8, 8)))
			mcont.gui_input.emit(_mm_at(Vector2(8, 8) + Vector2(30, 0)))
			mcont.gui_input.emit(_mb(MOUSE_BUTTON_MIDDLE, false, Vector2(8, 8) + Vector2(30, 0)))
			check(not is_equal_approx(_fget(inst, "_orbit_yaw"), yaw_b2),
				"M-E②：中键空白处拖拽亦旋转（任意位置热区）")

	# ==================== 段 5：滚轮缩放 size 语义（spec 目标行为 1 + 回修4 A 动态限幅） ====================
	if mcont != null:
		var size0: float = main_cam.size
		mcont.gui_input.emit(_mb(MOUSE_BUTTON_WHEEL_UP, true, Vector2(10, 10)))
		check(main_cam.size <= size0 + 0.0001 and main_cam.size > 0.0,
			"M-E①：滚轮上→ortho size 不放大（×0.9；初始档=统一动态下限极限档，N批口径）")
		for i: int in 40:
			mcont.gui_input.emit(_mb(MOUSE_BUTTON_WHEEL_DOWN, true, Vector2(10, 10)))
		var sz_max := d_main * 4.0
		check(absf(_fget(inst, "_ortho_size_main") - sz_max) < 0.01,
			"M-E①：滚轮放大越界夹在直径×4.0（%.2f）" % sz_max)
		check(absf(main_cam.size - _fget(inst, "_ortho_size_main")) < 0.001,
			"M-E①：滚轮后相机 size 与状态变量同步（_update_main_camera 生效）")
		# 【N批 旋转缩放解耦 等价替换留痕】旧回修4 A 断言「滚轮到底=当前朝向动态下限 +
		# 正视朝向下限更小可再放大」废止——正是「下限随朝向实时顶大」机制造成用户反馈的
		# 「旋转时木块自己缩小」bug。新口径：下限=任意朝向统一值（包围球直径），滚轮到底后
		# 任意旋转 size 恒定、朝向变化不产生新的放大自由度。
		for i2: int in 60:
			mcont.gui_input.emit(_mb(MOUSE_BUTTON_WHEEL_UP, true, Vector2(10, 10)))
		var smin_u := _smin_unif(aabb_main.length(), vp_m)
		check(absf(_fget(inst, "_ortho_size_main") - smin_u) < 0.01,
			"N7：滚轮放大到底=任意朝向统一动态下限（期望 %.3f，实际 %.3f；包围球口径）"
			% [smin_u, _fget(inst, "_ortho_size_main")])
		var sz_at_min: float = _fget(inst, "_ortho_size_main")
		inst.set("_orbit_yaw", 0.0)
		inst.set("_orbit_pitch", 0.0)
		inst.call("_update_main_camera")
		check(absf(_fget(inst, "_ortho_size_main") - sz_at_min) < 0.001,
			"N7：转至正视朝向后取景恒定（旋转缩放解耦，不再被当前朝向下限顶大）")
		for i5: int in 40:
			mcont.gui_input.emit(_mb(MOUSE_BUTTON_WHEEL_UP, true, Vector2(10, 10)))
		check(absf(_fget(inst, "_ortho_size_main") - sz_at_min) < 0.001,
			"N7：正视朝向滚轮上仍钳在同一统一下限（不存在更小的朝向专用下限）")
		# 复位初始朝向与初始取景（后续段环境干净）
		inst.set("_orbit_yaw", deg_to_rad(45.0))
		inst.set("_orbit_pitch", deg_to_rad(35.264))
		inst.call("_update_main_camera")

	# ==================== 段 6：HUD（顶栏计数 / 提示行精简 / 标签下移，spec 验收 3） ====================
	var voxel_lbl: Label = inst.get_node_or_null("TopBar/VoxelLabel")
	check(voxel_lbl is Label, "M-E⑥：TopBar/VoxelLabel 存在（剩余体素计数挪顶栏）")
	# M-Hb 走查回修（2026-09-08）→ U-D（c63260a）等价替换留痕：TitleLabel/VoxelLabel
	# clip_text=true 由 tscn 移除——TitleLabel 改 text_overrun_behavior=3（省略号截断，
	# 语义等价升级）；VoxelLabel 计数文本长度有界，改 stretch_ratio=1.0 弹性伸缩承接压缩。
	var title_lbl: Label = inst.get_node_or_null("TopBar/TitleLabel") as Label
	check(title_lbl != null and title_lbl.text_overrun_behavior == 3,
		"M-Hb：TopBar/TitleLabel text_overrun_behavior=3（省略号截断，U-D 等价替换 clip_text）")
	check(voxel_lbl != null and voxel_lbl.size_flags_stretch_ratio == 1.0,
		"M-Hb：TopBar/VoxelLabel stretch_ratio=1.0 弹性伸缩（U-D 等价替换 clip_text，计数可压缩）")
	if voxel_lbl != null:
		# P1-1（2026-09-08 终审回修）：NG-Hb-1 只给 clip 不给 expand → VoxelLabel 最小宽塌缩
		# 至 1px，被 TitleLabel expand 独占的剩余空间压瘪（W7_level_topbar_zoom 四图实证顶栏
		# 无「剩余体素」）——回修：VoxelLabel expand 平分 + TopBar 右端 -264→-132 扩容。
		var vrect: Rect2 = (voxel_lbl as Control).get_global_rect()
		var vw: float = voxel_lbl.get_theme_font("font").get_string_size(
			voxel_lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, voxel_lbl.get_theme_font_size("font_size")).x
		check(vrect.size.x >= 120.0,
			"P1-1：VoxelLabel 全局 rect 宽 ≥120px（实际 %.1fpx；≈1px 即 NG-Hb-1 回归）" % vrect.size.x)
		check(vrect.size.x >= vw - 0.5,
			"P1-1：VoxelLabel 完整不截断（rect %.1f ≥ 文本宽 %.1f）" % [vrect.size.x, vw])
		check(voxel_lbl.visible and voxel_lbl.modulate.a > 0.0,
			"P1-1：VoxelLabel 可见（visible 且 modulate α>0）")
		check(vrect.position.y >= 0.0 and vrect.end.y <= H,
			"P1-1：VoxelLabel 位于设计视口内（y %.1f..%.1f）" % [vrect.position.y, vrect.end.y])
		if title_lbl != null:
			var trect: Rect2 = title_lbl.get_global_rect()
			var tw: float = title_lbl.get_theme_font("font").get_string_size(
				title_lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, title_lbl.get_theme_font_size("font_size")).x
			check(trect.size.x >= tw - 0.5,
				"P1-1：TitleLabel 完整不截断（rect %.1f ≥ 文本宽 %.1f；防修复挤压标题）" % [trect.size.x, tw])
			# P1-1 配套：顶栏标签字号钉 16（场景 override）——主题默认 20 时 Title≈217+Voxel≈187
			# 平分空间必截断（v2 首拍实证），16px 下 174+150 可完整容纳（HintLabel 18 同款 override 口径）
			check(title_lbl.get_theme_font_size("font_size") == 16,
				"P1-1：TitleLabel 字号 16（场景 override，防主题默认漂移再压爆顶栏）")
		check(voxel_lbl.get_theme_font_size("font_size") == 16,
			"P1-1：VoxelLabel 字号 16（场景 override，同上）")
		check(voxel_lbl.text.contains("180 / 180"), "M-E⑥：初始计数文本=180 / 180（实际「%s」）" % voxel_lbl.text)
		inst.call("select_voxel", Vector3i(0, 0, 0), false)
		inst.call("select_voxel", Vector3i(1, 0, 0), true)
		inst.call("select_voxel", Vector3i(0, 1, 0), true)
		inst.call("delete_selected")
		check(voxel_lbl.text.contains("177 / 180"), "M-E⑥：删除 3 格后顶栏计数同步 177 / 180（批次 Z 实况等价改写）")
		inst.call("undo")
		check(voxel_lbl.text.contains("180 / 180"), "M-E⑥：撤销后顶栏计数恢复 180 / 180")
		inst.call("select_voxel", Vector3i(0, 0, 0), false)
		inst.call("select_voxel", Vector3i(1, 0, 0), true)
		inst.call("delete_selected")  # 删 2 格（留 178，供提示行断言环境干净；批次 Z 实况回填）
		inst.call("undo")
	var hint: Label = inst.get_node_or_null("HintLabel")
	check(hint is Label, "提示行 Label 存在")
	if hint != null:
		# 回修4：文案等价替换留痕——「右键删除→右键点删除」「撤销重做→撤/重做」
		# 「空白/中键拖拽旋转+单击空白取消选中→右键/中键/空白拖=旋转+点空白取消选中」
		# （全句精简适配主题字体 18px 单行 ≤ 容器宽，走查量宽定稿）
		# 2026-09-11 用户文案修订：「撤/重做→撤/取消撤回」（仅界面文案，undo/redo 逻辑不变）
		check(hint.text.contains("左键划选") and hint.text.contains("Ctrl+点击多选")
			and hint.text.contains("右键点删除") and hint.text.contains("Ctrl+Z/Y 撤/取消撤回")
			and hint.text.contains("中键/空白拖=旋转") and hint.text.contains("滚轮缩放")
			and hint.text.contains("点空白取消选中"),
			"M-E⑥+回修4：提示行=精简模板七段（含右键点删除/点空白取消选中语义）")
		check(hint.text.contains("右键") and hint.text.contains("拖=旋转"),
			"回修4 C：提示行含右键拖拽旋转口径（原地点击=删除语义不变）")
		check(hint.get_theme_font_size("font_size") == 18,
			"回修4：提示行字号 18（主题默认 20 贴满，18px 单行实测 947 ≤ 1013）")
		check(not hint.text.contains("剩余体素") and not hint.text.contains("挖出与"),
			"M-E⑥：提示行不再承载计数与对接引导句")
		check(not hint.text.contains("按住左键划动 选中体素"), "M-E⑥：旧超长话术已替换（等价留痕）")
		var fnt: Font = hint.get_theme_font("font")
		var fsz: int = hint.get_theme_font_size("font_size")
		var text_w: float = fnt.get_string_size(hint.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fsz).x
		check(text_w <= W and text_w <= hint.size.x,
			"M-E⑥：提示行单行放得下（文本宽 %.0f ≤ 提示区宽 %.0f ≤ 视口宽 %.0f）" % [text_w, hint.size.x, W])
	var join_btn: Button = inst.get_node_or_null("TopBar/Buttons/JoinButton")
	# U-D（c63260a）等价替换留痕：原生 tooltip 移除（防与 HoverTip 双提示），文案由
	# HoverTip 组件逐字承接（level_scene U7-3 接入段「对接：按标准答案判定对接」——批次 Z
	# 终审 P2 等价替换：旧「对照成品」→「按标准答案判定对接」，判定基准=target）。
	var lvl_src_tip: String = FileAccess.get_file_as_string("res://scenes/level/level_scene.gd")
	check(join_btn != null and String(join_btn.tooltip_text).is_empty()
		and lvl_src_tip.contains("hover_tip.gd") and lvl_src_tip.contains("对接：按标准答案判定对接"),
		"M-E⑥：对接引导句由 HoverTip 承载（U-D 原生 tooltip 已移除防双提示，等价替换；批次Z终审P2标准答案口径）")
	# 标签下移：文案/字号/描边/位置（视口容器正下方 + 水平中轴对齐）
	var title_expect := {"TargetView": "最终成品", "JoinView": "对接固定件"}  # 批次 Z Z1：左上「对照成品」→「最终成品」（等价替换留痕）
	for tn: String in ["TargetView", "JoinView"]:
		var ttl: Label = inst.get_node_or_null(tn + "/Title") as Label
		var vc: Control = inst.get_node_or_null(tn + "/ViewportContainer") as Control
		check(ttl is Label and vc is Control, "M-E⑤：%s/Title 与视口容器存在" % tn)
		if ttl == null or vc == null:
			continue
		check_eq(String(ttl.text), String(title_expect[tn]), "M-E⑤：%s 标签文案精简「%s」" % [tn, title_expect[tn]])
		check(ttl.get_theme_font_size("font_size") == 16, "M-E⑤：%s 标签字号 16（原 20 收敛）" % tn)
		check(int(ttl.get_theme_constant("outline_size")) == 2, "M-E⑤：%s 标签描边 2（原 4 收敛）" % tn)
		var fc: Color = ttl.get_theme_color("font_color")
		check(fc.a >= 0.80 and fc.a <= 0.86, "M-E⑤：%s 标签字色柔和（α 0.82~0.85 档）" % tn)
		var tr := ttl.get_global_rect()
		var vr := vc.get_global_rect()
		# N批 等价替换留痕：旧「标签位于视口容器正下方/水平中轴对齐」随 N2「文字让位」废止——
		# 标签改叠加窗口内部左上角：完全落在视口容器矩形内、节点序在容器之后（绘制于 3D
		# 内容之上）、字号 16 不放大；不遮挡体素主体判读由角落放置+走查核定。
		check(tr.position.x >= vr.position.x - 0.5 and tr.position.y >= vr.position.y - 0.5
			and tr.end.x <= vr.end.x + 0.5 and tr.end.y <= vr.end.y + 0.5,
			"N2：%s 标签叠加窗口内部（完全落在视口容器矩形内）" % tn)
		check(tr.position.x <= vr.position.x + 16.0 and tr.position.y <= vr.position.y + 12.0,
			"N2：%s 标签位于窗内左上角（距容器左上角偏移 ≤16/12px，实际 %s）" % [tn, str(tr.position - vr.position)])
		check(ttl.get_index() > vc.get_index(),
			"N2：%s 标签节点序在视口容器之后（叠加绘制于 3D 内容之上）" % tn)
	# N12-3（用户 2026-09-10 口径「直接去掉那个文字」）等价替换留痕：中央窗 MainView/Title
	# 「木料」标签删除（左上「最终成品」——批次 Z Z1 由「对照成品」换源改题/右上「对接固定件」保留）；M-E⑤ 三标签
	# 断言按新口径收缩为两侧标签+中央标签不存在（相关断言等价替换）。
	check(inst.get_node_or_null("MainView/Title") == null,
		"N12-3：MainView/Title「木料」标签已删除（节点不存在；Target/Join 标签保留）")

	# ==================== 段 7：追2 悬停「手电筒照木头」点光（spec 目标行为 8 / 验收 5） ====================
	# 【用户澄清 2026-09-08】追2=手电筒点光：鼠标悬停处木纹提亮+凹缝浮雕感、光影随 3D 形状
	# 变化；**金色壳方案废弃**（原 marker/mesh 断言删除留痕）。OmniLight3D 暖金点光跟随悬停
	# 命中点（沿视线反方向抬高防贴面死黑），移开/无命中能量趋 0（渐入渐出）；体素木纹材质
	# 本就受光（StandardMaterial3D 默认 PER_PIXEL，roughness 0.55）→ 零材质改动最小侵入。
	check(inst.has_method("get_hover_cell"), "追2：get_hover_cell() 测试钩子存在")
	check(inst.has_method("_tick_hover_light"), "追2：点光能量渐变推进钩子存在（输入驱动路径纪律）")
	var marker_gone: Variant = inst.get("_hover_marker")
	check(marker_gone == null, "追2 留痕：金色壳方案已废弃（_hover_marker 不复存在）")
	if mcont != null and main_vp.size.x > 1 and inst.has_method("get_hover_cell"):
		var center2 := Vector2(main_vp.size.x * 0.5, main_vp.size.y * 0.5)
		var hit2: Vector3i = inst.call("get_cell_hit",
			main_cam.project_ray_origin(center2), main_cam.project_ray_normal(center2))
		var hlight: OmniLight3D = inst.get("_hover_lights")["Main"] as OmniLight3D if inst.get("_hover_lights") is Dictionary else null
		check(hlight is OmniLight3D, "追2/回修2 D：Main 悬停点光 OmniLight3D 存在（三视图 dict）")
		var tlight: OmniLight3D = inst.get("_hover_lights")["Target"] as OmniLight3D if inst.get("_hover_lights") is Dictionary else null
		check(tlight is OmniLight3D, "回修2 D：Target 悬停点光存在（三视图覆盖）")
		if hlight != null:
			check(hlight.light_color.r > 0.85 and hlight.light_color.g > 0.6 and hlight.light_color.g < 0.95
				and hlight.light_color.b < 0.75,
				"追2：点光为暖金色（照木头色温，实际 %s）" % str(hlight.light_color))
			check(hlight.omni_range >= 2.0 and hlight.omni_range <= 4.0,
				"追2：点光范围≈2~4 格（omni_range=%.1f）" % hlight.omni_range)
			check(hlight.shadow_enabled, "追2：点光开阴影（凹缝投影浮雕感来源之一）")
		if hit2 != MISS and hlight != null:
			mcont.gui_input.emit(_mm_at(center2))
			check(_call0(inst, "get_hover_cell", Vector3i(-9, -9, -9)) == hit2, "追2：合成悬停 motion → 悬停格置位（跟随拾取）")
			# 光位置跟随命中点：光心与命中格中心距离 ≤ 抬高偏移+半格容差（2.0）
			var cell_center: Vector3 = Vector3(hit2) + Vector3(0.5, 0.5, 0.5) - (inst.get("_voxel_center") as Vector3)
			check(hlight.position.distance_to(cell_center) <= 2.0,
				"追2：光位置跟随命中格（距格心 %.2f ≤ 2.0，含法线抬高偏移）" % hlight.position.distance_to(cell_center))
			check(hlight.visible, "追2：命中后点光可见（能量渐入中或已亮）")
			inst.call("_tick_hover_light", 1.0)  # 推进一拍大 delta → 能量到目标位
			check(hlight.light_energy > 1.0, "追2：能量渐入到位（>1.0，实际 %.2f）" % hlight.light_energy)
			var sel_before_hover: Array = inst.call("get_selected_voxels")
			mcont.gui_input.emit(_mm_at(Vector2(8, 8)))  # 移开到空白
			check(_call0(inst, "get_hover_cell", Vector3i(-9, -9, -9)) == MISS, "追2：移开空白 → 悬停格复位 NO_CELL")
			inst.call("_tick_hover_light", 1.0)
			inst.call("_tick_hover_light", 1.0)
			check(hlight.light_energy < 0.01, "追2：移开后能量趋 0（渐灭，实际 %.3f）" % hlight.light_energy)
			check(not hlight.visible, "追2：能量耗尽后点光隐藏（场景观感与无悬停一致）")
			var sel_after_hover: Array = inst.call("get_selected_voxels")
			check(sel_before_hover.size() == sel_after_hover.size(),
				"追2：悬停纯视觉层不改变选区（拾取逻辑零干扰）")

	# ==================== 段 8：回修3 B 取景居中 + E FailToast 顶部中央 ====================
	# B：轨道相机 look_at(块中心)+正交 size 只改视野不改中心 → 任意缩放档位块中心投影恒=视口中心
	#（用户截图「上下裁左右空」系宽扁 aspect 自然裁切，非偏移；对称性由此数学保证）
	if mcont != null and main_vp.size.x > 1 and main_cam is Camera3D:
		var vp_center := Vector2(main_vp.size.x * 0.5, main_vp.size.y * 0.5)
		var s0_fit := _size0_fit_unif(aabb_main.length(), vp_m, 0.75)  # N批：统一口径初始取景
		for mul: float in [1.0, 1.6, 0.999]:  # 回修4 档位：初始/拉远/微放大（<下限被 clamp 回极限档）
			inst.set("_ortho_size_main", s0_fit * mul)
			inst.call("_update_main_camera")
			var proj_c: Vector2 = main_cam.unproject_position(Vector3.ZERO)  # 块中心=世界原点
			check(proj_c.distance_to(vp_center) < 0.51,
				"回修3 B：size=%.2f×s0 档块中心投影=视口中心（偏差 %.2fpx，任何档位居中）"
				% [mul, proj_c.distance_to(vp_center)])
		inst.set("_ortho_size_main", s0_fit)
		inst.call("_update_main_camera")
	# E：ToastCenter 居中路径——批次V规格§3.4 等价替换留痕（V-C6，原 M-E 回修3 E「centered=true
	# 卡片进顶部中央盒」同层/中线/顶缘/入盒四断言废止）：中央锚点盒退役，中央 toast 口径单点归
	# TopStrip（Game.toast centered=true → _strip.push_info 改道，几何断言迁 test_v_top_strip A2）；
	# ToastCenter 收窄右上堆叠专用——centered=true 直推落右上队列（未挂 strip 的降级路径）、
	# 不再创建中央锚点盒节点；「默认路径零变化」断言保持。
	var tc: Node = (load("res://scenes/shared/toast_center.gd") as GDScript).new()
	add_child(tc)
	tc.call("push", "无法对接：木料与固定件干涉，请调整挖除位置", "warn", 60.0, true)
	await process_frame
	await process_frame
	check(tc.get_child_count() >= 1,
		"批次V§3.4（等价替换旧·回修3 E 中央盒断言）：centered=true 直推 → 卡片落右上队列（降级路径）")
	check(tc.get_child(0) is PanelContainer,
		"批次V§3.4（等价替换）：降级直推卡片结构保持（PanelContainer L3 样式载体）")
	check(tc.get_parent().get_node_or_null("ToastCenterTop") == null,
		"批次V§3.4（等价替换）：父层无中央锚点盒节点（懒创建路径已删，同层语义由右上队列承载）")
	check(tc.has_method("push") and tc.has_method("clear_all"),
		"批次V§3.4（等价替换）：push/clear_all 公开 API 保持（右上队列契约不变）")
	tc.call("push", "右上路径回归", "info", 60.0)  # 缺省参数=右上原路径
	await process_frame
	check(tc.get_child_count() >= 2, "回修3 E：默认路径零变化（右上盒仍收卡）")
	tc.call("clear_all")
	tc.queue_free()

	# ==================== 段 9：N批 三窗极致占满（文字让位）+ N12-4 侧窗再放大 + N7 旋转缩放解耦 ====================
	# N批 等价替换留痕（用户 2026-09-09 拍板「极致占满、文字让位」）：旧 M-E 回修4 B 几何
	# （侧窗 380×164@y88 避让设置钮 / 主窗 880×340@x136,y260 避让提示行与见证者）按新口径废止。
	# N12-4 等价替换留痕（用户 2026-09-10 口径「中间木料大小够了，左上右上还是小，尽可能再放大」）：
	# N批 几何（侧窗 440×148@y64 / 主窗 1060×400@x46,y216）再度扩大为——
	#   ①侧窗 520×202@y64（垂直：吃掉与主窗 4px 间隙+主窗让渡高度 400→346，底 266/主窗顶 270 留 4px；
	#     水平：外缘 12/1140 不动、对称向中缝扩展 440→520，中缝留 88px）；
	#   ②主窗 1060×346@x46,y270（高度让渡后仍占满中带，底 616 不变让位贴底提示行）；
	#   ③旧「主窗左缘避见证者立绘」废止不变：主窗允许覆盖立绘区域（WitnessPortrait 节点序在
	#     MainView 之后=置顶绘制+点击优先，可点性不受影响；观感走查定稿）；
	#  ④TopBar/VoxelLabel 不得被三窗遮挡（13e1e88 修复的视觉塌缩回归保护）；侧窗顶 64 不高于
	#     TopBar 底 60 之下（可点性）；
	#   ⑤N7 旋转缩放解耦：_ortho_size_min_for 对任意朝向返回统一值（包围球口径），旋转全程
	#     ortho size 恒定（旧「当前朝向投影下限随朝向顶大」=旋转时木块自己缩小的根因，废止）；
	#     改窗后正交包围球口径自动适配新视口（N7 红线复验=段 9b/走查旋转 4 帧）。
	var tgv: Control = inst.get_node_or_null("TargetView") as Control
	var jgv: Control = inst.get_node_or_null("JoinView") as Control
	var mgv: Control = inst.get_node_or_null("MainView") as Control
	check(tgv is Control and jgv is Control and mgv is Control, "N2：三窗节点存在")
	if tgv != null and jgv != null and mgv != null:
		var rt := tgv.get_global_rect()
		var rj := jgv.get_global_rect()
		var rm := mgv.get_global_rect()
		check(absf(rt.position.x - 12.0) < 0.6 and absf(rt.position.y - 64.0) < 0.6
			and absf(rt.size.x - 520.0) < 0.6 and absf(rt.size.y - 202.0) < 0.6,
			"N12-4：TargetView rect≈(12,64,520,202)（实际 %s）" % str(rt))
		check(absf(rj.position.x - 620.0) < 0.6 and absf(rj.position.y - 64.0) < 0.6
			and absf(rj.size.x - 520.0) < 0.6 and absf(rj.size.y - 202.0) < 0.6,
			"N12-4：JoinView rect≈(620,64,520,202)（实际 %s）" % str(rj))
		check(absf(rm.position.x - 132.48) < 0.6 and absf(rm.position.y - 270.0) < 0.6
			and absf(rm.size.x - 973.52) < 0.6 and absf(rm.size.y - 346.0) < 0.6,
			"N12-4→AD §4.3.5：MainView rect≈(132.48,270,973.52,346)（实际 %s；anchor_left 0.0399→0.115 收窄避让左下立绘，旧 rect(46,270,1060,346) 留痕——顶/底/右缘与高度 346 全部不变，仅左缘内移 86.48px）" % str(rm))
		check(absf((W - rj.end.x) - rt.position.x) < 0.6,
			"N2：左右侧窗对称（左留边 %.2f / 右留边 %.2f）" % [rt.position.x, W - rj.end.x])
		# N2「主窗水平居中」判据 → 批次 AD §4.3.5 等价改写：主窗**有意偏右**（左缘避让立绘、右缘不动）
		# → 几何中心由 W*0.5=576.0 平移至 (132.48+1106.0)/2=619.24。旧值留痕：`absf(rm.get_center().x - W*0.5) < 0.6`。
		# 判据语义「主窗仍占满中带（右缘锚点 1106 不动 + 中缝不留白）」保持，仅中心基准随避让口径等价平移；
		# 断言数 1→2（只增不减）：新增「主窗与立绘可见带不再水平重叠」= §4.3.5 收窄避让的正向判据。
		check(absf(rm.get_center().x - 619.24) < 0.6,
			"N2→AD §4.3.5：主窗中心 x≈619.24（避让立绘后仍占满中带：右缘 1106 不动；旧「居中 576」随 anchor_left 0.115 收窄平移留痕）")
		var wit_ad: Control = inst.get_node_or_null("WitnessPortrait") as Control
		check(wit_ad != null and rm.position.x >= wit_ad.get_global_rect().end.x,
			"AD §4.3.5：MainView 左缘 132.48 ≥ 立绘右缘（anchor 0.11→126.72）→ 拾取带水平零重叠（收窄避让正向判据；旧 N12-4「主窗允许覆盖立绘」口径随点击恢复废止）")
		# N批 等价替换留痕：旧「侧窗顶 y≥88 避让右上设置钮（底 84）」废止——侧窗顶至 TopBar
		# 下方 y≈64，允许与设置钮 x/y 带交叠（设置钮在 GlobalUI 层 100 浮于窗上、窗 Panel
		# mouse_filter=2 现状保持 → 可点性不受影响；观感走查定稿）
		check(rt.position.y >= 64.0 - 0.6 and rj.position.y >= 64.0 - 0.6,
			"N2：侧窗顶 y≈64（TopBar 下方不高于其底 60；N批等价替换旧 ≥86 设置钮避让）")
		check(not rt.intersects(rm) and not rj.intersects(rm) and not rt.intersects(rj),
			"N2：三窗两两不重叠")
		var hint9: Label = inst.get_node_or_null("HintLabel") as Label
		check(hint9 is Label, "N2：底部提示行 Label 存在（贴底压扁保留）")
		if hint9 != null:
			var rh: Rect2 = hint9.get_global_rect()
			check(rm.end.y < rh.position.y - 1.0,
				"N2：主窗底 %.1f 在贴底提示行顶 %.1f 之上（提示行完整可见）"
				% [rm.end.y, rh.position.y])
			check(rh.end.y >= 640.0, "N2：提示行贴底（底缘 %.1f ≥640）" % rh.end.y)
		# N批：TopBar VoxelLabel（13e1e88 视觉塌缩修复）不得被三窗扩大遮挡或挤压
		var voxel_lbl9: Control = inst.get_node_or_null("TopBar/VoxelLabel") as Control
		check(voxel_lbl9 is Control, "N2：TopBar/VoxelLabel 存在（回归保护基准）")
		if voxel_lbl9 != null:
			var rv9: Rect2 = voxel_lbl9.get_global_rect()
			check(not rt.intersects(rv9) and not rj.intersects(rv9) and not rm.intersects(rv9),
				"N2：三窗均不遮挡 TopBar/VoxelLabel（计数标签完整可见不挤压）")
		# N批 等价替换留痕：旧「主窗左缘避开左下见证者立绘」废止——立绘允许被主窗覆盖，
		# 但节点序在 MainView 之后（后绘制=置顶+点击优先），可点性与可见性不变（观感走查定稿）
		var wit9: Control = inst.get_node_or_null("WitnessPortrait") as Control
		check(wit9 is Control, "N2：WitnessPortrait 存在")
		if wit9 != null:
			check(wit9.get_index() > mgv.get_index(),
				"N2：WitnessPortrait 节点序在 MainView 之后（置顶绘制+点击优先，可点性不受主窗覆盖影响）")
			check(wit9.visible, "N2：WitnessPortrait 可见")

	# ---- 段 9b：N7 旋转缩放解耦（纯函数两朝向同值 + 旋转行为 size 恒定，主/侧双路径） ----
	# N12-4 复验口径：改窗后 ortho 包围球口径自动适配新视口（初始 size 按新 vp 重算，段 1e），
	# 但「旋转全程 size 恒定零跳变」红线不随几何变化——本段断言零改动即复验载体。
	if aabb_main.x > 0.0 and inst.has_method("_ortho_size_min_for"):
		var smin_a: float = float(inst.call("_ortho_size_min_for", "Main", 0.0, 0.0))
		var smin_b: float = float(inst.call("_ortho_size_min_for", "Main", deg_to_rad(37.0), deg_to_rad(-21.0)))
		var smin_c: float = float(inst.call("_ortho_size_min_for", "Main", deg_to_rad(-120.0), deg_to_rad(60.0)))
		check(smin_a > 0.0 and absf(smin_a - smin_b) < 0.0001 and absf(smin_a - smin_c) < 0.0001,
			"N7：_ortho_size_min_for 三个不同朝向返回同值 %.4f（与 yaw/pitch 解耦）" % smin_a)
		check(absf(smin_a - _smin_unif(aabb_main.length(), vp_m)) < 0.01,
			"N7：统一下限=包围球口径（期望 %.4f，实际 %.4f）" % [_smin_unif(aabb_main.length(), vp_m), smin_a])
	if main_cam != null and mcont != null and main_vp.size.x > 1:
		var sz9: float = main_cam.size
		var yaw9: float = _fget(inst, "_orbit_yaw")
		var pitch9: float = _fget(inst, "_orbit_pitch")
		inst.set("_orbit_yaw", 0.0)
		inst.set("_orbit_pitch", deg_to_rad(-30.0))
		inst.call("_update_main_camera")
		check(absf(main_cam.size - sz9) < 0.001,
			"N7：旋转（yaw→0/pitch→−30°）后 MainView ortho size 恒定（%.4f→%.4f）" % [sz9, main_cam.size])
		inst.set("_orbit_yaw", deg_to_rad(-70.0))
		inst.set("_orbit_pitch", deg_to_rad(50.0))
		inst.call("_update_main_camera")
		check(absf(main_cam.size - sz9) < 0.001, "N7：再次大角度旋转（yaw→−70°/pitch→50°）后 size 仍恒定（全程零跳变）")
		inst.set("_orbit_yaw", yaw9)
		inst.set("_orbit_pitch", pitch9)
		inst.call("_update_main_camera")
	var tcont9: SubViewportContainer = inst.get_node_or_null("TargetView/ViewportContainer") as SubViewportContainer
	var tgt_cam9: Camera3D = inst.get_node_or_null("TargetView/ViewportContainer/SubViewport/Camera3D") as Camera3D
	if tcont9 != null and tgt_cam9 != null and vp_t.x > 1.0:
		var tsz9: float = tgt_cam9.size
		var sy_d: Dictionary = inst.get("_side_yaw") as Dictionary
		var sp_d: Dictionary = inst.get("_side_pitch") as Dictionary
		var tyaw9: float = float(sy_d["Target"])
		var tpitch9: float = float(sp_d["Target"])
		sy_d["Target"] = 0.0
		sp_d["Target"] = deg_to_rad(-25.0)
		inst.call("_update_side_camera", "Target")
		check(absf(tgt_cam9.size - tsz9) < 0.001,
			"N7：侧视图旋转（Target yaw→0/pitch→−25°）后 ortho size 恒定（%.4f→%.4f）" % [tsz9, tgt_cam9.size])
		sy_d["Target"] = tyaw9
		sp_d["Target"] = tpitch9
		inst.call("_update_side_camera", "Target")

	# ==================== 段 10：回修4 A 最大放大档不穿帮（主/侧滚轮到底=投影完整留边 ≥8px） ====================
	if mcont != null and main_vp.size.x > 1 and aabb_main.x > 0.0:
		for i3: int in 80:
			mcont.gui_input.emit(_mb(MOUSE_BUTTON_WHEEL_UP, true, Vector2(10, 10)))
		var sz_bot: float = _fget(inst, "_ortho_size_main")
		var span_now := _span_at(aabb_main, _fget(inst, "_orbit_yaw"), _fget(inst, "_orbit_pitch"))
		var px_per_world := vp_m.y / sz_bot
		check(span_now.y * px_per_world <= vp_m.y - 2.0 * FIT_MARGIN + 0.51,
			"回修4 A：主视图最大档块投影高 %.1fpx ≤ 视口高 %.1f−16（垂直不穿帮）"
			% [span_now.y * px_per_world, vp_m.y])
		check(span_now.x * px_per_world <= vp_m.x - 2.0 * FIT_MARGIN + 0.51,
			"回修4 A：主视图最大档块投影宽 %.1fpx ≤ 视口宽 %.1f−16（水平不穿帮）"
			% [span_now.x * px_per_world, vp_m.x])
		# 侧面板（Target）同样口径：滚轮到底=该窗内完整留边
		var tcont10: SubViewportContainer = inst.get_node_or_null("TargetView/ViewportContainer") as SubViewportContainer
		if tcont10 != null and vp_t.x > 1.0 and aabb_tgt.x > 0.0:
			for i4: int in 80:
				tcont10.gui_input.emit(_mb(MOUSE_BUTTON_WHEEL_UP, true, Vector2(40, 40)))
			var szt_bot: float = float((inst.get("_ortho_size_side") as Dictionary)["Target"])
			var span_t := _span_at(aabb_tgt, float((inst.get("_side_yaw") as Dictionary)["Target"]),
				float((inst.get("_side_pitch") as Dictionary)["Target"]))
			var pxw_t := vp_t.y / szt_bot
			check(span_t.y * pxw_t <= vp_t.y - 2.0 * FIT_MARGIN + 0.51
				and span_t.x * pxw_t <= vp_t.x - 2.0 * FIT_MARGIN + 0.51,
				"回修4 A：侧面板最大档块投影完整（高 %.1f/%.1f 宽 %.1f/%.1f，窗 %s；用户拍板「最大限制一下」）"
				% [span_t.y * pxw_t, vp_t.y, span_t.x * pxw_t, vp_t.x, str(vp_t)])
			# 恢复侧面板初始取景（后续无侧视口消费段，保持环境干净）
			inst.call("_update_side_camera", "Target")

	# ==================== 段 11：N批 初始取景（统一口径）+ 中央/侧块视觉尺寸比 ====================
	# N批 等价替换留痕：旧「初始档块高撑满视口（−16 边距）」口径随 N7 统一取景废止——
	# 初始取景改为保证「任意朝向最坏投影完整」，初始朝向的实际块高 ≤ 视口−16（完整不裁切）；
	# 「尽可能放到最大」的观感由 N2 窗口极致扩大承载。
	# N12-4 等价替换留痕（用户 2026-09-10「侧窗尽可能再放大」取代旧「中央比侧块大好几倍 ≥2.5」）：
	# 侧窗放大后（主窗高 400→346 让渡、侧窗高 148→202）两侧初始取景比例收窄——探测实值
	# 3.160→1.885（tools_n12b_shot/n12b_probe.gd 实测主块宽 307px/侧块宽 163px），用户已以
	# 「中间大小够了、侧窗尽可能大」新口径取代倍数要求；断言下限等价替换 2.5→1.8（留安全
	# 余量），中央块仍显著大于侧块。
	if aabb_main.x > 0.0 and aabb_tgt.x > 0.0 and vp_m.x > 1.0 and vp_t.x > 1.0:
		var span0m := _span_at(aabb_main, deg_to_rad(45.0), deg_to_rad(35.264))
		var span0t := _span_at(aabb_tgt, deg_to_rad(45.0), deg_to_rad(35.264))
		var s0m2 := _size0_fit_unif(aabb_main.length(), vp_m, 0.75)
		var s0t2 := _size0_fit_unif(aabb_tgt.length(), vp_t, 0.70)
		var w_m := span0m.x * (vp_m.y / s0m2)   # 主块投影宽 px
		var h_m := span0m.y * (vp_m.y / s0m2)   # 主块投影高 px
		var w_t := span0t.x * (vp_t.y / s0t2)   # 侧块投影宽 px
		check(h_m <= vp_m.y - 2.0 * FIT_MARGIN + 0.51,
			"N7：主视图初始档块高 %.1fpx ≤ 视口 %.1f−16（任意朝向完整保证下的当前朝向不裁切）"
			% [h_m, vp_m.y])
		check(w_m / w_t >= 1.8,
			"N12-4：中央块/侧面板块初始视觉宽比 %.2f ≥1.8（旧 ≥2.5 随侧窗再放大口径等价替换；用户「中间大小够了」）"
			% (w_m / w_t))

	# ==================== 段 12：回修4 C 右键交互分流（拖拽=旋转 / 原地点击=删除） ====================
	if mcont != null and main_vp.size.x > 1:
		var rem0: int = (inst.call("get_remaining_voxels") as Array).size()
		var yaw_r0: float = _fget(inst, "_orbit_yaw")
		mcont.gui_input.emit(_mb(MOUSE_BUTTON_RIGHT, true, Vector2(60, 60)))
		mcont.gui_input.emit(_mm_at(Vector2(90, 60)))
		mcont.gui_input.emit(_mm_at(Vector2(120, 60)))
		mcont.gui_input.emit(_mb(MOUSE_BUTTON_RIGHT, false, Vector2(120, 60)))
		check(absf(_fget(inst, "_orbit_yaw") - yaw_r0) > 0.001,
			"回修4 C：右键拖拽（位移>2px）=旋转（yaw 变化）")
		check((inst.call("get_remaining_voxels") as Array).size() == rem0,
			"回修4 C：右键拖拽不删除（remaining 不变）")
		var hit_r: Vector3i = inst.call("get_cell_hit",
			main_cam.project_ray_origin(Vector2(main_vp.size.x * 0.5, main_vp.size.y * 0.5)),
			main_cam.project_ray_normal(Vector2(main_vp.size.x * 0.5, main_vp.size.y * 0.5)))
		check(hit_r != MISS, "回修4 C 前置：视口中心命中木料（删除断言环境）")
		if hit_r != MISS:
			inst.call("select_voxel", hit_r, false)
			mcont.gui_input.emit(_mb(MOUSE_BUTTON_RIGHT, true, Vector2(70, 70)))
			mcont.gui_input.emit(_mb(MOUSE_BUTTON_RIGHT, false, Vector2(70, 70)))  # 原地抬起（无 motion）
			check((inst.call("get_remaining_voxels") as Array).size() == rem0 - 1,
				"回修4 C：右键原地点击=删除选中（删除语义完全不变）")
			inst.call("clear_selection")

	inst.queue_free()
	container.queue_free()
	finish()
