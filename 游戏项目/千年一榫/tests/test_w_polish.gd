extends "res://tests/test_base.gd"
## 批次 W6 结构治理波（规格 §7）集合件：P2-8 锐眼差集口径 / P3-1 色彩单源 / P3-3 信号生命周期 /
## P3-5 健壮性 a·b·c·d / P3-6 a·b·d。编辑器侧（P3-5 a/e/f）见 E/tests/test_w_polish_editor.gd。
## TDD 红态：本文件先于实现提交运行，标注「红：」的断言在旧代码下必 FAIL。
## 纪律：主脚本零 class_name 全局引用（load()/get()/call()，test_level_scene 先例）；
## 坑⑥ add 后 await process_frame；坑⑦⑩ Variant 判空后强转；坑⑪ 字典取键 .get 防御；
## MCP 段为真实 127.0.0.1:7777 自连（editor 态无头服务由插件 _ready 启动，服务器未监听则 skip）。

const PaletteScript := "res://scripts/palette.gd"
const LEVEL_SCENE_SCRIPT := "res://scenes/level/level_scene.gd"
const WIN := Vector2i(1152, 648)

func _initialize() -> void:
	print("== test_w_polish（批次 W6：P2-8/P3-1/P3-3/P3-5abcd/P3-6abd） ==")
	root.size = WIN
	await process_frame
	# 批次 AF 终审备案族（语言钉扎先例=6411fae o_catalog_shop）：autoload _ready 推迟至树激活，
	# 须等一帧后钉 zh——用户真实存档现 language=en，不钉则文案断言呈 en 态假红。
	# 编译窗安全：经节点查找而非全局名（--script 模式 autoload 全局名编译期未注册）。
	var i18n_node: Variant = get_root().get_node_or_null("I18n")
	if i18n_node != null:
		i18n_node.call("set_language", "zh")
	await _a_eye_diff_domain()
	await _b_palette_single_source()
	await _c_signal_lifecycle()
	await _d_robustness()
	await _e_hud_tips()
	finish()

# ================= 段 A（P2-8）：锐眼差集过滤域统一 target 域口径 =================
func _a_eye_diff_domain() -> void:
	var ls: GDScript = load(LEVEL_SCENE_SCRIPT)
	# A1/A2/A3：口径差分（静态纯函数，两口径行为对照——A2 复现「红绿皆空」缺陷本体）
	var target_out_of_blocks: Array = ["2,0,0"]   # 超出 blocks 域 (2,2,2) 的答案格
	var empty_remaining: Dictionary = {}
	var d_blocks: Dictionary = ls.call("diff_vs_target", empty_remaining, target_out_of_blocks, Vector3i(2, 2, 2))
	check(d_blocks is Dictionary and (d_blocks.get("missing", []) as Array).is_empty()
		and (d_blocks.get("extra", []) as Array).is_empty(),
		"A1: 旧口径（传 blocks 域 size）→ 超域答案格被过滤，红绿皆空（缺陷复现锚）")
	var d_target: Dictionary = ls.call("diff_vs_target", empty_remaining, target_out_of_blocks, Vector3i(3, 2, 2))
	check(d_target is Dictionary and (d_target.get("missing", []) as Array).size() == 1,
		"A2: target 域口径（_domain_size(piece,\"target_size\",bs)）→ missing 非空（修复后消费口径）")
	# A3（红）：_refresh_eye 消费 _target_size（_build_views 缓存 target 域尺寸）——
	# 构造 target_size>block_size 内存档实例化关卡场景，断言缓存存在且取值正确。
	var doc := {
		"chapter": 99, "level_id": "w6_probe_domain", "title": "W6 探针", "format_version": 1,
		"data": {"pieces": [{
			"block_size": {"x": 2, "y": 2, "z": 2},
			"target_size": {"x": 3, "y": 2, "z": 2},
			"blocks": ["0,0,0", "1,0,0", "0,1,0", "1,1,0", "0,0,1", "1,0,1", "0,1,1", "1,1,1"],
			"target_shapes": [["2,0,0", "0,0,0", "1,0,0"]],
			"join_part": {"voxels": [], "size": {"x": 2, "y": 2, "z": 2}},
			"final_answer": {"voxels": [], "size": {"x": 3, "y": 2, "z": 2}},
		}]},
	}
	var packed: PackedScene = load("res://scenes/level/level_scene.tscn")
	var inst: Node = (packed as PackedScene).instantiate()
	inst.call("set_context", {"chapter": 99})   # 库中无 99 章 → _load_level 早退，_level 保持注入档
	inst.set("_level", doc)
	root.add_child(inst)
	await process_frame
	var ts_v: Variant = inst.get("_target_size")
	check(ts_v is Vector3i, "A3（红）: _build_views 缓存 _target_size（target 域尺寸；红：成员缺失）")
	if ts_v is Vector3i:
		check_eq(ts_v, Vector3i(3, 2, 2), "A4: _target_size==target_size 域值（3,2,2），非 block_size")
	inst.queue_free()
	await process_frame

# ================= 段 B（P3-1）：色彩单源锚定（值零变化；d 项拍板为唯一值级变化） =================
func _b_palette_single_source() -> void:
	var pal: GDScript = load(PaletteScript)
	# B1：palette 本体值锚（对照 W0 清单原值逐条）
	var anchors := {
		"STROKE_GOLD": Color(1, 0.922, 0.706), "MAIN_GOLD": Color(0.96, 0.77, 0.26),
		"HINT_GOLD_TOAST": Color(1.0, 0.85, 0.4), "TOAST_WARN_RED": Color(1.0, 0.45, 0.35),
		"TOAST_OK_GREEN": Color(0.4, 0.9, 0.5), "FOCUS_JOIN_RED": Color(0.90, 0.25, 0.20),
		"EYE_MARK_RED": Color(1.0, 0.16, 0.12), "PICK_GREEN": Color(0.30, 0.85, 0.40),
		"GHOST_GREEN": Color(0.3, 1.0, 0.35), "CONF_GREEN": Color("#3FA34D"),
		"CURSOR_RED": Color("#C0504D"), "CURSOR_BLUE": Color("#3E7BBD"),
		"SKELETON_BLUE": Color(0.30, 0.55, 1.0), "TEXT_DARK_BUTTON": Color(0.96, 0.90, 0.78),
		"TEXT_DARK_HUD": Color("#F7EDD6"), "TEXT_DARK_SETTLE": Color(0.96, 0.93, 0.84),
		"TEXT_DARK_TITLE": Color(0.95, 0.93, 0.84, 0.82), "TEXT_DARK_LEVELBAR": Color(0.949, 0.910, 0.835),
		"TEXT_DARK_CAMSEL": Color(1, 0.95, 0.8),
		"NO_HAND_GRAY": Color("#B5B5B5"),
	}
	# 批次 AB-3：TEXT_LIGHT_* 浅字族随浅色调色板退役——反向锁（palette 不得留浅档、不得复辟）。
	for light_key: String in ["TEXT_LIGHT_SETTLE", "TEXT_LIGHT_TITLE", "TEXT_LIGHT_LEVELBAR"]:
		check(pal.get(light_key) == null, "AB-3 反向锁: palette %s 浅档常量退役（无复辟）" % light_key)
	for key: String in anchors.keys():
		var v: Variant = pal.get(key)
		check(v is Color and (v as Color).is_equal_approx(anchors[key]),
			"B1 %s: palette 值==W0 清单原值 %s" % [key, str(anchors[key])])
	# B2（红）：dark .tres 深底浅字统一 Button 族（N12 实证档）——CheckBox/Label/Panel/ProgressBar 四处
	var dark_src := FileAccess.get_file_as_string("res://themes/theme_dark.tres")
	for ctrl: String in ["CheckBox", "Label", "Panel", "ProgressBar"]:
		check(dark_src.contains("%s/colors/font_color = Color(0.96, 0.90, 0.78, 1)" % ctrl),
			"B2（红）: theme_dark %s font_color 统一 (0.96,0.90,0.78)（旧 (0.949,0.910,0.835) 对照表留痕）" % ctrl)
	# B3/B4/B5（theme_light .tres 深字/边框锚定）随批次 AB-3 浅色调色板删除退役——
	# 等价改写为「theme_light.tres 退役 + theme_dark.tres 描边金锚定保留」双护栏。
	check(not ResourceLoader.exists("res://themes/theme_light.tres"),
		"B3 等价改写: theme_light.tres 已删除（浅色调色板退役）")
	check(dark_src.contains("border_color = Color(1, 0.922, 0.706, 0.35)"),
		"B4 等价改写: theme_dark 按压/hover 边框==描边金 0.35 档（P3-1d 拍板值保留）")
	var catalog_src := FileAccess.get_file_as_string("res://scenes/catalog/catalog_scene.gd")
	check(not catalog_src.contains("Color(1, 1, 0.9, 0.7)"),
		"B6（红）: catalog_scene.gd 两处浅档边框复制值同步拍板值")
	# B7（红）：单源化守卫——被替换文件不再保留字面量复制（防漂移回潮）
	var literal_guards := [
		["res://scenes/shared/window_buttons.gd", "0.922, 0.706"],
		["res://scenes/shared/glass_dialog.gd", "0.922, 0.706"],
		["res://scenes/shared/top_strip.gd", "0.922, 0.706"],
		["res://scenes/shared/gesture_exit_dialog.gd", "0.922, 0.706"],
		["res://scenes/settings/settings_panel.gd", "0.922, 0.706"],
		["res://scenes/settings/camera_menu.gd", "0.922, 0.706"],
		["res://scenes/shared/toast_center.gd", "1.0, 0.85, 0.4"],
		["res://scripts/focus_fx.gd", "0.96, 0.77, 0.26"],
		["res://scenes/catalog/catalog_scene.gd", "0.96, 0.77, 0.26"],
		["res://scenes/settle/settle_scene.gd", "0.96, 0.77, 0.26"],
		["res://scripts/gesture_cursor_layer.gd", "3E7BBD"],
		["res://scripts/gesture_cursor_layer.gd", "C0504D"],
		["res://scenes/shared/camera_skeleton.gd", "0.30, 0.55, 1.0"],
		["res://scripts/level_voxel_view.gd", "1.0, 0.16, 0.12"],
		["res://scenes/shared/gesture_hud.gd", "F7EDD6"],
		["res://scenes/level/level_scene.gd", "0.949, 0.910, 0.835"],
		["res://scenes/level/level_scene.gd", "0.96, 0.93, 0.84"],
	]
	for guard: Array in literal_guards:
		var src := FileAccess.get_file_as_string(guard[0])
		check(not String(src).contains(String(guard[1])),
			"B7（红）: %s 不再含字面量复制（%s）" % [guard[0], guard[1]])
	# B8：脚本常量与 palette 同值（漂移守卫；值未变仅源换——「观感零变化」锚）
	var hud: Node = (load("res://scenes/shared/gesture_hud.gd") as GDScript).new()
	check((hud.get("TEXT_DARK") as Color).is_equal_approx(Color("#F7EDD6")),
		"B8: gesture_hud TEXT_DARK 值不变（=palette TEXT_DARK_HUD 同值）")
	check((hud.get("NO_HAND_GRAY") as Color).is_equal_approx(Color("#B5B5B5")),
		"B9: gesture_hud NO_HAND_GRAY 值不变（回归锚）")
	hud.free()

# ================= 段 C（P3-3）：主题信号生命周期（批次 AB-3 全面退役为反向锁） =================
## 源码去注释（AA 批 test_aa_gesture_remap 同款工具迁入）：留痕注释允许记载旧接线措辞，
## 反向锁只对代码行生效。
func _code_only(src: String) -> String:
	var out: PackedStringArray = []
	for ln: String in src.split("\n"):
		var i: int = ln.find("#")
		out.append(ln if i < 0 else ln.substr(0, i))
	return "\n".join(out)

func _c_signal_lifecycle() -> void:
	var tm: Node = root.get_node("ThemeManager")
	# C1 旧「hover_tip 背景随 theme_changed 刷新」live 翻转断言随深浅主题机制删除退役——
	# 等价改写：hover_tip 衬底恒深档值 + ThemeManager 无信号反向锁（翻转通道无复辟可能）。
	var tip: Control = (load("res://scenes/shared/hover_tip.gd") as GDScript).new()
	var host: Button = Button.new()
	root.add_child(host)
	root.add_child(tip)
	await process_frame
	var sb_v: Variant = tip.get_theme_stylebox("panel")
	check(sb_v is StyleBoxFlat and (sb_v as StyleBoxFlat).bg_color.is_equal_approx(Color(0.16, 0.12, 0.06, 0.92)),
		"AB-3 等价改写: hover_tip 衬底恒深档 (0.16,0.12,0.06,0.92)（旧深档终态值不变）")
	check(not tm.has_signal("theme_changed"),
		"AB-3 反向锁: ThemeManager 无 theme_changed 信号（hover_tip 刷新链无复辟通道）")
	tip.free()
	host.free()
	await process_frame
	# C2/C3 旧「六处 theme_changed 具名连接/离树断开」源锚断言随机制删除退役——
	# 等价改写为反向锁：六处生产源不得再含 theme_changed 接线（无订阅、无断开、无复辟）。
	var six := [
		"res://scenes/shared/gesture_hud.gd", "res://scenes/shared/glass_dialog.gd",
		"res://scenes/dialog/talk_controller.gd", "res://scenes/settings/settings_panel.gd",
		"res://scenes/shared/gesture_exit_dialog.gd", "res://scenes/menu/main_menu.gd",
	]
	for path: String in six:
		var src := _code_only(String(FileAccess.get_file_as_string(path)))
		check(not src.contains("theme_changed.connect") and not src.contains("theme_changed.is_connected"),
			"AB-3 反向锁: %s 无 theme_changed 连接/断开接线（机制删除，注释行不计）" % path)
	# C4（批次 Y Y-C7 等价改写，spec §9.2 测试红线）→ **批次 AD §4.3.5 等价改写**：原「事件分流
	# 不回滚 STOP」反向锁随立绘点击恢复反置为正向锁——MainView 锚点收窄至 0.115（与立绘右缘 0.11
	# 不再水平重叠，拾取带根因消失）后，witness 恢复 MOUSE_FILTER_STOP 并直连 gui_input
	#（旧值留痕：`not ls_src.contains("func _on_witness_gui_input") and not
	#  ls_src.contains("witness.gui_input.connect")`）。判据语义「点击立绘弹泡链在位」保持，
	# 实现载体由 MainView 分流 → 立绘自身 gui_input 直连（分流兜底链仍在案由 C4b 覆盖，断言数不变）。
	var ls_src := String(FileAccess.get_file_as_string(LEVEL_SCENE_SCRIPT))
	check(ls_src.contains("func _on_witness_gui_input")
		and ls_src.contains("witness.gui_input.connect(_on_witness_gui_input)"),
		"AD §4.3.5：level_scene 立绘 gui_input 直连 _on_witness_gui_input（锚点收窄消除重叠带后 STOP 恢复；旧 Y-C7「不回滚 STOP」反向锁留痕）")
	check(ls_src.contains("func _witness_bubble_dispatch")
		and ls_src.contains("_witness_bubble_dispatch(event,"),
		"C4b: 见证者气泡点击链恢复——MainView gui_input 入口接 _witness_bubble_dispatch（事件分流）")
	check(ls_src.contains("func _toggle_witness_bubble"),
		"C4c: 气泡 toggle 显隐语义在位（旧设计 ded6fa8/ad85663 口径恢复）")
	# C5：glass_dialog 具名连接 live 验证（代表件；其余五件源锚已覆盖）。
	# 经 tscn 实例化（@onready 节点路径依赖场景树，.new() 裸实例不可用）。
	var gd: Control = (load("res://scenes/shared/glass_dialog.tscn") as PackedScene).instantiate() as Control
	root.add_child(gd)
	await process_frame
	# C5 旧「glass_dialog 实例 theme_changed 已连接」live 断言随信号退役——等价改写：
	# 信号不存在（连接无复辟通道）+ 玻璃样式恒深档挂载在场。
	check(not tm.has_signal("theme_changed"),
		"AB-3 反向锁: glass_dialog theme_changed→_on_theme_changed 连接随信号退役")
	var gd_sb: Variant = (gd as Control).get_node_or_null("Card").get_theme_stylebox("panel")
	check(gd_sb is StyleBoxFlat, "AB-3: glass_dialog 深档玻璃样式挂载在场（恒深档唯一真值）")
	gd.free()
	await process_frame

# ================= 段 D（P3-5 a/b/c/d）：健壮性 =================
func _d_robustness() -> void:
	# D1（红）P3-5a：_write_text_flushed get_error 时机移到 close() 后（源序断言+行为回归）
	var sm_src := String(FileAccess.get_file_as_string("res://autoload/save_manager.gd"))
	var i0 := sm_src.find("static func _write_text_flushed")
	var i1 := sm_src.find("# ---------- 首次标记 ----------")
	if i0 >= 0 and i1 > i0:
		var body := sm_src.substr(i0, i1 - i0)
		check(body.find("close()") < body.find("get_error()"),
			"D1（红）: save_manager._write_text_flushed close() 先于 get_error()（旧序缓冲错误不可见）")
	var save: Node = root.get_node("SaveManager")
	var tmp_path: String = "user://w6_polish_tmp_write.json"
	var ok_write: bool = bool(save.call("_write_text_flushed", tmp_path, "{\"k\":1}"))
	check(ok_write, "D2: _write_text_flushed 有效写返回 true（行为回归锚）")
	var abs_path: String = ProjectSettings.globalize_path(tmp_path)
	check(FileAccess.file_exists(abs_path)
		and String(FileAccess.get_file_as_string(abs_path)) == "{\"k\":1}",
		"D3: 写盘内容往返一致（行为回归锚）")
	DirAccess.remove_absolute(abs_path)
	# D4（红）P3-5b：apply_dock_state 行集合重建与折叠分支解耦
	var hud: Control = (load("res://scenes/shared/gesture_hud.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	await process_frame
	# AF 同步批（2026-11-01）：内存钉 gesture_input=true（同 test_w_camera_menu E 段手法，不落盘
	# 进程退出即弃；钉位于本文件首个 await 之后防 SaveManager._ready load_game 整体替换 _data 引
	# 用冲钉）。实证：apply_dock_state 可见门 `gesture_hud_visible ∧ gesture_input` 在用户存档 Q3
	# 双关时整组 visible=false 提前 return，停靠布局与其内 guide_list 行集合重建不可达——D4 两断
	# 言读到的是 _ready 默认 key 的 4 行（非代码回归；「手势关=HUD 整组隐」生产语义正确）。
	var sm_polish: Node = root.get_node_or_null("SaveManager")
	if sm_polish != null:
		var sm_data_polish: Dictionary = sm_polish.get("_data")
		if typeof(sm_data_polish.get("settings")) != TYPE_DICTIONARY:
			sm_data_polish["settings"] = {}
		(sm_data_polish["settings"] as Dictionary)["gesture_input"] = true
	hud.call("apply_dock_state", 6, false, false)   # Game.State.CATALOG=6：6 行
	await process_frame
	var catalog_rows: int = (hud.get("guide_list") as Container).get_child_count()
	check_eq(catalog_rows, 6, "D4 前置: CATALOG 展开态 6 行")
	hud.set("_hint_folded", {"SETTLE": true})
	hud.call("apply_dock_state", 5, false, false)   # Game.State.SETTLE=5：5 行（折叠）
	var settle_rows: int = (hud.get("guide_list") as Container).get_child_count()
	check_eq(settle_rows, 5, "D4（红）: 折叠切态后行集合仍与 key 同源（旧折叠分支不重建→滞后 6 行）")
	hud.free()
	await process_frame
	# D5（红）P3-5c：缺 gesture_runtime 处置决策——editor 判据前置（警告仅 editor 态）
	var bridge: Node = root.get_node("GestureBridge")
	check(bool(bridge.has_method("_missing_runtime_plan")),
		"D5（红）: GestureBridge._missing_runtime_plan 决策缝存在（导出态静默降 UNAVAILABLE 契约锚）")
	if bridge.has_method("_missing_runtime_plan"):
		var plan_export: Dictionary = bridge.call("_missing_runtime_plan", false)
		check(plan_export is Dictionary and bool(plan_export.get("warn", true)) == false
			and bool(plan_export.get("degrade", false)) == true,
			"D6: 导出态=静默降 UNAVAILABLE（warn=false, degrade=true；旧实现每 5s 刷 push_error）")
		var plan_editor: Dictionary = bridge.call("_missing_runtime_plan", true)
		check(plan_editor is Dictionary and bool(plan_editor.get("warn", false)) == true,
			"D7: editor 态=警告保留（缺运行时警告仅 editor 态可达）")
	var bridge_src := String(FileAccess.get_file_as_string("res://autoload/gesture_bridge.gd"))
	var plan_pos := bridge_src.find("_missing_runtime_plan(OS.has_feature(\"editor\"))")
	var warn_pos := bridge_src.find("手势运行时未就位")
	check(plan_pos >= 0 and plan_pos < warn_pos,
		"D8（红）: start_gesture_process editor 判据（plan 消费）先于 push_error 文案（源序锚）")
	# D9~D12（红）P3-5d：MCP TCP 读侧分帧——半包/粘包/裸 JSON（协议零变更：请求侧裸 JSON 维持；
	# 响应侧实测含 put_utf8_string 隐式 4 字节长度前缀，客户端按实测协议解码）
	var mcp: Node = root.get_node_or_null("MCPRuntime")
	var listening: bool = mcp != null and mcp.get("_server") != null \
		and bool((mcp.get("_server") as TCPServer).is_listening())
	if not listening:
		push_warning("[test_w_polish] MCP 7777 未监听（环境性），段 D9~D12 skip 不 fail（P2-11 同款纪律）")
		print("[SKIP] D9~D12: MCP server not listening")
		return
	await _mcp_framing_case()

# P3-5d 自连用例：半包（红：旧实现 Invalid JSON 丢命令）/粘包（红）/裸 JSON 无换行（回归锚）
func _mcp_framing_case() -> void:
	# 半包
	var c1 := await _tcp_connect()
	c1.put_data('{"command":"ping","id":"half1"'.to_utf8_buffer())
	await _frames(5)
	c1.put_data('}\n'.to_utf8_buffer())
	var got_half: Dictionary = await _wait_response(c1, "half1")
	check(not got_half.is_empty() and String(got_half.get("type", "")) == "pong"
		and String(got_half.get("id", "")) == "half1",
		"D9（红）: MCP 半包两段拼接后完整受理（旧实现按到达字节即解析→Invalid JSON 丢命令）")
	c1.disconnect_from_host()
	# 粘包（单次写入两条完整命令；同一连接一次收集两条响应——首条命中即返回会丢弃已缓冲的次条）
	var c2 := await _tcp_connect()
	c2.put_data(('{"command":"ping","id":"stick1"}\n{"command":"ping","id":"stick2"}\n').to_utf8_buffer())
	var both: Dictionary = await _collect_responses(c2, ["stick1", "stick2"])
	var got1: Dictionary = both.get("stick1", {})
	var got2: Dictionary = both.get("stick2", {})
	check(String(got1.get("id", "")) == "stick1" and String(got1.get("type", "")) == "pong",
		"D10（红）: MCP 粘包首条完整受理")
	check(String(got2.get("id", "")) == "stick2" and String(got2.get("type", "")) == "pong",
		"D11（红）: MCP 粘包次条完整受理（旧实现整段解析失败→两条皆丢）")
	c2.disconnect_from_host()
	# 裸 JSON 无换行结尾（协议零变更回归锚：请求侧维持裸 JSON 读取）
	var c3 := await _tcp_connect()
	c3.put_data('{"command":"ping","id":"bare1"}'.to_utf8_buffer())
	var got3: Dictionary = await _wait_response(c3, "bare1")
	check(String(got3.get("id", "")) == "bare1" and String(got3.get("type", "")) == "pong",
		"D12: 无换行裸 JSON 仍即时受理（协议零变更回归锚，GoPeak 契约不破坏）")
	c3.disconnect_from_host()
	await _frames(2)

func _tcp_connect() -> StreamPeerTCP:
	var c := StreamPeerTCP.new()
	c.connect_to_host("127.0.0.1", 7777)
	for i in range(600):
		c.poll()
		if c.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			break
		await process_frame
	await _frames(2)   # 放行 welcome
	_drain(c)
	return c

func _frames(n: int) -> void:
	for i in range(n):
		await process_frame

func _drain(c: StreamPeerTCP) -> void:
	c.poll()
	var n := c.get_available_bytes()
	if n > 0:
		c.get_partial_data(n)

## 响应解码（W6 实测线级协议）：_send_response 源码 JSON+换行 经 put_utf8_string 落线=
## [4 字节小端长度][JSON 字节]（隐式前缀）；逐帧收字节按前缀拆帧，id 匹配即返回。
func _wait_response(c: StreamPeerTCP, id: String) -> Dictionary:
	var got := await _collect_responses(c, [id])
	return got.get(id, {})

## 同连接收集多条响应（粘包用例）：帧解码循环持续到 ids 全命中或超时。
func _collect_responses(c: StreamPeerTCP, ids: Array) -> Dictionary:
	var rx := PackedByteArray()
	var found: Dictionary = {}
	for i in range(300):
		c.poll()
		var n := c.get_available_bytes()
		if n > 0:
			var res: Array = c.get_partial_data(n)
			if int(res[0]) == OK:
				rx.append_array(res[1])
		while rx.size() >= 4:
			var ln := rx.decode_u32(0)
			if rx.size() < 4 + ln:
				break
			var body := rx.slice(4, 4 + ln).get_string_from_utf8()
			rx = rx.slice(4 + ln)
			var v: Variant = JSON.parse_string(body.strip_edges())
			if v is Dictionary:
				var vid := String((v as Dictionary).get("id", ""))
				if vid in ids:
					found[vid] = v
		if found.size() >= ids.size():
			return found
		await process_frame
	return found

# ================= 段 E（P3-6 a/b/d）：HUD 与提示 =================
func _e_hud_tips() -> void:
	# E1（红）P3-6a：ui_light_linker._mats 随 node_removed 清理（场景切换泄漏根除）
	var linker: Node = (load("res://scripts/ui_light_linker.gd") as GDScript).new()
	root.add_child(linker)
	await process_frame
	var btn := Button.new()
	root.add_child(btn)
	await _frames(3)   # node_added→延帧重扫→attach
	var mats_v: Variant = linker.get("_mats")
	check(mats_v is Dictionary and (mats_v as Dictionary).has(btn),
		"E1 前置: Button 入树后 _mats 登记（attach 链路回归锚）")
	btn.free()
	await _frames(3)
	check(mats_v is Dictionary and not (mats_v as Dictionary).has(btn),
		"E2（红）: 节点 free 后 _mats 键清除（旧实现永不清理→跨场景累积泄漏）")
	# E3：入树同帧即 free 的延帧重扫健壮性（W4-P3-D「Cannot convert argument 1」同源；
	# 旧实现 call_deferred 强引用直传在参数转换期报错——stderr 留证，本断言保功能面）
	var c2 := Control.new()
	root.add_child(c2)
	c2.free()
	await _frames(3)
	check(true, "E3: 入树即 free 节点的延帧重扫零异常（弱引用传递；log 侧 grep 留证）")
	linker.free()
	await process_frame
	# E4（红）P3-6b：CATALOG 说明栏与 Body 底边 14px 重叠校正——my+h==Body 底边距 120
	var hud2: Control = (load("res://scenes/shared/gesture_hud.tscn") as PackedScene).instantiate()
	root.add_child(hud2)
	await process_frame
	var cfg: Dictionary = hud2.call("_dock_cfg", "CATALOG")
	var hint: Dictionary = cfg.get("hint", {})
	var my := float(hint.get("my", 0.0))
	var h := ((hint.get("size", Vector2()) as Vector2)).y
	var tscn_src := String(FileAccess.get_file_as_string("res://scenes/catalog/catalog_scene.tscn"))
	check(is_equal_approx(my + h, 134.0),
		"E4（红）: CATALOG 说明栏顶=H−(my+h)=H−134 与 Body 新底边齐平（旧 Body 底 H−120 重叠 14px）")
	check(tscn_src.contains("offset_bottom = -134.0"),
		"E5（红）: catalog Body 底边 -120→-134（重叠校正落内容区侧；HUD 侧 106 方案证伪留痕）")
	hud2.free()
	await process_frame
	# E5b（红）P3-6d：hover_tip 每帧高度置 0 修正——钳宽不清高（直调 _process 观测；W7a 标签纠偏：与 E5 重名故改 E5b）
	var tip2: Control = (load("res://scenes/shared/hover_tip.gd") as GDScript).new()
	var host2 := Button.new()
	root.add_child(host2)
	root.add_child(tip2)
	await process_frame
	host2.global_position = Vector2(100, 100)
	host2.size = Vector2(200, 60)
	var provider := func() -> Variant: return host2.get_global_rect().position + Vector2(2, 2)
	tip2.call("setup", host2, "W6 P3-6d", Callable(), provider)
	tip2.size = Vector2(400, 80)
	tip2.call("_process", 0.016)
	check(is_equal_approx(tip2.size.y, 80.0),
		"E5b（红）: 钳宽保留现有高度（旧实现 y=0 依赖容器最小尺寸兜底，脆弱）")
	check(tip2.size.x <= 320.0, "E6: 宽钳 MAX_WIDTH 语义保持（回归锚）")
	tip2.free()
	host2.free()
	await process_frame
