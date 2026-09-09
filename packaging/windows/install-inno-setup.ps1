param([string]$ToolsDirectory = "")

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$pin = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'inno-setup.json') | ConvertFrom-Json
if (-not $ToolsDirectory) {
    $ToolsDirectory = if ($env:RUNNER_TEMP) { Join-Path $env:RUNNER_TEMP 'home-tunnel-build-tools' } else { Join-Path $PSScriptRoot '..\..\.downloads\build-tools' }
}
$ToolsDirectory = [IO.Path]::GetFullPath($ToolsDirectory)
New-Item -ItemType Directory -Force -Path $ToolsDirectory | Out-Null
$installer = Join-Path $ToolsDirectory "innosetup-$($pin.version)-x64.exe"
if (-not (Test-Path -LiteralPath $installer)) {
    Invoke-WebRequest -Uri $pin.url -OutFile $installer
}
if ((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash.ToLowerInvariant() -ne $pin.sha256) {
    throw 'Inno Setup compiler installer checksum mismatch'
}
$destination = Join-Path $ToolsDirectory "inno-$($pin.version)"
$arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOICONS', '/SP-', "/DIR=`"$destination`"")
$process = Start-Process -FilePath $installer -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Inno Setup installation failed: $($process.ExitCode)" }
$compiler = Join-Path $destination 'ISCC.exe'
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) { throw 'Inno Setup compiler is missing' }
Write-Output "ISCC=$compiler"
