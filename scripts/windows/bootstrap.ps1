#Requires -Version 5.1
<#
.SYNOPSIS
    Hudi Lab Portable —— Windows 一键部署（幂等）
.DESCRIPTION
    检查 Docker -> 准备 .env / 镜像 -> 启动 NameNode/DataNode/Spark
    -> 等待健康 -> 运行 HDFS / Spark / Hudi 冒烟测试 -> 输出状态。
    重复执行不会格式化已有 NameNode，也不会删除任何数据。
.EXAMPLE
    .\scripts\windows\bootstrap.ps1
.EXAMPLE
    .\scripts\windows\bootstrap.ps1 -PersistenceTest
#>
[CmdletBinding()]
param(
    [switch]$PersistenceTest,
    [switch]$SkipTests,
    [int]$TimeoutSeconds = 300
)

. (Join-Path $PSScriptRoot '_common.ps1')

$results = [ordered]@{}
$runId   = (Get-Date -Format 'yyyyMMddHHmmss')
$exitCode = 0

try {
    Initialize-DockerCli | Out-Null

    # ---------------------------------------------------------
    Write-Section '1/8 检查本机 Docker 环境'
    Assert-DockerReady

    Ensure-EnvFile

    # 已存在部署（容器已创建）时跳过端口检查，避免误报
    $existing = @(& docker compose --project-directory $script:RepoRoot -f $script:ComposeFile ps -a -q 2>$null | Where-Object { $_ })
    if ($existing.Count -eq 0) {
        Assert-PortsAvailable
    } else {
        Write-Ok '检测到已有部署，跳过端口占用检查（不会重新初始化数据）'
    }

    # ---------------------------------------------------------
    Write-Section '2/8 准备 Spark + Hudi 镜像'
    Ensure-SparkImage

    # ---------------------------------------------------------
    Write-Section '3/8 启动 NameNode'
    if ((Invoke-Compose @('up', '-d', 'namenode')) -ne 0) { throw '启动 namenode 失败' }
    Wait-ServiceHealthy -Service 'namenode' -TimeoutSeconds $TimeoutSeconds
    Wait-HdfsSafeModeOff -TimeoutSeconds $TimeoutSeconds

    # ---------------------------------------------------------
    Write-Section '4/8 启动 DataNode'
    if ((Invoke-Compose @('up', '-d', 'datanode')) -ne 0) { throw '启动 datanode 失败' }
    Wait-ServiceHealthy -Service 'datanode' -TimeoutSeconds $TimeoutSeconds
    Wait-LiveDataNodes -Expected 1 -TimeoutSeconds $TimeoutSeconds

    # ---------------------------------------------------------
    Write-Section '5/8 启动 Spark'
    if ((Invoke-Compose @('up', '-d', 'spark')) -ne 0) { throw '启动 spark 失败' }
    Wait-ServiceHealthy -Service 'spark' -TimeoutSeconds $TimeoutSeconds

    # ---------------------------------------------------------
    if (-not $SkipTests) {
        Write-Section '6/8 功能冒烟测试'
        Write-Info "测试运行 ID: $runId（测试数据位于 /tmp/hudi-lab-portable-test/$runId）"

        # ---- HDFS ----
        Write-Host ''
        Write-Host '  -> HDFS' -ForegroundColor DarkCyan
        $code = Invoke-ContainerScript -Service 'namenode' -ScriptPath '/opt/hudi-lab/tests/test-hdfs.sh' -ScriptArguments @($runId)
        if ($code -eq 0) { $results['HDFS Test'] = 'PASS'; Write-Ok 'HDFS Test PASS' }
        else { $results['HDFS Test'] = 'FAIL'; $exitCode = 1; Write-Err 'HDFS Test FAIL' }

        # ---- Spark ----
        Write-Host ''
        Write-Host '  -> Spark + HDFS' -ForegroundColor DarkCyan
        $code = Invoke-ContainerScript -Service 'spark' -ScriptPath '/opt/hudi-lab/tests/test-spark.sh' -ScriptArguments @($runId)
        if ($code -eq 0) { $results['Spark Test'] = 'PASS'; Write-Ok 'Spark Test PASS' }
        else { $results['Spark Test'] = 'FAIL'; $exitCode = 1; Write-Err 'Spark Test FAIL' }

        # ---- Hudi COW / MOR ----
        Write-Host ''
        Write-Host '  -> Hudi COW / MOR' -ForegroundColor DarkCyan
        $code = Invoke-ContainerScript -Service 'spark' -ScriptPath '/opt/hudi-lab/tests/test-hudi.sh' -ScriptArguments @($runId)
        $cowOk = $false
        $morOk = $false
        if ($code -eq 0) {
            $cowOk = $true
            $morOk = $true
        }

        $code = Invoke-ContainerScript -Service 'namenode' -ScriptPath '/opt/hudi-lab/tests/verify-hudi-layout.sh' -ScriptArguments @($runId)
        if ($code -ne 0) {
            $cowOk = $false
            $morOk = $false
        }

        if ($cowOk) { $results['Hudi COW'] = 'PASS'; Write-Ok 'Hudi COW PASS' }
        else { $results['Hudi COW'] = 'FAIL'; $exitCode = 1; Write-Err 'Hudi COW FAIL' }

        if ($morOk) { $results['Hudi MOR'] = 'PASS'; Write-Ok 'Hudi MOR PASS' }
        else { $results['Hudi MOR'] = 'FAIL'; $exitCode = 1; Write-Err 'Hudi MOR FAIL' }

        # ---- 持久化（可选）----
        if ($PersistenceTest) {
            Write-Host ''
            Write-Host '  -> 容器重建后的数据持久化' -ForegroundColor DarkCyan
            $marker = "hudi-lab-persist-$runId"
            Invoke-ComposeExec -Service 'namenode' -Command @('bash', '-c', "echo '$marker' | hdfs dfs -put -f - /tmp/hudi-lab-portable-test/$runId/persist.txt") | Out-Null

            if ((Invoke-Compose @('down')) -ne 0) { throw 'docker compose down 失败' }
            if ((Invoke-Compose @('up', '-d')) -ne 0) { throw 'docker compose up 失败' }
            Wait-ServiceHealthy -Service 'namenode' -TimeoutSeconds $TimeoutSeconds
            Wait-ServiceHealthy -Service 'datanode' -TimeoutSeconds $TimeoutSeconds
            Wait-ServiceHealthy -Service 'spark' -TimeoutSeconds $TimeoutSeconds
            Wait-HdfsSafeModeOff -TimeoutSeconds $TimeoutSeconds

            $markerOut = (& docker compose --project-directory $script:RepoRoot -f $script:ComposeFile exec -T namenode hdfs dfs -cat "/tmp/hudi-lab-portable-test/$runId/persist.txt" 2>$null) -join "`n"
            $markerOk = ($markerOut.Trim() -eq $marker)

            $code = Invoke-ContainerScript -Service 'spark' -ScriptPath '/opt/hudi-lab/tests/test-persistence.sh' -ScriptArguments @($runId)
            if ($markerOk -and $code -eq 0) {
                $results['Persistence'] = 'PASS'
                Write-Ok 'Persistence PASS（容器重建后 HDFS 与 Hudi 表均保留）'
            } else {
                $results['Persistence'] = 'FAIL'
                $exitCode = 1
                Write-Err "Persistence FAIL (marker=$markerOk, query exit=$code)"
            }
        }

        # ---- 清理本次测试数据 ----
        Write-Host ''
        Write-Info '清理本次测试数据（仅 run id 资源）'
        Invoke-ContainerScript -Service 'spark' -ScriptPath '/opt/hudi-lab/tests/cleanup-hudi.sh' -ScriptArguments @($runId) | Out-Null
        Invoke-ComposeExec -Service 'namenode' -Command @('hdfs', 'dfs', '-rm', '-r', '-f', "/tmp/hudi-lab-portable-test/$runId") | Out-Null
    } else {
        Write-Section '6/8 功能冒烟测试（已跳过）'
        $results['HDFS Test']  = 'NOT TESTED'
        $results['Spark Test'] = 'NOT TESTED'
        $results['Hudi COW']   = 'NOT TESTED'
        $results['Hudi MOR']   = 'NOT TESTED'
    }

    # ---------------------------------------------------------
    Write-Section '7/8 部署状态'
    Show-DeploymentSummary -Checks $results

    # ---------------------------------------------------------
    Write-Section '8/8 完成'
    if ($exitCode -eq 0) {
        Write-Host '  Deployment:   SUCCESS' -ForegroundColor Green
        Write-Host ''
        Write-Host '  常用命令：'
        Write-Host '    .\scripts\windows\status.ps1      查看状态'
        Write-Host '    .\scripts\windows\spark-sql.ps1   进入 Spark SQL'
        Write-Host '    .\scripts\windows\hdfs.ps1 dfs -ls /'
        Write-Host '    .\scripts\windows\down.ps1        停止（保留数据）'
        Write-Host ''
    } else {
        Write-Host '  Deployment:   FAILED（见上方失败项）' -ForegroundColor Red
        Write-Host ''
    }

    exit $exitCode
}
catch {
    Write-Host ''
    Write-Err $_.Exception.Message
    Write-Host ''
    exit 1
}
