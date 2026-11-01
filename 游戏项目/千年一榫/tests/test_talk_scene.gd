extends "res://tests/test_base.gd"
## T14 判定用例：Galgame 对话系统无头测试；批次 K-E（K5）按 spec §八 改写。
## 契约来源：实施计划 T14「契约」节 + 批次 K 计划 K-E（spec §8-1~8-5）：
## 批次 Y Y4 修订（2026-09-22，剧情对话文档体系 Y-B1~Y-B7）：加载与立绘契约等价改写——
##   数据格式（Y-B2）：{"_说明":[…],"rounds":[{"speaker":"晷"|"我","texts":[…]}]}；"_说明" 被加载器忽略。
##   set_context({"mode":"after_level","chapter":int})；_ready 按 mode 选文件（批次 Z §14 增补，
##     用户 2026-09-24 拍板：**opening 语境退役**——开场对话文档删除，旧 mode=="opening" 等值
##     静默归一为 after_level（按传入 chapter 取文档，缺省 1，零告警）；
##     after_level→剧情对话/第n关.json（缺失回退**空文档** loaded_path=="" 并警告，不指向已删文件）
##   立绘（Y-B4）：对话立绘=晷唯一，时代立绘按章节常量映射定档、对话期间锁死（与穿戴无关；
##     旧「立绘随皮肤变化」清单5 语义废止，§14 反向锁定）；名牌左=晷、右=我（2026-09-22
##     用户拍板名牌=晷，纠正 Y3 误改「古今晷」，全工程可见文案统一单字「晷」）。
##   旧 opening.json/after_chapter1.json 保留于 assets/dialog/ 作迁移对照（不再被读取链引用）。
##   打字机 30 字/秒；打字中推进=立即补全本段（快进）；本段完成后推进=下一句；末句后 _finish()：
##     （批次 Y Y-C6 补充，用户 2026-09-23 拍板「对话挂载点对齐」：after_level=「进第 N 关之前」
##      的关前对话，挂载章节=即将进入的关；开场→第1关对话→第1关；通关第 N 关→播第 N+1 关
##      对话→进第 N+1 关——旧「opening→LEVEL1 / after_level(n)→LEVEL{n+1}」路由退役）
##     mode==after_level → goto_state(LEVEL,{chapter:chapter,replay:false})（进挂载章节）
##     （§14：旧 mode==opening 分支退役——归一后同 after_level 语义，播完即进挂载章节）
##   推进输入：鼠标任意点击（gui_input）或 ui_accept（_unhandled_input）；无自动播放。
##   K5-3 根因回归：Portrait/双名牌/DialogPanel 必须显式 MOUSE_FILTER_IGNORE（否则子控件 STOP
##     吞点击，根节点 _gui_input 收不到 → 「点击多次才响应」）；仅根 Control（STOP）收推进。
##   K5-2 双名牌：NameTagLeft（晷）/NameTagRight（我）text 固定，_show_line 按 speaker
##     互斥切 visible；其他/缺省 speaker 两名牌皆隐（防御）。锚 DialogPanel 顶沿上方、左右错位。
##   K5-1 立绘贴 DialogPanel 顶沿（offset_bottom ±4px）；K5-4 SkipButton「跳过剧情」一键 _finish。
##   台词约束（铁律 8 / spec §8-5 → M-Ha 修订 2026-09-07）：旧 assets/dialog/opening.json
##     （M-Ha 试写 5 页）自批次 Z §14 起**文案已被用户否决、不得再挂载**（文件本体按 14.4 保留
##     仅作归档）；剧情对话/开场.json 整份删除，对话一律由 剧情对话/第N关.json 文档驱动；
##     after_chapter1.json 两页制「……」结构占位保留为迁移对照；打字机/快进等机制测试
##     用 tests/fixtures/dialog_sample.json 合成数据。
## 环境说明：--script 无头模式下 7 个 autoload 均已自动实例化（T08 实测），但 --script 主脚本编译
## 早于 autoload 注册/class_name 注册，不能直接写全局标识符与 class_name（T08/T10 实测），
## 故经 /root/<Name> 与 load() 取 Variant 动态引用。枚举：BOOT=0 MAIN_MENU=1 OPENING_MOVIE=2
## TALK=3 LEVEL=4 SETTLE=5 CATALOG=6（与 T07/T08 测试一致）。

const SCENE_PATH := "res://scenes/dialog/talk_scene.tscn"
const CONTROLLER_PATH := "res://scenes/dialog/talk_controller.gd"
const FIXTURE := "res://tests/fixtures/dialog_sample.json"
const SKIN_CATALOG := "res://data/skin_catalog.gd"
const ERA_PORTRAIT_CH1 := "res://assets/characters/era_portraits/开头.png"
const CH1_DOC := "res://剧情对话/第1关.json"
const DELETED_OPENING_DOC := "res://剧情对话/开场.json"  # §14：已删除（断言其不存在）
const SAVE_PATH := "user://save.json"
const D1_FIRST := "等——这是哪儿？刚才还站着，一眨眼，满天是光。"
const D1_LAST := "……到了。小心，几千年前的泥，可不好擦。"
const D1_SENTS := 51

const ST_MAIN_MENU := 1
const ST_TALK := 3  # 批次 Y（Y-C6）
const ST_LEVEL := 4

const LINE1_FULL := "这是打字机测试的第一句台词，长度足够覆盖逐字检查。"

# 实例化被测场景（与 Game 路由同路径：先 set_context 再入树）
func _new_talk(ctx: Dictionary) -> Control:
	var talk: Node = load(SCENE_PATH).instantiate()
	talk.call("set_context", ctx)
	add_child(talk)
	await process_frame  # _ready 延迟至下一帧（T03/T08 实测经验）
	return talk as Control

func _wait_until(caller: Object, property: String, value: Variant, frames: int) -> bool:
	for i: int in range(frames):
		if caller.get(property) == value:
			return true
		await process_frame
	return false

# K5-3：伪造一次鼠标左键按下事件（直调 _gui_input，口径见 spec §8-3）
func _mk_click() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	return ev

func _cleanup() -> void:
	var save_abs: String = ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(save_abs):
		DirAccess.remove_absolute(save_abs)

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
const DISC_BK_PREFIX := "user://_r2b_tlk_backup_"
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
	print("EVID|user_restore|tlk|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_talk_scene ==")
	_backup_user()
	var save: Variant = get_root().get_node("SaveManager")
	var game: Variant = get_root().get_node("Game")

	_cleanup()
	save.load_game()  # 重置默认存档

	# Game 路由环境准备：场景容器（等价 main.tscn 的 attach）
	# M-D（M 批等价替换）：钉设计视口 1152×648——spec §六坑 1 惯例；0 尺寸容器会触发
	# 立绘落位「头顶出屏 clamp」防御分支（headless 布局伪象），非真实运行形态。
	var container: Control = Control.new()
	container.size = Vector2(1152, 648)
	add_child(container)
	game.attach(container, null)

	# ---- 1. 文件与节点结构（契约：Portrait/NameTagLeft{NameLabel}/NameTagRight{NameLabel}/
	#      DialogPanel/VBox/TextLabel/HintLabel/SkipButton）----
	check(ResourceLoader.exists(CONTROLLER_PATH), "talk_controller.gd 存在")
	check(ResourceLoader.exists(SCENE_PATH), "talk_scene.tscn 存在")
	check(ResourceLoader.exists("res://assets/dialog/opening.json"), "opening.json 存在")
	check(ResourceLoader.exists("res://assets/dialog/after_chapter1.json"), "after_chapter1.json 存在")
	if not ResourceLoader.exists(SCENE_PATH):
		finish()
		return
	var scene_root: Node = load(SCENE_PATH).instantiate()
	container.add_child(scene_root)
	await process_frame
	check(scene_root is Control, "场景根为 Control")
	check_eq((scene_root as Control).mouse_filter, 0, "根 mouse_filter=STOP（接收点击）")
	# P3-② 回修（K-A 审查）：对话根挂 interactive meta——点击空白推进对话不应同时触发无边框拖窗
	# （main.gd _input 经 WindowManager.is_interactive_control 命中排除，meta 键=契约 window_manager.gd）
	check(scene_root.has_meta("interactive"), "P3-②：talk_scene 根 Control 挂 meta(interactive)（推进点击不拖窗）")
	check(scene_root.get_node_or_null("Portrait") is TextureRect, "Portrait(TextureRect) 存在")
	check(scene_root.get_node_or_null("DialogPanel") is PanelContainer, "DialogPanel(PanelContainer) 存在")
	check(scene_root.get_node_or_null("DialogPanel/VBox") is VBoxContainer, "VBox(VBoxContainer) 存在")
	# K5-2 双名牌（替代原单 NameTag）：左右两块 PanelContainer，各内嵌 Label
	var name_tag_left: Node = scene_root.get_node_or_null("NameTagLeft")
	var name_tag_right: Node = scene_root.get_node_or_null("NameTagRight")
	check(name_tag_left is PanelContainer, "K5-2：NameTagLeft(PanelContainer) 存在（见证者名牌）")
	check(name_tag_right is PanelContainer, "K5-2：NameTagRight(PanelContainer) 存在（主角名牌）")
	check(scene_root.get_node_or_null("NameTagLeft/NameLabel") is Label, "K5-2：NameTagLeft/NameLabel(Label) 存在")
	check(scene_root.get_node_or_null("NameTagRight/NameLabel") is Label, "K5-2：NameTagRight/NameLabel(Label) 存在")
	check(scene_root.get_node_or_null("DialogPanel/VBox/TextLabel") is Label, "TextLabel(Label) 存在")
	check(scene_root.get_node_or_null("HintLabel") is Label, "HintLabel(Label) 存在")
	# K5-3 根因回归（spec §二.2/§8-3）：立绘/名牌/对话框默认 STOP 吞点击 → 修复后必须全部 IGNORE
	# （get_node_or_null 守门：红灯阶段节点缺失时逐条 FAIL 而非 null 引用崩中断后续断言）
	for n: String in ["Portrait", "NameTagLeft", "NameTagRight", "DialogPanel"]:
		var sub: Control = scene_root.get_node_or_null(n) as Control
		check(sub != null and sub.mouse_filter == Control.MOUSE_FILTER_IGNORE, "K5-3：子控件 %s mouse_filter=IGNORE（点击吞噬根因回归）" % n)
	# K5-4 跳过剧情按钮：存在 + 文案 + pressed 已接线（_ready 内 connect(_finish)）
	var skip_btn: Node = scene_root.get_node_or_null("SkipButton")
	check(skip_btn is Button, "K5-4：SkipButton(Button) 存在")
	if skip_btn is Button:
		check_eq(String((skip_btn as Button).text), "跳过剧情", "K5-4：跳过按钮文案「跳过剧情」")
		check((skip_btn as Button).pressed.get_connections().size() >= 1, "K5-4：SkipButton.pressed 已接线（>=1 回调）")
	# 布局对齐（项目前期设计稿 image4 + K5-2 错位）：双名牌悬于对话框顶沿上方左右两侧；内容区横贯全宽
	var dialog_node: Node = scene_root.get_node_or_null("DialogPanel")
	var vbox_node: Node = scene_root.get_node_or_null("DialogPanel/VBox")
	if vbox_node is VBoxContainer:
		check_eq((vbox_node as VBoxContainer).get_child_count(), 1, "布局：VBox 仅含 TextLabel（名字标签已外置）")
	var dp_top: float = -1.0
	if dialog_node is Control:
		dp_top = float((dialog_node as Control).anchor_top)
	if name_tag_left is PanelContainer and name_tag_right is PanelContainer:
		var ntl: PanelContainer = name_tag_left as PanelContainer
		var ntr: PanelContainer = name_tag_right as PanelContainer
		check_eq(ntl.anchor_bottom, dp_top, "K5-2：左名牌 anchor_bottom==DialogPanel.anchor_top（锚对话框顶沿悬挂）")
		check_eq(ntr.anchor_bottom, dp_top, "K5-2：右名牌 anchor_bottom==DialogPanel.anchor_top（锚对话框顶沿悬挂）")
		check(ntl.anchor_left < ntr.anchor_left, "K5-2：双名牌左右错位（左锚<右锚，互不重叠）")
	if dialog_node is PanelContainer:
		var dp: PanelContainer = dialog_node as PanelContainer
		check(absf(dp.anchor_left - 0.03) < 0.001 and absf(dp.anchor_right - 0.97) < 0.001, "布局：对话框横贯全宽（x≈0.03~0.97）")
		check(absf(dp.anchor_top - 0.72) < 0.001 and absf(dp.anchor_bottom - 0.97) < 0.001, "布局：对话框居底部大块（y≈0.72~0.97）")
		var portrait_node: Node = scene_root.get_node_or_null("Portrait")
		if portrait_node is TextureRect:
			check((portrait_node as TextureRect).anchor_bottom <= dp.anchor_top + 0.001, "布局：立绘位于对话框上方")
	# ---- J4-1（E1/E2/E3）+ K5-1：下一关背景压暗 + 立绘放大贴顶 + 对话框黄色系毛玻璃 ----
	# E3 背景/压暗层
	var bg_node: TextureRect = scene_root.get_node_or_null("Background") as TextureRect
	check(bg_node != null, "E3：对话有背景层（Background TextureRect）")
	if bg_node != null:
		check(bg_node.mouse_filter == Control.MOUSE_FILTER_IGNORE, "E3：背景层不吃输入")
		check(bg_node.texture != null and String(bg_node.texture.resource_path).ends_with("bg_chapter1.png"),
			"E3：opening 对话背景=第 1 关关卡背景")
	var dim_node: ColorRect = scene_root.get_node_or_null("Dim") as ColorRect
	check(dim_node != null, "E3：压暗层存在（Dim ColorRect）")
	if dim_node != null:
		check(dim_node.mouse_filter == Control.MOUSE_FILTER_IGNORE, "E3：压暗层不吃输入")
		check(dim_node.color.r < 0.2 and dim_node.color.a >= 0.5 and dim_node.color.a <= 0.7,
			"E3：压暗层为半透黑（深 0.62/浅 0.55）")
	# E2 立绘放大（±260、盒高 620）+ M-D 落位（M 批等价替换）：可见脚底全局 y==DialogPanel
	# 顶−30（拍板 #2，portrait_metrics used_rect 口径）。原 K5-1「盒底贴面板顶（offset_bottom
	# ±4px）」废止——立绘纹理底部大片透明边（default_witness 548px）使可见脚底远高于盒底，
	# 旧口径下可见脚部悬空过高（历史「从来没修对」根因）。
	var prt: TextureRect = scene_root.get_node_or_null("Portrait") as TextureRect
	if prt != null:
		await process_frame
		await process_frame  # M-D 落位为 call_deferred（布局后排布），补帧等齐
		check(prt.offset_top < -400.0, "E2：立绘放大（盒顶 offset_top 深于 -400；Y4 换时代立绘开头.png 后实测仍成立）")
		var pmm: GDScript = load("res://scripts/portrait_metrics.gd")
		var pm_m: Dictionary = pmm.call("measure", String(scene_root.get("portrait_path")))
		var pm_f: Dictionary = pmm.call("fit_in_box", pm_m["size"], pm_m["rect_px"], prt.size)
		var pm_foot: float = prt.global_position.y + float(pm_f["foot_local_y"])
		var pm_dptop: float = (dialog_node as Control).global_position.y
		check(absf(pm_foot - (pm_dptop - 30.0)) <= 2.0,
			"M-D：可见脚底全局 y==面板顶−30（±2px，拍板 #2，实测差 %.2f）" % (pm_foot - (pm_dptop - 30.0)))
		check(prt.size.y <= 620.5, "M-D：盒高≤620（放大档上限，暂定走查微调）")
		check(prt.offset_left < -200.0 and prt.offset_right > 200.0, "E2：立绘加宽（±260）")
		check(prt.stretch_mode == TextureRect.STRETCH_KEEP_ASPECT_CENTERED, "E2/K5-1：立绘保比例居中")
	var hint_node: Node = scene_root.get_node_or_null("HintLabel")
	if hint_node != null:
		check(String((hint_node as Label).text).contains("点击"), "HintLabel 提示文案含「点击」")
	var panel: Node = scene_root.get_node_or_null("DialogPanel")
	if panel != null:
		var sb: StyleBox = (panel as PanelContainer).get_theme_stylebox("panel")
		check(sb is StyleBoxFlat, "DialogPanel 面板样式为 StyleBoxFlat（E1 黄色系毛玻璃运行时覆盖）")
		if sb is StyleBoxFlat:
			var fsb: StyleBoxFlat = sb as StyleBoxFlat
			check(fsb.bg_color.a >= 0.70 and fsb.bg_color.a <= 0.80,
				"M-D 追1：对话框半透明 α∈[0.70,0.80]（深 0.75/浅 0.78，M 批等价替换原 α≈0.66 断言）")
			check(fsb.shadow_size == 0, "M-D 追1：StyleBox 投影置 0（外投影移交 ui_material 面板档材质，M 批等价替换原 shadow_size=12 断言）")
			var dpm: ShaderMaterial = (panel as PanelContainer).material as ShaderMaterial
			check(dpm != null and dpm.shader != null and String(dpm.shader.resource_path).ends_with("ui_material.gdshader"),
				"M-D 追1：DialogPanel 挂 ui_material 面板档材质（悬停金属反光载体）")
			check(fsb.border_width_top >= 2, "E1：对话框顶缘高光边（border_width_top=2）")
			check(fsb.bg_color.r > fsb.bg_color.b + 0.05, "E1：对话框为黄色系底（深浅两套皆红多于蓝）")
	scene_root.queue_free()
	await process_frame

	# ---- 2. opening.json 旧文件契约（Y4 起为迁移对照源，读取链已切至 剧情对话/第N关.json：
	#      本节断言保留=锁定归档源未被改动（14.4：文件本体保留，文案已被用户否决不得挂载；
	#      2026-09-22 用户拍板名牌=晷：迁移源 speaker/自称已统一「晷」）----
	# M-Ha（清单 M7）：开场动画配剧情文案——主角遇见晷；after 系章节台词仍为
	# 两页制「……」占位（铁律 8：章节台词未获授权，仅 opening.json 获授权试写）。
	var of: FileAccess = FileAccess.open("res://assets/dialog/opening.json", FileAccess.READ)
	var opening_parsed: Variant = JSON.parse_string(of.get_as_text())
	of.close()
	check(typeof(opening_parsed) == TYPE_DICTIONARY, "opening.json 可解析")
	var opening_lines: Array = (opening_parsed as Dictionary).get("lines", [])
	check_eq(opening_lines.size(), 5, "M-Ha：opening.json 共 5 页（开场剧情文案）")
	check_eq(String((opening_parsed as Dictionary).get("dialog_id", "")), "opening", "M-Ha：dialog_id==opening")
	var n_witness: int = 0
	var n_me: int = 0
	for line_v: Variant in opening_lines:
		var line_d: Dictionary = line_v as Dictionary
		var sp: String = String(line_d.get("speaker", ""))
		var tx: String = String(line_d.get("text", ""))
		check(sp == "晷" or sp == "我", "M-Ha：说话人限定双名牌集合（实测「%s」）" % sp)
		if sp == "晷":
			n_witness += 1
		elif sp == "我":
			n_me += 1
		check(tx.length() > 0, "M-Ha：文本非空（speaker=%s）" % sp)
		check(tx != "……", "M-Ha：占位省略号已替换为剧情文案")
		check(tx.length() <= 60, "M-Ha：单页 ≤60 字（实测 %d）" % tx.length())
		check_eq(String(line_d.get("portrait", "")), "equipped", "M-Ha：portrait 固定 equipped（立绘=当前皮肤）")
	check(opening_lines.size() >= 1 and String((opening_lines[0] as Dictionary).get("speaker", "")) == "晷",
		"M-Ha：页1 说话人=晷（§11 缺失回退名牌断言依赖此前提）")
	check(n_witness >= 2 and n_me >= 1, "M-Ha：双角色均有台词（见证者 %d 页 / 我 %d 页）" % [n_witness, n_me])

	# ---- 2a. §14 增补（用户 2026-09-24 拍板）：开场对话文档整份删除（AI 试写稿退役）----
	#      旧「5 轮/5 句迁移契约」断言随文档删除退役，等价换锚：文件不在库 + 控制器/挂载链
	#      零指向已删文件的字面引用 + opening 语境静默归一（旧 opening 实例=第1关.json 语义）。
	check(not (ResourceLoader.exists(DELETED_OPENING_DOC) or FileAccess.file_exists(DELETED_OPENING_DOC)),
		"§14②：剧情对话/开场.json 已删除（红测：现状在库）")
	var tc_src: String = FileAccess.get_file_as_string("res://scenes/dialog/talk_controller.gd")
	check(not tc_src.contains("开场.json"), "§14④：talk_controller.gd 零 开场.json 字面引用（OPENING_DOC 常量已删）")
	var om_src: String = FileAccess.get_file_as_string("res://scenes/movie/opening_movie.gd")
	check(not om_src.contains("\"mode\": \"opening\""), "§14①：opening_movie 零 opening 语境挂载")
	# 归一语义：mode=opening/chapter=n → 第n关.json（按传入 chapter 取文档，零告警）
	var t_norm: Control = await _new_talk({"mode": "opening", "chapter": 2})
	check_eq(String(t_norm.get("loaded_path")), "res://剧情对话/第2关.json",
		"§14④：opening chapter=2 静默归一 → 第2关.json（红测：现状回退旧文件）")
	var nw: Variant = t_norm.get("doc_warnings")
	check(nw is Array and (nw as Array).is_empty(), "§14④：归一零新增告警（实测 %d 条）" % ((nw as Array).size() if nw is Array else -1))
	check((t_norm.get("_lines") as Array).size() >= 1, "§14④：归一后逐句清单非空")
	t_norm.queue_free()
	await process_frame

	# ---- 2b. after_chapter1.json 旧文件维持两页制「……」占位（Y4 起为迁移对照源，不再被读取链引用；
	#      章节对话已由 剧情对话/第N关.json 供给）----
	var af: FileAccess = FileAccess.open("res://assets/dialog/after_chapter1.json", FileAccess.READ)
	var after_parsed: Variant = JSON.parse_string(af.get_as_text())
	af.close()
	check(typeof(after_parsed) == TYPE_DICTIONARY, "after_chapter1.json 可解析")
	var after_lines: Array = (after_parsed as Dictionary).get("lines", [])
	check_eq(after_lines.size(), 2, "K5-5：after_chapter1.json 两页制（lines==2）")
	if after_lines.size() >= 2:
		check_eq(String((after_lines[0] as Dictionary).get("speaker", "")), "晷", "K5-5：after 页1 说话人=晷")
		check_eq(String((after_lines[1] as Dictionary).get("speaker", "")), "我", "K5-5：after 页2 说话人=我")
		check_eq(String((after_lines[0] as Dictionary).get("text", "")), "……", "K5-5：after 页1 文本=省略号占位（铁律 8 边界）")
		check_eq(String((after_lines[1] as Dictionary).get("text", "")), "……", "K5-5：after 页2 文本=省略号占位（铁律 8 边界）")

	# ---- 3. 数据加载：set_context(opening) 静默归一（§14）→ 第1关.json 首轮（我）右名牌显示
	#      （K5-2 双名牌固定文本+互斥 visible；§14 后首轮 speaker 由「晷」变「我」，方向反转）----
	var talk: Control = await _new_talk({"mode": "opening", "chapter": 1})
	var live_tag_left: Control = talk.get_node_or_null("NameTagLeft") as Control
	var live_tag_right: Control = talk.get_node_or_null("NameTagRight") as Control
	var name_label_left: Label = talk.get_node_or_null("NameTagLeft/NameLabel") as Label
	var name_label_right: Label = talk.get_node_or_null("NameTagRight/NameLabel") as Label
	var text_label: Label = talk.get_node("DialogPanel/VBox/TextLabel")
	var hint_label: Label = talk.get_node("HintLabel")
	var portrait: TextureRect = talk.get_node("Portrait")
	check(name_label_left != null and name_label_left.text == "晷", "K5-2：左名牌固定文本「晷」")
	check(name_label_right != null and name_label_right.text == "我", "K5-2：右名牌固定文本「我」")
	check(live_tag_left != null and live_tag_right != null and live_tag_right.visible and not live_tag_left.visible,
		"§14：opening 归一→第1关首轮（我）右显左隐（互斥；红测：现状 opening 首轮晷左显）")
	check_eq(String(talk.get("loaded_path")), CH1_DOC, "§14：opening 归一加载 第1关.json")
	var page1_full: String = ""
	var talk_lines: Array = talk.get("_lines") as Array
	if talk_lines.size() >= 1:
		page1_full = String((talk_lines[0] as Dictionary).get("text", ""))
	check_eq(page1_full, D1_FIRST, "§14③：对话首句逐字=用户正式文案第 1 句")
	check(page1_full.length() > 0 and page1_full.begins_with(String(text_label.text)),
		"Y-B3：首轮文本为打字机前缀（§14 后=第1关.json 首句）")

	# ---- 4. 首句打字机自然完成 → 显示推进提示（首句 22 字 @30字/秒≈0.8s；
	#      headless 帧率不定、原 _wait_until 按帧等待不再可靠 → 等价替换为真实时间切片等待）----
	var typing_done: bool = false
	for i_wait: int in range(40):  # 上限 4s（0.1s/片，约 3.3 倍冗余）
		if not bool(talk.get("_typing")):
			typing_done = true
			break
		await talk.get_tree().create_timer(0.1).timeout
	check(typing_done, "M-Ha：首句 打字机自然完成（_typing=false，等价替换原 120 帧等待）")
	check(hint_label.visible == true, "首句 完成后推进提示可见")
	check_eq(String(text_label.text), page1_full, "M-Ha：首句 全文=用户正式文案（打字机自然完成）")

	# ---- 5. 推进（末行后 _finish）：§14 归一后 opening 实例=after_level(1) 语义 → 播完进第 1 关 ----
	# 每句先置 _typing=false（视作打字完成）再推进一次，推进到末句后快进展示末句、再击 _finish。
	# 打字中首击=快进的既有语义由 5b/§15 专测，不在此混入。
	var n_lines: int = int(talk.get("_lines").size())
	check_eq(n_lines, D1_SENTS, "§14：opening 归一=第1关.json 共 51 句（红测：现状 5 句）")
	for i: int in range(n_lines - 1):
		talk.set("_typing", false)
		talk._advance()
		await process_frame
	check_eq(int(talk.get("_index")), n_lines - 1, "§14：逐句推进至末句（_index==50）")
	talk.call("_show_line", n_lines - 1)
	talk._advance()   # 打字中推进=快进（同帧驱动，无帧边界竞态）
	check_eq(String(text_label.text), D1_LAST, "§14⑤：末句逐字==「……到了。小心，几千年前的泥，可不好擦。」（51 句全播到位）")
	talk.set("_typing", false)
	talk._advance()   # 末句完成态击 → _finish（§14 归一 → LEVEL{chapter:1}）
	await process_frame
	check_eq(int(game.current_state()), ST_LEVEL, "§14：opening 归一实例播完 → LEVEL 进第 1 关（红测：现状 TALK 接开场对话）")
	check_eq(int(game.context().get("chapter", -1)), 1, "§14：ctx.chapter==1（进第 1 关）")
	check(bool(game.is_replay()) == false, "§14：replay==false")

	# ---- 5b. K5-3 单次响应口径（spec §8-3）：逐击序列 0→快进→1→…→末页 finish，
	#      每击恰响应一次无吞键（M-Ha 等价替换：由两页制三击泛化为 n_lines 页逐击推进）----
	talk.call("_show_line", 0)
	talk.call("_gui_input", _mk_click())
	check_eq(int(talk.get("_index")), 0, "K5-3：打字中首击=快进补全不动页（既有打字机语义非 bug）")
	talk.set("_typing", false)
	talk.call("_gui_input", _mk_click())
	check_eq(int(talk.get("_index")), 1, "K5-3：第二击推进到页2（_index==1）")
	for i_page: int in range(2, n_lines):
		talk.set("_typing", false)
		talk.call("_gui_input", _mk_click())
		check_eq(int(talk.get("_index")), i_page, "K5-3：第 %d 击推进到页 %d（_index==%d）" % [i_page + 1, i_page + 1, i_page])
	talk.set("_typing", false)
	talk.call("_gui_input", _mk_click())
	check_eq(int(talk.get("_index")), n_lines - 1, "K5-3：末页击=触发 _finish 且 _index 不动（talk_controller._finish 不改索引）")
	check_eq(int(game.current_state()), ST_LEVEL, "K5-3（§14 归一）：opening 归一实例末击后 game 状态已路由（LEVEL 进第 1 关）")

	# ---- 6. 打字机（30 字/秒）：fixture 非空文本，打字中部分显示 ----
	var talk2: Control = await _new_talk({"mode": "opening", "chapter": 1})
	talk2._load_dialog(FIXTURE)
	check(bool(talk2.get("_typing")) == true, "fixture 加载后处于打字状态")
	# K5-2 断言（Y4 改写）：fixture 首行 speaker=晷（新格式合法集合）→ 左名牌显、右名牌隐
	# （「非法 speaker 两名牌皆隐」防御分支已由 test_y4_dialog.gd 合成行专测锁定）
	var t2_tag_l: Control = talk2.get_node_or_null("NameTagLeft") as Control
	var t2_tag_r: Control = talk2.get_node_or_null("NameTagRight") as Control
	check(t2_tag_l != null and t2_tag_r != null and t2_tag_l.visible and not t2_tag_r.visible,
		"K5-2：fixture 首行（晷）左显右隐（Y4 新格式合法 speaker）")
	await talk2.get_tree().create_timer(0.2).timeout
	var mid: String = String(talk2.get_node("DialogPanel/VBox/TextLabel").text)
	check(mid.length() > 0 and mid.length() < LINE1_FULL.length(), "打字机：0.2s 后部分显示（%d/%d 字）" % [mid.length(), LINE1_FULL.length()])
	check(bool(talk2.get("_typing")) == true, "打字机：未完成时 _typing 仍为 true")

	# ---- 7. 快进：打字未完成时推进 = 立即显示全段 ----
	talk2._advance()
	check_eq(String(talk2.get_node("DialogPanel/VBox/TextLabel").text), LINE1_FULL, "快进：立即补全本段全文")
	check(bool(talk2.get("_typing")) == false, "快进后 _typing=false")
	check(talk2.get_node("HintLabel").visible == true, "快进后推进提示可见")

	# ---- 8. 逐行推进：第2/3行说话人与文本正确；双名牌随句互斥切换（K5-2 visible 语义，text 恒固定）----
	talk2._advance()  # → 第 2 行（speaker=我）
	await process_frame
	var t2_tag_l2: Control = talk2.get_node_or_null("NameTagLeft") as Control
	var t2_tag_r2: Control = talk2.get_node_or_null("NameTagRight") as Control
	check(t2_tag_l2 != null and t2_tag_r2 != null and not t2_tag_l2.visible and t2_tag_r2.visible,
		"K5-2：第2行（我）右名牌显、左名牌隐（互斥切换）")
	talk2._advance()  # 快进第 2 行
	talk2._advance()  # → 第 3 行（speaker=晷）
	await process_frame
	var t2_tag_l3: Control = talk2.get_node_or_null("NameTagLeft") as Control
	var t2_tag_r3: Control = talk2.get_node_or_null("NameTagRight") as Control
	check(t2_tag_l3 != null and t2_tag_r3 != null and t2_tag_l3.visible and not t2_tag_r3.visible,
		"K5-2：第3行（晷）左名牌显、右名牌隐")
	talk2._advance()  # 快进第 3 行
	talk2._advance()  # 末行后 → _finish
	await process_frame
	check_eq(int(game.current_state()), ST_LEVEL, "fixture 播完（§14 归一）→ opening 归一实例路由 LEVEL 进第 1 关")

	# ---- 9. 无自动播放：停手不翻行 ----
	var talk3: Control = await _new_talk({"mode": "opening", "chapter": 1})
	talk3._load_dialog(FIXTURE)
	talk3._advance()  # 快进首行
	var before: String = String(talk3.get_node("DialogPanel/VBox/TextLabel").text)
	var idx_before: int = int(talk3.get("_index"))
	for i: int in range(45):
		await process_frame
	check_eq(String(talk3.get_node("DialogPanel/VBox/TextLabel").text), before, "无自动播放：文本不自动变化")
	check_eq(int(talk3.get("_index")), idx_before, "无自动播放：行索引不自动前进")
	talk3.queue_free()
	await process_frame

	# ---- 10. after_level 模式（批次 Y Y-C6 改写）：chapter=1=即将进入的关（关前对话）→
	#         加载 第1关.json → 结束路由 LEVEL{chapter:1}（进第 1 关）----
	var talk4: Control = await _new_talk({"mode": "after_level", "chapter": 1})
	var bg4: TextureRect = talk4.get_node_or_null("Background") as TextureRect
	check(bg4 != null and bg4.texture != null and String(bg4.texture.resource_path).ends_with("bg_chapter1.png"),
		"E3（Y-C6 改写）：after_level(1) 背景=即将进入的关（第 1 章）关卡背景")
	for i: int in range(int(talk4.get("_lines").size())):
		talk4.set("_typing", false)
		talk4._advance()
	await process_frame
	check_eq(int(game.current_state()), ST_LEVEL, "after_level(1) 结束 → 路由 LEVEL")
	check_eq(int(game.context().get("chapter", -1)), 1, "after_level(1)（Y-C6 改写）→ ctx.chapter==1（进第 1 关）")
	check(bool(game.is_replay()) == false, "after_level(1) → replay==false")

	# ---- 11. 缺失回退（§14 等价改写）：映射外章节 9（无 第9关.json 映射）→ 空文档 + 告警
	#      + 空台词流程收尾（_finish 防御回主菜单；loaded_path==""，不再指向已删文件）----
	var talk5: Control = await _new_talk({"mode": "after_level", "chapter": 9})
	var t5_label_l: Label = talk5.get_node_or_null("NameTagLeft/NameLabel") as Label
	check(t5_label_l != null and t5_label_l.text == "晷", "缺失回退：左名牌固定文本=晷（静态契约保持）")
	var t5_loaded: Variant = talk5.get("loaded_path")
	check(t5_loaded is String and String(t5_loaded) == "",
		"缺失回退（§14）：loaded_path==\"\"（空文档；红测：现状回退旧文件；实测 %s）" % str(t5_loaded))
	var t5_warns: Variant = talk5.get("doc_warnings")
	check(t5_warns is Array and not (t5_warns as Array).is_empty(), "缺失回退：已告警（doc_warnings 非空）")
	check((talk5.get("_lines") as Array).is_empty(), "缺失回退：空台词清单（无死引用、无指向已删文件的加载）")
	check_eq(int(game.current_state()), ST_MAIN_MENU, "缺失回退：空台词流程收尾 → 映射外章节防御回主菜单")

	# ---- 12. chapter==5（批次 Y Y-C6 改写）：after_level(5)=第 5 关关前对话 → 播完进第 5 关；
	#         旧「终点占位回主菜单」随挂载点前移退役——第 5 关通关后走结算 has_next=false→主菜单 ----
	var talk6: Control = await _new_talk({"mode": "after_level", "chapter": 5})
	var bg6: TextureRect = talk6.get_node_or_null("Background") as TextureRect
	check(bg6 != null and bg6.texture != null and String(bg6.texture.resource_path).ends_with("bg_chapter5.png"),
		"E3：after_level(5) 背景=第 5 章（封顶取 5）")
	talk6._load_dialog(FIXTURE)
	# 3 行 fixture：快进L1 → L2 → 快进L2 → L3 → 快进L3 → 结束，共 6 次推进
	for i: int in range(6):
		talk6._advance()
	await process_frame
	check_eq(int(game.current_state()), ST_LEVEL, "chapter==5（Y-C6 改写）→ 进第 5 关（LEVEL，关前对话）")
	check_eq(int(game.context().get("chapter", -1)), 5, "chapter==5（Y-C6 改写）→ ctx.chapter==5")

	# ---- 13. 立绘（Y-B4 等价改写）：对话立绘=时代立绘按章节定档，与穿戴无关 ----
	# K-D 后全新档默认 equipped=skin_origin_kaitou，仍显式穿回 skin_default 以证立绘与穿戴解耦。
	save.equip_skin("skin_default")
	var talk7: Control = await _new_talk({"mode": "opening", "chapter": 1})
	check_eq(String(talk7.get("portrait_path")), ERA_PORTRAIT_CH1, "Y-B4：opening 归一实例对话立绘=第 1 关时代立绘（开头）")
	var era_tex: Texture2D = talk7.get_node("Portrait").texture
	check(era_tex != null, "Y-B4：时代立绘纹理已加载")

	# ---- 14. Y-B4 反向锁（等价改写原清单5「立绘随皮肤变化」语义）：对话中购买+穿戴皮肤→立绘锁死不变 ----
	# 旧「皮肤信号联动」为用户点名修复的 bug（拍板 4：每关对话开始定档、期间恒定）；红测先行（test_y4_dialog）。
	save.add_talent(500)
	check(bool(save.buy_skin("skin_01")), "前置：购买 skin_01 成功")
	check(bool(save.equip_skin("skin_01")), "前置：穿戴 skin_01 成功")
	save.skin_changed.emit("skin_01")  # 直播信号：覆盖任何换肤源
	await process_frame
	await process_frame
	check_eq(String(talk7.get("portrait_path")), ERA_PORTRAIT_CH1, "Y-B4 锁死：对话中换肤→立绘路径不变")
	var tex_now: Texture2D = talk7.get_node("Portrait").texture
	check(tex_now == era_tex, "Y-B4 锁死：对话中换肤→立绘纹理实例不变")

	# ---- 15. 点击推进（_gui_input 鼠标事件）----
	var talk8: Control = await _new_talk({"mode": "opening", "chapter": 1})
	talk8._load_dialog(FIXTURE)
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	talk8._gui_input(click)
	check_eq(String(talk8.get_node("DialogPanel/VBox/TextLabel").text), LINE1_FULL, "鼠标点击（打字中）= 快进本段")

	# ---- 16. ui_accept 推进（_unhandled_input）----
	var accept: InputEventKey = InputEventKey.new()
	accept.keycode = KEY_SPACE
	accept.pressed = true
	talk8._unhandled_input(accept)
	await process_frame
	check_eq(int(talk8.get("_index")), 1, "空格（ui_accept）推进到第 2 行")

	# ---- 17. 数据异常兜底（Y-B2）：rounds 为空 → 告警+直接结束路由不崩溃 ----
	var talk9: Control = await _new_talk({"mode": "opening", "chapter": 1})
	var empty_path: String = "user://dialog_empty_test.json"
	var ef: FileAccess = FileAccess.open(empty_path, FileAccess.WRITE)
	ef.store_string(JSON.stringify({"_说明": ["空文档"], "rounds": []}))
	ef.close()
	talk9._load_dialog(empty_path)
	await process_frame
	check_eq(int(game.current_state()), ST_LEVEL, "空 rounds 文件（§14 归一）→ 直接 _finish 路由（不崩溃；opening 归一→LEVEL 进第 1 关）")
	var t9_warns: Variant = talk9.get("doc_warnings")
	check(t9_warns is Array and not (t9_warns as Array).is_empty(), "空 rounds：已告警（doc_warnings 非空）")
	var abs_empty: String = ProjectSettings.globalize_path(empty_path)
	if FileAccess.file_exists(abs_empty):
		DirAccess.remove_absolute(abs_empty)

	_cleanup()
	finish()
