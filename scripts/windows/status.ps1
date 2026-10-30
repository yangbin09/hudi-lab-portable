#Requires -Version 5.1
<#
.SYNOPSIS
    Hudi Lab Portable —— 查看部署状态
#>
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot '_common.ps1')

try {
    Initialize-DockerCli | Out-Null

    $id = Get-ServiceContainerId 'namenode'
    if (-not $id) {
        Write-Host ''
        Write-Warn 'Hudi Lab Portable 尚未部署或容器已移除。'
        Write-Host '  首次部署: .\scripts\windows\bootstrap.ps1' -ForegroundColor Gray
        Write-Host ''
        exit 1
    }

    Show-DeploymentSummary

    Write-Section '资源'
    Write-Info 'Docker Volumes:'
    & docker volume ls --filter 'name=hudi-lab-portable' --format '    {{.Name}}' | Out-Host

    Write-Info 'Docker Network:'
    & docker network ls --filter 'name=hudi-lab-portable' --format '    {{.Name}}  {{.Driver}}' | Out-Host

    $ids = @(& docker compose --project-directory $script:RepoRoot -f $script:ComposeFile ps -q 2>$null | Where-Object { $_ })
    if ($ids.Count -gt 0) {
        Write-Info '容器资源占用:'
        & docker stats --no-stream --format '    {{.Name}}  CPU={{.CPUPerc}}  MEM={{.MemUsage}}' $ids | Out-Host
    }
    Write-Host ''
    exit 0
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}
