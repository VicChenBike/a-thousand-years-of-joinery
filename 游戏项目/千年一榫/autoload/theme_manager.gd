extends Node
## ThemeManager：全局深色主题唯一提供者。
## 批次 AB-3（用户拍板 2026-09-25）：**深浅色主题机制彻底删除**——浅色调色板（theme_light.tres）、
## 主题切换 API（refresh/force_dark）、theme_changed 信号、「跟随系统深浅色」1s 轮询
## （DisplayServer.is_dark_mode 探测）全部退役；深色为全局唯一观感，本 autoload 退化为
## 「深色 Theme 单一提供者」（current_theme/apply_theme 两方法保留，消费点零改动）。
## 历史（留痕）：原为跟随 Windows 系统深浅色（批次 W P1-4 加 1.0s Timer 轮询激活），
## 随本批「全局固定深色」拍板一并删除（test_theme 深色唯一真值护栏锁定）。

const DARK_THEME_PATH := "res://themes/theme_dark.tres"

var _dark_theme: Theme

func _ready() -> void:
	_dark_theme = load(DARK_THEME_PATH)

func current_theme() -> Theme:
	return _dark_theme

func apply_theme(root: Control) -> void:
	root.theme = current_theme()
