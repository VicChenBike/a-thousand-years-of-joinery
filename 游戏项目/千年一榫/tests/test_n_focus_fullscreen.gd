extends "res://tests/test_base.gd"
## N3（批次 N / spec §6.4 + §6.5）：聚焦动画全屏三色重做——判定用例（TDD 红灯先行）。
## 契约（spec §五方案口径 4~7 + §6.4 方案口径）：
##   ①全屏层：FocusFX 重写为单节点控制器 extends CanvasLayer，layer 走查定稿=0（关卡内容同层
##     树序置顶，GlobalUI=1/SuccessOverlay=0（P批波2 结算覆盖层避让设置面板）/GlowLayer=100 均在其上；spec 暂定 85 走查可调）；
##     子容器 SubViewportContainer mouse_filter=IGNORE（纯视觉层，
##     不拦截顶栏聚焦钮/退出钮/设置钮任何点击）；内含全屏 SubViewport + 透视相机。
##   ②三色通道：单控制器三通道接入（主=金黄/对照=绿/固定件=红），三视图同时聚焦三色共存；
##     _fx_main/_fx_target/_fx_join 句柄面保留（N批等价替换：语义=通道引用，指向同一控制器）。
##   ③相位机：IDLE→CONDENSE(凝聚 0.25s，体素先实体→密集点云面，体素凝聚完成才隐藏=无空窗跳变)
##     →SPREAD(散开 1.2s，P批波2 放慢+滞空缓动，屏外环域)→STEADY(稳态 闪烁/漂移)；deactivate=完整倒放 RETURN
##     （散点收拢→点云面→实体还原，无残留点阵）；重复 activate 幂等；RETURN 期 activate=打断快进
##     收尾后重新激活；deactivate_immediate（成功动画入口）立即复位幂等。
##   ④性能红线：点 transform 静态预生成（激活时一次性构建），动画 GPU uniform 驱动
##     （ShaderMaterial u_spread/u_alpha；闪烁/漂移走 TIME，稳态 CPU 零逐帧成本）。
##   ⑤散点密度：目标屏幕位按「距四角距离」加权（离角越近越密）；纯函数可无头单测。
## ⚠ 坑纪律（spec 铁律 5）：无头 MultiMesh 色/transform/custom 读回恒 0——
##   只断言 instance_count/use_colors/use_custom_data/材质标志/自持数组等属性证据链；
##   观感（无空窗/四角更密/三色共存/倒放无残留）= 窗口截图走查判定（spec §6.5）。
## 环境说明（同既有测试）：--script 模式 class_name 注册时序不稳——新组件一律 load() +
##   set_script()/call()，不直接引用全局类名（P2-5）。

const FX_SCRIPT := "res://scripts/focus_fx.gd"
const VOX_SCRIPT := "res://scripts/level_voxel_view.gd"
const LEVEL_SCENE := "res://scenes/level/level_scene.tscn"
const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"

## 递归查找子树中的 MultiMeshInstance3D（不约定节点名，降脆性）。
func _find_mmi(node: Node) -> MultiMeshInstance3D:
	for c: Node in node.get_children():
		if c is MultiMeshInstance3D:
			return c as MultiMeshInstance3D
		var found: MultiMeshInstance3D = _find_mmi(c)
		if found != null:
			return found
	return null

func _find_svp_container(node: Node) -> SubViewportContainer:
	for c: Node in node.get_children():
		if c is SubViewportContainer:
			return c as SubViewportContainer
		var found: SubViewportContainer = _find_svp_container(c)
		if found != null:
			return found
	return null

## 递归查找子树中的 Camera3D（透视相机挂 DotWorld 下，不约定层级）。
func _find_cam(node: Node) -> Camera3D:
	for c: Node in node.get_children():
		if c is Camera3D:
			return c as Camera3D
		var found: Camera3D = _find_cam(c)
		if found != null:
			return found
	return null

## Variant → Dictionary 防御（--script 模式属性缺失时降级 FAIL 而非中断，P2-5 同源纪律）。
func _dict_or(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}

## 批次V回修②B移交/V-C5语义对齐夹具：TopStrip 替身——记录 Game.confirm 委托来的 push_confirm
## 调用（test_v_confirm_migration/test_level_extra 同款夹具形态；--script 模式 class_name 注册
## 时序不稳，内部类 load-free 定义随本文件，命名加 NFF 后缀防撞）。
class StripSpyNFF extends Node:
	var confirm_calls: Array = []   # 每项 [text, on_confirmed, on_canceled]
	var info_calls: Array = []      # 每项 [text, seconds]
	func push_confirm(text: String, on_confirmed: Callable = Callable(),
			on_canceled: Callable = Callable()) -> void:
		confirm_calls.append([text, on_confirmed, on_canceled])
	func push_info(text: String, seconds: float = 3.0) -> void:
		info_calls.append([text, seconds])

var ssp_nff: StripSpyNFF = null

## 缺方法安全调用：N3 新 API（bind_channel/activate_channel/...）在实现前调用会触发
## SCRIPT ERROR 并中断测试函数（4.7 实证）——统一经此调用，缺失时返回 def 降级 FAIL。
func _mc(node: Variant, method: String, args: Array = [], def: Variant = null) -> Variant:
	if node is Object and (node as Object).has_method(method):
		return (node as Object).callv(method, args)
	return def

func _cleanup_files() -> void:
	for p: String in [SAVE_PATH, FLAG_PATH]:
		var abs: String = ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs):
			DirAccess.remove_absolute(abs)

func _make_level(ch: int) -> Node:
	var inst: Node = (load(LEVEL_SCENE) as PackedScene).instantiate()
	inst.call("set_context", {"chapter": ch})
	add_child(inst)
	await process_frame
	await process_frame
	return inst

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
const DISC_BK_PREFIX := "user://_r2b_nff_backup_"
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
	print("EVID|user_restore|nff|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_n_focus_fullscreen ==")
	_backup_user()
	# 批次V回修②B/V-E4 补清档基线（test_v_confirm_migration :132-136 同款）：起测备份后把
	# 测试域档案全清+SaveManager 内存重同步——否则本机真实 save.json 的挖除断点经
	# level._replay_saved_progress 泄入关卡（实测本机断点恰含 (0,0,0)：remaining=191、
	# select_voxel 拒选 → 聚焦 Main 通道 activate_channel「selected 为空拒绝」恒 false），
	# 段 D/E 三通道断言与 F 段「聚焦已激活」前置在 HEAD 即环境性红（受控红实证，69da6e5 同款甄别）。
	for p: String in DISC_WATCHED:
		_disc_del(p)
	var sm_reset: Node = get_root().get_node_or_null(NodePath("SaveManager"))
	if sm_reset != null:
		sm_reset.load_game()
	var lib: Node = get_root().get_node("LevelLibrary")
	lib.scan_directory("res://levels_data")
	var fx_s: Script = load(FX_SCRIPT) as Script
	check(fx_s != null, "N3：scripts/focus_fx.gd 可加载")
	if fx_s == null:
		finish()
		return
	var cmap: Dictionary = fx_s.get_script_constant_map()

	# ==================== A. 全屏层与层号口径（spec §6.4 方案口径①）====================
	var inst: Node = await _make_level(1)
	var fx: Node = inst.get_node_or_null("FocusFX")
	check(fx != null and fx is CanvasLayer, "N3①：关卡场景挂全屏层 FocusFX（CanvasLayer，随场景生命周期）")
	check(fx != null and int((fx as CanvasLayer).layer) == int(cmap.get("LAYER", -1)) and int(cmap.get("LAYER", -1)) == 0,
		"N3①：全屏层 layer=0（走查定稿：关卡内容同层树序置顶，GlobalUI=1/SuccessOverlay=0（P批波2 结算覆盖层避让设置面板）/GlowLayer=100 均在其上——spec §五 7「暂定 85 走查可调」授权调整，85 实测视觉压设置覆盖层，N批等价替换留痕）")
	check(fx != null and fx.get_parent() == inst, "N3①：全屏层为关卡场景子节点（不挂全局单例，关卡重开不残留）")
	var cont: SubViewportContainer = _find_svp_container(fx) if fx != null else null
	check(cont != null, "N3①：全屏层含 SubViewportContainer 容器")
	check(cont != null and (cont as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"N3①：容器 mouse_filter=IGNORE（纯视觉层，不拦截顶栏钮点击）")
	var lvp: SubViewport = cont.get_node_or_null("SubViewport") if cont != null else null
	check(lvp != null and lvp.transparent_bg, "N3①：全屏 SubViewport 存在且透底（游戏画面透出）")
	var lcam: Camera3D = _find_cam(lvp) if lvp != null else null
	check(lcam != null and lcam.projection == Camera3D.PROJECTION_PERSPECTIVE,
		"N3①：全屏层透视相机（点深度/大小随深度/视差前提）")
	# 通道句柄面（N批等价替换：_fx_main/_fx_target/_fx_join → 同一控制器引用）
	var fxm: Node = inst.get("_fx_main")
	check(fxm != null and fxm == inst.get("_fx_target") and fxm == inst.get("_fx_join"),
		"N3②：三句柄=同一全屏控制器（通道引用，spec §五 5）")
	check(fxm != null and fxm == fx, "N3②：句柄指向场景内 FocusFX 全屏层")
	var chs: Dictionary = _dict_or(fxm.get("_channels") if fxm != null else null)
	check(chs.size() == 3 and chs.has("Main") and chs.has("Target") and chs.has("Join"),
		"N3②：三通道已接入（Main/Target/Join）")
	var mvp: SubViewport = inst.get("main_viewport")
	var tvp: SubViewport = inst.get("target_viewport")
	var jvp: SubViewport = inst.get("join_viewport")
	check(_dict_or(chs.get("Main")).get("vp") == mvp and _dict_or(chs.get("Target")).get("vp") == tvp \
		and _dict_or(chs.get("Join")).get("vp") == jvp,
		"N3②：三通道分别绑定三视图 SubViewport（位置换算单处实现前提）")

	# ==================== B. 常量组与三色通道配置（spec §6.4 目标）====================
	check_eq(int(cmap.get("PHASE_IDLE", -1)), 0, "N3③：PHASE_IDLE=0")
	check_eq(int(cmap.get("PHASE_CONDENSE", -1)), 1, "N3③：PHASE_CONDENSE=1（凝聚相位，N批新增）")
	check_eq(int(cmap.get("PHASE_SPREAD", -1)), 2, "N3③：PHASE_SPREAD=2（散开相位）")
	check_eq(int(cmap.get("PHASE_STEADY", -1)), 3, "N3③：PHASE_STEADY=3（稳态相位，N批新增）")
	check_eq(int(cmap.get("PHASE_RETURN", -1)), 4, "N3③：PHASE_RETURN=4（收回=完整倒放）")
	check_eq(float(cmap.get("CONDENSE_TIME", -1.0)), 0.25, "N3③：CONDENSE_TIME=0.25s（实体→点云面，spec 暂定）")
	check_eq(float(cmap.get("SPREAD_TIME", -1.0)), 1.2,
		"P批波2等价替换（2026-09-10 用户口径 P-C 散开放慢+滞空）：SPREAD_TIME=1.2s（聚焦散开；N3 0.9 档废止留痕）")
	check_eq(float(cmap.get("RETURN_TIME", -1.0)), 0.6,
		"N3③：RETURN_TIME=0.6s（倒放总时长，M批 0.4 等价替换留痕：完整倒放=收拢0.4+还原0.2）")
	var cc: Color = _dict_or(cmap.get("CHANNEL_COLORS")).get("Main", Color())
	check_eq(cc, Color(0.96, 0.77, 0.26), "N3②：主通道=金黄（沿用 GOLD 口径，M批等价替换）")
	check_eq(_dict_or(cmap.get("CHANNEL_COLORS")).get("Target", Color()), Color(0.30, 0.85, 0.40),
		"N3②：对照成品通道=绿（左上）")
	check_eq(_dict_or(cmap.get("CHANNEL_COLORS")).get("Join", Color()), Color(0.90, 0.25, 0.20),
		"N3②：对接固定件通道=红（右上）")
	check(cmap.get("GOLD", Color()) == Color(0.96, 0.77, 0.26), "N3②：GOLD 旧常量等价保留（契约面）")
	check_eq(int(cmap.get("DOTS_PER_VOXEL", -1)), 7,
		"O批等价替换（2026-09-10 用户反馈②遮屏降密）：DOTS_PER_VOXEL=7（细腻档；N3 22 档废止，M批 6 亦废）")
	var cset: Dictionary = {cc: true}
	for k: String in ["Target", "Join"]:
		cset[_dict_or(cmap.get("CHANNEL_COLORS")).get(k, Color())] = true
	check(cset.size() == 3, "N3②：三色互异（三色共存可辨前提）")

	# ==================== C. 纯函数证据链（无头可测：相机距离/坐标换算/四角加权）====================
	var dist: float = float(_mc(fx_s, "compute_camera_distance", [648.0, float(cmap.get("FOV_DEG", 45.0))], -1.0))
	check(absf(dist - 782.27) < 0.5,
		"N3①：透视相机距离=视高一半/tan(fov/2)≈782.27（焦点平面 1px=1 世界单位，实际 %.2f）" % dist)
	check(float(_mc(fx_s, "compute_camera_distance", [0.0, 45.0], -1.0)) > 0.0,
		"N3①：视高无效防御回退（>0，不产生退化相机）")
	var w0: Vector3 = _mc(fx_s, "screen_to_layer_world", [Vector2.ZERO, Vector2(1152, 648)], Vector3(-9, -9, -9))
	check(w0.x < -570.0 and w0.y > 318.0, "N3①：屏幕(0,0)→层世界左上角（y 翻转，实际 %s）" % str(w0))
	var wc: Vector3 = _mc(fx_s, "screen_to_layer_world", [Vector2(576, 324), Vector2(1152, 648)], Vector3(-9, -9, -9))
	check(wc.length() < 0.01, "N3①：屏幕中心→层世界原点")
	var cc_corner: float = float(_mc(fx_s, "corner_closeness", [Vector2(1152, 648), Vector2(1152, 648)], -1.0))
	var cc_center: float = float(_mc(fx_s, "corner_closeness", [Vector2(576, 324), Vector2(1152, 648)], -1.0))
	check(cc_corner > 0.95 and cc_center < 0.05,
		"N3⑤：corner_closeness 角=1/中心=0（距四角距离加权基准）")
	# 散点目标位生成（O批等价替换，2026-09-10 用户反馈③「先发散到屏幕外面」）：确定性 +
	# 全部落屏外 + 四象限（离心向）覆盖 + 角向密度>边向密度（离角偏置语义屏外等价保留）。
	# 原 N3「全部 clamp 屏内（全屏铺满不越界裁切）+ 屏内角区/中心区面积归一密度」契约随
	# 散开目标改屏外环域废止，本块按新语义等价重写并留痕（细节档断言另见 test_o_animation.gd）。
	var rnd_a := RandomNumberGenerator.new()
	rnd_a.seed = 20260909
	var rnd_b := RandomNumberGenerator.new()
	rnd_b.seed = 20260909
	var det_same := true
	var all_off := true
	var quadrant := {"tl": false, "tr": false, "bl": false, "br": false}
	var vsz := Vector2(1152, 648)
	var center := vsz * 0.5
	var ca := absf(atan2(vsz.y * 0.5, vsz.x * 0.5))
	var corner_n := 0
	var edge_n := 0
	for i: int in 2400:
		var t_a: Vector2 = _mc(fx_s, "spread_target_screen", [Vector2(576, 324), rnd_a, vsz], Vector2(-1, -1))
		var t_b: Vector2 = _mc(fx_s, "spread_target_screen", [Vector2(576, 324), rnd_b, vsz], Vector2(-1, -1))
		if (t_a - t_b).length() > 0.001:
			det_same = false
		if t_a.x >= 0.0 and t_a.x <= vsz.x and t_a.y >= 0.0 and t_a.y <= vsz.y:
			all_off = false  # O批：屏内命中=违例（原 in_screen 语义反转）
		if t_a.x < center.x and t_a.y < center.y: quadrant["tl"] = true
		if t_a.x >= center.x and t_a.y < center.y: quadrant["tr"] = true
		if t_a.x < center.x and t_a.y >= center.y: quadrant["bl"] = true
		if t_a.x >= center.x and t_a.y >= center.y: quadrant["br"] = true
		var ang := absf(Vector2(1, 0).angle_to((t_a - center).normalized()))
		for base: float in [ca, PI - ca]:
			if absf(angle_difference(ang, base)) < deg_to_rad(15.0):
				corner_n += 1
		for base: float in [0.0, PI * 0.5, PI, PI * 1.5]:
			if absf(angle_difference(ang, base)) < deg_to_rad(15.0):
				edge_n += 1
	check(det_same, "N3⑤：spread_target_screen 同种子确定性（静态预生成可复现）")
	check(all_off, "O批等价替换：散点目标全部落设计视口外（散开=逃出屏幕；原「全部屏内铺满」废止）")
	check(quadrant["tl"] and quadrant["tr"] and quadrant["bl"] and quadrant["br"],
		"O批等价替换：四象限（离心向）均有目标（全向散开覆盖）")
	check(corner_n > edge_n,
		"O批等价替换：角向密度>边向密度（%d vs %d；原屏内角区/中心区面积归一口径随屏外化废止）" % [corner_n, edge_n])

	# ==================== D. 相位机全流程（rig：小视口+VoxelView，无头属性证据链）====================
	var vox_s: Script = load(VOX_SCRIPT) as Script
	var world := Node3D.new()
	add_child(world)
	var vp := SubViewport.new()
	vp.size = Vector2i(160, 120)
	world.add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 6.0
	cam.position = Vector3(0, 0, 20)
	vp.add_child(cam)
	var vv: Node = (vox_s as GDScript).new()
	vv.name = "VoxelView"
	vp.add_child(vv)
	vv.call("build_voxels", ["0,0,0", "1,0,0", "2,0,0", "3,0,0"], Vector3i(4, 1, 1), StandardMaterial3D.new())
	var fx2: Node = (fx_s as GDScript).new()
	fx2.name = "FocusFXRig"
	world.add_child(fx2)
	_mc(fx2, "bind_channel", ["Main", vp])
	await process_frame
	var built: Array = vv.call("get_built_cells")
	var n_unsel: MeshInstance3D = vv.call("get_voxel_node", Vector3i(2, 0, 0))
	var n_sel: MeshInstance3D = vv.call("get_voxel_node", Vector3i(0, 0, 0))

	check_eq(int(fx2.call("get_phase")), int(cmap.get("PHASE_IDLE", -1)), "N3③：初始 get_phase()==IDLE")
	check_eq(bool(_mc(fx2, "activate_channel", ["Main", [], built], false)), false,
		"N3③：selected 为空 activate_channel 返回 false（不激活）")
	check_eq(bool(_mc(fx2, "activate_channel", ["Main", [Vector3i(0, 0, 0)], built], false)), true,
		"N3③：activate_channel 成功（selected 非空）")
	check_eq(int(fx2.call("get_phase")), int(cmap.get("PHASE_CONDENSE", -1)), "N3③：激活后 get_phase()==CONDENSE（先凝聚）")
	check_eq(bool(fx2.call("is_active")), true, "N3③：凝聚期 is_active()==true")
	check(n_unsel != null and n_unsel.visible == true,
		"N3③：凝聚期未选中体素仍可见（实体→点云面过渡，修瞬时 hide 卡顿）")
	check(n_sel != null and n_sel.visible == true, "N3③：选中格凝聚期保持可见")
	# O批等价替换（用户口径③凝聚持续 0.5s）：凝聚完成后先进 HOLD（0.5s）再入 SPREAD——
	# 原「0.35s 后即 SPREAD」时序断言废止留痕。
	await create_timer(0.35).timeout  # > CONDENSE_TIME 0.25，< 0.25+FOCUS_HOLD 0.5
	check_eq(int(fx2.call("get_phase")), int(cmap.get("PHASE_HOLD", -1)),
		"O批等价替换：凝聚完成 → HOLD 持续段（点云面稳态 0.5s）")
	check(n_unsel != null and n_unsel.visible == false,
		"N3③：凝聚完成未选中体素隐藏（点云面已接管，无空窗跳变）")
	await create_timer(0.55).timeout  # 累计 0.9 > 0.25+0.5 → 散开起步
	check_eq(int(fx2.call("get_phase")), int(cmap.get("PHASE_SPREAD", -1)), "N3③：持续完成 → SPREAD 相位")
	var sp0: float = float(_mc(fx2, "get_spread_progress", [], -1.0))
	check(sp0 >= 0.0 and sp0 < 0.35,
		"N3③：散开起点进度接近 0（N4 接力读取口；相位切换同帧已起步，实际 %.3f）" % sp0)
	check_eq(bool(_mc(fx2, "activate_channel", ["Main", [Vector3i(0, 0, 0)], built], false)), false,
		"N3③：活跃期重复 activate_channel 返回 false（幂等防重入）")
	# 点云证据链（无头读回恒 0 → 属性级：instance_count/use_colors/use_custom_data/材质）
	var mmi: MultiMeshInstance3D = _find_mmi(fx2)
	check(mmi != null and mmi.multimesh != null and int(mmi.multimesh.instance_count) == 3 * int(cmap.get("DOTS_PER_VOXEL", -1)),
		"N3③：instance_count=3格×7点=21（O批密度档；静态预生成一次性构建，实际 %s)" %
			str(int(mmi.multimesh.instance_count) if mmi != null and mmi.multimesh != null else -1))
	check(mmi != null and mmi.multimesh != null and mmi.multimesh.use_colors,
		"N3③：use_colors=true（三色逐实例前提，坑 13：先于 instance_count）")
	check(mmi != null and mmi.multimesh != null and mmi.multimesh.use_custom_data,
		"N3③：use_custom_data=true（散点方向/距离 GPU 通道，动画 uniform 驱动前提）")
	var smat: Material = mmi.material_override if mmi != null else null
	check(smat is ShaderMaterial and (smat as ShaderMaterial).shader != null \
		and (smat as ShaderMaterial).shader.code.contains("u_spread") \
		and (smat as ShaderMaterial).shader.code.contains("INSTANCE_CUSTOM"),
		"N3③：ShaderMaterial+u_spread+INSTANCE_CUSTOM（GPU/uniform 驱动，禁逐帧 CPU 重建红线）")
	# 自持数组证据链（N4 接力口：face/target 屏幕位与点数等长）
	var ch_d: Dictionary = _dict_or(fx2.get("_channels"))
	var face_a: PackedVector2Array = _dict_or(ch_d.get("Main")).get("face", PackedVector2Array()) if ch_d.get("Main") is Dictionary else PackedVector2Array()
	var tgt_a: PackedVector2Array = _dict_or(ch_d.get("Main")).get("target", PackedVector2Array()) if ch_d.get("Main") is Dictionary else PackedVector2Array()
	check(face_a.size() == 21 and tgt_a.size() == 21,
		"O批等价替换：通道自持 face/target 数组与点数等长 21（3 格×7 点；原 66=22点档废止，N4 可采样）")
	await create_timer(1.3).timeout  # > SPREAD_TIME 1.2（P批波2 散开放慢档）
	check_eq(int(fx2.call("get_phase")), int(cmap.get("PHASE_STEADY", -1)), "N3③：散开完成 → STEADY 稳态")
	check_eq(bool(fx2.call("is_active")), true, "N3③：稳态 is_active()==true")
	# 完整倒放：deactivate → RETURN（收拢→点云面→实体还原）
	fx2.call("deactivate")
	check_eq(int(fx2.call("get_phase")), int(cmap.get("PHASE_RETURN", -1)), "N3③：deactivate → RETURN 倒放相位")
	check_eq(bool(fx2.call("is_active")), false, "N3③：RETURN 期对外失活（M批等价替换留痕）")
	fx2.call("deactivate")
	check_eq(int(fx2.call("get_phase")), int(cmap.get("PHASE_RETURN", -1)), "N3③：RETURN 期重复 deactivate 幂等")
	await create_timer(0.75).timeout  # > RETURN_TIME 0.6
	check_eq(int(fx2.call("get_phase")), int(cmap.get("PHASE_IDLE", -1)), "N3③：倒放完成 → IDLE")
	check(n_unsel != null and n_unsel.visible == true, "N3③：倒放完成体素实体还原")
	var mmi2: MultiMeshInstance3D = _find_mmi(fx2)
	check(mmi2 == null or mmi2.multimesh == null, "N3③：倒放完成点云清空（无残留点阵）")
	# RETURN 期 activate=打断快进收尾后重新激活（M批语义等价保留）
	_mc(fx2, "activate_channel", ["Main", [Vector3i(0, 0, 0)], built], false)
	fx2.call("deactivate")
	check_eq(int(fx2.call("get_phase")), int(cmap.get("PHASE_RETURN", -1)), "N3③ 前置：进入 RETURN")
	check_eq(bool(_mc(fx2, "activate_channel", ["Main", [Vector3i(0, 0, 0)], built], false)), true,
		"N3③：RETURN 期 activate_channel 打断收回并重新激活（返回 true）")
	check_eq(int(fx2.call("get_phase")), int(cmap.get("PHASE_CONDENSE", -1)), "N3③：打断后回 CONDENSE 相位")
	# deactivate_immediate（成功动画入口专用）：立即复位/体素还原/点云清空，幂等
	await create_timer(0.35).timeout  # 推进到 SPREAD（体素已隐藏态）
	check(n_unsel != null and n_unsel.visible == false, "N3③ 前置：散开期体素隐藏")
	fx2.call("deactivate_immediate")
	check_eq(int(fx2.call("get_phase")), int(cmap.get("PHASE_IDLE", -1)),
		"N3③：deactivate_immediate 立即复位 IDLE（成功动画入口，_begin_success 链语义不变）")
	check(n_unsel != null and n_unsel.visible == true, "N3③：immediate 后体素立即还原")
	var mmi3: MultiMeshInstance3D = _find_mmi(fx2)
	check(mmi3 == null or mmi3.multimesh == null, "N3③：immediate 后点云清空")
	fx2.call("deactivate_immediate")
	check_eq(int(fx2.call("get_phase")), int(cmap.get("PHASE_IDLE", -1)), "N3③：deactivate_immediate 幂等不崩")
	world.queue_free()

	# ==================== E. 关卡集成：三通道同屏 + 句柄面 deactivate_immediate 链 ====================
	var inst2: Node = await _make_level(1)
	var fx3: Node = inst2.get("_fx_main")
	var mvv: Node = inst2.get_node_or_null("MainView/ViewportContainer/SubViewport/VoxelView")
	var tvv: Node = inst2.get_node_or_null("TargetView/ViewportContainer/SubViewport/VoxelView")
	var jvv: Node = inst2.get_node_or_null("JoinView/ViewportContainer/SubViewport/VoxelView")
	inst2.call("select_voxel", Vector3i(0, 0, 0), false)
	var sside: Dictionary = inst2.get("_side_selected")
	var t_cells: Array = tvv.call("get_built_cells")
	var j_cells: Array = jvv.call("get_built_cells")
	sside["Target"][t_cells[0]] = true
	sside["Join"][j_cells[0]] = true
	var rem_main: int = (inst2.call("get_remaining_voxels") as Array).size()
	var exp_dots: int = (rem_main - 1 + t_cells.size() - 1 + j_cells.size() - 1) * int(cmap.get("DOTS_PER_VOXEL", -1))
	inst2.call("_toggle_focus")
	check(bool(_mc(fx3, "is_channel_active", ["Main"], false)) and bool(_mc(fx3, "is_channel_active", ["Target"], false)) \
		and bool(_mc(fx3, "is_channel_active", ["Join"], false)),
		"N3②：_toggle_focus 三通道同权激活（三视图同时聚焦三色共存）")
	await process_frame
	var mmi4: MultiMeshInstance3D = _find_mmi(fx3)
	check(mmi4 != null and mmi4.multimesh != null and int(mmi4.multimesh.instance_count) == exp_dots,
		"N3②：三通道同屏点数=三视图未选格×7（O批密度档；单 MultiMesh 单绘制，实际 %d 期望 %d）" %
			[int(mmi4.multimesh.instance_count) if mmi4 != null and mmi4.multimesh != null else -1, exp_dots])
	# 三色证据链：自持颜色数组含金/绿/红三色（无头读回恒 0 → 生成侧属性证据）
	var cols_v: Variant = fx3.get("_mm_colors")
	var cols: PackedColorArray = cols_v if cols_v is PackedColorArray else PackedColorArray()
	var has_g := false
	var has_gn := false
	var has_r := false
	for c0: Color in cols:
		if c0.is_equal_approx(_dict_or(cmap.get("CHANNEL_COLORS")).get("Main", Color())): has_g = true
		if c0.is_equal_approx(_dict_or(cmap.get("CHANNEL_COLORS")).get("Target", Color())): has_gn = true
		if c0.is_equal_approx(_dict_or(cmap.get("CHANNEL_COLORS")).get("Join", Color())): has_r = true
	check(cols.size() == exp_dots and has_g and has_gn and has_r,
		"N3②：点色数组含金/绿/红三色（通道配色证据链，允许屏上重叠）")
	# 句柄面成功动画链：deactivate_immediate 经 _fx_main 调用立即复位（_begin_success 调用链同款）
	fx3.call("deactivate_immediate")
	check(not bool(fx3.call("is_active")) and int(fx3.call("get_phase")) == int(cmap.get("PHASE_IDLE", -1)),
		"N3③：句柄面 deactivate_immediate 立即复位（成功动画入口调用链零改动）")
	inst2.queue_free()

	# ==================== F. 批次V回修②B移交/V-C5语义对齐：关卡退出确认经 Game.confirm → 统一确认条 ====================
	# 移交留痕（批次V回修②B，原 N12b 审查 A P2-1「退出确认弹窗可见期散点层避让」）：
	# 旧 F 段读 inst4.get("_exit_dialog")（GlassDialog 实例）再 open_centered/close——V-C5（spec §3.2）
	# 已把关卡退出确认迁移 Game.confirm → TopStrip 统一确认条，场景内动态弹窗节点退役
	# （level_scene.gd :411-417 退役留痕），旧断言 null.call 挂死（本件无 finish 输出）。
	# 等价重写（test_v_confirm_migration/test_level_extra 现行为断言口径）：spy 记录 Game.confirm
	# （恰 1 条/文案逐字/双回调透传/取消零副作用/确认路由 MAIN_MENU）；FocusFX 散点层避让随弹窗
	# 退役（确认条挂独立层 63 已脱离关卡画布层域——level_scene.gd 退役留痕原文），语义对齐为
	# 「确认条挂起全程 FocusFX 可见性与聚焦态零耦合」。超时自证：本件无头跑完到 finish() 即
	# 不挂死；断言数只增不减（原 8 checks 全等价替换 + 新增 5）。
	var game_nff: Node = get_root().get_node("Game")
	ssp_nff = StripSpyNFF.new()
	add_child(ssp_nff)
	game_nff.call("attach_strip", ssp_nff)   # V-C5 注册路径（Game.confirm 委托 push_confirm）
	await process_frame
	var inst4: Node = await _make_level(1)
	inst4.call("select_voxel", Vector3i(0, 0, 0), false)
	var fx4: Node = inst4.get("_fx_main")
	inst4.call("_toggle_focus")
	check(bool(_mc(fx4, "is_channel_active", ["Main"], false)), "P2-1 前置：聚焦已激活（Main 通道活跃）")
	check(fx4 is CanvasLayer and (fx4 as CanvasLayer).visible,
		"P2-1 前置：FocusFX 全屏层在场且可见（弹窗未开时散点正常渲染）")
	check(inst4.get("_exit_dialog") == null,
		"批次V回修②B：场景内退出弹窗节点已退役（V-C5 迁移 Game.confirm——旧 null.call 挂死根因消除）")
	# 退出确认流：TopBar 退出钮 → Game.confirm（spy 恰 1 条、文案逐字、双回调透传）。
	var eb4: Button = inst4.get_node_or_null("TopBar/Buttons/ExitButton")
	check(eb4 is Button, "批次V回修②B：TopBar 退出钮在场（确认流入口）")
	var f_before: int = (ssp_nff.confirm_calls as Array).size()
	if eb4 != null:
		eb4.pressed.emit()
	var f_recs: Array = ssp_nff.confirm_calls
	check_eq(f_recs.size(), f_before + 1, "批次V回修②B：点击退出 → Game.confirm 统一确认条（恰 1 条，不直接退场）")
	var f_ok := Callable()
	var f_cancel := Callable()
	if f_recs.size() == f_before + 1:
		var f_rec: Array = f_recs[f_recs.size() - 1]
		check_eq(String(f_rec[0]), "返回主菜单？", "批次V回修②B：退出确认文案逐字「返回主菜单？」（V-C5 文案逐字保持）")
		check((f_rec[1] as Callable).is_valid(), "批次V回修②B：确认回调透传有效（挂起目标路由）")
		check((f_rec[2] as Callable).is_valid(), "批次V回修②B：取消回调透传有效（挂起路由作废语义）")
		f_ok = f_rec[1]
		f_cancel = f_rec[2]
	# 确认条挂起期间 FocusFX 零耦合（避让前提=场景内同层弹窗，已随 V-C5 退役——独立层 63 语义对齐）
	# + 聚焦态保留（原 P2-1「聚焦态保留」语义延续）。
	check(fx4 is CanvasLayer and (fx4 as CanvasLayer).visible,
		"批次V回修②B：确认条挂起全程 FocusFX 全屏层保持可见（散点层与统一确认条零耦合，避让退役）")
	check(bool(_mc(fx4, "is_channel_active", ["Main"], false)) and int(_mc(fx4, "get_phase", [], -1)) != int(cmap.get("PHASE_IDLE", -1)),
		"批次V回修②B：确认条挂起全程聚焦态保留（相位仍活跃——原「优于先退聚焦」语义延续）")
	# 取消零副作用：先取消（作废挂起路由）→ 状态机不动 → 再调确认回调亦不得路由（零副作用）。
	var st_before: int = int(game_nff.current_state())
	if f_cancel.is_valid():
		f_cancel.call()
	check_eq(int(game_nff.current_state()), st_before, "批次V回修②B：取消回调零副作用（Game 状态机不动）")
	if f_ok.is_valid():
		f_ok.call()
	check_eq(int(game_nff.current_state()), st_before, "批次V回修②B：取消后确认回调不路由（挂起已作废，一次性消费语义）")
	# 确认路由：重触发退出 → 确认回调 → Game 路由 MAIN_MENU（test_level_extra 段 11 同款现行为断言；
	# --script 模式 Game.State 触发编译级联失败——MAIN_MENU=1 字面量，test_level_extra :27 先例）。
	if eb4 != null:
		eb4.pressed.emit()
	var f_recs2: Array = ssp_nff.confirm_calls
	if f_recs2.size() == f_before + 2:
		var f_rec2: Array = f_recs2[f_recs2.size() - 1]
		check_eq(String(f_rec2[0]), "返回主菜单？", "批次V回修②B：重触发退出文案逐字（二次确认条）")
		var f_ok2: Callable = f_rec2[1]
		if f_ok2.is_valid():
			f_ok2.call()
		check_eq(int(game_nff.current_state()), 1, "批次V回修②B：确认 → Game 路由 MAIN_MENU（挂起目标路由）")
	inst4.call("_set_focus", false)  # 收尾：取消聚焦还原（体素还原由管线 RETURN 完成，测试不依赖）
	inst4.queue_free()
	game_nff.call("attach_strip", null)   # 批次V§3.2：卸下统一确认条 spy，还原 autoload 挂接态
	ssp_nff.queue_free()
	ssp_nff = null
	_cleanup_files()
	finish()
