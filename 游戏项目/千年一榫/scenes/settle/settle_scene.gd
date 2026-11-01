extends Control

# 批次 W（P3-1）：色彩单源表（值不变）。
const Palette := preload("res://scripts/palette.gd")
## 结算场景（批次 F 完整接线；J4-2 视觉修订）。
## ⚠ P批波2 退役标注（2026-09-10，用户口径 P-D 结算架构重做）：本场景**不再被路由**——
## 结算 UI 已合并进 level_scene 覆盖层（SuccessOverlay/SettleUI，主路径零重建零回正零切换；
## goto_state(SETTLE) 经 game.gd 特判改载 level 场景注入 settle:true 走边缘路径）。
## 本文件与 settle_scene.tscn 保留不删（避免 asset 断链/旧测试留档），NextButton 三分流
## 语义已迁入 level_scene.settle_next_route/_on_settle_next_pressed。
## 依据 spec 4.8/5.1：
## 中央 CenterMount 复用 PointCloudViewer 组件挂载文物点云
## （F2：左键拖拽旋转含俯仰 + 滚轮缩放；金黄 tint #F5C542 强度 0.85；展示区扩大显大）；
## 背景压暗（F1：Dim 黑 0.62）；下方信息 = 评分（完美/良好/及格）+ 耗时 mm:ss + 获得天赋值；
## 右下「下一关」：重玩结算 → CATALOG；无下一关数据 → MAIN_MENU；有 → TALK（关后剧情）。
## set_context({chapter, grade, score, elapsed, talent, replay}) 注入结算数据；
## grade=中文评级（批次 F 由 level_scene 计算传入）；缺省字段显示「——」占位。
## 评级/天赋/下一关等运行逻辑零改动（批次 J 仅视觉/组件复用）。

const DEFAULT_BG := "res://assets/backgrounds/bg_chapter1.png"
const GOLD_TINT := Palette.MAIN_GOLD   # 批次 J §0.5 点云金黄 #F5C542（P3-1 主金单源，值不变）
const SETTLE_CAMERA_DISTANCE := 2.8            # 比 viewer 默认 3.2 略近，点云更有实物感（J4-2）

@onready var background: TextureRect = $Background
@onready var center_mount: Control = $CenterMount  # 文物点云挂载（PointCloudViewer 组件子树）
@onready var score_label: Label = $ScoreLabel
@onready var elapsed_label: Label = $ElapsedLabel
@onready var talent_label: Label = $TalentLabel
@onready var next_btn: Button = $NextButton

var _ctx: Dictionary = {}
var _viewer: Control = null  # J4-2：复用的点云查看器组件实例

func set_context(ctx: Dictionary) -> void:
	_ctx = ctx.duplicate(true)

func _ready() -> void:
	_apply_background()
	_apply_labels()
	# I18n：tscn 静态文字（下一关）经 t() 覆写。
	next_btn.text = I18n.t("下一关")
	next_btn.pressed.connect(_on_next_pressed)
	_build_cloud()
	# 批次 R（spec §5.1/§5.7/§10.2）：结算点云区注册手势面板（一处；边缘路径场景，主路径
	# 结算 UI 由 level 覆盖层承载——注册随文件保留，P批波2 退役注记不变）
	add_to_group("gesture_panel")

## 批次 R（spec §5.1）：手势面板最小契约——中央点云查看区全局矩形
func gesture_panel_rect() -> Rect2:
	return center_mount.get_global_rect()

## 批次 R（spec §5.7）：点云面板可选契约——返回结算 PointCloudViewer
func get_gesture_viewer() -> Control:
	return _viewer

func _apply_labels() -> void:
	# 评分：优先 grade（中文评级，批次 F 数据流——评级名键「完美/良好/及格」亦经 t()），缺省回退 score
	# I18n：全部标签模板/占位经 t()（zh 直通原样；en 命中词条；退役件重进生效口径）。
	var grade: String = String(_ctx.get("grade", ""))
	var score_txt: String = (I18n.t(grade) if not grade.is_empty() else str(_ctx.get("score", "——")))
	score_label.text = I18n.t("评分：%s") % score_txt
	if _ctx.has("elapsed"):
		var secs: float = float(_ctx["elapsed"])
		elapsed_label.text = I18n.t("耗时：%02d:%02d") % [int(secs / 60.0), maxi(int(secs), 0) % 60]
	else:
		elapsed_label.text = I18n.t("耗时：——")
	if _ctx.has("talent"):
		talent_label.text = I18n.t("获得天赋值：%d") % int(_ctx["talent"])
	else:
		talent_label.text = I18n.t("获得天赋值：——")

func _apply_background() -> void:
	# 章节背景（LevelLibrary 映射），缺失回退第 1 关背景，再缺失隐藏露主题底色
	var chapter: int = int(_ctx.get("chapter", 1))
	var path: String = LevelLibrary.get_background_path(chapter)
	if not ResourceLoader.exists(path):
		path = DEFAULT_BG
	if ResourceLoader.exists(path):
		background.texture = load(path)
	else:
		background.visible = false

## 中央文物点云（spec 4.8「中央即该关文物点云，可旋转」）——J4-2（F2）改为复用
## PointCloudViewer 组件：自带拖拽旋转（Y+俯仰）/滚轮缩放/降级占位，删除原内联
## MultiMesh 构建与根 _gui_input 绕 Y 拖拽（消除双实现分叉；材质 UNSHADED 口径随组件保留）。
## 金黄 tint（§0.5 #F5C542，强度 0.85）经 J4-2 落在组件上的 @export 接口逐实例设置，
## 不影响图鉴侧默认（图鉴 J5-2 复用同接口调参）。
func _build_cloud() -> void:
	_viewer = load("res://scripts/point_cloud_viewer.gd").new()
	_viewer.name = "PointCloudViewer"
	_viewer.set("tint_color", GOLD_TINT)
	_viewer.set("tint_strength", 0.85)
	_viewer.set("camera_distance", SETTLE_CAMERA_DISTANCE)
	# J6-P1-3/J6r3-2：viewer 缺省 0.02 走查实证实心金条（截图 09）→ 0.008；复走查 4x
	# 放大判 0.008 主体仍融合 → 再降档 0.005（可显单点）。TODO 后续复走查微调。
	_viewer.set("point_size", 0.005)
	center_mount.add_child(_viewer)
	var chapter: int = int(_ctx.get("chapter", 1))
	var points_path: String = LevelLibrary.get_points_path(chapter)
	_viewer.call("build", load(points_path) if ResourceLoader.exists(points_path) else null)

func _on_next_pressed() -> void:
	# 分流（spec 5.1）：重玩结算 → CATALOG；无下一关数据 → MAIN_MENU（第 5 关后终点待确认 #6）；
	# 有 → TALK 关后剧情（talk_controller mode=after_level，对话完 → LEVEL 下一关）。
	var chapter: int = int(_ctx.get("chapter", 1))
	if bool(_ctx.get("replay", false)):
		Game.goto_state(Game.State.CATALOG)
		return
	if LevelLibrary.get_level(chapter + 1).is_empty():
		Game.goto_state(Game.State.MAIN_MENU)
		return
	Game.goto_state(Game.State.TALK, {"mode": "after_level", "chapter": chapter})
