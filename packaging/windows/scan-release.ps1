param(
    [Parameter(Mandatory = $true)][string]$Directory,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$ReportPath,
    [switch]$UpdateSignatures
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$directoryPath = (Resolve-Path -LiteralPath $Directory).Path
$subjects = @("HomeTunnel-Setup-$Version-x64.exe", "HomeTunnel-Windows-$Version-x64.zip", 'home-tunnel-gui.exe', 'home-tunnel-agent.exe')
$scanner = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
if (-not (Test-Path -LiteralPath $scanner -PathType Leaf)) { throw 'Microsoft Defender scanner is missing' }
# Hosted runners may leave the installed service stopped. Start protection only
# on the disposable CI host; never weaken preferences or add exclusions.
if ($env:GITHUB_ACTIONS -eq 'true') {
    $service = Get-Service -Name WinDefend -ErrorAction Stop
    Write-Output "Defender service: $($service.Status), startup: $($service.StartType)"
    if ($service.Status -ne 'Running') {
        if ($service.StartType -eq 'Disabled') { Set-Service -Name WinDefend -StartupType Manual -ErrorAction Stop }
        Start-Service -Name WinDefend -ErrorAction Stop
        (Get-Service WinDefend).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
    }
}
if ($UpdateSignatures) {
    & $scanner -SignatureUpdate
    if ($LASTEXITCODE -ne 0) { throw "Defender signature update failed: $LASTEXITCODE" }
}
$status = Get-MpComputerStatus -ErrorAction Stop
if (-not $status.AMServiceEnabled -or -not $status.AntivirusEnabled) { throw 'Microsoft Defender is unavailable; release scanning is required' }
if ($status.AntivirusSignatureLastUpdated -lt (Get-Date).AddDays(-2)) { throw 'Defender signatures are older than 48 hours' }
$report = [ordered]@{
    schema_version = 1
    status = 'pending'
    version = $Version
    repository_revision = $env:GITHUB_SHA
    engine = 'Microsoft Defender'
    engine_version = [string]$status.AMEngineVersion
    signature_version = [string]$status.AntivirusSignatureVersion
    signature_updated_at = $status.AntivirusSignatureLastUpdated.ToUniversalTime().ToString('o')
    scanned_at = (Get-Date).ToUniversalTime().ToString('o')
    files = @()
}
try {
    foreach ($name in $subjects) {
        $file = Join-Path $directoryPath $name
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Scan subject is missing: $name" }
        $before = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        # Custom scanning with this flag ignores exclusions and reports detections
        # without changing the files or real-time protection preferences.
        $scanOutput = & $scanner -Scan -ScanType 3 -File $file -DisableRemediation 2>&1
        $scanExit = $LASTEXITCODE
        $scanOutput | Write-Output
        if ($scanExit -ne 0) { throw "Defender rejected $name (exit $scanExit); publication is blocked" }
        $after = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($before -ne $after) { throw "File changed during scanning: $name" }
        $report.files += [ordered]@{ name = $name; sha256 = $after; exit_code = $scanExit }
    }
    $report.status = 'passed'
} catch {
    $report.status = 'failed'
    throw
} finally {
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath), ($report | ConvertTo-Json -Depth 6) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}
