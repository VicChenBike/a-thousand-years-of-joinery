extends "res://tests/test_base.gd"
## 批次 R 判定用例：ExitGestureTracker 4 次倒数退出状态机（spec §11.1-3/§6.2）。
## 批次 Y（Y-A2/Y-A9，spec §2-②⑨）语义更新（红→绿，旧延迟断言按拍板退役）：
##   - 首翻**当帧** emit countdown_started(3)（FIRST_DELAY_SEC=0.6 退役——旧「0.6s 后首显」断言废止）；
##   - #2/#3 **当帧** emit countdown_changed(2|1)（REFRESH_DELAY_SEC=0.3 退役——旧「0.3s 后刷新」废止）；
##   - 每次同翻重置停留（批次 Z Z5-6：TIMEOUT_SEC 3.0→4.5s 拍板——旧「3 秒」断言平移，
##     4.4s 中途帧护栏 + 4.6s 超时两段锁，防空转假绿）；
## 批次 AC 4A（spec §4.6-7，2026-09-27 用户实机反馈）：HAND_LOST_CANCEL_SEC 0.8→**2.0**——
##   双手翻掌*侧立瞬间* MediaPipe 短暂丢帧（侧立盲区）在旧 0.8s 窗下会把倒数**中途归零**
##   （用户「翻 4 次才弹一次」主因之一）。段 4 断言按新窗等价改写：1.5s 离场**不**取消
##   （旧 0.8s 档下此处必红=红绿反转锁）+ 1.8s 仍不取消（中途帧护栏）+ 2.1s 才取消；
##   段 5「离场未满防抖恢复」同步平移为 1.5s 内恢复（旧 0.5s/0.7s 档随窗放宽退役留痕）。
## 纯逻辑直调：notify_flip(now)/tick(now, both_present)，时间显式注入。

var t: Variant

func _no_signals() -> Array:
	return [[], [], [], []]  # started/changed/cancelled/confirmed 收集位

func _wire(sig: Array) -> void:
	t.countdown_started.connect(func(r: int) -> void: sig[0].append(r))
	t.countdown_changed.connect(func(r: int) -> void: sig[1].append(r))
	t.countdown_cancelled.connect(func(r: String) -> void: sig[2].append(r))
	t.exit_confirmed.connect(func() -> void: sig[3].append(true))

func _initialize() -> void:
	print("== test_gesture_exit_tracker ==")
	t = load("res://scripts/gesture_exit_tracker.gd").new()

	# ---- 1. 全流程：#1→当帧 started(3)；#2/#3→当帧 changed(2/1)；#4→exit_confirmed 恰一次 ----
	var sig: Array = _no_signals()
	_wire(sig)
	t.notify_flip(0.0)
	check_eq((sig[0] as Array).size(), 1, "Y-A2：翻转 #1 当帧 countdown_started（0.6s 首显延迟退役红锁）")
	check_eq(int(sig[0][0]), 3, "首显 remaining=3（还需翻转 3 次）")
	t.notify_flip(1.0)
	check_eq((sig[1] as Array).size(), 1, "Y-A2：#2 当帧 changed（0.3s 刷新延迟退役红锁）")
	check_eq(int(sig[1][0]), 2, "remaining=2")
	t.notify_flip(1.5)
	check_eq((sig[1] as Array).size(), 2, "#3 当帧 changed(1)")
	check_eq(int(sig[1][1]), 1, "remaining=1")
	t.notify_flip(2.0)
	check_eq((sig[3] as Array).size(), 1, "翻转 #4 → exit_confirmed 恰一次（立即）")
	t.tick(3.0, true)
	check_eq((sig[3] as Array).size(), 1, "确认后不再重复发")

	# ---- 2. 4.5 秒无新同翻 → cancelled（首翻当帧起算；Z5-6 停留 3.0→4.5s；4.4s 中途帧护栏）----
	t.reset()
	var sig2: Array = _no_signals()
	_wire(sig2)
	t.notify_flip(10.0)
	check_eq((sig2[0] as Array).size(), 1, "重计前置：首翻当帧 started")
	t.tick(14.4, true)
	check((sig2[2] as Array).is_empty(), "距末次同翻 4.4s 未超时（中途帧护栏：旧 3.0s 下此处必红）")
	t.tick(14.6, true)
	check_eq((sig2[2] as Array).size(), 1, "4.5 秒无新同翻 → cancelled")
	check_eq(String(sig2[2][0]), "timeout", "取消原因=timeout")

	# ---- 3. 计时器每次同翻后重置（每次刷新重置 4.5s 停留）----
	t.reset()
	var sig3: Array = _no_signals()
	_wire(sig3)
	t.notify_flip(20.0)
	t.tick(22.0, true)      # 距 #1 2s
	t.notify_flip(22.5)     # #2 重置计时（当帧 changed(2)）
	t.tick(24.4, true)      # 距 #2 1.9s
	check((sig3[2] as Array).is_empty(), "同翻重置超时计时")
	t.tick(26.9, true)      # 距 #2 4.4s（中途帧护栏）
	check((sig3[2] as Array).is_empty(), "重置后 4.4s 仍未超时（中途帧护栏：旧 3.0s 下此处必红）")
	t.tick(27.1, true)      # 距 #2 4.6s
	check_eq((sig3[2] as Array).size(), 1, "重置后仍 4.5s 超时取消")

	# ---- 4. 双手任一真离场 2.0s 防抖 → cancelled（AC 4A：0.8→2.0s 延长，侧立盲区不吞倒数）----
	# 红绿反转锁：1.5s 离场在**旧 0.8s 档**下必已取消（此处判红）；2.0s 档下不取消。
	t.reset()
	var sig4: Array = _no_signals()
	_wire(sig4)
	t.notify_flip(30.0)
	t.tick(30.4, false)     # 离场 0.4s
	t.tick(31.0, false)     # 离场 1.0s（旧 0.8s 档已取消）
	check((sig4[2] as Array).is_empty(), "AC 4A：离场 1.0s 防抖不取消（旧 0.8s 档红锁）")
	t.tick(31.5, false)     # 离场 1.5s（用户实测侧立盲区量级——旧 0.8s 档红锁）
	check((sig4[2] as Array).is_empty(), "AC 4A：离场 1.5s 防抖不取消（侧立丢帧容忍；旧 0.8s 档红锁）")
	t.tick(31.8, false)     # 离场 1.8s（中途帧护栏：2.0s 未到不提前取消）
	check((sig4[2] as Array).is_empty(), "AC 4A：离场 1.8s 仍不取消（中途帧护栏，防空转假绿）")
	t.tick(32.05, false)    # 离场持续 >2.0s
	check_eq((sig4[2] as Array).size(), 1, "AC 4A：离场 2.0s 防抖 → cancelled")
	check_eq(String(sig4[2][0]), "hand_lost", "取消原因=hand_lost")

	# ---- 5. 回到场恢复：离场未满 2.0s 回来继续倒数 ----
	t.reset()
	var sig5: Array = _no_signals()
	_wire(sig5)
	t.notify_flip(40.0)
	t.tick(40.8, false)
	t.tick(41.4, true)      # 离场 1.4s 内回到双手
	t.tick(41.7, true)
	check((sig5[2] as Array).is_empty(), "AC 4A：离场未满 2.0s 恢复 → 不取消（旧 0.8s 档此处已取消）")
	check_eq((sig5[0] as Array).size(), 1, "首显照常（当帧 started 不受影响）")

	# ---- 6. 取消后可重新全流程（无额外冷却）----
	t.reset()
	var sig6: Array = _no_signals()
	_wire(sig6)
	t.notify_flip(50.0)
	t.tick(54.8, true)      # 4.8s>4.5s 超时取消（Z5-6 平移：旧 53.2=3.2s 档退役）
	check_eq((sig6[2] as Array).size(), 1, "第一次取消")
	t.notify_flip(55.6)     # 重新从翻转 #1 计
	check_eq((sig6[0] as Array).size(), 2, "取消后重触发生效：当帧再次 started")
	t.notify_flip(56.4)
	t.notify_flip(56.9)
	t.notify_flip(57.4)
	check_eq((sig6[3] as Array).size(), 1, "第二次流程 #4 → exit_confirmed 恰一次")
	finish()
