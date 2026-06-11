# Integration tests for make_claude_launchers.ps1 (Windows)
# Runs in an isolated temp USERPROFILE — never touches your real Claude setup.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib\harness.ps1')

Require-WindowsForTests

Write-Host 'Running claude-fix tests'
Write-Host "Script: $Script:ScriptPath"
Write-Host "Platform: Windows $([Environment]::OSVersion.Version)"

function Test-ScriptSyntax {
    Start-Test 'script passes PowerShell parser check'
    Assert-True 'parser reports no errors' { Test-ScriptParses }
}

function Test-SlugMapping {
    Start-Test 'slug() maps labels to safe data-dir names'
    Assert-Equal 'ClaudeWork' (Get-SlugViaScript 'Work') 'Work -> ClaudeWork'
    Assert-Equal 'ClaudePersonal' (Get-SlugViaScript 'Personal') 'Personal -> ClaudePersonal'
    Assert-Equal 'ClaudeBigClient' (Get-SlugViaScript 'Big Client') 'spaces removed'
    Assert-Equal 'ClaudeClientA' (Get-SlugViaScript 'client-a!!!') 'hyphens become word breaks'
    Assert-Equal 'Claude123' (Get-SlugViaScript '123') 'numeric label'
}

function Test-Help {
    Start-Test 'help prints usage and taskbar limitation'
    Initialize-Sandbox
    $result = Capture-Script @('help')
    Assert-Contains $result.Output 'Commands:' 'shows commands section'
    Assert-Contains $result.Output 'clean --purge' 'documents purge'
    Assert-Contains $result.Output '--desktop' 'documents Desktop shortcuts option'
    Assert-Contains $result.Output '--launch' 'documents launch option'
    Assert-Contains $result.Output 'existing Claude login' 'documents existing profile model'
    Assert-Contains $result.Output 'same-looking Claude taskbar icons' 'documents taskbar icon limitation'
    Remove-Sandbox
}

function Test-HelpAliases {
    Start-Test 'help aliases (-h, --help)'
    Initialize-Sandbox
    Assert-Contains (Capture-Script @('-h')).Output 'make_claude_launchers.ps1' '-h works'
    Assert-Contains (Capture-Script @('--help')).Output 'create [options]' '--help works'
    Remove-Sandbox
}

function Test-PipedExecution {
    Start-Test 'piped execution (iex-style dot-source) does not crash on dispatch'
    Initialize-Sandbox
    New-MockClaude | Out-Null
    $result = Capture-ScriptPiped @('help')
    Assert-Equal '0' "$($result.ExitCode)" 'piped invocation exits 0'
    Assert-Contains $result.Output 'make_claude_launchers.ps1' 'piped invocation runs main dispatch'
    Remove-Sandbox
}

function Test-NotInstalledCreateFails {
    Start-Test '[not installed] create exits with clear error'
    Initialize-Sandbox
    Assert-False 'Claude absent in sandbox' { Test-ClaudeInstalledInSandbox }
    $result = Capture-Script @('create', '--yes')
    Assert-Equal '1' "$($result.ExitCode)" 'exits 1'
    Assert-Contains $result.Output 'Claude Desktop is not installed' 'meaningful error'
    Assert-Contains $result.Output 'claude.ai/download' 'includes download link'
    Remove-Sandbox
}

function Test-NotInstalledImplicitCreateFails {
    Start-Test '[not installed] bare labels (implicit create) also fail'
    Initialize-Sandbox
    $result = Capture-Script @('Work', 'Personal')
    Assert-Equal '1' "$($result.ExitCode)" 'implicit create exits 1 without Claude'
    Assert-Contains $result.Output 'Claude Desktop is not installed' 'meaningful error'
    Remove-Sandbox
}

function Test-NotInstalledCleanStillWorks {
    Start-Test '[not installed] clean still works'
    Initialize-Sandbox
    New-GeneratedLauncherStub 'Work'
    $result = Capture-Script @('clean')
    Assert-Equal '0' "$($result.ExitCode)" 'clean exits 0 without Claude installed'
    Assert-Contains $result.Output 'Removing launcher: Claude Work.lnk' 'removes launcher'
    Assert-FileMissing (Get-LauncherShortcut 'Work') 'launcher removed'
    Remove-Sandbox
}

function Test-NotInstalledHelpStillWorks {
    Start-Test '[not installed] help still works'
    Initialize-Sandbox
    Assert-False 'Claude absent in sandbox' { Test-ClaudeInstalledInSandbox }
    $result = Capture-Script @('help')
    Assert-Equal '0' "$($result.ExitCode)" 'help exits 0 without Claude installed'
    Assert-Contains $result.Output 'Commands:' 'shows usage'
    Assert-Contains $result.Output 'CLAUDE_LAUNCHERS_CLAUDE_EXE' 'documents custom Claude path'
    Remove-Sandbox
}

function Test-NotInstalledNoArgsFailsEarly {
    Start-Test '[not installed] no-args fails before onboarding'
    Initialize-Sandbox
    $result = Capture-ScriptNoArgs
    Assert-Equal '1' "$($result.ExitCode)" 'no-args exits 1 without Claude'
    Assert-Contains $result.Output 'Claude Desktop is not installed' 'meaningful error'
    Assert-NotContains $result.Output 'Which account is your current Claude already signed into?' 'skips onboarding menu'
    Assert-NotContains $result.Output 'Create Desktop launchers too?' 'skips desktop prompt'
    Remove-Sandbox
}

function Test-NotInstalledManagementMenuWithoutClaude {
    Start-Test '[not installed] management menu works when launchers exist'
    Initialize-Sandbox
    New-GeneratedLauncherStub 'Personal'
    $env:CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE = '8'
    $result = Capture-Script @('create')
    Assert-Equal '0' "$($result.ExitCode)" 'cancel exits 0 without Claude'
    Assert-Contains $result.Output 'already set up' 'shows management menu'
    Assert-NotContains $result.Output 'Claude Desktop is not installed' 'does not require Claude to cancel'
    Remove-Sandbox
}

function Test-NotInstalledManagementCreateAnotherFails {
    Start-Test '[not installed] management menu create another profile fails clearly'
    Initialize-Sandbox
    New-GeneratedLauncherStub 'Personal'
    $env:CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE = '4'
    $env:CLAUDE_LAUNCHERS_NEW_PROFILE_NAMES = 'ClientA'
    $result = Capture-Script @('create')
    Assert-Equal '1' "$($result.ExitCode)" 'create another exits 1 without Claude'
    Assert-Contains $result.Output 'Claude Desktop is not installed' 'meaningful error'
    Assert-Contains $result.Output 'CLAUDE_LAUNCHERS_CLAUDE_EXE' 'suggests custom path env var'
    Remove-Sandbox
}

function Test-NotInstalledErrorMentionsClaudeExeEnv {
    Start-Test '[not installed] error suggests CLAUDE_LAUNCHERS_CLAUDE_EXE'
    Initialize-Sandbox
    $result = Capture-Script @('create', '--yes')
    Assert-Contains $result.Output 'CLAUDE_LAUNCHERS_CLAUDE_EXE' 'mentions env var'
    Assert-Contains $result.Output 'claude.ai/download' 'includes download link'
    Remove-Sandbox
}

function Test-InstalledNotRunningCreateSucceeds {
    Start-Test '[installed, not running] create succeeds and does not launch Claude'
    Initialize-Sandbox
    New-MockClaudeRunnable | Out-Null
    $marker = Join-Path $Script:Sandbox 'claude-launched.marker'
    $env:CLAUDE_MOCK_LAUNCHED_MARKER = $marker
    Assert-False 'mock Claude process not started yet' { Test-Path -LiteralPath $marker }
    Capture-Script @('create', '--yes', '--no-desktop', '--no-launch', 'Work') | Out-Null
    Assert-FileExists (Get-LauncherShortcut 'Work') 'launcher created'
    Assert-FileMissing $marker 'Claude binary was never executed during create'
    Remove-Sandbox
}

function Test-InstalledRunningCreateAndCleanDoNotKillClaude {
    Start-Test '[installed, running] create/clean never kill the running Claude process'
    Initialize-Sandbox
    New-MockClaudeRunnable | Out-Null
    $marker = Join-Path $Script:Sandbox 'claude-launched.marker'
    Start-MockClaudeProcess $marker
    Assert-True 'mock Claude process is running' { Test-MockClaudeProcessRunning }
    Capture-Script @('create', '--yes', '--no-desktop', '--no-launch', 'Work', 'Personal') | Out-Null
    Capture-Script @('clean') | Out-Null
    Assert-True 'Claude process survived create + clean' { Test-MockClaudeProcessRunning }
    Assert-FileExists $marker 'launch marker still present'
    Remove-Sandbox
}

function Test-CreateDefaultProfiles {
    Start-Test 'default create keeps existing Work and adds Personal launcher'
    Initialize-Sandbox
    New-MockClaude | Out-Null
    $result = Capture-Script @('create', '--yes', '--no-desktop', '--no-launch')
    Assert-Contains $result.Output 'Creating 1 launcher(s)' 'creates one launcher'
    Assert-Contains $result.Output 'Your existing Claude remains your Work / Company profile.' 'explains existing profile'
    Assert-Contains $result.Output 'I created Claude Personal' 'creates Personal profile'
    Assert-FileMissing (Get-LauncherShortcut 'Work') 'does not create Work launcher'
    Assert-FileExists (Get-LauncherShortcut 'Personal') 'Personal launcher exists'
    Remove-Sandbox
}

function Test-OnboardingExistingPersonalCreatesWork {
    Start-Test 'onboarding with existing Personal creates Work launcher only'
    Initialize-Sandbox
    New-MockClaude | Out-Null
    $env:CLAUDE_LAUNCHERS_ONBOARDING_EXISTING = 'Personal'
    $result = Capture-Script @('create', '--yes', '--no-desktop', '--no-launch')
    Assert-Contains $result.Output 'Creating 1 launcher(s)' 'creates one launcher'
    Assert-Contains $result.Output 'Your existing Claude remains your Personal profile.' 'explains existing profile'
    Assert-FileExists (Get-LauncherShortcut 'Work') 'Work launcher created'
    Assert-FileMissing (Get-LauncherShortcut 'Personal') 'does not create Personal launcher'
    Remove-Sandbox
}

function Test-DesktopShortcutsOption {
    Start-Test 'create --desktop creates Desktop launchers'
    Initialize-Sandbox
    New-MockClaude | Out-Null
    Capture-Script @('create', '--desktop', '--no-launch', 'Work', 'Personal') | Out-Null
    Assert-FileExists (Join-Path (Get-SandboxDesktop) 'Claude Work.lnk') 'Work Desktop launcher'
    Assert-FileExists (Join-Path (Get-SandboxDesktop) 'Claude Personal.lnk') 'Personal Desktop launcher'
    Remove-Sandbox
}

function Test-NoDesktopOption {
    Start-Test 'create --no-desktop avoids Desktop aliases'
    Initialize-Sandbox
    New-MockClaude | Out-Null
    Capture-Script @('create', '--no-desktop', '--no-launch', 'Work', 'Personal') | Out-Null
    Assert-FileMissing (Join-Path (Get-SandboxDesktop) 'Claude Work.lnk') 'no Work Desktop launcher'
    Assert-FileMissing (Join-Path (Get-SandboxDesktop) 'Claude Personal.lnk') 'no Personal Desktop launcher'
    Remove-Sandbox
}

function Test-LaunchOptionPrintsFirstTimeSetup {
    Start-Test 'create --launch starts onboarding profile and explains next login step'
    Initialize-Sandbox
    New-MockClaude | Out-Null
    $result = Capture-Script @('create', '--yes', '--no-desktop', '--launch')
    Assert-Contains $result.Output 'Launching your new Claude profile' 'reports launch step'
    Assert-Contains $result.Output 'Claude Personal' 'mentions Personal profile launch'
    Assert-Contains $result.Output 'sign in with your Personal account' 'explains separate login'
    Assert-Contains $result.Output 'Keep using your normal Claude app for Work / Company.' 'explains existing profile usage'
    Remove-Sandbox
}

function Test-LaunchOptionMultiProfile {
    Start-Test 'create --launch with explicit labels supports multiple profiles'
    Initialize-Sandbox
    New-MockClaude | Out-Null
    $result = Capture-Script @('create', '--launch', '--no-desktop', 'Work', 'Personal')
    Assert-Contains $result.Output 'Launching your new Claude profile(s)' 'reports launch step'
    Assert-Contains $result.Output 'sign in with the account for that profile' 'explains multi-profile login'
    Remove-Sandbox
}

function Test-NoLaunchOptionKeepsProfilesClosed {
    Start-Test 'create --no-launch leaves profiles closed and explains next step'
    Initialize-Sandbox
    New-MockClaude | Out-Null
    $result = Capture-Script @('create', '--yes', '--no-desktop', '--no-launch')
    Assert-NotContains $result.Output 'Launching your new Claude profile' 'does not launch profiles'
    Assert-Contains $result.Output "Next: open Claude Personal from $(Get-SandboxApplications)" 'explains later login'
    Remove-Sandbox
}

function Test-NoArgsDefaultsToCreate {
    Start-Test 'running with no arguments adds the missing Personal profile'
    Initialize-Sandbox
    New-MockClaude | Out-Null
    $result = Capture-ScriptNoArgs
    Assert-Equal '0' "$($result.ExitCode)" 'no-args command exits 0'
    Assert-Contains $result.Output 'Creating 1 launcher(s)' 'prints create progress'
    Assert-FileMissing (Get-LauncherShortcut 'Work') 'Work launcher not created'
    Assert-FileExists (Get-LauncherShortcut 'Personal') 'Personal launcher created'
    Remove-Sandbox
}

function Test-ExistingLaunchersShowManagementMenu {
    Start-Test 'existing generated launchers show management menu instead of onboarding'
    Initialize-Sandbox
    New-GeneratedLauncherStub 'Personal'
    $env:CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE = '8'
    $result = Capture-Script @('create')
    Assert-Contains $result.Output 'already set up' 'detects existing setup'
    Assert-Contains $result.Output 'Claude Personal' 'lists existing launcher'
    Assert-Contains $result.Output 'What would you like to do next?' 'shows next-step menu'
    Assert-NotContains $result.Output 'Which account is your current Claude already signed into?' 'does not re-run onboarding'
    Remove-Sandbox
}

function Test-ManagementMenuOpensExistingProfile {
    Start-Test 'management menu opens selected generated profile'
    Initialize-Sandbox
    New-GeneratedLauncherStub 'Personal'
    $env:CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE = '1'
    $result = Capture-Script @('create')
    Assert-Contains $result.Output 'Opening Claude Personal' 'opens generated launcher'
    Assert-NotContains $result.Output 'Creating 1 launcher' 'does not rebuild launcher'
    Remove-Sandbox
}

function Test-ManagementMenuCreateAnotherProfile {
    Start-Test 'management menu can create another profile'
    Initialize-Sandbox
    New-MockClaude | Out-Null
    New-GeneratedLauncherStub 'Personal'
    $env:CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE = '4'
    $env:CLAUDE_LAUNCHERS_NEW_PROFILE_NAMES = 'ClientA'
    $result = Capture-Script @('create', '--no-desktop', '--no-launch')
    Assert-Contains $result.Output 'Creating 1 launcher(s)' 'creates requested extra profile'
    Assert-FileExists (Get-LauncherShortcut 'ClientA') 'ClientA launcher created'
    Remove-Sandbox
}

function Test-ManagementMenuStartFreshProfile {
    Start-Test 'management menu can clear local sign-in for generated profile'
    Initialize-Sandbox
    New-GeneratedLauncherStub 'Personal'
    $data = Join-Path $env:USERPROFILE 'ClaudePersonal'
    New-Item -ItemType Directory -Path $data -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $data 'config.json') -Value '{"oauth:tokenCache":"stale"}' -Encoding UTF8
    $env:CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE = '5'
    $env:CLAUDE_LAUNCHERS_RESET_PROFILE_ANSWER = 'y'
    $result = Capture-Script @('create')
    Assert-Contains $result.Output 'does NOT delete your Claude account' 'uses safe wording'
    Assert-Contains $result.Output 'cleared local sign-in for Claude Personal' 'clears local sign-in'
    Assert-FileMissing $data 'local profile directory removed'
    Remove-Sandbox
}

function Test-CreateCustomAndImplicitLabels {
    Start-Test 'create accepts custom labels and implicit create'
    Initialize-Sandbox
    New-MockClaude | Out-Null
    Capture-Script @('create', '--no-desktop', '--no-launch', 'Alpha', 'Beta') | Out-Null
    Capture-Script @('--no-desktop', '--no-launch', 'Solo') | Out-Null
    Assert-FileExists (Get-LauncherShortcut 'Alpha') 'Alpha launcher'
    Assert-FileExists (Get-LauncherShortcut 'Beta') 'Beta launcher'
    Assert-FileExists (Get-LauncherShortcut 'Solo') 'implicit create works'
    Remove-Sandbox
}

function Test-LauncherShortcutPayload {
    Start-Test 'launcher embeds isolated --user-data-dir path'
    Initialize-Sandbox
    New-MockClaude | Out-Null
    Capture-Script @('create', '--no-desktop', '--no-launch', 'Work') | Out-Null
    $info = Get-ShortcutInfo (Get-LauncherShortcut 'Work')
    Assert-Contains $info.Arguments '--user-data-dir=' 'passes user-data-dir flag'
    Assert-Contains $info.Arguments (Join-Path $env:USERPROFILE 'ClaudeWork') 'uses absolute profile dir'
    Assert-NotContains $info.Arguments '$env:USERPROFILE' 'does not rely on runtime env expansion'
    Remove-Sandbox
}

function Test-OnboardingResetProfileData {
    Start-Test 'onboarding can reset previously used profile data before launch'
    Initialize-Sandbox
    New-MockClaude | Out-Null
    $data = Join-Path $env:USERPROFILE 'ClaudePersonal'
    New-Item -ItemType Directory -Path $data -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $data 'config.json') -Value '{"oauth:tokenCache":"stale"}' -Encoding UTF8
    $env:CLAUDE_LAUNCHERS_RESET_PROFILE_ANSWER = 'y'
    $result = Capture-Script @('create', '--yes', '--no-desktop', '--no-launch')
    Assert-Contains $result.Output 'already has a saved sign-in' 'warns about existing profile data'
    Assert-Contains $result.Output 'does not change your normal Claude app' 'reassures user about safety'
    Assert-Contains $result.Output 'cleared local sign-in for Claude Personal' 'reports fresh start'
    Assert-FileMissing (Join-Path $data 'config.json') 'profile data removed'
    Remove-Sandbox
}

function Test-LauncherUsesClaudeIcon {
    Start-Test 'launchers reference Claude executable icon'
    Initialize-Sandbox
    $exe = New-MockClaude
    Capture-Script @('create', '--no-desktop', '--no-launch', 'Work', 'Personal') | Out-Null
    $work = Get-ShortcutInfo (Get-LauncherShortcut 'Work')
    $personal = Get-ShortcutInfo (Get-LauncherShortcut 'Personal')
    Assert-Contains $work.IconLocation $exe 'Work launcher uses source icon'
    Assert-Contains $personal.IconLocation $exe 'Personal launcher uses source icon'
    Remove-Sandbox
}

function Test-GeneratedLauncherHasMarker {
    Start-Test 'create writes ownership marker next to each generated launcher'
    Initialize-Sandbox
    New-MockClaude | Out-Null
    Capture-Script @('create', '--no-desktop', '--no-launch', 'Work') | Out-Null
    $marker = Get-LauncherMarker 'Work'
    Assert-FileExists $marker 'marker file exists'
    Assert-Contains (Get-Content -LiteralPath $marker -Raw) 'generated-by=claude-fix' 'marker identifies claude-fix'
    Remove-Sandbox
}

function Test-CreatePreservesExistingProfileData {
    Start-Test 're-create keeps existing profile data'
    Initialize-Sandbox
    New-MockClaude | Out-Null
    $data = Join-Path $env:USERPROFILE 'ClaudeWork'
    New-Item -ItemType Directory -Path $data -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $data 'keep-me.txt') -Value 'precious-chat-history' -Encoding ASCII
    Capture-Script @('create', '--no-desktop', '--no-launch', 'Work') | Out-Null
    Capture-Script @('create', '--no-desktop', '--no-launch', 'Work') | Out-Null
    Assert-FileExists (Join-Path $data 'keep-me.txt') 'profile data untouched'
    Assert-Equal 'precious-chat-history' (Get-Content -LiteralPath (Join-Path $data 'keep-me.txt') -Raw).Trim() 'data content intact'
    Remove-Sandbox
}

function Test-CreateRebuildsLauncherOnly {
    Start-Test 're-create replaces launcher shortcut and marker but not data dir'
    Initialize-Sandbox
    New-MockClaude | Out-Null
    Capture-Script @('create', '--no-desktop', '--no-launch', 'Work') | Out-Null
    $marker = Get-LauncherMarker 'Work'
    Set-Content -LiteralPath $marker -Value 'stale-marker' -Encoding ASCII
    Capture-Script @('create', '--no-desktop', '--no-launch', 'Work') | Out-Null
    Assert-Contains (Get-Content -LiteralPath $marker -Raw) 'generated-by=claude-fix' 'marker rebuilt'
    Assert-FileExists (Get-LauncherShortcut 'Work') 'launcher still valid'
    Remove-Sandbox
}

function Test-LabelValidation {
    Start-Test 'create validates labels'
    Initialize-Sandbox
    New-MockClaude | Out-Null
    Capture-Script @('create', '--no-desktop', '--no-launch', '   ', '', 'Work') | Out-Null
    Assert-FileMissing (Get-LauncherShortcut ' ') 'empty labels ignored'
    Assert-FileExists (Get-LauncherShortcut 'Work') 'valid label built'

    $result = Capture-Script @('create', '--no-desktop', '--no-launch', 'Bad/Label')
    Assert-Equal '1' "$($result.ExitCode)" 'slash label exits 1'
    Assert-Contains $result.Output 'unsupported characters' 'slash label rejected'

    $result = Capture-Script @('create', '--no-desktop', '--no-launch', 'Client A', 'client-a')
    Assert-Equal '1' "$($result.ExitCode)" 'duplicate slug exits 1'
    Assert-Contains $result.Output 'duplicate profile data directory' 'duplicate slug explained'
    Remove-Sandbox
}

function Test-QuotedClaudePaths {
    Start-Test 'create handles Claude.exe paths with apostrophes, dollars, backticks and backslashes'
    Initialize-Sandbox
    $root = Join-Path $env:USERPROFILE 'Applications\Sergej''s $Apps `tick Back\Slash\Claude'
    New-MockClaude -Root $root | Out-Null
    Capture-Script @('create', '--no-desktop', '--no-launch', 'Work') | Out-Null
    $info = Get-ShortcutInfo (Get-LauncherShortcut 'Work')
    Assert-Contains $info.TargetPath "Sergej's" 'apostrophe path segment survived'
    Assert-Contains $info.TargetPath 'Back' 'backslash path segment survived'
    Assert-Contains $info.Arguments (Join-Path $env:USERPROFILE 'ClaudeWork') 'profile dir still absolute'
    Remove-Sandbox
}

function Test-MsixPathDiscovery {
    Start-Test 'MSIX package Claude path is discovered automatically'
    Initialize-Sandbox
    $exe = New-MockClaudeMsix
    $result = Capture-Script @('create', '--no-desktop', '--no-launch', 'Work')
    Assert-Equal '0' "$($result.ExitCode)" 'create succeeds with MSIX install'
    Assert-Contains $result.Output $exe 'reports MSIX Claude path'
    Assert-FileExists (Get-LauncherShortcut 'Work') 'Work launcher created'
    Remove-Sandbox
}

function Test-CleanRemovesGeneratedLaunchers {
    Start-Test 'clean removes generated launchers'
    Initialize-Sandbox
    New-GeneratedLauncherStub 'Work'
    New-GeneratedLauncherStub 'Personal'
    $result = Capture-Script @('clean')
    Assert-Contains $result.Output 'Removing launcher: Claude Work.lnk' 'removes Work'
    Assert-Contains $result.Output 'Removing launcher: Claude Personal.lnk' 'removes Personal'
    Assert-FileMissing (Get-LauncherShortcut 'Work') 'Work launcher gone'
    Assert-FileMissing (Get-LauncherShortcut 'Personal') 'Personal launcher gone'
    Remove-Sandbox
}

function Test-CleanKeepsProfileData {
    Start-Test 'clean keeps profile data by default'
    Initialize-Sandbox
    New-GeneratedLauncherStub 'Work'
    $data = Join-Path $env:USERPROFILE 'ClaudeWork'
    New-Item -ItemType Directory -Path $data -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $data 'history.db') -Value 'keep' -Encoding ASCII
    $result = Capture-Script @('clean')
    Assert-Contains $result.Output 'kept profile data' 'reports data kept'
    Assert-FileExists (Join-Path $data 'history.db') 'profile data still on disk'
    Remove-Sandbox
}

function Test-CleanSafety {
    Start-Test 'clean skips unrelated shortcuts and plain Claude install'
    Initialize-Sandbox
    New-RealClaudeStub
    New-UnmarkedLauncherStub 'Other'
    New-GeneratedLauncherStub 'Work'
    $result = Capture-Script @('clean')
    Assert-Contains $result.Output 'skip (not a generated launcher): Claude Other.lnk' 'unmarked shortcut skipped'
    Assert-FileExists (Get-LauncherShortcut 'Other') 'unmarked shortcut left intact'
    Assert-FileExists (Join-Path (Get-SandboxApplications) 'Claude\claude.exe') 'plain Claude install intact'
    Assert-FileMissing (Get-LauncherShortcut 'Work') 'marked launcher removed'
    Remove-Sandbox
}

function Test-CleanNothingToDo {
    Start-Test 'clean with no launchers is a no-op success'
    Initialize-Sandbox
    $result = Capture-Script @('clean')
    Assert-Contains $result.Output 'Nothing to clean' 'friendly message'
    Remove-Sandbox
}

function Test-CleanPurge {
    Start-Test 'clean --purge prompts and deletes only when confirmed'
    Initialize-Sandbox
    New-GeneratedLauncherStub 'Work'
    $data = Join-Path $env:USERPROFILE 'ClaudeWork'
    New-Item -ItemType Directory -Path $data -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $data 'secret.txt') -Value 'secret' -Encoding ASCII
    Remove-Item Env:CLAUDE_LAUNCHERS_PURGE_ANSWER -ErrorAction SilentlyContinue
    $result = Capture-Script @('clean', '--purge')
    Assert-Contains $result.Output 'Delete profile data' 'asks before delete'
    Assert-Contains $result.Output "kept $data" 'declined delete'
    Assert-FileExists (Join-Path $data 'secret.txt') 'data preserved'

    New-GeneratedLauncherStub 'Work'
    $env:CLAUDE_LAUNCHERS_PURGE_ANSWER = 'y'
    $result = Capture-Script @('clean', '--purge')
    Assert-Contains $result.Output "deleted $data" 'reports deletion'
    Assert-FileMissing $data 'data directory removed'
    Remove-Sandbox
}

function Test-CleanPurgeNeverTargetsPlainClaude {
    Start-Test 'clean --purge never deletes plain Claude install or unrelated data'
    Initialize-Sandbox
    New-RealClaudeStub
    New-GeneratedLauncherStub 'Personal'
    $data = Join-Path $env:USERPROFILE 'ClaudePersonal'
    New-Item -ItemType Directory -Path $data -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $data 'secret.txt') -Value 'personal-data' -Encoding ASCII
    $env:CLAUDE_LAUNCHERS_PURGE_ANSWER = 'y'
    $result = Capture-Script @('clean', '--purge')
    Assert-Contains $result.Output "deleted $data" 'deletes generated profile data when confirmed'
    Assert-FileExists (Join-Path (Get-SandboxApplications) 'Claude\claude.exe') 'plain Claude install intact'
    Assert-NotContains $result.Output "Delete profile data at $(Join-Path (Get-SandboxApplications) 'Claude')" 'never offers to purge plain Claude'
    Remove-Sandbox
}

function Test-FullLifecycle {
    Start-Test 'full lifecycle: create -> clean -> re-create'
    Initialize-Sandbox
    New-MockClaude | Out-Null
    Capture-Script @('create', '--no-desktop', '--no-launch', 'Work', 'Personal') | Out-Null
    Assert-FileExists (Get-LauncherShortcut 'Work')
    Assert-FileExists (Get-LauncherShortcut 'Personal')
    $workData = Join-Path $env:USERPROFILE 'ClaudeWork'
    $personalData = Join-Path $env:USERPROFILE 'ClaudePersonal'
    New-Item -ItemType Directory -Path $workData, $personalData -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $workData 'x') -Value 'work-data' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $personalData 'y') -Value 'personal-data' -Encoding ASCII
    Capture-Script @('clean') | Out-Null
    Assert-FileMissing (Get-LauncherShortcut 'Work')
    Assert-FileMissing (Get-LauncherShortcut 'Personal')
    Assert-FileExists (Join-Path $workData 'x') 'work data survives clean'
    Assert-FileExists (Join-Path $personalData 'y') 'personal data survives clean'
    Capture-Script @('create', '--no-desktop', '--no-launch', 'Work') | Out-Null
    Assert-FileExists (Get-LauncherShortcut 'Work')
    Assert-Equal 'work-data' (Get-Content -LiteralPath (Join-Path $workData 'x') -Raw).Trim() 're-create reuses existing profile'
    Remove-Sandbox
}

function Test-UnsafeLabelRejected {
    Start-Test 'unsafe labels are rejected'
    Initialize-Sandbox
    New-MockClaude | Out-Null
    $result = Capture-Script @('create', '../evil')
    Assert-Equal '1' "$($result.ExitCode)" 'exits 1'
    Assert-Contains $result.Output 'unsupported characters' 'reports bad label'
    Remove-Sandbox
}

Test-ScriptSyntax
Test-SlugMapping
Test-Help
Test-HelpAliases
Test-PipedExecution
Test-NotInstalledCreateFails
Test-NotInstalledImplicitCreateFails
Test-NotInstalledCleanStillWorks
Test-NotInstalledHelpStillWorks
Test-NotInstalledNoArgsFailsEarly
Test-NotInstalledManagementMenuWithoutClaude
Test-NotInstalledManagementCreateAnotherFails
Test-NotInstalledErrorMentionsClaudeExeEnv
Test-InstalledNotRunningCreateSucceeds
Test-InstalledRunningCreateAndCleanDoNotKillClaude
Test-CreateDefaultProfiles
Test-OnboardingExistingPersonalCreatesWork
Test-DesktopShortcutsOption
Test-NoDesktopOption
Test-LaunchOptionPrintsFirstTimeSetup
Test-LaunchOptionMultiProfile
Test-NoLaunchOptionKeepsProfilesClosed
Test-NoArgsDefaultsToCreate
Test-ExistingLaunchersShowManagementMenu
Test-ManagementMenuOpensExistingProfile
Test-ManagementMenuCreateAnotherProfile
Test-ManagementMenuStartFreshProfile
Test-CreateCustomAndImplicitLabels
Test-LauncherShortcutPayload
Test-OnboardingResetProfileData
Test-LauncherUsesClaudeIcon
Test-GeneratedLauncherHasMarker
Test-CreatePreservesExistingProfileData
Test-CreateRebuildsLauncherOnly
Test-LabelValidation
Test-QuotedClaudePaths
Test-MsixPathDiscovery
Test-CleanRemovesGeneratedLaunchers
Test-CleanKeepsProfileData
Test-CleanSafety
Test-CleanNothingToDo
Test-CleanPurge
Test-CleanPurgeNeverTargetsPlainClaude
Test-FullLifecycle
Test-UnsafeLabelRejected

exit (Show-Summary)
