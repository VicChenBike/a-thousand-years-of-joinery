extends "res://tests/test_base.gd"
## 批次 V-D（2026-09-19 规格 §8 方案 F 存档域 / V17+V18）——TDD 红测先行。
## 契约来源：批次 V 规格 §8.1/§8.3 + §6.2 三设置键（本路只做存档域；main.gd 退出兜底与
## main_menu 判据替换归后续路，本测试零触碰）。四块口径：
##   ①原子写（§8.1）：save_game 重写为编辑器 level_slots.gd:168-191 同构 Windows 安全序——
##     写同目录 tmp → rename 覆盖 save.json → rename 失败时旧档改名 .bak 腾位 → rename tmp →
##     成功清 .bak / 失败回滚 .bak；任何路径不留半截档。
##     探针实证（tests/_vd_probe_fs.gd，2026-09-19）：本 Godot 4.7 构建 rename_absolute 可覆盖
##     已存在文件（RENAME_OVER_FILE err=0）→ 正常保存走直换路径；rename 失败面=目标被目录
##     占位（RENAME_TO_DIR err=1）/目标被句柄锁定（RENAME_OVER_LOCKED err=1）。据此注入：
##     A=tmp 被目录占位（写 tmp 失败）、B=save.json 被句柄锁定（rename 失败→.bak 腾位亦失败
##     →放弃本次写）、C=save.json 被同名目录占位（编辑器 P2-4 同款早退）→ 均返回 false 且
##     旧档内容未动。回滚分支（.bak 腾位成功后 rename 仍失败）无确定性无头注入面，与编辑器
##     先例一致由代码审查覆盖。
##   ②损坏档载入回落：截断/半截/空文件/合法 JSON 缺 settings 键 → 不炸、内存回落默认档、
##     磁盘原文件不删不改写（4.7 坑 2：dict 取键一律 .get 防御——缺 settings 键手写档在
##     旧实现会无效下标中止 _initialize，本组断言锁定容器防御）。
##   ③has_any_progress()（§8.3）：三分支真值表（仅 flag/仅 watched/仅 cleared/全无/组合），
##     且每态与 can_open_catalog() 等值（同源判据锁；供后续路替换主菜单 is_first_launch 单判据）。
##   ④三新键防御（§6.2，派遣口径 V-D）：gesture_camera_device(String,"") /
##     gesture_camera_res(String,"") / gesture_camera_fps(int,0)——默认档含三键、错型回落
##     缺省（fps 接受 int/float：JSON 往返数字恒 float，int() 归一；字符串/布尔等非法回落 0）、
##     合法值落盘往返、update_settings 合并对三键透明（其余设置键/volume 嵌套合并不受扰）。
## 清档纪律（tools/README_走查清档规范.md）：起测前备份 user:// 真实档案（save.json/flag 及
##   本测试可触及的 .tmp/.bak 全四件），终测还原并打印 EVID 证据行；真实 autoload SaveManager
##   若在树则 load_game 重同步内存（防退出写回污染，规范第 2 条）。零摄像头。

const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"
const SM_SCRIPT := "res://autoload/save_manager.gd"
# 备份路径必须带全 user:// 前缀（test_n10 先例）——实测相对路径在 FileAccess/DirAccess 间
# 解析不一致（copy 落工程根进程 cwd、file_exists 又随 API 漂移），前缀缺失=备份链静默失效。
const BK_PREFIX := "user://_vd_backup_"
# 走查规范备份四件组（含测试可自建的 tmp/bak，还原后 user:// 与起测前逐字节等价）
const WATCHED_PATHS: Array = [SAVE_PATH, FLAG_PATH, TMP_PATH, BAK_PATH]

var _sm_seq: int = 0
var _pre_save_text: String = ""  # 起测前真实 save.json 原文（还原等价自检基准）

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

func _backup_user() -> void:
	# 规范第 1 条：任何删/写档操作之前备份真实档案（test_n10_catalog_gate 先例，全 user:// 路径）
	if FileAccess.file_exists(SAVE_PATH):
		_pre_save_text = _read_file(SAVE_PATH)
	for p: String in WATCHED_PATHS:
		if FileAccess.file_exists(p):
			var bk := BK_PREFIX + p.get_file()
			DirAccess.copy_absolute(_abs(p), _abs(bk))
			check(FileAccess.file_exists(bk), "备份落位自检：%s" % bk)

func _restore_user() -> void:
	# 规范第 2 条：所有退出路径统一收口还原；还原后真实 autoload load_game 重同步内存
	for p: String in WATCHED_PATHS:
		_del(p)
		var bk := BK_PREFIX + p.get_file()
		if FileAccess.file_exists(bk):
			DirAccess.copy_absolute(_abs(bk), _abs(p))
			DirAccess.remove_absolute(_abs(bk))
	var real_sm: Node = root.get_node_or_null(NodePath("SaveManager"))
	if real_sm != null:
		real_sm.load_game()  # 防进程退出 close_requested → save_game 把测试态写回真实档案
	# 纪律自检：还原后 save.json 与起测前逐字节等价（起测前无档 ↔ 还原后无档）
	var post: String = _read_file(SAVE_PATH) if FileAccess.file_exists(SAVE_PATH) else ""
	check_eq(post, _pre_save_text, "清档纪律：user://save.json 起测前/终测还原逐字节等价")
	print("EVID|user_restore|save_domain|files=%d" % WATCHED_PATHS.size())

func _rm_dir_tree(p: String) -> void:
	# 测试自建目录占位桩清理（先清内件再清目录；best-effort）
	var inner := _abs(p) + "/stub.txt"
	if FileAccess.file_exists(inner):
		DirAccess.remove_absolute(inner)
	if DirAccess.dir_exists_absolute(_abs(p)):
		DirAccess.remove_absolute(_abs(p))

func _new_sm() -> Node:
	# 独立实例先例（test_save_manager/test_n9）：--script 无头 autoload _ready 不触发，
	# add_child 后显式 load_game 初始化 _data
	_sm_seq += 1
	var sm: Node = (load(SM_SCRIPT) as GDScript).new()
	sm.name = "SM_VD_%d" % _sm_seq
	get_root().add_child(sm)
	sm.load_game()
	return sm

func _default_progress(cleared: Array, watched: bool) -> Dictionary:
	return {"cleared": cleared, "next_chapter": 1, "watched_opening": watched, "level_progress": {}}

func _initialize() -> void:
	print("== test_v_save_domain ==")
	_backup_user()
	for p: String in WATCHED_PATHS:
		_del(p)  # 沙盒基线：真实档案已备份，测试域内四件全清

	# ===== 一、原子写·正常序（可观测行为；本组多为等价守卫，红测由②③④段承担） =====
	var sm: Node = _new_sm()
	check_eq(sm.save_game(), true, "V-D：save_game 返回 true（首次保存，无旧档）")
	check(FileAccess.file_exists(SAVE_PATH), "首次保存后 save.json 落盘")
	check(not FileAccess.file_exists(TMP_PATH), "首次保存后无 .tmp 残留")
	check(not FileAccess.file_exists(BAK_PATH), "首次保存后无 .bak 残留")
	check(JSON.parse_string(_read_file(SAVE_PATH)) is Dictionary, "落盘为完整可解析 JSON（无半截档）")
	# 二次保存：本 Godot 4.7 实证 rename_absolute 可覆盖已存在文件（tests/_vd_probe_fs.gd 探针
	# RENAME_OVER_FILE err=0）→ 直换路径不产生 .bak；.bak 腾位序仅在 rename 失败（目录占位/
	# 句柄锁定等）时启用（见下方注入 B/C）。无论何路径，成功后均无 .tmp/.bak 残留。
	sm.add_talent(64)  # 500→564（内部变更即存一次，落盘路径同经原子序）
	check_eq(sm.save_game(), true, "二次保存（旧档已存在）返回 true")
	check(not FileAccess.file_exists(TMP_PATH), "二次保存后无 .tmp 残留")
	check(not FileAccess.file_exists(BAK_PATH), "二次保存后无 .bak 残留（成功路径零残留）")
	var sm2: Node = _new_sm()
	check_eq(sm2.get_talent(), 564, "二次保存内容已更新（重载 500+64=564）")

	# ===== 二、原子写·失败注入（旧档保全红线；探针 _vd_probe_fs.gd 实证语义） =====
	# 注入 A：save.json.tmp 被目录占位 → tmp 写失败（FileAccess.open(目录)=null）→
	# 放弃本次写（旧档未动）。变更经 get_progress() 活引用纯内存修改（不触发自动保存，
	# 防内部保存先消费注入桩——add_talent 系变更即存，红调试实测会自愈清桩）。
	sm.save_game()  # 磁盘=内存基线对齐（talent 564）
	var old_text: String = _read_file(SAVE_PATH)
	DirAccess.make_dir_recursive_absolute(_abs(TMP_PATH))
	var p_ref: Dictionary = sm.get_progress()
	p_ref["next_chapter"] = 2  # 纯内存变更，不落盘
	check_eq(sm.save_game(), false, "注入A：tmp 被目录占位 → save_game 返回 false")
	check_eq(_read_file(SAVE_PATH), old_text, "注入A：旧档内容未动（保全红线）")
	_rm_dir_tree(TMP_PATH)
	# 注入 B：save.json 被占用句柄锁定（Windows 共享 violation，探针 RENAME_OVER_LOCKED err=1）
	# → rename 覆盖失败 → .bak 腾位序 rename 旧档亦失败 → 放弃本次写（旧档未动、tmp 清理）
	old_text = _read_file(SAVE_PATH)
	var lock: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	check(lock != null, "注入B 前置：旧档句柄已打开（锁定源）")
	var p_ref2: Dictionary = sm.get_progress()
	p_ref2["next_chapter"] = 3
	check_eq(sm.save_game(), false, "注入B：旧档被句柄锁定 → save_game 返回 false")
	check_eq(_read_file(SAVE_PATH), old_text, "注入B：旧档内容未动（保全红线）")
	check(not FileAccess.file_exists(TMP_PATH), "注入B：tmp 残留已清理（不留半截档）")
	if lock != null:
		lock.close()
	# 注入 C：save.json 被同名目录占位（编辑器 P2-4 同款）→ 确定性 false（早退未写 tmp）
	_del(SAVE_PATH)
	DirAccess.make_dir_recursive_absolute(_abs(SAVE_PATH))
	var p_ref3: Dictionary = sm.get_progress()
	p_ref3["next_chapter"] = 4
	check_eq(sm.save_game(), false, "注入C：save.json 被同名目录占位 → save_game 返回 false")
	check(not FileAccess.file_exists(TMP_PATH), "注入C：无 tmp 残留（早退未写 tmp）")
	DirAccess.remove_absolute(_abs(SAVE_PATH))  # 清空目录占位
	# 注入解除后自愈：正常保存恢复
	check_eq(sm.save_game(), true, "注入解除后保存恢复 true")

	# ===== 三、损坏档载入回落（不炸/回落默认档/原文件不删不改写） =====
	sm.save_game()
	var good_text: String = _read_file(SAVE_PATH)
	# 3a 截断档（合法 JSON 前半截）
	var truncated: String = good_text.substr(0, good_text.length() / 2)
	_write_file(SAVE_PATH, truncated)
	var sm3: Node = _new_sm()
	check_eq(sm3.get_talent(), 500, "截断档载入回落默认档（天赋 500）")
	check(FileAccess.file_exists(SAVE_PATH), "损坏档载入不删除原文件")
	check_eq(_read_file(SAVE_PATH), truncated, "损坏档载入不改写原文件内容")
	# 3b 空文件
	_write_file(SAVE_PATH, "")
	var sm4: Node = _new_sm()
	check_eq(sm4.get_talent(), 500, "空文件载入回落默认档")
	# 3c 半截 JSON（合法 JSON 中途截断，parse 失败）
	_write_file(SAVE_PATH, "{ \"save_version\": 2, \"talent\":")
	var sm5: Node = _new_sm()
	check_eq(sm5.get_talent(), 500, "半截 JSON 不炸、回落默认档")
	# 3d 非字典 JSON
	_write_file(SAVE_PATH, "12345")
	var sm6: Node = _new_sm()
	check_eq(sm6.get_talent(), 500, "非字典 JSON 回落默认档")
	# 3e 损坏档之后可正常再保存（原子写自愈，落盘完整）
	check_eq(sm5.save_game(), true, "损坏档后保存成功（自愈）")
	check(JSON.parse_string(_read_file(SAVE_PATH)) is Dictionary, "再保存后档完整可解析")

	# ===== 四、has_any_progress 三分支真值表（§8.3；每态与 can_open_catalog 同源等值） =====
	# 每组合前双删（flag+save）显式清场——组合态互不污染（组合 3/4/6 必须无 flag 才真验分支②③）
	# 组合1 全无（新档：无 flag + watched false + cleared 空）→ false
	_del(SAVE_PATH)
	_del(FLAG_PATH)
	var c1: Node = _new_sm()
	check_eq(c1.has_any_progress(), false, "真值表：全无 → false")
	check_eq(c1.can_open_catalog(), c1.has_any_progress(), "同源锁：全无态 can_open_catalog==has_any_progress")
	# 组合2 仅 flag → true
	_del(SAVE_PATH)
	_del(FLAG_PATH)
	var c2: Node = _new_sm()
	c2.mark_first_launch()
	check_eq(c2.has_any_progress(), true, "真值表：仅 flag → true")
	check_eq(c2.can_open_catalog(), c2.has_any_progress(), "同源锁：仅 flag 态")
	# 组合3 仅 watched_opening → true
	_del(SAVE_PATH)
	_del(FLAG_PATH)
	_write_file(SAVE_PATH, JSON.stringify({"save_version": 2, "progress": _default_progress([], true)}))
	var c3: Node = _new_sm()
	check_eq(c3.has_any_progress(), true, "真值表：仅 watched_opening → true")
	check_eq(c3.can_open_catalog(), c3.has_any_progress(), "同源锁：仅 watched 态")
	# 组合4 仅 cleared 非空 → true
	_del(SAVE_PATH)
	_del(FLAG_PATH)
	_write_file(SAVE_PATH, JSON.stringify({"save_version": 2, "progress": _default_progress([3], false)}))
	var c4: Node = _new_sm()
	check_eq(c4.has_any_progress(), true, "真值表：仅 cleared 非空 → true")
	check_eq(c4.can_open_catalog(), c4.has_any_progress(), "同源锁：仅 cleared 态")
	# 组合5 组合（flag+watched+cleared）→ true
	_del(SAVE_PATH)
	_del(FLAG_PATH)
	_write_file(SAVE_PATH, JSON.stringify({"save_version": 2, "progress": _default_progress([1, 2], true)}))
	var c5: Node = _new_sm()
	c5.mark_first_launch()
	check_eq(c5.has_any_progress(), true, "真值表：三者组合 → true")
	check_eq(c5.can_open_catalog(), c5.has_any_progress(), "同源锁：组合态")
	# 组合6 显式反例（watched=false + cleared 空 + 无 flag）→ false
	_del(SAVE_PATH)
	_del(FLAG_PATH)
	_write_file(SAVE_PATH, JSON.stringify({"save_version": 2, "progress": _default_progress([], false)}))
	var c6: Node = _new_sm()
	check_eq(c6.has_any_progress(), false, "真值表：watched=false 且 cleared 空 且无 flag → false")
	check_eq(c6.can_open_catalog(), c6.has_any_progress(), "同源锁：反例态")

	# ===== 五、三新键防御（§6.2 派遣口径：device/res=String("")、fps=int(0)） =====
	# 5a 默认档三键缺省值与类型
	var d1: Node = _new_sm()
	var s1: Dictionary = d1.get_settings()
	check_eq(String(s1.get("gesture_camera_device", "<键缺失>")), "", "默认档 gesture_camera_device=\"\"")
	check_eq(String(s1.get("gesture_camera_res", "<键缺失>")), "", "默认档 gesture_camera_res=\"\"")
	check_eq(int(s1.get("gesture_camera_fps", -999)), 0, "默认档 gesture_camera_fps=0")
	check_eq(typeof(s1.get("gesture_camera_device")), TYPE_STRING, "默认档 device 类型 String")
	check_eq(typeof(s1.get("gesture_camera_res")), TYPE_STRING, "默认档 res 类型 String")
	check_eq(typeof(s1.get("gesture_camera_fps")), TYPE_INT, "默认档 fps 类型 int")
	# 5b 错型回落缺省（手写档：device=123 / res=true / fps="30"）
	_write_file(SAVE_PATH, JSON.stringify({
		"save_version": 2,
		"settings": {"gesture_camera_device": 123, "gesture_camera_res": true, "gesture_camera_fps": "30"},
	}))
	var d2: Node = _new_sm()
	var s2: Dictionary = d2.get_settings()
	check_eq(String(s2.get("gesture_camera_device", "<键缺失>")), "", "错型 device(123) 回落缺省 \"\"")
	check_eq(String(s2.get("gesture_camera_res", "<键缺失>")), "", "错型 res(true) 回落缺省 \"\"")
	check_eq(int(s2.get("gesture_camera_fps", -999)), 0, "错型 fps(\"30\") 回落缺省 0")
	# 5c fps 浮点往返（JSON 数字恒 float：30 → 30.0 → 归一 int 30）
	_write_file(SAVE_PATH, JSON.stringify({
		"save_version": 2,
		"settings": {"gesture_camera_fps": 30},
	}))
	var d3: Node = _new_sm()
	var s3: Dictionary = d3.get_settings()
	check_eq(int(s3.get("gesture_camera_fps", -999)), 30, "fps JSON float 往返归一 30")
	check_eq(typeof(s3.get("gesture_camera_fps")), TYPE_INT, "fps 往返后类型 int（非 float）")
	# 5d 合法值落盘往返（经默认档全量 settings 基线——模拟真实游戏写档路径；5c 手写部分
	# settings 档仅用于 fps float 归一断言，不带全量键，勿作本段基线）
	_del(SAVE_PATH)
	_del(FLAG_PATH)
	d3 = _new_sm()
	d3.update_settings({"gesture_camera_device": "1", "gesture_camera_res": "1280x720", "gesture_camera_fps": 30})
	var d4: Node = _new_sm()
	var s4: Dictionary = d4.get_settings()
	check_eq(String(s4.get("gesture_camera_device", "")), "1", "合法 device 往返=\"1\"")
	check_eq(String(s4.get("gesture_camera_res", "")), "1280x720", "合法 res 往返=\"1280x720\"")
	check_eq(int(s4.get("gesture_camera_fps", -999)), 30, "合法 fps 往返=30")
	# 5e update_settings 合并对三键透明（其余键不受扰 + volume 嵌套合并语义保持）
	d4.update_settings({"gesture_camera_device": "2"})
	var s5: Dictionary = d4.get_settings()
	check_eq(String(s5.get("gesture_camera_device", "")), "2", "合并路径：device 单键更新")
	check_eq(String(s5.get("gesture_camera_res", "")), "1280x720", "合并路径：res 不受扰")
	check_eq(bool(s5.get("gesture_input", false)), true, "合并路径：既有键 gesture_input 不受扰")
	d4.update_settings({"volume": {"master": 0.5}})
	var s6: Dictionary = d4.get_settings()
	check_eq(float((s6.get("volume", {}) as Dictionary).get("music", -1.0)), 1.0, "合并路径：volume 嵌套合并只改 master")
	check_eq(float((s6.get("volume", {}) as Dictionary).get("master", -1.0)), 0.5, "合并路径：volume.master 更新生效")
	# 5f 陌生键共存不炸（载入归一对未知键不误伤三键；处置口径=保守保留，见文件头注）
	_write_file(SAVE_PATH, JSON.stringify({
		"save_version": 2,
		"settings": {"future_key": {"a": 1}, "gesture_camera_device": "3"},
	}))
	var d5: Node = _new_sm()
	var s7: Dictionary = d5.get_settings()
	check_eq(String(s7.get("gesture_camera_device", "")), "3", "陌生键共存：三键归一不受扰")

	# ===== 六、合法 JSON 缺 settings 键（4.7 坑 2 容器防御；置于末段——旧实现在此中止 _initialize） =====
	_write_file(SAVE_PATH, JSON.stringify({
		"save_version": 2,
		"progress": _default_progress([1], true),
		"talent": 320,
	}))
	var e1: Node = _new_sm()
	check_eq(e1.get_talent(), 320, "缺 settings 键：合法 JSON 其余字段保留（不中止）")
	check_eq(bool(e1.get_settings().get("gesture_input", false)), true, "缺 settings 键：设置整体回落默认档")
	check_eq(String(e1.get_settings().get("gesture_camera_device", "<键缺失>")), "", "缺 settings 键：三键随默认档回落")

	# ===== 收口：还原真实档案（规范第 2 条）+ 真实 autoload 重同步 =====
	_restore_user()
	finish()
