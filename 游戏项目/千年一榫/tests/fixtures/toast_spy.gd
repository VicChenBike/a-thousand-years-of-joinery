extends Node
## K-C（KC-2）测试夹具：ToastCenter 替身（spy）——记录 push 调用参数供断言
## （Game.attach_toast 注入链路验证，避免测试依赖真实 UI 计时/动画）。
## M-E 回修3 E：签名对齐 ToastCenter.push 新增 centered 可选参（缺省 false 旧用例不受影响）。

var calls: Array = []

func push(text: String, level: String = "warn", seconds: float = 2.5, centered: bool = false) -> void:
	calls.append([text, level, seconds, centered])

func get_calls() -> Array:
	return calls
