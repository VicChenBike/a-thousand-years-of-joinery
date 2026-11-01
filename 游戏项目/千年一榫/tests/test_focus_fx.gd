extends "res://tests/test_base.gd"
## KG-1（批次 K / K6-7，spec §10.5）→ N3 等价重写（批次 N / spec §6.4 + §五 4~7）：
## FocusFX 全屏三色散点控制器判定用例。旧「每视图 SubViewport 内 CPU 金点」契约随重写废止，
## 本文件按 N3 新契约等价重写并留痕（总 checks 只增不减）。
## 契约（spec §6.4 方案口径）：scripts/focus_fx.gd——class_name FocusFX extends CanvasLayer（全屏层 0）；
##   signal activated/deactivated；is_active()/get_phase()/is_channel_active(id)；
##   activate(selected_cells, remaining_cells) -> bool（保留接线 API 面=主通道激活）；
##   activate_channel(id, selected, remaining) -> bool（三通道接入；selected 非空才生效；
##     已活跃再调 false 幂等；凝聚期体素先不隐藏=实体→点云面过渡，凝聚完成才 hide）；
##   deactivate()（完整倒放 RETURN：收拢→点云面→实体还原，幂等）；
##   deactivate_immediate()（成功动画入口，立即复位，幂等）；
##   bind_channel(id, vp)（通道接入）；常量组 PHASE_IDLE=0/CONDENSE=1/SPREAD=2/STEADY=3/RETURN=4、
##   CONDENSE_TIME=0.25 / SPREAD_TIME=0.9 / RETURN_TIME=0.6 / DOTS_PER_VOXEL=22 / LAYER=0 /
##   GOLD=Color(0.96,0.77,0.26) / CHANNEL_COLORS 三色。⚠ use_colors/use_custom_data 先于
##   instance_count（4.7 实证，坑 13）。
## 4.7 规避：无头 MultiMesh 色/transform/custom 读回恒 0——只断言
##   instance_count/材质标志/自持数组等属性级证据链；闪烁/漂移/四角密度/透视感观感=窗口截图判定。
## 环境说明（同既有测试）：--script 模式 class_name 注册时序不稳（T14 实证）——
##   新组件一律 load() + call()，不直接引用全局类名（P2-5）。

const FX_SCRIPT := "res://scripts/focus_fx.gd"
const VOX_SCRIPT := "res://scripts/level_voxel_view.gd"

## 递归查找子树中的 MultiMeshInstance3D（不约定节点名，降脆性）。
func _find_mmi(node: Node) -> MultiMeshInstance3D:
	for c: Node in node.get_children():
		if c is MultiMeshInstance3D:
			return c as MultiMeshInstance3D
		var found: MultiMeshInstance3D = _find_mmi(c)
		if found != null:
			return found
	return null

func _initialize() -> void:
	print("== test_focus_fx ==")
	var fx_s: Script = load(FX_SCRIPT) as Script
	check(fx_s != null, "K6-7→N3：scripts/focus_fx.gd 可加载")
	var vox_s: Script = load(VOX_SCRIPT) as Script
	check(vox_s != null, "K6-7 前置：level_voxel_view.gd 可加载")
	if fx_s == null or vox_s == null:
		finish()
		return

	# ---- 接口存在性：经实例断言（--script 模式 Script.has_signal 对刚 load 脚本不可靠，
	# 同 test_hover_glow 口径；load() 方式，P2-5）----
	var fx_probe: Node = (fx_s as GDScript).new()
	check(fx_probe is CanvasLayer, "N3①：FocusFX extends CanvasLayer（全屏层载体，等价替换原 Node3D）")
	check(fx_probe.has_signal("activated"), "K6-7→N3：signal activated 存在（API 面保留）")
	check(fx_probe.has_signal("deactivated"), "K6-7→N3：signal deactivated 存在（API 面保留）")
	check(fx_probe.has_method("activate") and fx_probe.has_method("deactivate") and fx_probe.has_method("is_active"),
		"K6-7→N3：接口 activate/deactivate/is_active 齐备（API 面保留）")
	check(fx_probe.has_method("activate_channel") and fx_probe.has_method("bind_channel")
		and fx_probe.has_method("deactivate_immediate") and fx_probe.has_method("get_phase")
		and fx_probe.has_method("is_channel_active"),
		"N3：接口 activate_channel/bind_channel/deactivate_immediate/get_phase/is_channel_active 齐备")
	fx_probe.free()

	# ---- 常量组（N3 新状态机 + 三色通道，spec §6.4 定稿值，走查微调项以常量为准）----
	var cmap: Dictionary = fx_s.get_script_constant_map()
	check_eq(cmap.get("GOLD"), Color(0.96, 0.77, 0.26), "K6-7→N3：GOLD=Color(0.96,0.77,0.26)（主通道金，契约面保留）")
	check_eq(int(cmap.get("DOTS_PER_VOXEL", -1)), 7, "O批等价替换（2026-09-10 用户反馈②遮屏降密）：DOTS_PER_VOXEL=7（∈[6,8] 细腻档；N3 22 档废止，M批 6 亦废）")
	check_eq(float(cmap.get("BLINK_HZ", -1.0)), 0.8, "K6-7→N3：BLINK_HZ=0.8（低频闪烁保留，shader 同款）")
	check_eq(float(cmap.get("DRIFT_AMP", -1.0)), 6.0, "N3：DRIFT_AMP=6.0（px 级漂移保留，M批 0.15 视图单位等价替换留痕）")
	check_eq(int(cmap.get("LAYER", -1)), 0, "N3：LAYER=0（走查定稿：关卡同层树序置顶，GlobalUI=1/SuccessOverlay=0（P批波2 结算覆盖层避让设置面板）在其上；spec 暂定 85→0 走查可调留痕）")
	check_eq(float(cmap.get("CONDENSE_TIME", -1.0)), 0.25, "N3：CONDENSE_TIME=0.25（实体→点云面，spec 暂定）")
	check_eq(float(cmap.get("SPREAD_TIME", -1.0)), 1.2,
		"P批波2等价替换（2026-09-10 用户口径 P-C 散开放慢+滞空）：SPREAD_TIME=1.2（聚焦散开；N3 0.9 档废止留痕）")
	check_eq(float(cmap.get("RETURN_TIME", -1.0)), 0.6, "N3：RETURN_TIME=0.6（完整倒放，M批 0.4 等价替换留痕）")
	var cm: Dictionary = cmap.get("CHANNEL_COLORS", {})
	check_eq(cm.get("Main", Color()), Color(0.96, 0.77, 0.26), "N3②：主通道=金黄")
	check_eq(cm.get("Target", Color()), Color(0.30, 0.85, 0.40), "N3②：对照成品通道=绿")
	check_eq(cm.get("Join", Color()), Color(0.90, 0.25, 0.20), "N3②：对接固定件通道=红")
	var cset := {cm.get("Main", Color()): true, cm.get("Target", Color()): true, cm.get("Join", Color()): true}
	check(cset.size() == 3, "N3②：三色互异（三色共存可辨前提）")

	# ---- 组装：全屏层 rig + 通道视口（VoxelView name 契约=VoxelView）----
	var world := Node3D.new()
	add_child(world)
	var vp := SubViewport.new()
	vp.size = Vector2i(160, 120)
	world.add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 6.0
	cam.position = Vector3(0, 0, 20)
	vp.add_child(cam)
	var vv: Node = (vox_s as GDScript).new()
	vv.name = "VoxelView"
	vp.add_child(vv)
	vv.call("build_voxels", ["0,0,0", "1,0,0", "2,0,0", "3,0,0"], Vector3i(4, 1, 1), StandardMaterial3D.new())
	var fx: Node = (fx_s as GDScript).new()
	fx.name = "FocusFX"
	world.add_child(fx)
	fx.call("bind_channel", "Main", vp)
	await process_frame

	var built: Array = vv.call("get_built_cells")
	var cmap2: Dictionary = fx_s.get_script_constant_map()
	# 1) 空选不激活
	check_eq(bool(fx.call("activate", [], built)), false, "K6-7→N3：selected 为空 activate 返回 false（不激活）")
	check_eq(bool(fx.call("is_active")), false, "K6-7→N3：空选后 is_active()==false")
	# 2) 正常激活（legacy API=主通道）：选 (0,0,0)(1,0,0)，未选 (2,0,0)(3,0,0)
	check_eq(bool(fx.call("activate", [Vector3i(0, 0, 0), Vector3i(1, 0, 0)], built)), true,
		"K6-7→N3：非空 selected activate 返回 true")
	check_eq(int(fx.call("get_phase")), int(cmap2.get("PHASE_CONDENSE", -1)),
		"N3③：激活后 get_phase()==CONDENSE（先凝聚，M批直入 SPREAD 等价替换）")
	check_eq(bool(fx.call("is_active")), true, "K6-7→N3：激活后 is_active()==true")
	# 3) 凝聚期体素仍可见（实体→点云面过渡=修瞬时 hide 卡顿，N批行为变化留痕）
	var n_unsel: MeshInstance3D = vv.call("get_voxel_node", Vector3i(2, 0, 0))
	var n_sel: MeshInstance3D = vv.call("get_voxel_node", Vector3i(0, 0, 0))
	check(n_unsel != null and n_unsel.visible == true,
		"N3③：凝聚期未选中格 (2,0,0) 仍可见（实体→点云面，M批「激活即隐藏」等价替换留痕）")
	check(n_sel != null and n_sel.visible == true, "K6-7：选中格 (0,0,0) 保持可见")
	# 4) 重复激活幂等（活跃期）
	check_eq(bool(fx.call("activate", [Vector3i(0, 0, 0)], built)), false,
		"K6-7→N3：已激活重复 activate 返回 false（幂等）")
	# 5) 凝聚完成：体素隐藏+点云接管（无空窗），点云证据链（无头读回恒 0，只断属性）
	# O批等价替换（2026-09-10 用户口径③）：凝聚完成后先进 HOLD 持续段（0.5s，聚焦/成功两处
	# 口径一致）再入 SPREAD——原 N3「凝聚完成直入 SPREAD」时序废止留痕。
	await create_timer(0.35).timeout  # > CONDENSE_TIME 0.25，< 0.25+FOCUS_HOLD_TIME 0.5
	check_eq(int(fx.call("get_phase")), int(cmap2.get("PHASE_HOLD", -1)),
		"O批等价替换：凝聚完成 → HOLD 持续段（点云面稳态 0.5s；原直入 SPREAD 断言废止）")
	check_eq(float(fx.call("get_spread_progress")), 0.0, "O批：HOLD 期散开进度=0（倒放从点云面还原语义不变）")
	await create_timer(0.55).timeout  # 累计 0.9 > 0.25+0.5 → 散开起步
	check_eq(int(fx.call("get_phase")), int(cmap2.get("PHASE_SPREAD", -1)),
		"N3③：持续完成 → SPREAD 相位（散开目标=屏外，O批③留痕）")
	check(n_unsel != null and n_unsel.visible == false,
		"N3③：凝聚完成未选中格 (2,0,0) 隐藏（点云面已接管，无空窗跳变）")
	var mmi: MultiMeshInstance3D = _find_mmi(fx)
	check(mmi != null, "K6-7→N3：激活后 FocusFX 子树含 MultiMeshInstance3D")
	if mmi != null:
		var exp_n: int = 2 * int(cmap.get("DOTS_PER_VOXEL", -1))
		check(mmi.multimesh != null and mmi.multimesh.instance_count == exp_n,
			"O批等价替换：instance_count=28（7 点/格 × 未选中 2 格；N3 22 点/格 档废止留痕）")
		check(mmi.multimesh != null and mmi.multimesh.use_colors,
			"N3②：use_colors=true（三色逐实例前提；坑 13 先于 instance_count）")
		check(mmi.multimesh != null and mmi.multimesh.use_custom_data,
			"N3④：use_custom_data=true（GPU 散开方向/距离通道）")
		var smat: Material = mmi.material_override
		check(smat is ShaderMaterial and (smat as ShaderMaterial).shader != null \
			and (smat as ShaderMaterial).shader.code.contains("u_spread") \
			and (smat as ShaderMaterial).shader.code.contains("INSTANCE_CUSTOM") \
			and (smat as ShaderMaterial).shader.code.contains("TIME"),
			"N3④：ShaderMaterial uniform/TIME 驱动（禁逐帧 CPU 重建点阵红线证据）")
	# 5b) 通道自持数组证据链（无头 MultiMesh 读回恒 0 的替代证据；N4 采样口）
	var chs: Dictionary = fx.get("_channels")
	var face: PackedVector2Array = chs.get("Main", {}).get("face", PackedVector2Array())
	var tgt: PackedVector2Array = chs.get("Main", {}).get("target", PackedVector2Array())
	check(face.size() == 14 and tgt.size() == 14,
		"O批等价替换：通道 face/target 自持数组与点数等长 14（静态预生成；原 44=N3 22点档废止）")
	# 6) deactivate：N3 等价替换（spec §6.4 目标 2）——完整倒放 RETURN（收拢→点云面→实体还原）：
	# 倒放完成前体素保持隐藏、完成后恢复可见+点云清空；重复调用幂等。
	fx.call("deactivate")
	check_eq(int(fx.call("get_phase")), int(cmap2.get("PHASE_RETURN", -1)),
		"N3③：deactivate → RETURN 倒放相位（get_phase 钩子）")
	check_eq(bool(fx.call("is_active")), false, "K6-7→N3：deactivate 后 is_active()==false（RETURN 期对外失活）")
	check(n_unsel != null and n_unsel.visible == false,
		"K6-7→N3：倒放完成前体素 (2,0,0) 保持隐藏（实体未还原）")
	await create_timer(0.75).timeout  # > RETURN_TIME 0.6
	check_eq(int(fx.call("get_phase")), int(cmap2.get("PHASE_IDLE", -1)), "N3③：倒放完成 → IDLE 相位")
	check(n_unsel != null and n_unsel.visible == true,
		"K6-7→N3：倒放完成后体素 (2,0,0) 实体还原（完整倒放；M批 RETURN 等价替换）")
	var mmi2: MultiMeshInstance3D = _find_mmi(fx)
	check(mmi2 == null or mmi2.multimesh == null, "N3③：倒放完成点云清空（无残留点阵）")
	fx.call("deactivate")
	check(true, "K6-7→N3：deactivate 幂等不崩（IDLE 重复调用）")
	# 7) RETURN 期 activate=打断快进收尾后重新激活（M-Gb 语义等价保留）
	fx.call("activate", [Vector3i(0, 0, 0)], built)
	fx.call("deactivate")
	check_eq(int(fx.call("get_phase")), int(cmap2.get("PHASE_RETURN", -1)), "N3③ 前置：进入 RETURN")
	check_eq(bool(fx.call("activate", [Vector3i(0, 0, 0)], built)), true,
		"M-Gb②→N3：RETURN 期 activate 打断收回并重新激活（返回 true）")
	check_eq(int(fx.call("get_phase")), int(cmap2.get("PHASE_CONDENSE", -1)), "N3③：打断后回 CONDENSE 相位")
	# 8) deactivate_immediate（成功动画入口）：立即复位/体素还原/点云清空，幂等
	fx.call("deactivate_immediate")
	check_eq(int(fx.call("get_phase")), int(cmap2.get("PHASE_IDLE", -1)),
		"M-Gb②→N3：deactivate_immediate 立即复位 IDLE（成功动画入口专用）")
	check(n_unsel != null and n_unsel.visible == true, "N3③：immediate 后体素立即还原")
	fx.call("deactivate_immediate")  # 已 IDLE，重复调用幂等
	check_eq(int(fx.call("get_phase")), int(cmap2.get("PHASE_IDLE", -1)),
		"M-Gb②→N3：deactivate_immediate 幂等不崩（相位保持 IDLE）")
	world.queue_free()
	finish()
