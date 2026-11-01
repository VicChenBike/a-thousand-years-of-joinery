extends "res://tests/test_base.gd"
## 批次 T 判定用例（T-C 域）：T6 tip 三源锁死 / T8 增益 / T9 置信度 /
## T7 死区（Godot 消费侧 jitter 路由）+ EMA 兜底收敛 + T10 供件 set_ring_color。
## 夹具沿用 test_gesture_map 手 dict 生成器；Router 级断言用 MockLayer（click_route 同款）。
## 批次 V §5 等价替换留痕：增益 2.5→3.5、置信度 0.60→0.65（受影响断言逐条同位替换，只增不减）。

const F_CURSOR := [0.1, 0.9, 0.1, 0.1, 0.1]
const F_TWO := [0.1, 0.9, 0.9, 0.1, 0.1]

var m: Variant
var router: Variant
var mock: MockLayer

class MockLayer extends CanvasLayer:
	var calls: Array = []
	func synth_button(pos: Vector2, pressed: bool, ctrl: bool) -> InputEventMouseButton:
		calls.append(["btn", pos, pressed, ctrl])
		return InputEventMouseButton.new()
	func synth_motion(pos: Vector2) -> InputEventMouseMotion:
		calls.append(["motion", pos])
		return InputEventMouseMotion.new()
	func push(_ev: InputEvent) -> void:
		calls.append(["push"])
	func show_cursor(_side: String, _pos: Vector2) -> void:
		calls.append(["show"])   # 批次 AC 4B：光标圈自绘刷新计数（空闲 cursor_move 视觉零回归锚）
	# 批次 W（N15 等价改写，拍板 10）：环色 mock 定义随琥珀环 API 删除整体退役（光标恒手别色）

func _hand(conf: float, fingers: Array, tip: Vector2, ts: float) -> Dictionary:
	var lm: Array = []
	for i: int in 21:
		lm.append([0.5, 0.5, 0.0])
	lm[0] = [tip.x - 0.05, tip.y + 0.2, 0.0]
	lm[5] = [lm[0][0] + 0.05, lm[0][1] - 0.06, 0.0]   # 左掌面朝镜
	lm[17] = [lm[0][0] - 0.05, lm[0][1] - 0.05, 0.0]
	lm[8] = [tip.x, tip.y, 0.0]
	lm[9] = [lm[0][0], lm[0][1] - 0.2, 0.0]
	return {"gesture": "", "gesture_id": 0, "confidence": conf,
		"hand_x": 0.5, "hand_y": 0.5, "hand_z": 0.0,
		"hand_rotation_x": 5.0, "hand_rotation_y": 0.0, "hand_rotation_z": 0.0,
		"fingers": fingers, "pinch_distance": 0.5, "hand_index": 0, "handedness": "Left",
		"landmarks": lm, "fps": 30.0, "is_detected": true, "timestamp": ts, "palm_size": 0.2}

func _feed_left(conf: float, fingers: Array, tip: Vector2, now: float) -> Array:
	return m.feed_frame(_hand(conf, fingers, tip, now), {}, now)

func _first_pos(intents: Array) -> Vector2:
	for it: Variant in intents:
		if String(it["type"]) == "cursor_move":
			return Vector2(it["pos"])
	return Vector2(-9.0, -9.0)

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
const DISC_BK_PREFIX := "user://_r2b_tcf_backup_"
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
	print("EVID|user_restore|tcf|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_t_cursor_filter ==")
	_backup_user()
	m = load("res://scripts/gesture_map.gd").new()
	var gm: Dictionary = (load("res://scripts/gesture_map.gd") as Script).get_script_constant_map()
	# 批次 AA（W2-2/3/1）等价替换留痕：CURSOR_GAIN 3.5→2.5、CURSOR_DEADZONE 0.0035→0.0015、
	# EMA_FALLBACK_BASE/FAST（死代码双档）→ CURSOR_EMA_ALPHA 单系数（spec §5.3/§15#3~#5）。
	check_eq(float(gm.get("CURSOR_GAIN", -1.0)), 2.5, "W2-2：CURSOR_GAIN=2.5（3.5→2.5 降增益；旧值留痕：3.5=批次V、2.5=批次T、2.0=批次S；暂定值·待用户复验）")
	check_eq(float(gm.get("CONF_ENTER", -1.0)), 0.55, "Z5：CONF_ENTER=0.55（拍板放宽；等价替换留痕：旧 0.65=批次V，更旧 0.60/0.55；滞后带 0.45~0.55）")
	check_eq(float(gm.get("CONF_EXIT", -1.0)), 0.45, "T9：CONF_EXIT=0.45（旧 0.40 等价替换）")
	# 批次 AD（§4.1.2）等价改写留痕：CURSOR_DEADZONE 0.0015→0.0003、CURSOR_EMA_ALPHA
	# 0.60→1.0=直通（GDScript 二级低通退役，只依赖 Python 端 One Euro + LandmarkSmoother）。
	# 断言强度保持：常量登记值仍逐一锁死（防单侧偷改）；下方首帧直通/阶跃收敛/死区三组行为
	# 断言的期望值全部由 live 常量推导，随新值**自动等价平移**（不硬编码旧 α/旧死区）。
	check_eq(float(gm.get("CURSOR_DEADZONE", -1.0)), 0.0003, "AD §4.1.2：CURSOR_DEADZONE 0.0015→0.0003（1152 折约 0.35px 仅滤硬件微噪；旧 0.0015=批次 AA W2-3、0.0035=批次 T 留痕）")
	check_eq(float(gm.get("CURSOR_EMA_ALPHA", -1.0)), 1.0, "AD §4.1.2：CURSOR_EMA_ALPHA 0.60→1.0=直通（GDScript 二级低通退役；旧 0.60=批次 AC §4.3-2、0.35=批次 AA W2-1 留痕）")
	check(not gm.has("EMA_FALLBACK_BASE"), "W2-1：EMA_FALLBACK_BASE 已退役（死代码双档→单系数统一路径留痕）")
	check(not gm.has("EMA_FALLBACK_FAST"), "W2-1：EMA_FALLBACK_FAST 已退役（死代码双档→单系数统一路径留痕）")
	# ---- 1. T6 三源优先级（4 checks；批次 AA W2-1/W2-2 连带改写：①二级 EMA 首帧直通语义
	# 要求本帧为 reset 后首帧（旧 filtered 无平滑、重喂即直出，新增平滑后需 reset 才等价）；
	# ②期望值随 gain 2.5 等价平移（3.5 时 (0.22,0.78)、批次 T 2.5 时代 (0.3,0.7) 复归）----
	m.reset()
	var r1: Array = _feed_left(0.9, F_CURSOR, Vector2(0.4, 0.6), 1.0)
	var h1: Dictionary = _hand(0.9, F_CURSOR, Vector2(0.4, 0.6), 1.0)
	# 批次 AC（§4.4-2）：纵向基准上移 c_y → 采样 tip_y 取 0.28（映射 y=(0.28−0.26)×2.5+0.5=0.55，
	# 与 lm[8]=(0.4,0.6) 的映射 (0.25,1.15) 两轴均可区分，判据判别力不减）。
	h1["tip_x"] = 0.42
	h1["tip_y"] = 0.28
	m.reset()   # W2-1：二级 EMA 存在 → 重喂帧须为首帧（首帧直通）才等价于旧「重喂即直出」
	r1 = m.feed_frame(h1, {}, 1.0)   # 同帧带 tip_x/tip_y 重喂（reset 后首帧）
	check(bool(_first_pos(r1).is_equal_approx(Vector2(0.3, 0.55))),
		"T6：tip_x/tip_y 最高优先（(0.42,0.28)→增益(0.3,0.55)，lm[8]=(0.4,0.6) 不被采用；AC 纵向基准 c_y 等价值；批次 AA 增益 2.5 平移留痕）")
	m.reset()
	var r2: Array = _feed_left(0.9, F_CURSOR, Vector2(0.1, 0.9), 2.0)
	check(bool(_first_pos(r2).is_equal_approx(Vector2(-0.15, 1.15))),
		"T6：无 tip 字段 → lm[8] 次之（(0.1,0.9)→增益钳制(−0.15,1.15)≠掌心(0.5,0.5)，断言锁死；旧 V「钳(0,1)」等价改写=批次X规格§3）")
	var r3: Array = _feed_left(0.9, F_CURSOR, Vector2(0.1, 0.9), 2.033)
	var h3: Dictionary = _hand(0.9, F_CURSOR, Vector2(0.1, 0.9), 2.033)
	h3["landmarks"] = []      # landmarks 异常缺失
	r3 = m.feed_frame(h3, {}, 2.033)
	check(bool(_first_pos(r3).is_equal_approx(Vector2(-0.15, 1.15))),
		"T6：landmarks 缺失 → 保持该手上帧 tip（永不跳掌心，hand_x/y=(0.5,0.5) 不污染；旧「钳(0,1)」等价改写=批次X规格§3）")
	m.reset()
	var h4: Dictionary = _hand(0.9, F_CURSOR, Vector2(0.1, 0.9), 3.0)
	h4["landmarks"] = []
	var r4: Array = m.feed_frame(h4, {}, 3.0)
	# 批次 AC（§4.4-2）：无缓存回落 (0.5,0.5) 经**新纵向基准** c_y=0.26 → content y=1.10
	# （旧 0.5 随中心上移退役留痕；x 轴仍为 0.5 不动点）。
	check(bool(_first_pos(r4).is_equal_approx(Vector2(0.5, 1.10))),
		"T6：首帧缺失且无缓存 → 回落 (0.5,0.5) 归一（仅首帧一次，spec §4-6-风险；AC：经新基准映射到 content (0.5,1.10)，旧 (0.5,0.5) 留痕）")
	# ---- 2. T8 增益三点（raw landmark 路径，首帧直达无 EMA 干扰；批次 AA W2-2 采样点随
	# gain 2.5 等价平移；**批次 AC §4.4-2 再平移**：纵向基准上移 c_y=0.26——
	# 「中心不动点」采样点由 (0.5,0.5) 改为 (0.5,c_y)，钳制域三点语义（钳 −0.15 / 不动点 /
	# 钳 1.15）逐条保持）----
	var cy_t := (0.5 + float(gm.get("CURSOR_OVERSHOOT", 0.15))) / float(gm.get("CURSOR_GAIN", 2.5))
	m.reset()
	var t1: Vector2 = _first_pos(_feed_left(0.9, F_CURSOR, Vector2(0.2, 0.0), 10.0))
	check(bool(t1.is_equal_approx(Vector2(-0.15, -0.15))), "T8：(0.2,0.0)→(−0.15,−0.15)（增益 2.5 下 x 0.2<0.3、y 0.0<c_y−0.2 触下缘钳，屏幕左上角余量带可达=overshoot 语义；AC 纵向采样点随 c_y 平移）")
	m.reset()
	var t2: Vector2 = _first_pos(_feed_left(0.9, F_CURSOR, Vector2(0.5, cy_t), 10.033))
	check(bool(t2.is_equal_approx(Vector2(0.5, 0.5))), "AC §4.4-2：新不动点 (0.5,c_y=%.2f)→(0.5,0.5)（旧 (0.5,0.5) 不动点随纵向中心上移退役留痕）" % cy_t)
	m.reset()
	var t3: Vector2 = _first_pos(_feed_left(0.9, F_CURSOR, Vector2(0.8, 0.52), 10.066))
	check(bool(t3.is_equal_approx(Vector2(1.15, 1.15))), "T8：(0.8,0.52)→(1.15,1.15)（增益 2.5 下 x 0.8>0.7、y 0.52>框底触上缘钳 1.15；AC 纵向采样点=2c_y 平移留痕）")
	# ---- 3. T9 置信度（3 checks；0.57 反转主用例归 test_gesture_map 段 3，此处守边界；批次 V §5.3
	# 等价替换留痕：边界对 0.60/0.59 → 0.65/0.64 → 批次 Z Z5 再平移 0.55/0.54）----
	m.reset()
	check(_first_pos(_feed_left(0.55, F_CURSOR, Vector2(0.4, 0.6), 20.0)) != Vector2(-9, -9),
		"T9：conf=0.55 触发光标（Z5 边界含；旧 0.65 等价平移留痕）")
	m.reset()
	check(_first_pos(_feed_left(0.54, F_CURSOR, Vector2(0.4, 0.6), 20.0)) == Vector2(-9, -9),
		"T9：conf=0.54<0.55 不触发（Z5 新带下沿；旧 0.64<0.65 等价平移留痕）")
	m.reset()
	_feed_left(0.9, F_CURSOR, Vector2(0.4, 0.6), 21.0)
	check(_first_pos(_feed_left(0.44, F_CURSOR, Vector2(0.4, 0.6), 21.033)) == Vector2(-9, -9),
		"T9：conf=0.44<0.45 已进入态回落（滞后带 [0.45,0.55) 维持）")
	# ---- 4. T7 EMA 兜底收敛（raw 路径，2 checks）----
	m.reset()
	var h50: Dictionary = _hand(0.9, F_CURSOR, Vector2(0.2, 0.0), 30.0)
	h50["landmarks"][8] = [0.2, 0.0, 0.0]
	m.feed_frame(h50, {}, 30.0)   # 首帧直达 (0.2,0.0)
	var conv := Vector2(-9, -9)
	for i: int in 30:
		var hi: Dictionary = _hand(0.9, F_CURSOR, Vector2(0.8, 0.52), 30.033 + 0.033 * i)
		conv = _first_pos(m.feed_frame(hi, {}, 30.033 + 0.033 * i))
	# 偏离 D2 留痕（plan §5 TC-1 甄别报告）：_first_pos 取的是 cursor_move 的 pos=增益后坐标。
	# 批次 X overshoot 钳界 [−0.15,1.15]；批次 AC §4.4-2 纵向基准上移 c_y → raw y=0.52 映射到
	# 1.15（上缘），raw y=0.0 映射到 −0.15（下缘）——两轴目标由 (±0.15) 角点给出（同位等价改写）。
	check(bool(conv.distance_to(Vector2(1.15, 1.15)) < 0.02),
		"T7：阶跃后 30 帧收敛到 (1.15,1.15)（AC：源 (0.8,0.52) 双轴触上缘钳；二级 EMA α0.60 + 死区地板 0.0015 归一×增益 2.5≈0.00375 content；W2-1 α0.35 与 (1.15,−0.15) 旧采样留痕）")
	var lag := _first_pos(_feed_left(0.9, F_CURSOR, Vector2(0.2, 0.8), 31.0))
	check(bool(lag.distance_to(Vector2(0.2, 0.2)) > 0.02),
		"T7：二级 EMA 首帧滞后于目标（低通语义在，非直通；批次 AA W2-1 统一两源单 α 后滤波路径同款）")
	# ---- 5. T7 死区（Router 级，5 checks；偏离 D0 留痕：plan 代码块头注「4 checks」与 plan 自身
	# 计数对账「段 5=5、总计 26」矛盾，按对账口径写 5——仅注释更正）----
	var save: Variant = get_root().get_node("SaveManager")
	var bridge: Variant = get_root().get_node("GestureBridge")
	var game: Variant = get_root().get_node("Game")
	var p: String = ProjectSettings.globalize_path("user://save.json")
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
	save.load_game()
	bridge._set_state(1)
	game.goto_state(game.State.MAIN_MENU)
	router = load("res://autoload/gesture_router.gd").new()
	add_child(router)
	await process_frame
	bridge._set_state(1)
	router._setup()
	mock = MockLayer.new()
	add_child(mock)
	router.set_cursor_layer(mock)
	m.reset()
	# 死区内微抖（Δ≈0.0006 < 0.0035）：motion 不推但新鲜度存活
	# 批次 AD（§4.1.2）等价改写：死区 0.0015→0.0003 后，原位移 0.0006 **越阈**（不再是死区帧）
	# ——采样位移随新死区等比收窄（取 0.4× 死区）以保「死区内锁定」判据判别力；断言语义零变化。
	var dz_t: float = float(gm.get("CURSOR_DEADZONE", 0.0003))
	var jd := _hand(0.9, F_CURSOR, Vector2(0.3, 0.4), 40.0)
	jd["tip_x"] = 0.3
	jd["tip_y"] = 0.4
	var j1: Array = m.feed_frame(jd, {}, 40.0)
	check(bool(int(j1[0].get("jitter", 1)) == 0), "T7：首帧无上一帧 → jitter=false")
	var jd2: Dictionary = _hand(0.9, F_CURSOR, Vector2(0.3, 0.4), 40.033)
	jd2["tip_x"] = 0.3 + dz_t * 0.4
	jd2["tip_y"] = 0.4 + dz_t * 0.4
	var j2: Array = m.feed_frame(jd2, {}, 40.033)
	check(bool(bool(j2[0]["jitter"]) == true),
		"T7：帧间位移 0.4×死区（%.5f < %.4f）→ jitter=true（AD 死区收窄后采样等比收窄，判据语义不变）" % [dz_t * 0.4, dz_t])
	# 偏离 D3① 留痕（plan §5 TC-1 甄别报告）：Router 内部 _map 为独立实例，从未见过 jd 基准帧，
	# jd2 对 Router 是首帧 → jitter=false，死区断言空转。此处先喂 jd 使 jd2 成为 Router 级真
	# jitter 帧（Δ0.00085<0.0035）；该喂帧产生的 motion 在 clear 之前、不计入后续计数。
	# 注意：jitter=true 不推 synth_motion 的 Router 侧守卫属 T-D 域（gesture_router.gd 本域禁触），
	# 该 check 现状红=待 T-D 落 spec §4-7 守卫后转绿（甄别报告 D3②，已上报主会话裁决）。
	router.feed({"left": jd, "right": null, "timestamp": 0.0})
	mock.calls.clear()
	router.feed({"left": jd2, "right": null, "timestamp": 0.0})
	var motions := 0
	for c: Variant in mock.calls:
		if c[0] == "motion":
			motions += 1
	check_eq(motions, 0, "T7：死区帧 Router 不推 synth_motion（光标圈 show_cursor 同位刷新无害）")
	var f_two_l: Dictionary = _hand(0.9, F_TWO, Vector2(0.3, 0.4), 40.066)
	f_two_l["tip_x"] = 0.3
	f_two_l["tip_y"] = 0.4
	router.feed({"left": f_two_l, "right": null, "timestamp": 0.0})
	var f_two_l2: Dictionary = _hand(0.9, F_TWO, Vector2(0.3, 0.4), 40.099)
	f_two_l2["tip_x"] = 0.3
	f_two_l2["tip_y"] = 0.4
	router.feed({"left": f_two_l2, "right": null, "timestamp": 0.0})
	var downs := 0
	for c: Variant in mock.calls:
		if c[0] == "btn" and bool(c[2]):
			downs += 1
	check_eq(downs, 1, "T7：死区期新鲜度照刷 → 中指单击仍成立（按下恰一次，死区不误杀新鲜度门）")
	mock.calls.clear()
	# 死区外正常移动 → **批次 AD §4.3.5 等价改写（悬停光晕恢复）**：真实物理鼠标静止时，
	# 空闲巡航 cursor_move **恢复**向视口下发轻量 synth_motion（点亮 hover_glow），
	# 键鼠焦点归还物理鼠标的隔离由 `not _real_mouse_recent()`（1.5s 让位窗）+ armed/jitter/物理按压门
	# 保证（本段已置 _last_real_mouse_time=-1.0e9 = 鼠标静止 → 应恰推一条 motion）。
	# 旧值留痕：AC 4B §4.6-8「死区外空闲 cursor_move 零 synth_motion」随光晕恢复整体反置
	#（旧「笔画在场(_left_stroking or _right_stroking)」硬门已在 gesture_router.gd 移除，见 5f）。
	router.set("_last_cursor_at", {})
	router.set("_last_real_mouse_time", -1.0e9)   # 让位窗复位（本段零真实鼠标注入 = 鼠标静止）
	var far: Dictionary = _hand(0.9, F_CURSOR, Vector2(0.5, 0.4), 41.0)
	far["tip_x"] = 0.5
	far["tip_y"] = 0.4
	router.feed({"left": far, "right": null, "timestamp": 0.0})
	motions = 0
	var shows := 0
	for c: Variant in mock.calls:
		if c[0] == "motion":
			motions += 1
		elif c[0] == "show":
			shows += 1
	check_eq(motions, 1, "T7→AD §4.3.5：死区外（Δ0.2）空闲巡航 + 物理鼠标静止 → synth_motion 恢复恰一条（悬停光晕点亮）")
	check(shows > 0, "AD §4.3.5 护栏：光标圈 show_cursor 照常刷新（视觉自绘零回归，与 synth_motion 并行）")
	# ---- 6. N15 等价改写（批次 W4 拍板 10）：T10 供件 set_ring_color/reset_ring_color 随琥珀环
	# 删除整体退役——旧 3 条环色断言等价改写为「API 不存在 + 光标环恒手别色」（3 checks 维持）----
	var layer: CanvasLayer = load("res://scripts/gesture_cursor_layer.gd").new()
	add_child(layer)
	await process_frame
	check(layer.has_method("set_ring_color") == false and layer.has_method("reset_ring_color") == false,
		"N15：set_ring_color/reset_ring_color API 已删除（琥珀环退役，拍板 10）")
	var rings: Dictionary = layer.get("_rings")
	check((rings["left"].ring_color as Color).is_equal_approx(Color("#3E7BBD")),
		"N15：左环恒手别蓝 #3E7BBD（零动态染色路径）")
	check((rings["right"].ring_color as Color).is_equal_approx(Color("#C0504D")),
		"N15：右环恒手别红 #C0504D（旧「右环同置」断言等价改写为恒色断言）")
	layer.queue_free()
	router.queue_free()
	finish()
