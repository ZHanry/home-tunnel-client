# 使用普通目录 Junction 准备 Flutter 插件，不修改 Windows 开发者模式。
param([string]$ProjectRoot = (Resolve-Path "$PSScriptRoot/../..").Path)
$ErrorActionPreference = 'Stop'
$flutterRoot = Join-Path $ProjectRoot 'client/flutter'
$metadata = Get-Content -LiteralPath (Join-Path $flutterRoot '.flutter-plugins-dependencies') -Raw | ConvertFrom-Json
$cacheRoot = if ($env:PUB_CACHE) { [IO.Path]::GetFullPath($env:PUB_CACHE) } else { Join-Path $env:LOCALAPPDATA 'Pub/Cache' }
$cachePrefix = $cacheRoot.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
$count = 0
# Flutter 在 Windows 构建时仍会处理已启用的 Linux 桌面插件目录。
foreach ($platform in @('windows', 'linux')) {
  if (!(Test-Path -LiteralPath (Join-Path $flutterRoot $platform))) { continue }
  $linkRoot = [IO.Path]::GetFullPath((Join-Path $flutterRoot "$platform/flutter/ephemeral/.plugin_symlinks"))
  New-Item -ItemType Directory -Path $linkRoot -Force | Out-Null
  foreach ($plugin in $metadata.plugins.$platform) {
    if ($plugin.name -notmatch '^[a-z0-9_]+$') { throw '插件名无效' }
    $target = [IO.Path]::GetFullPath($plugin.path)
    if (!$target.StartsWith($cachePrefix, [StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $target -PathType Container)) {
        throw "插件 $($plugin.name) 不在已安装的 Pub 缓存中"
    }
    $link = Join-Path $linkRoot $plugin.name
    if (Test-Path -LiteralPath $link) {
        $item = Get-Item -LiteralPath $link -Force
        if (!$item.LinkType -or [IO.Path]::GetFullPath([string]$item.Target).TrimEnd('\','/') -ne $target.TrimEnd('\','/')) {
            throw "插件 $($plugin.name) 的现有路径与依赖记录不符；请检查该路径"
        }
    } else {
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
    }
    $count++
  }
}
Write-Output "已核对 $count 个桌面插件链接。后续使用 flutter build windows --no-pub。"
