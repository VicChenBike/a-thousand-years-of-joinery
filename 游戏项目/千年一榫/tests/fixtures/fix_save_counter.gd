extends "res://autoload/save_manager.gd"
## save_game 落盘计数 spy（tests/test_fix_save_buy_skin.gd 专用夹具）：
## 计数后转发 super —— buy_skin/spend_talent 内部的 save_game() 经虚分派命中本覆写，
## 用于断言「购买成功路径恰一次落盘」（P3 两阶段落盘修复的红绿判据）。
## 附 talent_changed/skin_changed 发射计数（setup_probe 显式接线，防 lambda 按值捕获坑）。

var save_calls: int = 0
var talent_emits: int = 0
var skin_emits: int = 0

func save_game() -> bool:
	save_calls += 1
	return super.save_game()

func setup_probe() -> void:
	talent_changed.connect(_on_talent_emit)
	skin_changed.connect(_on_skin_emit)

func _on_talent_emit(_n: int) -> void:
	talent_emits += 1

func _on_skin_emit(_s: String) -> void:
	skin_emits += 1
