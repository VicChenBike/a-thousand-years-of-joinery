extends "res://tests/test_base.gd"
## 批次 U 判定用例（U-D 域·HoverTip）：双路径悬停＋三钮文案＋IGNORE 不吞点击＋enabled 谓词
## （双审 P2-12）＋U3 象限门控。spec §4-U2-1/U3/U7。
## 防坑 6：全部同系比较（host.get_global_rect 对合成全局光标位）；防坑 1：断言前 await process_frame。

const TipScript := preload("res://scenes/shared/hover_tip.gd")

func _make_tip(host: Control, text: String, enabled: Callable = Callable(), provider: Callable = Callable()) -> PanelContainer:
	var tip: PanelContainer = TipScript.new()
	get_root().add_child(tip)
	await process_frame
	tip.setup(host, text, enabled, provider)
	return tip

## 双审回修 P1-2：合成左键点击（press+release）经 push_input 注入既有 gui_input 管线
##（gesture_cursor_layer「push_input(ev, true)」同款先例；position 为全局 content 坐标）
func _click_at(pos: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	get_root().push_input(down, true)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	get_root().push_input(up, true)

# ===== 清档纪律（tools/README_走查清档规范.md，批次V回修②B 补齐，test_v_save_domain 同款）=====
# 起测前备份 user:// 真实档案（save.json/first_launch.flag 及可触及的 .tmp/.bak 四件组），
# 终测统一经 finish() 收口还原：先同步 free 测试挂载节点（level._exit_tree 兜底写档等
# 「退出写回」先落测试域磁盘，规范第 6 条），再逐件还原 + SaveManager load_game 重同步内存
# + 逐字节等价断言 + EVID 证据行。备份路径必须带全 user:// 前缀（相对路径在 FileAccess/
# DirAccess 间解析漂移 → 备份链静默失效，test_n10 先例）；每文件独立备份前缀防崩溃残留互踩。
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_r2b_uht_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _pre_save_text: String = ""   # 起测前真实 save.json 原文（还原等价自检基准）

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _disc_del(p: String) -> void:
	var a: String = _disc_abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _backup_user() -> void:
	# 规范第 1 条：任何删/写档操作之前备份真实档案（有档才备份；还原「有备份才回拷」幂等，
	# 起测前不存在的档案终测后仍不存在——测试自建残留一律清零）
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	# 防退出写回（规范第 6 条）：先同步 free 测试挂载的非 autoload 节点——level._exit_tree
	# 兜底写档（N9）若拖到进程退出树序，会在还原之后把测试态写回真实档案；提前 free 令
	# 兜底写档落测试域磁盘，紧随其后的逐件还原即将其覆盖。
	for c: Node in root.get_children():
		if not DISC_AUTOLOADS.has(String(c.name)):
			c.free()
	# 规范第 2 条：逐件还原 + load_game 重同步内存（防后续 save_game 把测试态写回真实档案）
	for p: String in DISC_WATCHED:
		_disc_del(p)
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(_disc_abs(bk))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()
	# 纪律自检：还原后 save.json 与起测前逐字节等价（起测前无档 ↔ 还原后无档）
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|uht|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_u_hover_tip ==")
	_backup_user()
	# ---- 段 1. 组件形态（4 checks）----
	var host := Button.new()
	host.text = "宿主"
	host.position = Vector2(100, 100)
	host.size = Vector2(120, 40)
	get_root().add_child(host)
	await process_frame
	var tip := await _make_tip(host, "测试提示")
	check_eq(int(tip.mouse_filter), Control.MOUSE_FILTER_IGNORE, "U7：HoverTip mouse_filter==IGNORE（绝不吞点击——CamTip 三因同治之一）")
	check_eq(int((tip.get_child(0) as Label).mouse_filter), Control.MOUSE_FILTER_IGNORE, "U7：内部 Label 同为 IGNORE")
	# 磁盘实况适配留痕：计划原文 TipScript.get("TIP_OFFSET") 在 4.7 报 Parse Error
	#（Cannot call non-static function "get()" on the class directly）——常量读取改静态
	# 成员访问 TipScript.TIP_OFFSET（preload 脚本常量静态可解析，断言目标不变：(18,20)）。
	check_eq(TipScript.TIP_OFFSET, Vector2(18, 20), "U2/U7：TIP_OFFSET==(18,20)（光标右下偏移，spec §5）")
	check_eq(String((tip.get_child(0) as Label).text), "测试提示", "U7：setup 文案逐字落 Label")
	# ---- 段 2. 键鼠路径（4 checks；provider 注入合成系统鼠标位）----
	# 磁盘实况适配留痕：GDScript lambda 按值捕获（创建时快照），外层重赋值不入闭包——
	# 改单元素 Array 作可变引用单元（provider 每帧读 cell[0]，断言语义不变）。
	var mouse_cell: Array = [Vector2(150, 120)]   # host 中心
	var tip2 := await _make_tip(host, "键鼠提示", Callable(), func() -> Variant: return mouse_cell[0])
	await process_frame
	tip2._process(0.016)
	await process_frame
	check(bool(tip2.visible), "U7：键鼠路径——指针入宿主 → tip 可见")
	check_eq((tip2.global_position as Vector2).is_equal_approx(Vector2(150, 120) + Vector2(18, 20)), true,
		"U7：tip 位置==光标右下偏移（永不压光标本体）")
	mouse_cell[0] = Vector2(10, 10)
	tip2._process(0.016)
	await process_frame
	check(not bool(tip2.visible), "U7：指针移出宿主 → 隐藏（无保活矩形——U2-1 判据删除）")
	host.visible = false
	mouse_cell[0] = Vector2(150, 120)
	tip2._process(0.016)
	await process_frame
	check(not bool(tip2.visible), "U7：宿主不可见 → 强制隐藏")
	host.visible = true
	# ---- 段 3. 手势路径（4 checks；provider 注入手势光标位）----
	var gest_cell: Array = [Vector2(160, 130)]
	var tip3 := await _make_tip(host, "手势提示", Callable(), func() -> Variant: return gest_cell[0])
	tip3._process(0.016)
	await process_frame
	check(bool(tip3.visible), "U7：手势路径——合成光标入宿主 → 可见（双路径同一判定核）")
	gest_cell[0] = Vector2(900, 600)
	tip3._process(0.016)
	await process_frame
	check(not bool(tip3.visible), "U7：手势光标移出 → 隐藏")
	var tip4 := await _make_tip(host, "空光标", Callable(), func() -> Variant: return null)
	tip4._process(0.016)
	await process_frame
	check(not bool(tip4.visible), "U7：provider 返回 null（本帧无手势光标）→ 隐藏")
	# +10 同系验证：host 挂带 offset 的 CanvasLayer 下（GlobalUI 同构）——get_global_rect 含 +10，
	# 合成光标位为真全局位，has_point 命中即证明无跨系漂移（防坑 6）
	var cl := CanvasLayer.new()
	cl.offset = Vector2(10, 10)
	get_root().add_child(cl)
	var host2 := Button.new()
	host2.position = Vector2(90, 90)   # 层内坐标；全局=(100,100)
	host2.size = Vector2(120, 40)
	cl.add_child(host2)
	await process_frame
	var tip5 := await _make_tip(host2, "同系", Callable(), func() -> Variant: return Vector2(150, 120))
	tip5._process(0.016)
	await process_frame
	check(bool(tip5.visible), "U7：CanvasLayer offset(+10) 下同系比较命中（无 10px 手工加减漂移）")
	# ---- 段 4. enabled 谓词（3 checks）----
	var gate_cell: Array = [false]   # 同段 2：lambda 按值捕获 → Array 引用单元
	var tip6 := await _make_tip(host, "谓词", func() -> bool: return gate_cell[0], func() -> Variant: return Vector2(150, 120))
	tip6._process(0.016)
	await process_frame
	check(not bool(tip6.visible), "U2-12：enabled=false → 强制隐藏（指针在宿主上也不显示）")
	gate_cell[0] = true
	tip6._process(0.016)
	await process_frame
	check(bool(tip6.visible), "U2-12：enabled=true → 恢复显示（每帧复判）")
	gate_cell[0] = false
	tip6._process(0.016)
	await process_frame
	check(not bool(tip6.visible), "U2-12：谓词翻转 → 可见性跟随翻转")
	# ---- 段 5. 三钮文案（5 checks；level_scene 实例）----
	var lvl: Node = (load("res://scenes/level/level_scene.tscn") as PackedScene).instantiate()
	get_root().add_child(lvl)
	await process_frame
	await process_frame
	var eye: Button = lvl.get_node("TopBar/Buttons/EyeButton")
	var join: Button = lvl.get_node("TopBar/Buttons/JoinButton")
	var focus: Button = lvl.get_node("TopBar/Buttons/FocusButton")
	check_eq(String(join.tooltip_text), "", "U7-3：JoinButton 原生 tooltip_text 移除（防双提示并存）")
	var tips: Array = []
	for n: Variant in lvl.find_children("*", "PanelContainer", true, false):
		if (n as Node).get_script() == TipScript:
			tips.append(n)
	check_eq(tips.size(), 3, "U7-3：三钮各挂 1 个 HoverTip（共 3）")
	var texts: Array = []
	for t: Variant in tips:
		texts.append(String((t as PanelContainer).get_child(0).text))
	check(texts.has("锐眼：挖除已选部件的辅助提示"), "U7-3：锐眼文案逐字")
	# 批次 Z 终审 P2（2026-09-24）：判定基准=标准答案（target），面板显示=最终成品（final）——
	# 旧名「对照成品」tooltip 文案退场，正向锚新文案 + 反向锚旧名零残留（断言只增不减，+1）。
	check(texts.has("对接：按标准答案判定对接"), "U7-3：对接文案逐字（批次Z终审P2：标准答案口径）")
	check(not texts.has("对接：对照成品判定对接"), "U7-3：旧名「对照成品」tooltip 文案退场（反向护栏）")
	check(texts.has("聚焦：放大聚焦单个部件"), "U7-3：聚焦文案逐字")
	lvl.queue_free()
	# ---- 段 6. 不吞点击（2 checks；双审回修 P1-2：Viewport.gui_find_control 在 4.7 不存在
	#（has_method 实测 false）——改合成 InputEventMouseButton 经 push_input 实弹断言按钮 pressed）----
	var under := Button.new()
	under.position = Vector2(300, 300)
	under.size = Vector2(100, 40)
	get_root().add_child(under)
	await process_frame
	var tip7 := await _make_tip(under, "压住", Callable(), func() -> Variant: return Vector2(340, 320))
	tip7._process(0.016)
	await process_frame
	var clicked: Array = []
	under.pressed.connect(func() -> void: clicked.append(1))
	_click_at(Vector2(340, 320))
	await process_frame
	check(clicked.size() == 1, "U7：tip 可见态压宿主——合成点击（push_input）命中宿主按钮而非 tip（IGNORE 穿透实判；tip 若吞点击则 clicked 空）")
	var sp: Node = (load("res://scenes/settings/settings_panel.tscn") as PackedScene).instantiate()
	get_root().add_child(sp)
	await process_frame
	await process_frame
	var ct: Button = sp.get_node("Panel/VBox/OptionsBox/CameraRow/CameraToggle")
	var clicked2: Array = []
	ct.pressed.connect(func() -> void: clicked2.append(1))
	_click_at(ct.get_global_rect().get_center())
	await process_frame
	check(clicked2.size() == 1, "U2：CamTip 迁移后——摄像头开关矩形中心合成点击命中其本体（点击会切 Q2，测试实例用后即弃无副作用）")
	sp.queue_free()
	# ---- 段 7. U3 象限门控（2 checks；settings_panel 的 Q2 谓词）----
	var sp2: Node = (load("res://scenes/settings/settings_panel.tscn") as PackedScene).instantiate()
	get_root().add_child(sp2)
	await process_frame
	var save: Node = get_root().get_node("SaveManager")
	save.load_game()
	# Q2（手势关＋摄像头开）→ 谓词 true
	save.update_settings({"gesture_input": false, "gesture_camera_enabled": true})
	var q2_tips: Array = []
	for n: Variant in sp2.find_children("*", "PanelContainer", true, false):
		if (n as Node).get_script() == TipScript:
			q2_tips.append(n)
	check(q2_tips.size() >= 1 and _eval_enabled(q2_tips[0]), "U3：Q2 态谓词 true（悬浮摄像头开关显示）")
	# 挂死防御留痕（磁盘实况适配）：UD-6 未合并时 q2_tips 为空——计划原文 q2_tips[0] 越界
	# 中止 _initialize 致 finish() 永不执行（--script 挂死）。守卫后红灯期显式红、UD-6 后转实判。
	var q2_tip: PanelContainer = q2_tips[0] if q2_tips.size() > 0 else null
	# Q1/Q3/Q4 → 谓词 false（表驱动一条循环断言）
	var quad_ok := q2_tip != null
	for quad: Array in [[true, true], [true, false], [false, false]]:   # [gesture_input, camera_enabled] = Q1/Q3/Q4
		save.update_settings({"gesture_input": quad[0], "gesture_camera_enabled": quad[1]})
		if q2_tip != null and _eval_enabled(q2_tip):
			quad_ok = false
	check(quad_ok, "U3：Q1/Q3/Q4 态谓词 false（不显示；Q1 信息由 U1 toast 承担）")
	save.update_settings({"gesture_input": true, "gesture_camera_enabled": false})
	sp2.queue_free()
	finish()

func _eval_enabled(tip: PanelContainer) -> bool:
	# 经组件私有谓词逐帧判定结果反推 enabled（驱动一帧后读 visible 与指针在位状态）
	return bool(tip._enabled.call())
