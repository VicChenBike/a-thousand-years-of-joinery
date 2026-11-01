@tool
extends EditorPlugin

## Godot MCP Runtime Plugin（plugin.cfg 的 EditorPlugin 入口件）。
## 本体只做一件事：工程加载/卸载时注册/注销 MCPRuntime autoload（mcp_runtime_autoload.gd）。
## 运行时实现（TCP 7777 JSON 行协议、场景树检查、运行时节点/方法操作、截图等）全部在
## mcp_runtime_autoload.gd——本文件不持端口/协议常量与运行时状态（批次 W W5，P3-4e：
## 旧存根态的死常量/死成员与过时传输层描述清理，真端口/协议以 autoload 侧为准）。


func _enter_tree() -> void:
	# Plugin initialization
	print("[MCP Runtime] Plugin loaded")
	add_autoload_singleton("MCPRuntime", "res://addons/godot_mcp_runtime/mcp_runtime_autoload.gd")


func _exit_tree() -> void:
	# Cleanup
	remove_autoload_singleton("MCPRuntime")
	print("[MCP Runtime] Plugin unloaded")
