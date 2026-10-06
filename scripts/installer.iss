; Windows installer of AvtoSmart Avtodrom (Inno Setup 6).
;
;   python scripts/build.py --installer      (exports the game, then runs ISCC)
;   ISCC scripts/installer.iss               (from an existing export/windows)
;
; Installs per user by default (no administrator rights needed; "for all
; users" is offered), adds Start-menu and optional desktop shortcuts and an
; uninstaller. The game keeps its data (settings, exam history) in
; %APPDATA%\Godot\app_userdata\Avtodrom, which the uninstaller leaves alone.

#ifndef AppVersion
  #define AppVersion "1.1.0"
#endif

[Setup]
AppId={{6A1F3E52-8C4B-4D2A-9E7F-3B5C1D2E4F60}
AppName=AvtoSmart Avtodrom
AppVersion={#AppVersion}
AppVerName=AvtoSmart Avtodrom {#AppVersion}
AppPublisher=AvtoSmart
AppPublisherURL=https://avtotestu.uz
AppSupportURL=https://avtotestu.uz
AppUpdatesURL=https://avtotestu.uz
AppCopyright=© 2026 AvtoSmart
VersionInfoVersion={#AppVersion}.0
VersionInfoProductName=AvtoSmart Avtodrom
VersionInfoDescription=AvtoSmart Avtodrom — haydovchilik amaliy imtihoni simulyatori
DefaultDirName={autopf}\AvtoSmart Avtodrom
DefaultGroupName=AvtoSmart Avtodrom
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\Avtodrom.exe
UninstallDisplayName=AvtoSmart Avtodrom
OutputDir=..\export\installer
OutputBaseFilename=AvtoSmart-Avtodrom-Setup-{#AppVersion}
SetupIconFile=..\brand\windows\avtodrom.ico
WizardStyle=modern
WizardImageFile=..\brand\installer\wizard.bmp
WizardSmallImageFile=..\brand\installer\wizard_small.bmp
Compression=lzma2/ultra64
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\export\windows\Avtodrom.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\export\windows\libavtodrom.windows.template_release.x86_64.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\AvtoSmart Avtodrom"; Filename: "{app}\Avtodrom.exe"
Name: "{autodesktop}\AvtoSmart Avtodrom"; Filename: "{app}\Avtodrom.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Avtodrom.exe"; Description: "{cm:LaunchProgram,AvtoSmart Avtodrom}"; Flags: nowait postinstall skipifsilent
