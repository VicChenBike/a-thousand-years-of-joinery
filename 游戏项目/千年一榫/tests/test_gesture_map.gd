extends "res://tests/test_base.gd"
## 批次 R 核心判定用例：GestureMap 语义判定（spec §11.1-2 全检查点）。
## 纯逻辑层直调：feed_frame(左,右,now) 注入合成手 dict 与显式时间戳，无头零依赖。
## 意图词汇契约见 gesture_map.gd 文件尾表（type/side/pos/dir/factor/at）。

const F_CURSOR := [0.1, 0.9, 0.1, 0.1, 0.1]        # 仅食指（拇指收）
const F_TWO := [0.1, 0.9, 0.9, 0.1, 0.1]           # 食+中
const F_THREE := [0.1, 0.9, 0.9, 0.9, 0.1]         # 食+中+无
const F_FOUR := [0.1, 0.9, 0.9, 0.9, 0.9]          # 四指（拇指收）
const F_FOUR_THUMB_UP := [0.9, 0.9, 0.9, 0.9, 0.9] # 拇指不管断言用
const F_FOLD := [0.1, 0.9, 0.1, 0.1, 0.1]          # 收中指（与 F_CURSOR 同形）
const F_REST := [0.1, 0.1, 0.1, 0.1, 0.1]          # 全收指（审查回修 P1-1：Rest 夹具，时长三态/对接/拇指不管段回落用）

var m: Variant   # GestureMap 实例（load 动态引用）

func _hand(conf: float, fingers: Array, roll: float, facing: bool, label: String,
		palm_size: float, tip: Vector2, ts: float) -> Dictionary:
	var lm: Array = []
	for i: int in 21:
		lm.append([0.5, 0.5, 0.0])
	lm[0] = [tip.x - 0.05, tip.y + 0.20, 0.0]
	if (label == "Right") == facing:
		lm[5] = [lm[0][0] - 0.05, lm[0][1] - 0.06, 0.0]    # 食指根腕左上（cz>0：右掌朝镜/左背）
		lm[17] = [lm[0][0] + 0.05, lm[0][1] - 0.05, 0.0]
	else:
		lm[5] = [lm[0][0] + 0.05, lm[0][1] - 0.06, 0.0]    # 镜像布局（cz<0：左掌朝镜/右背）
		lm[17] = [lm[0][0] - 0.05, lm[0][1] - 0.05, 0.0]
	lm[8] = [tip.x, tip.y, 0.0]
	lm[9] = [lm[0][0], lm[0][1] - palm_size, 0.0]          # 腕0→中指根9 距离=palm_size
	return {
		"gesture": "", "gesture_id": 0, "confidence": conf,
		"hand_x": tip.x, "hand_y": tip.y, "hand_z": 0.0,
		"hand_rotation_x": roll, "hand_rotation_y": 0.0, "hand_rotation_z": 0.0,
		"fingers": fingers, "pinch_distance": 0.5,
		"hand_index": 0 if label == "Left" else 1, "handedness": label,
		"landmarks": lm, "fps": 30.0, "is_detected": true,
		"timestamp": ts, "palm_size": palm_size,
	}

func _types(intents: Array) -> Array:
	var out: Array = []
	for it: Variant in intents:
		out.append(String(it["type"]))
	return out

func _has(intents: Array, t: String) -> bool:
	return _types(intents).has(t)

## 批次 AA（W3-1 等价改写）：取指定意图的 side 序列（双侧同链断言用）
func _sides(intents: Array, t: String) -> Array:
	var out: Array = []
	for it: Variant in intents:
		if typeof(it) == TYPE_DICTIONARY and String(it["type"]) == t:
			out.append(String(it.get("side", "")))
	return out

func _feed_left(fingers: Array, conf: float, roll: float, facing: bool,
		ps: float, tip: Vector2, now: float) -> Array:
	return m.feed_frame(_hand(conf, fingers, roll, facing, "Left", ps, tip, now), {}, now)

func _feed_both(lf: Array, rf: Array, conf: float, roll: float, facing: bool,
		ps: float, now: float) -> Array:
	return m.feed_frame(
		_hand(conf, lf, roll, facing, "Left", ps, Vector2(0.3, 0.4), now),
		_hand(conf, rf, roll, facing, "Right", ps, Vector2(0.7, 0.4), now), now)

## 批次 AA（W3-4 等价改写）：双手**异 roll** 同帧喂帧——单侧翻转/配对窗异帧配对断言用
func _feed_rolls(lf: Array, rf: Array, conf: float, lroll: float, rroll: float,
		facing: bool, ps: float, now: float) -> Array:
	return m.feed_frame(
		_hand(conf, lf, lroll, facing, "Left", ps, Vector2(0.3, 0.4), now),
		_hand(conf, rf, rroll, facing, "Right", ps, Vector2(0.7, 0.4), now), now)

func _feed_left_filtered(tip: Vector2, now: float) -> Array:
	# P0-1 修正：_hand 为 8 参签名 (conf, fingers, roll, facing, label, palm_size, tip, ts)（磁盘 :16-17），
	# 不得传 4 参（编译期类型错误整文件挂死）。
	var h := _hand(0.9, F_CURSOR, 5.0, true, "Left", 0.2, tip, now)
	h["tip_x"] = tip.x
	h["tip_y"] = tip.y
	return m.feed_frame(h, {}, now)

func _initialize() -> void:
	print("== test_gesture_map ==")
	m = load("res://scripts/gesture_map.gd").new()
	# 批次 AC 4A（spec §4.6-3）：生产语义改**双手协同推拉/间距缩放**，单手推拉通道默认关。
	# 本文件段 10 的「单手掌推拉缩放」存量用例经兼容开关（`set_single_hand_zoom_enabled`）
	# 开启历史通道后逐字节照跑（等价改写留痕：断言与时序均不变，仅加一行开关）。
	m.set_single_hand_zoom_enabled(true)

	# ---- 1. 光标 0 帧即时（§4.2）----
	var r1: Array = _feed_left(F_CURSOR, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 1.0)
	check(_has(r1, "cursor_move"), "光标 0 帧即时：首帧即出 cursor_move")
	# 批次 T T8→批次 V §5.1→批次 X §3→批次 AA W2-2 等价替换留痕：tip 经增益 (n−0.5)×GAIN+0.5
	# 换算，GAIN 2.5→3.5→**2.5（批次 AA 降增益）**——raw(0.3,0.4) 期望 (0.0,0.25)
	#（(0.3−0.5)×2.5+0.5=0.0；(0.4−0.5)×2.5+0.5=0.25；旧 3.5 时代 (−0.15,0.15)、更旧
	# 批次 S ×2.0 期望 (0.1,0.3) 相继留痕）。首帧直达无 EMA 干扰）
	check(is_equal_approx(Vector2(r1[0]["pos"]).x, 0.0), "X1/W2-2：光标 pos.x=食指尖经增益换算（raw 0.3 → 0.0；批次 AA 增益 2.5 等价平移，旧 3.5 时钳 −0.15 留痕）")
	check(is_equal_approx(Vector2(r1[0]["pos"]).y, 0.85), "光标 pos.y=食指尖经增益换算（raw 0.4 → 0.85；AC §4.4-2 纵向基准上移 c_y=0.26 后重算 (0.4−0.26)×2.5+0.5=0.85；旧 (0.5,0.5) 基准时 0.25、更旧 3.5 时 0.15 相继留痕）")

	# ---- 2. 二指/三指/四指 2 帧确认（§4.2）----
	var r2a: Array = _feed_left(F_TWO, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 2.0)
	check(not _has(r2a, "two_down"), "二指第 1 帧不确认")
	var r2b: Array = _feed_left(F_TWO, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 2.033)
	check(_has(r2b, "two_down"), "二指第 2 帧确认 two_down")
	var r3a: Array = _feed_left(F_THREE, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 3.0)
	var r3b: Array = _feed_left(F_THREE, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 3.033)
	# 批次 X P5（spec §6）等价替换留痕：三指语义让位——旧 focus（聚焦锐眼）退役，改发 delete
	#（删除=【左】竖三指；Router 分派 delete_cell/delete_selected）
	check(_has(r3a, "focus") == false and _has(r3a, "delete") == false and _has(r3b, "delete"),
		"X4：三指 2 帧确认 delete（左手；旧 focus 意图随 P5-a 聚焦手势退役等价替换留痕）")
	var r4a: Array = _feed_both(F_FOUR, F_FOUR, 0.9, 5.0, true, 0.2, 4.0)
	var r4b: Array = _feed_both(F_FOUR, F_FOUR, 0.9, 5.0, true, 0.2, 4.033)
	# 批次 AA（W3-2，spec §6.3 + §22 裁决 2）等价改写：右四指双帧**不再立即 clear**（清空改
	# 【右】掌静止 dwell 1.0s，红绿证据与 0.9s/1.1s 边界见 test_aa_gesture_remap 段 2）——
	# 本段断言「双帧确认入态零 clear + 两侧同链 palm_begin」，断言数 2→3 只增不减。
	check(not _has(r4a, "clear") and not _has(r4b, "clear"),
		"W3-2：四指 2 帧确认零 clear（旧「双帧即 clear」退役留痕；清空=dwell 1.0s）")
	check(_has(r4b, "palm_begin"), "左手四指+掌面朝镜 → palm_begin（掌态候选）")
	check(_sides(r4b, "palm_begin").has("right"),
		"W3-1：右掌同帧同链 → palm_begin（旧 right=four/clear 分支退役，左右同链）")

	# ---- 3. 置信度三档（批次 Z Z5-1 等价改写：CONF_ENTER 0.65→0.55 拍板放宽、CONF_EXIT 0.45 维持
	# → 新滞后带 0.45~0.55；旧 0.45~0.65 带与「0.57 维持不触发」反转用例随放宽退役留痕——
	# 0.57 现落新带内应触发，边界对平移为 0.54/0.55）----
	m.reset()   # 清零第 2 段残留语义态（三档断言要求全新状态）
	var low: Array = []
	for i: int in 5:
		low.append_array(_feed_left(F_CURSOR, 0.52, 5.0, true, 0.2, Vector2(0.3, 0.4), 5.0 + 0.033 * i))
	check(not _has(low, "cursor_move"), "0.45~0.55 持续 5 帧不触发任何切换（Z5 新带；旧 0.45~0.65 带退役留痕）")
	var r54: Array = _feed_left(F_CURSOR, 0.54, 5.0, true, 0.2, Vector2(0.3, 0.4), 5.9)
	check(not _has(r54, "cursor_move"), "Z5 边界下沿：conf=0.54<0.55 维持不触发（旧 0.57 反转用例等价平移）")
	var r5: Array = _feed_left(F_CURSOR, 0.55, 5.0, true, 0.2, Vector2(0.3, 0.4), 6.0)
	check(_has(r5, "cursor_move"), "Z5：conf=0.55 触发光标（边界含；旧 0.65 断言退役留痕）")
	var r6: Array = _feed_left(F_CURSOR, 0.45, 5.0, true, 0.2, Vector2(0.3, 0.4), 6.033)
	check(_has(r6, "cursor_move"), "0.45~0.55 维持原态（motion 照发；0.45=EXIT 边界含）")
	var r7: Array = _feed_left(F_CURSOR, 0.39, 5.0, true, 0.2, Vector2(0.3, 0.4), 6.066)
	check(not _has(r7, "cursor_move"), "<0.45 回落：光标语义退出（T9：旧 0.40 等价替换）")

	# ---- 4. 右手二指收指（批次 X P5 退役等价替换留痕，spec §6：旧「0.35s 挖除/迟滞带/0.40s
	# 取消臂」三态时序窗整体退役——快伸快收挖除与按住取消随「右手=Ctrl 减选笔」新模型废除，
	# 二指态仅剩 two_down/two_move/two_up 即时事件对，收指=兜底 two_up 恰一次）----
	m.reset()
	var ra: Array = _feed_both(F_REST, F_TWO, 0.9, 5.0, true, 0.2, 10.0)
	ra.append_array(_feed_both(F_REST, F_TWO, 0.9, 5.0, true, 0.2, 10.033))  # 10.033 确认
	var rb: Array = _feed_both(F_REST, F_FOLD, 0.9, 5.0, true, 0.2, 10.30)   # 0.267s 收中指（旧挖除窗内）
	check(_has(rb, "two_up") and not _has(rb, "dig") and not _has(rb, "deselect_arm"),
		"X4：右手二指 <0.35s 收 → 仅兜底 two_up，零挖除/零取消意图（旧 dig 断言退役留痕）")
	var rc: Array = _feed_both(F_REST, F_TWO, 0.9, 5.0, true, 0.2, 11.0)
	rc.append_array(_feed_both(F_REST, F_TWO, 0.9, 5.0, true, 0.2, 11.033))
	var rd: Array = _feed_both(F_REST, F_FOLD, 0.9, 5.0, true, 0.2, 11.40)   # 0.367s ∈旧迟滞带
	check(_has(rd, "two_up") and not _has(rd, "dig") and not _has(rd, "deselect_arm"),
		"X4：0.35~0.40 旧迟滞带收 → 同款即时 two_up（时序窗废除后各时长口径收敛一致）")
	var re_: Array = _feed_both(F_REST, F_TWO, 0.9, 5.0, true, 0.2, 12.0)
	re_.append_array(_feed_both(F_REST, F_TWO, 0.9, 5.0, true, 0.2, 12.033))
	re_.append_array(_feed_both(F_REST, F_TWO, 0.9, 5.0, true, 0.2, 12.45))  # ≥0.40s（旧取消臂阈值帧）
	check(not _has(re_, "deselect_arm") and not _has(re_, "two_up") and _has(re_, "two_move"),
		"X4：按住 ≥0.40s → 无取消臂意图、two_move 照常（旧 deselect_arm 断言退役留痕）")
	var rf2: Array = _feed_both(F_REST, F_FOLD, 0.9, 5.0, true, 0.2, 12.60)
	check(_has(rf2, "two_up") and not _has(rf2, "dig"), "X4：长按后收中指 → two_up 恰一次")

	# ---- 5. 翻转前置与触发（§4.1 注 A）：锁定 → 1.0s 内 >75°（Z5 FLIP_ANGLE 90→75）→ 2 帧 → undo ----
	m.reset()
	_feed_left(F_FOUR, 0.9, 10.0, true, 0.2, Vector2(0.3, 0.4), 20.0)
	_feed_left(F_FOUR, 0.9, 10.0, true, 0.2, Vector2(0.3, 0.4), 20.033)      # 前置 2 帧锁定
	var r8: Array = _feed_left(F_FOUR, 0.9, 130.0, true, 0.2, Vector2(0.3, 0.4), 20.10)
	check(not _has(r8, "undo"), "翻转第 1 帧不触发（须 2 帧）")
	var r9: Array = _feed_left(F_FOUR, 0.9, 130.0, true, 0.2, Vector2(0.3, 0.4), 20.133)
	check(_has(r9, "flip") == false, "flip 为内部意图不外泄")
	# 批次 Z（Z5-1）：配对窗 SAME_WINDOW_SEC 0.8→1.2s——0.867s 处新窗未闭合（中途帧红锁，
	# 旧 0.8s 窗下此处已解算 undo=红）；1.267s 才闭合解算。
	var r10mid: Array = _feed_left(F_FOLD, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 21.00)
	check(not _has(r10mid, "undo"), "Z5：0.867s<1.2s 配对窗未闭合 → 尚不解算（窗放宽中途帧红锁）")
	var r10: Array = _feed_left(F_FOLD, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 21.40)
	check(_has(r10, "undo"), "1.2s 同翻窗口闭合（1.267s>1.2s；Z5 窗平移留痕）→ 单手翻转=左 undo")
	# roll 起点不满足（≥30°）不锁定不触发
	_feed_left(F_FOUR, 0.9, 50.0, true, 0.2, Vector2(0.3, 0.4), 21.0)
	_feed_left(F_FOUR, 0.9, 50.0, true, 0.2, Vector2(0.3, 0.4), 21.033)
	_feed_left(F_FOUR, 0.9, 170.0, true, 0.2, Vector2(0.3, 0.4), 21.10)
	var r11: Array = _feed_left(F_FOLD, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 21.60)
	check(not _has(r11, "undo"), "前置 roll≥30° 不锁定 → 不触发")
	# 1 秒冷却→批次 Y（Y-A8）0.35s：首翻经 1.2s 同窗闭合（Z5 配对窗 0.8→1.2）解算恰一次 undo；
	# 冷却期内（0.35s）重进前置被拒；冷却过期后重翻**被接受**（新语义红绿双锁）。
	# Z5 窗平移连带：#1 解算点 23.10→23.60（1.317s>1.2s），#2 场景整体后移（23.70 起）——
	# 否则 #2 同侧翻转会刷新仍在场的 pending 把 #1/#2 合并成一次解算（断言「恰两次」破）。
	_feed_left(F_FOUR, 0.9, 10.0, true, 0.2, Vector2(0.3, 0.4), 22.15)   # 前段窗口（21.033 起 1.0s）已过期，全新前置
	_feed_left(F_FOUR, 0.9, 10.0, true, 0.2, Vector2(0.3, 0.4), 22.183)
	_feed_left(F_FOUR, 0.9, 130.0, true, 0.2, Vector2(0.3, 0.4), 22.25)
	_feed_left(F_FOUR, 0.9, 130.0, true, 0.2, Vector2(0.3, 0.4), 22.283)   # 触发#1（翻转@22.283，冷却至 22.633）
	# 冷却期内（<22.633）重进前置+翻腕：被拒，不产生第二次翻转
	_feed_left(F_FOUR, 0.9, 10.0, true, 0.2, Vector2(0.3, 0.4), 22.35)
	_feed_left(F_FOUR, 0.9, 10.0, true, 0.2, Vector2(0.3, 0.4), 22.383)
	_feed_left(F_FOUR, 0.9, 130.0, true, 0.2, Vector2(0.3, 0.4), 22.45)
	_feed_left(F_FOUR, 0.9, 130.0, true, 0.2, Vector2(0.3, 0.4), 22.483)
	var r_res: Array = _feed_left(F_REST, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 23.60)
	check(_has(r_res, "undo"), "首翻经 1.2s 同窗闭合（1.317s>1.2s；Z5 窗平移留痕）解算为左 undo（恰一次）")
	check(not _has(r_res, "redo"), "Y-A8：冷却期内（0.35s）重进前置翻腕被拒 → 无第二次翻转意图")
	# 冷却过期后（>0.35s）重进前置+翻转：被接受（Y-A8 新语义——旧 1.0s 冷却吞翻转红灯）
	_feed_left(F_FOUR, 0.9, 10.0, true, 0.2, Vector2(0.3, 0.4), 23.70)
	_feed_left(F_FOUR, 0.9, 10.0, true, 0.2, Vector2(0.3, 0.4), 23.733)
	_feed_left(F_FOUR, 0.9, 130.0, true, 0.2, Vector2(0.3, 0.4), 23.80)
	_feed_left(F_FOUR, 0.9, 130.0, true, 0.2, Vector2(0.3, 0.4), 23.833)   # 触发#2（距#1 1.55s，冷却 0.35s 已过）
	var r12: Array = _feed_left(F_REST, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 25.10)
	check(_has(r12, "undo"), "Y-A8：冷却过期（>0.35s）后重翻被接受 → 第二次 undo（旧 1.0s 冷却=红灯）")

	# ---- 5b. 批次X收口 P2-1（spec §12 方案①）→ 批次 Y（Y-A8）独立防误窗改写 →
	# 批次 AD（§4.3.4）等价改写：右掌 dwell 清空**彻底废除**（清空改双手握拳，见
	# test_ad_batch3_interaction 段 A）——本段「静止满 1.0s → clear 提交」的旧通路整体退役。
	# 断言集与断言数（3 条）维持：①右掌静止全窗（>1.0s）零 clear（旧「dwell 提交」废除留痕，
	# 判据反置）②无 clear 亦无防误窗误派发 redo（窗内翻腕仍零 redo，判据不变）
	# ③防误窗/冷却语义与翻转解算仍正常（redo 可达，判据不变）。
	m.reset()
	# 批次 AA（W3-2，spec §6.3 + §22 裁决 2）旧等价改写留痕：右掌 clear 曾由「双帧即提交」改为
	# 「静止 dwell 1.0s 提交」——本段时序整体后移：入态 25.233 → 静止保持至 26.256 首帧越过
	# 1.0s。批次 AD（§4.3.4）起 dwell 提交通路废除，右掌静止不再产生 clear。
	var cb: Array = _feed_both(F_REST, F_FOUR, 0.9, 10.0, true, 0.2, 25.2)
	cb.append_array(_feed_both(F_REST, F_FOUR, 0.9, 10.0, true, 0.2, 25.233))   # 右掌入态（旧 dwell 起算锚 25.233）
	for i: int in 31:   # 静止保持 25.266…26.256（旧口径此窗首帧应越 1.0s 提交 clear）
		cb.append_array(_feed_both(F_REST, F_FOUR, 0.9, 10.0, true, 0.2, 25.266 + 0.033 * i))
	check(not _has(cb, "clear"), "AD §4.3.4：右掌静止连续满 1.0s 亦零 clear（旧 W3-2「静止 dwell 提交」随右掌 dwell 清空彻底废除留痕；清空改双手握拳）")
	cb.append_array(_feed_both(F_REST, F_FOUR, 0.9, 130.0, true, 0.2, 26.30))
	cb.append_array(_feed_both(F_REST, F_FOUR, 0.9, 130.0, true, 0.2, 26.333))  # 防误窗内翻腕 2 帧（roll Δ=120°>75°）
	cb.append_array(_feed_both(F_REST, F_FOUR, 0.9, 130.0, true, 0.2, 26.70))   # 防误窗已过期帧
	check(not _has(cb, "redo"), "P2-1/Y-A8：clear 防误窗内翻腕（roll Δ>75° 2 帧）→ 零 redo 派发（窗内误解算抑制）")
	cb.append_array(_feed_both(F_REST, F_FOUR, 0.9, 130.0, true, 0.2, 26.733))  # 保持掌面前置重锁（roll0=130）
	cb.append_array(_feed_both(F_REST, F_FOUR, 0.9, 10.0, true, 0.2, 26.80))
	cb.append_array(_feed_both(F_REST, F_FOUR, 0.9, 10.0, true, 0.2, 26.833))   # 反向翻腕 2 帧（Δ=120°）→ 触发
	var cb2: Array = _feed_both(F_REST, F_FOLD, 0.9, 5.0, true, 0.2, 28.10)     # 1.2s 同窗闭合解算（28.10-26.833=1.267s）
	check(_has(cb2, "redo"), "P2-1/Y-A8：防误窗过期后翻转仍正常（保持掌面重锁 → 反向翻腕 → redo 解算可达；W3-2 dwell 时序平移+Z5 1.2s 窗留痕）")

	# ---- 6. 双手 1.2s 窗口内双翻 → exit_flip 优先，不出 undo/redo（§4.1 注 A；Z5 窗 0.8→1.2 留痕）----
	# 历史留痕（批次X收口 P2-1/Y-A8）：旧时序曾因「右掌 clear 双帧提交置独立防误窗 0.35s」而后移
	# 至 31.10 起重锁再同翻（31.20/31.233）；批次 AA（W3-2）起 clear 改静止 dwell，该时序退役。
	# 批次 AA（W3-2/W3-4 连带）等价改写：旧「右 clear 双帧提交（30.033）+ 防误窗过期重锁」时序
	# 随 clear 改 dwell 退役——右掌现于 30.033 起算 dwell（31.033 满 1.0s），配对须在此之前完成；
	# 故改为**异帧配对**（左 30.133 翻、右 30.833 翻，Δ=0.7s ≤1.2s 配对窗），比旧同帧配对更强
	#（真机两手翻转天然错帧）。断言数 2→3（新增「单侧翻不成对」前置），只增不减。
	_feed_both(F_FOUR, F_FOUR, 0.9, 10.0, true, 0.2, 30.0)
	_feed_both(F_FOUR, F_FOUR, 0.9, 10.0, true, 0.2, 30.033)   # 双方前置锁定（W3-2：右 dwell 同刻起算）
	_feed_rolls(F_FOUR, F_FOUR, 0.9, 130.0, 10.0, true, 0.2, 30.10)
	var r12b: Array = _feed_rolls(F_FOUR, F_FOUR, 0.9, 130.0, 10.0, true, 0.2, 30.133)   # 左翻转 2 帧触发 → pending(left)
	check(not _has(r12b, "exit_flip"), "W3-4 前置：仅左单翻不成对 → 零 exit_flip（配对窗前置）")
	var r13: Array = _feed_rolls(F_FOUR, F_FOUR, 0.9, 130.0, 130.0, true, 0.2, 30.80)
	r13.append_array(_feed_rolls(F_FOUR, F_FOUR, 0.9, 130.0, 130.0, true, 0.2, 30.833))  # 右翻转触发（距左 0.7s）
	check(_has(r13, "exit_flip"), "双手 1.2s 窗口内异帧同翻 → exit_flip（配对窗语义保持；须在右掌 dwell 满 1.0s 前完成——W3-2 时序平移留痕）")
	check(not _has(r13, "undo") and not _has(r13, "redo"), "同翻优先：不出 undo/redo")

	# ---- 7. 倒数进行中单手翻转抑制（§4.1 注 A）----
	m.set_exit_countdown(true)
	_feed_left(F_FOUR, 0.9, 10.0, true, 0.2, Vector2(0.3, 0.4), 32.0)
	_feed_left(F_FOUR, 0.9, 10.0, true, 0.2, Vector2(0.3, 0.4), 32.033)
	_feed_left(F_FOUR, 0.9, 130.0, true, 0.2, Vector2(0.3, 0.4), 32.10)
	_feed_left(F_FOUR, 0.9, 130.0, true, 0.2, Vector2(0.3, 0.4), 32.133)
	var r14: Array = _feed_left(F_FOLD, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 32.70)
	check(not _has(r14, "undo") and not _has(r14, "exit_flip"), "倒数期单翻一律抑制（不成对不解算）")
	m.set_exit_countdown(false)

	# ---- 8. 双手二指（食+中）确认 = 对接；单帧不触发/持续不重复/1s 冷却/零左键（批次 AA W3-4，
	# spec §6.3 W3-4 + §22 裁决 3）——旧「双侧仅食指 cursor 边沿 ±SAME_WINDOW_SEC」判据退役
	# （用户「太易误触」根因：单食指+拇指自然收起即触发），红绿证据见 test_aa_gesture_remap 段 3。
	# 断言数 4→7（新增单帧门、双侧零 two_down、冷却态零 two_down），只增不减 ----
	m.reset()
	var j0: Array = _feed_both(F_TWO, F_TWO, 0.9, 5.0, true, 0.2, 40.0)
	check(not _has(j0, "join"), "W3-4：单帧未确认零 join（CONFIRM_FRAMES=2 双帧门保持）")
	var j1: Array = _feed_both(F_TWO, F_TWO, 0.9, 5.0, true, 0.2, 40.033)
	check(_has(j1, "join"), "W3-4：双手同帧二指确认 → join 恰一次（判据改双手同帧 two）")
	check(not _has(j1, "two_down"), "W3-4：双手同时 two → 零 two_down（左键抑制，裁决 3）")
	var j2: Array = _feed_both(F_TWO, F_TWO, 0.9, 5.0, true, 0.2, 40.5)
	check(not _has(j2, "join"), "持续保持双手二指不重复触发（_join_latched 单真值）")
	var j3: Array = _feed_both(F_REST, F_REST, 0.9, 5.0, true, 0.2, 40.6)
	var j4: Array = _feed_both(F_TWO, F_TWO, 0.9, 5.0, true, 0.2, 40.8)
	j4.append_array(_feed_both(F_TWO, F_TWO, 0.9, 5.0, true, 0.2, 40.833))
	check(not _has(j4, "join"), "冷却期（<1s）内新配对不触发（join@40.033 → 冷却至 41.033）")
	check(not _has(j4, "two_down"), "冷却期内新配对同样零 two_down（抑制不随冷却失效）")
	var j5: Array = _feed_both(F_REST, F_REST, 0.9, 5.0, true, 0.2, 41.0)
	var j6: Array = _feed_both(F_TWO, F_TWO, 0.9, 5.0, true, 0.2, 41.2)
	j6.append_array(_feed_both(F_TWO, F_TWO, 0.9, 5.0, true, 0.2, 41.233))
	check(_has(j6, "join"), "冷却（1s）过后双手二指重新触发 join")

	# ---- 9. 拇指不管（§4.2）：fingers[0] 任意值不参与四指判定（批次 AA W3-1/2 连带等价改写：
	# 观察载体由「clear」改为「palm_begin + 语义=palm」——清空已改右掌静止 dwell，见段 2/段 8）----
	var t1: Array = _feed_both(F_REST, F_FOUR_THUMB_UP, 0.9, 5.0, true, 0.2, 45.0)
	t1.append_array(_feed_both(F_REST, F_FOUR_THUMB_UP, 0.9, 5.0, true, 0.2, 45.033))
	check(_has(t1, "palm_begin") and not _has(t1, "clear"),
		"W3-1/2：右手四指+拇指伸直 → palm_begin 且零 clear（拇指不管保持；清空改 dwell 留痕）")
	check_eq(String(m.get_side_semantic("right")), "palm",
		"拇指不管：fingers[0] 不参与四指判定 → 右侧语义=palm（旧 four 通路退役）")

	# ---- 10. 掌态观察窗（§5.3）：推拉 15%/3 帧 → zoom；静止 → 翻转窗至满 1.0s ----
	m.reset()
	var z1: Array = []
	z1.append_array(_feed_left(F_FOUR, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 50.0))
	z1.append_array(_feed_left(F_FOUR, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 50.033))  # 确认+锁定
	z1.append_array(_feed_left(F_FOUR, 0.9, 5.0, true, 0.35, Vector2(0.3, 0.4), 50.066))
	z1.append_array(_feed_left(F_FOUR, 0.9, 5.0, true, 0.35, Vector2(0.3, 0.4), 50.099))
	var z2: Array = _feed_left(F_FOUR, 0.9, 5.0, true, 0.35, Vector2(0.3, 0.4), 50.132)
	check(_has(z2, "zoom_begin"), "palm_size 变化 >15% 持续 3 帧 → zoom_begin")
	check(_has(z2, "zoom_step"), "推近 r 增大越过 ln(1.10) 台阶 → zoom_step")
	var zf: Variant = null
	for it: Variant in z2:
		if String(it["type"]) == "zoom_step":
			zf = it
	check(int(zf["dir"]) == 1, "推近（palm_size 增）→ dir=+1（WHEEL_UP 放大）")
	var z3: Array = _feed_left(F_CURSOR, 0.9, 5.0, true, 0.35, Vector2(0.3, 0.4), 50.30)
	check(_has(z3, "zoom_end"), "收掌（四指收回）→ zoom_end")
	# 观察窗超时后翻转窗继续有效至满 1.0s（§5.3 终态）
	_feed_left(F_FOUR, 0.9, 10.0, true, 0.2, Vector2(0.3, 0.4), 52.0)
	_feed_left(F_FOUR, 0.9, 10.0, true, 0.2, Vector2(0.3, 0.4), 52.033)
	var z4: Array = _feed_left(F_FOUR, 0.9, 130.0, true, 0.2, Vector2(0.3, 0.4), 52.60)
	var z5: Array = _feed_left(F_FOUR, 0.9, 130.0, true, 0.2, Vector2(0.3, 0.4), 52.633)
	check(not _has(z4, "undo") and not _has(z5, "undo"), "观察窗期翻转 2 帧未满不触发")
	var z6: Array = _feed_left(F_FOLD, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 53.90)
	check(_has(z6, "undo"), "观察窗期完成的翻转仍触发（1.267s>1.2s 同窗闭合后解算；Z5 窗平移留痕）")
	# 缩放态抑制翻转：进入 zoom 后 roll 变化不触发 undo
	_feed_left(F_FOUR, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 54.0)
	_feed_left(F_FOUR, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 54.033)
	_feed_left(F_FOUR, 0.9, 5.0, true, 0.35, Vector2(0.3, 0.4), 54.066)
	_feed_left(F_FOUR, 0.9, 5.0, true, 0.35, Vector2(0.3, 0.4), 54.099)
	var z7: Array = _feed_left(F_FOUR, 0.9, 5.0, true, 0.35, Vector2(0.3, 0.4), 54.132)
	check(_has(z7, "zoom_begin"), "进入缩放态")
	var z8: Array = _feed_left(F_FOUR, 0.9, 130.0, true, 0.35, Vector2(0.3, 0.4), 54.20)
	var z9: Array = _feed_left(F_FOUR, 0.9, 130.0, true, 0.35, Vector2(0.3, 0.4), 54.233)
	var z10: Array = _feed_left(F_FOLD, 0.9, 5.0, true, 0.35, Vector2(0.3, 0.4), 54.80)
	check(not _has(z10, "undo"), "缩放态中翻转被抑制（本段掌态不再判翻转）")

	# ---- 11. 单笔互斥（§13 注 B）：左笔活跃 → 右笔整段忽略（批次 X P5 等价替换留痕：旧以
	# dig/deselect_arm 为右笔观察载体，时序窗退役后改以 two_down/two_up 为观察载体）----
	var m1: Array = _feed_left(F_TWO, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 60.0)
	m1.append_array(_feed_left(F_TWO, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 60.033))
	check(_has(m1, "two_down"), "左笔建立")
	var m2: Array = _feed_both(F_TWO, F_TWO, 0.9, 5.0, true, 0.2, 60.10)
	m2.append_array(_feed_both(F_TWO, F_TWO, 0.9, 5.0, true, 0.2, 60.133))
	check(not _has(m2, "two_down"), "左笔活跃期右二指入待判被抑制（右 two_down 零派发；旧 dig/deselect_arm 载体等价替换）")
	var m3: Array = _feed_left(F_FOLD, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 60.30)
	check(_has(m3, "two_up"), "左笔抬起")
	var m4: Array = _feed_both(F_FOLD, F_TWO, 0.9, 5.0, true, 0.2, 60.40)
	m4.append_array(_feed_both(F_FOLD, F_TWO, 0.9, 5.0, true, 0.2, 60.433))
	m4.append_array(_feed_both(F_FOLD, F_FOLD, 0.9, 5.0, true, 0.2, 60.70))
	check(_has(m4, "two_down") and _has(m4, "two_up"), "左笔结束后右笔恢复（two_down 双帧确认建立+收指 two_up）")

	# ---- 12. 手离场兜底：二指按住中离场 → two_up 防虚拟键卡死 ----
	_feed_left(F_TWO, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 70.0)
	_feed_left(F_TWO, 0.9, 5.0, true, 0.2, Vector2(0.3, 0.4), 70.033)
	var l1: Array = m.feed_frame({}, {}, 70.10)
	check(_has(l1, "two_up"), "手离场 → 兜底 two_up")

	# ---- 13. 增益 filtered 源直测（批次 V §5.1 → 批次 AA W2-1/W2-2 等价改写：二级 EMA
	# 上线后「filtered 直喂直出」语义退役（spec §5.3 W2-1 明令对 tip_x/tip_y 增加 α0.35
	# 二级平滑）——本段改按「首帧直通 + 阶跃 35% 逐帧」断言，采样点随 gain 2.5 等价平移，
	# 钳制域（±m）与中心不动点覆盖以首帧直通点保持，断言数 6→7 只增不减）----
	# 批次 AC 等价改写：纵向基准上移 c_y=0.26（§4.4-2）→「不动点」采样改为 (0.5,c_y)；
	# α 0.35→0.60（§4.3-2）→ 阶跃逐帧期望按新 α 的 raw-EMA 链重算（EMA 作用于 raw tip，
	# 增益在其后；链：0.3→0.5→0.7→0.8 raw → gain 后 0.0 / 0.30 / 0.72 / 1.038）。
	var gm_c: Dictionary = (load("res://scripts/gesture_map.gd") as Script).get_script_constant_map()
	var cy_here: float = (0.5 + float(gm_c.get("CURSOR_OVERSHOOT", 0.15))) / float(gm_c.get("CURSOR_GAIN", 2.5))
	m.reset()
	var gc: Array = _feed_left_filtered(Vector2(0.5, cy_here), 79.9)
	check(gc.size() > 0 and Vector2(gc[0]["pos"]).is_equal_approx(Vector2(0.5, 0.5)),
		"AC §4.4-2：新不动点 (0.5,c_y=%.2f)→(0.5,0.5)（首帧直通；旧 (0.5,0.5) 不动点随纵向中心上移退役留痕）" % cy_here)
	m.reset()
	var g1: Array = _feed_left_filtered(Vector2(0.3, 0.0), 80.0)
	check(g1.size() > 0 and Vector2(g1[0]["pos"]).x <= 0.0001 and Vector2(g1[0]["pos"]).y <= 0.0001,
		"W2-2：(0.3,0.0)→(0.0,−0.15 量级)（增益 2.5 线性段 x 无钳、y 触下缘钳；AC 纵向采样点随 c_y 平移留痕：旧 3.5 时 0.3→−0.15）")
	var g2: Array = _feed_left_filtered(Vector2(0.5, cy_here), 80.033)
	# 批次 AD（§4.1.2）等价改写：α 0.60→**1.0 直通**——期望值改由 **live α 的 raw-EMA 链**推导
	# （判据「单条真实生效的二级路径 + 系数随常量」逐条保持；α=1.0 时即「当帧食指尖直出」，这正是
	# AD 消除级联低通的目标语义）。旧 α 0.60 数值留痕：content x 0.30 / y 0.24。
	var alpha_here: float = float(gm_c.get("CURSOR_EMA_ALPHA", 1.0))
	var raw_x: float = 0.3 + alpha_here * (0.5 - 0.3)
	var raw_y: float = 0.0 + alpha_here * (cy_here - 0.0)
	var exp_x2: float = (raw_x - 0.5) * float(gm_c.get("CURSOR_GAIN", 2.5)) + 0.5
	var exp_y2: float = (raw_y - cy_here) * float(gm_c.get("CURSOR_GAIN", 2.5)) + 0.5
	check(g2.size() > 0 and absf(float(Vector2(g2[0]["pos"]).x) - exp_x2) < 0.002
		and absf(float(Vector2(g2[0]["pos"]).y) - exp_y2) < 0.002,
		"AD §4.1.2：阶跃 (0.3→0.5) 第 1 帧按 live α(%.2f) 的 raw-EMA 链到位（期望 x %.3f / y %.3f——EMA 作用于 raw tip，两轴同链；α=1.0 即直通=消除级联低通；旧 α0.60 content 0.30/0.24、α0.35 时 0.175 留痕）" % [alpha_here, exp_x2, exp_y2])
	var g3: Array = _feed_left_filtered(Vector2(0.7, cy_here), 80.066)
	var raw_x3: float = raw_x + alpha_here * (0.7 - raw_x)
	var exp_x3: float = (raw_x3 - 0.5) * float(gm_c.get("CURSOR_GAIN", 2.5)) + 0.5
	check(g3.size() > 0 and absf(float(Vector2(g3[0]["pos"]).x) - exp_x3) < 0.002,
		"AD §4.1.2：阶跃第 2 帧继续按 live α 链推进（期望 content x %.3f，raw ema %.4f；旧 α0.60 值 0.72、α0.35 时 0.46375 留痕）" % [exp_x3, raw_x3])
	var g4: Array = _feed_left_filtered(Vector2(0.8, cy_here), 80.099)
	var raw_x4: float = raw_x3 + alpha_here * (0.8 - raw_x3)
	var exp_x4: float = clampf((raw_x4 - 0.5) * float(gm_c.get("CURSOR_GAIN", 2.5)) + 0.5,
		-float(gm_c.get("CURSOR_OVERSHOOT", 0.15)), 1.0 + float(gm_c.get("CURSOR_OVERSHOOT", 0.15)))
	check(g4.size() > 0 and absf(float(Vector2(g4[0]["pos"]).x) - exp_x4) < 0.005
		and absf(float(Vector2(g4[0]["pos"]).y) - 0.5) < 0.005,
		"AD §4.1.2：两轴独立推进且 y 恒不动点 0.5（期望 x %.3f = live α 链增益后；钳制域 [−0.15,1.15]；旧 α0.60 值 1.038/0.4584、α0.35 数值留痕）" % exp_x4)
	m.reset()
	var g5: Array = _feed_left_filtered(Vector2(0.9, 0.9), 80.132)
	check(g5.size() > 0 and Vector2(g5[0]["pos"]).is_equal_approx(Vector2(1.15, 1.15)),
		"X1：(0.9,0.9) 首帧直通→(1.15,1.15) 上缘钳（钳制域 [-m,1+m] 覆盖保持；采样点随 gain 2.5 等价平移：旧 3.5 时 0.7/0.8 触钳）")

	# ---- 14. S12 光标层 get_pointer_pos（批次 S spec §3-12；S-C1 数据侧契约，§11-R1 落位本文件）----
	var layer: CanvasLayer = load("res://scripts/gesture_cursor_layer.gd").new()
	add_child(layer)
	await process_frame
	check(layer.call("get_pointer_pos") == null, "S12：无可见光圈 → null（键鼠路径不受影响）")
	layer.call("show_cursor", "left", Vector2(100.0, 200.0))
	check_eq(layer.call("get_pointer_pos"), Vector2(100, 200), "S12：show 后返回最近光圈中心（content 坐标）")
	layer.call("show_cursor", "right", Vector2(300.0, 50.0))
	check_eq(layer.call("get_pointer_pos"), Vector2(300, 50), "S12：同帧双侧更新取后迭代侧（right，>= 平局裁决）")
	layer.call("hide_cursor", "right")
	check_eq(layer.call("get_pointer_pos"), Vector2(100, 200), "S12：隐藏侧剔除，回到仍可见侧")
	layer.call("hide_cursor", "left")
	check(layer.call("get_pointer_pos") == null, "S12：两侧全隐 → null")
	layer.queue_free()
	finish()
