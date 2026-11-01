class_name ToastCenter
extends VBoxContainer

# 批次 W（P3-1）：色彩单源表（值不变）。
const Palette := preload("res://scripts/palette.gd")
## K-C（K4-2）：右上角可堆叠 toast（spec §6.3，参考 CC Switch）。GlobalUI 挂点节点序
## 排 WindowButtons/SettingsButton 之前——同层 Control 后挂者绘制在上，toast 永垫其下。
## 跨批契约（plan KC-2 定稿，K-D/K-G 复用）：push(text, level="warn", seconds=2.5)/clear_all()；
## level "info"金/"warn"红/"ok"绿 只换卡片描边与文字色；卡片 L3 圆角 14 最小宽 220+「×」钮；
## 0.2s 淡入近似右侧浮入（spec 疑点 7）；seconds 后自动移除；堆叠上限 5 超出顶掉最旧。
## M-E 回修3 E：push 新增 centered 可选参数（中央锚点盒直推）——批次 V（V-C6，spec §3.4
## 中央 toast 口径统一裁决）中央锚点盒随本批退役：中央 toast 口径单点归 TopStrip（Game.toast
## centered=true → _strip.push_info 改道，game.gd V-C1 落地），几何常量单源迁 top_strip.gd
##（TOP_OFFSET=70，勿双写）。本组件收窄右上堆叠专用；centered=true 参数保留（公开 API 不变）
## 仅作降级直推语义——未挂 strip 时 Game.toast 降级路径仍达右上队列，不再创建任何中央锚点盒。
const MAX_VISIBLE := 5
const SLIDE_TIME := 0.25   # 批次 W（N2）：自上方滑入+淡入统一时长（0.2~0.3s 档）
const SLIDE_GAP := 14.0
const LEVEL_COLORS := {"info": Palette.HINT_GOLD_TOAST, "warn": Palette.TOAST_WARN_RED, "ok": Palette.TOAST_OK_GREEN}   # P3-1：提示金/红/绿单源（值不变）

func _ready() -> void:
	add_theme_constant_override("separation", 8)

func push(text: String, level: String = "warn", seconds: float = 2.5, centered: bool = false) -> void:
	# 批次 V（V-C6，spec §3.4）：centered 参数保留仅兼容既有调用签名——中央锚点盒已退役，
	# 直推右上队列（中央口径由 Game.toast→TopStrip 单点改道承担，见头注；原中央盒分流
	# 判定随中央盒一并删除）。
	var host: Container = self
	var color: Color = LEVEL_COLORS.get(level, LEVEL_COLORS["warn"])
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.30, 0.22, 0.09, 0.72)  # L3 深色底（spec §3.3）
	sb.set_corner_radius_all(14); sb.set_border_width_all(2); sb.border_color = color
	sb.shadow_color = Color(0, 0, 0, 0.45); sb.shadow_size = 16; sb.shadow_offset = Vector2(3, 5)
	sb.content_margin_left = 12.0; sb.content_margin_right = 8.0
	sb.content_margin_top = 8.0; sb.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", sb); card.custom_minimum_size = Vector2(220, 0)
	var row := HBoxContainer.new(); var lbl := Label.new()
	lbl.text = text; lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; lbl.add_theme_color_override("font_color", color)
	var close_btn := Button.new(); close_btn.text = "×"; close_btn.focus_mode = Control.FOCUS_NONE
	row.add_child(lbl); row.add_child(close_btn)
	card.add_child(row); host.add_child(card)
	# 批次 W3 回修 P1-1（审查实锤+探针逐帧实证）：滑入动效必须「排序落位后」再启动——VBox 对
	# add_child 的排序是 deferred 且**排在本组件 call_deferred 之后**（探针 f0：起点写后被
	# fit_child_in_rect 拉回叠放位 55.00 → position:y tween 初始采样=终值 → final→final 空转，
	# 只剩淡入=W3 首版假绿）。故：①modulate.a=0 同步写（排序当帧即不可见，防首帧在终位闪现）；
	# ②动效装置 call_deferred 后**再等一帧**（排序已落位）读终值/写起点/建 tween；子件纯位置
	# 改写不触发容器重排（Container 只在增删/尺寸变更时 queue_sort），滑入真实生效；终值=排序
	# 落位（叠放位）→ 终态与现状一致。
	card.modulate.a = 0.0
	_start_card_slide.call_deferred(card)
	while host.get_child_count() > MAX_VISIBLE:
		# 批次 W3 回修 P1-1 顺手项：逐出使余卡上移一行——先杀运行中的滑入 tween 再 remove_child，
		# 防陈旧终值在 kill 前回写把卡钉在错位（逐出后容器重排即拥有余卡正确落位）。
		_kill_slide_tweens()
		var oldest := host.get_child(0)
		host.remove_child(oldest); oldest.queue_free()
	close_btn.pressed.connect(func() -> void: _dismiss(card, host))
	get_tree().create_timer(seconds).timeout.connect(func() -> void: _dismiss(card, host))

## 批次 W3 回修 P1-1：滑入启动（deferred + 排序落位等待，见 push 内注释）。
func _start_card_slide(card: Control) -> void:
	await get_tree().process_frame   # 等排序落位（实测排序 deferred 于本装置之后执行）
	if not is_instance_valid(card) or not card.is_inside_tree() or card.get_parent() != self:
		return
	var final_y := card.position.y
	var h := maxf(card.size.y, card.get_combined_minimum_size().y)
	card.position.y = final_y - (h + SLIDE_GAP)
	var tw := card.create_tween(); tw.set_parallel(true)
	tw.tween_property(card, "position:y", final_y, SLIDE_TIME)
	tw.tween_property(card, "modulate:a", 1.0, SLIDE_TIME)
	card.set_meta("slide_tween", tw)   # 逐出/收起时 kill 句柄（P1-1 顺手项）

## 批次 W3 回修 P1-1：杀全体运行中滑入 tween（逐出/移除使余卡移位前调用，防陈旧终值回写错位）
func _kill_slide_tweens() -> void:
	for c: Node in get_children():
		if c is Control and (c as Control).has_meta("slide_tween"):
			var tw: Tween = (c as Control).get_meta("slide_tween")
			if tw != null and tw.is_valid():
				tw.kill()
func _dismiss(card: Control, host: Container = null) -> void:
	var owner_box: Container = host if host != null else self
	if not is_instance_valid(card) or card.get_parent() != owner_box: return
	# 批次 W3 回修 P1-1：移除使余卡上移一行——先杀运行中滑入 tween（含被移除卡自身的），
	# 防陈旧终值回写错位；移除后容器重排拥有余卡正确落位。（现网 host 恒=self，本队列即宿主）
	if owner_box == self:
		_kill_slide_tweens()
	owner_box.remove_child(card); card.queue_free()
func clear_all() -> void:
	for child: Node in get_children():
		remove_child(child); child.queue_free()
