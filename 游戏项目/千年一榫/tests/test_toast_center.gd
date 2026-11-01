extends "res://tests/test_base.gd"
## K-C（KC-2）判定用例：ToastCenter 右上角可堆叠通知契约无头测试（TDD 先写）。
## 契约来源：spec §6.3 / plan KC-2 接口定稿（跨批契约，K-D 商店失败通知 / K-G 关卡对接失败复用）：
##   class_name ToastCenter extends VBoxContainer；
##   push(text, level="warn", seconds=2.5)——level "info"(金)/"warn"(红)/"ok"(绿)，只换卡片描边与文字色；
##   clear_all()。挂点 main.tscn/GlobalUI/ToastCenter，节点声明序排 WindowButtons/SettingsButton 之前
##   （同层 Control 后挂者绘制在上，toast 永垫右上功能区之下）；卡片= L3 圆角 14 最小宽 220+「×」钮；
##   堆叠上限 5 超出顶掉最旧；seconds 后自动移除（默认 2.5，计时移除不无头等待）。
## Game 侧：attach_toast(center) 注入 + toast(text, level, seconds) 转发；未注入 push_warning 静默降级。
## P2-5 纪律：新增组件断言一律 load() 比较 script / has_method / call()，不引用全局类名（plan §0.1）。

const TC_SCRIPT := "res://scenes/shared/toast_center.gd"
const SPY_SCRIPT := "res://tests/fixtures/toast_spy.gd"
const INFO_COLOR := Color(1.0, 0.85, 0.4)
const WARN_COLOR := Color(1.0, 0.45, 0.35)
const OK_COLOR := Color(0.4, 0.9, 0.5)

func _card_border(card: Control) -> Color:
	var sb: StyleBoxFlat = card.get_theme_stylebox("panel") as StyleBoxFlat
	return sb.border_color if sb != null else Color()

func _initialize() -> void:
	print("== test_toast_center ==")
	var script: Variant = load(TC_SCRIPT)
	check(script != null, "KC-2：toast_center.gd 可加载")
	if script == null:
		finish()
		return

	# ---- 1. 契约方法齐备（load()+has_method，P2-5） ----
	var tc: Node = (script as GDScript).new()
	add_child(tc)
	await process_frame  # --script 实证：_initialize 同步段内 root.add_child 后 get_tree() 暂为 null，
	                     # 须放行一帧（同 test_window_k window_buttons 惯例）；否则 push 内 create_timer 报错
	check(tc.has_method("push") and tc.has_method("clear_all"), "KC-2：push/clear_all 契约方法齐备")
	check(tc is VBoxContainer, "KC-2：根为 VBoxContainer（纵排堆叠）")

	# ---- 2. push 一条 → 子节点 +1，卡片三层结构（card→row→[Label,×钮]） ----
	tc.call("push", "无法对接")
	check_eq(tc.get_child_count(), 1, "KC-2：push 一条 → child_count==1")
	var card: Control = tc.get_child(0) as Control
	check(card is PanelContainer, "KC-2：卡片为 PanelContainer（L3 样式载体）")
	var row: Node = card.get_child(0)
	check(row is HBoxContainer and row.get_child_count() == 2, "KC-2：card→row(HBox)→[Label, ×钮] 三层路径")
	check((row.get_child(1) as Button).text == "×", "KC-2：× 关闭钮存在")
	check_eq(card.custom_minimum_size.x, 220.0, "KC-2：卡片最小宽 220")

	# ---- 3. 三色语义：只换描边与文字色 ----
	var lbl: Label = row.get_child(0) as Label
	check_eq(_card_border(card), WARN_COLOR, "KC-2：默认 warn 描边红 Color(1.0,0.45,0.35)")
	check_eq(lbl.get_theme_color("font_color"), WARN_COLOR, "KC-2：默认 warn 文字红")
	tc.call("push", "提示", "info")
	check_eq(_card_border(tc.get_child(tc.get_child_count() - 1) as Control), INFO_COLOR, "KC-2：info 描边金")
	tc.call("push", "成功", "ok")
	check_eq(_card_border(tc.get_child(tc.get_child_count() - 1) as Control), OK_COLOR, "KC-2：ok 描边绿")
	var sb: StyleBoxFlat = card.get_theme_stylebox("panel") as StyleBoxFlat
	check(sb != null and sb.corner_radius_top_left == 14, "KC-2：toast 卡片圆角 14（L3 弹窗档）")

	# ---- 4. 堆叠上限：连 push 至 6 条 → child_count ≤ 5（超出顶掉最旧） ----
	while tc.get_child_count() >= 1:
		tc.call("clear_all")
	for i: int in range(6):
		tc.call("push", "堆叠 %d" % i)
	check(tc.get_child_count() <= 5, "KC-2：连 push 6 条 → 同屏 ≤5（顶掉最旧）")
	check_eq(String((tc.get_child(tc.get_child_count() - 1).get_child(0).get_child(0) as Label).text), "堆叠 5", "KC-2：被顶掉的是最旧而非最新")

	# ---- 5. × 钮点击 → 该卡片移除 ----
	var last_card: Control = tc.get_child(tc.get_child_count() - 1) as Control
	var cnt_before: int = tc.get_child_count()
	(last_card.get_child(0).get_child(1) as Button).pressed.emit()
	check_eq(tc.get_child_count(), cnt_before - 1, "KC-2：× 按下 → 卡片移除")

	# ---- 6. clear_all → 0 ----
	tc.call("clear_all")
	check_eq(tc.get_child_count(), 0, "KC-2：clear_all 清空全部")

	# ---- 6b. 中央锚点盒退役（批次V规格§3.4 等价替换留痕，V-C6）：中央路由单点归 TopStrip
	#（Game.toast centered=true 单点改道，V-C1 落地）→ ToastCenter 收窄右上堆叠专用——中央盒
	# 源码/懒创建路径删除、几何常量单源迁 top_strip.gd 勿双写；push/clear_all 公开 API 不变，
	# centered=true 直推（未挂 strip 的降级路径）落右上队列。 ----
	var tc_src_v: String = FileAccess.get_file_as_string(TC_SCRIPT)
	check(not tc_src_v.contains("_ensure_center_box") and not tc_src_v.contains("CENTER_TOP")
		and not tc_src_v.contains("ToastCenterTop"),
		"批次V§3.4：toast_center.gd 中央锚点盒源码级退役（_ensure_center_box/CENTER_TOP/ToastCenterTop 零残留）")
	tc.call("push", "降级中央直推", "warn", 60.0, true)
	check_eq(tc.get_child_count(), 1, "批次V§3.4：push(centered=true) 直推 → 卡片落右上队列（中央盒退役后降级路径）")
	check(tc.get_parent().get_node_or_null("ToastCenterTop") == null,
		"批次V§3.4：父层无 ToastCenterTop 中央锚点盒节点（懒创建路径已删）")
	tc.call("clear_all")
	check_eq(tc.get_child_count(), 0, "批次V§3.4：clear_all 清空（API 语义保持）")

	# ---- 7. main.tscn 挂点与节点声明序（toast 垫右上功能区之下） ----
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	check(main_scene != null, "KC-2：main.tscn 可加载")
	if main_scene != null:
		var mj: Node = main_scene.instantiate()  # 不入树（_ready 不触发）
		var gui: Node = mj.get_node_or_null("GlobalUI")
		var toast_idx: int = -1
		var settings_idx: int = -1
		var wb_idx: int = -1
		if gui != null:
			for i: int in range(gui.get_child_count()):
				match String(gui.get_child(i).name):
					"ToastCenter": toast_idx = i
					"SettingsButton": settings_idx = i
					"WindowButtons": wb_idx = i
		check(toast_idx >= 0 and (mj.get_node("GlobalUI/ToastCenter") as Node).get_script() == script, "KC-2：GlobalUI/ToastCenter 存在且挂 toast_center.gd")
		# 审查 P1-2 回修防回归：容器本体必须 IGNORE——328×364 常驻区不得吞图鉴右列点击、
		# 不得被拖窗命中排除误判（子卡片/×钮各自默认 STOP，通知可交互不受影响）。
		check(toast_idx >= 0 and (mj.get_node("GlobalUI/ToastCenter") as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"P1-2：ToastCenter mouse_filter=IGNORE（常驻区穿透，卡片各自 STOP）")
		check(toast_idx >= 0 and settings_idx >= 0 and wb_idx >= 0 and toast_idx < settings_idx and toast_idx < wb_idx, "KC-2：ToastCenter 声明序排 SettingsButton/WindowButtons 之前（永垫功能区之下）")
		mj.free()

	# ---- 8. Game 注入/降级链路（独立实例，不碰 autoload 本体） ----
	var game: Node = load("res://autoload/game.gd").new()
	add_child(game)
	check(game.has_method("attach_toast") and game.has_method("toast"), "KC-2：Game.attach_toast/toast 契约方法齐备")
	game.call("toast", "降级测试", "warn", 1.0)  # 未注入 → push_warning 静默降级不崩
	check(true, "KC-2：未 attach toast 不崩溃（降级 push_warning）")
	var spy: Node = load(SPY_SCRIPT).new()
	game.call("attach_toast", spy)
	game.call("toast", "无法对接", "warn", 2.5)
	var calls: Array = spy.call("get_calls")
	check_eq(calls.size(), 1, "KC-2：attach spy 后 Game.toast 转发恰 1 次")
	if calls.size() == 1:
		check_eq(String(calls[0][0]), "无法对接", "KC-2：spy 收到原文案")
		check_eq(String(calls[0][1]), "warn", "KC-2：spy 收到 level")
		check_eq(float(calls[0][2]), 2.5, "KC-2：spy 收到 seconds")
	game.free()
	spy.free()

	finish()
