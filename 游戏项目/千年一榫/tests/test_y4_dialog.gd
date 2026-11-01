extends "res://tests/test_base.gd"
## 批次 Y Y4 波（剧情对话文档体系，Y-B1~Y-B7）无头测试。
## 契约来源：批次 Y spec §9.0 拍板 1~6 + §9.1 Y-B1~Y-B7 + 技术文档/接口规范_剧情对话.md。
##   格式（Y-B2）：{"_说明":[…],"rounds":[{"speaker":"晷"|"我","texts":[…]}]}；"_说明" 被加载器忽略；
##     解析防御：非法 speaker/缺字段/空 texts → 整轮跳过+告警（doc_warnings）不崩；JSON 注释必炸→空文档不崩。
##   加载（Y-B3 + 批次 Z §14 增补，用户 2026-09-24 拍板）：opening 语境退役——开场对话
##     （剧情对话/开场.json，AI 试写稿）整份删除，set_context 对 mode=="opening" 等旧值**静默归一**
##     为 after_level（按传入 chapter 取该关文档，缺省 1，不报错不新增告警）；after_level(n)→
##     剧情对话/第n关.json（缺失回退**空文档+告警**，loaded_path==""，不再指向已删文件）；
##     逐句点击推进（轮内逐句、轮末切下一轮）；开场迁移逐字节等价断言随 §14 退役
##     （旧归档 assets/dialog/opening.json 保留文件本体，文案已被用户否决，不得再挂载）。
##   立绘（Y-B4）：对话立绘=晷唯一（主角无立绘），章节常量映射（1开头/2宋/3元/4明/5现，assets/characters/era_portraits/）；
##     对话开始定档、期间锁死（断开 skin_changed 联动——对话中换肤立绘纹理不变，红测锁定）；缺图回落第 1 关+告警。
##   名字框（拍板 4）：晷=左、我=右，随 speaker 互斥切换（2026-09-22 拍板名牌=晷）。
##   气泡（Y-B6/Y-C8 文件域）：气泡_第N关.json={"_说明",lines:字符串数组}；第 1 关 12 条正式文案逐字锚点。
##   批次 AF（2026-11-01）：全 5 关对话+气泡正式文案入库并注入英文字段（speaker_en/texts_en/
##     lines_en，机械解析实况：轮数 44/18/7/10/11、句数 51/51/17/26/27、气泡 12/16/16/16/16）
##     ——「占位待替换」断言改反向锁（零命中）、第 3~5 关升级正式锚点、新增英文字段护栏
##     （11b 统一护栏环：配对/等长/全字符串）；原「条数两两互异」占位稿口径随正式文案退役
##     （第 3~5 关气泡实况同为 16 条，互异判据恒假——读码依据留痕 §11）。
## 环境说明（同 test_talk_scene）：--script 无头模式 autoload 已实例化，但主脚本编译早于注册，
##   经 /root/<Name> 与 load() 动态引用；add_child 后 await process_frame 再驱动。

const SCENE_PATH := "res://scenes/dialog/talk_controller.gd"
const TALK_SCENE := "res://scenes/dialog/talk_scene.tscn"
const DOC_DIR := "res://剧情对话/"
const OLD_OPENING := "res://assets/dialog/opening.json"
const SAVE_PATH := "user://save.json"

const ST_LEVEL := 4
const ST_MAIN_MENU := 1
const ST_TALK := 3  # 批次 Y（Y-C6）：对话挂载态（§14 后 opening 实例归一=after_level 语义）

const SP_GUI := "晷"
const SP_ME := "我"

# 章节→文档映射期望（与 talk_controller.CHAPTER_DOCS 契约一致）
const DOC_FILES: Array = ["第1关.json", "第2关.json", "第3关.json", "第4关.json", "第5关.json"]
const BUBBLE_FILES: Array = ["气泡_第1关.json", "气泡_第2关.json", "气泡_第3关.json", "气泡_第4关.json", "气泡_第5关.json"]
# 章节→立绘映射期望（Y-B4 拍板：1开头/2宋/3元/4明/5现）
const ERA_PNG: Dictionary = {
	1: "res://assets/characters/era_portraits/开头.png",
	2: "res://assets/characters/era_portraits/宋.png",
	3: "res://assets/characters/era_portraits/元.png",
	4: "res://assets/characters/era_portraits/明.png",
	5: "res://assets/characters/era_portraits/现.png",
}

# 第 1 关内容锚点（用户提供文案逐字入库；机械解析自查=44 轮 51 句）
const D1_ROUNDS := 44
const D1_SENTS := 51
const D1_FIRST := "等——这是哪儿？刚才还站着，一眨眼，满天是光。"
const D1_LAST := "……到了。小心，几千年前的泥，可不好擦。"
const D1_ROUND5_TEXTS: Array = [
	"形貌于我，本就不是死物。真的、画的、大的、小的，都是我。这一身，我偏爱。",
	"改了好几处呢。这儿添条飘带，那儿缀一枚……",
	"（一顿）算了，这些你听了也白听。",
]
const D1_SHAN := "善。"

# ===== 第 2 关正式文案锚点（用户 2026-09-27 提供；铁律 8：正式台词仅替换文本，结构不变）=====
# 机械解析自查：18 轮 / 51 句 / 气泡 16 条（见 AI工作记录 批次 AC 走查取证）。
const D2_ROUNDS := 18
const D2_SENTS := 51
const D2_BUBBLES := 16
const D2_FIRST := "（低头拍了拍衣角）呼……总算是从那几千年前的河姆渡爬出来了，上一关那满地的黄土泥巴，可算全给甩干净了。"
const D2_LAST := "光幕散了，站稳咯！咱们——入宋！"
const D2_BUBBLE_FIRST := "看腻我现在这副模样了？衣橱就在边上，这回随你怎么换，可别挑花了眼哦。"
const D2_BUBBLE_LAST := "你尽管放手去试，错了大不了重来。有我在边上看着你呢，慌什么。"

# ===== 批次 AF（2026-11-01）：第 3~5 关正式文案锚点（用户提供替换占位稿并注入英文字段）=====
# 机械解析自查（盘上实况唯一真相）：第 3 关 7 轮 17 句、第 4 关 10 轮 26 句、第 5 关 11 轮 27 句；
# 第 2~5 关气泡统一 16 条（第 1 关 12 条不变）；全 5 关每轮 speaker_en∈{Gui,I} 与 speaker
# 合法配对（晷↔Gui、我↔I）、texts_en 与 texts 逐轮等长、气泡 lines_en 与 lines 逐条等长。
const D3_ROUNDS := 7
const D3_SENTS := 17
const D4_ROUNDS := 10
const D4_SENTS := 26
const D5_ROUNDS := 11
const D5_SENTS := 27
const AF_BUBBLES := 16
const SP_EN_GUI := "Gui"
const SP_EN_ME := "I"
const D1_LAST_EN := "...We're here. Mind yourself—mud from a few thousand years past does not wipe off easily."
const D2_LAST_EN := "The screen of light is scattering—hold your footing! We—enter the Song!"

# ===== 清档纪律（tools/README_走查清档规范.md；test_talk_scene 同款）=====
const DISC_SAVE_PATH := "user://save.json"
const DISC_FLAG_PATH := "user://first_launch.flag"
const DISC_TMP_PATH := "user://save.json.tmp"
const DISC_BAK_PATH := "user://save.json.bak"
const DISC_BK_PREFIX := "user://_r2y4_backup_"
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
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

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
	print("EVID|user_restore|y4|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

# ===== 助手 =====

func _new_talk(ctx: Dictionary) -> Control:
	var talk: Node = load(TALK_SCENE).instantiate()
	talk.call("set_context", ctx)
	add_child(talk)
	await process_frame
	await process_frame
	return talk as Control

func _drop(talk: Node) -> void:
	if talk != null:
		talk.queue_free()
	await process_frame

func _write_user_json(name: String, content: String) -> String:
	var p := "user://" + name
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(content)
	f.close()
	return p

func _del_user(name: String) -> void:
	_disc_del("user://" + name)

## 告警列表安全取值（红阶段属性缺失时返回空数组而非崩）
func _warns(talk: Node) -> Array:
	var w: Variant = talk.get("doc_warnings")
	return w if w is Array else []

## 解析器调用守卫（红阶段方法缺失→返回 null 由调用方判）
func _parse_via(talk: Node, parsed: Variant, path: String) -> Variant:
	if not talk.has_method("_parse_dialog_doc"):
		return null
	return talk.call("_parse_dialog_doc", parsed, path)

func _load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed

func _read_text(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t

# ===== 主流程 =====

func _initialize() -> void:
	print("== test_y4_dialog ==")
	_backup_user()
	var save: Node = root.get_node("SaveManager")
	var game: Node = root.get_node("Game")

	if FileAccess.file_exists(_disc_abs(SAVE_PATH)):
		DirAccess.remove_absolute(_disc_abs(SAVE_PATH))
	save.load_game()

	var container: Control = Control.new()
	container.size = Vector2(1152, 648)
	add_child(container)
	game.attach(container, null)

	# ---- 1. 文件清单（Y-B1：五份主对话 JSON+README；气泡五份；§14 开场.json 已删除）----
	for f: String in DOC_FILES:
		check(FileAccess.file_exists(DOC_DIR + f), "Y-B1：%s 存在" % f)
	check(not FileAccess.file_exists(DOC_DIR + "开场.json"),
		"§14②：开场.json 已删除（AI 试写稿退役，红测：现状在库）")
	check(FileAccess.file_exists(DOC_DIR + "README.md"), "Y-B1：剧情对话/README.md 存在")
	for f: String in BUBBLE_FILES:
		check(FileAccess.file_exists(DOC_DIR + f), "Y-C8 文件域：%s 存在" % f)
	# 每份主文档："_说明" 是数组（被忽略的说明键）+ rounds 非空数组
	for f: String in DOC_FILES:
		var parsed: Variant = _load_json(DOC_DIR + f)
		check(parsed is Dictionary, "%s 可解析为对象" % f)
		if parsed is Dictionary:
			check((parsed as Dictionary).get("_说明") is Array, "%s _说明 为数组（加载器忽略）" % f)
			var rd: Variant = (parsed as Dictionary).get("rounds")
			check(rd is Array and not (rd as Array).is_empty(), "%s rounds 非空" % f)
	# ---- 2. 章节映射（Y-B3 + §14 归一）：after_level(n)→第n关.json；opening 静默归一 after_level；暴露 loaded_path ----
	if FileAccess.file_exists(SCENE_PATH):
		check(true, "talk_controller.gd 存在")
	else:
		check(false, "talk_controller.gd 存在")
	for ch: int in range(1, 6):
		var t: Control = await _new_talk({"mode": "after_level", "chapter": ch})
		var lp: Variant = t.get("loaded_path")
		check(lp is String and String(lp) == DOC_DIR + DOC_FILES[ch - 1],
			"Y-B3：after_level(%d) → %s（实测 %s）" % [ch, DOC_FILES[ch - 1], str(lp)])
		await _drop(t)
	var to: Control = await _new_talk({"mode": "opening", "chapter": 1})
	var lpo: Variant = to.get("loaded_path")
	check(lpo is String and String(lpo) == DOC_DIR + "第1关.json",
		"§14④：opening 静默归一 after_level(1) → 第1关.json（红测：现状 开场.json；实测 %s）" % str(lpo))
	check(_warns(to).is_empty(), "§14④：归一静默（零新增告警，实测 %d 条）" % _warns(to).size())
	await _drop(to)

	# ---- 2b. §14④ 归一按传入 chapter 取文档 / 缺省语境=after_level(1) ----
	var t_norm: Control = await _new_talk({"mode": "opening", "chapter": 2})
	check_eq(String(t_norm.get("loaded_path")), DOC_DIR + "第2关.json",
		"§14④：opening chapter=2 归一 → 第2关.json")
	check((t_norm.get("_lines") as Array).size() >= 1, "§14④：归一后 rounds 非空（逐句清单非空）")
	await _drop(t_norm)
	var t_def: Control = await _new_talk({})
	check_eq(String(t_def.get("loaded_path")), DOC_DIR + "第1关.json",
		"§14④：缺省语境（无 mode/chapter）→ after_level(1) → 第1关.json")
	await _drop(t_def)

	# ---- 3. 缺文件回退（§14 等价改写）：after_level(9) → 空文档 + 告警（不再指向已删文件）----
	var tf: Control = await _new_talk({"mode": "after_level", "chapter": 9})
	var lpf: Variant = tf.get("loaded_path")
	check(lpf is String and String(lpf) == "",
		"缺失回退（§14）：after_level(9) → 空文档 loaded_path==\"\"（红测：现状回退旧文件；实测 %s）" % str(lpf))
	check(not _warns(tf).is_empty(), "缺失回退：已输出告警（doc_warnings 非空）")
	check(_warns(tf).size() >= 1, "缺失回退：告警进入 doc_warnings（%d 条）" % _warns(tf).size())
	check((tf.get("_lines") as Array).is_empty(), "缺失回退：空台词清单（空文档按空台词流程收尾）")
	await _drop(tf)

	# ---- 4. 解析器红测（Y-B2）：非法用例跳过+告警不崩；合法用例全收 ----
	var tp: Control = await _new_talk({"mode": "opening", "chapter": 1})
	if not tp.has_method("_parse_dialog_doc"):
		check(false, "Y-B2：解析器 _parse_dialog_doc 存在（新契约 API）")
	var cases: Array = [
		# [名, JSON 文本, 期望存活句数, 期望告警>=1]
		["非法 speaker", '{"rounds":[{"speaker":"路人甲","texts":["x"]},{"speaker":"晷","texts":["合法"]},{"speaker":"我","texts":["合法我"]}]}', 2, true],
		["缺 speaker", '{"rounds":[{"texts":["x"]}]}', 0, true],
		["缺 texts", '{"rounds":[{"speaker":"晷"}]}', 0, true],
		["空 texts", '{"rounds":[{"speaker":"晷","texts":[]}]}', 0, true],
		["全空串 texts", '{"rounds":[{"speaker":"我","texts":["",""]}]}', 0, true],
		["元素非对象", '{"rounds":["垃圾",{"speaker":"晷","texts":["好"]}]}', 1, true],
		["顶层缺 rounds", '{"_说明":["只有说明"]}', 0, true],
		["顶层垃圾", '"一个字符串"', 0, true],
		["非字符串句", '{"rounds":[{"speaker":"晷","texts":[123,"好"]}]}', 1, true],
	]
	var parser_alive: bool = tp.has_method("_parse_dialog_doc")
	for c: Array in cases:
		var p := "user://y4_case.json"
		var fw := FileAccess.open(p, FileAccess.WRITE)
		fw.store_string(String(c[1]))
		fw.close()
		tp.call("_load_dialog", p)
		var lines: Variant = tp.get("_lines")
		var n: int = (lines as Array).size() if lines is Array else -1
		check_eq(n, int(c[2]), "Y-B2 %s：存活句数==%d（实测 %s）" % [String(c[0]), int(c[2]), str(n)])
		var w: Array = _warns(tp)
		if bool(c[3]):
			check(not w.is_empty(), "Y-B2 %s：跳过轮有告警（doc_warnings %d 条）" % [String(c[0]), w.size()])
		_del_user("y4_case.json")
	# JSON 注释必炸 → 空文档不崩（4.7 行为锁定）
	var tc := FileAccess.open("user://y4_comment.json", FileAccess.WRITE)
	tc.store_string("{/*注释*/\"rounds\":[]}")
	tc.close()
	tp.call("_load_dialog", "user://y4_comment.json")
	var lc: Variant = tp.get("_lines")
	check(lc is Array and (lc as Array).is_empty(), "Y-B2 JSON 注释：解析失败→空文档不崩")
	_del_user("y4_comment.json")
	# 兼容宽容：顶层纯数组也收（接口规范允许的手写简化形态）
	var ta := FileAccess.open("user://y4_arr.json", FileAccess.WRITE)
	ta.store_string('[{"speaker":"晷","texts":["数组顶层也可"]}]')
	ta.close()
	tp.call("_load_dialog", "user://y4_arr.json")
	var la: Variant = tp.get("_lines")
	check(la is Array and (la as Array).size() == 1, "Y-B2 宽容：顶层纯数组可解析（实测 %s 句）" % str((la as Array).size() if la is Array else "null"))
	_del_user("y4_arr.json")
	# "_说明" 被忽略：合法轮不受说明影响
	var ok_doc: Dictionary = {"_说明": ["说明一行", "说明两行"], "rounds": [{"speaker": "晷", "texts": ["甲", "乙"]}, {"speaker": "我", "texts": ["丙"]}]}
	var parsed_ok: Variant = _parse_via(tp, ok_doc, "<合成>")
	check(parsed_ok is Array, "Y-B2：_parse_dialog_doc 可直接调用")
	if parsed_ok is Array:
		check_eq((parsed_ok as Array).size(), 3, "Y-B2：_说明 被忽略，轮内容全收（2 轮 3 句）")
	await _drop(tp)

	# ---- 5. 合法任意轮数句数完整播放（Y-B2 验收：顺序与文件一致；§14 归一后 opening 实例=after_level(1) 语义）----
	var tm: Control = await _new_talk({"mode": "opening", "chapter": 1})
	var order_path := "user://y4_order.json"
	var ow := FileAccess.open(order_path, FileAccess.WRITE)
	ow.store_string('{"_说明":["顺序"],"rounds":[{"speaker":"晷","texts":["甲一","甲二"]},{"speaker":"我","texts":["乙一"]},{"speaker":"晷","texts":["丙一"]}]}')
	ow.close()
	tm.call("_load_dialog", order_path)
	var ml: Array = (tm.get("_lines") as Array)
	var want: Array = [["晷", "甲一"], ["晷", "甲二"], ["我", "乙一"], ["晷", "丙一"]]
	check_eq(ml.size(), 4, "播放：4 句全收")
	var seq_ok := ml.size() == 4
	for i: int in range(mini(ml.size(), 4)):
		if String((ml[i] as Dictionary).get("speaker", "")) != String(want[i][0]) \
				or String((ml[i] as Dictionary).get("text", "")) != String(want[i][1]):
			seq_ok = false
	check(seq_ok, "播放：句序/说话人与文件一致")
	# 逐击推进：快进甲一 → 甲二 → 乙一 → 丙一 → 末句击=结束路由
	var text_label: Label = tm.get_node("DialogPanel/VBox/TextLabel")
	for k: int in range(4):
		tm.call("_advance")  # 打字中首击=快进本句
		check_eq(String(text_label.text), String(want[k][1]), "播放：第 %d 句快进全文==%s" % [k + 1, String(want[k][1])])
		if k < 3:
			tm.call("_advance")  # 完成态击=下一句
			await process_frame
	tm.call("_advance")  # 末句完成态击 → _finish（§14 归一：opening 实例=after_level(1) 语义 → 进第 1 关）
	await process_frame
	check_eq(int(game.current_state()), ST_LEVEL, "播放（§14 归一）：opening 实例播完 → LEVEL{chapter:1}（after_level 语义，红测：现状 TALK）")
	check_eq(int(game.context().get("chapter", -1)), 1, "播放（§14 归一）：ctx.chapter==1（进第 1 关）")
	_del_user("y4_order.json")
	await _drop(tm)

	# ---- 6. 超长句（Y-B2：长度不限）----
	var tl: Control = await _new_talk({"mode": "opening", "chapter": 1})
	var long_s: String = "长".repeat(2000) + "。"
	var lw := FileAccess.open("user://y4_long.json", FileAccess.WRITE)
	lw.store_string(JSON.stringify({"_说明": ["超长"], "rounds": [{"speaker": "晷", "texts": [long_s]}]}))
	lw.close()
	tl.call("_load_dialog", "user://y4_long.json")
	var ll: Array = (tl.get("_lines") as Array)
	check_eq(ll.size(), 1, "超长：单句全收")
	if ll.size() == 1:
		check_eq(String((ll[0] as Dictionary).get("text", "")).length(), long_s.length(), "超长：句长完整（%d 字）" % long_s.length())
	tl.call("_advance")
	check_eq(String((tl.get_node("DialogPanel/VBox/TextLabel") as Label).text), long_s, "超长：快进显示全文")
	_del_user("y4_long.json")
	await _drop(tl)

	# ---- 7. §14 增补（用户 2026-09-24 拍板）：开场对话退役——旧迁移逐字节等价断言随文档删除退役，
	#      换锚「文件已删 / 归一零告警 / 首句逐字 / 控制器零指向已删文件字面引用」----
	check(not FileAccess.file_exists(DOC_DIR + "开场.json"), "§14②：开场.json 不在库（迁移等价断言退役锚）")
	check(FileAccess.file_exists(OLD_OPENING),
		"§14④ 边界：旧迁移源 assets/dialog/opening.json 保留文件本体（14.4 备案，不得挂载）")
	var tc_src: String = FileAccess.get_file_as_string("res://scenes/dialog/talk_controller.gd")
	check(not tc_src.contains("开场.json"), "§14④：talk_controller.gd 零 开场.json 字面引用（OPENING_DOC 已删）")
	var om_src: String = FileAccess.get_file_as_string("res://scenes/movie/opening_movie.gd")
	check(om_src.contains("\"mode\": \"after_level\"") and not om_src.contains("\"mode\": \"opening\""),
		"§14①：opening_movie 首次路径挂 after_level（零 opening 语境）")

	# ---- 8. 第 1 关内容锚点（Y-B6：正式文案逐字入库）----
	var d1: Variant = _load_json(DOC_DIR + "第1关.json")
	check(d1 is Dictionary, "第1关.json 可解析")
	if d1 is Dictionary:
		var r1: Array = (d1 as Dictionary).get("rounds", [])
		var n_s := 0
		for r: Variant in r1:
			if r is Dictionary and (r as Dictionary).get("texts") is Array:
				n_s += (r["texts"] as Array).size()
		check_eq(r1.size(), D1_ROUNDS, "第1关：轮数==%d（机械解析自查值，见交付报告 43/49 口径偏差说明）" % D1_ROUNDS)
		check_eq(n_s, D1_SENTS, "第1关：句数==%d" % D1_SENTS)
		if r1.size() >= 1:
			var r0: Dictionary = r1[0] as Dictionary
			check_eq(String(r0.get("speaker", "")), SP_ME, "第1关：首轮 speaker=我")
			var t0: Variant = r0.get("texts")
			check(t0 is Array and (t0 as Array).size() >= 1 and String((t0 as Array)[0]) == D1_FIRST, "第1关：首句逐字==「等——这是哪儿？…」")
		if r1.size() == D1_ROUNDS:
			check_eq(String((r1[D1_ROUNDS - 1] as Dictionary).get("speaker", "")), SP_GUI, "第1关：末轮 speaker=晷")
			var te: Variant = (r1[D1_ROUNDS - 1] as Dictionary).get("texts")
			check(te is Array and (te as Array).size() >= 1 and String((te as Array)[te.size() - 1]) == D1_LAST, "第1关：末句逐字==「……到了。…」")
			check_eq((r1[5] as Dictionary).get("texts", []), D1_ROUND5_TEXTS, "第1关：第 6 轮（晷×3 连续合并）逐字一致（含行内（一顿）保留）")
			check_eq((r1[42] as Dictionary).get("texts", []), [D1_SHAN], "第1关：第 43 轮=「善。」")
	# 播放链路：after_level(1) → 51 句逐句推进
	var t_d1: Control = await _new_talk({"mode": "after_level", "chapter": 1})
	var d1_lines: Variant = t_d1.get("_lines")
	check(d1_lines is Array and (d1_lines as Array).size() == D1_SENTS, "第1关播放：51 句全收（实测 %s）" % str((d1_lines as Array).size() if d1_lines is Array else "null"))
	await _drop(t_d1)

	# ---- 9. 立绘（Y-B4）：章节映射定档 + 锁死红测 + 缺图回落 ----
	var t_p0: Control = await _new_talk({"mode": "opening", "chapter": 1})
	check_eq(String(t_p0.get("portrait_path")), ERA_PNG[1], "Y-B4：opening 归一实例立绘=第 1 关开头立绘")
	await _drop(t_p0)
	for ch2: int in range(1, 6):
		var t_pc: Control = await _new_talk({"mode": "after_level", "chapter": ch2})
		check_eq(String(t_pc.get("portrait_path")), ERA_PNG[ch2], "Y-B4：chapter=%d 立绘=%s" % [ch2, String(ERA_PNG[ch2]).get_file()])
		check((t_pc.get_node("Portrait") as TextureRect).texture != null, "Y-B4：chapter=%d 立绘纹理已加载" % ch2)
		await _drop(t_pc)
	# 锁死红测：对话开始定档后，购买+穿戴皮肤→立绘路径与纹理实例均不变
	var t_lock: Control = await _new_talk({"mode": "after_level", "chapter": 1})
	var before_path: String = String(t_lock.get("portrait_path"))
	var before_tex: Texture2D = (t_lock.get_node("Portrait") as TextureRect).texture
	check_eq(before_path, ERA_PNG[1], "锁死前置：对话开始已定档开头立绘")
	save.add_talent(500)
	check(bool(save.buy_skin("skin_01")), "锁死前置：购买 skin_01 成功")
	check(bool(save.equip_skin("skin_01")), "锁死前置：穿戴 skin_01 成功")
	save.skin_changed.emit("skin_01")  # 直播信号：模拟任何换肤源（含商店/设置链路）
	await process_frame
	await process_frame
	check_eq(String(t_lock.get("portrait_path")), before_path, "Y-B4 锁死：对话中换肤→立绘路径不变（旧 bug 红测反锁）")
	check((t_lock.get_node("Portrait") as TextureRect).texture == before_tex, "Y-B4 锁死：对话中换肤→立绘纹理实例不变")
	# 缺图回落：映射外章节→第 1 关立绘+告警
	var warns0: int = _warns(t_lock).size()
	var fb: Variant = null
	if t_lock.has_method("_era_portrait_path"):
		fb = t_lock.call("_era_portrait_path", 7)
	check(fb is String and String(fb) == ERA_PNG[1], "Y-B4 缺图回落：映射外章节→开头立绘（实测 %s）" % str(fb))
	check(_warns(t_lock).size() > warns0, "Y-B4 缺图回落：已输出告警")
	await _drop(t_lock)

	# ---- 10. 名字框（Y-B4/拍板 4）：晷=左、我=右，随 speaker 互斥 ----
	var t_tag: Control = await _new_talk({"mode": "after_level", "chapter": 1})
	var nll: Label = t_tag.get_node("NameTagLeft/NameLabel")
	var nlr: Label = t_tag.get_node("NameTagRight/NameLabel")
	var ntl: Control = t_tag.get_node("NameTagLeft")
	var ntr: Control = t_tag.get_node("NameTagRight")
	check_eq(String(nll.text), "晷", "名牌：左框固定文本=晷")
	check_eq(String(nlr.text), SP_ME, "名牌：右框固定文本=我")
	# 第 1 句 speaker=我 → 右显左隐
	check(ntl != null and ntr != null and ntr.visible and not ntl.visible, "名牌：句1（我）右显左隐")
	var dtext: Label = t_tag.get_node("DialogPanel/VBox/TextLabel")
	t_tag.call("_advance")  # 快进句1
	check_eq(String(dtext.text), D1_FIRST, "名牌：句1 全文正确")
	t_tag.call("_advance")  # → 句2（晷：在路上。）
	await process_frame
	check(ntl.visible and not ntr.visible, "名牌：句2（晷）左显右隐（轮切换）")
	t_tag.call("_advance")  # 快进句2
	check_eq(String(dtext.text), "在路上。", "名牌：句2 全文=在路上。")
	t_tag.call("_advance")  # → 句3（我：哪儿的路上？）
	await process_frame
	check(ntr.visible and not ntl.visible, "名牌：句3（我）右显左隐（来回交替）")
	# 非法 speaker 合成行：两名牌皆隐（防御保留）
	var synth: Array = [{"speaker": "路人", "text": "合成"}]
	t_tag.set("_lines", synth)
	t_tag.call("_show_line", 0)
	await process_frame
	check(not ntl.visible and not ntr.visible, "名牌：非法 speaker 合成行两名牌皆隐（防御）")
	await _drop(t_tag)

	# ---- 11. 气泡文件（Y-B6/Y-C8 文件域）----
	var b1: Variant = _load_json(DOC_DIR + "气泡_第1关.json")
	check(b1 is Dictionary, "气泡_第1关.json 可解析")
	if b1 is Dictionary:
		var bl: Array = (b1 as Dictionary).get("lines", [])
		check_eq(bl.size(), 12, "气泡_第1关：12 条（用户提供文案）")
		if bl.size() == 12:
			check_eq(String(bl[0]), "别急。木头比人实在——你怎么待它，它就怎么待你。", "气泡_第1关：首条逐字锚点")
			check_eq(String(bl[11]), "方才那一下……你真没想起什么？罢了，逼你也没用", "气泡_第1关：末条逐字锚点（句尾无句号原样保留）")
	# 第 2 关**正式文案**已由用户提供并入库（2026-09-27，铁律 8）——该关断言从「占位重写口径」
	# 升级为**正式文案锚点**（轮数/句数/首末句/章 2 独有「衣橱」提及逐字）。
	# 批次 AF（2026-11-01）：第 3~5 关占位稿亦由用户正式文案替换并注入英文字段——「占位待
	# 替换」正断言改**反向锁**（零命中）、区间判据保留为下限护栏、精确锚点与英文字段护栏
	# 见下方 11b 统一护栏环；原「第 3~5 关气泡条数两两互异」随正式文案退役（读码依据：三关
	# 实况条数同为 16，互异判据恒假——机械解析实况 [16,16,16]），替换为逐关精确锚点。
	# 第 2 关正式锚点（机械解析自查值，2026-09-27 用户定稿）
	check_eq(D2_ROUNDS, 18, "第2关：正式文案轮数锚点常量自检（18）")
	check_eq(D2_SENTS, 51, "第2关：正式文案句数锚点常量自检（51）")
	var b2: Variant = _load_json(DOC_DIR + BUBBLE_FILES[1])
	check(b2 is Dictionary, "气泡_第2关.json 可解析")
	if b2 is Dictionary:
		var l2: Array = (b2 as Dictionary).get("lines", [])
		check_eq(l2.size(), D2_BUBBLES, "气泡_第2关：正式文案 %d 条（用户提供，铁律 8）" % D2_BUBBLES)
		if l2.size() == D2_BUBBLES:
			check_eq(String(l2[0]), D2_BUBBLE_FIRST, "气泡_第2关：首条逐字锚点（正式文案）")
			check_eq(String(l2[D2_BUBBLES - 1]), D2_BUBBLE_LAST, "气泡_第2关：末条逐字锚点（正式文案）")
		var note_b2: Variant = (b2 as Dictionary).get("_说明")
		check(note_b2 is Array and not JSON.stringify(note_b2).contains("占位待替换"),
			"气泡_第2关：_说明 已去占位标注（正式文案入库，铁律 8）")
		var has_closet := false
		for lb: Variant in l2:
			if String(lb).contains("衣橱"):
				has_closet = true
		check(has_closet, "气泡_第2关：正式文案提及「衣橱」（§4.9 改名同源口径）")
	for k: int in range(3, 6):
		var bk: Variant = _load_json(DOC_DIR + BUBBLE_FILES[k - 1])
		check(bk is Dictionary, "%s 可解析" % BUBBLE_FILES[k - 1])
		if bk is Dictionary:
			var lk: Array = (bk as Dictionary).get("lines", [])
			check(lk.size() >= 5, "%s 正式文案 ≥5 条（下限护栏保留；实测 %d）" % [BUBBLE_FILES[k - 1], lk.size()])
			var note: Variant = (bk as Dictionary).get("_说明")
			check(note is Array and not (note as Array).is_empty() and not JSON.stringify(note).contains("占位待替换"),
				"%s _说明 零「占位待替换」（正式文案反向锁，AF）" % BUBBLE_FILES[k - 1])
	# 第 2 关正式文案锚点（首轮/末轮/首句/末句逐字）+ 三关占位轮数口径
	var d2r: Variant = _load_json(DOC_DIR + DOC_FILES[1])
	check(d2r is Dictionary, "第2关.json 可解析（正式文案锚点段）")
	if d2r is Dictionary:
		var rounds2: Array = (d2r as Dictionary).get("rounds", [])
		check_eq(rounds2.size(), D2_ROUNDS, "第2关：正式文案轮数==%d" % D2_ROUNDS)
		var sents2 := 0
		for rr3: Variant in rounds2:
			if rr3 is Dictionary and (rr3 as Dictionary).get("texts") is Array:
				sents2 += ((rr3 as Dictionary)["texts"] as Array).size()
		check_eq(sents2, D2_SENTS, "第2关：正式文案句数==%d" % D2_SENTS)
		if rounds2.size() == D2_ROUNDS:
			check_eq(String((rounds2[0] as Dictionary).get("speaker", "")), SP_ME, "第2关：首轮 speaker=我")
			var t0_2: Variant = (rounds2[0] as Dictionary).get("texts")
			check(t0_2 is Array and (t0_2 as Array).size() >= 1 and String((t0_2 as Array)[0]) == D2_FIRST,
				"第2关：首句逐字锚点（正式文案）")
			check_eq(String((rounds2[D2_ROUNDS - 1] as Dictionary).get("speaker", "")), SP_GUI, "第2关：末轮 speaker=晷")
			var te2: Variant = (rounds2[D2_ROUNDS - 1] as Dictionary).get("texts")
			check(te2 is Array and (te2 as Array).size() >= 1
				and String((te2 as Array)[te2.size() - 1]) == D2_LAST,
				"第2关：末句逐字锚点（正式文案，入宋）")
		var note_d2: Variant = (d2r as Dictionary).get("_说明")
		check(note_d2 is Array and not JSON.stringify(note_d2).contains("占位待替换"),
			"第2关：_说明 已去占位标注（正式文案入库，铁律 8）")
		# 「衣橱」改名同源：正式文案在剧情中提及「衣橱」（与 §4.9 UI 改名口径一致）
		var d2_txt: String = FileAccess.get_file_as_string(DOC_DIR + DOC_FILES[1])
		check(d2_txt.contains("衣橱"), "第2关：正式文案含「衣橱」字样（§4.9 改名同源）")
	# 批次 AF：第 3~5 关对话已由用户正式文案替换——6~12 轮区间护栏保留（实况 7/10/11 仍在带内），
	# 「占位待替换」正断言改反向锁；精确锚点（7/17、10/26、11/27）见 11b 统一护栏环。
	var dialog_round_counts: Array = []
	for k2: int in range(3, 6):
		var dk: Variant = _load_json(DOC_DIR + DOC_FILES[k2 - 1])
		check(dk is Dictionary, "%s 可解析" % DOC_FILES[k2 - 1])
		if dk is Dictionary:
			var rk: Array = (dk as Dictionary).get("rounds", [])
			check(rk.size() >= 6 and rk.size() <= 12, "%s 轮数 6~12 区间护栏（实况 %d 在带内）" % [DOC_FILES[k2 - 1], rk.size()])
			dialog_round_counts.append(rk.size())
			var has_multi := false
			for rr2: Variant in rk:
				if rr2 is Dictionary and (rr2 as Dictionary).get("texts") is Array \
						and ((rr2 as Dictionary)["texts"] as Array).size() >= 2:
					has_multi = true
			check(has_multi, "%s 至少一轮同 speaker 连说 ≥2 句（连点多次走完一轮用例）" % DOC_FILES[k2 - 1])
			var note2: Variant = (dk as Dictionary).get("_说明")
			check(note2 is Array and not JSON.stringify(note2).contains("占位待替换"),
				"%s _说明 零「占位待替换」（正式文案反向锁，AF）" % DOC_FILES[k2 - 1])
	var duniq: Dictionary = {}
	for dc: Variant in dialog_round_counts:
		duniq[dc] = true
	check_eq(duniq.size(), dialog_round_counts.size(), "第 3~5 关对话轮数两两互异（%s）" % str(dialog_round_counts))

	# ---- 11b. 批次 AF（2026-11-01）：全 5 关统一护栏——正式锚点 + 英文字段 + 占位反向锁 ----
	# 盘上实况（机械解析自查唯一真相）：轮数 44/18/7/10/11、句数 51/51/17/26/27、气泡条数
	# 12/16/16/16/16；每轮 speaker_en∈{Gui,I} 与 speaker 合法配对（晷↔Gui、我↔I）、texts_en
	# 与 texts 逐轮等长且全为字符串；气泡 lines_en 与 lines 逐条等长。断言只增不减。
	var af_rounds := {1: D1_ROUNDS, 2: D2_ROUNDS, 3: D3_ROUNDS, 4: D4_ROUNDS, 5: D5_ROUNDS}
	var af_sents := {1: D1_SENTS, 2: D2_SENTS, 3: D3_SENTS, 4: D4_SENTS, 5: D5_SENTS}
	for k3: int in range(1, 6):
		var daf: Variant = _load_json(DOC_DIR + DOC_FILES[k3 - 1])
		check(daf is Dictionary, "AF：%s 可解析（11b 统一护栏）" % DOC_FILES[k3 - 1])
		if daf is Dictionary:
			var raf: Array = (daf as Dictionary).get("rounds", [])
			check_eq(raf.size(), int(af_rounds[k3]), "AF：%s 轮数==%d（正式锚点）" % [DOC_FILES[k3 - 1], int(af_rounds[k3])])
			var saf := 0
			var pair_ok := true
			var en_len_ok := true
			var en_str_ok := true
			for raf_r: Variant in raf:
				if not (raf_r is Dictionary):
					continue
				var rd: Dictionary = raf_r as Dictionary
				var sp := String(rd.get("speaker", ""))
				var spe := String(rd.get("speaker_en", ""))
				if not ((sp == SP_GUI and spe == SP_EN_GUI) or (sp == SP_ME and spe == SP_EN_ME)):
					pair_ok = false
				var tv: Variant = rd.get("texts", [])
				var ev: Variant = rd.get("texts_en", [])
				if not (tv is Array and ev is Array and (ev as Array).size() == (tv as Array).size()):
					en_len_ok = false
				else:
					for es: Variant in (ev as Array):
						if not (es is String):
							en_str_ok = false
				if tv is Array:
					saf += (tv as Array).size()
			check_eq(saf, int(af_sents[k3]), "AF：%s 句数==%d（正式锚点）" % [DOC_FILES[k3 - 1], int(af_sents[k3])])
			check(pair_ok, "AF：%s 全轮 speaker/speaker_en 合法配对（晷↔Gui、我↔I）" % DOC_FILES[k3 - 1])
			check(en_len_ok, "AF：%s 全轮 texts_en 与 texts 逐轮等长" % DOC_FILES[k3 - 1])
			check(en_str_ok, "AF：%s texts_en 全为字符串" % DOC_FILES[k3 - 1])
	# 英文逐字锚点：第 1/2 关末句 texts_en（正式文案英译入库事实锁定；em-dash U+2014 已逐字节核验）
	var d1e: Variant = _load_json(DOC_DIR + DOC_FILES[0])
	if d1e is Dictionary:
		var r1e: Array = (d1e as Dictionary).get("rounds", [])
		if r1e.size() == D1_ROUNDS:
			var te1e: Variant = (r1e[D1_ROUNDS - 1] as Dictionary).get("texts_en", [])
			check(te1e is Array and (te1e as Array).size() >= 1 \
					and String((te1e as Array)[(te1e as Array).size() - 1]) == D1_LAST_EN,
				"AF：第1关 末句 texts_en 逐字锚点")
	var d2e: Variant = _load_json(DOC_DIR + DOC_FILES[1])
	if d2e is Dictionary:
		var r2e: Array = (d2e as Dictionary).get("rounds", [])
		if r2e.size() == D2_ROUNDS:
			var te2e: Variant = (r2e[D2_ROUNDS - 1] as Dictionary).get("texts_en", [])
			check(te2e is Array and (te2e as Array).size() >= 1 \
					and String((te2e as Array)[(te2e as Array).size() - 1]) == D2_LAST_EN,
				"AF：第2关 末句 texts_en 逐字锚点（入宋）")
	# 气泡统一护栏：5 件全查——条数锚点（第 1 关 12、第 2~5 关 16）+ 占位反向锁 + lines_en 等长全字符串
	var af_bubble_counts := {1: 12, 2: AF_BUBBLES, 3: AF_BUBBLES, 4: AF_BUBBLES, 5: AF_BUBBLES}
	for k4: int in range(1, 6):
		var baf: Variant = _load_json(DOC_DIR + BUBBLE_FILES[k4 - 1])
		check(baf is Dictionary, "AF：%s 可解析（11b 气泡护栏）" % BUBBLE_FILES[k4 - 1])
		if baf is Dictionary:
			var lf: Array = (baf as Dictionary).get("lines", [])
			check_eq(lf.size(), int(af_bubble_counts[k4]), "AF：%s 条数==%d（正式锚点）" % [BUBBLE_FILES[k4 - 1], int(af_bubble_counts[k4])])
			var nb: Variant = (baf as Dictionary).get("_说明")
			check(nb is Array and not JSON.stringify(nb).contains("占位待替换"),
				"AF：%s _说明 零「占位待替换」（反向锁）" % BUBBLE_FILES[k4 - 1])
			var lev: Variant = (baf as Dictionary).get("lines_en", [])
			var blen_ok: bool = lev is Array and (lev as Array).size() == lf.size()
			var bstr_ok := true
			if blen_ok:
				for bs: Variant in (lev as Array):
					if not (bs is String):
						bstr_ok = false
			check(blen_ok, "AF：%s lines_en 与 lines 逐条等长" % BUBBLE_FILES[k4 - 1])
			check(bstr_ok, "AF：%s lines_en 全为字符串" % BUBBLE_FILES[k4 - 1])

	# ---- 12. 接口文档案例可直接通过解析器（Y-B5：文档与实现一致）----
	var ws_root: String = ProjectSettings.globalize_path("res://")
	var doc_abs: String = (ws_root + "../../技术文档/接口规范_剧情对话.md").simplify_path()
	var doc_txt: String = _read_text(doc_abs)
	check(doc_txt.length() > 0, "Y-B5：接口规范_剧情对话.md 可读（%s）" % doc_abs)
	if doc_txt.length() > 0:
		check(doc_txt.contains("合法 speaker") and doc_txt.contains("立绘"), "Y-B5：接口文档含 speaker/立绘要素")
		var i_open: int = doc_txt.find("```json")
		var has_case := false
		if i_open >= 0:
			var body_start: int = i_open + String("```json").length()
			var i_close: int = doc_txt.find("```", body_start)
			if i_close > body_start:
				var case_parsed: Variant = JSON.parse_string(doc_txt.substr(body_start, i_close - body_start))
				var t_case: Control = await _new_talk({"mode": "opening", "chapter": 1})
				var via: Variant = _parse_via(t_case, case_parsed, "<接口文档案例>")
				if via is Array:
					has_case = (via as Array).size() >= 1
					for line_v: Variant in (via as Array):
						var spv := String((line_v as Dictionary).get("speaker", ""))
						if spv != SP_GUI and spv != SP_ME:
							has_case = false
				await _drop(t_case)
		check(has_case, "Y-B5：接口文档首个 json 案例经解析器全收且 speaker 合法（文档与实现一致）")

	# 清理临时文件
	for nm: String in ["y4_case.json", "y4_comment.json", "y4_arr.json", "y4_order.json", "y4_long.json"]:
		_del_user(nm)

	# ---- 13. §14⑤ 验收：对话首句逐字（生产链口径，先于推进断言不依赖控制器状态）----
	var d1_head: Variant = _load_json(DOC_DIR + "第1关.json")
	check(d1_head is Dictionary, "§14③：第1关.json 可解析（首句验收锚）")
	if d1_head is Dictionary:
		var rr: Array = (d1_head as Dictionary).get("rounds", [])
		check(rr.size() > 0 and (rr[0] as Dictionary).get("texts") is Array \
			and ((rr[0] as Dictionary)["texts"] as Array).size() > 0 \
			and String(((rr[0] as Dictionary)["texts"] as Array)[0]) == D1_FIRST,
			"§14③：对话首句逐字==「等——这是哪儿？刚才还站着，一眨眼，满天是光。」")

	_cleanup_save()
	finish()

func _cleanup_save() -> void:
	var abs_save: String = ProjectSettings.globalize_path(SAVE_PATH)
	if FileAccess.file_exists(abs_save):
		DirAccess.remove_absolute(abs_save)
