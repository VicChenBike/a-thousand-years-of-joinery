extends "res://tests/test_base.gd"
## 批次 Y（Y-A5/Y-A8/Y-A9/Y-A10，spec §2-⑤⑧⑨⑩/§3.1）：语义层消费 Y1 稳定数据——map 级红测。
##   Y-A5：held 帧（丢帧容忍窗内陈旧数据）——不触发该侧 teardown、不清翻转状态、不计为翻转、
##         计入 both_present（Router 侧）；手 id 变化=新手→该侧累计态全清（防串手污染）。
##   Y-A8：翻转冷却 1.0→0.35s（FLIP_COOLDOWN_SEC）；clear 提交独立 CLEAR_FLIP_GUARD_SEC——
##         clear 后 0.5s 真翻转仍被接受（旧 1.0s 冷却吞翻转=「翻 4 次才弹一次」主因，红测锁定）。
##   Y-A9：双手就位时差 ≤1.2s 可进入倒数（错时 0.70s 配对 exit_flip；批次 Z Z5 窗 0.8→1.2 拍板放宽，
##         旧 0.5s/0.8s 窗相继退役留痕；超窗对照 0.90s→1.30s 平移）。
##   Y-A10：诊断日志增记 roll/facing/flip_locked/flip_streak/冷却剩余/pending_flip/手 id/held/
##         丢手恢复事件（键齐全断言；向后兼容 semantic/conf/fingers/intents）。
## 手 dict 夹具=test_gesture_map 同构（含 Y1 新键 id/held）；DEBUG_LOG 起删终删（非存档）。

const F_FOUR := [0.1, 0.9, 0.9, 0.9, 0.9]
const F_FOLD := [0.1, 0.9, 0.1, 0.1, 0.1]
const F_REST := [0.1, 0.1, 0.1, 0.1, 0.1]
const DEBUG_LOG := "user://gesture_debug.log"

var m: Variant

func _hand(conf: float, fingers: Array, roll: float, facing: bool, label: String,
		ps: float, tip: Vector2, ts: float) -> Dictionary:
	var lm: Array = []
	for i: int in 21:
		lm.append([0.5, 0.5, 0.0])
	lm[0] = [tip.x - 0.05, tip.y + 0.20, 0.0]
	if (label == "Right") == facing:
		lm[5] = [lm[0][0] - 0.05, lm[0][1] - 0.06, 0.0]
		lm[17] = [lm[0][0] + 0.05, lm[0][1] - 0.05, 0.0]
	else:
		lm[5] = [lm[0][0] + 0.05, lm[0][1] - 0.06, 0.0]
		lm[17] = [lm[0][0] - 0.05, lm[0][1] - 0.05, 0.0]
	lm[8] = [tip.x, tip.y, 0.0]
	lm[9] = [lm[0][0], lm[0][1] - ps, 0.0]
	return {
		"gesture": "", "gesture_id": 0, "confidence": conf,
		"hand_x": tip.x, "hand_y": tip.y, "hand_z": 0.0,
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

func _del_debug_log() -> void:
	if FileAccess.file_exists(DEBUG_LOG):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DEBUG_LOG))

func _initialize() -> void:
	print("== test_y_flip_decoder ==")
	_del_debug_log()
	m = load("res://scripts/gesture_map.gd").new()

	# ---- 段 1（Y-A5）：held 帧冻结语义/翻转态机（不计为翻转、不清翻转状态）----
	m.reset()
	var h0 := _hand(0.9, F_FOUR, 10.0, true, "Left", 0.2, Vector2(0.3, 0.4), 1.0)
	var h1 := _hand(0.9, F_FOUR, 10.0, true, "Left", 0.2, Vector2(0.3, 0.4), 1.033)
	h0["id"] = "L0"
	h1["id"] = "L0"
	m.feed_frame(h0, {}, 1.0)
	m.feed_frame(h1, {}, 1.033)             # 前置 2 帧锁定（roll0=10）
	var h2 := _hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 1.10)
	h2["id"] = "L0"
	var seq_a: Array = m.feed_frame(h2, {}, 1.10)   # 翻腕第 1 帧（streak=1）
	check(not _has(seq_a, "undo"), "Y-A5 前置：翻腕第 1 帧不触发（2 帧门）")
	var h_held := _hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 1.133)
	h_held["id"] = "L0"
	h_held["held"] = true
	var seq_b: Array = m.feed_frame(h_held, {}, 1.133)   # held 帧（陈旧数据=翻腕姿态）
	check(seq_b.is_empty(), "Y-A5：held 帧零语义事件派发（不计数/不触发）")
	check(not _has(seq_b, "undo"), "Y-A5：held 帧不计为翻转（旧码照常处理凑满 2 帧=undo 红灯）")
	var seq_c: Array = m.feed_frame(_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 1.60), {}, 1.60)
	check(not _has(seq_c, "undo"), "Y-A5：held 后第 1 真帧仍不足 2 连（held 帧未计入 streak）")
	seq_c.append_array(m.feed_frame(_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 1.633), {}, 1.633))   # 真帧补满 2 连 → flip（内部 pending）
	seq_c.append_array(m.feed_frame(_hand(0.9, F_FOLD, 5.0, true, "Left", 0.2, Vector2(0.3, 0.4), 2.90), {}, 2.90))   # Z5：1.30s>1.2s 窗闭合
	check(_has(seq_c, "undo"),
		"Y-A5：held 帧未清翻转态——锁定窗内真帧补满 2 连触发 + 1.2s 同窗闭合解算 undo（Z5 窗平移留痕）")

	# ---- 段 2（Y-A5）：id 变化=新手 → 该侧累计态全清（防串手污染）----
	m.reset()
	var g0 := _hand(0.9, F_FOUR, 10.0, true, "Left", 0.2, Vector2(0.3, 0.4), 10.0)
	var g1 := _hand(0.9, F_FOUR, 10.0, true, "Left", 0.2, Vector2(0.3, 0.4), 10.033)
	g0["id"] = "L0"
	g1["id"] = "L0"
	m.feed_frame(g0, {}, 10.0)
	m.feed_frame(g1, {}, 10.033)            # 前置 2 帧锁定（id=L0，roll0=10）
	var g2 := _hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 10.10)
	g2["id"] = "L1"                         # id 变化帧（L0→L1=新手）
	var seq_d: Array = []
	seq_d.append_array(m.feed_frame(g2, {}, 10.10))
	seq_d.append_array(m.feed_frame(_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 10.133), {}, 10.133))   # id 缺省=同侧同一手（L1 续）
	seq_d.append_array(m.feed_frame(_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 10.40), {}, 10.40))
	seq_d.append_array(m.feed_frame(_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 10.433), {}, 10.433))
	seq_d.append_array(m.feed_frame(_hand(0.9, F_FOLD, 5.0, true, "Left", 0.2, Vector2(0.3, 0.4), 11.00), {}, 11.00))
	check(not _has(seq_d, "undo"),
		"Y-A5：手 id 变化（L0→L1）→ 翻转锁/进度全清（旧码沿用前任锁定态于窗闭合解算 undo=红灯）")
	# 新手（L1）重走前置：2 帧锁定 + 反向翻腕 2 帧 → 触发 + 1.2s 同窗闭合解算
	m.feed_frame(_hand(0.9, F_FOUR, 10.0, true, "Left", 0.2, Vector2(0.3, 0.4), 11.40), {}, 11.40)
	m.feed_frame(_hand(0.9, F_FOUR, 10.0, true, "Left", 0.2, Vector2(0.3, 0.4), 11.433), {}, 11.433)
	var seq_e: Array = m.feed_frame(_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 11.50), {}, 11.50)
	seq_e.append_array(m.feed_frame(_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 11.533), {}, 11.533))
	seq_e.append_array(m.feed_frame(_hand(0.9, F_FOLD, 5.0, true, "Left", 0.2, Vector2(0.3, 0.4), 12.90), {}, 12.90))   # Z5：1.367s>1.2s
	check(_has(seq_e, "undo"), "Y-A5：id 清零后新手重新前置/翻转可达（清零不毁语义可用性；Z5 窗平移留痕）")

	# ---- 段 3（Y-A8）：clear 独立防误窗解耦——clear 后 0.5s 真翻转仍被接受 ----
	# （右手 dict 一律喂 feed_frame 第二参；第一参 left 恒 {}）
	# 批次 AA W3-2 等价改写：clear 提交由「右四指双帧确认（20.066）」改为「右掌静止 dwell 1.0s
	# （21.10，dwell 起算 20.066）」→ 独立防误窗同步后移至 21.45；翻转序列改为「防误窗过期后
	# 前置重锁（21.50/21.533，roll0=130）→ 反向翻腕（21.60/21.633）→ 1.2s 同窗闭合（22.90）」，
	# Y-A8 语义（防误窗只抑制窗内误解算、0.35s 后真翻转照常）不变。
	m.reset()
	var seq_f: Array = m.feed_frame({}, _hand(0.9, F_REST, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 20.0), 20.0)
	seq_f.append_array(m.feed_frame({}, _hand(0.9, F_FOUR, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 20.033), 20.033))
	seq_f.append_array(m.feed_frame({}, _hand(0.9, F_FOUR, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 20.066), 20.066))   # 入态（dwell 起算锚）
	seq_f.append_array(m.feed_frame({}, _hand(0.9, F_FOUR, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 21.10), 21.10))   # 静止满 1.0s → clear
	check(not _has(seq_f, "clear"), "Y-A8 前置（AD §4.3.4 等价改写）：右掌静止 dwell 清空已彻底废除 → 静止满 1.0s 零 clear（旧 W3-2 dwell 提交通路退役留痕；Y-A8 翻转冷却/窗闭合语义独立于 clear，仍由下方 redo 可达断言覆盖）")
	seq_f.append_array(m.feed_frame({}, _hand(0.9, F_FOUR, 130.0, true, "Right", 0.2, Vector2(0.7, 0.4), 21.50), 21.50))   # 防误窗过期：前置重锁 roll0=130
	seq_f.append_array(m.feed_frame({}, _hand(0.9, F_FOUR, 130.0, true, "Right", 0.2, Vector2(0.7, 0.4), 21.533), 21.533))
	seq_f.append_array(m.feed_frame({}, _hand(0.9, F_FOUR, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 21.60), 21.60))
	seq_f.append_array(m.feed_frame({}, _hand(0.9, F_FOUR, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 21.633), 21.633))   # 反向翻腕 2 帧 → 触发
	seq_f.append_array(m.feed_frame({}, _hand(0.9, F_REST, 5.0, true, "Right", 0.2, Vector2(0.7, 0.4), 22.90), 22.90))   # 1.267s>1.2s 窗闭合
	check(_has(seq_f, "redo"),
		"Y-A8：clear 提交后 0.5s 翻转仍被接受 → redo 解算可达（旧码 1.0s 冷却吞翻转=红灯；W3-2 dwell 时序平移留痕）")
	# clear 后立刻翻腕（<0.35 防误窗）仍被抑制（P2-1 语义保留）
	m.reset()
	var seq_g: Array = m.feed_frame({}, _hand(0.9, F_REST, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 22.0), 22.0)
	seq_g.append_array(m.feed_frame({}, _hand(0.9, F_FOUR, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 22.033), 22.033))
	seq_g.append_array(m.feed_frame({}, _hand(0.9, F_FOUR, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 22.066), 22.066))   # 入态（dwell 起算锚）
	seq_g.append_array(m.feed_frame({}, _hand(0.9, F_FOUR, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 23.10), 23.10))     # 静止满 1.0s → clear（防误窗至 23.45）
	check(not _has(seq_g, "clear"), "Y-A8 对照前置（AD §4.3.4 等价改写）：右掌 dwell 清空废除 → 静止满 1.0s 零 clear（旧防误窗起算随 dwell 通路退役留痕；本段窗内不闭合零 redo 判据仍由下条覆盖）")
	seq_g.append_array(m.feed_frame({}, _hand(0.9, F_FOUR, 130.0, true, "Right", 0.2, Vector2(0.7, 0.4), 23.20), 23.20))
	seq_g.append_array(m.feed_frame({}, _hand(0.9, F_FOUR, 130.0, true, "Right", 0.2, Vector2(0.7, 0.4), 23.233), 23.233))
	seq_g.append_array(m.feed_frame({}, _hand(0.9, F_FOUR, 130.0, true, "Right", 0.2, Vector2(0.7, 0.4), 23.30), 23.30))
	seq_g.append_array(m.feed_frame({}, _hand(0.9, F_FOUR, 130.0, true, "Right", 0.2, Vector2(0.7, 0.4), 23.333), 23.333))
	seq_g.append_array(m.feed_frame({}, _hand(0.9, F_REST, 5.0, true, "Right", 0.2, Vector2(0.7, 0.4), 24.20), 24.20))
	check(not _has(seq_g, "redo"),
		"Y-A8：clear 后 0.35s 防误窗内翻腕（roll Δ>90° 2 帧）零 redo（清空姿态同构误翻转防线保留）")
	# 连翻按新冷却全数计入：两翻相隔 >0.35s 冷却均触发（同窗闭合时点按 Z5 1.2s 平移——
	# #1 于 31.40 解算（1.267s>1.2s）先于 #2 场景（31.50 起），防同侧刷新把两次合并成一次）
	m.reset()
	m.feed_frame(_hand(0.9, F_FOUR, 10.0, true, "Left", 0.2, Vector2(0.3, 0.4), 30.0), {}, 30.0)
	m.feed_frame(_hand(0.9, F_FOUR, 10.0, true, "Left", 0.2, Vector2(0.3, 0.4), 30.033), {}, 30.033)   # 前置锁定
	m.feed_frame(_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 30.10), {}, 30.10)
	m.feed_frame(_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 30.133), {}, 30.133)  # 翻#1（冷却至 30.483）
	var seq_h: Array = m.feed_frame(_hand(0.9, F_FOLD, 5.0, true, "Left", 0.2, Vector2(0.3, 0.4), 31.40), {}, 31.40)
	check(_has(seq_h, "undo"), "Y-A8 前置：翻#1 经 1.2s 同窗闭合解算 undo#1（Z5 窗平移留痕）")
	seq_h.append_array(m.feed_frame(_hand(0.9, F_FOUR, 10.0, true, "Left", 0.2, Vector2(0.3, 0.4), 31.50), {}, 31.50))
	seq_h.append_array(m.feed_frame(_hand(0.9, F_FOUR, 10.0, true, "Left", 0.2, Vector2(0.3, 0.4), 31.533), {}, 31.533))   # 重锁（冷却已过）
	seq_h.append_array(m.feed_frame(_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 31.60), {}, 31.60))
	seq_h.append_array(m.feed_frame(_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 31.633), {}, 31.633))  # 翻#2（距#1 1.5s>冷却）
	seq_h.append_array(m.feed_frame(_hand(0.9, F_FOLD, 5.0, true, "Left", 0.2, Vector2(0.3, 0.4), 32.90), {}, 32.90))      # Z5：1.267s>1.2s
	check(_has(seq_h, "undo") and _types(seq_h).count("undo") >= 2,
		"Y-A8：连翻按新冷却 0.35s 全数计入（两 undo 皆可达；旧 1.0s 冷却第二翻=红灯）")

	# ---- 段 4（Y-A9/Z5）：双手就位时差 ≤1.2s 可进入倒数（错时 0.70s 配对 exit_flip）----
	# 批次 AA W3-2 等价改写：旧时序注「右四指 clear 提交（40.033）置独立防误窗 → 窗内右翻转态
	# 被清 → 防误窗过期重锁」随 clear 改【右】掌静止 dwell 退役——dwell 满 1.0s 的提交点在
	# 41.033（本段 40.933 结束前不触发），且 40.40 起右掌 roll 变化即取消 dwell → 本段**零
	# clear/零防误窗干扰**。为保住「错时 0.70s 配对」原意，右侧 roll 时序改为：40.40/40.433
	# 保持 roll10（掌面不变，不做翻腕），40.90/40.933 才反向翻腕（roll0=10 → 130，Δ=120°>75°
	# → flip@40.933，距左翻 40.233 恰 0.70s ≤1.2s 配对窗）。左侧时序零改动。
	m.reset()
	var acc: Array = []
	acc.append_array(m.feed_frame(
		_hand(0.9, F_FOUR, 10.0, true, "Left", 0.2, Vector2(0.3, 0.4), 40.0),
		_hand(0.9, F_FOUR, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 40.0), 40.0))
	acc.append_array(m.feed_frame(
		_hand(0.9, F_FOUR, 10.0, true, "Left", 0.2, Vector2(0.3, 0.4), 40.033),
		_hand(0.9, F_FOUR, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 40.033), 40.033))   # 双方前置锁定（W3-2：右 dwell 同刻起算，本段零 clear）
	acc.append_array(m.feed_frame(
		_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 40.20),
		_hand(0.9, F_FOUR, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 40.20), 40.20))
	acc.append_array(m.feed_frame(
		_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 40.233),
		_hand(0.9, F_FOUR, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 40.233), 40.233))   # 仅左翻（flip@40.233 → pending）
	check(not _has(acc, "exit_flip"), "Y-A9 前置：左先翻（右未翻）不成对")
	acc.append_array(m.feed_frame(
		_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 40.40),
		_hand(0.9, F_FOUR, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 40.40), 40.40))
	acc.append_array(m.feed_frame(
		_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 40.433),
		_hand(0.9, F_FOUR, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 40.433), 40.433))  # 左保持掌面重锁（roll0=130）；右仍 roll10 不翻（W3-2 等价改写）
	acc.append_array(m.feed_frame(
		_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 40.90),
		_hand(0.9, F_FOUR, 130.0, true, "Right", 0.2, Vector2(0.7, 0.4), 40.90), 40.90))
	acc.append_array(m.feed_frame(
		_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 40.933),
		_hand(0.9, F_FOUR, 130.0, true, "Right", 0.2, Vector2(0.7, 0.4), 40.933), 40.933))   # 右翻腕（flip@40.933，距左翻 0.70s；roll0=10 → Δ=120°）
	check(_has(acc, "exit_flip"),
		"Y-A9：右翻距左翻 0.70s（≤1.2 配对窗，Z5 放宽）→ exit_flip（旧 0.5s 窗=红灯）")
	check(not _has(acc, "clear"), "Y-A9 前置：错时配对段零 clear（dwell 未满 + roll 取消；W3-2 零干扰）")
	# 对照：时差 >1.2s 不配对 → 左翻按单翻解算 undo（1.2s 窗闭合；Z5 平移 0.90s→1.30s）
	# 批次 AA W3-2 等价改写：旧「右防误窗过期重锁（50.40/50.433，roll0=130）」依赖右 clear 双帧
	# 提交（防误窗清翻转态）——该通路随 dwell 退役（dwell 满点=51.033）。新时序：右掌静止至
	# 51.10 触发 clear（防误窗 0.35s 至 51.45）→ 51.20 前置重锁（roll0=10）→ 51.60/51.633 翻腕
	# （Δ=120°，防误窗已过）→ flip@51.633 距左翻 50.233 恰 1.40s>1.2s 仍不成对；左 pending 于
	# 51.50 首帧解算（1.267s>1.2s）先于右翻。末帧双侧离场清 pending（防残留泄入段 5）。
	m.reset()
	var acc2: Array = []
	acc2.append_array(m.feed_frame(
		_hand(0.9, F_FOUR, 10.0, true, "Left", 0.2, Vector2(0.3, 0.4), 50.0),
		_hand(0.9, F_FOUR, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 50.0), 50.0))
	acc2.append_array(m.feed_frame(
		_hand(0.9, F_FOUR, 10.0, true, "Left", 0.2, Vector2(0.3, 0.4), 50.033),
		_hand(0.9, F_FOUR, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 50.033), 50.033))   # 双方入态+前置锁定（右 dwell 同刻起算）
	acc2.append_array(m.feed_frame(
		_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 50.20),
		_hand(0.9, F_FOUR, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 50.20), 50.20))
	acc2.append_array(m.feed_frame(
		_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 50.233),
		_hand(0.9, F_FOUR, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 50.233), 50.233))   # 左翻@50.233
	acc2.append_array(m.feed_frame(
		_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 51.10),
		_hand(0.9, F_FOUR, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 51.10), 51.10))     # 右静止满 1.0s → clear（防误窗至 51.45）
	check(not _has(acc2, "clear"),
		"Y-A9 对照前置（AD §4.3.4 等价改写）：右掌 dwell 清空废除 → 静止满 1.0s 零 clear（旧 W3-2 新通路随右掌 dwell 彻底废除退役留痕；错帧配对 exit_flip/undo 判据不变）")
	acc2.append_array(m.feed_frame(
		_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 51.20),
		_hand(0.9, F_FOUR, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 51.20), 51.20))      # 右防误窗过期前置重锁（roll0=10）
	acc2.append_array(m.feed_frame(
		_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 51.50),
		_hand(0.9, F_FOUR, 10.0, true, "Right", 0.2, Vector2(0.7, 0.4), 51.50), 51.50))      # 左 pending 超 1.2s 窗（此处解算 undo）
	acc2.append_array(m.feed_frame(
		_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 51.60),
		_hand(0.9, F_FOUR, 130.0, true, "Right", 0.2, Vector2(0.7, 0.4), 51.60), 51.60))     # 右翻腕 1（Δ=120°）
	acc2.append_array(m.feed_frame(
		_hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 51.633),
		_hand(0.9, F_FOUR, 130.0, true, "Right", 0.2, Vector2(0.7, 0.4), 51.633), 51.633))   # 右翻@51.633（距左翻 1.40s>1.2）
	acc2.append_array(m.feed_frame(null, null, 51.70))                                       # 双侧离场：清 pending 残留（防泄入段 5）
	check(_has(acc2, "undo") and not _has(acc2, "exit_flip"),
		"Y-A9 对照：时差 1.40s（>1.2 窗，Z5 平移）→ 不配对，左翻按单翻解算 undo")

	# ---- 段 5（Y-A10）：诊断日志字段齐全（键齐全断言）----
	_del_debug_log()
	m.set_debug_enabled(true)
	var lf := _hand(0.9, F_FOUR, 45.0, true, "Left", 0.2, Vector2(0.3, 0.4), 80.0)
	var lf2 := _hand(0.9, F_FOUR, 130.0, true, "Left", 0.2, Vector2(0.3, 0.4), 80.10)
	lf["id"] = "L0"
	lf2["id"] = "L0"
	m.feed_frame(lf, {}, 80.0)
	m.feed_frame(lf2, {}, 80.10)
	m.feed_frame({}, {}, 80.20)   # 丢手（ev=lost 边沿）
	m.set_debug_enabled(false)
	check(FileAccess.file_exists(DEBUG_LOG), "Y-A10：开启后逐帧 dump 落盘")
	var dump_src: String = FileAccess.get_file_as_string(DEBUG_LOG)
	for key: String in ["roll=", "facing=", "locked=", "streak=", "cd=", "pending=[", "id=",
			"held=", "ev=lost", "semantic=", "conf=", "fingers=", "intents="]:
		check(dump_src.contains(key), "Y-A10：诊断日志含字段「%s」（向后兼容+新增键齐全）" % key)
	_del_debug_log()
	check(not FileAccess.file_exists(DEBUG_LOG), "Y-A10：日志非存档，终态清理")
	finish()
