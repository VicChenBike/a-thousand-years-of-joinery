extends "res://tests/test_base.gd"
## 批次 AA（W2 域，spec §5）：手势稳定性与光标——二级 EMA / 增益 / 死区 / 拇指门 /
## 滞回 / 分指阈值 / 确认计数解耦 / 小指泄漏守卫 / 状态条同源（新件）。
## TDD 口径：本件全部断言在 W2 实现落地前**应判红**（红态证据
## AI工作记录/批次AA_走查_20260925/w2_red_gdscript.txt），实现后转绿。
## 判定锚（spec §5.4 验收 / §5.5 红测清单 R2-a~d/f/i）：
##   R2-a σ=0.005 合成噪声 → 光标 SD 显著下降（同一噪声序列，实测 vs 旧链路参考实现，数值对比）；
##   R2-b 死区击穿最小跳 ≤4.5px（spec §5.4-2 + §23.2.3 第 2 项：4.32 下确界、上界 4.5 紧界）；
##   R2-c 拇指外展帧仍判 cursor（拇指门移除）；
##   R2-d 真手二指稳态（中指 0.42~0.58 摆动）→ 语义恒 two（滞回）；
##   R2-f 置信度单帧跌落 → 确认计数不归零（滑窗多数表决）；
##   R2-i `_profile` 两条平滑路径（filtered / landmark）均真实生效（非死代码）；
##   分指阈值（无名指 0.45）+ 小指泄漏守卫（≤0.70 → three 不 palm）；
##   W2-10 状态条显示名与 GestureMap 语义同源（不再显示 python gesture 名双轨口径）。
## 零摄像头纪律：全部为合成手 dict 直喂 GestureMap / HUD 状态直调，不触 UDP、不触设备。
## 坑位纪律：GestureMap 为 RefCounted → 一律 Variant 直调，禁 `as Node`。

const F_CURSOR := [0.1, 0.9, 0.1, 0.1, 0.1]        # 仅食指（拇指收）
const F_CURSOR_THUMB := [0.9, 0.9, 0.1, 0.1, 0.1]   # 仅食指 + 拇指外展（拇指门红测用）
const F_TWO := [0.1, 0.9, 0.9, 0.1, 0.1]           # 食+中（真手二指基形）
const F_THREE := [0.1, 0.9, 0.9, 0.9, 0.1]         # 食+中+无（小指收）
const F_THREE_LEAK := [0.1, 0.9, 0.9, 0.9, 0.6]    # 三指 + 小指泄漏 0.6（守卫红测用）
const F_RING_SEMI := [0.1, 0.9, 0.9, 0.5, 0.1]     # 三指形但无名指 0.5（AC：连带解耦用例）
const F_RING_TRUE := [0.1, 0.9, 0.9, 0.9, 0.1]     # AC 反向护栏：无名指真实主动伸展 0.9
const F_FOUR := [0.1, 0.9, 0.9, 0.9, 0.9]          # 四指（真四指正例）
const NOISE_N := 300                                 # SD 统计窗（帧数）

var m: Variant   # GestureMap 实例（load 动态引用，Variant 直调）

## 与 python one_euro_filter.OneEuroFilter 同公式的测试内移植（min_cutoff1.2/beta1.7/
## d_cutoff1.0）——把「σ=0.005 原始 landmark 噪声」复现为 tip 通道噪声（含 OE 相关性），
## 使 SD 统计与规格 §5.2 量化口径同源（纯白噪声会高估旧链路 SD，见报告量化表）。
class OEFilter:
	var xp: Variant = null
	var dxp: float = 0.0
	var tp: float = 0.0

	func _alpha(cutoff: float, dt: float) -> float:
		var tau: float = 1.0 / (2.0 * PI * cutoff)
		return 1.0 / (1.0 + tau / dt)

	func filt(x: float, t: float) -> float:
		if xp == null:
			xp = x
			tp = t
			return x
		var dt: float = maxf(t - tp, 1e-6)
		var dx: float = (x - float(xp)) / dt
		var ad: float = _alpha(1.0, dt)
		var dxh: float = ad * dx + (1.0 - ad) * dxp
		var cutoff: float = 1.2 + 1.7 * absf(dxh)
		var a: float = _alpha(cutoff, dt)
		var xh: float = a * x + (1.0 - a) * float(xp)
		xp = xh
		dxp = dxh
		tp = t
		return xh

## 合成手 dict（test_gesture_map 同构；facing 决定掌面朝镜 landmark 布局）
func _hand(fingers: Array, tip: Vector2, conf: float, label: String,
		facing: bool, ts: float) -> Dictionary:
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
	lm[9] = [lm[0][0], lm[0][1] - 0.2, 0.0]
	# 生产口径 = tip_x/tip_y（One Euro 协议字段，src=="filtered" 路径）；landmark 路径用例
	# 须显式 erase 这两键（段 4 landmark 阶跃分支）。
	return {"gesture": "", "gesture_id": 0, "confidence": conf,
		"hand_x": tip.x, "hand_y": tip.y, "hand_z": 0.0,
		"hand_rotation_x": 5.0, "hand_rotation_y": 0.0, "hand_rotation_z": 0.0,
		"fingers": fingers, "pinch_distance": 0.5,
		"hand_index": 0 if label == "Left" else 1, "handedness": label,
		"landmarks": lm, "fps": 30.0, "is_detected": true, "timestamp": ts,
		"palm_size": 0.2, "tip_x": tip.x, "tip_y": tip.y}

func _feed(fingers: Array, tip: Vector2, conf: float, label: String,
		facing: bool, ts: float) -> Array:
	return m.feed_frame(_hand(fingers, tip, conf, label, facing, ts), {}, ts)

func _types(intents: Array) -> Array:
	var out: Array = []
	for it: Variant in intents:
		out.append(String((it as Dictionary).get("type", "")))
	return out

func _has(intents: Array, t: String) -> bool:
	return _types(intents).has(t)

func _first_pos(intents: Array) -> Vector2:
	for it: Variant in intents:
		if String((it as Dictionary).get("type", "")) == "cursor_move":
			return Vector2((it as Dictionary).get("pos", Vector2.ZERO))
	return Vector2(-9.0, -9.0)

## LCG 正态噪声（与报告定标脚本同参数：seed=20260925、乘加常数、逐对 Box-Muller）
func _lcg_normals(n: int, sigma: float, seed_v: int) -> Array:
	var s: int = seed_v
	var out: Array = []
	while out.size() < n:
		s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
		var u1: float = float(s) / 4294967296.0
		s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
		var u2: float = float(s) / 4294967296.0
		if u1 < 1e-12:
			u1 = 1e-12
		var z: float = sqrt(-2.0 * log(u1)) * cos(2.0 * PI * u2)
		out.append(z * sigma)
	return out

## 旧链路参考实现（批次 Z 终态：无二级平滑、死区 0.0035、增益 3.5）——同一 tip 序列
## 下与当前实现做数值对比（「处理前」基准，非自证：两套参数独立于被测实现常量）。
func _ref_old_chain(tips: Array) -> Array:
	var pos := 0.0
	var first := true
	var outs: Array = []
	for tv_v: Variant in tips:
		var t: float = float(tv_v)
		if first:
			pos = t
			first = false
		elif absf(t - pos) >= 0.0035:
			pos = t
		var v: float = (pos - 0.5) * 3.5 + 0.5
		outs.append(clampf(v, -0.15, 1.15))
	return outs

func _sd_px(norms: Array) -> float:
	var n := norms.size()
	if n < 2:
		return 0.0
	var mean := 0.0
	for v_v: Variant in norms:
		mean += float(v_v)
	mean /= float(n)
	var acc := 0.0
	for v_v: Variant in norms:
		var d: float = float(v_v) - mean
		acc += d * d
	return sqrt(acc / float(n - 1)) * 1152.0

func _step_px(norms: Array) -> float:
	if norms.size() < 2:
		return 0.0
	var acc := 0.0
	for i: int in range(1, norms.size()):
		acc += absf(float(norms[i]) - float(norms[i - 1]))
	return acc / float(norms.size() - 1) * 1152.0

func _initialize() -> void:
	print("== test_aa_gesture_stability ==")
	m = load("res://scripts/gesture_map.gd").new()
	var gm: Dictionary = (load("res://scripts/gesture_map.gd") as Script).get_script_constant_map()

	# ---- 段 1：暂定值常量锚（spec §15 #3~#7；批次 AA W2-2/3/1/5/6）----
	check(absf(float(gm.get("CURSOR_GAIN", -1.0)) - 2.5) < 1e-9,
		"W2-2：CURSOR_GAIN=2.5（3.5→2.5 降增益；暂定值·待用户复验）")
	# 批次 AD（§4.1.2 / §4.2）等价改写：CURSOR_DEADZONE 0.0015→0.0003（仅滤硬件微噪）、
	# CURSOR_EMA_ALPHA 0.60→1.0=直通（GDScript 二级低通退役，只依赖 Python 端滤波）、
	# EXTEND_EXIT_TH 0.40→0.45（随中指进入阈回 0.55 保持 0.10 滞后带）。
	# 断言强度保持：常量登记值逐一锁死；段 2~4 的行为期望值**全部由 live 常量推导**
	# （死区 / α / 退出阈均不硬编码旧值），随新值自动等价平移。
	check(absf(float(gm.get("CURSOR_DEADZONE", -1.0)) - 0.0003) < 1e-12,
		"AD §4.1.2：CURSOR_DEADZONE 0.0015→0.0003（1152 折约 0.35px；旧 0.0015=批次 AA W2-3、0.0035=批次 T 留痕）")
	check(absf(float(gm.get("CURSOR_EMA_ALPHA", -1.0)) - 1.0) < 1e-9,
		"AD §4.1.2：CURSOR_EMA_ALPHA 0.60→1.0=直通（消除 Python+GDScript 级联双低通滞后；旧 0.60=批次 AC §4.3-2、0.35=批次 AA W2-1 留痕）")
	check(absf(float(gm.get("EXTEND_EXIT_TH", -1.0)) - 0.45) < 1e-9,
		"AD §4.2：EXTEND_EXIT_TH 0.40→0.45（与中指新进入阈 0.55 保持 0.10 滞后带；旧 0.40=批次 AA W2-5 留痕）")
	var finger_th_v: Variant = gm.get("FINGER_EXTEND_TH", null)
	var ring_th := -1.0
	if typeof(finger_th_v) == TYPE_ARRAY and (finger_th_v as Array).size() >= 5:
		ring_th = float((finger_th_v as Array)[3])
	check(absf(ring_th - 0.48) < 1e-9,
		"AC §4.5-1：FINGER_EXTEND_TH[无名指] 0.45→0.48（与中指同档；W2-6 旧值 0.45 留痕）")
	check(absf(float(gm.get("PALM_PINKY_TH", -1.0)) - 0.70) < 1e-9,
		"W2-6：PALM_PINKY_TH=0.70（小指泄漏守卫：>0.70 才判 palm）")
	check(not gm.has("EMA_FALLBACK_BASE"),
		"W2-1：EMA_FALLBACK_BASE 已退役（:250-254 死代码分支删除，统一为 CURSOR_EMA_ALPHA 单路径）")
	check(not gm.has("EMA_FALLBACK_FAST"),
		"W2-1：EMA_FALLBACK_FAST 已退役（速度自适应双档随死分支一并删除）")
	check(not gm.has("EMA_SPEED_TH"),
		"W2-1：EMA_SPEED_TH 已退役（无死分支即无速度换档判据）")

	# ---- 段 2：映射数值级断言（spec §5.4-1/2/3；断言要求 e）----
	# 批次 AC（§4.4-2）等价改写：纵向中心基准上移 c_y=(0.5+m)/g——纵向采样点绕 c_y 取值，
	# 横向断言（本段主判据）零变化。
	var g: float = float(gm.get("CURSOR_GAIN", 3.5))
	var mo2 := float(gm.get("CURSOR_OVERSHOOT", 0.15))
	var cy2: float = (0.5 + mo2) / g
	var p0: Vector2 = gm_s().apply_cursor_gain(Vector2(0.5, cy2), g)
	var p1: Vector2 = gm_s().apply_cursor_gain(Vector2(0.6, cy2), g)
	var px_per_norm: float = (p1.x - p0.x) / 0.1 * 1152.0
	check(absf(px_per_norm - 2880.0) < 1.0,
		"W2-2：1 归一单位 tip 位移 → 屏幕位移=gain×1152=2880px（x 轴；旧 gain3.5=4032px 留痕）")
	# ---- 回修2（审查 P3-2，spec §23.2.3 第 2 项）：死区击穿上界口径对齐 ----
	# **下确界 = deadzone×gain×1152**（仅当 EMA 输出步恰踩死区时取到），任意可接受输入的实测
	# 跳 **≥ 下确界**。批次 AD（§4.1.2）死区 0.0015→0.0003 → 下确界 4.32px→**0.864px**；
	# 上界随之按「下确界 × 1.042」等比收口（旧 4.5px = 4.32×1.042 同口径，spec §23.2.3 第 2 项
	# 废止的 6.05 宽界仍是留痕）。判据语义（下确界 + 等比上界）逐条保持，仅随常量平移。
	var min_jump_px: float = float(gm.get("CURSOR_DEADZONE", 0.0035)) * g * 1152.0
	var max_jump_px: float = min_jump_px * 1.042
	print("EVID|w2fix_min_jump|deadzone=%.4f gain=%.2f min_jump_px=%.4f（AD 下确界 = 0.0003×2.5×1152）" % [
		float(gm.get("CURSOR_DEADZONE", 0.0035)), g, min_jump_px])
	check(min_jump_px <= max_jump_px and min_jump_px < 4.5,
		"AD §4.1.2：死区击穿最小跳=deadzone×gain×1152=%.4fpx（AD 收窄后远小于旧 4.32px 下确界；移动初始卡顿根治）" % min_jump_px)
	# 批次 AC（§4.4-2）：纵向可达角点须绕新基准 c_y 推导——屏幕 y=0 需 tip_y = c_y−0.5/g，
	# 屏幕 y=1 需 tip_y = c_y+0.5/g（旧「中心 ±0.2 归一回覆盖四角」为 (0.5,0.5) 基准时代口径，
	# 两轴同权；现纵向基准上移 → 采样点等价平移，四角可达语义逐条保持）。
	var c_lo: Vector2 = gm_s().apply_cursor_gain(Vector2(0.3, cy2 - 0.5 / g), g)
	check(c_lo.x <= 0.0001 and c_lo.y <= 0.0001,
		"W2-2：手在（中心 −0.2 归一, 框中心 −0.2 归一）即覆盖屏幕左上角（gain=2.5 四角可达 §5.4-3；AC 纵向基准 c_y）")
	var c_hi: Vector2 = gm_s().apply_cursor_gain(Vector2(0.7, cy2 + 0.5 / g), g)
	check(c_hi.x >= 0.9999 and c_hi.y >= 0.9999,
		"W2-2：手在中心 +0.2 归一回即覆盖屏幕右下角（gain=2.5 四角可达 §5.4-3）")

	# ---- 段 3：死区击穿最小跳（功能级；R2-b）----
	# 批次 AD（§4.1.2）等价改写：α 0.60→1.0、死区 0.0015→0.0003 → 击穿死区所需原始位移
	# = deadzone/α（期望值仍由 live 常量推导，判据「单帧击穿位移 = deadzone×1.04 归一 × gain×1152」
	# 逐条保持，只是量级随常量收窄 5 倍）。旧口径留痕：α0.60×dz0.0015 → 实测 4.4928px ∈(4.32,4.5]。
	var dz := float(gm.get("CURSOR_DEADZONE", 0.0015))
	var alpha_s := float(gm.get("CURSOR_EMA_ALPHA", 0.35))
	var raw_step: float = (dz * 1.04) / alpha_s
	var lo_px: float = dz * float(gm.get("CURSOR_GAIN", 2.5)) * 1152.0
	var hi_px: float = lo_px * 1.042
	m.reset()
	var j0: Array = _feed(F_CURSOR, Vector2(0.5, 0.5), 0.9, "Left", true, 10.0)
	var j1: Array = _feed(F_CURSOR, Vector2(0.5 + raw_step, 0.5), 0.9, "Left", true, 10.033)
	var jump_px: float = absf(_first_pos(j1).x - _first_pos(j0).x) * 1152.0
	print("EVID|w2fix_deadzone_breakthrough|raw_step=%.5f jump_px=%.4f（AD 下确界 %.4f / 上界 %.4f；α=%.2f dz=%.4f）" % [
		raw_step, jump_px, lo_px, hi_px, alpha_s, dz])
	check(jump_px > lo_px and jump_px <= hi_px,
		"AD §4.1.2：死区边界单帧击穿位移∈(%.4f,%.4f]px（下确界=deadzone×gain×1152=%.4f；AD 死区收窄后判据量级等比 5 倍收窄，语义逐条保持；旧 α0.60 下确界 4.32px 口径留痕）"
		% [lo_px, hi_px, lo_px])

	# ---- 段 4：二级 EMA 阶跃响应 + 两条平滑路径均非死代码（W2-1；R2-i）----
	m.reset()
	var s0: Array = _feed(F_CURSOR, Vector2(0.5, 0.5), 0.9, "Left", true, 20.0)
	var s1: Array = _feed(F_CURSOR, Vector2(0.6, 0.5), 0.9, "Left", true, 20.033)
	var full_px: float = 0.1 * float(gm.get("CURSOR_GAIN", 3.5)) * 1152.0
	var step1_px: float = absf(_first_pos(s1).x - _first_pos(s0).x) * 1152.0
	var ratio_f: float = step1_px / maxf(full_px, 0.0001)
	check(absf(ratio_f - alpha_s) <= 0.03,
		"AD §4.1.2：filtered 路径阶跃第 1 帧到位 %.0f%%±3%%（α=%.2f；AD α=1.0 即直通=消除级联低通；旧 α0.60 到位 60%% / α0.35 到位 35%% 留痕）" % [alpha_s * 100.0, alpha_s])
	var s_conv := Vector2(-9, -9)
	for i: int in 20:
		s_conv = _first_pos(_feed(F_CURSOR, Vector2(0.6, 0.5), 0.9, "Left", true, 20.066 + 0.033 * float(i)))
	var exp_final: float = (0.6 - 0.5) * float(gm.get("CURSOR_GAIN", 3.5)) + 0.5
	check((s_conv.x - 0.5) / maxf(exp_final - 0.5, 0.0001) >= 0.97,
		"W2-1：阶跃 20 帧后收敛到位 ≥97%（低通不滞留；死区地板 0.0003 归一在容差内）")
	# landmark 路径（显式剔除 tip_x/tip_y → src=="landmark"）同款阶跃：与 filtered 同一 α
	m.reset()
	var l0: Dictionary = _hand(F_CURSOR, Vector2(0.5, 0.5), 0.9, "Left", true, 21.0)
	var l1: Dictionary = _hand(F_CURSOR, Vector2(0.6, 0.5), 0.9, "Left", true, 21.033)
	l0.erase("tip_x")
	l0.erase("tip_y")
	l1.erase("tip_x")
	l1.erase("tip_y")
	var lp0: Array = m.feed_frame(l0, {}, 21.0)
	var lp1: Array = m.feed_frame(l1, {}, 21.033)
	var ratio_l: float = absf(_first_pos(lp1).x - _first_pos(lp0).x) * 1152.0 / maxf(full_px, 0.0001)
	check(absf(ratio_l - alpha_s) <= 0.03,
		"AD §4.1.2/R2-i：landmark 路径阶跃第 1 帧到位 %.0f%%±3%%（与 filtered 同一 α；旧速度自适应 α=0.70 双档死分支留痕）" % (alpha_s * 100.0))

	# ---- 段 5：光标 SD 定量（R2-a；同一噪声序列，实测 vs 旧链路参考实现）----
	# 批次 AC（§4.3-2）等价改写：α 0.35→0.60 主动换响应速度（用户「快速移动 3~5 帧严重滞后」
	# 为更高优先级缺陷），SD/步长判据随之等价平移（仍为**同一噪声序列下与旧链路参考实现的
	# 数值对比**，非自证式）：
	#   · SD ≤ 7.0px（旧判据 6.0px，α0.35 时代；实测 5.75px）且 ≤0.80×旧链路；
	#   · 平均步长 ≤1.10px（旧 0.60px；实测 0.968px，仍显著低于旧链路 0.715px 的 1.35 倍——
	#     响应换速度是本批**用户拍板的有意取向**，见 spec §4.3-2/D3）。
	var noise: Array = _lcg_normals(NOISE_N, 0.005, 20260925)
	var oe := OEFilter.new()
	var tips: Array = []
	for i: int in NOISE_N:
		tips.append(oe.filt(0.5 + float(noise[i]), float(i) / 30.0))
	var measured: Array = []
	m.reset()
	for i: int in NOISE_N:
		var h: Dictionary = _hand(F_CURSOR, Vector2(float(tips[i]), 0.5), 0.9, "Left", true, 30.0 + 0.033 * float(i))
		var its: Array = m.feed_frame(h, {}, 30.0 + 0.033 * float(i))
		if _has(its, "cursor_move"):
			measured.append(_first_pos(its).x)
	var ref_norms: Array = _ref_old_chain(tips)
	check_eq(measured.size(), NOISE_N,
		"R2-a 前置：300 帧全部产出 cursor_move（光标语义稳定）")
	var sd_ref: float = _sd_px(ref_norms)
	var sd_meas: float = _sd_px(measured)
	var st_ref: float = _step_px(ref_norms)
	var st_meas: float = _step_px(measured)
	print("EVID|w2_sd|seed=20260925 n=300 sigma=0.005 | OLD_ref_sd=%.2fpx NEW_sd=%.2fpx | OLD_ref_step=%.3f NEW_step=%.3f | ratio_sd=%.2f ratio_step=%.2f" % [
		sd_ref, sd_meas, st_ref, st_meas, sd_meas / maxf(sd_ref, 0.0001), st_meas / maxf(st_ref, 0.0001)])
	check(sd_ref >= 7.0,
		"R2-a 基准自检：旧链路参考实现 SD≥7.0px（与规格 §5.2 「7.1px」口径同量级，参考实现非空转）")
	check(sd_meas <= 7.0,
		"AC §4.3-2：光标 SD≤7.0px（α0.60 提速后的等价判据，实测见 EVID；W2-1 α0.35 旧判据 6.0px 留痕）")
	check(sd_meas <= 0.80 * sd_ref,
		"AD §4.1.2：同一噪声序列 SD 较旧链路下降 ≥20%（上游 One Euro 滤波实效；数值对比，非「调用了平滑」式自证）")
	# 批次 AD（§4.1.2）等价改写：α 0.60→**1.0 直通** → GDScript 侧不再附加低通，平滑职责已
	# 全部前移到 Python 端（One Euro tip + LandmarkSmoother，本段以 OEFilter 实例模拟）。
	# 旧判据「平均步长 ≤1.10px 且 ≤1.45×旧链路」是**低通存在性**代理（α0.60 实测 0.968px）；
	# 其在新架构下的等价判据=「GDScript 输出步长与上游输出步长**等值**（直通零附加滞后）」——
	# 同一条「防失控」判据，改为直接量测本侧透明性（更强的针对性，非放宽）。
	var mapped_in: Array = []
	for tv: Variant in tips:
		mapped_in.append((float(tv) - 0.5) * float(gm.get("CURSOR_GAIN", 2.5)) + 0.5)
	var st_in: float = _step_px(mapped_in)
	var dz_floor_px: float = float(gm.get("CURSOR_DEADZONE", 0.0003)) * float(gm.get("CURSOR_GAIN", 2.5)) * 1152.0
	print("EVID|ad1_passthrough|in_step=%.3f out_step=%.3f ratio=%.4f（AD α=1.0 直通；旧 α0.60 out_step=0.968 / 旧链路 ref=0.715 留痕）" % [
		st_in, st_meas, st_meas / maxf(st_in, 0.0001)])
	check(st_in > 0.0, "R2-a 基准自检：上游输出步长非零（直通等值判据的对照基准非空转）")
	check(st_meas <= st_in,
		"AD §4.1.2：GDScript 侧 α=1.0 直通**不附加滞后**——输出步长 ≤ 上游输出步长（实测 %.3f vs %.3f；旧 α0.60 会显著低于上游=级联低通滞后，判据 ≤1.10px/≤1.45× 留痕）" % [st_meas, st_in])
	check((st_in - st_meas) <= dz_floor_px,
		"AD §4.1.2：直通步长与上游的差值**全部归因于死区锁微噪**（差值 %.4f ≤ 死区折算 %.4fpx；死区仅滤硬件微噪，无其它衰减通路）" % [st_in - st_meas, dz_floor_px])
	# 第三判据（旧「≤1.45×旧链路」的直通等价物）：**直通不得放大单帧步长**——输出最大单帧
	# 步长 ≤ 输入最大单帧步长（直通系统的不放大不变量；比「与旧链路比倍数」更具针对性）。
	var max_in_step: float = 0.0
	for i: int in range(1, mapped_in.size()):
		max_in_step = maxf(max_in_step, absf(float(mapped_in[i]) - float(mapped_in[i - 1])))
	var max_out_step: float = 0.0
	for i: int in range(1, measured.size()):
		max_out_step = maxf(max_out_step, absf(float(measured[i]) - float(measured[i - 1])))
	print("EVID|ad1_step_bound|max_in_step=%.4f max_out_step=%.4f" % [max_in_step, max_out_step])
	check(max_out_step <= max_in_step + 1e-9,
		"AD §4.1.2：α=1.0 直通不放大单帧步长（输出最大步长 %.4f ≤ 输入最大步长 %.4f；旧「≤1.45×旧链路」判据在直通架构下的等价物）" % [
			max_out_step, max_in_step])

	# ---- 段 6：cursor 拇指门移除（W2-4；R2-c；断言要求 b）----
	m.reset()
	var t_in: Array = _feed(F_CURSOR_THUMB, Vector2(0.4, 0.6), 0.9, "Left", true, 40.0)
	check(_has(t_in, "cursor_move"),
		"W2-4：仅食指+拇指外展 0.9 首帧即判 cursor（拇指不管口径与文件头 §7-9 对齐；旧 `not e[0]` 拇指门判 rest 判红）")
	m.reset()
	var th_seq := [0.1, 0.7, 0.9]
	var th_ok := true
	var ts_f := 41.0
	for v_v: Variant in th_seq:
		var fh: Dictionary = _hand([float(v_v), 0.9, 0.1, 0.1, 0.1], Vector2(0.4, 0.6), 0.9, "Left", true, ts_f)
		var its2: Array = m.feed_frame(fh, {}, ts_f)
		if not _has(its2, "cursor_move"):
			th_ok = false
		ts_f += 0.033
	check(th_ok,
		"W2-4：拇指 0.1→0.7→0.9 漂移全程 cursor 语义保持（大幅斜移光标不冻结；旧掉 rest 判红）")

	# ---- 段 7：cursor/two 滞回（W2-5；R2-d；断言要求 c）----
	# 批次 AD（§4.2）等价改写：进入阈 0.55（不动）、**退出阈 0.40→0.45** → 滞回带由
	# [0.40,0.55) 平移为 **[0.45,0.55)**，摆动序列随带下沿等比上移 0.05（0.41~0.58 → 0.46~0.58）
	# ——「带内摆动零 two_up / 零重复 two_down / two_move 每帧在」三条判据与帧数逐条不变。
	m.reset()
	var h2 := F_TWO.duplicate()
	h2[2] = 0.58   # 真手二指中指 0.6191 ± 波动下沿附近（≥0.55 进入）
	_feed(h2, Vector2(0.5, 0.4), 0.9, "Left", true, 50.0)
	var tb: Array = _feed(h2, Vector2(0.5, 0.4), 0.9, "Left", true, 50.033)
	check(_has(tb, "two_down"), "R2-d 前置：中指 0.58×2 帧 → two_down（进入态建立）")
	var osc: Array = [0.47, 0.58, 0.48, 0.54, 0.46, 0.57, 0.47, 0.52,
		0.49, 0.58, 0.46, 0.55, 0.48, 0.53, 0.47, 0.50]
	var ups := 0
	var downs := 0
	var moves := 0
	var ts_o := 50.10
	for v_v: Variant in osc:
		var oh: Dictionary = _hand([0.1, 0.9, float(v_v), 0.1, 0.1], Vector2(0.5, 0.4), 0.9, "Left", true, ts_o)
		var its3: Array = m.feed_frame(oh, {}, ts_o)
		if _has(its3, "two_up"):
			ups += 1
		if _has(its3, "two_down"):
			downs += 1
		if _has(its3, "two_move"):
			moves += 1
		ts_o += 0.033
	check_eq(ups, 0,
		"R2-d：中指 0.46~0.58 摆动 16 帧零 two_up（AD 滞回出阈 0.45，带 [0.45,0.55) 内保持上帧；旧 [0.40,0.55) 带与 0.41~0.58 摆动随阈值等价平移留痕）")
	check_eq(downs, 0, "R2-d：摆动期零重复 two_down（无 cursor↔two 来回翻转）")
	check_eq(moves, osc.size(),
		"R2-d：摆动期 two_move 每帧在（语义恒 two，零冻结）")

	# ---- 段 8：确认计数与置信度门解耦（W2-7；R2-f；断言要求 d）----
	m.reset()
	var confs: Array = [0.60, 0.50, 0.60, 0.50, 0.60, 0.50, 0.60, 0.50]
	var td_at := -1
	var td_cnt := 0
	var ts_c := 60.0
	for i: int in confs.size():
		var ch: Dictionary = _hand(F_TWO, Vector2(0.5, 0.4), float(confs[i]), "Left", true, ts_c)
		var its4: Array = m.feed_frame(ch, {}, ts_c)
		if _has(its4, "two_down"):
			td_cnt += 1
			if td_at < 0:
				td_at = i
		ts_c += 0.033
	check(td_at >= 0,
		"R2-f：置信度 0.60/0.50 交替摆动仍完成确认（旧单帧 0.50<0.55 即归零 → 永不确认判红）")
	check(td_at >= 0 and td_at <= 4,
		"R2-f：确认在有限帧内完成（≤5 帧；滑窗 CONFIRM_FRAMES+1 多数表决）")
	check_eq(td_cnt, 1, "R2-f：交替序列恰一次 two_down（无重复提交）")

	# ---- 段 9：小指泄漏守卫（W2-6；R2-e）→ 批次 AD §4.3.2 等价改写（严格三指收紧）----
	# W2-6 旧口径：三指形 + 小指泄漏 ≤0.70 仍判 three（做删除时小指误伸不成 palm/清空）。
	# 批次 AD §4.3.2 有意收紧：删除须**严格三指**（食/中/无名 ≥0.55 且小指收拢 ≤THREE_PINKY_FOLD_MAX=0.35），
	# 小指 0.6（>0.35）不再判 three/delete（防四指平展误触发批量删除）；真三指（小指 ≤0.35）仍 delete 可达。
	# 断言拆二（1→2，只增不减）：①泄漏 0.6 → 零 delete（旧「three=delete」收紧留痕）②真三指（小指 0.1≤0.35）→ delete 照常。
	m.reset()
	var lk := 0
	for i: int in 2:
		var lh: Dictionary = _hand(F_THREE_LEAK, Vector2(0.5, 0.4), 0.9, "Left", true, 70.0 + 0.033 * float(i))
		var its5: Array = m.feed_frame(lh, {}, 70.0 + 0.033 * float(i))
		if _has(its5, "delete"):
			lk += 1
	check_eq(lk, 0,
		"AD §4.3.2 收紧：左手三指+小指泄漏 0.6（>0.35）→ 零 delete（旧 W2-6「泄漏≤0.70→three=delete」随严格三指收拢门退役留痕）")
	m.reset()
	var lk_strict := 0
	for i: int in 2:
		var ls: Dictionary = _hand(F_THREE, Vector2(0.5, 0.4), 0.9, "Left", true, 70.2 + 0.033 * float(i))   # 小指 0.1≤0.35
		var its5s: Array = m.feed_frame(ls, {}, 70.2 + 0.033 * float(i))
		if _has(its5s, "delete"):
			lk_strict += 1
	check(lk_strict >= 1,
		"AD §4.3.2 正例：严格三指（食/中/无名≥0.55 且小指 0.1≤0.35）→ three=delete 可达（守卫不破真删除姿势）")
	m.reset()
	var clear_seen := false
	var ts_k := 71.0
	for i: int in 2:
		var rh: Dictionary = _hand(F_THREE_LEAK, Vector2(0.5, 0.4), 0.9, "Right", true, ts_k)
		var its6: Array = m.feed_frame({}, rh, ts_k)   # 右手必须喂右槽（手 dict 位置=侧别）
		if _has(its6, "clear"):
			clear_seen = true
		ts_k += 0.033
	check(not clear_seen,
		"R2-e：右手三指+小指泄漏 → 零 clear（旧判 palm→清空破坏性误触判红）")
	m.reset()
	# 批次 AA W3-2 旧口径：右掌静止 dwell 满 1.0s → 恰一次 clear（清空选择新通路）。
	# 批次 AD §4.3.4 有意变更：**彻底废除右掌 dwell 清空**（清空改由双手握拳接管，见 test_ad_batch3_interaction 段 A）。
	# 断言拆二（2→2，条数不减，判据反置留痕）：①入态 0.9s 内零 clear（旧「双帧即 clear」退役留痕，语义不变）
	#   ②满 1.0s 亦零 clear（旧「静止 dwell 提交」随 §4.3.4 废除留痕——正例反置为「全窗零 clear」）。
	var fc_early := false
	var fc_seen := false
	var ts_g := 72.0
	for i: int in 40:
		var gh: Dictionary = _hand(F_FOUR, Vector2(0.5, 0.4), 0.9, "Right", true, ts_g)
		var its7: Array = m.feed_frame({}, gh, ts_g)
		if _has(its7, "clear"):
			if ts_g < 73.0:
				fc_early = true
			fc_seen = true
		ts_g += 0.033
	check(not fc_early,
		"W3-2 正例：真四指右掌入态 0.9s 内零 clear（旧「双帧即 clear」退役留痕）")
	check(not fc_seen,
		"AD §4.3.4 废除：真四指（小指 0.9>0.70）右掌静止满 1.0s → 零 clear（旧 W3-2「静止 dwell 提交 clear」随右掌 dwell 清空彻底废除留痕；清空改双手握拳）")

	# ---- 段 10：分指阈值（W2-6 ring 0.45 → 批次 AC §4.5-1 连带解耦；断言要求 c）----
	# 批次 AC 等价改写（2026-09-27，spec §4.5-1/D5）：无名指 extend=0.50 且中指 0.90
	# （差值 0.40 ≥ TWO_MIDDLE_RING_GAP=0.12、≤ TWO_RING_COUPLE_MAX=0.65）→ 现判 **two**
	# （中指主动 + 无名指被肌腱连带抬起），不再判 three。W2-6 时代「0.45 阈放宽让半伸无名指
	# 落入 three」的语义被本批**有意反转**（竖中指单击灵敏优先，见 D5）；真三指（无名指主动
	# 伸展 >0.65 或与中指齐平）仍判 three——反向护栏见本段与 test_ac_batch3_algo 段 C。
	m.reset()
	var rg := 0
	var rg_two := 0
	for i: int in 2:
		var xh: Dictionary = _hand(F_RING_SEMI, Vector2(0.5, 0.4), 0.9, "Left", true, 80.0 + 0.033 * float(i))
		var its8: Array = m.feed_frame(xh, {}, 80.0 + 0.033 * float(i))
		if _has(its8, "delete"):
			rg += 1
		if _has(its8, "two_down"):
			rg_two += 1
	check_eq(rg, 0,
		"AC §4.5-1：无名指 extend=0.50（≤0.65 且落后中指 0.40）→ **判 two 非 three**（W2-6 旧断言「判 three=delete」随连带解耦反转留痕；竖中指单击灵敏优先=D5）")
	check(rg_two >= 1,
		"AC §4.5-1：该连带态双帧确认 → two_down（食指瞄准后竖中指单击通路打通）")
	m.reset()
	var rg3 := 0
	for i: int in 2:
		var xh3: Dictionary = _hand(F_RING_TRUE, Vector2(0.5, 0.4), 0.9, "Left", true, 80.2 + 0.033 * float(i))
		var its9: Array = m.feed_frame(xh3, {}, 80.2 + 0.033 * float(i))
		if _has(its9, "delete"):
			rg3 += 1
	check(rg3 >= 1,
		"AC §4.5-1 反向护栏：无名指真实主动伸展 0.90（>0.65）→ 仍判 three=delete（三指删除语义零损失）")
	m.reset()
	var t2a: Array = _feed(F_TWO, Vector2(0.5, 0.4), 0.9, "Left", true, 81.0)
	var t2b: Array = _feed(F_TWO, Vector2(0.5, 0.4), 0.9, "Left", true, 81.033)
	check(_has(t2b, "two_down") and not _has(t2b, "delete"),
		"W2-6 正例：无名指 0.1（收）二指形恒 two（分指阈值不破 two 姿态）")

	# ---- 段 11：状态条显示名与游戏动作同源（W2-10；断言要求 g 前置）----
	await process_frame
	var hud: Control = load("res://scenes/shared/gesture_hud.tscn").instantiate()
	add_child(hud)
	await process_frame
	await process_frame
	var bridge: Variant = get_root().get_node("GestureBridge")
	var rt: Variant = get_root().get_node("GestureRouter")
	var svm: Variant = get_root().get_node("SaveManager")
	if typeof(svm.get_settings()) == TYPE_DICTIONARY:
		(svm.get_settings() as Dictionary)["gesture_input"] = true   # 内存态置真，零落盘
	bridge._set_state(1)   # READY（feed 守卫链门）
	rt.call("_setup")
	var hsd := {"left": _hand(F_CURSOR, Vector2(0.4, 0.6), 0.9, "Left", true, 90.0),
		"right": null, "timestamp": 0.0}
	rt.call("feed", hsd)
	check(rt.has_method("side_semantic"),
		"W2-10：GestureRouter.side_semantic 接口在位（HUD 状态名消费源）")
	if rt.has_method("side_semantic"):
		check_eq(String(rt.call("side_semantic", "left")), "cursor",
			"W2-10 前置：语义层左=cursor（feed 后状态可读）")
	var hstate := {"left": _hand(F_CURSOR, Vector2(0.4, 0.6), 0.9, "Left", true, 90.0),
		"right": null, "timestamp": 0.0}
	hstate["left"]["gesture"] = "point"   # python 侧双轨名（0.6/0.7 严阈口径）——不得再显示
	hud.call("_on_state", hstate)
	var name_label: Label = hud.get_node("StatusRow/LeftPanel/VBox/LeftLabel")
	check_eq(String(name_label.text), "光标",
		"W2-10：状态条显示名=语义层动作名「光标」（与 _classify 同源；旧显 python gesture 名双轨判红）")
	check(String(name_label.text) != "point",
		"W2-10：状态条不再显示 python gesture_id 双轨名")
	hud.queue_free()
	finish()

func gm_s() -> Variant:
	return load("res://scripts/gesture_map.gd")
