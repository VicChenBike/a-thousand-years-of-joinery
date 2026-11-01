extends "res://tests/test_base.gd"
## 批次 V（V-C5，spec §3.2/§8）：三场景确认弹窗迁移 Game.confirm + 主菜单判据统一（TDD 先写）。
## 契约（迁移点文案逐字、语义逐字保持）：
##   main_menu：新游戏确认「新游戏将清除当前存档，确定重新开始吗？」（确认=清档+重建标记+进开场，
##     取消/缺省回调=零副作用）；退出确认「退出《千年一榫》？」（确认=stop+quit；无头环境
##     绝不触发 on_confirmed——会真退进程）。
##   shop：免费领取「免费领取 <名>？」/ 购买「确认购买 <名>（205 天赋值）？」——确认=领取/扣费
##     原链路；取消=零副作用（不扣费不入 owned）；失败分支中央提示经 strip info 承载。
##   level：重玩退出「返回图鉴？」/ 正常退出「返回主菜单？」——确认=挂起目标路由（先落断点）；
##     取消=挂起路由作废（_pending_exit_state 复位 -1）。
##   三场景迁移后源码级零旧弹窗实例化（grep 断言；旧组件文件本体保留不删，settle_scene 先例）。
##   主菜单判据矩阵（§8.3）：has_any_progress 三分支（flag∨watched∨cleared）驱动按钮两态——
##     存档有进度而 flag 丢失时「载入存档」不再灰禁（「进度看着丢了」病灶修复）。
## 4.7 坑对照：回调判空一律 is_valid()（坑 1）；spy 记录挂成员数组（坑 8 lambda 按值捕获）；
##   --script 时序 await process_frame（坑 5）；Game.confirm 用注册路径（attach_strip spy 替身，
##   未挂接兜底路径 test_v_game_confirm 已覆盖）；属性读取 .get 防御（坑 2）。
## 纪律：P2-5 load()/has_method()/call()，不引用全局类名；零摄像头。
## 清档纪律（tools/README_走查清档规范.md，批次V回修②P1-1 补齐）：本测试触碰 save.json 与
##   first_launch.flag 双件（V-C5 清档/重建标记语义）——起测前备份双件（及可触及的 .tmp/.bak），
##   终测逐字节还原并断言等价 + EVID 证据行；还原后真实 autoload load_game 重同步内存
##  （规范第 2 条）。

const MM_SCENE := "res://scenes/menu/main_menu.tscn"
const SHOP_SCENE := "res://scenes/shop/shop_panel.tscn"
const LEVEL_SCENE := "res://scenes/level/level_scene.tscn"
const CATALOG := "res://data/skin_catalog.gd"
const FLAG_PATH := "user://first_launch.flag"
const SAVE_PATH := "user://save.json"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"
# 备份路径必须带全 user:// 前缀（test_n10/test_v_save_domain 先例）——实测相对路径在
# FileAccess/DirAccess 间解析不一致（copy 落工程根进程 cwd、file_exists 又随 API 漂移），
# 前缀缺失=备份链静默失效。
const BK_PREFIX := "user://_vcfm_backup_"
# 走查规范备份组（本测试动 flag——reset_for_new_game 删标记/mark_first_launch 重建，入组）
const WATCHED_PATHS: Array = [SAVE_PATH, FLAG_PATH, TMP_PATH, BAK_PATH]

# Game.State 枚举：BOOT=0 MAIN_MENU=1 OPENING_MOVIE=2 TALK=3 LEVEL=4 SETTLE=5 CATALOG=6
const ST_MAIN_MENU := 1
const ST_OPENING_MOVIE := 2
const ST_CATALOG := 6

## TopStrip 替身：记录 push_confirm/push_info 调用参数（test_v_game_confirm 同款夹具形态）；
## 确认/取消路径由测试直接调用记录到的回调（模拟统一确认条内按钮触发）。
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

var game: Variant
var save: Variant
var lib: Variant
var ssp: StripSpy
var _pre_save_text: String = ""  # 起测前真实 save.json 原文（还原等价自检基准）

func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

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
		var abs: String = _abs(p)
		if FileAccess.file_exists(abs):
			DirAccess.remove_absolute(abs)
		var bk := BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_abs(bk), abs)
			DirAccess.remove_absolute(_abs(bk))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()  # 防进程退出 close_requested → save_game 把测试态写回真实档案
	# 纪律自检：还原后 save.json 与起测前逐字节等价（起测前无档 ↔ 还原后无档）
	var post: String = _read_file(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|v_confirm_migration|files=%d" % WATCHED_PATHS.size())

func _cleanup() -> void:
	for p: String in [SAVE_PATH, FLAG_PATH]:
		var abs: String = ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs):
			DirAccess.remove_absolute(abs)

func _del_flag() -> void:
	var abs: String = ProjectSettings.globalize_path(FLAG_PATH)
	if FileAccess.file_exists(abs):
		DirAccess.remove_absolute(abs)

func _confirm_count() -> int:
	return ssp.get_confirm_calls().size()

func _last_confirm() -> Array:
	var calls: Array = ssp.get_confirm_calls()
	return calls[calls.size() - 1]

func _open_menu(container: Control) -> Node:
	var menu: Node = (load(MM_SCENE) as PackedScene).instantiate()
	container.add_child(menu)
	await process_frame
	return menu

func _initialize() -> void:
	print("== test_v_confirm_migration ==")
	game = get_root().get_node("Game")
	save = get_root().get_node("SaveManager")
	lib = get_root().get_node("LevelLibrary")
	ssp = StripSpy.new()
	add_child(ssp)
	game.call("attach_strip", ssp)   # V-C5 注册路径（未挂接兜底已由 test_v_game_confirm 覆盖）
	await process_frame  # 坑 5：--script 无头 _initialize 时序
	_backup_user()                   # 清档纪律：任何删/写档前备份真实档案（save+flag）
	for p: String in WATCHED_PATHS:
		var abs0: String = _abs(p)
		if FileAccess.file_exists(abs0):
			DirAccess.remove_absolute(abs0)   # 沙盒基线：真实档案已备份，测试域内全清
	save.load_game()

	# ---- A. 源码级断言：三迁移场景零旧弹窗实例化/引用（旧组件文件本体保留不删） ----
	for path: String in ["res://scenes/menu/main_menu.gd", "res://scenes/shop/shop_panel.gd",
			"res://scenes/level/level_scene.gd"]:
		var src: String = FileAccess.get_file_as_string(path)
		check(not src.contains("GlassDialog") and not src.contains("glass_dialog"),
			"V-C5 §3.2：迁移脚本零旧弹窗实例化/引用（%s）" % path)
		check(src.contains("Game.confirm"), "V-C5 §3.2：迁移脚本已接线 Game.confirm（%s）" % path)
	var mm_tscn: String = FileAccess.get_file_as_string(MM_SCENE)
	check(not mm_tscn.contains("glass_dialog") and not mm_tscn.contains("NewGameDialog")
		and not mm_tscn.contains("ExitDialog"), "V-C5 §3.2：main_menu.tscn 两确认弹窗节点已退役（选退役删除，非保留不路由）")
	var shop_tscn: String = FileAccess.get_file_as_string(SHOP_SCENE)
	check(not shop_tscn.contains("glass_dialog") and not shop_tscn.contains("ConfirmDialog"),
		"V-C5 §3.2：shop_panel.tscn 确认弹窗节点已退役")
	check(ResourceLoader.exists("res://scenes/shared/glass_dialog.gd")
		and ResourceLoader.exists("res://scenes/shared/glass_dialog.tscn"),
		"V-C5 §3.2：旧组件文件本体保留不删（settle_scene 先例，main.gd 路仍复用）")

	# ---- B. main_menu 迁移行为（两处确认经 Game.confirm，文案逐字 + 回调语义） ----
	var container: Control = Control.new()
	add_child(container)
	var menu: Node = await _open_menu(container)
	var start_btn: Button = menu.get_node("LeftPanel/StartButton")
	var load_btn: Button = menu.get_node("LeftPanel/LoadButton")
	var quit_btn: Button = menu.get_node("LeftPanel/QuitButton")

	# B1 无档态「开始游戏」：直接进开场（语义不变），不弹确认条
	var b0: int = _confirm_count()
	start_btn.pressed.emit()
	check_eq(_confirm_count(), b0, "V-C5：无档开始=直接开场（Game.confirm 不触发，分流语义保持）")
	check_eq(int(game.current_state()), ST_OPENING_MOVIE, "V-C5：无档开始路由 OPENING_MOVIE（语义保持）")
	game.call("goto_state", ST_MAIN_MENU)  # 状态机复位：防 B1 路由残留使 B3 断言失真

	# B2 有档态「新游戏」：弹统一确认条，文案逐字，确认前不清档不路由
	save.advance_progress(1)
	await process_frame
	check_eq(start_btn.text, "新游戏", "前置：有档两态文本（has_any_progress 判据）")
	var b1: int = _confirm_count()
	var st_b2: int = int(game.current_state())
	start_btn.pressed.emit()
	check_eq(_confirm_count(), b1 + 1, "V-C5 §3.2：有档点新游戏 → Game.confirm 统一确认条（恰 1 条）")
	var ng_ok := Callable()
	if _confirm_count() == b1 + 1:
		var rec: Array = _last_confirm()
		check_eq(String(rec[0]), "新游戏将清除当前存档，确定重新开始吗？",
			"V-C5 §3.2：新游戏确认文案逐字（占位文案不新编，铁律 8）")
		check((rec[1] as Callable).is_valid(), "V-C5 §3.2：新游戏确认回调透传有效（清档+进开场）")
		check(not (rec[2] as Callable).is_valid(),
			"V-C5 §3.2：新游戏取消缺省空回调（取消/×=零副作用语义保持）")
		ng_ok = rec[1]
	check_eq(int(game.current_state()), st_b2, "V-C5：确认前不路由（仅弹条）")
	check_eq(int(save.get_progress()["next_chapter"]), 2, "V-C5：确认前存档进度不变（未清档）")

	# B3 确认回调=清档+重建标记+进开场（语义逐字保持）
	if ng_ok.is_valid():
		ng_ok.call()
	check_eq(int(save.get_talent()), 500, "V-C5：确认后天赋回默认 500（清档语义保持）")
	check_eq(int(save.get_progress()["next_chapter"]), 1, "V-C5：确认后进度重置（清档语义保持）")
	check(FileAccess.file_exists(FLAG_PATH), "V-C5：确认后 first_launch 标记已重建（新周目有档态，P1-1 修语义保持）")
	check_eq(int(game.current_state()), ST_OPENING_MOVIE, "V-C5：确认后路由 OPENING_MOVIE（新游戏重走开场）")

	# B4 退出确认：文案逐字 + 回调接线；无头环境绝不触发确认回调（会真 quit）
	var b4: int = _confirm_count()
	var st_b4: int = int(game.current_state())
	quit_btn.pressed.emit()
	check_eq(_confirm_count(), b4 + 1, "V-C5 §3.2：点退出 → Game.confirm 统一确认条（不直接退出）")
	if _confirm_count() == b4 + 1:
		var qrec: Array = _last_confirm()
		check_eq(String(qrec[0]), "退出《千年一榫》？", "V-C5 §3.2：退出确认文案逐字（与窗口关闭同流程）")
		check((qrec[1] as Callable).is_valid(), "V-C5 §3.2：退出确认回调已接线（stop+quit，无头不触发）")
		check(not (qrec[2] as Callable).is_valid(), "V-C5 §3.2：退出取消零回调（零副作用语义保持）")
	check_eq(int(game.current_state()), st_b4, "V-C5：退出确认前状态不变（不直接退出）")
	menu.queue_free()
	await process_frame

	# ---- C. shop 迁移行为（领取/购买确认文案逐字 + 确认链保持 + 失败中央提示可达） ----
	_cleanup()
	save.load_game()
	save.spend_talent(save.get_talent())   # 归零（绝对值链口径，test_shop_panel 同款前置）
	var shop_container: Control = Control.new()
	add_child(shop_container)
	var overlay: CanvasLayer = CanvasLayer.new()
	add_child(overlay)
	game.call("attach", shop_container, overlay)
	await process_frame
	game.call("open_overlay", "shop")
	await process_frame
	var shop: Node = overlay.get_child(overlay.get_child_count() - 1)
	check(shop != null, "V-C5 前置：商店覆盖层已打开")
	var catalog: GDScript = load(CATALOG)
	var buy_btn: Button = shop.get_node("Content/DetailBox/DetailInner/DetailBottom/BuyButton")

	# C1 免费领取：文案逐字 + 取消零回调 + 确认领取链保持
	var free_skin: Dictionary = catalog.get_skin("skin_02")
	shop.call("_show_detail", free_skin)
	var c0: int = _confirm_count()
	buy_btn.pressed.emit()
	check_eq(_confirm_count(), c0 + 1, "V-C5 §3.2：免费领取 → Game.confirm 统一确认条（恰 1 条）")
	var free_ok := Callable()
	if _confirm_count() == c0 + 1:
		var crec: Array = _last_confirm()
		check_eq(String(crec[0]), "免费领取 %s？" % String(free_skin["name"]),
			"V-C5 §3.2：领取确认文案逐字（免费领取 <名>？）")
		check(not (crec[2] as Callable).is_valid(), "V-C5 §3.2：领取取消缺省空回调（零副作用语义保持）")
		check((crec[1] as Callable).is_valid(), "V-C5 §3.2：领取确认回调透传有效")
		free_ok = crec[1]
	if free_ok.is_valid():
		free_ok.call()
	await process_frame
	check((save.get_skins()["owned"] as Array).has("skin_02"), "V-C5：确认后免费皮肤入 owned（领取链保持）")
	check_eq(String(save.get_skins()["equipped"]), "skin_02", "V-C5：确认后自动穿戴（领取链保持）")
	check_eq(int(save.get_talent()), 0, "V-C5：免费领取 0 扣费（语义保持）")

	# C2 付费购买：文案逐字（含价格）+ 确认扣费链保持
	save.add_talent(1000)
	var paid_skin: Dictionary = catalog.get_skin("skin_07")
	shop.call("_show_detail", paid_skin)
	var c2: int = _confirm_count()
	buy_btn.pressed.emit()
	check_eq(_confirm_count(), c2 + 1, "V-C5 §3.2：付费购买 → Game.confirm 统一确认条")
	var paid_ok := Callable()
	if _confirm_count() == c2 + 1:
		var prec: Array = _last_confirm()
		check_eq(String(prec[0]), "确认购买 %s（%d 天赋值）？" % [String(paid_skin["name"]), 205],
			"V-C5 §3.2：购买确认文案逐字（确认购买 <名>（205 天赋值）？）")
		paid_ok = prec[1]
	if paid_ok.is_valid():
		paid_ok.call()
	await process_frame
	check((save.get_skins()["owned"] as Array).has("skin_07"), "V-C5：确认后购买入 owned（扣费链保持）")
	check_eq(int(save.get_talent()), 795, "V-C5：确认后扣费 205（1000-205，语义保持）")
	check_eq(String(save.get_skins()["equipped"]), "skin_07", "V-C5：确认后自动穿戴（购买链保持）")

	# C3 余额不足：确认消费后失败分支 → 中央提示仍可达（toast 链保持，strip info 承载）
	save.spend_talent(save.get_talent())
	save.add_talent(100)
	var fail_skin: Dictionary = catalog.get_skin("skin_08")
	shop.call("_show_detail", fail_skin)
	var i0: int = ssp.get_info_calls().size()
	var c3: int = _confirm_count()
	buy_btn.pressed.emit()
	if _confirm_count() == c3 + 1:
		var f_ok: Callable = _last_confirm()[1]
		if f_ok.is_valid():
			f_ok.call()
	await process_frame
	var info_calls: Array = ssp.get_info_calls()
	check((info_calls as Array).size() > i0, "V-C5：余额不足失败分支 → 中央提示仍可达（统一弹条 info 承载）")
	if (info_calls as Array).size() > i0:
		check_eq(String((info_calls[info_calls.size() - 1] as Array)[0]), "天赋值不足，无法购买",
			"V-C5：失败提示文案透传（Game.toast centered 单点改道链保持）")
	game.call("close_overlay")
	await process_frame

	# ---- D. level 迁移行为（退出确认文案逐字 + 确认分流/取消作废语义） ----
	_cleanup()
	save.load_game()
	lib.call("scan_directory", "res://levels_data")

	# D1 重玩退出：返回图鉴
	var lvl1: Node = (load(LEVEL_SCENE) as PackedScene).instantiate()
	lvl1.call("set_context", {"chapter": 1, "replay": true})
	add_child(lvl1)
	await process_frame
	var rbtn: Button = lvl1.get_node_or_null("ExitReplayButton")
	check(rbtn is Button and rbtn != null and rbtn.visible, "V-C5 前置：重玩退出按钮可见")
	var d0: int = _confirm_count()
	if rbtn != null:
		rbtn.pressed.emit()
	check_eq(_confirm_count(), d0 + 1, "V-C5 §3.2：重玩退出 → Game.confirm 统一确认条（恰 1 条）")
	var d_ok := Callable()
	var d_cancel := Callable()
	if _confirm_count() == d0 + 1:
		var drec: Array = _last_confirm()
		check_eq(String(drec[0]), "返回图鉴？", "V-C5 §3.2：重玩退出文案逐字（返回图鉴？）")
		check((drec[1] as Callable).is_valid(), "V-C5 §3.2：确认回调透传（挂起目标路由）")
		check((drec[2] as Callable).is_valid(), "V-C5 §3.2：取消回调透传（挂起路由作废语义）")
		d_ok = drec[1]
		d_cancel = drec[2]
	# 取消路径：挂起路由作废（_pending_exit_state 复位 -1）+ 状态不变
	var st_d1: int = int(game.current_state())
	if d_cancel.is_valid():
		d_cancel.call()
	var pend: Variant = lvl1.get("_pending_exit_state")   # 坑 2：.get 防御
	check_eq(int(pend) if pend != null else -1, -1, "V-C5：取消后挂起路由作废（_pending_exit_state==-1）")
	check_eq(int(game.current_state()), st_d1, "V-C5：取消路径状态不变（零副作用）")
	# 确认路径：按挂起目标路由 CATALOG（spec 3.10/Q&A10 语义保持）
	if rbtn != null:
		rbtn.pressed.emit()
	if _confirm_count() == d0 + 2 and ((_last_confirm()[1] as Callable).is_valid()):
		(_last_confirm()[1] as Callable).call()
	check_eq(int(game.current_state()), ST_CATALOG, "V-C5：确认 → 路由 CATALOG（重玩分流语义保持）")
	lvl1.queue_free()
	await process_frame

	# D2 正常退出：返回主菜单
	var lvl2: Node = (load(LEVEL_SCENE) as PackedScene).instantiate()
	lvl2.call("set_context", {"chapter": 1, "replay": false})
	add_child(lvl2)
	await process_frame
	var ebtn: Button = lvl2.get_node_or_null("TopBar/Buttons/ExitButton")
	check(ebtn is Button, "V-C5 前置：TopBar 退出按钮存在")
	var d2: int = _confirm_count()
	if ebtn != null:
		ebtn.pressed.emit()
	check_eq(_confirm_count(), d2 + 1, "V-C5 §3.2：正常退出 → Game.confirm 统一确认条")
	if _confirm_count() == d2 + 1:
		var d2rec: Array = _last_confirm()
		check_eq(String(d2rec[0]), "返回主菜单？", "V-C5 §3.2：正常退出文案逐字（返回主菜单？）")
		if (d2rec[1] as Callable).is_valid():
			(d2rec[1] as Callable).call()
	check_eq(int(game.current_state()), ST_MAIN_MENU, "V-C5：确认 → 路由 MAIN_MENU（语义保持）")
	lvl2.queue_free()
	await process_frame

	# ---- E. 主菜单判据矩阵（§8.3：has_any_progress 三分支驱动按钮两态） ----
	# E1 全无（flag 无 ∧ watched=false ∧ cleared 空）→「开始游戏」+「加载存档」灰禁
	_cleanup()
	save.load_game()
	check(bool(save.has_any_progress()) == false, "判据矩阵·全无：has_any_progress()==false")
	var m1: Node = await _open_menu(container)
	check_eq(String((m1.get_node("LeftPanel/StartButton") as Button).text), "开始游戏",
		"判据矩阵·全无：StartButton=「开始游戏」")
	check_eq((m1.get_node("LeftPanel/LoadButton") as Button).disabled, true,
		"判据矩阵·全无：LoadButton 灰禁（无任何进度）")
	m1.queue_free()
	await process_frame

	# E2 仅 flag（first_launch 标记在 ∧ watched/cleared 全空）→ 有档两态（flag 分支语义保持）
	save.mark_first_launch()
	check(bool(save.has_any_progress()), "判据矩阵·仅 flag：has_any_progress()==true")
	var m2: Node = await _open_menu(container)
	check_eq(String((m2.get_node("LeftPanel/StartButton") as Button).text), "新游戏",
		"判据矩阵·仅 flag：StartButton=「新游戏」")
	check_eq((m2.get_node("LeftPanel/LoadButton") as Button).disabled, false,
		"判据矩阵·仅 flag：LoadButton 可用")
	m2.queue_free()
	await process_frame

	# E3 仅 watched（flag 丢失 ∧ watched_opening=true）→「载入存档」不再灰禁（§8 判据统一病灶修复）
	_cleanup()
	save.load_game()
	save.mark_opening_watched()
	_del_flag()
	check(bool(save.has_any_progress()), "判据矩阵·仅 watched：has_any_progress()==true")
	var m3: Node = await _open_menu(container)
	check_eq((m3.get_node("LeftPanel/LoadButton") as Button).disabled, false,
		"判据矩阵·仅 watched：LoadButton 可用（进度不因 flag 丢失而灰禁，§8 判据统一）")
	check_eq(String((m3.get_node("LeftPanel/LoadButton") as Button).text), "载入存档",
		"判据矩阵·仅 watched：LoadButton=「载入存档」")
	# E3b（回修②P2-1）行为断言：仅 watched（flag 缺失）态点「开始游戏」→ 走清档确认流
	#（确认条弹出），未确认前不清档、不进开场、不重建标记——按钮判据(_update_buttons)与
	# 动作判据(_on_start)同源 has_any_progress() 收口，修旧 is_first_launch() 单判据在
	# flag 丢失态「点开始游戏不清档不确认直接重播开场」的按钮/动作分叉。
	var e3_chapter: int = int(save.get_progress()["next_chapter"])
	var e3_confirms: int = _confirm_count()
	var e3_state: int = int(game.current_state())
	(m3.get_node("LeftPanel/StartButton") as Button).pressed.emit()
	check_eq(_confirm_count(), e3_confirms + 1,
		"回修②P2-1：仅 watched（flag 缺失）点开始 → 清档确认条弹出（确认流收口，非静默首启流）")
	check_eq(int(game.current_state()), e3_state, "回修②P2-1：未确认前不进开场（状态机不变）")
	check_eq(int(save.get_progress()["next_chapter"]), e3_chapter, "回修②P2-1：未确认前不清档（进度保持）")
	check(not FileAccess.file_exists(FLAG_PATH), "回修②P2-1：未确认前不重建 first_launch 标记（旧判据会误 mark）")
	m3.queue_free()
	await process_frame

	# E4 仅 cleared（flag 丢失 ∧ cleared=[1]）→ 有档两态
	_cleanup()
	save.load_game()
	save.advance_progress(1)
	_del_flag()
	check(bool(save.has_any_progress()), "判据矩阵·仅 cleared：has_any_progress()==true")
	var m4: Node = await _open_menu(container)
	check_eq((m4.get_node("LeftPanel/LoadButton") as Button).disabled, false,
		"判据矩阵·仅 cleared：LoadButton 可用")
	check_eq(String((m4.get_node("LeftPanel/StartButton") as Button).text), "新游戏",
		"判据矩阵·仅 cleared：StartButton=「新游戏」")
	m4.queue_free()
	await process_frame

	# ---- 收尾：还原 autoload 挂接态 + 清档纪律还原（备份→测试→逐字节还原+EVID，规范第 2 条） ----
	game.call("attach_strip", null)
	game.call("attach_toast", null)
	_restore_user()
	ssp.queue_free()
	await process_frame
	finish()
