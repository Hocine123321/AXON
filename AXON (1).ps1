# ================================================================
#  AXON — AI Agent Framework
#  Phase 1-7 : Foundation (TUI, Profiles, API, Tags, Safety, Logs)
#  v1.0 Mega A: Smart Brain, Real Streaming, Auto Functions,
#               New Tags ($SEARCH$ $OPEN$ $NOTIFY$ $CLIP$ $MACRO$
#               $STATUS$ $PLUGIN$), Function Registry, Context Mgr
#  v1.1 Mega B: Atomic Writes, Health Check, Deferred Approval,
#               QoL Commands (/status /pending /recent /last /context
#               /retry /fixlast), Profile Tools (/test /clone /doctor),
#               History Tools (/search /resume /export),
#               Error Recovery Loop, Convenience (/open /logs /temp clean),
#               Intent Classifier (local routing), Multi-Step Task Tracker
#               ($TASK$ tag + /tasks command)
#  Version: 1.1.0
# ================================================================

#SAFETY_START
# !! THIS SECTION IS NEVER SENT TO THE AI !!
# !! DO NOT MODIFY !!
$AXON_PROTECTED_PATHS = @(
    "C:\Windows\System32",
    "C:\Windows\SysWOW64",
    "C:\Program Files",
    "C:\Program Files (x86)",
    "$env:APPDATA\Microsoft",
    "$env:WINDIR"
)
$AXON_SELF_PATH = $MyInvocation.MyCommand.Path
#SAFETY_END


# ================================================================
#  GLOBAL STATE
# ================================================================

$AXON_VERSION  = "1.1.0"
$AXON_NAME     = "AXON"
$SESSION_ID    = Get-Date -Format "yyyyMMdd-HHmmss"
$DataFolder    = Join-Path ([Environment]::GetFolderPath("Desktop")) "AXON Data"

$State = @{
    ActiveProfile        = $null
    SessionNumber        = 1
    SandboxMode          = $false
    ChatHistory          = [System.Collections.ArrayList]@()
    PendingAction        = $null
    LastCodeBlock        = $null
    LastUserInput        = ""
    LastAIReply          = ""
    SessionStart         = Get-Date
    ExecutionCount       = 0
    ExecutionWindowStart = Get-Date
    UndoStack            = [System.Collections.ArrayList]@()
    MessageCount         = 0
    SessionLogPath       = $null
    AICallCount          = 0
    LastAPIError         = ""
    # v1.0 — Smart Brain
    SmartMemory          = @{}
    # v1.0 — Context manager
    TokenEstimate        = 0
    MaxContextTokens     = 6000
    # v1.0 — Function registry
    FunctionRegistry     = [ordered]@{}
    # v1.0 — Macros
    Macros               = @{}
    # v1.0 — Plugins loaded this session
    LoadedPlugins        = [System.Collections.ArrayList]@()
    # v1.0 — Status bar message
    StatusBarMsg         = ""
    # v1.1 — Deferred approval queue
    ApprovalQueue        = [System.Collections.ArrayList]@()
    # v1.1 — Multi-step task tracker
    Tasks                = [System.Collections.ArrayList]@()
}


# ================================================================
#  UI — COLORS & SYMBOLS
# ================================================================

$UI = @{
    Border    = "DarkCyan"
    Header    = "Cyan"
    UserLabel = "Yellow"
    AILabel   = "Cyan"
    SysLabel  = "DarkCyan"
    SysText   = "DarkGray"
    OkText    = "Green"
    ErrText   = "Red"
    WarnText  = "Yellow"
    PendText  = "Magenta"
    DimText   = "DarkGray"
    BodyText  = "Gray"
    CmdHint   = "DarkCyan"
    TaskDone  = "Green"
    TaskPend  = "Cyan"
    TaskWait  = "DarkGray"
}


# ================================================================
#  UI — HELPERS
# ================================================================

function Get-WindowWidth {
    try { return [Math]::Max($Host.UI.RawUI.WindowSize.Width, 72) }
    catch { return 80 }
}

function Write-Divider {
    param([string]$Char = "═", [string]$Color = $UI.Border)
    Write-Host ($Char * (Get-WindowWidth)) -ForegroundColor $Color
}

function Write-ThinDivider {
    Write-Host ("  " + ("─" * ([Math]::Max((Get-WindowWidth) - 4, 40)))) -ForegroundColor $UI.Border
}

function Write-Header {
    $profileLabel = if ($State.ActiveProfile) { $State.ActiveProfile.profile_name } else { "No Profile" }
    $sessionLabel = "Session #$($State.SessionNumber)"
    $sandboxTag   = if ($State.SandboxMode) { "  [SANDBOX]" } else { "" }
    $tokenLabel   = if ($State.TokenEstimate -gt 0) { "  ~$($State.TokenEstimate)t" } else { "" }
    $pluginLabel  = if ($State.LoadedPlugins.Count -gt 0) { "  +$($State.LoadedPlugins.Count) plugin(s)" } else { "" }
    $taskLabel    = if ($State.Tasks.Count -gt 0) {
        $done = ($State.Tasks | Where-Object { $_.status -eq "done" }).Count
        "  Tasks $done/$($State.Tasks.Count)"
    } else { "" }
    $pendLabel    = if ($State.ApprovalQueue.Count -gt 0) { "  [$($State.ApprovalQueue.Count) pending]" } else { "" }

    Write-Divider
    Write-Host "  $AXON_NAME  •  $profileLabel  •  $sessionLabel$sandboxTag$tokenLabel$pluginLabel$taskLabel$pendLabel" -ForegroundColor $UI.Header
    if ($State.StatusBarMsg) {
        Write-Host "  $($State.StatusBarMsg)" -ForegroundColor $UI.SysText
    }
    Write-Divider
}

function Write-Footer {
    Write-Divider
}

function Write-Msg {
    param(
        [ValidateSet("user","ai","system","ok","error","warn","pending")]
        [string]$Role,
        [string]$Content
    )

    Write-Host ""
    switch ($Role) {
        "user"    { Write-Host "  You : " -ForegroundColor $UI.UserLabel -NoNewline; Write-Host $Content -ForegroundColor White }
        "ai"      { Write-Host "  AI  : " -ForegroundColor $UI.AILabel   -NoNewline; Write-Host $Content -ForegroundColor $UI.BodyText }
        "system"  { Write-Host "  o   " -ForegroundColor $UI.SysLabel   -NoNewline; Write-Host $Content -ForegroundColor $UI.SysText }
        "ok"      { Write-Host "  v   " -ForegroundColor Green          -NoNewline; Write-Host $Content -ForegroundColor $UI.OkText }
        "error"   { Write-Host "  x   " -ForegroundColor Red            -NoNewline; Write-Host $Content -ForegroundColor $UI.ErrText }
        "warn"    { Write-Host "  !   " -ForegroundColor Yellow         -NoNewline; Write-Host $Content -ForegroundColor $UI.WarnText }
        "pending" { Write-Host "  ?   " -ForegroundColor Magenta        -NoNewline; Write-Host $Content -ForegroundColor $UI.PendText }
    }
}

function Show-Banner {
    [Console]::Clear()
    $w = Get-WindowWidth
    $pad = " " * ([Math]::Max(([int](($w - 26) / 2)), 0))

    Write-Host ""
    Write-Host "${pad}╔══════════════════════════╗" -ForegroundColor Cyan
    Write-Host "${pad}║                          ║" -ForegroundColor Cyan
    Write-Host "${pad}║    A  X  O  N   v1.1     ║" -ForegroundColor Cyan
    Write-Host "${pad}║                          ║" -ForegroundColor Cyan
    Write-Host "${pad}╚══════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "${pad}  AI Agent Framework  —  Mega Phase B" -ForegroundColor DarkGray
    Write-Host "${pad}  Pure PowerShell. No dependencies." -ForegroundColor DarkGray
    Write-Host ""
    Start-Sleep -Milliseconds 1400
}

function Show-SlashHints {
    $hints = @("/help","/status","/tasks","/pending","/settings","/profile","/history","/files","/sandbox","/brake","/exit")
    Write-Host ""
    Write-Host "  Commands: " -ForegroundColor $UI.DimText -NoNewline
    Write-Host ($hints -join "   ") -ForegroundColor $UI.CmdHint
    Write-Host ""
}


# ================================================================
#  DATA FOLDER — INIT
# ================================================================

function Initialize-DataFolder {
    $dirs = @(
        $DataFolder,
        "$DataFolder\profiles",
        "$DataFolder\sessions",
        "$DataFolder\temp",
        "$DataFolder\workspace",
        "$DataFolder\logs",
        "$DataFolder\plugins",
        "$DataFolder\macros"
    )
    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
    }

    # Default settings — normalize missing keys on every load
    $settingsPath = "$DataFolder\settings.json"
    $defaults = [ordered]@{
        active_profile            = $null
        script_name               = "AXON"
        blocked_paths             = @(
            "C:\Windows\System32",
            "C:\Windows\SysWOW64",
            "C:\Program Files",
            "C:\Program Files (x86)"
        )
        user_blocked_paths        = @()
        max_executions_per_minute = 5
        dry_run_before_execute    = $true
        auto_memory               = $true
        streaming                 = $false
        approval_timeout_seconds  = 30
    }

    if (Test-Path $settingsPath) {
        # Merge — add any keys that don't exist yet (forward-compat)
        $existing = Get-Content $settingsPath -Raw | ConvertFrom-Json
        $changed = $false
        foreach ($key in $defaults.Keys) {
            if ($null -eq $existing.$key) {
                $existing | Add-Member -NotePropertyName $key -NotePropertyValue $defaults[$key] -Force
                $changed = $true
            }
        }
        if ($changed) {
            Write-SettingsAtomic -Settings $existing
        }
    } else {
        $defaults | ConvertTo-Json -Depth 5 | Set-Content -Path $settingsPath -Encoding UTF8
    }

    # Default memory
    $memPath = "$DataFolder\memory.txt"
    if (-not (Test-Path $memPath)) {
        Set-Content -Path $memPath -Value "No previous memory." -Encoding UTF8
    }

    # Session counter — count real session files (exclude current partial)
    $sessions = Get-ChildItem "$DataFolder\sessions" -Filter "*.json" -ErrorAction SilentlyContinue
    $State.SessionNumber = ($sessions.Count) + 1
}

# ── Atomic write for settings — prevents corruption on crash ──
function Write-SettingsAtomic {
    param($Settings)
    $sp  = "$DataFolder\settings.json"
    $tmp = "$sp.tmp"
    try {
        $Settings | ConvertTo-Json -Depth 5 | Set-Content -Path $tmp -Encoding UTF8
        Move-Item -Path $tmp -Destination $sp -Force
    } catch {
        # If move fails, fall back to direct write
        $Settings | ConvertTo-Json -Depth 5 | Set-Content -Path $sp -Encoding UTF8
    }
}

function Get-Settings {
    $p = "$DataFolder\settings.json"
    if (Test-Path $p) { return Get-Content $p -Raw | ConvertFrom-Json }
    return $null
}

function Write-ActionLog {
    param([string]$Entry)
    $logPath = "$DataFolder\logs\actions.log"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    try {
        Add-Content -Path $logPath -Value "[$timestamp]  $Entry" -Encoding UTF8 -ErrorAction Stop
    } catch {
        # Retry once after brief delay if log is locked
        Start-Sleep -Milliseconds 50
        try { Add-Content -Path $logPath -Value "[$timestamp]  $Entry" -Encoding UTF8 } catch {}
    }
}


# ================================================================
#  v1.1 — STARTUP HEALTH CHECK
# ================================================================

function Invoke-StartupHealthCheck {
    $issues = [System.Collections.ArrayList]@()

    # 1. Data folder writable?
    try {
        $testPath = "$DataFolder\_health_check_test_"
        [System.IO.File]::WriteAllText($testPath, "ok")
        Remove-Item $testPath -Force -ErrorAction SilentlyContinue
    } catch {
        $issues.Add("Data folder is not writable: $DataFolder") | Out-Null
    }

    # 2. Settings file readable?
    $s = Get-Settings
    if (-not $s) { $issues.Add("settings.json is missing or corrupt — defaults will be used.") | Out-Null }

    # 3. Profile check
    if ($State.ActiveProfile) {
        if ([string]::IsNullOrWhiteSpace($State.ActiveProfile.api_key) -and
            $State.ActiveProfile.provider -ne "ollama") {
            $issues.Add("Active profile '$($State.ActiveProfile.profile_name)' has no API key set.") | Out-Null
        }
        if ([string]::IsNullOrWhiteSpace($State.ActiveProfile.api_url)) {
            $issues.Add("Active profile '$($State.ActiveProfile.profile_name)' has no API URL set.") | Out-Null
        }
    }

    # 4. PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        $issues.Add("PowerShell 5.1+ recommended. Current: $($PSVersionTable.PSVersion)") | Out-Null
    }

    # 5. Stale temp files warning
    $tempPath = "$DataFolder\temp"
    $staleTemp = Get-ChildItem $tempPath -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) }
    if ($staleTemp -and $staleTemp.Count -gt 0) {
        $issues.Add("$($staleTemp.Count) stale file(s) in temp/ (>7 days). Use /temp clean to remove.") | Out-Null
    }

    if ($issues.Count -gt 0) {
        Write-Host ""
        Write-Host "  Health Check Warnings:" -ForegroundColor Yellow
        foreach ($issue in $issues) {
            Write-Host "    ! $issue" -ForegroundColor Yellow
        }
        Write-ActionLog "HEALTH CHECK — $($issues.Count) warning(s): $($issues -join '; ')"
    } else {
        Write-ActionLog "HEALTH CHECK — OK"
    }

    return $issues
}


# ================================================================
#  COMMAND HANDLERS — HELP
# ================================================================

function Invoke-HelpCommand {
    Write-Host ""
    Write-ThinDivider
    Write-Host "   $AXON_NAME  v$AXON_VERSION  —  Command Reference" -ForegroundColor $UI.Header
    Write-ThinDivider

    $sections = [ordered]@{
        "NAVIGATION" = @(
            @{cmd="/help";               desc="Show this command reference"},
            @{cmd="/clear";              desc="Clear the chat display (context preserved)"},
            @{cmd="/exit";               desc="Close AXON cleanly"}
        )
        "AI & PROFILES" = @(
            @{cmd="/profile";            desc="View or switch active profile"},
            @{cmd="/profile new";        desc="Create a new AI provider profile"},
            @{cmd="/profile delete";     desc="Remove a profile"},
            @{cmd="/profile test";       desc="Send a test ping to verify the active profile works"},
            @{cmd="/profile clone [n]";  desc="Duplicate a profile under a new name"},
            @{cmd="/profile doctor";     desc="Diagnose the active profile for config issues"},
            @{cmd="/reload";             desc="Resend system prompt to AI (fresh brain)"},
            @{cmd="/inject [text]";      desc="Add hidden context to the next AI message"}
        )
        "SESSION STATUS" = @(
            @{cmd="/status";             desc="Show current session status dashboard"},
            @{cmd="/last";               desc="Show the last AI reply again"},
            @{cmd="/recent";             desc="Show the last 5 turns of this session"},
            @{cmd="/context";            desc="Show what is in the AI context window right now"},
            @{cmd="/retry";              desc="Retry the last user message (re-sends to AI)"},
            @{cmd="/fixlast";            desc="Ask the AI to improve its last response"}
        )
        "TASKS" = @(
            @{cmd="/tasks";              desc="Show the multi-step task tracker"},
            @{cmd="/tasks clear";        desc="Clear all tasks from the tracker"}
        )
        "APPROVAL QUEUE" = @(
            @{cmd="/pending";            desc="Review all queued deferred actions"},
            @{cmd="/approve";            desc="Approve the next pending action"},
            @{cmd="/deny";               desc="Deny and discard the next pending action"},
            @{cmd="/approve all";        desc="Approve all pending actions at once"},
            @{cmd="/deny all";           desc="Deny and discard all pending actions"}
        )
        "SESSION & HISTORY" = @(
            @{cmd="/history";            desc="Browse past sessions"},
            @{cmd="/history search [q]"; desc="Search past session transcripts for a keyword"},
            @{cmd="/history resume [n]"; desc="Load a past session's context and continue"},
            @{cmd="/history export [n]"; desc="Export session to a readable .txt file"},
            @{cmd="/log";                desc="View this session's action log"},
            @{cmd="/memory";             desc="View the AI's memory from last session"},
            @{cmd="/macro";              desc="List saved macros  (/macro list / delete [name])"}
        )
        "FILES & EXECUTION" = @(
            @{cmd="/files";              desc="Browse Data folder contents"},
            @{cmd="/open [path]";        desc="Open a file or URL from the command line"},
            @{cmd="/peek [path]";        desc="Preview a file (first 50 lines, size, modified)"},
            @{cmd="/exec";               desc="Re-run the last code block"},
            @{cmd="/undo";               desc="Attempt to reverse last action"},
            @{cmd="/temp";               desc="Show files in temp/ awaiting approval"},
            @{cmd="/temp clean";         desc="Delete all files from the temp/ folder now"},
            @{cmd="/logs clean";         desc="Archive and rotate the action log"}
        )
        "SAFETY" = @(
            @{cmd="/sandbox";            desc="Toggle sandbox mode — simulates everything, runs nothing"},
            @{cmd="/lock [path]";        desc="Add a path to your personal blocklist"},
            @{cmd="/unlock [path]";      desc="Remove a path from your blocklist"},
            @{cmd="/brake";              desc="!! EMERGENCY STOP — halts all running jobs immediately !!"}
        )
        "SETTINGS" = @(
            @{cmd="/settings";           desc="Open the settings menu"}
        )
    }

    foreach ($section in $sections.Keys) {
        Write-Host ""
        Write-Host "   $section" -ForegroundColor $UI.DimText
        foreach ($item in $sections[$section]) {
            Write-Host ("   {0,-32} {1}" -f $item.cmd, $item.desc) -ForegroundColor $UI.BodyText
        }
    }

    Write-Host ""
    Write-ThinDivider
}

function Invoke-ClearCommand {
    [Console]::Clear()
    Write-Header
    Write-Msg -Role "system" -Content "Display cleared. Chat context is preserved."
}

function Invoke-ExitCommand {
    Write-Host ""
    Write-Host "  Shutting down AXON..." -ForegroundColor $UI.DimText
    Write-ActionLog "SESSION ENDED — Session #$($State.SessionNumber)"

    Invoke-AutoMemory
    Save-SessionLog
    Clear-TempFolder
    Show-SessionStats

    Write-Host ""
    Write-Host "  Goodbye." -ForegroundColor $UI.DimText
    Write-Host ""
    exit
}

function Invoke-SandboxCommand {
    $State.SandboxMode = -not $State.SandboxMode
    if ($State.SandboxMode) {
        Write-Msg -Role "warn" -Content "SANDBOX MODE ON — executions are simulated. Nothing runs for real."
    } else {
        Write-Msg -Role "ok"   -Content "Sandbox mode OFF — executions are live."
    }
    Write-ActionLog "Sandbox mode toggled: $($State.SandboxMode)"
}

function Invoke-BrakeCommand {
    Write-Host ""
    Write-Host "  ██████████████████████████████████████" -ForegroundColor Red
    Write-Host "  ██   EMERGENCY BRAKE  ACTIVATED     ██" -ForegroundColor Red
    Write-Host "  ██████████████████████████████████████" -ForegroundColor Red

    $State.PendingAction = $null
    $State.LastCodeBlock = $null
    $State.ApprovalQueue.Clear()

    try {
        Get-Job | Stop-Job  -ErrorAction SilentlyContinue
        Get-Job | Remove-Job -ErrorAction SilentlyContinue
    } catch {}

    Write-Msg -Role "system" -Content "All jobs stopped. Pending actions and approval queue cleared. System is idle."
    Write-ActionLog "!! EMERGENCY BRAKE ACTIVATED !!"
}


# ================================================================
#  v1.1 — STATUS DASHBOARD
# ================================================================

function Invoke-StatusCommand {
    $duration = [Math]::Round(((Get-Date) - $State.SessionStart).TotalMinutes, 1)
    $profile  = if ($State.ActiveProfile) { "$($State.ActiveProfile.profile_name)  ($($State.ActiveProfile.provider) / $($State.ActiveProfile.model))" } else { "No profile loaded" }

    Write-Host ""
    Write-ThinDivider
    Write-Host "   AXON v$AXON_VERSION — Session Status" -ForegroundColor $UI.Header
    Write-ThinDivider
    Write-Host ("   {0,-28} {1}" -f "Session #:",      $State.SessionNumber)           -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-28} {1}" -f "Profile:",        $profile)                       -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-28} {1}" -f "Duration:",       "$duration min")                -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-28} {1}" -f "AI calls:",       $State.AICallCount)             -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-28} {1}" -f "Code executions:", $State.ExecutionCount)         -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-28} {1}" -f "Chat turns:",     $State.ChatHistory.Count)       -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-28} {1}" -f "Context tokens:", "~$($State.TokenEstimate)")     -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-28} {1}" -f "Sandbox mode:",   $State.SandboxMode)             -ForegroundColor $(if ($State.SandboxMode) { "Yellow" } else { $UI.BodyText })
    Write-Host ("   {0,-28} {1}" -f "Pending actions:", $State.ApprovalQueue.Count)    -ForegroundColor $(if ($State.ApprovalQueue.Count -gt 0) { "Magenta" } else { $UI.BodyText })
    Write-Host ("   {0,-28} {1}" -f "Tasks:",          "$( ($State.Tasks | Where-Object {$_.status -eq 'done'}).Count )/$($State.Tasks.Count) done") -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-28} {1}" -f "Loaded plugins:", $State.LoadedPlugins.Count)     -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-28} {1}" -f "Undo stack:",     "$($State.UndoStack.Count) entries") -ForegroundColor $UI.BodyText
    if ($State.StatusBarMsg) {
        Write-Host ""
        Write-Host ("   Status bar: $($State.StatusBarMsg)") -ForegroundColor $UI.SysText
    }
    if ($State.LastAPIError) {
        Write-Host ""
        Write-Host ("   Last API error: $($State.LastAPIError)") -ForegroundColor $UI.ErrText
    }
    Write-ThinDivider
    Write-Host "   /recent  → last 5 turns  |  /context → context window  |  /tasks → task list" -ForegroundColor $UI.DimText
    Write-ThinDivider
}


# ================================================================
#  v1.1 — LAST / RECENT / CONTEXT / RETRY / FIXLAST
# ================================================================

function Invoke-LastCommand {
    if ([string]::IsNullOrWhiteSpace($State.LastAIReply)) {
        Write-Msg -Role "system" -Content "No AI reply yet this session."
        return
    }
    Write-Host ""
    Write-ThinDivider
    Write-Host "   Last AI Reply" -ForegroundColor $UI.Header
    Write-ThinDivider
    Write-Host ""
    Write-AIResponse -Text $State.LastAIReply
    Write-Host ""
    Write-ThinDivider
}

function Invoke-RecentCommand {
    $turns = $State.ChatHistory | Where-Object {
        $_.content -notlike "[AXON*" -and $_.content -notlike "[CONTEXT*"
    } | Select-Object -Last 10

    if (-not $turns -or @($turns).Count -eq 0) {
        Write-Msg -Role "system" -Content "No turns this session."
        return
    }

    Write-Host ""
    Write-ThinDivider
    Write-Host "   Recent Turns (last 5 exchanges)" -ForegroundColor $UI.Header
    Write-ThinDivider

    foreach ($t in $turns) {
        Write-Host ""
        if ($t.role -eq "user") {
            Write-Host "  You : " -ForegroundColor $UI.UserLabel -NoNewline
            $preview = if ($t.content.Length -gt 120) { $t.content.Substring(0,120) + "..." } else { $t.content }
            Write-Host $preview -ForegroundColor White
        } else {
            Write-Host "  AI  : " -ForegroundColor $UI.AILabel -NoNewline
            $preview = if ($t.content.Length -gt 160) { $t.content.Substring(0,160) + "..." } else { $t.content }
            Write-Host $preview -ForegroundColor $UI.BodyText
        }
    }

    Write-Host ""
    Write-ThinDivider
}

function Invoke-ContextCommand {
    Write-Host ""
    Write-ThinDivider
    Write-Host "   Context Window  (~$($State.TokenEstimate) tokens  /  $($State.ChatHistory.Count) messages)" -ForegroundColor $UI.Header
    Write-ThinDivider

    if ($State.ChatHistory.Count -eq 0) {
        Write-Host "   Context is empty." -ForegroundColor $UI.DimText
        Write-ThinDivider; return
    }

    $i = 1
    foreach ($msg in $State.ChatHistory) {
        $role = $msg.role.PadRight(9)
        $preview = if ($msg.content.Length -gt 100) { $msg.content.Substring(0,100) + "..." } else { $msg.content }
        $color   = if ($msg.role -eq "user") { $UI.UserLabel } elseif ($msg.role -eq "assistant") { $UI.AILabel } else { $UI.DimText }
        Write-Host ("   [{0,2}] {1}: {2}" -f $i, $role, $preview) -ForegroundColor $color
        $i++
    }

    Write-Host ""
    Write-ThinDivider
    Write-Host "   Tip: /reload clears this and gives the AI a fresh start." -ForegroundColor $UI.DimText
    Write-ThinDivider
}

function Invoke-RetryCommand {
    if ([string]::IsNullOrWhiteSpace($State.LastUserInput)) {
        Write-Msg -Role "system" -Content "No previous message to retry."
        return
    }

    Write-Msg -Role "system" -Content "Retrying last message: '$($State.LastUserInput)'"

    # Remove the last user + assistant pair from history so we don't duplicate
    $history = $State.ChatHistory
    $lastUser = -1
    for ($i = $history.Count - 1; $i -ge 0; $i--) {
        if ($history[$i].role -eq "user" -and $history[$i].content -eq $State.LastUserInput) {
            $lastUser = $i
            break
        }
    }
    if ($lastUser -ge 0) {
        # Remove user message and any assistant reply after it
        while ($history.Count -gt $lastUser) { $history.RemoveAt($lastUser) }
    }

    # Re-inject and call AI
    return $State.LastUserInput
}

function Invoke-FixLastCommand {
    if ([string]::IsNullOrWhiteSpace($State.LastAIReply)) {
        Write-Msg -Role "system" -Content "No AI reply to fix yet."
        return
    }

    Write-Msg -Role "system" -Content "Asking AI to improve its last response..."
    return "[AXON /fixlast] Please review your previous response and improve it — be more detailed, clear, and accurate. Provide the improved version now."
}


# ================================================================
#  v1.1 — MULTI-STEP TASK TRACKER
# ================================================================

function Invoke-TasksCommand {
    param([string]$Sub = "")

    if ($Sub -eq "clear") {
        $State.Tasks.Clear()
        Write-Msg -Role "ok" -Content "Task list cleared."
        Write-ActionLog "Tasks cleared by user"
        return
    }

    Write-Host ""
    Write-ThinDivider
    Write-Host "   Multi-Step Task Tracker" -ForegroundColor $UI.Header
    Write-ThinDivider

    if ($State.Tasks.Count -eq 0) {
        Write-Host "   No tasks yet. The AI can create tasks using the " -ForegroundColor $UI.DimText -NoNewline
        Write-Host '$TASK$...$ENDTASK$' -ForegroundColor Cyan -NoNewline
        Write-Host " tag." -ForegroundColor $UI.DimText
        Write-ThinDivider; return
    }

    $done  = ($State.Tasks | Where-Object { $_.status -eq "done"     }).Count
    $inprog= ($State.Tasks | Where-Object { $_.status -eq "active"   }).Count
    $wait  = ($State.Tasks | Where-Object { $_.status -eq "waiting"  }).Count

    Write-Host ("   {0}/{1} done   {2} active   {3} waiting" -f $done, $State.Tasks.Count, $inprog, $wait) -ForegroundColor $UI.SysText
    Write-Host ""

    $i = 1
    foreach ($task in $State.Tasks) {
        $icon  = switch ($task.status) {
            "done"    { "[v]" }
            "active"  { "[>]" }
            "waiting" { "[ ]" }
            default   { "[ ]" }
        }
        $color = switch ($task.status) {
            "done"    { $UI.TaskDone }
            "active"  { $UI.TaskPend }
            "waiting" { $UI.TaskWait }
            default   { $UI.BodyText }
        }
        $note = if ($task.note) { "  — $($task.note)" } else { "" }
        Write-Host ("   {0} {1,2}. {2}{3}" -f $icon, $i, $task.title, $note) -ForegroundColor $color
        $i++
    }

    Write-Host ""
    Write-ThinDivider
    Write-Host "   /tasks clear  → remove all tasks" -ForegroundColor $UI.DimText
    Write-ThinDivider
}

function Add-Task {
    param([string]$Title, [string]$Note = "", [string]$Status = "waiting")
    $State.Tasks.Add([ordered]@{
        id     = [guid]::NewGuid().ToString("N").Substring(0,8)
        title  = $Title
        note   = $Note
        status = $Status
        added  = (Get-Date -Format "HH:mm:ss")
    }) | Out-Null
    Write-ActionLog "TASK ADDED: $Title [$Status]"
}

function Set-TaskStatus {
    param([string]$TitleOrId, [string]$Status)
    foreach ($t in $State.Tasks) {
        if ($t.title -like "*$TitleOrId*" -or $t.id -eq $TitleOrId) {
            $t.status = $Status
            Write-ActionLog "TASK STATUS: '$($t.title)' -> $Status"
            return $true
        }
    }
    return $false
}


# ================================================================
#  v1.1 — DEFERRED APPROVAL QUEUE
# ================================================================

function Add-ApprovalItem {
    param([string]$Type, [string]$Description, [scriptblock]$Action)
    $item = [ordered]@{
        id          = [guid]::NewGuid().ToString("N").Substring(0,8)
        type        = $Type
        description = $Description
        action      = $Action
        added_at    = (Get-Date -Format "HH:mm:ss")
    }
    $State.ApprovalQueue.Add($item) | Out-Null
    Write-Msg -Role "pending" -Content "Queued for approval: [$Type] $Description  (use /pending to review)"
    Write-ActionLog "APPROVAL QUEUED: [$Type] $Description"
}

function Invoke-PendingCommand {
    param([string]$Sub = "")

    if ($Sub -eq "all" -or $Sub -eq "approve all") { Invoke-ApproveAllCommand; return }
    if ($Sub -eq "deny all")                        { Invoke-DenyAllCommand;    return }

    Write-Host ""
    Write-ThinDivider
    Write-Host "   Pending Approval Queue  ($($State.ApprovalQueue.Count) items)" -ForegroundColor $UI.Header
    Write-ThinDivider

    if ($State.ApprovalQueue.Count -eq 0) {
        Write-Host "   Nothing pending." -ForegroundColor $UI.DimText
        Write-ThinDivider; return
    }

    $i = 1
    foreach ($item in $State.ApprovalQueue) {
        Write-Host ("   [{0}] {1,-10} {2}  (added {3})" -f $i, "[$($item.type)]", $item.description, $item.added_at) -ForegroundColor $UI.PendText
        $i++
    }

    Write-Host ""
    Write-ThinDivider
    Write-Host "   /approve      → approve next item (executes it)" -ForegroundColor $UI.DimText
    Write-Host "   /deny         → deny and discard next item" -ForegroundColor $UI.DimText
    Write-Host "   /approve all  → approve everything" -ForegroundColor $UI.DimText
    Write-Host "   /deny all     → discard everything" -ForegroundColor $UI.DimText
    Write-ThinDivider
}

function Invoke-ApproveCommand {
    if ($State.ApprovalQueue.Count -eq 0) {
        Write-Msg -Role "system" -Content "No pending actions. Approvals happen inline when the AI requests them."
        return
    }

    $item = $State.ApprovalQueue[0]
    $State.ApprovalQueue.RemoveAt(0)

    Write-Msg -Role "system" -Content "Executing: [$($item.type)] $($item.description)"
    try {
        $result = & $item.action
        Write-Msg -Role "ok" -Content "Done: $($item.description)"
        Write-ActionLog "APPROVAL EXECUTED: [$($item.type)] $($item.description)"
        if ($result) {
            $State.ChatHistory.Add(@{
                role    = "user"
                content = "[AXON DEFERRED EXECUTION FEEDBACK]`n[$($item.type)] $($item.description)`nResult: $result"
            }) | Out-Null
            $State.ChatHistory.Add(@{
                role    = "assistant"
                content = "Understood. Deferred action executed successfully."
            }) | Out-Null
        }
    } catch {
        Write-Msg -Role "error" -Content "Execution failed: $($_.Exception.Message)"
        Write-ActionLog "APPROVAL EXEC FAILED: [$($item.type)] $($_.Exception.Message)"
    }
}

function Invoke-DenyCommand {
    if ($State.ApprovalQueue.Count -eq 0) {
        Write-Msg -Role "system" -Content "No pending action to deny."
        return
    }
    $item = $State.ApprovalQueue[0]
    $State.ApprovalQueue.RemoveAt(0)
    Write-Msg -Role "ok" -Content "Denied and discarded: $($item.description)"
    Write-ActionLog "APPROVAL DENIED: [$($item.type)] $($item.description)"
}

function Invoke-ApproveAllCommand {
    if ($State.ApprovalQueue.Count -eq 0) {
        Write-Msg -Role "system" -Content "Nothing to approve."
        return
    }
    $count = $State.ApprovalQueue.Count
    Write-Host ""
    Write-Host "  Approve all $count pending action(s)? (y/n): " -ForegroundColor $UI.WarnText -NoNewline
    if ((Read-Host).Trim().ToLower() -notin @("y","yes")) {
        Write-Msg -Role "system" -Content "Cancelled."
        return
    }

    $items = @($State.ApprovalQueue)  # snapshot
    $State.ApprovalQueue.Clear()

    foreach ($item in $items) {
        Write-Msg -Role "system" -Content "Executing: [$($item.type)] $($item.description)"
        try {
            & $item.action | Out-Null
            Write-Msg -Role "ok" -Content "Done: $($item.description)"
            Write-ActionLog "APPROVE ALL EXECUTED: [$($item.type)] $($item.description)"
        } catch {
            Write-Msg -Role "error" -Content "Failed: $($item.description) — $($_.Exception.Message)"
        }
    }
    Write-Msg -Role "ok" -Content "All $count action(s) processed."
}

function Invoke-DenyAllCommand {
    if ($State.ApprovalQueue.Count -eq 0) {
        Write-Msg -Role "system" -Content "Nothing to deny."
        return
    }
    $count = $State.ApprovalQueue.Count
    $State.ApprovalQueue.Clear()
    Write-Msg -Role "ok" -Content "All $count pending action(s) denied and discarded."
    Write-ActionLog "DENY ALL — $count items discarded"
}


# ================================================================
#  PROFILE COMMANDS — VIEW / SWITCH / NEW / DELETE
# ================================================================

function Invoke-ProfileCommand {
    param([string]$Sub = "")

    switch -Regex ($Sub.Trim().ToLower()) {

        '^new$'         { New-Profile }

        '^delete$'      { Remove-Profile }

        '^test$'        { Invoke-ProfileTest }

        '^doctor$'      { Invoke-ProfileDoctor }

        '^clone(\s+.+)?$' {
            $targetName = ($Sub -replace '^clone\s*', '').Trim()
            Invoke-ProfileClone -SourceName $targetName
        }

        default {
            if ($Sub -ne "") {
                Switch-Profile -Name $Sub
                return
            }

            $profilesDir = "$DataFolder\profiles"
            $profiles    = Get-ChildItem $profilesDir -Filter "*.json" -ErrorAction SilentlyContinue

            Write-Host ""
            Write-ThinDivider
            Write-Host "   Profiles" -ForegroundColor $UI.Header
            Write-ThinDivider

            if (-not $profiles -or $profiles.Count -eq 0) {
                Write-Host "   No profiles found." -ForegroundColor $UI.DimText
                Write-Host "   Use /profile new to create your first profile." -ForegroundColor $UI.DimText
            } else {
                $i = 1
                foreach ($pf in $profiles) {
                    $d      = Get-Content $pf.FullName -Raw | ConvertFrom-Json
                    $active = if ($State.ActiveProfile -and
                                  $State.ActiveProfile.profile_name -eq $d.profile_name) { "  < active" } else { "" }
                    Write-Host ("   [{0}] {1,-24} {2} / {3}{4}" -f $i, $d.profile_name, $d.provider, $d.model, $active) -ForegroundColor $UI.BodyText
                    $i++
                }
                Write-Host ""
                Write-Host "   /profile [name]    -> switch" -ForegroundColor $UI.DimText
                Write-Host "   /profile new       -> create"  -ForegroundColor $UI.DimText
                Write-Host "   /profile delete    -> remove"  -ForegroundColor $UI.DimText
                Write-Host "   /profile test      -> ping AI" -ForegroundColor $UI.DimText
                Write-Host "   /profile clone     -> duplicate" -ForegroundColor $UI.DimText
                Write-Host "   /profile doctor    -> diagnose" -ForegroundColor $UI.DimText
            }
            Write-ThinDivider
        }
    }
}

# ── v1.1: Profile Test ──
function Invoke-ProfileTest {
    if (-not $State.ActiveProfile) {
        Write-Msg -Role "error" -Content "No active profile to test. Use /profile new."
        return
    }

    $p = $State.ActiveProfile
    Write-Msg -Role "system" -Content "Testing profile '$($p.profile_name)'  ($($p.provider) / $($p.model))..."

    $testHistory = [System.Collections.ArrayList]@(@{ role = "user"; content = 'Say exactly: "AXON TEST OK"' })
    $sp = "You are a test responder. Reply only with the exact text requested."

    $reply = Invoke-AICall -UserMessage 'Say exactly: "AXON TEST OK"' -SystemPrompt $sp -History $testHistory

    if ($reply -and $reply -match "AXON TEST OK") {
        Write-Msg -Role "ok" -Content "Profile test PASSED — API is responding correctly."
        Write-ActionLog "PROFILE TEST PASSED: $($p.profile_name)"
    } elseif ($reply) {
        Write-Msg -Role "warn" -Content "Profile test PARTIAL — API responded but not exactly. Reply: $($reply.Substring(0,[Math]::Min(80,$reply.Length)))"
        Write-ActionLog "PROFILE TEST PARTIAL: $($p.profile_name)"
    } else {
        Write-Msg -Role "error" -Content "Profile test FAILED — no response from API. Check your API key and URL."
        Write-ActionLog "PROFILE TEST FAILED: $($p.profile_name)"
    }
}

# ── v1.1: Profile Doctor ──
function Invoke-ProfileDoctor {
    if (-not $State.ActiveProfile) {
        Write-Msg -Role "error" -Content "No active profile. Use /profile new."
        return
    }

    $p      = $State.ActiveProfile
    $issues = [System.Collections.ArrayList]@()
    $ok     = [System.Collections.ArrayList]@()

    if ([string]::IsNullOrWhiteSpace($p.profile_name)) { $issues.Add("profile_name is empty") | Out-Null }
    else { $ok.Add("profile_name: $($p.profile_name)") | Out-Null }

    if ([string]::IsNullOrWhiteSpace($p.provider))     { $issues.Add("provider is not set") | Out-Null }
    else { $ok.Add("provider: $($p.provider)") | Out-Null }

    if ([string]::IsNullOrWhiteSpace($p.model))        { $issues.Add("model is not set") | Out-Null }
    else { $ok.Add("model: $($p.model)") | Out-Null }

    if ([string]::IsNullOrWhiteSpace($p.api_url))      { $issues.Add("api_url is empty") | Out-Null }
    else { $ok.Add("api_url: $($p.api_url)") | Out-Null }

    if ($p.provider -ne "ollama" -and [string]::IsNullOrWhiteSpace($p.api_key)) {
        $issues.Add("api_key is not set (required for $($p.provider))") | Out-Null
    } elseif ($p.provider -ne "ollama") {
        $ok.Add("api_key: set ($($p.api_key.Length) chars)") | Out-Null
    }

    $maxT = $p.max_tokens
    if (-not $maxT -or $maxT -lt 100 -or $maxT -gt 200000) {
        $issues.Add("max_tokens '$maxT' looks unusual (expected 256-128000)") | Out-Null
    } else { $ok.Add("max_tokens: $maxT") | Out-Null }

    $temp = $p.temperature
    if ($temp -lt 0 -or $temp -gt 2) {
        $issues.Add("temperature '$temp' out of range (0.0 - 2.0)") | Out-Null
    } else { $ok.Add("temperature: $temp") | Out-Null }

    Write-Host ""
    Write-ThinDivider
    Write-Host "   Profile Doctor — $($p.profile_name)" -ForegroundColor $UI.Header
    Write-ThinDivider

    foreach ($line in $ok)     { Write-Host "   [OK] $line" -ForegroundColor $UI.OkText }
    foreach ($issue in $issues){ Write-Host "   [!!] $issue" -ForegroundColor $UI.ErrText }

    Write-Host ""
    if ($issues.Count -eq 0) {
        Write-Msg -Role "ok" -Content "Profile looks healthy! Use /profile test to verify API connectivity."
    } else {
        Write-Msg -Role "warn" -Content "$($issues.Count) issue(s) found. Delete and recreate with /profile delete + /profile new."
    }
    Write-ThinDivider
    Write-ActionLog "PROFILE DOCTOR: $($p.profile_name) — $($issues.Count) issue(s)"
}

# ── v1.1: Profile Clone ──
function Invoke-ProfileClone {
    param([string]$SourceName = "")

    $profilesDir = "$DataFolder\profiles"
    $profiles    = Get-ChildItem $profilesDir -Filter "*.json" -ErrorAction SilentlyContinue

    if (-not $profiles -or $profiles.Count -eq 0) {
        Write-Msg -Role "error" -Content "No profiles to clone."
        return
    }

    # Pick source
    $sourceFile = $null
    if ($SourceName) {
        $sourceFile = $profiles | Where-Object {
            ($_ | Get-Content -Raw | ConvertFrom-Json).profile_name -like "*$SourceName*"
        } | Select-Object -First 1
    } else {
        # Default: clone active profile
        if ($State.ActiveProfile) {
            $sourceFile = $profiles | Where-Object {
                ($_ | Get-Content -Raw | ConvertFrom-Json).profile_name -eq $State.ActiveProfile.profile_name
            } | Select-Object -First 1
        }
    }

    if (-not $sourceFile) {
        Write-Msg -Role "error" -Content "Source profile not found. Specify a name: /profile clone [name]"
        return
    }

    $sourceData = Get-Content $sourceFile.FullName -Raw | ConvertFrom-Json

    Write-Host ""
    Write-Host "  New profile name for the clone: " -ForegroundColor $UI.BodyText -NoNewline
    $newName = (Read-Host).Trim()
    if ([string]::IsNullOrWhiteSpace($newName)) { Write-Msg -Role "error" -Content "Name cannot be empty."; return }

    $safeName = $newName -replace '[\\/:*?"<>|]','_'
    $destPath = "$profilesDir\$safeName.json"
    if (Test-Path $destPath) { Write-Msg -Role "error" -Content "A profile with that name already exists."; return }

    $clone = [ordered]@{
        profile_name         = $newName
        provider             = $sourceData.provider
        model                = $sourceData.model
        api_key              = $sourceData.api_key
        api_url              = $sourceData.api_url
        max_tokens           = $sourceData.max_tokens
        temperature          = $sourceData.temperature
        created_at           = (Get-Date -Format "yyyy-MM-dd")
        custom_system_addons = $sourceData.custom_system_addons
    }

    $clone | ConvertTo-Json -Depth 5 | Set-Content -Path $destPath -Encoding UTF8
    Write-Msg -Role "ok" -Content "Profile '$($sourceData.profile_name)' cloned as '$newName'."
    Write-ActionLog "PROFILE CLONED: $($sourceData.profile_name) -> $newName"
}

function New-Profile {
    Write-Host ""
    Write-ThinDivider
    Write-Host "   New Profile — Setup" -ForegroundColor $UI.Header
    Write-ThinDivider
    Write-Host ""

    Write-Host "   Profile name (e.g. Claude Work): " -ForegroundColor $UI.BodyText -NoNewline
    $profileName = (Read-Host).Trim()
    if ([string]::IsNullOrWhiteSpace($profileName)) {
        Write-Msg -Role "error" -Content "Profile name cannot be empty."
        return
    }

    $safeFileName = ($profileName -replace '[\\/:*?"<>|]', '_')
    $profilePath  = "$DataFolder\profiles\$safeFileName.json"
    if (Test-Path $profilePath) {
        Write-Msg -Role "error" -Content "A profile with that name already exists."
        return
    }

    Write-Host ""
    Write-Host "   Select provider:" -ForegroundColor $UI.BodyText
    Write-Host "   [1] Anthropic (Claude)" -ForegroundColor $UI.DimText
    Write-Host "   [2] OpenAI (GPT)"       -ForegroundColor $UI.DimText
    Write-Host "   [3] Groq"               -ForegroundColor $UI.DimText
    Write-Host "   [4] Ollama (local)"     -ForegroundColor $UI.DimText
    Write-Host "   [5] Custom endpoint"    -ForegroundColor $UI.DimText
    Write-Host ""
    Write-Host "   Choice (1-5): " -ForegroundColor $UI.BodyText -NoNewline
    $provChoice = (Read-Host).Trim()

    $providerMap = @{
        "1" = @{ name="anthropic"; url="https://api.anthropic.com/v1/messages";         defaultModel="claude-sonnet-4-20250514" }
        "2" = @{ name="openai";    url="https://api.openai.com/v1/chat/completions";     defaultModel="gpt-4o" }
        "3" = @{ name="groq";      url="https://api.groq.com/openai/v1/chat/completions"; defaultModel="llama-3.3-70b-versatile" }
        "4" = @{ name="ollama";    url="http://localhost:11434/api/chat";                defaultModel="llama3" }
        "5" = @{ name="custom";    url="";                                               defaultModel="" }
    }

    if (-not $providerMap.ContainsKey($provChoice)) {
        Write-Msg -Role "error" -Content "Invalid choice."
        return
    }

    $provInfo = $providerMap[$provChoice]

    Write-Host ""
    Write-Host "   Model [$($provInfo.defaultModel)]: " -ForegroundColor $UI.BodyText -NoNewline
    $modelInput = (Read-Host).Trim()
    $model = if ($modelInput -eq "") { $provInfo.defaultModel } else { $modelInput }

    $apiUrl = $provInfo.url
    if ($provChoice -eq "5") {
        Write-Host "   API endpoint URL: " -ForegroundColor $UI.BodyText -NoNewline
        $apiUrl = (Read-Host).Trim()
    }

    $apiKey = ""
    if ($provInfo.name -ne "ollama") {
        Write-Host "   API key: " -ForegroundColor $UI.BodyText -NoNewline
        $secureKey = Read-Host -AsSecureString
        $apiKey    = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                         [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey))
    }

    Write-Host "   Max tokens [4096]: " -ForegroundColor $UI.BodyText -NoNewline
    $tokInput  = (Read-Host).Trim()
    $maxTokens = if ($tokInput -match '^\d+$') { [int]$tokInput } else { 4096 }

    Write-Host "   Temperature [0.7]: " -ForegroundColor $UI.BodyText -NoNewline
    $tempInput = (Read-Host).Trim()
    $temp      = if ($tempInput -match '^\d*\.?\d+$') { [double]$tempInput } else { 0.7 }

    $profile = [ordered]@{
        profile_name         = $profileName
        provider             = $provInfo.name
        model                = $model
        api_key              = $apiKey
        api_url              = $apiUrl
        max_tokens           = $maxTokens
        temperature          = $temp
        created_at           = (Get-Date -Format "yyyy-MM-dd")
        custom_system_addons = ""
    }

    $profile | ConvertTo-Json -Depth 5 | Set-Content -Path $profilePath -Encoding UTF8

    Write-Host ""
    Write-Msg -Role "ok" -Content "Profile '$profileName' created."
    Write-ActionLog "Profile created: $profileName ($($provInfo.name) / $model)"

    Write-Host ""
    Write-Host "   Activate this profile now? (y/n): " -ForegroundColor $UI.BodyText -NoNewline
    $activate = (Read-Host).Trim().ToLower()
    if ($activate -eq "y") {
        Switch-Profile -Name $profileName
    }
}

function Switch-Profile {
    param([string]$Name)

    $profilesDir = "$DataFolder\profiles"
    $profiles    = Get-ChildItem $profilesDir -Filter "*.json" -ErrorAction SilentlyContinue

    if (-not $profiles) {
        Write-Msg -Role "error" -Content "No profiles found. Use /profile new."
        return
    }

    $match = $profiles | Where-Object {
        ($_ | Get-Content -Raw | ConvertFrom-Json).profile_name -eq $Name
    } | Select-Object -First 1

    if (-not $match) {
        $match = $profiles | Where-Object {
            ($_ | Get-Content -Raw | ConvertFrom-Json).profile_name -like "*$Name*"
        } | Select-Object -First 1
    }

    if (-not $match) {
        Write-Msg -Role "error" -Content "No profile found matching '$Name'."
        return
    }

    $profileData = Get-Content $match.FullName -Raw | ConvertFrom-Json
    $State.ActiveProfile = $profileData

    $s = Get-Settings
    $s.active_profile = $profileData.profile_name
    Write-SettingsAtomic -Settings $s

    [Console]::Clear()
    Write-Header
    Write-Msg -Role "ok" -Content "Switched to profile: $($profileData.profile_name)  ($($profileData.provider) / $($profileData.model))"
    Write-ActionLog "Switched to profile: $($profileData.profile_name)"
}

function Remove-Profile {
    $profilesDir = "$DataFolder\profiles"
    $profiles    = Get-ChildItem $profilesDir -Filter "*.json" -ErrorAction SilentlyContinue

    if (-not $profiles -or $profiles.Count -eq 0) {
        Write-Msg -Role "error" -Content "No profiles to delete."
        return
    }

    Write-Host ""
    Write-ThinDivider
    Write-Host "   Delete Profile" -ForegroundColor $UI.Header
    Write-ThinDivider
    $i = 1
    foreach ($pf in $profiles) {
        $d = Get-Content $pf.FullName -Raw | ConvertFrom-Json
        Write-Host ("   [{0}] {1}" -f $i, $d.profile_name) -ForegroundColor $UI.BodyText
        $i++
    }
    Write-Host ""
    Write-Host "   Profile name to delete (or blank to cancel): " -ForegroundColor $UI.WarnText -NoNewline
    $target = (Read-Host).Trim()
    if ([string]::IsNullOrWhiteSpace($target)) { Write-Msg -Role "system" -Content "Cancelled."; return }

    $match = $profiles | Where-Object {
        ($_ | Get-Content -Raw | ConvertFrom-Json).profile_name -eq $target
    } | Select-Object -First 1

    if (-not $match) { Write-Msg -Role "error" -Content "Profile not found."; return }

    Write-Host "   Confirm delete '$target'? (yes/no): " -ForegroundColor $UI.WarnText -NoNewline
    $confirm = (Read-Host).Trim().ToLower()
    if ($confirm -ne "yes") { Write-Msg -Role "system" -Content "Cancelled."; return }

    Remove-Item $match.FullName -Force
    if ($State.ActiveProfile -and $State.ActiveProfile.profile_name -eq $target) {
        $State.ActiveProfile = $null
    }
    Write-Msg -Role "ok" -Content "Profile '$target' deleted."
    Write-ActionLog "Profile deleted: $target"
}


# ================================================================
#  PROFILE — AUTO LOAD ON STARTUP
# ================================================================

function Load-ActiveProfile {
    $s = Get-Settings
    if (-not $s -or -not $s.active_profile) { return }

    $profilesDir = "$DataFolder\profiles"
    $profiles    = Get-ChildItem $profilesDir -Filter "*.json" -ErrorAction SilentlyContinue
    if (-not $profiles) { return }

    $match = $profiles | Where-Object {
        ($_ | Get-Content -Raw | ConvertFrom-Json).profile_name -eq $s.active_profile
    } | Select-Object -First 1

    if ($match) {
        $State.ActiveProfile = Get-Content $match.FullName -Raw | ConvertFrom-Json
    }
}


# ================================================================
#  v1.0 — CONTEXT MANAGER
# ================================================================

function Get-TokenEstimate {
    param([string]$Text)
    return [Math]::Ceiling($Text.Length / 4)
}

function Trim-ChatHistory {
    $totalChars = ($State.ChatHistory | ForEach-Object { $_.content } | Measure-Object -Character).Characters
    $estimated  = [Math]::Ceiling($totalChars / 4)
    $State.TokenEstimate = $estimated

    $softLimit = $State.MaxContextTokens
    while ($estimated -gt $softLimit -and $State.ChatHistory.Count -gt 4) {
        $idx = 0
        while ($idx -lt $State.ChatHistory.Count -and
               ($State.ChatHistory[$idx].content -like "[AXON*" -or
                $State.ChatHistory[$idx].content -like "[CONTEXT*")) {
            $idx++
        }
        if ($idx -lt $State.ChatHistory.Count) {
            $State.ChatHistory.RemoveAt($idx)
        } else { break }
        $totalChars = ($State.ChatHistory | ForEach-Object { $_.content } | Measure-Object -Character).Characters
        $estimated  = [Math]::Ceiling($totalChars / 4)
        $State.TokenEstimate = $estimated
    }
}


# ================================================================
#  v1.0 — SMART BRAIN (STRUCTURED MEMORY)
# ================================================================

function Load-SmartMemory {
    $memPath = "$DataFolder\smart_memory.json"
    if (Test-Path $memPath) {
        try {
            $raw = Get-Content $memPath -Raw | ConvertFrom-Json
            $ht  = @{}
            $raw.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
            $State.SmartMemory = $ht
        } catch { $State.SmartMemory = @{} }
    }
}

function Save-SmartMemory {
    $memPath = "$DataFolder\smart_memory.json"
    $tmp     = "$memPath.tmp"
    try {
        $State.SmartMemory | ConvertTo-Json -Depth 5 | Set-Content $tmp -Encoding UTF8
        Move-Item -Path $tmp -Destination $memPath -Force
    } catch {
        $State.SmartMemory | ConvertTo-Json -Depth 5 | Set-Content $memPath -Encoding UTF8
    }
}

function Update-SmartMemory {
    param([string]$Key, $Value)
    $State.SmartMemory[$Key] = $Value
    Save-SmartMemory
    Write-ActionLog "SMART MEMORY updated: $Key"
}

function Get-SmartMemoryBlock {
    if ($State.SmartMemory.Count -eq 0) { return "No structured memory yet." }
    $lines = [System.Collections.ArrayList]@()
    foreach ($k in $State.SmartMemory.Keys) {
        $v = $State.SmartMemory[$k]
        $lines.Add("  $k : $v") | Out-Null
    }
    return $lines -join "`n"
}


# ================================================================
#  v1.0 — FUNCTION REGISTRY
# ================================================================

function Register-AXONFunction {
    param(
        [string]$Name,
        [string]$Description,
        [hashtable]$Parameters = @{},
        [scriptblock]$Handler
    )
    $State.FunctionRegistry[$Name] = @{
        name        = $Name
        description = $Description
        parameters  = $Parameters
        handler     = $Handler
    }
}

function Get-FunctionRegistryBlock {
    if ($State.FunctionRegistry.Count -eq 0) { return "No functions registered." }
    $lines = [System.Collections.ArrayList]@()
    foreach ($fn in $State.FunctionRegistry.Values) {
        $lines.Add("  $($fn.name) — $($fn.description)") | Out-Null
        foreach ($p in $fn.parameters.Keys) {
            $lines.Add("      param: $p — $($fn.parameters[$p])") | Out-Null
        }
    }
    return $lines -join "`n"
}

function Invoke-FunctionCall {
    param([string]$Name, [hashtable]$Args = @{})
    if (-not $State.FunctionRegistry.ContainsKey($Name)) {
        return "[ERROR] Unknown function: $Name"
    }
    $fn = $State.FunctionRegistry[$Name]
    try {
        $result = & $fn.handler @Args
        Write-ActionLog "FUNCTION CALL: $Name — success"
        return $result
    } catch {
        Write-ActionLog "FUNCTION CALL ERROR: $Name — $($_.Exception.Message)"
        return "[ERROR] $($_.Exception.Message)"
    }
}

function Register-CoreFunctions {
    # $SEARCH$ — web search via DuckDuckGo instant API
    Register-AXONFunction -Name "search" -Description "Search the web and return top results" `
        -Parameters @{ query = "The search query string" } `
        -Handler {
            param([string]$query)
            try {
                $enc  = [Uri]::EscapeDataString($query)
                $resp = Invoke-RestMethod "https://api.duckduckgo.com/?q=$enc&format=json&no_html=1&skip_disambig=1" -ErrorAction Stop
                $lines = [System.Collections.ArrayList]@()
                if ($resp.AbstractText) { $lines.Add("Summary: $($resp.AbstractText)") | Out-Null }
                if ($resp.RelatedTopics) {
                    $top = $resp.RelatedTopics | Where-Object { $_.Text } | Select-Object -First 5
                    foreach ($t in $top) { $lines.Add("- $($t.Text)") | Out-Null }
                }
                if ($lines.Count -eq 0) { return "No results found for: $query" }
                return $lines -join "`n"
            } catch { return "[SEARCH ERROR] $($_.Exception.Message)" }
        }

    # $OPEN$ — open a file, URL, or application
    Register-AXONFunction -Name "open" -Description "Open a file, URL, or application" `
        -Parameters @{ target = "File path, URL, or app name to open" } `
        -Handler {
            param([string]$target)
            if (-not (Test-PathSafe -TargetPath $target) -and $target -notmatch '^https?://') {
                return "[BLOCKED] Path is protected: $target"
            }
            try {
                Start-Process $target
                return "[OK] Opened: $target"
            } catch { return "[ERROR] $($_.Exception.Message)" }
        }

    # $NOTIFY$ — Windows toast notification
    Register-AXONFunction -Name "notify" -Description "Show a Windows toast notification" `
        -Parameters @{ title = "Notification title"; message = "Notification body text" } `
        -Handler {
            param([string]$title, [string]$message)
            try {
                $xml = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
                $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(
                    [Windows.UI.Notifications.ToastTemplateType]::ToastText02)
                $template.GetElementsByTagName("text")[0].AppendChild($template.CreateTextNode($title))  | Out-Null
                $template.GetElementsByTagName("text")[1].AppendChild($template.CreateTextNode($message)) | Out-Null
                $toast = [Windows.UI.Notifications.ToastNotification]::new($template)
                [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("AXON").Show($toast)
                return "[OK] Notification sent: $title"
            } catch {
                try { msg * "$title`n$message" 2>$null } catch {}
                return "[OK] Notification dispatched (fallback)."
            }
        }

    # $CLIP$ — read or write clipboard
    Register-AXONFunction -Name "clip" -Description "Read from or write text to the clipboard" `
        -Parameters @{ action = "'read' or 'write'"; text = "Text to write (only for write action)" } `
        -Handler {
            param([string]$action, [string]$text = "")
            if ($action -eq "read") {
                $content = Get-Clipboard
                return if ($content) { $content } else { "(clipboard is empty)" }
            } elseif ($action -eq "write") {
                Set-Clipboard -Value $text
                return "[OK] Clipboard set ($($text.Length) chars)"
            } else { return "[ERROR] action must be 'read' or 'write'" }
        }

    # $STATUS$ — update the AXON header status bar
    Register-AXONFunction -Name "status" -Description "Update the AXON status bar message" `
        -Parameters @{ message = "Short status message to display in the header" } `
        -Handler {
            param([string]$message)
            $State.StatusBarMsg = $message
            return "[OK] Status updated: $message"
        }

    # $MACRO$ — save or run a macro
    Register-AXONFunction -Name "macro" -Description "Save or run a named AXON macro" `
        -Parameters @{ action = "'save' or 'run'"; name = "Macro name"; steps = "Steps to save (for save action)" } `
        -Handler {
            param([string]$action, [string]$name, [string]$steps = "")
            $macroPath = "$DataFolder\macros\$($name -replace '[\\/:*?<>|]','_').json"
            if ($action -eq "save") {
                @{ name = $name; steps = $steps; created = (Get-Date -Format "yyyy-MM-dd HH:mm") } |
                    ConvertTo-Json | Set-Content $macroPath -Encoding UTF8
                $State.Macros[$name] = $steps
                return "[OK] Macro '$name' saved."
            } elseif ($action -eq "run") {
                if (Test-Path $macroPath) {
                    $m = Get-Content $macroPath -Raw | ConvertFrom-Json
                    return "[MACRO:$name] $($m.steps)"
                }
                return "[ERROR] Macro '$name' not found. Use /macro list to see saved macros."
            }
            return "[ERROR] action must be 'save' or 'run'"
        }

    # $MEMORY_SET$ — write a specific key to smart memory
    Register-AXONFunction -Name "memory_set" -Description "Store a key-value pair in smart memory" `
        -Parameters @{ key = "Memory key (topic/category)"; value = "Value to store" } `
        -Handler {
            param([string]$key, [string]$value)
            Update-SmartMemory -Key $key -Value $value
            return "[OK] Memory stored: $key = $value"
        }

    # v1.1: $TASK$ — add a task to the tracker
    Register-AXONFunction -Name "task_add" -Description "Add a step to the multi-step task tracker" `
        -Parameters @{ title = "Task title"; note = "Optional note or context"; status = "waiting, active, or done" } `
        -Handler {
            param([string]$title, [string]$note = "", [string]$status = "waiting")
            Add-Task -Title $title -Note $note -Status $status
            return "[OK] Task added: $title [$status]"
        }

    # v1.1: $TASK_UPDATE$ — update task status
    Register-AXONFunction -Name "task_update" -Description "Update a task's status in the tracker" `
        -Parameters @{ title = "Task title or partial title"; status = "waiting, active, or done" } `
        -Handler {
            param([string]$title, [string]$status)
            $r = Set-TaskStatus -TitleOrId $title -Status $status
            return if ($r) { "[OK] Task updated: $title -> $status" } else { "[WARN] Task not found: $title" }
        }
}


# ================================================================
#  v1.0 — PLUGIN LOADER
# ================================================================

function Load-Plugins {
    $pluginDir = "$DataFolder\plugins"
    $plugins   = Get-ChildItem $pluginDir -Filter "*.ps1" -ErrorAction SilentlyContinue
    if (-not $plugins) { return }

    foreach ($plugin in $plugins) {
        try {
            $content    = Get-Content $plugin.FullName -Raw
            $nameMatch  = [regex]::Match($content, '#\s*PLUGIN_NAME\s*:\s*(.+)')
            $descMatch  = [regex]::Match($content, '#\s*PLUGIN_DESC\s*:\s*(.+)')
            $pName      = if ($nameMatch.Success) { $nameMatch.Groups[1].Value.Trim() } else { $plugin.BaseName }
            $pDesc      = if ($descMatch.Success) { $descMatch.Groups[1].Value.Trim() } else { "Plugin: $($plugin.BaseName)" }

            . $plugin.FullName

            $State.LoadedPlugins.Add(@{ name = $pName; desc = $pDesc; file = $plugin.Name }) | Out-Null

            $pNameLocal = $pName
            Register-AXONFunction -Name "plugin_$pNameLocal" -Description $pDesc `
                -Parameters @{ input = "Input to pass to the plugin" } `
                -Handler ([scriptblock]::Create("param([string]`$input) Invoke-Plugin_$pNameLocal -Input `$input"))

            Write-ActionLog "Plugin loaded: $pName ($($plugin.Name))"
        } catch {
            Write-ActionLog "Plugin load FAILED: $($plugin.Name) — $($_.Exception.Message)"
        }
    }

    if ($State.LoadedPlugins.Count -gt 0) {
        Write-Msg -Role "ok" -Content "$($State.LoadedPlugins.Count) plugin(s) loaded."
    }
}


# ================================================================
#  v1.0 — STREAMING API CALLER
# ================================================================

function Invoke-AICall {
    param(
        [string]$UserMessage,
        [string]$SystemPrompt,
        [System.Collections.ArrayList]$History
    )

    if (-not $State.ActiveProfile) {
        Write-Msg -Role "error" -Content "No active profile. Use /profile new to create one."
        return $null
    }

    $profile  = $State.ActiveProfile
    $provider = $profile.provider

    Trim-ChatHistory

    $bodyObj = Build-ApiBody -Profile $profile -Messages $History.ToArray() -SystemPrompt $SystemPrompt -Stream $true
    if (-not $bodyObj) {
        Write-Msg -Role "error" -Content "Unknown provider: $provider"
        return $null
    }

    $bodyJson  = $bodyObj | ConvertTo-Json -Depth 10
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)

    $headerScript = $PROVIDER_HEADERS[$provider]
    $headers      = & $headerScript $profile

    Write-Host ""
    Write-Host "  AI  : " -ForegroundColor $UI.AILabel -NoNewline

    $fullText = [System.Text.StringBuilder]::new()

    try {
        $req = [System.Net.HttpWebRequest]::Create($profile.api_url)
        $req.Method      = "POST"
        $req.ContentType = "application/json"
        $req.Timeout     = 120000
        foreach ($h in $headers.Keys) { $req.Headers[$h] = $headers[$h] }

        $reqStream = $req.GetRequestStream()
        $reqStream.Write($bodyBytes, 0, $bodyBytes.Length)
        $reqStream.Close()

        $resp   = $req.GetResponse()
        $reader = [System.IO.StreamReader]::new($resp.GetResponseStream())

        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if ([string]::IsNullOrEmpty($line)) { continue }

            if ($line.StartsWith("data: ")) {
                $jsonStr = $line.Substring(6).Trim()
                if ($jsonStr -eq "[DONE]") { break }
                try {
                    $chunk = $jsonStr | ConvertFrom-Json
                    $delta = ""
                    switch ($provider) {
                        "anthropic" {
                            if ($chunk.type -eq "content_block_delta" -and $chunk.delta.type -eq "text_delta") {
                                $delta = $chunk.delta.text
                            }
                        }
                        { $_ -in @("openai","groq","custom") } {
                            $delta = $chunk.choices[0].delta.content
                        }
                        "ollama" {
                            $delta = $chunk.message.content
                        }
                    }
                    if ($delta) {
                        $fullText.Append($delta) | Out-Null
                        Write-Host $delta -NoNewline -ForegroundColor $UI.BodyText
                    }
                } catch { continue }
            } elseif ($provider -eq "ollama") {
                try {
                    $chunk = $line | ConvertFrom-Json
                    $delta = $chunk.message.content
                    if ($delta) {
                        $fullText.Append($delta) | Out-Null
                        Write-Host $delta -NoNewline -ForegroundColor $UI.BodyText
                    }
                    if ($chunk.done) { break }
                } catch { continue }
            }
        }

        $reader.Close()
        $resp.Close()
        Write-Host ""

        $text = $fullText.ToString()
        if ([string]::IsNullOrWhiteSpace($text)) {
            Write-Msg -Role "error" -Content "Empty response from $provider."
            $History.RemoveAt($History.Count - 1)
            return $null
        }

        $History.Add(@{ role = "assistant"; content = $text }) | Out-Null
        $State.TokenEstimate = Get-TokenEstimate -Text ($History | ForEach-Object { $_.content } | Out-String)
        $State.LastAIReply   = $text
        $State.LastAPIError  = ""

        Write-ActionLog "AI call (stream) — provider: $provider  model: $($profile.model)  chars: $($text.Length)"
        $State.AICallCount++
        return $text

    } catch {
        Write-Host ""
        $errMsg = $_.Exception.Message
        try {
            if ($_.Exception.Response) {
                $errStream = $_.Exception.Response.GetResponseStream()
                $errReader = [System.IO.StreamReader]::new($errStream)
                $errBody   = $errReader.ReadToEnd() | ConvertFrom-Json
                if ($errBody.error.message) { $errMsg = $errBody.error.message }
            }
        } catch {}
        Write-Msg -Role "error" -Content "API call failed: $errMsg"
        Write-ActionLog "API call FAILED: $errMsg"
        $State.LastAPIError = $errMsg
        if ($History.Count -gt 0 -and $History[$History.Count-1].role -eq "user") {
            $History.RemoveAt($History.Count - 1)
        }
        return $null
    }
}


# ================================================================
#  v1.0 — API BODY BUILDER
# ================================================================

$PROVIDER_HEADERS = @{
    "anthropic" = {
        param($profile)
        return @{
            "x-api-key"         = $profile.api_key
            "anthropic-version" = "2023-06-01"
            "content-type"      = "application/json"
        }
    }
    "openai" = {
        param($profile)
        return @{
            "Authorization" = "Bearer $($profile.api_key)"
            "content-type"  = "application/json"
        }
    }
    "groq" = {
        param($profile)
        return @{
            "Authorization" = "Bearer $($profile.api_key)"
            "content-type"  = "application/json"
        }
    }
    "ollama" = {
        param($profile)
        return @{ "content-type" = "application/json" }
    }
    "custom" = {
        param($profile)
        return @{
            "Authorization" = "Bearer $($profile.api_key)"
            "content-type"  = "application/json"
        }
    }
}

function Build-ApiBody {
    param($Profile, $Messages, $SystemPrompt, [bool]$Stream = $true)

    $provider = $Profile.provider

    if ($provider -eq "anthropic") {
        $body = @{
            model      = $Profile.model
            max_tokens = $Profile.max_tokens
            system     = $SystemPrompt
            messages   = $Messages
            stream     = $Stream
        }
        if ($Profile.temperature) { $body.temperature = $Profile.temperature }
        return $body
    }

    if ($provider -in @("openai","groq","custom")) {
        $msgs = [System.Collections.ArrayList]@()
        if ($SystemPrompt) { $msgs.Add(@{ role = "system"; content = $SystemPrompt }) | Out-Null }
        foreach ($m in $Messages) { $msgs.Add($m) | Out-Null }
        $body = @{
            model      = $Profile.model
            max_tokens = $Profile.max_tokens
            messages   = $msgs.ToArray()
            stream     = $Stream
        }
        if ($Profile.temperature) { $body.temperature = $Profile.temperature }
        return $body
    }

    if ($provider -eq "ollama") {
        return @{
            model    = $Profile.model
            messages = $Messages
            stream   = $Stream
        }
    }

    return $null
}


# ================================================================
#  SIMPLE COMMAND HANDLERS
# ================================================================

function Invoke-MemoryCommand {
    $memPath = "$DataFolder\memory.txt"
    Write-Host ""
    Write-ThinDivider
    Write-Host "   AI Memory — Last Session" -ForegroundColor $UI.Header
    Write-ThinDivider
    if (Test-Path $memPath) {
        Get-Content $memPath | ForEach-Object { Write-Host "   $_" -ForegroundColor $UI.BodyText }
    } else {
        Write-Host "   No memory file found." -ForegroundColor $UI.DimText
    }
    Write-ThinDivider
}

function Invoke-FilesCommand {
    Write-Host ""
    Write-ThinDivider
    Write-Host "   AXON Data Folder  —  $DataFolder" -ForegroundColor $UI.Header
    Write-ThinDivider

    $subFolders = @("profiles","sessions","temp","workspace","logs","plugins","macros")
    foreach ($sub in $subFolders) {
        $path  = "$DataFolder\$sub"
        $items = Get-ChildItem $path -ErrorAction SilentlyContinue
        $count = if ($items) { $items.Count } else { 0 }
        Write-Host ("   [F] {0,-16} ({1} items)" -f "$sub/", $count) -ForegroundColor $UI.BodyText

        if ($count -gt 0 -and $count -le 6) {
            foreach ($item in $items) {
                Write-Host "      -> $($item.Name)" -ForegroundColor $UI.DimText
            }
        } elseif ($count -gt 6) {
            Write-Host "      -> ... and $count items" -ForegroundColor $UI.DimText
        }
    }

    $rootFiles = Get-ChildItem $DataFolder -File -ErrorAction SilentlyContinue
    if ($rootFiles) {
        Write-Host ""
        foreach ($f in $rootFiles) {
            $sz = [Math]::Round($f.Length/1KB, 1)
            Write-Host ("   [f] {0,-30} {1} KB" -f $f.Name, $sz) -ForegroundColor $UI.DimText
        }
    }
    Write-ThinDivider
}

# ── v1.1: /temp  — show or clean temp folder ──
function Invoke-TempCommand {
    param([string]$Sub = "")

    $tempPath = "$DataFolder\temp"

    if ($Sub -eq "clean") {
        $items = Get-ChildItem $tempPath -File -ErrorAction SilentlyContinue
        if (-not $items -or $items.Count -eq 0) {
            Write-Msg -Role "system" -Content "Temp folder is already empty."
            return
        }
        Write-Host ""
        Write-Host "  Delete $($items.Count) file(s) from temp/? (y/n): " -ForegroundColor $UI.WarnText -NoNewline
        if ((Read-Host).Trim().ToLower() -notin @("y","yes")) {
            Write-Msg -Role "system" -Content "Cancelled."
            return
        }
        $removed = 0
        foreach ($f in $items) {
            try { Remove-Item $f.FullName -Force; $removed++ } catch {}
        }
        Write-Msg -Role "ok" -Content "Removed $removed file(s) from temp/."
        Write-ActionLog "TEMP CLEAN: $removed files removed by user"
        return
    }

    $items = Get-ChildItem $tempPath -ErrorAction SilentlyContinue
    Write-Host ""
    Write-ThinDivider
    Write-Host "   Temp — Files Awaiting Approval" -ForegroundColor $UI.Header
    Write-ThinDivider
    if (-not $items -or $items.Count -eq 0) {
        Write-Host "   No files waiting." -ForegroundColor $UI.DimText
    } else {
        foreach ($item in $items) {
            $size = [Math]::Round($item.Length / 1KB, 1)
            $age  = [Math]::Round(((Get-Date) - $item.LastWriteTime).TotalHours, 1)
            Write-Host ("   {0,-32} {1,6} KB  {2}h ago" -f $item.Name, $size, $age) -ForegroundColor $UI.BodyText
        }
    }
    Write-ThinDivider
    Write-Host "   /temp clean  -> delete all temp files now" -ForegroundColor $UI.DimText
    Write-ThinDivider
}

function Invoke-LogCommand {
    $logPath = "$DataFolder\logs\actions.log"
    Write-Host ""
    Write-ThinDivider
    Write-Host "   Action Log  (last 20 entries)" -ForegroundColor $UI.Header
    Write-ThinDivider
    if (Test-Path $logPath) {
        $lines = Get-Content $logPath -Tail 20
        if ($lines) {
            foreach ($line in $lines) { Write-Host "   $line" -ForegroundColor $UI.DimText }
        } else {
            Write-Host "   Log is empty." -ForegroundColor $UI.DimText
        }
    } else {
        Write-Host "   No log file yet." -ForegroundColor $UI.DimText
    }
    Write-ThinDivider
}

# ── v1.1: /logs clean — archive and rotate ──
function Invoke-LogsCleanCommand {
    $logPath = "$DataFolder\logs\actions.log"
    if (-not (Test-Path $logPath)) {
        Write-Msg -Role "system" -Content "No action log file exists yet."
        return
    }
    $size = [Math]::Round((Get-Item $logPath).Length / 1KB, 1)
    Write-Host ""
    Write-Host "  Archive and clear actions.log ($size KB)? (y/n): " -ForegroundColor $UI.WarnText -NoNewline
    if ((Read-Host).Trim().ToLower() -notin @("y","yes")) {
        Write-Msg -Role "system" -Content "Cancelled."
        return
    }
    $archive = "$DataFolder\logs\actions_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
    try {
        Move-Item -Path $logPath -Destination $archive -Force
        New-Item -ItemType File -Path $logPath -Force | Out-Null
        Write-Msg -Role "ok" -Content "Archived to: $([System.IO.Path]::GetFileName($archive))  ($size KB)"
        Write-ActionLog "LOG ROTATED — archived $([System.IO.Path]::GetFileName($archive))"
    } catch {
        Write-Msg -Role "error" -Content "Log rotation failed: $($_.Exception.Message)"
    }
}

function Invoke-SettingsCommand {
    Write-Host ""
    Write-ThinDivider
    Write-Host "   Settings" -ForegroundColor $UI.Header
    Write-ThinDivider
    $s = Get-Settings
    if ($s) {
        Write-Host ("   {0,-34} {1}" -f "Active profile:",       ($s.active_profile ?? "none"))         -ForegroundColor $UI.BodyText
        Write-Host ("   {0,-34} {1}" -f "Dry run before execute:", $s.dry_run_before_execute)            -ForegroundColor $UI.BodyText
        Write-Host ("   {0,-34} {1}" -f "Max executions/min:",    $s.max_executions_per_minute)         -ForegroundColor $UI.BodyText
        Write-Host ("   {0,-34} {1}" -f "Auto memory:",           $s.auto_memory)                       -ForegroundColor $UI.BodyText
        Write-Host ("   {0,-34} {1}" -f "Approval timeout (sec):", $s.approval_timeout_seconds)         -ForegroundColor $UI.BodyText
        Write-Host ""
        Write-Host "   Blocked paths (hardcoded):" -ForegroundColor $UI.DimText
        foreach ($bp in $s.blocked_paths) {
            Write-Host "     [X] $bp" -ForegroundColor $UI.DimText
        }
        if ($s.user_blocked_paths -and $s.user_blocked_paths.Count -gt 0) {
            Write-Host ""
            Write-Host "   Blocked paths (user-defined):" -ForegroundColor $UI.DimText
            foreach ($up in $s.user_blocked_paths) {
                Write-Host "     [X] $up" -ForegroundColor $UI.DimText
            }
        }
        Write-Host ""
        Write-Host "   Use /profile new to add a profile." -ForegroundColor $UI.DimText
        Write-Host "   Use /lock [path] to add blocked paths." -ForegroundColor $UI.DimText
    }
    Write-ThinDivider
}

function Invoke-LockCommand {
    param([string]$Path)
    if (-not $Path) { Write-Msg -Role "error" -Content "Usage: /lock [path]"; return }

    $s    = Get-Settings
    $list = [System.Collections.ArrayList]@($s.user_blocked_paths)

    if ($list -contains $Path) {
        Write-Msg -Role "warn" -Content "Already in your blocklist: $Path"
    } else {
        $list.Add($Path) | Out-Null
        $s.user_blocked_paths = $list.ToArray()
        Write-SettingsAtomic -Settings $s
        Write-Msg -Role "ok"  -Content "Locked: $Path"
        Write-ActionLog "User locked path: $Path"
    }
}

function Invoke-UnlockCommand {
    param([string]$Path)
    if (-not $Path) { Write-Msg -Role "error" -Content "Usage: /unlock [path]"; return }

    $s    = Get-Settings
    $list = [System.Collections.ArrayList]@($s.user_blocked_paths)

    if ($list -contains $Path) {
        $list.Remove($Path)
        $s.user_blocked_paths = $list.ToArray()
        Write-SettingsAtomic -Settings $s
        Write-Msg -Role "ok"  -Content "Unlocked: $Path"
        Write-ActionLog "User unlocked path: $Path"
    } else {
        Write-Msg -Role "warn" -Content "Path not found in your blocklist."
    }
}

# ── v1.1: Enhanced /peek with line count, modified date, encoding hint ──
function Invoke-PeekCommand {
    param([string]$Path)
    if (-not $Path) { Write-Msg -Role "error" -Content "Usage: /peek [filepath]"; return }
    if (-not (Test-Path $Path)) { Write-Msg -Role "error" -Content "File not found: $Path"; return }

    $item       = Get-Item $Path
    $modifiedAt = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    $sizeKB     = [Math]::Round($item.Length / 1KB, 1)
    $totalLines = 0

    Write-Host ""
    Write-ThinDivider
    Write-Host "   Peek: $($item.Name)" -ForegroundColor $UI.Header
    Write-Host ("   {0,-16} {1}" -f "Size:", "$sizeKB KB") -ForegroundColor $UI.DimText
    Write-Host ("   {0,-16} {1}" -f "Modified:", $modifiedAt)   -ForegroundColor $UI.DimText
    Write-Host ("   {0,-16} {1}" -f "Full path:", $item.FullName) -ForegroundColor $UI.DimText
    Write-ThinDivider

    try {
        $allLines   = Get-Content $Path -ErrorAction Stop
        $totalLines = $allLines.Count
        $showLines  = $allLines | Select-Object -First 50
        $lineNum    = 1
        foreach ($line in $showLines) {
            Write-Host ("   {0,4}  {1}" -f $lineNum, $line) -ForegroundColor $UI.BodyText
            $lineNum++
        }
        if ($totalLines -gt 50) {
            Write-Host ""
            Write-Host ("   ... {0} more line(s) not shown" -f ($totalLines - 50)) -ForegroundColor $UI.DimText
        }
        Write-ThinDivider
        Write-Host ("   Total lines: $totalLines") -ForegroundColor $UI.DimText
    } catch {
        Write-Host "   Cannot preview this file type." -ForegroundColor $UI.DimText
    }
    Write-ThinDivider
}

# ── v1.1: /open — open a file or URL directly from the command line ──
function Invoke-OpenCommand {
    param([string]$Target)
    if (-not $Target) { Write-Msg -Role "error" -Content "Usage: /open [path or URL]"; return }

    if ($Target -notmatch '^https?://' -and -not (Test-PathSafe -TargetPath $Target)) {
        Write-Msg -Role "error" -Content "Blocked path: $Target"
        return
    }

    try {
        Start-Process $Target
        Write-Msg -Role "ok" -Content "Opened: $Target"
        Write-ActionLog "USER OPEN: $Target"
    } catch {
        Write-Msg -Role "error" -Content "Failed to open: $($_.Exception.Message)"
    }
}


# ================================================================
#  PHASE 3 — SCRIPT SNAPSHOT GENERATOR
# ================================================================

function Build-ScriptSnapshot {
    $snapshotPath = "$DataFolder\script_snapshot.ps1"

    try {
        $selfPath = $PSCommandPath
        if (-not $selfPath -or -not (Test-Path $selfPath)) {
            $selfPath = $MyInvocation.ScriptName
        }

        if (-not $selfPath -or -not (Test-Path $selfPath)) {
            $notice = "# [AXON] Script snapshot unavailable — could not locate source file."
            Set-Content -Path $snapshotPath -Value $notice -Encoding UTF8
            return $notice
        }

        $lines     = Get-Content $selfPath
        $sanitized = [System.Collections.ArrayList]@()
        $inSafety  = $false

        foreach ($line in $lines) {
            if ($line.Trim() -eq "#SAFETY_START") {
                $inSafety = $true
                $sanitized.Add("# [SAFETY BLOCK REDACTED]") | Out-Null
                continue
            }
            if ($line.Trim() -eq "#SAFETY_END") {
                $inSafety = $false
                continue
            }
            if (-not $inSafety) {
                $sanitized.Add($line) | Out-Null
            }
        }

        $content = $sanitized -join "`n"
        # Atomic write for snapshot too
        $tmpSnap = "$snapshotPath.tmp"
        Set-Content -Path $tmpSnap -Value $content -Encoding UTF8
        Move-Item -Path $tmpSnap -Destination $snapshotPath -Force

        Write-ActionLog "Script snapshot generated — $($sanitized.Count) lines (safety block redacted)"
        return $content

    } catch {
        $notice = "# [AXON] Snapshot generation failed: $($_.Exception.Message)"
        Set-Content -Path $snapshotPath -Value $notice -Encoding UTF8
        return $notice
    }
}


# ================================================================
#  PHASE 3 — SYSTEM PROMPT BUILDER
# ================================================================

function Build-SystemPrompt {
    $osInfo      = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue)
    $osCaption   = if ($osInfo) { $osInfo.Caption } else { "Windows (unknown version)" }
    $osBuild     = if ($osInfo) { $osInfo.BuildNumber } else { "?" }
    $userName    = $env:USERNAME
    $computerName= $env:COMPUTERNAME
    $currentDir  = (Get-Location).Path
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $sessionTime = Get-Date -Format "yyyy-MM-dd  HH:mm:ss"
    $profileName = $State.ActiveProfile.profile_name
    $model       = $State.ActiveProfile.model
    $provider    = $State.ActiveProfile.provider
    $sandboxNote = if ($State.SandboxMode) { "YES — no code will actually execute" } else { "NO — executions are live" }

    $memPath     = "$DataFolder\memory.txt"
    $memory      = if (Test-Path $memPath) { Get-Content $memPath -Raw } else { "No previous memory." }
    $smartMem    = Get-SmartMemoryBlock
    $fnBlock     = Get-FunctionRegistryBlock
    $snapshot    = Build-ScriptSnapshot

    $s           = Get-Settings
    $blockedAll  = @()
    if ($s) { $blockedAll += $s.blocked_paths; $blockedAll += $s.user_blocked_paths }
    $blockedList = ($blockedAll | Where-Object { $_ }) -join "`n      "
    $maxExec     = if ($s) { $s.max_executions_per_minute } else { 5 }
    $dryRun      = if ($s) { $s.dry_run_before_execute } else { $true }

    $pluginBlock = if ($State.LoadedPlugins.Count -gt 0) {
        ($State.LoadedPlugins | ForEach-Object { "  plugin_$($_.name) — $($_.desc)" }) -join "`n"
    } else { "  No plugins loaded." }

    $macroBlock = ""
    $macroFiles = Get-ChildItem "$DataFolder\macros" -Filter "*.json" -ErrorAction SilentlyContinue
    if ($macroFiles -and $macroFiles.Count -gt 0) {
        $macroLines = $macroFiles | ForEach-Object {
            try { $m = Get-Content $_.FullName -Raw | ConvertFrom-Json; "  $($m.name)" } catch {}
        }
        $macroBlock = $macroLines -join "`n"
    } else { $macroBlock = "  No macros saved yet." }

    # v1.1 — Active tasks block
    $taskBlock = if ($State.Tasks.Count -eq 0) { "  No tasks." } else {
        $State.Tasks | ForEach-Object {
            $icon = switch ($_.status) { "done" { "[v]" } "active" { "[>]" } default { "[ ]" } }
            "  $icon $($_.title)$(if($_.note){ ' — ' + $_.note })"
        }
        ($State.Tasks | ForEach-Object {
            $icon = switch ($_.status) { "done" { "[v]" } "active" { "[>]" } default { "[ ]" } }
            "  $icon $($_.title)$(if($_.note){ ' — ' + $_.note })"
        }) -join "`n"
    }

    $prompt = @"
╔══════════════════════════════════════════════════════════════════╗
  AXON v$AXON_VERSION — AI INTERFACE DOCUMENT  (fresh every call)
╚══════════════════════════════════════════════════════════════════╝

SESSION
  ID: $SESSION_ID  •  #$($State.SessionNumber)  •  $sessionTime
  Profile : $profileName  ($provider / $model)
  Sandbox : $sandboxNote
  Tokens  : ~$($State.TokenEstimate) estimated in context

ENVIRONMENT
  User: $userName  •  Machine: $computerName
  OS  : $osCaption (Build $osBuild)
  CWD : $currentDir
  Desktop : $desktopPath
  Data    : $DataFolder

══════════════════════════════════════════════════════════════════

WHO YOU ARE
  You are the AI brain of AXON v$AXON_VERSION — an intelligent agent
  running inside the user's Windows machine.  You are NOT a chatbot.
  The PowerShell script is your body.  You are the mind.
  The user is the authority.  Nothing destructive runs without approval.

══════════════════════════════════════════════════════════════════

TAG PROTOCOL  (embed these in your response to take action)

  ┌──────────────────────────────────────────────────────────────────┐
  │ TAG                            │ PURPOSE                │ TIER    │
  ├──────────────────────────────────────────────────────────────────┤
  │ `$CODE$`...`$ENDCODE$`          │ Execute PowerShell     │ CONFIRM │
  │ `$FILE:name$`...`$ENDFILE$`     │ Create a file          │ CONFIRM │
  │ `$PLACE:path$`                  │ Move temp -> real path │ CONFIRM │
  │ `$READ:path$`                   │ Read file -> context   │ AUTO    │
  │ `$CONFIRM:msg$`                 │ Ask user yes/no        │ CONFIRM │
  │ `$WARN:msg$`                    │ Flag risk              │ AUTO    │
  │ `$MEMORY:content$`              │ Write memory.txt       │ AUTO    │
  │ `$SEARCH:query$`                │ Web search             │ CONFIRM │
  │ `$OPEN:target$`                 │ Open file/URL/app      │ CONFIRM │
  │ `$NOTIFY:title|message$`        │ Windows notification   │ AUTO    │
  │ `$CLIP:read$`                   │ Read clipboard         │ AUTO    │
  │ `$CLIP:write|text$`             │ Write to clipboard     │ CONFIRM │
  │ `$STATUS:message$`              │ Update AXON status bar │ AUTO    │
  │ `$MACRO:save|name|steps$`       │ Save a macro           │ CONFIRM │
  │ `$MACRO:run|name$`              │ Run saved macro        │ CONFIRM │
  │ `$MEMSET:key|value$`            │ Store to smart memory  │ AUTO    │
  │ `$PLUGIN:name|input$`           │ Call a loaded plugin   │ CONFIRM │
  │ `$TASK:title|note|status$`      │ Add task to tracker    │ AUTO    │
  │ `$TASK_UPDATE:title|status$`    │ Update task status     │ AUTO    │
  └──────────────────────────────────────────────────────────────────┘

  TIER meanings:
    AUTO    — runs immediately, no confirmation needed
    CONFIRM — shows to user and requires y/n approval

  TASK STATUS values: waiting (not started), active (in progress), done (complete)

  EXAMPLES:
  Add a task:           `$TASK:Write report|Draft executive summary|active$`
  Complete a task:      `$TASK_UPDATE:Write report|done$`
  Search the web:       `$SEARCH:latest PowerShell 7 features$`
  Open a URL:           `$OPEN:https://docs.microsoft.com$`
  Notify the user:      `$NOTIFY:Done|Your report is ready.$`
  Read clipboard:       `$CLIP:read$`
  Write clipboard:      `$CLIP:write|Here is the result...$`
  Update status bar:    `$STATUS:Working on your report...$`
  Save a macro:         `$MACRO:save|morning-check|check disk space then list recent files$`
  Run a macro:          `$MACRO:run|morning-check$`
  Store smart memory:   `$MEMSET:user_project|C:\Projects\webapp$`

══════════════════════════════════════════════════════════════════

MULTI-STEP TASK TRACKER
$taskBlock

REGISTERED FUNCTIONS (auto-available this session)
$fnBlock

LOADED PLUGINS
$pluginBlock

SAVED MACROS
$macroBlock

══════════════════════════════════════════════════════════════════

DATA FOLDER  —  YOUR HOME BASE
  $DataFolder\
    temp\       -> YOUR staging area. Create files here freely.
    workspace\  -> Files you are actively reading/editing.
    plugins\    -> Loaded .ps1 plugins
    macros\     -> Saved macro definitions
    memory.txt  -> Your session notes
    smart_memory.json -> Your structured knowledge base

RULES
  [OK] Full read/write inside temp\ and workspace\
  [OK] Use `$MEMSET$` to remember anything structured about the user
  [OK] Use `$TASK$` at the start of multi-step work to create a checklist
  [OK] Use `$TASK_UPDATE$` to mark steps done as you complete them
  [X]  Cannot delete the Data folder itself
  [X]  Cannot touch settings.json or profiles\
  [X]  Cannot access Desktop or above without `$PLACE$` + approval

BLOCKED PATHS (hard-rejected, no exceptions)
  $blockedList

EXECUTION LIMITS
  Max code executions/min : $maxExec
  Dry run preview         : $dryRun

GOLDEN RULES
  1. Never touch blocked paths — not even to read them.
  2. Never modify the AXON script itself.
  3. Always use `$CONFIRM$` before irreversible actions.
  4. Always tell the user what you are doing and why.
  5. Use `$WARN$` if anything feels risky.
  6. Use `$MEMSET$` to remember anything useful for next session.
  7. Use `$STATUS$` to keep the user informed during long tasks.
  8. For multi-step work, create tasks with `$TASK$` and update as you go.

══════════════════════════════════════════════════════════════════

SMART MEMORY  (structured knowledge about this user)
$smartMem

SESSION MEMORY  (notes from last session)
$memory

══════════════════════════════════════════════════════════════════

FULL AXON SCRIPT REFERENCE  (sanitized — safety block redacted)
$snapshot
══════════════════════════════════════════════════════════════════
"@
    return $prompt
}


# ================================================================
#  PHASE 4 — SAFETY LAYER
# ================================================================

$DANGEROUS_PATTERNS = @(
    'Format-Volume',
    'Clear-Disk',
    'Initialize-Disk',
    'Remove-Item\s+.*-Recurse.*-Force',
    'Remove-Item\s+.*-Force.*-Recurse',
    'Set-ItemProperty\s+HKLM',
    'New-Item\s+HKLM',
    'Remove-ItemProperty\s+HKLM',
    'reg\s+delete',
    'reg\s+add',
    'net\s+user',
    'net\s+localgroup',
    'Invoke-Expression\s*\(',
    'iex\s*\(',
    '\$PSCommandPath',
    'Start-Process.*-Verb.*RunAs',
    'Set-ExecutionPolicy',
    'Disable-WindowsOptionalFeature',
    'Stop-Computer',
    'Restart-Computer'
)

function Test-PathSafe {
    param([string]$TargetPath)
    try { $resolved = [System.IO.Path]::GetFullPath($TargetPath) }
    catch { return $false }

    if ($AXON_SELF_PATH -and (Test-Path $AXON_SELF_PATH)) {
        if ($resolved -eq [System.IO.Path]::GetFullPath($AXON_SELF_PATH)) { return $false }
    }

    foreach ($blocked in $AXON_PROTECTED_PATHS) {
        try {
            $rb = [System.IO.Path]::GetFullPath($blocked)
            if ($resolved.StartsWith($rb, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
        } catch {}
    }

    $s = Get-Settings
    if ($s) {
        $all = @($s.blocked_paths) + @($s.user_blocked_paths)
        foreach ($bp in $all) {
            if (-not $bp) { continue }
            try {
                $rb = [System.IO.Path]::GetFullPath($bp)
                if ($resolved.StartsWith($rb, [System.StringComparison]::OrdinalIgnoreCase)) { return $false }
            } catch {}
        }
    }
    return $true
}

function Test-CodeSafe {
    param([string]$Code)
    foreach ($pattern in $DANGEROUS_PATTERNS) {
        if ($Code -match $pattern) {
            return @{ Safe = $false; Reason = "Dangerous pattern detected: $pattern" }
        }
    }
    $pathMatches = [regex]::Matches($Code, '[A-Za-z]:\\[^\s"''`,;]+')
    foreach ($m in $pathMatches) {
        $p = $m.Value.TrimEnd(')',']',';',',','.')
        if (-not (Test-PathSafe -TargetPath $p)) {
            return @{ Safe = $false; Reason = "Blocked path in code: $p" }
        }
    }
    return @{ Safe = $true; Reason = "" }
}

function Get-CodeSummary {
    param([string]$Code)
    $lines   = $Code -split "`n" | Where-Object { $_.Trim() -ne "" -and -not $_.TrimStart().StartsWith("#") }
    $summary = [System.Collections.ArrayList]@()
    foreach ($line in $lines) {
        $t = $line.Trim()
        switch -Regex ($t) {
            '^Get-ChildItem|^ls |^dir '            { $summary.Add("[LIST] List files/folders")            | Out-Null }
            '^Get-Content|^cat '                   { $summary.Add("[READ] Read file content")             | Out-Null }
            '^Set-Content|^Out-File|^Add-Content'  { $summary.Add("[WRITE] Write to a file")             | Out-Null }
            '^Copy-Item'                           { $summary.Add("[COPY] Copy a file or folder")        | Out-Null }
            '^Move-Item'                           { $summary.Add("[MOVE] Move a file or folder")        | Out-Null }
            '^Remove-Item'                         { $summary.Add("[DEL] Delete a file or folder")       | Out-Null }
            '^New-Item'                            { $summary.Add("[NEW] Create a new file or folder")   | Out-Null }
            '^Rename-Item'                         { $summary.Add("[RENAME] Rename a file or folder")    | Out-Null }
            '^Start-Process'                       { $summary.Add("[PROC] Launch a process/application") | Out-Null }
            '^Stop-Process'                        { $summary.Add("[STOP] Stop a running process")       | Out-Null }
            '^Get-Process'                         { $summary.Add("[LIST] List running processes")       | Out-Null }
            '^Invoke-WebRequest|^Invoke-RestMethod'{ $summary.Add("[NET] Make a web/network request")   | Out-Null }
            '^Write-Output|^Write-Host'            { $summary.Add("[OUT] Print output to terminal")      | Out-Null }
            '^Install-Package|^winget '            { $summary.Add("[PKG] Install software")             | Out-Null }
            '^Register-ScheduledTask'              { $summary.Add("[SCHED] Create a scheduled task")    | Out-Null }
            '^Compress-Archive|^Expand-Archive'    { $summary.Add("[ZIP] Compress or extract archive")  | Out-Null }
        }
    }
    if ($summary.Count -eq 0) { $summary.Add("[EXEC] Execute PowerShell ($($lines.Count) line(s))") | Out-Null }
    return ($summary | Select-Object -Unique)
}

function Request-UserConfirm {
    param([string]$Prompt)
    Write-Host ""
    Write-Host "  +-- Confirm Action " -ForegroundColor $UI.WarnText
    Write-Host "  |   $Prompt" -ForegroundColor White
    Write-Host "  +-- Proceed? (y/n): " -ForegroundColor $UI.WarnText -NoNewline
    $a = (Read-Host).Trim().ToLower()
    return ($a -eq "y" -or $a -eq "yes")
}

function Test-RateLimit {
    $s       = Get-Settings
    $maxExec = if ($s) { $s.max_executions_per_minute } else { 5 }
    $now     = Get-Date
    if (($now - $State.ExecutionWindowStart).TotalSeconds -ge 60) {
        $State.ExecutionCount        = 0
        $State.ExecutionWindowStart  = $now
    }
    if ($State.ExecutionCount -ge $maxExec) {
        Write-Msg -Role "error" -Content "Rate limit reached ($maxExec/min). Wait a moment."
        return $false
    }
    $State.ExecutionCount++
    return $true
}


# ================================================================
#  PHASE 4 — TAG ENGINES
# ================================================================

function Invoke-CodeTag {
    param([string]$Code)
    $Code = $Code.Trim()
    if ([string]::IsNullOrWhiteSpace($Code)) { return $null }
    $State.LastCodeBlock = $Code

    $safety = Test-CodeSafe -Code $Code
    if (-not $safety.Safe) {
        Write-Host ""
        Write-Host "  [!] CODE BLOCK REJECTED [!]" -ForegroundColor Red
        Write-Msg -Role "error" -Content "Safety violation: $($safety.Reason)"
        Write-ActionLog "CODE REJECTED — $($safety.Reason)"
        return "[REJECTED] $($safety.Reason)"
    }

    if (-not (Test-RateLimit)) { return "[RATE LIMITED]" }

    Write-Host ""
    Write-ThinDivider
    Write-Host "   AI wants to execute PowerShell:" -ForegroundColor $UI.WarnText
    Write-ThinDivider
    $Code -split "`n" | ForEach-Object { Write-Host "   $_" -ForegroundColor Cyan }
    Write-ThinDivider

    $s = Get-Settings
    if ($s -and $s.dry_run_before_execute) {
        Write-Host ""
        Write-Host "   This code will:" -ForegroundColor $UI.DimText
        foreach ($ln in (Get-CodeSummary -Code $Code)) { Write-Host "   $ln" -ForegroundColor $UI.BodyText }
    }

    if ($State.SandboxMode) {
        Write-Msg -Role "warn" -Content "SANDBOX MODE — execution simulated, nothing ran."
        Write-ActionLog "SANDBOX — code simulated"
        return "[SANDBOX] Execution simulated."
    }

    if (-not (Request-UserConfirm -Prompt "Run this code on your machine?")) {
        Write-Msg -Role "system" -Content "Code execution denied."
        Write-ActionLog "CODE DENIED by user"
        return "[DENIED] User rejected execution."
    }

    Write-Host ""
    Write-Host "  > Executing..." -ForegroundColor $UI.DimText
    try {
        $output = Invoke-Expression $Code 2>&1 | Out-String
        $output = $output.Trim()
        Write-Host ""
        Write-ThinDivider
        Write-Host "   Output:" -ForegroundColor $UI.OkText
        Write-ThinDivider
        if ([string]::IsNullOrWhiteSpace($output)) {
            Write-Host "   (no output)" -ForegroundColor $UI.DimText
        } else {
            $output -split "`n" | ForEach-Object { Write-Host "   $_" -ForegroundColor $UI.BodyText }
        }
        Write-ThinDivider
        Write-ActionLog "CODE EXECUTED — $($Code.Length) chars — output $($output.Length) chars"
        Push-UndoEntry -Type "CODE_EXEC" -Data @{ code = $Code; output = $output }
        return $output
    } catch {
        $err = $_.Exception.Message
        Write-Msg -Role "error" -Content "Execution error: $err"
        Write-ActionLog "CODE ERROR — $err"
        return "[ERROR] $err"
    }
}

function Invoke-FileTag {
    param([string]$FileName, [string]$Content)
    $FileName = [System.IO.Path]::GetFileName($FileName.Trim())
    if ([string]::IsNullOrWhiteSpace($FileName)) { Write-Msg -Role "error" -Content "FILE tag had empty filename."; return $null }
    $destPath = "$DataFolder\temp\$FileName"

    Write-Host ""
    Write-ThinDivider
    Write-Host "   AI wants to create a file:" -ForegroundColor $UI.WarnText
    Write-Host "   $destPath" -ForegroundColor White
    Write-ThinDivider
    $Content -split "`n" | Select-Object -First 8 | ForEach-Object { Write-Host "   $_" -ForegroundColor $UI.BodyText }
    $totalLines = ($Content -split "`n").Count
    if ($totalLines -gt 8) { Write-Host "   ... ($totalLines lines total)" -ForegroundColor $UI.DimText }
    Write-ThinDivider

    if ($State.SandboxMode) {
        Write-Msg -Role "warn" -Content "SANDBOX MODE — file creation simulated."
        Write-ActionLog "SANDBOX — FILE simulated: $FileName"
        return "[SANDBOX] File creation simulated."
    }

    if (-not (Request-UserConfirm -Prompt "Create '$FileName' in temp folder?")) {
        Write-ActionLog "FILE DENIED: $FileName"
        return "[DENIED]"
    }

    try {
        $tmp = "$destPath.tmp"
        Set-Content -Path $tmp -Value $Content -Encoding UTF8
        Move-Item -Path $tmp -Destination $destPath -Force
        Write-Msg -Role "ok" -Content "File created: $destPath"
        Write-ActionLog "FILE CREATED: $destPath"
        Push-UndoEntry -Type "FILE_CREATE" -Data @{ path = $destPath }
        return "[OK] Created at $destPath"
    } catch {
        $err = $_.Exception.Message
        Write-Msg -Role "error" -Content "File creation failed: $err"
        Write-ActionLog "FILE ERROR: $err"
        return "[ERROR] $err"
    }
}

function Invoke-PlaceTag {
    param([string]$DestPath)
    $DestPath = $DestPath.Trim()
    if (-not (Test-PathSafe -TargetPath $DestPath)) {
        Write-Msg -Role "error" -Content "PLACE blocked — protected path: $DestPath"
        Write-ActionLog "PLACE BLOCKED: $DestPath"
        return "[BLOCKED]"
    }
    $fileName = [System.IO.Path]::GetFileName($DestPath)
    $srcPath  = "$DataFolder\temp\$fileName"
    if (-not (Test-Path $srcPath)) {
        Write-Msg -Role "error" -Content "No file '$fileName' found in temp."
        return "[ERROR] Source not found."
    }

    Write-Host ""
    Write-ThinDivider
    Write-Host "   AI wants to place a file:" -ForegroundColor $UI.WarnText
    Write-Host "   From : $srcPath"   -ForegroundColor $UI.DimText
    Write-Host "   To   : $DestPath"  -ForegroundColor White
    Write-ThinDivider

    if ($State.SandboxMode) {
        Write-Msg -Role "warn" -Content "SANDBOX MODE — placement simulated."
        Write-ActionLog "SANDBOX — PLACE simulated: $DestPath"
        return "[SANDBOX]"
    }

    if (-not (Request-UserConfirm -Prompt "Move file to: $DestPath ?")) {
        Write-ActionLog "PLACE DENIED: $DestPath"
        return "[DENIED]"
    }

    try {
        $dir = [System.IO.Path]::GetDirectoryName($DestPath)
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Move-Item -Path $srcPath -Destination $DestPath -Force
        Write-Msg -Role "ok" -Content "File placed: $DestPath"
        Write-ActionLog "FILE PLACED: $srcPath -> $DestPath"
        Push-UndoEntry -Type "FILE_PLACE" -Data @{ dest = $DestPath; src = $srcPath }
        return "[OK] Placed at $DestPath"
    } catch {
        $err = $_.Exception.Message
        Write-Msg -Role "error" -Content "Place failed: $err"
        Write-ActionLog "PLACE ERROR: $err"
        return "[ERROR] $err"
    }
}

function Invoke-ReadTag {
    param([string]$FilePath)
    $FilePath = $FilePath.Trim()
    if (-not (Test-PathSafe -TargetPath $FilePath)) {
        Write-Msg -Role "error" -Content "READ blocked — protected path."
        Write-ActionLog "READ BLOCKED: $FilePath"
        return "[BLOCKED]"
    }
    if (-not (Test-Path $FilePath)) {
        Write-Msg -Role "error" -Content "READ — file not found: $FilePath"
        return "[ERROR] File not found."
    }
    try {
        $item = Get-Item $FilePath
        if ($item.Length -gt 204800) {
            $content = (Get-Content $FilePath -TotalCount 300) -join "`n"
            $content += "`n[... truncated — first 300 lines shown ...]"
        } else {
            $content = Get-Content $FilePath -Raw
        }
        Write-Msg -Role "system" -Content "File read into context: $FilePath  ($([Math]::Round($item.Length/1KB,1)) KB)"
        Write-ActionLog "FILE READ: $FilePath"
        return $content
    } catch {
        $err = $_.Exception.Message
        Write-Msg -Role "error" -Content "READ error: $err"
        return "[ERROR] $err"
    }
}

function Invoke-ConfirmTag {
    param([string]$Message)
    Write-Host ""
    Write-Host "  +-- AI is asking for your confirmation" -ForegroundColor Magenta
    Write-Host "  |   $Message" -ForegroundColor White
    Write-Host "  +-- Proceed? (y/n): " -ForegroundColor Magenta -NoNewline
    $a = (Read-Host).Trim().ToLower()
    $r = ($a -eq "y" -or $a -eq "yes")
    Write-ActionLog "CONFIRM — '$Message' — $(if($r){'approved'}else{'denied'})"
    return $r
}

function Invoke-WarnTag {
    param([string]$Message)
    Write-Host ""
    Write-Host "  [!] AI WARNING" -ForegroundColor Yellow
    Write-Host "      $Message"   -ForegroundColor Yellow
    Write-ActionLog "WARN — $Message"
}

function Invoke-MemoryTag {
    param([string]$Content)
    $memPath = "$DataFolder\memory.txt"
    $ts      = Get-Date -Format "yyyy-MM-dd HH:mm"
    # Atomic write
    $tmp = "$memPath.tmp"
    Set-Content -Path $tmp -Value "[$ts]`n$Content" -Encoding UTF8
    Move-Item -Path $tmp -Destination $memPath -Force
    Write-Msg -Role "system" -Content "Memory updated for next session."
    Write-ActionLog "MEMORY written — $($Content.Length) chars"
}


# ================================================================
#  PHASE 4 — RESPONSE PARSER + DISPLAY
# ================================================================

function Write-AIResponse {
    param([string]$Text)
    Write-Host ""
    Write-Host "  AI  : " -ForegroundColor $UI.AILabel -NoNewline
    $maxW    = [Math]::Max((Get-WindowWidth) - 10, 40)
    $indent  = "         "
    $firstLn = $true
    $line    = ""
    foreach ($word in ($Text -split ' ')) {
        $hasNL = $word.Contains("`n")
        if ($hasNL) {
            $parts2 = $word -split "`n"
            foreach ($i in 0..($parts2.Count-1)) {
                $p  = $parts2[$i]
                $tl = if ($line) { "$line $p" } else { $p }
                if ($tl.TrimStart().Length -gt $maxW -and $line) {
                    if ($firstLn) { Write-Host $line.TrimStart() -ForegroundColor $UI.BodyText; $firstLn = $false }
                    else          { Write-Host ($indent + $line.TrimStart()) -ForegroundColor $UI.BodyText }
                    $line = $p
                } else { $line = $tl.TrimStart() }
                if ($i -lt ($parts2.Count-1)) {
                    if ($firstLn) { Write-Host $line -ForegroundColor $UI.BodyText; $firstLn = $false }
                    else          { Write-Host ($indent + $line) -ForegroundColor $UI.BodyText }
                    $line = ""
                }
            }
        } else {
            $test = if ($line) { "$line $word" } else { $word }
            if ($test.TrimStart().Length -gt $maxW -and $line) {
                if ($firstLn) { Write-Host $line.TrimStart() -ForegroundColor $UI.BodyText; $firstLn = $false }
                else          { Write-Host ($indent + $line.TrimStart()) -ForegroundColor $UI.BodyText }
                $line = $word
            } else { $line = $test.TrimStart() }
        }
    }
    if ($line.Trim()) {
        if ($firstLn) { Write-Host $line -ForegroundColor $UI.BodyText }
        else          { Write-Host ($indent + $line) -ForegroundColor $UI.BodyText }
    }
}

function Get-DisplayText {
    param([string]$Text)
    $c = $Text
    $o = [System.Text.RegularExpressions.RegexOptions]::Singleline
    $c = [regex]::Replace($c, '\$CODE\$.*?\$ENDCODE\$',      '[executing code...]',      $o)
    $c = [regex]::Replace($c, '\$FILE:.+?\$.*?\$ENDFILE\$',  '[creating file...]',        $o)
    $c = [regex]::Replace($c, '\$MEMORY:.+?\$',              '',                          $o)
    $c = [regex]::Replace($c, '\$MEMSET:.+?\|.+?\$',         '',                          $o)
    $c = [regex]::Replace($c, '\$TASK:.+?\|.+?\|.+?\$',      '',                          $o)
    $c = [regex]::Replace($c, '\$TASK_UPDATE:.+?\|.+?\$',    '',                          $o)
    $c = $c -replace '\$PLACE:.+?\$',             '[placing file...]'
    $c = $c -replace '\$READ:.+?\$',              '[reading file...]'
    $c = $c -replace '\$CONFIRM:.+?\$',           '[requesting confirmation...]'
    $c = $c -replace '\$WARN:.+?\$',              ''
    $c = $c -replace '\$SEARCH:.+?\$',            '[searching web...]'
    $c = $c -replace '\$OPEN:.+?\$',              '[opening...]'
    $c = $c -replace '\$NOTIFY:.+?\|.+?\$',       '[notifying...]'
    $c = $c -replace '\$CLIP:read\$',             '[reading clipboard...]'
    $c = $c -replace '\$CLIP:write\|.+?\$',       '[writing to clipboard...]'
    $c = $c -replace '\$STATUS:.+?\$',            ''
    $c = $c -replace '\$MACRO:(save|run)\|.+?\$', '[macro...]'
    $c = $c -replace '\$PLUGIN:.+?\|.+?\$',       '[running plugin...]'
    return $c.Trim()
}

function Invoke-ParseResponse {
    param([string]$RawReply)
    $feedback = [System.Collections.ArrayList]@()
    $o        = [System.Text.RegularExpressions.RegexOptions]::Singleline

    # ── WARN — display first, no blocking ──
    foreach ($m in ([regex]::Matches($RawReply, '\$WARN:(.+?)\$', $o))) {
        Invoke-WarnTag -Message $m.Groups[1].Value.Trim()
    }

    # ── STATUS — update header bar (auto) ──
    foreach ($m in ([regex]::Matches($RawReply, '\$STATUS:(.+?)\$'))) {
        Invoke-FunctionCall -Name "status" -Args @{ message = $m.Groups[1].Value.Trim() } | Out-Null
    }

    # ── NOTIFY — auto ──
    foreach ($m in ([regex]::Matches($RawReply, '\$NOTIFY:(.+?)\|(.+?)\$'))) {
        $r = Invoke-FunctionCall -Name "notify" -Args @{ title = $m.Groups[1].Value.Trim(); message = $m.Groups[2].Value.Trim() }
        $feedback.Add("[NOTIFY] $r") | Out-Null
    }

    # ── CLIP read — auto ──
    foreach ($m in ([regex]::Matches($RawReply, '\$CLIP:read\$'))) {
        $r = Invoke-FunctionCall -Name "clip" -Args @{ action = "read" }
        if ($r) { $feedback.Add("[CLIPBOARD CONTENT]`n$r") | Out-Null }
    }

    # ── MEMSET — auto ──
    foreach ($m in ([regex]::Matches($RawReply, '\$MEMSET:(.+?)\|(.+?)\$'))) {
        $r = Invoke-FunctionCall -Name "memory_set" -Args @{ key = $m.Groups[1].Value.Trim(); value = $m.Groups[2].Value.Trim() }
        $feedback.Add("[SMART MEMORY] $r") | Out-Null
    }

    # ── TASK — auto (add task to tracker) ──
    foreach ($m in ([regex]::Matches($RawReply, '\$TASK:(.+?)\|(.+?)\|(.+?)\$'))) {
        $r = Invoke-FunctionCall -Name "task_add" -Args @{
            title  = $m.Groups[1].Value.Trim()
            note   = $m.Groups[2].Value.Trim()
            status = $m.Groups[3].Value.Trim()
        }
        $feedback.Add("[TASK] $r") | Out-Null
    }

    # ── TASK_UPDATE — auto ──
    foreach ($m in ([regex]::Matches($RawReply, '\$TASK_UPDATE:(.+?)\|(.+?)\$'))) {
        $r = Invoke-FunctionCall -Name "task_update" -Args @{
            title  = $m.Groups[1].Value.Trim()
            status = $m.Groups[2].Value.Trim()
        }
        $feedback.Add("[TASK_UPDATE] $r") | Out-Null
    }

    # ── MEMORY — write to memory.txt ──
    foreach ($m in ([regex]::Matches($RawReply, '\$MEMORY:(.+?)\$', $o))) {
        Invoke-MemoryTag -Content $m.Groups[1].Value.Trim()
    }

    # ── CONFIRM — may block further execution ──
    $blocked = $false
    foreach ($m in ([regex]::Matches($RawReply, '\$CONFIRM:(.+?)\$', $o))) {
        if (-not (Invoke-ConfirmTag -Message $m.Groups[1].Value.Trim())) {
            $blocked = $true
            $feedback.Add("[CONFIRM DENIED]: $($m.Groups[1].Value.Trim())") | Out-Null
        } else {
            $feedback.Add("[CONFIRM APPROVED]: $($m.Groups[1].Value.Trim())") | Out-Null
        }
    }
    if ($blocked) {
        Write-Msg -Role "system" -Content "Actions skipped — user declined confirmation."
        return ($feedback -join "`n")
    }

    # ── READ — auto ──
    foreach ($m in ([regex]::Matches($RawReply, '\$READ:(.+?)\$'))) {
        $r = Invoke-ReadTag -FilePath $m.Groups[1].Value.Trim()
        if ($r) { $feedback.Add("[READ: $($m.Groups[1].Value.Trim())]`n$r") | Out-Null }
    }

    # ── SEARCH — confirm ──
    foreach ($m in ([regex]::Matches($RawReply, '\$SEARCH:(.+?)\$'))) {
        $query = $m.Groups[1].Value.Trim()
        Write-Host ""
        Write-ThinDivider
        Write-Host "   AI wants to search the web:" -ForegroundColor $UI.WarnText
        Write-Host "   Query: $query" -ForegroundColor White
        Write-ThinDivider
        if ($State.SandboxMode) {
            $feedback.Add("[SEARCH SANDBOX] Would search: $query") | Out-Null
        } elseif (Request-UserConfirm -Prompt "Allow web search: '$query'?") {
            $r = Invoke-FunctionCall -Name "search" -Args @{ query = $query }
            Write-Msg -Role "system" -Content "Search results injected into context."
            $feedback.Add("[SEARCH: $query]`n$r") | Out-Null
            Write-ActionLog "SEARCH executed: $query"
        } else {
            $feedback.Add("[SEARCH DENIED]: $query") | Out-Null
        }
    }

    # ── OPEN — confirm ──
    foreach ($m in ([regex]::Matches($RawReply, '\$OPEN:(.+?)\$'))) {
        $target = $m.Groups[1].Value.Trim()
        Write-Host ""
        Write-ThinDivider
        Write-Host "   AI wants to open:" -ForegroundColor $UI.WarnText
        Write-Host "   $target" -ForegroundColor White
        Write-ThinDivider
        if ($State.SandboxMode) {
            $feedback.Add("[OPEN SANDBOX] Would open: $target") | Out-Null
        } elseif (Request-UserConfirm -Prompt "Open '$target'?") {
            $r = Invoke-FunctionCall -Name "open" -Args @{ target = $target }
            $feedback.Add("[OPEN] $r") | Out-Null
        } else {
            $feedback.Add("[OPEN DENIED]: $target") | Out-Null
        }
    }

    # ── CLIP write — confirm ──
    foreach ($m in ([regex]::Matches($RawReply, '\$CLIP:write\|(.+?)\$', $o))) {
        $text = $m.Groups[1].Value.Trim()
        if ($State.SandboxMode) {
            $feedback.Add("[CLIP SANDBOX] Would write to clipboard.") | Out-Null
        } elseif (Request-UserConfirm -Prompt "Write to clipboard ($($text.Length) chars)?") {
            $r = Invoke-FunctionCall -Name "clip" -Args @{ action = "write"; text = $text }
            $feedback.Add("[CLIP] $r") | Out-Null
        }
    }

    # ── MACRO save — confirm ──
    foreach ($m in ([regex]::Matches($RawReply, '\$MACRO:save\|(.+?)\|(.+?)\$', $o))) {
        $name  = $m.Groups[1].Value.Trim()
        $steps = $m.Groups[2].Value.Trim()
        if (Request-UserConfirm -Prompt "Save macro '$name'?") {
            $r = Invoke-FunctionCall -Name "macro" -Args @{ action = "save"; name = $name; steps = $steps }
            $feedback.Add("[MACRO] $r") | Out-Null
        }
    }

    # ── MACRO run — confirm ──
    foreach ($m in ([regex]::Matches($RawReply, '\$MACRO:run\|(.+?)\$'))) {
        $name = $m.Groups[1].Value.Trim()
        if (Request-UserConfirm -Prompt "Run macro '$name'?") {
            $r = Invoke-FunctionCall -Name "macro" -Args @{ action = "run"; name = $name }
            $feedback.Add("[MACRO RUN: $name] $r") | Out-Null
        }
    }

    # ── PLUGIN — confirm ──
    foreach ($m in ([regex]::Matches($RawReply, '\$PLUGIN:(.+?)\|(.+?)\$', $o))) {
        $pName  = $m.Groups[1].Value.Trim()
        $pInput = $m.Groups[2].Value.Trim()
        if (Request-UserConfirm -Prompt "Run plugin '$pName'?") {
            $r = Invoke-FunctionCall -Name "plugin_$pName" -Args @{ input = $pInput }
            $feedback.Add("[PLUGIN: $pName] $r") | Out-Null
        }
    }

    # ── FILE — confirm ──
    foreach ($m in ([regex]::Matches($RawReply, '\$FILE:(.+?)\$(.*?)\$ENDFILE\$', $o))) {
        $r = Invoke-FileTag -FileName $m.Groups[1].Value.Trim() -Content $m.Groups[2].Value.Trim()
        if ($r) { $feedback.Add("[FILE: $($m.Groups[1].Value.Trim())] $r") | Out-Null }
    }

    # ── CODE — confirm ──
    foreach ($m in ([regex]::Matches($RawReply, '\$CODE\$(.*?)\$ENDCODE\$', $o))) {
        $r = Invoke-CodeTag -Code $m.Groups[1].Value
        if ($r) { $feedback.Add("[CODE OUTPUT]`n$r") | Out-Null }
    }

    # ── PLACE — confirm ──
    foreach ($m in ([regex]::Matches($RawReply, '\$PLACE:(.+?)\$'))) {
        $r = Invoke-PlaceTag -DestPath $m.Groups[1].Value.Trim()
        if ($r) { $feedback.Add("[PLACE: $($m.Groups[1].Value.Trim())] $r") | Out-Null }
    }

    return ($feedback -join "`n")
}


# ================================================================
#  PHASE 5 — SESSION LOGGING
# ================================================================

function Initialize-SessionLog {
    $ts      = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $profile = if ($State.ActiveProfile) { $State.ActiveProfile.profile_name -replace '[\\/:*?"<>|]','_' } else { "NoProfile" }
    $logName = "session_$($State.SessionNumber)_${ts}.json"
    $logPath = "$DataFolder\sessions\$logName"

    $meta = [ordered]@{
        session_number = $State.SessionNumber
        session_id     = $SESSION_ID
        started_at     = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        profile        = $profile
        provider       = if ($State.ActiveProfile) { $State.ActiveProfile.provider } else { "" }
        model          = if ($State.ActiveProfile) { $State.ActiveProfile.model }    else { "" }
        turns          = @()
        ended_at       = ""
        ai_calls       = 0
        executions     = 0
    }

    $meta | ConvertTo-Json -Depth 5 | Set-Content -Path $logPath -Encoding UTF8
    $State.SessionLogPath = $logPath
    Write-ActionLog "Session log initialized: $logName"
}

function Save-SessionLog {
    if (-not $State.SessionLogPath) { return }
    try {
        $log   = Get-Content $State.SessionLogPath -Raw | ConvertFrom-Json
        $turns = [System.Collections.ArrayList]@()

        foreach ($msg in $State.ChatHistory) {
            if ($msg.content -like "\[AXON*" -or $msg.content -like "\[CONTEXT*") { continue }
            $turns.Add([ordered]@{
                role    = $msg.role
                content = $msg.content
            }) | Out-Null
        }

        $log.turns      = $turns.ToArray()
        $log.ended_at   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        $log.ai_calls   = $State.AICallCount
        $log.executions = $State.ExecutionCount

        # Atomic write for session log
        $tmp = "$($State.SessionLogPath).tmp"
        $log | ConvertTo-Json -Depth 10 | Set-Content -Path $tmp -Encoding UTF8
        Move-Item -Path $tmp -Destination $State.SessionLogPath -Force
    } catch {
        Write-ActionLog "Session log save failed: $($_.Exception.Message)"
    }
}

function Invoke-HistoryCommand {
    param([string]$Sub = "")

    $sessionsDir = "$DataFolder\sessions"
    $logs = Get-ChildItem $sessionsDir -Filter "*.json" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending

    if (-not $logs -or $logs.Count -eq 0) {
        Write-Host ""; Write-ThinDivider
        Write-Host "   Session History" -ForegroundColor $UI.Header
        Write-ThinDivider
        Write-Host "   No past sessions found." -ForegroundColor $UI.DimText
        Write-ThinDivider; return
    }

    # ── v1.1: /history search [query] ──
    if ($Sub -match '^search\s+(.+)$') {
        $query = $Matches[1].Trim()
        Invoke-HistorySearch -Query $query -Logs $logs
        return
    }

    # ── v1.1: /history resume [n] ──
    if ($Sub -match '^resume\s+(\d+)$') {
        $idx = [int]$Matches[1] - 1
        if ($idx -lt 0 -or $idx -ge $logs.Count) { Write-Msg -Role "error" -Content "Invalid session number."; return }
        Load-SessionHistory -LogPath $logs[$idx].FullName; return
    }

    # ── v1.1: /history export [n] ──
    if ($Sub -match '^export\s+(\d+)$') {
        $idx = [int]$Matches[1] - 1
        if ($idx -lt 0 -or $idx -ge $logs.Count) { Write-Msg -Role "error" -Content "Invalid session number."; return }
        Export-SessionHistory -LogPath $logs[$idx].FullName; return
    }

    # Legacy: /history load [n]
    if ($Sub -match '^load\s+(\d+)$') {
        $idx = [int]$Matches[1] - 1
        if ($idx -lt 0 -or $idx -ge $logs.Count) { Write-Msg -Role "error" -Content "Invalid session number."; return }
        Load-SessionHistory -LogPath $logs[$idx].FullName; return
    }

    # /history [n] — detail view
    if ($Sub -match '^\d+$') {
        $idx = [int]$Sub - 1
        if ($idx -lt 0 -or $idx -ge $logs.Count) { Write-Msg -Role "error" -Content "Invalid session number."; return }
        Show-SessionDetail -LogPath $logs[$idx].FullName; return
    }

    # Default — list
    Write-Host ""; Write-ThinDivider
    Write-Host "   Session History  ($($logs.Count) sessions)" -ForegroundColor $UI.Header
    Write-ThinDivider
    Write-Host ("   {0,-4} {1,-22} {2,-18} {3,-6} {4}" -f "#","Started","Profile","Turns","Model") -ForegroundColor $UI.DimText
    Write-ThinDivider

    $i = 1
    foreach ($log in $logs) {
        try {
            $d     = Get-Content $log.FullName -Raw | ConvertFrom-Json
            $turns = if ($d.turns) { $d.turns.Count } else { 0 }
            $cur   = if ($State.SessionLogPath -eq $log.FullName) { " <" } else { "" }
            Write-Host ("   {0,-4} {1,-22} {2,-18} {3,-6} {4}{5}" -f $i, $d.started_at, $d.profile, $turns, $d.model, $cur) -ForegroundColor $UI.BodyText
        } catch {
            Write-Host "   $i   $($log.Name)  (unreadable)" -ForegroundColor $UI.DimText
        }
        $i++
    }
    Write-ThinDivider
    Write-Host "   /history [n]           -> view session detail" -ForegroundColor $UI.DimText
    Write-Host "   /history resume [n]    -> load session into context" -ForegroundColor $UI.DimText
    Write-Host "   /history search [q]    -> search transcripts" -ForegroundColor $UI.DimText
    Write-Host "   /history export [n]    -> export to text file" -ForegroundColor $UI.DimText
    Write-ThinDivider
}

# ── v1.1: History Search ──
function Invoke-HistorySearch {
    param([string]$Query, $Logs)
    Write-Host ""
    Write-ThinDivider
    Write-Host "   History Search — '$Query'" -ForegroundColor $UI.Header
    Write-ThinDivider

    $found = $false
    $i = 1
    foreach ($log in $Logs) {
        try {
            $d = Get-Content $log.FullName -Raw | ConvertFrom-Json
            if (-not $d.turns) { $i++; continue }

            $matches = $d.turns | Where-Object { $_.content -like "*$Query*" }
            if ($matches) {
                $found = $true
                Write-Host ""
                Write-Host "   Session #$i  ($($d.started_at)  $($d.profile))" -ForegroundColor $UI.WarnText
                foreach ($turn in $matches) {
                    $snippet = $turn.content
                    $idx     = $snippet.IndexOf($Query, [System.StringComparison]::OrdinalIgnoreCase)
                    $start   = [Math]::Max(0, $idx - 40)
                    $end     = [Math]::Min($snippet.Length, $idx + $Query.Length + 40)
                    $preview = "..." + $snippet.Substring($start, $end - $start) + "..."
                    $label   = if ($turn.role -eq "user") { "You" } else { " AI" }
                    Write-Host "     [$label] $preview" -ForegroundColor $UI.BodyText
                }
            }
        } catch {}
        $i++
    }

    if (-not $found) {
        Write-Host "   No matches found for '$Query' in any session." -ForegroundColor $UI.DimText
    }
    Write-ThinDivider
}

# ── v1.1: History Export ──
function Export-SessionHistory {
    param([string]$LogPath)
    try { $d = Get-Content $LogPath -Raw | ConvertFrom-Json }
    catch { Write-Msg -Role "error" -Content "Could not read session log."; return }

    $outName = "AXON_Session_$($d.session_number)_$($d.started_at -replace '[: ]','-').txt"
    $outPath = "$DataFolder\$outName"

    $sb = [System.Text.StringBuilder]::new()
    $sb.AppendLine("AXON Session Export") | Out-Null
    $sb.AppendLine("===================") | Out-Null
    $sb.AppendLine("Session #:  $($d.session_number)") | Out-Null
    $sb.AppendLine("Started:    $($d.started_at)") | Out-Null
    $sb.AppendLine("Ended:      $($d.ended_at)") | Out-Null
    $sb.AppendLine("Profile:    $($d.profile)") | Out-Null
    $sb.AppendLine("Model:      $($d.model)") | Out-Null
    $sb.AppendLine("AI calls:   $($d.ai_calls)") | Out-Null
    $sb.AppendLine("") | Out-Null
    $sb.AppendLine("────────────────────────────────────────────") | Out-Null
    $sb.AppendLine("CONVERSATION") | Out-Null
    $sb.AppendLine("────────────────────────────────────────────") | Out-Null
    $sb.AppendLine("") | Out-Null

    if ($d.turns) {
        foreach ($turn in $d.turns) {
            $label = if ($turn.role -eq "user") { "YOU" } else { " AI" }
            $sb.AppendLine("[$label]") | Out-Null
            $sb.AppendLine($turn.content) | Out-Null
            $sb.AppendLine("") | Out-Null
        }
    }

    Set-Content -Path $outPath -Value $sb.ToString() -Encoding UTF8
    Write-Msg -Role "ok" -Content "Exported to: $outPath"
    Write-ActionLog "HISTORY EXPORTED: Session #$($d.session_number) -> $outName"
}

function Show-SessionDetail {
    param([string]$LogPath)
    try { $d = Get-Content $LogPath -Raw | ConvertFrom-Json }
    catch { Write-Msg -Role "error" -Content "Could not read session log."; return }

    Write-Host ""; Write-ThinDivider
    Write-Host "   Session Detail" -ForegroundColor $UI.Header
    Write-ThinDivider
    Write-Host ("   {0,-22} {1}" -f "Session #:",  $d.session_number)  -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-22} {1}" -f "Started:",    $d.started_at)      -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-22} {1}" -f "Ended:",      $(if($d.ended_at){"$($d.ended_at)"}else{"(in progress)"})) -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-22} {1}" -f "Profile:",    $d.profile)         -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-22} {1}" -f "Model:",      $d.model)           -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-22} {1}" -f "AI calls:",   $d.ai_calls)        -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-22} {1}" -f "Turns:",      $(if($d.turns){$d.turns.Count}else{0})) -ForegroundColor $UI.BodyText
    Write-ThinDivider

    if ($d.turns -and $d.turns.Count -gt 0) {
        Write-Host ""; Write-Host "   Last 6 turns:" -ForegroundColor $UI.DimText
        foreach ($turn in ($d.turns | Select-Object -Last 6)) {
            $label = if ($turn.role -eq "user") { "  You" } else { "   AI" }
            $color = if ($turn.role -eq "user") { $UI.UserLabel } else { $UI.AILabel }
            $preview = if ($turn.content.Length -gt 110) { $turn.content.Substring(0,110) + "..." } else { $turn.content }
            Write-Host ""; Write-Host "   $label : " -ForegroundColor $color -NoNewline
            Write-Host $preview -ForegroundColor $UI.BodyText
        }
    }
    Write-Host ""; Write-ThinDivider
    Write-Host "   /history export [n]  -> export this session to a .txt file" -ForegroundColor $UI.DimText
    Write-Host "   /history resume [n]  -> load this session into current context" -ForegroundColor $UI.DimText
    Write-ThinDivider
}

function Load-SessionHistory {
    param([string]$LogPath)
    try { $d = Get-Content $LogPath -Raw | ConvertFrom-Json }
    catch { Write-Msg -Role "error" -Content "Could not read session log."; return }

    if (-not $d.turns -or $d.turns.Count -eq 0) {
        Write-Msg -Role "warn" -Content "That session has no conversation turns to load."; return
    }

    Write-Host ""
    Write-Host "   Load $($d.turns.Count) turns from Session #$($d.session_number) into current context?" -ForegroundColor $UI.WarnText
    Write-Host "   Your existing context will be replaced. (y/n): " -ForegroundColor $UI.WarnText -NoNewline
    if ((Read-Host).Trim().ToLower() -notin @("y","yes")) {
        Write-Msg -Role "system" -Content "Cancelled."; return
    }

    $State.ChatHistory.Clear()
    foreach ($turn in $d.turns) {
        $State.ChatHistory.Add(@{ role = $turn.role; content = $turn.content }) | Out-Null
    }

    Write-Msg -Role "ok"     -Content "Loaded $($d.turns.Count) turns from Session #$($d.session_number)."
    Write-Msg -Role "system" -Content "AI has full context from that session on your next message."
    Write-ActionLog "Session history loaded from: $([System.IO.Path]::GetFileName($LogPath))"
}


# ================================================================
#  PHASE 5 — UNDO SYSTEM
# ================================================================

function Push-UndoEntry {
    param(
        [ValidateSet("FILE_CREATE","FILE_PLACE","CODE_EXEC")]
        [string]$Type,
        [hashtable]$Data
    )
    $State.UndoStack.Add(@{
        type      = $Type
        data      = $Data
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }) | Out-Null
    while ($State.UndoStack.Count -gt 20) { $State.UndoStack.RemoveAt(0) }
}

function Invoke-UndoCommand {
    if ($State.UndoStack.Count -eq 0) {
        Write-Msg -Role "system" -Content "Nothing to undo."; return
    }

    $last = $State.UndoStack[$State.UndoStack.Count - 1]
    $State.UndoStack.RemoveAt($State.UndoStack.Count - 1)

    Write-Host ""; Write-ThinDivider
    Write-Host "   Undo — $($last.type)  at $($last.timestamp)" -ForegroundColor $UI.WarnText
    Write-ThinDivider

    switch ($last.type) {
        "FILE_CREATE" {
            $path = $last.data.path
            Write-Host "   Will delete: $path" -ForegroundColor $UI.BodyText
            if (-not (Test-Path $path)) {
                Write-Msg -Role "warn" -Content "File no longer exists: $path"; return
            }
            Write-Host "   Confirm delete? (y/n): " -ForegroundColor $UI.WarnText -NoNewline
            if ((Read-Host).Trim().ToLower() -in @("y","yes")) {
                try {
                    Remove-Item -Path $path -Force
                    Write-Msg -Role "ok" -Content "Undone — deleted: $path"
                    Write-ActionLog "UNDO FILE_CREATE — deleted: $path"
                } catch { Write-Msg -Role "error" -Content "Undo failed: $($_.Exception.Message)" }
            } else { Write-Msg -Role "system" -Content "Undo cancelled." }
        }

        "FILE_PLACE" {
            $dest = $last.data.dest
            $src  = $last.data.src
            Write-Host "   Will move back: $dest" -ForegroundColor $UI.BodyText
            Write-Host "              to: $src"   -ForegroundColor $UI.BodyText
            if (-not (Test-Path $dest)) {
                Write-Msg -Role "warn" -Content "File no longer at destination."; return
            }
            Write-Host "   Confirm? (y/n): " -ForegroundColor $UI.WarnText -NoNewline
            if ((Read-Host).Trim().ToLower() -in @("y","yes")) {
                try {
                    Move-Item -Path $dest -Destination $src -Force
                    Write-Msg -Role "ok" -Content "Undone — moved back to temp."
                    Write-ActionLog "UNDO FILE_PLACE — $dest -> $src"
                } catch { Write-Msg -Role "error" -Content "Undo failed: $($_.Exception.Message)" }
            } else { Write-Msg -Role "system" -Content "Undo cancelled." }
        }

        "CODE_EXEC" {
            Write-Host "   Code execution cannot be automatically reversed." -ForegroundColor $UI.DimText
            Write-Host "   Here is what ran:" -ForegroundColor $UI.DimText; Write-Host ""
            $last.data.code -split "`n" | ForEach-Object { Write-Host "   $_" -ForegroundColor Cyan }
            Write-Host ""; Write-ThinDivider
            Write-Msg -Role "warn" -Content "Review the code above and manually reverse its effects if needed."
            Write-ActionLog "UNDO CODE_EXEC requested — shown to user, not reversible"
        }
    }
}


# ================================================================
#  PHASE 6 — AUTO MEMORY + TEMP CLEANUP + SESSION STATS
# ================================================================

function Invoke-AutoMemory {
    $s = Get-Settings
    if (-not $s -or -not $s.auto_memory)  { return }
    if (-not $State.ActiveProfile)         { return }
    if ($State.AICallCount -eq 0)          { return }

    Write-Msg -Role "system" -Content "Auto-memory: summarizing session..."

    $summaryPrompt = "This AXON session is ending. Write a concise memory summary (under 200 words) covering: what the user worked on, files created or modified, code that ran, and any preferences worth remembering. Be factual and specific."
    $State.ChatHistory.Add(@{ role = "user"; content = $summaryPrompt }) | Out-Null

    try {
        $sp    = Build-SystemPrompt
        $reply = Invoke-AICall -UserMessage $summaryPrompt -SystemPrompt $sp -History $State.ChatHistory
        if ($reply) {
            $ts = Get-Date -Format "yyyy-MM-dd HH:mm"
            # Atomic memory write
            $memPath = "$DataFolder\memory.txt"
            $tmp     = "$memPath.tmp"
            Set-Content -Path $tmp -Value "[$ts — Session #$($State.SessionNumber)]`n$reply" -Encoding UTF8
            Move-Item -Path $tmp -Destination $memPath -Force
            Write-Msg -Role "ok" -Content "Memory saved for next session."
            Write-ActionLog "AUTO-MEMORY written — $($reply.Length) chars"
        }
    } catch {
        Write-ActionLog "AUTO-MEMORY failed: $($_.Exception.Message)"
    }
}

function Clear-TempFolder {
    $tempPath = "$DataFolder\temp"
    $cutoff   = (Get-Date).AddDays(-7)
    $old      = Get-ChildItem $tempPath -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt $cutoff }
    if ($old -and $old.Count -gt 0) {
        foreach ($f in $old) { try { Remove-Item $f.FullName -Force } catch {} }
        Write-ActionLog "TEMP CLEANUP — removed $($old.Count) old file(s)"
        Write-Msg -Role "system" -Content "Cleaned $($old.Count) old temp file(s) (>7 days)."
    }
}

function Show-SessionStats {
    $duration = [Math]::Round(((Get-Date) - $State.SessionStart).TotalMinutes, 1)
    Write-Host ""; Write-ThinDivider
    Write-Host "   Session #$($State.SessionNumber) Summary" -ForegroundColor $UI.Header
    Write-ThinDivider
    Write-Host ("   {0,-26} {1}" -f "Duration:",        "$duration min")           -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-26} {1}" -f "AI calls:",        $State.AICallCount)        -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-26} {1}" -f "Code executions:", $State.ExecutionCount)     -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-26} {1}" -f "Chat turns:",      $State.ChatHistory.Count)  -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-26} {1}" -f "Tasks completed:", "$(($State.Tasks | Where-Object {$_.status -eq 'done'}).Count)/$($State.Tasks.Count)") -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-26} {1}" -f "Undo stack:",      "$($State.UndoStack.Count) entries") -ForegroundColor $UI.BodyText
    if ($State.SessionLogPath) {
        Write-Host ("   {0,-26} {1}" -f "Log:", [System.IO.Path]::GetFileName($State.SessionLogPath)) -ForegroundColor $UI.DimText
    }
    Write-ThinDivider
}


function Invoke-MacroCommand {
    param([string]$Sub = "")
    $macroDir = "$DataFolder\macros"

    if ($Sub -eq "list" -or $Sub -eq "") {
        $macros = Get-ChildItem $macroDir -Filter "*.json" -ErrorAction SilentlyContinue
        Write-Host ""; Write-ThinDivider
        Write-Host "   Saved Macros" -ForegroundColor $UI.Header
        Write-ThinDivider
        if (-not $macros -or $macros.Count -eq 0) {
            Write-Host "   No macros saved yet. Ask the AI to save a macro." -ForegroundColor $UI.DimText
        } else {
            foreach ($f in $macros) {
                try {
                    $m = Get-Content $f.FullName -Raw | ConvertFrom-Json
                    Write-Host ("   {0,-20} {1}" -f $m.name, $m.steps) -ForegroundColor $UI.BodyText
                } catch {}
            }
        }
        Write-ThinDivider
        Write-Host "   /macro list           -> list saved macros" -ForegroundColor $UI.DimText
        Write-Host "   /macro delete [name]  -> delete a macro" -ForegroundColor $UI.DimText
        Write-ThinDivider
        return
    }

    if ($Sub -match '^delete\s+(.+)$') {
        $name = $Matches[1].Trim()
        $safe = $name -replace '[\\/:*?<>|]','_'
        $path = "$macroDir\$safe.json"
        if (Test-Path $path) {
            Remove-Item $path -Force
            Write-Msg -Role "ok" -Content "Macro '$name' deleted."
            Write-ActionLog "MACRO deleted: $name"
        } else {
            Write-Msg -Role "error" -Content "Macro '$name' not found."
        }
        return
    }

    Write-Msg -Role "system" -Content "Usage: /macro list  |  /macro delete [name]"
}


# ================================================================
#  v1.1 — INTENT CLASSIFIER (local routing — skips API for trivia)
# ================================================================

function Invoke-IntentClassifier {
    param([string]$Input)
    # Returns a string response if handled locally, $null if should go to AI

    $i = $Input.Trim().ToLower()

    # Greetings
    if ($i -match '^(hi|hello|hey|howdy|sup|yo|greetings|good morning|good evening|good afternoon)[\s!.]*$') {
        $greetings = @(
            "Hello! What can I help you with today?",
            "Hey! Ready when you are.",
            "Hi there — what would you like to do?",
            "Good to see you. What's on the agenda?"
        )
        return $greetings[(Get-Random -Maximum $greetings.Count)]
    }

    # Thanks
    if ($i -match '^(thanks|thank you|thx|ty|cheers|appreciate it|nice work|good job|great|awesome|perfect|cool)[\s!.]*$') {
        $thanks = @(
            "Happy to help!",
            "Anytime.",
            "Glad that worked out.",
            "Of course — let me know if you need anything else."
        )
        return $thanks[(Get-Random -Maximum $thanks.Count)]
    }

    # Version / what are you
    if ($i -match '\b(version|what version|which version|axon version)\b') {
        return "I am AXON v$AXON_VERSION — AI Agent Framework."
    }

    # Status questions
    if ($i -match '^(status|what.s the status|how are you|are you working|are you online|ping|pong)[\s?!.]*$') {
        $profile = if ($State.ActiveProfile) { "$($State.ActiveProfile.profile_name) ($($State.ActiveProfile.model))" } else { "no profile loaded" }
        return "AXON v$AXON_VERSION is running. Profile: $profile. AI calls this session: $($State.AICallCount). Use /status for the full dashboard."
    }

    # Help redirect
    if ($i -match '^(help|commands|what can you do|what are the commands|show commands)[\s?!.]*$') {
        Invoke-HelpCommand
        return "[HANDLED_LOCALLY]"
    }

    # Current time / date
    if ($i -match '\b(what.?s the time|current time|what time is it|what.?s today.?s date|today.?s date|what day is it|current date)\b') {
        $now = Get-Date
        return "Current date/time: $($now.ToString('dddd, MMMM d yyyy  HH:mm:ss'))"
    }

    # Disk/drive quick check
    if ($i -match '^(disk|disk space|storage|free space|drives?)\s*(space|info|status|check)?[\s?!.]*$') {
        try {
            $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | Where-Object { $_.Used -ne $null }
            $lines  = $drives | ForEach-Object {
                $used  = [Math]::Round($_.Used / 1GB, 1)
                $free  = [Math]::Round($_.Free / 1GB, 1)
                $total = [Math]::Round(($_.Used + $_.Free) / 1GB, 1)
                "$($_.Name):  $used GB used / $free GB free / $total GB total"
            }
            return "Disk space:`n" + ($lines -join "`n")
        } catch {
            return $null  # fall through to AI
        }
    }

    return $null  # Not handled locally — send to AI
}


# ================================================================
#  SLASH COMMAND ROUTER
# ================================================================

function Invoke-SlashCommand {
    param([string]$RawInput)

    $parts   = $RawInput.TrimStart("/").Split(" ", 2)
    $cmd     = $parts[0].ToLower().Trim()
    $subArgs = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }

    switch ($cmd) {
        # ── Core ──
        "help"     { Invoke-HelpCommand }
        "clear"    { Invoke-ClearCommand }
        "exit"     { Invoke-ExitCommand }
        "quit"     { Invoke-ExitCommand }

        # ── Safety ──
        "sandbox"  { Invoke-SandboxCommand }
        "brake"    { Invoke-BrakeCommand }
        "lock"     { Invoke-LockCommand  -Path $subArgs }
        "unlock"   { Invoke-UnlockCommand -Path $subArgs }

        # ── Profiles & Settings ──
        "profile"  { Invoke-ProfileCommand -Sub $subArgs }
        "settings" { Invoke-SettingsCommand }

        # ── v1.1 Session status ──
        "status"   { Invoke-StatusCommand }
        "last"     { Invoke-LastCommand }
        "recent"   { Invoke-RecentCommand }
        "context"  { Invoke-ContextCommand }

        "retry"    {
            $retryMsg = Invoke-RetryCommand
            if ($retryMsg -and $retryMsg -ne "") {
                # Return signal to main loop to re-send this as a user message
                $script:RETRY_MESSAGE = $retryMsg
            }
        }

        "fixlast"  {
            $fixMsg = Invoke-FixLastCommand
            if ($fixMsg) { $script:RETRY_MESSAGE = $fixMsg }
        }

        # ── v1.1 Tasks ──
        "tasks"    { Invoke-TasksCommand -Sub $subArgs }

        # ── v1.1 Approval queue ──
        "pending"  { Invoke-PendingCommand -Sub $subArgs }
        "approve"  {
            if ($subArgs -eq "all") { Invoke-ApproveAllCommand }
            else { Invoke-ApproveCommand }
        }
        "deny"     {
            if ($subArgs -eq "all") { Invoke-DenyAllCommand }
            else { Invoke-DenyCommand }
        }

        # ── Session & Files ──
        "memory"   { Invoke-MemoryCommand }
        "files"    { Invoke-FilesCommand }
        "temp"     { Invoke-TempCommand -Sub $subArgs }
        "log"      { Invoke-LogCommand }
        "logs"     {
            if ($subArgs -eq "clean") { Invoke-LogsCleanCommand }
            else { Invoke-LogCommand }
        }
        "peek"     { Invoke-PeekCommand -Path $subArgs }
        "open"     { Invoke-OpenCommand -Target $subArgs }
        "macro"    { Invoke-MacroCommand -Sub $subArgs }

        # ── History ──
        "history"  { Invoke-HistoryCommand -Sub $subArgs }

        # ── AI interaction ──
        "reload"   {
            if (-not $State.ActiveProfile) {
                Write-Msg -Role "error" -Content "No active profile to reload."
            } else {
                $State.ChatHistory.Clear()
                Write-Msg -Role "ok" -Content "Chat history cleared. AI will receive a fresh system prompt on your next message."
                Write-ActionLog "User triggered /reload — chat history cleared."
            }
        }

        "inject"   {
            if ([string]::IsNullOrWhiteSpace($subArgs)) {
                Write-Msg -Role "error" -Content "Usage: /inject [text to add to context]"
            } else {
                $State.ChatHistory.Add(@{ role = "user";      content = "[CONTEXT INJECTION]: $subArgs" }) | Out-Null
                $State.ChatHistory.Add(@{ role = "assistant"; content = "Understood. I have noted the injected context." }) | Out-Null
                Write-Msg -Role "ok" -Content "Context injected into chat history."
                Write-ActionLog "Context injected: $subArgs"
            }
        }

        "exec"     {
            if ($State.LastCodeBlock) {
                Write-Msg -Role "system" -Content "Re-running last code block..."
                $result = Invoke-CodeTag -Code $State.LastCodeBlock
                if ($result) {
                    $State.ChatHistory.Add(@{ role = "user";      content = "[AXON /exec] Last code block was re-run. Output:`n$result" }) | Out-Null
                    $State.ChatHistory.Add(@{ role = "assistant"; content = "Understood, I see the re-execution output." }) | Out-Null
                }
            } else {
                Write-Msg -Role "system" -Content "No code block has been executed yet this session."
            }
        }

        "undo"     { Invoke-UndoCommand }

        default {
            Write-Msg -Role "error" -Content "Unknown command: /$cmd  —  type /help to see all commands."
        }
    }
}


# ================================================================
#  INPUT LOOP
# ================================================================

function Read-UserInput {
    Write-Host ""
    Write-Footer
    Write-Host "  " -NoNewline
    $raw = Read-Host "You"
    return $raw.Trim()
}


# ================================================================
#  v1.1 — ERROR RECOVERY LOOP
# ================================================================

function Invoke-AIWithRecovery {
    param([string]$UserMessage, [string]$SystemPrompt)

    $maxRetries = 2
    $attempt    = 0

    while ($attempt -le $maxRetries) {
        $reply = Invoke-AICall `
            -UserMessage  $UserMessage `
            -SystemPrompt $SystemPrompt `
            -History      $State.ChatHistory

        if ($reply) { return $reply }

        $attempt++
        if ($attempt -le $maxRetries) {
            Write-Msg -Role "warn" -Content "API call failed. Retrying ($attempt/$maxRetries)..."
            Start-Sleep -Seconds (2 * $attempt)

            # Remove the failed user message from history if it got added
            if ($State.ChatHistory.Count -gt 0 -and $State.ChatHistory[$State.ChatHistory.Count-1].role -eq "user") {
                $State.ChatHistory.RemoveAt($State.ChatHistory.Count - 1)
            }
        }
    }

    Write-Msg -Role "error" -Content "Could not reach the AI after $maxRetries retries. Check your connection and API key (/profile doctor)."
    Write-Msg -Role "system" -Content "Your message was not lost. Type it again when the API is available, or use /retry."
    return $null
}


# ================================================================
#  ENTRY POINT
# ================================================================

function Start-AXON {
    Show-Banner
    Initialize-DataFolder
    Load-ActiveProfile
    Load-SmartMemory
    Register-CoreFunctions
    Load-Plugins
    Initialize-SessionLog
    Write-ActionLog "SESSION STARTED — Session #$($State.SessionNumber)  ID: $SESSION_ID  v$AXON_VERSION"

    [Console]::Clear()
    Write-Header

    Write-Msg -Role "system" -Content "AXON v$AXON_VERSION initialized.  Mega Phase B active."
    Write-Msg -Role "system" -Content "Data folder: $DataFolder"
    if ($State.FunctionRegistry.Count -gt 0) {
        Write-Msg -Role "ok" -Content "$($State.FunctionRegistry.Count) functions registered."
    }

    # Run health check
    $healthIssues = Invoke-StartupHealthCheck

    if ($State.ActiveProfile) {
        Write-Msg -Role "ok" -Content "Profile loaded: $($State.ActiveProfile.profile_name)  ($($State.ActiveProfile.provider) / $($State.ActiveProfile.model))"
        Write-Msg -Role "system" -Content "Type anything to start talking to the AI."
    } else {
        Write-Msg -Role "warn" -Content "No profile loaded — use /profile new to create one."
    }

    Write-Msg -Role "system" -Content "Type / for quick command hints, or /help for full reference."
    Write-Host ""

    $script:RETRY_MESSAGE = $null

    while ($true) {

        # Handle /retry or /fixlast signal from slash router
        if ($script:RETRY_MESSAGE) {
            $userInput = $script:RETRY_MESSAGE
            $script:RETRY_MESSAGE = $null
        } else {
            $userInput = Read-UserInput
        }

        if ([string]::IsNullOrWhiteSpace($userInput)) { continue }

        if ($userInput -eq "/") {
            Show-SlashHints
            continue
        }

        if ($userInput.StartsWith("/")) {
            Invoke-SlashCommand -RawInput $userInput
            continue
        }

        # ── Regular message ──
        if (-not $State.ActiveProfile) {
            Write-Msg -Role "error" -Content "No active profile. Use /profile new first."
            continue
        }

        # ── v1.1: Intent classifier — handle locally if possible ──
        $localReply = Invoke-IntentClassifier -Input $userInput
        if ($localReply -eq "[HANDLED_LOCALLY]") { continue }
        if ($localReply) {
            Write-Msg -Role "user" -Content $userInput
            Write-Msg -Role "ai"   -Content $localReply
            Write-ActionLog "INTENT CLASSIFIED (local): $userInput"
            continue
        }

        # ── Send to AI ──
        Write-Msg -Role "user" -Content $userInput
        $State.LastUserInput = $userInput

        $systemPrompt = Build-SystemPrompt
        $State.ChatHistory.Add(@{ role = "user"; content = $userInput }) | Out-Null

        $reply = Invoke-AIWithRecovery -UserMessage $userInput -SystemPrompt $systemPrompt

        if ($reply) {
            $feedback = Invoke-ParseResponse -RawReply $reply

            if (-not [string]::IsNullOrWhiteSpace($feedback)) {
                $State.ChatHistory.Add(@{
                    role    = "user"
                    content = "[AXON EXECUTION FEEDBACK]`n$feedback"
                }) | Out-Null
                $State.ChatHistory.Add(@{
                    role    = "assistant"
                    content = "Understood. I have received the execution feedback."
                }) | Out-Null
            }

            Save-SessionLog
        }
    }
}

Start-AXON
