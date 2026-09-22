#define AppName "Home Tunnel"
#ifndef AppVersion
  #define AppVersion "8.0.0-rc.1"
#endif
#ifndef AppNumericVersion
  #define AppNumericVersion "8.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "."
#endif

[Setup]
AppId={{8F3C1B2A-7D54-4E19-9A6C-2B0E5D8F4A11}
AppName={#AppName}
AppVersion={#AppVersion}
VersionInfoVersion={#AppNumericVersion}
AppPublisher=Home Tunnel
AppPublisherURL=https://github.com/ZHanry/home-tunnel-client
AppSupportURL=https://github.com/ZHanry/home-tunnel-client/issues
DefaultDirName={localappdata}\Home Tunnel
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
LicenseFile={#SourceDir}\LICENSE.txt
OutputDir={#SourceDir}
OutputBaseFilename=HomeTunnel-Setup-{#AppVersion}-x64
SetupIconFile={#SourceDir}\HomeTunnel.ico
Compression=lzma2
SolidCompression=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\home-tunnel-gui.exe
WizardStyle=modern
CloseApplications=yes
CloseApplicationsFilter=home-tunnel-gui.exe,home-tunnel-agent.exe,home_tunnel_remote_host.exe
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\home-tunnel-gui.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\home-tunnel-agent.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\home_tunnel_remote_host.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\remote-host-provenance.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\remote-host-build.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\remote-source-manifest.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\WEBRTC-THIRD-PARTY-NOTICES.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\HomeTunnel.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\FRP-LICENSE.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\THIRD-PARTY-NOTICES.txt"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\platform-signing.json"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\README*.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\docs\*"; DestDir: "{app}\docs"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceDir}\contracts\*"; DestDir: "{app}\contracts"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceDir}\packaging\nas\*"; DestDir: "{app}\packaging\nas"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
Type: files; Name: "{app}\uninstall.cmd"

[Icons]
Name: "{group}\Home Tunnel"; Filename: "{app}\home-tunnel-gui.exe"; IconFilename: "{app}\HomeTunnel.ico"
Name: "{group}\Uninstall Home Tunnel"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Home Tunnel"; Filename: "{app}\home-tunnel-gui.exe"; IconFilename: "{app}\HomeTunnel.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\home-tunnel-gui.exe"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[Code]
procedure CurStepChanged(CurStep: TSetupStep);
var
  PreviousLocation: String;
begin
  if CurStep = ssPostInstall then
    if RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\HomeTunnel', 'InstallLocation', PreviousLocation) then
      if CompareText(RemoveBackslashUnlessRoot(PreviousLocation), RemoveBackslashUnlessRoot(ExpandConstant('{app}'))) = 0 then
        RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\HomeTunnel');
end;
