class_name FocusFX
extends CanvasLayer
## N3（spec §6.4 + §五方案口径 4~7）：聚焦动画全屏三色重做——单节点全屏散点控制器。
## 取代 M-Gb 各视图 SubViewport 内 CPU MultiMesh 金点方案（单视图扩散/边缘渐隐/正交钳制
## 随重写废止，相关断言「N批等价替换」留痕）。
##
## 架构（spec §五 4/5 定夺）：
## ① 全屏层=本节点（CanvasLayer，layer=85，低于 SuccessOverlay 90 与 GlobalUI 100）+
##   代码创建的全屏 SubViewport（透底）+ 透视相机（避免依赖 tscn）；容器 SubViewportContainer
##   mouse_filter=IGNORE（纯视觉层，不拦截顶栏聚焦钮/退出钮/设置钮任何点击）。
## ② 三色通道：单一控制器承载三通道 MultiMesh（单绘制），三视图各作为一条颜色通道接入
##   （主=金黄/对照=绿/固定件=红，允许屏上重叠）；三视图体素位置经各视图相机 unproject
##   换算入全屏层（_voxel_screen_pos 单处实现）；散点目标屏幕位按「距四角距离」加权
##   （spread_target_screen，离角越近越密）。
## ③ 相位状态机：IDLE→CONDENSE（凝聚约 0.25s：体素先实体→密集点云面成形，凝聚完成才
##   hide 体素=无空窗跳变，修「聚焦瞬间瞬时 hide 卡顿」）→HOLD（O批用户口径③：凝聚点云面
##   稳态持续 0.5s，FOCUS_HOLD_TIME；N批「聚焦默认直入散开」废止留痕）→SPREAD（散开 1.2s，
##   P批波 2 放慢+滞空缓动，O批目标位=屏外环域——散点逃出屏幕不遮屏）→STEADY（稳态：闪烁+
##   漂移）；deactivate=完整
##   倒放 RETURN（散点从当前位收拢→点云面→实体还原，完成后点云清空=无残留点阵）；重复
##   activate 幂等防重入；RETURN 期 activate=打断快进收尾后重新激活（M-Gb 语义等价保留）；
##   deactivate_immediate（成功动画入口 _begin_success 专用）跳过倒放立即复位（体素还原/点云
##   清空），调用链零改动。
##   N批：N4复用扩展——CONDENSE 与 SPREAD 之间可选 HOLD 持续段（PHASE_HOLD，成功动画经
##   n4_hold_time>0 覆写；O批起聚焦路径亦经 FOCUS_HOLD_TIME 默认进入，两处 0.5s 口径一致）。
## ④ 性能红线（spec §五 6）：点 transform/颜色/custom 全部激活时一次性静态预生成
##   （MultiMesh 单缓冲），动画 GPU uniform 驱动（ShaderMaterial u_spread/u_alpha，
##   闪烁/漂移走 shader TIME——稳态 CPU 每帧零成本）；禁止逐帧全量 CPU 重建点阵。
## ⚠ 坑纪律：use_colors/use_custom_data 须在 instance_count 之前（4.7 实证，坑 13）；
##   无头 MultiMesh 色/transform/custom 读回恒 0——断言只用 instance_count/材质标志/
##   自持数组（_channels/_mm_colors）等属性证据链，观感=窗口截图判定（spec §6.5）。
## ⑤ N4 预留（spec §6.6，本批只留接口不实现）：散开目标位生成 spread_target_screen /
##   凝聚相位常量 / 通道配置 CHANNEL_COLORS / 散开进度 get_spread_progress /
##   逐点当前屏幕位 get_channel_screen_positions / 逐点颜色 _mm_colors 均为独立可复用入口；
##   成功动画四段式（凝聚→散开→聚合→回看）复用本管线时不改本文件状态机本体。
## 环境说明：--script 模式 class_name 注册时序不稳——接线方一律 load() + call()（P2-5）。

signal activated
signal deactivated

# ---- N3 相位状态机（get_phase() 测试钩子消费；M-Gb 三相位按新状态机重定义，等价替换留痕）----
const PHASE_IDLE := 0
const PHASE_CONDENSE := 1   # 凝聚：体素位密集点云面成形（体素仍在屏，0.25s）
const PHASE_SPREAD := 2     # 散开：全屏铺满（0.9s）
const PHASE_STEADY := 3     # 稳态：闪烁+漂移（GPU TIME 驱动，CPU 零逐帧成本）
const PHASE_RETURN := 4     # 收回=完整倒放：散点收拢→点云面→实体还原（0.6s）
# N批：N4复用扩展——PHASE_HOLD=持续段（凝聚完成后、散开前的短暂保持；n4_hold_time≤0 时不
# 进入本相位，N3 行为完全不变）。deactivate/RETURN 语义兼容：HOLD 期散开进度=0，倒放直入还原段。
const PHASE_HOLD := 5
const CONDENSE_TIME := 0.25
# P-C（批次 P 波 2，2026-09-10 用户口径「发散放慢+滞空」）：SPREAD_TIME 0.9→1.2——聚焦散开
# 与成功动画（ANIM_SPREAD 同值经 n4_spread_time 覆写）同口径放慢，「刷一下过去」观感根除。
const SPREAD_TIME := 1.2
const RETURN_GATHER_TIME := 0.4
const RETURN_RESTORE_TIME := 0.2
const RETURN_TIME := 0.6  # =收拢0.4+还原0.2（M-Gb 0.4 等价替换留痕；字面量避免浮点和 0.6000...1）

# ---- P-C 滞空感缓动参数（走查调档单点；shader 内同值字面量同步，见 SHADER_CODE 注）----
## 缓动曲线（CPU 纯函数 spread_ease/spread_hover 与 GPU shader 同式）：行进=幂 2.6 ease-out
## （前段缓出更快进入慢速段），再叠加阻尼正弦悬浮 sin(πx)·(1−x)·SPREAD_HOVER_AMP（起止为零、
## 中段峰、后段衰减——「缓缓飘出」非「直落出屏」）。接力采样不受影响：get_channel_screen_
## positions 仅在散开末帧（进度=1）被 level 读取，缓动只改观感不改终点。
const SPREAD_EASE_POW := 2.6   # 缓出幂（原 2.0；越大前段越快、尾段越绵）
const SPREAD_HOVER_AMP := 14.0 # 悬浮幅度 px（阻尼正弦峰值≈0.5×AMP）

# ---- N批：N4复用扩展——成功动画四段式相位时长覆盖入口（spec §6.6 方案口径 1）----
## 成功流程按自身四段时长驱动（凝聚 0.3/持续 0.15/散开 0.55s），激活前由 level_scene 写入
## 本组覆盖值（≤0/缺省走 N3 常量，聚焦路径零影响）；数值随 anim_time_scale 折算（覆盖值
## 由调用方折算，本层只按秒推进）。
var n4_condense_time := -1.0   # ≤0=CONDENSE_TIME
var n4_hold_time := 0.0        # ≤0=无持续段（凝聚完成直入散开，N3 行为）
var n4_spread_time := -1.0     # ≤0=SPREAD_TIME

# 批次 W（P3-1）：色彩单源表（值不变）。
const Palette := preload("res://scripts/palette.gd")

# ---- 三色通道配置# ---- 三色通道配置（N4 可复用入口①：通道=颜色+视口绑定，id 固定 Main/Target/Join）----
const COLOR_MAIN := Palette.MAIN_GOLD          # 中央木料=金黄（P3-1 主金单源，值不变）
const COLOR_TARGET := Palette.PICK_GREEN        # 左上最终成品（final，批次 Z Z1 改名；target 只做判定）=绿（P3-1 单源，值不变）
const COLOR_JOIN := Palette.FOCUS_JOIN_RED      # 右上对接固定件=红（P3-1 单源，值不变）
const GOLD := COLOR_MAIN                        # 旧常量等价保留（K6-7 契约面）
const CHANNEL_COLORS := {"Main": COLOR_MAIN, "Target": COLOR_TARGET, "Join": COLOR_JOIN}
const DOTS_PER_VOXEL := 7    # O批等价替换（2026-09-10 用户反馈②散布太密集）：22→6~8 档定 7——
                             # 配合散开目标改屏外（屏内不再遮屏）与圆点化细腻口径；M-Gb 6/N3 22 均废止留痕

# ---- O批（2026-09-10 用户口径①）：圆点化细腻档（原 7px 方块点废止，走查定档）----
const FOCUS_HOLD_TIME := 0.5  # O批（用户口径③）：聚焦凝聚点云面稳态持续 0.5s——n4_hold_time≤0 时
                              # 生效（成功路径经 ANIM_HOLD 覆写同值=两处口径一致）；N批「默认 0 直入散开」废止留痕

# ---- 全屏层几何/观感常量（暂定值，走查微调）----
# LAYER 走查定稿留痕：spec 暂定 85（彼时误读 GlobalUI=100，实为 GlowLayer=100、GlobalUI 默认
# 层 1）——85 实测视觉压设置覆盖层/窗钮（N3_B1 截图实证）。定稿 0=与关卡内容同层且本节点
# 为 _ready 内最后挂载（树序在全部关卡 UI 之后）→ 散点盖关卡 UI；GlobalUI(1)/SuccessOverlay(90)/
# GlowLayer(100) 均高于 0 → 不压全局 UI（spec §九 1 红线本意）。测试断言同步 LAYER=0。
const LAYER := 0
const DESIGN_SIZE := Vector2(1152, 648)  # 换算基准设计视口（实际窗口缩放由 stretch 承担）
const FOV_DEG := 45.0
const DOT_SIZE := 2.8          # O批（用户口径①细腻小圆点）：点基准尺寸 7px 方块→2.8px 圆点面片
                               # （×逐点缩放 0.9~1.25 → 2.5~3.5px 细腻带，走查定档）
const DOT_SCALE_MIN := 0.9     # O批：0.6→0.9（细腻带下限，过大随机档废止）
const DOT_SCALE_MAX := 1.25    # O批：1.5→1.25（细腻带上限）
const FACE_SPREAD_MARGIN := 1.3  # 凝聚面覆盖余量（体素投影对角线>半边长——覆盖不足会在隐藏瞬间露出边缘木色，走查定稿）
const FACE_DEPTH_PX := 40.0    # 凝聚面深度抖动半幅（透视感：离焦平面越远点越小/视差）
const DRIFT_AMP := 6.0         # 漂移幅度（px 级，保留 M-Gb 缓慢漂移观感）
const BLINK_HZ := 0.8          # 闪烁频率（保留 M-Gb 低频闪烁）
const SPREAD_FACTOR := 1.25    # 契约面保留（O批 spread_target_screen 改屏外环域采样后不再消费；
                               # 原「盘内采样覆盖系数」语义废止留痕，暂不删除防外部引用）
const SPREAD_OUT_MARGIN := 0.35  # O批（用户口径③散开=逃出屏幕）：屏外环域外扩比例——落点半径
                                 # ∈[0.51, 0.86]×对角线长（任意方向该半径必在屏外）
const CORNER_PULL := 0.85      # 距角加权收拢强度（离角越近越密）
const CORNER_RANGE := 0.38     # 角加权影响半径（对角线比例）

var _phase := PHASE_IDLE
var _anim_t := 0.0             # 当前相位内部进度 0..1
var _spread_capture := 0.0     # RETURN 起点散开进度快照（从当前位收回）
var _return_stage := 0         # RETURN 内部段：0=散点收拢 1=实体还原
var _burst_open := false       # 同帧激活突发窗口（_toggle_focus 三通道并入同一凝聚时间线；首个凝聚 tick 关闭=防重入）
var _channels := {}            # id → {vp,color,vv,active,cells,face,facez,scale,target,dot_n}
var _mm: MultiMesh
var _mmi: MultiMeshInstance3D
var _mat: ShaderMaterial
var _cam: Camera3D
var _lvp: SubViewport
var _build_pending := false
var _rng := RandomNumberGenerator.new()
var _mm_colors := PackedColorArray()   # 生成侧自持逐点颜色（无头证据链 / N4 复用入口⑤）

## ---- P-C 滞空感缓动纯函数（可无头单测；shader SHADER_CODE 内同式字面量，两处同步改）----

## 行进缓动（前段缓出）：x∈[0,1] → 行程比例；幂 SPREAD_EASE_POW ease-out。
static func spread_ease(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), SPREAD_EASE_POW)

## 阻尼正弦悬浮（0 起止、中段峰、后段衰减）：x∈[0,1] → 悬浮系数 ∈[0,~0.5]，×SPREAD_HOVER_AMP px。
static func spread_hover(x: float) -> float:
	var c := clampf(x, 0.0, 1.0)
	return sin(c * PI) * (1.0 - c)

## ---- GPU 动画着色器（内嵌避免新增资源文件，spec §6.4 白名单约束）----
## 点位 = 实例静态 transform 原点（凝聚面位）+ mix(0, 方向×距离, ease(u_spread)) + 漂移；
## P-C 滞空感：行进 ease 幂 2.6（前段缓出）+ 沿逃逸方向叠加阻尼正弦悬浮 u_hover×sin(πx)(1−x)
## （起止为零不污染接力采样；与 CPU spread_ease/spread_hover 同式）；
## 闪烁/漂移相位由 INSTANCE_CUSTOM 分量哈希（spatial shader 无 INSTANCE_ID 内建——4.7 实证；
## INSTANCE_CUSTOM 仅 vertex 内建可直用，fragment 经 varying 传递——两轮编译实证），逐点独立，
## 随 TIME 连续动画（稳态 CPU 零成本）。
## O批（用户口径①细腻小圆点）：fragment 增圆盘 alpha——UV 距面片中心距离 smoothstep 软过渡
##（边缘 ~14% 渐隐），方形点观感废止；点 mesh 同步方块面片→QuadMesh（见 _build_mesh 选型说明）。
const SHADER_CODE := "
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, specular_disabled;
uniform float u_spread = 0.0;
uniform float u_alpha = 0.0;
uniform float u_shrink = 1.0;
uniform float u_drift = 6.0;
uniform float u_hover = 14.0;
uniform float u_blink_hz = 0.8;
varying vec4 v_col;
varying float v_blink_ph;
void vertex() {
	// P-C 滞空感缓动（与 CPU spread_ease/spread_hover 同式，幂 2.6+阻尼正弦悬浮）：
	// 前段缓出（更快进入慢速段）+ 沿逃逸方向 sin(πx)(1−x) 悬浮——「缓缓飘出」非「直落出屏」
	float e = 1.0 - pow(1.0 - clamp(u_spread, 0.0, 1.0), 2.6);
	float bob = sin(clamp(u_spread, 0.0, 1.0) * 3.14159265) * (1.0 - clamp(u_spread, 0.0, 1.0)) * u_hover;
	vec3 off = INSTANCE_CUSTOM.xyz * (INSTANCE_CUSTOM.w * e + bob);
	float ph = fract(dot(INSTANCE_CUSTOM.xyz, vec3(12.9898, 78.233, 37.719))) * 6.2831853;
	off += u_drift * vec3(sin(TIME * 0.6 + ph), sin(TIME * 0.78 + ph * 1.7), sin(TIME * 0.42 + ph * 0.6));
	VERTEX *= u_shrink;
	VERTEX += off;
	v_col = COLOR;
	v_blink_ph = fract(dot(INSTANCE_CUSTOM.xyz, vec3(93.989, 67.345, 11.135)) + INSTANCE_CUSTOM.w * 0.017) * 6.2831853;
}
void fragment() {
	float disc = 1.0 - smoothstep(0.36, 0.5, length(UV - vec2(0.5)));
	float blink = 0.55 + 0.45 * sin(TIME * 6.2831853 * u_blink_hz + v_blink_ph);
	ALBEDO = v_col.rgb;
	ALPHA = clamp(v_col.a * u_alpha * blink * disc, 0.0, 1.0);
}
"

func _ready() -> void:
	layer = LAYER
	_rng.seed = 20260909
	_build_layer()

## 全屏层结构（代码创建，避免依赖 tscn；随本节点生命周期=随关卡场景创建/销毁）。
func _build_layer() -> void:
	var cont := SubViewportContainer.new()
	cont.name = "DotContainer"
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 纯视觉层：不拦截任何点击（spec §五 4 红线）
	cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	cont.stretch = true
	add_child(cont)
	_lvp = SubViewport.new()
	_lvp.name = "SubViewport"
	_lvp.transparent_bg = true          # 游戏画面透出
	_lvp.own_world_3d = true            # 独立 3D 世界（与三视图互不干扰）
	_lvp.handle_input_locally = false
	_lvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	cont.add_child(_lvp)
	var dot_world := Node3D.new()
	dot_world.name = "DotWorld"
	_lvp.add_child(dot_world)
	_cam = Camera3D.new()
	_cam.name = "Camera3D"
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = FOV_DEG
	_cam.current = true
	var dist := compute_camera_distance(_safe_layer_size().y, FOV_DEG)
	_cam.position = Vector3(0, 0, dist)  # 焦点平面（z=0）1px=1 世界单位，正对原点
	dot_world.add_child(_cam)
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_mat.shader = sh
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "DotCloud"
	_mmi.material_override = _mat
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dot_world.add_child(_mmi)

## ---- 通道接入（spec §五 5：三视图各一条颜色通道，bind 于关卡接线区）----
func bind_channel(id: String, vp: SubViewport) -> void:
	_channels[id] = {
		"vp": vp,
		"color": CHANNEL_COLORS.get(id, GOLD),
		"vv": null,
		"active": false,
		"cells": [],
		"face": PackedVector2Array(),
		"facez": PackedFloat32Array(),
		"scale": PackedFloat32Array(),
		"target": PackedVector2Array(),
	}

func is_active() -> bool:
	## CONDENSE/HOLD/SPREAD/STEADY 为活跃；RETURN 收回中对外已失活（deactivate 已受理）。
	## N批：N4复用扩展——HOLD（持续段）纳入活跃集（聚焦路径行为不变：默认无持续段）。
	return _phase == PHASE_CONDENSE or _phase == PHASE_HOLD \
		or _phase == PHASE_SPREAD or _phase == PHASE_STEADY

## 测试钩子：当前相位。
func get_phase() -> int:
	return _phase

## 通道级活跃判定（三色共存断言面；M-Gb「每视图一个 fx」的等价替换钩子）。
func is_channel_active(id: String) -> bool:
	var ch: Variant = _channels.get(id)
	return ch is Dictionary and bool((ch as Dictionary).get("active", false))

## 当前散开进度 0..1（未散开/凝聚/持续=0，稳态=1，RETURN=从当前位回落；N4 接力读取口）。
func get_spread_progress() -> float:
	match _phase:
		PHASE_SPREAD:
			return _anim_t
		PHASE_STEADY:
			return 1.0
		PHASE_RETURN:
			if _return_stage != 0:
				return 0.0
			return _spread_capture * (1.0 - _ease01(_anim_t))
	return 0.0  # IDLE/CONDENSE/HOLD：散开未开始（N批：N4复用扩展 HOLD 分支）

## N4 复用入口⑤：指定通道逐点当前屏幕位（face→target 按散开进度插值，不含漂移）。
func get_channel_screen_positions(id: String) -> PackedVector2Array:
	var ch: Variant = _channels.get(id)
	if not (ch is Dictionary):
		return PackedVector2Array()
	var face: PackedVector2Array = (ch as Dictionary).get("face", PackedVector2Array())
	var target: PackedVector2Array = (ch as Dictionary).get("target", PackedVector2Array())
	var e := _ease01(get_spread_progress())
	var out := PackedVector2Array()
	out.resize(face.size())
	for i: int in face.size():
		out[i] = face[i].lerp(target[i], e)
	return out

## M-Gb 接线 API 面保留：activate = 主通道（金）激活（level_scene._toggle_focus 经
## activate_channel 分通道调用；独立单测/旧接线走此入口）。
func activate(selected_cells: Array, remaining_cells: Array) -> bool:
	return activate_channel("Main", selected_cells, remaining_cells)

## 通道激活：selected 非空才生效；未选中可见体素「先凝聚成点云面、凝聚完成才隐藏」并生成
## 该色散点。remaining 传 null 时回退读取通道 VoxelView 实际构建格（走查驱动便利口）。
## 返回是否激活成功；活跃期重复激活 false（幂等防重入）；RETURN 期=打断快进收尾后重新激活。
## N批：N4复用扩展——condense_all=true（成功动画成功凝聚专用）：忽略选区分割、全量构建格
## 进入凝聚（selected 可为空）；默认 false=N3 聚焦语义逐字节不变。
## O批（用户口径④成功动画全金）：override_color.a>0 时覆写本通道点色（成功动画三通道全金——
## 「无论左上右上中间全都金黄色」）；缺省 Color(0,0,0,0) 不覆写=聚焦三色语义不变（留痕）。
func activate_channel(id: String, selected_cells: Array, remaining_cells: Variant = null,
		condense_all := false, override_color := Color(0, 0, 0, 0)) -> bool:
	if _phase == PHASE_RETURN:
		_finish_return_now()  # M-Gb 语义等价保留：打断收回重新激活
	# 激活窗口：IDLE 直入；CONDENSE 且同帧突发未关闭时并入（三通道同帧各一次，N批等价替换
	# 原「三 fx 各自激活」；首个凝聚 tick 关闭窗口=后续帧重复激活 false 幂等防重入）
	var burst := _phase == PHASE_IDLE or (_phase == PHASE_CONDENSE and _burst_open)
	if not burst or not _channels.has(id):
		return false
	if not condense_all and selected_cells.is_empty():
		return false
	var ch: Dictionary = _channels[id]
	if bool(ch.get("active", false)):
		return false  # 同帧突发内重复激活同通道=幂等拒绝（契约：已激活再调 false）
	# O批：通道点色定档（覆写参数优先，缺省回退通道配色=聚焦三色）
	ch["color"] = override_color if override_color.a > 0.0 else CHANNEL_COLORS.get(id, GOLD)
	var vp: SubViewport = ch.get("vp")
	if vp == null:
		return false
	var vv: Node = ch.get("vv")
	if vv == null:
		vv = vp.get_node_or_null("VoxelView")
		ch["vv"] = vv
	if vv == null:
		return false
	var sel_set := {}
	if not condense_all:
		for v: Variant in selected_cells:
			var sc := normalize_cell(v)
			if sc.x >= 0:
				sel_set[sc] = true
		if sel_set.is_empty():
			return false
	var rem_v: Array = remaining_cells if remaining_cells is Array else (vv.call("get_built_cells") as Array)
	var to_hide := _collect_channel_dots(ch, sel_set, rem_v)
	if to_hide.is_empty():
		return false
	ch["cells"] = to_hide
	ch["active"] = true
	# 凝聚相位启动（首个成功通道触发；后续通道同帧并入同一凝聚时间线）
	if _phase == PHASE_IDLE:
		_phase = PHASE_CONDENSE
		_burst_open = true
		_anim_t = 0.0
		activated.emit()
	if not _build_pending:
		_build_pending = true
		_build_mesh.call_deferred()  # 激活突发结束统一构建一次（多通道合并单 MultiMesh）
	return true

## N批：N4复用扩展（spec §6.6 方案口径 2：三视图分组统一凝聚接口）——成功动画专用：
## 全量构建格进入该通道凝聚（无选区分割=同视图体素同步，废止逐体素随机序的入口语义）。
## remaining 传 null 回退通道 VoxelView 构建格。返回是否激活成功（幂等/防重入同 activate_channel）。
## O批：override_color 透传（成功动画三通道全金覆写入口，见 activate_channel 注）。
func activate_channel_all(id: String, remaining_cells: Variant = null,
		override_color := Color(0, 0, 0, 0)) -> bool:
	return activate_channel(id, [], remaining_cells, true, override_color)

## 完整倒放（spec §6.4 目标 2）：散点从当前位收拢→点云面→实体还原→清空。
## IDLE（无可收）/RETURN（已在倒放）重复调用幂等。
func deactivate() -> void:
	if not is_active():
		return
	_spread_capture = get_spread_progress()
	_phase = PHASE_RETURN
	_return_stage = 0
	_anim_t = 0.0
	deactivated.emit()

## 成功动画入口专用（level_scene._begin_success 调用链零改动）——跳过倒放观感立即复位：
## 体素 show + 点云清空 + 回 IDLE。不发 deactivated（入口直接接线，无监听者依赖）。
func deactivate_immediate() -> void:
	if _phase == PHASE_IDLE:
		return
	_finish_return_now()

## N批：N4复用扩展（spec §6.6 方案口径 3 + §九风险 10：生命周期移交「散点收归覆盖层承载」）——
## 成功动画聚合段起点：N3 层散点由覆盖层逐点接力采样后，本层清空散点渲染与通道态回 IDLE。
## 与 deactivate_immediate 的分歧点：**不还原体素**——成功流程中体素已随凝聚段隐藏、其可见性
## 归属成功动画（结算前保持隐藏），show_voxel 会让木块在聚合建模背后复活穿帮。
func release_particles() -> void:
	for id: String in _channels:
		var ch: Dictionary = _channels[id]
		if not bool(ch.get("active", false)):
			continue
		ch["active"] = false  # 清态但**不**调 show_voxel（成功流程体素保持隐藏）
		ch["cells"] = []
		ch["face"] = PackedVector2Array()
		ch["facez"] = PackedFloat32Array()
		ch["scale"] = PackedFloat32Array()
		ch["target"] = PackedVector2Array()
	_build_pending = false
	_burst_open = false
	_mm = null
	_mm_colors = PackedColorArray()
	if _mmi != null:
		_mmi.multimesh = null
	_set_mat_uniforms(0.0, 0.0, 1.0)
	_phase = PHASE_IDLE
	_anim_t = 0.0
	_return_stage = 0

## N批：N4复用扩展——相位实际时长（n4 覆盖值>0 优先，否则 N3 常量）。
func _eff_condense_time() -> float:
	return n4_condense_time if n4_condense_time > 0.0 else CONDENSE_TIME

func _eff_hold_time() -> float:
	# O批（用户口径③凝聚持续 0.5s，聚焦/成功两处口径一致）：n4_hold_time≤0（聚焦路径缺省）
	# 回退 FOCUS_HOLD_TIME=0.5；成功路径经 level_scene 写入 ANIM_HOLD 同值（随 time_scale 折算）。
	# N批「≤0=无持续段」语义废止留痕（聚焦凝聚后恒有 0.5s 点云面稳态）。
	return n4_hold_time if n4_hold_time > 0.0 else FOCUS_HOLD_TIME

func _eff_spread_time() -> float:
	return n4_spread_time if n4_spread_time > 0.0 else SPREAD_TIME

## 收尾共用：隐藏体素逐格 show、点云清空、通道态复位、回 IDLE
## （RETURN 自然完成 / immediate 共用；凝聚期触发时 show 为幂等无害）。
func _finish_return_now() -> void:
	for id: String in _channels:
		var ch: Dictionary = _channels[id]
		if not bool(ch.get("active", false)):
			continue
		var vv: Node = ch.get("vv")
		if vv != null:
			for c: Variant in (ch.get("cells", []) as Array):
				vv.call("show_voxel", c)
		ch["active"] = false
		ch["cells"] = []
		ch["face"] = PackedVector2Array()
		ch["facez"] = PackedFloat32Array()
		ch["scale"] = PackedFloat32Array()
		ch["target"] = PackedVector2Array()
	_build_pending = false
	_burst_open = false
	_mm = null
	_mm_colors = PackedColorArray()
	if _mmi != null:
		_mmi.multimesh = null
	_set_mat_uniforms(0.0, 0.0, 1.0)
	_phase = PHASE_IDLE
	_anim_t = 0.0
	_return_stage = 0

func _process(delta: float) -> void:
	match _phase:
		PHASE_CONDENSE:
			_tick_condense(delta)
		PHASE_HOLD:
			_tick_hold(delta)  # N批：N4复用扩展——持续段（默认时长 0 不进入）
		PHASE_SPREAD:
			_tick_spread(delta)
		PHASE_RETURN:
			_tick_return(delta)
		_:
			pass  # IDLE/STEADY：CPU 零逐帧成本（闪烁/漂移由 shader TIME 驱动）

## 凝聚 tick：点云面渐显（体素仍在屏=实体→点云面过渡）；完成才隐藏体素并进入散开。
## N批：N4复用扩展——完成后按 n4_hold_time 决定直入散开（N3）或先进持续段（N4 成功动画）。
func _tick_condense(delta: float) -> void:
	_burst_open = false  # 同帧激活突发窗口关闭（后续帧 activate=幂等拒绝）
	_anim_t = minf(_anim_t + delta / _eff_condense_time(), 1.0)
	_set_mat_uniforms(0.0, _ease01(_anim_t), 1.0)
	if _anim_t >= 1.0:
		_set_cells_visible(false)
		if _eff_hold_time() > 0.0:
			_phase = PHASE_HOLD
			_anim_t = 0.0
			_set_mat_uniforms(0.0, 1.0, 1.0)  # 点云面全显保持
		else:
			_phase = PHASE_SPREAD
			_anim_t = 0.0

## N批：N4复用扩展——持续段 tick：点云面短暂保持（体素已隐藏、散开未开始），到时进散开。
func _tick_hold(delta: float) -> void:
	_anim_t = minf(_anim_t + delta / _eff_hold_time(), 1.0)
	_set_mat_uniforms(0.0, 1.0, 1.0)
	if _anim_t >= 1.0:
		_phase = PHASE_SPREAD
		_anim_t = 0.0

## 散开 tick：只推进一个 uniform（位置混合/缓动在 GPU）。
func _tick_spread(delta: float) -> void:
	_anim_t = minf(_anim_t + delta / _eff_spread_time(), 1.0)
	_set_mat_uniforms(_anim_t, 1.0, 1.0)
	if _anim_t >= 1.0:
		_phase = PHASE_STEADY

## 倒放 tick：段0 散点从当前位收拢回点云面；段1 体素实体还原（点云收缩渐隐让位）→清空。
func _tick_return(delta: float) -> void:
	if _return_stage == 0:
		if _spread_capture > 0.001:
			_anim_t = minf(_anim_t + delta / RETURN_GATHER_TIME, 1.0)
			_set_mat_uniforms(_spread_capture * (1.0 - _ease01(_anim_t)), 1.0, 1.0)
			if _anim_t < 1.0:
				return
		_return_stage = 1  # 点云面就位 → 实体还原
		_anim_t = 0.0
		_set_cells_visible(true)
	_anim_t = minf(_anim_t + delta / RETURN_RESTORE_TIME, 1.0)
	var e := _ease01(_anim_t)
	_set_mat_uniforms(0.0, 1.0 - e, 1.0 - 0.7 * e)  # 点云收缩渐隐=实体从点云中显现
	if _anim_t >= 1.0:
		_finish_return_now()

func _set_cells_visible(visible_now: bool) -> void:
	for id: String in _channels:
		var ch: Dictionary = _channels[id]
		if not bool(ch.get("active", false)):
			continue
		var vv: Node = ch.get("vv")
		if vv == null:
			continue
		var fn := "show_voxel" if visible_now else "hide_voxel"
		for c: Variant in (ch.get("cells", []) as Array):
			vv.call(fn, c)

func _set_mat_uniforms(spread: float, alpha: float, shrink: float) -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("u_spread", spread)
	_mat.set_shader_parameter("u_alpha", alpha)
	_mat.set_shader_parameter("u_shrink", shrink)
	# P-C：滞空悬浮幅度档（单点写入；shader uniform u_hover 缺省 14.0 同值双保险）
	_mat.set_shader_parameter("u_hover", SPREAD_HOVER_AMP)

## 激活突发结束的统一构建（静态预生成一次；多通道合并进单 MultiMesh=单绘制调用）。
func _build_mesh() -> void:
	if not _build_pending:
		return
	_build_pending = false
	if _phase == PHASE_IDLE:
		return  # 构建前已被 immediate 复位（成功动画同帧入口），不建
	var lsize := _safe_layer_size()
	_cam.position = Vector3(0, 0, compute_camera_distance(lsize.y, FOV_DEG))  # 随布局自适应
	var total := 0
	for id: String in _channels:
		var ch0: Dictionary = _channels[id]
		if bool(ch0.get("active", false)):
			total += (ch0.get("face", PackedVector2Array()) as PackedVector2Array).size()
	if total <= 0:
		return
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	# O批（用户口径①细腻小圆点）圆点选型说明：QuadMesh（4 顶点/2 三角）+ fragment 圆盘 alpha
	# （SHADER_CODE smoothstep 软边缘）——备选极小 SphereMesh 被性能红线否决（高段数×数千点在
	# gl_compatibility 压力大）；billboard 渲染模式不需要：本层相机固定朝 -Z 且实例 Basis 无旋转，
	# QuadMesh 天然正对相机（零额外 GPU 成本）。
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * DOT_SIZE
	_mm.mesh = quad
	_mm.use_colors = true       # ⚠ 须在 instance_count 之前（4.7 实证，坑 13）
	_mm.use_custom_data = true  # ⚠ 同上（GPU 散开方向/距离通道）
	_mm.instance_count = total
	var cols := PackedColorArray()
	cols.resize(total)
	var vi := 0
	for id: String in ["Main", "Target", "Join"]:  # 固定序填充（通道区间稳定，N4 采样可依赖）
		var ch: Dictionary = _channels.get(id, {})
		if not bool(ch.get("active", false)):
			continue
		var face: PackedVector2Array = ch.get("face", PackedVector2Array())
		var facez: PackedFloat32Array = ch.get("facez", PackedFloat32Array())
		var scl: PackedFloat32Array = ch.get("scale", PackedFloat32Array())
		var target: PackedVector2Array = ch.get("target", PackedVector2Array())
		var col: Color = ch.get("color", GOLD)
		for i: int in face.size():
			var start := screen_to_layer_world(face[i], lsize) + Vector3(0, 0, facez[i])
			var end := screen_to_layer_world(target[i], lsize)
			var d := end - start
			var dist := d.length()
			var dir := (d / dist) if dist > 0.001 else Vector3.UP
			_mm.set_instance_transform(vi, Transform3D(Basis().scaled(Vector3.ONE * scl[i]), start))
			_mm.set_instance_color(vi, col)
			_mm.set_instance_custom_data(vi, Color(dir.x, dir.y, dir.z, dist))
			cols[vi] = col
			vi += 1
	_mm_colors = cols
	_mmi.multimesh = _mm
	_set_mat_uniforms(0.0, 0.0, 1.0)  # 凝聚起点（首帧不可见，无闪烁穿帮）

## 通道散点静态预生成：每体素 22 点=凝聚面（体素投影面内偏移+深度抖动）+全屏四角加权目标位。
## 返回该通道隐藏格列表（空=无可凝聚，激活失败）。
func _collect_channel_dots(ch: Dictionary, sel_set: Dictionary, remaining_v: Array) -> Array:
	var vp: SubViewport = ch.get("vp")
	var vv: Node = ch.get("vv")
	if vp == null or vv == null:
		return []
	var rem_set := {}
	for v: Variant in remaining_v:
		var cell := normalize_cell(v)
		if cell.x >= 0:
			rem_set[cell] = true
	for k: Variant in sel_set:
		rem_set.erase(k)
	if rem_set.is_empty():
		return []
	var cam: Camera3D = vp.get_node_or_null("Camera3D") as Camera3D
	var center: Vector3 = vv.call("get_center_offset")
	var lsize := _safe_layer_size()
	var half_face := _voxel_half_screen_px(cam, vp) * FACE_SPREAD_MARGIN
	var to_hide: Array = rem_set.keys()
	var face: PackedVector2Array = ch.get("face", PackedVector2Array())
	var facez: PackedFloat32Array = ch.get("facez", PackedFloat32Array())
	var scl: PackedFloat32Array = ch.get("scale", PackedFloat32Array())
	var target: PackedVector2Array = ch.get("target", PackedVector2Array())
	for cell: Vector3i in to_hide:
		var world := Vector3(cell) + Vector3(0.5, 0.5, 0.5) - center  # 体素中心（P1-2 同式）
		var sp := _voxel_screen_pos(cam, vp, world, lsize)
		for k: int in DOTS_PER_VOXEL:
			face.append(sp + Vector2(_rng.randf_range(-1, 1) * half_face, _rng.randf_range(-1, 1) * half_face))
			facez.append(_rng.randf_range(-1, 1) * FACE_DEPTH_PX * 0.5)
			scl.append(_rng.randf_range(DOT_SCALE_MIN, DOT_SCALE_MAX))
			target.append(spread_target_screen(sp, _rng, lsize))
	ch["face"] = face
	ch["facez"] = facez
	ch["scale"] = scl
	ch["target"] = target
	return to_hide

## ---- 坐标换算（spec §五 5：三视图体素位置→全屏层，单处实现）----

## 视图体素世界位 → 全屏层屏幕位（视图相机 unproject + 视图容器全局位；度量缺失防御回退屏中心）。
static func _voxel_screen_pos(cam: Camera3D, vp: SubViewport, world: Vector3, layer_size: Vector2) -> Vector2:
	if cam != null and vp != null and cam.is_inside_tree() and vp.size.x >= 1 and vp.size.y >= 1:
		var p := cam.unproject_position(world)
		var par: Node = vp.get_parent()
		if par is Control:
			p += (par as Control).get_global_position()
		return p
	return layer_size * 0.5

## 视图正交相机下体素投影半边长（KEEP_HEIGHT：1 世界单位 = size.y/cam.size px）；
## 非正交/度量缺失回退 24px（暂定值，走查微调）。
static func _voxel_half_screen_px(cam: Camera3D, vp: SubViewport) -> float:
	if cam != null and cam.projection == Camera3D.PROJECTION_ORTHOGONAL and cam.size > 0.0 \
			and vp != null and vp.size.y >= 1:
		return 0.47 * (float(vp.size.y) / cam.size)  # VOXEL_INSET 0.94 之半
	return 24.0

## 全屏层屏幕位 → 层世界位（焦点平面 1px=1 世界单位，y 翻转；vp_size 无效用设计视口）。
static func screen_to_layer_world(sp: Vector2, vp_size: Vector2) -> Vector3:
	var s := vp_size
	if s.y < 1.0 or s.x < 1.0:
		s = DESIGN_SIZE
	return Vector3(sp.x - s.x * 0.5, s.y * 0.5 - sp.y, 0.0)

## 透视相机距离（N批等价替换 M-Gb compute_spread_scale）：焦点平面可见高=view_h，
## 即 dist=(h/2)/tan(fov/2)；h 无效回退设计视口高（保证非退化）。
static func compute_camera_distance(view_h: float, fov_deg: float) -> float:
	var h := view_h if view_h > 0.0 else DESIGN_SIZE.y
	var f := fov_deg if fov_deg > 0.0 else FOV_DEG
	return (h * 0.5) / tan(deg_to_rad(f) * 0.5)

## ---- 散点密度（spec §五 5：目标屏幕位按「距四角距离」加权，离角越近越密；N4 复用入口②）----

## 距最近角的贴近度 0..1（角=1，中心≈0）。
static func corner_closeness(sp: Vector2, vp_size: Vector2) -> float:
	var dmin := minf(minf(sp.distance_to(Vector2.ZERO), sp.distance_to(Vector2(vp_size.x, 0))),
		minf(sp.distance_to(Vector2(0, vp_size.y)), sp.distance_to(vp_size)))
	var diag := vp_size.length()
	if diag <= 0.0:
		return 0.0
	return clampf(1.0 - dmin / (diag * CORNER_RANGE), 0.0, 1.0)

## 距 sp 最近的屏幕角。
static func nearest_corner(sp: Vector2, vp_size: Vector2) -> Vector2:
	return Vector2(0.0 if sp.x < vp_size.x * 0.5 else vp_size.x,
		0.0 if sp.y < vp_size.y * 0.5 else vp_size.y)

## 散点目标屏幕位（纯函数，rnd 注入=可复现）。O批等价替换（用户口径③「先发散到屏幕外面」）：
## ①方向均匀采样后按角向贴近度把方向拉向最近角对角线（离角方向更密——原「径向向角收拢」
##   语义的屏外等价：四角方向为主保留）；②落点半径 ∈[0.51, 0.51+MARGIN]×对角线长（任意方向
##   该半径必在屏外）——原「盘内采样+clamp 屏内（全屏铺满）」口径废止，散开观感=向外逃出屏幕。
static func spread_target_screen(_origin: Vector2, rnd: RandomNumberGenerator, vp_size: Vector2) -> Vector2:
	var half := vp_size * 0.5
	var ang := rnd.randf() * TAU
	var dir := Vector2(cos(ang), sin(ang))
	var probe := half + dir * minf(half.x, half.y)
	var cc := corner_closeness(probe, vp_size)
	if cc > 0.0:
		var corner_dir := (nearest_corner(probe, vp_size) - half).normalized()
		dir = dir.lerp(corner_dir, clampf(cc * CORNER_PULL, 0.0, 1.0)).normalized()
	var r_escape := vp_size.length() * (0.51 + rnd.randf() * SPREAD_OUT_MARGIN)
	return half + dir * r_escape

## ---- 内部工具 ----

func _safe_layer_size() -> Vector2:
	if _lvp != null and _lvp.size.x >= 1 and _lvp.size.y >= 1:
		return Vector2(_lvp.size)
	return DESIGN_SIZE

static func _ease01(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 2.0)

## 格位输入归一（Vector3i/Vector3/"x,y,z" 均接受；非法=(-1,-1,-1) 由调用方剔除）。
## 字符串口径对齐 level_voxel_view._parse_voxel（走查 TCP 驱动注入字符串键选区用）。
static func normalize_cell(v: Variant) -> Vector3i:
	if v is Vector3i:
		return v
	if v is Vector3:
		return Vector3i(int(roundf((v as Vector3).x)), int(roundf((v as Vector3).y)), int(roundf((v as Vector3).z)))
	if v is String:
		var parts: PackedStringArray = (v as String).split(",")
		if parts.size() == 3:
			return Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
	return Vector3i(-1, -1, -1)
