param(
    [Parameter(Mandatory = $true)][string]$Installer,
    [Parameter(Mandatory = $true)][string]$PayloadDirectory,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$ReportPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -ne 'true' -or -not $env:RUNNER_TEMP) { throw 'Installer lifecycle checks must run on an isolated GitHub runner' }
$runnerRoot = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\') + '\'
$destination = [IO.Path]::GetFullPath((Join-Path $runnerRoot "home-tunnel-install-$Version"))
if (-not $destination.StartsWith($runnerRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid smoke installation path' }
if (Test-Path -LiteralPath $destination) { throw 'Smoke installation path already exists' }
$arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', "/DIR=`"$destination`"")
$process = Start-Process -FilePath $Installer -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Installer exited with $($process.ExitCode)" }
foreach ($name in @('home-tunnel-gui.exe', 'home-tunnel-agent.exe', 'LICENSE.txt', 'FRP-LICENSE.txt', 'THIRD-PARTY-NOTICES.txt')) {
    $installed = (Get-FileHash -LiteralPath (Join-Path $destination $name) -Algorithm SHA256).Hash
    $expected = (Get-FileHash -LiteralPath (Join-Path $PayloadDirectory $name) -Algorithm SHA256).Hash
    if ($installed -ne $expected) { throw "Installed payload mismatch: $name" }
}
if (Test-Path -LiteralPath (Join-Path $destination 'uninstall.cmd')) { throw 'Legacy batch uninstaller must not be installed' }
$uninstaller = Join-Path $destination 'unins000.exe'
if (-not (Test-Path -LiteralPath $uninstaller -PathType Leaf)) { throw 'Native uninstaller is missing' }
$process = Start-Process -FilePath $uninstaller -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -WindowStyle Hidden -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Uninstaller exited with $($process.ExitCode)" }
foreach ($name in @('home-tunnel-gui.exe', 'home-tunnel-agent.exe')) {
    if (Test-Path -LiteralPath (Join-Path $destination $name)) { throw "Uninstall left $name behind" }
}
$report = @{ schema_version = 1; status = 'passed'; version = $Version; repository_revision = $env:GITHUB_SHA; installer_sha256 = (Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash.ToLowerInvariant(); install = 'passed'; payload_hashes = 'passed'; uninstall = 'passed' }
[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath), ($report | ConvertTo-Json) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
