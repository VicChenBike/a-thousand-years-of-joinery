extends Control
## 关卡编辑器·编排层（规格 §6.2/§6.3）：节点装配与信号接线、四标签 VoxelEditSession 生命周期、
## 文件对话框流程、状态栏刷新、toast。视图刷新由本层统一驱动（视图层与纯逻辑层互不持引用）。
## 阶段留痕：T1-7 最小骨架 → T2-4 本版（编辑接线）→ T2-5 替换 _wire_edit_ops → T3-2 替换 _wire_playtest。
## 不写判定/IO 逻辑——全部下沉纯逻辑层（level_project / voxel_edit_ops / playtest_judge）。

const LevelProjectScript := preload("res://scripts/level_project.gd")
const SessionScript := preload("res://scripts/voxel_edit_ops.gd")
const EditorViewScript := preload("res://scripts/editor_view.gd")
const InteractionScript := preload("res://scripts/editor_interaction.gd")
## 20260916 槽位化批 D4~D6（规格 §3.4~§3.6）：槽位纯逻辑类接入（自动保存/续接/自动元数据）。
const LevelSlotsScript := preload("res://scripts/level_slots.gd")

const TAG_NAMES := {
	0: "初始木块 blocks",
	1: "标准答案 target_shapes[0]",
	2: "对接件 join_part",
	3: "最终成品 final_answer",
}
# 退役留痕（spec §3.6-2/§3.4-6）：STATUS_OPEN_FAIL/STATUS_CHAPTER_KEY/STATUS_NEW_UNSAVED/
# STATUS_SAVE_FAIL/STATUS_NEW_DONE 随文件对话框/新建流程/dirty 退役删除；STATUS_MULTI_PIECE 保留迁入槽位加载。
const STATUS_MULTI_PIECE := "该文件含 %d 个 piece，编辑器仅编辑第 1 个（游戏只消费 pieces[0]）"
const STATUS_SLOT_LOAD_FAIL := "槽位加载失败：level.json 缺失或格式不符（仅支持 format_version=1 且 pieces 非空）"
const STATUS_AUTOSAVE_FAIL := "自动保存失败：无法写入槽位文件（编辑继续，下次操作重试）"
const STATUS_SLOT_INIT_FAIL := "槽位初始化失败：无法创建 levels/ 槽位目录（本次编辑仅内存态，不自动保存）"
const STATUS_SIZE_CONFIRM := "确认将尺寸调整为 %d×%d×%d（全局（四域统一））？\n将被越界裁剪：\n%s"
## 审查②遗留①：tag2/3 发起单组件应用确认框专属文案（「仅当前组件域」口径，含尺寸与裁剪明细占位）
## ——隔离性修复批 20260917 起「仅当前组件域」措辞仅再用于 tag2/3 发起（tag0/1 发起改用同料联动文案）。
## 批次 V（V-E1，规格 §9.2）：「仅当前组件域」措辞自本批起复位为四标签通用单域文案——tag0/1
## 不再同料联动，单组件应用 affected 恒={active_tag}，四标签统一走本文案。
const STATUS_SIZE_CONFIRM_ONE := "确认将尺寸调整为 %d×%d×%d（仅当前组件域）？\n将被越界裁剪：\n%s"
## 退役留痕（批次 V-E1，规格 §9.2）：STATUS_SIZE_CONFIRM_LINK「初始木块与标准答案同一块料，
## 尺寸联动」文案随四域彻底独立退役删除——tag1 标准答案自此写独立 target_size 字段
## （level_project.gd §9.1 分流），「同料联动」语义不复存在，确认框按域独立（四标签统一
## STATUS_SIZE_CONFIRM_ONE + REGEN_NOTE）。
const STATUS_SIZE_APPLIED := "尺寸→%d×%d×%d（全局（四域统一）），裁剪 %s"
## 修复批二 F3：应用尺寸后受影响页自动重生实心——确认弹窗注明 + 反馈文案。
## 隔离性修复批 20260917（R2/R3/R4 共用执行体）：REGEN_NOTE 措辞泛化「初始木块」→「受影响组件」
## （tag0/1 两页/tag2/3 本页/全局四页全部重生实心，所有确认框路径恒附）。
const REGEN_NOTE := "受影响组件将按新尺寸重生实心，已有挖除将被覆盖（可撤销）"
const STATUS_SIZE_REGEN := "尺寸→%d×%d×%d（全局（四域统一）），初始木块已重生实心 %d 格"
const STATUS_SIZE_NOOP := "尺寸未变化，无需应用"
# 退役留痕（批次 W W5，N16 拍板 9）：STATUS_EXPORT_OK/STATUS_EXPORT_FAIL 常量随导出契约 JSON
# 链路（按钮/_on_export_contract_pressed/LevelSlots.export_contract_text）整体退役删除。
## 20260916 槽位化批 D2（规格 §3.2-6）：单组件应用两条反馈文案——「仅当前组件域」指 size 字段
## 只改当前域。隔离性修复批 20260917（R3）：tag2/3 发起本页也重生实心→原「初始木块域/初始木块」
## 措辞泛化为「当前组件域/受影响组件」（避免 join/final 页显示错域文案）；STATUS_SIZE_APPLIED_ONE
## （只裁不重生）分支随全路径重生退役，常量保留退役留痕。
const STATUS_SIZE_APPLIED_ONE := "尺寸→%d×%d×%d（仅当前组件域），裁剪 %s"
const STATUS_SIZE_REGEN_ONE := "尺寸→%d×%d×%d（当前组件域），受影响组件已重生实心 %d 格"
const SIZE_TAG_SHORT := {0: "初始木块", 1: "标准答案", 2: "对接件", 3: "最终成品"}
const LAYOUT_EDIT := 0
const LAYOUT_PLAYTEST := 1

@onready var btn_slot1: Button = $TopBar/BtnSlot1
@onready var btn_slot2: Button = $TopBar/BtnSlot2
@onready var btn_slot3: Button = $TopBar/BtnSlot3
@onready var btn_slot4: Button = $TopBar/BtnSlot4
@onready var btn_slot5: Button = $TopBar/BtnSlot5
@onready var btn_join: Button = $TopBar/BtnJoin
@onready var btn_playtest: Button = $TopBar/BtnPlaytest
# 退役留痕（批次 W W5，N16 拍板 9）：@onready btn_export_contract 随导出契约 JSON 按钮退役删除。
@onready var file_name_label: Label = $TopBar/FileNameLabel
@onready var tab_blocks: Button = $LeftPanel/LeftScroll/LeftVBox/TabBlocks
@onready var tab_target: Button = $LeftPanel/LeftScroll/LeftVBox/TabTarget
@onready var tab_join: Button = $LeftPanel/LeftScroll/LeftVBox/TabJoin
@onready var tab_final: Button = $LeftPanel/LeftScroll/LeftVBox/TabFinal
@onready var size_x: SpinBox = $LeftPanel/LeftScroll/LeftVBox/SizeRow/SizeX
@onready var size_y: SpinBox = $LeftPanel/LeftScroll/LeftVBox/SizeRow/SizeY
@onready var size_z: SpinBox = $LeftPanel/LeftScroll/LeftVBox/SizeRow/SizeZ
@onready var btn_solid: Button = $LeftPanel/LeftScroll/LeftVBox/OpsRow/BtnSolid
@onready var btn_clear: Button = $LeftPanel/LeftScroll/LeftVBox/OpsRow/BtnClear
@onready var btn_copy_base: Button = $LeftPanel/LeftScroll/LeftVBox/BtnCopyBase
@onready var btn_dig_mode: Button = $LeftPanel/LeftScroll/LeftVBox/ModeRow/BtnDigMode
@onready var btn_add_mode: Button = $LeftPanel/LeftScroll/LeftVBox/ModeRow/BtnAddMode
@onready var btn_apply_size_one: Button = $LeftPanel/LeftScroll/LeftVBox/SizeApplyRow/BtnApplySizeOne
@onready var btn_apply_size_all: Button = $LeftPanel/LeftScroll/LeftVBox/SizeApplyRow/BtnApplySizeAll
# 退役留痕（spec §3.5-2）：@onready 六元数据控件（chapter_option/title_edit/era_edit/desc_edit/
# name_edit/level_id_edit）随元数据 UI 全删（tscn 七节点同步删除）。
@onready var target_panel: Panel = $TargetPanel
@onready var join_panel: Panel = $JoinPanel
@onready var main_vc: SubViewportContainer = $MainPanel/VC
@onready var main_viewport: SubViewport = $MainPanel/VC/SubViewport
@onready var main_cam: Camera3D = $MainPanel/VC/SubViewport/Camera3D
@onready var main_voxel_view: Node = $MainPanel/VC/SubViewport/VoxelView
@onready var target_voxel_view: Node = $TargetPanel/VC/SubViewport/VoxelView
@onready var join_voxel_view: Node = $JoinPanel/VC/SubViewport/VoxelView
@onready var target_vc: SubViewportContainer = $TargetPanel/VC
@onready var join_vc: SubViewportContainer = $JoinPanel/VC
@onready var target_cam: Camera3D = $TargetPanel/VC/SubViewport/Camera3D
@onready var join_cam: Camera3D = $JoinPanel/VC/SubViewport/Camera3D
@onready var target_viewport: SubViewport = $TargetPanel/VC/SubViewport
@onready var join_viewport: SubViewport = $JoinPanel/VC/SubViewport
@onready var main_title: Label = $MainPanel/MainTitle
@onready var count_label: Label = $StatusBar/StatusRow/CountLabel
@onready var hover_label: Label = $StatusBar/StatusRow/HoverLabel
@onready var mode_label: Label = $StatusBar/StatusRow/ModeLabel
@onready var contract_label: Label = $StatusBar/StatusRow/ContractLabel
# 试玩 toast（场景节点 PlaytestToast）：锚点定在底部中央 (0.32,0.885)~(0.68,0.925)——
# W4 顶栏五槽位钮改造后顶部无可安放区（原顶带 0.02~0.06 与第四/第五关钮重叠撞色，
# W5 走查 NG-1/NG-2），下移后不压顶栏/左面板（右缘 0.27）/状态栏（0.95 起），仅浮主视口下缘。
@onready var playtest_toast: Label = $PlaytestToast
# 批次 Y6（Y-D4，spec §9.4）：success 常驻通关横幅——不吃 2.5s toast 自愈；进试玩新局或退出
# 试玩才清除（_enter_playtest/_do_exit_playtest 置隐）。锚定主视口上带（试玩布局 0.43 起），
# 居中大字金描边，mouse_filter=IGNORE 不挡主视口拾取。
@onready var playtest_banner: Label = $PlaytestBanner
@onready var left_panel: Panel = $LeftPanel
@onready var main_panel: Panel = $MainPanel

var project: RefCounted = null             # LevelProject 实例
var sessions: Dictionary = {}              # tag(int) → VoxelEditSession
var active_tag: int = 0                    # LevelProjectScript.TAG_BLOCKS
var is_add_mode: bool = false
# 退役留痕（spec §3.4-6/§3.5-2/§3.6-2）：file_path/dirty/_file_dialog/_file_mode_open/_new_dialog/
# _last_title 随文件流/dirty/手动元数据退役删除。
## 槽位编排（spec §3.4-5/§3.4-7）：_slots_root=env 沙盒或 slots_root()；空=降级内存态。
## _current_slot=当前槽位 1~5；_last_contract_hint=自动保存契约提示去重基准（P2-3）；
## _last_status_text=最近一次 status_hint 文本（任何来源）——P2-3 落地注记：契约提示仅在
## 「状态栏空闲（空）或正显示上一条契约提示」时刷新，否则不顶掉刚显示的操作反馈（G7/G20/G21
## 既有状态栏断言零回归的必要条件，spec §3.4-1 括注目的句的实现化）。
var _slots_root: String = ""
var _current_slot: int = 1
var _last_contract_hint: String = ""
var _last_status_text: String = ""
var interaction: Node = null
var _mat_light: Material = null
var _mat_dark: Material = null
var _size_dialog: ConfirmationDialog = null
var _size_draft: Vector3i = Vector3i(3, 3, 3)
var _pending_apply: Dictionary = {}
# ---- 试玩态（T3-2 实装；v2 声明占位保证 _active_session 等引用可编译） ----
var _in_playtest: bool = false
var _playtest_session: RefCounted = null
var _playtest_snapshot: Dictionary = {}
var _exit_playtest_dialog: ConfirmationDialog = null
var _judge_script: GDScript = null
# ---- VIEW 只读预览交互（T3：常驻实例 + 进出试玩绑定/解绑） ----
var _view_interaction_target: Node = null
var _view_interaction_join: Node = null

func _ready() -> void:
	_mat_light = EditorViewScript.make_wood_material(EditorViewScript.WOOD_LIGHT)
	_mat_dark = EditorViewScript.make_wood_material(EditorViewScript.WOOD_DARK)
	project = LevelProjectScript.new()
	# 槽位续接（spec §3.4-5）：env 沙盒根（VOXEL_EDITOR_SLOTS_ROOT，由 LevelSlots.slots_root()
	# 消费——审查②遗留③单点化）→ ensure_initialized → load_meta().last_slot → 槽位数据装载
	# （首载不先保存——盘上即权威）；初始化失败=状态栏降级提示继续内存态；装载失败=
	# STATUS_SLOT_LOAD_FAIL + 内存 3³ 骨架 + apply_auto_meta 照常进入（下次操作自动保存即以
	# 合法内容覆盖坏文件）。UI 重建延后到会话/接线完成后的 _after_project_reloaded 统一走。
	_slots_root = LevelSlotsScript.ensure_initialized()
	if _slots_root.is_empty():
		status_hint(STATUS_SLOT_INIT_FAIL)
		project.new_project(Vector3i(3, 3, 3))
		LevelSlotsScript.apply_auto_meta(project, _current_slot)
	else:
		_current_slot = clampi(int(LevelSlotsScript.load_meta(_slots_root).get("last_slot", 1)), 1, 5)
		if not _load_slot_data(_current_slot):
			status_hint(STATUS_SLOT_LOAD_FAIL)
			project.new_project(Vector3i(3, 3, 3))
			LevelSlotsScript.apply_auto_meta(project, _current_slot)
	for tag: int in [0, 1, 2, 3]:
		var sess = SessionScript.new()
		sess.setup({})   # 占位（_after_project_reloaded 按载入数据重设四会话）
		sessions[tag] = sess
	# 批次 W（W5，P2-4a/P1-9）初始化收尾提示：
	# ①预填源不可用（P2-4a）→ 状态栏显式提示（不得静默降级；优先级高于槽位根展示）；
	# ②状态栏显示实际生效槽位根（P1-9 拍板 6：便携/回退两态可辨识）——仅写文本不占
	# _last_status_text 契约提示去重基准（一次性展示，任何后续 status_hint 直接覆盖）；
	# 载入警告/多 piece 提示已占状态栏时不覆盖（警告优先）。
	if not LevelSlotsScript.last_prefill_note.is_empty():
		status_hint(LevelSlotsScript.last_prefill_note)
	elif not _slots_root.is_empty() and _last_status_text.is_empty():
		contract_label.text = "槽位目录：%s" % _slots_root
	_wire_topbar()
	_wire_editing()
	_wire_edit_ops()
	_wire_playtest()
	_apply_layout(LAYOUT_EDIT)
	_after_project_reloaded()
	_sync_slot_buttons()
	file_name_label.text = "第%s关 · 已加载" % LevelSlotsScript.CN_NUMS[_current_slot - 1]

## 布局双态单一权威（T1 修复批 D1/D3）：EDIT=主视口右侧全高、双面板隐藏；
## PLAYTEST=主视口回下带、双面板取现状锚点并显示（逐像素不动）。进入/退出试玩唯一入口。
func _apply_layout(mode: int) -> void:
	if mode == LAYOUT_PLAYTEST:
		main_panel.anchor_left = 0.27
		main_panel.anchor_top = 0.43
		main_panel.anchor_right = 0.995
		main_panel.anchor_bottom = 0.945
		target_panel.anchor_left = 0.27
		target_panel.anchor_top = 0.075
		target_panel.anchor_right = 0.59
		target_panel.anchor_bottom = 0.42
		join_panel.anchor_left = 0.61
		join_panel.anchor_top = 0.075
		join_panel.anchor_right = 0.995
		join_panel.anchor_bottom = 0.42
		target_panel.visible = true
		join_panel.visible = true
	else:
		main_panel.anchor_left = 0.27
		main_panel.anchor_top = 0.075
		main_panel.anchor_right = 0.995
		main_panel.anchor_bottom = 0.945
		target_panel.visible = false
		join_panel.visible = false

# ---------- 顶栏槽位选择器（spec §3.6；新建/打开/另存+FileDialog 全套退役，退役留痕：
# _make_file_dialog/_make_dialogs/_on_new_pressed/_do_new/_on_open_pressed/_on_save_pressed/
# _suggest_file_name/_on_file_selected/_do_open/_do_save 删除，语义由 _switch_slot/
# _load_slot_into_project/_autosave_current 承接） ----------
func _wire_topbar() -> void:
	btn_slot1.pressed.connect(_switch_slot.bind(1))
	btn_slot2.pressed.connect(_switch_slot.bind(2))
	btn_slot3.pressed.connect(_switch_slot.bind(3))
	btn_slot4.pressed.connect(_switch_slot.bind(4))
	btn_slot5.pressed.connect(_switch_slot.bind(5))
	btn_playtest.disabled = true   # T3-2 启用
	btn_join.visible = false
	# 退役留痕（批次 W W5，N16 拍板 9）：btn_export_contract.pressed 接线随导出链路退役删除。

## 槽位数据装载（不含 UI 重建，供 _ready 早于会话创建时调用）：读槽→结构门→多 piece 提示
## （STATUS_MULTI_PIECE 迁入，spec §3.6-2）→apply_auto_meta（spec §3.5-1：加载后调用，保存前不重复）。
## 返回 false=空文本/结构门拒绝（project 数据零改动），调用方负责提示与降级。
func _load_slot_data(n: int) -> bool:
	# 批次 U（U12⑥，spec §4-U12-⑥）：孤儿残留检测——save_slot_text 原子写兜底序（旧文件先改名
	# .bak 腾位）可能遗留 <slot>.json.bak/.tmp（写侧逻辑零改动），载入前检测只提示不自动删除。
	# 槽位路径派生沿 test_level_slots.gd:143 先例（root + "level_%d/level.json"；level_slots.gd 零改动）；
	# status_hint 为方法实名（:142/:148/:211 既有调用先例，计划「节点赋值」表述按磁盘实况校正）。
	if not _slots_root.is_empty():
		var slot_path: String = _slots_root + ("level_%d/level.json" % n)
		for suffix: String in [".bak", ".tmp"]:
			if FileAccess.file_exists(slot_path + suffix):
				status_hint("检测到未完成的保存残留（.bak/.tmp），槽位内容可能为旧版本")
				break
	var text := LevelSlotsScript.load_slot_text(n, _slots_root)
	if text.is_empty() or not project.load_from_text(text):
		return false
	if project.get_piece_count() > 1:
		status_hint(STATUS_MULTI_PIECE % project.get_piece_count())
	# 批次 U（U12⑤）状态栏消费（双审回修⑬）：载入警告逐条上状态栏（数据正确性警告优先级
	# 高于孤儿残留提示——后写覆盖；空载入警告路径零行为变化）。
	for w: Variant in project.load_warnings:
		status_hint(String(w))
	LevelSlotsScript.apply_auto_meta(project, n)
	return true

## 槽位装载（spec §3.6-2：原 _do_open 职责承接，G21 当前槽重载同通道）：数据装载 + 全量重建。
func _load_slot_into_project(n: int) -> bool:
	if not _load_slot_data(n):
		return false
	_after_project_reloaded()
	return true

## 切槽位四态（spec §3.6-3 表）：守卫 _in_playtest（试玩禁切）与 n==_current_slot（noop）→
## _autosave_current() 失败（=当前槽 save_slot_text 失败；save_meta 失败不致命见 _autosave_current）
## 则 status_hint+中止切换（唯一「写失败升级为阻断」例外：切换是数据流转关口，防丢数据）→
## load_slot_text 空/装载失败=status_hint(STATUS_SLOT_LOAD_FAIL)+保持当前槽（钮弹回，不崩）→
## 成功：_load_slot_into_project(n)（内含 apply_auto_meta）→ _current_slot=n → save_meta(n)
## 失败=非阻断仅提示（P2-5/plan §11 P9：仅 last_slot 指针未更新，零数据丢失）→
## _sync_slot_buttons() + FileNameLabel「第N关 · 已加载」。
func _switch_slot(n: int) -> void:
	if _in_playtest or n == _current_slot:
		return
	if _slots_root.is_empty():
		status_hint(STATUS_SLOT_INIT_FAIL)   # 降级内存态：无槽位根不可切换
		_sync_slot_buttons()
		return
	if not _autosave_current():
		status_hint(STATUS_AUTOSAVE_FAIL)
		_sync_slot_buttons()   # 目标钮弹回当前槽高亮
		return
	var prev_slot := _current_slot
	if not _load_slot_into_project(n):
		status_hint(STATUS_SLOT_LOAD_FAIL)
		_current_slot = prev_slot   # 加载失败保持当前槽（load_from_text 失败不改 project 数据）
		_sync_slot_buttons()
		return
	_current_slot = n
	if not LevelSlotsScript.save_meta(n, _slots_root):
		status_hint(STATUS_AUTOSAVE_FAIL)   # P2-5：非阻断，不回滚切换
	_sync_slot_buttons()
	file_name_label.text = "第%s关 · 已加载" % LevelSlotsScript.CN_NUMS[n - 1]

## 五钮 button_pressed 按槽高亮（ButtonGroup 互斥组下置值即随组互斥弹回其余钮）。
func _sync_slot_buttons() -> void:
	btn_slot1.button_pressed = _current_slot == 1
	btn_slot2.button_pressed = _current_slot == 2
	btn_slot3.button_pressed = _current_slot == 3
	btn_slot4.button_pressed = _current_slot == 4
	btn_slot5.button_pressed = _current_slot == 5

## 自动保存统一入口（spec §3.4-1）：首行试玩守卫（试玩临时改动不落档，P2⑤/R2——_on_dig_requested
## 无试玩守卫由此统一封死）→ _sync_sessions_to_project → save_to_text → save_slot_text+save_meta →
## 成功=FileNameLabel「第N关 · 已保存 HH:MM」（Time.get_time_dict_from_system 取 %02d:%02d）+
## 契约提示仅内容变化时刷新（P2-3，见 _last_status_text 注记）→ 两种失败都不中断调用方编辑操作。
## 返回值语义（plan §11 P9 裁决）：仅由 save_slot_text（关卡数据）决定——false=致命（仅 _switch_slot
## 据此中止切换）；save_meta 失败仅 status_hint 恒返回 true（仅 last_slot 指针问题，零数据丢失）。
func _autosave_current() -> bool:
	if _in_playtest:
		return true   # 试玩中不落档
	if _slots_root.is_empty():
		return true   # 降级内存态：无槽位根，无盘可写（_ready 已提示）
	_sync_sessions_to_project()
	var text: String = project.save_to_text()
	if not LevelSlotsScript.save_slot_text(_current_slot, text, _slots_root):
		# 批次 V（V-E2，规格 §9.3）：拆分五文件逐文件原子写——失败时状态栏附报具体文件
		# （LevelSlots.last_error_file；成功保存清零，此处仅在失败分支读取）。
		var err_file: String = LevelSlotsScript.last_error_file
		status_hint(STATUS_AUTOSAVE_FAIL if err_file.is_empty()
			else "%s（%s）" % [STATUS_AUTOSAVE_FAIL, err_file.get_file()])
		return false
	if not LevelSlotsScript.save_meta(_current_slot, _slots_root):
		status_hint(STATUS_AUTOSAVE_FAIL)   # P2-5：非阻断
	var hint: String = project.contract_hint()
	if hint != LevelProjectScript.HINT_ALL_OK and hint != _last_contract_hint \
			and (_last_status_text.is_empty() or _last_status_text == _last_contract_hint):
		status_hint(hint)   # 全过静默；同一异常持续期间不重复刷屏，变化时才重现
		# 审查③ P2-1：吸收移入「实际显示」分支——被第三门条件（状态栏忙）压制的提示不得更新
		# 去重基准，否则门条件满足后同内容提示被永久吞没；对齐 spec §3.4-1「仅内容变化时刷新」语义。
		_last_contract_hint = hint
	var t := Time.get_time_dict_from_system()
	file_name_label.text = "第%s关 · 已保存 %02d:%02d" % [
		LevelSlotsScript.CN_NUMS[_current_slot - 1], int(t["hour"]), int(t["minute"])]
	return true

## 打开/新建共用的全量重建：尺寸控件、四会话、标签态、视图、拾取上下文。
## 尺寸 SpinBox 用 set_value_no_signal 静默写（审查⑤回修 P1-1/D-1）：逐轴带信号写会在
## 中间态（新x,旧y,旧z）触发 _on_size_draft_changed 误改草稿并可能误弹尺寸确认框/直通应用执行体。
func _after_project_reloaded() -> void:
	var bs: Vector3i = project.get_block_size()
	size_x.set_value_no_signal(bs.x)
	size_y.set_value_no_signal(bs.y)
	size_z.set_value_no_signal(bs.z)
	for tag: int in [0, 1, 2, 3]:
		sessions[tag].setup(project.get_voxel_set(tag))
	active_tag = 0
	_sync_tab_buttons()
	interaction.clear_selection()
	_sync_pick_context()
	_rebuild_active_view()
	_refresh_status()
	_pending_apply = {}
	_size_draft = bs   # D2：草稿显式对齐已载入尺寸（静默写不再经 handler 自愈）

func _sync_sessions_to_project() -> void:
	for tag: int in [0, 1, 2, 3]:
		project.set_voxel_set(tag, sessions[tag].cells)

# ---------- 元数据自动化（spec §3.5）：六项手输 UI 与 8 个处理器（_wire_meta/_load_meta_form/
# _on_chapter_changed/_on_title_changed/_on_era_changed/_on_desc_changed/_on_name_changed/
# _on_level_id_changed）全量退役——chapter/title/level_id 强制、name 空补、era/theme/description
# 不动，单点实现=LevelSlots.apply_auto_meta（槽位载入与切槽时调用，W2 已落地）。

# ---------- 编辑接线（标签切换 / 交互信号 / 撤销重做 / 键盘） ----------
func _wire_editing() -> void:
	tab_blocks.pressed.connect(switch_tag.bind(0))
	tab_target.pressed.connect(switch_tag.bind(1))
	tab_join.pressed.connect(switch_tag.bind(2))
	tab_final.pressed.connect(switch_tag.bind(3))
	interaction = InteractionScript.new()
	add_child(interaction)
	interaction.bind(main_vc, main_viewport, main_cam)
	interaction.set_view(main_voxel_view)
	_sync_pick_context()
	interaction.dig_requested.connect(_on_dig_requested)
	interaction.add_requested.connect(_on_add_requested)
	interaction.selection_changed.connect(_on_selection_changed)
	interaction.hover_changed.connect(_on_hover_changed)
	interaction.place_target_changed.connect(_on_place_target_changed)
	# T3：常驻创建 Target/Join 的 VIEW 只读交互实例（进试玩时 bind，退出 unbind）。
	_view_interaction_target = InteractionScript.new()
	add_child(_view_interaction_target)
	_view_interaction_join = InteractionScript.new()
	add_child(_view_interaction_join)

## 拾取上下文与注视目标同步（F2；隔离性修复批 20260917 R6）：pick=格集/尺寸/容器中心；
## look_target=格集 AABB 中心（世界系，扣视图中心偏移本页域×0.5）；空集回落世界原点（容器中心，
## 供容器线框取景）。尺寸来源=_active_domain_size()（本页域；试玩=blocks 域）。
func _sync_pick_context() -> void:
	if interaction != null:
		var bs: Vector3i = _active_domain_size()
		var cells: Dictionary = _active_session().cells
		var center_off: Vector3 = Vector3(bs) * 0.5
		interaction.set_pick_context(cells, bs, center_off)
		var lt: Vector3 = Vector3.ZERO if cells.is_empty() \
			else InteractionScript.cells_center(cells) - center_off
		interaction.set_look_target(lt)

func _sync_tab_buttons() -> void:
	tab_blocks.button_pressed = active_tag == 0
	tab_target.button_pressed = active_tag == 1
	tab_join.button_pressed = active_tag == 2
	tab_final.button_pressed = active_tag == 3

func switch_tag(tag: int) -> void:
	if _in_playtest:
		return
	active_tag = tag
	_sync_tab_buttons()
	btn_copy_base.visible = tag != 0   # blocks 无复制初始块按钮（§7.3）
	_revert_size_spins()   # D2 §3.2-7：切标签草稿重置为当前域尺寸（get_size_for_tag(active_tag)）
	main_title.text = String(TAG_NAMES[tag])
	interaction.clear_selection()      # 规格暂定 T4：切换清空该标签选区
	_sync_pick_context()
	_rebuild_active_view()
	_refresh_status()

func _rebuild_active_view() -> void:
	if not main_voxel_view.has_method("build_set"):
		return
	var cells: Dictionary = _active_session().cells
	# 隔离性修复批 20260917 R6：build_set 尺寸参数=本页域（旧恒 get_block_size，tag2/3 页错域）。
	main_voxel_view.call("build_set", cells, _active_domain_size(),
		_mat_dark if active_tag == 2 else _mat_light)   # join 标签深木（呼应游戏固定件）
	_sync_bounds()
	interaction.refresh_view(false)

## 容器包围盒线框常显（修复批二 F3；隔离性修复批 20260917 R6）：恒按本页域全范围绘制
## （get_size_for_tag(active_tag)；试玩=blocks 域），独立于格集（尺寸应用后立即反映新尺寸，
## 用户可凭线框看出尺寸已生效）。既有「空集才显示」口径作废；格集线框与容器线框合并为同一
## 容器线框（视觉上次于格子本体，避免双重线框观感噪声）。editor_view.gd 的 show_bounds 本就
## 接受尺寸参数，本处仅改调用方传参，视图层零改动。
func _sync_bounds() -> void:
	main_voxel_view.call("show_bounds", _active_domain_size())

## 当前活动会话所属域尺寸（隔离性修复批 20260917 R6 单点化）：编辑态=本页域
## get_size_for_tag(active_tag)（线框/拾取/分母/取景随各自域）；试玩态=blocks 域
## （get_size_for_tag(0)==block_size——试玩以初始木块挖除，视图/拾取/计数全锚 block 域，
## 防从 tag2/3 页进试玩时的拾取几何/线框/分母错位；G8/G10/G15/G16 既有试玩断言零回归）。
func _active_domain_size() -> Vector3i:
	var s: Vector3i = project.get_size_for_tag(0) if _in_playtest else project.get_size_for_tag(active_tag)
	return s

func _active_session() -> RefCounted:
	return _playtest_session if _in_playtest else sessions[active_tag]

## 视图刷新统一入口：hidden 隐藏、shown 显示/新建；空集切包围盒（§7.2 空集起步）。
func _apply_change(res: Dictionary) -> void:
	for c: Variant in res["hidden"]:
		main_voxel_view.call("hide_voxel", c)
	for c: Variant in res["shown"]:
		main_voxel_view.call("add_voxel", c)
	_sync_bounds()
	if interaction != null:
		_sync_pick_context()   # F2：增删格后 look_target 跟随新集 AABB 中心
		interaction.refresh_view()   # 直径随集变化（缩放夹限基准），保当前档位

func _on_dig_requested(cells: Array) -> void:
	var set_dict: Dictionary = {}
	for c: Variant in cells:
		set_dict[c] = true
	var res: Dictionary = _active_session().dig(set_dict)
	_apply_change(res)
	_refresh_status()
	_autosave_current()   # 自动保存挂接点（spec §3.4-2）：试玩中由 _autosave_current 首行守卫封死

func _on_add_requested(cells: Array) -> void:
	if _in_playtest:
		return   # 审查⑥回修 P2-3：试玩=挖除（§8.1）——模式按钮锁定但模式不重置，残留添加模式时封死无幻影预览的加块路径
	var set_dict: Dictionary = {}
	for c: Variant in cells:
		set_dict[c] = true
	var res: Dictionary = _active_session().add(set_dict)
	_apply_change(res)
	main_voxel_view.call("clear_place_preview")   # 放置后清幻影（审查⑤回修 P2-2/D-3）
	_refresh_status()
	_autosave_current()   # 自动保存挂接点（spec §3.4-2）

func _on_selection_changed() -> void:
	_refresh_status()

func _on_hover_changed(cell: Vector3i) -> void:
	if cell.x < 0:
		main_voxel_view.call("clear_hover")
		hover_label.text = "(-,-,-)"
	else:
		main_voxel_view.call("set_hover", cell)
		hover_label.text = "(%d,%d,%d)" % [cell.x, cell.y, cell.z]

func _on_place_target_changed(cell: Vector3i) -> void:
	if not is_add_mode or _in_playtest:
		return
	if cell.x < 0:
		main_voxel_view.call("clear_place_preview")
	else:
		main_voxel_view.call("show_place_preview", cell)

func _apply_undo() -> void:
	var sess = _active_session()
	var unit: Dictionary = sess.undo_stack.back() if sess.can_undo() else {}
	var res: Dictionary = sess.undo()
	_apply_change(res)
	if unit.has("compound"):
		_replay_compound(unit, true)
		_sync_pick_context()   # P2-2：回放后尺寸/格集才定稿，重算 look_target/pick 上下文
		interaction.refresh_view()   # P2-2：再触发相机重挂（否则相机停在回放前 look_target 直到下次交互）
	_refresh_status()
	_autosave_current()   # 自动保存挂接点（spec §3.4-2）：栈操作回放后

func _apply_redo() -> void:
	var sess = _active_session()
	var unit: Dictionary = sess.redo_stack.back() if sess.can_redo() else {}
	var res: Dictionary = sess.redo()
	_apply_change(res)
	if unit.has("compound"):
		_replay_compound(unit, false)
		_sync_pick_context()   # P2-2：回放后尺寸/格集才定稿，重算 look_target/pick 上下文
		interaction.refresh_view()   # P2-2：再触发相机重挂（与 undo 对称）
	interaction.clear_selection()   # 重做移除的格可能正被选中——整组清选区防残留高亮（level_scene.gd:1117-1119 口径）
	_refresh_status()
	_autosave_current()   # 自动保存挂接点（spec §3.4-2）：栈操作回放后

## 键盘：Ctrl+Z=撤销 / Ctrl+Y、Ctrl+Shift+Z=重做 / Esc=清选区（物理键判定，不改输入映射；
## R6 :1400-1428 随迁；试玩分支 T3-2 增补）。
func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var ctrl := key.ctrl_pressed or key.meta_pressed
	var is_z := key.keycode == KEY_Z or key.physical_keycode == KEY_Z
	var is_y := key.keycode == KEY_Y or key.physical_keycode == KEY_Y
	var is_esc := key.keycode == KEY_ESCAPE or key.physical_keycode == KEY_ESCAPE
	if ctrl and is_z:
		if key.shift_pressed:
			_apply_redo()
		else:
			_apply_undo()
	elif ctrl and is_y:
		_apply_redo()
	elif is_esc:
		if _in_playtest:
			_exit_playtest_dialog.popup_centered()   # Esc 退试玩带确认弹窗（T9）
		else:
			interaction.clear_selection()

# ---------- 状态栏（规格 §10.2 行「状态栏」） ----------
func _refresh_status() -> void:
	var cells: Dictionary = _active_session().cells
	var bs: Vector3i = _active_domain_size()   # 隔离性修复批 R6：计数分母=本页域体积（试玩=blocks 域）
	count_label.text = "%d / %d" % [cells.size(), bs.x * bs.y * bs.z]
	# 审查⑥回修 P3-3：试玩中模式标签置试玩文案；退出时 _do_exit_playtest 末尾的本函数调用
	# 即还原既有「模式｜标签名」文案（复用现有刷新路径，不另写还原代码）
	mode_label.text = TITLE_PLAYTEST if _in_playtest \
		else (("添加" if is_add_mode else "挖除") + "｜" + String(TAG_NAMES[active_tag]))

func status_hint(text: String) -> void:
	contract_label.text = text   # 契约提示槽兼操作提示（暂定，走查微调）
	_last_status_text = text     # P2-3：自动保存契约提示去重的「已显示值」基准（任何来源都计入）

# ---------- 尺寸 / 编辑操作 / 模式（规格 §7.2/§7.3；T4 批量区全删后更名 _wire_edit_ops） ----------
func _wire_edit_ops() -> void:
	_make_size_dialog()
	size_x.value_changed.connect(_on_size_draft_changed)
	size_y.value_changed.connect(_on_size_draft_changed)
	size_z.value_changed.connect(_on_size_draft_changed)
	btn_apply_size_one.pressed.connect(_on_apply_size_one_pressed)
	btn_apply_size_all.pressed.connect(_on_apply_size_all_pressed)
	btn_solid.pressed.connect(_on_solid_pressed)
	btn_clear.pressed.connect(_on_clear_pressed)
	btn_copy_base.pressed.connect(_on_copy_base_pressed)
	btn_dig_mode.pressed.connect(_on_mode_changed.bind(false))
	btn_add_mode.pressed.connect(_on_mode_changed.bind(true))

## 尺寸确认弹窗（D2 草稿+应用流程；T2b 复用编辑器现行 ConfirmationDialog 通道）。
func _make_size_dialog() -> void:
	_size_dialog = ConfirmationDialog.new()
	_size_dialog.title = "调整尺寸"   # P2-1：中文标题（D-6 同口径）
	_size_dialog.dialog_text = "确认应用新尺寸？"
	_size_dialog.ok_button_text = "应用"
	_size_dialog.cancel_button_text = "取消"
	_size_dialog.confirmed.connect(_on_size_confirmed)
	_size_dialog.canceled.connect(_revert_size_spins)
	add_child(_size_dialog)

## 草稿态（D2）：SpinBox 改框只写 _size_draft，零触发（不重建/不裁剪/不弹窗/不写 block_size）。
func _on_size_draft_changed(_value: float) -> void:
	if _in_playtest:
		return
	_size_draft = Vector3i(int(size_x.value), int(size_y.value), int(size_z.value))

## 取消/重置草稿：静默写回当前域尺寸并清待应用（带信号回写会再次触发草稿写入）。
## 20260916 槽位化批 D2（规格 §3.2-7）：草稿随域——tag2/tag3 页回填各自域尺寸（join_part.size/final_answer.size）。
func _revert_size_spins() -> void:
	var bs: Vector3i = project.get_size_for_tag(active_tag)
	size_x.set_value_no_signal(bs.x)
	size_y.set_value_no_signal(bs.y)
	size_z.set_value_no_signal(bs.z)
	_size_draft = bs
	_pending_apply = {}

## 有裁剪确认后执行：取出待应用并清空，走统一执行体（D2 新载荷 affected/plan/plan_tags）。
## 批次 U（U12②，双审 P2-4）：confirmed 回调直执 _execute_size_apply 不再过第二道闸
## （零裁剪有覆盖弹窗与本弹窗同走本回调——防重入成环）。
func _on_size_confirmed() -> void:
	if _pending_apply.is_empty():
		return
	var pa: Dictionary = _pending_apply
	_pending_apply = {}
	_execute_size_apply(pa["affected"], pa["plan"], pa["plan_tags"])

## 裁剪明细分隔串（D2 §3.3 短名口径；20260916 槽位化批 §3.2-5 改按 plan_tags 范围遍历；
## 隔离性修复批 20260917 R1：plan_tags=affected——tag0/1 发起=[0,1] 两行、tag2/3 发起=[tag] 一行、
## 全局四行。P1-1「tag2/3 随 block_size 收缩连带裁剪」行废除，join/final 零接触）。
## 批次 V（V-E1，规格 §9.2）：单组件 affected 恒={active_tag}——明细恒单行（本域一行）。
## plan 缺键按空集计，零裁剪="0 格"。
func _size_clip_summary(plan: Dictionary, tags: Array) -> String:
	var parts: Array = []
	var total: int = 0
	for tag_v: Variant in tags:
		var tag: int = tag_v
		var n: int = (plan[tag] as Dictionary).size() if plan.has(tag) else 0
		parts.append("%s: %d 格" % [SIZE_TAG_SHORT[tag], n])
		total += n
	return "0 格" if total == 0 else " / ".join(parts)

## plan 裁剪总数（plan_tags 范围内求和，与 _size_clip_summary 同口径）。
func _plan_clip_total(plan: Dictionary, tags: Array) -> int:
	var total: int = 0
	for tag_v: Variant in tags:
		var tag: int = tag_v
		if plan.has(tag):
			total += (plan[tag] as Dictionary).size()
	return total

## 仅当前组件应用（20260916 槽位化批 D2 拍板②，spec §3.2-5；批次 V §9.2 四域彻底独立重写）：
## affected **恒={active_tag: d}**（批次 V 弃旧 {0:d,1:d} 同料联动——tag1 标准答案写独立
## target_size 字段，tag0/1 互不波及；tag2/3 既有单域语义保持）。
## plan 预演与 plan_tags 恒=affected——只重生当前标签格群、只裁本域；其余三域体素与 size 字段
## 零接触（不删不裁不改写）；超域数据保留不删、照实落盘，由 level_project.contract_hint()
## 超域分支在 _autosave_current 时提示「N 格超出所属组件域尺寸」（批次 V per-domain 口径）。
## 确认框：四标签统一 STATUS_SIZE_CONFIRM_ONE（「仅当前组件域」——批次 V 起 tag0/1 亦用本款，
## STATUS_SIZE_CONFIRM_LINK 联动文案退役，常量删除+注释留痕）；REGEN_NOTE 恒附（受影响页全部
## 重生实心）。零裁剪→U12② 判据分流（「无裁剪但有覆盖」强制确认）。
## noop=草稿==get_size_for_tag(active_tag)（分域判定，spec §3.2-5；批次 V 下 tag1 判据锚 target_size）。
func _on_apply_size_one_pressed() -> void:
	if _in_playtest:
		return
	var d: Vector3i = _size_draft
	if d == project.get_size_for_tag(active_tag):
		status_hint(STATUS_SIZE_NOOP)
		return
	if not LevelProjectScript.is_valid_size(d):
		_revert_size_spins()
		return
	_sync_sessions_to_project()   # plan_shrink_domains 读模型，须先把会话编辑态同步进 Project（否则预演看不到未保存的格子）
	# 批次 V（V-E1，规格 §9.2）：affected 恒={active_tag:d}——弃 {0:d,1:d} 同料联动特例，
	# 单组件应用只写/只重生/只清栈当前标签域。
	var affected: Dictionary = {active_tag: d}
	var plan: Dictionary = project.plan_shrink_domains(affected)   # 预演范围恒=affected（其余三域零接触）
	var plan_tags: Array = affected.keys()
	if _plan_clip_total(plan, plan_tags) > 0:
		_pending_apply = {"affected": affected, "plan": plan, "plan_tags": plan_tags}
		# 批次 V：四标签统一「仅当前组件域」文案（联动文案退役）；REGEN_NOTE 恒附
		# （受影响页=本域按新尺寸重生实心，已有挖除将被覆盖）。
		var dt: String = STATUS_SIZE_CONFIRM_ONE \
			% [d.x, d.y, d.z, _size_clip_summary(plan, plan_tags)]
		dt += "\n" + REGEN_NOTE
		_size_dialog.dialog_text = dt
		_size_dialog.popup_centered()
	else:
		# 批次 U（U12②，双审 P2-4）：零裁剪路径强制确认——仅当全部 affected 页旧体素集==目标
		# 实心集（完全一致、无覆盖）才直接 _execute_size_apply；否则强制弹确认（STATUS_SIZE_CONFIRM
		# 同款文案＋REGEN_NOTE）——「无裁剪但有覆盖」不再跳过。confirmed 回调直执 _execute_size_apply
		# 不再过第二道闸（防重入成环）。
		var old_cells_u: Dictionary = {}
		for tg_u: Variant in affected.keys():
			old_cells_u[int(tg_u)] = sessions[int(tg_u)].cells.duplicate()
		if zero_diff_all(old_cells_u, affected):
			_execute_size_apply(affected, plan, plan_tags)
		else:
			_pending_apply = {"affected": affected, "plan": plan, "plan_tags": plan_tags}
			var dt_u: String = STATUS_SIZE_CONFIRM_ONE \
				% [d.x, d.y, d.z, _size_clip_summary(plan, plan_tags)]
			dt_u += "\n" + REGEN_NOTE
			_size_dialog.dialog_text = dt_u
			_size_dialog.popup_centered()

## 全局应用（20260916 槽位化批 D2 拍板②，spec §3.2-5）：affected={0:d,1:d,2:d,3:d}=现行全量语义
## （四域统一+裁剪+blocks 重生+复合撤销），确认框列四标签明细（现状口径，REGEN_NOTE 恒附）。
## 批次 V（V-E1，规格 §9.2）：四域语义保留，四域写入**各自域字段**（set_size_for_tag 分流后
## tag1 写 target_size 不再联动 block_size，§9.1）；noop=四域尺寸与草稿全等才提示
## STATUS_SIZE_NOOP（部分同值仍执行，plan §11 P4 裁决）。
func _on_apply_size_all_pressed() -> void:
	if _in_playtest:
		return
	var d: Vector3i = _size_draft
	var all_equal: bool = true
	for tag: int in [0, 1, 2, 3]:
		if project.get_size_for_tag(tag) != d:
			all_equal = false
			break
	if all_equal:
		status_hint(STATUS_SIZE_NOOP)
		return
	if not LevelProjectScript.is_valid_size(d):
		_revert_size_spins()
		return
	_sync_sessions_to_project()   # plan_shrink_domains 读模型，须先把会话编辑态同步进 Project（否则预演看不到未保存的格子）
	var affected: Dictionary = {0: d, 1: d, 2: d, 3: d}
	var plan: Dictionary = project.plan_shrink_domains(affected)
	var plan_tags: Array = [0, 1, 2, 3]
	if _plan_clip_total(plan, plan_tags) > 0:
		_pending_apply = {"affected": affected, "plan": plan, "plan_tags": plan_tags}
		var dt: String = STATUS_SIZE_CONFIRM % [d.x, d.y, d.z, _size_clip_summary(plan, plan_tags)]
		dt += "\n" + REGEN_NOTE   # 全局恒含 block_size 域（affected.has(0) 恒真）
		_size_dialog.dialog_text = dt
		_size_dialog.popup_centered()
	else:
		# 批次 U（U12②，双审 P2-4）：零裁剪路径强制确认（同单组件口径——「无裁剪但有覆盖」
		# 不再跳过；confirmed 回调直执 _execute_size_apply 不再过第二道闸，防重入成环）。
		var old_cells_g: Dictionary = {}
		for tg_g: Variant in affected.keys():
			old_cells_g[int(tg_g)] = sessions[int(tg_g)].cells.duplicate()
		if zero_diff_all(old_cells_g, affected):
			_execute_size_apply(affected, plan, plan_tags)
		else:
			_pending_apply = {"affected": affected, "plan": plan, "plan_tags": plan_tags}
			var dt_g: String = STATUS_SIZE_CONFIRM % [d.x, d.y, d.z, _size_clip_summary(plan, plan_tags)]
			dt_g += "\n" + REGEN_NOTE
			_size_dialog.dialog_text = dt_g
			_size_dialog.popup_centered()

## 批次 U（U12②，双审 P2-4）：零裁剪路径「完全一致」判据——逐 tag 旧体素集==solid_cells(affected[tag])。
## 全部一致（无覆盖）才允许跳过确认；任一页有覆盖即强制弹确认。静态纯函数可无头直测
## （test_u_editor_guards 段 1 表驱动）。
static func zero_diff_all(old_cells: Dictionary, affected: Dictionary) -> bool:
	for tg: Variant in affected.keys():
		var t: int = tg
		var solid: Dictionary = LevelProjectScript.solid_cells(affected[t])
		var old_set: Dictionary = old_cells[t]
		if old_set.size() != solid.size():
			return false
		for k: Variant in solid:
			if not old_set.has(k):
				return false
	return true

## 格集差（F3 重生单元构造）：removed=应用前有、应用后无（Session.undo 逆做需恢复/显示）、
## added=应用前无、应用后有（Session.undo 逆做需移除/隐藏）——与 voxel_edit_ops.undo 实际语义一致。
func _cells_diff(cells: Dictionary, target: Dictionary) -> Dictionary:
	var removed: Array = []
	var added: Array = []
	for k: Variant in cells:
		if not target.has(k):
			removed.append(k)
	for k: Variant in target:
		if not cells.has(k):
			added.append(k)
	return {"removed": removed, "added": added}

## 尺寸应用执行体（D2 + 修复批二 F3；20260916 槽位化批 §3.2-3 新签名；批次 V §9.2 四域独立收窄）：
## affected={tag: 新尺寸}=size 字段将被改写的域；plan={tag: 裁剪格集}；plan_tags=体素集将被处理的
## 标签（=affected：批次 V 下单组件发起=[active_tag] 单页、全局=[0,1,2,3] 四页；plan_tags 外的域
## 零接触——体素、size 字段、撤销栈均不动）。执行序：old_sizes 捕获（仅 affected 域；tag1 经
## set_size_for_tag 分流写 target_size，§9.1）→ 逐域快照旧格集（重生差异基准）→ 逐 tag
## set_size_for_tag → 对 plan_tags 内标签 remove_no_stack(plan[tag])（不入栈）→ regen 推广：对
## plan_tags 内全部域逐一重生实心（solid_cells(affected[tag])，原地清写 cells 保留撤销栈活引用
## 语义，差集对归 by_tag[tag]）→ push_compound（只推发起标签栈）→ 视图/状态栏反馈 → 自动保存 →
## u08 回修尾注：应用产生超域（N>0，count_over_domain_cells per-domain 口径）时 toast 补知情提示。
## 顶层 removed/added 恒=发起标签自身「裁剪+重生定稿差集对」（R0/A0 泛化）：单组件发起=本页重生
## 差集对、全局发起=发起页重生差集对（原「tag0 发起才取重生对」特例随全路径重生退役——
## by_tag[active_tag] 即定稿差集对，顶层直接取用）。
## removed_by_tag 每项={removed: Array, added: Array} 对结构沿用（P0-1）；plan_tags 外标签无键
## （批次 V 单域应用：by_tag 恒单键 active_tag，old_sizes/new_sizes 同为单域——复合单元只含本域
## old/new，§9.2）。
## 复合回放 _replay_compound 零结构改动（old_sizes/new_sizes/removed_by_tag/regen 键沿用）。
func _execute_size_apply(affected: Dictionary, plan: Dictionary, plan_tags: Array) -> void:
	var old_sizes: Dictionary = {}
	for tag_v: Variant in affected:
		old_sizes[tag_v] = project.get_size_for_tag(tag_v)
	# R2/R3/R4：逐域应用前快照——重生差异相对「该域应用前旧集」计算（F3 旧口径仅快照 blocks）。
	var old_cells_by_tag: Dictionary = {}
	for tag_v: Variant in plan_tags:
		old_cells_by_tag[tag_v] = sessions[tag_v].cells.duplicate()
	for tag_v: Variant in affected:
		project.set_size_for_tag(tag_v, affected[tag_v])
	var by_tag: Dictionary = {}
	for tag_v: Variant in plan_tags:
		var tag: int = tag_v
		var clip_set: Dictionary = plan[tag] if plan.has(tag) else {}
		var hidden: Array = (sessions[tag].remove_no_stack(clip_set) as Dictionary)["hidden"]
		by_tag[tag] = {"removed": hidden, "added": []}
	# R2/R3/R4：regen 推广——对 plan_tags 内全部域逐一重生实心（批次 V §9.2：单组件发起=本页、
	# 全局=四页）。原地清写 cells（不调 setup）：维持 interaction 持有的活引用
	# 语义（setup 会替换字典对象使活引用失效）；差异相对「应用前该域旧集」计算。
	# 批次 U（U12③，双审 P2-7）：显式推翻「保留撤销栈（线性历史）」旧决策——尺寸应用后清栈
	# 精化（见函数尾），越界回放风险根除优先。
	for tag_v: Variant in plan_tags:
		var tag: int = tag_v
		var solid: Dictionary = LevelProjectScript.solid_cells(affected[tag])
		var diff: Dictionary = _cells_diff(old_cells_by_tag[tag], solid)
		sessions[tag].cells.clear()
		for k: Variant in solid:
			sessions[tag].cells[k] = true
		by_tag[tag] = {"removed": diff["removed"], "added": diff["added"]}   # P0-1：重生差集对归 by_tag[tag]
	var unit_removed: Array = (by_tag[active_tag] as Dictionary)["removed"]
	var unit_added: Array = (by_tag[active_tag] as Dictionary)["added"]
	sessions[active_tag].push_compound({"removed": unit_removed, "added": unit_added,
		"compound": {"old_sizes": old_sizes, "new_sizes": affected.duplicate(),
			"removed_by_tag": by_tag, "regen": true}})
	# 批次 U（U12③，双审 P2-7）：清栈精化——发起标签撤销栈重置为仅含本次 compound 单元、重做栈
	# 清空（Ctrl+Z 回退本次应用，更早历史一并清除）。voxel_edit_ops.gd 本体零改动——直操
	# Session.undo_stack/redo_stack 成员；根除发起域越界回放（无界校验由清栈根除，spec §4-U12-③）。
	# 批次 V（V-E1，规格 §9.2）收窄：清栈范围**只触 plan_tags（受影响域）**——旧实现「plan_tags 外
	# 全清」循环随单域应用退役删除：四域彻底独立后，单组件应用只改本域 size+cells，其他三域的
	# 域尺寸与格群逐字节不变，其撤销单元回放前提（自家域尺寸/格群未变）恒成立，历史保留即可安全
	# 回放（用户主诉「撤销历史被清」的修复本体）；plan_tags 内非发起标签（仅全局应用存在）栈顶是
	# 应用前旧单元（本次 compound 未推入其栈），保留即越界回放+不一致中间态——双栈全清维持
	# U12③ 口径（其重生差集已由发起标签 compound 的 removed_by_tag 承载，undo 经
	# _replay_compound 按域还原，全清无损）。
	for tag_i: Variant in plan_tags:
		var t_i: int = tag_i
		if t_i == active_tag:
			var top: Variant = sessions[t_i].undo_stack.back()
			sessions[t_i].undo_stack.clear()
			if top != null:
				sessions[t_i].undo_stack.append(top)
			sessions[t_i].redo_stack.clear()
		else:
			# plan_tags 内非活跃发起标签（全局应用的非发起页）——双栈全清（U12③ 既有处置；
			# 批次 V 下该分支仅全局应用可达，单组件 plan_tags=[active_tag] 无此分支）。
			sessions[t_i].undo_stack.clear()
			sessions[t_i].redo_stack.clear()
	_size_draft = affected[active_tag]
	_sync_pick_context()
	_rebuild_active_view()
	var is_global: bool = affected.size() == 4   # 全局=四域入参；单组件=单键 {active_tag}（批次 V 弃 {0,1} 两键特例）
	# R2/R3/R4：所有应用路径恒重生（plan_tags 全域重建实心）——STATUS_SIZE_APPLIED(_ONE)「只裁不
	# 重生」分支退役（常量保留退役留痕），反馈恒用重生文案。
	var msg: String = (STATUS_SIZE_REGEN if is_global else STATUS_SIZE_REGEN_ONE) \
		% [affected[active_tag].x, affected[active_tag].y, affected[active_tag].z,
			affected[active_tag].x * affected[active_tag].y * affected[active_tag].z]
	status_hint(msg)
	show_toast(msg)
	_refresh_status()
	_autosave_current()   # 自动保存挂接点（spec §3.4-2）：应用生效后（status/toast/_refresh_status 后）
	# u08 回修（20260917）：应用可能使其他域体素超出其所属域（全局收缩各域、或本域新尺寸小于既有
	# 体素——W_走查判定表 u08 NG 实证），契约提示唯一状态栏通道被上方
	# status_hint(应用反馈) 占用（P2-3 门恒关）→ 知情提示被永久吞没；改走 toast 通道补知
	# （底部中央浮层 2.5s 自愈，与状态栏零争用；状态栏契约提示机制不动，G7/G20/G21/G26 断言零回归）。
	# N 计数复用 level_project.count_over_domain_cells（与 contract_hint 超域分支同源，避免逻辑双写；
	# 批次 V（V-E1）：计数改 per-domain——各格集按所属域自身尺寸计越界，N=「游戏加载将被裁剪格数」）。
	var over: int = project.count_over_domain_cells()
	if over > 0:
		show_toast(LevelProjectScript.HINT_OVER_DOMAIN % over)

## 复合单元回放（编排层，接口 2；20260916 槽位化批 §3.2-4 按域还原，P0-1 对位改造）：
## undo=逐 tag（old_sizes 键）set_size_for_tag 还原各域尺寸 + 对 by_tag 各项「cells 加回
## item.removed / 擦除 item.added」；redo=逐 tag set new_sizes + 反向「擦除 item.removed / 加回
## item.added」。发起标签的格集已由 Session.undo/redo 常规通道回放（顶层键），编排层循环对其幂等
## （重复置位/擦除无副作用，现状 :657-663 同款纪律）。
## 批次 V（V-E1，规格 §9.2）：单域复合单元只含发起域 old/new（old_sizes/removed_by_tag 单键），
## 本循环按键遍历天然收敛为单域回放——其他三域尺寸/格群零触碰（结构零改动，键集收窄即达成）。
func _replay_compound(unit: Dictionary, is_undo: bool) -> void:
	var cp: Dictionary = unit["compound"]
	var sizes: Dictionary = cp["old_sizes"] if is_undo else cp["new_sizes"]
	for tag_v: Variant in sizes:
		project.set_size_for_tag(tag_v, sizes[tag_v])
	var by_tag: Dictionary = cp["removed_by_tag"]
	for tag_v: Variant in by_tag:
		var tag: int = tag_v
		var item: Dictionary = by_tag[tag_v]
		var sess = sessions[tag]
		if is_undo:
			for c_v: Variant in item["removed"]:
				sess.cells[c_v] = true
			for c_v: Variant in item["added"]:
				sess.cells.erase(c_v)
		else:
			for c_v: Variant in item["removed"]:
				sess.cells.erase(c_v)
			for c_v: Variant in item["added"]:
				sess.cells[c_v] = true
	_sync_bounds()   # F3：尺寸随单元回放变化，容器线框须同步到回放后的 block_size
	# P2-3：尺寸控件与草稿须随当前域尺寸回滚（否则 undo 后三态矛盾：SpinBox=新/线框=旧/草稿=新，
	# 此时误点「应用尺寸」会把新尺寸重新应用、变相吞掉用户的尺寸 undo）。复用 _sync_size_spins 通道
	# （读 get_size_for_tag(active_tag)），随后显式对齐 _size_draft 收口终态。
	_sync_size_spins()
	_size_draft = project.get_size_for_tag(active_tag)

func _on_mode_changed(add_mode: bool) -> void:
	is_add_mode = add_mode
	interaction.set_mode(add_mode)
	main_voxel_view.call("clear_place_preview")
	_refresh_status()

func _on_solid_pressed() -> void:
	# 隔离性修复批 20260917 R5：一键实心恒本页域（旧 :748 get_block_size 正是痛点②「tag2/3 页被
	# 填成 blocks 域实心」根因——tag2/3 页改按 join_part.size/final_answer.size 满域重生）。
	var res: Dictionary = _active_session().set_cells(
		LevelProjectScript.solid_cells(project.get_size_for_tag(active_tag)))
	_apply_change(res)
	_refresh_status()
	_autosave_current()   # 自动保存挂接点（spec §3.4-2）

func _on_clear_pressed() -> void:
	var res: Dictionary = _active_session().set_cells({})
	_apply_change(res)
	_refresh_status()
	_autosave_current()   # 自动保存挂接点（spec §3.4-2）

## 复制初始块为基底（§7.3）：blocks 当前集深拷贝覆盖本标签，一个撤销单元；重复点击=再次覆盖。
## 批次 V（V-E4）适配：四域独立后源域（blocks）格可超出目标域尺寸——目标域尺寸为权威，
## 复制前按 get_size_for_tag(active_tag) 裁剪落格（源域超界格不复制；不引入新弹窗）。
## 判定留痕（V-E1 遗留风险点审视）：复制流只搬格集、从不写任何域尺寸字段，且 active_tag==0
## 早退保证无「目标域→blocks」反向流——跨域污染面=「源域超界格流入目标域」，以目标域裁剪收口
## （裁剪后超域计数 0，游戏加载零裁剪意外；test_v_editor_opmatrix 序⑩锁定）。
func _on_copy_base_pressed() -> void:
	if active_tag == 0 or _in_playtest:
		return
	var dom: Vector3i = project.get_size_for_tag(active_tag)
	var clipped: Dictionary = {}
	for c: Variant in sessions[0].cells:
		var cell: Vector3i = c
		if cell.x >= 0 and cell.x < dom.x and cell.y >= 0 and cell.y < dom.y and cell.z >= 0 and cell.z < dom.z:
			clipped[cell] = true
	var res: Dictionary = _active_session().set_cells(clipped)
	_apply_change(res)
	_refresh_status()
	_autosave_current()   # 自动保存挂接点（spec §3.4-2）

# ---------- 试玩模式（规格 §8.1/§8.2/§8.3，T3-2 实装；T3-3 走查回修 D-4/D-6/D-7） ----------
# 侧视相机常量照抄游戏 level_scene.gd（T3-3 回修 D-4）：SIDE_YAW0_DEG/SIDE_PITCH0_DEG（:53-54，
# M-E 统一真等轴测口径）、SIDE_ORTHO_DIST（:40，下限距离——审查⑦回修 P1-1：大集自适应
# max(20, 包围球半径+1)，同根因随 D-4 复制进本函数）、SIDE_FILL_W0（:48）、
# VIEW_FIT_MARGIN（:49）、ORTHO_NEAR/FAR（:41-42）。
const SIDE_YAW0_DEG := 45.0
const SIDE_PITCH0_DEG := 35.264
const SIDE_ORTHO_DIST := 20.0
const SIDE_FILL_W0 := 0.70
const SIDE_FIT_MARGIN := 8.0
const SIDE_ORTHO_NEAR := 0.1
const SIDE_ORTHO_FAR := 100.0
const LOCKED_PANEL_DIM := Color(1, 1, 1, 0.55)   # 批次 W（P3-5f）：锁定变暗改 self_modulate 落面板背景自身（旧 LOCKED_PANEL_MODULATE 整体 modulate 乘算连文字一起降对比；D-7 视觉差保留）
const TITLE_PLAYTEST := "试玩中（以初始木块挖除）"   # 审查⑥回修 P3-3：试玩中主标题/模式标签文案（防显示进入前标签名）
## 批次 Y6（Y-D4）：success 常驻通关横幅文案（沿用原 success toast 文案语义，通道升级为常驻）。
const PLAYTEST_SUCCESS_TEXT := "试玩成功：与标准答案一致（试玩不落档，退出还原编辑态）"

func _wire_playtest() -> void:
	_judge_script = load("res://scripts/playtest_judge.gd")
	btn_playtest.disabled = false
	btn_playtest.pressed.connect(_on_playtest_pressed)
	btn_join.pressed.connect(_on_join_pressed)
	# 批次 Y6（Y-D4）：对接判定按钮 hover 提示补判定语义（对称/旋转/镜像均认可=48 变换等价口径）。
	btn_join.tooltip_text = "判定剩余木块是否与标准答案一致（对称/旋转/镜像均认可）"
	_exit_playtest_dialog = ConfirmationDialog.new()
	_exit_playtest_dialog.title = "退出试玩"   # D-6：中文标题（默认 Please Confirm... 与游戏中文 UI 不符）
	_exit_playtest_dialog.dialog_text = "退出试玩将丢弃试玩挖除进度"
	_exit_playtest_dialog.ok_button_text = "退出"
	_exit_playtest_dialog.cancel_button_text = "继续试玩"
	_exit_playtest_dialog.confirmed.connect(_do_exit_playtest)
	add_child(_exit_playtest_dialog)

func _on_playtest_pressed() -> void:
	if _in_playtest:
		_exit_playtest_dialog.popup_centered()   # 防误触确认（对齐游戏退关确认习惯 level_scene.gd:1894）
	else:
		_enter_playtest()

## 批次 V（V-E4）：撤销/重做栈快照深拷贝（单元={removed,added[,compound]}；普通单元逐数组拷贝、
## compound 复合单元整体深拷贝——试玩进出不动编辑撤销栈，快照回填语义见 _enter_playtest 注）。
func _dup_stack_snapshot(arr: Array) -> Array:
	var out: Array = []
	for u: Variant in arr:
		var unit: Dictionary = u
		var cp: Dictionary = {
			"removed": (unit.get("removed", []) as Array).duplicate(),
			"added": (unit.get("added", []) as Array).duplicate(),
		}
		if unit.has("compound"):
			cp["compound"] = (unit.get("compound", {}) as Dictionary).duplicate(true)
		out.append(cp)
	return out

## 进入：四件套体素集+元数据内存深拷贝快照；试玩会话=临时 Session（初始=blocks 当前集，
## 独立撤销栈）；左侧面板编辑控件禁用置灰；顶栏「对接」出现；三面板取景对齐游戏代码实况
## （§8.2：左上=target_shapes[0]、右上=join 深木、中央=blocks 快照）。不写任何文件、
## 不动编辑会话与编辑撤销栈（试玩不落档，拍板 5）。
## 批次 V（V-E4）：快照增记四会话撤销/重做双栈深拷贝——退出侧 setup() 还原格群会清双栈，
## 栈快照在退出时回填，落实本注释「不动编辑撤销栈」承诺（用户主诉「撤销历史被清」试玩路径收口，
## test_v_editor_opmatrix 序⑤/⑥/⑨B 锁定）。
func _enter_playtest() -> void:
	_playtest_snapshot = {
		"sets": {
			0: sessions[0].cells.duplicate(),
			1: sessions[1].cells.duplicate(),
			2: sessions[2].cells.duplicate(),
			3: sessions[3].cells.duplicate(),
		},
		"data": project.snapshot_data(),
		"tag": active_tag,
		# 批次 V（V-E4）：撤销/重做双栈快照（单元深拷贝，compound 复合键保全）。
		"undo_stacks": {
			0: _dup_stack_snapshot(sessions[0].undo_stack),
			1: _dup_stack_snapshot(sessions[1].undo_stack),
			2: _dup_stack_snapshot(sessions[2].undo_stack),
			3: _dup_stack_snapshot(sessions[3].undo_stack),
		},
		"redo_stacks": {
			0: _dup_stack_snapshot(sessions[0].redo_stack),
			1: _dup_stack_snapshot(sessions[1].redo_stack),
			2: _dup_stack_snapshot(sessions[2].redo_stack),
			3: _dup_stack_snapshot(sessions[3].redo_stack),
		},
		# 退役留痕（spec §3.4-4/P2⑤）：快照原 "dirty" 项随 dirty 退役删除——试玩挖除不再污染任何
		# 标记（_autosave_current 首行守卫使其也不落盘）。
	}
	_playtest_session = SessionScript.new()
	_playtest_session.setup(sessions[0].cells.duplicate())
	_in_playtest = true
	_set_editing_ui_locked(true)
	btn_join.visible = true
	btn_playtest.text = "退出试玩"
	playtest_banner.visible = false   # 批次 Y6（Y-D4）：进试玩新局清除上一局通关横幅
	# 隔离性修复批 20260917 R6 + 批次 Z Z1（spec §1 三者同改·用户拍板）：三面板 build_set
	# 各自域（main=get_size_for_tag(0)、左上「最终成品」=sessions[3]/get_size_for_tag(3)=final
	# 域〔Z1 渲染由 target(1) 换源 final(3)，与标题/副标题同改〕、join=get_size_for_tag(2)）
	# ——旧恒 get_block_size，join/final 域独立尺寸时预览错域。
	target_voxel_view.call("build_set", sessions[3].cells, project.get_size_for_tag(3), _mat_light)
	join_voxel_view.call("build_set", sessions[2].cells, project.get_size_for_tag(2), _mat_dark)
	main_voxel_view.call("build_set", _playtest_session.cells, project.get_size_for_tag(0), _mat_light)
	_update_side_camera("Target", sessions[3].cells)   # D-4+Z1：左上取景=最终成品集（Z1 换源 final）
	_update_side_camera("Join", sessions[2].cells)     # D-4：右上取景=对接件集（走查 w12d 面板空）
	_bind_view_interactions()   # T3：上两面板只读旋转缩放
	_apply_layout(LAYOUT_PLAYTEST)
	interaction.clear_selection()
	_sync_pick_context()
	_refresh_status()
	main_title.text = TITLE_PLAYTEST   # 审查⑥回修 P3-3：主标题随试玩态切换（ModeLabel 由 _refresh_status 试玩分支置换）
	show_toast("试玩中：以当前初始木块为起点挖除，「对接」判定与游戏同源（试玩不落档）")

func _set_editing_ui_locked(locked: bool) -> void:
	for c: Control in _locked_controls():
		if c is SpinBox or c is LineEdit:
			c.editable = not locked   # SpinBox/LineEdit 4.7 无 disabled 属性（红跑实证），置只读等价禁用；处理器另有 _in_playtest 守卫兜底
		else:
			c.disabled = locked
	# 退役留痕（spec §3.6-4）：btn_new/open/save 三钮行随三钮退役删除——五槽位钮入 _locked_controls
	# 由通用循环接管 disabled。
	# 批次 W（P3-5f，规格 §7）：锁定变暗不再走 modulate 乘算（LeftPanel 整棵子树含文字一起
	# 半透明，暗底上文字对比度受损——W0 §P3-5f）；改 self_modulate 只作用于面板自身绘制
	# （StyleBox 背景），子控件/文字不受乘算，文字对比度保持；D-7「锁定有视觉差」保留。
	left_panel.self_modulate = LOCKED_PANEL_DIM if locked else Color.WHITE

func _locked_controls() -> Array:
	return [tab_blocks, tab_target, tab_join, tab_final, size_x, size_y, size_z,
		btn_apply_size_one, btn_apply_size_all,
		btn_solid, btn_clear, btn_copy_base, btn_dig_mode, btn_add_mode,
		btn_slot1, btn_slot2, btn_slot3, btn_slot4, btn_slot5]
	# 退役留痕（批次 W W5，N16 拍板 9）：btn_export_contract 随导出按钮退役移出锁定清单。

## T3：绑定上两面板 VIEW 只读交互（gui_input 挂各自 SubViewportContainer）+ 注入拾取/注视上下文。
func _bind_view_interactions() -> void:
	_view_interaction_target.bind(target_vc, target_viewport, target_cam, InteractionScript.BindMode.VIEW)
	_view_interaction_join.bind(join_vc, join_viewport, join_cam, InteractionScript.BindMode.VIEW)
	# 批次 Z Z1：左上面板渲染换源 final——只读交互上下文随 final 集合（sessions[3]/域 3）。
	_sync_view_context(_view_interaction_target, target_voxel_view, sessions[3].cells, 3)
	_sync_view_context(_view_interaction_join, join_voxel_view, sessions[2].cells, 2)

## T3：解绑上两面板 VIEW 交互（退出试玩）。
func _unbind_view_interactions() -> void:
	_view_interaction_target.unbind()
	_view_interaction_join.unbind()

## T3：注入 VIEW 实例上下文——直径（集合尺寸）、注视目标（集中心−视图中心偏移，与 _update_side_camera
## 注视目标同式）、反解相机位姿（首次拖拽/滚轮零跳变）。
## 隔离性修复批 20260917 R6：签名增加所属标签参数 tag（int 显式注解）——注入尺寸
## 改 get_size_for_tag(tag)（Target=3〔Z1：final 域，与面板渲染同源〕/Join=2 各自域），旧恒
## get_block_size 在 join/final 域独立尺寸时拾取/取景上下文错域。
## 审查回修批 P1-1：夹持下限同源化——VIEW 下限注入「包围球直径」（span=diameter 的零边距口径，
## 与两处 fit 同源），必 < 播种值（播种值的垂直约束含 ≥0 边距），故首次拖拽/滚轮不再被本层 24px
## 口径夹高，且 zoom in 仍有一档以内空间（回得到标准档以内）。注：若直接注入播种值当 floor，则
## zoom in 会被夹回播种值（无向内空间），无法满足「zoom in 后 size 严格小于播种值」的行为契约。
func _sync_view_context(vi: Node, view: Node, cells: Dictionary, tag: int) -> void:
	var bs: Vector3i = project.get_size_for_tag(tag)
	vi.set_pick_context(cells, bs, Vector3(bs) * 0.5)
	vi.set_look_target(InteractionScript.cells_center(cells) - (view.call("get_center_offset") as Vector3))
	vi.set_ortho_floor(_cells_sphere_diameter(cells))
	vi.sync_from_camera()

## 试玩侧视相机布置（T3-3 回修 D-4，照抄游戏 level_scene.gd:1537-1552 _update_side_camera）：
## 正交参数兜底 + 等轴测轨道位姿（位置=距离×(sin yaw·cos pitch, sin pitch, cos yaw·cos pitch)，
## yaw=SIDE_YAW0_DEG/pitch=SIDE_PITCH0_DEG）+ look_at + ortho size 适配。
## 审查⑦回修 P1-1：轨道距离自适应 dist=max(SIDE_ORTHO_DIST, 包围球半径+1.0)（半径=既有
## _cells_sphere_diameter/2，与 _side_fit_ortho_size 同源不改动）——32³ 满块半径≈27.7>20 时恒距
## 会把最近角推到 near 平面之后（同根因随 D-4 复制进本函数），自适应后最近角深度恒 1.0>near，
## far 复核 dist+r=2r+1<100 ⇔ 直径<99；小集（3³ r≈2.6）仍取 20 与游戏原行为一致。
## 游戏侧 VoxelView 以「体素集自身 AABB 中心」为原点故恒 look_at(ZERO)；编辑器视图中心定锚
## block_size 中心（editor_view.gd 改造①），故 look_at 目标=集 AABB 中心−视图中心偏移
## （与游戏「集居中取景」同语义——join 少体素且离对角线时格子不再出视锥）。空集不布置
## （保持 tscn 等轴测兜底位姿）。仅试玩进出构建路径调用（level_scene.gd:505 坑 9 同款纪律）。
## 相机不进快照：退出后面板隐藏即无取景态，重进按当时体素集重新布置。
func _update_side_camera(which: String, cells: Dictionary) -> void:
	var vp: SubViewport = target_viewport if which == "Target" else join_viewport
	var view: Node = target_voxel_view if which == "Target" else join_voxel_view
	var cam: Camera3D = vp.get_node_or_null("Camera3D") as Camera3D
	if cam == null or cells.is_empty():
		return
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL   # 游戏 _apply_ortho_cam :1253-1256 兜底同款
	cam.near = SIDE_ORTHO_NEAR
	cam.far = SIDE_ORTHO_FAR
	var yaw := deg_to_rad(SIDE_YAW0_DEG)
	var pitch := deg_to_rad(SIDE_PITCH0_DEG)
	var dist := maxf(SIDE_ORTHO_DIST, _cells_sphere_diameter(cells) * 0.5 + 1.0)   # 审查⑦回修 P1-1
	cam.position = dist * Vector3(
		sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var center_off: Vector3 = view.call("get_center_offset")   # RefCounted/Node 成员调用显式注解
	cam.look_at(InteractionScript.cells_center(cells) - center_off, Vector3.UP)
	var sz := _side_fit_ortho_size(_cells_sphere_diameter(cells), vp)
	if sz > 0.0:
		cam.size = sz

## 试玩侧视 ortho size 适配（照抄游戏 level_scene.gd:706-717 _ortho_size_fit 同式；N 批统一口径
## 跨度=包围球直径、宽向 fill=SIDE_FILL_W0、垂直完整约束留边=SIDE_FIT_MARGIN；视口未布局兜底
## d×2=editor_interaction.gd:118-126 同款）。游戏侧 _ortho_size_min_for 缩放保底不随迁（编辑器
## 侧视无滚轮/旋转交互，无缩放档位可保）。
func _side_fit_ortho_size(d: float, vp: SubViewport) -> float:
	if d <= 0.0:
		return 0.0
	var vs := Vector2(vp.size)
	if vs.y < 1.0 or vs.x < 1.0:
		return d * 2.0
	var by_w := d / maxf(SIDE_FILL_W0 * (vs.x / vs.y), 0.0001)
	var by_h := d * vs.y / maxf(vs.y - 2.0 * SIDE_FIT_MARGIN, 1.0)
	return maxf(by_w, by_h)

## 格集包围球直径（游戏 level_scene.gd:744-753 _cells_sphere_diameter 同式；空集 0）。
static func _cells_sphere_diameter(cells: Dictionary) -> float:
	var mn := Vector3i(1 << 29, 1 << 29, 1 << 29)
	var mx := Vector3i(-(1 << 29), -(1 << 29), -(1 << 29))
	for c: Variant in cells:
		var p := Vector3i(c)
		mn.x = mini(mn.x, p.x); mn.y = mini(mn.y, p.y); mn.z = mini(mn.z, p.z)
		mx.x = maxi(mx.x, p.x); mx.y = maxi(mx.y, p.y); mx.z = maxi(mx.z, p.z)
	if mx.x < 0:
		return 0.0
	return Vector3(mx - mn + Vector3i.ONE).length()

## 退出：编辑态从快照整体还原（四会话 reset+元数据还原+表单/尺寸/标签态/视图重建）；
## 试玩会话即弃。快照还原是兜底，隔离是主防线（§8.1）。
## 批次 V（V-E4）：setup() 还原格群会清双栈——撤销/重做历史改由快照回填（进试玩时深拷贝），
## 落实 spec §8.1 拍板 5「不动编辑会话与编辑撤销栈」（test_v_editor_opmatrix 序⑤逐字节锁定）。
## 退役留痕（spec §3.4-4/P2⑤）：dirty 标记还原行、_load_meta_form()（元数据表单随 UI 退役）、
## _last_title 赋值（title→name 联动退役）三行删除。
func _do_exit_playtest() -> void:
	_in_playtest = false
	_playtest_session = null
	project.restore_data(_playtest_snapshot["data"])
	var sets: Dictionary = _playtest_snapshot["sets"]
	for tag: int in [0, 1, 2, 3]:
		sessions[tag].setup(sets[tag])
		sessions[tag].undo_stack = _playtest_snapshot["undo_stacks"][tag]   # 批次 V（V-E4）：历史回填
		sessions[tag].redo_stack = _playtest_snapshot["redo_stacks"][tag]
	_set_editing_ui_locked(false)
	btn_join.visible = false
	btn_playtest.text = "试玩"
	playtest_banner.visible = false   # 批次 Y6（Y-D4）：退出试玩清除通关横幅
	_apply_layout(LAYOUT_EDIT)
	_unbind_view_interactions()   # T3：解绑上两面板只读交互
	_update_side_camera("Target", sessions[3].cells)   # D3+Z1：退出复位等轴测机位（Z1 换源 final 集，与进试玩口径一致）
	_update_side_camera("Join", sessions[2].cells)
	active_tag = int(_playtest_snapshot["tag"])
	_sync_tab_buttons()
	main_title.text = String(TAG_NAMES[active_tag])   # 审查⑥回修 P3-3：还原进入前标签名（switch_tag 同式）
	_sync_size_spins()
	_size_draft = project.get_size_for_tag(active_tag)   # D2 §3.2-7 草稿随域：退出试玩草稿对齐当前域尺寸（与上行 _sync_size_spins 同源，防三态矛盾）
	interaction.clear_selection()
	_sync_pick_context()
	_rebuild_active_view()
	_refresh_status()
	_sync_slot_buttons()   # R8 对策：强制按 _current_slot 重高亮（disabled 瞬间残留视觉态兜底）
	_autosave_current()   # 自动保存挂接点（spec §3.4-3）：快照还原后等价重写（幂等，load→save 确定性）

func _sync_size_spins() -> void:
	var bs: Vector3i = project.get_size_for_tag(active_tag)   # RefCounted 成员调用返回 Variant，禁 := 推断（显式注解）；D2 §3.2-7：回填当前 active_tag 所属域尺寸
	size_x.value = bs.x
	size_y.value = bs.y
	size_z.value = bs.z

## 对接判定（§8.3）：playtest_judge.judge(试玩剩余集, [target 体素集], join 体素集)；
## 失败仅提示不改状态、无惩罚、次数不限（与游戏 _on_join_pressed 同口径，level_scene.gd:2003）；
## final_answer 不参与试玩判定（与真游戏一致，evaluate_join 不消费 final_answer）。
func _on_join_pressed() -> void:
	if not _in_playtest or _judge_script == null:
		return
	var result: String = _judge_script.judge(
		_playtest_session.cells,
		[sessions[1].cells.keys()],
		sessions[2].cells.keys())
	match result:
		"success":
			show_success_banner()   # 批次 Y6（Y-D4）：success 升级常驻通关横幅（不吃 2.5s 自愈）
		"unfit":
			show_toast("无法对接：木料与固定件干涉，请调整挖除位置")
		"wrong":
			show_toast("答案错误：当前形状与目标不一致")

## 批次 Y6（Y-D4，spec §9.4）：success 常驻通关横幅——显示后不自愈，仅在进试玩新局
## （_enter_playtest）或退出试玩（_do_exit_playtest）时清除；unfit/wrong 维持 2.5s toast。
func show_success_banner() -> void:
	playtest_banner.text = PLAYTEST_SUCCESS_TEXT
	playtest_banner.visible = true

## 顶部中央浮动提示 2.5 秒（T9；对齐游戏 toast 习惯 level_scene.gd:1464-1467）。
func show_toast(text: String) -> void:
	playtest_toast.text = text
	playtest_toast.visible = true
	var timer := get_tree().create_timer(2.5)
	timer.timeout.connect(func() -> void:
		if playtest_toast.text == text:
			playtest_toast.visible = false)
