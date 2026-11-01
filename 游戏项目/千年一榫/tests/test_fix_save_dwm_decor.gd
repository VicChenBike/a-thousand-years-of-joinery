extends "res://tests/test_base.gd"
## 修复批（存档与系统域）P2-②：DWM 装饰态轮询只活 15s——TDD 红测先行。
## 病灶（独立审查确认）：main.gd _poll_dwm_flag_async（:526-548）把「等 dwm_round.flag」与
## 「装饰态刷新」耦合在同一循环：15s 超时（DWM_FLAG_WAIT_SEC）循环结束、或 flag 命中即
## return → _decoration_force_hidden 不再刷新 → 运行 >15s 后 Aero Snap 最大化（无边框
## get_mode 恒报 WINDOWED，K-H 实证）下拖窗门/16:9 门半失效（WindowManager.drag_gate_closed
## 第三通道读的就是 _decoration_force_hidden）。
## 修法：拆分——等 flag 最多 15s（命中即 break 收束等待段），装饰态刷新抽出
## _refresh_decoration_state 并改持续慢轮询（DWM_DECOR_POLL_SEC，1~2s 永久，低频无 CPU 压力）。
## 判定口径：
##   S1 结构：_refresh_decoration_state 存在且轮询体调用之（可被测试直调）；
##   S2 结构：轮询体两段 while（flag 等待段 + 持续装饰段），flag 命中用 break（红态=return）；
##   S3 常量：DWM_DECOR_POLL_SEC 存在且 0<x≤2.0；DWM_FLAG_WAIT_SEC 仍 15.0（等 flag 上限不变）；
##   S4 动态：不入树实例化 main.tscn（_ready 不触发、零手势子进程零摄像头），直调
##     _refresh_decoration_state——window_buttons._maxed 翻转 → RoundedFrame.
##     _decoration_force_hidden 跟随翻转（状态机断言）。注记：DisplayServer 真窗口 mode
##     通道（Snap 最大化真实上报）无头桩不到 → **窗口态需真机复验**（结构+状态机已锁）。

const MAIN_SCENE := "res://scenes/main.tscn"
const MAIN_GD := "res://scenes/main.gd"

func _poll_body(src: String) -> String:
	## 提取 _poll_dwm_flag_async 函数体（到下一个 func 声明或文件尾）
	var i: int = src.find("func _poll_dwm_flag_async")
	if i < 0:
		return ""
	var j: int = src.find("\nfunc ", i + 1)
	if j > 0:
		return src.substr(i, j - i)
	return src.substr(i)

func _initialize() -> void:
	print("== test_fix_save_dwm_decor ==")
	var src: String = FileAccess.get_file_as_string(MAIN_GD)
	var body: String = _poll_body(src)

	# ===== S1 结构：刷新函数抽出 =====
	check(src.contains("func _refresh_decoration_state"), "S1a _refresh_decoration_state 独立函数存在（轮询可直调断言）")
	check(body.length() > 0, "S1b _poll_dwm_flag_async 函数体可定位")
	check(body.contains("_refresh_decoration_state"), "S1c 轮询体调用刷新函数（两段共用单点）")

	# ===== S2 结构：等 flag 与装饰刷新拆分 =====
	check(body.count("while") >= 2, "S2a 轮询体两段 while（flag 等待段 + 持续装饰刷新段；红态=1 段耦合）")
	check(body.contains("break"), "S2b flag 命中以 break 收束等待段（红态=return 终止装饰刷新）")

	# ===== S3 常量 =====
	var mgd: GDScript = load(MAIN_GD)
	check(mgd != null, "S3a main.gd 脚本可加载")
	if mgd != null:
		var cmap: Dictionary = mgd.get_script_constant_map()
		check(cmap.has("DWM_DECOR_POLL_SEC"), "S3b DWM_DECOR_POLL_SEC 持续慢轮询常量存在（红态缺失）")
		if cmap.has("DWM_DECOR_POLL_SEC"):
			var dp: float = float(cmap["DWM_DECOR_POLL_SEC"])
			check(dp > 0.0 and dp <= 2.0, "S3c 慢轮询间隔 0<x≤2s（防高频 CPU）")
		check_eq(float(cmap.get("DWM_FLAG_WAIT_SEC", -1.0)), 15.0, "S3d 等 flag 上限 15s 不变（只约束等 flag）")

	# ===== S4 动态：不入树实例直调刷新，断言状态翻转 =====
	var mi: Node = (load(MAIN_SCENE) as PackedScene).instantiate()  # 不入树，_ready 不触发
	check(mi != null, "S4a main.tscn 可实例化（不入树）")
	if mi != null:
		check(mi.has_method("_refresh_decoration_state"), "S4b 实例可调 _refresh_decoration_state（红态=无此方法）")
		if mi.has_method("_refresh_decoration_state"):
			var rf: Node = mi.get_node_or_null("RoundedFrame")
			var wb: Node = mi.get_node_or_null("GlobalUI/WindowButtons")
			check(rf != null and wb != null, "S4c 夹具节点在场（RoundedFrame/WindowButtons）")
			if rf != null and wb != null:
				# mode 通道真值先取（headless 桩无关化：断言对齐「_maxed 或 mode 隐藏」综合判定）
				var mode_hidden: bool = bool(rf.call("window_decoration_hidden",
					DisplayServer.window_get_mode()))
				wb.set("_maxed", false)
				mi.call("_refresh_decoration_state")
				check_eq(bool(rf.get("_decoration_force_hidden")), mode_hidden,
					"S4d _maxed=false → flag=mode 通道综合真值（直调刷新可断言）")
				wb.set("_maxed", true)
				mi.call("_refresh_decoration_state")
				check_eq(bool(rf.get("_decoration_force_hidden")), true,
					"S4e _maxed=true → 装饰隐藏（状态翻转断言——Aero Snap 收敛的真值源）")
				wb.set("_maxed", false)
				mi.call("_refresh_decoration_state")
				check_eq(bool(rf.get("_decoration_force_hidden")), mode_hidden,
					"S4f 复位回综合真值不粘死")
		mi.free()
	print("EVID|dwm_decor|fixs|done")  # 窗口态（真 Snap 最大化 mode 通道）需真机复验——结构+状态机已锁
	finish()
