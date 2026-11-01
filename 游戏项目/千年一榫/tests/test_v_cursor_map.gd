extends "res://tests/test_base.gd"
## 批次 V-A（V11/V12，spec §5/§11/§14）：光标映射域判定用例。
## ① CURSOR_GAIN 2.5→3.5 + 映射抽纯函数 apply_cursor_gain + 四角可达（0.357/0.643→0/1、
##    0.5 不动点；−0.0005/1.0005 被 clamp 收口）；② CONF_ENTER 0.60→0.65（0.65 边界含、
##    0.64 不触发）；③ One Euro 活动期（src=="filtered"）旁路 EMA 二次平滑锁定（直喂直出）
##    + raw landmark 路径 EMA 兜底仍在的正对照；④ 中指 armed 双帧稳定：Map 层 two_down 携带
##    confirm_frames=2、单帧/不稳定序列/teardown 后单帧重入不 arm，Router 层
##    CLICK_ARM_CONFIRM_FRAMES=2 消费门（防单帧直通旁路）；⑤ 手部活动区域参考框：
##    camera_skeleton.cursor_zone_rect 纯函数（[0.5±1/(2g)]² 经 pillarbox 换算）+ 增益同源
##    map_cursor_gain()==GestureMap.CURSOR_GAIN + 琥珀 #D9A441 细线常量（绘制本身=截图走查 V12）。
## 批次 X X1（P2，spec §3）：①常量段新增 CURSOR_OVERSHOOT=0.15 锚（:146 增益锚 3.5 不动）；
## ②四角钳制断言等价改写为 overshoot 语义——钳制域 [-m,1+m]，屏幕角 0.357/0.643→−0.0005/1.0005
##    不再钳 0/1、域缘 tip=0→−0.15/1→1.15、中心不动点保持、回代行内式钳界同步扩边；
## ③参考框公式 half=(0.5+m)/g 重算（overshoot 缺省=0 旧框等价直测保留）+ map_cursor_overshoot
##    同源锚；ZONE_COLOR/ZONE_LINE_W 常量锚不动。
## 批次 AC（2026-09-27，spec §4.4 领域四）等价改写留痕：
##   · 参考框**纵向顶边贴画面顶**（y0=0.0、h=2half；旧纵向居中 [0.5±1/(2g)]² 退役）——
##     段 7「旧框等价」断言改为「顶边=内衬顶 + 归一纵向 [0, 2half]」；
##   · `apply_cursor_gain` **纵向中心基准 0.5 → c_y=(0.5+m)/gain=0.26**——「(0.5,0.5) 中心
##     不动点」退役，改为「框中心 c_y → 屏幕 0.5」新不动点；各轴角点按各自基准推导；
##   · CURSOR_EMA_ALPHA 0.35→0.60（§4.3-2）：二级 EMA 阶跃第 1 帧到位率断言 35%→60%。
## 夹具沿用 test_gesture_map / test_gesture_click_route 手 dict 生成器与 MockLayer。

var m: Variant            # GestureMap 实例
var router: Variant
var mock: MockLayer

class MockLayer extends CanvasLayer:
	## 合成事件流水记录（click_route 同款）
	var calls: Array = []
	func synth_button(_pos: Vector2, _pressed: bool, _ctrl: bool) -> InputEventMouseButton:
		calls.append(["btn"])
		return InputEventMouseButton.new()
	func synth_motion(_pos: Vector2) -> InputEventMouseMotion:
		calls.append(["motion"])
		return InputEventMouseMotion.new()
	func push(_ev: InputEvent) -> void:
		calls.append(["push"])
	func show_cursor(_side: String, _pos: Vector2) -> void:
		pass

const F_CURSOR := [0.1, 0.9, 0.1, 0.1, 0.1]
const F_TWO := [0.1, 0.9, 0.9, 0.1, 0.1]

func _hand(conf: float, fingers: Array, tip: Vector2, ts: float) -> Dictionary:
	var lm: Array = []
	for i: int in 21:
		lm.append([0.5, 0.5, 0.0])
	lm[0] = [tip.x - 0.05, tip.y + 0.2, 0.0]
	lm[5] = [lm[0][0] + 0.05, lm[0][1] - 0.06, 0.0]   # 左掌面朝镜（cz<0）
	lm[17] = [lm[0][0] - 0.05, lm[0][1] - 0.05, 0.0]
	lm[8] = [tip.x, tip.y, 0.0]
	lm[9] = [lm[0][0], lm[0][1] - 0.2, 0.0]
	return {"gesture": "", "gesture_id": 0, "confidence": conf,
		"hand_x": tip.x, "hand_y": tip.y, "hand_z": 0.0,
		"hand_rotation_x": 5.0, "hand_rotation_y": 0.0, "hand_rotation_z": 0.0,
		"fingers": fingers, "pinch_distance": 0.5, "hand_index": 0, "handedness": "Left",
		"landmarks": lm, "fps": 30.0, "is_detected": true, "timestamp": ts, "palm_size": 0.2}

func _feed_raw(conf: float, fingers: Array, tip: Vector2, now: float) -> Array:
	return m.feed_frame(_hand(conf, fingers, tip, now), {}, now)

func _feed_filtered(tip: Vector2, now: float) -> Array:
	var h := _hand(0.9, F_CURSOR, tip, now)
	h["tip_x"] = tip.x
	h["tip_y"] = tip.y
	return m.feed_frame(h, {}, now)

func _first(intents: Array, t: String) -> Dictionary:
	for it_v: Variant in intents:
		var it: Dictionary = it_v
		if String(it.get("type", "")) == t:
			return it
	return {}

func _has(intents: Array, t: String) -> bool:
	return not _first(intents, t).is_empty()

func _script_has_method(s: Variant, mname: String) -> bool:
	for md: Dictionary in (s as Script).get_script_method_list():
		if String(md.get("name", "")) == mname:
			return true
	return false

func _script_consts(s: Variant) -> Dictionary:
	return (s as Script).get_script_constant_map()

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
const DISC_BK_PREFIX := "user://_r2b_vmap_backup_"
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
	print("EVID|user_restore|vmap|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_v_cursor_map ==")
	_backup_user()
	var gm_s: Variant = load("res://scripts/gesture_map.gd")
	m = gm_s.new()
	var gm: Dictionary = _script_consts(gm_s)

	# ---- 1. 常量口径（V11/V12；批次 AA W2-2 等价平移：3.5→2.5 降增益）----
	check_eq(float(gm.get("CURSOR_GAIN", -1.0)), 2.5, "W2-2：CURSOR_GAIN=2.5（3.5→2.5 降增益；旧值留痕：3.5=批次V§5.1、2.5=批次T、2.0=批次S；暂定值·待用户复验）")
	check_eq(float(gm.get("CURSOR_OVERSHOOT", -1.0)), 0.15, "X1：CURSOR_OVERSHOOT=0.15（P2 新增；调优带 0.10~0.25 留痕=批次X规格§3）")
	check_eq(float(gm.get("CONF_ENTER", -1.0)), 0.55, "Z5：CONF_ENTER=0.55（拍板放宽；旧 0.65 等价平移留痕=批次V规格§5.3；滞后带 0.45~0.55）")
	check_eq(float(gm.get("CONF_EXIT", -1.0)), 0.45, "V11：CONF_EXIT=0.45 维持（滞后带下沿不回退）")
	check_eq(int(gm.get("CONFIRM_FRAMES", -1)), 2, "V11：CONFIRM_FRAMES=2（armed 双帧确认同源锚）")

	# ---- 2. apply_cursor_gain 纯函数 + 四角可达（V12→X1 overshoot 语义等价改写）----
	var has_gain_fn: bool = _script_has_method(gm_s, "apply_cursor_gain")
	check(has_gain_fn, "V12：gesture_map 新增 static apply_cursor_gain 纯函数（映射式抽取出供件）")
	if has_gain_fn:
		var g35 := float(gm.get("CURSOR_GAIN", 3.5))
		var mo := float(gm.get("CURSOR_OVERSHOOT", 0.15))
		# 批次 X P2（spec §3）：钳制域 [-m,1+m]——屏幕角内侧采样点映射值恰落 (−0.0005,1.0005)
		# 量级、不被硬钳（旧 V12「0.357→钳 0 / 0.643→钳 1」断言废止留痕）。
		# 批次 AA W2-2 等价平移：0.357/0.643 系 gain3.5 角点（0.5±0.5/3.5）取整，改由 **live
		# gain 推导**角点 c=0.5±0.5/g∓0.0002，任意增益下断言语义（角内可达不被钳）保持。
		# 批次 AC（§4.4-2）：纵向中心基准上移 c_y=(0.5+m)/g——横轴采样点的纵坐标取 c_y
		# （否则 y 被映射到 1.1 而非 0.5）；纵轴角点以 c_y±0.5/g 推导。
		var c_lo: float = 0.5 - 0.5 / g35 - 0.0002
		var c_hi: float = 0.5 + 0.5 / g35 + 0.0002
		var cy35: float = (0.5 + mo) / g35
		var lo := Vector2(gm_s.apply_cursor_gain(Vector2(c_lo, cy35), g35))
		check(bool(lo.is_equal_approx(Vector2(-0.0002 * g35, 0.5))), "X1：屏幕角可达 x− 角点→−0.0005 量级不钳 0（角点随 live gain 推导；旧 V12「钳 0」等价改写=批次X规格§3；AC 纵向采样基准改为 c_y）")
		var hi := Vector2(gm_s.apply_cursor_gain(Vector2(c_hi, cy35), g35))
		check(bool(hi.is_equal_approx(Vector2(1.0 + 0.0002 * g35, 0.5))), "X1：屏幕角可达 x+ 角点→1.0005 量级不钳 1（旧 V12「钳 1」等价改写=批次X规格§3）")
		var c_lo_y: float = cy35 - 0.5 / g35 - 0.0002
		var c_hi_y: float = cy35 + 0.5 / g35 + 0.0002
		var loy := Vector2(gm_s.apply_cursor_gain(Vector2(0.5, c_lo_y), g35))
		check(bool(loy.is_equal_approx(Vector2(0.5, -0.0002 * g35))), "X1：屏幕角可达 y− 角点→−0.0005 量级不钳 0（AC：角点绕新基准 c_y 推导）")
		var hiy := Vector2(gm_s.apply_cursor_gain(Vector2(0.5, c_hi_y), g35))
		check(bool(hiy.is_equal_approx(Vector2(0.5, 1.0 + 0.0002 * g35))), "X1：屏幕角可达 y+ 角点→1.0005 量级不钳 1")
		var cl := Vector2(gm_s.apply_cursor_gain(Vector2(0.0, 1.0), g35))
		check(bool(cl.is_equal_approx(Vector2(-mo, 1.0 + mo))), "X1：域缘收口 tip=(0,1)→(−m,1+m)（m=0.15 钳制域扩边；AC 中心上移后两轴仍双饱和）")
		var mid := Vector2(gm_s.apply_cursor_gain(Vector2(0.5, cy35), g35))
		check(bool(mid.is_equal_approx(Vector2(0.5, 0.5))), "AC §4.4-2：新不动点=（横 0.5, 纵 c_y=(0.5+m)/g）→ 屏幕正中 (0.5,0.5)——旧 (0.5,0.5) 不动点随纵向中心上移退役留痕")
		var old := Vector2(gm_s.apply_cursor_gain(Vector2(0.7, 0.3), 2.5))
		var manual := ((Vector2(0.7, 0.3) - Vector2(0.5, cy35)) * 2.5 + Vector2(0.5, 0.5)).clamp(Vector2(-mo, -mo), Vector2(1.0 + mo, 1.0 + mo))
		check(bool(old.is_equal_approx(manual)), "X1：纯函数与行内式回代等价（g=2.5，AC：行内式纵向基准同步为 c_y；钳界 [-m,1+m]）")
		# feed_frame 消费位同源（raw 路径首帧直达；角点随 live gain 推导，同上等价平移）
		m.reset()
		var p1 := Vector2(_first(_feed_raw(0.9, F_CURSOR, Vector2(c_hi, cy35), 70.0), "cursor_move").get("pos", Vector2(-9, -9)))
		check(bool(p1.is_equal_approx(Vector2(1.0 + 0.0002 * g35, 0.5))), "X1：feed_frame raw 角点→1.0005 量级（消费位与纯函数同源；旧 V12 x=1 等价改写）")
		m.reset()
		var p2 := Vector2(_first(_feed_raw(0.9, F_CURSOR, Vector2(c_lo, cy35), 70.033), "cursor_move").get("pos", Vector2(-9, -9)))
		check(bool(p2.is_equal_approx(Vector2(-0.0002 * g35, 0.5))), "X1：feed_frame raw 角点→−0.0005 量级（消费位与纯函数同源；旧 V12 x=0 等价改写）")

	# ---- 3. CONF_ENTER=0.55 边界（V11 → Z5 平移 0.65/0.64→0.55/0.54）----
	m.reset()
	check(not _has(_feed_raw(0.54, F_CURSOR, Vector2(0.4, 0.6), 71.0), "cursor_move"), "Z5：conf=0.54<0.55 不触发光标（旧 0.64/0.65 平移留痕）")
	m.reset()
	check(_has(_feed_raw(0.55, F_CURSOR, Vector2(0.4, 0.6), 71.033), "cursor_move"), "Z5：conf=0.55 触发光标（边界含；旧 0.65 平移留痕）")

	# ---- 4. 二级 EMA（批次 AA W2-1 等价改写：旧 V11「filtered 直喂直出（One Euro 活动期
	# 旁路 EMA）」语义随 spec §5.3 W2-1 明令「对 tip_x/tip_y 增加 α0.35 二级平滑」退役——
	# 两源（filtered/landmark）统一为同一 α 单路径；批次 AC §4.3-2 再提速 α 0.35→0.60，
	# 阶跃第 1 帧到位率断言随常量等价平移 35%→60%（期望值由 live α 推导，防双处硬编码漂移）----
	var alpha_e := float(gm.get("CURSOR_EMA_ALPHA", 0.35))
	m.reset()
	_feed_raw(0.9, F_CURSOR, Vector2(0.5, 0.5), 80.0)   # 首帧 raw 基准（直达）
	var fb := Vector2(_first(_feed_filtered(Vector2(0.58, 0.5), 80.033), "cursor_move").get("pos", Vector2(-9, -9)))
	var exp_step_x: float = 0.5 + alpha_e * 0.08   # ema 0.5→0.5+α·0.08
	var exp_content_x: float = (exp_step_x - 0.5) * float(gm.get("CURSOR_GAIN", 2.5)) + 0.5
	check(absf(fb.x - exp_content_x) < 0.001,
		"AC §4.3-2：filtered 帧二级 EMA 阶跃第 1 帧到位 %.0f%%（α=%.2f→content %.3f；W2-1 旧 α=0.35 时 0.57 留痕）" % [alpha_e * 100.0, alpha_e, exp_content_x])
	m.reset()
	_feed_raw(0.9, F_CURSOR, Vector2(0.5, 0.5), 81.0)
	var em := Vector2(_first(_feed_raw(0.9, F_CURSOR, Vector2(0.58, 0.5), 81.033), "cursor_move").get("pos", Vector2(-9, -9)))
	check(absf(em.x - fb.x) < 0.0005 and em.x < 0.78,
		"W2-1：两源统一 α 单路径——raw landmark 帧与 filtered 帧同值（旧「raw 0.696 vs filtered 直通 0.78」双轨留痕）")

	# ---- 5. 中指双帧稳定 armed·Map 层（V11）----
	m.reset()
	_feed_raw(0.9, F_CURSOR, Vector2(0.3, 0.4), 90.0)
	var single := _feed_raw(0.9, F_TWO, Vector2(0.3, 0.4), 90.033)
	check(not _has(single, "two_down"), "V11：单帧中指不稳定 → 不产生 two_down（不得 armed）")
	var second := _feed_raw(0.9, F_TWO, Vector2(0.3, 0.4), 90.066)
	var td := _first(second, "two_down")
	check(not td.is_empty() and int(td.get("confirm_frames", 0)) == 2, "V11：连续 2 帧稳定 → two_down 携带 confirm_frames=2")
	# 不稳定序列（2 帧确认被 1 帧偏离打断须重计）
	m.reset()
	_feed_raw(0.9, F_CURSOR, Vector2(0.3, 0.4), 91.0)
	_feed_raw(0.9, F_TWO, Vector2(0.3, 0.4), 91.033)    # pend=1
	_feed_raw(0.9, F_CURSOR, Vector2(0.3, 0.4), 91.066) # 偏离 → 重置
	var flip := _feed_raw(0.9, F_TWO, Vector2(0.3, 0.4), 91.099)   # pend=1 重计
	check(not _has(flip, "two_down"), "V11：不稳定序列（偏离打断）→ 重计第 1 帧不 arm")
	check(_has(_feed_raw(0.9, F_TWO, Vector2(0.3, 0.4), 91.133), "two_down"), "V11：重计满 2 连帧 → two_down（稳定语义不回退）")
	# teardown（置信度回落）后单帧重入不得 arm
	m.reset()
	_feed_raw(0.9, F_CURSOR, Vector2(0.3, 0.4), 92.0)
	_feed_raw(0.9, F_TWO, Vector2(0.3, 0.4), 92.033)
	check(_has(_feed_raw(0.9, F_TWO, Vector2(0.3, 0.4), 92.066), "two_down"), "V11：前置——two_down 正常产出")
	_feed_raw(0.40, F_TWO, Vector2(0.3, 0.4), 92.099)   # conf<CONF_EXIT → 整侧 teardown
	var re1 := _feed_raw(0.9, F_TWO, Vector2(0.3, 0.4), 92.133)
	check(not _has(re1, "two_down"), "V11：teardown 后单帧重入 → 不 arm（spec §5.3 旁路探针）")
	check(_has(_feed_raw(0.9, F_TWO, Vector2(0.3, 0.4), 92.166), "two_down"), "V11：teardown 后重计满 2 帧 → 恢复 arm")

	# ---- 6. Router CLICK_ARM_CONFIRM_FRAMES 消费门（V11；坑 5：先放行一帧再取节点）----
	var rt_s: Variant = load("res://autoload/gesture_router.gd")
	check_eq(int(_script_consts(rt_s).get("CLICK_ARM_CONFIRM_FRAMES", -1)), 2, "V11：Router 新增常量 CLICK_ARM_CONFIRM_FRAMES=2")
	var save: Variant = get_root().get_node("SaveManager")
	var bridge: Variant = get_root().get_node("GestureBridge")
	var game: Variant = get_root().get_node("Game")
	var p: String = ProjectSettings.globalize_path("user://save.json")
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
	save.load_game()
	bridge._set_state(1)
	game.goto_state(game.State.MAIN_MENU)
	router = rt_s.new()
	add_child(router)
	await process_frame
	bridge._set_state(1)
	router._setup()
	mock = MockLayer.new()
	add_child(mock)
	router.set_cursor_layer(mock)
	_feed_router_cursor()
	var down1: Dictionary = {"type": "two_down", "side": "left", "pos": Vector2(0.3, 0.4), "confirm_frames": 1}
	router.call("_on_two_down", down1)
	check(bool(router.get("_menu_click_armed")["left"]) == false, "V11：armed 消费门——confirm_frames=1 的 two_down 不 arm（单帧直通旁路封死）")
	var down0: Dictionary = {"type": "two_down", "side": "left", "pos": Vector2(0.3, 0.4)}
	router.call("_on_two_down", down0)
	check(bool(router.get("_menu_click_armed")["left"]) == false, "V11：armed 消费门——缺 confirm_frames 键（.get 缺省 0）不 arm")
	var down2: Dictionary = {"type": "two_down", "side": "left", "pos": Vector2(0.3, 0.4), "confirm_frames": 2}
	router.call("_on_two_down", down2)
	check(bool(router.get("_menu_click_armed")["left"]), "V11：confirm_frames=2 → armed 成立（四重门/互斥窗语义不回退）")
	router.call("_on_two_up", {"type": "two_up", "side": "left", "pos": Vector2(0.3, 0.4)})
	check(bool(router.get("_menu_click_armed")["left"]) == false, "V11：armed 成对释放不回退（two_up 抬起复位）")

	# ---- 7. 手部活动区域参考框（V12→X1 overshoot 改写；纯函数+同源，绘制=截图走查）----
	var sk_s: Variant = load("res://scenes/shared/camera_skeleton.gd")
	var has_zone: bool = _script_has_method(sk_s, "cursor_zone_rect")
	var has_gsrc: bool = _script_has_method(sk_s, "map_cursor_gain")
	var has_mo: bool = _script_has_method(sk_s, "map_cursor_overshoot")
	check(has_zone, "X1：camera_skeleton cursor_zone_rect 纯函数在位（增第四参 overshoot 缺省=0）")
	check(has_gsrc, "V12：camera_skeleton 新增 map_cursor_gain（增益运行期读 gesture_map 常量，零静态引用）")
	check(has_mo, "X1：camera_skeleton 新增 map_cursor_overshoot（同款零静态引用守卫读取）")
	if has_zone and has_gsrc:
		var zone_gain: float = float(sk_s.map_cursor_gain())
		check(is_equal_approx(zone_gain, float(gm.get("CURSOR_GAIN", 3.5))), "V12：参考框增益与 GestureMap.CURSOR_GAIN 同源（测试锁定）")
		if has_mo:
			check(is_equal_approx(float(sk_s.map_cursor_overshoot()), float(gm.get("CURSOR_OVERSHOOT", 0.15))),
				"X1：map_cursor_overshoot()==GestureMap.CURSOR_OVERSHOOT=0.15（同源读取测试锁定）")
		var win := Vector2(1152, 648)
		var inner: Rect2 = sk_s.pillarbox_rect(win, win)
		var lof := 0.5 - 0.5 / 3.5
		# 批次 AC（§4.4-1）等价改写：纵向顶边贴画面顶（y0=0.0、h=2half），横向保持居中——
		# 旧「纵向居中 [0.5−1/(2g), 0.5+1/(2g)]」断言随拍板退役（旧调用参数不变、几何语义更新）。
		var exp1 := Rect2(inner.position + Vector2(lof, 0.0) * inner.size, Vector2(1.0 / 3.5, 1.0 / 3.5) * inner.size)
		var got1: Rect2 = sk_s.cursor_zone_rect(win, win, 3.5)
		check(bool(got1.position.is_equal_approx(exp1.position) and got1.size.is_equal_approx(exp1.size)),
			"AC §4.4-1：参考框 overshoot 缺省=0 → 顶边贴顶 y0=0、h=1/g（满窗例 pos≈(411.4,0) size≈(329.1,185.1)；X1 纵向居中语义退役留痕）")
		var got1e: Rect2 = sk_s.cursor_zone_rect(win, win, 3.5, 0.0)
		check(bool(got1e.position.is_equal_approx(got1.position) and got1e.size.is_equal_approx(got1.size)),
			"X1：参考框 overshoot=0 显式传参 == 缺省调用（调用面零变化）")
		# X1：overshoot=0.15 → half=(0.5+m)/g=0.65/3.5≈0.1857；AC：归一 x∈[0.314,0.686]、y∈[0,0.371]
		var lon := 0.5 - 0.65 / 3.5
		var half_new := 0.65 / 3.5
		var exp1n := Rect2(inner.position + Vector2(lon, 0.0) * inner.size, Vector2(2.0 * half_new, 2.0 * half_new) * inner.size)
		var got1n: Rect2 = sk_s.cursor_zone_rect(win, win, 3.5, 0.15)
		check(bool(got1n.position.is_equal_approx(exp1n.position) and got1n.size.is_equal_approx(exp1n.size)),
			"AC §4.4-1：参考框 overshoot=0.15 → 顶边贴顶、h=2half（满窗例 pos≈(362.1,0) size≈(427.9,240.7)）")
		var nlo: Vector2 = (got1n.position - inner.position) / inner.size
		var nhi: Vector2 = (got1n.end - inner.position) / inner.size
		check(bool(absf(nlo.x - lon) < 0.0001 and absf(nlo.y) < 0.0001
			and absf(nhi.x - (0.5 + 0.65 / 3.5)) < 0.0001 and absf(nhi.y - 2.0 * half_new) < 0.0001),
			"AC §4.4-1：新框归一数值锚 x∈[0.314,0.686]、y∈[0.0,0.371]（half=0.65/3.5；旧 [0.314,0.686]² 纵向居中留痕）")
		check(bool(got1n.position.x < got1.position.x and got1n.position.y <= got1.position.y + 0.001
			and got1n.end.x > got1.end.x and got1n.end.y > got1.end.y),
			"AC §4.4-1：overshoot 扩展框在横/下三向严格外扩（顶边同贴画面顶=新几何必然结果）")
		var inner2: Rect2 = sk_s.pillarbox_rect(Vector2(320, 180), Vector2(640, 480))
		var exp2 := Rect2(inner2.position + Vector2(lof, 0.0) * inner2.size, Vector2(1.0 / 3.5, 1.0 / 3.5) * inner2.size)
		var got2: Rect2 = sk_s.cursor_zone_rect(Vector2(320, 180), Vector2(640, 480), 3.5)
		check(bool(got2.position.is_equal_approx(exp2.position) and got2.size.is_equal_approx(exp2.size)),
			"AC §4.4-1：参考框 letterbox 例顶边贴顶（内衬矩形内随增益自适应；X1 纵向居中语义退役留痕）")
		var exp2n := Rect2(inner2.position + Vector2(lon, 0.0) * inner2.size, Vector2(2.0 * half_new, 2.0 * half_new) * inner2.size)
		var got2n: Rect2 = sk_s.cursor_zone_rect(Vector2(320, 180), Vector2(640, 480), 3.5, 0.15)
		check(bool(got2n.position.is_equal_approx(exp2n.position) and got2n.size.is_equal_approx(exp2n.size)),
			"AC §4.4-1：参考框 letterbox overshoot=0.15（框随内衬自适应）")
		var fb0: Rect2 = sk_s.cursor_zone_rect(Vector2(320, 180), Vector2(640, 480), 0.0)
		check(bool(fb0.position.is_equal_approx(inner2.position) and fb0.size.is_equal_approx(inner2.size)),
			"X1：无效增益（≤0）回退整个内衬矩形（不猜值防御；V12 语义保持）")
		var fb0n: Rect2 = sk_s.cursor_zone_rect(Vector2(320, 180), Vector2(640, 480), 0.0, 0.15)
		check(bool(fb0n.position.is_equal_approx(inner2.position) and fb0n.size.is_equal_approx(inner2.size)),
			"X1：无效增益（≤0）时 overshoot 不参与（同守卫退化为旧框）")
	var skc: Dictionary = _script_consts(sk_s)
	var zc: Variant = skc.get("ZONE_COLOR", null)   # 常量表存 Color 对象本体（非字符串，坑 1：不强转）
	check(zc is Color and (zc as Color).is_equal_approx(Color("#D9A441")), "V12：参考框琥珀色常量 ZONE_COLOR=#D9A441（ORBIT 环同色）")
	check(is_equal_approx(float(skc.get("ZONE_LINE_W", -1.0)), 1.5), "V12：参考框细线常量 ZONE_LINE_W=1.5")

	finish()

func _feed_router_cursor() -> void:
	## Router 级光标新鲜度前置（click_route 段 1 同款：conf 0.9 光标帧喂入）
	router.feed({"left": _hand(0.9, F_CURSOR, Vector2(0.3, 0.4), 0.0), "right": null, "timestamp": 0.0})
