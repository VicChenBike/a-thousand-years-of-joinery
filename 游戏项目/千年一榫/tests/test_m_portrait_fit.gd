extends "res://tests/test_base.gd"
## M-D（批次 M spec §3.4，2026-09-07）：对话立绘 30px 悬空落位 + 见证者气泡贴头落位
## + 【用户追加 追1】对话框背板 70~80% 半透 + 悬停「金属反光感」光标效果。
## 契约来源：批次 M spec §3.4 目标行为 1~4 / 验收标准 1~4：
##   ① portrait_metrics.gd 静态工具：纹理路径 → Image.used_rect 可见内容包围盒
##     （归一化 ratio + 绝对像素 rect_px），同路径缓存（cache_hit_count 递增可测），
##     全 1 透明图/不可读路径返回 valid=false 空 rect（防御）；headless 可测。
##   ② talk Portrait 盒：可见脚底全局 y == DialogPanel 全局顶 − 30（拍板 #2，暂定走查微调），
##     盒高 560→620（暂定），水平居中不变，头顶不出屏（越界回退放大档）；
##     47 皮肤与缺省立绘统一按各自纹理 used_rect 计算（不再吃固定透明边亏）。
##   ③ level WitnessBubble：气泡全局底 == 见证者可见头顶 − 8（暂定），随浮动同步
##     （_tick_witness 同 tick 更新 y，浮动振幅内恒贴不穿头）。
##   ④ 追1：PANEL_BG 深 0.75/浅 0.78（∈[0.70,0.80]）；DialogPanel 挂 ui_material 面板档
##     （u_panel_mode=1/u_ellipse_use=0 圆角矩形卡片档），悬停期窄幅金属高光带随光标移动
##     （u_hover_metal 能量渐入渐出 + u_mouse_screen 屏幕口径），非悬停恒 0 不出现；
##     不复活 u_specular（M-C 根除红线）；StyleBox 投影置 0 移交材质（L-A 面板档契约）。
## 坑位吸收（spec §六）：钉设计视口 1152×648（headless expand 撑 1152×1152 伪象）；
## 断言相对几何（可见脚底/气泡底）随 witness 当前浮动/缩放态直算，任意 tick 皆可验。

const W := 1152.0
const H := 648.0
const METRICS := "res://scripts/portrait_metrics.gd"
const TALK_SCENE := "res://scenes/dialog/talk_scene.tscn"
const TALK_SCRIPT := "res://scenes/dialog/talk_controller.gd"
const LEVEL_SCENE := "res://scenes/level/level_scene.tscn"
const UI_SHADER := "res://assets/shaders/ui_material.gdshader"
const DEFAULT_PORTRAIT := "res://assets/characters/default_witness.png"
const SAVE_PATH := "user://save.json"
const GAP := 30.0        # 拍板 #2：可见脚底与对话框上沿悬空（暂定走查微调）
const BUBBLE_GAP := 4.0  # 气泡盒底与可见头顶间隙（M-D 回修 2026-09-08：8→4 配合文字贴底，暂定）
const BOX_H := 620.0     # 立绘盒高放大档（560→620 暂定）

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
const DISC_BK_PREFIX := "user://_r2b_mpf_backup_"
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
	print("EVID|user_restore|mpf|files=%d" % DISC_WATCHED.size())

func finish() -> void:
	_restore_user()
	super.finish()

func _initialize() -> void:
	print("== test_m_portrait_fit ==")
	_backup_user()
	var met: GDScript = load(METRICS)
	_sec_metrics(met)
	_sec_fit(met)
	_sec_shader()
	await _sec_talk(met)
	await _sec_level(met)
	_cleanup()
	finish()

func _cleanup() -> void:
	for p: String in [SAVE_PATH, "user://md_transparent_probe.png"]:
		var abs: String = ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs):
			DirAccess.remove_absolute(abs)

# ==================== 段 A：portrait_metrics 纯函数（spec 验收 1） ====================

func _sec_metrics(met: GDScript) -> void:
	check(ResourceLoader.exists(METRICS), "M-D：portrait_metrics.gd 存在")
	var m: Dictionary = met.call("measure", DEFAULT_PORTRAIT)
	check(bool(m.get("valid", false)), "A：default_witness 度量 valid=true")
	# 与 Image 直算交叉验证（IO 独立：直算用 load().get_image()，不经 measure）
	var tex: Texture2D = load(DEFAULT_PORTRAIT)
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	var ref: Rect2i = img.get_used_rect()
	var rect_px: Rect2 = m.get("rect_px", Rect2())
	check(rect_px.position.is_equal_approx(Vector2(ref.position)), "A：rect_px.position==Image 直算 used_rect.position")
	check(rect_px.size.is_equal_approx(Vector2(ref.size)), "A：rect_px.size==Image 直算 used_rect.size")
	check(Vector2(m.get("size", Vector2.ZERO)).is_equal_approx(tex.get_size()), "A：size==纹理实际尺寸")
	var ratio: Rect2 = m.get("ratio", Rect2())
	check(ratio.position.is_equal_approx(rect_px.position / tex.get_size()), "A：ratio.position==归一化包围盒左上")
	check(ratio.size.is_equal_approx(rect_px.size / tex.get_size()), "A：ratio.size==归一化包围盒尺寸")
	# 缓存生效：同路径二次调用命中（cache_hit_count 递增，不重复读盘）
	var hits0: int = int(met.get("cache_hit_count"))
	met.call("measure", DEFAULT_PORTRAIT)
	check(int(met.get("cache_hit_count")) > hits0, "A：同路径二次调用命中缓存（cache_hit_count 递增）")
	# 全 1 透明图 → 空 rect（防御）
	var img_t := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	img_t.fill(Color(0, 0, 0, 0))
	var tpath: String = "user://md_transparent_probe.png"
	img_t.save_png(ProjectSettings.globalize_path(tpath))
	var mt: Dictionary = met.call("measure", tpath)
	var mt_rect: Rect2 = mt.get("rect_px", Rect2(1, 1, 1, 1))
	check(not bool(mt.get("valid", true)) and mt_rect.size == Vector2.ZERO,
		"A：全 1 透明图 → valid=false 且空 rect（防御）")
	# 不可读路径 → 防御
	var mx: Dictionary = met.call("measure", "res://no_such_file_md_probe.png")
	check(not bool(mx.get("valid", true)), "A：不可读路径 → valid=false（防御）")

func _sec_fit(met: GDScript) -> void:
	# fit_in_box（KEEP_ASPECT_CENTERED 布局解算）与手算交叉验证
	var m: Dictionary = met.call("measure", DEFAULT_PORTRAIT)
	var f: Dictionary = met.call("fit_in_box", m["size"], m["rect_px"], Vector2(520.0, 620.0))
	var ts: Vector2 = m["size"]
	var sc_ref: float = minf(520.0 / ts.x, 620.0 / ts.y)
	var dy_ref: float = (620.0 - ts.y * sc_ref) * 0.5
	check(absf(float(f.get("scale", 0.0)) - sc_ref) < 0.0001, "A：fit_in_box.scale==手算 min(盒宽/纹理宽, 盒高/纹理高)")
	check(absf(float(f.get("dy", 0.0)) - dy_ref) < 0.0001, "A：fit_in_box.dy==手算垂直居中偏移")
	var foot_ref: float = dy_ref + (m["rect_px"] as Rect2).end.y * sc_ref
	var head_ref: float = dy_ref + (m["rect_px"] as Rect2).position.y * sc_ref
	check(absf(float(f.get("foot_local_y", 0.0)) - foot_ref) < 0.01, "A：foot_local_y==dy+used.end.y×scale（可见脚底盒内 y）")
	check(absf(float(f.get("head_local_y", 0.0)) - head_ref) < 0.01, "A：head_local_y==dy+used.position.y×scale（可见头顶盒内 y）")

# ==================== 段 B：shader 源码口径（追1 金属反光红线） ====================

func _sec_shader() -> void:
	var sh: Shader = load(UI_SHADER) as Shader
	check(sh != null, "追1：ui_material.gdshader 可加载")
	if sh == null:
		return
	var src := String(sh.get_code())
	check(src.contains("uniform float u_hover_metal"), "追1：shader 新增 u_hover_metal 能量 uniform（专用 hover 高光路径，非点光项）")
	check(src.contains("* u_hover_metal"), "追1：金属高光能量受 u_hover_metal 控制（乘子形态，非悬停恒灭）")
	check(not src.contains("u_specular"), "追1红线：u_specular 未复活（M-C 镜射根除维持，spec §3.3）")
	check(src.contains("across") and src.contains("exp("), "追1：高光为窄幅带状高斯衰减（金属反光带形态，无 pow 镜射）")

# ==================== 段 C：talk 立绘落位 + 追1 对话框（spec 验收 2/4） ====================

func _sec_talk(met: GDScript) -> void:
	var save: Node = get_root().get_node("SaveManager")
	save.load_game()  # 全新档（K-D 后默认穿戴 skin_origin_kaitou）
	var container: Control = Control.new()
	container.size = Vector2(W, H)  # 钉设计视口（headless expand 伪象防御，spec §六坑 1）
	add_child(container)
	var talk: Control = (load(TALK_SCENE) as PackedScene).instantiate()
	container.add_child(talk)
	await process_frame
	await process_frame
	await process_frame
	var dp: Control = talk.get_node("DialogPanel")
	var prt: TextureRect = talk.get_node("Portrait")
	# C-1 原创皮肤（kaitou）落位（统一算法按纹理实际 used_rect）
	_check_portrait_fit(talk, prt, dp, met, "kaitou")
	# C-2 缺省立绘（skin_default）落位
	save.equip_skin("skin_default")
	await process_frame
	await process_frame
	_check_portrait_fit(talk, prt, dp, met, "default")
	# C-3 盒高放大档生效（620 档可行——实测 default_witness used_rect 底部透明边 548px，
	#  盒 520×620 宽度受限 sc=0.2438，可见脚底盒内 ≈416px，头顶全局 ≈112 不出屏）
	check(absf(prt.size.y - BOX_H) <= 0.5, "落位：盒高==620（放大档生效，暂定值走查微调）")
	# C-4 度量失效回落旧锚（防御路径）
	talk.set("portrait_path", "")
	prt.texture = null
	talk.call("_layout_portrait")
	await process_frame
	check(absf(prt.offset_top + 560.0) < 0.01 and absf(prt.offset_bottom) < 0.01,
		"落位：度量失效回落旧锚（offset_top=-560/offset_bottom=0，K5-1 语义兜底）")
	# C-5 立绘在对话框上方（K5-1 锚点语义保留）
	check(prt.anchor_bottom <= dp.anchor_top + 0.001, "落位：Portrait 锚点仍在对话框上方（anchor_bottom<=面板 anchor_top）")

	# ---- 追1：背板半透 + 悬停金属反光 ----
	var lk: GDScript = load(TALK_SCRIPT)
	var bd: Color = lk.PANEL_BG_DARK
	# 批次 AB-3：PANEL_BG_LIGHT 浅档随深浅主题机制删除退役——反向锁 + 深档值不变。
	check(absf(bd.a - 0.75) < 0.001, "追1 等价改写：背板 α 常量恒深档 0.75（浅档 0.78 退役）")
	check(lk.get_script_constant_map().get("PANEL_BG_LIGHT", null) == null,
		"AB-3 反向锁：PANEL_BG_LIGHT 浅档常量退役（无复辟）")
	var sb: StyleBox = dp.get_theme_stylebox("panel")
	check(sb is StyleBoxFlat and (sb as StyleBoxFlat).bg_color.a >= 0.70 and (sb as StyleBoxFlat).bg_color.a <= 0.80,
		"追1：运行时背板 α∈[0.70,0.80]（当前主题实际值 %.3f）" % ((sb as StyleBoxFlat).bg_color.a if sb is StyleBoxFlat else -1.0))
	check(sb is StyleBoxFlat and (sb as StyleBoxFlat).shadow_size == 0,
		"追1：StyleBox 投影置 0（外投影移交材质面板档承担，L-A「StyleBox shadow 已置 0」契约）")
	var mat: ShaderMaterial = dp.material as ShaderMaterial
	check(mat != null, "追1：DialogPanel 已挂 ShaderMaterial（金属反光载体）")
	if mat != null:
		check(mat.shader != null and String(mat.shader.resource_path).ends_with("ui_material.gdshader"),
			"追1：材质 shader==ui_material（沿用按钮档金属光照语言）")
		check(int(mat.get_shader_parameter("u_panel_mode")) == 1 and int(mat.get_shader_parameter("u_ellipse_use")) == 0,
			"追1：面板档=1/椭圆档=0（圆角矩形卡片档，不破坏容器/按钮档既有口径）")
	# 非悬停：能量 0（高光不出现）
	check(absf(float(talk.call("get_hover_metal_energy"))) < 0.001, "追1：非悬停初始能量==0（金属高光不出现）")
	if mat != null:
		check(absf(float(mat.get_shader_parameter("u_hover_metal"))) < 0.001, "追1：非悬停 uniform u_hover_metal==0")
	# 悬停渐入：面板中心持续探测 → 能量至 1.0、uniform 同步、光标坐标写入
	var inside: Vector2 = dp.get_global_rect().get_center()
	for i: int in range(12):
		talk.call("hover_probe", inside, 0.2)
	check(absf(float(talk.call("get_hover_metal_energy")) - 1.0) < 0.001, "追1：悬停持续 → 能量渐入至 1.0")
	if mat != null:
		check(absf(float(mat.get_shader_parameter("u_hover_metal")) - 1.0) < 0.001, "追1：悬停 uniform u_hover_metal 同步==1（高光出现）")
		check((mat.get_shader_parameter("u_mouse_screen") as Vector2).is_equal_approx(inside),
			"追1：u_mouse_screen==光标屏幕坐标（高光随光标移动，SCREEN_UV 同口径）")
	# 移出渐出
	var outside: Vector2 = Vector2(-500.0, -500.0)
	for i: int in range(12):
		talk.call("hover_probe", outside, 0.2)
	check(float(talk.call("get_hover_metal_energy")) < 0.001, "追1：移出面板 → 能量渐出至 0（非悬停无高光）")
	container.queue_free()
	talk.queue_free()
	await process_frame

## 立绘落位核心断言（相对几何：测试用 metrics 直算 witness/立绘当前态，与实现共用同一数学源）
func _check_portrait_fit(talk: Control, prt: TextureRect, dp: Control, met: GDScript, tag: String) -> void:
	var panel_top: float = dp.global_position.y
	var m: Dictionary = met.call("measure", String(talk.get("portrait_path")))
	var f: Dictionary = met.call("fit_in_box", m["size"], m["rect_px"], prt.size)
	var foot_g: float = prt.global_position.y + float(f["foot_local_y"])
	var head_g: float = prt.global_position.y + float(f["head_local_y"])
	check(absf(foot_g - (panel_top - GAP)) <= 2.0,
		"落位[%s]：可见脚底全局 y==面板顶−30（±2px，实测差 %.2f）" % [tag, foot_g - (panel_top - GAP)])
	check(head_g >= -0.5, "落位[%s]：可见头顶不出屏（全局 y=%.1f）" % [tag, head_g])
	check(prt.size.y <= BOX_H + 0.5, "落位[%s]：盒高≤620（放大档上限）" % tag)
	check(absf((prt.global_position.x + prt.size.x * 0.5) - W * 0.5) <= 2.0, "落位[%s]：水平居中不变（中心 x==576±2）" % tag)

# ==================== 段 D：level 见证者气泡落位（spec 验收 2） ====================

func _sec_level(met: GDScript) -> void:
	get_root().get_node("SaveManager").load_game()
	var container: Control = Control.new()
	container.size = Vector2(W, H)
	add_child(container)
	var lvl: Control = (load(LEVEL_SCENE) as PackedScene).instantiate()
	lvl.call("set_context", {"chapter": 1, "replay": false})
	container.add_child(lvl)
	await process_frame
	await process_frame
	var wit: TextureRect = lvl.get_node("WitnessPortrait")
	var bub: Label = lvl.get_node("WitnessBubble")
	# 批次 Y（Y-C8）：台词源=洗牌袋（剧情对话/气泡_第N关.json，Y4 域交付）；本套件注入
	# tests/fixtures 短句夹具保几何确定性——旧 WITNESS_BUBBLE_LINES 顺序轮换已退役，正式
	# 长句经 autowrap+fit_content 自适应盒体（盒底贴头几何不变，见 _sync_bubble_y 动态 size.y）。
	lvl.call("load_witness_lines_from_path", "res://tests/fixtures/bubble_y5_fixture.json")
	lvl.set_process(false)  # 确定性驱动：手动喂 delta（test_level_extra 同款）
	lvl.call("_process", 0.0)  # 捕获浮动基准位
	var x_before: float = bub.position.x
	# D-1 弹出瞬时贴头
	lvl.call("_show_witness_bubble")
	_check_bubble_fit(lvl, wit, bub, met, "弹出瞬时")
	# D-2 浮动中同步（phase=1.2 → witness 位移，气泡同 tick 跟随，振幅内恒贴不穿头）
	lvl.set("_witness_float_phase", 0.0)
	lvl.call("_process", 0.6)
	_check_bubble_fit(lvl, wit, bub, met, "浮动中")
	check(absf(bub.position.x - x_before) < 0.01, "气泡：x 不随浮动变化（仅 y 同步）")
	# D-3 隐藏后再弹重算
	lvl.call("_hide_witness_bubble")
	lvl.call("_show_witness_bubble")
	_check_bubble_fit(lvl, wit, bub, met, "复弹")
	# D-4 气泡盒高（回修2 F 等价替换留痕：64.8→40 紧凑固定高——盒小居中后文字自然贴近头顶）
	check(absf(bub.size.y - 40.0) <= 0.5, "回修2 F：气泡盒高紧凑 40（64.8→40，等价替换 D-4 旧断言）")
	# D-5 浮动振幅常量（防穿头机制的前提）
	var cmap: Dictionary = {}
	for k: String in ["WITNESS_FLOAT_AMP"]:
		cmap[k] = (load("res://scenes/level/level_scene.gd") as GDScript).get(k)
	check(absf(float(cmap["WITNESS_FLOAT_AMP"]) - 6.0) < 0.001, "气泡：WITNESS_FLOAT_AMP==6（浮动振幅，同步覆盖防穿头）")
	# ==================== M-D 提交前回修（用户验收 2026-09-08，四项） ====================
	# E-1 台词池（批次 Y Y-C8 等价改写：旧 WITNESS_BUBBLE_LINES 数组随洗牌袋退役——
	# 池改经 level_scene.get_witness_lines_pool() 读取；「5~8 条/≤20 字」风格规则仅约束
	# 旧试写稿，正式文案（Y4 域）由用户提供不受此限，铁律 8 不变）。
	var lines_v: Variant = lvl.call("get_witness_lines_pool")
	check(lines_v is Array and (lines_v as Array).size() >= 2,
		"回修E-1（Y-C8 改写）：洗牌袋台词池非空（夹具 %d 条）" % ((lines_v as Array).size() if lines_v is Array else -1))
	if lines_v is Array:
		var all_ok := true
		for line: Variant in (lines_v as Array):
			if not (line is String) or String(line).is_empty():
				all_ok = false
		check(all_ok, "回修E-1（Y-C8 改写）：每条文案为非空 String")
	# E-2 弹出显示池内文案（批次 Y Y-C8 等价改写：轮换语义升级为洗牌袋——整轮不重复，
	# 连续两抽必不同为直接推论；文本∈池断言保持）。
	var t1: String = String(bub.text)
	if lines_v is Array:
		check(t1 in (lines_v as Array), "回修E-2：弹出文本∈洗牌袋台词池（首条=%s）" % t1)
		lvl.call("_hide_witness_bubble")
		lvl.call("_show_witness_bubble")
		check(String(bub.text) in (lines_v as Array) and String(bub.text) != t1,
			"回修E-2：再次弹出文本∈池且与上句不同（洗牌袋轮内不重复，%s → %s）" % [t1, String(bub.text)])
		lvl.call("_hide_witness_bubble")
		lvl.call("_show_witness_bubble")  # 恢复弹出态（后续几何/hover 断言前提）
	# E-3 → 回修2 F 等价替换留痕（用户反馈「贴底看着非常奇怪」）：文字改盒内垂直居中
	# （CENTER），盒高紧凑 40 后居中文字自然贴近头顶；贴可见头顶−4 的盒位口径不变
	check(int(bub.vertical_alignment) == VERTICAL_ALIGNMENT_CENTER,
		"回修2 F：气泡文字盒内垂直居中（VERTICAL_ALIGNMENT_CENTER，等价替换 E-3 贴底断言）")
	var bsb: StyleBox = bub.get_theme_stylebox("normal")
	check(bsb is StyleBoxFlat, "回修E-3：气泡背板 StyleBoxFlat（半透明底）")
	if bsb is StyleBoxFlat:
		var bbf := bsb as StyleBoxFlat
		check(bbf.bg_color.a >= 0.70 and bbf.bg_color.a <= 0.80,
			"回修E-3：气泡背板 α∈[0.70,0.80]（深浅同对话背板口径，当前 %.3f）" % bbf.bg_color.a)
		check(bbf.corner_radius_top_left >= 10, "回修E-3：背板圆角 ≥10（UI 卡片语言一致）")
		check(bbf.shadow_size == 0, "回修E-3：背板投影置 0（外投影移交材质，L-A 契约）")
		var visual_gap: float = BUBBLE_GAP + float(bbf.content_margin_bottom)
		# 回修2 F 留痕：文字改盒内居中后「贴底间距」口径废止——贴头性由「盒底贴头顶−4」
		# （D 段 _sync_bubble_y 断言）+ 盒高紧凑 40（D-4）共同达成，本断言仅保留背板边距上限
		check(visual_gap <= 15.0, "回修2 F：背板下边距口径保留（GAP(%.0f)+margin_bottom(%.0f)=%.0f ≤15px）" % [BUBBLE_GAP, bbf.content_margin_bottom, visual_gap])
	check(bub.get_theme_font_size("font_size") == 18, "回修E-3：气泡字号 18（UI 语言一致、看得清）")
	var ls_gd: GDScript = load("res://scenes/level/level_scene.gd") as GDScript
	var fcd: Color = ls_gd.get("BUBBLE_FONT_DARK")
	check(fcd.a >= 0.9 and fcd.r > fcd.b, "回修E-3：气泡字色=米白系（r>b 亮色；AB-3 唯一真值）")
	# 批次 AB-3：BUBBLE_FONT_LIGHT 浅档随深浅主题机制删除退役——反向锁。
	check(ls_gd.get_script_constant_map().get("BUBBLE_FONT_LIGHT", null) == null,
		"AB-3 反向锁：BUBBLE_FONT_LIGHT 浅档常量退役（无复辟）")
	# E-4 hover 光晕：witness 代理热区（气泡 mouse_filter=IGNORE 不挡射线拾取）
	check(int(bub.get("mouse_filter")) == 2, "回修E-4：气泡 mouse_filter=IGNORE（不挡关卡射线拾取）")
	check(bub.get("material") == null, "回修E-4：气泡 Label 无材质（ui_material 挂 Label 会以字体图集 UV 误判 SDF 破坏文字——T11 实证坑，文字保持纯主题绘制）")
	var gnode: Control = lvl.get_node_or_null("WitnessBubbleGlow")
	check(gnode is ColorRect, "回修E-4：气泡光晕覆盖层 WitnessBubbleGlow 存在（hover_glow 体系）")
	if gnode != null:
		check(int(gnode.get("mouse_filter")) == 2, "回修E-4：覆盖层 mouse_filter=IGNORE（不挡射线/手势 HUD）")
		var gmat: ShaderMaterial = gnode.material as ShaderMaterial
		check(gmat != null and gmat.shader != null and String(gmat.shader.resource_path).ends_with("hover_glow.gdshader"),
			"回修E-4：覆盖层挂 hover_glow.gdshader（M-C 光斑体系复用）")
		if gmat != null:
			check(absf(float(gmat.get_shader_parameter("u_glow_k")) - 0.16) < 0.001,
				"回修E-4：加色 u_glow_k==0.16（M-C 定档字面口径）")
			check(absf(float(gmat.get_shader_parameter("u_glow_radius_btn")) - 85.0) < 0.01,
				"回修E-4：径向半径 85（M-C 按钮档定档字面口径）")
			check(absf(float(gmat.get_shader_parameter("u_strength"))) < 0.001, "回修E-4：非悬停 u_strength==0（光晕不出现）")
			# 悬停代理：probe 光标至 witness 立绘区中心 → 总幅渐入至 1（加色峰值 0.16=M-C 档）；移出归 0
			var wit_center: Vector2 = wit.get_global_rect().get_center()
			for i: int in range(12):
				lvl.call("_bubble_hover_probe", wit_center, 0.2)
			check(absf(float(gmat.get_shader_parameter("u_strength")) - 1.0) < 0.01,
				"回修E-4：悬停 witness 代理 → 总幅渐入至 1.0（加色峰值 0.16=M-C 同档）")
			# 窗口缩放坐标修复1c（2026-09-18）同步：u_mouse_px 契约恒为 hover_glow 设备系
			# （与 main.gd u_mouse_px 同口径），sim 值（content 口径）现在也经
			# content→device 换算后写入——断言期望值同步乘 viewport screen_transform
			#（无头=0.0556 虚拟缩放，窗口=拉伸 s；命中判定仍为 content 系原值不动）。
			var want_px: Vector2 = lvl.get_viewport().get_screen_transform() * wit_center
			check((gmat.get_shader_parameter("u_mouse_px") as Vector2).is_equal_approx(want_px),
				"回修E-4：u_mouse_px==光标位置×screen_transform（hover_glow 设备系，修复1c 契约）")
			var rects_p: Array = gmat.get_shader_parameter("u_rects")
			check(rects_p != null and (rects_p as Array).size() >= 1,
				"回修E-4：u_rects 已写入（光斑目标=气泡矩形）")
			check(gnode.visible, "回修E-4：悬停期覆盖层可见")
			for i: int in range(12):
				lvl.call("_bubble_hover_probe", Vector2(-500.0, -500.0), 0.2)
			check(float(gmat.get_shader_parameter("u_strength")) < 0.001, "回修E-4：移出 witness → 总幅归 0（非悬停无光晕）")
			check(not gnode.visible, "回修E-4：非悬停期覆盖层隐藏（零绘制成本）")
	container.queue_free()
	lvl.queue_free()
	await process_frame

func _check_bubble_fit(lvl: Node, wit: TextureRect, bub: Label, met: GDScript, tag: String) -> void:
	var m: Dictionary = met.call("measure", String(lvl.call("get_witness_texture_path")))
	var f: Dictionary = met.call("fit_in_box", m["size"], m["rect_px"], wit.size)
	var top_g: float = wit.global_position.y + float(f["head_local_y"]) * wit.scale.y
	var bottom_g: float = bub.global_position.y + bub.size.y
	check(absf(bottom_g - (top_g - BUBBLE_GAP)) <= 2.0,
		"气泡[%s]：全局底==可见头顶−4（±2px，实测差 %.2f）" % [tag, bottom_g - (top_g - BUBBLE_GAP)])
