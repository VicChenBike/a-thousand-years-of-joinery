extends "res://tests/test_base.gd"

const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"

func _cleanup() -> void:
	var save_abs: String = ProjectSettings.globalize_path(SAVE_PATH)
	var flag_abs: String = ProjectSettings.globalize_path(FLAG_PATH)
	if FileAccess.file_exists(save_abs):
		DirAccess.remove_absolute(save_abs)
	if FileAccess.file_exists(flag_abs):
		DirAccess.remove_absolute(flag_abs)

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
const DISC_BK_PREFIX := "user://_r2b_svm_backup_"
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
	print("EVID|user_restore|svm|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_save_manager ==")
	_backup_user()
	_cleanup()
	var sm: Node = load("res://autoload/save_manager.gd").new()
	get_root().add_child(sm)
	sm.name = "SaveManager"
	sm.load_game()

	# 1 默认值（A7/J1-4：初始天赋值 0→500）
	check_eq(sm.get_talent(), 500, "初始天赋值为 500")
	check_eq(sm.get_skins()["equipped"], "skin_origin_kaitou", "K-D：初始穿戴「开头」原创皮肤")
	check(sm.is_first_launch(), "无标记文件时为首次进入")

	# 2 首次标记
	sm.mark_first_launch()
	check(FileAccess.file_exists(FLAG_PATH), "标记文件已创建")
	check(not sm.is_first_launch(), "有标记文件后为非首次")

	# 3 货币（J1-4：默认 500 后先归零，保「加500→扣205→295」绝对值链最小改动法）
	sm.spend_talent(sm.get_talent())
	sm.add_talent(500)
	check_eq(sm.get_talent(), 500, "加 500 天赋值")
	check(sm.spend_talent(205), "扣 205 成功")
	check_eq(sm.get_talent(), 295, "扣后余额 295")
	check(not sm.spend_talent(296), "余额不足时扣费失败")
	check_eq(sm.get_talent(), 295, "失败时不扣费")

	# 4 皮肤购买/穿戴（余额推演：500→扣205=295→买 skin_a 扣205=90）
	check(sm.buy_skin("skin_a"), "购买 skin_a 成功（295>=205）")
	check(not sm.buy_skin("skin_a"), "重复购买被阻止")
	check(not sm.buy_skin("skin_b"), "余额不足(90<205)购买 skin_b 被阻止")
	check(not sm.equip_skin("skin_b"), "穿戴未拥有皮肤被阻止")
	check(sm.equip_skin("skin_a"), "穿戴已拥有皮肤成功")
	check_eq(sm.get_skins()["equipped"], "skin_a", "穿戴已更新")

	# 5 重玩计数：每关独立，前 3 次发，第 4 次起不发
	check(sm.consume_replay_award(1), "第1关重玩第1次发放")
	check(sm.consume_replay_award(1), "第1关重玩第2次发放")
	check(sm.consume_replay_award(1), "第1关重玩第3次发放")
	check(not sm.consume_replay_award(1), "第1关重玩第4次不再发放")
	check(sm.consume_replay_award(2), "第2关计数独立，第1次发放")

	# 6 进度推进
	sm.advance_progress(1)
	var p: Dictionary = sm.get_progress()
	check(p["cleared"].has(1), "通关列表含第1关")
	check_eq(p["next_chapter"], 2, "下一章为 2")
	sm.advance_progress(5)
	check_eq(sm.get_progress()["next_chapter"], 6, "第5关后 next_chapter=6（终点标记）")

	# 7 round-trip
	sm.save_game()
	var sm2: Node = load("res://autoload/save_manager.gd").new()
	get_root().add_child(sm2)
	sm2.name = "SaveManager2"
	sm2.load_game()
	check_eq(sm2.get_skins()["equipped"], "skin_a", "读出穿戴一致")
	check_eq(sm2.get_progress()["cleared"], [1, 5], "读出进度一致")
	check(not sm2.consume_replay_award(1), "读出重玩计数一致（第4次不发）")

	# 8 损坏存档重置
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	f.store_string("{ 损坏的json !!!")
	f.close()
	var sm3: Node = load("res://autoload/save_manager.gd").new()
	get_root().add_child(sm3)
	sm3.name = "SaveManager3"
	sm3.load_game()
	check_eq(sm3.get_talent(), 500, "损坏存档重置为默认（含初始天赋 500）")

	# 9 J3-2 新游戏清档：reset_for_new_game()（重置默认〔含天赋 500〕+ 删 first_launch 标记 + 落盘）
	check(not sm.is_first_launch(), "J3-2 前置：清档前标记存在（非首次）")
	sm.add_talent(1000)  # 弄脏天赋数据（当前 90→1090，明显非默认）
	sm.save_game()
	check(sm.get_talent() != 500, "J3-2 前置：清档前存档数据为脏")
	sm.reset_for_new_game()
	check_eq(sm.get_talent(), 500, "J3-2：清档后天赋回默认 500")
	check_eq(int(sm.get_progress()["next_chapter"]), 1, "J3-2：清档后 next_chapter=1")
	check((sm.get_progress()["cleared"] as Array).is_empty(), "J3-2：清档后通关列表为空")
	check_eq(sm.get_skins()["equipped"], "skin_origin_kaitou", "J3-2/K-D：清档后皮肤回默认（穿戴开头原创）")
	check(sm.is_first_launch(), "J3-2：清档后 first_launch 标记已删（重新走开场动画）")
	var sm4: Node = load("res://autoload/save_manager.gd").new()
	get_root().add_child(sm4)
	sm4.name = "SaveManager4"
	sm4.load_game()
	check_eq(sm4.get_talent(), 500, "J3-2：清档落盘生效（重载后天赋=500）")
	check_eq(int(sm4.get_progress()["next_chapter"]), 1, "J3-2：清档落盘生效（重载后 next_chapter=1）")

	# ---- 10. K-D（K3-5）旧档迁移 + 原创解锁/穿戴 API（spec §7.3/§7.4）----
	# a) 旧档（save_version=1、skins 无 preferred）迁移：先 equipped 有效性回退，再 preferred=equipped；owned 补开头原创
	var legacy: Dictionary = {
		"save_version": 1,
		"progress": {"cleared": [1], "next_chapter": 2},
		"settings": {"gesture_input": true, "kb_input": true, "gesture_hud_visible": true, "gesture_hud_offset": [0, 0], "volume": {"master": 1.0, "music": 1.0, "sfx": 1.0}, "udp_port": 0},
		"talent": 320,
		"skins": {"owned": ["skin_default", "skin_07"], "equipped": "skin_07"},
		"replay_award_counts": {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0},
	}
	var lf: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	lf.store_string(JSON.stringify(legacy))
	lf.close()
	var smx: Node = load("res://autoload/save_manager.gd").new()
	get_root().add_child(smx)
	smx.name = "SaveManagerKD"
	smx.load_game()
	check_eq(smx.get_skins()["preferred"], "skin_07", "K-D a：旧档无 preferred → 迁移=equipped")
	check_eq(smx.get_skins()["equipped"], "skin_07", "K-D a：旧档 equipped 无损保留（owned 含 skin_07）")
	check((smx.get_skins()["owned"] as Array).has("skin_origin_kaitou"), "K-D a：旧档 owned 自动补入开头原创（幂等）")
	check_eq(smx.get_talent(), 320, "K-D a：旧档天赋 320 保留")
	# b) 全新档（reset+load）：默认穿戴并自选「开头」
	smx.reset_for_new_game()
	smx.load_game()
	check_eq(smx.get_skins()["preferred"], "skin_origin_kaitou", "K-D b：全新档 preferred=开头")
	check_eq(smx.get_skins()["equipped"], "skin_origin_kaitou", "K-D b：全新档 equipped=开头")
	check((smx.get_skins()["owned"] as Array).has("skin_origin_kaitou"), "K-D b：全新档 owned 含开头")
	# c) 解锁第 3 章→主动穿戴元：set_preferred 同步 equipped/preferred
	smx.unlock_origin_skin(3)
	check(smx.set_preferred_skin("skin_origin_yuan"), "K-D c：解锁后 set_preferred(元) 成功")
	check_eq(smx.get_skins()["equipped"], "skin_origin_yuan", "K-D c：set_preferred→equipped=元")
	check_eq(smx.get_skins()["preferred"], "skin_origin_yuan", "K-D c：set_preferred→preferred=元")
	# d) 设回默认自选→解锁 4→apply(4) 穿戴明（不动 preferred）；apply(5) 未解锁→跳过（防御）
	smx.set_preferred_skin("skin_default")
	smx.unlock_origin_skin(4)
	smx.apply_contextual_skin(4)
	check_eq(smx.get_skins()["equipped"], "skin_origin_ming", "K-D d：apply_contextual(4)→equipped=明")
	check_eq(smx.get_skins()["preferred"], "skin_default", "K-D d：apply_contextual 不动 preferred")
	smx.apply_contextual_skin(5)
	check_eq(smx.get_skins()["equipped"], "skin_origin_ming", "K-D d：apply_contextual 未解锁跳过（equipped 不变）")
	# e) 关卡结束换回自选
	smx.restore_preferred_skin()
	check_eq(smx.get_skins()["equipped"], "skin_default", "K-D e：restore_preferred→equipped=preferred")
	# f) equip_skin 内部重定向 set_preferred → preferred==equipped
	check(smx.equip_skin("skin_origin_ming"), "K-D f：equip_skin(已拥有原创) 成功")
	check_eq(smx.get_skins()["preferred"], "skin_origin_ming", "K-D f：equip_skin 重定向→preferred==equipped")
	# g) 解锁点位②：advance_progress 兜底解锁该章原创（幂等）
	smx.reset_for_new_game()
	smx.load_game()
	smx.advance_progress(2)
	check((smx.get_skins()["owned"] as Array).has("skin_origin_song"), "K-D g：advance_progress(2) 解锁宋原创入 owned")
	smx.advance_progress(2)
	var song_cnt: int = 0
	for o: Variant in (smx.get_skins()["owned"] as Array):
		if String(o) == "skin_origin_song":
			song_cnt += 1
	check_eq(song_cnt, 1, "K-D g：解锁幂等，不重复入 owned")
	# h) 未拥有穿戴拒绝
	check(not smx.set_preferred_skin("skin_99"), "K-D h：set_preferred 未拥有返回 false")
	# i) 纵深防御：原创皮肤不可经 buy_skin 购买（即便天赋充足、未拥有）
	check(not smx.buy_skin("skin_origin_song"), "K-D P3：buy_skin 对原创 id 直接拒绝（API 级禁购）")

	_cleanup()
	finish()
