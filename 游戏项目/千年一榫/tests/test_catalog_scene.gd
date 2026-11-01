extends "res://tests/test_base.gd"
## T11 判定用例：图鉴外壳契约无头测试（TDD 先写；plan 步骤 1 手动清单 5 条全部脚本化）。
## 契约来源：实施计划 T11「契约」节（spec 4.6）：
##   节点：LeftInfo(PanelContainer：VBox→RefImage(TextureRect)+FourPoints(RichTextLabel))、
##        CenterMount(Control，T24 挂 point_cloud_viewer)、RightList(VBoxContainer 动态生成)、
##        BottomBar/EnterButton(Button「进入关卡」、初始禁用)、BottomBar/ExitButton(Button「退出」)；
##   列表：每关一行 Button——已通关→标题（LevelLibrary.get_level(ch).title，缺失回落「第N关」）；
##        未通关→「第N关 未完待续」且禁用；5 关全通后「未完待续」不再出现；
##        列表末尾另加一行「开场动画（回看）」；
##   选中项 _selected = {"kind":"chapter","chapter":int} 或 {"kind":"video"}；
##   进入关卡：选中章节 → goto_state(LEVEL, {chapter, replay:true})（重玩入口，场景缺失仅占位警告不崩溃）；
##   （J5-3/G4 契约变更）选中视频 → 不再路由 OPENING_MOVIE：中间区域挂内嵌预览播放器；
##   退出：goto_state(MAIN_MENU)（层级栈细化见 T29 走查）；
##   列表随 SaveManager.progress_changed 自动重建。
## 批次 H 追加契约（图鉴主体补全）：
##   选中已通关章节 → 左栏参考图/四要点联动 + 中央点云按章节重建（spec 9.1/9.2）；
##   未通关项禁用且无联动（点它不改变选中）；切换选中 → 参考图/点云随之切换。
## 批次 K-F（K7，spec §9）契约重写：
##   布局重排：根下 Background/Vignette + TitleBar + Body(HBox 三列：LeftInfo|CenterMount|RightBox)
##     + ControlBar（视频单层控制条）+ BottomBar；左侧占位提示文字删（K7-2）；
##     左信息框 L2 毛玻璃 12px 内边距透气（K7-3）；参考图 KEEP_ASPECT_CENTERED 入框（K7-4）；
##   默认选中（K7-5）：_ready 末尾 _select_video(null)，进图鉴即 kind=video、中央预览定格首帧；
##   视频单层整合（K7-7）：删「退出预览」按钮；
##     控制条三件套 PlayPauseBtn（播放暂停合一）+ TimeSlider（可拖时间轴）
##     + TimeLabel（mm:ss / mm:ss）；seek 内部状态 =_video_duration/_video_pos/_seek_video；
##   右侧可收起侧边栏（K7-7）：RightToggle 切换 RightScroll 显隐；
##   J6 视频规避实现全部保留（K-F 严禁顺手清理）：PREVIEW_SETTLE_FRAMES=3 首帧定格放行、
##     stream_position/get_stream_length（4.7 无 seek()/pause()/Theora.get_length()/get_fps() 无头挂死）。
##   点云旋转缩放/四要点/重玩入口既有功能不回归。
## 批次 M-F（spec §3.6）等价替换留痕（2026-09-08，总量只增不减）：
##   ① 控制条层级迁移：ControlBar 从页面级 HBox 降为 VideoPreview 内悬浮 PanelContainer
##     （路径 .../VideoPreview/ControlBar/BarRow/*；K7-7「ControlBar/PlayPauseBtn」页面级路径
##     按新结构等价改写，行为语义不变：视频态显示/章节态隐藏）；
##   ② 全屏层回归：K7-7「VideoFullscreenLayer 已删除」断言按 M-F 验收反转（M-F 重新引入
##     单播放器 reparent 全屏层 CanvasLayer(layer=62，批次 Z Z6-P2-1 由 90 降层——黑底不再
##     压 TopStrip63/HUD64；layer>1 断言归 test_m_video_player.gd，FS_LAYER_ID 断言归
##     test_z_defects.gd）；
##   ③ RightBox 改 PanelContainer 毛玻璃背板，内容迁入 RightInner（RightList 路径加一层
##     RightInner，列表/收起钮行为语义零变化）；
##   ④ 右上设置钮避让：RightBox 顶部 44px spacer（列表首行全局顶 ≥108，锚点断言归
##     test_m_video_player.gd）。
## 环境说明（同 T08~T10 测试）：--script 无头模式主脚本编译期不能直接写全局标识符，
## 故经 get_root().get_node 取 Variant 动态引用。枚举值：
##   BOOT=0 MAIN_MENU=1 OPENING_MOVIE=2 TALK=3 LEVEL=4 SETTLE=5 CATALOG=6。

const SCENE_PATH := "res://scenes/catalog/catalog_scene.tscn"
const SAVE_PATH := "user://save.json"

const ST_MAIN_MENU := 1
# J5-3（G4）：视频回看改内嵌播放器后本测试不再断言 OPENING_MOVIE 路由，常量随之删除。
const ST_LEVEL := 4
const ST_CATALOG := 6

func _cleanup() -> void:
	var save_abs: String = ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(save_abs):
		DirAccess.remove_absolute(save_abs)

## 等待两帧：让 queue_free 的旧列表项离场、信号触发的重建稳定
func _settle() -> void:
	await process_frame
	await process_frame

## 路由进入图鉴并返回场景实例（等待一帧让 _ready/布局稳定）
func _open_catalog(game: Variant, container: Control) -> Node:
	game.goto_state(ST_CATALOG)
	await process_frame
	if container.get_child_count() == 0:
		return null
	return container.get_child(container.get_child_count() - 1)

## 递归查找 CenterMount 下挂载的 PointCloudViewer（按脚本判定，批次 H）
func _find_viewer(node: Node) -> Control:
	if node.get_script() == load("res://scripts/point_cloud_viewer.gd"):
		return node as Control
	for c: Node in node.get_children():
		var found: Control = _find_viewer(c)
		if found != null:
			return found
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
const DISC_BK_PREFIX := "user://_r2b_cat_backup_"
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
	print("EVID|user_restore|cat|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_catalog_scene ==")
	_backup_user()
	var save: Variant = get_root().get_node("SaveManager")
	var game: Variant = get_root().get_node("Game")
	var lib: Variant = get_root().get_node("LevelLibrary")

	_cleanup()
	save.load_game()  # 重置为默认存档（cleared=[]，next_chapter=1）

	# Game 路由环境准备：场景容器 + 覆盖层层（等价 main.tscn 的 attach）
	var container: Control = Control.new()
	add_child(container)
	var overlay: CanvasLayer = CanvasLayer.new()
	add_child(overlay)
	game.attach(container, overlay)

	# ---- 1. 场景存在；路由常量已指向本场景；K-F 三列布局与契约一致（清单①）----
	check(ResourceLoader.exists(SCENE_PATH), "catalog_scene.tscn 存在")
	if not ResourceLoader.exists(SCENE_PATH):
		finish()
		return
	var panel: Node = await _open_catalog(game, container)
	check(panel != null, "goto_state(CATALOG) 创建图鉴场景（Game 路由常量生效）")
	if panel == null:
		finish()
		return
	check_eq(int(game.current_state()), ST_CATALOG, "当前状态为 CATALOG")
	check(panel is Control, "根节点为 Control")
	# K7-1：贴主题底（渐晕）替代灰底 + 标题条 + Body 三列
	check(panel.get_node_or_null("Background") is TextureRect, "K7-1：Background 章节主题背景层存在（灰色不符主题底已替代）")
	var vg_node: TextureRect = panel.get_node_or_null("Vignette") as TextureRect
	check(vg_node is TextureRect, "K7-1：Vignette 渐晕层存在（关卡同族）")
	check(vg_node != null and vg_node.texture is GradientTexture2D, "K7-1：渐晕为运行时径向渐变纹理")
	var title_bar: PanelContainer = panel.get_node_or_null("TitleBar") as PanelContainer
	check(title_bar != null, "K7-1：TitleBar 标题条（PanelContainer）存在")
	if title_bar != null:
		var title_lbl: Label = title_bar.get_node_or_null("Title") as Label
		check(title_lbl != null and title_lbl.text == "图鉴", "K7-1：TitleBar 含标题「图鉴」")
		var tbsb: StyleBoxFlat = title_bar.get_theme_stylebox("panel") as StyleBoxFlat
		check(tbsb != null and tbsb.bg_color.a < 0.7, "K7-1：标题条毛玻璃半透明（L2 卡层）")
	var body: HBoxContainer = panel.get_node_or_null("Body") as HBoxContainer
	check(body != null, "K7-1：Body(HBoxContainer) 三列主体存在")
	if body != null:
		check_eq(body.get_child_count(), 3, "K7-1：Body 三列（左信息|中央展示|右列表）")
		check_eq(String(body.get_child(0).name), "LeftInfo", "K7-1：第一列=LeftInfo")
		check_eq(String(body.get_child(1).name), "CenterMount", "K7-1：第二列=CenterMount")
		check_eq(String(body.get_child(2).name), "RightBox", "K7-1：第三列=RightBox")
		# J6-P2-7 避让语义随 K-F 重排迁移：整条 Body 顶缘让出右上全局设置按钮区（≥64）
		check((body as Control).offset_top >= 64.0, "J6-P2-7→K-F：Body offset_top≥64 避让右上全局设置按钮")
		check(body.get_child(1).get("size_flags_horizontal") != null
			and int((body.get_child(1) as Control).size_flags_horizontal) == int(Control.SIZE_EXPAND_FILL),
			"K7-1：中央展示区横向扩展（收起侧边栏时自动占位）")
	var left_info: PanelContainer = panel.get_node_or_null("Body/LeftInfo") as PanelContainer
	check(left_info != null, "K7-1：Body/LeftInfo(PanelContainer) 左侧信息栏")
	check(left_info != null and (left_info as Control).custom_minimum_size.x >= 300.0,
		"K7-1：左信息框最小宽 ≥300（plan 定 320）")
	check(panel.get_node_or_null("Body/LeftInfo/VBox") is VBoxContainer, "清单①：LeftInfo/VBox 存在")
	check(panel.get_node_or_null("Body/LeftInfo/VBox/FourPoints") is RichTextLabel, "清单①⑦：FourPoints(RichTextLabel) 四要点")
	var center_mount: Control = panel.get_node_or_null("Body/CenterMount") as Control
	check(center_mount is Control, "清单①：Body/CenterMount(Control) 中央点云/视频容器")
	var right_box: PanelContainer = panel.get_node_or_null("Body/RightBox") as PanelContainer
	check(right_box != null, "K7-7→M-F：Body/RightBox(PanelContainer 毛玻璃背板) 右侧列表盒（内容在 RightInner）")
	var right_scroll: ScrollContainer = panel.get_node_or_null("Body/RightBox/RightInner/RightScroll") as ScrollContainer
	check(right_scroll != null, "清单①：Body/RightBox/RightInner/RightScroll(ScrollContainer) 右侧列表滚动容器")
	check(right_scroll != null and (right_scroll as Control).custom_minimum_size.x >= 240.0,
		"K7-7：右列表最小宽 ≥240（plan 定 260）")
	check(panel.get_node_or_null("Body/RightBox/RightInner/RightScroll/RightList") is VBoxContainer, "清单①：RightList(VBoxContainer) 右侧关卡列表")
	check(panel.get_node_or_null("BottomBar") is HBoxContainer, "清单①：BottomBar(HBoxContainer) 底部按钮区")
	var enter_btn: Button = panel.get_node_or_null("BottomBar/EnterButton")
	var exit_btn: Button = panel.get_node_or_null("BottomBar/ExitButton")
	check(enter_btn != null, "清单①：EnterButton(Button) 存在")
	check(exit_btn != null, "清单①：ExitButton(Button) 存在")
	if enter_btn != null:
		# K7-5 → 回修3（2026-09-08 用户反馈冗余）：视频态右下「播放」钮删除（控制条悬浮播控已覆盖），
		# 等价替换：默认选中视频 → EnterButton 隐藏（disabled 口径保留防回归）
		check(not enter_btn.visible, "K7-5→回修3：默认选中视频 → 底部「播放」钮隐藏（冗余删除，等价替换）")
		check(not enter_btn.disabled, "K7-5：默认选中后底部按钮可用性不回归（隐藏非禁用）")
	if exit_btn != null:
		check_eq(exit_btn.text, "退出", "ExitButton 文本「退出」")

	# K-F 红灯快速门（同既有 panel==null 早退风格）：新布局结构缺失 → 上方断言已记红，
	# 此处 finish 早退，防后续深层取节点/直调方法空引用崩溃挂死无头测试进程。
	# M-F 等价替换：ControlBar 路径随悬浮层迁移更新（VideoPreview 子层 BarRow）。
	if panel.get_node_or_null("Body/LeftInfo/VBox/FourPoints") == null \
			or panel.get_node_or_null("Body/RightBox/RightInner/RightScroll/RightList") == null \
			or panel.get_node_or_null("Body/CenterMount/VideoPreview/ControlBar/BarRow/PlayPauseBtn") == null \
			or panel.get_node_or_null("TitleBar") == null:
		_cleanup()
		finish()
		return

	# ---- 1.5 批次 J5-1（G2 保留）+ K7-2/3/4 → 批次 O1 等价替换（2026-09-10）：
	# G1 径向渐变羽化层 RefFade 按用户反馈整体删除（红圈渐变），原「羽化层存在/纹理/显隐」
	# 断言组等价替换为「RefFade 已删 + RefFrame 画框（边框/阴影/圆角）」断言组；
	# K7-4 参考图入框路径随画框包裹迁移（RefFrame/RefImage），等比居中口径不变。 ----
	var ref_fade: TextureRect = panel.get_node_or_null("Body/LeftInfo/VBox/RefFrame/RefFade")
	check(ref_fade == null, "O1 批等价替换：G1 羽化层 RefFade 已删（用户红圈渐变，P3-2 显隐守卫随之失效无残留）")
	var ref_frame: PanelContainer = panel.get_node_or_null("Body/LeftInfo/VBox/RefFrame") as PanelContainer
	check(ref_frame is PanelContainer, "O1 批等价替换：RefFrame(PanelContainer) 画框存在（替代羽化层的装裱方案）")
	if ref_frame != null:
		var ofsb: StyleBoxFlat = ref_frame.get_theme_stylebox("panel") as StyleBoxFlat
		check(ofsb != null and ofsb.border_width_top >= 2 and ofsb.shadow_size >= 8,
			"O1 批等价替换：画框随主题生成（边框≥2px+阴影≥8，与 G1「程序化随主题」语义等价）")
	# K7-2：左侧占位提示文字已删（tscn 不再含该默认文本；节点保留为空的 FourPoints）
	var tscn_text: String = FileAccess.get_file_as_string(SCENE_PATH)
	check(not tscn_text.contains("选择右侧已通关关卡"), "K7-2：左侧占位提示文字已从 tscn 删除")
	var fp_init: RichTextLabel = panel.get_node("Body/LeftInfo/VBox/FourPoints")
	# O2 批等价替换（2026-09-10）：默认选中开场动画项 → 左下显示 OPENING_INTRO 短文案
	# （原 K7-2「初始四要点区无占位提示文字」的空文案口径随开场项配图+文案联动退役）
	var intro_txt: String = String(panel.get("OPENING_INTRO"))
	check(intro_txt.is_empty() or String(fp_init.text) == intro_txt,
		"O2 批等价替换：初始四要点区=开场项短文案 OPENING_INTRO（原空文案口径随联动退役）")
	# K7-3：左信息框 L2 毛玻璃圆角透气（运行时随主题覆写：半透明/圆角≥12/12px 内边距/投影）
	var li: PanelContainer = panel.get_node("Body/LeftInfo")
	var lisb: StyleBoxFlat = li.get_theme_stylebox("panel") as StyleBoxFlat
	check(lisb != null and lisb.bg_color.a < 0.9, "G2：图鉴 LeftInfo 面板毛玻璃半透明")
	check(lisb != null and lisb.bg_color.a < 0.7 and lisb.bg_color.a > 0.2, "K7-3：LeftInfo L2 卡层半透明（0.2<a<0.7）")
	check(lisb != null and lisb.corner_radius_top_left >= 12, "K7-3：LeftInfo 圆角（≥12 卡层档）")
	check(lisb != null and lisb.content_margin_left >= 12.0 and lisb.content_margin_top >= 12.0,
		"K7-3：LeftInfo 12px 内边距透气（左框不透气问题）")
	check(lisb != null and lisb.shadow_size >= 8, "K7-3：LeftInfo 柔投影（毛玻璃三层之一）")
	# K7-4：参考图放进框内（等比居中、最小高 ≥200，plan 定 220；悬框外问题修复）
	# O1 批等价替换：路径随画框包裹迁移（RefFrame/RefImage），口径不变
	var ref_img0: TextureRect = panel.get_node("Body/LeftInfo/VBox/RefFrame/RefImage")
	check(int(ref_img0.stretch_mode) == int(TextureRect.STRETCH_KEEP_ASPECT_CENTERED),
		"K7-4：RefImage KEEP_ASPECT_CENTERED 等比居中入框")
	check(ref_img0.custom_minimum_size.y >= 200.0, "K7-4：RefImage 最小高 ≥200（信息框内上图区）")
	var center_pad: Panel = panel.get_node_or_null("Body/CenterMount/CenterPad") as Panel
	check(center_pad is Panel, "G2：中央展示区极淡内衬 CenterPad 存在")
	if center_pad != null:
		var psb: StyleBoxFlat = center_pad.get_theme_stylebox("panel") as StyleBoxFlat
		check(psb != null and psb.bg_color.a > 0.0 and psb.bg_color.a <= 0.15,
			"G2：内衬极淡（0<alpha<=0.15）区分展示区且非实心")
		check(int(center_pad.mouse_filter) == int(Control.MOUSE_FILTER_IGNORE), "G2：内衬不吃输入")
	var fp_check: RichTextLabel = panel.get_node("Body/LeftInfo/VBox/FourPoints")
	check(fp_check.has_theme_color_override("default_color"), "G2：四要点文字色已按主题显式覆写")

	# ---- 2. 清单②：默认未通关 → 5 行「未完待续」禁用 + 清单③：视频回看项 ----
	var right_list: VBoxContainer = panel.get_node("Body/RightBox/RightInner/RightScroll/RightList")
	check_eq(right_list.get_child_count(), 6, "列表共 6 项（5 关 + 开场动画回看）")
	for i: int in range(5):
		var b: Button = right_list.get_child(i)
		check_eq(b.text, "第%d关 未完待续" % (i + 1), "清单②：第%d关未通关显示「未完待续」" % (i + 1))
		check(b.disabled, "清单②：第%d关未通关禁用" % (i + 1))
	var video_btn: Button = right_list.get_child(5)
	check_eq(video_btn.text, "开场动画（回看）", "清单③：列表含「开场动画（回看）」项")
	check(not video_btn.disabled, "视频回看项可点击")
	# 审查回修 P2-1 护栏：K7-5 默认选中态 → 回看项已套金黄高亮
	# （_select_video(null) 前置于 _rebuild_list，重建尾部 J6-P2-4 分支自动补高亮）
	var vgold: StyleBoxFlat = video_btn.get_theme_stylebox("normal") as StyleBoxFlat
	check(vgold != null and vgold.border_width_top >= 2 and vgold.border_color.r > 0.8
		and vgold.border_color.g > 0.6 and vgold.border_color.b < 0.5,
		"P2-1：默认选中「开场动画（回看）」项带金黄高亮（与章节选中一致）")

	# ---- 3. progress_changed 订阅：通关第 1 关 → 列表自动重建（行 1 脱离未完待续）----
	var conns: Array = save.progress_changed.get_connections()
	check(conns.size() >= 1, "progress_changed 已连接（列表随存档进度自动刷新）")
	save.advance_progress(1)  # cleared=[1]，next_chapter=2
	await _settle()
	var b1: Button = right_list.get_child(0)
	check(not b1.text.contains("未完待续"), "清单②：通关后第1关脱离「未完待续」")
	check(not b1.disabled, "清单②：通关后第1关可选")
	check((right_list.get_child(1) as Button).text.contains("未完待续"), "未通关的第2关仍「未完待续」")
	check_eq(right_list.get_child_count(), 6, "重建后列表仍 6 项（旧项已释放）")

	# ---- 4. 标题分支：关卡库有数据时已通关行显示标题 ----
	lib.scan_directory("res://tests/fixtures")  # valid_chapter1.json（title=河姆渡榫卯木构件）
	panel.call("_rebuild_list")
	await _settle()
	check_eq((right_list.get_child(0) as Button).text, "河姆渡榫卯木构件", "清单②：已通关关卡显示标题（关卡库数据）")

	# ---- 5. 清单④前半：选中已通关关卡 → 「进入关卡」可用；左侧占位填充；_selected 结构 ----
	var btn1: Button = right_list.get_child(0)
	btn1.pressed.emit()
	check(not enter_btn.disabled, "清单④：选中已通关关卡 →「进入关卡」可用")
	check_eq(enter_btn.text, "进入关卡", "K7-7：选中章节后底部按钮文本回「进入关卡」")
	var sel: Dictionary = panel.get("_selected")
	check_eq(sel.get("kind"), "chapter", "_selected.kind=chapter")
	check_eq(int(sel.get("chapter", 0)), 1, "_selected.chapter=1")
	var four_points: RichTextLabel = panel.get_node("Body/LeftInfo/VBox/FourPoints")
	check(not four_points.text.is_empty(), "左侧四要点占位文本非空（正式文案属 T24）")
	var sel_btn: Button = right_list.get_child(0)
	var gold_sb: StyleBoxFlat = sel_btn.get_theme_stylebox("normal") as StyleBoxFlat
	check(gold_sb != null and gold_sb.border_width_top >= 2
		and gold_sb.border_color.r > 0.8 and gold_sb.border_color.g > 0.6
		and gold_sb.border_color.b < 0.5, "G2：选中项按钮高亮金黄边")

	# ---- 5b. 批次 H：选中联动——左栏参考图/四要点 + 中央 PointCloudViewer 挂真实点云 ----
	# O1 批等价替换：参考图路径随画框迁移；原 P3-2「RefFade 恢复显示」断言随羽化层删除退役。
	var ref_img: TextureRect = panel.get_node("Body/LeftInfo/VBox/RefFrame/RefImage")
	check(ref_img.texture != null and ref_img.texture.resource_path.contains("ref_chapter1.png"),
		"批次H：选中第1关 → RefImage 显示 ref_chapter1.png")
	check(four_points.text.contains("时间") and four_points.text.contains("地点")
		and four_points.text.contains("类型") and four_points.text.contains("历史意义"),
		"批次H：四要点占位含 时间/地点/类型/历史意义 四栏（简短史实占位，正式文案待用户审核）")
	check(right_list.get_child_count() == 6, "批次H：选中联动后列表仍 6 项（开场视频项保留）")
	var center: Control = panel.get_node("Body/CenterMount")
	var viewer: Control = _find_viewer(center)
	check(viewer != null, "批次H：CenterMount 挂载 PointCloudViewer（scripts/point_cloud_viewer.gd）")
	var real1: Resource = load(lib.call("get_points_path", 1))
	var n1: int = (real1 as PointCloudData).points.size() if real1 != null else -1
	check(viewer != null and int(viewer.call("get_instance_count")) == n1,
		"批次H：viewer 已 build 真实章节点云（instance_count=%d）" % n1)

	# ---- 5b2. J5-2（G3）：图鉴侧 viewer 金黄 tint 设参（回归保护，零改动）。
	# 4.7 无头 MultiMesh 逐实例色/transform CPU 读回恒 0（J4-2 实证，引擎读侧限制非缺陷），
	# 故不写 get_instance_color 断言——tint 生效证据链=属性分量 + use_colors 门 + 材质标志。 ----
	if viewer != null:
		var g3_tc: Variant = viewer.get("tint_color")
		check(g3_tc is Color and (g3_tc as Color).a > 0 and absf((g3_tc as Color).r - 0.96) < 0.02
			and absf((g3_tc as Color).g - 0.77) < 0.02 and absf((g3_tc as Color).b - 0.26) < 0.02,
			"G3：图鉴点云金黄 tint 已设（≈#F5C542，色分量判定非裸 !=null）")
		var g3_ts: Variant = viewer.get("tint_strength")
		check(typeof(g3_ts) == TYPE_FLOAT and absf(float(g3_ts) - 0.85) < 0.001,
			"G3：图鉴 tint 强度=0.85（计划暂定值，TODO J6 走查后微调）")
		var g3_ps: Variant = viewer.get("point_size")
		# J6r3-2：复走查 4x 放大判 0.008 主体仍融合 → 再降档 0.005（可显单点）
		check(typeof(g3_ps) == TYPE_FLOAT and float(g3_ps) >= 0.004 and float(g3_ps) <= 0.006,
			"J6r3-2：图鉴点尺寸在 0.004~0.006 档（0.005 显单点）")
		var g3_pc_mesh: MultiMeshInstance3D = viewer.get_node_or_null(
			"CloudContainer/CloudViewport/CloudWorld/CloudPivot/PointCloud") as MultiMeshInstance3D
		# O批并行等价替换（2026-09-10，动画域圆点化）：点云 mesh 由 BoxMesh(0.005) 改 QuadMesh
		# （DOT_SIZE_MIN 单向下限，0.005 实设被上调至下限档）——原「BoxMesh 实际边长=0.005」
		# 断言等价替换为「QuadMesh 且边长 ≥0.005（下限钳制语义）」。
		check(g3_pc_mesh != null and g3_pc_mesh.multimesh != null and g3_pc_mesh.multimesh.mesh != null
			and (g3_pc_mesh.multimesh.mesh as QuadMesh) != null
			and (g3_pc_mesh.multimesh.mesh as QuadMesh).size.x >= 0.005,
			"O批并行等价替换：图鉴点云圆点化 QuadMesh 边长 ≥0.005（DOT_SIZE_MIN 单向下限）")
		var g3_pc: MultiMeshInstance3D = viewer.get_node_or_null(
			"CloudContainer/CloudViewport/CloudWorld/CloudPivot/PointCloud") as MultiMeshInstance3D
		check(g3_pc != null and g3_pc.multimesh != null and g3_pc.multimesh.use_colors,
			"G3：use_colors 门已开（tint 逐实例 lerp 落点生效，原色数据等长）")
		var g3_mat: Material = viewer.call("get_cloud_material")
		# M 批等价替换（2026-09-08 M-Ga，唯一一条断言随 viewer 组件材质升级同步）：点云材质
		# 升级为内嵌涟漪 ShaderMaterial（shader vertex 位移路线），显示口径语义等价——
		# 旧 shading_mode==UNSHADED ↔ render_mode unshaded；旧 vertex_color_use_as_albedo ↔ COLOR→ALBEDO 透传。
		check(g3_mat is ShaderMaterial
			and String((g3_mat as ShaderMaterial).shader.code).contains("unshaded")
			and absf(float((g3_mat as ShaderMaterial).get_shader_parameter("u_use_vertex_color")) - 1.0) < 0.0001,
			"G3：材质保持 unshaded+逐实例色透传（M 批等价替换：涟漪 ShaderMaterial，274085a 口径不回退）")
	else:
		for _g3: int in 5:
			check(false, "G3：viewer 缺失，关联断言记红")

	# ---- 5c. 批次 H：未通关章节不可选（无联动：选中态不变）----
	var before_sel: Dictionary = panel.get("_selected").duplicate(true)
	var locked2: Button = right_list.get_child(1)  # 第 2 关未通关
	check(locked2.disabled, "批次H：未通关第2关禁用（不可选）")
	locked2.pressed.emit()  # 未通关项不应连接任何选中处理器
	var after_sel: Dictionary = panel.get("_selected")
	check_eq(after_sel.get("kind", ""), before_sel.get("kind", ""), "批次H：点未通关项不改变选中（无联动）")
	check_eq(int(after_sel.get("chapter", -1)), int(before_sel.get("chapter", -1)), "批次H：无联动（chapter 不变）")

	# ---- 5d. J6-P2-4：progress_changed 重建列表后选中高亮不丢（_selected 未变 → 新按钮重套高亮）----
	save.advance_progress(2)  # 触发 progress_changed → _rebuild_list（旧按钮 queue_free）
	await _settle()
	var sel_5d: Dictionary = panel.get("_selected")
	check_eq(String(sel_5d.get("kind", "")), "chapter", "J6-P2-4：重建后选中 kind 不变")
	check_eq(int(sel_5d.get("chapter", -1)), 1, "J6-P2-4：重建后选中 chapter 不变")
	var btn0_new: Button = right_list.get_child(0)
	var gold_5d: StyleBoxFlat = btn0_new.get_theme_stylebox("normal") as StyleBoxFlat
	check(gold_5d != null and gold_5d.border_width_top >= 2 and gold_5d.border_color.r > 0.8,
		"J6-P2-4：重建后第1关新按钮已重套金黄高亮")

	# ---- 6. 清单⑤：退出按钮回主菜单 ----
	exit_btn.pressed.emit()
	await process_frame
	check_eq(int(game.current_state()), ST_MAIN_MENU, "清单⑤：退出回主菜单")

	# ---- 7. 清单④后半：进入关卡 → LEVEL + {chapter, replay:true}（场景缺失仅警告不崩溃）----
	panel = await _open_catalog(game, container)
	check(panel != null, "可再次进入图鉴")
	if panel == null:
		_cleanup()
		finish()
		return
	right_list = panel.get_node("Body/RightBox/RightInner/RightScroll/RightList")
	(right_list.get_child(0) as Button).pressed.emit()
	enter_btn = panel.get_node("BottomBar/EnterButton")
	enter_btn.pressed.emit()
	await process_frame
	check_eq(int(game.current_state()), ST_LEVEL, "清单④：路由至 LEVEL（重玩进入）")
	check_eq(int(game.context().get("chapter", -1)), 1, "清单④：ctx.chapter=1")
	check(bool(game.context().get("replay", false)), "清单④：ctx.replay=true")
	check(bool(game.is_replay()), "清单④：Game.is_replay()=true")

	# ---- 8. K-F（K7-7）：视频单层播放——预览即播放层（中央 VideoPreview + M-F 悬浮 ControlBar），
	#      「退出预览」按钮已删；回看不再路由 OPENING_MOVIE。M-F 等价替换：第二层全屏播放界面
	#      在 M-F 重新引入（单播放器 reparent 全屏层，spec §3.6），下方断言按新验收反转留痕。
	#      无头不产帧：结构=节点/属性断言；播放态推进不可测 → seek 直调方法验证内部状态；
	#      播完路径用手动 finished.emit() 驱动（不依赖真实解码）。 ----
	panel = await _open_catalog(game, container)
	check(panel != null, "可再次进入图鉴（视频项路径）")
	if panel == null:
		_cleanup()
		finish()
		return
	right_list = panel.get_node("Body/RightBox/RightInner/RightScroll/RightList")
	enter_btn = panel.get_node("BottomBar/EnterButton")
	# ① 删除/回归清单（K7-7 + M-F 反转）：冗余退出预览按钮 + 旧预览区控件已迁走；
	#    M-F 全屏层回归为 CanvasLayer 结构（行为断言归 test_m_video_player.gd）
	check(panel.get_node_or_null("VideoFullscreenLayer") is CanvasLayer,
		"M-F 等价替换：全屏层回归（CanvasLayer 结构，K7-7「已删除」断言按 M-F 验收反转）")
	check(panel.get_node_or_null("Body/CenterMount/VideoExitBtn") == null, "K7-7：冗余「退出预览」按钮已删除")
	check(panel.get_node_or_null("Body/CenterMount/VideoScrub") == null, "K7-7：旧预览区时间轴已移入控制条")
	check(panel.get_node_or_null("Body/CenterMount/VideoPlayBtn") == null, "K7-7：旧预览区播放钮已移入控制条")
	# ⑤ 默认选中（K7-5）：进图鉴即选中开场动画
	check(String(panel.get("_selected").get("kind")) == "video", "K7-5：进图鉴默认选中开场动画")
	var vp: VideoStreamPlayer = panel.get_node_or_null("Body/CenterMount/VideoPreview") as VideoStreamPlayer
	check(vp != null, "K7-7：Body/CenterMount 下 VideoPreview(VideoStreamPlayer) 唯一播放器存在")
	check(vp != null and vp.stream != null, "K7-7：预览播放器已挂开场动画.ogv 视频源")
	check(vp != null and vp.visible, "K7-5：默认选中视频 → 中央预览可见（定格首帧）")
	# ② 悬浮控制条三件套（视频选中态显示；M-F：层级从页面级迁至 VideoPreview 子层）
	var cbar: PanelContainer = panel.get_node_or_null("Body/CenterMount/VideoPreview/ControlBar") as PanelContainer
	check(cbar != null and cbar.visible, "K7-7→M-F：ControlBar(PanelContainer 悬浮层) 存在且视频态显示")
	# K-F 窗口自查回修护栏（kf_01 截图实证根因）：VideoStreamPlayer 的 min 尺寸由**其自身
	# expand(bool)**决定（非 TextureRect.expand_mode，误用则 rect=纹理 1280×720 居中溢出
	# 盖住左信息框/标题条）。无头不做容器排布（size 恒 0 不可断），故断 expand 属性根因；
	# 观感=窗口截图判定（kf_01 复拍）。
	check(bool(vp.get("expand")), "K7-7：VideoPreview expand=true（min 尺寸不受纹理尺寸驱动，防溢出铺屏）")
	var ppb: Button = panel.get_node_or_null("Body/CenterMount/VideoPreview/ControlBar/BarRow/PlayPauseBtn") as Button
	var tsld: HSlider = panel.get_node_or_null("Body/CenterMount/VideoPreview/ControlBar/BarRow/TimeSlider") as HSlider
	var tlbl: Label = panel.get_node_or_null("Body/CenterMount/VideoPreview/ControlBar/BarRow/TimeLabel") as Label
	check(ppb != null, "K7-7：播放/暂停合一按钮 PlayPauseBtn(Button) 存在")
	check(tsld != null, "K7-7：可拖动时间轴 TimeSlider(HSlider) 存在")
	check(tlbl != null, "K7-7：时间显示 TimeLabel(Label) 存在")
	if ppb != null:
		# 回修3（2026-09-08 用户反馈）：合一按钮符号化——▶/⏸ 自绘图标替代文字（text 恒空），
		# 文字说明转入 tooltip；等价替换原「初值播放」文本断言。
		check(String(ppb.text) == "" and ppb.icon != null, "K7-7→回修3：合一按钮符号化（text 空+自绘 icon）")
		check(String(ppb.tooltip_text) == "播放" and ppb.icon == panel.get("_icon_play"),
			"K7-7→回修3：定格暂停态显示播放三角图标 + tooltip「播放」")
	if tsld != null:
		check(int(tsld.size_flags_horizontal) == int(Control.SIZE_EXPAND_FILL), "K7-7：时间轴横向扩展占控制条主宽")
		check(float(tsld.max_value) > 0.0, "K7-7：时间轴总长已挂 get_stream_length()（4.7 实证无头亦可读 >0）")
	if tlbl != null:
		check(tlbl.text.contains(":") and tlbl.text.contains("/"), "K7-7：时间显示 mm:ss / mm:ss 格式（轴右旁）")
	# J6r3-1 首帧定格（4.7 规避保留回归护栏）：显示当帧不暂停 → 放行数帧后定格 [0.5,1.5)
	check(vp != null and not vp.paused, "J6r3-1：预览显示当帧不暂停（先放行解码帧）")
	for _pf: int in 4:
		await process_frame
	check(vp != null and vp.paused and float(vp.stream_position) >= 0.5 and float(vp.stream_position) < 1.5,
		"J6r3-1：数帧后自动定格（paused=true、播放位在 0.5s 可见帧附近）")
	var psf: Variant = panel.get("PREVIEW_SETTLE_FRAMES")
	check_eq(int(psf) if psf != null else -1, 3, "K-F：首帧定格规避实现保留（4.7 实证）")
	# ③ 合一按钮互切（无 pause() 方法，paused 属性制；回修3 符号化后断言转 icon/tooltip 口径）
	if panel.has_method("_toggle_play"):
		panel.call("_toggle_play")
		check(ppb != null and ppb.icon == panel.get("_icon_pause"), "K7-7→回修3：合一按钮点击 → paused=false 图标切暂停双杠")
		check(ppb != null and String(ppb.tooltip_text) == "暂停", "K7-7→回修3：起播态 tooltip「暂停」（文字说明保留）")
		panel.call("_toggle_play")
		check(ppb != null and ppb.icon == panel.get("_icon_play"), "K7-7→回修3：合一按钮再点 → paused=true 图标回播放三角")
	else:
		check(false, "K7-7：_toggle_play 方法存在（合一按钮挂点）")
	# ④ 时间轴 seek：_video_pos 权威状态 + 夹紧（复用旧 _seek_full 语义作用于 preview）
	if panel.has_method("_seek_video") and tsld != null and vp != null:
		panel.set("_video_duration", 59.0)
		panel.call("_seek_video", 13.0)
		check(absf(float(panel.get("_video_pos")) - 13.0) < 0.001, "K7-7：时间轴拖拽 seek → 内部播放位=13s")
		check(absf(tsld.value - 13.0) < 0.001, "K7-7：seek 同步反映到控制条时间轴")
		check(absf(float(vp.stream_position) - 13.0) < 0.001, "K7-7：seek 写入 stream_position（4.7 无 seek() 方法）")
		panel.call("_seek_video", 999.0)
		check(absf(float(panel.get("_video_pos")) - 59.0) < 0.001, "K7-7：快进 seek 夹紧到总时长尾")
		panel.call("_seek_video", -3.0)
		check(absf(float(panel.get("_video_pos"))) < 0.001, "K7-7：seek 夹紧下界 0")
	else:
		check(false, "K7-7：_seek_video 方法+时间轴/播放器挂点齐备")
	# 回修3（2026-09-08 用户反馈冗余）：底部「播放」双入口已删除（视频态 EnterButton 隐藏，
	# 播控唯一入口=控制条悬浮合一钮）；等价替换：按钮隐藏 + 不再路由 + 播完态图标回归
	check(enter_btn != null and not enter_btn.visible, "K7-7→回修3：底部「播放」双入口已删（视频态隐藏，等价替换）")
	check_eq(int(game.current_state()), ST_CATALOG, "K7-7：回看不再路由 OPENING_MOVIE（留在图鉴）")
	# 播完 → 定格回 0.5s 首帧、按钮回「播放」态（手动 emit，无头无真实解码）
	if vp != null:
		vp.finished.emit()
	check(absf(float(panel.get("_video_pos")) - 0.5) < 0.001, "K7-7：播完定格回 0.5s 首帧位")
	check(vp != null and vp.paused, "K7-7：播完自动暂停")
	check(ppb != null and ppb.icon == panel.get("_icon_play") and String(ppb.tooltip_text) == "播放",
		"K7-7→回修3：播完按钮回播放图标态（等价替换文本断言）")
	# ⑥ 可收起侧边栏（K7-7；M-F：RightToggle 迁入 RightInner）
	var rtgl: Button = panel.get_node_or_null("Body/RightBox/RightInner/RightToggle") as Button
	var rscr: ScrollContainer = panel.get_node_or_null("Body/RightBox/RightInner/RightScroll") as ScrollContainer
	check(rtgl is Button, "K7-7：侧边栏收起/展开切换钮 RightToggle(Button) 存在")
	check(rscr != null and rscr.visible, "K7-7：右侧列表默认展开可见")
	if rtgl != null:
		rtgl.pressed.emit()
	check(rscr != null and not rscr.visible, "K7-7：点 RightToggle → RightScroll 收起隐藏")
	check(rtgl != null and String(rtgl.text) == "»", "K7-7：收起态按钮文本「»」（恢复提示）")
	if rtgl != null:
		rtgl.pressed.emit()
	check(rscr != null and rscr.visible, "K7-7：再点 RightToggle → 侧边栏恢复展开")
	check(rtgl != null and String(rtgl.text) == "«", "K7-7：展开态按钮文本「«」（收起提示）")
	# 点云↔视频互斥显隐（既有 G4 语义保持）：章节态藏预览与控制条；视频态清隐藏点云
	(right_list.get_child(0) as Button).pressed.emit()
	check(vp != null and not vp.visible, "K7-7：改选章节 → 视频预览隐藏")
	check(cbar != null and not cbar.visible, "K7-7：改选章节 → 控制条隐藏（与点云态互斥）")
	var viewer_back: Control = _find_viewer(panel.get_node("Body/CenterMount"))
	check(viewer_back != null and viewer_back.visible, "K7-7：改选章节 → 点云恢复显示（联动回归）")
	check_eq(enter_btn.text, "进入关卡", "K7-7：章节态底部按钮文本回「进入关卡」")
	(right_list.get_child(5) as Button).pressed.emit()
	var viewer_v: Control = _find_viewer(panel.get_node("Body/CenterMount"))
	check(viewer_v != null and not viewer_v.visible, "K7-7：选中视频 → 中央点云隐藏")
	check(viewer_v != null and int(viewer_v.call("get_instance_count")) == 0, "K7-7：选中视频 → 点云已清空（不叠影）")
	# 重玩入口不回归（K-F 既有功能保持）：章节 → 进入关卡 → LEVEL+replay
	(right_list.get_child(0) as Button).pressed.emit()
	enter_btn.pressed.emit()
	await process_frame
	check_eq(int(game.current_state()), ST_LEVEL, "K-F：重玩入口不回归（LEVEL+replay:true）")
	check(bool(game.context().get("replay", false)), "K-F：重玩 ctx.replay=true")

	# ---- 9. 全通关后「未完待续」消失（spec 4.6）----
	save.advance_progress(2)
	save.advance_progress(3)
	save.advance_progress(4)
	save.advance_progress(5)  # cleared=[1..5]，next_chapter=6
	panel = await _open_catalog(game, container)
	check(panel != null, "全通关后可进入图鉴")
	if panel != null:
		right_list = panel.get_node("Body/RightBox/RightInner/RightScroll/RightList")
		check_eq(right_list.get_child_count(), 6, "全通关后列表仍 6 项")
		var soon_count: int = 0
		for i: int in range(5):
			var b: Button = right_list.get_child(i)
			if b.text.contains("未完待续"):
				soon_count += 1
			check(not b.disabled, "全通关后第%d关可选" % (i + 1))
		check_eq(soon_count, 0, "全通关后「未完待续」全部消失")
		# 批次 H：切换选中第 3 关 → 参考图/点云联动切换（宋→元 对应 元_points）
		# O1 批等价替换：参考图路径随画框迁移（RefFrame/RefImage）
		var b3: Button = right_list.get_child(2)
		b3.pressed.emit()
		var ref3: TextureRect = panel.get_node("Body/LeftInfo/VBox/RefFrame/RefImage")
		check(ref3.texture != null and ref3.texture.resource_path.contains("ref_chapter3.png"),
			"批次H：切换选中第3关 → RefImage 切为 ref_chapter3.png")
		var viewer3: Control = _find_viewer(panel.get_node("Body/CenterMount"))
		var real3: Resource = load(lib.call("get_points_path", 3))
		var n3: int = (real3 as PointCloudData).points.size() if real3 != null else -1
		check(viewer3 != null and int(viewer3.call("get_instance_count")) == n3,
			"批次H：切换选中第3关 → 点云重建为元_points（instance_count=%d）" % n3)
		var enter3: Button = panel.get_node("BottomBar/EnterButton")
		check(not enter3.disabled, "批次H：切换选中后「进入关卡」可用（重玩第3关）")
		enter3.pressed.emit()
		await process_frame
		check_eq(int(game.current_state()), ST_LEVEL, "批次H：切换后进入 → LEVEL（重玩第3关）")
		check_eq(int(game.context().get("chapter", -1)), 3, "批次H：ctx.chapter=3")

	_cleanup()
	finish()
