extends Control
## Galgame 对话。依据 spec 4.3/10.1 + 批次 K spec §八（K5）+ 批次 Y Y4 波（Y-B1~Y-B7）。
## Y4（spec §9.0 拍板 1~6）：台词改由 剧情对话/ 剧情对话文档体系供给——格式
## {"_说明":[…],"rounds":[{"speaker":"晷"|"我","texts":[…]}]}（接口规范=技术文档/接口规范_剧情对话.md），
## after_level(n)→第n关.json（章节→文件映射写死为常量；批次 Z §14 增补，用户 2026-09-24
## 拍板：开场对话文档删除、opening 语境退役——旧 mode=="opening" 等值静默归一为 after_level，
## 按传入 chapter 取该关文档缺省 1，不报错不崩不新增告警）；逐句点击推进
## （轮内逐句、轮末切下一轮）；"_说明" 键加载器忽略；非法轮跳过+告警不崩（铁律 8：正式台词
## 替换零代码，仅改 JSON）。
## 交互：点击/空格推进（无自动播放）；打字机 30 字/秒；打字未完成时推进=立即补全本段（快进）。
## K5-3：仅根 Control（STOP）收 _gui_input 推进；子控件全部显式 IGNORE（tscn+代码双保险），
## 修复立绘/名牌/对话框吞点击致「点击多次才响应」。K5-4：SkipButton 一键跳过整段。
## M-D（批次 M spec §3.4，2026-09-07）：①立绘按 portrait_metrics 可见内容落位——可见脚底
## =对话框顶−30px（拍板 #2）、盒高 560→620、头顶不出屏回退档，纹理统一算法（不再吃
## 纹理底部大片透明边的亏）；②【追1】对话框背板 α 深 0.75/浅 0.78 + DialogPanel 挂
## ui_material 面板档，悬停期窄幅金属高光带随光标移动（u_hover_metal 专用 hover 高光路径，
## 不复活镜射系 uniform——M-C 根除红线）。
## Y-B4 立绘定档（拍板 4）：对话立绘=晷唯一（主角无立绘），按章节常量映射取时代立绘
## （assets/characters/era_portraits/，复制自项目前期素材，不动原文件），对话开始定档、期间锁死——
## 已断开皮肤变化信号对对话立绘的一切联动（修复既有「对话中换皮肤立绘跟着变」bug）；
## 对话文档不控制立绘；缺图回落第 1 关立绘+告警。名字框：晷=左（名牌=单字「晷」，2026-09-22
## 用户拍板名牌=晷，纠正 Y3 误改「古今晷」）、我=右。

const PM := preload("res://scripts/portrait_metrics.gd")

@onready var portrait: TextureRect = $Portrait
@onready var dialog_panel: PanelContainer = $DialogPanel
@onready var name_tag_left: PanelContainer = $NameTagLeft
@onready var name_tag_right: PanelContainer = $NameTagRight
@onready var name_label_left: Label = $NameTagLeft/NameLabel
@onready var name_label_right: Label = $NameTagRight/NameLabel
@onready var skip_btn: Button = $SkipButton
@onready var text_label: Label = $DialogPanel/VBox/TextLabel
@onready var hint_label: Label = $HintLabel
@onready var background: TextureRect = $Background
@onready var dim: ColorRect = $Dim

const TYPE_SPEED := 30.0  # 字/秒
# ── Y4 剧情对话文档体系常量（spec §9.0 拍板 1~6；接口规范=技术文档/接口规范_剧情对话.md）──
# 拍板 1：文档放游戏工程内 G/剧情对话/，打包直读；拍板 3：合法 speaker 仅「晷」「我」。
const DOC_DIR := "res://剧情对话/"
const CHAPTER_DOCS := {
	1: DOC_DIR + "第1关.json",
	2: DOC_DIR + "第2关.json",
	3: DOC_DIR + "第3关.json",
	4: DOC_DIR + "第4关.json",
	5: DOC_DIR + "第5关.json",
}
const SPEAKER_GUI := "晷"
const SPEAKER_ME := "我"
# 拍板 4：时代立绘映射（第 1 关→开头、第 2 关→宋、第 3 关→元、第 4 关→明、第 5 关→现）；
# 复制入库不移动原文件；缺图回落第 1 关立绘+告警。
const ERA_PORTRAITS := {
	1: "res://assets/characters/era_portraits/开头.png",
	2: "res://assets/characters/era_portraits/宋.png",
	3: "res://assets/characters/era_portraits/元.png",
	4: "res://assets/characters/era_portraits/明.png",
	5: "res://assets/characters/era_portraits/现.png",
}
const PORTRAIT_FALLBACK_CHAPTER := 1
# J4-1（E1）对话框黄色系毛玻璃（批次 J 计划 §0.5/B1 体系：半透明底+顶缘高光边+柔投影）
# M-D 追1：背板 α 锚定 70~80%——深 0.66→0.75（暂定值走查微调）
# 批次 AB-3：PANEL_BG_LIGHT（浅档）随深浅主题机制删除退役，深档为唯一值。
const PANEL_BG_DARK := Color(0.36, 0.26, 0.10, 0.75)   # 对话框黄棕底（恒深档）
const PANEL_BORDER_HILITE := Color(1.0, 0.92, 0.7, 0.4)  # 顶缘高光渐变边
const UI_MATERIAL_SHADER := "res://assets/shaders/ui_material.gdshader"
# M-D 立绘落位（拍板 #2，暂定值走查微调）：可见脚底=面板顶−GAP；盒高 560→620；
# 头顶出屏按 STEP 回退放大档；度量失效回落旧锚（K5-1 兜底）。
const PORTRAIT_GAP := 30.0
const PORTRAIT_BOX_H := 620.0
const PORTRAIT_H_STEP := 40.0
const PORTRAIT_MIN_H := 320.0
const PORTRAIT_FALLBACK_TOP := -560.0
# M-D 追1：金属反光能量渐入渐出速率（能量/s，0→1 约 0.17s，走查微调）
const HOVER_METAL_SPEED := 6.0
# J4-1（E3）背景压暗层：黑 0.62（批次 AB-3：DIM_ALPHA_LIGHT 浅档退役，恒深档）
const DIM_ALPHA_DARK := 0.62
const MAX_CHAPTER := 5  # 背景章节封顶（after_level 第 5 关后取第 5 关背景；路由原 >5 判定不动）

var _lines: Array = []
var _index: int = 0
var _shown: int = 0
var _typing: bool = false
var _mode: String = "after_level"  # §14：opening 语境退役，缺省即 after_level（set_context 归一）
var _chapter: int = 1
var _elapsed: float = 0.0
var portrait_path: String = ""  # 当前立绘纹理路径（测试与调试用；Y4 起=时代立绘，与穿戴无关）
# Y4 诊断（测试断言用）：doc_warnings 收集解析/回退告警（同步 push_warning）；loaded_path=最近加载文档
var doc_warnings: Array[String] = []
var loaded_path: String = ""
# M-D 追1：悬停金属反光状态（能量 0~1 渐入渐出；光标屏幕像素坐标，SCREEN_UV 同口径）
var _hover_metal_energy: float = 0.0
var _hover_mouse_screen: Vector2 = Vector2(-9999.0, -9999.0)

func set_context(ctx: Dictionary) -> void:
	# 批次 Z §14（用户 2026-09-24 拍板）：opening 语境整体退役——旧调用方传 mode=="opening"
	# 等任何非 after_level 值一律**静默归一**为 after_level（按传入 chapter 取该关文档、缺省 1；
	# 不报错、不崩、不新增告警）。_chapter 不归一（映射外章节沿用既有缺失回退防御口径）。
	_mode = String(ctx.get("mode", "after_level"))
	if _mode != "after_level":
		_mode = "after_level"
	_chapter = int(ctx.get("chapter", 1))

func _ready() -> void:
	# Y-B3/§14：按语境解析文档路径（after_level→第n关.json，缺失回退空文档+告警）
	load_dialog(_doc_path_for_context())
	_apply_panel_theme()
	_apply_background()
	_apply_portrait()
	skip_btn.pressed.connect(_finish)  # K5-4：一键跳过（等效整段播完的路由）
	# I18n：tscn 静态文字经 t() 覆写（zh 直通原样；en 命中词条表）。
	# AF 修复③（实机反馈批，2026-11-01）：旧口径「TALK 为临时件无实时刷需求」按用户实机
	# 反馈推翻——对话常驻屏内可达数十秒，中途切语言当前句须立即换文。订阅 language_changed
	# 即时重绘（当前句正文/双名牌/跳过钮/继续提示）；_exit_tree 显式退订（J6 信号卫生）。
	skip_btn.text = I18n.t("跳过剧情")
	hint_label.text = I18n.t("点击 / 空格继续")
	if not I18n.language_changed.is_connected(_on_language_changed):
		I18n.language_changed.connect(_on_language_changed)
	# K5-3 代码防御兜底：子控件一律 IGNORE，仅根 Control（STOP）收 _gui_input 推进
	for c: Control in [portrait, name_tag_left, name_tag_right, dialog_panel, hint_label]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Y-B4 立绘锁死：不再连接 SaveManager.skin_changed——对话立绘按章节定档后恒定，
	# 断开皮肤变化信号对对话立绘的一切联动（修复既有「对话中换皮肤立绘跟着变」bug）。
	# 批次 AB-3：theme_changed 订阅随深浅主题机制删除退役（对话框毛玻璃/压暗层挂载直挂，恒深档）。

func load_dialog(path: String) -> void:
	_load_dialog(path)

func _apply_panel_theme() -> void:
	# E1（J4-1）：黄色系毛玻璃对话框（多层 StyleBoxFlat 近似，体系同 J1 批次 B1）——
	# 半透明黄底（深浅各配，§0.5 定值）+ 顶缘高光渐变边 + 圆角 14。
	# M-D 追1：α 提至 0.75/0.78（70~80% 半透锚定）；shadow_size 置 0——DialogPanel 已挂
	# ui_material 面板档材质，外投影由材质承担（L-A「StyleBox shadow 已置 0，材质承担」契约）。
	# 批次 AB-3：深浅主题机制删除，恒深档黄底。
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG_DARK
	sb.border_width_left = 1
	sb.border_width_top = 2  # 顶缘高光加宽（玻璃光效）
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = PANEL_BORDER_HILITE
	sb.set_corner_radius_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.0)
	sb.shadow_size = 0  # M-D 追1：投影移交材质面板档（offset 3,5 / 12px 渐隐）
	sb.shadow_offset = Vector2.ZERO
	sb.set_content_margin_all(18.0)
	dialog_panel.add_theme_stylebox_override("panel", sb)
	_ensure_dialog_material()

## M-D 追1：DialogPanel 挂 ui_material 面板档（u_panel_mode=1 / u_ellipse_use=0 圆角矩形
## 卡片档）——最小侵入决策：不经 UILightLinker（talk_scene 的 DialogPanel mouse_filter=IGNORE、
## hover 由本脚本自驱，避免纳入 linker 的 glow_targets 体系），挂载与驱动归本脚本全权管理，
## 不破坏 linker 既有容器档/按钮档口径；主题参数与 linker 常量同源读取（单一参数源防漂移）。
func _ensure_dialog_material() -> void:
	var mat := dialog_panel.material as ShaderMaterial
	if mat == null or mat.shader == null or not String(mat.shader.resource_path).ends_with("ui_material.gdshader"):
		mat = ShaderMaterial.new()
		mat.shader = load(UI_MATERIAL_SHADER)
		dialog_panel.material = mat
		if not dialog_panel.resized.is_connected(_on_dialog_resized):
			dialog_panel.resized.connect(_on_dialog_resized)
	# 批次 AB-3：THEME_PARAMS/PANEL_PARAMS 已由 [深,浅] 双档数组收敛为深档标量，直读直写
	#（旧 di 取列分支随深浅主题机制删除退役；写入值=旧深档，逐一未变）。
	var lk: GDScript = load("res://scripts/ui_light_linker.gd")
	for key: String in (lk.THEME_PARAMS as Dictionary):
		mat.set_shader_parameter(key, (lk.THEME_PARAMS as Dictionary)[key])
	for key: String in (lk.PANEL_PARAMS as Dictionary):
		mat.set_shader_parameter(key, (lk.PANEL_PARAMS as Dictionary)[key])
	mat.set_shader_parameter("u_ellipse_use", 0)  # 圆角矩形卡片档（非 D 形椭圆容器）
	mat.set_shader_parameter("u_rect_size", dialog_panel.size)
	var vp := get_viewport()
	if vp != null:
		mat.set_shader_parameter("u_viewport_size", vp.get_visible_rect().size)

func _on_dialog_resized() -> void:
	var mat := dialog_panel.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("u_rect_size", dialog_panel.size)
	_layout_portrait.call_deferred()  # 面板顶随布局变化 → 立绘重落位

func _apply_background() -> void:
	# E3（J4-1）：对话背景 = 即将进入关卡的背景图压暗。批次 Y（Y-C6）：after_level 挂载章节=
	# 即将进入的关 → 背景取 _chapter（旧口径 chapter+1 随挂载点前移退役）；§14 归一后所有语境
	# 同此口径（opening 退役，越界封顶取 5、下限 1）。素材缺失留空露主题底色。
	var target: int = clampi(_chapter, 1, MAX_CHAPTER)
	var path: String = LevelLibrary.get_background_path(target)
	background.texture = load(path) if ResourceLoader.exists(path) else null
	_apply_dim()

## 压暗层：叠加于背景之上、立绘/对话框之下，黑半透（深 0.62，§0.5 定值；批次 AB-3：恒深档）。
func _apply_dim() -> void:
	dim.color = Color(0, 0, 0, DIM_ALPHA_DARK)

## Y-B3/§14：语境→文档路径（章节→文件映射常量，拍板 1）。after_level→第n关.json
## （n=ctx.chapter；opening 语境已退役，set_context 归一后恒 after_level）；文件缺失→
## **空文档（返回 ""）+ 告警**——回退口径与接口规范 §1「缺 rounds→视为空文档（告警后按
## 空台词流程收尾，不崩）」同源一致，不指向任何已删文件（§14 增补）。
func _doc_path_for_context() -> String:
	var p: String = String(CHAPTER_DOCS.get(_chapter, "")) if _mode == "after_level" else ""
	if p == "" or not FileAccess.file_exists(p):
		_warn("剧情对话文件缺失，按空文档收尾: %s" % (p if p != "" else "chapter=%d（映射外）" % _chapter))
		return ""
	return p

## Y4 告警收口：push_warning 同时登记 doc_warnings（无头测试断言用，行为不变）。
func _warn(msg: String) -> void:
	doc_warnings.append(msg)
	push_warning(msg)

## Y-B4 立绘定档（拍板 4）：对话立绘=晷唯一（主角无立绘），按章节常量映射取时代立绘；
## 仅对话开始（_ready）调用一次，此后无人再调——对话期间锁死（皮肤/穿戴变化不联动）。
func _apply_portrait() -> void:
	var tex_path: String = _era_portrait_path(_portrait_chapter())
	portrait_path = tex_path
	portrait.texture = load(tex_path) if ResourceLoader.exists(tex_path) else null
	# M-D：落位延后至布局稳定（_ready 首次调用时面板锚点/盒尺寸未排布）
	_layout_portrait.call_deferred()

## 立绘归属章节：挂载章节（批次 Y Y-C6 起=即将进入的关——关前对话立绘按该关时代定档，
## 与 game.gd 自动穿戴同口径 ctx.chapter）；§14 归一后所有语境同此口径（opening 语境退役，
## 旧「opening=第 1 关」分支随之退役——归一后 chapter 缺省 1 结果等价）。
func _portrait_chapter() -> int:
	return clampi(_chapter, 1, 5)

## 章节→时代立绘路径；映射外或文件缺失→回落第 1 关立绘并告警（拍板 4）。
func _era_portrait_path(chapter: int) -> String:
	var p: String = String(ERA_PORTRAITS.get(chapter, ""))
	if p == "" or not ResourceLoader.exists(p):
		_warn("时代立绘缺失，回落第 1 关立绘: chapter=%d path=%s" % [chapter, p])
		return String(ERA_PORTRAITS[PORTRAIT_FALLBACK_CHAPTER])
	return p

## M-D 立绘落位（拍板 #2）：按 portrait_metrics 可见内容（used_rect）计算——
## 可见脚底全局 y = DialogPanel 顶 − PORTRAIT_GAP(30px)；盒高 620 起步，头顶出屏按
## 40px 步进回退放大档（下限 320，仍出屏则 clamp 头顶贴屏顶）；水平居中不变
## （offset_left/right 固定 ±260）。47 皮肤与缺省立绘统一按各自纹理实际 used_rect 计算。
func _layout_portrait() -> void:
	var panel_top: float = dialog_panel.global_position.y  # Portrait 与 DialogPanel 同锚（0.72）
	var box_w: float = absf(portrait.offset_right - portrait.offset_left)
	var m: Dictionary = PM.measure(portrait_path)
	if portrait.texture == null or not bool(m.get("valid", false)) or box_w <= 0.0:
		# 度量失效（纹理缺失/全透明/盒宽异常）→ 回落旧锚 K5-1（盒顶=面板顶−560）
		portrait.offset_top = PORTRAIT_FALLBACK_TOP
		portrait.offset_bottom = 0.0
		return
	var box_h: float = PORTRAIT_BOX_H
	var f: Dictionary = PM.fit_in_box(m["size"], m["rect_px"], Vector2(box_w, box_h))
	var box_top: float = (panel_top - PORTRAIT_GAP) - float(f["foot_local_y"])
	while box_top + float(f["head_local_y"]) < 0.0 and box_h > PORTRAIT_MIN_H:
		box_h -= PORTRAIT_H_STEP  # 头顶出屏 → 回退放大档（spec 目标行为 2）
		f = PM.fit_in_box(m["size"], m["rect_px"], Vector2(box_w, box_h))
		box_top = (panel_top - PORTRAIT_GAP) - float(f["foot_local_y"])
	if box_top + float(f["head_local_y"]) < 0.0:
		box_top = -float(f["head_local_y"])  # 极端防御：最小档仍出屏 → 头顶贴屏顶
	portrait.offset_top = box_top - panel_top
	portrait.offset_bottom = box_top + box_h - panel_top

func _load_dialog(path: String) -> void:
	# K-E 伴随修复（两页制「……」有真实打字时长后暴露的潜伏 bug）：重载前清打字态，
	# 否则 lines 置空走 _finish 后 _process 仍按旧 _index 读空 _lines → 越界 SCRIPT ERROR。
	_typing = false
	_shown = 0
	loaded_path = path
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		_warn("剧情对话文件缺失: %s" % path)
		_finish()
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	_lines = _parse_dialog_doc(parsed, path)
	if _lines.is_empty():
		_warn("剧情对话无有效台词: %s" % path)
		_finish()
		return
	_show_line(0)

## Y-B2 解析器：剧情对话文档 → 逐句播放清单 [{speaker,text},…]。
## 契约=技术文档/接口规范_剧情对话.md：顶层 {"_说明":[…],"rounds":[{"speaker","texts":[…]}]}；
## "_说明" 键忽略；非法轮（非对象/缺 speaker/非法 speaker/缺 texts/空 texts）整轮跳过并告警，
## 不崩、不影响其余轮；句内空串/非字符串逐句丢弃并告警；顶层纯数组为宽容形态；
## JSON 注释必炸（4.7）→ parse_string 返回 null → 视为空文档告警不崩。长度不限。
func _parse_dialog_doc(parsed: Variant, path: String) -> Array:
	var out: Array = []
	var rounds: Variant = parsed
	if parsed is Dictionary:
		rounds = (parsed as Dictionary).get("rounds", null)
	elif parsed is Array:
		pass  # 宽容：顶层纯数组视同 rounds（接口规范 §4 手写简化形态）
	else:
		_warn("剧情对话格式非法（无法解析出 rounds 数组）: %s" % path)
		return out
	if not (rounds is Array):
		_warn("剧情对话格式非法（缺 rounds 数组）: %s" % path)
		return out
	for i: int in range((rounds as Array).size()):
		var el: Variant = (rounds as Array)[i]
		if not (el is Dictionary):
			_warn("第 %d 轮不是对象，跳过: %s" % [i + 1, path])
			continue
		var d: Dictionary = el as Dictionary
		# P3-6（审查缺陷）：`String(可能为 null/数组)` 属 4.7 运行期中止族（Nonexistent
		# 'String' constructor）——validate 不校验 speaker 类型；非字符串回退 "" 落入下方
		# 「speaker 非法」分支整轮跳过并告警（不中止解析、后继轮保留）。
		var sp_v: Variant = d.get("speaker", "")
		var speaker: String = sp_v if typeof(sp_v) == TYPE_STRING else ""
		if speaker != SPEAKER_GUI and speaker != SPEAKER_ME:
			_warn("第 %d 轮 speaker 非法（仅「晷」/「我」），跳过: %s" % [i + 1, path])
			continue
		var texts_v: Variant = d.get("texts", null)
		if not (texts_v is Array) or (texts_v as Array).is_empty():
			_warn("第 %d 轮 texts 缺失/为空，跳过: %s" % [i + 1, path])
			continue
		# I18n 解耦④：契约校验（speaker ∈ {晷,我}）不动；轮级英文字段带入播放清单——
		# speaker_en（名牌英文）/texts_en（逐句英文，与 texts 下标配对，短缺/非串句回退中文）。
		# 字段属另一实施者并行产出域：落盘与否都正确（缺省空串→显示回退 I18n.t / 中文原文）。
		var sp_en_v: Variant = d.get("speaker_en", "")
		var speaker_en: String = sp_en_v if typeof(sp_en_v) == TYPE_STRING else ""
		var texts_en_v: Variant = d.get("texts_en", null)
		var texts_en: Array = texts_en_v if (texts_en_v is Array) else []
		var kept := 0
		var ti := -1
		for t_v: Variant in (texts_v as Array):
			ti += 1
			if not (t_v is String):
				_warn("第 %d 轮含非字符串句，丢弃该句: %s" % [i + 1, path])
				continue
			var t := String(t_v)
			if t.is_empty():
				_warn("第 %d 轮含空句，丢弃该句: %s" % [i + 1, path])
				continue
			var en := ""
			if ti < texts_en.size() and typeof(texts_en[ti]) == TYPE_STRING:
				en = String(texts_en[ti])
			out.append({"speaker": speaker, "text": t, "speaker_en": speaker_en, "text_en": en})
			kept += 1
		if kept == 0:
			_warn("第 %d 轮无有效句，跳过: %s" % [i + 1, path])
	return out

## I18n 解耦④：名牌显示名单源——本轮 JSON 带 speaker_en 且本轮 speaker 即该名牌归属者
## → 用英文字段（另一实施者产出域，落盘与否都正确）；否则 I18n.t(中文角色名)
## （zh 直通原样「晷」/「我」；en 未命中词条回退中文）。SPEAKER_GUI/SPEAKER_ME 契约
## 常量与 _parse_dialog_doc 校验（:300）零改动。
func _speaker_name(line: Dictionary, who: String) -> String:
	if I18n.get_language() == "en" and String(line.get("speaker", "")) == who:
		var en := String(line.get("speaker_en", ""))
		if not en.is_empty():
			return en
	return I18n.t(who)

## I18n：逐句正文取值——en 优先轮级 texts_en 配对句（空=未落盘回退中文原文）；zh 恒原文。
func _line_text(line: Dictionary) -> String:
	if I18n.get_language() == "en":
		var en := String(line.get("text_en", ""))
		if not en.is_empty():
			return en
	return String(line.get("text", ""))

## AF 修复③：语言切换实时重绘落点——静态件（跳过钮/继续提示）+ 当前句（正文/双名牌）。
## 名牌显隐由 speaker 决定（语言无关）不重算；当前句按打字态二分：
##   已完整 → 直接置新语言全文；打字中 → _elapsed（字符数口径）跨语言续打（新文案更短则
##   立即收口出提示，与 _process 收口口径一致）。
func _on_language_changed(_lang: String) -> void:
	skip_btn.text = I18n.t("跳过剧情")
	hint_label.text = I18n.t("点击 / 空格继续")
	_refresh_current_line()

func _refresh_current_line() -> void:
	if _lines.is_empty() or _index < 0 or _index >= _lines.size():
		return
	var line: Dictionary = _lines[_index]
	name_label_left.text = _speaker_name(line, SPEAKER_GUI)
	name_label_right.text = _speaker_name(line, SPEAKER_ME)
	var full := _line_text(line)
	if _typing:
		var target: int = mini(int(_elapsed), full.length())
		_shown = target
		text_label.text = full.substr(0, _shown)
		if _shown >= full.length():
			_typing = false
			hint_label.visible = true
	else:
		text_label.text = full

## J6 信号卫生硬化：断开挂在 autoload（常驻）上的命名连接，防场景释放后回调 freed 实例
##（main_menu._exit_tree 同款）。
func _exit_tree() -> void:
	if I18n.language_changed.is_connected(_on_language_changed):
		I18n.language_changed.disconnect(_on_language_changed)

func _show_line(i: int) -> void:
	_index = i
	var line: Dictionary = _lines[i]
	var speaker := String(line.get("speaker", ""))
	# K5-2：按 speaker 互斥切换双名牌。Y4（拍板 3/4）：合法 speaker=「晷」「我」；
	# 晷名牌在左（名牌=单字「晷」，2026-09-22 用户拍板纠正 Y3 误改「古今晷」）、我名牌在右；
	# 其他/缺省 speaker 两名牌皆隐（防御保留）。
	name_label_left.text = _speaker_name(line, SPEAKER_GUI)
	name_label_right.text = _speaker_name(line, SPEAKER_ME)
	name_tag_left.visible = speaker == SPEAKER_GUI
	name_tag_right.visible = speaker == SPEAKER_ME
	text_label.text = ""
	_shown = 0
	_typing = true
	_elapsed = 0.0
	hint_label.visible = false

func _process(delta: float) -> void:
	_hover_metal_tick(delta)  # M-D 追1：金属反光能量每帧推进（打字机 idle 时也要跑）
	if not _typing:
		return
	_elapsed += delta * TYPE_SPEED
	var full: String = _line_text(_lines[_index])
	var target: int = mini(int(_elapsed), full.length())
	if target > _shown:
		_shown = target
		text_label.text = full.substr(0, _shown)
	if _shown >= full.length():
		_typing = false
		hint_label.visible = true

func _input(event: InputEvent) -> void:
	# M-D 追1：捕获鼠标移动（内容坐标口径，与 shader SCREEN_UV×u_viewport_size 同系）；
	# DialogPanel mouse_filter=IGNORE 收不到 hover 事件，走全局光标位置判定。
	if event is InputEventMouseMotion:
		_hover_mouse_screen = (event as InputEventMouseMotion).position

## M-D 追1：金属反光能量 tick——光标在 DialogPanel 全局 rect 内 → 目标 1（渐入），否则 0
## （渐出）；uniform 同步写入（u_hover_metal 能量 / u_mouse_screen 光标坐标）。
## 非悬停能量恒 0 → shader 高光项乘 0 恒灭（「非悬停不出现」）。
func _hover_metal_tick(delta: float) -> void:
	if dialog_panel == null:
		return
	var inside: bool = dialog_panel.get_global_rect().has_point(_hover_mouse_screen)
	_hover_metal_energy = move_toward(_hover_metal_energy, 1.0 if inside else 0.0, delta * HOVER_METAL_SPEED)
	var mat := dialog_panel.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("u_hover_metal", _hover_metal_energy)
		mat.set_shader_parameter("u_mouse_screen", _hover_mouse_screen)
		# u_viewport_size 每帧随写（main.gd 同惯例）：expand 模式窗口 resize 会改变逻辑视口，
		# SCREEN_UV×u_viewport_size 与 u_mouse_screen 像素口径必须同步，否则高光位置漂移。
		var vp := get_viewport()
		if vp != null:
			mat.set_shader_parameter("u_viewport_size", vp.get_visible_rect().size)

## 测试/走查钩子：模拟光标屏幕位置并推进一拍（与 _process 真实链路同一变量同一路径）。
func hover_probe(mouse_screen: Vector2, delta: float = 0.2) -> void:
	_hover_mouse_screen = mouse_screen
	_hover_metal_tick(delta)

func get_hover_metal_energy() -> float:
	return _hover_metal_energy

func _advance() -> void:
	if _lines.is_empty():
		return
	if _typing:
		# 打字未完成 → 快进本段
		_typing = false
		text_label.text = _line_text(_lines[_index])
		hint_label.visible = true
		return
	if _index + 1 < _lines.size():
		_show_line(_index + 1)
	else:
		_finish()

func _finish() -> void:
	# 批次 Y（Y-C6 补充，用户 2026-09-23 拍板）对话挂载点对齐 + 批次 Z §14（用户 2026-09-24
	# 拍板）开场对话删除：
	#   开场链：开场动画（§14 起链路零 opening 对话段）→ 第 1 关关前对话（第1关.json，
	#   {"mode":"after_level","chapter":1} 挂载）→ 第 1 关；
	#   after_level 语义=「进第 N 关之前」的关前对话（挂载章节=即将进入的关，结算侧已前移一位）——
	#   播完进第 _chapter 关（旧口径「播第 N 关对话→进 N+1」整体前移退役）。
	#   旧 opening 分支（播完接 after_level(1) 再播一次）随 opening 语境退役删除——归一后
	#   opening 实例即 after_level 语义，直进挂载章节。
	if _chapter > 5 or _chapter < 1:
		# 防御：映射外章节（第 5 关后终点流程待确认 spec #6，沿用回主菜单口径）
		Game.goto_state(Game.State.MAIN_MENU)
		return
	Game.goto_state(Game.State.LEVEL, {"chapter": _chapter, "replay": false})

func _gui_input(event: InputEvent) -> void:
	# 鼠标任意点击推进（根节点 mouse_filter=STOP 保证可收到）
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_advance()

func _unhandled_input(event: InputEvent) -> void:
	# 空格/回车推进
	if event.is_action_pressed("ui_accept"):
		_advance()
		get_viewport().set_input_as_handled()

## 批次 AB-3：主题翻转回调与 theme_changed 断开随深浅主题机制删除退役。
