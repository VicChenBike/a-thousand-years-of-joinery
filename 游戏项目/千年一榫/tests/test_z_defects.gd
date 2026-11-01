extends "res://tests/test_base.gd"
## 批次 Z（Z6 波，spec §6）：全项目 28 条缺陷清账——P1×5 红测 + 选定 P2 修复项断言 + 回归断言。
## TDD：本文件先于修复落地（红态证据 AI工作记录/批次Z_走查_20260924/ze_tdd_red.txt；绿态 ze_tdd_green.txt）。
## 覆盖段：
##   S1  P1-1 拖窗白名单：PointCloudViewer 根豁免 + ModelDragArea 接线（读码）+ 空白 Label 仍可拖窗回归；
##   S2  P1-2 无边框最大化综合真值：drag_gate_closed 真值表 + main.gd 接线（读码）；
##   S3  P1-3 连点两次退出确认：第二轮挂起态不被旧 cancel 清空 + 取消回归；
##   S4  P2-2 手势合成事件标记：synth_* 事件带 gesture_synth meta + main 拖窗分支跳过（读码）
##       + P3-4 光标层 > Glow 层（同 index 消歧）；
##   S5  P2-1 图鉴全屏：FS_LAYER_ID=62 + 全屏期 exit_flip 不推进倒数（dispatch 行为红测）；
##   S6  P2-6 掌推拉三级回退：active 空 → 光标命中 → 首个可缩放面板（红测=直接推拉失效）；
##   S7  P2-7 SETTLE 手势退出：接通结算退出钮同链路（红测=else 静默）；
##   S8  P2-4 回归断言：8s 回落旧链 _fallback_camera_open 已退役（Z-B 根除无限轮换）；
##   S9  P2-10 confirm 期 info 排队：收起后补播最新一条（红测=丢弃）；
##   S10 P1-5 商店僵尸确认条：真实购买链挂起 → 关店 → 条收起 + 后续 info 正常（红测）；
##   S11 P2-9 dismiss_confirm 不误杀：关设置面板不收走外来确认 + 自有确认照常收（红测+对照）；
##   S12 P2-8 HUD 即时重排：Game.overlay_changed 信号 + 开/关覆盖层当帧重排（红测=0.5s 轮询）；
##   S13 P2-11 fps 子列不压设备行：帧率列锚菜单底缘下方 + 右安全边距 ≥14（红测=压行）；
##   S14 P1-4 回归断言（Z-B 已修，不重复改码）：Q3 → 下拉点设备 → 变亮 + OPENING + 落档。
## 纪律：无头零真拉起（autoload 桥前置注入高位 _udp_port_override 防触 9876/9877/9878）；
## user:// 起测备份、终测还原逐字节等价（test_fix_window_scale 同款清档纪律，前缀 zzd）；
## 新增 API 一律 has_method/has_signal/字面量防解析——红态须逐条出 FAIL 而非整文件中止。

const WM_GD := "res://scripts/window_manager.gd"
const MAIN_GD := "res://scenes/main.gd"
const LEVEL_GD := "res://scenes/level/level_scene.gd"
const CATALOG_GD := "res://scenes/catalog/catalog_scene.gd"
const SETTINGS_GD := "res://scenes/settings/settings_panel.gd"
const SHOP_GD := "res://scenes/shop/shop_panel.gd"
const SETTINGS_SCENE := "res://scenes/settings/settings_panel.tscn"
const PCV_GD := "res://scripts/point_cloud_viewer.gd"
const CURSOR_GD := "res://scripts/gesture_cursor_layer.gd"

# ===== 清档纪律（test_fix_window_scale 同款，前缀 zzd）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_zzd_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _pre_save_text: String = ""

# ---- 内联夹具：可缩放点云面板（P2-6 三级回退驱动）----
class _ZoomViewer extends Control:
	var zooms: Array = []
	func zoom_by(factor: float) -> void:
		zooms.append(factor)

class _CloudPanel extends Control:
	var viewer: Control = null
	func get_gesture_viewer() -> Control:
		return viewer
	func gesture_panel_rect() -> Rect2:
		return Rect2(global_position, size)

# ---- 内联夹具：SETTLE 退出探针（P2-7）----
class _SettleProbe extends Node:
	var called: bool = false
	func _on_settle_exit_pressed() -> void:
		called = true

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _disc_del(p: String) -> void:
	var a := _disc_abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _backup_user() -> void:
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			var bk := DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	for c: Node in root.get_children():
		if not DISC_AUTOLOADS.has(String(c.name)):
			c.free()
	for p: String in DISC_WATCHED:
		_disc_del(p)
		var bk := DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(_disc_abs(bk)):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(_disc_abs(bk))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()
	var post: String = ""
	if FileAccess.file_exists(DISC_SAVE_PATH):
		post = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|zzd|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_z_defects（批次Z Z6 波）==")
	_backup_user()
	root.size = Vector2i(1152, 648)   # 实证坑：钉设计视口（防无头 expand 撑大）
	var save: Variant = get_root().get_node("SaveManager")
	save.load_game()

	var wm: GDScript = load(WM_GD)
	var game: Variant = get_root().get_node("Game")
	var router: Variant = get_root().get_node("GestureRouter")
	var gb: Variant = get_root().get_node("GestureBridge")
	# 9876/9877/9878 真端口防触碰：autoload 桥注入高位 override（zcam 先例）
	gb.set("_udp_port_override", 29878)

	# ---- Game 覆盖层挂接 + 全局真实 TopStrip（P1-3/P1-5/P2-9/P2-10 共用）----
	var g_layer := CanvasLayer.new()
	g_layer.name = "ZzGameLayer"
	add_child(g_layer)
	var g_cont := Control.new()
	g_cont.name = "ZzSceneCont"
	add_child(g_cont)
	game.call("attach", g_cont, g_layer, null)
	var strip: Control = (load("res://scenes/shared/top_strip.gd") as GDScript).new()
	strip.name = "ZzTopStrip"
	add_child(strip)
	await process_frame
	game.call("attach_strip", strip)

	# ================= S1. P1-1 拖窗白名单 =================
	print("-- S1 P1-1 拖窗白名单 --")
	var viewer: Control = (load(PCV_GD) as GDScript).new()
	check(bool(wm.call("is_interactive_control", viewer)),
		"P1-1：PointCloudViewer 根=拖窗豁免（红态：无 meta → 按住点云拖动连带拖走窗口）")
	viewer.free()
	var lv_src := FileAccess.get_file_as_string(LEVEL_GD)
	check(lv_src.contains("drag.set_meta(\"interactive\", true)"),
		"P1-1：结算 ModelDragArea 创建处挂 meta interactive（读码接线断言；红态=缺失）")
	var plain := Label.new()
	check(not bool(wm.call("is_interactive_control", plain)),
		"P1-1 回归：普通空白 Label 不豁免 → 键鼠拖窗路径零回归")
	plain.free()
	var withm := Control.new()
	withm.set_meta("interactive", true)
	check(bool(wm.call("is_interactive_control", withm)),
		"P1-1 回归：meta('interactive') 祖先链白名单契约保持（talk_scene 先例）")
	withm.free()

	# ================= S2. P1-2 最大化综合真值 =================
	print("-- S2 P1-2 最大化综合真值 --")
	if wm.has_method("drag_gate_closed"):
		check_eq(bool(wm.call("drag_gate_closed", DisplayServer.WINDOW_MODE_WINDOWED, true, false)), true,
			"P1-2：无边框最大化（WindowButtons._maxed）→ 拖窗/16:9 门关闭（红态=恒 WINDOWED 放行）")
		check_eq(bool(wm.call("drag_gate_closed", DisplayServer.WINDOW_MODE_WINDOWED, false, true)), true,
			"P1-2：装饰隐藏通道（RoundedFrame._decoration_force_hidden 标志，修复4 改读）→ 门关闭")
		check_eq(bool(wm.call("drag_gate_closed", DisplayServer.WINDOW_MODE_WINDOWED, false, false)), false,
			"P1-2 回归：真窗口化且未最大化 → 拖窗可用（键鼠零回归）")
		check_eq(bool(wm.call("drag_gate_closed", DisplayServer.WINDOW_MODE_FULLSCREEN, false, false)), true,
			"P1-2 回归：全屏（mode 真实上报）→ 门关闭")
	else:
		check(false, "P1-2：WindowManager.drag_gate_closed 缺失（红态：无边框最大化恒报 WINDOWED，拖窗门/16:9 门失效）")
	var main_src := FileAccess.get_file_as_string(MAIN_GD)
	check(main_src.contains("drag_gate_closed"),
		"P1-2 接线：main._input 拖窗门与 enforce_aspect 走综合真值（读码断言；红态=仅判 window_get_mode）")
	# ---- 修复4（批次Z走查 P2 建议修）：drag_gate_closed 第三通道名实不符 ----
	# 旧态：第三通道入参=window_decoration_hidden(mode)=mode>=MAXIMIZED，与第一通道
	# mode!=WINDOWED 逻辑蕴含（mode≥2 ⟹ mode≠0）= 死通道，注释宣称「三通道纵深」不成立。
	# 处置=改读 RoundedFrame._decoration_force_hidden 显式标志（set_decoration_hidden 状态机
	# 真值：maximize_toggled 即时写 + 1s 轮询刷新，带历史粘性——覆盖不经 maximize_toggled
	# 的瞬时路径与 WindowButtons 缺位场景），使第三通道与 mode/_maxed 两通道真正正交。
	var rf_inst: Node = (load("res://scenes/shared/rounded_frame.gd") as GDScript).new()
	rf_inst.call("set_decoration_hidden", true)
	check_eq(bool(rf_inst.get("_decoration_force_hidden")), true,
		"修复4：set_decoration_hidden(true) → _decoration_force_hidden 置位（第三通道实源可安全获取）")
	rf_inst.call("set_decoration_hidden", false)
	check_eq(bool(rf_inst.get("_decoration_force_hidden")), false,
		"修复4：set_decoration_hidden(false) → 标志复位（防粘死）")
	check(main_src.contains("rf.get(\"_decoration_force_hidden\")"),
		"修复4 接线：main._window_non_windowed 第三通道改读 _decoration_force_hidden（读码断言，锚真实取值语句而非注释；红态=window_decoration_hidden(mode) 死通道）")
	rf_inst.free()

	# ================= S3. P1-3 连点两次退出确认 =================
	print("-- S3 P1-3 连点两次退出确认 --")
	var lv: Control = (load(LEVEL_GD) as GDScript).new()
	lv.call("_ask_exit", 1, "退出测试第一轮")
	check_eq(int(lv.get("_pending_exit_state")), 1, "P1-3：首轮 _ask_exit 挂起目标态=1")
	lv.call("_ask_exit", 2, "退出测试第二轮")
	check_eq(int(lv.get("_pending_exit_state")), 2,
		"P1-3：连点两次退出 → 第二轮挂起态=2（红态=-1：旧 cancel 补调把新目标写废，第二次「确认」空转）")
	strip.call("_on_cancel_pressed")   # 键鼠回归：确认条「取消」→ 挂起作废
	check_eq(int(lv.get("_pending_exit_state")), -1, "P1-3 回归：取消 → 挂起态作废（键鼠零回归）")
	check_eq(String(strip.get("_mode")), "", "P1-3 回归：取消后条收起")
	lv.free()

	# ================= S4. P2-2 合成事件标记 + P3-4 层序 =================
	print("-- S4 P2-2 合成事件标记 / P3-4 层序 --")
	var cl: CanvasLayer = (load(CURSOR_GD) as GDScript).new()
	cl.name = "ZzCursorLayer"
	add_child(cl)   # _ready 才写 layer → 入树取层序
	await process_frame
	check(int(cl.get("layer")) > 100,
		"P3-4：GestureCursorLayer 层序 > GlowLayer(100)（红态：同 index 100 → 前后序 non-deterministic）")
	var ev_btn: InputEvent = cl.call("synth_button", Vector2(10.0, 10.0), true, false)
	var ev_mot: InputEvent = cl.call("synth_motion", Vector2(10.0, 10.0))
	check(ev_btn.has_meta("gesture_synth") and ev_mot.has_meta("gesture_synth"),
		"P2-2：合成按下/移动事件带 gesture_synth 标记（红态：无判别 → 手势点击+动鼠标拖走窗口）")
	check(main_src.contains("event.has_meta(GestureCursorLayer.SYNTH_META)"),
		"P2-2 接线：main._input 拖窗分支显式跳过合成事件（读码断言=守卫行本体；红态=无判别）")
	cl.queue_free()
	await process_frame

	# ================= S5. P2-1 图鉴全屏层 + exit 门 =================
	print("-- S5 P2-1 图鉴全屏层与退出门 --")
	var cat_script: GDScript = load(CATALOG_GD)
	var fs_id := int(cat_script.get_script_constant_map().get("FS_LAYER_ID", -1))
	check_eq(fs_id, 62,
		"P2-1：FS_LAYER_ID=62（红态=90：黑底压 TopStrip63/HUD64，确认条看不见点不到、倒数黑屏照跑）")
	var cat_src := FileAccess.get_file_as_string(CATALOG_GD)
	check(cat_src.contains("func is_video_fullscreen"),
		"P2-1：catalog_scene 全屏谓词 is_video_fullscreen 在位（Router exit_flip 门消费点；红态=缺失）")
	var cat: Control = cat_script.new()   # 不入树：裸实例手动注全屏态
	var tracker: Variant = router.get("_tracker")
	var conf_hits: Array = []
	var conf_cb: Callable = func() -> void: conf_hits.append(true)
	router.exit_confirmed.connect(conf_cb)
	game.set("_current_scene", cat)
	game.set("_state", int(game.State.BOOT))   # 确认分流落静默 else 分支（防触发场景路由）
	# 对照：非全屏 → 四指同翻照常推进（键鼠/手势零回归）
	cat.set("_is_fullscreen", false)
	tracker.reset()
	conf_hits.clear()
	for i: int in 4:
		router.call("_dispatch", {"type": "exit_flip"})
	check_eq(conf_hits.size(), 1, "P2-1 回归：非全屏四指同翻 → exit_confirmed 恰一次")
	# 红测：全屏 → 不推进
	cat.set("_is_fullscreen", true)
	tracker.reset()
	conf_hits.clear()
	for i: int in 4:
		router.call("_dispatch", {"type": "exit_flip"})
	check_eq(conf_hits.size(), 0,
		"P2-1：全屏期四指同翻不推进退出倒数（红态：无 zone 门，倒数黑屏下照跑/确认条被 90 层压死）")
	router.exit_confirmed.disconnect(conf_cb)
	cat.free()
	game.set("_current_scene", null)

	# ================= S6. P2-6 掌推拉三级回退 =================
	print("-- S6 P2-6 掌推拉三级回退 --")
	game.set("_state", int(game.State.CATALOG))   # zone=cloud（无覆盖层）
	var zv := _ZoomViewer.new()
	var cp := _CloudPanel.new()
	cp.viewer = zv
	cp.position = Vector2(300.0, 200.0)
	cp.size = Vector2(400.0, 300.0)
	add_child(cp)
	cp.add_to_group("gesture_panel")
	router.set("_active_panel", null)
	# ① 光标命中面板（红态：active 空 → 静默 return，直接掌推拉 100% 失效）
	router.set("_last_cursor_pos", {"left": Vector2(400.0, 300.0)})
	var z0: int = (zv.zooms as Array).size()
	router.call("_do_zoom_factor", {"factor": 0.9})
	check((zv.zooms as Array).size() > z0,
		"P2-6①：active 空 + 光标在面板内 → 回退命中面板缩放（红态：直接掌推拉失效，须先二指点一下）")
	# ② 光标在面板外 → 回退首个可缩放面板
	router.set("_last_cursor_pos", {"left": Vector2(50.0, 50.0)})
	var z1: int = (zv.zooms as Array).size()
	router.call("_do_zoom_factor", {"factor": 1.1})
	check((zv.zooms as Array).size() > z1,
		"P2-6②：active 空 + 光标面板外 → 回退组内首个可缩放面板（红态：静默 return）")
	# ③ 回归：激活面板优先（既有路径零变化）
	router.set("_active_panel", cp)
	router.set("_last_cursor_pos", {"left": Vector2(50.0, 50.0)})
	var z2: int = (zv.zooms as Array).size()
	router.call("_do_zoom_factor", {"factor": 1.1})
	check((zv.zooms as Array).size() > z2, "P2-6③ 回归：激活面板优先缩放（既有路径零回归）")
	router.set("_active_panel", null)
	cp.queue_free()

	# ================= S7. P2-7 SETTLE 手势退出 =================
	print("-- S7 P2-7 SETTLE 手势退出 --")
	var probe := _SettleProbe.new()
	game.set("_state", int(game.State.SETTLE))
	game.set("_current_scene", probe)
	tracker.reset()
	router.call("_on_exit_confirmed")   # 四翻确认后的统一分流入口
	check(probe.called,
		"P2-7：SETTLE 态手势确认退出 → 转结算退出钮同链路（红态：落 else 静默零反馈，HUD 却常显「退出【双手】四指同翻」）")
	check_eq(bool(tracker.get("_done")), false, "P2-7 回归：确认后 tracker 复位（可再来一轮）")
	probe.free()
	game.set("_current_scene", null)

	# ================= S8. P2-4 回归断言（Z-B 已根除） =================
	print("-- S8 P2-4 8s 回落退役回归 --")
	var sp_src := FileAccess.get_file_as_string(SETTINGS_GD)
	check(not sp_src.contains("_fallback_camera_open"),
		"P2-4 回归：8s 超时回落旧链 _fallback_camera_open 已退役（Z-B：根除 A→B→… 无限轮换）")
	check(sp_src.contains("func _fail_camera_open("),
		"P2-4 回归：失败收口单漏斗 _fail_camera_open 在位（超时→失败终态、零设备切换）")

	# ================= S9. P2-10 confirm 期 info 排队 =================
	print("-- S9 P2-10 confirm 期 info 排队 --")
	strip.call("push_info", "信息A")
	strip.call("push_confirm", "挂起确认", Callable(), Callable())
	strip.call("push_info", "信息B（confirm 期排队）")
	check_eq(String(strip.get("_mode")), "confirm", "S9 前置：confirm 活动期条不被 info 顶掉（既有单槽）")
	strip.call("_on_cancel_pressed")   # confirm 收起 → 补播排队 info
	check_eq(String(strip.get("_mode")), "info",
		"P2-10：confirm 收起后补播排队 info（红态：静默丢弃 → 槽位空，期间所有 info 消失）")
	check_eq(str((strip.get("_msg_label") as Label).text), "信息B（confirm 期排队）",
		"P2-10：补播的是最新一条（非旧文案）")
	strip.call("_on_cancel_pressed")   # 收掉 info 复位
	check_eq(String(strip.get("_mode")), "", "S9 收尾：条复位")

	# ================= S10. P1-5 商店僵尸确认条 =================
	print("-- S10 P1-5 商店僵尸确认条 --")
	game.call("open_overlay", "shop")
	var shop: Node = game.get("_overlay_instance")
	check(shop != null and is_instance_valid(shop), "S10 前置：商店覆盖层已开")
	# 真实购买链：选一张未拥有、价>0、可购的皮肤 → _on_select 推购买确认（与用户实测同路径）
	var target: Dictionary = {}
	var owned: Array = (save.call("get_skins") as Dictionary).get("owned", [])
	for skin: Dictionary in SkinCatalog.get_skins():
		if not owned.has(String(skin.get("id", ""))) and int(skin.get("price", 0)) > 0 \
				and bool(skin.get("buyable", true)):
			target = skin
			break
	check(not target.is_empty(), "S10 前置：存在未拥有可购皮肤（购买确认真实可达）")
	if not target.is_empty():
		shop.call("_on_select", target)
	check_eq(String(strip.get("_mode")), "confirm", "S10 前置：购买确认条挂起")
	game.call("close_overlay")
	await process_frame
	await process_frame   # queue_free → _exit_tree（shop 收口）在本帧落地
	check(str(strip.get("_mode")) != "confirm",
		"P1-5：购买确认挂起时关店 → 无僵尸确认条（红态：_mode 恒 confirm，点确认/取消无效）")
	game.call("info", "僵尸后信息")
	check_eq(String(strip.get("_mode")), "info",
		"P1-5：关店后 info 正常显示（红态：confirm 占单槽 → 之后所有 info 被 push_info 静默丢弃）")
	check_eq(str((strip.get("_msg_label") as Label).text), "僵尸后信息", "P1-5：后续 info 文案落位")
	strip.call("_on_cancel_pressed")

	# ================= S11. P2-9 dismiss_confirm 不误杀 =================
	print("-- S11 P2-9 dismiss_confirm 不误杀 --")
	game.call("confirm", "关卡退出确认（外来）", Callable(), Callable())
	check_eq(String(strip.get("_mode")), "confirm", "S11 前置：外来确认挂起（等效关卡退出确认）")
	game.call("open_overlay", "settings")
	await process_frame
	game.call("close_overlay")
	await process_frame
	await process_frame   # settings._exit_tree 落地
	check_eq(String(strip.get("_mode")), "confirm",
		"P2-9：关设置面板不误杀外来确认（红态：settings._exit_tree 无条件 dismiss 收走关卡退出确认）")
	# 对照：面板自己推的确认关闭时照常收起（既有回修②P2-2 语义保持）
	save.call("update_settings", {"gesture_input": false, "gesture_camera_enabled": true})
	game.call("open_overlay", "settings")
	await process_frame
	var sp_own: Node = game.get("_overlay_instance")
	var cam_btn: Button = sp_own.get("camera_toggle") as Button
	cam_btn.set_pressed_no_signal(true)   # Q2：手势关+摄像头开
	cam_btn.set_pressed_no_signal(false)
	cam_btn.toggled.emit(false)           # 点摄像头钮 → 态② Game.confirm（面板自记句柄）
	check_eq(String(strip.get("_mode")), "confirm", "S11 对照前置：面板自有确认挂起")
	game.call("close_overlay")
	await process_frame
	await process_frame
	check(str(strip.get("_mode")) != "confirm",
		"P2-9 对照：面板自己的 confirm 关闭时照常按取消收起（回修②P2-2 既有语义保持）")

	# ================= S12. P2-8 HUD 即时重排 =================
	print("-- S12 P2-8 HUD 即时重排 --")
	check(game.has_signal("overlay_changed"), "P2-8：Game.overlay_changed 信号在位（红态=缺失，仅 0.5s 轮询）")
	var hud: Control = (load("res://scenes/shared/gesture_hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	await process_frame
	check_eq(bool(hud.get("_dock_settings_open")), false, "S12 前置：HUD 停靠标记初始无覆盖层")
	game.call("open_overlay", "settings")
	check_eq(bool(hud.get("_dock_settings_open")), true,
		"P2-8：open_overlay 当帧即时重排 HUD（红态：0.5s 内 HUD 仍按 LEVEL 停靠压在面板上）")
	game.call("close_overlay")
	check_eq(bool(hud.get("_dock_settings_open")), false,
		"P2-8：close_overlay 当帧即时重排（轮询留作兜底）")
	hud.queue_free()
	await process_frame

	# ================= S13. P2-11 fps 子列不压设备行 =================
	print("-- S13 P2-11 fps 子列几何 --")
	var sp: Node = (load(SETTINGS_SCENE) as PackedScene).instantiate()
	add_child(sp)
	await process_frame
	var menu: Node = sp.get_node("CameraMenuLayer/CameraMenuPopup/CameraMenu")
	gb.set("_camera_enum", {"cameras": [{"id": 0, "name": "A"}, {"id": 1, "name": "B"},
		{"id": 2, "name": "C"}], "current_camera": 0})
	gb.set("_probe_matrix_cache", {1: {"ok": true, "resolutions": [[640, 480]], "fps_options": [15, 30]}})
	menu.call("open_menu")
	var rows: Array = menu.get("_rows") as Array
	check(rows.size() >= 3, "S13 前置：设备行 ≥3（fps 压行复现前提）")
	# 夹具钉几何（test_fix_window_scale 段7 同款：无头行宽退化夹具伪影；同帧钉位不触发重排）
	var menu_root: Control = menu as Control
	menu_root.size = Vector2(280.0, 130.0)
	for i: int in rows.size():
		var r: Control = rows[i]
		r.size = Vector2(264.0, 26.0)
		r.position = Vector2(8.0, 8.0 + float(i) * 36.0)
	var row1: Control = rows[1]
	menu.call("_open_res_sub", 1, row1)
	var res_sub: PopupPanel = menu.get("_res_sub")
	var fps_sub: PopupPanel = menu.get("_fps_sub")
	check(res_sub != null and fps_sub != null, "S13 前置：res/fps 双列同现（阶梯既有语义）")
	if fps_sub != null and rows.size() >= 3:
		var fps_pos: Vector2i = fps_sub.position
		var fps_w: float = float(fps_sub.size.x) if fps_sub.size.x > 0 else 100.0
		var fps_h: float = float(fps_sub.size.y) if fps_sub.size.y > 0 else 100.0
		var fps_rect := Rect2(Vector2(fps_pos), Vector2(fps_w, fps_h))
		# ① 红测：fps 列不得覆盖任何设备行（旧行为 y=锚行底缘 → 恒压后续行右端 ~106px）
		var hit_rows: Array = []
		for r2: Variant in rows:
			var rc: Control = r2 as Control
			if fps_rect.intersects(Rect2(rc.get_screen_transform().origin, rc.size)):
				hit_rows.append(rc.name)
		check_eq(hit_rows.size(), 0,
			"P2-11①：fps 列与全部设备行零相交（红态：点设备名右半命中 fps 按钮写 gesture_camera_fps；命中=%s）" % [hit_rows])
		# ② 右安全边距 ≥14px（fps 右缘 → res 列左缘）
		var res_x: float = float(res_sub.position.x)
		check(res_x - (float(fps_pos.x) + fps_w) >= 14.0 - 0.01,
			"P2-11②：fps 列右缘距 res 列左缘 ≥14px（红态：仅 6px 安全边）")
		# ③ 回归：res 列仍锚锚控行右缘（popup_anchor_px 单一漏斗零变化）
		check_eq(Vector2i(res_sub.position),
			Vector2i(row1.get_screen_transform().origin + Vector2(row1.size.x, 0.0)),
			"P2-11③ 回归：res 子列锚 = 锚控行 origin+宽（既有锚定漏斗零回归）")
	sp.queue_free()
	await process_frame

	# ================= S14. P1-4 回归断言（Z-B 已修，不重复改码） =================
	print("-- S14 P1-4 下拉切设备回归 --")
	save.call("update_settings", {"gesture_input": false, "gesture_camera_enabled": false})
	var sp2: Node = (load(SETTINGS_SCENE) as PackedScene).instantiate()
	add_child(sp2)
	await process_frame
	var ges2: Button = sp2.get("gesture_toggle") as Button
	var cam2: Button = sp2.get("camera_toggle") as Button
	check(not bool(ges2.button_pressed) and not bool(cam2.button_pressed), "P1-4 前置：面板进入 Q3（手势关+摄像头关）")
	gb.set("_camera_enum", {"cameras": [{"id": 0, "name": "CamX"}, {"id": 1, "name": "CamY"}],
		"current_camera": 0})
	var menu2: Node = sp2.get_node("CameraMenuLayer/CameraMenuPopup/CameraMenu")
	menu2.call("open_menu")
	var rows2: Array = menu2.get("_rows") as Array
	var row_b: Control = null
	for r3: Variant in rows2:
		var rc3: Control = r3 as Control
		if rc3.has_meta("cam_id") and int(rc3.get_meta("cam_id")) == 1:
			row_b = rc3
	check(row_b != null, "P1-4 前置：下拉设备行 CamY（id=1）在位")
	if row_b != null:
		row_b.pressed.emit()   # 无头 GUI 命中不可用 → pressed.emit() 直驱
	check_eq(bool(cam2.button_pressed), true, "P1-4 回归：Q3 下拉点设备 → 摄像头按钮变亮")
	check(bool(cam2.disabled), "P1-4 回归：进 OPENING 加载态（按钮禁用=打开中）")
	var dots: Array = (load(SETTINGS_GD) as GDScript).get_script_constant_map().get("CAM_OPENING_DOTS", [])
	check(dots is Array and (dots as Array).has(String(cam2.text)),
		"P1-4 回归：OPENING 文案 ∈ 摄像头正在加载中点循环档（实际=%s）" % String(cam2.text))
	var s_after: Dictionary = save.call("get_settings")
	check_eq(bool(s_after.get("gesture_camera_enabled", false)), true,
		"P1-4 回归：gesture_camera_enabled=true（单一状态机入口落档，非绕过四象限直发 SWITCH）")
	check_eq(String(s_after.get("gesture_camera_device", "")), "CamY",
		"P1-4 回归：记忆设备=点击行显示名（经 select_camera_device 写档）")
	sp2.queue_free()
	await process_frame
	await process_frame

	print("== test_z_defects 断言完成 ==")
	finish()
