param(
    [ValidateSet("status", "sample", "monitor", "install", "uninstall", "deferred-clean", "clear-backup", "enable-counter", "disable-counter", "open-gui", "self-test")]
    [string]$Command = "status",
    [int]$DurationSeconds = 120,
    [int]$IntervalSeconds = 5,
    [switch]$Json
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

function ConvertTo-LogGuardSummary {
    $status = Get-LogGuardStatus
    $writeStats = Get-CodexProcessWriteStats
    $thread = Get-RecentThreadContext
    $logWriteMB = [math]::Round(($status.DbMB + $status.WalMB + $status.ShmMB), 3)
    $blockerText = if ($status.trigger_installed) { "protected" } else { "not_installed" }
    $risk = if ($writeStats.TotalWriteMBps -ge 0.5) {
        if ($status.trigger_installed) { "write_high_but_guarded" } else { "write_high_install_guard_recommended" }
    } else {
        if ($status.trigger_installed) { "write_low_guarded" } else { "write_low_no_guard" }
    }

    return [pscustomobject]@{
        result = $risk
        blocker = $blockerText
        trigger_installed = [bool]$status.trigger_installed
        blocker_mode = $status.blocker_mode
        log_file = $script:LogDbPath
        log_write_mb = $logWriteMB
        logs_count = $status.logs_count
        backup_dir = $script:BackupDir
        backup_dir_mb = $status.BackupDirMB
        counter_total = $status.counter_total
        last_session_delta = $status.last_session_delta
        total_write_mbps = $writeStats.TotalWriteMBps
        top_process = $writeStats.TopProcess
        top_pid = $writeStats.TopPID
        top_write_mbps = $writeStats.TopWriteMBps
        process_count = $writeStats.ProcessCount
        process_status = $writeStats.Status
        thread_state = $thread.TaskState
        thread_title = $thread.ThreadTitle
        thread_cwd = $thread.ThreadCwd
        error = $status.error
    }
}

function Write-Result($Value) {
    if ($Json) {
        $Value | ConvertTo-Json -Depth 6
        return
    }

    if ($Value -is [string]) {
        Write-Output $Value
        return
    }

    if ($Value.PSObject.Properties["csv_file"]) {
        Write-Output "result=$($Value.result)"
        Write-Output "duration_seconds=$($Value.duration_seconds) interval_seconds=$($Value.interval_seconds) sample_count=$($Value.sample_count)"
        Write-Output "avg_write_mbps=$($Value.avg_write_mbps) max_write_mbps=$($Value.max_write_mbps)"
        Write-Output "blocked_total=$($Value.blocked_total)"
        Write-Output "top_process=$($Value.top_write_mbps) MB/s | $($Value.top_process)#$($Value.top_pid)"
        Write-Output "counting_active=$($Value.counting_active) blocker_at_start=$($Value.blocker_at_start)"
        Write-Output "csv_file=$($Value.csv_file)"
        return
    }

    Write-Output "result=$($Value.result)"
    Write-Output "blocker=$($Value.blocker) mode=$($Value.blocker_mode)"
    Write-Output "log_write_mb=$($Value.log_write_mb) logs_count=$($Value.logs_count)"
    Write-Output "counter_total=$($Value.counter_total) last_session_delta=$($Value.last_session_delta)"
    Write-Output "total_write_mbps=$($Value.total_write_mbps)"
    Write-Output "top_process=$($Value.top_write_mbps) MB/s | $($Value.top_process)#$($Value.top_pid)"
    Write-Output "thread_state=$($Value.thread_state)"
    if ($Value.thread_title) {
        Write-Output "thread_title=$($Value.thread_title)"
    }
    Write-Output "log_file=$($Value.log_file)"
}

function Start-DeferredCleanHelper {
    $helper = Join-Path $script:RootDir "tools\CodexLogGuardDeferredClean.ps1"
    if (-not (Test-Path -LiteralPath $helper)) {
        throw "Deferred clean helper missing: $helper"
    }

    $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (-not (Test-Path -LiteralPath $powershell)) {
        $powershell = "powershell.exe"
    }

    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$helper`""
    Start-Process -FilePath $powershell -ArgumentList $arguments
}

function Write-MonitorCsvRow([string]$Path, [pscustomobject]$Sample) {
    $exists = Test-Path -LiteralPath $Path
    if ($exists) {
        $Sample | Export-Csv -LiteralPath $Path -NoTypeInformation -Append -Encoding UTF8
    } else {
        $Sample | Export-Csv -LiteralPath $Path -NoTypeInformation -Encoding UTF8
    }
}

function New-CliMonitorSample([int]$StartCounter, [ref]$PreviousCounter, [bool]$CountingActive) {
    $stats = Get-CodexProcessWriteStats
    $thread = Get-RecentThreadContext
    $currentCounter = 0
    if (Test-Path -LiteralPath $script:LogDbPath) {
        try {
            $currentCounter = Invoke-LogCounterAction "read"
        } catch {
            $currentCounter = 0
        }
    }

    if ($CountingActive) {
        $sinceStart = $currentCounter - $StartCounter
        $sinceLast = $currentCounter - [int]$PreviousCounter.Value
        $PreviousCounter.Value = $currentCounter
        $countMode = "monitor_counting"
    } else {
        $sinceStart = 0
        $sinceLast = 0
        $countMode = "not_counting"
    }

    $sampleStatus = $stats.Status
    if ($sinceLast -gt 0) {
        $sampleStatus = "guarded"
    }

    return [pscustomobject]@{
        Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        TotalWriteMBps = $stats.TotalWriteMBps
        TopProcess = $stats.TopProcess
        TopPID = $stats.TopPID
        TopWriteMBps = $stats.TopWriteMBps
        ProcessCount = $stats.ProcessCount
        Status = $sampleStatus
        TaskState = $thread.TaskState
        ActiveThreadTitle = $thread.ThreadTitle
        ActiveThreadCwd = $thread.ThreadCwd
        BlockedLogCountMode = $countMode
        BlockedLogInsertsTotal = $currentCounter
        BlockedLogInsertsSinceStart = $sinceStart
        BlockedLogInsertsSinceLastSample = $sinceLast
    }
}

function Get-CliMonitorEvaluation([object[]]$Samples, [bool]$HadBlockerAtStart) {
    if (-not $Samples -or $Samples.Count -eq 0) {
        return "no_samples"
    }

    $avg = [math]::Round((($Samples | Measure-Object TotalWriteMBps -Average).Average), 3)
    $max = [math]::Round((($Samples | Measure-Object TotalWriteMBps -Maximum).Maximum), 3)
    $blocked = ($Samples | Measure-Object BlockedLogInsertsSinceLastSample -Sum).Sum
    if ($blocked -gt 0) {
        if ($blocked -ge 1000 -or $avg -ge 0.5 -or $max -ge 0.5) {
            return "write_high_guarded"
        }
        return "write_slight_high_guarded"
    }
    if ($avg -ge 0.5 -or $max -ge 0.5) {
        if ($HadBlockerAtStart) {
            return "write_high_no_recent_blocks"
        }
        return "write_high_guard_recommended"
    }
    if ($avg -lt 0.05 -and $max -lt 0.5) {
        return "write_normal"
    }
    return "write_slight_high"
}

function Start-FixedMonitor {
    if ($DurationSeconds -lt 5) {
        throw "DurationSeconds must be >= 5"
    }
    if ($IntervalSeconds -lt 1) {
        throw "IntervalSeconds must be >= 1"
    }

    if (-not (Test-Path -LiteralPath $script:LogDir)) {
        New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
    }

    $csvPath = Join-Path $script:LogDir ("codex-write-cli-" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".csv")
    $status = Get-LogGuardStatus
    $hadBlocker = [bool]$status.trigger_installed
    $countingActive = $false
    $startCounter = 0
    $previousCounterValue = 0

    if ($hadBlocker) {
        $startCounter = Invoke-LogCounterAction "enable"
        $previousCounterValue = $startCounter
        $countingActive = $true
    }

    $samples = @()
    $sampleCount = [math]::Max(1, [math]::Floor($DurationSeconds / $IntervalSeconds))
    try {
        for ($i = 0; $i -lt $sampleCount; $i++) {
            $previousRef = [ref]$previousCounterValue
            $sample = New-CliMonitorSample $startCounter $previousRef $countingActive
            $previousCounterValue = [int]$previousRef.Value
            $samples += $sample
            Write-MonitorCsvRow $csvPath $sample
            if (-not $Json) {
                Write-Output ("sample={0}/{1} write_mbps={2} blocked_since_last={3}" -f ($i + 1), $sampleCount, $sample.TotalWriteMBps, $sample.BlockedLogInsertsSinceLastSample)
            }
            if ($i -lt ($sampleCount - 1)) {
                Start-Sleep -Seconds $IntervalSeconds
            }
        }
    } finally {
        if ($hadBlocker) {
            try {
                Invoke-LogCounterAction "restore" | Out-Null
            } catch {
            }
        }
    }

    $avgWrite = if ($samples.Count -gt 0) { [math]::Round((($samples | Measure-Object TotalWriteMBps -Average).Average), 3) } else { 0 }
    $maxWrite = if ($samples.Count -gt 0) { [math]::Round((($samples | Measure-Object TotalWriteMBps -Maximum).Maximum), 3) } else { 0 }
    $blockedTotal = if ($samples.Count -gt 0) { [int](($samples | Measure-Object BlockedLogInsertsSinceLastSample -Sum).Sum) } else { 0 }
    $topSample = $samples | Sort-Object TopWriteMBps -Descending | Select-Object -First 1

    return [pscustomobject]@{
        result = Get-CliMonitorEvaluation $samples $hadBlocker
        duration_seconds = $DurationSeconds
        interval_seconds = $IntervalSeconds
        sample_count = $samples.Count
        csv_file = $csvPath
        blocker_at_start = $hadBlocker
        counting_active = $countingActive
        avg_write_mbps = $avgWrite
        max_write_mbps = $maxWrite
        blocked_total = $blockedTotal
        top_process = if ($topSample) { $topSample.TopProcess } else { "" }
        top_pid = if ($topSample) { $topSample.TopPID } else { "" }
        top_write_mbps = if ($topSample) { $topSample.TopWriteMBps } else { 0 }
        samples = $samples
    }
}

try {
    switch ($Command) {
        "status" {
            Write-Result (ConvertTo-LogGuardSummary)
        }
        "sample" {
            Write-Result (ConvertTo-LogGuardSummary)
        }
        "monitor" {
            Write-Result (Start-FixedMonitor)
        }
        "install" {
            Invoke-LogBlockerAction "install"
            Write-Result "guard_installed"
        }
        "uninstall" {
            Invoke-LogBlockerAction "remove"
            Write-Result "guard_uninstalled"
        }
        "deferred-clean" {
            Start-DeferredCleanHelper
            Write-Result "deferred_clean_started_close_codex_then_reopen_codex_when_prompted"
        }
        "clear-backup" {
            Write-Result (Clear-BackupHistory)
        }
        "enable-counter" {
            $count = Invoke-LogCounterAction "enable"
            Write-Result "counter_enabled total=$count"
        }
        "disable-counter" {
            Invoke-LogCounterAction "reset" | Out-Null
            Invoke-LogBlockerAction "install"
            Write-Result "counter_disabled_pure_guard_restored"
        }
        "open-gui" {
            $launcher = Join-Path $script:RootDir "codex写盘异常检测.vbs"
            if (-not (Test-Path -LiteralPath $launcher)) {
                throw "GUI launcher missing: $launcher"
            }
            Start-Process wscript.exe -ArgumentList "`"$launcher`""
            Write-Result "gui_opened"
        }
        "self-test" {
            Write-Result (Test-CodexLogGuardCore)
        }
    }
} catch {
    if ($Json) {
        [pscustomobject]@{ error = $_.Exception.Message } | ConvertTo-Json -Depth 4
        exit 1
    }
    Write-Error $_.Exception.Message
    exit 1
}
