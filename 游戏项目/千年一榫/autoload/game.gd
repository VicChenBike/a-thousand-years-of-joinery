extends Node
## Game：全局状态机 + 场景路由。依据 spec 5.1。

signal state_changed(from_state: int, to_state: int)
## 批次 Z（Z6-P2-8，spec §6）：覆盖层开合轻量信号——GestureHUD 据此当帧 apply_dock 即时重排
##（旧仅 0.5s 轮询 → 开设置后 ≤0.5s 内 HUD 仍按 LEVEL 停靠压在面板上，层 64>覆盖层 1）；
## 轮询留作兜底（mark_settle_entered 等无信号迁移仍由轮询承担）。
signal overlay_changed(opened: bool)

enum State { BOOT, MAIN_MENU, OPENING_MOVIE, TALK, LEVEL, SETTLE, CATALOG, FINALE }

const SCENE_PATHS := {
	State.MAIN_MENU: "res://scenes/menu/main_menu.tscn",
	State.OPENING_MOVIE: "res://scenes/movie/opening_movie.tscn",
	State.TALK: "res://scenes/dialog/talk_scene.tscn",
	State.LEVEL: "res://scenes/level/level_scene.tscn",
	State.SETTLE: "res://scenes/settle/settle_scene.tscn",
	State.CATALOG: "res://scenes/catalog/catalog_scene.tscn",
	State.FINALE: "res://scenes/finale/finale_scene.tscn",
}
const SETTINGS_SCENE := "res://scenes/settings/settings_panel.tscn"
const SHOP_SCENE := "res://scenes/shop/shop_panel.tscn"

var _state: int = State.BOOT
var _context: Dictionary = {}
var _replay: bool = false
# O5（批次 O，2026-09-10）单槽来源记忆 → 批次 AA / W5（2026-09-25）升级为**有界返回栈**
# （规格 §8.3 W5-1/§8.4 语义表）。单槽覆盖语义（goto_state(CATALOG) 覆盖快照、跳非
# CATALOG 目标清空）在「TALK→设置→图鉴→关卡→退→图鉴→退」多跳链下把快照覆盖成 LEVEL，
# 造成 LEVEL↔CATALOG 永久乒乓（用户称致命死循环）——现由栈治本：
# 【返回栈语义表（规格 §8.4 逐条）】
# - 可返回来源（入栈）：TALK/SETTLE/OPENING_MOVIE/MAIN_MENU/LEVEL（覆盖层态视为主宿状态，
#   settings._on_catalog 在 goto 前已关层，old 记录的是宿主态）；
# - 不可返回来源（不入栈）：BOOT（启动态）；old==CATALOG（图鉴自跳不压不盖）；
#   **old==LEVEL 且 _level_from_catalog**（该关由图鉴进入——其退出回图鉴属图鉴行程内嵌
#   分支，来源仍由栈中更早条目承担。注：规格 §8.4 字面规则不含此条时主复现链仍弹回
#   LEVEL、§8.5-1 末态 TALK 不可达，第三条跳过条件系满足验收口径的最小必要偏离，已登记）；
# - 入栈时机：仅 goto_state(CATALOG) 入口，快照 _context 覆写前 duplicate(true)；SETTLE
#   来源额外合并 settle_snapshot 结算字段（§8.4「SETTLE 入栈 ctx 须含结算快照」，W6-1）；
# - 出栈时机：图鉴退出（catalog_scene._on_exit_pressed → pop_catalog_return）弹栈顶按
#   state/ctx 路由；出栈后**不清栈**（支持连续多跳返回）；
# - 栈空兜底：pop 得空 → 消费方回落 MAIN_MENU（O5 旧契约保持）；
# - 清栈时机：① goto_state(MAIN_MENU)（导航根，历史无意义）；② 新游戏（自 MAIN_MENU 发起
#   时①已覆盖，零残留由①保证）；③ 深度溢出 >CATALOG_RETURN_MAX_DEPTH 丢最旧（队头 pop_front）；
#   **跳往非 CATALOG 目标不再无条件清栈**（旧 else 分支退役=乒乓直接成因）；
# - 兼容面：catalog_return = **栈顶镜像（只读）**，由 push/pop/clear 单点同步；存量单跳件
#   （test_o_catalog_shop/test_p_wave1/test_p_settle/test_y5_dialog_route）按 Dictionary
#   消费零改动（P3 MOVIE/TALK 透传、P批波2 SETTLE 透传、消费后复位契约全部保持）。
## 深度上界 8【暂定值·待用户复验】（规格 §15 调参表集中常量，禁散落魔改）。
const CATALOG_RETURN_MAX_DEPTH: int = 8
var catalog_return_stack: Array = []
var catalog_return: Dictionary = {}
## 批次 AA / W6（规格 §9.3 W6-1）：结算专用快照 {chapter,grade,score,elapsed,talent,replay}。
## level_scene._goto_settle 记账写入（_settled 恰一次守卫）；_enter_settle_direct 优先读它、
## 其次读 ctx、最后兜底「——」+push_warning（W6-2）。独立于 _context 与返回栈 ctx（防污染
## 「进关上下文」语义）；生命周期（W6-5）：goto_state 进入 SETTLE/CATALOG 保留（结算在场/
## 绕行通道），其余目标清空（MAIN_MENU、新游戏链 TALK/MOVIE、LEVEL 重玩皆零残留）；
## mark_settle_entered 不触碰（结算显示依赖）。SETTLE 来源入栈时其字段合并进快照 ctx
## （§8.4 语义表末行）。
var settle_snapshot: Dictionary = {}
## 乒乓阻断标记：当前是否处于「由图鉴进入的关卡」（goto_state(LEVEL) 且 old==CATALOG）。
## 该关退出回图鉴时跳过入栈（见上语义表第三条跳过条件）；任何 goto_state 后重算。
var _level_from_catalog: bool = false
var _scene_container: Control
var _overlay_layer: CanvasLayer
var _hud_layer: CanvasLayer = null   # 批次 U（U5⑧）：GestureHUDLayer(64) 引用登记（层级台账/主题传播用）
var _overlay_instance: Node
var _current_scene: Node

func attach(container: Control, overlay_layer: CanvasLayer, hud_layer: CanvasLayer = null) -> void:
	_scene_container = container
	_overlay_layer = overlay_layer
	_hud_layer = hud_layer   # 批次 U（U5⑧）：HUD 层登记；open_overlay 避让参数零改动（面板避让由 settings 侧读 Game.current_state()）

func current_state() -> int:
	return _state

## P-D①（批次 P 波 2）：主路径结算记账——level 覆盖层结算 UI 显现时同步状态机为 SETTLE。
## 原 goto_state(SETTLE) 语义拆分：场景切换部分由 level 内部结算取代（零重建零回正零切换），
## 「经过 SETTLE 态」的状态面依赖保持兼容——O5 catalog_return 快照（进图鉴时 state==SETTLE）、
## 设置面板「结算页可开」等判据。仅改 _state：不加载场景、不发 state_changed（无场景变化，
## 无外部监听者消费该差异；SCENE_PATHS 契约表不动）。
func mark_settle_entered() -> void:
	_state = State.SETTLE

func context() -> Dictionary:
	return _context

func is_replay() -> bool:
	return _replay

func get_current_scene() -> Node:
	if _current_scene != null and is_instance_valid(_current_scene):
		return _current_scene
	return null

func goto_state(s: int, ctx: Dictionary = {}) -> void:
	var old: int = _state
	# 批次 AA / W7-4（规格 §10.3 W7-4）：场景切换**前**显式释放残留按压态——走 Router 同一
	# reset 通路（state_changed → _on_game_state_changed → reset_runtime；§23.1.3「不新增
	# 第二套清态入口」），提前到旧场景卸载之前：引擎 mouse_focus 若指向旧场景控件，先补发抬起
	# 清掉按住态再卸载，卡死按压不跨关卡/跨结算存活（用户「通关后退出/下一关也点不动」）。
	# 幂等：reset_runtime 逐成员判空 + 无合成持压时零事件；随后 state_changed 触发的那次重复
	# 调用因标志/台账已清而 no-op（不会重复发抬起）。无 Router 实例（--script 极早期）静默跳过。
	var _rt: Node = get_node_or_null("/root/GestureRouter")
	if _rt != null:
		_rt.call("reset_runtime")
	# 批次 AA / W5-2（规格 §8.3 W5-2）：状态跳转前显式关闭覆盖层——幂等（已关零副作用），
	# 根除「带设置/商店覆盖层切场景」的面板残留（§8.5-5 验收：任一 goto_state 后
	# is_settings_open()/is_shop_open() 恒 false）。open_overlay 自身首行已 close_overlay，
	# 两入口互不重入。
	close_overlay()
	# 批次 AA / W5-1（规格 §8.4 语义表，详注见字段区）：进 CATALOG 入栈（不再覆盖单槽）；
	# BOOT/图鉴自跳/图鉴进关再回图鉴不入栈；跳非 CATALOG 目标**不再无条件清栈**（旧 else
	# 分支退役），仅 MAIN_MENU 按导航根清栈；SETTLE 来源入栈时合并 settle_snapshot（W6-1）。
	# 批次 AA 回修4（W5-P2-1）：第三条跳过条件加 **from_level_exit 来源标记**——旧条件
	# 「old==LEVEL ∧ _level_from_catalog」过度泛化，把「关卡内设置→图鉴」（settings_panel.
	# _on_catalog，生产可达）也一并跳过入栈 → 嵌套链（图鉴→关卡→关内设置→图鉴→退出）
	# 回不到该关卡（W5 前单槽语义下该路径回关卡，O5 修的正是它=语义回归）。现仅关卡
	# 自己的「退出(回图鉴)」按钮路径（level_scene._on_exit_confirmed，ctx 带标记）跳过入栈
	# （LEVEL↔CATALOG 乒乓阻断保持）；关内设置→图鉴正常入栈（退出图鉴回该关卡）。
	if s == State.CATALOG:
		var from_level_exit := bool(ctx.get("from_level_exit", false))
		if old != State.CATALOG and old != State.BOOT \
				and not (old == State.LEVEL and _level_from_catalog and from_level_exit):
			_push_catalog_return(old, _context.duplicate(true))
	elif s == State.MAIN_MENU:
		clear_catalog_return()   # 规则②：主菜单=导航根
	# 乒乓阻断标记重算（任何跳转后）：仅「从图鉴进关」为真。
	_level_from_catalog = (s == State.LEVEL and old == State.CATALOG)
	# 批次 AA / W6-5（规格 §9.3 W6-5）：结算快照生命周期——SETTLE（结算在场）与 CATALOG
	# （绕行通道，清空则边缘路径必断链）保留；其余目标（MAIN_MENU/新游戏链/LEVEL 重玩）清空。
	if s != State.SETTLE and s != State.CATALOG:
		settle_snapshot = {}
	_state = s
	_context = ctx
	_replay = bool(ctx.get("replay", false))
	# K-D（K3-5/K3-6）自动穿戴状态机（Q2 单点收口，spec §7.4 时序表逐行）：TALK/LEVEL 先解锁该章原创
	# （点位①，幂等）再强制穿戴——首次进关（含关前剧情立绘）即成立。批次 Y 挂载对齐后口径：
	# after_level 关后对话挂载传 chapter=n+1（即将进入的关，level_scene 结算分流/settle 路由同式），
	# 故本处穿戴归属=ctx.chapter 指向的即将进入那套（不再是旧「刚通关那套 ctx.chapter=n」表述）；
	# SETTLE/MAIN_MENU/CATALOG 换回自选（Q2）。
	# 批次 AD 步骤四（spec §4.4.1）：FINALE=通关终局「未完待续」界面，属**非关卡场景组**，
	# 并入下方换回自选组（终局页滞留第 5 章强制穿戴不合终局氛围，通关后玩家自主选装更妥）。
	# 其余分支天然兼容零改动逐条留痕（T0 探查结论；回归锚 tests/test_ad_batch4_finale.gd 段 E）：
	# ①返回栈入栈判据（s==CATALOG 专有）：终局态经「设置→图鉴」正常入栈；退出图鉴时
	#   catalog._on_exit_pressed 对 FINALE 来源无特判分支 → 兜底 MAIN_MENU——终局唯一出口
	#   即主菜单（与本页 BackButton 同式），语义自洽不破坏「通关后回主菜单」大方向，
	#   spec §4.4.2 未要求终局→图鉴回链，不越权补透传分支；
	# ②_level_from_catalog 重算（s==LEVEL∧old==CATALOG）：FINALE 两侧均不命中，恒 false 正确；
	# ③settle_snapshot 保留组（s==SETTLE‖s==CATALOG）：FINALE 不在保留组 → 进终局即清，正确
	#   （结算链在「下一关」按下时已消费完毕，终局页不显示任何结算数据，零残留防越态显示）；
	# ④BGM 联动（判据=OPENING_MOVIE 进出）：FINALE 无涉，bgm 延续淡入态正确；
	# ⑤_load_main_scene SETTLE 特判（改载 level）：FINALE 走通用 SCENE_PATHS 映射，零改动；
	# ⑥MAIN_MENU 清栈（s==MAIN_MENU）：终局「返回主菜单」即走此支，返回栈清空正确。
	var chapter := int(ctx.get("chapter", 0))
	if s == State.TALK or s == State.LEVEL:
		if chapter >= 1:
			SaveManager.unlock_origin_skin(chapter)
			SaveManager.apply_contextual_skin(chapter)
	elif s == State.SETTLE or s == State.MAIN_MENU or s == State.CATALOG or s == State.FINALE:
		SaveManager.restore_preferred_skin()
	# BGM 联动（2026-08-27）：进入开场动画 → 淡出渐停；离开开场动画（→TALK/CATALOG）→ 淡入恢复。
	# 判定以调用前的旧状态 old 为准（_state 已被覆盖），两条入口（首玩/图鉴回看）统一收口于此。
	if s == State.OPENING_MOVIE:
		AudioManager.fade_out_bgm()
	elif old == State.OPENING_MOVIE:
		AudioManager.fade_in_bgm()
	_load_main_scene(s)
	state_changed.emit(old, s)

## 批次 AA / W5-1：返回栈入栈（仅 goto_state(CATALOG) 内部调用）。SETTLE 来源把
## settle_snapshot 字段合并进快照 ctx（§8.4 语义表末行——图鉴快照不丢结算链，W6-1）；
## 溢出丢最旧（队头 pop_front），栈深恒 ≤CATALOG_RETURN_MAX_DEPTH；栈顶镜像同步。
func _push_catalog_return(st: int, c: Dictionary) -> void:
	if st == State.SETTLE and not settle_snapshot.is_empty():
		for k: Variant in settle_snapshot.keys():
			c[k] = settle_snapshot[k]
	catalog_return_stack.append({"state": st, "ctx": c})
	while catalog_return_stack.size() > CATALOG_RETURN_MAX_DEPTH:
		catalog_return_stack.pop_front()
	# 批次 AA（P3-b，W5-P3-2）：栈顶镜像改**快照**（旧=引用别名，「只读」纯靠约定，
	# 外部写穿栈内条目即串镜像）——深拷贝与栈内条目解耦。
	catalog_return = (catalog_return_stack.back() as Dictionary).duplicate(true)

## 批次 AA / W5-1：出栈（图鉴退出消费口）。弹栈顶并把镜像同步为新栈顶（空栈→{}）；
## 空栈返回 {}（消费方按旧契约兜底 MAIN_MENU）。pop 后**不清栈**（支持连续多跳返回）。
func pop_catalog_return() -> Dictionary:
	if catalog_return_stack.is_empty():
		catalog_return = {}
		return {}
	var entry: Dictionary = catalog_return_stack.pop_back()
	# 批次 AA（P3-b，W5-P3-2）：镜像同步同改快照（与 _push_catalog_return 同口径）。
	catalog_return = (catalog_return_stack.back() as Dictionary).duplicate(true) \
			if not catalog_return_stack.is_empty() else {}
	return entry

## 批次 AA / W5-1：清栈（goto_state(MAIN_MENU) 规则② 调用；新游戏由①覆盖零残留）。
func clear_catalog_return() -> void:
	catalog_return_stack.clear()
	catalog_return = {}

## 批次 AA / W5-1：栈深查询（测试/诊断锚；红期 API 缺席时测试按 -1 判红）。
func catalog_return_depth() -> int:
	return catalog_return_stack.size()

func _load_main_scene(s: int) -> void:
	# P-D⑥（批次 P 波 2）：SETTLE 态特判——结算显示已由 level 覆盖层承载（level._goto_settle
	# 主路径零切换），settle_scene.tscn 退役不再被路由（文件保留防 asset 断链）：
	# goto_state(SETTLE) 入口保留（枚举/O5 快照/自动穿戴语义不变），场景改载 level 并注入
	# settle:true——level _ready 检测后重建关卡体素+跳过动画直显结算 UI 与建模（边缘路径）。
	if s == State.SETTLE:
		_context["settle"] = true
	if _scene_container == null:
		return
	for child: Node in _scene_container.get_children():
		if child == _current_scene:
			_current_scene = null
		child.queue_free()
	var path: String = SCENE_PATHS.get(s, "")
	if s == State.SETTLE:
		path = SCENE_PATHS.get(State.LEVEL, path)  # 特判：SETTLE → level 场景（settle 模式）
	if path == "" or not ResourceLoader.exists(path):
		push_warning("场景缺失: %s（占位跳过）" % path)
		return
	var inst: Node = load(path).instantiate()
	# 重要：set_context 必须在 add_child 之前调用——add_child 会立即触发 _ready，
	# 场景在 _ready 里消费上下文（如关卡的 chapter），顺序颠倒会导致上下文丢失。
	if inst.has_method("set_context"):
		inst.call("set_context", _context)
	_scene_container.add_child(inst)
	_current_scene = inst

func open_overlay(kind: String) -> void:
	if _overlay_layer == null:
		return
	close_overlay()
	var path: String = SETTINGS_SCENE if kind == "settings" else SHOP_SCENE
	if not ResourceLoader.exists(path):
		push_warning("覆盖层场景缺失: %s" % path)
		return
	_overlay_instance = load(path).instantiate()
	# J6-P1-1（根因实证 canvas_theme_probe.gd：CanvasLayer 无 theme 属性、主题传播止于
	# CanvasLayer 边界）：覆盖层根 Control 显式赋当前主题。批次 AB-3：深浅主题机制删除，
	# theme_changed 监听/断开退役——恒赋深色主题（ThemeManager 退化为深色唯一提供者）。
	if _overlay_instance is Control:
		(_overlay_instance as Control).theme = ThemeManager.current_theme()
	_overlay_layer.add_child(_overlay_instance)
	overlay_changed.emit(true)   # Z6-P2-8：开覆盖层当帧广播（HUD 即时重排消费）

func has_open_overlay() -> bool:
	return _overlay_instance != null and is_instance_valid(_overlay_instance)

## 批次 R（spec §10.2）：覆盖层类型只读助手——手势路由状态矩阵判定用（两行转发既有覆盖层引用）
func is_settings_open() -> bool:
	return has_open_overlay() and _overlay_instance.scene_file_path == SETTINGS_SCENE

func is_shop_open() -> bool:
	return has_open_overlay() and _overlay_instance.scene_file_path == SHOP_SCENE

func close_overlay() -> void:
	var had := _overlay_instance != null and is_instance_valid(_overlay_instance)
	if had:
		_overlay_instance.queue_free()
		_overlay_instance = null
		overlay_changed.emit(false)   # Z6-P2-8：关覆盖层当帧广播（_overlay_instance 先清后发，
		                              # 消费方读 is_settings/is_shop_open 即 false）

# ---------- K-C（K4-2）：全局 toast 便捷入口（main.gd 注入；未注入降级） ----------
var _toast_center: Node = null
func attach_toast(center: Node) -> void:
	_toast_center = center
func toast(text: String, level: String = "warn", seconds: float = 2.5, centered: bool = false) -> void:
	# M-E 回修3 E：centered=true → 顶部中央锚点盒（关卡对接失败弹窗，不遮顶栏/侧面板）；
	# 批次 V（V-C1，spec §3.4 裁决）：centered=true 且 TopStrip 已挂接 → 单点改道 _strip.push_info
	#（顶部统一弹条，独立层 63 棕主题；商店余额不足等全部中央提示自动获益）；未挂接降级与
	# centered=false 维持右上原路径，其他界面零影响。
	if centered and _strip != null and is_instance_valid(_strip) and _strip.has_method("push_info"):
		_strip.call("push_info", text, seconds)
		return
	if _toast_center != null and is_instance_valid(_toast_center):
		_toast_center.call("push", text, level, seconds, centered)
	else:
		push_warning("Toast 未挂接，降级：%s" % text)

# ---------- 批次 V（V-C1，spec §3.1/§3.4）：TopStrip 统一弹条注入（attach_toast 同款降级判空模式） ----------
var _strip: Node = null
func attach_strip(strip: Node) -> void:
	_strip = strip

# ---------- 批次 V（V-C3a，spec §3.1/§3.2）：Game 级统一弹条入口（confirm/info 消费地基） ----------
## confirm 类消费方（settings_panel 摄像头钮、main_menu 新游戏/退出、level_scene 退出、
## shop_panel 购买确认）单点收口：已注册 strip（attach_strip 收到过）→ 委托 push_confirm
##（TopStrip confirm 模式常驻直至用户选择）；未注册（极端时序/无头 fresh 实例）→ 兜底 toast
## 居中警示（信息可达性，不静默丢弃）+ push_warning 留痕，回调不执行——无条即无确认/取消
## 按钮，静默执行会制造不可撤销副作用。对 strip 的判空/has_method 守卫与 toast 改道分支同款
##（降级判空模式）；回调判空一律 is_valid()（4.7 坑 1，不引入 bool/Callable 强转）。
func confirm(text: String, on_confirmed: Callable = Callable(), on_canceled: Callable = Callable()) -> int:
	if _strip != null and is_instance_valid(_strip) and _strip.has_method("push_confirm"):
		_strip.call("push_confirm", text, on_confirmed, on_canceled)
		# 批次 Z（Z6-P1-5/P2-9，spec §6）：返回本次 confirm 的句柄序号——调用方（settings/shop
		# 面板）记位「自己那条」，_exit_tree 仅在自有序号仍活动时 dismiss（get_active_confirm_seq
		# 比对）；既有调用方忽略返回值零变化（GDScript 允许丢弃返回值作语句）。
		return get_active_confirm_seq()
	push_warning("Game.confirm 未挂接 TopStrip，降级 toast：%s" % text)
	toast(text, "warn", 3.0, true)
	return -1

## 批次 Z（Z6-P1-5/P2-9，spec §6）：当前活动 confirm 的句柄序号（无条/替身 strip 缺方法=-1）。
## TopStrip.push_confirm 每次自增 _confirm_seq，活动期返回当前序号、非 confirm 态返回 -1。
func get_active_confirm_seq() -> int:
	if _strip != null and is_instance_valid(_strip) and _strip.has_method("active_confirm_seq"):
		return int(_strip.call("active_confirm_seq"))
	return -1

## info 便捷口（与 confirm 对称）：= toast(text, "warn", seconds, true)——TopStrip 已挂接时由
## toast 的 V-C1 单点改道进 push_info（顶部统一弹条），未挂接降级右上原路径；
## 既有 toast 行为零改动。
func info(text: String, seconds: float = 3.0) -> void:
	toast(text, "warn", seconds, true)

## 批次 V 回修② P2-2：覆盖层/面板关闭时挂起 confirm 残留收口——委托 TopStrip.dismiss_active_confirm
##（仅 confirm 模式：on_canceled 回调执行+按取消收起，零副作用=不调 on_confirmed；info 不动）。
## strip 未挂接/未含该方法（旧替身 spy）时静默 no-op（降级判空模式，与 confirm/toast 改道分支同款守卫）。
func dismiss_confirm() -> void:
	if _strip != null and is_instance_valid(_strip) and _strip.has_method("dismiss_active_confirm"):
		_strip.call("dismiss_active_confirm")
