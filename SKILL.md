---
name: codex-log-guard-skill
description: 检查和缓解 Windows 上 Codex 本地 logs_2.sqlite 异常写盘问题。Use when the user asks to inspect Codex write activity, open the Codex write monitor panel, install or remove the log guard, defer Codex log cleanup, or troubleshoot Codex logs_2.sqlite disk usage.
---

# Codex 写盘异常检测

用于 Windows 上 Codex `logs_2.sqlite` 写盘异常的检查、监测和临时止血。

## 入口命令

把包含这个 `SKILL.md` 的目录当作项目根目录。

- 固定时长实时监测：运行 `tools/CodexLogGuardCli.ps1 monitor -DurationSeconds 120 -Json`。
- 清理日志文件或关闭 Codex 后自动清理日志：运行 `tools/CodexLogGuardCli.ps1 deferred-clean`。
- 安装日志拦截保护：运行 `tools/CodexLogGuardCli.ps1 install`。
- 卸载日志拦截保护：运行 `tools/CodexLogGuardCli.ps1 uninstall`。
- 不打开 GUI，直接检查状态：运行 `tools/CodexLogGuardCli.ps1 status -Json`。
- 打开 GUI 面板：运行 `tools/CodexLogGuardCli.ps1 open-gui`。
- 只清空备份历史：运行 `tools/CodexLogGuardCli.ps1 clear-backup`。
- 自检：运行 `tools/CodexLogGuardCli.ps1 self-test`。

PowerShell 调用示例：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\CodexLogGuardCli.ps1 status -Json
```

## 调度规则

- 诊断监测：用户说“检查 Codex 有没有问题”“检查写盘”“看看是否异常”“Codex 最近有点卡”“帮我诊断”“监测 2 分钟”时，运行 `monitor -DurationSeconds 120 -Json`。
- 延迟清理：用户说“清理日志”“清理文件”“关闭 Codex 后自动清理日志”时，运行 `deferred-clean`。
- 拦截保护：用户说“安装拦截器”“开启保护”时运行 `install`；说“卸载拦截器”“关闭保护”时运行 `uninstall`。
- 状态检查：用户说“查看当前保护状态”“快速看状态”“看一下拦截器状态”时，运行 `status -Json`。
- 打开面板：用户说“打开监控面板”“打开 GUI”“我想看实时数据”时，运行 `open-gui`。
- 维护检查：用户说“清空备份历史”时运行 `clear-backup`；说“运行自检”“检查工具是否正常”时运行 `self-test`。

## 执行要求

- 诊断监测前，先告诉用户会监测约 2 分钟，期间可以正常使用 Codex 或运行一个任务；结束后总结监测结论、平均写盘、峰值写盘、拦截次数、CSV 路径和最终保护状态。
- 状态检查后，总结拦截器状态、日志文件大小、日志行数和备份目录大小。
- 安装保护后，说明拦截保护会持续生效，关闭 GUI 后仍会拦截。
- 延迟清理启动后，提醒用户按助手窗口提示完全退出 Codex，清理后重新打开 Codex；说明旧 `logs_2.sqlite*` 会被移走，助手会等待新日志库生成并自动重新安装拦截器。

## 安装完成后给用户的提示

安装或首次启动完成后，用简短中文告诉用户：

```text
已准备好 Codex 写盘异常检测工具。你可以按需要直接对我说：

要确认 Codex 有没有问题时，可以说：
- 帮我检查 Codex 有没有问题
- 帮我检查 Codex 写盘
- Codex 最近有点卡，帮我检查一下
- 监测 2 分钟并生成报告

要清理日志时，可以说：
- 清理日志文件
- 关闭 Codex 后自动清理日志

要开启或关闭拦截保护时，可以说：
- 安装拦截器
- 卸载拦截器

要快速查看当前状态时，可以说：
- 查看当前保护状态

要打开图形界面时，可以说：
- 打开监控面板

要维护备份或检查工具时，可以说：
- 清空备份历史
- 运行自检
```

## 安全边界

- 不要强制关闭 Codex，除非用户明确要求。
- 只能移动、删除或清空 Codex 日志相关文件：
  - `C:\Users\<user>\.codex\logs_2.sqlite`
  - `C:\Users\<user>\.codex\logs_2.sqlite-wal`
  - `C:\Users\<user>\.codex\logs_2.sqlite-shm`
  - `C:\Users\<user>\.codex\logs_backup\*`
  - 本工具项目目录下的 `monitor-logs\*`
- 只能为了安装、卸载或计数拦截器修改 `logs_2.sqlite` 内的日志拦截触发器；不要修改其他表、其他数据库或其他 Codex 配置。
- 不要整体删除 `C:\Users\<user>\.codex`，不要删除、移动或修改 `.codex` 下除上述日志文件以外的任何文件。
- 不要删除、移动或修改用户项目文件、配置文件、源码、密钥文件、聊天记录文件或其他非日志文件。
- 如果日志文件被占用、清理失败或等待 Codex 重建日志库超时，只能提示用户退出 Codex 后重试或打开 GUI 处理；不要扩大删除范围，不要改删其他目录，不要强制结束进程。
- 不要读取或输出用户消息正文、Codex 回复正文、API Key、Token 或无关状态。
- `monitor-logs` 和 `logs_backup` 是本地运行产物，不要作为发布文件提交。
