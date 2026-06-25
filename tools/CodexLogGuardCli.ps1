param(
    [ValidateSet("status", "sample", "install", "uninstall", "clean", "clear-backup", "enable-counter", "disable-counter", "open-gui", "self-test")]
    [string]$Command = "status",
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

try {
    switch ($Command) {
        "status" {
            Write-Result (ConvertTo-LogGuardSummary)
        }
        "sample" {
            Write-Result (ConvertTo-LogGuardSummary)
        }
        "install" {
            Invoke-LogBlockerAction "install"
            Write-Result "guard_installed"
        }
        "uninstall" {
            Invoke-LogBlockerAction "remove"
            Write-Result "guard_uninstalled"
        }
        "clean" {
            Write-Result (Backup-And-ClearLogs)
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
