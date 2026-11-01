extends "res://tests/test_base.gd"
## T07 判定用例：Game 全局状态机契约无头测试（TDD 先写）。
## 契约来源：实施计划 T07「契约」节（与 spec 5.1 一致）：
##   枚举 State{BOOT,MAIN_MENU,OPENING_MOVIE,TALK,LEVEL,SETTLE,CATALOG}
##   信号 state_changed(from,to)；方法 goto_state/current_state/get_current_scene/
##   has_open_overlay/open_overlay/close_overlay/is_replay/context/attach；
##   场景路径常量 SCENE_PATHS / SETTINGS_SCENE / SHOP_SCENE。
## 说明：本测试直接实例化 game.gd 脚本（不依赖 autoload 注册，注册由主会话统一处理），
## 也不依赖任何其它单例，可独立无头运行。

const GAME_SCRIPT := "res://autoload/game.gd"

var _signals: Array = []

func _initialize() -> void:
	var script: Variant = load(GAME_SCRIPT)
	if script == null:
		check(false, "加载 %s（红灯：实现尚未创建）" % GAME_SCRIPT)
		finish()
		return
	var consts: Dictionary = (script as GDScript).get_script_constant_map()
	var st: Dictionary = consts.get("State", {})
	var game: Node = (script as GDScript).new()
	add_child(game)

	# ---- 1. 枚举值（契约顺序）----
	check_eq(int(st.get("BOOT", -1)), 0, "State.BOOT == 0")
	check_eq(int(st.get("MAIN_MENU", -1)), 1, "State.MAIN_MENU == 1")
	check_eq(int(st.get("OPENING_MOVIE", -1)), 2, "State.OPENING_MOVIE == 2")
	check_eq(int(st.get("TALK", -1)), 3, "State.TALK == 3")
	check_eq(int(st.get("LEVEL", -1)), 4, "State.LEVEL == 4")
	check_eq(int(st.get("SETTLE", -1)), 5, "State.SETTLE == 5")
	check_eq(int(st.get("CATALOG", -1)), 6, "State.CATALOG == 6")

	# ---- 2. 初始状态 ----
	check_eq(game.current_state(), 0, "初始状态为 BOOT")
	check(game.get_current_scene() == null, "未 attach 时 get_current_scene() 为 null")
	check(game.is_replay() == false, "is_replay() 默认 false")
	check(game.has_open_overlay() == false, "has_open_overlay() 默认 false")
	check(game.context().is_empty(), "初始 context 为空")

	# ---- 3. 状态切换与信号（from, to 顺序）----
	game.state_changed.connect(_on_state_changed)
	game.goto_state(int(st["MAIN_MENU"]))
	check_eq(game.current_state(), 1, "goto_state(MAIN_MENU) 生效")
	check_eq(_signals.size(), 1, "state_changed 发射一次")
	if _signals.size() == 1:
		var sig: Array = _signals[0]
		check_eq(sig[0], 0, "state_changed.from == BOOT")
		check_eq(sig[1], 1, "state_changed.to == MAIN_MENU")

	# ---- 4. ctx 传递与 replay 标记 ----
	game.goto_state(int(st["LEVEL"]), {"chapter": 2, "replay": true})
	check_eq(int(game.context().get("chapter", -1)), 2, "ctx.chapter == 2")
	check(game.is_replay() == true, "ctx.replay=true → is_replay() 为 true")
	game.goto_state(int(st["LEVEL"]), {"chapter": 1})
	check(game.is_replay() == false, "ctx 无 replay → is_replay() 回落 false")

	# ---- 5. 场景路径常量（契约表）----
	var sp: Dictionary = consts.get("SCENE_PATHS", {})
	check_eq(String(sp.get(int(st["MAIN_MENU"]), "")), "res://scenes/menu/main_menu.tscn", "MAIN_MENU 场景路径")
	check_eq(String(sp.get(int(st["OPENING_MOVIE"]), "")), "res://scenes/movie/opening_movie.tscn", "OPENING_MOVIE 场景路径")
	check_eq(String(sp.get(int(st["TALK"]), "")), "res://scenes/dialog/talk_scene.tscn", "TALK 场景路径")
	check_eq(String(sp.get(int(st["LEVEL"]), "")), "res://scenes/level/level_scene.tscn", "LEVEL 场景路径")
	check_eq(String(sp.get(int(st["SETTLE"]), "")), "res://scenes/settle/settle_scene.tscn", "SETTLE 场景路径")
	check_eq(String(sp.get(int(st["CATALOG"]), "")), "res://scenes/catalog/catalog_scene.tscn", "CATALOG 场景路径")
	check_eq(String(consts.get("SETTINGS_SCENE", "")), "res://scenes/settings/settings_panel.tscn", "SETTINGS_SCENE 常量")
	check_eq(String(consts.get("SHOP_SCENE", "")), "res://scenes/shop/shop_panel.tscn", "SHOP_SCENE 常量")

	# ---- 6. 未 attach 守卫（容器/覆盖层为 null 不崩溃）----
	game.goto_state(int(st["TALK"]), {"mode": "opening", "chapter": 1})
	check_eq(game.current_state(), 3, "未 attach 也能切换状态（仅不加载场景）")
	game.open_overlay("settings")
	check(game.has_open_overlay() == false, "未 attach 时 open_overlay 不崩溃且无覆盖层")
	game.close_overlay()
	check(true, "未 attach 时 close_overlay 不崩溃")

	# ---- 7. attach 后：MAIN_MENU 场景已存在（T08），其余业务场景仍缺失应跳过 ----
	var container: Control = Control.new()
	var overlay_layer: CanvasLayer = CanvasLayer.new()
	add_child(container)
	add_child(overlay_layer)
	game.attach(container, overlay_layer)
	game.goto_state(int(st["MAIN_MENU"]))
	check_eq(container.get_child_count(), 1, "main_menu.tscn 存在：容器加载 1 个子节点（T08 更新）")
	check(game.get_current_scene() != null, "场景存在时 get_current_scene() 非 null（T08 更新）")
	game.open_overlay("settings")
	check(game.has_open_overlay() == true, "settings_panel.tscn 已存在（T09）：覆盖层已打开（更新）")
	game.open_overlay("shop")
	check(game.has_open_overlay() == true, "shop_panel.tscn 已存在（T10）：覆盖层已打开（更新）")

	# ---- 8. K-C（KC-2）：全局 toast 入口——未注入 ToastCenter 时降级不崩、状态不变 ----
	var st_before_toast: int = game.current_state()
	check(game.has_method("toast") and game.has_method("attach_toast"), "K-C：Game.toast/attach_toast 契约方法存在")
	if game.has_method("toast"):
		game.toast("冒烟", "warn")  # 未 attach → push_warning 静默降级
	check_eq(game.current_state(), st_before_toast, "K-C：toast 降级调用不改变状态机状态")

	finish()

func _on_state_changed(from_state: int, to_state: int) -> void:
	_signals.append([from_state, to_state])
