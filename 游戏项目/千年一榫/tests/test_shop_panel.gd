extends "res://tests/test_base.gd"
## 商店面板契约无头测试（T10 起；K-D 重构改写，spec §7.5/§6.2/§6.3）。
## K-D 变更：目录 47 项（5 原创置顶 + 42 占位）；右栏标题「神通谱」、desc 读 skin_catalog；
##   ConfirmDialog → 批次V规格§3.2（V-C5 等价替换留痕）：确认弹窗节点退役，领取/购买确认改经
##   Game.confirm → TopStrip 统一确认条（本文件以 StripSpy 夹具承接文案逐字断言与「确认/取消」
##   驱动；旧「GlassDialog script 比较/节点可见性/Body Label」断言等价替换为「spy 收到逐字文案
##   + 回调透传」）；NoteLabel 占位文案删除；
##   未解锁原创卡片按钮「随剧情解锁」且 disabled、穿戴中卡片按钮「穿戴中」disabled；
##   （O6 批等价替换 2026-09-10：未解锁原创按钮改可点开详情，disabled 断言转详情购买钮
##   disabled+「随剧情解锁」——见 1. 节 K3-4/K3-5 段注）
##   确认走统一确认条（Game.confirm → push_confirm → 回调 → _on_confirmed）；余额不足/已拥有改 toast
##   （经 Game.toast；strip 在位时 centered=true 单点改道 push_info——段 3 断言随之承接，
##   右上原路径断言（段 10/Q2）先 attach_strip(null) 还原降级环境）。
## M-S（2026-09-08，批次 M spec §3.6B）等价替换留痕：详情栏重排 DetailInner（Title 固定/Scroll 滚动区/
##   DetailBottom 固定底行）——DetailScroll/DetailVBox 路径与 DetailVBox EXPAND_FILL 断言按新结构/新口径
##   等价替换（顶对齐 SHRINK_BEGIN）；BuyButton 5 处驱动路径改 DetailInner/DetailBottom；
##   购买/选择/领取/toast/存档断言语义零改动（路由与数值链全保留）。
## 环境：--script 无头模式 autoload 在 /root/<Name>；主脚本不能直接写全局标识符 → get_root().get_node 取。

const SCENE_PATH := "res://scenes/shop/shop_panel.tscn"
const CATALOG := "res://data/skin_catalog.gd"
const SAVE_PATH := "user://save.json"

## 批次V规格§3.2（V-C5）夹具：TopStrip 替身——记录 Game.confirm 委托来的 push_confirm/push_info
##（test_v_game_confirm 同款形态）；「确认」由测试直接调用记录到的 on_confirmed 回调驱动。
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

func _cleanup() -> void:
	var save_abs: String = ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(save_abs):
		DirAccess.remove_absolute(save_abs)

## 等待两帧：让 queue_free 的旧卡片离场、信号触发的重建稳定
func _settle() -> void:
	await process_frame
	await process_frame

## 打开商店覆盖层并返回面板实例（等待一帧让 _ready 完成）
func _open(game: Variant, overlay: CanvasLayer) -> Node:
	game.open_overlay("shop")
	await process_frame
	if overlay.get_child_count() == 0:
		return null
	return overlay.get_child(overlay.get_child_count() - 1)

## 批次V§3.2 等价替换（原 _dialog/_body/_press_ok 三助手）：确认条经 Game.confirm 委托 spy，
## 旧「取节点/读 Body/发 OkButton」驱动改「读记录/调 on_confirmed 回调」驱动。
func _confirm_count() -> int:
	return (ssp.call("get_confirm_calls") as Array).size()

func _last_confirm() -> Array:
	var calls: Array = ssp.call("get_confirm_calls")
	return calls[calls.size() - 1]

func _press_ok(_panel: Node) -> void:
	var calls: Array = ssp.call("get_confirm_calls")
	if calls.is_empty():
		return
	var cb: Callable = (calls[calls.size() - 1] as Array)[1]
	if cb.is_valid():
		cb.call()

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
const DISC_BK_PREFIX := "user://_r2b_shp_backup_"
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
	print("EVID|user_restore|shp|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_shop_panel ==")
	_backup_user()
	var save: Variant = get_root().get_node("SaveManager")
	var game: Variant = get_root().get_node("Game")
	# 批次V规格§3.2（V-C5）：领取/购买确认迁移 Game.confirm → 统一确认条——spy 夹具注册到
	# autoload Game（注册路径；未挂接兜底路径归 test_v_game_confirm）
	ssp = StripSpy.new()
	add_child(ssp)
	game.call("attach_strip", ssp)

	_cleanup()
	save.load_game()  # K-D：默认存档 equipped/preferred=skin_origin_kaitou，owned=[skin_default, 开头原创]
	save.spend_talent(save.get_talent())  # 归零，保本文件 100/1000/795 绝对值链不变

	var container: Control = Control.new()
	add_child(container)
	var overlay: CanvasLayer = CanvasLayer.new()
	add_child(overlay)
	game.attach(container, overlay)
	await process_frame

	# ---- 0. SkinCatalog 目录数据契约（K-D：47 项 = 5 原创 + 42 占位）----
	check(ResourceLoader.exists(CATALOG), "skin_catalog.gd 存在")
	var catalog: GDScript = load(CATALOG)
	check(catalog != null, "SkinCatalog 可加载")
	var skins: Array = catalog.get_skins()
	check_eq(skins.size(), 47, "K-D 目录共 47 个皮肤（5 原创 + 42）")
	check_eq(String(skins[0]["id"]), "skin_origin_kaitou", "K-D 首项为开头原创（置顶）")
	check_eq(String(skins[46]["id"]), "skin_42", "K-D 末项仍为 skin_42")
	var free_count: int = 0
	var paid_count: int = 0
	var origin_count: int = 0
	for s: Dictionary in skins:
		if bool(s.get("original", false)):
			origin_count += 1
			continue
		if int(s["price"]) == 0:
			free_count += 1
		elif int(s["price"]) == 205:
			paid_count += 1
	check_eq(origin_count, 5, "K-D 原创皮肤 5 个")
	check_eq(free_count, 6, "非原创免费皮肤 6 个")
	check_eq(paid_count, 36, "非原创付费皮肤 36 个（205/个）")
	var s01: Dictionary = catalog.get_skin("skin_01")
	check_eq(s01["id"], "skin_01", "get_skin 命中")
	check(catalog.get_skin("不存在").is_empty(), "get_skin 未命中返回空字典")

	# ---- 1. 场景结构（K-D）：NoteLabel 删除 / ConfirmDialog=GlassDialog / DetailTitle=神通谱 ----
	check(ResourceLoader.exists(SCENE_PATH), "shop_panel.tscn 存在")
	if not ResourceLoader.exists(SCENE_PATH):
		finish()
		return
	var panel: Node = await _open(game, overlay)
	check(panel != null, "open_overlay('shop') 创建商店覆盖层")
	if panel == null:
		finish()
		return
	check(panel is Control, "根节点为 Control")
	check((panel as Control).anchor_right == 1.0 and (panel as Control).anchor_bottom == 1.0, "根节点全屏覆盖")
	check(panel.get_node_or_null("Dim") is ColorRect, "J1-2：商店覆盖层有 Dim 遮罩")
	check(panel.get_node_or_null("TopBar") is HBoxContainer, "TopBar(HBoxContainer) 存在")
	check((panel.get_node("TopBar") as Control).offset_right <= -128.0, "J6-P2-7：商店顶栏 offset_right≤-128 避让")
	check(panel.get_node_or_null("TopBar/BalanceLabel") is Label, "BalanceLabel(Label) 存在")
	check(panel.get_node_or_null("TopBar/NoteLabel") == null, "K3-1：TODO 占位文案 NoteLabel 已删")
	check(panel.get_node_or_null("TopBar/ExitButton") is Button, "ExitButton(Button) 存在")
	var content: Node = panel.get_node_or_null("Content")
	check(content is HBoxContainer, "Content(HBoxContainer) 存在（左网格/右详情两栏）")
	check(panel.get_node_or_null("Content/GridPanel") is PanelContainer, "GridPanel(PanelContainer) 存在")
	check(panel.get_node_or_null("Content/GridPanel/Scroll") is ScrollContainer, "GridPanel/Scroll 存在")
	var grid: Node = panel.get_node_or_null("Content/GridPanel/Scroll/SkinGrid")
	check(grid is GridContainer, "SkinGrid(GridContainer) 存在")
	if grid != null:
		check_eq((grid as GridContainer).columns, 3, "布局：SkinGrid 3 列大格")
	var detail_box: Node = panel.get_node_or_null("Content/DetailBox")
	check(detail_box is PanelContainer, "DetailBox(PanelContainer) 存在")
	# M-S 等价替换（spec §3.6B）：详情栏重排 DetailInner=[Title(固定) + DetailScroll>DetailVBox(滚) + DetailBottom(固定底行)]，
	# 旧「DetailBox 直挂 DetailScroll」路径断言按新结构等价替换留痕。
	check(panel.get_node_or_null("Content/DetailBox/DetailInner/DetailScroll") is ScrollContainer, "K-H P1→M-S 等价替换：DetailBox/DetailInner/DetailScroll 存在（描述独立滚动，购买钮已出滚动区常驻右下）")
	check(panel.get_node_or_null("Content/DetailBox/DetailInner/DetailScroll/DetailVBox") is VBoxContainer, "DetailVBox(VBoxContainer) 存在")
	var dbox: Node = panel.get_node_or_null("Content/DetailBox/DetailInner/DetailScroll/DetailVBox")
	# M-S 行为变化断言（spec §3.6B 紧凑化）：DetailVBox 由 EXPAND_FILL 改顶对齐 SHRINK_BEGIN（重心上移，DetailSpacer 已删）
	check(dbox != null and int((dbox as Control).size_flags_vertical) == int(Control.SIZE_SHRINK_BEGIN),
		"M-S 等价替换：DetailVBox 顶对齐 SHRINK_BEGIN（旧 K-H P3② EXPAND_FILL+Spacer 沉底口径随紧凑化退役）")
	var dname: Node = panel.get_node_or_null("Content/DetailBox/DetailInner/DetailScroll/DetailVBox/DetailName")
	var dimg: Node = panel.get_node_or_null("Content/DetailBox/DetailInner/DetailScroll/DetailVBox/DetailImage")
	var ddesc: Node = panel.get_node_or_null("Content/DetailBox/DetailInner/DetailScroll/DetailVBox/DetailDesc")
	var dprice: Node = panel.get_node_or_null("Content/DetailBox/DetailInner/DetailBottom/DetailPrice")
	var dtitle: Node = panel.get_node_or_null("Content/DetailBox/DetailInner/DetailTitle")
	var buyb: Node = panel.get_node_or_null("Content/DetailBox/DetailInner/DetailBottom/BuyButton")
	check(dname is Label, "DetailName(Label) 存在")
	check(dimg is TextureRect, "DetailImage(TextureRect) 存在")
	check(ddesc is Label, "DetailDesc(Label) 存在")
	check(dprice is Label, "DetailPrice(Label) 存在")
	check_eq(String((dtitle as Label).text), "神通谱", "K3-2：详情栏标题=神通谱")
	check(buyb is Button, "BuyButton(Button) 存在")
	# 批次 W（P2-10）等价改写：默认详情=开头原创（已拥有）→ 钮文案「穿戴」
	# （旧「购买」断言随 P2-10 拥有态分文案废止留痕；未拥有「购买」断言见段 11b）。
	check_eq((buyb as Button).text, "穿戴", "BuyButton 文本（默认详情=已拥有开头原创 → 「穿戴」）")
	# 批次V规格§3.2（V-C5）等价替换留痕（原 K4-1：ConfirmDialog 为 GlassDialog 实例 script 比较）：
	# 确认弹窗节点退役，领取/购买确认改经 Game.confirm → 统一确认条（文案/回调断言见段 2/3/4）。
	check(panel.get_node_or_null("ConfirmDialog") == null, "批次V§3.2：ConfirmDialog 节点已退役（确认改经 Game.confirm 统一弹条）")
	# J6-P1-1：覆盖层主题接线
	var tm: Variant = get_root().get_node("ThemeManager")
	check((panel as Control).theme != null, "J6-P1-1：覆盖层根节点已显式赋主题")
	for pc_path: String in ["Content/GridPanel", "Content/DetailBox"]:
		var sb: StyleBoxFlat = null
		if panel.get_node_or_null(pc_path) is PanelContainer:
			sb = (panel.get_node(pc_path) as Control).get_theme_stylebox("panel") as StyleBoxFlat
		check(sb != null and sb.bg_color.a > 0.0 and sb.bg_color.a < 0.9, "J6-P1-1：商店 %s 半透明毛玻璃（0<a<0.9）" % pc_path)
	(panel as Control).theme = null
	# J6-P1-1「theme_changed 即时刷新覆盖层主题」断言随批次 AB-3 深浅主题机制删除退役——
	# 等价改写：信号无复辟（Game.open_overlay 恒赋深色主题，覆盖层主题接线锁在上一断言）。
	check(not tm.has_signal("theme_changed"),
		"AB-3 反向锁：ThemeManager 无 theme_changed 信号（覆盖层刷新订阅无复辟）")
	var exit_btn: Button = panel.get_node("TopBar/ExitButton")
	check_eq(exit_btn.text, "退出", "ExitButton 文本「退出」")
	var balance: Label = panel.get_node("TopBar/BalanceLabel")
	check(balance.text.contains("天赋值"), "清单①：余额标签含「天赋值」")
	check_eq(balance.text, "天赋值：%d" % int(save.get_talent()), "清单①：余额数值与存档一致")
	if grid != null:
		check_eq((grid as GridContainer).get_child_count(), 47, "K-D：网格渲染 47 格")
	var cards: Dictionary = panel.get("_cards")
	check_eq(cards.size(), 47, "K-D：卡片索引 47 条")
	if cards.has("skin_01"):
		var card1: VBoxContainer = cards["skin_01"]
		check(card1 != null and card1.get_child_count() == 3, "卡片结构：图/文/按钮 3 子节点")
		check(((card1.get_child(1)) as Label).text.contains("免费"), "免费皮肤卡片信息区显示「免费」")
	if cards.has("skin_07"):
		var card7: VBoxContainer = cards["skin_07"]
		check(((card7.get_child(1)) as Label).text.contains("205 天赋值"), "付费皮肤卡片信息区显示「205 天赋值」")
		check_eq((card7.get_child(2) as Button).text, "选择", "非原创未穿戴卡片按钮「选择」")
	# K3-4/K3-5：原创卡片状态机（开头默认拥有→穿戴中；宋未解锁→随剧情解锁不显示价格）
	# O6 批等价替换（2026-09-10）：未解锁原创卡片按钮不再 disabled——用户要求随剧情解锁的
	# 角色也能点开看文案；原「禁用（禁购）」断言等价替换为「可点击 + 详情购买钮 disabled+
	# 「随剧情解锁」承接禁购语义」（_on_select buyable 守卫保持，见下方 9.）。
	if cards.has("skin_origin_song"):
		var song_btn: Button = (cards["skin_origin_song"] as VBoxContainer).get_child(2)
		check_eq(song_btn.text, "随剧情解锁", "K3-5：未解锁原创按钮文本「随剧情解锁」")
		check_eq(song_btn.disabled, false, "O6 批等价替换：未解锁原创按钮可点击看详情（原 K3-5 disabled 断言随 O6 退役）")
		var song_info: String = String((cards["skin_origin_song"] as VBoxContainer).get_child(1).text)
		check(not song_info.contains("免费"), "K3-5：未解锁原创信息区不显示「免费」（禁购语义）")
		check(song_info.contains("随剧情解锁"), "K3-5：未解锁原创信息区显示「随剧情解锁」")
		# O6 新增：点击未解锁卡片 → 详情展示该皮肤 + 详情购买钮禁用态（禁购语义新落点）
		song_btn.pressed.emit()
		await process_frame
		var song_name: String = String(catalog.get_skin("skin_origin_song")["name"])
		check_eq(String((dname as Label).text), song_name, "O6：点未解锁卡片 → 详情栏展示该皮肤（文案可看）")
		var obuy: Button = panel.get_node("Content/DetailBox/DetailInner/DetailBottom/BuyButton")
		check(obuy != null and obuy.disabled and obuy.text == "随剧情解锁",
			"O6：未解锁原创详情购买钮 disabled+「随剧情解锁」（防静默吞点击，禁购语义承接）")
		# 复位详情到默认皮肤（kaitou 已拥有 → 购买钮可用，不影响后续清单②③④驱动）
		panel.call("_show_detail", catalog.get_skin("skin_origin_kaitou"))
	if cards.has("skin_origin_kaitou"):
		var kaitou_btn: Button = (cards["skin_origin_kaitou"] as VBoxContainer).get_child(2)
		check_eq(kaitou_btn.text, "穿戴中", "K3-5：默认拥有且穿戴的开头原创按钮「穿戴中」")
		check_eq(kaitou_btn.disabled, true, "K3-5：穿戴中原创按钮禁用")

	# ---- 1b. 默认详情栏=首个皮肤（开头原创）；点选格子 → 详情栏更新（K3-3 desc 上屏，动态比对）----
	if dname != null and dprice != null:
		check_eq((dname as Label).text, String(catalog.get_skin("skin_origin_kaitou")["name"]), "K-D：详情栏默认展示首个皮肤（开头原创名称）")
		check_eq((dprice as Label).text, "价格：免费", "K-D：开头原创价格「免费」（0）")
	if ddesc != null:
		check_eq(String((ddesc as Label).text), String(catalog.get_skin("skin_origin_kaitou")["desc"]), "K3-3：desc 上屏（读 skin_catalog，非固定「商品介绍」）")
	if cards.has("skin_07") and dname != null and dimg != null:
		var btn7_view: Button = (cards["skin_07"] as VBoxContainer).get_child(2)
		btn7_view.pressed.emit()
		await process_frame
		check_eq((dname as Label).text, String(catalog.get_skin("skin_07")["name"]), "K-D：点选格子后详情栏名称更新（skin_07）")
		var tex7: Texture2D = (dimg as TextureRect).texture
		check(tex7 != null and String(tex7.resource_path).contains("skin_07"), "K-D：点选格子后详情栏展示该皮肤预览图")

	# ---- 2. 清单②：免费皮肤领取（0 扣费）——确认走统一确认条（批次V§3.2），回调驱动 ----
	var talent0: int = int(save.get_talent())
	var free_skin: Dictionary = catalog.get_skin("skin_02")
	panel.call("_show_detail", free_skin)
	var c2_before: int = _confirm_count()
	panel.get_node("Content/DetailBox/DetailInner/DetailBottom/BuyButton").pressed.emit()  # M-S 等价替换：按钮移至 DetailBottom 固定底行（购买路由零改动）
	check_eq(_confirm_count(), c2_before + 1, "批次V§3.2：免费领取弹出统一确认条（Game.confirm 恰 1 条）")
	if _confirm_count() == c2_before + 1:
		var c2_rec: Array = _last_confirm()
		check_eq(String(c2_rec[0]), "免费领取 %s？" % String(free_skin["name"]), "K4-1→批次V§3.2：确认文案逐字=免费领取 <名>？（原「含免费领取」断言等价替换升格逐字）")
		check((c2_rec[1] as Callable).is_valid(), "批次V§3.2：领取确认回调透传有效")
		check(not (c2_rec[2] as Callable).is_valid(), "批次V§3.2：取消缺省空回调（零副作用语义保持）")
	_press_ok(panel)
	await _settle()
	check_eq(int(save.get_talent()), talent0, "清单②：领取免费皮肤 0 扣费")
	check((save.get_skins()["owned"] as Array).has("skin_02"), "清单②：免费皮肤加入 owned")
	check_eq(save.get_skins()["equipped"], "skin_02", "清单②：领取后自动穿戴")
	check((panel.get("_selected") as Dictionary).is_empty(), "批次V§3.2：确认消费后 _selected 复位（原「弹窗关闭」断言等价替换）")
	cards = panel.get("_cards")
	if cards.has("skin_02"):
		check(((cards["skin_02"] as VBoxContainer).get_child(1) as Label).text.contains("穿戴中"), "清单②：领取后卡片显示「穿戴中」")

	# ---- 3. 清单③：余额不足购买被拒并中央提示（失败分支=确认消费后 _selected 复位）----
	save.add_talent(100)  # 余额 100 < 205
	var paid1: Dictionary = catalog.get_skin("skin_08")
	panel.call("_show_detail", paid1)
	var c3_before: int = _confirm_count()
	var i3_before: int = (ssp.call("get_info_calls") as Array).size()
	panel.get_node("Content/DetailBox/DetailInner/DetailBottom/BuyButton").pressed.emit()  # M-S 等价替换：按钮移至 DetailBottom
	check_eq(_confirm_count(), c3_before + 1, "清单③：付费购买弹出统一确认条")
	if _confirm_count() == c3_before + 1:
		check_eq(String(_last_confirm()[0]), "确认购买 %s（%d 天赋值）？" % [String(paid1["name"]), 205],
			"批次V§3.2：购买确认文案逐字（确认购买 <名>（205 天赋值）？，原「含价格 205」断言等价替换升格逐字）")
	_press_ok(panel)
	await _settle()
	check_eq(int(save.get_talent()), 100, "清单③：余额不足不扣费")
	check(not (save.get_skins()["owned"] as Array).has("skin_08"), "清单③：余额不足未加入 owned")
	# K4-2→批次V 等价替换：失败提示仍可达——strip 在位时 Game.toast centered=true 单点改道
	# push_info（统一弹条承载），原「弹窗关闭+toast」断言改「info 条收到文案」。
	var info3: Array = ssp.call("get_info_calls")
	check((info3 as Array).size() > i3_before, "K4-2→批次V：余额不足失败改中央提示（统一弹条 info 收到，非二次弹）")
	if (info3 as Array).size() > i3_before:
		check_eq(String((info3[info3.size() - 1] as Array)[0]), "天赋值不足，无法购买",
			"K4-2→批次V：失败提示文案透传（TopStrip info 承载）")
	check((panel.get("_selected") as Dictionary).is_empty(), "K4-2：失败后 _selected 复位为空")

	# ---- 4. 清单④：余额充足购买成功（扣 205 + 自动穿戴）----
	save.add_talent(900)  # 100 + 900 = 1000
	check_eq(int(save.get_talent()), 1000, "清单④前置：余额 1000")
	var paid2: Dictionary = catalog.get_skin("skin_07")
	panel.call("_show_detail", paid2)
	var c4_before: int = _confirm_count()
	panel.get_node("Content/DetailBox/DetailInner/DetailBottom/BuyButton").pressed.emit()  # M-S 等价替换：按钮移至 DetailBottom
	check_eq(_confirm_count(), c4_before + 1, "批次V§3.2：清单④付费购买弹出统一确认条")
	_press_ok(panel)
	await _settle()
	check((save.get_skins()["owned"] as Array).has("skin_07"), "清单④：购买成功加入 owned")
	check_eq(int(save.get_talent()), 795, "清单④：扣费 205（1000-205=795）")
	check_eq(save.get_skins()["equipped"], "skin_07", "清单④：购买后自动穿戴")
	balance = panel.get_node("TopBar/BalanceLabel")
	check_eq(balance.text, "天赋值：795", "清单④：余额标签即时刷新 795")
	cards = panel.get("_cards")
	if cards.has("skin_07"):
		# K3-5 状态机：已拥有且穿戴中 → 按钮「穿戴中」且禁用
		var b7: Button = (cards["skin_07"] as VBoxContainer).get_child(2)
		check_eq(b7.text, "穿戴中", "K3-5：购买后穿戴中原创/皮肤按钮「穿戴中」")
		check_eq(b7.disabled, true, "K3-5：穿戴中按钮禁用")

	# ---- 5. 清单⑤：重复购买被拒 ----
	# 5a. 已拥有→选中直接穿戴，不弹确认、不扣费
	panel.call("_show_detail", paid2)  # skin_07 已拥有
	var c5_before: int = _confirm_count()
	panel.get_node("Content/DetailBox/DetailInner/DetailBottom/BuyButton").pressed.emit()  # M-S 等价替换：按钮移至 DetailBottom
	await _settle()
	check_eq(int(save.get_talent()), 795, "清单⑤：已拥有再选中不扣费")
	var cnt7: int = 0
	for o: Variant in (save.get_skins()["owned"] as Array):
		if String(o) == "skin_07":
			cnt7 += 1
	check_eq(cnt7, 1, "清单⑤：已拥有不重复加入 owned")
	check_eq(_confirm_count(), c5_before, "批次V§3.2：已拥有选中不弹确认（直接穿戴，无新确认条）")
	# 5b. 防御路径：确认后若已拥有 → 拒绝并 toast（_selected 复位）
	# 批次V§3.2 等价替换：旧 _press_ok（重发已关弹窗 OkButton）改直调 _on_confirmed（消费语义同款）。
	panel.set("_selected", paid2)
	panel.call("_on_confirmed")
	await _settle()
	check_eq(int(save.get_talent()), 795, "清单⑤：防御路径不扣费")
	check((panel.get("_selected") as Dictionary).is_empty(), "清单⑤：防御路径 _selected 复位")

	# ---- 6. 清单⑥：穿戴切换即时高亮 + 余额不变 ----
	var owned_free: Dictionary = catalog.get_skin("skin_02")  # 已拥有的免费皮肤
	panel.call("_show_detail", owned_free)
	panel.get_node("Content/DetailBox/DetailInner/DetailBottom/BuyButton").pressed.emit()  # M-S 等价替换：按钮移至 DetailBottom  # 已拥有→直接穿戴
	await _settle()
	check_eq(save.get_skins()["equipped"], "skin_02", "清单⑥：穿戴切换为 skin_02")
	check_eq(int(save.get_talent()), 795, "清单⑥：穿戴不影响余额")
	balance = panel.get_node("TopBar/BalanceLabel")
	check_eq(balance.text, "天赋值：795", "清单⑥：余额区不变")
	cards = panel.get("_cards")
	if cards.has("skin_02"):
		check(((cards["skin_02"] as VBoxContainer).get_child(1) as Label).text.contains("穿戴中"), "清单⑥：当前穿戴卡片高亮「穿戴中」")
		check(((cards["skin_07"] as VBoxContainer).get_child(1) as Label).text.contains("已拥有"), "清单⑥：原穿戴卡片回落「已拥有」")

	# ---- 7. 清单⑦：退出关闭商店覆盖层 ----
	exit_btn = panel.get_node("TopBar/ExitButton")
	exit_btn.pressed.emit()
	await process_frame
	check(bool(game.has_open_overlay()) == false, "清单⑦：退出关闭商店覆盖层")

	# ---- 8. 持久化：文件验证 + 模拟重启读回 ----
	check(FileAccess.file_exists(SAVE_PATH), "存档文件存在（自动保存）")
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		check(typeof(parsed) == TYPE_DICTIONARY, "存档文件为合法 JSON")
		if typeof(parsed) == TYPE_DICTIONARY:
			var sk: Dictionary = parsed["skins"]
			check((sk["owned"] as Array).has("skin_02"), "文件 owned 含免费皮肤 skin_02")
			check((sk["owned"] as Array).has("skin_07"), "文件 owned 含付费皮肤 skin_07")
			check((sk["owned"] as Array).has("skin_origin_kaitou"), "K-D：文件 owned 含默认开头原创")
			check_eq(sk["equipped"], "skin_02", "文件 equipped=skin_02")
			check_eq(int(parsed["talent"]), 795, "文件 talent=795")
	else:
		check(false, "存档文件可读")
	save.load_game()  # 模拟重启读回
	panel = await _open(game, overlay)
	check(panel != null, "重启后商店可再次打开")
	if panel != null:
		check_eq((panel.get_node("TopBar/BalanceLabel") as Label).text, "天赋值：795", "重启读回：余额 795")
		var grid2: GridContainer = panel.get_node("Content/GridPanel/Scroll/SkinGrid")
		check_eq(grid2.get_child_count(), 47, "重启读回：网格仍 47 格")
		var cards2: Dictionary = panel.get("_cards")
		if cards2.has("skin_02"):
			check(((cards2["skin_02"] as VBoxContainer).get_child(1) as Label).text.contains("穿戴中"), "重启读回：穿戴状态反映 skin_02")

	# ---- 9. K-D P2-1 回归：已解锁原创可经 _on_select 穿戴（owned 判定前移，不被 buyable 守卫吞）----
	save.unlock_origin_skin(2)  # 模拟通关/剧情解锁宋原创 → owned 含 skin_origin_song（未穿戴）
	var song_skin: Dictionary = catalog.get_skin("skin_origin_song")
	panel.call("_on_select", song_skin)
	check_eq(save.get_skins()["equipped"], "skin_origin_song", "K-D P2-1：已解锁原创 _on_select 直接穿戴（功能死路回归）")

	# ---- 10. 批次 Q2（spec §四/§七 8~9）：余额不足 toast 置顶居中（toast_spy 四参断言）----
	# 批次V§3.2 等价替换留痕：先卸下统一确认条 spy——strip 在位时 Game.toast centered=true
	# 单点改道 push_info 会绕过右上 ToastCenter；本段断言对象是右上原路径（未挂接降级环境），
	# 故 attach_strip(null) 还原（strip 路径断言已由段 3 与 test_v_confirm_migration.gd 承接）。
	game.call("attach_strip", null)
	var spy: Node = load("res://tests/fixtures/toast_spy.gd").new()
	add_child(spy)
	game.call("attach_toast", spy)  # 注入链参照 test_k_regression.gd:79~84
	save.spend_talent(save.get_talent())  # 归零再补 100：复现余额不足（<205）
	save.add_talent(100)
	var q2_paid: Dictionary = catalog.get_skin("skin_08")  # 未拥有付费皮肤（同段 3 路径）
	panel.call("_show_detail", q2_paid)
	panel.set("_selected", q2_paid)  # 磁盘实况：_show_detail 只置 _preview（shop_panel.gd:128 在 _on_select 内），_selected 需显式置（:273 防御路径先例）
	panel.call("_on_confirmed")
	var q2_calls: Array = spy.call("get_calls")
	check(q2_calls.size() >= 1, "Q2 前置：spy 收到余额不足 toast")
	if q2_calls.size() >= 1:
		var q2_last: Array = q2_calls[q2_calls.size() - 1]
		check_eq(String(q2_last[0]), "天赋值不足，无法购买", "Q2：余额不足 toast 文案透传")
		check_eq(String(q2_last[1]), "warn", "Q2：余额不足 toast level=warn")
		check_eq(float(q2_last[2]), 2.5, "Q2：余额不足 toast seconds=2.5 显式（同 FailToast 四参）")
		check(q2_last[3] == true, "Q2：余额不足 toast centered=true（置顶居中，不再遮设置钮）")
	panel.set("_selected", catalog.get_skin("skin_07"))  # 已拥有付费皮肤（段 4 购入）
	panel.call("_on_confirmed")
	var q2b_calls: Array = spy.call("get_calls")
	check(q2b_calls.size() >= 2, "Q2 回归前置：已拥有路径亦 toast")
	if q2b_calls.size() >= 2:
		var q2b_last: Array = q2b_calls[q2b_calls.size() - 1]
		check_eq(String(q2b_last[0]), "已拥有该皮肤", "Q2 回归：已拥有 toast 文案不变")
		check(q2b_last[3] == false, "Q2 回归：已拥有 toast 仍右上角（centered=false 不误伤）")
	panel.set("_selected", catalog.get_skin("skin_03"))  # 免费（目录 i<=6）且未拥有
	var q2c_before: int = (spy.call("get_calls") as Array).size()
	panel.call("_on_confirmed")
	check_eq((spy.call("get_calls") as Array).size(), q2c_before, "Q2 回归：免费领取路径无 toast（行为不变）")
	game.call("attach_toast", null)  # 卸下 spy，还原 Game 降级路径

	# ---- 11. 批次 W3（P2-10，规格 §4）：详情购买钮文案三态——已拥有=「穿戴」----
	# 旧况：仅 locked_origin 特判，已拥有仍显示「购买」（点击实际直接穿戴不扣费，文案误导）。
	# 改法：owned 分支钮文案改「穿戴」；点击行为不动（_on_buy→_on_select owned→equip_skin，
	# 段 5/6 回归承接）；locked_origin「随剧情解锁」不动。三态断言=规格验收锚。
	var buy_btn11: Button = panel.get_node("Content/DetailBox/DetailInner/DetailBottom/BuyButton")
	# 11a 未解锁原创 → 随剧情解锁（分支不动，回归锚）
	panel.call("_show_detail", catalog.get_skin("skin_origin_yuan"))  # 段 9 已解锁 song，改用从未解锁的 yuan 原创
	check_eq(String(buy_btn11.text), "随剧情解锁",
		"W-P2-10：未解锁原创详情钮「随剧情解锁」不动（回归锚）")
	check_eq(bool(buy_btn11.disabled), true, "W-P2-10：未解锁原创详情钮 disabled 保持（回归锚）")
	# 11b 未拥有普通皮肤 → 购买（不动，回归锚）
	panel.call("_show_detail", catalog.get_skin("skin_08"))
	check_eq(String(buy_btn11.text), "购买",
		"W-P2-10：未拥有普通皮肤详情钮「购买」不动（回归锚）")
	check_eq(bool(buy_btn11.disabled), false, "W-P2-10：未拥有详情钮可用保持")
	# 11c 已拥有（段 4 购入 skin_07）→ 穿戴（红：旧文案「购买」误导）
	panel.call("_show_detail", catalog.get_skin("skin_07"))
	check_eq(String(buy_btn11.text), "穿戴",
		"W-P2-10：已拥有详情钮文案「穿戴」（红：旧「购买」——点击实际直接穿戴不扣费）")
	check_eq(bool(buy_btn11.disabled), false, "W-P2-10：已拥有详情钮可用（点击=equip 穿戴，行为不变）")
	# 11d 点击行为不变冒烟：文案「穿戴」态点击 → 直接 equip+零扣费+零确认条
	var talent_before11: int = int(save.get_talent())
	var equipped_before11: String = String((save.get_skins() as Dictionary)["equipped"])
	var confirms_before11: int = _confirm_count()
	buy_btn11.pressed.emit()
	await _settle()
	check_eq(int(save.get_talent()), talent_before11, "W-P2-10：详情「穿戴」点击零扣费（点击行为不变）")
	check_eq(String((save.get_skins() as Dictionary)["equipped"]), "skin_07",
		"W-P2-10：详情「穿戴」点击生效（%s→skin_07；equip 直穿戴）" % equipped_before11)
	check_eq(_confirm_count(), confirms_before11, "W-P2-10：详情「穿戴」点击零确认条（直穿戴语义）")

	_cleanup()
	ssp.queue_free()
	finish()
