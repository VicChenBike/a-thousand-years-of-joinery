extends "res://tests/test_base.gd"
## 批次 Z Z3（spec §3 验收验收①②③④ + §14 验收②③⑤）：**生产默认装载链红测（不注入任何夹具）**——
## 本域核心交付。锁两条生产链的默认真值：
##   A. 气泡默认链：level_scene._ready → _load_witness_lines(BubbleBag.path_for_chapter(_chapter))
##      → res://剧情对话/气泡_第N关.json（Y-C8 洗牌袋）；
##   B. 对话默认链：talk_controller.set_context({"mode":"after_level","chapter":n})
##      → CHAPTER_DOCS → res://剧情对话/第N关.json（批次 Z §14 起 opening 语境归一同此口径）。
## 断言①：level_scene(set_context chapter=1) 默认链池==气泡_第1关.json **12 条逐字**；
##        经生产 _show_witness_bubble 连续 12 次抽取（洗牌袋整轮）**零重复**且每次真弹出。
## 断言②：talk_controller 默认链加载 第1关.json——拍平 **51 句**、speaker∈{晷,我}、
##        逐句**点击**（_gui_input 真实输入路径）推进：索引 0..50 严格递增无跳句、末句显示
##        逐字、_finish → LEVEL{chapter:1}（51 句全播、推进次数口径不变）。
## 断言③：第 2~5 关每关默认链加载对应文件、rounds 非空、四关文本**实质句零交集**（批次 AF：
##        现行正式文案第 2∩4 关存在 1 句纯标点交集「？？？」——判据改为交集⊆已知纯标点句集合，
##        已知交集句单列锁定）、"_说明" 零「占位待替换」（全 5 关正式文案入库，AF 反向锁）；
##        气泡默认路径（path_for_chapter）2~5 关同样逐字可用。
## 断言④：第 1 关对话首句逐字==「等——这是哪儿？刚才还站着，一眨眼，满天是光。」（speaker=我）。
## 断言⑤（§14②）：res://剧情对话/开场.json **已删除**。
## 批次 AF（2026-11-01）断言同步：全 5 关正式文案+英文字段（speaker_en/texts_en/lines_en）入库
## ——生产显示链按 I18n 语言消费英文字段（talk_controller._line_text/_speaker_name：en 优先
## texts_en/speaker_en，zh 恒中文），故显示链断言前**语言钉扎 zh**（I18n._ready 读用户档
## settings.language，用户档 language=en 时显示英文——红态实测末句为英文 texts_en）；钉扎后
## 新增 en 显示链断言（拍平数据层恒中文、显示层取 texts_en、名牌取 speaker_en）+ 英文字段护栏
## （配对/等长）。
## 无头纪律：add_child 后 await process_frame 再驱动；level_scene _exit_tree
## 写挖除断点 → user:// 备份还原（独立前缀 zdlp，规范六条）；本文件不 attach Game 容器
## （_scene_container=null → goto_state 只切状态机、零场景加载，见 game.gd:102）。

const LEVEL_SCENE := "res://scenes/level/level_scene.tscn"
const TALK_SCENE := "res://scenes/dialog/talk_scene.tscn"
const BubbleBag := preload("res://scripts/bubble_lines_bag.gd")
const DOC_DIR := "res://剧情对话/"

const D1_FIRST := "等——这是哪儿？刚才还站着，一眨眼，满天是光。"
const D1_LAST := "……到了。小心，几千年前的泥，可不好擦。"
const D1_SENTS := 51
const D1_BUBBLES := 12
# 批次 AF（2026-11-01）：第 1 关末句英译逐字锚点（texts_en 末元素，em-dash U+2014 逐字节核验）
const D1_LAST_EN := "...We're here. Mind yourself—mud from a few thousand years past does not wipe off easily."
const SP_EN_GUI := "Gui"
const SP_EN_ME := "I"
# 批次 AC 4A（2026-09-27）：第 2 关正式文案锚点（用户提供，铁律 8；机械解析自查 18 轮 51 句）
const D2_ROUNDS := 18
const D2_SENTS := 51
const ST_LEVEL := 4
const LEGAL_SPEAKERS: Array = ["晷", "我"]

# ===== 清档纪律（tools/README_走查清档规范.md；level_scene 实例 _exit_tree 写检查点）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_zdlp_backup_"
const DISC_WATCHED: Array = [DISC_SAVE_PATH, DISC_FLAG_PATH, DISC_TMP_PATH, DISC_BAK_PATH]
const DISC_AUTOLOADS: Array = ["MCPRuntime", "SaveManager", "AudioManager", "ThemeManager",
	"GestureBridge", "LevelLibrary", "Game", "GestureRouter", "I18n"]
var _pre_save_text: String = ""
var _pre_lang: String = "zh"  # AF：语言钉扎前实测值（finish 还原；进程级状态）

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
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	# 规范第 6 条：先同步 free 测试挂载节点（level._exit_tree 兜底写档先落测试域磁盘）
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
	print("EVID|user_restore|zdlp|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	# AF：语言钉扎还原（收工还原实测前值；进程级内存状态，逐字节存档还原由 _restore_user 承担）
	var i18n_end: Node = root.get_node_or_null(NodePath("I18n"))
	if i18n_end != null:
		i18n_end.call("set_language", _pre_lang)
	_restore_user()
	super.finish()

func _load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed

func _mk_click() -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	return ev

func _new_level(chapter: int) -> Node:
	var lv: Node = (load(LEVEL_SCENE) as PackedScene).instantiate()
	lv.call("set_context", {"chapter": chapter})
	add_child(lv)
	await process_frame
	await process_frame
	return lv

func _new_talk(ctx: Dictionary) -> Node:
	var t: Node = (load(TALK_SCENE) as PackedScene).instantiate()
	t.call("set_context", ctx)
	add_child(t)
	await process_frame
	await process_frame
	return t

func _initialize() -> void:
	print("== test_z_dialog_production_chain ==")
	_backup_user()
	var game: Node = root.get_node("Game")
	var lib: Node = root.get_node("LevelLibrary")
	lib.call("scan_directory")

	# ---- 断言⑤（§14②）：开场对话文档整份删除 ----
	check(not FileAccess.file_exists(DOC_DIR + "开场.json"),
		"⑤§14②：剧情对话/开场.json 已删除（不在库）")

	# ---- 断言④：第 1 关对话首句逐字（生产文件，非夹具）----
	var d1_raw: Variant = _load_json(DOC_DIR + "第1关.json")
	check(d1_raw is Dictionary, "④：第1关.json 生产文件可解析")
	if d1_raw is Dictionary and (d1_raw as Dictionary).get("rounds") is Array:
		var r1: Array = (d1_raw as Dictionary).get("rounds")
		check(r1.size() > 0 and (r1[0] as Dictionary).get("texts") is Array \
			and ((r1[0] as Dictionary)["texts"] as Array).size() > 0,
			"④：首轮 texts 非空")
		if r1.size() > 0 and (r1[0] as Dictionary).get("texts") is Array \
				and ((r1[0] as Dictionary)["texts"] as Array).size() > 0:
			check_eq(String(((r1[0] as Dictionary)["texts"] as Array)[0]), D1_FIRST,
				"④：对话首句逐字==「等——这是哪儿？刚才还站着，一眨眼，满天是光。」")
			check_eq(String((r1[0] as Dictionary).get("speaker", "")), "我", "④：首句 speaker=我")
		# AF：第 1 关英文字段护栏（speaker_en 配对 + texts_en 逐轮等长全字符串 + 末句英译锚点）
		var pair1 := true
		var enlen1 := true
		var enstr1 := true
		for r1af: Variant in r1:
			if not (r1af is Dictionary):
				continue
			var rd1: Dictionary = r1af as Dictionary
			var sp1 := String(rd1.get("speaker", ""))
			var spe1 := String(rd1.get("speaker_en", ""))
			if not ((sp1 == "晷" and spe1 == SP_EN_GUI) or (sp1 == "我" and spe1 == SP_EN_ME)):
				pair1 = false
			var tv1: Variant = rd1.get("texts", [])
			var ev1: Variant = rd1.get("texts_en", [])
			if not (tv1 is Array and ev1 is Array and (ev1 as Array).size() == (tv1 as Array).size()):
				enlen1 = false
			else:
				for es1: Variant in (ev1 as Array):
					if not (es1 is String):
						enstr1 = false
		check(pair1, "④：第1关 全轮 speaker/speaker_en 合法配对（晷↔Gui、我↔I，AF 护栏）")
		check(enlen1, "④：第1关 全轮 texts_en 与 texts 逐轮等长（AF 护栏）")
		check(enstr1, "④：第1关 texts_en 全为字符串（AF 护栏）")
		if r1.size() > 0:
			var te1z: Variant = (r1[r1.size() - 1] as Dictionary).get("texts_en", [])
			check(te1z is Array and (te1z as Array).size() >= 1 \
					and String((te1z as Array)[(te1z as Array).size() - 1]) == D1_LAST_EN,
				"④：第1关 末句 texts_en 逐字锚点（AF）")
		# AF：气泡_第1关 lines_en 护栏（与 lines 逐条等长）
		var b1en: Variant = _load_json(DOC_DIR + "气泡_第1关.json")
		var bl1: Array = (b1en as Dictionary).get("lines", []) if b1en is Dictionary else []
		var le1: Variant = (b1en as Dictionary).get("lines_en", []) if b1en is Dictionary else []
		check(le1 is Array and (le1 as Array).size() == bl1.size() and bl1.size() > 0,
			"④：气泡_第1关 lines_en 与 lines 逐条等长（%d 条，AF 护栏）" % bl1.size())

	# ==================== AF：显示链语言钉扎（确定性基线） ====================
	# 生产显示链现按 I18n 语言消费英文字段（talk_controller._line_text/_speaker_name：en 优先
	# texts_en/speaker_en；zh 恒中文）。I18n._ready 于树激活时读存档 settings.language——用户档
	# 可能带入 "en"（红态实测：② 末句显示英文 texts_en）。本件默认链基线断言以 zh（缺省语言）
	# 为锚：等一帧让 autoload _ready 完成（坑⑥），显式钉 zh；收工 finish() 还原实测前值。
	await process_frame
	var i18n: Node = root.get_node("I18n")
	_pre_lang = String(i18n.call("get_language"))
	i18n.call("set_language", "zh")
	check_eq(String(i18n.call("get_language")), "zh", "AF：显示链语言钉扎 zh（钉前实测=%s；用户档 language=en 即红态同源）" % _pre_lang)

	# ==================== 断言①：level_scene 默认气泡链（chapter=1，零夹具） ====================
	var lv: Node = await _new_level(1)
	# 源码级默认链锁：_ready 消费的就是 path_for_chapter 生产表达式（无注入、无重定向）
	var ls_src: String = FileAccess.get_file_as_string("res://scenes/level/level_scene.gd")
	check(ls_src.contains("_load_witness_lines(BubbleBag.path_for_chapter(_chapter))"),
		"①：level_scene 默认链=_load_witness_lines(BubbleBag.path_for_chapter(_chapter))（源码锁，零夹具注入点改写）")
	var b1_raw: Variant = _load_json(DOC_DIR + "气泡_第1关.json")
	check(b1_raw is Dictionary and (b1_raw as Dictionary).get("lines") is Array, "①：气泡_第1关.json 生产文件可解析")
	var file_lines: Array = (b1_raw as Dictionary).get("lines", []) if b1_raw is Dictionary else []
	var pool: Array = lv.call("get_witness_lines_pool")
	check_eq(pool.size(), D1_BUBBLES, "①：默认链池==12 条（实测 %d）" % pool.size())
	var pool_word_ok: bool = pool.size() == file_lines.size()
	for i: int in range(mini(pool.size(), file_lines.size())):
		if String(pool[i]) != String(file_lines[i]):
			pool_word_ok = false
	check(pool_word_ok, "①：池与 气泡_第1关.json 逐字逐位一致（12 条零改写）")
	# 连续 12 次抽取（经生产弹出入口 _show_witness_bubble 读回）零重复 + 每次真弹出
	var drawn: Array = []
	var popped_ok := true
	for k: int in range(D1_BUBBLES):
		lv.call("_show_witness_bubble")
		var lb: Variant = lv.get("witness_bubble")
		if lb == null or not bool((lb as Node).get("visible")) or String((lb as Label).text) == "":
			popped_ok = false
			drawn.append("<未弹出>")
		else:
			drawn.append(String((lb as Label).text))
	check(popped_ok, "①：连续 12 次抽取每次均真弹出（visible+非空文本）")
	var drawn_uniq: Dictionary = {}
	var in_pool := true
	for d: Variant in drawn:
		drawn_uniq[d] = true
		if not file_lines.has(d):
			in_pool = false
	check_eq(drawn_uniq.size(), D1_BUBBLES, "①：洗牌袋连续 12 次抽取零重复（%d 异）" % drawn_uniq.size())
	check(in_pool, "①：抽取句全部∈生产池（逐字）")
	lv.queue_free()
	await process_frame

	# ==================== 断言②：talk_controller 默认链（chapter=1）——51 句逐句点击至 _finish ====================
	var talk: Node = await _new_talk({"mode": "after_level", "chapter": 1})
	check_eq(String(talk.get("loaded_path")), DOC_DIR + "第1关.json",
		"②：默认章节映射 CHAPTER_DOCS[1] → 第1关.json（零夹具）")
	var lines: Array = talk.get("_lines")
	check_eq(lines.size(), D1_SENTS, "②：拍平句数==51（实测 %d）" % lines.size())
	var sp_ok := true
	for ln: Variant in lines:
		if not (ln is Dictionary) or not LEGAL_SPEAKERS.has(String((ln as Dictionary).get("speaker", ""))):
			sp_ok = false
	check(sp_ok, "②：全部 51 句 speaker∈{晷,我}")
	if lines.size() == D1_SENTS:
		check_eq(String((lines[0] as Dictionary).get("text", "")), D1_FIRST, "②：首句逐字（控制器拍平后）")
		check_eq(String((lines[D1_SENTS - 1] as Dictionary).get("text", "")), D1_LAST, "②：末句逐字在库")
	# 逐句**点击**推进（_gui_input 真实输入路径；同步连点不跨帧，打字机态由快进语义承接）
	var st0: int = int(game.current_state())
	var visited: Array = [0]
	var clicks := 0
	var finished := false
	var click_ev: InputEventMouseButton = _mk_click()
	while clicks < 200 and not finished:
		clicks += 1
		talk.call("_gui_input", click_ev)
		var idx: int = int(talk.get("_index"))
		if int(visited[visited.size() - 1]) != idx:
			visited.append(idx)
		finished = int(game.current_state()) != st0
	check(finished, "②：点击至 _finish（%d 次点击，state %d→%d）" % [clicks, st0, int(game.current_state())])
	check_eq(visited.size(), D1_SENTS, "②：逐句推进恰经过 51 个索引（0..50，无跳句；实测 %d）" % visited.size())
	var seq_ok: bool = visited.size() == D1_SENTS
	for i: int in range(visited.size()):
		if int(visited[i]) != i:
			seq_ok = false
	check(seq_ok, "②：索引序严格 0..50 递增（逐句推进口径不变）")
	check_eq(String((talk.get_node("DialogPanel/VBox/TextLabel") as Label).text), D1_LAST,
		"②：末句完成态显示逐字（点击链路播完 51 句）")
	check_eq(int(game.current_state()), ST_LEVEL, "②：_finish → LEVEL（进第 1 关）")
	check_eq(int(game.context().get("chapter", -1)), 1, "②：ctx.chapter==1")
	talk.queue_free()
	await process_frame

	# ==================== AF：en 显示链新事实锁定（红态同源事实，断言只增不减） ====================
	# 红态实测（2026-11-01）：用户档 language=en 时 ② 末句显示英文 texts_en——生产双语显示链
	# 新事实（_line_text/_speaker_name en 优先轮级英文字段）。zh 基线已钉扎恢复，此处显式切 en
	# 锁定英文链：拍平数据层 text 恒中文原文（双语改写只在显示层）、显示层取 texts_en、名牌取
	# speaker_en（右名牌「我」=I、末轮左名牌「晷」=Gui——均 JSON 驱动，不依赖词条表回退）。
	i18n.call("set_language", "en")
	check_eq(String(i18n.call("get_language")), "en", "AF：切 en（language_changed 链路就绪）")
	var t_en: Node = await _new_talk({"mode": "after_level", "chapter": 1})
	check_eq(String(t_en.get("loaded_path")), DOC_DIR + "第1关.json", "AF-en：默认链 → 第1关.json")
	var en_lines: Array = t_en.get("_lines")
	check_eq(en_lines.size(), D1_SENTS, "AF-en：拍平句数恒 %d（语言无关）" % D1_SENTS)
	check_eq(String((en_lines[D1_SENTS - 1] as Dictionary).get("text", "")), D1_LAST,
		"AF-en：拍平清单 text 字段恒中文原文（双语改写在显示层，不在数据层）")
	check_eq(String((t_en.get_node("NameTagRight/NameLabel") as Label).text), SP_EN_ME,
		"AF-en：首句（我）右名牌=I（speaker_en 消费）")
	t_en.call("_show_line", D1_SENTS - 1)
	t_en.call("_advance")  # 打字中首击=快进本句（en 全文置入）
	await process_frame
	check_eq(String((t_en.get_node("DialogPanel/VBox/TextLabel") as Label).text), D1_LAST_EN,
		"AF-en：en 末句显示==texts_en 逐字（红态同源事实锁定）")
	check_eq(String((t_en.get_node("NameTagLeft/NameLabel") as Label).text), SP_EN_GUI,
		"AF-en：末轮（晷）左名牌=Gui（speaker_en 消费）")
	t_en.queue_free()
	await process_frame
	i18n.call("set_language", "zh")  # 还原 zh 基线（后续 ③ 断言与语言无关，稳妥复位）

	# ==================== 断言③：第 2~5 关默认链 + 实质句零交集 + 文案入库状态 ====================
	# 批次 AC 4A（2026-09-27）：第 2 关正式文案入库——"占位待替换" 断言改**正式文案锚点**
	#（轮数/句数/「衣橱」提及）。批次 AF（2026-11-01）：第 3~5 关占位稿亦由用户正式文案替换
	# 并注入英文字段——"占位待替换" 正断言改**反向锁**（零命中）+ 英文字段护栏；交集判据改
	# 「实质句零交集」（已知交集=第 2∩4 关纯标点句「？？？」，单列锁定）。断言数只增不减。
	var text_sets: Dictionary = {}
	for ch: int in range(2, 6):
		var fname := "第%d关.json" % ch
		var tk: Node = await _new_talk({"mode": "after_level", "chapter": ch})
		check_eq(String(tk.get("loaded_path")), DOC_DIR + fname, "③：chapter=%d 默认链 → %s（零夹具）" % [ch, fname])
		var tlines: Array = tk.get("_lines")
		check(tlines.size() >= 1, "③：第%d关 默认链拍平句数≥1（rounds 非空；实测 %d）" % [ch, tlines.size()])
		if ch == 2:
			check_eq(tlines.size(), D2_SENTS, "③：第2关 正式文案拍平句数==%d（实测 %d）" % [D2_SENTS, tlines.size()])
		var raw: Variant = _load_json(DOC_DIR + fname)
		check(raw is Dictionary, "③：%s 生产文件可解析" % fname)
		if raw is Dictionary:
			var rds: Variant = (raw as Dictionary).get("rounds")
			check(rds is Array and not (rds as Array).is_empty(), "③：%s rounds 非空" % fname)
			var note: Variant = (raw as Dictionary).get("_说明")
			if ch == 2:
				check(note is Array and not JSON.stringify(note).contains("占位待替换"),
					"③：第2关 \"_说明\" 已去占位标注（正式文案入库，铁律 8）")
				var raw_txt: String = FileAccess.get_file_as_string(DOC_DIR + fname)
				check(raw_txt.contains("衣橱"), "③：第2关 正式文案含「衣橱」字样（§4.9 改名同源）")
				if rds is Array:
					check_eq((rds as Array).size(), D2_ROUNDS, "③：第2关 正式文案轮数==%d" % D2_ROUNDS)
			else:
				check(note is Array and not JSON.stringify(note).contains("占位待替换"),
					"③：%s \"_说明\" 零「占位待替换」（正式文案反向锁，AF）" % fname)
			var st: Dictionary = {}
			if rds is Array:
				for rr: Variant in (rds as Array):
					if rr is Dictionary and (rr as Dictionary).get("texts") is Array:
						for tx: Variant in (rr as Dictionary)["texts"]:
							if tx is String and String(tx) != "":
								st[String(tx)] = true
			text_sets[ch] = st
			# AF：英文字段护栏（speaker_en 配对 + texts_en 逐轮等长全字符串）
			var pair_af := true
			var enlen_af := true
			var enstr_af := true
			if rds is Array:
				for raf3: Variant in (rds as Array):
					if not (raf3 is Dictionary):
						continue
					var rd3: Dictionary = raf3 as Dictionary
					var sp3 := String(rd3.get("speaker", ""))
					var spe3 := String(rd3.get("speaker_en", ""))
					if not ((sp3 == "晷" and spe3 == SP_EN_GUI) or (sp3 == "我" and spe3 == SP_EN_ME)):
						pair_af = false
					var tv3: Variant = rd3.get("texts", [])
					var ev3: Variant = rd3.get("texts_en", [])
					if not (tv3 is Array and ev3 is Array and (ev3 as Array).size() == (tv3 as Array).size()):
						enlen_af = false
					else:
						for es3: Variant in (ev3 as Array):
							if not (es3 is String):
								enstr_af = false
			check(pair_af, "③：第%d关 全轮 speaker/speaker_en 合法配对（晷↔Gui、我↔I，AF 护栏）" % ch)
			check(enlen_af, "③：第%d关 全轮 texts_en 与 texts 逐轮等长（AF 护栏）" % ch)
			check(enstr_af, "③：第%d关 texts_en 全为字符串（AF 护栏）" % ch)
		# 气泡默认链（level_scene 同款 path_for_chapter 表达式）2~5 关逐字可用
		var bpath: String = String(BubbleBag.path_for_chapter(ch))
		check_eq(bpath, DOC_DIR + "气泡_第%d关.json" % ch, "③：path_for_chapter(%d) → 气泡_第%d关.json" % [ch, ch])
		var bag: RefCounted = BubbleBag.new()
		var bag_ok: bool = bool(bag.load_path(bpath))
		check(bag_ok, "③：气泡第%d关 默认路径加载成功" % ch)
		if bag_ok:
			var braw: Variant = _load_json(bpath)
			var blines: Array = (braw as Dictionary).get("lines", []) if braw is Dictionary else []
			check_eq((bag.pool() as Array).size(), blines.size(),
				"③：气泡第%d关 池==文件条数（%d 条，逐字链）" % [ch, blines.size()])
			# AF：lines_en 护栏（与 lines 逐条等长）
			var blines_en: Variant = (braw as Dictionary).get("lines_en", []) if braw is Dictionary else []
			check(blines_en is Array and (blines_en as Array).size() == blines.size() and blines.size() > 0,
				"③：气泡第%d关 lines_en 与 lines 逐条等长（AF 护栏）" % ch)
		tk.queue_free()
		await process_frame
	# （批次 AF 改口径）四关（2~5）文本两两**实质句零交集**：现行正式文案第 2∩4 关存在 1 句
	# 纯标点交集「？？？」（盘上实况，机械解析自查，三个全角问号 U+FF1F）——纯标点句无语义
	# 承载，判据改为「交集⊆已知纯标点句集合 {「？？？」}」（保护力不变：任何实质句跨关复制
	# 仍红；已知交集句于下一条单列锁定）。
	for a: int in range(2, 6):
		for b: int in range(a + 1, 6):
			if text_sets.has(a) and text_sets.has(b):
				var inter: Dictionary = {}
				for k2: Variant in (text_sets[a] as Dictionary):
					if (text_sets[b] as Dictionary).has(k2):
						inter[k2] = true
				var sub_ok := true
				for ik: Variant in inter:
					if String(ik) != "？？？":
						sub_ok = false
				check(sub_ok, "③：第%d关∩第%d关 实质句零交集（交集⊆{「？？？」}；实测交集 %s）" % [a, b, str(inter.keys())])
	# AF：已知交集句锁定（盘上实况）：第 2∩4 关交集恰为 {「？？？」}（纯标点句）
	if text_sets.has(2) and text_sets.has(4):
		var inter24: Dictionary = {}
		for k4: Variant in (text_sets[2] as Dictionary):
			if (text_sets[4] as Dictionary).has(k4):
				inter24[k4] = true
		check(inter24.size() == 1 and bool(inter24.get("？？？", false)),
			"③：已知交集句锁定：第2∩4 关交集恰为 {「？？？」}（纯标点句；实测 %s）" % str(inter24.keys()))

	# 全量卫生自检：五个对话文件 + 五个气泡文件均在库（生产链文件清单完整性）
	for ch2: int in range(1, 6):
		check(FileAccess.file_exists(DOC_DIR + "第%d关.json" % ch2), "清单：第%d关.json 在库" % ch2)
		check(FileAccess.file_exists(DOC_DIR + "气泡_第%d关.json" % ch2), "清单：气泡_第%d关.json 在库" % ch2)
	check(FileAccess.file_exists(DOC_DIR + "README.md"), "清单：剧情对话/README.md 在库")

	finish()
