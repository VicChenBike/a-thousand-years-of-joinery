extends RefCounted
## 批次 W（P3-1，规格 §7）：色彩单源常量表。
## 纪律（红线逐条）：
## - 观感零变化：本表只收录现网既有值，消费方逐文件替换后引用值不变（P3-1d 按压/hover
##   边框与 theme .tres 内部深底浅字族统一为规格拍板的唯一值级变化点，对照表见实施报告；
##   批次 AB-3：浅底深字族随深浅主题机制删除退役，本表深色为唯一真值）。
## - 消费方式：工程纪律「--script 模式 class_name 注册时序不稳，消费方一律 preload」（coord_space/
##   focus_fx 先例）——本件不设 class_name，消费方 `const Palette := preload("res://scripts/palette.gd")`。
## - .tres 无法引用脚本常量：theme_dark 内描边金/深底浅字字面量由 test_w_polish
##   段 B 做同值锚定断言（漂移即红；批次 AB-3：theme_light.tres 已退役）。
## - 异值位点不并值（W0 清单内同族多档系历史走查/实证调档），以语义命名单源管理；值级统一
##   留走查定档（P3-1a 提示金两档、光标蓝/骨架蓝等）。

# ---------- 金色族 ----------
const STROKE_GOLD := Color(1, 0.922, 0.706)      # 描边金 RGB 单源（各站点 α 档 0.3/0.35/0.4/0.45 原值保留；theme_dark.tres 五处字面量同值锚定）
const MAIN_GOLD := Color(0.96, 0.77, 0.26)       # 主金（focus_fx 中央木料/图鉴 GOLD/结算 GOLD_TINT；批次 J #F5C542）
const HINT_GOLD_TOAST := Color(1.0, 0.85, 0.4)   # 提示金·toast 信息档（顶栏消息金=STROKE_GOLD 全 α，不另立值）

# ---------- 语义红 ----------
const TOAST_WARN_RED := Color(1.0, 0.45, 0.35)   # toast 警告红
const FOCUS_JOIN_RED := Color(0.90, 0.25, 0.20)  # 聚焦特效·对接固定件红
const EYE_MARK_RED := Color(1.0, 0.16, 0.12)     # 锐眼·多余体素红
const CURSOR_RED := Color("#C0504D")             # 光标 B 红（=手别指示右色/置信度红，§7.1 同值）

# ---------- 语义绿 ----------
const PICK_GREEN := Color(0.30, 0.85, 0.40)      # 选中/对照绿（体素高亮 RGB；focus_fx 目标侧同值）
const GHOST_GREEN := Color(0.3, 1.0, 0.35)       # 锐眼·缺少体素幻影绿
const CONF_GREEN := Color("#3FA34D")             # 置信度 >0.8 绿
const TOAST_OK_GREEN := Color(0.4, 0.9, 0.5)     # toast 成功绿

# ---------- 语义蓝（P3-1c：光标蓝与骨架蓝现网异值，N15 后光标蓝语义独立，不并值） ----------
const CURSOR_BLUE := Color("#3E7BBD")            # 光标 A 蓝（=手别指示左色）
const SKELETON_BLUE := Color(0.30, 0.55, 1.0)    # 手部骨架左手蓝（spec §5）

# ---------- 深底浅字（P3-1a：历史调档值零变化，命名单源；值级统一留走查定档） ----------
## 批次 AB-3（深浅主题机制删除）：原「浅底深字」族 TEXT_LIGHT_SETTLE/TITLE/LEVELBAR 随
## theme_light.tres 一并退役——深色为全局唯一观感，本表只存深色消费的真值。
const TEXT_DARK_BUTTON := Color(0.96, 0.90, 0.78)      # theme_dark Button 族（N12 用户实证调档；.tres 统一套）
const TEXT_DARK_HUD := Color("#F7EDD6")                # 手势 HUD 字色（批次 T T3 提亮档）
const TEXT_DARK_SETTLE := Color(0.96, 0.93, 0.84)      # 结算/气泡米白（关卡 HUD 标题族）
const TEXT_DARK_TITLE := Color(0.95, 0.93, 0.84, 0.82) # 关卡标题米白（α 原档）
const TEXT_DARK_LEVELBAR := Color(0.949, 0.910, 0.835) # 顶栏标签（dark .tres Label 族 rounded 旧值）
const TEXT_DARK_CAMSEL := Color(1, 0.95, 0.8)          # 摄像头菜单选中行（深）

# ---------- 中性 ----------
const NO_HAND_GRAY := Color("#B5B5B5")           # 未检出灰（批次 T T3 提亮档；P3-1e 起改字色直写不再 self_modulate 相乘）
