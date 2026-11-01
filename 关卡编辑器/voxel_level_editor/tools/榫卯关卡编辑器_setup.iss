; 《榫卯关卡编辑器》Windows 安装包脚本（Inno Setup 7）
; 用法：ISCC.exe 本文件 即可编译出安装包
; 前置：先用 Godot 4.7 执行 --export-release "Windows" 产出 编辑器 EXE
;       （PCK 已嵌入，单文件，零外部依赖）
; 输出：构建产物\关卡编辑器打包_20260913\榫卯关卡编辑器_安装包_v1.0.0_20260913.exe
; 注意：本包为临时打包（编辑器仍在迭代中，不代表开发完结）；
;       与《千年一榫》游戏本体安装包 AppId 不同，互不影响。

#define MyAppName "榫卯关卡编辑器"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "千年一榫开发组"
#define MyAppExeName "榫卯关卡编辑器.exe"

[Setup]
AppId={{92636DBB-B694-4473-ADA3-A13FE499109F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
; 允许命令行覆盖权限模式（如需测试可用 /PRIVILEGESREQUIRED=lowest 免 UAC）
PrivilegesRequiredOverridesAllowed=commandline
OutputDir=..\..\..\构建产物\关卡编辑器打包_20260913
OutputBaseFilename=榫卯关卡编辑器_安装包_v{#MyAppVersion}_20260913
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ShowLanguageDialog=no
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
Source: "..\..\..\构建产物\关卡编辑器打包_20260913\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppName}"
Name: "{group}\卸载 {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
