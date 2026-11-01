extends "res://tests/test_base.gd"
## 批次 Z Z3（spec §3-6，用户拍板）：见证者气泡**入场动效**红测——只加「淡入 + 轻微缩放弹跳
## （约 0.2s）」，弹窗样式与 4 秒自灭**完全不变**，**不做打字机**。
## 中途帧护栏（防「空转假绿」，批次 W ToastCenter 教训——临时删守卫须见红，见交付报告）：
##   ① 弹出当帧 modulate.a==0 且 scale<1（入场起点）；入场过程存在某帧 a∈(0,1)；
##   ② 存在缩放**过冲帧** scale.x>1.0（弹跳峰值），终值回落 a==1 且 scale==1；
##   ③ **无逐字打字机通道**：弹出即整句（∈生产池），整段入场文本逐帧恒定；
##   ④ 总自灭仍 4.0s：WITNESS_BUBBLE_SECONDS==4.0、弹出即置 4.0s 计时、计时中段仍可见、
##      计时到点自动隐藏（真实计时驱动，非空转）；
##   ⑤ 常量 WITNESS_BUBBLE_ENTER_SEC==0.2（约 0.2s 档）。
## 生产默认链（不注入夹具）：level_scene set_context(chapter=1) → 剧情对话/气泡_第1关.json。
## 无头纪律：add_child 后 await process_frame；缺属性时 get 返回 null——
## 一律 `is float/is Array` 判型后再取值（禁止 float(null) 中止 _initialize）；
## level_scene _exit_tree 写挖除断点 → user:// 备份还原（独立前缀 zbge，规范六条）。

const LEVEL_SCENE := "res://scenes/level/level_scene.tscn"
const LS_SCRIPT := "res://scenes/level/level_scene.gd"
const DOC_DIR := "res://剧情对话/"

const ENTER_SEC := 0.2
const AUTO_HIDE_SEC := 4.0

# ===== 清档纪律（tools/README_走查清档规范.md；level 实例 _exit_tree 写检查点）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_zbge_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _pre_save_text: String = ""

func _disc_abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _disc_del(p: String) -> void:
	var a: String = _disc_abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _backup_user() -> void:
	if FileAccess.file_exists(DISC_SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(DISC_SAVE_PATH)
	for p: String in DISC_WATCHED:
		if FileAccess.file_exists(p):
			var bk: String = DISC_BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_disc_abs(p), _disc_abs(bk))

func _restore_user() -> void:
	for c: Node in root.get_children():
		if not DISC_AUTOLOADS.has(String(c.name)):
			c.free()
	for p: String in DISC_WATCHED:
		_disc_del(p)
		var bk: String = DISC_BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_disc_abs(bk), _disc_abs(p))
			DirAccess.remove_absolute(bk)
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()
	var post: String = FileAccess.get_file_as_string(DISC_SAVE_PATH) if FileAccess.file_exists(DISC_SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|zbge|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_z_bubble_entry ==")
	_backup_user()

	# ---- ⑤/④ 常量锁（源级；缺键时 get 缺省 -1 → 必红）----
	var cmap: Dictionary = (load(LS_SCRIPT) as GDScript).get_script_constant_map()
	check(is_equal_approx(float(cmap.get("WITNESS_BUBBLE_SECONDS", -1.0)), AUTO_HIDE_SEC),
		"④：WITNESS_BUBBLE_SECONDS==4.0（自灭口径不变，实测 %s）" % str(cmap.get("WITNESS_BUBBLE_SECONDS")))
	check(is_equal_approx(float(cmap.get("WITNESS_BUBBLE_ENTER_SEC", -1.0)), ENTER_SEC),
		"⑤：入场时长常量 WITNESS_BUBBLE_ENTER_SEC==0.2s（实测 %s）" % str(cmap.get("WITNESS_BUBBLE_ENTER_SEC")))

	# ---- 生产默认链实例化（chapter=1 → 气泡_第1关.json，零夹具）----
	var lv: Node = (load(LEVEL_SCENE) as PackedScene).instantiate()
	lv.call("set_context", {"chapter": 1})
	add_child(lv)
	await process_frame
	await process_frame
	var pool: Array = lv.call("get_witness_lines_pool")
	check_eq(pool.size(), 12, "前置：默认链池 12 条（零夹具）")
	var lb: Variant = lv.get("witness_bubble")
	check(lb is Label, "前置：WitnessBubble(Label) 在位")
	if not (lb is Label) or pool.is_empty():
		finish()
		return
	var label: Label = lb as Label

	# ---- 弹出：当帧入场起点（① 起点 + ③ 整句 + ④ 计时）----
	lv.call("_show_witness_bubble")
	check(bool(lv.get("_witness_bubble_open")), "前置：气泡已弹出")
	check(label.visible, "前置：WitnessBubble.visible==true")
	var t0: Variant = lv.get("_bubble_entry_t")
	check(t0 is float and is_equal_approx(float(t0), 0.0),
		"①：弹出当帧入场进度==0（进度槽在位；实测 %s）" % str(t0))
	check(is_equal_approx(label.modulate.a, 0.0),
		"①：弹出当帧 modulate.a==0（淡入起点；红：现状恒 1）")
	check(label.scale.x < 0.999, "①：弹出当帧 scale<1（缩放入场起点；红：现状恒 1，实测 %s）" % str(label.scale))
	var text0: String = String(label.text)
	check(text0 != "" and pool.has(text0),
		"③：弹出即整句（∈生产池，无逐字重建；实测「%s」）" % text0)
	var tm: Variant = lv.get("_witness_bubble_timer")
	check(tm is float and is_equal_approx(float(tm), AUTO_HIDE_SEC),
		"④：弹出即置 4.0s 自灭计时（实测 %s）" % str(tm))

	# ---- 中途帧采样护栏（① a∈(0,1) 帧 + ② 过冲帧 + ③ 文本恒定 + 入场终值）----
	var saw_partial_a := false
	var saw_bounce := false
	var max_scale := 1.0
	var text_const := true
	var entry_live := true
	var frames := 0
	while frames < 20000 and entry_live:
		frames += 1
		await process_frame
		var a: float = label.modulate.a
		if a > 0.001 and a < 0.999:
			saw_partial_a = true
		var sx: float = label.scale.x
		if sx > max_scale:
			max_scale = sx
		if sx > 1.001:
			saw_bounce = true
		if String(label.text) != text0:
			text_const = false
		var et: Variant = lv.get("_bubble_entry_t")
		entry_live = et is float and float(et) >= 0.0
	check(saw_partial_a, "①中途帧护栏：入场过程存在 modulate.a∈(0,1) 帧（防空转假绿）")
	check(saw_bounce, "②中途帧护栏：存在缩放过冲帧 scale.x>1.0（弹跳峰值 %.3f；红：现状恒 1.0）" % max_scale)
	check(is_equal_approx(label.modulate.a, 1.0) and label.scale.is_equal_approx(Vector2.ONE),
		"②入场终值：modulate.a==1.0 且 scale==1（实测 a=%.2f scale=%s）" % [label.modulate.a, str(label.scale)])
	check(text_const, "③：整段入场文本逐帧恒定=整句（无逐字打字机通道；首句「%s」）" % text0)
	check(frames >= 2, "①：入场非瞬时（采样 %d 帧跨过入场期；单帧即完成=锚失真）" % frames)

	# ---- ④ 总自灭仍 4.0s：按真实剩余计时驱动中段可见 → 到点隐藏 ----
	var tv: Variant = lv.get("_witness_bubble_timer")
	check(tv is float and float(tv) > 3.0 and float(tv) <= AUTO_HIDE_SEC + 0.001,
		"④：入场结束后剩余自灭计时∈(3,4]（实测 %s）" % str(tv))
	if tv is float and float(tv) > 0.6:
		await create_timer(float(tv) - 0.3).timeout
		check(label.visible, "④：计时未到（剩 ≈0.3s）仍可见（4.0s 口径中段护栏）")
		await create_timer(0.8).timeout
		check(not label.visible, "④：计时到点自动隐藏（总自灭仍 4.0s，真实计时非空转）")
	# ---- 再次弹出：入场动效重置可复现（防一次性假绿）----
	lv.call("_show_witness_bubble")
	check(label.visible and is_equal_approx(label.modulate.a, 0.0),
		"①：再次弹出重置入场（a==0；红：现状 a 恒 1）")
	check(String(label.text) != "" and pool.has(String(label.text)), "③：再次弹出仍为整句∈池")
	lv.call("_hide_witness_bubble")
	check(not label.visible, "收起：_hide_witness_bubble 生效")

	lv.queue_free()
	await process_frame
	finish()
