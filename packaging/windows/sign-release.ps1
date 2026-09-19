[CmdletBinding()]
param([Parameter(Mandatory=$true)][string[]]$Files)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$configured = -not [string]::IsNullOrWhiteSpace($env:WINDOWS_SIGNING_PFX_BASE64)
if (-not $configured) {
    if ($env:REQUIRE_PLATFORM_SIGNING -eq 'true' -or $env:WINDOWS_SIGNING_PFX_PASSWORD) { throw 'Windows signing identity is incomplete or required' }
    Write-Host 'No Windows publishing certificate configured; artifacts are explicitly unsigned.'
    return
}
if (-not $env:WINDOWS_SIGNING_PFX_PASSWORD) { throw 'WINDOWS_SIGNING_PFX_PASSWORD is required with a PFX certificate' }
$sdkRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
$signTool = Get-ChildItem -LiteralPath $sdkRoot -Filter signtool.exe -Recurse -File |
    Where-Object { $_.Directory.Name -eq 'x64' } | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $signTool) { throw 'Install the Windows SDK signing tools' }
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('home-tunnel-signing-' + [Guid]::NewGuid().ToString('N') + '.pfx')
$certificate = $null
$previousThumbprints = @(Get-ChildItem Cert:\CurrentUser\My | ForEach-Object { $_.Thumbprint })
try {
    [IO.File]::WriteAllBytes($temporary, [Convert]::FromBase64String($env:WINDOWS_SIGNING_PFX_BASE64))
    $password = ConvertTo-SecureString $env:WINDOWS_SIGNING_PFX_PASSWORD -AsPlainText -Force
    $certificate = Import-PfxCertificate -FilePath $temporary -CertStoreLocation Cert:\CurrentUser\My -Password $password
    if (-not $certificate.HasPrivateKey) { throw 'Signing certificate has no private key' }
    foreach ($path in $Files) {
        $resolved = (Resolve-Path -LiteralPath $path).Path
        & $signTool sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /sha1 $certificate.Thumbprint $resolved
        if ($LASTEXITCODE -ne 0) { throw 'Authenticode signing failed' }
        & $signTool verify /pa /all $resolved
        if ($LASTEXITCODE -ne 0) { throw 'Authenticode verification failed' }
        $signature = Get-AuthenticodeSignature -LiteralPath $resolved
        if ($signature.Status -ne 'Valid' -or -not $signature.TimeStamperCertificate) { throw 'Signature or timestamp is invalid' }
    }
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    if ($certificate -and $certificate.Thumbprint -match '^[A-Fa-f0-9]{40}$' -and $certificate.Thumbprint -notin $previousThumbprints) {
        Remove-Item -LiteralPath ("Cert:\CurrentUser\My\" + $certificate.Thumbprint) -DeleteKey -Force
    }
}
