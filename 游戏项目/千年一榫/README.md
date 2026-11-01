# 千年一榫（游戏本体）

Godot 4.7 工程（gl_compatibility 渲染器）。榫卯文化体验 + 休闲益智游戏《千年一榫》的游戏本体工程。游戏整体介绍、玩法与背景设定见仓库根 [README](../../README.md)。

## 目录说明

- `autoload/` 全局单例：Game（状态机与场景路由）、SaveManager（存档/天赋值/皮肤/关卡进度自动保存）、ThemeManager（深色主题）、AudioManager（BGM 与音频总线）、GestureBridge（手势桥，与 Python 手势进程 UDP 本机通信）、LevelLibrary（关卡数据）、GestureRouter（手势事件路由）；另有编辑器插件运行时 MCPRuntime 自动注册
- `scenes/` 业务场景（主菜单/开场动画/对话/关卡/图鉴/商店/设置等）；`scenes/shared/` 共享 UI 组件（圆角窗口装饰框 `rounded_frame.gd`、悬停提示 `hover_tip.gd`、摄像头手部骨架叠加 `camera_skeleton.gd`、摄像头设备下拉 `settings/camera_menu.gd` 等）
- `scripts/` 玩法逻辑（体素挖除与拾取、对接 48 变换等价判定、评分结算、锐眼差集提示、三视图交互、关卡数据校验等）
- `data/` 静态配置；`themes/` 深色主题（`theme_dark.tres` 单套）
- `fonts/` 开源中文字体（NotoSansSC=UI 默认；马善政书法体=标题）；`audio/` 音频总线布局
- `addons/` 开发辅助插件（GoPeak MCP 三插件，仅开发期使用，游戏运行不依赖）
- `assets/` 素材：背景图、角色立绘与皮肤（常规体系 + 原创皮肤）、音频、3D 模型与点云，以及 `shaders/hover_glow.gdshader`（悬停光晕）、`shaders/ui_material.gdshader`（统一按钮/面板材质）
- `levels_data/` 关卡数据（JSON，5 关，格式契约见 `技术文档/接口规范_关卡数据.md`）
- `剧情对话/` 剧情对话与见证者气泡文案（JSON）
- `gesture_runtime/` 手势识别 Python 运行时（MediaPipe / OpenCV / NumPy，含 One Euro 光标滤波；与游戏经本机 UDP 9876/9877/9878 通信；Godot 导出时排除，由安装包脚本落盘至 EXE 旁）
- `tests/` 无头测试套件（`test_*.gd` 160 余件，`godot --headless --script` 运行）
- `tools/` 离线工具：应用图标生成 `gen_app_icon.py`、点云采样与校验 `point_cloud_sampler.gd` / `check_pointclouds.gd`、UDP 注入模拟器 `udp_simulator.ps1`、Inno Setup 7 安装包脚本 `千年一榫_setup.iss`
- `export_presets.cfg` Windows 导出预设（release 单文件 PCK 嵌入；exclude_filter 排除 `tools/`、`tests/`、`tools_p_shot/`、`gesture_runtime/` 等开发期目录）

## 如何运行

1. 安装 [Godot 4.7](https://godotengine.org/download/archive/)（标准版即可，无需 .NET 版）。
2. 用 Godot 打开本目录的 `project.godot`，按 F5 运行主场景。
3. 键鼠可完整通关；手势交互为可选功能（见下）。

## 手势交互（可选）

手势识别为独立 Python 进程（本目录 `gesture_runtime/`），游戏通过本机 UDP（默认 9876/9877/9878）与之通信：

1. 安装 **Python 3.13**（mediapipe 0.10.x 实证锁定；详见 `gesture_runtime/requirements.txt`）。
2. `pip install -r gesture_runtime/requirements.txt`（MediaPipe / OpenCV / NumPy）。
3. 游戏内「设置 → 手势」开启手势与摄像头；需普通单目摄像头（内置或 USB 均可）。

> 不开摄像头则手势子系统保持待机，不影响键鼠游玩；未检测到摄像头时游戏同样完整可玩，手势相关 UI 置灰。

## 如何测试

```bash
godot --headless --path . --script res://tests/test_main_menu.gd
```

- 把 `test_main_menu.gd` 换成 `tests/test_*.gd` 中任意一个即可运行对应测试；退出码 0 且输出含 `ALL TESTS PASSED`（且无 `SCRIPT ERROR`）为通过。
- 关卡编辑器为独立 Godot 工程，位于仓库根 `关卡编辑器/voxel_level_editor/`，测试同理（`关卡编辑器/voxel_level_editor/tests/`）。
