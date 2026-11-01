extends Control
## 主菜单。依据 spec 4.1 + 2026-08-26 用户 UI 修正指示（布局按设计稿 image8）
## + 批次 J3（C1 圆弧毛玻璃底衬+书法金黄标题；C2 按钮两态）
## + 批次 K-KC-3 主菜单修复（spec §6.1，K2-1~2-6/K4-1/K8）：
## 布局（M-B 修订，spec §3.2）：左侧竖向菜单区 LeftPanel（椭圆容器 EllipsePanel——面板档
##   材质 SDF 右半支半椭圆（左贴弧：弧心 (0,H/2)、ry=H/2 端点顶满上下角、rx=440），
##   标题+3 按钮绝对定位直挂（stacked_layout 垂直均匀居中+title_box 同轴，L-B 贴弧算法
##   已废止；K2-5 删左下手势提示面板，清单由全局 GestureHUD 承载）；
##   右侧大面积背景图区域。K2-6/Q3：左列去「设置」按钮——唯一入口=右上角 GlobalUI 常驻。
## 按钮两态（C2/J3-2）：无存档=「开始游戏」+「加载存档」(灰禁)；
##   有存档=「新游戏」(清档需确认)+「载入存档」（断点继续）。退出常驻。
## K4-1→批次V（V-C5，spec §3.2）：NewGameDialog/ExitDialog 节点退役——新游戏/退出两处确认
##   改经 Game.confirm → TopStrip 统一确认条（文案与确认/取消语义逐字保持；旧弹窗组件文件
##   本体保留不删，settle_scene 先例）。
##   K8：退出确认与窗口关闭按钮同流程（确认后 stop_gesture_process + quit）。
## 判据（批次V，spec §8.3）：按钮两态/载入兜底/开始动作统一读 SaveManager.has_any_progress()
##   三分支（flag∨watched_opening∨cleared，与图鉴门控同源）——弃 is_first_launch() 单判据，
##   存档有进度而 flag 丢失时「载入存档」不再灰禁、「开始游戏」不再绕过清档确认直重播开场
##  （「进度看着丢了」病灶修复+回修②P2-1 按钮/动作判据收口）。
## 背景固定为大厅背景图 bg_menu.png（2026-08-26 修正：不再随章节取关卡背景
##   get_background_path(ch)——现代/宋/元/明/石器图仅用于关卡内）。
## 右下左右手置信度显示区由全局手势 HUD（GestureHUDMount）负责，本场景不重复做、不遮挡。

const MENU_BG_PATH := "res://assets/backgrounds/bg_menu.png"

# ---- M-B（spec §3.2，拍板 #5/#7 硬约束，2026-09-07）椭圆几何重做 + 垂直均匀居中布局 ----
# 【M 批等价替换留痕】旧 L-B/L-D「贴弧布局」全废止：arc_layout 函数（弧心 (W-rx,H/2)、
# rx380/ry280、PAD_ARC/Y_TOP/Y_BOT_MARGIN、等 y 间隙 155/155 贴弧 x 坐标）已删除——
# ①形状不符（两端不顶满屏幕左上/左下角，m01 拍板 #5）；②三钮贴弧 x 排布「中间空一大块」
# （m01 拍板 #7 改垂直均匀居中）。新几何（拍板 #5）：半椭圆=右半支、弧心在面板左边缘
# (0, H/2)、ry=H/2（端点严格过 (0,0) 与 (0,648)）、rx=440（弧顶深度，暂定值走查微调）。
# 单一几何参数源（spec §1.4-1）：本处常量+meta 下发，面板材质 SDF（ui_light_linker）、
# 光晕椭圆掩码（window_manager）、布局校验（stacked_layout/角点预校验）三方消费同值；
# ry 运行时恒由容器实际高×0.5 推导（ELLIPSE_RY 仅为设计视口参考值，防窗口高变化失配）。
const ELLIPSE_RX := 440.0
const ELLIPSE_RY := 324.0   # =648/2 设计视口参考值；运行时 ry := 容器高×0.5（端点顶满上下角）
const BTN_W := 200.0        # 拍板 #7 加大（原 160）
const BTN_H := 56.0         # 拍板 #7 加大（原 52）
const COL_X_RATIO := 0.42   # 按钮列/标题水平中心 = 0.42*rx（椭圆视觉中轴，暂定值走查微调）
const BAND_TOP_RATIO := 0.32     # 三钮 y 带上缘 = H*0.32（暂定值）
const BAND_BOTTOM_RATIO := 0.78  # 三钮 y 带下缘 = H*0.78（暂定值）
const TITLE_BAND_GAP := 24.0     # 标题底边距带顶 ≥24px（spec §3.2-6）
const TITLE_FONT_MAX := 64       # 标题字号起步档（原 40；校验不过 4px 步降档，暂定值）
const TITLE_FONT_MIN := 24       # 降档下限（防御）
const TITLE_FONT_STEP := 4       # 降档步长（spec §3.2-6「校验即权威」）
const TITLE_OUTLINE_SIZE := 10   # 深墨棕描边宽（暂定值）
const TITLE_OUTLINE_COLOR := Color(0.102, 0.071, 0.031)  # 深墨棕（与 M-A 按钮文字色同源）
const ARC_COLOR_DARK := Color(0.30, 0.20, 0.10, 0.70)    # N5 深棕 70% 不透明（M-B 金褐 0.55/0.42/0.16 调深，N 批等价替换；α 语义=70% 实/30% 透出 bg_menu）
# 批次 AB-3：ARC_COLOR_LIGHT（浅档）随深浅主题机制删除退役，深档为唯一值。

@onready var start_btn: Button = $LeftPanel/StartButton
@onready var load_btn: Button = $LeftPanel/LoadButton
@onready var quit_btn: Button = $LeftPanel/QuitButton
@onready var title_label: Label = $LeftPanel/Title
@onready var left_panel: Control = $LeftPanel
@onready var ellipse_panel: Panel = $LeftPanel/EllipsePanel
@onready var bg: TextureRect = $Background

func _ready() -> void:
	# I18n：标题随语言切换（zh=「千年一榫」直通；en=「A Thousand Years of Joinery」，
	# 批次 AF 实机反馈②，与英文版 README 标题一致；长句由 _layout_title 几何权威制自动降档收纳）；
	# 退出钮为 tscn 静态文字，_ready 经 t() 覆写；language_changed → _refresh_texts 实时重刷按钮组。
	title_label.text = I18n.t("千年一榫")
	quit_btn.text = I18n.t("退出")
	start_btn.pressed.connect(_on_start)
	load_btn.pressed.connect(_on_load_save)
	quit_btn.pressed.connect(_on_quit)
	if not I18n.language_changed.is_connected(_refresh_texts):
		I18n.language_changed.connect(_refresh_texts)
	# 批次V（V-C5，spec §3.2）：两处确认文案收口到触发点（Game.confirm 调用处），语义逐字保持；
	# TODO(J3-2)：新游戏确认文案「新游戏将清除当前存档，确定重新开始吗？」为暂定占位，待用户确认正式文案（铁律不自行编定）。
	# 存档变化（通关推进等触发）时同步刷新按钮两态（C2/J3-2）
	SaveManager.progress_changed.connect(func() -> void: _update_buttons())
	# 批次 AB-3：深浅主题机制删除——theme_changed 订阅/回调退役，弧形底衬恒深档。
	_apply_background()
	_apply_arc_panel()
	# M-B：stacked_layout 垂直均匀居中布局——_ready/LeftPanel resized 两时点调用
	left_panel.resized.connect(_layout_menu_buttons)
	_layout_menu_buttons()
	_update_buttons()

func _apply_arc_panel() -> void:
	# L-B（spec §6.1 定稿）：StyleBox 置平（corner 0/shadow 0/border 0）——形状/AA/外投影全部
	# 由面板档材质 SDF 承担；仅保留半透明底色源（毛玻璃叠色基座）。
	var sb := StyleBoxFlat.new()
	sb.bg_color = ARC_COLOR_DARK
	ellipse_panel.add_theme_stylebox_override("panel", sb)
	ellipse_panel.set_meta("hover_glow", true)          # K9 判定链保留
	ellipse_panel.set_meta("ui_material", "panel")      # L-A 面板档材质挂载
	ellipse_panel.set_meta("glow_mask", "ellipse")      # L-C 容器档椭圆 SDF 掩码
	ellipse_panel.set_meta("glow_max", 0.30)            # L-C 容器区域档上限
	ellipse_panel.set_meta("ellipse_params", Vector2(ELLIPSE_RX, ELLIPSE_RY))  # 一处定参
	# L-D 走查定档（spec §14-11 档内 0.40/0.38→0.30/0.30）：截图实测退出钮 hover 与普通钮亮度差
	# 仅 ~14%（mean_dL 0.287 vs 0.332，L6-5「明显低于」不达）——根因是按钮材质第二点光不分级稀释
	# 了档位差（详见 LD 走查报告 NG 项）；先把可动的档位差拉满：0.75/0.30=2.5（档内封顶比），
	# 配合 §14-9/10 降点光能量后亮度差应扩大到 ~30%，退出钮不再与普通钮同亮。
	quit_btn.set_meta("glow_max", 0.30)                 # L-C 退出钮档（显式 meta，不做文本匹配）

func _apply_background() -> void:
	# 主菜单背景 = 大厅背景图（与存档进度/章节无关）；图片不存在时纯色兜底（隐藏 TextureRect，露主题底色）。
	if ResourceLoader.exists(MENU_BG_PATH):
		bg.texture = load(MENU_BG_PATH)
	else:
		bg.visible = false

func _update_buttons() -> void:
	# C2（J3-2）两态（Q&A12 单存档+自动保存）：
	#   无进度（flag/watched/cleared 三分支全空）=「开始游戏」亮 +「加载存档」灰禁用（tooltip「暂无存档」）；
	#   有进度 =「新游戏」（点击弹清档确认）+「载入存档」（断点继续），「开始游戏」文本消失。
	# 批次V（V-C5，spec §8.3）判据统一：读 has_any_progress()（与图鉴门控 can_open_catalog 同源
	# 三分支）——弃 is_first_launch() 单判据，存档有进度而 flag 丢失时不再灰禁「加载存档」。
	var has_save: bool = SaveManager.has_any_progress()
	if has_save:
		start_btn.text = I18n.t("新游戏")
		start_btn.disabled = false
		start_btn.tooltip_text = ""
		load_btn.text = I18n.t("载入存档")
		load_btn.disabled = false
		load_btn.tooltip_text = ""
	else:
		start_btn.text = I18n.t("开始游戏")
		start_btn.disabled = false
		start_btn.tooltip_text = ""
		load_btn.text = I18n.t("加载存档")
		load_btn.disabled = true
		load_btn.tooltip_text = I18n.t("暂无存档")

func _on_start() -> void:
	# 批次 V 回修② P2-1：动作判据与 _update_buttons 按钮判据同源收口 has_any_progress()——
	# 无进度（flag/watched/cleared 三分支全空）=首启流：创建标记+首次流程走开场动画（语义不变）；
	# 有进度（含 flag 丢失但有 watched/cleared 形态）=清档确认流——修旧 is_first_launch() 单判据
	# 在 flag 丢失态「点开始游戏不清档不确认直接重播开场」的按钮/动作分叉。
	if not SaveManager.has_any_progress():
		# 无存档态「开始游戏」：创建标记 + 首次流程走开场动画（语义不变）
		SaveManager.mark_first_launch()
		Game.goto_state(Game.State.OPENING_MOVIE)
		return
	# 有存档态「新游戏」：只弹清档确认防误触，确认前不清档不路由
	# 批次V（V-C5，spec §3.2）：统一确认条 Game.confirm 承载（文案逐字保持，确认=清档+进开场；
	# 取消/×缺省空回调=零副作用）。
	Game.confirm(I18n.t("新游戏将清除当前存档，确定重新开始吗？"), _on_new_game_confirmed)

func _on_new_game_confirmed() -> void:
	# C2（J3-2）确认后清档：数据回默认（含天赋 500）+ 删 first_launch 标记
	# （清档重走开场）→ 重建标记（P1-1 修：与首次流程「先 mark 再进动画」对称——新周目玩家
	# 已进入游戏，flag 缺失会使回主菜单判为无档：载入存档灰死、开始游戏重播开场硬回第1关）
	# → 路由 OPENING_MOVIE（新游戏=重新走开场动画）。
	SaveManager.reset_for_new_game()
	SaveManager.mark_first_launch()
	Game.goto_state(Game.State.OPENING_MOVIE)

func _on_load_save() -> void:
	# C2（J3-2）：断点继续语义由本按钮承接（原属「开始游戏」有档分支）——进入下一未通关
	# 章节；全通关则引导去图鉴。无进度时按钮已禁用，此处兜底不路由。
	# 批次V（V-C5，spec §8.3）：兜底判据与 _update_buttons 同源 has_any_progress()（判据统一，
	# 弃 is_first_launch() 单判据）。
	if not SaveManager.has_any_progress():
		return
	_resume_from_save()

func _resume_from_save() -> void:
	var ch: int = int(SaveManager.get_progress()["next_chapter"])
	if ch > 5:
		# 已全部通关：引导去图鉴
		Game.goto_state(Game.State.CATALOG)
		return
	# W9-7（批次 AA 规格 §12 P3-8）：目标章节数据存在性校验——对齐 level_scene._on_settle_next_pressed
	# 既有口径（`not LevelLibrary.get_level(x).is_empty()`）。next_chapter 指向的章节缺档（数据损坏/
	# 未扫描）时旧实现直接 goto_state(LEVEL) → 落入「空场占位」关（_load_level 兜底 push_warning 后
	# 空场）。改为零路由 + Game.info 提示（信息可达、可恢复），留在当前界面由用户重试/走新游戏。
	if LevelLibrary.get_level(ch).is_empty():
		push_warning("载入存档失败：第 %d 关数据缺失（零路由，留在主菜单）" % ch)
		Game.info(I18n.t("第 %d 关数据缺失，无法载入存档") % ch, 4.0)
		return
	Game.goto_state(Game.State.LEVEL, {"chapter": ch, "replay": false})

func _on_quit() -> void:
	# K8→批次V（V-C5，spec §3.2）：退出确认统一确认条（与窗口关闭按钮同流程，文案逐字保持）；
	# 确认=stop_gesture_process+quit，取消/×缺省空回调=零副作用。
	Game.confirm(I18n.t("退出《千年一榫》？"), _quit_now)

func _quit_now() -> void:
	# 批次 V（V18，spec §8.2）：退出兜底保存——stop/quit 前显式 SaveManager.save_game()（与
	# main.gd:_quit_now_shared 同构；主菜单退出经 _on_quit 确认条确认后走本函数，覆盖退出前
	# 未落盘的内存变更；close_requested 自动保存 save_manager.gd:23-25 保留）。
	SaveManager.save_game()
	GestureBridge.stop_gesture_process()
	get_tree().quit()

# ---- M-B（拍板 #7，spec §3.2-5）：stacked_layout 垂直均匀居中布局（M 批等价替换原 arc_layout） ----
static func stacked_layout(w: float, h: float, btn_w: float, btn_h: float, n: int) -> Array[Vector2]:
	## 三钮垂直均匀居中：按钮列水平中心 x = COL_X_RATIO*ELLIPSE_RX（椭圆视觉中轴，常量一处定参）；
	## y = H/2 + (i-(n-1)/2)·gap，gap = (BAND_BOTTOM_RATIO-BAND_TOP_RATIO)·h/n —— 三钮垂直等间隙、
	## 整组对 H/2 居中、全部落在 [0.32H,0.78H] 带内（纯代数，无三角函数——4.7 无 asinf/cosf 实证坑）。
	## w 入参保留签名完整性（水平中心由椭圆参数推导，与面板宽解耦）。
	var x := COL_X_RATIO * ELLIPSE_RX
	var gap := (BAND_BOTTOM_RATIO - BAND_TOP_RATIO) * h / float(n)
	var out: Array[Vector2] = []
	for i in n:
		out.append(Vector2(x, h * 0.5 + (float(i) - float(n - 1) * 0.5) * gap))
	return out

static func title_box(h: float, text_w: float, line_h: float) -> Rect2:
	## 标题盒（spec §3.2-6）：水平中心与按钮列同轴（COL_X_RATIO*ELLIPSE_RX）、
	## 底边 = 带顶（H*0.32）- TITLE_BAND_GAP、高 = 文字行高、宽 = 文字实际宽。
	var bottom := h * BAND_TOP_RATIO - TITLE_BAND_GAP
	var cx := COL_X_RATIO * ELLIPSE_RX
	return Rect2(cx - text_w * 0.5, bottom - line_h, text_w, line_h)

static func corners_in_ellipse(rects: Array[Rect2], h: float, rx: float, ry: float, limit := 0.99) -> bool:
	## 各 rect 4 角全部落入内缩椭圆（左贴弧参考系：弧心 (0, h*0.5)）：u²+v² ≤ limit（默认 0.99，
	## 外椭圆 SDF<0 且留 1% 安全余量）。16 角点 = 标题 4 + 三钮 12（spec §3.2-6）。
	var cy := h * 0.5
	for r: Rect2 in rects:
		for corner: Vector2 in [r.position, Vector2(r.end.x, r.position.y),
				Vector2(r.position.x, r.end.y), r.end]:
			var u := corner.x / rx
			var v := (corner.y - cy) / ry
			if u * u + v * v > limit:
				return false
	return true

func _layout_menu_buttons() -> void:
	# M-B：tscn 内三钮/标题 offset 仅占位，运行时按 stacked_layout + title_box 绝对定位；
	# 未布局（size.x<=0，坑 7）时等 LeftPanel resized 再排。resized 时同步刷新 meta ry
	#（单一参数源：ry=容器实际高×0.5，防窗口高变化失配——expand 模式逻辑视口随窗口变）。
	if left_panel.size.x <= 0.0: return  # 无头/未布局时等 resized 再排
	var h := left_panel.size.y
	ellipse_panel.set_meta("ellipse_params", Vector2(ELLIPSE_RX, h * 0.5))
	var centers := stacked_layout(left_panel.size.x, h, BTN_W, BTN_H, 3)
	var btns: Array[Button] = [start_btn, load_btn, quit_btn]
	for i in btns.size():
		var b := btns[i]
		b.custom_minimum_size = Vector2(BTN_W, BTN_H)
		b.size = Vector2(BTN_W, BTN_H)
		b.position = centers[i] - Vector2(BTN_W, BTN_H) * 0.5
	_layout_title(h)
	if not _check_layout_corners_in_ellipse():
		push_warning("主菜单标题/按钮 16 角点越出内缩椭圆（M-B spec §3.2-6 预校验，参数需回修）")

func _layout_title(h: float) -> void:
	## 标题重摆（spec §3.2-6）：与按钮列同轴、置于带上方（底边距带顶 ≥24px）、
	## 字号 TITLE_FONT_MAX 起 4px 步降档至 16 角点校验通过为止（校验即权威）。
	var font := title_label.get_theme_font("font")
	if font == null or title_label.text.is_empty():
		return
	var size := float(TITLE_FONT_MAX)
	while size > float(TITLE_FONT_MIN):
		var fs := int(size)
		var tw := font.get_string_size(title_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var lh := font.get_height(fs)
		var tbox := title_box(h, tw, lh)
		var rects: Array[Rect2] = [tbox]
		rects.append_array(_button_rects(h))
		if corners_in_ellipse(rects, h, ELLIPSE_RX, h * 0.5):
			break
		size -= float(TITLE_FONT_STEP)
	var fs2 := int(size)
	var tw2 := font.get_string_size(title_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x
	var lh2 := font.get_height(fs2)
	title_label.add_theme_font_size_override("font_size", fs2)
	var tbox2 := title_box(h, tw2, lh2)
	title_label.position = tbox2.position
	title_label.size = tbox2.size

func _button_rects(h: float) -> Array[Rect2]:
	var centers := stacked_layout(left_panel.size.x, h, BTN_W, BTN_H, 3)
	var out: Array[Rect2] = []
	for c: Vector2 in centers:
		out.append(Rect2(c - Vector2(BTN_W, BTN_H) * 0.5, Vector2(BTN_W, BTN_H)))
	return out

func _check_layout_corners_in_ellipse() -> bool:
	## M-B（spec §3.2-6 强制前置）：标题 4 角 + 三钮 12 角共 16 角点全部复核
	## （左贴弧参考系 u²+v²≤0.99；M 批等价替换原 12 角点贴弧校验 _check_button_corners_in_ellipse）。
	if left_panel.size.x <= 0.0:
		return true  # 未布局时无可校验（守卫，非放行——resized 后会再校验）
	var h := left_panel.size.y
	var rects: Array[Rect2] = _button_rects(h)
	rects.append(Rect2(title_label.position, title_label.size))
	return corners_in_ellipse(rects, h, ELLIPSE_RX, h * 0.5)

## I18n：语言切换实时重刷（任务口径「主菜单按钮」组）——按钮两态+退出钮；标题=作品名
## 不随语言变化（保留中文书法观感）。签名带 lang（language_changed 1 参——Godot 4 信号
## 到 Callable 参数数严格匹配，0 参方法被拒调不执行）。
func _refresh_texts(_lang: String = "") -> void:
	_update_buttons()
	quit_btn.text = I18n.t("退出")
	# 批次 AF 实机反馈②：标题随语言切换重取文本，并重跑弧面布局（幂等）——
	# _layout_title 按新文本宽度重新降档取字号与摆位（en 长句自动收纳）。
	title_label.text = I18n.t("千年一榫")
	_apply_arc_panel()

## 批次 AB-3：主题翻转回调随深浅主题机制删除退役（_apply_arc_panel 在 _ready 直挂）。
func _exit_tree() -> void:
	if I18n.language_changed.is_connected(_refresh_texts):
		I18n.language_changed.disconnect(_refresh_texts)
