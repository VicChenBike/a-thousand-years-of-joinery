extends Node
## GestureRouter：手势语义路由（批次 R autoload，spec §2.4/§4.2/§5/§6/§13 注 B）。
## 职责：守卫链（Game 状态+覆盖层开合+_input_locked+批次 Q 守卫环境）→ 意图执行：
## 合成事件经 GestureCursorLayer（content 坐标 push_input(ev,true)）；语义动作直调
## level_scene 既有公开方法（含下划线处理器，内部守卫全部生效，无特权通道，§5.5）；
## 面板注册制（§5.1 组 "gesture_panel"）+ 激活面板描边（§5.2）+ 单笔互斥（Map 层 §13 注 B）
## + 退出倒数（ExitGestureTracker → 弹窗信号 → §6.3 分流）。
## 批次 X（P5-a，spec §6，20260921）重映射终态：左手=鼠标左键完全等效（左键笔——two_down
## 双帧确认后立即合成左键按下，dwell 0.3s/28px 与 0.8s 冷却退役；点空白=ORBIT 现行为不变）；
## 右手=Ctrl+左键等效减选笔（点空白与键鼠完全同源不特判）；左三指=删除（命中单块走
## level_scene.delete_cell 同源删除链 / 未命中 delete_selected；聚焦锐眼手势退役走 UI 按钮）。
## 批次 AA（W3，spec §6.3 + §22 裁决 2/3，2026-09-25）**旧口径留痕**：语义重映射曾定
## 「清空=【右】掌静止 1.0s dwell」（更早「右手竖四指」亦退役）、**对接=双手同帧 two（均经确认帧）**且优先级高于单击
## （检测到双手同时 two → 抑制两侧 two_down 合成、改走 join；单侧 two 仍左键笔/右减选笔）、
## **缩放=双手协同**（批次 AC 4A；旧「任一手掌推拉」退役）。
## 批次 AD（§4.3.4，2026-09-28 审查回修）**现口径**：**清空=双手握拳**（食+中+无名三指 ≤0.35、
## 连续 2 帧、Latch；GestureMap._feed_dual_fist_clear → {"type":"clear","side":"both"}，
## HUD 行「7 清空选择【双手】握拳」同源）——右掌 dwell 通路已彻底废除，上列 AA 行仅存旧口径留痕。
## 不变项：撤销/重做=竖掌翻转、退出=双手四指同翻、左三指=删除（右手 three 零语义）、
## 双帧确认（单侧 two_down 仍在确认帧同帧补发，零时延）、键鼠零变化。
##
## 批次 AC 4B（spec §4.6-1/2/4/5/6/8，2026-09-27 用户实机反馈）关卡交互重构终态：
##  ①**视口显式绑定三态**（§4.6-1）：进关 _active_panel=null（态 0=未绑定，蓝色描边缺席）；
##    左手二指在**目标视口空白处**单击 → 仅绑定该视口并点亮 2px #3E7BBD 蓝框（态 1
##    SELECT_ARMED），**不触发选块、不进入旋转**（旧 Y-A13「首笔在块上同时激活+选块」旁路退役）；
##    绑定后一切选块/减选/删除/缩放/旋转**严格受限该视口**（未绑定=全部忽略）。
##  ②**态 2 ORBIT 不限框**（§4.6-2）：已绑定视口内空白处再次二指单击 → ORBIT；期间只要左手在
##    摄像头画面内移动（two_move 或 cursor_move）即按帧间位移持续调用 level_scene.orbit_rotate_panel
##    驱动该视口平滑旋转——**移出视口矩形绝不中断**（旧「panel 命中失败→_exit_orbit_to_select」
##    与「移出面板跳出 ORBIT」逻辑整体删除）；退出唯一途径=再次空白二指单击（含切换绑定他视口）
##    或手势完全消失（two_up/teardown → 回 SELECT_ARMED）。
##  ③**左三指=直接批量删除**（§4.6-4）：_do_delete 优先 delete_selected 删除全部已选块（无需
##    光标精准命中）；实际删除（removed>0）时回调 suppress_flip_after_delete 施加 0.6s 翻转冷却。
##  ④**右二指滑动连续减选**（§4.6-6）：_right_sliding 起笔即置位，滑过已选块逐一取消（旧「仅
##    首帧命中已选块才成笔」缺陷根除）；扫过未选块/空白绝不误选（纯减选笔口径保持）。
##  ⑤**键鼠焦点彻底隔离**（§4.6-8）：非手势按压期 cursor_move **不再向视口推送 synth_motion**
##    （手势光标圈 show_cursor 照常自绘）——真实物理鼠标 hover/点击 100% 归键鼠所有；
##    真实鼠标最近 1.5s 有移动时连按压期 motion 一并让位；合成 motion 仅在按下点
##    （_push_btn(pressed=true)）与笔画拖拽（_push_motion/_push_motion_ctrl）时下发。

signal countdown_started(remaining: int)
signal countdown_changed(remaining: int)
signal countdown_cancelled(reason: String)
signal exit_confirmed

const CLOUD_ROT_SENS := 0.25            # 点云旋转灵敏度 度/像素（§5.7 终态值）
const CURSOR_FRESH_SEC := 0.5    # S10 中指单击光标新鲜度门（批次 S spec §3-10/§5.3）
const CLICK_ARM_DEDUP_SEC := 0.1  # T5：双 armed 同窗互斥去重窗口（spec §5；起点=任一侧 arm 成功时刻，裁决 J8）
const CLICK_ARM_CONFIRM_FRAMES := 2  # 批次V §5.3：中指 armed 双帧稳定——armed 仅消费经语义层
                                     # CONFIRM_FRAMES=2 双帧确认产出（two_down.confirm_frames）的意图，
                                     # 单帧/缺标记直通一律静默（teardown 重入等旁路由 Map 补门+本门双封）
const OUTLINE_COLOR := Color("#3E7BBD") # 激活面板描边=光标 A 蓝（§5.2）
const NO_CELL := Vector3i(-1, -1, -1)   # 与 level_scene 哨兵一致（不 import，防编译期耦合）
# 批次 AC 4B（§4.6-8）：手势合成事件标记键——与 GestureCursorLayer.SYNTH_META 同源（_setup 内
# 经 get_script_constant_map 单点读取覆盖本缺省值，防字面量漂移；缺省同值供 _setup 前调用）。
const SYNTH_META_DEFAULT := "gesture_synth"
# 批次 AC 4B（§4.6-8）：真实物理鼠标「最近移动」让位窗（秒）——窗内禁止推送合成 motion，
## 保证真实键鼠 hover/点击 100% 归物理鼠标（手势光标圈 show_cursor 照常自绘，零注入）。
const REAL_MOUSE_YIELD_SEC := 1.5
# 批次 AC 4B（§4.6-4）：左三指删除=破坏性操作，与「至少三指翻转撤销」姿态同构——删除实际
# 发生（removed>0）时经 suppress_flip_after_delete 施加的防误触冷却（常量真值源=gesture_map）。
const MAIN_PANEL_PATH := "MainView/ViewportContainer"   # 主视图容器路径（左三指删除/选块语义域）
# 批次 AC 4B（§4.6-2）：ORBIT 退出途径②「手势完全消失」的在场兜底观察窗（连续丢手帧数）。
# ≈0.27s@30fps：短于 python 侧 hold 窗（0.3s）→ 陈旧 held 帧不会先被误清，且抖动重入可容忍。
const ORBIT_LOST_FRAMES := 8
# 批次 Z Z3-6（spec §3-5，用户拍板 2026-09-24）：TALK 态退出确认条文案——文件头部单点常量
# （逐字锁 tests/test_z_talk_exit_confirm.gd）。误触发四指同翻先弹条、用户确认才 _finish
# 跳过；取消则继续对话（消除「静默吞掉整段对话」缺陷）。
const TALK_SKIP_TEXT := "确定跳过本段剧情？"

# ---------- 批次 AA（域 W7，spec §10）：按钮失效根治相关常量 ----------
## W7-3 卡死看门狗帧数 N（§10.3/§10.7）：「引擎持 LEFT + 物理左键未按 + Router 无按压标志」
## 三条件**同时连续**成立 N 帧才强制补发抬起——单条件判定会误清合法手势长按（§10.6 风险 2）。
const STUCK_WATCHDOG_FRAMES := 30   # ≈0.5s@60fps 【暂定值·待用户复验】
## W7-3 强制抬起前先推一条**全屏之外**的 synth_motion：BaseButton 收 rect 外 motion 即把
## `pressuring_inside` 刷 false，随后抬起只结束按住态、**不触发 pressed**（防幽灵点击）。
## 无头探针实证（tests/w7_probe_release_route_temp.gd R3/R4）：不带 motion 直推抬起会误发
## pressed（幽灵点击），R5（motion@屏外 + release@按下位）button_up 正常且 pressed 零误发。
const STUCK_CLEAR_MOTION_POS := Vector2(-100000.0, -100000.0)

var _map: Variant                # GestureMap（load 规避 --script class_name 时序）
var _tracker: Variant            # ExitGestureTracker
var _cursor_layer: CanvasLayer = null   # main.gd 挂载后注入（set_cursor_layer）
var _active_panel: Node = null   # 面板选择模型：初始无激活（§5.2 终态）
var _active_ring: Control = null # 激活描边直引用（终审 P2-2：挂父层后不在 _active_panel 子树）
var _last_cursor_pos := {}       # side → content 坐标（zoom/delete 事件夹取基准）
var _cursor_seen := {}           # 批次 X（P2-5，spec §3-6）：side → bool 在屏标志——cursor_move 派发置位。
                                 # 与 Vector2(-1,-1)「从未有光标」哨兵语义分离：overshoot 后光标 content 坐标
                                 # 可为负（左缘余量带，至 −m×视宽），不得再以 pos.x<0 判「无光标」
var _last_two_pos := {}          # side → content 坐标（点云旋转 Δ 基准/笔画按下位）
var _left_stroking := false      # 左笔合成按下中（左键笔）
var _right_stroking := false     # 右笔 Ctrl 合成按下中（批次 X P5：Ctrl 减选笔；旧 _right_cancel_armed 更名，
                                 # 「0.4s 取消臂」语义退役、Ctrl 态随侧）
# 批次 AC 4B（§4.6-6）：右二指**滑动减选**常驻标志——起笔即置位（不再要求首帧命中已选块），
# 滑动期持续检测命中已选块并逐一取消（旧「从空白/未选格滑入→全程失效」缺陷根除）。
var _right_sliding := false
# 批次 AC 4B（§4.6-2）：ORBIT 旋转的帧间位移基准（content 坐标）。进 ORBIT 时=进入点，
# 其后每帧更新——**不限框**：光标移出视口矩形照常按帧间位移驱动绑定视口旋转。
var _orbit_last_pos := Vector2.INF
var _orbit_anchor_pos := Vector2.INF   # 批次 AD §4.3.1：ORBIT_PENDING 起始锚点坐标
const ORBIT_DRAG_THRESHOLD := 15.0     # 批次 AD §4.3.1：有界拖拽触发旋转阈值（像素）
# 批次 AC 4B（§4.6-2）：ORBIT 丢手兜底计数器（连续不在场帧数；在场/非 ORBIT 即归零）。
var _orbit_lost_frames := 0
var _right_press_pos := Vector2.INF   # 批次 W（P3-2b）沿改：右笔按下位（抬起统一取按下位）
var _armed_press_pos := {}            # 批次 W（P3-2b）：side → 单击按下位（抬起统一取按下位）
var _cloud_rotating := false     # 点云面板二指旋转中
var _menu_click_armed := {"left": false, "right": false}   # T5：per-side armed（spec §4-5-1；旧单布尔批次 S NG-1 同族防护升级）
var _click_arm_dedup_at := -100.0   # T5：互斥窗口起算时刻
var _level_mode := "SELECT_ARMED"   # T10：关卡模式状态机（批次 X P5 按「立即按下」重构：
                                    # SELECT_ARMED 块上=立即左键笔；空白=清选+ORBIT；ORBIT 进出语义保留）
var _last_cursor_at := {}        # S10：side → 最近 cursor_move 时刻（秒，dispatch cursor_move 时刷新）
var _prev_bridge_state := -1     # 批次 AA（W1-11 回修 P2-2②）：桥上一状态（-1=本会话未知）——
                                 # 「非 READY→READY」边沿清态判据；只记边沿，不逐事件清（反向护栏）
var _blocked_latched := false    # 修复批 P3（2026-09-26）：blocked 态迁移锁——禁用/非 READY 期
                                 # 恰在进入迁移时 reset 一次（清态不变量保持），持续 blocked 跳过；
                                 # 恢复供帧解除，防每包 reset + tracker cancelled 信号风暴（feed 内消费）
# ---------- 批次 AA（W7-1/W7-3）：合成 LEFT 按压台账与卡死看门狗 ----------
# 引擎 `Viewport::gui.mouse_focus_mask` **无公开读口**（Godot 4.7 探针
# tests/w7_probe_mouse_focus_temp.gd 实证：Viewport 属性/方法列表无 mouse_focus* 项），
# 故以**台账**建模「引擎正持 LEFT」：合成按下已推、抬起未推即为持 LEFT。
# 与物理左键（Input 单例）、Router 侧按压标志三者正交，构成 §10.6 风险 2 要求的三条件判据。
var _synth_left_held := false       # 台账真值（合成按下已推、抬起未推）
var _synth_left_pos := Vector2.ZERO # 该次按下位（W7-3 强制抬起落点=按下位，保证路由命中）
var _stuck_frames := 0              # 三条件连续成立帧计数（任一条件不成立即归零）
# ---------- 批次 AC 4B（§4.6-8）：真实物理鼠标新鲜度（键鼠焦点抢夺根治） ----------
## 真实物理鼠标最近一次移动时刻（秒；_unhandled_input 记录，-1e9=本会话尚未见真实鼠标）。
## 用途：手势合成 motion 让位窗（REAL_MOUSE_YIELD_SEC）——玩家正在用键鼠时手势绝不把引擎
## gui.mouse_over / mouse_focus 拽回手势光标位（用户实机缺陷「鼠标点按钮完全没反应」根因）。
var _last_real_mouse_time := -1.0e9
var _synth_meta_key := SYNTH_META_DEFAULT   # 合成事件 meta 键（_setup 内与光标层常量同源校准）

class PanelOutline extends Control:
	## 激活面板 2px 描边（自绘，mouse_filter=IGNORE，§5.2）
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("#3E7BBD"), false, 2.0)

func _ready() -> void:
	_setup()

## 批次 AC 4B（§4.6-8）：真实物理鼠标移动时刻记账（键鼠焦点抢夺根治的判据源）。
## 只记真实事件：手势合成事件带 SYNTH_META 标记，一律跳过（合成 motion 不刷新让位窗，
## 否则手势自身移动会把让位窗无限续期 → 手势按压期 motion 永久不发）。
## 双通道接线（`_input` + `_unhandled_input`，同一记账函数）：Godot 事件序为
## `_input` → GUI（Control 消费）→ `_unhandled_input`——**motion 一旦被 STOP 型 Control
## 的 gui_input 消费就不再进 `_unhandled_input`**（关卡/图鉴满屏 Control 常态），仅挂
## `_unhandled_input` 会漏记大部分真实移动、让位窗形同虚设；`_input` 恒先到达且对合成
## motion 有 meta 判别，故双挂为「指令面（unhandled）+ 可达性兜底（input）」同源实现，
## 两次记账幂等（同帧同值），零额外语义。
func _input(event: InputEvent) -> void:
	_note_real_mouse_motion(event)

func _unhandled_input(event: InputEvent) -> void:
	_note_real_mouse_motion(event)

func _note_real_mouse_motion(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm == null:
		return
	if mm.has_meta(_synth_meta_key):
		return   # 手势合成 motion 不计入真实鼠标新鲜度（防自我续期）
	_last_real_mouse_time = Time.get_ticks_msec() / 1000.0

## 幂等初始化（--script 测试可显式调用）
func _setup() -> void:
	if _map != null:
		return
	_map = load("res://scripts/gesture_map.gd").new()
	# 批次 X（P6，spec §7-3）：语义层识别态诊断日志开关——环境变量 GAME_GESTURE_DEBUG=1 开启
	# （默认关零写文件；真手复验定位用，dump=user://gesture_debug.log 逐帧 semantic/fingers/
	# confidence/intents）。波内定档：环境变量而非存档 settings——零存档 schema 变更、零 UI、
	# 复验会话一行命令可控（不设置即对正常玩家完全无扰）。
	if OS.get_environment("GAME_GESTURE_DEBUG") == "1":
		_map.set_debug_enabled(true)
	_tracker = load("res://scripts/gesture_exit_tracker.gd").new()
	_tracker.countdown_started.connect(func(r: int) -> void:
		_map.set_exit_countdown(true)
		countdown_started.emit(r))
	_tracker.countdown_changed.connect(func(r: int) -> void: countdown_changed.emit(r))
	_tracker.countdown_cancelled.connect(func(reason: String) -> void:
		_map.set_exit_countdown(false)
		countdown_cancelled.emit(reason))
	_tracker.exit_confirmed.connect(_on_exit_confirmed)
	# 批次 W（顺手项，W7 移交清单第四节）：绝对路径节点接线前置 is_inside_tree 守卫——
	# 非树内调用（--script 构建窗时序）时 /root 绝对路径 get_node 会产生引擎噪声；树内
	# _ready 路径接线必然完成，测试显式调用亦在 add_child 之后，守卫零行为影响。
	if not is_inside_tree():
		return
	var bridge: Node = get_node_or_null("/root/GestureBridge")
	if bridge != null and not bridge.gesture_state_received.is_connected(feed):
		bridge.gesture_state_received.connect(feed)
	# 批次 Y 扫描回修 P2-4：桥 UNAVAILABLE 边沿 → 语义层全量复位。旧口径复位仅发生在
	# 「帧到达而桥非 READY」（feed 守卫链）或场景切换——python 判死期无帧可达，复位不
	# 触发；重拉后首包 id 复位（"L0"/"R0"）与残留 hand_id 相同 → gesture_map id 断链清态
	# 永不触发，新物理手继承旧 zooming/flip 累计态。UNAVAILABLE 边沿（判死/断流/重拉
	# 失败）统一走 reset_runtime（幂等，S16 同款全量清：map/tracker/按下标志合成抬起一并收口）。
	# 批次 AA（W1-11 回修 P2-2②）：同一处理器另判**「非 READY→READY」边沿**强制清态
	# （python 重启 id 碰撞防护，见 _on_bridge_state_for_reset 注）。
	if bridge != null and not bridge.load_state_changed.is_connected(_on_bridge_state_for_reset):
		bridge.load_state_changed.connect(_on_bridge_state_for_reset)
	var game: Node = get_node_or_null("/root/Game")
	if game != null and not game.state_changed.is_connected(_on_game_state_changed):
		game.state_changed.connect(_on_game_state_changed)
	# 批次 AC 4B（§4.6-8）：合成事件 meta 键与光标层常量同源校准（零静态引用纪律——
	# 不 class_name 依赖，经 get_script_constant_map 单点读取；键名真值唯一源=光标层）。
	var cl_s: Variant = load("res://scripts/gesture_cursor_layer.gd")
	if cl_s is Script:
		var cl_c: Dictionary = (cl_s as Script).get_script_constant_map()
		_synth_meta_key = String(cl_c.get("SYNTH_META", SYNTH_META_DEFAULT))

## main.gd 挂载光标层后注入（未注入时仅语义动作生效、无合成事件）
func set_cursor_layer(layer: CanvasLayer) -> void:
	_cursor_layer = layer

## 批次 AA（W2-10，spec §5.3）：状态条显示名与游戏动作同源——直读语义层（GestureMap）
## 当前态，不经 python gesture_id 双轨口径（_classify_gesture 内部 0.6/0.7 严阈仅显示消费，
## 与运行时 fingers 通道判定脱钩，spec §5.2 R2-6）。HUD `_refresh_hand` 逐包调用；
## _map 未就位返回 ""（=待命）。桥→Router 的 feed 连接建立于 autoload _ready（早于场景
## HUD _ready），同包内 HUD 读到的即本帧已更新语义。
func side_semantic(side: String) -> String:
	if _map == null:
		return ""
	return String(_map.call("get_side_semantic", side))

func _on_game_state_changed(_from: int, _to: int) -> void:
	reset_runtime()

## 复位：激活面板唯一复位时机=场景退出（§5.2 终态）+ Map 状态清零。
## 终审 P2-3：补 tracker 复位——倒数中切场景（state_changed→本方法）若不清 ExitGestureTracker，
## _pending_start/_remaining/_done 残留：随后同翻在新状态接着旧计数触发 exit_confirmed/弹窗
## 残留抑制撤销重做；reset() 末尾补发 countdown_cancelled("reset")（批次 W P1-8b——弹窗跨场景
## 残留单点修复，main 侧幂等 hide 消费）。
func reset_runtime() -> void:
	# P2-1 回修：无头 --script 测试未走 _setup 时（_map/_tracker 为 null），state_changed 信号
	# 回调触发本方法曾空引用 SCRIPT ERROR → 函数中断、armed 清零步被跳过。逐成员判空守卫：
	# null 安全跳过对应清理；已 _setup 实例（两者恒成对就位）行为逐字节不变。
	if _map != null:
		_map.reset()
	if _tracker != null:
		_tracker.reset()
	_clear_outline()   # 内部已对 _active_ring 判空（is_instance_valid），未初始化时为 no-op
	_active_panel = null
	# 批次 W（P1-8a，规格 §5）：三类按下标志各按原 ctrl 语义补合成抬起再清零——
	# 旧码直接清零不派发抬起（抬起唯一出口 _push_btn），关卡左键卡死在按下态（ORBIT/STROKE
	# 虚拟键卡死）。按侧去重恰一次：左支 armed∨stroking→(false,false)、右支 stroking→(false,true)
	# （Ctrl 抬起配对，对齐 STROKE_DESELECT 抬起口径）；记位=该手最近 two 位（P3-2b 按下位
	# 同源），缺省回 _last_cursor_pos。清零动作在本调用之后（抬起位读取需在清缓存前）。
	_release_pressed_side("left")
	_release_pressed_side("right")
	_left_stroking = false
	_right_stroking = false
	_right_sliding = false   # 批次 AC 4B（§4.6-6）：滑动减选标志随复位清零
	_orbit_last_pos = Vector2.INF  # 批次 AC 4B（§4.6-2）：ORBIT Δ 基准清零
	_orbit_anchor_pos = Vector2.INF # 批次 AD §4.3.1：ORBIT 准备态锚点清零
	_orbit_lost_frames = 0         # 批次 AC 4B（§4.6-2）：丢手兜底计数器清零
	_right_press_pos = Vector2.INF
	_armed_press_pos = {}
	_cloud_rotating = false
	_menu_click_armed = {"left": false, "right": false}   # S16：关手势/场景切换清单击 armed（T5 双侧清零）
	_click_arm_dedup_at = -100.0   # T5：互斥窗口随 armed 清单一并关闭（防误杀后续顺序单击）
	_level_mode = "SELECT_ARMED"   # T10：状态机复位（批次 X P5：dwell/冷却成员随重映射退役，无残留态）
	# 批次 W（P3-2c，规格 §5）：光标缓存三键跨场景清零——_last_cursor_pos（zoom 夹取基准）、
	# _last_two_pos（点云旋转 Δ 基准）、_last_cursor_at（单击新鲜度门）旧档残留会以陈旧坐标
	# 参与新场景首帧判定。
	_last_cursor_pos = {}
	_cursor_seen = {}   # 批次 X（P2-5）：在屏标志与光标缓存同生命周期（W P3-2c 跨场景清零同族）
	_last_two_pos = {}
	_last_cursor_at = {}
	# 批次 AA（W7-4，spec §10.3）：场景切换/复位**同一 reset 语义**内清引擎残留按压态
	# （§23.1.3：不新增第二套清态入口）——按下标志全清后 _release_pressed_side 按标志早退，
	# 无法兜住「台账真而标志已清」的卡死态（W7-1 前的丢抬起残留、通道缺席期丢抬起等），
	# 由台账兜底补发抬起；非卡死态本调用为 no-op（幂等，重复 state_changed 零事件）。
	# 批次 AA 回修5（W7-P3-4，防御深度）：**物理按压中不强制释放**——补 Input 读口早退，
	# 闭合「陈旧台账 + 真实按压中 + 场景切换」同帧叠加窗（强制释放的三步序列与真实按压
	# 事件同帧叠加会打乱引擎 focus）；物理按压期台账保持真，待物理抬起后由 W7-3 看门狗
	# 三条件兜底补发（既有护栏②链路）。
	if _synth_left_held and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_force_gui_release()
	_stuck_frames = 0

## P1-8a 合成抬起兜底（按侧恰一次）：仅在存在对应按下标志时派发。
func _release_pressed_side(side: String) -> void:
	var armed: bool = bool(_menu_click_armed.get(side, false))
	var is_left_pressed: bool = side == "left" and (_left_stroking or armed)
	var is_right_pressed: bool = side == "right" and (_right_stroking or armed)
	if not is_left_pressed and not is_right_pressed:
		return
	var pos: Vector2 = _last_two_pos.get(side, _last_cursor_pos.get(side, Vector2(-1.0, -1.0)))
	# Ctrl 抬起配对：仅右笔 true（对齐 _on_two_up 的 STROKE_DESELECT 抬起口径）；
	# 右支 armed 单击（无笔画）仍走普通抬起——语义以笔画段优先（同帧并存实况不可能）。
	var ctrl: bool = side == "right" and _right_stroking
	_push_btn(pos, false, ctrl)

## 桥信号转发入口（测试可直调注入帧）
func feed(data: Dictionary) -> void:
	_setup()
	if not _bridge_ready() or not _gesture_enabled():
		# 修复批 P3（2026-09-26）：状态迁移才 reset——旧码每包调 reset_runtime（禁用期 N 个
		# blocked 包 → N 次全量清态 + tracker countdown_cancelled N 连发）。latch 语义：
		# 进入 blocked 恰清一次（首次进入必须清，清态不变量保持），持续 blocked 跳过；
		# 恢复供帧（下方非 blocked 路径）解除 latch，下次再入 blocked 重新清一次。
		if not _blocked_latched:
			_blocked_latched = true
			reset_runtime()   # S16：禁用/非 READY → 全量复位（tracker/描边/面板/armed 一并清）
		return
	_blocked_latched = false
	var now := Time.get_ticks_msec() / 1000.0
	_tracker.tick(now, _both_present(data))
	# 批次 AA（W1-11，spec §4.3）：心跳空包 `stale` 顶层字段透传语义层（协议**只增不改**，
	# 老包无该键 → 缺省 false → feed_frame 走原路径行为零变化）。用 `== true` 判型——对任意
	# Variant 安全（dict/数组/字符串/null 一律 false，不触发 4.7 实证规律⑦ bool(null) 中止）。
	var intents: Array = _map.feed_frame(data.get("left"), data.get("right"), now,
		data.get("stale", false) == true)
	for it_v: Variant in intents:
		_dispatch(it_v)
	# 批次 AC 4B（§4.6-2）：ORBIT 退出途径②「手势完全消失」——语义层无 two_up 可发的场景
	# （旋转期仅食指瞄准时整手离开）也要收口；见 _orbit_presence_watch 注。
	_orbit_presence_watch(now, _side_present(data.get("left")))

## 批次 Y 扫描回修 P2-4：桥 UNAVAILABLE 边沿复位（接线与动机见 _setup 注）。
## 批次 AA（W1-11 回修 P2-2②，审查 ACCEPT-WITH-FIXES）：追加**「非 READY→READY」边沿**强制清态。
## 动机：python 进程重启后 id 计数器归零 → 新手复得 "L0" 等**旧 id** → gesture_map 的
## 「id 变=新手」断链判据（hid != prev_id）永不触发 → 旧手 zooming/flip_locked/flip_streak
## 等累计态泄入新手会话（审查 P2-2 (b)）。桥在 `_set_state(READY)` 里**先发** load_state_changed、
## **后** emit 首包（gesture_bridge `_poll_udp`），故边沿清态恒发生在新会话首包被 feed 之前。
## 反向护栏（审查明令）：**只在非 READY→READY 迁移上触发**——READY→READY 重复事件不清
## （「每次 READY 都清」会误清正常重连后的累计态）；首帧（prev==-1，本会话未知）亦不清。
func _on_bridge_state_for_reset(state: int) -> void:
	# 批次 AA 终审回修3（aarev P3-1）：树外早退守卫——桥 _exit_tree→stop_gesture_process→
	# _set_state→load_state_changed 时序里本回调可达，而此时树已拆，下方 /root/GestureBridge
	# 绝对路径 get_node_or_null 触发引擎 ERROR「Can't use get_node() with absolute paths from
	# outside the active scene tree.」（两次走查复现的退出期噪声）。不在树内本就无法取桥
	# （旧码 b==null 早退等价），首行守卫只消噪声不改语义；_prev_bridge_state 同帧不必记账
	# （拆树期状态边沿对已退出会话无意义，重进树为新实例恒 -1）。
	if not is_inside_tree():
		return
	var prev := _prev_bridge_state
	_prev_bridge_state = state
	var b: Node = get_node_or_null("/root/GestureBridge")
	if b == null:
		return
	if state == int(b.LoadState.UNAVAILABLE):
		reset_runtime()   # 批次 Y 扫描回修 P2-4（既有）：判死/断流/重拉失败边沿全量复位
		return
	if state == int(b.LoadState.READY) and prev != -1 and prev != int(b.LoadState.READY):
		reset_runtime()   # 批次 AA P2-2②：非 READY→READY 边沿（LOADING/UNAVAILABLE → READY）

# ---------- 守卫链（§4.2/§5.5） ----------

func _bridge_ready() -> bool:
	var b: Node = get_node_or_null("/root/GestureBridge")
	return b == null or int(b.get_load_state()) == int(b.LoadState.READY)

func _gesture_enabled() -> bool:
	var s: Node = get_node_or_null("/root/SaveManager")
	if s == null:
		return true
	return bool(s.get_settings().get("gesture_input", true))

## 语义分区（§4.2）：level=关卡专属手势可用；cloud=点云观察类；none=静默。
## 覆盖层（设置/商店）打开 → 语义动作一律静默（键鼠永远可用，玩家用键鼠操作面板）。
func _semantic_zone() -> String:
	var game: Node = get_node_or_null("/root/Game")
	if game == null:
		return "none"
	if game.is_settings_open() or game.is_shop_open():
		return "none"
	var st := int(game.current_state())
	if st == int(game.State.LEVEL):
		return "level"
	if st == int(game.State.CATALOG) or st == int(game.State.SETTLE):
		return "cloud"
	return "none"

## T5 分区（spec §4-5-3）：替代对 `_semantic_zone()=="none"` 的直接依赖——
## 设置/商店覆盖层开 → true；zone none（主菜单/开场/对话/弹窗）→ true；
## cloud（CATALOG/SETTLE）光标在全部 gesture_panel 注册矩形之外 → true、之内 → false（面板模型）；
## level → false；BOOT 由调用点 _game_booting() 前置拦截。side 参数预留对称语义（左右手同分区）。
func _click_zone(side: String) -> bool:
	var game: Node = get_node_or_null("/root/Game")
	if game == null:
		return false
	if game.is_settings_open() or game.is_shop_open():
		return true
	match _semantic_zone():
		"level":
			# 批次 W（N7，拍板 8，**推翻批次 T 拍板 3**，规格 §5）：关卡内 UI 按钮放开合成单击——
			# 光标悬停控件为 Button 族或挂 meta("interactive") → true；3D 体素区维持 false
			#（N8 交互模型零污染：悬停选中/二指点选/划选删除/点空白旋转全部不变）。
			# 陷阱（规格 §5-N7）：gui_get_hovered_control() 跟随真实鼠标，手势合成点击时不可用
			# ——按 _last_cursor_pos 位置推送 synth motion 后取 hover 态（引擎 GUI 命中测试，
			# content 坐标口径与 push_input 一致）；防误触=armed 单击仅悬停按钮时生效。
			return _hovered_ui_interactive(side)
		"cloud":
			return _panel_at(_last_cursor_pos.get(side, Vector2(-1.0, -1.0))) == null
		_:
			return true

## N7：按手势光标位置判定悬停控件是否 UI 可点（Button 族祖先链 ∪ meta("interactive")）。
func _hovered_ui_interactive(side: String) -> bool:
	if _cursor_layer == null:
		return false
	var pos: Vector2 = _last_cursor_pos.get(side, Vector2(-1.0, -1.0))
	# 批次 X（P2-5，spec §3-6）：哨兵语义分离——旧以 pos.x<0.0 判「该手从未有 cursor_move」，
	# overshoot 后真实光标 content x 可为负（左缘余量带）会被误判无光标；改在屏标志判定，
	# 负坐标光标正常走下方 hover 实测路径（命中判定交引擎，不特判）。
	if not bool(_cursor_seen.get(side, false)):
		return false
	var vp := get_viewport()
	if vp == null:
		return false
	# 推送一次合成 motion 刷新引擎 hover 态（与 cursor_move 常规推送同管线；armed 期
	# cursor_move 静默，但本判定发生在 armed 之前/二指按下瞬间，推送无副作用）。
	# 批次 AA 回修5（W7-P3-5，防御深度）：**W7-2 同门**——物理左键按压期不推合成 motion
	#（现行唯一调用链 _on_two_down 经上层门传递性覆盖，此处补门防未来新增调用方破防；
	# 物理按压期判定沿用真实 hover 态，语义安全）。
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_cursor_layer.call("push", _cursor_layer.call("synth_motion", pos))
	var hovered: Control = vp.gui_get_hovered_control()
	var cur := hovered
	while cur != null and is_instance_valid(cur):
		if cur is BaseButton or cur.has_meta("interactive"):
			return true
		cur = cur.get_parent() as Control
	return false

## S10：BOOT 期静默（语义区矩阵：BOOT 无点击；game 缺失同判）
func _game_booting() -> bool:
	var game: Node = get_node_or_null("/root/Game")
	return game == null or int(game.current_state()) == int(game.State.BOOT)

## S10：该手光标 CURSOR_FRESH_SEC 内有 cursor_move（_last_cursor_at 由 dispatch cursor_move 刷新）
func _cursor_fresh(side: String) -> bool:
	return _last_cursor_at.has(side) \
		and Time.get_ticks_msec() / 1000.0 - float(_last_cursor_at[side]) <= CURSOR_FRESH_SEC

## `_input_locked` 期间语义动作一律忽略、观察类豁免（§4.2）。
## 无关卡场景（含结算边缘路径）视为未锁。
func _locked() -> bool:
	var lv: Node = _level()
	return lv != null and bool(lv.call("is_input_locked"))

## 当前关卡场景（有 select_voxel 公开方法才认；SETTLE 边缘路径也是 level 场景）
func _level() -> Node:
	var game: Node = get_node_or_null("/root/Game")
	if game == null:
		return null
	var sc: Node = game.get_current_scene()
	if sc != null and sc.has_method("select_voxel"):
		return sc
	return null

func _both_present(data: Dictionary) -> bool:
	# 批次 Y（Y-A5，spec §3.1 held 映射定档）：held 帧（丢帧容忍窗内陈旧数据）计为在场——
	# 倒数不因 hold 窗（0.3s）内丢帧取消；真离场超窗（null/无效 dict）才计离场，
	# ExitGestureTracker 自身 0.8s 防抖（HAND_LOST_CANCEL_SEC）兜底收尾。
	var l: Variant = data.get("left")
	var r: Variant = data.get("right")
	return _side_present(l) and _side_present(r)

func _side_present(h: Variant) -> bool:
	if typeof(h) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = h
	if d.is_empty():
		return false
	return bool(d.get("is_detected", false)) or bool(d.get("held", false))

func _content(normalized: Variant) -> Vector2:
	var vp := get_viewport()
	var size := Vector2(1152, 648)  # 设计视口兜底（project.godot stretch 基准）
	if vp != null:
		size = vp.get_visible_rect().size
	return (normalized as Vector2) * size

# ---------- 意图分派 ----------

func _dispatch(it: Dictionary) -> void:
	var t: String = String(it.get("type", ""))
	match t:
		"cursor_move":
			var cm_side: String = String(it["side"])
			_last_cursor_pos[cm_side] = _content(it["pos"])
			_cursor_seen[cm_side] = true   # 批次 X（P2-5）：在屏标志置位（负坐标光标≠无光标）
			# 批次 AD 审查回修 P2-4（2026-09-28）：仲裁参考=**刷新前**的双侧时刻——若在下方刷新
			# 之后再比，本侧恒为最新，双手同帧仍退化为「末位右手覆盖」（详见 push 处注）。
			var l_pre := float(_last_cursor_at.get("left", -1.0))
			var r_pre := float(_last_cursor_at.get("right", -1.0))
			_last_cursor_at[cm_side] = Time.get_ticks_msec() / 1000.0   # S10：单击新鲜度门刷新
			if _cursor_layer != null:
				_cursor_layer.call("show_cursor", cm_side, _last_cursor_pos[cm_side])
			# 批次 AC 4B（§4.6-8）**旧口径留痕**：曾定「非手势按压期 cursor_move 绝不向视口推送
			# synth_motion」（旧码空闲帧逐帧注入把真实鼠标 hover/点击拽坏）。
			# 批次 AD §4.3.5 **现口径演进**：巡航期恢复轻量 synth_motion（点亮 hover_glow，见下方
			# AD 门），键鼠隔离不削弱——仍收在 `_cursor_layer != null` + armed/jitter/物理左键 +
			# `not _real_mouse_recent()` 总门内；show_cursor 照常自绘。按下点/笔画补位沿用 AC 4B。
			if cm_side == "left" and _orbit_mode_active():
				# 态 2 ORBIT（§4.6-2）：不限框——只要**左手**在摄像头画面内移动（two_move/cursor_move
				# 均可），即按帧间位移持续驱动绑定视口平滑旋转（不推合成 motion，纯语义驱动）。
				# 手别门：旋转是左手专属语义（右二指=减选笔），右手移动绝不驱动旋转。
				_orbit_apply_move(_last_cursor_pos[cm_side])
			# 批次 AD §4.3.5：轻量 synth_motion 巡航注入更新 GUI hover 光晕
			# 当手势光标巡航移动且真实物理鼠标静止（超过 1.5s 避让窗）时，向 Viewport 发送轻量合成 motion，
			# 即时更新 gui_get_hovered_control() 点亮 hover_glow；真实鼠标移动时立即避让。
			# 批次 AD-3 回修：光标层缺席（未挂载/无头兼容）整体跳过——与既有 `_cursor_layer == null`
			# 早退守卫同口径（原码缺守卫致无 MockLayer 夹具 cursor_move 分派抛「call on null」SCRIPT ERROR）。
			# 批次 AD 审查回修 P2-4（2026-09-28）：注入位**按最近活跃手仲裁**（_last_cursor_at）——
			# feed_frame 恒先左后右，双手同帧各派一条 cursor_move 时旧码直推 cm_side，末位右手覆盖
			# 引擎指针 → 左手正悬停的控件 hover_glow 点不亮。仲裁判据（用**刷新前**捕获的 l_pre/r_pre）：
			#   · 左手派发 → 左手位（本帧先派发侧，天然正确）；
			#   · 右手派发且 l_pre > r_pre（左手本帧已派发、比右手上一帧新 = 双手同帧双活跃）
			#     → 取左手位（同帧平手左手胜，末位右手不覆盖）；
			#   · 右手派发且左手时间戳陈旧（左手不在场/未派发）→ 右手位（单手场景零变化）。
			# 引擎指针单点，同帧双活跃只能照亮一处；右手按钮命中由 _push_btn 按下点补位兜底。
			if _cursor_layer != null \
					and not bool(_menu_click_armed["left"]) and not bool(_menu_click_armed["right"]) \
					and not bool(it.get("jitter", false)) \
					and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) \
					and not _real_mouse_recent():
				var syn_side := cm_side
				if cm_side == "right" and l_pre > r_pre:
					syn_side = "left"
				_cursor_layer.call("push", _cursor_layer.call("synth_motion", _last_cursor_pos[syn_side]))
		"two_down":
			_on_two_down(it)
		"two_move":
			_on_two_move(it)
		"two_up":
			_on_two_up(it)
		"delete":
			# 批次 AC 4B（§4.6-4）：左三指=直接批量删除全部已选（无需光标精准命中某格）。
			if _semantic_zone() == "level" and not _locked():
				_do_delete()
		"clear":
			# 批次 AD §4.3.4：双手握拳清空当前已绑定视口的全部选区
			if _semantic_zone() == "level" and not _locked() and _active_panel != null:
				_clear_bound_view_selection()
		"palm_begin", "zoom_begin", "zoom_end":
			pass  # 缩放态生命周期标记（表现由 zoom_step/zoom_factor 承载）
		"zoom_factor":
			_do_zoom_factor(it)
		"zoom_step":
			_do_zoom_step(it)
		"undo":
			if _semantic_zone() == "level" and not _locked():
				_level().call("undo")                     # :1096
		"redo":
			if _semantic_zone() == "level" and not _locked():
				_level().call("redo")                     # :1120
		"join":
			if _semantic_zone() == "level" and not _locked():
				_level().call("_on_join_pressed")         # :2021（:2022 四重守卫生效）
		"exit_flip":
			# 批次 Z（Z6-P2-1，spec §6）：全屏视频期不推进退出倒数——图鉴全屏黑底层压住
			# 倒数弹窗/确认条却照跑（白做无反馈、确认条被压则单槽被占），全屏在场谓词门。
			if not _exit_gesture_blocked():
				_tracker.call("notify_flip", Time.get_ticks_msec() / 1000.0)

# ---------- 面板选择模型（§5.1/§5.2） ----------

## 批次 Z（Z6-P2-1，spec §6）：退出倒数全屏门——当前场景自报「全屏视频在场」即阻断
## exit_flip 推进（catalog_scene.is_video_fullscreen 消费点；其他场景无该谓词恒 false）。
func _exit_gesture_blocked() -> bool:
	var game: Node = get_node_or_null("/root/Game")
	if game == null:
		return false
	var sc: Node = game.get_current_scene()
	return sc != null and sc.has_method("is_video_fullscreen") \
		and bool(sc.call("is_video_fullscreen"))

func _panel_rect(panel: Node) -> Rect2:
	if panel.has_method("gesture_panel_rect"):
		return panel.call("gesture_panel_rect")
	return (panel as Control).get_global_rect()   # 三视图容器未实现契约 → 全局矩形回退

func _panel_at(pos: Vector2) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for n: Node in tree.get_nodes_in_group("gesture_panel"):
		if n is Control and _panel_rect(n).has_point(pos):
			return n
	return null

func _set_active_panel(panel: Node) -> void:
	_clear_outline()
	_active_panel = panel
	if panel == null:
		return
	var rect: Rect2 = _panel_rect(panel)
	var ring: PanelOutline = PanelOutline.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 终审 P2-2：描边按面板全局矩形精确定位（catalog=center_mount 契约带，关卡三视图=容器
	# 矩形与旧 PRESET_FULL_RECT 挂容器自身等值）——旧实现挂注册节点+FULL_RECT，catalog 注册
	# 节点=场景根 → 描边画成全屏框。现挂 panel 的 Control 父层，面板全局矩形经父逆变换换算
	# 本地坐标 set_position/set_size；父层非 Control（场景根直挂 root Window 等）兜底挂 panel
	# 自身（同为全局矩形换算），双兜底皆无 Control 挂点时保留历史 FULL_RECT 行为。
	var par: Node = panel.get_parent()
	var host: Control = null
	if par is Control:
		host = par
	elif panel is Control:
		host = panel
	if host != null:
		host.add_child(ring)
		ring.set_position(host.get_global_transform().affine_inverse() * rect.position)
		ring.set_size(rect.size)
	else:
		panel.add_child(ring)
		ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_active_ring = ring
	ring.visible = true

func _clear_outline() -> void:
	# 终审 P2-2：描边挂 panel 父层后不再必然位于 _active_panel 子树——改经 _active_ring
	# 直引用释放（is_instance_valid 防场景切换后已释放）。
	if _active_ring != null and is_instance_valid(_active_ring):
		_active_ring.queue_free()
	_active_ring = null
	_active_panel = null

# ---------- 笔生命周期（左=左键笔 / 右=Ctrl 减选笔，批次 X P5-a） ----------

func _on_two_down(it: Dictionary) -> void:
	var side: String = String(it["side"])
	# 批次 AA（W7-2，spec §10.3「按下可丢」的源头收口）：真实物理左键按压期间不发起**任何**
	# 合成按下/笔画/面板激活——若只在 _push_btn 丢按下，armed/笔画标志会先于引擎态置位而
	# 脱节（标志真、引擎无按下），随后 two_up 的抬起就成了对**真实鼠标正按控件**的幽灵抬起
	# （W7-1 放行抬起后更危险）。早退同时封死 _hovered_ui_interactive 的合成 hover 探测 motion
	# （真实按压期该 motion 同样会打掉真实按压）。真实抬起后本门自动放行，手势零感知。
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	# 批次V §5.3：armed 双帧稳定消费门——防坑 2 一律 .get 防御取键；Map 是 two_down 唯一生产者
	# 且恒携带 confirm_frames=2，本门仅拦截未来单帧直通/合成注入，正常链路零变化。
	if int(it.get("confirm_frames", 0)) < CLICK_ARM_CONFIRM_FRAMES:
		return
	_last_two_pos[side] = _content(it["pos"])
	# S10（批次 S spec §3-10/§5.3）→ T5（批次 T spec §4-5）：中指单击四重门放宽为左右手各自判定
	# （语义区→click_zone 分区/非 BOOT/光标 0.5s 新鲜度/per-side armed 成对）。
	# LEVEL 悬停 UI 按钮时 armed 合成单击（N7 链零改动——双手皆可点按钮，普通单击非 Ctrl）。
	if not _game_booting() and _click_zone(side) and _cursor_fresh(side):
		if bool(_menu_click_armed[side]):
			return   # 该侧已 armed（按下未抬起）→ 同侧静默
		var now_t := Time.get_ticks_msec() / 1000.0
		if now_t - _click_arm_dedup_at < CLICK_ARM_DEDUP_SEC:
			return   # 双 armed 同帧互斥：0.1s 窗口内后到侧该笔静默（spec §4-5-风险，裁决 J8）
		_click_arm_dedup_at = now_t
		_menu_click_armed[side] = true
		var press_pos: Vector2 = _last_cursor_pos.get(side, Vector2(-1.0, -1.0))
		_armed_press_pos[side] = press_pos   # 批次 W（P3-2b）：按下位记位——抬起统一取按下位
		_push_btn(press_pos, true, false)
		return
	# 右手（批次 X P5-a）：关卡内非按钮区=Ctrl 减选笔——立即合成 Ctrl+左键按下（与键鼠
	# Ctrl+左键完全同源：块上=toggle/反选划，空白=键鼠 Ctrl 点空白原行为，零特判）。
	if side == "right":
		if _semantic_zone() == "level" and not _locked():
			_on_level_two_down(side)
		return
	# 左笔：光标所在面板决定「激活/切换」或「开始交互」（§5.2）
	# 自查回修（R-C 交付时）：该手从无 cursor_move（直接伸二指）时取缺省屏外坐标 → 命中不了任何
	# 面板 → 走下方 panel==null 无动作路径；直接下标取缺失键会运行时报错中断 feed。
	var panel := _panel_at(_last_cursor_pos.get("left", Vector2(-1.0, -1.0)))
	if panel == null:
		# 批次 AC 4B（§4.6-2）：**ORBIT 不限框**——视口外起笔既不退出旋转也不产生任何动作
		#（旧批次 W P1-8c「panel 命中失败 → action 回待命」随「移出视口绝不中断旋转」拍板退役：
		# 旋转期间手/光标移出矩形属常态，强制回待命正是用户实机反馈的旋转中断根因）。
		return   # 空白处伸中指=无动作、当前激活保持（§5.2 无取消激活路径）
	if _semantic_zone() == "level" and not _locked():
		# 批次 AC 4B（§4.6-1）：LEVEL 区面板**绑定/切换/选块/旋转**全部收口 _on_level_two_down
		# 三态状态机（绑定仅由视口空白单击完成；未绑定/换视口态的块上起笔零动作——旧 Y-A13
		# 「首笔在体素块上同时激活并选块」旁路整体退役）。
		_on_level_two_down(side)
		return
	if panel != _active_panel:
		_set_active_panel(panel)   # 非 LEVEL 区：激活/切换仅描边反馈，键鼠无感知（§5.2）
		return   # 激活/切换那一笔不产生交互（§5.2 契约保持）
	if _semantic_zone() == "cloud" and _panel_viewer(panel) != null:
		_cloud_rotating = true   # 已选中的点云区：本笔进入旋转（§5.7）

## 批次 AC 4B（§4.6-1/§4.6-2，2026-09-27）：关卡视口绑定三态状态机（绑定/待命/旋转）。
## 态 0（未绑定或目标视口≠绑定视口）：左手二指在**目标视口空白处**单击 → 仅绑定该视口并点亮
##   2px #3E7BBD 蓝框（态 1），不选块不旋转；块上起笔零动作；全部视口之外零动作。
## 态 1（已绑定待命 SELECT_ARMED）：绑定视口内块上起笔=立即合成左键按下（左键笔，键鼠同源
##   划选/单选替换全链）；绑定视口内空白处单击=进入态 2（清空该视口选区 + 提示行 + Δ 基准）。
## 态 2（ORBIT 旋转）：只要左手在摄像头画面内移动即按帧间位移持续旋转绑定视口（不限框，
##   移出视口矩形不中断）；退出唯一途径=绑定视口内空白处二指单击（或落在另一视口顺带切换绑定），
##   以及手势完全消失（_on_two_up）。
## 右手分支=Ctrl 减选笔（Y-A12 纯减选笔）+ 批次 AC 4B 滑动减选（§4.6-6）：起笔即置滑动标志，
##   滑过已选块逐一取消；起笔点必须落在绑定视口矩形内，未绑定一律忽略。
func _on_level_two_down(side: String) -> void:
	var pos: Vector2 = _last_two_pos.get(side, Vector2(-1.0, -1.0))
	var lv: Node = _level()
	if lv == null:
		return
	if side == "right":
		_on_level_two_down_right(pos, lv)
		return
	_on_level_two_down_left(pos, lv)

## 右手二指（Ctrl 减选笔 + 批次 AC 4B §4.6-6 滑动减选）起笔。
func _on_level_two_down_right(pos: Vector2, lv: Node) -> void:
	# ORBIT/ORBIT_PENDING 态选块类手势统一忽略（左右口径对称，与左二指/左三指 P3-2 判据同款）。
	# 批次 AD 审查回修 P2-2（2026-09-28）：判据收紧补入 ORBIT_PENDING——准备态（压下未越阈）
	# 同属旋转流程，旧码只挡正式 ORBIT，准备态内右二指仍可起减选笔（越 spec 窄判）。
	if String(_level_mode) == "ORBIT" or String(_level_mode) == "ORBIT_PENDING":
		return
	if _active_panel == null or not is_instance_valid(_active_panel):
		return   # 批次 AC 4B（§4.6-1 态 0）：未绑定视口 → 减选忽略
	if _panel_at(pos) != _active_panel:
		return   # §4.6-1 态 1：减选起笔点必须位于绑定视口矩形内（视口隔离）
	# 批次 AC 4B（§4.6-6）：起笔即置滑动标志（旧码仅首帧命中已选块才成笔 → 从空白/未选块
	# 滑入已选块全程失效的缺陷根除）。扫过未选块绝不误选：仅命中已选块才合成事件。
	_right_sliding = true
	if _panel_view_kind(_active_panel) != "Main":
		return   # 视口选区（_side_selected）无公开已选谓词 → 减选笔主视图专属（同左三指删除界）
	var cell_r: Vector3i = _hit_cell(pos)
	if cell_r == NO_CELL or not bool(lv.call("is_cell_selected", cell_r)):
		return   # 未选块/空白 → 不发事件（纯减选笔；two_down 仍正常入待判态，滑过已选块再成笔）
	# 右笔（Ctrl 减选笔）：按下位记位（P3-2b 口径——抬起统一取按下位），Ctrl 态随侧
	_right_stroking = true
	_right_press_pos = pos
	_push_btn(pos, true, true)

## 左手二指（视口绑定三态状态机主体，§4.6-1/§4.6-2）。
func _on_level_two_down_left(pos: Vector2, _lv: Node) -> void:
	var panel := _panel_at(pos)
	# ---- 态 2（ORBIT / ORBIT_PENDING）：仅绑定视口内**空白**单击可退出（不限框口径：视口外/块上起笔一律保持）----
	if String(_level_mode) == "ORBIT" or String(_level_mode) == "ORBIT_PENDING":
		if panel == null:
			return                       # 视口外起笔：旋转持续（移出视口绝不中断）
		if _hit_panel_cell(panel, pos) != NO_CELL:
			return                       # 块上起笔：静默保持旋转（防误选，仅空白单击可退出）
		_exit_orbit_to_select()          # 空白二指单击 → 退出旋转（退出途径①）
		if panel != _active_panel:
			_set_active_panel(panel)     # 落在另一视口 → 顺带切换绑定（§4.6-2 末条）
		return
	# ---- 态 0（未绑定 / 目标视口≠绑定视口）：空白单击=绑定（或切换绑定）----
	if _active_panel == null or panel != _active_panel:
		if panel == null:
			return                       # 全部视口之外：零动作（无绑定对象）
		if _hit_panel_cell(panel, pos) != NO_CELL:
			return                       # 块上起笔不绑定（§4.6-1：必须空白处单击完成绑定）
		_set_active_panel(panel)          # 绑定/切换：点亮 2px #3E7BBD 蓝框
		_level_mode = "SELECT_ARMED"      # 态 1（待命）
		_orbit_last_pos = Vector2.INF
		_orbit_anchor_pos = Vector2.INF
		return                           # 绑定当笔仅绑定：不选块、不进入旋转
	# ---- 态 1（已绑定待命）：块上=左键笔；空白=进入准备态 ORBIT_PENDING ----
	if _hit_panel_cell(_active_panel, pos) != NO_CELL:
		_left_stroking = true
		_push_btn(pos, true, false)       # 立即合成左键按下=左键笔（绑定视口内选块）
		return
	# 批次 AD §4.3.1：在已绑定视口的空白处按下左手二指，不立即切换到 ORBIT 模式，
	# 而是进入准备态 ORBIT_PENDING，记录起始屏幕坐标 _orbit_anchor_pos = pos
	_left_stroking = false
	_orbit_lost_frames = 0                 # 丢手观察窗从进入 ORBIT_PENDING 起算
	_level_mode = "ORBIT_PENDING"
	_orbit_anchor_pos = pos
	_orbit_last_pos = pos

## 批次 AC 4B（§4.6-1）：绑定视口类别（"Main"/"Target"/"Join"；未绑定/非三视图 → ""）。
## 三视图容器节点同名（ViewportContainer），以关卡场景内路径寻址比对（唯一真值源）。
func _panel_view_kind(panel: Node) -> String:
	var lv: Node = _level()
	if lv == null or panel == null or not is_instance_valid(panel):
		return ""
	for pair: Array in [["Main", MAIN_PANEL_PATH],
			["Target", "TargetView/ViewportContainer"], ["Join", "JoinView/ViewportContainer"]]:
		if lv.get_node_or_null(String(pair[1])) == panel:
			return String(pair[0])
	return ""

## 批次 AC 4B（§4.6-1）：视口命中判定（经 level_scene.hit_panel_cell 公开契约，按绑定视口分流
## 主视 _raycast_cell / 侧视 _raycast_side_at）。无关卡或旧场景无该方法时回退主视 _hit_cell。
func _hit_panel_cell(panel: Node, pos: Vector2) -> Vector3i:
	var lv: Node = _level()
	if lv == null:
		return NO_CELL
	if panel != null and lv.has_method("hit_panel_cell"):
		return lv.call("hit_panel_cell", panel, pos)
	return _hit_cell(pos)

## 批次 AC 4B（§4.6-1）：清空**绑定视口**选区——主视=_selected（clear_selection 公开链）、
## 侧视=_side_selected（level_scene 既有下划线处理器直调，工程既有语义动作直调口径，§5.5）。
func _clear_bound_view_selection() -> void:
	var lv: Node = _level()
	if lv == null or _active_panel == null:
		return
	match _panel_view_kind(_active_panel):
		"Main":
			lv.call("clear_selection")
		"Target", "Join":
			var which := _panel_view_kind(_active_panel)
			if lv.has_method("_clear_side_selection"):
				lv.call("_clear_side_selection", which)

## 批次 AC 4B（§4.6-2）：ORBIT 活跃谓词（态 2 且绑定视口有效）。
func _orbit_mode_active() -> bool:
	return String(_level_mode) == "ORBIT" and _active_panel != null \
		and is_instance_valid(_active_panel)

## 批次 AC 4B（§4.6-2）：ORBIT 不限框旋转驱动——按帧间位移调用绑定视口旋转（主视/侧视同链），
## **不校验光标是否仍在视口矩形内**（用户拍板：只要手在摄像头画面内移动就必须持续旋转）。
func _orbit_apply_move(now_pos: Vector2) -> void:
	if not _orbit_mode_active() or _semantic_zone() != "level" or _locked():
		return
	var lv: Node = _level()
	if lv == null or not lv.has_method("orbit_rotate_panel"):
		return
	var prev_pos: Vector2 = _orbit_last_pos
	_orbit_last_pos = now_pos
	if prev_pos == Vector2.INF:
		return                           # 首帧仅立基准（Δ 不可得）
	var rel := now_pos - prev_pos
	if rel == Vector2.ZERO:
		return
	lv.call("orbit_rotate_panel", _active_panel, rel)

## 批次 AC 4B（§4.6-8）：真实物理鼠标让位窗判据——最近 REAL_MOUSE_YIELD_SEC 秒内有真实鼠标
## 移动 → 手势合成 motion 一律不发（手势光标圈照常自绘，引擎 hover/焦点 100% 归物理鼠标）。
func _real_mouse_recent() -> bool:
	return Time.get_ticks_msec() / 1000.0 - _last_real_mouse_time <= REAL_MOUSE_YIELD_SEC

## ORBIT → SELECT_ARMED 回待命（N15 提示行随之还原；态 2 的退出出口共用）。
func _exit_orbit_to_select() -> void:
	if String(_level_mode) != "ORBIT" and String(_level_mode) != "ORBIT_PENDING":
		return
	_level_mode = "SELECT_ARMED"
	_orbit_last_pos = Vector2.INF
	_orbit_anchor_pos = Vector2.INF
	_set_orbit_hint(false)

## N15：旋转模式提示行开关（走 level_scene 公开方法；无关卡/方法缺失静默——无头兼容）。
func _set_orbit_hint(active: bool) -> void:
	var lv: Node = _level()
	if lv != null and lv.has_method("set_orbit_hint"):
		lv.call("set_orbit_hint", active)

func _on_two_move(it: Dictionary) -> void:
	var side: String = String(it["side"])
	var now_pos: Vector2 = _content(it["pos"])
	var prev: Vector2 = _last_two_pos.get(side, now_pos)
	_last_two_pos[side] = now_pos
	if side == "left":
		if String(_level_mode) == "ORBIT_PENDING":
			# 批次 AD §4.3.1：按住二指拖动位移 > 15px 才正式切入 ORBIT。
			# 批次 AD 审查回修 P2-1（2026-09-28）：越阈帧**只立 Δ 基准**（_orbit_last_pos=now_pos），
			# 不再直调 _orbit_apply_move——旧码在切入帧把「压下点→越阈点」的 15~20px 全量位移
			# 当单帧 Δ 施加，起手即一次可见的单帧阶跃旋转；现基准重置到越阈点，阶跃归零，
			# 自下一帧起按正常帧间位移平滑驱动（行为面：切入帧零旋转，其余帧零变化）。
			if (now_pos - _orbit_anchor_pos).length() > ORBIT_DRAG_THRESHOLD:
				_level_mode = "ORBIT"
				_clear_bound_view_selection()
				_set_orbit_hint(true)
				_orbit_last_pos = now_pos
		elif String(_level_mode) == "ORBIT":
			_orbit_apply_move(now_pos)
		elif _left_stroking:
			_push_motion(now_pos)    # 按住拖动=STROKE 累加/空白 ORBIT（既有处理器分流）
		elif _cloud_rotating and _active_panel != null and is_instance_valid(_active_panel):
			var viewer: Control = _panel_viewer(_active_panel)
			if viewer != null:
				var rect: Rect2 = _panel_rect(_active_panel)
				# 主会话裁决（R-E-2 上报）：spec §5.7 灵敏度口径=归一帧间差 × 区块像素宽 × 0.25——
				# 原实现 content 像素差 × rect 像素宽属双重乘视口宽（实测 Δ=期望×1152），此处
				# 除回视口宽还原归一差（仅点云分支；关卡合成事件路径 content 坐标口径不变）。
				# 视口兜底与 _content() 同口径（未入树 1152×648）。
				var vp_size := Vector2(1152, 648)
				var rvp := get_viewport()
				if rvp != null:
					vp_size = rvp.get_visible_rect().size
				var dx: float = (now_pos.x - prev.x) / vp_size.x * rect.size.x * CLOUD_ROT_SENS
				var dy: float = (now_pos.y - prev.y) / vp_size.y * rect.size.y * CLOUD_ROT_SENS
				viewer.call("rotate_by", dx, dy)   # §5.7 直调（0.25 度/像素）
	else:
		# 批次 AC 4B（§4.6-6）：右手二指**滑动连续减选**——只要滑动标志（起笔即置）在场，逐帧
		# 检测光标命中的已选块并逐一取消（旧码仅 two_down 首帧命中已选块才成笔，从空白/未选格
		# 滑入已选块全程失效=用户实机「单点未命中即失效」根因）。扫过未选块/空白绝不误选。
		_on_right_slide(now_pos)

## 批次 AC 4B（§4.6-6）：右手二指滑动减选单帧处理（自含事件推送，调用方零分支）。
## 命中已选块：未成笔 → 立即成笔（记按下位 + 合成 Ctrl+左键按下 @ 当前命中位，按下即取消该格）；
## 已成笔 → 推送 Ctrl motion 走 STROKE_DESELECT 扫选，并**兜底确认**该格若仍为选中态则直调
## select_voxel(additive) 取消（合成 motion 被让位窗/物理按压门拦截时通道仍不失效）。
## 未命中/未选块/非绑定主视口/ORBIT（含 ORBIT_PENDING 准备态）态 → 仅维持既有笔画 motion，零选中副作用。
func _on_right_slide(now_pos: Vector2) -> void:
	if not _right_sliding and not _right_stroking:
		return
	# 批次 AD 终验补强 F-1（2026-09-28）：模式门补入 ORBIT_PENDING——准备态（压下未越阈）与正式
	# ORBIT 同属旋转流程，口径与 P2-2 的 _do_delete / _on_level_two_down_right 守卫保持一致；
	# 旧码只挡正式 ORBIT，准备态内右二指滑入已选块仍会当帧成笔并取消该格（越 spec 窄判）。
	if String(_level_mode) == "ORBIT" or String(_level_mode) == "ORBIT_PENDING" or _semantic_zone() != "level" or _locked():
		if _right_stroking:
			_push_motion_ctrl(now_pos)
		return
	var lv: Node = _level()
	if lv == null or _active_panel == null or _panel_view_kind(_active_panel) != "Main":
		if _right_stroking:
			_push_motion_ctrl(now_pos)
		return
	var cell_m: Vector3i = _hit_cell(now_pos)
	if cell_m == NO_CELL or not bool(lv.call("is_cell_selected", cell_m)):
		if _right_stroking:
			_push_motion_ctrl(now_pos)   # 滑过未选块/空白：仅维持既有笔画（绝不误选）
		return
	if not _right_stroking:
		# 滑入已选块 → 立即成笔（按下位=当前命中位，Ctrl 态随侧；按下即 toggle 取消该格）
		_right_stroking = true
		_right_press_pos = now_pos
		_push_btn(now_pos, true, true)
		return
	_push_motion_ctrl(now_pos)           # Ctrl+按住拖动=批量反选划（STROKE_DESELECT 扫选）
	if bool(lv.call("is_cell_selected", cell_m)):
		lv.call("select_voxel", cell_m, true)   # 兜底：本帧合成 motion 未达视口时直接取消选中

func _on_two_up(it: Dictionary) -> void:
	var side: String = String(it["side"])
	if side == "left":
		if bool(_menu_click_armed.get(side, false)):
			_menu_click_armed[side] = false
			_click_arm_dedup_at = -100.0   # T5 实施勘误：互斥窗口随该侧 armed 释放关闭——窗口语义
			# =「双 armed 并存」互斥（同帧/同窗双 two_down），armed 释放（含 Map teardown 兜底
			# two_up）后冲突源消失；不关窗则 0.1s 真实时钟窗会误杀顺序单击（click_route 段 1→3、
			# t_click_expand 段 1→2/段 3/段 5/段 7 顺序 arm 场景红灯实证）。
			# 批次 W（P3-2b）：抬起位统一取按下位（armed 记位；抖动致点错目标缺陷——按下位与
			# armed 判定同帧坐标，命中即用户所指数）。
			_push_btn(_pop_armed_press_pos(side), false, false)
		if _left_stroking:
			_left_stroking = false
			_push_btn(_content(it["pos"]), false, false)   # 合成抬起=结束笔画（笔画末端=抬起帧位，语义正确不改）
		_cloud_rotating = false
		# 批次 AD §4.3.1：自然退出——松开中指（手势转为单食指瞄准 cursor 或静止 rest），或姿势
		# 变更经 two_up 落到非 two 语义（含张开无名指成三指确认瞬 sem=""），立即自动退出旋转模式，
		# 平滑回到 SELECT_ARMED 待命态。
		# 安全不变量注记（批次 X P3-2 纵深防御保持）：_do_delete 内 `if _level_mode=="ORBIT": return`
		# 守卫**保留不删**——本批两指进旋转须经 >15px 拖拽（§4.3.1），真机在纯 ORBIT 态直落三指删除
		# 姿势必先得 two_up 退转，守卫在常规喂帧路径下不再被命中，但作为「旋转中绝不误删全部选区」
		# 的最后一道代码防线常驻（单元级直调 _dispatch 断言其在位，见 test_x_gesture_remap 段 8）。
		if String(_level_mode) == "ORBIT" or String(_level_mode) == "ORBIT_PENDING":
			var sem := side_semantic("left")
			if sem == "cursor" or sem == "" or sem == "rest":
				_exit_orbit_to_select()
	else:
		# T5（spec §4-5-1「对应侧 armed → 抬起＋清」）：右手单击已随四重门放宽启用，
		# per-side armed 成对释放同步覆盖右支（plan diff 6 左支代码块的对侧必然延伸）。
		if bool(_menu_click_armed.get(side, false)):
			_menu_click_armed[side] = false
			_click_arm_dedup_at = -100.0   # 互斥窗口随 armed 释放关闭（同左支勘误注记）
			_push_btn(_pop_armed_press_pos(side), false, false)   # T5：右手单击抬起（P3-2b 按下位）
		_right_sliding = false   # 批次 AC 4B（§4.6-6）：滑动减选标志随该侧手势生命周期清零
		if _right_stroking:
			_right_stroking = false
			# 批次 W（P3-2b）：Ctrl 抬起位=笔画按下位（记位；旧码用抬起帧指尖位）。
			var rel_pos: Vector2 = _right_press_pos
			_right_press_pos = Vector2.INF
			_push_btn(_content(it["pos"]) if rel_pos == Vector2.INF else rel_pos,
				false, true)   # Ctrl+抬起（STROKE_DESELECT 无抬起兜底=Q1 口径）

## 批次 AD 审查回修 P2-9（2026-09-28）：旧「ORBIT 期手势仍在」谓词 `_orbit_hand_alive()`
##（判语义层 two/cursor）**零调用方，已删除退役留痕**——AC 4B 语义层判据经实测覆盖不到
##「旋转期仅食指瞄准、整手离场」残余场景（见下条注释），当时已由 `_orbit_presence_watch`
## 在场兜底取代；谓词本体遗留至今无人消费，随本批清理移除。
##
## 批次 AC 4B（§4.6-2）：ORBIT 退出途径②「手势完全消失」的**在场兜底**（成员声明见文件头
## ORBIT_LOST_FRAMES / _orbit_lost_frames 段）。
## 动机（旧 `_orbit_hand_alive` 语义层判据覆盖不到的残余场景）：旋转期仅以食指瞄准时
## （语义层已非 two），整手离开画面**不会**产生 two_up（Map 的 two_up 只在 two 语义退出时发）
## → 上一判据无可触发点。
## 判据：该侧连续 ORBIT_LOST_FRAMES 帧不在场（null/无效 dict；held 陈旧帧按在场计，与
## `_side_present` 同口径）即视为手势消失 → 回 SELECT_ARMED（绑定保持）。
## 计数器仅在「非 ORBIT」或「在场」时清零，故进入 ORBIT 前后无需显式武装——进 ORBIT 那一刻
## 起算的丢手序列天然从 0 开始（其余状态零影响）。
func _orbit_presence_watch(_now: float, left_present: bool) -> void:
	if not _orbit_mode_active() and String(_level_mode) != "ORBIT_PENDING":
		_orbit_lost_frames = 0
		return
	if left_present:
		_orbit_lost_frames = 0
		return
	_orbit_lost_frames += 1
	if _orbit_lost_frames >= ORBIT_LOST_FRAMES:
		_orbit_lost_frames = 0
		_exit_orbit_to_select()

## P3-2b：取该侧 armed 按下位并清除记位；缺记位（旁路 two_up，如 Map teardown 兜底抬起
## 未经理armed 路径）回退 _last_cursor_pos（该手最近光标位——抬起帧位在旁路场景已不可得，
## 光标位与 armed 记位同属用户所见坐标族，优于旧「抬起帧指尖位」口径）。
func _pop_armed_press_pos(side: String) -> Vector2:
	var pos: Variant = _armed_press_pos.get(side, null)
	_armed_press_pos.erase(side)
	if pos == null:
		return _last_cursor_pos.get(side, Vector2(-1.0, -1.0))
	return pos as Vector2

## 批次 AC 4B（§4.6-4，2026-09-27 用户拍板）：**左三指（食+中+无名）=直接批量删除全部已选块**。
## 守卫：zone==level、未锁、非 ORBIT、且已绑定视口为主视图（选块/删除语义域）。
## 行为：优先 `delete_selected()` 批量删除全部已选木块——**无需指尖精准命中某个体素**（旧
## X P5-a「命中单块 delete_cell / 未命中才 delete_selected」双分支整体退役=用户「删不掉」根因）；
## 选区为空时才尝试单删命中格（保留「照着一块删一块」的顺手语义，未命中则零动作）。
## 防误触护栏：实际删除了体素（removed>0）时回调 `suppress_flip_after_delete("left", now)`
## 施加 DELETE_FLIP_GUARD_SEC(0.6s) 翻转冷却——三指删除与「至少三指翻转=undo」姿态同构，
## 收手瞬间手腕自然偏转极易被立即误判为撤销把刚删的块恢复回来；选区为空（removed==0）时不置
## 冷却，玩家伸左三指翻转即可顺畅触发 undo（§4.6-4 末条）。
func _do_delete() -> void:
	# 批次X收口（P3-2，spec §12 拍板）：ORBIT 旋转态删除一律忽略——删除是破坏性操作，与 ORBIT
	# 「防误选」设计对齐（spec §6 未 carve out，全项目扫描补门）；判据与既有口径同款
	# （String(_level_mode) == "ORBIT"）。退出 ORBIT（空白二指回待命）恢复可用。
	# 批次 AD 审查回修 P2-2（2026-09-28）：判据收紧补入 ORBIT_PENDING——准备态（压下未越阈）
	# 同属旋转流程，旧码只挡正式 ORBIT，准备态内左三指仍可触发批量删除（破坏性窄判漏洞）。
	if String(_level_mode) == "ORBIT" or String(_level_mode) == "ORBIT_PENDING":
		return
	var lv: Node = _level()
	if lv == null:
		return
	# 批次 AC 4B（§4.6-1）：未绑定视口 / 绑定的是侧视口 → 删除忽略（视口隔离；左三指删除的
	# 选区语义域=主视图 _selected，侧视口选区无公开删除链）。
	if _panel_view_kind(_active_panel) != "Main":
		return
	var removed: int = 0
	if (lv.call("get_selected_voxels") as Array).size() > 0:
		removed = int(lv.call("delete_selected"))   # 优先：批量删除全部已选（无需精准命中）
	else:
		var pos: Vector2 = _last_cursor_pos.get("left", Vector2(-1.0, -1.0))
		var cell: Vector3i = _hit_cell(pos)
		if cell != NO_CELL:
			removed = int(lv.call("delete_cell", cell))   # 选区为空：照着一块删一块
	if removed > 0 and _map != null:
		# 删除实际发生 → 施加该侧翻转防误触冷却（0.6s；选区为空时零副作用不加冷却）
		var now := Time.get_ticks_msec() / 1000.0
		if _map.has_method("suppress_flip_after_delete"):
			_map.call("suppress_flip_after_delete", "left", now)

## T10 命中判定（spec §6.3）：复用 level 既有 _raycast_cell 路径（容器逆变换），
## 返回命中格；空白/无关卡 → NO_CELL 哨兵。
func _hit_cell(pos: Vector2) -> Vector3i:
	var lv: Node = _level()
	if lv == null:
		return NO_CELL
	var cont: Node = lv.get_node_or_null("MainView/ViewportContainer")
	if cont == null or not (cont is Control):
		return NO_CELL
	var local: Vector2 = (cont as Control).get_global_transform().affine_inverse() * pos
	return lv.call("_raycast_cell", local, cont)

# 批次 X（P5-a）退役留痕：_hit_selected_cell（命中已选块判定）唯一消费方 _on_deselect_arm
# 已随「右手二指按住已选块 ≥0.4s 取消臂」整体退役——函数删除，无死分支残留。
# 聚焦锐眼手势（批次 T/U _do_focus 链路：无选中 toast/已聚焦静默/_toggle_focus 直调）随
# P5-a 三指让位删除整体退役——聚焦/锐眼/时长菜单全走 UI 按钮（批次 X P4 已修通手势点击）。

# ---------- 缩放双通道（§5.3 注 3 / §5.7） ----------

## 点云连续缩放：zoom_by(factor) 每帧直调（§5.7，非滚轮步进）
func _do_zoom_factor(it: Dictionary) -> void:
	if _semantic_zone() != "cloud":
		return
	# 批次 Z（Z6-P2-6，spec §6）：补三级回退（与 _do_zoom_step 同病灶同序——其头注自认
	# 「未激活面板回退」）：激活面板 → 光标命中面板 → 组内首个可缩放面板。旧实现在
	# _active_panel 空时静默 return = 图鉴/结算**直接掌推拉缩放 100% 失效**（须先二指点一下
	# 点云区激活才生效；红测锁定）。
	# 批次 AA（W3 独立审查回修 P2-3 附带，判断=一并按 side 修）：光标命中面板的回退源由写死
	# "left" 改取**本意图所属手**——W3-1 后右手单独掌推拉可达，取左手陈旧位会命中错面板。
	# 兜底链零变化（_first_zoomable_panel 三级回退保持）；缺 side 键（旧调用/测试直调）按 "left"
	# 缺省 = 行为逐字节不变（4.7 实证规律⑪：裸 it["side"] 对缺键意图会中止脚本，故用 .get）。
	var side := String(it.get("side", "left"))
	var panel: Node = _active_panel
	if panel == null or not is_instance_valid(panel):
		panel = _panel_at(_last_cursor_pos.get(side, Vector2(-1.0, -1.0)))
	if panel == null:
		panel = _first_zoomable_panel()
	if panel == null:
		return
	var viewer: Control = _panel_viewer(panel)
	if viewer != null:
		viewer.call("zoom_by", float(it["factor"]))

## Z6-P2-6：组内首个可缩放面板（get_gesture_viewer 契约命中者——视频面板等无 viewer 不入列）
func _first_zoomable_panel() -> Node:
	if not is_inside_tree():
		return null
	for n: Node in get_tree().get_nodes_in_group("gesture_panel"):
		if n is Control and is_instance_valid(n) and _panel_viewer(n) != null:
			return n
	return null

## 三视图滚轮步进：位置=**本意图 side 那只手**光标暂停前最后坐标夹取面板矩形内（面板外取该面板
## 中心，§5.3）——批次 AA W3 回修 P2-3：旧码写死 "left"，右手 zoom 落点错位（红测 7a/7b/7d）。
## 批次 X（P6，spec §7-1 回放实证）：未激活面板回退——面板模型=二指激活，用户「直接掌推拉」
## 时 _active_panel 恒空，旧实现此处静默 return=掌推拉缩放 100% 失效（红测锁定）。
## 回退序：激活面板 → 光标位命中面板 → 关卡主视图（缩放主消费对象）。
func _do_zoom_step(it: Dictionary) -> void:
	if _semantic_zone() != "level" or _locked() or _cursor_layer == null:
		return
	# 批次 AC 4B（§4.6-1，2026-09-27 用户拍板）：**缩放严格受限绑定视口**——未绑定任何视口
	# （态 0）时关卡内缩放直接忽略；已绑定则只向该绑定视口的矩形内发送滚轮事件。
	# 旧「未激活/未绑定 → 回退主视图」分支整体退役（旧 X5/Z6-P2-6 回退链为「掌推拉缩放 100%
	# 失效」补丁；AC 4B 以显式绑定 + 视口隔离取代回退，语义更严：不再因随手推拉而缩放某个
	# 从未被选中的视口）。旧判据零残留（本函数为 LEVEL 专属；点云/结算走 _do_zoom_factor 不涉）。
	if _active_panel == null or not is_instance_valid(_active_panel):
		return
	# 批次 AA（W3 独立审查回修 P2-3，spec §6.3 W3-1 后果）：本函数按 `it["side"]` 取**该手**光标位。
	# 缺 side 键按 "left" 缺省 = 旧调用零变化（实证规律⑪ .get 防御）。
	var side := String(it.get("side", "left"))
	var rect: Rect2 = _panel_rect(_active_panel)
	var pos: Vector2 = _last_cursor_pos.get(side, rect.get_center())
	if not rect.has_point(pos):
		pos = rect.get_center()   # 该手光标不在绑定视口内 → 落点取该视口中心（视口隔离不变）
	_cursor_layer.call("push", _cursor_layer.call("synth_wheel", pos, int(it["dir"])))

func _panel_viewer(panel: Node) -> Control:
	if panel != null and panel.has_method("get_gesture_viewer"):
		var v: Variant = panel.call("get_gesture_viewer")
		if v is Control:
			return v
	return null

# ---------- 合成事件推送 ----------

func _push_btn(pos: Vector2, pressed: bool, ctrl: bool) -> void:
	# 批次 W（P2-6，规格 §5）：键鼠手势互斥门——物理鼠标左键按下期间丢弃本帧**合成按下**
	# （合成事件直进 GUI 管线，同按钮双触发双扣费防线；motion/滚轮不在此门内）。合成事件经
	# viewport.push_input 注入、不更新 Input 单例按下态，故手势自身链路永不见物理按下=零影响。
	# 批次 AA（W7-1，spec §10.3）：门改为**「按下可丢、抬起必达」**——release（pressed==false）
	# **无条件放行、不经互斥门**。旧码按下与抬起走同一道门：合成按下已发出而抬起瞬间物理左键
	# 恰好按下 → 抬起被丢弃，且 Router 侧标志已在 _on_two_up 先行清零 → 永不补发 → 引擎左键
	# 「按住」不放，后续真实点击全部路由到陈旧 mouse_focus（R7-2 根因）。
	# 幽灵抬起缓解（§10.6 风险 1）：全部 release 调用点（_on_two_up / _release_pressed_side）
	# 均以「该侧确有按下标志」为前置，无按下时零事件。
	if pressed and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	if _cursor_layer == null:
		return
	# 批次 AC 4B（§4.6-8）：手势**真正发起按下**的当帧先推一条合成 motion 定位悬停控件
	# （BaseButton 的 pressuring_inside 依赖按下前后指针在 rect 内——按下点必须显式补位，
	# 否则悬停/点击判定落空=「手势点按钮失效」回归）。
	# 批次 AD 审查回修 P2-3（2026-09-28）：旧注「非按压期已不再逐帧推送 motion」随 AD §4.3.5
	# 巡航注入恢复而过期——空闲巡航期光标层可注入轻量 synth_motion（见 _dispatch cursor_move
	# 分派点），但按下点补位语义**不变**：按下帧坐标须就地锚定，不依赖巡航注入的时序。
	# 抬起（pressed=false）不补 motion：抬起按 mouse_focus 路由，补 motion 反而可能挪走
	# 引擎 focus（W7-1 抬起必达语义保持）。
	if pressed:
		_cursor_layer.call("push", _cursor_layer.call("synth_motion", pos))
	_cursor_layer.call("push", _cursor_layer.call("synth_button", pos, pressed, ctrl))
	# 合成 LEFT 按压台账（W7-3 判据第一条件；引擎 gui.mouse_focus_mask 无公开读口，见成员注）
	if pressed:
		_synth_left_held = true
		_synth_left_pos = pos
		return
	# 抬起清账**仅在物理左键未按**时确认——物理同按期引擎 gui.mouse_focus 很可能已被真实按下
	# 挪走（真实鼠标压在空白/其它控件上），本条抬起会**落空**（release 只按 mouse_focus 路由、
	# 无命中回退；无头探针 w7_probe_phys_focus_temp V2/V3 实证：合成按下后注入 parse 物理按下，
	# 随后合成抬起 button_up 不发射）。落空时不能记作「引擎已释放」，台账保持真，待物理抬起后
	# 由 W7-3 看门狗按三条件兜底补发（补发序列见 _force_gui_release）。物理未按=抬起必达、
	# 与既有链路逐字节一致，零额外事件。
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_synth_left_held = false

func _push_motion(pos: Vector2) -> void:
	if _cursor_layer == null:
		return
	# 批次 AA（W7-2）：真实物理按压期间冻结合成 motion（与 cursor_move 推送同门）
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	# 批次 AC 4B（§4.6-8）：真实鼠标让位窗内不推合成 motion（键鼠焦点 100% 归物理鼠标）
	if _real_mouse_recent():
		return
	_cursor_layer.call("push", _cursor_layer.call("synth_motion", pos))

func _push_motion_ctrl(pos: Vector2) -> void:
	if _cursor_layer == null:
		return
	# 批次 AA（W7-2）：同上（Ctrl 减选笔 motion 一并冻结）
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	# 批次 AC 4B（§4.6-8）：真实鼠标让位窗内不推合成 motion（同 _push_motion 口径；
	# 减选滑动的选中取消由 _on_right_slide 兜底直调保证，通道缺席不失效）
	if _real_mouse_recent():
		return
	var ev: InputEventMouseMotion = _cursor_layer.call("synth_motion", pos)
	ev.ctrl_pressed = true
	_cursor_layer.call("push", ev)

# ---------- 批次 AA（W7-3）：卡死看门狗 → 强制补发抬起 ----------

## 三条件判据（spec §10.6 风险 2 的第三条件为必要项）：
##   ① 引擎持 LEFT（台账：合成按下已推、抬起未推）
##   ② 物理左键未按（Input 单例）
##   ③ Router 侧无按压标志（_left_stroking / _right_stroking / 双侧 _menu_click_armed 全 false）
## ③ 缺失即合法手势按压（物理键本就未按、引擎由合成事件持 LEFT）——不加会误清长按。
func _stuck_three_conditions() -> bool:
	if not _synth_left_held:
		return false
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return false
	if _left_stroking or _right_stroking:
		return false
	if bool(_menu_click_armed.get("left", false)) or bool(_menu_click_armed.get("right", false)):
		return false
	return true

func _process(_delta: float) -> void:
	if not _stuck_three_conditions():
		_stuck_frames = 0
		return
	_stuck_frames += 1
	if _stuck_frames >= STUCK_WATCHDOG_FRAMES:   # N=30【暂定值·待用户复验】
		_stuck_frames = 0
		_force_gui_release()

## 强制补发抬起（清理引擎残留 LEFT 按压）。三步：**按下位补按下**（重置引擎 mouse_focus——
## 卡死态常伴随 focus 被真实按下/抬起周期挪走，release 只按 mouse_focus 路由、focus 丢失时
## 落空）→ **屏外 motion**（把 pressuring_inside 刷 false）→ **按下位抬起**（结束按住态，
## 因 pressuring_inside=false 不触发 pressed，防幽灵点击；探针 R5 实证该序列 button_up 正常
## 且 pressed 零误发）。台账先行清零（防 _push_btn 重入）；光标层缺席则只清台账。
func _force_gui_release() -> void:
	if not _synth_left_held:
		return
	var at: Vector2 = _synth_left_pos
	_synth_left_held = false
	_stuck_frames = 0
	if _cursor_layer == null:
		return
	_cursor_layer.call("push", _cursor_layer.call("synth_button", at, true, false))
	_cursor_layer.call("push", _cursor_layer.call("synth_motion", STUCK_CLEAR_MOTION_POS))
	_cursor_layer.call("push", _cursor_layer.call("synth_button", at, false, false))

# ---------- 退出倒数 → §6.3 分流 ----------

func _on_exit_confirmed() -> void:
	_map.set_exit_countdown(false)
	exit_confirmed.emit()
	var game: Node = get_node_or_null("/root/Game")
	if game == null:
		return
	# 覆盖层优先（§6.3）：商店/设置面板开 = 关闭回上级（等效点其关闭钮）
	if game.is_settings_open() or game.is_shop_open():
		game.close_overlay()
		# 修复A（2026-09-18 外部审计高危项）→ 批次 W（P1-1，拍板 1）语义升级：tracker 复位
		# 推广到**全部确认分支**（下方 MAIN_MENU/CATALOG/OPENING_MOVIE/TALK/LEVEL 各分支补
		# _tracker.reset()）——旧裁决「保持分支局部」（外部审计在案注释）被 W0 拍板 1 推翻：
		# 非覆盖层界面确认退出后 _done 残留使该界面内手势退出永久失灵（用户实测）。
		# 「接受确认挂起期间重复触发」语义=靠 TopStrip 单槽 confirm 顶替兜底（P2-7 补调旧
		# cancel 后不泄漏）。重入安全：本 handler 在 notify_flip 栈内同步执行，返回后
		# notify_flip 立即 return（tracker :48）；勿提升到本函数顶部全局加。
		_tracker.reset()
		return
	var sc: Node = game.get_current_scene()
	var st := int(game.current_state())
	# 批次 W（P1-1，拍板 1）：各确认分支转发后即复位 tracker——限定确认分支（不全局加，
	# 尊重旧注释对 reset_runtime 全局化的警示），该界面内退出倒数再次触发可达。
	var confirmed_branch := true
	if st == int(game.State.MAIN_MENU):
		if sc != null and sc.has_method("_on_quit"):
			sc.call("_on_quit")            # main_menu.gd:158 弹既有「退出《千年一榫》？」确认
	elif st == int(game.State.CATALOG):
		if sc != null and sc.has_method("_on_exit_pressed"):
			sc.call("_on_exit_pressed")    # catalog_scene.gd:458 catalog_return 来源路由
	elif st == int(game.State.OPENING_MOVIE):
		if sc != null and sc.has_method("_on_skip"):
			sc.call("_on_skip")            # opening_movie.gd:56 等效跳过按钮
	elif st == int(game.State.TALK):
		# 批次 Z Z3-6（spec §3-5，用户拍板）：TALK 态退出改**先弹 TopStrip 确认条**——
		# 误触发四指同翻（哪怕走完整个倒数）不再静默吞掉对话：旧码直调 _finish 整段跳过，
		# 用户会以为「对话只有两三句」。确认→_finish 跳过；取消→对话继续（Game.confirm
		# 缺省空回调零副作用）；确认条挂起期间状态迁移由 TopStrip 跨态收起按取消兜底
		# （批次 V 审查①P2-4 既有契约）。LEVEL 态直达主菜单既有语义零改动（用户拍板）；
		# tracker 复位随函数尾 confirmed_branch 统一执行（批次 W P1-1 契约保持，可再来一轮）。
		if sc != null and sc.has_method("_finish"):
			game.confirm(I18n.t(TALK_SKIP_TEXT), func() -> void:
				if is_instance_valid(sc) and sc.has_method("_finish"):
					sc.call("_finish"))
	elif st == int(game.State.LEVEL):
		# 批次 Y（Y-A3，spec §2-③拍板一）：关卡内倒数计 0 → **手势倒数专属退出入口**——
		# 直连回主菜单（存档+清理在 level_scene.gesture_exit_to_menu 收口），**不再走
		# _on_exit_pressed 二次确认**（两入口不共用方法：手动 TopBar 二次确认语义保持现状）。
		if sc != null and sc.has_method("gesture_exit_to_menu"):
			sc.call("gesture_exit_to_menu")   # level_scene 直连 Game.goto_state(MAIN_MENU)+flush_checkpoint()
	elif st == int(game.State.SETTLE):
		# 批次 Z（Z6-P2-7，spec §6）：结算态接通右下「退出」钮同链路——HUD 说明栏结算页常显
		# 「退出【双手】四指同翻」，旧码落 else 静默零反馈（只复位 tracker，玩家不知道翻了干嘛）。
		# _on_settle_exit_pressed 自带 _settled 守卫（与右下退出钮同一函数零新语义）；
		# tracker 复位随 confirmed_branch 尾统一执行（可再来一轮）。主路径结算=level 场景
		#（mark_settle_entered 不换场景）、边缘路径 goto_state(SETTLE) 亦载 level——两径同命中。
		if sc != null and sc.has_method("_on_settle_exit_pressed"):
			sc.call("_on_settle_exit_pressed")
	else:
		confirmed_branch = false           # BOOT：静默忽略（§14-12；SETTLE 已上移接链路）
		# 批次 Y（Y-A22，spec §2-㉒）：静默分支同样补 tracker reset——旧码仅 confirmed_branch
		# 分支复位，_done 残留使该界面内手势退出一次失灵（红测 test_w_gesture_state 段 C 扩
		# SETTLE/BOOT 第二轮断言）。
		_tracker.reset()
	if confirmed_branch:
		_tracker.reset()
