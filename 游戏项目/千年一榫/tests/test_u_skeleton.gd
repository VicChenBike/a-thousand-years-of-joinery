extends "res://tests/test_base.gd"
## 批次 U 判定用例（U-D 域·骨架）：pillarbox_rect 纯函数表驱动＋颜色/绘制参数常量＋23 段连接表
## ＋数据刷新节流＋IGNORE。spec §4-U6/§6.3。D 盘 :144-162 实况 23 段为逐段照录依据。
## 磁盘实况适配留痕（与 test_u_hover_tip 同款两坑预防）：
## ① GDScript 资源 .get() 非 static 不可类上调（4.7 Parse Error）→ 常量改静态成员访问
##   SkScript.CONST（preload 脚本常量静态可解析）；
## ② lambda 按值捕获（创建时快照）→ draw 计数器改单元素 Array 引用单元。

const SkScript := preload("res://scenes/shared/camera_skeleton.gd")

func _make_lm(wrist: Vector2, tip: Vector2) -> Array:
	# 21 点合成：0=腕、8=食指尖，其余沿腕→指尖线性插值（几何合理即可）
	var lm := []
	for i: int in 21:
		lm.append([wrist.x + (tip.x - wrist.x) * i / 20.0, wrist.y + (tip.y - wrist.y) * i / 20.0])
	return lm

func _initialize() -> void:
	print("== test_u_skeleton ==")
	# ---- 段 1. pillarbox_rect 纯函数表驱动（8 checks）----
	var r1: Rect2 = SkScript.pillarbox_rect(Vector2(320, 180), Vector2(640, 480))
	check(r1.position.is_equal_approx(Vector2(40, 0)) and r1.size.is_equal_approx(Vector2(240, 180)),
		"U6：4:3 源 320×180 窗 → 内衬 240×180 @(40,0)（spec 锚）")
	var r2: Rect2 = SkScript.pillarbox_rect(Vector2(320, 180), Vector2(320, 180))
	check(r2.position.is_equal_approx(Vector2.ZERO) and r2.size.is_equal_approx(Vector2(320, 180)),
		"U6：16:9 源 → 满窗")
	var r3: Rect2 = SkScript.pillarbox_rect(Vector2(320, 180), Vector2(180, 320))
	# 磁盘实况适配留痕：计划原文断言 r3.position==(0,0) 与 keep-aspect-centered 契约（spec §4-U6-2）
	# 及本文件段 1 第一锚（4:3 源 → 内衬@(40,0) 居中）自相矛盾——竖幅源居中内衬 position.x=(320−inner.x)/2
	# ≠0。按契约修正为「满高+左右收窄+水平居中」，断言强度不降。
	check(r3.size.y == 180.0 and r3.size.x < 320.0 and r3.position.y == 0.0
		and absf(r3.position.x * 2.0 + r3.size.x - 320.0) <= 1.0,
		"U6：竖幅源 → 左右收窄水平居中内衬（上下对齐同理；keep-aspect-centered 契约）")
	var r4: Rect2 = SkScript.pillarbox_rect(Vector2(224, 126), Vector2(1920, 1080))
	check(r4.size.is_equal_approx(Vector2(224, 126)) and r4.position.is_equal_approx(Vector2.ZERO),
		"U6：1080p 源 224×126 窗 → 满窗（16:9 对 16:9）")
	var r5: Rect2 = SkScript.pillarbox_rect(Vector2(320, 180), Vector2.ZERO)
	check(r5.is_equal_approx(Rect2(Vector2.ZERO, Vector2(320, 180))), "U6：src 零尺寸防御 → 回退满窗（不炸）")
	var r6: Rect2 = SkScript.pillarbox_rect(Vector2.ZERO, Vector2(640, 480))
	check(r6.is_equal_approx(Rect2()), "U6：win 零尺寸防御 → 空矩形（不炸）")
	var r7: Rect2 = SkScript.pillarbox_rect(Vector2(300, 180), Vector2(2000, 480))
	check(absf(r7.size.x / r7.size.y - 2000.0 / 480.0) < 0.02, "U6：极端宽源 → 内衬保持源比例（keep-aspect）")
	var r8: Rect2 = SkScript.pillarbox_rect(Vector2(320, 180), Vector2(1024, 768))
	check(r8.size.x <= 320.0 and r8.size.y <= 180.0 and r8.position.x >= 0.0 and r8.position.y >= 0.0,
		"U6：4:3 源（1024×768）→ 内衬不越窗、起点非负")
	# ---- 段 2. 颜色常量（2 checks）----
	check((SkScript.SKELETON_COLOR_LEFT as Color).is_equal_approx(Color(0.30, 0.55, 1.0)), "U6：左蓝逐分量")
	check((SkScript.SKELETON_COLOR_RIGHT as Color).is_equal_approx(Color(1.0, 0.35, 0.30)), "U6：右红逐分量")
	# ---- 段 3. 绘制参数常量（3 checks；批次 W4-N6 等价改写：用户反馈「骨架太粗糊团」——
	# 变细起步档 2.0→1.2 / 7.0→4.0 / 4.0→2.5（camera_skeleton.gd:21-23，左蓝右红不变），
	# 旧 D 盘口径三断言同位替换，走查可微调档）----
	check_eq(float(SkScript.SKELETON_LINE_W), 1.2, "U6：线宽 1.2（W4-N6 变细，旧 D 盘口径 2.0 退役）")
	check_eq(float(SkScript.SKELETON_TIP_R), 4.0, "U6：指尖圆 r=4（W4-N6，旧 7.0 退役）")
	check_eq(float(SkScript.SKELETON_JOINT_R), 2.5, "U6：关节圆 r=2.5（W4-N6，旧 4.0 退役）")
	# ---- 段 4. 连接表（2 checks）----
	var conns: Array = SkScript.HAND_CONNECTIONS
	check_eq(conns.size(), 23, "U6：HAND_CONNECTIONS 段数==23（D 盘实况；需求原文 25 系计数偏差勘误）")
	var expect_set := [[0, 1], [1, 2], [2, 3], [3, 4], [0, 5], [5, 6], [6, 7], [7, 8],
		[0, 9], [9, 10], [10, 11], [11, 12], [0, 13], [13, 14], [14, 15], [15, 16],
		[0, 17], [17, 18], [18, 19], [19, 20], [5, 9], [9, 13], [13, 17]]
	var got := []
	for c: Variant in conns:
		got.append([int((c as Array)[0]), int((c as Array)[1])])
	check(got == expect_set, "U6：23 段逐段照录一致（拇指/食指/中指/无名指/小指各 4＋掌骨 3）")
	# ---- 段 5. 数据刷新与节流（4 checks；双审回修④「纹理缺失」恒真断言已删并置换为真实断言「纹理置空后数据缓存保持」，条数不变）----
	var sk: Control = SkScript.new()
	var win := TextureRect.new()
	win.size = Vector2(320, 180)
	win.add_child(sk)
	get_root().add_child(win)
	await process_frame
	var redraw_cell: Array = [0]   # lambda 按值捕获 → Array 引用单元（头注②）
	sk.draw.connect(func() -> void: redraw_cell[0] += 1)
	sk.set_hands({"landmarks": _make_lm(Vector2(0.2, 0.5), Vector2(0.4, 0.3))}, null)
	for i: int in 60:   # 1s 内 60 包
		sk.set_hands({"landmarks": _make_lm(Vector2(0.2, 0.5), Vector2(0.4, 0.3))}, null)
		sk._process(1.0 / 60.0)
	check(int(redraw_cell[0]) <= 31, "U6：重绘节流 30fps（1s 内 60 包 → 重绘 ≤31，实测 %d）" % int(redraw_cell[0]))
	sk.clear_hands()
	sk._process(1.0 / 30.0)
	sk._process(1.0 / 30.0)
	await process_frame
	check(sk._hands.is_empty(), "U6：clear_hands → 双侧清空（手离场）")
	var tex := ImageTexture.create_from_image(Image.create(640, 480, false, Image.FORMAT_RGB8))
	win.texture = tex
	sk.set_hands(null, {"landmarks": _make_lm(Vector2(0.5, 0.2), Vector2(0.7, 0.4))})
	sk._process(1.0 / 30.0)
	await process_frame
	check(not sk._hands.is_empty() and sk._hands.has("right"), "U6：单手注入 → 该侧缓存、另一侧清空")
	win.texture = null
	sk.queue_redraw()
	sk._process(1.0 / 30.0)
	await process_frame
	check(sk._hands.has("right") and (sk._hands["right"] as PackedVector2Array).size() == 21,
		"U6：纹理置空后数据缓存保持（_draw 早退不绘制系 _draw 内分支，走查 u13 实弹覆盖三态）")
	# ---- 段 6. IGNORE（1 check）----
	check_eq(int(sk.mouse_filter), Control.MOUSE_FILTER_IGNORE, "U6：骨架 mouse_filter==IGNORE（CameraWindow 穿透）")
	win.queue_free()
	finish()
