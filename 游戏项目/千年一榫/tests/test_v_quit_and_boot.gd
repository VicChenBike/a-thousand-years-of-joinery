extends "res://tests/test_base.gd"
## 批次 V（V-C6，spec §3.2/§3.3③/§3.4/§8 + 审查①P2-4 + V-C4 移交断言收尾）判定用例：
## main.gd 域收口（TDD 先写）。契约：
##   ① 启动提示条（V19，§3.3③）：main.gd _ready 路由主菜单后短暂延迟 → Game.info(
##     "本游戏支持手势交互和键鼠交互", 4.0)——首次与再次启动都弹（不写档、不判首启）；
##   ② 退出兜底保存（V18，§8）：main.gd _quit_now_shared（窗口×确认与所有确认退出共用的真退出
##     函数）在 stop/quit 前 SaveManager.save_game() 兜底；main_menu.gd _quit_now 同构；
##   ③ ExitConfirmDialog 迁移（§3.2）：main.tscn 节点退役，main.gd 窗口×改 Game.confirm(
##     "退出《千年一榫》？", _quit_now_shared)（文案与既有弹窗正文逐字一致）；确认=真退出，
##     取消/×=零副作用；旧组件文件本体保留不删（settle_scene 先例）；
##   ④ toast_center 中央盒退役（§3.4）：无 _ensure_center_box/CENTER_TOP 源码；push/clear_all
##     公开 API 不变；centered=true 直推不再建中央锚点盒（几何常量单源迁 top_strip.gd）；
##   ⑤ TopStrip 跨态收起（审查①P2-4）：订阅 Game.state_changed（_ready 订阅/_exit_tree 退订），
##     场景切换时 confirm 常驻 → 自动按取消收起（on_canceled 执行、零副作用）；info 不受影响；
##     防重入（同帧重复 state_changed 只生效一次）。
## 4.7 坑对照：回调判空 is_valid（坑 1）；.get 防御（坑 2）；--script 时序 await（坑 5）；
##   lambda 计数用成员变量（坑 8）；信号退订（_exit_tree）。
## 走查清档规范（tools/README_走查清档规范.md）：save.json 起测前快照 / 终测还原 + load_game
##   重同步 + EVID 证据行；退出兜底行为断言经子进程探针（-- --probe-quit-save）——本文件自举
##   复用（进程内调 _quit_now_shared 会真退当前测试进程）。

const BOOT_TEXT := "本游戏支持手势交互和键鼠交互"
const EXIT_TEXT := "退出《千年一榫》？"
const MAIN_SCENE := "res://scenes/main.tscn"
const SAVE_PATH := "user://save.json"
const MARKER_PORT := 43219

## TopStrip 替身（test_v_confirm_migration 同款夹具形态）：记录 push_info/push_confirm 参数。
class StripSpy extends Node:
	var info_calls: Array = []     # 每项 [text, seconds]
	var confirm_calls: Array = []  # 每项 [text, on_confirmed, on_canceled]
	func push_info(text: String, seconds: float = 3.0) -> void:
		info_calls.append([text, seconds])
	func push_confirm(text: String, on_confirmed: Callable = Callable(),
			on_canceled: Callable = Callable()) -> void:
		confirm_calls.append([text, on_confirmed, on_canceled])
	func get_info_calls() -> Array:
		return info_calls
	func get_confirm_calls() -> Array:
		return confirm_calls

var _strip_ok := 0
var _strip_cancel := 0

func _snapshot_save() -> String:
	## 走查清档规范第 1 条：任何删/写档前快照（内存文本，无盘外落物）。
	if FileAccess.file_exists(SAVE_PATH):
		return FileAccess.get_file_as_string(SAVE_PATH)
	return ""

func _cleanup() -> void:
	for suffix: String in ["", ".tmp", ".bak"]:
		var p: String = SAVE_PATH + suffix
		var abs: String = ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs):
			DirAccess.remove_absolute(abs)

func _restore_save(pre: String) -> void:
	## 走查清档规范第 2 条：退出路径统一还原 + load_game 重同步 + EVID 证据行。
	_cleanup()
	if pre != "":
		var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(pre)
			f.close()
	var sm: Node = get_root().get_node("SaveManager")
	if sm != null:
		sm.call("load_game")
	print("EVID|user_restore|quit_and_boot|snapshot_bytes=%d" % pre.length())

## 子进程探针模式（-- --probe-quit-save）：boot 自动保存后回到「磁盘无档」基线 → 内存写标记
## （直改 dict 不落盘）→ 调 _quit_now_shared（预期 save_game 落盘含标记 → stop → quit）→
## 父进程验磁盘档与标记。判据甄别性：标记写入晚于 boot 全部自动保存点，且 quit 本身无自动保存
##（tmp 探针 2026-09-19 实证：get_tree().quit() 不触发 close_requested）——磁盘出现「档+标记」
## 唯一来源=_quit_now_shared 的兜底 save_game（旧实现=两断言全红）。
## --script 时序实证留痕：autoload _ready 延迟到首帧才跑且其 load_game 重置 _data——探针首行
## 先 await 一帧放行，内存写入全部置于其后（否则标记被重置，首次红灯运行即踩）。
func _probe_quit_save() -> void:
	await process_frame
	var sm: Node = get_root().get_node("SaveManager")
	_cleanup()
	sm.call("load_game")
	var s: Dictionary = sm.call("get_settings")
	s["gesture_input"] = false                        # Q3 夹具：防 boot 期手势子进程拉起
	s["gesture_camera_enabled"] = false
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	get_root().add_child(main)
	await process_frame
	await process_frame   # boot 自动保存（goto_state→restore_preferred_skin→save_game）已落盘
	_cleanup()            # 回「磁盘无档」基线——此后至 quit 之间唯一写点=兜底保存
	s = sm.call("get_settings")
	s["udp_port"] = MARKER_PORT                       # 退出前内存变更（绕开 update_settings 自动保存）
	main.call("_quit_now_shared")   # 预期进程在此结束（exit 0）
	# 兜底：实现回退未 quit 时 5s 后以码 3 退出（父进程判红，不悬挂）
	await create_timer(5.0).timeout
	quit(3)

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--probe-quit-save"):
		await _probe_quit_save()
		return
	print("== test_v_quit_and_boot ==")
	var pre_save: String = _snapshot_save()
	var game_node: Node = get_root().get_node("Game")
	var save_node: Node = get_root().get_node("SaveManager")
	var bridge_node: Node = get_root().get_node("GestureBridge")
	_cleanup()
	save_node.call("load_game")
	# Q3 夹具 + READY 基线：防 boot 期手势子进程拉起与 UNAVAILABLE 噪声（boot 提示无条件，
	# 与象限无关；update_settings 会自动落盘——测试态，终测统一还原）。
	save_node.call("update_settings", {"gesture_input": false, "gesture_camera_enabled": false})
	bridge_node.call("_set_state", 1)
	var main_src: String = FileAccess.get_file_as_string("res://scenes/main.gd")
	var spy := StripSpy.new()
	add_child(spy)

	# ---- A. 启动提示条（V19，spec §3.3③）：boot 后 Game.info 恰 1 次、文案逐字、4s 档 ----
	var main1: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(main1)
	await process_frame
	# 批次 AF 终审备案族（语言钉扎先例=6411fae o_catalog_shop）：autoload _ready 推迟至树激活，
	# 须等一帧后钉 zh——用户真实存档现 language=en，不钉则文案断言呈 en 态假红。
	# 编译窗安全：经节点查找而非全局名（--script 模式 autoload 全局名编译期未注册）。
	var i18n_node: Variant = get_root().get_node_or_null("I18n")
	if i18n_node != null:
		i18n_node.call("set_language", "zh")
	game_node.call("attach_strip", spy)   # main._ready 已挂自条 → 换 spy 捕获 boot 提示
	await create_timer(1.0).timeout       # 实现为一帧+0.3s 延迟，1.0s 窗口充分覆盖
	var calls1: Array = spy.get_info_calls()
	check_eq(calls1.size(), 1, "V19：boot 后 Game.info 恰 1 次（Q3 夹具下零其他中央提示噪声）")
	if calls1.size() >= 1:
		check_eq(String(calls1[0][0]), BOOT_TEXT, "V19：启动提示文案逐字（spec §3.3③）")
		check_eq(float(calls1[0][1]), 4.0, "V19：4s 自灭档（push_info(text, 4.0)）")
	check(main_src.contains("Game.info(I18n.t(\"%s\")" % BOOT_TEXT),
		"V19：main.gd 启动提示文案单源逐字（源码级锁；AF-I18n 波后经 I18n.t 包装，zh 直通原样）")

	# ---- B. 窗口×确认路径经 Game.confirm（§3.2 迁移点①） ----
	var wb1: Node = main1.get_node("GlobalUI/WindowButtons")
	var st_b: int = int(game_node.call("current_state"))
	wb1.emit_signal("close_pressed")      # 窗口× → _on_window_close → Game.confirm（不直接退出）
	check_eq(spy.get_confirm_calls().size(), 1, "V-C6 §3.2：窗口× → Game.confirm 统一确认条恰 1 条")
	if spy.get_confirm_calls().size() == 1:
		var rec: Array = spy.get_confirm_calls()[0]
		check_eq(String(rec[0]), EXIT_TEXT, "V-C6 §3.2：窗口×确认文案逐字（与旧 ExitConfirmDialog 正文一致）")
		check((rec[1] as Callable).is_valid(), "V-C6 §3.2：确认回调已接线（_quit_now_shared；测试不触发——无头会真退）")
		check(not (rec[2] as Callable).is_valid(), "V-C6 §3.2：取消/×缺省空回调（零副作用语义）")
	check_eq(int(game_node.call("current_state")), st_b, "V-C6 §3.2：窗口×确认前不退出不路由（状态不变）")

	# ---- C. 再次 boot 仍弹（不写档、不判首启） ----
	main1.queue_free()
	await process_frame
	var main2: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(main2)
	await process_frame
	game_node.call("attach_strip", spy)
	await create_timer(1.0).timeout
	var calls2: Array = spy.get_info_calls()
	check_eq(calls2.size(), 2, "V19：再次 boot 仍弹（恰第 2 条，无首启判据/写档去重）")
	if calls2.size() >= 2:
		check_eq(String(calls2[1][0]), BOOT_TEXT, "V19：第二次启动提示文案逐字")
	check(main2.get_node_or_null("GlobalUI/ExitConfirmDialog") == null,
		"V-C6 §3.2：入树 main 实例无 ExitConfirmDialog 节点（退役）")
	main2.queue_free()
	await process_frame

	# ---- D. ExitConfirmDialog 退役（§3.2；镜像 V-C5 对 main_menu.tscn 的处置） ----
	var main_tscn_src: String = FileAccess.get_file_as_string(MAIN_SCENE)
	check(not main_tscn_src.contains("ExitConfirmDialog"),
		"V-C6 §3.2：main.tscn 无 ExitConfirmDialog 节点声明（源码级）")
	check(not main_tscn_src.contains("glass_dialog"),
		"V-C6 §3.2：main.tscn 无 glass_dialog ext_resource 引用（随节点一并清理）")
	check(not main_src.contains("ExitConfirmDialog") and not main_src.contains("GlassDialog"),
		"V-C6 §3.2：main.gd 零旧弹窗引用（@onready/接线/主题刷新全退役）")
	check(main_src.contains("Game.confirm(\"%s\", _quit_now_shared)" % EXIT_TEXT),
		"V-C6 §3.2：main.gd 窗口×接线 Game.confirm(退出《千年一榫》？, _quit_now_shared)（源码级）")
	check(ResourceLoader.exists("res://scenes/shared/glass_dialog.gd")
		and ResourceLoader.exists("res://scenes/shared/glass_dialog.tscn"),
		"V-C6 §3.2：旧组件文件本体保留不删（settle_scene 先例）")

	# ---- E. 退出兜底保存（V18，§8）：源码序（save_game 先于 stop/quit）+ 子进程探针落盘 ----
	var quit_body := _func_body(main_src, "func _quit_now_shared(")
	check(quit_body.contains("SaveManager.save_game()")
		and quit_body.find("SaveManager.save_game()") < quit_body.find("stop_gesture_process"),
		"V18 §8：_quit_now_shared 在 stop_gesture_process 前 SaveManager.save_game()（窗口×确认与所有确认退出共用真退出函数）")
	var mm_src: String = FileAccess.get_file_as_string("res://scenes/menu/main_menu.gd")
	var mm_quit_body := _func_body(mm_src, "func _quit_now(")
	check(mm_quit_body.contains("SaveManager.save_game()")
		and mm_quit_body.find("SaveManager.save_game()") < mm_quit_body.find("stop_gesture_process"),
		"V18 §8：main_menu._quit_now 同构兜底（主菜单退出路径 save_game 先于 stop）")
	# 子进程探针（进程内调 _quit_now_shared 会真退当前测试进程 → 自举复用本文件）
	var out: Array = []
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tests/test_v_quit_and_boot.gd", "--", "--probe-quit-save"])
	var code: int = OS.execute(OS.get_executable_path(), args, out, true, true)
	check_eq(code, 0, "V18：退出兜底探针子进程按预期收口（_quit_now_shared → quit，exit 0）")
	check(FileAccess.file_exists(SAVE_PATH),
		"V18：_quit_now_shared 退出前 save_game 落盘（boot 自动保存已清的无档基线 → 退出后档在；quit 本身无自动保存——探针实证）")
	var marker_ok := false
	if FileAccess.file_exists(SAVE_PATH):
		var parsed_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if typeof(parsed_v) == TYPE_DICTIONARY:
			var st_v: Variant = (parsed_v as Dictionary).get("settings", null)
			if typeof(st_v) == TYPE_DICTIONARY:
				marker_ok = int((st_v as Dictionary).get("udp_port", -1)) == MARKER_PORT
	check(marker_ok, "V18：落盘档含退出前内存变更（udp_port=%d——兜底保存语义，内存态不丢）" % MARKER_PORT)

	# ---- F. toast_center 中央盒退役（§3.4）：源码级 + 右上路径正常 ----
	var tc_src: String = FileAccess.get_file_as_string("res://scenes/shared/toast_center.gd")
	check(not tc_src.contains("_ensure_center_box") and not tc_src.contains("CENTER_TOP")
		and not tc_src.contains("ToastCenterTop"),
		"V-C6 §3.4：toast_center.gd 中央锚点盒源码级退役（_ensure_center_box/CENTER_TOP/ToastCenterTop 零残留）")
	check(not tc_src.contains("CENTER_HALF_W"),
		"V-C6 §3.4：中央盒几何常量零残留（单源迁 top_strip.gd，勿双写）")
	var tc: Node = (load("res://scenes/shared/toast_center.gd") as GDScript).new()
	add_child(tc)
	await process_frame
	check(tc.has_method("push") and tc.has_method("clear_all"),
		"V-C6 §3.4：push/clear_all 公开 API 保持不变（右上队列契约）")
	tc.call("push", "中央改道降级直推", "warn", 60.0, true)
	check_eq(tc.get_child_count(), 1, "V-C6 §3.4：push(centered=true) 直推 → 卡片落右上队列（中央盒退役后降级路径）")
	check(tc.get_parent().get_node_or_null("ToastCenterTop") == null,
		"V-C6 §3.4：父层无 ToastCenterTop 中央锚点盒节点（懒创建路径已删）")
	tc.call("clear_all")
	check_eq(tc.get_child_count(), 0, "V-C6 §3.4：clear_all 清空（API 语义保持）")

	# ---- G. TopStrip 跨态收起（审查①P2-4）：confirm 自动取消 / info 不受影响 / 防重入 ----
	var strip_f: Node = (load("res://scenes/shared/top_strip.gd") as GDScript).new()
	add_child(strip_f)
	await process_frame
	await process_frame
	strip_f.call("push_info", "跨态信息", 60.0)
	game_node.state_changed.emit(1, 4)   # 场景切换信号（直发，免场景加载副作用）
	check(strip_f.visible and strip_f.get("_mode") == "info",
		"P2-4：info 条不受场景切换影响（自有计时自灭）")
	_strip_ok = 0
	_strip_cancel = 0
	strip_f.call("push_confirm", "跨态确认",
		func() -> void: _strip_ok += 1,
		func() -> void: _strip_cancel += 1)
	game_node.state_changed.emit(1, 4)
	check(_strip_cancel == 1 and _strip_ok == 0,
		"P2-4：场景切换 confirm 常驻 → 自动按取消收起（on_canceled 恰 1 次、on_confirmed 零调用=零副作用）")
	check_eq(strip_f.visible, false, "P2-4：跨态收起后条隐藏")
	_strip_cancel = 0
	strip_f.call("push_confirm", "跨态确认二",
		func() -> void: _strip_ok += 1,
		func() -> void: _strip_cancel += 1)
	game_node.state_changed.emit(2, 4)
	game_node.state_changed.emit(4, 1)   # 同帧重复触发（场景切换瞬间重复信号）
	check_eq(_strip_cancel, 1, "P2-4：防重入——重复 state_changed 只生效一次（首次收起后 _mode 空判据守卫）")
	check_eq(_strip_ok, 0, "P2-4：跨态收起全程 on_confirmed 恒零（真退出回调不误触）")
	var ts_src: String = FileAccess.get_file_as_string("res://scenes/shared/top_strip.gd")
	check(ts_src.contains("Game.state_changed.connect(_on_game_state_changed)")
		and ts_src.contains("Game.state_changed.disconnect(_on_game_state_changed)"),
		"P2-4：top_strip.gd _ready 订阅/_exit_tree 退订 Game.state_changed（信号卫生）")
	strip_f.call("push_info", "收尾", 0.1)
	await create_timer(0.4).timeout
	strip_f.queue_free()
	spy.free()
	await process_frame

	# ---- 收尾：走查清档规范（快照还原 + load_game 重同步） ----
	_restore_save(pre_save)
	finish()

## 提取函数体文本（自 "func 名(" 起至下一个顶层 "\nfunc " 止）——供退出兜底源码序断言。
func _func_body(src: String, header: String) -> String:
	var start := src.find(header)
	if start < 0:
		return ""
	var next := src.find("\nfunc ", start)
	if next < 0:
		next = src.length()
	return src.substr(start, next - start)
