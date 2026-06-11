# Shared test helpers for make_claude_launchers.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Script:ScriptPath = Join-Path $Script:RepoRoot 'make_claude_launchers.ps1'
$Script:MarkerSuffix = '.claude-fix-generated'

$Script:TestsRun = 0
$Script:TestsPassed = 0
$Script:TestsFailed = 0
$Script:CurrentTest = ''

function Assert-Equal {
    param(
        [string]$Expected,
        [string]$Actual,
        [string]$Message = ''
    )
    if ($Expected -eq $Actual) {
        $Script:TestsPassed++
        Write-Host "  PASS: $(if ($Message) { $Message } else { "expected '$Expected'" })"
    }
    else {
        $Script:TestsFailed++
        Write-Error "  FAIL: $(if ($Message) { $Message } else { 'values differ' })`n        expected: '$Expected' got: '$Actual'"
    }
}

function Assert-Contains {
    param(
        [string]$Haystack,
        [string]$Needle,
        [string]$Message = ''
    )
    if ($Haystack.Contains($Needle)) {
        $Script:TestsPassed++
        Write-Host "  PASS: $(if ($Message) { $Message } else { "output contains '$Needle'" })"
    }
    else {
        $Script:TestsFailed++
        Write-Error "  FAIL: $(if ($Message) { $Message } else { "output contains '$Needle'" })`n        needle not found in output"
    }
}

function Assert-NotContains {
    param(
        [string]$Haystack,
        [string]$Needle,
        [string]$Message = ''
    )
    if (-not $Haystack.Contains($Needle)) {
        $Script:TestsPassed++
        Write-Host "  PASS: $(if ($Message) { $Message } else { "output does not contain '$Needle'" })"
    }
    else {
        $Script:TestsFailed++
        Write-Error "  FAIL: $(if ($Message) { $Message } else { "output does not contain '$Needle'" })`n        unexpected needle in output"
    }
}

function Assert-True {
    param(
        [string]$Message,
        [scriptblock]$Condition
    )
    if (& $Condition) {
        $Script:TestsPassed++
        Write-Host "  PASS: $Message"
    }
    else {
        $Script:TestsFailed++
        Write-Error "  FAIL: $Message`n        condition was false"
    }
}

function Assert-False {
    param(
        [string]$Message,
        [scriptblock]$Condition
    )
    if (-not (& $Condition)) {
        $Script:TestsPassed++
        Write-Host "  PASS: $Message"
    }
    else {
        $Script:TestsFailed++
        Write-Error "  FAIL: $Message`n        condition was true"
    }
}

function Assert-FileExists {
    param(
        [string]$Path,
        [string]$Message = "file exists: $Path"
    )
    if (Test-Path -LiteralPath $Path) {
        $Script:TestsPassed++
        Write-Host "  PASS: $Message"
    }
    else {
        $Script:TestsFailed++
        Write-Error "  FAIL: $Message`n        missing: $Path"
    }
}

function Assert-FileMissing {
    param(
        [string]$Path,
        [string]$Message = "file missing: $Path"
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        $Script:TestsPassed++
        Write-Host "  PASS: $Message"
    }
    else {
        $Script:TestsFailed++
        Write-Error "  FAIL: $Message`n        still present: $Path"
    }
}

function Start-Test {
    param([string]$Name)
    $Script:CurrentTest = $Name
    $Script:TestsRun++
    Write-Host ''
    Write-Host "== $Name =="
}

function Get-SandboxDesktop {
    if ($env:CLAUDE_LAUNCHERS_DESKTOP) {
        return $env:CLAUDE_LAUNCHERS_DESKTOP
    }
    return Join-Path $env:USERPROFILE 'Desktop'
}

function Get-SandboxApplications {
    return Join-Path $env:USERPROFILE 'Applications'
}

function Initialize-Sandbox {
    $Script:Sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("claude-fix-test-{0}" -f [guid]::NewGuid().ToString('N'))
    $Script:SandboxHome = Join-Path $Script:Sandbox 'home'
    $localAppData = Join-Path $Script:SandboxHome 'AppData\Local'
    $roamingAppData = Join-Path $Script:SandboxHome 'AppData\Roaming'
    $programData = Join-Path $Script:SandboxHome 'ProgramData'
    $desktop = Join-Path $Script:SandboxHome 'Desktop'
    New-Item -ItemType Directory -Path (Join-Path $Script:SandboxHome 'Applications') -Force | Out-Null
    New-Item -ItemType Directory -Path $localAppData -Force | Out-Null
    New-Item -ItemType Directory -Path $roamingAppData -Force | Out-Null
    New-Item -ItemType Directory -Path $programData -Force | Out-Null
    New-Item -ItemType Directory -Path $desktop -Force | Out-Null

    $env:USERPROFILE = $Script:SandboxHome
    $env:HOME = $Script:SandboxHome
    $env:LOCALAPPDATA = $localAppData
    $env:APPDATA = $roamingAppData
    $env:ProgramData = $programData
    $env:ProgramFiles = Join-Path $Script:SandboxHome 'Program Files'
    Set-Item -Path 'Env:ProgramFiles(x86)' -Value (Join-Path $Script:SandboxHome 'Program Files (x86)')
    $env:CLAUDE_LAUNCHERS_DESKTOP = $desktop
    $env:CLAUDE_LAUNCHERS_NO_OPEN = '1'
    $env:CLAUDE_LAUNCHERS_TEST_MODE = '1'
    Remove-Item Env:CLAUDE_LAUNCHERS_CLAUDE_EXE -ErrorAction SilentlyContinue
    Remove-Item Env:CLAUDE_LAUNCHERS_PURGE_ANSWER -ErrorAction SilentlyContinue
    Remove-Item Env:CLAUDE_LAUNCHERS_ONBOARDING_EXISTING -ErrorAction SilentlyContinue
    Remove-Item Env:CLAUDE_LAUNCHERS_RESET_PROFILE_ANSWER -ErrorAction SilentlyContinue
    Remove-Item Env:CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE -ErrorAction SilentlyContinue
    Remove-Item Env:CLAUDE_LAUNCHERS_PROFILE_CHOICE -ErrorAction SilentlyContinue
    Remove-Item Env:CLAUDE_LAUNCHERS_NEW_PROFILE_NAMES -ErrorAction SilentlyContinue
    Remove-Item Env:CLAUDE_MOCK_LAUNCHED_MARKER -ErrorAction SilentlyContinue
    $Script:MockClaudeProcess = $null
}

function Remove-Sandbox {
    Stop-MockClaudeProcess
    Remove-MockClaudeRegistryInstall
    if ($Script:Sandbox -and (Test-Path -LiteralPath $Script:Sandbox)) {
        Remove-Item -LiteralPath $Script:Sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item Env:CLAUDE_LAUNCHERS_DESKTOP -ErrorAction SilentlyContinue
    Remove-Item Env:APPDATA -ErrorAction SilentlyContinue
    Remove-Item Env:ProgramData -ErrorAction SilentlyContinue
    Remove-Item Env:ProgramFiles -ErrorAction SilentlyContinue
    Remove-Item 'Env:ProgramFiles(x86)' -ErrorAction SilentlyContinue
    Remove-Variable -Name Sandbox -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name SandboxHome -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name MockClaudeProcess -Scope Script -ErrorAction SilentlyContinue
}

function New-MockClaude {
    param([string]$Root = (Join-Path $env:USERPROFILE 'Applications\Claude'))

    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    $exe = Join-Path $Root 'claude.exe'
    Set-Content -LiteralPath $exe -Value 'mock' -Encoding ASCII
    $env:CLAUDE_LAUNCHERS_CLAUDE_EXE = $exe
    return $exe
}

function New-MockClaudeMsix {
    param([string]$PackageId = 'Claude_abc123')

    $pkgRoot = Join-Path $env:LOCALAPPDATA "Packages\$PackageId"
    $exeDir = Join-Path $pkgRoot 'LocalCache\Local\Claude\app-1.0.0'
    New-Item -ItemType Directory -Path $exeDir -Force | Out-Null
    $exe = Join-Path $exeDir 'claude.exe'
    Set-Content -LiteralPath $exe -Value 'mock-msix' -Encoding ASCII
    Remove-Item Env:CLAUDE_LAUNCHERS_CLAUDE_EXE -ErrorAction SilentlyContinue
    return $exe
}

function New-MockClaudeMsixNested {
    param([string]$PackageId = 'Claude_nested123')

    $pkgRoot = Join-Path $env:LOCALAPPDATA "Packages\$PackageId"
    $exeDir = Join-Path $pkgRoot 'LocalCache\Roaming\Anthropic\Claude\app-9.9.9\resources'
    New-Item -ItemType Directory -Path $exeDir -Force | Out-Null
    $exe = Join-Path $exeDir 'Claude.exe'
    Set-Content -LiteralPath $exe -Value 'mock-msix-nested' -Encoding ASCII
    Remove-Item Env:CLAUDE_LAUNCHERS_CLAUDE_EXE -ErrorAction SilentlyContinue
    return $exe
}

function New-MockClaudePrograms {
    $root = Join-Path $env:LOCALAPPDATA 'Programs\Claude'
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $exe = Join-Path $root 'Claude.exe'
    Set-Content -LiteralPath $exe -Value 'mock-programs' -Encoding ASCII
    Remove-Item Env:CLAUDE_LAUNCHERS_CLAUDE_EXE -ErrorAction SilentlyContinue
    return $exe
}

function New-MockClaudeWindowsApps {
    param([string]$PackageId = 'Claude_testpkg_x64__abc')

    $root = Join-Path $env:ProgramFiles "WindowsApps\$PackageId\app"
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $exe = Join-Path $root 'Claude.exe'
    Set-Content -LiteralPath $exe -Value 'mock-windowsapps' -Encoding ASCII
    Remove-Item Env:CLAUDE_LAUNCHERS_CLAUDE_EXE -ErrorAction SilentlyContinue
    return $exe
}

function New-MockClaudeWindowsAppsAlias {
    $aliasDir = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps'
    New-Item -ItemType Directory -Path $aliasDir -Force | Out-Null
    $exe = Join-Path $aliasDir 'Claude.exe'
    Set-Content -LiteralPath $exe -Value 'mock-alias' -Encoding ASCII
    Remove-Item Env:CLAUDE_LAUNCHERS_CLAUDE_EXE -ErrorAction SilentlyContinue
    return $exe
}

function New-MockClaudeStartMenuShortcut {
    param([string]$TargetExe)

    $menu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    New-Item -ItemType Directory -Path $menu -Force | Out-Null
    $shortcut = Join-Path $menu 'Claude.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($shortcut)
    $link.TargetPath = $TargetExe
    $link.Save()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($link) | Out-Null
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
    Remove-Item Env:CLAUDE_LAUNCHERS_CLAUDE_EXE -ErrorAction SilentlyContinue
    return $shortcut
}

function New-MockClaudeRegistryInstall {
    param([string]$InstallRoot)

    $keyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ClaudeFixTestClaude'
    if (Test-Path -LiteralPath $keyPath) {
        Remove-Item -LiteralPath $keyPath -Recurse -Force
    }
    New-Item -Path $keyPath -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name 'DisplayName' -Value 'Claude' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $keyPath -Name 'InstallLocation' -Value $InstallRoot -PropertyType String -Force | Out-Null
    Remove-Item Env:CLAUDE_LAUNCHERS_CLAUDE_EXE -ErrorAction SilentlyContinue
    return $keyPath
}

function Remove-MockClaudeRegistryInstall {
    $keyPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ClaudeFixTestClaude'
    if (Test-Path -LiteralPath $keyPath) {
        Remove-Item -LiteralPath $keyPath -Recurse -Force
    }
}

function Invoke-FindClaudeDesktopInSandbox {
    Remove-Item Env:CLAUDE_LAUNCHERS_CLAUDE_EXE -ErrorAction SilentlyContinue
    $env:CLAUDE_LAUNCHERS_TEST_MODE = '1'
    . $Script:ScriptPath
    return Find-ClaudeDesktop
}

function New-MockClaudeRunnable {
    param([string]$Root = (Join-Path $env:USERPROFILE 'Applications\Claude'))

    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    $cmd = Join-Path $Root 'claude.cmd'
    @'
@echo off
if defined CLAUDE_MOCK_LAUNCHED_MARKER echo launched>"%CLAUDE_MOCK_LAUNCHED_MARKER%"
ping -n 3600 127.0.0.1 >nul
'@ | Set-Content -LiteralPath $cmd -Encoding ASCII
    $env:CLAUDE_LAUNCHERS_CLAUDE_EXE = $cmd
    return $cmd
}

function Start-MockClaudeProcess {
    param([string]$MarkerPath = (Join-Path $Script:Sandbox 'claude-launched.marker'))

    $env:CLAUDE_MOCK_LAUNCHED_MARKER = $MarkerPath
    if (Test-Path -LiteralPath $MarkerPath) {
        Remove-Item -LiteralPath $MarkerPath -Force
    }
    $Script:MockClaudeProcess = Start-Process -FilePath $env:CLAUDE_LAUNCHERS_CLAUDE_EXE -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 300
}

function Stop-MockClaudeProcess {
    if ($Script:MockClaudeProcess -and -not $Script:MockClaudeProcess.HasExited) {
        Stop-Process -Id $Script:MockClaudeProcess.Id -Force -ErrorAction SilentlyContinue
    }
    $Script:MockClaudeProcess = $null
    Remove-Item Env:CLAUDE_MOCK_LAUNCHED_MARKER -ErrorAction SilentlyContinue
}

function Test-MockClaudeProcessRunning {
    return ($null -ne $Script:MockClaudeProcess -and -not $Script:MockClaudeProcess.HasExited)
}

function Test-ClaudeInstalledInSandbox {
    if ($env:CLAUDE_LAUNCHERS_CLAUDE_EXE -and (Test-Path -LiteralPath $env:CLAUDE_LAUNCHERS_CLAUDE_EXE)) {
        return $true
    }
    $testExe = Join-Path (Get-SandboxApplications) 'Claude\claude.exe'
    return Test-Path -LiteralPath $testExe
}

function New-GeneratedLauncherStub {
    param(
        [string]$Label,
        [string]$DirSlug = ''
    )

    if ([string]::IsNullOrWhiteSpace($DirSlug)) {
        $DirSlug = Get-SlugViaScript $Label
    }

    $launchers = Get-SandboxApplications
    $shortcut = Join-Path $launchers "Claude $Label.lnk"
    $marker = "$shortcut$Script:MarkerSuffix"
    New-Item -ItemType Directory -Path $launchers -Force | Out-Null

    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($shortcut)
    $link.TargetPath = 'C:\Windows\System32\cmd.exe'
    $link.Arguments = '/c echo stub'
    $link.Save()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($link) | Out-Null
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null

    Set-Content -LiteralPath $marker -Value @(
        'generated-by=claude-fix'
        "label=$Label"
        "data-dir=$DirSlug"
    ) -Encoding UTF8
}

function New-UnmarkedLauncherStub {
    param([string]$Label)

    $launchers = Get-SandboxApplications
    $shortcut = Join-Path $launchers "Claude $Label.lnk"
    New-Item -ItemType Directory -Path $launchers -Force | Out-Null

    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($shortcut)
    $link.TargetPath = 'C:\Windows\System32\cmd.exe'
    $link.Arguments = '/c echo stub'
    $link.Save()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($link) | Out-Null
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
}

function New-RealClaudeStub {
    $root = Join-Path (Get-SandboxApplications) 'Claude'
    New-MockClaude -Root $root | Out-Null
}

function Get-ShortcutInfo {
    param([string]$ShortcutPath)

    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($ShortcutPath)
    $info = [PSCustomObject]@{
        TargetPath    = $link.TargetPath
        Arguments     = $link.Arguments
        IconLocation  = $link.IconLocation
        WorkingDirectory = $link.WorkingDirectory
    }
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($link) | Out-Null
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null
    return $info
}

function Get-LauncherShortcut {
    param([string]$Label)
    return Join-Path (Get-SandboxApplications) "Claude $Label.lnk"
}

function Get-LauncherMarker {
    param([string]$Label)
    return "$(Get-LauncherShortcut $Label)$Script:MarkerSuffix"
}

function Invoke-Script {
    param([string[]]$ScriptArgs)

    & $Script:ScriptPath @ScriptArgs 2>&1 | ForEach-Object { "$_" }
}

function Capture-Script {
    param([string[]]$ScriptArgs)

    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $Script:ScriptPath @ScriptArgs 2>&1
        $code = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
        if ($code -eq 0 -and ($output | Where-Object { "$_" -match 'ERROR:' })) {
            $code = 1
        }
    }
    finally {
        $ErrorActionPreference = $prev
    }
    return @{
        Output   = ($output | ForEach-Object { "$_" }) -join "`n"
        ExitCode = $code
    }
}

function Capture-ScriptNoArgs {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $Script:ScriptPath 2>&1
        $code = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
        if ($code -eq 0 -and ($output | Where-Object { "$_" -match 'ERROR:' })) {
            $code = 1
        }
    }
    finally {
        $ErrorActionPreference = $prev
    }
    return @{
        Output   = ($output | ForEach-Object { "$_" }) -join "`n"
        ExitCode = $code
    }
}

function Capture-ScriptPiped {
    param([string[]]$ScriptArgs)

    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $quotedArgs = ($ScriptArgs | ForEach-Object {
            "'$($_ -replace "'", "''")'"
        }) -join ','
        $escapedPath = $Script:ScriptPath -replace "'", "''"
        $command = @"
`$ErrorActionPreference = 'Continue'
`$scriptPath = '$escapedPath'
`$sb = [scriptblock]::Create((Get-Content -LiteralPath `$scriptPath -Raw))
& `$sb $(if ($quotedArgs) { "@($quotedArgs)" } else { '@()' })
"@
        $output = powershell -NoProfile -ExecutionPolicy Bypass -Command $command 2>&1
        $code = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
        if ($code -eq 0 -and ($output | Where-Object { "$_" -match 'ERROR:' })) {
            $code = 1
        }
    }
    finally {
        $ErrorActionPreference = $prev
    }
    return @{
        Output   = ($output | ForEach-Object { "$_" }) -join "`n"
        ExitCode = $code
    }
}

function Get-SlugViaScript {
    param([string]$Label)

    . $Script:ScriptPath
    return Get-ProfileSlug $Label
}

function Test-ScriptParses {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Script:ScriptPath, [ref]$null, [ref]$errors)
    return ($null -eq $errors -or $errors.Count -eq 0)
}

function Show-Summary {
    Write-Host ''
    Write-Host '========================================'
    Write-Host "Tests run:    $Script:TestsRun"
    Write-Host "Assertions:   $($Script:TestsPassed + $Script:TestsFailed) ($Script:TestsPassed passed, $Script:TestsFailed failed)"
    if ($Script:TestsFailed -eq 0) {
        Write-Host 'Result:       ALL PASSED'
        return 0
    }
    Write-Host 'Result:       FAILED'
    return 1
}

function Require-WindowsForTests {
    if ($env:OS -ne 'Windows_NT') {
        Write-Host 'SKIP: tests require Windows (PowerShell, WScript.Shell).' -ForegroundColor Yellow
        exit 0
    }
}
