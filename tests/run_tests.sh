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
  test_start "help prints usage and Dock options"
  setup_sandbox
  local out
  out="$(capture_script help)"
  assert_contains "$out" "Commands:" "shows commands section"
  assert_contains "$out" "clean --purge" "documents purge"
  assert_contains "$out" "--desktop" "documents Desktop shortcuts option"
  assert_contains "$out" "--launch" "documents launch option"
  assert_contains "$out" "--dock" "documents Dock pinning option"
  assert_contains "$out" "--dock-cleanup" "documents Dock cleanup option"
  assert_contains "$out" "existing Claude login" "documents existing profile model"
  assert_contains "$out" "original profile icons" "documents icon policy"
  teardown_sandbox
}

test_help_aliases() {
  test_start "help aliases (-h, --help)"
  setup_sandbox
  assert_contains "$(capture_script -h)" "make_claude_launchers.sh" "-h works"
  assert_contains "$(capture_script --help)" "create [options]" "--help works"
  teardown_sandbox
}

test_piped_execution_works() {
  test_start "piped execution (curl | bash) does not crash on BASH_SOURCE"
  setup_sandbox
  local out code
  set +e
  out="$(bash -s help 2>&1 <"$SCRIPT")"
  code=$?
  set -e
  assert_eq "0" "$code" "piped bash exits 0"
  assert_contains "$out" "make_claude_launchers.sh" "piped bash runs main dispatch"
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

test_management_menu_create_pins_to_dock() {
  test_start "management menu create can pin new launcher to Dock"
  setup_sandbox
  create_mock_claude >/dev/null
  create_mock_dock_plist
  create_generated_launcher "Personal"
  export CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE=4
  export CLAUDE_LAUNCHERS_NEW_PROFILE_NAMES="ClientA"
  export CLAUDE_LAUNCHERS_DOCK_ANSWER=y
  export CLAUDE_LAUNCHERS_FROM_MANAGEMENT=1
  local out urls client_url
  out="$(capture_script create)"
  assert_contains "$out" "Creating 1 launcher(s)" "creates requested extra profile"
  assert_contains "$out" "Dock: pinned Claude ClientA.app" "reports new Dock pin"
  assert_contains "$out" "Dock: pinned 1 launcher(s)" "summarizes Dock pinning"
  client_url="$(dock_file_url_via_script "$HOME/Applications/Claude ClientA.app")"
  urls="$(dock_persistent_urls)"
  assert_contains "$urls" "$client_url" "ClientA launcher pinned"
  assert_eq "ok" "$(dock_assert_valid_entries)" "Dock entries use native tile structure"
  teardown_sandbox
}

test_management_menu_start_fresh_profile() {
  test_start "management menu can clear local sign-in for generated profile"
  setup_sandbox
  create_mock_claude >/dev/null
  capture_script create DRD >/dev/null
  local data="$HOME/ClaudeDrd"
  mkdir -p "$data"
  printf '{"oauth:tokenCache":"stale"}\n' >"$data/config.json"
  export CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE=5
  export CLAUDE_LAUNCHERS_RESET_PROFILE_ANSWER=y
  export CLAUDE_LAUNCHERS_LAUNCH_ANSWER=n
  export CLAUDE_LAUNCHERS_DOCK_ANSWER=n
  local out
  out="$(capture_script create)"
  assert_contains "$out" "does NOT delete your Claude account" "uses safe wording"
  assert_contains "$out" "cleared local sign-in for Claude DRD" "clears local sign-in"
  assert_contains "$out" "Rebuilding launcher for Claude DRD" "rebuilds launcher after clear"
  assert_file_missing "$data" "local profile directory removed"
  teardown_sandbox
}

test_start_fresh_rebuilds_launcher() {
  test_start "start fresh rebuilds launcher app with profile icon"
  setup_sandbox
  create_mock_claude >/dev/null
  capture_script create DRD >/dev/null
  local app="$HOME/Applications/Claude DRD.app"
  echo "stale" >"$app/stale-marker.txt"
  touch "$app/Contents/Resources/Assets.car"
  mkdir -p "$HOME/ClaudeDrd"
  printf '{"oauth:tokenCache":"stale"}\n' >"$HOME/ClaudeDrd/config.json"
  export CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE=5
  export CLAUDE_LAUNCHERS_RESET_PROFILE_ANSWER=y
  export CLAUDE_LAUNCHERS_LAUNCH_ANSWER=n
  export CLAUDE_LAUNCHERS_DOCK_ANSWER=n
  capture_script create >/dev/null
  assert_file_missing "$app/stale-marker.txt" "launcher rebuilt"
  assert_file_missing "$app/Contents/Resources/Assets.car" "Assets.car removed"
  assert_file_exists "$app/Contents/Resources/applet.icns" "profile icon installed"
  assert_file_exists "$app/Contents/MacOS/applet" "launcher still valid"
  teardown_sandbox
}

test_start_fresh_repins_dock() {
  test_start "start fresh refreshes Dock pin when launcher already pinned"
  setup_sandbox
  create_mock_claude >/dev/null
  create_mock_dock_plist
  capture_script create --dock DRD >/dev/null
  local app="$HOME/Applications/Claude DRD.app"
  local drd_url
  drd_url="$(dock_file_url_via_script "$app")"
  mkdir -p "$HOME/ClaudeDrd"
  printf '{"oauth:tokenCache":"stale"}\n' >"$HOME/ClaudeDrd/config.json"
  export CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE=5
  export CLAUDE_LAUNCHERS_RESET_PROFILE_ANSWER=y
  export CLAUDE_LAUNCHERS_LAUNCH_ANSWER=n
  local out urls
  out="$(capture_script create)"
  assert_contains "$out" "Rebuilding launcher for Claude DRD" "rebuilds launcher after clear"
  assert_contains "$out" "Updating Dock" "refreshes Dock after rebuild"
  assert_contains "$out" "Dock: pinned Claude DRD.app" "re-pins launcher after rebuild"
  assert_not_contains "$out" "Dock: all launcher(s) already pinned" "does not skip with stale pin"
  urls="$(dock_persistent_urls)"
  assert_contains "$urls" "$drd_url" "DRD launcher still pinned"
  assert_eq "ok" "$(dock_assert_valid_entries)" "Dock entries use native tile structure"
  teardown_sandbox
}

test_start_fresh_pins_dock_when_not_pinned() {
  test_start "start fresh pins Dock even when launcher was not previously pinned"
  setup_sandbox
  create_mock_claude >/dev/null
  create_mock_dock_plist
  capture_script create DRD >/dev/null
  local app="$HOME/Applications/Claude DRD.app"
  local drd_url
  drd_url="$(dock_file_url_via_script "$app")"
  mkdir -p "$HOME/ClaudeDrd"
  printf '{"oauth:tokenCache":"stale"}\n' >"$HOME/ClaudeDrd/config.json"
  export CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE=5
  export CLAUDE_LAUNCHERS_RESET_PROFILE_ANSWER=y
  export CLAUDE_LAUNCHERS_LAUNCH_ANSWER=n
  local out urls before_count after_count
  before_count="$(dock_persistent_urls | grep -c "$drd_url" || true)"
  assert_eq "0" "$before_count" "DRD not pinned before start fresh"
  out="$(capture_script create)"
  assert_contains "$out" "Updating Dock" "updates Dock after rebuild"
  assert_contains "$out" "Dock: pinned Claude DRD.app" "pins launcher after start fresh"
  urls="$(dock_persistent_urls)"
  assert_contains "$urls" "$drd_url" "DRD launcher pinned"
  after_count="$(printf '%s\n' "$urls" | grep -c "$drd_url" || true)"
  assert_eq "1" "$after_count" "exactly one DRD Dock pin"
  assert_eq "ok" "$(dock_assert_valid_entries)" "Dock entries use native tile structure"
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

test_launcher_removes_assets_car() {
  test_start "launchers remove Assets.car after osacompile"
  setup_sandbox
  create_mock_claude >/dev/null
  capture_script create Work >/dev/null
  assert_file_missing "$HOME/Applications/Claude Work.app/Contents/Resources/Assets.car" "Assets.car removed"
  teardown_sandbox
}

test_launcher_profile_icons_distinct() {
  test_start "Work and Personal launchers get distinct profile icons"
  setup_sandbox
  create_mock_claude >/dev/null
  capture_script create Work Personal >/dev/null
  local work_hash personal_hash claude_hash
  work_hash="$(shasum -a 256 "$HOME/Applications/Claude Work.app/Contents/Resources/applet.icns" | awk '{print $1}')"
  personal_hash="$(shasum -a 256 "$HOME/Applications/Claude Personal.app/Contents/Resources/applet.icns" | awk '{print $1}')"
  claude_hash="$(shasum -a 256 "$CLAUDE_LAUNCHERS_CLAUDE_APP/Contents/Resources/AppIcon.icns" | awk '{print $1}')"
  assert_ne "$work_hash" "$personal_hash" "Work and Personal icons differ"
  assert_ne "$work_hash" "$claude_hash" "Work icon is not copied from Claude.app"
  assert_ne "$personal_hash" "$claude_hash" "Personal icon is not copied from Claude.app"
  teardown_sandbox
}

test_profile_icon_assignment_deterministic() {
  test_start "profile icon assignment is deterministic"
  setup_sandbox
  assert_eq "0" "$(profile_icon_index_via_script "Work")" "Work maps to profile-0"
  assert_eq "1" "$(profile_icon_index_via_script "Personal")" "Personal maps to profile-1"
  assert_eq "W" "$(profile_icon_letter_via_script "Work")" "Work letter is W"
  assert_eq "P" "$(profile_icon_letter_via_script "Personal")" "Personal letter is P"
  assert_eq "D" "$(profile_icon_letter_via_script "DRD")" "DRD letter is D"
  assert_eq "C" "$(profile_icon_letter_via_script "ClientA")" "ClientA letter is C"
  local first second
  first="$(profile_icon_index_via_script "ClientA")"
  second="$(profile_icon_index_via_script "ClientA")"
  assert_eq "$first" "$second" "custom label hash is stable"
  assert_true "custom label maps to palette 2-7" test "$first" -ge 2
  assert_true "custom label maps to palette 2-7" test "$first" -le 7
  assert_eq "$REPO_ROOT/icons/profile-0.icns" "$(profile_icon_path_via_script "Work")" "Work icon path"
  assert_eq "$REPO_ROOT/icons/profile-1.icns" "$(profile_icon_path_via_script "Personal")" "Personal icon path"
  teardown_sandbox
}

test_custom_profile_icons_have_letter_badge() {
  test_start "custom profile icons differ from palette-only icons"
  setup_sandbox
  create_mock_claude >/dev/null
  capture_script create Work Personal DRD ClientA >/dev/null
  local drd_hash client_hash work_hash personal_hash drd_idx palette_hash
  drd_hash="$(shasum -a 256 "$HOME/Applications/Claude DRD.app/Contents/Resources/applet.icns" | awk '{print $1}')"
  client_hash="$(shasum -a 256 "$HOME/Applications/Claude ClientA.app/Contents/Resources/applet.icns" | awk '{print $1}')"
  work_hash="$(shasum -a 256 "$HOME/Applications/Claude Work.app/Contents/Resources/applet.icns" | awk '{print $1}')"
  personal_hash="$(shasum -a 256 "$HOME/Applications/Claude Personal.app/Contents/Resources/applet.icns" | awk '{print $1}')"
  drd_idx="$(profile_icon_index_via_script "DRD")"
  palette_hash="$(shasum -a 256 "$REPO_ROOT/icons/profile-${drd_idx}.icns" | awk '{print $1}')"
  assert_ne "$drd_hash" "$palette_hash" "DRD icon is generated with letter badge"
  assert_ne "$drd_hash" "$work_hash" "DRD icon differs from Work"
  assert_ne "$drd_hash" "$personal_hash" "DRD icon differs from Personal"
  assert_ne "$drd_hash" "$client_hash" "DRD and ClientA icons differ"
  teardown_sandbox
}

test_dock_adds_launcher_paths() {
  test_start "--dock adds launcher paths to persistent-apps"
  setup_sandbox
  create_mock_claude >/dev/null
  create_mock_dock_plist
  capture_script create --dock Work Personal >/dev/null
  local work_url personal_url urls work_app personal_app
  work_app="$HOME/Applications/Claude Work.app"
  personal_app="$HOME/Applications/Claude Personal.app"
  work_url="$(dock_file_url_via_script "$work_app")"
  personal_url="$(dock_file_url_via_script "$personal_app")"
  urls="$(dock_persistent_urls)"
  assert_contains "$urls" "$work_url" "Work launcher pinned"
  assert_contains "$urls" "$personal_url" "Personal launcher pinned"
  assert_eq "ok" "$(dock_assert_valid_entries)" "Dock entries use native tile structure"
  assert_eq "ok" "$(dock_assert_launchers_grouped "$work_app" "$personal_app")" "launcher pins grouped"
  teardown_sandbox
}

test_dock_pins_three_launchers() {
  test_start "--dock pins Work Personal and DRD together"
  setup_sandbox
  create_mock_claude >/dev/null
  create_mock_dock_plist
  capture_script create --dock Work Personal DRD >/dev/null
  local work_app personal_app drd_app urls
  work_app="$HOME/Applications/Claude Work.app"
  personal_app="$HOME/Applications/Claude Personal.app"
  drd_app="$HOME/Applications/Claude DRD.app"
  urls="$(dock_persistent_urls)"
  assert_contains "$urls" "$(dock_file_url_via_script "$work_app")" "Work launcher pinned"
  assert_contains "$urls" "$(dock_file_url_via_script "$personal_app")" "Personal launcher pinned"
  assert_contains "$urls" "$(dock_file_url_via_script "$drd_app")" "DRD launcher pinned"
  assert_eq "ok" "$(dock_assert_valid_entries)" "all Dock entries valid"
  assert_eq "ok" "$(dock_assert_launchers_grouped "$work_app" "$personal_app" "$drd_app")" "all launcher pins grouped"
  teardown_sandbox
}

test_dock_repairs_stale_pins() {
  test_start "--dock repairs stale pins with zero mod-date"
  setup_sandbox
  create_mock_claude >/dev/null
  create_mock_dock_plist
  capture_script create --no-dock Work Personal DRD >/dev/null
  local work_app personal_app drd_app out
  work_app="$HOME/Applications/Claude Work.app"
  personal_app="$HOME/Applications/Claude Personal.app"
  drd_app="$HOME/Applications/Claude DRD.app"
  dock_seed_stale_pin "$personal_app"
  dock_seed_stale_pin "$drd_app"
  out="$(capture_script create --dock Work Personal DRD)"
  assert_contains "$out" "repaired stale pin for Claude Personal.app" "repairs Personal stale pin"
  assert_contains "$out" "repaired stale pin for Claude DRD.app" "repairs DRD stale pin"
  assert_eq "ok" "$(dock_assert_valid_entries)" "repaired Dock entries valid"
  assert_eq "ok" "$(dock_assert_launchers_grouped "$work_app" "$personal_app" "$drd_app")" "repaired pins grouped"
  teardown_sandbox
}

test_dock_is_idempotent() {
  test_start "--dock is idempotent when launcher already pinned"
  setup_sandbox
  create_mock_claude >/dev/null
  create_mock_dock_plist
  capture_script create --dock Work >/dev/null
  local before after
  before="$(dock_persistent_urls | grep -c "$(dock_file_url_via_script "$HOME/Applications/Claude Work.app")" || true)"
  capture_script create --dock Work >/dev/null
  after="$(dock_persistent_urls | grep -c "$(dock_file_url_via_script "$HOME/Applications/Claude Work.app")" || true)"
  assert_eq "$before" "$after" "no duplicate Dock pin added"
  assert_eq "1" "$after" "single Work pin remains"
  teardown_sandbox
}

test_dock_cleanup_removes_claude_duplicates() {
  test_start "--dock-cleanup removes duplicate Claude.app pins"
  setup_sandbox
  create_mock_claude >/dev/null
  create_mock_dock_plist
  dock_add_claude_pin "$CLAUDE_LAUNCHERS_CLAUDE_APP"
  dock_add_claude_pin "$CLAUDE_LAUNCHERS_CLAUDE_APP"
  local claude_url before_count
  claude_url="$(dock_file_url_via_script "$CLAUDE_LAUNCHERS_CLAUDE_APP")"
  before_count="$(dock_persistent_urls | grep -c "$claude_url" || true)"
  assert_eq "2" "$before_count" "seeded duplicate Claude pins"
  capture_script create --dock --dock-cleanup Work >/dev/null
  before_count="$(dock_persistent_urls | grep -c "$claude_url" || true)"
  assert_eq "0" "$before_count" "duplicate Claude.app pins removed"
  assert_contains "$(dock_persistent_urls)" "$(dock_file_url_via_script "$HOME/Applications/Claude Work.app")" "launcher still pinned"
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

test_create_without_icons_dir() {
  test_start "create succeeds when profile icons directory is missing"
  setup_sandbox
  create_mock_claude >/dev/null
  unset CLAUDE_LAUNCHERS_ICONS_DIR
  export CLAUDE_LAUNCHERS_ICONS_DIR="$SANDBOX/missing-icons"
  local out
  out="$(capture_script create Work 2>&1)"
  assert_contains "$out" "profile icons unavailable" "warns about missing icons dir"
  assert_file_exists "$HOME/Applications/Claude Work.app/Contents/MacOS/applet" "launcher still created"
  assert_file_missing "$HOME/Applications/Claude Work.app/Contents/Resources/Assets.car" "Assets.car still removed"
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

test_label_max_length_and_rejections() {
  test_start "labels reject length 51+, leading dot, colon"
  setup_sandbox
  create_mock_claude >/dev/null
  local ok_label="$(printf 'A%.0s' {1..50})"
  capture_script create "$ok_label" >/dev/null
  assert_file_exists "$HOME/Applications/Claude $ok_label.app" "50-char label accepted"

  local long_label="$(printf 'B%.0s' {1..51})"
  set +e
  local out code
  out="$(capture_script create "$long_label" 2>&1)"
  code=$?
  set -e
  assert_eq "1" "$code" "51-char label exits 1"
  assert_contains "$out" "too long" "51-char label rejected"

  set +e
  out="$(capture_script create ".hidden" 2>&1)"
  code=$?
  set -e
  assert_eq "1" "$code" "leading dot exits 1"
  assert_contains "$out" "unsupported characters" "leading dot rejected"

  set +e
  out="$(capture_script create "Bad:Label" 2>&1)"
  code=$?
  set -e
  assert_eq "1" "$code" "colon label exits 1"
  assert_contains "$out" "unsupported characters" "colon rejected"
  teardown_sandbox
}

test_label_allowed_special_chars() {
  test_start "labels allow apostrophe, hyphen, underscore"
  setup_sandbox
  create_mock_claude >/dev/null
  capture_script create "Client's" "side-project" "my_profile" >/dev/null
  assert_file_exists "$HOME/Applications/Claude Client's.app" "apostrophe label"
  assert_file_exists "$HOME/Applications/Claude side-project.app" "hyphen label"
  assert_file_exists "$HOME/Applications/Claude my_profile.app" "underscore label"
  assert_eq "ClaudeClients" "$(slug_via_script "Client's")" "apostrophe stripped in slug"
  assert_eq "ClaudeSideProject" "$(slug_via_script "side-project")" "hyphen slug"
  assert_eq "ClaudeMyprofile" "$(slug_via_script "my_profile")" "underscore stripped in slug"
  teardown_sandbox
}

test_label_trim_and_case_slug_collision() {
  test_start "labels trim whitespace and reject case-insensitive slug duplicates"
  setup_sandbox
  create_mock_claude >/dev/null
  capture_script create "  Work  " >/dev/null
  assert_file_exists "$HOME/Applications/Claude Work.app" "trimmed label creates launcher"
  teardown_sandbox

  setup_sandbox
  create_mock_claude >/dev/null
  set +e
  local out code
  out="$(capture_script create "Work" "WORK" 2>&1)"
  code=$?
  set -e
  assert_eq "1" "$code" "Work + WORK duplicate slug exits 1"
  assert_contains "$out" "duplicate profile data directory" "case-insensitive duplicate explained"
  teardown_sandbox
}

test_label_unicode_allowed() {
  test_start "unicode labels are accepted when printable"
  setup_sandbox
  create_mock_claude >/dev/null
  capture_script create "Café" >/dev/null
  assert_file_exists "$HOME/Applications/Claude Café.app" "unicode label accepted"
  teardown_sandbox
}

test_icons_download_to_cache() {
  test_start "curl-style install downloads icons into cache when repo icons absent"
  setup_sandbox
  create_mock_claude >/dev/null
  mkdir -p "$SANDBOX/icon-src"
  cp "$REPO_ROOT/icons/profile-"*.icns "$SANDBOX/icon-src/"
  cp "$REPO_ROOT/icons/generate_icons.swift" "$SANDBOX/icon-src/"
  # Simulate curl | bash: run a copy of the script with no sibling icons/ folder.
  cp "$SCRIPT" "$SANDBOX/make_claude_launchers.sh"
  local saved_script="$SCRIPT"
  SCRIPT="$SANDBOX/make_claude_launchers.sh"
  unset CLAUDE_LAUNCHERS_ICONS_DIR
  export CLAUDE_LAUNCHERS_ALLOW_ICON_DOWNLOAD=1
  export CLAUDE_LAUNCHERS_ICONS_BASE="file://$SANDBOX/icon-src"
  export CLAUDE_LAUNCHERS_ICONS_CACHE="$SANDBOX/icon-cache"
  local out work_hash palette_hash
  out="$(capture_script create Work 2>&1)"
  SCRIPT="$saved_script"
  assert_contains "$out" "Downloading profile icons" "reports icon download"
  assert_contains "$out" "profile icons ready" "icons download succeeded"
  assert_file_exists "$SANDBOX/icon-cache/profile-0.icns" "cached profile-0"
  assert_file_exists "$SANDBOX/icon-cache/generate_icons.swift" "cached swift generator"
  work_hash="$(shasum -a 256 "$HOME/Applications/Claude Work.app/Contents/Resources/applet.icns" | awk '{print $1}')"
  palette_hash="$(shasum -a 256 "$SANDBOX/icon-cache/profile-0.icns" | awk '{print $1}')"
  assert_eq "$palette_hash" "$work_hash" "Work launcher uses downloaded icon"
  teardown_sandbox
}

test_icons_dir_override() {
  test_start "CLAUDE_LAUNCHERS_ICONS_DIR override supplies profile icons"
  setup_sandbox
  create_mock_claude >/dev/null
  export CLAUDE_LAUNCHERS_ICONS_DIR="$REPO_ROOT/icons"
  capture_script create Work >/dev/null
  local work_hash palette_hash
  work_hash="$(shasum -a 256 "$HOME/Applications/Claude Work.app/Contents/Resources/applet.icns" | awk '{print $1}')"
  palette_hash="$(shasum -a 256 "$REPO_ROOT/icons/profile-0.icns" | awk '{print $1}')"
  assert_eq "$palette_hash" "$work_hash" "override icons dir used for Work"
  teardown_sandbox
}

test_work_personal_icons_match_palette() {
  test_start "Work and Personal icons use symbol palette without letter badge"
  setup_sandbox
  create_mock_claude >/dev/null
  capture_script create Work Personal >/dev/null
  local work_hash personal_hash
  work_hash="$(shasum -a 256 "$HOME/Applications/Claude Work.app/Contents/Resources/applet.icns" | awk '{print $1}')"
  personal_hash="$(shasum -a 256 "$HOME/Applications/Claude Personal.app/Contents/Resources/applet.icns" | awk '{print $1}')"
  assert_eq "$(shasum -a 256 "$REPO_ROOT/icons/profile-0.icns" | awk '{print $1}')" "$work_hash" "Work matches profile-0 symbol"
  assert_eq "$(shasum -a 256 "$REPO_ROOT/icons/profile-1.icns" | awk '{print $1}')" "$personal_hash" "Personal matches profile-1 symbol"
  assert_eq "W" "$(profile_icon_letter_via_script "Work")" "Work letter metadata is W"
  assert_eq "P" "$(profile_icon_letter_via_script "Personal")" "Personal letter metadata is P"
  teardown_sandbox
}

test_generate_icons_swift_failure_graceful() {
  test_start "generate_icons.swift failure falls back without breaking create"
  setup_sandbox
  create_mock_claude >/dev/null
  local icons="$SANDBOX/icons"
  mkdir -p "$icons"
  cp "$REPO_ROOT/icons/profile-"*.icns "$icons/"
  printf 'not valid swift\n' >"$icons/generate_icons.swift"
  export CLAUDE_LAUNCHERS_ICONS_DIR="$icons"
  local out
  out="$(capture_script create DRD 2>&1)"
  assert_file_exists "$HOME/Applications/Claude DRD.app/Contents/MacOS/applet" "launcher created despite icon gen failure"
  assert_file_missing "$HOME/Applications/Claude DRD.app/Contents/Resources/Assets.car" "Assets.car still removed"
  assert_not_contains "$out" "ERROR: failed to build launcher" "create did not abort"
  teardown_sandbox
}

test_dock_no_dock_skips_pinning() {
  test_start "create --no-dock does not modify Dock plist"
  setup_sandbox
  create_mock_claude >/dev/null
  create_mock_dock_plist
  capture_script create --no-dock Work Personal >/dev/null
  local urls
  urls="$(dock_persistent_urls)"
  assert_not_contains "$urls" "$(dock_file_url_via_script "$HOME/Applications/Claude Work.app")" "Work not pinned"
  assert_not_contains "$urls" "$(dock_file_url_via_script "$HOME/Applications/Claude Personal.app")" "Personal not pinned"
  teardown_sandbox
}

test_dock_pin_single_launcher() {
  test_start "--dock pins a single launcher"
  setup_sandbox
  create_mock_claude >/dev/null
  create_mock_dock_plist
  capture_script create --dock Work >/dev/null
  local urls work_url
  work_url="$(dock_file_url_via_script "$HOME/Applications/Claude Work.app")"
  urls="$(dock_persistent_urls)"
  assert_contains "$urls" "$work_url" "single Work pin added"
  assert_eq "1" "$(printf '%s\n' "$urls" | grep -c "$work_url" || true)" "exactly one Work pin"
  teardown_sandbox
}

test_dock_changes_disabled_in_test_mode() {
  test_start "dock_changes_disabled skips Dock writes without mock plist"
  setup_sandbox
  create_mock_claude >/dev/null
  unset CLAUDE_LAUNCHERS_DOCK_PLIST
  local out plist
  plist="$HOME/Library/Preferences/com.apple.dock.plist"
  out="$(capture_script create --dock Work 2>&1)"
  assert_file_exists "$HOME/Applications/Claude Work.app" "launcher created"
  assert_file_missing "$plist" "real Dock plist not created in test mode"
  assert_not_contains "$out" "Dock: pinned Claude Work.app" "no Dock pin message without mock plist"
  teardown_sandbox
}

test_dock_url_encodes_spaces_in_label() {
  test_start "Dock URLs encode spaces in Claude Personal.app path"
  setup_sandbox
  create_mock_claude >/dev/null
  create_mock_dock_plist
  capture_script create --dock Personal >/dev/null
  local urls
  urls="$(dock_persistent_urls)"
  assert_contains "$urls" "%20" "space encoded in Dock URL"
  assert_contains "$urls" "Claude%20Personal.app" "Personal app name encoded"
  teardown_sandbox
}

test_dock_url_encodes_special_path_chars() {
  test_start "Dock URLs encode special characters in launcher paths"
  setup_sandbox
  export HOME="$SANDBOX/home with spaces"
  mkdir -p "$HOME/Applications"
  create_mock_claude >/dev/null
  create_mock_dock_plist
  capture_script create --dock Work >/dev/null
  local urls
  urls="$(dock_persistent_urls)"
  assert_contains "$urls" "%20" "space in HOME path encoded"
  assert_contains "$urls" "Claude%20Work.app" "launcher name encoded"
  teardown_sandbox
}

test_dock_remove_pins_by_url_and_label() {
  test_start "dock_remove_app_pins removes matches by URL or file-label"
  setup_sandbox
  create_mock_claude >/dev/null
  create_mock_dock_plist
  capture_script create --no-dock Work >/dev/null
  local app="$HOME/Applications/Claude Work.app"
  dock_seed_stale_pin "$app"
  dock_seed_pin_label_only "$app"
  local before removed after
  before="$(python3 - "$CLAUDE_LAUNCHERS_DOCK_PLIST" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as fh:
    print(len(plistlib.load(fh).get("persistent-apps", [])))
PY
)"
  assert_eq "2" "$before" "seeded URL and label pins"
  removed="$(dock_remove_pins_via_script "$app" "$CLAUDE_LAUNCHERS_DOCK_PLIST")"
  assert_eq "2" "$removed" "removed both stale pins"
  after="$(python3 - "$CLAUDE_LAUNCHERS_DOCK_PLIST" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as fh:
    print(len(plistlib.load(fh).get("persistent-apps", [])))
PY
)"
  assert_eq "0" "$after" "no Dock pins remain"
  teardown_sandbox
}

test_profile_data_initialized_detection() {
  test_start "profile_data_initialized detects saved sign-in artifacts"
  setup_sandbox
  local dir="$HOME/ClaudeWork"
  assert_false "empty dir not initialized" profile_data_initialized_via_script "ClaudeWork"
  mkdir -p "$dir"
  assert_false "empty profile dir not initialized" profile_data_initialized_via_script "ClaudeWork"
  printf '{"oauth:tokenCache":"x"}\n' >"$dir/config.json"
  assert_true "config.json oauth marks initialized" profile_data_initialized_via_script "ClaudeWork"
  rm -f "$dir/config.json"
  touch "$dir/Local State"
  assert_true "Local State marks initialized" profile_data_initialized_via_script "ClaudeWork"
  rm -f "$dir/Local State"
  touch "$dir/Cookies"
  assert_true "Cookies marks initialized" profile_data_initialized_via_script "ClaudeWork"
  teardown_sandbox
}

test_start_fresh_declined_keeps_data() {
  test_start "start fresh declined keeps profile data and skips rebuild"
  setup_sandbox
  create_mock_claude >/dev/null
  capture_script create DRD >/dev/null
  local app="$HOME/Applications/Claude DRD.app"
  local data="$HOME/ClaudeDrd"
  echo "stale" >"$app/stale-marker.txt"
  mkdir -p "$data"
  printf '{"oauth:tokenCache":"keep"}\n' >"$data/config.json"
  export CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE=5
  export CLAUDE_LAUNCHERS_RESET_PROFILE_ANSWER=n
  local out
  out="$(capture_script create)"
  assert_contains "$out" "kept the saved local sign-in" "decline keeps sign-in"
  assert_not_contains "$out" "Rebuilding launcher" "no rebuild when declined"
  assert_file_exists "$data/config.json" "profile data preserved"
  assert_file_exists "$app/stale-marker.txt" "launcher not rebuilt"
  teardown_sandbox
}

test_management_menu_cancel() {
  test_start "management menu option 8 cancels without changes"
  setup_sandbox
  create_generated_launcher "Personal"
  export CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE=8
  local out
  out="$(capture_script create)"
  assert_contains "$out" "Cancelled. Nothing changed." "cancel message"
  assert_file_exists "$HOME/Applications/Claude Personal.app" "launcher unchanged"
  teardown_sandbox
}

test_management_menu_open_all() {
  test_start "management menu option 2 opens all generated profiles"
  setup_sandbox
  create_generated_launcher "Work"
  create_generated_launcher "Personal"
  export CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE=2
  local out
  out="$(capture_script create)"
  assert_contains "$out" "Opening Claude Work" "opens Work"
  assert_contains "$out" "Opening Claude Personal" "opens Personal"
  teardown_sandbox
}

test_management_menu_open_launchers_folder() {
  test_start "management menu option 3 opens launchers folder"
  setup_sandbox
  create_generated_launcher "Personal"
  export CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE=3
  local out
  out="$(capture_script create)"
  assert_contains "$out" "Opening launchers folder" "reports folder open"
  assert_contains "$out" "$HOME/Applications" "shows Applications path"
  teardown_sandbox
}

test_management_menu_clean_keep_data() {
  test_start "management menu option 6 removes launchers but keeps data"
  setup_sandbox
  create_generated_launcher "Work"
  local data="$HOME/ClaudeWork"
  mkdir -p "$data"
  echo "keep" >"$data/history.db"
  export CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE=6
  local out
  out="$(capture_script create)"
  assert_contains "$out" "Removing launcher: Claude Work.app" "removes launcher"
  assert_file_missing "$HOME/Applications/Claude Work.app" "launcher removed"
  assert_file_exists "$data/history.db" "profile data kept"
  teardown_sandbox
}

test_management_menu_clean_purge() {
  test_start "management menu option 7 runs clean --purge"
  setup_sandbox
  create_generated_launcher "Work"
  local data="$HOME/ClaudeWork"
  mkdir -p "$data"
  echo "secret" >"$data/secret.txt"
  export CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE=7
  export CLAUDE_LAUNCHERS_PURGE_ANSWER=y
  local out
  out="$(capture_script create)"
  assert_contains "$out" "Removing launcher: Claude Work.app" "removes launcher"
  assert_contains "$out" "deleted $data" "purges profile data"
  assert_file_missing "$data" "data directory removed"
  teardown_sandbox
}

test_non_macos_rejected() {
  test_start "non-macOS environments exit with clear error"
  setup_sandbox
  mkdir -p "$SANDBOX/bin"
  cat >"$SANDBOX/bin/uname" <<'FAKE'
#!/bin/bash
if [ "$1" = "-s" ]; then
  echo Linux
  exit 0
fi
exec /usr/bin/uname "$@"
FAKE
  chmod +x "$SANDBOX/bin/uname"
  PATH="$SANDBOX/bin:$PATH"
  set +e
  local out code
  out="$(bash "$SCRIPT" create Work 2>&1)"
  code=$?
  set -e
  assert_eq "1" "$code" "non-macOS exits 1"
  assert_contains "$out" "only works on macOS" "clear platform error"
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
  test_piped_execution_works
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
  test_management_menu_create_pins_to_dock
  test_management_menu_start_fresh_profile
  test_start_fresh_rebuilds_launcher
  test_start_fresh_repins_dock
  test_start_fresh_pins_dock_when_not_pinned
  test_create_custom_and_implicit_labels
  test_launcher_applescript_payload
  test_onboarding_reset_profile_data
  test_launcher_removes_assets_car
  test_launcher_profile_icons_distinct
  test_profile_icon_assignment_deterministic
  test_custom_profile_icons_have_letter_badge
  test_dock_adds_launcher_paths
  test_dock_pins_three_launchers
  test_dock_repairs_stale_pins
  test_dock_is_idempotent
  test_dock_cleanup_removes_claude_duplicates
  test_generated_launcher_has_marker
  test_create_preserves_existing_profile_data
  test_create_rebuilds_launcher_only
  test_create_without_icons_dir
  test_label_validation
  test_label_max_length_and_rejections
  test_label_allowed_special_chars
  test_label_trim_and_case_slug_collision
  test_label_unicode_allowed
  test_quoted_claude_paths
  test_clean_removes_generated_launchers
  test_clean_keeps_profile_data_by_default
  test_clean_safety
  test_clean_nothing_to_do
  test_clean_purge
  test_clean_purge_never_targets_plain_claude_app
  test_full_lifecycle
  test_icons_download_to_cache
  test_icons_dir_override
  test_work_personal_icons_match_palette
  test_generate_icons_swift_failure_graceful
  test_dock_no_dock_skips_pinning
  test_dock_pin_single_launcher
  test_dock_changes_disabled_in_test_mode
  test_dock_url_encodes_spaces_in_label
  test_dock_url_encodes_special_path_chars
  test_dock_remove_pins_by_url_and_label
  test_profile_data_initialized_detection
  test_start_fresh_declined_keeps_data
  test_management_menu_cancel
  test_management_menu_open_all
  test_management_menu_open_launchers_folder
  test_management_menu_clean_keep_data
  test_management_menu_clean_purge
  test_non_macos_rejected

  print_summary
}

main "$@"
