; 《千年一榫》Windows 安装包脚本（Inno Setup 7）
; 用法：ISCC.exe 本文件 即可编译出安装包
; 前置：先用 Godot 4.7 执行 --export-release "Windows" 产出 游戏本体 EXE
;       （PCK 已嵌入，单文件，零外部依赖）
; 输出：构建产物\千年一榫_安装包_v0.9.0.4_20261101.exe

#define MyAppName "千年一榫"
#define MyAppVersion "0.9.0.4"
#define MyAppPublisher "千年一榫开发组"
#define MyAppExeName "千年一榫.exe"

[Setup]
AppId={{A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; 允许命令行覆盖权限模式（测试时用 /PRIVILEGESREQUIRED=lowest 免 UAC 静默安装验证）
PrivilegesRequiredOverridesAllowed=commandline
OutputDir=..\..\..\构建产物
OutputBaseFilename=千年一榫_安装包_v{#MyAppVersion}_20261101
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ShowLanguageDialog=no
; 批次 AC（2026-09-27 领域一）：安装程序本体图标 = 真透明多尺寸 app_icon.ico。
; 路径口径：Inno 相对路径以本 .iss 所在目录（tools/）为基准解析，故上跳一级至工程根
; （spec §4.1.3 同款 `..\` 相对写法；ISPP 无 `SourceDir` 变量——经实测
;  `{#SourceDir}` 会「Undeclared identifier」中止编译，故不用 `{#...}` 展开）。
SetupIconFile=..\assets\icons\app_icon.ico
UninstallDisplayIcon={app}\assets\icons\app_icon.ico

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
Source: "..\..\..\构建产物\千年一榫_Windows_EXE\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
; 批次 AC（2026-09-27 领域一）：真透明 .ico 随包落盘 {app}\assets\icons\app_icon.ico
; ——[Icons] 全部快捷方式与 [Setup] UninstallDisplayIcon 的图标源（GDI/shell 可直接读取）。
Source: "..\assets\icons\app_icon.ico"; DestDir: "{app}\assets\icons"; Flags: ignoreversion
; 批次 R 手势运行时（spec §12）：gesture_runtime 代码+模型+嵌入式 Python 落 EXE 旁真实目录
; （PCK 内无法执行子进程，export_presets exclude_filter 已排 gesture_runtime/*；嵌入式 python/ 由
;   D 盘 build_embedded 产物复制到 构建产物\gesture_runtime\ 后一并打包，约 +300MB）
Source: "..\gesture_runtime\*.py"; DestDir: "{app}\gesture_runtime"; Flags: ignoreversion recursesubdirs
Source: "..\gesture_runtime\models\hand_landmarker.task"; DestDir: "{app}\gesture_runtime\models"; Flags: ignoreversion
Source: "..\gesture_runtime\requirements.txt"; DestDir: "{app}\gesture_runtime"; Flags: ignoreversion
Source: "..\..\..\构建产物\千年一榫_Windows_EXE\gesture_runtime\python\*"; DestDir: "{app}\gesture_runtime\python"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; 批次 AC（2026-09-27 领域一）：全部快捷方式显式绑定真透明 .ico——绝不再落回 EXE 自身
; 资源或 python.exe 解释器图标（旧「手势版」快捷方式图标即来自 Filename=python.exe）。
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\assets\icons\app_icon.ico"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"; IconFilename: "{app}\assets\icons\app_icon.ico"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\assets\icons\app_icon.ico"; Tasks: desktopicon
; 2026-09-29 打包小修：桌面「手势版」启动器快捷方式退役（用户 2026-09-29 指示——实测该入口报错，
; 且普通入口已可正常调用摄像头手势：游戏内桥在需要时自动拉起 gesture_runtime/python）。
; 安装时不再创建任何「手势版」快捷方式；launcher.py 随包保留（仅入口退役，文件不删）。
; 历史沿革：批次 R 新增该快捷方式（launcher 先拉起 Python 手势服务再拉起游戏，无摄像头时游戏内自动降级键鼠）；
; 批次 AC 曾为其绑定 app_icon.ico 修图标（旧图标来自 python.exe 解释器）。

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
