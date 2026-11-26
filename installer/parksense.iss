; PARKSENSE — Windows kurulum sihirbazı (Inno Setup 6)
; CI tarafından derlenir: ISCC /DAppVersion=1.0.0 /DSourceDir=... installer\parksense.iss
;
; Özellikler: Türkçe sihirbaz, kurulum dizini seçimi, Başlat menüsü kısayolu,
; isteğe bağlı masaüstü kısayolu, Programlar ve Özellikler'den kaldırma.
; Yönetici izni gerektirmez (kullanıcı başına kurulum); istenirse tüm
; kullanıcılar için kurulum seçilebilir.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{B7E4C2A1-5F3D-4E8B-9A6C-2D1F0E7B8C45}
AppName=PARKSENSE
AppVersion={#AppVersion}
AppVerName=PARKSENSE {#AppVersion}
AppPublisher=Furkan
AppPublisherURL=https://github.com/furkantr1923/parksense
AppSupportURL=https://github.com/furkantr1923/parksense/issues
AppUpdatesURL=https://github.com/furkantr1923/parksense/releases
VersionInfoVersion={#AppVersion}
VersionInfoProductName=PARKSENSE
VersionInfoDescription=PARKSENSE Kurulum
DefaultDirName={autopf}\PARKSENSE
DefaultGroupName=PARKSENSE
DisableDirPage=no
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=commandline dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=PARKSENSE-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\PARKSENSE.exe
UninstallDisplayName=PARKSENSE
LicenseFile=..\LICENSE
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
MinVersion=10.0
CloseApplications=yes

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\PARKSENSE"; Filename: "{app}\PARKSENSE.exe"
Name: "{group}\PARKSENSE kaldır"; Filename: "{uninstallexe}"
Name: "{autodesktop}\PARKSENSE"; Filename: "{app}\PARKSENSE.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\PARKSENSE.exe"; Description: "{cm:LaunchProgram,PARKSENSE}"; Flags: nowait postinstall skipifsilent
