extends "res://tests/test_base.gd"
## 批次 Z Z3（spec §3-7 验收⑤，用户拍板）：**商店在剧情对话期间拦截**红测——
##   **购买与装配都拦**，提示文案逐字「剧情对话期间无法改变装配」；
## 判据：Game.current_state()==Game.State.TALK；落点=shop_panel._on_select（装配 / 发起购买确认）
##   与 _on_confirmed（完成购买扣费）；
## 通道：提示经 Game.info → toast(centered) → TopStrip push_info（StripSpy 夹具捕获，逐字断言；
##   test_shop_panel 同款夹具形态）；
## 回归：**非 TALK 态购买/装配零变化**——确认条文案逐字、扣费 205、owned/equipped 全链照旧；
##   键鼠路径（buy_btn.pressed / 卡片选择链）驱动（无头鼠标 GUI 命中不可用 → 信号 emit/直调处理器）。
## 清档纪律：购买/穿戴/状态机穿戴均写档 → user:// 备份还原（独立前缀 zsg，规范六条）。

const SHOP_SCENE := "res://scenes/shop/shop_panel.tscn"
const SHOP_SCRIPT := "res://scenes/shop/shop_panel.gd"
const CATALOG := "res://data/skin_catalog.gd"
const GUARD_TEXT := "剧情对话期间无法改变装配"
const PAID_ID := "skin_07"     # 付费 205（test_skin_origin 目录契约）
const PAID_PRICE := 205
const ALT_EQUIP_ID := "skin_01"      # 目录内、初始未 owned——经前置购置转 owned 的装配探针

## TopStrip 替身（test_shop_panel/V-C5 同款）：记录 push_confirm/push_info 调用参数。
class StripSpy extends Node:
	var confirm_calls: Array = []   # 每项 [text, on_confirmed, on_canceled]
	var info_calls: Array = []      # 每项 [text, seconds]
	func push_confirm(text: String, on_confirmed: Callable = Callable(),
			on_canceled: Callable = Callable()) -> void:
		confirm_calls.append([text, on_confirmed, on_canceled])
	func push_info(text: String, seconds: float = 3.0) -> void:
		info_calls.append([text, seconds])
	func get_confirm_calls() -> Array:
		return confirm_calls
	func get_info_calls() -> Array:
		return info_calls

var ssp: Node

# ===== 清档纪律（tools/README_走查清档规范.md）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_zsg_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _pre_save_text: String = ""

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _disc_del(p: String) -> void:
	var a: String = _disc_abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _backup_user() -> void:
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))

func _restore_user() -> void:
	for c: Node in root.get_children():
		if not DISC_AUTOLOADS.has(String(c.name)):
			c.free()
	for p: String in DISC_WATCHED:
		_disc_del(p)
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|zsg|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _last_info() -> String:
	var calls: Array = ssp.call("get_info_calls")
	if calls.is_empty():
		return ""
	return String((calls[calls.size() - 1] as Array)[0])

func _initialize() -> void:
	print("== test_z_shop_talk_guard ==")
	_backup_user()
	var save: Variant = root.get_node("SaveManager")
	var game: Variant = root.get_node("Game")
	ssp = StripSpy.new()
	add_child(ssp)
	game.call("attach_strip", ssp)

	# 默认档清档后重载 + 手笔金额归零（绝对值链可控）+ 非 TALK 前置购置装配探针
	# （skin_default 不在 SkinCatalog 目录内——grep 实证；装配探针须为目录内 owned 皮肤）
	for p: String in DISC_WATCHED:
		_disc_del(p)
	save.load_game()
	save.spend_talent(save.get_talent())
	save.add_talent(1000)

	var container: Control = Control.new()
	container.size = Vector2(1152, 648)
	add_child(container)
	var overlay: CanvasLayer = CanvasLayer.new()
	add_child(overlay)
	game.attach(container, overlay)
	await process_frame

	# ---- 0. 常量逐字锁（文件头部单点常量；缺键 → "" 必红）----
	var cmap: Dictionary = (load(SHOP_SCRIPT) as GDScript).get_script_constant_map()
	check_eq(String(cmap.get("TALK_GUARD_TEXT", "")), GUARD_TEXT,
		"常量：TALK_GUARD_TEXT==「剧情对话期间无法改变装配」（文件头部单点，实测「%s」）" % str(cmap.get("TALK_GUARD_TEXT", "")))

	# ---- 环境：非 TALK 起点 → 打开商店覆盖层（生产 open_overlay 链）→ 再进 TALK ----
	# 批次 AA / W5-2 夹具等价改写（2026-09-25，规格 §8.5-5「任一 goto_state 后
	# is_settings_open()/is_shop_open() 恒 false」强制语义）：旧夹具依赖「商店覆盖层跨
	# goto_state(TALK) 残留」的已退役行为——W5-2 起 goto_state 入口 close_overlay，旧序
	# 下 panel 引用 freed → call 打空 SCRIPT ERROR 中断 _initialize 挂死（回归实测 8min
	# 无输出判红实锤）。等价改写为**生产可达链**：① MAIN_MENU 开商店 → 进 TALK → 断言
	# 覆盖层零残留（W5-2 新锚 +1）② TALK 态重开商店（生产链=TALK→设置→商店入口，同
	# Game.open_overlay 链、零 goto 参与，本就合法）→ A/B/C 拦截与回归断言**逐条原样保持**，
	# panel 每次跨 goto 后重取在场实例。断言数 27 → 30（只增不减）。
	game.goto_state(int(game.State.MAIN_MENU))
	await process_frame
	check(bool(save.buy_skin(ALT_EQUIP_ID)), "前置：非 TALK 购入 %s（owned 装配探针就位）" % ALT_EQUIP_ID)
	check((save.get_skins()["owned"] as Array).has(ALT_EQUIP_ID), "前置：%s ∈ owned" % ALT_EQUIP_ID)
	game.open_overlay("shop")
	await process_frame
	var panel: Node = null
	if overlay.get_child_count() > 0:
		panel = overlay.get_child(overlay.get_child_count() - 1)
	check(panel != null, "前置：shop_panel 经 Game.open_overlay 打开")
	if panel == null:
		finish()
		return

	# ==================== A. TALK 态：装配被拦 ====================
	game.goto_state(int(game.State.TALK), {"mode": "after_level", "chapter": 1})
	await process_frame
	await process_frame
	check_eq(int(game.current_state()), int(game.State.TALK), "前置：当前 TALK 态（对话进行中）")
	check(not bool(game.is_shop_open()),
		"W5-2：goto_state(TALK) 后商店覆盖层零残留（规格 §8.5-5；旧实现跨态残留=红）")
	# TALK 态重开商店（拦截测点在场；生产可达链，无 goto 参与）
	game.open_overlay("shop")
	await process_frame
	panel = overlay.get_child(overlay.get_child_count() - 1) if overlay.get_child_count() > 0 else null
	check(panel != null and bool(game.is_shop_open()),
		"前置（AA 改写）：TALK 态商店重开就绪（A/B 拦截测点在场）")
	if panel == null:
		finish()
		return
	var st: Dictionary = save.get_skins()
	var eq_before: String = String(st["equipped"])
	var tal_before: int = int(save.get_talent())
	var info_before: int = (ssp.call("get_info_calls") as Array).size()
	var confirm_before: int = (ssp.call("get_confirm_calls") as Array).size()
	var catalog: GDScript = load(CATALOG)
	var alt_skin: Dictionary = {}
	for s: Variant in catalog.get_skins():
		if String((s as Dictionary).get("id", "")) == ALT_EQUIP_ID:
			alt_skin = s
	check(not alt_skin.is_empty() and (save.get_skins()["owned"] as Array).has(ALT_EQUIP_ID),
		"前置：%s 已 owned（装配链探针可用）" % ALT_EQUIP_ID)
	panel.call("_on_select", alt_skin)   # 装配路径（owned → equip_skin 分支）
	var st2: Dictionary = save.get_skins()
	check_eq(String(st2["equipped"]), eq_before, "A：TALK 态装配被拦（equipped 不变；红：现状直接穿戴）")
	check_eq((ssp.call("get_info_calls") as Array).size(), info_before + 1,
		"A：TALK 态装配 → TopStrip info 恰 +1（红：现状零提示）")
	check_eq(_last_info(), GUARD_TEXT, "A：info 文案逐字==「剧情对话期间无法改变装配」（实测「%s」）" % _last_info())

	# ==================== B. TALK 态：购买被拦（不发起确认 + 不扣费） ====================
	var paid_skin: Dictionary = {}
	for s2: Variant in catalog.get_skins():
		if String((s2 as Dictionary).get("id", "")) == PAID_ID:
			paid_skin = s2
	check(not paid_skin.is_empty() and int(paid_skin.get("price", -1)) == PAID_PRICE,
		"前置：skin_07 在目录且价 205（test_skin_origin 目录契约）")
	panel.call("_on_select", paid_skin)  # 未拥有付费 → 正常态会 Game.confirm 发起确认
	check_eq((ssp.call("get_confirm_calls") as Array).size(), confirm_before,
		"B：TALK 态购买不发起确认条（_on_select 拦截；红：现状 +1）")
	# 模拟「确认条挂起后回调落进 TALK」：直设 _selected → _on_confirmed
	panel.set("_selected", paid_skin)
	panel.call("_on_confirmed")
	var st3: Dictionary = save.get_skins()
	check_eq(int(save.get_talent()), tal_before, "B：TALK 态 _on_confirmed 不扣费（红：现状 -205）")
	check(not (st3["owned"] as Array).has(PAID_ID), "B：TALK 态 _on_confirmed 不入 owned（红：现状购买成功）")
	check_eq(String(st3["equipped"]), eq_before, "B：TALK 态 _on_confirmed 不自动穿戴")
	check_eq(_last_info(), GUARD_TEXT, "B：购买拦截 info 文案逐字（实测「%s」）" % _last_info())
	check_eq((ssp.call("get_info_calls") as Array).size(), info_before + 3,
		"B：三处拦截各恰一次提示（装配1 + 发起购买1 + 完成购买兜底1）→ info 累计恰 +3")

	# ==================== C. 非 TALK 态：购买/装配回归零变化 ====================
	game.goto_state(int(game.State.MAIN_MENU))
	await process_frame
	await process_frame
	check(int(game.current_state()) != int(game.State.TALK), "C：前置已离开 TALK 态")
	# 批次 AA / W5-2 夹具等价改写（续）：goto MAIN_MENU 同样关层（覆盖层零残留）→
	# panel 引用已释放，重开商店取新实例（生产链=主菜单→设置→商店，同 open_overlay 链），
	# C 段全部回归断言逐条原样保持。
	check(not bool(game.is_shop_open()),
		"W5-2：goto_state(MAIN_MENU) 后商店覆盖层零残留（规格 §8.5-5）")
	game.open_overlay("shop")
	await process_frame
	panel = overlay.get_child(overlay.get_child_count() - 1) if overlay.get_child_count() > 0 else null
	check(panel != null, "前置（AA 改写）：MAIN_MENU 态商店重开（C 段回归测点在场）")
	if panel == null:
		finish()
		return
	save.add_talent(1000)
	var tal_c0: int = int(save.get_talent())
	var info_c0: int = (ssp.call("get_info_calls") as Array).size()
	panel.call("_show_detail", paid_skin)
	var buy_btn: Variant = panel.get("buy_btn")
	check(buy_btn is Button, "C：详情购买钮在位")
	if buy_btn is Button:
		(buy_btn as Button).pressed.emit()   # 键鼠路径（无头 GUI 命中不可用 → pressed.emit）
	var confirms_c: Array = ssp.call("get_confirm_calls")
	check_eq(confirms_c.size(), confirm_before + 1, "C：非 TALK 购买发起确认条（+1，回归零变化）")
	if confirms_c.size() == confirm_before + 1:
		check_eq(String((confirms_c[confirms_c.size() - 1] as Array)[0]),
			"确认购买 %s（%d 天赋值）？" % [paid_skin["name"], PAID_PRICE],
			"C：非 TALK 购买确认文案逐字（回归零变化）")
		var cb: Callable = (confirms_c[confirms_c.size() - 1] as Array)[1]
		if cb.is_valid():
			cb.call()   # 确认 → _on_confirmed 扣费链
	var st4: Dictionary = save.get_skins()
	check((st4["owned"] as Array).has(PAID_ID), "C：非 TALK 购买成功入 owned（回归）")
	check_eq(String(st4["equipped"]), PAID_ID, "C：非 TALK 购买后自动穿戴（回归）")
	check_eq(int(save.get_talent()), tal_c0 - PAID_PRICE, "C：非 TALK 扣费 205（回归；实测 %d→%d）" % [tal_c0, int(save.get_talent())])
	check_eq((ssp.call("get_info_calls") as Array).size(), info_c0,
		"C：非 TALK 购买全程零拦截提示（回归零变化）")
	# 装配回归（非 TALK）：owned 直接穿戴生效、零拦截
	panel.call("_on_select", alt_skin)
	check_eq(String((save.get_skins())["equipped"]), ALT_EQUIP_ID, "C：非 TALK 装配直接生效（回归）")
	check_eq((ssp.call("get_info_calls") as Array).size(), info_c0, "C：非 TALK 装配零拦截提示（回归）")

	# 收尾：还原 strip 挂接（降级环境，test_shop_panel 同口径）+ 关覆盖层
	game.call("close_overlay")
	game.call("attach_strip", null)
	await process_frame
	finish()
