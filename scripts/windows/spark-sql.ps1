#Requires -Version 5.1
<#
.SYNOPSIS
    进入 Hudi Lab Portable 的 Spark SQL（转发参数到 spark-sql）
.EXAMPLE
    .\scripts\windows\spark-sql.ps1
    .\scripts\windows\spark-sql.ps1 -f /workspace/sql/cow-test.sql
    .\scripts\windows\spark-sql.ps1 -e "SHOW DATABASES"
#>
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '_common.ps1')

Initialize-DockerCli | Out-Null

$st = Get-ServiceStatus 'spark'
if ($st.State -ne 'running') {
    Write-Err 'Spark 容器未运行。请先执行 .\scripts\windows\up.ps1'
    exit 1
}

if ($args.Count -gt 0) {
    # 非交互：-e / -f 等参数
    & docker compose --project-directory $script:RepoRoot -f $script:ComposeFile exec -T spark /opt/spark/bin/spark-sql @args
} else {
    # 交互式会话（需要 TTY）
    & docker compose --project-directory $script:RepoRoot -f $script:ComposeFile exec spark /opt/spark/bin/spark-sql
}
exit $LASTEXITCODE
