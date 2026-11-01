extends "res://tests/test_base.gd"
## 批次 V 判定用例（V-C2 路，spec §4.1/§7.1/§7.2/§7.3）：
## ①可见门单一真值——整组可见 ⇔ gesture_hud_visible ∧ gesture_input（旧 OR 半支
##   「or camera_enabled」废除）；摄像头窗子件可见 ⇔ 整组 ∧ camera_enabled（开关开而进程
##   未起=「摄像头暂未打开/启动中」占位行为保留；开关关=窗隐）；main.gd 第二道门双处同源。
## ②七非关卡场景提示行含四全局行（ROW_HANDS/ROW_G_MOVE/ROW_G_CLICK/ROW_G_EXIT，spec §7.1）；
##   LEVEL 12 条零改动；FALLBACK=GLOBAL。
## ③折叠竖条化（宽 30∈[28,32]、高随场景 cfg hint 高、竖排「手势说明」旋转 90°+▲/▼ 贴顶可点；
##   记忆机制不变——主菜单写档、其余会话级，spec §7.2）；批次 X（P1-a）分段更新：LEVEL/SETTINGS
##   ∈HORIZONTAL_FOLD_KEYS 折叠改横条（H_FOLD_W×H_FOLD_H、FoldTitle 无旋转），SETTLE 拆出维持竖条。
## ④LEVEL dock 下移（LEVEL_DOCK_TOP=284，spec §7.3）：摄像头窗×JoinView(620,64)-(1140,266)
##   矩形交集为空＋右缘 14 边距＋底界在键鼠提示条顶 621 之上。
## ⑤批次 V 走查回修 NG-1：七非 LEVEL 场景说明栏行 Label 宽 >100（EXPAND_FILL 防单列 1px 塌缩）；
##   LEVEL 双列 170 档零回退。
## 防坑：--script 时序（add 后 await 两帧＋补钉视口，test_u_dock_anchors 同款）；字典 .get 防御；
## 禁测试脚本静态 Game.State（动态取枚举，UB-2 同款）；空值断言先 typeof/is Array 短路（防坑 1）。
## 清档纪律（tools/README_走查清档规范.md，批次V回修②P1-1 补齐）：起测前备份 user:// 真实
## 档案（save.json 及本测试可触及的 .tmp/.bak），终测逐字节还原并断言等价 + EVID 证据行；
## 还原后真实 autoload SaveManager load_game 重同步内存（规范第 2 条）。零摄像头。

const HUD_SCENE := "res://scenes/shared/gesture_hud.tscn"
const WIN := Vector2(1152, 648)
const JOIN_VIEW := Rect2(620, 64, 520, 202)   # level_scene.tscn JoinView 锚 0.5382/0.0988/0.9896/0.4105 → (620,64)-(1140,266)
const HINT_LABEL_TOP := 621.0   # level_scene.tscn HintLabel anchor_top=0.9583×648

const SAVE_PATH := "user://save.json"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"
# 备份路径必须带全 user:// 前缀（test_n10/test_v_save_domain 先例）——实测相对路径在
# FileAccess/DirAccess 间解析不一致（copy 落工程根进程 cwd、file_exists 又随 API 漂移），
# 前缀缺失=备份链静默失效。
const BK_PREFIX := "user://_vhg_backup_"
# 走查规范备份组（本测试不触碰 first_launch.flag——无 mark_first_launch 路径，不入组）
const WATCHED_PATHS: Array = [SAVE_PATH, TMP_PATH, BAK_PATH]

var save: Node
var hud: Control
var STATE: Dictionary = {}
var _pre_save_text: String = ""  # 起测前真实 save.json 原文（还原等价自检基准）

func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _del(p: String) -> void:
	var a: String = _abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _read_file(p: String) -> String:
	return FileAccess.get_file_as_string(p)

func _backup_user() -> void:
	# 规范第 1 条：任何删/写档操作之前备份真实档案（test_v_save_domain 同款实现）
	if FileAccess.file_exists(SAVE_PATH):
		_pre_save_text = _read_file(SAVE_PATH)
	for p: String in WATCHED_PATHS:
		if FileAccess.file_exists(p):
			var bk := BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_abs(p), _abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	# 规范第 2 条：所有退出路径统一收口还原；还原后真实 autoload load_game 重同步内存
	for p: String in WATCHED_PATHS:
		_del(p)
		var bk := BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_abs(bk), _abs(p))
			DirAccess.remove_absolute(_abs(bk))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()  # 防进程退出 close_requested → save_game 把测试态写回真实档案
	# 纪律自检：还原后 save.json 与起测前逐字节等价（起测前无档 ↔ 还原后无档）
	var post: String = _read_file(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|v_hud_gate|files=%d" % WATCHED_PATHS.size())

func _rect(n: Control) -> Rect2:
	return Rect2(n.global_position.round(), n.size.round())

func _texts() -> Array:
	var out: Array = []
	for r: Node in (hud.get_node("GuidePanel/GuideVBox/GuideList") as GridContainer).get_children():
		out.append(String((r as Label).text))
	return out

func _initialize() -> void:
	print("== test_v_hud_gate ==")
	save = get_root().get_node("SaveManager")
	var game_node: Node = get_root().get_node("Game")
	STATE = {
		"MAIN_MENU": int(game_node.State.MAIN_MENU), "OPENING_MOVIE": int(game_node.State.OPENING_MOVIE),
		"TALK": int(game_node.State.TALK), "LEVEL": int(game_node.State.LEVEL),
		"CATALOG": int(game_node.State.CATALOG), "SETTLE": int(game_node.State.SETTLE),
		"BOOT": int(game_node.State.BOOT),
	}
	_backup_user()                     # 清档纪律：任何删/写档前备份真实档案
	for p: String in WATCHED_PATHS:
		_del(p)                        # 沙盒基线：真实档案已备份，测试域内全清
	save.load_game()
	save.update_settings({"gesture_input": true, "gesture_camera_enabled": false,
		"gesture_hud_visible": true, "gesture_panel_folded": false})
	hud = (load(HUD_SCENE) as PackedScene).instantiate()
	add_child(hud)
	await process_frame
	await process_frame
	# 无头 expand 撑 1152×1152（坑⑨）——add 后补钉设计视口（test_u_dock_anchors 同款）
	get_root().size = Vector2i(int(WIN.x), int(WIN.y))
	await process_frame
	await process_frame

	# ---- 段 1. 可见门单一真值（hud 自身门，spec §4.1；6 checks）----
	# 批次 Y 审查② P1-2 等价注入：apply_dock_state 收口 AND 流开启真值（三真值幂等）——
	# 本段「期望显」行需开启真值在场（camera_opened 事件注入）；期望隐行不受扰。
	get_root().get_node("GestureBridge").simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "HD Camera"}))
	await process_frame
	var gate_cases := [
		# [gesture_input, camera_enabled, hud_visible, 期望整组可见]
		[true, false, true, true],
		[true, true, true, true],
		[false, true, true, false],   # 批次 V 核心：手势关=整组隐（即便摄像头开；旧 OR 门判 true）
		[false, false, true, false],
		[true, false, false, false],  # 显示区开关关 → 隐
	]
	for c: Array in gate_cases:
		save.update_settings({"gesture_input": c[0], "gesture_camera_enabled": c[1], "gesture_hud_visible": c[2]})
		hud.apply_dock_state(STATE["MAIN_MENU"], false, false)
		check_eq(bool(hud.visible), bool(c[3]),
			"V7：可见门 input=%s cam=%s hud=%s → %s" % [c[0], c[1], c[2], c[3]])
	hud.apply_dock_state(STATE["BOOT"], false, false)
	check_eq(bool(hud.visible), false, "V7：BOOT 档整组隐藏（st != BOOT 门保留）")
	save.update_settings({"gesture_input": true, "gesture_camera_enabled": false, "gesture_hud_visible": true})

	# ---- 段 2. 摄像头窗占位（批次 W N3 等价改写：窗恒显 + 文案按桥状态；3 checks）----
	# 旧 V7 子件门「整组 ∧ camera_enabled」语义随 N3 废止留痕（W3 探针：门读值 falsy 即窗隐=
	# 首启占位缺失根因）；「窗隐」断言反转为「窗恒显」。「摄像头暂未打开」文案分支现要求
	# 枚举非空 ∧ 未主动关（新「已关闭/未检出」分支在场），注入枚举缓存保持原断言语义。
	var bridge: Node = get_root().get_node("GestureBridge")
	bridge._set_state(2)   # UNAVAILABLE（占位语义前置）
	save.update_settings({"gesture_camera_enabled": false})
	hud.apply_dock_state(STATE["MAIN_MENU"], false, false)
	check_eq(bool(hud.camera_window.visible), true,
		"W-N3：手势开+摄像头关 → 窗仍显（占位常驻；旧「窗隐」语义废止留痕）")
	save.update_settings({"gesture_camera_enabled": true})
	hud.apply_dock_state(STATE["MAIN_MENU"], false, false)
	check_eq(bool(hud.camera_window.visible), true,
		"W-N3：手势开+摄像头开 → 窗显（恒显双档第二档）")
	bridge._camera_enum = {"cameras": [{"id": 0, "name": "CamA"}], "current_camera": -1}  # 枚举非空 → 走「暂未打开」分支
	hud.apply_dock_state(STATE["MAIN_MENU"], false, false)
	check(String(hud.camera_hint.text) == "摄像头暂未打开" and bool(hud.camera_hint.visible),
		"V7：摄像头开而未起（枚举非空+未主动关）→ 既有「摄像头暂未打开」占位行为保持（回归锚）")
	bridge._camera_enum = {}   # 复位注入
	bridge._set_state(1)   # READY 复位（后续段不受占位干扰）

	# ---- 段 3. 七非关卡场景全局提示行（spec §7.1；11 checks）----
	var hs: GDScript = load("res://scenes/shared/gesture_hud.gd")
	var grows_v: Variant = hs.get("GLOBAL_HINT_ROWS")
	check(grows_v is Array, "V9/V14：GLOBAL_HINT_ROWS 常量在场（防坑 1：先 is Array 判型）")
	var grows: Array = grows_v if grows_v is Array else []
	check_eq(grows.size(), 4, "V9/V14：GLOBAL_HINT_ROWS 恰 4 行（HANDS/G_MOVE/G_CLICK/G_EXIT）")
	var scene_flag: Dictionary = {
		"MAIN_MENU": [STATE["MAIN_MENU"], false, false], "OPENING_MOVIE": [STATE["OPENING_MOVIE"], false, false],
		"TALK": [STATE["TALK"], false, false], "CATALOG": [STATE["CATALOG"], false, false],
		"SHOP": [STATE["MAIN_MENU"], false, true], "SETTINGS": [STATE["MAIN_MENU"], true, false],
		"SETTLE": [STATE["SETTLE"], false, false],
	}
	for key: String in scene_flag:
		var f: Array = scene_flag[key]
		hud.apply_dock_state(int(f[0]), bool(f[1]), bool(f[2]))
		var texts: Array = _texts()
		var ok4: bool = true
		for g: String in grows:
			if not texts.has(g):
				ok4 = false
		check(ok4, "V9/V14：%s 行集含四全局行（实测 %d 行）" % [key, texts.size()])
	hud.apply_dock_state(STATE["CATALOG"], false, false)
	var cat_texts: Array = _texts()
	# 批次 X（P5-c）→ 批次 AA（W3-5，spec §6.4-A 序 4/5）等价改写：尾二行随新文案表（旋转=食+中、
	# 缩放=双手通用【左/右】，W3-1 后缩放左右掌同链）
	check(String(cat_texts[cat_texts.size() - 2]) == "4 旋转视角【左】食+中" \
			and String(cat_texts[cat_texts.size() - 1]) == "5 缩放【左/右】手掌推拉",
		"X4/W3-5：CATALOG=GLOBAL+[ROW_ROTATE,ROW_ZOOM]（点云观察保留，尾二行逐字·§6.4-A 新表）")
	hud.apply_dock_state(STATE["SETTLE"], false, false)
	var se_texts: Array = _texts()
	check(String(se_texts[se_texts.size() - 1]) == "点选钮【左/右】·拖转/掌缩放【左/右】",
		"X4/W3-5：SETTLE=GLOBAL+点云行（尾行逐字·掌缩放双手版 §6.4-C；旧「掌缩放【左】」与「单击=选钮…」留痕）")
	check_eq(hs.get("SCENE_HINTS_FALLBACK"), grows, "V9：FALLBACK=GLOBAL（未知态兜底同源）")
	hud.apply_dock_state(99, false, false)
	var u_texts: Array = _texts()
	var u_ok: bool = u_texts.size() == 4
	for g2: String in grows:
		if not u_texts.has(g2):
			u_ok = false
	check(u_ok, "V9：未知态兜底展开=四全局行")

	# ---- 段 4. LEVEL 12 行不动（spec §7.1；2 checks；批次 X P5-c 首尾逐字随文案表等价改写）----
	hud.apply_dock_state(STATE["LEVEL"], false, false)
	var lv: Array = _texts()
	# 批次 Y（Y-A14）等价改写：LEVEL 行组追加参考框说明行「参考框=推荐活动区」（拍板三口径，
	# 判定全画面不变仅文案）——12→13 行；列高预算 7×15=105≤110 复核（gesture_hud.gd 常量注）
	check_eq(lv.size(), 13, "V9（Y2 等价改写）：LEVEL 13 行（原 12 行+Y-A14 参考框说明行）")
	check((lv as Array).has("参考框=推荐活动区"), "Y-A14：LEVEL 行组含参考框说明行「框=推荐活动区」口径（文案表断言）")
	var lv_no_global: bool = true
	for g3: String in grows:
		if lv.has(g3):
			lv_no_global = false
	# 批次 AA（W3-5，spec §6.4-A）等价改写：首行序号 1 不变、退出行由旧「13 退出」改为
	# 序 10（11 手势 + 图例 + 参考框新表）；断言补图例行在案（简写全称承载处），断言数不变。
	check(lv_no_global and String(lv[0]) == "1 移动光标【左/右】食指" and String(lv[9]) == "10 退出【双手】四指同翻" \
			and String(lv[11]) == "食=食指 中=中指 无名=无名指",
		"X4/W3-5：LEVEL 行集保持带序号规范行（首/退出/图例逐字·§6.4-A 新表+无全局行混入；P5-c 表留痕）")

	# ---- 段 5. 折叠竖条化（spec §7.2；15 checks）----
	# 主菜单：FoldBtn 入口折叠（生产真路径——_folded 成员+存档键同写，直写存档键不回读 _folded）
	game_node._state = STATE["MAIN_MENU"]   # 直写模拟主菜单态（_current_key 路由用；test_gesture_hud 先例）
	hud.apply_dock_state(STATE["MAIN_MENU"], false, false)
	hud.fold_btn.pressed.emit()
	hud.apply_dock_state(STATE["MAIN_MENU"], false, false)
	var mm_size: Vector2 = hud._dock_cfg("MAIN_MENU")["hint"]["size"]
	var bar: Vector2 = hud.guide_panel.size.round()
	check_eq(bool(save.get_settings().get("gesture_panel_folded", false)), true,
		"V13：主菜单 FoldBtn 折叠写档 gesture_panel_folded=true（记忆机制不变）")
	check(bar.x >= 28.0 and bar.x <= 32.0,
		"V13：主菜单折叠竖条宽∈[28,32]（旧横条 (宽,24) 废除留痕；实测 %s）" % bar)
	check(bar.y > bar.x and is_equal_approx(bar.y, mm_size.y),
		"V13：主菜单竖条高随场景 cfg hint 高 %s（高>宽；实测 %s）" % [mm_size.y, bar])
	check(bool(hud.hint_fold_btn.visible), "V13：主菜单折叠态 ▲/▼ 钮可点（双审 P0-1 死路不回退）")
	var ft: Control = hud.get_node_or_null("FoldTitle")
	check(ft != null and bool(ft.visible) and absf(ft.rotation - PI / 2.0) < 0.01,
		"V13：竖排「手势说明」Label 旋转 90° 显示于竖条（代码构建件 FoldTitle）")
	# 展开经竖条 ▲/▼ 钮（V13 归一路由端到端：hint_fold_btn → _on_hint_fold_pressed → 主菜单
	# 路由 _on_fold_pressed 存档语义）
	hud.hint_fold_btn.pressed.emit()
	hud.apply_dock_state(STATE["MAIN_MENU"], false, false)
	check_eq(bool(save.get_settings().get("gesture_panel_folded", false)), false,
		"V13：竖条 ▲/▼ 钮展开写回 gesture_panel_folded=false（归一路由端到端）")
	check((hud.guide_panel.size as Vector2).is_equal_approx(mm_size) and bool(hud.guide_list.visible),
		"V13：主菜单展开还原（cfg hint 尺寸+行集可见；展开态视觉零变化）")
	# 会话级：批次 X（P1-a，spec §2）分流——LEVEL/SETTINGS∈HORIZONTAL_FOLD_KEYS 折叠改横条
	#（宽≈H_FOLD_W、高≈H_FOLD_H、FoldTitle 横排无旋转）；SETTLE 拆出维持竖条零变化。
	# 折叠写档/会话级记忆断言（上方 :205-208 与下方末条）不动。
	for key2: String in ["LEVEL", "SETTINGS"]:
		hud._hint_folded[key2] = true
		# SETTINGS 经覆盖层旁路（settings_open=true），LEVEL 直驱对应态（key 分流同源）
		hud.apply_dock_state(int(STATE["MAIN_MENU"] if key2 == "SETTINGS" else STATE[key2]),
			key2 == "SETTINGS", false)
		var b2: Vector2 = hud.guide_panel.size.round()
		check(is_equal_approx(b2.x, float(hud.H_FOLD_W)) and is_equal_approx(b2.y, float(hud.H_FOLD_H)),
			"X-P1a：%s 折叠横条 %sx%s（锚定五元组不动、ax=R 贴右缘；实测 %s）" % [key2, hud.H_FOLD_W, hud.H_FOLD_H, b2])
		var ft2: Control = hud.get_node_or_null("FoldTitle")
		check(ft2 != null and bool(ft2.visible) and absf(ft2.rotation) < 0.01,
			"X-P1a：%s 横条 FoldTitle 横排显示且无旋转（竖条态 PI/2 语义分流）" % key2)
		check(bool(hud.hint_fold_btn.visible), "V13：%s 折叠态 ▲/▼ 钮可点（死路不回退）" % key2)
		hud._hint_folded[key2] = false
		hud.apply_dock_state(int(STATE["MAIN_MENU"] if key2 == "SETTINGS" else STATE[key2]),
			key2 == "SETTINGS", false)
		check((hud.guide_panel.size as Vector2).is_equal_approx(hud._dock_cfg(key2)["hint"]["size"]),
			"V13：%s 展开还原（cfg hint 尺寸）" % key2)
	# SETTLE 拆出（批次 X P1-a）：五态竖条维持——宽∈[28,32]、高随场景 cfg hint 高、标题竖排旋转
	hud._hint_folded["SETTLE"] = true
	hud.apply_dock_state(int(STATE["SETTLE"]), false, false)
	var b3: Vector2 = hud.guide_panel.size.round()
	check(b3.x >= 28.0 and b3.x <= 32.0 and b3.y > b3.x \
			and is_equal_approx(b3.y, (hud._dock_cfg("SETTLE")["hint"]["size"] as Vector2).y),
		"V13/X-P1a：SETTLE 折叠维持竖条宽∈[28,32]、高随场景 cfg hint 高（实测 %s）" % b3)
	var ft3: Control = hud.get_node_or_null("FoldTitle")
	check(ft3 != null and bool(ft3.visible) and absf(ft3.rotation - PI / 2.0) < 0.01,
		"X-P1a：SETTLE 竖条 FoldTitle 维持旋转 90°（五态竖条零变化）")
	check(bool(hud.hint_fold_btn.visible), "V13：SETTLE 折叠态 ▲/▼ 钮可点（死路不回退）")
	hud._hint_folded["SETTLE"] = false
	hud.apply_dock_state(int(STATE["SETTLE"]), false, false)
	check((hud.guide_panel.size as Vector2).is_equal_approx(hud._dock_cfg("SETTLE")["hint"]["size"]),
		"V13：SETTLE 展开还原（cfg hint 尺寸）")
	check_eq(bool(save.get_settings().get("gesture_panel_folded", false)), false,
		"V13：会话级折叠不写档（记忆机制不变——主菜单写档/其余会话级）")

	# ---- 段 6. LEVEL dock 下移避让（spec §7.3；7 checks）----
	var ldt_v: Variant = hud.get("LEVEL_DOCK_TOP")
	check(typeof(ldt_v) == TYPE_FLOAT and is_equal_approx(float(ldt_v), 284.0),
		"V15：LEVEL_DOCK_TOP=284（JoinView 底 266+18 间隙；防坑 1：typeof 先判）")
	var lv_src: String = FileAccess.get_file_as_string("res://scenes/level/level_scene.tscn")
	check(lv_src.contains("anchor_left = 0.5381944") and lv_src.contains("anchor_top = 0.0987654") \
			and lv_src.contains("anchor_right = 0.9895833") and lv_src.contains("anchor_bottom = 0.4104938"),
		"V15：JoinView 几何源锁（锚→(620,64)-(1140,266)；tscn 漂移防呆）")
	hud.apply_dock_state(STATE["LEVEL"], false, false)
	var cam_r: Rect2 = _rect(hud.camera_window)
	var st_r: Rect2 = _rect(hud.status_panel)
	var hint_r: Rect2 = _rect(hud.guide_panel)
	check(not cam_r.intersects(JOIN_VIEW), "V15：摄像头窗×JoinView 矩形交集为空（实测 cam=%s）" % cam_r)
	check(cam_r.position.y >= 283.5, "V15：摄像头窗顶 y≥284（实测 %s）" % cam_r.position.y)
	check(absf(cam_r.end.x - (WIN.x - 14.0)) < 0.5, "V15：右缘 14 边距不变（实测右缘 %s）" % cam_r.end.x)
	check(hint_r.end.y < HINT_LABEL_TOP, "V15：底界在键鼠提示条顶 621 之上（实测底 %s）" % hint_r.end.y)
	check(st_r.position.y >= 415.5 and hint_r.position.y >= 445.5,
		"V15：status/hint 随 LEVEL_DOCK_TOP 同源下移（416/446；实测 %s/%s）" % [st_r.position.y, hint_r.position.y])

	# ---- 段 7. main 集成双门单一真值（spec §4.1 双处同改；2 checks）----
	# 批次 Y（Y-A20）等价改写：main 门升级三真值（第三支=camera_stream_open）——期望「显」行
	# 先经 camera_opened 事件注入开启真值；期望「隐」行不受影响。
	var bridge7: Node = get_root().get_node("GestureBridge")
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	await process_frame
	await process_frame
	bridge7.simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "HD Camera"}))
	await process_frame
	save.update_settings({"gesture_input": false, "gesture_camera_enabled": true})
	main._refresh_hud()
	check_eq(bool(main._hud_instance.visible), false,
		"V7：main 门 手势关+摄像头开 → 隐（双处同源防漂移；旧 OR 判 true）")
	save.update_settings({"gesture_input": true, "gesture_camera_enabled": false})
	main._refresh_hud()
	check_eq(bool(main._hud_instance.visible), true,
		"V7（Y2）：main 门 手势开+摄像头关+流开启真值 → 显（整组门不含摄像头半支；三真值齐备）")
	main.queue_free()
	await process_frame

	# ---- 段 8. 批次 V 走查回修 NG-1：非 LEVEL 场景说明栏行 Label 宽度不塌缩（8 checks）----
	# 走查 w03/w11 + probe.gd 实证：非 LEVEL 行 custom_minimum_size=(0,row_h)+clip_text=true
	# → Label 最小宽 0~1px → GridContainer 单列列宽塌至 1px 文字不可视（V9 全局行被掩蔽）。
	# 修复口径=行 Label SIZE_EXPAND_FILL 撑满说明栏净宽（面板宽由 _dock_cfg hint size 锚定给出）；
	# 折叠竖条无副作用（折叠态 guide_list.visible=false 隐藏件不参与最小尺寸，竖条 30 宽不变）。
	for key4: String in ["MAIN_MENU", "OPENING_MOVIE", "TALK", "CATALOG", "SETTLE", "SHOP", "SETTINGS"]:
		var f4: Array = scene_flag[key4]
		hud.apply_dock_state(int(f4[0]), bool(f4[1]), bool(f4[2]))
		await process_frame
		await process_frame
		var min_w := INF
		for r10: Node in (hud.get_node("GuidePanel/GuideVBox/GuideList") as GridContainer).get_children():
			if r10 is Label and (r10 as Label).visible:
				min_w = minf(min_w, (r10 as Label).size.x)
		check(min_w > 100.0, "NG-1：%s 说明栏行 Label 宽 >100 不塌缩（最窄行实测 %.1f）" % [key4, min_w])
	# LEVEL 双列不回退：行宽保持 170 最小宽档（368−12=356=170×2+16 恰满，expand 零多余空间）
	hud.apply_dock_state(STATE["LEVEL"], false, false)
	await process_frame
	await process_frame
	var lv_min_w := INF
	var lv_max_w := 0.0
	for r11: Node in (hud.get_node("GuidePanel/GuideVBox/GuideList") as GridContainer).get_children():
		if r11 is Label:
			lv_min_w = minf(lv_min_w, (r11 as Label).size.x)
			lv_max_w = maxf(lv_max_w, (r11 as Label).size.x)
	check(lv_min_w >= 169.0 and lv_max_w <= 171.0 and hud.guide_list.columns == 2,
		"NG-1：LEVEL 双列行宽 170 档零回退（min=%.1f max=%.1f columns=%d）" % [lv_min_w, lv_max_w, hud.guide_list.columns])

	# ---- 现场还原：先复位测试改写的桥态，再走清档纪律还原（备份→测试→逐字节还原+EVID） ----
	save.update_settings({"gesture_input": true, "gesture_camera_enabled": true,
		"gesture_hud_visible": true, "gesture_panel_folded": false})
	bridge._set_state(1)
	_restore_user()
	finish()
