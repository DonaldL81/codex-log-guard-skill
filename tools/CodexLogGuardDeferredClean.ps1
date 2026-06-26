param(
    [int]$WaitExitTimeoutSeconds = 1800,
    [int]$WaitRebuildTimeoutSeconds = 1800,
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom

$script:RootDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$script:LogDir = Join-Path $script:RootDir "monitor-logs"
$script:CodexDir = Join-Path $env:USERPROFILE ".codex"
$script:LogDbPath = Join-Path $script:CodexDir "logs_2.sqlite"
$script:BackupDir = Join-Path $script:CodexDir "logs_backup"

Import-Module (Join-Path $script:RootDir "lib\CodexLogGuardCore.psm1") -Force -WarningAction SilentlyContinue
Initialize-CodexLogGuardContext -RootDir $script:RootDir -LogDir $script:LogDir -CodexDir $script:CodexDir -LogDbPath $script:LogDbPath -BackupDir $script:BackupDir

function Write-Step([string]$Message) {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Message)
}

function Wait-CodexExit([int]$TimeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $processes = @(Get-CodexProcesses)
        if ($processes.Count -eq 0) {
            return $true
        }
        Write-Step "检测到 Codex 正在运行，请完全退出 Codex。剩余进程数：$($processes.Count)"
        Start-Sleep -Seconds 5
    }
    return $false
}

function Wait-LogDatabaseReady([int]$TimeoutSeconds) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $status = Get-LogGuardStatus
        if ($status.db_exists -and $null -ne $status.logs_count) {
            return $status
        }
        if (-not $status.db_exists) {
            Write-Step "等待 Codex 重新生成 logs_2.sqlite..."
        } else {
            Write-Step "已发现 logs_2.sqlite，等待 logs 表初始化..."
        }
        Start-Sleep -Seconds 5
    }
    return $null
}

function Invoke-DeferredClean {
    Write-Host ""
    Write-Host "Codex 写盘异常检测 - 延迟清理助手"
    Write-Host "----------------------------------------"
    Write-Host "请完全退出 Codex。退出后将自动清理 logs_2.sqlite*。"
    Write-Host "清理完成后，请重新打开 Codex；助手会等待新日志库生成并自动安装拦截器。"
    Write-Host ""

    if (-not (Wait-CodexExit $WaitExitTimeoutSeconds)) {
        Write-Step "等待 Codex 退出超时，未执行清理。"
        Write-Host "你可以重新运行 deferred-clean，或打开 GUI 手动处理。"
        return 1
    }

    Write-Step "已检测到 Codex 完全退出，开始清理日志文件。"
    try {
        $message = Backup-And-ClearLogs
        Write-Step $message
    } catch {
        Write-Step "清理失败：$($_.Exception.Message)"
        return 1
    }

    Write-Host ""
    Write-Host "日志文件已清理。请现在重新打开 Codex。"
    Write-Host "助手会等待 Codex 重新生成 logs_2.sqlite 和 logs 表。"
    Write-Host ""

    $status = Wait-LogDatabaseReady $WaitRebuildTimeoutSeconds
    if (-not $status) {
        Write-Step "等待 Codex 重新生成日志库超时。"
        Write-Host "请确认 Codex 已重新打开，然后重新运行 install 或打开 GUI。"
        return 1
    }

    if ($status.trigger_installed) {
        Write-Step "拦截器已经安装，无需重复安装。"
        return 0
    }

    try {
        Invoke-LogBlockerAction "install"
        Write-Step "清理完成，拦截器已重新安装。"
        return 0
    } catch {
        Write-Step "安装拦截器失败：$($_.Exception.Message)"
        Write-Host "请确认 Codex 已完成初始化，然后重新运行 install 或打开 GUI。"
        return 1
    }
}

if ($SelfTest) {
    [void](Test-CodexLogGuardCore)
    Write-Output "DeferredClean SelfTest OK"
    exit 0
}

$exitCode = Invoke-DeferredClean
Write-Host ""
Write-Host "按 Enter 关闭窗口。"
[void](Read-Host)
exit $exitCode
