#Requires -Version 5.1
<#
.SYNOPSIS
    Hudi Lab Portable —— 删除本项目的容器、网络与数据卷（不可恢复）
.DESCRIPTION
    只操作 Compose 项目 hudi-lab-portable 的资源。
    不使用 docker volume prune / docker system prune。
    不会删除旧的 hudi-lab 环境。
#>
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot '_common.ps1')

try {
    Initialize-DockerCli | Out-Null

    Write-Section '即将删除的 hudi-lab-portable 资源'
    Write-Info 'Compose 项目: hudi-lab-portable'
    Write-Host ''

    Write-Info '容器:'
    & docker compose --project-directory $script:RepoRoot -f $script:ComposeFile ps -a --format '    {{.Name}}  {{.Status}}' | Out-Host

    Write-Info '数据卷:'
    & docker volume ls --filter 'name=hudi-lab-portable' --format '    {{.Name}}' | Out-Host

    Write-Info '网络:'
    & docker network ls --filter 'name=hudi-lab-portable' --format '    {{.Name}}' | Out-Host

    Write-Host ''
    Write-Host '  这会永久删除 HDFS 数据、Hudi 表、Spark warehouse 与 Derby 元数据。' -ForegroundColor Yellow
    Write-Host '  旧 hudi-lab 环境（hudi-namenode / hudi-datanode / hudi-spark）不受影响。' -ForegroundColor Yellow
    Write-Host ''
    $answer = Read-Host '  请输入完整确认字符串: DELETE HUDI LAB PORTABLE'

    if ($answer -cne 'DELETE HUDI LAB PORTABLE') {
        Write-Host ''
        Write-Warn '确认字符串不匹配，已退出，未删除任何内容。'
        exit 1
    }

    Write-Host ''
    if ((Invoke-Compose -ComposeArgs @('down', '--volumes', '--remove-orphans')) -ne 0) {
        throw 'docker compose down --volumes 失败'
    }

    Write-Ok '容器、网络与数据卷已删除'
    Write-Host ''
    Write-Host '  重新部署: .\scripts\windows\bootstrap.ps1' -ForegroundColor Gray
    Write-Host ''
    exit 0
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}
