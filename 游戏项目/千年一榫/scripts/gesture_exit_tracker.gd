class_name ExitGestureTracker
extends RefCounted
## 批次 R：双手四指同翻 ×4 退出倒数状态机（spec §6.2）。
## 批次 Y（Y-A2，spec §2-②拍板）：首翻**当帧立即**弹出（FIRST_DELAY_SEC=0.6 退役），此后
## 每次翻转**立即**刷新且剩余数字减 1（3→2→1），每次刷新重置 4.5 秒停留（TIMEOUT_SEC，批次 Z Z5-6 由 3.0 调至 4.5）——旧「0.6s 首显延迟/
## 0.3s 刷新延迟/迟到显示宽限」三件延迟机制整体退役（弹条改顶部常显长条，见 gesture_exit_dialog）。
## 批次 Y（Y-A9，spec §2-⑨）：HAND_LOST_CANCEL_SEC 0.5→0.8（与 hold 窗 0.3s 对齐放宽，常量可调；
## held 帧计为 both_present 的映射在 Router/_both_present——防抖只在真离场超窗后触发）。
## 时间由调用方注入（now 秒）；Router 持有本实例并转发信号给退出弹条/分流。
## 信号：countdown_started(remaining=3) / countdown_changed(2|1) /
##       countdown_cancelled("timeout"|"hand_lost") / exit_confirmed（恰一次）。

const TIMEOUT_SEC := 4.5            # 批次 Z（Z5-6，spec §5-6 拍板）：4.5 秒无新同翻取消（旧 3.0 退役留痕；
                                    # 计时器每次同翻后重置=「每次刷新重置 4.5s 停留」）
const HAND_LOST_CANCEL_SEC := 2.0   # 批次 AC 4A（spec §4.6-7，2026-09-27 用户实机反馈）：双手翻掌侧立
                                    # 瞬间 MediaPipe 短暂丢帧（侧立盲区）→ 旧 0.8s 防抖窗过短会令倒数
                                    # **中途归零**（用户「翻 4 次才弹一次」主因之一）。延长至 2.0s 容忍
                                    # 整个侧立盲区（单次翻转动作全程 ≈0.5~1.0s，2.0s 足够覆盖一次完整
                                    # 翻转+回正），本次 4 次同翻序列不再被瞬时丢帧打断（3→2→1→触发退出）。
                                    # 留痕：批次 Y（Y-A9）0.5→0.8（与 python hold 窗 0.6s 对齐）；
                                    # 1.5s 侧立空窗不重置倒数由 tests/test_ac_batch4_gesture 段 4 红锁。

signal countdown_started(remaining: int)
signal countdown_changed(remaining: int)
signal countdown_cancelled(reason: String)
signal exit_confirmed

var _remaining := 0
var _last_flip_at := -1.0
var _lost_since := -1.0       # 离场防抖锚点=最后确认在场时刻（同翻帧或双手 tick 帧）
var _last_present_at := -1.0  # 最后确认双手在场时刻（防抖基准，计划 R-C-2 实测口径：离场时长自主翻/最近在场帧起算）
var _done := false

func reset() -> void:
	# 修复批 P3（2026-09-26）：仅倒数活跃（_remaining>0，即 countdown_started 已发且未收尾）
	# 才补发 countdown_cancelled("reset")——旧码无条件 emit，禁用期 blocked 包每包 reset 打出
	# N 连发。清态语义不变（全字段照清）；「倒数中切场景 → 弹条收起」的 P1-8b 主诉求保留
	#（活跃才需要收，非活跃时弹条本就不在场、main 侧幂等 hide 无事可做）。
	var had_active := _remaining > 0
	_remaining = 0
	_last_flip_at = -1.0
	_lost_since = -1.0
	_last_present_at = -1.0
	_done = false
	# 批次 W（P1-8b，规格 §5）：reset() 末尾补发 countdown_cancelled("reset")——倒数中切场景
	# （reset_runtime→本方法）时 main.gd 侧倒数弹条只监听 cancelled/confirmed，静默 reset 令弹条
	# 跨场景永久残留。单点修复：main 侧既有接收方幂等 hide。
	if had_active:
		countdown_cancelled.emit("reset")

## 一次「双手同翻」事件（由 Router 消费 GestureMap 的 exit_flip 意图时调用）。
## 批次 Y（Y-A2）：首翻当帧 emit countdown_started(3)；#2/#3 当帧 emit countdown_changed(2|1)；
## #4 立即 exit_confirmed。每次同翻重置 _last_flip_at=now（3s 停留刷新）。
func notify_flip(now: float) -> void:
	if _done:
		return
	_last_flip_at = now
	_last_present_at = now   # 同翻发生=双手在场（双手同翻前提，spec §6.1）
	if _remaining <= 0:
		_remaining = 3
		countdown_started.emit(_remaining)   # 首翻当帧立即弹（0.6s 延迟退役）
		return
	_remaining -= 1
	if _remaining <= 0:
		_done = true
		exit_confirmed.emit()   # 翻转 #4：立即关闭弹条 → Router 执行 §6.3 分流
		return
	countdown_changed.emit(_remaining)   # #2/#3 当帧立即刷新（0.3s 延迟退役）

## 每帧驱动（Router 在 feed 中调用；both_present=双手均在场——held 帧亦计在场，spec §3.1 定档）。
## 批次 Y（Y-A2）：延迟/显示宽限机制退役，本方法只剩 3s 超时与 hand_lost 防抖两条取消线。
func tick(now: float, both_present: bool) -> void:
	if _done:
		return
	if _last_flip_at >= 0.0 and now - _last_flip_at > TIMEOUT_SEC:
		_cancel("timeout")
		return
	if not both_present:
		if _lost_since < 0.0:
			# 离场防抖从「最后确认在场」起算（同翻帧/最近双手帧）；无在场记录时从本帧起算
			_lost_since = _last_present_at if _last_present_at >= 0.0 else now
		elif now - _lost_since > HAND_LOST_CANCEL_SEC:
			_cancel("hand_lost")
			return
	else:
		_lost_since = -1.0
		_last_present_at = now

func _cancel(reason: String) -> void:
	_remaining = 0
	_last_flip_at = -1.0
	_lost_since = -1.0
	_last_present_at = -1.0
	countdown_cancelled.emit(reason)   # 取消后回到正常态；再次触发重新从翻转 #1 计（§6.2）
