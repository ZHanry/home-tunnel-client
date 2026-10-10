# Backups stay outside the repository. Install to an Explorer-visible location.
param(
    [Parameter(Mandatory = $true)][string]$Installer,
    [Parameter(Mandatory = $true)][string]$BuildReceipt,
    [switch]$PlanOnly,
    [switch]$Launch
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$installerPath = (Resolve-Path -LiteralPath $Installer).Path
if ([IO.Path]::GetExtension($installerPath) -ne '.exe') { throw 'Expected a Windows installer executable.' }
$localRoot = [IO.Path]::GetFullPath([Environment]::GetFolderPath('LocalApplicationData'))
$roamingRoot = [IO.Path]::GetFullPath([Environment]::GetFolderPath('ApplicationData'))
$profileRoot = [IO.Path]::GetFullPath([Environment]::GetFolderPath('UserProfile'))
$installRoot = Join-Path $profileRoot 'Applications\NestLink'
$oldInstallRoot = Join-Path $localRoot 'Home Tunnel'
$receipt = Get-Content -LiteralPath $BuildReceipt -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $installerPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $receipt.installer_sha256) {
    throw 'Installer hash does not match the local build receipt.'
}
Add-Type -Path (Join-Path $PSScriptRoot 'local-path.cs')

# MSIX can redirect AppData writes while Explorer reads the original paths.
# Access original AppData through the local volume share when available, and
# clean only named product directories in Codex's redirected cache too.
$driveRoot = [IO.Path]::GetPathRoot($localRoot)
$physicalShare = '\\localhost\' + $driveRoot.Substring(0, 1) + '$'
$usePhysicalShare = Test-Path -LiteralPath $physicalShare
function Get-PhysicalAppDataPath([string]$path) {
    if (-not $usePhysicalShare) { return $path }
    if (-not $path.StartsWith($driveRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'AppData is not on the checked local volume.' }
    return Join-Path $physicalShare $path.Substring($driveRoot.Length)
}
$targets = @(
    [pscustomobject]@{ path = $installRoot; boundary = $profileRoot; install = $true },
    [pscustomobject]@{ path = (Get-PhysicalAppDataPath $oldInstallRoot); boundary = (Get-PhysicalAppDataPath $localRoot); install = $true }
)
$configurationNames = @('HomeDesk', 'Purslane Tech Pte. Ltd\HomeDesk', 'NestLink\NestLink')
foreach ($name in $configurationNames) {
    $targets += [pscustomobject]@{ path = (Get-PhysicalAppDataPath (Join-Path $roamingRoot $name)); boundary = (Get-PhysicalAppDataPath $roamingRoot); install = $false }
}
$virtualCaches = @(Get-ChildItem -LiteralPath (Join-Path $localRoot 'Packages') -Directory -Filter 'OpenAI.Codex_*' -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName 'LocalCache' } | Where-Object { Test-Path -LiteralPath $_ })
foreach ($cache in $virtualCaches) {
    $targets += [pscustomobject]@{ path = (Join-Path $cache 'Local\Home Tunnel'); boundary = $localRoot; install = $true }
    foreach ($name in $configurationNames) {
        $targets += [pscustomobject]@{ path = (Join-Path $cache ('Roaming\' + $name)); boundary = $localRoot; install = $false }
    }
}
if ($virtualCaches.Count -gt 0 -and -not $usePhysicalShare -and (Test-Path -LiteralPath (Join-Path $oldInstallRoot 'homedesk.exe'))) {
    $actualOldExecutable = [NestLinkInstallPaths]::ActualFilePath((Join-Path $oldInstallRoot 'homedesk.exe'))
    if (-not $actualOldExecutable.Equals((Join-Path $oldInstallRoot 'homedesk.exe'), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Original AppData cannot be verified through this redirected environment. Run this script from a normal PowerShell session.'
    }
}
$allowedTargets = @{}
foreach ($entry in $targets) {
    $target = [IO.Path]::GetFullPath($entry.path).TrimEnd('\')
    $boundary = [IO.Path]::GetFullPath($entry.boundary).TrimEnd('\')
    if (-not $target.StartsWith($boundary + '\', [StringComparison]::OrdinalIgnoreCase) -or $target -eq $boundary) {
        throw 'Cleanup path escaped its approved product directory.'
    }
    $allowedTargets[$target.ToLowerInvariant()] = $true
    $ancestor = $target
    while ($ancestor -and $ancestor -ne $boundary) {
        if (Test-Path -LiteralPath $ancestor) {
            if ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Refusing cleanup through a redirected filesystem folder.'
            }
        }
        $ancestor = [IO.Path]::GetDirectoryName($ancestor)
    }
}
if ($PlanOnly) {
    [ordered]@{ installer = $installerPath; cleanup = @($targets.path); fresh_configuration = $true; install = $installRoot } | ConvertTo-Json -Depth 4
    return
}

$installPrefixes = @($installRoot.TrimEnd('\') + '\', $oldInstallRoot.TrimEnd('\') + '\') + @(
    $targets | Where-Object { $_.install } | ForEach-Object { $_.path.TrimEnd('\') + '\' })
$ownedProcesses = @(Get-Process | Where-Object {
    $processPath = $_.Path
    $processPath -and @($installPrefixes | Where-Object { $processPath.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
})
foreach ($ownedProcess in $ownedProcesses) {
    if ($ownedProcess.MainWindowHandle -ne 0) { [void]$ownedProcess.CloseMainWindow() }
}
foreach ($ownedProcess in $ownedProcesses) {
    if (-not $ownedProcess.HasExited) { Stop-Process -Id $ownedProcess.Id -Force -ErrorAction SilentlyContinue }
    Wait-Process -Id $ownedProcess.Id -Timeout 15 -ErrorAction SilentlyContinue
}
$stamp = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, 'China Standard Time').ToString('yyyyMMdd-HHmmss')
$backupRoot = Join-Path $profileRoot ('.cache\NestLink-LocalBackups\' + $stamp)
New-Item -ItemType Directory -Path $backupRoot | Out-Null
$backups = @()
$index = 0
foreach ($entry in $targets) {
    $index++
    if (Test-Path -LiteralPath $entry.path) {
        $destination = Join-Path $backupRoot ('{0:D2}-{1}' -f $index, [IO.Path]::GetFileName($entry.path))
        Copy-Item -LiteralPath $entry.path -Destination $destination -Recurse
        $backups += [ordered]@{ original = $entry.path; backup = $destination }
    }
}
foreach ($entry in $targets | Where-Object { $_.install }) {
    $uninstaller = Join-Path $entry.path 'unins000.exe'
    if (Test-Path -LiteralPath $uninstaller) {
        $uninstallProcess = Start-Process -FilePath $uninstaller -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -WindowStyle Hidden -Wait -PassThru
        if ($uninstallProcess.ExitCode -ne 0) { throw "Previous uninstall failed: $($uninstallProcess.ExitCode). Backup: $backupRoot" }
    }
}
foreach ($entry in $targets) {
    $target = [IO.Path]::GetFullPath($entry.path).TrimEnd('\')
    if (-not $allowedTargets.ContainsKey($target.ToLowerInvariant())) { throw 'Cleanup path is not approved.' }
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    if (Test-Path -LiteralPath $target) { throw 'Old installation or configuration still exists.' }
}
$shortcutShell = New-Object -ComObject WScript.Shell
$shortcutFolders = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs'))
foreach ($folder in $shortcutFolders) {
    foreach ($shortcut in Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue) {
        $link = $shortcutShell.CreateShortcut($shortcut.FullName)
        if ($link.TargetPath -and @($installPrefixes | Where-Object { $link.TargetPath.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
            Remove-Item -LiteralPath $shortcut.FullName -Force
        }
    }
}
$installLog = Join-Path $backupRoot 'fresh-install.log'
$installArguments = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CURRENTUSER /TASKS=desktopicon /DIR="' + $installRoot + '" /LOG="' + $installLog + '"'
$installProcess = Start-Process -FilePath $installerPath -ArgumentList $installArguments -WindowStyle Hidden -Wait -PassThru
if ($installProcess.ExitCode -ne 0) { throw "Fresh install failed: $($installProcess.ExitCode). Backup: $backupRoot" }
$executable = Join-Path $installRoot 'homedesk.exe'
if (-not (Test-Path -LiteralPath $executable)) { throw 'Installed desktop executable is missing.' }
if (-not [NestLinkInstallPaths]::ActualFilePath($executable).Equals($executable, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Installation was redirected; Explorer would not be able to use this shortcut.'
}
$installPrefix = $installRoot.TrimEnd('\') + '\'
foreach ($entry in $receipt.payload_sha256.PSObject.Properties) {
    $installedFile = [IO.Path]::GetFullPath((Join-Path $installRoot $entry.Name))
    if (-not $installedFile.StartsWith($installPrefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid build receipt payload path.' }
    if ((Get-FileHash -LiteralPath $installedFile -Algorithm SHA256).Hash.ToLowerInvariant() -ne $entry.Value) {
        throw "Installed file does not match the local build: $($entry.Name)"
    }
}
if ((Get-Item -LiteralPath $executable).VersionInfo.ProductVersion -ne $receipt.version) { throw 'Installed version does not match the build receipt.' }
$desktopShortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'NestLink.lnk'
$desktopLink = $shortcutShell.CreateShortcut($desktopShortcut)
$iconFile = Join-Path $installRoot 'NestLink.ico'
if ($desktopLink.TargetPath -ne $executable -or $desktopLink.IconLocation -ne ($iconFile + ',0')) { throw 'Desktop shortcut does not reference the installed app and shared icon.' }
if (-not [NestLinkInstallPaths]::ActualFilePath($iconFile).Equals($iconFile, [StringComparison]::OrdinalIgnoreCase)) { throw 'Desktop icon path was redirected.' }
$report = [ordered]@{
    completed_at = $stamp; installer = $installerPath; install = $installRoot;
    old_install_and_configuration_removed = $true; cleanup = @($targets.path);
    backup = $backupRoot; backups = $backups;
    version = (Get-Item -LiteralPath $executable).VersionInfo.ProductVersion;
    payload_verified = $true; desktop_shortcut_verified = $true;
    actual_executable = [NestLinkInstallPaths]::ActualFilePath($executable)
}
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $backupRoot 'installation.json') -Encoding utf8
$report | ConvertTo-Json -Depth 6
if ($Launch) { Start-Process -FilePath $executable -WorkingDirectory $installRoot -WindowStyle Normal }
