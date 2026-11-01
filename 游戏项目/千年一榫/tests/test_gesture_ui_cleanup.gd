extends "res://tests/test_base.gd"
## 批次 S 判定用例（S16/S12 消费侧；批次 T 归属单化 P1-4：S14 toast 段移交 test_t_camera_device）
## ：关手势全清 + 光斑数据源联动 + Router 状态机复位。
## main.tscn 真挂载（test_gesture_hud 同款）；Router 用 autoload 实例（--script 无头 _ready 不
## 触发 → 显式 _setup() 幂等初始化）。倒数时序经真实 feed 驱动（tracker 延迟窗用真实时钟等待）。

func _hand(conf: float, fingers: Array, tip: Vector2, label: String) -> Dictionary:
	var lm: Array = []
	for i: int in 21:
		lm.append([0.5, 0.5, 0.0])
	lm[0] = [tip.x - 0.05, tip.y + 0.2, 0.0]
	if label == "Left":   # 左掌面朝镜
		lm[5] = [lm[0][0] + 0.05, lm[0][1] - 0.06, 0.0]
		lm[17] = [lm[0][0] - 0.05, lm[0][1] - 0.05, 0.0]
	else:
		lm[5] = [lm[0][0] - 0.05, lm[0][1] - 0.06, 0.0]
		lm[17] = [lm[0][0] + 0.05, lm[0][1] - 0.05, 0.0]
	lm[8] = [tip.x, tip.y, 0.0]
	lm[9] = [lm[0][0], lm[0][1] - 0.2, 0.0]
	return {"gesture": "", "gesture_id": 0, "confidence": conf,
		"hand_x": tip.x, "hand_y": tip.y, "hand_z": 0.0,
		"hand_rotation_x": 5.0, "hand_rotation_y": 0.0, "hand_rotation_z": 0.0,
		"fingers": fingers, "pinch_distance": 0.5, "hand_index": 0, "handedness": label,
		"landmarks": lm, "fps": 30.0, "is_detected": true, "timestamp": 0.0, "palm_size": 0.2}

func _cleanup() -> void:
	var p: String = ProjectSettings.globalize_path("user://save.json")
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)

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
const DISC_BK_PREFIX := "user://_r2b_guc_backup_"
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
	print("EVID|user_restore|guc|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_gesture_ui_cleanup ==")
	_backup_user()
	var save: Variant = get_root().get_node("SaveManager")
	var bridge: Variant = get_root().get_node("GestureBridge")
	var router: Variant = get_root().get_node("GestureRouter")
	router._setup()   # --script 无头 autoload _ready 不触发 → 显式幂等初始化（_map/_tracker 就位）
	_cleanup()
	save.load_game()
	bridge._set_state(1)   # READY（feed 消费前提）
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await process_frame
	await process_frame
	# 环境性甄别（§1.3 并行窗口期）：树激活时 bridge._ready 才首次触发，无头 9876 被并行进程
	# 占用即置 UNAVAILABLE——headless 无真包，与被测消费侧逻辑无关；复位 READY 恢复设计前置
	# （与本测试开局 _set_state(1) 同手法，空闲环境下为 no-op）。
	bridge._set_state(1)

	# ---- 1. S12：光标可见时 _resolve_pointer_px 返回光标位；隐藏回落真实鼠标 ----
	var layer: Node = main.get_node("GestureCursorLayer")
	layer.call("show_cursor", "left", Vector2(300.0, 200.0))
	var vp := main.get_viewport()
	var expect: Vector2 = vp.get_screen_transform() * Vector2(300, 200)
	check(main._resolve_pointer_px().is_equal_approx(expect), "S12：光标可见 → 光斑源=光标位（同屏变换同像素系）")
	layer.call("hide_cursor", "left")
	var mouse_expect: Vector2 = vp.get_screen_transform() * vp.get_mouse_position()
	check(main._resolve_pointer_px().is_equal_approx(mouse_expect), "S12：无可见光圈 → 回落真实鼠标路径（键鼠零变化）")

	# ---- 2. S16：倒数中关手势开关 → 光标圈/弹窗/面板/tracker 四件全清，重开可再用 ----
	# 修复6（批次Z走查）：倒数弹条迁独立 ExitDialogLayer（layer=66>TopStrip 63），路径随之更新。
	var ged: Node = main.get_node("ExitDialogLayer/GestureExitDialog")
	var ring_l: Control = layer.get_child(0)   # Ring 创建序：left=child(0)/right=child(1)
	var f_cursor: Array = [0.1, 0.9, 0.1, 0.1, 0.1]
	var f_four: Array = [0.1, 0.9, 0.9, 0.9, 0.9]
	router.feed({"left": _hand(0.9, f_cursor, Vector2(0.3, 0.4), "Left"), "right": null, "timestamp": 0.0})
	check(ring_l.visible, "S16 前置：左手光标圈可见")
	var lf := _hand(0.9, f_four, Vector2(0.3, 0.4), "Left")
	var rf := _hand(0.9, f_four, Vector2(0.7, 0.4), "Right")
	router.feed({"left": lf, "right": rf, "timestamp": 0.0})
	router.feed({"left": lf, "right": rf, "timestamp": 0.033})   # 翻转前置 2 帧锁定；右掌入态（W3-2 dwell 起算）
	var lf2 := _hand(0.9, f_four, Vector2(0.3, 0.4), "Left")
	var rf2 := _hand(0.9, f_four, Vector2(0.7, 0.4), "Right")
	lf2["hand_rotation_x"] = 130.0
	rf2["hand_rotation_x"] = 130.0
	# 批次 AA W3-2 时序改写（spec §6.3 + §22 裁决 2；接续批次X收口 P2-1 的「实时等窗」手法）：
	# clear 提交由「右四指双帧同帧」改为「右掌静止 dwell 1.0s」（router.feed 走真实时钟）→
	# ①先实时等待跨过 dwell 窗，补喂静态帧使 clear 提交并置独立防误窗（CLEAR_FLIP_GUARD_SEC=0.35s）；
	# ②再实时等待越过防误窗 → 前置重锁 2 帧 → 双手同翻；exit_flip 配对/倒数断言意图不变。
	await create_timer(1.1).timeout
	router.feed({"left": lf, "right": rf, "timestamp": 0.10})    # 静止满 1.0s → 右 clear 提交（防误窗 0.35s）+ 双方前置重累计 1
	await create_timer(0.45).timeout                               # 越过独立防误窗（旧「1.0s 翻转冷却」注退役）
	router.feed({"left": lf, "right": rf, "timestamp": 0.133})   # 双方前置重锁（roll0=5.0）
	router.feed({"left": lf2, "right": rf2, "timestamp": 0.20})  # 双手同翻 1（roll Δ=125°>75°）
	router.feed({"left": lf2, "right": rf2, "timestamp": 0.233}) # 同翻 2 → 双触发 → 窗内配对 exit_flip
	check(int(router._tracker.get("_remaining")) == 3, "S16 前置：同翻 ×1 → 倒数 pending（批次 Y Y-A2：首翻当帧 started，remaining=3）")
	await create_timer(0.7).timeout   # 批次 Y（Y-A2）：首显延迟退役——started 已于配对帧当帧发出，此等待仅留时序余量
	router.feed({"left": lf, "right": rf, "timestamp": 1.0})   # tick（3s 停留期内）→ 弹条保持显示
	check(ged.visible, "S16 前置：倒数弹窗已显示（main 经 Router 信号驱动）")
	save.update_settings({"gesture_input": false})   # settings_changed → main._refresh_hud 清理
	check(not ring_l.visible, "S16：光标圈即时隐藏（不等 2s 自然超时）")
	check(not ged.visible, "S16：倒数弹窗关闭")
	check(router.get("_active_panel") == null, "S16：激活面板/描边清空")
	check(int(router._tracker.get("_remaining")) == 0, "S16：tracker 已复位")
	save.update_settings({"gesture_input": true})   # 重开 → 可再用
	router.feed({"left": _hand(0.9, f_cursor, Vector2(0.4, 0.4), "Left"), "right": null, "timestamp": 3.0})
	check(ring_l.visible, "S16：重开手势 → 光标随 cursor_move 重现（无残留状态）")
	router.feed({"left": lf, "right": rf, "timestamp": 3.1})
	router.feed({"left": lf, "right": rf, "timestamp": 3.133})   # 前置重锁；右掌入态（W3-2 dwell 起算）
	# W3-2 时序改写同序列 1：实时跨 dwell 窗让 clear 提交（防误窗 0.35s）→ 越窗重锁再同翻
	#（tracker reset 后从翻转 #1 重计断言不变）
	await create_timer(1.1).timeout
	router.feed({"left": lf, "right": rf, "timestamp": 3.20})    # 静止满 1.0s → 右 clear + 双方前置重累计 1
	await create_timer(0.45).timeout                               # 越过独立防误窗
	router.feed({"left": lf, "right": rf, "timestamp": 3.233})   # 双方前置重锁
	router.feed({"left": lf2, "right": rf2, "timestamp": 3.30})  # 双手同翻 1（roll Δ=125°>75°）
	router.feed({"left": lf2, "right": rf2, "timestamp": 3.333}) # 同翻 2 → 配对 exit_flip（复位后再同翻 ×1）
	check(int(router._tracker.get("_remaining")) == 3,
		"S16：复位后同翻从翻转 #1 重计（remaining=3；未复位应为 2）——再喂同翻不会立即 exit")

	# ---- 3. P2-1 回修：未 _setup 的 Router 直调 reset_runtime() 不报错且 armed 等成员照常清零 ----
	# 批次 T 归属单化（P1-4，§0.5 台账 ui_cleanup 净 −9）：原段 3「S14 UNAVAILABLE toast」10 条
	# 整段移交 test_t_camera_device 段 5 承接（含「consume 标志已被 main 消费」与「补发同文案」两条），
	# 本文件不再持有 S14 断言；段序相应上移。
	# 无头 --script 场景：_ready/_setup 未触发 → _map/_tracker 为 null；此态被 state_changed 信号
	# 回调触发 reset_runtime 曾空引用 SCRIPT ERROR（函数中断，armed 清零步被跳过）。守卫方案：
	# null 成员安全跳过、普通成员清零照常；已 _setup 实例行为不变。
	var fresh: Variant = load("res://autoload/gesture_router.gd").new()   # 不入树 → _ready/_setup 不触发
	var fake_panel: Node = Node.new()   # 真实 Node（_active_panel 为 Node 型，防 set 类型报错干扰）
	fresh.set("_menu_click_armed", {"left": true, "right": true})   # 批次 T：armed 字典化等价改写（预置双侧 armed 残留态）
	fresh.set("_left_stroking", true)
	fresh.set("_right_stroking", true)
	fresh.set("_cloud_rotating", true)
	fresh.set("_active_panel", fake_panel)
	check(fresh.get("_map") == null and fresh.get("_tracker") == null,
		"P2-1 前置：未 setup 实例 _map/_tracker 为 null（守卫对象甄别）")
	fresh.call("reset_runtime")   # 修复前：_map.reset() 空引用 SCRIPT ERROR → 函数中断，armed 残留 true
	check(bool(fresh.get("_menu_click_armed")["left"]) == false and bool(fresh.get("_menu_click_armed")["right"]) == false \
		and fresh.get("_left_stroking") == false and fresh.get("_right_stroking") == false \
		and fresh.get("_cloud_rotating") == false and fresh.get("_active_panel") == null,
		"P2-1：未 setup 直调 reset_runtime 不报错且双侧 armed/笔画/面板等成员照常清零（批次 T per-side 字典化等价改写：布尔真值对非空字典恒真，必须逐侧键值；其余条件原样保持）")
	check_eq(String(fresh.get("_level_mode")), "SELECT_ARMED",
		"T10：reset_runtime 后关卡模式状态机复位（S16 清理清单扩展）")
	fake_panel.free()
	fresh.free()   # 未入树手动释放（防退出 ObjectDB 泄漏告警）

	_cleanup()
	finish()
