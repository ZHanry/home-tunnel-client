# HOMEDESK: 原生下载回退，仅接收固定官方发行URL及本准备包运行目录。
param([Parameter(Mandatory=$true)][string]$Uri, [Parameter(Mandatory=$true)][string]$Destination)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
    $parsed = [Uri]$Uri
    $runtimeBase = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.runtime'))
    $target = [IO.Path]::GetFullPath($Destination)
    $artifactDir = Split-Path -Parent $target
    $runDir = Split-Path -Parent $artifactDir
    if ($parsed.Scheme -ne 'https' -or $parsed.Host -ne 'github.com' -or $parsed.Query -or $parsed.Fragment -or
        $parsed.AbsolutePath -notmatch '^/ZHanry/home-tunnel-(server|client)/releases/download/v10\.1\.0/[a-zA-Z0-9_.-]+$' -or
        (Split-Path -Leaf $artifactDir) -ne 'artifacts' -or (Split-Path -Leaf $runDir) -notmatch '^hd-portal-acceptance-[a-z0-9][a-z0-9_-]{0,48}$' -or
        (Split-Path -Parent $runDir) -ne $runtimeBase -or (Test-Path -LiteralPath $target)) {
        throw '范围不符'
    }
    Invoke-WebRequest -UseBasicParsing -Uri $parsed.AbsoluteUri -OutFile $target -TimeoutSec 60
    exit 0
} catch {
    # 不回显签名下载URL、工具异常全文或任何凭据。
    Write-Output '原生下载未完成，未输出响应内容。'
    exit 1
}
