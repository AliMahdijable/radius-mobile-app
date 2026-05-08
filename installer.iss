; ════════════════════════════════════════════════════════════════════════
; Inno Setup script — MyServices Desktop installer
; ────────────────────────────────────────────────────────────────────────
; استعمل بعد `flutter build windows --release`. النتيجة installer واحد
; (.exe) ينصّب التطبيق على Windows مع desktop shortcut + uninstaller.
;
; Usage:
;   1) نزّل Inno Setup من https://jrsoftware.org/isinfo.php
;   2) شغّل الـcompiler:
;        & "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer.iss
;   3) يُنتج: installer-out\MyServices-Setup-1.0.0.exe
; ════════════════════════════════════════════════════════════════════════

#define MyAppName "MyServices Desktop"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "MyServices"
#define MyAppExeName "rad_mysvcs.exe"

[Setup]
AppId={{8F2A1B5C-3D4E-4F6A-9B7C-1D8E2F3A4B5C}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\MyServices
DefaultGroupName=MyServices
DisableProgramGroupPage=yes
OutputDir=installer-out
OutputBaseFilename=MyServices-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

; لغة الـinstaller — العربية
ShowLanguageDialog=no
LanguageDetectionMethod=none
RTLEnabled=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; كل محتوى مجلد build كاملاً
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: quicklaunchicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[Code]
// Optional: فحص .NET / VC++ runtime — Flutter لا يحتاج .NET أصلاً.
// تركناها مفتوحة لو احتجت إضافة فحوص لاحقة.
