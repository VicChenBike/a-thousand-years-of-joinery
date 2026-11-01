extends "res://tests/test_base.gd"
## 批次 V（V-C1，spec §3.1/§3.2/§3.4/§10/§14）判定用例：TopStrip 全局统一弹条（TDD 先写）。
## 契约：
##   scenes/shared/top_strip.gd（class_name TopStrip extends PanelContainer，纯代码构建、无 .tscn）；
##   push_info(text, seconds=3.0)——info 模式：文本+自动消失，无按钮；
##   push_confirm(text, on_confirmed, on_canceled=Callable())——confirm 模式：常驻直至用户选择，
##     内嵌「确认」「取消」两钮 + 右上「×」钮；× 与「取消」等价、零副作用（不调 on_confirmed）；
##   signal confirmed / canceled（供测试断言）；
##   单槽策略（confirm 优先）：confirm 活动期新 info 入单槽队列（批次 Z Z6-P2-10 等价改写——
##     旧「直接丢弃」废止：confirm 收起后补播最新一条；**显示期间条文案零扰动，A7 断言原文保持**）；
##     新 confirm 替换旧 confirm（旧回调不执行）；info 活动期新 confirm 顶掉 info；info 到时自灭释放槽位；
##   主题：显式注入 ThemeManager.current_theme() 并随 theme_changed 重刷（CanvasLayer 无 theme，
##     §14 坑 6）；棕主题弹窗档 GlassDialog L3 同族（深 0.30,0.22,0.09,0.72 / 浅 0.99,0.92,0.72,0.75，圆角 14）；
##   几何：复用 toast_center 中央锚点盒口径——anchor 左右 0.5 水平居中、offset_top=70、grow 双向；
##     条宽随内容 min 320、max=视口宽−2×14（autowrap）；
##   挂载（P0-1）：main.gd 代码建独立 CanvasLayer layer=63（禁挂 GlobalUI——open_overlay 后加树序
##     会遮条=V8 病灶同源）+ Game.attach_strip(strip) 接线；
##   路由（§3.4 裁决）：Game.toast(centered=true) 单点改道 strip.push_info；centered=false 或未挂接
##     维持右上原路径（ToastCenter）零变化。
## P2-5 纪律：load() 比较 script / has_method / call()，不引用全局类名；
## 坑 5：--script 无头 add_child 后 await process_frame；坑 1/2：回调判 is_valid、无字典下标裸取。

const TS_SCRIPT := "res://scenes/shared/top_strip.gd"
const MAIN_SCENE := "res://scenes/main.tscn"
const GAME_SCRIPT := "res://autoload/game.gd"
const SPY_SCRIPT := "res://tests/fixtures/toast_spy.gd"
const LINKER_SHADER := "res://assets/shaders/ui_material.gdshader"
const DARK_BG := Color(0.30, 0.22, 0.09, 0.72)   # spec §3.1：GlassDialog L3 弹窗档深色底
# 批次 AB-3：LIGHT_BG 浅档测试常量随深浅主题机制删除退役（生产 LIGHT_BG 同步退役）。
const TOP_OFFSET := 70.0     # 中央盒顶（toast_center.CENTER_TOP 同值，几何单源迁入 top_strip.gd）
const MARGIN := 14.0         # 视口左右安全边距（spec §3.1 max=视口宽−2×14）
const MIN_WIDTH := 320.0     # 条最小宽（spec §3.1）

## 内联夹具：TopStrip 替身（记录 push_info 调用参数；Game.attach_strip 注入链路验证用）
class StripSpy extends Node:
	var calls: Array = []
	func push_info(text: String, seconds: float = 3.0) -> void:
		calls.append([text, seconds])

var _ok_count := 0
var _cancel_count := 0
var _confirmed_sig := 0
var _canceled_sig := 0

func _reset_counters() -> void:
	_ok_count = 0; _cancel_count = 0; _confirmed_sig = 0; _canceled_sig = 0

func _push_counted(strip: Node, text: String) -> void:
	strip.call("push_confirm", text,
		func() -> void: _ok_count += 1,
		func() -> void: _cancel_count += 1)

func _initialize() -> void:
	print("== test_v_top_strip ==")
	var script: Variant = load(TS_SCRIPT)
	check(script != null, "V-C1：top_strip.gd 可加载")
	if script == null:
		finish()
		return

	# ---- A1. 契约形态：根为 PanelContainer、双 push 方法 + confirmed/canceled 信号齐备 ----
	var strip: Node = (script as GDScript).new()
	check(strip is PanelContainer, "V-C1：根为 PanelContainer（弹窗档样式载体）")
	check(strip.has_method("push_info") and strip.has_method("push_confirm"),
		"V-C1：push_info/push_confirm 双模式契约方法齐备")
	check(strip.has_signal("confirmed") and strip.has_signal("canceled"),
		"V-C1：confirmed/canceled 两信号齐备")
	add_child(strip)
	await process_frame
	await process_frame  # 坑 5：无头 _initialize 期 add_child 后放行帧（主题/树时序）

	# ---- A2. info 模式：显示、无按钮、几何顶部居中（顶 70 / 中线 576 / min 宽 320） ----
	strip.call("push_info", "手势交互需要摄像头，无法关闭")
	check_eq(strip.visible, true, "V-C1：push_info 后弹条可见")
	await process_frame  # 布局放行一帧再读几何（min-size 展开时序）
	await create_timer(0.5).timeout  # 批次 W（N2）等价改写：入场改为 0.25s 滑入动效——几何终值断言前放行动效时长（断言本体零变化）
	var row: Node = strip.get_node_or_null("Row")
	var btn_row: Node = strip.get_node_or_null("Row/BtnRow")
	var lbl: Label = strip.get_node_or_null("Row/MsgLabel") as Label
	check(row != null and lbl != null and btn_row != null, "V-C1：Row→[MsgLabel, BtnRow] 结构齐备")
	check_eq(String(lbl.text), "手势交互需要摄像头，无法关闭", "V-C1：info 文案写入")
	check_eq(btn_row.visible, false, "V-C1：info 模式无按钮（BtnRow 隐藏）")
	check_eq(float(strip.get("offset_top")), TOP_OFFSET, "V-C1：几何 offset_top=70（toast_center 中央盒口径单源）")
	check(strip.size.x >= MIN_WIDTH, "V-C1：条宽 ≥ min 320")
	var vp_w: float = strip.get_viewport_rect().size.x
	var center_x: float = strip.global_position.x + strip.size.x * 0.5
	check(absf(center_x - vp_w * 0.5) <= 1.0, "V-C1：条水平居中（anchor 0.5 + grow 双向）")
	check(absf(strip.global_position.y - TOP_OFFSET) <= 1.0, "V-C1：条顶 ≈70（设计视口 y）")

	# ---- A3. info 到时自动收起、槽位释放（真实时钟短秒数） ----
	strip.call("push_info", "临时条", 0.3)
	await create_timer(0.7).timeout
	check_eq(strip.visible, false, "V-C1：info 到时自动收起（seconds 生效）")
	strip.call("push_confirm", "释放后可再弹")
	check_eq(strip.visible, true, "V-C1：info 自灭后槽位释放——push_confirm 可再弹")

	# ---- A4. confirm 模式常驻 + 内嵌三按钮（确认/取消/×） ----
	strip.call("push_confirm", "退出《千年一榫》？")
	check_eq(strip.visible, true, "V-C1：push_confirm 后弹条可见")
	check_eq(btn_row.visible, true, "V-C1：confirm 模式按钮行可见")
	var ok_btn: Button = strip.get_node_or_null("Row/BtnRow/OkButton") as Button
	var cancel_btn: Button = strip.get_node_or_null("Row/BtnRow/CancelButton") as Button
	var close_btn: Button = strip.get_node_or_null("Row/CloseButton") as Button  # 批次 W（N1）等价改写：× 移到条标题行常显（旧 Row/BtnRow/CloseButton 路径随 × 迁址失效留痕；文案/回调语义零变化）
	check(ok_btn != null and cancel_btn != null and close_btn != null, "V-C1：确认/取消/× 三钮齐备")
	check_eq(String(ok_btn.text), "确认", "V-C1：确认钮文案")
	check_eq(String(cancel_btn.text), "取消", "V-C1：取消钮文案")
	check_eq(String(close_btn.text), "×", "V-C1：右上 × 关闭钮文案")
	await create_timer(0.7).timeout
	check_eq(strip.visible, true, "V-C1：confirm 常驻——超时（0.7s）不自动收起")

	# ---- A5. 三按钮回调语义：确认→on_confirmed+收起；取消/×→on_canceled（等价、零副作用） ----
	_reset_counters()
	strip.connect("confirmed", func() -> void: _confirmed_sig += 1)
	strip.connect("canceled", func() -> void: _canceled_sig += 1)
	_push_counted(strip, "选择一")
	ok_btn.pressed.emit()
	check(_ok_count == 1 and _cancel_count == 0, "V-C1：确认→on_confirmed 恰 1 次、on_canceled 零调用")
	check(_confirmed_sig == 1 and _canceled_sig == 0, "V-C1：确认→confirmed 信号、canceled 不发")
	check_eq(strip.visible, false, "V-C1：确认后收起")
	_reset_counters()
	_push_counted(strip, "选择二")
	cancel_btn.pressed.emit()
	check(_cancel_count == 1 and _ok_count == 0, "V-C1：取消→on_canceled 恰 1 次、on_confirmed 零调用（零副作用）")
	check(_canceled_sig == 1, "V-C1：取消→canceled 信号")
	_reset_counters()
	_push_counted(strip, "选择三")
	close_btn.pressed.emit()
	check(_cancel_count == 1 and _ok_count == 0, "V-C1：× 与取消等价→on_canceled、on_confirmed 恒零（零副作用）")
	check_eq(strip.visible, false, "V-C1：× 后收起")

	# ---- A6. 空回调静默收起（Callable() 缺省，坑 1 强转防御） ----
	strip.call("push_confirm", "静默条")
	close_btn.pressed.emit()
	check(true, "V-C1：空回调 × 收起零异常（静默收起）")
	check_eq(strip.visible, false, "V-C1：空回调后收起")

	# ---- A7. 单槽策略（confirm 优先） ----
	_reset_counters()
	_push_counted(strip, "旧确认")
	strip.call("push_info", "挤不进的信息")
	check_eq(String(lbl.text), "旧确认", "V-C1：confirm 活动期新 info 丢弃（文案不被顶掉）")
	check_eq(btn_row.visible, true, "V-C1：confirm 活动期按钮行保持（confirm 常驻不被 info 干扰）")
	check(_ok_count == 0 and _cancel_count == 0, "V-C1：info 丢弃不触发任何回调")
	_push_counted(strip, "新确认")
	check_eq(String(lbl.text), "新确认", "V-C1：新 confirm 替换旧 confirm")
	# 批次 W（P2-7）等价改写：批次 V spec §3.1「旧回调不执行」顶替语义被推翻——新 confirm
	# 顶替时旧 on_canceled 恰一次补调（恢复挂起状态统一闭环）、旧 on_confirmed 恒不执行。
	check(_ok_count == 0 and _cancel_count == 1,
		"P2-7 等价改写：旧 confirm 被顶替 → 旧 on_canceled 恰一次补调、旧 on_confirmed 零调用")
	close_btn.pressed.emit()
	check(_cancel_count == 2 and _ok_count == 0, "P2-7：替换后仅新条回调生效（×→新 on_canceled 恰一次，累计=旧补调1+新1）")
	_reset_counters()
	strip.call("push_info", "临时 info")
	_push_counted(strip, "顶掉 info")
	check_eq(String(lbl.text), "顶掉 info", "V-C1：info 活动期新 confirm 顶掉 info（confirm 优先）")
	close_btn.pressed.emit()
	check(_cancel_count == 1, "V-C1：顶掉 info 的 confirm 回调语义正常")

	# ---- A7b. 批次 W（P2-7）新段：顶替补调幂等守卫（同帧重入不双重补调）----
	# 场景=level_scene._pending_exit_state 闭合语义：旧 cancel 内清挂起标志；若旧 cancel 链内
	# 同帧重入 push_confirm/dismiss_active_confirm/_on_game_state_changed，槽已先清 → 不双重补调。
	_reset_counters()
	var pending_flag: Dictionary = {"exit_pending": true}
	var old_cancel_calls: Array = []
	var reentrant_cb: Callable = func() -> void:
		old_cancel_calls.append(true)
		pending_flag["exit_pending"] = false
		strip.call("push_confirm", "重入条")   # 旧 cancel 链内重入推新条（极端路径）
	strip.call("push_confirm", "外层确认", Callable(), reentrant_cb)
	_reset_counters()
	_push_counted(strip, "顶替条")
	check_eq(old_cancel_calls.size(), 1, "P2-7：重入型旧 cancel 恰一次补调（链内 push_confirm 不双重补调）")
	check_eq(bool(pending_flag["exit_pending"]), false, "P2-7：挂起状态标志经补调统一闭合（_pending_exit_state 泄漏根除）")
	close_btn.pressed.emit()
	check(_cancel_count == 1, "P2-7：重入链后的顶替条自身回调恰一次")
	_reset_counters()
	# 同帧 dismiss_active_confirm 重入：顶替时旧 cancel 内 dismiss → 不得二次补调
	var dismiss_calls: Array = []
	var dismiss_cb: Callable = func() -> void:
		dismiss_calls.append(true)
		strip.call("dismiss_active_confirm")
	strip.call("push_confirm", "dismiss 前条", Callable(), dismiss_cb)
	dismiss_calls.clear()
	_push_counted(strip, "dismiss 顶替条")
	check_eq(dismiss_calls.size(), 1, "P2-7：dismiss 链内旧 cancel 恰一次（幂等守卫）")
	close_btn.pressed.emit()
	check(_cancel_count == 1 and _ok_count == 0, "P2-7：dismiss 顶替条回调语义正常（×→on_canceled）")

	# ---- A8. 主题注入：theme 非空 + 恒深色 + L3 弹窗档样式（批次 AB-3：切换更新断言退役）----
	strip.call("push_info", "主题条")
	check(strip.theme != null, "V-C1：条根 theme 非空（CanvasLayer 层界显式注入，坑 6）")
	var tm: Node = get_root().get_node("ThemeManager")
	check(strip.theme == tm.current_theme(), "V-C1：theme==ThemeManager.current_theme()（恒深色主题）")
	check(not tm.has_signal("theme_changed"),
		"AB-3 反向锁：无 theme_changed 信号（旧「订阅重刷」断言随深浅主题机制删除退役）")
	var sb: StyleBoxFlat = strip.get_theme_stylebox("panel") as StyleBoxFlat
	check(sb != null, "V-C1：根挂 panel StyleBoxFlat（弹窗档）")
	if sb != null:
		check(sb.corner_radius_top_left == 14, "V-C1：弹条圆角 14（L3 弹窗档）")
		check(sb.bg_color.is_equal_approx(DARK_BG), "AB-3：底色恒 GlassDialog L3 深档（浅色档随机制删除）")
	var dark_bg: Color = strip.DARK_BG
	check(dark_bg.is_equal_approx(DARK_BG),
		"AB-3 等价改写：DARK_BG 常量与 spec §3.1 L3 深档值一致（LIGHT_BG 浅档退役）")
	var ts_const: Dictionary = (strip.get_script() as Script).get_script_constant_map()
	check(not ts_const.has("LIGHT_BG") and not ts_const.has("LIGHT_BORDER") and not ts_const.has("LIGHT_FONT"),
		"AB-3 反向锁：top_strip LIGHT_BG/LIGHT_BORDER/LIGHT_FONT 浅档常量退役（无复辟）")

	# ---- A9. 材质/光效挂点：ui_material meta + 按钮 hover_glow 目标集合 ----
	check(strip.has_meta("ui_material") and str(strip.get_meta("ui_material")) == "panel",
		"V-C1：条本体 set_meta(ui_material, panel)——UILightLinker 面板档识别挂点")
	var wm: Variant = load("res://scripts/window_manager.gd")
	check(bool(wm.is_glow_target(ok_btn)) and bool(wm.is_glow_target(cancel_btn)),
		"V-C1：确认/取消钮在 hover_glow 目标集合（悬浮光效体系自动覆盖 Button）")

	# ---- A10. 长文本钳制：max=视口宽−2×14（autowrap） ----
	strip.call("push_info", "X".repeat(600))
	await process_frame
	await process_frame
	check(strip.size.x <= vp_w - MARGIN * 2.0 + 1.0, "V-C1：长文本条宽 ≤ 视口宽−2×14（半宽钳制）")
	check_eq(strip.visible, true, "V-C1：长文本条仍显示（autowrap 折行）")
	strip.call("push_info", "收尾", 0.1)
	await create_timer(0.4).timeout

	# ---- A11. 批次 V 走查回修 NG-2：confirm 条内容自适应宽 + 按钮不纵向膨胀（5 checks） ----
	# 走查 w08 实证：confirm 条宽停在 MIN_WIDTH=320，autowrap MsgLabel 被按钮行挤成 ≈60px
	# 一字一行、按钮垂直 FILL 膨胀 ≈330px 高（高瘦块）。修复口径：①条宽按内容扩展（文案所需
	# 宽+按钮行宽 与 MIN_WIDTH 取大、视口宽−2×MARGIN 取小，_clamp_width 同口径）；②按钮
	# SHRINK_CENTER + MsgLabel 最小宽保障。断言带注记：本项目主题 Button font_size=22+
	# stylebox 上下 margin 10 → 基础最小高实测 53px，故「不拉伸」带取 [36,60] 并加
	# 「高度==自身最小高±0.5」强断言（coord 提示的 [36,48] 带与本项目主题真实档位不符，偏差备案）。
	var confirm_text := "摄像头关闭后，下次开启手势交互需要重新等待数秒启动。"
	strip.call("push_confirm", confirm_text)
	await process_frame
	await process_frame
	check(strip.size.x > 360.0, "NG-2：confirm 长文案条宽 >360 内容自适应（实测 %.1f）" % strip.size.x)
	check(lbl.size.x >= 200.0, "NG-2：confirm MsgLabel 宽 ≥200 不被按钮行挤窄（实测 %.1f）" % lbl.size.x)
	var ok_h: float = ok_btn.size.y
	check(ok_h >= 36.0 and ok_h <= 60.0 and absf(ok_h - ok_btn.get_combined_minimum_size().y) <= 0.5,
		"NG-2：确认钮高度∈[36,60] 且==自身最小高不纵向膨胀（实测 %.1f，min %.1f）" % [ok_h, ok_btn.get_combined_minimum_size().y])
	check(cancel_btn.size.y >= 36.0 and cancel_btn.size.y <= 60.0,
		"NG-2：取消钮高度∈[36,60]（实测 %.1f）" % cancel_btn.size.y)
	check(String(lbl.text) == confirm_text, "NG-2：confirm 长文案逐字写入（%d 字）" % confirm_text.length())
	close_btn.pressed.emit()
	await process_frame
	check_eq(strip.visible, false, "NG-2：confirm 布局断言后 × 收起（槽位复位零残留）")

	# ---- B. main.gd 挂载接线（P0-1 层归属：独立层 63、父链不在 GlobalUI） ----
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(main)
	await process_frame
	await process_frame
	var strip_layer: CanvasLayer = main.get_node_or_null("TopStripLayer") as CanvasLayer
	check(strip_layer != null, "V-C1：main 挂载 TopStripLayer（CanvasLayer 代码创建）")
	check(strip_layer != null and strip_layer.layer == 63,
		"V-C1：TopStripLayer layer=63（高于 GlobalUI=1、低于 GestureHUDLayer=64/CameraMenuLayer=65）")
	var strip_in_main: Node = main.get_node_or_null("TopStripLayer/TopStrip")
	check(strip_in_main != null and strip_in_main.get_script() == load(TS_SCRIPT),
		"V-C1：TopStripLayer/TopStrip 挂 top_strip.gd（script 比较，P2-5）")
	var under_global := false
	if strip_in_main != null:
		var anc: Node = strip_in_main
		while anc != null:
			if anc == main.get_node("GlobalUI"):
				under_global = true
			anc = anc.get_parent()
	check(not under_global, "V-C1：条父链不在 GlobalUI 下（V8 病灶同源根除——overlay 后加树序不可遮条）")
	var game_node: Node = get_root().get_node("Game")
	check(game_node != null and game_node.has_method("attach_strip"), "V-C1：Game.attach_strip 注册 API 齐备")
	check(game_node != null and game_node.get("_strip") == strip_in_main,
		"V-C1：Game.attach_strip 接线生效（autoload _strip==条实例）")
	check(main.get_node_or_null("GlobalUI/ToastCenter") != null,
		"V-C1：与 ToastCenter 右上队列并存不互斥（原节点保留）")
	check(strip_in_main != null and strip_in_main.theme != null,
		"V-C1：入树条 theme 非空（挂载即显式赋主题）")

	# ---- B2. Game.toast 中央改道（autoload 真身）：centered=true 走条、false 走右上原路 ----
	var tc: Node = main.get_node("GlobalUI/ToastCenter")
	var tc_cnt: int = tc.get_child_count()
	game_node.call("toast", "中央改道条", "warn", 60.0, true)
	check(strip_in_main != null and strip_in_main.visible and String((strip_in_main.get_node("Row/MsgLabel") as Label).text) == "中央改道条",
		"V-C1：Game.toast(centered=true)→TopStrip.push_info 改道生效")
	check_eq(tc.get_child_count(), tc_cnt, "V-C1：改道时右上队列零新增（单点改道不双投）")
	game_node.call("toast", "右上原路", "warn", 60.0, false)
	check_eq(tc.get_child_count(), tc_cnt + 1, "V-C1：Game.toast(centered=false) 维持右上原路径")
	check(String((strip_in_main.get_node("Row/MsgLabel") as Label).text) == "中央改道条",
		"V-C1：右上路径不影响条内容（互不干扰）")

	# ---- B3. UILightLinker 动态挂材质（条/按钮同材质族） ----
	var mat: Material = strip_in_main.material as Material
	check(mat is ShaderMaterial and (mat as ShaderMaterial).shader != null \
		and (mat as ShaderMaterial).shader.resource_path == LINKER_SHADER,
		"V-C1：条本体经 UILightLinker 自动挂 ui_material（panel 档）")
	var ok_in_main: Button = strip_in_main.get_node("Row/BtnRow/OkButton") as Button
	var bmat: Material = ok_in_main.material as Material
	check(bmat is ShaderMaterial and (bmat as ShaderMaterial).shader != null \
		and (bmat as ShaderMaterial).shader.resource_path == LINKER_SHADER,
		"V-C1：内嵌按钮经 linker 动态挂 ui_material（按钮档，与全局按钮同族）")

	# ---- C. Game 改道契约（fresh 实例 + 双 spy，不碰 autoload 真身） ----
	var game: Node = (load(GAME_SCRIPT) as GDScript).new()
	add_child(game)
	var tsp: Node = (load(SPY_SCRIPT) as GDScript).new()
	add_child(tsp)
	var ssp: StripSpy = StripSpy.new()
	add_child(ssp)
	game.call("attach_toast", tsp)
	game.call("attach_strip", ssp)
	game.call("toast", "中央提示", "warn", 2.5, true)
	var s_calls: Array = ssp.calls
	check_eq(s_calls.size(), 1, "V-C1：attach_strip 后 Game.toast(centered=true) 改道 strip 恰 1 次")
	if s_calls.size() == 1:
		check_eq(String(s_calls[0][0]), "中央提示", "V-C1：改道条收到原文案")
		check_eq(float(s_calls[0][1]), 2.5, "V-C1：改道条收到 seconds（level 不透传，统一棕主题档）")
	check_eq((tsp.call("get_calls") as Array).size(), 0, "V-C1：改道时右上 ToastCenter 零转发（不双投）")
	game.call("toast", "右上提示", "warn", 2.5, false)
	check_eq((tsp.call("get_calls") as Array).size(), 1, "V-C1：centered=false 转发右上 ToastCenter")
	check_eq(ssp.calls.size(), 1, "V-C1：右上路径不进条")

	# ---- C2. 未挂接降级：维持右上原路径 / 全未挂接零异常 ----
	var game2: Node = (load(GAME_SCRIPT) as GDScript).new()
	add_child(game2)
	var tsp2: Node = (load(SPY_SCRIPT) as GDScript).new()
	add_child(tsp2)
	game2.call("attach_toast", tsp2)
	game2.call("toast", "降级中央", "warn", 1.0, true)   # 未 attach_strip → 右上原路径（降级判空模式）
	check_eq((tsp2.call("get_calls") as Array).size(), 1, "V-C1：未挂 strip 时 centered=true 维持右上原路径（降级）")
	var game3: Node = (load(GAME_SCRIPT) as GDScript).new()
	add_child(game3)
	game3.call("toast", "全降级", "warn", 1.0, true)
	check(true, "V-C1：全未挂接 toast 零异常（push_warning 静默降级）")

	game.queue_free()
	game2.queue_free()
	game3.queue_free()
	tsp.queue_free()
	tsp2.queue_free()
	ssp.queue_free()
	main.queue_free()
	strip.queue_free()
	await process_frame
	finish()
