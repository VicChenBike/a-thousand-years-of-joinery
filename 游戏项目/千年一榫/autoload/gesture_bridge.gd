extends Node
## GestureBridge：UDP 三端口收发/解析/加载状态机/手势子进程生命周期（批次 R 全面改写）。
## 端口派生（spec §3.3）：基准 P=get_udp_port()=常量 9876（P2-3a 批次 W 规格 §3 单一真源，
## 存档 settings.udp_port 已退役不再消费）；
## 手势 JSON=P（Godot 绑定）/摄像头 JPEG=P+1（Godot 绑定）/控制命令=P+2（Python 绑定，Godot 发送）。
## 状态机（spec §9.1）：LOADING→(9876 合法包)→READY；LOADING→(45s 探测超时且 python 进程不在
## /9876 绑定失败/子进程失败)→UNAVAILABLE——批次 Z（Z4-②）超时判据=python 进程存活（pid 存活或
## 9878 被占），存活即延长就绪窗不判死（最坏启动预算 35s 振荡根除）；READY→(5s 无 9876 包)→
## UNAVAILABLE；UNAVAILABLE→(每 5s bind 试探 9878 + 开发模式重拉子进程成功)→LOADING→READY。
## 降级（spec §9.2）：9877 绑定失败仅摄像头窗降级不拖垮 9876；键鼠永远可用。

signal gesture_state_received(data: Dictionary)
signal gesture_event(event: Dictionary)
signal camera_frame_received(texture: ImageTexture)
signal load_state_changed(state: int)
signal camera_enum_received(cameras: Array, current_camera: int)
signal camera_matrix_received(resolutions: Array, fps_options: Array)
signal camera_error_received(id: int)
signal probe_result_received(id: int, ok: bool, resolutions: Array, fps_options: Array)   # 批次 U（U2，spec §6.1）
# 批次 Y（Y-A17，spec §3.2）：摄像头流开启真值边沿信号——open=流开启真值、device_id=最近
# 一次 camera_opened/camera_closed 事件设备 id（心跳电平纠偏时以枚举 current_camera 近似）。
signal camera_stream_changed(open: bool, device_id: int)

# 批次 W（N5，规格 §5）：最近一次 SWITCH_CAMERA 目标 id（ensure_camera_open/回落链写位，
# 供 settings_panel 摄像头按钮 OPENING 态判定回落目标；-1=本次会话未发过）。
var last_switch_camera_id := -1
# 批次 W（N9，规格 §5）：PROBE_MATRIX 探测在飞标志（探测与主流互斥；probe_result 到达或
# SWITCH_CAMERA 主流命令抢占时清除）。批次 W 审查 P2-A：在飞超时回收（丢包自愈），
# probe_timeout_ms 可注入（无头测试缩短）。
var _probe_in_flight := false
var _probe_sent_at_ms := -1
var probe_timeout_ms := 6000

enum LoadState { LOADING, READY, UNAVAILABLE }

const NO_PACKET_TIMEOUT_SEC := 5.0         # READY 后无 9876 包判链路断（§9.1）
# 批次 Z（Z4-②，spec §4-2）：就绪探测超时 15→45s——python 启动最坏预算 35s（WMI 4 链×5s +
# CAP 枚举 15s + 同步首开）远超旧 15s 窗 → 必判 UNAVAILABLE → 15s/5s 振荡（「连接连接连接」）。
# 且超时判定以 python 进程存活为准（见 _python_alive），存活即延长就绪窗。
const PROBE_TIMEOUT_SEC := 45.0            # LOADING 就绪探测超时（≥ 启动最坏预算 35s + 裕量）
const RETRY_INTERVAL_SEC := 5.0            # UNAVAILABLE 自动重试周期（§9.1）
const JPEG_MAX_INTERVAL_SEC := 1.0 / 30.0  # 9877 解码节流 ≤30fps（§3.3）
const JPEG_HEADER_LEN := 4                 # 4 字节小端 uint32 长度头（§3.3）
const ENUM_REQUEST_THROTTLE_MS := 1000     # 拉取模式节流：同一秒内最多一次（防菜单反复开合刷包）
# 批次 V-B2（spec §6.4）camera_error 自动回落节流常量随批次 Z（Z4-④）桥回落抢句柄退役删除
#（旧 CAMERA_FALLBACK_THROTTLE_MS=5000 留痕：恒零回落，节流概念不再需要）。
# P2-3a（批次 W 规格 §3）：基准端口单一真源——恒 9876（P/P+1/P+2 派生不变）。旧实现读存档
# settings.udp_port（0→9876），存档被改后与 launcher（环境变量默认 9876）互不通且无提示；
# 现与 launcher 语义恒一致。存档键 deprecated 退役不再消费（save_manager.gd defaults 注释留痕）。
const DEFAULT_UDP_PORT := 9876

# 批次 W（P1-2，规格 §5）：子进程死后重拉最小间隔（防 spawn 风暴退避）。
const RESPAWN_MIN_INTERVAL_SEC := 2.0

## 运行时入口相对路径（测试可改写以无头验证缺失分支）
var _runtime_res_path := "res://gesture_runtime/main.py"

# 批次 W（P1-3，规格 §5）：测试缝——无头测试注入高位端口验证 bind 重试（生产恒 -1 走
# DEFAULT_UDP_PORT，P2-3a 单一真源语义不变）；重试参数可注入（测试缩短等待）。
var _udp_port_override := -1
var udp_bind_retry_base := 2.0        # 首次重试等待（秒；2s 起指数退避）
var udp_bind_max_retries := 5         # 最多重试 5 次
var _udp_bind_fail_count := 0         # 9876 连续失败计数（成功清零）
var _udp_bind_next_at := -1.0         # 下次重 bind 时刻
var _jpeg_bind_fail_count := 0
var _jpeg_bind_next_at := -1.0
# 批次 W（P1-2）：子进程死后重拉退避截止时刻（-1=未置）
var _respawn_block_until := -1.0

var _udp: PacketPeerUDP              # 9876 手势 JSON（Godot 绑定）
var _jpeg_udp: PacketPeerUDP         # 9877 JPEG（Godot 绑定；失败单独降级 §13-3）
var _control_peer: PacketPeerUDP     # 9878 控制发送（Godot→Python）
var _state: int = LoadState.LOADING
var _process_pid: int = -1
var _last_packet_time: float = 0.0
var _udp_initialized: bool = false
var _jpeg_initialized: bool = false
var _last_jpeg_decode_time: float = -1000.0
var _probe_started_at: float = -1.0
var _last_retry_at: float = -1000.0
var _intentional_stop := false     # 批次 S13/S14：主动关标志（Q3）——stop 置位、consume 取走即清
var _camera_enum := {}       # P1-1：最近 init#1 载荷（未收到=空）
# 批次 Y（Y-A20，spec §2）：0 设备确认语义——仅 init#1 实收且 cameras 为空列表才为 true；
# 缓存空（{}）=未知（init#1 未达）≠0 设备，不得误判置灰。
var _camera_enum_zero := false
# 批次 Y（Y-A17，spec §3.2）：摄像头流开启真值——边沿事件（camera_opened/camera_closed）为主、
# 心跳 camera_open 电平字段周期校准兜底（防 UDP 丢事件真值卡死）。与链路 READY 两语义解耦：
# _state=READY 只代表 python 在（bridge :301-303 不再承担「摄像头开」语义）。
var camera_stream_open := false
var camera_stream_device_id := -1
# 批次 Y（Y-A16，spec §3.3）：开机记忆握手——spawn 成功后向 9878 下发
# SET_PREFERRED_CAMERA:<存档记忆设备名>。批次 AA（W4-1，spec §7.3）时序重构：
# ①下发统一收口 _tick_preferred_camera_handshake，且**探到 9878 已 bind（_probe_python_ready）
# 才发**——bind 前的包必被内核丢弃（症状③根因：旧 4×0.25s≈0.75s 窗全落在 python
# import cv2/mediapipe 的秒级 bind 之前）；②重试窗 4×0.25s → **30s 内 1s 间隔**
#【暂定值·待用户复验】（30s=重发上限而非等待时长，§22 裁决 7）；③止发判据
# 「init#1 到达即止」→「camera_opened 且 id 匹配记忆设备 / 窗过期」。
const PREFERRED_HANDSHAKE_WINDOW_SEC := 30.0  #【暂定值·待用户复验】重发窗上限（秒）
const PREFERRED_RESTORE_THROTTLE_MS := 3000   #【暂定值·待用户复验】开机恢复 SWITCH 节流（ms）
var preferred_handshake_interval_ms := 1000   # 重发间隔（旧 250ms 退役留痕；可注入）
var preferred_handshake_window_sec := PREFERRED_HANDSHAKE_WINDOW_SEC   # 窗上限（可注入）
var _preferred_device_name := ""
var _preferred_handshake_armed := false      # W4-1：重发期武装标志（bind 门控在 _tick）
var _preferred_handshake_deadline_ms := -1   # W4-1：重发窗上限时刻（绝对 ms）
var _preferred_next_at_ms := -1
# 批次 AA（W4-6，spec §7.3）：开机自动恢复——主恢复路径（旧「开设置面板才恢复」降级为
# 幂等再确认）。READY 边沿 / init#1 / camera_opened≠记忆 三入口 → 记忆设备 SWITCH（节流防刷）。
var _preferred_restore_last_ms := -1000000
# 批次 AD-5（F-2，需求 §4.2）：**三路启动指令下发共享同一节流记账**——握手 tick
# （_tick_preferred_camera_handshake）/ 开机恢复（_ensure_preferred_camera_restore）/
# 显式 ensure（ensure_camera_open）原先各自记账、互不相认（AB2 R1 P3-2 曾备案不改码），
# 同帧/同秒多路可各发一条 START_CAMERA_BY_NAME → Python 侧在飞窗口内反复接收重复指令。
# 新口径：单一账本（_start_send_*），**跨源同目标**在 gap 内只发一条；同源自重复仍由
# 各路既有节流（tick 1s / restore 3s）管辖（既有条数断言零弱化）；
# 显式 ensure 走 force=true **不被抑制**（批次 AD「用户点开必须照发」语义保护，但照常
# 记账——它发出后，自动两路在其 gap 内即被抑制）。可注入（start_send_shared_gap_ms）。
var start_send_shared_gap_ms := 1000
var _start_send_last_cmd := ""
var _start_send_last_src := ""
var _start_send_last_ms := -1000000
# 批次 AA 回修1（W4-P2-1，W4-6 语义修订）：用户主动关闭意图锁存——camera_closed(reason=release)
# / request_camera_release / stop_gesture_process 置位，_ensure_preferred_camera_restore 三入口
# （READY 边沿 / init#1 / camera_opened≠记忆）统一短路：**「用户主动关掉摄像头」优先于「恢复
# 记忆设备」**，根除被明确关掉的摄像头在 3s 节流窗过后被补发 SWITCH 重开（用户诉求「切换/
# 关闭后旧设备别再请求、已断开就别再连」）。锁存清除=显式再开（ensure_camera_open /
# start_gesture_process）。与 _intentional_stop 正交：后者被 consume_intentional_stop 一次性
# 取走（toast 抑制语义），不能承担跨入口持久门。
var _camera_release_intent := false
# 批次 AA 终审回修1（aarev P1-1）：Q3 启动 RELEASE 兜底哨兵——true=本会话已发过一次
# RELEASE_CAMERA（仅 _q3_release_camera_once 写位；会话内恰一次语义，防逐帧/逐重试刷包）。
var _q3_release_sent := false
# 批次 AB2 R1 审查回修1（P2-1）：「用户显式重枚举意图」锁存——置位点=request_camera_enum
# 显式重枚举公共入口（C6 摄像头钮 zero 态点击/D10 开下拉等用户触达路径；桥内部拉取一律
# 走 _pull_camera_enum 不置位，防自动路径自我解锁）；消费点=_spawn 漏斗 zero 态第二道门。
# zero 确认（_camera_enum_zero）下 respawn 仅在有此意图时放行——0 态下 watchdog 自愈重拉
# 改发「重枚举试探」（_request_reattach_probe，仅 GET_CAMERAS 零 spawn 零开镜），假阴性
# （设备在/枚举瞬时空）复确认到设备即解除 zero；**收到枚举结果（init#1 cameras）即清除**
# ——一次点击只兑一次 respawn 机会（无设备则回归零 spawn）。
# 与 _camera_release_intent（恢复锁存）正交：后者管「SWITCH 补发」，本锁存管「spawn」。
var _reattach_intent := false
# 批次 AC（领域二，spec §4.2-3）：**枚举未达待开握手**——ensure_camera_open 在枚举缓存空时
# 不盲发 SWITCH 而是置本哨兵（armed 握手 + 拉取枚举），init#1 到达由 _handle_meta 兑现：
# 首选非手机设备自动开（本轮显式开启意图不因枚举迟到而丢失）。一次性语义：
# 兑现即清零；由用户点击/ensure 显式开启置位，「仅拉取枚举」的内部路径不置位
# （防自动路径自我触发开镜）。
var _open_on_next_enum := false
# 批次 U（U2，spec §6.1/§6.3）：probe_result 缓存（id → {"ok","resolutions","fps_options"}；P1-1 缓存模式）
var _probe_matrix_cache: Dictionary = {}
# 批次 U（U4，spec §6.3）：ensure_camera_open 测试接缝——true 时 start_gesture_process 视为已启动
#（无头/导出无法真拉起；复核终版短路判据表驱动的第三态「start true」由它承载）
var _simulate_start_ok := false
var _camera_matrix := {}     # P1-1：最近 init#2 载荷
var _camera_errors: Array = []   # P1-1：历史 camera_error id（置灰数据源；V-B2 起成功即清，见 _handle_meta）
var _last_enum_request_ms: int = -1000000   # 拉取模式：上次 GET_CAMERAS 发出时刻（负大值=从未发过）
# 批次 V-B2（V16，spec §6.4）：camera_error 统一提示——last_good=最近一次成功设备
#（init#1 到达即以 current_camera 更新，Python 切换/开启成功必发 init#1；记录保留供诊断）。
# 批次 Z（Z4-④）：自动回落 SWITCH（回旧设备）抢句柄路径退役 → _last_fallback_ms/节流删除。
var _last_good_camera_id := -1

func _ready() -> void:
	_init_udp()
	_init_jpeg_udp()
	_last_packet_time = _now()
	_start_orphan_cleanup_async()   # 批次 Z（Z4-①-②，spec §4-1）：启动路径孤儿清理（探测→判定→PID 精确终止）
	# 批次 AA 终审回修1（aarev P1-1）：Q3（手势关＋摄像头关）启动兜底——打包形态 launcher 已
	# 代拉常驻 python 时，boot 门（main.gd）不 start、桥不 spawn、restore 已受门，但常驻 python
	# 自身启动序会「首开」摄像头（hand_tracking_server 首开前查 RELEASE/SHUTDOWN）→ 启动即显式
	# 发一次 RELEASE_CAMERA 兜住「进程在而摄像头被首开」的场景（会话内恰一次，见方法注）。
	_q3_release_camera_once()

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

# ======================================================================
# 批次 Z（Z4-①-②，spec §4-1）：启动孤儿清理——双保险之②。
# 与 python 侧父/宿主看门狗（Z4-①-①）互补：看门狗覆盖「游戏进程死亡」即时路径；本清理
# 覆盖「看门狗不适用/存量无 owner 进程/上局硬杀残留」——新局启动时先探测进程表，按
# select_orphan_pids 纯函数判定，再以 PID 精确 Stop-Process（绝不按名称/匹配串 taskkill：
# 批次 Z 深查曾发生 taskkill 匹配串误杀 bash 子 shell 事故）。
# 双重判据：命令行精确匹配运行时形态（gesture_runtime 脚本 + python 形态）∧（父已死 ∨ owner 已死）；
# 9878 端口占用信息不单独构成击杀资格（端口可能被无关程序持有）。
# 零头纪律：仅 Windows 非无头执行（--script 测试恒 headless 跳过，零真实进程表触碰）。
# 编码硬化（活体复核实证风险）：PowerShell 管道默认 OEM/GBK 输出，而 OS.execute 按 UTF-8
# 解码——GBK 尾字节可取 0x5C('\'）落在 CJK 命令行（本项目路径恒含中文）里会破坏 JSON 转义
# → 解析失败静默零击杀（首轮实测多数快照侥幸未命中，属概率性）。强制子进程 UTF-8 输出根除。
const ORPHAN_PROBE_PS := "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; Get-CimInstance Win32_Process | Select-Object ProcessId,ParentProcessId,CommandLine | ConvertTo-Json -Compress"
var _orphan_cleanup_thread: Thread = null
var _orphan_cleanup_done := false

## 启动清理入口（_ready 调）：独立线程跑 PowerShell 只读探测 + 判定 + 精确终止，
## 不阻塞主线程启动帧；_process 轮询收尸（wait_to_finish 即返），_exit_tree 兜底收尸。
func _start_orphan_cleanup_async() -> void:
	if DisplayServer.get_name() == "headless":
		return   # 无头测试/CI：不碰真实进程表
	if OS.get_name() != "Windows":
		return   # 探测/终止链为 Win32 PowerShell 实现（本项目当前仅 Windows 目标）
	if _orphan_cleanup_thread != null:
		return
	_orphan_cleanup_done = false
	_orphan_cleanup_thread = Thread.new()
	_orphan_cleanup_thread.start(_orphan_cleanup_worker)

func _orphan_cleanup_worker() -> void:
	var entries: Array = _probe_process_table()
	var victims: Array = select_orphan_pids(entries)
	if not victims.is_empty():
		var ids: PackedStringArray = []
		for v: Variant in victims:
			ids.append(str(int(v)))
		print("[孤儿清理] 检测到 %d 个无主手势运行时进程，按 PID 精确终止：%s" % [victims.size(), ",".join(ids)])
		# PID 精确终止（Stop-Process -Id <显式 PID 列表>；无匹配串、无通配——误杀防护硬纪律）
		OS.execute("powershell", ["-NoProfile", "-NonInteractive", "-Command",
			"Stop-Process -Id %s -Force -ErrorAction SilentlyContinue" % ",".join(ids)], [], true)
	else:
		print("[孤儿清理] 无无主手势运行时进程（判定基于 父/宿主存活 × 命令行形态 双重判据）")
	_orphan_cleanup_done = true

## 进程表只读探测（PowerShell Win32_Process → Dictionary 数组；失败/解析失败回空=静默降级零误杀）。
func _probe_process_table() -> Array:
	var out: Array = []
	var err: int = OS.execute("powershell", ["-NoProfile", "-NonInteractive", "-Command",
		ORPHAN_PROBE_PS], out, true)
	if err != 0 and out.is_empty():
		return []
	var entries: Array = []
	for line: Variant in out:
		# trim_prefix BOM：强制 UTF-8 后首行可能带 ﻿，防 begins_with 判据失配
		var t := String(line).strip_edges().trim_prefix("﻿")
		if t.is_empty() or not (t.begins_with("[") or t.begins_with("{")):
			continue
		var parsed: Variant = JSON.parse_string(t)
		if typeof(parsed) == TYPE_ARRAY:
			for e: Variant in (parsed as Array):
				if typeof(e) == TYPE_DICTIONARY:
					entries.append(e)
		elif typeof(parsed) == TYPE_DICTIONARY:
			entries.append(parsed)
	return entries

## 孤儿判定纯函数（无头直测，test_z_camera_lifecycle 段①）：输入进程表
## → 输出应终止 PID 集合（按表序）。
## 字段双形态兼容（活体实测回修）：Win32_Process/Select-Object 实况键为 PascalCase
##（ProcessId/ParentProcessId/CommandLine），夹具/手写表为小写（pid/ppid/cmdline）——
## 单一归一点 _entry_field 双读，任一形态均正确判定（首版只读小写致真机探测全表失配、
## 孤儿一个不杀：纯函数单测绿而集成红的口径教训，PascalCase 正例随本修锁进测试段①）。
## 判据（双重）：①命令行匹配运行时形态 _is_gesture_runtime_cmd；②父已死（ppid 不在存活表）
## ∨ owner 已死（cmdline --owner-pid 不在存活表）。两判据缺一不杀——含「父活 owner 死」
##（编辑器硬杀）、「父死无 owner」（py.exe 包装）两种正例形态与多重反例（见测试段①）。
## 防误杀硬护栏：pid≤4（系统保留）与本进程 pid 一票否决。
func select_orphan_pids(entries: Array) -> Array:
	var alive: Dictionary = {}
	for e: Variant in entries:
		if typeof(e) == TYPE_DICTIONARY:
			var ep: Variant = _entry_field(e, ["pid", "ProcessId"])   # 显式 Variant（:= 从 Variant 推断在本工程告警即错误）
			if ep != null:
				alive[int(ep)] = true
	var own: int = OS.get_process_id()
	var out: Array = []
	for e: Variant in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		var pid_v: Variant = _entry_field(d, ["pid", "ProcessId"])
		if pid_v == null:
			continue
		var pid := int(pid_v)
		if pid <= 4 or pid == own:
			continue
		var cv: Variant = _entry_field(d, ["cmdline", "CommandLine"])
		var cmd := "" if cv == null else str(cv)
		if not _is_gesture_runtime_cmd(cmd):
			continue   # 判据①：命令行必须精确匹配运行时形态（端口占用/名称近似不算）
		var pp: Variant = _entry_field(d, ["ppid", "ParentProcessId"])
		var ppid := 0 if pp == null else int(pp)
		var parent_dead := ppid <= 0 or not alive.has(ppid)
		var owner := _owner_pid_from_cmd(cmd)
		var owner_dead := owner >= 0 and not alive.has(owner)
		if parent_dead or owner_dead:
			out.append(pid)
	return out

## 字段双形态读取（小写夹具形态 / Win32 实况 PascalCase 形态；缺键回 null）。
static func _entry_field(d: Dictionary, names: Array) -> Variant:
	for n: Variant in names:
		if d.has(n):
			return d[n]
	return null

## 命令行形态匹配（防误杀核心）：须同时命中「运行时脚本标记」与「python 形态」。
## 标记：hand_tracking_server.py，或 gesture_runtime + main.py（双子串同现）；
## 形态：python（python.exe/pythonw）、py.exe、裸 "py "（编辑器态 py -3 命令行实况）。
## 反例锁：grep "hand_tracking_server.py" 类用户命令（非 python 形态）永不命中。
static func _is_gesture_runtime_cmd(cmd: String) -> bool:
	var c := cmd.to_lower()
	var marker: bool = c.contains("hand_tracking_server.py") \
		or (c.contains("gesture_runtime") and c.contains("main.py"))
	if not marker:
		return false
	return c.contains("python") or c.contains("py.exe") \
		or c.begins_with("py ") or c.contains(" py ")

## 从命令行提取 --owner-pid <N>（无则 -1=未携带，走父判据兜底）。
static func _owner_pid_from_cmd(cmd: String) -> int:
	var rx := RegEx.new()
	if rx.compile("--owner-pid[=\\s]+(\\d+)") != OK:
		return -1
	var m := rx.search(cmd)
	if m == null:
		return -1
	return int(m.get_string(1))

## 幂等初始化：绑定 9876。--script 无头测试中树未启动时 _ready 不触发，
## 测试可显式调用本方法完成初始化（行为与 _ready 等价）。
## 批次 W（P1-3，规格 §5）：绑定失败不再置 _udp_initialized（允许重入重 bind）——失败计数
## +指数退避调度（2s 起翻倍，最多 5 次），到点由 _retry_binds 重试；成功清计数并置位守卫。
func _init_udp() -> void:
	if _udp_initialized:
		return
	_udp = PacketPeerUDP.new()
	var port: int = get_udp_port()
	var err: Error = _udp.bind(port)
	if err != OK:
		_udp.close()
		_udp = null
		_udp_bind_fail_count += 1
		_udp_bind_next_at = _now() + udp_bind_retry_base * pow(2.0, float(_udp_bind_fail_count - 1))
		push_error("UDP 绑定失败（err=%d，端口 %d 可能被占用），手势不可用（键鼠仍可用）；%.1fs 后重试（%d/%d）"
			% [err, port, udp_bind_retry_base * pow(2.0, float(_udp_bind_fail_count - 1)), _udp_bind_fail_count, udp_bind_max_retries])
		_set_state(LoadState.UNAVAILABLE)
		return
	_udp_initialized = true
	_udp_bind_fail_count = 0
	_udp_bind_next_at = -1.0
	_probe_started_at = _now()

## 9877 独立绑定：失败仅降级摄像头窗（§13-3），不拖垮 9876 手势链路。
## 批次 W（P1-3）：与 _init_udp 同款失败重入+指数退避（不置 _jpeg_initialized）。
func _init_jpeg_udp() -> void:
	if _jpeg_initialized:
		return
	_jpeg_udp = PacketPeerUDP.new()
	var err: Error = _jpeg_udp.bind(get_frame_port())
	if err != OK:
		_jpeg_udp.close()
		_jpeg_udp = null
		_jpeg_bind_fail_count += 1
		_jpeg_bind_next_at = _now() + udp_bind_retry_base * pow(2.0, float(_jpeg_bind_fail_count - 1))
		push_error("JPEG 端口绑定失败（err=%d，端口 %d），摄像头窗降级（手势 JSON 不受影响）；%.1fs 后重试"
			% [err, get_frame_port(), udp_bind_retry_base * pow(2.0, float(_jpeg_bind_fail_count - 1))])
		return
	_jpeg_initialized = true
	_jpeg_bind_fail_count = 0
	_jpeg_bind_next_at = -1.0

## 批次 W（P1-3）：绑定重试调度——到点即重入 _init_udp/_init_jpeg_udp；成功后 9876 回
## LOADING（就绪探测周期重启）。超过 udp_bind_max_retries 不再调度（保持 UNAVAILABLE 静默）。
func _retry_binds(now: float) -> void:
	if not _udp_initialized and _udp_bind_fail_count > 0 \
			and _udp_bind_fail_count <= udp_bind_max_retries and now >= _udp_bind_next_at:
		_init_udp()
		if _udp_initialized:
			_set_state(LoadState.LOADING)
	if not _jpeg_initialized and _jpeg_bind_fail_count > 0 \
			and _jpeg_bind_fail_count <= udp_bind_max_retries and now >= _jpeg_bind_next_at:
		_init_jpeg_udp()

## 批次 W（P1-2，规格 §5）：子进程存活周期校验——死亡（含崩溃/被杀）即清 pid + 转
## UNAVAILABLE + 置重拉退避（RESPAWN_MIN_INTERVAL_SEC 防 spawn 风暴）；真实重拉并入
## W7 重导清单⑧（无头仅验判死与退避调度）。
func _check_process_alive() -> void:
	if _process_pid < 0:
		return
	if OS.is_process_running(_process_pid):
		return
	push_warning("手势子进程消失（pid=%d），转 UNAVAILABLE 退避重拉（%.1fs 内不再 spawn）"
		% [_process_pid, RESPAWN_MIN_INTERVAL_SEC])
	_process_pid = -1
	_respawn_block_until = _now() + RESPAWN_MIN_INTERVAL_SEC
	_set_state(LoadState.UNAVAILABLE)

## 基准端口 P：恒常量 DEFAULT_UDP_PORT=9876（P2-3a 批次 W 规格 §3 单一真源——存档
## settings.udp_port 退役不再消费，键保留在档仅作兼容；注释与常量见本文件头/SaveManager defaults）。
## 9876/9877/9878 = P/P+1/P+2（spec §3.3 终态）。
func get_udp_port() -> int:
	# 批次 W（P1-3 测试缝）：override ≥0 仅无头测试注入；生产恒 -1 → DEFAULT_UDP_PORT=9876
	#（P2-3a 单一真源不变）。
	return _udp_port_override if _udp_port_override >= 0 else DEFAULT_UDP_PORT

func get_frame_port() -> int:
	return get_udp_port() + 1

func get_control_port() -> int:
	return get_udp_port() + 2

func get_load_state() -> int:
	return _state

func _set_state(s: int) -> void:
	if s != _state:
		_state = s
		if s == LoadState.LOADING:
			_probe_started_at = _now()
		if s == LoadState.READY and _camera_enum.is_empty():
			_pull_camera_enum()   # 拉取模式：转 READY 且枚举缓存空 → 自动拉取一次（节流护栏兜底；
			# 批次 AB2 R1 回修1：自动路径不置重枚举意图，走内部漏斗）
		if s == LoadState.READY:
			# 批次 AA（W4-6，spec §7.3）：开机自动恢复主入口——首个 9876 包（READY 边沿）
			# 即补发记忆设备 SWITCH（不依赖开设置面板；枚举未达时由 init#1 入口续接）。
			_ensure_preferred_camera_restore()
		load_state_changed.emit(s)

func _process(_delta: float) -> void:
	var now := _now()
	if _orphan_cleanup_thread != null and _orphan_cleanup_done:
		# 批次 Z（Z4-①-②）：孤儿清理线程收尸（已完成 → wait_to_finish 即返，不阻塞帧）
		_orphan_cleanup_thread.wait_to_finish()
		_orphan_cleanup_thread = null
	_check_process_alive()   # 批次 W（P1-2）：子进程存活周期校验
	_retry_binds(now)        # 批次 W（P1-3）：绑定失败重试调度
	_poll_udp()
	_poll_jpeg(now)
	match _state:
		LoadState.LOADING:
			if _probe_started_at != -1.0 and now - _probe_started_at > PROBE_TIMEOUT_SEC:
				# 落地实况修正：哨兵判据由 >= 0.0 改为 != -1.0——_now() 为进程启动秒数，
				# 测试注入 now-16.0 类「N 秒前」时间戳在进程启动 16s 内为合法负值，
				# >= 0.0 会把其误判为未设置哨兵（R-B-1 第 10 段实证）；-1.0 才是未设置哨兵。
				if _python_alive():
					# 批次 Z（Z4-②，spec §4-2）：判定以 python 进程存活为准——单次未就绪
					# 不转 UNAVAILABLE，重置就绪窗继续等（启动预算内零 UNAVAILABLE 抖动）。
					_probe_started_at = now
				else:
					_set_state(LoadState.UNAVAILABLE)
					push_warning("手势加载超时（%d 秒未就绪）：无摄像头或手势程序未运行（键鼠仍可用）"
						% int(PROBE_TIMEOUT_SEC))
		LoadState.READY:
			if now - _last_packet_time > NO_PACKET_TIMEOUT_SEC:
				_set_state(LoadState.UNAVAILABLE)
				push_error("手势链路中断（5 秒无 9876 包），转 UNAVAILABLE 自动重试")
		LoadState.UNAVAILABLE:
			if now - _last_retry_at >= RETRY_INTERVAL_SEC:
				_last_retry_at = now
				if _probe_python_ready():
					# 服务驻留（probe bind 失败=9878 被占=python 在）→ 回 LOADING 等包。
					# spawn 仍限 editor（打包态 python 在=launcher 已拉起，spawn 会造双实例）。
					if now >= _respawn_block_until:
						if OS.has_feature("editor") and DisplayServer.get_name() != "headless":
							_spawn()
					_set_state(LoadState.LOADING)
				else:
					# 批次 W 审查 P1-B 回修：子进程真死闭环——probe bind 成功=9878 已释放=
					# python 不在，旧口径零动作致 UNAVAILABLE 永久滞留（W7 重导清单⑧「杀进程→
					# 桥自动重拉」的开发态落点）。补互补分支：编辑器形态 ∧ 退避窗外 → 重拉；
					# 重拉成功回 LOADING，失败保持 UNAVAILABLE 等下轮。
					# 批次 Y（Y-A21，㉑）：打包形态 respawn 通路注册——判据由「editor ∧ 非无头」
					# 放宽为「非无头」（打包态真死亦自动重拉；spawn 可行性由 start_gesture_process
					# 内 _packaged_spawn_plan 纯函数裁决，不可行保持 UNAVAILABLE 等下轮+按钮重试，
					# 不得假死 READY）。_spawn_hook 为无头测试探缝（headless 判据由 hook 绕行以可断言）。
					var spawned := false
					if now >= _respawn_block_until and (not _spawn_hook.is_null()
							or DisplayServer.get_name() != "headless"):
						spawned = _spawn()
						# 批次 AB2 R1 审查回修1（P2-1）：zero 态 ∧ 无用户重枚举意图 → 漏斗门拒
						# respawn（见 _spawn），此处改发零 spawn 的重枚举试探复确认设备。
						if not spawned and _camera_enum_zero and not _reattach_intent:
							_request_reattach_probe()
						if spawned:
							_set_state(LoadState.LOADING)
	# 批次 Y（Y-A16）→ 批次 AA（W4-1）：开机记忆握手重发调度（bind 探测门 + 1s 间隔 +
	# 30s 窗上限；止发判据见 _tick_preferred_camera_handshake）
	_tick_preferred_camera_handshake()

## 批次 W 审查 P1-B：spawn 单一漏斗——_spawn_hook 探缝（测试注入计数替身）优先，
## 生产走 start_gesture_process（内含防重入门/导出判据/headless 判据/退避门）。
## 批次 Y（Y-A16）：spawn 成功（含 hook 替身）→ 开机记忆握手首发（重发调度见 _tick）。
var _spawn_hook := Callable()
func _spawn() -> bool:
	# 批次 AA 终审回修1（aarev P1-1）：设置门前置——Q3（双关）下自愈重拉不得 spawn（含 hook
	# 计数替身路径一并短路：UNAVAILABLE 两分支均经本漏斗，boot 门只管首拉不管自愈）。
	# 旧漏（终审实证）：判据只有「editor ∧ 非无头 ∧ 退避窗外」，Q3 下编辑器形态 45s+5s 后
	# 真拉起 python → python 启动序首开摄像头，Q3「关掉摄像头」跨重启失效。
	if not _settings_allow_camera():
		return false
	# 批次 AB2 R1 审查回修1（P2-1）：zero 态 respawn 第二道门——_settings_allow_camera 系
	# 「gesture_input ∨ gesture_camera_enabled」OR 门，B4 只写 gesture_input=false，0 态
	# OR 仍放行 → respawn 可达；真无设备机 python CAP 必败无害，但枚举**假阴性**（设备在、
	# 枚举返回空，如被占用/驱动抖动）下 respawn 出的 python 启动序可能真开镜，且 0 态
	# q3 兜底不发（需双键皆关）→ 前提不闭合。补门：zero 确认 ∧ 无「用户显式重枚举意图」
	# → 拒一切 respawn（含 hook 替身路径一并短路，与设置门同款漏斗语义）；意图由
	# request_camera_enum 置位（C6 摄像头钮点击/D10 开下拉等用户触达路径）、收到枚举结果
	# （init#1 cameras）清除。C6/C8 链不破坏：用户点击 → 意图置位 → respawn 放行 →
	# python 活 → init#1 非空边沿 → zero 解除 ∧ 意图清除 ∧ ensure 自动开（有设备则开）。
	if _camera_enum_zero and not _reattach_intent:
		return false
	if not _spawn_hook.is_null():
		var hook_ok: bool = _spawn_hook.call()
		if hook_ok:
			_begin_preferred_camera_handshake()
		return hook_ok
	return start_gesture_process()

## 批次 Y（Y-A21，㉑，spec §2）：打包 respawn 可行性判定纯函数（无头直测）。
## 打包布局实证（构建产物/千年一榫_Windows_EXE/）：gesture_runtime/ 外置随包（pck
## exclude_filter 排除、随包分发），入口 main.py、嵌入式解释器 python/python.exe。
## 返回 {spawnable, script, interpreter, reason}；不可行 → 调用方明确降 UNAVAILABLE
##（按钮可重试恢复，不得假死 READY）。
static func _packaged_spawn_plan(exe_dir: String, runtime_main_exists: bool,
		interpreter_exists: bool) -> Dictionary:
	var script_p := String(exe_dir).path_join("gesture_runtime/main.py")
	var interp_p := String(exe_dir).path_join("gesture_runtime/python/python.exe")
	if not runtime_main_exists:
		return {"spawnable": false, "script": script_p, "interpreter": interp_p,
			"reason": "runtime_missing"}
	if not interpreter_exists:
		return {"spawnable": false, "script": script_p, "interpreter": interp_p,
			"reason": "interpreter_missing"}
	return {"spawnable": true, "script": script_p, "interpreter": interp_p, "reason": ""}

## 批次 Y（Y-A21）：打包形态 spawn/respawn——launcher 首拉后子进程死亡可重拉。
## 路径解析与可行性经 _packaged_spawn_plan 纯函数；不可行 → 静默 false（UNAVAILABLE
## 5s 重试与按钮重试兜底，不假死 READY）。
## 批次 Y 审查② P1-1：在场门前置——防重入门只认本进程 spawn 的 pid（launcher 拉起的
## python 恒 _process_pid=-1 穿透首门），此处 9878 probe 在场（python 健康）即仅探测不
## spawn，真死才 create_process——防 python bind 接管序向旧实例发 SHUTDOWN 杀健康进程
##（双实例接管重启/摄像头闪断数秒根因）。_process 循环 python 在场分支「不 spawn」口径
## 不变（对照基准）。
func _spawn_packaged() -> bool:
	if _probe_python_ready():
		return false
	var exe_dir := OS.get_executable_path().get_base_dir()
	var plan := _packaged_spawn_plan(exe_dir,
		FileAccess.file_exists(String(exe_dir).path_join("gesture_runtime/main.py")),
		FileAccess.file_exists(String(exe_dir).path_join("gesture_runtime/python/python.exe")))
	if not bool(plan["spawnable"]):
		return false
	return _packaged_spawn_exec(plan)

## 批次 Y 审查② P1-1：打包 spawn 执行段（测试缝拆分——无头子类覆写拦截 create_process，
## 行为级断言在场门 probe ready→零 create、真死→create 恰一次；生产语义与拆分前等价）。
func _packaged_spawn_exec(plan: Dictionary) -> bool:
	var args: PackedStringArray = [String(plan["script"]), "--port", str(get_udp_port()),
		"--owner-pid", str(OS.get_process_id())]   # 批次 Z（Z4-①）：宿主 PID → python 父进程看门狗
	_process_pid = OS.create_process(String(plan["interpreter"]), args)
	if _process_pid < 0:
		push_error("打包形态手势子进程重拉失败（嵌入式解释器创建失败），手势不可用")
		_set_state(LoadState.UNAVAILABLE)
		return false
	_respawn_block_until = -1.0
	_set_state(LoadState.LOADING)
	_begin_preferred_camera_handshake()
	return true

## 批次 Z（Z4-②，spec §4-2）：python 进程存活判据（就绪超时是否转 UNAVAILABLE 的唯一裁决）。
## pid 已知（本桥 spawn 的编辑器态）→ OS.is_process_running；pid 未知（launcher 代拉/打包态）
## → 9878 bind 试探（被占=服务驻留）。两判据任一命中即视为存活。
func _python_alive() -> bool:
	if _process_pid >= 0 and OS.is_process_running(_process_pid):
		return true
	return _probe_python_ready()

## 9876 收包轮询（从 _process 拆出，测试可直调）
func _poll_udp() -> void:
	if _udp == null:
		return
	while _udp.get_available_packet_count() > 0:
		var bytes: PackedByteArray = _udp.get_packet()
		simulate_packet(bytes.get_string_from_utf8())

## 9877 JPEG 轮询：队列只解最新一帧（陈旧帧静默丢弃）、≤30fps 节流（§3.3）
func _poll_jpeg(now: float) -> void:
	# 审查回修 P2-3：spec §3.3「乱序/陈旧帧（超 200ms）丢弃」由本函数「排空队列只解最新一包 +
	# 30fps 节流」等价覆盖——陈旧包必然被更新的包覆盖或因节流被跳过，无需显式 200ms 判据（计划审查备案）。
	# 落地实况修正：节流判据前置到排空之前——节流窗口内不排空（包留队列待窗口过后只解最新），
	# 否则窗口内到达的包被排空即弃、窗口过后无包可解（R-B-1 第 7 段「节流窗口过后恢复解码」实证）。
	if _jpeg_udp == null:
		return
	if now - _last_jpeg_decode_time < JPEG_MAX_INTERVAL_SEC:
		return  # 节流窗口内不解码（不排空，最新包留队）
	var newest := PackedByteArray()
	while _jpeg_udp.get_available_packet_count() > 0:
		newest = _jpeg_udp.get_packet()  # 逐个覆盖：仅保留队列末（最新）包
	if newest.is_empty():
		return
	_last_jpeg_decode_time = now
	var tex := decode_jpeg_packet(newest)
	if tex != null:
		camera_frame_received.emit(tex)

## 9877 包解码（纯函数可无头直测）：4 字节小端长度头校验，不符/解码失败 → null 静默丢帧
func decode_jpeg_packet(pkt: PackedByteArray) -> ImageTexture:
	if pkt.size() <= JPEG_HEADER_LEN:
		return null
	var declared: int = pkt.decode_u32(0)
	if declared != pkt.size() - JPEG_HEADER_LEN:
		return null
	var img: Image = Image.new()
	var err: Error = img.load_jpg_from_buffer(pkt.slice(JPEG_HEADER_LEN))
	if err != OK:
		return null
	return ImageTexture.create_from_image(img)

## 注入/收包统一入口：解析 → 归一化 → 状态转移 → 发信号（palm_size 等新字段原样透传）
func simulate_packet(json_text: String) -> void:
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	# 批次 T（T12，spec §6.1）：9876 带内消息分流——type 分流优先（init/camera_error 走新分支并
	# return：不进状态机、不重置 _last_packet_time）；未知 type 静默忽略；其余维持 left/right 校验。
	var msg_type := String(d.get("type", ""))
	# 批次 U（U2，spec §6.1）：probe_result 分流——沿用 init/camera_error 先例：不进状态机、
	# 不重置 _last_packet_time；写缓存后发信号（先写后 emit，后挂订阅者经 getter 直读）。
	if msg_type == "probe_result":
		_handle_probe_result(d)
		return
	# 批次 Y（Y-A17，spec §3.2）：camera_opened/camera_closed 带内事件分流——不进状态机、
	# 不重置 _last_packet_time（probe_result 同款口径）；写开启真值缓存后发边沿信号。
	if msg_type == "camera_opened" or msg_type == "camera_closed":
		_handle_camera_event(d, msg_type)
		return
	if msg_type == "init" or msg_type == "camera_error":
		_handle_meta(d, msg_type)
		return
	if not d.has("left") and not d.has("right"):
		return
	_normalize(d)
	_last_packet_time = _now()
	if _state != LoadState.READY:
		_set_state(LoadState.READY)
	# 批次 Y（Y-A17，spec §3.2）：心跳 camera_open 电平字段——事件丢失时的周期校准兜底。
	# 仅显式携带该键的包参与校准（老协议包零回归）；与真值不一致时以电平为准并广播边沿。
	# 本分支保留链路 READY 语义（上方 _set_state(READY) 不废止——假真值废除仅指「开启」语义）。
	if d.has("camera_open"):
		var lvl: bool = bool(d.get("camera_open", false))
		if lvl != camera_stream_open:
			camera_stream_open = lvl
			camera_stream_device_id = int((get_camera_enum() as Dictionary).get("current_camera", -1))
			camera_stream_changed.emit(camera_stream_open, camera_stream_device_id)
	gesture_state_received.emit(d)

## 批次 Y（Y-A17，spec §3.2）：摄像头流开启真值消费——先写缓存后 emit（probe_result 先例）。
## 事件不进状态机、不重置 _last_packet_time；边沿幂等（真值未翻转不重复广播）。
## Y-A18 附带：摄像头事件（切换成功/重连成功/RELEASE）后刷新设备枚举缓存
##（request_camera_enum→GET_CAMERAS，1s 节流内建——重连成功不发 init#1 的缓存陈旧根除）。
## Y-A16 附带：camera_opened 且设备==记忆设备（名字匹配）→ 按存档值追发既有
## SET_RESOLUTION/SET_FPS（开机首开 res/fps 记忆恢复，零新协议；防跨设备串值语义同 V17）。
func _handle_camera_event(d: Dictionary, msg_type: String) -> void:
	var eid: int = int(d.get("id", -1))
	var opened := msg_type == "camera_opened"
	# 批次 AA 回修1（W4-P2-1）：release 意图判定源=camera_closed 的 reason 字段（python
	# RELEASE_CAMERA/主动释放路径 _emit_camera_closed("release") 单点合成回执）——置锁存后
	# restore 三入口统一短路；device_lost 等非 release 关闭不置（W4-6 开错设备兜底保持）。
	if not opened and String(d.get("reason", "")) == "release":
		_camera_release_intent = true
	if opened != camera_stream_open:
		camera_stream_open = opened
		camera_stream_device_id = eid
		if opened:
			var cams: Array = (get_camera_enum() as Dictionary).get("cameras", [])
			var mem_id := _resolve_target_camera_id(cams, _memory_camera_device_name())
			if mem_id >= 0 and eid == mem_id:
				var mem_res := _memory_camera_res()
				if mem_res != "":
					send_control("SET_RESOLUTION:%d:%s" % [eid, mem_res])
				var mem_fps := _memory_camera_fps()
				if mem_fps > 0:
					send_control("SET_FPS:%d:%d" % [eid, mem_fps])
		camera_stream_changed.emit(camera_stream_open, eid)
	# 批次 AA（W4-1）：camera_opened 且 id 匹配记忆设备 → 握手止发（事件侧即时收束）
	if _preferred_handshake_satisfied():
		_preferred_handshake_armed = false
	# 批次 AA（W4-6）：camera_opened≠记忆设备（python 开错/回落缺省）→ 补发恢复兜底
	_ensure_preferred_camera_restore()
	_pull_camera_enum()   # 批次 AB2 R1 回修1：事件后刷新=桥内部路径，不置重枚举意图

## 批次 Y（Y-A17/Y-A16）：流开启真值公开只读查询（设置面板按钮态/0 摄像头门/HUD 三真值门消费入口）。
func is_camera_stream_open() -> bool:
	return camera_stream_open

## 批次 Y（Y-A20）：0 设备确认公开查询——仅 init#1 实收空列表为 true（缓存空=未知）。
func is_camera_enum_zero() -> bool:
	return _camera_enum_zero

## 批次 T（T12，spec §6.1/§6.3）：init#1/init#2/camera_error 解析分流 + 热路径缓存（P1-1）。
## 缓存先写后 emit：后挂订阅者（CameraMenu）可经 getter 首帧直读，不丢一次性 init 消息。
func _handle_meta(d: Dictionary, msg_type: String) -> void:
	if msg_type == "init" and d.has("cameras"):
		_camera_enum = {"cameras": d.get("cameras", []), "current_camera": int(d.get("current_camera", 0))}
		# 批次 AB2（2026-09-25，「电脑没有摄像头」分支）：0 设备确认**边沿**判定——
		# false→true=「本机无摄像头」确认（→ B4 强制手势交互置关写档）；
		# true→false=「用户外接摄像头后重枚举到设备」（→ C8 记忆名/首项自动开）。
		var prev_zero := _camera_enum_zero
		_camera_enum_zero = (_camera_enum["cameras"] as Array).is_empty()
		# 批次 AB2 R1 审查回修1（P2-1）：枚举结果已到达 → 清除「用户显式重枚举意图」
		# （一次点击只兑一次 respawn 机会；C8 链不依赖意图——边沿 ensure 直接放行）。
		_reattach_intent = false
		if _camera_enum_zero and not prev_zero:
			# 批次 AB2 R1 审查回修1（P2-1）：zero 确认边沿就地发一次 RELEASE_CAMERA——
			# 兜住「若枚举为假阴性（设备在/枚举瞬时为空）且 python 在或 respawn 起来的
			# python 启动序首开摄像头」的最坏场景：0 态下 q3 兜底不发（其判据=双键皆关），
			# 本包=zero 态唯一显式释放意图。python 不在（真无设备常态）→ 9878 未 bind、
			# 包被内核丢弃，零副作用；python 在（假阴性）→ 收线程即时置闩释放（Z4-③），
			# 回 camera_closed(release) 置恢复锁存——后续 C8 重枚举到设备经
			# ensure_camera_open 显式开（ensure 入口清锁存），链不断。
			send_control("RELEASE_CAMERA")
			_force_gesture_off_when_zero()
		var cur: int = int(_camera_enum["current_camera"])
		# 批次 V-B2（V16，spec §6.4）：置灰可恢复——init#1（Python 切换/开启成功必发 _send_camera_list_init）
		# 把 current_camera 从 _camera_errors 移除（旧口径「只增不减」致失败置灰不可恢复，废止）；
		# 同时记录 last_good（最近一次成功设备，供 camera_error 自动回落目标）。
		while _camera_errors.has(cur):
			_camera_errors.erase(cur)
		_last_good_camera_id = cur
		camera_enum_received.emit(_camera_enum["cameras"], _camera_enum["current_camera"])
		# 批次 AB2（C8）：重枚举到设备边沿 → ensure_camera_open 自动开（记忆设备名优先→列表首项，
		# 与启动链路同逻辑；设置门/释放锁存/no-op 判据内建）。本边沿以 ensure 全语义**替代**
		# _ensure_preferred_camera_restore（后者无记忆名时零动作、有记忆名时与 ensure 同目标
		# 双发 SWITCH 闪烁）；ensure 内 res/fps 记忆追发语义同步继承。非边沿路径（AA W4-6
		# 既有三入口之一）保持 restore 不变。
		if not _camera_enum_zero and prev_zero:
			ensure_camera_open()
		else:
			_ensure_preferred_camera_restore()
		# 批次 AC（领域二，spec §4.2-3）：枚举未达期登记的显式开启意图 → init#1 兑现。
		# 一次性清零（防重入）；有设备才开（空枚举已由上方 zero 边沿/restore 处理）。
		if _open_on_next_enum:
			_open_on_next_enum = false
			if not _camera_enum_zero \
					and not (_camera_enum.get("cameras", []) as Array).is_empty():
				_last_enum_request_ms = -1000000   # 免节流吞本轮 SWITCH 后的即刻刷新
				ensure_camera_open()
	elif msg_type == "init" and d.has("resolutions"):
		_camera_matrix = {"resolutions": d.get("resolutions", []), "fps_options": d.get("fps_options", [])}
		camera_matrix_received.emit(_camera_matrix["resolutions"], _camera_matrix["fps_options"])
	elif msg_type == "camera_error":
		var eid: int = int(d.get("id", -1))
		_camera_errors.append(eid)
		# 批次 V-B2（V16，spec §6.4）：任何 camera_error 统一提示（centered 改道 TopStrip info 条）；
		# 错误 id==当前设备时自动回落 SWITCH_CAMERA:<last_good> 一次（5s 节流防风暴）。
		_notify_camera_error(eid, String(d.get("reason", "")))
		camera_error_received.emit(eid)
	# 其余（缺 cameras/resolutions 的 init 等）静默忽略

## 批次 AB2（B4，主会话拍板）：0 设备确认 → 强制手势交互状态置关并写档——根除「存档说
## 手势开着但没有设备可用」的矛盾态。经 SaveManager.update_settings 落盘（内建 save_game
## 即时写盘，settings_changed 联动 HUD 三真值门全隐）；父节点相对定位（_read_save_settings
## 同款防坑：勿用 /root 绝对路径）。已是关则零写盘（幂等）；gesture_camera_enabled 域不动
##（重接设备后 C8 自动开链靠它放行，且用户未表达过「关摄像头」意图）。
func _force_gesture_off_when_zero() -> void:
	if not bool(_read_save_settings().get("gesture_input", true)):
		return   # 已是关：零写盘（幂等边沿语义）
	var parent_node: Node = get_parent()
	if parent_node == null:
		return
	var save_node: Node = parent_node.get_node_or_null("SaveManager")
	if save_node == null or not save_node.has_method("update_settings"):
		return
	save_node.call("update_settings", {"gesture_input": false})

## 批次 Z（Z4-④，spec §4-4）：camera_error 统一提示（桥自动回落退役）。
## toast 经 Game（centered=true，V-C1 单点改道 TopStrip info 条；Game 未挂接时其内部降级
## push_warning）；文案恒为提示态双分支「摄像头启动失败」/「摄像头启动失败：<reason>」
##（reason 可空，坑 1/坑 2 防御不变；旧回落态专用文案随回落路径一并退役）。
## 退役理由：旧实现向 last_good（通常=切换前的旧设备）补发 SWITCH——正是「切换后旧设备
## 仍被请求」的闪烁根因之一（spec §4-4 13 条抢句柄来源之桥回落）；失败后由面板失败收口
## toast + 用户重试承担，零自动抢句柄。
func _notify_camera_error(eid: int, reason: String) -> void:
	var parent_node: Node = get_parent()
	if parent_node != null:
		var game_node: Node = parent_node.get_node_or_null("Game")
		if game_node != null and game_node.has_method("toast"):
			# 坑1/坑2 防御：reason 可空（旧载荷无 reason 键）→ 提示态文案双分支
			var text := "摄像头启动失败" if reason.is_empty() else "摄像头启动失败：%s" % reason
			game_node.call("toast", text, "warn", 3.0, true)

## 批次 U（U2，spec §6.1）：probe_result 解析——先写缓存后 emit（后挂订阅者 CameraMenu 首帧直读）。
func _handle_probe_result(d: Dictionary) -> void:
	var id: int = int(d.get("id", -1))
	var ok: bool = bool(d.get("ok", false))
	var resolutions: Array = []
	var fps_options: Array = []
	if ok:
		resolutions = d.get("resolutions", [])
		fps_options = d.get("fps_options", [])
	_probe_matrix_cache[id] = {"ok": ok, "resolutions": resolutions, "fps_options": fps_options}
	_probe_in_flight = false   # 批次 W（N9）：探测回包到达 → 互斥标志清除（可接受新探测）
	probe_result_received.emit(id, ok, resolutions, fps_options)

## 批次 U（U2，spec §6.3）：探测矩阵缓存 getter——未命中返回空 {}（P1-1 缓存模式沿用）。
func get_probe_matrix(id: int) -> Dictionary:
	var v: Variant = _probe_matrix_cache.get(id, null)
	if v == null:
		return {}
	return v

func get_camera_enum() -> Dictionary:
	return _camera_enum

func get_camera_matrix() -> Dictionary:
	return _camera_matrix

func get_camera_errors() -> Array:
	return _camera_errors

## 归一化：左右手 gesture 字符串统一小写（与 D 盘 GESTURE_NAMES 命名对齐的显示口径）；
## 其余字段（含 palm_size）原样透传。
func _normalize(d: Dictionary) -> void:
	for hand: String in ["left", "right"]:
		var h: Variant = d.get(hand)
		if typeof(h) == TYPE_DICTIONARY:
			var hd: Dictionary = h
			if hd.has("gesture"):
				hd["gesture"] = String(hd["gesture"]).to_lower()

## 9878 控制命令发送（Godot→Python）。本批唯一命令 SHUTDOWN（§3.3，预留一行一命令文本协议）。
## 批次 W（N9）：SWITCH_CAMERA 主流命令抢占在飞探测（清探测互斥标志——探测回包若迟到，
## camera_menu P2-5b 按 id 匹配行，错投无副作用）。
func send_control(cmd: String) -> void:
	if cmd.begins_with("SWITCH_CAMERA"):
		_probe_in_flight = false
	if _control_peer == null:
		_control_peer = PacketPeerUDP.new()
	_control_peer.set_dest_address("127.0.0.1", get_control_port())
	_control_peer.put_packet(cmd.to_utf8_buffer())

## 批次 W（N9，规格 §5）：PROBE_MATRIX 探测与主流互斥/串行——探测在飞期间丢弃新探测请求
##（下拉悬停重复请求由 camera_menu 1s 节流兜底，探测回包到达后恢复）；消费方 camera_menu
## :293 由直发 send_control 收口到本方法（单一漏斗）。批次 W 审查 P2-A：在飞标志补超时回收
##（UDP 丢包/无回包不至永久饿死；probe_timeout_ms 可注入，无头测试缩短等待）。
func send_probe_matrix(cam_id: int) -> void:
	var now_ms: int = Time.get_ticks_msec()
	if _probe_in_flight:
		if now_ms - _probe_sent_at_ms <= probe_timeout_ms:
			return
		_probe_in_flight = false   # 超时回收：上一次探测视作丢失，放行新探测
	_probe_in_flight = true
	_probe_sent_at_ms = now_ms
	send_control("PROBE_MATRIX:%d" % cam_id)

## 拉取模式（修复批 2026-09-18）：主动向 Python 服务端请求重发摄像头枚举 init#1。
## 背景：init#1 为一次性 UDP 消息，服务端启动 t≈0.1s 枚举完即发（t≈5s 打开成功补发一次），
## 游戏进程可能晚至 t≈17s 才绑定 9876（打包实弹实测）→ 两次 init 全部丢失、_camera_enum
## 缓存恒空、设置下拉「正在加载」永不到达。Python 侧 9878 新增 GET_CAMERAS 命令（收到即调
## _send_camera_list_init 重发）。幂等节流：同一秒内最多一次（Time.get_ticks_msec 计时）。
## 批次 AB2 R1 审查回修1（P2-1）：本入口=「用户触达重枚举」（设置面板摄像头钮 zero 态
## 点击 C6 / 开下拉 D10 / OPENING 超时重枚举）→ 顺带置「用户显式重枚举意图」锁存
## （zero 态 respawn 第二道门的放行凭据，见 _spawn 注）；桥内部事件驱动拉取（READY 边沿
## 自动拉取 / camera 事件后刷新 / zero 态看门狗试探）一律改走 _pull_camera_enum 不置意图。
func request_camera_enum() -> void:
	_reattach_intent = true
	_pull_camera_enum()

## 批次 AB2 R1 审查回修1（P2-1）：枚举拉取内部漏斗（=旧 request_camera_enum 本体，零语义
## 变化）——不置重枚举意图（自动路径不得自我解锁 zero respawn 门）。
func _pull_camera_enum() -> void:
	var now_ms: int = Time.get_ticks_msec()
	if now_ms - _last_enum_request_ms < ENUM_REQUEST_THROTTLE_MS:
		return
	_last_enum_request_ms = now_ms
	send_control("GET_CAMERAS")

## 批次 AB2 R1 审查回修1（P2-1）：zero 态看门狗重枚举试探——respawn 被意图门拒后改发
## GET_CAMERAS（零 spawn 零开镜）复确认假阴性（设备在、枚举瞬时为空）。走内部漏斗
## 不置意图（防试探自解锁放大 respawn 面；意图在 1s 节流窗内亦不串扰用户点击记账）。
func _request_reattach_probe() -> void:
	_pull_camera_enum()

## 就绪探测（spec §3.3/§14-10）：尝试 bind 9878（Python 绑定端，不是 9876）。
## bind 失败=端口被占=Python 已就绪；bind 成功=未就绪（立即关闭套接字）。
func _probe_python_ready() -> bool:
	var p := PacketPeerUDP.new()
	var err: Error = p.bind(get_control_port())
	if err == OK:
		p.close()
		return false
	return true

## 批次 AC（领域二，spec §4.2-4）：就绪探测**公开只读**入口——camera_menu 下拉刷新时判定
## 「Python 未运行/已挂起」以决定是否安全拉起（消费方不得直调下划线私有件；语义与
## _probe_python_ready 逐字同源，零副作用：仅 bind 试探后立即释放）。
func is_python_ready_probe() -> bool:
	return _probe_python_ready()

## 缺 gesture_runtime/ 处置决策（P3-5c 纯函数，无头直测）：editor 态=警告+降 UNAVAILABLE；
## 导出态=静默降 UNAVAILABLE（launcher 代拉/重导把关，不刷日志）。返回 {warn, degrade}。
static func _missing_runtime_plan(is_editor: bool) -> Dictionary:
	return {"warn": is_editor, "degrade": true}

## 拉起手势子进程（spec §8.3-2）：开发/编辑器模式 OS.create_process("py", ["-3", …])；
## 导出运行时 launcher.py 已先行拉起（§12.4），Godot 仅探测 → 跳过拉起返回 false；
## 无头（测试/CI）不真拉起（防测试拉起摄像头进程；main.gd 图标守卫同款判据）。
## 终审 P1-1：防重入门——已有活实例（_process_pid>=0 哨兵，未启动恒 -1/失败不改写）直接
## 复用返回 true，防编辑器模式每次打开设置面板/UNAVAILABLE 每 5s 重试重复 spawn MediaPipe
## 子进程（重复进程争抢 9876/9877 摄像头）；stop_gesture_process 置回 -1 后方可再拉起。
func start_gesture_process() -> bool:
	# 批次 AA 终审回修1（aarev P1-1）：设置门前置（单一漏斗门）——Q3 下一切直调路径（含
	# camera_menu 无缓存开下拉预热 :144 等旁路）零 spawn 零副作用（不清 _intentional_stop /
	# 不清 release 意图锁存 / 不武装握手 / 不改状态机）。显式开启路径（settings_panel 四象限
	# Q1/Q2 分支、select_camera_device）均先写档 gesture_camera_enabled=true 再进本入口，门放行
	# 语义不受影响；与 main.gd boot 门同口径（本门=boot 之后的第二道同源门，防新增旁路漏门）。
	if not _settings_allow_camera():
		return false
	# 批次 W（P1-2）：死后重拉退避门——判死后的 RESPAWN_MIN_INTERVAL_SEC 内拒绝再 spawn
	#（防 spawn 风暴；UNAVAILABLE 5s 重试周期本就长于退避，此门兜住设置面板等主动 ensure 路径）。
	if _now() < _respawn_block_until:
		return false
	_intentional_stop = false   # 批次 S13：任何主动拉起清陈旧主动关标志（防 Q3 无状态迁移遗留标志吞下次故障 toast）
	_camera_release_intent = false   # 批次 AA 回修1（W4-P2-1）：主动拉起=显式开启意图 → 清恢复锁存
	if _process_pid >= 0 and OS.is_process_running(_process_pid):
		# 批次 Z（Z4-⑤，spec §4-5）：防重入门早于握手发送点的丢记忆缺口修复——进程已在时
		# 同样重发 SET_PREFERRED_CAMERA 握手（旧行为直接 return true，打包态/编辑器态二次进入
		# 均可能丢开机记忆）。_begin 幂等（W4-1）：重武装窗与止发判据（camera_opened 匹配
		# 记忆设备/30s 窗上限）在 _tick 内建，重入零风暴。
		_begin_preferred_camera_handshake()
		return true  # 已有活实例直接复用（终审 P1-1 防重入门）
	if _process_pid >= 0:
		# 修复批 P3（2026-09-26）：pid 陈旧（python 已死）→ 清 pid 走重拉链路——旧码只查
		# `_process_pid >= 0` 即判活 return true，死进程被当活实例复用、永不重拉。
		# OS.is_process_running 判据与本文件 :355/:539/:930 三处既有用法同源（4.7 API 实证）。
		_process_pid = -1
	# 批次 W（P3-5c，规格 §7）：editor 判据前置——缺 gesture_runtime/ 的 push_error 仅 editor 态
	# 可达，导出态静默降 UNAVAILABLE（状态语义与旧版一致，每 5s 重试刷警告的日志噪音根除）；
	# 处置决策收敛 _missing_runtime_plan 纯函数（test_w_polish D5~D8 无头直测）。
	var runtime_script: String = ProjectSettings.globalize_path(_runtime_res_path)
	var plan := _missing_runtime_plan(OS.has_feature("editor"))
	if not FileAccess.file_exists(runtime_script):
		if not OS.has_feature("editor"):
			# 批次 Y（Y-A21）：pck 内无运行时为打包常态（export_presets.cfg exclude_filter 外置）
			# ——改走 exe 同级外置运行时判定（respawn 通路），不再误降 UNAVAILABLE。
			return _spawn_packaged()
		if bool(plan["warn"]):
			push_error("手势运行时未就位（gesture_runtime/main.py 缺失），手势不可用")
		if bool(plan["degrade"]):
			_set_state(LoadState.UNAVAILABLE)
		return false
	if not OS.has_feature("editor"):
		# 批次 Y（Y-A21）：res:// 命中（开发目录形态）亦走打包 respawn 判定（launcher 已先行
		# 拉起时 _packaged_spawn_plan 不可达此分支——导出包 res:// 不含 gesture_runtime）。
		return _spawn_packaged()
	if DisplayServer.get_name() == "headless":
		return false  # 无头测试：不真拉起（不置 UNAVAILABLE，避免污染状态断言）
	# 批次 Z（Z4-①，spec §4-1）：--owner-pid=游戏进程 PID——编辑器「停止」=TerminateProcess
	# 硬杀游戏 → _exit_tree 不执行 → 旧口径 python/py 双存活占摄像头；看门狗据宿主 PID
	# 消失即释放摄像头自退（编辑器态父=py.exe 恒存活，父判据不可用，owner 判据是主判据）。
	var args := ["-3", runtime_script, "--port", str(get_udp_port()),
		"--owner-pid", str(OS.get_process_id())]
	_process_pid = OS.create_process("py", args)
	if _process_pid < 0:
		push_error("手势子进程拉起失败（py 启动器缺失），手势不可用")
		_set_state(LoadState.UNAVAILABLE)
		return false
	_respawn_block_until = -1.0   # 批次 W（P1-2）：成功 spawn 清退避
	_begin_preferred_camera_handshake()   # 批次 Y（Y-A16）：spawn 即握手
	_set_state(LoadState.LOADING)   # 批次 S13：Q4 重开即刻进加载态（HUD 清陈旧纹理显「摄像头启动中…」占位）
	return true

func stop_gesture_process() -> void:
	# 批次 S13/S14：主动关（Q3）即刻进不可用态（不等 5s 无包超时），并置主动关标志供 main.gd
	# 消费抑制「摄像头暂未打开」toast（主动关≠故障，不提示）；标志由 consume_intentional_stop() 取走即清。
	_intentional_stop = true
	_camera_release_intent = true   # 批次 AA 回修1（W4-P2-1）：进程停止=用户关，恢复路径同锁存
	_set_state(LoadState.UNAVAILABLE)
	if _process_pid >= 0:
		send_control("SHUTDOWN")  # 优雅退出：Python 先释放摄像头再退进程（§3.3）
		# 批次 W（P1-2，规格 §5）：kill 前校验存活——Windows PID 复用残留风险窗口极小但存在，
		# 已死/不存在的 pid 只清 pid 不 kill，防误杀复用该 PID 的无关进程（语义留痕）。
		if OS.is_process_running(_process_pid):
			OS.kill(_process_pid)
		_process_pid = -1

## 批次 U（U4，spec §4-U4-②/§6.3）：Q3 专用——只释放摄像头，进程与三端口服务循环常驻。
## 置 _intentional_stop=true（批次 S13 语义，防 UNAVAILABLE 误报 toast）＋ _set_state(UNAVAILABLE)
##（stop 即刻不可用语义）；send_control("RELEASE_CAMERA")；不调 stop_gesture_process（不杀进程）。
func request_camera_release() -> void:
	_intentional_stop = true
	_camera_release_intent = true   # 批次 AA 回修1（W4-P2-1）：用户主动关 → 恢复路径锁存
	_set_state(LoadState.UNAVAILABLE)
	send_control("RELEASE_CAMERA")

## 批次 V-B2（V3/V17，spec §6.2）：读存档 settings——与 get_udp_port() 同款父节点相对定位
##（勿用 /root/SaveManager 绝对路径：4.7 无头 _initialize 期绝对路径 get_node 报错实证，P1-2 勘误；
## _data 空档/get_settings() 对空档取键运行时错误 → 判空兜底，取值一律 .get 防御）。
func _read_save_settings() -> Dictionary:
	var parent_node: Node = get_parent()
	if parent_node == null:
		return {}
	var save_node: Node = parent_node.get_node_or_null("SaveManager")
	if save_node == null:
		return {}
	var data: Variant = save_node.get("_data")
	if data == null or typeof(data) != TYPE_DICTIONARY or (data as Dictionary).is_empty():
		return {}
	var s: Variant = (data as Dictionary).get("settings", {})
	return s if typeof(s) == TYPE_DICTIONARY else {}

## 批次 AA 终审回修1（aarev P1-1）：**摄像头可用性单一真值判定**——读 SaveManager settings
## 的 `gesture_input ∨ gesture_camera_enabled`（OR 双键，与 main.gd boot 门 :178-179 逐字同口径、
## 同缺省 true：任一开=允许拉起/开镜类控制；双关=Q3，一切「自动开摄像头」路径统一短路）。
## 读不到设置（SaveManager 不在/_data 空档）→ 双缺省 true=允许——与 boot 门对空档的语义一致
## （防误伤默认档），不引入第三种口径。复用 _read_save_settings 的父节点相对定位
##（勿用 /root 绝对路径：4.7 无头 _initialize 期绝对路径 get_node 报错实证）。
func _settings_allow_camera() -> bool:
	var s: Dictionary = _read_save_settings()
	return bool(s.get("gesture_input", true)) or bool(s.get("gesture_camera_enabled", true))

## 批次 AA 终审回修1（aarev P1-1）：Q3 启动兜底——显式发一次 RELEASE_CAMERA（会话内恰一次，
## _q3_release_sent 哨兵；非 Q3（任一开）零发送零置位）。消费点：_ready（启动时序；
## SaveManager autoload 先于本桥，_data 已载）。打包形态 launcher 代拉 python 时 boot 门不
## start、自愈 spawn 已受门、restore 已受门，但常驻 python 启动序会「首开」摄像头——此兜底
## 在「python 已 bind 9878」前提下可令其就地释放（python 首开前 RELEASE 检查）。
## 已知残余窗（备案）：若本包先于 python bind 9878 发出（慢启动），UDP 包被内核丢弃且不再补发
##（恰一次语义）；根治需 python 侧/launcher 侧配合（后续批次，本波 python 零改动约束）。
func _q3_release_camera_once() -> void:
	if _q3_release_sent:
		return
	if _settings_allow_camera():
		return
	_q3_release_sent = true
	send_control("RELEASE_CAMERA")

## 批次 V-B2：设备记忆三键读取（SaveManager 三键由 V-D 路落地——磁盘实况：gesture_camera_device
## 系 String 型（""=未记忆），res String（""=设备默认），fps int（0=默认）；JSON null 载荷强转报错
## → 显式判空，坑 1）。
## 批次 W2（P2-3b，规格 §3）：设备记忆升级「显示名字符串匹配」——写入端（camera_menu）落设备
## 实名，消费端经纯函数缝 _resolve_target_camera_id 在枚举缓存中按名字匹配 id；旧档纯数字残留
## （"3"）按旧 CAP 索引语义解释一次（id 在枚举中才命中），不做存档迁移。原 int 解析器
## _memory_camera_device() 随之退役（全仓无他处引用，grep 实证）。
func _memory_camera_device_name() -> String:
	var v: Variant = _read_save_settings().get("gesture_camera_device", "")
	return String(v) if v != null else ""

## 批次 AD（spec §4.2.2-2，P2-3b 纯函数缝升级）：记忆名 → 枚举缓存中的目标设备 id；
## 未记忆/匹配不到返回 -1（调用方走既有回落链：枚举首项 → 由 Python 侧查名直启降级承担）。
## 匹配序：①记忆名 trim 后为空 → -1（未记忆）；②与枚举条目显示名**忽略大小写与首尾空格**
## 比对命中 → 返回该条目 id（条目形态同 camera_menu.normalize_cam_entry 契约：
## dict {id,name}/旧字符串条目名即值）。
## **纯数字串不再按旧 CAP 索引解释**（spec §4.2.2-2：禁止存储或依赖 CAP 索引数字，防热插拔
## 或重排序失效）——旧档纯数字残留视同未命中，走首项降级（AB2 档面几何不变）。
static func _resolve_target_camera_id(enum_cams: Array, memory_name: String) -> int:
	var name_s := String(memory_name).strip_edges().to_lower()
	if name_s.is_empty():
		return -1
	for cam: Variant in enum_cams:
		var entry_name := ""
		var entry_id := -1
		if typeof(cam) == TYPE_DICTIONARY:
			entry_name = String((cam as Dictionary).get("name", ""))
			entry_id = int((cam as Dictionary).get("id", -1))
		else:
			entry_name = str(cam)  # 旧字符串条目：名即值（normalize_cam_entry 同契约）
		if entry_id >= 0 and entry_name.strip_edges().to_lower() == name_s:
			return entry_id
	return -1

func _memory_camera_res() -> String:
	var v: Variant = _read_save_settings().get("gesture_camera_res", "")
	return String(v) if v != null else ""

func _memory_camera_fps() -> int:
	var v: Variant = _read_save_settings().get("gesture_camera_fps", 0)
	return int(v) if v != null else 0

## 批次 AD-5（F-2，需求 §4.2）：`START_CAMERA_BY_NAME` **三路共享节流记账**唯一出包口。
## 调用源（source 字符串）："handshake"=握 tick / "restore"=开机恢复 / "ensure"=显式 ensure。
## 判据（跨源同目标才抑制——同源自重复交给各路既有节流，存量条数断言零弱化）：
##   - `force=true`（显式 ensure）：**永不抑制**，但照常记账（它发出后自动两路在其 gap 内被抑制）；
##   - 否则：与上一笔**同命令串**、**不同来源**、且间隔 < start_send_shared_gap_ms → 抑制，
##     返回 false（零出包）；命中则记账并出包，返回 true。
## 幂等兜底不变：Python 侧 `_start_camera_by_name` 已有「已开同设备零 release/reopen」+
## AD-5 新增「开镜在飞同目标重复指令忽略」，本账本只是把重复下发挡在桥侧（少一次往返）。
func _send_start_camera_by_name(name: String, source: String, force: bool = false) -> bool:
	var cmd := "START_CAMERA_BY_NAME:%s" % name
	var now_ms := int(Time.get_ticks_msec())
	if not force and cmd == _start_send_last_cmd and source != _start_send_last_src \
			and now_ms - _start_send_last_ms < start_send_shared_gap_ms:
		print("[AD-5] 启动指令共享节流：源=%s 命中上一源(%s)同目标在 %dms 内 → 抑制：%s"
			% [source, _start_send_last_src, start_send_shared_gap_ms, cmd])
		return false
	_start_send_last_cmd = cmd
	_start_send_last_src = source
	_start_send_last_ms = now_ms
	send_control(cmd)
	return true

## 批次 Y（Y-A16，spec §3.3）→ 批次 AA（W4-1）→ 批次 AC（领域二）→ 批次 AD（spec §4.2.2-3）：
## 设备启动指令**武装**（不直接发送）。下发统一收口 _tick_preferred_camera_handshake
##（bind 探测门控 + 1s 间隔 + 30s 窗上限）。
## 批次 AC（2026-09-27）：**无记忆名亦武装**——旧实现 `mem_name.is_empty()` 直接 return
## 不武装，导致首次启动（存档无 gesture_camera_device）时 Python 侧干等满握手窗才开流。
## 批次 AD（spec §4.2.2-2/3）：命令改为 `START_CAMERA_BY_NAME:<存档设备名字符串>`（禁止依赖
## 或存储 CAP 索引）；无记忆名 → `_preferred_device_name = ""` 照常武装，_tick 到点发
## **空载荷** `START_CAMERA_BY_NAME:`，Python 收到即按「未命中/空名 → 列表首项」降级启动；
## 列表为空则 Python 保持未启动并回传 0 摄像头状态（spec §8 风险二缓解措施）。
func _begin_preferred_camera_handshake() -> void:
	_preferred_handshake_armed = false
	_preferred_handshake_deadline_ms = -1
	_preferred_next_at_ms = -1
	_preferred_device_name = _memory_camera_device_name()
	_preferred_handshake_armed = true
	var now_ms := int(Time.get_ticks_msec())
	_preferred_handshake_deadline_ms = now_ms + int(preferred_handshake_window_sec * 1000.0)
	_preferred_next_at_ms = now_ms   # 首发在下一帧 _tick（过 bind 门后）

## W4-1 握手满足判据：流已开且开启设备==记忆设备（记忆名经枚举解析；枚举未达=不可验证）。
## 批次 AC/AD：空记忆名（空载荷启动指令形态）无可验证目标——改判「流一旦真实开启即
## 握手完成」（Python 已按「未命中降级首项」选好设备），其余情形由 30s 窗上限自然收束。
func _preferred_handshake_satisfied() -> bool:
	if _preferred_device_name.is_empty():
		return camera_stream_open
	var cams: Array = (get_camera_enum() as Dictionary).get("cameras", [])
	var mem_id := _resolve_target_camera_id(cams, _preferred_device_name)
	return mem_id >= 0 and camera_stream_device_id == mem_id

## 批次 Y（Y-A16）→ 批次 AA（W4-1）→ 批次 AD：启动指令重发调度（_process 每帧调用）。
## 门控序：①用户主动关闭锁存（_camera_release_intent）→ 止发（自动补发不得复活被关掉的
## 摄像头；用户显式再开经 ensure_camera_open 入口清锁存后自然恢复可达——批次 AD 把 AC 由
## Python 侧承担的 release 拦截上提到桥侧，因 Python 侧命令现为「显式开启」语义不得被拦）；
## ②止发判据（camera_opened 匹配记忆设备 / 30s 重发上限到）→ 收束；
## ③间隔到点才探 bind（_probe_python_ready，≤1 次/间隔防 socket 风暴）；
## ④bind 未确认（probe=false）→ 不发（bind 前的包必被内核丢弃，重排下个间隔再探）；
## ⑤bind 确认 → 发 START_CAMERA_BY_NAME:<存档设备名>（可空名，语义=降级首项）。
func _tick_preferred_camera_handshake() -> void:
	if not _preferred_handshake_armed:
		return
	if _camera_release_intent:
		return   # 用户主动关闭：自动补发路径一律短路（与 _ensure_preferred_camera_restore 同锁存）
	var now_ms := int(Time.get_ticks_msec())
	if _preferred_handshake_satisfied() or now_ms > _preferred_handshake_deadline_ms:
		_preferred_handshake_armed = false   # 止发：已命中记忆设备 / 30s 上限到
		return
	if now_ms < _preferred_next_at_ms:
		return
	if not _probe_python_ready():
		# W4-1：python 未 bind（9878 空闲）→ 零下发；下个间隔再探
		_preferred_next_at_ms = now_ms + preferred_handshake_interval_ms
		return
	_send_start_camera_by_name(_preferred_device_name, "handshake")
	_preferred_next_at_ms = now_ms + preferred_handshake_interval_ms

## 批次 AA（W4-6，spec §7.3）→ 批次 AD（spec §4.2.2-3）：开机自动恢复（主恢复路径）——
## 记忆设备名解析命中且非当前开启设备 → 补发 `START_CAMERA_BY_NAME:<记忆名>`（3s 节流防刷）。
## 三入口调用：READY 边沿（首包）/ init#1（枚举到达）/ camera_opened≠记忆（python 开错兜底）。
## 「开设置面板 ensure」保留为幂等再确认（settings_panel._apply_camera_quadrant 不变）。
## 批次 AD-5（F-2，需求 §4.2，替代 AB2 R1 P3-2「备案不改码」）：本函数与
## _tick_preferred_camera_handshake / ensure_camera_open 现共用**同一本节流账**
## （`_send_start_camera_by_name`：跨源同目标 gap 内只发一条）——根治「同帧/同秒多路
## 各发一条 START_CAMERA_BY_NAME → Python 在飞窗口反复收重复指令」。三条保留约束：
## ① **同源自重复不叠加**：restore 的 3s 节流（`_preferred_restore_last_ms`）与 tick 的
##   1s 间隔（`_preferred_next_at_ms`）各自照旧，账本只管**跨源**去重 → 存量条数断言零弱化；
## ② **显式 ensure 不被抑制**（force=true）：批次 Y（Y-A25/㉕）红测根除的「吞显式开启」
##   语义原样保持——用户点开必须照发；C8a（zero 边沿自动开）等合法同目标快速二连发亦不受影响；
##   ensure 发出后照常记账，其后自动两路在其 gap 内即被抑制（这正是「同帧多路各发一条」的收敛点）；
## ③ release 意图锁存 / 设置门 / 3s 节流的**判定序与判据一律不变**（本批只改出包口，
##   门与账的先后关系零变更）。既有 Python 侧护栏（同设备零 release/reopen、AD-5 在飞
##   同目标幂等）作为第二道防线保留。
func _ensure_preferred_camera_restore() -> void:
	# 批次 AA 终审回修1（aarev P1-1）：设置门前置（先于 release 意图锁存门）——Q3（双关）下
	# 三入口（READY 边沿/init#1/camera_opened≠记忆）一律零下发：终审实证 Q3 重启后
	# READY 边沿/init#1 仍按记忆设备补发启动指令（记忆设备≠枚举 current 时），跨重启
	# 复活摄像头。release 锁存只管「同会话主动关」；本门管「档面双关」跨会话语义，二者正交。
	if not _settings_allow_camera():
		return
	# 批次 AA 回修1（W4-P2-1）：release 意图锁存门——用户主动关闭后本函数一切入口短路
	#（含 init#1/READY 边沿等后续事件驱动的再入，节流窗外的延迟补发一并根除）。
	if _camera_release_intent:
		return
	var mem_name := _memory_camera_device_name()
	if mem_name.strip_edges().is_empty():
		return
	var enum_d: Dictionary = get_camera_enum()
	var cams: Array = enum_d.get("cameras", [])
	if cams.is_empty():
		return   # 枚举未达（init#1 入口再试）
	var mem_id := _resolve_target_camera_id(cams, mem_name)
	if mem_id < 0:
		return   # 记忆名不在枚举（回落链归 ensure_camera_open）
	# 已满足：记忆设备就是当前开启设备 → 零恢复
	if camera_stream_open and camera_stream_device_id == mem_id:
		return
	var cur := int(enum_d.get("current_camera", -1))
	if not camera_stream_open and mem_id == cur:
		return   # 未开流但枚举即记忆设备（python 首开目标正确，交给其自身开启链）
	var now_ms := int(Time.get_ticks_msec())
	if now_ms - _preferred_restore_last_ms < PREFERRED_RESTORE_THROTTLE_MS:
		return
	_preferred_restore_last_ms = now_ms
	last_switch_camera_id = mem_id   # N5 OPENING 回落目标记账同源
	# 批次 AD（spec §4.2.2-3）：恢复同样按**设备名字符串**下发（禁止依赖 CAP 索引）。
	_send_start_camera_by_name(mem_name, "restore")
	print("[W4-6] 开机恢复：补发 START_CAMERA_BY_NAME:%s" % mem_name)

## 批次 V-B2：枚举条目 id 提取（camera_menu.normalize_cam_entry 同源契约——新契约 dict 条目/
## 向下兼容旧字符串条目；id 不可解析回 -1）。
static func _cam_entry_id(cam: Variant) -> int:
	if typeof(cam) == TYPE_DICTIONARY:
		return int(cam.get("id", -1))
	var s := str(cam)
	return int(s) if s.is_valid_int() else -1

## 批次 AD（spec §4.2.2-4，静态纯函数）：枚举列表 → **首项物理设备 id**（=旧「列表第一个」
## 降级目标，与 Python `pick_camera_by_name` 的未命中降级同源）。首项 id 不可解析向后顺延
## 取下一个可解析条目；全不可解析/空列表 → -1（调用方零下发，不盲发索引）。
static func _first_camera_entry_id(enum_cams: Array) -> int:
	for cam: Variant in enum_cams:
		var cid := _cam_entry_id(cam)
		if cid >= 0:
			return cid
	return -1

## 批次 AD（spec §4.2.1）：手机/虚拟摄像头黑名单关键词元组与 `is_virtual_or_phone_camera_name`
## 判定函数、以及 `_pick_non_phone_camera_id` 自动缺省选择**彻底退役**——不再依靠名称字符串
## 猜测设备类型，也不再有任何「本桥自选设备」通路：设备启停一律由存档记忆名（
## `gesture_camera_device`）经 `START_CAMERA_BY_NAME:<名>` 下发，Python 侧查名直启
## （未命中/空名 → 列表首项；列表空 → 0 摄像头状态）。

## 批次 U（U4，spec §4-U4-③/§6.3）：开摄像头幂等封装——start_gesture_process()＋启动指令。
## 短路判据（复核终版，修双审 P2-15 判据错置）：start 返回 false 且 _probe_python_ready()==false
##（9878 bind 成功=无服务驻留）才 return false 不发 SWITCH_CAMERA；false＋probe ready（=有常驻服务，
## 打包形态常态——导出运行时 start 恒 false，:284-285 launcher 代拉起致 _process_pid 恒 −1）照发。
## 批次 V-B2（V3，spec §6.2）：last_id 选择序——①记忆设备存在于枚举缓存 → 用之；②否则枚举
## 缓存第一项（V3 拍板「无记忆→首设备默认选中」，旧口径 current_camera 保留废止）；③缓存空
##（或首项 id 不可解析）回落 0（现状兜底）。
## 批次 W2（P2-3b/N10，规格 §3）：①升级为「设备显示名匹配」——记忆值=设备实名（旧档纯数字
## 残留按旧 CAP 索引语义解释一次），经纯函数缝 _resolve_target_camera_id 解析；返回 -1（未记忆/
## 名字不在枚举）走②③既有回落链。
## 幂等：设备已开时 SWITCH_CAMERA 到同 id 由 Python _switch_camera release/reopen 兜底（spec §4-U4-③）。
## 批次 V-B2（V17，spec §6.2）：分辨率/帧率随开启恢复——SWITCH 发出后，记忆 res 非空/fps 非 0 且
## 设备匹配（记忆设备未记录视为通配；记忆设备≠本次开启设备则不追发，防跨设备串值）时追发
## SET_RESOLUTION/SET_FPS（Python 控制命令串行处理；对不支持值已有重开回退链，行为安全）。
## W2 等价迁移：匹配判据由「记忆 int==开启 id」改为「未记忆（名空）通配 ∨ 解析命中==开启 id」
## ——已记忆但未解析命中（记了名字却不在当前枚举）不追发，V17 防串值语义保持
##（test_v_camera_menu 段 G / test_w_save_domain 段 B 双向锁定）。
func ensure_camera_open() -> bool:
	# 批次 AA 终审回修1（aarev P1-1）：设置门前置（先于清锁存）——Q3 下显式 ensure 视为漏门
	# 请求：直接 false 早退，不发 SWITCH/SET_RESOLUTION/SET_FPS、不清 release 意图锁存、不触碰
	# start。显式开启路径（四象限/select_camera_device）先写档 camera_enabled=true 再进本入口，
	# 门放行语义不变（OR 双键任一开即过）。
	if not _settings_allow_camera():
		return false
	# 批次 AB2（D11）：0 设备确认态一切开镜类命令短路——零 SWITCH_CAMERA/零分辨率帧率追发/
	# 零开镜尝试（旧「缓存空回落 0」会对无设备 python 发 SWITCH_CAMERA:0 的漏门根除）。
	# 重枚举到设备（_camera_enum_zero 边沿解除）后自然放行；未知态（缓存空未确认）不在本门内，
	# 既有回落 0 语义保持（test_u_bridge_protocol 段5/test_t_camera_device 锚定）。
	# 短路先于锁存清理/入口清标志（零副作用，防 0 态点击意外解锁 release 意图）。
	if _camera_enum_zero:
		var cams_z_v: Variant = (get_camera_enum() as Dictionary).get("cameras", [])
		if cams_z_v is Array and (cams_z_v as Array).is_empty():
			return false
	# 批次 AA 回修1（W4-P2-1）：显式再开=用户开启意图 → 清 release 恢复锁存（此后 restore
	# 路径恢复可达；与 start_gesture_process 内清除双保险——_simulate_start_ok 短路测试缝
	# 不经 start 时亦清除）。
	_camera_release_intent = false
	# 批次 Y（Y-A18）：入口先快照主动关标志——下方 start_gesture_process 入口会无条件清标志
	#（Q4 重启路径既有语义），no-op 门改用「调用前」快照判定，主动关语义不再被入口清标志破坏
	#（RELEASE 后 ensure 误判「未主动关」吞显式开启的根因）。
	var released_before := _intentional_stop
	var started: bool = _simulate_start_ok or start_gesture_process()
	if not started and not _probe_python_ready():
		return false
	var cams: Array = (get_camera_enum() as Dictionary).get("cameras", [])
	# 批次 AC（领域二，spec §4.2-3/D2）：**枚举未达（cams 空）不再盲发 SWITCH_CAMERA:0**——
	# 旧回落链「③缓存空回落 0」在荣耀手机于 CAP 0 的机器上=盲开手机摄像头（手机弹窗 +
	# 指示灯闪烁根因）。新口径：未达 → 重新武装握手（_begin_preferred_camera_handshake，
	# 无记忆名亦发空载荷）＋拉取枚举（_pull_camera_enum/GET_CAMERAS），待 init#1 到达由
	# _handle_meta 自动按记忆名/非手机首项开启（C8 边沿链）；本轮零 SWITCH 零开镜。
	if cams.is_empty():
		_begin_preferred_camera_handshake()
		_pull_camera_enum()
		# 本轮显式开启意图登记：init#1 到达由 _handle_meta 兑现（首选非手机设备），
		# 不因枚举迟到而静默丢失（旧实现盲发 SWITCH_CAMERA:0 已废止）。
		_open_on_next_enum = true
		return true
	# 批次 AD（spec §4.2.2-2/3）：**依设备名称字符串启动**（禁止依赖/存储 CAP 索引）——
	# 本桥不再自行按黑名单/关键词挑设备，只把存档记忆名（可空）原样下发
	# `START_CAMERA_BY_NAME:<名>`；Python 侧查名直启（命中→该设备；未命中/空名→列表首项）。
	var mem_name := _memory_camera_device_name()
	var mem_id := _resolve_target_camera_id(cams, mem_name)
	var target_id := mem_id if mem_id >= 0 else _first_camera_entry_id(cams)
	# 批次 Y（Y-A18）：no-op 门以「摄像头流开启真值」判定已开（camera_stream_open）——
	# 流已开 ∧ 未主动关（入口快照）∧ 链路在（READY/LOADING）∧ 目标==当前设备 → no-op 直亮；
	# 流未开（假死 READY/RELEASE 后/设备丢失）→ 照发启动指令，陈旧 current_camera 比较不再卡死。
	# 批次 Y（Y-A25/㉕）：旧「LOADING+枚举空 → no-op」分支废止——该分支吞显式开启
	#（python 启动中用户点开被静默吞掉），启动指令本就幂等（python 同设备零 release/reopen）。
	var cur_cam: int = int((get_camera_enum() as Dictionary).get("current_camera", -1))
	if not released_before and camera_stream_open \
			and (_state == LoadState.READY or _state == LoadState.LOADING) \
			and target_id >= 0 and target_id == cur_cam:
		return true
	last_switch_camera_id = target_id   # 批次 W（N5）：OPENING 态回落目标判定消费
	# 批次 AD-5（F-2）：显式 ensure 走 force=true——用户点开必须照发（不被共享账本抑制），
	# 但照常记账，其后自动两路在其 gap 内即被抑制（同帧多路不再各发一条）。
	_send_start_camera_by_name(mem_name, "ensure", true)
	# 分辨率/帧率随开启恢复（V17 语义保持）：仅在记忆名解析命中（=确定目标设备）时追发，
	# 无记忆/失配时目标由 Python 设定、其 camera_opened 事件到达后由 _handle_camera_event 追发。
	if mem_id >= 0 and mem_id == target_id:
		var mem_res := _memory_camera_res()
		if mem_res != "":
			send_control("SET_RESOLUTION:%d:%s" % [target_id, mem_res])
		var mem_fps := _memory_camera_fps()
		if mem_fps > 0:
			send_control("SET_FPS:%d:%d" % [target_id, mem_fps])
	return true

## 批次 S13/S14：取走主动关标志。true=最近一次 UNAVAILABLE 系主动关（main.gd 据此跳过 toast 与
## pending 标记）；调用即清零（一次性语义，防陈旧标志吞后续真实故障提示）。
func consume_intentional_stop() -> bool:
	var v := _intentional_stop
	_intentional_stop = false
	return v

## 批次 W2 支撑项（规格 §3）：主动关只读态查询——置位期间恒真、不消费标志本身（consume 的
## 一次性语义不变）；start_gesture_process 入口清标志即自动转 false。供 W3 N3「已关闭」占位
## 文案与 W4 N5 按钮态判定消费（本波仅落 API 最小面）。
func is_camera_intentionally_released() -> bool:
	return _intentional_stop

func _exit_tree() -> void:
	stop_gesture_process()
	# 批次 Z（Z4-①-②）：孤儿清理线程兜底收尸（Godot Thread 析构前必须 wait；探测在飞最坏
	# ~2s——仅「启动 2s 内即退出」的极短会话命中，编辑器硬杀路径本就不走 _exit_tree）。
	if _orphan_cleanup_thread != null:
		_orphan_cleanup_thread.wait_to_finish()
		_orphan_cleanup_thread = null
	if _udp != null:
		_udp.close()
	if _jpeg_udp != null:
		_jpeg_udp.close()
