extends "res://tests/test_base.gd"
## 批次 T 判定用例（T-D 域）：T5 中指单击扩展——左右手各自四重门 + _click_zone 分区 +
## 任一 armed 冻结全部 motion + 双 armed 同窗互斥去重（0.1s）。旧文件守基础门（click_route），
## 本文件守扩展面（spec §4-5 锚点）。

const CATALOG_SCENE := "res://scenes/catalog/catalog_scene.tscn"

var router: Variant
var game: Variant
var mock: MockLayer

class MockLayer extends CanvasLayer:
	var calls: Array = []
	func synth_button(pos: Vector2, pressed: bool, ctrl: bool) -> InputEventMouseButton:
		calls.append(["btn", pos, pressed, ctrl])
		return InputEventMouseButton.new()
	func synth_motion(pos: Vector2) -> InputEventMouseMotion:
		calls.append(["motion", pos])
		return InputEventMouseMotion.new()
	func push(_ev: InputEvent) -> void:
		calls.append(["push"])
	func show_cursor(_side: String, _pos: Vector2) -> void:
		pass
	# 批次 W（N15 等价改写，拍板 10）：环色 mock 定义随琥珀环 API 删除整体退役

func _btn_events(pressed: bool) -> Array:
	var out: Array = []
	for c: Variant in mock.calls:
		if c[0] == "btn" and bool(c[2]) == pressed:
			out.append(c)
	return out

## P2-3（RV-2）：T8 增益逆变换——本文件喂入归一坐标语义=期望 content 归一位（plan 直喂口径系
## S9 时代无增益语义），而 Router _profile 尾部统一增益 (n−0.5)×GAIN+0.5 后才发 pos，直喂经增益
## +钳制实际生效点落角点/边缘（段 2「面板内零 click」依赖布局碰运气）。喂点先逆推
## raw=(n−0.5)/GAIN+0.5（spec §2 协议 8 同式），Router 侧 content 位精确还原=喂入归一 × 视口；
## raw 恒落 [0.3,0.7] 中央带不触钳制。配套手 dict 携带 tip_x/tip_y（T7 滤波直通：_profile 字段在
## 时不再二次滤波/EMA，t_level_mode :129-131 同款）——landmark 路径 EMA 兜底会使跳位首帧只到
## 70% 处致命中坐标漂移。
## 批次V审查①-P1: 逆增益硬编码÷2.5→运行期常量读法（pointcloud_route _inv_gain 同款供件）——
## 生产增益已 2.5→3.5（gesture_map.CURSOR_GAIN），旧硬编码致喂点 content 位漂移 1.4 倍
## （断言容忍漂移假绿）。GAIN 运行期读 gesture_map 常量，断言意图不变（本文件测点击扩张/
## armed 门逻辑，非增益本身）。
func _gain_inv(n: Vector2) -> Vector2:
	## 批次 AC §4.4-2：纵向基准上移 c_y=(0.5+m)/g（与 apply_cursor_gain 互为反函数）。
	var gm_c: Dictionary = load("res://scripts/gesture_map.gd").get_script_constant_map()
	var g: float = float(gm_c.get("CURSOR_GAIN", 3.5))
	var cy: float = (0.5 + float(gm_c.get("CURSOR_OVERSHOOT", 0.15))) / g
	return (n - Vector2(0.5, 0.5)) / g + Vector2(0.5, cy)

func _hand(conf: float, fingers: Array, tip: Vector2, label: String) -> Dictionary:
	var lm: Array = []
	for i: int in 21:
		lm.append([0.5, 0.5, 0.0])
	lm[0] = [tip.x - 0.05, tip.y + 0.2, 0.0]
	if label == "Left":
		lm[5] = [lm[0][0] + 0.05, lm[0][1] - 0.06, 0.0]
		lm[17] = [lm[0][0] - 0.05, lm[0][1] - 0.05, 0.0]
	lm[8] = [tip.x, tip.y, 0.0]
	lm[9] = [lm[0][0], lm[0][1] - 0.2, 0.0]
	return {"gesture": "", "gesture_id": 0, "confidence": conf,
		"hand_x": tip.x, "hand_y": tip.y, "hand_z": 0.0,
		"hand_rotation_x": 5.0, "hand_rotation_y": 0.0, "hand_rotation_z": 0.0,
		"fingers": fingers, "pinch_distance": 0.5, "hand_index": 0 if label == "Left" else 1,
		"handedness": label, "landmarks": lm, "fps": 30.0, "is_detected": true,
		"timestamp": 0.0, "palm_size": 0.2,
		"tip_x": tip.x, "tip_y": tip.y}   # P2-3：滤波直通字段（tip 实参已过 _gain_inv 为增益前 raw）

func _feed(side: String, fingers: Array, tip: Vector2) -> void:
	var h := _hand(0.9, fingers, _gain_inv(tip), "Left" if side == "left" else "Right")
	var d := {"left": null, "right": null, "timestamp": 0.0}
	d[side] = h
	router.feed(d)

func _feed_both(lf: Array, rf: Array, lt: Vector2, rt: Vector2) -> void:
	router.feed({"left": _hand(0.9, lf, _gain_inv(lt), "Left"),
		"right": _hand(0.9, rf, _gain_inv(rt), "Right"), "timestamp": 0.0})

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
const DISC_BK_PREFIX := "user://_r2b_tce_backup_"
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
	print("EVID|user_restore|tce|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_t_click_expand ==")
	_backup_user()
	var save: Variant = get_root().get_node("SaveManager")
	var bridge: Variant = get_root().get_node("GestureBridge")
	game = get_root().get_node("Game")
	var p: String = ProjectSettings.globalize_path("user://save.json")
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
	save.load_game()
	bridge._set_state(1)
	game.goto_state(game.State.MAIN_MENU)
	router = load("res://autoload/gesture_router.gd").new()
	add_child(router)
	await process_frame
	bridge._set_state(1)
	router._setup()
	mock = MockLayer.new()
	add_child(mock)
	router.set_cursor_layer(mock)
	# 实施勘误（TD-1，留痕）：无头 --script 未 attach → open_overlay 首行 _overlay_layer==null
	# 即 return，_click_zone 覆盖层分支空转（段 8「设置覆盖层开 → true」在 CATALOG 态实测红）。
	# attach(null, layer)：容器保持 null → goto_state 仍只改状态机不加载真场景（pointcloud_route
	# :183「goto_state 只改状态机」同款口径，防真场景与测试 cat 双注册污染 gesture_panel 组），
	# 仅覆盖层通道真实化（test_settings_panel :53 attach 先例）——段 3/段 8 覆盖层断言由此可达。
	var overlay_holder: CanvasLayer = CanvasLayer.new()
	add_child(overlay_holder)
	game.attach(null, overlay_holder)
	var f_cursor: Array = [0.1, 0.9, 0.1, 0.1, 0.1]
	var f_two: Array = [0.1, 0.9, 0.9, 0.1, 0.1]
	# ---- 1. 右手主菜单单击（3 checks）----
	_feed("right", f_cursor, Vector2(0.7, 0.4))
	_feed("right", f_two, Vector2(0.7, 0.4))
	_feed("right", f_two, Vector2(0.7, 0.4))
	check_eq(_btn_events(true).size(), 1, "T5：右手主菜单伸中指 → 合成按下恰一次（左手限定放宽）")
	if _btn_events(true).size() == 1:
		check_eq(Vector2(_btn_events(true)[0][1]),
			Vector2(router.get("_last_cursor_pos")["right"]), "T5：右手按下位=右手光标 content 坐标")
	_feed("right", f_cursor, Vector2(0.7, 0.4))
	check_eq(_btn_events(false).size(), 1, "T5：右手收中指 → 抬起恰一次（per-side armed 成对）")
	mock.calls.clear()
	# ---- 2. CATALOG 面板外可点 / 面板内仍面板模型（4 checks）----
	var cat: Node = (load(CATALOG_SCENE) as PackedScene).instantiate()
	add_child(cat)
	await process_frame
	await process_frame
	game.goto_state(game.State.CATALOG)
	cat.call("_select_chapter", 1)
	await process_frame
	var rect: Rect2 = cat.call("gesture_panel_rect")
	var outside: Vector2 = (Vector2(24, 620)) / get_root().get_visible_rect().size   # 面板外角落
	_feed("left", f_cursor, outside)
	_feed("left", f_two, outside)
	_feed("left", f_two, outside)
	check_eq(_btn_events(true).size(), 1, "T5：图鉴面板外左手单击 → 按下恰一次（cloud 面板外可点）")
	_feed("left", f_cursor, outside)
	mock.calls.clear()
	_feed("right", f_cursor, outside)
	_feed("right", f_two, outside)
	_feed("right", f_two, outside)
	check_eq(_btn_events(true).size(), 1, "T5：图鉴面板外右手单击 → 按下恰一次")
	mock.calls.clear()
	var center: Vector2 = rect.get_center() / get_root().get_visible_rect().size
	_feed("left", f_cursor, center)
	_feed("left", f_two, center)
	_feed("left", f_two, center)
	check_eq(_btn_events(true).size(), 0, "T5：图鉴面板内伸中指 → 零 click（面板模型不变）")
	check(router.get("_active_panel") == cat, "T5：面板内仍走激活面板（批次 R 契约）")
	# P0-5：cat 不在此处释放——段 8 的「面板内 → _click_zone false」判定依赖 gesture_panel 组非空
	game.goto_state(game.State.MAIN_MENU)
	await process_frame
	mock.calls.clear()
	# ---- 3. 设置/商店覆盖层双手单击（3 checks）----
	game.open_overlay("settings")
	await process_frame
	_feed("left", f_cursor, Vector2(0.3, 0.4))
	_feed("left", f_two, Vector2(0.3, 0.4))
	_feed("left", f_two, Vector2(0.3, 0.4))
	check_eq(_btn_events(true).size(), 1, "T5：设置覆盖层左手单击成立")
	mock.calls.clear()
	_feed("right", f_cursor, Vector2(0.3, 0.4))
	_feed("right", f_two, Vector2(0.3, 0.4))
	_feed("right", f_two, Vector2(0.3, 0.4))
	check_eq(_btn_events(true).size(), 1, "T5：设置覆盖层右手单击成立")
	mock.calls.clear()   # 实施勘误（TD-1，留痕）：plan 段 3 设置→商店之间缺清场，商店断言累计到设置右手
	                     # 的按下（绿灯期实测期望 1 实际 2）——补 clear 使各断言只数本笔
	game.close_overlay()
	game.open_overlay("shop")
	await process_frame
	_feed("left", f_cursor, Vector2(0.5, 0.5))
	_feed("left", f_two, Vector2(0.5, 0.5))
	_feed("left", f_two, Vector2(0.5, 0.5))
	check_eq(_btn_events(true).size(), 1, "T5：商店覆盖层单击成立（覆盖层态语义）")
	game.close_overlay()
	await process_frame
	# 批次 W 等价改写①（P1-8a 上线）：前序覆盖层段遗留的 left armed 在 goto_state 的
	# reset_runtime 会派发恰一次合成抬起（新契约=不残留虚拟按下键）——先显式收手（cursor 帧
	# → two_up 释放 armed），隔离前序段的抬起与 LEVEL 段断言。
	_feed("left", f_cursor, Vector2(0.5, 0.5))
	mock.calls.clear()
	# ---- 4. LEVEL 双手零 click（2 checks；批次 W 等价改写②：拍板 3 已被 N7/拍板 8 推翻——
	# LEVEL 零 armed click 语义收窄为「非 UI 按钮悬停位」，本段喂点=视口中心（非按钮悬停），
	# armed 仍不可达，断言语义保持）----
	game.goto_state(game.State.LEVEL)
	_feed("left", f_cursor, Vector2(0.5, 0.5))
	_feed("left", f_two, Vector2(0.5, 0.5))
	_feed("left", f_two, Vector2(0.5, 0.5))
	_feed("right", f_cursor, Vector2(0.5, 0.5))
	_feed("right", f_two, Vector2(0.5, 0.5))
	_feed("right", f_two, Vector2(0.5, 0.5))
	check_eq(_btn_events(true).size(), 0, "T5：LEVEL 左手伸中指零 click（拍板 3）")
	check_eq(_btn_events(false).size(), 0, "T5：LEVEL 右手伸中指零 click（拍板 3）")
	game.goto_state(game.State.MAIN_MENU)
	await process_frame
	mock.calls.clear()
	# ---- 5. 任一 armed 冻结全部 motion（2 checks）----
	_feed("left", f_cursor, Vector2(0.3, 0.4))
	_feed("left", f_two, Vector2(0.3, 0.4))
	_feed("left", f_two, Vector2(0.3, 0.4))   # 左 armed
	check(bool(router.get("_menu_click_armed")["left"]), "T5 前置：左 armed 成立（字典化）")
	mock.calls.clear()
	# 实施勘误（TD-1 段 5，留痕）：plan 原文 _feed("right", ...) 单侧喂帧 → 对侧 null 触发 Map
	# teardown 兜底 two_up（click_route 段 8 终审 P1 注记同款机制）→ 左 armed 在右 cursor_move
	# 派发前已被解除，断言空转（绿灯期实测 motions=1）。改双手同喂（click_route 段 8 先例）：
	# 左手 f_two 维持 armed 段，右手 cursor_move 走守卫（右侧重建后首帧 jitter=false）。
	router.feed({"left": _hand(0.9, f_two, Vector2(0.3, 0.4), "Left"),
		"right": _hand(0.9, f_cursor, Vector2(0.7, 0.4), "Right"), "timestamp": 0.0})
	var motions := 0
	for c: Variant in mock.calls:
		if c[0] == "motion":
			motions += 1
	check_eq(motions, 0, "T5：左 armed 期间右手 cursor_move 不推 motion（守卫升级：任一 armed）")
	_feed("left", f_cursor, Vector2(0.3, 0.4))   # 抬起成对
	mock.calls.clear()
	_feed("right", f_cursor, Vector2(0.7, 0.4))
	_feed("right", f_two, Vector2(0.7, 0.4))
	_feed("right", f_two, Vector2(0.7, 0.4))   # 右 armed
	mock.calls.clear()
	# 实施勘误（TD-1 段 5，对称同款）：双手同喂——右手 f_two 维持 armed 段，左手 cursor_move
	# 走守卫：喂 (0.32,0.4) 与上帧 (0.3,0.4) 的 raw 差=0.02/GAIN（批次V审查①-P1 运行期读法，
	# GAIN=3.5 → 0.0057）仍 1.6 倍于死区 0.0035
	# （P2-3 逆变换等比缩位移），jitter=false → cursor_move 派发受 armed[right] 拦截，断言为真护栏
	# （同位会落死区帧假绿）。
	router.feed({"left": _hand(0.9, f_cursor, Vector2(0.32, 0.4), "Left"),
		"right": _hand(0.9, f_two, Vector2(0.7, 0.4), "Right"), "timestamp": 0.0})
	motions = 0
	for c: Variant in mock.calls:
		if c[0] == "motion":
			motions += 1
	check_eq(motions, 0, "T5：右 armed 期间左手 cursor_move 不推 motion（对称）")
	_feed("right", f_cursor, Vector2(0.7, 0.4))
	mock.calls.clear()
	# ---- 6. 双 armed 同窗互斥去重 → 批次 AA W3-4 等价改写（spec §6.3 + §22 裁决 3）----
	# 旧口径「双手同帧伸中指 → 仅先到侧受理（0.1s 互斥窗口，恰 1 按下）」随对接判据改「双手
	# 同帧 two 且保持确认帧优先于单击」退役：两侧 two_down 同帧抑制 → **零按下**、双侧 armed
	# 皆不成立（改走 join）；「互斥不破坏成对性」改由**单侧受理 → 收指成对抬起**等价承接
	# （断言数 2→5，只增不减）。单侧 two 零回归同时是 R3-e 护栏在 router 级的落点。
	_feed_both(f_two, f_two, Vector2(0.3, 0.4), Vector2(0.7, 0.4))
	_feed_both(f_two, f_two, Vector2(0.3, 0.4), Vector2(0.7, 0.4))
	_feed_both(f_two, f_two, Vector2(0.3, 0.4), Vector2(0.7, 0.4))
	check_eq(_btn_events(true).size(), 0,
		"T5：双手同帧 two → 两侧零按下（W3-4 抑制改走 join；旧「仅先到侧受理 0.1s 互斥窗」退役）")
	check(not bool(router.get("_menu_click_armed")["left"]) and not bool(router.get("_menu_click_armed")["right"]),
		"T5：抑制态双侧 armed 皆不成立（零残留武装）")
	_feed_both(f_cursor, f_cursor, Vector2(0.3, 0.4), Vector2(0.7, 0.4))   # 双侧收指复位（退出 two → 恢复常态）
	mock.calls.clear()
	_feed("left", f_two, Vector2(0.3, 0.4))
	_feed("left", f_two, Vector2(0.3, 0.4))   # 单侧 two → 左=单击常态（右手缺席，不受抑制）
	check_eq(_btn_events(true).size(), 1,
		"T5：单侧 two → 恰 1 按下（W3-4 护栏 R3-e：单击常态不受对接抑制影响）")
	var armed_l: bool = bool(router.get("_menu_click_armed")["left"])
	var armed_r: bool = bool(router.get("_menu_click_armed")["right"])
	check(armed_l != armed_r, "T5：单侧受理后恰一侧 armed（异或保持）")
	var keep: String = "left" if armed_l else "right"
	_feed(keep, f_cursor, Vector2(0.3, 0.4))   # 受理侧收中指 → 成对抬起
	check_eq(_btn_events(false).size(), 1, "T5：受理侧抬起成对（互斥不破坏成对性）")
	mock.calls.clear()
	# ---- 7. reset 清双侧 armed（2 checks）----
	_feed("left", f_cursor, Vector2(0.3, 0.4))
	_feed("left", f_two, Vector2(0.3, 0.4))
	_feed("left", f_two, Vector2(0.3, 0.4))
	router.reset_runtime()
	check_eq(bool(router.get("_menu_click_armed")["left"]), false, "T5：reset 后左 armed 清零")
	check_eq(bool(router.get("_menu_click_armed")["right"]), false, "T5：reset 后右 armed 清零")
	# ---- 8. _click_zone 分区直测（6 checks）----
	check_eq(bool(router.call("_click_zone", "left")), true, "T5 zone：主菜单（none）→ true")
	game.goto_state(game.State.LEVEL)
	check_eq(bool(router.call("_click_zone", "left")), false, "T5 zone：LEVEL → false（拍板 3）")
	game.goto_state(game.State.CATALOG)
	router.set("_last_cursor_pos", {"left": Vector2(24.0, 620.0)})   # P0-5：先直注面板外点（图鉴底部空带；段 4~7 的 feed 残留位不可靠）
	check_eq(bool(router.call("_click_zone", "left")), true, "T5 zone：图鉴光标在面板外 → true")
	var armed := {"left": false, "right": false}
	router.set("_last_cursor_pos", {"left": rect.get_center()})
	check_eq(bool(router.call("_click_zone", "left")), false, "T5 zone：图鉴光标在面板矩形内 → false（面板模型；cat 存活至本段末）")
	game.open_overlay("settings")
	check_eq(bool(router.call("_click_zone", "left")), true, "T5 zone：设置覆盖层开 → true")
	game.close_overlay()
	game.open_overlay("shop")
	check_eq(bool(router.call("_click_zone", "right")), true, "T5 zone：商店覆盖层开 → true")
	game.close_overlay()
	game.goto_state(game.State.MAIN_MENU)
	await process_frame
	armed = {"left": false, "right": false}
	router.set("_menu_click_armed", armed)   # 清场复位
	cat.free()
	finish()
