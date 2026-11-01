extends "res://tests/test_base.gd"
## 批次 O-P1 图鉴+商店域五修判定用例（O1/O2/O5/O6/O7，TDD 红灯先行，2026-09-10）。
## 契约来源：批次 O 用户五条反馈 + 调研结论（plan 批次 O）：
##   O1 删除参考图渐变+加画框阴影：tscn/gd 中 RefFade 羽化层全删（用户：红圈渐变删掉）；
##     RefImage 外包 RefFrame(PanelContainer) 画框——StyleBoxFlat 边框≥2px+圆角+阴影
##     shadow_size/offset，随主题深浅刷新（与图鉴卡同族做法）。
##   O2 「开场动画（回看）」项：左上 RefImage 显示 ref_opening_hand.jpg（项目前期素材开场末段
##     原图复制，头字节校验 JPEG）；左下四要点区改自由短文案 OPENING_INTRO（非四要点表格，
##     总长防超出卡片）；章节选中仍显示 ref_chapterN（往返切换回归）。
##   O5 图鉴退出路由：Game.catalog_return 来源记忆——goto_state 目标==CATALOG 时快照
##     {state:旧态, ctx:旧上下文}，其他目标清空；图鉴退出读它：state==LEVEL 且 ctx 含
##     chapter → goto_state(LEVEL, 快照ctx)（透传 replay 位保持左下退出钮语义）；
##     P批波2（2026-09-10）SETTLE 来源透传回 SETTLE（原降级 MAIN_MENU 待办随波 2 结算
##     架构重做兑现，goto_state(SETTLE) 经 game.gd 特判边缘路径重建 level）；消费后复位防串味；
##     无记忆/非 LEVEL 来源兜底 MAIN_MENU（旧契约保持）。
##   O6 商店未解锁皮肤可点击看详情：卡片按钮「随剧情解锁」不再 disabled（可点开看文案）；
##     详情购买钮对未解锁原创置 disabled+文本「随剧情解锁」（防可点被 _on_select 静默吞）；
##     47 张目录皮肤（非未解锁原创路径）行为不变。
##   O7 皮肤「效果」固定行+全量效果文案：SkinCatalog.EFFECT 常量表（目录 47 张=5 原创+42
##     普通各一条；任务书「52 条」系「47+5」把已含原创的 47 张重复计数，按「每张皮肤一条、
##     键齐全」口径落 47 条——等价覆盖，见完成报告偏离说明）；模式「对XX有X的提升」、
##     逐条不同质；get_skins/get_origin_skin 合并出 d["effect"]；
##     shop 详情栏 DetailScroll 与 DetailBottom 之间新增固定行 EffectRow（HBox：前缀「效果」
##     +内容 Label，不随 DetailDesc 滚动，滚动前后全局 rect 不变）；_show_detail 填充。
## 段序说明：商店段（O6/O7）必须在 O5 路由段之前——goto_state(LEVEL) 会触发
##   unlock_origin_skin（game.gd K-D 解锁点位①）+advance_progress 兜底解锁②并入档，
##   污染「未解锁原创」前置态。环境说明：--script 无头模式 autoload 在 /root/<Name>
##   （P2-5 动态引用）；枚举 MAIN_MENU=1 SETTLE=5 CATALOG=6 LEVEL=4；
##   起测前备份 user:// 档案、终测还原（N10 同规）。

const CATALOG_SCENE := "res://scenes/catalog/catalog_scene.tscn"
const CATALOG_GD := "res://scenes/catalog/catalog_scene.gd"
const SHOP_SCENE := "res://scenes/shop/shop_panel.tscn"
const CATALOG_DATA := "res://data/skin_catalog.gd"
const OPENING_IMG := "res://assets/reference_images/ref_opening_hand.jpg"
const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const BK_SAVE := "user://_o_backup_save.json"
const BK_FLAG := "user://_o_backup_flag.flag"

const ST_MAIN_MENU := 1
const ST_LEVEL := 4
const ST_SETTLE := 5
const ST_CATALOG := 6

const EFFECT_MAX_LEN := 24  # O7 效果文案长度上限（一句话短文案防溢出）

func _backup_user() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(BK_SAVE))
	if FileAccess.file_exists(FLAG_PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(FLAG_PATH), ProjectSettings.globalize_path(BK_FLAG))

func _restore_user() -> void:
	for pair: Array in [[BK_SAVE, SAVE_PATH], [BK_FLAG, FLAG_PATH]]:
		if FileAccess.file_exists(String(pair[0])):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(String(pair[0])), ProjectSettings.globalize_path(String(pair[1])))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(String(pair[0])))
	var sm: Node = get_root().get_node_or_null("SaveManager")
	if sm != null:
		sm.load_game()

func _settle() -> void:
	await process_frame
	await process_frame

## 批次 AA / W5-1：返回栈深度查询（API 缺席 → -1 判红不崩，4.7 防御访问纪律）。
func _depth(g: Variant) -> int:
	if g.has_method("catalog_return_depth"):
		return int(g.call("catalog_return_depth"))
	return -1

func _open_catalog(game: Variant, container: Control) -> Node:
	game.goto_state(ST_CATALOG)
	await process_frame
	if container.get_child_count() == 0:
		return null
	return container.get_child(container.get_child_count() - 1)

func _open_shop(game: Variant, overlay: CanvasLayer) -> Node:
	game.open_overlay("shop")
	await process_frame
	if overlay.get_child_count() == 0:
		return null
	return overlay.get_child(overlay.get_child_count() - 1)

func _initialize() -> void:
	print("== test_o_catalog_shop ==")
	_backup_user()
	var save: Variant = get_root().get_node("SaveManager")
	var game: Variant = get_root().get_node("Game")
	save.load_game()  # 重置默认存档（owned=[skin_default, 开头原创]）
	# 批次 AF 修复批（2026-11-01，587f01e「夹具显式钉前提」同款）：I18n autoload 启动读
	# 用户真档 settings.language（实测档可能为 en）——本件断言为 zh 时代口径，钉 zh 保
	# 环境确定性（纯测试夹具前提，生产代码零改动）。时序坑⑥：--script 模式 autoload
	# _ready 推迟至树激活——先放行一帧让 I18n._ready 读完档，再钉 zh（否则钉被启动读档覆盖）。
	await process_frame
	var i18n: Variant = get_root().get_node_or_null("I18n")
	if i18n != null:
		i18n.call("set_language", "zh")

	var container: Control = Control.new()
	add_child(container)
	var overlay: CanvasLayer = CanvasLayer.new()
	add_child(overlay)
	game.attach(container, overlay)

	# ==================== 段 1：O1 删渐变+画框 ====================
	print("-- 段1 O1 删渐变+画框 --")
	var tscn_text: String = FileAccess.get_file_as_string(CATALOG_SCENE)
	var gd_text: String = FileAccess.get_file_as_string(CATALOG_GD)
	check(not tscn_text.contains("RefFade"), "O1：tscn 已无 RefFade 羽化层节点（红圈渐变删除）")
	check(not gd_text.contains("ref_fade"), "O1：gd 已无 ref_fade 引用（@onready/_apply/_make/_select 五处全删）")
	check(ResourceLoader.exists(CATALOG_SCENE), "O1：catalog_scene.tscn 可用")
	var panel: Node = await _open_catalog(game, container)
	check(panel != null, "O1：图鉴场景可打开")
	if panel == null:
		_restore_user()
		finish()
		return
	check(panel.get_node_or_null("Body/LeftInfo/VBox/RefImage/RefFade") == null,
		"O1：运行时 RefImage 下无 RefFade 子节点（渐变覆盖层根除）")
	var frame: PanelContainer = panel.get_node_or_null("Body/LeftInfo/VBox/RefFrame") as PanelContainer
	check(frame is PanelContainer, "O1：RefFrame(PanelContainer) 画框节点存在（包裹 RefImage）")
	var ref_img: TextureRect = panel.get_node_or_null("Body/LeftInfo/VBox/RefFrame/RefImage") as TextureRect
	check(ref_img is TextureRect, "O1：RefImage 迁入画框内（RefFrame/RefImage 路径）")
	check(ref_img != null and int(ref_img.stretch_mode) == int(TextureRect.STRETCH_KEEP_ASPECT_CENTERED),
		"O1：RefImage 等比居中入框口径不回归（K7-4 保持）")
	if frame != null:
		var fsb: StyleBoxFlat = frame.get_theme_stylebox("panel") as StyleBoxFlat
		check(fsb != null, "O1：画框运行时样式已生成（_apply_catalog_palette 接管）")
		check(fsb != null and fsb.border_width_top >= 2, "O1：画框边框 ≥2px")
		check(fsb != null and fsb.shadow_size >= 8 and fsb.shadow_offset != Vector2.ZERO,
			"O1：画框带阴影（shadow_size≥8 且 offset 非零）")
		check(fsb != null and fsb.corner_radius_top_left >= 8, "O1：画框圆角 ≥8（与图鉴卡同族）")
		check(fsb != null and fsb.content_margin_left >= 4.0, "O1：画框留衬边（照片不满贴框缘）")

	# ==================== 段 2：O2 开场项配图+短文案 ====================
	print("-- 段2 O2 开场项配图+短文案 --")
	check(FileAccess.file_exists(ProjectSettings.globalize_path(OPENING_IMG)), "O2：ref_opening_hand.jpg 已复制进工程")
	var f: FileAccess = FileAccess.open(OPENING_IMG, FileAccess.READ)
	var is_jpeg: bool = false
	if f != null:
		var b: PackedByteArray = f.get_buffer(3)
		f.close()
		is_jpeg = b.size() >= 3 and b[0] == 0xFF and b[1] == 0xD8 and b[2] == 0xFF
	check(is_jpeg, "O2：头字节校验=真 JPEG（FF D8 FF，历史坑：PNG 伪装 jpg）")
	check(ResourceLoader.exists(OPENING_IMG), "O2：配图已导入（ResourceLoader 可见）")
	var opening_ref: Variant = panel.get("OPENING_REF")
	check(typeof(opening_ref) == TYPE_STRING and String(opening_ref) == OPENING_IMG,
		"O2：catalog 挂 OPENING_REF 常量指向该图")
	# 默认选中即开场项（K7-5）→ 左上已显示配图、左下为短文案
	check(ref_img != null and ref_img.texture != null
		and String(ref_img.texture.resource_path).contains("ref_opening_hand"),
		"O2：选中开场动画项 → RefImage 显示 ref_opening_hand.jpg")
	var intro: Variant = panel.get("OPENING_INTRO")
	check(typeof(intro) == TYPE_STRING and not String(intro).is_empty(), "O2：开场项短文案 OPENING_INTRO 非空")
	var intro_txt: String = String(intro) if typeof(intro) == TYPE_STRING else ""  # 红灯期防崩守卫
	var fp: RichTextLabel = panel.get_node("Body/LeftInfo/VBox/FourPoints")
	check_eq(String(fp.text), intro_txt, "O2：四要点区显示开场短文案（自由文案，非文物四要点模板）")
	check(intro_txt.is_empty() or intro_txt.length() <= 80, "O2：短文案 ≤80 字（防超出卡片）")
	check(not String(fp.text).contains("时间：") and not String(fp.text).contains("地点：")
		and not String(fp.text).contains("类型：") and not String(fp.text).contains("历史意义"),
		"O2：开场项不再套 时间/地点/类型/历史意义 四要点表格（显示方式理顺）")
	# 往返切换回归：章节 → 配图/四要点回落章节内容；再回开场项 → 配图/文案切回
	# （注：advance_progress(1) 会兜底解锁第1章原创——该皮肤默认已拥有，不影响后续商店段前置态）
	save.advance_progress(1)
	await _settle()
	var btn1: Button = panel.get_node("Body/RightBox/RightInner/RightScroll/RightList").get_child(0)
	btn1.pressed.emit()
	check(ref_img != null and ref_img.texture != null
		and String(ref_img.texture.resource_path).contains("ref_chapter1"),
		"O2：选中第1关 → RefImage 回落 ref_chapter1.png（章节联动不回归）")
	check(String(fp.text).contains("时间："), "O2：章节态四要点保留（与开场项自由文案互斥切换）")
	var vbtn: Button = panel.get_node("Body/RightBox/RightInner/RightScroll/RightList").get_child(5)
	vbtn.pressed.emit()
	check(ref_img != null and ref_img.texture != null
		and String(ref_img.texture.resource_path).contains("ref_opening_hand"),
		"O2：切回开场项 → RefImage 切回开场配图（往返切换）")
	check_eq(String(fp.text), intro_txt, "O2：切回开场项 → 短文案恢复")

	# ==================== 段 3：O7 数据（EFFECT 全量覆盖） ====================
	print("-- 段3 O7 EFFECT 数据 --")
	var catalog: GDScript = load(CATALOG_DATA)
	var effect: Variant = catalog.get("EFFECT")
	var eff_map: Dictionary = effect if effect is Dictionary else {}  # 红灯期防崩守卫
	check(effect is Dictionary, "O7：SkinCatalog.EFFECT 常量表存在")
	if effect is Dictionary:
		var et: Dictionary = eff_map
		# 目录 47 张（5 原创+42 普通）每张一条；任务书「47 普通+5 原创=52」系重复计数（原创已含
		# 在 47 内），按「键齐全+无冗余」口径断 47——偏离说明见测试头注与完成报告。
		check_eq(et.size(), 47, "O7：EFFECT 47 条与目录一一对应（5 原创+42 普通，无缺无冗余）")
		var missing: PackedStringArray = []
		for i: int in range(1, 43):
			if not et.has("skin_%02d" % i):
				missing.append("skin_%02d" % i)
		for oid: String in ["skin_origin_kaitou", "skin_origin_song", "skin_origin_yuan",
				"skin_origin_ming", "skin_origin_xiandai"]:
			if not et.has(oid):
				missing.append(oid)
		check(missing.is_empty(), "O7：47+5 id 全部有键（缺=%s）" % [missing])
		var empty_or_long: PackedStringArray = []
		var uniq: Dictionary = {}
		for k: String in et.keys():
			var v: String = String(et[k])
			if v.is_empty() or v.length() > EFFECT_MAX_LEN:
				empty_or_long.append("%s(%d)" % [k, v.length()])
			uniq[v] = true
		check(empty_or_long.is_empty(), "O7：每条非空且 ≤%d 字（违例=%s）" % [EFFECT_MAX_LEN, empty_or_long])
		check_eq(uniq.size(), et.size(), "O7：逐条不同质（无重复文案）")
		var pat_bad: PackedStringArray = []
		for k2: String in et.keys():
			var v2: String = String(et[k2])
			if not (v2.begins_with("对") and v2.contains("的提升")):
				pat_bad.append(k2)
		check(pat_bad.is_empty(), "O7：文案符合「对XX有…提升」口径（违例=%s）" % [pat_bad])
	var skins: Array = catalog.call("get_skins")
	var eff_bad: PackedStringArray = []
	for s: Dictionary in skins:
		var want: String = String(eff_map.get(String(s["id"]), ""))
		if String(s.get("effect", "")) != want or want.is_empty():
			eff_bad.append(String(s["id"]))
	check(eff_bad.is_empty(), "O7：get_skins() 47 项均合并 d[\"effect\"]（缺/错=%s）" % [eff_bad])
	var og2: Dictionary = catalog.call("get_origin_skin", 2)
	check_eq(String(og2.get("effect", "")), String(eff_map.get("skin_origin_song", "")),
		"O7：get_origin_skin() 同样合并 effect")

	# ==================== 段 4：O6 未解锁可点 + O7 效果行布局 ====================
	print("-- 段4 O6+O7 商店 --")
	# O6/O7 前置归一：本机真实档可能已解锁/穿戴 song（advance_progress/关卡进入都会解锁原创），
	# reset_for_new_game 回默认档（owned=[skin_default, 开头原创]，song 未解锁）保证前置态确定性。
	save.reset_for_new_game()
	var shop: Node = await _open_shop(game, overlay)
	check(shop != null, "O6：商店覆盖层可打开")
	if shop == null:
		_restore_user()
		finish()
		return
	var cards: Dictionary = shop.get("_cards")
	var song_btn: Button = (cards["skin_origin_song"] as VBoxContainer).get_child(2) as Button
	check(song_btn != null and not song_btn.disabled, "O6：未解锁原创卡片按钮可点击（不再 disabled）")
	check(song_btn != null and song_btn.text == "随剧情解锁", "O6：卡片按钮文本保持「随剧情解锁」（语义不变）")
	song_btn.pressed.emit()
	await process_frame
	var preview: Dictionary = shop.get("_preview")
	check_eq(String(preview.get("id", "")), "skin_origin_song", "O6：点未解锁卡片 → 详情展示该皮肤（文案可看）")
	check_eq(String((shop.get_node("Content/DetailBox/DetailInner/DetailScroll/DetailVBox/DetailName") as Label).text),
		String(catalog.get_skin("skin_origin_song")["name"]), "O6：详情栏名称更新为未解锁原创")
	var buy_btn: Button = shop.get_node("Content/DetailBox/DetailInner/DetailBottom/BuyButton") as Button
	check(buy_btn != null and buy_btn.disabled, "O6：未解锁原创详情购买钮 disabled（防静默吞点击）")
	check(buy_btn != null and buy_btn.text == "随剧情解锁", "O6：详情购买钮文本「随剧情解锁」（未解锁态补全）")
	var equipped_before: String = save.get_skins()["equipped"]
	shop.call("_on_select", catalog.get_skin("skin_origin_song"))
	check_eq(save.get_skins()["equipped"], equipped_before, "O6：_on_select 禁购守卫保持（未解锁不被穿戴，K3-5 不回归）")
	# 47 张目录皮肤的非未解锁路径行为不变
	var btn7: Button = (cards["skin_07"] as VBoxContainer).get_child(2) as Button
	check(btn7 != null and not btn7.disabled and btn7.text == "选择", "O6：普通皮肤卡片按钮「选择」可点（行为不变）")
	shop.call("_show_detail", catalog.get_skin("skin_07"))
	await process_frame
	check(buy_btn != null and not buy_btn.disabled and buy_btn.text == "购买", "O6：普通皮肤详情购买钮可用「购买」")
	# ---- O7 布局：固定效果行 ----
	var inner: Control = shop.get_node("Content/DetailBox/DetailInner")
	check(inner is VBoxContainer, "O7：DetailInner 容器在位")
	var dscroll: ScrollContainer = shop.get_node("Content/DetailBox/DetailInner/DetailScroll")
	var effect_row: HBoxContainer = shop.get_node_or_null("Content/DetailBox/DetailInner/EffectRow") as HBoxContainer
	check(effect_row is HBoxContainer, "O7：EffectRow(HBox) 固定行存在（DetailScroll 与 DetailBottom 之间）")
	var dbottom: Control = shop.get_node("Content/DetailBox/DetailInner/DetailBottom")
	check(effect_row != null and effect_row.get_index() == dscroll.get_index() + 1
		and dbottom.get_index() == effect_row.get_index() + 1,
		"O7：EffectRow 位置在 DetailScroll 之后、DetailBottom 之前")
	check(shop.get_node_or_null("Content/DetailBox/DetailInner/DetailScroll/DetailVBox/EffectRow") == null,
		"O7：EffectRow 不在滚动区内（不随 DetailDesc 滚动）")
	var eprefix: Label = effect_row.get_node_or_null("EffectPrefix") as Label
	var evalue: Label = effect_row.get_node_or_null("EffectValue") as Label
	check(eprefix is Label and String(eprefix.text).begins_with("效果"), "O7：效果行前缀 Label「效果」")
	check(evalue is Label, "O7：效果行内容 Label 存在")
	check(evalue != null and not evalue.has_theme_color_override("font_color"),
		"O7：内容字色用主题正文色（不硬编码，深浅自协调）")
	# 固定不滚：制造长文本滚动，EffectRow 全局 rect 不变
	var rect0: Rect2 = effect_row.get_global_rect()
	var filler: Control = Control.new()
	filler.custom_minimum_size = Vector2(0, 800)
	shop.get_node("Content/DetailBox/DetailInner/DetailScroll/DetailVBox").add_child(filler)
	await process_frame
	await process_frame
	dscroll.scroll_vertical = 200
	await process_frame
	await process_frame
	check(dscroll.scroll_vertical > 0, "O7：模拟滚动真实生效（scroll_vertical=%d）" % dscroll.scroll_vertical)
	var rect1: Rect2 = effect_row.get_global_rect()
	check(absf(rect1.position.y - rect0.position.y) < 0.5 and absf(rect1.position.x - rect0.position.x) < 0.5,
		"O7：滚动前后效果行全局位置不变（固定置顶语义，spec 验收同 M-S 段 B 口径）")
	filler.queue_free()
	await process_frame
	# _show_detail 填充效果
	shop.call("_show_detail", catalog.get_skin("skin_07"))
	await process_frame
	check_eq(String(evalue.text), String(eff_map.get("skin_07", "")),
		"O7：_show_detail 填充效果文案（skin_07，行内可视=「效果：」+内容）")
	shop.call("_show_detail", catalog.get_skin("skin_origin_song"))
	await process_frame
	check_eq(String(evalue.text), String(eff_map.get("skin_origin_song", "")),
		"O7：未解锁原创详情同样填充效果文案")

	# ==================== 段 5：O5 图鉴退出路由（来源记忆；置于商店段后防解锁污染） ====================
	# 批次 AA / W5-1（规格 §8.3/§8.4，2026-09-25）等价改写：单槽覆盖语义升级**有界返回栈**。
	# 旧 5d「跳转其他目标 → 记忆清空」把已退役的 else 清空分支固化成正确行为——该分支正是
	# LEVEL↔CATALOG 永久乒乓（用户致命死循环）的直接成因。改写为栈语义三则且**不弱化**：
	# ① 再次进图鉴 = 压栈（深度计数面断言）② 跳非 CATALOG/非 MAIN_MENU 目标 = **保留栈**
	# （旧实现在此判红）③ goto MAIN_MENU = 导航根清栈。5a~5c 单跳断言逐条原样保持（O5/P3/
	# P批波2 契约零回归），另补栈面深度断言（断言数只增不减：15 → +6）。
	print("-- 段5 O5 退出路由（批次 AA 栈语义等价改写） --")
	check(game.get("catalog_return") is Dictionary, "O5：Game.catalog_return 栈顶镜像字段存在（Dictionary 兼容面）")
	# 段1 曾进图鉴（goto_state(CATALOG)）→ 栈中持有当时快照属预期；先回 MAIN_MENU（导航根）
	# 清栈再验空——清栈判据自「任意非图鉴目标」收窄为「MAIN_MENU」（§8.4 规则②，旧口径废止）
	game.goto_state(ST_MAIN_MENU)
	await process_frame
	var cr0: Variant = game.get("catalog_return")
	check(cr0 is Dictionary and (cr0 as Dictionary).is_empty(), "O5/AA：goto MAIN_MENU（导航根）清栈后镜像空（初始空态）")
	check(_depth(game) == 0, "W5-1/AA：MAIN_MENU 清栈后返回栈深度 0")
	# 5a. LEVEL 来源：进关（replay）→ 图鉴 → 退出 → 回关卡（ctx 透传 replay）【断言原样保持】
	game.goto_state(ST_LEVEL, {"chapter": 2, "replay": true})
	await process_frame
	game.goto_state(ST_CATALOG)
	await process_frame
	check(_depth(game) == 1, "W5-1/AA：LEVEL 单跳来源入栈深度 1")
	var ret: Dictionary = game.get("catalog_return") if game.get("catalog_return") is Dictionary else {}
	check_eq(int(ret.get("state", -1)), ST_LEVEL, "O5：进图鉴快照来源 state=LEVEL")
	check_eq(int(ret.get("ctx", {}).get("chapter", -1)), 2, "O5：快照 ctx.chapter=2")
	check(bool(ret.get("ctx", {}).get("replay", false)), "O5：快照 ctx.replay=true（原样保存）")
	panel = container.get_child(container.get_child_count() - 1)
	(panel.get_node("BottomBar/ExitButton") as Button).pressed.emit()
	await process_frame
	check_eq(int(game.current_state()), ST_LEVEL, "O5：LEVEL 来源 → 图鉴退出回关卡（非主菜单，用户 bug 修复）")
	check_eq(int(game.context().get("chapter", -1)), 2, "O5：回关卡 ctx.chapter 透传=2")
	check(bool(game.context().get("replay", false)), "O5：回关卡 replay 位透传=true（左下退出钮语义保持）")
	var cr: Variant = game.get("catalog_return")
	check(cr is Dictionary and (cr as Dictionary).is_empty(), "O5：消费后 catalog_return 复位（防串味）")
	check(_depth(game) == 0, "W5-1/AA：单跳出栈后深度 0（pop 恰消费一条）")
	# 5b. MAIN_MENU 来源兜底：退出回主菜单（旧契约）【断言原样保持】
	game.goto_state(ST_MAIN_MENU)
	await process_frame
	game.goto_state(ST_CATALOG)
	await process_frame
	panel = container.get_child(container.get_child_count() - 1)
	(panel.get_node("BottomBar/ExitButton") as Button).pressed.emit()
	await process_frame
	check_eq(int(game.current_state()), ST_MAIN_MENU, "O5：MAIN_MENU 来源 → 退出回主菜单（兜底不变）")
	cr = game.get("catalog_return")
	check(cr is Dictionary and (cr as Dictionary).is_empty(), "O5：主菜单路径消费后复位")
	# 5c. P批波2等价替换：SETTLE 来源透传回 SETTLE（原「策略性降级回主菜单」待办随波 2
	# 结算架构重做兑现——结算已由 level 覆盖层承载，goto_state(SETTLE) 经 game.gd 特判
	# 按边缘路径重建 level 直显结算 UI；状态机面在此断言，场景面归 test_p_settle）【断言原样保持】
	game.goto_state(ST_SETTLE, {"chapter": 1, "grade": "完美"})
	await process_frame
	game.goto_state(ST_CATALOG)
	await process_frame
	ret = game.get("catalog_return") if game.get("catalog_return") is Dictionary else {}
	check_eq(int(ret.get("state", -1)), ST_SETTLE, "O5：SETTLE 来源已被快照")
	panel = container.get_child(container.get_child_count() - 1)
	(panel.get_node("BottomBar/ExitButton") as Button).pressed.emit()
	await process_frame
	check_eq(int(game.current_state()), ST_SETTLE, "O5 P批波2等价替换：SETTLE 来源透传回结算（level 边缘路径重建，原降级主菜单废止）")
	# 5d. 批次 AA 栈语义等价改写（旧「其他目标清空」固化过时覆盖语义，废止并升级三则）
	game.goto_state(ST_CATALOG)
	await process_frame
	cr = game.get("catalog_return")
	check(cr is Dictionary and not (cr as Dictionary).is_empty(), "O5/AA：再次进图鉴 = 压栈（栈顶镜像非空；旧断言语义升级为 push，非覆盖）")
	check(_depth(game) == 1, "W5-1/AA：再次进图鉴入栈深度 1（旧单槽无深度面——API 缺席判红）")
	# 核心新规则锚：跳往非 CATALOG 且非 MAIN_MENU 目标 → **保留返回栈**
	#（旧 else: catalog_return={} 清空分支即乒乓成因，本断言在旧实现下必红）
	game.goto_state(ST_LEVEL, {"chapter": 1})
	await process_frame
	check(_depth(game) == 1,
		"W5-1/AA：跳往非 CATALOG/非 MAIN_MENU 目标保留返回栈（旧「非图鉴目标一律清空」分支退役）")
	game.goto_state(ST_MAIN_MENU)
	await process_frame
	cr = game.get("catalog_return")
	check(cr is Dictionary and (cr as Dictionary).is_empty(), "O5/AA：goto MAIN_MENU → 清栈+镜像空（导航根规则，不残留）")
	check(_depth(game) == 0, "W5-1/AA：MAIN_MENU 清栈后深度 0")

	_restore_user()
	finish()
