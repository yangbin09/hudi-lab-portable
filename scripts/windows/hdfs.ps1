#Requires -Version 5.1
<#
.SYNOPSIS
    在 NameNode 容器内执行 hdfs 命令（宿主机无需安装 Hadoop）
.DESCRIPTION
    保留 hdfs 原始参数与退出码。
    位于 <repo>\transfer 下的 Windows 路径会自动映射为容器内 /transfer/...
.EXAMPLE
    .\scripts\windows\hdfs.ps1 dfs -ls /
    .\scripts\windows\hdfs.ps1 dfs -mkdir -p /warehouse
    .\scripts\windows\hdfs.ps1 dfs -put .\transfer\test.csv /datasets/
    .\scripts\windows\hdfs.ps1 dfsadmin -report
#>
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_common.ps1')

Initialize-DockerCli | Out-Null

if ($args.Count -eq 0) {
    Write-Host ''
    Write-Host '用法: .\scripts\windows\hdfs.ps1 <command> [args...]'
    Write-Host ''
    Write-Host '  .\scripts\windows\hdfs.ps1 dfs -ls /'
    Write-Host '  .\scripts\windows\hdfs.ps1 dfs -mkdir -p /warehouse'
    Write-Host '  .\scripts\windows\hdfs.ps1 dfs -put .\transfer\test.csv /datasets/'
    Write-Host '  .\scripts\windows\hdfs.ps1 dfsadmin -report'
    Write-Host '  .\scripts\windows\hdfs.ps1 fsck / -files -blocks'
    Write-Host ''
    exit 0
}

$st = Get-ServiceStatus 'namenode'
if ($st.State -ne 'running') {
    Write-Err 'NameNode 容器未运行。请先执行 .\scripts\windows\up.ps1'
    exit 1
}

$transferWin = Join-Path $script:RepoRoot 'transfer'
$transferNix = '/transfer'

function Convert-ToContainerPath {
    param([string]$Value)

    if ($Value -notmatch '^[A-Za-z]:[\\/]') { return $Value }

    $full = $null
    try { $full = [System.IO.Path]::GetFullPath($Value) } catch { return $Value }

    $root = $transferWin.TrimEnd('\')
    if ($full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        $rel = $full.Substring($root.Length).TrimStart('\', '/') -replace '\\', '/'
        if ([string]::IsNullOrEmpty($rel)) { return $transferNix }
        return "$transferNix/$rel"
    }

    Write-Host ''
    Write-Err "Windows 路径不在共享目录内，容器无法访问: $Value"
    Write-Host "  仅支持: $transferWin  (容器内为 $transferNix)" -ForegroundColor Yellow
    Write-Host '  请先把文件放入 transfer 目录再上传。' -ForegroundColor Yellow
    Write-Host ''
    exit 2
}

$forward = @()
foreach ($a in $args) { $forward += Convert-ToContainerPath $a }

& docker compose --project-directory $script:RepoRoot -f $script:ComposeFile exec -T namenode hdfs @forward
exit $LASTEXITCODE
