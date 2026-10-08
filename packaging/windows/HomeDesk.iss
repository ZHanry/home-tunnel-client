#ifndef AppVersion
  #define AppVersion "11.0.0-rc.1"
#endif
#ifndef SourceDir
  #define SourceDir "."
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

[Setup]
AppId={{8F3C1B2A-7D54-4E19-9A6C-2B0E5D8F4A11}
AppName=HomeDesk
AppVersion={#AppVersion}
VersionInfoVersion=11.0.0.1
AppPublisher=Home Tunnel
AppPublisherURL=https://github.com/ZHanry/home-tunnel-client
DefaultDirName={localappdata}\Home Tunnel
DefaultGroupName=HomeDesk
DisableProgramGroupPage=yes
LicenseFile={#SourceDir}\LICENSE-RUSTDESK
OutputDir={#OutputDir}
OutputBaseFilename=HomeDesk-Setup-{#AppVersion}-x64
SetupIconFile={#SourceDir}\HomeDesk.ico
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\homedesk.exe
WizardStyle=modern
CloseApplications=no
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\HomeDesk"; Filename: "{app}\homedesk.exe"
Name: "{autodesktop}\HomeDesk"; Filename: "{app}\homedesk.exe"; Tasks: desktopicon
Name: "{group}\Uninstall HomeDesk"; Filename: "{uninstallexe}"

[InstallDelete]
Type: files; Name: "{app}\home-tunnel-gui.exe"
Type: files; Name: "{app}\home-tunnel-service.exe"
Type: files; Name: "{app}\home_tunnel_remote_host.exe"
Type: files; Name: "{app}\home_tunnel_remote_host.dll"

[Registry]
Root: HKA; Subkey: "Software\Classes\homedesk"; ValueType: string; ValueData: "URL:HomeDesk"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\homedesk"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKA; Subkey: "Software\Classes\homedesk\shell\open\command"; ValueType: string; ValueData: """{app}\homedesk.exe"" ""%1"""

[Run]
Filename: "{app}\homedesk.exe"; Description: "{cm:LaunchProgram,HomeDesk}"; Flags: nowait postinstall skipifsilent

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  LegacyService: String;
  ExitCode: Integer;
begin
  Result := '';
  LegacyService := ExpandConstant('{app}\home-tunnel-service.exe');
  if FileExists(LegacyService) then
  begin
    if not Exec(LegacyService, 'stop', '', SW_HIDE, ewWaitUntilTerminated, ExitCode) or (ExitCode <> 0) then
      Result := 'Close the old Home Tunnel service before upgrading. Existing account and tunnel data are preserved.';
  end;
end;
