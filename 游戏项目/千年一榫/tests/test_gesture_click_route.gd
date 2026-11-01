extends "res://tests/test_base.gd"
## 批次 S 判定用例（S10/S11）：非关卡语义区「食指移动+中指单击」路由。
## Router 直喂（test_gesture_pointcloud_route 同款手 dict 夹具）；光标层以 MockLayer 承接合成
## 事件流水（synth_button/synth_motion/push 调用记录），断言：按下/抬起恰一次、位置=光标位、
## 0.5s 光标新鲜度门、右手静默、BOOT 静默、cloud/level 分区维持面板模型（无 click）、armed 复位。
## 无头环境：MockLayer 不经 push_input 真管线——路由决策逻辑为被测单元（GUI 真命中=窗口走查 §8-③）。

const CATALOG_SCENE := "res://scenes/catalog/catalog_scene.tscn"

var router: Variant
var game: Variant
var mock: MockLayer

class MockLayer extends CanvasLayer:
	## 合成事件流水记录（替代真光标层，路由决策单测）
	var calls: Array = []   # ["btn", pos, pressed, ctrl] / ["motion", pos] / ["push"]
	func synth_button(pos: Vector2, pressed: bool, ctrl: bool) -> InputEventMouseButton:
		calls.append(["btn", pos, pressed, ctrl])
		return InputEventMouseButton.new()
	func synth_motion(pos: Vector2) -> InputEventMouseMotion:
		calls.append(["motion", pos])
		return InputEventMouseMotion.new()
	func push(_ev: InputEvent) -> void:
		calls.append(["push"])
	func show_cursor(_side: String, _pos: Vector2) -> void:
		pass

func _btn_events(pressed: bool) -> Array:
	var out: Array = []
	for c: Variant in mock.calls:
		if c[0] == "btn" and bool(c[2]) == pressed:
			out.append(c)
	return out

func _hand(conf: float, fingers: Array, tip: Vector2) -> Dictionary:
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
		"landmarks": lm, "fps": 30.0, "is_detected": true, "timestamp": 0.0, "palm_size": 0.2}

func _feed_left(fingers: Array, tip: Vector2) -> void:
	router.feed({"left": _hand(0.9, fingers, tip), "right": null, "timestamp": 0.0})

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
const DISC_BK_PREFIX := "user://_r2b_gcr_backup_"
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
	print("EVID|user_restore|gcr|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_gesture_click_route ==")
	_backup_user()
	var save: Variant = get_root().get_node("SaveManager")
	var bridge: Variant = get_root().get_node("GestureBridge")
	game = get_root().get_node("Game")
	var p: String = ProjectSettings.globalize_path("user://save.json")
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
	save.load_game()
	bridge._set_state(1)  # READY（feed 消费前提）
	game.goto_state(game.State.MAIN_MENU)   # 语义区 none（无覆盖层）
	router = load("res://autoload/gesture_router.gd").new()
	router.name = "GestureRouterClickProbe"
	add_child(router)
	# Godot 4.7 --script 实证（gesture_bridge.get_udp_port 注记同款先例）：_initialize 阶段节点
	# 不在树内（is_inside_tree()=false，"/root/..." 绝对路径 get_node 直接报错）——先放行一帧
	# 让树激活，router._ready → _setup 才能完成 bridge/Game 信号连接（否则 _game_booting 的
	# get_node 恒 null → 恒判 BOOT 静默，S10 主链路永远打不通）。
	await process_frame
	# 环境性甄别（§1.3 并行窗口期）：树激活时 bridge._ready 才首次触发，无头 9876 被并行进程
	# 占用即置 UNAVAILABLE——headless 无真包，与被测路由决策逻辑无关；复位 READY 恢复设计前置
	# （与本测试开局 _set_state(1) 同手法，空闲环境下为 no-op）。
	bridge._set_state(1)
	router._setup()
	mock = MockLayer.new()
	add_child(mock)
	router.set_cursor_layer(mock)

	var f_cursor: Array = [0.1, 0.9, 0.1, 0.1, 0.1]
	var f_two: Array = [0.1, 0.9, 0.9, 0.1, 0.1]

	# ---- 1. S10 主链路：光标 0.3s 内伸中指 → 按下恰一次于光标位；收中指 → 抬起恰一次 ----
	_feed_left(f_cursor, Vector2(0.3, 0.4))    # 光标出现（0 帧即时，新鲜度起算）
	_feed_left(f_two, Vector2(0.3, 0.4))       # 二指第 1 帧（确认中）
	_feed_left(f_two, Vector2(0.3, 0.4))       # 第 2 帧 → two_down
	var downs: Array = _btn_events(true)
	check_eq(downs.size(), 1, "S10：中指单击 → 合成左键按下恰一次")
	if downs.size() == 1:
		check_eq(Vector2(downs[0][1]), Vector2(router.get("_last_cursor_pos")["left"]),
			"S10：按下位置=该手最近光标 content 坐标（增益后口径）")
	_feed_left(f_cursor, Vector2(0.3, 0.4))    # 收中指回光标态 → two_up
	var ups: Array = _btn_events(false)
	check_eq(ups.size(), 1, "S10：收中指 → 合成左键抬起恰一次（armed 成对）")
	check(bool(router.get("_menu_click_armed")["left"]) == false and bool(router.get("_menu_click_armed")["right"]) == false,
		"S10：抬起后 armed 复位（批次 T per-side 字典化等价改写：双侧键值逐验）")
	mock.calls.clear()

	# ---- 2. 新鲜度门：光标 >0.5s 未动 / 从无光标 → 不 arm 不合成 ----
	# 批次 AD（§4.1.1）等价改写留痕：AD 起「只要检出有效手，每帧恒发 cursor_move」——经
	# **map→router 链路**已不可能构造出「正在跟踪却光标陈旧」的形态（每帧刷新，门恒真），
	# 故原夹具在同一链路上不可达。新鲜度门本身仍是 Router 侧的**纵深防御**（桥重启/丢包
	# 空窗等 `_last_cursor_at` 陈旧形态），故改在 **Router 层直注** 该门被测对象：
	# `_dispatch` 直喂 two_down（带 confirm_frames=2 过 T5 稳定门），以 `_last_cursor_at`
	# 的陈旧/新鲜两态做**红绿双锚**——判据从「经 map 间接触发」改为「直击门本体」，
	# 覆盖不减且新增阳性对照（防门恒真/恒假的空转绿）。
	var mp2: Variant = router.get("_map")
	var two_dn: Dictionary = {"type": "two_down", "side": "left",
		"pos": Vector2(0.5, 0.5), "confirm_frames": 2}
	router.set("_last_cursor_at", {"left": Time.get_ticks_msec() / 1000.0 - 0.8})  # 陈旧 > 0.5s
	router.set("_menu_click_armed", {"left": false, "right": false})
	mock.calls.clear()
	router.call("_dispatch", two_dn)
	check_eq(_btn_events(true).size(), 0,
		"S10：光标陈旧（>0.5s）时 two_down → 零事件（防陈旧坐标误点；Router 层直击门本体）")
	mock.calls.clear()
	router.set("_last_cursor_at", {})   # 该手从未出现光标
	router.set("_menu_click_armed", {"left": false, "right": false})
	router.call("_dispatch", two_dn)
	check_eq(_btn_events(true).size(), 0, "S10：该手从未出现光标 → two_down 零事件（哨兵防线）")
	mock.calls.clear()
	# 阳性对照（防「门恒假/空转绿」）：置新鲜光标 → 同一 two_down 必须 arm（恰一次）
	router.set("_last_cursor_at", {"left": Time.get_ticks_msec() / 1000.0})
	router.set("_menu_click_armed", {"left": false, "right": false})
	router.call("_dispatch", two_dn)
	check_eq(_btn_events(true).size(), 1,
		"S10 阳性对照：光标新鲜时同一 two_down 必 arm（门具判别力，非恒假空转）")
	router.set("_menu_click_armed", {"left": false, "right": false})
	router.set("_click_arm_dedup_at", -100.0)   # 阳性对照后复位互斥窗（T5 段 3 右手单击前置）
	mock.calls.clear()

	# ---- 3. T5 右手单击（批次 T 等价改写：左手限定废止，期望 0→1 反转留痕；扩展面细节归 test_t_click_expand）----
	var r_hand := _hand(0.9, f_cursor, Vector2(0.7, 0.4))
	r_hand["handedness"] = "Right"
	router.feed({"left": null, "right": r_hand, "timestamp": 0.0})
	var r_two := _hand(0.9, f_two, Vector2(0.7, 0.4))
	r_two["handedness"] = "Right"
	router.feed({"left": null, "right": r_two, "timestamp": 0.033})
	router.feed({"left": null, "right": r_two, "timestamp": 0.066})
	check_eq(_btn_events(true).size(), 1, "T5：右手主菜单伸中指 → 按下恰一次（基础门；左手限定废止——扩展面细节归 test_t_click_expand）")
	router.feed({"left": null, "right": r_hand, "timestamp": 0.099})   # 段尾补 _feed 式抬起帧（per-side armed 成对）
	mock.calls.clear()

	# ---- 4. BOOT 静默 ----
	game._state = game.State.BOOT   # 直写模拟（无头 goto_state 不切场景；test_gesture_hud 先例）
	_feed_left(f_cursor, Vector2(0.3, 0.4))
	_feed_left(f_two, Vector2(0.3, 0.4))
	_feed_left(f_two, Vector2(0.3, 0.4))
	check_eq(_btn_events(true).size(), 0, "S10：BOOT 期伸中指 → 零事件")
	game.goto_state(game.State.MAIN_MENU)
	mock.calls.clear()

	# ---- 5. LEVEL 分区维持面板模型：伸中指 → 无 click（无面板注册 → 无动作）----
	game.goto_state(game.State.LEVEL)
	_feed_left(f_cursor, Vector2(0.5, 0.5))
	_feed_left(f_two, Vector2(0.5, 0.5))
	_feed_left(f_two, Vector2(0.5, 0.5))
	check_eq(_btn_events(true).size(), 0, "S11：LEVEL 伸中指 → 无 click（批次 R 面板模型不变）")
	game.goto_state(game.State.MAIN_MENU)
	mock.calls.clear()

	# ---- 6. CATALOG（cloud）分区：点云激活/旋转，无 click ----
	var cat: Node = (load(CATALOG_SCENE) as PackedScene).instantiate()
	add_child(cat)
	await process_frame
	await process_frame
	game.goto_state(game.State.CATALOG)
	cat.call("_select_chapter", 1)
	await process_frame
	var rect: Rect2 = cat.call("gesture_panel_rect")
	var center_norm: Vector2 = rect.get_center() / get_root().get_visible_rect().size
	# 批次 AC（§4.4-2）等价改写：馈帧 tip 为**增益前**归一坐标，面板中心是**增益后** content
	# 归一——逆映射 tip=(q−(0.5,0.5))/g+(0.5,c_y)，c_y=(0.5+m)/g（旧 (0.5,0.5) 单基准随纵向
	# 中心上移退役；不改则 y 偏 +0.24 归一 → 光标落面板外，本段断言失真）。
	var gm_ck: Dictionary = load("res://scripts/gesture_map.gd").get_script_constant_map()
	var g_ck: float = float(gm_ck.get("CURSOR_GAIN", 2.5))
	var cy_ck: float = (0.5 + float(gm_ck.get("CURSOR_OVERSHOOT", 0.15))) / g_ck
	var center: Vector2 = (center_norm - Vector2(0.5, 0.5)) / g_ck + Vector2(0.5, cy_ck)
	_feed_left(f_cursor, center)
	_feed_left(f_two, center)
	_feed_left(f_two, center)
	check_eq(_btn_events(true).size(), 0, "S11：CATALOG 伸中指 → 无 click（面板激活）")
	check(router.get("_active_panel") == cat, "CATALOG：中指仍走面板激活（批次 R 模型不变）")
	cat.queue_free()
	game.goto_state(game.State.MAIN_MENU)
	await process_frame

	# ---- 7. reset_runtime 清 armed（批次 W P1-8a 等价改写：旧 S10/S16「抬起不再合成」口径
	# 随「虚拟键卡死」缺陷退役——新契约=清零前补合成抬起恰一次，抬起位=armed 记位）----
	_feed_left(f_cursor, Vector2(0.3, 0.4))
	_feed_left(f_two, Vector2(0.3, 0.4))
	_feed_left(f_two, Vector2(0.3, 0.4))   # armed（按下已合成）
	mock.calls.clear()
	router.reset_runtime()
	check_eq(_btn_events(false).size(), 1,
		"P1-8a 等价改写（批次 W）：reset_runtime 清 armed → 合成抬起恰一次（左键不再卡死）")
	_feed_left(f_cursor, Vector2(0.3, 0.4))  # 收中指 → two_up
	check_eq(_btn_events(false).size(), 1, "S10/S16 等价改写：复位后 two_up 不再追加抬起（armed 已清，恰一次保持）")

	# ---- 8. S10 回修（批次 S 窗口走查 m04 NG 实证，探针双手/单手对照复现）：armed 窗口内
	# 对侧手 cursor_move 不再推 synth_motion——对侧 rect 外 motion 会把真 BaseButton 的
	# pressuring_inside 打掉（合成按下被取消），双手同可见时中指单击必失败。----
	var r_hand2: Dictionary = _hand(0.9, f_cursor, Vector2(0.7, 0.4))
	r_hand2["handedness"] = "Right"
	_feed_left(f_cursor, Vector2(0.3, 0.4))
	router.feed({"left": _hand(0.9, f_cursor, Vector2(0.3, 0.4)), "right": r_hand2, "timestamp": 0.0})
	_feed_left(f_two, Vector2(0.3, 0.4))
	_feed_left(f_two, Vector2(0.3, 0.4))   # armed（按下已合成）
	check(bool(router.get("_menu_click_armed")["left"]), "S10 回修前置：双手同喂下左 armed 成立（批次 T 字典化等价改写：布尔真值对非空字典恒真，必须逐侧键值）")
	mock.calls.clear()                     # 从 armed 起观察窗口内事件
	# 终审 P1：补喂帧使断言②转真实护栏——clear 后原直接计数=遍历空数组恒 0（删守卫仍全绿）；
	# 补喂双手帧：左手 f_two 维持 armed 段（f_cursor 会先 two_up 令 armed 失效），对侧右手
	# cursor_move 若无 armed 守卫即被记为 motion → motions_in_armed>0 必红。
	router.feed({"left": _hand(0.9, f_two, Vector2(0.3, 0.4)), "right": r_hand2, "timestamp": 0.099})
	var motions_in_armed: int = 0
	for c: Variant in mock.calls:
		if c[0] == "motion":
			motions_in_armed += 1
	check_eq(motions_in_armed, 0, "S10 回修：armed 窗口内对侧手 cursor_move 不推 synth_motion（真按钮按下不被打断）")
	_feed_left(f_cursor, Vector2(0.3, 0.4))   # 收中指 → 抬起
	check_eq(_btn_events(false).size(), 1, "S10 回修：armed 后收中指仍恰一次合成抬起（成对不回归）")
	mock.calls.clear()

	finish()
