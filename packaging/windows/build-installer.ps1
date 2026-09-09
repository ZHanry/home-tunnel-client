param(
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$SourceDir,
    [Parameter(Mandatory = $true)][string]$IsccPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Installer version must be X.Y.Z' }
$SourceDir = (Resolve-Path -LiteralPath $SourceDir).Path
$compiler = (Resolve-Path -LiteralPath $IsccPath).Path
$clientDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
foreach ($name in @('home-tunnel-gui.exe', 'home-tunnel-agent.exe', 'HomeTunnel.ico')) {
    if (-not (Test-Path -LiteralPath (Join-Path $SourceDir $name) -PathType Leaf)) { throw "Missing installer payload: $name" }
}
Copy-Item -LiteralPath (Join-Path $clientDir 'LICENSE') -Destination (Join-Path $SourceDir 'LICENSE.txt') -Force
foreach ($name in @('FRP-LICENSE.txt', 'THIRD-PARTY-NOTICES.txt')) {
    Copy-Item -LiteralPath (Join-Path $clientDir "agent\$name") -Destination (Join-Path $SourceDir $name) -Force
}
& $compiler '/Qp' "/DAppVersion=$Version" "/DSourceDir=$SourceDir" (Join-Path $PSScriptRoot 'HomeTunnel.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compilation failed: $LASTEXITCODE" }
$setup = Join-Path $SourceDir "HomeTunnel-Setup-$Version-x64.exe"
if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) { throw 'Compiled installer is missing' }
Write-Output "SETUP=$setup"
