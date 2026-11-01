extends Control
## 关卡场景骨架（批次 D，键鼠优先）。三面板 3D 体素视图 + 顶部 HUD + 提示 + 见证者占位。
## 布局（2026-08-26 确认的三块关系；N12-4 2026-09-10 再放大：左上=最终成品 TargetView
## （批次 Z Z1 起渲染 final_answer 域，target 只留判定）
## 520×202@y64、右上=固定件 JoinView 520×202@y64（外缘对称 12/1140 向中缝扩展）、
## 中央=玩家正在挖的木块 MainView 1060×346@y270（高度让渡仍占满中带；N12-3 起
## MainView「木料」文字标签删除，两侧标签保留）。
## 批次 E 本批接线：挖除交互——右键删除选中组、Ctrl+Z 撤销 / Ctrl+Y（兼 Ctrl+Shift+Z）重做；
## 拾取为纯数学射线-AABB（ray_to_cell），不依赖 Physics；删除=隐藏节点（撤销可恢复）。
## K-G（K6-5/6，spec §10.4）改造：多选=按住左键在体素上划动连续拾取（废 Ctrl+逐点点击）；
## 空白按住拖动=轨道旋转（与划选互斥）；普通单击=单选替换、空白单击/Esc=清空选区。
## 手势版交互（后置批次接口占位，不实现）：左手 OK 手势→圆形光标划过体素多选；
## 张开手掌→取消选择；握拳→删除选中。届时经 GestureBridge 映射到
## select_voxel/clear_selection/delete_selected 同一组接口（多选已由划选承载，
## select_voxel 第二参 additive 为手势版保留）。
## 批次 F 接线：计时（_ready 起 mm:ss）、对接判定 evaluate_join（spec 5.2 三分支：
## success=剩余==任一 target / unfit=与固定件干涉 / wrong=形状不对）、
## 成功动画（木料缩小→相机拉远→文物点云聚合，spec 8.4：不可跳过、速度较快、首/重玩都播）
## 与结算路由（评级/天赋值按 spec 8.5：完美≤180s 全额、良好≤360s 80%、及格 60%；
## 第 1~5 关完美档 100/200/400/800/1600；重玩第 4 次起不发放）→ SETTLE。
## 批次 G 接线（第 1 关润色）：①锐眼（spec 7.4）——EyeButton → 时长菜单
## （0.5~3.0s，缺省 1.0）→ 一次性扣费 cost=int(50×时长/0.5)；余额不足提示「天赋值不足」；
## 红绿差集：多余（remaining−target）=红 mark、缺少（target−remaining）=绿 ghost；
## 开启期间挖除/撤销/重做实时重算；到时自动关闭；激活中重开=旧效果先清再扣费重开。
## ②见证者（spec 8.6/3.2）——监听 skin_changed 刷新立绘（修批次 D P3）、正弦上下浮动+
## 缩放呼吸、点击弹「……」气泡（台词留空铁律，待用户台词后替换 TODO）。
## ③退出（spec 3.10/5.1）——重玩（context.replay=true）左下 ExitReplayButton → 确认「返回
## 图鉴？」→ CATALOG；正常流程 TopBar ExitButton → 确认「返回主菜单？」→ MAIN_MENU；
## 输入锁定期间退出/锐眼禁用且处理器守卫。

const DEFAULT_BG := "res://assets/backgrounds/bg_chapter1.png"
const DEFAULT_WITNESS := "res://assets/characters/default_witness.png"
const PM := preload("res://scripts/portrait_metrics.gd")  # M-D：立绘可见内容度量共享工具
const CoordSpace := preload("res://scripts/coord_space.gd")  # 窗口缩放坐标修复1c：content↔device 纯函数
# ---- M-E（spec §3.5，拍板 #6）：正交等轴测相机（参考 m06 观感基准）----
# 根因修复：原透视 FOV75 距离 6 < 木块包围球半径 9（相机在包围球内）→ 近平面裁切
# + 畸形梯形 +「界限」+ 整边消失；正交化后距离与裁切解耦，拾取（project_ray + slab）零改动。
# 等价替换留痕：CAM_DIST0/CAM_DIST_MIN/MAX（K6-1 透视 6/[4.5,14]）、CAM_DIST_SIDE/
# SIDE_DIST_MIN/MAX（K6-3/4 侧视图 4.5/[3,10]）——全部废止，缩放改 ortho size 语义。
const ORBIT_YAW0_DEG := 45.0      # 初始 yaw=45°（真等轴测；原 -35 奇葩角）
const ORBIT_PITCH0_DEG := 35.264  # 初始 pitch=atan(1/√2)≈35.264°（原 22）
const ORTHO_DIST := 20.0          # 相机距离固定 20（near 0.1/far 100，包围球恒在锥内）
const ORTHO_NEAR := 0.1
const ORTHO_FAR := 100.0
# ---- M-E 回修4（用户方案 2026-09-08「窗口拉大+块限幅不穿帮」）：取景/限幅按窗口尺寸
# 与块投影包围盒动态推导，废除固定直径倍数口径（等价替换留痕：ORTHO_SIZE_MUL0=1.25、
# ORTHO_SIDE_SIZE_MUL0=0.85、ORTHO_SIZE_MIN_MUL=0.30——直径倍数与窗口无关，宽扁窗下
# 初始块过小致用户疯狂放大而穿帮；新口径初始取景即「当前朝向最大不穿帮档」）。
const MAIN_FILL_W0 := 0.75        # 主视图初始块投影宽占视口宽目标（垂直约束更紧时被压制）
const SIDE_FILL_W0 := 0.70        # 侧视图初始块投影宽占视口宽目标
const VIEW_FIT_MARGIN := 8.0      # 最大放大档四周留边（px）——「保证不会穿帮」的硬边距
const ORTHO_SIZE_MAX_MUL := 4.0   # 滚轮缩小上限（直径倍数；缩小方向永远安全，保留定值）
const ORTHO_ZOOM_IN := 0.9        # 滚轮上缩小 size
const ORTHO_ZOOM_OUT := 1.1       # 滚轮下放大 size
const SIDE_YAW0_DEG := 45.0       # 侧视图初始等距视角（M-E 统一真等轴测口径）
const SIDE_PITCH0_DEG := 35.264   # 原 31 → 35.264（三视图统一）
const ORBIT_SPEED := 0.005        # 拖拽角速度（rad/px）
const PITCH_LIMIT_DEG := 80.0     # pitch 夹紧 ±80°（防翻转奇点）

# 木色材质（浅木=原木料/目标成品，深木=固定件；§0.5 总表色板，叠程序化木纹贴图）
const WOOD_LIGHT := Color(0.62, 0.44, 0.24)
const WOOD_DARK := Color(0.36, 0.24, 0.13)

# 拾取未命中哨兵：Vector3i.ZERO 可能是合法体素，必须用显式负值哨兵区分
const NO_CELL := Vector3i(-1, -1, -1)
# 常驻操作提示文案（M-E 拍板 #8：精简为一行键鼠操作模板——原「按住左键划动…」超长话术
# 与「剩余体素 N/M」计数、对接引导句全部移出提示行：计数挪 TopBar/VoxelLabel、
# 对接引导迁 JoinButton.tooltip_text（spec §3.5 目标行为 6）。
# M-E 回修4 C：右键分流进模板（右键点删除/拖旋转合并段），并全句精简适配主题字体
# 18px 单行 ≤ 容器宽 1013px（走查实测口径，tools_me4_shot/probe_hint_width.gd 量宽定稿）。
const HINT_OPERATIONS := "左键划选 · Ctrl+点击多选 · 右键点删除 · 右键/中键/空白拖=旋转 · 滚轮缩放 · Ctrl+Z/Y 撤/取消撤回 · 点空白取消选中"
const HINT_FONT_SIZE := 18  # 回修4：提示行字号（主题默认 20 时旧文案已贴满，当时文案 18px 实测 947px；2026-09-11 文案修订「撤/取消撤回」后套件量宽 917px ≤ 预算 1014px 仍适配）
# 对接引导句（M-E：不再进提示行，语义由顶栏对接按钮 tooltip 承载——零新增 UI）
# 批次 Z 终审 P2：判定基准=标准答案（target_shapes），左上面板显示=最终成品（final）——
# 旧提示名与 Z1 改名后的面板实际内容已不符，改按新口径措辞（本文件旧名零残留，反向锚锁死）。
const HINT_JOIN_GUIDE := "挖出与标准答案一致的形状后对接"
# 顶栏剩余体素计数格式（M-E 拍板 #8：删除/撤销/重做实时刷新）
const VOXEL_LABEL_FMT := "剩余体素：%d / %d"
# 提示警示色（保留供 hint 语义色；失败长文案醒目化体系已随 K4-2 迁 Game.toast 删除）
const HINT_WARN_COLOR := Color(1.0, 0.45, 0.35)
# ---- 批次 F：评级与天赋值（数值来源 spec 8.5 原文表格）----
# 评级时间阈值：完美 ≤3 分钟、良好 ≤6 分钟、及格=完成即有（>6 分钟）
const GRADE_TIME_PERFECT := 180.0
const GRADE_TIME_GOOD := 360.0
# 第 1~5 关完美档天赋值（良好 80%、及格 60%）
const CHAPTER_PERFECT_TALENT: Array = [100, 200, 400, 800, 1600]
const GRADE_MULT := {"perfect": 1.0, "good": 0.8, "pass": 0.6}
const GRADE_NAMES := {"perfect": "完美", "good": "良好", "pass": "及格"}
# 判定结果（evaluate_join 返回值，spec 5.2 三分支）
const JOIN_SUCCESS := "success"
const JOIN_UNFIT := "unfit"
const JOIN_WRONG := "wrong"
# 批次 N1（spec §6.1）：48 种正交变换等价工具——对接判定与锐眼差集的单一真相源
# （evaluate_join 与 diff_vs_target 一律经它实现，防两处口径漂移误导玩家）。
const JoinXform := preload("res://scripts/join_transform.gd")
# 批次 W（P3-1）：色彩单源表（值不变）。
const Palette := preload("res://scripts/palette.gd")
# ---- 批次 N4（spec §6.6）：成功动画四段式时长（spec 8.4 硬约束：总时长 2.5~4s、不可跳过、
# 首/重玩都播）。P批波2等价替换（2026-09-10 用户口径 P-C「发散放慢+滞空」）：ANIM_SPREAD
# 0.5→1.2（聚焦散开 SPREAD_TIME 1.2 同口径），总时长重排 0.25+0.5+1.2+1.1+0.9=3.95s ∈[2.5,4]
# （O批 0.25+0.5+0.5+1.3+1.0=3.55s 档废止留痕）。等价替换留痕：M-Gb 三段式 ANIM_DISSOLVE=0.9/
# ANIM_AGGREGATE=1.5/ANIM_SPIN=1.2 废止——四段式=①凝聚（三视图分组统一 实体→粒子面，复用
# N3 全屏三色管线）②持续+突然散开 ③同批粒子接力聚合 ④回看自转+拖拽直入结算（P批波2 起
# 末段对位窗口废止——结算 UI 由本场景覆盖层承载，建模以玩家姿态直入不回正）；Fisher-Yates
# 逐体素随机序与 CLOUD_MODEL_HEIGHT=420px 归一化、SPIN_PIVOT_PITCH_DEG=-8 一并废止（聚合
# 直接按结算 fit 口径归一、初始朝向=结算 30/22）----
const ANIM_CONDENSE := 0.25  # ①凝聚：三视图分组统一凝聚（activate_channel_all，体素实体在屏起点）
const ANIM_HOLD := 0.5       # ②持续：粒子面稳态保持 0.5s（=FocusFX.FOCUS_HOLD_TIME 两处口径一致，用户口径③）
const ANIM_SPREAD := 1.2     # ②突然散开：粒子逃出屏幕（P批波2 放慢+滞空缓动；O批 0.5 废止留痕）
const ANIM_AGGREGATE := 1.1  # ③聚合：散开末帧逐点接力聚成单一金色建模（P批波2 平衡 1.3→1.1）
const ANIM_REVIEW := 0.9     # ④回看：自转（SPIN_SPEED_DEG）+玩家拖拽，全程自转窗口直入结算
# P批波2等价替换留痕：ANIM_ALIGN=0.3（④内对位窗口）随「不回正不重建」架构废止——回看段末
# 不再转向结算初始朝向（对位 lerp/失配回退整套删除，建模保持玩家旋转姿态直入结算）。
const SPIN_SPEED_DEG := 20.0  # 回看自转角速度 °/s（spec 暂定值，走查微调；总转角=速度×回看段）
# ---- 聚合建模金黄口径（M-Gb 黑膜修复口径保留，对齐 settle GOLD_TINT / point_cloud_viewer）----
const CLOUD_TINT := Color(0.96, 0.77, 0.26)
const CLOUD_TINT_STRENGTH := 0.85  # 契约面保留（O批起成功动画建模改全金覆写不消费，用户口径④
								   # 「全部点金黄色」；图鉴/结算 viewer tint 档仍 0.85）
const CLOUD_DELAY_MAX := 0.35      # 聚合逐点延迟上限（占聚合段比例；分层聚合防「齐步走」感）
# ---- 批次 N4：同位续接对位（spec §6.6 方案口径 4 + §九风险 12）→ P批波2 单一真相源重写 ----
# P批波2（用户口径 P-D「结算页面再创一次建模导致位置对不上/旋转回正」根因消除）：结算 UI
# 合并进本场景覆盖层，settle_scene 退役不再被路由（文件保留防 asset 断链）——对位参数从
# 「instantiate 结算场景 live 读 + 镜像兜底常量」收敛为本场景**单一真相源常量表**：挂载 rect
# 由 SETTLE_MOUNT_ANCHORS×当前视口直接计算，fov/视距/归一化/初始朝向/点径下限全部常量定值。
# 等价替换留痕：SETTLE_SCENE_PATH / SETTLE_FOV_MIRROR / SETTLE_POINT_SIZE_MIRROR（镜像兜底）
# 与 read_settle_align live 读段整套废止；失配回退（mount_rect_ok false→建模淡出）随常量表
# 无失配态一并废止。settle_match_fov 纯函数保留（覆盖层相机投影匹配仍消费）。
const SETTLE_VIEWER_SCRIPT := "res://scripts/point_cloud_viewer.gd"
# ---- P-D 结算建模参数单一真相源（原 settle_scene/viewer 同值收敛；走查调档单点）----
const SETTLE_MOUNT_ANCHORS := Rect2(0.18, 0.06, 0.64, 0.60)  # 建模挂载锚点（原 settle CenterMount 同值）
const SETTLE_CAMERA_DISTANCE := 2.8  # 建模视距（原 settle_scene.SETTLE_CAMERA_DISTANCE 同值）
const SETTLE_FOV := 45.0             # viewer KEEP_HEIGHT 垂直 fov（原镜像 SETTLE_FOV_MIRROR 定值）
const SETTLE_FIT_SIZE := 2.2         # 点云归一化对角线（=viewer FIT_SIZE）
const SETTLE_INIT_YAW := 30.0        # 建模初始朝向（=viewer INIT_YAW_DEG）
const SETTLE_INIT_PITCH := 22.0      # 建模初始俯仰（=viewer INIT_TILT_DEG）
const SETTLE_TILT_LIMIT := 75.0      # 俯仰夹紧（=viewer TILT_LIMIT_DEG）
const SETTLE_POINT_SIZE_MIN := 0.012 # 圆点世界尺寸下限（=viewer DOT_SIZE_MIN；原 0.005 亚像素档废止）
# ---- P-D 结算 UI（覆盖层承载）淡入演出参数（用户口径「从水里起来的感觉」；走查调档单点）----
const SETTLE_UI_FADE_TIME := 0.7     # 淡入时长 s（0.6~0.8 档中值）
const SETTLE_UI_RISE_OFFSET := 40.0  # 起始 y 偏移 px（从下往上，非完全从屏幕底出来）
const SETTLE_UI_STAGGER := 0.1       # 三 Label/按钮级联错峰 s（更有质感）
const SETTLE_DIM_ALPHA := 0.5        # 结算压暗层（对齐退役 settle Dim 0.62 与关卡背景渐晕观感折中）
const SETTLE_FONT_SIZE := 22         # 结算三 Label 字号（评级/耗时/获得天赋值）
const SETTLE_FONT_DARK := Palette.TEXT_DARK_SETTLE   # 结算米白字（P3-1 单源，值不变；AB-3 恒深档）

# ---- 批次 W（P1-6，规格 §4）：顶栏四标签+底部提示行字色（tscn 静态 override 删除，
# 经 _apply_level_bar_theme 挂 override；批次 AB-3：恒深档） ----
const LEVEL_BAR_FONT_DARK := Palette.TEXT_DARK_LEVELBAR   # 顶栏米白字（P3-1 单源，值不变）

# ---- 批次 G：锐眼（spec 7.4，2026-08-27 任务单确认决策）----
const EYE_DURATIONS: Array = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0]  # 时长档位（秒）
const EYE_DEFAULT_DURATION := 1.0  # 缺省档位
const EYE_RATE := 50.0       # 50 天赋值 / 0.5 秒（一次性扣）
const EYE_RATE_UNIT := 0.5
const EYE_HINT_POOR := "天赋值不足，无法开启锐眼（需 %d，当前 %d）"
# ---- 批次 Y（Y-C4，spec §9.2 拍板 7）：第 5 关锐眼免费——清批次 G 既有 TODO（spec 7.4 遗留）----
## 集中落点：EYE_FREE_CHAPTER 常量 + is_eye_free_chapter 谓词 + eye_cost_for_chapter 计费口；
## 第 5 关不扣费、激活/差集/到时自动关流程不变；第 1~4 关照旧按 EYE_RATE 计费。
## 红测锁：tests/test_y5_eye_free.gd（第 5 关扣费=0、第 1 关照旧扣费=100）。
const EYE_FREE_CHAPTER := 5
const EYE_PANEL_SCRIPT := preload("res://scenes/level/eye_duration_panel.gd")  # P4 自绘面板（PopupMenu 退役）

# ---- 批次 G：见证者（spec 8.6/3.2：缩小放大、上下浮动纯装饰）----
const WITNESS_FLOAT_AMP := 6.0     # 上下浮动幅度（px）
const WITNESS_FLOAT_SPEED := 2.0   # 浮动角速度（rad/s，y=基准+幅度×sin(phase)）
const WITNESS_BREATH_AMP := 0.03   # 缩放呼吸幅度（scale=1+幅度×sin(2×phase)）
const WITNESS_BUBBLE_SECONDS := 4.0  # 气泡自动隐藏秒数（批次 Z Z3-6 拍板：4s 口径不变）
# ---- 批次 Z（Z3-6，用户拍板 2026-09-24）：气泡**入场动效**——只加「淡入 + 轻微缩放弹跳」
# （约 0.2s）；弹窗样式与 4 秒自灭完全不变；**不做打字机**（弹出即整句、入场期文本恒定）。
# 入场曲线：a 线性 0→1（0.2s）；scale 起 0.72 → 0.12s 过冲 1.06 → 0.2s 回落 1.0。
# **缩放原点必须保持默认 (0,0)**（Godot 4.7 实证，批次 Z 走查定谳）：非单位 scale × 非零
# pivot 会把 Control 变换原点平移 pivot·(1−s)——40×0.28=11.2px，使 global_position 漂移、
# 击穿 test_level_extra「气泡全局底==可见头顶−4」既有几何契约（该契约按 global_position+
# size 度量，锁死 pivot=0）；视觉上气泡自顶向下展开落回头顶（过冲 1.06 时底边仅越 GAP 内
# 2.4px，不穿头）。红测：tests/test_z_bubble_entry.gd（中途帧护栏：a∈(0,1) 帧 + scale>1.0
# 过冲帧，防空转假绿；批次 W ToastCenter 教训）。
const WITNESS_BUBBLE_ENTER_SEC := 0.2     # 入场时长（秒，约 0.2s 档）
const WITNESS_BUBBLE_ENTER_SCALE := 0.72  # 入场起始缩放
const WITNESS_BUBBLE_BOUNCE_SCALE := 1.06 # 弹跳过冲峰值（终值回落 1.0）
const WITNESS_BUBBLE_GAP := 4.0      # M-D 回修（2026-09-08 用户验收）：盒底贴可见头顶 −4px
# （回修 8→4 配合文字贴盒底对齐，视觉文字底距头顶 = 4 + margin_bottom 6 = 10 ≤ 15px）
# ---- M-D 回修2 E（用户 2026-09-08 终审意见）：气泡互动文案旧 8 条——批次 Y（Y-C8）退役 ----
## 旧顺序轮换数组 WITNESS_BUBBLE_LINES（批次 M 用户授权试写 8 条，见提交 ad85663）随洗牌袋
## 上线退役：台词源改读 剧情对话/气泡_第N关.json（Y4 域交付；第 1 关 12 条=用户 2026-09-22
## 正式文案逐字入库，零改写迁移；第 2~5 关占位待替换——铁律 8 不变）。退役留痕（逐字）：
##   "凿子拿稳啦" / "榫卯要严丝合缝哦" / "别急，木头不会跑" / "这个凹槽，再挖深一点点？"
##   / "手稳一点，我再看看" / "我就在旁边陪着你" / "挖好的形状，和我比比看？"
##   / "累了就歇会儿，我不催你"
## 抽取器=scripts/bubble_lines_bag.gd（整轮不重复、轮尽重洗；缺文件/空池不弹+告警不崩）。
const BubbleBag := preload("res://scripts/bubble_lines_bag.gd")
# ---- M-D 回修：气泡背板/字色（对齐追1 对话背板 70~80% 口径与 M-A 可读性口径）----
# 批次 AB-3：BUBBLE_BG_LIGHT/BUBBLE_FONT_LIGHT 浅档随深浅主题机制删除退役，深档为唯一值。
const BUBBLE_BG_DARK := Color(0.36, 0.26, 0.10, 0.75)   # 气泡黄棕半透底（同对话背板）
const BUBBLE_FONT_DARK := Palette.TEXT_DARK_SETTLE       # 气泡米白系字（P3-1 单源，值不变）
const BUBBLE_FONT_SIZE := 18       # UI 语言一致、看得清（引擎默认 16 基础上 +2）
const BUBBLE_MARGIN_H := 14.0      # 背板左右 content margin
const BUBBLE_MARGIN_TOP := 8.0     # 背板上 content margin
const BUBBLE_MARGIN_BOTTOM := 6.0  # 背板下 content margin（文字贴底时距盒底 6px）
const BUBBLE_HOVER_ENERGY := 1.0   # hover 光晕总幅 u_strength 渐入目标（加色峰值=u_glow_k 0.16，
# 与 M-C 光标光斑同族同档，不亮瞎）；半径/加色用 hover_glow shader 定档默认（u_glow_radius_btn
# 85 / u_glow_k 0.16，M-C 字面口径「加色 0.16/半径 85」）
const BUBBLE_GLOW_EXPAND := 24.0   # 覆盖层 rect 外扩（容纳 12px 掩码渐隐余量）
const BUBBLE_HOVER_SPEED := 8.0    # hover 能量渐入渐出速率（能量/s）

# ---- 批次 G：退出确认文案（spec 3.10/5.1）----
# P2（批次 P 波 1，2026-09-10 用户口径）：进度已能存（N9 断点存档链），「关卡进度不保留」
# 提示与实际行为冲突 → 两处删除；重玩句整句简化（P批等价替换原两常量文案）。
const EXIT_MENU_TEXT := "返回主菜单？"
const EXIT_CATALOG_TEXT := "返回图鉴？"

@onready var background: TextureRect = $Background
@onready var title_label: Label = $TopBar/TitleLabel
@onready var talent_label: Label = $TopBar/TalentLabel
@onready var timer_label: Label = $TopBar/TimerLabel
@onready var voxel_label: Label = $TopBar/VoxelLabel  # M-E 拍板 #8：剩余体素计数挪顶栏
@onready var eye_btn: Button = $TopBar/Buttons/EyeButton
@onready var join_btn: Button = $TopBar/Buttons/JoinButton
@onready var focus_btn: Button = $TopBar/Buttons/FocusButton  # K6-7：聚焦（金色点云）
@onready var exit_btn: Button = $TopBar/Buttons/ExitButton
@onready var hint_label: Label = $HintLabel
@onready var witness: TextureRect = $WitnessPortrait
@onready var exit_replay_btn: Button = $ExitReplayButton
@onready var witness_bubble: Label = $WitnessBubble
# 三视图 SubViewport（VoxelView 经 get_node_or_null + call() 动态访问，规避
# --script 测试模式 class_name 注册时序问题，见 T14 实测记录）
@onready var main_viewport: SubViewport = $MainView/ViewportContainer/SubViewport
@onready var target_viewport: SubViewport = $TargetView/ViewportContainer/SubViewport
@onready var join_viewport: SubViewport = $JoinView/ViewportContainer/SubViewport

var _chapter: int = 1
var _replay_mode: bool = false   # 批次 G：图鉴重玩进入（spec 3.10 左下退出按钮）
var _level: Dictionary = {}
var _mat_light: StandardMaterial3D
var _mat_dark: StandardMaterial3D
var _target_shape0: Array = []   # 批次 G：锐眼差集基准 target_shapes[0]（构建时缓存）

# ---- 批次 E 挖除状态（MainView 玩家视图）----
var _selected: Dictionary = {}   # 选区 Set：Vector3i(cell) → true
var _remaining: Dictionary = {}  # 当前仍存在体素 Set：Vector3i(cell) → true（初始=blocks 全集）
var _undo_stack: Array = []      # 撤销栈，元素=Array[Vector3i]（一次删除的组）
# W9-8（批次 AA 规格 §12 P3-9）：撤销栈上限——超出丢最旧（保留最近 MAX_UNDO 条），防长时游玩
# 栈无界增长。【暂定值·待用户复验】（规格 §15 暂定值表登记）；编辑器同构件 voxel_edit_ops 同值。
const MAX_UNDO := 200
var _redo_stack: Array = []      # 重做栈，元素同上
var _initial_total: int = 0      # 初始体素总数（提示「N / 192」用）
# ---- 批次 N9（spec §6.11）：挖除断点（deleted_cells 差集）存档/重放 ----
var _initial_cells: Dictionary = {}  # 进关初始体素全集快照（断点导出基准=blocks−_remaining；
# 与 _remaining 同源构建、构建后不随挖除变化——撤销/重做只动 _remaining）
var _voxel_size: Vector3i = Vector3i.ZERO    # 木料包围盒尺寸（拾取越界过滤；批次 V 起恒锚 blocks 域）
var _target_size: Vector3i = Vector3i.ZERO   # 批次 W（P2-8）：target 域尺寸缓存（_build_views 按
# _domain_size(piece,"target_size",bs) 写入；锐眼差集过滤域——现网档缺省 target_size 回落
# block_size 时与旧口径逐字节等价，target_size>block_size 的内存档不再「红绿皆空」）
# 批次 V（规格 §9.5）：侧视图域尺寸缓存（"Target"/"Join" → Vector3i）——_build_views 按各域
# 尺寸构建后写入；_raycast_side_at 侧视拾取按各自域过滤（超 block_size 的界内格可悬停/选中）。
var _view_sizes: Dictionary = {}
var _voxel_center: Vector3 = Vector3.ZERO    # 构建时包围盒中心（拾取几何与渲染一致）

# ---- M-E（spec §3.5）：MainView 正交轨道相机状态 ----
# 等价替换留痕：_cam_dist（透视轨道距离，K6-1 [4.5,14] 滚轮缩放）废止——距离固定 ORTHO_DIST，
# 滚轮缩放改调 _ortho_size_main（ortho size 语义，限幅=包围球直径 1.2~4.0 倍）。
var _orbit_yaw: float = deg_to_rad(ORBIT_YAW0_DEG)
var _orbit_pitch: float = deg_to_rad(ORBIT_PITCH0_DEG)
var _ortho_size_main: float = 0.0   # MainView 正交取景尺寸（build 后按窗口适配初始化，滚轮实时调）
var _main_diameter: float = 0.0     # MainView 块包围球直径（缩小上限基准）
var _ortho_size_side: Dictionary = {"Target": 0.0, "Join": 0.0}  # 侧视图正交取景尺寸（各按自身直径）
var _view_aabb_size := {}  # 回修4：view → Vector3 构建格集 AABB 世界尺寸（取景/限幅投影基准）
var _left_pressed: bool = false   # 左键按住中（仅按住时的 motion 才驱动划选/旋转）
var _middle_pressed: bool = false # M-E②：中键按住中（任意位置拖拽=旋转，体素上方也可转）
var _right_pressed: bool = false  # 回修4 C：右键按住中（位移>2px=拖拽旋转；原地抬起=删除）
var _right_moved: float = 0.0     # 回修4 C：本次右键按住累计位移（px，阈值判定）
var _right_orbit: bool = false    # 回修4 C：本次右键是否已成旋转拖拽（成转后抬起不删除）
var _last_motion_pos: Vector2 = Vector2.ZERO
# ---- K-G（K6-5/6，spec §10.4）：按下即时 raycast 分流状态机（取代旧 DRAG_THRESHOLD 判定）----
enum DragMode { NONE, STROKE, ORBIT, STROKE_DESELECT }
var _drag_mode: int = DragMode.NONE
var _stroke_start_cell: Vector3i = NO_CELL
var _stroke_new_seen := false     # 本次划选是否扫出新格（全程未划出→抬起=单选替换）
var _orbit_moved := 0.0           # ORBIT 态累计位移（<2px 抬起=空白单击清空选区）
# ---- M-E 追2：悬停拾取状态（壳方案废弃，点光状态见下方常量区）----
var _hover_cells := {"Main": NO_CELL, "Target": NO_CELL, "Join": NO_CELL}  # 追2：各视图悬停格
var _hover_lights := {}    # 追2：view → OmniLight3D（_ready 预创建三盏）
var _hover_light_targets := {"Main": 0.0, "Target": 0.0, "Join": 0.0}
var _view_centers := {}    # view → Vector3 拾取几何中心（build_views 缓存，含侧视图）
var _view_cells := {}      # view → Array 构建格集缓存（侧视图悬停拾取用，D）

# ---- 批次 F：计时 / 成功流程状态 ----
var _start_ms: int = 0            # 关卡计时起点（_ready）
var _final_elapsed: float = 0.0   # 对接成功时刻的耗时（秒）
var _input_locked: bool = false   # 成功动画期间锁定输入（防连点/防误操作）
var _success_started: bool = false
var _settled: bool = false        # 结算只发一次（skip 钩子与动画完成互斥）
# N11（批次 W 规格 §3，拍板 3）：关卡进度实时自动存档防抖——挖除/撤销/重做等改动路径置脏，
# _process 判 ≥2s 无新改动即落检查点（强杀最多丢 2 秒）；退出确认/切场景/窗口×立即兜底。
const CHECKPOINT_DEBOUNCE_MS := 2000
var _checkpoint_dirty_at: int = -1  # 最后一次改动时刻 ms（-1=无未落改动）
var anim_time_scale: float = 1.0  # 动画时长参数化（测试加速用；正常游玩=1.0）
var _anim_tween: Tween
# 聚合段数据（_build_success_overlay 填充，_cloud_progress 消费）。
# N4 等价替换留痕：坐标系从 M-Gb「相对 SpinPivot 像素空间（CLOUD_MODEL_HEIGHT 归一）」改为
# 「结算 fit 口径世界空间」（与结算 viewer 同 sf 同点径，同位续接的数学前提）。
var _cloud_mm: MultiMesh
var _cloud_inst: MultiMeshInstance3D
var _cloud_starts: PackedVector3Array = PackedVector3Array()
var _cloud_targets: PackedVector3Array = PackedVector3Array()
var _cloud_delay: PackedFloat32Array = PackedFloat32Array()  # 逐点聚合延迟（分层聚合）
var _cloud_colors := PackedColorArray()  # 自持逐点色（失配回退淡出用；无头读回恒 0 的读侧依据）
# ---- 批次 N4 四段式运行态 ----
## 四段相位（测试钩子 get_success_seg；spec §6.6 四段：凝聚→持续+散开→聚合→回看）。
## N12b P3-2（审查 A 回修）：HOLD_SPREAD 死枚举删除——声明后从未赋值，「持续+散开」段
## 由 N3 全屏管线相位机承载（_play_success_anim 对该段仅 tween_interval 等待，无独立
## level 侧 seg 值）；编号钉死 0/2/3 保持 test_n4_success_flow 段钩子数值契约不变
## （0 凝聚 / 2 聚合 / 3 回看，等价替换留痕：旧枚举序 CONDENSE=0/HOLD_SPREAD=1）。
enum SuccessSeg { CONDENSE, AGGREGATE = 2, REVIEW = 3 }
var _cloud_vsz := Vector2.ZERO        # 覆盖层视口尺寸（构建时快照，换算基准）
var _spin_pivot: Node3D              # ④回看自转 pivot（独立节点，不与轨道相机共链，坑 9）
var _anim_cam: Camera3D              # 覆盖层相机（N4：透视+结算投影匹配，跟随 pivot 平移）
var _align: Dictionary = {}          # 结算建模参数（read_settle_align 单点读取结果，构建时定格）
var _align_dist := 2.8               # 覆盖层相机视距（=SETTLE_CAMERA_DISTANCE，世界单位）
var _cloud_k := 167.6                # 覆盖层 px/世界单位（=结算挂载投影口径，构建时定格）
var _review_center := Vector3.ZERO   # 聚合中心世界位（=覆盖层世界原点=屏幕中心）
var _mount_world := Vector3.ZERO     # 结算挂载中心世界位（对位平移终点）
var _rev_yaw := 0.0                  # 回看当前 yaw（rad；自转与拖拽共享状态）
var _rev_pitch := 0.0                # 回看当前 pitch（rad；拖拽夹紧）
var _rev_auto := true                # 自动自转缺省；玩家拖拽即接管（本次回看内不自转复位）
var _rev_dragging := false           # 回看拖拽按住中（专用输入通道，不解锁 _input_locked）
var _success_seg: int = -1           # 当前四段相位（SuccessSeg；-1=未开始）
# N4 等价替换留痕：M-Gb 消散撒点/逐体素随机隐藏运行态（_dot_mm/_dot_base/_dot_dir/_dot_dist/
# _dissolve_cells/_dissolved_i）废止——凝聚/散开由 N3 全屏三色管线承载（分组统一，无随机序）。
# P批波2等价替换留痕：_align_started/_align_from/_align_fading（末段对位窗口运行态+失配回退）
# 随对位废止删除——建模保持玩家姿态直入结算，无对位插值、无失配态。
# ---- P批波2（P-D）：结算 UI（覆盖层承载）运行态 ----
var _settle_mode := false            # 边缘路径模式（goto_state(SETTLE) 重建：ctx.settle=true）
var _settle_data := {}               # 结算显示/路由数据（评级/耗时/获得天赋值/replay/chapter）
var _settle_ui: Control = null       # SuccessOverlay/SettleUI 根（_build_settle_ui 创建）
var _settle_cascade: Array = []      # 淡入级联清单：[node, rise] 对（rise=从下往上位移）
var _settle_tween: Tween             # 结算 UI 淡入 tween
var _settle_dragging := false        # 结算页建模拖拽按住中（ModelDragArea 通道）

# ---- 批次 G：锐眼运行态 ----
var _eye_active: bool = false        # 锐眼效果开启中
var _eye_remaining_sec: float = 0.0  # 剩余显示秒数（_process 逐帧倒计，到 0 自动关闭）
var _eye_menu: Control = null        # 时长选择自绘面板（P4：PopupMenu 子视口手势不可达已退役，懒创建）
var _eye_marked: Dictionary = {}     # 当前红色 mark 的 cell 集合：Vector3i → true（恢复用）

# ---- 批次 G：见证者运行态 ----
var _witness_base_pos: Vector2 = Vector2.ZERO   # 浮动基准位（首帧捕获，布局完成后）
var _witness_base_valid: bool = false
var _witness_float_phase: float = 0.0           # 浮动相位（delta×speed 推进）
var _witness_bubble_open: bool = false
# 批次 Y（Y-C8）：台词洗牌袋（剧情对话/气泡_第N关.json）。类型经 const preload 标注
# （全局 class_name 在无头 --script 运行期的类缓存注册不可依赖——实测坑，留痕）。
var _bubble_bag: BubbleBag = null
var _bubble_hover_energy: float = 0.0            # M-D 回修：hover 光晕总幅（0~1 渐入渐出）
var _bubble_glow_rect: ColorRect = null          # M-D 回修：光晕覆盖层（hover_glow 体系，透明读屏加色）
var _bubble_glow_mat: ShaderMaterial = null      # M-D 回修：光晕覆盖层材质
var _bubble_mouse_sim: Vector2 = Vector2.ZERO    # M-D 回修：测试/走查模拟光标（_bubble_mouse_sim_on=false 时用真实光标）
var _bubble_mouse_sim_on: bool = false           # 模拟光标开关（probe 钩子置位，真实运行恒 false）
var _witness_bubble_timer: float = 0.0          # 气泡自动隐藏倒计时
var _bubble_entry_t: float = -1.0               # Z3-6：入场进度秒（≥0=进行中；<0=无入场动画）
var _witness_texture_path: String = ""          # 当前立绘路径（测试/调试用）
var _witness_head_local_y: float = -1.0         # M-D：可见头顶盒内 y（度量未就绪=-1）

# ---- 批次 G：退出确认（重玩=左下 → CATALOG；正常=TopBar → MAIN_MENU）----
# K4-1→批次V（V-C5，spec §3.2）：确认条迁移 Game.confirm → TopStrip 统一确认条（文案逐字保持），
# 动态弹窗实例退役；挂起目标路由语义不变（确认=按挂起目标先落断点再路由，取消=作废挂起）。
var _pending_exit_state: int = -1

func set_context(ctx: Dictionary) -> void:
	_chapter = int(ctx.get("chapter", 1))
	_replay_mode = bool(ctx.get("replay", false))  # 图鉴重玩入口传 replay:true（T24 接入方）
	# P-D⑥边缘路径：Game.goto_state(SETTLE) 特判改载本场景并注入 settle:true（结算显示由
	# 覆盖层承载后，从图鉴等来源退回结算=重建关卡体素+直显结算 UI 与建模，不再路由 settle_scene）。
	_settle_mode = bool(ctx.get("settle", false))
	if _settle_mode:
		_settle_data = ctx.duplicate(true)

func _ready() -> void:
	_start_ms = Time.get_ticks_msec()  # 批次 F：计时范围=进入关卡至对接成功（spec 8.5）
	# I18n：tscn 静态文字经 t() 覆写（三钮/重玩退出钮/两视图标题「最终成品」「对接固定件」；
	# 顶栏计数/标题/提示行由 _load_level/_apply_hud 运行时动态覆写——消费点已接 t()）。
	($TopBar/Buttons/EyeButton as Button).text = I18n.t("锐眼")
	($TopBar/Buttons/JoinButton as Button).text = I18n.t("对接")
	($TopBar/Buttons/FocusButton as Button).text = I18n.t("聚焦")
	($TopBar/Buttons/ExitButton as Button).text = I18n.t("退出")
	exit_replay_btn.text = I18n.t("退出")
	($TargetView/Title as Label).text = I18n.t("最终成品")
	($JoinView/Title as Label).text = I18n.t("对接固定件")
	_apply_background()
	_make_vignette()  # 批次 J（A1）：背景径向渐晕
	_make_materials()
	_load_level()
	_setup_cameras()
	_build_views()
	_apply_hud()
	_apply_witness()
	# 批次 E 键鼠接线：MainView 视口容器接管点击拾取（gui_input 为容器局部坐标）
	var main_cont := get_node_or_null("MainView/ViewportContainer")
	if main_cont is SubViewportContainer:
		(main_cont as SubViewportContainer).gui_input.connect(_on_main_view_gui_input)
	# M-E 回修2 B（用户实测推翻「完全不可交互」拍板，留痕）：Target/Join 侧视图交互恢复——
	# 拖拽=旋转（空白左键/中键任意位置）、滚轮=独立 ortho size 缩放、划选/Ctrl+点击=选区、
	# 单击空白=清空该侧选区（旧「误触多选无法取消」痛点以此出口解决）；悬停点光跟随（追2 D）
	for side_pair: Array in [["TargetView/ViewportContainer", "Target"], ["JoinView/ViewportContainer", "Join"]]:
		var scont := get_node_or_null(String(side_pair[0]))
		if scont is SubViewportContainer:
			(scont as SubViewportContainer).gui_input.connect(_on_side_view_gui_input.bind(String(side_pair[1])))
	# 批次 R（spec §5.1）：三视图注册手势面板组——光标+伸中指激活/切换（手势层专属概念，
	# 键鼠零感知 §14-11）；rect 由 Router 对容器回退 get_global_rect()（容器无 gesture_panel_rect）
	# 附带回修 P2-5：硬 get_node 改 get_node_or_null（与上方 :362 周边卫生口径一致）
	for view_path: String in ["MainView/ViewportContainer", "TargetView/ViewportContainer", "JoinView/ViewportContainer"]:
		var view_cont: Node = get_node_or_null(view_path)
		if view_cont != null:
			view_cont.add_to_group("gesture_panel")
	# 批次 F 接线：对接判定
	join_btn.pressed.connect(_on_join_pressed)
	# 批次 G 接线：锐眼时长菜单 / 退出确认 / 见证者联动
	eye_btn.pressed.connect(_open_eye_menu)
	exit_btn.pressed.connect(_on_exit_pressed)
	# 批次 U（U7-3，spec §4-U7-3）：三钮 HoverTip 接入（键鼠+手势双路径；JoinButton 原生 tooltip
	# 已在 tscn 移除防双提示）。纯展示件不触碰输入路径（红线①）。
	var tip_script: GDScript = load("res://scenes/shared/hover_tip.gd")
	# I18n：tooltip 文案键经 t()。
	for pair: Array in [[$TopBar/Buttons/EyeButton, "锐眼：挖除已选部件的辅助提示"],
			[$TopBar/Buttons/JoinButton, "对接：按标准答案判定对接"],
			[$TopBar/Buttons/FocusButton, "聚焦：放大聚焦单个部件"]]:
		var tip: PanelContainer = tip_script.new()
		add_child(tip)
		tip.setup(pair[0], I18n.t(String(pair[1])))   # I18n：tooltip 文案 t()
	# K-G（K6-7）接线 → N3 重写（spec §6.4/§五 4~5）：聚焦钮 + 全屏三色散点单控制器
	# （CanvasLayer 0=关卡内容同层树序置顶，走查定稿；N12b P3-1 注释漂移回修：旧注释 85
	# 已随 N3 LAYER 定稿 0 修正，体内断言早已锁 0。随关卡场景创建/销毁；三视图各作为一条
	# 颜色通道接入）
	focus_btn.pressed.connect(_toggle_focus)
	focus_btn.disabled = true
	_fx_layer = _make_focus_fx()
	_fx_main = _fx_layer    # N批等价替换：句柄面保留，语义=通道引用（同一全屏控制器）
	_fx_target = _fx_layer
	_fx_join = _fx_layer
	_fx_layer.call("bind_channel", "Main", main_viewport)
	_fx_layer.call("bind_channel", "Target", target_viewport)
	_fx_layer.call("bind_channel", "Join", join_viewport)
	exit_replay_btn.visible = _replay_mode  # 仅图鉴重玩显示左下退出按钮（spec 3.10）
	exit_replay_btn.pressed.connect(_on_exit_replay_pressed)
	for view: String in ["Main", "Target", "Join"]:
		_ensure_hover_light(view)  # M-E 追2/回修2 D：三视图悬停点光预创建（初始熄灭，命中才渐亮）
	# 批次 AD §4.3.5：MainView 锚点收窄至 0.115 避让左下角立绘（与 WitnessPortrait
	# [0.005, 0.11] 不再物理重叠），立绘恢复 MOUSE_FILTER_STOP 并连接 gui_input 点击弹泡。
	witness.mouse_filter = Control.MOUSE_FILTER_STOP
	witness.set_meta("interactive", true)
	if not witness.gui_input.is_connected(_on_witness_gui_input):
		witness.gui_input.connect(_on_witness_gui_input)
	var hint_label_meta := get_node_or_null("HintLabel") as Control
	if hint_label_meta != null:
		hint_label_meta.set_meta("interactive", true)
	_apply_level_bar_theme()  # 批次 W（P1-6）：tscn 静态字色已删，入树首挂字色（批次 AB-3：恒深档）
	witness.resized.connect(_refresh_witness_metrics)  # M-D：盒尺寸变化 → 重算可见头顶度量
	# 批次 Y（Y-C8）：气泡台词洗牌袋——第 N 关读 剧情对话/气泡_第N关.json；缺文件/空池
	# → 袋内池空，_show_witness_bubble 不弹（防御路径自然生效+告警，不崩）。
	_load_witness_lines(BubbleBag.path_for_chapter(_chapter))
	_apply_bubble_theme()  # M-D 回修：气泡背板/字色/材质随主题挂载
	# 批次V（V-C5，spec §3.2）：退出确认动态弹窗实例退役——确认经 Game.confirm → TopStrip
	# 统一确认条（独立层 63，高于关卡场景画布与 FocusFX 散点层，条内容不被遮盖/不可点性
	# 风险随之消除）；N12b P2-1 的「弹窗可见期间散点层避让」随弹窗退役（其存在前提=
	# 场景内同层弹窗，确认条已脱离该层域，无需避让），_on_exit_dialog_visibility_changed
	# 一并退役。确认/取消回调收口到 _ask_exit 调用处（文案逐字保持）。
	# 批次 G 联动：天赋值 HUD 随扣费/发放实时刷新；皮肤切换即时刷新见证者立绘（修批次 D P3）
	SaveManager.talent_changed.connect(_on_talent_changed)
	SaveManager.skin_changed.connect(_on_skin_changed)
	# 回修4 A：窗口适配取景依赖视口布局尺寸——_ready 同帧布局未就绪，挂 size_changed
	# 触发首算（+ deferred 兜底重试）；后续 resize 只按新窗尺寸 clamp 防穿帮（不重置用户档位）
	for vp: SubViewport in [main_viewport, target_viewport, join_viewport]:
		if not vp.size_changed.is_connected(_on_any_viewport_resized):
			vp.size_changed.connect(_on_any_viewport_resized)
	_apply_ortho_sizes.call_deferred()
	# J6-P2-5：渐晕按主题取角部色——批次 AB-3：theme_changed 订阅随深浅主题机制删除退役
	#（渐晕/气泡/标题/结算样式由各 _apply_* 在 _ready/构建时直挂，恒深档）。
	# P-D⑥边缘路径：经 SETTLE 态重建（图鉴等来源退回结算）——布局就绪后直显结算 UI 与建模
	if _settle_mode:
		_enter_settle_direct.call_deferred()

## 批次 W（P1-6）：五处标签（TopBar 四标签+HintLabel）字色应用。tscn 静态米白 override
## 已删（浅色主题不可读缺陷根除）；本方法在 _ready 首挂。批次 AB-3：force 注入缝与浅档
## 随深浅主题机制删除退役——恒深档米白（Palette.TEXT_DARK_LEVELBAR 单源）。
func _apply_level_bar_theme() -> void:
	var col := LEVEL_BAR_FONT_DARK
	for path: String in ["TopBar/TitleLabel", "TopBar/TalentLabel", "TopBar/TimerLabel",
			"TopBar/VoxelLabel", "HintLabel"]:
		var lbl := get_node_or_null(path) as Label
		if lbl != null:
			lbl.add_theme_color_override("font_color", col)

## J6 信号卫生硬化：本场景连接在 autoload（常驻）上的信号，离场时显式断开。
## N9（spec §6.11 写档检查点②）：_exit_tree 兜底落挖除断点（防窗口 X/直接切场景等未走
## 退出确认路径丢档；goto_state 前钩子语义）。_settled 守卫：通关结算路径 _goto_settle 已
## 清该章断点（通关即整章完成，断点作废），此处不得把通关态重写成断点；未动关卡经
## set_level_progress 幂等省写零 I/O（存档无新增数据）。
func _exit_tree() -> void:
	if not _settled:
		_save_level_checkpoint()
	if SaveManager.talent_changed.is_connected(_on_talent_changed):
		SaveManager.talent_changed.disconnect(_on_talent_changed)
	if SaveManager.skin_changed.is_connected(_on_skin_changed):
		SaveManager.skin_changed.disconnect(_on_skin_changed)
	for vp: SubViewport in [main_viewport, target_viewport, join_viewport]:
		if vp != null and vp.size_changed.is_connected(_on_any_viewport_resized):
			vp.size_changed.disconnect(_on_any_viewport_resized)

func _process(delta: float) -> void:
	# 批次 G：见证者浮动/呼吸/气泡自动隐藏（纯装饰，成功动画期间仍正常走）
	_tick_witness(delta)
	_tick_bubble_hover(delta)  # M-D 回修：气泡 hover 光晕能量每帧推进
	_tick_hover_light(delta)   # M-E 追2：悬停点光能量渐入渐出（只动 light_energy，坑 9 安全）
	# N11（批次 W 规格 §3，拍板 3）：关卡进度实时自动存档——改动后 2s 无新改动即落检查点
	# （防抖；时间戳比较非 Timer 节点）。通关/结算态由 flush_checkpoint 的 _settled 守卫拦截；
	# 未来版本只读锁（W1 P0-8）下 set_level_progress→save_game 早退静默零写盘零警告刷屏。
	if _checkpoint_debounce_due():
		flush_checkpoint()
	# K4-2（批次 K）：FailToast 短暂停留计时已随组件迁移删除（Game.toast 自动消退）
	# 批次 G：锐眼剩余时长倒计时，到 0 自动关闭（恢复 mark 与 ghost）
	if _eye_active:
		_eye_remaining_sec -= delta
		if _eye_remaining_sec <= 0.0:
			_finish_eye()
	if _success_started:
		return
	# 计时 mm:ss（成功后停表，保持最终耗时展示）
	timer_label.text = format_time((Time.get_ticks_msec() - _start_ms) / 1000.0)

## Game 路由约定：set_context 先于 add_child；数据在 _ready 消费。
func _load_level() -> void:
	var lvl: Dictionary = LevelLibrary.get_level(_chapter)
	if lvl.is_empty():
		# 兜底：库未扫描（如测试直启场景）时重扫一次再取（正常流程 main.gd 已扫描）
		LevelLibrary.scan_directory("res://levels_data")
		lvl = LevelLibrary.get_level(_chapter)
	if lvl.is_empty():
		push_warning("关卡数据缺失: chapter=%d（显示空场占位）" % _chapter)
		return
	_level = lvl

func _make_materials() -> void:
	# 批次 J（A3）：程序化木纹（不引外部素材），浅木/深木各一份
	_mat_light = _make_wood_material(WOOD_LIGHT)
	_mat_dark = _make_wood_material(WOOD_DARK)

## 程序化木纹材质（批次 J/A3）：FastNoiseLite（SIMPLEX，frequency≈0.08）→ NoiseTexture2D
## 作 albedo，albedo_color 乘 §0.5 木色基色；uv1_scale 压扁 y 向制造横向木纹条纹；
## roughness 0.55（K6-2 批次 K 由 0.7 调低增层次感）、无金属度。
## gl_compatibility 下 StandardMaterial3D+DirectionalLight3D 正常。
func _make_wood_material(base_color: Color) -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.08
	var tex := NoiseTexture2D.new()  # tex.seamless 内部处理无缝（FastNoiseLite 无 seamless 属性）
	tex.noise = noise
	tex.width = 128
	tex.height = 128
	tex.seamless = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = base_color
	mat.albedo_texture = tex
	mat.roughness = 0.55  # K-G（K6-2，spec §10.2）：0.7→0.55 木纹层次感
	mat.metallic = 0.0
	mat.uv1_scale = Vector3(1.0, 0.15, 1.0)  # 横向拉伸噪声 → 木纹方向感
	return mat

func _setup_cameras() -> void:
	# M-E（spec §3.5）：三视图正交等轴测相机——距离固定 ORTHO_DIST、near/far 定值、
	# 投影 PROJECTION_ORTHOGONAL（tscn 已声明，此处兜底显式化）。ortho size 在
	# _build_views 按各视图包围球直径设定（_apply_ortho_sizes）。
	# ⚠ 仅允许在输入回调（拖拽/滚轮）与初始化/构建路径调用更新函数，
	# 严禁 _process 每帧刷新（spec §六坑 9：成功动画 tween 依赖位姿不被覆写）。
	_update_main_camera()
	_update_side_camera("Target")
	_update_side_camera("Join")
	for vp: SubViewport in [main_viewport, target_viewport, join_viewport]:
		var light: DirectionalLight3D = vp.get_node_or_null("Light")
		if light == null:
			light = DirectionalLight3D.new()
			light.name = "Light"
			vp.add_child(light)
			light.rotation_degrees = Vector3(-50, -30, 0)
			light.light_energy = 1.2

func _build_views() -> void:
	if _level.is_empty():
		return
	var pieces: Array = (_level["data"] as Dictionary).get("pieces", [])
	if pieces.is_empty():
		return
	var piece: Dictionary = pieces[0]
	var bs_v: Dictionary = piece.get("block_size", {})
	var bs := Vector3i(int(bs_v.get("x", 1)), int(bs_v.get("y", 1)), int(bs_v.get("z", 1)))
	# 批次 V（规格 §9.5）：三视图各传各域尺寸——批次 Z Z1（spec §1，用户拍板三者同改）起
	# 左上「最终成品」对照面板改渲染 final=final_answer.size 回落 bs、右上 join=join_part.size
	# 回落 bs（_domain_size 缺字典/缺轴逐轴回落 block_size，与 level_library 按域净化/编辑器
	# get_size_for_tag 回落链同口径）；主视口恒 blocks=block_size。**标准答案 target 关卡内零
	# 渲染**（只用于对接判定与锐眼差集——_target_size 仍锚 target 域，判定/差集口径不动，
	# 与左上渲染换源解耦）；_voxel_size 仍锚 blocks 域（挖除/拾取现状不变）；
	# 对接判定按格坐标不变（evaluate_join 零改动）。
	var ts := _domain_size(piece, "target_size", bs)
	var fs := _domain_size(piece, "final_answer", bs)
	var js := _domain_size(piece, "join_part", bs)
	_view_sizes = {"Target": fs, "Join": js}   # 侧视拾取按域（_raycast_side_at 消费；Z1：Target=final 域，与渲染同源）
	_target_size = ts   # 批次 W（P2-8）：target 域尺寸缓存（锐眼差集过滤域——判定侧口径，Z1 渲染换源后仍锚 target 域）
	var main_vv: Node = main_viewport.get_node_or_null("VoxelView")
	var target_vv: Node = target_viewport.get_node_or_null("VoxelView")
	var join_vv: Node = join_viewport.get_node_or_null("VoxelView")
	if main_vv != null:
		main_vv.call("build_voxels", piece.get("blocks", []), bs, _mat_light)
		# 批次 E：以实际构建成功的格子初始化剩余集，并锁定拾取几何（与渲染同中心）
		_remaining.clear()
		for c: Variant in (main_vv.call("get_built_cells") as Array):
			_remaining[Vector3i(c)] = true
		_initial_total = _remaining.size()
		# N9：初始全集快照（差集导出基准 deleted_cells=blocks−_remaining；构建后不变）
		_initial_cells = _remaining.duplicate()
		_voxel_size = bs
		_voxel_center = main_vv.call("get_center_offset")
	if not (piece.get("target_shapes", []) as Array).is_empty():
		_target_shape0 = (piece["target_shapes"] as Array)[0]  # 批次 G：锐眼差集基准（Z1 保留：判定/差集依赖，不进渲染）
	if target_vv != null:
		# 批次 Z Z1：左上渲染 final_answer（对接完成形态，仅供参照）；target 只留判定，关卡内零渲染。
		target_vv.call("build_voxels", (piece.get("final_answer", {}) as Dictionary).get("voxels", []), fs, _mat_light)
	if join_vv != null:
		join_vv.call("build_voxels", (piece.get("join_part", {}) as Dictionary).get("voxels", []), js, _mat_dark)
	_apply_ortho_sizes()  # M-E：缓存各视图包围/直径（size0 由窗口适配 _fit_all_sizes 延迟设定）
	_replay_saved_progress()  # N9：进关重放存档挖除断点（spec §6.11，主菜单/图鉴各入口同路）

## N9 重放钩子（spec §6.11）：进关 _build_views 后若存档记有该章挖除断点（非空 deleted_cells），
## 经既有删除管线（select_voxel 逐格并入选区 → delete_selected）重放删除——渲染 hide 与
## _remaining/顶栏计数同步一致（与玩家手挖同一管线，数据一致性由管线保证）。
## 撤销栈红线定稿（spec §九 14）：重放后 _undo_stack/_redo_stack 一律清空——存档断点即「进关
## 基线」，玩家撤销历史不跨会话保留；基线以下的回退无入口（undo 返回 false），故重放后的
## 撤销不可能把状态回退到与存档矛盾（test_n9_save_progress N9-E3/E4 锁定）。
## 会话内新挖/撤销只相对基线起效：撤销最多回到基线（=存档态），再退无门。
## 脏数据防御：只重放初始全集内的格（存档外坐标跳过）；重放格已在基线外（理论不可能）天然幂等。
func _replay_saved_progress() -> void:
	_undo_stack.clear()
	_redo_stack.clear()
	if _initial_cells.is_empty():
		return
	var saved: Array = SaveManager.get_level_progress(_chapter)
	if (saved as Array).is_empty():
		return
	var picked: Array = []
	for s_v: Variant in saved:
		var cell := cell_v_to_i(s_v)
		if _initial_cells.has(cell):  # 只重放初始全集内的格（存档外/非法坐标跳过，脏数据防御）
			picked.append(cell)
	if (picked as Array).is_empty():
		return
	for cell: Vector3i in picked:
		select_voxel(cell, true)   # additive 逐格并入选区（picked 去重无 toggle 回退）
	delete_selected()              # 既有删除管线：_remaining 移出+渲染隐藏+计数刷新（不入栈路径同款）
	_undo_stack.clear()            # 重放步不入撤销栈（红线：基线以下回退无入口）
	_redo_stack.clear()

## N9 断点导出（spec §6.11）：deleted_cells = 初始 blocks − 当前 _remaining（只存删了哪些格）。
## 没动 = 空数组（「没改」天然表达）；统一 "x,y,z" 字符串、去重、字典序排序（确定性落盘）。
func _export_deleted_cells() -> Array:
	var out: Array = []
	for cell_v: Variant in _initial_cells.keys():
		if not _remaining.has(cell_v):
			var c: Vector3i = cell_v
			out.append("%d,%d,%d" % [c.x, c.y, c.z])
	(out as Array).sort()
	return out

## N9 写档检查点（spec §6.11）：关卡离场路径先落挖除断点再路由。未动（差集空）且存档本无
## 该章断点 → set_level_progress 幂等省写零 I/O；挖了又全撤销 → 清除既有断点（没改语义）。
func _save_level_checkpoint() -> void:
	SaveManager.set_level_progress(_chapter, _export_deleted_cells())

## N11 防抖判定缝（批次 W 规格 §3；无头直测不依赖真实等待）：有脏且距最后一次改动
## ≥ CHECKPOINT_DEBOUNCE_MS（2000ms）。now_ms<0 取真实时钟（_process 路径），测试注入推进。
## 哨兵判据用 == -1 而非 < 0（bridge R-B-1 第 10 段同款实证坑）：测试注入「now-2500」类
## 「N 秒前」时间戳在进程启动 2.5s 内为合法负值，< 0 会把它误判为未设置哨兵（-1 才是哨兵）。
func _checkpoint_debounce_due(now_ms: int = -1) -> bool:
	if _checkpoint_dirty_at == -1:
		return false
	var now: int = Time.get_ticks_msec() if now_ms < 0 else now_ms
	return now - _checkpoint_dirty_at >= CHECKPOINT_DEBOUNCE_MS

## N11/P2-12b 显式落盘缝（公开）：立即落一次挖除断点——退出确认/窗口×（main._quit_now_shared
## 经 Game 取本场景调用）与 _process 防抖到点共用。幂等省写（未动关卡零 I/O）；_settled 守卫
## 防把通关态重写成断点（_exit_tree 兜底同语义）；落盘即清脏（防同帧二次触发）。
func flush_checkpoint() -> void:
	if _settled:
		return
	_checkpoint_dirty_at = -1
	_save_level_checkpoint()

## M-E（spec §3.5 目标行为 1/7）+ 回修4 A：缓存各视图实际构建格集的包围球直径/AABB
## 世界尺寸/拾取几何中心；初始取景 size0 由 _fit_all_sizes 按「窗口尺寸×块投影包围盒」
## 计算（固定直径倍数口径废止——直径倍数与窗口无关，宽扁窗下初始块过小致疯狂放大穿帮）。
func _apply_ortho_sizes() -> void:
	_main_diameter = _cells_sphere_diameter(_remaining.keys())
	_view_centers["Main"] = _voxel_center  # 追2/回修2 D：主视图拾取几何中心
	var tvv: Node = target_viewport.get_node_or_null("VoxelView")
	var jvv: Node = join_viewport.get_node_or_null("VoxelView")
	var t_cells: Array = tvv.call("get_built_cells") if tvv != null else []
	var j_cells: Array = jvv.call("get_built_cells") if jvv != null else []
	_side_diameters["Target"] = _cells_sphere_diameter(t_cells)
	_side_diameters["Join"] = _cells_sphere_diameter(j_cells)
	_view_centers["Target"] = tvv.call("get_center_offset") if tvv != null else Vector3.ZERO
	_view_centers["Join"] = jvv.call("get_center_offset") if jvv != null else Vector3.ZERO
	_view_cells["Target"] = t_cells
	_view_cells["Join"] = j_cells
	_view_aabb_size["Main"] = _aabb_size_of_cells(_remaining.keys())
	_view_aabb_size["Target"] = _aabb_size_of_cells(t_cells)
	_view_aabb_size["Join"] = _aabb_size_of_cells(j_cells)
	_fit_all_sizes()

var _fit_deferred_pending := false

## 回修4 A：初始取景设定——主视图=块投影宽占窗宽 MAIN_FILL_W0、侧=SIDE_FILL_W0，
## 与「垂直方向完整（四周留边 ≥VIEW_FIT_MARGIN）」取 max（宽扁窗下垂直先撑满=
## 「尽可能把块放到最大」的正确诠释）。视口未布局（<1px）→ 帧末 deferred 重试一次
## （size_changed 双保险覆盖更晚布局）。
func _fit_all_sizes() -> void:
	if _main_diameter <= 0.0 and float(_side_diameters.get("Target", 0.0)) <= 0.0:
		return  # 空场占位（无块）→ 无取景可算
	if main_viewport.size.y < 1.0 or target_viewport.size.y < 1.0:
		if not _fit_deferred_pending:
			_fit_deferred_pending = true
			_fit_all_sizes.call_deferred()
		return
	_fit_deferred_pending = false
	_ortho_size_main = _ortho_size_fit("Main", _orbit_yaw, _orbit_pitch, MAIN_FILL_W0)
	_ortho_size_side["Target"] = _ortho_size_fit(
		"Target", deg_to_rad(SIDE_YAW0_DEG), deg_to_rad(SIDE_PITCH0_DEG), SIDE_FILL_W0)
	_ortho_size_side["Join"] = _ortho_size_fit(
		"Join", deg_to_rad(SIDE_YAW0_DEG), deg_to_rad(SIDE_PITCH0_DEG), SIDE_FILL_W0)
	_update_main_camera()
	_update_side_camera("Target")
	_update_side_camera("Join")

## 回修4 A：视口尺寸变化——取景未算（布局刚就绪）→ 补算初始取景；已算 → 仅按新窗
## 尺寸 clamp 防穿帮（不重置用户当前档位）。只动 size 不动相机位姿（坑 9 纪律；
## 成功动画期间 _input_locked 已 guard）。
func _on_any_viewport_resized() -> void:
	if _input_locked:
		return
	if _ortho_size_main <= 0.0 or float(_ortho_size_side.get("Target", 0.0)) <= 0.0 \
			or float(_ortho_size_side.get("Join", 0.0)) <= 0.0:
		_fit_all_sizes()
		return
	_clamp_ortho_size("Main")
	_clamp_ortho_size("Target")
	_clamp_ortho_size("Join")

## 回修4 A：把 view 当前取景抬到 ≥ 动态下限（旋转/resize 保底；只改 size，
## 位姿由调用方路径负责）。size 未初始化（0）时跳过。
## N批：旋转缩放解耦——下限已改为任意朝向统一值，resize 路径语义不变。
func _clamp_ortho_size(view: String) -> void:
	if view != "Main" and not _ortho_size_side.has(view):
		return
	var cur: float = _ortho_size_main if view == "Main" else float(_ortho_size_side[view])
	if cur <= 0.0:
		return
	var d := _main_diameter if view == "Main" else _side_diameter(view)
	if d <= 0.0:
		return
	var yaw: float = _orbit_yaw if view == "Main" else float(_side_yaw[view])
	var pitch: float = _orbit_pitch if view == "Main" else float(_side_pitch[view])
	var clamped := clampf(cur, _ortho_size_min_for(view, yaw, pitch), d * ORTHO_SIZE_MAX_MUL)
	if is_equal_approx(clamped, cur):
		return
	if view == "Main":
		_ortho_size_main = clamped
	else:
		_ortho_size_side[view] = clamped
	var cam := _viewport_of(view).get_node_or_null("Camera3D") as Camera3D
	if cam != null:
		cam.size = clamped  # 只写 size，不动 position/look_at（坑 9：动画 tween 位姿安全）

## 回修4 A：动态下限（不穿帮）——KEEP_HEIGHT 口径下 ortho size 须满足块投影完整落在
## 窗口内且四周留边 ≥VIEW_FIT_MARGIN：
##   水平：size×(vp.x/vp.y)×(vp.x−2m)/vp.x ≥ span.x → size ≥ span.x×vp.y/(vp.x−2m)
##   垂直：size×(vp.y−2m)/vp.y ≥ span.y → size ≥ span.y×vp.y/(vp.y−2m)
## N批：旋转缩放解耦（用户 2026-09-09 追加 bug：旋转木块时 ortho size 被当前朝向下限实时
## 顶大 → 视野变大 → 木块视觉缩小）。下限跨度从「当前朝向投影」改为「任意朝向最坏投影」
## 的统一值：正交投影下块 AABB 沿任意屏幕轴的跨度 ≤ 包围球直径（Cauchy-Schwarz：
## a|u_x|+b|u_y|+c|u_z| ≤ |(a,b,c)|，且任意屏幕轴方向都存在与之垂直的视向），故以包围球
## 直径作水平/垂直双向保守跨度，得到与 yaw/pitch 无关的统一下限——旋转全程 ortho size
## 恒定零跳变。yaw/pitch 参数保留（调用面兼容+测试断言两朝向同值），实现不再消费。
## 视口未布局/无块返回 0（调用方以 >0 判定是否参与 clamp）。
func _ortho_size_min_for(view: String, yaw: float, pitch: float) -> float:
	var aabb_v: Variant = _view_aabb_size.get(view, Vector3.ZERO)
	var aabb: Vector3 = aabb_v if aabb_v is Vector3 else Vector3.ZERO
	if aabb.x <= 0.0:
		return 0.0
	var vs := Vector2(_viewport_of(view).size)
	if vs.y < 1.0:
		return 0.0
	var span := Vector2(aabb.length(), aabb.length())  # N批：旋转缩放解耦（包围球统一口径）
	return maxf(span.x * vs.y / maxf(vs.x - 2.0 * VIEW_FIT_MARGIN, 1.0),
		span.y * vs.y / maxf(vs.y - 2.0 * VIEW_FIT_MARGIN, 1.0))

## 回修4 A：初始取景 = max(块投影宽占窗宽目标 fill_w，垂直完整约束)。
## N批：旋转缩放解耦——初始取景同步改统一口径（跨度=包围球直径），保证任意朝向完整可见；
## 初始视野较旧「当前朝向适配」略保守，N2 窗口极致扩大已补偿放大体验。
func _ortho_size_fit(view: String, yaw: float, pitch: float, fill_w: float) -> float:
	var aabb_v: Variant = _view_aabb_size.get(view, Vector3.ZERO)
	var aabb: Vector3 = aabb_v if aabb_v is Vector3 else Vector3.ZERO
	if aabb.x <= 0.0:
		return 0.0
	var vs := Vector2(_viewport_of(view).size)
	if vs.y < 1.0 or vs.x < 1.0:
		return 0.0
	var span := Vector2(aabb.length(), aabb.length())  # N批：旋转缩放解耦（包围球统一口径）
	var by_w := span.x / maxf(fill_w * (vs.x / vs.y), 0.0001)
	var by_h := span.y * vs.y / maxf(vs.y - 2.0 * VIEW_FIT_MARGIN, 1.0)
	return maxf(by_w, by_h)

## 格集 AABB 世界尺寸（体素占 [p,p+1]，1 格=1 单位；空集返回 ZERO）。
static func _aabb_size_of_cells(cells: Array) -> Vector3:
	var mn := Vector3i(1 << 29, 1 << 29, 1 << 29)
	var mx := Vector3i(-(1 << 29), -(1 << 29), -(1 << 29))
	for c: Variant in cells:
		var p := Vector3i(c)
		mn.x = mini(mn.x, p.x); mn.y = mini(mn.y, p.y); mn.z = mini(mn.z, p.z)
		mx.x = maxi(mx.x, p.x); mx.y = maxi(mx.y, p.y); mx.z = maxi(mx.z, p.z)
	if mx.x < 0:
		return Vector3.ZERO
	return Vector3(mx - mn + Vector3i.ONE)

## 块 AABB 在给定朝向下的屏幕投影跨度（世界单位；|·| 保证任意象限保守正确）：
## 水平=x|cos yaw|+z|sin yaw|；垂直=(x|sin yaw|+z|cos yaw|)|sin pitch|+y|cos pitch|。
## N批：旋转缩放解耦后实现内不再消费（留作朝向投影对照与测试同式互验基准）。
static func _proj_span_at(aabb: Vector3, yaw: float, pitch: float) -> Vector2:
	return Vector2(
		aabb.x * absf(cos(yaw)) + aabb.z * absf(sin(yaw)),
		(aabb.x * absf(sin(yaw)) + aabb.z * absf(cos(yaw))) * absf(sin(pitch)) + aabb.y * absf(cos(pitch)))

## view 名 → SubViewport（Main/Target/Join）。
func _viewport_of(view: String) -> SubViewport:
	return main_viewport if view == "Main" else (target_viewport if view == "Target" else join_viewport)

## cells 包围盒对角线长度（包围球直径；空集返回 0——调用方以 >0 判定是否应用 size）。
static func _cells_sphere_diameter(cells: Array) -> float:
	var mn := Vector3i(1 << 29, 1 << 29, 1 << 29)
	var mx := Vector3i(-(1 << 29), -(1 << 29), -(1 << 29))
	for c: Variant in cells:
		var p := Vector3i(c)
		mn.x = mini(mn.x, p.x); mn.y = mini(mn.y, p.y); mn.z = mini(mn.z, p.z)
		mx.x = maxi(mx.x, p.x); mx.y = maxi(mx.y, p.y); mx.z = maxi(mx.z, p.z)
	if mx.x < 0:
		return 0.0
	return Vector3(mx - mn + Vector3i.ONE).length()

func _apply_hud() -> void:
	# P3-7（审查缺陷）：validate_level 不校验 title 类型——`String(可能为 null/数组)` 属 4.7
	# 运行期中止族（Nonexistent 'String' constructor）；非字符串一律回退缺省「第%d关」
	# （与旧「键缺失默认」逐字节同口径）。
	var title_v: Variant = _level.get("title", null)
	var title: String = title_v if typeof(title_v) == TYPE_STRING else (I18n.t("第%d关") % _chapter)
	title_label.text = I18n.t("第%d关 %s") % [_chapter, I18n.t(title)]   # I18n：模板键+标题键双层
	talent_label.text = I18n.t("天赋值：%d") % SaveManager.get_talent()
	timer_label.text = "00:00"  # 批次 F 接真计时
	_update_hint()
	_update_voxel_label()  # M-E：顶栏计数初值（192 / 192）
	_apply_title_theme()   # M-E⑤：三面板标签字色/描边随主题刷新（tscn 缺省深色档）

func _apply_background() -> void:
	# 章节背景（LevelLibrary 映射），缺失回退第 1 关背景，再缺失隐藏露主题底色
	var path: String = LevelLibrary.get_background_path(_chapter)
	if not ResourceLoader.exists(path):
		path = DEFAULT_BG
	if ResourceLoader.exists(path):
		background.texture = load(path)
	else:
		background.visible = false

## 批次 J（A1）：径向渐晕纹理挂 Vignette 层——中心全透明露出背景、四边向角部渐暗。
## 深色角部黑 alpha 0.55（§0.5 色板总表；批次 AB-3：浅色暖褐角部随主题机制删除退役，恒深档）。
## 仅压暗观感，mouse_filter=IGNORE 不吃任何输入（tscn 已设，此处不改）。
func _make_vignette() -> void:
	var vg := get_node_or_null("Vignette") as TextureRect
	if vg == null:
		return
	var grad := Gradient.new()  # 默认 2 锚点：offset 0 / 1
	grad.set_color(0, Color(0, 0, 0, 0))  # 中心：全透明
	grad.set_color(1, Color(0.0, 0.0, 0.0, 0.55))  # 边缘/四角：压暗
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL  # 径向填充
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 256
	vg.texture = tex

func _apply_witness() -> void:
	# 古今见证者立绘：当前穿戴皮肤 → 缺省立绘（批次 G：随 skin_changed 实时刷新）
	var equipped: String = String(SaveManager.get_skins().get("equipped", "skin_default"))
	var tex_path: String = ""
	if equipped != "skin_default":
		var skin: Dictionary = SkinCatalog.get_skin(equipped)
		tex_path = String(skin.get("texture", ""))
	if tex_path.is_empty() or not ResourceLoader.exists(tex_path):
		tex_path = DEFAULT_WITNESS
	_witness_texture_path = tex_path
	witness.texture = load(tex_path) if ResourceLoader.exists(tex_path) else null
	# M-D：可见头顶度量延后至布局稳定（_ready 首次调用时 witness 盒尺寸未排布）
	_refresh_witness_metrics.call_deferred()

## M-D（spec §3.4 目标行为 3）：按 witness 纹理 used_rect 度量「可见头顶」盒内 y
## （纹理顶部透明边不再计入——气泡贴头以可见像素为准）。
func _refresh_witness_metrics() -> void:
	var m: Dictionary = PM.measure(_witness_texture_path)
	if witness.texture == null or not bool(m.get("valid", false)) or witness.size.y <= 1.0:
		_witness_head_local_y = -1.0  # 度量未就绪（布局未排布/纹理缺失），气泡维持 tscn 缺省位
		return
	var f: Dictionary = PM.fit_in_box(m["size"], m["rect_px"], witness.size)
	_witness_head_local_y = float(f["head_local_y"])

## M-D：可见头顶全局 y（含当前浮动位移与呼吸缩放——pivot (0,0) 左上缩放线性传递）；
## 度量未就绪返回 -1（调用方跳过同步）。
func _witness_visible_top_global() -> float:
	if _witness_head_local_y < 0.0:
		return -1.0
	return witness.global_position.y + _witness_head_local_y * witness.scale.y

## M-D：气泡 y 同步——气泡全局底贴「可见头顶 − WITNESS_BUBBLE_GAP(4px)」。挂 witness
## 同一 tick 更新（_tick_witness 调用），浮动/呼吸位移被同步覆盖 → 振幅内恒贴 4px 不穿头
## （「叠加 WITNESS_FLOAT_AMP 余量防穿头」以同 tick 同步方式落位，无需额外静态偏移）。
func _sync_bubble_y() -> void:
	var top_g: float = _witness_visible_top_global()
	if top_g < 0.0 or witness_bubble.size.y <= 0.0:
		return
	witness_bubble.position.y = top_g - WITNESS_BUBBLE_GAP - witness_bubble.size.y

## ==================== M-D 回修（用户验收 2026-09-08）：气泡背板/文案/hover 光晕 ====================

## 气泡主题样式：半透明背板（0.75，同对话背板口径；批次 AB-3 恒深档）+ 圆角 12（UI 卡片语言）
## + 米白字色 + 字号 18 + 文字贴盒底（visual 文字底距头顶 = GAP4+margin6=10≤15）。
## 投影置 0：外投影由 ui_material 面板档承担（L-A「StyleBox shadow 已置 0」契约）。
func _apply_bubble_theme() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BUBBLE_BG_DARK
	sb.set_corner_radius_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.0)
	sb.shadow_size = 0
	sb.shadow_offset = Vector2.ZERO
	sb.content_margin_left = BUBBLE_MARGIN_H
	sb.content_margin_right = BUBBLE_MARGIN_H
	sb.content_margin_top = BUBBLE_MARGIN_TOP
	sb.content_margin_bottom = BUBBLE_MARGIN_BOTTOM
	witness_bubble.add_theme_stylebox_override("normal", sb)
	witness_bubble.add_theme_color_override("font_color", BUBBLE_FONT_DARK)
	witness_bubble.add_theme_font_size_override("font_size", BUBBLE_FONT_SIZE)
	# M-D 回修2 F（用户反馈「贴底看着非常奇怪」）：文字改回盒内垂直居中 + 盒高紧凑化
	# （tscn 盒高 64.8→40，单行文案时盒小、居中后文字自然贴近头顶；盒底贴头顶−4 不变）
	witness_bubble.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 批次 Y（Y-C8）表现适配：台词池=Y4 正式/占位句（远超旧 20 字试写约束）——
	# 自适应换行 + 高度随内容增长（短句仍 40 固定档；长句盒体向上长高，盒底贴头顶−4 不变，
	# _sync_bubble_y 消费动态 size.y；hover 光晕 rect 同步动态框）。
	witness_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	witness_bubble.set("fit_content", true)  # 动态 set（4.7 Label 有此属性；防版本漂移运行时静默）
	_ensure_bubble_glow_layer()
	# 光晕色（main.gd _apply_glow_color 同对值：金白；批次 AB-3：恒深档）
	if _bubble_glow_mat != null:
		_bubble_glow_mat.set_shader_parameter("u_glow_color", Vector3(1.0, 0.95, 0.8))

## 气泡 hover 光晕：**hover_glow 覆盖层**（M-C 体系复用：透明 ColorRect 挂 hover_glow.gdshader
## 读屏加色，u_glow_k=0.16/u_glow_radius_btn=85 即 M-C 定档默认值，字面口径「加色 0.16/半径
## 85」）。⚠️ 实证坑（本批走查发现）：ui_material 面板档**不可挂 Label**——Label 文字走 TEXT
## 绘制命令，其 UV 是字体图集坐标而非控件矩形 UV，ui_material 的 SDF 几何按矩形 UV 判定会把
## 字形像素错判为「矩形外」→ 渲染成外投影黑块/被裁剪（首拍文字呈暗色块，T11 4x 实证）。
## 故气泡背板=纯 StyleBoxFlat（无 shader），光晕=独立透明覆盖层（只读 screen_tex 加色，
## 不触碰气泡自身绘制，文字无损）。覆盖层 mouse_filter=IGNORE 不挡射线拾取/手势 HUD；
## hover 热区由 witness 立绘矩形代理（气泡 IGNORE 收不到鼠标；每帧全局光标判定——witness
## 浮动/呼吸矩形每帧变化，enter/exit 信号会抖动；talk_controller 同模式）。
func _ensure_bubble_glow_layer() -> void:
	if _bubble_glow_rect != null:
		return
	var cr := ColorRect.new()
	cr.name = "WitnessBubbleGlow"
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cr.color = Color(0, 0, 0, 0)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/hover_glow.gdshader")
	# 半径/加色显式化（与 shader M-C 定档默认同值：u_glow_radius_btn=85 / u_glow_k=0.16，
	# 字面口径「加色 0.16/半径 85」；显式 set 兼供测试读回断言与走查调档单点）
	mat.set_shader_parameter("u_glow_k", 0.16)
	mat.set_shader_parameter("u_glow_radius_btn", 85.0)
	mat.set_shader_parameter("u_glow_color", Vector3(1.0, 0.95, 0.8))
	mat.set_shader_parameter("u_rect_count", 1)
	mat.set_shader_parameter("u_rects", [Vector4.ZERO])
	mat.set_shader_parameter("u_rect_strength", [1.0])
	mat.set_shader_parameter("u_mask_type", [0])
	mat.set_shader_parameter("u_ellipses", [Vector4.ZERO])
	mat.set_shader_parameter("u_strength", 0.0)  # 非悬停恒 0（高光不出现）
	cr.material = mat
	_bubble_glow_mat = mat
	add_child(cr)  # 根 Control 后 add → 绘制序最上（覆盖层语义）
	_bubble_glow_rect = cr

## hover 光晕 tick：光标在 witness 全局 rect（浮动/呼吸实时态）内且气泡可见 → 总幅渐入至 1
##（加色峰值 0.16 = M-C 档），否则渐出至 0（非悬停不出现）。覆盖层 rect 同步气泡矩形外扩
## BUBBLE_GLOW_EXPAND（容纳掩码 12px 渐隐）；u_mouse_px 与 main.gd 同口径（screen_transform
## × 视口鼠标；模拟态用 probe 值）。
## 窗口缩放坐标修复1c（2026-09-18）：命中判定统一 content 口径——witness.get_global_rect()
## 系 content 系 rect，旧实现把设备系鼠标（get_screen_transform×content，s≠1 失配）直接喂
## has_point；现拆双轨：命中判定走 content（bubble_hover_hit 纯函数），u_mouse_px 仍设备系
## （hover_glow 族不动，device_from_content 纯函数换算）。
static func bubble_hover_hit(witness_rect: Rect2, mouse_content: Vector2, bubble_visible: bool) -> bool:
	## content 系命中判定纯函数（无头可测，test_fix_window_scale 段6）
	return bubble_visible and witness_rect.has_point(mouse_content)

func _tick_bubble_hover(delta: float) -> void:
	if witness_bubble == null or witness == null:
		return
	var vp := get_viewport()
	var mouse_content: Vector2
	if _bubble_mouse_sim_on:
		mouse_content = _bubble_mouse_sim   # 模拟态（probe 值=content 口径，与命中判定同系）
	elif vp != null:
		mouse_content = vp.get_mouse_position()
	else:
		return
	var on: bool = bubble_hover_hit(witness.get_global_rect(), mouse_content, witness_bubble.visible)
	_bubble_hover_energy = move_toward(_bubble_hover_energy, BUBBLE_HOVER_ENERGY if on else 0.0, delta * BUBBLE_HOVER_SPEED)
	if _bubble_glow_mat == null or _bubble_glow_rect == null:
		return
	var br := witness_bubble.get_global_rect()
	var glow_r := br.grow(BUBBLE_GLOW_EXPAND)
	_bubble_glow_rect.position = glow_r.position
	_bubble_glow_rect.size = glow_r.size
	_bubble_glow_rect.visible = witness_bubble.visible and _bubble_hover_energy > 0.001
	var mat := _bubble_glow_mat
	mat.set_shader_parameter("u_strength", _bubble_hover_energy)
	# u_mouse_px 保持 hover_glow 设备系（与 FRAGCOORD 同系；content→device 经纯函数换算）
	var mouse_px: Vector2 = mouse_content
	if vp != null:
		mouse_px = CoordSpace.device_from_content(mouse_content, vp.get_screen_transform())
	mat.set_shader_parameter("u_mouse_px", mouse_px)
	# hover_glow 修复批（2026-09-18 追加，第三处供给点）：气泡矩形 br 系 content——
	# u_rects 消费端 FRAGCOORD 是设备像素，改经 rect 纯函数换设备系（与 window_manager._push
	# 同源口径）；覆盖层 glow_r 本身是 content 系 ColorRect（渲染自乘 s），掩码矩形与其视觉
	# 覆盖域在设备空间重合。
	if vp != null:
		var br_dev: Rect2 = CoordSpace.rect_device_from_content(br, vp.get_screen_transform())
		mat.set_shader_parameter("u_rects", [Vector4(br_dev.position.x, br_dev.position.y,
			br_dev.size.x, br_dev.size.y)])
	else:
		mat.set_shader_parameter("u_rects", [Vector4(br.position.x, br.position.y, br.size.x, br.size.y)])

## 测试/走查钩子：模拟光标位置并推进一拍（与 _tick_bubble_hover 真实链路同一变量同一路径）。
## probe 值口径=content（命中判定系；u_mouse_px 无头 identity 下与旧值逐位一致，窗口态为
## 同值×s 的等价换算）。
func _bubble_hover_probe(mouse_content: Vector2, delta: float = 0.2) -> void:
	_bubble_mouse_sim = mouse_content
	_bubble_mouse_sim_on = true
	_tick_bubble_hover(delta)

# ==================== M-E⑤（spec §3.5 目标行为 5）：三面板标签 ====================
# 标签已移到视口容器正下方（tscn 锚定面板底边居中）、文案精简、字号 16、描边 2（tscn 静态）；
# 字色=米白 α0.82 柔和描边（批次 AB-3：浅档随主题机制删除退役，恒深档）。
const TITLE_FONT_DARK := Palette.TEXT_DARK_TITLE
const TITLE_FONT_SIZE := 16
const TITLE_OUTLINE := 2

func _apply_title_theme() -> void:
	# N12-3：中央窗 MainView/Title「木料」标签已删（等价替换留痕）；批次 AB-3：恒深档。
	for path: String in ["TargetView/Title", "JoinView/Title"]:
		var lb := get_node_or_null(path) as Label
		if lb == null:
			continue
		lb.add_theme_color_override("font_color", TITLE_FONT_DARK)
		lb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
		lb.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
		lb.add_theme_constant_override("outline_size", TITLE_OUTLINE)

# ---- M-E 追2（spec §3.5 目标行为 8）：悬停「手电筒照木头」点光（用户澄清 2026-09-08）----
# 【方案定稿】用户澄清追2 意图=「鼠标放上去像手电筒照在真实木头上，纹理浮雕质感，光影随
# 3D 形状变化」——**金色半透明壳方案废弃**（_hover_marker/BoxMesh 壳整套删除留痕）。
# 现方案：各视图 OmniLight3D 暖金点光跟随**各自视图**悬停命中点（沿视线反方向抬高防贴面
# 死黑；回修2 D 覆盖三视图，非主视图专属）；体素木纹材质本就受光（StandardMaterial3D
# 缺省 PER_PIXEL + roughness 0.55 + 木纹 albedo 噪声 + 0.06 体素缝隙 + 深褐线框）→
# 点光近照天然形成「凸面亮/凹缝暗」浮雕感，**零材质改动**=最小侵入。
# 能量渐入渐出走 _tick_hover_light(delta)（参照气泡 hover 能量惯例）；光位置只在输入
# 驱动路径（motion/悬停格变化）更新，不进 _process 强刷（坑 9 纪律）。
const HOVER_LIGHT_COLOR := Color(1.0, 0.87, 0.58)   # 暖金照木头色温
const HOVER_LIGHT_ENERGY := 1.5                      # 照射能量（适中，M-C 手电筒定档口径 3D 换算）
const HOVER_LIGHT_RANGE := 3.0                       # 照射范围≈3 格（2~4 格档）
const HOVER_LIGHT_LIFT := 1.6                        # 沿视线反方向抬高距离（防贴面死黑+浮雕出光角）
const HOVER_LIGHT_SPEED := 10.0                      # 能量渐入渐出速率（/s，参照 hover 渐变惯例）

## 悬停格查询（M-E 追2 测试钩子；view="Main"/"Target"/"Join"，NO_CELL=未悬停）。
func get_hover_cell(view: String = "Main") -> Vector3i:
	var v: Variant = _hover_cells.get(view, NO_CELL)
	return v if v is Vector3i else NO_CELL

## 各视图悬停点光能量渐变推进（_process 每 tick 调用；只动 light_energy 数值——不碰
## 相机位姿/体素节点，坑 9 纪律安全；光位置仍只在 _set_hover 输入驱动路径更新）。
func _tick_hover_light(delta: float) -> void:
	for view: String in ["Main", "Target", "Join"]:
		var light: OmniLight3D = _hover_lights.get(view)
		if light == null or not is_instance_valid(light):
			continue
		var target: float = float(_hover_light_targets.get(view, 0.0))
		light.light_energy = move_toward(light.light_energy, target, delta * HOVER_LIGHT_SPEED)
		# 回修4 甄别修复：headless/低帧率下 delta 极小时渐入首帧 energy 可能 <0.01，
		# 旧判定 `visible = energy > 0.01` 会把悬停中的光误隐藏（测试 flake 根因）——
		# 改「悬停中（target>0）恒可见；渐灭（target=0）能量耗尽才隐藏」，观感语义不变。
		light.visible = target > 0.0 or light.light_energy > 0.01

## 悬停点光置位/复位：cell=NO_CELL → 该视图能量目标归 0（渐灭）；否则移动光位到命中格
## （格心 + 朝该视图相机方向 × LIFT 抬高），能量目标渐入。
func _set_hover(view: String, cell: Vector3i) -> void:
	if cell == _hover_cells.get(view, NO_CELL) and cell != NO_CELL:
		return  # 同格不重复刷（motion 高频调用性能）
	_hover_cells[view] = cell
	if cell == NO_CELL or _focus_active:
		_hover_cells[view] = NO_CELL  # 移开/聚焦点云显示中 → 悬停态复位（点光渐灭）
		_hover_light_targets[view] = 0.0
		return
	var light := _ensure_hover_light(view)
	var vp := main_viewport if view == "Main" else (target_viewport if view == "Target" else join_viewport)
	var center_v: Variant = _view_centers.get(view, Vector3.ZERO)
	var center: Vector3 = center_v if center_v is Vector3 else Vector3.ZERO
	var cell_center: Vector3 = Vector3(cell) + Vector3(0.5, 0.5, 0.5) - center
	var cam := vp.get_node_or_null("Camera3D") as Camera3D
	if cam != null:
		var to_cam: Vector3 = (cam.position - cell_center).normalized()
		light.position = cell_center + to_cam * HOVER_LIGHT_LIFT  # 沿视线反方向抬高
	_hover_light_targets[view] = HOVER_LIGHT_ENERGY
	light.visible = true  # 命中即显示（能量由 _tick_hover_light 渐入）

func _ensure_hover_light(view: String) -> OmniLight3D:
	var existing: Variant = _hover_lights.get(view)
	if existing is OmniLight3D and is_instance_valid(existing):
		return existing
	var light := OmniLight3D.new()
	light.name = "HoverLight_%s" % view
	light.light_color = HOVER_LIGHT_COLOR
	light.light_energy = 0.0
	light.omni_range = HOVER_LIGHT_RANGE
	light.omni_attenuation = 1.3          # 衰减略陡（自然手电筒衰减+聚拢浮雕感）
	light.shadow_enabled = true           # 凹缝投影（浮雕感来源之一）
	light.visible = false
	var vp := main_viewport if view == "Main" else (target_viewport if view == "Target" else join_viewport)
	vp.add_child(light)
	_hover_lights[view] = light
	return light

# ==================== 批次 E：挖除交互（选区 / 删除 / 撤销重做 / 拾取） ====================

## 选中/取消体素：additive=false 普通点击=单选替换；true=Ctrl 点击=追加切换。
## 越界或已删除（不存在于 _remaining）的 cell 静默忽略；成功动画期间锁定输入。
func select_voxel(cell: Vector3i, additive: bool) -> void:
	if _input_locked or not _remaining.has(cell):
		return
	if additive:
		if _selected.has(cell):
			_selected.erase(cell)
			_set_cell_highlight(cell, false)
		else:
			_selected[cell] = true
			_set_cell_highlight(cell, true)
	else:
		clear_selection()
		_selected[cell] = true
		_set_cell_highlight(cell, true)
	if _eye_active:
		_refresh_eye()  # 批次 G：选区变化影响 mark/高亮互斥，实时重算
	if _focus_active:
		_set_focus(false)  # K6-7：聚焦中再次操作选区 → 先恢复（可恢复语义）
	_update_focus_btn()  # P1-1 审查回修：主视图选区变动即时刷新聚焦钮（真机可达性）

## 批次 Y（Y-A12，spec §2-⑫）：格选中态查询（Router 右手二指「纯减选笔」来源判别消费——
## 仅命中已选块才合成 Ctrl+左键事件）。只读谓词，键鼠路径零依赖零改动。
func is_cell_selected(cell: Vector3i) -> bool:
	return _selected.has(cell)

## 清空选区（点击空白 / Esc 同效），逐格取消高亮。
func clear_selection() -> void:
	for cell_v: Variant in _selected.keys():
		_set_cell_highlight(cell_v, false)
	_selected.clear()
	if _eye_active:
		_refresh_eye()  # 批次 G：取消选中后若仍为多余体素需重新标红
	if _focus_active:
		_set_focus(false)  # K6-7：清选=恢复聚焦（点云散开、隐藏体素回显）
	_update_focus_btn()  # P1-1 审查回修：清选后聚焦钮回灰态

## 批次 X（P5-a）同源删除核心（spec §6）：对给定格集执行「无条件清高亮→移出选区/剩余集→
## 渲染隐藏→撤销栈整组入栈→重做清空→检查点脏标→提示/计数/锐眼/聚焦刷新」，delete_cell
## （单删）与 delete_selected（删全部已选）共用本链——锁守卫/撤销栈入栈/检查点脏标零分叉。
## 空结果=幂等返回 0（不入栈不刷新，与旧 delete_selected 空删除口径一致）。
func _delete_cells(cells: Array) -> int:
	if _input_locked:
		return 0
	var removed: Array = []
	for cell_v: Variant in cells:
		var cell: Vector3i = cell_v
		_set_cell_highlight(cell, false)  # P2：先清高亮（不依赖 _remaining 判定）
		_selected.erase(cell)
		if not _remaining.has(cell):
			continue
		_remaining.erase(cell)
		_hide_cell(cell)
		removed.append(cell)
	if removed.is_empty():
		return 0
	_push_undo(removed)
	_redo_stack.clear()  # 新操作分支：重做历史作废
	_checkpoint_dirty_at = Time.get_ticks_msec()  # N11：改动置脏（2s 防抖自动存档）
	_update_hint()
	_update_voxel_label()  # M-E：顶栏计数实时刷新
	if _eye_active:
		_refresh_eye()  # 批次 G：删除改变剩余集，差集实时重算
	if _focus_active:
		_set_focus(false)  # K6-7：挖除即退出聚焦（隐藏体素恢复后按新剩余集重算）
	_update_focus_btn()  # P1-1 审查回修：删除清空选区后聚焦钮回灰态
	return removed.size()

## 批次 X（P5-a）手势单删入口：删除指定一格（同源删除链见 _delete_cells）。
## 返回实际删除数 0/1——锁定守卫/撤销栈整组入栈/检查点脏标与 delete_selected 完全一致
## （单格自成一组=手势单删一次撤销；键鼠右键多格整组撤销语义由 delete_selected 保持）。
func delete_cell(cell: Vector3i) -> int:
	return _delete_cells([cell])

## 删除选中组：返回实际删除数；隐藏节点（撤销可恢复）、入撤销栈、清空重做栈、同步提示。
## 选区为空 → 提示且不入栈（不崩）；已删体素不在 _remaining → 天然幂等。
## P2 修复（方案 A）：对每个选区键先无条件清高亮，再判 _remaining——否则「撤销后重新
## 选中 → 重做移出剩余集」的格子会永久残留高亮（选区被清后无法再清除）。
## 批次 X（P5-a）：重构为复用 _delete_cells 同源链（delete_cell 单删与全删零分叉），
## 空选话术/整组单撤销组/返回值语义零变化（键鼠行为零变化红线）。
func delete_selected() -> int:
	if _input_locked:
		return 0
	if _selected.is_empty():
		hint_label.text = I18n.t("请先按住左键划选要挖除的体素")  # K6-5：划选话术（Ctrl 话术清理第二处）
		return 0
	return _delete_cells(_selected.keys())

## 撤销：弹出最近删除组，整组恢复（show + 回到剩余集），转入重做栈；空栈安全返回 false。
func undo() -> bool:
	if _input_locked:
		return false
	if _undo_stack.is_empty():
		hint_label.text = I18n.t("没有可撤销的操作")
		return false
	var group: Array = _undo_stack.pop_back()
	for cell_v: Variant in group:
		var cell: Vector3i = cell_v
		_remaining[cell] = true
		_show_cell(cell)
	_redo_stack.append(group)
	_checkpoint_dirty_at = Time.get_ticks_msec()  # N11：撤销同样改变差集 → 置脏
	_update_hint()
	_update_voxel_label()  # M-E：顶栏计数实时刷新
	if _eye_active:
		_refresh_eye()  # 批次 G：撤销恢复体素，差集实时重算
	if _focus_active:
		_set_focus(false)  # K6-7：撤销=恢复操作，退出聚焦防点云与回显体素叠影
	_update_focus_btn()  # P1-1 审查回修：撤销后选区态同步聚焦钮
	return true

## 重做：弹出最近撤销组，整组再删（hide + 移出剩余集），转回撤销栈；空栈安全返回 false。
## P2 修复（方案 B）：组内格子若正被选中（高亮），一并移出选区并清高亮——重做会绕过
## delete_selected 直接移出剩余集，不清高亮会留下无法清除的残留。
func redo() -> bool:
	if _input_locked:
		return false
	if _redo_stack.is_empty():
		hint_label.text = I18n.t("没有可重做的操作")
		return false
	var group: Array = _redo_stack.pop_back()
	for cell_v: Variant in group:
		var cell: Vector3i = cell_v
		if _selected.has(cell):
			_selected.erase(cell)
			_set_cell_highlight(cell, false)
		_remaining.erase(cell)
		_hide_cell(cell)
	_push_undo(group)
	_checkpoint_dirty_at = Time.get_ticks_msec()  # N11：重做同样改变差集 → 置脏
	_update_hint()
	_update_voxel_label()  # M-E：顶栏计数实时刷新
	if _eye_active:
		_refresh_eye()  # 批次 G：重做移除体素，差集实时重算
	if _focus_active:
		_set_focus(false)  # K6-7：重做同撤销=恢复类操作，退出聚焦
	_update_focus_btn()  # P1-1 审查回修：重做后选区态同步聚焦钮
	return true

## W9-8（批次 AA 规格 §12 P3-9）撤销栈唯一入栈口：append 后按 MAX_UNDO 截断（丢最旧、留最近
## N 条）。挖除（_delete_cells）与重做（redo）两处 append 点均收口至此；撤销/重做往返不越界。
func _push_undo(unit: Array) -> void:
	_undo_stack.append(unit)
	while _undo_stack.size() > MAX_UNDO:
		_undo_stack.pop_front()

func get_selected_voxels() -> Array:
	return _selected.keys()

func get_remaining_voxels() -> Array:
	return _remaining.keys()

func get_undo_depth() -> int:
	return _undo_stack.size()

func get_redo_depth() -> int:
	return _redo_stack.size()

## 拾取包装：对当前剩余体素做射线-AABB 最近命中（几何与构建中心锁定一致）。
func get_cell_hit(origin: Vector3, dir: Vector3) -> Vector3i:
	if _remaining.is_empty():
		return NO_CELL
	return ray_to_cell(origin, dir, _remaining, _voxel_size, _voxel_center)

## 纯数学拾取（slab 射线-AABB，不依赖 Physics）：遍历 cells 对每格 [p,p+1] AABB（按
## build_voxels 同式减 center 平移到原点）求射线进入区间，返回 t 最近命中的 cell；
## 未命中返回哨兵 NO_CELL=(-1,-1,-1)。center 缺省时由 cells 自行计算包围盒中心；
## 显式传入可锁定构建时中心（删除后剩余集缩小也不漂移，level_scene 走该路径）。
static func ray_to_cell(origin: Vector3, dir: Vector3, cells: Dictionary, size: Vector3i, center: Vector3 = Vector3.INF) -> Vector3i:
	var d := dir
	if d.length_squared() < 1e-12 or cells.is_empty():
		return NO_CELL
	d = d.normalized()
	var ctr := center
	if ctr == Vector3.INF:
		ctr = _cells_center(cells)
	var best_t := INF
	var best := NO_CELL
	for c: Variant in cells:
		var cell := Vector3i(c)
		# 与构建/关卡库同规则的越界过滤
		if cell.x < 0 or cell.x >= size.x or cell.y < 0 or cell.y >= size.y or cell.z < 0 or cell.z >= size.z:
			continue
		var bmin: Vector3 = Vector3(cell) - ctr
		var bmax: Vector3 = bmin + Vector3.ONE
		# slab 逐轴求 [t0,t1] 进入区间
		var t0 := -INF
		var t1 := INF
		var ok := true
		for axis: int in 3:
			var o := origin[axis]
			var dd := d[axis]
			var lo := bmin[axis]
			var hi := bmax[axis]
			if absf(dd) < 1e-12:
				if o < lo or o > hi:  # 射线与该轴平板平行且原点在外 → 无交
					ok = false
					break
			else:
				var inv := 1.0 / dd
				var ta := (lo - o) * inv
				var tb := (hi - o) * inv
				if ta > tb:
					var tmp := ta
					ta = tb
					tb = tmp
				t0 = maxf(t0, ta)
				t1 = minf(t1, tb)
				if t0 > t1:
					ok = false
					break
		if not ok or t1 < 0.0:  # 区间为空或整段在射线后方
			continue
		var t_enter := maxf(t0, 0.0)  # 起点已在格内时按 0 计
		if t_enter < best_t:
			best_t = t_enter
			best = cell
	return best

## cells 的包围盒中心（与 build_voxels 公式一致：体素占 [p,p+1]）。空集返回零向量。
static func _cells_center(cells: Dictionary) -> Vector3:
	var mn := Vector3i(1 << 29, 1 << 29, 1 << 29)
	var mx := Vector3i(-(1 << 29), -(1 << 29), -(1 << 29))
	for c: Variant in cells:
		var p := Vector3i(c)
		mn.x = mini(mn.x, p.x); mn.y = mini(mn.y, p.y); mn.z = mini(mn.z, p.z)
		mx.x = maxi(mx.x, p.x); mx.y = maxi(mx.y, p.y); mx.z = maxi(mx.z, p.z)
	if mx.x < 0:
		return Vector3.ZERO
	return (Vector3(mn) + Vector3(mx) + Vector3.ONE) * 0.5

## M-E（spec §3.5）：MainView 正交轨道相机位姿刷新（绕原点球坐标，看向原点）。
## ⚠ 仅允许在输入回调（拖拽/滚轮）与初始化/构建路径调用，
## 严禁 _process 每帧刷新——对接成功动画（_play_success_anim）对 MainView
## Camera3D.position 做 tween 拉远，若每帧被轨道逻辑覆写会与 tween 打架
## （动画位姿被拉回、跳变闪烁；spec §六坑 9）。
func _update_main_camera() -> void:
	var cam := main_viewport.get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		return
	_apply_ortho_cam(cam)
	var pos := ORTHO_DIST * Vector3(
		sin(_orbit_yaw) * cos(_orbit_pitch),
		sin(_orbit_pitch),
		cos(_orbit_yaw) * cos(_orbit_pitch))
	cam.position = pos
	cam.look_at(Vector3.ZERO, Vector3.UP)
	if _ortho_size_main > 0.0:
		# N批：旋转缩放解耦——下限与朝向无关（包围球统一口径），旋转路径此保底恒为无操作，
		# ortho size 全程恒定零跳变；「任何朝向不穿帮」仍由统一下限保证（等价替换留痕：
		# 旧回修4 A「朝向变化后块投影可能变大→抬到动态下限」即旋转时木块视觉缩小根因，废止）
		_ortho_size_main = maxf(_ortho_size_main, _ortho_size_min_for("Main", _orbit_yaw, _orbit_pitch))
		cam.size = _ortho_size_main

## M-E：正交相机参数兜底（投影/近远平面定值；tscn 已声明，双保险）。
func _apply_ortho_cam(cam: Camera3D) -> void:
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = ORTHO_NEAR
	cam.far = ORTHO_FAR

## MainView 视口容器的鼠标交互（K6-5/6 状态机 + M-E 修订 + 回修4 C 右键分流，spec §3.5）：
## 左键按下命中体素 → Ctrl 按住=对命中格 additive 切换（M-E④ 多选恢复）；否则 STROKE 划选态
##   （该格立即 additive 选中；每个 motion 再 raycast，命中新格→追加+高亮）；未命中 → ORBIT 旋转态。
## 中键（M-E②）任意位置按下 → ORBIT 旋转态（体素上方也可转），抬起不清选区/不拾取。
## 右键（回修4 C）任意位置按下 → 旋转候选：位移 >2px=ORBIT 拖拽旋转；原地抬起=删除选中组
##   （删除语义不变）。
## 悬停（M-E 追2）：无按键 motion 实时 raycast → 金色壳高亮跟随；移开/拖拽中复位（纯视觉层）。
## 抬起：STROKE 全程未划出新格 → 单选替换（clear+select）；左键 ORBIT 累计位移 <2px → 空白单击清空。
## 右键=删除选中组；滚轮=缩放 ortho size（×0.9/×1.1，限幅=包围球直径 1.2~4.0 倍，M-E① size 语义）。
## Ctrl+Z/Y、Esc、输入锁定守卫全部保留。
# ==================== 批次 Y（Y-C7/Y-C9）：见证者气泡事件分流 ====================

## 立绘可见 rect（content 系）：witness.get_global_rect()（浮动/呼吸实时态）为基，
## portrait_metrics used_rect 精化到非透明像素（KEEP_ASPECT_CENTERED 布局 ×呼吸 scale）。
## 度量未就绪/纹理缺失 → 回落整盒（不误伤分流可用性）。
func _witness_visible_rect() -> Rect2:
	var r := witness.get_global_rect()
	if witness.texture == null or _witness_texture_path == "":
		return r
	var m: Dictionary = PM.measure(_witness_texture_path)
	if not bool(m.get("valid", false)):
		return r
	var f: Dictionary = PM.fit_in_box(m["size"], m["rect_px"], r.size)
	var rp: Rect2 = m["rect_px"]
	var sc := float(f["scale"])
	return Rect2(r.position + Vector2(float(f["dx"]), float(f["dy"])) + rp.position * sc,
		rp.size * sc)

## 批次 Y（Y-C9④）：立绘可见区命中谓词（content 系点判定；main.gd 根 Control 拖窗判定
## 消费——立绘 mouse_filter=IGNORE 使 meta("interactive") 白名单对 gui_get_hovered_control
## 永不可达，拖窗豁免改经本谓词显式处理，选型留痕见交付报告）。外扩 1px 容边缘舍入。
func is_point_over_witness_visible(content_pos: Vector2) -> bool:
	if not is_instance_valid(witness):
		return false
	return _witness_visible_rect().grow(1.0).has_point(content_pos)

## 测试/走查钩子：当前立绘可见 rect（content 系）。
func get_witness_visible_rect() -> Rect2:
	return _witness_visible_rect()

## gui_input 事件落点 → content 系（gui_input 的 position 系容器局部坐标）。
func _witness_hit_at(ev: InputEventMouse, cont: SubViewportContainer) -> bool:
	return is_point_over_witness_visible(cont.get_global_transform() * ev.position)

## Y-C7 事件分流（_on_main_view_gui_input 入口调用）：命中立绘可见区 → 气泡交互并
## 消费事件（左键按下=toggle，旧设计 ded6fa8/ad85663 口径；右/中键按下仅消费不动作）；
## 未命中 → 返回 false，原 3D 拾取链原样（批次 W P1-7a 拾取带修复不回退）。
## 拖拽进行中（任一按键已按下）motion 一律放行——划选/轨道旋转跨立绘带不中断。
func _witness_bubble_dispatch(event: InputEvent, cont: SubViewportContainer) -> bool:
	if cont == null:
		return false
	var consumed := false
	var mm := event as InputEventMouseMotion
	if mm != null:
		if not (_left_pressed or _middle_pressed or _right_pressed) and _witness_hit_at(mm, cont):
			consumed = true  # 悬停态命中立绘：消费 motion（旧 STOP 行为：3D 点光不穿透立绘）
	else:
		var mb := event as InputEventMouseButton
		if mb != null:
			var hit := _witness_hit_at(mb, cont)
			if mb.pressed and hit:
				if mb.button_index == MOUSE_BUTTON_LEFT:
					_toggle_witness_bubble()
				consumed = true
			elif not mb.pressed and hit and not (_left_pressed or _middle_pressed or _right_pressed):
				# 批次 Y 扫描回修 P1：抬起消费补「按下归属」校验——仅当按下也被立绘消费
				# （3D 链三键标志全 false）才对称吃掉抬起；3D 链按下（划选/ORBIT/右键候选）
				# 横穿立绘带后抬起落点命中立绘时，旧实现无条件吞掉 → level_scene 永远收不到
				# 抬起（虚拟按键卡死/候选态残留，红测 test_y6_bubble_release_guard ①②③）。
				consumed = true  # 按下已被消费的抬起对称吃掉（防落空回原链）
	if consumed and cont != null:
		cont.accept_event()
	return consumed

## Y-C7：气泡 toggle（显示期间再点=关闭；未显示=弹出）——旧批次 G 设计同款语义。
func _toggle_witness_bubble() -> void:
	if _witness_bubble_open:
		_hide_witness_bubble()
	else:
		_show_witness_bubble()

# ==================== 批次 R：主视图 gui_input（挖除/划选/旋转/缩放） ====================

func _on_main_view_gui_input(event: InputEvent) -> void:
	if _input_locked:
		return
	var mm0 := event as InputEventMouseMotion
	if mm0 != null and (_right_pressed or _middle_pressed) \
			and mm0.has_meta(GestureCursorLayer.SYNTH_META):
		# 批次 AD 审查回修 P2-4（2026-09-28）：物理右/中键拖拽期过滤手势**合成** motion——
		# 巡航 synth_motion 的注入门只挡物理左键（Router `not is_mouse_button_pressed(LEFT)`
		# + 让位窗），物理右/中键按住且指针静止超 1.5s 让位窗后，合成 motion 会窜入本 handler
		# 的拖拽分支：`_last_motion_pos`/`_right_moved` 被手势光标位污染 → 轨道旋转跳变、
		# 右键 2px 阈值误判。此处按 SYNTH_META（synth_* 工厂统一挂标，真实键鼠零此 meta）
		# 只在**物理右/中键按压期**过滤；物理左键既有门（Router 注入端）保持不变，
		# 手势左键笔画（_left_pressed 由合成左键置位、右/中键未按）不受影响。
		return
	# 批次 Y（Y-C7）：事件分流——命中立绘可见区→气泡交互并消费；未命中→原 3D 拾取链不动。
	# W9-9（批次 AA 规格 §12 P3-10①）：分流**前移**到 _remaining 空早退之前——旧序把两件事绑在
	# 一起，全挖空态（_remaining 空）连见证者点击/悬停也被早退挡死、气泡交互不可达。现语义：
	# 立绘交互**双入口**：① 本 handler 的 _witness_bubble_dispatch 分流（MainView 命中带）；
	# ② WitnessPortrait.gui_input 直连 _on_witness_gui_input（批次 AD §4.3.5 恢复，见其头注）。
	# 两入口同受 _input_locked（成功动画锁）约束——P2-5 回修给 ② 补了同款锁（旧缺门可锁定期弹泡）。
	# P3-5（审查缺陷）：_remaining 空的 blanket 早退已下沉——只拦拾取/删除分支（悬停射线、
	# 按下拾取、右键删除），滚轮缩放与轨道旋转/拖拽在全挖空态照常可用（W9-9 意图只拦拾取链）。
	if _witness_bubble_dispatch(event, get_node_or_null("MainView/ViewportContainer") as SubViewportContainer):
		return
	var cont := get_node_or_null("MainView/ViewportContainer") as SubViewportContainer
	if cont == null or main_viewport.get_node_or_null("Camera3D") == null:
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		if _left_pressed or _middle_pressed or _right_pressed:
			_set_hover("Main", NO_CELL)  # 拖拽/划选中点光让位（不干扰划选/旋转视觉）
		else:
			# P3-5：空场拦悬停拾取（隐藏几何仍可被射线命中的批次 Q 同族防线）
			_set_hover("Main", NO_CELL if _remaining.is_empty() else _raycast_cell(mm.position, cont))  # 追2：点光实时跟随
		if _left_pressed and _drag_mode == DragMode.STROKE:
			# 划选：每个 motion 再 raycast，命中新格→追加+高亮（_selected 字典天然幂等）
			var hit := _raycast_cell(mm.position, cont)
			if hit != NO_CELL and not _selected.has(hit):
				select_voxel(hit, true)
				_stroke_new_seen = true
			cont.accept_event()
		elif _left_pressed and _drag_mode == DragMode.STROKE_DESELECT:
			# 批次 Q1（R2）：反选划选——扫过的已选格逐个 toggle 取消；扫过未选格无操作
			var hit_d := _raycast_cell(mm.position, cont)
			if hit_d != NO_CELL and _selected.has(hit_d):
				select_voxel(hit_d, true)
			cont.accept_event()
		elif _drag_mode == DragMode.ORBIT and (_left_pressed or _middle_pressed or _right_pressed):
			# 空白左键拖动 / 中键任意位置拖动 / 右键拖动（回修4 C）=旋转：
			# motion 驱动 yaw/pitch，夹 ±80°。右键有 2px 阈值分流（原地=点击删除候选）
			if _right_pressed and not _left_pressed and not _middle_pressed:
				_right_moved += (mm.position - _last_motion_pos).length()
				if _right_moved <= 2.0 and not _right_orbit:
					_last_motion_pos = mm.position
					return  # 未超阈值：仍是「原地右键点击」候选，不旋转
				_right_orbit = true
			var rel := mm.position - _last_motion_pos
			_orbit_moved += rel.length()
			_orbit_yaw -= rel.x * ORBIT_SPEED  # 抓握式：右拖场景右转
			_orbit_pitch = clampf(_orbit_pitch + rel.y * ORBIT_SPEED,
				-deg_to_rad(PITCH_LIMIT_DEG), deg_to_rad(PITCH_LIMIT_DEG))
			_update_main_camera()
			cont.accept_event()
		_last_motion_pos = mm.position
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if mb.pressed and _main_diameter > 0.0 and _ortho_size_main > 0.0:
			# M-E①：缩放改 ortho size 语义（等价替换留痕：原 _cam_dist ×0.9/×1.1 限幅 [4.5,14]）；
			# 回修4 A：下限=当前朝向窗口适配动态下限（最大档块投影完整留边，不穿帮）
			_ortho_size_main = clampf(
				_ortho_size_main * (ORTHO_ZOOM_IN if mb.button_index == MOUSE_BUTTON_WHEEL_UP else ORTHO_ZOOM_OUT),
				_ortho_size_min_for("Main", _orbit_yaw, _orbit_pitch), _main_diameter * ORTHO_SIZE_MAX_MUL)
			_update_main_camera()
			cont.accept_event()
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_left_pressed = true
			_orbit_moved = 0.0
			_stroke_new_seen = false
			_last_motion_pos = mb.position
			# P3-5：空场拦按下拾取——隐藏几何仍可被射线命中（批次 Q 同族），remaining 空时
			# 强制 NO_CELL → 自然落入 ORBIT 分支（旋转可达、零选中）；非空维持原射线拾取。
			var hit := NO_CELL if _remaining.is_empty() else _raycast_cell(mb.position, cont)
			# 批次 Q3（F1/F3）：聚焦态按下一律 ORBIT——点云已隐藏但拾取仍按静态几何命中（§2.4），
			# 守卫置于选区分流链最上游：Q1 的 Ctrl/STROKE_DESELECT 分支在其后不可达
			if _focus_active:
				_drag_mode = DragMode.ORBIT
			elif hit != NO_CELL:
				if mb.ctrl_pressed:
					# M-E④：Ctrl+点击=对命中格 additive 切换（复用 select_voxel，与划选并存）
					# 批次 Q1：先取 was_selected 再 toggle——已选格进反选划选态，未选格维持点选态
					var was_selected := _selected.has(hit)
					select_voxel(hit, true)
					_drag_mode = DragMode.STROKE_DESELECT if was_selected else DragMode.NONE
				else:
					_drag_mode = DragMode.STROKE
					_stroke_start_cell = hit
					# P3-1 审查回修：与 motion 分支同款 not-has 守卫——按下扫过已选格不 toggle 取消
					# （spec §10.4「划选中扫过已选格不重复计数」；起点格保留，单选替换仍由抬起路径负责）
					if not _selected.has(hit):
						select_voxel(hit, true)  # 该格立即 additive 选中
			else:
				_drag_mode = DragMode.ORBIT
			cont.accept_event()
		elif _left_pressed:
			_left_pressed = false
			# 批次 Q1：STROKE_DESELECT 无抬起兜底——起点格按下即取消，套用单选替换会反向错加
			if _drag_mode == DragMode.STROKE:
				if not _stroke_new_seen:
					clear_selection()  # 全程未划出新格→单选替换（clear+select）
					select_voxel(_stroke_start_cell, false)
			elif _drag_mode == DragMode.ORBIT and _orbit_moved < 2.0 and not _focus_active:
				clear_selection()  # 空白单击=清空选区（批次 Q3（F1）：聚焦态跳过——不退聚焦不清选区）
				_update_hint()
			_drag_mode = DragMode.NONE
			cont.accept_event()
	elif mb.button_index == MOUSE_BUTTON_MIDDLE:
		# M-E②：中键任意位置（含体素上方）拖拽=旋转；抬起仅退出旋转态（不清选区/不拾取）
		if mb.pressed:
			_middle_pressed = true
			_drag_mode = DragMode.ORBIT
			_orbit_moved = 0.0
			_last_motion_pos = mb.position
			cont.accept_event()
		elif _middle_pressed:
			_middle_pressed = false
			_drag_mode = DragMode.NONE
			cont.accept_event()
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		# 回修4 C（用户「旋转必须找空白处很难操作」痛点）：右键分流——按下后位移 >2px=
		# 拖拽旋转（任意位置含体素上方）；原地抬起（无位移）=删除选中组（删除语义完全
		# 不变，仅从「按下即删」延后到「抬起判定」，键鼠点击行为无感）。
		if mb.pressed:
			if _drag_mode == DragMode.NONE and not _left_pressed and not _middle_pressed:
				_right_pressed = true
				_right_moved = 0.0
				_right_orbit = false
				_drag_mode = DragMode.ORBIT  # 候选旋转态（超阈值才真转）
				_last_motion_pos = mb.position
			cont.accept_event()
		elif _right_pressed:
			_right_pressed = false
			_drag_mode = DragMode.NONE
			if not _right_orbit:
				_set_hover("Main", NO_CELL)  # 删除后剩余集变化，点光先复位（motion 会重新拾取）
				if not _remaining.is_empty():  # P3-5：空场拦删除分支（无格可删，防误提示）
					delete_selected()  # 空选时内部给出划选提示，不崩
			cont.accept_event()

## 按下/划选即时 raycast（事件坐标→SubViewport 坐标→相机射线，数学同原 _pick_at）。
func _raycast_cell(pos: Vector2, cont: SubViewportContainer) -> Vector3i:
	var cam := main_viewport.get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		return NO_CELL
	var vp_pos := _to_viewport_pos(pos, cont)
	return get_cell_hit(cam.project_ray_origin(vp_pos), cam.project_ray_normal(vp_pos))

## 容器局部坐标 → SubViewport 坐标（stretch=true 除以 shrink；否则按尺寸比例换算）。
func _to_viewport_pos(local: Vector2, cont: SubViewportContainer) -> Vector2:
	if cont.stretch:
		return local / float(cont.stretch_shrink)
	var vp := cont.get_node_or_null("SubViewport") as SubViewport
	if vp != null and cont.size.x > 0.0 and cont.size.y > 0.0:
		return Vector2(local.x * vp.size.x / cont.size.x, local.y * vp.size.y / cont.size.y)
	return local

## 键盘：Ctrl+Z=撤销；Ctrl+Y / Ctrl+Shift+Z=重做；Esc=清空选区。
## 用事件物理键判定（不改 project.godot 输入映射）；走 _unhandled_input 避免与 GUI 抢事件。
## N4：回看拖拽专用通道独立走 _input（GUI 之前，见 _review_unhandled_input）——
func _input(event: InputEvent) -> void:
	if _review_unhandled_input(event):
		get_viewport().set_input_as_handled()  # 消费拖拽通道事件，防穿透到 GUI/unhandled

## 键盘：Ctrl+Z=撤销；Ctrl+Y / Ctrl+Shift+Z=重做；Esc=清空选区。
## 用事件物理键判定（不改 project.godot 输入映射）；走 _unhandled_input 避免与 GUI 抢事件。
func _unhandled_input(event: InputEvent) -> void:
	if _input_locked:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var ctrl := key.ctrl_pressed or key.meta_pressed
	var is_z := key.keycode == KEY_Z or key.physical_keycode == KEY_Z
	var is_y := key.keycode == KEY_Y or key.physical_keycode == KEY_Y
	var is_esc := key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE
	if ctrl and is_z:
		if key.shift_pressed:
			redo()  # Ctrl+Shift+Z 兼作重做
		else:
			undo()  # 空栈时 undo() 内部给出提示
	elif ctrl and is_y:
		redo()
	elif is_esc and not _selected.is_empty() and not _focus_active:
		clear_selection()
		_update_hint()

func _main_voxel_view() -> Node:
	return main_viewport.get_node_or_null("VoxelView")

func _hide_cell(cell: Vector3i) -> void:
	var vv := _main_voxel_view()
	if vv != null:
		vv.call("hide_voxel", cell)

func _show_cell(cell: Vector3i) -> void:
	var vv := _main_voxel_view()
	if vv != null:
		vv.call("show_voxel", cell)

func _set_cell_highlight(cell: Variant, on: bool) -> void:
	var vv := _main_voxel_view()
	if vv != null:
		vv.call("set_voxel_highlight", cell, on)

## 提示同步（M-E 拍板 #8）：底部常驻一行=纯键鼠操作精简模板（不再拼接对接引导句与
## 剩余体素计数——计数挪 TopBar/VoxelLabel、引导迁 JoinButton.tooltip）。
## 回修4：字号 18（主题默认 20 下旧文案已贴满 1013 容器宽，新文案@18 实测 947 单行无忧）。
func _update_hint() -> void:
	hint_label.modulate = Color.WHITE
	hint_label.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	hint_label.text = I18n.t(HINT_OPERATIONS)   # I18n：显示点 t()（常量=中文键不动）

## 批次 W（N15，拍板 10）：旋转模式提示行文字提示——ORBIT 进/出由 GestureRouter 调用。
## 活跃期提示行整行替换为固定文案（与光标解耦：光标恒左蓝右红，琥珀环已删）；退出时
## 还原常驻操作提示（_update_hint 既有文案）。仅 GestureRouter 二指空白路径调用。
## 批次 X（P5-c）：加手别标注——ORBIT 进入=左手空白二指（右手二指=Ctrl 减选笔，spec §6）。
## 批次 AA（W3-5，spec §6.4-D）：措辞消歧——「点击」与「二指单击」易混，改「二指再点空白退出」
##（语义未变：旋转仍左手专属、退出仍=二指再点空白；键鼠 Esc/点空白路径零改动）。
const ORBIT_HINT_TEXT := "【左】旋转模式：二指再点空白退出"
func set_orbit_hint(active: bool) -> void:
	if active:
		hint_label.modulate = Color.WHITE
		hint_label.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
		hint_label.text = I18n.t(ORBIT_HINT_TEXT)
	else:
		_update_hint()

## 顶栏剩余体素计数（M-E 拍板 #8）：删除/撤销/重做/直驱测试钩子后实时刷新。
func _update_voxel_label() -> void:
	voxel_label.text = I18n.t(VOXEL_LABEL_FMT) % [_remaining.size(), _initial_total]   # I18n

## 失败提示（K4-2）：一律右上角 Game.toast 短文案；hint_label 回归纯操作提示
## （常驻说明+剩余计数），不再承载错误长文案（spec §6.3/§10.6）。连续对接→toast 堆叠。
## M-E 回修3 E（用户反馈：弹窗遮退出/设置钮与右上木块）：对接失败弹窗改顶部中央锚点
## （左右侧面板之间、木料标签上方空档，centered=true），任何状态不遮顶栏/侧面板。
func _show_fail_hint(msg: String) -> void:
	Game.toast(msg, "warn", 2.5, true)
	_update_hint()

# ==================== N3（spec §6.4，K-G 原三视图各挂 FocusFX 随重写废止，等价替换留痕）：全屏三色聚焦 ====================
# 单节点全屏散点控制器（CanvasLayer 0；N12b P3-1 注释漂移回修：旧注释 85 已随 N3 走查
# 定稿 LAYER=0 修正，体内断言早已锁 0）+ 三通道句柄面（_fx_main/_fx_target/_fx_join 保留，
# N批等价替换：语义=通道引用，均指向 _fx_layer 同一控制器；成功动画 deactivate_immediate 调用链零改动）。
var _fx_layer: Node
var _fx_main: Node
var _fx_target: Node
var _fx_join: Node
var _focus_active := false
# _side_selected 声明已随 M-E③ 迁至「侧面板完全不可交互 + 恒空兼容层」段（下方，注释口径更全）

func _make_focus_fx() -> Node:
	## N3：全屏层随关卡场景创建（本场景子节点，不挂全局单例——关卡重开随场景释放不残留）。
	var fx: Node = (load("res://scripts/focus_fx.gd") as GDScript).new()
	fx.name = "FocusFX"
	add_child(fx)
	return fx

func _toggle_focus() -> void:
	if _focus_active:
		_set_focus(false)
		return
	_finish_eye()  # 聚焦与锐眼互斥（开一方先关另一方）
	var any := false
	any = bool(_fx_main.call("activate_channel", "Main", _selected.keys(), _remaining.keys())) or any
	var tvv: Node = target_viewport.get_node_or_null("VoxelView")
	if tvv != null:
		any = bool(_fx_target.call("activate_channel", "Target", _side_selected["Target"].keys(), tvv.call("get_built_cells"))) or any
	var jvv: Node = join_viewport.get_node_or_null("VoxelView")
	if jvv != null:
		any = bool(_fx_join.call("activate_channel", "Join", _side_selected["Join"].keys(), jvv.call("get_built_cells"))) or any
	_set_focus(any)

func _set_focus(on: bool) -> void:
	if not on:
		for fx: Node in [_fx_main, _fx_target, _fx_join]:
			if fx != null:
				fx.call("deactivate")
	else:
		for view: String in ["Main", "Target", "Join"]:
			_set_hover(view, NO_CELL)  # M-E 追2：聚焦态三视图点光复位（视觉互斥）
	_focus_active = on
	_update_focus_btn()

func _update_focus_btn() -> void:
	focus_btn.disabled = _selected.is_empty() and _side_selected["Target"].is_empty() \
		and _side_selected["Join"].is_empty()
	focus_btn.text = I18n.t("取消聚焦") if _focus_active else I18n.t("聚焦")

# ==================== M-E 回修2 B（用户实测推翻 M-E-3「完全不可交互」拍板，留痕） ====================
# 侧面板交互恢复：拖拽=旋转（空白左键/中键任意位置）、滚轮=各视图独立 ortho size 缩放、
# 划选/Ctrl+点击=选区（_side_selected 真实选区，聚焦钮恢复消费）、**单击空白=清空该侧选区**
# （旧「误触多选无法取消」痛点以此明显出口解决）。悬停点光跟随各视图命中点（追2 D）。
var _side_selected := {"Target": {}, "Join": {}}  # 侧视图临时高亮集（回修2 起为真实选区）
var _side_yaw := {"Target": deg_to_rad(SIDE_YAW0_DEG), "Join": deg_to_rad(SIDE_YAW0_DEG)}
var _side_pitch := {"Target": deg_to_rad(SIDE_PITCH0_DEG), "Join": deg_to_rad(SIDE_PITCH0_DEG)}
var _side_pressed := {"Target": 0, "Join": 0}  # 0=NONE / 1=STROKE / 2=ORBIT（与 DragMode 枚举值同）
var _side_last := {"Target": Vector2.ZERO, "Join": Vector2.ZERO}
var _side_moved := {"Target": 0.0, "Join": 0.0}
var _side_diameters := {"Target": 0.0, "Join": 0.0}   # 各视图包围球直径（缩放限幅基准）
var _side_stroke_start := {"Target": null, "Join": null}  # 划选起点格（抬起单选替换用）
var _side_stroke_seen := {"Target": false, "Join": false}  # 本次划选是否扫出新格

## 侧面板选区计数（测试钩子；回修2 起语义=真实计数）。
func get_side_selected_count() -> int:
	return _side_selected["Target"].size() + _side_selected["Join"].size()

## Target/Join 正交相机位姿（独立轨道角+独立 ortho size，回修2 B 恢复交互驱动）。
## ⚠ 仅输入回调与初始化/构建路径调用（同主相机纪律，spec §六坑 9）。
func _update_side_camera(which: String) -> void:
	var vp := target_viewport if which == "Target" else join_viewport
	var cam := vp.get_node_or_null("Camera3D") as Camera3D
	if cam == null:
		return
	_apply_ortho_cam(cam)
	var yaw: float = _side_yaw[which]
	var pitch: float = _side_pitch[which]
	cam.position = ORTHO_DIST * Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	cam.look_at(Vector3.ZERO, Vector3.UP)
	var sz: float = float(_ortho_size_side.get(which, 0.0))
	if sz > 0.0:
		# N批：旋转缩放解耦——侧视图旋转路径同主视图，下限与朝向无关（统一口径），size 恒定
		sz = maxf(sz, _ortho_size_min_for(which, yaw, pitch))
		_ortho_size_side[which] = sz
		cam.size = sz

## 侧视图容器输入（回修2 B 状态机，与 MainView 同族分流 + D 悬停点光）：
## 左键按下命中体素 → Ctrl=该格 toggle（_side_selected） / 无 Ctrl=STROKE 划选；
## 未命中 → ORBIT。中键任意位置 → ORBIT。motion 无按键 → 悬停点光跟随该视图命中点。
## 抬起：STROKE 未划出 → 单选替换（clear+select 该侧）；ORBIT 累计 <2px → 空白单击=清空该侧选区。
## 滚轮 = 该视图独立 ortho size（×0.9/×1.1，回修4 A：下限=当前朝向窗口适配动态下限
## ——侧面板最大档受窗尺寸限制且不穿帮；上限=直径×4.0）。
func _on_side_view_gui_input(event: InputEvent, which: String) -> void:
	if _input_locked:
		return
	var vp := target_viewport if which == "Target" else join_viewport
	var vv: Node = vp.get_node_or_null("VoxelView")
	var cam := vp.get_node_or_null("Camera3D") as Camera3D
	if vv == null or cam == null:
		return
	var mm := event as InputEventMouseMotion
	if mm != null:
		if _side_pressed[which] == 0:
			_set_hover(which, _raycast_side_at(which, mm.position, vv, cam))  # 追2 D：点光跟随
		elif _side_pressed[which] == 2:
			var rel: Vector2 = mm.position - _side_last[which]
			_side_moved[which] += rel.length()
			_side_yaw[which] -= rel.x * ORBIT_SPEED  # 抓握式旋转（独立轨道角）
			_side_pitch[which] = clampf(float(_side_pitch[which]) + rel.y * ORBIT_SPEED,
				-deg_to_rad(PITCH_LIMIT_DEG), deg_to_rad(PITCH_LIMIT_DEG))
			_update_side_camera(which)
		elif _side_pressed[which] == 1:
			# 划选：motion 重复射线拾取=连续多选（天然幂等，回修3 D 与分流拾取同源精确）；
			# 带 Ctrl 的 motion 不追加（Ctrl 语义只在按下 toggle，同主视图口径）；扫出新格置 seen
			if not mm.ctrl_pressed:
				var hit_m: Vector3i = _raycast_side_at(which, mm.position, vv, cam)
				if hit_m != NO_CELL and not _side_selected[which].has(hit_m):
					_select_side_cell(which, hit_m, vv, true)
					_side_stroke_seen[which] = true
			_set_hover(which, NO_CELL)  # 划选中点光让位
		_side_last[which] = mm.position
		return
	var mb := event as InputEventMouseButton
	if mb == null:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if mb.pressed:
			var d_side := _side_diameter(which)
			# 回修4 A：下限=该视图当前朝向窗口适配动态下限（侧面板最大档受窗尺寸限制
			# 且不穿帮——用户拍板「左上、右上大小最大限制一下」）
			if d_side > 0.0 and float(_ortho_size_side[which]) > 0.0:
				_ortho_size_side[which] = clampf(
					float(_ortho_size_side[which]) * (ORTHO_ZOOM_IN if mb.button_index == MOUSE_BUTTON_WHEEL_UP else ORTHO_ZOOM_OUT),
					_ortho_size_min_for(which, float(_side_yaw[which]), float(_side_pitch[which])),
					d_side * ORTHO_SIZE_MAX_MUL)
				_update_side_camera(which)
		return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			_side_moved[which] = 0.0
			_side_last[which] = mb.position
			# 回修3 D 根因修复：分流拾取改射线-AABB 精确命中（原 48px unproject 就近拾取在
			# 小侧视口下任何按下点都 <48px 命中某体素 → 永远进划选、永不进旋转——用户实测
			# 「绿格能选但旋转不通」的根因）；空白=真空白 → ORBIT
			var hit: Vector3i = _raycast_side_at(which, mb.position, vv, cam)
			# 批次 Q3（F3）：聚焦态整面板=旋转热区——一律拦为 ORBIT(2)、选区冻结（修复问题 B：
			# 点云隐藏但 ray_to_cell 仍命中，原分流大多被吞成划选态、真空白边缘极小）
			if _focus_active:
				_side_pressed[which] = 2
			elif hit != NO_CELL:
				_side_pressed[which] = 1
				if mb.ctrl_pressed:
					_select_side_cell(which, hit, vv, true)  # Ctrl=该格 toggle（含取消）
					# P1（审查缺陷）：本次按压已按 toggle 处理 → 置 seen——抬起兜底
					# 「未 seen && start 是格 → 清整侧+单选旧起点」不得覆盖 Ctrl toggle 结果
					# （旧序 seen/start 停留上一次普通单击值，Ctrl+点击 抬起即被抹掉）。
					_side_stroke_seen[which] = true
				else:
					_side_stroke_start[which] = hit
					_side_stroke_seen[which] = false
					if not _side_selected[which].has(hit):
						_select_side_cell(which, hit, vv, true)  # 起点格立即 additive 选中
			else:
				_side_pressed[which] = 2  # 空白 → 旋转
		elif _side_pressed[which] == 1:
			var start: Variant = _side_stroke_start.get(which, null)
			if not _side_stroke_seen[which] and start is Vector3i:
				# 全程未扫出新格 → 单选替换（clear 该侧 + 单选起点）
				_clear_side_selection(which)
				_select_side_cell(which, start, vv, false)
			_side_pressed[which] = 0
		elif _side_pressed[which] == 2 and float(_side_moved[which]) < 2.0 and not _focus_active:
			# M-E 回修2 B：单击空白=清空该侧选区（误触防护的明显出口）
			_clear_side_selection(which)
			_side_pressed[which] = 0
		else:
			_side_pressed[which] = 0
	elif mb.button_index == MOUSE_BUTTON_MIDDLE:
		if mb.pressed:
			_side_pressed[which] = 2  # 中键任意位置（含体素上方）拖拽=旋转
			_side_moved[which] = 0.0
			_side_last[which] = mb.position
		else:
			_side_pressed[which] = 0

## 该视图包围球直径（缩放限幅基准，_apply_ortho_sizes 缓存）。
func _side_diameter(which: String) -> float:
	var d: Variant = _side_diameters.get(which, 0.0)
	return float(d) if d != null else 0.0

## 侧视图射线拾取（追2 D 悬停跟随用）：容器局部 → 视口坐标 → 相机射线 → ray_to_cell
## （几何与渲染同中心锁定，拾取零容差精确）。
## 批次 V（规格 §9.5）等价适配 + 批次 Z Z1 换源：过滤尺寸改按该视图所属域（Target=
## final_answer.size 回落〔Z1 起左上渲染 final 域，与渲染同源〕、Join=join_part.size
## 回落，_build_views 缓存于 _view_sizes）——超 block_size 的界内格
## 可悬停/选中（与按域渲染同口径）；未知视图/未缓存回落 _voxel_size（blocks 域，现状口径）。
func _raycast_side_at(which: String, pos: Vector2, vv: Node, cam: Camera3D) -> Vector3i:
	var cells: Array = _view_cells.get(which, vv.call("get_built_cells"))
	if cells.is_empty():
		return NO_CELL
	var center_v: Variant = _view_centers.get(which, Vector3.ZERO)
	var center: Vector3 = center_v if center_v is Vector3 else Vector3.ZERO
	return ray_to_cell(cam.project_ray_origin(pos), cam.project_ray_normal(pos),
		_cells_dict(cells), _view_size_of(which), center)

## 侧视拾取域尺寸（批次 V §9.5）：_view_sizes 缓存值；缺失回落 _voxel_size（blocks 域）。
func _view_size_of(which: String) -> Vector3i:
	var v: Variant = _view_sizes.get(which, null)
	return (v as Vector3i) if v is Vector3i else _voxel_size

## 批次 V（规格 §9.5）piece 分域尺寸解析（静态纯函数）：domain="target_size"（piece 直属键）
## 或 "join_part"/"final_answer"（嵌套 .size 键）；缺字典整缺回落 bs、缺轴逐轴回落 bs 对应轴
## （与 level_library._domain_size / 编辑器 get_size_for_tag 回落链同口径）。size 合法性
## （每维 1~32）由 level_library 净化门把关（拒载/回落），渲染层不二次校验（宽容消费）。
static func _domain_size(piece: Dictionary, domain: String, bs: Vector3i) -> Vector3i:
	var sz_v: Variant = piece.get(domain, null)
	if domain != "target_size" and sz_v is Dictionary:
		sz_v = (sz_v as Dictionary).get("size", null)
	var d: Dictionary = sz_v if typeof(sz_v) == TYPE_DICTIONARY else {}
	return Vector3i(
		int(d.get("x", bs.x)),
		int(d.get("y", bs.y)),
		int(d.get("z", bs.z)))

## 批次 AC（§4.6-1，2026-09-27）：手势层视口显式绑定与命中判定的公开契约面（GestureRouter 消费）。
## panel 为三视图之一（MainView/ViewportContainer 或 TargetView|JoinView/ViewportContainer），
## global_pos 为 content 全局坐标（合成的 _last_cursor_pos 口径）——按 panel 分流到对应拾取链：
##   主视图 → 局部坐标下 `_raycast_cell(local, cont)`（轴对齐精确命中）；
##   侧视图 → 局部坐标下 `_raycast_side_at(which, local, vv, cam)`（侧视独立域过滤）。
## 返回命中的体素坐标；空白/未知 panel/环境缺失一律 NO_CELL 哨兵（(-1,-1,-1)）。
## 只读谓词：零状态变更、零事件合成（键鼠路径零感知）。
func hit_panel_cell(panel: Node, global_pos: Vector2) -> Vector3i:
	if panel == null or not is_instance_valid(panel) or not (panel is Control):
		return NO_CELL
	var cont := panel as SubViewportContainer
	if cont == null:
		return NO_CELL
	var local: Vector2 = cont.get_global_transform().affine_inverse() * global_pos
	match String(cont.name):
		"ViewportContainer":
			var which := _side_which_of(cont)
			if which == "":
				return _raycast_cell(local, cont)   # MainView（侧视容器同名，以父链区分）
			var vp := target_viewport if which == "Target" else join_viewport
			var vv: Node = vp.get_node_or_null("VoxelView")
			var cam := vp.get_node_or_null("Camera3D") as Camera3D
			if vv == null or cam == null:
				return NO_CELL
			return _raycast_side_at(which, local, vv, cam)
	return NO_CELL

## 批次 AC（§4.6-1）：侧视容器归属解析（"Target"/"Join"；主视图或未知返回 ""）。
## 三容器节点名同为 "ViewportContainer"，以父节点名区分（TargetView/JoinView/MainView）。
func _side_which_of(cont: Control) -> String:
	var par := cont.get_parent()
	if par == null:
		return ""
	var pn := String(par.name)
	if pn == "TargetView":
		return "Target"
	if pn == "JoinView":
		return "Join"
	return ""

## 批次 AC（§4.6-2，2026-09-27）：手势旋转模式（ORBIT）驱动入口——**不限框**持续平滑旋转。
## rel = 帧间光标位移（content 像素，调用方负责 Δ 基准与更新）。主视图更新 _orbit_yaw/_orbit_pitch
## （同键鼠 ORBIT 公式与夹紧）；Target/Join 侧视口按同公式更新各自 _side_yaw/_side_pitch。
## 不校验光标是否仍在 panel 矩形内（用户拍板：旋转期间手/光标移出视口绝不中断旋转）；
## panel 为 null/非三视图/环境缺失时静默零动作（幂等，调用方零分支）。
func orbit_rotate_panel(panel: Node, rel: Vector2) -> void:
	if panel == null or not is_instance_valid(panel) or not (panel is Control) \
			or rel == Vector2.ZERO:
		return
	var cont := panel as SubViewportContainer
	if cont == null:
		return
	var which := _side_which_of(cont)   # ""=主视图
	if which == "":
		_orbit_yaw -= rel.x * ORBIT_SPEED
		_orbit_pitch = clampf(_orbit_pitch + rel.y * ORBIT_SPEED,
			-deg_to_rad(PITCH_LIMIT_DEG), deg_to_rad(PITCH_LIMIT_DEG))
		_update_main_camera()
		return
	_side_yaw[which] -= rel.x * ORBIT_SPEED
	_side_pitch[which] = clampf(float(_side_pitch[which]) + rel.y * ORBIT_SPEED,
		-deg_to_rad(PITCH_LIMIT_DEG), deg_to_rad(PITCH_LIMIT_DEG))
	_update_side_camera(which)

## cells 数组 → Dictionary（ray_to_cell 入参口径）。
func _cells_dict(cells: Array) -> Dictionary:
	var d: Dictionary = {}
	for c: Variant in cells:
		d[Vector3i(c)] = true
	return d

## 侧视图就近拾取（回修3 D 废止留痕）：原 48px unproject 就近命中在小型侧视口下
## 「任何按下点都 <48px 命中某体素」→ 空白按下被吞成划选、旋转永不可达（用户实测
## 「绿格能选但旋转不通」根因）；回修3 起分流/划选全部改 _raycast_side_at 射线精确
## 拾取，空白=真空白，本函数物理删除。

## 该侧选区单格选择/取消（additive=true=切换；false=清空后单选）并同步高亮与聚焦钮。
func _select_side_cell(which: String, cell: Vector3i, vv: Node, additive: bool) -> void:
	if not additive:
		_clear_side_selection(which)
	if _side_selected[which].has(cell):
		_side_selected[which].erase(cell)
		vv.call("set_voxel_highlight", cell, false)
	else:
		_side_selected[which][cell] = true
		vv.call("set_voxel_highlight", cell, true)
	_update_focus_btn()  # 回修2 B：侧选区变动即时刷新聚焦钮（P1-1 同款真机可达性）

## 清空该侧选区（空白单击/单选替换路径共用）并复位高亮。
func _clear_side_selection(which: String) -> void:
	var vp := target_viewport if which == "Target" else join_viewport
	var vv: Node = vp.get_node_or_null("VoxelView")
	for c: Variant in _side_selected[which].keys():
		if vv != null:
			vv.call("set_voxel_highlight", c, false)
	_side_selected[which].clear()
	_update_focus_btn()

# ==================== 批次 G：锐眼（spec 7.4 差集显示 / 付费 / 到时自动关） ====================

## 计费纯函数（spec 7.4/Q&A8）：50 天赋值 / 0.5 秒，一次性扣。
## 档位时长均为 0.5 的整数倍，int 截断与「向上取整」口径结果一致。
static func eye_cost(duration: float) -> int:
	return int(EYE_RATE * duration / EYE_RATE_UNIT)

## 批次 Y（Y-C4）：锐眼免费谓词——第 5 关使用锐眼不消耗任何天赋值（拍板 7）。
static func is_eye_free_chapter(chapter: int) -> bool:
	return chapter == EYE_FREE_CHAPTER

## 批次 Y（Y-C4）：章节感知计费口（菜单文案与 _start_eye 扣费共用，走查调档单点）——
## 免费关返回 0（菜单显示「0 天赋值」），其余关回落 eye_cost 既有口径。
static func eye_cost_for_chapter(chapter: int, duration: float) -> int:
	return 0 if is_eye_free_chapter(chapter) else eye_cost(duration)

## 差集纯函数（spec 7.4 红绿高亮语义；批次 N1 起 spec §6.1 同步 48 变换口径）：
## 多余=extra（remaining 有 target 无，红）；缺少=missing（target 有 remaining 无，绿）。
## N批口径：双方平移归一后按「missing 数最小的最佳变换」（并列取 extra 更小者，仍并列取
## 枚举序首个，确定性）经 JoinXform.best_diff 计算；extra/missing 经逆变换映射回玩家木料
## 当前坐标系，保证红 mark/绿 ghost 落在玩家实际可操作格上；等价形状 → 红绿皆空
##（不再出现「显示差异但实际能通关」的误导）。元素兼容 Vector3i/Vector3/"x,y,z" 字符串，
## 去重按集合语义；size 各维为正时按 **target 域包围盒**过滤 t（越界/负值坐标，spec 校验表
## 同规则），p_size 各维为正时按 **blocks 域包围盒**过滤 p——P2 审查缺陷修复：旧序 p、t 同用
## target_size 过滤，blocks 域 ≥target_size 的玩家格被剔出差集（少显红/归一偏移）；p_size
## 缺省回落 size，2/3 参旧调用行为逐字节不变。缺省不过滤。
## 多解关卡按任务单约定只与 target_shapes[0] 比较（spec §9 遗留 #6，
## 既有现状不在本批扩大）。
static func diff_vs_target(remaining: Dictionary, target: Array, size: Vector3i = Vector3i(-1, -1, -1), p_size: Vector3i = Vector3i(-1, -1, -1)) -> Dictionary:
	var p := _cell_set(remaining.keys())
	var t := _cell_set(target)
	if size.x > 0 and size.y > 0 and size.z > 0:
		_filter_in_bounds(t, size)
	var pf: Vector3i = p_size if (p_size.x > 0 and p_size.y > 0 and p_size.z > 0) else size
	if pf.x > 0 and pf.y > 0 and pf.z > 0:
		_filter_in_bounds(p, pf)
	var bd: Dictionary = JoinXform.best_diff(p, t)
	return {"extra": bd["extra"], "missing": bd["missing"]}

## 就地剔除越界/负值坐标（键为已归一化的 Vector3i）。
static func _filter_in_bounds(cells: Dictionary, size: Vector3i) -> void:
	for k: Variant in cells.keys():
		var c: Vector3i = k
		if c.x < 0 or c.x >= size.x or c.y < 0 or c.y >= size.y or c.z < 0 or c.z >= size.z:
			cells.erase(k)

## 锐眼激活态查询（测试/互斥判定用）。
func is_eye_active() -> bool:
	return _eye_active

## EyeButton 入口：弹出时长选择自绘面板（spec 7.4 流程「选择开启 → 输入显示时长」）。
## P4（批次 X，spec §5）：PopupMenu（独立 Window 子视口）→ 主视口内 PanelContainer 面板
## （手势命中=主视口 Button 祖先链；探针归档 AI工作记录/批次X_走查_20260921/）。
## 每次开启重建（幂等）并锚定 eye_btn 正下方。激活中再次点击 = 重新弹菜单（本批选定行为：
## 选中后先扣费、成功才清旧重开，见 _start_eye）。
func _open_eye_menu() -> void:
	if _input_locked or _success_started or _settled:
		return
	if _eye_menu == null or not is_instance_valid(_eye_menu):
		_eye_menu = EYE_PANEL_SCRIPT.new()
		_eye_menu.name = "EyeMenu"
		add_child(_eye_menu)
		(_eye_menu as Control).connect("duration_selected", _on_eye_duration_selected)
	(_eye_menu as Control).call("build", EYE_DURATIONS, EYE_DURATIONS.find(EYE_DEFAULT_DURATION),
		func(i: int) -> String:
			# 批次 Y（Y-C4）：章节感知计费——第 5 关显示 0 天赋值（免费）。
			return I18n.t("%.1f 秒（%d 天赋值）") % [float(EYE_DURATIONS[i]), eye_cost_for_chapter(_chapter, float(EYE_DURATIONS[i]))])   # I18n
	(_eye_menu as Control).call("open_at", eye_btn.get_global_rect().position + Vector2(0.0, eye_btn.size.y))

## P4：收起面板（点选回调共用；hide 不释放——懒复用与旧 _eye_menu 缓存口径一致）。
func _close_eye_menu() -> void:
	if _eye_menu != null and is_instance_valid(_eye_menu):
		(_eye_menu as Control).call("close")

## 菜单选择回调：按档位开启锐眼。P4：点选即收（PopupMenu id_pressed→自动收起同款语义）。
func _on_eye_duration_selected(idx: int) -> void:
	if idx < 0 or idx >= EYE_DURATIONS.size():
		return
	_close_eye_menu()
	_start_eye(float(EYE_DURATIONS[idx]))

## 开启锐眼：扣费（失败提示不动）→ 红绿差集显示 → 到时自动关闭。返回是否成功。
## 激活中再次开启 = 按新时长扣费，成功后才清旧效果（_finish_eye）重开（不叠加计费）；
## 扣费失败直接提示并保留旧效果继续显示（批次 H P3-1：旧顺序先清旧再扣费，
## 失败会丢失已付费的剩余差集显示）。
## 批次 Y（Y-C4）：TODO 已清偿——第 5 关免费（eye_cost_for_chapter=0 不扣费），流程不变。
func _start_eye(duration: float = EYE_DEFAULT_DURATION) -> bool:
	if _input_locked or _success_started or _settled:
		return false
	if duration <= 0.0:
		_show_fail_hint(I18n.t("锐眼时长非法（需大于 0 秒）"))
		return false
	if _target_shape0.is_empty() or _main_voxel_view() == null:
		_show_fail_hint(I18n.t("锐眼不可用：关卡数据缺失"))
		return false
	var cost := eye_cost_for_chapter(_chapter, duration)
	if cost > 0 and not SaveManager.spend_talent(cost):
		_show_fail_hint(I18n.t(EYE_HINT_POOR) % [cost, SaveManager.get_talent()])   # I18n：模板键 t()
		return false
	_finish_eye()  # 重开路径：扣费成功后才清旧（避免 mark/ghost 叠加；失败时保留旧显示）
	_set_focus(false)  # P2-1 审查回修：锐眼→聚焦方向互斥补齐（spec §10.5 双向；此前仅聚焦→锐眼单向）
	_eye_active = true
	_eye_remaining_sec = duration
	_refresh_eye()
	return true

## 重算并应用差集（激活期间挖除/撤销/重做/选区变化后实时调用）：
## 上一轮 mark 按选区状态复位（选中格恢复绿色高亮）→ 重打多余=红 mark、缺少=绿 ghost。
## N批消费口径：diff_vs_target 已按 48 变换最佳变换口径返回玩家坐标系下的 extra/missing
## （spec §6.1），等价形状 → 红绿皆空；红 mark=玩家实际多余格、绿 ghost=玩家系缺失位。
func _refresh_eye() -> void:
	for c: Variant in _eye_marked.keys():
		var cell: Vector3i = c
		_set_cell_mark(cell, false)
		if _selected.has(cell):
			_set_cell_highlight(cell, true)
	_eye_marked.clear()
	if not _eye_active:
		return
	var vv := _main_voxel_view()
	if vv == null:
		return
	# 批次 W（P2-8，规格 §7）+ P2 审查缺陷修复：分域过滤——t 按 target 域尺寸
	# （_target_size 缓存，缺省回落 _voxel_size=blocks 域）、p 按 blocks 域尺寸（_voxel_size；
	# 未构建回落 size 即旧口径）。evaluate_join 按格坐标不动；三视图渲染/level_library 按域净化
	# 链对齐。现网档 target_size=block_size 时与旧口径逐字节等价；target_size<block_size 的
	# 自建档不再把 blocks 域越 target 域的玩家格剔出差集（少显红/归一偏移根治）。
	var diff: Dictionary = diff_vs_target(_remaining, _target_shape0,
		_target_size if _target_size.x > 0 else _voxel_size,
		_voxel_size)
	for c: Variant in (diff["extra"] as Array):
		var cell: Vector3i = c
		if _selected.has(cell):
			continue  # 选中格以绿色高亮优先，不与红 mark 抢材质槽
		_set_cell_mark(cell, true)
		_eye_marked[cell] = true
	# W9-10（批次 AA 规格 §12 P3-10②）：幻影格钳制到 blocks 包围盒——批次 W P2-8 后差集过滤域
	# 改 target 域（target_size>block_size 的自建档），missing 经逆变换映射回玩家系时可越出
	# blocks 包围盒；level_voxel_view 幻影 no_depth_test=true 会把这些越界格「浮空」渲染在木料外。
	# 故送显前裁剪到 _voxel_size（blocks 域）；size 非正（视图未构建）→ 全裁不渲染。
	vv.call("show_ghosts", clip_to_blocks(diff["missing"], _voxel_size))

## W9-10（P3-10②）：把格集裁剪到 size 包围盒内（保序、越界/负值丢弃）；size 非正 → 空集。
func clip_to_blocks(cells: Array, size: Vector3i) -> Array:
	if size.x <= 0 or size.y <= 0 or size.z <= 0:
		return []
	var out: Array = []
	for c_v: Variant in cells:
		if not (c_v is Vector3i):
			continue
		var c: Vector3i = c_v
		if c.x < 0 or c.x >= size.x or c.y < 0 or c.y >= size.y or c.z < 0 or c.z >= size.z:
			continue
		out.append(c)
	return out

## 关闭锐眼（到时自动/重开/成功流程开始）：恢复全部 mark 材质与 ghost。
func _finish_eye() -> void:
	_eye_active = false
	_eye_remaining_sec = 0.0
	for c: Variant in _eye_marked.keys():
		var cell: Vector3i = c
		_set_cell_mark(cell, false)
		if _selected.has(cell):
			_set_cell_highlight(cell, true)
	_eye_marked.clear()
	var vv := _main_voxel_view()
	if vv != null:
		vv.call("clear_ghosts")

func _set_cell_mark(cell: Vector3i, on: bool) -> void:
	var vv := _main_voxel_view()
	if vv != null:
		vv.call("set_voxel_mark", cell, on)

# ==================== 批次 G：见证者（spec 8.6/3.2 皮肤刷新 / 浮动 / 气泡） ====================

## 皮肤切换联动（修批次 D P3：立绘不再只在 _ready 应用一次）。
func _on_skin_changed(_equipped_id: String) -> void:
	_apply_witness()

## 天赋值 HUD 随扣费/发放实时刷新（锐眼扣费、结算发放共用）。
func _on_talent_changed(new_total: int) -> void:
	talent_label.text = I18n.t("天赋值：%d") % new_total

## 当前见证者立绘路径（测试/调试用）。
func get_witness_texture_path() -> String:
	return _witness_texture_path

## 见证者逐帧动画（spec 3.2：缩小放大 + 上下浮动，纯装饰）与气泡自动隐藏。
## 用逐帧 delta 推进（树暂停时自然冻结，无独立 Timer/Tween 生命周期问题）。
func _tick_witness(delta: float) -> void:
	if not _witness_base_valid:
		_witness_base_pos = witness.position  # 首帧捕获布局基准位（锚点排版完成后）
		_witness_base_valid = true
	_witness_float_phase = fposmod(_witness_float_phase + delta * WITNESS_FLOAT_SPEED, TAU)
	witness.position = Vector2(_witness_base_pos.x, _witness_base_pos.y + sin(_witness_float_phase) * WITNESS_FLOAT_AMP)
	var s := 1.0 + sin(_witness_float_phase * 2.0) * WITNESS_BREATH_AMP
	witness.scale = Vector2(s, s)
	if _witness_bubble_open:
		_bubble_entry_tick(delta)  # Z3-6：入场动效推进（淡入+缩放弹跳，0.2s 内完成）
		_sync_bubble_y()  # M-D：气泡随浮动同 tick 同步（振幅内恒贴 4px 不穿头）
		_witness_bubble_timer -= delta
		if _witness_bubble_timer <= 0.0:
			_hide_witness_bubble()

## 点击见证者（左键按下）→ 弹/收气泡。
## 批次 AD §4.3.5：恢复 witness.gui_input 点击事件弹出/收起气泡
## 批次 AD 审查回修 P2-5（2026-09-28）：首行补 `_input_locked` 锁——立绘交互双入口
##（MainView `_witness_bubble_dispatch` 分流 + 本直连接口）必须同锁：旧直连接口缺门，
## 成功动画锁定期（_input_locked=true）点立绘仍可弹泡，与「立绘交互只受 _input_locked
## 约束」的 W9-9 语义相悖（主视图入口有锁、直连入口裸奔=双入口不一致）。
func _on_witness_gui_input(event: InputEvent) -> void:
	if _input_locked:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_toggle_witness_bubble()

## 批次 Y（Y-C8）：加载台词洗牌袋。缺文件/空池 → 袋内池空（next_line 返回 ""=不弹+告警不崩）。
func _load_witness_lines(path: String) -> void:
	_bubble_bag = BubbleBag.new()
	_bubble_bag.load_path(path)

## 批次 Y（Y-C8）：测试/走查钩子——重定向台词源（res://剧情对话/ 档归 Y4 域，
## 测试用 tests/fixtures 夹具，不在该目录建改任何文件）。
func load_witness_lines_from_path(path: String) -> void:
	_load_witness_lines(path)

## 批次 Y（Y-C8）：当前台词池副本（测试断言用；袋未建/池空返回 []）。
func get_witness_lines_pool() -> Array:
	return _bubble_bag.pool() if _bubble_bag != null else []

func _show_witness_bubble() -> void:
	# 批次 Y（Y-C8）：台词改洗牌袋抽取（整轮不重复、轮尽重洗）；旧顺序轮换
	# WITNESS_BUBBLE_LINES[_witness_bubble_line % 8] 退役（旧 8 条逐字留痕见常量段）。
	# 防御：袋未建/池空/缺文件 → next_line()="" → 不弹（bag 已 push_warning，不崩）。
	var line := ""
	if _bubble_bag != null:
		line = _bubble_bag.next_line()
	if line == "":
		return
	_witness_bubble_open = true
	_witness_bubble_timer = WITNESS_BUBBLE_SECONDS  # Z3-6：4s 自灭口径不变（入场含在 4s 内）
	witness_bubble.text = line   # Z3-6：弹出即整句（不做打字机）
	witness_bubble.visible = true
	# Z3-6 入场动效起点：a=0、scale=起始档、进度槽归零（首帧 _tick_witness 起推进）
	_bubble_entry_t = 0.0
	_apply_bubble_entry(0.0)
	_sync_bubble_y()  # M-D：弹出即贴「可见头顶 − 4px」（后续由 _tick_witness 同 tick 同步）

func _hide_witness_bubble() -> void:
	_witness_bubble_open = false
	_witness_bubble_timer = 0.0
	_bubble_entry_t = -1.0          # Z3-6：入场进度复位（下次弹出重新入场）
	witness_bubble.modulate.a = 1.0 # Z3-6：终态卫生（防隐藏后残留透明/缩放）
	witness_bubble.scale = Vector2.ONE
	witness_bubble.visible = false

## Z3-6：入场动效逐帧推进（0.2s 内完成；完成后进度槽置 -1、终值归 a=1/scale=1）。
func _bubble_entry_tick(delta: float) -> void:
	if _bubble_entry_t < 0.0:
		return
	_bubble_entry_t += delta
	_apply_bubble_entry(_bubble_entry_t)

## Z3-6：入场动效应用（t=已进行秒数）。淡入 a 线性 0→1；scale 两段弹跳
## 起 0.72 → 0.12s 过冲 1.06 → 0.2s 回落 1.0。**不设 pivot**（缩放原点恒 (0,0)）——
## 非零 pivot×非单位 scale 平移 global_position（pivot·(1−s)），会击穿既有贴顶几何契约
## （见常量段 Godot 4.7 实证注记；_sync_bubble_y 每帧回写 position，位置恒定不随 scale 漂）。
func _apply_bubble_entry(t: float) -> void:
	var k := clampf(t / WITNESS_BUBBLE_ENTER_SEC, 0.0, 1.0)
	var s := 1.0
	if k < 0.6:
		s = lerpf(WITNESS_BUBBLE_ENTER_SCALE, WITNESS_BUBBLE_BOUNCE_SCALE, k / 0.6)
	else:
		s = lerpf(WITNESS_BUBBLE_BOUNCE_SCALE, 1.0, (k - 0.6) / 0.4)
	witness_bubble.scale = Vector2(s, s)
	witness_bubble.modulate.a = k
	if k >= 1.0:
		_bubble_entry_t = -1.0
		witness_bubble.modulate.a = 1.0
		witness_bubble.scale = Vector2.ONE

# ==================== 批次 G：退出（spec 3.10/5.1 重玩回图鉴 / 正常回主菜单） ====================

## TopBar 退出（正常流程）：确认后回主菜单；成功动画/结算路由期间拒绝。
func _on_exit_pressed() -> void:
	if _input_locked or _success_started or _settled:
		return
	_ask_exit(Game.State.MAIN_MENU, I18n.t(EXIT_MENU_TEXT))   # I18n

## 批次 Y（Y-A3，spec §2-③拍板一）：**手势倒数专属退出入口**——关卡内双手翻转倒数计 0 时
## Router 直调本方法（不再走 _on_exit_pressed 二次确认，两入口不共用方法：手动 TopBar 二次
## 确认语义保持现状不受影响）。直连回主菜单；退出前主动落盘一次挖除断点（flush_checkpoint，
## 「2s 实时自动存档兜底」之上的显式一次；_settled 守卫防把通关态重写成断点）；goto_state
## 触发 state_changed → Router.reset_runtime 相关清理（tracker/描边/笔画/armed 一并清零）。
func gesture_exit_to_menu() -> void:
	if _input_locked or _success_started or _settled:
		return
	flush_checkpoint()
	Game.goto_state(Game.State.MAIN_MENU)

## 左下退出（仅图鉴重玩可见）：确认后回图鉴（spec 3.10/Q&A10）。
func _on_exit_replay_pressed() -> void:
	if _input_locked or _success_started or _settled:
		return
	_ask_exit(Game.State.CATALOG, I18n.t(EXIT_CATALOG_TEXT))   # I18n

## 弹统一确认条并挂起目标状态（Game 未 attach 的环境同样只改状态机、不加载场景，见 game.gd 守卫）。
## 批次V（V-C5，spec §3.2）：Game.confirm 接口（文案逐字沿用既有中文文案，杜绝英文默认窗口
## 标题语义由「文案即条全文」承接）；确认=按挂起目标路由，取消/×=作废挂起路由（零副作用）。
func _ask_exit(target: int, text: String) -> void:
	Game.confirm(text, _on_exit_confirmed, _on_exit_canceled)
	# 批次 Z（Z6-P1-3，spec §6）：挂起态写入必须在 Game.confirm **之后**——TopStrip.push_confirm
	# 会先补调旧条 on_canceled（批次 W P2-7 契约），若先写 target，连点两次「退出」时旧
	# _on_exit_canceled 会把第二轮目标写废成 -1 → 新条确认空转（复现：退出→确认条出现→
	# 再点退出→条重建→点「确认」无反应）。取消/确认回调语义零变化。
	_pending_exit_state = target

## 取消回调：作废挂起路由（原弹窗 canceled lambda 语义逐字保持）。
func _on_exit_canceled() -> void:
	_pending_exit_state = -1

## 确认回调：按挂起目标路由（一次性消费，防止重复触发）。
## N9（spec §6.11 写档检查点①）：退出确认路径先落挖除断点再 goto_state——用户实测
## 「关内退出回来进度没体现」的根因之一（退出三路径原全程零 SaveManager 调用）。
## N11 等价替换留痕（批次 W 规格 §3）：_save_level_checkpoint() 直调改走 flush_checkpoint()
## ——同落盘（幂等省写）+清脏+「_settled」守卫（调用点由 _on_exit_pressed/_ask_exit 守卫未通关，
## 语义等价）；防同帧防抖分支二次触发。
func _on_exit_confirmed() -> void:
	if _pending_exit_state < 0:
		return
	var target := _pending_exit_state
	_pending_exit_state = -1
	flush_checkpoint()
	# 批次 AA 回修4（W5-P2-1）：关卡自己的「退出(回图鉴)」路径置来源标记——game.gd 依
	# 「old==LEVEL ∧ 图鉴进入 ∧ from_level_exit」跳过入栈（LEVEL↔CATALOG 乒乓阻断保持）；
	# 关卡内设置→图鉴（settings_panel._on_catalog）不置标记、正常入栈，退出图鉴可返回
	# 该关卡（O5 语义恢复，嵌套链修复）。
	if target == Game.State.CATALOG:
		Game.goto_state(target, {"from_level_exit": true})
	else:
		Game.goto_state(target)

# ==================== 批次 D 遗留接口 ====================

## 测试钩子：三视图已构建体素总数（Main+Target+Join）
func get_built_voxel_count() -> int:
	var total := 0
	for vp: SubViewport in [main_viewport, target_viewport, join_viewport]:
		var vv: Node = vp.get_node_or_null("VoxelView")
		if vv != null:
			total += int(vv.call("get_voxel_count"))
	return total

# ==================== 批次 F：对接判定 / 计时评级 / 成功动画 / 结算路由 ====================

## 对接判定（纯静态；批次 N1 起 spec §6.1：48 种正交变换全等价——「木块不分正反，形状一致
## 即通关」，用户 2026-09-09 拍板）。判定顺序（关键）：
## - remaining（键=Vector3i 或字符串坐标的 Set）为空 → "wrong"（空块无物可接，保证非 success）；
## - remaining 平移归一（各自包围盒最小角→原点，见 JoinXform.normalize_cells）后经 48 种正交
##   变换（24 旋转 det=+1 + 24 镜像 det=−1，JoinXform.are_equivalent）之一与任一 target_shapes[i]
##   平移归一集合相等 → "success"（即使此时 remaining 与 join_voxels 在原坐标有交叠也算成功
##   ——翻转/镜像挖法与固定件干涉不再误判「无法对接」，用户实测场景）；
## - 否则 remaining 与 join_voxels **在原坐标有交集**（不平移归一，既有口径不变）→ "unfit"
##   （无法对接：与固定件干涉，插不进）；
## - 否则 → "wrong"（答案错误：能放上但形状不是答案）。
## 元素兼容 Vector3i/Vector3/"x,y,z" 字符串，非法元素跳过。判定瞬时完成、无容差、无次数限制。
static func evaluate_join(remaining: Dictionary, target_shapes: Array, join_voxels: Array) -> String:
	var p := _cell_set(remaining.keys())
	if p.is_empty():
		return JOIN_WRONG
	for shape_v: Variant in target_shapes:
		if shape_v is Array and JoinXform.are_equivalent(p, _cell_set(shape_v)):
			return JOIN_SUCCESS
	var j := _cell_set(join_voxels)
	for k: Variant in p:
		if j.has(k):
			return JOIN_UNFIT
	return JOIN_WRONG

const _BAD_CELL := Vector3i(1 << 21, 1 << 21, 1 << 21)  # 非法坐标哨兵（远离合法网格）

## 坐标元素归一化为 Vector3i 集合：Vector3i/Vector3/"x,y,z" 字符串；非法跳过（去重靠字典键）。
static func _cell_set(cells: Array) -> Dictionary:
	var out: Dictionary = {}
	for v: Variant in cells:
		var c := _parse_cell(v)
		if c != _BAD_CELL:
			out[c] = true
	return out

static func _parse_cell(v: Variant) -> Vector3i:
	if v is Vector3i:
		return v
	if v is Vector3:
		return Vector3i(v)
	if v is String:
		var parts: PackedStringArray = (v as String).split(",")
		if parts.size() != 3:
			return _BAD_CELL
		return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
	return _BAD_CELL

# N批：evaluate_join 旧私有辅助 _sets_equal 已废止——集合相等/等价判定统一收敛到
# scripts/join_transform.gd（JoinXform.sets_equal / are_equivalent，单一真相源）。

## 评级（spec 8.5：完美 ≤3 分钟全额；良好 ≤6 分钟 80%；及格=完成即有 60%）。
static func grade_for_time(elapsed: float) -> String:
	if elapsed <= GRADE_TIME_PERFECT:
		return "perfect"
	if elapsed <= GRADE_TIME_GOOD:
		return "good"
	return "pass"

## 章节天赋值 = 完美档 [100,200,400,800,1600]（spec 8.5）× 评级比例（1.0/0.8/0.6）。
## 注：任务单备注「第 1 章基础 60/48/36」与 spec 8.5 表格冲突，按任务单约定以 spec 为准。
static func talent_for_grade(chapter: int, grade: String) -> int:
	var idx := clampi(chapter - 1, 0, CHAPTER_PERFECT_TALENT.size() - 1)
	var mult: float = float(GRADE_MULT.get(grade, 0.6))
	return int(round(float(CHAPTER_PERFECT_TALENT[idx]) * mult))

static func grade_name(grade: String) -> String:
	# I18n：评级名显示点 t()（GRADE_NAMES 常量表=中文键不动；映射外原样返回）。
	return I18n.t(String(GRADE_NAMES.get(grade, grade)))

## 计时展示 mm:ss（mm 不封顶，超一小时显示 62:05 属预期）。
static func format_time(seconds: float) -> String:
	var s := maxi(int(seconds), 0)
	return "%02d:%02d" % [int(s / 60.0), s % 60]

## 对接按钮：evaluate_join 三分支（spec 5.2 JUDGE）。失败仅提示不改状态、无惩罚、次数不限。
func _on_join_pressed() -> void:
	if _input_locked or _success_started or _settled or _level.is_empty():
		return
	var pieces: Array = (_level.get("data", {}) as Dictionary).get("pieces", [])
	if pieces.is_empty():
		return
	var piece: Dictionary = pieces[0]
	var targets: Array = piece.get("target_shapes", [])
	var join_vox: Array = (piece.get("join_part", {}) as Dictionary).get("voxels", [])
	match evaluate_join(_remaining, targets, join_vox):
		JOIN_SUCCESS:
			_begin_success()
		JOIN_UNFIT:
			_show_fail_hint(I18n.t("无法对接：木料与固定件干涉，请调整挖除位置"))
		JOIN_WRONG:
			_show_fail_hint(I18n.t("答案错误：当前形状与目标不一致"))

func is_input_locked() -> bool:
	return _input_locked

## 批次 R（spec §5.5）：聚焦态只读转发——手势聚焦前置判定消费（公开既有状态，非新通道）
func is_focus_active() -> bool:
	return _focus_active

## 测试钩子：直接设置剩余体素集（跳过逐格删除；不动撤销/重做栈）。
func set_remaining_for_test(cells: Array) -> void:
	_remaining.clear()
	for c: Variant in cells:
		var cell := cell_v_to_i(c)
		_remaining[cell] = true
	_update_hint()
	_update_voxel_label()  # M-E：顶栏计数同步（测试直驱路径）
	if _eye_active:
		_refresh_eye()  # 批次 G：剩余集变化后差集同步（测试直驱路径）

static func cell_v_to_i(v: Variant) -> Vector3i:
	var c := _parse_cell(v)
	return c if c != _BAD_CELL else Vector3i(-1, -1, -1)

## 批次 AA（W7-6，规格 §10.3）：关卡游玩四钮（锐眼/对接/退出/重玩退出）禁用态**单一写手**。
## `_begin_success` 一次性锁四钮（批次 G 语义保持）；`restore_play_buttons()` 为**显式恢复
## 入口**——同场景重入/返回等路径需要恢复四钮可点态时走它，不再散落逐钮赋值（旧码四处直赋、
## 无恢复路径，见 §10.2 R7-3 排除项注记）。四钮引用均 @onready，未就位时逐钮判空跳过。
## 注：本方法只管四钮可点态；`_success_started`/`_input_locked`/结算展示等状态标志归
## `_begin_success`/`_goto_settle`/`_enter_settle_direct` 语义，不在本方法职责内（场景重建
## 是现行唯一真实重入路径，四钮于新实例天然可点——测试段 W7-6③ 护栏锁定）。
func _set_play_buttons_disabled(v: bool) -> void:
	for b: Button in [eye_btn, join_btn, exit_btn, exit_replay_btn]:
		if b != null:
			b.disabled = v

## W7-6 显式恢复入口：四钮恢复可点（幂等，未禁用时调用零变化）。
func restore_play_buttons() -> void:
	_set_play_buttons_disabled(false)

## 对接成功：停表 → 锁定输入 → 成功动画（spec 8.4：首/重玩都播、不可跳过）。
func _begin_success() -> void:
	if _success_started or _settled:
		return
	_success_started = true
	_input_locked = true
	_final_elapsed = (Time.get_ticks_msec() - _start_ms) / 1000.0
	_set_play_buttons_disabled(true)  # 批次 G：重玩退出同样锁定（防误触离开成功流程）；W7-6 收口单点
	_finish_eye()  # 批次 G：成功流程开始即关闭锐眼（恢复 mark/ghost，不留到动画里闪烁）
	# K6-7：成功动画开始强制退聚焦（spec §10.5 互斥收口）——M-Gb 起走 deactivate_immediate
	# （跳过 RETURN 收回观感：所有体素随即在消散段逐格隐藏，慢速收回会与逐格隐藏打架）
	for fx: Node in [_fx_main, _fx_target, _fx_join]:
		if fx != null:
			fx.call("deactivate_immediate")
	_focus_active = false
	_update_focus_btn()
	for view: String in ["Main", "Target", "Join"]:
		_set_hover(view, NO_CELL)  # M-E 追2：成功动画开始三视图点光复位（输入锁定后不再刷新）
	clear_selection()
	_update_hint()  # 复位提示文案与警示色（失败提示不带入成功动画段）
	timer_label.text = format_time(_final_elapsed)
	# M-Gb：气泡 hover 光晕层随消散一并淡出（不在子树清单时懒创建可能未建，get_node 兜底）
	var bglow := get_node_or_null("WitnessBubbleGlow") as CanvasItem
	if bglow != null:
		bglow.modulate.a = 0.0
	# N4（spec §6.6 方案口径 2）：Fisher-Yates 逐体素随机隐藏序废止——三视图木块按
	# Main/Target/Join 分组统一凝聚（同视图体素同步），体素隐藏时点改由 N3 管线在凝聚完成时
	# 统一接管（_play_success_anim 内 activate_channel_all 三通道；凝聚段起点=体素实体在屏，
	# spec §九风险 9）。等价替换留痕：原 M-Gb 固定种子 20260907 随机序游标（_dissolve_cells/
	# _dissolved_i/_dissolve_progress）随四段式重做废止。
	_success_seg = SuccessSeg.CONDENSE
	_play_success_anim()

## N4 相位钩子（测试断言面）：0 凝聚 / 2 聚合 / 3 回看（「持续+散开」由 N3 全屏管线相位承载，
## 无独立 level 侧 seg 值——N12b P3-2 起 HOLD_SPREAD 死枚举值已删，编号钉死保 N4 契约）。
func get_success_seg() -> int:
	return _success_seg

## 成功动画四段式（N4，spec §6.6；spec 8.4 硬约束不变：首/重玩都播、不可跳过、
## 总时长 0.25+0.5+1.2+1.1+0.9=3.95s ∈[2.5,4]，P批波2 平衡档）。等价替换留痕：M-Gb 三段式（消散撒点+
## Fisher-Yates 逐格隐藏 0.9 / 边缘环聚合 1.5 / 自转回看 1.2）废止；N批 3.7s 档随 O批「凝聚持续
## 0.5s」平衡废止；O批 3.55s 档随 P批波2「散开放慢+滞空」重排废止——四段式：
## ①凝聚 0.25s：三视图木块按 Main/Target/Join **分组统一** 实体→密集粒子面（复用 N3 全屏
##   三色管线 activate_channel_all + O批全金覆写；凝聚完成才统一隐藏体素=无空窗跳变；UI
##   modulate 并行淡出）；
## ②持续 0.5s+突然散开 1.2s：粒子面稳态保持后**放慢+滞空缓动**逃出屏幕（P批波2 用户口径
##   P-C「散开要比现在慢很多、有滞空的感觉」；O批屏外环域目标位保持）；
## ③聚合 1.1s：同一批粒子在散开末帧逐点接力采样（relay_sample，计数以文物点云为准）后
##   聚成**结算挂载位**单一金色建模（O批⑤位置统一：原「屏幕中心聚合」废止——建模只在
##   结算建模位一处形成，无聚合后再平移的二次跳变；无清场重来、无空窗，风险 9/10）；
## ④回看 0.9s：建模绕 Y 自转（独立 SpinPivot，坑 9）+ 玩家拖拽旋转（专用输入通道，
##   不解锁 _input_locked）→ 结算 UI 从下往上淡入（P批波2 P-D：原「末段 ANIM_ALIGN 姿态
##   对位→切 settle 场景」废止——建模保持玩家姿态直入结算，零重建零回正零切换）。
func _play_success_anim() -> void:
	var k := anim_time_scale if anim_time_scale > 0.0 else 1.0
	_build_success_overlay()  # 覆盖层立即建立（对位参数定格+建模预构建，聚合段无构建 hitch）
	# ①②凝聚+持续+散开：N3 全屏三色管线承载（覆盖值按 time_scale 折算后写入相位机）。
	# O批（用户口径④）：成功动画三通道全金覆写（override_color=CLOUD_TINT）——凝聚/散开全程
	# 金黄「无论左上/右上/中间」；聚焦路径不传覆写=三色语义不变（区分左上/右上颜色）。
	var fx := _fx_layer
	if fx != null and fx.has_method("activate_channel_all"):
		fx.set("n4_condense_time", ANIM_CONDENSE / k)
		fx.set("n4_hold_time", ANIM_HOLD / k)
		fx.set("n4_spread_time", ANIM_SPREAD / k)
		fx.call("activate_channel_all", "Main", _remaining.keys(), CLOUD_TINT)
		fx.call("activate_channel_all", "Target", null, CLOUD_TINT)   # null=通道 VoxelView 全量构建格
		fx.call("activate_channel_all", "Join", null, CLOUD_TINT)
	_anim_tween = create_tween()
	var seg12 := (ANIM_CONDENSE + ANIM_HOLD + ANIM_SPREAD) / k
	_anim_tween.tween_interval(seg12)  # 步1：①②由 N3 相位机推进（凝聚→持续→散开）
	_anim_tween.set_parallel(true)     # UI 淡出与等待并行（贯穿①②，M-Gb 淡出口径保持）
	for n: CanvasItem in _dissolve_ui_nodes():
		_anim_tween.tween_property(n, "modulate:a", 0.0, seg12)
	_anim_tween.set_parallel(false)
	# ③聚合：散开末帧逐点接力 → 单一金色建模
	_anim_tween.tween_callback(_begin_aggregate)
	_anim_tween.tween_method(_cloud_progress, 0.0, 1.0, ANIM_AGGREGATE / k)
	# ④回看：自转+拖拽 → 结算 UI 就地淡入（P批波2：对位/切场景废止，零重建零回正零切换）
	_anim_tween.tween_callback(_begin_review)
	_anim_tween.tween_method(_review_progress, 0.0, 1.0, ANIM_REVIEW / k)
	_anim_tween.tween_callback(_goto_settle)

## ③聚合段启动（tween 回调，与②散开完成同帧衔接）：粒子贯穿接力。
## 顺序纪律：先采样 N3 散点末帧屏幕位（get_channel_screen_positions，O批=屏外散点位）→
## 写入覆盖层建模起点并显示 → 再 release_particles 清 N3 层（**不还原体素**，spec §九风险 10
## 生命周期移交）——同帧换手，帧间无全黑帧。
## O批⑤（位置统一）：SpinPivot 常驻结算挂载位（_review_center==_mount_world，聚合段建模
## 直接在挂载位成形）→ 接力起点按 pivot-local 换算（散点世界位−pivot 平移），起点=屏外散点位
## 语义不变。
func _begin_aggregate() -> void:
	_success_seg = SuccessSeg.AGGREGATE
	if _fx_layer != null and _fx_layer.has_method("release_particles"):
		if _cloud_mm == null or _cloud_inst == null:
			_fx_layer.call("release_particles")  # 点云缺失静默降级：散点直接清场按原节奏结算
			return
		var flat := PackedVector2Array()
		for id: String in ["Main", "Target", "Join"]:  # 固定序=构建填充序（通道区间稳定）
			flat.append_array(_fx_layer.call("get_channel_screen_positions", id))
		var starts_px := relay_sample(flat, _cloud_mm.instance_count)
		# 接力空群回退位=结算挂载中心屏幕位（O批⑤：原地成形=在挂载位成形，非屏幕中心）
		var fallback_px: Vector2 = _align.get("center", _cloud_vsz * 0.5)
		var pivot_off: Vector3 = _spin_pivot.position if _spin_pivot != null else Vector3.ZERO
		var n := _cloud_starts.size()
		for i: int in n:
			# 散开末帧屏幕位 → 覆盖层世界（世界原点=屏幕中心，y 翻转，1 世界单位=_cloud_k px）
			# → SpinPivot 本地位（O批：pivot 常驻挂载位，需减 pivot 平移）
			var px := starts_px[i] if i < starts_px.size() else fallback_px
			_cloud_starts[i] = Vector3((px.x - _cloud_vsz.x * 0.5) / _cloud_k,
				(_cloud_vsz.y * 0.5 - px.y) / _cloud_k, 0.0) - pivot_off
			_cloud_mm.set_instance_transform(i, Transform3D(Basis(), _cloud_starts[i]))
		_cloud_inst.visible = true
		_fx_layer.call("release_particles")  # 同帧移交（不还原体素——体素保持隐藏）

## ④回看段启动（tween 回调）：初始姿态=结算建模初始朝向（聚合段即按此姿态成形）。
## P批波2：末段对位启动逻辑随「不回正不重建」废止——回看段全程自转（拖拽即接管），
## 建模以玩家旋转后的姿态直入结算（结算 UI 由覆盖层承载，无第二次建模无回正）。
func _begin_review() -> void:
	_success_seg = SuccessSeg.REVIEW
	_rev_yaw = deg_to_rad(SETTLE_INIT_YAW)
	_rev_pitch = deg_to_rad(SETTLE_INIT_PITCH)
	_rev_auto = true
	_rev_dragging = false
	_apply_review_pose()

## ④回看段逐帧（tween_method 0→1）：全程自转窗口（P批波2等价替换：原「自转窗口+末段
## ANIM_ALIGN 对位窗口（姿态 lerp 至结算 30/22+平移 lerp）」废止留痕——位置本就统一
## （O批⑤ _review_center==_mount_world，平移 lerp 恒等无对象）、姿态不再回正（用户口径
## 「建模旋转了结算界面又自动回正」根因消除），结算 UI 淡入时保持当前姿态。
func _review_progress(t: float) -> void:
	if _spin_pivot == null:
		return
	if _rev_auto:
		_rev_yaw = deg_to_rad(SETTLE_INIT_YAW) \
			+ deg_to_rad(SPIN_SPEED_DEG * ANIM_REVIEW) * clampf(t, 0.0, 1.0)
	_apply_review_pose()

## 回看段位姿应用（自转/拖拽共用）。相机**固定于屏幕中心轴**（0,0,dist）：
## P批波2：对位平移分支废止——SpinPivot 常驻结算挂载位（O批⑤ _review_center==_mount_world
## 恒等），建模直接在挂载位成形并以玩家姿态直入结算（相机轴保持过屏幕中心的几何不变：
## 模型成像于轴上前方，屏位=轴心投影+pivot 偏移）。
func _apply_review_pose() -> void:
	if _spin_pivot == null:
		return
	_spin_pivot.rotation = Vector3(_rev_pitch, _rev_yaw, 0.0)
	if _anim_cam != null:
		_anim_cam.position = Vector3(0.0, 0.0, _align_dist)

## ④回看玩家拖拽旋转（spec §6.6 方案口径 5：成功动画专用轻量输入通道）——
## 走 _input（GUI 之前的专用轻量通道）：成功动画期间 UI 已淡出但容器节点仍在（STOP 过滤会
## 吞掉鼠标事件使其到不了 unhandled），回看段拖拽必须先于 GUI 消费；仅回看自转窗口生效，
## 其余事件零触碰（不消费不路由，键盘 Ctrl+Z/Esc 通道不受影响）；不触碰 _input_locked 与
## 挖除/对接交互（挖除/对接处理器各有 _input_locked/_success_started 守卫）。
## 返回是否消费（_input 据此 set_input_as_handled 防穿透）。
func _review_unhandled_input(event: InputEvent) -> bool:
	if not _success_started or _settled or _success_seg != SuccessSeg.REVIEW:
		return false
	# P批波2：对位窗口冻结拖拽分支废止（对位已删）——回看段全程可拖拽，玩家接管后停自转。
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		_rev_dragging = mb.pressed
		return true  # 回看段左键按下/抬起=拖拽通道事件（消费防穿透）
	var mm := event as InputEventMouseMotion
	if mm != null and _rev_dragging:
		_rev_auto = false  # 玩家接管（本次回看内自动自转停）
		var tilt_limit := float(_align.get("tilt_limit", 75.0))
		_rev_yaw += mm.relative.x * ORBIT_SPEED
		_rev_pitch = clampf(_rev_pitch + mm.relative.y * ORBIT_SPEED,
			deg_to_rad(-tilt_limit), deg_to_rad(tilt_limit))
		_apply_review_pose()
		return true
	return false

## 屏幕中心像素（覆盖层世界原点对应的屏幕位）。
func _screen_center_px() -> Vector2:
	return _cloud_vsz * 0.5

## P批波2等价替换留痕：_cloud_fade（失配回退淡出，风险 12）随对位机制废止删除——
## 对位参数收敛为单一真相源常量表后无失配态，建模恒成形直入结算。

## ①消散段 UI 淡出清单（spec §3.7 行为 4：顶栏/三面板/提示行/见证者等全 UI 元素；
## 背景/渐晕为场景层保留。WitnessBubbleGlow 系懒创建覆盖层，存在才加入）。
func _dissolve_ui_nodes() -> Array:
	var nodes: Array = []
	for path: String in ["TopBar", "MainView", "TargetView", "JoinView", "HintLabel",
			"WitnessPortrait", "WitnessBubble", "WitnessBubbleGlow", "ExitReplayButton"]:
		var n := get_node_or_null(path)
		if n is CanvasItem:
			nodes.append(n)
	return nodes

## ---- 批次 N4：同位续接对位工具（spec §6.6 方案口径 4 + §九风险 12；均纯函数可无头单测）----

## 挂载 rect 防御断言：非零且在屏内（±2px 容差）。失败 → 对位失配回退路径。
static func mount_rect_ok(rect: Rect2, vsz: Vector2) -> bool:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return false
	return rect.position.x >= -2.0 and rect.position.y >= -2.0 \
		and rect.end.x <= vsz.x + 2.0 and rect.end.y <= vsz.y + 2.0

## 结算投影匹配 fov（度，KEEP_HEIGHT 垂直口径）：覆盖层全屏视口与结算挂载视口渲染出相同的
## px/世界单位——tan(fov_o/2)·mount_h == tan(fov_s/2)·vsz_h。度量退化时原样返回。
static func settle_match_fov(fov_settle_deg: float, mount_h: float, vsz_h: float) -> float:
	if mount_h <= 0.0 or vsz_h <= 0.0 or fov_settle_deg <= 0.0:
		return fov_settle_deg
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(fov_settle_deg * 0.5)) * vsz_h / mount_h))

## 逐点采样接力（确定性）：文物点云第 i 点聚合起点=散开末帧散点群第 i mod m 点屏幕位
## （计数以文物点云为准，spec §6.6 方案口径 3；散点群空=返回空，聚合段回退原地成形）。
static func relay_sample(flat: PackedVector2Array, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if flat.is_empty() or n <= 0:
		return out
	out.resize(n)
	var m := flat.size()
	for i: int in n:
		out[i] = flat[i % m]
	return out

## 结算建模参数单点（read_settle_align 单点读取集中此处；键面与 N4 契约保持，消费方零改动）。
## P批波2 单一真相源重写（settle 场景退役不再被路由）：挂载 rect=SETTLE_MOUNT_ANCHORS×当前
## 视口直接计算，fov/视距/归一化/初始朝向/点径下限取本场景常量表——原「instantiate 结算场景
## live 读 viewer 构建参数 + 镜像兜底常量 + 失配回退」整套机制废止（用户口径 P-D：结算页面
## 再创一次建模致位置对不上/旋转回正的根因，随结算 UI 合并进覆盖层一并消除）。
## 输出键：ok/rect/center/mount_h/dist/fit/yaw/pitch/fov/point_size/tilt_limit/px_per_world/fov_overlay。
func read_settle_align(vsz: Vector2) -> Dictionary:
	var a := SETTLE_MOUNT_ANCHORS
	var rect := Rect2(vsz.x * a.position.x, vsz.y * a.position.y,
		vsz.x * a.size.x, vsz.y * a.size.y)
	var mh := maxf(rect.size.y, 1.0)
	var dd := maxf(SETTLE_CAMERA_DISTANCE, 0.1)
	var fov_s := SETTLE_FOV
	return {
		"ok": mount_rect_ok(rect, vsz),  # 防御断言保留（rect 非零且在屏内；常量表下恒真）
		"rect": rect,
		"center": rect.get_center(),
		"mount_h": rect.size.y,
		"dist": SETTLE_CAMERA_DISTANCE,
		"fit": SETTLE_FIT_SIZE,
		"yaw": SETTLE_INIT_YAW,
		"pitch": SETTLE_INIT_PITCH,
		"fov": fov_s,
		"point_size": SETTLE_POINT_SIZE_MIN,
		"tilt_limit": SETTLE_TILT_LIMIT,
		"px_per_world": mh / (2.0 * dd * tan(deg_to_rad(fov_s * 0.5))),
		"fov_overlay": settle_match_fov(fov_s, mh, vsz.y),
	}

## 构建成功动画全屏覆盖层（N4 重写；P批波2 增挂结算 UI）：CanvasLayer + SubViewport + 透视相机
## （结算投影匹配）+ SettleUI（结算界面覆盖层承载，见 _build_settle_ui）。
## 层级：AnimWorld ─ AnimCam（透视，fov=settle_match_fov 匹配档，跟随 SpinPivot 平移）
##                        └ SpinPivot ─ SuccessCloud（建模点云，结算 fit 口径世界空间）。
##        SettleUI（结算三 Label+下一关/退出钮+建模拖拽区，聚合完成后淡入——P-D 主路径）。
## 同位续接（spec §6.6 方案口径 4）：建模参数 read_settle_align 单点定格——建模归一化（fit
## 对角线口径）/点径/初始朝向（结算 30°/22°）与退役结算 viewer 同构成（P批波2 起参数单一
## 真相源常量表）；覆盖层相机 px/世界单位经 settle_match_fov 与结算挂载视口严格相等。
## O批⑤位置统一：SpinPivot 常驻结算挂载位——聚合段建模直接在结算建模位成形（P批波2 起
## 结算 UI 同覆盖层显示，建模保持玩家姿态直入结算，无二次建模无回正无切换）。
## O批⑦圆点化：SuccessCloud=QuadMesh+viewer 同源圆点 ShaderMaterial（手动 billboard+圆盘
## alpha，自转任意视角恒面向相机）；全金逐点色（O批④）。
## N4 等价替换留痕：M-Gb 正交像素空间（CLOUD_MODEL_HEIGHT=420px 归一/点径 3.2px/边缘环起点/
## _spawn_dissolve_dots 消散撒点）废止——凝聚/散开由 N3 全屏三色管线承载（风险 10 生命周期
## 移交），覆盖层只在聚合段承载建模。M批 StandardMaterial3D 材质载体随 O批圆点化升级
## （unshaded/逐实例色/α 淡出口径语义等价保留，见材质段注）。
func _build_success_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "SuccessOverlay"
	# P批波2走查回修：层 90→0。原 N4 定档 90（GlobalUI=1 之上）在「结算 UI 进覆盖层」后
	# 会把结算展示压在设置面板之上（edge_2 走查实证：模型/Label 盖住设置面板；同层 1 实测
	# 仍压面板——跨子树同层序不定）。定档 0=关卡内容同层：树序上 SuccessOverlay 晚于 FocusFX
	# 挂载（覆盖层压散点粒子 ✓）、设置面板/toast（GlobalUI 层 1）在结算展示之上（与退役
	# settle 场景同观感 ✓）。
	layer.layer = 0
	add_child(layer)
	var cont := SubViewportContainer.new()
	cont.name = "AnimContainer"
	cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vp := SubViewport.new()
	vp.name = "AnimViewport"
	vp.transparent_bg = true
	vp.own_world_3d = true  # N4：独立 3D 世界（同 FocusFX 层口径）——与关卡三视图/结算 viewer
							# 共享根世界会跨视口互渲（走查实测：结算场景共存帧互相成像出重影阶梯）
	# M-Gb 回修（探针实锤）：SubViewportContainer.stretch 默认 false → vp 保持默认 512×512，
	# 覆盖层像素空间整体错位。按根窗口可见区显式设 vp 尺寸 + stretch=true 跟随后续 resize。
	var world := Node3D.new()
	world.name = "AnimWorld"
	var vsz := get_viewport().get_visible_rect().size
	if vsz.y < 1.0:
		vsz = Vector2(1152, 648)  # 设计视口兜底
	_cloud_vsz = vsz
	vp.size = Vector2i(vsz)
	# N4：对位参数单点定格（先于相机/建模构建——二者均按对位口径配置）
	_align = read_settle_align(vsz)
	_cloud_k = float(_align.get("px_per_world", 1.0))
	_align_dist = float(_align.get("dist", SETTLE_CAMERA_DISTANCE))
	var cam := Camera3D.new()
	cam.name = "AnimCam"
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE  # N4：透视=与结算同构成（M-Gb 正交口径等价替换）
	cam.keep_aspect = Camera3D.KEEP_HEIGHT            # fov=垂直口径（与结算 viewer 一致）
	cam.fov = float(_align.get("fov_overlay", settle_match_fov(SETTLE_FOV,
		vsz.y * SETTLE_MOUNT_ANCHORS.size.y, vsz.y)))
	cam.near = 0.05
	cam.far = 50.0
	cam.position = Vector3(0.0, 0.0, _align_dist)  # 相机固定屏幕中心轴（O批：建模心=SpinPivot@挂载位，经投影成像于挂载位）
	world.add_child(cam)
	_anim_cam = cam
	var spin := Node3D.new()
	spin.name = "SpinPivot"
	spin.position = Vector3.ZERO
	# 初始姿态=结算建模初始朝向（聚合段即按此姿态成形；YXZ 欧拉序与 viewer _apply_view 同构）
	spin.rotation = Vector3(deg_to_rad(float(_align.get("pitch", 22.0))),
		deg_to_rad(float(_align.get("yaw", 30.0))), 0.0)
	world.add_child(spin)
	_spin_pivot = spin
	var center_px: Vector2 = _align.get("center", vsz * 0.5)
	_mount_world = Vector3((center_px.x - vsz.x * 0.5) / _cloud_k,
		(vsz.y * 0.5 - center_px.y) / _cloud_k, 0.0)  # 对位平移终点=结算挂载中心世界位
	# O批⑤（用户口径⑥位置统一）：聚合中心=结算挂载位——建模只在结算建模位一处形成（原
	# 「屏幕中心聚合→回看末平移到挂载位」双位口径废止，用户「最终建模位置要与结算页建模
	# 位置同一位」）；回看段对位平移 lerp 恒等保留（路径零改动，仅转向仍生效）。
	_review_center = _mount_world
	spin.position = _mount_world  # 聚合段起 SpinPivot 常驻挂载位（建模成形位=结算建模位）
	vp.add_child(world)
	cont.add_child(vp)
	cont.stretch = true  # M-Gb 回修：vp 尺寸跟随容器
	layer.add_child(cont)
	_build_settle_ui(layer)  # P-D：结算 UI 同覆盖层挂载（聚合完成后 _show_settle_ui 淡入）
	var points_path: String = LevelLibrary.get_points_path(_chapter)
	if not ResourceLoader.exists(points_path):
		push_warning("点云缺失: %s（跳过聚合展示，仍按节奏结算）" % points_path)
		return
	var data: PointCloudData = load(points_path)
	if data == null or data.points.is_empty():
		return
	var pts := data.points
	var n := pts.size()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	# O批⑦（用户口径①⑧「建模不流畅→圆点+尺寸调档」）：BoxMesh 方块点废止 → QuadMesh 圆点
	# 面片（4 顶点）+ viewer 同源圆点 ShaderMaterial（手动 billboard+圆盘 alpha——回看自转/
	# 拖拽任意视角恒面向相机）；点径=对位 point_size（结算实读经 DOT_SIZE_MIN 下限上调）。
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * float(_align.get("point_size", SETTLE_POINT_SIZE_MIN))  # N4：点径=结算同径（P批单一真相源下限档）
	mm.mesh = quad
	var use_color := data.colors.size() == n
	mm.use_colors = use_color  # 须在 instance_count 之前设置（坑 13）
	mm.instance_count = n
	# N4 归一化=结算 viewer 同口径：包围盒中心到原点、对角线缩放至 fit（M-Gb CLOUD_MODEL_HEIGHT
	# 最长边口径废止留痕——对角线口径使覆盖层与结算建模逐点重合，同位续接零尺度差）
	var sf := float(_align.get("fit", 2.2)) / maxf(data.aabb_size.length(), 0.001)
	_cloud_targets = PackedVector3Array()
	_cloud_targets.resize(n)
	_cloud_starts = PackedVector3Array()
	_cloud_starts.resize(n)
	_cloud_delay = PackedFloat32Array()
	_cloud_delay.resize(n)
	_cloud_colors = PackedColorArray()
	_cloud_colors.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260827
	for i: int in n:
		_cloud_targets[i] = (pts[i] - data.aabb_center) * sf
		_cloud_starts[i] = _cloud_targets[i]  # 真起点=散开末帧接力位（_begin_aggregate 写入；此前不可见）
		_cloud_delay[i] = rng.randf() * CLOUD_DELAY_MAX  # 逐点延迟分层（消「齐步走」，M-Gb 口径保持）
		mm.set_instance_transform(i, Transform3D(Basis(), _cloud_starts[i]))
		# O批④（用户口径④「全部点金黄色」）：全金覆写——原 M-Gb lerp(CLOUD_TINT, 0.85) 部分金
		# 口径废止留痕，数据色不再掺入（凝聚/散开/聚合建模全程纯金）。
		_cloud_colors[i] = CLOUD_TINT
		mm.set_instance_color(i, CLOUD_TINT)
	var inst := MultiMeshInstance3D.new()
	inst.name = "SuccessCloud"
	# O批⑦等价替换（M-Gb 黑膜修复口径保持，载体升级圆点 ShaderMaterial——与 point_cloud_viewer
	# 同源 CLOUD_SHADER_CODE）：unshaded ↔ render_mode unshaded（无光视口直接显色）；
	# vertex_color_use_as_albedo ↔ COLOR 透传（u_use_vertex_color）；TRANSPARENCY_ALPHA ↔
	# blend_mix+逐实例色 α 衰减（失配回退淡出前提保持，风险 12）；手动 billboard+圆盘 alpha。
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	var vset_o: Script = load(SETTLE_VIEWER_SCRIPT) as Script
	sh.code = String(vset_o.get_script_constant_map().get("CLOUD_SHADER_CODE", "")) if vset_o != null else ""
	mat.shader = sh
	mat.set_shader_parameter("u_use_vertex_color", 1.0 if use_color else 0.0)
	mat.set_shader_parameter("u_fallback_color", CLOUD_TINT)
	inst.material_override = mat
	inst.multimesh = mm
	inst.visible = false  # 聚合段才显示（_begin_aggregate 接力写入真起点后同帧置真）
	spin.add_child(inst)  # 挂 SpinPivot：④回看自转带动建模，不与轨道相机共节点（坑 9）
	_cloud_mm = mm
	_cloud_inst = inst

## N4 等价替换留痕：_spawn_dissolve_dots（M-Gb 消散撒点：UI 区域+逐体素中心金点，仅撒
## MainView 体素）废止——凝聚/散开由 N3 全屏三色管线承载（FocusFX._collect_channel_dots
## 统一生成器口径，三视图分组统一且 Target/Join 木块同样粒子化，用户拍板根因②）。

## 点云聚合逐帧插值（tween_method 0→1）：接力起点 lerp 到建模本体位。
## N4：起点=散开末帧三通道逐点接力屏幕位（_begin_aggregate 写入，覆盖层世界空间）；
## 逐点延迟分层（delay 0~CLOUD_DELAY_MAX）保持 M-Gb 口径——每点在自身窗口内推进，
## 未起飞点恰停在接力起点=散点群原位，聚合有先有后且观感连续。
func _cloud_progress(t: float) -> void:
	if _cloud_mm == null:
		return
	var n := _cloud_mm.instance_count
	for i: int in n:
		var d: float = _cloud_delay[i] if i < _cloud_delay.size() else 0.0
		var te := clampf((t - d) / maxf(1.0 - d, 0.001), 0.0, 1.0)
		_cloud_mm.set_instance_transform(i, Transform3D(Basis(), _cloud_starts[i].lerp(_cloud_targets[i], te)))

## 结算（P批波2 重做）：评级/天赋值/进度推进（spec 8.5 发放口径）→ 结算 UI 就地淡入。
## P-D①主路径零重建零回正零切换：不再 goto_state(SETTLE) 切场景（settle_scene 退役不再被
## 路由）——用户口径「结算页面再创一次建模导致位置对不上/旋转了又自动回正/没有过渡动画」
## 三问题一并消除：建模保持玩家旋转后的姿态继续可拖拽，结算 UI（评级/耗时/获得天赋值/
## 下一关/退出）在本场景覆盖层内从下往上淡入渐显；Game 侧经 mark_settle_entered 记账
## SETTLE 态（O5 catalog_return 快照/设置面板「经过 SETTLE 态」依赖保持兼容）。
## 落盘：add_talent/advance_progress/consume_replay_award 内部均自动 save（spec 7.1 通关结算后保存）。
func _goto_settle() -> void:
	if _settled:
		return
	_settled = true
	var grade := grade_for_time(_final_elapsed)
	var gain := talent_for_grade(_chapter, grade)
	var is_replay: bool = (SaveManager.get_progress().get("cleared", []) as Array).has(_chapter)
	if is_replay and not SaveManager.consume_replay_award(_chapter):
		gain = 0  # 重玩第 4 次起不再发放（spec 8.5/Q&A14）
	if gain > 0:
		SaveManager.add_talent(gain)
	SaveManager.advance_progress(_chapter)
	# N9（spec §6.11）：通关清该章挖除断点——通关=整章完成，挖除进度已无意义；advance_progress
	# 记账链路与调用点零改动（禁触红线），清账是新增显式一步（set_level_progress 幂等省写，
	# 无断点时不产生额外落盘）。语义取舍：删键而非留空数组——「没动=键缺省/空数组」两态等价，
	# 删键存储最少且防旧断点跨通关残留（如上会话退出存过断点、本会话通关须清除）。
	SaveManager.set_level_progress(_chapter, [])
	_checkpoint_dirty_at = -1  # N11：通关清账同步清脏（防后续防抖把通关态重写成断点）
	talent_label.text = I18n.t("天赋值：%d") % SaveManager.get_talent()
	_settle_data = {
		"chapter": _chapter,
		"grade": grade_name(grade),
		"score": gain,
		"elapsed": _final_elapsed,
		"talent": gain,
		"replay": is_replay,
	}
	# 批次 AA / W6-1（规格 §9.3）：结算快照写入 Game.settle_snapshot——边缘路径
	# （goto_state(SETTLE) 重建）与图鉴往返（入栈 ctx 合并，game._push_catalog_return）
	# 的生产数据源；_settled 恰一次守卫保证写入恰一次（R6-c）。独立字段，不回写
	# Game._context（防污染「进关上下文」语义，W6-1 决策）。
	Game.settle_snapshot = _settle_data.duplicate(true)
	_show_settle_ui(_settle_data)

# ==================== P批波2（P-D）：结算 UI（覆盖层承载，settle_scene 退役） ====================

## 结算 UI 淡入演出（用户口径「按钮字从下往上直接淡入渐显——从水里起来的那种感觉，稍微
## 偏移一点（不是完全从屏幕底出来），逐渐显现」）：各元素 alpha 0→1 + y 从 base+40px
## 缓出归位，三 Label/按钮 0.1s 级联错峰；建模（聚合段已成形的 SuccessCloud）保持当前
## 姿态不参与淡入。
func _show_settle_ui(data: Dictionary) -> void:
	if _settle_ui == null:
		return
	_settle_data = data
	Game.mark_settle_entered()  # P-D①：主路径记账 SETTLE 态（O5/图鉴 SETTLE 透传兼容）
	_apply_settle_labels(data)
	_apply_settle_theme()
	var ui := _settle_ui
	ui.theme = ThemeManager.current_theme()  # 坑 11：CanvasLayer 主题不传播，显式重赋
	ui.visible = true
	if _settle_tween != null and _settle_tween.is_valid():
		_settle_tween.kill()
	_settle_tween = create_tween()
	_settle_tween.set_parallel(true)
	for i: int in _settle_cascade.size():
		var el: Control = _settle_cascade[i][0]
		var rise: bool = bool(_settle_cascade[i][1])
		var delay := SETTLE_UI_STAGGER * i
		el.modulate.a = 0.0
		_settle_tween.tween_property(el, "modulate:a", 1.0, SETTLE_UI_FADE_TIME).set_delay(delay)
		if rise:  # 压暗层只淡入不位移（全屏 rect 位移会露底边）
			var base_y := el.position.y
			el.position.y = base_y + SETTLE_UI_RISE_OFFSET
			_settle_tween.tween_property(el, "position:y", base_y, SETTLE_UI_FADE_TIME) \
				.set_delay(delay).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_settle_tween.set_parallel(false)
	# 终审 P2-1（spec §5.1）：结算态手势面板切换——生产 SETTLE 态=本场景内结算（settle_scene
	# 退役不再路由），旧注册随之落在本场景：①三视图容器退出面板组（游玩 UI 已隐藏不可交互，
	# 其矩形仍覆盖挂载带会抢先命中）②本场景根以契约方法注册（gesture_panel_rect=建模挂载带
	# ModelDragArea 矩形、get_gesture_viewer→self 二指旋转与键鼠拖拽同写手，见结算契约段）。
	# 挂在 _show_settle_ui：主路径（_goto_settle）与边缘路径（_enter_settle_direct）唯一汇合点，
	# 且恰在 mark_settle_entered 置 SETTLE 态之后（语义分区 cloud 与面板组同帧生效）。
	for view_path: String in ["MainView/ViewportContainer", "TargetView/ViewportContainer", "JoinView/ViewportContainer"]:
		var view_cont: Node = get_node_or_null(view_path)
		if view_cont != null:
			view_cont.remove_from_group("gesture_panel")
	add_to_group("gesture_panel")

## 批次 AA / W6-2（规格 §9.3 W6-2）：断链留痕约定标记——grade/elapsed/talent 三字段
## 有缺失（Game.settle_snapshot 与 ctx 双缺才可能命中）即 push_warning 并记入
## _settle_break_log（数据断链不再静默降级；判据=告警文本含本标记，R6-b 红测锁定；
## 主路径 _goto_settle 产出恒齐套 → 正常路径零告警）。
const SETTLE_BREAK_MARKER := "SETTLE_DATA_BREAK"
## 断链告警环内记录（测试直读锚；与 push_warning 同文本，防无头捕获不到告警流）。
var _settle_break_log: Array = []

## 结算三 Label 数值就地填充（键缺省防御「——」占位，对齐退役 settle_scene 显示口径；
## 批次 AA / W6-2：兜底命中 → push_warning + _settle_break_log 留痕）。
func _apply_settle_labels(data: Dictionary) -> void:
	var grade_l := _settle_ui.get_node_or_null("GradeLabel") as Label
	var elapsed_l := _settle_ui.get_node_or_null("ElapsedLabel") as Label
	var talent_l := _settle_ui.get_node_or_null("TalentLabel") as Label
	if grade_l != null:
		grade_l.text = I18n.t("评分：%s") % I18n.t(String(data.get("grade", "——")))   # I18n：模板+评级名双层
	if elapsed_l != null:
		elapsed_l.text = I18n.t("耗时：%s") % (format_time(float(data.get("elapsed", -1.0)))
			if data.has("elapsed") else "——")
	if talent_l != null:
		talent_l.text = I18n.t("获得天赋值：%s") % (str(int(data.get("talent", 0))) if data.has("talent") else "——")
	if not (data.has("grade") and data.has("elapsed") and data.has("talent")):
		# 批次 AA / W6-2：数据断链留痕（快照与 ctx 双缺）——告警文本含约定标记。
		var brk_msg := "[%s] 结算数据断链：字段缺失（settle_snapshot 与 ctx 双缺，兜底显「——」）keys=%s" \
			% [SETTLE_BREAK_MARKER, str(data.keys())]
		_settle_break_log.append(brk_msg)
		push_warning(brk_msg)

## 结算 UI 样式（字色/描边对齐关卡 HUD 标题族；按钮走 SettleUI.theme 主题档；批次 AB-3 恒深档）。
func _apply_settle_theme() -> void:
	if _settle_ui == null:
		return
	for lname: String in ["GradeLabel", "ElapsedLabel", "TalentLabel"]:
		var lb := _settle_ui.get_node_or_null(lname) as Label
		if lb == null:
			continue
		lb.add_theme_color_override("font_color", SETTLE_FONT_DARK)
		lb.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
		lb.add_theme_constant_override("outline_size", 4)
		lb.add_theme_font_size_override("font_size", SETTLE_FONT_SIZE)

## 结算 UI 子树构建（_build_success_overlay 内调用，聚合完成前隐藏）：
## SettleDim 压暗层 + 评级/耗时/获得天赋值三 Label + 下一关/退出按钮 + 建模拖拽区。
## 布局锚点对齐退役 settle_scene.tscn（建模挂载带 0.18~0.82×0.06~0.66，文字带 0.3~0.7×0.64~0.86，
## 按钮右下）；ModelDragArea=建模拖拽通道（结算页继续可旋转——原 settle 由 viewer 自带拖拽承载）。
func _build_settle_ui(layer: CanvasLayer) -> void:
	var ui := Control.new()
	ui.name = "SettleUI"
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 根不吃输入：只由子钮/拖拽区承接
	ui.theme = ThemeManager.current_theme()  # 坑 11：CanvasLayer 主题不传播，显式赋主题
	ui.visible = false
	layer.add_child(ui)
	_settle_ui = ui
	var dim := ColorRect.new()
	dim.name = "SettleDim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.color = Color(0, 0, 0, SETTLE_DIM_ALPHA)
	ui.add_child(dim)
	# 三 Label（锚点=退役 settle_scene.tscn 同带）
	var grade_l := _make_settle_label(ui, "GradeLabel", 0.3, 0.64, 0.7, 0.72)
	var elapsed_l := _make_settle_label(ui, "ElapsedLabel", 0.3, 0.72, 0.7, 0.79)
	var talent_l := _make_settle_label(ui, "TalentLabel", 0.3, 0.79, 0.7, 0.86)
	# 下一关（三分流迁入）+ 退出（新增；右下双钮横排）
	var next_btn := Button.new()
	next_btn.name = "NextButton"
	next_btn.text = I18n.t("下一关")   # I18n：tscn 静态覆写同源
	next_btn.anchor_left = 1.0
	next_btn.anchor_top = 1.0
	next_btn.anchor_right = 1.0
	next_btn.anchor_bottom = 1.0
	next_btn.offset_left = -196.0
	next_btn.offset_top = -84.0
	next_btn.offset_right = -24.0
	next_btn.offset_bottom = -28.0
	next_btn.pressed.connect(_on_settle_next_pressed)
	ui.add_child(next_btn)
	var exit_btn := Button.new()
	exit_btn.name = "ExitButton"
	exit_btn.text = I18n.t("退出")   # I18n
	exit_btn.anchor_left = 1.0
	exit_btn.anchor_top = 1.0
	exit_btn.anchor_right = 1.0
	exit_btn.anchor_bottom = 1.0
	exit_btn.offset_left = -396.0
	exit_btn.offset_top = -84.0
	exit_btn.offset_right = -224.0
	exit_btn.offset_bottom = -28.0
	exit_btn.pressed.connect(_on_settle_exit_pressed)
	ui.add_child(exit_btn)
	# 建模拖拽区（覆盖建模挂载带；结算页玩家继续拖拽旋转，事件经 GUI 通道——回看段专用
	# _input 通道随 _settled 置位自动让位，二者不抢事件）
	var drag := Control.new()
	drag.name = "ModelDragArea"
	drag.anchor_left = SETTLE_MOUNT_ANCHORS.position.x
	drag.anchor_top = SETTLE_MOUNT_ANCHORS.position.y
	drag.anchor_right = SETTLE_MOUNT_ANCHORS.position.x + SETTLE_MOUNT_ANCHORS.size.x
	drag.anchor_bottom = SETTLE_MOUNT_ANCHORS.position.y + SETTLE_MOUNT_ANCHORS.size.y
	drag.mouse_filter = Control.MOUSE_FILTER_STOP
	# 批次 Z（Z6-P1-1，spec §6）：结算建模拖拽区挂拖窗豁免 meta——本区自持拖拽旋转
	#（_on_settle_drag_gui_input），无 meta 时按住建模拖动会连带拖走窗口（契约键与
	# PointCloudViewer 根/talk_scene.tscn 根 metadata/interactive 同源）。
	drag.set_meta("interactive", true)
	drag.gui_input.connect(_on_settle_drag_gui_input)
	ui.add_child(drag)
	# 淡入级联清单：压暗层（只淡入）→ 三 Label → 按钮组（错峰 0.1s，"从水里升起"质感）
	_settle_cascade = [[dim, false], [grade_l, true], [elapsed_l, true], [talent_l, true],
		[next_btn, true], [exit_btn, true]]

## 结算 Label 工厂（全宽锚带居中；IGNORE 不吃输入，样式在 _apply_settle_theme 统一刷）。
func _make_settle_label(parent: Control, lname: String, l: float, t: float, r: float, b: float) -> Label:
	var lb := Label.new()
	lb.name = lname
	lb.anchor_left = l
	lb.anchor_top = t
	lb.anchor_right = r
	lb.anchor_bottom = b
	lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lb)
	return lb

## 下一关四分流（settle_scene._on_next_pressed 语义迁入；纯函数可无头断言，P-D③）：
## replay→CATALOG / 第 5 关通关→FINALE（批次 AD 步骤四，spec §4.4.1 终局「未完待续」）/
## 无下一关数据→MAIN_MENU / 有→TALK（after_level 关后剧情）。
## chapter 缺省 1=旧两参形态零回归（既有调用/测试按 2 参消费行为与旧「三分流」逐字相同：
## chapter≠5 时判定顺序与旧码完全一致——replay→catalog、not has_next→main_menu、否则 talk）。
static func settle_next_route(replay: bool, has_next: bool, chapter: int = 1) -> String:
	if replay:
		return "catalog"
	if chapter == 5:
		return "finale"
	if not has_next:
		return "main_menu"
	return "talk"

## 「下一关」路由（P-D③；批次 AD 步骤四补 finale 分流）：语义自退役 settle_scene._on_next_pressed
## 迁入，replay/has_next 旧三分流不变，第 5 关通关改道终局界面。
func _on_settle_next_pressed() -> void:
	if not _settled:
		return
	var replay := bool(_settle_data.get("replay", false))
	var has_next: bool = not LevelLibrary.get_level(_chapter + 1).is_empty()
	match settle_next_route(replay, has_next, _chapter):
		"catalog":
			Game.goto_state(Game.State.CATALOG)
		"finale":
			# 批次 AD 步骤四（spec §4.4.1，D7）：通关第 5 关点「下一关」→ 终局「未完待续」界面。
			# ctx 不带 settle 位（FINALE 非 level 特判态，game._load_main_scene 走通用 SCENE_PATHS
			# 映射载 finale_scene.tscn）；进 FINALE 时 settle_snapshot 自动清空（非保留组，
			# game.gd 分支③留痕）——结算链已在「下一关」按下时消费完毕。
			Game.goto_state(Game.State.FINALE)
		"main_menu":
			Game.goto_state(Game.State.MAIN_MENU)
		"talk":
			# 批次 Y（Y-C6 补充，用户 2026-09-23 拍板）：对话挂载点前移一位——「通关第 N 关→
			# 播第 N+1 关对话（第N+1关.json）→进第 N+1 关」（旧口径=通关第 N 关播第 N 关对话）。
			# 挂载章节=即将进入的关卡（talk._finish 据此进关；背景/立绘/自动穿戴同口径联动）。
			Game.goto_state(Game.State.TALK, {"mode": "after_level", "chapter": _chapter + 1})

## 「退出」按钮（P-D 新增，退役 settle_scene 无此钮）：结算页返回主菜单。
func _on_settle_exit_pressed() -> void:
	if not _settled:
		return
	Game.goto_state(Game.State.MAIN_MENU)

## 结算页建模拖拽（ModelDragArea gui_input 通道）：与回看段同一姿态状态（_rev_yaw/_rev_pitch
## → _apply_review_pose 单一写手），建模保持玩家姿态继续旋转、不回正不重建。
func _on_settle_drag_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		_settle_dragging = mb.pressed
		return
	var mm := event as InputEventMouseMotion
	if mm != null and _settle_dragging and _spin_pivot != null:
		var tilt_limit := float(_align.get("tilt_limit", SETTLE_TILT_LIMIT))
		_rev_yaw += mm.relative.x * ORBIT_SPEED
		_rev_pitch = clampf(_rev_pitch + mm.relative.y * ORBIT_SPEED,
			deg_to_rad(-tilt_limit), deg_to_rad(tilt_limit))
		_apply_review_pose()

# ==================== 终审 P2-1：结算手势面板契约（spec §5.1/§5.7） ====================
## 生产 SETTLE 态=本场景内结算（settle_scene 退役不再路由），结算点云区注册随 P批波2 迁入：
## 注册节点=本场景根（catalog_scene 同款「根注册+契约」模式；生产结算无 PointCloudViewer
## 实例——建模由 SuccessOverlay MultiMesh 承载，SETTLE_VIEWER_SCRIPT 仅取 shader 常量，
## 故「结算 viewer 容器」=挂载带交互容器 ModelDragArea，其全局矩形即本契约矩形）。
## 观察类豁免 _input_locked 由 Router 语义分区 cloud 侧承担（§5.7），本侧仅提供通道。

## 面板矩形=建模挂载带（ModelDragArea 全局矩形，与退役 settle CenterMount 同带 0.18~0.82×
## 0.06~0.66）；结算 UI 未构建（非结算态/极早帧）时按 SETTLE_MOUNT_ANCHORS×当前视口现算兜底。
func gesture_panel_rect() -> Rect2:
	var drag: Control = null
	if _settle_ui != null and is_instance_valid(_settle_ui):
		drag = _settle_ui.get_node_or_null("ModelDragArea") as Control
	if drag != null:
		return drag.get_global_rect()
	var vsz := Vector2(1152, 648)
	var vp := get_viewport()
	if vp != null:
		vsz = vp.get_visible_rect().size
	return Rect2(SETTLE_MOUNT_ANCHORS.position * vsz, SETTLE_MOUNT_ANCHORS.size * vsz)

## 点云观察通道（§5.7 直调契约）：返回本场景——rotate_by/zoom_by 即下方两方法，
## Router `_panel_viewer` 判 `is Control`（本场景根为 Control）。
func get_gesture_viewer() -> Control:
	return self

## 手势二指旋转（度，灵敏度换算由 Router 承担）：与 ModelDragArea 键鼠拖拽/_review_unhandled_input
## 同一姿态写手（_rev_yaw/_rev_pitch → _apply_review_pose 单一真相源），不回正不重建。
func rotate_by(dx_deg: float, dy_deg: float) -> void:
	if not _settled or _spin_pivot == null:
		return
	var tilt_limit := float(_align.get("tilt_limit", SETTLE_TILT_LIMIT))
	_rev_yaw += deg_to_rad(dx_deg)
	_rev_pitch = clampf(_rev_pitch + deg_to_rad(dy_deg),
		deg_to_rad(-tilt_limit), deg_to_rad(tilt_limit))
	_apply_review_pose()

## 手势掌推拉缩放：结算页无缩放通道静默忽略——键鼠滚轮在 ModelDragArea 亦无缩放绑定
## （结算拖拽区仅左键拖拽旋转），手势不超键鼠上限口径（§2.4）；显式空实现防 Router zoom
## 意图直调 `zoom_by` 运行时报错（退役 settle viewer 有 zoom 通道，生产覆盖层相机距离由
## settle_match_fov 对位单点定格，随意 dolly 会破坏聚合→结算对位契约）。
func zoom_by(_factor: float) -> void:
	pass  # 结算无缩放通道（对位契约定格），静默

## P-D⑥边缘路径（goto_state(SETTLE) 特判重建本场景）：跳过成功动画直接进入结算展示——
## 重建关卡体素（正常 _build_views 链）后隐藏游玩 UI、覆盖层建模直接成形、结算 UI 淡入。
## 取舍：此路径允许重建（场景已销毁无状态可续），主路径（动画自然完成）零重建零切换不变；
## 不再路由 settle_scene（退役）。结算数据三级读取（批次 AA / W6-1，规格 §9.3）：
## ① **Game.settle_snapshot 优先**（_goto_settle 记账的生产数据源，经 CATALOG 绕行后仍
## 在场——W6-5 生命周期对 CATALOG 保留）② 其次 ctx（set_context 快照；图鉴入栈时已合并
## 结算字段，见 game._push_catalog_return）③ 最后兜底「——」并由 _apply_settle_labels
## 断链留痕 push_warning（W6-2）。不重复评级/发奖/推进（advance_progress 恰一次跨路径
## 守护：_settled 先置位，_goto_settle 不可达）。
func _enter_settle_direct() -> void:
	await get_tree().process_frame  # 布局/正交取景就绪（call_deferred 入口；add_child 同帧 anchor 未排布）
	# 防御：await/deferred 期间场景可能已被后续路由释放或替换（快速连续 goto_state，
	# 测试/设置面板连跳）——非当前场景不进结算展示、不记账（防 mark_settle_entered 串态）。
	if not _settle_mode or not is_inside_tree() or Game.get_current_scene() != self:
		return
	_settled = true
	_input_locked = true
	_success_started = true  # 冻结计时与挖除/对接交互（结算展示态；按钮已隐藏+处理器各有守卫）
	_success_seg = SuccessSeg.REVIEW
	for n: CanvasItem in _dissolve_ui_nodes():
		n.modulate.a = 0.0  # 游玩 UI 隐藏（结算由覆盖层承载，与动画自然完成终态一致）
	_build_success_overlay()
	_form_cloud_in_place()  # 建模直接成形（无聚合段：粒子系统不在场）
	_begin_review()         # 姿态=结算初始朝向（30/22）；无 tween 推进=静置可拖拽
	# 批次 AA / W6-1：① settle_snapshot 优先（字段级覆盖 ctx 快照；快照空 → 保持 ctx
	# 读数走 ②，双缺由 _apply_settle_labels ③ 留痕兜底）。
	var snap: Dictionary = Game.settle_snapshot
	if not snap.is_empty():
		var merged: Dictionary = _settle_data.duplicate(true)
		for k: Variant in snap.keys():
			merged[k] = snap[k]
		_settle_data = merged
	_show_settle_ui(_settle_data)

## 覆盖层建模就地成形（skip 直达/边缘路径共用）：逐点落到建模本体位并显示（无飞行段）。
func _form_cloud_in_place() -> void:
	if _cloud_mm == null or _cloud_inst == null:
		return
	var n := _cloud_mm.instance_count
	for i: int in n:
		_cloud_mm.set_instance_transform(i, Transform3D(Basis(), _cloud_targets[i]))
	_cloud_inst.visible = true

## 测试钩子：跳过成功动画直接进入结算 UI（P批波2 语义=跳过动画不跳过结算；正常游玩动画
## 不可跳过）。P-D①：不再复原游玩 UI/不再释放覆盖层——skip 后建模就地成形、游玩 UI 保持
## 隐藏，结算 UI 在覆盖层内淡入（旧「UI modulate 复原 WHITE+释放覆盖层+路由 settle_scene」
## 随结算场景退役废止，等价替换留痕见各分支注）。
func _skip_success_animation() -> void:
	if not _success_started or _settled:
		return
	if _anim_tween != null and _anim_tween.is_valid():
		_anim_tween.kill()
	# N3 层散点清场（release_particles 不还原体素——skip 路径体素保持隐藏，
	# 与动画自然完成终态一致「剩余积木块全部隐藏」）
	if _fx_layer != null and _fx_layer.has_method("release_particles"):
		_fx_layer.call("release_particles")
	# 游玩 UI 统一收敛到隐藏（打断点可能在淡出完成前——旧「复原 WHITE」随场景切换废止，
	# P批波2 结算 UI 就地接管显示，HUD 残留会与结算 UI 叠影）
	for n: CanvasItem in _dissolve_ui_nodes():
		n.modulate.a = 0.0
	_form_cloud_in_place()  # P-D：建模就地成形（旧 _cloud_mm/_cloud_inst 置 null 释放废止——
	                        # 覆盖层建模即结算展示建模，保留后续拖拽复用）
	_goto_settle()  # P-D：结算 UI 就地淡入（内部含 mark_settle_entered 记账）
