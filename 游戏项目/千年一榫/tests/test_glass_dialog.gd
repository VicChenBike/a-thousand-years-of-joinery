extends "res://tests/test_base.gd"
## K-C（KC-1）判定用例：GlassDialog 通用毛玻璃确认弹窗契约无头测试（TDD 先写）。
## 契约来源：spec §6.2 / plan KC-1 接口定稿（跨批契约，K-D 商店 / K-G 关卡复用）：
##   class_name GlassDialog extends Control；signal confirmed / signal canceled；
##   setup(title, body, ok_text="确认", cancel_text="取消", show_cancel=true) 纯配置不显示；
##   open_centered() 显示；close() 隐藏复位（不 queue_free，可复用）；set_body(body) 二次弹复用。
## 语义：仅确认钮发 confirmed；遮罩/Esc/取消钮发 canceled；全屏遮罩 STOP 锁下层输入。
## 卡片样式 L3（spec §3.3 弹窗档）：圆角 14 / 顶缘 border 2px / shadow_size 16。
## P2-5 纪律：--script 模式 class_name 注册有时序问题 → 组件断言一律 load() 比较 script，
## 不直接引用全局类名（plan §0.1）。

const GD_SCENE := "res://scenes/shared/glass_dialog.tscn"
const GD_SCRIPT := "res://scenes/shared/glass_dialog.gd"

func _counters() -> Dictionary:
	return {"ok": 0, "cancel": 0}

func _initialize() -> void:
	print("== test_glass_dialog ==")
	var scene: PackedScene = load(GD_SCENE)
	check(scene != null, "KC-1：glass_dialog.tscn 可加载")
	if scene == null:
		finish()
		return
	var dlg: Control = scene.instantiate()
	add_child(dlg)
	await process_frame  # _ready 延迟至下一帧（实测经验）：初始隐藏 + 信号接线

	# ---- 1. 契约结构：script / 信号 / 四方法 ----
	check(dlg.get_script() == load(GD_SCRIPT), "KC-1：根节点挂 glass_dialog.gd（script 比较，P2-5）")
	check(dlg.has_signal("confirmed") and dlg.has_signal("canceled"), "KC-1：confirmed/canceled 两信号齐备")
	var has_api: bool = true
	for m: String in ["setup", "open_centered", "close", "set_body"]:
		has_api = has_api and dlg.has_method(m)
	check(has_api, "KC-1：契约四方法 setup/open_centered/close/set_body 齐备")
	check_eq(dlg.visible, false, "KC-1：入树后初始不可见")

	# ---- 2. setup 纯配置不显示；open_centered 显示 ----
	dlg.call("setup", "新游戏", "新游戏将清除当前存档，确定重新开始吗？")
	check_eq(dlg.visible, false, "KC-1：setup 只配置不显示")
	check_eq(String(dlg.get_node("Card/VBox/Title").text), "新游戏", "KC-1：setup 标题生效")
	check_eq(String(dlg.get_node("Card/VBox/Body").text), "新游戏将清除当前存档，确定重新开始吗？", "KC-1：setup 正文生效")
	dlg.call("open_centered")
	check_eq(dlg.visible, true, "KC-1：open_centered 后可见")

	# ---- 3. 仅确认钮发 confirmed，且自动 close ----
	var c := _counters()
	dlg.connect("confirmed", func() -> void: c["ok"] += 1)
	dlg.connect("canceled", func() -> void: c["cancel"] += 1)
	(dlg.get_node("Card/VBox/ButtonRow/OkButton") as Button).pressed.emit()
	check_eq(int(c["ok"]), 1, "KC-1：OkButton.pressed → confirmed 恰 1 次")
	check_eq(dlg.visible, false, "KC-1：确认后自动 close")

	# ---- 4. set_body 复用二次弹（商店「已拥有该皮肤」场景，K-D 依赖） ----
	dlg.call("set_body", "已拥有该皮肤")
	check_eq(String(dlg.get_node("Card/VBox/Body").text), "已拥有该皮肤", "KC-1：set_body 复用改写正文生效")
	dlg.call("open_centered")
	check_eq(dlg.visible, true, "KC-1：close 后可再 open_centered（不 queue_free 可复用）")

	# ---- 5. 遮罩点击 = canceled（伪左键按下直调回调） ----
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	dlg.call("_on_dim_gui_input", ev)
	check_eq(int(c["cancel"]), 1, "KC-1：遮罩左键按下 → canceled")
	check_eq(dlg.visible, false, "KC-1：遮罩点击后自动关闭")

	# ---- 6. show_cancel=false 无取消钮；取消钮发 canceled ----
	dlg.call("setup", "退出", "退出《千年一榫》？", "退出", "取消", false)
	check_eq((dlg.get_node("Card/VBox/ButtonRow/CancelButton") as Control).visible, false, "KC-1：show_cancel=false 时 CancelButton 隐藏")
	(dlg.get_node("Card/VBox/ButtonRow/CancelButton") as Button).pressed.emit()
	check_eq(int(c["cancel"]), 2, "KC-1：CancelButton.pressed → canceled 再 +1")
	check_eq(int(c["ok"]), 1, "KC-1：取消路径不发 confirmed")

	# ---- 7. Esc（ui_cancel）= canceled ----
	dlg.call("open_centered")
	var eva := InputEventAction.new()
	eva.action = "ui_cancel"
	eva.pressed = true
	dlg.call("_unhandled_input", eva)
	check_eq(int(c["cancel"]), 3, "KC-1：Esc(ui_cancel) → canceled")
	check_eq(dlg.visible, false, "KC-1：Esc 后自动关闭")

	# ---- 8. L3 卡片样式（spec §3.3 弹窗档） ----
	var sb: StyleBoxFlat = (dlg.get_node("Card") as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	check(sb != null and sb.corner_radius_top_left == 14, "KC-1：L3 卡片圆角 14")
	check(sb != null and sb.border_width_top == 2, "KC-1：L3 顶缘高光边 2px")
	check(sb != null and sb.shadow_size == 16, "KC-1：L3 弹窗投影 shadow_size 16")

	finish()
