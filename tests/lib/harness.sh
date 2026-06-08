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
  unset CLAUDE_LAUNCHERS_CLAUDE_APP CLAUDE_LAUNCHERS_PURGE_ANSWER \
    CLAUDE_LAUNCHERS_ONBOARDING_EXISTING CLAUDE_LAUNCHERS_RESET_PROFILE_ANSWER \
    CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE CLAUDE_LAUNCHERS_PROFILE_CHOICE \
    CLAUDE_LAUNCHERS_NEW_PROFILE_NAMES 2>/dev/null || true
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
  sleep 0.2
  kill -0 "$MOCK_CLAUDE_PID" 2>/dev/null
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

# Generated launcher produced by osacompile.
create_generated_launcher() {
  local label="$1"
  local app="$HOME/Applications/Claude ${label}.app"
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
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
