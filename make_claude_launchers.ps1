#Requires -Version 5.1
<#
.SYNOPSIS
  Claude Profile Switcher for Windows - isolated Claude Desktop profiles.

.DESCRIPTION
  Create (or remove) isolated Claude Desktop launchers - separate profiles
  (each with its own login/history/settings/tools).
  Safe to re-run: it never deletes profile data unless asked.

.EXAMPLE
  .\make_claude_launchers.ps1

.EXAMPLE
  .\make_claude_launchers.ps1 create Work Personal

.EXAMPLE
  .\make_claude_launchers.ps1 clean --purge
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ScriptArguments = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:LaunchersDir = Join-Path $env:USERPROFILE 'Applications'
$Script:MarkerSuffix = '.claude-fix-generated'

function Require-Windows {
    if ($env:OS -ne 'Windows_NT') {
        Write-Error 'ERROR: This script only works on Windows.'
        exit 1
    }
}

function Test-CanPrompt {
    if ($env:CLAUDE_LAUNCHERS_TEST_MODE -eq '1') { return $false }
    try {
        return [Console]::IsInputRedirected -eq $false
    }
    catch {
        return $false
    }
}

function Read-Prompt {
    param(
        [string]$Prompt,
        [string]$Default = ''
    )
    if (-not (Test-CanPrompt)) { return $Default }
    Write-Host -NoNewline $Prompt
    $reply = Read-Host
    if ([string]::IsNullOrWhiteSpace($reply)) { return $Default }
    return $reply.Trim()
}

function Get-TrimmedLabel {
    param([string]$Label)
    return $Label.Trim()
}

function Test-ValidLabel {
    param([string]$Label)

    if ([string]::IsNullOrWhiteSpace($Label)) { return $false }
    if ($Label.Length -gt 50) {
        Write-Error "ERROR: profile label is too long (max 50 characters): $Label"
        exit 1
    }
    if ($Label.StartsWith('.') -or $Label.Contains('\') -or $Label.Contains('/') -or $Label.Contains(':')) {
        Write-Error @"
ERROR: profile label contains unsupported characters: $Label
       Use letters, numbers, spaces, hyphens, underscores, or apostrophes.
"@
        exit 1
    }
    if ($Label -match '[\x00-\x1F\x7F]') {
        Write-Error 'ERROR: profile label contains control characters.'
        exit 1
    }
    return $true
}

function Get-ProfileSlug {
    param([string]$Label)

    $clean = ($Label -replace '[^a-zA-Z0-9\s-]', '')
    $clean = $clean -replace '-', ' '
    $words = ($clean -split '\s+') | Where-Object { $_ -ne '' }
    $parts = foreach ($word in $words) {
        if ($word.Length -eq 1) {
            $word.ToUpper()
        }
        else {
            $word.Substring(0, 1).ToUpper() + $word.Substring(1).ToLower()
        }
    }
    return 'Claude' + ($parts -join '')
}

function Get-ProfileDisplayName {
    param([string]$Label)
    switch ($Label) {
        'Work' { return 'Work / Company' }
        'Personal' { return 'Personal' }
        default { return $Label }
    }
}

function Get-ProfileDataPath {
    param([string]$DirSlug)
    return Join-Path $env:USERPROFILE $DirSlug
}

function Test-ProfileDataInitialized {
    param([string]$DirSlug)

    $data = Get-ProfileDataPath $DirSlug
    if (-not (Test-Path -LiteralPath $data -PathType Container)) { return $false }

    $config = Join-Path $data 'config.json'
    if (Test-Path -LiteralPath $config) {
        $content = Get-Content -LiteralPath $config -Raw -ErrorAction SilentlyContinue
        if ($content -and $content.Contains('oauth:tokenCache')) { return $true }
    }
    if (Test-Path -LiteralPath (Join-Path $data 'Local State')) { return $true }
    if (Test-Path -LiteralPath (Join-Path $data 'Cookies')) { return $true }
    return $false
}

function Get-MarkerPath {
    param([string]$ShortcutPath)
    return "$ShortcutPath$Script:MarkerSuffix"
}

function Read-MarkerValue {
    param(
        [string]$MarkerPath,
        [string]$Key
    )
    if (-not (Test-Path -LiteralPath $MarkerPath)) { return '' }
    foreach ($line in Get-Content -LiteralPath $MarkerPath -ErrorAction SilentlyContinue) {
        if ($line.StartsWith("$Key=")) {
            return $line.Substring($Key.Length + 1)
        }
    }
    return ''
}

function Write-MarkerFile {
    param(
        [string]$ShortcutPath,
        [string]$Label,
        [string]$DirSlug
    )
    $marker = Get-MarkerPath $ShortcutPath
    @(
        'generated-by=claude-fix'
        "label=$Label"
        "data-dir=$DirSlug"
    ) | Set-Content -LiteralPath $marker -Encoding UTF8
}

function Get-LauncherName {
    param([string]$Label)
    return "Claude $Label"
}

function Get-ShortcutPath {
    param([string]$Label)
    return Join-Path $Script:LaunchersDir "$(Get-LauncherName $Label).lnk"
}

function Find-ClaudeDesktop {
    if ($env:CLAUDE_LAUNCHERS_CLAUDE_EXE -and (Test-Path -LiteralPath $env:CLAUDE_LAUNCHERS_CLAUDE_EXE)) {
        return (Resolve-Path -LiteralPath $env:CLAUDE_LAUNCHERS_CLAUDE_EXE).Path
    }

    if ($env:CLAUDE_LAUNCHERS_TEST_MODE -eq '1') {
        $testExe = Join-Path $Script:LaunchersDir 'Claude\claude.exe'
        if (Test-Path -LiteralPath $testExe) {
            return (Resolve-Path -LiteralPath $testExe).Path
        }
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Claude\Claude.exe')
        (Join-Path $env:LOCALAPPDATA 'AnthropicClaude\claude.exe')
        (Join-Path ${env:ProgramFiles} 'Claude\Claude.exe')
        (Join-Path ${env:ProgramFiles(x86)} 'Claude\Claude.exe')
    )
    foreach ($path in $candidates) {
        if (Test-Path -LiteralPath $path) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }

    $packages = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Packages') -Filter 'Claude_*' -Directory -ErrorAction SilentlyContinue
    foreach ($pkg in $packages) {
        $patterns = @(
            (Join-Path $pkg.FullName 'LocalCache\Local\Claude\app-*\claude.exe')
            (Join-Path $pkg.FullName 'LocalCache\Local\Claude\claude.exe')
        )
        foreach ($pattern in $patterns) {
            $match = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending |
                Select-Object -First 1
            if ($match) { return $match.FullName }
        }
    }

    $cmd = Get-Command Claude.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) { return $cmd.Source }

    return $null
}

function Write-ClaudeNotInstalledError {
    Write-Error @"
ERROR: Claude Desktop is not installed (or could not be found).

  Install Claude Desktop from https://claude.ai/download
  Then re-run this script.

  If Claude is already installed in a non-standard location, point this script at it:
    `$env:CLAUDE_LAUNCHERS_CLAUDE_EXE = 'C:\Path\To\Claude.exe'
"@
    exit 1
}

function Require-ClaudeDesktop {
    $claudeExe = Find-ClaudeDesktop
    if (-not $claudeExe) {
        Write-ClaudeNotInstalledError
    }
    return $claudeExe
}

function Get-GeneratedLaunchers {
    $result = @()
    if (-not (Test-Path -LiteralPath $Script:LaunchersDir)) { return $result }

    Get-ChildItem -Path $Script:LaunchersDir -Filter 'Claude *.lnk' -File -ErrorAction SilentlyContinue | ForEach-Object {
        $marker = Get-MarkerPath $_.FullName
        if (-not (Test-Path -LiteralPath $marker)) { return }

        $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        $label = Read-MarkerValue $marker 'label'
        if ([string]::IsNullOrWhiteSpace($label)) {
            $label = $base.Substring(7) # strip "Claude "
        }
        $dir = Read-MarkerValue $marker 'data-dir'
        if ([string]::IsNullOrWhiteSpace($dir)) {
            $dir = Get-ProfileSlug $label
        }

        $result += [PSCustomObject]@{
            Label        = $label
            ShortcutPath = $_.FullName
            DataDirSlug  = $dir
        }
    }
    return $result
}

function Show-GeneratedLaunchers {
    param($Launchers)

    Write-Host 'Found generated profile launcher(s):'
    foreach ($item in $Launchers) {
        Write-Host "  - Claude $($item.Label)"
        Write-Host "    launcher: $($item.ShortcutPath)"
        Write-Host "    local sign-in: ~/$($item.DataDirSlug)"
    }
}

function Open-Shortcut {
    param([string]$ShortcutPath)
    if ($env:CLAUDE_LAUNCHERS_NO_OPEN -eq '1') { return }
    Start-Process -FilePath $ShortcutPath | Out-Null
}

function Open-LaunchersFolder {
    if ($env:CLAUDE_LAUNCHERS_NO_OPEN -eq '1') { return }
    if (-not (Test-Path -LiteralPath $Script:LaunchersDir)) {
        New-Item -ItemType Directory -Path $Script:LaunchersDir -Force | Out-Null
    }
    Start-Process explorer.exe $Script:LaunchersDir | Out-Null
}

function Start-FreshGeneratedProfile {
    param($Launcher)

    $label = $Launcher.Label
    $dirSlug = $Launcher.DataDirSlug
    $data = Get-ProfileDataPath $dirSlug

    Write-Host ''
    Write-Host "Claude $label can be started fresh by clearing this launcher's local sign-in:"
    Write-Host "  ~/$dirSlug"
    Write-Host ''
    Write-Host 'This does NOT delete your Claude account.'
    Write-Host 'This does NOT change your normal Claude app.'
    Write-Host "It only clears the saved local data for the Claude $label launcher on this PC."

    $ans = if ($env:CLAUDE_LAUNCHERS_RESET_PROFILE_ANSWER) {
        $env:CLAUDE_LAUNCHERS_RESET_PROFILE_ANSWER
    }
    else {
        Read-Prompt "Clear Claude $label local sign-in and start fresh? [y/N] "
    }

    switch -Regex ($ans) {
        '^(y|yes)$' {
            Remove-Item -LiteralPath $data -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  cleared local sign-in for Claude $label"
            Write-Host "Next: open Claude $label and sign in with the right account."
        }
        default {
            Write-Host "  kept the saved local sign-in in ~/$dirSlug"
        }
    }
}

function Reset-OnboardingProfileDataIfNeeded {
    param(
        [string]$Label,
        [string]$DirSlug
    )

    if (-not (Test-ProfileDataInitialized $DirSlug)) { return }

    Write-Host ''
    Write-Host "NOTE: Claude $Label already has a saved sign-in in ~/$DirSlug."
    Write-Host 'That folder is only for this launcher on your PC.'
    Write-Host 'It does not change your normal Claude app or delete your Claude account online.'
    Write-Host 'Choose yes only if the wrong account opens there and you want a fresh sign-in.'

    $ans = if ($env:CLAUDE_LAUNCHERS_RESET_PROFILE_ANSWER) {
        $env:CLAUDE_LAUNCHERS_RESET_PROFILE_ANSWER
    }
    else {
        Read-Prompt "Clear this launcher's local sign-in and start fresh? [y/N] "
    }

    switch -Regex ($ans) {
        '^(y|yes)$' {
            $data = Get-ProfileDataPath $DirSlug
            Remove-Item -LiteralPath $data -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  cleared local sign-in for Claude $Label (your normal Claude app is unchanged)"
        }
        default {
            Write-Host "  kept the saved sign-in in ~/$DirSlug"
            Write-Host '  If the wrong account opens, sign out in Claude' $Label 'or re-run and choose start fresh.'
        }
    }
}

function Select-GeneratedLauncher {
    param(
        [string]$Prompt,
        [array]$Launchers
    )

    if ($Launchers.Count -eq 1) { return 0 }

    Write-Host ''
    Write-Host $Prompt
    for ($i = 0; $i -lt $Launchers.Count; $i++) {
        Write-Host "  $($i + 1)) Claude $($Launchers[$i].Label)"
    }

    $answer = if ($env:CLAUDE_LAUNCHERS_PROFILE_CHOICE) {
        $env:CLAUDE_LAUNCHERS_PROFILE_CHOICE
    }
    else {
        Read-Prompt 'Select profile: '
    }

    if ($answer -notmatch '^\d+$') {
        Write-Error "ERROR: unknown profile selection: $answer"
        exit 1
    }
    $index = [int]$answer - 1
    if ($index -lt 0 -or $index -ge $Launchers.Count) {
        Write-Error "ERROR: unknown profile selection: $answer"
        exit 1
    }
    return $index
}

function Show-ExistingSetupMenu {
    $launchers = @(Get-GeneratedLaunchers)
    if ($launchers.Count -eq 0) { return $false }

    Write-Host ''
    Write-Host 'Claude Profile Switcher is already set up.'
    Write-Host ''
    Show-GeneratedLaunchers $launchers
    Write-Host ''
    Write-Host 'What would you like to do next?'
    Write-Host '  1) Open a generated Claude profile'
    Write-Host '  2) Open all generated Claude profiles'
    Write-Host '  3) Open the launchers folder'
    Write-Host '  4) Create another profile'
    Write-Host '  5) Fix wrong account / start fresh for a generated profile'
    Write-Host '  6) Remove generated launchers (keep local sign-ins)'
    Write-Host '  7) Remove launchers AND local generated profile data'
    Write-Host '  8) Cancel'

    $choice = if ($env:CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE) {
        $env:CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE
    }
    elseif (Test-CanPrompt) {
        Read-Prompt 'Select [1]: ' '1'
    }
    else {
        Write-Host ''
        Write-Host "Run a generated launcher from $Script:LaunchersDir, or run clean to remove setup."
        return $true
    }

    switch ($choice) {
        '1' {
            $idx = Select-GeneratedLauncher 'Which profile should I open?' $launchers
            Write-Host "Opening Claude $($launchers[$idx].Label)..."
            Open-Shortcut $launchers[$idx].ShortcutPath
        }
        '2' {
            foreach ($launcher in $launchers) {
                Write-Host "Opening Claude $($launcher.Label)..."
                Open-Shortcut $launcher.ShortcutPath
            }
        }
        '3' {
            Write-Host "Opening launchers folder: $Script:LaunchersDir"
            Open-LaunchersFolder
        }
        '4' {
            $names = if ($env:CLAUDE_LAUNCHERS_NEW_PROFILE_NAMES) {
                $env:CLAUDE_LAUNCHERS_NEW_PROFILE_NAMES
            }
            elseif (Test-CanPrompt) {
                Write-Host 'Enter profile names separated by spaces (example: ClientA ClientB)'
                Read-Prompt 'Profiles: '
            }
            else {
                Write-Host "Run create ProfileName to create another profile."
                return $true
            }
            Invoke-CreateSetup @($names -split '\s+')
        }
        '5' {
            $idx = Select-GeneratedLauncher 'Which profile should start fresh?' $launchers
            Start-FreshGeneratedProfile $launchers[$idx]
        }
        '6' { Invoke-CleanSetup }
        '7' { Invoke-CleanSetup -Purge }
        '8' { Write-Host 'Cancelled. Nothing changed.' }
        default {
            Write-Error "ERROR: unknown selection: $choice"
            exit 1
        }
    }
    return $true
}

function Get-DesktopPath {
    if ($env:CLAUDE_LAUNCHERS_DESKTOP) {
        return $env:CLAUDE_LAUNCHERS_DESKTOP
    }
    return [Environment]::GetFolderPath('Desktop')
}

function New-DesktopShortcut {
    param(
        [string]$SourceShortcut,
        [string]$Name
    )

    $desktop = Get-DesktopPath
    if (-not (Test-Path -LiteralPath $desktop)) {
        New-Item -ItemType Directory -Path $desktop -Force | Out-Null
    }
    $dest = Join-Path $desktop "$Name.lnk"
    Copy-Item -LiteralPath $SourceShortcut -Destination $dest -Force
    $marker = Get-MarkerPath $SourceShortcut
    if (Test-Path -LiteralPath $marker) {
        Copy-Item -LiteralPath $marker -Destination (Get-MarkerPath $dest) -Force
    }
    Write-Host "     desktop launcher: $dest"
}

function New-ProfileLauncher {
    param(
        [string]$Label,
        [string]$ClaudeExe,
        [bool]$DesktopAliases
    )

    $name = Get-LauncherName $Label
    $dirSlug = Get-ProfileSlug $Label
    $shortcut = Get-ShortcutPath $Label
    $data = Get-ProfileDataPath $dirSlug

    if (Test-Path -LiteralPath $data) {
        Write-Host "  -> profile '$Label' already has data at ~/$dirSlug (keeping it)"
    }
    else {
        Write-Host "  -> creating new profile '$Label' at ~/$dirSlug"
    }

    Remove-Item -LiteralPath $shortcut -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Get-MarkerPath $shortcut) -Force -ErrorAction SilentlyContinue

    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($shortcut)
    $link.TargetPath = $ClaudeExe
    $link.Arguments = "--user-data-dir=`"$data`""
    $link.WorkingDirectory = Split-Path -Parent $ClaudeExe
    $link.Description = "Claude Desktop - $Label profile"
    $link.IconLocation = "$ClaudeExe,0"
    $link.Save()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($link) | Out-Null
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null

    Write-MarkerFile $shortcut $Label $dirSlug
    Write-Host "     built launcher: $shortcut"

    if ($DesktopAliases) {
        New-DesktopShortcut $shortcut $name
    }
}

function Show-Usage {
    @'
make_claude_launchers.ps1 - manage isolated Claude Desktop profiles

Commands:
  create [options] [labels...]   Create one launcher per label
  clean                Remove generated launchers (keeps your profile data)
  clean --purge        Remove generated launchers AND their profile data
  help                 Show this help

Interactive default:
  Keeps your existing Claude login as-is and creates only the missing second
  profile (Work or Personal).

Create options:
  --desktop            Also copy clickable launchers to your Desktop
  --no-desktop         Do not copy launchers to your Desktop
  --launch             Launch the created profile(s) after setup
  --no-launch          Do not launch profiles after setup
  --yes                Skip the interactive menu (assumes existing Work, creates Personal)

Examples:
  .\make_claude_launchers.ps1
  .\make_claude_launchers.ps1 create Work Personal Clients
  .\make_claude_launchers.ps1 create --desktop --launch Personal
  .\make_claude_launchers.ps1 clean --purge

Note:
  Your normal Claude install keeps its current login. Generated launchers open
  isolated profiles via --user-data-dir. Running profiles may appear as
  separate same-looking Claude taskbar icons.

  create requires Claude Desktop. clean and help work without it.
  If Claude is in an unusual location, set CLAUDE_LAUNCHERS_CLAUDE_EXE.
'@ | Write-Host
}

function Invoke-CreateSetup {
    param([string[]]$SetupArgs)

    New-Item -ItemType Directory -Path $Script:LaunchersDir -Force | Out-Null

    $desktopAliases = $false
    $launchAfterCreate = $false
    $skipInteractive = $false
    $existingProfileLabel = ''
    $rawLabels = @()

    $i = 0
    while ($i -lt $SetupArgs.Count) {
        switch ($SetupArgs[$i]) {
            '--desktop' { $desktopAliases = $true; $i++; continue }
            '--no-desktop' { $desktopAliases = $false; $i++; continue }
            '--launch' { $launchAfterCreate = $true; $i++; continue }
            '--no-launch' { $launchAfterCreate = $false; $i++; continue }
            { $_ -in '--yes', '-y' } { $skipInteractive = $true; $i++; continue }
            '--' {
                $i++
                while ($i -lt $SetupArgs.Count) {
                    $rawLabels += $SetupArgs[$i]
                    $i++
                }
                break
            }
            { $_.StartsWith('--') } {
                Write-Error "ERROR: unknown create option: $($SetupArgs[$i])"
                exit 1
            }
            default {
                $rawLabels += $SetupArgs[$i]
                $i++
            }
        }
    }

    if ($rawLabels.Count -eq 0 -and -not $skipInteractive) {
        if (Show-ExistingSetupMenu) { return }
    }

    $claudeExe = Require-ClaudeDesktop

    if ($rawLabels.Count -eq 0) {
        if (-not $skipInteractive -and (Test-CanPrompt)) {
            Write-Host ''
            Write-Host 'Claude Profile Switcher for Windows'
            Write-Host 'Your existing Claude app keeps its current login.'
            Write-Host 'This script adds a second isolated profile for your other account.'
            Write-Host ''
            Write-Host 'Which account is your current Claude already signed into?'
            Write-Host '  1) Work / Company'
            Write-Host '  2) Personal'
            Write-Host '  3) Custom profile names'
            Write-Host '  4) Remove generated launchers (keep profile data)'
            Write-Host '  5) Remove generated launchers AND profile data'
            Write-Host '  6) Cancel'

            switch (Read-Prompt 'Select [1]: ' '1') {
                { $_ -in '', '1' } {
                    $existingProfileLabel = 'Work'
                    $rawLabels = @('Personal')
                    Write-Host ''
                    Write-Host 'Your existing Claude stays as Work / Company.'
                    Write-Host 'I will create Claude Personal for your personal account.'
                }
                '2' {
                    $existingProfileLabel = 'Personal'
                    $rawLabels = @('Work')
                    Write-Host ''
                    Write-Host 'Your existing Claude stays as Personal.'
                    Write-Host 'I will create Claude Work for your work / company account.'
                }
                '3' {
                    Write-Host 'Enter profile names separated by spaces (example: Work Personal ClientA)'
                    $rawLabels = (Read-Prompt 'Profiles: ') -split '\s+'
                }
                '4' {
                    Write-Host ''
                    Invoke-CleanSetup
                    exit 0
                }
                '5' {
                    Write-Host ''
                    Invoke-CleanSetup -Purge
                    exit 0
                }
                '6' {
                    Write-Host 'Cancelled. No launchers were created.'
                    exit 0
                }
                default {
                    Write-Error 'ERROR: unknown selection.'
                    exit 1
                }
            }

            if ($rawLabels.Count -gt 0) {
                Write-Host ''
                switch (Read-Prompt 'Create Desktop launchers too? [Y/n] ' 'Y') {
                    { $_ -match '^(n|no)$' } { $desktopAliases = $false }
                    default { $desktopAliases = $true }
                }
                Write-Host ''

                $launchPrompt = if ($rawLabels.Count -eq 1) {
                    'Launch the new Claude profile now? [Y/n] '
                }
                else {
                    'Launch the new Claude profile(s) now? [Y/n] '
                }
                switch (Read-Prompt $launchPrompt 'Y') {
                    { $_ -match '^(n|no)$' } { $launchAfterCreate = $false }
                    default { $launchAfterCreate = $true }
                }
                Write-Host ''
            }
        }
        else {
            if ($env:CLAUDE_LAUNCHERS_ONBOARDING_EXISTING -eq 'Personal') {
                $existingProfileLabel = 'Personal'
                $rawLabels = @('Work')
            }
            else {
                $existingProfileLabel = 'Work'
                $rawLabels = @('Personal')
            }
        }
    }

    $labels = @()
    $seenDirs = @{}
    foreach ($label in $rawLabels) {
        $cleanLabel = Get-TrimmedLabel $label
        if (-not (Test-ValidLabel $cleanLabel)) { continue }
        $dirSlug = Get-ProfileSlug $cleanLabel
        if ($seenDirs.ContainsKey($dirSlug)) {
            Write-Error @"
ERROR: duplicate profile data directory from labels: $cleanLabel -> ~/$dirSlug
       Choose labels that map to different profile names.
"@
            exit 1
        }
        $seenDirs[$dirSlug] = $true
        $labels += $cleanLabel
    }

    if ($labels.Count -eq 0) {
        Write-Error 'ERROR: no valid profile labels were provided.'
        exit 1
    }

    Write-Host "Found Claude at: $claudeExe"

    if ($existingProfileLabel -and $labels.Count -eq 1) {
        Reset-OnboardingProfileDataIfNeeded $labels[0] (Get-ProfileSlug $labels[0])
    }

    Write-Host "Creating $($labels.Count) launcher(s)..."
    foreach ($label in $labels) {
        New-ProfileLauncher -Label $label -ClaudeExe $claudeExe -DesktopAliases $desktopAliases
    }

    if ($launchAfterCreate) {
        Write-Host ''
        if ($labels.Count -eq 1) {
            Write-Host 'Launching your new Claude profile...'
        }
        else {
            Write-Host 'Launching your new Claude profile(s)...'
        }
        foreach ($label in $labels) {
            Write-Host "  -> Claude $label"
            Open-Shortcut (Get-ShortcutPath $label)
        }
    }

    Write-Host ''
    Write-Host 'Done.'
    if ($existingProfileLabel -and $labels.Count -eq 1) {
        $label = $labels[0]
        Write-Host "Your existing Claude remains your $(Get-ProfileDisplayName $existingProfileLabel) profile."
        Write-Host "I created Claude $label for your $(Get-ProfileDisplayName $label) account."
        Write-Host ''
        if ($launchAfterCreate) {
            if (Test-ProfileDataInitialized (Get-ProfileSlug $label)) {
                Write-Host "Next: check the Claude $label window that just opened."
                Write-Host 'If it shows the wrong account, sign out there or re-run this script and choose start fresh.'
                Write-Host "If it is a fresh profile, sign in with your $(Get-ProfileDisplayName $label) account"
                Write-Host 'and connect the matching email, calendar, Slack, Notion, or other tools there.'
            }
            else {
                Write-Host "Next: in the Claude $label window that just opened, sign in with your $(Get-ProfileDisplayName $label) account,"
                Write-Host 'then connect the matching email, calendar, Slack, Notion, or other tools there.'
            }
        }
        else {
            Write-Host "Next: open Claude $label from $Script:LaunchersDir, sign in with your $(Get-ProfileDisplayName $label) account,"
            Write-Host 'then connect the matching email, calendar, Slack, Notion, or other tools there.'
        }
        Write-Host ''
        Write-Host "Keep using your normal Claude app for $(Get-ProfileDisplayName $existingProfileLabel)."
        Write-Host "Use Claude $label when you want the other account and tools."
    }
    else {
        Write-Host "Launchers are in: $Script:LaunchersDir"
        if ($desktopAliases) {
            Write-Host 'Desktop launchers were also created.'
        }
        if ($launchAfterCreate) {
            Write-Host ''
            Write-Host 'Next: in each new Claude window, sign in with the account for that profile'
            Write-Host 'and connect the matching tools there.'
        }
        else {
            Write-Host 'Open each launcher and sign in with the account and tools you want isolated.'
        }
    }

    Write-Host ''
    Write-Host 'Taskbar note: running profiles may appear as separate same-looking Claude icons.'
    if ($labels.Count -eq 1) {
        Write-Host "Tip: pin Claude $($labels[0]) to your taskbar or Start menu for quick access."
    }
    else {
        Write-Host 'Tip: pin the launchers to your taskbar. Each opens an isolated Claude profile.'
    }

    if (-not $launchAfterCreate -and $env:CLAUDE_LAUNCHERS_NO_OPEN -ne '1') {
        Open-LaunchersFolder
    }
}

function Invoke-CleanSetup {
    param([switch]$Purge)

    New-Item -ItemType Directory -Path $Script:LaunchersDir -Force | Out-Null

    $found = $false
    Get-ChildItem -Path $Script:LaunchersDir -Filter 'Claude *.lnk' -File -ErrorAction SilentlyContinue | ForEach-Object {
        $marker = Get-MarkerPath $_.FullName
        if (-not (Test-Path -LiteralPath $marker)) {
            Write-Host "  skip (not a generated launcher): $($_.Name)"
            return
        }

        $found = $true
        $base = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        $label = Read-MarkerValue $marker 'label'
        if ([string]::IsNullOrWhiteSpace($label)) {
            $label = $base.Substring(7)
        }
        $data = Get-ProfileDataPath (Get-ProfileSlug $label)

        Write-Host "Removing launcher: $base.lnk"
        Remove-Item -LiteralPath $_.FullName -Force
        Remove-Item -LiteralPath $marker -Force

        if ($Purge) {
            if (Test-Path -LiteralPath $data) {
                $ans = if ($env:CLAUDE_LAUNCHERS_PURGE_ANSWER) {
                    $env:CLAUDE_LAUNCHERS_PURGE_ANSWER
                }
                elseif (Test-CanPrompt) {
                    Write-Host -NoNewline "  Delete profile data at $data ? [y/N] "
                    Read-Host
                }
                else {
                    Write-Host "  Delete profile data at $data ? [y/N]"
                    ''
                }
                if ($ans -in 'y', 'Y') {
                    Remove-Item -LiteralPath $data -Recurse -Force
                    Write-Host "  deleted $data"
                }
                else {
                    Write-Host "  kept $data"
                }
            }
        }
        elseif (Test-Path -LiteralPath $data) {
            Write-Host "  (kept profile data at $data)"
        }
    }

    if (-not $found) {
        Write-Host "No generated Claude launchers found in $Script:LaunchersDir. Nothing to clean."
        return
    }

    Write-Host ''
    Write-Host 'Cleaned - back to standard: only the normal Claude install remains.'
    if (-not $Purge) {
        Write-Host 'Profile data (~/Claude*) was kept. To remove it too, run: clean --purge'
    }
    Open-LaunchersFolder
}

function Get-RemainingArgs {
    param(
        [string[]]$All,
        [int]$StartIndex = 1
    )
    if ($All.Count -le $StartIndex) { return @() }
    return @($All[$StartIndex..($All.Count - 1)])
}

function Invoke-Main {
    param([string[]]$MainArgs)

    Require-Windows

    $cmd = if ($MainArgs.Count -gt 0) { $MainArgs[0] } else { 'create' }
    switch ($cmd) {
        'clean' {
            $rest = @(Get-RemainingArgs $MainArgs)
            $purge = $false
            foreach ($arg in $rest) {
                if ($arg -eq '--purge') { $purge = $true }
                else { throw "ERROR: unknown clean option: $arg" }
            }
            if ($purge) { Invoke-CleanSetup -Purge }
            else { Invoke-CleanSetup }
        }
        'create' {
            Invoke-CreateSetup @(Get-RemainingArgs $MainArgs)
        }
        { $_ -in 'help', '-h', '--help' } {
            Show-Usage
        }
        default {
            Invoke-CreateSetup $MainArgs
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main @($ScriptArguments)
}
