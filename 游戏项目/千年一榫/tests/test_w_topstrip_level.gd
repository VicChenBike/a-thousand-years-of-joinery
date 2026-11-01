extends "res://tests/test_base.gd"
## 批次 W3（P1-5，拍板 2）：TopStrip 关卡态顶部贴边（规格指定测试件，TDD 先红）。
## 规格 §4 P1-5 契约：
##   TopStrip push 时查 Game 当前态——LEVEL 态 offset_top=6（条顶移入顶栏高度内短暂覆盖顶栏
##   标签，2.5s 自愈；条高 ~53 < TopBar 60），其它态维持 TOP_OFFSET=70；水平居中不变；
##   直接赋 offset_top 不走 set_anchors_preset（坑⑧）。
##   验收硬断言：info 条矩形 × TargetView / JoinView（level_scene.tscn 锚 → x 12~532 / 620~1140,
##   y 64~266）零相交；主菜单态 offset=70 回归。confirm 条明确决策=允许压顶栏标签（拍板 2 口径，
##   同走 offset=6；零相交硬断言仅 info 条，confirm 压顶栏判走 W7 走查）。
## 防坑：--script 模式 Game._scene_container=null → 不走 goto_state（会触发场景加载链），
##   直写 Game._state 模拟状态（test_v_hud_gate 段 5 先例）；钉设计视口 1152×648（headless
##   expand 撑 1152×1152）；N2 滑入动效 0.25s —— 几何断言前 await 0.5s 等动效终值。
## 清档纪律：本测试实例化 level_scene.tscn 但以 _settled 直写拦截 _exit_tree 检查点写盘，
##   全程零 SaveManager 写路径（update_settings/save_game 零调用）→ 无需备份还原组；
##   尾段 EVID 断言 save.json 字节不变自证。

const LEVEL_SCENE := "res://scenes/level/level_scene.tscn"
const SAVE_PATH := "user://save.json"
const STATE_LEVEL := 4      # Game.State {BOOT0,MAIN_MENU1,OPENING_MOVIE2,TALK3,LEVEL4,SETTLE5,CATALOG6}
const STATE_MAIN_MENU := 1
const STATE_BOOT := 0
const LEVEL_TOP := 6.0
const REST_TOP := 70.0

var _pre_save_text: String = ""

func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _rect(n: Control) -> Rect2:
	return Rect2(n.global_position, n.size)

func _initialize() -> void:
	print("== test_w_topstrip_level（批次 W3：P1-5 关卡态顶部贴边） ==")
	if FileAccess.file_exists(SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(SAVE_PATH)
	await process_frame
	# ---- 前置：关卡场景实例（面板矩形取真实 tscn 几何）----
	var game: Node = root.get_node("Game")
	var level: Node = (load(LEVEL_SCENE) as PackedScene).instantiate()
	level.call("set_context", {"chapter": 1})
	add_child(level)
	await process_frame
	await process_frame
	# 实证坑（test_u_dock_anchors 先例）：无头 expand 撑 1152×1152——**add 后补钉**设计视口再等两帧
	root.size = Vector2i(1152, 648)
	await process_frame
	await process_frame
	var target_view: Control = level.get_node("TargetView") as Control
	var join_view: Control = level.get_node("JoinView") as Control
	check(target_view != null and join_view != null, "P0 前置：TargetView/JoinView 节点在场")
	var tv := _rect(target_view)
	var jv := _rect(join_view)
	check(absf(tv.position.x - 12.0) < 2.0 and absf(tv.position.y - 64.0) < 2.0,
		"P0 前置：TargetView 矩形≈(12,64)（锚×设计视口，实测 %s）" % tv)
	check(absf(jv.position.x - 620.0) < 2.0, "P0 前置：JoinView 矩形≈x 620 起（实测 %s）" % jv)
	# ---- 段 1：LEVEL 态 info 条贴边 + 与两 3D 面板零相交（硬断言）----
	game.set("_state", STATE_LEVEL)
	var strip: Control = (load("res://scenes/shared/top_strip.gd") as GDScript).new()
	var layer := CanvasLayer.new()
	layer.layer = 63
	add_child(layer)
	layer.add_child(strip)
	await process_frame
	strip.call("push_info", "对接成功，进入结算")
	await process_frame
	await create_timer(0.5).timeout   # N2 滑入动效（0.25s）终值放行
	check_eq(float(strip.get("offset_top")), LEVEL_TOP,
		"W1: LEVEL 态 push_info 后 offset_top=6（红：旧口径恒 70）")
	var sr := _rect(strip)
	check(sr.position.y >= 0.0 and sr.position.y < 64.0,
		"W2: 条顶在顶栏高度内（y<64，实测 %s）" % sr.position.y)
	check(sr.intersects(tv) == false, "W3 硬断言: info 条 × TargetView 零相交（条=%s 面板=%s）" % [sr, tv])
	check(sr.intersects(jv) == false, "W4 硬断言: info 条 × JoinView 零相交")
	var vp_w: float = strip.get_viewport_rect().size.x
	var center_x := sr.position.x + sr.size.x * 0.5
	check(absf(center_x - vp_w * 0.5) <= 1.0, "W5: 水平居中不变（中线 %.1f / 视口宽 %.1f）" % [center_x, vp_w])
	# ---- 段 2：confirm 条同走贴边（拍板 2：允许压顶栏，2.5s 自愈口径一致；不设零相交硬断言）----
	strip.call("push_confirm", "确认退出关卡？", Callable(), Callable())
	await create_timer(0.5).timeout
	check_eq(float(strip.get("offset_top")), LEVEL_TOP,
		"W6: LEVEL 态 confirm 条同走 offset_top=6（允许短暂覆盖顶栏标签，零相交断言不适用）")
	strip.call("dismiss_active_confirm")
	# ---- 段 3：主菜单态回归 offset=70 ----
	game.set("_state", STATE_MAIN_MENU)
	strip.call("push_info", "主菜单提示条")
	await create_timer(0.5).timeout
	check_eq(float(strip.get("offset_top")), REST_TOP,
		"W7: 非 LEVEL 态维持 offset_top=70（主菜单回归锚）")
	check(absf(_rect(strip).position.y - REST_TOP) <= 1.0, "W8: 条顶全局 y≈70（回归锚）")
	# info 到时自愈（2.5s 档）：用短秒数验证自灭路径不受贴边改动影响
	strip.call("push_info", "自愈条", 0.3)
	await create_timer(0.7).timeout
	check_eq(bool(strip.visible), false, "W9: info 到时自灭（贴边改动不破坏单槽自愈）")
	# ---- 收尾：直写 _settled 拦截 level _exit_tree 检查点写盘 + 态复位 + 字节不变自证 ----
	strip.free()
	layer.free()
	level.set("_settled", true)
	level.free()
	await process_frame
	game.set("_state", STATE_BOOT)
	var post: String = FileAccess.get_file_as_string(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "W10 清档自证：全程零写盘（save.json 起测/终测逐字节等价）")
	print("EVID|no_user_write|w_topstrip_level|settled_poke=1")
	finish()
