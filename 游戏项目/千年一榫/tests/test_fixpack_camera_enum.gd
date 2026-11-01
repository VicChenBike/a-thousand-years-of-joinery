extends "res://tests/test_base.gd"
## 修复批（拉取模式，2026-09-18）判定用例：init#1 一次性消息因启动时序丢失（服务端 t≈0.1s
## 枚举完即发、游戏进程 t≈17s 才绑定 9876 → 两次 init 全部丢失、_camera_enum 缓存恒空、
## 设置面板摄像头下拉「正在加载」永不到达）。修法=9878 控制协议新增 GET_CAMERAS 拉取命令
## （Python 侧收到即重发 init#1）+ 桥 request_camera_enum()（1s 节流）+ READY 迁移缓存空自动拉取
## + camera_menu.open_menu 缓存空时主动拉取。
## 判定映射：段 1 既有行为锁（2）｜段 2 拉取入口出包逐字（3）｜段 3 节流护栏（2）｜
## 段 4 READY 迁移自动拉取+节流+缓存非空不拉（4）｜段 5 open_menu 拉取+缓存刷新重扫（5）→ 合计 16。
## 批次 AC（2026-09-27，spec §4.2-4）：段 5 负例由「缓存直读零出包」等价改写为「下拉刷新
## 强制重扫恰一出包 GET_CAMERAS」（热插拔识别）——断言数 4→5 只增不减，LOADED 直进语义保持。
## 环境说明：9878 被占属环境性失败（bind 断言前置甄别，批次 S 单跑先例）；9876/JPEG 绑定
## 与本用例无关（拉取走 9878 控制端口出包）。
## AF 同步批（2026-11-01）环境噪音甄别：本机若另驻游戏/编辑器实例（用户存档同为手势/摄像头
## 双关 Q3 态），其桥 _ready 的 _q3_release_camera_once 会向 127.0.0.1:9878 广播 RELEASE_CAMERA
##（实锤证据链：本进程 q3sent=true 恰一次哨兵早在 _ready 消费、不可能发第二包；外来包时刻
## 在多次跑测间漂移 348→740ms）——该类外来包与「GET_CAMERAS 拉取节流」断言语义正交，
## 统一经 _recv_expect/按内容过滤消费，不计入出包断言（外来 GET_CAMERAS 混入仍判红留人工口）。

## 按期望内容收包：frames 帧内等到逐字相等的包即返回；其余包打印留痕不消费断言。
func _recv_expect(l: PacketPeerUDP, expect: String, frames: int) -> String:
	for i: int in frames:
		while l.get_available_packet_count() > 0:
			var pkt: String = l.get_packet().get_string_from_utf8()
			if pkt == expect:
				return pkt
			print("[env-noise] 收到非期望包「%s」（外部进程噪音，不计入断言）" % pkt)
		await process_frame
	return ""

func _initialize() -> void:
	print("== test_fixpack_camera_enum ==")
	var bridge: Variant = get_root().get_node("GestureBridge")

	# ---- 段 1. 既有行为锁：含 cameras 的 init#1 到达 → 缓存 getter 非空（2 checks）----
	bridge._camera_enum = {}
	bridge.simulate_packet(JSON.stringify(
		{"type": "init", "cameras": [{"id": 0, "name": "HD Cam"}], "current_camera": 0}))
	check(not (bridge.get_camera_enum() as Dictionary).is_empty(),
		"F1：含 cameras 的 init 到达 → get_camera_enum() 非空（既有行为锁）")
	check_eq(int((bridge.get_camera_enum() as Dictionary).get("current_camera", -1)), 0,
		"F1：缓存 current_camera 同值（cameras+current_camera 对组）")

	# ---- 段 2. 拉取入口：request_camera_enum → 9878 出包逐字 GET_CAMERAS（3 checks）----
	var has_req: bool = bridge.has_method("request_camera_enum")
	check(has_req, "F2：GestureBridge.request_camera_enum() 方法存在（拉取入口）")
	var listener := PacketPeerUDP.new()
	check_eq(listener.bind(bridge.get_control_port()), 0,
		"F2 前置：9878 回环监听绑定成功（占用即环境性失败，单跑甄别 §1.4）")
	var got := ""
	if has_req:
		bridge.set("_last_enum_request_ms", -1000000)   # 复位节流（注入惯例：_probe_started_at 同款）
		bridge.request_camera_enum()
	else:
		check(false, "F2：request_camera_enum 缺失（红灯短路防动态调用挂死）")
	got = await _recv_expect(listener, "GET_CAMERAS", 30)
	# 批次 AF 终审备案族（语言钉扎先例=6411fae o_catalog_shop）：autoload _ready 推迟至树激活，
	# 须等一帧后钉 zh——用户真实存档现 language=en，不钉则文案断言呈 en 态假红。
	# 编译窗安全：经节点查找而非全局名（--script 模式 autoload 全局名编译期未注册）。
	var i18n_node: Variant = get_root().get_node_or_null("I18n")
	if i18n_node != null:
		i18n_node.call("set_language", "zh")
	check_eq(got, "GET_CAMERAS", "F2：request_camera_enum → send_control(\"GET_CAMERAS\") 逐字出包")

	# ---- 段 3. 节流护栏：同一秒内最多一次；窗口过后恢复（2 checks）----
	if has_req:
		bridge.request_camera_enum()   # 段 2 刚发过一包（同秒内）
		bridge.request_camera_enum()
	else:
		check(false, "F3：request_camera_enum 缺失（红灯短路）")
	var extra := 0
	for i: int in 20:
		if listener.get_available_packet_count() > 0:
			var pkt: String = listener.get_packet().get_string_from_utf8()
			if pkt == "GET_CAMERAS":
				extra += 1
			else:
				print("[env-noise] F3 节流窗收到非拉取包「%s」（外部进程噪音，不计入断言）" % pkt)
		else:
			await process_frame
	check_eq(extra, 0, "F3：节流窗口内连续调用 → 零 GET_CAMERAS 出包（防菜单反复开合刷包；外来非拉取包按内容过滤不计）")
	if has_req:
		bridge.set("_last_enum_request_ms", Time.get_ticks_msec() - 2000)   # 拨回窗口外
		bridge.request_camera_enum()
	var got2: String = await _recv_expect(listener, "GET_CAMERAS", 30)
	check_eq(got2, "GET_CAMERAS", "F3：节流窗口过后再次调用 → 恢复出包（节流可过期非永久封死）")
	listener.close()

	# ---- 段 4. READY 迁移自动拉取（4 checks）----
	var listener2 := PacketPeerUDP.new()
	check_eq(listener2.bind(bridge.get_control_port()), 0, "F4 前置：9878 监听绑定成功")
	bridge._camera_enum = {}
	bridge.set("_last_enum_request_ms", -1000000)
	bridge._set_state(2)   # UNAVAILABLE（确保下一步为真实迁移；_process 不产生 READY 迁移无干扰）
	bridge._set_state(1)   # →READY 迁移点：缓存空 → 自动 request 一次
	var got3: String = await _recv_expect(listener2, "GET_CAMERAS", 30)
	check_eq(got3, "GET_CAMERAS", "F4：READY 迁移且缓存空 → 自动 request_camera_enum 恰一次")
	bridge._set_state(2)
	bridge._set_state(1)   # 节流窗口内再次迁移（缓存仍空）
	var extra2 := 0
	for i: int in 20:
		if listener2.get_available_packet_count() > 0:
			var pkt2: String = listener2.get_packet().get_string_from_utf8()
			if pkt2 == "GET_CAMERAS":
				extra2 += 1
			else:
				print("[env-noise] F4 节流窗收到非拉取包「%s」（外部进程噪音，不计入断言）" % pkt2)
		else:
			await process_frame
	check_eq(extra2, 0, "F4：节流窗口内重复 READY 迁移 → 不重发（自动拉取同受护栏约束；外来非拉取包不计）")
	bridge.set("_last_enum_request_ms", Time.get_ticks_msec() - 2000)
	bridge._camera_enum = {"cameras": [{"id": 0, "name": "C"}], "current_camera": 0}
	bridge._set_state(2)
	bridge._set_state(1)   # 缓存非空迁移
	var extra3 := 0
	for i: int in 20:
		if listener2.get_available_packet_count() > 0:
			var pkt3: String = listener2.get_packet().get_string_from_utf8()
			if pkt3 == "GET_CAMERAS":
				extra3 += 1
			else:
				print("[env-noise] F4 缓存非空段收到非拉取包「%s」（外部进程噪音，不计入断言）" % pkt3)
		else:
			await process_frame
	check_eq(extra3, 0, "F4：缓存非空 READY 迁移 → 不拉取（已持有枚举无需重取；外来非拉取包不计）")
	listener2.close()

	# ---- 段 5. camera_menu.open_menu 拉取（4 checks）----
	var listener3 := PacketPeerUDP.new()
	check_eq(listener3.bind(bridge.get_control_port()), 0, "F5 前置：9878 监听绑定成功")
	bridge.set("_last_enum_request_ms", -1000000)   # 复位节流（防段 4 余波吞包）
	bridge._camera_enum = {}
	var menu: Control = (load("res://scenes/settings/camera_menu.gd") as GDScript).new()
	add_child(menu)
	await process_frame
	menu.call("open_menu")   # 缓存空 → LOADING 分支 → 应经桥 request_camera_enum（不直碰控制端口）
	var got4: String = await _recv_expect(listener3, "GET_CAMERAS", 30)
	check_eq(got4, "GET_CAMERAS", "F5：open_menu 缓存空 → 经桥 request_camera_enum 出包逐字")
	# 负例：缓存非空直读分支（P1-1 零等待 LOADED）——批次 AC 等价改写（2026-09-27，
	# spec §4.2-4/D4）：下拉刷新（本入口）改为**一律发 GET_CAMERAS 强制重扫物理硬件**
	# （外接摄像头热插拔识别；旧「缓存非空即零出包」使新插入设备永不可见），
	# 决策依据=实机「插上外接摄像头→下拉仍无新设备」走查项。断言由「零出包」等价迁移为
	# 「恰一出包且逐字 GET_CAMERAS」，LOADED 直进语义（P1-1 零等待）逐条保持。
	bridge.set("_last_enum_request_ms", Time.get_ticks_msec() - 2000)
	bridge._camera_enum = {"cameras": [{"id": 0, "name": "CamX"}], "current_camera": 0}
	menu.call("open_menu")
	var extra4 := 0
	var got4b := ""
	for i: int in 20:
		if listener3.get_available_packet_count() > 0:
			var pkt4: String = listener3.get_packet().get_string_from_utf8()
			if pkt4 == "GET_CAMERAS":
				extra4 += 1
				if got4b.is_empty():
					got4b = pkt4
			else:
				print("[env-noise] F5 重扫段收到非拉取包「%s」（外部进程噪音，不计入断言）" % pkt4)
		else:
			await process_frame
	check_eq(extra4, 1, "AC 等价替换（旧「缓存直读分支零出包」）：下拉刷新强制重扫恰一出包")
	check_eq(got4b, "GET_CAMERAS", "AC：下拉刷新出包逐字 GET_CAMERAS（热插拔重扫请求）")
	check_eq(int(menu.get("state")), 2, "F5：缓存直读分支仍直进 LOADED（MenuState.LOADED=2 既有口径不动）")
	listener3.close()
	menu.free()
	bridge._camera_enum = {}   # 夹具复位（防污染后续测试/树退出路径）
	finish()
