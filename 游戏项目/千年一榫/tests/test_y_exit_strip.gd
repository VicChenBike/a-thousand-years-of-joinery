extends "res://tests/test_base.gd"
## 批次 Y（Y-A2/Y-A3，spec §2-②③拍板）：倒数顶部条 + 手势倒数专属退出入口——TDD 红测先行。
## 段 1（Y-A2）：gesture_exit_dialog 顶部居中长条形态（屏幕正中卡片/Dim 遮罩退役；
##   TopStrip 同款视觉语言；正文 spec 口径「还需翻转 N 次」）。
## 段 2（Y-A3）：关卡内倒数计 0 → Router LEVEL 分支改走 **手势倒数专属退出入口**
##   level_scene.gesture_exit_to_menu（直连 MAIN_MENU+flush_checkpoint 存档），不再弹
##   「返回主菜单？」二次确认；手动 TopBar _on_exit_pressed 二次确认回归不变（分流判据）。
## 清档纪律沿用 test_x_gesture_remap（真 level_scene + user:// 备份还原，独立前缀 y3es）。

const SCENE_PATH := "res://scenes/level/level_scene.tscn"
const MISS := Vector3i(-1, -1, -1)

# ===== 清档纪律（test_x_gesture_remap 同款，独立前缀 y3es）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_y3es_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _pre_save_text: String = ""

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _backup_user() -> void:
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	for c: Node in root.get_children():
		if not DISC_AUTOLOADS.has(String(c.name)):
			c.free()
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(_disc_abs(p)):
			DirAccess.remove_absolute(_disc_abs(p))
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(_disc_abs(bk)):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(_disc_abs(bk))
	var real_sm: Node = root.get_node_or_null("SaveManager")
	if real_sm != null:
		real_sm.load_game()
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")

func finish() -> void:
	_restore_user()
	super.finish()

# ==================== 段 1（Y-A2）：倒数顶部条形态 ====================
func _seg1_dialog() -> void:
	var ed: Node = (load("res://scenes/shared/gesture_exit_dialog.tscn") as PackedScene).instantiate()
	add_child(ed)
	await process_frame
	await process_frame
	check(ed.get_node_or_null("Dim") == null, "Y-A2：全屏 Dim 遮罩退役（TopStrip 同款无遮罩长条）")
	var card: Control = ed.get_node_or_null("Card") as Control
	check(card != null and card is PanelContainer, "Y-A2：Card=PanelContainer 顶部条载体在位")
	check(is_equal_approx(float(card.get("anchor_top")), 0.0) and is_equal_approx(float(card.get("anchor_left")), 0.5),
		"Y-A2：顶部居中锚点（anchor_top=0/anchor_left=0.5）")
	check(is_equal_approx(float(card.get("offset_top")), 70.0),
		"Y-A2：顶部偏移=70（TopStrip TOP_OFFSET 同款样式语言）")
	check(is_equal_approx(float(card.get("anchor_bottom")), 0.0),
		"Y-A2：屏幕正中卡片退役（旧 anchor 0.5/0.5 offset ±64）")
	ed.call("show_countdown", 3)
	check(ed.visible, "Y-A2：首显可见（Tracker 当帧 emit 驱动）")
	var body: Label = ed.get_node("Card/VBox/Body") as Label
	check_eq(String(body.text), "还需翻转 3 次", "Y-A2：首显正文「还需翻转 3 次」（spec 文案口径）")
	ed.call("update_countdown", 2)
	check_eq(String(body.text), "还需翻转 2 次", "Y-A2：刷新正文「还需翻转 2 次」")
	check(body.autowrap_mode != TextServer.AUTOWRAP_OFF, "Y-A2：正文 autowrap（超宽折行不溢出）")
	await create_timer(0.45).timeout
	check(float(card.position.y) <= 71.0, "Y-A2：滑入动效终值=顶部目标位（实测 %.1f）" % float(card.position.y))
	ed.call("close_countdown")
	check(not ed.visible, "Y-A2：close_countdown 收起")
	ed.queue_free()
	await process_frame

# ==================== 段 2（Y-A3）：倒数计 0 直达主菜单（专属退出入口） ====================
var router: Variant

func _seg2_level_exit() -> void:
	var bridge: Node = get_root().get_node("GestureBridge")
	var game: Node = get_root().get_node("Game")
	bridge._set_state(1)
	router = load("res://autoload/gesture_router.gd").new()
	add_child(router)
	await process_frame
	bridge._set_state(1)
	router._setup()
	var inst: Node = (load(SCENE_PATH) as PackedScene).instantiate()
	check(inst != null and inst.has_method("gesture_exit_to_menu"),
		"Y-A3 前置：level_scene 手势倒数专属退出入口方法在位（与 _on_exit_pressed 不共用）")
	inst.call("set_context", {"chapter": 1})
	add_child(inst)
	game._current_scene = inst
	await process_frame
	await process_frame
	game.goto_state(game.State.LEVEL)
	await process_frame
	await process_frame
	# 探得剩余格并挖除一格（挖除断点脏标 → flush_checkpoint 落盘可断言）
	var cont: SubViewportContainer = inst.get_node_or_null("MainView/ViewportContainer") as SubViewportContainer
	var vps: SubViewport = inst.get_node_or_null("MainView/ViewportContainer/SubViewport") as SubViewport
	var cam: Camera3D = inst.get_node_or_null("MainView/ViewportContainer/SubViewport/Camera3D")
	var c7: Variant = MISS
	var x := vps.size.x * 0.5
	while x < vps.size.x and c7 == MISS:
		var c: Variant = inst.call("get_cell_hit", cam.project_ray_origin(Vector2(x, vps.size.y * 0.5)),
			cam.project_ray_normal(Vector2(x, vps.size.y * 0.5)))
		if c != MISS:
			c7 = c
		x += 8.0
	check(c7 != MISS, "Y-A3 前置：探得剩余格")
	inst.call("delete_cell", c7)
	var pre_save: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	# ---- 手动 TopBar 二次确认回归（分流判据：现状保持）----
	inst.call("_on_exit_pressed")
	check(int(inst.get("_pending_exit_state")) == int(game.State.MAIN_MENU),
		"Y-A3：手动 TopBar 退出 → 仍走二次确认（_pending_exit_state 挂起主菜单；现状不变）")
	check(int(game.current_state()) == int(game.State.LEVEL),
		"Y-A3：手动退出确认前不切状态（二次确认现状回归）")
	inst.call("_on_exit_canceled")
	check(int(inst.get("_pending_exit_state")) == -1, "Y-A3：手动确认取消 → 挂起作废（零副作用）")
	# ---- 手势倒数计 0：专属入口直达 ----
	var t: Variant = router.get("_tracker")
	t.notify_flip(1000.0)
	t.notify_flip(1000.2)
	t.notify_flip(1000.4)
	t.notify_flip(1000.6)   # 计 0 → exit_confirmed → LEVEL 分支专属入口
	check_eq(int(game.current_state()), int(game.State.MAIN_MENU),
		"Y-A3：倒数计 0 直连回主菜单（不弹二次确认——旧码 _on_exit_pressed 只挂起不切状态=红灯）")
	check(int(inst.get("_pending_exit_state")) == -1,
		"Y-A3：手势倒数全程未触碰二次确认挂起（专属入口与手动口不共用分流判据）")
	var post_save: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check(post_save != pre_save and post_save.contains("deleted_cells"),
		"Y-A3：专属入口主动存档（flush_checkpoint 落盘挖除断点；存档时间戳/内容更新）")
	# 收尾卫生：断开桥 feed 连接（防 freed 回调）
	if bridge != null and bridge.gesture_state_received.is_connected(router.feed):
		bridge.gesture_state_received.disconnect(router.feed)
	router.queue_free()
	await process_frame

func _initialize() -> void:
	print("== test_y_exit_strip ==")
	_backup_user()
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(_disc_abs(p)):
			DirAccess.remove_absolute(_disc_abs(p))
	get_root().get_node("SaveManager").call("load_game")
	await _seg1_dialog()
	await _seg2_level_exit()
	finish()
