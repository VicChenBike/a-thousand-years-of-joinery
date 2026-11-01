extends "res://tests/test_base.gd"
## 批次 P 波 1 小型修复合批判定用例（P1/P2/P3，TDD 红灯先行，2026-09-10）。
## 契约来源：批次 P 用户反馈 + 调研结论（plan 批次 P 波 1）：
##   P1 设置面板开关调深（用户截图红圈：三开关亮金与周边深棕按钮不匹配）：开启态弃高饱和
##     亮金 (0.902,0.722,0,0.85)，改深棕底（深 (0.38,0.27,0.10,0.85)==theme_dark normal 档 /
##     浅 (0.72,0.55,0.08,0.85)）+金描边 (1,0.922,0.706,0.4)（仅开启态有）+字色米黄浅金
##     (0.96,0.90,0.78)（深）/深棕 (0.227,0.165,0.063)（浅）==N12 按钮字色档；关闭态保持
##     灰半透明底+灰字且**无描边**（区分维度=「有金描边+浅字=开 / 灰底灰字=关」，不再靠
##     高饱和亮金）；圆角 10→12 对齐主题按钮；hover 态开启用 hover 深档（深
##     (0.34,0.24,0.09,0.85)==theme_dark hover 档 / 浅 (0.62,0.47,0.07,0.85)==theme_light hover 档）。
##   P2 删除「关卡进度不保留」冲突文案（进度已能存=N9 断点链，提示与实际行为冲突）：
##     EXIT_MENU_TEXT="返回主菜单？"、EXIT_CATALOG_TEXT="返回图鉴？"。
##   P3 图鉴退出全透传扩展（用户口径：像商店一样「什么时候打开就退回去」）：
##     catalog_return 来源==OPENING_MOVIE/TALK → goto_state(旧态, 快照ctx) 全透传
##     （MOVIE 重播开场动画、TALK 重进对应章节对话，属可接受行为，报告注明）；
##     LEVEL 透传（O5 既有）不回归；SETTLE 暂维持降级 MAIN_MENU（P批波2待办：波 2 结算
##     架构重做将改变 SETTLE 态语义，届时统一调整）；MAIN_MENU/无记忆兜底 MAIN_MENU；
##     消费后复位防串味。
## 环境说明：--script 无头模式 autoload 在 /root/<Name>；State 枚举 MAIN_MENU=1
## OPENING_MOVIE=2 TALK=3 LEVEL=4 SETTLE=5 CATALOG=6；无头 DisplayServer.is_dark_mode()
## 恒 false（浅档分支生效）→ 深浅两套色值经 settings_panel.gd 脚本常量表锁定，运行时按
## is_dark() 当前分支取期望（窗口机两分支由走查截图补证）；起测前备份 user:// 档案、
## 终测还原（N10/O 同规）。

const SETTINGS_SCENE := "res://scenes/settings/settings_panel.tscn"
const SETTINGS_GD := "res://scenes/settings/settings_panel.gd"
const LEVEL_GD := "res://scenes/level/level_scene.gd"
const CATALOG_GD := "res://scenes/catalog/catalog_scene.gd"
const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const BK_SAVE := "user://_p_backup_save.json"
const BK_FLAG := "user://_p_backup_flag.flag"

const ST_MAIN_MENU := 1
const ST_MOVIE := 2
const ST_TALK := 3
const ST_LEVEL := 4
const ST_SETTLE := 5
const ST_CATALOG := 6

func _backup_user() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(BK_SAVE))
	if FileAccess.file_exists(FLAG_PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(FLAG_PATH), ProjectSettings.globalize_path(BK_FLAG))

func _restore_user() -> void:
	for pair: Array in [[BK_SAVE, SAVE_PATH], [BK_FLAG, FLAG_PATH]]:
		if FileAccess.file_exists(String(pair[0])):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(String(pair[0])), ProjectSettings.globalize_path(String(pair[1])))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(String(pair[0])))
	var sm: Node = get_root().get_node_or_null("SaveManager")
	if sm != null:
		sm.load_game()

## 源码去注释行（行首 # 的独立注释行剔除）——留痕注释允许记载旧值，
## 「残留清零」判定只对有效代码行生效。
func _code_lines_only(path: String) -> String:
	var out: PackedStringArray = []
	for line: String in FileAccess.get_file_as_string(path).split("\n"):
		if not line.strip_edges().begins_with("#"):
			out.append(line)
	return "\n".join(out)

func _initialize() -> void:
	print("== test_p_wave1 ==")
	_backup_user()
	var save: Variant = get_root().get_node("SaveManager")
	var game: Variant = get_root().get_node("Game")
	save.load_game()  # 重置默认存档
	# AF 同步批（2026-11-01）：段 1「开启态」断言的隐含前提钉住——P1 原口径「默认全开」依赖
	# 跑测环境存档 gesture_input=true；用户存档 Q3 双关（gesture_input=false）时面板从存档恢复
	# 关态，「GestureToggle 默认开」前置不成立属环境红非代码回归（样式断言本体测的是开启态
	# 样式装配，与开关初值正交）。update_settings 即时落盘，由本文件 _backup_user/_restore_user
	# 纪律兜底（收口还原原档）。
	save.update_settings({"gesture_input": true})
	var container: Control = Control.new()
	add_child(container)
	var overlay: CanvasLayer = CanvasLayer.new()
	add_child(overlay)
	game.attach(container, overlay)

	# ==================== 段 1：P1 开关调深（常量表 + 运行时两态样式） ====================
	print("-- 段1 P1 开关调深 --")
	check(ResourceLoader.exists(SETTINGS_SCENE), "前置：settings_panel.tscn 存在")
	var sp_script: Script = load(SETTINGS_GD)
	check(sp_script != null, "前置：settings_panel.gd 可加载")
	# 1a 常量表锁定（深浅两套全量色值；get() 取常量，test_m_readability 同口径）
	check(sp_script != null and sp_script.get("TOGGLE_ON_BG_DARK") == Color(0.38, 0.27, 0.10, 0.85),
		"P1：TOGGLE_ON_BG_DARK=(0.38,0.27,0.10,0.85)（==theme_dark normal 档；P批等价替换原亮金 (0.902,0.722,0,0.85)）")
	# 批次 AB-3：TOGGLE_ON_BG_LIGHT/TOGGLE_ON_HOVER_LIGHT 浅档常量随深浅主题机制删除退役——反向锁。
	check(sp_script != null and sp_script.get("TOGGLE_ON_BG_LIGHT") == null,
		"AB-3 反向锁：TOGGLE_ON_BG_LIGHT 浅档常量退役（无复辟）")
	check(sp_script != null and sp_script.get("TOGGLE_ON_HOVER_LIGHT") == null,
		"AB-3 反向锁：TOGGLE_ON_HOVER_LIGHT 浅档常量退役（无复辟）")
	check(sp_script != null and sp_script.get("TOGGLE_ON_HOVER_DARK") == Color(0.34, 0.24, 0.09, 0.85),
		"P1：TOGGLE_ON_HOVER_DARK=(0.34,0.24,0.09,0.85)（==theme_dark hover 档）")
	check(sp_script != null and sp_script.get("TOGGLE_BORDER_GOLD") == Color(1, 0.922, 0.706, 0.4),
		"P1：TOGGLE_BORDER_GOLD=(1,0.922,0.706,0.4)（金描边，L2 卡顶缘高光同族）")
	check(sp_script != null and sp_script.get("TOGGLE_ON_FONT_DARK") == Color(0.96, 0.90, 0.78, 1),
		"P1：TOGGLE_ON_FONT_DARK=(0.96,0.90,0.78)（米黄浅金==N12 深色按钮字色档；P批等价替换原深墨棕）")
	check(sp_script != null and sp_script.get("TOGGLE_ON_FONT_LIGHT") == null,
		"AB-3 反向锁：TOGGLE_ON_FONT_LIGHT 浅档常量退役（无复辟）")
	var cr_const: Variant = sp_script.get("TOGGLE_CORNER_RADIUS") if sp_script != null else null
	check(cr_const != null and int(cr_const) == 12,
		"P1：TOGGLE_CORNER_RADIUS=12（10→12 对齐主题按钮圆角）")
	var sp_src: String = _code_lines_only(SETTINGS_GD)
	check(not sp_src.contains("0.902"), "P1：settings_panel.gd 代码行亮金 (0.902,…) 残留清零（P批等价替换留痕见注释）")
	# 1b 运行时：开覆盖层验开启态（默认全开）/ hover / 关闭态
	game.open_overlay("settings")
	await process_frame
	# 批次 AF 终审备案族（语言钉扎先例=6411fae o_catalog_shop）：autoload _ready 推迟至树激活，
	# 须等一帧后钉 zh——用户真实存档现 language=en，不钉则文案断言呈 en 态假红。
	# 编译窗安全：经节点查找而非全局名（--script 模式 autoload 全局名编译期未注册）。
	var i18n_node: Variant = get_root().get_node_or_null("I18n")
	if i18n_node != null:
		i18n_node.call("set_language", "zh")
	var panel: Node = overlay.get_child(overlay.get_child_count() - 1) if overlay.get_child_count() > 0 else null
	check(panel != null, "P1：设置覆盖层可打开")
	if panel != null:
		var gt: Button = panel.get_node_or_null("Panel/VBox/OptionsBox/GestureToggle") as Button
		check(gt is Button and (gt as Button).button_pressed, "P1：GestureToggle 默认开（开启态前置）")
		if gt != null:
			# 批次 AB-3：恒深档（is_dark() 探测与浅档分支随深浅主题机制删除退役，深档值不变）
			var on_sb: StyleBoxFlat = gt.get_theme_stylebox("normal") as StyleBoxFlat
			var exp_on: Color = Color(0.38, 0.27, 0.10, 0.85)
			check(on_sb != null and on_sb.bg_color == exp_on,
				"P1 运行时：开启态底色恒深档 (%s)（AB-3 唯一真值）" % str(exp_on))
			check(on_sb != null and on_sb.border_width_top >= 2 and on_sb.border_color == Color(1, 0.922, 0.706, 0.4),
				"P1 运行时：开启态有金描边 (1,0.922,0.706,0.4)（区分维度①）")
			check(on_sb != null and on_sb.corner_radius_top_left == 12, "P1 运行时：开启态圆角 12")
			var exp_font: Color = Color(0.96, 0.90, 0.78)
			check(gt.get_theme_color("font_color") == exp_font,
				"P1 运行时：开启态字色恒浅金档 (%s)（==N12 按钮字色档；AB-3 深棕浅档退役）" % str(exp_font))
			var on_hb: StyleBoxFlat = gt.get_theme_stylebox("hover") as StyleBoxFlat
			var exp_hover: Color = Color(0.34, 0.24, 0.09, 0.85)
			check(on_hb != null and on_hb.bg_color == exp_hover,
				"P1 运行时：开启态 hover=hover 深档 (%s)（与 normal 有区分）" % str(exp_hover))
			check(on_hb != null and on_sb != null and on_hb.bg_color != on_sb.bg_color,
				"P1 运行时：开启态 hover 与 normal 底色不同（hover 反馈保留）")
			# 拨关 → 灰底灰字无描边（区分维度②：无描边）
			gt.button_pressed = false
			var off_sb: StyleBoxFlat = gt.get_theme_stylebox("normal") as StyleBoxFlat
			var exp_off: Color = Color(0.35, 0.30, 0.22, 0.35)   # AB-3 恒深档（浅灰底退役）
			check(off_sb != null and off_sb.bg_color == exp_off,
				"P1 运行时：关闭态灰半透明底不变 (%s)（a<0.5 语义保持）" % str(exp_off))
			check(off_sb != null and off_sb.border_width_top == 0 and off_sb.border_width_left == 0,
				"P1 运行时：关闭态无描边（区分维度②：描边有=开/无=关）")
			check(gt.get_theme_color("font_color") == Color(0.85, 0.80, 0.70, 0.8),
				"P1 运行时：关闭态灰字不变（TOGGLE_OFF_FONT）")
			gt.button_pressed = true  # 恢复（即时落盘 true）
			check(gt.get_theme_stylebox("normal") != off_sb, "P1 运行时：拨回开态样式重生成（两态互斥）")
	game.close_overlay()
	await process_frame

	# ==================== 段 2：P2 退出确认文案删除「进度不保留」 ====================
	print("-- 段2 P2 弹窗文案 --")
	var lvl_script: Script = load(LEVEL_GD)
	check(str(lvl_script.get("EXIT_MENU_TEXT")) == "返回主菜单？",
		"P2：EXIT_MENU_TEXT=「返回主菜单？」（P批等价替换原「返回主菜单？（关卡进度不保留）」）")
	check(str(lvl_script.get("EXIT_CATALOG_TEXT")) == "返回图鉴？",
		"P2：EXIT_CATALOG_TEXT=「返回图鉴？」（重玩句整句简化，P批等价替换原「返回图鉴？（退出重玩，本关进度不保留）」）")
	var lvl_src: String = _code_lines_only(LEVEL_GD)
	check(not lvl_src.contains("进度不保留"), "P2：level_scene.gd 代码行「进度不保留」冲突文案清零（进度已能存；留痕见注释）")

	# ==================== 段 3：P3 图鉴退出全透传（MOVIE/TALK）+ 既有语义不回归 ====================
	print("-- 段3 P3 图鉴退出透传 --")
	var cs_src: String = FileAccess.get_file_as_string(CATALOG_GD)
	check(cs_src.contains("OPENING_MOVIE") and cs_src.contains("State.TALK"),
		"P3：catalog_scene.gd 退出分支含 MOVIE/TALK 透传（源码留痕）")
	check(cs_src.contains("P批波2"), "P3：SETTLE 分支含「P批波2」留痕（波 1 待办随波 2 结算架构重做兑现为透传）")
	# 3a MOVIE 来源透传（含 ctx 完整性）
	game.goto_state(ST_MOVIE, {"replay_video": true})
	await process_frame
	game.goto_state(ST_CATALOG)
	await process_frame
	var ret: Dictionary = game.get("catalog_return") if game.get("catalog_return") is Dictionary else {}
	check_eq(int(ret.get("state", -1)), ST_MOVIE, "P3：进图鉴快照来源 state=OPENING_MOVIE")
	check(bool(ret.get("ctx", {}).get("replay_video", false)), "P3：快照 ctx.replay_video=true（ctx 完整性前置）")
	var cat_panel: Node = container.get_child(container.get_child_count() - 1)
	(cat_panel.get_node("BottomBar/ExitButton") as Button).pressed.emit()
	await process_frame
	check_eq(int(game.current_state()), ST_MOVIE, "P3：MOVIE 来源 → 图鉴退出回开场动画（透传，非主菜单兜底）")
	check(bool(game.context().get("replay_video", false)), "P3：回 MOVIE ctx.replay_video 透传=true（快照 ctx 完整传回）")
	var cr: Variant = game.get("catalog_return")
	check(cr is Dictionary and (cr as Dictionary).is_empty(), "P3：MOVIE 路径消费后复位（防串味）")
	# 3b TALK 来源透传（含 mode/chapter ctx 完整性）
	game.goto_state(ST_TALK, {"mode": "after_level", "chapter": 2})
	await process_frame
	game.goto_state(ST_CATALOG)
	await process_frame
	ret = game.get("catalog_return") if game.get("catalog_return") is Dictionary else {}
	check_eq(int(ret.get("state", -1)), ST_TALK, "P3：进图鉴快照来源 state=TALK")
	cat_panel = container.get_child(container.get_child_count() - 1)
	(cat_panel.get_node("BottomBar/ExitButton") as Button).pressed.emit()
	await process_frame
	check_eq(int(game.current_state()), ST_TALK, "P3：TALK 来源 → 图鉴退出回剧情对话（透传，非主菜单兜底）")
	check_eq(String(game.context().get("mode", "")), "after_level", "P3：回 TALK ctx.mode 透传=after_level（快照 ctx 完整传回）")
	check_eq(int(game.context().get("chapter", -1)), 2, "P3：回 TALK ctx.chapter 透传=2（快照 ctx 完整传回）")
	cr = game.get("catalog_return")
	check(cr is Dictionary and (cr as Dictionary).is_empty(), "P3：TALK 路径消费后复位（防串味）")
	# 3c LEVEL 来源透传不回归（O5 语义保持）
	game.goto_state(ST_LEVEL, {"chapter": 3, "replay": true})
	await process_frame
	game.goto_state(ST_CATALOG)
	await process_frame
	cat_panel = container.get_child(container.get_child_count() - 1)
	(cat_panel.get_node("BottomBar/ExitButton") as Button).pressed.emit()
	await process_frame
	check_eq(int(game.current_state()), ST_LEVEL, "P3：LEVEL 来源透传不回归（O5：回关卡非主菜单）")
	check_eq(int(game.context().get("chapter", -1)), 3, "P3：LEVEL 透传 ctx.chapter=3（O5 语义保持）")
	# 3d SETTLE 来源透传（P批波2兑现：波 1「SETTLE 暂降级 MAIN_MENU」待办随波 2 结算架构
	# 重做改为透传回 SETTLE——结算已由 level 覆盖层承载，goto_state(SETTLE) 经 game.gd 特判
	# 按边缘路径重建 level 直显结算 UI；本处只断言状态机面，场景面归 test_p_settle）
	game.goto_state(ST_SETTLE, {"chapter": 1, "grade": "完美"})
	await process_frame
	game.goto_state(ST_CATALOG)
	await process_frame
	cat_panel = container.get_child(container.get_child_count() - 1)
	(cat_panel.get_node("BottomBar/ExitButton") as Button).pressed.emit()
	await process_frame
	check_eq(int(game.current_state()), ST_SETTLE,
		"P批波2等价替换：SETTLE 来源透传回结算（P批波2待办兑现——原降级 MAIN_MENU 随波 2 架构重做废止）")
	# 3e MAIN_MENU 来源兜底（旧契约不变）+ 无记忆兜底
	game.goto_state(ST_MAIN_MENU)
	await process_frame
	game.goto_state(ST_CATALOG)
	await process_frame
	cat_panel = container.get_child(container.get_child_count() - 1)
	(cat_panel.get_node("BottomBar/ExitButton") as Button).pressed.emit()
	await process_frame
	check_eq(int(game.current_state()), ST_MAIN_MENU, "P3：MAIN_MENU 来源兜底回主菜单（旧契约不变）")
	game.set("catalog_return", {"state": ST_LEVEL, "ctx": {"chapter": 1}})  # 造脏记忆
	game.goto_state(ST_MAIN_MENU)  # 非图鉴目标 → 应清空
	await process_frame
	cr = game.get("catalog_return")
	check(cr is Dictionary and (cr as Dictionary).is_empty(), "P3：非图鉴目标跳转清空脏记忆（双保险不变）")

	_restore_user()
	finish()
