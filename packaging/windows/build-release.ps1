# Builds the unified Windows x64 desktop package: home-tunnel-gui.exe + Agent.
param(
    [string]$Version = "7.0.0",
    [string]$WindRes = "",
    [string]$OutputDir = "",
    [string]$IsccPath = $env:HOME_TUNNEL_ISCC
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

$agentScript = Join-Path $workspace "agent\build-agent.ps1"
$agentLines = if ($WindRes) {
    & $agentScript -WindRes $WindRes
} else {
    & $agentScript
}
$agentLines | ForEach-Object { Write-Host $_ }
$agentVersion = ($agentLines | Where-Object { $_ -like "AGENT_VERSION=*" } | Select-Object -First 1) -replace "^AGENT_VERSION=", ""
if ($agentVersion -notmatch "^\d+\.\d+\.\d+$") {
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
Copy-Item -LiteralPath $agentSource -Destination $agent -Force
& (Join-Path $PSScriptRoot 'sign-release.ps1') -Files @($agent)
# Signing changes the Agent bytes. Pin the shipped, signed bytes in the GUI.
$agentSha = (Get-FileHash -LiteralPath $agent -Algorithm SHA256).Hash.ToLowerInvariant()
& (Join-Path $PSScriptRoot 'build-gui.ps1') -Version $Version -OutputDir $OutputDir -WindRes $WindRes -AgentVersion $agentVersion -ExpectedAgentSHA256 $agentSha
& (Join-Path $PSScriptRoot 'sign-release.ps1') -Files @($gui)
$icon = Join-Path $workspace "agent\assets\HomeTunnel.ico"
Copy-Item -LiteralPath $icon -Destination (Join-Path $OutputDir "HomeTunnel.ico") -Force

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
    files = @(@($agent, $gui, $setup) | ForEach-Object { [ordered]@{
        name = [IO.Path]::GetFileName($_)
        sha256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
        signature_status = [string](Get-AuthenticodeSignature -LiteralPath $_).Status
    } })
}
[IO.File]::WriteAllText((Join-Path $OutputDir 'platform-signing.json'), ($signingEvidence | ConvertTo-Json -Depth 5) + [char]10, [Text.UTF8Encoding]::new($false))
$packageFiles = @('home-tunnel-gui.exe', 'home-tunnel-agent.exe', 'HomeTunnel.ico', 'LICENSE.txt', 'FRP-LICENSE.txt', 'THIRD-PARTY-NOTICES.txt', 'platform-signing.json') | ForEach-Object { Join-Path $OutputDir $_ }
Compress-Archive -LiteralPath $packageFiles -DestinationPath $zip -Force
$zipSha = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$zip.sha256", "$zipSha  $zipName" + [char]10, [Text.UTF8Encoding]::new($false))
Write-Output "ZIP=$zip"
Write-Output "ZIP_SHA256=$zipSha"
