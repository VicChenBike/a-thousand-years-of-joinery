extends "res://tests/test_base.gd"
## 批次 Z（Z-C 波，spec §5 手势域）——阈值放宽 / 翻转计数双手同翻口径 / 倒数弹条几何与
## 4.5s 停留 / 加载态动态点 四段验收断言（TDD 红测先行，红→绿证据留痕 AI工作记录）。
## 段口径（对应 spec §5 验收断言方向 ①⑤⑥⑦）：
##   段 1 常量断言：CONF_ENTER=0.55 / FLIP_ANGLE_DEG=75.0 / PALM_PUSH_RATIO=0.12 /
##      SAME_WINDOW_SEC=1.2 / CONFIRM_FRAMES=2 / CONF_EXIT<CONF_ENTER 滞后带；
##      ExitGestureTracker.TIMEOUT_SEC=4.5；加载点步进常量 0.4s、点序 3→2→1。
##   段 2 阈值行为红绿反转：conf 0.55 触发（旧 0.65 不触发=红）/ 0.54 不触发；
##      roll Δ=80° 触发翻转（旧 90° 门不触发=红）；掌推 13% 触发 zoom（旧 15% 不触发=红）。
##   段 3 翻转计数（用户拍板：双手同时翻转才算一次）：配对窗 1.2s 内双手同翻 → exit_flip
##      → Tracker 计数 -1（started(3)→changed(2)）；单侧翻 / 超窗（1.4s>1.2s）左右手交替
##      → 零 exit_flip 零计数（红测）。
##   段 4 倒数弹条几何 == 对接失败条（TopStrip）：关卡内（LEVEL）offset_top=6 贴顶栏 +
##      水平居中（anchor 0.5/对称 offsets）；非 LEVEL 维持 70；4.5s 停留带**中途帧护栏**
##      （4.4s 仍可见/未取消 → 4.6s 才取消，防空转假绿）。
##   段 5 加载态动态点：右下 GestureLoadingTip「手势交互加载中」+ 3→2→1 点循环（0.4s 步进、
##      0.39s 不推进中途帧护栏）；设置面板 CAM_OPENING_DOTS=「摄像头正在加载中」3→2→1。
## 夹具纪律：全程 headless 零真拉起；user:// 备份还原（前缀 zgt）；不触碰 9876/9878 真端口。

const MAP_PATH := "res://scripts/gesture_map.gd"
const TRACKER_PATH := "res://scripts/gesture_exit_tracker.gd"
const DIALOG_SCENE := "res://scenes/shared/gesture_exit_dialog.tscn"
const TOPSTRIP_PATH := "res://scenes/shared/top_strip.gd"
const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const MAIN_GD := "res://scenes/main.gd"
const PANEL_GD := "res://scenes/settings/settings_panel.gd"

const F_CURSOR := [0.1, 0.9, 0.1, 0.1, 0.1]
const F_FOUR := [0.1, 0.9, 0.9, 0.9, 0.9]
const F_FOLD := [0.1, 0.9, 0.1, 0.1, 0.1]
const F_REST := [0.1, 0.1, 0.1, 0.1, 0.1]

# ===== 清档纪律（test_gesture_hud 同款，前缀 zgt；main.tscn 实例化会触碰 SaveManager）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_zgt_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _pre_save_text: String = ""

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _backup_user() -> void:
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	for c: Node in root.get_children():
		if not DISC_AUTOLOADS.has(String(c.name)):
			c.free()
	for p: String in DISC_WATCHED:
		_disc_del(p)
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(_disc_abs(bk)):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(_disc_abs(bk))
	var real_sm: Node = root.get_node_or_null("SaveManager")
	if real_sm != null:
		real_sm.load_game()
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")

func _disc_del(p: String) -> void:
	var a := _disc_abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func finish() -> void:
	_restore_user()
	super.finish()

# ==================== 夹具 ====================

func _hand(fingers: Array, roll: float, label: String, ps: float, ts: float,
		conf: float = 0.9) -> Dictionary:
	var lm: Array = []
	for i: int in 21:
		lm.append([0.5, 0.5, 0.0])
	lm[0] = [0.45 if label == "Left" else 0.65, 0.6, 0.0]
	# 掌面朝镜布局：(label=="Right")==facing 时 cz>0（test_gesture_map _hand 同构，facing 恒 true）
	if label == "Right":
		lm[5] = [lm[0][0] - 0.05, lm[0][1] - 0.06, 0.0]
		lm[17] = [lm[0][0] + 0.05, lm[0][1] - 0.05, 0.0]
	else:
		lm[5] = [lm[0][0] + 0.05, lm[0][1] - 0.06, 0.0]
		lm[17] = [lm[0][0] - 0.05, lm[0][1] - 0.05, 0.0]
	lm[8] = [0.3 if label == "Left" else 0.7, 0.4, 0.0]
	lm[9] = [lm[0][0], lm[0][1] - ps, 0.0]
	return {
		"gesture": "", "gesture_id": 0, "confidence": conf,
		"hand_x": 0.3, "hand_y": 0.4, "hand_z": 0.0,
		"hand_rotation_x": roll, "hand_rotation_y": 0.0, "hand_rotation_z": 0.0,
		"fingers": fingers, "pinch_distance": 0.5,
		"hand_index": 0 if label == "Left" else 1, "handedness": label,
		"landmarks": lm, "fps": 30.0, "is_detected": true,
		"timestamp": ts, "palm_size": ps,
	}

func _types(intents: Array) -> Array:
	var out: Array = []
	for it: Variant in intents:
		if typeof(it) == TYPE_DICTIONARY:
			out.append(String(it["type"]))
	return out

func _has(intents: Array, t: String) -> bool:
	return _types(intents).has(t)

func _left(m: Variant, fingers: Array, roll: float, ts: float, ps: float = 0.2) -> Array:
	return m.feed_frame(_hand(fingers, roll, "Left", ps, ts), {}, ts)

func _both(m: Variant, lf: Array, rf: Array, lroll: float, rroll: float,
		ts: float) -> Array:
	return m.feed_frame(_hand(lf, lroll, "Left", 0.2, ts),
		_hand(rf, rroll, "Right", 0.2, ts), ts)

## 双手同帧翻转序列（批次 AA W3-2 等价改写）：旧「预热右 clear 防误窗 0.35s 后重锁再同翻」
## 随 clear 改【右】掌静止 dwell 退役——新时序 = 先收指退掌态（dwell 中止、上一轮掌态清干净）
## → 入掌双帧重锁 → 入掌 0.1s 内同帧同翻（远早于 dwell 1.0s，无 clear 干扰）。
## 返回 5 帧累计意图；t 为首帧时刻。断言载体（exit_flip 计数）不变，断言数不减。
func _pair_flip_seq(m: Variant, t: float) -> Array:
	var out: Array = []
	out.append_array(_both(m, F_REST, F_REST, 10.0, 10.0, t))            # 收指退掌态（W3-2：dwell 中止）
	out.append_array(_both(m, F_FOUR, F_FOUR, 10.0, 10.0, t + 0.033))     # 入掌 1（dwell 起算）
	out.append_array(_both(m, F_FOUR, F_FOUR, 10.0, 10.0, t + 0.066))     # 入掌 2 → 双方前置锁定
	out.append_array(_both(m, F_FOUR, F_FOUR, 130.0, 130.0, t + 0.133))   # 同帧翻转 1
	out.append_array(_both(m, F_FOUR, F_FOUR, 130.0, 130.0, t + 0.166))   # 同帧翻转 2 → exit_flip
	return out

func _wire_tracker(t: Variant) -> Array:
	var sig := [[], [], [], []]
	t.countdown_started.connect(func(r: int) -> void: sig[0].append(r))
	t.countdown_changed.connect(func(r: int) -> void: sig[1].append(r))
	t.countdown_cancelled.connect(func(r: String) -> void: sig[2].append(r))
	t.exit_confirmed.connect(func() -> void: sig[3].append(true))
	return sig

func _dot_count(s: String) -> int:
	return s.count(".")

# ==================== 段 1~2：常量与阈值行为 ====================

func _seg1_2_thresholds(m: Variant) -> void:
	var gm: Dictionary = (load(MAP_PATH) as Script).get_script_constant_map()
	check_eq(float(gm.get("CONF_ENTER", -1.0)), 0.55,
		"①：CONF_ENTER=0.55（Z5 拍板放宽；旧 0.65 退役留痕）")
	check_eq(float(gm.get("CONF_EXIT", -1.0)), 0.45, "①：CONF_EXIT=0.45 维持")
	check(float(gm.get("CONF_EXIT", 1.0)) < float(gm.get("CONF_ENTER", -1.0)),
		"①：CONF_EXIT < CONF_ENTER 滞后带保持（0.45~0.55）")
	check_eq(float(gm.get("FLIP_ANGLE_DEG", -1.0)), 75.0,
		"①：FLIP_ANGLE_DEG=75.0（旧 90.0 退役留痕）")
	check_eq(float(gm.get("PALM_PUSH_RATIO", -1.0)), 0.12,
		"①：PALM_PUSH_RATIO=0.12（旧 0.15 退役留痕）")
	check_eq(float(gm.get("SAME_WINDOW_SEC", -1.0)), 1.2,
		"①：SAME_WINDOW_SEC=1.2（双手配对窗拍板放宽；旧 0.8 退役留痕）")
	check_eq(int(gm.get("CONFIRM_FRAMES", -1)), 2, "①：CONFIRM_FRAMES=2 保持")
	var tk: Dictionary = (load(TRACKER_PATH) as Script).get_script_constant_map()
	check_eq(float(tk.get("TIMEOUT_SEC", -1.0)), 4.5,
		"⑥：倒数弹条停留 TIMEOUT_SEC=4.5（旧 3.0 退役留痕）")

	# 2a. 置信度边界：0.55 触发（旧 0.65 门=红）/ 0.54 不触发（新带下沿红锁）
	var gen := func(conf: float, ts: float) -> Array:
		return m.feed_frame(_hand(F_CURSOR, 5.0, "Left", 0.2, ts, conf), {}, ts)
	m.reset()
	check(not _has(gen.call(0.54, 5.0), "cursor_move"),
		"2a：conf=0.54<0.55 不触发光标（新滞后带下沿红锁）")
	m.reset()
	check(_has(gen.call(0.55, 6.0), "cursor_move"),
		"2a：conf=0.55 触发光标（边界含；旧 0.65 门下此处=红）")
	m.reset()
	check(not _has(gen.call(0.54, 7.0), "cursor_move"),
		"2a：conf=0.54 第二轮仍不触发（中途帧护栏：非单帧空转绿）")

	# 2b. 翻转角：roll Δ=80°∈(75,90) → 新阈值触发、旧 90° 门不触发（红绿反转锁）
	m.reset()
	_left(m, F_FOUR, 10.0, 10.0)
	_left(m, F_FOUR, 10.0, 10.033)
	_left(m, F_FOUR, 90.0, 10.10)
	_left(m, F_FOUR, 90.0, 10.133)         # Δ=80°>75° 两帧 → flip（旧 90° 门=不触发）
	var ang: Array = _left(m, F_FOLD, 5.0, 11.50)   # 1.367s>1.2s 窗闭合
	check(_has(ang, "undo"),
		"2b：roll Δ=80°（75°<Δ<90°）→ 触发翻转并解算 undo（FLIP_ANGLE 90→75 红绿反转锁）")

	# 2c. 掌推拉：13%（12%<r<15%）持续 3 帧 → zoom_begin（旧 15% 门=永不触发，红绿反转锁）
	m.reset()
	_left(m, F_FOUR, 10.0, 20.0)
	_left(m, F_FOUR, 10.0, 20.033)         # 掌态确认（基准 palm_size=0.20）
	var zc: Array = []
	for i: int in 14:
		zc.append_array(_left(m, F_FOUR, 10.0, 20.066 + 0.033 * i, 0.226))   # +13% 推近
		if _has(zc, "zoom_begin"):
			break
	check(_has(zc, "zoom_begin"),
		"2c：掌推 13%（EMA 渐近爬坡 ~10 帧过 12% 门、渐近值 13%<15% 旧门永不触发）→ zoom_begin（PALM_PUSH_RATIO 0.15→0.12 红绿反转锁）")

# ==================== 段 3：翻转计数（双手同翻才算一次） ====================

func _seg3_flip_count(m: Variant) -> void:
	var tk: Variant = load(TRACKER_PATH).new()
	# 3a. 配对窗（1.2s）内双手同翻 → exit_flip → Tracker 计数 -1（started(3)→changed(2)）
	m.reset()
	tk.reset()
	var sig: Array = _wire_tracker(tk)
	var acc: Array = []
	acc.append_array(_pair_flip_seq(m, 100.0))
	check(_has(acc, "exit_flip"), "3a：预热后双手同帧翻转 → exit_flip（双手配对语义）")
	for it: Variant in acc:
		if typeof(it) == TYPE_DICTIONARY and String(it.get("type", "")) == "exit_flip":
			tk.notify_flip(101.233)
	check_eq((sig[0] as Array).size(), 1, "3a：配对 #1 → countdown_started 恰一次")
	check_eq(int(sig[0][0]), 3, "3a：首配对 remaining=3（倒数起点）")
	# 配对 #2（同侧冷却 0.35s 已过）→ changed(2) = 计数 -1
	var acc2: Array = _pair_flip_seq(m, 103.0)
	check(_has(acc2, "exit_flip"), "3a：第二次配对 → exit_flip 再发")
	tk.notify_flip(104.233)
	check_eq((sig[1] as Array).size(), 1, "3a：配对 #2 → changed 恰一次")
	check_eq(int(sig[1][0]), 2, "3a：每配对成功数字减 1（3→2，用户拍板口径）")

	# 3b. 单侧翻（对侧全程离场）→ 零 exit_flip、零计数（红测）
	m.reset()
	var tk2: Variant = load(TRACKER_PATH).new()
	var sig2: Array = _wire_tracker(tk2)
	_left(m, F_FOUR, 10.0, 200.0)
	_left(m, F_FOUR, 10.0, 200.033)
	_left(m, F_FOUR, 130.0, 200.10)
	_left(m, F_FOUR, 130.0, 200.133)
	var single: Array = _left(m, F_FOLD, 5.0, 201.50)   # 1.367s>1.2s 窗闭合
	check(_has(single, "undo") and not _has(single, "exit_flip"),
		"3b：单侧翻 → 窗闭合解算 undo、零 exit_flip（不计数）")
	check((sig2[0] as Array).is_empty() and (sig2[1] as Array).is_empty(),
		"3b：单侧翻 → Tracker 零信号（红测：不进倒数不计数）")

	# 3c. 左右手交替但时差 1.4s>1.2s 配对窗 → 零 exit_flip、零计数（红测）
	m.reset()
	var tk3: Variant = load(TRACKER_PATH).new()
	var sig3: Array = _wire_tracker(tk3)
	var alt: Array = []
	alt.append_array(_both(m, F_FOUR, F_FOUR, 10.0, 10.0, 300.0))
	alt.append_array(_both(m, F_FOUR, F_FOUR, 10.0, 10.0, 300.033))  # 双方入掌锁定（W3-2：右 dwell 同刻起算，301.033 满 1.0s）
	# 左先翻（右保持 roll10 不翻）
	alt.append_array(_both(m, F_FOUR, F_FOUR, 130.0, 10.0, 300.10))
	alt.append_array(_both(m, F_FOUR, F_FOUR, 130.0, 10.0, 300.133))  # 左 flip@300.133
	# 窗闭合（左 pending 解算 undo）
	alt.append_array(_both(m, F_FOUR, F_FOUR, 130.0, 10.0, 301.40))   # Δ=1.267s>1.2s
	alt.append_array(_both(m, F_FOUR, F_FOUR, 130.0, 10.0, 301.433))
	# 右后翻（距左翻 1.40s>1.2s → 不配对）
	alt.append_array(_both(m, F_FOUR, F_FOUR, 130.0, 90.0, 301.50))
	alt.append_array(_both(m, F_FOUR, F_FOUR, 130.0, 90.0, 301.533))  # 右翻腕帧（W3-2：301.40 右 dwell 已 clear+防误窗 0.35s → 右翻被抑制，对照结论不变）
	check(not _has(alt, "exit_flip"),
		"3c：左右手交替时差 1.40s>1.2s 配对窗 → 零 exit_flip（红测：交替超窗不计数）")
	check(_has(alt, "undo"), "3c 前置：左翻超窗按单翻解算 undo（单翻通路保持）")
	check((sig3[0] as Array).is_empty() and (sig3[1] as Array).is_empty(),
		"3c：超窗交替 → Tracker 零信号（零计数红测）")

# ==================== 段 4：held 保态 + 弹条几何 + 4.5s 停留 ====================

func _seg4_dialog_and_hold(m: Variant) -> void:
	# 4a. held 帧（丢帧容忍窗内陈旧数据）不 teardown 翻转累计态——长 gap 后解算仍可达
	m.reset()
	_left(m, F_FOUR, 10.0, 400.0)
	_left(m, F_FOUR, 10.0, 400.033)
	_left(m, F_FOUR, 130.0, 400.10)
	_left(m, F_FOUR, 130.0, 400.133)         # flip@400.133 → pending
	for i: int in 16:
		var hh: Dictionary = _hand(F_FOUR, 130.0, "Left", 0.2, 400.2 + 0.033 * i)
		hh["held"] = true
		var ev: Array = m.feed_frame(hh, {}, 400.2 + 0.033 * i)
		if i == 0:
			check(ev.is_empty(), "4a：held 帧零语义事件（首帧抽样）")
	var after_hold: Array = _left(m, F_FOLD, 5.0, 401.60)   # hold 段后首真帧（1.467s>1.2s）
	check(_has(after_hold, "undo"),
		"4a：hold 窗内 held 帧不清翻转累计态 → 恢复后窗闭合仍解算 undo（不 teardown）")
	# 4a 反例 → 批次 AD §4.3.3 等价改写（单手翻转侧立保护）：旧口径「真离场（null）→ _teardown_side
	# 立即清空 _pending_flip → 后续窗闭合零残留 undo」。§4.3.3 有意反转：单手翻转（对侧从未在场，
	# other_recent=false）在 SAME_WINDOW_SEC(1.2s) 窗口期内**严禁清空 _pending_flip**——侧立丢帧的
	# 当帧 teardown 不再吞掉撤回意图，等待窗口自然到期由 feed_frame 的 _resolve_pending_flip 稳定
	# 解算输出 undo（单手翻转撤销 100% 可达，spec §4.3.3 根治「撤销 100% 丢失」缺陷）。
	# 旧值留痕：`check(not _has(after_null, "undo"), "4a反例：真离场 null → 累计态清零…")`。
	# 断言条数 1→2（只增不减）：①在途窗内（Δ0.067s）null 帧自身零残留解算（teardown 不抢跑解算）
	# ②超窗回归帧 → undo 照常解算（旧「清零」反置为「受保护可达」）。
	m.reset()
	_left(m, F_FOUR, 10.0, 410.0)
	_left(m, F_FOUR, 10.0, 410.033)
	_left(m, F_FOUR, 130.0, 410.10)
	_left(m, F_FOUR, 130.0, 410.133)         # flip → pending
	var drop_null: Array = m.feed_frame({}, {}, 410.20)   # 侧立丢帧（在途窗内）→ 保护不清空
	check(not _has(drop_null, "undo"),
		"4a反例·窗内：null 丢帧当帧不抢跑解算（零 undo 残留；§4.3.3 保护期语义=不清空也不提前解算）")
	var after_null: Array = _left(m, F_FOLD, 5.0, 411.60)
	check(_has(after_null, "undo"),
		"4a反例→AD §4.3.3：真离场 null 不再清零累计态 → 超窗回归帧解算 undo 可达（旧「null→累计态清零零残留」随单手翻转侧立保护反置留痕）")

	# 4b. 弹条几何 == 对接失败条（TopStrip 常量同源）
	var ts_script: GDScript = load(TOPSTRIP_PATH)
	var game: Node = get_root().get_node("Game")
	var state0: int = int(game.current_state())
	var ed: Node = (load(DIALOG_SCENE) as PackedScene).instantiate()
	add_child(ed)
	await process_frame
	await process_frame
	# LEVEL 态：贴顶栏 offset_top=6（TopStrip.LEVEL_TOP_OFFSET 同源）+ 水平居中
	game.set("_state", int(game.State.LEVEL))
	ed.call("show_countdown", 3)
	await create_timer(0.4).timeout   # 等滑入 tween（0.25s）收敛到终值再读几何（中途帧读值会偏）
	var card: Control = ed.get_node("Card") as Control
	check_eq(float(card.get("offset_top")), float(ts_script.LEVEL_TOP_OFFSET),
		"⑥：关卡内倒数弹条 offset_top==TopStrip.LEVEL_TOP_OFFSET=6（与对接失败条完全一致）")
	check(is_equal_approx(float(card.get("anchor_left")), 0.5)
			and is_equal_approx(float(card.get("offset_left")), -float(card.get("offset_right"))),
		"⑥：弹条水平居中（anchor_left=0.5 + 对称 offsets，与 TopStrip 同几何）")
	check_eq(float(card.get("anchor_top")), 0.0, "⑥：弹条顶锚（anchor_top=0，同 TopStrip）")
	# 非 LEVEL 态：维持 70（TopStrip.TOP_OFFSET 同源）
	ed.call("close_countdown")
	game.set("_state", int(game.State.MAIN_MENU))
	ed.call("show_countdown", 3)
	await create_timer(0.4).timeout
	check_eq(float(card.get("offset_top")), float(ts_script.TOP_OFFSET),
		"⑥：非关卡态弹条 offset_top==TopStrip.TOP_OFFSET=70（维持现状口径）")
	ed.call("close_countdown")
	game.set("_state", state0)   # 状态机复位

	# 4c. 4.5s 停留带中途帧护栏（防空转假绿）：4.4s 仍可见未取消 → 4.6s 才取消
	var tk: Variant = load(TRACKER_PATH).new()
	var sigc: Array = [[], [], [], []]
	var ed2: Node = (load(DIALOG_SCENE) as PackedScene).instantiate()
	add_child(ed2)
	await process_frame
	await process_frame
	tk.countdown_started.connect(func(r: int) -> void:
		sigc[0].append(r); ed2.call("show_countdown", r))
	tk.countdown_changed.connect(func(r: int) -> void: ed2.call("update_countdown", r))
	tk.countdown_cancelled.connect(func(_rs: String) -> void:
		sigc[2].append(_rs); ed2.call("close_countdown"))
	tk.exit_confirmed.connect(func() -> void: sigc[3].append(true))
	tk.notify_flip(500.0)
	check(ed2.visible, "4c 前置：首翻弹条可见")
	tk.tick(504.4, true)    # 4.4s < 4.5s
	check((sigc[2] as Array).is_empty() and ed2.visible,
		"4c 中途帧护栏：4.4s 未超时不取消、弹条仍可见（旧 3.0s 下此处必红=防空转假绿）")
	tk.tick(504.6, true)    # 4.6s > 4.5s
	check_eq((sigc[2] as Array).size(), 1, "4c：4.5s 停留到期 → cancelled 恰一次")
	check(not ed2.visible, "4c：取消后弹条收起")
	ed2.queue_free()
	ed.queue_free()
	await process_frame

# ==================== 段 5：加载态动态点 ====================

func _seg5_loading_dots() -> void:
	# 5a. 源码锚：main._process 内调用点数推进器（防「只定义不消费」空转假绿）
	var main_src := FileAccess.get_file_as_string(MAIN_GD)
	check(main_src.contains("_tick_loading_dots(delta)"),
		"5a：main._process 消费 _tick_loading_dots(delta)（读码断言）")
	# 5b. main 常量：步进 0.4s + 点序 3→2→1
	var mc: Dictionary = (load(MAIN_GD) as Script).get_script_constant_map()
	check_eq(float(mc.get("LOAD_TIP_DOTS_SEC", -1.0)), 0.4,
		"5b：右下加载点步进 LOAD_TIP_DOTS_SEC=0.4")
	var dots_v: Variant = mc.get("LOAD_TIP_DOTS", [])
	check(typeof(dots_v) == TYPE_ARRAY and (dots_v as Array).size() == 3,
		"5b：LOAD_TIP_DOTS 恰 3 档")
	if typeof(dots_v) == TYPE_ARRAY and (dots_v as Array).size() == 3:
		var dc: Array = []
		for d: Variant in dots_v:
			check(String(d).begins_with("手势交互加载中"),
				"5b：点循环文案基座=「手势交互加载中」（旧「手势交互正在加载中」退役）实际 %s" % String(d))
			dc.append(String(d).count("."))
		check_eq(dc, [3, 2, 1],
			"5b：点序 3→2→1（递减循环；正序索引推进即 3→2→1→3）")
	# 5c. 设置面板常量：同款 3→2→1、0.4s、基座「摄像头正在加载中」
	var pc: Dictionary = (load(PANEL_GD) as Script).get_script_constant_map()
	check_eq(float(pc.get("CAM_OPENING_DOTS_SEC", -1.0)), 0.4,
		"5c：设置加载点步进 CAM_OPENING_DOTS_SEC=0.4")
	var pdots: Variant = pc.get("CAM_OPENING_DOTS", [])
	check(typeof(pdots) == TYPE_ARRAY and (pdots as Array).size() == 3,
		"5c：CAM_OPENING_DOTS 恰 3 档")
	if typeof(pdots) == TYPE_ARRAY and (pdots as Array).size() == 3:
		var pdc: Array = []
		for d: Variant in pdots:
			check(String(d).begins_with("摄像头正在加载中"),
				"5c：文案基座=「摄像头正在加载中」（旧「打开中」退役）实际 %s" % String(d))
			pdc.append(String(d).count("."))
		check_eq(pdc, [3, 2, 1],
			"5c：点序 3→2→1（递减循环——实现方向确认：正序推进=3→2→1→3，非 0→1→2 递增）")
		check_eq(String(pc.get("CAM_OPENING_TEXT", "")), "摄像头正在加载中",
			"5c：CAM_OPENING_TEXT 单点常量=「摄像头正在加载中」")
	# 5d. 实例级：右下提示动态推进（0.39s 不推进中途帧 → 0.41s 推进；READY 冻结）
	var save: Variant = get_root().get_node("SaveManager")
	save.load_game()
	# AF 同步批（2026-11-01）：内存钉 gesture_input=true——main.gd `_update_loading_tip` LOADING
	# 分支有 Q3 显示层门（批次 Z 修复3：gesture_input=false → tip 恒隐+点循环不激活），用户存档
	# Q3 双关时本段「右下提示可见/点循环步进」三断言在门处恒隐（非代码回归；「手势关=零加载
	# 提示」生产语义正确，5e 段恰以该门为被测对象）。钉在本段 load_game 后同步生效（无 await
	# 隔开），不落盘；5e 段 update_settings 写入链与本钉正交，文件级由 _backup_user/_restore_user
	# 纪律兜底。
	if save is Node:
		var sm_data_5d: Dictionary = (save as Node).get("_data")
		if typeof(sm_data_5d.get("settings")) != TYPE_DICTIONARY:
			sm_data_5d["settings"] = {}
		(sm_data_5d["settings"] as Dictionary)["gesture_input"] = true
	var bridge: Variant = get_root().get_node("GestureBridge")
	bridge._set_state(0)   # LOADING 冷启动模拟
	var main: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child(main)
	await process_frame
	await process_frame
	var tip: Label = main.get_node("GlobalUI/GestureLoadingTip") as Label
	check(tip.visible, "5d：LOADING → 右下提示可见")
	var t0 := String(tip.text)
	check_eq(_dot_count(t0), 3, "5d：起点=3 点（实际「%s」）" % t0)
	main.set("_loading_dot_accum", 0.0)   # 清除挂树期间 _process 已累计的实帧 delta（夹具归零，测步进本身）
	main.call("_tick_loading_dots", 0.39)
	check_eq(String(tip.text), t0, "5d 中途帧护栏：0.39s<0.4s 不推进（防空转假绿）")
	main.call("_tick_loading_dots", 0.02)   # 累计 0.41s
	check_eq(_dot_count(String(tip.text)), 2, "5d：0.4s 步进 → 3 点推进到 2 点")
	main.call("_tick_loading_dots", 0.41)
	check_eq(_dot_count(String(tip.text)), 1, "5d：再一步进 → 2 点推进到 1 点")
	main.call("_tick_loading_dots", 0.41)
	check_eq(_dot_count(String(tip.text)), 3, "5d：1 点回卷 3 点（3→2→1→3 循环成立）")
	bridge._set_state(1)   # READY
	check(not tip.visible, "5d：READY → 提示隐藏")
	var frozen := String(tip.text)
	main.call("_tick_loading_dots", 0.8)
	check_eq(String(tip.text), frozen, "5d：READY 后点循环冻结（零推进）")
	main.queue_free()
	await process_frame

	# 5e. 修复3（批次Z走查 P2，Q3=手势关+摄像头关）：手势总开关关闭 → LOADING 也不显示
	# 右下「手势交互加载中」+点循环（Q3 boot 不 start_gesture_process，状态可滞留 LOADING，
	# 旧码无条件显示致开机右下永久点循环）。翻回手势开 → 照常显示（Z5-7 点循环零回归）。
	save.update_settings({"gesture_input": false})
	bridge._set_state(0)   # LOADING（Q3 冷启动同构）
	var main2: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child(main2)
	await process_frame
	await process_frame
	var tip2: Label = main2.get_node("GlobalUI/GestureLoadingTip") as Label
	check(not tip2.visible,
		"5e：gesture_input=false + LOADING → 右下加载提示不显示（Q3 永久点循环根修）")
	check_eq(bool(main2.get("_loading_dots_active")), false,
		"5e：手势关 → 点循环推进器不激活（零推进）")
	main2.call("_tick_loading_dots", 1.0)
	check(not tip2.visible, "5e 中途帧护栏：手势关下推进 1.0s 提示仍不现身（防空转假绿）")
	# 翻回手势开（state 仍 LOADING）→ 提示恢复 + 3 点起点（手势开启路径照常工作）
	save.update_settings({"gesture_input": true})
	check(tip2.visible, "5e：gesture_input=true + LOADING → 提示恢复显示（手势开启零回归）")
	check_eq(_dot_count(String(tip2.text)), 3, "5e：恢复即 3 点起点（实际「%s」）" % String(tip2.text))
	main2.queue_free()
	await process_frame
	bridge._set_state(1)   # 复位 READY（与 5d 收尾现场一致，供段 6 消费）

# ==================== 段 6：双手并行 GDScript 消费侧（Z5-2 补断言） ====================

func _seg6_dual_side_parallel(m: Variant, bridge: Variant) -> void:
	# 6a. 桥级：注入 python 同侧冲突修正后的双侧首帧包（左右均非 null、id/hand_index 相异、
	# handedness == MediaPipe 原始值）→ gesture_state_received 两侧均上报、id 不同。
	var got: Array = []
	var hconn := func(d: Dictionary) -> void: got.append(d)
	(bridge as Node).gesture_state_received.connect(hconn)
	var lh: Dictionary = _hand(F_CURSOR, 5.0, "Left", 0.2, 900.0)
	var rh: Dictionary = _hand(F_CURSOR, 5.0, "Right", 0.2, 900.0)
	lh["id"] = "L0"
	lh["hand_index"] = 0
	lh["handedness"] = "Left"
	rh["id"] = "R7"
	rh["hand_index"] = 1
	rh["handedness"] = "Right"
	bridge.simulate_packet(JSON.stringify({"timestamp": 900.0, "left": lh, "right": rh}))
	check_eq(got.size(), 1, "6a：首帧双侧包被桥接收（无单侧空窗丢弃）")
	if got.size() == 1:
		var d: Dictionary = got[0]
		check(typeof(d.get("left")) == TYPE_DICTIONARY and typeof(d.get("right")) == TYPE_DICTIONARY,
			"6a：首帧包两侧均非 null（两侧均上报）")
		check(String((d["left"] as Dictionary).get("id", "")) != String((d["right"] as Dictionary).get("id", "")),
			"6a：两侧 id 不同（L0≠R7，python HandTracker 稳定 id 契约透传）")
		check_eq(int((d["left"] as Dictionary).get("hand_index", -1)), 0, "6a：左手 hand_index=0")
		check_eq(int((d["right"] as Dictionary).get("hand_index", -1)), 1, "6a：右手 hand_index=1")
		check_eq(String((d["left"] as Dictionary).get("handedness", "")), "Left",
			"6a：左手 handedness 与 MediaPipe 原始值一致（透传零改判）")
		check_eq(String((d["right"] as Dictionary).get("handedness", "")), "Right",
			"6a：右手 handedness 与 MediaPipe 原始值一致（透传零改判）")
	(bridge as Node).gesture_state_received.disconnect(hconn)

	# 6b. GestureMap 级：同帧双侧首帧喂入 → 两侧即刻在场（_last_present_at 双侧同帧落位）、
	# 双侧 hand_id 各自登记且不同（消费侧无「后者覆盖前者」单侧塌缩）。
	m.reset()
	var t := 910.0
	var ev: Array = m.feed_frame(lh, rh, t)
	# m 是 GestureMap（extends RefCounted）——`m as Node` 恒为 null，曾致本段 SCRIPT ERROR 断言
	# 全数空转（假绿）；改用 Variant 直调 Object.get（批次 Z 走查修复 1 P1）。
	check_eq(float(m.get("_last_present_at")["left"]), t, "6b：首帧左手即在场（无单侧空窗）")
	check_eq(float(m.get("_last_present_at")["right"]), t, "6b：首帧右手即在场（无单侧空窗）")
	check_eq(String(m.get("_side")["left"]["hand_id"]), "L0", "6b：左手 hand_id=L0 登记")
	check_eq(String(m.get("_side")["right"]["hand_id"]), "R7", "6b：右手 hand_id=R7 登记")
	check(String(m.get("_side")["left"]["hand_id"])
			!= String(m.get("_side")["right"]["hand_id"]),
		"6b：双侧 hand_id 不同（同侧冲突修正后消费侧双轨并存）")
	var sides: Array = []
	for it: Variant in ev:
		if typeof(it) == TYPE_DICTIONARY and String(it.get("type", "")) == "cursor_move":
			sides.append(String(it.get("side", "")))
	check(sides.has("left") and sides.has("right"),
		"6b：首帧双侧 cursor_move 均发出（两侧并行上报；实际 %s）" % str(sides))

func _initialize() -> void:
	print("== test_z_gesture_thresholds ==")
	_backup_user()
	get_root().get_node("SaveManager").call("load_game")
	var m: Variant = load(MAP_PATH).new()
	# 批次 AC 4A（spec §4.6-3）：生产语义改**双手协同推拉/间距缩放**，单手掌推拉通道默认关。
	# 本件段 2c 的「单手掌推 13% → zoom_begin」阈值用例经兼容开关开启历史通道后照跑
	#（等价改写留痕：夹具与时序零变化，仅加一行开关；双手协同缩放新语义见 test_ac_batch4_gesture）。
	m.call("set_single_hand_zoom_enabled", true)
	_seg1_2_thresholds(m)
	_seg3_flip_count(m)
	await process_frame
	# 批次 AF 终审备案族（语言钉扎先例=6411fae o_catalog_shop）：autoload _ready 推迟至树激活，
	# 须等一帧后钉 zh——用户真实存档现 language=en，不钉则文案断言呈 en 态假红。
	# 编译窗安全：经节点查找而非全局名（--script 模式 autoload 全局名编译期未注册）。
	var i18n_node: Variant = get_root().get_node_or_null("I18n")
	if i18n_node != null:
		i18n_node.call("set_language", "zh")
	await _seg4_dialog_and_hold(m)
	await _seg5_loading_dots()
	_seg6_dual_side_parallel(m, get_root().get_node("GestureBridge"))
	finish()
