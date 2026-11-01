extends "res://tests/test_base.gd"
## K-A（KA-1，spec §三/§4.1）：主题质感断言——圆角/统一方向光影（光源左上，
## 常态/面板阴影统一 (3,5)）/按压反馈 (0,1)/size 6/disabled 无阴影/hover 金色发光兜底/
## 毛玻璃 L1 面板（圆角 16/顶缘边 2px/shadow 16/bg 半透明）。
## 批次 AB-3（深浅主题机制删除）：浅色档断言随功能退役，深色档质感锚定原样保留（值零变化）；
## 「深浅分家」对照断言等价改写为「theme_light.tres 退役 + 深色单源在场」双护栏。

func _initialize() -> void:
	print("== test_theme_k（批次 AB-3：深色唯一真值质感锚定） ==")
	var dark: Theme = load("res://themes/theme_dark.tres")
	check(dark != null, "深色主题可加载")
	# AB-3 退役护栏：浅色主题资源与浅档常量不得复辟
	check(not ResourceLoader.exists("res://themes/theme_light.tres"),
		"AB-3：theme_light.tres 已退役（浅色主题资源删除留痕）")

	for pair: Array in [["深", dark]]:
		var label: String = String(pair[0])
		var th: Theme = pair[1] as Theme

		# Button normal：圆角 12（M-A 暂定值 10→12；M 批等价替换，spec §3.1）+ 统一方向阴影 (3,5)（spec §3.1）
		var nb: StyleBoxFlat = th.get_stylebox("normal", "Button") as StyleBoxFlat
		check(nb != null, "%s色 Button normal 样式存在" % label)
		if nb == null:
			continue
		check_eq(nb.corner_radius_top_left, 12, "M-A：%s色 Button normal 圆角 12（K-A 10→12，M 批等价替换）" % label)
		check_eq(nb.shadow_offset, Vector2(3, 5), "K-A：%s色 Button normal 方向阴影 (3,5)" % label)

		# L-A（L7，spec §5.4）：hover 归一方向影——金色 omni 发光删除（发光全部由材质点光
		# 与光晕层承载，主题不再自带第二套发光）。旧 K-A 金色三条断言由本四条等量+承接。
		var hb: StyleBoxFlat = th.get_stylebox("hover", "Button") as StyleBoxFlat
		check_eq(hb.shadow_offset, Vector2(3, 5), "L-A：%s色 Button hover 方向影 (3,5)" % label)
		check_eq(hb.shadow_size, 8, "L-A：%s色 Button hover 影 size 8（10→8）" % label)
		# 双通道防假防御：浅色旧金 (0.95,0.8,0.32) 的 b=0.32<0.4 可绕过单 b 阈值，
		# r>0.9 正是旧金特征 → 归黑判定必须 r<0.4 与 b<0.4 并查。
		check(hb.shadow_color.r < 0.4 and hb.shadow_color.b < 0.4,
			"L-A：%s色 Button hover 无金色发光（r<0.4 且 b<0.4，防浅色 b<0.4 假防御）" % label)
		check(absf(hb.shadow_color.a - 0.35) < 0.01, "L-A：%s色 Button hover 影 alpha 归一 0.35" % label)

		# Button pressed：按压贴合（spec §3.1）——offset (0,1)、size 6
		var pb: StyleBoxFlat = th.get_stylebox("pressed", "Button") as StyleBoxFlat
		check_eq(pb.shadow_offset, Vector2(0, 1), "K-A：%s色 Button pressed 按压 offset (0,1)" % label)
		check_eq(pb.shadow_size, 6, "K-A：%s色 Button pressed 按压 size 6" % label)

		# Button disabled：无投影（spec §3.3 disabled 行）+ M-A 禁用态收敛新档（spec §4.1）
		var db: StyleBoxFlat = th.get_stylebox("disabled", "Button") as StyleBoxFlat
		check_eq(db.shadow_size, 0, "K-A：%s色 Button disabled 无阴影" % label)
		# M-A 回修（用户验收反馈）：常态字色口径——浅色深棕常显；深色 N12 反转留痕：
		# M-A 深墨棕 (0.102,0.071,0.031) 在 N5 按钮底调深棕 (0.38,0.27,0.10) 后深字贴深底撞色
		# （用户 2026-09-10「按钮上的字本来就是黑的，现在字撞了看不清」）→ 深色字改米黄浅金浅字。
		var nc: Color = th.get_color("font_color", "Button")
		if label == "深":
			check(absf(nc.r - 0.96) < 0.003 and absf(nc.g - 0.90) < 0.003 and absf(nc.b - 0.78) < 0.003,
				"N12：深色 Button 常态字色=米黄浅金 (0.96,0.90,0.78)（M-A 深墨棕 0.102/0.071/0.031 与 N5 深棕底撞色，N12 反转留痕）")
		else:
			check(absf(nc.r - 0.227) < 0.003 and absf(nc.g - 0.165) < 0.003 and absf(nc.b - 0.063) < 0.003,
				"M-A 回修：浅色 Button 常态字色=深棕 (0.227,0.165,0.063)（原 0.353 系提档）")
		var d_fc: Color = th.get_color("font_disabled_color", "Button")
		if label == "深":
			check(absf(d_fc.r - 0.96) < 0.003 and absf(d_fc.g - 0.90) < 0.003 and absf(d_fc.b - 0.78) < 0.003 and absf(d_fc.a - 0.80) < 0.01,
				"N12：深色 font_disabled_color=米黄浅金 α0.80（M-A 深墨棕 α0.80 档随字色方案反转，仅 rgb 换档 α 不变）")
			check(absf(db.bg_color.a - 0.45) < 0.01, "M-A：深色禁用底 α0.45（金 α0.3→0.45）")
		else:
			check(absf(d_fc.r - 0.227) < 0.003 and absf(d_fc.g - 0.165) < 0.003 and absf(d_fc.b - 0.063) < 0.003 and absf(d_fc.a - 0.60) < 0.01,
				"M-A：浅色 font_disabled_color=深棕 α0.60（spec §4.1 新档）")
			check(absf(db.bg_color.a - 0.40) < 0.01, "M-A：浅色禁用底 α0.40（金 α0.3→0.40）")
		# N12（2026-09-10 用户反馈「深底深字撞色」）防串档：字色与底色明度方向必须正确——
		# 深色主题=浅字压深底（字明度 > normal 底明度）、浅色主题=深字压浅底（字明度 < normal 底明度）。
		# Rec.601 加权明度（与 shader lum_w 同系数口径，参照 test_light_material N5 分档先例）。
		var _lum := func(c: Color) -> float: return c.r * 0.299 + c.g * 0.587 + c.b * 0.114
		check(_lum.call(nc) > _lum.call(nb.bg_color) if label == "深" else _lum.call(nc) < _lum.call(nb.bg_color),
			"N12：%s色 Button 字色与 normal 底明度方向正确（深色浅字/浅色深字，撞色防回归）" % label)

		# L1 页面板（spec §3.3）：Panel 与 PanelContainer 同款——bg 半透明 (0.4,0.7)、
		# 顶缘高光边 2px、圆角 16（面板档）、shadow 16
		for node_type: String in ["Panel", "PanelContainer"]:
			var sp: StyleBoxFlat = th.get_stylebox("panel", node_type) as StyleBoxFlat
			check(sp != null, "%s色 %s panel 样式存在" % [label, node_type])
			if sp == null:
				continue
			check(sp.bg_color.a > 0.4 and sp.bg_color.a < 0.7,
				"K-A：%s色 %s 毛玻璃底 alpha∈(0.4,0.7)" % [label, node_type])
			check_eq(sp.border_width_top, 2, "K-A：%s色 %s 顶缘高光边 2px" % [label, node_type])
			check_eq(sp.corner_radius_top_left, 16, "K-A：%s色 %s 圆角 16" % [label, node_type])
			check_eq(sp.shadow_size, 16, "K-A：%s色 %s 面板柔投影 16" % [label, node_type])

	# K-A「深浅 L1 底色分家」断言随批次 AB-3 浅色主题删除退役——等价改写：
	# 深色 L1 面板底色具体值锚定（旧深档值零变化）+ 主题资源单一性。
	var d_bg: Color = (dark.get_stylebox("panel", "Panel") as StyleBoxFlat).bg_color
	check(absf(d_bg.r - 0.176) < 0.004 and absf(d_bg.g - 0.125) < 0.004 and absf(d_bg.b - 0.047) < 0.004 		and absf(d_bg.a - 0.55) < 0.01,
		"AB-3 等价改写：深色 L1 面板底色==深棕 (0.176,0.125,0.047) α0.55（旧深档值逐一未变，实际 %s）" % str(d_bg))
	check_eq(dark.resource_path, "res://themes/theme_dark.tres",
		"AB-3：深色主题为唯一主题资源（单一真值）")
	finish()
