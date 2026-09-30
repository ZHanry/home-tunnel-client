param(
    [string]$ArchivePath = '',
    [string]$ExpectedSHA256 = '',
    [string]$ExpectedVersion = '',
    [string]$OutputDirectory = 'outputs/windows-ui',
    [switch]$Regression
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:RUNNER_ENVIRONMENT -ne 'github-hosted' -or -not $env:RUNNER_TEMP) { throw 'Capture requires an isolated GitHub-hosted Windows runner' }
$output = [IO.Path]::GetFullPath((Join-Path $PWD $OutputDirectory))
New-Item -ItemType Directory -Force $output | Out-Null
$root = Join-Path $env:RUNNER_TEMP ('home-tunnel-ui-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $root | Out-Null
$releasedMode = -not $ArchivePath
if ($releasedMode) {
    if ($Regression -or $ExpectedSHA256 -or $ExpectedVersion) { throw 'Released-v10 mode does not accept candidate or regression parameters' }
    $ExpectedSHA256 = '54dd75d7261000eab6e01c747e5e4545790f006b13646d892c01cb169ce85e34'
    $ExpectedVersion = '10.0.0'
    $archive = Join-Path $root 'client.zip'
    $url = 'https://github.com/ZHanry/home-tunnel-client/releases/download/v10.0.0/HomeTunnel-Windows-10.0.0-x64.zip'
    Invoke-WebRequest -Uri $url -OutFile $archive
} else {
    if ($ExpectedSHA256 -cnotmatch '^[0-9a-f]{64}$' -or $ExpectedVersion -notmatch '^\d+\.\d+\.\d+(?:-rc\.[1-9]\d*)?$') { throw 'Candidate capture requires an exact archive SHA-256 and version' }
    $archive = (Resolve-Path -LiteralPath $ArchivePath).Path
    $url = $null
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedSHA256) { throw 'Input package archive hash mismatch' }
Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $root 'package')
$gui = @(Get-ChildItem (Join-Path $root 'package') -Recurse -Filter home-tunnel-gui.exe)
if ($gui.Count -ne 1) { throw 'Expected one packaged GUI executable' }
$version = [Diagnostics.FileVersionInfo]::GetVersionInfo($gui[0].FullName).ProductVersion
if ($version -ne $ExpectedVersion) { throw "Unexpected GUI version: $version" }
$report = [ordered]@{
    schema_version = 1; version = $version; status = 'pending'
    capture_revision = $env:GITHUB_SHA; run_id = $env:GITHUB_RUN_ID
    package_revision = $(if ($env:HT_WINDOWS_UI_SOURCE_REVISION) { $env:HT_WINDOWS_UI_SOURCE_REVISION } else { $env:GITHUB_SHA })
    package_url = $url; package_sha256 = $ExpectedSHA256
    gui_sha256 = (Get-FileHash $gui[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    os = [Environment]::OSVersion.VersionString
    interactive = [Environment]::UserInteractive
    session_id = [Diagnostics.Process]::GetCurrentProcess().SessionId
    fixture = $(if ($Regression) { 'Final packaged GUI with explicit local-API fixtures; no real account or remote connection' } else { 'Pinned portable GUI, empty isolated state, no account or remote connection' })
    regression = [bool]$Regression
    screenshots = @()
    capture_method = 'Win32 foreground native window bounds and System.Drawing CopyFromScreen'
    full_remote_session_acceptance = $false
}
$process = $null
$qaProcess = $null
try {
    if (-not $report.interactive -or $report.session_id -eq 0) { throw 'Runner has no interactive user desktop; no screenshot claimed' }
    Add-Type -AssemblyName System.Drawing
    Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class HomeTunnelDocWindow {
    public struct RECT { public int Left, Top, Right, Bottom; }
    public delegate bool WindowCallback(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")] public static extern bool EnumWindows(WindowCallback callback, IntPtr parameter);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr window, StringBuilder name, int count);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int state);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr window, int x, int y, int width, int height, bool repaint);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr window, int attribute, out RECT rectangle, int size);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out RECT rectangle);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] public static extern bool PostThreadMessage(uint thread, uint message, UIntPtr wparam, IntPtr lparam);
    public static IntPtr FindWindow(uint process) {
        IntPtr found=IntPtr.Zero;
        EnumWindows((window, parameter) => {
            uint owner; GetWindowThreadProcessId(window,out owner);
            var name=new StringBuilder(256); GetClassName(window,name,256);
            if(owner==process && IsWindowVisible(window) && name.ToString()=="webview") { found=window; return false; }
            return true;
        },IntPtr.Zero);
        return found;
    }
    public static void Quit(IntPtr window) {
        uint process; var thread=GetWindowThreadProcessId(window,out process);
        PostThreadMessage(thread,0x0012,UIntPtr.Zero,IntPtr.Zero);
    }
}
'@
    [HomeTunnelDocWindow]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
    $env:HOME_TUNNEL_STATE_PATH = Join-Path $root 'isolated-state/state.json'
    $env:WEBVIEW2_USER_DATA_FOLDER = Join-Path $root 'webview2-profile'
    $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS = '--remote-debugging-port=9223'
    $report.browser_arguments = $env:WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS
    $process = Start-Process -FilePath $gui[0].FullName -WorkingDirectory $gui[0].DirectoryName -WindowStyle Normal -PassThru
    $deadline = (Get-Date).AddSeconds(45)
    $window = [IntPtr]::Zero
    do {
        if ($process.HasExited) { throw 'Released GUI exited before creating its native window' }
        $window = [HomeTunnelDocWindow]::FindWindow([uint32]$process.Id)
        if ($window -ne [IntPtr]::Zero) { break }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)
    if ($window -eq [IntPtr]::Zero) { throw 'No native WebView2 window found' }
    [HomeTunnelDocWindow]::ShowWindow($window,9) | Out-Null
    [HomeTunnelDocWindow]::SetForegroundWindow($window) | Out-Null
    $env:HT_WINDOWS_UI_OUTPUT = $output
    node scripts/wait-windows-ui.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Released WebView2 did not render its actual application DOM' }
    function Save-NativeCapture([string]$Name) {
        if ($Name -cnotmatch '^[a-z0-9][a-z0-9-]{0,90}\.png$') { throw 'Unsafe screenshot filename' }
        [HomeTunnelDocWindow]::ShowWindow($window,9) | Out-Null
        [HomeTunnelDocWindow]::SetForegroundWindow($window) | Out-Null
        Start-Sleep -Milliseconds 600
        if ([HomeTunnelDocWindow]::GetForegroundWindow() -ne $window) { throw 'Native GUI is not foreground; refuse unrelated desktop pixels' }
        $rectangle = [HomeTunnelDocWindow+RECT]::new()
        if (-not [HomeTunnelDocWindow]::GetWindowRect($window,[ref]$rectangle)) { throw 'Native window bounds unavailable' }
        if ([HomeTunnelDocWindow]::DwmGetWindowAttribute($window,9,[ref]$rectangle,16) -ne 0) { throw 'Visible window frame bounds unavailable' }
        $width = $rectangle.Right-$rectangle.Left; $height = $rectangle.Bottom-$rectangle.Top
        if ($width -lt 600 -or $height -lt 400 -or $width -gt 4096 -or $height -gt 2160) { throw 'Unexpected native window dimensions' }
        $bitmap = [Drawing.Bitmap]::new($width,$height)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.CopyFromScreen($rectangle.Left,$rectangle.Top,0,0,[Drawing.Size]::new($width,$height))
            $colors = [Collections.Generic.HashSet[int]]::new()
            for($y=35;$y -lt ($height-20);$y+=7) { for($x=16;$x -lt ($width-16);$x+=7) { $colors.Add($bitmap.GetPixel($x,$y).ToArgb()) | Out-Null } }
            if($colors.Count -lt 24) { throw 'Blank or incomplete rendered screenshot; refusing to claim capture' }
            $image = Join-Path $output $Name
            $bitmap.Save($image,[Drawing.Imaging.ImageFormat]::Png)
        } finally { $graphics.Dispose(); $bitmap.Dispose() }
        return [ordered]@{ file = $Name; width = $width; height = $height; sha256 = (Get-FileHash $image -Algorithm SHA256).Hash.ToLowerInvariant(); captured_at = (Get-Date).ToUniversalTime().ToString('o') }
    }
    Start-Sleep -Seconds 3
    $first = Save-NativeCapture $(if ($releasedMode) { 'windows-v10-signin.png' } else { 'windows-candidate-signin.png' })
    $report.screenshots += $first
    $report.width = $first.width; $report.height = $first.height
    $report.screenshot_sha256 = $first.sha256; $report.captured_at = $first.captured_at
    if ($Regression) {
        $bridge = Join-Path $root 'bridge'
        New-Item -ItemType Directory -Path $bridge | Out-Null
        $env:HT_WINDOWS_UI_BRIDGE = $bridge
        $env:HT_WINDOWS_UI_OUTPUT = $output
        $env:HT_WINDOWS_UI_VERSION = $ExpectedVersion
        $env:HT_WINDOWS_UI_ARCHIVE_SHA256 = $ExpectedSHA256
        $qaProcess = Start-Process node -ArgumentList 'scripts/test-windows-packaged-ui.mjs' -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path $root 'qa.stdout') -RedirectStandardError (Join-Path $root 'qa.stderr')
        $deadline = (Get-Date).AddMinutes(8)
        $last = 0
        while (-not $qaProcess.HasExited) {
            if ((Get-Date) -gt $deadline) { throw 'Packaged UI regression timed out' }
            $requestFile = Join-Path $bridge 'request.json'
            if (Test-Path -LiteralPath $requestFile) {
                $command = Get-Content -Raw -LiteralPath $requestFile | ConvertFrom-Json
                if ($command.id -gt $last) {
                    $last = $command.id
                    if ($command.action -eq 'resize') {
                        if ($command.width -lt 960 -or $command.width -gt 1600 -or $command.height -lt 640 -or $command.height -gt 1000) { throw 'Invalid regression window dimensions' }
                        if (-not [HomeTunnelDocWindow]::MoveWindow($window,0,0,$command.width,$command.height,$true)) { throw 'Native window resize failed' }
                        Start-Sleep -Milliseconds 600
                    } elseif ($command.action -eq 'capture') {
                        $shot = Save-NativeCapture $command.name
                        $report.screenshots += $shot
                    } else { throw 'Unknown regression bridge command' }
                    $response = @{id=$last; status='done'} | ConvertTo-Json -Compress
                    $response | Set-Content (Join-Path $bridge 'response.tmp') -Encoding utf8NoBOM
                    Move-Item -Force (Join-Path $bridge 'response.tmp') (Join-Path $bridge 'response.json')
                }
            }
            Start-Sleep -Milliseconds 100
            $qaProcess.Refresh()
        }
        $qaProcess.WaitForExit()
        # Do not upload process output: Playwright failures may include private URLs.
        if ($qaProcess.ExitCode -ne 0) { throw 'Packaged UI regression failed; inspect the sanitized regression.json report' }
        $regressionReport = Get-Content -Raw (Join-Path $output 'regression.json') | ConvertFrom-Json
        if ($regressionReport.status -ne 'passed' -or $regressionReport.package_sha256 -ne $ExpectedSHA256) { throw 'Packaged UI regression report is missing or mismatched' }
        $report.regression_status = 'passed'
    }
    $report.status='captured-pending-visual-review'
    [HomeTunnelDocWindow]::Quit($window)
    if(-not $process.WaitForExit(15000)) { throw 'GUI did not close cleanly' }
} catch {
    $report.status='failed'; $report.error=$_.Exception.Message; throw
} finally {
    if($qaProcess -and -not $qaProcess.HasExited) { $qaProcess.Kill(); $qaProcess.WaitForExit() }
    if($process -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    $report | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $output 'capture.json') -Encoding utf8NoBOM
}
