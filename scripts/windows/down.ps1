#Requires -Version 5.1
<#
.SYNOPSIS
    Hudi Lab Portable —— 停止并移除容器，保留所有数据卷
#>
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot '_common.ps1')

try {
    Initialize-DockerCli | Out-Null
    Write-Section '停止 Hudi Lab Portable'

    if ((Invoke-Compose -ComposeArgs @('down')) -ne 0) {
        throw 'docker compose down 失败'
    }

    Write-Ok '容器与项目网络已移除'
    Write-Ok '数据卷保留：namenode-data / datanode-data / spark-warehouse / spark-metastore'
    Write-Host ''
    Write-Host '  重新启动: .\scripts\windows\up.ps1' -ForegroundColor Gray
    Write-Host '  彻底删除: .\scripts\windows\destroy.ps1' -ForegroundColor Gray
    Write-Host ''
    exit 0
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}
