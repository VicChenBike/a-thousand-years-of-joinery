# 第三方素材与组件声明（Third-Party Notices）

> 本仓库主许可为 [MIT](./LICENSE)。下表为仓库中随源码分发的第三方素材与组件清单，各项均按其**自身的开源许可证**分发，与主许可相互独立。
> **许可证全文随仓库附带于 [`licenses/`](./licenses/) 目录**（`Apache-2.0.txt`、`MIT_Godot.txt`、`OFL-1.1_MaShanZheng.txt`、`OFL-1.1_NotoSansSC.txt`，均取自权利人官方原文）。
> 本文件仅作汇总提示，各许可证的完整文本与最新条款以权利人**官方发布为准**；文中版本号均取自仓库内实际锁定的文件（如 `requirements.txt`、`project.godot`），未另行推算。
> 文中路径均为仓库内相对路径。

## 一、游戏引擎

| 组件 | 路径 | 来源 | 许可证 | 备注 |
|---|---|---|---|---|
| Godot 引擎 4.7 | 不随仓库分发（两个工程 `project.godot` 的 `config/features` 均标注 `4.7` + `GL Compatibility`） | Godot Engine（godotengine.org） | MIT（全文：`licenses/MIT_Godot.txt`） | 开源游戏引擎；编译运行与导出需自行从官方渠道获取对应版本及导出模板 |

## 二、字体

| 组件 | 路径 | 来源 | 许可证 | 备注 |
|---|---|---|---|---|
| Noto Sans SC（可变字体，文件 `NotoSansSC[wght].ttf`） | `游戏项目/千年一榫/fonts/`；`关卡编辑器/voxel_level_editor/fonts/` | Google Noto Fonts（notofonts.github.io，亦发布于 Google Fonts） | SIL Open Font License 1.1 | 简体中文黑体家族；用于界面正文与 UI 文本 |
| Ma Shan Zheng（楷书风格中文字体，文件 `MaShanZheng-Regular.ttf`） | `游戏项目/千年一榫/fonts/`；`关卡编辑器/voxel_level_editor/fonts/` | Google Fonts（fonts.google.com） | SIL Open Font License 1.1 | 书法楷体；用于标题与书法风格文本 |

### 字体许可要点（OFL 1.1）

- OFL 1.1 允许在遵守条款的前提下自由使用、嵌入、修改与再分发字体（含商业用途）；
- 再分发字体（原始版或修改版）时，**须随附 OFL 1.1 许可证全文与相应版权声明**；
- 部分字体设有保留字体名（Reserved Font Name）条款：修改后的版本不得沿用原字体名，具体以许可证原文为准；
- 字体不得作为独立商品单独出售（作为更大软件的组成部分捆绑分发不受此限）；
- 本仓库已随附 OFL 1.1 许可证全文（与各字体官方仓库逐字一致）：`licenses/OFL-1.1_NotoSansSC.txt`、`licenses/OFL-1.1_MaShanZheng.txt`——满足 OFL 第 2) 条「再分发须附带上述版权声明与本许可证」的要求。

## 三、手势识别：模型与 Python 依赖

手部关键点检测由独立的 Python 子进程承担，其依赖经 `gesture_runtime/requirements.txt` 精确锁版；预训练模型随仓库分发。

| 组件 | 路径 | 来源 | 许可证 | 备注 |
|---|---|---|---|---|
| MediaPipe Hand Landmarker 预训练模型（`hand_landmarker.task`） | `游戏项目/千年一榫/gesture_runtime/models/` | Google MediaPipe（developers.google.com/mediapipe，模型发布见其官方仓库/文档页） | Apache-2.0（以官方仓库为准） | 手部 21 关键点检测模型，`.task` 打包格式 |
| mediapipe（`requirements.txt` 锁定 `==0.10.35`） | `游戏项目/千年一榫/gesture_runtime/requirements.txt` | PyPI：pypi.org/project/mediapipe | Apache-2.0 | 手部关键点检测推理框架 |
| opencv-python-headless（同上，`==5.0.0.93`） | 同上 | PyPI：pypi.org/project/opencv-python-headless | Apache-2.0 | OpenCV 无 GUI 变体，用于摄像头采集与图像处理 |
| numpy（同上，`==2.5.1`） | 同上 | PyPI：pypi.org/project/numpy | BSD-3-Clause | 数值计算基础库 |
| CPython 解释器 3.13 系 | 不随本 git 仓库分发（打包产物内嵌） | Python 软件基金会（python.org） | PSF-2.0 | 嵌入式运行时仅存在于安装包/便携包形态，源码仓库不含 |

补充说明：

- **Apache-2.0 全文**随仓库附带于 `licenses/Apache-2.0.txt`（官方原文，www.apache.org/licenses/LICENSE-2.0.txt）——覆盖 MediaPipe 模型与 mediapipe/opencv-python 依赖；
- **numpy（BSD-3-Clause）**：其完整许可证文本随 pip 分发包内附（安装后位于 `site-packages/numpy-2.5.1.dist-info/licenses/LICENSE.txt`（PEP 639 形态，以 dist-info 为准）），本仓库以 pip 依赖方式引用、不以源码形态再分发该库；
- `gesture_runtime/one_euro_filter.py` 中的 One Euro Filter 算法由 CHI 2012 论文提出；该文件为**按论文公式自行实现**，未复制任何第三方代码，在此仅作学术致谢，不计入第三方组件。
- 上述 Python 依赖仅在手势识别子进程中使用，游戏引擎侧通过本地 UDP 通信与其交互。

## 四、开发辅助插件（addons）

以下插件为**开发辅助插件，随源码分发**：仅服务于开发期的人工智能辅助工作流（基于 Model Context Protocol 的编辑器/运行时桥接与外部修改自动重载），**游戏本体运行不依赖它们**。作者与版本信息见各插件目录内的 `plugin.cfg`；许可证以随附文件及上游官方仓库为准。

| 组件 | 路径 | 来源 | 许可证 | 备注 |
|---|---|---|---|---|
| Godot MCP Auto Reload（`auto_reload`） | `游戏项目/千年一榫/addons/auto_reload/`；`关卡编辑器/voxel_level_editor/addons/auto_reload/` | Godot MCP 开发工具链（作者信息见 `plugin.cfg`） | 以随附文件及上游官方仓库为准 | 外部修改后自动重载场景/脚本 |
| Godot MCP Editor（`godot_mcp_editor`） | `游戏项目/千年一榫/addons/godot_mcp_editor/`；`关卡编辑器/voxel_level_editor/addons/godot_mcp_editor/` | 同上 | 同上 | 编辑器内场景/资源操作的 MCP 桥接 |
| Godot MCP Runtime（`godot_mcp_runtime`） | `游戏项目/千年一榫/addons/godot_mcp_runtime/`；`关卡编辑器/voxel_level_editor/addons/godot_mcp_runtime/` | 同上 | 同上 | 运行时通信桥接（场景检查/属性修改/方法调用） |

> 注：MCP 即 Model Context Protocol。如需在生产构建中排除上述插件，可在导出预设的过滤规则中排除 `addons/`。

## 五、项目自有素材

`游戏项目/千年一榫/assets/` 下的全部背景图、三维模型、动画视频、角色立绘、皮肤、BGM、图标、着色器，以及关卡数据、全部对话与文案、界面设计等，均为**本项目自有原创素材**（部分由 AI 辅助生成），随本仓库主许可（MIT）分发，不属于第三方内容。

---

## 善意条款

本仓库力求完整、准确地标注上述组件的来源与许可信息，如有疏漏纯属无意。若您是某素材或组件的权利人，认为本仓库对其作品的使用方式侵害了您的权益，请通过本仓库的 Issue 功能与我们联系，并附上可证明权利归属的材料；我们将在核实后及时妥善处理，包括但不限于补充声明、替换素材或移除相关内容。
