extends "res://tests/test_base.gd"
## 批次 T 判定用例（T-D 域）→ 批次 X X4 波等价替换（2026-09-21，spec §6 P5-a）：T10 状态机
## SELECT_ARMED↔ORBIT 保留；dwell 0.3s/28px 悬停确认 + 选择冷却 0.8s 随「立即按下」新模型
## 退役——段 D/E/F 已改写为「立即按下/空白即时可达/reset 笔画标志清零」断言（逐条留痕）。
## 拦截点契约（P1-2：面板激活/面板外两段零触碰）不变。
## 夹具复用 test_q_level_interactions 真场景驱动（实例化 level_scene，P2-11）；清档前奏同款。
## 键鼠回归红线不在本文件（test_q_level_interactions / test_level_interaction 回归覆盖）。

const SCENE_PATH := "res://scenes/level/level_scene.tscn"
const MISS := Vector3i(-1, -1, -1)
const ORBIT_COLOR := Color("#D9A441")

var router: Variant
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
	# 批次 W（N15 等价改写，拍板 10）：set_ring_color/reset_ring_color mock 定义随琥珀环 API
	# 删除整体退役——光标环恒手别色，Router 零染色调用；ORBIT 进/出改由提示行承载（段 B/C）。

func _btn_events(pressed: bool) -> Array:
	var out: Array = []
	for c: Variant in mock.calls:
		if c[0] == "btn" and bool(c[2]) == pressed:
			out.append(c)
	return out

func _ring_events() -> Array:
	var out: Array = []
	for c: Variant in mock.calls:
		if c[0] == "ring" or c[0] == "ring_reset":
			out.append(c)
	return out

func _cleanup_save() -> void:
	for q: String in ["user://save.json", "user://first_launch.flag"]:
		var abs_p: String = ProjectSettings.globalize_path(q)
		if FileAccess.file_exists(abs_p):
			DirAccess.remove_absolute(abs_p)

func _hand(conf: float, fingers: Array, tip: Vector2) -> Dictionary:
	var lm: Array = []
	for i: int in 21:
		lm.append([0.5, 0.5, 0.0])
	lm[0] = [tip.x - 0.05, tip.y + 0.2, 0.0]
	lm[5] = [lm[0][0] + 0.05, lm[0][1] - 0.06, 0.0]
	lm[17] = [lm[0][0] - 0.05, lm[0][1] - 0.05, 0.0]
	lm[8] = [tip.x, tip.y, 0.0]
	lm[9] = [lm[0][0], lm[0][1] - 0.2, 0.0]
	# 实施勘误（TD-3，留痕）：携带 T7 协议字段 tip_x/tip_y 走滤波直通（_profile 字段在时不再
	# 二次滤波/EMA，t_cursor_filter 段 1 与 pointcloud_route 段 2 先例）——landmark 路径的 EMA
	# 兜底会使跳位后首帧只到 70% 处，面板命中/格命中坐标不可靠。
	return {"gesture": "", "gesture_id": 0, "confidence": conf,
		"hand_x": tip.x, "hand_y": tip.y, "hand_z": 0.0,
		"hand_rotation_x": 5.0, "hand_rotation_y": 0.0, "hand_rotation_z": 0.0,
		"fingers": fingers, "pinch_distance": 0.5, "hand_index": 0, "handedness": "Left",
		"landmarks": lm, "fps": 30.0, "is_detected": true, "timestamp": 0.0, "palm_size": 0.2,
		"tip_x": tip.x, "tip_y": tip.y}

func _feed_left(fingers: Array, tip: Vector2) -> void:
	router.feed({"left": _hand(0.9, fingers, tip), "right": null, "timestamp": 0.0})

## 批次 AC 4B（§4.6-1）新增基建：**视口空白收敛喂帧**——连续喂 cursor 帧直至路由光标缓存
## 落入目标面板矩形内且该点命中为空，随后交由调用方的 two 帧完成绑定/进入。
## 动机：二级 EMA（α0.60）在起点与目标相距较远时 3 帧内到不了位（探针实测跨视口切换后
## 光标停在面板外 23px → 绑定落空），与 test_y_subtract_pen._settle_cell 的「位置敏感断言
## 前置收敛」同一纪律，对象由「命中格」换为「面板内空白」。上限 40 帧（收敛 + 死区地板余量）。
func _settle_blank(lv: Node, panel: Node, norm: Vector2) -> void:
	if lv == null or panel == null or not (panel is Control):
		return
	var rect: Rect2 = (panel as Control).get_global_rect()
	for _i: int in 40:
		_feed_left([0.1, 0.9, 0.1, 0.1, 0.1], norm)
		var cur_v: Variant = (router.get("_last_cursor_pos") as Dictionary).get("left", null)
		if typeof(cur_v) != TYPE_VECTOR2:
			continue
		var cur: Vector2 = cur_v
		if not rect.has_point(cur):
			continue
		if lv.call("hit_panel_cell", panel, cur) != MISS:
			continue
		return

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
const DISC_BK_PREFIX := "user://_r2b_tlm_backup_"
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
	print("EVID|user_restore|tlm|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_t_level_mode ==")
	_backup_user()
	_cleanup_save()
	get_root().get_node("SaveManager").call("load_game")
	var bridge: Variant = get_root().get_node("GestureBridge")
	var game: Variant = get_root().get_node("Game")
	bridge._set_state(1)
	router = load("res://autoload/gesture_router.gd").new()
	add_child(router)
	await process_frame
	bridge._set_state(1)
	router._setup()
	mock = MockLayer.new()
	add_child(mock)
	router.set_cursor_layer(mock)
	var inst: Node = (load(SCENE_PATH) as PackedScene).instantiate()
	check(inst != null, "关卡场景可实例化")
	if inst == null:
		finish()
		return
	inst.call("set_context", {"chapter": 1})
	add_child(inst)
	# 实施勘误（TD-3，留痕）：Router._level() 经 game.get_current_scene() 解析关卡（game.gd :56），
	# 无头 --script 未 attach → goto_state 的 _load_main_scene 首行 container==null 早退不载场景
	# （test_game_statemachine :37「未 attach 时 get_current_scene() 为 null」实证）→ T10 状态机
	# _level()==null 全线空转。直启实例须显式挂账（pointcloud_route 段 5 attach 先例的等价最小
	# 替代：不引入容器防 goto_state 加载第二份关卡场景污染 gesture_panel 组）。
	game._current_scene = inst
	await process_frame
	await process_frame
	game.goto_state(game.State.LEVEL)
	await process_frame
	var cont: SubViewportContainer = inst.get_node_or_null("MainView/ViewportContainer") as SubViewportContainer
	var vps: SubViewport = inst.get_node_or_null("MainView/ViewportContainer/SubViewport") as SubViewport
	var cam: Camera3D = inst.get_node_or_null("MainView/ViewportContainer/SubViewport/Camera3D")
	check(cont != null and vps != null and cam != null and vps.size.x > 1, "前置：容器/视口/相机在位")
	# 探针：中线步进找 2 互异命中格 + 1 空白位（q 夹具同款；全局位=容器全局原点+局部位）
	var found: Array = []
	var seen: Array = []
	var x := vps.size.x * 0.5
	while found.size() < 2 and x < vps.size.x:
		var c: Variant = inst.call("get_cell_hit", cam.project_ray_origin(Vector2(x, vps.size.y * 0.5)),
			cam.project_ray_normal(Vector2(x, vps.size.y * 0.5)))
		if c != MISS and not seen.has(c):
			seen.append(c)
			found.append([c, cont.get_global_rect().position + Vector2(x, vps.size.y * 0.5)])
		x += 8.0
	check_eq(found.size(), 2, "前置：主视中线探得 2 互异格（probes[i]=[cell,全局位]）")
	var blank := cont.get_global_rect().position + Vector2(6.0, 6.0)
	if inst.call("get_cell_hit", cam.project_ray_origin(Vector2(6.0, 6.0)), cam.project_ray_normal(Vector2(6.0, 6.0))) != MISS:
		blank = cont.get_global_rect().position + Vector2(4.0, vps.size.y - 4.0)
	var f_cursor: Array = [0.1, 0.9, 0.1, 0.1, 0.1]
	var f_two: Array = [0.1, 0.9, 0.9, 0.1, 0.1]
	# 实施勘误（TD-3，留痕）：喂点须按 T8 增益逆变换（plan §2 协议 #8：raw=(content/视口−0.5)/GAIN+0.5）
	# ——_profile 尾部统一增益后才发 pos，直喂 gpos/视口 经增益+钳制落角点（红灯期 ⑧ 激活失败、
	# 段 B 按下缺失实证）。逆变换后 Router 侧 content 位=gpos 精确还原。
	# 批次V审查①-P1: 逆增益硬编码÷2.5→运行期常量读法（pointcloud_route _inv_gain 同款供件）——
	# 生产增益已 2.5→3.5（gesture_map.CURSOR_GAIN），旧硬编码致喂点 content 位漂移 1.4 倍
	# （段 B 空白按下/段 D dwell 28px 断言落位失真真红）。GAIN 运行期读 gesture_map 常量，
	# 断言意图不变（本文件测 dwell/状态机逻辑，非增益本身）。
	## 批次 AC §4.4-2 等价改写：逆映射纵向基准上移 c_y=(0.5+m)/g（与 apply_cursor_gain 互逆）。
	var _gm_c: Dictionary = load("res://scripts/gesture_map.gd").get_script_constant_map()
	var _gain_g: float = float(_gm_c.get("CURSOR_GAIN", 3.5))
	var _cy_g: float = (0.5 + float(_gm_c.get("CURSOR_OVERSHOOT", 0.15))) / _gain_g
	var two_norm_at: Callable = func(gpos: Vector2) -> Vector2:
		var vsz: Vector2 = get_root().get_visible_rect().size
		return (gpos / vsz - Vector2(0.5, 0.5)) / _gain_g + Vector2(0.5, _cy_g)
	var blank_norm: Vector2 = two_norm_at.call(blank)
	var cell_norm: Vector2 = two_norm_at.call(found[0][1])
	# ---- 段 A. 拦截点契约（P1-2：⑧⑨，2 checks；P0-4 修正：⑨ 用全部 gesture_panel 之外的点、
	# ⑧ 用未激活面板 TargetView——blank(6,6) 在 MainView 容器内会走首笔激活空转、center 在已激活时凭运气）----
	# 实施勘误（TD-3，留痕）：plan 硬编码外点 (100,640) 系生产 1152×648 布局口径（MainView 底 616）；
	# 无头 --script 视口实测 1152×1152（探针留痕 AI工作记录/td3_probe_panels_temp.gd），关卡布局转置
	# （MainView 底≈1089），(100,640) 落入 MainView 矩形致 ⑨ 红改绿不可达。改动态取「全部注册矩形
	# 底边之下 +20px」外点（生产布局下语义与 (100,640) 一致，仍低于 MainView 底 616+20<644）。
	var outside_all := Vector2(100.0, 0.0)
	var max_bottom := 0.0
	for n: Node in get_root().get_tree().get_nodes_in_group("gesture_panel"):
		if n is Control:
			max_bottom = maxf(max_bottom, (n as Control).get_global_rect().end.y)
	outside_all.y = minf(max_bottom + 20.0, get_root().get_visible_rect().size.y - 4.0)
	_feed_left(f_cursor, two_norm_at.call(outside_all))
	_feed_left(f_two, two_norm_at.call(outside_all))
	_feed_left(f_two, two_norm_at.call(outside_all))
	check(router.get("_active_panel") == null and _btn_events(true).size() == 0,
		"⑨全部 gesture_panel 注册矩形之外 two_down → 无动作且无激活（批次 R 契约零触碰）")
	var tv_cont: SubViewportContainer = inst.get_node_or_null("TargetView/ViewportContainer") as SubViewportContainer
	check(tv_cont != null, "段 A 前置：TargetView 容器在位（未绑定视口供 ⑧ 用）")
	# 批次 AC 4B（§4.6-1）等价改写：视口绑定需「空白处二指单击」——TargetView **中心**在生产
	# 布局下命中木料（块上起笔不绑定），故取该容器内确认空白的一点（hit_panel_cell==NO_CELL）。
	var tv_blank: Vector2 = tv_cont.get_global_rect().position + Vector2(6.0, 6.0)
	if inst.call("hit_panel_cell", tv_cont, tv_blank) != MISS:
		tv_blank = tv_cont.get_global_rect().position + Vector2(4.0, tv_cont.size.y - 4.0)
	check(bool(inst.call("hit_panel_cell", tv_cont, tv_blank) == MISS),
		"段 A 前置：TargetView 空白点探得（hit_panel_cell==NO_CELL）")
	_feed_left(f_cursor, two_norm_at.call(tv_blank))
	_settle_blank(inst, tv_cont, two_norm_at.call(tv_blank))   # AC 4B：喂到 TargetView 空白（EMA 收敛）
	_feed_left(f_two, two_norm_at.call(tv_blank))
	_feed_left(f_two, two_norm_at.call(tv_blank))
	check(router.get("_active_panel") == tv_cont and _btn_events(true).size() == 0,
		"⑧ 批次 AC 4B §4.6-1：视口空白二指单击 → 仅绑定（蓝框点亮/零交互），旧「非激活面板首笔仅激活」等价改写")
	check_eq(String(router.get("_level_mode")), "SELECT_ARMED",
		"⑧ 批次 AC 4B：绑定当笔不进入旋转（态 0→态 1 单步迁移）")
	mock.calls.clear()
	# ---- 段 B. 态 1 空白 → 清选+ORBIT（4 checks）----
	# 批次 AC 4B 等价改写：先把绑定切到 MainView——须在 **MainView 空白处**单击（旧「容器中心
	# 切换笔零交互」随显式绑定重构：中心命中木料，块上起笔零动作不绑定）。
	inst.call("clear_selection")
	_settle_blank(inst, cont, blank_norm)   # AC 4B：跨视口切换前喂到 MainView 空白（EMA 收敛）
	_feed_left(f_two, blank_norm)
	_feed_left(f_two, blank_norm)
	check(router.get("_active_panel") == cont and _btn_events(true).size() == 0,
		"段 B 前置：MainView 空白单击 → 绑定切至主视图（块上起笔不绑定=AC 4B 显式绑定判据）")
	mock.calls.clear()
	inst.call("select_voxel", found[0][0], true)
	check((inst.call("get_selected_voxels") as Array).has(found[0][0]), "段 B 前置：备选 1 格")
	_feed_left(f_cursor, blank_norm)
	_feed_left(f_two, blank_norm)
	_feed_left(f_two, blank_norm)
	# 批次 AD §4.3.1 等价改写：空白二指双帧仅入 ORBIT_PENDING，按住拖拽 >15px（content 口径，
	# 此处 Δnorm=30px/视口宽经 _content 还原≈30px>15）才正式切入 ORBIT——清选/提示行随正式进入
	# 触发（旧「空白双帧即 ORBIT+清选」判据整体后移至拖拽帧，语义主体「进旋转=清选+提示」保持）。
	_feed_left(f_two, blank_norm + Vector2(30.0 / get_root().get_visible_rect().size.x, 0.0))
	check((inst.call("get_selected_voxels") as Array).is_empty(), "T10①：SELECT_ARMED 空白 two_down+拖拽越阈 → clear_selection 生效（§4.3.1 清选随正式进 ORBIT）")
	check_eq(_btn_events(true).size(), 0,
		"AC 4B §4.6-2：空白点击 → 零合成事件（旧「合成按下进旋转笔」随不限框语义旋转直驱退役）")
	check_eq(String(router.get("_level_mode")), "ORBIT", "T10①：mode=ORBIT")
	var rings: Array = _ring_events()
	check_eq(rings.size(), 0, "N15 等价改写（批次 W4 拍板 10）：T10① 光标圈琥珀 set_ring_color 断言随环删退役 → 零环色调用（光标恒手别色）")
	check_eq(String((inst.get_node("HintLabel") as Label).text), String(inst.ORBIT_HINT_TEXT),
		"N15 等价改写：ORBIT 进入 → 提示行（批次 AA W3-5 起=「【左】旋转模式：二指再点空白退出」同源比较；进出 ORBIT 光标色零变化由 test_w_gesture_level 段 A 锁定）")
	mock.calls.clear()
	# ---- 段 C. ORBIT 块上 → 静默；ORBIT 空白 → 回待命（5 checks；P0-3 段序修正：
	# 先趁段 B 遗留的 ORBIT 态测块上静默，再测空白回待命——原序空白先行会把 mode 切回，
	# 块上断言 "ORBIT" 不可能成立）----
	_feed_left(f_two, cell_norm)
	_feed_left(f_two, cell_norm)
	check_eq(_btn_events(true).size() + _btn_events(false).size(), 0, "T10③：ORBIT 块上 two_down → 静默忽略（防误选；须先点空白切回）")
	check_eq(String(router.get("_level_mode")), "ORBIT", "T10③：ORBIT 态保持（块上不切态）")
	mock.calls.clear()
	# 批次 AD §4.3.1 等价改写：ORBIT 退出途径更新为「松开中指（two→cursor，发 two_up）即时自然
	# 退出」回 SELECT_ARMED（旧 §4.6-2「收中指保持旋转、仅空白二指单击退出」口径反置）。本段
	# 从段 C 遗留 ORBIT 态喂 cursor 收中指 → 自然退出，零合成事件（旧「空白 two_down 退出」判据
	# 语义主体「旋转态可干净退待命」保持；旧值留痕：cursor+two+two→SELECT_ARMED）。
	_feed_left(f_cursor, blank_norm)   # 松中指 → two_up → §4.3.1 自然退出
	check_eq(_btn_events(true).size() + _btn_events(false).size(), 0, "T10②：ORBIT 自然退出 → 零合成事件（不拖拽不清选）")
	check_eq(String(router.get("_level_mode")), "SELECT_ARMED", "T10②：ORBIT 松中指 → 自然退出回待命（§4.3.1）")
	var rings2: Array = _ring_events()
	check_eq(rings2.size(), 0, "N15 等价改写：T10② reset_ring_color 断言随环删退役 → 零环色调用")
	check_eq(String((inst.get_node("HintLabel") as Label).text), String(inst.HINT_OPERATIONS),
		"N15 等价改写：ORBIT 退出 → 提示行还原常驻操作提示")
	mock.calls.clear()
	# ---- 段 D. 立即按下（批次 X P5-a 等价替换，spec §6：dwell 0.3s/28px 悬停确认退役——
	# 旧 5 checks 悬停确认/取消路径断言随机制废止；新契约=块上 two_down 双帧后同批喂帧内
	# 立即合成左键按下，two_up 成对抬起）----
	mock.calls.clear()
	_feed_left(f_cursor, cell_norm)
	_feed_left(f_two, cell_norm)
	_feed_left(f_two, cell_norm)
	check(_btn_events(true).size() == 1 and _btn_events(false).size() == 0,
		"X4：SELECT_ARMED 块上 two_down 双帧 → 立即合成左键按下恰一次（无 dwell 等待；旧「进 dwell 不立即按下」断言等价替换留痕）")
	_feed_left(f_two, cell_norm)   # two_move（同格无位移语义）
	check_eq(_btn_events(true).size() + _btn_events(false).size(), 1, "X4：two_move 不追加合成事件（旧 dwell 28px 复核窗口随机制退役）")
	_feed_left(f_cursor, cell_norm)   # 收中指 → two_up 抬起
	check_eq(_btn_events(false).size(), 1, "X4：two_up → 合成抬起恰一次（笔画成对；旧「two_up 取消 dwell」路径随 dwell 退役）")
	mock.calls.clear()
	# 重伸二指：再按立即派发（无冷却窗——旧 0.8s SELECT_COOLDOWN 退役实证）
	_feed_left(f_two, cell_norm)
	_feed_left(f_two, cell_norm)
	check_eq(_btn_events(true).size(), 1, "X4：抬起后立即重按 → 恰一次新按下（0.8s 冷却退役，旧冷却期整段静默已废）")
	_feed_left(f_cursor, cell_norm)   # 收中指结束笔画
	mock.calls.clear()
	# ---- 段 E. 空白点击零阻碍（批次 X P5-a 等价替换：旧冷却期静默/冷却过期恢复两断言
	# 随 SELECT_COOLDOWN 退役——空白清选+ORBIT 即时可达，无卡死路径）。
	# 批次 AC 4B（§4.6-2）二次等价改写：进 ORBIT 不再合成按下（旋转改由 orbit_rotate_panel
	# 语义直驱、不限框），故「1 次合成按下」断言改为「零合成事件 + 清选 + ORBIT 即时可达」。----
	_feed_left(f_cursor, blank_norm)
	_feed_left(f_two, blank_norm)
	_feed_left(f_two, blank_norm)
	# 批次 AD §4.3.1 等价改写：空白点击不再即时进 ORBIT——双帧入 ORBIT_PENDING 后须拖拽 >15px
	# 才正式 ORBIT（旧「ORBIT 即时可达，无冷却延迟」→ 新「拖拽越阈即达，仍无冷却延迟」）。
	_feed_left(f_two, blank_norm + Vector2(30.0 / get_root().get_visible_rect().size.x, 0.0))
	check_eq(_btn_events(true).size() + _btn_events(false).size(), 0,
		"AC 4B §4.6-2：块上笔画后空白 two_down → 零合成事件（旧「合成按下进旋转笔」随不限框直驱退役）")
	check((inst.call("get_selected_voxels") as Array).is_empty(),
		"X4/AC 4B：空白 two_down → 即时清选（旧冷却静默段退役留痕；P2-10 备案语义随之消除）")
	check_eq(String(router.get("_level_mode")), "ORBIT", "X4→AD §4.3.1：空白二指拖拽 >15px → ORBIT 可达（无冷却延迟）")
	_feed_left(f_cursor, blank_norm)
	mock.calls.clear()
	# ---- 段 F. reset 复位（批次 X P5-a 等价替换：dwell 成员退役——复位断言改查笔画标志）----
	router.reset_runtime()
	check_eq(String(router.get("_level_mode")), "SELECT_ARMED", "T10⑥：reset_runtime 后 mode=SELECT_ARMED")
	check(bool(router.get("_dwell") == null) and bool(router.get("_left_stroking")) == false
		and bool(router.get("_right_stroking")) == false,
		"X4：reset 后 dwell 成员退役（get=null）且左右笔画标志清零（旧「dwell 清空」断言等价替换留痕）")
	inst.queue_free()
	_cleanup_save()
	finish()
