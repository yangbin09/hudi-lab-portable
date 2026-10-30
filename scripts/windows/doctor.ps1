#Requires -Version 5.1
<#
.SYNOPSIS
    Hudi Lab Portable —— 只读诊断（不会删除或修改任何内容）
#>
[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot '_common.ps1')

$script:failed = 0

function Check {
    param([string]$Name, [scriptblock]$Test, [switch]$WarnOnly)
    try {
        $result = & $Test
        if ($result -eq $false) { throw '检查未通过' }
        Write-Ok $Name
    } catch {
        if ($WarnOnly) {
            Write-Warn "$Name —— $($_.Exception.Message)"
        } else {
            Write-Err "$Name —— $($_.Exception.Message)"
            $script:failed++
        }
    }
}

Write-Section 'Hudi Lab Portable 诊断（只读）'

# ---------- 工具链 ----------
Check 'docker.exe 可用' {
    Initialize-DockerCli | Out-Null
    $true
}

Check 'Docker Engine 运行中' {
    & docker version --format '{{.Server.Version}}' *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Docker Engine 无响应' }
    $true
}

Check 'Docker Compose 可用' {
    & docker compose version --short *> $null
    if ($LASTEXITCODE -ne 0) { throw 'Compose 插件缺失' }
    $true
}

Check 'Linux Containers 模式' {
    $os = (& docker info --format '{{.OSType}}' 2>$null)
    if ($os -ne 'linux') { throw "当前 OSType=$os" }
    $true
}

# ---------- 仓库文件 ----------
Check 'compose.yaml 存在' {
    if (-not (Test-Path $script:ComposeFile)) { throw '缺失 compose.yaml' }
    $true
}

Check '.env 存在' {
    if (-not (Test-Path $script:EnvFile)) { throw '缺失 .env（执行 bootstrap 或复制 .env.example）' }
    $true
}

Check 'Hadoop XML 配置可解析' {
    foreach ($f in @('hadoop\core-site.xml', 'hadoop\hdfs-site.xml', 'spark\hadoop-conf\core-site.xml', 'spark\hadoop-conf\hdfs-site.xml')) {
        $p = Join-Path $script:RepoRoot $f
        if (-not (Test-Path $p)) { throw "缺失 $f" }
        [xml]$x = Get-Content -LiteralPath $p -Raw
        if ($null -eq $x.configuration) { throw "$f 不是有效 Hadoop 配置" }
    }
    $true
}

Check 'Compose 配置可解析' {
    & docker compose --project-directory $script:RepoRoot -f $script:ComposeFile config --quiet *> $null
    if ($LASTEXITCODE -ne 0) { throw 'docker compose config 失败' }
    $true
}

Check 'Hudi JAR 已固化在镜像中（构建期校验 SHA256）' {
    $image = Get-EnvValue 'SPARK_IMAGE'
    if ([string]::IsNullOrWhiteSpace($image)) { $image = 'hudi-lab-portable-spark:0.1.0' }
    & docker image inspect $image *> $null
    if ($LASTEXITCODE -ne 0) { throw "镜像不存在: $image" }
    $true
}

Check 'Hadoop 镜像存在 (apache/hadoop:3.3.6)' {
    & docker image inspect 'apache/hadoop:3.3.6' *> $null
    if ($LASTEXITCODE -ne 0) { throw 'apache/hadoop:3.3.6 未拉取' }
    $true
}

# ---------- 资源 ----------
Check '项目数据卷齐全' {
    $expected = @('hudi-lab-portable_namenode-data', 'hudi-lab-portable_datanode-data', 'hudi-lab-portable_spark-warehouse', 'hudi-lab-portable_spark-metastore')
    $missing = @()
    foreach ($v in $expected) {
        & docker volume inspect $v *> $null
        if ($LASTEXITCODE -ne 0) { $missing += $v }
    }
    if ($missing.Count -gt 0) { throw ("缺失卷: " + ($missing -join ', ')) }
    $true
} -WarnOnly

Check '项目网络存在' {
    & docker network inspect 'hudi-lab-portable_default' *> $null
    if ($LASTEXITCODE -ne 0) { throw '网络 hudi-lab-portable_default 不存在' }
    $true
} -WarnOnly

# ---------- 服务 ----------
Check 'NameNode 运行且健康' {
    $st = Get-ServiceStatus 'namenode'
    if (-not $st.Exists -or $st.State -ne 'running' -or $st.Health -ne 'healthy') {
        throw "state=$($st.State) health=$($st.Health)"
    }
    $true
}

Check 'DataNode 运行且健康' {
    $st = Get-ServiceStatus 'datanode'
    if (-not $st.Exists -or $st.State -ne 'running' -or $st.Health -ne 'healthy') {
        throw "state=$($st.State) health=$($st.Health)"
    }
    $true
}

Check 'Spark 运行且健康' {
    $st = Get-ServiceStatus 'spark'
    if (-not $st.Exists -or $st.State -ne 'running' -or $st.Health -ne 'healthy') {
        throw "state=$($st.State) health=$($st.Health)"
    }
    $true
}

Check 'HDFS 可读（dfs -ls /）' {
    $out = (& docker compose --project-directory $script:RepoRoot -f $script:ComposeFile exec -T namenode hdfs dfs -ls / 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'HDFS ls 失败' }
    $true
}

Check 'HDFS Live DataNodes = 1' {
    $out = (& docker compose --project-directory $script:RepoRoot -f $script:ComposeFile exec -T namenode hdfs dfsadmin -report 2>$null) -join "`n"
    if ($out -notmatch 'Live datanodes \(1\)') { throw 'Live DataNodes 不为 1' }
    $true
}

Check 'HDFS Safe Mode 已关闭' {
    $out = (& docker compose --project-directory $script:RepoRoot -f $script:ComposeFile exec -T namenode hdfs dfsadmin -safemode get 2>$null) -join "`n"
    if ($out -notmatch 'Safe mode is OFF') { throw 'Safe Mode 仍开启' }
    $true
}

Check 'Spark 可执行（spark-submit --version）' {
    $out = (& docker compose --project-directory $script:RepoRoot -f $script:ComposeFile exec -T spark /opt/spark/bin/spark-submit --version 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'spark-submit 失败' }
    $true
}

Write-Host ''
if ($script:failed -eq 0) {
    Write-Host '  Doctor: PASS（未执行任何写操作）' -ForegroundColor Green
    exit 0
} else {
    Write-Host "  Doctor: $($script:failed) 项失败（未执行任何写操作）" -ForegroundColor Red
    exit 1
}
