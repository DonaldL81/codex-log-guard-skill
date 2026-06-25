---
name: codex-log-guard-skill
description: Check and mitigate Codex local logs_2.sqlite abnormal disk writes on Windows. Use when the user asks to inspect Codex write activity, open the Codex write monitor panel, install or remove the log guard, clean Codex logs, or troubleshoot Codex logs_2.sqlite disk usage.
---

# Codex Log Guard

Use this skill for Windows Codex `logs_2.sqlite` write checks and temporary mitigation.

## Entry Points

Resolve the skill directory as the folder containing this `SKILL.md`.

- Open GUI panel: run `tools/CodexLogGuardCli.ps1 open-gui`.
- Check status without opening GUI: run `tools/CodexLogGuardCli.ps1 status -Json`.
- Install log guard: run `tools/CodexLogGuardCli.ps1 install`.
- Remove log guard: run `tools/CodexLogGuardCli.ps1 uninstall`.
- Clean current Codex log files after Codex fully exits: run `tools/CodexLogGuardCli.ps1 clean`.
- Clear backup history only: run `tools/CodexLogGuardCli.ps1 clear-backup`.
- Self-test: run `tools/CodexLogGuardCli.ps1 self-test`.

Use PowerShell like:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\CodexLogGuardCli.ps1 status -Json
```

## Behavior

- If the user asks to "打开监控面板", "打开 GUI", or wants to watch live data, open the GUI.
- If the user asks to "检查写盘", "看看是否异常", or asks for a diagnosis, call `status -Json` and summarize the result.
- If the user asks to install protection, call `install` and explain that the guard remains active after the GUI closes.
- If the user asks to clean logs, tell them Codex should be fully exited first, then call `clean`.

## Safety

- Do not force-close Codex unless the user explicitly asks.
- Do not delete `C:\Users\<user>\.codex` wholesale.
- Do not read or print user message bodies, API keys, tokens, or unrelated Codex state.
- Treat `monitor-logs` and `logs_backup` as local runtime artifacts, not files to publish.
