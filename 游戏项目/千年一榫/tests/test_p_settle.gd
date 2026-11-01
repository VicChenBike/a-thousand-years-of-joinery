extends "res://tests/test_base.gd"
## 批次 P 波 2（P-C 散开放慢+滞空 / P-D 结算架构重做）判定用例（TDD 红灯先行，2026-09-10）。
## 契约（用户口径 2026-09-10 批次 P 波 2）：
##   P-C 发散放慢+滞空：聚焦与成功动画散开段同口径放慢——focus_fx SPREAD_TIME 0.9→1.2、
##     level ANIM_SPREAD 0.5→1.2；缓动改滞空感=前段缓出（幂 2.6 ease-out）+阻尼正弦悬浮
##     （sin(πx)·(1−x)，起止零/中段峰/后段衰减）；四段总时长重排 0.25+0.5+1.2+1.1+0.9=3.95
##     ∈[2.5,4]（spec 8.4 红线保持）；ANIM_ALIGN 对位窗口随「不回正」废止。
##   P-D 结算架构重做（方案 A：结算 UI 合并进 level 覆盖层，settle 场景退役不再路由）：
##     ①主路径零重建零回正零切换：_goto_settle 不再 goto_state(SETTLE)——评级/发奖/
##       advance_progress(恰一次)/清断点保留，结算 UI 在 SuccessOverlay 内从下往上淡入渐显；
##     ②结算 UI 节点面：SuccessOverlay/SettleUI/{SettleDim,GradeLabel,ElapsedLabel,TalentLabel,
##       NextButton,ExitButton,ModelDragArea}（退出按钮为新增）；淡入参数
##       （时长 0.7s/起始 y 偏移 40px/级联 0.1s，深浅主题双档）；
##     ③下一关三分流语义从 settle_scene 迁入 level（replay→CATALOG/无下关→MAIN_MENU/
##       有下关→TALK after_level）；④退出按钮 → MAIN_MENU；
##     ⑤advance_progress 全流程恰一次守护（重复 _goto_settle/skip 不重复发奖推进）；
##     ⑥SETTLE 态特判：goto_state(SETTLE) → game.gd 改载 level 场景注入 settle:true
##       （边缘路径：重建关卡体素+直显结算 UI 与建模，不再路由 settle_scene）；
##       mark_settle_entered 主路径记账（O5 catalog_return/图鉴 SETTLE 透传兼容）；
##     ⑦skip 钩子=直达结算 UI（跳过动画不跳过结算）；settle_scene.tscn 保留不删但不再被路由。
## 坑纪律：无头 MultiMesh 读回恒 0 → 属性/标签/状态证据链；--script 模式 autoload 在
##   /root/<Name>（P2-5 动态引用）；起测前备份 user:// 档案、终测还原（P波1/N10/O 同规）。

const FX_SCRIPT := "res://scripts/focus_fx.gd"
const LS_SCRIPT := "res://scenes/level/level_scene.gd"
const GAME_SCRIPT := "res://autoload/game.gd"
const CATALOG_GD := "res://scenes/catalog/catalog_scene.gd"
const SETTLE_GD := "res://scenes/settle/settle_scene.gd"
const SETTLE_SCENE := "res://scenes/settle/settle_scene.tscn"
const LEVEL_SCENE := "res://scenes/level/level_scene.tscn"
const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const BK_SAVE := "user://_p2_backup_save.json"
const BK_FLAG := "user://_p2_backup_flag.flag"

const ST_MAIN_MENU := 1
const ST_TALK := 3
const ST_LEVEL := 4
const ST_SETTLE := 5
const ST_CATALOG := 6
const ST_FINALE := 7  # 批次 AD-4（spec §4.4.1）：通关第 5 关「下一关」改道终局「未完待续」态

var game: Variant
var save: Variant
var lib: Variant

func _backup_user() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(BK_SAVE))
	if FileAccess.file_exists(FLAG_PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(FLAG_PATH), ProjectSettings.globalize_path(BK_FLAG))

func _restore_user() -> void:
	for pair: Array in [[BK_SAVE, SAVE_PATH], [BK_FLAG, FLAG_PATH]]:
		if FileAccess.file_exists(String(pair[0])):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(String(pair[0])), ProjectSettings.globalize_path(String(pair[1])))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(String(pair[0])))
	if save != null:
		save.load_game()

func _reset_save() -> void:
	for p: String in [SAVE_PATH, FLAG_PATH]:
		var abs: String = ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs):
			DirAccess.remove_absolute(abs)
	save.load_game()

func _target_cells() -> Array:
	var lvl: Dictionary = lib.get_level(1)
	if lvl.is_empty():
		return []
	var pieces: Array = (lvl["data"] as Dictionary)["pieces"]
	return (pieces[0] as Dictionary)["target_shapes"][0]

## 经 Game 路由造 level 场景（主路径零切换断言需 get_current_scene 同一实例证据）。
func _make_level_routed(ch: int) -> Node:
	game.goto_state(ST_LEVEL, {"chapter": ch})
	for _i: int in 3:
		await process_frame
	return game.get_current_scene()

func _initialize() -> void:
	print("== test_p_settle ==")
	Engine.max_fps = 60
	_backup_user()
	save = get_root().get_node("SaveManager")
	game = get_root().get_node("Game")
	lib = get_root().get_node("LevelLibrary")
	save.load_game()
	lib.scan_directory("res://levels_data")
	var container: Control = Control.new()
	add_child(container)
	var overlay: CanvasLayer = CanvasLayer.new()
	add_child(overlay)
	game.attach(container, overlay)

	var fx_s: Script = load(FX_SCRIPT)
	var ls_s: Script = load(LS_SCRIPT)
	var g_s: Script = load(GAME_SCRIPT)
	check(fx_s != null and ls_s != null and g_s != null, "P 前置：focus_fx/level_scene/game 可加载")
	if fx_s == null or ls_s == null or g_s == null:
		finish()
		return
	var fcmap: Dictionary = fx_s.get_script_constant_map()
	var lcmap: Dictionary = ls_s.get_script_constant_map()
	var gcmap: Dictionary = g_s.get_script_constant_map()

	# ==================== A. P-C 散开放慢+滞空（常量 + 缓动纯函数 + shader 证据） ====================
	print("-- A P-C 散开放慢+滞空 --")
	check_eq(float(fcmap.get("SPREAD_TIME", -1.0)), 1.2,
		"P-C：SPREAD_TIME=1.2（聚焦散开放慢同口径；N3 0.9 档 P批等价替换废止留痕）")
	check_eq(float(fcmap.get("SPREAD_EASE_POW", -1.0)), 2.6,
		"P-C：SPREAD_EASE_POW=2.6（前段缓出幂；原 2.0 直落出屏档废止）")
	check(float(fcmap.get("SPREAD_HOVER_AMP", -1.0)) > 0.0,
		"P-C：SPREAD_HOVER_AMP>0（阻尼正弦悬浮幅度档存在）")
	check_eq(float(fx_s.call("spread_ease", 0.0)), 0.0, "P-C：spread_ease(0)==0（缓动起点）")
	check(absf(float(fx_s.call("spread_ease", 1.0)) - 1.0) < 0.0001,
		"P-C：spread_ease(1)==1（缓动终点=散开末帧全距，接力采样不变）")
	var e25: float = float(fx_s.call("spread_ease", 0.25))
	var e50: float = float(fx_s.call("spread_ease", 0.5))
	var e75: float = float(fx_s.call("spread_ease", 0.75))
	check(e25 > 0.5 and e25 < e50 and e50 < e75,
		"P-C：缓动单调且前段快（ease(0.25)=%.3f>0.5——前段缓出，非匀速滑出）" % e25)
	check(e75 > 0.95,
		"P-C：ease(0.75)=%.3f>0.95（后段低速低漂移——滞空感，'刷一下'根因消除）" % e75)
	var h0: float = float(fx_s.call("spread_hover", 0.0))
	var h1: float = float(fx_s.call("spread_hover", 1.0))
	var h4: float = float(fx_s.call("spread_hover", 0.4))
	var h9: float = float(fx_s.call("spread_hover", 0.9))
	check(absf(h0) < 0.0001 and absf(h1) < 0.0001,
		"P-C：spread_hover 起止为零（sin(πx)——不污染散开起点/末帧接力位）")
	check(h4 > 0.3 and h4 > h9, "P-C：spread_hover 中段峰+后段阻尼衰减（h(0.4)=%.3f>h(0.9)=%.3f）" % [h4, h9])
	var shader_src: String = String(fcmap.get("SHADER_CODE", ""))
	check(shader_src.contains("u_hover") and shader_src.contains("2.6"),
		"P-C：shader 注入 u_hover 悬浮项+缓动幂 2.6（GPU 同曲线证据链）")
	check_eq(float(lcmap.get("ANIM_SPREAD", -1.0)), 1.2,
		"P-C：ANIM_SPREAD=1.2（成功动画散开放慢；O批 0.5 档 P批等价替换废止留痕）")
	check_eq(float(lcmap.get("ANIM_AGGREGATE", -1.0)), 1.1,
		"P-C：ANIM_AGGREGATE=1.1（总时长重排平衡；O批 1.3 废止留痕）")
	check_eq(float(lcmap.get("ANIM_REVIEW", -1.0)), 0.9,
		"P-C：ANIM_REVIEW=0.9（总时长重排平衡；O批 1.0 废止留痕）")
	var seg_sum: float = float(lcmap.get("ANIM_CONDENSE", -1.0)) + float(lcmap.get("ANIM_HOLD", -1.0)) \
		+ float(lcmap.get("ANIM_SPREAD", -1.0)) + float(lcmap.get("ANIM_AGGREGATE", -1.0)) \
		+ float(lcmap.get("ANIM_REVIEW", -1.0))
	check(seg_sum >= 2.5 and seg_sum <= 4.0,
		"P-C：四段总时长 %.2f=0.25+0.5+1.2+1.1+0.9 ∈[2.5,4]（spec 8.4 红线保持）" % seg_sum)
	check(lcmap.get("ANIM_ALIGN", null) == null,
		"P-C：ANIM_ALIGN 对位窗口常量已废止（回看段全程自转，建模以玩家姿态直入结算不回正）")

	# ==================== B. 结算 UI 节点面 + skip 直达结算 ====================
	print("-- B 结算 UI 节点面 + skip 直达 --")
	_reset_save()
	var inst: Node = await _make_level_routed(1)
	var target: Array = _target_cells()
	check(not target.is_empty() and inst != null, "P 前置：第 1 关经 Game 路由就绪")
	if inst != null and not target.is_empty():
		var jb: Button = inst.get_node_or_null("TopBar/Buttons/JoinButton")
		inst.set("anim_time_scale", 8.0)
		inst.call("set_remaining_for_test", target)
		jb.pressed.emit()
		inst.call("_skip_success_animation")  # P-D⑦：skip=直达结算 UI（跳过动画不跳过结算）
		await process_frame
		check_eq(int(game.current_state()), ST_SETTLE,
			"P-D⑦：skip 钩子直达结算（mark_settle_entered 记账 SETTLE 态）")
		var ui: Control = inst.get_node_or_null("SuccessOverlay/SettleUI")
		check(ui is Control and ui.visible, "P-D①：结算 UI=SuccessOverlay/SettleUI（覆盖层承载，skip 后可见）")
		check(ui != null and ui.get_node_or_null("SettleDim") is ColorRect,
			"P-D②：SettleDim 压暗层存在（对齐退役 settle Dim 口径）")
		var grade_l: Label = ui.get_node_or_null("GradeLabel") if ui != null else null
		var elapsed_l: Label = ui.get_node_or_null("ElapsedLabel") if ui != null else null
		var talent_l: Label = ui.get_node_or_null("TalentLabel") if ui != null else null
		var next_b: Button = ui.get_node_or_null("NextButton") if ui != null else null
		var exit_b: Button = ui.get_node_or_null("ExitButton") if ui != null else null
		var drag_a: Control = ui.get_node_or_null("ModelDragArea") if ui != null else null
		check(grade_l is Label and String(grade_l.text).contains("评分："),
			"P-D②：评级 Label 就位（就地取 grade_for_time）")
		check(elapsed_l is Label and String(elapsed_l.text).contains("耗时："),
			"P-D②：耗时 Label 就位（就地取 _final_elapsed）")
		check(talent_l is Label and String(talent_l.text).contains("获得天赋值：100"),
			"P-D②：获得天赋值 Label=100（第 1 关首通完美档）")
		check(next_b is Button and String(next_b.text) == "下一关",
			"P-D②：「下一关」按钮就位（三分流迁入 level）")
		check(exit_b is Button and String(exit_b.text) == "退出",
			"P-D②：「退出」按钮就位（新增，退役 settle_scene 无此钮）")
		check(drag_a is Control and int(drag_a.mouse_filter) == int(Control.MOUSE_FILTER_STOP),
			"P-D①：ModelDragArea 建模拖拽区就位（结算页继续可拖拽旋转）")
		check(ui != null and int(ui.mouse_filter) == int(Control.MOUSE_FILTER_IGNORE),
			"P-D②：SettleUI 根 mouse_filter=IGNORE（不挡全局输入）")
		check(ui != null and ui.theme != null,
			"P-D②：SettleUI 显式赋主题（坑 11：CanvasLayer 主题不传播）")
		var cloud: Node = inst.get_node_or_null(
			"SuccessOverlay/AnimContainer/AnimViewport/AnimWorld/SpinPivot/SuccessCloud")
		check(cloud is MultiMeshInstance3D and (cloud as MultiMeshInstance3D).visible,
			"P-D①：建模成形直显（SuccessCloud visible=零重建）")
		# ---- C. 淡入演出参数与「从水里升起」位移证据 ----
		var fade_t: float = float(lcmap.get("SETTLE_UI_FADE_TIME", -1.0))
		var rise: float = float(lcmap.get("SETTLE_UI_RISE_OFFSET", -1.0))
		var stag: float = float(lcmap.get("SETTLE_UI_STAGGER", -1.0))
		check(fade_t >= 0.6 and fade_t <= 0.8 and absf(rise - 40.0) < 0.001 and absf(stag - 0.1) < 0.001,
			"P-D②：淡入参数档 时长%.1fs∈[0.6,0.8]/y偏移%.0fpx/级联%.1fs（用户口径 0.6~0.8s+40px）"
				% [fade_t, rise, stag])
		if grade_l != null:
			var a0: float = grade_l.modulate.a
			var y0: float = grade_l.position.y
			await create_timer(1.3).timeout
			check(a0 < 0.1, "P-D②：淡入起点近全透（同帧 a=%.3f<0.1，渐显非硬切）" % a0)
			check(absf(grade_l.modulate.a - 1.0) < 0.02,
				"P-D②：淡入完成 alpha→1（%.3f）" % grade_l.modulate.a)
			check(grade_l.position.y < y0 - 10.0,
				"P-D②：从下往上升起位移证据（y %.1f→%.1f，起始偏移≈40px 渐归位）" % [y0, grade_l.position.y])
	# ==================== D. 主路径零重建零回正零切换 + advance 恰一次守护 ====================
	print("-- D 主路径零切换 + advance 恰一次 --")
	_reset_save()
	var talent0: int = int(save.get_talent())
	var lvl2: Node = await _make_level_routed(1)
	if lvl2 != null and not target.is_empty():
		var jb2: Button = lvl2.get_node_or_null("TopBar/Buttons/JoinButton")
		lvl2.set("anim_time_scale", 8.0)
		lvl2.call("set_remaining_for_test", target)
		jb2.pressed.emit()
		await create_timer(0.3).timeout  # 聚合段中（seg12/8≈0.244 后、聚合完 0.381 前）
		var ui2: Control = lvl2.get_node_or_null("SuccessOverlay/SettleUI")
		check(ui2 != null and not ui2.visible,
			"P-D②：动画期间结算 UI 未显（聚合/回看段先演出，UI 后淡入）")
		check_eq(int(game.current_state()), ST_LEVEL,
			"P-D①：主路径动画期间状态保持 LEVEL（不再提前切 SETTLE 场景）")
		await create_timer(0.45).timeout  # 累计 0.75 > 3.95/8≈0.494 自然完成
		check_eq(int(game.current_state()), ST_SETTLE, "P-D①：四段动画自然完成 → 记账 SETTLE")
		check(game.get_current_scene() == lvl2,
			"P-D①：主路径零切换硬证据（get_current_scene 仍为同一 level 实例，无场景重建）")
		check(game.get_current_scene() != null and (game.get_current_scene() as Node).get_node_or_null(
			"SuccessOverlay/SettleUI") != null and (game.get_current_scene() as Node).get_node_or_null("SuccessOverlay/SettleUI").visible,
			"P-D①：自然完成后结算 UI 在原 level 覆盖层内显现（按钮字从下往上淡入）")
		check_eq(int(save.get_talent()), talent0 + 100,
			"P-D⑤：天赋值恰发放一次（首通 +100，评级口径零改动）")
		check((save.get_progress()["cleared"] as Array).has(1),
			"P-D⑤：advance_progress 恰推进一次（cleared 含第 1 关）")
		lvl2.call("_goto_settle")  # 重复记账尝试（守卫）
		lvl2.call("_skip_success_animation")
		check_eq(int(save.get_talent()), talent0 + 100,
			"P-D⑤：重复 _goto_settle/skip 不再发奖（_settled 守卫=恰一次红线）")
		check_eq((save.call("get_level_progress", 1) as Array), [],
			"P-D⑤：通关清断点保留（N9 链路零改动）")
	# ==================== E. 下一关三分流（纯函数 + 行为；goto_state 会释放旧场景——
	# 每个分流变体各用一具新 level 实例）====================
	print("-- E 三分流路由 --")
	check_eq(String(ls_s.call("settle_next_route", true, true)), "catalog",
		"P-D③：settle_next_route(replay=*)→catalog（重玩结算→图鉴）")
	check_eq(String(ls_s.call("settle_next_route", false, false)), "main_menu",
		"P-D③：settle_next_route(无下关)→main_menu（批次 AD-4 后系 chapter≠5 防御分支：现网 1~5 关数据齐备，仅第 5 关无下关且已改道 FINALE）")
	check_eq(String(ls_s.call("settle_next_route", false, true)), "talk",
		"P-D③：settle_next_route(有下关)→talk（关后剧情 after_level）")
	# 批次 AD-4（spec §4.4.1）四分流补断言（纯函数面，行为面由段 E route_cases 章=5 用例承担）：
	check_eq(String(ls_s.call("settle_next_route", false, false, 5)), "finale",
		"AD-4③：settle_next_route(chapter=5)→finale（终局「未完待续」，取代旧 MAIN_MENU 终点）")
	check_eq(String(ls_s.call("settle_next_route", true, false, 5)), "catalog",
		"AD-4③：replay 优先——chapter=5∧replay 仍 →catalog（终局不截胡回看链）")
	# 批次 Y（Y-C1 数据入库）前注：levels_data 现有第 1~5 关数据，「无下关数据」行为代理
	# 由 chapter=5 实例承担（get_level(6) 恒空）；「有下关 →TALK」行为断言由 test_y5_dialog_route
	# 通关第 1 关→第 2 关对话 专测锁定（本处纯函数断言保持）。
	# 批次 AD-4（spec §4.4.1，2026-09-28 等价改写留痕）：章=5 代理用例旧期望 ST_MAIN_MENU(1)
	# ——第 5 关通关「下一关」回主菜单；新语义改道终局界面 ST_FINALE(7)，MAIN_MENU 分支退为
	# chapter≠5∧无下关数据的防御位（现网数据不可达，纯函数面上一条断言继续锁定不删）。
	var route_cases: Array = [
		[1, {"chapter": 1, "replay": true, "elapsed": 10.0, "talent": 0}, ST_CATALOG,
			"P-D③：重玩结算「下一关」→ CATALOG（语义迁移不回归）"],
		[5, {"chapter": 5, "replay": false, "elapsed": 10.0, "talent": 0}, ST_FINALE,
			"AD-4③：通关第 5 关「下一关」→ FINALE 终局（旧期望 MAIN_MENU=批次 AD-4 语义改道）"],
	]
	for case_v: Variant in route_cases:
		var case_d: Dictionary = case_v[1]
		_reset_save()
		var case_target: Array = target
		if int(case_v[0]) != 1:
			# 代理章=5：需第 5 关自身 target（挖成判定按本关数据）；空数据兜底沿用第 1 关 target
			var lvl5d: Dictionary = lib.call("get_level", int(case_v[0]))
			if not lvl5d.is_empty():
				case_target = ((lvl5d["data"] as Dictionary)["pieces"][0] as Dictionary)["target_shapes"][0]
		var lvl_r: Node = await _make_level_routed(int(case_v[0]))
		var jb_r: Button = lvl_r.get_node_or_null("TopBar/Buttons/JoinButton")
		lvl_r.set("anim_time_scale", 8.0)
		lvl_r.call("set_remaining_for_test", case_target)
		jb_r.pressed.emit()
		lvl_r.call("_skip_success_animation")
		await process_frame
		var nb_r: Button = lvl_r.get_node_or_null("SuccessOverlay/SettleUI/NextButton")
		check(nb_r is Button, "P-D③ 前置：结算「下一关」钮可达")
		if nb_r != null:
			lvl_r.set("_settle_data", case_d)
			nb_r.pressed.emit()
			await process_frame
			check_eq(int(game.current_state()), int(case_v[2]), String(case_v[3]))
	var lvl4: Node = await _make_level_routed(1)
	if lvl4 != null and not target.is_empty():
		var jb4: Button = lvl4.get_node_or_null("TopBar/Buttons/JoinButton")
		lvl4.set("anim_time_scale", 8.0)
		lvl4.call("set_remaining_for_test", target)
		jb4.pressed.emit()
		lvl4.call("_skip_success_animation")
		await process_frame
		var exit_b2: Button = lvl4.get_node_or_null("SuccessOverlay/SettleUI/ExitButton")
		if exit_b2 != null:
			exit_b2.pressed.emit()
			await process_frame
			check_eq(int(game.current_state()), ST_MAIN_MENU, "P-D④：结算「退出」→ MAIN_MENU（新增钮路由）")
	# ==================== F. SETTLE 边缘路径（game 特判重建 level 直显结算） ====================
	print("-- F SETTLE 边缘路径 --")
	var gsrc: String = FileAccess.get_file_as_string(GAME_SCRIPT)
	check(gsrc.contains("mark_settle_entered") and gsrc.contains("\"settle\""),
		"P-D⑥：game.gd 特判留痕（mark_settle_entered + ctx.settle 注入）")
	check(game.has_method("mark_settle_entered"), "P-D⑥：Game.mark_settle_entered 契约方法存在")
	# 批次 AA / W6-2（规格 §9.3 W6-4，2026-09-25）等价改写：旧用例喂**手工伪造 ctx**
	# {grade:"完美",elapsed:65,talent:100}——生产路径永远产生不出这种 ctx（goto_state(SETTLE)
	# 的调用方只带 chapter/replay），等于把断链遮蔽成绿。改为**生产真实链路产出**：
	# 真实完成第 1 关 → _goto_settle 记账（Game.settle_snapshot + level._settle_data）→
	# goto_state(SETTLE, {chapter}) 只带生产同构的最小 ctx，结算数据由 W6-1 优先通道
	# （settle_snapshot）提供。断言等价不弱化：评级/耗时改锁**生产产出值**（精确匹配快照，
	# 强于旧「含完美/01:05」的字面包含），并补天赋 Label 与「不重复发奖/推进」的前后一致性
	# （cleared/talent 双断言替旧单断言；断言数 67 → 72，净 +5）。
	_reset_save()
	# —— 生产链路产出结算数据（真实 join+skip 完成第 1 关）——
	var inst_f: Node = await _make_level_routed(1)
	check(inst_f != null and not target.is_empty(), "W6-2 前置：生产链路 level 实例就绪")
	if inst_f != null and not target.is_empty():
		var jb_f: Button = inst_f.get_node_or_null("TopBar/Buttons/JoinButton")
		inst_f.set("anim_time_scale", 8.0)
		inst_f.call("set_remaining_for_test", target)
		jb_f.pressed.emit()
		inst_f.call("_skip_success_animation")
		await process_frame
		check_eq(int(game.current_state()), ST_SETTLE,
			"W6-2 前置：生产链路完成记账（_goto_settle → SETTLE 态）")
	var snap_f: Dictionary = {}
	if "settle_snapshot" in game and game.get("settle_snapshot") is Dictionary:
		snap_f = game.get("settle_snapshot")
	check(not snap_f.is_empty() and String(snap_f.get("grade", "")) == "完美",
		"W6-2 前置：生产链路 settle_snapshot 已记账（grade=完美；红期字段缺席=断链）")
	var cleared_f: Array = (save.get_progress()["cleared"] as Array).duplicate()
	var talent_f: int = int(save.get_talent())
	# —— 边缘路径重建：ctx 只带生产同构最小字段（数据由 settle_snapshot 优先通道提供）——
	game.goto_state(ST_SETTLE, {"chapter": 1})
	await create_timer(0.5).timeout
	var edge: Node = game.get_current_scene()
	check(edge != null and (edge as Node).get_script() == ls_s,
		"P-D⑥：goto_state(SETTLE) 改载 level 场景（settle_scene 不再被路由）")
	check(edge != null and bool(edge.get("_settle_mode")), "P-D⑥：level 边缘路径模式置位（ctx.settle）")
	var ui3: Control = edge.get_node_or_null("SuccessOverlay/SettleUI") if edge != null else null
	check(ui3 != null and ui3.visible, "P-D⑥：边缘路径直显结算 UI（跳过动画）")
	if ui3 != null:
		var g3: Label = ui3.get_node_or_null("GradeLabel") as Label
		var e3: Label = ui3.get_node_or_null("ElapsedLabel") as Label
		var t3: Label = ui3.get_node_or_null("TalentLabel") as Label
		check(g3 != null and not String(g3.text).contains("——") and snap_f.has("grade")
			and String(g3.text).contains(String(snap_f.get("grade", ""))),
			"W6-2：边缘路径评分取生产快照（非「——」且=快照 grade；旧手工 ctx 通道废止）")
		check(e3 != null and not String(e3.text).contains("——") and snap_f.has("elapsed")
			and String(e3.text).contains(String(ls_s.call("format_time", float(snap_f.get("elapsed", 0.0))))),
			"W6-2：边缘路径耗时取生产快照（非「——」且=format_time(快照 elapsed)；旧 01:05 字面断言等价替换）")
		check(t3 != null and not String(t3.text).contains("——") and snap_f.has("talent")
			and String(t3.text).contains(str(int(snap_f.get("talent", -1)))),
			"W6-2：边缘路径天赋值取生产快照（非「——」；旧用例缺此断言，补强 +1）")
	var cloud3: Node = edge.get_node_or_null(
		"SuccessOverlay/AnimContainer/AnimViewport/AnimWorld/SpinPivot/SuccessCloud") if edge != null else null
	check(cloud3 is MultiMeshInstance3D and (cloud3 as MultiMeshInstance3D).visible,
		"P-D⑥：边缘路径建模直显（重建关卡体素后覆盖层建模成形）")
	if edge != null and cloud3 is MultiMeshInstance3D:
		# 批次 AA / W6-2 等价改写：旧「fresh save + 边缘 goto → cleared 仍空」改为
		# 「生产完成时点 vs 边缘重建后 双账一致」——生产链路必然已推进（cleared 含 1），
		# 断言前后一致 = 边缘路径不重复推进/不重复发奖（advance_progress 恰一次守护等价面，
		# cleared/talent 双账替旧单断言，断言数不减）。
		check((save.get_progress()["cleared"] as Array) == cleared_f,
			"P-D⑤⑥：边缘路径不重复推进（cleared 与生产完成时点一致——advance 恰一次跨路径守护）")
		check_eq(int(save.get_talent()), talent_f,
			"P-D⑤⑥：边缘路径不重复发奖（talent 与生产完成时点一致）")
		# 结算页继续可拖拽（拖拽区事件直驱 SpinPivot：按下置拖拽态+motion 旋转）
		var spin3: Node3D = edge.get_node_or_null(
			"SuccessOverlay/AnimContainer/AnimViewport/AnimWorld/SpinPivot")
		var yaw0: float = spin3.rotation.y if spin3 != null else 0.0
		var mb_e: InputEventMouseButton = InputEventMouseButton.new()
		mb_e.button_index = MOUSE_BUTTON_LEFT
		mb_e.pressed = true
		edge.call("_on_settle_drag_gui_input", mb_e)
		var mm_e: InputEventMouseMotion = InputEventMouseMotion.new()
		mm_e.relative = Vector2(80, 0)
		edge.call("_on_settle_drag_gui_input", mm_e)
		check(spin3 != null and absf(spin3.rotation.y - (yaw0 + 80.0 * float(lcmap.get("ORBIT_SPEED", 0.005)))) < 0.001,
			"P-D①：结算页拖拽继续旋转（yaw += dx×ORBIT_SPEED 作用于 SpinPivot，不回正）")
	# settle 场景资产保留（不删防断链）但退役留痕
	check(ResourceLoader.exists(SETTLE_SCENE) and (load(SETTLE_SCENE) as PackedScene) != null,
		"P-D⑦：settle_scene.tscn 保留可加载（asset 不断链）")
	check(FileAccess.file_exists(SETTLE_GD) and FileAccess.get_file_as_string(SETTLE_GD).contains("退役"),
		"P-D⑦：settle_scene.gd 退役标注留痕（不再被路由）")
	# ==================== G. 图鉴 SETTLE 透传（波 1 待办兑现） ====================
	print("-- G 图鉴 SETTLE 透传 --")
	var csrc: String = FileAccess.get_file_as_string(CATALOG_GD)
	check(csrc.contains("State.SETTLE"),
		"P-D⑤：catalog_scene 退出分支含 SETTLE 透传（波 1 降级 MAIN_MENU 待办兑现）")
	check(csrc.contains("P批波2"), "P-D⑤：catalog 透传注释含 P批波2 兑现留痕")
	game.goto_state(ST_SETTLE, {"chapter": 1, "grade": "完美", "elapsed": 65, "talent": 100})
	await create_timer(0.4).timeout
	game.goto_state(ST_CATALOG)
	await process_frame
	var cat: Node = game.get_current_scene()
	check(cat != null and (cat as Node).get_script() == load(CATALOG_GD), "P-D⑤ 前置：经结算进图鉴")
	if cat != null:
		(cat.get_node("BottomBar/ExitButton") as Button).pressed.emit()
		await process_frame
		check_eq(int(game.current_state()), ST_SETTLE,
			"P-D⑤：图鉴退出 SETTLE 来源透传回结算（level 边缘路径重建，不再降级主菜单）")
		var cr: Variant = game.get("catalog_return")
		check(cr is Dictionary and (cr as Dictionary).is_empty(), "P-D⑤：透传消费后复位（防串味）")

	Engine.max_fps = 0
	_restore_user()
	finish()
