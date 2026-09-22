# Build the release worker from the reviewed source lock. No global tools are changed.
param([int]$Jobs = 4)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$clientDir = Split-Path -Parent $PSScriptRoot
$cache = Join-Path $clientDir '.downloads/remote-webrtc'
$output = Join-Path $clientDir 'outputs/native-windows-build'
New-Item -ItemType Directory -Force -Path $cache, $output | Out-Null
$drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($cache))
$required = 24GB
$resources = [ordered]@{
    schema_version = 1
    status = $(if ($drive.AvailableFreeSpace -ge $required) { 'sufficient' } else { 'insufficient' })
    free_bytes = $drive.AvailableFreeSpace
    required_free_bytes = $required
    processor_count = [Environment]::ProcessorCount
    jobs = $Jobs
}
[IO.File]::WriteAllText((Join-Path $output 'resources.json'), ($resources | ConvertTo-Json) + [char]10, [Text.UTF8Encoding]::new($false))
if ($drive.AvailableFreeSpace -lt $required) { throw 'Pinned native build needs 24 GiB free disk; select a larger Windows runner. No installed tools were deleted.' }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$installation = (& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json | ConvertFrom-Json | Select-Object -First 1)
if (-not $installation) { throw 'Visual Studio C++ x64 toolchain is required' }
$vsVersion = if ([version]$installation.installationVersion -ge [version]'18.0') { '2026' } else { '2022' }
Push-Location $clientDir
try {
    python scripts/prepare-remote-windows-sdk.py --visual-studio $installation.installationPath --visual-studio-version $vsVersion
    if ($LASTEXITCODE -ne 0) { throw 'Pinned portable SDK preparation failed' }
    python scripts/build-remote-webrtc.py --build --windows-toolchain (Join-Path $cache 'windows-toolchain/portable-toolchain.json') --jobs $Jobs --media-probe
    if ($LASTEXITCODE -ne 0) { throw 'Native source build, authorization checks or dependency notices failed' }
    $build = Join-Path $cache 'checkout/src/out/home_tunnel'
    foreach ($name in @('home_tunnel_remote_host.exe', 'remote-host-build.json', 'remote-source-manifest.json', 'LICENSE.md')) {
        Copy-Item -LiteralPath (Join-Path $build $name) -Destination (Join-Path $output $name) -Force
    }
    # Preserve the local packaging path only in the internal build record.
    $record = Get-Content -Raw -LiteralPath (Join-Path $output 'remote-host-build.json') | ConvertFrom-Json
    $record.executable = Join-Path $output 'home_tunnel_remote_host.exe'
    [IO.File]::WriteAllText((Join-Path $output 'remote-host-build.json'), ($record | ConvertTo-Json -Depth 12) + [char]10, [Text.UTF8Encoding]::new($false))
    Write-Output "REMOTE_HOST_BUILD=$(Join-Path $output 'remote-host-build.json')"
} finally { Pop-Location }
