extends "res://tests/test_base.gd"
## 批次 W（W5）编辑器波新测试：P1-9 槽位根便携优先+用户目录回退、P2-4a 默认源健壮解析+显式提示、
## P1-10 探针（主视口左上 348×24 标题区是否真拦截——证伪结案）、P2-4d 探针·证伪结案（Target/Join
## 子视口更新模式系 SubViewportContainer 可见性引擎接管，tscn 值运行期不被治理）、
## P3-4c session_meta.json 原子写、P3-4e godot_mcp_runtime.gd 死常量/过时注释清理。
## TDD 红态定义：新 API 经 Script 动态派发（has_method 守卫——红期可编译零中止，test_v_editor_export
## 旧件同款手法）；editor_main 面向断言（状态栏/视口模式/按钮缺席）直接读节点。
## 磁盘纪律：沙盒一律 TEMP 一次性子目录（test_level_slots P7 裁决先例），真实 levels/ 与 user://
## 零触碰（_user_levels_root 仅派生路径不探测不落盘——测试对 user 候选只做字符串断言）。
## Godot 4.7 坑对齐：dict 取键 .get 防御、Variant 判空后强转、
## add_child 后 await process_frame。

const LS := preload("res://scripts/level_slots.gd")
const LP := preload("res://scripts/level_project.gd")
const FIXTURE := "res://tests/fixtures/level_chapter1_hemudu.json"
const MISSING_SOURCE := "res://tests/fixtures/__no_such_source.json"
const MCP_PLUGIN_PATH := "res://addons/godot_mcp_runtime/godot_mcp_runtime.gd"
const NOTE_TEXT := "内置示例不可用"   # P2-4a 状态栏显式提示（spec §6 措辞；完整文案含「未找到第 1 关模板，已用空骨架」事实句）

var _sandboxes: Array[String] = []
var _eds: Array = []
var _ls: Script = preload("res://scripts/level_slots.gd")   # 新 API 动态路由（红期可编译）

func _initialize() -> void:
	print("== test_w_editor（批次 W5：P1-9/P2-4a/P1-10 探针/P2-4d/P3-4c/P3-4e） ==")
	OS.set_environment("VOXEL_EDITOR_SLOTS_ROOT", "")
	OS.set_environment("VOXEL_EDITOR_DEFAULT_SOURCE", "")
	_w1_slots_root_fallback()
	_w5_session_meta_atomic()
	_w6_mcp_plugin_cleanup()
	await _w2_default_source()
	await _w34_editor_scene_probe()
	_cleanup()
	finish()

# ---------- 沙盒 / 动态路由 helper ----------
func _make_sandbox(tag: String) -> String:
	var base := OS.get_environment("TEMP")
	if base.is_empty():
		base = "/tmp"
	base = base.replace("\\", "/")
	var dir: String = base.path_join("voxel_editor_w5_%s_%d" % [tag, Time.get_ticks_msec()]) + "/"
	_sandboxes.append(dir)
	return dir

func _lsc(method: String, args: Array) -> Variant:
	if not _ls.has_method(method):
		return null
	return _ls.callv(method, args)   # callv：args 即参数表（call 的变长参把数组当单个实参，实证坑）

func _file_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)

func _remove_dir_recursive(path: String) -> void:
	var da := DirAccess.open(path)
	if da == null:
		return
	da.list_dir_begin()
	var item := da.get_next()
	while item != "":
		if item != "." and item != "..":
			var full := path.path_join(item)
			if da.current_is_dir():
				_remove_dir_recursive(full)
			else:
				DirAccess.remove_absolute(full)
		item = da.get_next()
	da.list_dir_end()
	DirAccess.remove_absolute(path)

func _cleanup() -> void:
	for ed: Variant in _eds:
		if ed is Node:
			(ed as Node).free()
	_eds.clear()
	OS.set_environment("VOXEL_EDITOR_SLOTS_ROOT", "")
	OS.set_environment("VOXEL_EDITOR_DEFAULT_SOURCE", "")
	for dir: String in _sandboxes:
		_remove_dir_recursive(dir)
	_sandboxes.clear()

## 实例化 editor_main（env 沙盒就绪后调用）并等一帧（_ready 完成）。
func _fresh_editor() -> Control:
	var ed: Control = (load("res://scenes/editor_main.tscn") as PackedScene).instantiate() as Control
	add_child(ed)
	await process_frame
	_eds.append(ed)
	return ed

# ============ W1（P1-9 拍板 6）：slots_root 便携优先 + 用户可写目录自动回退 ============
func _w1_slots_root_fallback() -> void:
	# a 开发态回归锚：主路径=工程内 levels/（三级解析下 dev 仍恒首位且探针通过）。
	check_eq(LS.slots_root(), ProjectSettings.globalize_path("res://levels/"),
		"W1a: 开发态 slots_root()==工程内 levels/（P1-9 三级解析下开发态不变，回归锚）")
	# b 用户可写候选=纯派生（不探测不落盘——user:// 零触碰纪律）。
	var user_root: Variant = _lsc("_user_levels_root", [])
	check(user_root is String and not (user_root as String).is_empty(),
		"W1b: _user_levels_root 派生非空（红：P1-9 前无本 API）")
	check_eq(str(user_root), OS.get_user_data_dir().path_join("levels/"),
		"W1c: _user_levels_root()==OS.get_user_data_dir()/levels/（拍板 6 回退路径口径）")
	# d 候选表：导出态=exe 同级（便携优先）→ user 回退，两元素序锁定；开发态=dev→exe→user 三级。
	var cands_exp: Variant = _lsc("_candidates_for", [true])
	check(cands_exp is Array and (cands_exp as Array).size() == 2,
		"W1d: 导出态候选表 2 级（exe 同级→user 回退；红：P1-9 前无本 API）")
	if cands_exp is Array and (cands_exp as Array).size() == 2:
		var exe_root: String = OS.get_executable_path().get_base_dir().path_join("levels/")
		check_eq(str((cands_exp as Array)[0]), exe_root,
			"W1e: 导出态第一候选=exe 同级 levels/（便携优先）")
		check_eq(str((cands_exp as Array)[1]), str(user_root),
			"W1f: 导出态第二候选=user levels/（不可写自动回退）")
	var cands_dev: Variant = _lsc("_candidates_for", [false])
	check(cands_dev is Array and (cands_dev as Array).size() == 3 \
			and str((cands_dev as Array)[0]) == ProjectSettings.globalize_path("res://levels/"),
		"W1g: 开发态候选表 3 级且首位=工程内 levels/（开发态不变）")
	# h 回退解析：首候选不可写（父位被同名文件占位→建目录必败）→ 落到次候选可写沙盒。
	var good := _make_sandbox("w1good")
	DirAccess.make_dir_recursive_absolute(good)
	var block_file: String = OS.get_environment("TEMP").replace("\\", "/") \
		.path_join("voxel_editor_w5_blockfile_%d" % Time.get_ticks_msec())
	var bf := FileAccess.open(block_file, FileAccess.WRITE)
	bf.store_string("blocker")
	bf.close()
	var bad_root: String = block_file.path_join("levels/")
	var resolved: Variant = _lsc("_resolve_from_candidates", [[bad_root, good]])
	check(resolved is String and (resolved as String) == good,
		"W1h: 不可写候选探针失败→回退次候选（P1-9 回退语义，红：P1-9 前无本 API；实际 %s）" % [str(resolved)])
	var all_bad: Variant = _lsc("_resolve_from_candidates", [[bad_root, bad_root + "x/"]])
	check(all_bad is String and (all_bad as String).is_empty(),
		"W1h2: 诸候选皆不可写→返回空串（调用方走初始化失败提示，返回值契约锁定）")
	# i 写探针：已存在目录写探针成功且零残留（探针文件用后即清）；文件占位路径探针失败。
	# （2 参签名随 P1-9 落地——以 _user_levels_root 在场为「新实现已入库」门，红期旧 1 参
	# _probe_root 不被 2 参误调，防 SCRIPT ERROR 噪声。）
	# 【P2-2 审查留痕】「目录在场但只读」分支（write_probe=true 时 FileAccess 打开写失败路径，
	# level_slots.gd _probe_root）无 ACL 注入直接测试——Windows 无头难造只读目录，不强制造测；
	# 当前由 W1i 写探针通过路径（FileAccess 真实打开+写入+即清，成功态已实证写路径健康）
	# + level_slots.gd _probe_root 读码双背书；ACL 注入补测留待需要时。
	var new_impl := _ls.has_method("_user_levels_root")
	if new_impl:
		var probe_ok: Variant = _lsc("_probe_root", [good, true])
		check(probe_ok == true, "W1i: 可写目录写探针通过（mkdir+写探针文件验证真实可写性）")
		check(not FileAccess.file_exists(good.path_join(".slots_probe")),
			"W1j: 探针文件零残留（用后即清）")
		var probe_bad: Variant = _lsc("_probe_root", [bad_root, true])
		check(probe_bad == false,
			"W1k: 不可写路径写探针失败（旧口径 dir_exists/mkdir 二态无法甄别只读已存在目录）")
	else:
		check(false, "W1i: 写探针未实现（红）")
		check(false, "W1j: 写探针未实现（红）")
		check(false, "W1k: 写探针未实现（红）")
	DirAccess.remove_absolute(block_file)

# ============ W5（P3-4c）：session_meta.json 原子写（tmp+rename，对齐关卡 JSON 同款序） ============
func _w5_session_meta_atomic() -> void:
	var root := _make_sandbox("w5meta")
	DirAccess.make_dir_recursive_absolute(root)
	check(LS.save_meta(1, root), "W5a: save_meta 常规写入成功（前置）")
	var meta1: Variant = JSON.parse_string(_file_text(root + LS.META_NAME))
	check(meta1 is Dictionary and int((meta1 as Dictionary).get("last_slot", -1)) == 1,
		"W5b: session_meta.json 内容正确（last_slot==1）")
	var residue := false
	var da := DirAccess.open(root)
	da.list_dir_begin()
	var item := da.get_next()
	while item != "":
		if item.ends_with(".tmp") or item.ends_with(".bak"):
			residue = true
		item = da.get_next()
	da.list_dir_end()
	check(not residue, "W5c: 常规写入零 .tmp/.bak 残留（原子写序成功态不留中间件）")
	# 原子性验证：tmp 路径被目录占位（写中间件必败）→ save_meta 失败且旧档逐字节保留——
	# 旧直写口径（无 tmp）会直接覆写旧档（红），原子写口径 tmp 建败即中止（绿）。
	var tmp_dir := root + LS.META_NAME + ".tmp"
	check(DirAccess.make_dir_absolute(tmp_dir) == OK, "W5d: 注入 session_meta.json.tmp 目录占位（前置）")
	var before := _file_text(root + LS.META_NAME)
	check(LS.save_meta(2, root) == false,
		"W5e: tmp 被占位→save_meta 确定性失败（原子写：tmp 写不进即中止，红：旧直写口径会覆写成功）")
	check_eq(_file_text(root + LS.META_NAME), before,
		"W5f: 失败路径旧 session_meta.json 逐字节保留（坏档不产生半截内容，坏档续接语义保持）")
	DirAccess.remove_absolute(tmp_dir)
	check(LS.save_meta(4, root) and int((JSON.parse_string(_file_text(root + LS.META_NAME)) as Dictionary).get("last_slot", -1)) == 4,
		"W5g: 占位解除后 save_meta 恢复成功且内容正确（瞬时阻塞不损坏后续写入）")

# ============ W6（P3-4e）：godot_mcp_runtime.gd 死常量与过时头注释清理 ============
func _w6_mcp_plugin_cleanup() -> void:
	var src := _file_text(MCP_PLUGIN_PATH)
	check(not src.is_empty(), "W6a: 插件入口文件可读（前置）")
	check(src.contains("mcp_runtime_autoload.gd"),
		"W6b: 文件本体仍是 plugin.cfg 的 EditorPlugin 入口（autoload 注册/注销保留，红：误删即失）")
	check(not src.contains("DEFAULT_PORT"),
		"W6c: 死常量 DEFAULT_PORT 已删（:15 未被运行时消费——真端口在 mcp_runtime_autoload.gd，红：批次 W 前在）")
	check(not src.contains("WebSocket"),
		"W6d: 过时头注释清理（「WebSocket server」描述与 TCP 7777 JSON 行协议实况不符，红：批次 W 前在）")

# ============ W2（P2-4a）：_default_source 健壮解析 + 解析失败显式提示 ============
func _w2_default_source() -> void:
	# a 开发态回归：默认源可解析到真实工作区文件，且为不含 .. 的规范绝对路径（健壮解析）。
	var src := LS._default_source()
	check(not src.is_empty() and FileAccess.file_exists(src),
		"W2a: 开发态默认源解析成功且文件存在（回归锚）")
	check(not src.contains(".."),
		"W2b: 默认源为逐级上溯解析的规范绝对路径（不含 .. 透传，红：旧 ../../ 相对拼接在）")
	# c 导出态模拟：以「解析落空」的 base（TEMP 沙盒）驱动 → 返回 ""；据此初始化=空骨架+显式提示。
	var bare := _make_sandbox("w2bare")
	DirAccess.make_dir_recursive_absolute(bare)
	var src_missing: Variant = _lsc("_default_source_from", [bare])
	check(src_missing is String and (src_missing as String).is_empty(),
		"W2c: 基准目录下无工作区→_default_source_from 返回空（导出态落空模拟，红：P2-4a 前无本 API）")
	var root := _make_sandbox("w2miss")
	# 导出态模拟：_default_source_from()=="" 时导出态 ensure_initialized 内部即以空源调
	# _prefill_slot（读入失败）；dev 测试以显式缺失源走同一分支（_prefill_slot 对 src=""
	# 与坏路径同判 text.is_empty() → 空骨架+提示）。
	var got: String = LS.ensure_initialized(root, MISSING_SOURCE)
	check(not got.is_empty(), "W2d: 源落空→初始化仍成功（空骨架降级，S7 语义保持）")
	var p1 := LP.new()
	var text := LS.load_slot_text(1, got)
	check(not text.is_empty() and p1.load_from_text(text) and p1.get_voxel_set(LP.TAG_BLOCKS).size() == 27,
		"W2e: level_1 降级空骨架（27 格）")
	# 【P2-1 审查留痕·复跑实证通过】_ls.get("last_prefill_note")（Script 对象动态读 static var）
	# 在 Godot 4.7 实测真实暴露：绿态返回置位文本（contains(NOTE_TEXT)+contains("空骨架") 非恒真、
	# 非 null）；与 test_v_editor_split.gd:337 的直接静态访问（LS.last_error_file）同效，维持本件
	# 红期兼容的 _ls 动态读手法族不动。
	var note: Variant = _ls.get("last_prefill_note")
	check(note is String and str(note).contains(NOTE_TEXT) and str(note).contains("空骨架"),
		"W2f: 解析失败显式置提示（非静默降级；红：P2-4a 前无本变量）")
	LS.ensure_initialized(got, FIXTURE)   # 二次初始化：五槽全在直接返回——入口清零提示不残留
	check(str(_ls.get("last_prefill_note")) == "",
		"W2f2: 已初始化根二次调用后提示清零（ensure_initialized 入口 reset，不残留上次降级提示）")
	# g 默认源 env 注入缝（VOXEL_EDITOR_DEFAULT_SOURCE，对齐 VOXEL_EDITOR_SLOTS_ROOT 先例；
	# editor 态消费）——导出态模拟/编排层测试注入口。
	OS.set_environment("VOXEL_EDITOR_DEFAULT_SOURCE", MISSING_SOURCE)
	check_eq(LS._default_source(), MISSING_SOURCE,
		"W2g: env 注入源生效（红：P2-4a 前未消费本变量）")
	OS.set_environment("VOXEL_EDITOR_DEFAULT_SOURCE", "")
	# h 编排层消费：env 注入缺失源 + 新沙盒 → editor_main 首启全量初始化降级 → 状态栏显式提示。
	var root_env := _make_sandbox("w2ed")
	OS.set_environment("VOXEL_EDITOR_SLOTS_ROOT", root_env)
	OS.set_environment("VOXEL_EDITOR_DEFAULT_SOURCE", MISSING_SOURCE)
	var ed: Control = await _fresh_editor()
	var label: Label = ed.get_node("StatusBar/StatusRow/ContractLabel") as Label
	check(String(label.text).contains(NOTE_TEXT),
		"W2h: editor_main 状态栏显式提示「内置示例不可用…」（红：旧实现静默降级）")
	var blocks_doc: Variant = JSON.parse_string(_file_text(root_env + "level_1/blocks.json"))
	check(blocks_doc is Dictionary and ((blocks_doc as Dictionary).get("blocks", []) as Array).size() == 27,
		"W2i: 编排层初始化 level_1=空骨架 27 格（提示与实况一致）")
	check((ed.get_node("TopBar/FileNameLabel") as Label).text.contains("第一关 · 已加载"),
		"W2j: 提示不阻断正常装载（FileNameLabel 第一关 · 已加载）")
	ed.free()
	_eds.clear()
	OS.set_environment("VOXEL_EDITOR_SLOTS_ROOT", "")
	OS.set_environment("VOXEL_EDITOR_DEFAULT_SOURCE", "")

# ============ W3+W4：editor_main 实例探针（P1-10 标题拦截 / P2-4d 子视口渲染） ============
func _w34_editor_scene_probe() -> void:
	var root_env := _make_sandbox("w34")
	OS.set_environment("VOXEL_EDITOR_SLOTS_ROOT", root_env)
	var ed: Control = await _fresh_editor()
	# 【P1-1 审查回修】P1-9 状态栏路径展示的编排层断言承接（editor_main.gd _ready「槽位目录：%s」）：
	# 前置=本实例为全新沙盒（默认源 dev 可解析→预填成功→last_prefill_note 空、无载入警告）→
	# 状态栏应以「槽位目录：」开头且含 env 注入根（便携/回退两态可辨识的落点验证）。
	var status_label: Label = ed.get_node("StatusBar/StatusRow/ContractLabel") as Label
	check(String(status_label.text).begins_with("槽位目录：") and String(status_label.text).contains(root_env),
		"W3-0: 状态栏显示实际生效槽位根（P1-9 编排层承接：开头「槽位目录：」+含 env 注入根；实际 %s）" % [status_label.text])
	var main_title: Label = ed.get_node("MainPanel/MainTitle") as Label
	var target_title: Label = ed.get_node("TargetPanel/Title") as Label
	var join_title: Label = ed.get_node("JoinPanel/Title") as Label
	var main_vc: SubViewportContainer = ed.get_node("MainPanel/VC") as SubViewportContainer
	# ---- W3（P1-10 探针）：主视口左上 348×24 死区——审计假设=MainTitle Label 拦截 / 拖窗白名单。
	# 探针①：Label 默认 mouse_filter 运行时实测（Godot 4.7 Label 构造默认=MOUSE_FILTER_IGNORE）。
	check_eq(int(main_title.mouse_filter), Control.MOUSE_FILTER_IGNORE,
		"W3a: 探针——MainTitle mouse_filter==IGNORE（未设即默认 2，不拦截；红态定义=若为 STOP 才是真拦截）")
	check_eq(int(target_title.mouse_filter), Control.MOUSE_FILTER_IGNORE,
		"W3b: 探针——TargetPanel/Title 同族 IGNORE（同款默认，试玩面板标题不拦子视口）")
	check_eq(int(join_title.mouse_filter), Control.MOUSE_FILTER_IGNORE,
		"W3c: 探针——JoinPanel/Title 同族 IGNORE")
	check_eq(int(main_vc.mouse_filter), Control.MOUSE_FILTER_STOP,
		"W3d: 探针——MainPanel/VC mouse_filter==STOP（点击落点=容器，事件进主视口）")
	# 探针②：按 Godot GUI 拾取序（逆绘制序取首个非 IGNORE 命中控件）模拟标题中心点点击——
	# 命中应为 MainPanel/VC 本体（标题 Label 被跳过）→ 348×24 区点击可达主视口（证伪「死区」）。
	var title_rect := main_title.get_global_rect()
	check(title_rect.size.is_equal_approx(Vector2(348, 24)),
		"W3e: 探针——MainTitle 矩形 348×24（审计所称死区几何在场；实际 %s）" % str(title_rect.size))
	var hit := _first_hit_at(ed, title_rect.get_center())
	check(hit == main_vc,
		"W3f: 探针——标题中心点 GUI 命中=MainPanel/VC（点击穿标题直达主视口容器；实际 %s）" % [str(hit)])
	# 结案口径（spec §6 P1-10 证伪出口）：编辑器工程无窗口拖拽逻辑（grep 实证零命中，
	# 「拖窗白名单」假设属主游戏 main.gd 机制）→ 审计死区证伪结案，本波零改动留痕。
	# ---- W4（P2-4d 探针·证伪结案）：Target/Join 子视口「render_target_update_mode=0 且代码从未
	# 改回→面板空白/陈旧帧」假设被探针证伪——Godot 4.7 实测（官方 4.7.stable 二进制，最小场景
	# +编辑器场景双对照）：**SubViewportContainer 无条件按可见性强制接管子视口更新模式**——
	# 容器可见→强制 UPDATE_ALWAYS（即使节点值被显式置 0 亦被覆盖）、容器隐藏→强制
	# UPDATE_DISABLED（正确不渲染）、无容器的裸 SubViewport 才治理自身值。Target/Join 面板
	# 仅试玩态可见（显示→引擎强 ALWAYS=实时渲染的机制保证），编辑态隐藏→DISABLED（本应不渲染）。
	# 故 tscn 的 mode=0 在运行期从不生效，审计假设不成立——按 §0-10 误报结案留痕（先例 P2-4b），
	# tscn 零改动，本段改锁「可见性→更新模式」引擎行为（面板实时反映编辑内容的机制回归锁）。
	var target_vp: SubViewport = ed.get_node("TargetPanel/VC/SubViewport") as SubViewport
	var join_vp: SubViewport = ed.get_node("JoinPanel/VC/SubViewport") as SubViewport
	var target_panel: Panel = ed.get_node("TargetPanel") as Panel
	var join_panel: Panel = ed.get_node("JoinPanel") as Panel
	var main_vp: SubViewport = ed.get_node("MainPanel/VC/SubViewport") as SubViewport
	check_eq(int(target_vp.render_target_update_mode), SubViewport.UPDATE_DISABLED,
		"W4a: 探针——编辑态（面板隐藏）容器强制 UPDATE_DISABLED（引擎可见性接管实证；非 tscn 值治理）")
	check_eq(int(join_vp.render_target_update_mode), SubViewport.UPDATE_DISABLED,
		"W4b: 探针——Join 同款（隐藏态 DISABLED）")
	check_eq(int(main_vp.render_target_update_mode), SubViewport.UPDATE_ALWAYS,
		"W4c: 探针——MainPanel 恒可见→容器强制 UPDATE_ALWAYS（回归锚）")
	target_panel.visible = true
	join_panel.visible = true
	await process_frame
	check_eq(int(target_vp.render_target_update_mode), SubViewport.UPDATE_ALWAYS,
		"W4d: 探针——面板显示→引擎强制 UPDATE_ALWAYS（试玩态实时渲染的机制保证，证伪「面板空白」假设）")
	check_eq(int(join_vp.render_target_update_mode), SubViewport.UPDATE_ALWAYS,
		"W4e: 探针——Join 显示→引擎强制 UPDATE_ALWAYS（同款）")
	target_panel.visible = false
	join_panel.visible = false
	# 结案口径（spec §6 P2-4d 证伪出口 + §8 走查复核）：真机/窗口观感（面板实时反映编辑内容）
	# 由 W7 走查截图复核；本波代码零改动。
	ed.free()
	_eds.clear()
	OS.set_environment("VOXEL_EDITOR_SLOTS_ROOT", "")

## 按 Godot GUI 拾取序模拟点命中：收集绘制序（前序 DFS）后逆序取首个
## 「树内可见 ∧ 矩形含点 ∧ mouse_filter≠IGNORE」的 Control（headless 探针，非真实注入）。
func _first_hit_at(root_node: Node, point: Vector2) -> Control:
	var order: Array = []
	_collect_controls(root_node, order)
	var i := order.size() - 1
	while i >= 0:
		var c: Control = order[i] as Control
		if c.is_visible_in_tree() and c.get_global_rect().has_point(point) \
				and int(c.mouse_filter) != Control.MOUSE_FILTER_IGNORE:
			return c
		i -= 1
	return null

func _collect_controls(node: Node, out: Array) -> void:
	if node is Control:
		out.append(node)
	for c: Variant in node.get_children():
		_collect_controls(c as Node, out)
