extends "res://tests/test_base.gd"
## K-B（批次 K spec §5.1/§5.2，plan KB-1）判定用例：设置面板契约无头测试（TDD 先红后绿）。
## 契约（plan K-B 断言清单①~⑨ + 旧 T09 功能回归迁移至新节点路径）：
##   ①根 Control 主题显式赋值（J6-P1-1 纪律）+ Dim(ColorRect)；
##   ②K1-1/1-2/1-6：Panel(PanelContainer) 四 anchor==0.5 居中、custom_minimum_size==Vector2(460,560)、L1 毛玻璃 a<0.7；
##   ③K7-6：EntryBox 下 CatalogEntry/ShopEntry（M-A 批 TextureButton→普通 Button，图标清零、
##     文字「图鉴」「商店」并入按钮、旁挂 Label 删除）、图鉴 disabled==!can_open_catalog()（N批
##     等价替换 2026-09-09：原判据 is_first_launch() 与 save.json 进度零耦合，五路径 BUG 修复）+
##     禁止光标、双入口挂 hover_glow meta（K9 接入②）；
##   ④K1-4：OptionsBox 下 GestureToggle/KbToggle/HudToggle/FullscreenToggle 均 Button(toggle_mode)，
##     text 无「开启」前缀；开态金底(r>0.8,a>0.6)/拨关灰卡(a<0.5)；
##   ⑤开关即时保存（拨关即写 gesture_input=false，拨回恢复）；
##   ⑥约束即时拒绝：双关时 KbToggle 弹回 true + WarningLabel 提示，拒绝不落盘；恢复后提示清空；
##   ⑦K1-5：VolumeGrid(GridContainer) columns==2、HSlider 恰 3（无语音，Q&A7）；
##   ⑧K1-7：CloseButton 不横向撑满（无直角长条）；⑨旧长条 ShopButton/CatalogButton 已移除。
## 环境说明（同旧测试）：--script 无头模式 7 个 autoload 均在 /root/<Name>，经 get_root().get_node
## 取 Variant 动态引用（P2-5：不写全局类名/新 class_name，规避编译期时序问题）；枚举 CATALOG=6。
## 全屏开关无头守卫：FullscreenToggle 打开面板时按 WM.is_fullscreen() 回显且 headless 下隐藏。

const SCENE_PATH := "res://scenes/settings/settings_panel.tscn"
const SAVE_PATH := "user://save.json"
const ST_CATALOG := 6

func _cleanup() -> void:
	var save_abs: String = ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(save_abs):
		DirAccess.remove_absolute(save_abs)
	# 回修3：first_launch.flag 为磁盘级判据，翻转测试后必须清理防污染其他测试进程
	var flag_abs: String = ProjectSettings.globalize_path("user://first_launch.flag")
	if FileAccess.file_exists(flag_abs):
		DirAccess.remove_absolute(flag_abs)

## 打开设置覆盖层并返回面板实例（等待一帧让 queue_free 的旧实例离场、_ready 完成）
func _open_panel(game: Variant, overlay: CanvasLayer) -> Node:
	game.open_overlay("settings")
	await process_frame
	if overlay.get_child_count() == 0:
		return null
	return overlay.get_child(overlay.get_child_count() - 1)

func _font_of(lbl: Node) -> Font:
	if lbl is Label:
		return (lbl as Label).get_theme_font("font")
	return null

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
const DISC_BK_PREFIX := "user://_r2b_ssp_backup_"
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
	print("EVID|user_restore|ssp|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_settings_panel ==")
	_backup_user()
	var save: Variant = get_root().get_node("SaveManager")
	var game: Variant = get_root().get_node("Game")

	_cleanup()
	save.load_game()  # 重置为默认设置（双开关均开、音量全 1.0）

	var st0: int = int(game.current_state())

	# Game 路由环境准备：场景容器 + 覆盖层层（等价 main.tscn 的 attach）
	var container: Control = Control.new()
	add_child(container)
	var overlay: CanvasLayer = CanvasLayer.new()
	add_child(overlay)
	game.attach(container, overlay)
	# J6-P1-1：--script 模式 autoload._ready 首帧才执行（探针实证），等一帧再开层。
	await process_frame

	# ---- 0. 场景存在；open_overlay 可创建覆盖层 ----
	check(ResourceLoader.exists(SCENE_PATH), "settings_panel.tscn 存在")
	if not ResourceLoader.exists(SCENE_PATH):
		finish()
		return
	var panel: Node = await _open_panel(game, overlay)
	check(panel != null, "open_overlay('settings') 创建设置覆盖层（常驻入口可达）")
	if panel == null:
		finish()
		return

	# ---- ① 根 Control 主题 + Dim ----
	check((panel as Control).theme != null, "①：覆盖层根 Control 已显式赋主题（J6-P1-1 纪律）")
	check(panel.get_node_or_null("Dim") is ColorRect, "①：Dim(ColorRect) 全屏遮罩存在")

	# ---- ② K1-1/K1-2/K1-6：居中 + 紧凑 + 毛玻璃 ----
	var pb: PanelContainer = panel.get_node_or_null("Panel") as PanelContainer
	check(pb != null, "②：Panel(PanelContainer) 存在")
	if pb != null:
		check(pb.anchor_left == 0.5 and pb.anchor_right == 0.5 and pb.anchor_top == 0.5 and pb.anchor_bottom == 0.5,
			"②：K1-1 Panel 屏幕正中（四 anchor==0.5）")
		check_eq(pb.custom_minimum_size, Vector2(460, 560), "②：K1-2 Panel 紧凑尺寸 460×560")
		var psb: StyleBoxFlat = pb.get_theme_stylebox("panel") as StyleBoxFlat
		check(psb != null and psb.bg_color.a < 0.7, "②：K1-6 Panel 毛玻璃半透明（bg a<0.7）")

	# ---- ③ M-A 反转（spec §3.1/§4.2，2026-09-07）：双入口 TextureButton→普通 Button，
	# 文字「图鉴」「商店」并入按钮、旁挂 Label 删除、图标清零；K7-6 置灰与光标语义保留 ----
	var vbox: Node = panel.get_node_or_null("Panel/VBox")
	check(vbox is VBoxContainer, "③：Panel/VBox(VBoxContainer) 存在")
	var title: Node = panel.get_node_or_null("Panel/VBox/Title")
	check(title is Label and String((title as Label).text) == "设置", "③：Title(Label「设置」) 存在")
	if title is Label:
		check_eq((title as Label).get_theme_font_size("font_size"), 28, "③：K1 标题字号 28")
		var tfont: Font = _font_of(title)
		check(tfont != null and String(tfont.resource_path).ends_with("MaShanZheng-Regular.ttf"), "③：标题字体指向马善政")
	var entry_box: Node = panel.get_node_or_null("Panel/VBox/EntryBox")
	check(entry_box is HBoxContainer, "③：EntryBox(HBoxContainer) 双入口行存在")
	var cat_entry: Button = null
	var shop_entry: Button = null
	if entry_box != null:
		cat_entry = entry_box.get_node_or_null("CatalogEntry") as Button
		shop_entry = entry_box.get_node_or_null("ShopEntry") as Button
	check(cat_entry != null, "③：CatalogEntry(Button) 存在（M 批 TextureButton→Button 反转留痕）")
	check(shop_entry != null, "③：ShopEntry(Button) 存在（M 批 TextureButton→Button 反转留痕）")
	if cat_entry != null:
		check(cat_entry.icon == null and cat_entry.get("texture_normal") == null,
			"③：M-A CatalogEntry 无任何贴图（icon/texture_normal 均 null，K1-3 反转留痕）")
		check_eq(String(cat_entry.text), "图鉴", "③：M-A CatalogEntry 文本「图鉴」（旁挂 Label 并入）")
		check_eq(cat_entry.custom_minimum_size, Vector2(140, 48), "③：M-A CatalogEntry 普通按钮尺寸 140×48（原 120² 大图标）")
		check_eq(cat_entry.disabled, not bool(save.can_open_catalog()),
			"③：K7-6→N10 图鉴入口 disabled==!can_open_catalog()（N批等价替换：原判据 is_first_launch()，2026-09-09 五路径修复，新档态两判据等价）")
		check_eq(cat_entry.mouse_default_cursor_shape, Control.CURSOR_FORBIDDEN, "③：K7-6 图鉴入口禁止光标（保留）")
		check(cat_entry.has_meta("hover_glow"), "③：K9 CatalogEntry 已挂 hover_glow meta（保留）")
	if shop_entry != null:
		check(shop_entry.icon == null and shop_entry.get("texture_normal") == null,
			"③：M-A ShopEntry 无任何贴图（icon/texture_normal 均 null，K1-3 反转留痕）")
		# 批次 AC 4A（spec §4.9，2026-09-27 用户追加需求）：商店改名「衣橱」——旧断言 "商店" 等价改写
		#（节点名 ShopEntry 与状态枚举 SHOP 不变，仅 UI 文本；检查项数不减）。
		check_eq(String(shop_entry.text), "衣橱", "③：AC §4.9 ShopEntry 文本「衣橱」（原「商店」等价改写）")
		check_eq(shop_entry.custom_minimum_size, Vector2(140, 48), "③：M-A ShopEntry 普通按钮尺寸 140×48")
		check_eq(shop_entry.mouse_default_cursor_shape, Control.CURSOR_POINTING_HAND, "③：商店入口手指光标（保留）")
		check(shop_entry.has_meta("hover_glow"), "③：K9 ShopEntry 已挂 hover_glow meta（保留）")
	var cat_label: Node = entry_box.get_node_or_null("CatalogLabel") if entry_box != null else null
	var shop_label: Node = entry_box.get_node_or_null("ShopLabel") if entry_box != null else null
	check(cat_label == null, "③：M-A CatalogLabel 旁挂标签已删除（文字并入按钮）")
	check(shop_label == null, "③：M-A ShopLabel 旁挂标签已删除（文字并入按钮）")

	# ---- ④ K1-4：点亮式开关组（Button toggle_mode，无「开启」前缀） ----
	# （批次 R 收口裁决 2026-09-14 主会话：旧断言「KbToggle 为 Button(toggle_mode)」随用户拍板
	#  「删键鼠交互开关」（spec §8.1）作废等价替换——改为 KbToggle 节点不存在 + GestureToggle 存在；
	#  批次 P test_settle_scene 退役语义改写 35→41 同款先例，全链只增不减等价替换口径记账）
	var options_box: Node = panel.get_node_or_null("Panel/VBox/OptionsBox")
	check(options_box is VBoxContainer, "④：OptionsBox(VBoxContainer) 存在")
	var toggle_names: Array[String] = ["GestureToggle", "HudToggle", "FullscreenToggle"]
	# 批次 AC（2026-09-27 领域八，spec §4.8/§5）：GestureToggle 文案加 `(Beta)` 角标
	# ——旧断言 "手势交互" 随用户拍板等价改写（检查项数不减：文本断言仍逐项在位）。
	var toggle_texts: Array[String] = ["手势交互 (Beta)", "显示手势状态区", "全屏显示"]
	var toggles: Array = []
	for i: int in range(toggle_names.size()):
		var t: Node = options_box.get_node_or_null(toggle_names[i]) if options_box != null else null
		check(t is Button and (t as Button).toggle_mode, "④：K1-4 %s 为 Button(toggle_mode)" % toggle_names[i])
		if t is Button:
			check_eq((t as Button).text, toggle_texts[i], "④：K1-4 %s 文本（无「开启」前缀）" % toggle_names[i])
		toggles.append(t)
	# 批次 R 作废等价替换：旧「④：K1-4 KbToggle 为 Button(toggle_mode)」作废，新契约断言如下
	check(options_box != null and options_box.get_node_or_null("KbToggle") == null,
		"④：批次 R 作废等价替换——KbToggle 节点已删（键鼠交互物理上永远可用，spec §8.1/§14-②）")
	var gt: Button = toggles[0] as Button
	var ht: Button = toggles[1] as Button
	var fs: Button = toggles[2] as Button
	var warn: Label = panel.get_node_or_null("Panel/VBox/WarningLabel") as Label
	check(warn is Label, "④：WarningLabel(Label) 存在")
	# 默认值（旧清单1 语义迁移）：手势/状态区默认开、警告空（批次 R：键鼠开关已删无默认值断言）
	if gt != null and ht != null:
		check(gt.button_pressed, "④：手势开关默认开")
		check(ht.button_pressed, "④：手势状态区默认开")
	if warn != null:
		check_eq(warn.text, "", "④：警告文本默认空")
	# 全屏开关（K8 无头守卫回显：headless is_fullscreen()==false 且隐藏）
	if fs != null:
		check_eq(fs.button_pressed, false, "④：K8 无头下 FullscreenToggle 回显非全屏")
		check_eq(fs.visible, false, "④：K8 无头下 FullscreenToggle 隐藏（窗口 API 守卫）")
		# K-H（P3①）：设置内全屏切换后须回写自绘三钮字形——接线段 set_fullscreen 与 refresh_state 同现
		var src: String = FileAccess.get_file_as_string("res://scenes/settings/settings_panel.gd")
		var fs_idx: int = src.find("WM.set_fullscreen")
		check(fs_idx >= 0 and src.find("refresh_state", fs_idx) > fs_idx,
			"K-H P3①：全屏接线后同步 WindowButtons.refresh_state 回写 □/❐ 字形")
	# 开态深棕族底+金描边 → 拨关灰卡（点亮式两态）
	# （P批等价替换 2026-09-10：原「开态金底 r>0.8」锁定亮金 (0.902,0.722,0,0.85)，P1 开关
	# 调深后开启态改深棕/暖棕底+金描边+浅字，判定等价替换为「深棕族底+有金描边」，
	# 全量色值口径见 test_p_wave1 段1）
	if gt != null:
		var on_sb: StyleBoxFlat = gt.get_theme_stylebox("normal") as StyleBoxFlat
		# 批次 AB-3：恒深档（is_dark() 与浅档底随深浅主题机制删除退役）
		var exp_on_bg: Color = Color(0.38, 0.27, 0.10, 0.85)
		check(on_sb != null and on_sb.bg_color == exp_on_bg,
			"④：K1-4 开态深棕族底（P批等价替换原亮金 r>0.8：深 (0.38,0.27,0.10) / 浅 (0.72,0.55,0.08)，a>0.6 保持）")
		check(on_sb != null and on_sb.border_width_top >= 2, "④：P1 开态金描边（border≥2，开启/关闭区分维度）")
	else:
		check(false, "④：GestureToggle 缺失，点亮式两态无法验证")

	# ---- 批次 T T12：ArrowBtn 段（ExclaimBtn 替换留痕）----
	var ab: Button = options_box.get_node_or_null("CameraRow/ArrowBtn") as Button
	check(ab != null, "T12：ArrowBtn 节点存在（ExclaimBtn 原位替换）")
	check_eq(ab.custom_minimum_size, Vector2(24, 24), "T12：ArrowBtn 24×24")
	check_eq(String(ab.text), "▾", "T12：ArrowBtn 文本「▾」")
	# 批次 U 等价替换（U2-2，双审 P1-1）：宿主迁独立层 65 → 路径 CameraMenuPopup 前增 CameraMenuLayer/
	check(panel.get_node_or_null("CameraMenuLayer/CameraMenuPopup") is PopupPanel, "T12：CameraMenuPopup(PopupPanel) 已挂载（批次 U：宿主迁 CameraMenuLayer 层 65）")

	# ---- ⑤ 开关即时保存（拨 false→落盘 false；拨回 true 恢复）+ 关态灰卡 ----
	if gt != null:
		gt.button_pressed = false  # 属性赋值即发 toggled → 即时保存（K1-4 新语义）
		var off_sb: StyleBoxFlat = gt.get_theme_stylebox("normal") as StyleBoxFlat
		check(off_sb != null and off_sb.bg_color.a < 0.5, "④：K1-4 拨关后灰卡（a<0.5）")
		check_eq(bool(save.get_settings()["gesture_input"]), false, "⑤：拨 false 即时持久化 gesture_input=false")
		gt.button_pressed = true
		check_eq(bool(save.get_settings()["gesture_input"]), true, "⑤：拨回 true 即时恢复 gesture_input=true")
	else:
		check(false, "⑤：GestureToggle 缺失，即时保存无法验证")
		check(false, "⑤：GestureToggle 缺失，即时恢复无法验证")

	# ---- ⑥ 批次 R 收口裁决（2026-09-14 主会话）作废等价替换：旧「至少一项输入约束：双关弹回
	#      +提示」随「删键鼠交互开关」拍板删除（spec §8.1——键鼠物理上永远可用 §14-②），旧断言
	#      「K1-4 双关时 KbToggle 弹回 true/约束提示/拒绝不落盘」作废；等价替换为新契约：
	#      同关校验函数 _on_input_toggled 已删 + 唯一手势开关单独关不再弹回/无警告（只增不减记账）----
	check(not (panel as Object).has_method("_on_input_toggled"),
		"⑥：批次 R 作废等价替换——同关校验 _on_input_toggled 已随拍板删除（spec §8.1）")
	if gt != null and warn != null:
		gt.button_pressed = false  # 唯一输入开关单独关=合法操作（不再即时拒绝）
		check_eq(warn.text, "", "⑥：批次 R 作废等价替换——单关手势无警告弹回（校验已删）")
		gt.button_pressed = true   # 恢复（段 11 重新拨关验证关闭语义，不受影响）
	else:
		check(false, "⑥：GestureToggle/WarningLabel 缺失，等价断言无法验证")

	# ---- ⑦ K1-5：音量紧凑网格（GridContainer 2 列 × 3 滑条，无语音） ----
	var vg: Node = panel.get_node_or_null("Panel/VBox/VolumeGrid")
	check(vg is GridContainer, "⑦：K1-5 VolumeGrid(GridContainer) 存在")
	var master_s: HSlider = null
	var music_s: HSlider = null
	var sfx_s: HSlider = null
	if vg != null:
		check_eq((vg as GridContainer).columns, 2, "⑦：K1-5 VolumeGrid columns==2")
		check_eq(vg.find_children("*", "HSlider", true, false).size(), 3, "⑦：K1-5 HSlider 恰 3 个（总/音乐/音效，无语音 Q&A7）")
		master_s = vg.get_node_or_null("MasterBox/Slider") as HSlider
		music_s = vg.get_node_or_null("MusicBox/Slider") as HSlider
		sfx_s = vg.get_node_or_null("SfxBox/Slider") as HSlider
	check(master_s is HSlider, "⑦：MasterBox/Slider(HSlider) 存在")
	check(music_s is HSlider, "⑦：MusicBox/Slider(HSlider) 存在")
	check(sfx_s is HSlider, "⑦：SfxBox/Slider(HSlider) 存在")
	if master_s != null:
		check(absf(master_s.min_value) < 0.001 and absf(master_s.max_value - 1.0) < 0.001, "⑦：MasterSlider 范围 0..1")
		check(master_s.custom_minimum_size.x >= 150.0, "⑦：K1-5 滑条紧凑最小宽 ≥150")
	var m_name: Node = vg.get_node_or_null("MasterBox/Name") if vg != null else null
	var mu_name: Node = vg.get_node_or_null("MusicBox/Name") if vg != null else null
	var sf_name: Node = vg.get_node_or_null("SfxBox/Name") if vg != null else null
	if m_name is Label:
		check_eq((m_name as Label).text, "总音量", "⑦：布局：总音量滑条文字标签")
	if mu_name is Label:
		check_eq((mu_name as Label).text, "音乐", "⑦：布局：音乐滑条文字标签")
	if sf_name is Label:
		check_eq((sf_name as Label).text, "音效", "⑦：布局：音效滑条文字标签")
	var m_val: Node = vg.get_node_or_null("MasterBox/Value") if vg != null else null
	if m_val is Label:
		check_eq((m_val as Label).text, "100%", "⑦：默认音量数值标签 100%")

	# ---- ⑧ K1-7 / ⑨ 旧长条入口已移除 ----
	var btn_box: Node = panel.get_node_or_null("Panel/VBox/ButtonBox")
	check(btn_box is HBoxContainer, "⑧：ButtonBox(HBoxContainer) 底部按钮行存在")
	var close_btn: Button = btn_box.get_node_or_null("CloseButton") as Button if btn_box != null else null
	check(close_btn != null, "⑧：CloseButton 存在")
	if close_btn != null:
		check_eq(close_btn.text, "关闭", "⑧：CloseButton 文本「关闭」（非「保存并关闭」）")
		check(close_btn.size_flags_horizontal != Control.SIZE_EXPAND_FILL, "⑧：K1-7 CloseButton 不横向撑满（无直角长条）")
	check(panel.get_node_or_null("Panel/VBox/ButtonBox/ShopButton") == null, "⑨：旧长条入口 ShopButton 已移除")
	check(panel.get_node_or_null("Panel/VBox/ButtonBox/CatalogButton") == null, "⑨：旧长条入口 CatalogButton 已移除")

	# ---- 10. 功能回归（旧清单4 迁移新路径）：音量变更即时持久化 + 总线联动 + 数值标签 ----
	if vg != null and music_s != null:
		var music_bus: int = AudioServer.get_bus_index("Music")
		var master_bus: int = AudioServer.get_bus_index("Master")
		music_s.value = 0.5  # value_changed → 即时保存 + apply_volumes
		var vol: Dictionary = save.get_settings()["volume"]
		check(absf(float(vol["music"]) - 0.5) < 0.001, "功能：音乐音量变更即时持久化（0.5）")
		check(absf(float(vol["master"]) - 1.0) < 0.001, "功能：总音量保持 1.0")
		check(absf(AudioServer.get_bus_volume_db(music_bus) - linear_to_db(0.5)) < 0.01, "功能：Music 总线 volume_db 与滑条联动")
		check(absf(AudioServer.get_bus_volume_db(master_bus) - linear_to_db(1.0)) < 0.01, "功能：Master 总线不受影响")
		var mu_val: Node = vg.get_node_or_null("MusicBox/Value")
		check(mu_val is Label and String((mu_val as Label).text) == "50%", "功能：数值标签随滑条刷新 50%")

	# ---- 11. K1-4 新语义：关闭只关面板（校验已前移开关即时拒绝），关闭前拨关手势 ----
	if gt != null and close_btn != null:
		gt.button_pressed = false  # 即时保存 gesture=false
		close_btn.pressed.emit()   # 关闭不再做任何输入校验，直接关面板
		await process_frame
		check(bool(game.has_open_overlay()) == false, "K1-4：CloseButton 只关面板（覆盖层已关）")
		check_eq(int(game.current_state()), st0, "K1-4：关闭不改主状态")
		check_eq(bool(save.get_settings()["gesture_input"]), false, "K1-4：关前面板时设置已即时落盘")
	else:
		check(false, "K1-4：GestureToggle/CloseButton 缺失，关闭语义无法验证")

	# ---- 12. 持久化文件 + 模拟重启读回（旧清单6/7 迁移新路径） ----
	check(FileAccess.file_exists(SAVE_PATH), "持久化：存档文件存在（update_settings 自动保存）")
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		check(typeof(parsed) == TYPE_DICTIONARY, "持久化：存档文件为合法 JSON")
		if typeof(parsed) == TYPE_DICTIONARY:
			var s6: Dictionary = parsed["settings"]
			check_eq(bool(s6["gesture_input"]), false, "持久化：文件 gesture_input=false")
			check_eq(bool(s6["kb_input"]), true, "持久化：文件 kb_input=true")
			check(absf(float(s6["volume"]["music"]) - 0.5) < 0.001, "持久化：文件音乐音量 0.5")
	else:
		check(false, "持久化：存档文件可读")
	save.load_game()  # 模拟重启读回
	var panel2: Node = await _open_panel(game, overlay)
	check(panel2 != null, "重启后可再次打开设置覆盖层")
	if panel2 != null:
		var gt2: Button = panel2.get_node_or_null("Panel/VBox/OptionsBox/GestureToggle") as Button
		var ms2: HSlider = panel2.get_node_or_null("Panel/VBox/VolumeGrid/MasterBox/Slider") as HSlider
		var mus2: HSlider = panel2.get_node_or_null("Panel/VBox/VolumeGrid/MusicBox/Slider") as HSlider
		check(gt2 != null and gt2.button_pressed == false, "重启：手势开关回显持久化值（关）")
		check(ms2 != null and absf(ms2.value - 1.0) < 0.001, "重启：总音量滑条回显 1.0")
		check(mus2 != null and absf(mus2.value - 0.5) < 0.001, "重启：音乐滑条回显持久化值 0.5")
		# 恢复默认值（避免影响后续断言与真实存档）
		if gt2 != null:
			gt2.button_pressed = true
		if mus2 != null:
			mus2.value = 1.0
	else:
		check(false, "重启：面板重开缺失，回显断言无法执行")

	# ---- 13. 双入口路由（M-A：TextureButton→Button 后接线零改动，路由断言按 Button 口径） ----
	if panel2 != null:
		var shop2: Button = panel2.get_node_or_null("Panel/VBox/EntryBox/ShopEntry") as Button
		check(shop2 != null and shop2.pressed.get_connections().size() >= 1, "路由：ShopEntry.pressed 已连接")
		if shop2 != null:
			shop2.pressed.emit()
			await process_frame
			check_eq(int(game.current_state()), st0, "路由：点商店入口不改主状态（覆盖层路由）")
			check(bool(game.has_open_overlay()), "路由：商店覆盖层已打开（open_overlay('shop')）")
			game.close_overlay()
			await process_frame
		var panel3: Node = await _open_panel(game, overlay)
		var cat3: Button = panel3.get_node_or_null("Panel/VBox/EntryBox/CatalogEntry") as Button if panel3 != null else null
		check(cat3 != null and cat3.pressed.get_connections().size() >= 1, "路由：CatalogEntry.pressed 已连接")
		if cat3 != null:
			cat3.pressed.emit()  # _on_catalog：关覆盖层 + goto CATALOG
			await process_frame
			check_eq(int(game.current_state()), ST_CATALOG, "路由：图鉴入口 → CATALOG 状态")
			check(bool(game.has_open_overlay()) == false, "路由：图鉴入口先关闭设置覆盖层")
	else:
		check(false, "路由：panel2 缺失，双入口路由无法验证")

	# ---- 14. 回修3（2026-09-08 用户实测「看过开场动画后悬停仍禁止符号但能点开」）：
	#      图鉴入口光标与可点性严格联动——未看过=disabled+禁止光标；看过=enabled+手型光标；
	#      open_overlay 每次新实例（主菜单/关卡内两条打开路径）→ _ready 即按存档状态刷新
	#      （N10 等价替换：判据改 can_open_catalog() 三分支，本段存档态 watched/cleared 均空，
	#      flag 翻转语义与回修3 等价，断言保留；仅 watched/仅 cleared 分支见 test_n10_catalog_gate）----
	game.close_overlay()
	await process_frame
	var panel4: Node = await _open_panel(game, overlay)
	check(panel4 != null, "回修3：可再次打开设置面板（光标联动验证载体）")
	if panel4 != null:
		var cat4: Button = panel4.get_node_or_null("Panel/VBox/EntryBox/CatalogEntry") as Button
		check(cat4 != null and cat4.disabled and int(cat4.mouse_default_cursor_shape) == int(Control.CURSOR_FORBIDDEN),
			"回修3：未看过开场动画 → disabled+禁止光标（可点性与光标语义一致）")
		if cat4 != null:
			check(cat4.pressed.get_connections().size() >= 1, "回修3：入口 pressed 已接线（看过即可点开）")
	# 模拟「看过开场动画一丢丢」——主菜单点开始游戏即写 flag（main_menu.gd mark_first_launch）
	save.mark_first_launch()
	await process_frame
	var panel5: Node = await _open_panel(game, overlay)
	check(panel5 != null, "回修3：看过后可再开面板（重开=新实例刷新路径）")
	if panel5 != null:
		var cat5: Button = panel5.get_node_or_null("Panel/VBox/EntryBox/CatalogEntry") as Button
		check(cat5 != null and not cat5.disabled and int(cat5.mouse_default_cursor_shape) == int(Control.CURSOR_POINTING_HAND),
			"回修3：看过开场动画 → enabled+手型光标（禁止符号不再残留）")
		# 状态翻转即时刷新（防面板开着时状态变化——_refresh_catalog_entry 双向）
		# （防御式断言：call 不存在方法会 SCRIPT ERROR 中止 _initialize 致无头挂死——先 has_method 探测）
		if cat5 != null and panel5.has_method("_refresh_catalog_entry"):
			var flag_abs: String = ProjectSettings.globalize_path("user://first_launch.flag")
			if FileAccess.file_exists(flag_abs):
				DirAccess.remove_absolute(flag_abs)
			panel5.call("_refresh_catalog_entry")
			check(cat5.disabled and int(cat5.mouse_default_cursor_shape) == int(Control.CURSOR_FORBIDDEN),
				"回修3：_refresh_catalog_entry 双向即时刷新（看过→未看过，disabled+禁止）")
			save.mark_first_launch()
			panel5.call("_refresh_catalog_entry")
			check(not cat5.disabled and int(cat5.mouse_default_cursor_shape) == int(Control.CURSOR_POINTING_HAND),
				"回修3：_refresh_catalog_entry 双向即时刷新（未看过→看过，enabled+手型）")
		else:
			check(false, "回修3：_refresh_catalog_entry 缺失（红灯占位）")
	game.close_overlay()
	await process_frame

	# ---- 批次 U（U5⑧/U1/U3/U7-4，6 checks）----
	# 磁盘实况适配留痕：计划原文用 `panel`——本文件夹具为 panel2..panel5 分段命名，此处经既有
	# _open_panel helper 另开一面板实例（夹具同源）；OVERLAY_TOP_FLOOR 读脚本常量（实例化前置，
	# get_script_constant_map 为 4.7 Script 常量正名 API——GDScript 资源 .get() 非 static 不可调）。
	var ud_script: GDScript = load("res://scenes/settings/settings_panel.gd")
	check_eq(float(ud_script.get_script_constant_map().get("OVERLAY_TOP_FLOOR")), 76.0,
		"U5⑧：OVERLAY_TOP_FLOOR=76.0（顶栏底 70＋6）")
	check(76.0 + 560.0 <= 648.0, "U5⑧：面板底 76+560=636 ≤648（避让后不出界）")
	save.update_settings({"gesture_input": true, "gesture_camera_enabled": true})
	var panel6: Node = await _open_panel(game, overlay)
	check(panel6 != null, "批次 U：设置面板可打开（UD-9 段夹具）")
	if panel6 != null:
		var ct3: Button = panel6.get_node("Panel/VBox/OptionsBox/CameraRow/CameraToggle")
		check_eq(String(ct3.text), "摄像头", "U1：Q1 态文本「摄像头」（面板级复核）")
		check(bool(ct3.button_pressed) and not bool(ct3.disabled), "U1：Q1 亮态 pressed（面板级复核）")
		# 批次 V（V-C4，spec §4.2）等价替换：q1_last_toast 观测成员随 Q1 拦截钩子退役
		#（旧「未点击时观测成员为空」作废；实例属性不存在=get null）
		check(panel6.get("q1_last_toast") == null, "V-C4：q1_last_toast 观测成员已退役（get null，旧 U1 观测断言等价替换留痕）")
		var q2_tips: Array = []
		for n9: Variant in panel6.find_children("*", "PanelContainer", true, false):
			if (n9 as Node).get_script() == load("res://scenes/shared/hover_tip.gd"):
				q2_tips.append(n9)
		check_eq(q2_tips.size(), 1, "U7-4：面板恰 1 个 HoverTip（CamTip 迁移单实例）")
	else:
		check(false, "批次 U：面板打开失败（红灯占位）")
		check(false, "U1：面板级复核占位")
		check(false, "U7-4：HoverTip 计数占位")
	game.close_overlay()
	await process_frame

	# ---- R2①-P2-6：LEVEL 态面板顶缘实例级行为锁（非仅常量锁，1 check）----
	# 直写 _state 绕开 goto_state 的切场景/BGM/皮肤副作用（--script 夹具无场景容器路由）；
	# 面板 _ready 钳制只读 current_state()（game.gd:41 单值直读），直写等价。断言面板顶缘
	# offset 实际 ≥ OVERLAY_TOP_FLOOR(76)——锁行为不只锁常量。
	var st_saved: int = int(game._state)
	game._state = int(game.State.LEVEL)
	var panel7: Node = await _open_panel(game, overlay)
	if panel7 != null:
		var top_px: float = float((panel7.get_node("Panel") as Control).offset_top)
		check(top_px >= float(ud_script.get_script_constant_map().get("OVERLAY_TOP_FLOOR")),
			"R2①-P2-6：LEVEL 态面板顶缘 offset 实际 ≥ OVERLAY_TOP_FLOOR(76)（实例级行为锁；实测 %s）" % top_px)
	else:
		check(false, "R2①-P2-6：LEVEL 态面板打开失败（红灯占位）")
	game._state = st_saved
	game.close_overlay()
	await process_frame

	_cleanup()
	finish()
