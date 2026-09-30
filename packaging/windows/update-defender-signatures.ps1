function Update-DefenderSignatures {
    param([Parameter(Mandatory = $true)][string]$Scanner)

    # Retry only the observed WinINet timeout. Never retry a scan/detection,
    # accept stale signatures, change update sources, or weaken protection.
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $updateOutput = & $Scanner -SignatureUpdate 2>&1
        $updateExit = $LASTEXITCODE
        $updateOutput | Write-Output
        if ($updateExit -eq 0) { return }
        if ($attempt -eq 3 -or ($updateOutput -join "`n") -notmatch '(?i)\b0x80072ee2\b') {
            throw "Defender signature update failed: $updateExit (attempt $attempt)"
        }
        $delay = 10 * $attempt
        Write-Warning "Defender signature update timed out; retrying in $delay seconds ($attempt/3)"
        Start-Sleep -Seconds $delay
    }
}
