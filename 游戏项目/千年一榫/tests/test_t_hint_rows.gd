extends "res://tests/test_base.gd"
## 批次 T 判定用例（T-E 域）：T1/T4 SCENE_HINTS 七态逐字集合 + T2 字号 + T3 高对比色值 +
## 置灰机制废止 + 未知状态兜底。主菜单负例（关卡行不显示）为 T3 根因闭环断言。

const HUD_SCENE := "res://scenes/shared/gesture_hud.tscn"
const STATE := {"MAIN_MENU": 1, "OPENING_MOVIE": 2, "TALK": 3, "LEVEL": 4, "SETTLE": 5, "CATALOG": 6}

func _rows(hud: Control) -> Array:
	# 批次 U 偏离②：GuideList VBoxContainer→GridContainer（LEVEL 双列）——旧 as VBoxContainer
	# 对 GridContainer 返回 null（批次 P 坑⑤同族），helper 等价替换 as GridContainer
	return (hud.get_node("GuidePanel/GuideVBox/GuideList") as GridContainer).get_children()

func _texts(hud: Control) -> Array:
	var out: Array = []
	for r: Node in _rows(hud):
		out.append(String((r as Label).text))
	return out

func _dock(hud: Control, st: int) -> void:
	hud.call("apply_dock_state", st, false, false)

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
const DISC_BK_PREFIX := "user://_r2b_thr_backup_"
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
	print("EVID|user_restore|thr|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_t_hint_rows ==")
	_backup_user()
	var save: Variant = get_root().get_node("SaveManager")
	var p: String = ProjectSettings.globalize_path("user://save.json")
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
	save.load_game()
	var game: Variant = get_root().get_node("Game")
	var hud: Control = (load(HUD_SCENE) as PackedScene).instantiate()
	add_child(hud)
	await process_frame
	await process_frame
	var src: String = FileAccess.get_file_as_string("res://scenes/shared/gesture_hud.gd")
	# ---- 段 1. 常量终态（13 checks）----
	check_eq(int(hud.get("HINT_FONT_MAIN")), 15, "X-P1b：HINT_FONT_MAIN=15（批次 X 由 14 +1 档；FB h15=22 实测 4 行恰满 116/88，旧 14 等价替换留痕）")
	check_eq(float(hud.get("HINT_ROW_H_MAIN")), 20.0, "T2：HINT_ROW_H_MAIN=20.0（行高 min 常量不动，有效行高随字号实高上浮）")
	check_eq(int(hud.get("HINT_FONT_LEVEL")), 12, "X-P1b：HINT_FONT_LEVEL=12（批次 X 由 10 +2 档起步；FB h12=17：6×17=102≤110、Noto 18：108≤110 实测放行，旧 J1 保守 10 等价替换留痕）")
	check_eq(float(hud.get("HINT_ROW_H_LEVEL")), 15.0, "T2/J1：HINT_ROW_H_LEVEL=15.0（min 常量不动）")
	check_eq(int(hud.get("HINT_FONT_CATALOG")), 14, "X-P1b：HINT_FONT_CATALOG=14（批次 X 由 13 +1 档；FB h14=20：6×20=120 恰满，旧 13 等价替换留痕）")
	check_eq(float(hud.get("HINT_ROW_H_CATALOG")), 17.0, "T2：HINT_ROW_H_CATALOG=17.0（min 常量不动）")
	check_eq(int(hud.get("STATUS_FONT")), 13, "T2：STATUS_FONT=13（旧 11 等价替换留痕）")
	check((hud.get("PANEL_BG_DARK") as Color).is_equal_approx(Color(0.20, 0.15, 0.07, 0.85)),
		"T3：PANEL_BG_DARK=(0.20,0.15,0.07,0.85)（批次 S α0.78→0.85 留痕）")
	check(hud.get("PANEL_BG_LIGHT") == null,
		"AB-3 反向锁：PANEL_BG_LIGHT 浅档常量随深浅主题机制删除退役（无复辟）")
	check((hud.get("TEXT_DARK") as Color).is_equal_approx(Color("#F7EDD6")),
		"T3：TEXT_DARK=#F7EDD6（批次 S #F2E6C8 提亮留痕）")
	check(hud.get("TEXT_LIGHT") == null,
		"AB-3 反向锁：TEXT_LIGHT 浅档字色常量随深浅主题机制删除退役（无复辟）")
	check((hud.get("NO_HAND_GRAY") as Color).is_equal_approx(Color("#B5B5B5")),
		"T3：NO_HAND_GRAY=#B5B5B5（批次 S #8A8A8A 提亮留痕，深底对比 ≈7:1）")
	check(not src.contains("GRAY_ALPHA") and not src.contains("GESTURE_TABLE12"),
		"T1/T3：GESTURE_TABLE12/kind/GRAY_ALPHA/LEVEL_ONLY_SUFFIX 置灰机制整体废止（源码证据）")
	check_eq((hud.get("GLOBAL_HINT_ROWS") as Array).size(), 4,
		"V9/V14：GLOBAL_HINT_ROWS 恰 4 行（HANDS/G_MOVE/G_CLICK/G_EXIT，批次 V spec §7.1 新增）")
	# ---- 段 2. MAIN_MENU 4 全局行（批次 V 等价替换 V9，spec §7.1：4 checks；旧 3 行 MOVE/CLICK/EXIT 逐字断言退役留痕）----
	_dock(hud, STATE["MAIN_MENU"])
	check_eq(_texts(hud).size(), 4, "V9：MAIN_MENU 恰 4 行（旧 3 行等价替换留痕）")
	# 批次 X（P5-c）等价改写 → 批次 AA（W3-5，spec §6.4-B）：ROW_G_CLICK 随单击语义改「食指+中指」全称
	var mm_expect: Array = ["左/右手状态 状态条实时显示", "移动光标 【左/右】竖起食指", "单击确认 【左/右】食指+中指", "退出 【双手】四指同翻"]
	var mm_ok := true
	for i: int in 4:
		if _texts(hud)[i] != mm_expect[i]:
			mm_ok = false
	check(mm_ok, "X4/W3-5：MAIN_MENU=GLOBAL 四行逐字（ROW_HANDS/ROW_G_MOVE/ROW_G_CLICK 食指+中指版/ROW_G_EXIT；W2 旧「竖起中指」留痕）")
	check(not String(_texts(hud)[0]).begins_with("1 "), "V9：全局行无序号前缀（不复用带序号 LEVEL 系常量）")
	check_eq(int((_rows(hud)[0] as Label).get_theme_font_size("font_size")), 15, "X-P1b：全局行字号 15（HINT_FONT_MAIN 族随 P1-b 新值 live 同步）")
	# ---- 段 3. 开场/对话 4 全局行（批次 V 等价替换 V9：4 checks；旧 2 行逐字断言退役留痕）----
	_dock(hud, STATE["OPENING_MOVIE"])
	check_eq(_texts(hud).size(), 4, "V9：OPENING_MOVIE 恰 4 行（旧 2 行等价替换留痕）")
	check(String(_texts(hud)[0]) == "左/右手状态 状态条实时显示" and String(_texts(hud)[3]) == "退出 【双手】四指同翻",
		"X4：开场 HANDS/EXIT 行逐字（手别标注版；旧「退出 双手四指同翻」留痕）")
	check(String(_texts(hud)[1]) == "移动光标 【左/右】竖起食指" and String(_texts(hud)[2]) == "单击确认 【左/右】食指+中指",
		"X4/W3-5：开场 G_MOVE/G_CLICK 行逐字（ROW_G_CLICK 食指+中指全称版）")
	# 批次 X（P5-c）宽度定档锚：OPENING_MOVIE/TALK/SHOP/SETTINGS/UNKNOWN 同用 224 宽 hint
	#（content margin 6×2 → 净宽 212）=全局行最紧预算；字号 15 手别标注版不得截断
	var g_okw := true
	var g_maxw: float = 0.0
	for r2: Node in _rows(hud):
		var gl := r2 as Label
		var gw: float = (gl.get_theme_font("font") as Font).get_string_size(
			gl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, gl.get_theme_font_size("font_size")).x
		g_maxw = maxf(g_maxw, gw)
		if gw > 212.0:
			g_okw = false
	check(g_okw, "X4：全局行实测文本宽 ≤212（224 hint 净宽 clip 红线；最宽行 %.1fpx）" % g_maxw)
	_dock(hud, STATE["TALK"])
	check_eq(_texts(hud), ["左/右手状态 状态条实时显示", "移动光标 【左/右】竖起食指", "单击确认 【左/右】食指+中指", "退出 【双手】四指同翻"],
		"X4/W3-5：TALK 与开场同集合=GLOBAL（逐字数组比较，ROW_G_CLICK 食指+中指版）")
	# ---- 段 4. LEVEL 13 行（批次 AA W3-5 等价改写，spec §6.4-A：13 行 = 11 条手势 + 1 图例
	# 行 + 1 参考框行；旧「12 手势（含激活面板/选块两行）+ 参考框」随 §6.3 W3-5 文案表退役——
	# 「激活面板/选块」并入第 2 行「单击/选块」，新增 ROW_LEGEND 图例行承载简写全称；
	# 列高预算 7×15=105≤110 复核不变；行宽红线 170 见段 4b）----
	_dock(hud, STATE["LEVEL"])
	check_eq(_texts(hud).size(), 13, "T1（W3-5 等价改写）：LEVEL 恰 13 行（11 手势 + 图例 + 参考框；旧 12 手势+参考框退役留痕）")
	# 批次 AA（W3-5，spec §6.4-A）文案表定稿逐字：LEVEL 内指名用简写（食/中/无名）、全称由
	# 图例行给出；手别经 gesture_map/router 门控核实照实标注（移动/单击/缩放/撤销/退出=左/右、
	# 减选与清空=右、旋转与删除=左、对接与退出=双手）。宽度实测定档见段 4b 与
	# test_aa_gesture_remap 段 5d（旧「3 激活面板/4 选块划选/8 取消 竖四指清空」等行退役留痕）：
	var lv_expect: Array = ["1 移动光标【左/右】食指", "2 单击/选块【左/右】食+中",
		"3 减选【右】食+中", "4 旋转视角【左】食+中", "5 缩放【左/右】手掌推拉",
		"6 删除/挖除【左】食+中+无名", "7 清空选择【双手】握拳", "8 撤销/重做【左/右】掌翻转",
		"9 对接尝试【双手】食+中", "10 退出【双手】四指同翻", "11 聚焦/锐眼 走屏幕按钮",
		"食=食指 中=中指 无名=无名指", "参考框=推荐活动区"]
	var lv_rows: Array = _texts(hud)
	var lv_ok := true
	for i: int in 13:
		if lv_rows[i] != lv_expect[i]:
			lv_ok = false
	check(lv_ok, "X4/W3-5：LEVEL 13 行逐字等于 §6.4-A 文案表（序号 1~11 跨场景一致，循环展开 13；P5-c 表退役留痕）")
	# ---- 段 4b. 行宽定档（批次 X P5-c：「不换行不截断」红线实测锚——LEVEL 双列列宽 170
	# clip_text=true，超宽即截断；用行字体（_hint_row_font=Noto 变体，测试/生产同语境）实测定档）----
	var lv_okw := true
	var lv_maxw: float = 0.0
	var lv_over: Array = []
	for r: Node in _rows(hud):
		var lb := r as Label
		var w: float = (lb.get_theme_font("font") as Font).get_string_size(
			lb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, lb.get_theme_font_size("font_size")).x
		lv_maxw = maxf(lv_maxw, w)
		if w > 170.0:
			lv_okw = false
			lv_over.append("%s=%.1f" % [lb.text, w])
	check(lv_okw, "X4：LEVEL 每行实测文本宽 ≤170（双列列宽 clip 红线；最宽行 %.1fpx；超宽清单 %s）" % [lv_maxw, lv_over])
	# ---- 段 5. CATALOG 6 行（批次 V 等价替换 V14，spec §7.1：4 checks）----
	_dock(hud, STATE["CATALOG"])
	check_eq(_texts(hud).size(), 6, "V14：CATALOG 恰 6 行（GLOBAL 4+旋转/缩放 2；旧 5 行等价替换留痕）")
	var cat_expect: Array = ["左/右手状态 状态条实时显示", "移动光标 【左/右】竖起食指", "单击确认 【左/右】食指+中指",
		"退出 【双手】四指同翻", "4 旋转视角【左】食+中", "5 缩放【左/右】手掌推拉"]
	var cat_ok := true
	for i: int in 6:
		if _texts(hud)[i] != cat_expect[i]:
			cat_ok = false
	check(cat_ok, "X4/W3-5：CATALOG=GLOBAL+[ROW_ROTATE,ROW_ZOOM] 逐字（循环展开 6；§6.4-A 序 4/5 新表，P5-c 表退役留痕）")
	check_eq(int((_rows(hud)[0] as Label).get_theme_font_size("font_size")), 14, "X-P1b：CATALOG 行字号 14 生效（HINT_FONT_CATALOG 族随 P1-b 新值 live 同步）")
	check_eq(int((_rows(hud)[5] as Label).get_theme_font_size("font_size")), 14, "X-P1b：CATALOG 尾行（ROW_ZOOM）字号 14 生效（保留行同族；文案逐字断言本波不动）")
	# ---- 段 6. SHOP 4 全局行＋设置 4 全局行（批次 V 等价替换 V14，spec §7.1：9 checks）----
	# 旧段（U5⑦）2 专用短行 SHOP_MIN_HINTS 退役留痕：恰 2 行/「食指=光标」/「中指=单击」逐字/
	# SCENE_HINTS["SHOP"]==SHOP_MIN_HINTS 同源引用——批次 V SHOP 并入四全局行组、常量退役。
	hud.call("apply_dock_state", STATE["MAIN_MENU"], false, true)   # shop_open=true
	check_eq(_texts(hud).size(), 4, "V14：SHOP 覆盖层恰 4 行=GLOBAL（旧 2 短行 U5⑦ 语义退役留痕）")
	check(String(_texts(hud)[0]) == "左/右手状态 状态条实时显示" and String(_texts(hud)[1]) == "移动光标 【左/右】竖起食指",
		"X4：SHOP 全局行 1/2 逐字（手别标注版）")
	check(String(_texts(hud)[2]) == "单击确认 【左/右】食指+中指" and String(_texts(hud)[3]) == "退出 【双手】四指同翻",
		"X4/W3-5：SHOP 全局行 3/4 逐字（ROW_G_CLICK 食指+中指版）")
	check(not String(_texts(hud)[0]).begins_with("1 "), "V9：SHOP 全局行无序号前缀（与 13 条规范行体系区分，U5⑦ 判据沿用）")
	var hud_script: GDScript = load("res://scenes/shared/gesture_hud.gd")
	check(hud_script.get("SCENE_HINTS")["SHOP"] == hud_script.get("GLOBAL_HINT_ROWS"),
		"V14：SCENE_HINTS[\"SHOP\"] 与 GLOBAL_HINT_ROWS 同源引用（旧 SHOP_MIN_HINTS 同源断言等价替换）")
	check(not FileAccess.get_file_as_string("res://scenes/shared/gesture_hud.gd").contains("SHOP_MIN_HINTS"),
		"V14：SHOP_MIN_HINTS 常量退役删除（源码证据；旧 2 短行语义退役留痕）")
	hud.call("apply_dock_state", STATE["MAIN_MENU"], true, false)   # settings_open=true
	check_eq(_texts(hud).size(), 4, "V9：设置覆盖层恰 4 行=GLOBAL（旧 3 行等价替换留痕）")
	check(String(_texts(hud)[1]) == "移动光标 【左/右】竖起食指" and String(_texts(hud)[3]) == "退出 【双手】四指同翻",
		"X4：设置行 G_MOVE/G_EXIT 逐字（手别标注版）")
	check(hud_script.get("SCENE_HINTS")["SETTINGS"] == hud_script.get("GLOBAL_HINT_ROWS"),
		"V9：SCENE_HINTS[\"SETTINGS\"] 与 GLOBAL_HINT_ROWS 同源引用（批次 V §7.1）")
	hud.call("apply_dock_state", 1, false, false)
	# ---- 段 7. SETTLE 5 行（批次 V 等价替换 V14，spec §7.1：4 checks）----
	_dock(hud, STATE["SETTLE"])
	check_eq(_texts(hud).size(), 5, "V14：SETTLE 恰 5 行（GLOBAL 4+点云行；旧单行等价替换留痕）")
	check_eq(_texts(hud)[0], "左/右手状态 状态条实时显示", "V14：SETTLE 首行=ROW_HANDS（旧「单击=选钮…」单行断言移至尾行等价替换）")
	# 批次 X（P5-c）→ 批次 AA（W3-5，spec §6.4-C）等价改写：掌缩放随 W3-1 双手通用 →【左/右】
	#（拖转仍左手专属；旧「掌缩放【左】」与「单击=选钮 · 二指拖=转 · 掌=缩放」两版留痕）
	check_eq(_texts(hud)[4], "点选钮【左/右】·拖转/掌缩放【左/右】", "X4/W3-5：SETTLE 尾行=点云行双手缩放版（§6.4-C 定稿）")
	check_eq(int((_rows(hud)[0] as Label).get_theme_font_size("font_size")), 12, "T2：SETTLE 行 font 12")
	var se_l := _rows(hud)[4] as Label
	var se_w: float = (se_l.get_theme_font("font") as Font).get_string_size(
		se_l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, se_l.get_theme_font_size("font_size")).x
	# SETTLE 尾行宽度定档（批次 AA W3-5：hint 宽 224→**240** —— 定稿点云行「…掌缩放【左/右】」
	# 实测 219px > 旧 224−12=212 净宽，按 spec §6.4-B「面板加宽」逃生舱抬到 240 → 净宽 228；
	# 同源改点=gesture_hud._dock_cfg SETTLE hint 分支；clip_text=true 截断红线锚同步 212→228）
	check(se_w <= 228.0, "X4/W3-5：SETTLE 尾行实测宽 ≤228（240 hint 净宽 clip 红线；实际 %.1fpx；旧 212 锚随加宽退役）" % se_w)
	# ---- 段 8. 主菜单负例（1 check）----
	_dock(hud, STATE["MAIN_MENU"])
	var bad := false
	for t: String in ["挖除", "取消选择", "清空选择", "聚焦", "撤销", "对接", "缩放视角"]:
		for txt: String in _texts(hud):
			if txt == t or txt.contains(t):   # plan 代码块修正：String(Array) 构造不存在，改逐行 contains（语义不变）
				bad = true
	check(not bad, "T3：主菜单不存在任何关卡专属行字样（挖除/取消/清空/聚焦/撤销/对接/缩放，7 词逐一）")
	# ---- 段 9. 未知状态兜底（批次 V 等价替换 V9，spec §7.1 FALLBACK=GLOBAL：3 checks）----
	# 批次 Y 审查② P1-2 等价注入：apply_dock_state 收口 AND 流开启真值——兜底可见断言需
	# 开启真值在场（camera_opened 事件注入）
	get_root().get_node("GestureBridge").simulate_packet(JSON.stringify({"type": "camera_opened", "id": 0, "name": "HD Camera"}))
	await process_frame
	hud.call("apply_dock_state", 99, false, false)
	check(hud.visible, "T1：未知状态兜底可见（UNKNOWN 兜底三件套，不再全隐）")
	check_eq(_texts(hud).size(), 4, "V9：未知状态兜底 4 行=GLOBAL（旧 3 行等价替换留痕；SCENE_HINTS_FALLBACK 经 _build_list 生效）")
	check_eq(_texts(hud)[0], "左/右手状态 状态条实时显示", "V9：兜底首行=ROW_HANDS（旧 MOVE 等价替换留痕）")
	hud.call("apply_dock_state", 1, false, false)
	# ---- 段 10. modulate 恒 1.0（2 checks）----
	var gray_free := true
	for r: Node in _rows(hud):
		if float((r as Label).modulate.a) < 0.99:
			gray_free = false
	check(gray_free, "T3：主菜单全部行 modulate.a==1.0（置灰根除）")
	_dock(hud, STATE["LEVEL"])
	var gray_free2 := true
	for r: Node in _rows(hud):
		if float((r as Label).modulate.a) < 0.99:
			gray_free2 = false
	check(gray_free2, "T3：LEVEL 全部行 modulate.a==1.0（无第三种灰字）")
	# ---- 段 11. 行字号生效（3 checks）----
	check_eq(int((_rows(hud)[0] as Label).get_theme_font_size("font_size")), 12, "X-P1b：LEVEL 行字号 12 生效（批次 X 由 10 提升；旧 J1 锚等价替换留痕）")
	_dock(hud, STATE["MAIN_MENU"])
	check_eq(int((_rows(hud)[0] as Label).get_theme_font_size("font_size")), 15, "X-P1b：MAIN_MENU 行字号 15 生效（随 P1-b 新值 live 同步）")
	check_eq(float((_rows(hud)[0] as Label).custom_minimum_size.y), 20.0, "T2：MAIN_MENU 行 min 高 20（J2：容器实高按字体实高 22 适配，探针回填，见 TE-4）")
	# ---- 段 12. LEVEL 行高（2 checks）----
	_dock(hud, STATE["LEVEL"])
	check_eq(float((_rows(hud)[0] as Label).custom_minimum_size.y), 15.0, "T2/J1：LEVEL 行 min 高 15")
	check_eq(float((_rows(hud)[0] as Label).custom_minimum_size.x), 170.0, "T2/U5④：LEVEL 行 min 宽 170（批次 U 偏离②双列列宽；规格 176 未计 PanelContainer margin 6×2，170×2+16=368−12 恰满，等价替换留痕）")
	_dock(hud, 1)
	hud.queue_free()
	finish()
