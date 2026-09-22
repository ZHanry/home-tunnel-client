param(
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$SourceDir,
    [Parameter(Mandatory = $true)][string]$IsccPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($Version -notmatch '^(\d+\.\d+\.\d+)(?:-rc\.[1-9]\d*)?$') { throw 'Installer version must be X.Y.Z or X.Y.Z-rc.N' }
$numericVersion = $Matches[1]
$SourceDir = (Resolve-Path -LiteralPath $SourceDir).Path
$compiler = (Resolve-Path -LiteralPath $IsccPath).Path
$clientDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
foreach ($name in @('home-tunnel-gui.exe', 'home-tunnel-agent.exe', 'home_tunnel_remote_host.exe', 'remote-host-provenance.json', 'remote-host-build.json', 'remote-source-manifest.json', 'WEBRTC-THIRD-PARTY-NOTICES.md', 'HomeTunnel.ico', 'platform-signing.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $SourceDir $name) -PathType Leaf)) { throw "Missing installer payload: $name" }
}
Copy-Item -LiteralPath (Join-Path $clientDir 'LICENSE') -Destination (Join-Path $SourceDir 'LICENSE.txt') -Force
foreach ($name in @('LICENSE', 'README.md', 'README.en.md', 'docs', 'contracts')) {
    Copy-Item -LiteralPath (Join-Path $clientDir $name) -Destination $SourceDir -Recurse -Force
}
New-Item -ItemType Directory -Path (Join-Path $SourceDir 'packaging') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $clientDir 'packaging\nas') -Destination (Join-Path $SourceDir 'packaging') -Recurse -Force
foreach ($name in @('FRP-LICENSE.txt', 'THIRD-PARTY-NOTICES.txt')) {
    Copy-Item -LiteralPath (Join-Path $clientDir "agent\$name") -Destination (Join-Path $SourceDir $name) -Force
}
& $compiler '/Qp' "/DAppVersion=$Version" "/DAppNumericVersion=$numericVersion" "/DSourceDir=$SourceDir" (Join-Path $PSScriptRoot 'HomeTunnel.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed: $LASTEXITCODE" }
$setup = Join-Path $SourceDir "HomeTunnel-Setup-$Version-x64.exe"
if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) { throw 'Compiled installer is missing' }
Write-Output "SETUP=$setup"
