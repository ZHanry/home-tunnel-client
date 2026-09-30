$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'update-defender-signatures.ps1')

# Pure unit test: no Defender, network, sleep, or machine preferences are used.
function Test-Scanner {
    param([switch]$SignatureUpdate)
    if (-not $SignatureUpdate) { throw 'Only signature updates may be retried' }
    $result = $script:results[$script:calls]
    $script:calls++
    $global:LASTEXITCODE = $result.exit
    Write-Output $result.output
}
function Start-Sleep {
    param([int]$Seconds)
    $script:delays += $Seconds
}
function Test-Update {
    param([array]$Results, [int]$Calls, [array]$Delays, [bool]$MustFail)
    $script:results = $Results
    $script:calls = 0
    $script:delays = @()
    $failed = $false
    try { Update-DefenderSignatures -Scanner Test-Scanner | Out-Null }
    catch { $failed = $true }
    if ($failed -ne $MustFail -or $script:calls -ne $Calls -or
        ($script:delays -join ',') -ne ($Delays -join ',')) {
        throw "Unexpected retry result: failed=$failed calls=$script:calls delays=$script:delays"
    }
}
$success = @{ exit = 0; output = 'Signature update finished' }
$timeout = @{ exit = 2; output = 'ERROR: Signature Update failed with hr=0x80072ee2' }
$denied = @{ exit = 2; output = 'Access denied: 0x80070005' }
Test-Update -Results @($success) -Calls 1 -Delays @() -MustFail $false
Test-Update -Results @($timeout, $success) -Calls 2 -Delays @(10) -MustFail $false
Test-Update -Results @($timeout, $timeout, $success) -Calls 3 -Delays @(10, 20) -MustFail $false
Test-Update -Results @($timeout, $timeout, $timeout) -Calls 3 -Delays @(10, 20) -MustFail $true
Test-Update -Results @($denied) -Calls 1 -Delays @() -MustFail $true
Test-Update -Results @($timeout, $denied) -Calls 2 -Delays @(10) -MustFail $true
Write-Output 'Defender signature retry policy: 6 cases passed'
