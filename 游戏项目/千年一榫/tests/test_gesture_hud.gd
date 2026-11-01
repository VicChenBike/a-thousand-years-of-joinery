extends "res://tests/test_base.gd"
## 批次 R 判定用例（重构后）→ 批次 S 等价替换留痕：控制台挂载 + 加载提示 + 可见性联动。
## 批次 S：StatusRow HBox→VBox、GuideHeader/GuideList 移入 GuidePanel/GuideVBox（容器化 S1）、
## 状态文本删「左手：」前缀（S6）；其余段（加载提示/UNAVAILABLE toast/倒数弹窗/可见性）原样保留。
## 契约来源：批次 R spec §7.2（BOOT 隐藏/右下加载提示）、§7.3（显隐总开关）、§8.3-1/3（Q3 门控/
## UNAVAILABLE toast 一次）。旧表（8 行 GESTURE_TABLE）与拖拽断言随重构删除（spec §14-①/⑨）。
## 环境说明：--script 无头 autoload 不触发 _ready；主脚本经 get_root().get_node 动态引用。

const SCENE_PATH := "res://scenes/shared/gesture_hud.tscn"
const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"

func _cleanup() -> void:
	for p: String in [ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(FLAG_PATH)]:
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
const DISC_BK_PREFIX := "user://_r2b_ghu_backup_"
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
	print("EVID|user_restore|ghu|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_gesture_hud ==")
	_backup_user()
	var save: Variant = get_root().get_node("SaveManager")
	var bridge: Variant = get_root().get_node("GestureBridge")
	var theme_mgr: Variant = get_root().get_node("ThemeManager")
	theme_mgr._dark_theme = load("res://themes/theme_dark.tres")
	# 批次 AB-3：深浅主题机制删除——_light_theme/_last_dark 注入退役（恒深档）。
	_cleanup()
	save.load_game()

	# ---- 1. 场景存在 + 新结构（旧节点 ListToggle/GestureList 已删）----
	check(ResourceLoader.exists(SCENE_PATH), "gesture_hud.tscn 存在")
	var hud: Control = load(SCENE_PATH).instantiate()
	add_child(hud)
	await process_frame
	await process_frame
	check(hud.get_node_or_null("CameraWindow") is TextureRect, "控制台：CameraWindow 存在")
	check(hud.get_node_or_null("StatusRow") is VBoxContainer, "控制台：StatusRow 存在（批次 S 容器化：状态列 VBox）")
	check(hud.get_node_or_null("GuidePanel/GuideVBox/GuideHeader/FoldBtn") is Button, "控制台：FoldBtn 存在（批次 S：GuidePanel 容器化）")
	check(hud.get_node_or_null("GuidePanel/GuideVBox/GuideList") is GridContainer, "控制台：GuideList 存在（批次 S：GuidePanel 容器化；批次 U 偏离②：VBox→GridContainer 承载 LEVEL 双列，等价替换留痕）")
	check_eq(int((hud.get_node("CameraWindow") as TextureRect).expand_mode), 1, "S5：CameraWindow expand_mode=1（批次 S）")
	check(hud.get_node_or_null("VBox/ListToggle") == null, "旧表入口 ListToggle 已删（spec §14-①）")
	check(hud.get_node_or_null("VBox/GestureList") == null, "旧 8 行对照表容器已删")
	# ---- 批次 T（TE-2，T2 字号提级 +3）：tscn/gd 注入口径锚定 ----
	check_eq(int((hud.get_node("StatusPanel/StatusLineBox/StatusLine") as Label).get_theme_font_size("font_size")), 13,
		"T2：紧凑状态行 STATUS_FONT=13（tscn 11→13 等价替换留痕）")
	check_eq(int((hud.get_node("CameraWindow/CameraHint") as Label).get_theme_font_size("font_size")), 15,
		"T2：占位字 13→15（等价替换留痕）")
	check_eq(int((hud.get_node("GuidePanel/GuideVBox/GuideHeader/FoldBtn") as Button).get_theme_font_size("font_size")), 14,
		"T2：折叠钮字号 12→14（等价替换留痕；gd _apply_panel_bg 覆写生效需 await 帧）")

	# ---- 2. 状态刷新（沿用桥订阅；批次 AA W2-10 等价改写：行 2 显示名由 python gesture 名
	# 改为语义层动作名（与 GestureMap._classify 同源）——本包无 fingers/未进语义态 → 「待命」；
	# 旧断言「显示 open_palm」（python _classify_gesture 双轨名）随 W2-10 退役留痕）----
	bridge.simulate_packet('{"timestamp":1.0,"left":{"gesture":"open_palm","confidence":0.9},"right":null}')
	check_eq(String((hud.get_node("StatusRow/LeftPanel/VBox/LeftLabel") as Label).text), "待命", "W2-10：桥收包 → 左手状态名=语义层动作名（本包未进语义态→待命；旧显 python gesture 名 open_palm 留痕）")
	check_eq(String((hud.get_node("StatusRow/RightPanel/VBox/RightConf") as Label).text), "未检出", "无手侧「未检出」")
	hud.queue_free()

	# ---- 3. main.tscn 挂载验证（控制台实例化 + 光标层挂载 + 主题显式赋值）----
	_cleanup()
	save.load_game()
	bridge._set_state(0)  # 回到 LOADING 模拟冷启动（第 2 段 simulate_packet 曾置 READY；旧用例同款 _set_state 手法）
	var main: Node = load(MAIN_SCENE_PATH).instantiate()
	add_child(main)
	await process_frame
	await process_frame
	# 批次 U 等价替换（UB-5）：GlobalUI/GestureHUDMount → GestureHUDLayer/GestureHUDMount
	#（HUD 迁独立层 layer=64，spec §4-U5⑧；旧路径留痕）
	var mount_node: Node = main.get_node_or_null("GestureHUDLayer/GestureHUDMount")
	check(mount_node is Control, "main：GestureHUDMount(Control) 存在（GestureHUDLayer 下）")
	check(mount_node != null and mount_node.get_child_count() >= 1, "main：_ready 已实例化控制台")
	var hud_in_main: Control = null
	if mount_node != null and mount_node.get_child_count() >= 1:
		hud_in_main = mount_node.get_child(0)
	if hud_in_main != null:
		check(hud_in_main.theme == theme_mgr.current_theme(), "挂载主题：控制台已显式赋当前主题（跨 CanvasLayer 不传播）")
	var cursor_layer: Node = main.get_node_or_null("GestureCursorLayer")
	check(cursor_layer != null, "main：GestureCursorLayer 已挂载（批次 R §2.4）")

	# ---- 4. 加载提示（§7.2 BOOT 行 + §8.3-3）：无头 start 不拉起 → 状态维持 LOADING → 提示可见 ----
	check_eq(int(bridge.get_load_state()), 0, "无头启动：start_gesture_process 不真拉起，状态维持 LOADING")
	var tip: Label = main.get_node("GlobalUI/GestureLoadingTip")
	# 批次 Z（Z5-7）等价改写：静态「手势交互正在加载中」→「手势交互加载中」+3→2→1 动态点
	#（文案/点序/步进断言归 test_z_gesture_thresholds 段 5，此处锁基座文案与可见性联动回归）
	check(String(tip.text).begins_with("手势交互加载中"),
		"LOADING：右下加载提示基座=「手势交互加载中」（旧「手势交互正在加载中」拍板退役）实际「%s」" % String(tip.text))
	check_eq(String(tip.text), String(main.LOAD_TIP_DOTS[0]),
		"LOADING：提示文本=动态点起点常量（3 点档；单点常量处供 Z5 替换）")
	check(tip.visible, "LOADING：提示可见")
	bridge._set_state(1)  # READY
	check(not tip.visible, "READY：加载提示隐藏、被控制台取代（§7.3）")
	# UNAVAILABLE：主菜单 toast 一次（标志位防重复）
	var toast_count_before: int = 0
	main._update_loading_tip(2)
	check(bool(main._gesture_unavailable_toasted), "UNAVAILABLE：置每进程一次标志")
	main._update_loading_tip(2)
	check(bool(main._gesture_unavailable_toasted), "重复 UNAVAILABLE 不再触发（toast 一次）")
	# 附带回修 P2-3：UNAVAILABLE 非主菜单发生 → 只置待提示标志不直接 toast（回主菜单补提示）
	var game_node: Node = get_root().get_node("Game")
	main._gesture_unavailable_toasted = false
	game_node._state = game_node.State.OPENING_MOVIE  # 直写模拟非主菜单态（无头测试，goto_state 会真路由）
	main._update_loading_tip(2)
	check(bool(main._gesture_unavailable_pending) and not bool(main._gesture_unavailable_toasted),
		"P2-3：UNAVAILABLE 非主菜单 → 置待提示标志、不直接 toast（回主菜单补提示一次）")
	game_node._state = game_node.State.MAIN_MENU  # 复位现场
	main._gesture_unavailable_pending = false
	main._gesture_unavailable_toasted = true

	# ---- 5. 可见性总开关（§7.3）——批次 V 等价替换（V7，spec §4.1）：可见门单一真值
	# gesture_hud_visible ∧ gesture_input（旧 OR 半支「or camera_enabled」废除——批次 U Q2
	# 「摄像头开而手势关仍可见」语义退役；手势关=整组隐，摄像头设备保持后台运行语义不变）
	# ---- 批次 Y（Y-A20）等价改写：main 门升级三真值（第三支=camera_stream_open）——
	# 「重开恢复」行需注入开启真值（camera_opened 事件）方可见；隐藏行不受影响 ----
	save.update_settings({"gesture_input": false, "gesture_camera_enabled": false})
	check(hud_in_main != null and not hud_in_main.visible, "手势交互与摄像头双关 → 控制台隐藏（Q4；旧「手势开关关即隐」随 U4 新语义等价替换）")
	save.update_settings({"gesture_hud_visible": false})
	check(hud_in_main != null and not hud_in_main.visible, "显示区开关关 → 控制台隐藏")
	save.update_settings({"gesture_hud_visible": true, "gesture_input": true})
	bridge.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "HD Camera"}))
	await process_frame
	check(hud_in_main != null and hud_in_main.visible, "重开恢复（Y2：三真值齐备——含 camera_opened 注入的开流真值）")

	# ---- 6. 批次 R（spec §6.2）：手势退出倒数弹窗挂载与 Router 接线 ----
	# 批次 Y（Y-A2）：屏幕正中卡片退役改顶部居中长条，正文按 spec 文案口径「还需翻转 N 次」
	#（旧「【双手】再翻转 N 次…」随拍板退役；节点路径 Card/VBox/Body 保留）。
	# 修复6（批次Z走查 P2 评估=安全迁移）：倒数弹条迁独立 CanvasLayer（layer=66>TopStrip 63
	# ——4.5s 倒数窗内恰来对接失败 info 时 TopStrip 不再盖倒数条；66≠光标 101/光晕 100/
	# HUD 64/下拉 65/外框 128 消同 index 序 non-determinism；父仍为 CanvasLayer 全屏锚点
	# 几何零变化、主题挂载显式赋值口径不变、TALK/SETTLE 偏移读 Game 态与父无关）。
	var ged: Node = main.get_node_or_null("ExitDialogLayer/GestureExitDialog")
	check(ged != null, "main：GestureExitDialog 已挂独立 ExitDialogLayer（修复6 迁移；红态=仍在 GlobalUI）")
	check(main.get_node_or_null("GlobalUI/GestureExitDialog") == null,
		"修复6：GlobalUI 下不再有 GestureExitDialog（旧挂载点清退）")
	var strip_layer_ref: Node = main.get_node_or_null("TopStripLayer")
	var exit_layer_ref: Node = main.get_node_or_null("ExitDialogLayer")
	check(exit_layer_ref != null and exit_layer_ref is CanvasLayer,
		"修复6：ExitDialogLayer 为 CanvasLayer")
	if exit_layer_ref != null and strip_layer_ref != null:
		check(int(exit_layer_ref.get("layer")) > int(strip_layer_ref.get("layer")),
			"修复6：倒数弹条层号(%d) > TopStrip 层号(%d) → info 条不得盖倒数条"
			% [int(exit_layer_ref.get("layer")), int(strip_layer_ref.get("layer"))])
		check(int(exit_layer_ref.get("layer")) != 101,
			"修复6：层号≠101（手势光标层 Z6-P3-4 现状协调，避同 index）")
	if ged != null:
		check(ged.visible == false, "倒数弹条初始隐藏")
		ged.call("show_countdown", 3)
		check(ged.visible and String((ged.get_node("Card/VBox/Body") as Label).text) == "还需翻转 3 次", "Y-A2：首显正文「还需翻转 3 次」（spec 文案口径）")
		ged.call("update_countdown", 2)
		check(String((ged.get_node("Card/VBox/Body") as Label).text) == "还需翻转 2 次", "Y-A2：刷新正文「还需翻转 2 次」")
		var card: Control = ged.get_node("Card") as Control
		check(is_equal_approx(float(card.get("anchor_top")), 0.0) and is_equal_approx(float(card.get("anchor_left")), 0.5),
			"Y-A2：Card 顶部居中锚点（anchor_top=0/anchor_left=0.5——屏幕正中卡片退役）")
		ged.call("close_countdown")
		check(not ged.visible, "取消/确认后关闭")
	var router_node: Node = get_root().get_node_or_null("GestureRouter")
	if router_node != null:
		check(bool(router_node.countdown_started.is_connected(main._on_gesture_countdown_started)),
			"Router.countdown_started 已接 main（弹窗驱动）")
		check(bool(router_node.exit_confirmed.is_connected(main._on_gesture_exit_confirmed)),
			"Router.exit_confirmed 已接 main（关弹窗后分流）")

	# ---- 批次 U 段（U4-④/U5②，spec §4-U4/§4-U5）：可见门真值表＋废止件＋折叠往返（10 checks）----
	# 可见门真值表（gesture_hud 自身门；main.gd:350 第二道门的集成真值表归 test_u_dock_anchors 段 6）
	var hud_gate: Node = mount_node.get_child(0)
	var gate_cases := [
		# [gesture_input, camera_enabled, hud_visible, 期望可见]（.get 默认值同源：input=T/cam=F/hud=T）
		# 批次 V 等价替换（V7，spec §4.1）：门=gesture_hud_visible ∧ gesture_input——旧 Q2 行
		# [false,true]→true（OR 半支）废除，改期望 false（手势关=整组隐，摄像头后台运行语义不变）
		[true, false, true, true],
		[true, true, true, true],
		[false, true, true, false],   # 批次 V：手势关=整组隐（即便摄像头开；旧 Q2「可见」等价替换留痕）
		[false, false, true, false],  # Q4：双关 → 隐藏
		[true, false, false, false],  # 显示区开关关 → 隐藏
	]
	for c: Array in gate_cases:
		save.update_settings({"gesture_input": c[0], "gesture_camera_enabled": c[1], "gesture_hud_visible": c[2]})
		hud_gate.apply_dock_state(int(game_node.State.MAIN_MENU), false, false)
		check_eq(bool(hud_gate.visible), bool(c[3]),
			"U4：可见门 input=%s cam=%s hud=%s → %s" % [c[0], c[1], c[2], c[3]])
	# 批次 V（V7，spec §4.1）：摄像头窗子件门——可见 ⇔ 整组 ∧ camera_enabled（子件式追加断言；
	# hud_visible 一并复位——上一真值表末例置 false 会早退绕过子件门）
	# 批次 W（N3）等价改写：摄像头窗占位常驻——旧 V7 子件门「整组 ∧ camera_enabled」语义废止
	# （W3 探针实证该门读值 falsy 即窗隐=首启占位缺失根因）；「窗隐」断言反转为「窗恒显」，
	# 整组门（本文件段 1 真值表）不受影响。留痕：旧断言 1 条语义翻转，计数不变。
	save.update_settings({"gesture_input": true, "gesture_camera_enabled": false, "gesture_hud_visible": true})
	hud_gate.apply_dock_state(int(game_node.State.MAIN_MENU), false, false)
	check(bool(hud_gate.camera_window.visible),
		"W-N3：手势开+摄像头关 → 窗仍显（占位常驻；旧「窗隐」子件门语义废止留痕）")
	save.update_settings({"gesture_input": true, "gesture_camera_enabled": false, "gesture_hud_visible": true})
	# BOOT 档：显式驱动 BOOT 断言自身门恒隐（防坑 1：--script 模式 Game 真实态经上一段 goto 已是 MAIN_MENU，
	# 须显式 apply_dock_state(BOOT) 取 BOOT 语义——磁盘实况校正计划文本「fresh main 实例 state=BOOT」的假设）
	hud_gate.apply_dock_state(int(game_node.State.BOOT), false, false)
	check_eq(bool(hud_gate.visible), false, "U4：BOOT 档整组隐藏（st != BOOT 门保留）")
	# 废止件（U5②）：fold_restore 整组复原钮废止、LvToggleBtn 退役删除
	check(hud_gate.get_node_or_null("FoldRestore") == null, "U5②：FoldRestore 废止删除（fold_restore 整组折叠语义废止）")
	check(hud_gate.get_node_or_null("StatusPanel/StatusLineBox/LvToggleBtn") == null, "U5②：LvToggleBtn 退役删除（说明栏顶缘收起钮并轨）")
	# 主菜单折叠往返（批次 V 等价替换 V13，spec §7.2：折叠竖条化——旧 P0-1「header 恒显承载
	# FoldBtn」方案随竖条退役留痕；展开钮统一为竖条顶部 hint_fold_btn，收起后可再展开不锁死）
	hud_gate.apply_dock_state(int(game_node.State.MAIN_MENU), false, false)   # BOOT 断言后回主菜单档
	hud_gate._folded = false
	hud_gate._on_fold_pressed()
	await process_frame
	check(not bool(hud_gate.guide_header.visible) and not bool(hud_gate.guide_list.visible) \
			and bool(hud_gate.hint_fold_btn.visible),
		"V13：主菜单收起 → header 随竖条退役＋guide_list 隐＋HintFoldBtn 可点（旧「header 恒显」等价替换留痕）")
	check((hud_gate.guide_panel.size as Vector2).round().x <= 32.0,
		"V13：主菜单折叠态=竖条（宽≤32 档；旧横条等价替换留痕）")
	hud_gate.hint_fold_btn.pressed.emit()   # 批次 V：竖条 ▲/▼ 钮归一路由（主菜单→_on_fold_pressed 存档语义）
	await process_frame
	check(bool(hud_gate.guide_list.visible), "V13：再点竖条钮 → 展开恢复（收起→展开往返成立；旧「再点 FoldBtn」等价替换）")
	save.update_settings({"gesture_panel_folded": false})   # 折叠写档还原（_on_fold_pressed 落盘）

	# ---- 批次 W（P2-9）新段：SETTLE 停靠一帧重排（规格 §5）----
	# mark_settle_entered() 只改 _state 不发 state_changed（P-D 记账语义），旧 _process 轮询
	# 只比对 is_settings_open/is_shop_open → SETTLE 迁移恒漏、HUD 顶着 LEVEL 布局。修复后
	# 轮询比对含 current_state：状态差即 apply_dock 重排（无头手推 _process 0.6s 过轮询窗）。
	hud_gate.apply_dock_state(int(game_node.State.LEVEL), false, false)
	game_node.mark_settle_entered()
	hud_gate._process(0.6)
	check_eq(int(hud_gate.get("_dock_st")), int(game_node.State.SETTLE),
		"P2-9：mark_settle_entered 后一帧轮询停靠表重排为 SETTLE 配置（无新信号面，比对处扩展）")
	game_node.set("_state", int(game_node.State.MAIN_MENU))   # 状态机复位（直改不发信号，防下游态污染）

	main.queue_free()
	await process_frame
	_cleanup()
	finish()
