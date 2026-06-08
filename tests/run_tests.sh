#!/bin/bash
#
# Integration + edge-case tests for make_claude_launchers.sh
# Runs in an isolated temp HOME — never touches your real Claude setup.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$SCRIPT_DIR/lib/harness.sh"

require_macos_for_tests

if [ ! -x "$SCRIPT" ]; then
  chmod +x "$SCRIPT"
fi

test_slug_mapping() {
  test_start "slug() maps labels to safe data-dir names"
  assert_eq "ClaudeWork" "$(slug_via_script "Work")" "Work -> ClaudeWork"
  assert_eq "ClaudePersonal" "$(slug_via_script "Personal")" "Personal -> ClaudePersonal"
  assert_eq "ClaudeBigClient" "$(slug_via_script "Big Client")" "spaces removed"
  assert_eq "ClaudeClientA" "$(slug_via_script "client-a!!!")" "hyphens become word breaks"
  assert_eq "Claude123" "$(slug_via_script "123")" "numeric label"
}

test_help() {
  test_start "help prints usage and Dock limitation"
  setup_sandbox
  local out
  out="$(capture_script help)"
  assert_contains "$out" "Commands:" "shows commands section"
  assert_contains "$out" "clean --purge" "documents purge"
  assert_contains "$out" "--desktop" "documents Desktop shortcuts option"
  assert_contains "$out" "--launch" "documents launch option"
  assert_contains "$out" "existing Claude login" "documents existing profile model"
  assert_contains "$out" "same-looking Claude Dock icons" "documents Dock icon limitation"
  teardown_sandbox
}

test_help_aliases() {
  test_start "help aliases (-h, --help)"
  setup_sandbox
  assert_contains "$(capture_script -h)" "make_claude_launchers.sh" "-h works"
  assert_contains "$(capture_script --help)" "create [options]" "--help works"
  teardown_sandbox
}

test_not_installed_create_fails() {
  test_start "[not installed] create exits with clear error"
  setup_sandbox
  assert_false "Claude.app absent in sandbox" claude_app_installed_in_sandbox
  local out
  set +e
  out="$(capture_script create 2>&1)"
  local code=$?
  set -e
  assert_eq "1" "$code" "exits 1"
  assert_contains "$out" "Claude Desktop is not installed" "meaningful error"
  assert_contains "$out" "claude.ai/download" "includes download link"
  teardown_sandbox
}

test_not_installed_implicit_create_fails() {
  test_start "[not installed] bare labels (implicit create) also fail"
  setup_sandbox
  set +e
  capture_script Work Personal >/dev/null 2>&1
  local code=$?
  set -e
  assert_eq "1" "$code" "implicit create exits 1 without Claude.app"
  teardown_sandbox
}

test_not_installed_clean_still_works() {
  test_start "[not installed] clean still works"
  setup_sandbox
  create_generated_launcher "Work"
  local out code
  set +e
  out="$(capture_script clean 2>&1)"
  code=$?
  set -e
  assert_eq "0" "$code" "clean exits 0 without Claude installed"
  assert_contains "$out" "Removing launcher: Claude Work.app" "removes launcher"
  assert_file_missing "$HOME/Applications/Claude Work.app" "launcher removed"
  teardown_sandbox
}

test_installed_not_running_create_succeeds() {
  test_start "[installed, not running] create succeeds and does not launch Claude"
  setup_sandbox
  create_mock_claude_runnable >/dev/null
  local marker="$SANDBOX/claude-launched.marker"
  export CLAUDE_MOCK_LAUNCHED_MARKER="$marker"
  assert_false "mock Claude process not started yet" mock_claude_process_running
  capture_script create Work >/dev/null
  assert_file_exists "$HOME/Applications/Claude Work.app/Contents/MacOS/applet" "launcher created"
  assert_file_missing "$marker" "Claude binary was never executed during create"
  teardown_sandbox
}

test_installed_running_create_and_clean_do_not_kill_claude() {
  test_start "[installed, running] create/clean never kill the running Claude process"
  setup_sandbox
  create_mock_claude_runnable >/dev/null
  local marker="$SANDBOX/claude-launched.marker"
  start_mock_claude_process "$marker"
  assert_true "mock Claude process is running" mock_claude_process_running
  capture_script create Work Personal >/dev/null
  capture_script clean >/dev/null
  assert_true "Claude process survived create + clean" mock_claude_process_running
  assert_file_exists "$marker" "launch marker still present"
  teardown_sandbox
}

test_create_default_profiles() {
  test_start "default create keeps existing Work and adds Personal launcher"
  setup_sandbox
  create_mock_claude >/dev/null
  local out
  out="$(capture_script create)"
  assert_contains "$out" "Creating 1 launcher(s)" "creates one launcher"
  assert_contains "$out" "Your existing Claude remains your Work / Company profile." "explains existing profile"
  assert_contains "$out" "I created Claude Personal" "creates Personal profile"
  assert_file_missing "$HOME/Applications/Claude Work.app" "does not create Work launcher"
  assert_file_exists "$HOME/Applications/Claude Personal.app/Contents/MacOS/applet" "Personal launcher is an applet"
  teardown_sandbox
}

test_onboarding_existing_personal_creates_work() {
  test_start "onboarding with existing Personal creates Work launcher only"
  setup_sandbox
  create_mock_claude >/dev/null
  export CLAUDE_LAUNCHERS_ONBOARDING_EXISTING=Personal
  local out
  out="$(capture_script create)"
  assert_contains "$out" "Creating 1 launcher(s)" "creates one launcher"
  assert_contains "$out" "Your existing Claude remains your Personal profile." "explains existing profile"
  assert_file_exists "$HOME/Applications/Claude Work.app" "Work launcher created"
  assert_file_missing "$HOME/Applications/Claude Personal.app" "does not create Personal launcher"
  teardown_sandbox
}

test_desktop_shortcuts_option() {
  test_start "create --desktop creates Desktop launchers"
  setup_sandbox
  create_mock_claude >/dev/null
  capture_script create --desktop Work Personal >/dev/null
  assert_file_exists "$HOME/Desktop/Claude Work.app/Contents/MacOS/applet" "Work Desktop launcher"
  assert_file_exists "$HOME/Desktop/Claude Personal.app/Contents/MacOS/applet" "Personal Desktop launcher"
  teardown_sandbox
}

test_no_desktop_option() {
  test_start "create --no-desktop avoids Desktop aliases"
  setup_sandbox
  create_mock_claude >/dev/null
  capture_script create --no-desktop Work Personal >/dev/null
  assert_file_missing "$HOME/Desktop/Claude Work.app" "no Work Desktop launcher"
  assert_file_missing "$HOME/Desktop/Claude Personal.app" "no Personal Desktop launcher"
  teardown_sandbox
}

test_launch_option_prints_first_time_setup() {
  test_start "create --launch starts onboarding profile and explains next login step"
  setup_sandbox
  create_mock_claude >/dev/null
  local out
  out="$(capture_script create --launch)"
  assert_contains "$out" "Launching your new Claude profile" "reports launch step"
  assert_contains "$out" "Claude Personal" "mentions Personal profile launch"
  assert_contains "$out" "sign in with your Personal account" "explains separate login"
  assert_contains "$out" "Keep using your normal Claude app for Work / Company." "explains existing profile usage"
  teardown_sandbox
}

test_launch_option_multi_profile() {
  test_start "create --launch with explicit labels supports multiple profiles"
  setup_sandbox
  create_mock_claude >/dev/null
  local out
  out="$(capture_script create --launch Work Personal)"
  assert_contains "$out" "Launching your new Claude profile(s)" "reports launch step"
  assert_contains "$out" "sign in with the account for that profile" "explains multi-profile login"
  teardown_sandbox
}

test_no_launch_option_keeps_profiles_closed() {
  test_start "create --no-launch leaves profiles closed and explains next step"
  setup_sandbox
  create_mock_claude >/dev/null
  local out
  out="$(capture_script create --no-launch)"
  assert_not_contains "$out" "Launching your new Claude profile" "does not launch profiles"
  assert_contains "$out" "Next: open Claude Personal from $HOME/Applications" "explains later login"
  teardown_sandbox
}

test_no_args_defaults_to_create() {
  test_start "running with no arguments adds the missing Personal profile"
  setup_sandbox
  create_mock_claude >/dev/null
  local out code
  set +e
  out="$(capture_script)"
  code=$?
  set -e
  assert_eq "0" "$code" "no-args command exits 0"
  assert_contains "$out" "Creating 1 launcher(s)" "prints create progress"
  assert_file_missing "$HOME/Applications/Claude Work.app" "Work launcher not created"
  assert_file_exists "$HOME/Applications/Claude Personal.app" "Personal launcher created"
  teardown_sandbox
}

test_existing_launchers_show_management_menu() {
  test_start "existing generated launchers show management menu instead of onboarding"
  setup_sandbox
  create_generated_launcher "Personal"
  local out
  out="$(capture_script create)"
  assert_contains "$out" "already set up" "detects existing setup"
  assert_contains "$out" "Claude Personal" "lists existing launcher"
  assert_contains "$out" "What would you like to do next?" "shows next-step menu"
  assert_not_contains "$out" "Which account is your current Claude already signed into?" "does not re-run onboarding"
  teardown_sandbox
}

test_management_menu_opens_existing_profile() {
  test_start "management menu opens selected generated profile"
  setup_sandbox
  create_generated_launcher "Personal"
  export CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE=1
  local out
  out="$(capture_script create)"
  assert_contains "$out" "Opening Claude Personal" "opens generated launcher"
  assert_not_contains "$out" "Creating 1 launcher" "does not rebuild launcher"
  teardown_sandbox
}

test_management_menu_create_another_profile() {
  test_start "management menu can create another profile"
  setup_sandbox
  create_mock_claude >/dev/null
  create_generated_launcher "Personal"
  export CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE=4
  export CLAUDE_LAUNCHERS_NEW_PROFILE_NAMES="ClientA"
  local out
  out="$(capture_script create)"
  assert_contains "$out" "Creating 1 launcher(s)" "creates requested extra profile"
  assert_file_exists "$HOME/Applications/Claude ClientA.app" "ClientA launcher created"
  teardown_sandbox
}

test_management_menu_start_fresh_profile() {
  test_start "management menu can clear local sign-in for generated profile"
  setup_sandbox
  create_generated_launcher "Personal"
  local data="$HOME/ClaudePersonal"
  mkdir -p "$data"
  printf '{"oauth:tokenCache":"stale"}\n' >"$data/config.json"
  export CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE=5
  export CLAUDE_LAUNCHERS_RESET_PROFILE_ANSWER=y
  local out
  out="$(capture_script create)"
  assert_contains "$out" "does NOT delete your Claude account" "uses safe wording"
  assert_contains "$out" "cleared local sign-in for Claude Personal" "clears local sign-in"
  assert_file_missing "$data" "local profile directory removed"
  teardown_sandbox
}

test_create_custom_and_implicit_labels() {
  test_start "create accepts custom labels and implicit create"
  setup_sandbox
  create_mock_claude >/dev/null
  capture_script create Alpha Beta >/dev/null
  capture_script Solo >/dev/null
  assert_file_exists "$HOME/Applications/Claude Alpha.app" "Alpha launcher"
  assert_file_exists "$HOME/Applications/Claude Beta.app" "Beta launcher"
  assert_file_exists "$HOME/Applications/Claude Solo.app" "implicit create works"
  teardown_sandbox
}

test_launcher_applescript_payload() {
  test_start "launcher embeds isolated --user-data-dir path"
  setup_sandbox
  create_mock_claude >/dev/null
  capture_script create Work >/dev/null
  local script_path="$HOME/Applications/Claude Work.app/Contents/Resources/Scripts/main.scpt"
  assert_file_exists "$script_path" "compiled AppleScript exists"
  local decompiled
  decompiled="$(osadecompile "$script_path" 2>/dev/null || true)"
  assert_contains "$decompiled" "--user-data-dir" "passes user-data-dir flag"
  assert_contains "$decompiled" "$HOME/ClaudeWork" "uses absolute profile dir"
  local runtime_home_literal="\$HOME/ClaudeWork"
  assert_not_contains "$decompiled" "$runtime_home_literal" "does not rely on runtime HOME expansion"
  assert_contains "$decompiled" "open -n" "opens new instance"
  teardown_sandbox
}

test_onboarding_reset_profile_data() {
  test_start "onboarding can reset previously used profile data before launch"
  setup_sandbox
  create_mock_claude >/dev/null
  local data="$HOME/ClaudePersonal"
  mkdir -p "$data"
  printf '{"oauth:tokenCache":"stale"}\n' >"$data/config.json"
  export CLAUDE_LAUNCHERS_RESET_PROFILE_ANSWER="y"
  local out
  out="$(capture_script create)"
  assert_contains "$out" "already has a saved sign-in" "warns about existing profile data"
  assert_contains "$out" "does not change your normal Claude app" "reassures user about safety"
  assert_contains "$out" "cleared local sign-in for Claude Personal" "reports fresh start"
  assert_file_missing "$data/config.json" "profile data removed"
  teardown_sandbox
}

test_launcher_uses_normal_claude_icon() {
  test_start "launchers copy the normal Claude icon when available"
  setup_sandbox
  create_mock_claude >/dev/null
  capture_script create Work Personal >/dev/null
  local source_hash work_hash personal_hash
  source_hash="$(shasum -a 256 "$CLAUDE_LAUNCHERS_CLAUDE_APP/Contents/Resources/AppIcon.icns" | awk '{print $1}')"
  work_hash="$(shasum -a 256 "$HOME/Applications/Claude Work.app/Contents/Resources/applet.icns" | awk '{print $1}')"
  personal_hash="$(shasum -a 256 "$HOME/Applications/Claude Personal.app/Contents/Resources/applet.icns" | awk '{print $1}')"
  assert_eq "$source_hash" "$work_hash" "Work launcher uses source icon"
  assert_eq "$source_hash" "$personal_hash" "Personal launcher uses source icon"
  teardown_sandbox
}

test_generated_launcher_has_marker() {
  test_start "create writes ownership marker into each generated launcher"
  setup_sandbox
  create_mock_claude >/dev/null
  capture_script create Work >/dev/null
  assert_file_exists "$HOME/Applications/Claude Work.app/$MARKER_REL" "marker file exists"
  assert_contains "$(cat "$HOME/Applications/Claude Work.app/$MARKER_REL")" "generated-by=claude-fix" "marker identifies claude-fix"
  teardown_sandbox
}

test_create_preserves_existing_profile_data() {
  test_start "re-create keeps existing profile data"
  setup_sandbox
  create_mock_claude >/dev/null
  local data="$HOME/ClaudeWork"
  mkdir -p "$data"
  echo "precious-chat-history" >"$data/keep-me.txt"
  capture_script create Work >/dev/null
  capture_script create Work >/dev/null
  assert_file_exists "$data/keep-me.txt" "profile data untouched"
  assert_eq "precious-chat-history" "$(cat "$data/keep-me.txt")" "data content intact"
  teardown_sandbox
}

test_create_rebuilds_launcher_only() {
  test_start "re-create replaces launcher app bundle but not data dir"
  setup_sandbox
  create_mock_claude >/dev/null
  capture_script create Work >/dev/null
  echo "stale" >"$HOME/Applications/Claude Work.app/stale-marker.txt"
  capture_script create Work >/dev/null
  assert_file_missing "$HOME/Applications/Claude Work.app/stale-marker.txt" "launcher rebuilt"
  assert_file_exists "$HOME/Applications/Claude Work.app/Contents/MacOS/applet" "launcher still valid"
  teardown_sandbox
}

test_create_without_icon() {
  test_start "create succeeds when Claude.app has no .icns"
  setup_sandbox
  create_mock_claude >/dev/null
  rm -f "$CLAUDE_LAUNCHERS_CLAUDE_APP/Contents/Resources/"*.icns
  local out
  out="$(capture_script create Work 2>&1)"
  assert_contains "$out" "no source .icns found" "warns about missing icon"
  assert_file_exists "$HOME/Applications/Claude Work.app/Contents/MacOS/applet" "launcher still created"
  teardown_sandbox
}

test_label_validation() {
  test_start "create validates labels"
  setup_sandbox
  create_mock_claude >/dev/null
  capture_script create "   " "" Work >/dev/null
  assert_file_missing "$HOME/Applications/Claude .app" "empty labels ignored"
  assert_file_exists "$HOME/Applications/Claude Work.app" "valid label built"

  set +e
  local out code
  out="$(capture_script create "Bad/Label" 2>&1)"
  code=$?
  set -e
  assert_eq "1" "$code" "slash label exits 1"
  assert_contains "$out" "unsupported characters" "slash label rejected"

  set +e
  out="$(capture_script create "Client A" "client-a" 2>&1)"
  code=$?
  set -e
  assert_eq "1" "$code" "duplicate slug exits 1"
  assert_contains "$out" "duplicate profile data directory" "duplicate slug explained"
  teardown_sandbox
}

test_quoted_claude_paths() {
  test_start "create escapes Claude.app paths with quotes, dollars, backticks and backslashes"
  setup_sandbox
  create_mock_claude "$HOME/Applications/Sergej's \"Quote\" \$Apps \`tick\` Back\\Slash/Claude.app" >/dev/null
  capture_script create Work >/dev/null
  local script_path="$HOME/Applications/Claude Work.app/Contents/Resources/Scripts/main.scpt"
  local decompiled
  decompiled="$(osadecompile "$script_path" 2>/dev/null || true)"
  assert_contains "$decompiled" "Sergej'\\\\''s" "single quote was shell-escaped"
  assert_contains "$decompiled" "Quote" "double-quoted path segment survived"
  local dollar_apps_literal="\$Apps"
  local backticks_literal="\`tick\`"
  assert_contains "$decompiled" "$dollar_apps_literal" "dollar sign was not expanded"
  assert_contains "$decompiled" "$backticks_literal" "backticks were not evaluated"
  assert_contains "$decompiled" "Back\\\\Slash" "backslash survived escaping"
  teardown_sandbox
}

test_clean_removes_generated_launchers() {
  test_start "clean removes generated launchers"
  setup_sandbox
  create_generated_launcher "Work"
  create_generated_launcher "Personal"
  local out
  out="$(capture_script clean)"
  assert_contains "$out" "Removing launcher: Claude Work.app" "removes Work"
  assert_contains "$out" "Removing launcher: Claude Personal.app" "removes Personal"
  assert_file_missing "$HOME/Applications/Claude Work.app" "Work launcher gone"
  assert_file_missing "$HOME/Applications/Claude Personal.app" "Personal launcher gone"
  teardown_sandbox
}

test_clean_keeps_profile_data_by_default() {
  test_start "clean keeps profile data by default"
  setup_sandbox
  create_generated_launcher "Work"
  local data="$HOME/ClaudeWork"
  mkdir -p "$data"
  echo "keep" >"$data/history.db"
  local out
  out="$(capture_script clean)"
  assert_contains "$out" "kept profile data" "reports data kept"
  assert_file_exists "$data/history.db" "profile data still on disk"
  teardown_sandbox
}

test_clean_safety() {
  test_start "clean skips unrelated apps and plain Claude.app"
  setup_sandbox
  create_real_claude_stub
  create_unmarked_applet_launcher "Other"
  create_generated_launcher "Work"
  local out
  out="$(capture_script clean)"
  assert_contains "$out" "skip (not a generated launcher): Claude Other.app" "unmarked applet skipped"
  assert_file_exists "$HOME/Applications/Claude Other.app" "unmarked applet left intact"
  assert_file_exists "$HOME/Applications/Claude.app/Contents/MacOS/Claude" "plain Claude.app intact"
  assert_file_missing "$HOME/Applications/Claude Work.app" "marked launcher removed"
  teardown_sandbox
}

test_clean_nothing_to_do() {
  test_start "clean with no launchers is a no-op success"
  setup_sandbox
  local out
  out="$(capture_script clean)"
  assert_contains "$out" "Nothing to clean" "friendly message"
  teardown_sandbox
}

test_clean_purge() {
  test_start "clean --purge prompts and deletes only when confirmed"
  setup_sandbox
  create_generated_launcher "Work"
  local data="$HOME/ClaudeWork"
  mkdir -p "$data"
  echo "secret" >"$data/secret.txt"
  unset CLAUDE_LAUNCHERS_PURGE_ANSWER 2>/dev/null || true
  local out
  out="$(capture_script clean --purge)"
  assert_contains "$out" "Delete profile data" "asks before delete"
  assert_contains "$out" "kept $data" "declined delete"
  assert_file_exists "$data/secret.txt" "data preserved"

  create_generated_launcher "Work"
  export CLAUDE_LAUNCHERS_PURGE_ANSWER="y"
  out="$(capture_script clean --purge)"
  assert_contains "$out" "deleted $data" "reports deletion"
  assert_file_missing "$data" "data directory removed"
  teardown_sandbox
}

test_clean_purge_never_targets_plain_claude_app() {
  test_start "clean --purge never deletes plain Claude.app or unrelated data"
  setup_sandbox
  create_real_claude_stub
  create_generated_launcher "Personal"
  local data="$HOME/ClaudePersonal"
  mkdir -p "$data"
  echo "personal-data" >"$data/secret.txt"
  export CLAUDE_LAUNCHERS_PURGE_ANSWER="y"
  local out
  out="$(capture_script clean --purge)"
  assert_contains "$out" "deleted $data" "deletes generated profile data when confirmed"
  assert_file_exists "$HOME/Applications/Claude.app/Contents/MacOS/Claude" "plain Claude.app intact"
  assert_not_contains "$out" "Delete profile data at $HOME/Applications/Claude.app" "never offers to purge Claude.app"
  teardown_sandbox
}

test_full_lifecycle() {
  test_start "full lifecycle: create -> clean -> re-create"
  setup_sandbox
  create_mock_claude >/dev/null
  capture_script create Work Personal >/dev/null
  assert_file_exists "$HOME/Applications/Claude Work.app"
  assert_file_exists "$HOME/Applications/Claude Personal.app"
  mkdir -p "$HOME/ClaudeWork" "$HOME/ClaudePersonal"
  echo "work-data" >"$HOME/ClaudeWork/x"
  echo "personal-data" >"$HOME/ClaudePersonal/y"
  capture_script clean >/dev/null
  assert_file_missing "$HOME/Applications/Claude Work.app"
  assert_file_missing "$HOME/Applications/Claude Personal.app"
  assert_file_exists "$HOME/ClaudeWork/x" "work data survives clean"
  assert_file_exists "$HOME/ClaudePersonal/y" "personal data survives clean"
  capture_script create Work >/dev/null
  assert_file_exists "$HOME/Applications/Claude Work.app"
  assert_eq "work-data" "$(cat "$HOME/ClaudeWork/x")" "re-create reuses existing profile"
  teardown_sandbox
}

test_script_syntax() {
  test_start "script passes bash -n syntax check"
  bash -n "$SCRIPT"
  pass "bash -n succeeded"
}

test_script_is_executable() {
  test_start "script is executable"
  assert_true "script bit is set" test -x "$SCRIPT"
}

main() {
  echo "Running claude-fix tests"
  echo "Script: $SCRIPT"
  echo "Platform: $(uname -s) $(uname -m)"

  test_script_syntax
  test_script_is_executable
  test_slug_mapping
  test_help
  test_help_aliases
  test_not_installed_create_fails
  test_not_installed_implicit_create_fails
  test_not_installed_clean_still_works
  test_installed_not_running_create_succeeds
  test_installed_running_create_and_clean_do_not_kill_claude
  test_create_default_profiles
  test_onboarding_existing_personal_creates_work
  test_desktop_shortcuts_option
  test_no_desktop_option
  test_launch_option_prints_first_time_setup
  test_launch_option_multi_profile
  test_no_launch_option_keeps_profiles_closed
  test_no_args_defaults_to_create
  test_existing_launchers_show_management_menu
  test_management_menu_opens_existing_profile
  test_management_menu_create_another_profile
  test_management_menu_start_fresh_profile
  test_create_custom_and_implicit_labels
  test_launcher_applescript_payload
  test_onboarding_reset_profile_data
  test_launcher_uses_normal_claude_icon
  test_generated_launcher_has_marker
  test_create_preserves_existing_profile_data
  test_create_rebuilds_launcher_only
  test_create_without_icon
  test_label_validation
  test_quoted_claude_paths
  test_clean_removes_generated_launchers
  test_clean_keeps_profile_data_by_default
  test_clean_safety
  test_clean_nothing_to_do
  test_clean_purge
  test_clean_purge_never_targets_plain_claude_app
  test_full_lifecycle

  print_summary
}

main "$@"
