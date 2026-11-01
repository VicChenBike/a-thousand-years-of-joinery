extends "res://tests/test_base.gd"
## 批次 R 判定用例：点云手势路由（spec §11.1-6）。
## catalog/settle 点云注册 → 选中 → 二指拖动 rotate_by（0.25 度/像素）/ 掌推拉 zoom_by（连续
## factor）；视频态移出组后手势静默；观察类豁免 _input_locked（结算点云查看在锁定态可用 §5.7）。
## settle 段（终审 P2-1 重写）：生产 SETTLE 态=level_scene 内结算（game.gd 特判改载 level 注入
## settle:true 走边缘路径，settle_scene.gd 退役不路由）——经 Game.attach 容器 + goto_state(SETTLE)
## 真驱动 level 边缘重建，断言 level 结算 viewer 注册/契约/二指旋转（旧「直接实例化退役
## settle_scene」假绿段废止）。
## 环境说明：无头 MultiMesh 读回恒 0（坑清单 1）——catalog 断言 viewer 的 rot_y_deg/_distance、
## settle 断言 level _rev_yaw（与键鼠拖拽同一姿态写手）；Game.attach 前无头 goto_state 只改
## 状态机（坑清单 2）。
## 批次 V §5.1 等价替换留痕：CURSOR_GAIN 2.5→3.5——①位置 feed 改经 _inv_gain 增益逆映射
## （断言意图「光标落位」不变：高增益下直接喂期望位会偏出面板矩形）；②位移帧 content 换算
## 0.05×vp→0.07×vp（归一手位移 0.02×GAIN）。断言条数与强度不变，只增不减。

const CATALOG_SCENE := "res://scenes/catalog/catalog_scene.tscn"

var router: Variant
var bridge: Variant
var game: Variant
var save: Variant

func _cleanup() -> void:
	var p: String = ProjectSettings.globalize_path("user://save.json")
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)

func _vp() -> Vector2:
	return get_root().get_visible_rect().size

func _hand(conf: float, fingers: Array, tip: Vector2, ps: float, facing: bool,
		filtered: bool = false) -> Dictionary:
	var lm: Array = []
	for i: int in 21:
		lm.append([0.5, 0.5, 0.0])
	lm[0] = [tip.x - 0.05, tip.y + 0.2, 0.0]
	if facing:   # Left 掌面朝镜：cz<0（食指根在腕右上）
		lm[5] = [lm[0][0] + 0.05, lm[0][1] - 0.06, 0.0]
		lm[17] = [lm[0][0] - 0.05, lm[0][1] - 0.05, 0.0]
	else:
		lm[5] = [lm[0][0] - 0.05, lm[0][1] - 0.06, 0.0]
		lm[17] = [lm[0][0] + 0.05, lm[0][1] - 0.05, 0.0]
	lm[8] = [tip.x, tip.y, 0.0]
	lm[9] = [lm[0][0], lm[0][1] - ps, 0.0]
	var h: Dictionary = {"gesture": "", "gesture_id": 0, "confidence": conf,
		"hand_x": tip.x, "hand_y": tip.y, "hand_z": 0.0,
		"hand_rotation_x": 5.0, "hand_rotation_y": 0.0, "hand_rotation_z": 0.0,
		"fingers": fingers, "pinch_distance": 0.5, "hand_index": 0, "handedness": "Left",
		"landmarks": lm, "fps": 30.0, "is_detected": true, "timestamp": 0.0, "palm_size": ps}
	if filtered:   # 批次 T：位移帧携带 tip_x/tip_y（协议字段）走滤波直通，EMA 兜底不激活（T7）
		h["tip_x"] = tip.x
		h["tip_y"] = tip.y
	return h

func _feed(left: Dictionary) -> void:
	router.feed({"left": left, "right": null, "timestamp": 0.0})

func _inv_gain(p: Vector2) -> Vector2:
	## 批次 V §5.1 等价替换供件：期望光标位的增益逆映射（GAIN/CURSOR_OVERSHOOT 运行期读
	## gesture_map 常量）——feed 后 post-gain 光标恰落位 p，与旧 2.5 直喂的断言意图同位。
	## 批次 AC §4.4-2 等价改写：纵向基准由 0.5 上移至 c_y=(0.5+m)/g（与 apply_cursor_gain
	## 新映射严格互为反函数；旧 (0.5,0.5) 单一基准随中心上移退役留痕）。
	var gm_c: Dictionary = load("res://scripts/gesture_map.gd").get_script_constant_map()
	var g: float = float(gm_c.get("CURSOR_GAIN", 3.5))
	var cy: float = (0.5 + float(gm_c.get("CURSOR_OVERSHOOT", 0.15))) / g
	return (p - Vector2(0.5, 0.5)) / g + Vector2(0.5, cy)

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
const DISC_BK_PREFIX := "user://_r2b_gpr_backup_"
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
	print("EVID|user_restore|gpr|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_gesture_pointcloud_route ==")
	_backup_user()
	save = get_root().get_node("SaveManager")
	bridge = get_root().get_node("GestureBridge")
	game = get_root().get_node("Game")
	_cleanup()
	save.load_game()
	bridge._set_state(1)  # READY（观察类消费前提）
	game.goto_state(game.State.CATALOG)

	# ---- 1. Router 实例化（--script 模式 _ready 不触发 → 显式幂等 _setup）----
	router = load("res://autoload/gesture_router.gd").new()
	router.name = "GestureRouterProbe"
	add_child(router)
	router._setup()
	# 批次 AC 4A（spec §4.6-3）：生产语义改**双手协同推拉/间距缩放**，单手掌推拉通道默认关。
	# 本件段 3 的「单掌推拉 → zoom_by 连续 factor」存量用例经兼容开关开启历史通道后照跑
	#（等价改写留痕：夹具与断言零变化，仅加一行开关；双手协同缩放新语义见 test_ac_batch4_gesture）。
	router.get("_map").call("set_single_hand_zoom_enabled", true)

	# ---- 2. catalog 点云态注册 → 选中 → 二指旋转 rotate_by（0.25 度/像素）----
	var cat: Node = (load(CATALOG_SCENE) as PackedScene).instantiate()
	add_child(cat)
	await process_frame
	await process_frame
	cat.call("_select_chapter", 1)
	await process_frame
	check(cat.is_in_group("gesture_panel"), "catalog 点云态已注册 gesture_panel 组")
	var viewer: Control = cat.call("get_gesture_viewer")
	check(viewer != null, "catalog 面板契约 get_gesture_viewer 返回 viewer")
	var rect: Rect2 = cat.call("gesture_panel_rect")
	check(rect.size.x > 0.0 and rect.size.y > 0.0, "catalog 面板矩形有效")
	var center: Vector2 = rect.get_center() / _vp()   # 归一化光标位（面板中心）
	var f_cursor: Array = [0.1, 0.9, 0.1, 0.1, 0.1]
	var f_two: Array = [0.1, 0.9, 0.9, 0.1, 0.1]
	var f_fold: Array = [0.1, 0.9, 0.1, 0.1, 0.1]
	var f_palm: Array = [0.1, 0.9, 0.9, 0.9, 0.9]
	_feed(_hand(0.9, f_cursor, _inv_gain(center), 0.2, true))    # 光标入面板（批次 V：tip=逆增益映射）
	_feed(_hand(0.9, f_two, _inv_gain(center), 0.2, true))       # 二指第 1 帧
	_feed(_hand(0.9, f_two, _inv_gain(center), 0.2, true))       # 第 2 帧 → two_down=激活笔
	check(router.get("_active_panel") == cat, "面板中心伸中指 → catalog 激活（描边+无交互）")
	# 终审 P2-2：激活描边按面板矩形定位（catalog=center_mount 契约带，不再全屏框）
	var ring: Control = router.get("_active_ring")
	check(ring != null and is_instance_valid(ring), "激活描边节点在位（_active_ring 直引用）")
	if ring != null and is_instance_valid(ring):
		var crect: Rect2 = cat.call("gesture_panel_rect")
		var rrect: Rect2 = Rect2(ring.global_position, ring.size)
		check(absf(rrect.position.x - crect.position.x) < 1.0
			and absf(rrect.position.y - crect.position.y) < 1.0
			and absf(rrect.size.x - crect.size.x) < 1.0
			and absf(rrect.size.y - crect.size.y) < 1.0,
			"描边矩形=面板契约矩形（center_mount 带，非全屏）")
	_feed(_hand(0.9, f_fold, _inv_gain(center), 0.2, true))      # 收中指结束第一笔
	var rot0: float = float(viewer.get("rot_y_deg"))
	# 帧序偏离注记（plan 原文 two_down 落在位移位 → two_move Δ=0 恒 0 转动，红灯实锯 Δ0.000°）：
	# 2 帧确认的 two_down 位=确认帧当前 tip（gesture_map._commit_enter 取当前帧），故确认两帧
	# 同位 @center，位移只在后续 two_move 帧体现（手 Δx=0.02 归一），语义与 spec §5.7 公式对齐。
	_feed(_hand(0.9, f_two, _inv_gain(center), 0.2, true))       # 二指第 1 帧（确认起步）
	_feed(_hand(0.9, f_two, _inv_gain(center), 0.2, true))       # 第 2 帧 → two_down @center（已激活 → 进入旋转）
	_feed(_hand(0.9, f_two, _inv_gain(center) + Vector2(0.02, 0.0), 0.2, true, true))   # 位移帧（手 Δx=0.02）
	# 批次 AA（W2-1/W2-2）等价改写：①二级 EMA（α0.35）上线后单帧位移仅到位 35%（旧「批次 T
	# 滤波直通」直出语义退役）→ 连续 16 帧位移喂到收敛（0.65^16≈1.5e-5 残差 « 死区地板），
	# 逐帧 two_move 的 Δ 望远镜求和=终值−起点，累计转动与路径无关；②增益 3.5→2.5 → 归一
	# 手位移 0.02 的 content 位移 = 0.05×vp（旧 0.07×vp=0.02×3.5 留痕）；③死区 0.0015 归一
	# 的锁定地板（终值可短于目标 ≤0.0015）→ 容差改死区感知（旧 <0.001° 直出紧容差退役）。
	for i: int in 15:
		_feed(_hand(0.9, f_two, _inv_gain(center) + Vector2(0.02, 0.0), 0.2, true, true))
	var rot1: float = float(viewer.get("rot_y_deg"))
	# spec §5.7 权威公式：dx_deg = Δhand_x(归一) × 区块像素宽 × 0.25。Router 点云分支已按
	# 主会话裁决（R-E-2 上报）修正：content 像素差除回视口宽还原归一差（双重乘视口宽缺陷消除）。
	var gain_v: float = float(load("res://scripts/gesture_map.gd").get_script_constant_map().get("CURSOR_GAIN", 2.5))
	var expect_dx: float = 0.02 * gain_v * rect.size.x * 0.25
	var floor_deg: float = 0.0016 * gain_v * rect.size.x * 0.25 + 0.02
	check(absf((rot1 - rot0) - expect_dx) <= floor_deg,
		"二指拖动 → rotate_by 按 0.25 度/像素（Δ%.3f°，期望 %.3f°±%.3f 死区地板；W2 增益 2.5+EMA 收敛 16 帧）" % [rot1 - rot0, expect_dx, floor_deg])
	_feed(_hand(0.9, f_fold, _inv_gain(center) + Vector2(0.02, 0.0), 0.2, true))  # 收中指=旋转结束

	# ---- 3. 掌推拉 → zoom_by 连续 factor（§5.7 非滚轮步进）----
	var dist0: float = float(viewer.get("_distance"))
	_feed(_hand(0.9, f_palm, _inv_gain(center), 0.20, true))     # 掌态第 1 帧
	_feed(_hand(0.9, f_palm, _inv_gain(center), 0.20, true))     # 第 2 帧 → palm_begin（基准 0.20）
	_feed(_hand(0.9, f_palm, _inv_gain(center), 0.35, true))     # 推近 >15% 第 1 帧
	_feed(_hand(0.9, f_palm, _inv_gain(center), 0.35, true))     # 第 2 帧
	var z3: Dictionary = {"ok": false}
	# 第 3 帧触发 zoom_begin + zoom_factor（>15% 持续 3 帧），zoom_by 使 _distance 减小
	_feed(_hand(0.9, f_palm, _inv_gain(center), 0.35, true))
	var dist1: float = float(viewer.get("_distance"))
	check(dist1 < dist0, "掌推拉 → zoom_by 连续映射（factor>1 → 距离拉近）")
	_feed(_hand(0.9, f_fold, _inv_gain(center), 0.35, true))     # 收掌结束

	# ---- 4. 视频态移出组 → 手势静默（§11.1-6）----
	cat.call("_select_video", null)
	await process_frame
	check(not cat.is_in_group("gesture_panel"), "视频态已移出 gesture_panel 组")
	var rot2: float = float(viewer.get("rot_y_deg"))
	_feed(_hand(0.9, f_two, _inv_gain(center), 0.2, true))
	_feed(_hand(0.9, f_two, _inv_gain(center) + Vector2(0.05, 0.0), 0.2, true))
	_feed(_hand(0.9, f_two, _inv_gain(center) + Vector2(0.05, 0.0), 0.2, true))
	check(is_equal_approx(float(viewer.get("rot_y_deg")), rot2), "视频态：二指拖动不旋转（静默）")
	cat.queue_free()

	# ---- 5. settle 点云区（终审 P2-1 重写：生产路径驱动，§5.7 观察类豁免 _input_locked）----
	# Game.attach 容器后 goto_state(SETTLE) 走 game.gd 特判改载 level 场景（settle:true 边缘
	# 重建直显结算 UI）——生产 SETTLE 态的真场景就是 level，settle_scene 退役不再实例化。
	var holder := Control.new()
	get_root().add_child(holder)
	game.attach(holder, null)   # 容器在位 → _load_main_scene 真挂场景（坑清单 2 反向利用）
	game.goto_state(game.State.SETTLE, {"chapter": 1, "grade": "完美", "elapsed": 100.0, "talent": 100})
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	var lv: Node = game.get_current_scene()
	check(lv != null and lv.has_method("select_voxel"),
		"SETTLE 态生产路径=level 场景边缘重建（settle_scene 退役不再被路由）")
	check(lv != null and lv.is_in_group("gesture_panel"), "level 结算 viewer 已注册 gesture_panel 组")
	check(lv != null and lv.has_method("gesture_panel_rect") and lv.has_method("get_gesture_viewer"),
		"level 结算面板契约方法在位（gesture_panel_rect/get_gesture_viewer）")
	if lv != null and lv.has_method("gesture_panel_rect"):
		var srect: Rect2 = lv.call("gesture_panel_rect")
		var vp_sz: Vector2 = _vp()
		check(srect.size.x > 0.0 and srect.size.y > 0.0, "结算面板矩形有效")
		check(srect.position.x > 0.0 and srect.position.y > 0.0
			and srect.end.x < vp_sz.x - 1.0 and srect.end.y < vp_sz.y - 1.0,
			"结算面板矩形=建模挂载带（非全屏 get_global_rect 回退）")
		check(bool(router.call("_locked")), "生产结算边缘路径 _input_locked=true（结算页事实态）")
		var scenter: Vector2 = srect.get_center() / vp_sz
		var syaw0: float = float(lv.get("_rev_yaw"))
		_feed(_hand(0.9, f_cursor, _inv_gain(scenter), 0.2, true))
		_feed(_hand(0.9, f_two, _inv_gain(scenter), 0.2, true))
		_feed(_hand(0.9, f_two, _inv_gain(scenter), 0.2, true))     # two_down → 激活结算面板
		check(router.get("_active_panel") == lv, "挂载带中心伸中指 → level 结算面板激活")
		_feed(_hand(0.9, f_fold, _inv_gain(scenter), 0.2, true))    # 收中指结束第一笔
		_feed(_hand(0.9, f_two, _inv_gain(scenter), 0.2, true))     # 二指第 1 帧（确认起步；帧序同 catalog 段偏离注记）
		_feed(_hand(0.9, f_two, _inv_gain(scenter), 0.2, true))     # 第 2 帧 → two_down（已激活 → 进入旋转）
		_feed(_hand(0.9, f_two, _inv_gain(scenter) + Vector2(0.03, 0.0), 0.2, true))   # 位移帧（手 Δx=0.03）
		var syaw1: float = float(lv.get("_rev_yaw"))
		check(absf(syaw1 - syaw0) > 0.001, "SETTLE 态二指拖动 → rotate_by 生效（观察类豁免 _input_locked §5.7）")
	game.attach(null, null)  # 摘容器：回归无头「goto_state 只改状态机」口径（后续路由零副作用）
	game.goto_state(game.State.MAIN_MENU)
	holder.queue_free()      # level 随容器释放（_exit_tree 断点守卫按 _settled 跳过）
	_cleanup()
	finish()
