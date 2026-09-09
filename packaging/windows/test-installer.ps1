param(
    [Parameter(Mandatory = $true)][string]$Installer,
    [Parameter(Mandatory = $true)][string]$PayloadDirectory,
    [Parameter(Mandatory = $true)][string]$Version,
    [Parameter(Mandatory = $true)][string]$ReportPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:GITHUB_ACTIONS -ne 'true' -or -not $env:RUNNER_TEMP) { throw 'Installer lifecycle checks must run on an isolated GitHub runner' }
$runnerRoot = [IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\') + '\'
$destination = [IO.Path]::GetFullPath((Join-Path $runnerRoot "home-tunnel-install-$Version"))
if (-not $destination.StartsWith($runnerRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid smoke installation path' }
if (Test-Path -LiteralPath $destination) { throw 'Smoke installation path already exists' }
$arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', "/DIR=`"$destination`"")
$process = Start-Process -FilePath $Installer -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Installer exited with $($process.ExitCode)" }
foreach ($name in @('home-tunnel-gui.exe', 'home-tunnel-agent.exe', 'LICENSE.txt', 'FRP-LICENSE.txt', 'THIRD-PARTY-NOTICES.txt')) {
    $installed = (Get-FileHash -LiteralPath (Join-Path $destination $name) -Algorithm SHA256).Hash
    $expected = (Get-FileHash -LiteralPath (Join-Path $PayloadDirectory $name) -Algorithm SHA256).Hash
    if ($installed -ne $expected) { throw "Installed payload mismatch: $name" }
}
if (Test-Path -LiteralPath (Join-Path $destination 'uninstall.cmd')) { throw 'Legacy batch uninstaller must not be installed' }
$gui = Join-Path $destination 'home-tunnel-gui.exe'
Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class HomeTunnelIconProbe {
    [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
    public static extern uint ExtractIconEx(string file, int index, IntPtr large, IntPtr small, uint count);
    public delegate bool WindowCallback(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")] public static extern bool EnumWindows(WindowCallback callback, IntPtr parameter);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr window, StringBuilder name, int count);
    [DllImport("user32.dll", EntryPoint="GetClassLongPtrW")] public static extern IntPtr GetClassLongPtr(IntPtr window, int index);
    [DllImport("user32.dll")] public static extern bool PostThreadMessage(uint thread, uint message, UIntPtr wparam, IntPtr lparam);
    public static IntPtr FindWindow(uint process) {
        IntPtr found=IntPtr.Zero;
        EnumWindows((window, parameter) => {
            uint owner; GetWindowThreadProcessId(window, out owner);
            var name=new StringBuilder(256); GetClassName(window,name,256);
            if (owner==process && name.ToString()=="webview") { found=window; return false; }
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
if ([HomeTunnelIconProbe]::ExtractIconEx($gui, -1, [IntPtr]::Zero, [IntPtr]::Zero, 0) -lt 1) { throw 'Installed GUI has no embedded Windows application icon' }
if ([Diagnostics.FileVersionInfo]::GetVersionInfo($gui).ProductVersion -ne $Version) { throw 'GUI version resources are missing or incorrect' }
$reader = [IO.BinaryReader]::new([IO.File]::OpenRead($gui))
try {
    $reader.BaseStream.Position = 0x3c
    $peOffset = $reader.ReadInt32()
    $reader.BaseStream.Position = $peOffset + 24 + 68
    if ($reader.ReadUInt16() -ne 2) { throw 'Desktop executable must use the Windows GUI subsystem' }
} finally { $reader.Dispose() }
$guiProcess = Start-Process -FilePath $gui -WindowStyle Hidden -PassThru
try {
    $window = [IntPtr]::Zero
    $deadline = (Get-Date).AddSeconds(30)
    do {
        $window = [HomeTunnelIconProbe]::FindWindow([uint32]$guiProcess.Id)
        if ($window -ne [IntPtr]::Zero) { break }
        if ($guiProcess.HasExited) { throw 'Native GUI exited before creating its window' }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)
    if ($window -eq [IntPtr]::Zero) { throw 'Native GUI window did not appear' }
    if ([HomeTunnelIconProbe]::GetClassLongPtr($window,-14) -eq [IntPtr]::Zero -or [HomeTunnelIconProbe]::GetClassLongPtr($window,-34) -eq [IntPtr]::Zero) { throw 'Native window is missing its large or small application icon' }
    [HomeTunnelIconProbe]::Quit($window)
    if (-not $guiProcess.WaitForExit(15000)) { throw 'Native GUI did not exit cleanly' }
} finally {
    if (-not $guiProcess.HasExited) { $guiProcess.Kill(); $guiProcess.WaitForExit() }
}
$uninstaller = Join-Path $destination 'unins000.exe'
if (-not (Test-Path -LiteralPath $uninstaller -PathType Leaf)) { throw 'Native uninstaller is missing' }
$process = Start-Process -FilePath $uninstaller -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -WindowStyle Hidden -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Uninstaller exited with $($process.ExitCode)" }
foreach ($name in @('home-tunnel-gui.exe', 'home-tunnel-agent.exe')) {
    if (Test-Path -LiteralPath (Join-Path $destination $name)) { throw "Uninstall left $name behind" }
}
$report = @{ schema_version = 1; status = 'passed'; version = $Version; repository_revision = $env:GITHUB_SHA; installer_sha256 = (Get-FileHash -LiteralPath $Installer -Algorithm SHA256).Hash.ToLowerInvariant(); install = 'passed'; payload_hashes = 'passed'; uninstall = 'passed'; embedded_icon = 'passed'; gui_subsystem = 'passed'; native_window_icon = 'passed' }
[IO.File]::WriteAllText([IO.Path]::GetFullPath($ReportPath), ($report | ConvertTo-Json) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
