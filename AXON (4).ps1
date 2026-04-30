# ================================================================
#  AXON — AI Agent Framework
#  Phase 1: TUI Shell + Slash Command Router
#  Phase 2: Profile System + API Caller
#  Phase 3: System Prompt Engine + Script Snapshot
#  Phase 4: Tag Parser + Execution Engine
#  Phase 5: Session History + Undo System
#  Phase 6: Data Folder Management + Logger + Memory Polish
#  Phase 7: Full Wiring — Exit Chain, Session Log, Undo, AICallCount
#  Phase 8: Deferred Approval Engine + Confirm Mode Controls
#  Phase 9: Atomic Persistence + Startup Health Checks
#  Phase 10: Quality-of-Life Commands + Context/Recovery UX
#  Version: 0.10.0
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

$AXON_VERSION  = "0.10.0"
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
    SessionStart         = Get-Date
    ExecutionCount       = 0
    ExecutionWindowStart = Get-Date
    # Phase 5 — undo + session
    UndoStack            = [System.Collections.ArrayList]@()
    MessageCount         = 0
    SessionLogPath       = $null
    AICallCount          = 0
    StartupHealth        = $null
    LastAIRawReply       = $null
    LastAIError          = $null
    LastFailedUserMessage = $null
    LastFailedAt         = $null
    LastContextNote      = $null
    PendingApprovedCount = 0
    PendingDeniedCount   = 0
    BlockedActionCount   = 0
    LastHistoryLoaded    = $null
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

    Write-Divider
    Write-Host "  $AXON_NAME  •  $profileLabel  •  $sessionLabel$sandboxTag" -ForegroundColor $UI.Header
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
        "system"  { Write-Host "  ●   " -ForegroundColor $UI.SysLabel   -NoNewline; Write-Host $Content -ForegroundColor $UI.SysText }
        "ok"      { Write-Host "  ✓   " -ForegroundColor Green          -NoNewline; Write-Host $Content -ForegroundColor $UI.OkText }
        "error"   { Write-Host "  ✗   " -ForegroundColor Red            -NoNewline; Write-Host $Content -ForegroundColor $UI.ErrText }
        "warn"    { Write-Host "  ⚠   " -ForegroundColor Yellow         -NoNewline; Write-Host $Content -ForegroundColor $UI.WarnText }
        "pending" { Write-Host "  ⏳  " -ForegroundColor Magenta        -NoNewline; Write-Host $Content -ForegroundColor $UI.PendText }
    }
}

function Show-Banner {
    [Console]::Clear()
    $w = Get-WindowWidth
    $pad = " " * ([Math]::Max(([int](($w - 26) / 2)), 0))

    Write-Host ""
    Write-Host "${pad}╔══════════════════════════╗" -ForegroundColor Cyan
    Write-Host "${pad}║                          ║" -ForegroundColor Cyan
    Write-Host "${pad}║   A  X  O  N   v0.10    ║" -ForegroundColor Cyan
    Write-Host "${pad}║                          ║" -ForegroundColor Cyan
    Write-Host "${pad}╚══════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "${pad}  AI Agent Framework" -ForegroundColor DarkGray
    Write-Host "${pad}  Pure PowerShell. No dependencies." -ForegroundColor DarkGray
    Write-Host ""
    Start-Sleep -Milliseconds 1400
}

function Show-SlashHints {
    $hints = @("/help","/status","/pending","/context","/recent","/health","/profile","/history","/retry","/exit")
    Write-Host ""
    Write-Host "  Commands: " -ForegroundColor $UI.DimText -NoNewline
    Write-Host ($hints -join "   ") -ForegroundColor $UI.CmdHint
    Write-Host ""
}


# ================================================================
#  FILE IO + INTEGRITY HELPERS
# ================================================================

function Write-TextFileAtomic {
    param(
        [string]$Path,
        [string]$Content
    )

    $tmpPath = $null
    try {
        $dir = [System.IO.Path]::GetDirectoryName($Path)
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $tmpPath = "$Path.tmp.$([guid]::NewGuid().ToString('N'))"
        Set-Content -LiteralPath $tmpPath -Value $Content -Encoding UTF8
        Move-Item -LiteralPath $tmpPath -Destination $Path -Force
        return $true
    } catch {
        if ($tmpPath -and (Test-Path -LiteralPath $tmpPath)) {
            try { Remove-Item -LiteralPath $tmpPath -Force } catch {}
        }
        throw
    }
}

function Write-JsonFileAtomic {
    param(
        [string]$Path,
        $Data,
        [int]$Depth = 10
    )
    $json = $Data | ConvertTo-Json -Depth $Depth
    return (Write-TextFileAtomic -Path $Path -Content $json)
}

function Move-ToQuarantine {
    param(
        [string]$Path,
        [string]$QuarantineFolder
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    if (-not (Test-Path -LiteralPath $QuarantineFolder)) {
        New-Item -ItemType Directory -Path $QuarantineFolder -Force | Out-Null
    }

    $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext  = [System.IO.Path]::GetExtension($Path)
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $dest = Join-Path $QuarantineFolder "$base.corrupt.$stamp$ext"
    Move-Item -LiteralPath $Path -Destination $dest -Force
    return $dest
}

function Read-JsonFileSafe {
    param(
        [string]$Path,
        [switch]$BackupOnError,
        [string]$QuarantineFolder = ""
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        if ($BackupOnError) {
            try {
                if ($QuarantineFolder) {
                    Move-ToQuarantine -Path $Path -QuarantineFolder $QuarantineFolder | Out-Null
                } else {
                    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
                    Move-Item -LiteralPath $Path -Destination "$Path.corrupt.$stamp" -Force
                }
            } catch {}
        }
        return $null
    }
}

function Get-DefaultSettingsObject {
    return [ordered]@{
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
        confirmation_mode         = "deferred"
        pending_timeout_minutes   = 20
        auto_memory               = $true
        streaming                 = $false
    }
}

function Normalize-SettingsObject {
    param($Settings)

    $defaults = Get-DefaultSettingsObject
    if (-not $Settings) { return $defaults }

    $blockedDefault = @($defaults.blocked_paths)
    $blockedRaw = @($Settings.blocked_paths)
    $userBlockedRaw = @($Settings.user_blocked_paths)
    $blocked = @($blockedRaw | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $userBlocked = @($userBlockedRaw | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (-not $blocked -or $blocked.Count -eq 0) { $blocked = $blockedDefault }

    $maxExec = 5
    if ($null -ne $Settings.max_executions_per_minute) {
        try {
            $parsed = [int]$Settings.max_executions_per_minute
            if ($parsed -gt 0 -and $parsed -le 1000) { $maxExec = $parsed }
        } catch {}
    }

    $dryRun = $defaults.dry_run_before_execute
    try {
        if ($null -ne $Settings.dry_run_before_execute) {
            $dryRun = [System.Convert]::ToBoolean($Settings.dry_run_before_execute)
        }
    } catch {}

    $autoMemory = $defaults.auto_memory
    try {
        if ($null -ne $Settings.auto_memory) {
            $autoMemory = [System.Convert]::ToBoolean($Settings.auto_memory)
        }
    } catch {}

    $streaming = $defaults.streaming
    try {
        if ($null -ne $Settings.streaming) {
            $streaming = [System.Convert]::ToBoolean($Settings.streaming)
        }
    } catch {}

    $confirmMode = if ($Settings.confirmation_mode) { ([string]$Settings.confirmation_mode).ToLower() } else { "deferred" }
    if ($confirmMode -notin @("inline","deferred")) { $confirmMode = "deferred" }

    $pendingTimeout = 20
    if ($null -ne $Settings.pending_timeout_minutes) {
        try {
            $pt = [int]$Settings.pending_timeout_minutes
            if ($pt -ge 1 -and $pt -le 1440) { $pendingTimeout = $pt }
        } catch {}
    }

    return [ordered]@{
        active_profile            = if ($Settings.active_profile) { [string]$Settings.active_profile } else { $null }
        script_name               = if ($Settings.script_name) { [string]$Settings.script_name } else { "AXON" }
        blocked_paths             = $blocked
        user_blocked_paths        = $userBlocked
        max_executions_per_minute = $maxExec
        dry_run_before_execute    = $dryRun
        confirmation_mode         = $confirmMode
        pending_timeout_minutes   = $pendingTimeout
        auto_memory               = $autoMemory
        streaming                 = $streaming
    }
}

function Save-Settings {
    param($Settings)
    $normalized = Normalize-SettingsObject -Settings $Settings
    Write-JsonFileAtomic -Path "$DataFolder\settings.json" -Data $normalized -Depth 10 | Out-Null
    return [pscustomobject]$normalized
}

function Test-ProfileObject {
    param($Profile)
    if (-not $Profile) { return $false }
    if (-not $Profile.profile_name -or -not $Profile.provider -or -not $Profile.model) { return $false }
    if ([string]::IsNullOrWhiteSpace([string]$Profile.profile_name)) { return $false }
    if ([string]::IsNullOrWhiteSpace([string]$Profile.provider)) { return $false }
    if ([string]::IsNullOrWhiteSpace([string]$Profile.model)) { return $false }
    return $true
}

function Get-ProfileFromFile {
    param([string]$Path)
    $profile = Read-JsonFileSafe -Path $Path
    if (-not (Test-ProfileObject -Profile $profile)) { return $null }
    return $profile
}

function Initialize-DataFolder {
    $dirs = @(
        $DataFolder,
        "$DataFolder\profiles",
        "$DataFolder\sessions",
        "$DataFolder\temp",
        "$DataFolder\workspace",
        "$DataFolder\logs"
    )
    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
    }

    # Default settings
    $settingsPath = "$DataFolder\settings.json"
    if (-not (Test-Path $settingsPath)) {
        Write-JsonFileAtomic -Path $settingsPath -Data (Get-DefaultSettingsObject) -Depth 10 | Out-Null
    }

    # Default memory
    $memPath = "$DataFolder\memory.txt"
    if (-not (Test-Path $memPath)) {
        Write-TextFileAtomic -Path $memPath -Content "No previous memory." | Out-Null
    }

    # Session counter
    $sessions = Get-ChildItem "$DataFolder\sessions" -Filter "*.json" -ErrorAction SilentlyContinue
    $State.SessionNumber = ($sessions.Count) + 1
}

function Get-Settings {
    $p = "$DataFolder\settings.json"
    if (-not (Test-Path -LiteralPath $p)) {
        return (Save-Settings -Settings (Get-DefaultSettingsObject))
    }

    $settings = Read-JsonFileSafe -Path $p -BackupOnError -QuarantineFolder "$DataFolder\quarantine\settings"
    if (-not $settings) {
        return (Save-Settings -Settings (Get-DefaultSettingsObject))
    }

    $normalized = Normalize-SettingsObject -Settings $settings
    $rawJson = $settings | ConvertTo-Json -Depth 10 -Compress
    $normJson = $normalized | ConvertTo-Json -Depth 10 -Compress
    if ($rawJson -ne $normJson) {
        return (Save-Settings -Settings $normalized)
    }
    return [pscustomobject]$normalized
}

function Write-ActionLog {
    param([string]$Entry)
    try {
        $logPath = "$DataFolder\logs\actions.log"
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        if (-not (Test-Path -LiteralPath (Split-Path $logPath -Parent))) {
            New-Item -ItemType Directory -Path (Split-Path $logPath -Parent) -Force | Out-Null
        }
        Add-Content -Path $logPath -Value "[$timestamp]  $Entry" -Encoding UTF8
    } catch {}
}

function Set-LastErrorState {
    param(
        [string]$Source,
        [string]$Message
    )
    $State.LastAIError = @{
        source = $Source
        message = $Message
        at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }
}

function Clear-LastErrorState {
    $State.LastAIError = $null
}

function Get-PendingTimeoutMinutes {
    $s = Get-Settings
    if ($s -and $s.pending_timeout_minutes) {
        try {
            $pt = [int]$s.pending_timeout_minutes
            if ($pt -ge 1 -and $pt -le 1440) { return $pt }
        } catch {}
    }
    return 20
}

function Test-PendingActionExpired {
    if (-not $State.PendingAction) { return $false }
    if (-not $State.PendingAction.expires_at) { return $false }
    try {
        $expiry = [datetime]$State.PendingAction.expires_at
        if ((Get-Date) -gt $expiry) { return $true }
    } catch {}
    return $false
}

function Invoke-StartupHealthCheck {
    $report = [ordered]@{
        warnings = [System.Collections.ArrayList]@()
        repairs  = [System.Collections.ArrayList]@()
    }

    $quarantineRoot = "$DataFolder\quarantine"
    $profileQuarantine = "$quarantineRoot\profiles"
    $sessionQuarantine = "$quarantineRoot\sessions"

    # Remove stale temp files left from interrupted atomic writes.
    $staleTmp = Get-ChildItem -Path $DataFolder -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "*.tmp.*" }
    if ($staleTmp -and $staleTmp.Count -gt 0) {
        foreach ($f in $staleTmp) { try { Remove-Item -LiteralPath $f.FullName -Force } catch {} }
        $report.repairs.Add("Removed $($staleTmp.Count) stale temp file(s).") | Out-Null
    }

    # Ensure settings are readable and normalized.
    $settingsPath = "$DataFolder\settings.json"
    $settingsBefore = Read-JsonFileSafe -Path $settingsPath -BackupOnError -QuarantineFolder "$quarantineRoot\settings"
    if (-not $settingsBefore) {
        Save-Settings -Settings (Get-DefaultSettingsObject) | Out-Null
        $report.repairs.Add("Recreated settings.json from defaults.") | Out-Null
    } else {
        $raw = $settingsBefore | ConvertTo-Json -Depth 10 -Compress
        $normObj = Normalize-SettingsObject -Settings $settingsBefore
        $norm = $normObj | ConvertTo-Json -Depth 10 -Compress
        if ($raw -ne $norm) {
            Save-Settings -Settings $normObj | Out-Null
            $report.repairs.Add("Normalized settings.json schema.") | Out-Null
        }
    }

    # Validate profiles and quarantine broken JSON/profile objects.
    $profileFiles = Get-ChildItem "$DataFolder\profiles" -Filter "*.json" -ErrorAction SilentlyContinue
    $invalidProfiles = 0
    foreach ($pf in $profileFiles) {
        $profile = Read-JsonFileSafe -Path $pf.FullName
        if (-not (Test-ProfileObject -Profile $profile)) {
            try {
                Move-ToQuarantine -Path $pf.FullName -QuarantineFolder $profileQuarantine | Out-Null
                $invalidProfiles++
            } catch {}
        }
    }
    if ($invalidProfiles -gt 0) {
        $report.repairs.Add("Quarantined $invalidProfiles invalid profile file(s).") | Out-Null
    }

    # Validate session logs and quarantine unreadable logs.
    $sessionFiles = Get-ChildItem "$DataFolder\sessions" -Filter "*.json" -ErrorAction SilentlyContinue
    $invalidSessions = 0
    foreach ($sf in $sessionFiles) {
        $session = Read-JsonFileSafe -Path $sf.FullName
        if (-not $session) {
            try {
                Move-ToQuarantine -Path $sf.FullName -QuarantineFolder $sessionQuarantine | Out-Null
                $invalidSessions++
            } catch {}
            continue
        }
    }
    if ($invalidSessions -gt 0) {
        $report.repairs.Add("Quarantined $invalidSessions unreadable session log(s).") | Out-Null
    }

    # Active profile integrity check.
    $settings = Get-Settings
    if ($settings -and $settings.active_profile) {
        $profiles = Get-ChildItem "$DataFolder\profiles" -Filter "*.json" -ErrorAction SilentlyContinue
        $exists = $false
        foreach ($pf in $profiles) {
            $profile = Get-ProfileFromFile -Path $pf.FullName
            if ($profile -and $profile.profile_name -eq $settings.active_profile) {
                $exists = $true
                break
            }
        }
        if (-not $exists) {
            $settings.active_profile = $null
            Save-Settings -Settings $settings | Out-Null
            $report.repairs.Add("Cleared missing active_profile reference.") | Out-Null
        }
    }

    # Ensure action log exists.
    $actionLogPath = "$DataFolder\logs\actions.log"
    if (-not (Test-Path -LiteralPath $actionLogPath)) {
        Write-TextFileAtomic -Path $actionLogPath -Content "" | Out-Null
        $report.repairs.Add("Created missing actions.log.") | Out-Null
    }

    return $report
}


# ================================================================
#  COMMAND HANDLERS
# ================================================================

function Invoke-HelpCommand {
    Write-Host ""
    Write-ThinDivider
    Write-Host "   $AXON_NAME  —  Command Reference" -ForegroundColor $UI.Header
    Write-ThinDivider

    $sections = [ordered]@{
        "NAVIGATION" = @(
            @{cmd="/help";           desc="Show this command reference"},
            @{cmd="/status";         desc="Show live AXON status summary"},
            @{cmd="/clear";          desc="Clear the chat display (context preserved)"},
            @{cmd="/exit";           desc="Close AXON cleanly"}
        )
        "AI & PROFILES" = @(
            @{cmd="/profile";        desc="View or switch active profile"},
            @{cmd="/profile new";    desc="Create a new AI provider profile"},
            @{cmd="/profile delete"; desc="Remove a profile"},
            @{cmd="/profile test [name]"; desc="Test profile connectivity with a tiny call"},
            @{cmd="/profile doctor"; desc="Validate profile file integrity and fields"},
            @{cmd="/reload [soft|hard]"; desc="Clear context (hard also clears notes/pending)"},
            @{cmd="/inject [text]";  desc="Alias for /context note [text]"}
        )
        "SESSION" = @(
            @{cmd="/history";        desc="Browse past sessions"},
            @{cmd="/history search [text]"; desc="Search across saved sessions"},
            @{cmd="/history resume [n]"; desc="Resume session #n into current context"},
            @{cmd="/context";        desc="Show chat-context stats"},
            @{cmd="/context trim [n]"; desc="Keep only last n turns in context"},
            @{cmd="/context note [text]"; desc="Add durable context note"},
            @{cmd="/recent [n]";     desc="Show recent actions and turns"},
            @{cmd="/last";           desc="Show last raw AI reply (with tags)"},
            @{cmd="/retry";          desc="Retry the last failed AI call"},
            @{cmd="/fixlast";        desc="Ask AI to fix last failure using structured context"},
            @{cmd="/log";            desc="View this session's action log"},
            @{cmd="/memory";         desc="View the AI's memory from last session"},
            @{cmd="/health";         desc="Show startup health-check report"}
        )
        "FILES & EXECUTION" = @(
            @{cmd="/files";          desc="Browse Data folder contents"},
            @{cmd="/open [temp|workspace|logs|sessions|data]"; desc="Open AXON folders in Explorer"},
            @{cmd="/peek [path]";    desc="Preview a file before AI touches it"},
            @{cmd="/exec";           desc="Re-run the last code block"},
            @{cmd="/pending";        desc="Inspect pending action details"},
            @{cmd="/approve";        desc="Execute the currently pending action"},
            @{cmd="/deny";           desc="Reject and clear pending action"},
            @{cmd="/undo";           desc="Attempt to reverse last action"},
            @{cmd="/temp";           desc="Show files waiting in temp/ for approval"}
        )
        "SAFETY" = @(
            @{cmd="/sandbox";        desc="Toggle sandbox mode — simulates everything, runs nothing"},
            @{cmd="/lock [path]";    desc="Add a path to your personal blocklist"},
            @{cmd="/unlock [path]";  desc="Remove a path from your blocklist"},
            @{cmd="/brake";          desc="!! EMERGENCY STOP — halts all running jobs immediately !!"}
        )
        "SETTINGS" = @(
            @{cmd="/settings";       desc="Open the settings menu"},
            @{cmd="/confirmmode [inline|deferred]"; desc="Set how confirmations are handled"}
        )
    }

    foreach ($section in $sections.Keys) {
        Write-Host ""
        Write-Host "   $section" -ForegroundColor $UI.DimText
        foreach ($item in $sections[$section]) {
            Write-Host ("   {0,-28} {1}" -f $item.cmd, $item.desc) -ForegroundColor $UI.BodyText
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

    # Auto-memory: ask the AI to summarize the session for next time
    Invoke-AutoMemory

    # Persist the session log one final time with ended_at + final counts
    Save-SessionLog

    # Clean up old temp files (>7 days)
    Clear-TempFolder

    # Show session stats before closing
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

    try {
        Get-Job | Stop-Job  -ErrorAction SilentlyContinue
        Get-Job | Remove-Job -ErrorAction SilentlyContinue
    } catch {}

    Write-Msg -Role "system" -Content "All jobs stopped. Pending actions cleared. System is idle."
    Write-ActionLog "!! EMERGENCY BRAKE ACTIVATED !!"
}

function Invoke-ProfileCommand {
    param([string]$Sub = "")
    $subTrim = $Sub.Trim()
    if ([string]::IsNullOrWhiteSpace($subTrim)) {
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
                $d = Get-ProfileFromFile -Path $pf.FullName
                if (-not $d) {
                    Write-Host ("   [{0}] {1}" -f $i, "$($pf.Name)  (invalid profile)") -ForegroundColor $UI.DimText
                    $i++
                    continue
                }
                $active = if ($State.ActiveProfile -and
                              $State.ActiveProfile.profile_name -eq $d.profile_name) { "  ◄ active" } else { "" }
                Write-Host ("   [{0}] {1,-24} {2} / {3}{4}" -f $i, $d.profile_name, $d.provider, $d.model, $active) -ForegroundColor $UI.BodyText
                $i++
            }
            Write-Host ""
            Write-Host "   /profile [name]       → switch to a profile" -ForegroundColor $UI.DimText
            Write-Host "   /profile new          → create a new profile" -ForegroundColor $UI.DimText
            Write-Host "   /profile delete       → remove a profile" -ForegroundColor $UI.DimText
            Write-Host "   /profile test [name]  → test profile connectivity" -ForegroundColor $UI.DimText
            Write-Host "   /profile doctor       → validate profile health" -ForegroundColor $UI.DimText
        }
        Write-ThinDivider
        return
    }

    $parts = $subTrim.Split(" ", 2)
    $verb = $parts[0].ToLower()
    $arg  = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }

    switch ($verb) {
        "new"    { New-Profile; return }
        "delete" { Remove-Profile; return }
        "doctor" { Invoke-ProfileDoctorCommand; return }
        "test"   { Invoke-ProfileTestCommand -Name $arg; return }
        default  { Switch-Profile -Name $subTrim; return }
    }
}

function New-Profile {
    Write-Host ""
    Write-ThinDivider
    Write-Host "   New Profile — Setup" -ForegroundColor $UI.Header
    Write-ThinDivider
    Write-Host ""

    # Profile name
    Write-Host "   Profile name (e.g. Claude Work): " -ForegroundColor $UI.BodyText -NoNewline
    $profileName = (Read-Host).Trim()
    if ([string]::IsNullOrWhiteSpace($profileName)) {
        Write-Msg -Role "error" -Content "Profile name cannot be empty."
        return
    }

    # Sanitize for filename
    $safeFileName = ($profileName -replace '[\\/:*?"<>|]', '_')
    $profilePath  = "$DataFolder\profiles\$safeFileName.json"
    if (Test-Path $profilePath) {
        Write-Msg -Role "error" -Content "A profile with that name already exists."
        return
    }

    # Provider selection
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
        "1" = @{ name="anthropic"; url="https://api.anthropic.com/v1/messages";    defaultModel="claude-sonnet-4-20250514" }
        "2" = @{ name="openai";    url="https://api.openai.com/v1/chat/completions"; defaultModel="gpt-4o" }
        "3" = @{ name="groq";      url="https://api.groq.com/openai/v1/chat/completions"; defaultModel="llama-3.3-70b-versatile" }
        "4" = @{ name="ollama";    url="http://localhost:11434/api/chat";           defaultModel="llama3" }
        "5" = @{ name="custom";    url="";                                          defaultModel="" }
    }

    if (-not $providerMap.ContainsKey($provChoice)) {
        Write-Msg -Role "error" -Content "Invalid choice."
        return
    }

    $provInfo = $providerMap[$provChoice]

    # Model
    Write-Host ""
    Write-Host "   Model [$($provInfo.defaultModel)]: " -ForegroundColor $UI.BodyText -NoNewline
    $modelInput = (Read-Host).Trim()
    $model = if ($modelInput -eq "") { $provInfo.defaultModel } else { $modelInput }

    # Custom URL if needed
    $apiUrl = $provInfo.url
    if ($provChoice -eq "5") {
        Write-Host "   API endpoint URL: " -ForegroundColor $UI.BodyText -NoNewline
        $apiUrl = (Read-Host).Trim()
    }

    # API key (skip for Ollama)
    $apiKey = ""
    if ($provInfo.name -ne "ollama") {
        Write-Host "   API key: " -ForegroundColor $UI.BodyText -NoNewline
        # Read as secure then convert — keeps it off screen history
        $secureKey = Read-Host -AsSecureString
        $apiKey    = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                         [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey))
    }

    # Max tokens
    Write-Host "   Max tokens [4096]: " -ForegroundColor $UI.BodyText -NoNewline
    $tokInput  = (Read-Host).Trim()
    $maxTokens = if ($tokInput -match '^\d+$') { [int]$tokInput } else { 4096 }

    # Temperature
    Write-Host "   Temperature [0.7]: " -ForegroundColor $UI.BodyText -NoNewline
    $tempInput = (Read-Host).Trim()
    $temp      = if ($tempInput -match '^\d*\.?\d+$') { [double]$tempInput } else { 0.7 }

    # Build profile object
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

    Write-JsonFileAtomic -Path $profilePath -Data $profile -Depth 10 | Out-Null

    Write-Host ""
    Write-Msg -Role "ok" -Content "Profile '$profileName' created."
    Write-ActionLog "Profile created: $profileName ($($provInfo.name) / $model)"

    # Offer to activate
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

    $match = $null
    foreach ($pf in $profiles) {
        $profile = Get-ProfileFromFile -Path $pf.FullName
        if ($profile -and $profile.profile_name -eq $Name) {
            $match = $pf
            break
        }
    }
    if (-not $match) {
        foreach ($pf in $profiles) {
            $profile = Get-ProfileFromFile -Path $pf.FullName
            if ($profile -and $profile.profile_name -like "*$Name*") {
                $match = $pf
                break
            }
        }
    }

    if (-not $match) {
        Write-Msg -Role "error" -Content "No profile found matching '$Name'."
        return
    }

    $profileData = Get-ProfileFromFile -Path $match.FullName
    if (-not $profileData) {
        Write-Msg -Role "error" -Content "Selected profile is invalid. Run startup health check."
        return
    }
    $State.ActiveProfile = $profileData

    # Save as active in settings
    $s = Get-Settings
    $s.active_profile = $profileData.profile_name
    Save-Settings -Settings $s | Out-Null

    # Refresh header
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
        $d = Get-ProfileFromFile -Path $pf.FullName
        if ($d) {
            Write-Host ("   [{0}] {1}" -f $i, $d.profile_name) -ForegroundColor $UI.BodyText
        } else {
            Write-Host ("   [{0}] {1}" -f $i, "$($pf.Name)  (invalid profile)") -ForegroundColor $UI.DimText
        }
        $i++
    }
    Write-Host ""
    Write-Host "   Profile name to delete (or blank to cancel): " -ForegroundColor $UI.WarnText -NoNewline
    $target = (Read-Host).Trim()
    if ([string]::IsNullOrWhiteSpace($target)) { Write-Msg -Role "system" -Content "Cancelled."; return }

    $match = $null
    foreach ($pf in $profiles) {
        $d = Get-ProfileFromFile -Path $pf.FullName
        if ($d -and $d.profile_name -eq $target) {
            $match = $pf
            break
        }
    }

    if (-not $match) { Write-Msg -Role "error" -Content "Profile not found."; return }

    Write-Host "   Confirm delete '$target'? (yes/no): " -ForegroundColor $UI.WarnText -NoNewline
    $confirm = (Read-Host).Trim().ToLower()
    if ($confirm -ne "yes") { Write-Msg -Role "system" -Content "Cancelled."; return }

    Remove-Item $match.FullName -Force
    if ($State.ActiveProfile -and $State.ActiveProfile.profile_name -eq $target) {
        $State.ActiveProfile = $null
        $s = Get-Settings
        $s.active_profile = $null
        Save-Settings -Settings $s | Out-Null
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

    $match = $null
    foreach ($pf in $profiles) {
        $d = Get-ProfileFromFile -Path $pf.FullName
        if ($d -and $d.profile_name -eq $s.active_profile) {
            $match = $d
            break
        }
    }

    if ($match) {
        $State.ActiveProfile = $match
    }
}


# ================================================================
#  API CALLER
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
    param($Profile, $Messages, $SystemPrompt)

    $provider = $Profile.provider

    if ($provider -eq "anthropic") {
        $body = @{
            model      = $Profile.model
            max_tokens = $Profile.max_tokens
            system     = $SystemPrompt
            messages   = $Messages
        }
        if ($Profile.temperature) { $body.temperature = $Profile.temperature }
        return $body
    }

    if ($provider -in @("openai","groq","custom")) {
        $msgs = [System.Collections.ArrayList]@()
        if ($SystemPrompt) {
            $msgs.Add(@{ role = "system"; content = $SystemPrompt }) | Out-Null
        }
        foreach ($m in $Messages) { $msgs.Add($m) | Out-Null }
        $body = @{
            model      = $Profile.model
            max_tokens = $Profile.max_tokens
            messages   = $msgs.ToArray()
        }
        if ($Profile.temperature) { $body.temperature = $Profile.temperature }
        return $body
    }

    if ($provider -eq "ollama") {
        return @{
            model    = $Profile.model
            messages = $Messages
            stream   = $false
        }
    }

    return $null
}

function Extract-ApiText {
    param($Response, [string]$Provider)

    try {
        switch ($Provider) {
            "anthropic" { return $Response.content[0].text }
            "openai"    { return $Response.choices[0].message.content }
            "groq"      { return $Response.choices[0].message.content }
            "ollama"    { return $Response.message.content }
            "custom"    {
                # Try OpenAI format first, then Anthropic format
                if ($Response.choices) { return $Response.choices[0].message.content }
                if ($Response.content) { return $Response.content[0].text }
                return $Response.ToString()
            }
        }
    } catch {
        return $null
    }
}

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

    # History already contains the user message added by the caller.
    # We pass history directly — just append assistant reply after.
    $messages = $History

    # Build headers
    $headerScript = $PROVIDER_HEADERS[$provider]
    $headers      = & $headerScript $profile

    # Build body
    $bodyObj  = Build-ApiBody -Profile $profile -Messages $messages.ToArray() -SystemPrompt $SystemPrompt
    if (-not $bodyObj) {
        Write-Msg -Role "error" -Content "Unknown provider: $provider"
        return $null
    }

    $bodyJson = $bodyObj | ConvertTo-Json -Depth 10

    # Send
    Write-Host ""
    Write-Host "  ◌ Thinking..." -ForegroundColor $UI.DimText -NoNewline

    try {
        $response = Invoke-RestMethod `
            -Uri     $profile.api_url `
            -Method  POST `
            -Headers $headers `
            -Body    ([System.Text.Encoding]::UTF8.GetBytes($bodyJson)) `
            -ContentType "application/json" `
            -ErrorAction Stop

        Write-Host "`r  ✓ Response received.   " -ForegroundColor $UI.DimText

        $text = Extract-ApiText -Response $response -Provider $provider

        if (-not $text) {
            Write-Msg -Role "error" -Content "Could not parse response from $provider."
            return $null
        }

        # Add assistant reply to history
        $History.Add(@{ role = "assistant"; content = $text }) | Out-Null

        Write-ActionLog "AI call — provider: $provider  model: $($profile.model)  chars: $($text.Length)"
        $State.AICallCount++
        $State.LastAIRawReply = $text
        $State.LastFailedUserMessage = $null
        $State.LastFailedAt = $null
        Clear-LastErrorState
        return $text

    } catch {
        Write-Host ""
        $errMsg = $_.Exception.Message
        # Try to extract API error detail
        try {
            $errBody = $_.ErrorDetails.Message | ConvertFrom-Json
            if ($errBody.error.message) { $errMsg = $errBody.error.message }
        } catch {}
        Write-Msg -Role "error" -Content "API call failed: $errMsg"
        Write-ActionLog "API call FAILED: $errMsg"
        Set-LastErrorState -Source "API_CALL" -Message $errMsg
        $State.LastFailedUserMessage = $UserMessage
        $State.LastFailedAt = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        # Remove the pre-added user message so history stays clean
        if ($History.Count -gt 0 -and $History[$History.Count-1].role -eq "user") {
            $History.RemoveAt($History.Count - 1)
        }
        return $null
    }
}

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

    $subFolders = @("profiles","sessions","temp","workspace","logs")
    foreach ($sub in $subFolders) {
        $path  = "$DataFolder\$sub"
        $items = Get-ChildItem $path -ErrorAction SilentlyContinue
        $count = if ($items) { $items.Count } else { 0 }
        Write-Host ("   📁 {0,-16} ({1} items)" -f "$sub/", $count) -ForegroundColor $UI.BodyText

        if ($count -gt 0 -and $count -le 6) {
            foreach ($item in $items) {
                Write-Host "      └─ $($item.Name)" -ForegroundColor $UI.DimText
            }
        } elseif ($count -gt 6) {
            Write-Host "      └─ ... and $count items" -ForegroundColor $UI.DimText
        }
    }

    # Root files
    $rootFiles = Get-ChildItem $DataFolder -File -ErrorAction SilentlyContinue
    if ($rootFiles) {
        Write-Host ""
        foreach ($f in $rootFiles) {
            Write-Host "   📄 $($f.Name)" -ForegroundColor $UI.DimText
        }
    }
    Write-ThinDivider
}

function Invoke-TempCommand {
    $tempPath = "$DataFolder\temp"
    $items    = Get-ChildItem $tempPath -ErrorAction SilentlyContinue
    Write-Host ""
    Write-ThinDivider
    Write-Host "   Temp — Files Awaiting Approval" -ForegroundColor $UI.Header
    Write-ThinDivider
    if (-not $items -or $items.Count -eq 0) {
        Write-Host "   No files waiting." -ForegroundColor $UI.DimText
    } else {
        foreach ($item in $items) {
            $size = [Math]::Round($item.Length / 1KB, 1)
            Write-Host ("   • {0,-30} {1} KB" -f $item.Name, $size) -ForegroundColor $UI.BodyText
        }
    }
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

function Invoke-HealthCommand {
    Write-Host ""
    Write-ThinDivider
    Write-Host "   Startup Health Report" -ForegroundColor $UI.Header
    Write-ThinDivider

    if (-not $State.StartupHealth) {
        Write-Host "   No startup health report is available in this session." -ForegroundColor $UI.DimText
        Write-ThinDivider
        return
    }

    $repairs = $State.StartupHealth.repairs
    $warnings = $State.StartupHealth.warnings
    $repairCount = if ($repairs) { $repairs.Count } else { 0 }
    $warningCount = if ($warnings) { $warnings.Count } else { 0 }

    Write-Host ("   {0,-16} {1}" -f "Repairs:",  $repairCount) -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-16} {1}" -f "Warnings:", $warningCount) -ForegroundColor $UI.BodyText

    if ($repairCount -gt 0) {
        Write-Host ""
        Write-Host "   Repairs applied:" -ForegroundColor $UI.DimText
        foreach ($r in $repairs) { Write-Host "   • $r" -ForegroundColor $UI.BodyText }
    }

    if ($warningCount -gt 0) {
        Write-Host ""
        Write-Host "   Warnings:" -ForegroundColor $UI.WarnText
        foreach ($w in $warnings) { Write-Host "   • $w" -ForegroundColor $UI.WarnText }
    }

    if ($repairCount -eq 0 -and $warningCount -eq 0) {
        Write-Host "   No issues found at startup." -ForegroundColor $UI.OkText
    }

    Write-ThinDivider
}

function Resolve-ProfileSelection {
    param([string]$Name = "")

    $profilesDir = "$DataFolder\profiles"
    $profiles = Get-ChildItem $profilesDir -Filter "*.json" -ErrorAction SilentlyContinue
    if (-not $profiles -or $profiles.Count -eq 0) { return $null }

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $State.ActiveProfile
    }

    foreach ($pf in $profiles) {
        $d = Get-ProfileFromFile -Path $pf.FullName
        if ($d -and $d.profile_name -eq $Name) { return $d }
    }
    foreach ($pf in $profiles) {
        $d = Get-ProfileFromFile -Path $pf.FullName
        if ($d -and $d.profile_name -like "*$Name*") { return $d }
    }

    return $null
}

function Invoke-ProfileDoctorCommand {
    $profilesDir = "$DataFolder\profiles"
    $profiles = Get-ChildItem $profilesDir -Filter "*.json" -ErrorAction SilentlyContinue

    Write-Host ""
    Write-ThinDivider
    Write-Host "   Profile Doctor" -ForegroundColor $UI.Header
    Write-ThinDivider

    if (-not $profiles -or $profiles.Count -eq 0) {
        Write-Host "   No profiles found." -ForegroundColor $UI.DimText
        Write-ThinDivider
        return
    }

    $ok = 0
    $warn = 0
    foreach ($pf in $profiles) {
        $p = Get-ProfileFromFile -Path $pf.FullName
        if (-not $p) {
            Write-Host "   ✗ $($pf.Name)  invalid profile JSON/schema" -ForegroundColor $UI.ErrText
            $warn++
            continue
        }

        $issues = [System.Collections.ArrayList]@()
        if (-not $p.api_url) { $issues.Add("missing api_url") | Out-Null }
        if ($p.provider -ne "ollama" -and [string]::IsNullOrWhiteSpace([string]$p.api_key)) { $issues.Add("missing api_key") | Out-Null }
        if (-not $p.max_tokens) { $issues.Add("missing max_tokens") | Out-Null }

        if ($issues.Count -eq 0) {
            Write-Host "   ✓ $($p.profile_name) ($($p.provider)/$($p.model))" -ForegroundColor $UI.OkText
            $ok++
        } else {
            Write-Host "   ⚠ $($p.profile_name) — $($issues -join ', ')" -ForegroundColor $UI.WarnText
            $warn++
        }
    }

    Write-Host ""
    Write-Host ("   Healthy: {0}   Issues: {1}" -f $ok, $warn) -ForegroundColor $UI.BodyText
    Write-ThinDivider
}

function Invoke-ProfileTestCommand {
    param([string]$Name = "")

    $profile = Resolve-ProfileSelection -Name $Name
    if (-not $profile) {
        Write-Msg -Role "error" -Content "Profile not found. Use /profile to list profiles."
        return
    }

    Write-Msg -Role "system" -Content "Testing profile '$($profile.profile_name)'..."
    $prev = $State.ActiveProfile
    $prevLastReply = $State.LastAIRawReply
    $prevLastError = $State.LastAIError
    $prevFailedMsg = $State.LastFailedUserMessage
    $prevFailedAt  = $State.LastFailedAt
    $State.ActiveProfile = $profile

    try {
        $hist = [System.Collections.ArrayList]@()
        $hist.Add(@{ role = "user"; content = "Reply with exactly: OK" }) | Out-Null
        $reply = Invoke-AICall -UserMessage "Reply with exactly: OK" -SystemPrompt "Connectivity test. Keep the answer to one token: OK." -History $hist
        if ($reply) {
            Write-Msg -Role "ok" -Content "Profile test succeeded. Reply: $reply"
        } else {
            Write-Msg -Role "error" -Content "Profile test failed."
        }
    } finally {
        $State.ActiveProfile = $prev
        $State.LastAIRawReply = $prevLastReply
        $State.LastAIError = $prevLastError
        $State.LastFailedUserMessage = $prevFailedMsg
        $State.LastFailedAt = $prevFailedAt
    }
}

function Invoke-StatusCommand {
    $s = Get-Settings
    $profileLabel = if ($State.ActiveProfile) { "$($State.ActiveProfile.profile_name) ($($State.ActiveProfile.provider)/$($State.ActiveProfile.model))" } else { "None" }
    $confirmMode = if ($s -and $s.confirmation_mode) { $s.confirmation_mode } else { "inline" }
    $pendingLabel = if ($State.PendingAction) { "$($State.PendingAction.type) — pending" } else { "None" }
    $windowAge = [Math]::Round(((Get-Date) - $State.ExecutionWindowStart).TotalSeconds, 0)

    Write-Host ""
    Write-ThinDivider
    Write-Host "   AXON Status" -ForegroundColor $UI.Header
    Write-ThinDivider
    Write-Host ("   {0,-28} {1}" -f "Version:", "v$AXON_VERSION") -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-28} {1}" -f "Session:", "#$($State.SessionNumber)  ($SESSION_ID)") -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-28} {1}" -f "Active profile:", $profileLabel) -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-28} {1}" -f "Sandbox mode:", $State.SandboxMode) -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-28} {1}" -f "Confirmation mode:", $confirmMode) -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-28} {1}" -f "Pending action:", $pendingLabel) -ForegroundColor $UI.BodyText
    if ($State.PendingAction -and $State.PendingAction.expires_at) {
        Write-Host ("   {0,-28} {1}" -f "Pending expires:", $State.PendingAction.expires_at) -ForegroundColor $UI.BodyText
    }
    Write-Host ("   {0,-28} {1}" -f "AI calls this session:", $State.AICallCount) -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-28} {1}" -f "Rate window usage:", "$($State.ExecutionCount) exec in $windowAge sec") -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-28} {1}" -f "Chat turns in context:", $State.ChatHistory.Count) -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-28} {1}" -f "Pending approved/denied:", "$($State.PendingApprovedCount)/$($State.PendingDeniedCount)") -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-28} {1}" -f "Blocked actions:", $State.BlockedActionCount) -ForegroundColor $UI.BodyText
    if ($State.LastAIError) {
        Write-Host ""
        Write-Host ("   Last error: [{0}] {1}" -f $State.LastAIError.source, $State.LastAIError.message) -ForegroundColor $UI.WarnText
        Write-Host ("   At: {0}" -f $State.LastAIError.at) -ForegroundColor $UI.DimText
    }
    Write-ThinDivider
}

function Invoke-PendingCommand {
    if (-not $State.PendingAction) {
        Write-Msg -Role "system" -Content "No pending action."
        return
    }

    if (Test-PendingActionExpired) {
        Write-Msg -Role "warn" -Content "Pending action expired and was cleared."
        Write-ActionLog "PENDING EXPIRED — $($State.PendingAction.type)"
        $State.PendingAction = $null
        $State.PendingDeniedCount++
        return
    }

    $p = $State.PendingAction
    Write-Host ""
    Write-ThinDivider
    Write-Host "   Pending Action" -ForegroundColor $UI.Header
    Write-ThinDivider
    Write-Host ("   {0,-16} {1}" -f "Type:", $p.type) -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-16} {1}" -f "Prompt:", $p.prompt) -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-16} {1}" -f "Created:", $p.created_at) -ForegroundColor $UI.BodyText
    Write-Host ("   {0,-16} {1}" -f "Expires:", $p.expires_at) -ForegroundColor $UI.BodyText
    if ($p.preview_lines -and $p.preview_lines.Count -gt 0) {
        Write-Host ""
        Write-Host "   Preview:" -ForegroundColor $UI.DimText
        foreach ($ln in $p.preview_lines) { Write-Host "   • $ln" -ForegroundColor $UI.BodyText }
    }
    Write-Host ""
    Write-Host "   Use /approve to execute, or /deny to cancel." -ForegroundColor $UI.DimText
    Write-ThinDivider
}

function Invoke-RecentCommand {
    param([string]$N = "6")
    $count = 6
    if ($N -match '^\d+$') { $count = [Math]::Min([Math]::Max([int]$N, 1), 50) }

    Write-Host ""
    Write-ThinDivider
    Write-Host "   Recent Activity" -ForegroundColor $UI.Header
    Write-ThinDivider

    $logPath = "$DataFolder\logs\actions.log"
    Write-Host "   Actions:" -ForegroundColor $UI.DimText
    if (Test-Path -LiteralPath $logPath) {
        $lines = Get-Content -LiteralPath $logPath -Tail $count -ErrorAction SilentlyContinue
        if ($lines) {
            foreach ($line in $lines) { Write-Host "   $line" -ForegroundColor $UI.BodyText }
        } else {
            Write-Host "   (none)" -ForegroundColor $UI.DimText
        }
    } else {
        Write-Host "   (log file missing)" -ForegroundColor $UI.DimText
    }

    Write-Host ""
    Write-Host "   Chat turns:" -ForegroundColor $UI.DimText
    $turns = $State.ChatHistory | Select-Object -Last $count
    if (-not $turns -or $turns.Count -eq 0) {
        Write-Host "   (none)" -ForegroundColor $UI.DimText
    } else {
        foreach ($t in $turns) {
            $label = if ($t.role -eq "user") { "You" } else { "AI " }
            $preview = [string]$t.content
            $preview = $preview -replace "`r"," " -replace "`n"," "
            if ($preview.Length -gt 100) { $preview = $preview.Substring(0,100) + "..." }
            Write-Host ("   [{0}] {1}" -f $label, $preview) -ForegroundColor $UI.BodyText
        }
    }
    Write-ThinDivider
}

function Invoke-LastCommand {
    if (-not $State.LastAIRawReply) {
        Write-Msg -Role "system" -Content "No AI reply captured yet."
        return
    }

    Write-Host ""
    Write-ThinDivider
    Write-Host "   Last AI Raw Reply (tags included)" -ForegroundColor $UI.Header
    Write-ThinDivider
    $lines = ([string]$State.LastAIRawReply) -split "`n"
    $max = 120
    $shown = [Math]::Min($lines.Count, $max)
    for ($i = 0; $i -lt $shown; $i++) {
        Write-Host ("   {0}" -f $lines[$i]) -ForegroundColor $UI.BodyText
    }
    if ($lines.Count -gt $shown) {
        Write-Host "   ... (truncated to first 120 lines)" -ForegroundColor $UI.DimText
    }
    Write-ThinDivider
}

function Invoke-ContextCommand {
    param([string]$Sub = "")

    if ([string]::IsNullOrWhiteSpace($Sub)) {
        $chars = 0
        foreach ($m in $State.ChatHistory) { $chars += ([string]$m.content).Length }

        Write-Host ""
        Write-ThinDivider
        Write-Host "   Context Overview" -ForegroundColor $UI.Header
        Write-ThinDivider
        Write-Host ("   {0,-24} {1}" -f "Turns:", $State.ChatHistory.Count) -ForegroundColor $UI.BodyText
        Write-Host ("   {0,-24} {1}" -f "Total characters:", $chars) -ForegroundColor $UI.BodyText
        Write-Host ("   {0,-24} {1}" -f "Last loaded history:", $(if($State.LastHistoryLoaded){$State.LastHistoryLoaded}else{"none"})) -ForegroundColor $UI.BodyText
        Write-Host ("   {0,-24} {1}" -f "Last context note:", $(if($State.LastContextNote){$State.LastContextNote}else{"none"})) -ForegroundColor $UI.BodyText
        Write-ThinDivider
        Write-Host "   /context trim [n]   /context note [text]" -ForegroundColor $UI.DimText
        Write-ThinDivider
        return
    }

    if ($Sub -match '^trim\s+(\d+)$') {
        $keep = [int]$Matches[1]
        if ($keep -lt 1) { Write-Msg -Role "error" -Content "Trim value must be >= 1."; return }
        if ($State.ChatHistory.Count -le $keep) {
            Write-Msg -Role "system" -Content "Context already within limit ($($State.ChatHistory.Count) turns)."
            return
        }
        $new = [System.Collections.ArrayList]@()
        foreach ($m in ($State.ChatHistory | Select-Object -Last $keep)) { $new.Add($m) | Out-Null }
        $State.ChatHistory = $new
        Write-Msg -Role "ok" -Content "Context trimmed to last $keep turns."
        Write-ActionLog "Context trimmed to $keep turns."
        Save-SessionLog
        return
    }

    if ($Sub -match '^note\s+(.+)$') {
        $note = $Matches[1].Trim()
        if ([string]::IsNullOrWhiteSpace($note)) { Write-Msg -Role "error" -Content "Note cannot be empty."; return }
        $State.ChatHistory.Add(@{ role = "user"; content = "[CONTEXT NOTE]: $note" }) | Out-Null
        $State.ChatHistory.Add(@{ role = "assistant"; content = "Context note acknowledged." }) | Out-Null
        $State.LastContextNote = $note
        Write-Msg -Role "ok" -Content "Context note added."
        Write-ActionLog "Context note added: $note"
        Save-SessionLog
        return
    }

    Write-Msg -Role "error" -Content "Usage: /context   |   /context trim [n]   |   /context note [text]"
}

function Invoke-OpenCommand {
    param([string]$Target = "")

    $map = @{
        "data" = $DataFolder
        "temp" = "$DataFolder\temp"
        "workspace" = "$DataFolder\workspace"
        "logs" = "$DataFolder\logs"
        "sessions" = "$DataFolder\sessions"
        "profiles" = "$DataFolder\profiles"
    }

    $key = if ($Target) { $Target.Trim().ToLower() } else { "data" }
    if (-not $map.ContainsKey($key)) {
        Write-Msg -Role "error" -Content "Usage: /open [data|temp|workspace|logs|sessions|profiles]"
        return
    }

    $path = $map[$key]
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Msg -Role "error" -Content "Path not found: $path"
        return
    }

    try {
        Start-Process explorer.exe -ArgumentList "`"$path`""
        Write-Msg -Role "ok" -Content "Opened: $path"
        Write-ActionLog "Opened folder: $path"
    } catch {
        Write-Msg -Role "error" -Content "Could not open folder: $($_.Exception.Message)"
    }
}

function Invoke-RetryCommand {
    if (-not $State.LastFailedUserMessage) {
        Write-Msg -Role "system" -Content "No failed AI call to retry."
        return
    }
    if (-not $State.ActiveProfile) {
        Write-Msg -Role "error" -Content "No active profile."
        return
    }

    Write-Msg -Role "system" -Content "Retrying last failed prompt..."
    Invoke-UserMessageFlow -UserInput $State.LastFailedUserMessage -Source "retry"
}

function Invoke-FixLastCommand {
    if (-not $State.LastFailedUserMessage -or -not $State.LastAIError) {
        Write-Msg -Role "system" -Content "No failure context available yet."
        return
    }

    $fixPrompt = @"
The previous AXON attempt failed.
Original user request:
$($State.LastFailedUserMessage)

Failure source: $($State.LastAIError.source)
Failure message: $($State.LastAIError.message)
Failure time: $($State.LastAIError.at)

Please propose a safer corrected approach and, if needed, provide compliant AXON tags.
"@

    Write-Msg -Role "system" -Content "Sending structured failure context to AI..."
    Invoke-UserMessageFlow -UserInput $fixPrompt -Source "fixlast" -ShowAsUser $false
}

function Invoke-SettingsCommand {
    Write-Host ""
    Write-ThinDivider
    Write-Host "   Settings" -ForegroundColor $UI.Header
    Write-ThinDivider
    $s = Get-Settings
    if ($s) {
        Write-Host ("   {0,-32} {1}" -f "Active profile:",       ($s.active_profile ?? "none"))         -ForegroundColor $UI.BodyText
        Write-Host ("   {0,-32} {1}" -f "Dry run before execute:", $s.dry_run_before_execute)            -ForegroundColor $UI.BodyText
        $confirmMode = if ($s.confirmation_mode) { $s.confirmation_mode } else { "inline" }
        Write-Host ("   {0,-32} {1}" -f "Confirmation mode:",     $confirmMode)                          -ForegroundColor $UI.BodyText
        Write-Host ("   {0,-32} {1}" -f "Pending timeout (min):",  $s.pending_timeout_minutes)             -ForegroundColor $UI.BodyText
        Write-Host ("   {0,-32} {1}" -f "Max executions/min:",    $s.max_executions_per_minute)         -ForegroundColor $UI.BodyText
        Write-Host ("   {0,-32} {1}" -f "Auto memory:",           $s.auto_memory)                       -ForegroundColor $UI.BodyText
        Write-Host ""
        Write-Host "   Blocked paths (hardcoded):" -ForegroundColor $UI.DimText
        foreach ($bp in $s.blocked_paths) {
            Write-Host "     🔴 $bp" -ForegroundColor $UI.DimText
        }
        if ($s.user_blocked_paths -and $s.user_blocked_paths.Count -gt 0) {
            Write-Host ""
            Write-Host "   Blocked paths (user-defined):" -ForegroundColor $UI.DimText
            foreach ($up in $s.user_blocked_paths) {
                Write-Host "     🔴 $up" -ForegroundColor $UI.DimText
            }
        }
        Write-Host ""
        Write-Host "   Use /profile new to add a profile." -ForegroundColor $UI.DimText
        Write-Host "   Use /lock [path] to add blocked paths." -ForegroundColor $UI.DimText
        Write-Host "   Use /confirmmode [inline|deferred] to choose approval style." -ForegroundColor $UI.DimText
    }
    Write-ThinDivider
}

function Invoke-ConfirmModeCommand {
    param([string]$Mode = "")

    $s = Get-Settings
    if (-not $s) {
        Write-Msg -Role "error" -Content "Settings not found."
        return
    }

    if ([string]::IsNullOrWhiteSpace($Mode)) {
        $current = if ($s.confirmation_mode) { $s.confirmation_mode } else { "inline" }
        Write-Msg -Role "system" -Content "Current confirmation mode: $current"
        Write-Msg -Role "system" -Content "Usage: /confirmmode inline   OR   /confirmmode deferred"
        return
    }

    $normalized = $Mode.Trim().ToLower()
    if ($normalized -notin @("inline","deferred")) {
        Write-Msg -Role "error" -Content "Invalid mode. Use: inline or deferred."
        return
    }

    $s.confirmation_mode = $normalized
    Save-Settings -Settings $s | Out-Null
    Write-Msg -Role "ok" -Content "Confirmation mode set to '$normalized'."
    Write-ActionLog "Confirmation mode changed to: $normalized"
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
        Save-Settings -Settings $s | Out-Null
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
        Save-Settings -Settings $s | Out-Null
        Write-Msg -Role "ok"  -Content "Unlocked: $Path"
        Write-ActionLog "User unlocked path: $Path"
    } else {
        Write-Msg -Role "warn" -Content "Path not found in your blocklist."
    }
}

function Invoke-PeekCommand {
    param([string]$Path)
    if (-not $Path) { Write-Msg -Role "error" -Content "Usage: /peek [filepath]"; return }
    if (-not (Test-Path $Path)) { Write-Msg -Role "error" -Content "File not found: $Path"; return }

    $item = Get-Item $Path
    Write-Host ""
    Write-ThinDivider
    Write-Host "   Peek: $($item.Name)  ($([Math]::Round($item.Length/1KB,1)) KB)" -ForegroundColor $UI.Header
    Write-ThinDivider

    try {
        $lines = Get-Content $Path -TotalCount 30 -ErrorAction Stop
        foreach ($line in $lines) { Write-Host "   $line" -ForegroundColor $UI.BodyText }
        if ((Get-Content $Path).Count -gt 30) {
            Write-Host "   ... (showing first 30 lines)" -ForegroundColor $UI.DimText
        }
    } catch {
        Write-Host "   Cannot preview this file type." -ForegroundColor $UI.DimText
    }
    Write-ThinDivider
}



# ================================================================
#  PHASE 3 — SCRIPT SNAPSHOT GENERATOR
# ================================================================

function Build-ScriptSnapshot {
    <#
    .SYNOPSIS
        Reads the live script file, strips the SAFETY_START/SAFETY_END block,
        and writes the sanitized copy to the Data folder.
        Returns the sanitized content as a string.
    #>
    $snapshotPath = "$DataFolder\script_snapshot.ps1"

    try {
        $selfPath = $PSCommandPath
        if (-not $selfPath -or -not (Test-Path $selfPath)) {
            # Fallback: try MyInvocation
            $selfPath = $MyInvocation.ScriptName
        }

        if (-not $selfPath -or -not (Test-Path $selfPath)) {
            $notice = "# [AXON] Script snapshot unavailable — could not locate source file."
            Write-TextFileAtomic -Path $snapshotPath -Content $notice | Out-Null
            return $notice
        }

        $lines      = Get-Content $selfPath
        $sanitized  = [System.Collections.ArrayList]@()
        $inSafety   = $false

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
        Write-TextFileAtomic -Path $snapshotPath -Content $content | Out-Null
        Write-ActionLog "Script snapshot generated — $($sanitized.Count) lines (safety block redacted)"
        return $content

    } catch {
        $notice = "# [AXON] Snapshot generation failed: $($_.Exception.Message)"
        Write-TextFileAtomic -Path $snapshotPath -Content $notice | Out-Null
        return $notice
    }
}


# ================================================================
#  PHASE 3 — SYSTEM PROMPT BUILDER
# ================================================================

function Build-SystemPrompt {
    <#
    .SYNOPSIS
        Assembles the full AXON Interface Document that is injected as the
        system prompt on every API call.  Includes:
          - Session identity & environment
          - Who the AI is and its role
          - Full tag protocol with examples
          - Confirmation tier rules
          - Data folder map
          - Capability and restriction list
          - Memory from the last session
          - Full sanitized script snapshot
    #>

    # ── Environment snapshot ──────────────────────────────────────
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

    # ── Memory ───────────────────────────────────────────────────
    $memPath  = "$DataFolder\memory.txt"
    $memory   = if (Test-Path $memPath) { Get-Content $memPath -Raw } else { "No previous memory." }

    # ── Script snapshot ──────────────────────────────────────────
    $snapshot = Build-ScriptSnapshot

    # ── Settings ─────────────────────────────────────────────────
    $s             = Get-Settings
    $blockedAll    = @()
    if ($s) {
        $blockedAll += $s.blocked_paths
        $blockedAll += $s.user_blocked_paths
    }
    $blockedList   = ($blockedAll | Where-Object { $_ }) -join "`n      "
    $maxExec       = if ($s) { $s.max_executions_per_minute } else { 5 }
    $dryRun        = if ($s) { $s.dry_run_before_execute } else { $true }
    $confirmMode   = if ($s -and $s.confirmation_mode) { $s.confirmation_mode } else { "inline" }
    $pendingTimeout= if ($s -and $s.pending_timeout_minutes) { $s.pending_timeout_minutes } else { 20 }

    # ── Assemble prompt ──────────────────────────────────────────
    $prompt = @"
╔══════════════════════════════════════════════════════════════════╗
  AXON — AI INTERFACE DOCUMENT  (injected fresh every API call)
╚══════════════════════════════════════════════════════════════════╝

SESSION IDENTITY
  Script name   : AXON v$AXON_VERSION
  Session ID    : $SESSION_ID
  Session #     : $($State.SessionNumber)
  Date / Time   : $sessionTime
  Active profile: $profileName  ($provider / $model)
  Sandbox mode  : $sandboxNote

ENVIRONMENT
  User          : $userName
  Computer      : $computerName
  OS            : $osCaption  (Build $osBuild)
  Current dir   : $currentDir
  Desktop       : $desktopPath
  Data folder   : $DataFolder

══════════════════════════════════════════════════════════════════

WHO YOU ARE
  You are the AI brain of AXON — an AI agent framework running
  inside the user's Windows machine through a PowerShell middleware
  script.  You are NOT a chatbot.  You are an intelligent agent
  with the ability to read files, create files, execute PowerShell
  code, and interact with the user's system — all via the tag
  protocol defined below.

  The PowerShell script is the MIDDLEMAN.  You are the BRAIN.
  The user is the AUTHORITY.  Nothing runs without their approval.

══════════════════════════════════════════════════════════════════

TAG PROTOCOL  (how you control AXON)

  Embed these tags anywhere in your response.  AXON's parser scans
  every reply and routes each tag to the correct engine.

  ┌─────────────────────────────────────────────────────────────┐
  │  TAG                      │ PURPOSE              │ TIER     │
  ├─────────────────────────────────────────────────────────────┤
  │ `$CODE$`...`$ENDCODE$`     │ Execute PowerShell   │ 🟡 Confirm│
  │ `$FILE:name.ext$`...`$ENDFILE$`│ Create a file   │ 🟡 Confirm│
  │ `$PLACE:C:\path\file.ext$`│ Move temp file out   │ 🟡 Confirm│
  │ `$READ:C:\path\file.ext$` │ Read file → context  │ 🟢 Auto  │
  │ `$CONFIRM:message$`       │ Ask user before act  │ 🟡 Always│
  │ `$WARN:message$`          │ Flag risk to user    │ 🟢 Display│
  │ `$MEMORY:content$`        │ Write to memory.txt  │ 🟢 Auto  │
  └─────────────────────────────────────────────────────────────┘

  TAG EXAMPLES:

  — Execute PowerShell:
      `$CODE$`
      Get-ChildItem C:\Users\$userName\Documents | Select-Object Name, Length
      `$ENDCODE$`

  — Create a file in the Data folder temp area:
      `$FILE:report.txt$`
      This is the content of the report.
      `$ENDFILE$`

  — Move that file to the Desktop (requires user approval):
      `$PLACE:$desktopPath\report.txt$`

  — Read a file into context:
      `$READ:$DataFolder\workspace\notes.txt$`

  — Ask user before doing something irreversible:
      `$CONFIRM:I am about to delete all files in the temp folder. Proceed?$`

  — Warn about something risky:
      `$WARN:The path you asked about is close to a system directory.$`

  — Write memory for next session:
      `$MEMORY:User is working on a Python project at C:\Projects\app. Prefers dark theme.$`

  IMPORTANT TAG RULES:
  1. Only one `$CODE$` block per response.  If you need multiple
     operations, chain them inside one block.
  2. All files you create go to the Data folder temp/ directory
     first.  Use `$PLACE$` to move them out with user approval.
  3. Never guess at paths.  Use `$READ$` to inspect before acting.
  4. Always use `$CONFIRM$` before any irreversible action
     (deleting, overwriting, moving system files).
  5. Use `$WARN$` if you detect anything suspicious or risky.
  6. Always use `$MEMORY$` at the end of sessions where something
     important happened that you want to remember.

══════════════════════════════════════════════════════════════════

CONFIRMATION TIERS

  🟢 AUTO     — Runs without asking.  Used for read-only actions
                and writing inside the Data folder.
  🟡 CONFIRM  — AXON shows the user a yes/no prompt before
                running.  Used for all writes, executions, and
                file placements.
  🔴 BLOCK    — Silently rejected.  Never reaches execution.
                Used for blocked paths and dangerous operations.

══════════════════════════════════════════════════════════════════

DATA FOLDER  —  YOUR HOME BASE
  $DataFolder\
    profiles\      → AI provider profiles (read-only to you)
    sessions\      → Past chat logs
    temp\          → YOUR staging area.  Create files here freely.
    workspace\     → Files you are actively reading or editing.
    logs\          → Action log (read-only to you)
    memory.txt     → Your notes from last session (you can write this)
    settings.json  → User settings (read-only to you)
    script_snapshot.ps1 → This sanitized copy of AXON

  RULES for the Data folder:
  ✅ Full read/write inside temp\ and workspace\
  ✅ Write memory.txt via `$MEMORY$` tag
  🔴 Cannot delete or rename the Data folder itself
  🔴 Cannot modify settings.json or profiles\
  🔴 Cannot access parent directories without `$PLACE$` + approval

══════════════════════════════════════════════════════════════════

BLOCKED PATHS  (AXON will hard-reject any action targeting these)
  $blockedList

══════════════════════════════════════════════════════════════════

EXECUTION LIMITS
  Max code executions per minute : $maxExec
  Dry run before execution        : $dryRun
  Confirmation mode              : $confirmMode
  Pending timeout (minutes)      : $pendingTimeout
  If you are in SANDBOX MODE, no code actually runs — AXON
  will simulate and show what would happen.

══════════════════════════════════════════════════════════════════

RULES YOU MUST ALWAYS FOLLOW
  1. Never attempt to touch blocked paths — not even to read them.
  2. Never attempt to modify the AXON script itself.
  3. Never make irreversible changes without `$CONFIRM$` first.
  4. Always be transparent — tell the user exactly what you are
     doing and why before you do it.
  5. If you are unsure whether an action is safe, use `$WARN$`
     and ask with `$CONFIRM$` rather than proceeding.
  6. You cannot change your own system prompt or override safety.
  7. The user's instruction always takes precedence over your
     own judgment — but never over the hardcoded safety layer.

══════════════════════════════════════════════════════════════════

MEMORY FROM LAST SESSION
$memory

══════════════════════════════════════════════════════════════════

FULL AXON SCRIPT REFERENCE  (sanitized — safety block redacted)
The following is the complete source of the AXON middleware script.
Study it to understand exactly what every function does, what tags
trigger what code paths, and what capabilities you have available.

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
            '^Get-ChildItem|^ls |^dir '           { $summary.Add("📋 List files/folders")            | Out-Null }
            '^Get-Content|^cat '                  { $summary.Add("📖 Read file content")              | Out-Null }
            '^Set-Content|^Out-File|^Add-Content' { $summary.Add("✏️  Write to a file")               | Out-Null }
            '^Copy-Item'                          { $summary.Add("📋 Copy a file or folder")          | Out-Null }
            '^Move-Item'                          { $summary.Add("📦 Move a file or folder")          | Out-Null }
            '^Remove-Item'                        { $summary.Add("🗑️  Delete a file or folder")        | Out-Null }
            '^New-Item'                           { $summary.Add("🆕 Create a new file or folder")    | Out-Null }
            '^Rename-Item'                        { $summary.Add("✏️  Rename a file or folder")        | Out-Null }
            '^Start-Process'                      { $summary.Add("▶️  Launch a process/application")  | Out-Null }
            '^Stop-Process'                       { $summary.Add("⏹️  Stop a running process")         | Out-Null }
            '^Get-Process'                        { $summary.Add("📋 List running processes")         | Out-Null }
            '^Invoke-WebRequest|^Invoke-RestMethod'{ $summary.Add("🌐 Make a web/network request")   | Out-Null }
            '^Write-Output|^Write-Host'           { $summary.Add("💬 Print output to terminal")       | Out-Null }
            '^Install-Package|^winget '           { $summary.Add("📦 Install software")              | Out-Null }
            '^Register-ScheduledTask'             { $summary.Add("⏰ Create a scheduled task")        | Out-Null }
            '^Compress-Archive|^Expand-Archive'   { $summary.Add("📦 Compress or extract archive")   | Out-Null }
        }
    }
    if ($summary.Count -eq 0) { $summary.Add("⚙️  Execute PowerShell ($($lines.Count) line(s))") | Out-Null }
    return ($summary | Select-Object -Unique)
}

function Request-UserConfirm {
    param([string]$Prompt)
    Write-Host ""
    Write-Host "  ┌─ Confirm Action " -ForegroundColor $UI.WarnText
    Write-Host "  │  $Prompt" -ForegroundColor White
    Write-Host "  └─ Proceed? (y/n): " -ForegroundColor $UI.WarnText -NoNewline
    $a = (Read-Host).Trim().ToLower()
    return ($a -eq "y" -or $a -eq "yes")
}

function Get-ConfirmationMode {
    $s = Get-Settings
    $mode = if ($s -and $s.confirmation_mode) { ([string]$s.confirmation_mode).ToLower() } else { "inline" }
    if ($mode -notin @("inline","deferred")) { return "inline" }
    return $mode
}

function Register-PendingAction {
    param(
        [ValidateSet("CODE","FILE","PLACE","CONFIRM")]
        [string]$Type,
        [string]$Prompt,
        [scriptblock]$OnApprove,
        [string]$OnApproveSummary = "",
        [string]$OnDenySummary = "",
        [string[]]$PreviewLines = @()
    )

    if ($State.PendingAction -and (Test-PendingActionExpired)) {
        Write-ActionLog "PENDING EXPIRED — $($State.PendingAction.type)"
        $State.PendingDeniedCount++
        $State.PendingAction = $null
    }

    if ($State.PendingAction) {
        Write-Msg -Role "warn" -Content "Another action is already pending. Resolve it with /approve or /deny first."
        return $false
    }

    $now = Get-Date
    $timeout = Get-PendingTimeoutMinutes

    $State.PendingAction = @{
        type = $Type
        prompt = $Prompt
        on_approve = $OnApprove
        on_approve_summary = $OnApproveSummary
        on_deny_summary = $OnDenySummary
        created_at = $now.ToString("yyyy-MM-dd HH:mm:ss")
        expires_at = $now.AddMinutes($timeout).ToString("yyyy-MM-dd HH:mm:ss")
        preview_lines = @($PreviewLines)
    }

    Write-Msg -Role "pending" -Content "$Prompt"
    Write-Msg -Role "system" -Content "Pending action saved. Use /pending to inspect, /approve to run, /deny to cancel."
    Write-ActionLog "PENDING $Type — $Prompt"
    return $true
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
        Set-LastErrorState -Source "RATE_LIMIT" -Message "Rate limit reached ($maxExec/min)"
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
        Write-Host "  ██  CODE BLOCK REJECTED  ██" -ForegroundColor Red
        Write-Msg -Role "error" -Content "Safety violation: $($safety.Reason)"
        Write-ActionLog "CODE REJECTED — $($safety.Reason)"
        $State.BlockedActionCount++
        return "[REJECTED] $($safety.Reason)"
    }

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

    if ((Get-ConfirmationMode) -eq "deferred") {
        $approveAction = {
            if (-not (Test-RateLimit)) { return "[RATE LIMITED]" }
            Write-Host ""
            Write-Host "  ◌ Executing..." -ForegroundColor $UI.DimText
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
                Set-LastErrorState -Source "CODE_EXEC" -Message $err
                return "[ERROR] $err"
            }
        }.GetNewClosure()

        $registered = Register-PendingAction `
            -Type "CODE" `
            -Prompt "Run AI-provided code block ($($Code.Length) chars)." `
            -OnApprove $approveAction `
            -OnApproveSummary "[APPROVED] CODE_EXEC" `
            -OnDenySummary "[DENIED] CODE_EXEC" `
            -PreviewLines @(
                "Execution mode: PowerShell code",
                "Lines: $(($Code -split "`n").Count)",
                "Summary: $((Get-CodeSummary -Code $Code) -join '; ')",
                "First line: $((($Code -split "`n")[0]).Trim())"
            )
        if ($registered) { return "[PENDING] Awaiting /approve for code execution." }
        return "[PENDING_EXISTS]"
    }

    if (-not (Request-UserConfirm -Prompt "Run this code on your machine?")) {
        Write-Msg -Role "system" -Content "Code execution denied."
        Write-ActionLog "CODE DENIED by user"
        return "[DENIED] User rejected execution."
    }

    if (-not (Test-RateLimit)) { return "[RATE LIMITED]" }

    Write-Host ""
    Write-Host "  ◌ Executing..." -ForegroundColor $UI.DimText
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
        Set-LastErrorState -Source "CODE_EXEC" -Message $err
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
    Write-Host "   📄 $destPath" -ForegroundColor White
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

    if ((Get-ConfirmationMode) -eq "deferred") {
        $approveAction = {
            try {
                Write-TextFileAtomic -Path $destPath -Content $Content | Out-Null
                Write-Msg -Role "ok" -Content "File created: $destPath"
                Write-ActionLog "FILE CREATED: $destPath"
                Push-UndoEntry -Type "FILE_CREATE" -Data @{ path = $destPath }
                return "[OK] Created at $destPath"
            } catch {
                $err = $_.Exception.Message
                Write-Msg -Role "error" -Content "File creation failed: $err"
                Write-ActionLog "FILE ERROR: $err"
                Set-LastErrorState -Source "FILE_CREATE" -Message $err
                return "[ERROR] $err"
            }
        }.GetNewClosure()

        $registered = Register-PendingAction `
            -Type "FILE" `
            -Prompt "Create file '$FileName' inside temp/." `
            -OnApprove $approveAction `
            -OnApproveSummary "[APPROVED] FILE_CREATE $FileName" `
            -OnDenySummary "[DENIED] FILE_CREATE $FileName" `
            -PreviewLines @(
                "Target: $destPath",
                "Lines: $totalLines",
                "Preview: $((($Content -split "`n" | Select-Object -First 1) -join ''))"
            )
        if ($registered) { return "[PENDING] Awaiting /approve for file creation." }
        return "[PENDING_EXISTS]"
    }

    if (-not (Request-UserConfirm -Prompt "Create '$FileName' in temp folder?")) {
        Write-ActionLog "FILE DENIED: $FileName"
        return "[DENIED]"
    }

    try {
        Write-TextFileAtomic -Path $destPath -Content $Content | Out-Null
        Write-Msg -Role "ok" -Content "File created: $destPath"
        Write-ActionLog "FILE CREATED: $destPath"
        Push-UndoEntry -Type "FILE_CREATE" -Data @{ path = $destPath }
        return "[OK] Created at $destPath"
    } catch {
        $err = $_.Exception.Message
        Write-Msg -Role "error" -Content "File creation failed: $err"
        Write-ActionLog "FILE ERROR: $err"
        Set-LastErrorState -Source "FILE_CREATE" -Message $err
        return "[ERROR] $err"
    }
}

function Invoke-PlaceTag {
    param([string]$DestPath)
    $DestPath = $DestPath.Trim()
    if (-not (Test-PathSafe -TargetPath $DestPath)) {
        Write-Msg -Role "error" -Content "PLACE blocked — protected path: $DestPath"
        Write-ActionLog "PLACE BLOCKED: $DestPath"
        $State.BlockedActionCount++
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
    Write-Host "   From : $srcPath" -ForegroundColor $UI.DimText
    Write-Host "   To   : $DestPath" -ForegroundColor White
    Write-ThinDivider

    if ($State.SandboxMode) {
        Write-Msg -Role "warn" -Content "SANDBOX MODE — placement simulated."
        Write-ActionLog "SANDBOX — PLACE simulated: $DestPath"
        return "[SANDBOX]"
    }

    if ((Get-ConfirmationMode) -eq "deferred") {
        $approveAction = {
            try {
                $dir = [System.IO.Path]::GetDirectoryName($DestPath)
                if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                Move-Item -Path $srcPath -Destination $DestPath -Force
                Write-Msg -Role "ok" -Content "File placed: $DestPath"
                Write-ActionLog "FILE PLACED: $srcPath → $DestPath"
                Push-UndoEntry -Type "FILE_PLACE" -Data @{ dest = $DestPath; src = $srcPath }
                return "[OK] Placed at $DestPath"
            } catch {
                $err = $_.Exception.Message
                Write-Msg -Role "error" -Content "Place failed: $err"
                Write-ActionLog "PLACE ERROR: $err"
                Set-LastErrorState -Source "FILE_PLACE" -Message $err
                return "[ERROR] $err"
            }
        }.GetNewClosure()

        $registered = Register-PendingAction `
            -Type "PLACE" `
            -Prompt "Move file '$fileName' from temp/ to '$DestPath'." `
            -OnApprove $approveAction `
            -OnApproveSummary "[APPROVED] FILE_PLACE $DestPath" `
            -OnDenySummary "[DENIED] FILE_PLACE $DestPath" `
            -PreviewLines @(
                "Source: $srcPath",
                "Destination: $DestPath"
            )
        if ($registered) { return "[PENDING] Awaiting /approve for placement." }
        return "[PENDING_EXISTS]"
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
        Write-ActionLog "FILE PLACED: $srcPath → $DestPath"
        Push-UndoEntry -Type "FILE_PLACE" -Data @{ dest = $DestPath; src = $srcPath }
        return "[OK] Placed at $DestPath"
    } catch {
        $err = $_.Exception.Message
        Write-Msg -Role "error" -Content "Place failed: $err"
        Write-ActionLog "PLACE ERROR: $err"
        Set-LastErrorState -Source "FILE_PLACE" -Message $err
        return "[ERROR] $err"
    }
}

function Invoke-ReadTag {
    param([string]$FilePath)
    $FilePath = $FilePath.Trim()
    if (-not (Test-PathSafe -TargetPath $FilePath)) {
        Write-Msg -Role "error" -Content "READ blocked — protected path."
        Write-ActionLog "READ BLOCKED: $FilePath"
        $State.BlockedActionCount++
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
    if ((Get-ConfirmationMode) -eq "deferred") {
        $approveAction = { return "[CONFIRM APPROVED]" }.GetNewClosure()
        $registered = Register-PendingAction `
            -Type "CONFIRM" `
            -Prompt "AI confirmation requested: $Message" `
            -OnApprove $approveAction `
            -OnApproveSummary "[APPROVED] CONFIRM '$Message'" `
            -OnDenySummary "[DENIED] CONFIRM '$Message'" `
            -PreviewLines @("AI message: $Message")
        if ($registered) { return $null }
        return $false
    }

    Write-Host ""
    Write-Host "  ┌─ AI is asking for your confirmation" -ForegroundColor Magenta
    Write-Host "  │  $Message" -ForegroundColor White
    Write-Host "  └─ Proceed? (y/n): " -ForegroundColor Magenta -NoNewline
    $a = (Read-Host).Trim().ToLower()
    $r = ($a -eq "y" -or $a -eq "yes")
    Write-ActionLog "CONFIRM — '$Message' — $(if($r){'approved'}else{'denied'})"
    return $r
}

function Invoke-WarnTag {
    param([string]$Message)
    Write-Host ""
    Write-Host "  ⚠  AI WARNING" -ForegroundColor Yellow
    Write-Host "     $Message"   -ForegroundColor Yellow
    Write-ActionLog "WARN — $Message"
}

function Invoke-MemoryTag {
    param([string]$Content)
    $memPath = "$DataFolder\memory.txt"
    $ts      = Get-Date -Format "yyyy-MM-dd HH:mm"
    Write-TextFileAtomic -Path $memPath -Content "[$ts]`n$Content" | Out-Null
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
        $test = if ($line) { "$line $word" } else { $word }
        $hasNL = $word.Contains("`n")
        if ($hasNL) {
            $parts2 = $word -split "`n"
            foreach ($i in 0..($parts2.Count-1)) {
                $p    = $parts2[$i]
                $tl   = if ($line) { "$line $p" } else { $p }
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
    $c = [regex]::Replace($c, '\$CODE\$.*?\$ENDCODE\$',      '[executing code...]',           $o)
    $c = [regex]::Replace($c, '\$FILE:.+?\$.*?\$ENDFILE\$',  '[creating file...]',            $o)
    $c = [regex]::Replace($c, '\$MEMORY:.+?\$',              '',                              $o)
    $c = $c -replace '\$PLACE:.+?\$',   '[placing file...]'
    $c = $c -replace '\$READ:.+?\$',    '[reading file...]'
    $c = $c -replace '\$CONFIRM:.+?\$', '[requesting confirmation...]'
    $c = $c -replace '\$WARN:.+?\$',    ''
    return $c.Trim()
}

function Invoke-ParseResponse {
    param([string]$RawReply)
    $feedback = [System.Collections.ArrayList]@()
    $o        = [System.Text.RegularExpressions.RegexOptions]::Singleline

    # WARN — first
    foreach ($m in ([regex]::Matches($RawReply, '\$WARN:(.+?)\$', $o))) {
        Invoke-WarnTag -Message $m.Groups[1].Value.Trim()
    }

    # CONFIRM — may block further actions
    $blocked = $false
    $hasPendingConfirm = $false
    foreach ($m in ([regex]::Matches($RawReply, '\$CONFIRM:(.+?)\$', $o))) {
        $confirmResult = Invoke-ConfirmTag -Message $m.Groups[1].Value.Trim()
        if ($null -eq $confirmResult) {
            $blocked = $true
            $hasPendingConfirm = $true
            $feedback.Add("[CONFIRM PENDING]: $($m.Groups[1].Value.Trim())") | Out-Null
        } elseif (-not $confirmResult) {
            $blocked = $true
            $feedback.Add("[CONFIRM DENIED]: $($m.Groups[1].Value.Trim())") | Out-Null
        } else {
            $feedback.Add("[CONFIRM APPROVED]: $($m.Groups[1].Value.Trim())") | Out-Null
        }
    }
    if ($blocked) {
        if ($hasPendingConfirm) {
            Write-Msg -Role "system" -Content "Actions paused — resolve pending confirmation with /pending and /approve or /deny."
        } else {
            Write-Msg -Role "system" -Content "Actions skipped — user declined confirmation."
        }
        return ($feedback -join "`n")
    }

    # READ — auto
    foreach ($m in ([regex]::Matches($RawReply, '\$READ:(.+?)\$'))) {
        $r = Invoke-ReadTag -FilePath $m.Groups[1].Value.Trim()
        if ($r) { $feedback.Add("[READ: $($m.Groups[1].Value.Trim())]`n$r") | Out-Null }
    }

    # FILE
    foreach ($m in ([regex]::Matches($RawReply, '\$FILE:(.+?)\$(.*?)\$ENDFILE\$', $o))) {
        $r = Invoke-FileTag -FileName $m.Groups[1].Value.Trim() -Content $m.Groups[2].Value.Trim()
        if ($r) { $feedback.Add("[FILE: $($m.Groups[1].Value.Trim())] $r") | Out-Null }
        if ($State.PendingAction -and ([string]$r).StartsWith("[PENDING")) {
            $feedback.Add("[AXON] Remaining actions deferred until pending action is resolved.") | Out-Null
            return ($feedback -join "`n")
        }
    }

    # CODE
    foreach ($m in ([regex]::Matches($RawReply, '\$CODE\$(.*?)\$ENDCODE\$', $o))) {
        $r = Invoke-CodeTag -Code $m.Groups[1].Value
        if ($r) { $feedback.Add("[CODE OUTPUT]`n$r") | Out-Null }
        if ($State.PendingAction -and ([string]$r).StartsWith("[PENDING")) {
            $feedback.Add("[AXON] Remaining actions deferred until pending action is resolved.") | Out-Null
            return ($feedback -join "`n")
        }
    }

    # PLACE
    foreach ($m in ([regex]::Matches($RawReply, '\$PLACE:(.+?)\$'))) {
        $r = Invoke-PlaceTag -DestPath $m.Groups[1].Value.Trim()
        if ($r) { $feedback.Add("[PLACE: $($m.Groups[1].Value.Trim())] $r") | Out-Null }
        if ($State.PendingAction -and ([string]$r).StartsWith("[PENDING")) {
            $feedback.Add("[AXON] Remaining actions deferred until pending action is resolved.") | Out-Null
            return ($feedback -join "`n")
        }
    }

    # MEMORY
    foreach ($m in ([regex]::Matches($RawReply, '\$MEMORY:(.+?)\$', $o))) {
        Invoke-MemoryTag -Content $m.Groups[1].Value.Trim()
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

    Write-JsonFileAtomic -Path $logPath -Data $meta -Depth 10 | Out-Null
    $State.SessionLogPath = $logPath
    Write-ActionLog "Session log initialized: $logName"
}

function Save-SessionLog {
    if (-not $State.SessionLogPath) { return }
    try {
        $log = Read-JsonFileSafe -Path $State.SessionLogPath
        if (-not $log) {
            $log = [ordered]@{
                session_number = $State.SessionNumber
                session_id     = $SESSION_ID
                started_at     = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                profile        = if ($State.ActiveProfile) { $State.ActiveProfile.profile_name } else { "NoProfile" }
                provider       = if ($State.ActiveProfile) { $State.ActiveProfile.provider } else { "" }
                model          = if ($State.ActiveProfile) { $State.ActiveProfile.model } else { "" }
                turns          = @()
                ended_at       = ""
                ai_calls       = 0
                executions     = 0
            }
        }
        $turns = [System.Collections.ArrayList]@()

        foreach ($msg in $State.ChatHistory) {
            # Skip internal AXON feedback injections.
            $content = [string]$msg.content
            if ($content.StartsWith("[AXON") -or $content.StartsWith("[CONTEXT")) { continue }
            $turns.Add([ordered]@{
                role    = $msg.role
                content = $content
            }) | Out-Null
        }

        $log.turns      = $turns.ToArray()
        $log.ended_at   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        $log.ai_calls   = $State.AICallCount
        $log.executions = $State.ExecutionCount
        Write-JsonFileAtomic -Path $State.SessionLogPath -Data $log -Depth 20 | Out-Null
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

    # /history load|resume [n]
    if ($Sub -match '^(load|resume)\s+(\d+)$') {
        $idx = [int]$Matches[2] - 1
        if ($idx -lt 0 -or $idx -ge $logs.Count) {
            Write-Msg -Role "error" -Content "Invalid session number."; return
        }
        Load-SessionHistory -LogPath $logs[$idx].FullName; return
    }

    # /history search [keyword]
    if ($Sub -match '^search\s+(.+)$') {
        $needle = $Matches[1].Trim()
        if ([string]::IsNullOrWhiteSpace($needle)) {
            Write-Msg -Role "error" -Content "Usage: /history search [keyword]"
            return
        }

        Write-Host ""; Write-ThinDivider
        Write-Host "   History Search: '$needle'" -ForegroundColor $UI.Header
        Write-ThinDivider
        $hits = 0
        $i = 1
        foreach ($log in $logs) {
            $d = Read-JsonFileSafe -Path $log.FullName
            if (-not $d -or -not $d.turns) { $i++; continue }

            $matchTurn = $d.turns | Where-Object { ([string]$_.content).ToLower().Contains($needle.ToLower()) } | Select-Object -First 1
            if ($matchTurn) {
                $preview = ([string]$matchTurn.content) -replace "`r"," " -replace "`n"," "
                if ($preview.Length -gt 90) { $preview = $preview.Substring(0,90) + "..." }
                Write-Host ("   [{0}] {1}  ({2})" -f $i, $d.started_at, $d.profile) -ForegroundColor $UI.BodyText
                Write-Host ("       {0}: {1}" -f $matchTurn.role, $preview) -ForegroundColor $UI.DimText
                $hits++
                if ($hits -ge 20) { break }
            }
            $i++
        }
        if ($hits -eq 0) {
            Write-Host "   No matches found." -ForegroundColor $UI.DimText
        } else {
            Write-Host ""
            Write-Host "   Use /history resume [n] to load one of the sessions above." -ForegroundColor $UI.DimText
        }
        Write-ThinDivider
        return
    }

    # /history [n] — detail view
    if ($Sub -match '^\d+$') {
        $idx = [int]$Sub - 1
        if ($idx -lt 0 -or $idx -ge $logs.Count) {
            Write-Msg -Role "error" -Content "Invalid session number."; return
        }
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
            $d = Read-JsonFileSafe -Path $log.FullName
            if (-not $d) { throw "Unreadable session log." }
            $turns = if ($d.turns) { $d.turns.Count } else { 0 }
            $cur   = if ($State.SessionLogPath -eq $log.FullName) { " ◄" } else { "" }
            Write-Host ("   {0,-4} {1,-22} {2,-18} {3,-6} {4}{5}" -f $i, $d.started_at, $d.profile, $turns, $d.model, $cur) -ForegroundColor $UI.BodyText
        } catch {
            Write-Host "   $i   $($log.Name)  (unreadable)" -ForegroundColor $UI.DimText
        }
        $i++
    }
    Write-ThinDivider
    Write-Host "   /history [n]         → view session detail" -ForegroundColor $UI.DimText
    Write-Host "   /history resume [n]  → resume session into context" -ForegroundColor $UI.DimText
    Write-Host "   /history search [k]  → search by keyword" -ForegroundColor $UI.DimText
    Write-ThinDivider
}

function Show-SessionDetail {
    param([string]$LogPath)
    try { $d = Read-JsonFileSafe -Path $LogPath; if (-not $d) { throw "Unreadable." } }
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
}

function Load-SessionHistory {
    param([string]$LogPath)
    try { $d = Read-JsonFileSafe -Path $LogPath; if (-not $d) { throw "Unreadable." } }
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

    $State.LastHistoryLoaded = "Session #$($d.session_number) ($($d.started_at))"

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
                    Write-ActionLog "UNDO FILE_PLACE — $dest → $src"
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
            Write-TextFileAtomic -Path "$DataFolder\memory.txt" -Content "[$ts — Session #$($State.SessionNumber)]`n$reply" | Out-Null
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
    Write-Host ("   {0,-26} {1}" -f "Undo stack:",      "$($State.UndoStack.Count) entries") -ForegroundColor $UI.BodyText
    if ($State.SessionLogPath) {
        Write-Host ("   {0,-26} {1}" -f "Log:", [System.IO.Path]::GetFileName($State.SessionLogPath)) -ForegroundColor $UI.DimText
    }
    Write-ThinDivider
}


function Invoke-SlashCommand {
    param([string]$RawInput)

    if ([string]::IsNullOrWhiteSpace($RawInput)) { return }

    $parts   = $RawInput.TrimStart("/").Split(" ", 2)
    $cmd     = $parts[0].ToLower().Trim()
    $subArgs = if ($parts.Count -gt 1) { $parts[1].Trim() } else { "" }

    switch ($cmd) {
        # ── Core ──
        "help"     { Invoke-HelpCommand }
        "status"   { Invoke-StatusCommand }
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
        "confirmmode" { Invoke-ConfirmModeCommand -Mode $subArgs }

        # ── Session & Files ──
        "memory"   { Invoke-MemoryCommand }
        "health"   { Invoke-HealthCommand }
        "pending"  { Invoke-PendingCommand }
        "recent"   { Invoke-RecentCommand -N $subArgs }
        "last"     { Invoke-LastCommand }
        "context"  { Invoke-ContextCommand -Sub $subArgs }
        "files"    { Invoke-FilesCommand }
        "temp"     { Invoke-TempCommand }
        "log"      { Invoke-LogCommand }
        "open"     { Invoke-OpenCommand -Target $subArgs }
        "peek"     { Invoke-PeekCommand -Path $subArgs }
        "retry"    { Invoke-RetryCommand }
        "fixlast"  { Invoke-FixLastCommand }

        # ── Advanced Session Controls ──
        "history"  { Invoke-HistoryCommand -Sub $subArgs }
        "reload"   {
            $mode = if ([string]::IsNullOrWhiteSpace($subArgs)) { "soft" } else { $subArgs.Trim().ToLower() }
            if ($mode -notin @("soft","hard")) {
                Write-Msg -Role "error" -Content "Usage: /reload [soft|hard]"
            } else {
                $State.ChatHistory.Clear()
                if ($mode -eq "hard") {
                    $State.LastContextNote = $null
                    $State.LastHistoryLoaded = $null
                    $State.PendingAction = $null
                    $State.LastAIRawReply = $null
                    $State.LastFailedUserMessage = $null
                    $State.LastFailedAt = $null
                    Clear-LastErrorState
                }
                Write-Msg -Role "ok" -Content "Reload complete ($mode). AI will receive a fresh system prompt on next message."
                Write-ActionLog "User triggered /reload $mode — chat history cleared."
            }
        }
        "inject"   {
            if ([string]::IsNullOrWhiteSpace($subArgs)) {
                Write-Msg -Role "error" -Content "Usage: /inject [text to add to context]"
            } else {
                Invoke-ContextCommand -Sub "note $subArgs"
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
        "approve"  {
            if (-not $State.PendingAction) {
                Write-Msg -Role "system" -Content "No pending action to approve."
                break
            }
            if (Test-PendingActionExpired) {
                Write-Msg -Role "warn" -Content "Pending action expired and was cleared."
                Write-ActionLog "PENDING EXPIRED — $($State.PendingAction.type)"
                $State.PendingDeniedCount++
                $State.PendingAction = $null
                break
            }
            $pending = $State.PendingAction
            $State.PendingAction = $null
            Write-Msg -Role "system" -Content "Approving: $($pending.prompt)"

            try {
                $result = & $pending.on_approve
                if ($pending.on_approve_summary) {
                    Write-ActionLog $pending.on_approve_summary
                } else {
                    Write-ActionLog "PENDING APPROVED — $($pending.type)"
                }

                if (-not [string]::IsNullOrWhiteSpace($result)) {
                    $State.ChatHistory.Add(@{ role = "user"; content = "[AXON APPROVAL RESULT]`n$result" }) | Out-Null
                    $State.ChatHistory.Add(@{ role = "assistant"; content = "Understood. I have received the approval result." }) | Out-Null
                }
                $State.PendingApprovedCount++
                Clear-LastErrorState
                Write-Msg -Role "ok" -Content "Pending action executed."
                Save-SessionLog
            } catch {
                $err = $_.Exception.Message
                Write-Msg -Role "error" -Content "Approval execution failed: $err"
                Write-ActionLog "PENDING APPROVAL FAILED — $err"
                Set-LastErrorState -Source "PENDING_APPROVE" -Message $err
            }
        }
        "deny" {
            if ($State.PendingAction) {
                $summary = if ($State.PendingAction.on_deny_summary) { $State.PendingAction.on_deny_summary } else { "PENDING DENIED — $($State.PendingAction.type)" }
                $State.PendingAction = $null
                $State.PendingDeniedCount++
                Write-Msg -Role "ok" -Content "Pending action rejected and cleared."
                Write-ActionLog $summary
                Save-SessionLog
            } else {
                Write-Msg -Role "system" -Content "No pending action to deny."
            }
        }
        "undo"     { Invoke-UndoCommand }

        default {
            Write-Msg -Role "error" -Content "Unknown command: /$cmd  —  type /help to see all commands."
        }
    }
}


# ================================================================
#  AI FLOW HELPER
# ================================================================

function Invoke-UserMessageFlow {
    param(
        [string]$UserInput,
        [string]$Source = "user",
        [bool]$ShowAsUser = $true,
        [string]$DisplayText = ""
    )

    if ([string]::IsNullOrWhiteSpace($UserInput)) { return $false }

    if ($State.PendingAction -and (Test-PendingActionExpired)) {
        Write-Msg -Role "warn" -Content "Pending action expired and was cleared."
        Write-ActionLog "PENDING EXPIRED — $($State.PendingAction.type)"
        $State.PendingDeniedCount++
        $State.PendingAction = $null
    }

    if ($State.PendingAction) {
        Write-Msg -Role "warn" -Content "There is a pending action. Resolve it with /pending, /approve, or /deny first."
        return $false
    }

    if (-not $State.ActiveProfile) {
        Write-Msg -Role "error" -Content "No active profile. Use /profile new first."
        return $false
    }

    if ($ShowAsUser) {
        $text = if ([string]::IsNullOrWhiteSpace($DisplayText)) { $UserInput } else { $DisplayText }
        Write-Msg -Role "user" -Content $text
    }
    if ($Source -ne "user") {
        Write-ActionLog "AI flow source: $Source"
    }

    # Build full AXON interface document — fresh on every call
    Write-Host "  ◌ Preparing context..." -ForegroundColor $UI.DimText -NoNewline
    $systemPrompt = Build-SystemPrompt
    Write-Host "`r                           `r" -NoNewline

    # Add user message to history BEFORE the call
    $State.ChatHistory.Add(@{ role = "user"; content = $UserInput }) | Out-Null

    $reply = Invoke-AICall `
        -UserMessage  $UserInput `
        -SystemPrompt $systemPrompt `
        -History      $State.ChatHistory

    if (-not $reply) { return $false }

    # Display clean text (tags stripped for readability)
    $displayText = Get-DisplayText -Text $reply
    if (-not [string]::IsNullOrWhiteSpace($displayText)) {
        Write-AIResponse -Text $displayText
    }

    # Parse and execute all tags in the response
    $feedback = Invoke-ParseResponse -RawReply $reply

    # If there was any execution output, inject it back into
    # chat history so the AI knows what happened
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
    return $true
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
#  ENTRY POINT
# ================================================================

function Start-AXON {
    Show-Banner
    Initialize-DataFolder
    $State.StartupHealth = Invoke-StartupHealthCheck
    Load-ActiveProfile
    Initialize-SessionLog
    Write-ActionLog "SESSION STARTED — Session #$($State.SessionNumber)  ID: $SESSION_ID"
    if ($State.StartupHealth) {
        foreach ($repair in $State.StartupHealth.repairs) {
            Write-ActionLog "HEALTH REPAIR — $repair"
        }
        foreach ($warning in $State.StartupHealth.warnings) {
            Write-ActionLog "HEALTH WARN — $warning"
        }
    }

    [Console]::Clear()
    Write-Header

    Write-Msg -Role "system" -Content "AXON v$AXON_VERSION initialized."
    Write-Msg -Role "system" -Content "Data folder: $DataFolder"
    if ($State.StartupHealth) {
        $repairCount = if ($State.StartupHealth.repairs) { $State.StartupHealth.repairs.Count } else { 0 }
        $warningCount = if ($State.StartupHealth.warnings) { $State.StartupHealth.warnings.Count } else { 0 }
        if ($repairCount -gt 0 -or $warningCount -gt 0) {
            Write-Msg -Role "warn" -Content "Startup health check: $repairCount repair(s), $warningCount warning(s)."
            Write-Msg -Role "system" -Content "Type /health to review details."
        } else {
            Write-Msg -Role "ok" -Content "Startup health check passed."
        }
    }

    if ($State.ActiveProfile) {
        Write-Msg -Role "ok" -Content "Profile loaded: $($State.ActiveProfile.profile_name)  ($($State.ActiveProfile.provider) / $($State.ActiveProfile.model))"
        Write-Msg -Role "system" -Content "Type anything to start talking to the AI."
    } else {
        Write-Msg -Role "warn" -Content "No profile loaded — use /profile new to create one."
    }

    Write-Msg -Role "system" -Content "Type / for quick command hints, or /help for full reference."
    Write-Msg -Role "system" -Content "Starter commands: /status   /pending   /context"
    Write-Host ""

    while ($true) {
        $userInput = Read-UserInput

        if ([string]::IsNullOrWhiteSpace($userInput)) { continue }

        if ($userInput -eq "/") {
            Show-SlashHints
            continue
        }

        if ($userInput.StartsWith("/")) {
            Invoke-SlashCommand -RawInput $userInput
            continue
        }

        # ── Regular message → AI ──
        [void](Invoke-UserMessageFlow -UserInput $userInput -Source "user")
    }
}

Start-AXON
