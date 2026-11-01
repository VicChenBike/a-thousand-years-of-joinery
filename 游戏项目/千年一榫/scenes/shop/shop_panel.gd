extends Control
## 「衣橱」（原「商店」，批次 AC §4.9 用户拍板改名）覆盖层。K-D 重构（spec §7.5）：删占位文案、
## 右栏改「神通谱」标题、原创 5 张置顶（默认拥有/
## 随剧情解锁状态标签/禁购）、详情介绍读 skin.desc、失败改 toast（经 Game.toast）。
## 批次V（V-C5，spec §3.2）：购买/领取确认弹窗节点退役——确认改经 Game.confirm → TopStrip
## 统一确认条（文案与确认/取消语义逐字保持；旧弹窗组件文件本体保留不删，settle_scene 先例）。
## M-S（批次 M spec §3.6B，用户追加 追4）：详情栏重排 DetailInner（题头固定/描述独立滚动/价格+购买钮
## 固定底行——购买钮常驻右下不随长文本下挤）；详情 VBox 顶对齐 + 立绘固定高（图文空隙 ≤24）；
## 左网格卡片 EXPAND_FILL 吃满列宽 + 网格滚动条压窄 6px（末列右缘距面板内边距 ≤8）。
## O7（批次 O，2026-09-10）：DetailScroll 与 DetailBottom 之间新增固定效果行 EffectRow
## （HBox：前缀「效果」+内容 Label；不随 DetailDesc 滚动；文案读 SkinCatalog EFFECT 表，
## 行内可视=「效果：」+内容；字色用主题正文色深浅自协调）。
## O6（批次 O）：未解锁原创卡片按钮可点击看详情（文本保持「随剧情解锁」）；详情购买钮对
## 未解锁原创置 disabled+同文案（防可点被 _on_select 静默吞）；47 张普通皮肤行为不变。
## 批次 Z Z3（spec §3-7，用户拍板 2026-09-24）：**剧情对话期间（Game.State.TALK）购买与
## 装配都拦**——判据 Game.current_state()==Game.State.TALK，落点 _on_select（装配/发起购买）
## 与 _on_confirmed（完成购买）；提示走 Game.info → TopStrip info，文案=本常量（文件头部
## 单点，逐字锁 tests/test_z_shop_talk_guard.gd）。非 TALK 态（含键鼠路径）行为零变化。

const TALK_GUARD_TEXT := "剧情对话期间无法改变装配"

@onready var balance_label: Label = $TopBar/BalanceLabel
@onready var skin_grid: GridContainer = $Content/GridPanel/Scroll/SkinGrid
@onready var exit_btn: Button = $TopBar/ExitButton
# M-S：详情三段式——DetailInner = [DetailTitle（固定题头）+ DetailScroll>DetailVBox（随文本滚动）
# + DetailBottom（固定底行：价格左/购买钮右下常驻）]。K-H 的「整列套 Scroll」语义由 DetailScroll 承接。
@onready var detail_name: Label = $Content/DetailBox/DetailInner/DetailScroll/DetailVBox/DetailName
@onready var detail_image: TextureRect = $Content/DetailBox/DetailInner/DetailScroll/DetailVBox/DetailImage
@onready var detail_desc: Label = $Content/DetailBox/DetailInner/DetailScroll/DetailVBox/DetailDesc
# O7：固定效果行（滚动区外，介于 DetailScroll 与 DetailBottom 之间）
@onready var effect_value: Label = $Content/DetailBox/DetailInner/EffectRow/EffectValue
@onready var detail_price: Label = $Content/DetailBox/DetailInner/DetailBottom/DetailPrice
@onready var buy_btn: Button = $Content/DetailBox/DetailInner/DetailBottom/BuyButton

var _selected: Dictionary = {}
var _preview: Dictionary = {}  # 右侧详情栏当前展示的皮肤
var _cards: Dictionary = {}  # id -> VBox
# 批次 Z（Z6-P1-5，spec §6）：本店推过的 confirm 句柄序号（Game.confirm 返回值记位）——
# _exit_tree 释放兜底消费：购买确认挂起时关店 → 旧无收口 → TopStrip 僵尸确认条（点确认/
# 取消均无效、_ok_cb 指向已释放实例，且 _mode=="confirm" 占单槽吞掉之后所有 Game.info）。
var _my_confirm_seq := -1

func _ready() -> void:
	exit_btn.pressed.connect(func() -> void: Game.close_overlay())
	buy_btn.pressed.connect(_on_buy)
	SaveManager.talent_changed.connect(func(_n: int) -> void: _refresh_balance())
	SaveManager.skin_changed.connect(func(_id: String) -> void: _build_grid())
	# M-S：左网格滚动条压窄 6px——卡片吃满列宽后末列右缘距面板内边距 = 滚动条宽（≤8 口径）
	# （4.7 实证：访问器为 get_v_scroll_bar() 大写 B；小写 get_v_scrollbar 与属性 v_scroll_bar 均不存在）
	var grid_scroll := skin_grid.get_parent() as ScrollContainer
	if grid_scroll != null and grid_scroll.get_v_scroll_bar() != null:
		grid_scroll.get_v_scroll_bar().custom_minimum_size = Vector2(6, 0)
	# I18n：tscn 静态文字经 t() 覆写（详情题头「神通谱」/效果前缀「效果：」/退出钮；
	# 余额/卡片/详情为运行时动态覆写——消费点见 _refresh_balance/_build_grid/_show_detail）。
	exit_btn.text = I18n.t("退出")
	($Content/DetailBox/DetailInner/DetailTitle as Label).text = I18n.t("神通谱")
	($Content/DetailBox/DetailInner/EffectRow/EffectPrefix as Label).text = I18n.t("效果：")
	exit_btn.text = I18n.t("退出")
	_refresh_balance()
	_build_grid()

## 批次 Z（Z6-P1-5，spec §6）：释放兜底——覆盖关闭钮 close_overlay/跨态收起之外，实例
## queue_free 释放时若「自家购买确认仍挂起」则按取消收起（句柄比对，同 settings_panel
## _exit_tree 口径；他源确认不受扰）。无确认在场时序号 -1 → 恒 no-op 零回归。
func _exit_tree() -> void:
	if _my_confirm_seq >= 0 and int(Game.call("get_active_confirm_seq")) == _my_confirm_seq:
		Game.dismiss_confirm()

func _refresh_balance() -> void:
	balance_label.text = I18n.t("天赋值：%d") % SaveManager.get_talent()

func _build_grid() -> void:
	for child: Node in skin_grid.get_children():
		# 修复批 P3（2026-09-26）：先 remove_child 再 queue_free——queue_free 节点帧末才摘除，
		# 旧序（queue_free 后同帧 add_child 新卡）帧内容器子件数=2N（47→94 一帧闪跳/布局抖动）。
		skin_grid.remove_child(child)
		child.queue_free()
	_cards.clear()
	var skins_state: Dictionary = SaveManager.get_skins()
	var owned: Array = skins_state["owned"]
	var equipped: String = skins_state["equipped"]
	for skin: Dictionary in SkinCatalog.get_skins():
		var card: VBoxContainer = VBoxContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # M-S：卡片 expand 吃满列宽（m09 左红圈整列空白）
		var tex: TextureRect = TextureRect.new()
		tex.custom_minimum_size = Vector2(0, 180)  # M-S：高固定、宽随卡片自适应（原 180 固定宽致右侧空列）
		tex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if ResourceLoader.exists(String(skin["texture"])):
			tex.texture = load(skin["texture"])
		var info: Label = Label.new()
		var is_locked_origin: bool = bool(skin.get("original", false)) and not owned.has(skin["id"])
		if is_locked_origin:
			# K3-5：未解锁原创=禁购，信息区不显示「免费/价格」，与「随剧情解锁」按钮语义一致
			info.text = "%s
%s" % [I18n.t(String(skin["name"])), I18n.t("随剧情解锁")]
		else:
			var price_text: String = I18n.t("免费") if int(skin["price"]) == 0 else I18n.t("%d 天赋值") % int(skin["price"])
			var state_text: String = I18n.t("穿戴中") if skin["id"] == equipped else (I18n.t("已拥有") if owned.has(skin["id"]) else price_text)
			info.text = "%s
%s" % [I18n.t(String(skin["name"])), state_text]
		# K3-5：原创卡片状态机——未解锁原创→「随剧情解锁」禁购不显示价格；穿戴中→禁用；其余→选择。
		var btn: Button = Button.new()
		if bool(skin.get("original", false)) and not owned.has(skin["id"]):
			btn.text = I18n.t("随剧情解锁")
			# O6（2026-09-10 用户反馈：随剧情解锁的角色也应能点开看文案）：不再 disabled，
			# 点击走 _show_detail 展示详情；禁购语义由详情购买钮 disabled 态承接（见 _show_detail）。
		elif skin["id"] == equipped:
			btn.text = I18n.t("穿戴中")
			btn.disabled = true
		else:
			btn.text = I18n.t("选择")
		btn.pressed.connect(func() -> void: _show_detail(skin))
		card.add_child(tex)
		card.add_child(info)
		card.add_child(btn)
		skin_grid.add_child(card)
		_cards[skin["id"]] = card
	# 右侧详情栏：默认展示首个皮肤；已有时（重建后）刷新当前预览
	if _preview.is_empty():
		_show_detail(SkinCatalog.get_skins()[0])
	else:
		_show_detail(SkinCatalog.get_skin(String(_preview["id"])))

func _show_detail(skin: Dictionary) -> void:
	## 点选左侧格子 → 右侧详情栏展示该皮肤（预览图/神通谱介绍/效果/价格）。desc 读 SkinCatalog（未写文案显示「——」）。
	_preview = skin
	detail_name.text = I18n.t(String(skin["name"]))
	if ResourceLoader.exists(String(skin["texture"])):
		detail_image.texture = load(String(skin["texture"]))
	else:
		detail_image.texture = null
	# I18n：desc/effect 显示点 t()（缺省占位「——」亦入词条表=原样）。
	detail_desc.text = I18n.t(String(skin.get("desc", "——")))
	effect_value.text = I18n.t(String(skin.get("effect", "——")))  # O7：效果固定行填充
	# O6：未解锁原创（未拥有+original）详情购买钮置禁用+「随剧情解锁」——卡片按钮已可点开
	# 详情，购买入口不能再被 _on_select 的 buyable 守卫静默吞（用户口径：随剧情解锁）。
	# 批次 W（P2-10，规格 §4）：其余分支按拥有态分文案——已拥有=「穿戴」（点击实际直接穿戴
	# 不扣费 _on_buy→_on_select owned→equip_skin，旧「购买」文案误导）；未拥有=「购买」不变。
	# 点击行为零改动（locked_origin/未拥有/已拥有三路点击语义原样，test_shop_panel 段 5/6 回归）。
	var locked_origin: bool = bool(skin.get("original", false)) \
		and not (SaveManager.get_skins()["owned"] as Array).has(String(skin["id"]))
	if locked_origin:
		buy_btn.disabled = true
		buy_btn.text = I18n.t("随剧情解锁")
	else:
		var owned_now: bool = (SaveManager.get_skins()["owned"] as Array).has(String(skin["id"]))
		buy_btn.disabled = false
		buy_btn.text = I18n.t("穿戴") if owned_now else I18n.t("购买")
	var price_text: String = I18n.t("免费") if int(skin["price"]) == 0 else I18n.t("%d 天赋值") % int(skin["price"])
	detail_price.text = I18n.t("价格：") + price_text

func _on_buy() -> void:
	## 详情栏「购买」：对当前预览的皮肤走既有确认弹窗/扣费/穿戴流程。
	if _preview.is_empty():
		return
	_on_select(_preview)

## 批次 Z Z3：剧情对话期间拦截谓词——TALK 态提示并返回 true（拦）；非 TALK 恒 false（零影响）。
func _in_talk_state() -> bool:
	if int(Game.current_state()) == int(Game.State.TALK):
		Game.info(I18n.t(TALK_GUARD_TEXT))
		return true
	return false

func _on_select(skin: Dictionary) -> void:
	# 批次 Z Z3（用户拍板）：TALK 态装配与发起购买一并拦截（提示=单点常量，经 TopStrip info）。
	if _in_talk_state():
		return
	_selected = skin
	var owned: Array = SaveManager.get_skins()["owned"]
	if owned.has(skin["id"]):
		# 已拥有→直接穿戴（含通关解锁后的原创：已 owned 即可点选穿戴，不吞）
		SaveManager.equip_skin(skin["id"])  # K-D：equip_skin 重定向 set_preferred（preferred 同步）
		return
	if bool(skin.get("buyable", true)) == false:
		return  # 未解锁原创禁购双保险（K3-5）——仅拦「未拥有 + 不可购买」的原创
	# 批次V（V-C5，spec §3.2）：领取/购买确认统一确认条 Game.confirm 承载（文案逐字保持；
	# 确认=原扣费/领取链 _on_confirmed，取消/×缺省空回调=零副作用）。
	if int(skin["price"]) == 0:
		_my_confirm_seq = Game.confirm(I18n.t("免费领取 %s？") % I18n.t(String(skin["name"])), _on_confirmed)
	else:
		_my_confirm_seq = Game.confirm(I18n.t("确认购买 %s（%d 天赋值）？") % [I18n.t(String(skin["name"])), int(skin["price"])], _on_confirmed)

func _on_confirmed() -> void:
	# 批次 Z Z3（用户拍板）：完成购买同样过闸——挂起确认回调若落进 TALK 态（理论时序兜底）
	# 不扣费、不入 owned、不穿戴，仅提示；_selected 一并作废防陈旧挂起。
	if _in_talk_state():
		_selected = {}
		return
	if _selected.is_empty():
		return
	var id: String = _selected["id"]
	if int(_selected["price"]) == 0:
		# 免费皮肤：0 扣费直接领取。buy_skin 固定扣 205，不适用于 0 价皮肤。
		var owned: Array = SaveManager.get_skins()["owned"]
		if owned.has(id):
			Game.toast(I18n.t("已拥有该皮肤"), "info")  # K4-2：已拥有改 toast（原 ConfirmationDialog 二次弹）
			_selected = {}
			return
		owned.append(id)
		SaveManager.save_game()
		SaveManager.equip_skin(id)
		_selected = {}
		return
	if not SaveManager.buy_skin(id):
		var still_owned: bool = (SaveManager.get_skins()["owned"] as Array).has(id)
		if still_owned:
			Game.toast(I18n.t("已拥有该皮肤"), "info")
		else:
			Game.toast(I18n.t("天赋值不足，无法购买"), "warn", 2.5, true)  # K4-2+批次Q2：置顶居中（同 FailToast 四参，走 toast_center 中央锚点盒）
		_selected = {}
		return
	SaveManager.equip_skin(id)
	_selected = {}
