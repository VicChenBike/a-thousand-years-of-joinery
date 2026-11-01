extends "res://tests/test_base.gd"
## M-S（批次 M spec §3.6B，用户追加 追4，2026-09-07）：商店界面布局紧凑化 + 神通谱文案缩短。
## 契约（spec §3.6B 目标行为 1~4 / 验收标准 1~2）：
##   ① 「选择（购买）」按钮常驻详情面板右下角——移出 DetailScroll，挂 DetailInner/DetailBottom
##     固定底行（价格左/按钮右），滚动前后全局 rect 不变（不随长文本下挤，m09 用户实测）。
##   ② 神通谱文案 47 段全量缩短：每段非空且 ≤70 字（暂定口径，spec §3.6B）。
##   ③ 详情紧凑：DetailVBox 顶对齐（SHRINK_BEGIN，等价替换 test_shop_panel 旧 EXPAND_FILL 口径）、
##     DetailImage 固定高不 expand，图/文垂直空隙 = VBox separation ≤24（m09 右红圈根除）。
##   ④ 左网格吃满：卡片 EXPAND_FILL → 末列右缘距 GridPanel 内容区右缘 ≤8（m09 左红圈整列空白根除）；
##     v_scrollbar 压缩 ≤8px 防吃满被滚动条顶开。
## 坑位吸收（spec §六）：①container.size 钉设计视口 1152×648（headless expand 撑 1152×1152 伪象）；
##   ⑩PanelContainer 非 Panel 子类——stylebox 按 get_theme_stylebox("panel") 取；
##   ⑦跨脚本常量动态访问 load().get() 判空 guard（DESC 表）。

const W := 1152.0
const H := 648.0
const SCENE_PATH := "res://scenes/shop/shop_panel.tscn"
const CATALOG := "res://data/skin_catalog.gd"
const DESC_MAX := 70
const GAP_IMG_DESC := 24.0  # 图/文垂直空隙上限（spec §3.6B 暂定）
const GAP_GRID := 8.0       # 末列右缘距面板内边距上限（spec §3.6B）

func _initialize() -> void:
	print("== test_m_shop_layout ==")
	var save: Variant = get_root().get_node("SaveManager")
	save.load_game()  # 复位内存态（只读场景，防他文件遗留穿戴态影响默认详情）
	var catalog: GDScript = load(CATALOG)
	_sec_desc(catalog)
	await _sec_layout()
	finish()

# ==================== 段 E：神通谱文案 47 段全量缩短（spec 验收 1） ====================

func _sec_desc(catalog: GDScript) -> void:
	var skins: Array = catalog.call("get_skins")
	check_eq(skins.size(), 47, "M-S：目录 47 段文案（5 原创 + 42）")
	var empty_ids: PackedStringArray = []
	var long_ids: PackedStringArray = []
	var total: int = 0
	var max_len: int = 0
	for s: Dictionary in skins:
		var d: String = String(s.get("desc", ""))
		total += d.length()
		max_len = maxi(max_len, d.length())
		if d.is_empty() or d == "——":
			empty_ids.append(String(s["id"]))
		if d.length() > DESC_MAX:
			long_ids.append("%s(%d)" % [String(s["id"]), d.length()])
	check(empty_ids.is_empty(), "E：47 段文案全部非空（缺=%s）" % [empty_ids])
	check(long_ids.is_empty(), "E：47 段文案每段 ≤%d 字（超=%s）" % [DESC_MAX, long_ids])
	check(max_len > 0 and max_len <= DESC_MAX, "E：最长段 %d 字 ∈ (0,%d]" % [max_len, DESC_MAX])
	check(total >= 47 and total <= 47 * DESC_MAX, "E：总字数 %d ∈ [47,%d]（原 3832 → 缩短）" % [total, 47 * DESC_MAX])
	# DESC 常量表键数一致（⑦坑：load().get() 判空 guard，未定义不挂死）
	var desc_table: Variant = catalog.get("DESC")
	if desc_table is Dictionary:
		check_eq((desc_table as Dictionary).size(), 47, "E：DESC 常量表 47 键（无缺漏/冗余）")
	else:
		check(false, "E：DESC 常量表可读（实际 %s）" % [type_string(typeof(desc_table))])

# ==================== 段 A~D：布局（spec 验收 1/2，钉设计视口） ====================

func _sec_layout() -> void:
	check(ResourceLoader.exists(SCENE_PATH), "shop_panel.tscn 存在")
	if not ResourceLoader.exists(SCENE_PATH):
		finish()
		return
	var container: Control = Control.new()
	container.size = Vector2(W, H)  # 钉设计视口（headless expand 伪象防御，spec §六坑 1）
	add_child(container)
	var panel: Control = (load(SCENE_PATH) as PackedScene).instantiate()
	container.add_child(panel)
	await process_frame
	await process_frame

	# ---- 段 A：结构（购买钮出滚动区 / 题头固定 / 价格固定底行） ----
	var inner: Control = panel.get_node_or_null("Content/DetailBox/DetailInner")
	check(inner is VBoxContainer, "A：DetailInner(VBox) 存在（M-S 详情重排容器）")
	var dtitle: Control = panel.get_node_or_null("Content/DetailBox/DetailInner/DetailTitle")
	check(dtitle is Label, "A：DetailTitle 移出滚动区（固定题头，不随长文滚出）")
	var dscroll: ScrollContainer = panel.get_node_or_null("Content/DetailBox/DetailInner/DetailScroll")
	check(dscroll is ScrollContainer, "A：DetailScroll 挂 DetailInner（描述文本独立滚动）")
	var dvbox: Control = panel.get_node_or_null("Content/DetailBox/DetailInner/DetailScroll/DetailVBox")
	check(dvbox is VBoxContainer, "A：DetailVBox 在 Scroll 内（随文本滚动）")
	var dbottom: Control = panel.get_node_or_null("Content/DetailBox/DetailInner/DetailBottom")
	check(dbottom is HBoxContainer, "A：DetailBottom(HBox) 固定底行存在")
	var buy_btn: Button = panel.get_node_or_null("Content/DetailBox/DetailInner/DetailBottom/BuyButton")
	check(buy_btn is Button, "A：BuyButton 挂 DetailBottom（滚动区外，常驻右下）")
	var dprice: Label = panel.get_node_or_null("Content/DetailBox/DetailInner/DetailBottom/DetailPrice")
	check(dprice is Label, "A：DetailPrice 固定底行（价格不再随文本滚动）")
	check(panel.get_node_or_null("Content/DetailBox/DetailScroll") == null, "A：旧直挂 DetailBox/DetailScroll 路径已废（等价替换留痕）")
	check(panel.get_node_or_null("Content/DetailBox/DetailInner/DetailScroll/DetailVBox/BuyButton") == null, "A：BuyButton 不再在滚动区内（根除下挤）")
	check(panel.get_node_or_null("Content/DetailBox/DetailInner/DetailScroll/DetailVBox/DetailSpacer") == null, "A：DetailSpacer 已删（紧凑化重心上移）")
	if buy_btn == null or dscroll == null or dvbox == null or inner == null:
		finish()
		return

	# ---- 段 B：按钮常驻右下（滚动前后全局 rect 不变 + 贴面板右下内缘） ----
	var rect0: Rect2 = buy_btn.get_global_rect()
	var filler: Control = Control.new()
	filler.custom_minimum_size = Vector2(0, 800)  # 制造溢出驱动真实滚动
	dvbox.add_child(filler)
	await process_frame
	await process_frame
	dscroll.scroll_vertical = 200
	await process_frame
	await process_frame
	check(dscroll.scroll_vertical > 0, "B：模拟滚动真实生效（scroll_vertical=%d）" % dscroll.scroll_vertical)
	var rect1: Rect2 = buy_btn.get_global_rect()
	check(absf(rect1.position.y - rect0.position.y) < 0.5 and absf(rect1.position.x - rect0.position.x) < 0.5,
		"B：滚动前后按钮全局位置不变（常驻右下，spec 验收 1）")
	var dbox: Control = panel.get_node("Content/DetailBox")
	var sb: StyleBox = dbox.get_theme_stylebox("panel")
	var inner_right: float = dbox.get_global_rect().end.x - sb.get_margin(SIDE_RIGHT)
	var inner_bottom: float = dbox.get_global_rect().end.y - sb.get_margin(SIDE_BOTTOM)
	var dr: float = absf(buy_btn.get_global_rect().end.x - inner_right)
	var db: float = absf(buy_btn.get_global_rect().end.y - inner_bottom)
	check(dr <= 4.0, "B：按钮右缘贴面板右内缘（差 %.1f ≤4）" % dr)
	check(db <= 4.0, "B：按钮底缘贴面板底内缘（差 %.1f ≤4）" % db)
	dvbox.remove_child(filler)
	filler.queue_free()
	await process_frame
	await process_frame

	# ---- 段 C：左网格吃满（m09 左红圈：末列右缘距面板内边距 ≤8） ----
	var grid_panel: Control = panel.get_node("Content/GridPanel")
	var grid: GridContainer = panel.get_node("Content/GridPanel/Scroll/SkinGrid")
	check_eq(grid.columns, 3, "C：SkinGrid 3 列（卡片宽自适应吃满，列数口径不变）")
	var cards: Dictionary = panel.get("_cards")
	check_eq(cards.size(), 47, "C：卡片 47 张")
	await process_frame
	var max_right: float = -1.0
	var max_card_w: float = 0.0
	for id: String in cards.keys():
		var c: Control = cards[id]
		max_right = maxf(max_right, c.get_global_rect().end.x)
		max_card_w = maxf(max_card_w, c.get_global_rect().size.x)
	var gsb: StyleBox = grid_panel.get_theme_stylebox("panel")
	var gap: float = grid_panel.get_global_rect().end.x - gsb.get_margin(SIDE_RIGHT) - max_right
	check(gap >= -0.5, "C：末列未越出面板内容区（gap=%.1f ≥0）" % gap)
	check(gap <= GAP_GRID, "C：末列右缘距面板内边距 ≤%.0f（实际 %.1f，m09 左红圈整列空白根除）" % [GAP_GRID, gap])
	check(max_card_w >= 200.0, "C：卡片宽 expand 自适应（%.0f > min 180）" % max_card_w)
	var vscroll: ScrollBar = (grid.get_parent() as ScrollContainer).get_v_scroll_bar()  # 4.7：访问器 get_v_scroll_bar() 大写 B
	check(vscroll.custom_minimum_size.x <= GAP_GRID, "C：v_scrollbar 压缩 ≤%.0fpx（实际 %.0f，防吃满被滚动条顶开）" % [GAP_GRID, vscroll.custom_minimum_size.x])

	# ---- 段 D：详情紧凑（m09 右红圈：图/文垂直空隙 ≤24） ----
	var dimg: TextureRect = panel.get_node("Content/DetailBox/DetailInner/DetailScroll/DetailVBox/DetailImage")
	var ddesc: Label = panel.get_node("Content/DetailBox/DetailInner/DetailScroll/DetailVBox/DetailDesc")
	check(int(dimg.size_flags_vertical) != int(Control.SIZE_EXPAND_FILL), "D：DetailImage 不再纵向 expand（m09 图文大空隙根因）")
	check_eq(int(dvbox.size_flags_vertical), int(Control.SIZE_SHRINK_BEGIN),
		"D：DetailVBox 顶对齐 SHRINK_BEGIN（重心上移，M-S 等价替换 test_shop_panel 旧 EXPAND_FILL 断言）")
	check_eq(int(dvbox.size_flags_horizontal), int(Control.SIZE_EXPAND_FILL),
		"D（走查 NG 回修）：DetailVBox 横向 EXPAND_FILL——Scroll 内撑满视口宽，desc 不再窄列（每行 2~4 字根因）")
	check(ddesc.size.x >= 250.0, "D（走查 NG 回修）：desc 宽 ≥250（实际 %.0f，面板 320 宽下每行 ~17 字）" % ddesc.size.x)
	var vgap: float = ddesc.get_global_position().y - dimg.get_global_rect().end.y
	check(vgap >= -0.5 and vgap <= GAP_IMG_DESC, "D：图/文垂直空隙 ≤%.0f（实际 %.1f，m09 右红圈根除）" % [GAP_IMG_DESC, vgap])
	check(dimg.custom_minimum_size.y <= 240.0, "D：立绘固定高紧凑（min %.0f ≤240）" % dimg.custom_minimum_size.y)
	check(ddesc.autowrap_mode != TextServer.AUTOWRAP_OFF, "D：描述 autowrap 保留（缩短文案仍自适应换行）")
	# 批次 W（P2-10）等价改写：该详情皮肤已拥有 → 钮文案「穿戴」
	# （旧「购买」断言随 P2-10 拥有态分文案等价改写留痕；点击路由零改动不变）。
	check_eq(String(buy_btn.text), "穿戴", "D：详情按钮文本=「穿戴」（P2-10 拥有态分文案；路由零改动）")
