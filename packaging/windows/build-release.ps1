# Builds the unified Windows x64 desktop package: home-tunnel-gui.exe + Agent.
param(
    [string]$Version = "8.0.0",
    [string]$WindRes = "",
    [string]$OutputDir = "",
    [string]$IsccPath = $env:HOME_TUNNEL_ISCC,
    [Parameter(Mandatory = $true)][string]$RemoteHostBuild
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$packagingDir = $PSScriptRoot
$clientDir = Split-Path -Parent (Split-Path -Parent $packagingDir)
$workspace = $clientDir
if (-not $IsccPath) { throw 'Set HOME_TUNNEL_ISCC or pass -IsccPath from install-inno-setup.ps1' }
if (-not $OutputDir) {
    $OutputDir = Join-Path $workspace "outputs\windows"
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$nativeRecord = Get-Content -Raw -LiteralPath $RemoteHostBuild | ConvertFrom-Json
$revision = (& git -C $clientDir rev-parse HEAD | Out-String).Trim()
if ($nativeRecord.version -ne $Version -or $nativeRecord.repository_revision -ne $revision -or $nativeRecord.target_os -ne 'win' -or $nativeRecord.target_cpu -ne 'x64' -or $nativeRecord.authorization_tests -ne 'passed') { throw 'Native worker build identity does not match this package' }
$nativeSource = $nativeRecord.executable
if (-not (Test-Path -LiteralPath $nativeSource -PathType Leaf) -or (Get-FileHash -LiteralPath $nativeSource -Algorithm SHA256).Hash.ToLowerInvariant() -ne $nativeRecord.sha256) { throw 'Native worker differs from its build record' }
$nativeNotices = Join-Path (Split-Path -Parent $RemoteHostBuild) 'LICENSE.md'
if (-not (Test-Path -LiteralPath $nativeNotices -PathType Leaf) -or (Get-FileHash -LiteralPath $nativeNotices -Algorithm SHA256).Hash.ToLowerInvariant() -ne $nativeRecord.notices_sha256) { throw 'Native dependency license bundle is missing or changed' }
$nativeSources = Join-Path (Split-Path -Parent $RemoteHostBuild) 'remote-source-manifest.json'
if (-not (Test-Path -LiteralPath $nativeSources -PathType Leaf) -or (Get-FileHash -LiteralPath $nativeSources -Algorithm SHA256).Hash.ToLowerInvariant() -ne $nativeRecord.source_manifest_sha256) { throw 'Native dependency source manifest is missing or changed' }
$serverLock = Get-Content -Raw -LiteralPath (Join-Path $clientDir 'tests/remote-native/server-lock.json') | ConvertFrom-Json

$agentScript = Join-Path $workspace "agent\build-agent.ps1"
$agentLines = if ($WindRes) {
    & $agentScript -WindRes $WindRes
} else {
    & $agentScript
}
$agentLines | ForEach-Object { Write-Host $_ }
$agentVersion = ($agentLines | Where-Object { $_ -like "AGENT_VERSION=*" } | Select-Object -First 1) -replace "^AGENT_VERSION=", ""
if ($agentVersion -notmatch '^\d+\.\d+\.\d+(?:-rc\.[1-9]\d*)?$') {
    throw "Agent version missing from build-agent.ps1"
}
$agentSha = ($agentLines | Where-Object { $_ -like "AGENT_SHA256=*" } | Select-Object -First 1) -replace "^AGENT_SHA256=", ""
if ($agentSha -notmatch "^[0-9a-f]{64}$") {
    throw "Agent SHA-256 missing from build-agent.ps1"
}
$agentSource = Join-Path $workspace "agent\assets\HomeTunnel.Agent.exe"
if (-not (Test-Path -LiteralPath $agentSource -PathType Leaf)) {
    throw "Agent executable was not produced"
}

$gui = Join-Path $OutputDir "home-tunnel-gui.exe"
$agent = Join-Path $OutputDir "home-tunnel-agent.exe"
$native = Join-Path $OutputDir 'home_tunnel_remote_host.exe'
Copy-Item -LiteralPath $agentSource -Destination $agent -Force
Copy-Item -LiteralPath $nativeSource -Destination $native -Force
Copy-Item -LiteralPath $nativeNotices -Destination (Join-Path $OutputDir 'WEBRTC-THIRD-PARTY-NOTICES.md') -Force
Copy-Item -LiteralPath $nativeSources -Destination (Join-Path $OutputDir 'remote-source-manifest.json') -Force
& (Join-Path $PSScriptRoot 'sign-release.ps1') -Files @($agent, $native)
# Signing changes the Agent bytes. Pin the shipped, signed bytes in the GUI.
$agentSha = (Get-FileHash -LiteralPath $agent -Algorithm SHA256).Hash.ToLowerInvariant()
$nativeSha = (Get-FileHash -LiteralPath $native -Algorithm SHA256).Hash.ToLowerInvariant()
& (Join-Path $PSScriptRoot 'build-gui.ps1') -Version $Version -OutputDir $OutputDir -WindRes $WindRes -AgentVersion $agentVersion -ExpectedAgentSHA256 $agentSha -ExpectedRemoteHostSHA256 $nativeSha
$nativeEvidence = [ordered]@{
    schema_version = 1
    version = $Version
    repository_revision = $revision
    worker = [ordered]@{ name = 'home_tunnel_remote_host.exe'; sha256 = $nativeSha; unsigned_sha256 = $nativeRecord.sha256 }
    abi_version = 1
    engine = [ordered]@{ revision = $nativeRecord.webrtc_revision; lock_sha256 = $nativeRecord.deps_lock_sha256 }
    server = [ordered]@{ repository = $serverLock.repository; revision = $serverLock.revision }
    build = [ordered]@{ source_modified = [bool]$nativeRecord.source_modified; authorization_tests = 'passed' }
    notices_sha256 = $nativeRecord.notices_sha256
    source_manifest_sha256 = $nativeRecord.source_manifest_sha256
}
[IO.File]::WriteAllText((Join-Path $OutputDir 'remote-host-provenance.json'), ($nativeEvidence | ConvertTo-Json -Depth 8) + [char]10, [Text.UTF8Encoding]::new($false))
$publicNativeBuild = $nativeRecord | Select-Object -Property * -ExcludeProperty executable
[IO.File]::WriteAllText((Join-Path $OutputDir 'remote-host-build.json'), ($publicNativeBuild | ConvertTo-Json -Depth 12) + [char]10, [Text.UTF8Encoding]::new($false))
& (Join-Path $PSScriptRoot 'sign-release.ps1') -Files @($gui)
$icon = Join-Path $workspace "agent\assets\HomeTunnel.ico"
Copy-Item -LiteralPath $icon -Destination (Join-Path $OutputDir "HomeTunnel.ico") -Force
if ($agentVersion -ne $Version) { throw 'Client and first-party Agent versions must match' }
# Include the payload's signing state inside the installer as well as the ZIP.
# The installer itself is recorded separately after its own signature is complete.
$signingEvidence = [ordered]@{
    version = $Version
    platform = 'windows'
    mode = $(if ($env:WINDOWS_SIGNING_PFX_BASE64) { 'authenticode-sha256-timestamped' } else { 'unsigned-no-certificate-configured' })
    files = @(@($agent, $gui, $native) | ForEach-Object { [ordered]@{
        name = [IO.Path]::GetFileName($_)
        sha256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
        signature_status = [string](Get-AuthenticodeSignature -LiteralPath $_).Status
    } })
}
[IO.File]::WriteAllText((Join-Path $OutputDir 'platform-signing.json'), ($signingEvidence | ConvertTo-Json -Depth 5) + [char]10, [Text.UTF8Encoding]::new($false))

$setupName = "HomeTunnel-Setup-$Version-x64.exe"
$setup = Join-Path $OutputDir $setupName
if (Test-Path -LiteralPath $setup) { Remove-Item -LiteralPath $setup -Force }
& (Join-Path $PSScriptRoot 'build-installer.ps1') -Version $Version -SourceDir $OutputDir -IsccPath $IsccPath
if (-not (Test-Path -LiteralPath $setup)) {
    throw "failed to produce $setup"
}
& (Join-Path $PSScriptRoot 'sign-release.ps1') -Files @($setup)
$sha = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText(
    "$setup.sha256",
    "$sha  $setupName" + [char]10,
    [Text.UTF8Encoding]::new($false)
)
Write-Host "SETUP=$setup"
Write-Host "SETUP_SHA256=$sha"
Write-Host "AGENT_SHA256=$agentSha"


$zipName = "HomeTunnel-Windows-$Version-x64.zip"
$zip = Join-Path $OutputDir $zipName
$signingEvidence = [ordered]@{
    version = $Version
    platform = 'windows'
    mode = $(if ($env:WINDOWS_SIGNING_PFX_BASE64) { 'authenticode-sha256-timestamped' } else { 'unsigned-no-certificate-configured' })
    files = @(@($agent, $gui, $native, $setup) | ForEach-Object { [ordered]@{
        name = [IO.Path]::GetFileName($_)
        sha256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
        signature_status = [string](Get-AuthenticodeSignature -LiteralPath $_).Status
    } })
}
[IO.File]::WriteAllText((Join-Path $OutputDir 'windows-platform-signing.json'), ($signingEvidence | ConvertTo-Json -Depth 5) + [char]10, [Text.UTF8Encoding]::new($false))
$packageFiles = @('home-tunnel-gui.exe', 'home-tunnel-agent.exe', 'home_tunnel_remote_host.exe', 'remote-host-provenance.json', 'remote-host-build.json', 'remote-source-manifest.json', 'WEBRTC-THIRD-PARTY-NOTICES.md', 'HomeTunnel.ico', 'LICENSE', 'LICENSE.txt', 'FRP-LICENSE.txt', 'THIRD-PARTY-NOTICES.txt', 'platform-signing.json', 'README.md', 'README.en.md', 'docs', 'contracts', 'packaging') | ForEach-Object { Join-Path $OutputDir $_ }
Compress-Archive -LiteralPath $packageFiles -DestinationPath $zip -Force
$zipSha = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$zip.sha256", "$zipSha  $zipName" + [char]10, [Text.UTF8Encoding]::new($false))
Write-Output "ZIP=$zip"
Write-Output "ZIP_SHA256=$zipSha"
