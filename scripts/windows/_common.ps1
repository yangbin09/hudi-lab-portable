#Requires -Version 5.1
<#
    Hudi Lab Portable —— Windows 脚本公共函数
    兼容 PowerShell 5.1。其它脚本通过 dot-source 引入本文件。
#>

$ErrorActionPreference = 'Continue'

$script:RepoRoot    = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:ComposeFile = Join-Path $script:RepoRoot 'compose.yaml'
$script:EnvFile     = Join-Path $script:RepoRoot '.env'

function Get-RepoRoot { return $script:RepoRoot }

function Write-Section {
    param([string]$Text)
    Write-Host ''
    Write-Host "== $Text ==" -ForegroundColor Cyan
}

function Write-Ok   { param([string]$Text) Write-Host "  [OK]   $Text" -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host "  [WARN] $Text" -ForegroundColor Yellow }
function Write-Err  { param([string]$Text) Write-Host "  [FAIL] $Text" -ForegroundColor Red }
function Write-Info { param([string]$Text) Write-Host "  $Text" }

function Initialize-DockerCli {
    $cmd = Get-Command docker.exe -ErrorAction SilentlyContinue
    if ($null -ne $cmd) { return $cmd.Source }

    $candidates = @()
    if ($env:LOCALAPPDATA)  { $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\DockerDesktop\resources\bin') }
    if ($env:ProgramFiles)  { $candidates += (Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin') }
    if (${env:ProgramFiles(x86)}) { $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Docker\Docker\resources\bin') }

    foreach ($dir in $candidates) {
        $exe = Join-Path $dir 'docker.exe'
        if (Test-Path $exe) {
            $env:PATH = "$dir;$env:PATH"
            return $exe
        }
    }
    throw '未找到 docker.exe。请安装并启动 Docker Desktop，然后重新打开终端。'
}

# 直接执行 docker compose，输出到控制台；返回退出码。
function Invoke-Compose {
    param([Parameter(Mandatory = $true)][string[]]$ComposeArgs)
    & docker compose --project-directory $script:RepoRoot -f $script:ComposeFile @ComposeArgs | Out-Host
    return $LASTEXITCODE
}

# 捕获输出并返回结果对象
function Invoke-ComposeCapture {
    param([Parameter(Mandatory = $true)][string[]]$ComposeArgs)
    $out  = & docker compose --project-directory $script:RepoRoot -f $script:ComposeFile @ComposeArgs
    $code = $LASTEXITCODE
    return [pscustomobject]@{ Output = ($out -join "`n"); ExitCode = $code }
}

function Get-EnvValue {
    param([Parameter(Mandatory = $true)][string]$Key)
    if (-not (Test-Path $script:EnvFile)) { return $null }
    foreach ($line in Get-Content -LiteralPath $script:EnvFile) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        $i = $t.IndexOf('=')
        if ($i -lt 1) { continue }
        if ($t.Substring(0, $i).Trim() -eq $Key) {
            return $t.Substring($i + 1).Trim()
        }
    }
    return $null
}

function Ensure-EnvFile {
    if (-not (Test-Path $script:EnvFile)) {
        $example = Join-Path $script:RepoRoot '.env.example'
        if (-not (Test-Path $example)) { throw '缺少 .env.example，仓库不完整。' }
        Copy-Item -LiteralPath $example -Destination $script:EnvFile
        Write-Ok '已根据 .env.example 创建 .env'
    } else {
        Write-Ok '.env 已存在（复用）'
    }
}

function Get-ActiveTcpListeners {
    $ports = @()
    try {
        $props = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
        foreach ($ep in $props.GetActiveTcpListeners()) { $ports += $ep.Port }
    } catch {
        # 退化方案：无法枚举时不阻断，交给 docker compose 报错
    }
    return $ports
}

function Assert-PortsAvailable {
    $listeners = @(Get-ActiveTcpListeners)
    $ports = [ordered]@{}
    foreach ($k in @('NN_RPC_PORT', 'NN_WEB_PORT', 'DN_WEB_PORT')) {
        $v = Get-EnvValue $k
        if ([string]::IsNullOrWhiteSpace($v)) { throw ".env 缺少 $k" }
        $n = 0
        if (-not [int]::TryParse($v, [ref]$n) -or $n -lt 1 -or $n -gt 65535) {
            throw ".env 中 $k 不是合法端口: $v"
        }
        $ports[$k] = $n
    }

    $values = @($ports.Values)
    if (($values | Sort-Object -Unique).Count -ne $values.Count) {
        throw "端口配置重复: NN_RPC_PORT=$($ports['NN_RPC_PORT']) NN_WEB_PORT=$($ports['NN_WEB_PORT']) DN_WEB_PORT=$($ports['DN_WEB_PORT'])"
    }

    $conflicts = @()
    foreach ($k in $ports.Keys) {
        if ($listeners -contains $ports[$k]) { $conflicts += "$k=$($ports[$k])" }
    }
    if ($conflicts.Count -gt 0) {
        $msg = "宿主机端口已被占用: $($conflicts -join ', ')。请修改 .env 中的端口，或自行释放端口。脚本不会停止其它容器。"
        throw $msg
    }
    Write-Ok "端口可用: RPC=$($ports['NN_RPC_PORT']) NN-UI=$($ports['NN_WEB_PORT']) DN-UI=$($ports['DN_WEB_PORT'])"
}

function Assert-DockerReady {
    $serverVersion = (& docker version --format '{{.Server.Version}}' 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($serverVersion)) {
        throw 'Docker Engine 未就绪。请启动 Docker Desktop 并等待其完成启动。'
    }
    Write-Ok "Docker Engine $serverVersion"

    $composeVersion = (& docker compose version --short 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($composeVersion)) {
        throw 'Docker Compose 插件不可用（需要 Docker Compose v2+）。'
    }
    Write-Ok "Docker Compose $composeVersion"

    $osType = (& docker info --format '{{.OSType}}' 2>$null)
    if ($osType -ne 'linux') {
        throw "Docker 当前不是 Linux Containers 模式 (OSType=$osType)。请在 Docker Desktop 中切换到 Linux containers。"
    }
    Write-Ok 'Docker 运行模式: linux containers'

    $mem = [double]0
    $memRaw = (& docker info --format '{{.MemTotal}}' 2>$null)
    if ([double]::TryParse([string]$memRaw, [ref]$mem)) {
        $gb = [math]::Round($mem / 1GB, 1)
        if ($gb -lt 4) {
            throw "Docker 可用内存仅 $gb GB，至少需要 4 GB（建议 8 GB 以上）。"
        }
        Write-Ok "Docker 可用内存: $gb GB"
    } else {
        Write-Warn '无法读取 Docker 可用内存'
    }

    $driveLetter = (Split-Path -Qualifier $script:RepoRoot).TrimEnd(':')
    try {
        $freeGb = [math]::Round((Get-PSDrive -Name $driveLetter).Free / 1GB, 1)
        if ($freeGb -lt 5) {
            Write-Warn "项目所在磁盘剩余空间仅 $freeGb GB（建议 10 GB 以上）"
        } else {
            Write-Ok "项目所在磁盘剩余空间: $freeGb GB"
        }
    } catch {
        Write-Warn '无法读取项目磁盘剩余空间'
    }
}

function Get-ServiceContainerId {
    param([string]$Service)
    $out = & docker compose --project-directory $script:RepoRoot -f $script:ComposeFile ps -q $Service 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    $id = @($out | Where-Object { $_ -and $_.Trim() -ne '' })
    if ($id.Count -eq 0) { return $null }
    return $id[0].Trim()
}

function Get-ServiceStatus {
    param([string]$Service)
    $id = Get-ServiceContainerId $Service
    if (-not $id) {
        return [pscustomobject]@{ Exists = $false; State = 'missing'; Health = 'unknown'; Id = $null }
    }
    $state  = (& docker inspect -f '{{.State.Status}}' $id 2>$null)
    $health = (& docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' $id 2>$null)
    return [pscustomobject]@{ Exists = $true; State = "$state".Trim(); Health = "$health".Trim(); Id = $id }
}

function Show-ServiceLogs {
    param([string]$Service, [int]$Tail = 40)
    Write-Host "  --- $Service 最近 $Tail 行日志 ---" -ForegroundColor DarkGray
    & docker compose --project-directory $script:RepoRoot -f $script:ComposeFile logs --tail $Tail $Service
}

function Wait-ServiceHealthy {
    param(
        [Parameter(Mandatory = $true)][string]$Service,
        [int]$TimeoutSeconds = 300
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $st = Get-ServiceStatus $Service
        if ($st.Exists -and $st.State -eq 'running' -and ($st.Health -eq 'healthy' -or $st.Health -eq 'none')) {
            Write-Ok "$Service 已就绪 (health=$($st.Health))"
            return
        }
        if ($st.Exists -and ($st.State -eq 'exited' -or $st.State -eq 'dead')) {
            Show-ServiceLogs $Service
            throw "$Service 启动失败 (state=$($st.State))"
        }
        Start-Sleep -Seconds 3
    }
    Show-ServiceLogs $Service
    throw "$Service 在 $TimeoutSeconds 秒内未就绪"
}

function Wait-HdfsSafeModeOff {
    param([int]$TimeoutSeconds = 180)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $out = & docker compose --project-directory $script:RepoRoot -f $script:ComposeFile exec -T namenode hdfs dfsadmin -safemode get 2>$null
        if (($out -join "`n") -match 'Safe mode is OFF') {
            Write-Ok 'HDFS Safe Mode 已关闭'
            return
        }
        Start-Sleep -Seconds 3
    }
    throw "HDFS Safe Mode 在 $TimeoutSeconds 秒内未关闭"
}

function Wait-LiveDataNodes {
    param([int]$Expected = 1, [int]$TimeoutSeconds = 180)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $out = & docker compose --project-directory $script:RepoRoot -f $script:ComposeFile exec -T namenode hdfs dfsadmin -report 2>$null
        if (($out -join "`n") -match "Live datanodes \($Expected\)") {
            Write-Ok "HDFS Live DataNodes = $Expected"
            return
        }
        Start-Sleep -Seconds 3
    }
    throw "HDFS Live DataNodes 在 $TimeoutSeconds 秒内未达到 $Expected"
}

function Invoke-ContainerScript {
    param(
        [Parameter(Mandatory = $true)][string]$Service,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$ScriptArguments = @()
    )
    $composeArgs = @('exec', '-T', $Service, 'bash', $ScriptPath) + $ScriptArguments
    & docker compose --project-directory $script:RepoRoot -f $script:ComposeFile @composeArgs | Out-Host
    return $LASTEXITCODE
}

function Invoke-ComposeExec {
    param(
        [Parameter(Mandatory = $true)][string]$Service,
        [Parameter(Mandatory = $true)][string[]]$Command
    )
    $composeArgs = @('exec', '-T', $Service) + $Command
    & docker compose --project-directory $script:RepoRoot -f $script:ComposeFile @composeArgs | Out-Host
    return $LASTEXITCODE
}

function Ensure-SparkImage {
    $image = Get-EnvValue 'SPARK_IMAGE'
    if ([string]::IsNullOrWhiteSpace($image)) { $image = 'hudi-lab-portable-spark:0.1.0' }

    & docker image inspect $image *> $null
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "Spark 镜像已存在: $image"
        return
    }

    if ($image -like 'ghcr.io/*') {
        Write-Info "从镜像仓库拉取: $image"
        & docker compose --project-directory $script:RepoRoot -f $script:ComposeFile pull spark
        if ($LASTEXITCODE -ne 0) {
            & docker image inspect $image *> $null
            if ($LASTEXITCODE -ne 0) {
                throw "拉取 $image 失败。若镜像为私有，请先执行: docker login ghcr.io"
            }
        }
        Write-Ok "镜像已就绪: $image"
    } else {
        Write-Info "本地构建镜像: $image"
        & docker compose --project-directory $script:RepoRoot -f $script:ComposeFile build spark
        if ($LASTEXITCODE -ne 0) { throw "Spark 镜像构建失败" }
        Write-Ok "镜像构建完成: $image"
    }
}

function Get-ShortVersion {
    param([string]$Text, [string]$Pattern)
    if ($Text -match $Pattern) { return $Matches[1] }
    return 'unknown'
}

function Show-DeploymentSummary {
    param($Checks = @{})

    $dockerVersion  = (& docker version --format '{{.Server.Version}}' 2>$null)
    $composeVersion = (& docker compose version --short 2>$null)

    $hadoopRaw = (& docker compose --project-directory $script:RepoRoot -f $script:ComposeFile exec -T namenode hdfs version 2>$null) -join "`n"
    $hadoopVersion = Get-ShortVersion $hadoopRaw 'Hadoop\s+([0-9][0-9.]*)'

    $sparkRaw = (& docker compose --project-directory $script:RepoRoot -f $script:ComposeFile exec -T spark /opt/spark/bin/spark-submit --version 2>&1) -join "`n"
    $sparkVersion = Get-ShortVersion $sparkRaw 'version\s+([0-9][0-9.]*)'

    $hudiJar = (& docker compose --project-directory $script:RepoRoot -f $script:ComposeFile exec -T spark bash -c 'ls /opt/hudi/*.jar 2>/dev/null' 2>$null) -join "`n"
    $hudiVersion = 'unknown'
    if ($hudiJar -match 'hudi-spark3\.3-bundle_2\.12-([0-9.]+)\.jar') { $hudiVersion = $Matches[1] }

    $nn = Get-ServiceStatus 'namenode'
    $dn = Get-ServiceStatus 'datanode'
    $sp = Get-ServiceStatus 'spark'

    $report = (& docker compose --project-directory $script:RepoRoot -f $script:ComposeFile exec -T namenode hdfs dfsadmin -report 2>$null) -join "`n"
    $liveNodes = Get-ShortVersion $report 'Live datanodes \((\d+)\)'

    $safeRaw = (& docker compose --project-directory $script:RepoRoot -f $script:ComposeFile exec -T namenode hdfs dfsadmin -safemode get 2>$null) -join "`n"
    $safeMode = 'unknown'
    if ($safeRaw -match 'Safe mode is (ON|OFF)') { $safeMode = $Matches[1] }

    $nnPort = Get-EnvValue 'NN_WEB_PORT'
    if ([string]::IsNullOrWhiteSpace($nnPort)) { $nnPort = '19870' }

    Write-Host ''
    Write-Host '  Hudi Lab Portable' -ForegroundColor White
    Write-Host ''
    Write-Host ("  Docker:       {0} / Compose {1}" -f $dockerVersion, $composeVersion)
    Write-Host ("  Hadoop:       {0}" -f $hadoopVersion)
    Write-Host ("  Spark:        {0}" -f $sparkVersion)
    Write-Host ("  Hudi:         {0}" -f $hudiVersion)
    Write-Host ''
    Write-Host ("  NameNode:     {0}" -f (Format-ServiceState $nn))
    Write-Host ("  DataNode:     {0}" -f (Format-ServiceState $dn))
    Write-Host ("  Spark:        {0}" -f (Format-ServiceState $sp))
    Write-Host ("  HDFS Nodes:   live={0}  safe-mode={1}" -f $liveNodes, $safeMode)
    Write-Host ("  NameNode UI:  http://127.0.0.1:{0}" -f $nnPort)
    Write-Host ''

    if ($Checks.Count -gt 0) {
        foreach ($key in $Checks.Keys) {
            $value = $Checks[$key]
            $color = 'Red'
            if ($value -eq 'PASS') { $color = 'Green' }
            elseif ($value -eq 'NOT TESTED') { $color = 'Yellow' }
            Write-Host ("  {0,-14} {1}" -f ($key + ':'), $value) -ForegroundColor $color
        }
        Write-Host ''
    }
}

function Format-ServiceState {
    param($Status)
    if (-not $Status.Exists) { return 'MISSING' }
    if ($Status.State -ne 'running') { return $Status.State.ToUpper() }
    if ($Status.Health -eq 'healthy') { return 'HEALTHY' }
    if ($Status.Health -eq 'starting') { return 'STARTING' }
    if ($Status.Health -eq 'none') { return 'RUNNING' }
    return $Status.Health.ToUpper()
}

function Test-CommandAvailable {
    param([string]$Name)
    return ($null -ne (Get-Command $Name -ErrorAction SilentlyContinue))
}
