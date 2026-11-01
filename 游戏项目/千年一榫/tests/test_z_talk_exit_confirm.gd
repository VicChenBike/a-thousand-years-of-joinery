extends "res://tests/test_base.gd"
## 批次 Z Z3（spec §3-5 验收⑥，用户拍板）：**消除手势误触发静默吞掉对话**红测——
## TALK 态的退出确认改为**先弹 TopStrip 确认条**（文案「确定跳过本段剧情？」+「确认」「取消」），
## 用户确认后才 _finish()；取消则继续对话。误触发（哪怕走完整个四翻倒数）不再静默跳过整段。
## 断言①：TALK 态**单次**四指同翻零跳过；**一轮四翻（倒数确认完成）也不产生跳过**——
##   不调 _finish、不离开 TALK、对话索引不动，且弹出确认条（红测：现状直接 _finish 静默跳过）。
## 断言②：完整确认流程（四翻 → 确认条 → 点「确认」）仍可跳过 → _finish → LEVEL{chapter:1}。
## 断言③：点「取消」→ 对话继续（状态/索引不动）、_finish 未被调用、条收起。
## 附加锁：确认条文案常量逐字、按钮「确认」「取消」在位可用；四翻后 tracker._done 复位
##   （批次 W P1-1 既有契约保持，可再来一轮）；LEVEL 态手势退出直达主菜单**零改动**（拍板）。
## 驱动：真实 gesture_router 新实例 + 真实 TopStrip（确认/取消为真按钮 pressed.emit，
##   无头鼠标 GUI 命中不可用）+ 真实 talk_scene（Game.attach 容器 → goto_state(TALK) 生产路由）。
## 清档纪律：goto_state(TALK/LEVEL) 触发自动穿戴与场景写档 → user:// 备份还原（前缀 ztec）。

const TALK_SCENE := "res://scenes/dialog/talk_scene.tscn"
const ROUTER := "res://autoload/gesture_router.gd"
const STRIP := "res://scenes/shared/top_strip.gd"
const GUARD_TEXT := "确定跳过本段剧情？"
const ST_TALK := 3
const ST_LEVEL := 4

# ===== 清档纪律（tools/README_走查清档规范.md）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_ztec_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _pre_save_text: String = ""

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _disc_del(p: String) -> void:
	var a: String = _disc_abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _backup_user() -> void:
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))

func _restore_user() -> void:
	for c: Node in root.get_children():
		if not DISC_AUTOLOADS.has(String(c.name)):
			c.free()
	for p: String in DISC_WATCHED:
		_disc_del(p)
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|ztec|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

## 一轮四翻（间隔均 <tracker 超时；时间显式注入，test_gesture_exit_tracker 同手法）
func _four_flips(t: Variant, base: float) -> void:
	t.notify_flip(base)
	t.notify_flip(base + 0.2)
	t.notify_flip(base + 0.4)
	t.notify_flip(base + 0.6)

func _initialize() -> void:
	print("== test_z_talk_exit_confirm ==")
	_backup_user()
	var game: Node = root.get_node("Game")
	var bridge: Node = root.get_node("GestureBridge")
	bridge._set_state(1)

	# ---- 0. 文案常量逐字（文件头部单点；缺键 → "" 必红）----
	var rcmap: Dictionary = (load(ROUTER) as GDScript).get_script_constant_map()
	check_eq(String(rcmap.get("TALK_SKIP_TEXT", "")), GUARD_TEXT,
		"常量：TALK_SKIP_TEXT==「确定跳过本段剧情？」（实测「%s」）" % str(rcmap.get("TALK_SKIP_TEXT", "")))

	# ---- 环境：真实 TopStrip + 容器 + 生产路由进 TALK ----
	var strip: Node = (load(STRIP) as GDScript).new()
	add_child(strip)
	await process_frame
	game.call("attach_strip", strip)
	var container: Control = Control.new()
	container.size = Vector2(1152, 648)
	add_child(container)
	game.attach(container, null)
	game.goto_state(int(game.State.TALK), {"mode": "after_level", "chapter": 1})
	await process_frame
	await process_frame
	check_eq(int(game.current_state()), ST_TALK, "前置：TALK 态（对话进行中）")
	var talk: Node = game.get_current_scene()
	check(talk != null and talk.has_method("_finish"), "前置：当前场景=真实 talk_scene（_finish 在位）")
	if talk == null:
		finish()
		return

	# ---- 真实 gesture_router 新实例 ----
	var router: Node = (load(ROUTER) as GDScript).new()
	add_child(router)
	await process_frame
	router.call("_setup")
	var confirmed_cnt: Array = []
	router.exit_confirmed.connect(func() -> void: confirmed_cnt.append(true))
	var t: Variant = router.get("_tracker")
	var idx0: int = int(talk.get("_index"))

	# ==================== ① 单次同翻：零跳过（锁） ====================
	t.notify_flip(100.0)
	check_eq(confirmed_cnt.size(), 0, "①：单次四指同翻不触发 exit_confirmed（倒数未满）")
	check_eq(int(game.current_state()), ST_TALK, "①：单次同翻后仍在 TALK（对话未被吞）")
	check_eq(int(talk.get("_index")), idx0, "①：单次同翻后对话索引不动")

	# ==================== ① 一轮四翻：不跳过 + 弹确认条（红测：现状直接 _finish） ====================
	_four_flips(t, 200.0)
	check_eq(confirmed_cnt.size(), 1, "①：一轮四翻 → exit_confirmed 恰一次（router 转发契约保持）")
	check_eq(int(game.current_state()), ST_TALK,
		"①：四翻确认后**不跳过**、仍在 TALK（红测：现状 _finish 直跳对话结束/进关卡）")
	check_eq(int(talk.get("_index")), idx0, "①：四翻确认后对话索引不动（未被静默吞掉）")
	check_eq(String(strip.get("_mode")), "confirm", "①：弹出 TopStrip 确认条（_mode==confirm；红：现状无条）")
	var msg: Variant = strip.get("_msg_label")
	check(msg is Label and String((msg as Label).text) == GUARD_TEXT,
		"①：确认条文案逐字==「确定跳过本段剧情？」（实测「%s」）" % str((msg as Label).text if msg is Label else ""))
	var ok_btn: Node = strip.get_node_or_null("Row/BtnRow/OkButton")
	var cancel_btn: Node = strip.get_node_or_null("Row/BtnRow/CancelButton")
	check(ok_btn is Button and (ok_btn as Button).visible, "①：「确认」按钮在位可用")
	check(cancel_btn is Button and (cancel_btn as Button).visible, "①：「取消」按钮在位可用")
	if ok_btn is Button:
		check_eq((ok_btn as Button).text, "确认", "①：确认钮文案逐字「确认」")
	if cancel_btn is Button:
		check_eq((cancel_btn as Button).text, "取消", "①：取消钮文案逐字「取消」")
	check(bool(t.get("_done")) == false, "①附加锁：四翻后 tracker._done 已复位（P1-1 契约保持，可再来一轮）")

	# ==================== ③ 点「取消」→ 对话继续、_finish 未被调用 ====================
	# _finish 未被调用的判据：after_level(1) 的 _finish 必路由（有效章→LEVEL / 映射外→MAIN_MENU），
	# 故「状态仍 TALK + 累引不动」⇔ _finish 未执行（零副作用语义等价断言）。
	if cancel_btn is Button:
		(cancel_btn as Button).pressed.emit()
	check_eq(String(strip.get("_mode")), "", "③：取消 → 确认条收起")
	check_eq(int(game.current_state()), ST_TALK, "③：取消后对话继续（仍在 TALK）")
	check_eq(int(talk.get("_index")), idx0, "③：取消后对话索引不动（_finish 未被调用——调用必路由 LEVEL）")
	check(not bool(strip.visible) or String(strip.get("_mode")) != "confirm", "③：取消后条不再处于 confirm 态")

	# ==================== ② 再来一轮四翻 → 点「确认」→ 跳过（完整流程仍可跳过） ====================
	confirmed_cnt.clear()
	_four_flips(t, 300.0)
	check_eq(confirmed_cnt.size(), 1, "②：第二轮四翻再次触发（tracker 复位可达）")
	check_eq(String(strip.get("_mode")), "confirm", "②：确认条再次弹出")
	check_eq(int(game.current_state()), ST_TALK, "②：确认条待命期间不跳过")
	if ok_btn is Button:
		(ok_btn as Button).pressed.emit()
	await process_frame
	check_eq(int(game.current_state()), ST_LEVEL, "②：点「确认」→ _finish 跳过 → LEVEL（after_level(1) 语义）")
	check_eq(int(game.context().get("chapter", -1)), 1, "②：跳过后 ctx.chapter==1")
	check_eq(String(strip.get("_mode")), "", "②：确认后确认条收起")

	# ==================== 附加锁：LEVEL 态手势退出直达主菜单零改动（用户拍板） ====================
	game.goto_state(int(game.State.LEVEL), {"chapter": 1})
	await process_frame
	await process_frame
	check_eq(int(game.current_state()), ST_LEVEL, "附加前置：LEVEL 态")
	var idx_lv: int = confirmed_cnt.size()
	_four_flips(t, 400.0)
	check_eq(confirmed_cnt.size(), idx_lv + 1, "附加：LEVEL 四翻仍触发 exit_confirmed（转发契约）")
	check_eq(int(game.current_state()), 1,
		"附加锁：LEVEL 态手势退出**直达主菜单**、不弹确认条（既有语义零改动；实测 state=%d）" % int(game.current_state()))
	check_eq(String(strip.get("_mode")), "", "附加锁：LEVEL 分支零确认条")

	# 收尾卫生（queue_free 后须等一帧离场，防 _restore_user 二次 free；test_w_gesture_state 同款）
	if bridge != null and bridge.gesture_state_received.is_connected(router.feed):
		bridge.gesture_state_received.disconnect(router.feed)
	router.queue_free()
	await process_frame
	game.call("attach_strip", null)
	await process_frame
	finish()
