extends "res://tests/test_base.gd"
## 批次 U 判定用例（U-B 域）：锚定停靠终态（spec §4-U5 八状态几何表逐格）＋两两不相交＋
## 可见门联动＋main.tscn 集成双层可见门真值表（双审 P0-1）＋下拉双开态层级（双审 P1-1）＋
## U10 数值表复核。防坑 3：断言全部经 get_global_rect()（GestureHUDLayer offset 零 → 即窗相对），
## 禁止手工加减 CanvasLayer offset；断言前 await process_frame 两帧（防坑 1）。
## 档位口径（磁盘实况校正）：静态 Game.State 在 --script 模式触发 SaveManager 编译级联失败
## （UB-2 实证，同批 test_t_hint_rows/test_t_dock_expand/test_gesture_console_dock 均用 STATE 字面量），
## 故本件经 get_root().get_node("Game") 动态取枚举→常量表（枚举真序 game.gd:6 SETTLE=5/CATALOG=6）。

const WIN := Vector2(1152, 648)

var save: Node
var main: Node
var hud: Node
var STATE: Dictionary = {}

func _expected_rect(d: Dictionary) -> Rect2:
	# 描述符 → 窗相对矩形（WIN 口径；apply_dock 四值组落位的解析式）
	var sz: Vector2 = d["size"]
	var x: float = float(d["mx"]) if d["ax"] == "L" else WIN.x - float(d["mx"]) - sz.x
	var y: float = float(d["my"]) if d["ay"] == "T" else WIN.y - float(d["my"]) - sz.y
	return Rect2(x, y, sz.x, sz.y)

func _rect_of(node: Control) -> Rect2:
	return node.get_global_rect()

func _no_overlap(a: Rect2, b: Rect2) -> bool:
	return not a.intersects(b)

func _load_main() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	await process_frame
	await process_frame
	# 实证坑（tmp_probe_layer_size 实测，批次 L 先例 test_fix_window_scale:35 同款）：无头
	# --script 下 expand 把 visible_rect 撑 1152×1152（底锚 ay=B 实测 y 恒 +504），且 main._ready
	# 窗口逻辑会改写 root.size（add 后实测 (64,64)）——**add 后补钉** root.size 再等两帧，满锚
	# GestureHUDMount 传播 648 高后锚定四值组才与 WIN 常量同系（磁盘实况校正，不入计划原稿）。
	get_root().size = Vector2i(int(WIN.x), int(WIN.y))
	await process_frame
	await process_frame
	hud = main.get_node_or_null("GestureHUDLayer/GestureHUDMount").get_child(0)

func _items_for(key: String) -> Array:
	# 两两不相交件组：摄像头窗/状态（row 或 panel）/说明栏＋场景对照矩形（TopBar 带/主菜单区）
	var items: Array = [_rect_of(hud.camera_window)]
	if bool(hud.status_row.visible):
		items.append(_rect_of(hud.status_row))
	else:
		items.append(_rect_of(hud.status_panel))
	if hud.guide_panel.visible:
		items.append(_rect_of(hud.guide_panel))
	match key:
		"LEVEL":
			items.append(Rect2(26, 18, WIN.x - 142 - 26, 52))   # TopBar 对照（窗相对右缘 W−142）
		"SETTINGS":
			items.append(Rect2(26, 18, WIN.x - 142 - 26, 52))
		"SHOP":
			# 批次 AA（W8-2，spec §11.4-2）：SHOP 三件改**顶部横排**（y∈[16,90]）后，旧「顶部内容带
			# Rect2(0,0,1152,88) 对照」对其必然相交（件本来就在顶带内）→ 对照矩形换 Content 格网带
			#（y≥92，商店首行卡立绘所在，用户图 2 症状本体）；顶带内容（TopBar 元素）零相交由
			# tests/test_aa_dock_placement.gd 段 3 以运行期实矩形硬锚覆盖。
			items.append(Rect2(0, 92, WIN.x, WIN.y - 92))
		_:
			items.append(Rect2(0, 0, WIN.x, 88))   # 顶部内容带对照
	return items

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
const DISC_BK_PREFIX := "user://_r2b_uda_backup_"
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
	print("EVID|user_restore|uda|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_u_dock_anchors ==")
	_backup_user()
	save = get_root().get_node("SaveManager")
	save.load_game()
	var game_node: Node = get_root().get_node("Game")
	STATE = {
		"MAIN_MENU": int(game_node.State.MAIN_MENU), "OPENING_MOVIE": int(game_node.State.OPENING_MOVIE),
		"TALK": int(game_node.State.TALK), "LEVEL": int(game_node.State.LEVEL),
		"CATALOG": int(game_node.State.CATALOG), "SETTLE": int(game_node.State.SETTLE),
	}
	save.update_settings({"gesture_input": true, "gesture_camera_enabled": false,
		"gesture_hud_visible": true, "gesture_panel_folded": false})
	await _load_main()
	# 批次 Z（Z6 波走查回修，2026-09-24）：冻结 HUD 0.5s 停靠轮询（夹具级，生产轮询语义零改动）——
	# 本件段3/4/5 直驱 apply_dock_state 合成态（Game 活态恒 MAIN_MENU），轮询兜底一旦在 await 窗
	# 内触发即按活态 apply_dock 覆写合成几何 → 恰一个 key 段红（三连单跑复现：SETTLE/SHOP 段红、
	# 实测值=MAIN_MENU 描述符）。阈值实验实证：轮询冻结后 63/63 全绿（ze_guardrail 同波留痕）。
	# 竞态机制=批次 W P2-9「轮询比对加入 Game 当前状态」引入、早于本批；本批仅帧时序微移令 0.5s
	# 边界落入段3 窗内触发表相（:248/:261 既有「轮询干扰甄别」注同根）。负大数冻结：+delta 恒
	# 不达 0.5，段内任何 await 后读数均稳定。
	hud.set("_dock_poll", -100000.0)

	# ---- 段 1. 层结构与常量（4 checks）----
	check_eq(int(main.get_node("GestureHUDLayer").layer), 64, "U5⑧：GestureHUDLayer.layer==64（HUD_LAYER）")
	check(main.get_node("GestureHUDLayer/GestureHUDMount") is Control, "U5⑧：GestureHUDMount 挂 GestureHUDLayer 下")
	check(main.get_node_or_null("GlobalUI/GestureHUDMount") == null, "U5⑧：HUD 已迁出 GlobalUI 子树（+10 平移系统性消失）")
	check_eq(int(main.get_node("GlobalUI").layer), 1, "U5⑧：GlobalUI 仍 layer=1（HUD 64 高于 Dim/面板、低于光标层 100/装饰框 128）")

	# ---- 段 2. 描述符形态（8 checks）----
	for key: String in ["MAIN_MENU", "OPENING_MOVIE", "TALK", "LEVEL", "CATALOG", "SETTLE", "SHOP", "UNKNOWN"]:
		var cfg: Dictionary = hud._dock_cfg(key)
		var shape_ok: bool = true
		for part: String in ["cam", "status", "hint"]:
			var d: Dictionary = cfg[part]
			if not (d.has("ax") and d.has("ay") and d.has("mx") and d.has("my") and d.has("size")):
				shape_ok = false
		check(shape_ok, "U5①：%s 停靠描述符 {ax,ay,mx,my,size} 五键齐全（双审 P1-2 双轴）" % key)

	# ---- 段 3. 八状态终态几何表逐格（26 checks；双审回修⑫补 SETTINGS status/hint 两条）----
	# st=99 走 apply_dock_state 的未知档兜底分支 → key="UNKNOWN"（P1-5 兜底路径实测）。
	# 档位直取 Game.State 常量（双审回修 P1-1：实况枚举序 SETTLE=5/CATALOG=6，弃手写序号防互换）。
	var states := ["MAIN_MENU", "OPENING_MOVIE", "TALK", "LEVEL", "CATALOG", "SETTLE", "SHOP", "UNKNOWN"]
	for key: String in states:
		var st: int = int(STATE[key]) if STATE.has(key) else 99
		hud.apply_dock_state(st, key == "SETTINGS", key == "SHOP")
		await process_frame
		var cfg: Dictionary = hud._dock_cfg(key)
		check(_rect_of(hud.camera_window).is_equal_approx(_expected_rect(cfg["cam"])),
			"U5：%s 摄像头窗 窗相对==%s（实测 %s）" % [key, _expected_rect(cfg["cam"]), _rect_of(hud.camera_window)])
		var status_node: Control = hud.status_row if bool(hud.status_row.visible) else hud.status_panel
		check(_rect_of(status_node).is_equal_approx(_expected_rect(cfg["status"])),
			"U5：%s 状态条 窗相对==%s" % [key, _expected_rect(cfg["status"])])
		check(_rect_of(hud.guide_panel).is_equal_approx(_expected_rect(cfg["hint"])),
			"U5：%s 说明栏 窗相对==%s（底/右缘零越界随等式成立）" % [key, _expected_rect(cfg["hint"])])
	# SETTINGS 经覆盖层旁路直驱（apply_dock_state 任意 st＋settings_open=true → key="SETTINGS"）——
	# 双审回修⑫补 status/hint 两条终态断言（SETTINGS 不在上列 STATE 映射，另行实测）
	hud.apply_dock_state(STATE["LEVEL"], true, false)
	await process_frame
	var cfg_s: Dictionary = hud._dock_cfg("SETTINGS")
	check(_rect_of(hud.status_panel).is_equal_approx(_expected_rect(cfg_s["status"])),
		"U5：SETTINGS 状态条终态 R14/T211 176×24（R2 回修 A：旧 T203 随组 +8 留痕；实测 %s）" % [_rect_of(hud.status_panel)])
	check(_rect_of(hud.guide_panel).is_equal_approx(_expected_rect(cfg_s["hint"])),
		"U5：SETTINGS 说明栏终态 R14/T256 224×88（GLOBAL 4 行×22=88，批次V §7.1 留痕；V-E4：my 241→256 让位下拉 LOADING 窗底缘 252——重叠 11px+4px 净隙，R2 回修 A 同式；旧 T241/3 行 66 留痕；实测 %s）" % [_rect_of(hud.guide_panel)])

	# ---- 段 4. 两两不相交（8 checks，每状态 1 条循环全对）----
	for key: String in states:
		var st2: int = int(STATE[key]) if STATE.has(key) else 99
		hud.apply_dock_state(st2, key == "SETTINGS", key == "SHOP")
		await process_frame
		var items := _items_for(key)
		var ok_all: bool = true
		for i: int in items.size():
			for j: int in range(i + 1, items.size()):
				if not _no_overlap(items[i], items[j]):
					ok_all = false
		check(ok_all, "U5：%s 全件两两不相交（含场景对照矩形）" % key)

	# ---- 段 5. 可见门联动：覆盖层开→非专属组隐藏、关闭恢复（3 checks）----
	hud.apply_dock_state(STATE["LEVEL"], true, false)
	await process_frame
	var cam_settings: Rect2 = _expected_rect(hud._dock_cfg("SETTINGS")["cam"])
	check(_rect_of(hud.camera_window).is_equal_approx(cam_settings),
		"U5⑧：设置面板开 → 停靠组切 SETTINGS 专属几何（非专属组自动隐藏，既有 so/sho 分支复验）")
	hud.apply_dock_state(STATE["LEVEL"], false, false)
	await process_frame
	check(_rect_of(hud.camera_window).is_equal_approx(_expected_rect(hud._dock_cfg("LEVEL")["cam"])),
		"U5⑧：面板关闭恢复 LEVEL 组")
	hud.apply_dock_state(STATE["MAIN_MENU"], false, true)
	await process_frame
	check(_rect_of(hud.camera_window).is_equal_approx(_expected_rect(hud._dock_cfg("SHOP")["cam"])),
		"U5⑧：商店开 → SHOP 组（S4 语义沿用）")

	# ---- 段 6. main.tscn 集成双层可见门真值表（双审 P0-1，4 checks）----
	# main.gd _refresh_hud 为第二道门（挂 settings_changed 写入晚于 hud 自身门）——直接驱动
	# main._refresh_hud 断言其公式。批次 V 等价替换（V7，spec §4.1）：门=gesture_hud_visible ∧
	# gesture_input——旧 OR 半支「or camera_enabled」废除，[false,true] 行期望 true→false。
	# 批次 Y（Y-A20）等价改写：main 门升级三真值（第三支=camera_stream_open）——先经
	# camera_opened 事件注入开启真值，期望「显」的行三真值齐备；期望「隐」的行不受影响。
	get_root().get_node("GestureBridge").simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "HD Camera"}))
	await process_frame
	for c: Array in [[true, false, true], [false, true, false], [false, false, false]]:
		save.update_settings({"gesture_input": c[0], "gesture_camera_enabled": c[1]})
		main._refresh_hud()
		check_eq(bool(main._hud_instance.visible), bool(c[2]),
			"V7/U4：main 门 input=%s cam=%s → %s（防假绿：两道门同断言；旧 Q2 行等价替换留痕）" % [c[0], c[1], c[2]])
	save.update_settings({"gesture_input": true, "gesture_camera_enabled": false, "gesture_hud_visible": false})
	main._refresh_hud()
	check_eq(bool(main._hud_instance.visible), false, "U4：hud_visible=false → main 门恒隐")
	save.update_settings({"gesture_hud_visible": true})

	# ---- 段 7. 下拉双开态：层级断言＋面板×右列组不相交（双审 P1-1，2 checks）----
	# 下拉与 SETTINGS 说明栏矩形相交是实证事实（见段 7b LOADED 实证）——解法=层级（65>64>1），
	# 故本段断言层级关系；双开态矩形级取证（LOADING 不相交＋LOADED 相交+层级兜底）见段 7b。
	var sp: Node = (load("res://scenes/settings/settings_panel.tscn") as PackedScene).instantiate()
	var menu_layer: CanvasLayer = sp.get_node_or_null("CameraMenuLayer")
	check(menu_layer == null or int(menu_layer.layer) == 65,
		"U2：下拉宿主迁独立层 layer=65（高于 HUD 64 与 GlobalUI 内面板——P1-1 层级解法；UD-6 未合并时短路通过，合并后转实判并回跑本文件）")
	var settings_rect := Rect2(346, 44, 460, 560)   # 设置面板主体（窗相对 460×560 居中）
	var right_col := _expected_rect(hud._dock_cfg("SETTINGS")["hint"])
	check(_no_overlap(settings_rect, right_col), "U5⑧：设置面板主体×SETTINGS 右列停靠组矩形不相交（面板右缘 806 < 组左缘，§11-8）")
	sp.queue_free()

	# ---- 段 7b. SETTINGS 开×下拉开 双开态矩形级取证（规格 §11-8 P1-1 修订，3 checks）----
	# 探针实证（AI工作记录/批次U_走查_20260918/uc_p11_probe.gd，GlobalUI offset 归零后）：
	# ①双开初始态（open_menu 无缓存→LOADING）下拉窗 pos=(814,204) 内容 280×48（批次 V-E4 实测：
	#   LOADING 自绘转圈行 24×24 批次 V-B2 加入后内容 24→48，底缘 252；批次 U 期 280×24/底缘 228 留痕）
	#   < 说明栏顶缘 256（V-E4：gesture_hud.gd SETTINGS hint my 241→256 让位，重叠 11px+4px 净隙；
	#   旧顶缘 241/13px 净隙、更旧 233/5px 净隙留痕）→ 内容级矩形不相交成立；
	# ②枚举回包后 LOADED（双设备实高 75→本环境 88）内容矩形×说明栏矩形**相交**（批次 U 期 279>241
	#   同族实证；规格双审 P1-1「807..1087×914..1138/233..293 相交」同族）→ 防遮挡由 CameraMenuLayer
	#   layer=65 > GestureHUDLayer layer=64 层级通道承担（对策原文）。
	# 坑⑨：PopupPanel 系 Window 子类无 Control.get_global_rect——实矩形=popup.position＋内容
	# 容器实尺寸组合（全程实取运行时值，禁坐标估算）；读数前重刷 SETTINGS 停靠（0.5s 轮询
	# 干扰甄别，探针实证）并在 1~2 帧窗口内断言。
	hud.apply_dock_state(STATE["LEVEL"], true, false)
	await process_frame
	var sp2: Node = (load("res://scenes/settings/settings_panel.tscn") as PackedScene).instantiate()
	main.get_node("GlobalUI").add_child(sp2)   # 生产同构挂载（Game.open_overlay 落 GlobalUI）
	await process_frame
	var popup2: PopupPanel = sp2.get_node("CameraMenuLayer/CameraMenuPopup") as PopupPanel
	var menu2: Control = sp2.get_node("CameraMenuLayer/CameraMenuPopup/CameraMenu") as Control
	var hint2: Control = hud.guide_panel
	sp2.call("_on_arrow_pressed")   # 开下拉（无缓存→LOADING 实高；open_menu 预热/拉取桥内无头守卫）
	await process_frame
	await process_frame
	hud.apply_dock_state(STATE["LEVEL"], true, false)   # 重刷停靠（轮询干扰甄别）
	await process_frame
	var hint_rect2: Rect2 = hint2.get_global_rect()
	var popup_rect2: Rect2 = Rect2(popup2.position, menu2.size)   # 坑⑨组合实矩形
	check(popup_rect2.size.x > 0.0 and popup_rect2.size.y > 0.0 and hint_rect2.size.x > 0.0 \
			and hint_rect2.is_equal_approx(_expected_rect(hud._dock_cfg("SETTINGS")["hint"])),
		"P1-1：双开态取证非零且说明栏实矩形==SETTINGS 终态（实测 %s；防零矩形假绿）" % [hint_rect2])
	check(not popup_rect2.intersects(hint_rect2),
		"P1-1：下拉开（LOADING 实矩形 %s）×SETTINGS 说明栏（%s）矩形级不相交（双开初始态真判据；坑⑨组合口径；V-E4：说明栏让位下移后判据恢复成立——断言意图/比较式零改动）" % [popup_rect2, hint_rect2])
	# LOADED 相交实证＋层级防遮挡通道（喂双设备缓存重开；事实锁防注释漂移）
	get_root().get_node("GestureBridge").set("_camera_enum",
		{"cameras": [{"id": 0, "name": "CamX"}, {"id": 1, "name": "CamY"}], "current_camera": 0})
	sp2.call("_on_arrow_pressed")   # 关
	await process_frame
	sp2.call("_on_arrow_pressed")   # 再开（有缓存→LOADED）
	await process_frame
	await process_frame
	var popup_rect3: Rect2 = Rect2(popup2.position, menu2.size)
	check(popup_rect3.intersects(hint_rect2) \
			and int((sp2.get_node("CameraMenuLayer") as CanvasLayer).layer) > int(main.get_node("GestureHUDLayer").layer),
		"P1-1：LOADED 实矩形（%s）×说明栏相交为实证事实→防遮挡由下拉层 %d > HUD 层 %d 承担（§11-8 对策；事实锁防漂移）"
			% [popup_rect3, int((sp2.get_node("CameraMenuLayer") as CanvasLayer).layer), int(main.get_node("GestureHUDLayer").layer)])
	sp2.queue_free()
	await process_frame

	# ---- 段 8. U10 数值表复核（2 checks；批次 U-C P0 追加口径③ + v2 补偿等价替换留痕：
	# 用户 2026-09-19 截图反馈 clearance+8px（右缘 W−16→W−24、顶 8→12）＋二次截图反馈-v2
	# GlobalUI offset 归零后本地 +10 反向补偿——窗相对终态 W−24/顶 12 维持，Toast 同 W−24）----
	var wb: Control = main.get_node("GlobalUI/WindowButtons")
	check((wb.offset_left == -132.0 and wb.offset_top == 12.0 and wb.offset_right == -24.0 and wb.offset_bottom == 44.0),
		"v2：WindowButtons 本地 offsets==(−132,12,−24,44)（窗相对右缘 W−24、顶 12；P0③ (−142,2,−34,34) 留痕）")
	var tc: Control = main.get_node("GlobalUI/ToastCenter")
	check_eq(float(tc.offset_right), -24.0, "v2：ToastCenter offset_right 终值 −24（窗相对 W−24；P0③ −34 留痕）")

	finish()
