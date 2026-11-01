extends "res://tests/test_base.gd"
## 批次 W W1（2026-09-20 规格 §2）发布链路——TDD 红测先行（test_w_publish）。
## 覆盖口径（本测试零触碰 user://，纯文本断言 + editor 构建行为探针）：
##   ①P2-1 MCP 7777 editor 守卫（规格 §2/W0 §一 P2-1，红线 §0-5）：_ready 含
##     OS.has_feature("editor") 守卫且先于 _start_server；插件本体零删除
##    （_start_server/DEFAULT_PORT=7777/_process 逻辑在位）；editor 构建实例化照常起服务
##     （开发态 GoPeak 链路回归锚——无头 console exe 即 editor build，探针断言）。
##     非 editor 路径的真实关闭由 W7 打包版 netstat 验收（规格 §10 P2-1 行）。
##   ②P0-5 iss :44 路径补段：Source 补「千年一榫_Windows_EXE」段（对齐 :37 写法）；
##     旧断链路径段清零；:51 快捷方式 python.exe 落位核对（实际 DestDir={app}\gesture_runtime\python）。
##   ③B-17 exclude_filter：追加 tools_v_walkthrough/*（wt2.gd bind 9878 注入 9876）；
##     既有 tools/*、tests/*、tools_p_shot/*、gesture_runtime/* 排除保留（P0-1~4 真源化依据）。
##   ④P2-2 launcher 日志落盘（文本锚）：_open_log_stream 回落链（运行目录→%LOCALAPPDATA%
##     /Godot/千年一榫_logs/→%TEMP%→静默）+ stdout/stderr 追加重定向 + CREATE_NO_WINDOW；
##     bridge 关键错误 push_error 同步（camera_error/进程死亡/端口失败三类）。
##   ⑤P0-1~4 真源化留痕（规格 §2：本波零代码改动，测试锁「G/gesture_runtime/=唯一真源」证据）：
##     源码版含 RELEASE_CAMERA/PROBE_MATRIX/三参 SET_RESOLUTION 解析（split(":") 多段）/
##     控制口接管重试/flag 通道标记；游戏端发送侧（bridge RELEASE_CAMERA、camera_menu
##     PROBE_MATRIX）在位。W7 重导 EXE 后按规格 §2 清单①~⑦逐项实测闭环。

const MCP_SCRIPT := "res://addons/godot_mcp_runtime/mcp_runtime_autoload.gd"
const ISS_PATH := "res://tools/千年一榫_setup.iss"
const EXPORT_PRESETS := "res://export_presets.cfg"
const LAUNCHER_PY := "res://gesture_runtime/launcher.py"
const SERVER_PY := "res://gesture_runtime/hand_tracking_server.py"
const BRIDGE_GD := "res://autoload/gesture_bridge.gd"
const CAMERA_MENU_GD := "res://scenes/settings/camera_menu.gd"

func _read_res(p: String) -> String:
	return FileAccess.get_file_as_string(ProjectSettings.globalize_path(p))

func _ready_block(src: String) -> String:
	## 抽取 _ready 函数体（至下一个顶层 func 为止）——守卫位置结构断言用
	var start := src.find("func _ready")
	if start < 0:
		return ""
	var next := src.find("\nfunc ", start + 1)
	return src.substr(start, (next if next > 0 else src.length()) - start)

func _initialize() -> void:
	print("== test_w_publish ==")
	await process_frame
	# 批次 AF 终审备案族（语言钉扎先例=6411fae o_catalog_shop）：autoload _ready 推迟至树激活，
	# 须等一帧后钉 zh——用户真实存档现 language=en，不钉则文案断言呈 en 态假红。
	# 编译窗安全：经节点查找而非全局名（--script 模式 autoload 全局名编译期未注册）。
	var i18n_node: Variant = get_root().get_node_or_null("I18n")
	if i18n_node != null:
		i18n_node.call("set_language", "zh")

	# ===== 一、P2-1：MCP 7777 editor 守卫（文本结构 + editor 构建行为） =====
	var mcp_src := _read_res(MCP_SCRIPT)
	var ready_src := _ready_block(mcp_src)
	check(not ready_src.is_empty(), "P2-1：mcp_runtime_autoload.gd _ready 函数体可抽取")
	var guard_at := ready_src.find("OS.has_feature(\"editor\")")
	var start_at := ready_src.find("_start_server()")
	check(guard_at >= 0, "P2-1：_ready 含 OS.has_feature(\"editor\") 守卫（红：守卫未实现时为负）")
	check(start_at >= 0, "P2-1：插件本体零删除——_ready 仍调用 _start_server（红线 §0-5）")
	if guard_at >= 0 and start_at >= 0:
		check(guard_at < start_at, "P2-1：守卫先于 _start_server（非 editor 构建不启动 7777）")
		var ret_at := ready_src.find("return", guard_at)
		check(ret_at >= 0 and ret_at < start_at, "P2-1：非 editor 分支直接 return（早退不落 listen）")
	check(mcp_src.contains("const DEFAULT_PORT = 7777"), "P2-1：插件零改动——DEFAULT_PORT=7777 保留（开发态 GoPeak 依赖）")
	check(mcp_src.contains("func _start_server"), "P2-1：插件零改动——_start_server 实现在位")
	check(mcp_src.contains("func _process"), "P2-1：插件零改动——_process 消息泵在位")
	# editor 构建行为探针：无头 console exe 即 editor build → 守卫放行 → _start_server 被调用
	#（_server 由 null 变实例）。真实 7777 监听可能被本进程真实 autoload 占用，故只断「守卫放行」
	# 证据（_server 非空），不断 is_listening；非 editor 关闭路径由 W7 打包版 netstat 验收。
	check(OS.has_feature("editor"), "P2-1 探针：无头 console exe 为 editor build（守卫走启动分支的前提）")
	var mcp: Node = (load(MCP_SCRIPT) as GDScript).new()
	mcp.name = "MCPRuntime_W_Probe"
	get_root().add_child(mcp)
	# 探针实证（规律⑥）：--script 模式 _initialize 阶段 add_child 不触发 _ready——
	# 显式驱动一次 _ready() 走守卫分支（free 先于树激活，引擎不会二次触发）。
	mcp.call("_ready")
	check(mcp.get("_server") != null, "P2-1 行为：editor 构建实例化后 _server 已创建（开发态照常启动，红线回归锚）")
	mcp.free()

	# ===== 二、P0-5：iss :44 路径补段 + :51 快捷方式落位核对 =====
	var iss := _read_res(ISS_PATH)
	check(iss.contains("..\\..\\..\\构建产物\\千年一榫_Windows_EXE\\gesture_runtime\\python\\*"),
		"P0-5：iss Source 补「千年一榫_Windows_EXE」段（对齐 :37 写法）")
	check(not iss.contains("..\\..\\..\\构建产物\\gesture_runtime\\"),
		"P0-5：旧断链路径段（缺 EXE 目录段）清零")
	check(iss.contains("..\\..\\..\\构建产物\\千年一榫_Windows_EXE\\{#MyAppExeName}"),
		"P0-5：游戏本体 Source 行（:37 正确写法）不受扰")
	# AF 同步批（2026-11-01）：09-29 打包小修 3e278ff 桌面「手势版」快捷方式退役（该入口实测
	# 报错、bug 暂不修；普通入口已可正常调用摄像头手势）——:51 快捷方式 Filename=python.exe 与
	# Parameters=launcher.py 随入口一并删除；launcher.py 本体经 [Files] 通配随包保留（仅入口退役）。
	check(not iss.contains("{app}\\gesture_runtime\\python\\python.exe"),
		"P0-5：手势版快捷方式 Filename=python.exe 已随入口退役删除（09-29 打包小修；反向锁）")
	check(not iss.contains("{app}\\gesture_runtime\\launcher.py"),
		"P0-5：手势版快捷方式 Parameters=launcher.py 已随入口退役删除（launcher.py 随包保留、仅入口退役；反向锁）")
	check(iss.contains("..\\gesture_runtime\\*.py"),
		"P0-5（AF 补锚）：launcher.py 经 [Files] 通配随包保留（仅入口退役，文件不删）")

	# ===== 三、B-17：exclude_filter 补排 tools_v_walkthrough/* =====
	var presets := _read_res(EXPORT_PRESETS)
	check(presets.contains("tools_v_walkthrough/*"),
		"B-17：exclude_filter 追加 tools_v_walkthrough/*（wt2.gd 会 bind 9878 注入 9876）")
	check(presets.contains("gesture_runtime/*"),
		"B-17：既有排除保留——gesture_runtime/*（P0-1~4 真源化依据：手势源码不入 PCK）")
	for keep: String in ["tools/*", "tests/*", "tools_p_shot/*"]:
		check(presets.contains(keep), "B-17：既有排除保留——%s" % keep)

	# ===== 四、P2-2：launcher 日志落盘（源码文本锚）+ bridge push_error 同步 =====
	var launcher_src := _read_res(LAUNCHER_PY)
	check(launcher_src.contains("_open_log_stream"), "P2-2：日志句柄回落链函数 _open_log_stream 存在")
	check(launcher_src.contains("gesture_runtime.log"), "P2-2：回落链级 1=运行目录 gesture_runtime.log")
	check(launcher_src.contains("LOCALAPPDATA"), "P2-2：回落链级 2=%LOCALAPPDATA%/Godot/千年一榫_logs/")
	check(launcher_src.contains("千年一榫_logs"), "P2-2：回落链级 2 子目录名（千年一榫_logs）")
	check(launcher_src.contains("TEMP"), "P2-2：回落链级 3=%TEMP%")
	check(launcher_src.contains("CREATE_NO_WINDOW"), "P2-2：server Popen 带 win32 CREATE_NO_WINDOW creationflags")
	check(launcher_src.contains("subprocess.STDOUT"), "P2-2：server stderr 合流 stdout 落盘")
	var bridge_src := _read_res(BRIDGE_GD)
	# P2-3 回修（W1 独立审查）：弱断言加固——五个 push_error 站点逐条子串锚 + 计数 ≥5，
	# 并锁 :143 手势加载超时维持 push_warning（规格三类口径：camera_error/进程死亡/端口失败，
	# 超时不属三类，防回归）。
	for site: String in ["UDP 绑定失败", "JPEG 端口绑定失败", "手势链路中断", "手势运行时未就位", "手势子进程拉起失败"]:
		check(bridge_src.contains("push_error(\"%s" % site), "P2-2：bridge push_error 站点锚——%s" % site)
	check(bridge_src.count("push_error") >= 5,
		"P2-2：bridge push_error 站点计数 ≥5（现 %d）" % bridge_src.count("push_error"))
	check(bridge_src.contains("push_warning(\"手势加载超时"),
		"P2-2：加载超时（:143）维持 push_warning（非规格三类）")
	check(not bridge_src.contains("push_error(\"手势加载超时"),
		"P2-2：加载超时未被误升 push_error（防回归）")

	# ===== 五、P0-1~4：真源化留痕（规格 §2：本波零代码改动；W7 重导 EXE 闭环待办） =====
	var server_src := _read_res(SERVER_PY)
	check(server_src.contains("RELEASE_CAMERA"), "P0-1 留痕：源码版含 RELEASE_CAMERA（关摄像头→停帧+按钮灭）")
	check(server_src.contains("PROBE_MATRIX"), "P0-1 留痕：源码版含 PROBE_MATRIX（悬停探测）")
	check(server_src.contains("parts = cmd.split(\":\")"),
		"P0-1 留痕：源码版 SET_RESOLUTION 多段解析（P 版 split(\":\",1)[1] 三参异常已不存在）")
	check(server_src.contains("CONTROL_BIND_MAX_RETRIES"), "P0-2 留痕：源码版控制口接管重试（bind 失败→SHUTDOWN→重试×3）")
	check(server_src.contains("CONTROL_TAKEOVER_CMD"), "P0-2 留痕：源码版接管序命令通道在位")
	check(server_src.contains("SWITCH_FAIL_COOLDOWN_SEC"), "P0-4 留痕：源码版切换失败冷却/防自动重连在位")
	check(launcher_src.contains("dwm_round.flag"), "P0-3 留痕：源码版 launcher flag 通道（U9-4 口径）在位")
	check(launcher_src.contains("apply_window_region"), "P0-3 留痕：源码版 launcher SetWindowRgn region 兜底在位")
	check(bridge_src.contains("RELEASE_CAMERA"), "P0-1 留痕：游戏端发送侧 bridge RELEASE_CAMERA 在位")
	check(_read_res(CAMERA_MENU_GD).contains("PROBE_MATRIX"), "P0-1 留痕：游戏端发送侧 camera_menu PROBE_MATRIX 在位")
	check(presets.contains("gesture_runtime/*"),
		"P0-1 留痕：export_presets 排除 gesture_runtime/*（源码目录不入 PCK，.gdignore 同向）")

	finish()
