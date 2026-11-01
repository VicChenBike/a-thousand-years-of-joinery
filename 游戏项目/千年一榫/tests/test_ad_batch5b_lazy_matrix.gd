extends "res://tests/test_base.gd"
## 批次 AD-5b——按需惰性矩阵探测契约（GDScript 侧回归锚；零真摄像头、零写档）。
## 背景：Python 侧把启动期 RES×5+FPS×5 同步探测风暴移出 `_switch_camera` 关键路径
##（首帧 9.3s→≤3.5s），改为播种最小矩阵 + 按需 PROBE_MATRIX；Godot 菜单**不改**，
## 本文件锁住其既有契约在改造后仍成立：
##   M1 矩阵缓存空 → 非 current 设备行下拉自动发 PROBE_MATRIX:<id> + 「检测中…」
##      （行为 + 源锚：_open_res_sub 空缓存分支走 _request_probe）；
##   M2 id==current——批次 AD-5c 条件探测（取代旧「current 行零 PROBE」口径，旧值留痕）：
##      播种矩阵（init#2）不充分（≤1 档，AD-5b 播种形态）→ 与其它设备行同链路发
##      PROBE_MATRIX:<id>，且子列播种档**立即可用**（不闪「检测中…」）；probe_result 到达 →
##      子列重建列出完整矩阵（P1 分辨率入口恢复主链路）；
##      缓存充分（≥2 档）→ 零 PROBE 直出（不打扰正在推流的设备，双审 P2-6 原意保持）；
##      init#2 未到的瞬时窗（矩阵空）→ 等待态（探测请求照发，8s 裁决既有）；
##      `camera_matrix_received` 到达 → 子列重建列出矩阵（重建钩子不回归）；
##   M3 probe_result 到达 → 非 current 子列重建列出矩阵（既有 U2 契约保持）；
##   M4 批次 AD-5d（终审 P2 闭环）：
##      ① 用户主动关（桥侧 release 锁存在位）→ 悬停 current 行**零 PROBE_MATRIX**、播种档照常
##         直出（P2-A：主动关不复活，探测另开句柄会点亮指示灯）；真值源源锚锁
##         `_camera_release_intent`（不取被 consume 一次性清的 `_intentional_stop`）；
##      ② 未主动关 + 缓存不充分 → 仍发（守住 M2-2①/AD-5c 条件探测原意）；
##      ③ 探测失败回包后，同菜单会话内**不重发**（把 1s 节流推到窗外仍零发——证明拦截
##         不靠节流）；失败即停（播种档直出/检测失败），不再「扫描⇄重探」循环；
##      ④ 重新打开菜单（open_menu 清一次性账）→ 同 id 允许再试一次。
## 夹具纪律：复用 test_t_camera_device 同款手法（面板实例化取 CameraMenu、
## 9878 回环监听抓命令）；不点任何矩阵行（`_remember_camera_choice` 仅在 pressed 里
## 写档 → 全程零写档）。

const PANEL_SCENE := "res://scenes/settings/settings_panel.tscn"
const MENU_SRC := "res://scenes/settings/camera_menu.gd"

var _bridge: Node = null

func _ctrl_listener() -> PacketPeerUDP:
	var l := PacketPeerUDP.new()
	if l.bind(int(_bridge.get_control_port())) != OK:
		return null
	return l

func _recv_cmds(l: PacketPeerUDP) -> Array:
	var out: Array = []
	while l != null and l.get_available_packet_count() > 0:
		out.append(l.get_packet().get_string_from_utf8())
	return out

func _wait_available(l: PacketPeerUDP, frames: int) -> void:
	for i: int in frames:
		if l != null and l.get_available_packet_count() > 0:
			return
		await process_frame

## res 子列当前按钮文本集（等待态/矩阵/失败三态判据数据源）
func _res_texts(menu: Control) -> Array:
	var out: Array = []
	var box: Control = menu.get("_res_box")
	if box == null:
		return out
	for b: Variant in box.get_children():
		if b is Button:
			out.append(String((b as Button).text))
	return out

## GDScript 源锚：取 `func <name>(` 起至下一个 `func ` 为止（test_ad5 同款口径）
func _gd_fn_body(src: String, name: String) -> String:
	var lines: PackedStringArray = src.split("\n")
	var start: int = -1
	for i: int in lines.size():
		if lines[i].begins_with("func %s(" % name):
			start = i
			break
	if start < 0:
		return ""
	var out: PackedStringArray = []
	for i: int in range(start + 1, lines.size()):
		if lines[i].begins_with("func ") or lines[i].begins_with("class "):
			break
		out.append(lines[i])
	return "\n".join(out)

func _initialize() -> void:
	print("== test_ad_batch5b_lazy_matrix（AD-5b 惰性探测 + AD-5c current 条件探测 + AD-5d 终审 P2：M1 检测中+PROBE / M2 不充分→PROBE、probe_result 重建、充分→零 PROBE、播种直出 / M3 probe_result 重建 / M4 主动关零 PROBE、未关仍发、失败不重探、重开菜单可再试）==")
	_bridge = get_root().get_node("GestureBridge")
	var panel: Control = (load(PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await process_frame
	# 批次 AF 终审备案族（语言钉扎先例=6411fae o_catalog_shop）：autoload _ready 推迟至树激活，
	# 须等一帧后钉 zh——用户真实存档现 language=en，不钉则文案断言呈 en 态假红。
	# 编译窗安全：经节点查找而非全局名（--script 模式 autoload 全局名编译期未注册）。
	var i18n_node: Variant = get_root().get_node_or_null("I18n")
	if i18n_node != null:
		i18n_node.call("set_language", "zh")
	var menu: Control = panel.get_node("CameraMenuLayer/CameraMenuPopup/CameraMenu")
	check(menu != null, "前置：CameraMenu 实例就位")

	# ================= 源锚：空缓存分支走 _request_probe（M1-s） =================
	var src: String = FileAccess.get_file_as_string(MENU_SRC)
	check(not src.is_empty(), "M1-s0 前置：camera_menu.gd 可读")
	var probe_body: String = _gd_fn_body(src, "_request_probe")
	check(probe_body.contains("GestureBridge.send_probe_matrix(cam_id)"),
		"M1-s1：_request_probe 收口到桥 send_probe_matrix（探测与主流互斥漏斗保持）")
	var open_body: String = _gd_fn_body(src, "_open_res_sub")
	check(open_body.contains("_request_probe(cam_id)"),
		"M1-s2：_open_res_sub 空缓存分支调用 _request_probe（源锚；红态=惰性探测通路断）")
	check(open_body.contains("_show_wait_state(box, anchor_row)"),
		"M1-s3：空缓存/瞬时窗分支显示「检测中…」等待态（源锚）")

	# ================= M1：矩阵缓存空 → 非 current 行走 PROBE + 检测中 =================
	_bridge.set("_probe_matrix_cache", {})
	_bridge.set("_probe_in_flight", false)
	_bridge.set("_probe_sent_at_ms", -1)
	menu.call("_on_enum", [{"id": 0, "name": "CamA"}, {"id": 1, "name": "CamB"}], 0)
	await process_frame
	var rows: Array = menu.get("_rows")
	check_eq(rows.size(), 2, "M1 前置：设备列表两行")
	var l1 := _ctrl_listener()
	check(l1 != null, "M1 前置：控制口回环监听就位")
	menu.call("_open_res_sub", 1, rows[1])
	await process_frame
	check(_res_texts(menu).has("检测中…"),
		"M1-1：id≠current 且矩阵缓存空 → 「检测中…」等待态（实际 %s）" % [_res_texts(menu)])
	await _wait_available(l1, 6)
	var m1_cmds: Array = _recv_cmds(l1)
	check(m1_cmds.has("PROBE_MATRIX:1"),
		"M1-2：自动下发 PROBE_MATRIX:1（按需惰性探测契约；实际 %s）" % [m1_cmds])

	# ================= M3：probe_result 到达 → 子列重建列出矩阵 =================
	_bridge.call("simulate_packet", JSON.stringify({
		"type": "probe_result", "id": 1, "ok": true,
		"resolutions": [[1280, 720], [640, 480]], "fps_options": [30, 60]}))
	await process_frame
	var m3_texts: Array = _res_texts(menu)
	check(m3_texts.has("1280x720") and m3_texts.has("640x480"),
		"M3：probe_result 到达 → 非 current 子列重建列出矩阵（检测中消失；实际 %s）" % [m3_texts])
	check(not m3_texts.has("检测中…"), "M3：等待态已让位")
	if l1 != null:
		l1.close()

	# ================= M2：current 行条件探测（AD-5c：不充分→按需 PROBE / 充分→零 PROBE）====================
	_bridge.set("_camera_enum", {"cameras": [{"id": 0, "name": "CamA"},
		{"id": 1, "name": "CamB"}], "current_camera": 0})
	# 「未主动关」前置显式钉住（AF 同步批补；M4-2 同款先例）：本段隐含前提=用户未主动关摄像头。
	# 夹具对环境敏感实证——面板 _ready 的 _apply_camera_quadrant 在存档 gesture_input=false 时
	# 走 Q3 分支 request_camera_release → 桥侧 `_camera_release_intent` 锁存主动关意图（批次 U
	# U4-② 正确语义），AD-5d 主动关闸门随即正确拦截 current 行自动探测（项目铁律「主动关不得
	# 复活」）——不清该锁存则 M2-2① 假红于存档环境而非代码回归。
	_bridge.set("_camera_release_intent", false)
	# M2a：播种 init#2 已到但**仅 1 档**（AD-5b 播种形态=不充分）→ 子列播种档立即可用（M2-1
	# 既有不变）+ 按需发 PROBE_MATRIX:0（M2-2① 新语义；旧断言「零 PROBE」等价改写，旧值留痕）
	_bridge.set("_camera_matrix", {"resolutions": [[640, 480]], "fps_options": [30]})
	menu.call("_close_res")
	var l2 := _ctrl_listener()
	check(l2 != null, "M2 前置：监听就位")
	menu.call("_open_res_sub", 0, rows[0])
	await process_frame
	var m2a: Array = _res_texts(menu)
	check(m2a.has("640x480"),
		"M2-1：current 行直读播种矩阵（init#2）→ 子列立即可用（实际 %s）" % [m2a])
	await _wait_available(l2, 6)
	var m2_cmds: Array = _recv_cmds(l2)
	check(m2_cmds.has("PROBE_MATRIX:0"),
		"M2-2①：current 缓存不充分（≤1 档=AD-5b 播种形态）→ 按需发 PROBE_MATRIX:0"
		+ "（AD-5c 条件探测；旧断言 not has(PROBE_MATRIX:0)「零 PROBE」废止留痕；实际 %s）" % [m2_cmds])
	if l2 != null:
		l2.close()
	# M2-5（AD-5c 新增，P1 修复主链路）：current probe_result 到达 → 子列重建列出完整矩阵
	#（旧实现 current 只读全局播种矩阵 → probe_result 重建仍只列 1 档，入口不恢复=红态）
	_bridge.call("simulate_packet", JSON.stringify({
		"type": "probe_result", "id": 0, "ok": true,
		"resolutions": [[1280, 720], [640, 480], [320, 240]], "fps_options": [30, 60]}))
	await process_frame
	var m2full: Array = _res_texts(menu)
	check(m2full.has("1280x720") and m2full.has("640x480") and m2full.has("320x240"),
		"M2-5：current probe_result 到达 → 子列重建列出完整矩阵（分辨率切换入口恢复；实际 %s）" % [m2full])
	# M2-6（旧 M2-2 断言迁移改绑充分性判据）：缓存**充分（≥2 档）**→ 零 PROBE 直出
	#（不打扰推流设备原意保持；四重复位=清 probe 缓存/菜单节流/**一次性探测账**（批次 AD-5d
	# 新增，不复位则 P2-B 会话账会顶替充分性判据致假绿）/桥在飞，确保「零探」
	# 源于充分性判据本身，而非节流或互斥丢弃的副作用假绿）
	menu.call("_close_res")
	_bridge.set("_camera_matrix", {"resolutions": [[1280, 720], [640, 480]], "fps_options": [30, 60]})
	_bridge.set("_probe_matrix_cache", {})
	menu.set("_probe_requested_at", {})
	menu.set("_auto_probe_attempted", {})
	_bridge.set("_probe_in_flight", false)
	_bridge.set("_probe_sent_at_ms", -1)
	var l2b := _ctrl_listener()
	check(l2b != null, "M2-6 前置：监听就位")
	menu.call("_open_res_sub", 0, rows[0])
	await _wait_available(l2b, 6)
	var m2b_cmds: Array = _recv_cmds(l2b)
	check(not m2b_cmds.has("PROBE_MATRIX:0"),
		"M2-6：current 缓存充分（≥2 档）→ 零 PROBE（旧 M2-2「零 PROBE」断言迁此改绑充分性判据；实际 %s）" % [m2b_cmds])
	var m2b_txts: Array = _res_texts(menu)
	check(m2b_txts.has("1280x720") and m2b_txts.has("640x480"),
		"M2-6：充分矩阵零探测直出（实际 %s）" % [m2b_txts])
	if l2b != null:
		l2b.close()
	# M2b：init#2 未到瞬时窗（矩阵空）→ 等待态（探测请求照发）→ camera_matrix_received 到达 → 重建
	menu.call("_close_res")
	_bridge.set("_camera_matrix", {})
	menu.call("_open_res_sub", 0, rows[0])
	await process_frame
	var m2b_wait: Array = _res_texts(menu)
	check(m2b_wait.has("检测中…"),
		"M2-3：current 矩阵瞬时窗 → 等待态（实际 %s）" % [m2b_wait])
	_bridge.set("_camera_matrix", {"resolutions": [[640, 480]], "fps_options": [30]})
	_bridge.emit_signal("camera_matrix_received", [[640, 480]], [30])
	await process_frame
	var m2b: Array = _res_texts(menu)
	check(m2b.has("640x480"),
		"M2-4：camera_matrix_received 到达 → current 子列重建列出矩阵（重建钩子不回归；"
		+ "实际 %s）" % [m2b])
	menu.call("_close_res")

	# ================= M4：批次 AD-5d（终审 P2 闭环：P2-A 主动关不复活 / P2-B 一会话一探）====================
	rows = menu.get("_rows")
	check_eq(rows.size(), 2, "M4 前置：设备列表两行")
	_bridge.set("_camera_enum", {"cameras": [{"id": 0, "name": "CamA"},
		{"id": 1, "name": "CamB"}], "current_camera": 0})
	_bridge.set("_camera_matrix", {"resolutions": [[640, 480]], "fps_options": [30]})   # 播种 1 档=不充分
	_bridge.set("_probe_matrix_cache", {})
	_bridge.set("_probe_in_flight", false)
	_bridge.set("_probe_sent_at_ms", -1)
	menu.set("_probe_requested_at", {})
	menu.set("_auto_probe_attempted", {})
	# --- M4-s 源锚（P2-A 闸门真值源 / P2-B 会话账接点）---
	var gate_body: String = _gd_fn_body(src, "_camera_released")
	check(not gate_body.is_empty() and gate_body.contains("_camera_release_intent"),
		"M4-s1：主动关闸门谓词在位且真值源=桥侧 release 锁存 `_camera_release_intent`（源锚；"
		+ "不取被 main.gd consume_intentional_stop 一次性清的 `_intentional_stop`；实际 %s）"
		% [gate_body])
	check(_gd_fn_body(src, "_open_res_sub").contains("_camera_released()"),
		"M4-s2：current 条件探测判据并入 _camera_released() 闸门（源锚；红态=P2-A 未接闸）")
	check(_gd_fn_body(src, "_request_probe").contains("_auto_probe_attempted"),
		"M4-s3：自动探测收口 _request_probe 并入「一会话一探」账（源锚；红态=P2-B 未接闸）")
	# --- M4-1（P2-A①）：用户主动关 → 悬停 current 行零 PROBE_MATRIX，播种档照常直出 ---
	_bridge.set("_camera_release_intent", true)
	check(bool(_bridge.get("_camera_release_intent")),
		"M4-1 前置：桥侧 release 锁存在位（真值源留痕——本闸门判据即它）")
	var l4 := _ctrl_listener()
	check(l4 != null, "M4-1 前置：监听就位")
	menu.call("_open_res_sub", 0, rows[0])
	await _wait_available(l4, 6)
	var m4a: Array = _recv_cmds(l4)
	check(not m4a.has("PROBE_MATRIX:0"),
		"M4-1（P2-A①）：主动关后悬停 current 行不发 PROBE_MATRIX（零开镜=指示灯不点亮；实际 %s）"
		% [m4a])
	check(_res_texts(menu).has("640x480"),
		"M4-1：闸门只关探测——已有矩阵/播种档照常直出（实际 %s）" % [_res_texts(menu)])
	# --- M4-2（P2-A②）：未主动关 + 缓存不充分 → 仍发（守住 M2-2①/AD-5c 条件探测原意）---
	menu.call("_close_res")
	_bridge.set("_camera_release_intent", false)
	_bridge.set("_probe_in_flight", false)
	_bridge.set("_probe_sent_at_ms", -1)
	menu.set("_probe_requested_at", {})
	menu.set("_auto_probe_attempted", {})
	menu.call("_open_res_sub", 0, rows[0])
	await _wait_available(l4, 6)
	var m4b: Array = _recv_cmds(l4)
	check(m4b.has("PROBE_MATRIX:0"),
		"M4-2（P2-A②）：未主动关且缓存不充分（≤1 档）→ 仍发 PROBE_MATRIX:0"
		+ "（AD-5c 条件探测守住 M2-2① 原意；实际 %s）" % [m4b])
	# --- M4-3（P2-B③）：失败回包后同会话不重探（把 1s 节流推到窗外，证明拦截不靠节流）---
	menu.call("_close_res")
	_bridge.set("_probe_in_flight", false)
	_bridge.set("_probe_sent_at_ms", -1)
	menu.set("_probe_requested_at", {})
	menu.set("_auto_probe_attempted", {})
	menu.call("_open_res_sub", 0, rows[0])   # 第 1 次自动探测（照发，前置）
	await _wait_available(l4, 6)
	var m4c1: Array = _recv_cmds(l4)
	check(m4c1.has("PROBE_MATRIX:0"), "M4-3 前置：首探发出（实际 %s）" % [m4c1])
	_bridge.call("simulate_packet", JSON.stringify({
		"type": "probe_result", "id": 0, "ok": false}))
	await process_frame
	# 回包重建（_on_probe_result）会再落一次漏斗；此处节流窗多半未过（节流本就拦得住），
	# 故显式把节流推到窗外（now-2000ms）再 hover 一次：红态（无会话账）→ 重发
	# PROBE_MATRIX:0（「扫描⇄重探」循环实证）；绿态零重发（拦截只可能来自一会话一探账）。
	menu.set("_probe_requested_at", {0: int(Time.get_ticks_msec()) - 2000})
	menu.call("_close_res")
	menu.call("_open_res_sub", 0, rows[0])
	await _wait_available(l4, 6)
	var m4c2: Array = _recv_cmds(l4)
	check(not m4c2.has("PROBE_MATRIX:0"),
		"M4-3（P2-B③）：失败回包后同菜单会话不重发（1s 节流已推到窗外仍零发；实际 %s）"
		% [m4c2])
	check(not _res_texts(menu).has("检测中…"),
		"M4-3：失败后不再进入「检测中…」等待态（停在播种档直出；实际 %s）" % [_res_texts(menu)])
	# --- M4-4（P2-B④）：重新打开菜单 = 显式动作 → 该 id 允许再试一次 ---
	menu.call("_close_res")
	menu.call("open_menu")   # open_menu 清一次性账（清点先于一切早退；菜单节流另行显式复位以隔离变量）
	rows = menu.get("_rows")   # open_menu → _apply_enum 重建行（旧 rows 引用作废）
	check_eq(rows.size(), 2, "M4-4 前置：重开菜单后设备列表仍两行")
	_bridge.set("_probe_in_flight", false)
	_bridge.set("_probe_sent_at_ms", -1)
	menu.set("_probe_requested_at", {})
	menu.call("_open_res_sub", 0, rows[0])
	await _wait_available(l4, 6)
	var m4d: Array = _recv_cmds(l4)
	check(m4d.has("PROBE_MATRIX:0"),
		"M4-4（P2-B④）：重新打开菜单后同 id 允许再探一次（重开=显式动作解锁；实际 %s）" % [m4d])
	if l4 != null:
		l4.close()
	_bridge.set("_camera_release_intent", false)   # 夹具收尾：真值还原

	# ================= 收尾：夹具复位（进程即退，仍按纪律清位） =================
	_bridge.set("_camera_enum", {})
	_bridge.set("_camera_matrix", {})
	_bridge.set("_probe_matrix_cache", {})
	panel.free()
	finish()
