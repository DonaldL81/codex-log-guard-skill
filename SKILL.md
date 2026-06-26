---
name: codex-log-guard-skill
description: 检查和缓解 Windows 上 Codex 本地 logs_2.sqlite 异常写盘问题。Use when the user asks to inspect Codex write activity, open the Codex write monitor panel, install or remove the log guard, clean Codex logs, or troubleshoot Codex logs_2.sqlite disk usage.
---

# Codex 写盘异常检测

用于 Windows 上 Codex `logs_2.sqlite` 写盘异常的检查、监测和临时止血。

## 入口命令

把包含这个 `SKILL.md` 的目录当作项目根目录。

- 打开 GUI 面板：运行 `tools/CodexLogGuardCli.ps1 open-gui`。
- 不打开 GUI，直接检查状态：运行 `tools/CodexLogGuardCli.ps1 status -Json`。
- 固定时长实时监测：运行 `tools/CodexLogGuardCli.ps1 monitor -DurationSeconds 120 -Json`。
- 安装日志拦截保护：运行 `tools/CodexLogGuardCli.ps1 install`。
- 卸载日志拦截保护：运行 `tools/CodexLogGuardCli.ps1 uninstall`。
- Codex 对话中清理日志：运行 `tools/CodexLogGuardCli.ps1 deferred-clean`。
- 手动命令行清理当前 Codex 日志文件：确认 Codex 已完全退出后，运行 `tools/CodexLogGuardCli.ps1 clean`；Codex 对话中不要默认使用这个命令。
- 只清空备份历史：运行 `tools/CodexLogGuardCli.ps1 clear-backup`。
- 自检：运行 `tools/CodexLogGuardCli.ps1 self-test`。

PowerShell 调用示例：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\CodexLogGuardCli.ps1 status -Json
```

## 调度规则

- 完成项目安装、初始化、运行自检或首次打开后，必须告诉用户支持的所有自然语言命令：检查写盘、打开监控面板、安装拦截器、卸载拦截器、清理日志文件、清空备份历史、自检。
- 用户说“打开监控面板”“打开 GUI”“我想看实时数据”时，打开 GUI。
- 用户说“检查写盘”“看看是否异常”“帮我诊断”时，调用 `status -Json` 并总结结果。
- 用户说“实时监测”“监测 2 分钟”“运行监测报告”时，调用 `monitor -DurationSeconds 120 -Json`；监测命令会持续到固定时长结束，结束后总结均值、峰值、拦截次数和 CSV 路径。
- 用户说“安装拦截器”“开启保护”时，调用 `install`，并说明拦截保护安装后会持续生效，关闭 GUI 后仍会拦截。
- 用户在 Codex 对话中说“清理日志”“清理文件”时，默认调用 `deferred-clean`；不要要求 Codex 已退出后再执行 `clean`，因为 Codex 退出后当前 Skill 无法继续执行。
- 只有用户明确表示自己在手动 PowerShell 或 GUI 场景中操作，并且 Codex 已完全退出时，才使用 `clean`。
- 清理完成后必须提醒：清理会移动旧的 `logs_2.sqlite*`，旧数据库里的拦截器也会一起被移走；如果 GUI 保持打开且拦截保护开启，重新打开 Codex 后会自动重新安装拦截器；如果只用命令行清理，则需要重新运行 `install`。
- 延迟清理助手完成后会自动等待新日志库生成并重新安装拦截器；不要再额外启动 GUI 等待。

## 安装完成后给用户的提示

安装或首次启动完成后，用简短中文告诉用户：

```text
已准备好 Codex 写盘异常检测工具。你可以直接对我说：
- 帮我检查 Codex 写盘
- 监测 2 分钟并生成报告
- 打开监控面板
- 安装拦截器
- 卸载拦截器
- 清理日志文件
- 关闭 Codex 后自动清理日志
- 清空备份历史
- 运行自检
```

## 安全边界

- 不要强制关闭 Codex，除非用户明确要求。
- 不要整体删除 `C:\Users\<user>\.codex`。
- 不要读取或输出用户消息正文、Codex 回复正文、API Key、Token 或无关状态。
- `monitor-logs` 和 `logs_backup` 是本地运行产物，不要作为发布文件提交。
