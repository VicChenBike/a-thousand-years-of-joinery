extends "res://tests/test_base.gd"
## 批次 AA / W3（spec §6 域 W3 全节 + §22 裁决 2、3；§6.6 R3-a~R3-i）——手势语义重映射与
## 说明文案域 TDD 用例。五个段：
##   段 1（W3-1）缩放双手通用：左掌推拉、右掌推拉均 → palm_begin/zoom_begin/zoom_factor，
##       零 clear（修复前右手 palm → clear 判红，R3-a）。
##   段 2（W3-2，§22 裁决 2）右掌静止 dwell 1.0s 清空：0.9s 零 clear / 连续满 1.0s 恰一次 /
##       位移优先走缩放且该掌态零 clear / 极慢位移 0.02 归一/s → 零 clear（R3-b + §22.4 边界用例）。
##   段 3（W3-4，§22 裁决 3）双手二指对接：同帧 two → 恰一次 join 且两侧零 two_down（R3-d）；
##       单侧 two → two_down 照常、零 join（反向护栏 R3-e）。
##   段 4（W3-3）三指删除：左手三指（无名 0.50 + 小指泄漏 0.60）→ delete 恰一次；
##       右手 three → 零破坏性意图（删除/清空/左键全零）。
##   段 5（W3-5/6/7）文案-实现同源：LEVEL 13 行逐字 = §6.4-A 定稿、全局 4 行 = §6.4-B、
##       SETTLE 追加行 = §6.4-C、行宽红线（LEVEL ≤170 / 全局 ≤212 / SETTLE ≤228 / CATALOG ≤288）、
##       ROW_CLICK 引用数 = 0（W3-7 退役）、每行手势词 → `_classify`/Router 判定分支反向断言；
##       5g = W2 审查 P3-1（EXTEND_TH 死常量零残留）。
##   段 6（W2 审查 P2-1 并入本波）掌态/缩放态小指抖动守卫：缩放态小指降到 0.6 → zoom 不中断、
##       零 delete、zoom_factor 继续；真折叠（<0.40）→ 正常 zoom_end；翻转前置不被打断；
##       右掌 dwell 期间抖动计时不重置（静止满 1.0s 仍恰一次 clear）。
##   段 7（W3 独立审查回修 P2-3）router 级 `_do_zoom_step` 按 `it["side"]` 取**该手**光标位：
##       7a 激活面板在场→右手 zoom 落点=右手光标位（修复前 :737 取 "left" → 落左手陈旧位判红）；
##       7a 护栏→左手 zoom 落点=左手光标位（零回归）；7b 激活面板空+双注册面板→右手命中右面板；
##       7d 右手光标在面板外→落面板**中心**（修复前取左手在板内位→判红）。
## W3 独立审查回修另两件（同文件）：段 2 追加 2f/2g（回修 P2-2：dwell 取消判据并入 **tip 位移**
##       分量——右掌横向平移 palm_size/roll 不变 → 修复前照发 clear 判红；反向护栏=纯静止仍恰一次
##       clear）、段 3 追加 3d（回修 P2-1：双手 two **连续保持 >JOIN_COOLDOWN_SEC 跨冷却过期**
##       恰一次 join——latch 判据被改坏即判红，冷却判据再也遮蔽不住）。
## 夹具口径：map 级合成手 dict + now 注入（零真时钟、零摄像头、零 user://）；文案级直接读
## gesture_hud 常量并按行字体同构（Noto wght400 + spacing −1/−2）量宽——不实例化 HUD。
## 段 7 例外：直调 autoload Game/GestureRouter（仅 `game.set("_state", LEVEL)` 直接置态，
## 零 goto_state/零场景切换/零存档写入），终段全量还原三成员（_state/_active_panel/_cursor_layer
## 与 _last_cursor_pos），零 user:// 纪律依赖；段首 `await process_frame` 让树激活
## （无头实证规律：_initialize 阶段 autoload 绝对路径取节点会报错返回 null）。
## 断言纪律：Variant 直调（禁 as Node/as Control 对 RefCounted）、字典 .get 缺省防御、
## 消息串含 % 一律转义 %%。

# ===== 手指通道夹具（与 test_gesture_map 同构） =====
const F_CURSOR := [0.1, 0.9, 0.1, 0.1, 0.1]
const F_TWO := [0.1, 0.9, 0.9, 0.1, 0.1]
const F_THREE := [0.1, 0.9, 0.9, 0.9, 0.1]
const F_THREE_LEAK := [0.1, 0.9, 0.9, 0.50, 0.60]   # 无名 0.50（W2-6 阈 0.45 内）+ 小指泄漏 0.60
const F_PALM := [0.1, 0.9, 0.9, 0.9, 0.9]            # 小指 0.9 > PALM_PINKY_TH(0.70) → palm
const F_PALM_PINKY_LOW := [0.1, 0.9, 0.9, 0.9, 0.6]  # 四指全伸 + 小指 0.60（∈[0.40,0.70]）→ 泄漏守卫判 three
                                                      # 批次 AA W2 审查 P2-1：缩放/掌态中小指抖动样本
const F_REST := [0.1, 0.1, 0.1, 0.1, 0.1]

const HINT_SRC := "res://scenes/shared/gesture_hud.gd"
const MAP_SRC := "res://scripts/gesture_map.gd"
const ROUTER_SRC := "res://autoload/gesture_router.gd"
const TRACKER_SRC := "res://scripts/gesture_exit_tracker.gd"
const LEVEL_SRC := "res://scenes/level/level_scene.gd"

## §6.4-A：LEVEL 行组定稿（13 行 = 11 手势 + 图例 + 参考框）
const LEVEL_ROWS_EXPECT := [
	"1 移动光标【左/右】食指",
	"2 单击/选块【左/右】食+中",
	"3 减选【右】食+中",
	"4 旋转视角【左】食+中",
	"5 缩放【左/右】手掌推拉",
	"6 删除/挖除【左】食+中+无名",
	"7 清空选择【双手】握拳",   # 批次 AD §4.3.4（2026-09-28 审查回修 P1-1）：清空通路改双手握拳
	# ——旧值留痕：本行原值 "7 清空选择【右】掌静止1秒"（AA W3-2 右掌 dwell 口径，随 §4.3.4 彻底废除退役）
	"8 撤销/重做【左/右】掌翻转",
	"9 对接尝试【双手】食+中",
	"10 退出【双手】四指同翻",
	"11 聚焦/锐眼 走屏幕按钮",
	"食=食指 中=中指 无名=无名指",
	"参考框=推荐活动区",
]
## §6.4-B：全局行组定稿（4 行）
const GLOBAL_ROWS_EXPECT := [
	"左/右手状态 状态条实时显示",
	"移动光标 【左/右】竖起食指",
	"单击确认 【左/右】食指+中指",
	"退出 【双手】四指同翻",
]
## W3-6 反向断言表：[文案行关键字, 判定分支锚（源码子串，全部须在案）]
## ——「文案中提到的每个手势都能在代码中找到对应判定分支」（防文案-实现漂移）。
const SYNC_ROWS := [
	["1 移动光标", ["return \"cursor\"", "\"cursor_move\"", "e[1] and not e[2] and not e[3] and not e[4]"]],
	["2 单击/选块", ["{\"type\": \"two_down\"", "_on_two_down", "if e[1] and e[2] and not e[4]:", "TWO_RING_COUPLE_MAX"]],
	# AC §4.5-1 等价改写：旧分支字面 "e[1] and e[2] and not e[3] and not e[4]" 随连带解耦
	# 合并入 `if e[1] and e[2] and not e[4]:` 三分支块（two/连带豁免/three），锚点换新字面 +
	# 连带常量（判别力不降：分支存在性与分流判据均可核）。
	["3 减选", ["_on_level_two_down", "_push_btn(pos, true, true)", "if side == \"right\":"]],
	["4 旋转视角", ["_level_mode = \"ORBIT\""]],
	["5 缩放", ["\"zoom_begin\"", "\"zoom_factor\"", "\"palm_begin\"", "\"zoom_end\""]],
	["6 删除/挖除", ["{\"type\": \"delete\"", "if side != \"left\":", "return \"three\"", "TWO_MIDDLE_RING_GAP"]],
	# AC §4.5-1 等价改写：旧三指分支字面 "e[1] and e[2] and e[3] and not e[4]" 同上并入新块，
	# `return "three"` 即删除分支的判定出口；TWO_MIDDLE_RING_GAP 为 two/three 分流判据。
	# 批次 AD §4.3.4（2026-09-28 审查回修 P2-6）锚点换新实现：清空=双手握拳
	# （_feed_dual_fist_clear / FIST_FINGER_TH / "side": "both"）。
	# 旧锚留痕（旧口径随 §4.3.4 废除后已非清空通路，锚在会空转假绿）：
	#   ["7 清空选择", ["{\"type\": \"clear\"", "PALM_DWELL_SEC", "side != \"right\""]]
	["7 清空选择", ["{\"type\": \"clear\"", "_feed_dual_fist_clear", "FIST_FINGER_TH", "\"side\": \"both\""]],
	["8 撤销/重做", ["_feed_flip", "{\"type\": \"undo\" if side == \"left\" else \"redo\""]],
	["9 对接尝试", ["{\"type\": \"join\"", "_resolve_two_arbitration", "_join_cooldown_until"]],
	["10 退出", ["{\"type\": \"exit_flip\"", "notify_flip", "_both_present"]],
	["11 聚焦/锐眼", ["__NEGATIVE_FOCUS__"]],
	["单击确认(全局)", ["{\"type\": \"two_down\"", "_menu_click_armed"]],
	["移动光标(全局)", ["return \"cursor\"", "\"cursor_move\""]],
	["退出(全局)四指同翻", ["notify_flip", "_tracker.tick(now, _both_present(data))"]],
	["左右手状态(全局)", ["side_semantic", "SEMANTIC_NAMES"]],
]

# ===== 段 7 夹具（W3 回修 P2-3）：可定位面板 + 滚轮落点 spy（零视口注入、零真鼠标）=====
class _StepPanel extends Control:
	func gesture_panel_rect() -> Rect2:
		return Rect2(global_position, size)

class _WheelSpy extends CanvasLayer:
	## 只记录被 push 的滚轮事件落点（_do_zoom_step 计算出的 pos 即被测对象产出）
	var wheels: Array = []

	func synth_wheel(content_pos: Vector2, dir: int) -> InputEventMouseButton:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_UP if dir > 0 else MOUSE_BUTTON_WHEEL_DOWN
		ev.pressed = true
		ev.position = content_pos
		ev.global_position = content_pos
		return ev

	func push(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb != null:
			wheels.append(mb.position)

func _mhand(conf: float, fingers: Array, roll: float, facing: bool, label: String,
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
	return {"gesture": "", "gesture_id": 0, "confidence": conf,
		"hand_x": tip.x, "hand_y": tip.y, "hand_z": 0.0,
		"hand_rotation_x": roll, "hand_rotation_y": 0.0, "hand_rotation_z": 0.0,
		"fingers": fingers, "pinch_distance": 0.5, "hand_index": 0 if label == "Left" else 1,
		"handedness": label, "landmarks": lm, "fps": 30.0, "is_detected": true,
		"timestamp": ts, "palm_size": ps}

## 左手单侧喂帧（右侧空 → 照常 teardown，不影响左语义）
func _fl(m: Variant, fingers: Array, ps: float, now: float) -> Array:
	return m.feed_frame(_mhand(0.9, fingers, 5.0, true, "Left", ps, Vector2(0.3, 0.4), now), {}, now)

## 右手单侧喂帧
func _fr(m: Variant, fingers: Array, ps: float, now: float) -> Array:
	return m.feed_frame({}, _mhand(0.9, fingers, 5.0, true, "Right", ps, Vector2(0.7, 0.4), now), now)

## 右手单侧喂帧（tip 可控——回修 P2-2「横向平移」用例；_fr 恒 tip=(0.7,0.4) 不足以驱动 tip 位移）
func _fr_tip(m: Variant, fingers: Array, ps: float, tip: Vector2, now: float) -> Array:
	return m.feed_frame({}, _mhand(0.9, fingers, 5.0, true, "Right", ps, tip, now), now)

## 左手单侧喂帧（roll 可控——段 6b 翻腕序列用；_fl 恒 roll=5 不足以驱动翻转）
func _fl_roll(m: Variant, fingers: Array, ps: float, roll: float, now: float) -> Array:
	return m.feed_frame(_mhand(0.9, fingers, roll, true, "Left", ps, Vector2(0.3, 0.4), now), {}, now)

## 双手同帧喂帧（左手先喂，与生产 feed_frame 内部序一致）
func _fb(m: Variant, lf: Array, rf: Array, lps: float, rps: float, now: float) -> Array:
	return m.feed_frame(
		_mhand(0.9, lf, 5.0, true, "Left", lps, Vector2(0.3, 0.4), now),
		_mhand(0.9, rf, 5.0, true, "Right", rps, Vector2(0.7, 0.4), now), now)

func _count(intents: Array, t: String) -> int:
	var n := 0
	for it: Variant in intents:
		if typeof(it) == TYPE_DICTIONARY and String((it as Dictionary).get("type", "")) == t:
			n += 1
	return n

func _sides(intents: Array, t: String) -> Array:
	var out: Array = []
	for it: Variant in intents:
		if typeof(it) == TYPE_DICTIONARY and String((it as Dictionary).get("type", "")) == t:
			out.append(String((it as Dictionary).get("side", "")))
	return out

func _row_font() -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = load("res://fonts/NotoSansSC[wght].ttf")
	fv.variation_opentype = {2003265652: 400}
	fv.spacing_top = -1
	fv.spacing_bottom = -2
	return fv

func _w(fv: Font, text: String, size: int) -> float:
	return fv.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

## 源码去注释（整行/行尾注释剥除）——W3-7「引用数=0」「措辞退场」类源证据断言只对**代码**生效：
## 历史留痕注释允许记载旧常量名/旧措辞，不构成引用。目标 token 不出现于「# 之后的字符串字面量」
## 场景，首个 '#' 截断安全。
func _code_only(src: String) -> String:
	var out: PackedStringArray = []
	for ln: String in src.split("\n"):
		var i: int = ln.find("#")
		out.append(ln if i < 0 else ln.substr(0, i))
	return "\n".join(out)

func _new_map() -> Variant:
	# 批次 AC 4A（spec §4.6-3）：生产语义改**双手协同推拉/间距缩放**，单手掌推拉通道默认关。
	# 本文件段 1/2/6 的「单手掌推拉缩放」存量用例经兼容开关开启历史通道后逐字节照跑
	#（等价改写留痕：断言与时序零变化，仅加一行开关；双手协同缩放**新**语义断言见
	# tests/test_ac_batch4_gesture.gd 段 1）。
	var m: Variant = load(MAP_SRC).new()
	m.call("set_single_hand_zoom_enabled", true)
	return m

func _initialize() -> void:
	print("== test_aa_gesture_remap ==")
	_seg1_zoom_both_hands()
	_seg2_right_palm_dwell()
	_seg3_join_two_hands()
	_seg4_three_finger_delete()
	_seg5_copy_impl_sync()
	_seg6_zoom_pinky_jitter_guard()
	await _seg7_zoom_step_side()
	finish()

# ================= 段 1（W3-1）：缩放改双手通用 =================
func _seg1_zoom_both_hands() -> void:
	var m: Variant = _new_map()
	# 1a 左掌推拉（既有通路回归）
	var a: Array = []
	a.append_array(_fl(m, F_PALM, 0.2, 10.0))
	a.append_array(_fl(m, F_PALM, 0.2, 10.033))
	check_eq(_count(a, "palm_begin"), 1, "1a 前置：左掌双帧确认 → palm_begin 恰一次")
	for i: int in 8:
		a.append_array(_fl(m, F_PALM, 0.24, 10.066 + 0.033 * i))
	check_eq(_count(a, "zoom_begin"), 1, "1a：左掌推拉 → zoom_begin 恰一次")
	check(_count(a, "zoom_factor") > 0, "1a：推拉期 zoom_factor 连续派发（点云/三视图消费）")
	check(_count(a, "zoom_step") > 0, "1a：累计越过 ln(1.10) 台阶 → zoom_step")
	check_eq(_count(a, "clear"), 0, "1a：左掌推拉零 clear")
	# 1b 右掌推拉（W3-1 核心：修复前右手 palm → clear，无 zoom）
	var b: Array = []
	b.append_array(_fr(m, F_PALM, 0.2, 20.0))
	b.append_array(_fr(m, F_PALM, 0.2, 20.033))
	check_eq(_count(b, "palm_begin"), 1, "1b 前置：右掌双帧确认 → palm_begin（与左同链）")
	for i: int in 8:
		b.append_array(_fr(m, F_PALM, 0.24, 20.066 + 0.033 * i))
	check_eq(_count(b, "zoom_begin"), 1,
		"1b：右掌推拉 → zoom_begin（R3-a：修复前右手 palm=清空语义 → 零 zoom_begin 判红）")
	check(_count(b, "zoom_factor") > 0, "1b：右掌 zoom_factor 连续派发")
	check_eq(_count(b, "clear"), 0, "1b：右掌推拉零 clear（取消「右手 palm → 清空」破坏性映射）")

# ================= 段 2（W3-2，裁决 2）：右掌静止 dwell 1.0s 清空 =================
func _seg2_right_palm_dwell() -> void:
	# 2a/2b：静止 0.9s 零 clear；连续满 1.0s 恰一次；其后不重发
	var m: Variant = _new_map()
	var a: Array = []
	a.append_array(_fr(m, F_PALM, 0.2, 30.0))
	a.append_array(_fr(m, F_PALM, 0.2, 30.033))
	check_eq(_count(a, "palm_begin"), 1, "2a 前置：右掌双帧确认入态（dwell 起算锚 = 确认帧）")
	check_eq(_count(a, "clear"), 0, "2a 前置：右掌入态零 clear（R3-b：修复前双帧即 clear 判红）")
	for i: int in 27:   # 30.066 … 30.927（入态后 0.894s，未满 1.0s）
		a.append_array(_fr(m, F_PALM, 0.2, 30.033 + 0.033 * (i + 1)))
	check_eq(_count(a, "clear"), 0, "2a：右掌静止 0.9s → 零 clear（dwell 未满 1.0s）")
	for i: int in 7:    # 30.960 … 31.158（越过 31.033 = 确认帧 +1.0s）
		a.append_array(_fr(m, F_PALM, 0.2, 30.033 + 0.033 * (i + 28)))
	# 批次 AD §4.3.4 等价改写留痕：彻底废除右掌 dwell 清空（改由双手握拳接管），右掌静止满 1.0s 零 clear
	check_eq(_count(a, "clear"), 0, "2b：右掌静止连续满 1.0s → 零 clear（批次 AD §4.3.4 彻底废除右掌 dwell）")
	for i: int in 12:   # 继续静止不重发
		a.append_array(_fr(m, F_PALM, 0.2, 31.30 + 0.033 * i))
	check_eq(_count(a, "clear"), 0, "2b：持续静止恒零 clear（批次 AD §4.3.4 废除 dwell 清空）")
	check(_count(a, "zoom_begin") == 0, "2b：纯静止掌态零 zoom_begin（与 dwell 互斥单一真值）")
	# 2c：位移优先走缩放，该掌态零 clear
	m.reset()
	var b: Array = []
	b.append_array(_fr(m, F_PALM, 0.2, 40.0))
	b.append_array(_fr(m, F_PALM, 0.2, 40.033))
	for i: int in 8:
		b.append_array(_fr(m, F_PALM, 0.24, 40.066 + 0.033 * i))
	check_eq(_count(b, "zoom_begin"), 1, "2c：右掌有位移 → 优先走缩放（zoom_begin 恰一次）")
	check_eq(_count(b, "clear"), 0, "2c：位移掌态零 clear（位移即取消 dwell，裁决 2 ①）")
	for i: int in 40:   # 位移已取消 → 该掌态后续静止 >1.0s 仍零 clear
		b.append_array(_fr(m, F_PALM, 0.24, 40.40 + 0.033 * i))
	check_eq(_count(b, "clear"), 0, "2c：该掌态 dwell 已取消 → 后续静止不再清空（互斥单一真值）")
	# 2d：极慢位移 0.02 归一/s → 零 clear（§22.4 新增边界用例）
	m.reset()
	var c: Array = []
	c.append_array(_fr(m, F_PALM, 0.2, 50.0))
	c.append_array(_fr(m, F_PALM, 0.2, 50.033))
	var t := 50.066
	var ps_end := 0.2
	while t <= 51.20 + 1e-9:
		ps_end = 0.2 + 0.02 * (t - 50.033)   # 0.02 归一/s 极慢位移
		c.append_array(_fr(m, F_PALM, ps_end, t))
		t += 0.033
	check_eq(_count(c, "clear"), 0,
		"2d：极慢位移 0.02 归一/s 持续 1.17s → 零 clear（位移即取消 dwell，边界用例）")
	for i: int in 40:   # 位移取消后静止 >1.0s
		c.append_array(_fr(m, F_PALM, ps_end, 51.23 + 0.033 * i))
	check_eq(_count(c, "clear"), 0, "2d：位移取消后该掌态恒零 clear（裁决 2 ①「该次掌态不产生 clear」）")
	# 2e：左手静止掌态不产生 clear（清空=右掌专属）
	m.reset()
	var d: Array = []
	d.append_array(_fl(m, F_PALM, 0.2, 70.0))
	d.append_array(_fl(m, F_PALM, 0.2, 70.033))
	for i: int in 40:
		d.append_array(_fl(m, F_PALM, 0.2, 70.066 + 0.033 * i))
	check_eq(_count(d, "clear"), 0, "2e：左掌静止 ≥1.3s 零 clear（清空=【右】掌专属，手别门）")
	# 2f（W3 独立审查回修 P2-2）：右掌**横向平移**——palm_size 与 roll 全程不变（不推拉、不翻腕），
	# 仅归一指尖 x 单向平移 0.55→0.68（增益后 ≈0.325）持续 1.2s → 必须零 clear。
	# 现状缺陷（修复前判红）：dwell「静止」判据只算 palm_size 分量 + roll 分量，**无指尖/掌心位置
	# 分量** → 横向平移下两分量恒 0 → dwell 照常计时到点发 clear，与规格裁决 2 ①字面「出现**任意**
	# 位移 → 取消 dwell 并优先走缩放」相悖。
	m.reset()
	var e: Array = []
	var tip_f := Vector2(0.55, 0.4)
	e.append_array(_fr_tip(m, F_PALM, 0.2, tip_f, 140.0))
	e.append_array(_fr_tip(m, F_PALM, 0.2, tip_f, 140.033))
	check_eq(_count(e, "palm_begin"), 1, "2f 前置：右掌双帧确认入态（dwell 起算锚在案）")
	check_eq(_count(e, "clear"), 0, "2f 前置：入态帧零 clear")
	var tf := 140.066
	while tf <= 141.20 + 1e-9:
		var px := 0.55 + 0.13 * ((tf - 140.033) / 1.167)   # 横向单向平移（palm_size/roll 恒定）
		e.append_array(_fr_tip(m, F_PALM, 0.2, Vector2(px, 0.4), tf))
		tf += 0.033
	check_eq(_count(e, "clear"), 0,
		"2f：右掌横向平移 1.2s（palm_size/roll 不变）→ 零 clear（回修 P2-2 红测：修复前只算 palm_size+roll → 照发 clear 判红）")
	check_eq(_count(e, "zoom_begin"), 0, "2f：纯横向平移（无推拉分量）零 zoom_begin（与裁决 2 ①「优先走缩放」的推拉前置不冲突）")
	# 2g（回修 P2-2 反向护栏）：右掌**纯静止**（tip/palm_size/roll 全恒定）1.2s → 仍恰一次 clear
	# ——防 tip 判据改过头把静止 dwell 也一并取消（两向都要守）。
	m.reset()
	var g: Array = []
	var tip_s := Vector2(0.6, 0.45)
	g.append_array(_fr_tip(m, F_PALM, 0.2, tip_s, 160.0))
	g.append_array(_fr_tip(m, F_PALM, 0.2, tip_s, 160.033))
	var tg := 160.066
	while tg <= 161.30 + 1e-9:
		g.append_array(_fr_tip(m, F_PALM, 0.2, tip_s, tg))
		tg += 0.033
		# 批次 AD §4.3.4 等价改写留痕：彻底废除右掌 dwell 清空，右掌纯静止 1.2s 零 clear
		check_eq(_count(g, "clear"), 0,
			"2g：右掌纯静止 1.2s → 零 clear（批次 AD §4.3.4 彻底废除右掌 dwell）")
	check_eq(_count(g, "delete") + _count(g, "two_down") + _count(g, "zoom_begin"), 0,
		"2g：纯静止掌态零 delete/two_down/zoom_begin（意图面无副作用）")

# ================= 段 3（W3-4，裁决 3）：双手二指对接 + 抑制两侧左键 =================
func _seg3_join_two_hands() -> void:
	var m: Variant = _new_map()
	# 3a 双手同帧 two → 恰一次 join、两侧零 two_down
	var a: Array = []
	a.append_array(_fb(m, F_TWO, F_TWO, 0.2, 0.2, 60.0))
	check_eq(_count(a, "two_down"), 0, "3a 前置：单帧未确认零 two_down")
	a.append_array(_fb(m, F_TWO, F_TWO, 0.2, 0.2, 60.033))
	check_eq(_count(a, "join"), 1,
		"3a：双手同帧二指（双帧确认）→ join 恰一次（R3-d：修复前只认 cursor 边沿 → 零 join 判红）")
	check_eq(_count(a, "two_down"), 0,
		"3a：双手同时 two → 两侧零 two_down（左键被抑制；R3-d：修复前左键先发判红）")
	var b: Array = _fb(m, F_TWO, F_TWO, 0.2, 0.2, 60.500)
	check_eq(_count(b, "join"), 0, "3a：持续保持双手二指不重复触发（_join_latched 单真值）")
	var c: Array = _fb(m, F_REST, F_REST, 0.2, 0.2, 60.700)
	check(_count(c, "two_up") >= 1, "3a：双手收指 → two_up 兜底（退出条件明确）")
	# 冷却 1s 窗内新配对不触发；冷却过期后重新触发（join@60.033 → 冷却至 61.033）
	var d: Array = []
	d.append_array(_fb(m, F_TWO, F_TWO, 0.2, 0.2, 60.800))
	d.append_array(_fb(m, F_TWO, F_TWO, 0.2, 0.2, 60.833))
	check_eq(_count(d, "join"), 0, "3a：1s 冷却窗内新配对不触发（JOIN_COOLDOWN_SEC 保持）")
	check_eq(_count(d, "two_down"), 0, "3a：冷却窗内配对同样零 two_down（抑制在冷却态下不失效）")
	var e: Array = _fb(m, F_REST, F_REST, 0.2, 0.2, 61.000)
	e.append_array(_fb(m, F_TWO, F_TWO, 0.2, 0.2, 61.200))
	e.append_array(_fb(m, F_TWO, F_TWO, 0.2, 0.2, 61.233))
	check_eq(_count(e, "join"), 1, "3a：冷却（1s）过后双手二指重新触发 join")
	check_eq(_count(e, "two_down"), 0, "3a：冷却后配对同样零 two_down（抑制规则不随冷却失效）")
	# 3b 反向护栏：单侧 two → two_down 照常（对接不误伤单击/减选）
	m.reset()
	var f: Array = []
	f.append_array(_fb(m, F_TWO, F_REST, 0.2, 0.2, 70.0))
	f.append_array(_fb(m, F_TWO, F_REST, 0.2, 0.2, 70.033))
	check_eq(_count(f, "two_down"), 1, "3b：单侧（左）two → two_down 恰一次（单击零回归，R3-e）")
	check_eq(_count(f, "join"), 0, "3b：单侧 two 零 join")
	check(_sides(f, "two_down").size() == 1 and String(_sides(f, "two_down")[0]) == "left",
		"3b：单侧 two → two_down.side=left")
	m.reset()
	var g: Array = []
	g.append_array(_fb(m, F_REST, F_TWO, 0.2, 0.2, 71.0))
	g.append_array(_fb(m, F_REST, F_TWO, 0.2, 0.2, 71.033))
	check_eq(_count(g, "two_down"), 1, "3b：单侧（右）two → two_down 恰一次（减选笔零回归）")
	check(_sides(g, "two_down").size() == 1 and String(_sides(g, "two_down")[0]) == "right",
		"3b：单侧 two → two_down.side=right（Ctrl 减选笔）")
	check_eq(_count(g, "join"), 0, "3b：单侧 two 零 join")
	# 3c：确认帧窗口——右后侧仅确认中（pend_cls=two）时左不先发；右退出确认 → 左补发单击
	m.reset()
	var h: Array = []
	h.append_array(_fb(m, F_TWO, F_REST, 0.2, 0.2, 80.0))    # 左确认 1（右 rest）
	h.append_array(_fb(m, F_TWO, F_TWO, 0.2, 0.2, 80.033))   # 左确认 2；右确认 1（pend）
	check_eq(_count(h, "two_down"), 0,
		"3c：对侧确认中（pend_cls=two）→ 左 two_down 挂起（不先于对接判定发出）")
	var h2: Array = _fb(m, F_TWO, F_REST, 0.2, 0.2, 80.066)  # 右退出确认
	check_eq(_count(h2, "two_down"), 1, "3c：对侧退出确认 → 左补发 two_down（单击恢复常态）")
	check(_sides(h2, "two_down").size() == 1 and String(_sides(h2, "two_down")[0]) == "left",
		"3c：补发侧 = left")
	# 3d（W3 独立审查回修 P2-1）：双手 two **连续保持 > JOIN_COOLDOWN_SEC(1.0s) 跨冷却过期**——
	# 这是 _join_latched 的**唯一价值**用例。既有 3a 用例持续时长（0.67/0.5/0.4s）全部 <1.0s，
	# 冷却判据完全遮蔽 latch 失效（实证：把 `if not _join_latched:` 改成 `if true:` 后 3a 照样全绿）。
	# 本例 join@100.033 → 冷却至 101.033，双手 two 持续到 101.500（跨冷却过期 0.47s）→ 全程恒 1 次
	# join；随后收指复位 latch，冷却已过的新配对须再触发一次（防「latch 卡死」过修）。
	m.reset()
	var x: Array = []
	x.append_array(_fb(m, F_TWO, F_TWO, 0.2, 0.2, 100.0))
	x.append_array(_fb(m, F_TWO, F_TWO, 0.2, 0.2, 100.033))
	check_eq(_count(x, "join"), 1, "3d 前置：双手同帧二指 → join 恰一次（join@100.033，冷却至 101.033）")
	var tx := 100.066
	while tx <= 101.500 + 1e-9:
		x.append_array(_fb(m, F_TWO, F_TWO, 0.2, 0.2, tx))
		tx += 0.033
	check_eq(_count(x, "join"), 1,
		"3d：双手 two 连续保持 1.47s（跨 JOIN_COOLDOWN_SEC 过期）恒 1 次 join——latch 单真值（改坏 `if not _join_latched:` 即判红）")
	check_eq(_count(x, "two_down"), 0, "3d：持续双手 two 全程零 two_down（抑制不随冷却失效）")
	x.append_array(_fb(m, F_REST, F_REST, 0.2, 0.2, 101.550))
	check(_count(x, "two_up") >= 1, "3d：双手收指 → two_up 兜底（退出条件明确，_join_latched 随之复位）")
	x.append_array(_fb(m, F_TWO, F_TWO, 0.2, 0.2, 101.600))
	x.append_array(_fb(m, F_TWO, F_TWO, 0.2, 0.2, 101.633))
	check_eq(_count(x, "join"), 2,
		"3d 反向护栏：退出 two 后新配对（冷却已过）→ 第二次 join（latch 随退出复位、非卡死）")

# ================= 段 4（W3-3）：三指删除 + 右手 three 零破坏 =================
func _seg4_three_finger_delete() -> void:
	var m: Variant = _new_map()
	var a: Array = []
	a.append_array(_fb(m, F_THREE_LEAK, F_REST, 0.2, 0.2, 10.0))
	a.append_array(_fb(m, F_THREE_LEAK, F_REST, 0.2, 0.2, 10.033))
	# 批次 AD §4.3.2 等价改写留痕：严格三指要求小指弯曲收拢 <= 0.35，小指泄漏 0.60 严禁判 delete
	check_eq(_count(a, "delete"), 0,
		"4a：左手三指小指泄漏 0.60（未收拢 <=0.35）零 delete（批次 AD §4.3.2 严格三指）")
	check_eq(_count(a, "clear"), 0, "4a：三指泄漏不判 palm → 零 clear（小指泄漏守卫）")
	m.reset()
	var b: Array = []
	b.append_array(_fb(m, F_REST, F_THREE_LEAK, 0.2, 0.2, 20.0))
	b.append_array(_fb(m, F_REST, F_THREE_LEAK, 0.2, 0.2, 20.033))
	check_eq(_count(b, "delete"), 0, "4b：右手 three → 零 delete（删除=左手专属）")
	check_eq(_count(b, "clear"), 0, "4b：右手 three → 零 clear（反向护栏：三指不产生清空）")
	check_eq(_count(b, "two_down"), 0, "4b：右手 three → 零 two_down（无左键类合成）")
	check_eq(_count(b, "palm_begin") + _count(b, "zoom_begin"), 0, "4b：右手 three → 零掌态/缩放意图")
	# 标准三指（无泄漏）同款
	m.reset()
	var c: Array = []
	c.append_array(_fb(m, F_THREE, F_REST, 0.2, 0.2, 30.0))
	c.append_array(_fb(m, F_THREE, F_REST, 0.2, 0.2, 30.033))
	check_eq(_count(c, "delete"), 1, "4a：左手标准三指（食+中+无名）→ delete 恰一次")

# ================= 段 5（W3-5/6/7）：文案-实现同源 + 行宽红线 + ROW_CLICK 退役 =================
func _seg5_copy_impl_sync() -> void:
	var hud: GDScript = load(HINT_SRC)
	check(hud != null, "5 前置：gesture_hud.gd 可加载")
	if hud == null:
		return
	var hud_src: String = FileAccess.get_file_as_string(HINT_SRC)
	var map_src: String = FileAccess.get_file_as_string(MAP_SRC)
	var router_src: String = FileAccess.get_file_as_string(ROUTER_SRC)
	var tracker_src: String = FileAccess.get_file_as_string(TRACKER_SRC)
	var level_src: String = FileAccess.get_file_as_string(LEVEL_SRC)
	# 批次 AD 终验补强 F-3（2026-09-28）：5e 反向源锚改经 _code_only 去注释——旧写法直接对含注释
	# 的 all_src（map+router+tracker+level+hud 原文）做 contains，历史留痕注释里记载旧字面/旧
	# 方法名即可满足锚点（注释即绿）。逐文件去注释后再以换行拼接（防文件边界无换行时跨文件
	# 并成一行被 '#' 截断丢锚）。
	var all_code: String = _code_only(map_src) + "\n" + _code_only(router_src) + "\n" \
		+ _code_only(tracker_src) + "\n" + _code_only(level_src) + "\n" + _code_only(hud_src)
	var map_code: String = _code_only(map_src)
	var router_code: String = _code_only(router_src)
	# ---- 5a. LEVEL 13 行逐字（§6.4-A）----
	var lv_rows: Variant = (hud.get("SCENE_HINTS") as Dictionary).get("LEVEL", [])
	check_eq((lv_rows as Array).size(), 13, "5a：LEVEL 恰 13 行（11 手势 + 图例 + 参考框）")
	var lv_ok := true
	var lv_first_bad := ""
	for i: int in mini(13, (lv_rows as Array).size()):
		if String((lv_rows as Array)[i]) != String(LEVEL_ROWS_EXPECT[i]):
			lv_ok = false
			if lv_first_bad.is_empty():
				lv_first_bad = "%d:%s" % [i, String((lv_rows as Array)[i])]
	check(lv_ok, "5a：LEVEL 13 行逐字 = §6.4-A 定稿（循环展开 13；首处不符=%s）" % lv_first_bad)
	# ---- 5b. 全局 4 行 + SETTLE 追加行 ----
	var g_rows: Variant = hud.get("GLOBAL_HINT_ROWS")
	check_eq((g_rows as Array).size(), 4, "5b：全局行组恰 4 行")
	var g_ok := true
	for i: int in mini(4, (g_rows as Array).size()):
		if String((g_rows as Array)[i]) != String(GLOBAL_ROWS_EXPECT[i]):
			g_ok = false
	check(g_ok, "5b：全局 4 行逐字 = §6.4-B 定稿（ROW_G_CLICK 改「食指+中指」全称）")
	var settle_rows: Variant = (hud.get("SCENE_HINTS") as Dictionary).get("SETTLE", [])
	var tail := String((settle_rows as Array)[(settle_rows as Array).size() - 1])
	check_eq(tail, "点选钮【左/右】·拖转/掌缩放【左/右】",
		"5b：SETTLE 追加行 = §6.4-C 定稿（掌缩放改双手通用 →【左/右】）")
	check_eq((settle_rows as Array).size(), 5, "5b：SETTLE 恒 5 行（全局 4 + 点云行）")
	# ---- 5c. ROW_CLICK 退役（W3-7 主推荐：引用数 = 0；留痕注释允许记载旧名，不计引用）----
	var hud_code: String = _code_only(hud_src)
	var rx := RegEx.new()
	rx.compile("ROW_CLICK\\b")
	var click_hits: int = rx.search_all(hud_code).size()
	check_eq(click_hits, 0,
		"5c：ROW_CLICK **代码**引用数 = 0（W3-7 退役；留痕注释另计、ROW_CLICK_SELECT 不计；常量复活即判红）")
	check(not (hud.get_script_constant_map() as Dictionary).has("ROW_CLICK"),
		"5c：ROW_CLICK 已从 gesture_hud 常量表删除（get_script_constant_map 无该键）")
	check(not hud_code.contains("ROW_ACTIVATE") and not hud_code.contains("ROW_SELECT"),
		"5c：ROW_ACTIVATE/ROW_SELECT 随合并退役（代码零引用 → ROW_CLICK_SELECT 单行承载「单击/选块」）")
	check(hud_src.contains("ROW_CLICK_SELECT"), "5c：ROW_CLICK_SELECT 常量在案（合并行）")
	check(hud_src.contains("ROW_LEGEND"), "5c：ROW_LEGEND 图例行常量在案（简写全称承载处）")
	# ---- 5d. 行宽红线（字体与 HUD 行字体同构）----
	var fv: Font = _row_font()
	var level_max := 0.0
	var level_over: Array = []
	for t: String in LEVEL_ROWS_EXPECT:
		var w: float = _w(fv, t, 12)
		level_max = maxf(level_max, w)
		if w > 170.0:
			level_over.append("%s=%.1f" % [t, w])
	check(level_over.is_empty(),
		"5d：LEVEL 每行实测宽 ≤170（双列列宽 clip 红线；最宽 %.1fpx；超宽清单 %s）" % [level_max, level_over])
	var global_max := 0.0
	var global_over: Array = []
	for t: String in GLOBAL_ROWS_EXPECT:
		var w2: float = _w(fv, t, 15)
		global_max = maxf(global_max, w2)
		if w2 > 212.0:
			global_over.append("%s=%.1f" % [t, w2])
	check(global_over.is_empty(),
		"5d：全局行每行实测宽 ≤212（224 hint 净宽红线；最宽 %.1fpx；超宽清单 %s）" % [global_max, global_over])
	var se_w: float = _w(fv, tail, 12)
	check(se_w <= 228.0, "5d：SETTLE 追加行实测宽 ≤228（hint 240 净宽红线；实际 %.1fpx）" % se_w)
	var cat_max := 0.0
	for i: int in [3, 4]:
		var w3: float = _w(fv, String(LEVEL_ROWS_EXPECT[i]), 14)
		cat_max = maxf(cat_max, w3)
	check(cat_max <= 288.0, "5d：CATALOG 追加两行实测宽 ≤288（300 hint 净宽；最宽 %.1fpx）" % cat_max)
	# ---- 5e. 反向断言：文案手势词 → 判定分支逐条命中（W3-6 同源护栏）----
	for row: Array in SYNC_ROWS:
		var anchors: Array = row[1]
		var miss: Array = []
		if String(anchors[0]) == "__NEGATIVE_FOCUS__":
			# 聚焦/锐眼=走屏幕按钮 → 语义层必须无 focus 判定分支（防文案写「手势聚焦」漂移）
			# 批次 AD F-3：负向锚同挂 code-only（注释里出现「func _do_focus」字样不计复活）
			if map_code.contains("{\"type\": \"focus\"") or router_code.contains("func _do_focus"):
				miss.append("focus 意图/方法已复活（应退役）")
		else:
			for a: Variant in anchors:
				if not all_code.contains(String(a)):
					miss.append(String(a))
		check(miss.is_empty(),
			"5e：文案行「%s」→ 判定分支全命中（缺失 %s）" % [String(row[0]), str(miss)])
	# ---- 5f. 手别门与退役词汇源证据 ----
	check(not map_src.contains("\"four\""),
		"5f：gesture_map 无 \"four\" 语义残留（右手 palm→清空旧映射整体退役）")
	check(map_src.contains("side != \"right\""),
		"5f：分指右手门在案（旧锚留痕：AD §4.3.4 前该字面=dwell 清空右手门，现清空=双手握拳；" \
		+ "该字面 residual=掌朝向守卫，仍在案防误删）")
	check(map_src.contains("if side != \"left\":"), "5f：删除左手门在案（删除=【左】三指）")
	check(map_src.contains("_resolve_two_arbitration") and map_src.contains("_join_latched"),
		"5f：双手二指对接仲裁（_resolve_two_arbitration/_join_latched）在案")
	check(not map_src.contains("_join_edges.has(\"left\")") and not map_src.contains("_resolve_join"),
		"5f：旧「双侧 cursor 边沿」join 触发判据（_join_edges.has 双查 + _resolve_join）已移除")
	check(level_src.contains("二指再点空白退出"),
		"5f：ORBIT 提示行改「二指再点空白退出」（§6.4-D 消歧措辞）")
	check(not hud_code.contains("竖四指") and not hud_code.contains("竖三指") \
		and not hud_code.contains("竖中指") and not hud_code.contains("竖食指"),
		"5f：说明栏旧「竖N指」措辞在**代码文案**整体退场（新表用「食/中/无名」简写 + 图例行全称）")
	# ---- 5g. W2 审查 P3-1：EXTEND_TH 死常量（零引用）退役断言（判据=词边界正则，不误伤
	# FINGER_EXTEND_TH / EXTEND_EXIT_TH 两个活常量）----
	var rx2 := RegEx.new()
	rx2.compile("\\bEXTEND_TH\\b")
	check_eq(rx2.search_all(_code_only(map_src)).size(), 0,
		"5g：P3-1 死常量 EXTEND_TH 零残留（词边界判据；活常量 FINGER_EXTEND_TH/EXTEND_EXIT_TH 不受影响）")
	check(map_src.contains("FINGER_EXTEND_TH := [") and map_src.contains("EXTEND_EXIT_TH :="),
		"5g：活常量 FINGER_EXTEND_TH 分指阈数组与 EXTEND_EXIT_TH 滞回退出阈在案（防误删）")
	# ---- 5h. 批次 AD 审查回修 P1-1：清空 HUD 行文案 ↔ _feed_dual_fist_clear 同源锚 ----
	# 新通路双端锁死：文案须指名「【双手】握拳」，实现端须为 _feed_dual_fist_clear 派发
	# clear/side=both——任一侧单独漂移（文案回改「掌静止」或实现更名/删除）即判红。
	# 旧锚留痕：AD 前本段无 5h（旧同源由 SYNC_ROWS「PALM_DWELL_SEC/side != "right"」旧锚承担，
	# 该旧锚随 §4.3.4 废除已改挂新实现，见 SYNC_ROWS 表注）。
	var const_map: Dictionary = hud.get_script_constant_map()
	var clear_row := String(const_map.get("ROW_CLEAR", ""))
	check_eq(clear_row, "7 清空选择【双手】握拳",
		"5h：ROW_CLEAR 文案逐字 = 批次 AD §4.3.4 新口径（旧值留痕「7 清空选择【右】掌静止1秒」）")
	check(clear_row.contains("双手") and clear_row.contains("握拳"),
		"5h：清空文案同时含「双手」+「握拳」（与 _feed_dual_fist_clear 判据同源，防措辞漂移）")
	check(not clear_row.contains("掌静止") and not clear_row.contains("dwell"),
		"5h：清空文案无「掌静止/dwell」残留（右掌 dwell 通路随 §4.3.4 彻底废除，宣传即误导）")
	check(map_src.contains("func _feed_dual_fist_clear") and map_src.contains("\"type\": \"clear\"") \
			and map_src.contains("\"side\": \"both\""),
		"5h：实现端同源在案（_feed_dual_fist_clear 派发 clear side=both）")
	var lv_hint_rows: Array = (hud.get("SCENE_HINTS") as Dictionary).get("LEVEL", [])
	check(not clear_row.is_empty() and lv_hint_rows.has(clear_row),
		"5h：LEVEL 行组实际引用 ROW_CLEAR 常量（文案改一处即全链生效，无硬编码副本）")

# ================= 段 6（W2 审查 P2-1 并入本波）：掌态/缩放态小指抖动不打断 =================
## 现状缺陷（修复前判红）：四指全伸 + 小指 raw 0.60（∈[0.40,0.70]）被小指泄漏守卫判 three →
## 缩放态下一帧即 zoom_end（缩放被抖动中断），左手再经 2 帧确认提交 delete（误删）；掌态
## （翻转前置/右掌 dwell）同理被打断（dwell 锚随语义掉出而丢失 → 永不 clear）。
## 修法：semantic=="palm" 且掌形未真折叠（四指均 ≥FOLD_EXIT_TH=0.40）时，泄漏守卫的 three
## 归一回 palm——保持 zoom/翻转前置/dwell，直到掌形真正折叠到折叠阈。
func _seg6_zoom_pinky_jitter_guard() -> void:
	# 6a：左掌缩放态中小指抖到 0.6 → zoom 不中断、零 delete、zoom_factor 继续
	var m: Variant = _new_map()
	var a: Array = []
	a.append_array(_fl(m, F_PALM, 0.2, 90.0))
	a.append_array(_fl(m, F_PALM, 0.2, 90.033))
	for i: int in 8:
		a.append_array(_fl(m, F_PALM, 0.24, 90.066 + 0.033 * i))
	check_eq(_count(a, "zoom_begin"), 1, "6a 前置：左掌推拉进入缩放态（zoom_begin 恰一次）")
	var j: Array = []
	for i: int in 4:
		j.append_array(_fl(m, F_PALM_PINKY_LOW, 0.24, 90.33 + 0.033 * i))
	check_eq(_count(j, "zoom_end"), 0,
		"6a：缩放态中小指降到 0.6 → zoom 不中断（P2-1 红→绿：修复前单帧即 zoom_end）")
	check_eq(_count(j, "delete"), 0,
		"6a：缩放态小指抖动零 delete（P2-1 红→绿：修复前左手 2 帧确认提交删除）")
	check(_count(j, "zoom_factor") > 0, "6a：抖动期缩放态仍派发 zoom_factor（语义未掉出 palm）")
	check_eq(_count(j, "clear"), 0, "6a：缩放态小指抖动零 clear")
	# 掌形真正折叠（小指 0.1 < FOLD_EXIT_TH 0.40）→ 正常 zoom_end 恰一次
	var f: Array = []
	f.append_array(_fl(m, F_THREE, 0.24, 90.462))
	check_eq(_count(f, "zoom_end"), 1, "6a：掌形真折叠到折叠阈 → 正常 zoom_end 恰一次")
	check_eq(_count(f, "delete"), 0, "6a：折叠首帧零 delete（三指边沿语义待确认帧）")
	f.append_array(_fl(m, F_REST, 0.24, 90.495))
	check_eq(_count(f, "delete"), 0, "6a：折叠后即收指 → 零 delete（确认链被打断）")
	# 6b：左掌态（非缩放）小指抖动不打断翻转前置——抖动零 delete、语义仍 palm、翻腕照常解算 undo
	m.reset()
	var b: Array = []
	b.append_array(_fl_roll(m, F_PALM, 0.2, 5.0, 100.0))
	b.append_array(_fl_roll(m, F_PALM, 0.2, 5.0, 100.033))
	b.append_array(_fl_roll(m, F_PALM_PINKY_LOW, 0.2, 5.0, 100.066))
	b.append_array(_fl_roll(m, F_PALM_PINKY_LOW, 0.2, 5.0, 100.099))
	check_eq(_count(b, "delete"), 0,
		"6b：掌态（翻转前置期）小指抖动零 delete（修复前掉进三指确认链判红）")
	check_eq(String(m.get_side_semantic("left")), "palm",
		"6b：抖动后语义仍=palm（翻转前置态不被小指抖动打断）")
	b.append_array(_fl_roll(m, F_PALM_PINKY_LOW, 0.2, 100.0, 100.133))
	b.append_array(_fl_roll(m, F_PALM_PINKY_LOW, 0.2, 100.0, 100.166))
	b.append_array(_fl_roll(m, F_PALM, 0.2, 100.0, 101.5))   # 距翻转 1.334s > SAME_WINDOW_SEC(1.2) → 窗闭合解算
	check_eq(_count(b, "undo"), 1, "6b：抖动不破坏翻转链——翻腕后窗闭合解算左 undo 恰一次")
	check_eq(_count(b, "zoom_end"), 0, "6b：非缩放掌态小指抖动零 zoom_end（未进缩放不收掌）")
	# 6c：右掌缩放态小指抖动 → zoom 不中断、零 clear、零 delete
	m.reset()
	var c: Array = []
	c.append_array(_fr(m, F_PALM, 0.2, 130.0))
	c.append_array(_fr(m, F_PALM, 0.2, 130.033))
	for i: int in 8:
		c.append_array(_fr(m, F_PALM, 0.24, 130.066 + 0.033 * i))
	check_eq(_count(c, "zoom_begin"), 1, "6c 前置：右掌推拉进入缩放态")
	var j2: Array = []
	for i: int in 4:
		j2.append_array(_fr(m, F_PALM_PINKY_LOW, 0.24, 130.33 + 0.033 * i))
	check_eq(_count(j2, "zoom_end"), 0, "6c：右掌缩放态小指抖动 zoom 不中断")
	check_eq(_count(j2, "clear"), 0, "6c：右掌缩放态小指抖动零 clear（dwell 未被误触发）")
	check_eq(_count(j2, "delete"), 0, "6c：右掌缩放态小指抖动零 delete")
	check(_count(j2, "zoom_factor") > 0, "6c：右掌抖动期 zoom_factor 继续派发")
	# 6d：右掌静止 dwell 期间小指抖动（姿势不动）→ dwell 计时不重置，静止满 1.0s 仍恰一次 clear
	m.reset()
	var d: Array = []
	d.append_array(_fr(m, F_PALM, 0.2, 120.0))
	d.append_array(_fr(m, F_PALM, 0.2, 120.033))
	var k := 0
	var tt := 120.066
	while tt <= 121.10 + 1e-9:
		d.append_array(_fr(m, F_PALM if k % 2 == 0 else F_PALM_PINKY_LOW, 0.2, tt))
		k += 1
		tt += 0.033
	# 批次 AD §4.3.4 等价改写留痕：彻底废除右掌 dwell 清空，小指抖动亦零 clear
	check_eq(_count(d, "clear"), 0,
		"6d：彻底废除右掌 dwell 清空，右掌静止零 clear（批次 AD §4.3.4）")
	check_eq(_count(d, "delete"), 0, "6d：右掌态小指抖动零 delete")
	check_eq(_count(d, "zoom_begin"), 0, "6d：纯静止（含抖动）掌态零 zoom_begin（与 dwell 互斥）")

# ============ 段 7（W3 独立审查回修 P2-3）：_do_zoom_step 按 side 取该手光标位 ============
## 现状缺陷（修复前判红）：`gesture_router.gd` `_do_zoom_step` 忽略 `it["side"]`——`:728`
## `_panel_at(_last_cursor_pos.get("left", …))` 与 `:737` `_last_cursor_pos.get("left", …)`
## 双双写死 "left"。W3-1 之前右手到不了 zoom，该落点只为左手写；现在右手单独掌推拉时滚轮
## 落点会落在**左手陈旧光标位**（或在板外分支被误算成中心）。本段直调 autoload Router，
## 仅 `game.set("_state", LEVEL)` 置态（零场景切换/零存档写入），终段全量还原。
func _seg7_zoom_step_side() -> void:
	# 时序（无头实证规律）：`_initialize` 阶段根尚未激活 → autoload 内
	# `get_node_or_null("/root/Game")` 报「absolute paths from outside the active scene tree」并
	# 返回 null（_semantic_zone 落 "none"、_do_zoom_step 早退），故先 await process_frame 让树激活。
	await process_frame
	var game: Variant = get_root().get_node("Game")
	var router: Variant = get_root().get_node("GestureRouter")
	if game == null or router == null:
		check(false, "7 前置：Game/GestureRouter autoload 在位")
		return
	var prev_state: int = int(game.get("_state"))
	var prev_panel: Variant = router.get("_active_panel")
	var prev_layer: Variant = router.get("_cursor_layer")
	var prev_cpos: Variant = router.get("_last_cursor_pos")
	game.set("_state", int(game.State.LEVEL))   # zone=level：直接置态，不走 goto_state（零场景切换/零存档写入）
	var spy := _WheelSpy.new()
	add_child(spy)
	router.set_cursor_layer(spy)
	check(String(router.call("_semantic_zone")) == "level", "7 前置：zone=level（Game._state 直接置态）")
	var left_pos := Vector2(220.0, 180.0)
	var right_pos := Vector2(820.0, 460.0)
	var p1 := _StepPanel.new()
	p1.position = Vector2.ZERO
	p1.size = Vector2(1152.0, 648.0)
	add_child(p1)
	router.set("_active_panel", p1)
	router.set("_last_cursor_pos", {"left": left_pos, "right": right_pos})
	# ---- 7a 激活面板在场：右手 zoom_step 落点 = 右手光标位（红测本体）----
	router.call("_dispatch", {"type": "zoom_step", "side": "right", "dir": 1})
	check_eq(spy.wheels.size(), 1, "7a 前置：右手 zoom_step → 恰一次滚轮合成推送")
	if spy.wheels.size() == 1:
		check_eq(spy.wheels[0], right_pos,
			"7a：右手 zoom_step 滚轮落点 = 右手光标位（回修 P2-3 红测：修复前写死 \"left\" → 落左手陈旧位判红）")
	# ---- 7a 护栏：左手 zoom_step 落点 = 左手光标位（既有左手语义零回归）----
	router.call("_dispatch", {"type": "zoom_step", "side": "left", "dir": -1})
	check(spy.wheels.size() == 2 and spy.wheels[1] == left_pos,
		"7a 护栏：左手 zoom_step 落点 = 左手光标位（旧语义保持，改 side 后不回退）")
	# ---- 7b 批次 AC 4B（§4.6-1）等价改写：未绑定视口（_active_panel==null）→ **零滚轮**。
	# 旧「激活面板空 → 注册面板回退链」随用户拍板退役：缩放严格受限绑定视口，不再因随手
	# 推拉而缩放某个从未被选中的视口（显式绑定取代回退；旧 X5/Z6-P2-6 回退链为「掌推拉
	# 100% 失效」补丁，AC 4B 以视口隔离根治）。----
	router.set("_active_panel", null)
	var p_left := _StepPanel.new()
	p_left.position = Vector2(160.0, 120.0)
	p_left.size = Vector2(300.0, 240.0)
	add_child(p_left)
	p_left.add_to_group("gesture_panel")
	var p_right := _StepPanel.new()
	p_right.position = Vector2(700.0, 360.0)
	p_right.size = Vector2(360.0, 240.0)
	add_child(p_right)
	p_right.add_to_group("gesture_panel")
	router.call("_dispatch", {"type": "zoom_step", "side": "right", "dir": 1})
	check_eq(spy.wheels.size(), 2,
		"7b 批次 AC 4B §4.6-1：未绑定视口（_active_panel==null）→ 缩放零滚轮（注册面板回退链退役）")
	# 阳性对照：绑定到右手所在视口后同序列 → 落点 = 右手光标位（视口隔离下的正确落点）
	router.set("_active_panel", p_right)
	router.call("_dispatch", {"type": "zoom_step", "side": "right", "dir": 1})
	check_eq(spy.wheels.size(), 3, "7b 对照：绑定右面板后 → 恰一次滚轮（绑定视口内缩放可达）")
	if spy.wheels.size() == 3:
		check_eq(spy.wheels[2], right_pos,
			"7b 对照：落点 = 右手光标位（绑定视口内取该手光标；修复前写死 \"left\" 判红）")
		var rr: Rect2 = p_right.call("gesture_panel_rect")
		check(rr.has_point(spy.wheels[2]), "7b 对照：落点 ∈ 绑定面板矩形（视口隔离）")
	# ---- 7d 右手光标在激活面板**外** → 落点 = 该面板中心（修复前取左手在板内位 → 判红）----
	p1.position = Vector2(500.0, 400.0)
	p1.size = Vector2(200.0, 100.0)
	router.set("_active_panel", p1)
	router.set("_last_cursor_pos", {"left": Vector2(550.0, 420.0), "right": Vector2(100.0, 100.0)})
	var n_before: int = spy.wheels.size()
	router.call("_dispatch", {"type": "zoom_step", "side": "right", "dir": 1})
	check_eq(spy.wheels.size(), n_before + 1, "7d 前置：恰一次滚轮推送")
	if spy.wheels.size() == n_before + 1:
		check_eq(spy.wheels[n_before], Vector2(600.0, 450.0),
			"7d：右手光标在板外 → 落点 = 面板中心 (600,450)（修复前取左手在板内位 → 判红）")
	# ---- 还原：三成员复位 + 夹具节点释放（零残留）----
	router.set("_active_panel", prev_panel)
	router.set("_last_cursor_pos", prev_cpos)
	router.set_cursor_layer(prev_layer)
	game.set("_state", prev_state)
	p_left.free()
	p_right.free()
	p1.free()
	spy.free()
