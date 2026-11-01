extends "res://tests/test_base.gd"
## 关卡库审查缺陷修复 TDD 测试（独占文件：autoload/level_library.gd）：
##   P3 validate_level 空集后置——`ts[0].is_empty()` 判在 _filter_voxels 之前，target 全越界
##      被滤空后仍 ok:true；修法=过滤后（全组皆空）再判一次 reject（与 join/final「过滤后为空」口径对齐）；
##   P3 write_user_level 路径穿越+非原子——level_id 只查空串、`../` 可穿越、FileAccess.WRITE
##      直写；修法=id 白名单 `^[A-Za-z0-9_-]+$`（违者 push_warning+return false 零落盘）+
##      tmp+rename 原子序（参考 save_manager.save_game）。
## 纪律：只在沙盒 `user://fixlvl_probe/` 读写；对穿越残留 `user://fixlvl_esc.json` 起测/终测
## 双向清理（红跑遗留幂等）；零触碰 save.json、零入树节点（LevelLibrary.new() 直用+free）。

const LIB_SCRIPT := "res://autoload/level_library.gd"
const PROBE := "user://fixlvl_probe"
const ESC_ID := "../fixlvl_esc"        # 穿越 id（path_join 后逃出探测目录）
const ESC_FILE := "user://fixlvl_esc.json"
const ESC_RAW := "user://fixlvl_probe/../fixlvl_esc.json"
const DOT_ID := "fixlvl.bad"           # 白名单外 id（含 `.`）——旧实现接受并落盘=红测锚
const OK_ID := "fixlvl_ok1"

func _remove_path(p: String) -> void:
	if p.is_empty():
		return
	if DirAccess.dir_exists_absolute(p):
		var d: DirAccess = DirAccess.open(p)
		if d != null:
			d.list_dir_begin()
			var fn: String = d.get_next()
			while fn != "":
				if d.current_is_dir():
					_remove_path(p.path_join(fn))
				else:
					DirAccess.remove_absolute(p.path_join(fn))
				fn = d.get_next()
			d.list_dir_end()
		DirAccess.remove_absolute(p)
	elif FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)

## 合成最小合法关卡档（test_ab_user_levels._mk_level 同款夹具，避免依赖既有夹具内容）。
func _mk_level(ch: int, id: String) -> Dictionary:
	return {
		"format_version": 1,
		"level_id": id,
		"chapter": ch,
		"title": "修复测_%d" % ch,
		"era": "",
		"pieces": [{
			"piece_id": "p1",
			"name": "主体",
			"block_size": {"x": 4, "y": 3, "z": 4},
			"blocks": ["0,0,0", "1,0,0", "2,0,0", "3,0,0", "0,1,0", "1,1,0", "2,1,0", "3,1,0",
				"0,2,0", "1,2,0", "2,2,0", "3,2,0"],
			"target_shapes": [["1,0,1", "2,0,1", "1,1,1", "2,1,1", "1,2,1", "2,2,1"]],
			"join_part": {"size": {"x": 4, "y": 3, "z": 4},
				"voxels": ["1,0,1", "2,0,1", "1,1,1", "2,1,1", "1,2,1", "2,2,1"]},
			"final_answer": {"size": {"x": 4, "y": 3, "z": 4},
				"voxels": ["1,0,0", "2,0,0", "1,1,0", "2,1,0", "1,0,1", "2,0,1",
					"1,1,1", "2,1,1"]},
		}],
	}

func _initialize() -> void:
	print("== test_fix_level_library ==")
	# 红跑遗留幂等清理（穿越残留 + 探测目录）
	_remove_path(ESC_FILE)
	_remove_path(PROBE)
	var lib: Node = (load(LIB_SCRIPT) as GDScript).new()  # 不入树（test_ab 先例）

	# ==================== 段 1：P3 validate_level 空集后置 ====================
	print("-- 段1 P3 validate 空集后置 --")
	var d3: Dictionary = _mk_level(2, "fixlvl_oob")
	var piece3: Dictionary = (d3["pieces"] as Array)[0]
	piece3["target_shapes"] = [["9,9,9"]]  # 全越界（target_size 回落 4,3,4）
	var r3: Dictionary = lib.call("validate_level", d3)
	check(not bool(r3.get("ok", false)),
		"P3-3a：target 全越界被滤空 → reject（红=旧序过滤前判、滤空仍 ok:true；实测 ok=%s reject=%s）" % [
			str(r3.get("ok", false)), str(r3.get("reject", ""))])
	# 反向回归：部分越界（滤后非空）仍接受 + 越界告警
	var d3b: Dictionary = _mk_level(2, "fixlvl_oob2")
	var piece3b: Dictionary = (d3b["pieces"] as Array)[0]
	piece3b["target_shapes"] = [["1,0,0", "9,9,9"]]
	var r3b: Dictionary = lib.call("validate_level", d3b)
	check(bool(r3b.get("ok", false)),
		"P3-3b：部分越界滤后非空仍接受（回归；实测 reject=%s）" % str(r3b.get("reject", "")))
	# 合法档零回归
	var r3c: Dictionary = lib.call("validate_level", _mk_level(3, "fixlvl_valid"))
	check(bool(r3c.get("ok", false)), "P3-3c：合法档 validate 零回归")

	# ==================== 段 2：P3 write_user_level 白名单 + 原子 ====================
	print("-- 段2 P3 write_user_level --")
	# 2a 穿越 id：拒写 + 零落盘
	var ok_esc: bool = bool(lib.call("write_user_level", _mk_level(2, ESC_ID), PROBE))
	check(not ok_esc, "P3-4a：level_id 含 ../ 被拒（红=旧实现仅查空串放行；实测返回 %s）" % str(ok_esc))
	check(not FileAccess.file_exists(ESC_FILE) and not FileAccess.file_exists(ESC_RAW),
		"P3-4a2：穿越 id 零落盘（%s / %s 均不存在）" % [ESC_FILE, ESC_RAW])
	# 2b 白名单外 id（点号）：拒写（确定性红锚——旧实现接受并成功落盘）
	var ok_dot: bool = bool(lib.call("write_user_level", _mk_level(3, DOT_ID), PROBE))
	check(not ok_dot, "P3-4b：白名单外 id（含 .）被拒（红=旧实现返回 true；实测返回 %s）" % str(ok_dot))
	check(not FileAccess.file_exists(PROBE + "/" + DOT_ID + ".json"),
		"P3-4b2：白名单外 id 零落盘")
	# 2c 合法 id：写盘成功 + 无 tmp 残留 + 内容可读回（原子序结果面）
	var ok_ok: bool = bool(lib.call("write_user_level", _mk_level(4, OK_ID), PROBE))
	check(ok_ok, "P3-4c：合法 id（A-Za-z0-9_-）写盘成功（实测 %s）" % str(ok_ok))
	var final_p: String = PROBE + "/" + OK_ID + ".json"
	check(FileAccess.file_exists(final_p), "P3-4c2：目标文件在位")
	check(not FileAccess.file_exists(final_p + ".tmp"), "P3-4c3：tmp 无残留（原子序收口）")
	if FileAccess.file_exists(final_p):
		var back: Variant = JSON.parse_string(FileAccess.get_file_as_string(final_p))
		check(typeof(back) == TYPE_DICTIONARY and String((back as Dictionary).get("level_id", "")) == OK_ID,
			"P3-4c4：读回 JSON level_id 一致（写盘内容完整）")
	# 2d 源锁：write_user_level 体内 tmp+rename 原子序
	var src: String = FileAccess.get_file_as_string(LIB_SCRIPT)
	var body_i: int = src.find("func write_user_level(")
	var next_i: int = src.find("\nfunc ", body_i + 1)
	var body: String = src.substr(body_i, (next_i - body_i) if next_i > body_i else 4000)
	check(body_i >= 0 and body.contains("rename_absolute") and body.contains(".tmp"),
		"P3-4d：源契约 write_user_level 走 tmp+rename 原子序（红=旧 FileAccess.WRITE 直写）")

	# 终清沙盒
	lib.free()
	_remove_path(PROBE)
	_remove_path(ESC_FILE)
	finish()
