#Requires -Version 5.1
<#
.SYNOPSIS
    Hudi Lab Portable —— 启动全部服务（幂等，不删除数据）
#>
[CmdletBinding()]
param([int]$TimeoutSeconds = 300)

. (Join-Path $PSScriptRoot '_common.ps1')

try {
    Initialize-DockerCli | Out-Null
    Write-Section '启动 Hudi Lab Portable'
    Assert-DockerReady
    Ensure-EnvFile
    Ensure-SparkImage

    if ((Invoke-Compose -ComposeArgs @('up', '-d')) -ne 0) { throw 'docker compose up 失败' }

    Wait-ServiceHealthy -Service 'namenode' -TimeoutSeconds $TimeoutSeconds
    Wait-ServiceHealthy -Service 'datanode' -TimeoutSeconds $TimeoutSeconds
    Wait-ServiceHealthy -Service 'spark' -TimeoutSeconds $TimeoutSeconds
    Wait-HdfsSafeModeOff -TimeoutSeconds $TimeoutSeconds
    Wait-LiveDataNodes -Expected 1 -TimeoutSeconds $TimeoutSeconds

    Show-DeploymentSummary
    exit 0
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}
