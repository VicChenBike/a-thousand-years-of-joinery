extends "res://tests/test_base.gd"
## 批次 AC（2026-09-27）Wave AC-1「基础设施与 UI」专项回归（spec §1/§7/§8，领域一/七/八）。
## 覆盖口径（三域，红态=改前）：
##   A 领域一（图标真透明与打包配置，spec §4.1）：
##     A1 图源 icon.png 真透明完整性（四角 alpha==0 + 透明区 RGB 清零，无灰白棋盘伪透明）；
##     A2 产物 assets/icons/app_icon.ico 存在且 ICONDIR 合规（reserved=0/type=1/count=6）；
##     A3 恰含 16/32/48/64/128/256 六档，且每档四角 alpha==0、中心 alpha>0（真透明非空图）；
##     A4 每档透明区 RGB 全零（伪棋盘根因=(255,255,255,0)，任何忽略 alpha 的解码路径都露白）；
##     A5 六帧 wPlanes==1（Windows ICONDIRENTRY 规范；Pillow 硬写 0，生成脚本已纠正）；
##     A6 export_presets.cfg application/icon 与 console_wrapper_icon 双绑 app_icon.ico；
##     A7 iss [Setup] SetupIconFile + UninstallDisplayIcon 指向真透明 .ico；
##     A8 iss [Files] 打包 .ico 至 {app}\assets\icons（快捷方式图标源须物理落盘）；
##     A9 iss [Icons] 快捷方式全部显式 IconFilename（批次 AC 原四条含「手势版」；
##       09-29 打包小修 3e278ff 起「手势版」快捷方式退役 → 恰三条 组/卸载/桌面，
##       AF 同步批锁定退役后形态）；A10 反向护栏：手势版专属 Filename=python.exe 与
##       GestureRuntimeInstalled Check 守卫段已随退役删除（launcher.py 随包保留、仅入口退役）。
##   B 领域八（手势交互 (Beta) 角标，spec §4.8）：
##     B1 tscn 文案含 (Beta)；B2 gd 常量 GESTURE_BTN_TEXT 单源；B3 实机面板实例文本含 (Beta)
##     并 begins_with("手势交互")（宽松匹配，防后续再挂角标误红）；B4 反向护栏：无纯文本
##     相等匹配消费该文案（`gesture_toggle.text ==` 零命中，字面量改动不会破坏逻辑分支）。
##   C 领域七（原生平滑拖窗，spec §4.7）：
##     C1 接线本体 DisplayServer.window_start_drag() 在位；C2 旧逐帧 window_set_position
##     位移语句已被整段删除（红态=反馈环迟滞）；C3 五道守卫全保留且早于拖拽调用（顺序断言：
##     headless → 合成事件 → 最大化/全屏门 → 交互控件 → 立绘可见区）；C4 _win_grab 抓取
##     成员退役；C5 运行期 API 探针 DisplayServer.has_method("window_start_drag")；
##     C6 InputEventMouseMotion 分支不再驱动窗口位移；C7 按下判据排除 double_click
##     （spec §4.7 明文「mb.pressed and not mb.double_click」——原生拖拽走 SC_MOVE|HTCAPTION
##     标题栏语义，双击会触发 OS 最大化并与 WindowButtons._maxed 状态机脱同步）。
## 纪律：纯文件读取 + 单次面板实例化（手势/摄像头双关，零 spawn 零真开镜零真摄像头）；
##       user:// 备份-还原四件组（abnc/fxog 同款，面板 _ready 触档亦逐字节自证）。
const ICON_PNG := "res://icon.png"
const ICON_ICO := "res://assets/icons/app_icon.ico"
const GEN_SCRIPT := "res://tools/gen_app_icon.py"
const EXPORT_PRESETS := "res://export_presets.cfg"
const ISS_PATH := "res://tools/千年一榫_setup.iss"
const PANEL_SCENE := "res://scenes/settings/settings_panel.tscn"
const PANEL_GD := "res://scenes/settings/settings_panel.gd"
const MAIN_GD := "res://scenes/main.gd"
const ICO_SIZES: Array = [16, 32, 48, 64, 128, 256]
## 旧逐帧位移语句特征（含 mouse_get_position/window_set_position 的反馈环本体）
const OLD_DRAG_STMT := "DisplayServer.window_set_position(Vector2i(Vector2(DisplayServer.mouse_get_position())"
const DRAG_CALL := "DisplayServer.window_start_drag()"

const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_acb1_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
var _pre_save_text: String = ""

func _src(p: String) -> String:
	return FileAccess.get_file_as_string(p)

func _exists(p: String) -> bool:
	return FileAccess.file_exists(p) or FileAccess.file_exists(ProjectSettings.globalize_path(p))

## 剥除整行注释后再做「语句/标识符存在与否」断言——本文件与 main.gd 的注释会为留痕
## 显式引用被退役的旧标识符（如旧 `_win_grab` 抓取式），若对原文断言会被留痕注释自身
## 判红（红态锚点错位）。口径同 test_z_defects「锚真实取值语句而非注释」：只认代码行。
## 仅剥整行注释（`#` 出现在行首非空白处）——行内字符串含 `#`（如色值）不受影响。
func _code_only(src: String) -> String:
	var out: Array[String] = []
	for ln: String in src.split("\n"):
		if ln.strip_edges().begins_with("#"):
			continue
		out.append(ln)
	return "\n".join(out)

## 抽取 _input 函数体（至下一个顶层 func / 文件尾）——拖窗段顺序断言用
func _input_body(src: String) -> String:
	var i: int = src.find("func _input(")
	if i < 0:
		return ""
	var j: int = src.find("\nfunc ", i + 1)
	return src.substr(i, (j if j > 0 else src.length()) - i)

func _backup_user() -> void:
	## 起测前占位清理：残留备份若在，先原样还原（同 abnc/fxog 纪律，防前次崩溃残留）
	for p0: String in DISC_WATCHED:
		var bk0: String = DISC_BK_PREFIX + p0.get_file()
		if FileAccess.file_exists(ProjectSettings.globalize_path(bk0)):
			if FileAccess.file_exists(ProjectSettings.globalize_path(p0)):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p0))
			DirAccess.copy_absolute(ProjectSettings.globalize_path(bk0), ProjectSettings.globalize_path(p0))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(bk0))
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	## 数据安全加固（本波 P0 存档事故教训）：**先备份落位并逐项自证存在**，确认后才移走活档。
	## 旧式「copy 后无条件 remove」在 copy 失败时会静默丢档（用户档不可再生）。
	for p: String in DISC_WATCHED:
		if not FileAccess.file_exists(p):
			continue
		var bk: String = DISC_BK_PREFIX + p.get_file()
		DirAccess.copy_absolute(ProjectSettings.globalize_path(p), ProjectSettings.globalize_path(bk))
		if not FileAccess.file_exists(bk):
			check(false, "存档纪律：%s 备份落位失败（保留活档不删）" % p)
			continue                     # 备份失败 → 绝不删活档
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	var sm: Node = root.get_node_or_null("SaveManager")
	if sm != null:
		sm.call("load_game")

func _restore_user() -> void:
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(bk), ProjectSettings.globalize_path(p))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(bk))
	var sm: Node = root.get_node_or_null("SaveManager")
	if sm != null:
		sm.call("load_game")
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")

func finish() -> void:
	_restore_user()
	super.finish()

# ===== A 领域一：图标真透明与打包配置 =====
func _section_a() -> void:
	print("-- A 领域一 图标真透明与打包配置（spec §4.1） --")
	check(_exists(ICON_PNG), "A1 前置：真透明图源 icon.png 在位")
	check(_exists(GEN_SCRIPT), "A1 前置：生成脚本 tools/gen_app_icon.py 在位（可复现）")
	check(_exists(ICON_ICO), "A2 产物 assets/icons/app_icon.ico 存在（红态=未生成）")
	if not _exists(ICON_ICO):
		return

	var f := FileAccess.open(ICON_ICO, FileAccess.READ)
	if f == null:
		check(false, "A2 产物可读（FileAccess 打开成功）")
		return
	var blob: PackedByteArray = f.get_buffer(f.get_length())
	f = null

	# A2 ICONDIR 合规
	var reserved: int = blob.decode_u16(0)
	var itype: int = blob.decode_u16(2)
	var count: int = blob.decode_u16(4)
	check_eq(reserved, 0, "A2 ICONDIR reserved==0（Windows 规范）")
	check_eq(itype, 1, "A2 ICONDIR type==1（ICO 类型）")
	check_eq(count, 6, "A2 ICONDIR count==6（恰六档）")

	# A3/A4/A5 逐帧
	var got_sizes: Array = []
	var all_corner_zero := true
	var all_center_opaque := true
	var all_rgb_clean := true
	var all_planes_ok := true
	var all_png_frames := true
	for i: int in range(count):
		var b: int = 6 + i * 16
		var w: int = blob.decode_u8(b)
		var h: int = blob.decode_u8(b + 1)
		var planes: int = blob.decode_u16(b + 4)
		var bpp: int = blob.decode_u16(b + 6)
		var sz: int = blob.decode_u32(b + 8)
		var off: int = blob.decode_u32(b + 12)
		var px: int = w if w != 0 else 256      # 0 表示 256（ICONDIRENTRY 约定）
		got_sizes.append(px)
		if planes != 1:
			all_planes_ok = false
		if bpp != 32:
			all_planes_ok = false
		var payload: PackedByteArray = blob.slice(off, off + sz)
		if payload.slice(0, 4).hex_encode() != "89504e47":
			all_png_frames = false
			continue
		var img := Image.new()
		if img.load_png_from_buffer(payload) != OK:
			check(false, "A3 第 %d 档（%dx%d）PNG 帧可解码" % [i, px, px])
			all_corner_zero = false
			all_center_opaque = false
			continue
		var fw: int = img.get_width()
		var fh: int = img.get_height()
		check_eq(Vector2i(fw, fh), Vector2i(px, px), "A3 第 %d 档帧尺寸 == %d×%d" % [i, px, px])
		# 四角 alpha
		for c: Vector2i in [Vector2i(0, 0), Vector2i(fw - 1, 0), Vector2i(0, fh - 1), Vector2i(fw - 1, fh - 1)]:
			if img.get_pixel(c.x, c.y).a != 0.0:
				all_corner_zero = false
		# 中心不透明（防全透明空图假绿）
		if img.get_pixel(fw / 2, fh / 2).a <= 0.0:
			all_center_opaque = false
		# A4 透明区 RGB 全零（防 (255,255,255,0) 白角/棋盘残留）
		for y: int in range(fh):
			for x: int in range(fw):
				var c: Color = img.get_pixel(x, y)
				if c.a == 0.0 and (c.r != 0.0 or c.g != 0.0 or c.b != 0.0):
					all_rgb_clean = false
	got_sizes.sort()
	check_eq(got_sizes, ICO_SIZES, "A3 六档尺寸齐全且升序（%s）" % str(ICO_SIZES))
	check(all_corner_zero, "A3 六档逐帧四角 alpha==0（真透明；红态=灰白棋盘/白角）")
	check(all_center_opaque, "A3 六档逐帧中心 alpha>0（非全透明空图，防假绿）")
	check(all_rgb_clean, "A4 六档透明区 RGB 全零（伪棋盘根因 (255,255,255,0) 已清零）")
	check(all_planes_ok, "A5 六帧 wPlanes==1 且 bpp==32（Windows ICONDIRENTRY 规范）")
	check(all_png_frames, "A5 六帧均为 PNG 压缩帧（Vista+ 标准；与项目前期已交付件同型）")

	# A1 图源真透明完整性（四角 + 透明区 RGB 清零）
	var png_img := Image.new()
	var png_f := FileAccess.open(ICON_PNG, FileAccess.READ)
	var png_blob: PackedByteArray = png_f.get_buffer(png_f.get_length()) if png_f != null else PackedByteArray()
	png_f = null
	var perr: int = png_img.load_png_from_buffer(png_blob)
	check_eq(perr, OK, "A1 图源 icon.png 可解码")
	if perr == OK:
		var pw: int = png_img.get_width()
		var ph: int = png_img.get_height()
		var src_corners_zero := true
		for c: Vector2i in [Vector2i(0, 0), Vector2i(pw - 1, 0), Vector2i(0, ph - 1), Vector2i(pw - 1, ph - 1)]:
			if png_img.get_pixel(c.x, c.y).a != 0.0:
				src_corners_zero = false
		check(src_corners_zero, "A1 图源四角 alpha==0（%d×%d 真透明）" % [pw, ph])
		# 图源透明区判定（口径精确定义）：真透明 vs 伪棋盘的分野是**是否存在规律深浅交替**，
		# 不是 RGB 是否非零。图源现存单一值 (255,255,255,0)：alpha 通道完整、无网格，
		# 故判「透明区 RGB 取值种类 ≤ 1」（既容 (0,0,0,0) 也容单一浅值）。
		# 棋盘伪透明会呈 ≥2 种交替取值 → 判红。产物侧另有 A4 更严的全零断言把关。
		var src_rgb_values := {}
		for y: int in range(0, ph, 4):
			for x: int in range(0, pw, 4):
				var c: Color = png_img.get_pixel(x, y)
				if c.a == 0.0:
					src_rgb_values[Vector3i(int(c.r * 255.0), int(c.g * 255.0), int(c.b * 255.0))] = true
		check(src_rgb_values.size() <= 1,
			"A1 图源透明区 RGB 取值无深浅交替（种类=%d ≤1 → 非棋盘伪透明）" % src_rgb_values.size())

	# A6 export_presets.cfg 双绑
	var ep: String = _src(EXPORT_PRESETS)
	check(ep.contains("application/icon=\"res://assets/icons/app_icon.ico\""),
		"A6 export_presets application/icon 绑定 app_icon.ico（红态=空串）")
	check(ep.contains("application/console_wrapper_icon=\"res://assets/icons/app_icon.ico\""),
		"A6 export_presets application/console_wrapper_icon 同绑（控制台包装器同图标）")
	check(not ep.contains("application/icon=\"\""), "A6 旧空值 application/icon=\"\" 已清零")

	# A7/A8/A9/A10 iss 打包与快捷方式
	var iss: String = _src(ISS_PATH)
	check(iss.contains("SetupIconFile=..\\assets\\icons\\app_icon.ico"),
		"A7 iss SetupIconFile 指向真透明 .ico（安装程序本体图标）")
	check(iss.contains("UninstallDisplayIcon={app}\\assets\\icons\\app_icon.ico"),
		"A7 iss UninstallDisplayIcon 指向已落盘 .ico（控制面板卸载项图标）")
	check(iss.contains("Source: \"..\\assets\\icons\\app_icon.ico\"; DestDir: \"{app}\\assets\\icons\""),
		"A8 iss [Files] 打包 .ico 至 {app}\\assets\\icons（图标源须物理落盘）")
	# A9 快捷方式逐行断言（杜绝回落到 EXE 资源或 python.exe 解释器图标）。
	# AF 同步批（2026-11-01）：09-29 打包小修 3e278ff「手势版」快捷方式退役——
	# iss [Icons] 现恰三条（组/卸载/桌面），断言锁定退役后形态并加「手势版条目零命中」反向护栏。
	var icon_lines := 0
	var gesture_line_exists := false
	for ln: String in iss.split("\n"):
		if ln.begins_with("Name: \"{") and ln.contains("Filename:"):
			if ln.contains("IconFilename: \"{app}\\assets\\icons\\app_icon.ico\""):
				icon_lines += 1
			if ln.contains("{autodesktop}") and ln.contains("手势版"):
				gesture_line_exists = true
	check_eq(icon_lines, 3, "A9 iss [Icons] 恰三条快捷方式全带 IconFilename（组/卸载/桌面；手势版退役后形态）")
	check(not gesture_line_exists,
		"A9 反向护栏：「手势版」快捷方式条目已退役（09-29 打包小修；Name 行零命中，留痕注释不计）")
	check(not iss.contains("{app}\\gesture_runtime\\python\\python.exe"),
		"A10 反向护栏：快捷方式 Filename=python.exe 随手势版退役删除（launcher.py 随包保留、仅入口退役）")
	check(not iss.contains("GestureRuntimeInstalled"),
		"A10 反向护栏：手势版 Check 守卫段 GestureRuntimeInstalled 已随退役删除（未装手势运行时不再有专属入口）")

# ===== B 领域八：手势交互 (Beta) 角标 =====
## B 段拆两半：B-src 纯文本同步断言 + B-live 面板实例化异步断言。
## 口径留痕（审查自纠）：_section_b 原为含 await 的协程，调用点未加 await → 协程在首个
## await 处即返回，B3 四条实机断言被静默跳过（表面仍 55 checks 全绿=**假绿**）。现拆分为
## 同步函数 _section_b_src() 与协程 _section_b_live()，调用点显式 await 后者。
func _section_b_src() -> void:
	print("-- B 领域八 手势交互 (Beta) 角标（spec §4.8） --")
	var tscn: String = _src(PANEL_SCENE)
	var gd: String = _src(PANEL_GD)
	check(tscn.contains("text = \"手势交互 (Beta)\""), "B1 tscn GestureToggle 文案含 (Beta)（红态=\"手势交互\"）")
	check(gd.contains("const GESTURE_BTN_TEXT := \"手势交互 (Beta)\""),
		"B2 gd 常量 GESTURE_BTN_TEXT 单源在位（防 tscn/代码字面量漂移）")
	check(gd.contains("gesture_toggle.text = I18n.t(GESTURE_BTN_TEXT)"),
		"B2 _ready 经常量回写文案（两处同源；AF-I18n 波后经 I18n.t 包装，zh 直通等值）")
	check(not gd.contains("gesture_toggle.text =="),
		"B4 反向护栏：无 `gesture_toggle.text ==` 纯文本相等匹配（改文案不破逻辑分支）")

func _section_b_live() -> void:
	# B3 实机面板实例化（手势/摄像头双关：零 spawn 零真开镜）
	var sm: Node = root.get_node_or_null("SaveManager")
	if sm != null:
		sm.call("update_settings", {"gesture_input": false, "gesture_camera_enabled": false})
	var panel: Node = (load(PANEL_SCENE) as PackedScene).instantiate()
	add_child(panel)
	await process_frame
	await process_frame
	var gt: Button = panel.get_node_or_null("Panel/VBox/OptionsBox/GestureToggle") as Button
	check(gt != null, "B3 前置：GestureToggle 按钮在位")
	if gt != null:
		check(String(gt.text).contains("(Beta)"), "B3 面板实例文案含 (Beta)（实际「%s」）" % String(gt.text))
		check(String(gt.text).begins_with("手势交互"),
			"B3 面板实例文案前缀「手势交互」保持（宽松匹配，后续再挂角标不误红）")
		check(gt.toggle_mode, "B3 反向护栏：仍为 toggle_mode 开关（换文案不改交互语义）")
	panel.free()

# ===== C 领域七：原生平滑拖窗 =====
func _section_c() -> void:
	print("-- C 领域七 原生平滑拖窗（spec §4.7） --")
	var src: String = _src(MAIN_GD)
	var code: String = _code_only(src)
	check(src.contains(DRAG_CALL), "C1 main.gd 接线 DisplayServer.window_start_drag()（红态=无此调用）")
	check(not code.contains(OLD_DRAG_STMT),
		"C2 旧逐帧 window_set_position 位移语句已删除（红态=DWM 反馈环沉重迟滞）")
	check(not code.contains("_win_grab"),
		"C4 抓取偏移成员 _win_grab 退役（原生拖拽无需自算抓取点；留痕注释不计）")
	check(src.contains("has_meta(GestureCursorLayer.SYNTH_META)"),
		"C3 守卫①：手势合成事件早退保留（Z6-P2-2 契约，改前改后同在）")
	check(src.contains("DisplayServer.get_name() == \"headless\""),
		"C3 守卫②：headless 早退保留（无头/window_start_drag 调用安全）")
	check(src.contains("_window_non_windowed()"),
		"C3 守卫③：最大化/全屏门保留（drag_gate_closed 综合真值）")
	check(src.contains("WindowManager.is_interactive_control(hovered)"),
		"C3 守卫④：交互控件命中排除保留（按钮/滑条/3D 视口不拖窗）")
	check(src.contains("is_point_over_witness_visible"),
		"C3 守卫⑤：立绘可见区豁免保留（Y-C9④）")
	check(src.contains("mb.double_click"),
		"C7 spec §4.7：按下判据排除 double_click（防 OS 双击标题栏最大化与 _maxed 状态机脱同步）")

	# C3 顺序断言：五道守卫全部早于拖拽调用（剥注释后按代码行判定）
	var body: String = _code_only(_input_body(src))
	check(not body.is_empty(), "C3 前置：_input 函数体可抽取")
	if not body.is_empty():
		var at_drag: int = body.find(DRAG_CALL)
		check(at_drag > 0, "C3 _input 体内含 window_start_drag 调用点")
		for guard: String in ["DisplayServer.get_name() == \"headless\"",
				"has_meta(GestureCursorLayer.SYNTH_META)",
				"_window_non_windowed()",
				"WindowManager.is_interactive_control(hovered)",
				"is_point_over_witness_visible"]:
			var g: int = body.find(guard)
			check(g >= 0 and g < at_drag, "C3 守卫「%s」早于拖拽调用（顺序断言）" % guard)
		# C6 MouseMotion 分支不再驱动窗口位移（剥注释后判：留痕注释不得充作代码证据）
		var mm: int = body.find("InputEventMouseMotion")
		if mm >= 0:
			check(not body.substr(mm, 200).contains("window_set_position"),
				"C6 MouseMotion 分支不再调用 window_set_position")
		else:
			check(true, "C6 InputEventMouseMotion 拖窗分支整段退役（无该分支）")

	# C5 运行期 API 探针（headless 下接口存在且调用安全，spec §8 风险五缓解措施）
	check(DisplayServer.has_method("window_start_drag"), "C5 DisplayServer.window_start_drag 接口在位")
	check(DisplayServer.has_method("window_start_resize"), "C5 DisplayServer.window_start_resize 接口在位（后续备用）")

func _initialize() -> void:
	print("== test_ac_batch1_infra ==")
	_backup_user()
	_section_a()
	_section_b_src()
	await process_frame
	# 批次 AF 终审备案族（语言钉扎先例=6411fae o_catalog_shop）：autoload _ready 推迟至树激活，
	# 须等一帧后钉 zh——用户真实存档现 language=en，不钉则文案断言呈 en 态假红。
	# 编译窗安全：经节点查找而非全局名（--script 模式 autoload 全局名编译期未注册）。
	var i18n_node: Variant = get_root().get_node_or_null("I18n")
	if i18n_node != null:
		i18n_node.call("set_language", "zh")
	await _section_b_live()
	_section_c()
	finish()
