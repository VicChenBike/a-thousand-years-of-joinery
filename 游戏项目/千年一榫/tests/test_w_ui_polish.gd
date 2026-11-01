extends "res://tests/test_base.gd"
## 批次 W3 玩家可见 UI 走查项集合件（TDD 先红；规格 §4；P1-5 归 test_w_topstrip_level）：
##   段 A（N1）：TopStrip info 模式叉号可见可点——× 移到条标题行常显（info/confirm 两模式均
##     可见可点，点击仅收条零副作用）；旧 confirm 语义（×与取消等价）不破坏。
##   段 B（N2）：四处弹窗统一「自屏幕上方滑入」入场动效（0.25s + 淡入）——TopStrip /
##     ToastCenter / GlassDialog / 退出倒数弹窗；直接 tween position（禁 set_anchors_preset 坑⑧）；
##     终态位置与现状一致（断言初始 y<目标 + 终值==目标）。
##   段 C（P1-6）：五处静态米白字色改主题双档（tscn 删静态 override → level_scene 回调联动）。
##   段 D（P1-7a）：WitnessPortrait 立绘本体 mouse_filter 放行（重叠带命中归 MainView）。
##   段 E（P1-7b）：WitnessPortrait/HintLabel 挂 meta("interactive")（拖窗白名单语义）。
##   段 F（P1-7c）：SHOP 展开态收起钮挪出 GridPanel 重叠区（矩形零相交硬断言）。
##   段 G（N4）：下拉行选中/未选字色双档（未选=中性灰族，消除「变细」观感）。
## 防坑：坑⑥ add 后 await 放行帧；坑⑧ 禁 set_anchors_preset；钉设计视口 1152×648；
## 坑⑦⑪ 字典/Variant 判空短路；level_scene 实例 _settled 直写拦截退出写盘（零 user:// 写路径）。

const WIN := Vector2i(1152, 648)
const STATE_BOOT := 0

func _rect(n: Control) -> Rect2:
	return Rect2(n.global_position, n.size)

func _make_strip() -> Control:
	var strip: Control = (load("res://scenes/shared/top_strip.gd") as GDScript).new()
	add_child(strip)
	await process_frame
	return strip

func _initialize() -> void:
	print("== test_w_ui_polish（批次 W3：N1/N2/P1-6/P1-7abc/N4） ==")
	root.size = WIN
	await process_frame
	# 批次 AF 终审备案族（语言钉扎先例=6411fae o_catalog_shop）：autoload _ready 推迟至树激活，
	# 须等一帧后钉 zh——用户真实存档现 language=en，不钉则文案断言呈 en 态假红。
	# 编译窗安全：经节点查找而非全局名（--script 模式 autoload 全局名编译期未注册）。
	var i18n_node: Variant = get_root().get_node_or_null("I18n")
	if i18n_node != null:
		i18n_node.call("set_language", "zh")
	await _a_topstrip_close_btn()
	await _b_slide_in_animations()
	await _c_level_bar_theme()
	await _d_witness_pick_band()
	await _e_drag_whitelist_meta()
	await _f_shop_fold_btn_clearance()
	await _g_camera_menu_tint()
	finish()

# ================= 段 A（N1）：info 模式叉号可见可点 =================
func _a_topstrip_close_btn() -> void:
	var strip: Control = await _make_strip()
	var close_path: String = "Row/CloseButton"
	var close_btn: Button = strip.get_node_or_null(close_path) as Button
	check(close_btn != null, "A1: × 钮在条标题行 Row/CloseButton（红：旧件藏于 info 隐藏的 BtnRow）")
	check(close_btn != null and String(close_btn.text) == "×", "A2: × 钮文案（回归锚）")
	# A3 info 模式：× 可见（红：旧实现 BtnRow 整行隐藏，用户截图不可见）
	strip.call("push_info", "手势交互需要摄像头，无法关闭")
	check(close_btn != null and bool(close_btn.visible), "A3: info 模式 × 可见（红：旧 BtnRow 隐藏连带 × 隐）")
	check(bool(strip.visible), "A3 前置：info 条在显")
	# A4 点击 × → 条收起零副作用（无回调路径零异常）
	if close_btn != null:
		close_btn.pressed.emit()
	check_eq(bool(strip.visible), false, "A4: info 模式点 × → 条收起（红：× 不可点即收不起）")
	# A5 confirm 模式：× 常显不破坏（旧语义回归锚——× 与取消等价由 test_v_top_strip 段 A5 承接）
	strip.call("push_confirm", "确认退出？", Callable(), Callable())
	check(close_btn != null and bool(close_btn.visible), "A5: confirm 模式 × 仍可见（旧语义回归）")
	if close_btn != null:
		close_btn.pressed.emit()
	check_eq(bool(strip.visible), false, "A6: confirm 模式点 × → 条收起（回归锚）")
	strip.free()
	await process_frame

# ================= 段 B（N2）：四处入场动效 =================
func _b_slide_in_animations() -> void:
	# ---- B1 TopStrip：自目标位上方滑入（目标 y=70，条高+14 的落差）----
	var strip: Control = await _make_strip()
	strip.call("push_info", "动效条")
	var start_y := float(strip.position.y)
	check(start_y < 70.0, "B1: TopStrip 初始 position.y<目标 70（红：旧实现仅 modulate 淡入无位移；实测 %.1f）" % start_y)
	await create_timer(0.5).timeout
	check(absf(float(strip.position.y) - 70.0) <= 1.0, "B2: TopStrip 动效终值 y≈70（终态与现状一致；实测 %.1f）" % float(strip.position.y))
	check(absf(float(strip.get("offset_top")) - 70.0) <= 1.0, "B3: TopStrip 终态 offset_top 回 70（锚定口径未被动效污染）")
	strip.free()
	await process_frame
	# ---- B2 ToastCenter：卡片自上方滑入（VBox 叠放位上方）----
	var tc: Control = (load("res://scenes/shared/toast_center.gd") as GDScript).new()
	add_child(tc)
	await process_frame
	tc.call("push", "第一条", "warn", 60.0)
	await create_timer(0.45).timeout   # 回修 P1-1 后动效真实运行——等首卡滑入完成再取叠放基准位
	var c1: Control = tc.get_child(0) as Control
	var c1_final := float(c1.position.y)
	check(absf(c1_final - 0.0) <= 1.0, "B4 前置：首卡容器落位 y≈0（实测 %.1f）" % c1_final)
	tc.call("push", "第二条", "warn", 60.0)
	var c2: Control = tc.get_child(1) as Control
	var c2_final := c1_final + c1.size.y + 8.0
	check(float(c2.position.y) < c2_final - 1.0,
		"B4: Toast 卡片初始 position.y<叠放目标（红：旧实现仅淡入；实测 %.1f 目标 %.1f）" % [float(c2.position.y), c2_final])
	# B4b 回修 P1-1 护栏（审查实锤）：VBox 对 add_child 的排序 deferred——若动效在 add 同帧启动，
	# fit_child_in_rect 会把起点强制放回叠放位，position:y tween 变 final→final 恒值空转、只剩
	# 淡入（旧实现 B4 假绿来源）。中途帧断言锁「真实位移」：0.1s 时 start<pos<final-1。
	await create_timer(0.1).timeout
	var c2_mid := float(c2.position.y)
	var c2_h := float(c2.size.y)   # 中途帧容器已定尺寸（==滑入起算高度）
	var c2_start := c2_final - (c2_h + 14.0)
	check(c2_mid > c2_start and c2_mid < c2_final - 1.0,
		"B4b: Toast 中途帧真实位移 start(%.1f)<mid(%.1f)<final-1(%.1f)（红：tween 空转假绿）"
			% [c2_start, c2_mid, c2_final - 1.0])
	await create_timer(0.4).timeout
	check(absf(float(c2.position.y) - c2_final) <= 1.0,
		"B5: Toast 卡片终值==容器叠放位（终态与现状一致；实测 %.1f 目标 %.1f）" % [float(c2.position.y), c2_final])
	check(absf(float(c1.position.y) - c1_final) <= 1.0, "B6: 首卡不受第二卡动效扰动（回归锚）")
	tc.free()
	await process_frame
	# ---- B3 GlassDialog：Card 自上方滑入，终态==锚定居中现状 ----
	var gd: Control = (load("res://scenes/shared/glass_dialog.tscn") as PackedScene) \
		.instantiate() as Control
	add_child(gd)
	await process_frame
	await process_frame
	# 实证坑（test_u_dock_anchors 先例）：无头 expand 撑 1152×1152——add 后补钉设计视口再等两帧
	root.size = WIN
	await process_frame
	await process_frame
	var card: Control = gd.get_node("Card") as Control
	var gd_target: Vector2 = card.position   # 现状终态=锚定派生位（可见性无关，布局已算）
	check(absf(gd_target.x - (root.size.x * 0.5 - 180.0)) <= 1.0,
		"B7 前置：Card 锚定居中位可读（x 实测 %.1f）" % gd_target.x)
	gd.call("open_centered")
	check(float(card.position.y) < gd_target.y - 1.0,
		"B7: GlassDialog Card 初始 position.y<居中目标（红：旧实现无动效；实测 %.1f 目标 %.1f）" % [float(card.position.y), gd_target.y])
	await create_timer(0.5).timeout
	check(card.position.distance_to(gd_target) <= 1.0,
		"B8: GlassDialog Card 终值==锚定居中位（终态与现状一致；实测 %s 目标 %s）" % [card.position, gd_target])
	gd.call("close")
	gd.free()
	await process_frame
	# ---- B4 退出倒数弹窗：同款滑入（锚 0.5 / offset −64）----
	var ed: Control = (load("res://scenes/shared/gesture_exit_dialog.tscn") as PackedScene) \
		.instantiate() as Control
	add_child(ed)
	await process_frame
	await process_frame
	root.size = WIN
	await process_frame
	await process_frame
	var ed_card: Control = ed.get_node("Card") as Control
	var ed_target: Vector2 = ed_card.position
	ed.call("show_countdown", 3)
	check(float(ed_card.position.y) < ed_target.y - 1.0,
		"B9: 退出倒数弹窗 Card 初始 position.y<居中目标（红：旧实现无动效；实测 %.1f 目标 %.1f）" % [float(ed_card.position.y), ed_target.y])
	await create_timer(0.5).timeout
	check(ed_card.position.distance_to(ed_target) <= 1.0,
		"B10: 退出倒数弹窗 Card 终值==锚定居中位（实测 %s 目标 %s）" % [ed_card.position, ed_target])
	ed.call("close_countdown")
	ed.free()
	await process_frame

# ================= 段 C（P1-6）：五处静态字色改主题双档 =================
## 规格 §4 P1-6：tscn :66/:75/:84/:95/:289 五处静态米白 font_color 删除，并入 level_scene 既有
## theme_changed 回调；常量 LEVEL_BAR_FONT_DARK(0.949,0.910,0.835)/LIGHT(0.227,0.165,0.063)。
## 双档断言：常量两档值 + headless 浅档 live（is_dark 冻结 false）+ 注入深档（_apply_level_bar_theme
## force 参数缝，refresh(force_dark) 同款口径）+ theme_changed 真信号链回浅。
func _c_level_bar_theme() -> void:
	var src: String = FileAccess.get_file_as_string("res://scenes/level/level_scene.tscn")
	check(src.contains("Color(0.9490196, 0.9098039, 0.8352941, 1)") == false,
		"C1: tscn 五处静态米白 font_color 已删除（红：静态 override 仍在）")
	var level: Node = (load("res://scenes/level/level_scene.tscn") as PackedScene).instantiate()
	level.call("set_context", {"chapter": 1})
	add_child(level)
	await process_frame
	await process_frame
	root.size = WIN   # add 后补钉（expand 坑，test_u_dock_anchors 先例）
	await process_frame
	await process_frame
	var labels: Array = []
	for p: String in ["TopBar/TitleLabel", "TopBar/TalentLabel", "TopBar/TimerLabel",
			"TopBar/VoxelLabel", "HintLabel"]:
		var l: Label = level.get_node_or_null(p) as Label
		labels.append(l)
		check(l != null, "C 前置：%s 在场" % p)
	# C2 常量档（规格档值逐字）；批次 AB-3：LEVEL_BAR_FONT_LIGHT 浅档随机制删除退役——反向锁。
	var cd: Variant = level.get("LEVEL_BAR_FONT_DARK")
	check(cd is Color and (cd as Color).is_equal_approx(Color(0.949, 0.910, 0.835)),
		"C2: LEVEL_BAR_FONT_DARK=(0.949,0.910,0.835)（顶栏米白唯一真值）")
	check(level.get("LEVEL_BAR_FONT_LIGHT") == null,
		"AB-3 反向锁: LEVEL_BAR_FONT_LIGHT 浅档常量退役（无复辟）")
	# C4 入树恒深档 live：五 Label 米白（旧「浅档深棕 live」断言随深浅主题机制删除退役——
	# 等价改写：入树终态=旧深档米白值，逐一未变）。
	var dark_live_ok := true
	for l2: Label in labels:
		if l2 == null or not l2.get_theme_color("font_color").is_equal_approx(Color(0.949, 0.910, 0.835)):
			dark_live_ok = false
	check(dark_live_ok, "AB-3 等价改写: 入树五 Label 字色恒米白（旧静态 override 深棕缺陷不复辟）")
	# C5 重复应用幂等（force 注入缝退役 → 无参直调，值恒米白）
	level.call("_apply_level_bar_theme")
	var dark_ok := true
	for l3: Label in labels:
		if l3 == null or not l3.get_theme_color("font_color").is_equal_approx(Color(0.949, 0.910, 0.835)):
			dark_ok = false
	check(dark_ok, "AB-3: 重复应用五 Label 字色恒米白（深档唯一真值幂等）")
	# C6/C7 旧「refresh 翻转真信号链」断言随 ThemeManager.refresh/theme_changed 退役——
	# 等价改写：信号无复辟反向锁 + force 注入缝参数个数锁。
	var tm: Node = root.get_node("ThemeManager")
	check(not tm.has_signal("theme_changed"),
		"AB-3 反向锁: C6 真信号链随 theme_changed 退役（无复辟通道）")
	var bar_argc: int = 0
	for m: Dictionary in (level.get_script() as Script).get_script_method_list():
		if String(m.get("name", "")) == "_apply_level_bar_theme":
			bar_argc = (m.get("args", []) as Array).size()
	check(bar_argc == 0,
		"AB-3 反向锁: _apply_level_bar_theme 无 force 注入参（双档通道退役，实际 args=%d）" % bar_argc)
	level.set("_settled", true)
	level.free()
	await process_frame

# ================= 段 D（P1-7a → AD §4.3.5 等价改写）：立绘点击恢复与拾取带根因消除 =================
## 规格 §4 P1-7a 旧口径：MainView 覆盖立绘 → 立绘本体让出拾取带 STOP→IGNORE（重叠带命中归 MainView，
## 立绘点击休眠）。批次 AD §4.3.5 有意反转：MainView 锚点 anchor_left 0.0399→0.115 **收窄避让**左下角
## 立绘（WitnessPortrait anchor_right=0.11），两者水平矩形不再重叠 → 重叠带根因消失，立绘恢复 STOP
## 且直连 gui_input 点击弹泡（旧值留痕：D1 `== IGNORE` / D2「重叠带实存 ≈80×150 死区」/ D3「样本点落
## MainView 容器 STOP 区」——三条判据逐条反置为「STOP + 零重叠带 + 死区消除」，条数 3→3 不减，
## 本段核心不变量「立绘/MainView 拾取互不侵占」以「几何分离」新形态保持）。
func _d_witness_pick_band() -> void:
	var level: Node = (load("res://scenes/level/level_scene.tscn") as PackedScene).instantiate()
	level.call("set_context", {"chapter": 1})
	add_child(level)
	await process_frame
	await process_frame
	root.size = WIN
	await process_frame
	await process_frame
	var witness: TextureRect = level.get_node_or_null("WitnessPortrait") as TextureRect
	var main_view: Panel = level.get_node_or_null("MainView") as Panel
	var main_cont: Control = level.get_node_or_null("MainView/ViewportContainer") as Control
	check(witness != null and main_view != null and main_cont != null, "D 前置：立绘/MainView/容器在场")
	check(witness != null and int(witness.mouse_filter) == Control.MOUSE_FILTER_STOP,
		"AD §4.3.5 D1: 立绘本体 mouse_filter==STOP（锚点收窄消除重叠带后可点击恢复；旧 P1-7a IGNORE 让位随根因消失退役）")
	if witness != null and main_view != null:
		var band: Rect2 = _rect(witness).intersection(_rect(main_view))
		check(band.size.x <= 1.0 or band.size.y <= 1.0,
			"AD §4.3.5 D2: 立绘×MainView 水平零重叠带（anchor_left 0.115 收窄，死区根因消除；旧「重叠带实存 ≈80×150」反置留痕，实测 %s）" % band)
		check(_rect(witness).end.x <= _rect(main_view).position.x + 0.5,
			"AD §4.3.5 D3: 立绘右缘 ≤ MainView 左缘（几何分离，样本点不再被 MainView STOP 吞没；旧「重叠带样本归 MainView」反置留痕）")
	var bubble: Label = level.get_node_or_null("WitnessBubble") as Label
	check(bubble != null and int(bubble.mouse_filter) == Control.MOUSE_FILTER_IGNORE,
		"D4: 见证者气泡独立控件不动（mouse_filter=IGNORE 语义保持）")
	level.set("_settled", true)
	level.free()
	await process_frame

# ================= 段 E（P1-7b）：拖窗白名单 meta =================
## 规格 §4 P1-7b：WitnessPortrait 与 HintLabel 挂 meta("interactive")（白名单语义已支持）；
## 不做全局 Label 白名单（保留空白区拖窗）。
func _e_drag_whitelist_meta() -> void:
	var level: Node = (load("res://scenes/level/level_scene.tscn") as PackedScene).instantiate()
	level.call("set_context", {"chapter": 1})
	add_child(level)
	await process_frame
	await process_frame
	var wm: GDScript = load("res://scripts/window_manager.gd")
	var witness: Control = level.get_node_or_null("WitnessPortrait") as Control
	var hint: Control = level.get_node_or_null("HintLabel") as Control
	check(witness != null and bool(wm.is_interactive_control(witness)),
		"E1: WitnessPortrait 在拖窗白名单（meta interactive；红：旧无 meta）")
	check(hint != null and bool(wm.is_interactive_control(hint)),
		"E2: HintLabel 在拖窗白名单（meta interactive；红：旧无 meta）")
	var plain := Label.new()
	add_child(plain)
	check(bool(wm.is_interactive_control(plain)) == false,
		"E3: 无 meta 普通 Label 不在白名单（不做全局 Label 白名单——语义锁死防扩大）")
	var blank := Control.new()
	add_child(blank)
	check(bool(wm.is_interactive_control(blank)) == false,
		"E4: 空白控件不在白名单（拖窗能力保留语义锚）")
	var svc := SubViewportContainer.new()
	add_child(svc)
	check(bool(wm.is_interactive_control(svc)),
		"E5: SubViewportContainer 在白名单（回归锚——立绘带命中归主视口后不拖窗）")
	plain.free(); blank.free(); svc.free()
	level.set("_settled", true)
	level.free()
	await process_frame

# ================= 段 F（P1-7c）：SHOP 收起钮让位格网 =================
## 规格 §4 P1-7c：SHOP 展开态收起钮（20×20 STOP）压商店格网首行（GridPanel 自 y 92 起，
## 旧公式落 y 90~110 实叠 ~20×18px）。几何红线=收起钮矩形 × GridPanel 矩形零相交；
## 其它场景展开态公式不变（回归锚）。
func _f_shop_fold_btn_clearance() -> void:
	var hud: Control = (load("res://scenes/shared/gesture_hud.tscn") as PackedScene).instantiate()
	var shop: Control = (load("res://scenes/shop/shop_panel.tscn") as PackedScene).instantiate()
	add_child(shop)
	add_child(hud)
	await process_frame
	await process_frame
	root.size = WIN   # add 后补钉（expand 坑）
	await process_frame
	await process_frame
	# AF 同步批（2026-11-01）：内存钉 gesture_input=true（同 test_w_camera_menu E 段手法，不落盘
	# 进程退出即弃；钉位于本文件首个 await 之后防 SaveManager._ready load_game 整体替换 _data
	# 引用冲钉）。实证：apply_dock_state 可见门 `gesture_hud_visible ∧ gesture_input` 在用户存档
	# Q3 双关时整组 visible=false 提前 return，停靠布局与收起钮定位全部跳过——F3 读到初始 (0,0)
	# 属夹具对存档环境敏感（F1/F2 同窗被早退绕过呈假绿），非代码回归。
	var sm_uip: Node = root.get_node_or_null("SaveManager")
	if sm_uip != null:
		var sm_data_uip: Dictionary = sm_uip.get("_data")
		if typeof(sm_data_uip.get("settings")) != TYPE_DICTIONARY:
			sm_data_uip["settings"] = {}
		(sm_data_uip["settings"] as Dictionary)["gesture_input"] = true
	var game: Node = root.get_node("Game")
	hud.set("_hint_folded", {})   # 清会话级折叠态（保证展开态公式路径）
	hud.call("apply_dock_state", int(game.State.MAIN_MENU), false, true)   # SHOP 键（shop_open=true）
	await process_frame
	await process_frame
	var grid: Control = shop.get_node_or_null("Content/GridPanel") as Control
	var btn: Control = hud.get_node_or_null("HintFoldBtn") as Control
	check(grid != null and btn != null, "F 前置：GridPanel/HintFoldBtn 在场")
	if grid != null and btn != null:
		var inter: Rect2 = _rect(btn).intersection(_rect(grid))
		check(inter.size == Vector2.ZERO,
			"F1: SHOP 展开态收起钮 × GridPanel 零相交（红：旧公式 y 90~110 压格网首行；钮=%s 格网=%s 交=%s）"
				% [_rect(btn), _rect(grid), inter.size])
		check(bool(btn.visible), "F2: 收起钮展开态可见可点（功能回归锚）")
	# 回归锚：非 SHOP 场景展开态公式不变（guide_panel 右上内缘 6px）
	hud.set("_hint_folded", {})
	hud.call("apply_dock_state", int(game.State.MAIN_MENU), false, false)
	await process_frame
	var gp: Control = hud.get_node_or_null("GuidePanel") as Control
	if gp != null and btn != null:
		var want: Vector2 = gp.position + Vector2(gp.size.x - 26.0, 2.0)
		check(btn.position.distance_to(want) <= 0.5,
			"F3: MAIN_MENU 展开态收起钮公式不变（回归锚；实测 %s 期望 %s）" % [btn.position, want])
	shop.free()
	hud.free()
	await process_frame

# ================= 段 G（N4）：下拉行选中/未选字色双档 =================
## 规格 §4 N4（W0 §四3 实证：无字重变化，字色+金棕底高亮致「变细」错觉）：未选=中性灰
##（NO_HAND_GRAY 族），选中=亮米白+金棕底保留；两主题双档。不改字号不改字重逻辑。
## 无头 is_dark() 冻结 → 双主题断言=常量两档 + 浅档 live（_tint_row 实刷）。
func _g_camera_menu_tint() -> void:
	var bridge: Node = root.get_node("GestureBridge")
	bridge.set("_camera_enum", {"cameras": [{"id": 0, "name": "CamA"}, {"id": 1, "name": "CamB"}],
		"current_camera": 0})
	bridge.set("_camera_matrix", {})
	bridge.set("_camera_errors", [])
	bridge.set("_probe_matrix_cache", {})
	var menu: Control = (load("res://scenes/settings/camera_menu.gd") as GDScript).new()
	add_child(menu)
	await process_frame
	menu.call("open_menu")
	var rows: Array = menu.get("_rows")
	check(rows.size() == 2, "G 前置：设备列表 2 行")
	# G1 未选=中性灰（批次 AB-3：浅档 G2/G4 断言随机制删除退役，深档值原样保留）
	var dd: Color = menu.get("DARK_FONT_DIM")
	check(absf(dd.r - dd.g) < 0.02 and absf(dd.g - dd.b) < 0.02,
		"G1: 未选字色为中性灰（红：旧 (0.72,0.66,0.55) 暖灰致弱对比；实测 %s）" % dd)
	check(menu.get("LIGHT_FONT_DIM") == null and menu.get("LIGHT_FONT_SEL") == null,
		"AB-3 反向锁: LIGHT_FONT_DIM/LIGHT_FONT_SEL 浅档常量退役（无复辟）")
	# G3 选中亮米白保留（回归锚）
	check((menu.get("DARK_FONT_SEL") as Color).is_equal_approx(Color(1, 0.95, 0.8)),
		"G3: 选中亮米白保留（回归锚，深档唯一真值）")
	# G5 live 恒深档：选中行/未选行字色实刷（金棕底 StyleBox 保留由 test_v_camera_menu 承接）
	if rows.size() == 2:
		var sel_c: Color = (rows[0] as Button).get_theme_color("font_color")
		var dim_c: Color = (rows[1] as Button).get_theme_color("font_color")
		check(sel_c.is_equal_approx(menu.get("DARK_FONT_SEL")),
			"AB-3 等价改写: 选中行 live 字色==DARK_FONT_SEL（实测 %s）" % sel_c)
		check(dim_c.is_equal_approx(menu.get("DARK_FONT_DIM")),
			"AB-3 等价改写: 未选行 live 字色==DARK_FONT_DIM 中性灰（实测 %s）" % dim_c)
		# G7 底色对比：选中行保留金棕淡底（回归锚——「变细」错觉的另一半修复面）
		check((rows[0] as Button).has_theme_stylebox_override("normal"),
			"G7: 选中行金棕底 override 在场（回归锚）")
	menu.call("_close_subs")
	menu.free()
	bridge.set("_camera_enum", {})
	bridge.set("_camera_matrix", {})
	bridge.set("_camera_errors", [])
	bridge.set("_probe_matrix_cache", {})
	await process_frame
