$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -ne 'true' -or -not $env:RUNNER_TEMP) { throw 'Capture requires an isolated GitHub-hosted Windows runner' }
$output = Join-Path $PWD 'outputs/windows-ui'
New-Item -ItemType Directory -Force $output | Out-Null
$root = Join-Path $env:RUNNER_TEMP 'home-tunnel-v10-docs'
New-Item -ItemType Directory $root | Out-Null
$expectedArchive = '54dd75d7261000eab6e01c747e5e4545790f006b13646d892c01cb169ce85e34'
$archive = Join-Path $root 'client.zip'
$url = 'https://github.com/ZHanry/home-tunnel-client/releases/download/v10.0.0/HomeTunnel-Windows-10.0.0-x64.zip'
Invoke-WebRequest -Uri $url -OutFile $archive
if ((Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedArchive) { throw 'Published v10 archive hash mismatch' }
Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $root 'package')
$gui = @(Get-ChildItem (Join-Path $root 'package') -Recurse -Filter home-tunnel-gui.exe)
if ($gui.Count -ne 1) { throw 'Expected one released GUI executable' }
$version = [Diagnostics.FileVersionInfo]::GetVersionInfo($gui[0].FullName).ProductVersion
if ($version -ne '10.0.0') { throw "Unexpected GUI version: $version" }
$report = [ordered]@{
    schema_version = 1; version = $version; status = 'pending'
    capture_revision = $env:GITHUB_SHA; run_id = $env:GITHUB_RUN_ID
    package_url = $url; package_sha256 = $expectedArchive
    gui_sha256 = (Get-FileHash $gui[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    os = [Environment]::OSVersion.VersionString
    interactive = [Environment]::UserInteractive
    session_id = [Diagnostics.Process]::GetCurrentProcess().SessionId
    fixture = 'Official v10.0.0 portable GUI, empty isolated state, no account or remote connection'
    capture_method = 'Win32 foreground native window bounds and System.Drawing CopyFromScreen'
    full_remote_session_acceptance = $false
}
$process = $null
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
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int state);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out RECT rectangle);
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] public static extern bool PostThreadMessage(uint thread, uint message, UIntPtr wparam, IntPtr lparam);
    public static IntPtr FindWindow(uint process) {
        IntPtr found=IntPtr.Zero;
        EnumWindows((window, parameter) => {
            uint owner; GetWindowThreadProcessId(window,out owner);
            var name=new StringBuilder(256); GetClassName(window,name,256);
            if(owner==process && name.ToString()=="webview") { found=window; return false; }
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
    Start-Sleep -Seconds 8
    if ([HomeTunnelDocWindow]::GetForegroundWindow() -ne $window) { throw 'Native GUI is not foreground; refuse unrelated desktop pixels' }
    $rectangle = [HomeTunnelDocWindow+RECT]::new()
    if (-not [HomeTunnelDocWindow]::GetWindowRect($window,[ref]$rectangle)) { throw 'Native window bounds unavailable' }
    $width = $rectangle.Right-$rectangle.Left; $height = $rectangle.Bottom-$rectangle.Top
    if ($width -lt 600 -or $height -lt 400 -or $width -gt 4096 -or $height -gt 2160) { throw 'Unexpected native window dimensions' }
    $bitmap = [Drawing.Bitmap]::new($width,$height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($rectangle.Left,$rectangle.Top,0,0,[Drawing.Size]::new($width,$height))
        $colors = [Collections.Generic.HashSet[int]]::new()
        for($y=0;$y -lt $height;$y+=11) { for($x=0;$x -lt $width;$x+=11) { $colors.Add($bitmap.GetPixel($x,$y).ToArgb()) | Out-Null } }
        if($colors.Count -lt 24) { throw 'Blank or incomplete rendered screenshot; refusing to claim capture' }
        $image = Join-Path $output 'windows-v10-signin.png'
        $bitmap.Save($image,[Drawing.Imaging.ImageFormat]::Png)
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
    $report.width=$width; $report.height=$height
    $report.screenshot_sha256=(Get-FileHash $image -Algorithm SHA256).Hash.ToLowerInvariant()
    $report.captured_at=(Get-Date).ToUniversalTime().ToString('o')
    $report.status='captured-pending-visual-review'
    [HomeTunnelDocWindow]::Quit($window)
    if(-not $process.WaitForExit(15000)) { throw 'GUI did not close cleanly' }
} catch {
    $report.status='failed'; $report.error=$_.Exception.Message; throw
} finally {
    if($process -and -not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
    $report | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $output 'capture.json') -Encoding utf8NoBOM
}
