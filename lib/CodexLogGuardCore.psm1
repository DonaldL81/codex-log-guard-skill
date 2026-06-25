$ErrorActionPreference = "Stop"

$script:RootDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:LogDir = Join-Path $script:RootDir "monitor-logs"
$script:CodexDir = Join-Path $env:USERPROFILE ".codex"
$script:LogDbPath = Join-Path $script:CodexDir "logs_2.sqlite"
$script:BackupDir = Join-Path $script:CodexDir "logs_backup"
$script:MonitorWarnMBps = 0.5
$script:MonitorActiveWindowSeconds = 120

function Initialize-CodexLogGuardContext {
    param(
        [string]$RootDir,
        [string]$LogDir,
        [string]$CodexDir,
        [string]$LogDbPath,
        [string]$BackupDir,
        [double]$MonitorWarnMBps = 0.5,
        [int]$MonitorActiveWindowSeconds = 120
    )

    if ($RootDir) { $script:RootDir = $RootDir }
    if ($LogDir) { $script:LogDir = $LogDir }
    if ($CodexDir) { $script:CodexDir = $CodexDir }
    if ($LogDbPath) { $script:LogDbPath = $LogDbPath }
    if ($BackupDir) { $script:BackupDir = $BackupDir }
    $script:MonitorWarnMBps = $MonitorWarnMBps
    $script:MonitorActiveWindowSeconds = $MonitorActiveWindowSeconds
}

function Get-CodexLogGuardPaths {
    return [pscustomobject]@{
        RootDir = $script:RootDir
        LogDir = $script:LogDir
        CodexDir = $script:CodexDir
        LogDbPath = $script:LogDbPath
        BackupDir = $script:BackupDir
    }
}
function Get-PythonCommand {
    if (Get-Command python -ErrorAction SilentlyContinue) {
        return "python"
    }
    if (Get-Command py -ErrorAction SilentlyContinue) {
        return "py -3"
    }
    return ""
}

function Invoke-PythonText([string]$Script, [hashtable]$Env = @{}) {
    $pythonCommand = Get-PythonCommand
    if (-not $pythonCommand) {
        throw "未找到 Python，无法读取或修改 SQLite。"
    }

    foreach ($key in $Env.Keys) {
        [Environment]::SetEnvironmentVariable($key, [string]$Env[$key], "Process")
    }

    $cleanScript = $Script.TrimStart([char]0xFEFF)
    if ($pythonCommand -eq "python") {
        return $cleanScript | python
    }
    return $cleanScript | py -3
}

function Invoke-PythonJson([string]$Script, [hashtable]$Env = @{}) {
    $encoded = Invoke-PythonText $Script $Env
    $encodedText = (($encoded | Select-Object -First 1) -as [string]).Trim()
    if (-not $encodedText) {
        throw "Python 没有返回数据。"
    }
    $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedText))
    return $json | ConvertFrom-Json
}

function ConvertTo-ShortText([string]$Value, [int]$MaxLength = 80) {
    if (-not $Value) {
        return ""
    }
    $clean = ($Value -replace "[\r\n\t]+", " ").Trim()
    if ($clean.Length -le $MaxLength) {
        return $clean
    }
    return $clean.Substring(0, $MaxLength) + "..."
}

function Get-FileMB([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return 0
    }
    $item = Get-Item -LiteralPath $Path -Force
    return [math]::Round($item.Length / 1MB, 3)
}

function Get-DirectoryMB([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return 0
    }
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) {
        return 0
    }
    return [math]::Round($sum / 1MB, 3)
}

function Get-CodexProcesses {
    return @(Get-Process -Name "Codex", "codex" -ErrorAction SilentlyContinue)
}

function Get-LogGuardStatus {
    $script = @'
import base64
import json
import os
import sqlite3

db_path = os.environ["CODEX_LOG_DB"]
result = {
    "database": db_path,
    "db_exists": os.path.exists(db_path),
    "logs_count": None,
    "logs_min_id": None,
    "logs_max_id": None,
    "trigger_installed": False,
    "blocker_mode": "数据库不存在",
    "trigger_name": "",
    "trigger_table": "",
    "counter_total": None,
    "last_session_start_count": None,
    "last_session_delta": None,
    "error": "",
}

try:
    if result["db_exists"]:
        con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=2)
        cur = con.cursor()
        cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='logs'")
        has_logs = cur.fetchone() is not None
        if has_logs:
            cur.execute("SELECT COUNT(*), MIN(id), MAX(id) FROM logs")
            count, min_id, max_id = cur.fetchone()
            result["logs_count"] = count
            result["logs_min_id"] = min_id
            result["logs_max_id"] = max_id

        cur.execute("SELECT name, tbl_name, sql FROM sqlite_master WHERE type='trigger' AND name='block_log_inserts'")
        row = cur.fetchone()
        if row:
            result["trigger_installed"] = True
            result["trigger_name"] = row[0]
            result["trigger_table"] = row[1]
            sql = row[2] or ""
            if "codex_log_blocker_counter" in sql or "blocked_count" in sql:
                result["blocker_mode"] = "计数拦截器"
            else:
                result["blocker_mode"] = "纯拦截器"
        else:
            result["blocker_mode"] = "未安装"

        cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='codex_log_blocker_counter'")
        if cur.fetchone() is not None:
            cur.execute("PRAGMA table_info(codex_log_blocker_counter)")
            columns = {row[1] for row in cur.fetchall()}
            if "last_session_start_count" in columns:
                cur.execute("SELECT blocked_count, last_session_start_count FROM codex_log_blocker_counter WHERE id = 1")
                counter_row = cur.fetchone()
                if counter_row:
                    result["counter_total"] = counter_row[0]
                    result["last_session_start_count"] = counter_row[1]
                    result["last_session_delta"] = counter_row[0] - counter_row[1]
            else:
                cur.execute("SELECT blocked_count FROM codex_log_blocker_counter WHERE id = 1")
                counter_row = cur.fetchone()
                if counter_row:
                    result["counter_total"] = counter_row[0]
                    result["last_session_start_count"] = 0
                    result["last_session_delta"] = counter_row[0]
        con.close()
except Exception as exc:
    result["error"] = str(exc)

payload = json.dumps(result, ensure_ascii=False).encode("utf-8")
print(base64.b64encode(payload).decode("ascii"))
'@
    $status = Invoke-PythonJson $script @{ CODEX_LOG_DB = $script:LogDbPath }
    $status | Add-Member -NotePropertyName DbMB -NotePropertyValue (Get-FileMB $script:LogDbPath) -Force
    $status | Add-Member -NotePropertyName WalMB -NotePropertyValue (Get-FileMB ($script:LogDbPath + "-wal")) -Force
    $status | Add-Member -NotePropertyName ShmMB -NotePropertyValue (Get-FileMB ($script:LogDbPath + "-shm")) -Force
    $status | Add-Member -NotePropertyName BackupDirMB -NotePropertyValue (Get-DirectoryMB $script:BackupDir) -Force
    return $status
}

function Invoke-LogBlockerAction([string]$Action) {
    $script = @'
import os
import sqlite3

db_path = os.environ["CODEX_LOG_DB"]
action = os.environ["CODEX_LOG_ACTION"]

pure_trigger_sql = """
CREATE TRIGGER IF NOT EXISTS block_log_inserts
BEFORE INSERT ON logs
BEGIN
    SELECT RAISE(IGNORE);
END;
"""

con = sqlite3.connect(db_path, timeout=10)
cur = con.cursor()
cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='logs'")
if cur.fetchone() is None:
    raise SystemExit("logs table missing")

if action == "install" or action == "restore":
    cur.execute("DROP TRIGGER IF EXISTS block_log_inserts")
    cur.execute(pure_trigger_sql)
elif action == "remove":
    cur.execute("DROP TRIGGER IF EXISTS block_log_inserts")
else:
    raise SystemExit(f"unknown action: {action}")

con.commit()
con.close()
print("ok")
'@
    Invoke-PythonText $script @{ CODEX_LOG_DB = $script:LogDbPath; CODEX_LOG_ACTION = $Action } | Out-Null
}

function Invoke-LogCounterAction([string]$Action) {
    $script = @'
import os
import sqlite3

db_path = os.environ["CODEX_LOG_DB"]
action = os.environ["CODEX_COUNTER_ACTION"]

pure_trigger_sql = """
CREATE TRIGGER IF NOT EXISTS block_log_inserts
BEFORE INSERT ON logs
BEGIN
    SELECT RAISE(IGNORE);
END;
"""

counter_table_sql = """
CREATE TABLE IF NOT EXISTS codex_log_blocker_counter (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    blocked_count INTEGER NOT NULL DEFAULT 0,
    last_session_start_count INTEGER NOT NULL DEFAULT 0,
    enabled_at TEXT,
    updated_at TEXT
);
"""

counter_trigger_sql = """
CREATE TRIGGER IF NOT EXISTS block_log_inserts
BEFORE INSERT ON logs
BEGIN
    UPDATE codex_log_blocker_counter
    SET blocked_count = blocked_count + 1,
        updated_at = strftime('%Y-%m-%d %H:%M:%f', 'now')
    WHERE id = 1;
    SELECT RAISE(IGNORE);
END;
"""

con = sqlite3.connect(db_path, timeout=10)
cur = con.cursor()
cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='logs'")
has_logs = cur.fetchone() is not None
if not has_logs and action == "reset":
    print(0)
    con.close()
    raise SystemExit(0)
if not has_logs:
    raise SystemExit("logs table missing")

if action == "enable":
    cur.execute(counter_table_sql)
    cur.execute("PRAGMA table_info(codex_log_blocker_counter)")
    columns = {row[1] for row in cur.fetchall()}
    if "last_session_start_count" not in columns:
        cur.execute("ALTER TABLE codex_log_blocker_counter ADD COLUMN last_session_start_count INTEGER NOT NULL DEFAULT 0")
    cur.execute(
        """
        INSERT INTO codex_log_blocker_counter (id, blocked_count, last_session_start_count, enabled_at, updated_at)
        VALUES (1, 0, 0, strftime('%Y-%m-%d %H:%M:%f', 'now'), strftime('%Y-%m-%d %H:%M:%f', 'now'))
        ON CONFLICT(id) DO UPDATE SET
            last_session_start_count = blocked_count,
            enabled_at = excluded.enabled_at,
            updated_at = excluded.updated_at
        """
    )
    cur.execute("DROP TRIGGER IF EXISTS block_log_inserts")
    cur.execute(counter_trigger_sql)
    con.commit()
elif action == "restore":
    cur.execute("DROP TRIGGER IF EXISTS block_log_inserts")
    cur.execute(pure_trigger_sql)
    con.commit()
elif action == "reset":
    cur.execute(counter_table_sql)
    cur.execute("PRAGMA table_info(codex_log_blocker_counter)")
    columns = {row[1] for row in cur.fetchall()}
    if "last_session_start_count" not in columns:
        cur.execute("ALTER TABLE codex_log_blocker_counter ADD COLUMN last_session_start_count INTEGER NOT NULL DEFAULT 0")
    cur.execute(
        """
        INSERT INTO codex_log_blocker_counter (id, blocked_count, last_session_start_count, enabled_at, updated_at)
        VALUES (1, 0, 0, NULL, strftime('%Y-%m-%d %H:%M:%f', 'now'))
        ON CONFLICT(id) DO UPDATE SET
            blocked_count = 0,
            last_session_start_count = 0,
            updated_at = excluded.updated_at
        """
    )
    con.commit()
elif action == "read":
    pass
else:
    raise SystemExit(f"unknown action: {action}")

cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='codex_log_blocker_counter'")
if cur.fetchone() is None:
    print(0)
    con.close()
    raise SystemExit(0)

cur.execute("SELECT blocked_count FROM codex_log_blocker_counter WHERE id = 1")
row = cur.fetchone()
print(0 if row is None else int(row[0]))
con.close()
'@
    $result = Invoke-PythonText $script @{ CODEX_LOG_DB = $script:LogDbPath; CODEX_COUNTER_ACTION = $Action }
    return [int](($result | Select-Object -Last 1) -as [string])
}

function Assert-BackupDirIsSafe {
    if (-not (Test-Path -LiteralPath $script:CodexDir)) {
        throw "没有找到 .codex 目录：$script:CodexDir"
    }

    $codexFullPath = [System.IO.Path]::GetFullPath($script:CodexDir)
    $backupFullPath = [System.IO.Path]::GetFullPath($script:BackupDir)
    if (-not $backupFullPath.StartsWith($codexFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "暂存目录不在 .codex 目录内，已停止清理：$script:BackupDir"
    }
}

function Clear-BackupHistory {
    Assert-BackupDirIsSafe

    if (-not (Test-Path -LiteralPath $script:BackupDir)) {
        New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null
        return "暂存目录已创建；没有历史文件需要清空：$script:BackupDir"
    }

    $items = @(Get-ChildItem -LiteralPath $script:BackupDir -Force -ErrorAction SilentlyContinue)
    foreach ($item in $items) {
        Remove-Item -LiteralPath $item.FullName -Recurse -Force
    }

    if ($items.Count -eq 0) {
        return "暂存目录为空，没有历史文件需要清空：$script:BackupDir"
    }

    return "已清空历史暂存文件：$script:BackupDir"
}

function Backup-And-ClearLogs {
    $processes = Get-CodexProcesses
    if ($processes.Count -gt 0) {
        throw "检测到 Codex 仍在运行。请先完全退出 Codex，再清理文件。"
    }

    Assert-BackupDirIsSafe

    $files = @()
    foreach ($name in @("logs_2.sqlite", "logs_2.sqlite-wal", "logs_2.sqlite-shm")) {
        $path = Join-Path $script:CodexDir $name
        if (Test-Path -LiteralPath $path) {
            $files += Get-Item -LiteralPath $path -Force
        }
    }

    Clear-BackupHistory | Out-Null

    if ($files.Count -eq 0) {
        return "已清空暂存目录；没有找到 logs_2.sqlite 日志文件，无需移动。"
    }

    foreach ($file in $files) {
        Move-Item -LiteralPath $file.FullName -Destination $script:BackupDir
    }
    return "日志已移动到暂存目录：$script:BackupDir"
}

function Get-CodexProcessWriteStats {
    $rows = @(Get-CimInstance Win32_PerfFormattedData_PerfProc_Process |
        Where-Object { $_.Name -like "Codex*" -or $_.Name -like "codex*" })

    if ($rows.Count -eq 0) {
        return [pscustomobject]@{
            TotalWriteMBps = 0
            TopProcess = ""
            TopPID = ""
            TopWriteMBps = 0
            ProcessCount = 0
            Status = "未发现 Codex 进程"
        }
    }

    $sum = ($rows | Measure-Object -Property IOWriteBytesPersec -Sum).Sum
    $top = $rows | Sort-Object IOWriteBytesPersec -Descending | Select-Object -First 1
    $total = [math]::Round($sum / 1MB, 2)
    return [pscustomobject]@{
        TotalWriteMBps = $total
        TopProcess = $top.Name
        TopPID = $top.IDProcess
        TopWriteMBps = [math]::Round($top.IOWriteBytesPersec / 1MB, 2)
        ProcessCount = $rows.Count
        Status = if ($total -ge $script:MonitorWarnMBps) { "写盘偏高" } else { "正常" }
    }
}

function Get-RecentThreadContext {
    $stateDb = Join-Path $script:CodexDir "state_5.sqlite"
    if (-not (Test-Path -LiteralPath $stateDb)) {
        return [pscustomobject]@{
            TaskState = "未找到会话状态库"
            ThreadId = ""
            ThreadTitle = ""
            ThreadCwd = ""
            ThreadUpdatedAt = ""
            ThreadAgeSeconds = ""
            ThreadTitleSource = ""
        }
    }

    $script = @'
import base64
from datetime import datetime
import json
import os
import sqlite3
import time

path = os.environ["CODEX_STATE_DB"]
session_index_path = os.path.join(os.path.dirname(path), "session_index.jsonl")

def emit(payload):
    raw = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    print(base64.b64encode(raw).decode("ascii"))

def parse_index_time(value):
    if not value:
        return 0
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    except Exception:
        return 0

def latest_index_title(thread_id, fallback_title):
    if not thread_id or not os.path.exists(session_index_path):
        return fallback_title or "", False
    latest_title = fallback_title or ""
    latest_ts = 0
    try:
        with open(session_index_path, "r", encoding="utf-8-sig") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                try:
                    item = json.loads(line)
                except Exception:
                    continue
                if item.get("id") != thread_id:
                    continue
                ts = parse_index_time(item.get("updated_at", ""))
                if ts >= latest_ts:
                    latest_ts = ts
                    latest_title = item.get("thread_name") or latest_title
    except Exception:
        return fallback_title or "", False
    return latest_title, latest_ts > 0

try:
    con = sqlite3.connect(f"file:{path}?mode=ro", uri=True, timeout=1)
    cur = con.cursor()
    row = cur.execute(
        """
        SELECT id, title, cwd, updated_at_ms, updated_at, recency_at_ms, recency_at
        FROM threads
        ORDER BY COALESCE(updated_at_ms, recency_at_ms, updated_at * 1000, recency_at * 1000, 0) DESC
        LIMIT 1
        """
    ).fetchone()
    con.close()
    if not row:
        emit({})
    else:
        thread_id, title, cwd, updated_at_ms, updated_at, recency_at_ms, recency_at = row
        title, title_from_index = latest_index_title(thread_id, title)
        updated_ms = updated_at_ms or (updated_at * 1000 if updated_at else None) or recency_at_ms or (recency_at * 1000 if recency_at else None)
        age = None
        updated_iso = ""
        if updated_ms:
            now_ms = int(time.time() * 1000)
            age = max(0, int((now_ms - int(updated_ms)) / 1000))
            updated_iso = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(int(updated_ms) / 1000))
        emit({
            "thread_id": thread_id or "",
            "title": title or "",
            "title_source": "session_index" if title_from_index else "state_db",
            "cwd": cwd or "",
            "updated_at": updated_iso,
            "age_seconds": age,
        })
except Exception as exc:
    emit({"error": str(exc)})
'@

    try {
        $data = Invoke-PythonJson $script @{ CODEX_STATE_DB = $stateDb }
        $age = $data.age_seconds
        $taskState = if ($null -ne $age -and $age -le $script:MonitorActiveWindowSeconds) {
            "最近有会话活动"
        } else {
            "未检测到近期会话活动"
        }
        return [pscustomobject]@{
            TaskState = $taskState
            ThreadId = $data.thread_id
            ThreadTitle = ConvertTo-ShortText $data.title 80
            ThreadCwd = (($data.cwd -as [string]) -replace "^\\\\\?\\", "")
            ThreadUpdatedAt = $data.updated_at
            ThreadAgeSeconds = if ($null -eq $age) { "" } else { [int]$age }
            ThreadTitleSource = $data.title_source
        }
    } catch {
        return [pscustomobject]@{
            TaskState = "读取会话状态失败"
            ThreadId = ""
            ThreadTitle = ""
            ThreadCwd = ""
            ThreadUpdatedAt = ""
            ThreadAgeSeconds = ""
            ThreadTitleSource = ""
        }
    }
}

function Test-CodexLogGuardCore {
    [void](Get-PythonCommand)
    [void](Get-LogGuardStatus)
    return "SelfTest OK"
}

Export-ModuleMember -Function Initialize-CodexLogGuardContext, Get-CodexLogGuardPaths, Get-PythonCommand, Invoke-PythonText, Invoke-PythonJson, ConvertTo-ShortText, Get-FileMB, Get-DirectoryMB, Get-CodexProcesses, Get-LogGuardStatus, Invoke-LogBlockerAction, Invoke-LogCounterAction, Assert-BackupDirIsSafe, Clear-BackupHistory, Backup-And-ClearLogs, Get-CodexProcessWriteStats, Get-RecentThreadContext, Test-CodexLogGuardCore