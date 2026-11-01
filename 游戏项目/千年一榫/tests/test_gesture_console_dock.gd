extends "res://tests/test_base.gd"
## 批次 T 判定用例（重写，替换批次 S 114 checks——逐段台账见 plan §7 TE-3）：
## 结构契约 + STOP 穿透例外 + MAIN_MENU 细节 + 折叠 + 终态停靠（与 test_t_dock_expand 分工：
## 本文件守结构/折叠/主菜单细节与占位联动；t_dock_expand 守七态全量矩形与不相交；
## t_hint_rows 守文案/字号/色值）。
## 批次 U 等价替换（UB-6，条数不变 0 净）：全部 648 基线绝对坐标断言 → hud._dock_cfg(key)
## 描述符换算（_expected_rect 同式，spec §4-U5 表锚定终态）；LvToggleBtn/FoldRestore 结构断言
## 退役改缺席；STOP 三钮→二钮（FoldBtn+HintFoldBtn，U5② 并轨）；折叠段改「只收说明栏」新语义；
## GuideList VBox→GridContainer cast（偏离②）。

const HUD_SCENE := "res://scenes/shared/gesture_hud.tscn"
const SAVE_PATH := "user://save.json"
const STATE := {"MAIN_MENU": 1, "OPENING_MOVIE": 2, "TALK": 3, "LEVEL": 4, "SETTLE": 5, "CATALOG": 6}
const WIN := Vector2(1152, 648)

func _expected_rect(d: Dictionary) -> Rect2:
	# 批次 U 等价替换：描述符 → 窗相对矩形（参考 test_u_dock_anchors 同式 helper）
	var sz: Vector2 = d["size"]
	var x: float = float(d["mx"]) if d["ax"] == "L" else WIN.x - float(d["mx"]) - sz.x
	var y: float = float(d["my"]) if d["ay"] == "T" else WIN.y - float(d["my"]) - sz.y
	return Rect2(x, y, sz.x, sz.y)

func _rect(n: Control) -> Rect2:
	return Rect2(n.global_position.round(), n.size.round())

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
const DISC_BK_PREFIX := "user://_r2b_gcd_backup_"
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
	print("EVID|user_restore|gcd|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_gesture_console_dock ==")
	_backup_user()
	var save: Variant = get_root().get_node("SaveManager")
	var game: Variant = get_root().get_node("Game")   # 无头预置用：折叠/浮层开关写档语义依赖真实状态机（Game._state 恒 BOOT，批次 S 先例）
	var p: String = ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
	save.load_game()
	check(ResourceLoader.exists(HUD_SCENE), "gesture_hud.tscn 存在")
	var hud: Control = (load(HUD_SCENE) as PackedScene).instantiate()
	add_child(hud)
	await process_frame
	await process_frame
	# 批次 U 实证坑（tmp_probe_layer_size / test_u_dock_anchors 同款）：无头 expand 撑
	# 1152×1152，底锚（ay=B）依赖 HUD 根尺寸——**add 后补钉**设计视口再等两帧（磁盘实况校正）
	get_root().size = Vector2i(int(WIN.x), int(WIN.y))
	await process_frame
	await process_frame
	# 批次 Y 收口微修（UF-1 先例等价注入补齐）：507ad79 三真值门——apply_dock_state 收口
	# `visible = visible and GestureBridge.is_camera_stream_open()`（场景切换旁路复活根除，
	# 有意生产行为变更）。本件原无 camera_opened 注入 → 无头无流环境整组被隐藏 → 容器排序
	# 子件（S3 状态列次块）几何停滞＋T15「SHOP 整组可见」假红。补与 test_v_hud_gate 同款
	# 事件注入，使几何/可见断言在「流开启」前提下按原语义验证（非弱化；段 8「S4：BOOT 隐藏」
	# 期望隐断言走早退分支不经该门，不受扰）。
	get_root().get_node("GestureBridge").simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "HD Camera"}))
	await process_frame
	# ---- 段 1. 结构契约（14 checks；BarColumn 2 条→缺席 1 条留痕；LvToggleBtn/FoldRestore 退役等价替换）----
	var cam: TextureRect = hud.get_node("CameraWindow")
	check(cam is TextureRect, "摄像头窗 CameraWindow(TextureRect) 存在")
	check_eq(int(cam.expand_mode), 1, "S5：expand_mode=1（沿用）")
	check_eq(int(cam.stretch_mode), 5, "S5：stretch_mode=5（沿用）")
	check(hud.get_node_or_null("StatusRow") is VBoxContainer, "状态列 StatusRow(VBox) 存在")
	check(hud.get_node_or_null("StatusRow/LeftPanel") is Panel, "左手状态块存在")
	check(hud.get_node_or_null("StatusRow/RightPanel") is Panel, "右手状态块存在")
	check(hud.get_node_or_null("StatusPanel/StatusLineBox/StatusLine") is Label, "紧凑状态行存在")
	# 批次 U 等价替换：LvToggleBtn 存在断言 → 退役缺席（说明栏顶缘收起钮并轨，U5②）
	check(hud.get_node_or_null("StatusPanel/StatusLineBox/LvToggleBtn") == null, "U5②：LvToggleBtn 退役删除（旧「LEVEL 说明开关钮存在」等价替换留痕）")
	check(hud.get_node_or_null("BarColumn") == null, "T14：BarColumn 已删（旧 BarLeft/BarRight 2 条等价替换为缺席断言）")
	check(hud.get_node_or_null("GuidePanel") is PanelContainer, "说明栏 GuidePanel(PanelContainer) 存在")
	check(hud.get_node_or_null("GuidePanel/GuideVBox/GuideHeader/FoldBtn") is Button, "折叠钮 FoldBtn 存在")
	# 批次 U 偏离②：GuideList VBoxContainer→GridContainer（LEVEL 双列承载）cast 等价替换
	check(hud.get_node_or_null("GuidePanel/GuideVBox/GuideList") is GridContainer, "说明行容器 GuideList 存在（批次 U 偏离②：VBox→GridContainer 等价替换）")
	# 批次 U 等价替换：FoldRestore 存在断言 → 废止缺席（U5② 整组复原钮退役）
	check(hud.get_node_or_null("FoldRestore") == null, "U5②：FoldRestore 废止删除（旧「整组折叠恢复钮存在」等价替换留痕）")
	check(hud.get_node_or_null("HintFoldBtn") is Button, "U5②：说明栏收起钮 HintFoldBtn 存在（顶缘钮 overlay，偏离①）")
	check_eq(int(hud.mouse_filter), 2, "根容器 mouse_filter=IGNORE")
	# ---- 段 2. STOP 穿透例外（2 checks；批次 U：三钮→二钮，FoldRestore/LvToggleBtn 退役并轨）----
	var stops: Array = []
	var stack: Array = [hud]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control and int((n as Control).mouse_filter) == 0:
			stops.append(String((n as Control).name))
		for c: Node in n.get_children():
			stack.append(c)
	check_eq(stops.size(), 2, "S1/§4.1：全控制台恰 2 个 STOP（U5② 并轨：旧 FoldBtn/FoldRestore/LvToggleBtn 三钮→FoldBtn/HintFoldBtn 二钮）")
	check(stops.has("FoldBtn") and stops.has("HintFoldBtn"),
		"S1/U5②：STOP 二钮=FoldBtn/HintFoldBtn（旧三钮集合等价替换）")
	# ---- 段 3. MAIN_MENU 细节（9 checks）----
	hud.call("apply_dock_state", STATE["MAIN_MENU"], false, false)
	await process_frame   # plan 代码块自查补：LeftPanel/RightPanel/FoldBtn 矩形由容器排序决定（延迟一帧），旧件 await 先例同款
	var fb: Button = hud.get_node("GuidePanel/GuideVBox/GuideHeader/FoldBtn")
	# 批次 U 等价替换：Rect2(16,462,320,180) → 描述符终态 L16/B14
	check_eq(_rect(cam), _expected_rect(hud._dock_cfg("MAIN_MENU")["cam"]), "S2/S3：摄像头窗 320×180 L16/B14（旧 @(16,462) 等价替换留痕）")
	# 批次 U 等价替换：Rect2(348,462,96,180) → 描述符终态 L348/B14
	check_eq(_rect(hud.get_node("StatusRow")), _expected_rect(hud._dock_cfg("MAIN_MENU")["status"]), "S3：状态列 96×180 L348/B14（旧 @(348,462) 等价替换留痕）")
	check_eq(_rect(hud.get_node("StatusRow/LeftPanel")), Rect2(348.0, WIN.y - 14.0 - 180.0, 96.0, 86.0), "S3：左手块 状态列首块（旧 (348,462)-(444,548) 等价替换：B 锚列 VBox 内容顶排）")
	check_eq(_rect(hud.get_node("StatusRow/RightPanel")), Rect2(348.0, WIN.y - 14.0 - 180.0 + 94.0, 96.0, 86.0), "S3：右手块 状态列次块（旧 (348,556)-(444,642) 等价替换：首块 86+separation 8）")
	# 批次 U 等价替换：Rect2(456,549,352,94) → 描述符终态 L456/B14
	check_eq(_rect(hud.get_node("GuidePanel")), _expected_rect(hud._dock_cfg("MAIN_MENU")["hint"]), "T14/J2：说明栏 352×94 L456/B14（旧 @(456,549) 等价替换留痕）")
	check_eq(fb.size.round(), Vector2(28, 28), "T2：折叠钮 28×28（旧 24×24 留痕）")
	check_eq(int(fb.get_theme_font_size("font_size")), 14, "T2：折叠钮字号 14（旧 12 留痕）")
	check((hud.get_node("GuidePanel/GuideVBox/GuideHeader") as Control).get_rect().encloses(fb.get_rect()),
		"S1：折叠钮整体位于头部行内")
	check_eq(bool(save.get_settings()["gesture_panel_folded"]), false, "默认折叠档=false（沿用）")
	# ---- 段 4. 整组折叠（6 checks；批次 U 等价替换：只收说明栏新语义，条数不变）----
	game.goto_state(game.State.MAIN_MENU)   # 无头预置（goto_state 无头只改状态机+发信号，批次 S 先例）
	fb.pressed.emit()
	check_eq(bool(save.get_settings()["gesture_panel_folded"]), true, "S3：说明栏折叠写档 true（批次 U 语义收窄=只收说明栏）")
	# 批次 V（V13，spec §7.2）：折叠竖条化——header 随竖条退役（旧 P0-1「header 恒显承载 FoldBtn」
	# 方案废止留痕），展开钮统一为竖条顶部 hint_fold_btn（所有场景可再展开，死路不回退）
	check(not (hud.get_node("GuidePanel/GuideVBox/GuideHeader") as Control).visible
		and not (hud.get_node("GuidePanel/GuideVBox/GuideList") as Control).visible
		and (hud.get_node("HintFoldBtn") as Control).visible,
		"V13：折叠态竖条化——header 隐＋guide_list 隐＋HintFoldBtn 可点（旧「header 恒显」等价替换留痕）")
	check(hud.get_node_or_null("FoldRestore") == null, "U5②：恢复钮 FoldRestore 废止（旧「恢复钮可见」等价替换）")
	check_eq(_rect(hud.get_node("GuidePanel")).size.round(),
		Vector2(30.0, (hud._dock_cfg("MAIN_MENU")["hint"]["size"] as Vector2).y),
		"V13：折叠态=竖条（宽 30∈[28,32]、高随场景 cfg hint 高；旧横条 (352,28) 等价替换留痕）")
	hud.get_node("HintFoldBtn").pressed.emit()   # 再点展开（批次 V：竖条 ▲/▼ 钮归一 _on_fold_pressed 存档语义）
	check_eq(bool(save.get_settings()["gesture_panel_folded"]), false, "S3：再点 FoldBtn 写回 false（旧恢复钮写回等价替换）")
	check((hud.get_node("GuidePanel/GuideVBox/GuideList") as Control).visible, "U5②：说明栏展开恢复（旧「三联组恢复显示」等价替换）")
	# ---- 段 5. MOVIE/TALK（4 checks）----
	hud.call("apply_dock_state", STATE["OPENING_MOVIE"], false, false)
	# 批次 U 等价替换：Rect2(912,92,224,126) → 描述符终态 R14/T98；R2 回修 A：T98→T106 整组下移 8px
	check_eq(_rect(hud.get_node("CameraWindow")), _expected_rect(hud._dock_cfg("OPENING_MOVIE")["cam"]), "S4：开场摄像头窗 R14/T106（旧 @(912,92)/T98 等价替换留痕）")
	# 批次 U 等价替换：Rect2(912,222,224,24) → 描述符终态 R14/T230；R2 回修 A：随组 +8
	check_eq(_rect(hud.get_node("StatusPanel")), _expected_rect(hud._dock_cfg("OPENING_MOVIE")["status"]), "S4：开场状态行 R14/T238（旧 @(912,222)/T230 等价替换留痕）")
	# 批次 U 等价替换：Rect2(912,254,224,44) → 描述符终态 R14/T260；R2 回修 A：随组 +8
	check_eq(_rect(hud.get_node("GuidePanel")), _expected_rect(hud._dock_cfg("OPENING_MOVIE")["hint"]), "T14/J2：开场说明栏 224×44 R14/T268（旧 @(912,254)/T260 等价替换留痕）")
	hud.call("apply_dock_state", STATE["TALK"], false, false)
	check_eq(_rect(hud.get_node("CameraWindow")), _expected_rect(hud._dock_cfg("TALK")["cam"]), "S4：对话摄像头窗同开场（描述符终态）")
	# ---- 段 6. LEVEL（8 checks；批次 U：LvToggleBtn 退役→HintFoldBtn 会话级收起钮并轨）----
	game.goto_state(game.State.LEVEL)   # 无头预置：开关钮写会话档→apply_dock() 依赖真实状态（批次 S 先例）
	hud.call("apply_dock_state", STATE["LEVEL"], false, false)
	await process_frame   # plan 代码块自查补：收起钮定位经 apply_dock_state 即时写（延迟一帧保险），旧件 await 先例同款
	# 批次 U 等价替换：Rect2(912,462,224,126) → 描述符终态 R14/T98（旧右下整组废止=LEVEL 漂移根除）；R2 回修 A：T98→T106
	check_eq(_rect(hud.get_node("CameraWindow")), _expected_rect(hud._dock_cfg("LEVEL")["cam"]), "S4：关卡摄像头窗 R14/T106（旧 @(912,462)/T98 等价替换留痕）")
	# 批次 U 等价替换：Rect2(912,592,224,24) → 描述符终态 R14/T230
	check_eq(_rect(hud.get_node("StatusPanel")), _expected_rect(hud._dock_cfg("LEVEL")["status"]), "S4：关卡状态行 R14/T238（旧 @(912,592)/T230 等价替换留痕）")
	check((hud.get_node("GuidePanel/GuideVBox/GuideList") as Control).visible, "T16：说明栏默认展开（旧 gp.visible 断言随 U5② 面板恒显等价替换）")
	# 批次 U 等价替换：Rect2(816,274,320,180) → 描述符终态 R14/T260 双列 368×110；R2 回修 A：随组 +8
	check_eq(_rect(hud.get_node("GuidePanel")), _expected_rect(hud._dock_cfg("LEVEL")["hint"]), "S4/U5④：LEVEL 说明栏双列 368×110 R14/T268（旧 320×180 @(816,274)/T260 等价替换留痕）")
	check((hud.get_node("HintFoldBtn") as Control).visible, "U5②：说明栏顶缘收起钮可见（旧 LvToggleBtn 可见断言等价替换）")
	# 批次 U 等价替换：LvToggleBtn 24×24 @(1104,592) → HintFoldBtn 20×20 说明栏顶缘 overlay（偏离①）
	var hfb: Control = hud.get_node("HintFoldBtn")
	check_eq(hfb.size.round(), Vector2(20, 20), "U5②：收起钮 20×20（旧 LvToggleBtn 24×24 等价替换）")
	check_eq(int((hud.get_node("CameraWindow") as Control).mouse_filter), Control.MOUSE_FILTER_IGNORE,
		"S4：MainView 明示豁免（穿透不挡交互机制=IGNORE 沿用；旧 cam×MainView 几何相交断言随 LEVEL 组迁右上废止，等价替换留痕）")
	hud.get_node("HintFoldBtn").pressed.emit()
	check(not (hud.get_node("GuidePanel/GuideVBox/GuideList") as Control).visible, "U5②：收起钮再点收起说明栏（会话级 _hint_folded；旧 LvToggleBtn 收浮层等价替换）")
	# ---- 段 7. CATALOG/SETTLE（6 checks）----
	hud.call("apply_dock_state", STATE["CATALOG"], false, false)
	# 批次 U 等价替换：Rect2(16,536,144,81) → 描述符终态 L16/B44
	check_eq(_rect(hud.get_node("CameraWindow")), _expected_rect(hud._dock_cfg("CATALOG")["cam"]), "T14：图鉴摄像头窗 L16/B44（旧 @(16,536) 等价替换留痕）")
	# 批次 U 等价替换：Rect2(16,621,144,24) → 描述符终态 L16/B14
	check_eq(_rect(hud.get_node("StatusPanel")), _expected_rect(hud._dock_cfg("CATALOG")["status"]), "T14：图鉴状态行 L16/B14（旧 @(16,621) 等价替换留痕）")
	# 批次 U 等价替换：Rect2(176,540,300,100) → 描述符终态 L172/B14
	check_eq(_rect(hud.get_node("GuidePanel")), _expected_rect(hud._dock_cfg("CATALOG")["hint"]), "T14/J2：图鉴说明栏 300×100 L172/B14（旧 @(176,540) 等价替换留痕）")
	hud.call("apply_dock_state", STATE["SETTLE"], false, false)
	# 批次 U 等价替换：Rect2(24,458,224,126) → 描述符终态 L24/B78
	check_eq(_rect(hud.get_node("CameraWindow")), _expected_rect(hud._dock_cfg("SETTLE")["cam"]), "S4：结算摄像头窗 L24/B78（旧 @(24,458) 等价替换留痕）")
	# 批次 U 等价替换：Rect2(24,588,224,24) → 描述符终态 L24/B48
	check_eq(_rect(hud.get_node("StatusPanel")), _expected_rect(hud._dock_cfg("SETTLE")["status"]), "S4：结算状态行 L24/B48（旧 @(24,588) 等价替换留痕）")
	# 批次 U 等价替换：Rect2(24,616,224,28) → 描述符终态 L24/B14
	check_eq(_rect(hud.get_node("GuidePanel")), _expected_rect(hud._dock_cfg("SETTLE")["hint"]), "T14：结算说明栏 240×140 L24/B14（旧 224×28 @(24,616) 等价替换留痕；_dock_cfg SETTLE hint 同源，批次 AA W3-5 宽 224→240 后消息串同步）")
	# ---- 段 8. SHOP/SETTINGS/BOOT（8 checks）----
	hud.call("apply_dock_state", 1, false, true)
	check((hud as Control).visible, "T15：SHOP 控制台不再整组隐藏（批次 S :198 废止）")
	# 批次 AA（W8-2，spec §11.4-2）：SHOP 改顶部横排（用户「平排」）——消息串随定稿几何同步
	# （旧批次 U/V14 左上三件套 176×99 L16/T88 等价替换留痕，断言本体仍与 _dock_cfg 同源自洽）
	check_eq(_rect(hud.get_node("CameraWindow")), _expected_rect(hud._dock_cfg("SHOP")["cam"]), "T15/W8-2：商店摄像头窗 128×72 L344/T16 顶排首件（批次 V14 176×99 L16/T88 留痕）")
	check_eq(_rect(hud.get_node("StatusPanel")), _expected_rect(hud._dock_cfg("SHOP")["status"]), "T15/W8-2：商店状态行 128×24 L480/T16（旧 L16/T193 留痕）")
	check_eq(_rect(hud.get_node("GuidePanel")), _expected_rect(hud._dock_cfg("SHOP")["hint"]), "T15/W8-2：商店说明栏 300×74 L616/T16 顶排（14/17 专属档 4×18=72；旧 224×88 L200/T88 留痕）")
	hud.call("apply_dock_state", 1, true, false)
	# 批次 U 等价替换：Rect2(826,48,176,99) → 描述符终态 R14/T98；R2 回修 A：T98→T106（设置钮底 102×旧顶 98 实叠 4px 根除，用户「UI 重叠不允许」铁律）
	check_eq(_rect(hud.get_node("CameraWindow")), _expected_rect(hud._dock_cfg("SETTINGS")["cam"]), "T14：设置摄像头窗 R14/T106（旧 @(826,48)/T98 等价替换留痕）")
	# 批次 U 等价替换：Rect2(826,155,176,24) → 描述符终态 R14/T203
	check_eq(_rect(hud.get_node("StatusPanel")), _expected_rect(hud._dock_cfg("SETTINGS")["status"]), "T14：设置状态行 R14/T211（旧 @(826,155)/T203 等价替换留痕）")
	# 批次 U 等价替换：Rect2(826,187,224,66) → 描述符终态 R14/T233
	check_eq(_rect(hud.get_node("GuidePanel")), _expected_rect(hud._dock_cfg("SETTINGS")["hint"]), "T14/J2：设置说明栏 224×66 R14/T241（旧 @(826,187)/T233 等价替换留痕）")
	hud.call("apply_dock_state", 0, false, false)
	check(not (hud as Control).visible, "S4：BOOT 隐藏")
	# ---- 段 9. 置灰废止留痕（2 checks）----
	hud.call("apply_dock_state", STATE["MAIN_MENU"], false, false)
	var a_free := true
	# 批次 U 偏离②：as VBoxContainer → as GridContainer（对 GridContainer 旧 cast 返回 null 挂死，批次 P 坑⑤同族）
	for r: Node in (hud.get_node("GuidePanel/GuideVBox/GuideList") as GridContainer).get_children():
		if float((r as Label).modulate.a) < 0.99:
			a_free = false
	check(a_free, "T3：主菜单行 modulate.a 恒 1.0（旧置灰断言组等价废止留痕）")
	var src: String = FileAccess.get_file_as_string("res://scenes/shared/gesture_hud.gd")
	check(not src.contains("GESTURE_TABLE12"), "T1：12 行固定表废止（旧 12 条逐字断言移交 test_t_hint_rows 留痕）")
	hud.queue_free()
	await process_frame
	finish()
