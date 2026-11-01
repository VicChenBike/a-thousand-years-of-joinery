extends "res://tests/test_base.gd"
## 批次 AA / W7（规格 §10「域 W7：长时间游玩后按钮全部失效」）判定用例。
## 用户症状：玩久后「锐眼」「对接」死活点不动、键鼠也无 hover 反应，但模块本身仍可交互；
## 通关后结算「退出」「下一关」同样点不动（§10.1）。
##
## 本件承接 §10.5 红测清单 R7-a ~ R7-f，全部**无摄像头**：合成事件经 `viewport.push_input`
## 注入 GUI 管线，物理态经 `Input.parse_input_event + flush_buffered_events` 注入 Input 单例
## （互斥门 `Input.is_mouse_button_pressed` 的读口）。
##
## 【无头实证，探针 `tests/w7_probe_engine_gui2_temp.gd`（临时件）】
##   A 段：`Input.parse_input_event` 鼠标事件**必须**再调 `Input.flush_buffered_events()` 才更新
##        Input 单例按下态（A2=false → A3=true）——本件 `_phys_only` 即此两步组合；
##   B 段：无头下 `parse_input_event` 的鼠标事件**不路由到 GUI 控件**（down=0），故「真实鼠标
##        的 GUI 事件」在本件用同一 `push_input` 通道显式注入（`_real_*` 族）——两条通道分别
##        对应互斥门读口与引擎 GUI 管线，不混用；
##   C/D/E 段：合成 press → **rect 外** motion → release → `pressed` **不发射**；rect 内 motion
##        或零 motion → `pressed` 正常发射——即根因 R7-1（BaseButton 收 rect 外 motion 即把
##        `pressuring_inside` 刷成 false）的无头实证，本件 R7-a 依此判定。
##
## 判定锚（§10.5）：
##   R7-a 真实 press → rect 外合成 motion → release → `pressed` **已发射**（并 hover 不被拽走）
##   R7-b armed two_down → 物理 LEFT down → two_up → 引擎**不残留按压**（抬起必达）
##   R7-c 物理按下期合成抬起送达（与 R7-b 同一断言面：`button_up` + `pressed`）
##   R7-d 卡死态 → N 帧后看门狗自动补发 release
##   R7-e 跨场景 → 零残留
##   R7-f 护栏：看门狗**不误清**合法手势按压 / 物理按压中不补发；W7-6 四钮恢复
##
## 存档纪律（tools/README_走查清档规范.md 六条）：本件末段实例化 level_scene（其 `_exit_tree`
## 兜底写档），故起测备份 user:// 四件组 + 清档前奏，终测经 finish() 统一还原并逐字节自检。

const LEVEL_SCENE := "res://scenes/level/level_scene.tscn"
const CURSOR_LAYER := "res://scripts/gesture_cursor_layer.gd"

# ===== 清档纪律（test_gesture_click_route 同款四件组；备份前缀 _w7p_ 防跨件互踩）=====
const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"
const BK_PREFIX := "user://_w7p_backup_"
const WATCHED: Array = [SAVE_PATH, FLAG_PATH, TMP_PATH, BAK_PATH]
const AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _pre_save_text: String = ""

var router: Variant          # 被测 Router 独立实例（autoload GestureRouter 不动）
var layer: Variant           # 真光标层（真 push_input 管线，非 MockLayer）
var btn: Button              # 探针按钮（按键信号计数 = 引擎按压态可观测量）
var game: Variant
var bridge: Variant
var vsz := Vector2(1152.0, 648.0)

var down_n := 0
var up_n := 0
var pressed_n := 0

# 按钮 rect=(100,100)-(300,160)：POS_IN 在内、POS_OUT 在外（rect 外 motion 判定用）
const POS_IN := Vector2(150.0, 130.0)
const POS_OUT := Vector2(700.0, 500.0)

# ---------------------------------------------------------------- 存档纪律
func _abs_path(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _del(p: String) -> void:
	var a: String = _abs_path(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _backup_user() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(SAVE_PATH)
	for p: String in WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_abs_path(p), _abs_path(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	# 规范第 6 条：先同步 free 测试挂载的非 autoload 节点（level._exit_tree 兜底写档落到测试域），
	# 再逐件还原 + load_game 重同步内存 + 逐字节等价断言。
	for c: Node in root.get_children():
		if not AUTOLOADS.has(String(c.name)):
			c.free()
	for p: String in WATCHED:
		_del(p)
		var bk: String = BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_abs_path(bk), _abs_path(p))
	var sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if sm != null:
		sm.load_game()
	var post: String = FileAccess.get_file_as_string(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|aa_pointer_stuck|files=%d" % WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

# ---------------------------------------------------------------- 事件工厂
func _norm(content: Vector2) -> Vector2:
	return content / vsz

func _content_of(norm: Vector2) -> Vector2:
	return norm * vsz

func _mk_btn(pos: Vector2, pressed_v: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed_v
	ev.position = pos
	ev.global_position = pos
	return ev

func _mk_motion(pos: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	return ev

## 物理态注入（互斥门读口）：parse + flush 才更新 Input 单例（探针 A 段实证）。
## **不** push 到 GUI（无头下本就不路由 GUI，探针 B 段实证）——GUI 侧只由 `_real_*` 显式注入。
func _phys_only(pressed_v: bool) -> void:
	Input.parse_input_event(_mk_btn(POS_IN, pressed_v))
	Input.flush_buffered_events()

## 「真实鼠标」GUI 事件注入：无头下真实鼠标事件进不了 GUI 管线，用同一 push_input 通道
## 等价注入（对应窗口模式下真实鼠标的位置/按压到达 GUI 的那一份）。
func _real_motion(pos: Vector2) -> void:
	root.push_input(_mk_motion(pos), true)

func _real_press(pos: Vector2) -> void:
	Input.parse_input_event(_mk_btn(pos, true))
	Input.flush_buffered_events()
	root.push_input(_mk_btn(pos, true), true)

func _real_release(pos: Vector2) -> void:
	Input.parse_input_event(_mk_btn(pos, false))
	Input.flush_buffered_events()
	root.push_input(_mk_btn(pos, false), true)

func _clear_counts() -> void:
	down_n = 0
	up_n = 0
	pressed_n = 0

## 段间复位：把探针按钮从「残留按压」拉回空闲，并清零计数。**每段开头调用**，保证各段互相
## 独立——上一段的红（按压残留）不会级联污染下一段的前置判定。
## 落点必须是 POS_IN：无头实证（探针 w7_probe_release_route_temp + 本件红态日志）——release
## 按「mouse_focus 优先、否则按抬起位命中」路由，而 `Input.parse_input_event` 的物理按下/抬起
## 会把 mouse_focus 挪成空（物理事件坐标系与 push_input 本地坐标系不一致、命中不到按钮），
## 故 rect 外抬起会落空、按钮继续残留按压；**按下位 press+release 往返**可无条件拉回空闲
## （press 先重建 mouse_focus，release 收口；幽灵 pressed 计数随即被本函数清零）。
func _reset_btn() -> void:
	_real_motion(POS_IN)
	root.push_input(_mk_btn(POS_IN, true), true)
	root.push_input(_mk_btn(POS_IN, false), true)
	_clear_counts()

func _on_btn_down() -> void:
	down_n += 1

func _on_btn_up() -> void:
	up_n += 1

func _on_btn_pressed() -> void:
	pressed_n += 1

## 手势光标落点（归一坐标，Router._content 消费）
func _cursor_move(pos: Vector2) -> void:
	router.call("_dispatch", {"type": "cursor_move", "side": "left", "pos": _norm(pos)})

func _two_down(pos: Vector2) -> void:
	router.call("_on_two_down", {"side": "left", "pos": _norm(pos), "confirm_frames": 2})

func _two_up(pos: Vector2) -> void:
	router.call("_on_two_up", {"side": "left", "pos": _norm(pos)})

## 制造卡死态：合成按下已推 → 抬起期推送通道缺席（_cursor_layer=null）→ 抬起丢失。
## 结果=引擎仍持 LEFT、物理未按、Router 标志已清（_on_two_up 先清 armed 再推抬起）——
## 即 §10.6 风险 2 描述的三条件齐备态。
func _make_stuck() -> void:
	_cursor_move(POS_IN)
	_two_down(POS_IN)
	router.set_cursor_layer(null)
	_two_up(POS_IN)
	router.set_cursor_layer(layer)

func _four_btns(lv: Node) -> Array:
	var out: Array = []
	for p: String in ["TopBar/Buttons/EyeButton", "TopBar/Buttons/JoinButton",
			"TopBar/Buttons/ExitButton", "ExitReplayButton"]:
		out.append(lv.get_node_or_null(p))
	return out

func _all_disabled(lv: Node) -> bool:
	for b: Variant in _four_btns(lv):
		if b == null or not bool((b as Button).disabled):
			return false
	return true

func _all_enabled(lv: Node) -> bool:
	for b: Variant in _four_btns(lv):
		if b == null or bool((b as Button).disabled):
			return false
	return true

func _make_level() -> Node:
	var inst: Node = (load(LEVEL_SCENE) as PackedScene).instantiate()
	inst.call("set_context", {"chapter": 1})
	add_child(inst)
	await process_frame
	await process_frame
	return inst

# ---------------------------------------------------------------- 主流程
func _initialize() -> void:
	print("== test_aa_pointer_stuck ==")
	_backup_user()
	var save: Variant = get_root().get_node("SaveManager")
	bridge = get_root().get_node("GestureBridge")
	game = get_root().get_node("Game")
	# 清档前奏（规范第 3 条）：末段实例化 level_scene 前把真实档清零并重同步内存
	var sp: String = ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(sp):
		DirAccess.remove_absolute(sp)
	save.load_game()
	bridge._set_state(1)   # READY
	game.goto_state(game.State.MAIN_MENU)   # 语义区 none → _click_zone 恒 true（armed 可达）

	router = load("res://autoload/gesture_router.gd").new()
	router.name = "GestureRouterW7Probe"
	add_child(router)
	await process_frame            # --script 实证⑥：树激活后 _ready/_setup 才完成接线
	bridge._set_state(1)
	router._setup()
	layer = load(CURSOR_LAYER).new()
	layer.name = "W7CursorLayer"
	add_child(layer)
	router.set_cursor_layer(layer)

	btn = Button.new()
	btn.position = Vector2(100.0, 100.0)
	btn.size = Vector2(200.0, 60.0)
	btn.text = "W7"
	root.add_child(btn)
	btn.button_down.connect(_on_btn_down)
	btn.button_up.connect(_on_btn_up)
	btn.pressed.connect(_on_btn_pressed)
	await process_frame
	await process_frame
	vsz = get_root().get_visible_rect().size
	check(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
		"前置：Input 单例物理左键为释放态（干净起测）")

	# ================= R7-a / W7-2：真实按压期间冻结合成 motion =================
	_reset_btn()
	_real_motion(POS_IN)
	check(root.gui_get_hovered_control() == btn, "前置：真实鼠标移到按钮上 → hover 命中按钮")
	_real_press(POS_IN)                     # 真实按下（GUI + Input 单例双通道）
	check(down_n == 1, "前置：真实按下 → 按钮 button_down 恰一次")
	check(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "前置：互斥门读口=物理按下态")
	# 手势光标在按钮**外**：修复前每个非抖动帧都推 synth_motion → rect 外 motion 打掉按压与 hover
	_cursor_move(POS_OUT)
	check(root.gui_get_hovered_control() == btn,
		"W7-2/R7-a①：真实按压期冻结合成 motion → hover 不被手势光标拽走")
	_real_release(POS_IN)
	check_eq(pressed_n, 1, "R7-a②：真实 press → rect 外合成 motion → release → pressed 已发射")
	check_eq(up_n, 1, "R7-a③：按钮 button_up 恰一次（按压态正常收尾）")

	# ================= R7-b/R7-c / W7-1：抬起豁免互斥门（抬起必达）=================
	_reset_btn()
	_cursor_move(POS_IN)
	_two_down(POS_IN)                        # armed 合成按下 → 落到按钮上
	check_eq(down_n, 1, "前置：armed 合成按下 → 按钮 button_down 恰一次")
	# 「抬起瞬间物理左键恰好按下」——物理按下建模为**压在同一按钮上**（用户症状原文即「鼠标移到
	# 按钮上却点不动」，两个指针同在按钮是常态）。须走 _real_press（parse 置互斥门 + push 置引擎
	# mouse_focus）：无头下裸 `Input.parse_input_event` 的坐标系与 push_input 本地坐标系不一致、
	# 命中不到按钮并会把 mouse_focus 改写成空（探针 w7_probe_phys_focus_temp V4 实证），那是
	# 与本修复无关的夹具侧失真，不能让它顶替红灯。
	_real_press(POS_IN)
	check(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "前置：互斥门读口=物理按下态")
	_two_up(POS_IN)
	# W7-1 红锚必须在 _real_release **之前**判（护栏真实性探针 w71_release_gate 首轮 GUARD
	# BROKEN 实证：锚放序后，合成抬起被丢时物理抬起仍会经 GUI 释放路径给按钮补 button_up
	# （up_n 被兜成 1），W7-1 单独破坏不判红=空转假绿）；序前判=纯合成抬起锚，抬起必达语义直达。
	check_eq(up_n, 1, "W7-1/R7-b：物理按下期合成抬起**仍送达**（_real_release 前=纯合成抬起锚）")
	_real_release(POS_IN)
	check_eq(up_n, 1, "R7-b 收尾：抬起恰一次（合成送达后物理抬起零重复补发）")
	check_eq(pressed_n, 1, "R7-c：抬起送达且按钮 pressed 正常发射（非幽灵丢弃）")
	check(not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "收尾：物理左键已释放")

	# ================= R7-d / W7-3：卡死看门狗（三条件判据）======================
	_reset_btn()
	_make_stuck()                            # 引擎持 LEFT + 物理未按 + Router 标志全清
	check_eq(down_n, 1, "前置：卡死态成立（合成按下已推）")
	check_eq(up_n, 0, "前置：抬起丢失（推送通道缺席）→ 按钮残留按压")
	for i: int in 45:
		await process_frame                  # 看门狗按帧计数（N=30【暂定值·待用户复验】）
	check_eq(up_n, 1, "W7-3/R7-d：看门狗三条件齐备 → N 帧后强制补发 release 清引擎按压")
	var pressed_after_wd: int = pressed_n
	check_eq(pressed_after_wd, 0, "W7-3 防幽灵点击：强制 release 落 rect 外 → 不触发 pressed")

	# ---- R7-f 护栏①：合法手势按压中（Router 标志在）→ 看门狗不得误清 ----
	_reset_btn()
	_cursor_move(POS_IN)
	_two_down(POS_IN)                        # armed=true（合法手势长按）
	check_eq(down_n, 1, "护栏①前置：手势合成按下已推")
	for i: int in 45:
		await process_frame
	check_eq(up_n, 0, "R7-f 护栏①：手势按压中（_menu_click_armed 在）→ 看门狗零补发（不误清合法长按）")
	_two_up(POS_IN)                          # 收尾（层在场 → 抬起正常送达）
	check_eq(up_n, 1, "R7-f 护栏①收尾：手势抬起正常送达")

	# ---- R7-f 护栏②：物理左键仍按住 → 看门狗不得补发；物理释放后才补发 ----
	_reset_btn()
	_make_stuck()
	check_eq(up_n, 0, "护栏②前置：卡死态成立")
	_phys_only(true)
	for i: int in 45:
		await process_frame
	check_eq(up_n, 0, "R7-f 护栏②：物理左键仍按住（三条件缺一）→ 看门狗零补发")
	_phys_only(false)
	for i: int in 45:
		await process_frame
	check_eq(up_n, 1, "W7-3：物理释放后三条件齐备 → N 帧内补发 release 清理")

	# ---- R7-g / 批次 AA 回修5（W7-P3-4）：物理按压中 reset_runtime 不强制释放（防御深度）----
	# 闭合「陈旧台账 + 真实按压中 + 场景切换」同帧叠加窗：物理按压中强制释放的三步序列
	# （按下位补按下→屏外 motion→抬起）会与真实按压事件同帧叠加打乱引擎 focus；物理按压中
	# 跳过，台账保持真，待物理抬起后由 W7-3 看门狗兜底（既有护栏②链路）。
	_reset_btn()
	_cursor_move(POS_IN)
	_two_down(POS_IN)                        # 合法手势按压在册（台账真）
	check_eq(down_n, 1, "R7-g 前置：合成按下已推（台账真）")
	_phys_only(true)                         # 物理左键按下（叠加窗构造）
	check(Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT), "R7-g 前置：互斥门读口=物理按下态")
	router.call("reset_runtime")             # 场景切换同款 reset 通路
	# 判据锚=台账真值（强制释放的第一效果即清账，确定性判读；按压事件本身经 parse 通道
	# 会使 push_input 抬起落空〔头注探针实证〕，up_n 非可靠观测量故不作锚）。
	check(bool(router.get("_synth_left_held")),
		"回修5/R7-g：物理按压中 reset_runtime 不强制释放（台账保持真待看门狗兜底；红态=强制释放清账）")
	_phys_only(false)
	router.call("reset_runtime")             # 物理释放后 → 强制释放可达（正常清态收口）
	check(not bool(router.get("_synth_left_held")),
		"回修5/R7-g 收尾：物理释放后 reset_runtime 强制释放照常清账（防御深度不误伤正常清态）")

	# ---- R7-h / 批次 AA 回修5（W7-P3-5）：物理按压中探测 motion 不推送（W7-2 同门防御深度）----
	# _hovered_ui_interactive 的探测 push 此前无 W7-2 门（靠唯一调用链传递性覆盖）；补门防
	# 未来新增调用方破防——物理按压中探测判定沿用真实 hover，不推送合成 motion。
	_reset_btn()
	_cursor_move(POS_OUT)                    # 手势光标在按钮外（_cursor_seen 置位；物理未按推送照常）
	_phys_only(true)                         # 先置互斥门读口（parse 事件会重置引擎 focus，hover 判定随后建立）
	_real_motion(POS_IN)                     # 真实鼠标悬停按钮（GUI hover=btn；真实运动不经互斥门）
	check(root.gui_get_hovered_control() == btn, "R7-h 前置：hover 命中按钮")
	var inter_h: bool = bool(router.call("_hovered_ui_interactive", "left"))
	check(inter_h,
		"回修5/R7-h：物理按压中探测 motion 不推送 → 判定沿用真实悬停=true（红态=探测 push 拽走 hover 后 false）")
	check(root.gui_get_hovered_control() == btn,
		"回修5/R7-h②：探测 motion 未推送（hover 保持按钮；红态=synth motion 把 hover 拽向 POS_OUT）")
	_phys_only(false)

	# ================= R7-e / W7-4：场景切换清引擎 GUI 残留按压 ==================
	_reset_btn()
	_make_stuck()
	check_eq(up_n, 0, "前置：卡死态成立（跨场景存活风险）")
	game.goto_state(game.State.CATALOG)
	await process_frame
	check_eq(up_n, 1, "W7-4/R7-e：场景切换（goto_state → Router reset 通路）→ 引擎残留按压清零")
	game.goto_state(game.State.MAIN_MENU)
	await process_frame

	# ================= W7-6：_begin_success 四钮禁用 + 恢复路径 ==================
	var lv1: Node = await _make_level()
	check(lv1 != null, "W7-6 前置：关卡场景实例化成功")
	if lv1 != null:
		check(_all_enabled(lv1), "W7-6 前置：新建场景四钮（锐眼/对接/退出/重玩退出）默认可点")
		lv1.call("_begin_success")
		check(_all_disabled(lv1), "W7-6①：_begin_success 一次性锁四钮（现状语义保持）")
		var has_restore: bool = lv1.has_method("restore_play_buttons")
		if has_restore:
			lv1.call("restore_play_buttons")
		check(has_restore and _all_enabled(lv1),
			"W7-6②：显式恢复入口 restore_play_buttons() → 四钮恢复可点（同场景重入防踩雷）")
		lv1.free()
	var lv2: Node = await _make_level()
	if lv2 != null:
		check(_all_enabled(lv2), "W7-6③：场景重建 → 四钮天然恢复可点（护栏）")
		lv2.free()

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_phys_only(false)
	finish()
