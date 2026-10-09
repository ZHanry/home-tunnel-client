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
$guiPath = Join-Path $destination 'homedesk.exe'
$versionInfo = (Get-Item -LiteralPath $guiPath).VersionInfo
if ($versionInfo.ProductVersion -ne $build.version -or $versionInfo.FileVersion -ne $build.version) { throw 'Installed GUI version mismatch' }
if (Test-Path -LiteralPath (Join-Path $destination 'home-tunnel-client.exe')) { throw 'Retired standalone CLI must not ship' }
$gui = Start-Process -FilePath $guiPath -WorkingDirectory $destination -WindowStyle Hidden -PassThru
try {
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        Start-Sleep -Milliseconds 500
        $gui.Refresh()
        if ($gui.HasExited) { throw "Installed GUI exited during startup: $($gui.ExitCode)" }
    } while ($gui.MainWindowHandle -eq 0 -and [DateTime]::UtcNow -lt $deadline)
    if ($gui.MainWindowHandle -eq 0 -or $gui.MainWindowTitle -cne 'nestlink') { throw 'Installed GUI did not create its branded window' }
} finally {
    if (-not $gui.HasExited) { Stop-Process -Id $gui.Id -Force; $gui.WaitForExit() }
}
$uninstall = Start-Process -FilePath (Join-Path $destination 'unins000.exe') -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -WindowStyle Hidden -Wait -PassThru
if ($uninstall.ExitCode -ne 0 -or (Test-Path -LiteralPath (Join-Path $destination 'homedesk.exe'))) { throw 'Uninstall did not remove the product' }
$record = [ordered]@{status='passed';revision=$build.revision;version=$build.version;scope='silent install, exact payload hashes, URL protocol, GUI PE version, branded window startup and uninstall; no remote media acceptance';verified_files=$verified;installer_sha256=(Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant()}
$record | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 -LiteralPath (Join-Path $EvidenceDirectory 'windows-installer.json')
# Remove only this newly created, verified fixture; keep it when any check fails.
$resolved = [IO.Path]::GetFullPath($fixture)
$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
if (-not $resolved.StartsWith($temporaryRoot, [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'homedesk-install-fixture-*') { throw 'Unexpected fixture path' }
Remove-Item -LiteralPath $resolved -Recurse -Force
Write-Output "Installed $verified exact files; URL registration, GUI version, startup and uninstall verified."
