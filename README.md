# claude-fix

[![Tests](https://github.com/sarhej/claude-fix/actions/workflows/test.yml/badge.svg)](https://github.com/sarhej/claude-fix/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-supported-blue.svg)](#requirements)
[![Windows](https://img.shields.io/badge/Windows-supported-blue.svg)](#requirements-windows)

**Claude Profile Switcher for Mac and Windows.**

Run separate **Work** and **Personal** Claude Desktop profiles on one computer, each
with its own login, chat history, settings, and connected tools.

**macOS:**

```bash
curl -fsSL https://raw.githubusercontent.com/sarhej/claude-fix/heads/main/make_claude_launchers.sh | bash
```

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/sarhej/claude-fix/heads/main/make_claude_launchers.ps1 | iex
```

The default setup keeps your **existing Claude login** as-is and creates only
the missing second profile:

- Your normal `Claude.app` stays on your current account (Work or Personal)
- The script creates one new launcher for the other account, e.g.
  `~/Applications/Claude Personal.app`
- Optionally, a clickable copy on your Desktop

When the new profile opens, sign in with your **other** account and connect the
matching tools there.

**Trust check:** this project is local-only, dependency-free, and covered by
integration tests in GitHub Actions (macOS and Windows). Review the source and
test suite on GitHub before running if you want the full details.

`make_claude_launchers.sh` (macOS) and `make_claude_launchers.ps1` (Windows)
create separate, clickable launchers for
[Claude Desktop](https://claude.ai/download) — each with its **own login,
chat history, settings, and connected tools**. Think *Work* vs *Personal*
(different email, calendar, Slack, etc.), or one profile per client.

It also includes a `clean` command to remove the generated launchers and restore
your Mac to the standard single-app setup.

---

## Why?

Claude Desktop (like most Electron/Chromium apps) stores all of its data —
the account you're signed into, your conversations, your preferences, and your
**connected integrations** — in a single user-data directory. That means one
app = one account = one set of connected tools.

If you use Claude with external services (Gmail, Google Calendar, Slack,
Notion, etc.), everything is wired to that single profile. You can't easily
have one Claude signed into your **personal Gmail and calendar** while another
uses your **company email and calendar** — without mixing contexts, accounts,
or permissions.

This script works around that by launching Claude with a per-profile
`--user-data-dir`, so each launcher is fully isolated:

- Sign into a **different Claude account** in each.
- Connect **different tools per profile** — e.g. personal email & calendar in
  one, company email & calendar in another.
- Keep **work and personal chats separate** (no cross-contamination of context).
- Run **multiple Claude windows at once** (one per profile).

**Example setup:**

| Launcher           | Connected tools                         |
|--------------------|-----------------------------------------|
| Claude Personal    | Personal Gmail, personal Google Calendar |
| Claude Work        | Company email, company calendar, Slack   |

No app modification, no re-signing, no patching — just thin AppleScript
launchers that point at your existing `Claude.app`.

---

## Who this is for

- People with a **private Claude account** and a **company Claude account**.
- Consultants who connect Claude to different clients' email, calendars, Slack,
  Notion, GitHub, or MCP/tool permissions.
- Anyone who wants to keep personal and work context separate while still using
  the native Claude Desktop app.

---

## Requirements

### macOS

- **macOS** (the script refuses to run anywhere else).
- **Claude Desktop** installed — [download here](https://claude.ai/download).
  The script auto-detects it in `/Applications`, `~/Applications`, via Launch
  Services (bundle id), or Spotlight.
- Built-in macOS tools: `osacompile` and `osascript` (preinstalled).
- No Python, Pillow, icon conversion, or package installation is required.

### Windows

- **Windows 10 or later** with **PowerShell 5.1+** (preinstalled).
- **Claude Desktop** installed — [download here](https://claude.ai/download).
  The script auto-detects standard install paths, MSIX package installs under
  `%LOCALAPPDATA%\Packages\Claude_*`, and `Claude.exe` on your PATH.
- No extra packages or admin rights required.
- If Claude is in an unusual location, set `CLAUDE_LAUNCHERS_CLAUDE_EXE` to the
  full path of `Claude.exe` (or `claude.exe` for MSIX installs).

---

## Installation

### macOS — One-Line Install

Copy and paste this into Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/sarhej/claude-fix/heads/main/make_claude_launchers.sh | bash
```

### Windows — One-Line Install

Copy and paste this into PowerShell:

```powershell
irm https://raw.githubusercontent.com/sarhej/claude-fix/heads/main/make_claude_launchers.ps1 | iex
```

If execution policy blocks scripts, download first and run:

```powershell
irm -OutFile make_claude_launchers.ps1 https://raw.githubusercontent.com/sarhej/claude-fix/heads/main/make_claude_launchers.ps1
.\make_claude_launchers.ps1
```

If your execution policy still blocks local scripts, use:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\make_claude_launchers.ps1
```

The script will ask a few simple questions. Press Enter to accept the default:

1. Confirm which account your current Claude is already signed into
2. Create the missing second profile launcher
3. Optionally place a clickable copy on your Desktop
4. Optionally launch the new profile immediately so you can sign in there

After launchers exist, running the script again shows a management menu instead
of asking the first-run question again.

### Inspect First

If you want to inspect the script before running it:

```bash
curl -fsSLO https://raw.githubusercontent.com/sarhej/claude-fix/heads/main/make_claude_launchers.sh
less make_claude_launchers.sh
bash make_claude_launchers.sh
```

### Clone the Repo

**macOS:**

```bash
git clone https://github.com/sarhej/claude-fix.git
cd claude-fix
bash make_claude_launchers.sh
```

**Windows:**

```powershell
git clone https://github.com/sarhej/claude-fix.git
cd claude-fix
.\make_claude_launchers.ps1
```

Use `powershell -NoProfile -ExecutionPolicy Bypass -File .\make_claude_launchers.ps1` only if execution policy blocks `.\make_claude_launchers.ps1`.

Executable permissions are optional on macOS; `bash make_claude_launchers.sh ...` works.

---

## Usage

**macOS** (`make_claude_launchers.sh`) and **Windows** (`make_claude_launchers.ps1`)
share the same commands:

```bash
# Interactive setup: keep existing Claude login, add the missing profile
./make_claude_launchers.sh          # macOS
.\make_claude_launchers.ps1       # Windows

# Create custom launchers (one per label) for power users
./make_claude_launchers.sh create Work Personal Clients

# Create launchers and also put clickable copies on your Desktop
./make_claude_launchers.sh create --desktop Personal

# Create the missing profile and launch it immediately
./make_claude_launchers.sh create --launch

# Skip Desktop copies
./make_claude_launchers.sh create --no-desktop Personal

# Remove generated launchers, but KEEP your profile data
./make_claude_launchers.sh clean

# Remove generated launchers AND their profile data (asks before each delete)
./make_claude_launchers.sh clean --purge

# Show help
./make_claude_launchers.sh help
```

After creation, the script opens `~/Applications` in Finder (macOS) or File Explorer
(Windows) unless it already launched the new profile for you.

If you choose to launch the new profile right away, only that new Claude window
opens. Sign into it with your other account, then connect the matching tools.
Keep using your normal Claude app for the account you already had.

### Running It Again

Once generated profiles already exist, the script detects them by their marker
files and skips first-run onboarding. Instead it shows next steps:

```text
Claude Profile Switcher is already set up.

Found generated profile launcher(s):
  - Claude Personal
    launcher: ~/Applications/Claude Personal.app
    local sign-in: ~/ClaudePersonal

What would you like to do next?
  1) Open a generated Claude profile
  2) Open all generated Claude profiles
  3) Open the launchers folder
  4) Create another profile
  5) Fix wrong account / start fresh for a generated profile
  6) Remove generated launchers (keep local sign-ins)
  7) Remove launchers AND local generated profile data
  8) Cancel
```

Use **start fresh** if a generated launcher opens the wrong account. It only
clears that launcher's local sign-in folder on your Mac; it does not delete your
Claude account and does not change the normal Claude app.

### Commands at a glance

| Command | What it does |
|---------|--------------|
| no command | First run: add missing profile. Later: show the management menu. |
| `create [labels...]` | Create one launcher per explicit label. |
| `create --desktop [labels...]` | Also place clickable launcher copies on your Desktop. |
| `create --no-desktop [labels...]` | Create only in `~/Applications`. |
| `create --launch [labels...]` | Launch the created profile(s) after setup. |
| `create --no-launch [labels...]` | Create launchers without opening Claude. |
| `create --yes` | Skip menu; assumes existing Work, creates Personal. |
| `clean` | Remove generated launchers; **keep** all profile data. |
| `clean --purge` | Remove launchers **and** generated profile data (per-profile confirmation). |
| `help` | Print usage. |

---

## What gets created

**Default interactive setup**

If your current Claude is already signed into Work / Company, the script creates
only `Claude Personal` and leaves your normal Claude app untouched.

If your current Claude is Personal, it creates only `Claude Work`.

**Explicit CLI labels**

For a label like `Work`, the script produces:

- **`~/Applications/Claude Work`** — a launcher (macOS `.app` or Windows `.lnk`)
  that runs Claude with an isolated profile directory:

  ```bash
  # macOS
  open -n -a '/Applications/Claude.app' --args --user-data-dir="$HOME/ClaudeWork"
  ```

  ```text
  # Windows (shortcut target — runs a wrapper that sets OAuth routing, then launches Claude)
  powershell.exe -File "%USERPROFILE%\.claude-fix\launch-profile.ps1" ...
  Claude.exe --user-data-dir="C:\Users\you\ClaudeWork"
  ```

- **`~/ClaudeWork/`** — the isolated profile data directory (created by Claude
  on first launch; holds that profile's login, history, and settings).
- **Optional Desktop copies** — clickable copies like
  `~/Desktop/Claude Work`, for people who expect to launch apps from the
  Desktop.

| Profile | Normal Claude app | Generated launcher | Data directory |
|---------|-------------------|--------------------|----------------|
| Existing Work login | stays as Work / Company | — | Claude's default profile data |
| Added Personal | — | `~/Applications/Claude Personal` | `~/ClaudePersonal` |
| Existing Personal login | stays as Personal | — | Claude's default profile data |
| Added Work | — | `~/Applications/Claude Work` | `~/ClaudeWork` |

Launcher names map to data dirs deterministically (`"Big Client"` →
`~/ClaudeBigClient`), so `create` and `clean` always agree on paths.

Labels are intentionally conservative: letters, numbers, spaces, hyphens,
underscores, and apostrophes are supported. Path separators, control characters,
leading dots, overly long labels, and duplicate labels that map to the same
profile directory are rejected.

---

## How it works

**macOS**

1. **Sanity checks** — confirms macOS and that required tools exist.
2. **Locate Claude** — checks standard paths, then Launch Services, then
   Spotlight. Exits with a clear message (and the download link) if not found.
3. **Copy Claude's normal icon** — launchers use the standard Claude icon if it
   is available. No tinting or icon conversion is attempted.
4. **Compile launchers** — `osacompile` turns a one-line `open -n ... --user-data-dir`
   command into a real `.app` bundle.
5. **Refresh Finder metadata** — `touch`es the bundle so
   Finder picks up the change.

**Windows**

1. **Sanity checks** — confirms Windows and PowerShell 5.1+.
2. **Locate Claude** — checks standard paths, MSIX package installs, and PATH.
3. **Create shortcuts** — builds `.lnk` files that launch a small PowerShell wrapper
   with `--user-data-dir` and a per-profile App User Model ID via
   `WScript.Shell`, using Claude's icon from the executable.
4. **OAuth callback router** — registers a user-level `claude://` protocol handler
   that forwards sign-in callbacks to the profile you opened most recently (with
   `--user-data-dir`), instead of your default Claude instance.
5. **Track ownership** — writes a sidecar `.claude-fix-generated` marker next to
   each shortcut so `clean` only removes launchers this script created.

`-n` tells macOS to launch a **new instance**, which is what allows several
Claude profiles to run simultaneously.

Important caveat: profile isolation depends on Claude Desktop continuing to
honor Electron/Chromium's `--user-data-dir` flag. That works today for this use
case, but Anthropic could change Claude Desktop in a future release.

Dock / taskbar icon caveat: the launchers use Claude's normal icon, and running
profiles may appear as separate but same-looking Claude icons in the Dock or
taskbar. This is a platform limitation of launching the same underlying Claude
process with different profile data directories.

---

## Safety

- **`create` never deletes profile data.** It only removes and rebuilds the
  `.app` launcher bundle; your `~/Claude*` directories are preserved.
- **`clean` only removes launchers this script generated.** It identifies them
  with a `claude-fix-generated` marker file inside the app bundle and **never
  touches the real `Claude.app`**.
- **`clean --purge` asks before each deletion**, defaulting to *No*, so an
  accidental Enter keeps your data. Purge only targets generated profile
  directories such as `~/ClaudePersonal`; it never deletes your normal Claude
  app or its default profile data.
- **No dependencies or package installs.** The scripts use only built-in
  platform tooling and never install Python packages or other dependencies.

---

## What this does not do

- It does **not** modify, patch, or re-sign `Claude.app`.
- It does **not** bypass account limits, authentication, or company policy.
- It does **not** migrate or merge chat history between profiles.
- It does **not** encrypt Claude profile data. Profiles are stored as normal
  local Claude/Electron user data.
- It does **not** guarantee official Anthropic support for `--user-data-dir`.
- It does **not** create different-looking running Dock/taskbar icons. Profiles
  may appear as separate but identical Claude icons.

---

## Troubleshooting

- **"Claude Desktop is not installed"** — install it from
  [claude.ai/download](https://claude.ai/download). On macOS, move Claude to
  `/Applications` if it is in an unusual location. On Windows, if Claude is
  installed elsewhere, set `CLAUDE_LAUNCHERS_CLAUDE_EXE` to the full path of
  `Claude.exe` before running the script. `clean` and `help` work without Claude;
  only `create` requires it.
- **Wrong account opens in the new profile** — an earlier sign-in may already be
  saved in the launcher's local folder (`~/ClaudePersonal` or `~/ClaudeWork`).
  Re-run the script and choose **start fresh** when prompted. This only clears
  that launcher's local sign-in on your Mac; it does not delete your Claude
  account or affect your normal Claude app.
- **Desktop icons grouped under "Applications"** — macOS Desktop Stacks may
  group `.app` launchers together. Right-click the Desktop and turn off
  `Use Stacks`, or open the Applications stack.
- **Dock icons look the same** — expected. The profiles are separate because
  each Claude process gets a different `--user-data-dir`, but macOS still shows
  Claude's normal app icon.
- **Both profiles share data** — this only happens if your Claude build ignores
  `--user-data-dir`. Verify by signing into different accounts in each launcher.
- **macOS Gatekeeper warning** — the launchers are locally generated and
  unsigned. Right-click → **Open** the first time if prompted.
- **Windows SmartScreen** — locally generated shortcuts may trigger a one-time
  warning. Use **More info → Run anyway**, or right-click the shortcut and choose
  **Open** the first time.
- **Second profile won't sign in / OAuth opens the wrong Claude window (Windows)** —
  Claude's global `claude://` handler normally launches your **default** Claude
  instance (the one from Start Menu), not an isolated profile. This script
  registers an OAuth callback router on `create` and removes it on `clean`.
  **To sign into a generated profile:** open that profile's launcher (e.g.
  Claude Personal), then start sign-in and approve it in the browser while that
  window stays open. Re-open the launcher if you started sign-in more than an
  hour ago. If Work and Personal are both open and sign-in still lands in the
  wrong window, close the other profile, open only the one you want to sign
  into, and try again.

---

## Uninstall

```bash
./make_claude_launchers.sh clean --purge
```

This removes the generated launchers and (with confirmation) their profile data,
returning your Mac to the standard single Claude setup. The original
`Claude.app` is left untouched.

---

## Testing

The project includes integration test suites that run in an **isolated
temporary home directory** — they never touch your real Claude install or profile
data.

**macOS:**

```bash
bash tests/run_tests.sh
```

**Windows:**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run_tests.ps1
```

The Windows suite mirrors the macOS integration tests (49 test cases), plus Windows-specific coverage for MSIX path discovery, WScript.Shell shortcuts, OAuth callback routing, and sidecar marker files.

### What is covered

| Area | Tests |
|------|-------|
| **Script integrity** | Bash syntax check, executable bit |
| **slug()** | Label → data-dir mapping, spaces, hyphens, special chars |
| **CLI** | `help`, `-h`, `--help`, implicit `create` command |
| **Missing Claude** | Clear error + download link when Claude is not found |
| **Claude not installed** | `create` fails; `clean` and `help` still work |
| **Claude installed, not running** | `create`/`clean` succeed; default `create` does not launch Claude.app |
| **Claude installed, running** | `create`/`clean` succeed; running process is never killed |
| **create** | Onboarding default, explicit labels, AppleScript payload (`--user-data-dir`, `open -n`) |
| **onboarding** | Existing Work creates Personal; existing Personal creates Work |
| **management menu** | Existing generated launchers skip onboarding and offer open/create/start-fresh/remove actions |
| **launch option** | `--launch` opens only created profile(s) and explains login for the new one |
| **Safety** | Re-create never deletes `~/Claude*` profile data; only rebuilds launcher `.app` |
| **Trust** | No Python/Pillow, no package installs, marker-based cleanup ownership |
| **Input hardening** | Empty labels, unsafe labels, duplicate profile dirs, quoted Claude paths |
| **Graceful fallback** | Missing `.icns` |
| **clean** | Removes only generated launchers; keeps profile data |
| **clean safety** | Never matches plain `Claude.app`; skips non-applet `Claude *.app` bundles |
| **clean --purge** | Decline (default), confirm `y`/`Y`, delete profile data |
| **Full lifecycle** | create → clean → re-create with data preserved |

Tests require **macOS** (`osacompile`, `osascript`) or **Windows** (PowerShell,
`WScript.Shell`). On other platforms they exit gracefully with a skip message.

CI runs automatically on push/PR via GitHub Actions
(`.github/workflows/test.yml`) on both macOS and Windows.

---

## License

[MIT](LICENSE) © 2026 [Sergej Fedorovic](https://strt.it)
