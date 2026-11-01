extends "res://tests/test_base.gd"
## 修复批红测 1（P2，UI 域）：TopStrip info 条跨状态不重算偏移。
## 病灶：top_strip.gd `_on_game_state_changed` 对非 confirm 模式早退（:353-356），
## info 的 offset 只在 _show/_play_slide_in（push 时）与 overlay_changed 重算——
## LEVEL 期 info（offset 6）存活期（≤4s）内跳主菜单 → 条停 y=6 压窗口三钮（STOP 吞点击）。
## 红断言：LEVEL push info（滑入动效走完）→ emit state_changed(LEVEL→MAIN_MENU) → offset_top 应=70（改前停 6）。
## 负例：info 不被跨态收起（既有语义：info 自有计时自灭，保持）。
## 零写档：仅直写 Game._state + 手动 emit_signal（不走 goto_state 零场景切换）。
## 几何读数纪律：滑入 tween 0.25s 会经 position→offset 联动改写 offset_top——
## 每次 offset 断言前 await 0.5s 走完动效（test_w_topstrip_level 同款先行纪律）。

const TS_SCRIPT := "res://scenes/shared/top_strip.gd"
const STATE_BOOT := 0
const STATE_MAIN_MENU := 1
const STATE_LEVEL := 4
const LEVEL_TOP := 6.0
const REST_TOP := 70.0

func _initialize() -> void:
	print("== test_fix_ui_topstrip_offset ==")
	await process_frame
	var game: Node = root.get_node("Game")
	check(game != null, "前置：Game autoload 在位")
	if game == null:
		finish()
		return
	# LEVEL 态推 info → 贴边 6（既有 per-state 偏移，前置锚）
	game.set("_state", STATE_LEVEL)
	var strip: Node = (load(TS_SCRIPT) as GDScript).new()
	add_child(strip)
	await process_frame
	await process_frame
	strip.call("push_info", "关卡内提示条")
	await create_timer(0.6).timeout   # 滑入动效 0.25s 走完（tween 经 position 联动 offset，先收敛）
	check_eq(float(strip.get("offset_top")), LEVEL_TOP,
		"前置：LEVEL 态 info 条 offset_top=6（既有贴边语义）")
	check_eq(bool(strip.get("visible")), true, "前置：info 条在场")
	# 跨态：LEVEL → MAIN_MENU（info 存活期内手动 emit state_changed，模拟真实场景切换信号）
	game.set("_state", STATE_MAIN_MENU)
	game.emit_signal("state_changed", STATE_LEVEL, STATE_MAIN_MENU)
	check_eq(float(strip.get("offset_top")), REST_TOP,
		"P2 红测：state_changed 后存活 info 条 offset 重算为主菜单 70（改前停 6 压窗口三钮）")
	check_eq(bool(strip.get("visible")), true,
		"负例保持：info 条不被跨态收起（info 自有计时自灭语义零变化）")
	# 再推一条 info（新状态 push 路径）仍走 70（防回归改坏 _show 内重算）
	strip.call("push_info", "主菜单提示条")
	await create_timer(0.6).timeout
	check_eq(float(strip.get("offset_top")), REST_TOP, "主菜单态 push_info → offset=70 不回归")
	strip.free()
	game.set("_state", STATE_BOOT)
	finish()
