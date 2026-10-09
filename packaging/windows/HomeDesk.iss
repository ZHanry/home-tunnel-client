#ifndef AppVersion
  #define AppVersion "12.0.0-RC1"
#endif
#ifndef SourceDir
  #define SourceDir "."
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

[Setup]
AppId={{8F3C1B2A-7D54-4E19-9A6C-2B0E5D8F4A11}
AppName=栖云桥 / NestLink
AppVersion={#AppVersion}
VersionInfoVersion=12.0.0.1
AppPublisher=NestLink
AppPublisherURL=https://github.com/ZHanry/home-tunnel-client
DefaultDirName={localappdata}\Home Tunnel
DefaultGroupName=NestLink
DisableProgramGroupPage=yes
LicenseFile={#SourceDir}\LICENSE-RUSTDESK
OutputDir={#OutputDir}
OutputBaseFilename=NestLink-Setup-{#AppVersion}-x64
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
Name: "{group}\NestLink"; Filename: "{app}\homedesk.exe"
Name: "{autodesktop}\NestLink"; Filename: "{app}\homedesk.exe"; Tasks: desktopicon
Name: "{group}\Uninstall NestLink"; Filename: "{uninstallexe}"

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
Filename: "{app}\homedesk.exe"; Description: "{cm:LaunchProgram,NestLink}"; Flags: nowait postinstall skipifsilent

[Code]
function OpenUpgradeTarget(FileName: String; DesiredAccess, ShareMode: LongWord;
  SecurityAttributes: NativeUInt; CreationDisposition, FlagsAndAttributes: LongWord;
  TemplateFile: THandle): THandle;
  external 'CreateFileW@kernel32.dll stdcall';

function CloseUpgradeTarget(Handle: THandle): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';

function UpgradeTargetAvailable(Name: String): Boolean;
var
  Target: String;
  Handle: THandle;
begin
  Target := AddBackslash(ExpandConstant('{app}')) + Name;
  Result := True;
  if not FileExists(Target) then
    Exit;
  { OPEN_EXISTING only probes the file. Loaded executables and files that
    cannot be replaced must still block the upgrade, regardless of the
    legacy service command's result. }
  Handle := OpenUpgradeTarget(Target, $C0000000, 0, 0, 3, 0, 0);
  Result := Handle <> THandle(-1);
  if Result then
    CloseUpgradeTarget(Handle);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  LegacyService: String;
  ExitCode: Integer;
begin
  Result := '';
  LegacyService := ExpandConstant('{app}\home-tunnel-service.exe');
  { Per-user installations can retain the old executable without having a
    system service. Do not request service-control privileges for a file
    that is already available. An attempted stop is best-effort; the file
    probes below are the final condition for safely replacing this folder. }
  if FileExists(LegacyService) and
     not UpgradeTargetAvailable('home-tunnel-service.exe') then
    Exec(LegacyService, 'stop', '', SW_HIDE, ewWaitUntilTerminated, ExitCode);

  if not UpgradeTargetAvailable('homedesk.exe') or
     not UpgradeTargetAvailable('homedesk-tunnel-helper.exe') or
     not UpgradeTargetAvailable('home-tunnel-client.exe') or
     not UpgradeTargetAvailable('home-tunnel-gui.exe') or
     not UpgradeTargetAvailable('home-tunnel-agent.exe') or
     not UpgradeTargetAvailable('home_tunnel_remote_host.exe') or
     not UpgradeTargetAvailable('home_tunnel_remote_host.dll') or
     not UpgradeTargetAvailable('home-tunnel-service.exe') then
  begin
    if ActiveLanguage = 'chinesesimplified' then
      Result := '请先从界面或托盘退出 Home Tunnel/HomeDesk，等待此安装目录的后台进程结束后重试。旧系统服务若仍运行，请以管理员身份停止；若文件仍不可写，请检查目录权限。账号及隧道配置会保留。'
    else
      Result := 'Exit Home Tunnel/HomeDesk from its window or tray and wait for background processes in this installation folder to finish. If the legacy service is still running, stop it as administrator, then retry. Check folder permissions if files remain unavailable. Existing account and tunnel data are preserved.';
  end;
end;
