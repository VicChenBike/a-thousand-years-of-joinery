extends "res://tests/test_base.gd"
## 批次 T 判定用例（T-E 域）：T14~T16 停靠表七分支终态几何 → 批次 U 等价替换（UB-6）：全部
## 648 基线绝对坐标期望改经 hud._dock_cfg(key) 描述符换算（_expected_rect 同式，spec §4-U5 表
## 锚定终态）；折叠段改「只收说明栏」新语义（U5②/P0-1）；LvToggleBtn/FoldRestore 退役断言；
## 末尾追加批次 U 段 4 checks（U10 右列带不相交×2＋TopBar −132 维持＋LEVEL 双列 368×110）。
## 几何权威=spec §4-U5 表（窗相对口径，W/H=1152/648）；行高实高推导沿革见 git 留痕。

const HUD_SCENE := "res://scenes/shared/gesture_hud.tscn"
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

func _dock(hud: Control, st: int, so := false, sho := false) -> void:
	hud.call("apply_dock_state", st, so, sho)

func _pairwise(hud: Control, ctx: String) -> void:
	var names: Array = ["CameraWindow", "StatusRow", "StatusPanel", "GuidePanel", "FoldRestore"]
	var rects: Array = []
	var rnames: Array = []
	for nm: String in names:
		var n: Control = hud.get_node_or_null(nm) as Control
		if n != null and n.visible:
			rects.append(_rect(n))
			rnames.append(nm)
	var ok := true
	for i: int in rects.size():
		for j: int in range(i + 1, rects.size()):
			if (rects[i] as Rect2).intersects(rects[j] as Rect2):
				ok = false
	check(ok, "%s：可见件两两不相交（%s，C(%d,2) 对展开）" % [ctx, ",".join(rnames), rects.size()])

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
const DISC_BK_PREFIX := "user://_r2b_tde_backup_"
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
	print("EVID|user_restore|tde|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_t_dock_expand ==")
	_backup_user()
	var save: Variant = get_root().get_node("SaveManager")
	var p: String = ProjectSettings.globalize_path("user://save.json")
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
	save.load_game()
	var game: Variant = get_root().get_node("Game")   # plan 代码块自查补预置：折叠段写档语义依赖真实状态机（无头 Game._state 恒 BOOT，旧 console_dock 先例）
	var hud: Control = (load(HUD_SCENE) as PackedScene).instantiate()
	add_child(hud)
	await process_frame
	await process_frame
	# 批次 U 实证坑（tmp_probe_layer_size / test_u_dock_anchors 同款）：无头 expand 撑
	# 1152×1152，底锚（ay=B）依赖 HUD 根尺寸——**add 后补钉**设计视口再等两帧（磁盘实况校正）
	get_root().size = Vector2i(int(WIN.x), int(WIN.y))
	await process_frame
	await process_frame
	var cam: Control = hud.get_node("CameraWindow")
	var col: Control = hud.get_node("StatusRow")
	var sp: Control = hud.get_node("StatusPanel")
	var gp: Control = hud.get_node("GuidePanel")
	# ---- MAIN_MENU（4）----
	_dock(hud, STATE["MAIN_MENU"])
	# 批次 U 等价替换：648 基线绝对值 Rect2(16,462,320,180) → 锚定描述符终态（spec §4-U5 表 L16/B14）
	check_eq(_rect(cam), _expected_rect(hud._dock_cfg("MAIN_MENU")["cam"]), "T14：主菜单摄像头窗 320×180 L16/B14（旧 @(16,462) 等价替换留痕）")
	# 批次 U 等价替换：Rect2(348,462,96,180) → 描述符终态 L348/B14
	check_eq(_rect(col), _expected_rect(hud._dock_cfg("MAIN_MENU")["status"]), "T14：主菜单状态列 96×180 L348/B14（旧 @(348,462) 等价替换留痕）")
	# 批次 U 等价替换：Rect2(456,549,352,94) → 描述符终态 L456/B14（旧 top 549 系 T-G② 5px 边距特调，锚定表统一 B14）
	check_eq(_rect(gp), _expected_rect(hud._dock_cfg("MAIN_MENU")["hint"]), "T14/J2：主菜单说明栏 352×94 L456/B14（旧 @(456,549) 等价替换留痕）")
	_pairwise(hud, "MAIN_MENU")
	# ---- OPENING_MOVIE/TALK（4）----
	_dock(hud, STATE["OPENING_MOVIE"])
	# 批次 U 等价替换：Rect2(912,92,224,126) → 描述符终态 R14/T98；R2 回修 A：T98→T106 整组下移 8px
	check_eq(_rect(cam), _expected_rect(hud._dock_cfg("OPENING_MOVIE")["cam"]), "T14：开场摄像头窗 R14/T106（旧 @(912,92)/T98 等价替换留痕）")
	# 批次 U 等价替换：Rect2(912,222,224,24) → 描述符终态 R14/T230；R2 回修 A：随组 +8
	check_eq(_rect(sp), _expected_rect(hud._dock_cfg("OPENING_MOVIE")["status"]), "T14：开场状态行 R14/T238（旧 @(912,222)/T230 等价替换留痕）")
	# 批次 U 等价替换：Rect2(912,254,224,44) → 描述符终态 R14/T260；R2 回修 A：随组 +8
	check_eq(_rect(gp), _expected_rect(hud._dock_cfg("OPENING_MOVIE")["hint"]), "T14/J2：开场说明栏 224×44 R14/T268（旧 @(912,254)/T260 等价替换留痕）")
	_dock(hud, STATE["TALK"])
	check_eq(_rect(gp), _expected_rect(hud._dock_cfg("TALK")["hint"]), "T14：对话说明栏同开场（批次 S 新增沿用，描述符终态）")
	# ---- LEVEL（5）----
	_dock(hud, STATE["LEVEL"])
	# 批次 U 等价替换：Rect2(912,462,224,126) → 描述符终态 R14/T98（旧右下 462 整组废止=LEVEL 漂移根除）；R2 回修 A：T98→T106
	check_eq(_rect(cam), _expected_rect(hud._dock_cfg("LEVEL")["cam"]), "T14：关卡摄像头窗 R14/T106（旧 @(912,462)/T98 等价替换留痕；LEVEL 漂移根除）")
	# 批次 U 等价替换：Rect2(912,592,224,24) → 描述符终态 R14/T230；R2 回修 A：随组 +8
	check_eq(_rect(sp), _expected_rect(hud._dock_cfg("LEVEL")["status"]), "T14：关卡状态行 R14/T238（旧 @(912,592)/T230 等价替换留痕）")
	# 批次 U 等价替换：旧「T16 浮层默认展开 gp.visible」→ 折叠语义收窄后 gp 恒显，改锁 guide_list（等价承接）
	check((hud.get_node("GuidePanel/GuideVBox/GuideList") as Control).visible, "T16：LEVEL 说明栏默认展开（guide_list 可见；旧 gp.visible 断言随 U5② 面板恒显等价替换）")
	# 批次 U 等价替换：Rect2(816,274,320,180) → 描述符终态 R14/T260 双列 368×110；R2 回修 A：随组 +8
	check_eq(_rect(gp), _expected_rect(hud._dock_cfg("LEVEL")["hint"]), "T14/U5④：LEVEL 说明栏双列 368×110 R14/T268（旧 320×180 @(816,274)/T260 等价替换留痕）")
	check(hud.get_node_or_null("StatusPanel/StatusLineBox/LvToggleBtn") == null,
		"U5②：LvToggleBtn 退役删除（说明栏顶缘收起钮 HintFoldBtn 并轨，批次 U 等价替换）")
	# ---- CATALOG（3）----
	_dock(hud, STATE["CATALOG"])
	# 批次 U 等价替换：Rect2(16,536,144,81) → 描述符终态 L16/B44
	check_eq(_rect(cam), _expected_rect(hud._dock_cfg("CATALOG")["cam"]), "T14：图鉴摄像头窗 L16/B44（旧 @(16,536) 等价替换留痕）")
	# 批次 U 等价替换：Rect2(16,621,144,24) → 描述符终态 L16/B14
	check_eq(_rect(sp), _expected_rect(hud._dock_cfg("CATALOG")["status"]), "T14：图鉴状态行 L16/B14（旧 @(16,621) 等价替换留痕）")
	# 批次 U 等价替换：Rect2(176,540,300,100) → 描述符终态 L172/B14（列距 GROUP_GAP_H=12：172=16+144+12）
	check_eq(_rect(gp), _expected_rect(hud._dock_cfg("CATALOG")["hint"]), "T14/J2：图鉴说明栏 300×100 L172/B14（旧 @(176,540) 等价替换留痕）")
	# ---- SETTLE（3）----
	_dock(hud, STATE["SETTLE"])
	# 批次 U 等价替换：Rect2(24,458,224,126) → 描述符终态 L24/B78
	check_eq(_rect(cam), _expected_rect(hud._dock_cfg("SETTLE")["cam"]), "T14：结算摄像头窗 L24/B78（旧 @(24,458) 等价替换留痕）")
	# 批次 U 等价替换：Rect2(24,588,224,24) → 描述符终态 L24/B48
	check_eq(_rect(sp), _expected_rect(hud._dock_cfg("SETTLE")["status"]), "T14：结算状态行 L24/B48（旧 @(24,588) 等价替换留痕）")
	# 批次 U 等价替换：Rect2(24,616,224,28) → 描述符终态 L24/B14
	check_eq(_rect(gp), _expected_rect(hud._dock_cfg("SETTLE")["hint"]), "T14：结算说明栏 240×140 L24/B14（旧 224×28 @(24,616) 等价替换留痕；_dock_cfg SETTLE hint 同源，批次 AA W3-5 宽 224→240 后消息串同步）")
	# ---- SHOP（3）----
	_dock(hud, 1, false, true)
	# 批次 AA（W8-2，spec §11.4-2 顶部横排）：消息串随定稿几何同步（断言本体仍与 _dock_cfg 同源）
	check_eq(_rect(cam), _expected_rect(hud._dock_cfg("SHOP")["cam"]), "T15/W8-2：商店摄像头窗 128×72 L344/T16 顶排首件（批次 V14 176×99 L16/T88 留痕）")
	check_eq(_rect(sp), _expected_rect(hud._dock_cfg("SHOP")["status"]), "T15/W8-2：商店状态行 128×24 L480/T16（旧 L16/T193 留痕）")
	check_eq(_rect(gp), _expected_rect(hud._dock_cfg("SHOP")["hint"]), "T15/W8-2：商店说明栏 300×74 L616/T16 顶排（14/17 专属档 4×18=72≤74；旧 224×88 L200/T88 留痕）")
	# ---- SETTINGS（3）----
	_dock(hud, 1, true, false)
	# 批次 U 等价替换：Rect2(826,48,176,99) → 描述符终态 R14/T98；R2 回修 A：T98→T106（设置钮底 102×旧顶 98 实叠 4px 根除，用户「UI 重叠不允许」铁律）
	check_eq(_rect(cam), _expected_rect(hud._dock_cfg("SETTINGS")["cam"]), "T14：设置覆盖层摄像头窗 R14/T106（旧 @(826,48)/T98 等价替换留痕）")
	# 批次 U 等价替换：Rect2(826,155,176,24) → 描述符终态 R14/T203；R2 回修 A：随组 +8
	check_eq(_rect(sp), _expected_rect(hud._dock_cfg("SETTINGS")["status"]), "T14：设置状态行 R14/T211（旧 @(826,155)/T203 等价替换留痕）")
	# 批次 U 等价替换：Rect2(826,187,224,66) → 描述符终态 R14/T233；R2 回修 A：随组 +8
	check_eq(_rect(gp), _expected_rect(hud._dock_cfg("SETTINGS")["hint"]), "T14/J2：设置说明栏 224×66 R14/T241（旧 @(826,187)/T233 等价替换留痕）")
	# ---- 其余态两两不相交（6）----
	_pairwise(hud, "SETTINGS")
	_dock(hud, STATE["OPENING_MOVIE"])
	_pairwise(hud, "OPENING_MOVIE")
	_dock(hud, STATE["LEVEL"])
	_pairwise(hud, "LEVEL")
	_dock(hud, STATE["CATALOG"])
	_pairwise(hud, "CATALOG")
	_dock(hud, STATE["SETTLE"])
	_pairwise(hud, "SETTLE")
	_dock(hud, 1, false, true)
	_pairwise(hud, "SHOP")
	# ---- 折叠档（批次 V 等价替换 V13，spec §7.2：折叠竖条化——旧「只收说明栏降高至 header 行」
	# 语义退役留痕）----
	game.goto_state(game.State.MAIN_MENU)   # 无头预置（goto_state 无头只改状态机+发信号，旧 console_dock 先例）
	_dock(hud, STATE["MAIN_MENU"])
	hud.get_node("GuidePanel/GuideVBox/GuideHeader/FoldBtn").pressed.emit()
	check_eq(bool(save.get_settings()["gesture_panel_folded"]), true, "T16：主菜单说明栏折叠写档沿用（批次 U 语义收窄=只收说明栏）")
	check(not (hud.get_node("GuidePanel/GuideVBox/GuideHeader") as Control).visible
		and not (hud.get_node("GuidePanel/GuideVBox/GuideList") as Control).visible
		and (hud.get_node("HintFoldBtn") as Control).visible,
		"V13：折叠态竖条化——header 隐＋guide_list 隐＋HintFoldBtn 可点（旧「header 恒显承载 FoldBtn」等价替换留痕）")
	check((hud.get_node("GuidePanel") as Control).size.round().x <= 32.0,
		"V13：折叠态=竖条（宽≤32 档；旧横条降高 (宽,24) 等价替换留痕）")
	check(hud.get_node_or_null("FoldRestore") == null, "U5②：FoldRestore 废止删除（折叠不藏组无复原需求；旧 28×28 @(16,614) rect 断言随节点退役等价替换）")
	hud.get_node("HintFoldBtn").pressed.emit()   # 再点展开（批次 V：竖条 ▲/▼ 钮归一 _on_fold_pressed 存档语义）
	check_eq(bool(save.get_settings()["gesture_panel_folded"]), false, "T16：再点竖条钮写回 false（旧「再点 FoldBtn」/原 FoldRestore 复原写回等价替换）")
	# ---- 废止项（3）----
	check(hud.get_node_or_null("BarColumn") == null, "T14：BarColumn 竖条节点已删（tscn）")
	var src: String = FileAccess.get_file_as_string("res://scenes/shared/gesture_hud.gd")
	check(not src.contains("_apply_gray"), "T3：置灰函数已删（源码证据）")
	check(not src.contains("and not shop_open"), "T14：SHOP 整组隐藏条件已删（:198 留痕）")
	# ---- SCENE_HINTS 联动可见性（1；批次 U 偏离②：VBox→GridContainer cast 等价替换；
	# 批次 V 等价替换 V9 spec §7.1：主菜单 3 行→GLOBAL 4 行）----
	check_eq((hud.get_node("GuidePanel/GuideVBox/GuideList") as GridContainer).get_child_count(), 4,
		"V9：主菜单说明栏 4 全局行在位（几何与集合联动；旧 3 行等价替换留痕；as GridContainer 等价替换留痕）")
	# ---- BOOT 隐藏（1）----
	_dock(hud, 0)
	check(not hud.visible, "T14：BOOT 控制台隐藏（沿用）")
	# ---- 批次 U 追加（U10/U5④，4 checks）----
	# 计划 UB-6 Step 1 末段：右列组×窗口钮/设置钮不相交（需 main.tscn 夹具——该文件无既有 main，
	# 按计划括注「夹具变量名以磁盘实况为准」经实例化补齐）＋TopBar −132 旁路＋LEVEL 双列描述符锁死
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	await process_frame
	await process_frame
	var wb: Control = main.get_node("GlobalUI/WindowButtons")
	var settings_btn: Control = main.get_node("GlobalUI/SettingsButton")
	var right_col_band := Rect2(Vector2(WIN.x - 14.0 - 368.0, 106.0), Vector2(368, WIN.y - 106.0))   # 右列组横向最宽带（R2 回修 A：COLUMN_TOP=106 起至窗底；旧 98 留痕）
	check(not wb.get_global_rect().intersects(right_col_band),
		"U10：右列停靠组（R2 回修 A：COLUMN_TOP=106 起）×窗口钮矩形不相交（复查项，间隙 14px；v2 实矩形复核维持）")
	# ---- 批次 U-C v2 实矩形校正（等价替换留痕，2 checks；v1 层偏移盲区根因）----
	# 4.7 无头实证（test_t_window_frame 同款换算注记）：Control.get_global_rect 链止于 CanvasLayer
	# 不含其 offset——v1 offset(10,10) 下旧断言测的是 canvas 矩形 fiction（视觉实位=canvas+10）。
	# v2 offset 归零 → get_global_rect 即窗相对实矩形，实况暴露：设置钮实高 50（font20+stylebox，
	# 探针 uc_tde_probe 实测 (1020,52,108,50)）×P0③ 顶 52 终态 → 底缘 102 与旧停靠组顶 98 实叠 4px
	#（452aa7b P0③ 下推引入、v1 fiction 断言盲区掩盖）。
	# R2 双审回修 A（用户「UI 重叠不允许」铁律）：COLUMN_TOP 98→106 整组下移 8px 根除叠压——
	# 旧「4px 实叠事实锁」废止，反转为不相交锁（设置钮底 102 × 摄像头窗顶 106，净隙 4px）。
	var sb_rect: Rect2 = settings_btn.get_global_rect()
	check(not sb_rect.intersects(Rect2(WIN.x - 14.0 - 176.0, 211.0, 176.0, 24.0)) \
			and not sb_rect.intersects(Rect2(WIN.x - 14.0 - 224.0, 241.0, 224.0, 66.0)),
		"U10：设置钮×右列组状态条（962,211 起）/说明栏（914,241 起）实矩形不相交（真禁叠区维持，R2 回修 A 随组 +8；实测 %s）" % [sb_rect])
	check(not sb_rect.intersects(Rect2(WIN.x - 14.0 - 176.0, 106.0, 176.0, 99.0)),
		"R2回修A：设置钮×SETTINGS 摄像头窗（顶 106 起）实矩形不相交（旧 4px 实叠事实锁废止反转为不相交锁——用户「UI 重叠不允许」铁律，下移 8px=4px 消叠+4px 随组对齐；实测 %s）" % [sb_rect])
	main.queue_free()
	await process_frame
	# 该文件无 LEVEL 场景夹具（计划括注「无则经 settings 旁路断言 offsets」）——经场景源文本锁死
	var lvl_src: String = FileAccess.get_file_as_string("res://scenes/level/level_scene.tscn")
	check(lvl_src.contains("offset_right = -132.0"),
		"U10：level TopBar offset_right=−132 维持（W−142；设置钮回位后间隙 18px，补断言锁死防漂；源文本旁路留痕）")
	var lv_hint: Dictionary = hud._dock_cfg("LEVEL")["hint"]
	check_eq(lv_hint["size"], Vector2(368, 110), "U5④：LEVEL 说明栏双列 368×110（收起钮行 20＋6 行×15；行高 15/字号 10 引 gesture_hud.gd 既有备案，双审 P2-11）")
	hud.queue_free()
	await process_frame
	finish()
