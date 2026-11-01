extends "res://tests/test_base.gd"
## 批次 R 判定用例：手势存档字段迁移 + 设置面板层级（spec §11.1-4）。
## 本文件分两段落位：R-B-3 落「存档段」（默认档/旧档归一/save_version/落盘）；R-F-1 追加「面板段」
## （四象限状态机/kb_input 停写/L 形连接线/感叹号说明框）。契约：spec §8.2/§8.4。
## 批次 V（V-C4，spec §4.2）：Q1 拦截钩子退役等价替换——U1-②「Q1 裸点击 toast 逐字」断言
## 随 Q1_TOAST_TEXT/q1_last_toast 删除作废（禁关语义改经 Game.info 成条）；Q3 直关断言改
## confirm 门控（确认才落盘+RELEASE）；Q4 迁移通道断言不变。环境说明：--script 无头 autoload
## 不触发 _ready → 显式 save.load_game()。

const SAVE_PATH := "user://save.json"

## 批次 V（V-C4）：TopStrip 替身（test_v_game_confirm 同款）——态① info/态② confirm 断言落点
##（Game.info/confirm 经 V-C3a 委托链记录到替身；进程内单测试实例，收尾 attach_strip(null) 摘除）。
class GssStrip extends Node:
	var info_calls: Array = []    # 每项 [text, seconds]
	var confirm_calls: Array = [] # 每项 [text, on_confirmed, on_canceled]
	func push_info(text: String, seconds: float = 3.0) -> void:
		info_calls.append([text, seconds])
	func push_confirm(text: String, on_confirmed: Callable = Callable(),
			on_canceled: Callable = Callable()) -> void:
		confirm_calls.append([text, on_confirmed, on_canceled])

func _cleanup() -> void:
	var p: String = ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)

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
const DISC_BK_PREFIX := "user://_r2b_gss_backup_"
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
	print("EVID|user_restore|gss|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_gesture_settings_save ==")
	_backup_user()
	var save: Variant = get_root().get_node("SaveManager")
	_cleanup()
	save.load_game()

	# ---- 存档段 1：默认档含两新字段（§8.4）----
	var s: Dictionary = save.get_settings()
	check_eq(bool(s.get("gesture_camera_enabled", null)), true, "默认 gesture_camera_enabled=true")
	check_eq(bool(s.get("gesture_panel_folded", null)), false, "默认 gesture_panel_folded=false")

	# ---- 存档段 2：旧档（缺键）load 后归一为 true/false；save_version 仍 2 ----
	var legacy := {
		"save_version": 2,
		"progress": {"cleared": [], "next_chapter": 1, "watched_opening": false, "level_progress": {}},
		"settings": {"gesture_input": true, "kb_input": true, "udp_port": 0},
		"talent": 500,
		"skins": {"owned": ["skin_default"], "equipped": "skin_default"},
		"replay_award_counts": {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0},
	}
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(legacy))
	f.close()
	save.load_game()
	s = save.get_settings()
	check_eq(int(save._data["save_version"]), 2, "save_version 维持 2 不升版")
	check_eq(bool(s["gesture_camera_enabled"]), true, "旧档缺 gesture_camera_enabled → 归一 true")
	check_eq(bool(s["gesture_panel_folded"]), false, "旧档缺 gesture_panel_folded → 归一 false")
	check_eq(int(s["udp_port"]), 0, "udp_port 归一先例仍生效（:88 口径）")

	# ---- 存档段 3：字段可写并落盘（update_settings 变更即存先例）----
	save.update_settings({"gesture_camera_enabled": false, "gesture_panel_folded": true})
	var f2: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	check(f2 != null, "update_settings 后存档文件存在")
	if f2 != null:
		var parsed: Variant = JSON.parse_string(f2.get_as_text())
		f2.close()
		check_eq(bool(parsed["settings"]["gesture_camera_enabled"]), false, "文件 gesture_camera_enabled=false 已落盘")
		check_eq(bool(parsed["settings"]["gesture_panel_folded"]), true, "文件 gesture_panel_folded=true 已落盘")

	# ---- 存档段 4：DEFAULT_UDP_PORT 值不变、:15 TODO 已删（§3.3/§8.4）----
	check_eq(int(save.DEFAULT_UDP_PORT), 9876, "DEFAULT_UDP_PORT 维持 9876")
	var src := FileAccess.open("res://autoload/save_manager.gd", FileAccess.READ)
	check(src != null, "save_manager.gd 可读")
	if src != null:
		var text := src.get_as_text()
		src.close()
		check(not text.contains("TODO 暂定值"), "save_manager.gd :15 的 TODO 暂定值注释已删")

	# ==================== 面板段（R-F-1，spec §11.1-4/§8.1/§8.2） ====================
	var theme_mgr: Variant = get_root().get_node("ThemeManager")
	theme_mgr._dark_theme = load("res://themes/theme_dark.tres")
	# 批次 AB-3：深浅主题机制删除——_light_theme/_last_dark 注入退役（恒深档）。
	_cleanup()
	save.load_game()
	# 批次 V（V-C4）：挂 TopStrip 替身（收尾摘除）——三态流 Game.info/confirm 断言落点
	var game_gss: Variant = get_root().get_node("Game")
	var gss_strip := GssStrip.new()
	add_child(gss_strip)
	game_gss.attach_strip(gss_strip)
	check(ResourceLoader.exists("res://scenes/settings/settings_panel.tscn"), "settings_panel.tscn 存在")
	var panel: Control = load("res://scenes/settings/settings_panel.tscn").instantiate()
	add_child(panel)
	await process_frame
	await process_frame
	var gt: Button = panel.get_node("Panel/VBox/OptionsBox/GestureToggle")
	var ct: Button = panel.get_node("Panel/VBox/OptionsBox/CameraRow/CameraToggle")
	# ---- 面板段 1：KbToggle 删除（节点+脚本引用+同关校验函数）----
	check(panel.get_node_or_null("Panel/VBox/OptionsBox/KbToggle") == null, "KbToggle 节点已删（§8.1）")
	check(not panel.has_method("_on_input_toggled"), "同关校验函数 _on_input_toggled 已删（§8.1）")
	# ---- 面板段 2：L 形连接线节点存在与缩进断言（§8.1）----
	var lline: Control = panel.get_node_or_null("Panel/VBox/OptionsBox/CameraRow/LLine")
	check(lline is Control, "LLine 连接线容器存在")
	if lline != null:
		var rects: int = 0
		for c: Node in lline.get_children():
			if c is ColorRect:
				rects += 1
		check_eq(rects, 2, "L 形线=竖 2×16+横 16×2 两枚 ColorRect")
		# 终审 P3-1：L 形线连续——旧 HSeg(x16~32) 与 VLine(x0~2) 之间 14px 断口，左移至 x2 起
		# （宽 30）使 VLine(x0~2,y0~14) 与 HSeg(x2~32,y14~16) 在 (2,14) 角点连成连续 L 形
		# （缩进 32 语义不变，CameraToggle 起点位不变）。
		var vline: ColorRect = lline.get_node_or_null("VLine")
		var hseg: ColorRect = lline.get_node_or_null("HSeg")
		if vline != null and hseg != null:
			check(hseg.offset_left <= vline.offset_right + 0.01
				and hseg.offset_top >= vline.offset_bottom - 0.01,
				"L 形线连续：HSeg 自 VLine 底部右缘 (2,14) 角点起笔（无 14px 断口）")
	# ---- 面板段 2b（批次 S S8）：「跟随手势」全宽长条 + 文字居中 + 左缩进 32 ----
	var ab8: Button = panel.get_node("Panel/VBox/OptionsBox/CameraRow/ArrowBtn")
	check_eq(int(ct.size_flags_horizontal), 3, "S8：CameraToggle size_flags_horizontal=3（expand+fill 占满剩余宽度）")
	check_eq(int(ab8.size_flags_vertical), 4, "T12：ArrowBtn size_flags_vertical=4（24×24 垂直居中；旧 ExclaimBtn 20×20 等价替换留痕，P0-7 改名连锁）")
	check_eq(float(lline.custom_minimum_size.x), 32.0, "S8：LLine 缩进恰 32px（保留层级表达，与既有 ≥32 断言并存）")
	check(absf(ct.size.y - gt.size.y) < 0.5, "S8：布局后 CameraToggle 行高与主项 GestureToggle 一致（同主题按钮默认高）")
	check(ct.size.x > 300.0, "S8：布局后 CameraToggle 为全宽长条（>300px；旧病灶=最小内容宽 ≈110px 右侧空白）")
	var cr: Control = panel.get_node("Panel/VBox/OptionsBox/CameraRow")
	check(cr is HBoxContainer, "CameraRow 容器存在")
	check((panel.get_node("Panel/VBox/OptionsBox/CameraRow/LLine") as Control).custom_minimum_size.x >= 32.0,
		"摄像头子项缩进 32px（LLine 宽度承载缩进，L 形线表达从属）")
	# ---- 面板段 3：四象限状态机（§8.2）----
	gt.button_pressed = true
	gt.toggled.emit(true)
	# 批次 U 等价替换（U1，spec §4-U1-1）：Q1 亮态可点＋文本「摄像头」（旧 disabled+「跟随手势」废止）
	check(not ct.disabled, "U1：Q1 摄像头子开关不再 disabled")
	check_eq(String(ct.text), "摄像头", "U1：Q1 文本「摄像头」（两态统一）")
	check_eq(bool(ct.button_pressed), true, "Q1：摄像头强制开")
	check_eq(bool(save.get_settings()["gesture_camera_enabled"]), true, "Q1 落盘 gesture_camera_enabled=true")
	# ---- 批次 V（V-C4，spec §4.2）等价替换留痕「批次V规格§4.2」：U1-② Q1 拦截钩子退役 →
	# 三态流态① info 条——旧「toast 逐字 Q1_TOAST_TEXT」断言随常量/q1_last_toast 观测成员删除
	# 作废；「存档零状态变化/亮态复位」两断言等价保留，禁关反馈落点改经 Game.info 顶部成条 ----
	var quadrant_before: Dictionary = save.get_settings().duplicate()
	# 批次 W（N5）等价改写：「无法关闭」info 条收窄到「摄像头真实已开」态（未开时点击=打开
	# 进 OPENING，见 test_w_camera_button N5②）——本段断言按原语义在 READY+未主动关注入下验证。
	var gb_v4: Node = get_root().get_node("GestureBridge")
	var gb_state_v4: int = int(gb_v4.get_load_state())
	var gb_released_v4: bool = bool(gb_v4.get("_intentional_stop"))
	gb_v4.set("_intentional_stop", false)
	gb_v4._set_state(1)   # READY
	# 批次 Y（Y-A17/㉔）等价注入：info 判据=「摄像头流真实开启」——camera_opened 事件注入开启真值
	gb_v4.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "HD Camera"}))
	await process_frame
	ct.set_pressed_no_signal(false)
	ct.toggled.emit(false)
	await process_frame
	check_eq(bool(save.get_settings().get("gesture_camera_enabled", false)), true,
		"V-C4：态① 点击 → 存档 gesture_camera_enabled 保持 true（零写档；.get 防坑 2）")
	check(bool(ct.button_pressed), "V-C4：态① 点击 → 亮态立即复位（set_pressed_no_signal(true)）")
	check(panel.get("q1_last_toast") == null,
		"V-C4：q1_last_toast 观测成员已退役（get null，旧 U1 toast 观测断言等价替换留痕）")
	check_eq(gss_strip.info_calls.size(), 1,
		"V-C4：态① 点击 → Game.info 成条恰 1 次（旧 Q1_TOAST_TEXT 拦截 toast 等价替换）")
	if gss_strip.info_calls.size() >= 1:
		check_eq(String(gss_strip.info_calls[0][0]), "手势交互需要摄像头，无法关闭",
			"V-C4：态① info 文案逐字（批次V规格§3.3①）")
	gb_v4._set_state(gb_state_v4)   # 桥态还原（N5 等价改写注入的 READY 退出，防后续段污染）
	gb_v4.set("_intentional_stop", gb_released_v4)
	gt.set_pressed_no_signal(false)
	gt.toggled.emit(false)
	check(not ct.disabled, "Q2：子开关可点")
	var ab: Button = panel.get_node("Panel/VBox/OptionsBox/CameraRow/ArrowBtn")
	check(ab.visible, "T12：箭头钮常显（Q1/Q2 均可见；旧「感叹号图标可见」等价替换留痕）")
	# ---- 批次 V（V-C4）等价替换留痕「批次V规格§4.2」：Q3「点关即直关落盘」退役 → confirm 门控
	#（确认才进 Q3 分支 RELEASE+写档 false；旧直关断言等价替换为「确认条弹出→模拟确认→落盘」）----
	ct.set_pressed_no_signal(false)
	ct.toggled.emit(false)
	check_eq(gss_strip.confirm_calls.size(), 1,
		"V-C4：态② 点击 → Game.confirm 确认条恰 1 次（旧 Q3 直关等价替换）")
	if gss_strip.confirm_calls.size() >= 1:
		check_eq(String(gss_strip.confirm_calls[0][0]), "摄像头关闭后，下次开启手势交互需要重新等待数秒启动。",
			"V-C4：态② confirm 文案逐字（批次V规格§3.3②）")
		check_eq(bool(save.get_settings().get("gesture_camera_enabled", true)), true,
			"V-C4：态② 未确认前零副作用（不落盘不释放）")
		(gss_strip.confirm_calls[0][1] as Callable).call()   # 模拟 TopStrip「确认」
	check_eq(bool(save.get_settings()["gesture_camera_enabled"]), false, "Q3：确认后落盘 false（批次 U 语义延续：request_camera_release+落盘不变；批次 V 起 confirm 门控前置）")
	gt.button_pressed = true
	gt.toggled.emit(true)
	check_eq(bool(save.get_settings()["gesture_camera_enabled"]), true, "Q4：手势重新开 → 摄像头自动回开（重启路径；V-C4 迁移通道不变）")
	# ---- 面板段 4（批次 T 等价替换留痕：感叹号 GlassDialog 说明框废止 → 悬浮说明窗 + 下拉挂载）----
	gt.set_pressed_no_signal(false)
	gt.toggled.emit(false)
	check(panel.get_node_or_null("CamTip") is PanelContainer or panel.find_children("*", "PanelContainer", true, false).any(
		func(un: Variant) -> bool: return (un as Node).get_script() == load("res://scenes/shared/hover_tip.gd")),
		"T13：悬浮跟随说明窗已挂载（批次 U 等价替换：CamTip 私有件废止 → HoverTip 共享组件承接）")
	check(panel.get_node_or_null("CameraMenuLayer/CameraMenuPopup/CameraMenu") != null,
		"T12：CameraMenuPopup/CameraMenu 已挂载（批次 U：宿主迁 CameraMenuLayer 层 65，路径等价替换）")
	check(not panel.has_method("_on_exclaim_pressed"), "T13：_on_exclaim_pressed 已删（GlassDialog 路径废止）")
	var srcq: String = FileAccess.get_file_as_string("res://scenes/settings/settings_panel.gd")
	# 走查移交项①（2026-09-18）等价替换：旧断言「Q2 含 start_gesture_process()」锁的是旁路本体
	# ——u10/u11 实证该旁路在打包形态（start 恒 false+probe ready）不发 SWITCH_CAMERA，RELEASE 后
	# 经 Q2 不重开。反转为「统一入口在场＋旁路已删」；行为级红灯断言在 test_t_camera_device 段 1。
	check(srcq.contains("GestureBridge.ensure_camera_open()"),
		"U移交①：Q2 分支统一入口 GestureBridge.ensure_camera_open() 在场（源码证据链，spawn 无头不可达）")
	check(not srcq.contains("GestureBridge.start_gesture_process()"),
		"U移交①：Q2 直调 start_gesture_process 旁路已删（打包形态不发 SWITCH_CAMERA 的根因源头）")
	# ---- 面板段 5：_save_settings 不再写 kb_input（旧值保持不覆盖，§8.1）----
	save.update_settings({"kb_input": false})
	var ht: Button = panel.get_node("Panel/VBox/OptionsBox/HudToggle")
	ht.set_pressed_no_signal(not bool(ht.button_pressed))
	ht.toggled.emit(not bool(ht.button_pressed))
	var f5: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	check(f5 != null, "面板段：存档可读")
	if f5 != null:
		var parsed5: Variant = JSON.parse_string(f5.get_as_text())
		f5.close()
		check_eq(bool(parsed5["settings"]["kb_input"]), false, "面板操作后 kb_input 保持旧值 false（停写验证）")
	panel.queue_free()
	await process_frame
	game_gss.attach_strip(null)   # 摘除替身（复位路由，test_t_camera_device 段5 同款收尾）
	gss_strip.queue_free()
	await process_frame
	_cleanup()
	finish()
