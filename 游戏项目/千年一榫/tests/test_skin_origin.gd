extends "res://tests/test_base.gd"
## K-D（批次 K，spec §7）判定用例：原创皮肤目录 + 解锁/穿戴链路无头测试（TDD 先写）。
## 覆盖 KD-2（SkinCatalog 扩展：①素材段/②目录段/③助手）与 KD-3（④首次进关链路，随本批转绿）。
## 契约来源：spec §7.1~7.4；plan KD-2/KD-3 断言清单。新增组件/新数据一律 load() 比较（P2-5）。
## 4.7 坑：--script 模式 class_name 注册有时序问题 → 目录经 load("res://data/skin_catalog.gd") 取 GDScript 动态调用。

const CATALOG := "res://data/skin_catalog.gd"
const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
# 原创 5 皮肤素材（spec §7.1 命名表）
const ORIGIN_TEXTURES := [
	"res://assets/skins/skin_origin_kaitou.png",
	"res://assets/skins/skin_origin_song.png",
	"res://assets/skins/skin_origin_yuan.png",
	"res://assets/skins/skin_origin_ming.png",
	"res://assets/skins/skin_origin_xiandai.png",
]

func _cleanup() -> void:
	var save_abs: String = ProjectSettings.globalize_path(SAVE_PATH)
	var flag_abs: String = ProjectSettings.globalize_path(FLAG_PATH)
	if FileAccess.file_exists(save_abs):
		DirAccess.remove_absolute(save_abs)
	if FileAccess.file_exists(flag_abs):
		DirAccess.remove_absolute(flag_abs)

## 读 res 路径文件前 4 字节（PNG 魔数校验，防 8a7575f 伪装坑）
func _head4(path: String) -> Array:
	var out: Array = []
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	for _i: int in range(4):
		out.append(f.get_8())
	f.close()
	return out

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
const DISC_BK_PREFIX := "user://_r2b_sko_backup_"
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
	print("EVID|user_restore|sko|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_skin_origin ==")
	_backup_user()
	_cleanup()

	# ---- ① 素材段：5 张原创皮肤素材存在且为真 PNG（头字节 89 50 4E 47）----
	for path: String in ORIGIN_TEXTURES:
		check(ResourceLoader.exists(path), "KD-2 素材存在：%s" % path)
		var head: Array = _head4(ProjectSettings.globalize_path(path))
		check(head.size() == 4 and head[0] == 0x89 and head[1] == 0x50 and head[2] == 0x4E and head[3] == 0x47,
			"KD-2 PNG 魔数校验通过：%s" % path)

	# ---- ② 目录段：get_skins() 头部置顶 5 原创（47 项），逐项 original/unlock_chapter/buyable/desc ----
	var cat: GDScript = load(CATALOG)
	check(cat != null, "KD-2 SkinCatalog 可加载")
	var skins: Array = cat.get_skins()
	check_eq(skins.size(), 47, "KD-2 目录共 47 个皮肤（5 原创 + 42 占位）")
	var expect_ids: Array = ["skin_origin_kaitou", "skin_origin_song", "skin_origin_yuan", "skin_origin_ming", "skin_origin_xiandai"]
	var expect_chapters: Array = [1, 2, 3, 4, 5]
	var head_ok: bool = skins.size() >= 5
	var desc_key_ok: bool = true
	for i: int in range(5):
		var s: Dictionary = skins[i]
		if String(s.get("id", "")) != String(expect_ids[i]):
			head_ok = false
		if bool(s.get("original", false)) != true:
			head_ok = false
		if int(s.get("unlock_chapter", -1)) != int(expect_chapters[i]):
			head_ok = false
		if bool(s.get("buyable", true)) != false:
			head_ok = false
		if not s.has("desc"):
			desc_key_ok = false
	check(head_ok, "KD-2 原创 5 项置顶顺序=开头/宋/元/明/现，且 original=true/unlock_chapter=1..5/buyable=false")
	check(desc_key_ok, "KD-2 原创项含 desc 键（神通谱文案位，spec §7.6）")
	# 其后仍为 skin_01..42（向后兼容：旧 42 项不变）—— 尺寸闸门防红灯期越界崩溃
	if skins.size() >= 47:
		check_eq(String(skins[5].get("id", "")), "skin_01", "KD-2 第 6 项为 skin_01（原创置顶其后接旧目录）")
		check_eq(String(skins[46].get("id", "")), "skin_42", "KD-2 末项为 skin_42（总数 47）")
		check_eq(int(skins[5].get("price", -1)), 0, "KD-2 skin_01 仍免费")
		check_eq(int(skins[11].get("price", -1)), 205, "KD-2 skin_07 仍付费 205")
	else:
		check(false, "KD-2 目录不足 47 项，向后兼容段无法校验")

	# ---- ③ 助手：get_origin_skin / is_origin —— has_method 闸门防红灯期崩溃 ----
	if cat.has_method("get_origin_skin") and cat.has_method("is_origin"):
		check_eq(String(cat.get_origin_skin(2).get("id", "")), "skin_origin_song", "KD-2 get_origin_skin(2)=skin_origin_song")
		check(cat.get_origin_skin(0).is_empty(), "KD-2 get_origin_skin(0) 返回空 Dictionary")
		check(cat.get_origin_skin(6).is_empty(), "KD-2 get_origin_skin(6) 超范围返回空 Dictionary")
		check_eq(String(cat.get_origin_skin(5).get("id", "")), "skin_origin_xiandai", "KD-2 get_origin_skin(5)=skin_origin_xiandai")
		check(cat.is_origin("skin_origin_ming"), "KD-2 is_origin(原创 id)=true")
		check(not cat.is_origin("skin_01"), "KD-2 is_origin(占位 id)=false")
	else:
		check(false, "KD-2 get_origin_skin/is_origin 助手未实现")

	# ---- ④ 首次进关链路（spec §7.3 点位① / §7.4：全新档直入第 2 关 → 宋皮肤已 owned 且 equipped）----
	# 直接调用 game.gd TALK/LEVEL 分支体内收口的同一对 API（先 unlock 再 apply），无需拉起完整状态机。
	_cleanup()
	var sm: Node = load("res://autoload/save_manager.gd").new()
	add_child(sm)
	sm.name = "SaveManagerOrigin"
	sm.reset_for_new_game()
	sm.load_game()
	sm.unlock_origin_skin(2)
	sm.apply_contextual_skin(2)
	var st: Dictionary = sm.get_skins()
	check((st["owned"] as Array).has("skin_origin_song"), "KD-3 链路：首次进第 2 关后宋皮肤已 owned")
	check_eq(String(st["equipped"]), "skin_origin_song", "KD-3 链路：进关自动穿戴宋皮肤")
	check_eq(String(st["preferred"]), "skin_origin_kaitou", "KD-3 链路：自动穿戴不动 preferred（仍为默认开头）")
	sm.free()

	_cleanup()
	finish()
