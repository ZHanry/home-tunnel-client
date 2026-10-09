$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
# HOMEDESK: GitHub-hosted native builds use the same fixed tools as local builds.
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:LIBCLANG_PATH = Join-Path $env:RUNNER_TEMP 'homedesk-clang\clang\native'
python -m pip install --disable-pip-version-check --target (Join-Path $env:RUNNER_TEMP 'homedesk-clang') libclang==14.0.6
if ($LASTEXITCODE -ne 0) { throw 'libclang installation failed' }
"LIBCLANG_PATH=$env:LIBCLANG_PATH" >> $env:GITHUB_ENV
"FLUTTER_SUPPRESS_ANALYTICS=true" >> $env:GITHUB_ENV
function Install-PinnedCargoTool([string]$Name, [string]$Version, [string[]]$ExtraArguments = @()) {
    # The cache can restore binaries without Cargo's installation metadata.
    $tool = Get-Command $Name -ErrorAction SilentlyContinue
    if ($tool) {
        $reported = & $tool.Source --version
        if ($LASTEXITCODE -eq 0 -and "$reported".Trim() -eq "$Name $Version") {
            Write-Output "Using cached $reported"
            return
        }
    }
    cargo install $Name --version $Version --locked --force @ExtraArguments
    if ($LASTEXITCODE -ne 0) { throw "$Name installation failed" }
}
Install-PinnedCargoTool 'cargo-expand' '1.0.95'
Install-PinnedCargoTool 'flutter_rust_bridge_codegen' '1.80.1' @('--features', 'uuid')
Push-Location client
try {
    # Cache the installation together with its patched source trees. A binary-
    # only restore cannot populate the corresponding-source release materials.
    $env:VCPKG_BINARY_SOURCES = 'clear'
    # FFmpeg is a host dependency in the upstream manifest. Rust links the
    # static triplet, so host and target must use the same installation layout.
    & "$env:VCPKG_ROOT\vcpkg.exe" install --triplet x64-windows-static --host-triplet x64-windows-static "--x-install-root=$env:VCPKG_ROOT/installed"
    if ($LASTEXITCODE -ne 0) { throw 'Native dependency build failed' }
    if (!(Test-Path "$env:VCPKG_ROOT/installed/x64-windows-static/include/libavcodec/avcodec.h")) {
        throw 'FFmpeg headers are missing from the static triplet'
    }
} finally { Pop-Location }
