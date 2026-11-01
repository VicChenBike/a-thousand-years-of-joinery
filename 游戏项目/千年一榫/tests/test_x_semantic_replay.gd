extends "res://tests/test_base.gd"
## 批次 X X5 波（spec §7 P6，20260921）——真手失效逐段排查·语义层回放测试。
##
## 回放链路：x5_probe_temp.py（临时探针，AI工作记录/批次X_走查_20260921/）构造六组「真手典型
## 序列」（MediaPipe 归一坐标风格 21×[x,y,z]，真手比例/翻面 2D 镜像投影/推拉近大远小缩放），
## 逐帧喂生产 gesture_engine.GestureEngine（Python 生产语义零改动），把 UDP 载荷级手 dict
## （server :812-822 组包同款）固化为 fixtures/x5_hands_replay.json；本件逐帧回放喂
## gesture_map.gd（now 注入零真时钟依赖）+ router 消费段（真 level_scene），逐手势断言意图。
##
## 逐手势结论锚（证实即修=断言锁定；证伪结案=现状断言留证据）：
##   A  左手掌推拉-快推（0.4s 内 20%）→ zoom_begin+zoom_step(dir=+1)
##   A2 左手掌推拉-慢启动（掌稳 0.67s 超旧观察窗后推 25%）→ zoom_begin
##      （X5 修复：观察窗过期基准重置——红测实证旧语义下永不触发）
##   A3 右手掌推拉（批次 AA W3-1 等价改写：旧「右手 palm=清空、无缩放」退役）→ zoom_begin 零 clear
##   B  右手竖四指 + 静止 dwell 1.0s → clear（批次 AA W3-2 等价改写：旧「双帧即 clear」退役；
##      夹具 17 帧不足 dwell 窗 → _replay_case 尾接静默续帧，夹具 JSON 不动）
##   C  左手竖掌左右翻 → undo（X5 修复：翻转前置去 roll<30° 绝对方向门——真手竖掌
##      roll≈270° 下旧前置永不锁定，撤销/重做真手 100% 失效；红测实证）
##   C2 右手竖掌左右翻 → redo（同 C）
##   D  左手食指→竖中指 → two_down（新左键笔模型对真手序列通过率证实）
##   D2 左手二指+无名指跟伸（变体）→ delete（three 误入风险量化记录，现状行为锁定）
##   E  右手食指→竖中指 → two_down(side=right)（Ctrl 减选笔通过率证实）
##   F  左手竖三指 → delete
## 另含：诊断日志开关（默认关零写文件/开启有 dump/环境变量接线）+ router 缩放消费段
## （未激活面板回退主视图——红测实证旧语义 _active_panel==null 时 zoom_step 静默）。
## user:// 纪律：router 级段备份还原真实档（独立前缀 _x5sr_）；诊断日志文件起删终删（日志
## 非存档，删除前关句柄）。

const FIXTURE := "res://gesture_runtime/fixtures/x5_hands_replay.json"
const DT := 1.0 / 30.0
const DEBUG_LOG := "user://gesture_debug.log"
const SCENE_PATH := "res://scenes/level/level_scene.tscn"

# ===== 清档纪律（test_x_gesture_remap 同款，独立前缀 x5sr）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_x5sr_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _pre_save_text: String = ""

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

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
		if FileAccess.file_exists(_disc_abs(p)):
			DirAccess.remove_absolute(_disc_abs(p))
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(_disc_abs(bk)):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(_disc_abs(bk))
	var real_sm: Node = root.get_node_or_null("SaveManager")
	if real_sm != null:
		real_sm.load_game()
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")

# ===== 夹具与 map 级回放 =====
var _fx: Dictionary = {}

func _load_fixture() -> bool:
	if not FileAccess.file_exists(FIXTURE):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("cases"):
		return false
	_fx = parsed
	return true

func _replay_case(case_name: String, tail: int = 0) -> Array:
	## map 级回放：逐帧 feed_frame（now=帧号×DT 注入），返回意图数组（原样）。
	## tail>0：回放结束后续接 tail 帧「静默帧」（复用末帧手 dict、now 继续按 DT 递进）——
	## 批次 AA W3-2 等价改写基建：夹具不足 dwell 1.0s 窗的清空用例在测试侧延长序列，夹具 JSON 不动。
	var m: Variant = load("res://scripts/gesture_map.gd").new()
	# 批次 AC 4A（spec §4.6-3）：生产语义改**双手协同推拉/间距缩放**，单手掌推拉通道默认关。
	# 本回放层的单手掌推拉用例（A/A2/A3）经兼容开关开启历史通道后照跑（等价改写留痕：夹具
	# JSON 与时序零变化，仅加一行开关）；双手协同缩放**新**语义断言见 test_ac_batch4_gesture 段 1。
	m.call("set_single_hand_zoom_enabled", true)
	var intents: Array = []
	var frames: Array = (_fx["cases"] as Dictionary).get(case_name, [])
	for i: int in frames.size():
		var fr: Dictionary = frames[i]
		intents.append_array(m.feed_frame(fr.get("left"), fr.get("right"), i * DT))
	if tail > 0 and frames.size() > 0:
		var last: Dictionary = frames[frames.size() - 1]
		for j: int in tail:
			intents.append_array(m.feed_frame(last.get("left"), last.get("right"),
				(frames.size() + j) * DT))
	return intents

func _types(intents: Array) -> Array:
	var out: Array = []
	for it: Variant in intents:
		if typeof(it) == TYPE_DICTIONARY:
			out.append(String((it as Dictionary).get("type", "")))
	return out

func _has(intents: Array, t: String) -> bool:
	return _types(intents).has(t)

func _steps_of(intents: Array) -> Array:
	var out: Array = []
	for it: Variant in intents:
		if typeof(it) == TYPE_DICTIONARY and String((it as Dictionary).get("type", "")) == "zoom_step":
			out.append(int((it as Dictionary).get("dir", 0)))
	return out

func _sides_of(intents: Array, t: String) -> Array:
	var out: Array = []
	for it: Variant in intents:
		if typeof(it) == TYPE_DICTIONARY and String((it as Dictionary).get("type", "")) == t:
			out.append(String((it as Dictionary).get("side", "")))
	return out

## C2②合成帧构造（批次X收口 P2-1 裁决）：以夹具末帧为底，landmarks 换成确定拓扑按 face 翻面
## （cz 符号由 face 定；test_gesture_map._hand Right/facing 同款布点），fingers 恒掌形
## [0.1,1,1,1,1]（cls=palm；semantic="four" 持有不重发 clear），roll/confidence 等继承夹具。
func _c2_refaced(base: Dictionary, face: bool) -> Dictionary:
	var h: Dictionary = base.duplicate(true)
	var lm: Array = []
	for k: int in 21:
		lm.append([0.5, 0.5, 0.0])
	lm[0] = [0.5, 0.82, 0.0]
	if face:
		lm[5] = [0.45, 0.62, 0.0]    # cz=+0.0195：右掌面朝镜
		lm[17] = [0.55, 0.63, 0.0]
	else:
		lm[5] = [0.55, 0.62, 0.0]    # cz=−0.0195：右掌翻背
		lm[17] = [0.45, 0.63, 0.0]
	h["landmarks"] = lm
	h["fingers"] = [0.1, 1.0, 1.0, 1.0, 1.0]
	return h

func _del_debug_log() -> void:
	if FileAccess.file_exists(DEBUG_LOG):
		DirAccess.remove_absolute(_disc_abs(DEBUG_LOG))

# ===== router 级段（真 level_scene 消费）=====
class SpyLayer:
	extends "res://scripts/gesture_cursor_layer.gd"
	func _init() -> void:
		pass

var router: Variant

func _initialize() -> void:
	print("== test_x_semantic_replay ==")
	_del_debug_log()
	check(_load_fixture(), "前置：回放夹具在案且可解析（x5_hands_replay.json）")
	if _fx.is_empty():
		# 夹具缺失不中止（探针件可再生），本件剩余断言按失败呈现
		finish()
		return
	var cases: Dictionary = _fx["cases"]

	# ================= 段 1. map 级逐手势回放（A/A2/A3/B/C/C2/D/D2/E/F） =================
	# A 快推（真手 0.4s 内推 20%）
	var ia: Array = _replay_case("A_palm_push_fast")
	check(_has(ia, "palm_begin"), "A：左手掌形序列 → palm_begin（掌态候选过双帧+conf 门）")
	check(_has(ia, "zoom_begin"), "A：快推 20% → zoom_begin（推拉 15%×3 帧在观察窗内达成）")
	check(_has(ia, "zoom_step") and _steps_of(ia).has(1),
		"A：推近 → zoom_step dir=+1（palm_size EMA 越过 ln(1.10) 台阶）")
	# A2 慢启动（掌稳 0.67s 超旧 0.5s 观察窗后再推 25%）
	var ia2: Array = _replay_case("A2_palm_push_late")
	check(_has(ia2, "zoom_begin"),
		"A2：慢启动推拉 → zoom_begin（X5 修复：观察窗过期基准重置——旧语义下永不触发，探针实证缩放失效根因之一）")
	# A3 右手掌推拉（批次 AA W3-1 等价改写：旧「右手 palm=清空、无缩放」语义随 §6.3 W3-1 退役——
	# 现左右掌同链，右掌推拉 → zoom_begin 且零 clear；夹具 JSON 不动，仅断言随终态语义翻转）
	var ia3: Array = _replay_case("A3_right_palm_push")
	check(_has(ia3, "palm_begin"), "A3：右掌形序列 → palm_begin（W3-1 左右同链，非清空专用分支）")
	check(_has(ia3, "zoom_begin"),
		"A3：右手掌推拉 → zoom_begin（W3-1 红→绿：修复前右手 palm=清空语义 → 零 zoom_begin 判红）")
	check(not _has(ia3, "clear"), "A3：右掌推拉零 clear（W3-1 取消「右手 palm→清空」破坏性映射）")
	# B 右手竖四指 + 静止续帧 → 零 clear（批次 AA W3-2 旧口径：静止 dwell 1.0s → clear；
	# 批次 AD §4.3.4 等价改写：右掌 dwell 清空通路**彻底废除**，清空改双手握拳接管——真手右四指
	# 静止续帧满窗不再产生任何 clear。旧值留痕：`check(_has(ib, "clear"), "B：…静止续帧满 1.0s →
	# clear（W3-2 dwell 新通路回放证实…）")`。断言条数 2→2 不减：反置为「零 clear」+ 保留
	# palm_begin 在案（四指掌态分类链本身未变，仅其 dwell 消费端退役）。
	var ib: Array = _replay_case("B_four_clear_right", 40)
	check(not _has(ib, "clear"),
		"B→AD §4.3.4：右手竖四指真手序列 + 静止续帧 → 零 clear（右掌 dwell 清空彻底废除留痕；双手握拳清空见 test_ad_batch3_interaction 段 A）")
	check(_has(ib, "palm_begin"), "B 前置：右四指 → palm_begin（四指掌态分类链不变；旧 dwell 起算锚随 §4.3.4 消费端退役）")
	# C/C2 翻转撤销/重做
	# 批次 Y（Y-A9）平移留痕：单翻 undo 解算窗 0.5→0.8s；批次 Z（Z5）再平移 0.8→1.2s——
	# 夹具 JSON 不动，回放后在序列尾合成「在场静默帧」推进窗闭合（teardown 会清 pending，故喂
	# 在场 cursor 手而非空帧）；合成帧时点 +0.90/+0.933 → +1.40/+1.433（保证 Δ>1.2s）。
	var m_c: Variant = load("res://scripts/gesture_map.gd").new()
	var frames_c: Array = cases.get("C_flip_undo_left", [])
	var ic: Array = []
	var c_len: int = frames_c.size()
	for i_c: int in c_len:
		var fr_c: Dictionary = frames_c[i_c]
		ic.append_array(m_c.feed_frame(fr_c.get("left"), fr_c.get("right"), i_c * DT))
	var c_close := func(h: Dictionary, t: float) -> Array:
		return m_c.feed_frame(h, null, t)
	var c_neutral := {"confidence": 0.9, "fingers": [0.1, 0.9, 0.1, 0.1, 0.1],
		"handedness": "Left", "is_detected": true, "timestamp": 0.0}
	ic.append_array(c_close.call(c_neutral, c_len * DT + 1.40))
	ic.append_array(c_close.call(c_neutral, c_len * DT + 1.433))
	check(_has(ic, "undo"), "C：左手竖掌左右翻真手序列 → undo（X5 修复：翻转前置去 roll<30° 绝对门——竖掌 roll≈270° 下旧前置永不锁定，撤销真手 100%% 失效根因；Z5 1.2s 窗闭合帧由序列尾合成帧承接）")
	# C2（批次X收口 P2-1 裁决改写：spec §12 方案①+主会话批准本件文件域例外）——本序列与「清空提交后
	# 窗内翻腕误触发 redo」BUG 场景帧结构完全同构（f7 清空提交 t=0.233 与 f19-20 掌面翻背 t=0.667
	# 仅隔 0.434s<1.0s 冷却窗），P2-1 修复目的即令该序列不再 redo——旧断言「C2 → redo」锁修复前语义，
	# 已过时。夹具 JSON 不动（原始真手序列存档价值保留，语义解释归本测试层）：①窗内抑制锁新语义；
	# ②测试内合成掌面帧推进冷却过期重锁再翻，redo 仍可达（X5「翻转前置去 roll<30° 绝对门」修复验证
	# 价值保留；红绿证据链见 test_gesture_map 段 5b，本条为回放层对账+防过修护栏）。
	var m_c2: Variant = load("res://scripts/gesture_map.gd").new()
	var ic2: Array = []
	var frames_c2: Array = cases.get("C2_flip_redo_right", [])
	var c2_ok: bool = not frames_c2.is_empty() \
		and typeof(frames_c2[frames_c2.size() - 1]) == TYPE_DICTIONARY \
		and typeof((frames_c2[frames_c2.size() - 1] as Dictionary).get("right")) == TYPE_DICTIONARY
	check(c2_ok, "C2 前置：夹具 case C2_flip_redo_right 末帧右手在案")
	if c2_ok:
		for i_c2: int in frames_c2.size():
			var fr_c2: Dictionary = frames_c2[i_c2]
			ic2.append_array(m_c2.feed_frame(fr_c2.get("left"), fr_c2.get("right"), i_c2 * DT))
		check(not _has(ic2, "redo"),
			"C2①：清空提交（f7 t=0.233）后掌面翻背序列 → redo 零派发（Y-A8 独立防误窗 0.35s+Z5 1.2s 窗下，误翻触发后的解算点越出序列尾；防误窗内抑制+窗外 undo/redo 正常可达由 test_y_flip_decoder 段 3 锁定）")
		# ②合成帧：以夹具末帧（t=1.3667，防误窗 0.35s 已过）为底构造掌形帧续时间轴——掌面朝镜重锁 2 帧
		#（roll0=夹具 roll 271.3）→ 掌面翻背 2 帧（flipped 条件触发）→ Z5 1.2s 同窗闭合
		#（触发 t=c2_t+0.3，闭合帧取 +1.60 → 1.30s>1.2s；旧 +1.25→0.95s>0.8s 平移留痕）解算 redo
		var c2_last: Dictionary = frames_c2[frames_c2.size() - 1] as Dictionary
		var c2_right: Dictionary = c2_last.get("right") as Dictionary   # 手 dict（非整帧；_valid 需 is_detected）
		var c2_t: float = float(frames_c2.size()) * DT
		ic2.append_array(m_c2.feed_frame(null, _c2_refaced(c2_right, true), c2_t + 0.2))    # 前置重累计 1
		ic2.append_array(m_c2.feed_frame(null, _c2_refaced(c2_right, true), c2_t + 0.2333)) # 前置重锁
		ic2.append_array(m_c2.feed_frame(null, _c2_refaced(c2_right, false), c2_t + 0.2667))# 掌面翻背 1
		ic2.append_array(m_c2.feed_frame(null, _c2_refaced(c2_right, false), c2_t + 0.3))   # 翻背 2 → 触发
		ic2.append_array(m_c2.feed_frame(null, _c2_refaced(c2_right, false), c2_t + 1.60))  # 1.30s>1.2s 闭合 → redo（Z5 平移留痕）
		check(_has(ic2, "redo"),
			"C2②：防误窗过期保持掌面前置重锁 → 掌面翻背 2 帧触发 → redo 解算仍可达（X5 翻转修复验证价值保留；Y-A8/Z5 平移留痕）")
	# D 左手二指选中（新左键笔模型通过率证实）
	var id1: Array = _replay_case("D_two_select_left")
	check(_has(id1, "two_down") and _sides_of(id1, "two_down").has("left"),
		"D：左手食指→竖中指真手序列 → two_down(side=left)（双帧窗对真手序列通过，新模型门槛低证实）")
	# D2 无名指跟伸变体（three 误入=delete 误触风险，量化记录型断言——现状行为锁定）
	var id2: Array = _replay_case("D2_two_ring_leak_left")
	check(_has(id2, "delete"),
		"D2：左手二指+无名指跟伸（引擎输出无名指伸直度 0.23→1.00：过渡帧→保持帧）→ 判 three → delete 意图（真手风险量化记录：竖中指无名跟伸会误触删除——文案/复验注意项，不改阈值）")
	# E 右手 Ctrl 减选笔
	var ie: Array = _replay_case("E_two_deselect_right")
	check(_has(ie, "two_down") and _sides_of(ie, "two_down").has("right"),
		"E：右手竖中指真手序列 → two_down(side=right)（Ctrl 减选笔通过率证实）")
	# F 左三指删除
	var iff: Array = _replay_case("F_three_delete_left")
	check(_has(iff, "delete"), "F：左手竖三指真手序列 → delete（左三指删除回放证实）")

	# ================= 段 2. 诊断日志开关（默认关零写文件 / 开启有 dump） =================
	check(_del_ok(), "段 2 前置：诊断日志文件已清（沙盒起删）")
	var m0: Variant = load("res://scripts/gesture_map.gd").new()
	var frames0: Array = cases.get("B_four_clear_right", [])
	for i2: int in mini(5, frames0.size()):
		var fr0: Dictionary = frames0[i2]
		m0.feed_frame(fr0.get("left"), fr0.get("right"), i2 * DT)
	check(not FileAccess.file_exists(DEBUG_LOG),
		"诊断开关默认关：5 帧回放零写文件（user://gesture_debug.log 不存在）")
	check(m0.has_method("set_debug_enabled") and m0.has_method("is_debug_enabled"),
		"诊断开关 API 在场（set_debug_enabled/is_debug_enabled）")
	var dbg_ok := true
	if m0.has_method("set_debug_enabled"):
		m0.set_debug_enabled(true)
		check(m0.is_debug_enabled(), "诊断开关显式开启 → is_debug_enabled=true")
		for i3: int in mini(6, frames0.size()):
			var fr1: Dictionary = frames0[i3]
			m0.feed_frame(fr1.get("left"), fr1.get("right"), i3 * DT)
		dbg_ok = FileAccess.file_exists(DEBUG_LOG)
		if dbg_ok:
			var lines: PackedStringArray = FileAccess.get_file_as_string(DEBUG_LOG).split("\n")
			var line_cnt: int = 0
			for ln: String in lines:
				if not ln.strip_edges().is_empty():
					line_cnt += 1
			dbg_ok = line_cnt >= 6
			check(line_cnt >= 6, "诊断开关开启后逐帧 dump 在案（≥6 行非空，含会话头+5 帧；实际 %d 行）" % line_cnt)
			var dump_src: String = FileAccess.get_file_as_string(DEBUG_LOG)
			check(dump_src.contains("semantic=") and dump_src.contains("conf=") and dump_src.contains("intents="),
				"诊断 dump 含 semantic/confidence/intents 关键域")
		m0.set_debug_enabled(false)
		check(not m0.is_debug_enabled(), "诊断开关显式关闭 → is_debug_enabled=false（句柄释放）")
	check(dbg_ok, "诊断开关开启后有 dump（文件存在且行数达标）")
	_del_debug_log()

	# ================= 段 3. router 级消费（真 level_scene；备份还原真实档） =================
	_backup_user()
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(_disc_abs(p)):
			DirAccess.remove_absolute(_disc_abs(p))
	get_root().get_node("SaveManager").call("load_game")
	var bridge: Node = get_root().get_node("GestureBridge")
	var game: Node = get_root().get_node("Game")
	bridge._set_state(1)
	router = load("res://autoload/gesture_router.gd").new()
	add_child(router)
	await process_frame
	bridge._set_state(1)
	router._setup()
	var spy: SpyLayer = SpyLayer.new()
	add_child(spy)
	await process_frame
	router.set_cursor_layer(spy)
	var inst: Node = (load(SCENE_PATH) as PackedScene).instantiate()
	check(inst != null, "前置：关卡场景可实例化")
	inst.call("set_context", {"chapter": 1})
	add_child(inst)
	game._current_scene = inst
	await process_frame
	await process_frame
	game.goto_state(game.State.LEVEL)
	await process_frame
	await process_frame
	await process_frame
	var cont: SubViewportContainer = inst.get_node_or_null("MainView/ViewportContainer") as SubViewportContainer
	var cam: Camera3D = inst.get_node_or_null("MainView/ViewportContainer/SubViewport/Camera3D") as Camera3D
	check(cont != null and cam != null, "前置：主视容器/相机在位")
	# ortho 缩放守卫前置确认（level_scene._main_diameter 初始化晚于 goto_state 一帧——时序探明留痕）
	check(float(inst.get("_main_diameter")) > 0.0 and float(inst.get("_ortho_size_main")) > 0.0,
		"前置：主视 ortho 缩放量纲已初始化（_main_diameter/_ortho_size_main>0）")
	var ortho0: float = cam.size
	# 批次 AC 4B（§4.6-1）等价改写：旧 X5「未激活面板（_active_panel==null）直接掌推拉 → 回退
	# 主视图」随用户拍板退役——现契约=**缩放严格受限绑定视口，未绑定一律忽略**（显式绑定取代
	# 回退；X5 回退链是「掌推拉 100% 失效」补丁，AC 4B 以视口隔离根治）。断言集零缩减：
	# ①未绑定 → 零变化（旧红点反向锚）；②绑定主视图后 → ortho 缩放生效（原「激活面板后消费」锚）。
	router.call("_dispatch", {"type": "zoom_step", "side": "left", "dir": -1})
	await process_frame
	var ortho_out: float = cam.size
	router.call("_dispatch", {"type": "zoom_step", "side": "left", "dir": 1})
	await process_frame
	var ortho_in: float = cam.size
	check(ortho_out == ortho0 and ortho_in == ortho_out,
		"router 批次 AC 4B §4.6-1：未绑定视口（_active_panel==null）zoom_step → 主视图 ortho 零变化（视口隔离；%.3f→%.3f→%.3f）" % [ortho0, ortho_out, ortho_in])
	# 对照：绑定主视图后 zoom_step 消费（视口内缩放可达，原语义防回归）
	router.call("_set_active_panel", cont)
	var ortho2: float = cam.size
	router.call("_dispatch", {"type": "zoom_step", "side": "left", "dir": -1})
	await process_frame
	check(cam.size > ortho2, "router：绑定视口后 zoom_step 走该视口矩形夹取消费（AC 4B 视口隔离）")
	# 全链段：fixture A 帧经 router._map（feed 同一实例）+ 逐意图 _dispatch → 主视 ortho 缩放
	var m2: Variant = router.get("_map")
	check(m2 != null, "前置：router._map 在案")
	# 批次 AC 4A（spec §4.6-3）：全链段用 fixture A（单手快推）验证 zoom_step → dispatch 消费链；
	# 单手通道默认关 → 经兼容开关开启后本段照跑（等价改写留痕：夹具与断言零变化，仅加一行开关）。
	m2.call("set_single_hand_zoom_enabled", true)
	m2.reset()
	var ortho3: float = cam.size
	var frames_a: Array = cases.get("A_palm_push_fast", [])
	for i4: int in frames_a.size():
		var fr2: Dictionary = frames_a[i4]
		var intents2: Array = m2.feed_frame(fr2.get("left"), fr2.get("right"), i4 * DT)
		for it2: Variant in intents2:
			router.call("_dispatch", it2)
	await process_frame
	check(cam.size < ortho3,
		"router 全链：fixture A 快推序列 → map 意图 → dispatch → **绑定视口** ortho 缩放（掌推拉端到端；%.3f→%.3f；AC 4B 起须先绑定视口）" % [ortho3, cam.size])
	router.call("_set_active_panel", null)   # 收尾：解绑（AC 4B 视口隔离语义）
	# 环境变量接线：GAME_GESTURE_DEBUG=1 → _setup 接线开启
	var dbg_path0: bool = FileAccess.file_exists(DEBUG_LOG)
	var router2: Variant = load("res://autoload/gesture_router.gd").new()
	OS.set_environment("GAME_GESTURE_DEBUG", "1")
	add_child(router2)
	router2._setup()
	check(router2.get("_map") != null and router2.get("_map").is_debug_enabled(),
		"诊断开关环境变量接线：GAME_GESTURE_DEBUG=1 → router._setup 开启 map dump（默认不开零写文件）")
	OS.set_environment("GAME_GESTURE_DEBUG", "")
	# 会话级隔离真命题（审查回修 P1-1：原「or true」恒真空转假绿废弃）：接线段（dbg_path0=false
	# 前置已清档）产生日志文件=开启即落盘（会话头）；router2 显式关闭句柄+沙盒清理后文件不存在。
	check(dbg_path0 == false and FileAccess.file_exists(DEBUG_LOG),
		"诊断日志接线段隔离：接线前无文件且 GAME_GESTURE_DEBUG=1 期间文件已建立（开启即落盘）")
	router2.get("_map").set_debug_enabled(false)
	check(not router2.get("_map").is_debug_enabled(), "诊断开关接线段显式关闭 → is_debug_enabled=false（句柄释放）")
	router2.queue_free()
	_del_debug_log()
	check(not FileAccess.file_exists(DEBUG_LOG),
		"诊断日志会话级隔离：接线段日志经关闭+清理后不存在（沙盒终态干净）")

	# 收尾卫生：断开桥 feed 连接（防 freed 回调）
	if bridge != null and bridge.gesture_state_received.is_connected(router.feed):
		bridge.gesture_state_received.disconnect(router.feed)
	router.queue_free()
	spy.queue_free()
	_restore_user()
	finish()

func _del_ok() -> bool:
	_del_debug_log()
	return not FileAccess.file_exists(DEBUG_LOG)
