extends "res://tests/test_base.gd"
## 批次 Y（Y-A1，spec §2 域一①）：TopStrip 恒顶部水平居中几何加固——TDD 回归锁。
## 根因探针定谳（AI工作记录/批次Y_走查_20260922/y3_probe_topstrip_定谳.md）：
##   缺陷①全宽残留：旧 grow-BOTH 布局反算 offsets 一次性写入，min 回缩后不重算（探针 p5/p6：
##   min=320 而 size=1124、offsets ±562 残留）；
##   缺陷②贴左：残留态 reset_size 以旧 position 反算 offsets → 非对称（探针 p7：ol=-772/or=-32，
##   center_err=-402，截图 y3_p7b 条贴死左上角）。
## 修复口径：_refit_width 无状态恒对称重推导单漏斗（push/resized/视口 size_changed 三入口）。
## 无头断言几何（批次 R 坑⑥口径：布局数值可无头断言；视觉终证=窗口截图 y3_p8*）。

const TS_SCRIPT := "res://scenes/shared/top_strip.gd"

func _center_err(strip: Control) -> float:
	var vp_w: float = strip.get_viewport_rect().size.x
	return strip.global_position.x + strip.size.x * 0.5 - vp_w * 0.5

func _symmetric(strip: Control) -> bool:
	return is_equal_approx(float(strip.get("offset_left")), -float(strip.get("offset_right")))

func _initialize() -> void:
	print("== test_y_topstrip_center ==")
	var strip: Control = (load(TS_SCRIPT) as GDScript).new()
	add_child(strip)
	await process_frame
	await process_frame

	# ---- 1. 基准：短 info 居中 + offsets 对称（探针 p1 等价回归）----
	strip.call("push_info", "手势交互需要摄像头，无法关闭")
	await process_frame
	await process_frame
	check(absf(_center_err(strip)) <= 1.0, "Y-A1 基准：短 info 居中（center_err≤1；实测 %.1f）" % _center_err(strip))
	check(_symmetric(strip), "Y-A1 基准：offsets 恒对称（offset_left==-offset_right）")

	# ---- 2. 缺陷①红锁：钳制全宽后内容回短 → size 收缩回内容宽、条仍居中 ----
	strip.call("push_confirm", "X".repeat(200))
	await process_frame
	await process_frame
	check(strip.size.x <= strip.get_viewport_rect().size.x - 28.0 + 1.0,
		"Y-A1 前置：长文案钳制全宽（实测 %.1f）" % strip.size.x)
	strip.call("dismiss_active_confirm")
	strip.call("push_info", "返回图鉴？")
	await process_frame
	await process_frame
	check(strip.size.x <= strip.get_combined_minimum_size().x + 1.0,
		"Y-A1 ①：内容回短后条宽收缩回内容宽（min %.1f，实测 %.1f——旧码残留全宽 1124 红灯）"
			% [strip.get_combined_minimum_size().x, strip.size.x])
	check(absf(_center_err(strip)) <= 1.0,
		"Y-A1 ①：回缩后仍居中（center_err %.1f）" % _center_err(strip))

	# ---- 3. 缺陷②红锁：非对称残留 offsets（探针 p7 实测值复刻）→ push 后重推导对称复位 ----
	strip.set("offset_left", -772.0)   # 探针 p7 贴左实测值原样注入（模拟残留态）
	strip.set("offset_right", -32.0)
	strip.call("push_info", "短文案复位")
	await process_frame
	await process_frame
	check(_symmetric(strip), "Y-A1 ②：非对称残留态 push 后 offsets 重推导对称复位（旧码原样残留=红灯）")
	check(absf(_center_err(strip)) <= 1.0,
		"Y-A1 ②：复位后居中（旧码贴左 center_err=-402；实测 %.1f）" % _center_err(strip))
	check(strip.size.x <= strip.get_combined_minimum_size().x + 1.0,
		"Y-A1 ②：复位后条宽=内容宽（不残留旧尺寸）")

	# ---- 4. 弹条在场时改窗口尺寸（视口 size_changed 重推导）→ 恒居中 ----
	strip.call("push_confirm", "X".repeat(200))
	await process_frame
	await process_frame
	var root_win: Window = get_root()
	var old_size: Vector2i = root_win.size
	root_win.size = Vector2i(1000, 640)   # 窄档（expand 拉伸下钳制域变化）
	await process_frame
	await process_frame
	await process_frame
	check(absf(_center_err(strip)) <= 1.0,
		"Y-A1 ④：钳制态缩窗后仍居中（center_err %.1f）" % _center_err(strip))
	check(strip.size.x <= strip.get_viewport_rect().size.x - 28.0 + 1.0,
		"Y-A1 ④：缩窗后条宽随新钳制域（实测 %.1f ≤ 视口-28）" % strip.size.x)
	root_win.size = old_size   # 还原窗口（后续段不受污染）
	await process_frame
	await process_frame
	check(absf(_center_err(strip)) <= 1.0, "Y-A1 ④：还原窗口后仍居中")

	# ---- 5. 超宽折行回归（A10 同口径新链路复验：explicit offsets 下仍折行不溢出）----
	strip.call("dismiss_active_confirm")
	strip.call("push_info", "摄".repeat(120))
	await process_frame
	await process_frame
	check(strip.size.x <= strip.get_viewport_rect().size.x - 28.0 + 1.0,
		"Y-A1 ⑤：超宽文案条宽 ≤ 视口宽−2×14（autowrap 折行，实测 %.1f）" % strip.size.x)
	check_eq(strip.visible, true, "Y-A1 ⑤：超宽文案条仍显示")

	strip.queue_free()
	await process_frame
	finish()
