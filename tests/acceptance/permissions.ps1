# HOMEDESK: 仅本准备包运行目录的ACL；不读取密钥内容、不改变用户或系统信任。
param([Parameter(Mandatory=$true)][string]$AcceptanceDirectory, [ValidateSet('Secure','Check')][string]$Mode = 'Check')
$ErrorActionPreference = 'Stop'
$phase = 'scope'
try {
    $phase = 'base_path'
    $runtimeBase = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.runtime'))
    $phase = 'target_path'
    $target = [IO.Path]::GetFullPath($AcceptanceDirectory)
    $phase = 'scope'
    if ((Split-Path -Parent $target) -ne $runtimeBase -or
        (Split-Path -Leaf $target) -notmatch '^hd-portal-acceptance-[a-z0-9][a-z0-9_-]{0,48}$') { throw '范围不符' }
    $phase = 'principal'
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $allowed = @($sid.Value, 'S-1-5-18', 'S-1-5-32-544')
    $phase = 'directory_inventory'
    $entries = @((Get-Item -LiteralPath $target))
    $secretDir = Join-Path $target 'secrets'
    if (Test-Path -LiteralPath $secretDir) {
        $entries += Get-Item -LiteralPath $secretDir
        $entries += Get-ChildItem -LiteralPath $secretDir -Force
    }
    foreach ($entry in $entries) {
        $phase = 'construct_acl'
        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw '拒绝重解析点' }
        if ($Mode -eq 'Secure') {
            $phase = 'write_acl'
            # icacls只修改本项目DACL，保留原Owner；不请求恢复/SACL特权。
            & icacls.exe $entry.FullName /inheritance:r | Out-Null
            if ($LASTEXITCODE -ne 0) { throw '无法限制继承' }
            foreach ($rule in (Get-Acl -LiteralPath $entry.FullName).Access) {
                $identity = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
                if ($rule.AccessControlType -eq 'Allow' -and $identity -notin $allowed) {
                    & icacls.exe $entry.FullName /remove:g ('*' + $identity) | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw '无法移除多余访问' }
                }
            }
            $grant = '*' + $sid.Value + $(if ($entry.PSIsContainer) { ':(OI)(CI)F' } else { ':F' })
            & icacls.exe $entry.FullName /grant:r $grant | Out-Null
            if ($LASTEXITCODE -ne 0) { throw '无法保护本机访问' }
        }
        $phase = 'check_acl'
        $currentAcl = Get-Acl -LiteralPath $entry.FullName
        foreach ($rule in $currentAcl.Access) {
            $identity = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
            if ($rule.AccessControlType -eq 'Allow' -and $identity -notin $allowed) { throw '权限过宽' }
        }
    }
    Write-Output '{"safe":true,"scope":"acceptance_directory_only"}'
    exit 0
} catch {
    Write-Output ('{"safe":false,"scope":"acceptance_directory_only","phase":"' + $phase + '","error_type":"' + $_.Exception.GetType().Name + '"}')
    exit 1
}
