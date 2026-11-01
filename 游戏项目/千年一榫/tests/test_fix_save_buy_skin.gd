extends "res://tests/test_base.gd"
## 修复批（存档与系统域）P3：buy_skin 两阶段落盘——TDD 红测先行。
## 病灶（独立审查确认）：save_manager.buy_skin（:608-626）先 spend_talent（内部 save_game
## 落盘①）再 owned.append 后 save_game（落盘②）——两阶段落盘，中间崩溃=扣 205 无货。
## 修法：合并为一次内存变更 + 一次 save_game（spend_talent 本体与余额不足分支语义不变）。
## 判定口径：
##   载入基线零落盘；购买成功路径 save_game **恰一次**（spy 计数——红态=2）；
##   购买后内存/磁盘原子一致（talent−205 与 owned 同档可见）；
##   余额不足/重复购买/原创禁购 → 拒绝且零新增落盘、不扣费；
##   talent_changed/skin_changed 各恰发一次（合并后信号语义不丢）；
##   spend_talent 语义不变（成功 +1 落盘、余额不足 false 零落盘）。
## 清档纪律：test_w_save_resilience 同款四件组备份/还原 + 真实 autoload 重同步 +
##   逐字节等价自检（EVID 行）。零摄像头零窗口（纯无头 --script）。

const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"
const COUNTER_PATH := "res://tests/fixtures/fix_save_counter.gd"
const BK_PREFIX := "user://_fixs_buy_backup_"
const WATCHED: Array = [SAVE_PATH, FLAG_PATH, TMP_PATH, BAK_PATH]
const AUTOLOAD_NAMES: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
const SKIN_PRICE := 205

var _pre_save_text: String = ""

func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

func _del(p: String) -> void:
	var a: String = _abs(p)
	if FileAccess.file_exists(a):
		DirAccess.remove_absolute(a)

func _write_file(p: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _read_file(p: String) -> String:
	return FileAccess.get_file_as_string(p)

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
		print("EVID|selfheal|fixs_buy|restored=%d" % healed)

func _backup_user() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		_pre_save_text = _read_file(SAVE_PATH)
	for p: String in WATCHED:
		if FileAccess.file_exists(p):
			var bk := BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_abs(p), _abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

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
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()
	var post: String = _read_file(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|fixs_buy|files=%d" % WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _full_v2(talent: int) -> Dictionary:
	return {
		"save_version": 2,
		"progress": {"cleared": [], "next_chapter": 1, "watched_opening": false, "level_progress": {}},
		"settings": {"gesture_input": true, "kb_input": true, "gesture_hud_visible": true,
			"gesture_hud_offset": [0, 0], "volume": {"master": 1.0, "music": 1.0, "sfx": 1.0},
			"gesture_camera_enabled": true, "gesture_panel_folded": false,
			"gesture_camera_device": "", "gesture_camera_res": "", "gesture_camera_fps": 0,
			"udp_port": 0},
		"talent": talent,
		"skins": {"owned": ["skin_default", "skin_origin_kaitou"],
			"equipped": "skin_origin_kaitou", "preferred": "skin_origin_kaitou"},
		"replay_award_counts": {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0},
	}

func _initialize() -> void:
	print("== test_fix_save_buy_skin ==")
	_selfheal()
	_backup_user()
	for p: String in WATCHED:
		_del(p)

	# 载入基线（干净 v2，talent 500）→ spy 计数从 0 起
	_write_file(SAVE_PATH, JSON.stringify(_full_v2(500)))
	var sm: Node = (load(COUNTER_PATH) as GDScript).new()
	sm.name = "SM_FIXS_BUY"
	get_root().add_child(sm)
	sm.load_game()
	sm.call("setup_probe")
	check_eq(int(sm.get("save_calls")), 0, "前置：载入路径零落盘（无 .bak 回退）")
	check_eq(sm.get_talent(), 500, "前置：基线 500")

	# ===== 1 购买成功：恰一次落盘（红态=2，两阶段病灶）+ 磁盘原子一致 =====
	check_eq(bool(sm.buy_skin("skin_01")), true, "1a 购买 skin_01 成功（500>=205）")
	check_eq(int(sm.get("save_calls")), 1, "P3 核心：购买成功路径 save_game 恰一次（红=2 两阶段）")
	check_eq(sm.get_talent(), 500 - SKIN_PRICE, "1b 扣费正确（295）")
	check((sm.get_skins()["owned"] as Array).has("skin_01"), "1c owned 含 skin_01")
	check_eq(int(sm.get("talent_emits")), 1, "1d talent_changed 恰发一次（合并后信号不丢）")
	check_eq(int(sm.get("skin_emits")), 1, "1e skin_changed 恰发一次")
	var disk: Variant = JSON.parse_string(_read_file(SAVE_PATH))
	check(typeof(disk) == TYPE_DICTIONARY, "1f 磁盘档可解析")
	if typeof(disk) == TYPE_DICTIONARY:
		check_eq(int((disk as Dictionary).get("talent", -1)), 500 - SKIN_PRICE, "1g 磁盘 talent 与内存一致（原子）")
		var disk_owned: Variant = (disk as Dictionary).get("skins", {}).get("owned", [])
		check(disk_owned is Array and (disk_owned as Array).has("skin_01"), "1h 磁盘 owned 与内存一致（原子——扣费与发货同档）")

	# ===== 2 余额不足：拒绝 + 不扣费 + 零新增落盘（spend_talent 分支语义不变） =====
	var d: Dictionary = sm.get("_data")
	d["talent"] = 100
	var before2: int = int(sm.get("save_calls"))
	check_eq(bool(sm.buy_skin("skin_02")), false, "2a 余额不足(100<205)拒绝购买")
	check_eq(sm.get_talent(), 100, "2b 余额不足不扣费")
	check_eq(int(sm.get("save_calls")), before2, "2c 余额不足零新增落盘")
	check(not (sm.get_skins()["owned"] as Array).has("skin_02"), "2d 未发货")

	# ===== 3 重复购买：拒绝零落盘 =====
	d["talent"] = 500
	var before3: int = int(sm.get("save_calls"))
	check_eq(bool(sm.buy_skin("skin_01")), false, "3a 重复购买被阻止")
	check_eq(int(sm.get("save_calls")), before3, "3b 重复购买零落盘")

	# ===== 4 原创禁购：拒绝零落盘不扣费 =====
	var before4: int = int(sm.get("save_calls"))
	check_eq(bool(sm.buy_skin("skin_origin_song")), false, "4a 原创皮肤禁购（API 级）")
	check_eq(int(sm.get("save_calls")), before4, "4b 禁购零落盘")
	check_eq(sm.get_talent(), 500, "4c 禁购不扣费")

	# ===== 5 spend_talent 语义不变（本修复不触碰其两分支行为） =====
	check_eq(bool(sm.spend_talent(50)), true, "5a spend_talent 成功 true")
	check_eq(sm.get_talent(), 450, "5b 扣 50 后 450")
	check_eq(int(sm.get("save_calls")), before4 + 1, "5c spend_talent 成功恰 +1 落盘")
	check_eq(bool(sm.spend_talent(99999)), false, "5d spend_talent 余额不足 false")
	check_eq(int(sm.get("save_calls")), before4 + 1, "5e spend_talent 余额不足零落盘（语义不变）")

	finish()
