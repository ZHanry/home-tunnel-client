param([Parameter(Mandatory=$true)][string]$Installer, [string]$EvidenceDirectory = 'material-input')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$build = Get-Content -Raw -LiteralPath (Join-Path $EvidenceDirectory 'windows-build.json') | ConvertFrom-Json
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('homedesk-install-fixture-' + [guid]::NewGuid().ToString('N'))
$destination = Join-Path $fixture 'installed'
New-Item -ItemType Directory -Path $fixture | Out-Null
$installerPath = (Get-Item -LiteralPath $Installer).FullName
$arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOICONS', '/SP-', '/CURRENTUSER', "/DIR=`"$destination`"", "/LOG=`"$fixture\install.log`"")
$install = Start-Process -FilePath $installerPath -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
if ($install.ExitCode -ne 0) { throw "Installation failed: $($install.ExitCode); fixture: $fixture" }
$verified = 0
foreach ($entry in $build.payload_sha256.PSObject.Properties) {
    $target = Join-Path $destination $entry.Name
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Missing installed file: $($entry.Name)" }
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.Value) {
        throw "Installed bytes differ: $($entry.Name)"
    }
    $verified++
}
if (Test-Path -LiteralPath (Join-Path $destination 'home_tunnel_remote_host.exe')) { throw 'Historical remote worker must not ship' }
if (Test-Path -LiteralPath (Join-Path $destination 'home-tunnel-service.exe')) { throw 'Historical GUI-bound service must not ship' }
$urlCommand = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Classes\homedesk\shell\open\command').'(default)'
if ($urlCommand -ne ('"' + (Join-Path $destination 'homedesk.exe') + '" "%1"')) { throw 'URL handler does not target this installation' }
$cli = & (Join-Path $destination 'home-tunnel-client.exe') version
if ($LASTEXITCODE -ne 0 -or ($cli -join "`n") -notmatch [regex]::Escape($build.version)) { throw 'Installed CLI version mismatch' }
$uninstall = Start-Process -FilePath (Join-Path $destination 'unins000.exe') -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -WindowStyle Hidden -Wait -PassThru
if ($uninstall.ExitCode -ne 0 -or (Test-Path -LiteralPath (Join-Path $destination 'homedesk.exe'))) { throw 'Uninstall did not remove the product' }
$record = [ordered]@{status='passed';revision=$build.revision;version=$build.version;scope='silent install, exact payload hashes, URL protocol, CLI version and uninstall; no remote media acceptance';verified_files=$verified;installer_sha256=(Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()}
$record | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 -LiteralPath (Join-Path $EvidenceDirectory 'windows-installer.json')
# Remove only this newly created, verified fixture; keep it when any check fails.
$resolved = [IO.Path]::GetFullPath($fixture)
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
if (-not $resolved.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'homedesk-install-fixture-*') { throw 'Unexpected fixture path' }
Remove-Item -LiteralPath $resolved -Recurse -Force
Write-Output "Installed $verified exact files; URL registration, CLI and uninstall verified."
