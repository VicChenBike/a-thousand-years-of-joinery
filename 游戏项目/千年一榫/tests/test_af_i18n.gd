extends "res://tests/test_base.gd"
## 游戏内中英文切换（I18n autoload）红测先行（TDD）。
## 契约（任务书 §架构）：
##   ①中文原文即键——I18n.t(zh)：zh 语言原样返回（既有 162 测试全绿基线）；en 查合并表，
##     未命中返回中文 + 每键一次 push_warning（get_warned_keys/get_warned_count 观测口）。
##   ②表 = assets/i18n/ui_en.json（{"_说明":[…],"翻译":{…}}，新建）+ assets/i18n/content_en.json
##     （只读、可能不存在则跳过——并行实施者产出域，本测试两态均须正确）。
##   ③set_language/get_language + language_changed 信号；存档 settings.language（"zh"/"en"
##     缺省 zh，归一化防御参照 _safe_bool 风格——非法值/键缺/null 一律回 zh，save_version 不变）。
##   ④设置面板 OptionsBox FullscreenToggle 后 Language 行：标签固定 "Language"（不翻译）+
##     OptionButton（简体中文/English），切换即 I18n.set_language + 写档。
##   ⑤实时刷新（language_changed）：设置面板/主菜单按钮/HUD 行组；其余 _ready 取值（重进生效）。
##   ⑥逻辑解耦 4 点（先行）：camera_menu 检测中行改 meta 状态位；settings_panel 点循环改下标
##     驱动；gesture_hud 左/右 tag 改逻辑键 "left"/"right"；talk_controller 晷/我契约不动、
##     显示回写优先 JSON speaker_en 回退 I18n.t。
## 清档纪律：test_fix_save_normalize 同款四件组备份/还原 + 自愈 + 逐字节自检（EVID 行）；
## 测试档 gesture_input=false + gesture_camera_enabled=false（ensure_camera_open 设置门直接
## false 早退——零 spawn 零摄像头红线）。零摄像头零窗口（纯无头 --script）。

const I18N_GD := "res://scripts/i18n.gd"
const UI_EN_PATH := "res://assets/i18n/ui_en.json"
const CONTENT_EN_PATH := "res://assets/i18n/content_en.json"
const PROJ_GODOT := "res://project.godot"
const SM_PATH := "res://autoload/save_manager.gd"
const SP_PATH := "res://scenes/settings/settings_panel.gd"
const CM_PATH := "res://scenes/settings/camera_menu.gd"
const HUD_PATH := "res://scenes/shared/gesture_hud.gd"
const TALK_PATH := "res://scenes/dialog/talk_controller.gd"

const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"
const TALK_TMP := "user://_af_i18n_talk.json"
const BK_PREFIX := "user://_af_i18n_backup_"
const WATCHED: Array = [SAVE_PATH, FLAG_PATH, TMP_PATH, BAK_PATH]
const AUTOLOAD_NAMES: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]

var _pre_save_text: String = ""

func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _del(p: String) -> void:
	var a: String = _abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _selfheal() -> void:
	var healed: int = 0
	for p: String in WATCHED:
		var bk := BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			_del(p)
			DirAccess.copy_absolute(_abs(bk), _abs(p))
			DirAccess.remove_absolute(_abs(bk))
			healed += 1
	if healed > 0:
		print("EVID|selfheal|af_i18n|restored=%d" % healed)

func _backup_user() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		_pre_save_text = FileAccess.get_file_as_string(SAVE_PATH)
	for p: String in WATCHED:
		if FileAccess.file_exists(p):
			var bk := BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_abs(p), _abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)
			DirAccess.remove_absolute(_abs(p))   # 清域（真实 flag/档隔离——has_any_progress 全空确定性）

func _restore_user() -> void:
	for c: Node in root.get_children():
		if not AUTOLOAD_NAMES.has(String(c.name)):
			c.free()
	for p: String in WATCHED:
		_del(p)
		var bk := BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_abs(bk), _abs(p))
			DirAccess.remove_absolute(_abs(bk))
	_del(TALK_TMP)   # 临时对话档清理（非真实档案域）
	var real_sm: Node = root.get_node_or_null("SaveManager")
	if real_sm != null:
		real_sm.load_game()
	var post: String = FileAccess.get_file_as_string(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|af_i18n|files=%d" % WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

## 写测试档：双关（零 spawn 红线）+ 无 language 键（缺省 zh 判定）。
func _write_test_save() -> void:
	var data: Dictionary = {
		"save_version": 2,
		"progress": {"cleared": [], "next_chapter": 1, "watched_opening": false, "level_progress": {}},
		"settings": {"gesture_input": false, "gesture_camera_enabled": false, "gesture_hud_visible": true},
		"talent": 500,
		"skins": {"owned": ["skin_default"], "equipped": "skin_default"},
	}
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()

func _sync_sm() -> Node:
	var sm: Node = root.get_node_or_null("SaveManager")
	if sm != null:
		sm.load_game()
	return sm

func _i18n() -> Node:
	return root.get_node_or_null("I18n")

func _initialize() -> void:
	print("== test_af_i18n ==")
	_selfheal()
	_backup_user()
	_write_test_save()
	_sync_sm()

	# ===== S 段：结构锚（红态先拿干净 FAIL） =====
	var i18n_src: String = FileAccess.get_file_as_string(I18N_GD) if FileAccess.file_exists(I18N_GD) else ""
	check(i18n_src.contains("func t("), "S1 scripts/i18n.gd 存在且提供 t()")
	check(i18n_src.contains("signal language_changed"), "S2 i18n 提供 language_changed 信号")
	var proj_src: String = FileAccess.get_file_as_string(PROJ_GODOT)
	check(proj_src.contains("I18n=") or proj_src.contains("I18n=\"*"), "S3 project.godot 已注册 I18n autoload")
	check(FileAccess.file_exists(UI_EN_PATH), "S4 assets/i18n/ui_en.json 存在")
	var ui_en: Variant = JSON.parse_string(FileAccess.get_file_as_string(UI_EN_PATH)) if FileAccess.file_exists(UI_EN_PATH) else null
	check(ui_en is Dictionary and (ui_en as Dictionary).has("翻译"), "S5 ui_en.json 含「翻译」表")
	var sm_src: String = FileAccess.get_file_as_string(SM_PATH)
	check(sm_src.contains("\"language\": \"zh\""), "S6 save_manager 默认档含 language=zh")
	check(sm_src.contains("s[\"language\"]"), "S7 save_manager 归一补 language（非法回 zh）")
	var sp_src: String = FileAccess.get_file_as_string(SP_PATH)
	check(sp_src.contains("LanguageOption"), "S8 设置面板存在 LanguageOption")
	check(not sp_src.contains("CAM_OPENING_DOTS.find("), "S9 解耦②：点循环退役 find(text) 文本判据")
	check(sp_src.contains("_cam_opening_dot_idx"), "S9b 解耦②：点循环下标驱动成员在位")
	var cm_src: String = FileAccess.get_file_as_string(CM_PATH)
	check(not cm_src.contains("== \"检测中…\""), "S10 解耦①：camera_menu 退役 text==「检测中…」判定")
	check(cm_src.contains("set_meta(\"i18n_wait\""), "S10b 解耦①：等待行 meta 状态位在位")
	check(cm_src.contains("func _mark_wait_rows_failed"), "S10c 解耦①：超时改写收口可测方法在位")
	var hud_src: String = FileAccess.get_file_as_string(HUD_PATH)
	check(hud_src.contains(", \"left\")") and hud_src.contains(", \"right\")"), "S11 解耦③：_refresh_hand 传逻辑键 left/right")
	var talk_src: String = FileAccess.get_file_as_string(TALK_PATH)
	check(talk_src.contains("speaker_en"), "S12 解耦④：talk_controller 消费 JSON speaker_en")
	check(talk_src.contains("texts_en"), "S12b 解耦④：talk_controller 消费 JSON texts_en（正文英文字段）")

	# ===== A 段：I18n 核心（真实 autoload） =====
	var i18n: Node = _i18n()
	if i18n == null:
		check(false, "A0 I18n autoload 已注册（/root/I18n 可达）")
	else:
		i18n.call("_load_tables")
		i18n.call("set_language", "zh")
		check_eq(String(i18n.call("get_language")), "zh", "A1 get_language 缺省 zh")
		check_eq(String(i18n.call("t", "退出")), "退出", "A2 zh 直通原样返回")
		i18n.call("set_language", "en")
		check_eq(String(i18n.call("t", "退出")), "Exit", "A3 en 命中词条表")
		check_eq(String(i18n.call("t", "锐眼")), "Keen Eye", "A4 术语表：锐眼=Keen Eye")
		var miss := "AF_I18N_缺词测试键"
		check_eq(String(i18n.call("t", miss)), miss, "A5 en 未命中回退中文")
		check(int(i18n.call("get_warned_count")) >= 1, "A6 缺词 push_warning 已发（观测口计数）")
		var before: int = int(i18n.call("get_warned_count"))
		i18n.call("t", miss)
		check_eq(int(i18n.call("get_warned_count")), before, "A7 同键缺词告警只发一次")
		# 双表合并 + content_en 缺文件不炸（并行实施者域，落盘与否都正确）
		var content_exists: bool = FileAccess.file_exists(CONTENT_EN_PATH)
		print("EVID|content_en|exists=%s" % str(content_exists))
		check_eq(String(i18n.call("t", "退出")), "Exit", "A8 content_en %s 时主表仍工作" % ("在场" if content_exists else "缺文件"))
		i18n.call("set_language", "zh")
		check_eq(String(i18n.call("t", "退出")), "退出", "A9 切回 zh 直通恢复")

		# ===== C 段：language 存档 roundtrip（测试档域内） =====
		var sm: Node = _sync_sm()
		check(sm != null, "C0 SaveManager 可达")
		if sm != null:
			sm.call("update_settings", {"language": "en"})
			var sm2: Node = (load(SM_PATH) as GDScript).new()
			sm2.name = "SM_AF_RT"
			root.add_child(sm2)
			sm2.call("load_game")
			check_eq(String((sm2.call("get_settings") as Dictionary).get("language", "")), "en", "C1 language 落盘后新实例读回 en")
			sm2.free()
			# 非法值归一：手写档 language="fr" / null → zh（_safe_bool 同族防御）
			var bad: Dictionary = {"save_version": 2, "settings": {"language": "fr", "gesture_input": false}}
			var fb: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
			fb.store_string(JSON.stringify(bad))
			fb.close()
			var sm3: Node = (load(SM_PATH) as GDScript).new()
			sm3.name = "SM_AF_BAD"
			root.add_child(sm3)
			sm3.call("load_game")
			check_eq(String((sm3.call("get_settings") as Dictionary).get("language", "")), "zh", "C2 非法 language 值归一回 zh")
			sm3.free()
			var bad2: Dictionary = {"save_version": 2, "settings": {"language": null, "gesture_input": false}}
			var fb2: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
			fb2.store_string(JSON.stringify(bad2))
			fb2.close()
			var sm4: Node = (load(SM_PATH) as GDScript).new()
			sm4.name = "SM_AF_NULL"
			root.add_child(sm4)
			sm4.call("load_game")
			check_eq(String((sm4.call("get_settings") as Dictionary).get("language", "")), "zh", "C3 language=null 归一回 zh（不中止）")
			sm4.free()
			_sync_sm()   # 重同步回测试基准档（language 键已无 → zh）

		# ===== D 段：设置面板 Language 行 + 切换生效 + 面板实时重刷 =====
		var panel: Node = (load("res://scenes/settings/settings_panel.tscn") as PackedScene).instantiate()
		add_child(panel)
		await process_frame
		var lo: OptionButton = panel.get_node_or_null("Panel/VBox/OptionsBox/LanguageRow/LanguageOption") as OptionButton
		check(lo != null, "D1 OptionsBox 内 Language 行 OptionButton 在位")
		if lo != null:
			var lang_label: Label = panel.get_node_or_null("Panel/VBox/OptionsBox/LanguageRow/LanguageLabel") as Label
			check(lang_label != null and lang_label.text == "Language", "D2 行标签固定 Language（不翻译）")
			check_eq(lo.item_count, 2, "D3 选项=简体中文/English 两项")
			check_eq(lo.selected, 0, "D4 首次默认 zh（测试档无 language 键）")
			check_eq(String((lo.get_item_text(0))), "简体中文", "D5 第一项=简体中文")
			check_eq(String((lo.get_item_text(1))), "English", "D6 第二项=English")
			lo.select(1)
			lo.emit_signal("item_selected", 1)
			check_eq(String(i18n.call("get_language")), "en", "D7 面板切换 → I18n.set_language 生效")
			check_eq(String((_sync_sm().call("get_settings") as Dictionary).get("language", "")), "en", "D8 切换即写档")
			var hud_toggle: Button = panel.get_node("Panel/VBox/OptionsBox/HudToggle") as Button
			check_eq(String(hud_toggle.text), "Show Gesture HUD", "D9 面板 language_changed 实时重刷（显示手势状态区）")
			var cat_entry: Button = panel.get_node("Panel/VBox/EntryBox/CatalogEntry") as Button
			check_eq(String(cat_entry.text), "Catalog", "D10 面板重刷（图鉴→Catalog）")

			# ===== E 段：抽样 10 条 en 词条 + 主菜单/HUD 实时刷新（信号驱动） =====
			var samples: Dictionary = {
				"退出": "Exit",
				"开始游戏": "Start Game",
				"手势说明": "Gesture Guide",
				"图鉴": "Catalog",
				"衣橱": "Wardrobe",
				"完美": "Perfect",
				"下一关": "Next Level",
				"确认": "Confirm",
				"跳过剧情": "Skip Story",
				"未完待续": "To be continued",
			}
			var hit: int = 0
			for k: String in samples.keys():
				if String(i18n.call("t", k)) == String(samples[k]):
					hit += 1
				else:
					print("[FAIL] E 词条抽查：%s → 期望 %s 实际 %s" % [k, String(samples[k]), String(i18n.call("t", k))])
			check_eq(hit, samples.size(), "E1 词条抽样 %d 条全命中" % samples.size())
			# 带参格式化键
			check_eq(String(i18n.call("t", "天赋值：%d")) % 500, "Talent: 500", "E2 格式化键：天赋值：%d")
			check_eq(String(i18n.call("t", "剩余体素：%d / %d")) % [3, 10], "Voxels left: 3 / 10", "E3 格式化键：剩余体素")
			check_eq(String(i18n.call("t", "还需翻转 %d 次")) % 2, "2 more flips to go", "E4 格式化键：还需翻转 %d 次")
			# 主菜单实时刷新（信号驱动，不手动调 _update_buttons）
			var mm: Node = (load("res://scenes/menu/main_menu.tscn") as PackedScene).instantiate()
			add_child(mm)
			await process_frame
			var start_btn: Button = mm.get_node("LeftPanel/StartButton") as Button
			var quit_btn: Button = mm.get_node("LeftPanel/QuitButton") as Button
			check_eq(String(start_btn.text), "Start Game", "E5 主菜单 en 挂载即英文（无档态开始游戏）")
			check_eq(String(quit_btn.text), "Exit", "E6 主菜单退出钮英文（tscn 静态覆写）")
			i18n.call("set_language", "zh")
			check_eq(String(start_btn.text), "开始游戏", "E7 主菜单实时刷回中文（信号驱动）")
			i18n.call("set_language", "en")
			check_eq(String(start_btn.text), "Start Game", "E8 主菜单实时刷回英文（信号驱动）")
			# HUD 行组实时刷新
			var hud: Node = (load("res://scenes/shared/gesture_hud.tscn") as PackedScene).instantiate()
			add_child(hud)
			await process_frame
			var guide_list: Node = hud.get_node("GuidePanel/GuideVBox/GuideList")
			var first_row: Label = (guide_list.get_child(0) as Label)
			# MAIN_MENU 行组首行=ROW_HANDS（全局四行组序）；行文案 en=词条表直查。
			check(String(first_row.text).begins_with("L/R hand status"), "E9 HUD 行组 en（信号驱动重刷首行=ROW_HANDS）")
			var fold_title: Label = hud.get_node_or_null("FoldTitle") as Label
			check_eq(String(fold_title.text) if fold_title != null else "", "Gesture Guide", "E10 HUD 折叠标题 en")
			i18n.call("set_language", "zh")
			check(String((guide_list.get_child(0) as Label).text).begins_with("左/右手状态"), "E11 HUD 行组实时刷回中文")
			i18n.call("set_language", "en")

			# ===== G 段：解耦运行时（点循环下标驱动 + camera_menu meta 改写） =====
			var panel2: Node = panel
			panel2.set("_cam_opening", true)
			panel2.set("_cam_opening_dot_idx", 0)
			(lo.get_parent().get_parent().get_node("CameraRow/CameraToggle") as Button).text = String(i18n.call("t", "摄像头正在加载中..."))
			panel2.call("_process", 0.5)
			var cam_btn: Button = panel2.get_node("Panel/VBox/OptionsBox/CameraRow/CameraToggle") as Button
			check_eq(String(cam_btn.text), String(i18n.call("t", "摄像头正在加载中..")), "G1 点循环下标推进（en 文案随表）")
			panel2.set("_cam_opening", false)
			# camera_menu：meta 状态位改写（不依赖按钮文本）
			var cm: Node = (load(CM_PATH) as GDScript).new()
			cm.name = "CM_AF"
			var box: VBoxContainer = VBoxContainer.new()
			cm.add_child(box)
			var wait_btn: Button = Button.new()
			wait_btn.text = String(i18n.call("t", "检测中…"))
			wait_btn.set_meta("i18n_wait", true)
			box.add_child(wait_btn)
			var norm_btn: Button = Button.new()
			norm_btn.text = "640x480"
			box.add_child(norm_btn)
			cm.call("_mark_wait_rows_failed", box)
			check_eq(String(wait_btn.text), String(i18n.call("t", "检测失败（设备无法打开）")), "G2 等待行超时改写（meta 判定）")
			check(wait_btn.disabled, "G3 等待行超时置灰")
			check_eq(String(norm_btn.text), "640x480", "G4 非等待行不受扰")
			cm.free()

			# ===== F 段：talk speaker_en/texts_en 回退（临时档在 user://） =====
			var talk_doc: Dictionary = {"_说明": ["AF 临时测试档"], "rounds": [
				{"speaker": "晷", "speaker_en": "Gui", "texts": ["你好"], "texts_en": ["Hello"]},
				{"speaker": "我", "texts": ["嗯"]},
			]}
			var ft: FileAccess = FileAccess.open(TALK_TMP, FileAccess.WRITE)
			ft.store_string(JSON.stringify(talk_doc))
			ft.close()
			var tc: Node = (load("res://scenes/dialog/talk_scene.tscn") as PackedScene).instantiate()
			add_child(tc)
			await process_frame
			tc.call("load_dialog", TALK_TMP)
			var lines: Array = tc.get("_lines")
			check(lines.size() == 2, "F1 临时对话档解析 2 句")
			if lines.size() == 2:
				var l0: Dictionary = lines[0]
				var l1: Dictionary = lines[1]
				check_eq(String(l0.get("speaker_en", "")), "Gui", "F2 轮级 speaker_en 带入播放清单")
				check_eq(String(l0.get("text_en", "")), "Hello", "F3 轮级 texts_en 带入播放清单")
				check_eq(String(l1.get("speaker_en", "")), "", "F4 未落英文字段=空串（回退通道）")
				# en 态显示回写：可见名牌优先 speaker_en，另一名牌回退 I18n.t
				tc.call("_show_line", 0)
				check_eq(String((tc.get_node("NameTagLeft/NameLabel") as Label).text), "Gui", "F5 en+speaker_en：左名牌=Gui")
				check_eq(String((tc.get_node("NameTagRight/NameLabel") as Label).text), "Me", "F6 en 无字段：右名牌回退 t(我)=Me")
				tc.call("_show_line", 1)
				check_eq(String((tc.get_node("NameTagRight/NameLabel") as Label).text), "Me", "F7 第2轮 speaker=我 无字段：右名牌回退 Me")
				# F8：第 2 轮（speaker=我，无 speaker_en）左名牌回退 t(晷)=Gui——speaker_en 只作用于归属名牌
				check_eq(String((tc.get_node("NameTagLeft/NameLabel") as Label).text), "Gui", "F8 左名牌回退 t(晷)=Gui")
				# zh 态：t 直通原样（契约常量不动）
				i18n.call("set_language", "zh")
				tc.call("_show_line", 0)
				check_eq(String((tc.get_node("NameTagLeft/NameLabel") as Label).text), "晷", "F9 zh：左名牌原样「晷」")
				i18n.call("set_language", "en")
			tc.free()

			# 收口：语言回 zh（还原段读 zh 基准）
			i18n.call("set_language", "zh")
			await process_frame

	finish()   # 内部唯一一次 _restore_user（勿在 _initialize 再调——双跑会删真档且无备份可还原）
