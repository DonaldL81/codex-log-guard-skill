# codex写盘异常检测

一个 Windows 小工具，也可以作为 Codex Skill 使用，用来检查和临时缓解 Codex 本地 `logs_2.sqlite` 异常写盘问题。

![界面预览](screenshot.png)

## 使用方式

复制给 Codex：

```text
查看项目并运行
https://github.com/DonaldL81/codex-log-guard-skill
```

或者手动双击：

```text
codex写盘异常检测.vbs
```

## 可以做什么

- 检查 Codex 当前写盘是否偏高。
- 一键安装日志拦截保护。
- 清理 Codex 日志写盘文件。
- 打开 GUI 面板实时监测。
- 作为 Codex Skill 时，可直接用命令行检查状态。

## 界面怎么看

顶部 `写盘评估` 是主要结论：

| 状态 | 含义 |
|---|---|
| 未检测 | 还没有开始监测 |
| 观察中 | 样本不足，暂时不下结论 |
| 正常 | 当前写盘较低 |
| 少量偏高 | 写盘略高，需要继续观察 |
| 异常偏高 | 写盘明显偏高，建议安装拦截器 |
| 少量偏高已拦截 | 发现少量日志写入尝试，已被拦截 |
| 异常偏高已拦截 | 发现较多日志写入尝试，已被拦截 |

`防护状态` 显示拦截器是否启用。安装拦截保护后会持续生效，不需要每次打开本工具；停止监测或关闭窗口后仍会继续拦截日志写入。

`文件管理` 可以打开 Codex 日志目录、清理当前日志文件、清空历史备份。清理当前日志前请先完全退出 Codex。

注意：`清理文件` 会把当前 `logs_2.sqlite*` 移动到备份目录，原来安装在这个数据库里的拦截器也会一起被移走。如果 GUI 窗口保持打开且拦截保护处于开启状态，重新打开 Codex 后工具会自动检测新的 `logs_2.sqlite` 和 `logs` 表，并自动重新安装拦截器；如果只用命令行清理，则需要重新运行安装命令。

`实时监测` 和 `监测明细` 用来观察任务运行时的真实写盘速度和拦截次数。

## Codex Skill 调用

安装或首次运行后，可以直接对 Codex 说：

```text
帮我检查 Codex 写盘
打开监控面板
安装拦截器
卸载拦截器
清理日志文件
清空备份历史
运行自检
```

在项目目录中可以直接运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\CodexLogGuardCli.ps1 status
```

常用命令：

```powershell
.\tools\CodexLogGuardCli.ps1 status
.\tools\CodexLogGuardCli.ps1 open-gui
.\tools\CodexLogGuardCli.ps1 install
.\tools\CodexLogGuardCli.ps1 uninstall
.\tools\CodexLogGuardCli.ps1 clean
.\tools\CodexLogGuardCli.ps1 self-test
```

## 重要说明

- 仅适用于 Windows。
- 工具脚本本身只占用几十 KB。
- 需要系统中可用的 `python` 或 `py -3`，用于读取和修改 SQLite。
- 本工具是临时排查和止血方案，不是 Codex 官方修复。
- 工具不读取用户消息正文、Codex 回复正文、API Key 或 Token。
