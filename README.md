# claude-usage-tray

**One Windows tray icon for your Claude plan usage (5-hour and weekly limits) and the Claude status page.**
The icon shows the 5-hour percentage on a coloured tile, the weekly percentage as a bar along its bottom edge, and a dot in the corner while Claude Code is not operational.

> [!WARNING]
> **Experimental.** Built and used daily by one person on one Windows 11 machine. Tested on Windows 11 with Windows PowerShell 5.1 (the launcher) and PowerShell 7.6, Claude Code 2.1.308 (2026-10-22). It calls an **undocumented** Anthropic endpoint with your Claude Code login token (see [Limitations](#limitations)), so it can stop working after any Claude Code or API change.

**TL;DR**
- Every 5 minutes it reads your Claude Code OAuth token from `.credentials.json` and asks `api.anthropic.com/api/oauth/usage` for the same numbers the `/usage` screen shows: 5-hour, weekly, and per-model weekly limits.
- Every 60 seconds it reads the public `status.claude.com` summary for Claude Code, claude.ai, the API and Cowork, and lists open incidents.
- Balloon notifications when a limit passes 95% (once per reset window) and when Claude Code's status changes.
- One PowerShell file, WinForms only, no modules, no installer. English by default, Thai optional.
- It replaces my earlier two-icon Python tool, [my fork](https://github.com/MankhongGarden/claude-quota-tray) of kpcrmv4/claude-quota-tray.

---

## What you see

| Where | Shows |
|---|---|
| Tray icon | 5-hour % as the number; tile colour green < 50 %, yellow < 75 %, orange < 90 %, red above; weekly % as the bottom bar; a coloured dot when Claude Code is degraded / in outage / in maintenance |
| Tooltip | `Claude 5h 42% · week 18%` and the Claude Code status |
| Left-click popup | Both limits with reset times, per-model weekly limits when the API returns them, component status, open incidents. Click "refresh" in the header to poll now |
| Right-click menu | Refresh now, open status.claude.com, open the claude.ai usage page, open the log folder, exit |

## Install (Windows)

Requirements: Windows 10/11, Windows PowerShell 5.1 (built in), and Claude Code logged in with a Claude subscription (Pro / Max / Team) on the same Windows account. API-key-only logins have no plan usage to show.

```powershell
git clone https://github.com/MankhongGarden/claude-usage-tray
cd claude-usage-tray
wscript launch.vbs
```

To start it at logon, either put a shortcut to `launch.vbs` in `shell:startup`, or register a task:

```powershell
$vbs = (Resolve-Path .\launch.vbs).Path
$a = New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\wscript.exe" -Argument "`"$vbs`""
$t = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME; $t.Delay = 'PT30S'
Register-ScheduledTask -TaskName ClaudeUsageTray -Action $a -Trigger $t -RunLevel Limited
```

Only one copy runs per data folder (a named mutex); launching it again does nothing.

### Configuration

Optional. Copy `config.example.json` to `config.json` next to the script. All keys are optional:

| Key | Default | Meaning |
|---|---|---|
| `language` | `en` | `en` or `th` |
| `accountLabel` | empty | Shown in the popup header, e.g. `Max` or `Personal` |
| `credentialsFile` | `%CLAUDE_CONFIG_DIR%\.credentials.json`, else `%USERPROFILE%\.claude\.credentials.json` | Where Claude Code stores its login |
| `claudeVersion` | output of `claude --version` | Version string sent in the `User-Agent` header |
| `quotaMinutes` | `5` | Usage poll interval |
| `statusSeconds` | `60` | Status page poll interval |
| `alertPercent` | `95` | Notify when the 5-hour or weekly limit reaches this |
| `pinTray` | `true` | Keep the icon visible on the taskbar instead of the overflow flyout (see below) |
| `dataDir` | `%LOCALAPPDATA%\claude-usage-tray` | Log, notification state and the last raw usage response |

If you run several Claude Code config dirs (for example a work and a personal login), run one copy per login from separate folders, each with its own `credentialsFile` and `dataDir`. Only one copy runs per data folder (a named mutex keyed on `dataDir`).

---

## How it works

- **Usage.** `GET https://api.anthropic.com/api/oauth/usage` with `Authorization: Bearer <claudeAiOauth.accessToken>`, `anthropic-beta: oauth-2025-04-20` and a `claude-code/<version>` User-Agent. It reads `five_hour` and `seven_day` (`utilization`, `resets_at`), and per-model weekly limits from `limits[]` entries of kind `weekly_scoped` (falling back to `seven_day_opus` / `seven_day_sonnet`). The raw body is saved to `last-usage.json` in the data folder so you can see what changed when the format moves.
- **Token handling.** The token is read from the file on each poll and never written anywhere. The tray does **not** refresh an expired token; it tells you to open Claude Code once, which refreshes it.
- **Status.** `GET https://status.claude.com/api/v2/summary.json` (public Statuspage API). Components are matched by their Statuspage IDs. Incidents that touch none of the four components are ignored; scheduled maintenance is shown once it starts.
- **No UI-thread blocking.** Both requests run on `HttpClient` tasks, and a 1-second WinForms timer polls them. A hung network never freezes the menu.
- **Battery.** While on battery, the usage poll is skipped once there is data, to avoid waking the network.
- **429.** On a rate-limit answer it waits 10 minutes before the next usage poll.
- **Pinning.** Windows 11 hides new tray icons in the overflow. Every ~10 minutes the script looks for its own entry under `HKCU\Control Panel\NotifyIconSettings` (matched by the first tooltip, `ClaudeUsageTray`) and sets `IsPromoted = 1`. This touches only that entry. Set `pinTray` to `false` to leave it alone.
- **Testing the status view.** Set `CLAUDE_USAGE_TRAY_STATUS_FILE` to a saved `summary.json` to render it instead of the live page.

## Limitations

- **Undocumented endpoint.** `/api/oauth/usage` returns the same limits Claude Code's `/usage` screen shows. It is not a public API and it may reject clients or change without notice. The tray identifies itself with a Claude Code User-Agent because the endpoint expects one.
- **Uses your login token.** The script sends the token only to `api.anthropic.com`. Read the script before running it, as you would with any tool that touches credentials.
- **Windows only.** WinForms + GDI+ from PowerShell. On macOS, Claude Code keeps the token in the Keychain, not in a file.
- **Read-only.** It never refreshes, rotates or writes the token, so after a long time without opening Claude Code the token expires and the tray shows that until you open Claude Code.
- **No screenshot yet.**

## License

MIT, see [LICENSE](LICENSE).
