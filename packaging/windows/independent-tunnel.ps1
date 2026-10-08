param(
    [ValidateSet('install', 'start', 'stop', 'uninstall')][string]$Action = 'install',
    [string]$StatePath = ''
)
# HOMEDESK: An explicitly enrolled standalone CLI runs independently of the GUI Job.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$taskName = 'HomeDesk Independent Tunnel'
if ($Action -eq 'stop') { Stop-ScheduledTask -TaskName $taskName; exit }
if ($Action -eq 'start') { Start-ScheduledTask -TaskName $taskName; exit }
if ($Action -eq 'uninstall') {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    exit
}
if (-not $StatePath) { throw 'Specify the standalone CLI state file created by enroll --state; GUI credentials are not reused.' }
$stateFile = Get-Item -LiteralPath $StatePath
if ($stateFile.PSIsContainer -or ($stateFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'State must be a regular file' }
$cli = Join-Path $PSScriptRoot 'home-tunnel-client.exe'
$agent = Join-Path $PSScriptRoot 'home-tunnel-agent.exe'
if (-not (Test-Path -LiteralPath $cli) -or -not (Test-Path -LiteralPath $agent)) { throw 'Keep this script beside the release CLI and locked Agent' }
$arguments = 'run --state "' + $stateFile.FullName + '" --agent "' + $agent + '"'
$account = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$scheduledAction = New-ScheduledTaskAction -Execute $cli -Argument $arguments -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $account
$settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId $account -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $scheduledAction -Trigger $trigger -Settings $settings -Principal $principal -Description 'Explicitly enrolled tunnel; remains active after HomeDesk closes' | Out-Null
Start-ScheduledTask -TaskName $taskName
Write-Output 'Independent tunnel starts at sign-in. Closing HomeDesk does not stop this task.'
