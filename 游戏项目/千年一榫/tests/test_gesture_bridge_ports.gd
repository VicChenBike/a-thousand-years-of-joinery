extends "res://tests/test_base.gd"
## 批次 R 判定用例：GestureBridge 三端口/状态机/JPEG 头校验（spec §11.1-1）。
## 契约来源：批次 R spec §3.3（端口派生 P/P+1/P+2、4 字节小端长度头、9878 SHUTDOWN、
## 就绪探测试探 9878）、§9.1（LOADING→READY→UNAVAILABLE→重试）、§8.3-2（editor 判据+导出跳过）。
## 环境说明：--script 无头 autoload 不触发 _ready → 显式 _init_udp()；手势 JSON 端口被
## 并行进程占用属环境性失败，单跑必绿（批次 M/N12c 先例）。

const JPEG_HDR := 4

func _jpeg_bytes() -> PackedByteArray:
	# 4×4 纯色 JPEG（无头可编码，探针实证 save_jpg_to_buffer 可用）
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color(0.9, 0.2, 0.1))
	return img.save_jpg_to_buffer()

func _with_header(jpg: PackedByteArray) -> PackedByteArray:
	var pkt := PackedByteArray()
	pkt.append_array(PackedByteArray([0, 0, 0, 0]))  # 占位
	pkt.encode_u32(0, jpg.size())
	pkt.append_array(jpg)
	return pkt

func _sender_to(port: int) -> PacketPeerUDP:
	var s := PacketPeerUDP.new()
	s.set_dest_address("127.0.0.1", port)
	return s

## 回环投递确定性等待：put_packet 后对端队列可能延迟一帧可读，逐帧重试至多 frames 帧
func _wait_available(peer: PacketPeerUDP, frames: int) -> void:
	for i: int in frames:
		if peer.get_available_packet_count() > 0:
			return
		await process_frame

# ===== 清档纪律（tools/README_走查清档规范.md，批次V回修②B 补齐，test_v_save_domain 同款）=====
# 起测前备份 user:// 真实档案（save.json/first_launch.flag 及可触及的 .tmp/.bak 四件组），
# 终测统一经 finish() 收口还原：先同步 free 测试挂载节点（level._exit_tree 兜底写档等
# 「退出写回」先落测试域磁盘，规范第 6 条），再逐件还原 + SaveManager load_game 重同步内存
# + 逐字节等价断言 + EVID 证据行。备份路径必须带全 user:// 前缀（相对路径在 FileAccess/
# DirAccess 间解析漂移 → 备份链静默失效，test_n10 先例）；每文件独立备份前缀防崩溃残留互踩。
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_r2b_gbp_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _pre_save_text: String = ""   # 起测前真实 save.json 原文（还原等价自检基准）

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _disc_del(p: String) -> void:
	var a: String = _disc_abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _backup_user() -> void:
	# 规范第 1 条：任何删/写档操作之前备份真实档案（有档才备份；还原「有备份才回拷」幂等，
	# 起测前不存在的档案终测后仍不存在——测试自建残留一律清零）
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	# 防退出写回（规范第 6 条）：先同步 free 测试挂载的非 autoload 节点——level._exit_tree
	# 兜底写档（N9）若拖到进程退出树序，会在还原之后把测试态写回真实档案；提前 free 令
	# 兜底写档落测试域磁盘，紧随其后的逐件还原即将其覆盖。
	for c: Node in root.get_children():
		if not DISC_AUTOLOADS.has(String(c.name)):
			c.free()
	# 规范第 2 条：逐件还原 + load_game 重同步内存（防后续 save_game 把测试态写回真实档案）
	for p: String in DISC_WATCHED:
		_disc_del(p)
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(_disc_abs(bk))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()
	# 纪律自检：还原后 save.json 与起测前逐字节等价（起测前无档 ↔ 还原后无档）
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|gbp|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_gesture_bridge_ports ==")
	_backup_user()
	var save: Variant = get_root().get_node("SaveManager")
	save.load_game()   # 审查回修 P1-3：--script 模式 autoload _ready 不触发，必须显式 load_game 初始化 _data，否则 update_settings 在空档上运行时错误（test_gesture_bridge.gd :8 既有先例）
	var bridge: Variant = load("res://autoload/gesture_bridge.gd").new()
	get_root().add_child(bridge)
	bridge.name = "GestureBridgePortsTest"
	bridge._init_udp()
	bridge._init_jpeg_udp()
	var received: Array = []
	bridge.gesture_state_received.connect(func(d: Dictionary) -> void: received.append(d))
	var frames: Array = []
	bridge.camera_frame_received.connect(func(t: ImageTexture) -> void: frames.append(t))

	# ---- 1. 端口派生（§3.3）：udp_port=0→9876/9877/9878；存档端口改写后恒常量派生 ----
	# 【P2-3a 等价替换留痕（批次 W2，规格 §3）】旧注入断言 3 条废止→新常量派生断言 3 条：
	# 旧口径「update_settings({"udp_port":10000}) → P=10000/10001/10002」随 udp_port 消费退役
	# 废止；等价改写为「存档 udp_port=9999 注入后桥仍绑常量 9876 派生」（单一真源，与 launcher
	# 语义恒一致）。对位改写 check 数持平——git show HEAD 实证新旧静态断言均 79 条
	#（check_eq 66+check 13）；runtime 总数（如 80）含「备份落位自检」一行按磁盘现存件数多次
	# 执行的环境性浮动，非本改动增量（W2 审查 P2-1 计数勘误留痕）。
	check_eq(int(bridge.get_udp_port()), 9876, "udp_port=0 → 基准 9876")
	check_eq(int(bridge.get_frame_port()), 9877, "JPEG=P+1=9877")
	check_eq(int(bridge.get_control_port()), 9878, "控制=P+2=9878")
	save.update_settings({"udp_port": 9999})
	check_eq(int(bridge.get_udp_port()), 9876, "P2-3a：udp_port=9999 → 桥仍 9876（常量派生，不再消费存档）")
	check_eq(int(bridge.get_frame_port()), 9877, "P2-3a：JPEG 派生不受存档端口影响（9877）")
	check_eq(int(bridge.get_control_port()), 9878, "P2-3a：控制派生不受存档端口影响（9878）")
	save.update_settings({"udp_port": 0})

	# ---- 2. 9876 JSON（simulate_packet 路）：双手对象/palm_size 透传/小写归一 ----
	check_eq(int(bridge.get_load_state()), bridge.LoadState.LOADING, "初始 LOADING")
	bridge.simulate_packet('{"timestamp":1.0,"left":{"gesture":"Open_Palm","confidence":0.9,"palm_size":0.23},"right":null}')
	check_eq(received.size(), 1, "simulate_packet 收到双手对象包")
	check_eq(String(received[0]["left"]["gesture"]), "open_palm", "gesture 归一小写")
	check(bool(received[0].has("right")) and received[0]["right"] == null, "right=null 透传")
	check_eq(float(received[0]["left"]["palm_size"]), 0.23, "palm_size 透传不剥离")

	# ---- 3. 9876 真实 UDP 回环路 ----
	var snd := _sender_to(int(bridge.get_udp_port()))
	snd.put_packet('{"timestamp":2.0,"left":null,"right":{"gesture":"Point","confidence":0.7,"palm_size":0.31}}'.to_utf8_buffer())
	await _wait_available(bridge._udp, 10)
	# 批次 AF 终审备案族（语言钉扎先例=6411fae o_catalog_shop）：autoload _ready 推迟至树激活，
	# 须等一帧后钉 zh——用户真实存档现 language=en，不钉则文案断言呈 en 态假红。
	# 编译窗安全：经节点查找而非全局名（--script 模式 autoload 全局名编译期未注册）。
	var i18n_node: Variant = get_root().get_node_or_null("I18n")
	if i18n_node != null:
		i18n_node.call("set_language", "zh")
	bridge._poll_udp()
	check_eq(received.size(), 2, "真实回环包被 _poll_udp 收到")
	check_eq(float(received[1]["right"]["palm_size"]), 0.31, "回环路 palm_size 透传")

	# ---- 4. 非法/缺字段包忽略 ----
	bridge.simulate_packet("这不是JSON")
	bridge.simulate_packet('{"timestamp":3.0}')
	check_eq(received.size(), 2, "非法 JSON 与缺 left/right 键包均忽略")

	# ---- 5. 9877 正例：4 字节小端长度头 + JPEG → 解码出纹理 ----
	# 批次 Z 终审（脆弱性根治，2026-09-24）：JPEG 段（5~7）改同一显式时间基准 jt 注入——
	# 旧写法 _poll_jpeg(bridge._now()+偏移) 依赖两次真实 _now() 差：窗口断言要求 <1/30s
	#（13.3ms），而两次注入之间夹真实 await → 机速/负载敏感（负载高时必红「期望 2 实际 3」，
	# 批次 Z 终态 log zg_regression_final.txt 与本批 zfr2_fix4_mechanism_red.txt 留档）。
	# 根治：①段前冻结 _last_jpeg_decode_time=jt-1.0——引擎 _process 的真实 now 相对恒负
	# → 恒节流不再排空，队列归显式调用独占；②全部偏移=显式构造定值（0/0.05/0.10/0.12/0.16），
	# 窗口内 0.02s<1/30s、窗口外 0.06s≥1/30s 双方向与真实耗时零耦合。
	var jt: float = bridge._now() + 100.0
	bridge._last_jpeg_decode_time = jt - 1.0
	var jpg := _jpeg_bytes()
	var snd2 := _sender_to(int(bridge.get_frame_port()))
	snd2.put_packet(_with_header(jpg))
	await _wait_available(bridge._jpeg_udp, 10)
	bridge._poll_jpeg(jt)
	check_eq(frames.size(), 1, "合法 JPEG 包解码出 1 帧")

	# ---- 6. 9877 负例：长度头不符/包过短 → 静默丢帧 ----
	var bad := _with_header(jpg)
	bad.encode_u32(0, jpg.size() + 5)  # 谎报长度
	snd2.put_packet(bad)
	snd2.put_packet(PackedByteArray([1, 2, 3]))  # 不足 4 字节头
	await _wait_available(bridge._jpeg_udp, 10)
	bridge._poll_jpeg(jt + 0.05)
	check_eq(frames.size(), 1, "头不符/过短包被丢帧")

	# ---- 7. 9877 陈旧丢弃：队列多包只解最新 + ≤30fps 节流 ----
	snd2.put_packet(_with_header(jpg))
	snd2.put_packet(_with_header(jpg))
	snd2.put_packet(_with_header(jpg))
	await _wait_available(bridge._jpeg_udp, 10)
	bridge._poll_jpeg(jt + 0.10)
	check_eq(frames.size(), 2, "同轮询窗口内 3 包只解最新 1 帧（陈旧丢弃）")
	snd2.put_packet(_with_header(jpg))
	await _wait_available(bridge._jpeg_udp, 10)
	bridge._poll_jpeg(jt + 0.12)   # 显式窗口内：距上次解码（jt+0.10）0.02s < 1/30s
	check_eq(frames.size(), 2, "30fps 节流窗口内再收到包不解码")
	check(bridge._jpeg_udp.get_available_packet_count() >= 1,
		"节流窗口内不排空（最新包留队待窗口过后解码，+1 断言只增不减）")
	bridge._poll_jpeg(jt + 0.16)   # 显式窗口外：距上次解码（jt+0.10）0.06s ≥ 1/30s
	check_eq(frames.size(), 3, "节流窗口（1/30s）过后恢复解码")

	# ---- 8. 9878 send_control：真实回环监听收 SHUTDOWN ----
	var listener := PacketPeerUDP.new()
	check_eq(int(listener.bind(int(bridge.get_control_port()))), 0, "测试监听 9878 成功（模拟 Python 绑定端）")
	bridge.send_control("SHUTDOWN")
	var got := false
	for i: int in 20:
		if listener.get_available_packet_count() > 0:
			got = String(listener.get_packet().get_string_from_utf8()) == "SHUTDOWN"
			break
		await process_frame
	check(got, "send_control('SHUTDOWN') 经 9878 真实送达")
	listener.close()

	# ---- 9. 就绪探测：试探 9878 不是 9876（§3.3/§14-10）----
	check_eq(bool(bridge._probe_python_ready()), false, "9878 空闲 → 未就绪")
	var fake_py := PacketPeerUDP.new()
	fake_py.bind(int(bridge.get_control_port()))
	check_eq(bool(bridge._probe_python_ready()), true, "9878 被占 → 已就绪")
	fake_py.close()

	# ---- 10. 状态机：LOADING→READY→(5s 无包)→UNAVAILABLE→(重试+探测成功)→LOADING→(15s)→UNAVAILABLE ----
	bridge.simulate_packet('{"timestamp":4.0,"left":null,"right":null}')
	check_eq(int(bridge.get_load_state()), bridge.LoadState.READY, "合法包 → READY")
	bridge._last_packet_time = bridge._now() - 6.0
	bridge._process(0.0)
	check_eq(int(bridge.get_load_state()), bridge.LoadState.UNAVAILABLE, "READY 5 秒无包 → UNAVAILABLE")
	fake_py = PacketPeerUDP.new()
	fake_py.bind(int(bridge.get_control_port()))  # 模拟 Python 已就绪
	bridge._last_retry_at = bridge._now() - 10.0
	bridge._process(0.0)
	check_eq(int(bridge.get_load_state()), bridge.LoadState.LOADING, "UNAVAILABLE 重试：探测 9878 成功 → LOADING")
	bridge._probe_started_at = -100.0  # 审查回修 P2-1（批次 R-C 授权）：直接哨兵值注入，与进程运行时长无关——now-(-100)≥100>45 恒触发超时分支，且不会撞上 -1.0「未设置」哨兵
	bridge._process(0.0)
	# 批次 Z（Z4-②，spec §4-2 等价改写）：就绪超时判据由「墙钟 15s」改为「python 进程存活」——
	# 9878 被占=python 在 → 单次未就绪不判死，延长就绪窗保持 LOADING（最坏启动预算 35s 振荡根除）。
	check_eq(int(bridge.get_load_state()), bridge.LoadState.LOADING,
		"Z4-②：python 存活（9878 被占）→ 就绪超时不转 UNAVAILABLE（延长就绪窗）")
	fake_py.close()
	bridge._probe_started_at = -100.0   # python 释放控制口（进程亡）→ 反例：超时才判死
	bridge._process(0.0)
	check_eq(int(bridge.get_load_state()), bridge.LoadState.UNAVAILABLE,
		"Z4-②：python 不在（9878 释放）→ 就绪超时转 UNAVAILABLE（反例不放水）")

	# ---- 11. start_gesture_process：无头不真拉起；文件缺失置 UNAVAILABLE ----
	# AF 同步批（2026-11-01）「设置门放行」前置钉住：批次 AA（aarev P1-1）在 start_gesture_process
	# 入口加 `_settings_allow_camera()` 单一漏斗门（gesture_input ∨ gesture_camera_enabled；Q3 双关
	# =一切直调路径零 spawn 零副作用）。夹具对用户存档敏感实证——存档双关时门在入口直接
	# return false，本段 runtime 缺失降级/段 12 防重入与死 pid 反向锁/段 13 S13 清标志四组分支
	# 全部不可达（非代码回归；生产语义「主动关不得复活」正确）。本处起 update_settings 置
	# gesture_input=true 钉住「设置门放行」前提（注入先例=段 4 udp_port；跑前备份-跑后还原
	# 纪律兜底），段 13 结束还原原值。
	var sm_gate: Node = get_root().get_node("SaveManager")
	var gate_orig: bool = bool((sm_gate.get_settings() as Dictionary).get("gesture_input", true))
	sm_gate.update_settings({"gesture_input": true})
	var st_before: int = int(bridge.get_load_state())
	var ok: bool = bridge.start_gesture_process()
	check(not ok, "无头模式 start 返回 false（不真拉起子进程）")
	check_eq(int(bridge.get_load_state()), st_before, "无头 start 不改状态（文件在位时不置 UNAVAILABLE）")
	var bridge2: Variant = load("res://autoload/gesture_bridge.gd").new()
	get_root().add_child(bridge2)
	bridge2._runtime_res_path = "res://gesture_runtime/__no_such_main__.py"
	bridge2._udp = null  # 防占端口：跳过 _init_udp，仅测 start 路径
	check(not bool(bridge2.start_gesture_process()), "runtime 缺失 → start 返回 false")
	check_eq(int(bridge2.get_load_state()), bridge2.LoadState.UNAVAILABLE, "runtime 缺失 → UNAVAILABLE")

	# ---- 12. 终审 P1-1：子进程防重入门——已有活实例 start 直接复用返回 true ----
	# 编辑器模式 UNAVAILABLE 每 5s 重试/设置面板反复开合会重复 spawn MediaPipe 子进程（终审 P1-1）。
	# 无头不真拉起（哨兵 -1），注入 _process_pid 模拟「已有活实例」观测守卫分支。
	# 修复批 P3（2026-09-26，gesture_bridge.gd:877）：防重门收紧为
	# `_process_pid >= 0 and OS.is_process_running(_process_pid)`（死 pid 清 -1 走重拉）——
	# 复用分支哨兵必须是真实存活 pid，取本测试进程自身（恒存活）；死 pid 另设双向护栏段。
	var live_pid: int = OS.get_process_id()
	bridge._process_pid = live_pid
	check(bool(bridge.start_gesture_process()), "防重入门：已有活实例时 start 返回 true（直接复用）")
	check_eq(int(bridge._process_pid), live_pid, "防重入门：二次调用不重复 spawn（pid 不变）")
	check_eq(int(bridge.get_load_state()), st_before, "防重入门：复用分支不改状态机")
	# 双向护栏（修复批 P3 反向锁）：死 pid 不得被当活实例复用——判死后清 -1 走重拉链路
	bridge._process_pid = 12345   # 非存活 pid（判活收紧后的陈旧哨兵形态）
	check(not bool(bridge.start_gesture_process()), "防重入门（反向锁）：死 pid 不复用（start 返回 false 走重拉，无头不真拉起）")
	check_eq(int(bridge._process_pid), -1, "防重入门（反向锁）：死 pid 判死后清 -1（不残留陈旧哨兵）")
	bridge._process_pid = -1  # 哨兵复位（防泄漏到后续段/树退出 stop 分支）

	# ---- 13. 批次 S13：stop → UNAVAILABLE + _intentional_stop 标志 + consume 取走即清 ----
	bridge.simulate_packet('{"timestamp":5.0,"left":null,"right":null}')
	check_eq(int(bridge.get_load_state()), bridge.LoadState.READY, "S13 前置：合法包 → READY")
	bridge._process_pid = 0   # PID 0=系统保留（Windows OpenProcess 必失败）：OS.kill 无害返回，防误杀真实进程；
	                          # 如 stderr 出现 kill 报错行属预期噪音（不影响 ALL TESTS PASSED 判读）
	bridge.stop_gesture_process()
	check_eq(int(bridge.get_load_state()), bridge.LoadState.UNAVAILABLE, "S13：stop → 即刻 UNAVAILABLE（不等 5s 无包超时）")
	check_eq(int(bridge._process_pid), -1, "S13：stop 杀子进程并复位哨兵")
	check_eq(bool(bridge.consume_intentional_stop()), true, "S13/S14：consume_intentional_stop 首次取走=true（主动关标志）")
	check_eq(bool(bridge.consume_intentional_stop()), false, "S13/S14：consume 取走即清（二次=false）")
	# S13：start 入口清陈旧主动关标志（防 Q3 无状态迁移时遗留标志吞掉下次真实故障 toast，计划 §11-R8）
	bridge._intentional_stop = true
	bridge._process_pid = live_pid   # 修复批 P3 判活收紧后：复用分支须真实存活 pid 才命中
	bridge.start_gesture_process()   # headless 恒可达的成功路径=防重入门复用分支（终审 P1-1）
	check_eq(bool(bridge._intentional_stop), false, "S13：start 入口清陈旧 _intentional_stop")
	check_eq(int(bridge._process_pid), live_pid, "S13：复用分支不重复 spawn（活 pid 不变）")
	bridge._process_pid = -1
	# AF 同步批：设置门前提还原（防污染后续段/树退出路径；文件级由备份-还原纪律兜底）
	sm_gate.update_settings({"gesture_input": gate_orig})
	# S13 spawn 成功 → LOADING：无头不可达真实 spawn（DisplayServer 守卫），以源码证据链固化
	#（m_cursor_glow 源码断言先例；活体证明=§8-④ 走查占位序列 + §8-6 用户真机复验）
	var bsrc := FileAccess.open("res://autoload/gesture_bridge.gd", FileAccess.READ)
	check(bsrc != null, "S13：gesture_bridge.gd 可读")
	if bsrc != null:
		var btext := bsrc.get_as_text()
		bsrc.close()
		var s0: int = btext.find("func start_gesture_process")
		var s1: int = btext.find("func stop_gesture_process")
		var s2: int = btext.find("func _exit_tree")
		var start_body := btext.substr(s0, s1 - s0)
		var stop_body := btext.substr(s1, s2 - s1)
		check(start_body.contains("_set_state(LoadState.LOADING)"), "S13：start 成功 spawn 段转 LOADING（源码证据链，无头不可达路径）")
		check(start_body.find("_set_state(LoadState.LOADING)") > start_body.find("if _process_pid < 0:"),
			"S13：LOADING 转换位于 spawn 失败分支之后（仅成功路径，防重入/无头分支不改状态）")
		check(stop_body.contains("_intentional_stop = true"), "S13：stop 置主动关标志（源码证据链）")
		check(btext.contains("func consume_intentional_stop() -> bool:"), "S13/S14：consume_intentional_stop 契约存在")

	# ---- 14. 批次 T 协议：init#1 分流 → camera_enum_received + 缓存 getter（P1-1）----
	bridge._camera_enum = {}
	bridge._camera_matrix = {}
	bridge._camera_errors = []
	check_eq(bridge.get_camera_enum(), {}, "P1-1：未收到 init 前 get_camera_enum()=空")
	check_eq(bridge.get_camera_matrix(), {}, "P1-1：未收到 init 前 get_camera_matrix()=空")
	check_eq(bridge.get_camera_errors(), [], "P1-1：未收到 camera_error 前 get_camera_errors()=空")
	var sig_enum: Array = []
	var sig_matrix: Array = []
	var sig_err: Array = []
	bridge.camera_enum_received.connect(func(cams: Array, cur: int) -> void: sig_enum.append([cams, cur]))
	bridge.camera_matrix_received.connect(func(res: Array, fps: Array) -> void: sig_matrix.append([res, fps]))
	bridge.camera_error_received.connect(func(id: int) -> void: sig_err.append(id))
	var st14: int = bridge.get_load_state()
	var pt14: float = float(bridge._last_packet_time)
	bridge.simulate_packet(JSON.stringify(
		{"type": "init", "cameras": [{"id": 0, "name": "Cam A"}, {"id": 1, "name": "Cam B"}], "current_camera": 1}))
	check_eq(sig_enum.size(), 1, "T12：init#1 → camera_enum_received 恰一次")
	if sig_enum.size() == 1:
		var pl: Array = sig_enum[0]
		check_eq((pl[0] as Array).size(), 2, "T12：cameras 载荷 2 项逐字透传")
		check_eq(String((pl[0] as Array)[1]["name"]), "Cam B", "T12：设备名逐字")
		check_eq(int(pl[1]), 1, "T12：current_camera=1")
	check_eq(bridge.get_load_state(), st14, "T12：init 不触发状态机（READY 判据仍=手势 JSON 首包）")
	check(bool(is_equal_approx(float(bridge._last_packet_time), pt14)),
		"T12：init 不重置 _last_packet_time（5s 链路超时判据不受枚举消息污染）")
	var ge: Dictionary = bridge.get_camera_enum()
	check_eq((ge["cameras"] as Array).size(), 2, "P1-1：缓存 getter cameras 与信号同源同值")
	check_eq(int(ge["current_camera"]), 1, "P1-1：缓存 getter current_camera 同值")
	# ---- 15. init#2 + camera_error（5 checks）----
	bridge.simulate_packet(JSON.stringify(
		{"type": "init", "resolutions": [[1920, 1080], [1280, 720]], "fps_options": [30, 60]}))
	check_eq(sig_matrix.size(), 1, "T12：init#2 → camera_matrix_received 恰一次")
	check_eq((bridge.get_camera_matrix()["resolutions"] as Array).size(), 2, "P1-1：缓存 resolutions 同值")
	check_eq((bridge.get_camera_matrix()["fps_options"] as Array).size(), 2, "P1-1：缓存 fps_options 同值")
	bridge.simulate_packet(JSON.stringify({"type": "camera_error", "id": 0}))
	bridge.simulate_packet(JSON.stringify({"type": "camera_error", "id": 2}))
	check_eq(sig_err.size(), 2, "T12：camera_error ×2 → camera_error_received 恰两次")
	check_eq(bridge.get_camera_errors(), [0, 2], "P1-1：错误 id 列表按序累积（置灰数据源）")
	# ---- 16. 混流正负例：init 与手势帧交替（4 checks）----
	var got_state: Array = []
	bridge.gesture_state_received.connect(func(d: Dictionary) -> void: got_state.append(d))
	bridge._set_state(0)   # LOADING（验证手势帧照常推 READY）
	bridge.simulate_packet(JSON.stringify({"type": "init", "cameras": [{"id": 0, "name": "C"}], "current_camera": 0}))
	bridge.simulate_packet(JSON.stringify({"left": null, "right": null, "timestamp": 1.0}))
	check_eq(int(bridge.get_load_state()), 1, "混流：init 后手势帧照常 LOADING→READY")
	check_eq(got_state.size(), 1, "混流：手势帧 gesture_state_received 照发一次")
	check_eq(sig_matrix.size(), 1, "混流：无 init#2 时矩阵信号不误发")
	bridge.simulate_packet(JSON.stringify({"type": "init", "resolutions": [[640, 480]], "fps_options": []}))
	check_eq(sig_matrix.size(), 2, "混流：交替 init#2 仍各断各的（第二次）")
	# ---- 17. 非法/未知 type 静默（3 checks）----
	var sig_all: int = sig_enum.size() + sig_matrix.size() + sig_err.size()
	bridge.simulate_packet(JSON.stringify({"type": "unknown_kind", "x": 1}))
	bridge.simulate_packet(JSON.stringify({"type": "init"}))
	check_eq(sig_enum.size() + sig_matrix.size() + sig_err.size(), sig_all,
		"T12：未知 type / 缺字段 init 静默忽略（不进状态机不发信号）")
	check_eq(int(bridge.get_load_state()), 1, "T12：静默消息不迁移状态（仍 READY）")
	check_eq(bridge.get_camera_enum()["cameras"], [{"id": 0.0, "name": "C"}],
		"T12：静默不污染既有缓存（最近一次合法 init#1 保持；偏离注记：JSON.parse 数值恒为 float，Godot 嵌套字典比较类型严格，plan 字面量 0 改 0.0 对齐回环类型）")
	bridge._set_state(st14)   # 批次 T 偏离注记：plan 原置段 16 末，会使段 17「仍 READY」恒红（st14=UNAVAILABLE），移至本处语义等价
	# ---- 18. 批次 U（U2，spec §6.1）：probe_result 分流基础（8 checks；缓存与超时语义归 test_u_bridge_protocol 分工）----
	var sig_probe: Array = []
	bridge.probe_result_received.connect(func(id: int, ok: bool, res: Array, fps: Array) -> void: sig_probe.append([id, ok, res, fps]))
	var st18: int = bridge.get_load_state()
	bridge.simulate_packet(JSON.stringify({"type": "probe_result", "id": 1, "ok": true, "resolutions": [[1280, 720], [640, 480]], "fps_options": [30, 60]}))
	check_eq(sig_probe.size(), 1, "U2：probe_result → probe_result_received 恰发一次")
	check_eq(int(bridge.get_load_state()), st18, "U2：probe_result 不进状态机（沿用 init/camera_error 先例）")
	bridge.simulate_packet(JSON.stringify({"left": null, "right": null, "timestamp": 1.0}))
	check_eq(int(bridge.get_load_state()), 1, "U2：probe_result 不重置 _last_packet_time（其后手势帧照常推 READY，链路超时判据不受污染）")
	bridge.simulate_packet(JSON.stringify({"type": "probe_result", "id": 2, "ok": false}))
	check_eq(sig_probe[1][1], false, "U2：ok=false 载荷照常分流")
	check_eq((sig_probe[1][2] as Array).size(), 0, "U2：ok=false 时 resolutions 缺省空 Array")
	check_eq((sig_probe[1][3] as Array).size(), 0, "U2：ok=false 时 fps_options 缺省空 Array")
	var ok_res: bool = sig_probe[0][0] == 1 and sig_probe[0][1] == true \
		and (sig_probe[0][2] as Array) == [[1280.0, 720.0], [640.0, 480.0]] and (sig_probe[0][3] as Array) == [30.0, 60.0]
	check(ok_res, "U2：载荷类型保真 id:int/ok:bool/resolutions:[[w,h]]/fps:[int]（JSON 回环 float 对齐）")
	bridge.simulate_packet(JSON.stringify({"type": "probe_result", "id": 3}))
	check_eq(sig_probe.size(), 3, "U2：缺 ok 键载荷不炸（.get 默认 false 防御，防坑 2）")
	finish()
