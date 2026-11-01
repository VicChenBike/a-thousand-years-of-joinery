extends "res://tests/test_base.gd"
## 批次 AA / W8 判定用例（spec §11.6 红测清单 R8-a~R8-i + 主会话计划 W8-5 新增硬锚）。
## 域：UI 停靠重叠（用户两张截图——图鉴全屏回放被控制台盖住播放键 / 商店立绘被摄像头窗盖住）。
##
## 硬锚（全部无头几何断言，零摄像头、零窗口模式）：
##   段 1  CATALOG 嵌入态几何零变化（R8-g 护栏——批次 W P3-6b 配平不回退）；
##   段 2  CATALOG 全屏子态 CATALOG_FS：三件纵向叠置左列，×ControlBar 零相交（R8-a）、
##         ×TopStrip info/confirm 两档零相交 + 静态不变式 right≤320（R8-b、§22 裁决 1 强约束）、
##         三件两两不相交（§11.4-1 约束③）、bottom≤260（§11.4-1 硬断言 4）、
##         逐件描述符 == 规格 §11.4-1 定稿几何（防「只对了个大概」）；
##   段 3  SHOP 顶部横排：三件两两不相交（R8-c/d 前置）、×TopBar 占用带（运行期 rect 推导，
##         非硬编码）零相交 + 静态不变式 left≥288、×Content 格网带(y≥92)零相交（R8-c）、
##         逐件描述符 == §11.4-2 定稿几何；
##   段 4  SHOP 收起钮：不越出视口顶部（R8-e）且 ×三件/×TopBar 占用带/×格网带零相交；
##   段 5  SHOP 态 TopStrip：顶 ≥96（R8-f）且 ×三件零相交；CATALOG_FS 态 ×TopStrip 两档零相交；
##   段 6  键集合一致性（R8-h）：MIN_SIZES / _dock_cfg / _avail_for 对 10 个停靠键逐键成立；
##   段 7  SHOP 专属字号档（§11.4-2 行高/字号定档）：HINT_FONT_SHOP=14 / HINT_ROW_H_SHOP=17。
##
## 夹具纪律：
##   ① 0.5s _dock_poll 与 W8-1 新增 0.25s _fs_poll 双轮询冻结（负大数，test_u_dock_anchors 先例），
##      防「合成态被 Game 活态覆写」竞态；_fs_poll 以属性表探活写入（红态该属性未在场亦不报错）；
##   ② 流真值开（camera_opened 合成包注入，GestureBridge.simulate_packet）——apply_dock_state
##      收口三真值 AND，无流则整组隐藏、几何断言全空转；
##   ③ 全屏驱动 = 纯 UI 路径：_select_video(null) + _set_fullscreen(true)（复用工程既有 .ogv 源，
##      不碰摄像头枚举/bind/窗口模式）；
##   ④ 视口钉设计尺寸 1152×648（无头 expand 撑高坑，add 后补钉 + 放行帧）。

const HUD_SCENE := "res://scenes/shared/gesture_hud.tscn"
const CATALOG_SCENE := "res://scenes/catalog/catalog_scene.tscn"
const SHOP_SCENE := "res://scenes/shop/shop_panel.tscn"
const TS_SCRIPT := "res://scenes/shared/top_strip.gd"
const WIN := Vector2(1152, 648)

# 规格 §11.4-1 定稿几何（CATALOG_FS 三件纵向叠置左列）
const FS_CAM := Rect2(16, 14, 144, 81)
const FS_STATUS := Rect2(16, 101, 144, 24)
const FS_HINT := Rect2(16, 131, 300, 120)
# 规格 §11.4-2 定稿几何（SHOP 顶部横排）——**左界 344 vs 规格 288 的实施期实测偏离**：
# 规格「TopBar 右缘 ≈270~280」系未挂主题语境（Label font 16）实测；生产主题
# themes/theme_dark.tres Label/font_size=20 → BalanceLabel「天赋值：500」实宽 114 →
# ExitButton x154~294，运行期占用右缘 294 > 288（cam 落 288 会盖退出钮 6px）。
# 取 344 = 占用右缘 + 50 净隙（天赋值 6 位数内恒不相交），仍满足静态不变式 left ≥ 288
# 与带界 x∈[288,1016]（行右缘 916 ≤ 1016）。
const SH_CAM := Rect2(344, 16, 128, 72)
const SH_STATUS := Rect2(480, 16, 128, 24)
const SH_HINT := Rect2(616, 16, 300, 74)
# 规格 §11.4-1：全屏控制条实测矩形（运行期另取实矩形交叉验证）
const CONTROL_BAR_SPEC := Rect2(8, 600, 1136, 40)
# 规格 §11.4-1 硬断言 2：TopStrip confirm 档实测带 x321~831 / y70~130（静态对照带）
const CONFIRM_BAND := Rect2(321, 70, 510, 60)
const INFO_BAND := Rect2(416, 70, 320, 60)
# 商店：Content 格网顶 / 顶部横排带左界
const GRID_TOP := 92.0
const SHOP_BAND_LEFT := 288.0
# 停靠键全集（R8-h：三处键集合一致的对照真值）
const DOCK_KEYS: Array = ["MAIN_MENU", "OPENING_MOVIE", "TALK", "LEVEL", "CATALOG",
	"CATALOG_FS", "SETTLE", "SHOP", "SETTINGS", "UNKNOWN"]

var _hud: Control = null
var _catalog: Node = null
var _strip: Node = null

func _rect(n: Control) -> Rect2:
	return n.get_global_rect()

func _no_inter(a: Rect2, b: Rect2) -> bool:
	return not a.intersects(b)

## 描述符 → 窗相对矩形（_apply_item 四值组直赋的解析式；test_u_dock_anchors 同式）
func _exp(d: Dictionary) -> Rect2:
	var sz: Vector2 = d["size"]
	var x: float = float(d["mx"]) if d["ax"] == "L" else WIN.x - float(d["mx"]) - sz.x
	var y: float = float(d["my"]) if d["ay"] == "T" else WIN.y - float(d["my"]) - sz.y
	return Rect2(x, y, sz.x, sz.y)

## 三件两两不相交（C(3,2)=3 对，逐对独立计数——失败可定位）
func _pairwise(rects: Array, ctx: String) -> void:
	var names: Array = ["cam", "status", "hint"]
	for i: int in 3:
		for j: int in range(i + 1, 3):
			var a: Rect2 = rects[i]
			var b: Rect2 = rects[j]
			check(not a.intersects(b),
				"%s：%s×%s 两两不相交（%s × %s）" % [ctx, names[i], names[j], a, b])

## TopBar 占用带（运行期推导，非硬编码）：容器实矩形的左/顶/高 + 右界取全部子件（天赋值/退出钮）
## 最右缘——容器自身 offset_right=−128 止于 x1024，其右段 x≈280~1024 是空带（spec §11.2 R8-3），
## 故占用带必须按子件推导，否则会把空带误判为占用（红态实证：容器右缘 1024 恒 ≠ 288）。
func _topbar_occupied(tb: Control) -> Rect2:
	var base: Rect2 = tb.get_global_rect()
	var right: float = base.position.x
	var found := false
	for c: Node in tb.get_children():
		if c is Control and (c as Control).visible:
			right = maxf(right, (c as Control).get_global_rect().end.x)
			found = true
	if not found:
		return Rect2(base.position, Vector2(0.0, base.size.y))
	return Rect2(base.position, Vector2(right - base.position.x, base.size.y))

## 脚本常量安全读取（红态常量未在场 → 返回 null，不产生「Invalid get index」噪声、不触发 int(null) 中止）。
## GDScript 的 const 不进 get_script_property_list()，须走 get_script_constant_map()（4.7 实测）。
func _const(hud: Control, prop: String) -> Variant:
	var s: Script = hud.get_script()
	if s == null:
		return null
	var cm: Dictionary = s.get_script_constant_map()
	if cm.has(prop):
		return cm[prop]
	for p: Dictionary in s.get_script_property_list():
		if String(p.get("name", "")) == prop:
			return hud.get(prop)
	return null

func _topbar_child_rects(tb: Control) -> Array:
	var out: Array = []
	for c: Node in tb.get_children():
		if c is Control and (c as Control).visible:
			out.append((c as Control).get_global_rect())
	return out

func _status_node(hud: Control) -> Control:
	return hud.status_row if bool(hud.status_row.visible) else hud.status_panel

func _three(hud: Control) -> Array:
	return [_rect(hud.camera_window), _rect(_status_node(hud)), _rect(hud.guide_panel)]

# ===== 清档纪律（tools/README_走查清档规范.md；本件不写档，四件组备份/还原仍照走留痕）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_w8a_dockp_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _pre_save_text: String = ""

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _disc_del(p: String) -> void:
	var a: String = _disc_abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _backup_user() -> void:
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	for c: Node in root.get_children():
		if not DISC_AUTOLOADS.has(String(c.name)):
			c.free()
	for p: String in DISC_WATCHED:
		_disc_del(p)
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(_disc_abs(bk))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|aa_dock_placement|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

## 轮询冻结：_dock_poll（既有 0.5s）与 _fs_poll（W8-1 新增 0.25s 全屏谓词兜底）双冻结。
## _fs_poll 经脚本属性表探活——红态该属性尚未在场时不产生无效 set 报错。
func _freeze_polls(hud: Control) -> void:
	hud.set("_dock_poll", -100000.0)
	for p: Dictionary in hud.get_script().get_script_property_list():
		if String(p.get("name", "")) == "_fs_poll":
			hud.set("_fs_poll", -100000.0)

func _initialize() -> void:
	print("== test_aa_dock_placement ==")
	_backup_user()
	var save: Node = get_root().get_node("SaveManager")
	var game: Node = get_root().get_node("Game")
	save.load_game()
	save.update_settings({"gesture_input": true, "gesture_camera_enabled": false,
		"gesture_hud_visible": true, "gesture_panel_folded": false})
	get_root().size = Vector2i(int(WIN.x), int(WIN.y))
	var hud: Control = (load(HUD_SCENE) as PackedScene).instantiate()
	add_child(hud)
	await process_frame
	await process_frame
	get_root().size = Vector2i(int(WIN.x), int(WIN.y))
	await process_frame
	await process_frame
	_hud = hud
	# 流真值开（三真值 AND 收口，无流整组隐藏 → 几何断言空转；合成包注入，零摄像头）
	get_root().get_node("GestureBridge").simulate_packet(
		JSON.stringify({"type": "camera_opened", "id": 0, "name": "HD Camera"}))
	await process_frame
	_freeze_polls(hud)

	# ================= 段 1. CATALOG 嵌入态零变化（R8-g 护栏）=================
	hud.call("apply_dock_state", 6, false, false)   # Game.State.CATALOG=6（无全屏 → 嵌入态）
	await process_frame
	check_eq(_rect(hud.camera_window), _exp(hud._dock_cfg("CATALOG")["cam"]),
		"R8-g：嵌入态图鉴摄像头窗 == CATALOG 描述符（L16/B44，批次 W P3-6b 配平零回退）")
	check_eq(_rect(hud.status_panel), _exp(hud._dock_cfg("CATALOG")["status"]),
		"R8-g：嵌入态图鉴状态行 == CATALOG 描述符（L16/B14）")
	check_eq(_rect(hud.guide_panel), _exp(hud._dock_cfg("CATALOG")["hint"]),
		"R8-g：嵌入态图鉴说明栏 == CATALOG 描述符（L172/B14 300×120）")

	# ================= 段 2. CATALOG 全屏子态 CATALOG_FS（R8-a/R8-b）=================
	var catalog: Node = (load(CATALOG_SCENE) as PackedScene).instantiate()
	add_child(catalog)
	await process_frame
	await process_frame
	_catalog = catalog
	get_root().size = Vector2i(int(WIN.x), int(WIN.y))
	await process_frame
	await process_frame
	check(catalog.has_method("is_video_fullscreen"), "前置：catalog_scene.is_video_fullscreen 谓词在场")
	# 纯 UI 驱动进全屏（复用工程既有 .ogv 源；不碰摄像头枚举/bind/窗口模式）
	catalog.call("_select_video", null)
	var control_bar: Control = catalog.get_node_or_null("Body/CenterMount/VideoPreview/ControlBar") as Control
	check(control_bar != null, "前置：内嵌态 ControlBar 节点在场（reparent 前取引用）")
	if control_bar == null:
		finish()
		return
	catalog.call("_set_fullscreen", true)
	await process_frame
	await process_frame
	check(bool(catalog.call("is_video_fullscreen")), "前置：_set_fullscreen(true) → 全屏谓词为真")
	# 把全屏场景登记为当前场景（生产链路：Game._current_scene 由场景加载器赋值，:198）
	game.set("_current_scene", catalog)
	hud.call("apply_dock_state", 6, false, false)
	await process_frame
	await process_frame
	check(bool(hud.visible), "前置：CATALOG_FS 态 HUD 整组可见（流真值门通过）")

	var fs_rects: Array = _three(hud)
	check_eq(fs_rects[0], FS_CAM,
		"R8-1：全屏态摄像头窗 (16,14) 144×81 纵向叠置左列首件（实测 %s）" % fs_rects[0])
	check_eq(fs_rects[1], FS_STATUS,
		"R8-1：全屏态状态行 (16,101) 144×24（cam 底 95+6 间隙；实测 %s）" % fs_rects[1])
	check_eq(fs_rects[2], FS_HINT,
		"R8-1：全屏态说明栏 (16,131) 300×120（实测 %s）" % fs_rects[2])
	_pairwise(fs_rects, "CATALOG_FS")

	# ControlBar 实矩形（运行期）×规格常量交叉验证 + 三件零相交（R8-a，§22 裁决 1 强约束）
	# 口径说明：无头 --script 无工程主题语境 → BarRow 内容最小高把 ControlBar 由 offset 高 40
	# 撑到 48（grow_vertical=0 向上长），故**上缘** 592（无主题）/600（生产带 Noto 主题）两值并存；
	# 左 8 / 右 1144 / 底 640 由 anchor+offset 直给、与主题无关，取为硬锚（规格 (8,600)-(1144,640)
	# 系生产实测口径，本断言对无头/生产两语境同时成立）。
	var cb: Rect2 = _rect(control_bar)
	check(is_equal_approx(cb.position.x, 8.0) and is_equal_approx(cb.end.x, 1144.0)
			and is_equal_approx(cb.end.y, 640.0) and cb.size.y >= 40.0 and cb.size.y <= 48.0,
		"前置：全屏 ControlBar 运行期矩形左 8/右 1144/底 640 锚定（实测 %s，规格 %s 上缘随主题 592~600）" % [cb, CONTROL_BAR_SPEC])
	for i: int in 3:
		var r: Rect2 = fs_rects[i]
		check(not r.intersects(cb),
			"R8-a：CATALOG_FS %s %s × ControlBar %s 零相交（图 1 播放键遮挡根除）" % [["cam", "status", "hint"][i], r, cb])

	# 静态不变式：三件 right ≤ 320（§22 裁决 1——结构上不可能与任何居中弹条相交）
	for i: int in 3:
		var r: Rect2 = fs_rects[i]
		check(r.end.x <= 320.0,
			"R8-b：CATALOG_FS %s 右缘 %.0f ≤ 320（静态不变式；confirm 档左缘 321 结构零相交）"
				% [["cam", "status", "hint"][i], r.end.x])
	check(fs_rects[0].end.y <= 260.0 and fs_rects[1].end.y <= 260.0 and fs_rects[2].end.y <= 260.0,
		"§11.4-1 硬断言 4：CATALOG_FS 三件 bottom ≤ 260（cam 95/status 125/hint 251）")

	# 静态对照带（info/confirm 两档，§11.4-1 硬断言 2 的结构化表达）
	for i: int in 3:
		var r: Rect2 = fs_rects[i]
		check(not r.intersects(CONFIRM_BAND) and not r.intersects(INFO_BAND),
			"R8-b：CATALOG_FS %s × TopStrip confirm 带(x321~831)/info 带(x416~736) 零相交" % ["cam", "status", "hint"][i])

	# ================= 段 5a. CATALOG_FS × TopStrip 运行期实矩形两档 =================
	_strip = (load(TS_SCRIPT) as GDScript).new()
	add_child(_strip)
	await process_frame
	await process_frame
	_strip.call("push_info", "手势交互需要摄像头，无法关闭")
	await process_frame
	await create_timer(0.5).timeout   # 入场滑动 0.25s 放行（test_v_top_strip 同式）
	var info_rect: Rect2 = _rect(_strip as Control)
	check(info_rect.size.x > 0.0 and info_rect.size.y > 0.0, "前置：TopStrip info 档实矩形非零（防零矩形假绿）")
	for i: int in 3:
		check(not fs_rects[i].intersects(info_rect),
			"R8-b：CATALOG_FS %s × TopStrip info 实矩形 %s 零相交" % [["cam", "status", "hint"][i], info_rect])
	_strip.call("push_confirm", "确认退出《千年一榫》？")
	await process_frame
	await create_timer(0.5).timeout
	var conf_rect: Rect2 = _rect(_strip as Control)
	check(conf_rect.size.x > 0.0 and conf_rect.size.y > 0.0, "前置：TopStrip confirm 档实矩形非零")
	for i: int in 3:
		check(not fs_rects[i].intersects(conf_rect),
			"R8-b：CATALOG_FS %s × TopStrip confirm 实矩形 %s 零相交（裁决 1 强约束）" % [["cam", "status", "hint"][i], conf_rect])
	_strip.call("dismiss_active_confirm")

	# 嵌入态回归复验（全屏退出 → 三件回 CATALOG 底部现位）
	catalog.call("_set_fullscreen", false)
	game.set("_current_scene", null)
	await process_frame
	hud.call("apply_dock_state", 6, false, false)
	await process_frame
	check(_rect(hud.guide_panel).is_equal_approx(_exp(hud._dock_cfg("CATALOG")["hint"])),
		"R8-g：全屏退出后嵌入态说明栏回 CATALOG 底部现位（分流回落零残留）")
	_catalog = null
	catalog.free()
	await process_frame

	# ================= 段 3. SHOP 顶部横排（R8-c/R8-d）=================
	var layer := CanvasLayer.new()
	var host := Control.new()
	get_root().add_child(layer)
	layer.add_child(host)
	game.call("attach", host, layer)
	game.call("open_overlay", "shop")
	await process_frame
	await process_frame
	get_root().size = Vector2i(int(WIN.x), int(WIN.y))
	await process_frame
	var shop: Node = game.get("_overlay_instance")
	check(shop != null and shop is Control, "前置：经 Game.open_overlay 取得 shop 实例（is_shop_open 真值通路）")
	if shop == null:
		finish()
		return
	var topbar: Control = (shop as Control).get_node_or_null("TopBar") as Control
	check(topbar != null, "前置：shop TopBar 节点在场")
	_freeze_polls(hud)
	hud.call("apply_dock_state", 1, false, true)   # MAIN_MENU + shop_open → key=SHOP
	await process_frame
	await process_frame
	check(bool(hud.visible), "前置：SHOP 态 HUD 整组可见")

	var sh_rects: Array = _three(hud)
	check_eq(sh_rects[0], SH_CAM,
		"R8-2：SHOP 摄像头窗 (288,16) 128×72 顶排首件（实测 %s；MIN_SIZES SHOP 同值）" % sh_rects[0])
	check_eq(sh_rects[1], SH_STATUS,
		"R8-2：SHOP 状态行 (424,16) 128×24（实测 %s）" % sh_rects[1])
	check_eq(sh_rects[2], SH_HINT,
		"R8-2：SHOP 说明栏 (560,16) 300×74（实测 %s；4 行×17=68 ≤ 74）" % sh_rects[2])
	_pairwise(sh_rects, "SHOP")

	if topbar != null:
		var occ: Rect2 = _topbar_occupied(topbar)
		check(occ.size.x > 0.0 and occ.size.y > 0.0,
			"前置：TopBar 占用带运行期推导非零（容器 rect %s ∪ 子件最右缘 → %s）" % [topbar.get_global_rect(), occ])
		# 运行期边距判据（替代规格「占用右缘 ≤288」前提——实测 294，见 SH_CAM 注）：顶排最左件
		# 必须落在占用带右缘之外且留 ≥8 净隙（天赋值位数增长即占用带右移，本判据随运行期矩形自适应）
		check(occ.end.x + 8.0 <= sh_rects[0].position.x,
			"R8-d：顶排最左件 left %.0f ≥ TopBar 占用带右缘 %.0f + 8 净隙（运行期自适应判据）"
				% [sh_rects[0].position.x, occ.end.x])
		check(occ.end.x <= WIN.x, "前置：TopBar 占用带右缘 %.0f 在视口内（数据依赖：天赋值位数）" % occ.end.x)
		for i: int in 3:
			var r: Rect2 = sh_rects[i]
			check(not r.intersects(occ),
				"R8-d：SHOP %s %s × TopBar 占用带 %s 零相交（天赋值/退出钮不遮挡）" % [["cam", "status", "hint"][i], r, occ])
		for k: int in _topbar_child_rects(topbar).size():
			var cr: Rect2 = _topbar_child_rects(topbar)[k]
			for i: int in 3:
				check(not sh_rects[i].intersects(cr),
					"R8-d：SHOP %s × TopBar 子件 %s 零相交（运行期 rect，非硬编码）" % [["cam", "status", "hint"][i], cr])
		# 静态不变式：三件 left ≥ 288（TopBar 占用带右缘之外）
		for i: int in 3:
			check(sh_rects[i].position.x >= SHOP_BAND_LEFT,
				"R8-d：SHOP %s left %.0f ≥ 288（静态不变式）" % [["cam", "status", "hint"][i], sh_rects[i].position.x])
	# Content 格网带（y ≥ 92）零相交 + 三件 bottom ≤ 92（R8-c）
	var grid_band := Rect2(0.0, GRID_TOP, WIN.x, WIN.y - GRID_TOP)
	for i: int in 3:
		var r: Rect2 = sh_rects[i]
		check(not r.intersects(grid_band) and r.end.y <= GRID_TOP,
			"R8-c：SHOP %s %s × 格网带 y≥%s 零相交且 bottom %.0f ≤ 92（图 2 立绘遮挡根除）"
				% [["cam", "status", "hint"][i], r, GRID_TOP, r.end.y])

	# ================= 段 4. SHOP 收起钮（R8-e）=================
	var btn: Control = hud.get_node_or_null("HintFoldBtn") as Control
	check(btn != null, "前置：HintFoldBtn 在场")
	if btn != null:
		var br: Rect2 = _rect(btn)
		check(br.position.y >= 0.0,
			"R8-e：SHOP 收起钮顶 %.0f ≥ 0（旧公式 guide_panel 顶 16−22=−6 越出视口顶部的根除）" % br.position.y)
		check(br.end.y <= GRID_TOP and br.end.x <= WIN.x and br.position.x >= 0.0,
			"R8-e：SHOP 收起钮整体在视口内且不压格网（rect=%s）" % br)
		check(bool(btn.visible), "R8-e：SHOP 展开态收起钮可见可点（功能回归锚）")
		# 注：hint 是收起钮的**宿主**（定稿=锚 hint 内右上角），二者按设计相交——故判据为
		# 「×cam/×status 零相交 + 整体含于 hint」；spec §11.4-2 断言 5 的「×三件零相交」按
		# 「其余两件」口径落地（字面口径与「锚 hint 内右上角」自相矛盾，已回报）。
		for i: int in 2:
			check(not br.intersects(sh_rects[i]),
				"R8-e：SHOP 收起钮 × %s 零相交（hint 为宿主不计）" % ["cam", "status"][i])
		check(sh_rects[2].encloses(br),
			"R8-e：SHOP 收起钮整体含于 hint 内右上角（rect=%s hint=%s）" % [br, sh_rects[2]])
		if topbar != null:
			check(not br.intersects(_topbar_occupied(topbar)),
				"R8-e：SHOP 收起钮 × TopBar 占用带零相交")
			for cr: Rect2 in _topbar_child_rects(topbar):
				check(not br.intersects(cr), "R8-e：SHOP 收起钮 × TopBar 子件 %s 零相交" % cr)
		check(not br.intersects(grid_band), "R8-e：SHOP 收起钮 × 格网带零相交")

	# ================= 段 5b. SHOP 态 TopStrip offset（R8-f）=================
	if _strip != null:
		_freeze_polls(hud)
		_strip.call("push_info", "购买确认条测试文案", 3.0)
		await process_frame
		await create_timer(0.5).timeout
		var ts_off := float(_strip.get("offset_top"))
		check(ts_off >= 96.0,
			"R8-f：SHOP 态 TopStrip 顶 %.0f ≥ 96（SHOP_TOP_OFFSET 暂定值；旧 70 与三件底 90 实叠 20）" % ts_off)
		var ts_rect: Rect2 = _rect(_strip as Control)
		for i: int in 3:
			check(not sh_rects[i].intersects(ts_rect),
				"R8-f：SHOP %s × TopStrip 实矩形 %s 零相交（三件底 90 < 条顶 96）" % [["cam", "status", "hint"][i], ts_rect])
		_strip.call("push_confirm", "确认购买「皮肤」？")
		await process_frame
		await create_timer(0.5).timeout
		var ts_c_rect: Rect2 = _rect(_strip as Control)
		for i: int in 3:
			check(not sh_rects[i].intersects(ts_c_rect),
				"R8-f：SHOP %s × TopStrip confirm 实矩形 %s 零相交（商店高频弹条）" % [["cam", "status", "hint"][i], ts_c_rect])
		_strip.call("dismiss_active_confirm")

	# 折叠态复验（W8-4：锚改后竖条不压新邻件；竖条高 = cfg hint 高）
	hud._hint_folded["SHOP"] = true
	_freeze_polls(hud)
	hud.call("apply_dock_state", 1, false, true)
	await process_frame
	var bar: Rect2 = _rect(hud.guide_panel)
	check_eq(bar.size.round(), Vector2(30.0, SH_HINT.size.y),
		"W8-4：SHOP 折叠竖条 30×74（高随 cfg hint 高；实测 %s）" % bar.size)
	if btn != null:
		var br2: Rect2 = _rect(btn)
		# 折叠态 ▲/▼ 钮按 V13 设计落在竖条**顶部内**（guide_panel 即竖条，宿主关系同展开态）
		check(bar.encloses(br2) and br2.position.y >= 0.0,
			"W8-4：SHOP 折叠态收起钮含于竖条顶且不越出视口（rect=%s bar=%s）" % [br2, bar])
		check(not br2.intersects(_rect(hud.camera_window)) and not br2.intersects(_rect(_status_node(hud))),
			"W8-4：SHOP 折叠态收起钮 × cam/status 零相交（锚改后竖条不压新邻件）")
	hud._hint_folded["SHOP"] = false

	# ================= 段 6. 键集合一致性（R8-h）=================
	var ms_v: Variant = hud.get("MIN_SIZES")
	var ms: Dictionary = ms_v if ms_v is Dictionary else {}
	check_eq(ms.size(), DOCK_KEYS.size(),
		"R8-h：MIN_SIZES 键数 == 停靠键全集 10（实测 %d；CATALOG_FS 新增同源）" % ms.size())
	for k: String in DOCK_KEYS:
		check(ms.has(k), "R8-h：MIN_SIZES 含键 %s（_dock_cfg/_avail_for/MIN_SIZES 三处同源）" % k)
		var cfg: Dictionary = hud._dock_cfg(k)
		var shape_ok: bool = cfg.has("cam") and cfg.has("status") and cfg.has("status_row") and cfg.has("hint")
		check(shape_ok, "R8-h：%s _dock_cfg 描述符四键齐备（cam/status/status_row/hint）" % k)
		if shape_ok:
			var d: Dictionary = cfg["cam"]
			check(d.has("ax") and d.has("ay") and d.has("mx") and d.has("my") and d.has("size"),
				"R8-h：%s cam 描述符五键齐备 {ax,ay,mx,my,size}" % k)
		var av: Vector2 = hud._avail_for(k, WIN)
		check(av.x > 0.0 and av.y > 0.0,
			"R8-h：%s _avail_for(%s, 1152×648) 净空正值（%s，缩放/自动收起兜底逐状态式）" % [k, k, av])
	# CATALOG_FS 描述符逐字段 == 规格 §11.4-1（防「匹配落 SETTINGS 兜底分支」假绿）
	var fs_cam_d: Dictionary = hud._dock_cfg("CATALOG_FS")["cam"]
	check(String(fs_cam_d["ax"]) == "L" and String(fs_cam_d["ay"]) == "T"
			and float(fs_cam_d["mx"]) == 16.0 and float(fs_cam_d["my"]) == 14.0
			and (fs_cam_d["size"] as Vector2) == Vector2(144, 81),
		"R8-h：CATALOG_FS cam 描述符逐字段 == 规格 (L,T,16,14,144×81)（实测 %s）" % fs_cam_d)

	# ================= 段 7. SHOP 专属字号档（§11.4-2 行高/字号定档）=================
	var ff_v: Variant = _const(hud, "HINT_FONT_SHOP")
	var rh_v: Variant = _const(hud, "HINT_ROW_H_SHOP")
	check(typeof(ff_v) == TYPE_INT and int(ff_v) == 14,
		"W8-2：HINT_FONT_SHOP=14（4 行 4×17=68 ≤ 74；旧 HINT_FONT_MAIN=15 档 4×20=80 > 74 必须换档；实测 %s）" % str(ff_v))
	check(typeof(rh_v) == TYPE_FLOAT and is_equal_approx(float(rh_v), 17.0),
		"W8-2：HINT_ROW_H_SHOP=17.0（min 常量；与 CATALOG 同族；实测 %s）" % str(rh_v))
	# SHOP 行字号 live 生效 + 内容最小高不撑破 74 高面板
	hud.call("apply_dock_state", 1, false, true)
	await process_frame
	var shop_font_ok := true
	for r: Node in hud.guide_list.get_children():
		if r is Label and int((r as Label).get_theme_font_size("font_size")) != 14:
			shop_font_ok = false
	check(shop_font_ok and hud.guide_list.get_child_count() > 0,
		"W8-2：SHOP 说明栏各行字号 14 live 生效（行数 %d，_build_list per-state 档）" % hud.guide_list.get_child_count())
	check(_rect(hud.guide_panel).size.y <= 74.0 + 0.01,
		"W8-2：SHOP 说明栏实高 %.1f ≤ 74（内容最小高未撑破顶排带；底 ≤ 90 < 格网顶 92）"
			% _rect(hud.guide_panel).size.y)

	# 现场还原
	if _strip != null:
		_strip.queue_free()
	game.call("close_overlay")
	await process_frame
	await process_frame

	# ================= 段 8. SETTLE 态右下贴边修复（批次 AA 终态验收备案①，aafin）=================
	# 现象：结算态桥 LOADING 期右下「手势交互加载中…」提示（main.tscn GestureLoadingTip，
	# 旧 offsets (−268,−52,−24,−20)）与结算「下一关」钮（level_scene._build_settle_ui，
	# offsets (−196,−84,−24,−28) → 实矩形 (956,564)-(1128,620)）底缘观感级重叠
	#（证据 AI工作记录/批次AA_走查_20260925/final_07b_settle_after_detour.png）。
	# 修复：tip 锚定四值组上移 70px（offset_top −52→−122 / offset_bottom −20→−90；右缘 W−24
	# 与尺寸 244×32 不变）→ tip 底 558，距下一关钮顶 564 净隙 6px ≥ 4。
	# 几何契约（无头断言，零摄像头、零窗口模式）：
	#   a) tip × 下一关/退出钮 零相交 + 竖向净隙 ≥4px（红→绿主断言）；
	#   b) tip 仍在右下区（右缘恒 W−24、纵位仍处下部带）——防「挪走即绿」假修；
	#   c) 反向护栏：tip × 三结算 Label 零相交；SETTLE 三件（cam/status/hint）× 结算关键元素
	#      （下一关/退出/三 Label）零相交；SETTLE 停靠描述符矩形零变化（本批未触 _dock_cfg）。
	# 夹具纪律：main.tscn 入树读 tip 实矩形（test_t_window_frame 段 7 先例，GlobalUI offset
	# 换算同式）；level_scene **不入树**（防 _ready/_exit_tree N9 检查点写档副作用），仅实例化
	# 后直调 _build_settle_ui(layer) 产出结算 UI（layer 入树 → 锚定可解析），读运行期实矩形。
	get_root().size = Vector2i(int(WIN.x), int(WIN.y))
	await process_frame
	var main_ui: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main_ui)
	var ls: Node = (load("res://scenes/level/level_scene.tscn") as PackedScene).instantiate()
	var settle_layer := CanvasLayer.new()
	add_child(settle_layer)
	ls.call("_build_settle_ui", settle_layer)
	await process_frame
	await process_frame
	var tip: Control = main_ui.get_node_or_null("GlobalUI/GestureLoadingTip") as Control
	check(tip != null, "AA-fin 前置：main.tscn GestureLoadingTip 在场")
	var settle_ui: Control = ls.get("_settle_ui") as Control
	check(settle_ui != null, "AA-fin 前置：_build_settle_ui 产出 SettleUI 在场")
	var next_btn: Control = null
	var exit_btn: Control = null
	if settle_ui != null:
		next_btn = settle_ui.get_node_or_null("NextButton") as Control
		exit_btn = settle_ui.get_node_or_null("ExitButton") as Control
	check(next_btn != null and exit_btn != null, "AA-fin 前置：结算 下一关/退出 钮在场")
	if tip != null and next_btn != null and exit_btn != null:
		var gui_off2: Vector2 = (main_ui.get_node("GlobalUI") as CanvasLayer).offset
		var tip_r: Rect2 = tip.get_global_rect()
		tip_r.position += gui_off2   # CanvasLayer offset 兼容换算（v2 后恒 (0,0)，test_t_window_frame 同式）
		var nb_r: Rect2 = next_btn.get_global_rect()
		var xb_r: Rect2 = exit_btn.get_global_rect()
		var gap: float = nb_r.position.y - tip_r.end.y
		check(not tip_r.intersects(nb_r),
			"AA-fin 备案①：GestureLoadingTip %s × 下一关钮 %s 零相交（右下状态文字不压结算钮）" % [tip_r, nb_r])
		check(gap >= 4.0,
			"AA-fin 备案①：tip 底缘→下一关钮顶缘竖向净隙 %.0fpx ≥ 4（修复=tip 上移 70px，旧 offsets (−268,−52,−24,−20) 留痕）" % gap)
		check(not tip_r.intersects(xb_r),
			"AA-fin 备案①：GestureLoadingTip %s × 退出钮 %s 零相交" % [tip_r, xb_r])
		check(is_equal_approx(tip_r.end.x + gui_off2.x, WIN.x - 24.0),
			"AA-fin 备案①：tip 右缘仍锚 W−24（右下角落位语义不变；实测 %.0f）" % (tip_r.end.x + gui_off2.x))
		check(tip_r.position.y >= WIN.y * 0.7,
			"AA-fin 备案①：tip 纵位仍处下部带（top %.0f ≥ 0.7H=%.0f；防挪到远处假绿）" % [tip_r.position.y, WIN.y * 0.7])
		for ln: String in ["GradeLabel", "ElapsedLabel", "TalentLabel"]:
			var lb: Control = settle_ui.get_node_or_null(ln) as Control
			check(lb != null and not tip_r.intersects(lb.get_global_rect()),
				"AA-fin 备案①：tip × 结算 %s 零相交" % ln)
	if settle_ui != null:
		# 反向护栏：SETTLE 三件 × 结算关键元素零相交（结算面板钮组+三 Label）
		_freeze_polls(hud)
		hud.call("apply_dock_state", 5, false, false)   # Game.State.SETTLE=5
		await process_frame
		var st_rects: Array = _three(hud)
		check(bool(hud.visible) and (st_rects[0] as Rect2).size.x > 0.0,
			"AA-fin 前置：SETTLE 态 HUD 整组可见且三件实矩形非零（流真值门已开）")
		var settle_elems: Array = []
		if next_btn != null:
			settle_elems.append(["下一关", next_btn.get_global_rect()])
		if exit_btn != null:
			settle_elems.append(["退出", exit_btn.get_global_rect()])
		for ln: String in ["GradeLabel", "ElapsedLabel", "TalentLabel"]:
			var lb2: Control = settle_ui.get_node_or_null(ln) as Control
			if lb2 != null:
				settle_elems.append([ln, lb2.get_global_rect()])
		for e: Array in settle_elems:
			for i: int in 3:
				check(not (st_rects[i] as Rect2).intersects(e[1] as Rect2),
					"AA-fin 护栏：SETTLE %s %s × 结算 %s %s 零相交"
						% [["cam", "status", "hint"][i], st_rects[i], e[0], e[1]])
		# SETTLE 停靠描述符零变化直锁（本批只动 main.tscn tip，_dock_cfg 未触碰的证明）
		var sc: Dictionary = hud._dock_cfg("SETTLE")
		check_eq(_exp(sc["cam"]), Rect2(24, 332, 224, 126),
			"AA-fin 护栏：SETTLE cam 描述符矩形零变化 (24,332) 224×126")
		check_eq(_exp(sc["status"]), Rect2(24, 464, 224, 24),
			"AA-fin 护栏：SETTLE status 描述符矩形零变化 (24,464) 224×24")
		check_eq(_exp(sc["hint"]), Rect2(24, 494, 240, 140),
			"AA-fin 护栏：SETTLE hint 描述符矩形零变化 (24,494) 240×140")
	# 段 8 现场清理（main 入树走 queue_free；settle_layer 入树走 free；level 未入树直 free）
	main_ui.queue_free()
	settle_layer.free()
	ls.free()
	await process_frame
	await process_frame
	finish()
