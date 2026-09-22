# Builds the shared Go graphical client for Windows x64.
# Requires Go 1.26+. Prefer packaging/windows/build-release.ps1 for the zip.

param(
    [string]$Version = "8.0.0-rc.1",
    [string]$OutputDir = "",
    [string]$WindRes = $env:HOME_TUNNEL_WINDRES,
    [string]$AgentVersion = "",
    [string]$ExpectedAgentSHA256 = "",
    [string]$ExpectedRemoteHostSHA256 = ""
)

$ErrorActionPreference = "Stop"
$clientDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $OutputDir) {
    $OutputDir = Join-Path $clientDir "outputs\windows"
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
if (-not $WindRes -or -not (Test-Path -LiteralPath $WindRes -PathType Leaf)) { throw 'Pass the pinned windres executable to embed the application icon' }
if ($Version -notmatch '^(\d+)\.(\d+)\.(\d+)(?:-(?:alpha|beta|rc)\.[1-9]\d*)?$') { throw 'Version must be X.Y.Z or X.Y.Z-rc.N/alpha.N/beta.N' }
$numericVersion = "$($Matches[1]).$($Matches[2]).$($Matches[3])"
$versionFlags = if ($Version.Contains('-')) { '0x2L' } else { '0x0L' }
if ($ExpectedRemoteHostSHA256 -and $ExpectedRemoteHostSHA256 -notmatch '^[0-9a-f]{64}$') { throw 'Invalid native host digest' }
$resourceDir = Join-Path $clientDir '.downloads\windows-gui-resources'
New-Item -ItemType Directory -Force -Path $resourceDir | Out-Null
$icon = (Join-Path $clientDir 'internal\desktop\icon.ico').Replace('\','/')
$numbers = $numericVersion.Replace('.', ',') + ',0'
$resource = @"
#include <winver.h>
1 ICON "$icon"
1 VERSIONINFO
 FILEVERSION $numbers
 PRODUCTVERSION $numbers
 FILEFLAGSMASK 0x3fL
 FILEFLAGS $versionFlags
 FILEOS VOS_NT_WINDOWS32
 FILETYPE VFT_APP
BEGIN
 BLOCK "StringFileInfo"
 BEGIN
  BLOCK "040904b0"
  BEGIN
   VALUE "CompanyName", "Home Tunnel"
   VALUE "FileDescription", "Home Tunnel"
   VALUE "FileVersion", "$Version"
   VALUE "InternalName", "home-tunnel-gui"
   VALUE "OriginalFilename", "home-tunnel-gui.exe"
   VALUE "ProductName", "Home Tunnel"
   VALUE "ProductVersion", "$Version"
  END
 END
 BLOCK "VarFileInfo"
 BEGIN
  VALUE "Translation", 0x0409, 1200
 END
END
"@
$rc = Join-Path $resourceDir 'HomeTunnel.rc'
$syso = Join-Path $clientDir 'cmd\home-tunnel-gui\resources_windows_amd64.syso'
if (Test-Path -LiteralPath $syso) { throw 'Generated GUI resource already exists; use a clean build directory' }
[IO.File]::WriteAllText($rc, $resource, [Text.UTF8Encoding]::new($false))
$previousEpoch = [Environment]::GetEnvironmentVariable('SOURCE_DATE_EPOCH','Process')
try {
    $env:SOURCE_DATE_EPOCH = '0'
    & $WindRes -i $rc -o $syso -O coff --target=pe-x86-64
    if ($LASTEXITCODE -ne 0) { throw 'GUI resource compilation failed' }
} finally {
    if ($null -eq $previousEpoch) { Remove-Item Env:SOURCE_DATE_EPOCH -ErrorAction SilentlyContinue } else { $env:SOURCE_DATE_EPOCH = $previousEpoch }
}
$env:CGO_ENABLED = "0"
$env:GOOS = "windows"
$env:GOARCH = "amd64"
$env:GOFLAGS = "-buildvcs=false"
Push-Location $clientDir
try {
    go build -trimpath -ldflags "-s -w -H windowsgui -buildid= -X main.version=$Version -X main.agentVersion=$AgentVersion -X main.expectedAgentSHA256=$ExpectedAgentSHA256 -X main.expectedRemoteHostSHA256=$ExpectedRemoteHostSHA256" `
        -o (Join-Path $OutputDir "home-tunnel-gui.exe") ./cmd/home-tunnel-gui
    if ($LASTEXITCODE -ne 0) { throw 'Windows GUI build failed' }
}
finally {
    Pop-Location
    Remove-Item -LiteralPath $syso -Force
}
Write-Host "GUI=$(Join-Path $OutputDir 'home-tunnel-gui.exe')"
