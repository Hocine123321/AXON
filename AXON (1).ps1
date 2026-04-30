# ================================================================
#  AXON — AI Agent Framework
#  Phase 1-7 : Foundation (TUI, Profiles, API, Tags, Safety, Logs)
#  v1.0 Mega A: Smart Brain, Real Streaming, Auto Functions,
#               New Tags ($SEARCH$ $OPEN$ $NOTIFY$ $CLIP$ $MACRO$
#               $STATUS$ $PLUGIN$), Function Registry, Context Mgr
#  Version: 1.0.0
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

$AXON_VERSION  = "1.0.0"
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
    UndoStack            = [System.Collections.ArrayList]@()
    MessageCount         = 0
    SessionLogPath       = $null
    AICallCount          = 0
    # v1.0 — Smart Brain
    SmartMemory          = @{}          # structured JSON knowledge base
    # v1.0 — Context manager
    TokenEstimate        = 0
    MaxContextTokens     = 6000         # soft ceiling before trimming
    # v1.0 — Function registry
    FunctionRegistry     = [ordered]@{}
    # v1.0 — Macros
    Macros               = @{}
    # v1.0 — Plugins loaded this session
    LoadedPlugins        = [System.Collections.ArrayList]@()
    # v1.0 — Status bar message
    StatusBarMsg         = ""
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
    $tokenLabel   = if ($State.TokenEstimate -gt 0) { "  ~$($State.TokenEstimate)t" } else { "" }
    $pluginLabel  = if ($State.LoadedPlugins.Count -gt 0) { "  +$($State.LoadedPlugins.Count) plugin(s)" } else { "" }

    Write-Divider
    Write-Host "  $AXON_NAME  •  $profileLabel  •  $sessionLabel$sandboxTag$tokenLabel$pluginLabel" -ForegroundColor $UI.Header
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
    Write-Host "${pad}║    A  X  O  N   v1.0     ║" -ForegroundColor Cyan
    Write-Host "${pad}║                          ║" -ForegroundColor Cyan
    Write-Host "${pad}╚══════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "${pad}  AI Agent Framework" -ForegroundColor DarkGray
    Write-Host "${pad}  Pure PowerShell. No dependencies." -ForegroundColor DarkGray
    Write-Host ""
    Start-Sleep -Milliseconds 1400
}

function Show-SlashHints {
    $hints = @("/help","/settings","/profile","/history","/files","/sandbox","/brake","/exit")
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

    # Default settings
    $settingsPath = "$DataFolder\settings.json"
    if (-not (Test-Path $settingsPath)) {
        @{
            active_profile           = $null
            script_name              = "AXON"
            blocked_paths            = @(
                "C:\Windows\System32",
                "C:\Windows\SysWOW64",
                "C:\Program Files",
                "C:\Program Files (x86)"
            )
            user_blocked_paths       = @()
            max_executions_per_minute = 5
            dry_run_before_execute   = $true
            auto_memory              = $true
            streaming                = $false
        } | ConvertTo-Json -Depth 5 | Set-Content -Path $settingsPath -Encoding UTF8
    }

    # Default memory
    $memPath = "$DataFolder\memory.txt"
    if (-not (Test-Path $memPath)) {
        Set-Content -Path $memPath -Value "No previous memory." -Encoding UTF8
    }

    # Session counter
    $sessions = Get-ChildItem "$DataFolder\sessions" -Filter "*.log" -ErrorAction SilentlyContinue
    $State.SessionNumber = ($sessions.Count) + 1
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
    Add-Content -Path $logPath -Value "[$timestamp]  $Entry" -Encoding UTF8
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
            @{cmd="/clear";          desc="Clear the chat display (context preserved)"},
            @{cmd="/exit";           desc="Close AXON cleanly"}
        )
        "AI & PROFILES" = @(
            @{cmd="/profile";        desc="View or switch active profile"},
            @{cmd="/profile new";    desc="Create a new AI provider profile"},
            @{cmd="/profile delete"; desc="Remove a profile"},
            @{cmd="/reload";         desc="Resend system prompt to AI (fresh brain)"},
            @{cmd="/inject [text]";  desc="Add hidden context to the next AI message"}
        )
        "SESSION" = @(
            @{cmd="/history";        desc="Browse past sessions"},
            @{cmd="/log";            desc="View this session's action log"},
            @{cmd="/memory";         desc="View the AI's memory from last session"},
            @{cmd="/macro";          desc="List saved macros  (/macro list / delete [name])"}
        )
        "FILES & EXECUTION" = @(
            @{cmd="/files";          desc="Browse Data folder contents"},
            @{cmd="/peek [path]";    desc="Preview a file before AI touches it"},
            @{cmd="/exec";           desc="Re-run the last code block"},
            @{cmd="/approve";        desc="Approve last pending action"},
            @{cmd="/deny";           desc="Reject last pending action"},
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
            @{cmd="/settings";       desc="Open the settings menu"}
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

    switch ($Sub.Trim().ToLower()) {

        "new" { New-Profile }

        "delete" { Remove-Profile }

        default {
            # If sub is a profile name, switch to it
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
                                  $State.ActiveProfile.profile_name -eq $d.profile_name) { "  ◄ active" } else { "" }
                    Write-Host ("   [{0}] {1,-24} {2} / {3}{4}" -f $i, $d.profile_name, $d.provider, $d.model, $active) -ForegroundColor $UI.BodyText
                    $i++
                }
                Write-Host ""
                Write-Host "   /profile [name]    → switch to a profile" -ForegroundColor $UI.DimText
                Write-Host "   /profile new       → create a new profile" -ForegroundColor $UI.DimText
                Write-Host "   /profile delete    → remove a profile" -ForegroundColor $UI.DimText
            }
            Write-ThinDivider
        }
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

    $profile | ConvertTo-Json -Depth 5 | Set-Content -Path $profilePath -Encoding UTF8

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

    # Try exact match first, then partial
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

    # Save as active in settings
    $sp = "$DataFolder\settings.json"
    $s  = Get-Settings
    $s.active_profile = $profileData.profile_name
    $s | ConvertTo-Json -Depth 5 | Set-Content $sp -Encoding UTF8

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
    # Rough estimate: ~4 chars per token
    return [Math]::Ceiling($Text.Length / 4)
}

function Trim-ChatHistory {
    # Keep system-critical messages, trim oldest turns when near limit
    $totalChars = ($State.ChatHistory | ForEach-Object { $_.content } | Measure-Object -Character).Characters
    $estimated  = [Math]::Ceiling($totalChars / 4)
    $State.TokenEstimate = $estimated

    $softLimit = $State.MaxContextTokens
    while ($estimated -gt $softLimit -and $State.ChatHistory.Count -gt 4) {
        # Remove oldest non-feedback pair
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
            # Convert PSCustomObject to hashtable
            $ht = @{}
            $raw.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
            $State.SmartMemory = $ht
        } catch { $State.SmartMemory = @{} }
    }
}

function Save-SmartMemory {
    $memPath = "$DataFolder\smart_memory.json"
    $State.SmartMemory | ConvertTo-Json -Depth 5 | Set-Content $memPath -Encoding UTF8
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
    # $SEARCH$ — web search via Invoke-WebRequest to DuckDuckGo instant API
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
                    foreach ($t in $top) { $lines.Add("• $($t.Text)") | Out-Null }
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
                # Fallback: use msg.exe
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
            $content = Get-Content $plugin.FullName -Raw

            # Extract plugin metadata from header comments
            $nameMatch = [regex]::Match($content, '#\s*PLUGIN_NAME\s*:\s*(.+)')
            $descMatch = [regex]::Match($content, '#\s*PLUGIN_DESC\s*:\s*(.+)')
            $pName = if ($nameMatch.Success) { $nameMatch.Groups[1].Value.Trim() } else { $plugin.BaseName }
            $pDesc = if ($descMatch.Success) { $descMatch.Groups[1].Value.Trim() } else { "Plugin: $($plugin.BaseName)" }

            # Dot-source the plugin (loads its functions into scope)
            . $plugin.FullName

            $State.LoadedPlugins.Add(@{ name = $pName; desc = $pDesc; file = $plugin.Name }) | Out-Null

            # Register a function call for the plugin
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

    # Trim context if getting large
    Trim-ChatHistory

    # Build body with stream:true
    $bodyObj = Build-ApiBody -Profile $profile -Messages $History.ToArray() -SystemPrompt $SystemPrompt -Stream $true
    if (-not $bodyObj) {
        Write-Msg -Role "error" -Content "Unknown provider: $provider"
        return $null
    }

    $bodyJson = $bodyObj | ConvertTo-Json -Depth 10
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyJson)

    # Build headers
    $headerScript = $PROVIDER_HEADERS[$provider]
    $headers      = & $headerScript $profile

    Write-Host ""
    Write-Host "  AI  : " -ForegroundColor $UI.AILabel -NoNewline

    $fullText = [System.Text.StringBuilder]::new()

    try {
        # Use HttpWebRequest for true streaming
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

        $lineBuffer = ""

        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if ([string]::IsNullOrEmpty($line)) { continue }

            # SSE format: "data: {...}"
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
                # Ollama uses newline-delimited JSON, not SSE
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
        Write-Host ""  # newline after streaming

        $text = $fullText.ToString()
        if ([string]::IsNullOrWhiteSpace($text)) {
            Write-Msg -Role "error" -Content "Empty response from $provider."
            $History.RemoveAt($History.Count - 1)
            return $null
        }

        # Add full assembled reply to history
        $History.Add(@{ role = "assistant"; content = $text }) | Out-Null

        # Update token estimate
        $State.TokenEstimate = Get-TokenEstimate -Text ($History | ForEach-Object { $_.content } | Out-String)

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
        if ($History.Count -gt 0 -and $History[$History.Count-1].role -eq "user") {
            $History.RemoveAt($History.Count - 1)
        }
        return $null
    }
}


# ================================================================
#  v1.0 — UPDATED API BODY BUILDER (stream param)
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

function Invoke-SettingsCommand {
    Write-Host ""
    Write-ThinDivider
    Write-Host "   Settings" -ForegroundColor $UI.Header
    Write-ThinDivider
    $s = Get-Settings
    if ($s) {
        Write-Host ("   {0,-32} {1}" -f "Active profile:",       ($s.active_profile ?? "none"))         -ForegroundColor $UI.BodyText
        Write-Host ("   {0,-32} {1}" -f "Dry run before execute:", $s.dry_run_before_execute)            -ForegroundColor $UI.BodyText
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
    }
    Write-ThinDivider
}

function Invoke-LockCommand {
    param([string]$Path)
    if (-not $Path) { Write-Msg -Role "error" -Content "Usage: /lock [path]"; return }

    $s    = Get-Settings
    $sp   = "$DataFolder\settings.json"
    $list = [System.Collections.ArrayList]@($s.user_blocked_paths)

    if ($list -contains $Path) {
        Write-Msg -Role "warn" -Content "Already in your blocklist: $Path"
    } else {
        $list.Add($Path) | Out-Null
        $s.user_blocked_paths = $list.ToArray()
        $s | ConvertTo-Json -Depth 5 | Set-Content $sp -Encoding UTF8
        Write-Msg -Role "ok"  -Content "Locked: $Path"
        Write-ActionLog "User locked path: $Path"
    }
}

function Invoke-UnlockCommand {
    param([string]$Path)
    if (-not $Path) { Write-Msg -Role "error" -Content "Usage: /unlock [path]"; return }

    $s    = Get-Settings
    $sp   = "$DataFolder\settings.json"
    $list = [System.Collections.ArrayList]@($s.user_blocked_paths)

    if ($list -contains $Path) {
        $list.Remove($Path)
        $s.user_blocked_paths = $list.ToArray()
        $s | ConvertTo-Json -Depth 5 | Set-Content $sp -Encoding UTF8
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
            Set-Content -Path $snapshotPath -Value $notice -Encoding UTF8
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
        Set-Content -Path $snapshotPath -Value $content -Encoding UTF8
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

  ┌────────────────────────────────────────────────────────────────┐
  │ TAG                          │ PURPOSE               │ TIER    │
  ├────────────────────────────────────────────────────────────────┤
  │ `$CODE$`...`$ENDCODE$`        │ Execute PowerShell    │ 🟡      │
  │ `$FILE:name$`...`$ENDFILE$`   │ Create a file         │ 🟡      │
  │ `$PLACE:path$`                │ Move temp→real path   │ 🟡      │
  │ `$READ:path$`                 │ Read file → context   │ 🟢 auto │
  │ `$CONFIRM:msg$`               │ Ask user yes/no       │ 🟡      │
  │ `$WARN:msg$`                  │ Flag risk             │ 🟢 disp │
  │ `$MEMORY:content$`            │ Write memory.txt      │ 🟢 auto │
  │ `$SEARCH:query$`              │ Web search            │ 🟡      │
  │ `$OPEN:target$`               │ Open file/URL/app     │ 🟡      │
  │ `$NOTIFY:title|message$`      │ Windows notification  │ 🟢 auto │
  │ `$CLIP:read$`                 │ Read clipboard        │ 🟢 auto │
  │ `$CLIP:write|text$`           │ Write to clipboard    │ 🟡      │
  │ `$STATUS:message$`            │ Update AXON status bar│ 🟢 auto │
  │ `$MACRO:save|name|steps$`     │ Save a macro          │ 🟡      │
  │ `$MACRO:run|name$`            │ Run saved macro       │ 🟡      │
  │ `$MEMSET:key|value$`          │ Store to smart memory │ 🟢 auto │
  │ `$PLUGIN:name|input$`         │ Call a loaded plugin  │ 🟡      │
  └────────────────────────────────────────────────────────────────┘

  EXAMPLES:
  Search the web:        `$SEARCH:latest PowerShell 7 features$`
  Open a URL:            `$OPEN:https://docs.microsoft.com$`
  Notify the user:       `$NOTIFY:Done|Your report is ready.$`
  Read clipboard:        `$CLIP:read$`
  Write clipboard:       `$CLIP:write|Here is the result...$`
  Update status bar:     `$STATUS:Working on your report...$`
  Save a macro:          `$MACRO:save|morning-check|check disk space then list recent files$`
  Run a macro:           `$MACRO:run|morning-check$`
  Store smart memory:    `$MEMSET:user_project|C:\Projects\webapp$`

══════════════════════════════════════════════════════════════════

REGISTERED FUNCTIONS (auto-available this session)
$fnBlock

LOADED PLUGINS
$pluginBlock

SAVED MACROS
$macroBlock

══════════════════════════════════════════════════════════════════

DATA FOLDER  —  YOUR HOME BASE
  $DataFolder\
    temp\       → YOUR staging area. Create files here freely.
    workspace\  → Files you are actively reading/editing.
    plugins\    → Loaded .ps1 plugins
    macros\     → Saved macro definitions
    memory.txt  → Your session notes
    smart_memory.json → Your structured knowledge base

RULES
  ✅ Full read/write inside temp\ and workspace\
  ✅ Use `$MEMSET$` to remember anything structured about the user
  🔴 Cannot delete the Data folder itself
  🔴 Cannot touch settings.json or profiles\
  🔴 Cannot access Desktop or above without `$PLACE$` + approval

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
        Write-Host "  ██  CODE BLOCK REJECTED  ██" -ForegroundColor Red
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

    if (-not (Request-UserConfirm -Prompt "Create '$FileName' in temp folder?")) {
        Write-ActionLog "FILE DENIED: $FileName"
        return "[DENIED]"
    }

    try {
        Set-Content -Path $destPath -Value $Content -Encoding UTF8
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
    Write-Host "   From : $srcPath" -ForegroundColor $UI.DimText
    Write-Host "   To   : $DestPath" -ForegroundColor White
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
        Write-ActionLog "FILE PLACED: $srcPath → $DestPath"
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
    Set-Content -Path $memPath -Value "[$ts]`n$Content" -Encoding UTF8
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
    $c = [regex]::Replace($c, '\$CODE\$.*?\$ENDCODE\$',      '[executing code...]',      $o)
    $c = [regex]::Replace($c, '\$FILE:.+?\$.*?\$ENDFILE\$',  '[creating file...]',        $o)
    $c = [regex]::Replace($c, '\$MEMORY:.+?\$',              '',                          $o)
    $c = [regex]::Replace($c, '\$MEMSET:.+?\|.+?\$',         '',                          $o)
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
        $r = Invoke-FunctionCall -Name "status" -Args @{ message = $m.Groups[1].Value.Trim() }
        Write-ActionLog "STATUS updated: $($m.Groups[1].Value.Trim())"
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
            if ($r -and $r -notlike "[ERROR]*") {
                $feedback.Add("[MACRO RUN: $name] $r") | Out-Null
            } else {
                $feedback.Add("[MACRO] $r") | Out-Null
            }
        }
    }

    # ── PLUGIN — confirm ──
    foreach ($m in ([regex]::Matches($RawReply, '\$PLUGIN:(.+?)\|(.+?)\$', $o))) {
        $pName = $m.Groups[1].Value.Trim()
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
            # Skip internal AXON feedback injections
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
        $log | ConvertTo-Json -Depth 10 | Set-Content -Path $State.SessionLogPath -Encoding UTF8
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

    # /history load [n]
    if ($Sub -match '^load\s+(\d+)$') {
        $idx = [int]$Matches[1] - 1
        if ($idx -lt 0 -or $idx -ge $logs.Count) {
            Write-Msg -Role "error" -Content "Invalid session number."; return
        }
        Load-SessionHistory -LogPath $logs[$idx].FullName; return
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
            $d     = Get-Content $log.FullName -Raw | ConvertFrom-Json
            $turns = if ($d.turns) { $d.turns.Count } else { 0 }
            $cur   = if ($State.SessionLogPath -eq $log.FullName) { " ◄" } else { "" }
            Write-Host ("   {0,-4} {1,-22} {2,-18} {3,-6} {4}{5}" -f $i, $d.started_at, $d.profile, $turns, $d.model, $cur) -ForegroundColor $UI.BodyText
        } catch {
            Write-Host "   $i   $($log.Name)  (unreadable)" -ForegroundColor $UI.DimText
        }
        $i++
    }
    Write-ThinDivider
    Write-Host "   /history [n]       → view session detail" -ForegroundColor $UI.DimText
    Write-Host "   /history load [n]  → resume session into context" -ForegroundColor $UI.DimText
    Write-ThinDivider
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
            Set-Content -Path "$DataFolder\memory.txt" -Value "[$ts — Session #$($State.SessionNumber)]`n$reply" -Encoding UTF8
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


function Invoke-MacroCommand {
    param([string]$Sub = "")
    $macroDir = "$DataFolder\macros"

    if ($Sub -eq "list" -or $Sub -eq "") {
        $macros = Get-ChildItem $macroDir -Filter "*.json" -ErrorAction SilentlyContinue
        Write-Host ""; Write-ThinDivider
        Write-Host "   Saved Macros" -ForegroundColor $UI.Header
        Write-ThinDivider
        if (-not $macros -or $macros.Count -eq 0) {
            Write-Host "   No macros saved yet. Ask the AI to save a macro with /macro." -ForegroundColor $UI.DimText
        } else {
            foreach ($f in $macros) {
                try {
                    $m = Get-Content $f.FullName -Raw | ConvertFrom-Json
                    Write-Host ("   {0,-20} {1}" -f $m.name, $m.steps) -ForegroundColor $UI.BodyText
                } catch {}
            }
        }
        Write-ThinDivider
        Write-Host "   /macro list           → list saved macros" -ForegroundColor $UI.DimText
        Write-Host "   /macro delete [name]  → delete a macro" -ForegroundColor $UI.DimText
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


function Invoke-SlashCommand {

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

        # ── Session & Files ──
        "memory"   { Invoke-MemoryCommand }
        "files"    { Invoke-FilesCommand }
        "temp"     { Invoke-TempCommand }
        "log"      { Invoke-LogCommand }
        "peek"     { Invoke-PeekCommand -Path $subArgs }
        "macro"    { Invoke-MacroCommand -Sub $subArgs }

        # ── Phase 2+ stubs ──
        "history"  { Invoke-HistoryCommand -Sub $subArgs }
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
        "approve"  {
            # Approval happens inline during tag parsing — confirm/deny prompts
            # appear automatically when the AI uses $CONFIRM$ or action tags.
            # /approve is kept as a reminder; if there's a pending action object
            # (future use), it would be processed here.
            if ($State.PendingAction) {
                Write-Msg -Role "system" -Content "Pending action cleared. Actions are approved inline — respond 'y' at the next prompt."
                $State.PendingAction = $null
            } else {
                Write-Msg -Role "system" -Content "No pending action. Approvals happen inline when the AI requests them."
            }
        }
        "deny" {
            if ($State.PendingAction) {
                $State.PendingAction = $null
                Write-Msg -Role "ok" -Content "Pending action rejected and cleared."
                Write-ActionLog "User denied pending action."
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
    Load-ActiveProfile
    Load-SmartMemory
    Register-CoreFunctions
    Load-Plugins
    Initialize-SessionLog
    Write-ActionLog "SESSION STARTED — Session #$($State.SessionNumber)  ID: $SESSION_ID"

    [Console]::Clear()
    Write-Header

    Write-Msg -Role "system" -Content "AXON v$AXON_VERSION initialized."
    Write-Msg -Role "system" -Content "Data folder: $DataFolder"
    if ($State.FunctionRegistry.Count -gt 0) {
        Write-Msg -Role "ok" -Content "$($State.FunctionRegistry.Count) functions registered."
    }

    if ($State.ActiveProfile) {
        Write-Msg -Role "ok" -Content "Profile loaded: $($State.ActiveProfile.profile_name)  ($($State.ActiveProfile.provider) / $($State.ActiveProfile.model))"
        Write-Msg -Role "system" -Content "Type anything to start talking to the AI."
    } else {
        Write-Msg -Role "warn" -Content "No profile loaded — use /profile new to create one."
    }

    Write-Msg -Role "system" -Content "Type / for quick command hints, or /help for full reference."
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
        if (-not $State.ActiveProfile) {
            Write-Msg -Role "error" -Content "No active profile. Use /profile new first."
            continue
        }

        Write-Msg -Role "user" -Content $userInput

        # Build full AXON interface document — fresh on every call
        $systemPrompt = Build-SystemPrompt

        # Add user message to history BEFORE the call
        $State.ChatHistory.Add(@{ role = "user"; content = $userInput }) | Out-Null

        $reply = Invoke-AICall `
            -UserMessage  $userInput `
            -SystemPrompt $systemPrompt `
            -History      $State.ChatHistory

        if ($reply) {
            # Streaming already printed the text live — just parse tags now
            $displayText = Get-DisplayText -Text $reply
            # If the response was ONLY tags with no conversational text, nothing extra to show
            # Parse and execute all tags in the response
            $feedback = Invoke-ParseResponse -RawReply $reply

            # Inject execution feedback back into context so AI knows what happened
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

            # Persist session log after every AI turn
            Save-SessionLog
        }
    }
}

Start-AXON
