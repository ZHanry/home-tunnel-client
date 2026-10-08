$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
# HOMEDESK: GitHub-hosted native builds use the same fixed tools as local builds.
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:LIBCLANG_PATH = Join-Path $env:RUNNER_TEMP 'homedesk-clang\clang\native'
python -m pip install --disable-pip-version-check --target (Join-Path $env:RUNNER_TEMP 'homedesk-clang') libclang==14.0.6
if ($LASTEXITCODE -ne 0) { throw 'libclang installation failed' }
"LIBCLANG_PATH=$env:LIBCLANG_PATH" >> $env:GITHUB_ENV
"FLUTTER_SUPPRESS_ANALYTICS=true" >> $env:GITHUB_ENV
cargo install cargo-expand --version 1.0.95 --locked
if ($LASTEXITCODE -ne 0) { throw 'cargo-expand installation failed' }
cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid --locked
if ($LASTEXITCODE -ne 0) { throw 'FRB installation failed' }
Push-Location client
try {
    & "$env:VCPKG_ROOT\vcpkg.exe" install --triplet x64-windows-static "--x-install-root=$env:VCPKG_ROOT/installed"
    if ($LASTEXITCODE -ne 0) { throw 'Native dependency build failed' }
} finally { Pop-Location }
