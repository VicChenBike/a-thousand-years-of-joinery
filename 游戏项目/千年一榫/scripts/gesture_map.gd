class_name GestureMap
extends RefCounted
## 批次 R：手势语义判定纯逻辑层（spec §4.1/§4.2/§5.3/§5.4/§13 注 B）。
## feed_frame() 逐帧喂入双手手 dict（spec §3.3 字段表），返回意图数组；无节点依赖、
## 可无头直测：所有时间由调用方注入（now: float 秒）。
## 判定权威=fingers 通道（§4.2「判定以 fingers 数组为准」+拇指不管口径）；gesture_id 不参与
## 运行时门控（防双轨判定漂移，仅控制台显示消费）——主会话裁决（计划审查 P1-5）：spec v1.3
## §3.5/§4.2 已按此口径回写，「拇指不管」类语义只有 finger 通道能表达，gesture_id 交叉校验
## 会在拇指边缘态漂移，故废弃 spec v1.2 前的「交叉校验」表述。
## 注：D 盘源 gesture_engine.py :190 实况 hand_rotation_x=roll（spec §3.3 表「z=roll」与源不符，
## 见实施计划「spec 疑义上报①」）——本类按源实况读 hand_rotation_x 为 roll。

const CONF_ENTER := 0.55          # 触发阈值（批次 Z Z5-1 用户拍板放宽 0.65→0.55——「动作更容易做出来」；
                                  # 误触由 CONFIRM_FRAMES=2 确认帧 + 冷却兜底；留痕：旧 0.65=批次V、更旧 0.60/0.55）
const CONF_EXIT := 0.45           # 回落阈值（Z5-1 校核：0.45 < CONF_ENTER 0.55 滞后带保持；旧 0.40 等价替换留痕）
const FOLD_EXIT_TH := 0.40        # 审查回修 P2-4：缩放态收掌迟滞阈值——任一四指<0.40 才收掌（spec §5.3），[0.40,0.55) 带内维持缩放
# 批次 AA（W2 审查 P3-1，随 W3 波清账）：旧 EXTEND_TH(0.55) 死常量已删除——全仓零引用
# （原注「亦为 FINGER_EXTEND_TH 缺省项」系误述：数组为字面量、无缺省回退）。0.55 进入阈
# 语义由 FINGER_EXTEND_TH 分指阈数组承担，滞回退出阈由 EXTEND_EXIT_TH 承担。
const EXTEND_EXIT_TH := 0.45      # 批次 AD §4.2 等价改写（0.40→0.45）：分指伸直滞回**退出**阈
                                  # ——[EXIT,ENTER) 带内保持上帧判定。上调理由：中指进入阈回到
                                  # 0.55 后，退出阈须同步抬升以保持 **0.10 滞后带**（0.45=0.55−0.10），
                                  # 且必须**严格低于无名指进入阈 0.48**（结构护栏见段 D9——否则无名指
                                  # 落在 [无名指阈, 中指退出阈) 时两指判定互相矛盾）；
                                  # 旧值留痕：0.40=批次 AA W2-5【暂定值·待用户复验】
const FINGER_EXTEND_TH := [0.55, 0.55, 0.55, 0.48, 0.55]  # 分指进入阈【批次 AD §4.2 等价改写】：
                                  # 拇指/食指/小指 0.55 不动；**中指 0.48→0.55（收回安全区间）**、
                                  # **无名指 0.48 不变**。收窄理由（用户实机反馈「瞄准时中指微伸被
                                  # 误判为双指」）：批次 AC 把中指降到 0.48 后，食指瞄准时中指因
                                  # 肌腱连带常落 0.48~0.54，越阈即被判 two → 误合成左键按下/进 ORBIT；
                                  # 现要求中指**明显竖起**（≥0.55）才算二指。
                                  # 带约束：EXTEND_EXIT_TH(0.45) < 无名指阈(0.48) < 中指阈(0.55)。
                                  # 旧值留痕：AC §4.5-1 时 [0.55,0.55,0.48,0.48,0.55]、W2-6 时
                                  # [0.55,0.55,0.55,0.45,0.55]。与 python
                                  # gesture_engine.FINGER_EXTEND_TH 同源同值（跨语言切点护栏
                                  # selftest_aa_finger_thresholds 已同步等价改写）。
const TWO_RING_COUPLE_MAX := 0.65  # 【批次 AC §4.5-1 新增】二指态无名指**生理连带**抬升容忍上限
                                  #（手背伸肌腱连带：竖中指时无名指常被带起 0.45~0.62 →
                                  # 旧判 three 打断确认/误发删除）
const TWO_MIDDLE_RING_GAP := 0.12  # 【批次 AC §4.5-1 新增】中指领先无名指伸直度最小差值
                                  #（fraw[2]−fraw[3] ≥ 0.12 → 判「中指主动、无名指被动跟随」）
const CURSOR_ARM_WINDOW_SEC := 0.25  # 【批次 AC §4.5-2 新增】瞄准预备窗（秒）——cursor 态每帧刷新
                                  # `cursor_armed_until`；窗内 cursor→two 过渡单帧 rest 容忍不清确认计数
                                  # （食指瞄准后竖中指单击灵敏、干脆、不丢击）
const PALM_PINKY_TH := 0.70       # 批次 AA（W2-6，spec §5.4-7）：小指泄漏守卫——四指全伸时小指
                                  # >0.70 才判 palm；(0.55,0.70] 视为三指形泄漏 → three（防右手
                                  # palm→clear 破坏性误触、左手 palm_begin 顶掉 delete；真四指
                                  # 小指 extend≈1.0 不受影响）
const FLIP_WINDOW_SEC := 1.0      # 翻转触发窗（§4.1 注 A）
# 批次 Y（Y-A8，spec §2-⑧拍板）：翻转成功冷却 1.0→0.35s（可调带 0.3~0.4 取中，常量集中真手复验一次调参）
# ——「翻 4 次才弹一次」主因之一（1.0s 冷却吞连翻）根除。
const FLIP_COOLDOWN_SEC := 0.35   # 翻转冷却（触发后 0.35s，冷却期不进新前置态）
# 批次 Y（Y-A8）：clear 提交独立翻转冷却——与翻转成功冷却**解耦**（独立常量独立计时）。
# 旧码（批次X收口 P2-1）clear 复用 FLIP_COOLDOWN_SEC(1.0) 致 clear 后真翻转被吞；现语义=
# clear 只防「清空姿态同构误翻转」（防误窗收窄至 0.35s），0.5s 后真翻转照常接受（红测锁定）。
const CLEAR_FLIP_GUARD_SEC := 0.35
# 批次 Z（Z5-1/Z5-5，spec §5-1/§5-5 用户拍板）：SAME_WINDOW_SEC 0.8→1.2s。
# **双手配对窗与单翻解算窗共用评估（本批处置=不拆分）**：①双手配对窗（双翻→exit_flip）与
# ②单翻 undo/redo 解算窗在 _pending_flip 上是**同一只表**——配对窗要放宽到 1.2s，解算必须
# ≥ 配对窗，二者结构耦合不可拆（拆开会使「1.3s 后到的对侧翻」永不可配对）。故单常量统一 1.2s，
# 接口注释与受影响测试（gesture_map/y_flip_decoder/x_semantic_replay/w_gesture_state）已同步
# 等价平移；CONFIRM_FRAMES=2 与 FLIP_COOLDOWN_SEC=0.35 不变。
# 批次 AA（W3-4，spec §6.3 W3-4）：join 判据由「双侧 cursor 边沿 ±SAME_WINDOW_SEC」改为
# **双手同帧 two（均经确认帧）**，本常量不再参与对接判定（对接防抖由 JOIN_COOLDOWN_SEC 承担）。
const SAME_WINDOW_SEC := 1.2      # 双手同翻配对窗 / 单翻解算窗（§4.2）
# 批次 X（P6，spec §7-1 回放实证）：FLIP_ROLL_LOCK_DEG=30.0 常量退役——旧前置 roll<30° 绝对
# 方向门要求掌向量沿画面 +x（横掌指尖朝右），真手竖掌（指尖朝上）roll≈270°
# （hand_rotation_x=atan2 掌向量 0~360 口径）下永不满足 → 翻转前置锁不上=撤销/重做真手
# 100% 失效（探针 C/C2：竖掌左右翻 cz 过零变号可达、roll 全程 271° 不变）。
const FLIP_ANGLE_DEG := 75.0      # roll 相对锁定基准变化 >75°（批次 Z Z5-1 拍板 90→75——翻转更容易做出来；
                                  # 留痕：旧 90.0；误触由 2 帧确认 + 0.35s 冷却兜底）
const PALM_OBSERVE_SEC := 0.5     # 静止基准跟随等待窗（批次 X P6 语义重构：旧「入掌 0.5s 内判推拉」观察窗——EMA 滞后+双帧确认使快推 streak 达成即超窗、停后慢推永不触发，缩放真手失效根因；现常量语义=入掌超此时长且无推拉活动时基准慢速跟随 EMA）
const PALM_FOLLOW_ALPHA := 0.10   # 批次 X（P6）：静止基准跟随速率（/帧）——推拉中途位移速率远大于跟随速率零干扰，MediaPipe 静态抖动（±2% « 15% 阈）被跟随吸收
const PALM_PUSH_RATIO := 0.12     # 推拉进入阈值 12%（相对入态基准；批次 Z Z5-1 拍板 15%→12%；
                                  # 留痕：旧 0.15；误触由 3 帧持续 + 静止基准跟随兜底）
const PALM_PUSH_FRAMES := 3       # 推拉持续 ≥3 帧
# 批次 AA（W3-2，spec §6.3 W3-2 + §22 裁决 2，2026-09-25 主会话拍板）**旧口径留痕**：清空选择
# 曾重分配为【右】手掌静止连续保持 PALM_DWELL_SEC → 恰一次 clear（旧「右手 palm 双帧即 clear」退役）。
# 判定优先级（旧硬口径）：①掌态期间出现任意位移 → 立即取消 dwell 计时并优先走缩放，
# 该次掌态零 clear；②静止连续满 PALM_DWELL_SEC → 恰一次 clear；③dwell 计时器与 zoom_begin
# 状态机互斥单一真值（同一次掌态只可能落其一）。
# 批次 AD（§4.3.4，2026-09-28 审查回修）**现口径**：右掌 dwell 清空**彻底废除**（_feed_palm_dwell
# 退役为 no-op 桩），清空=**双手握拳**（_feed_dual_fist_clear：食+中+无名 ≤FIST_FINGER_TH(0.35)、
# 连续 FIST_CONFIRM_FRAMES(2) 帧、Latch；派发 {"type": "clear", "side": "both"}；HUD 行
# 「7 清空选择【双手】握拳」同源）。下方 PALM_DWELL_* 常量组与 dwell_* 状态位仅存旧口径留痕。
# ——批次 AD §4.3.4 退役留痕（2026-09-28 审查回修 P2-9）：以下 PALM_DWELL_* 四常量为
#   **零消费死位**（唯一读取方 _feed_palm_dwell 已退役为 no-op 桩，全工程无其它引用），
#   成组保留旧值与判据注释供考古/回归对照，勿再接新通路；删除随下次 dwell 遗留清理波统一做。
const PALM_DWELL_SEC := 1.0         # 静止连续保持时长（秒）【暂定值·待用户复验】
const PALM_DWELL_STATIC_TH := 0.05  # 静止判据（推拉分量）：掌态期间 palm_ema 相对入态锚的相对
                                    # 位移阈（5%）【暂定值·待用户复验】——越阈即判「有位移」取消
                                    # dwell（0.02 归一/s 极慢位移在 1.0s 内累计 ≈10% 必越阈，
                                    # R3-b 极慢位移边界用例）
const PALM_DWELL_ROLL_TH := 30.0    # 静止判据（取向分量）：掌面 roll 相对入态锚变化 >30° 视为
                                    # 「摆掌/翻转」→ 取消 dwell【暂定值·待用户复验】（防清空打断
                                    # 撤销/重做/退出倒数的翻转序列；静止掌 roll 不变零干扰）
const PALM_DWELL_TIP_TH := 0.05     # 批次 AA（W3 独立审查回修 P2-2，规格 §6.3 W3-2 裁决 2 ①字面
                                    # 「出现**任意**位移」）：静止判据（**位置分量**）——dwell 期间
                                    # 逐帧归一指尖位（增益后坐标）与入态锚的直线距离 >0.05
                                    # （≈57.6px content）→ 取消 dwell【暂定值·待用户复验】。
                                    # 旧判据只算 palm_size 分量 + roll 分量，**漏指尖/掌心位置分量**：
                                    # 右掌在图像面内横向平移（不推拉、不翻腕）→ palm_size 与 roll 均
                                    # 不变 → dwell 照常计时到点发 clear（红测 2f 实证）。同量级取
                                    # PALM_DWELL_STATIC_TH(0.05)；增益前噪声已由 CURSOR_DEADZONE 拦截，
                                    # 阈值只对「1s 窗内真实位移」敏感（调参时与 deadzone 一并看）。
const ZOOM_STEP_LN := 0.0953102   # log(1.10)（§5.3 缩放台阶）
# ===== 批次 AC 4A（spec §4.6-3，2026-09-27 用户实机反馈）=====
# **双手协同推拉/间距缩放**：旧「任一只手单独掌推拉=缩放」被实机证伪——单手翻掌/横向移动
# 极易被误判为推拉（用户反馈「单手误触发缩放」）。现生产语义=**双手同时处于掌形张开态**
#（palm 或 three，即至少食+中+无名三指伸直）且双掌均朝向摄像头时，按「双掌中心间距相对变化」
# 与「双掌平均 palm_size 相对变化」取变化幅度较大者作为有效缩放比 r_eff，交由本文档
# `_feed_dual_palm_zoom` 统一接管；**单手不再触发缩放动作**（zoom_in/zoom_out）。
# 旧单手掌推拉通道以 `set_single_hand_zoom_enabled(true)` 专门接口兼容保留（默认关，仅存量
# 回归夹具按需开启；生产路径不启用）——见方法区注释。
const DUAL_ZOOM_DIST_RATIO := 0.10  # 双手协同缩放进入阈值（|r_eff−1| 相对变化 10%）
const DUAL_ZOOM_FRAMES := 2         # 双手协同缩放确认帧数（连续 2 帧越阈才进入）
const DUAL_ZOOM_EMA := 0.45         # 双掌间距/双掌面积逐帧 EMA 系数（spec §4.6-3 定值）
const DUAL_ZOOM_FOLD_EXIT_TH := 0.40  # 已进入双缩放态后的收掌迟滞阈（任一四指 <0.40 才收掌）
# 至少三指（食+中+无名）伸直判据阈（双掌协同缩放「手掌张开态」专用；**与本批
# FINGER_EXTEND_TH 分指档解耦**——AD §4.2 中指阈收回 0.55 只针对「二指/光标」分流，
# 双掌缩放是双手对称的显式张开姿态，阈值本批不动以保行为零变化。旧注「与
# FINGER_EXTEND_TH 同源：食 0.55 / 中 0.48 / 无名 0.48」已随中指档分叉而失效）。
const DUAL_POSE_TH := [0.55, 0.48, 0.48]
# 左三指批量删除后该侧翻转检测冷却（spec §4.6-4）：三指删除=食+中+无名，与「至少三指翻转」
# 姿态同构——玩家收手瞬间手腕自然偏转极易被立即误判为翻转 undo（把刚删的木块恢复回来）。
# 删除实际发生（removed > 0）时由 Router 调用 `suppress_flip_after_delete("left", now)` 施加
# 本冷却；选区为空（removed == 0）时不施加，玩家伸左三指翻转即可顺畅撤销。
const DELETE_FLIP_GUARD_SEC := 0.6
const CONFIRM_FRAMES := 2         # 二指/三指/四指/掌态确认帧数（光标 0 帧）
# ===== 批次 AD 4.3（spec §4.3.2/§4.3.4）新增常量 =====
const FIST_FINGER_TH := 0.35      # 握拳判定阈值（食、中、无名 <= 0.35）
const FIST_CONFIRM_FRAMES := 2    # 双手握拳确认帧数
const THREE_PINKY_FOLD_MAX := 0.35 # 三指删除小指收拢上限（§4.3.2）
const CURSOR_GAIN := 2.5          # 批次 AA（W2-2，spec §5.3/§15#3）：3.5→2.5 降增益【暂定值·待用户复验】
                                  #（用户「位移小一点」；旧值留痕：3.5=批次V §5.1、2.5=批次T、2.0=批次S；
                                  # 调优带 2.0~3.5，与 CURSOR_DEADZONE/CURSOR_EMA_ALPHA 三者联动调参）
const CURSOR_OVERSHOOT := 0.15    # 批次 X P2（spec §3）：光标四角余量——钳制域扩为 [-m,1+m]，屏幕 0/1 缘内侧
                                  # 归一 0.357/0.643 即达（旧硬钳 [0,1] 要求 tip 覆盖摄像头画面全域四角，
                                  # MediaPipe 边缘检测退化=实机「到不了四角」根因；调优带 0.10~0.25，仅常量可调）
const CURSOR_DEADZONE := 0.0003   # 批次 AD §4.1.2（0.0015→0.0003）：仅滤传感器硬件微噪——
                                  # 1152 视口折约 0.35px，移动初始阶段不再有「锁上帧」顿挫感；
                                  # 旧值留痕：0.0015=批次 AA W2-3（0.0035=批次 T §4-7）【暂定值·待用户复验】
const CURSOR_EMA_ALPHA := 1.0     # tip 二级 EMA 系数【批次 AD §4.1.2：0.60→1.0=**直通**】——
                                  # Python 端已完成 One Euro（min_cutoff 1.8/beta 3.0）+ 动态 α
                                  # LandmarkSmoother 两级自适应滤波，GDScript 侧再套一层低通属
                                  # **级联双低通**，是用户「快速移动仍迟滞/粘手」的剩余瓶颈。
                                  # 1.0 → `lerp(prev, tip, 1.0)` 恒等直通（死区击穿最小跳
                                  # =0.0003×2.5×1152≈0.86px，远小于旧 4.32px）。保留 lerp 调用点
                                  # 与常量本身（filtered/landmark 两源仍走同一路径→R2-i 护栏断言
                                  # 的「两路径均非死代码」语义保持；仅系数取直通值），
                                  # 未来若需在 GDScript 侧再降噪只调本常量、不返工结构。
                                  # 旧值留痕：0.60=批次 AC §4.3-2（0.35=批次 AA W2-1）
# 批次 Y（Y-A8 解耦留痕）：对接边沿冷却——旧码复用 FLIP_COOLDOWN_SEC（随 Y-A8 收敛至 0.35 会连带
# 缩短对接防抖）；解耦为独立常量维持 1.0s 既有对接手感（翻转冷却调参不再牵连 join）。
const JOIN_COOLDOWN_SEC := 1.0
# 批次 AA（W1-11 回修 P2-2①，spec §4.3 W1-11 增补；审查结论 ACCEPT-WITH-FIXES P2-2）：
# **连续 stale 时长上限**。旧码（W1-11 初版）stale 短路期间 semantic / flip_locked /
# flip_streak / hand_id / zooming / join 边沿**无上界**保留——捂镜或无帧数分钟后恢复时，
# 残留的 pending 翻转配对可能被新姿态误完成（审查 P2-2 (a)(c)）。超限即强制双侧
# `_teardown_side`（含兜底 two_up / zoom_end，防虚拟键卡死）；超限前的正常 stale 短路
# 行为**零变化**。计时器在任何「非 stale 供帧」或侧 teardown 时复位（分段 stale 不累计）。
const STALE_MAX_SEC := 5.0       # 连续 stale 上限（秒）【暂定值·待用户复验】
# 批次 AA（W2-1）：EMA_FALLBACK_BASE(0.35)/EMA_FALLBACK_FAST(0.70)/EMA_SPEED_TH(0.8) 三常量
# 随 :250-254 死代码分支（src=="landmark" 速度自适应 EMA，生产永不可达）一并退役——
# 统一为 CURSOR_EMA_ALPHA 单系数双源同路径（R2-i 护栏断言锁定两路径均非死代码）。
const DEBUG_LOG_PATH := "user://gesture_debug.log"   # 批次 X（P6，spec §7-3）：识别态诊断日志（文件名含 gesture_debug；默认关零写文件）
const DEBUG_ENV_VAR := "GAME_GESTURE_DEBUG"          # 批次 X（P6）：诊断开关环境变量（="1" 开启；Router _setup 接线，波内定档——零存档 schema 变更、真手复验一行命令可控）

var _side := {}                   # "left"/"right" → 状态字典（_new_side）
var _pending_flip := {}           # {"side":String,"at":float} 单翻等待同窗配对
var _join_edges := {}             # side → 最近进入光标态时刻（光标态边沿记账；批次 AA W3-4 起
                                  # **不再参与 join 触发**（判据改双手同帧 two），保留为诊断与
                                  # W1 手性测试（test_aa_handedness）的光标态在位记账锚）
var _join_cooldown_until := -1.0  # 对接冷却（1s）
var _join_latched := false        # 批次 AA（W3-4）：本次「双手 two 配对」已消费标记——双手二指
                                  # 持续期间至多触发一次 join（退出 two 才复位，防冷却后持续态重复触发）
var _stroke_owner := ""           # 单笔互斥（§13 注 B）：""/"left"/"right"
var _exit_countdown := false      # 倒数进行中（Router 注入）：单翻抑制、同翻进倒数
# 批次 W（P3-2d）：各手最近在场时刻（秒）——单翻落空判据「另一手刚离场」的记忆源
var _last_present_at := {"left": -1.0, "right": -1.0}
# 批次 X（P6，spec §7-3）：识别态诊断日志句柄（null=关，零写文件；开启=WRITE 覆盖+逐帧 append+flush）
var _debug_file: FileAccess = null
# 批次 Y（Y-A10）：丢手/恢复边沿检测记忆（side→bool 上帧在场态；仅 dump 用）
var _dbg_prev_present := {}
# 批次 AA（W1-11 回修 P2-2①）：连续 stale 起算时刻（秒；-1=未在 stale）——STALE_MAX_SEC 上限判据
var _stale_since := -1.0
# 批次 AC 4A（spec §4.6-3）：双手协同缩放状态（false=本帧未进入；进入后逐帧复判直至收掌）
var _dual_zooming := false
var _dual_dist_base := 0.0      # 双掌中心间距入态基准（首进入帧）
var _dual_palm_base := 0.0      # 双掌平均 palm_size 入态基准
var _dual_dist_ema := -1.0      # 双掌间距 EMA（-1=未初始化，首帧直通）
var _dual_palm_ema := -1.0      # 双掌平均 palm_size EMA（同上）
var _dual_streak := 0           # 越阈确认帧计数（DUAL_ZOOM_FRAMES 门）
var _dual_cum_log := 0.0        # 双手缩放累计 log(r_eff)（跨 ZOOM_STEP_LN 台阶发 zoom_step）
# 批次 AC 4A：单手推拉缩放兼容开关（默认 false=单手零缩放，见常量区与 set_single_hand_zoom_enabled）
var _single_hand_zoom := false
# 批次 AD §4.3.4：双手握拳清空全选状态
var _fist_streak: int = 0
var _fist_latched: bool = false

## 诊断日志开关（默认关）。开启时覆盖写 user://gesture_debug.log 并逐帧 dump；
## 关闭时 flush+close 释放句柄。真手复验定位用（Router 经环境变量接线，亦可测试直调）。
func set_debug_enabled(enabled: bool) -> void:
	if enabled:
		if _debug_file == null:
			_debug_file = FileAccess.open(DEBUG_LOG_PATH, FileAccess.WRITE)
			if _debug_file != null:
				_debug_file.store_line("# gesture semantic debug | %s | env=%s" %
					[Time.get_datetime_string_from_system(), DEBUG_ENV_VAR])
				_debug_file.flush()
	else:
		if _debug_file != null:
			_debug_file.flush()
			_debug_file.close()
			_debug_file = null

func is_debug_enabled() -> bool:
	return _debug_file != null

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _debug_file != null:
		_debug_file.close()
		_debug_file = null

## 逐帧识别态 dump（_debug_file==null 时零开销直返）。semantic=处理后终态、fingers/confidence=
## 该手输入量、intents=本帧意图 type 集。行格式：
## t=… pending=[…] L[semantic=… conf=… fingers=… roll=… facing=… locked=… streak=… cd=… id=… held=… ev=…] R[…] intents=[…]
## 批次 Y（Y-A10，spec §2-⑩）：在既有 semantic/conf/fingers/intents 结构（向后兼容）上增记
## roll（左右）/facing/flip_locked/flip_streak/冷却剩余/pending_flip/手 id/held/丢手与恢复事件
## （ev=lost/back 边沿标记，紧凑单行）——真手复验定位「翻 4 次才弹一次」类问题。
## 批次 AA（W1-8，spec §4.3）：再增记 **label_mp / mp_score / label_geo** 三个 python 侧
## 手性原始诊断字段（协议只增、老包缺键按 "-" 兜底）——真手复验手性映射方向用。
func _debug_dump(left_v: Variant, right_v: Variant, now: float, out: Array) -> void:
	if _debug_file == null:
		return
	var types: Array = []
	for it: Variant in out:
		if typeof(it) == TYPE_DICTIONARY:
			types.append(String((it as Dictionary).get("type", "")))
	var l_part := _debug_side_part("left", left_v, now)
	var r_part := _debug_side_part("right", right_v, now)
	var pend := "-"
	if not _pending_flip.is_empty():
		pend = "%s@%.2f" % [String(_pending_flip.get("side", "?")), float(_pending_flip.get("at", -1.0))]
	_debug_file.store_line("t=%.3f pending=[%s] %s %s intents=[%s]" % [now, pend, l_part, r_part, ",".join(types)])
	_debug_file.flush()

func _debug_side_part(side: String, h: Variant, now: float) -> String:
	var st: Dictionary = _side.get(side, {})
	var sem := String(st.get("semantic", ""))
	var cd_rem: float = maxf(float(st.get("flip_cooldown_until", -1.0)) - now, 0.0)
	var ev := ""
	var present := typeof(h) == TYPE_DICTIONARY and not (h as Dictionary).is_empty()
	var prev: Variant = _dbg_prev_present.get(side, null)
	if prev != null:
		if bool(prev) and not present:
			ev = " ev=lost"
		elif not bool(prev) and present:
			ev = " ev=back"
	_dbg_prev_present[side] = present
	if not present:
		return "%s[semantic=%s conf=n/a fingers=n/a roll=n/a facing=n/a locked=%s streak=%s cd=%.2f id=%s held=0 label_mp=- mp_score=- label_geo=- %s]" % [
			side.capitalize(), sem, str(st.get("flip_locked", false)), str(st.get("flip_streak", 0)),
			cd_rem, String(st.get("hand_id", "")), ev]
	var hd: Dictionary = h
	# W1-8：mp_score 判类型再 float（4.7 实证规律⑦：float(null) 强转中止脚本）
	var mps_v: Variant = hd.get("mp_score", 0.0)
	var mps: float = float(mps_v) if (typeof(mps_v) == TYPE_FLOAT or typeof(mps_v) == TYPE_INT) else 0.0
	return "%s[semantic=%s conf=%.2f fingers=%s roll=%.1f facing=%s locked=%s streak=%s cd=%.2f id=%s held=%d label_mp=%s mp_score=%.2f label_geo=%s%s]" % [
		side.capitalize(), sem, float(hd.get("confidence", 0.0)), str(hd.get("fingers", [])),
		float(hd.get("hand_rotation_x", 0.0)), str(_palm_facing(hd)),
		str(st.get("flip_locked", false)), str(st.get("flip_streak", 0)), cd_rem,
		String(hd.get("id", String(st.get("hand_id", "")))), (1 if bool(hd.get("held", false)) else 0),
		_dbg_field(hd.get("label_mp", null)), mps,
		_dbg_field(hd.get("label_geo", null)), ev]

## 批次 AA（W1-8）：诊断字段安全串化——null/缺键一律 "-"（4.7 实证规律⑩：String(null)
## 强转会中止脚本，故不用 String() 构造；str() 对 null 返回 "<null>" 亦不理想，故先判空）。
static func _dbg_field(v: Variant) -> String:
	return "-" if v == null else str(v)

func _init() -> void:
	reset()

## 全复位（Router 在场景切换/桥非 READY 时调用）
func reset() -> void:
	_side = {"left": _new_side(), "right": _new_side()}
	_pending_flip = {}
	_join_edges = {}
	_join_cooldown_until = -1.0
	_join_latched = false   # 批次 AA（W3-4）：双手 two 配对消费标记随全复位清零
	_stroke_owner = ""
	_exit_countdown = false
	_last_present_at = {"left": -1.0, "right": -1.0}
	_stale_since = -1.0   # 批次 AA（P2-2①）：stale 计时器随全复位清零
	_reset_dual_zoom()    # 批次 AC 4A（spec §4.6-3）：双手协同缩放累计态随全复位清零
	_fist_streak = 0      # 批次 AD §4.3.4：双手握拳计数复位
	_fist_latched = false # 批次 AD §4.3.4：双手握拳锁存复位

## 批次 AC 4A（spec §4.6-3）：双手协同缩放累计态复位（全复位 / 任一侧收掌 / 退出双缩放态时调用）。
## `_single_hand_zoom` 兼容开关**不在本方法内**（它属会话配置而非逐帧累计态）。
func _reset_dual_zoom() -> void:
	_dual_zooming = false
	_dual_dist_base = 0.0
	_dual_palm_base = 0.0
	_dual_dist_ema = -1.0
	_dual_palm_ema = -1.0
	_dual_streak = 0
	_dual_cum_log = 0.0

## 批次 AC 4A（spec §4.6-3）：**单手推拉缩放兼容开关**（默认关）。
## 生产语义（默认 false）=只有双手协同推拉/间距缩放能产生缩放动作，单手一律零缩放——
## 根治用户实机反馈的「单手翻掌/横向移动误触发缩放」。置 true 恢复批次 AA 的单手掌
## `palm_size` 推拉通道（历史行为），仅供存量回归夹具/对照复验按需开启，生产路径不启用。
func set_single_hand_zoom_enabled(enabled: bool) -> void:
	_single_hand_zoom = enabled

func is_single_hand_zoom_enabled() -> bool:
	return _single_hand_zoom

## 批次 AC 4A（spec §4.6-4）：左手三指批量删除后的翻转防误触冷却。
## 左三指删除（食+中+无名）与「至少三指翻转」姿态同构——删除实际发生后调用本方法，将该侧
## `flip_locked`/`flip_streak` 清零并把 `flip_cooldown_until` 推至 `now + DELETE_FLIP_GUARD_SEC`，
## 收手瞬间的手腕偏转不再被立即误判为翻转 undo（把刚删的木块恢复回来）。选区为空
## （removed == 0）时不调用 → 玩家伸左三指翻转即可顺畅撤销。
## `now < 0`（缺省 -1.0）= 调用方无时钟注入，按「不清剩余冷却、仅清零前置态」保守处置。
func suppress_flip_after_delete(side: String, now: float = -1.0) -> void:
	if not _side.has(side):
		return
	var st: Dictionary = _side[side]
	st["flip_locked"] = false
	st["flip_streak"] = 0
	if now >= 0.0:
		st["flip_cooldown_until"] = now + DELETE_FLIP_GUARD_SEC
	# 同侧在途单翻配对一并作废（删除意图下翻转解算无效；防收手帧误判成 undo）
	if not _pending_flip.is_empty() and String(_pending_flip.get("side", "")) == side:
		_pending_flip = {}

## 倒数进行中标志（ExitGestureTracker 触发/取消时由 Router 注入）
func set_exit_countdown(active: bool) -> void:
	_exit_countdown = active
	if active:
		_pending_flip = {}

## 批次 AA（W2-10，spec §5.3）：该侧当前语义（状态条显示名消费）——与 _classify 判定
## **同源**（不经 python gesture_id 的 0.6/0.7 严阈双轨口径）；"" = 待命/未进语义态。
func get_side_semantic(side: String) -> String:
	if not _side.has(side):
		return ""
	return String(_side[side].get("semantic", ""))

func _new_side() -> Dictionary:
	return {
		"semantic": "",        # ""/"cursor"/"two"/"three"/"palm"
		                       # 批次 AA（W3-1）：旧 four（右手四指=清空）语义退役——右掌与左掌
		                       # 同走 "palm" 链（W3-2 曾改由右掌静止 dwell 承担；批次 AD §4.3.4
		                       # 起 dwell 通路彻底废除，现清空=双手握拳 _feed_dual_fist_clear）
		"pend_cls": "", "pend_count": 0,   # 2 帧确认暂存
		"two_pos": Vector2.ZERO,  # 二指按下位（teardown 兜底抬起位；计划 v1.1 遗留注意：兜底抬起位与按下位一致）
		"two_click_pending": false,  # 批次 AA（W3-4）：two_down 被对接抑制的挂起标记（对侧 two 态
		                             # 或确认中；join 承接则作废，对侧退出 two 则补发）
		"two_move_pending": false,   # 批次 AA（W3-4）：确认帧 cursor_move 待仲裁帧补出（保序）
		"two_first_jitter": false,   # 批次 AA（W3-4）：确认帧 cursor_move 的死区标记（补出时回填）
		"palm_at": -1.0, "zooming": false,
		# 批次 AD §4.3.4 退役留痕（审查回修 P2-9）：以下 dwell_* 五键属右掌 dwell 清空通路——
		# 通路废除后全部零消费（dwell_at/anchor/roll0/tip0 只写不读；dwell_fired 恒 false 使
		# 推拉段互斥项恒真；dwell_cancelled 只写不读）。成组保留键名与初始化值以维持 side 字典
		# 形状稳定（_debug_dump/状态查询键集不断裂），勿再接新通路。
		"dwell_at": -1.0, "dwell_anchor": 0.0,   # 批次 AA（W3-2）：右掌静止 dwell 起算时刻与推拉锚
		"dwell_roll0": 0.0,                   # 批次 AA（W3-2）：dwell 取向锚（入态 roll）
		"dwell_tip0": Vector2.ZERO,           # 批次 AA（W3 回修 P2-2）：dwell 位置锚（入态 tip，
		                                     # 增益后归一位坐标——横向平移取消判据的比较基准）
		"dwell_fired": false, "dwell_cancelled": false,   # 单真值：已清空 / 已被位移取消
		"palm_baseline": 0.0, "palm_ema": 0.0,
		"push_streak": 0, "zoom_cum_log": 0.0,
		"flip_locked": false, "flip_roll0": 0.0, "flip_at": -1.0, "flip_streak": 0,
		"flip_cooldown_until": -1.0,
		"last_tip": Vector2.ZERO,   # T6：上帧 tip（归一增益前；landmarks 缺失时保持上帧永不跳掌心）
		"last_tip_at": -1.0,        # T7：上帧时刻（EMA dt）
		"tip_seen": false,          # T6：该手是否出现过有效 tip
		"ema_tip": Vector2.ZERO,    # 批次 AA（W2-1）：tip 二级 EMA 状态（首帧=测量值直通）
		"cursor_armed_until": -1.0,  # 批次 AC（§4.5-2）：瞄准预备窗截止时刻（cursor 态每帧刷新
		                             # now+CURSOR_ARM_WINDOW_SEC；窗内 cursor→two 过渡单帧容差）
		"ext_hyst": [false, false, false, false, false],  # 批次 AA（W2-5）：分指伸直滞回状态
		"conf_hist": [],            # 批次 AA（W2-7）：确认置信度滑窗（CONFIRM_FRAMES+1 帧多数表决）
		"hand_id": "",              # 批次 Y（Y-A5）：Y1 per-hand 稳定 id（"L0"/"R0"）；id 变化=新手→该侧累计态全清
		"last_p": {},               # 批次 AC 4A（§4.6-3）：本侧最近一帧特征 profile（供双手协同缩放
		                            # 通道读取五要素；teardown 整字典重置时自动清空=该侧退出双缩放判据）
	}

## 逐帧入口：left/right 为 spec §3.3 手 dict（可为 {} 或 null=无手）；now 注入秒。
## 返回意图数组（批次 X P5 终态词汇：cursor_move/two_down/two_move/two_up/delete/clear/
## palm_begin/zoom_begin/zoom_factor/zoom_step/zoom_end/undo/redo/join/exit_flip；
## 旧右笔三态时序词汇（挖除/取消臂）与左手聚焦词汇随 P5-a 重映射退役——二指态仅剩
## down/move/up 即时事件对，无计时分支）。
## 批次 AC 4A（spec §4.6-3，2026-09-27）：新增显式缩放**动作事件** `zoom_in` / `zoom_out`
## （type/side/dir/pos 四键；dir=+1 放大 / −1 缩小，side="both" 表双手协同通道、"left"/"right"
## 表单手兼容通道）——供语义层/诊断按动作名消费；既有 zoom_begin/zoom_factor/zoom_step/zoom_end
## 生命周期词汇**逐字保持**（消费侧零改动）。生产语义下缩放仅由双手协同通道产生，
## 单品手推拉不再发任何缩放意图（`set_single_hand_zoom_enabled` 兼容开关另计）。
## 批次 AA（W1-11，spec §4.3）：新增 `stale` 可选参（**协议只增不改**，缺省 false=老包
## 行为零变化）——无帧期心跳空包带 stale:true 时按 held 语义短路（见 _feed_side）。
func feed_frame(left_v: Variant, right_v: Variant, now: float, stale: bool = false) -> Array:
	var forced: Array = []   # 批次 AA（P2-2①）：超 stale 上限的强制清态意图（置于本帧意图之前）
	# 批次 AA（W1-11 回修 P2-2①）：连续 stale 时长上限——超 STALE_MAX_SEC 强制双侧清态
	# （残留态上界；含兜底 two_up/zoom_end）。计时器复位点：①任何非 stale 供帧（下方 else）
	# ②侧 teardown（_teardown_side 内，含本次强制清态自身 → 下一次 stale 重新起算）。
	# 超限前的 stale 短路（_feed_side 内）与老包（stale=false）行为**零变化**。
	if stale:
		if _stale_since < 0.0:
			_stale_since = now
		if now - _stale_since > STALE_MAX_SEC:
			forced.append_array(_teardown_side("left", _side["left"], now))
			forced.append_array(_teardown_side("right", _side["right"], now))
	else:
		_stale_since = -1.0
	var raw: Array = []
	raw.append_array(_feed_side("left", _valid(left_v), now, stale))
	raw.append_array(_feed_side("right", _valid(right_v), now, stale))
	var out: Array = []
	out.append_array(forced)
	for it_v: Variant in raw:
		var it: Dictionary = it_v
		if String(it.get("type", "")) == "flip":
			out.append_array(_on_flip_raw(String(it["side"]), now))
		else:
			out.append(it)
	# 批次 AC 4A（spec §4.6-3）：双手协同推拉/间距缩放在两侧单帧语义产出**之后**统一裁决
	# （两侧同帧喂完才有双掌判据；单手通道已在 _feed_side 内按开关门控）。
	# stale 心跳空包不参与双缩放裁决（无新帧=无新双掌判据；存量 `last_p` 陈旧数据不续跑）。
	if not stale:
		_feed_dual_palm_zoom(now, out)
		_feed_dual_fist_clear(now, out)
	out.append_array(_resolve_pending_flip(now))
	out.append_array(_resolve_two_arbitration(now))   # 批次 AA（W3-4）：双手二指对接仲裁 + 抑制态单击补发
	_debug_dump(left_v, right_v, now, out)   # 批次 X（P6）：识别态逐帧 dump（默认关零开销）
	return out

func _valid(h: Variant) -> Dictionary:
	if typeof(h) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = h
	if d.is_empty():
		return {}
	# 批次 Y（Y-A5，spec §3.1 契约）：held 帧（丢帧容忍窗内陈旧数据）计为在场——is_detected
	# 缺失/false 的 held 帧不再判无效（Y1 侧 held 帧保留上一帧完整数据含 is_detected，本门为
	# 双向兼容兜底）；held 缺省按 false（老包零变化）。
	if not bool(d.get("is_detected", false)) and not bool(d.get("held", false)):
		return {}
	return d

## 逐帧特征提取（fingers 通道权威；roll 取 hand_rotation_x=源实况，见文件头注）。
## 批次 T tip 消费链（spec §4-6/§4-7）：tip_x/tip_y（One Euro 协议字段）> lm[8] > 保持上帧
## （永不跳掌心；首帧无缓存回落 (0.5,0.5)）；EMA 兜底仅 raw landmark 路径（字段在不再二次滤波）；
## 死区在增益前归一坐标上判定（位移 <0.0035 → jitter=true 且锁上帧，Router 不推 motion）。
## S9/T8 增益映射纯函数（批次 V §5.1：旧行内式 (tip−0.5)×GAIN+0.5 后 clamp(0,1) 抽取，行为
## 等价；供无头四角可达断言与 camera_skeleton 活动区域参考框同源换算）。
## 批次 X P2（spec §3）：钳制域 [0,1]→[-CURSOR_OVERSHOOT,1+CURSOR_OVERSHOOT]（函数签名不变，
## 纯函数语义保持；中心段与增益式零变化，仅边界段由硬钳改余量钳——消费侧命中测试自然钳制）。
## 批次 AC（领域四 §4.4-2，2026-09-27）：**纵向中心基准由 0.5 上移至活动框中心**
## c_y = (0.5 + m)/gain（默认 2.5/0.15 → 0.26），与 camera_skeleton.cursor_zone_rect 的
## 顶边贴顶新几何严格互为反函数（框顶 tip_y=0 → 屏幕 −m；框中心 tip_y=c_y → 屏幕 0.5；
## 框底 tip_y=2c_y=0.52 → 屏幕 1+m）。旧码以 (0.5,0.5) 为中心 → 手在视觉框正中时屏幕
## 光标落在 0.5 以下（用户截图红圈到蓝框）——两条改动同批、缺一即错位。gain≤0 回退 0.5。
static func apply_cursor_gain(tip: Vector2, gain: float) -> Vector2:
	var m := CURSOR_OVERSHOOT
	var cy: float = ((0.5 + m) / gain) if gain > 0.0 else 0.5
	return ((tip - Vector2(0.5, cy)) * gain + Vector2(0.5, 0.5)).clamp(Vector2(-m, -m), Vector2(1.0 + m, 1.0 + m))

func _profile(h: Dictionary, side: String, now: float) -> Dictionary:
	var st: Dictionary = _side[side]
	var fingers_v: Variant = h.get("fingers", null)
	var fv: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
	var ext: Array = [false, false, false, false, false]
	var hyst: Array = st_hyst(st)
	# 批次 W（P3-2e，规格 §5）：逐元素防御读取——数组短于 5 或非数值元素不再整帧中断
	#（坑⑦⑪同族：越界下标/float(null) 强转都会中止 feed；缺省/脏值按「未伸直」0.0 处理）。
	# 批次 AA（W2-5/W2-6，spec §5.3）：分指阈值 + 滞回——进入用 FINGER_EXTEND_TH[i]
	#（AD §4.2 现值：拇/食/中/小 0.55、无名指 0.48）、退出用 EXTEND_EXIT_TH(0.45)，
	# [EXIT,ENTER) 带内保持上帧判定，分指独立滞回根治 cursor↔two 姿势抖动翻转。
	for i: int in 5:
		fv[i] = _finger_val(fingers_v, i)
		if float(fv[i]) >= float(FINGER_EXTEND_TH[i]):
			ext[i] = true
		elif float(fv[i]) < EXTEND_EXIT_TH:
			ext[i] = false
		else:
			ext[i] = bool(hyst[i])
	st["ext_hyst"] = ext.duplicate()
	var lm: Array = h.get("landmarks", [])
	var had_prev := bool(st.get("tip_seen", false))
	var prev_tip := Vector2(st.get("last_tip", Vector2.ZERO))
	var tip := Vector2.ZERO
	var src := ""
	if h.has("tip_x") and h.has("tip_y"):
		tip = Vector2(float(h["tip_x"]), float(h["tip_y"]))
		src = "filtered"
	elif lm.size() >= 9:
		tip = Vector2(float(lm[8][0]), float(lm[8][1]))
		src = "landmark"
	elif had_prev:
		tip = prev_tip
		src = "held"
	else:
		tip = Vector2(0.5, 0.5)
		src = "center"
	# 批次 AA（W2-1，spec §5.3）：**二级 EMA 统一平滑路径**——filtered/landmark 两源同走
	# CURSOR_EMA_ALPHA 单系数（旧 :250-254 的 src=="landmark" 速度自适应双档 EMA 是死代码：
	# 生产包恒带 tip_x/tip_y → src 恒 "filtered" → 该分支永不执行，已删除；raw landmark
	# 兜底路径现与 filtered 同一 α，两路径均真实生效=R2-i 护栏断言）。首帧无状态 → 直通。
	# held/center：ema 与保持值同步，防陈旧 EMA 状态串帧。
	if src == "filtered" or src == "landmark":
		if had_prev:
			var ema_prev := Vector2(st.get("ema_tip", tip))
			tip = ema_prev.lerp(tip, CURSOR_EMA_ALPHA)
		st["ema_tip"] = tip
	else:
		st["ema_tip"] = tip
	var jitter := false
	if had_prev and (tip - prev_tip).length() < CURSOR_DEADZONE:
		jitter = true
		tip = prev_tip   # 死区锁上帧（防 1px 级抖动经增益放大成可见漂移；W2-3 死区值见常量区）
	st["last_tip"] = tip
	st["last_tip_at"] = now
	st["tip_seen"] = true
	tip = apply_cursor_gain(tip, CURSOR_GAIN)   # S9/T8 增益（全部消费位同源；批次 V 抽纯函数）
	return {
		"conf": float(h.get("confidence", 0.0)),
		"ext": ext,
		"fingers": fv,   # 批次 AA（W2-6）：原始 fingers 浮点（小指泄漏守卫读 raw 值用）
		"roll": float(h.get("hand_rotation_x", 0.0)),
		"facing": _palm_facing(h),
		"palm_size": float(h.get("palm_size", 0.0)),
		"tip": tip,
		"jitter": jitter,
		"raw_tip": Vector2(st.get("last_tip", Vector2(0.5, 0.5))),   # 批次 AC 4A（§4.6-3）：增益前
		                                                            # 归一 tip（双掌间距判据用——
		                                                            # 增益仅线性放大，间距比不变）
		# 说明：`p["ext"]` 布尔数组的判据**不由 profile 承担**（_classify 负责）；双手协同缩放
		# 的三指门直接读 `p["fingers"]` 原始浮点（与 _profile 同帧快照，无二次分类分叉）。
	}

## 批次 AA（W2-5）：读取分指滞回状态（_new_side 必带；防御缺省全 false）
static func st_hyst(st: Dictionary) -> Array:
	var v: Variant = st.get("ext_hyst", null)
	if typeof(v) == TYPE_ARRAY and (v as Array).size() == 5:
		return v
	return [false, false, false, false, false]

## 批次 W（P3-2e）：fingers 通道防御读取——非数组/越界/非数值（含 null）一律回 0.0（未伸直），
## 不再让脏 feed 中止整帧判定（坑⑦ float(null)、坑⑪ 越界下标同族）。
static func _finger_val(fingers_v: Variant, i: int) -> float:
	if typeof(fingers_v) != TYPE_ARRAY:
		return 0.0
	var arr := fingers_v as Array
	if i < 0 or i >= arr.size():
		return 0.0
	var fv: Variant = arr[i]
	return float(fv) if (typeof(fv) == TYPE_FLOAT or typeof(fv) == TYPE_INT) else 0.0

## 姿态分类（fingers 通道；拇指不管类只看 fingers[1..4]）：
## palm=四指伸直**且小指 >PALM_PINKY_TH**（批次 AA W2-6 小指泄漏守卫）；
## 小指泄漏（0.55~0.70] 的四指形回落 three（做三指删除时小指误伸不变成 palm/清空）。
## 批次 AA（W2-4，spec §5.3）：cursor 态**移除拇指门**（旧 `and not e[0]` 与文件头 §7-9
## 「拇指不管」口径自相矛盾——拇指是最易随视角漂移的一根，大幅斜移 e[0] 越阈 → cursor
## 掉出 → 重新 2 帧确认 → 光标冻结），与 palm/two/three 同口径只看 fingers[1..4]。
## 批次 AC（领域五 §4.5-1）：**中指-无名指肌腱连带解耦**——食+中伸直且小指未伸时，无名指因
## 手背伸肌腱生理连带被抬升（fraw[3] ≤ TWO_RING_COUPLE_MAX=0.65）且明显落后中指
## （fraw[2]−fraw[3] ≥ TWO_MIDDLE_RING_GAP=0.12）→ 判 `two`（食指瞄准后竖中指单击），
## 不再误判 `three`（三指删除；误判会打断 two 确认计数并可能误删）。无名指真实主动伸展
## （fraw[3] > 0.65，或与中指齐平 <0.12）才判 `three`；`st` 上下文（semantic/pend_cls 已处
## cursor/two 链）下差值条件豁免——用户已明确在瞄准/单击链上，只认连带上限。
func _classify(p: Dictionary, st: Dictionary = {}) -> String:
	var e: Array = p["ext"]
	var fraw: Array = p["fingers"]
	if e[1] and e[2] and not e[4]:
		# 批次 AC（§4.5-1）/ AD（§4.2 严格三指约束）：
		# 食指+中指伸直、小指未伸 → two / 连带豁免 / three 三分支
		var ring_v := float(fraw[3])
		var mid_v := float(fraw[2])
		if not e[3]:
			return "two"   # 无名指未伸：真二指（不受中点阈 0.55 影响）
		# e[3] 为真（无名指 ≥0.48 进入阈）：
		# ①无名指被动连带（ring_v <= TWO_RING_COUPLE_MAX 且中指领先 ≥TWO_MIDDLE_RING_GAP）
		#   或瞄准单击链上下文（semantic 处 cursor/two 或 pend_cls==two）→ two；
		# ②**无名指反超中指**（ring_v > mid_v）属异常连带形（真手三指伸展时中指恒 ≥ 无名指，
		#   反超只可能是噪声/二指链牵连）→ **严禁回落 three**（AD §4.2：过渡态直接判 three=
		#   delete 会在瞄准期误发三指批量删除），判 rest；
		# ③其余（食+中+无名三指均伸直、无名指非反超、小指保持弯曲）→ three（删除可达）。
		#   注：**不得**要求 ring_v > TWO_RING_COUPLE_MAX 才判 three——真手无名指 extend
		#   典型仅 ≈0.59（W2-6 记），该要求会让三指删除在真手上不可达。
		if ring_v <= TWO_RING_COUPLE_MAX:
			if mid_v - ring_v >= TWO_MIDDLE_RING_GAP:
				return "two"   # 中指主动、无名指被动跟随（差值判据）
			var ctx := String(st.get("semantic", ""))
			if ctx == "cursor" or ctx == "two" or String(st.get("pend_cls", "")) == "two":
				return "two"   # 瞄准/单击链上下文（差值条件豁免）
			if ring_v > mid_v:
				return "rest"  # 反超异常形：过渡/牵连，严禁 three（AD §4.2）
		# 批次 AD §4.3.2：严格三指批量删除——食、中、无名均 >= 0.55，且小指必须弯曲收拢 <= 0.35
		if float(fraw[1]) >= 0.55 and float(fraw[2]) >= 0.55 and float(fraw[3]) >= 0.55 \
				and float(fraw[4]) <= THREE_PINKY_FOLD_MAX:
			return "three"
		return "rest"
	if e[1] and e[2] and e[3] and e[4]:
		if float(fraw[4]) > PALM_PINKY_TH:
			return "palm"
		var ctx := String(st.get("semantic", ""))
		if ctx == "palm" and not _fingers_any_below(p, FOLD_EXIT_TH):
			return "palm" # 批次 AA P2-1 维持：已处掌态期小指微抖（0.40~0.70）不打断缩放与翻转
		# 批次 AD §4.3.2：小指未收拢严禁判为 three（防四指平展误触发删除）
		return "rest"
	if e[1] and not e[2] and not e[3] and not e[4]:
		return "cursor"   # 仅食指（W2-4：拇指不管，§3.5 Point/Only_Index 归并口径对齐）
	return "rest"

## 审查回修 P2-4：任一四指（食/中/无/小，拇指不管）伸直度低于阈值——缩放态迟滞收掌判定用。
## 批次 Y（Y-A11 连带修复，spec §2-⑪验收前提）：入参改**原始手 dict**——旧码传 profile，
## profile 只有 "ext" 布尔数组、无 "fingers" 浮点数组 → _finger_val(null)=0.0 恒 <0.40 →
## 缩放态下任一后续掌形帧立即误收掌（zoom_end 下一帧即触发，P2-4 迟滞带 [0.40,0.55) 维持
## 缩放语义从未真正生效）——「掌态缩放期间 cursor_move 恒跟随」亦因此不可达。
static func _fingers_any_below(h: Dictionary, th: float) -> bool:
	var f: Variant = h.get("fingers", null)
	for i: int in range(1, 5):
		if _finger_val(f, i) < th:
			return true
	return false

## 掌面朝镜判定（spec §3.6-3 重写口径）：腕0/食指根5/小指根17 三点叉积 z 号与粘性手别标签
## 同相——镜像前提下右掌朝镜 cz>0、左掌朝镜 cz<0；翻面后环绕手性翻转，标签由 D 盘粘性跟踪
## （spec §3.4 沿用）保持稳定。
static func _palm_facing(h: Dictionary) -> bool:
	var lm: Array = h.get("landmarks", [])
	if lm.size() < 21:
		return false
	var w: Array = lm[0]
	var i5: Array = lm[5]
	var p17: Array = lm[17]
	var cz: float = (float(i5[0]) - float(w[0])) * (float(p17[1]) - float(w[1])) \
		- (float(i5[1]) - float(w[1])) * (float(p17[0]) - float(w[0]))
	return (String(h.get("handedness", "Right")) == "Right") == (cz > 0.0)

## 0-360 环形最短角差（-180..180）
static func _angdiff(a: float, b: float) -> float:
	return fposmod(a - b + 180.0, 360.0) - 180.0

func _feed_side(side: String, h: Dictionary, now: float, stale: bool = false) -> Array:
	var out: Array = []
	var st: Dictionary = _side[side]
	if h.is_empty():
		# 批次 AA（W1-11，spec §4.3 W1-11 落点）：心跳空包（无帧期 1Hz，顶层 stale:true）
		# 按 held 语义短路——不 teardown、不派发语义事件、不计在场（本行之前已 return，
		# _last_present_at 不刷新）、累计态（semantic/flip/hand_id/join 边沿）原样保留；
		# 老包（无 stale 字段 → stale=false）仍走 teardown，行为零变化。
		if stale:
			return out
		return _teardown_side(side, st, now)
	_last_present_at[side] = now   # 批次 W（P3-2d）：在场时刻记忆（单翻落空判据用）；held 帧亦计在场（Y-A5 定档）
	# 批次 Y（Y-A5，spec §3.1 held 映射定档）：held 帧=丢帧容忍窗内陈旧数据——不触发该侧
	# teardown、不清翻转状态（FlipDetector 整段冻结：locked/streak/roll0 原样保留）、不计为
	# 翻转（streak 不推进）、零语义事件派发；倒数取消判据经 Router 计 both_present（在场）。
	# 3s 翻转超时（Tracker）照常运行（held 帧不喂 notify_flip）。
	if bool(h.get("held", false)):
		return out
	# 批次 Y（Y-A5）：手 id 变化=新手（Y1 per-hand 稳定 id；id 缺省按「同侧同一手」处理，老包零变化）
	# ——该侧累计态全清（防串手污染）：语义（含兜底 two_up/zoom_end）+翻转锁/进度/冷却一并复位。
	var hid := String(h.get("id", ""))
	var prev_id := String(st.get("hand_id", ""))
	if hid != "" and prev_id != "" and hid != prev_id:
		out.append_array(_teardown_side(side, st, now))
		st = _side[side]   # teardown 已整字典重置，重取引用
	if hid != "":
		st["hand_id"] = hid
	var p := _profile(h, side, now)
	st["last_p"] = p   # 批次 AC 4A（§4.6-3）：本侧最近一帧特征快照（双手协同缩放通道读双掌五要素）
	var cls := _classify(p, st)
	# 批次 AA（W2 审查 P2-1 并入 W3 波，spec §6.3 影响面）：**掌态内泄漏守卫 three 归一回 palm**。
	# 四指全伸而小指 raw ∈ [FOLD_EXIT_TH, PALM_PINKY_TH]（0.40~0.70）时 _classify 落 "three" 纯属
	# 小指抖动/半伸（既未折叠到折叠阈、又过不了 palm 的小指守卫）——此时不得打断**已提交**的掌态：
	# ①缩放态：否则单帧即 zoom_end（缩放被抖动中断）+ 左手再经 2 帧确认提交 delete（误删，审查 P2-1）；
	# ②翻转前置态：flip_streak/锁窗累计被打断（小指一抖翻转前置清零）；
	# ③右掌 dwell：语义掉出即 dwell 锚随 _commit_enter 重置/丢失 → 静止满 1.0s 也永不清空。
	# 掌形**真折叠**（任一四指 < FOLD_EXIT_TH）时 cls 不归一 → palm 支首分支（zooming 收掌）
	# 或正常退出通路照常收掌，收掌语义零变化。
	if String(st.get("semantic", "")) == "palm" and cls == "three" \
			and not _fingers_any_below(h, FOLD_EXIT_TH):
		cls = "palm"
	if float(p["conf"]) < CONF_EXIT:
		return _teardown_side(side, st, now)   # <CONF_EXIT(0.45) 回落：整侧语义退出（§4.2）
	var conf_ok := float(p["conf"]) >= CONF_ENTER
	# 批次 AD（spec §4.1.1）：**光标位置与手势状态机彻底解耦**——本帧是否下发光标只由
	# 「有效手（_valid 已过）+ 置信度激活门」决定，与 sem/cls/二帧确认过渡/flip 并行段
	# 一律无关。置信度激活门与语义门**同源**（非新造判据）：
	#   conf ≥ CONF_ENTER(0.55)  → 本帧可入态（光标 0 帧即时语义的置信度门），必发；
	#   CONF_EXIT(0.45) ≤ conf < CONF_ENTER 且该侧已有语义态 → 既有语义保鲜期内，必发；
	#   二者皆非（全新态 conf∈[0.45,0.55)）→ 沿用既有语义门语义不发（test_gesture_map 段 3
	#   「0.45~0.55 持续 5 帧零 cursor_move」红锁不被削弱）。
	# 派发位集中在 `_feed_side` 末尾（本帧恰一条，杜绝与状态机内散布点重复），**唯一例外**是
	# 二指提交帧：该帧复用既有 `two_move_pending` 机制延至帧末 `_resolve_two_arbitration`
	# 之后补出，保持 [two_down, cursor_move] 顺序（Router S10 光标新鲜度门依赖「先判定后刷
	# 新鲜度」，见 _commit_enter 注）。
	var cursor_live := conf_ok or String(st["semantic"]) != ""
	# FlipDetector 与语义态机并行（§4.1 注 A）
	out.append_array(_feed_flip(side, st, p, cls, conf_ok, now))
	var sem: String = String(st["semantic"])
	match sem:
		"cursor":
			if cls == "cursor":
				# 批次 AC（§4.5-2）：瞄准预备窗每帧刷新——cursor 态持续期间置 now+0.25s，
				# 供「cursor→two 过渡单帧容差」与「确认期 cursor_move 保持」两处消费。
				# 批次 AD（§4.1.1）：本帧 cursor_move 由末尾统一派发点产出（此处不再单独 append）。
				st["cursor_armed_until"] = now + CURSOR_ARM_WINDOW_SEC
			else:
				st["semantic"] = ""
				_join_edges.erase(side)   # 计划 v1.1 遗留注意：离开光标态即清边沿（W3-4 起边沿仅记账，不参与 join 触发）
				_try_enter(side, st, cls, p, conf_ok, now, out)
		"two":
			if cls == "two":
				out.append({"type": "two_move", "side": side, "pos": p["tip"]})
				# 批次 Y（Y-A11，spec §2-⑪）：二指笔画（选中/减选/ORBIT 拖拽）期间该手 cursor_move
				# 持续发送（指尖 lm[8] 口径）——旧码二指态不发 cursor_move → 光标冻结 2s 被
				# HIDE_AFTER_SEC 隐藏（光标恒跟随修复）。批次 AD（§4.1.1）：改由末尾统一派发点
				# 产出同一条（位/序等价：仍在 two_move 之后、本侧意图内）。
			else:
				# 收中指/姿势变化 → 兜底抬起（批次 X P5：旧时序分流退役，
				# 二指态生命周期收敛为 down/move/up 即时事件对，无计时分支）
				out.append({"type": "two_up", "side": side, "pos": p["tip"]})
				st["semantic"] = ""
				if _stroke_owner == side:
					_stroke_owner = ""
				_try_enter(side, st, cls, p, conf_ok, now, out)
		"palm":
			if bool(st["zooming"]) and _fingers_any_below(h, FOLD_EXIT_TH):
				# 审查回修 P2-4：缩放态收掌走迟滞双阈值——任一四指 <0.40 才收掌（spec §5.3「收掌（任一四指
				# 收回<0.40）」），[0.40,0.55) 带内维持缩放防边缘抖动中断；_classify 的 0.55 单阈值仅用于非缩放态
				out.append({"type": "zoom_end", "side": side})
				st["zooming"] = false   # 缩放态结束须复位翻转抑制（FlipDetector 重新可用）
				st["semantic"] = ""
				_stroke_owner = ""
			elif cls != "palm":
				# 收掌（任一四指收回）=缩放态结束，光标恢复（§5.3）
				if bool(st["zooming"]):
					out.append({"type": "zoom_end", "side": side})
					st["zooming"] = false   # 缩放态结束须复位翻转抑制（FlipDetector 重新可用）
				st["semantic"] = ""
				_try_enter(side, st, cls, p, conf_ok, now, out)
			else:
				_ema_palm(st, float(p["palm_size"]))
				# 批次 AC 4A（spec §4.6-3）：**单手推拉缩放默认关**——生产路径下本侧掌态
				# 不再进入/维持 `zooming`（缩放统一由双手协同通道接管，消除单手翻掌/横向移动
				# 误触发缩放）。开关（`set_single_hand_zoom_enabled(true)`）打开时下方旧通道
				# 逐字节照常工作（存量回归夹具兼容接口）；惟对侧当前亦处掌形张开态时让位给
				# 双手协同通道（spec 末条：防左右手双倍触发 zoom_step）。运行中关开关/触发
				# 让位时残留缩放态当场收尾（zoom_end 恰一次）。
				var hand_zoom_active := _single_hand_zoom and not _dual_other_side_takes_over(side)
				if not hand_zoom_active and bool(st["zooming"]):
					out.append({"type": "zoom_end", "side": side})
					st["zooming"] = false
				# 批次 X（P6，spec §7-1 回放实证）：推拉判定全程活跃（翻转互斥仍由 flip_streak
				# 门保留）；无推拉活动且入掌超 PALM_OBSERVE_SEC 后基准慢速跟随 EMA——「停顿后
				# 再推/慢推/快推」均可达（探针 A/A2 红测锁定）。
				var ratio := absf(float(st["palm_ema"]) - float(st["palm_baseline"])) \
					/ maxf(float(st["palm_baseline"]), 0.0001)
				if hand_zoom_active and not bool(st["zooming"]) and int(st["flip_streak"]) == 0 \
						and not bool(st.get("dwell_fired", false)):
					# 批次 AA（W3-2 ③）**旧口径留痕**：dwell_fired（右掌静止已清空）后本掌态
					# 不再进推拉——dwell 计时器与 zoom_begin 状态机互斥单一真值（同次掌态只落其一）。
					# 批次 AD §4.3.4 现口径：dwell 通路废除后该位恒 false（读值恒真、判定中性），
					# 条件保留作旧口径锚与防误删护栏；清空=双手握拳，与推拉彻底解耦。
					if ratio > PALM_PUSH_RATIO:
						st["push_streak"] = int(st["push_streak"]) + 1
						if int(st["push_streak"]) >= PALM_PUSH_FRAMES:
							st["zooming"] = true
							# 修复批 P3（2026-09-26）：缩放意图下本侧翻转前置作废——zoom 期
							# _feed_flip 冻结（:747），入缩放前已锁的 flip_locked 会跨整个缩放段
							# 残留，收掌后残余 1.0s 窗（FLIP_WINDOW_SEC）内翻转姿态仍可触发 flip
							#（探针实证：锁@50.033 → 缩放 → 收掌 → 50.433 误发、cooldown 写入）。
							# 同侧在途 _pending_flip（单翻配对未解算）一并作废；对侧 pending 不动
							#（反向护栏 test_fix_gesture_zoom_flip 段4：作废只限翻转发起侧）。
							st["flip_locked"] = false
							st["flip_streak"] = 0
							if not _pending_flip.is_empty() \
									and String(_pending_flip.get("side", "")) == side:
								_pending_flip = {}
							out.append({"type": "zoom_begin", "side": side})
					else:
						st["push_streak"] = 0
						# 滞回缓冲带 [0.5×RATIO, RATIO] 内冻结基准（防跟随速率追上慢推位移——
						# 红测 A2 实证：无缓冲时基准与 EMA 同速爬升，ratio 峰值恒 <15% 永不触发）
						if now - float(st["palm_at"]) > PALM_OBSERVE_SEC \
								and ratio < PALM_PUSH_RATIO * 0.5:
							st["palm_baseline"] = float(st["palm_baseline"]) \
								+ PALM_FOLLOW_ALPHA * (float(st["palm_ema"]) - float(st["palm_baseline"]))
					# 批次 AD §4.3.4：彻底废除右掌 dwell 清空（由双手握拳清空接管）
					# if not bool(st["zooming"]):
					# 	_feed_palm_dwell(side, st, p, now, out)
				if bool(st["zooming"]):
					# r=当前 EMA palm_size/基准；累计 |log(r)| 越过 ln(1.10) 发一格滚轮（§5.3）
					var r := float(st["palm_ema"]) / maxf(float(st["palm_baseline"]), 0.0001)
					out.append({"type": "zoom_factor", "side": side, "factor": r})  # 点云连续消费
					# 批次 Y（Y-A11，spec §2-⑪）：掌态缩放期间该手 cursor_move 持续发送——旧 §5.3 注 2
					# 「掌态光标暂停」随光标恒跟随拍板收窄为「缩放进行期恒跟随」（观察期仍暂停）。
					# 批次 AD（§4.1.1）：现由末尾统一派发点产出（观察期亦派发，全程恒跟随）。
					st["zoom_cum_log"] = float(st["zoom_cum_log"]) + log(maxf(r, 0.0001))
					while absf(float(st["zoom_cum_log"])) >= ZOOM_STEP_LN:
						var dir := 1 if float(st["zoom_cum_log"]) > 0.0 else -1
						st["zoom_cum_log"] = float(st["zoom_cum_log"]) - ZOOM_STEP_LN * float(dir)
						out.append({"type": "zoom_step", "side": side, "dir": dir})
						# 批次 AC 4A：单手通道开启时同步发显式动作事件（与双手通道同词汇）
						out.append({"type": "zoom_in" if dir > 0 else "zoom_out", "side": side, "dir": dir})
		"three":
			if cls != "three":
				st["semantic"] = ""   # 三指为边沿语义（delete 已在确认帧发出）
				_try_enter(side, st, cls, p, conf_ok, now, out)
		_:
			_try_enter(side, st, cls, p, conf_ok, now, out)
	# 批次 AD（§4.1.1）：末尾统一派发点——本侧本帧恰一条 cursor_move（除非本帧二指提交帧
	# 走 two_move_pending 延后补出，见下方注释），与 sem/cls/确认过渡完全解耦。
	# 排除项说明：
	#   ①two_move_pending=true（本帧二指提交）→ 复用既有帧末仲裁补出，保 [two_down, cursor_move] 序；
	#   ②cursor_live=false（全新态 conf∈[0.45,0.55)）→ 置信度激活门未过，沿用既有语义门语义不发。
	if cursor_live and not bool(st.get("two_move_pending", false)):
		out.append({"type": "cursor_move", "side": side, "pos": p["tip"], "jitter": bool(p["jitter"])})
	return out

## 2 帧确认入口（光标 0 帧即时；two/three/four/palm 须连续 2 帧，§4.2）
## 批次 AA（W2-7，spec §5.3/§5.4-6）：**CONF_ENTER 与确认计数解耦**——旧码
## `if not conf_ok → pend 归零` 在置信度贴 0.55 门线（叠加批次 Z 降
## MIN_DETECTION_CONFIDENCE=0.55 同带）摆动时确认计数被单帧反复重置（「点半天点不动」
## 根因）；现改「置信度门 + 滑窗多数表决」：窗=CONFIRM_FRAMES+1 帧，窗内达标帧过半
## 才推进 1 计数，单帧跌落只暂停推进、不归零。姿态变化（cls 变更/rest）仍整段重置——
## 容错只对置信度抖动、不对姿态切换；光标为 0 帧语义不吃滑窗，置信度门不过=本帧不提交
## （Z5 边界 conf=0.54 不触发语义保持）。
func _try_enter(side: String, st: Dictionary, cls: String, p: Dictionary,
		conf_ok: bool, now: float, out: Array) -> void:
	# 批次 AC（§4.5-2）：瞄准预备窗（cursor 态末帧起 0.25s 内）——窗内 cursor→two 的
	# 过渡单帧（rest/姿势抖动）容忍：不清零已累计的 two 确认计数、不触发兜底抬键，
	# 保证「食指对准后竖中指单击」干脆不丢击。窗口到期或非 two 确认中 → 旧语义照常。
	var armed := now <= float(st.get("cursor_armed_until", -1.0))
	var two_confirming := String(st.get("pend_cls", "")) == "two" \
		and int(st.get("pend_count", 0)) >= 1
	if cls == "rest":
		if armed and two_confirming:
			return
		_clear_pending(st)
		return
	if cls == "palm" and side != "right" and not bool(p["facing"]):
		# 左手四指须掌面朝镜才构成掌态（§5.3）；右手四指即清空候选（拇指不管 §4.2）
		_clear_pending(st)
		return
	if cls == "cursor":
		# 光标 0 帧即时（批次 V §5.3 补门保留：提交必清 2 帧确认暂存，防残留 pend_count
		# 使偏离后单帧中指直通 armed）；置信度门不过=本帧不提交（旧码等价清暂存）。
		_clear_pending(st)
		if conf_ok:
			_commit_enter(side, st, cls, p, now, out)
		return
	if String(st.get("pend_cls", "")) != cls:
		st["pend_cls"] = cls
		st["pend_count"] = 0
		st["conf_hist"] = []
	var hist: Array = st["conf_hist"]
	hist.append(conf_ok)
	while hist.size() > CONFIRM_FRAMES + 1:
		hist.pop_front()
	var ok_n := 0
	for b_v: Variant in hist:
		if bool(b_v):
			ok_n += 1
	if ok_n * 2 > hist.size():   # 严格多数（>半数）→ 计 1 帧（W2-7 滑窗表决）
		st["pend_count"] = int(st["pend_count"]) + 1
	if int(st["pend_count"]) < CONFIRM_FRAMES:
		return
	_clear_pending(st)
	_commit_enter(side, st, cls, p, now, out)

## 批次 AA（W2-7）：确认暂存三键复位单点（pend_cls/pend_count/conf_hist）
static func _clear_pending(st: Dictionary) -> void:
	st["pend_cls"] = ""
	st["pend_count"] = 0
	st["conf_hist"] = []

func _commit_enter(side: String, st: Dictionary, target: String, p: Dictionary,
		now: float, out: Array) -> void:
	match target:
		"cursor":
			st["semantic"] = "cursor"
			_join_edges[side] = now   # 进入仅食指态边沿记账（批次 AA W3-4：判据改双手同帧 two，本记账仅供诊断/W1 手性测试锚）
			# 批次 AD（§4.1.1）：本帧 cursor_move 由 _feed_side 末尾统一派发点产出
			#（状态机内不再散布 append —— 单一派发点，杜绝重复/漏发）。
		"two":
			# 批次 AA（W3-4，spec §6.3 + §22 裁决 3）：对接判据改「双手同帧 two」且判定优先级
			# 高于单击——本侧 two_down **不在确认帧直发**，先挂 two_click_pending，由本帧末
			# _resolve_two_arbitration 统一裁决（对侧同帧/前后帧进入 two → join 承接并作废两侧
			# 左键；对侧非 two → 同帧补发单击）。单笔互斥仅在**对侧非 two**时保持既有语义。
			var other := "right" if side == "left" else "left"
			var other_st: Dictionary = _side[other]
			var other_two := _two_ish(other_st)
			if not other_two and _stroke_owner != "" and _stroke_owner != side:
				return   # 单笔互斥（§13 注 B）：对侧笔活跃 → 该段整段忽略（对侧非 two 时语义不变）
			_stroke_owner = side
			st["semantic"] = "two"
			st["two_pos"] = p["tip"]   # 按下位留存（teardown 兜底抬起同位；亦为抑制态补发按下位）
			# 批次 AA（W3-4）：two_down **与笔画起始帧 cursor_move 统一延至本帧末**
			# _resolve_two_arbitration 仲裁——两侧同帧喂完后再判「对侧是否 two/确认中」，封死
			# 「左键先于对接判定发出」的确认帧窗口（对侧晚一帧起步的错位配对同样被挂起）；单侧
			# two 的补发落在同一帧、零时延，且**保持旧顺序 [two_down, cursor_move]**（S10 光标
			# 新鲜度门依赖该顺序：commit 帧先判定后刷新鲜度，陈旧坐标误点防线不被绕过）。
			st["two_click_pending"] = true
			st["two_move_pending"] = true        # 本帧 cursor_move 待仲裁帧补出（保序）
			st["two_first_jitter"] = bool(p["jitter"])
		"three":
			if side != "left":
				return    # 删除=左手专属（批次 X P5-a/W3-3：左三指=删除；右手三指无语义、零破坏性）
			st["semantic"] = "three"
			# 批次 X P5-a（spec §6）：三指语义让位——旧 focus（聚焦锐眼）退役，改发 delete 意图
			#（Router 分派：光标命中单块=delete_cell 单删 / 未命中=delete_selected 删全部）
			out.append({"type": "delete", "side": side})
		"palm":
			# 批次 AA（W3-1，spec §6.3）：左/右掌走**同一条** palm_begin 链——旧「右手 palm →
			# 立即 clear（semantic=four）」破坏性映射退役；W3-2 曾改由右掌静止 dwell 承担，
			# 批次 AD §4.3.4 起 dwell 彻底废除，现清空=双手握拳（_feed_dual_fist_clear，见段头注）。
			st["semantic"] = "palm"
			st["palm_at"] = now
			st["zooming"] = false
			st["push_streak"] = 0
			st["zoom_cum_log"] = 0.0
			st["palm_ema"] = float(p["palm_size"])
			st["palm_baseline"] = float(p["palm_size"])   # 基准=确认帧 palm_size（§5.3）
			# W3-2：dwell 计时起算（锚=确认帧 palm_size/ema 同值）；两侧均初始化、仅右侧消费
			st["dwell_at"] = now
			st["dwell_anchor"] = float(p["palm_size"])
			st["dwell_roll0"] = float(p["roll"])   # W3-2 取向锚（静止判据 roll 分量）
			st["dwell_tip0"] = Vector2(p["tip"])   # W3 回修 P2-2：位置锚（静止判据 tip 分量）
			st["dwell_fired"] = false
			st["dwell_cancelled"] = false
			out.append({"type": "palm_begin", "side": side})

func _teardown_side(side: String, st: Dictionary, now: float = -1.0) -> Array:
	## 手离场/置信度回落：兜底抬起防虚拟键卡死（抬起位=按下位，计划 v1.1 遗留注意）；
	## 缩放态结束；整侧复位
	var out: Array = []
	if String(st["semantic"]) == "two":
		out.append({"type": "two_up", "side": side, "pos": st["two_pos"]})
	if String(st["semantic"]) == "palm" and bool(st["zooming"]):
		out.append({"type": "zoom_end", "side": side})
	_side[side] = _new_side()
	_stale_since = -1.0   # 批次 AA（P2-2①）：侧 teardown 复位 stale 计时器（超限清态后重新起算）
	_join_edges.erase(side)   # 计划 v1.1 遗留注意：离场清除边沿记账（W3-4 起不参与 join 触发）
	# 批次 W（P3-2d，规格 §5）：单翻落空不再发出撤销/重做——
	# ①翻转手自身离场（pending 对应侧）→ 配对与解算意图均已消失，清；
	# ②另一手离场 → pending.other_recent（翻转时刻快照「另一手 0.5s 内曾在场」——另一手
	#   先翻窗离场或翻后离场均属「落空配对」意图）且本侧非翻转侧 → 清；
	# 另一手从未在场（other_recent=false）→ 不清——窗口闭合解算左 undo/右 redo 的
	# 既有特性保持（F1 回归护栏）。
	#
	# 批次 AC 4A（spec §4.6-7，2026-09-27）：**侧立盲区保留窗**——双手翻掌侧立瞬间 MediaPipe
	# 短暂丢帧会把翻转手整个 teardown 掉（连同刚建立的 pending），同翻配对随之中断（用户
	# 「翻 4 次才弹一次」的配对侧根因）。当**翻转手自身**在 `SAME_WINDOW_SEC` 窗内短暂掉出，
	# 且（①正处于退出倒数期间 或 ②另一只手仍在场）时，**保留 `_pending_flip`** 直至
	# `SAME_WINDOW_SEC` 自然到期或对侧完成同翻配对——手掌回正后对侧翻即可照常配对计数。
	# 其它情形（非倒数期且对侧亦不在场 / 已超配对窗 / 非翻转侧离场）行为**零变化**。
	#
	# 批次 AD 审查回修（2026-09-28，独立审查 P1-2）：**双手分支恢复批次 W P3-2d 旧判据**。
	# 批次 AD 实施曾把本段写成 `not other_recent → 无条件 keep`（单手/双手两态一律保留），
	# 系越 spec 改动——§4.3.3 只要求「**单手**翻转（other_recent=false）在窗内严禁清空」，
	# 并未推翻「双手场景落空配对（other_recent=true 且非翻转侧离场）不发撤销/重做」的
	# P3-2d 拍板；该放宽与上列 P3-2d 注释②自相矛盾（注释保留而代码失效）。现按保守修复原：
	#   · other_recent=false（单手：对侧从未在场）→ §4.3.3 侧立丢帧保护，**无条件保留**；
	#   · other_recent=true（双手：对侧曾在场=落空配对意图）→ 恢复 W/AC 旧判据：
	#     翻转手自身在窗内离场 → 按「倒数中 or 对侧仍在场」保留；非翻转侧离场 → 清空；
	#     超窗 → 清空（到期解算由 _resolve_pending_flip 负责，本段不再放行）。
	if not _pending_flip.is_empty():
		var flip_side := String(_pending_flip["side"])
		var in_window := now >= 0.0 and now - float(_pending_flip.get("at", -1.0)) <= SAME_WINDOW_SEC
		var other_recent := bool(_pending_flip.get("other_recent", false))
		var keep := false
		if not other_recent:
			# 批次 AD §4.3.3：单手翻转（另一手从未在场）100% 受保护，
			# 侧立丢帧期间严禁清空，到期由 _resolve_pending_flip 稳定解算输出 undo/redo
			keep = true
		elif in_window:
			# 双手场景（对侧曾在场=落空配对意图）→ W P3-2d/AC 4A 旧判据（2026-09-28 审查
			# 回修 P1-2 恢复）：翻转手自身窗内掉出按「倒数中 or 对侧仍在场」保留；非翻转侧
			# 离场 → 清空。`_last_present_at` 取**对侧**（opp）在场时刻——旧码即此语义，
			# 勿再用误导名 other_seen 指代自身侧（AD 实施期笔误根除）。
			var opp := "right" if side == "left" else "left"
			var opp_seen := float(_last_present_at.get(opp, -1.0))
			var opp_present := opp_seen >= 0.0 and now - opp_seen <= SAME_WINDOW_SEC
			keep = (_exit_countdown or opp_present) if flip_side == side else false
		if not keep:
			_pending_flip = {}
	if _stroke_owner == side:
		_stroke_owner = ""
	return out

func _ema_palm(st: Dictionary, x: float) -> void:
	st["palm_ema"] = float(st["palm_ema"]) + 0.3 * (x - float(st["palm_ema"]))  # EMA α=0.3

## FlipDetector（§4.1 注 A，撤销/重做/退出共用）：
## 前置=**至少三指伸直（食+中+无名；不参考拇指与小指）**+掌面朝镜，连续 2 帧锁定并记录 roll 基准；
## 批次 AC 4A（spec §4.6-4，2026-09-27）：旧门 `cls == "palm"`（要求四指全伸且小指 >PALM_PINKY_TH
## 0.70）过严——真手伸出三指（食+中+无名、小指微曲）翻转时 cls=="three" 永不满足 → 撤销/重做
## 100% 失效（用户实机反馈）。现放宽为 `palm` 或 `three` 两态**或**分指 ext 的食+中+无名三连真，
## 左手翻转=undo、右手翻转=redo（手别分派在 _resolve_pending_flip，本次不动）。
## 触发=锁定起 1.0s 内 roll 变化>FLIP_ANGLE_DEG(75°) 或 掌法向翻转（双条件取或），连续 2 帧；
## 冷却=触发后 FLIP_COOLDOWN_SEC(0.35s) 不进新前置态（DELETE_FLIP_GUARD_SEC 由
## `suppress_flip_after_delete` 在左三指删除后单独施加）；
## 缩放态中本段不再判翻转（§5.3 两态互斥）。
func _feed_flip(side: String, st: Dictionary, p: Dictionary, cls: String,
		conf_ok: bool, now: float) -> Array:
	var out: Array = []
	if now < float(st["flip_cooldown_until"]):
		st["flip_locked"] = false
		st["flip_streak"] = 0
		return out
	if bool(st["zooming"]):
		return out   # 缩放态：本段掌态不再判翻转（§5.3）
	var e: Array = p["ext"]
	var three_or_more := cls == "palm" or cls == "three" \
		or (bool(e[1]) and bool(e[2]) and bool(e[3]))
	var pre := three_or_more and bool(p["facing"])
	if bool(st["flip_locked"]) and now - float(st["flip_at"]) <= FLIP_WINDOW_SEC:
		# 锁定有效段：触发条件（roll 相对基准 >FLIP_ANGLE_DEG 或 掌法向翻转）连续 2 帧确认
		var rolled := absf(_angdiff(float(p["roll"]), float(st["flip_roll0"]))) > FLIP_ANGLE_DEG
		var flipped := not bool(p["facing"])
		if rolled or flipped:
			st["flip_streak"] = int(st["flip_streak"]) + 1
			if int(st["flip_streak"]) >= CONFIRM_FRAMES:
				st["flip_locked"] = false
				st["flip_streak"] = 0
				st["flip_cooldown_until"] = now + FLIP_COOLDOWN_SEC
				out.append({"type": "flip", "side": side, "at": now})
		else:
			st["flip_streak"] = 0
		return out
	if bool(st["flip_locked"]):
		st["flip_locked"] = false   # 1.0s 窗口闭合未翻转 → 前置态作废（本帧即重新走前置累计，防窗口尾帧吞前置确认）
		st["flip_streak"] = 0
	if pre and conf_ok:
		st["flip_streak"] = int(st["flip_streak"]) + 1
		if int(st["flip_streak"]) >= CONFIRM_FRAMES:
			st["flip_locked"] = true
			st["flip_roll0"] = float(p["roll"])
			st["flip_at"] = now
			st["flip_streak"] = 0   # 触发判定独立计 2 连帧（spec「连续 2 帧」口径；前置确认计数不带入触发段）
	else:
		st["flip_streak"] = 0
	return out

## 单翻配对（§4.1 注 A/§6.1）：SAME_WINDOW_SEC（现 1.2s）窗口内双手都翻 → exit_flip（退出优先；倒数期 #2/#3/#4
## 同翻经此推进 Tracker）；窗口闭合无配对 → 单手翻转=左 undo/右 redo（倒数期在 resolve 中抑制）
func _on_flip_raw(side: String, now: float) -> Array:
	var out: Array = []
	if _pending_flip.is_empty():
		# 批次 W（P3-2d）：快照「另一手 0.5s 内曾在场」——在场而未同翻（翻前/翻后离场皆然）
		# 的单翻属「落空配对」意图，由 _teardown_side 清除（不发撤销/重做）。
		var other := "right" if side == "left" else "left"
		var last_seen: float = float(_last_present_at.get(other, -1.0))
		var other_recent := last_seen >= 0.0 and now - last_seen <= SAME_WINDOW_SEC
		_pending_flip = {"side": side, "at": now, "other_recent": other_recent}
	elif side != String(_pending_flip["side"]) \
			and now - float(_pending_flip["at"]) <= SAME_WINDOW_SEC:
		_pending_flip = {}
		out.append({"type": "exit_flip"})
	elif side == String(_pending_flip["side"]):
		# 批次 W（P3-2e，规格 §5）：同侧连续翻转刷新窗口起点——翻转意图以最后一翻为准，
		# 窗口到期恰解算一次 undo/redo（旧码丢弃第二翻、以首翻起点到期，时点偏早）。
		_pending_flip["at"] = now
	# 跨侧超窗：丢弃（冷却已挡连发）
	return out

func _resolve_pending_flip(now: float) -> Array:
	var out: Array = []
	if _pending_flip.is_empty():
		return out
	if now - float(_pending_flip["at"]) > SAME_WINDOW_SEC:
		var side: String = _pending_flip["side"]
		_pending_flip = {}
		if not _exit_countdown:
			out.append({"type": "undo" if side == "left" else "redo", "side": side})
	return out

## 批次 AD §4.3.4：彻底废除右掌 dwell 清空（由双手握拳清空接管）。
## 批次 AD §4.3.4 退役留痕（审查回修 P2-9）：本桩**零调用方**（原调用点已随废除注释掉，
## 见掌态推拉段 `# _feed_palm_dwell(side, st, p, now, out)`）——签名保留供考古/回滚对照，
## 函数体恒 no-op；PALM_DWELL_* 常量组与 dwell_* 状态位的零消费状态由本桩决定（见常量段头注）。
func _feed_palm_dwell(_side: String, _st: Dictionary, _p: Dictionary, _now: float, _out: Array) -> void:
	return

## 批次 AA（W3-4）：对侧「two 在场」判据——已确认 two（semantic）**或正在确认 two**
## （pend_cls=two）。把确认中纳入判据是「确认帧窗口」处理：本侧确认瞬间对侧尚在双帧确认中
## 即先抑制左键，避免左键先于对接判定发出。
static func _two_ish(st: Dictionary) -> bool:
	if String(st.get("semantic", "")) == "two":
		return true
	return String(st.get("pend_cls", "")) == "two"

## 批次 AA（W3-4）：抑制态 two_down 复原件（与 _commit_enter 同构：pos=按下位 + confirm_frames
## 门标记），保证补发单击与原生单击在 Router 侧零差异。
static func _make_two_down(side: String, st: Dictionary) -> Dictionary:
	return {"type": "two_down", "side": side, "pos": st.get("two_pos", Vector2.ZERO),
		"confirm_frames": CONFIRM_FRAMES}

## 批次 AA（W3-4，spec §6.3 W3-4 + §22 裁决 3）：双手二指对接仲裁（两侧喂帧完成后统一进行，
## 取代旧「双侧 cursor 边沿 ±SAME_WINDOW_SEC」判据；two_down 自本帧起统一延至此处产出）。规则：
## ①两侧皆 semantic=="two" → 每个配对至多一次 join（_join_latched 单真值 + JOIN_COOLDOWN_SEC
##   1s 冷却），本次双手二指意图由 join 承接，两侧挂起的左键合成作废（该帧零 two_down）；
## ②仅一侧在 two 且该侧 two_click_pending、对侧非 two 态（既未确认也未在确认中）→ 同帧补发
##   two_down（单击恢复常态：确认帧窗口内不先发、对侧退出后不丢失、单侧零时延）；
## ③任一侧退出 two → _join_latched 复位（退出条件明确：任一离开 two 即恢复常态）。
func _resolve_two_arbitration(now: float) -> Array:
	var out: Array = []
	var ls: Dictionary = _side["left"]
	var rs: Dictionary = _side["right"]
	var l_two := String(ls.get("semantic", "")) == "two"
	var r_two := String(rs.get("semantic", "")) == "two"
	if l_two and r_two:
		if not _join_latched:
			_join_latched = true
			if now >= _join_cooldown_until:
				out.append({"type": "join"})
				_join_cooldown_until = now + JOIN_COOLDOWN_SEC
		ls["two_click_pending"] = false
		rs["two_click_pending"] = false
		_flush_two_first_move("left", ls, out)
		_flush_two_first_move("right", rs, out)
		return out
	_join_latched = false
	if l_two:
		if bool(ls.get("two_click_pending", false)) and not _two_ish(rs):
			out.append(_make_two_down("left", ls))   # 顺序：two_down 先于本帧 cursor_move（S10 门）
			ls["two_click_pending"] = false
		_flush_two_first_move("left", ls, out)
	if r_two:
		if bool(rs.get("two_click_pending", false)) and not _two_ish(ls):
			out.append(_make_two_down("right", rs))
			rs["two_click_pending"] = false
		_flush_two_first_move("right", rs, out)
	return out

## 批次 AA（W3-4）：确认帧 cursor_move 补出（单次）——与 two_down 同帧产出且恒在其后，
## 意图序与批次 X「[two_down, cursor_move]」逐字一致（S10 新鲜度门/按下位取值零漂移）。
static func _flush_two_first_move(side: String, st: Dictionary, out: Array) -> void:
	if not bool(st.get("two_move_pending", false)):
		return
	st["two_move_pending"] = false
	out.append({"type": "cursor_move", "side": side, "pos": st.get("two_pos", Vector2.ZERO),
		"jitter": bool(st.get("two_first_jitter", false))})

# ==================== 批次 AC 4A（spec §4.6-3）：双手协同推拉/间距缩放 ====================

## 「手掌张开态」判据（至少食+中+无名三指伸直，不参考拇指与小指）——与 `_classify` 的
## palm/three 两态同源（three=食+中+无名；palm=四指且小指过守卫）。读 `p["fingers"]` 原始
## 浮点（与 _profile 同帧快照），阈值 DUAL_POSE_TH 为**双掌协同缩放的独立档**
## （AD §4.2 起与 FINGER_EXTEND_TH 的 1/2/3 位**不再同值**：本档中/无名 0.48/0.48，
## FINGER_EXTEND_TH 现为 0.55/0.48——见常量区注释「已随中指档分叉而失效」）。
static func _dual_open_palm(p: Dictionary) -> bool:
	if p.is_empty():
		return false
	var f: Variant = p.get("fingers", null)
	for i: int in 3:
		if _finger_val(f, i + 1) < float(DUAL_POSE_TH[i]):
			return false
	return true

## 双手协同缩放参与判据：进入前=手掌张开态 + 掌面朝镜（双手对称，无左右之别）；
## 已进入双缩放态后改走**收掌迟滞**——任一四指 < DUAL_ZOOM_FOLD_EXIT_TH 才收掌
##（与单手掌态缩放 FOLD_EXIT_TH 同口径，防边缘抖动中断缩放）。
func _dual_side_participates(side: String, p: Dictionary) -> bool:
	if p.is_empty():
		return false
	if _dual_zooming:
		return not _fingers_any_below(p, DUAL_ZOOM_FOLD_EXIT_TH)
	return _dual_open_palm(p) and bool(p.get("facing", false))

## 对侧是否已具备双手协同缩放资格（兼容开关开启时的接管判据，spec §4.6-3 末条）：
## 「当仅单手在 "palm" 态推拉时照常工作，双手同在 "palm" 时由双手协同缩放通道统一接管，
## 防止左右手双倍触发 zoom_step」——故单手掌通道在**对侧当前也是掌形张开态**时让位。
## 对侧判据取其对上帧 profile（本侧处理时对侧本帧可能尚未喂入；一帧偏斜在 33ms 级，无实感）。
func _dual_other_side_takes_over(side: String) -> bool:
	var other := "right" if side == "left" else "left"
	if not _side.has(other):
		return false
	return _dual_side_participates(other, _side[other].get("last_p", {}))

## 双手协同 push/pull 与空间间距缩放的**唯一裁决点**（每帧两侧语义产出后调用）。
## 判据链（spec §4.6-3 逐条）：
## ①左右双手均在手掌张开态（至少三指）且掌面朝镜 → 记录双掌中心间距基准 `_dual_dist_base`
##   与双掌平均 palm_size 基准 `_dual_palm_base`；
## ②逐帧对间距与平均掌面积做 EMA（DUAL_ZOOM_EMA=0.45），算 r_dist / r_palm，取 |r−1| 较大者
##   为有效缩放比 r_eff；
## ③|r_eff−1| > DUAL_ZOOM_DIST_RATIO 连续 DUAL_ZOOM_FRAMES 帧 → 进入双手缩放态：发
##   `zoom_begin`（并清**双侧** flip_locked/flip_streak/dwell——缩放意图下翻转/清空前置一律作废，
##   与单手掌态缩放同口径），随后按 ln(r_eff) 累计跨 ZOOM_STEP_LN 台阶发 `zoom_step`（dir=+1
##   双手拉开/推近放大，dir=−1 双手靠拢/拉远缩小）与 `zoom_factor`（点云连续消费），并同步发出
##   语义动作事件 `zoom_in`/`zoom_out`（本批新词汇，供语义层/诊断按动作名消费）；
## ④任一手收掌（迟滞门）→ 发 `zoom_end` 并复位全部双缩放累计态。
## **静止基准慢速跟随**（与批次 X P6 单手掌态同款防误触）：未进入缩放态且当帧未越阈时，
## 双基准以 PALM_FOLLOW_ALPHA 跟随 EMA——MediaPipe 静止抖动（约 ±2%）不累积越阈，
## 根治用户实机反馈的「双手静置自走缩放」类误触（10% 门 + 2 帧确认 + 基准跟随三重兜底）。
## 签名 `(now, out)` 与 spec §4.6-3 一致：意图**就地追加**进本帧 `out`（与 `_resolve_two_arbitration`
## 同款"帧末统一裁决"风格；`out` 的既有内容不读不改，纯追加）。
func _feed_dual_palm_zoom(now: float, out: Array) -> void:
	var lp: Dictionary = _side["left"].get("last_p", {})
	var rp: Dictionary = _side["right"].get("last_p", {})
	if not (lp is Dictionary and rp is Dictionary):
		return
	var l_ok := _dual_side_participates("left", lp)
	var r_ok := _dual_side_participates("right", rp)
	if not (l_ok and r_ok):
		if _dual_zooming:
			out.append({"type": "zoom_end", "side": "both"})
			_reset_dual_zoom()
		return
	var palm_avg: float = 0.5 * (float(lp.get("palm_size", 0.0)) + float(rp.get("palm_size", 0.0)))
	if palm_avg <= 0.0001:
		return   # 防御：palm_size 缺失（老包/异常帧）→ 双缩放惰性，零副作用
	var l_tip: Vector2 = lp.get("raw_tip", Vector2.ZERO)
	var r_tip: Vector2 = rp.get("raw_tip", Vector2.ZERO)
	var dist: float = (l_tip - r_tip).length()
	# 双掌中心（增益后 content 归一空间，与 cursor_move.pos 同族）——供消费侧锚定缩放落点
	var mid: Vector2 = 0.5 * (Vector2(lp.get("tip", Vector2.ZERO)) + Vector2(rp.get("tip", Vector2.ZERO)))
	if _dual_dist_ema < 0.0:
		# 首帧参与（或收掌后重入）：EMA 直通 + 置双基准（spec 「记录双掌初始间距与初始双掌均值」）
		_dual_dist_ema = dist
		_dual_palm_ema = palm_avg
		_dual_dist_base = dist
		_dual_palm_base = palm_avg
		_dual_streak = 0
		_dual_cum_log = 0.0
		return
	_dual_dist_ema = _dual_dist_ema + DUAL_ZOOM_EMA * (dist - _dual_dist_ema)
	_dual_palm_ema = _dual_palm_ema + DUAL_ZOOM_EMA * (palm_avg - _dual_palm_ema)
	var r_dist := _dual_dist_ema / maxf(_dual_dist_base, 0.0001)
	var r_palm := _dual_palm_ema / maxf(_dual_palm_base, 0.0001)
	var r_eff := r_dist if absf(r_dist - 1.0) >= absf(r_palm - 1.0) else r_palm
	if not _dual_zooming:
		if absf(r_eff - 1.0) > DUAL_ZOOM_DIST_RATIO:
			_dual_streak = int(_dual_streak) + 1
			if int(_dual_streak) >= DUAL_ZOOM_FRAMES:
				_dual_zooming = true
				# 进入帧的 EMA 已收敛在越阈侧 → 基准并入当前 EMA（防进入首帧 r_eff 反跳回 1 附近）
				_dual_dist_base = _dual_dist_ema
				_dual_palm_base = _dual_palm_ema
				_dual_cum_log = 0.0
				_clear_flip_and_dwell_for_dual_zoom()
				out.append({"type": "zoom_begin", "side": "both"})
		else:
			_dual_streak = 0
			# 静止/微弱位移：双基准慢速跟随 EMA（防静态抖动累积越阈；10% 门远大于单帧跟随步长）
			_dual_dist_base = _dual_dist_base + PALM_FOLLOW_ALPHA * (_dual_dist_ema - _dual_dist_base)
			_dual_palm_base = _dual_palm_base + PALM_FOLLOW_ALPHA * (_dual_palm_ema - _dual_palm_base)
	if not _dual_zooming:
		return
	out.append({"type": "zoom_factor", "side": "both", "factor": r_eff, "pos": mid})   # 点云连续消费
	_dual_cum_log = float(_dual_cum_log) + log(maxf(r_eff, 0.0001))
	while absf(float(_dual_cum_log)) >= ZOOM_STEP_LN:
		var dir := 1 if float(_dual_cum_log) > 0.0 else -1
		_dual_cum_log = float(_dual_cum_log) - ZOOM_STEP_LN * float(dir)
		out.append({"type": "zoom_step", "side": "both", "dir": dir, "pos": mid})
		# 批次 AC 4A：显式动作事件（zoom_in=双手拉开/推近放大；zoom_out=双手靠拢/拉远缩小）
		out.append({"type": "zoom_in" if dir > 0 else "zoom_out", "side": "both", "dir": dir, "pos": mid})

## 双缩放进入时的**双侧**清障（spec §4.6-3「同时清除双侧 flip_locked / flip_streak / dwell」）：
## ①翻转前置/进度清零——双掌推拉期间的腕部姿态变化不再解算成撤销/重做；
## ②在途单翻配对作废（缩放意图下翻转解算无效）；③右掌静止 dwell 取消（缩放与清空互斥单一真值）。
func _clear_flip_and_dwell_for_dual_zoom() -> void:
	for s: String in ["left", "right"]:
		var st: Dictionary = _side[s]
		st["flip_locked"] = false
		st["flip_streak"] = 0
		st["dwell_cancelled"] = true
	_pending_flip = {}

## 批次 AD §4.3.4：双手握拳清空全选（彻底废除右掌 dwell）。
## 左右手同时握拳（食、中、无名 <= 0.35），连续 2 帧确认后派发 {"type": "clear", "side": "both"}，
## 并进入锁存（Latch），直到至少一只手松开握拳后方可重置，防止连续误触发。
func _feed_dual_fist_clear(now: float, out: Array) -> void:
	if _exit_countdown:
		_fist_streak = 0
		return
	var ls: Dictionary = _side["left"]
	var rs: Dictionary = _side["right"]
	var lp: Dictionary = ls.get("last_p", {})
	var rp: Dictionary = rs.get("last_p", {})
	if lp.is_empty() or rp.is_empty():
		_fist_latched = false
		_fist_streak = 0
		return
	var l_seen: float = float(_last_present_at.get("left", -1.0))
	var r_seen: float = float(_last_present_at.get("right", -1.0))
	if l_seen < 0.0 or r_seen < 0.0 or now - l_seen > 0.2 or now - r_seen > 0.2:
		_fist_latched = false
		_fist_streak = 0
		return
	if _is_fist_profile(lp) and _is_fist_profile(rp):
		if bool(ls.get("flip_locked", false)) or bool(rs.get("flip_locked", false)):
			return # 翻转锁定期内挂起清空判定
		if not _fist_latched:
			_fist_streak += 1
			if _fist_streak >= FIST_CONFIRM_FRAMES:
				_fist_latched = true
				out.append({"type": "clear", "side": "both"})
				ls["flip_cooldown_until"] = now + CLEAR_FLIP_GUARD_SEC
				rs["flip_cooldown_until"] = now + CLEAR_FLIP_GUARD_SEC
	else:
		_fist_streak = 0
		_fist_latched = false

static func _is_fist_profile(p: Dictionary) -> bool:
	if p.is_empty():
		return false
	var fv: Variant = p.get("fingers", null)
	if typeof(fv) != TYPE_ARRAY:
		return false
	var arr := fv as Array
	if arr.size() < 4:
		return false
	return _finger_val(arr, 1) <= FIST_FINGER_TH \
		and _finger_val(arr, 2) <= FIST_FINGER_TH \
		and _finger_val(arr, 3) <= FIST_FINGER_TH

