#!/bin/bash
# Shared test helpers for make_claude_launchers.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/make_claude_launchers.sh"
MARKER_REL="Contents/Resources/claude-fix-generated"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
CURRENT_TEST=""

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo "  PASS: $1"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "  FAIL: $1" >&2
  if [ -n "${2:-}" ]; then
    echo "        $2" >&2
  fi
}

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-}"
  local default_msg="expected '$expected'"
  if [ "$expected" = "$actual" ]; then
    pass "${msg:-$default_msg}"
  else
    fail "${msg:-values differ}" "expected: '$expected' got: '$actual'"
  fi
}

assert_ne() {
  local not_expected="$1" actual="$2" msg="${3:-}"
  local default_msg="value is not '$not_expected'"
  if [ "$not_expected" != "$actual" ]; then
    pass "${msg:-$default_msg}"
  else
    fail "${msg:-unexpected value}" "got: '$actual'"
  fi
}

assert_true() {
  local msg="$1"
  shift
  if "$@"; then
    pass "$msg"
  else
    fail "$msg" "condition was false"
  fi
}

assert_false() {
  local msg="$1"
  shift
  if "$@"; then
    fail "$msg" "condition was true"
  else
    pass "$msg"
  fi
}

assert_file_exists() {
  local target="${1:-}"
  local msg="${2:-file exists: $target}"
  if [ -e "$target" ]; then
    pass "$msg"
  else
    fail "$msg" "missing: $target"
  fi
}

assert_file_missing() {
  local target="${1:-}"
  local msg="${2:-file missing: $target}"
  if [ ! -e "$target" ]; then
    pass "$msg"
  else
    fail "$msg" "still present: $target"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  local default_msg="output contains '$needle'"
  if printf '%s' "$haystack" | grep -Fq -- "$needle"; then
    pass "${msg:-$default_msg}"
  else
    fail "${msg:-$default_msg}" "needle not found in output"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" msg="${3:-}"
  local default_msg="output does not contain '$needle'"
  if printf '%s' "$haystack" | grep -Fq -- "$needle"; then
    fail "${msg:-$default_msg}" "unexpected needle in output"
  else
    pass "${msg:-$default_msg}"
  fi
}

assert_exit_code() {
  local expected="$1"
  shift
  set +e
  "$@" >/dev/null 2>&1
  local actual=$?
  set -e
  assert_eq "$expected" "$actual" "exit code $expected for: $*"
}

test_start() {
  CURRENT_TEST="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  # stderr is line-buffered when stdout is piped (tail/rg/CI); keeps progress visible
  echo >&2
  echo "== $CURRENT_TEST ==" >&2
  echo
  echo "== $CURRENT_TEST =="
}

# Create an isolated HOME for each test case.
setup_sandbox() {
  SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/claude-fix-test.XXXXXX")"
  ORIGINAL_PATH="$PATH"
  export ORIGINAL_PATH
  export HOME="$SANDBOX/home"
  mkdir -p "$HOME/Applications"
  export CLAUDE_LAUNCHERS_NO_OPEN=1
  export CLAUDE_LAUNCHERS_TEST_MODE=1
  export CLAUDE_LAUNCHERS_ICONS_DIR="$REPO_ROOT/icons"
  unset CLAUDE_LAUNCHERS_CLAUDE_APP CLAUDE_LAUNCHERS_PURGE_ANSWER \
    CLAUDE_LAUNCHERS_ONBOARDING_EXISTING CLAUDE_LAUNCHERS_RESET_PROFILE_ANSWER \
    CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE CLAUDE_LAUNCHERS_PROFILE_CHOICE \
    CLAUDE_LAUNCHERS_NEW_PROFILE_NAMES CLAUDE_LAUNCHERS_DOCK_PLIST \
    CLAUDE_LAUNCHERS_LAUNCH_ANSWER CLAUDE_LAUNCHERS_DOCK_ANSWER \
    CLAUDE_LAUNCHERS_ICONS_CACHE CLAUDE_LAUNCHERS_ICONS_BASE \
    CLAUDE_LAUNCHERS_ALLOW_ICON_DOWNLOAD CLAUDE_LAUNCHERS_NO_ICON_DOWNLOAD \
    CLAUDE_LAUNCHERS_UPGRADE_ANSWER CLAUDE_LAUNCHERS_ALLOW_QUIT_DUPES 2>/dev/null || true
}

teardown_sandbox() {
  stop_mock_claude_process 2>/dev/null || true
  if [ -n "${ORIGINAL_PATH:-}" ]; then
    PATH="$ORIGINAL_PATH"
    export PATH
  fi
  if [ -n "${SANDBOX:-}" ] && [ -d "$SANDBOX" ]; then
    rm -rf "$SANDBOX"
  fi
  unset SANDBOX HOME CLAUDE_LAUNCHERS_NO_OPEN CLAUDE_LAUNCHERS_TEST_MODE \
    CLAUDE_LAUNCHERS_CLAUDE_APP CLAUDE_LAUNCHERS_PURGE_ANSWER CLAUDE_LAUNCHERS_ONBOARDING_EXISTING \
    CLAUDE_LAUNCHERS_RESET_PROFILE_ANSWER CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE \
    CLAUDE_LAUNCHERS_PROFILE_CHOICE CLAUDE_LAUNCHERS_NEW_PROFILE_NAMES \
    CLAUDE_LAUNCHERS_ICONS_DIR CLAUDE_LAUNCHERS_DOCK_PLIST CLAUDE_LAUNCHERS_DOCK_ANSWER \
    CLAUDE_LAUNCHERS_LAUNCH_ANSWER CLAUDE_LAUNCHERS_FROM_MANAGEMENT \
    CLAUDE_LAUNCHERS_ICONS_CACHE CLAUDE_LAUNCHERS_ICONS_BASE \
    CLAUDE_LAUNCHERS_ALLOW_ICON_DOWNLOAD CLAUDE_LAUNCHERS_NO_ICON_DOWNLOAD \
    CLAUDE_LAUNCHERS_UPGRADE_ANSWER CLAUDE_LAUNCHERS_ALLOW_QUIT_DUPES \
    MOCK_CLAUDE_PID CLAUDE_MOCK_LAUNCHED_MARKER ORIGINAL_PATH
}

# Minimal fake Claude.app with an icon resource.
create_mock_claude() {
  local root="${1:-$HOME/Applications/Claude.app}"
  mkdir -p "$root/Contents/Resources" "$root/Contents/MacOS"
  touch "$root/Contents/MacOS/Claude"
  printf 'mock-claude-icon\n' > "$root/Contents/Resources/AppIcon.icns"
  export CLAUDE_LAUNCHERS_CLAUDE_APP="$root"
}

# Mock Claude.app whose binary can stay alive (simulates "Claude is running").
# Set CLAUDE_MOCK_LAUNCHED_MARKER before calling to detect if the app was launched.
create_mock_claude_runnable() {
  create_mock_claude
  local bin="$CLAUDE_LAUNCHERS_CLAUDE_APP/Contents/MacOS/Claude"
  cat >"$bin" <<'MOCK'
#!/bin/bash
marker="${CLAUDE_MOCK_LAUNCHED_MARKER:-}"
[ -n "$marker" ] && : >"$marker"
sleep 3600
MOCK
  chmod +x "$bin"
}

start_mock_claude_process() {
  local marker="${1:-$SANDBOX/claude-launched.marker}"
  export CLAUDE_MOCK_LAUNCHED_MARKER="$marker"
  rm -f "$marker"
  "$CLAUDE_LAUNCHERS_CLAUDE_APP/Contents/MacOS/Claude" &
  MOCK_CLAUDE_PID=$!
  export MOCK_CLAUDE_PID
  local deadline=$((SECONDS + 2))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ -f "$marker" ] && kill -0 "$MOCK_CLAUDE_PID" 2>/dev/null; then
      return 0
    fi
  done
  [ -f "$marker" ] && kill -0 "$MOCK_CLAUDE_PID" 2>/dev/null
}

stop_mock_claude_process() {
  if [ -n "${MOCK_CLAUDE_PID:-}" ]; then
    kill "$MOCK_CLAUDE_PID" 2>/dev/null || true
    wait "$MOCK_CLAUDE_PID" 2>/dev/null || true
    unset MOCK_CLAUDE_PID
  fi
  unset CLAUDE_MOCK_LAUNCHED_MARKER
}

mock_claude_process_running() {
  [ -n "${MOCK_CLAUDE_PID:-}" ] && kill -0 "$MOCK_CLAUDE_PID" 2>/dev/null
}

claude_app_installed_in_sandbox() {
  [ -d "${CLAUDE_LAUNCHERS_CLAUDE_APP:-}" ] || [ -d "$HOME/Applications/Claude.app" ]
}

# Generated launcher produced by osacompile (current version marker).
create_generated_launcher() {
  local label="$1"
  local app="$HOME/Applications/Claude ${label}.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  touch "$app/Contents/MacOS/applet"
  touch "$app/Contents/Resources/applet.icns"
  printf '#!/bin/bash\nopen -n -a Claude\n' >"$app/Contents/Resources/launch-profile.sh"
  chmod +x "$app/Contents/Resources/launch-profile.sh"
  printf 'generated-by=claude-fix\nlabel=%s\nlauncher-version=2\n' "$label" >"$app/$MARKER_REL"
}

# Old v1-style launcher (always open -n; no focus helper) for upgrade tests.
create_outdated_launcher() {
  local label="$1"
  local app="$HOME/Applications/Claude ${label}.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Scripts"
  touch "$app/Contents/MacOS/applet"
  touch "$app/Contents/Resources/applet.icns"
  printf 'generated-by=claude-fix\nlabel=%s\n' "$label" >"$app/$MARKER_REL"
}

create_unmarked_applet_launcher() {
  local label="$1"
  local app="$HOME/Applications/Claude ${label}.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  touch "$app/Contents/MacOS/applet"
  touch "$app/Contents/Resources/applet.icns"
}

# Real-looking Claude.app without the applet signature (must not be deleted).
create_real_claude_stub() {
  local app="$HOME/Applications/Claude.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  touch "$app/Contents/MacOS/Claude"
  touch "$app/Contents/Resources/AppIcon.icns"
}

run_script() {
  bash "$SCRIPT" "$@"
}

capture_script() {
  run_script "$@" 2>&1
}

slug_via_script() {
  bash -c 'source "$1"; slug "$2"' _ "$SCRIPT" "$1"
}

profile_icon_index_via_script() {
  bash -c 'source "$1"; profile_icon_index "$2"' _ "$SCRIPT" "$1"
}

profile_icon_path_via_script() {
  bash -c 'source "$1"; profile_icon_path "$2"' _ "$SCRIPT" "$1"
}

profile_icon_letter_via_script() {
  bash -c 'source "$1"; profile_icon_letter "$2"' _ "$SCRIPT" "$1"
}

profile_data_initialized_via_script() {
  bash -c 'source "$1"; profile_data_initialized "$2"' _ "$SCRIPT" "$1"
}

dock_remove_pins_via_script() {
  bash -c 'source "$1"; dock_remove_app_pins "$2" "$3"' _ "$SCRIPT" "$1" "$2"
}

dock_file_url_via_script() {
  bash -c 'source "$1"; dock_file_url "$2"' _ "$SCRIPT" "$1"
}

create_mock_dock_plist() {
  local plist="${1:-$SANDBOX/dock.plist}"
  printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0"><dict><key>persistent-apps</key><array/></dict></plist>' \
    >"$plist"
  export CLAUDE_LAUNCHERS_DOCK_PLIST="$plist"
}

dock_add_claude_pin() {
  local claude_app="$1"
  local plist="${CLAUDE_LAUNCHERS_DOCK_PLIST:-$SANDBOX/dock.plist}"
  local url label
  url=$(dock_file_url_via_script "$claude_app")
  label=$(basename "$claude_app" .app)
  /usr/libexec/PlistBuddy -c "Add :persistent-apps: dict" "$plist"
  local idx
  idx=$(python3 - "$plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as fh:
    data = plistlib.load(fh)
print(max(len(data.get("persistent-apps", [])) - 1, 0))
PY
)
  /usr/libexec/PlistBuddy -c "Add :persistent-apps:$idx:tile-data dict" "$plist"
  /usr/libexec/PlistBuddy -c "Add :persistent-apps:$idx:tile-data:file-data dict" "$plist"
  /usr/libexec/PlistBuddy -c "Add :persistent-apps:$idx:tile-data:file-data:_CFURLString string $url" "$plist"
  /usr/libexec/PlistBuddy -c "Add :persistent-apps:$idx:tile-data:file-data:_CFURLStringType integer 15" "$plist"
  /usr/libexec/PlistBuddy -c "Add :persistent-apps:$idx:tile-type string file-tile" "$plist"
  /usr/libexec/PlistBuddy -c "Add :persistent-apps:$idx:tile-data:file-label string $label" "$plist"
  /usr/libexec/PlistBuddy -c "Add :persistent-apps:$idx:tile-data:file-type integer 41" "$plist"
}

dock_persistent_urls() {
  local plist="${CLAUDE_LAUNCHERS_DOCK_PLIST:-$SANDBOX/dock.plist}"
  local count i
  count=$(python3 - "$plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as fh:
    data = plistlib.load(fh)
print(len(data.get("persistent-apps", [])))
PY
)
  for ((i = 0; i < count; i++)); do
    /usr/libexec/PlistBuddy -c "Print :persistent-apps:$i:tile-data:file-data:_CFURLString" "$plist" 2>/dev/null || true
  done
}

dock_assert_valid_entries() {
  local plist="${CLAUDE_LAUNCHERS_DOCK_PLIST:-$SANDBOX/dock.plist}"
  python3 - "$plist" <<'PY'
import plistlib, sys
plist = sys.argv[1]
with open(plist, "rb") as fh:
    data = plistlib.load(fh)
apps = data.get("persistent-apps", [])
for i, entry in enumerate(apps):
    tile = entry.get("tile-data", {})
    file_data = tile.get("file-data", {})
    if not file_data.get("_CFURLString"):
        raise SystemExit(f"persistent-apps[{i}] missing launcher URL")
    if entry.get("tile-type") != "file-tile":
        raise SystemExit(f"persistent-apps[{i}] missing tile-type=file-tile")
    url_type = file_data.get("_CFURLStringType")
    if url_type != 15:
        raise SystemExit(f"persistent-apps[{i}] expected _CFURLStringType 15, got {url_type!r}")
    if not tile.get("file-mod-date"):
        raise SystemExit(f"persistent-apps[{i}] missing file-mod-date")
print("ok")
PY
}

dock_assert_launchers_grouped() {
  local plist="${CLAUDE_LAUNCHERS_DOCK_PLIST:-$SANDBOX/dock.plist}"
  shift
  python3 - "$plist" "$@" <<'PY'
import os, plistlib, sys, urllib.parse

def normalize_url(path):
    path = os.path.abspath(path)
    if not path.endswith("/"):
        path += "/"
    return "file://" + urllib.parse.quote(path, safe="/")

def url_match(a, b):
    return urllib.parse.unquote(a or "").rstrip("/").lower() == urllib.parse.unquote(b or "").rstrip("/").lower()

plist = sys.argv[1]
app_paths = sys.argv[2:]
want_urls = [normalize_url(path) for path in app_paths]

with open(plist, "rb") as fh:
    data = plistlib.load(fh)

indices = []
for idx, entry in enumerate(data.get("persistent-apps", [])):
    url = entry.get("tile-data", {}).get("file-data", {}).get("_CFURLString", "")
    if any(url_match(url, want) for want in want_urls):
        indices.append(idx)

if len(indices) < 2:
    print("ok")
    raise SystemExit(0)

expected = list(range(indices[0], indices[0] + len(indices)))
if indices != expected:
    raise SystemExit(f"launcher pins not grouped: indices={indices}")
print("ok")
PY
}

dock_seed_stale_pin() {
  local app_path="$1"
  local plist="${CLAUDE_LAUNCHERS_DOCK_PLIST:-$SANDBOX/dock.plist}"
  local url label
  url=$(dock_file_url_via_script "$app_path")
  label=$(basename "$app_path" .app)
  python3 - "$plist" "$url" "$label" <<'PY'
import plistlib, sys
plist, url, label = sys.argv[1:4]
with open(plist, "rb") as fh:
    data = plistlib.load(fh)
apps = data.setdefault("persistent-apps", [])
apps.append({
    "tile-type": "file-tile",
    "tile-data": {
        "file-data": {
            "_CFURLString": url,
            "_CFURLStringType": 15,
        },
        "file-label": label,
        "file-type": 41,
        "file-mod-date": 0,
        "parent-mod-date": 0,
    },
})
with open(plist, "wb") as fh:
    plistlib.dump(data, fh)
PY
}

dock_seed_pin_label_only() {
  local app_path="$1"
  local plist="${CLAUDE_LAUNCHERS_DOCK_PLIST:-$SANDBOX/dock.plist}"
  local label
  label=$(basename "$app_path" .app)
  python3 - "$plist" "$label" <<'PY'
import plistlib, sys
plist, label = sys.argv[1:3]
with open(plist, "rb") as fh:
    data = plistlib.load(fh)
apps = data.setdefault("persistent-apps", [])
apps.append({
    "tile-type": "file-tile",
    "tile-data": {
        "file-data": {
            "_CFURLString": "file:///wrong/path/Claude.app/",
            "_CFURLStringType": 15,
        },
        "file-label": label,
        "file-type": 41,
        "file-mod-date": 384_000_000,
        "parent-mod-date": 384_000_000,
    },
})
with open(plist, "wb") as fh:
    plistlib.dump(data, fh)
PY
}

print_summary() {
  echo
  echo "========================================"
  echo "Tests run:    $TESTS_RUN"
  echo "Assertions:   $((TESTS_PASSED + TESTS_FAILED)) ($TESTS_PASSED passed, $TESTS_FAILED failed)"
  if [ "$TESTS_FAILED" -eq 0 ]; then
    echo "Result:       ALL PASSED"
    return 0
  fi
  echo "Result:       FAILED"
  return 1
}

require_macos_for_tests() {
  if [ "$(uname -s)" != "Darwin" ]; then
    echo "SKIP: tests require macOS (osacompile, osascript)." >&2
    exit 0
  fi
  for tool in osacompile osascript bash; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "SKIP: missing required tool '$tool'." >&2
      exit 0
    fi
  done
}
