extends Control
## 终局「未完待续」界面控制器（批次 AD 步骤四，spec §4.4.2，D7）。
## 职责最小化（布局/字体/遮罩/描边全在 .tscn 静态化，与 talk/catalog 场景同款口径）：
##   ①金色标题字色运行时单源覆写——Palette.MAIN_GOLD（工程纪律：色值禁散落 tscn 字面量，
##     P3-1 色彩单源；描边/阴影/字号/字体系几何观感参数留 tscn override，同 main_menu
##     Title 手法——其 font_color 虽在 tscn，系批次 L 前旧件；新建件一律 Palette 单源）；
##   ②右下【返回主菜单】钮：手型光标（工程可点项统一口径，catalog_scene.gd:160 同款）
##     + pressed → Game.goto_state(MAIN_MENU)（spec §4.4.2：平滑返回主菜单；
##     goto_state(MAIN_MENU) 触发 game.gd 清栈规则②——通关终局后历史无意义）；
##   ③悬停光晕体系零自持——ui_material 手电筒光斑由 UILightLinker node_added 自动挂载
##     （Button 恒为 _is_ui_target）；外圈 hover_glow 由 window_manager._is_glow_target
##     Button 族分支自动纳入；BackButton 另显式挂 metadata/hover_glow（tscn 静态 meta，
##     eye_duration_panel「显式兜底」同款双保险）——键鼠悬停与手势光标 synth_motion
##     巡航注入（gesture_router §4.3.5，不区分状态区）两路 Hover 全部天然点亮；
##   ④顶栏设置/手势交互由 main.tscn GlobalUI 常驻提供（Game.attach 的 SceneContainer
##     在 GlobalUI 之下），本场景不重复挂任何控制台件；无立绘、无对话框（spec §4.4.2）。

const Palette := preload("res://scripts/palette.gd")  # 工程纪律：--script 模式 class_name 时序不稳，消费方一律 preload

@onready var title_label: Label = $Title
@onready var back_button: Button = $BackButton

func _ready() -> void:
	# I18n：tscn 静态文字经 t() 覆写（「未完待续」术语表=To be continued；「返回主菜单」=Main Menu）。
	title_label.text = I18n.t("未完待续")
	back_button.text = I18n.t("返回主菜单")
	title_label.add_theme_color_override("font_color", Palette.MAIN_GOLD)
	back_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back_button.pressed.connect(_on_back_pressed)

## 「返回主菜单」路由（spec §4.4.2）：直连全局状态机，MAIN_MENU 导航根清栈语义自动生效。
func _on_back_pressed() -> void:
	Game.goto_state(Game.State.MAIN_MENU)
