extends "res://tests/test_base.gd"
## 批次 X 判定用例（P1-a，spec §2）：四态折叠横条 + 收起钮×停靠件不相交防回归 + 横条净空。
## ①常量锚：HORIZONTAL_FOLD_KEYS 恰四态（OPENING_MOVIE/TALK/LEVEL/SETTINGS，key 与 _dock_cfg
##   同源）、H_FOLD_W=120/H_FOLD_H=30（起步档，走查可微调）。
## ②四态横条逐态判据：折叠=GuidePanel 尺寸 (120,30)、锚定五元组不动（ax=R 者贴右缘）、
##   FoldTitle 横排无旋转、HintFoldBtn 居左+「手势说明」同组横排整组条内居中、▲=folded 语义、
##   展开还原 cfg hint 尺寸。
## ③五态竖条零变化：MAIN_MENU/CATALOG/SHOP/SETTLE/UNKNOWN 折叠维持宽 30、高=cfg hint y、
##   FoldTitle 旋转 90°（MAIN_MENU 折叠/竖条逐值断言另见 test_gesture_console_dock 段4）。
## ④防回归盲区补防：test_t_dock_expand._pairwise / test_u_dock_anchors._items_for 均不含收起钮
##   HintFoldBtn——本件全九态补「收起钮×其余可见停靠件（摄像头窗/状态条）不相交」。
## ⑤横条净空：H_FOLD_H ≤ 四态各自 _avail_for 净空（实测口径）；SETTINGS 横条顶缘 ≥ 下拉窗
##   底缘 252（V-E4 让位口径，V-E4 后弹窗底 252/说明栏顶 256）；折叠自动兜底路径横条态可用。
## 防坑：--script 无头 expand 撑 1152×1152——add 后补钉设计视口再等两帧；常量经 .get()+typeof
## 判型（防坑 1/7：缺常量时干净红而非中止）；同帧 position/size 即时值（无跨帧坑）。
## 清档纪律：起测前备份 user://save.json 四件组，终测逐字节还原+load_game 重同步（test_v_hud_gate
## 同款缩版；本件仅读档+会话级字典，无写档路径，仍按规范全流程留证）。

const HUD_SCENE := "res://scenes/shared/gesture_hud.tscn"
const WIN := Vector2(1152, 648)
const DROPDOWN_BOTTOM := 252.0   # 批次 V-E4：摄像头下拉 LOADING 弹窗底缘（u_dock_anchors 段7b 同源口径）

const SAVE_PATH := "user://save.json"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"
const BK_PREFIX := "user://_xfb_backup_"
const WATCHED_PATHS: Array = [SAVE_PATH, TMP_PATH, BAK_PATH]

var save: Node
var hud: Control
var STATE: Dictionary = {}
var _pre_save_text: String = ""

func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _del(p: String) -> void:
	var a: String = _abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _read_file(p: String) -> String:
	return FileAccess.get_file_as_string(p)

func _backup_user() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		_pre_save_text = _read_file(SAVE_PATH)
	for p: String in WATCHED_PATHS:
		if FileAccess.file_exists(p):
			var bk := BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_abs(p), _abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	for p: String in WATCHED_PATHS:
		_del(p)
		var bk := BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_abs(bk), _abs(p))
			DirAccess.remove_absolute(_abs(bk))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()
	var post: String = _read_file(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|x_fold_bar|files=%d" % WATCHED_PATHS.size())

func _rect(n: Control) -> Rect2:
	return Rect2(n.global_position.round(), n.size.round())

## 停靠件状态驱动（SETTINGS 经覆盖层旁路、SHOP 经 sho 旁路、UNKNOWN 走 99 兜底——分流同源）
func _drive(key: String) -> void:
	var st: int = int(STATE["MAIN_MENU"])
	match key:
		"OPENING_MOVIE", "TALK", "LEVEL", "CATALOG", "SETTLE":
			st = int(STATE[key])
		"UNKNOWN":
			st = 99
	hud.apply_dock_state(st, key == "SETTINGS", key == "SHOP")

func _status_node() -> Control:
	return hud.status_row if bool(hud.status_row.visible) else hud.status_panel

## 防回归盲区补防：收起钮（+同组 FoldTitle）×其余可见停靠件（摄像头窗/状态条）不相交
func _btn_pairwise(key: String) -> void:
	var btn: Control = hud.hint_fold_btn
	var others: Array = [[_rect(hud.camera_window), "CameraWindow"], [_rect(_status_node()), "Status"]]
	var ft: Control = hud.get_node_or_null("FoldTitle")
	var subjects: Array = [[_rect(btn), "HintFoldBtn"]]
	if ft != null and bool(ft.visible):
		subjects.append([_rect(ft), "FoldTitle"])
	var ok := true
	var bad := ""
	for s: Array in subjects:
		for o: Array in others:
			if (s[0] as Rect2).intersects(o[0] as Rect2):
				ok = false
				bad = "%s×%s" % [s[1], o[1]]
	check(ok, "X-P1a：%s 折叠态收起钮/标题×其余停靠件不相交（_pairwise 盲区补防%s）" % [key, "" if ok else "；实叠 %s" % bad])

func _initialize() -> void:
	print("== test_x_fold_bar ==")
	_backup_user()
	save = get_root().get_node("SaveManager")
	var game_node: Node = get_root().get_node("Game")
	STATE = {
		"MAIN_MENU": int(game_node.State.MAIN_MENU), "OPENING_MOVIE": int(game_node.State.OPENING_MOVIE),
		"TALK": int(game_node.State.TALK), "LEVEL": int(game_node.State.LEVEL),
		"CATALOG": int(game_node.State.CATALOG), "SETTLE": int(game_node.State.SETTLE),
	}
	for p: String in WATCHED_PATHS:
		_del(p)
	save.load_game()
	save.update_settings({"gesture_input": true, "gesture_camera_enabled": false,
		"gesture_hud_visible": true, "gesture_panel_folded": false})
	hud = (load(HUD_SCENE) as PackedScene).instantiate()
	add_child(hud)
	await process_frame
	await process_frame
	get_root().size = Vector2i(int(WIN.x), int(WIN.y))
	await process_frame
	await process_frame
	var hs: GDScript = load("res://scenes/shared/gesture_hud.gd")

	# ---- 段 1. 常量锚（5 checks）----
	var keys_v: Variant = hs.get("HORIZONTAL_FOLD_KEYS")
	check(keys_v is Array, "X-P1a：HORIZONTAL_FOLD_KEYS 常量在场（防坑 1：先 is Array 判型）")
	var hkeys: Array = keys_v if keys_v is Array else []
	check_eq(hkeys.size(), 4, "X-P1a：HORIZONTAL_FOLD_KEYS 恰四态")
	var keys_ok := true
	for k: String in ["OPENING_MOVIE", "TALK", "LEVEL", "SETTINGS"]:
		if not hkeys.has(k):
			keys_ok = false
	check(keys_ok, "X-P1a：四态=OPENING_MOVIE/TALK/LEVEL/SETTINGS（key 与 _dock_cfg 同源）")
	var wv: Variant = hs.get("H_FOLD_W")
	check(typeof(wv) == TYPE_FLOAT and is_equal_approx(float(wv), 120.0),
		"X-P1a：H_FOLD_W=120（起步档，拍板带宽 110~130；实测 %s）" % [wv])
	var hv: Variant = hs.get("H_FOLD_H")
	check(typeof(hv) == TYPE_FLOAT and is_equal_approx(float(hv), 30.0),
		"X-P1a：H_FOLD_H=30（起步档，拍板高≈30；实测 %s）" % [hv])

	# ---- 段 2. 四态横条逐态判据（4 态 × 6 checks = 24）----
	for key: String in ["OPENING_MOVIE", "TALK", "LEVEL", "SETTINGS"]:
		_drive(key)
		hud._hint_folded[key] = true
		_drive(key)
		var bar: Vector2 = hud.guide_panel.size.round()
		var bar_rect: Rect2 = _rect(hud.guide_panel)
		check(is_equal_approx(bar.x, 120.0) and is_equal_approx(bar.y, 30.0),
			"X-P1a：%s 折叠横条 120×30（实测 %s @%s）" % [key, bar, bar_rect.position])
		# 锚定五元组不动：ax=R 者贴右缘（右缘=窗宽−mx），ay=T 顶缘=cfg hint my
		var hint_d: Dictionary = hud._dock_cfg(key)["hint"]
		var expect_end_x: float = WIN.x - float(hint_d["mx"]) if hint_d["ax"] == "R" \
				else float(hint_d["mx"]) + bar.x
		check(is_equal_approx(bar_rect.end.x, expect_end_x) \
				and is_equal_approx(bar_rect.position.y, float(hint_d["my"])),
			"X-P1a：%s 横条锚点保持（右缘 %.0f/顶缘 %.0f；实测 %s）" % [key, expect_end_x, float(hint_d["my"]), bar_rect])
		var ft: Control = hud.get_node_or_null("FoldTitle")
		check(ft != null and bool(ft.visible) and absf(ft.rotation) < 0.01,
			"X-P1a：%s FoldTitle 横排显示且无旋转" % key)
		check(String(hud.hint_fold_btn.text) == "▲" and bool(hud.hint_fold_btn.visible),
			"X-P1a：%s 折叠态 ▲ 语义不变（钮可点）" % key)
		# 同组横排：▲ 居左、标题随右；整组条内左右留白均衡（居中）；钮垂直居中
		var t_rect: Rect2 = _rect(ft)
		var b_rect: Rect2 = _rect(hud.hint_fold_btn)
		check(b_rect.position.x < t_rect.position.x \
				and absf((b_rect.position.x - bar_rect.position.x) - (bar_rect.end.x - t_rect.end.x)) <= 6.0 \
				and is_equal_approx(b_rect.position.y - bar_rect.position.y, 5.0),
			"X-P1a：%s 「▲ 手势说明」同组横排整组居中、钮垂直居中（btn=%s title=%s）" % [key, b_rect, t_rect])
		_btn_pairwise(key)
		hud._hint_folded[key] = false
		_drive(key)
		check((hud.guide_panel.size as Vector2).is_equal_approx(hud._dock_cfg(key)["hint"]["size"]),
			"X-P1a：%s 展开还原 cfg hint 尺寸" % key)

	# ---- 段 3. 五态竖条零变化（5 态 × 3 checks = 15）----
	# MAIN_MENU 走 _folded 直驱（几何等价；写档语义已由 test_gesture_console_dock 段4/测试v_hud_gate 守）
	for key: String in ["MAIN_MENU", "CATALOG", "SHOP", "SETTLE", "UNKNOWN"]:
		if key == "MAIN_MENU":
			hud._folded = true
		else:
			hud._hint_folded[key] = true
		_drive(key)
		var vb: Vector2 = hud.guide_panel.size.round()
		var vh: float = (hud._dock_cfg(key)["hint"]["size"] as Vector2).y
		check(is_equal_approx(vb.x, 30.0) and vb.x >= 28.0 and vb.x <= 32.0 and is_equal_approx(vb.y, vh),
			"X-P1a：%s 折叠维持竖条宽 30∈[28,32]、高随 cfg hint 高 %.0f（实测 %s）" % [key, vh, vb])
		var ft2: Control = hud.get_node_or_null("FoldTitle")
		check(ft2 != null and bool(ft2.visible) and absf(ft2.rotation - PI / 2.0) < 0.01,
			"X-P1a：%s 竖条 FoldTitle 维持旋转 90°（竖排零变化）" % key)
		_btn_pairwise(key)
		if key == "MAIN_MENU":
			hud._folded = false
		else:
			hud._hint_folded[key] = false
		_drive(key)

	# ---- 段 4. 横条净空（5 checks）----
	# 拍板判据：横条高 ≤ 四态各自净空（_avail_for 实测口径）——兜底自动折叠后横条必容于净空
	for key: String in ["OPENING_MOVIE", "TALK", "LEVEL", "SETTINGS"]:
		var av: Vector2 = hud._avail_for(key, WIN)
		check(30.0 <= av.y and 120.0 <= av.x,
			"X-P1a：%s 横条 120×30 ≤ 净空 %s（_avail_for 实测口径）" % [key, av])
	# SETTINGS 横条顶缘 ≥ 下拉窗底缘 252（V-E4 让位口径——横条为展开矩形右对齐子集，仍守净隙）
	hud._hint_folded["SETTINGS"] = true
	_drive("SETTINGS")
	var s_bar: Rect2 = _rect(hud.guide_panel)
	check(s_bar.position.y >= DROPDOWN_BOTTOM,
		"X-P1a：SETTINGS 横条顶缘 %.0f ≥ 下拉窗底缘 %.0f（V-E4 净隙口径维持）" % [s_bar.position.y, DROPDOWN_BOTTOM])
	hud._hint_folded["SETTINGS"] = false
	_drive("SETTINGS")

	# ---- 段 5. 折叠自动兜底路径横条态可用（2 checks）----
	# 触发 U5⑨ 兜底（LEVEL：av.y<min_size.y → _hint_folded 自动置位）→ 横条态落位。
	# 无头实测坑（p1_probe_resize_temp 留证）：project.godot stretch=canvas_items/aspect=expand
	# → root.size 改小只缩放不缩内容坐标（内容空间恒 ≥ 基准 1152×648，二次 root.size 不传播到
	# HUD）——须改 content_scale_size 基准直缩内容空间；终测还原基准+重钉视口。
	get_root().content_scale_size = Vector2i(640, 360)
	await process_frame
	await process_frame
	_drive("LEVEL")
	check_eq(bool(hud._hint_folded.get("LEVEL", false)), true, "X-P1a：小窗兜底自动折叠 LEVEL（U5⑨ 路径存活）")
	var fb_bar: Vector2 = hud.guide_panel.size.round()
	check(is_equal_approx(fb_bar.x, 120.0) and is_equal_approx(fb_bar.y, 30.0),
		"X-P1a：兜底折叠落横条 120×30（实测 %s）" % fb_bar)
	get_root().content_scale_size = Vector2i(int(WIN.x), int(WIN.y))
	await process_frame
	await process_frame
	hud._hint_folded.clear()
	_drive("LEVEL")

	# ---- 现场还原 ----
	save.update_settings({"gesture_input": true, "gesture_camera_enabled": false,
		"gesture_hud_visible": true, "gesture_panel_folded": false})
	_restore_user()
	finish()
