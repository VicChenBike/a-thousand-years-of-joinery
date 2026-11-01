extends PanelContainer
## 批次 T（spec §4-12）：摄像头设备下拉内容件（挂 settings_panel.tscn 的 PopupPanel 内）。
## 三态：LOADING（「正在加载」+转圈）/ LOADED（设备列表）/ EMPTY（「未检测到摄像头」）。
## 数据源：GestureBridge 缓存 getter 优先（P1-1 零等待直进 LOADED），信号订阅刷新；
## ENUM_TIMEOUT=8 秒无 init → EMPTY。hover 设备项→分辨率+帧率双列阶梯同现（批次 X P3-b 前注，
## 旧「设备行右拉 res、res 行右拉 fps 连锁弹」废止）。置灰口径：camera_error 设备整行 disabled+「无法打开」（批次 V-B2
## 起成功即清可恢复）；resolutions 空子列单行「不支持」置灰；fps_options 空帧率子列不弹出。
## 选择动作（复用 send_control 零新通道）：SWITCH_CAMERA:<id> / SET_RESOLUTION:<id>:<w>x<h> /
## SET_FPS:<id>:<n>（批次 U U2-4 3 参扩展；2 参旧式保留兼容=对当前设备）。
## 批次 U（U2-③）→ 批次 AD-5c（P1，2026-09-28）：悬停设备行惰性异步探测——id==current
## **条件探测**（判据=已知矩阵不充分：该 id 未 ok 探明 且全局 init#2 ≤1 档 → 发
## PROBE_MATRIX:<id>；充分 → 零探测直出，双审 P2-6「不伤好设备」由 Python 侧 pid==current
## live 复用路径保持，不再靠「零探测」规避——AD-5b 播种只 1 档致旧口径失去改档入口的根治）；
## id≠current 查 get_probe_matrix(id) 缓存，无则 PROBE_MATRIX:<id>（1s 节流）＋「检测中…」；
## probe_result 到达刷新；8s 超时/ok=false → 「检测失败（设备无法打开）」置灰（旧「不支持」并入）。
## 批次 AD-5d（终审 P2 闭环，2026-09-28）：
## - P2-A **主动关闸门**：id==current 的条件探测在判据上再并一项「摄像头未被用户主动关闭」
##   （真值源=桥侧 release 锁存 `_camera_release_intent`，AD-2 起；主动关后悬停 current 行零
##   PROBE_MATRIX——项目铁律「用户显式关闭后任何自动路径不得重开」，探测另开句柄会点亮指示灯）。
##   非 current 行「悬停即探测」语义不变；显式再开（点设备行/下拉选中→ ensure_camera_open 先清
##   锁存再下发）不受本门影响。
## - P2-B **一会话一探**：`_auto_probe_attempted`（id → 本菜单会话已自动探测过，成败同）在
##   `_request_probe` 收口拦截——probe_result ok=false 且全局矩阵仍 ≤1 档时，回包重建会再次落
##   漏斗，而菜单 1s 节流 < 单次扫描耗时 → current 行子列保持打开期间「扫描⇄重探」循环（每轮
##   阻塞 live 流）。现同 id 一次会话至多自动探一次，失败即停（检测失败/播种档直出），
##   重新打开菜单（open_menu 清账）才允许再试。
## 批次 V-B2（V1~V4/V17，spec §6.1/§6.2/§6.4）：
## - 删「加载完了」常驻 head Label（V1）；LOADING/EMPTY 态文案逐字保留。
## - 三级子列棕化（V2）：PopupPanel 系 Window 不跨主题传播（坑4）→ 挂载即显式注入
##   ThemeManager.current_theme() + 棕档 panel StyleBox（批次 AB-3：theme_changed 跟随订阅退役）
##   （top_strip.gd 订阅先例）；行按钮保持 Button（UILightLinker/hover_glow 自动覆盖）+
##   显式字体色（未选灰化/选中提亮，棕主题深浅双档），视觉=设置按钮同族深棕。
## - 选中态常亮高亮（V2）：id==枚举 current_camera 行金棕淡底 StyleBox+字色提亮，随 init#1 重算；
##   分辨率/帧率子列同口径（记忆值匹配行高亮）。
## - 同设备点击 no-op（V4）：点当前设备行/已选 res/fps 值 → 零发送零写档不闪。
## - 选择即写档（V17）：SWITCH/SET_RESOLUTION/SET_FPS 发出处同步 SaveManager.update_settings
##   写 gesture_camera_device/gesture_camera_res/gesture_camera_fps（三键由 V-D 路落地，.get 防御）。
## - 矩阵等待态 8s 超时（V16）：「检测中…」等待行统一 8s 裁决转「检测失败」，含从未发过 PROBE
##   的 id==current 矩阵等待行（旧口径仅覆盖已发 PROBE 的 id → 恒死等，根治）。
## ⚠ 时序（plan TF-4 注）：MenuState 枚举序 EMPTY=0/LOADING=1/LOADED=2（测试段 7 按此断言）；
## 子列 PopupPanel 动态建/收（hide+queue_free 防泄漏）；_open_at/_wait_started_ms 直注为超时测试口径。
## 批次 W（W5，20260920）：P2-5a EMPTY 态接受后续 init#1（8s 超时后枚举到达照常重建退出 EMPTY
## ——打包 t≈17s 绑端口场景根除）；P2-5b probe/matrix 回包按设备 id 匹配行（_row_for_id meta
## 查找，取代 rows_snapshot 数组下标——CAP 索引不连续时的错位/越界根除）。

## 批次 X（P3，spec §4，20260921）：①选中态几何一致只换色——_tint_row 重写，margin 与主题
## Button 档等值（旧选中档 6/6/2/2 压细=「变细」根因）；未选=灰底（探针 p3a_gray_probe_run1.log
## 对齐 settings_panel「全屏显示」常态 TOGGLE_OFF_BG 双档）+灰字（N4 保留）；选中=SEL_BG 金棕淡底
## +SEL 字色（保留）。②双列阶梯同现——hover 设备行同时弹 res+fps 两列（fps 列 x=res 左缘−固定宽档、
## y=设备行底缘=阶梯状）；res 行 hover 只刷新 fps 列内容（不重弹不移位）；删除 res 行 mouse_entered
## 连锁弹 fps 旧路径；数据契约边界：Python 仅对当前分辨率探 fps_options 平铺数组
##（hand_tracking_server.py :1194-1201/:1224-1230），「刷新」现契约下为同一集合，禁止逐档探测。
## 保活谓词=两列并集（口径复核不变）；关闭时机语义不变（_close_res 连带收 fps 保留）。

enum MenuState { EMPTY, LOADING, LOADED }

const ENUM_TIMEOUT := 8.0        # spec §5：枚举超时（秒）
const PROBE_TIMEOUT := 8.0                # 批次 U（U2，spec §5）：惰性探测超时（秒）
const PROBE_REQUEST_THROTTLE_MS := 1000   # 批次 U（U2）：同 id 探测请求节流
const SPIN_RATE := 240.0         # spec §5：转圈角速度（度/秒）
const CAMERA_MENU_WIDTH := 280.0 # spec §5：下拉宽
const CoordSpace := preload("res://scripts/coord_space.gd")  # 窗口缩放坐标修复2：锚定单一漏斗
# 批次 V-B2（V2，spec §6.1）：三级子列棕化配色——设置按钮同族深棕（theme_dark.tres Button 档
# bg Color(0.38,0.27,0.1)/字 Color(0.96,0.90,0.78) 同族；金棕淡底取主题金 Color(0.788,0.635,0.153)
# 低透明度档；未选灰化=字色降饱和降亮度）。
# 批次 W（P3-1）：色彩单源表（值不变）。
# 批次 AB-3：*_LIGHT 浅档常量随深浅主题机制删除退役，深档为唯一值。
const Palette := preload("res://scripts/palette.gd")
const DARK_PANEL_BG := Color(0.24, 0.17, 0.08, 0.96)
const DARK_PANEL_BORDER := Color(Palette.STROKE_GOLD, 0.45)   # P3-1：描边金单源（值不变）
const DARK_FONT_DIM := Color(0.71, 0.71, 0.71)      # 未选行字色中性灰（批次 W N4：旧暖灰 (0.72,0.66,0.55) 留痕——
                                                    # 与选中米白同暖色系致「变细」错觉；现取 NO_HAND_GRAY #B5B5B5 族）
const DARK_FONT_SEL := Palette.TEXT_DARK_CAMSEL   # P3-1：深底浅字单源（值不变）          # 选中行字色提亮（深；N4 保留）
const SEL_BG_DARK := Color(0.788, 0.635, 0.153, 0.30)   # 金棕淡底
# 批次 X P3-a：未选灰底（探针实测对齐 settings_panel「全屏显示」常态 TOGGLE_OFF_BG——
# dark (0.35,0.30,0.22,0.35)，灰值留痕见探针 log）；圆角 12 同档。
const DIM_BG_DARK := Color(0.35, 0.30, 0.22, 0.35)
const ROW_CORNER_RADIUS := 12
# 批次 X P3-b：fps 列固定宽档——按钮 min 宽 56（帧率集最长文案 @12px 实测远小于此，波内定档）。
# 批次 X 走查 NG① 定档修正（x7b 探针实测，x7b_fps_w_probe_run1/x7b_geom_probe_run1 留痕）：
# fps PopupPanel 实际渲染宽=Window 默认 100×100——内容 min（56 钮+panel 8+8=72×68）不驱动
# 窗口尺寸（res/fps 两列内容 min 不同而窗口同为 100×100 实证）；旧 TOTAL_W=72 < 100 →
# fps 右缘越过 res 左缘 28px 叠压（违反「紧贴其左边」拍板）。新档=实测渲染宽 100+安全边距
# 6（紧贴不叠压口径 4~8 取中）；BTN_W 实测无责保留（内容 min 72 ≤ 100，列宽与文案/边距无关）。
const FPS_COL_BTN_W := 56.0
const FPS_COL_TOTAL_W := 106.0    # 批次 Z（Z6-P2-11）：旧档退役留痕——旧锚 x=res 左缘−106、
                                  # y=设备行底缘 使 fps 列恒与锚行下方设备行相交 106px（点设备名
                                  # 右半命中 fps 按钮写 gesture_camera_fps）；新锚见 FPS_COL_RENDER_W/
                                  # FPS_COL_MARGIN/FPS_COL_VGAP（常量保留供历史断言/留痕引用）
                                  # 【批次 Z 留痕】该常量当前零消费：代码已改用 FPS_COL_RENDER_W/
                                  # FPS_COL_MARGIN 组合显式坐标，本常量仅作历史留痕，勿删。
# 批次 Z（Z6-P2-11，spec §6）：fps 列几何重定档——y 改菜单底缘下方（与全部设备行零相交的
# 唯一无碰撞带）、x=res 列左缘−渲染宽−右安全边距（显式坐标；右安全边距 6→14，≥14 拍板）。
const FPS_COL_RENDER_W := 100.0  # fps 列实际渲染宽（Window 默认 100×100，x7b 探针实证，见上注）
const FPS_COL_MARGIN := 14.0     # fps 右缘 → res 列左缘安全边距（旧 6；spec「≥14px 右安全边距」）
const FPS_COL_VGAP := 6.0        # fps 列顶 → 菜单底缘纵向间隙（零压行前提）

var state: int = MenuState.LOADING
var _open_at := -1.0
var _rows: Array = []            # 设备行按钮（hover 子列锚点）
var _root_box: VBoxContainer
var _res_sub: PopupPanel = null
var _res_box: VBoxContainer = null   # P1-2：子列内容容器引（谓词收起矩形数据源；PopupPanel 系 Window 无 get_global_rect）
var _fps_sub: PopupPanel = null
var _fps_box: VBoxContainer = null   # FV-1 P2-1：帧率子列内容容器引（fps 层同享保活口径）
var _probe_requested_at: Dictionary = {}  # 批次 U（U2）：id → 上次 PROBE_MATRIX 发出时刻 ms（节流与超时共用）
# 批次 AD-5d（P2-B）：id → 本菜单会话**已自动探测过**（成败同记；open_menu 清空=重开可再试）。
# 与 _probe_requested_at（1s 节流，可被 _process 超时 erase）正交：本账只由 open_menu 清，
# 承担「同会话同 id 至多一次」的终审闸门（节流 1s < 单次扫描耗时，拦不住回包重建的重探）。
var _auto_probe_attempted: Dictionary = {}
var _wait_started_ms := -1                # 批次 V-B2（V16）：等待态起始时刻 ms（-1=未在等待；统一 8s 裁决用）
var _res_for_id := -1                     # 批次 U（U2）：当前子列服务的设备 id（probe_result 刷新定向）
var _spin := 0.0
var _spinner: Control = null

class Spinner extends Control:
	## 自绘转圈（LOADING 专属；24×24 主题色弧）
	var angle := 0.0
	func _draw() -> void:
		draw_arc(Vector2(12, 12), 9.0, angle, angle + TAU * 0.75, 24, Color(0.9, 0.8, 0.5, 0.9), 3.0, true)

func _ready() -> void:
	custom_minimum_size = Vector2(CAMERA_MENU_WIDTH, 0.0)
	if not GestureBridge.camera_enum_received.is_connected(_on_enum):
		GestureBridge.camera_enum_received.connect(_on_enum)
	if not GestureBridge.camera_matrix_received.is_connected(_on_matrix):
		GestureBridge.camera_matrix_received.connect(_on_matrix)
	if not GestureBridge.probe_result_received.is_connected(_on_probe_result):
		GestureBridge.probe_result_received.connect(_on_probe_result)   # 批次 U（U2）：到达即刷新子列
	# 批次 AB-3：theme_changed 订阅随深浅主题机制删除退役（子列棕化由打开/构建路径直挂）。
	_build_loading()

func _exit_tree() -> void:
	if GestureBridge.camera_enum_received.is_connected(_on_enum):
		GestureBridge.camera_enum_received.disconnect(_on_enum)
	if GestureBridge.camera_matrix_received.is_connected(_on_matrix):
		GestureBridge.camera_matrix_received.disconnect(_on_matrix)
	if GestureBridge.probe_result_received.is_connected(_on_probe_result):
		GestureBridge.probe_result_received.disconnect(_on_probe_result)
	_close_subs()

## 打开菜单：先读缓存（P1-1 有缓存零等待直进 LOADED），无缓存 → LOADING + 起算超时
## 批次 AB2（C6/D10b/D11）：0 摄像头确认态开下拉（摄像头列表按钮）=**重枚举机会**
##（GET_CAMERAS，request_camera_enum 1s 节流内建）；占位行照显（缓存分支空列表 →
## _build_empty）；零 spawn（start_gesture_process 跳过——空列表不得有拉起尝试）。
## 重枚举到设备 → init#1 到达经 _on_enum 实时重建 + 桥 zero 边沿自动开（记忆名/首项）。
## 批次 AC（领域二，spec §4.2-4/D2）：下拉刷新（**ArrowBtn 或重新打开下拉**=本入口）
## 一律向 Python 发 GET_CAMERAS **强制重新探测物理硬件**（外接摄像头热插拔识别）——
## Python 侧空名单时重跑 WMI/CAP 枚举并复位一次性探针门；旧实现「有缓存即纯直读零出包」
## 使新插入设备永不可见（红态）。若 Python 未运行/已挂起（9878 未被占）→ 先安全拉起
## Python 重新探查（桥 start_gesture_process 幂等：防重入门/设置门/无头 no-op）。
## 0 设备确认态仍保持 AB2 口径：零 spawn（空列表不得拉起），仅重枚举试探。
## 批次 AD-5d（P2-B）：打开菜单=显式动作 → 清空「同会话一次性自动探测账」（`_auto_probe_attempted`），
## 重新打开菜单后各 id 允许再试一次；本清点置于一切早退之前（缓存直进 LOADED 分支同样清）。
func open_menu() -> void:
	_close_subs()
	_auto_probe_attempted.clear()
	_open_at = Time.get_ticks_msec() / 1000.0
	if GestureBridge.is_camera_enum_zero():
		GestureBridge.request_camera_enum()   # AB2 C6/D10：0 态重枚举机会（零 spawn）
	else:
		if not GestureBridge.is_python_ready_probe():
			# 批次 AC：Python 未运行/已挂起 → 安全拉起后重新探查（start 幂等；无头/导出
			# 形态由桥内判据短路，零副作用）；随后照常出包 GET_CAMERAS（服务就绪即重扫）。
			GestureBridge.start_gesture_process()
		GestureBridge.request_camera_enum()
	var cached: Dictionary = GestureBridge.get_camera_enum()
	if not cached.is_empty():
		# 窗口缩放坐标修复4：取键一律 .get（桥数据防御硬纪律）；空列表缓存 → LOADED 占位
		_apply_enum(cached.get("cameras", []), int(cached.get("current_camera", 0)))
		return
	state = MenuState.LOADING
	if not GestureBridge.is_camera_enum_zero():
		GestureBridge.start_gesture_process()   # spec §4-T12-2：无缓存开下拉先预热（幂等：bridge 防重入门/无头 no-op；仅运行态，不改写 gesture_camera_enabled 存档）；AB2：0 确认态零 spawn
	# 拉取模式（修复批 2026-09-18）：缓存空即主动向服务端拉取枚举（经桥方法不直碰控制端口；
	# 幂等节流防反复开合刷包）——保证菜单每次打开都有拉取机会，init 到达即经 _on_enum 实时刷新。
	GestureBridge.request_camera_enum()
	_build_loading()

func _on_enum(cameras: Array, current: int) -> void:
	# 批次 W（W5，P2-5a）：EMPTY 态亦接受后续 init#1——8s 超时置 EMPTY 后枚举到达照常重建
	# 下拉退出 EMPTY（打包实测 t≈17s 才绑端口：8s 内无枚举 → 旧口径 EMPTY 后永不刷新，
	# 下拉定格「未检测到摄像头」）。进入前清超时哨兵 _open_at（防残留时间戳参与后续
	# LOADING 态超时误判）；LOADING/LOADED 原语义不变。
	if state == MenuState.EMPTY:
		_open_at = -1.0
	if state == MenuState.LOADING or state == MenuState.LOADED or state == MenuState.EMPTY:
		_apply_enum(cameras, current)

func _on_matrix(_res: Array, _fps: Array) -> void:
	# R2①-P2-2：矩阵到达刷新钩子——id==current 的等待态子列（init#2 瞬时窗）在矩阵到达时
	# 重建（同 _on_probe_result 路径）；「矩阵经 getter 单一数据源」语义不变（到达只触发重建、
	# 不落第二份缓存）。无子列/非当前设备则无操作。
	# 批次 W（W5，P2-5b）：锚定行改按设备 id 查找（_row_for_id）——旧 rows_snapshot[_res_for_id]
	# 数组下标在 CAP 索引不连续（置灰行/枚举空洞）时错位或越界回退 null（子列恒「检测中…」）。
	if state == MenuState.LOADED and _res_box != null and _res_for_id >= 0 \
			and _res_for_id == int((GestureBridge.get_camera_enum() as Dictionary).get("current_camera", -1)):
		var anchor: Control = _row_for_id(_res_for_id)
		if anchor != null:
			_open_res_sub(_res_for_id, anchor)

## 批次 W（W5，P2-5b）：按设备 id 查设备行（_rows 行 meta cam_id 绑定，修复4 既有口径）——
## probe_result/matrix 回包的行匹配单一漏斗（旧数组下标错位/越界根除；id 不在列表返回 null）。
func _row_for_id(id: int) -> Control:
	for r: Variant in _rows:
		if r is Control and (r as Control).has_meta("cam_id") \
				and int((r as Control).get_meta("cam_id")) == id:
			return r as Control
	return null

## 批次 U（U2）：probe_result 到达 → 当前子列若正服务该 id 则重建（「检测中…」→ 矩阵/失败）
## 批次 W（W5，P2-5b）：锚定行改按设备 id 查找（_row_for_id），取代 rows_snapshot[id] 数组下标。
func _on_probe_result(id: int, _ok: bool, _res: Array, _fps: Array) -> void:
	if state == MenuState.LOADED and _res_for_id == id and _res_box != null:
		var anchor: Control = _row_for_id(id)
		if anchor != null:
			_open_res_sub(id, anchor)

## 窗口缩放坐标修复4（2026-09-18）：cameras 条目归一纯函数（无头可测）。
## 新契约 [{"id":<int CAP索引>, "name":<str 显示名>}]（Python 侧并行升级，经 bridge
## _handle_meta 原样透传）；向下兼容旧字符串/整型数组条目（["0","1"]/id 即下标）。
## 缺键防御走 .get 硬纪律（实证坑⑪：无效字典下标直接中止），id 无法解析时取 -1 哨兵。
static func normalize_cam_entry(cam: Variant) -> Dictionary:
	if typeof(cam) == TYPE_DICTIONARY:
		return {"id": int(cam.get("id", -1)), "name": String(cam.get("name", ""))}
	var s := str(cam)
	return {"id": int(s) if s.is_valid_int() else -1, "name": s}

func _apply_enum(cameras: Array, _current: int) -> void:
	# 修复批 P2（2026-09-26）：枚举重建前显式收起 res/fps 子列——_clear_box 只重建
	# _root_box，子列挂 self（:389/:420）不随之回收；菜单开着时 init#1 到达若不清，
	# 旧子列成孤儿子列继续 popup（锚行已被 queue_free，帧末谓词 :484-500 依赖锚行
	# mouse_exited 永不触发，保活并集按旧矩形误判）。open_menu 既有 _close_subs 同款收口。
	_close_subs()
	state = MenuState.LOADED
	_clear_box()
	if cameras.is_empty():
		# 窗口缩放坐标修复4：LOADED 且空列表 → 占位行（区别于 8s 超时 EMPTY：状态保持
		# LOADED，后续 init 到达仍可经 _on_enum 刷新重建；文案与 EMPTY 占位逐字同源）
		_build_empty()
		return
	# 批次 V-B2（V1）：删「加载完了」head Label——设备行即全部内容，常驻文案废止。
	# 批次 V-B2（V2/V4）：选中态随 init#1 刷新重算（每次重建按最新枚举 current_camera 重算高亮）。
	var current: int = int((GestureBridge.get_camera_enum() as Dictionary).get("current_camera", -1))
	for cam: Variant in cameras:
		var entry: Dictionary = normalize_cam_entry(cam)
		var id: int = int(entry.get("id", -1))
		var disp: String = String(entry.get("name", ""))
		var b := Button.new()
		b.set_meta("cam_id", id)   # 修复4：id 存 meta（点击下发 SWITCH_CAMERA:<id> 同源变量，供无头断言）
		b.text = "[%d] %s" % [id, disp]
		b.add_theme_font_size_override("font_size", 12)
		b.clip_text = true
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.set_meta("hover_glow", true)   # V2：hover_glow 体系显式兜底挂点（Button 本身已命中 UILightLinker 判定）
		if (GestureBridge.get_camera_errors() as Array).has(id):
			b.disabled = true
			b.text = I18n.t("[%d] %s 无法打开") % [id, disp]
		else:
			_tint_row(b, id == current)   # V2：选中常亮/未选灰化
			b.pressed.connect(func() -> void:
				# 批次 V-B2（V4）：同设备点击 no-op——点当前设备行不发 SWITCH、零副作用（不闪）
				if id == int((GestureBridge.get_camera_enum() as Dictionary).get("current_camera", -1)):
					return
				# 批次 Z（Z4-⑤/Z6-P1-4，spec §4-6/§6-P1-4）：设备行点击**必须**经设置面板
				# 四象限状态机入口 select_camera_device（同步 gesture_camera_enabled+点亮按钮+
				# 进 OPENING 加载态+写记忆）——旧「本处直发 SWITCH」绕过四象限（按钮显示「关」
				# 摄像头却实际开启）的 P1-4 根除。生产形态菜单恒挂 settings_panel.tscn，必命中入口。
				var panel_node := _settings_panel_owner()
				if panel_node != null:
					panel_node.call("select_camera_device", id, disp if disp != "" else str(id))
					return
				# 无面板宿主（独立实例测试夹具；生产不可达）：保留旧直发路径零回归。
				# V17/W2 写档语义同源（device 记显示名，空回落 str(id)）。
				_remember_camera_choice({"gesture_camera_device": disp if disp != "" else str(id)})
				GestureBridge.send_control("SWITCH_CAMERA:%d" % id))
			b.mouse_entered.connect(func() -> void: _open_res_sub(id, b))
			b.mouse_exited.connect(_defer_close_res)
		_root_box.add_child(b)
		_rows.append(b)

## 批次 Z（Z4-⑤/P1-4）：向上定位设置面板宿主（select_camera_device 状态机入口谓词）——
## 生产链路 CameraMenu→CameraMenuPopup→CameraMenuLayer→settings_panel 必命中；
## 独立实例（测试夹具直挂测试根）返回 null → 调用方走旧直发兜底。
func _settings_panel_owner() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("select_camera_device"):
			return n
		n = n.get_parent()
	return null

func _build_loading() -> void:
	_clear_box()
	var head := HBoxContainer.new()
	var txt := Label.new()
	txt.text = I18n.t("正在加载")
	txt.add_theme_font_size_override("font_size", 12)
	_spinner = Spinner.new()
	_spinner.custom_minimum_size = Vector2(24, 24)
	head.add_child(_spinner)
	head.add_child(txt)
	_root_box.add_child(head)

func _build_empty() -> void:
	_clear_box()
	var l := Label.new()
	l.text = I18n.t("未检测到摄像头")
	l.add_theme_font_size_override("font_size", 12)
	_root_box.add_child(l)

func _clear_box() -> void:
	_rows = []
	_spinner = null
	if _root_box != null and is_instance_valid(_root_box):
		_root_box.queue_free()
	_root_box = VBoxContainer.new()
	add_child(_root_box)

## 超时判定（独立成方法供无头直测；ENUM_TIMEOUT 秒无 init → EMPTY）
func _check_timeout() -> void:
	# 哨兵判据用 != -1.0 而非 >= 0.0（bridge.gd :124-126 R-B-1 同款实证修正）：_open_at 注入
	# now-9.0 类「N 秒前」时间戳在进程启动 N 秒内为合法负值，>= 0.0 会误判为未设置哨兵。
	if state == MenuState.LOADING and _open_at != -1.0 \
			and Time.get_ticks_msec() / 1000.0 - _open_at >= ENUM_TIMEOUT:
		state = MenuState.EMPTY
		_build_empty()

## hover 设备项 → 分辨率子列（批次 U U2-③ → 批次 AD-5c 条件探测，spec §4-U2）：
## id==当前设备 → 主数据源=GestureBridge.get_camera_matrix()（init#2 全局矩阵）**条件探测**：
## 已知矩阵不充分（该 id 未 ok 探明 且全局 ≤1 档=AD-5b 播种形态）→ 发 PROBE_MATRIX:<id>
##（复用既有 1s 节流＋probe_result 到达重建链路；P2-6「自探自败」由 Python live 复用路径消解），
## 充分 → 零探测直出（不打扰推流设备）；probe 缓存有完整矩阵 → 并集直出（播种档立即可用）。
## id≠当前 → 查 get_probe_matrix(id) 缓存：有 → 列矩阵；无 → PROBE_MATRIX:<id>（同 id 1s 节流）
## ＋显示「检测中…」；probe_result 到达刷新；PROBE_TIMEOUT=8s 超时 → 单行「检测失败（设备无法
## 打开）」置灰。全程异步零阻塞（spec §4-U2-3）。
func _open_res_sub(cam_id: int, anchor_row: Control) -> void:
	# 批次 Y（Y-A15）：res 重建只收 res 列（_close_res_only，不再级联吞 fps）——非当前设备行
	# 等待态不再把已开的 fps 列吞成空（跨行直达帧率列不中断）；fps 收口仍由 _close_res
	#（级联）/_close_subs/_close_res_if_outside 承担。
	_close_res_only()
	_res_sub = PopupPanel.new()
	_apply_popup_theme(_res_sub)   # 批次 V-B2（V2）：Window 不跨主题传播（坑4）→ 挂载即显式注入
	var box := VBoxContainer.new()
	_res_sub.add_child(box)
	_res_box = box
	_res_for_id = cam_id
	var matrix: Dictionary
	if cam_id == int((GestureBridge.get_camera_enum() as Dictionary).get("current_camera", -1)):
		# id==当前：主数据源=全局矩阵（init#2）。**current 主数据源=全局矩阵**契约由
		# test_w_camera_menu B11~B13 锚定，不得改为「probe 缓存优先」（实测该改法使 B12 的
		# 「init#2 回包后以新矩阵重建」失败）——probe 缓存只作**并集补充**（全局条目在前，
		# 见 _merge_probe_resolutions，B12 断言位 800x600 恒在）。
		# 批次 AD-5c（P1，2026-09-28）：AD-5b 把启动期矩阵探测移出关键路径后，全局矩阵由
		# Python **播种**（仅当前生效 1 档）→ 旧「零探测直出」使当前设备分辨率子列只剩 1 档、
		# 失去切换分辨率入口（批次 T/U2 下拉矩阵能力削弱，终验 P1）。改为**条件探测**：
		# - 判据（已知矩阵不充分）= 该 id 从未 ok 探明（probe 缓存 ok≠true——真 1 档设备
		#   探明后不反复重探）**且** 全局矩阵 resolutions ≤1 档（播种形态）→ 发
		#   PROBE_MATRIX:<id>（复用既有 1s 节流＋probe_result 到达重建链路，_on_probe_result
		#   对 current 同样按 id 匹配重建）；
		# - 充分（≥2 档，或已 ok 探明）→ 零探测直出（不打扰正在推流的设备、无参数重协商）；
		# - P2-6「自探自败」不再靠零探测规避：Python 侧 `_probe_matrix_worker` 对
		#   pid==current 走 live 复用路径（不另开句柄不抢流、探测后恢复 res/fps、探测期抑制
		#   看门狗、绝不 release live 句柄）→ 画面不灭。
		# 显示：播种档立即可用（不闪「检测中…」）；probe 缓存有完整矩阵 → 并集直出，故
		# probe_result 到达经 _on_probe_result 重建即列全矩阵（分辨率入口恢复）。
		# R2①-P2-2：init#2 未到瞬时窗（全局矩阵空）→「检测中…」等待态（探测请求照发，
		# 矩阵/回包到达经 _on_matrix/_on_probe_result 刷新；V16 8s 裁决不变）。
		matrix = GestureBridge.get_camera_matrix()
		var probed: Dictionary = GestureBridge.get_probe_matrix(cam_id)
		var probed_ok: bool = bool(probed.get("ok", false))
		var probed_res: Array = []
		if probed_ok and typeof(probed.get("resolutions")) == TYPE_ARRAY:
			probed_res = probed.get("resolutions")
		var g_res: Array = []
		if typeof(matrix.get("resolutions")) == TYPE_ARRAY:
			g_res = matrix.get("resolutions")
		# 批次 AD-5d（P2-A，2026-09-28）：判据再并一项「**未被用户主动关闭**」——主动关后
		# current 行悬停零 PROBE_MATRIX。根因：AD-5b 后全局矩阵常仅播种 1 档 → 本条件恒真 →
		# 悬停 current 行会发探测，而 Python 侧该 id 的非 live 分支（cap=None）走
		# `_acquire_camera_handle` **重新开镜**做探测 → 指示灯被点亮（违反项目铁律「用户显式
		# 关闭后任何自动/隐式路径不得重开」）。真值源=桥侧 release 锁存（_camera_released）。
		# 仍照常显示已有矩阵/播种档（下方 matrix 直出路径不变）；非 current 行语义不变。
		if not probed_ok and g_res.size() <= 1 and not _camera_released():
			_request_probe(cam_id)   # AD-5c：不充分 → 按需惰性探测（节流＋互斥漏斗既有）
		if matrix.is_empty():
			_show_wait_state(box, anchor_row)
			return
		if not probed_res.is_empty():
			matrix = _merge_probe_resolutions(matrix, probed_res)   # AD-5c：并集直出（probe_result 重建列全）
	else:
		matrix = GestureBridge.get_probe_matrix(cam_id)
		if matrix.is_empty():
			_request_probe(cam_id)
			_show_wait_state(box, anchor_row)
			return
	_build_matrix_rows(box, cam_id, matrix)
	_position_res_sub(anchor_row)
	_open_fps_sub(cam_id, anchor_row)   # 批次 X P3-b①：hover 设备行 → fps 列同时同现（阶梯）

## 「检测中…」等待态（R2①-P2-2 提取共用）：id≠current 无缓存（发 PROBE 后等待）与
## id==current 矩阵瞬时窗（R2①-P2-2）同款显示；probe_result/矩阵到达自然刷新。
## 批次 V-B2（V16，spec §6.4）：记等待起始时刻（成员级）——_process 统一 8s 裁决判据的数据源
##（含从未发过 PROBE 的 id==current 矩阵等待行，根治死等）。
func _show_wait_state(box: VBoxContainer, anchor_row: Control) -> void:
	_wait_started_ms = Time.get_ticks_msec()
	var wait := Button.new()
	wait.text = I18n.t("检测中…")
	wait.set_meta("i18n_wait", true)   # I18n 解耦①：等待态标志位（旧 text=="检测中…" 文本反查退役）
	wait.disabled = true
	wait.add_theme_font_size_override("font_size", 12)
	box.add_child(wait)
	_position_res_sub(anchor_row)

## 批次 AD-5d（P2-A）：current 行自动探测的**主动关闸门**判据——摄像头是否处于「用户主动
## 关闭」状态（真值源单一：桥侧 release 锁存 `_camera_release_intent`）。
## 取值依据（代码现状）：
## - `_camera_release_intent`（AD-2 起）：置位=request_camera_release / stop_gesture_process /
##   camera_closed(reason=release)；清除=**显式再开**（ensure_camera_open / start_gesture_process）
##   ——持久锁存，正是项目铁律「主动关不得被复活」在桥内的既有门（_ensure_preferred_camera_restore /
##   _tick_preferred_camera_handshake 同款 `if _camera_release_intent: return`），本处同源同判据；
## - **不取** `is_camera_intentionally_released()`：其返回 `_intentional_stop`，被 main.gd 的
##   consume_intentional_stop 一次性取走即清（toast 抑制语义），非持久真值——取它会让主动关后
##   首次 UNAVAILABLE 消费即失守。
## 读桥私有成员走 .get（测试同款手法，test_t_camera_device 段 9b 等）；缺键返回 null → false。
func _camera_released() -> bool:
	return bool(GestureBridge.get("_camera_release_intent"))

## 批次 U（U2）：幂等节流发 PROBE_MATRIX（同 id 1s 内至多一次）
## 批次 W（N9，规格 §5）：发送收口到桥 send_probe_matrix（探测与主流互斥漏斗——探测在飞期
## 间新探测被丢弃，probe_result 到达/SWITCH 主流命令抢占后恢复；本菜单 1s 节流保持不变）。
## 批次 AD-5d（P2-B）：一次菜单会话内同 id 的自动探测**至多一次（成败同）**——`_auto_probe_attempted`
## 前置拦截。回包 ok=false 后 `_on_probe_result` 会立即重建子列再落本漏斗，而节流窗（1s）早已
## 过期（单次扫描 >1s）→ 旧码在 current 行子列保持打开期间形成「扫描⇄重探」循环（每轮阻塞
## live 流；一次成功即自愈）。现失败也记账：该 id 停在检测失败/播种档直出，`open_menu` 清账
## 才再试。两门次序：一次性账（会话级，管成败）→ 1s 节流（请求级，管风暴）。
func _request_probe(cam_id: int) -> void:
	if _auto_probe_attempted.has(cam_id):
		return
	var now_ms: int = Time.get_ticks_msec()
	if _probe_requested_at.has(cam_id) and now_ms - int(_probe_requested_at[cam_id]) < PROBE_REQUEST_THROTTLE_MS:
		return
	_probe_requested_at[cam_id] = now_ms
	_auto_probe_attempted[cam_id] = true
	GestureBridge.send_probe_matrix(cam_id)

## 批次 AD-5c：current 行矩阵并集——全局 init#2（种子/生效值，AD-5b 后可能仅 1 档）∪ 该 id 的
## probe 缓存完整矩阵（probe_result 经桥落缓存）。**全局条目在前**（B12「init#2 回包以新矩阵
## 重建」断言位不变：800x600 恒为首项可命中）、probe 增量补尾逐条去重（同分辨率不重复）。
## fps_options 原样随全局保留——fps 子列自有取数路径（_open_fps_sub：probe 缓存优先，既有
## 契约，不在此并表）。probe ok=false 时调用方传空（缓存无分辨率 → 不并）。
func _merge_probe_resolutions(matrix: Dictionary, probed_res: Array) -> Dictionary:
	var out: Dictionary = matrix.duplicate()
	var merged: Array = (matrix.get("resolutions", []) as Array).duplicate()
	for r: Variant in probed_res:
		if not (r is Array) or (r as Array).size() < 2:
			continue
		var w: int = int((r as Array)[0])
		var h: int = int((r as Array)[1])
		var dup := false
		for g: Variant in merged:
			if g is Array and (g as Array).size() >= 2 \
					and int((g as Array)[0]) == w and int((g as Array)[1]) == h:
				dup = true
				break
		if not dup:
			merged.append([w, h])
	out["resolutions"] = merged
	return out

## 矩阵行构建（id 语义=行目标设备；点分辨率/帧率=3 参命令，非当前设备 Python 先切后设）。
## ok 缺省视为 true（磁盘实况适配留痕：init#2 全局矩阵经桥 _handle_meta 落缓存时无 ok 键——
## 桥属 U-A 冻结面不改；probe 缓存恒显式带 ok（桥 :241）→ ok=false 仍走检测失败态）。
## 批次 V-B2（V2/V4/V17）：行棕化（显式字体色+hover_glow meta）、记忆值匹配行选中高亮、
## 已选值再点 no-op、选择即写档 gesture_camera_res。
func _build_matrix_rows(box: VBoxContainer, cam_id: int, matrix: Dictionary) -> void:
	var res_list: Array = matrix.get("resolutions", [])
	if not bool(matrix.get("ok", true)) or res_list.is_empty():
		var fail := Button.new()
		fail.text = I18n.t("检测失败（设备无法打开）")
		fail.disabled = true
		fail.add_theme_font_size_override("font_size", 12)
		box.add_child(fail)
		return
	var mem_res := _memory_res()
	for r: Variant in res_list:
		var res := Vector2i(int(r[0]), int(r[1]))
		var res_str := "%dx%d" % [res.x, res.y]
		var b := Button.new()
		b.text = res_str
		b.add_theme_font_size_override("font_size", 12)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.set_meta("hover_glow", true)   # V2：hover_glow 显式兜底挂点
		b.set_meta("res_value", res_str)   # V2：选中态重算/主题跟随重刷识别用
		_tint_row(b, cam_id == _current_enum_id() and mem_res == res_str)   # V2：分辨率子列选中态同口径
		b.pressed.connect(func() -> void:
			# 批次 V-B2（V4）：已选值（当前设备+记忆值匹配）再点 no-op——不重发不写档不闪
			if cam_id == _current_enum_id() and _memory_res() == res_str:
				return
			_remember_camera_choice({"gesture_camera_res": res_str})   # V17：选择即写档
			GestureBridge.send_control("SET_RESOLUTION:%d:%dx%d" % [cam_id, res.x, res.y]))
		# 批次 X P3-b③：res 行 hover 只刷新 fps 列内容（不重弹不移位）——旧「mouse_entered
		# → _open_fps_sub 连锁弹」路径删除（帧率乱弹根因）。
		b.mouse_entered.connect(func() -> void: _refresh_fps_sub(cam_id))
		box.add_child(b)

func _position_res_sub(anchor_row: Control) -> void:
	# 锚定单一漏斗不变（coord_space.gd 契约 4；防坑 4：PopupPanel 无 get_global_rect）
	_res_sub.position = CoordSpace.popup_anchor_px(anchor_row.get_screen_transform().origin,
		Vector2(anchor_row.size.x, 0.0))
	add_child(_res_sub)
	_res_sub.popup()

## fps 子列（批次 X P3-b 重构 → 批次 Z Z6-P2-11 重锚）：hover 设备行时与 res 列同时同现——
## x=res 列左缘−渲染宽−右安全边距（显式坐标，紧贴 res 列左侧不叠压）、**y=菜单底缘+VGAP**
## （Z6-P2-11：旧 y=设备行底缘使列恒压锚行下方设备行右端——点设备名右半命中 fps 按钮写
## gesture_camera_fps 而非切设备；改锚菜单底缘下方=与全部设备行零相交的唯一无碰撞带）。
## 内容=该设备当前分辨率档帧率集（probe 缓存优先、current 设备回落全局矩阵）；仅 fps_options
## 非空弹出；行固定宽档（FPS_COL_BTN_W）——res 行滑动只经 _refresh_fps_sub 刷新内容，
## 不重弹不移位（旧「res 行 mouse_entered 连锁弹」路径已删，本方法仅设备行 hover 链与测试直达）。
## 批次 V-B2（V2/V4/V17）行棕化/选中高亮/no-op/写档语义原样保留。
func _open_fps_sub(cam_id: int, anchor_row: Control) -> void:
	_close_fps()
	var matrix: Dictionary = GestureBridge.get_probe_matrix(cam_id)
	if matrix.is_empty() and cam_id == int((GestureBridge.get_camera_enum() as Dictionary).get("current_camera", -1)):
		matrix = GestureBridge.get_camera_matrix()
	var fps_list: Array = (matrix as Dictionary).get("fps_options", [])
	if fps_list.is_empty() or _res_sub == null or not is_instance_valid(_res_sub):
		return
	_fps_sub = PopupPanel.new()
	_apply_popup_theme(_fps_sub)   # 批次 V-B2（V2）：Window 不跨主题传播（坑4）→ 挂载即显式注入
	var box := VBoxContainer.new()
	_fps_sub.add_child(box)
	_fps_box = box
	_fill_fps_buttons(cam_id, fps_list)
	# Z6-P2-11：y=菜单底缘+VGAP（锚控件改菜单根，漏斗仍 popup_anchor_px 单一口径）；
	# x=res 列左缘−(渲染宽+右安全边距) 显式坐标（魔法 106 退役留痕于 FPS_COL_TOTAL_W 注）。
	var menu_bottom: int = CoordSpace.popup_anchor_px(get_screen_transform().origin,
		Vector2(0.0, size.y + FPS_COL_VGAP)).y
	_fps_sub.position = Vector2i(
		int(_res_sub.position.x) - int(FPS_COL_RENDER_W + FPS_COL_MARGIN), menu_bottom)
	add_child(_fps_sub)
	_fps_sub.popup()

## fps 行构建（P3-b 提取共用：_open_fps_sub 建列与 _refresh_fps_sub 刷新同源单漏斗）。
func _fill_fps_buttons(cam_id: int, fps_list: Array) -> void:
	var mem_fps := _memory_fps()
	for f: Variant in fps_list:
		var n := int(f)
		var fb := Button.new()
		fb.text = "%d" % n
		fb.add_theme_font_size_override("font_size", 12)
		fb.custom_minimum_size = Vector2(FPS_COL_BTN_W, 0.0)   # P3-b：固定宽档（内容切换宽度不变）
		fb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		fb.set_meta("hover_glow", true)   # V2：hover_glow 显式兜底挂点
		fb.set_meta("fps_value", n)   # V2：选中态重算/主题跟随重刷识别用
		_tint_row(fb, cam_id == _current_enum_id() and mem_fps == n)   # V2：帧率子列选中态同口径
		fb.pressed.connect(func() -> void:
			# 批次 V-B2（V4）：已选值（当前设备+记忆值匹配）再点 no-op
			if cam_id == _current_enum_id() and _memory_fps() == n:
				return
			_remember_camera_choice({"gesture_camera_fps": n})   # V17：选择即写档
			GestureBridge.send_control("SET_FPS:%d:%d" % [cam_id, n]))
		_fps_box.add_child(fb)

## 批次 X P3-b②：res 行 hover → fps 列内容刷新（同一 PopupPanel 实例=零重弹、锚定不变=不移位）。
## 数据契约边界（勿自创）：Python 仅对当前分辨率探 fps_options 平铺数组——「刷新」现契约下为
## 同一集合（换 res 行不改集合内容）；集合消失（异常态防御）→ 收列不留空壳。
func _refresh_fps_sub(cam_id: int) -> void:
	if _fps_sub == null or not is_instance_valid(_fps_sub) \
			or _fps_box == null or not is_instance_valid(_fps_box):
		return
	var matrix: Dictionary = GestureBridge.get_probe_matrix(cam_id)
	if matrix.is_empty() and cam_id == int((GestureBridge.get_camera_enum() as Dictionary).get("current_camera", -1)):
		matrix = GestureBridge.get_camera_matrix()
	var fps_list: Array = (matrix as Dictionary).get("fps_options", [])
	if fps_list.is_empty():
		_close_fps()
		return
	for c: Node in _fps_box.get_children():
		(c as Node).free()   # 即刻释放（queue_free 延迟会混入新旧两代行；本件无他处引用行实例）
	_fill_fps_buttons(cam_id, fps_list)

## 批次 U（U2）超时裁决＋批次 V-B2（V16，spec §6.4）统一扩展：判据由「已发 PROBE 的 id」扩展为
## 「一切『检测中…』等待行」（_show_wait_state 记录的 _wait_started_ms）——含从未发过 PROBE 的
## id==current 矩阵等待行（init#2 未到瞬时窗），旧口径恒死等，本批根治。超 PROBE_TIMEOUT 且
## 等待行仍在 → 「检测失败」置灰；probe_result/矩阵到达照常先行刷新（到达即重建、无等待行可改）。
func _process(delta: float) -> void:
	# 哨兵判据用 != -1 而非 >= 0（R-B-1 第 10 段同款实证修正）：ms 时间戳在进程启动 N 秒内注入
	# 「N 秒前」为合法负值，>= 0 会误判为未设置哨兵（测试注入 now-9000 实锤）。
	if _res_box != null and _res_for_id >= 0 and _wait_started_ms != -1 \
			and Time.get_ticks_msec() - _wait_started_ms >= int(PROBE_TIMEOUT * 1000.0):
		_probe_requested_at.erase(_res_for_id)   # 已发 PROBE 的同步清节流记录（旧口径保留）
		_wait_started_ms = -1
		_mark_wait_rows_failed(_res_box)   # I18n 解耦①：改写收口单漏斗（meta 判定，可测）
	_check_timeout()
	if _spinner != null and state == MenuState.LOADING:
		_spin = fposmod(_spin + SPIN_RATE * delta, 360.0)
		(_spinner as Spinner).angle = deg_to_rad(_spin)
		_spinner.queue_redraw()

## I18n 解耦①（可测收口）：「检测中…」等待行超时改写——判据=行创建时 set_meta("i18n_wait")
## 状态位（旧 text=="检测中…" 文本反查退役：en 词条化后按钮文本随语言变，文本反查恒失效）。
## 非等待行（真实分辨率行/检测失败行）不受扰；判定与显示文案彻底解耦（zh/en 同逻辑）。
func _mark_wait_rows_failed(box: VBoxContainer) -> void:
	for n: Variant in box.get_children():
		# R2①-P2-3：非 Button 子级跳过不崩（as 强转 null 再取 .text 即 SCRIPT ERROR）
		if n is Button and bool((n as Button).get_meta("i18n_wait", false)):
			(n as Button).text = I18n.t("检测失败（设备无法打开）")
			(n as Button).disabled = true

func _defer_close_res() -> void:
	# P1-2（RV-2 (b) 案）：移出设备行不再无条件帧末收起——鼠标从行→子列的 hover 路径必先触发行
	# mouse_exited，无条件收起会在用户到达前自毁子列。改走帧末谓词判定（deferred 挂本件：
	# _close_res_deferred 系菜单方法，非 PopupPanel 方法）。
	if _res_sub != null and is_instance_valid(_res_sub):
		call_deferred("_close_res_deferred")

## P1-2：帧末真实鼠标位取数（box 与鼠标同 viewport 坐标系，可直比）后转谓词收起。
func _close_res_deferred() -> void:
	if _res_sub == null or not is_instance_valid(_res_sub):
		return
	var mouse: Vector2 = _res_box.get_global_mouse_position() \
		if _res_box != null and is_instance_valid(_res_box) else Vector2(-1e9, -1e9)
	_close_res_if_outside(mouse)

## P1-2（RV-2 (b) 案）：谓词收起——鼠标已入子列矩形 → 保活；否则「移出即收」原口径。
## mouse 注入口径供无头直测（plan §1.3 时序注同款；真实路径经 _close_res_deferred 取数）。
func _close_res_if_outside(mouse: Vector2) -> void:
	if _res_sub == null or not is_instance_valid(_res_sub):
		return
	if _res_sub_contains_mouse(mouse):
		return   # 鼠标在子列内 → 保活（行 mouse_exited 系 hover 途经，非真移出）
	_close_res()

func _res_sub_contains_mouse(mouse: Vector2) -> bool:
	# PopupPanel 是 Window（无 get_global_rect）：矩形取内容容器 box 的全局矩形（同 viewport 系）。
	# FV-1 P2-1 连带收起后必要伴随：行→fps 直穿途经 res 按钮 mouse_exited 时鼠标已在 fps 子列
	#（res 框外），谓词若只查 res 框会在用户抵达 fps 层瞬间把它连带杀掉（fps 不可达=P1-2 同类
	# 自毁）——故 res 框 ∪ fps 框任一含鼠标即保活。
	# 批次 Y（Y-A15，spec §2）：保活并集扩为 设备行∪分辨率列∪帧率列——鼠标落在任一设备行上
	# （含行间过渡带/相邻设备行）即保活：行 mouse_exited 帧末谓词重判时，新行 mouse_entered
	# 已重建子列，过渡帧收起会误杀新子列（斜向直达帧率列中途收起根因之一）。
	if _res_box != null and is_instance_valid(_res_box) and _res_box.get_global_rect().has_point(mouse):
		return true
	if _fps_box != null and is_instance_valid(_fps_box) and _fps_box.get_global_rect().has_point(mouse):
		return true
	for r: Variant in _rows:
		if r is Control and is_instance_valid(r as Control) \
				and (r as Control).get_global_rect().has_point(mouse):
			return true
	return false

## 批次 Y（Y-A15）：res 列单独收起（不连带 fps）——设备行 hover 重建 res 列专用；
## 级联收 fps 语义保留在 _close_res（移出三域并集/切菜单等收口路径不变）。
func _close_res_only() -> void:
	if _res_sub != null and is_instance_valid(_res_sub):
		_res_sub.hide()
		_res_sub.queue_free()
	_res_sub = null
	_res_box = null

func _close_res() -> void:
	_close_res_only()
	_close_fps()   # FV-1 P2-1：分辨率列收起连带帧率子列（鼠标移出分辨率行/切设备行不残留孤儿）

func _close_fps() -> void:
	if _fps_sub != null and is_instance_valid(_fps_sub):
		_fps_sub.hide()
		_fps_sub.queue_free()
	_fps_sub = null
	_fps_box = null

func _close_subs() -> void:
	_close_res()
	_close_fps()

# ================= 批次 V-B2（V1~V4/V17，spec §6.1/§6.2/§6.4）新增辅助 =================

## 当前设备 id 单一取数漏斗（选中态/no-op 判据共用；.get 防御硬纪律）
func _current_enum_id() -> int:
	return int((GestureBridge.get_camera_enum() as Dictionary).get("current_camera", -1))

## 存档 settings 防御读取（V17：三键由 V-D 路落地，未落地时缺省不阻塞）。经 SaveManager._data
## 判空兜底（get_settings() 对空档 `_data["settings"]` 取下标运行时错误，实证坑⑪同族）。
func _memory_settings() -> Dictionary:
	var data: Variant = SaveManager.get("_data")
	if data == null or typeof(data) != TYPE_DICTIONARY or (data as Dictionary).is_empty():
		return {}
	var s: Variant = (data as Dictionary).get("settings", {})
	return s if typeof(s) == TYPE_DICTIONARY else {}

func _memory_res() -> String:
	var v: Variant = _memory_settings().get("gesture_camera_res", "")
	return String(v) if v != null else ""

func _memory_fps() -> int:
	var v: Variant = _memory_settings().get("gesture_camera_fps", 0)
	return int(v) if v != null else 0

## 选择即写档（V17）：SWITCH/SET_RESOLUTION/SET_FPS 发出处同步经 SaveManager.update_settings
## 落 gesture_camera_device/gesture_camera_res/gesture_camera_fps（既有「变更即存」惯例同款）。
func _remember_camera_choice(patch: Dictionary) -> void:
	SaveManager.update_settings(patch)

## 行样式注入（批次 X P3-a 重写，设备/分辨率/帧率三分支同函数）：选中/未选**几何完全一致
## （margin 与主题 Button 档等值，尺寸差=0）只换色**——未选=灰底（探针 p3a_gray_probe_run1.log
## 对齐 settings_panel「全屏显示」常态 TOGGLE_OFF_BG 双档）+未选灰字（N4 保留）；选中=SEL_BG
## 金棕淡底+SEL 字色（保留）。normal/hover/pressed 三态同盒注入（「全屏显示」开关同款注入形态；
## hover 反馈由 ui_material 辉光承担，消除灰行×主题棕 hover 观感断层）。旧行为（选中档
## content_margin 6/6/2/2 压细=「变细」根因+未选无覆盖）随本批废止留痕。
func _tint_row(b: Button, selected: bool) -> void:
	b.add_theme_color_override("font_color", DARK_FONT_SEL if selected else DARK_FONT_DIM)
	for st: String in ["normal", "hover", "pressed"]:
		if b.has_theme_stylebox_override(st):
			b.remove_theme_stylebox_override(st)   # 先摘本件注入再解析主题档（margin 几何单源）
	var base: StyleBox = b.get_theme_stylebox("normal")
	var sb := StyleBoxFlat.new()
	sb.bg_color = SEL_BG_DARK if selected else DIM_BG_DARK
	sb.set_corner_radius_all(ROW_CORNER_RADIUS)
	if base != null:
		for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			sb.set_content_margin(side, base.get_content_margin(side))
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)

## 子列 PopupPanel 棕档注入（V2，坑4）：Window 不跨主题传播 → theme 显式赋当前主题 +
## panel StyleBox 深棕覆盖（GlassDialog 弹窗档同族圆角/描边）。
## ⚠ 实证坑（V-B2 实施留痕）：StyleBoxFlat 的 shadow_size 会计入 Window 最小尺寸（StyleBox
## get_margin 含阴影），popup() 装配钳位随之回拉位置 → 子列锚定偏移（test_fix_window_scale 段7
## 实锤 -10,-10）。故面板档禁用阴影、padding 走显式 content margins（锚定单一漏斗不受扰动）。
func _apply_popup_theme(p: PopupPanel) -> void:
	var t: Theme = ThemeManager.current_theme()
	if t != null:
		p.theme = t
	var sb := StyleBoxFlat.new()
	sb.bg_color = DARK_PANEL_BG
	sb.border_color = DARK_PANEL_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 8.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	p.add_theme_stylebox_override("panel", sb)

## 批次 AB-3：主题变更跟随回调（V2）随深浅主题机制删除退役——子列棕化由 _apply_popup_theme/
## _tint_row 在打开/构建时直挂，全局恒深档。
