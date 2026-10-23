; مثبّت ويندوز (Inno Setup) — ملفٌّ واحد يضع البرنامج وكلّ ملفّاته في مكانه ويصنع اختصاراته.
; سببه: المالك شغّل البرنامج من داخل الـzip فرفض ويندوز تشغيله (file_selector_windows_plugin.dll was
; not found) — ويندوز يستخرج الملفّ التنفيذيّ وحده من الأرشيف. المثبّت لا يترك هذا الخطأ ممكناً.
;
; لكلّ مستخدم بلا صلاحيّات مدير (لا نافذة UAC)، في %LOCALAPPDATA%\Programs — والتحديث تثبيتٌ فوقه
; (AppId ثابتٌ لا يتغيّر أبداً). يُبنى في .github/workflows/windows-build.yml بعد «Package».

#define MyAppName "MyServices Pro"
#define MyAppExe "MyServicesPro.exe"
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef MyAppBuild
  #define MyAppBuild "0"
#endif

[Setup]
AppId={{8F3C2A51-6B7D-4E19-9A0C-3D5E7F1B2C64}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
VersionInfoVersion={#MyAppVersion}.{#MyAppBuild}
AppPublisher=MyServices
AppPublisherURL=https://pro.mysvcs.net
AppSupportURL=https://pro.mysvcs.net
DefaultDirName={localappdata}\Programs\MyServices Pro
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\dist
OutputBaseFilename=MyServicesPro_Setup_{#MyAppVersion}_{#MyAppBuild}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExe}
UninstallDisplayName={#MyAppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExe}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
