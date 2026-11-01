extends "res://tests/test_base.gd"
## 修复A 判定用例（2026-09-18 外部审计高危项）：覆盖层分支确认手势退出后 tracker 必须复位。
## 缺陷机理（外部审计只读核验；批次 W P1-1 头注更新）：ExitGestureTracker._done 唯一复位口
## =reset()；Router._tracker.reset() 调用点本件立项时仅 reset_runtime() 一处（仅挂
## game.state_changed，close_overlay 不发该信号）→ 覆盖层里确认手势退出后本界面内手势退出
## 静默失灵（_done 恒 true，notify_flip/tick 全短路）。批次 W P1-1（拍板 1）已推广为
## _on_exit_confirmed 全部确认分支各补 reset（见 gesture_router.gd 尾段），本件覆盖层分支
## 断言语义不变；「唯一调用点」表述系立项时点实况，防行号/调用面漂移误读特此注记。
## 驱动方式：真实 gesture_router.gd 新实例（add_child → _ready → _setup()，幂等口径同注释）；
## 真实 Game autoload 注入「不入树 settings 场景引用」（scene_file_path 命中 is_settings_open
## 判定）；close_overlay 无头安全（仅 queue_free 引用+断开主题连接）。时间显式注入（tracker
## 纯逻辑，notify_flip 直接驱动，既有 test_gesture_exit_tracker 同手法）。

func _initialize() -> void:
	print("== test_gesture_exit_overlay_reset ==")
	var game: Node = get_root().get_node("Game")
	var router: Node = load("res://autoload/gesture_router.gd").new()
	add_child(router)
	await process_frame
	check(router.get("_tracker") != null, "前置：新 Router 实例 _ready→_setup 完成（_tracker 就位）")

	# 信号计数器（tracker.exit_confirmed → router._on_exit_confirmed → router.exit_confirmed 转发）
	var confirmed: Array = []
	router.exit_confirmed.connect(func() -> void: confirmed.append(true))

	# 覆盖层态注入：settings 场景引用（不入树，仅供 is_settings_open 的 scene_file_path 判定）
	game._overlay_instance = (load("res://scenes/settings/settings_panel.tscn") as PackedScene).instantiate()
	check(bool(game.is_settings_open()), "前置：注入后 is_settings_open()==true（覆盖层态就绪）")

	var t: Variant = router.get("_tracker")
	# 第一次四翻（now 秒显式注入，间隔均 <3s 超时限）
	t.notify_flip(100.0)
	t.notify_flip(100.2)
	t.notify_flip(100.4)
	t.notify_flip(100.6)
	check_eq(confirmed.size(), 1, "第一次四翻 → exit_confirmed 恰一次（经 router 转发）")
	check(bool(game.has_open_overlay()) == false, "覆盖层分支：close_overlay 已执行（覆盖层引用清空）")
	# —— 修复点断言：确认后 tracker 必须已复位（_done=false），否则本界面手势退出静默失灵 ——
	check(bool(t.get("_done")) == false, "确认后 _tracker._done 已复位（修复前恒 true=缺陷态）")

	# 第二次四翻：同界面再来一轮（无任何场景切换/状态信号——close_overlay 不发 state_changed）
	t.notify_flip(200.0)
	t.notify_flip(200.2)
	t.notify_flip(200.4)
	t.notify_flip(200.6)
	check_eq(confirmed.size(), 2, "第二次四翻 → exit_confirmed 再触发（修复前红灯：_done 残留短路恒 1）")
	# 批次 Y（Y-A22）等价改写：第二轮四翻落在覆盖层已关后的非确认态（--script 下 Game=BOOT），
	# 旧码该静默分支不复位 → _done 残留 true（旧断言「置位=恰一次」）；Y-A22 定档=全分支复位，
	# 恰一次语义由 exit_confirmed 单发保证，_done 残留才是缺陷态（SETTLE/BOOT 一次失灵根除）。
	check(bool(t.get("_done")) == false, "第二轮确认后 _done 已复位（Y-A22：静默分支同样 reset；旧残留=true 红灯语义退役）")

	# 收尾卫生：清 Game 覆盖层引用；断开新实例挂到 autoload 桥的 feed 连接（防 freed 回调）
	game.close_overlay()
	var bridge: Node = get_root().get_node("GestureBridge")
	if bridge != null and bridge.gesture_state_received.is_connected(router.feed):
		bridge.gesture_state_received.disconnect(router.feed)
	router.queue_free()
	await process_frame
	finish()
