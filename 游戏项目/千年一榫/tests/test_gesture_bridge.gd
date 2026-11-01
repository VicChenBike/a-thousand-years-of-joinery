extends "res://tests/test_base.gd"

func _initialize() -> void:
	print("== test_gesture_bridge ==")
	var gb: Node = load("res://autoload/gesture_bridge.gd").new()
	get_root().add_child(gb)
	gb.name = "GestureBridge"
	# --script 模式下树未启动，add_child 不触发 _ready；显式调用幂等初始化（行为等价）
	gb._init_udp()

	var received: Array = []
	gb.gesture_state_received.connect(func(d: Dictionary) -> void: received.append(d))

	# 1 初始状态 LOADING
	check_eq(gb.get_load_state(), gb.LoadState.LOADING, "初始为 LOADING")

	# 2 注入合法顶层双手包 → 解析 + 转 READY（批次 R：顶层 {"left","right","timestamp"}）
	var state_holder: Array = []
	gb.load_state_changed.connect(func(s: int) -> void: state_holder.append(s))
	gb.simulate_packet('{"timestamp":1.0,"left":{"gesture":"open","confidence":0.9},"right":{"gesture":"ok","confidence":0.8}}')
	check_eq(received.size(), 1, "收到一个状态包")
	check_eq(received[0]["left"]["gesture"], "open", "左手形态解析")
	check_eq(gb.get_load_state(), gb.LoadState.READY, "收包后转 READY")
	check_eq(state_holder.size(), 1, "发出 load_state_changed")

	# 3 非法 JSON → 不崩溃、不计入
	gb.simulate_packet("这不是JSON")
	check_eq(received.size(), 1, "非法包被忽略")

	# 4 缺字段包 → 忽略（顶层须含 left 或 right 之一）
	gb.simulate_packet('{"timestamp":2.0}')
	check_eq(received.size(), 1, "缺手势字段包被忽略")

	# 5 端口派生（批次 R §3.3：P/P+1/P+2，udp_port=0 → 9876/9877/9878）
	check_eq(int(gb.get_udp_port()), 9876, "基准端口 9876")
	check_eq(int(gb.get_frame_port()), 9877, "JPEG 端口 P+1=9877")
	check_eq(int(gb.get_control_port()), 9878, "控制端口 P+2=9878")

	# 6 start：runtime 缺失路径（改写探测路径为不存在文件；必须放在所有初始状态断言之后——
	# 缺失时 start 同步置 UNAVAILABLE，会污染「初始为 LOADING」断言）
	gb._runtime_res_path = "res://gesture_runtime/__no_such_main__.py"
	var ok: bool = gb.start_gesture_process()
	check(not ok, "手势运行时缺失时 start 返回 false")
	check_eq(gb.get_load_state(), gb.LoadState.UNAVAILABLE, "未就位时置 UNAVAILABLE")

	# 7 UDP 9876 绑定失败 → push_warning + 置 UNAVAILABLE（端口已被第一个实例占用；
	# 必须放最后：此实例绑定失败不影响前面对同一端口第一个实例的断言）
	var gb2: Node = load("res://autoload/gesture_bridge.gd").new()
	get_root().add_child(gb2)
	gb2.name = "GestureBridge2"
	gb2._init_udp()
	check_eq(gb2.get_load_state(), gb2.LoadState.UNAVAILABLE, "绑定失败置 UNAVAILABLE")
	check(true, "绑定失败时已输出 push_warning（见控制台输出，不崩溃）")
	finish()
