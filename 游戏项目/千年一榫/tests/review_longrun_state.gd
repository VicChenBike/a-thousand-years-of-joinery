extends "res://tests/test_base.gd"
## 批次 AA 终审（review 专用，不入回归分母）：方向1a 状态机长跑量化。
## 循环 120 轮真实场景迁移（TALK↔CATALOG↔SETTLE↔MAIN_MENU + 少量 LEVEL），
## 前后对比：返回栈深度、settle_snapshot、Game/Router 信号连接数、root 节点数、
## Engine 对象数。存档四件组备份-还原（规范同 test_aa_nav_return）。

const SAVE_PATH := "user://save.json"
const FLAG_PATH := "user://first_launch.flag"
const TMP_PATH := "user://save.json.tmp"
const BAK_PATH := "user://save.json.bak"
const BK_PREFIX := "user://_review_lr_backup_"
const WATCHED: Array = [SAVE_PATH, FLAG_PATH, TMP_PATH, BAK_PATH]

const ST_MAIN_MENU := 1
const ST_TALK := 3
const ST_LEVEL := 4
const ST_SETTLE := 5
const ST_CATALOG := 6

var _bk_made := {}

func _backup_user() -> void:
	for p: String in WATCHED:
		var abs_p := ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs_p):
			var bk := ProjectSettings.globalize_path(BK_PREFIX + p.get_file())
			DirAccess.copy_absolute(abs_p, bk)
			_bk_made[p] = true

func _restore_user() -> void:
	for p: String in WATCHED:
		var abs_p := ProjectSettings.globalize_path(p)
		if FileAccess.file_exists(abs_p):
			DirAccess.remove_absolute(abs_p)
		var bk := ProjectSettings.globalize_path(BK_PREFIX + p.get_file())
		if _bk_made.has(p) and FileAccess.file_exists(bk):
			DirAccess.copy_absolute(bk, abs_p)
			DirAccess.remove_absolute(bk)

func _snapshot_counts() -> Dictionary:
	var router: Node = get_root().get_node_or_null("GestureRouter")
	var game: Node = get_root().get_node_or_null("Game")
	return {
		"root_children": root.get_child_count(),
		"game_conns": game.get_incoming_connections().size() if game != null else -1,
		"router_conns": router.get_incoming_connections().size() if router != null else -1,
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"max_depth_seen": 0,
	}

func _initialize() -> void:
	await process_frame
	await process_frame
	_backup_user()
	var game: Node = get_root().get_node("Game")
	check(game != null, "前置：/root/Game 在位")
	if game == null:
		finish()
		return
	var container := Control.new()
	container.name = "ReviewSceneContainer"
	var overlay_layer := CanvasLayer.new()
	overlay_layer.name = "ReviewOverlayLayer"
	root.add_child(container)
	root.add_child(overlay_layer)
	game.call("attach", container, overlay_layer)
	game.call("clear_catalog_return")
	game.call("goto_state", ST_MAIN_MENU, {})

	var before := _snapshot_counts()
	var max_depth_seen: int = int(before["max_depth_seen"])
	var depth_violations := 0
	var rounds := 120
	var saved_conns := game.get_signal_connection_list("state_changed").size()

	for i: int in rounds:
		game.call("goto_state", ST_TALK, {"chapter": 1})
		game.call("goto_state", ST_CATALOG, {})
		max_depth_seen = maxi(max_depth_seen, int(game.call("catalog_return_depth")))
		if int(game.call("catalog_return_depth")) > 8:
			depth_violations += 1
		# 图鉴退出 = 出栈回 TALK（直接驱动出栈口 + 回跳，等价 catalog_scene._on_exit_pressed 路由）
		var popped: Dictionary = game.call("pop_catalog_return")
		if popped.is_empty():
			check(false, "第 %d 轮：栈空（应有 TALK 条目）" % i)
			break
		game.call("goto_state", ST_SETTLE, {})
		# 伪造结算快照 → 验证入栈合并 + 离开清空生命周期
		game.set("settle_snapshot", {"chapter": 9, "score": 123})
		game.call("goto_state", ST_CATALOG, {})
		max_depth_seen = maxi(max_depth_seen, int(game.call("catalog_return_depth")))
		if int(game.call("catalog_return_depth")) > 8:
			depth_violations += 1
		game.call("pop_catalog_return")
		game.call("goto_state", ST_MAIN_MENU, {})
		if not (game.get("settle_snapshot") as Dictionary).is_empty():
			check(false, "第 %d 轮：回主菜单后 settle_snapshot 残留" % i)
			break
	check(depth_violations == 0, "栈深全程 ≤8（越限次数=%d，峰值=%d）" % [depth_violations, max_depth_seen])
	check_eq(int(game.call("catalog_return_depth")), 0, "120 轮后栈空（回主菜单清栈）")

	# LEVEL 换场景 10 次重载（重活场景 churn）
	var ok_level := true
	for i: int in 10:
		game.call("goto_state", ST_LEVEL, {"chapter": (i % 5) + 1})
		game.call("goto_state", ST_MAIN_MENU, {})
		if int(game.current_state()) != ST_MAIN_MENU:
			ok_level = false
			break
	check(ok_level, "10 次 LEVEL↔MAIN_MENU 重载往返状态机正确")

	# flush 待删场景（queue_free 延迟至帧尾）——先冲一次帧再取基线
	await process_frame
	await process_frame
	await process_frame
	var after := _snapshot_counts()
	var conns_after := game.get_signal_connection_list("state_changed").size()
	print("[LR] before=%s" % str(before))
	print("[LR] after =%s" % str(after))
	check_eq(conns_after, saved_conns, "Game.state_changed 入连接数不增长（%d→%d）" % [saved_conns, conns_after])
	var orphans_delta: int = int(after["orphans"]) - int(before["orphans"])
	var nodes_delta: int = int(after["nodes"]) - int(before["nodes"])
	print("[LR] nodes_delta=%d orphans_delta=%d objects_delta=%d" % [nodes_delta, orphans_delta,
		int(after["objects"]) - int(before["objects"])])
	check(orphans_delta <= 20, "孤儿节点增长受控（Δ=%d，阈值 20）" % orphans_delta)
	check(nodes_delta <= 60, "存活节点增长受控（Δ=%d，阈值 60）" % nodes_delta)

	# 第二轮 burst（10 轮轻迁移 + flush）——量化「无累积泄漏」：两轮 flush 后差值应≈0
	var burst_before := _snapshot_counts()
	for i: int in 10:
		game.call("goto_state", ST_TALK, {"chapter": 1})
		game.call("goto_state", ST_CATALOG, {})
		game.call("pop_catalog_return")
		game.call("goto_state", ST_MAIN_MENU, {})
	await process_frame
	await process_frame
	await process_frame
	var burst_after := _snapshot_counts()
	print("[LR] burst nodes_delta=%d orphans_delta=%d objects_delta=%d" % [
		int(burst_after["nodes"]) - int(burst_before["nodes"]),
		int(burst_after["orphans"]) - int(burst_before["orphans"]),
		int(burst_after["objects"]) - int(burst_before["objects"])])
	check(int(burst_after["orphans"]) - int(burst_before["orphans"]) <= 5,
		"第二轮 burst 孤儿零累积（Δ=%d）" % (int(burst_after["orphans"]) - int(burst_before["orphans"])))
	check(int(burst_after["nodes"]) - int(burst_before["nodes"]) <= 60,
		"第二轮 burst 存活节点零累积（Δ=%d）" % (int(burst_after["nodes"]) - int(burst_before["nodes"])))

	_restore_user()
	finish()
