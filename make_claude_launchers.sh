#!/bin/bash
#
# make_claude_launchers.sh
# Create (or remove) isolated Claude Desktop launchers - separate profiles
# (each with its own login/history/settings/tools).
# Works on any Mac. Safe to re-run: it never deletes profile data unless asked.
#
# Usage:
#   ./make_claude_launchers.sh                       # interactive: add missing profile
#   ./make_claude_launchers.sh create Work Personal Clients
#   ./make_claude_launchers.sh create --desktop Work Personal
#   ./make_claude_launchers.sh create --launch Work Personal
#   ./make_claude_launchers.sh clean                 # remove launchers, keep data
#   ./make_claude_launchers.sh clean --purge         # remove launchers AND data
#   ./make_claude_launchers.sh help
#
set -euo pipefail

APPS="$HOME/Applications"
MARKER_FILE="Contents/Resources/claude-fix-generated"
GENERATED_LABELS=()
GENERATED_APPS=()
GENERATED_DIRS=()

require_macos() {
  if [ "$(uname -s)" != "Darwin" ]; then
    echo "ERROR: This script only works on macOS." >&2
    exit 1
  fi
}

require_tools() {
  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "ERROR: required macOS tool '$tool' not found. Cannot continue." >&2
      exit 1
    fi
  done
}

trim_label() {
  printf '%s' "$1" | awk '{$1=$1; print}'
}

can_prompt() {
  [ "${CLAUDE_LAUNCHERS_TEST_MODE:-}" != "1" ] && [ -r /dev/tty ] && [ -w /dev/tty ]
}

prompt_read() {
  local prompt="$1"
  local var_name="$2"
  local reply
  printf "%s" "$prompt"
  IFS= read -r reply </dev/tty || reply=''
  printf -v "$var_name" '%s' "$reply"
}

marker_value() {
  local marker="$1" key="$2"
  awk -F= -v key="$key" '$1 == key {print substr($0, length(key) + 2); exit}' "$marker" 2>/dev/null || true
}

validate_label() {
  local label="$1"
  if [ -z "$label" ]; then
    return 1
  fi
  if [ "${#label}" -gt 50 ]; then
    echo "ERROR: profile label is too long (max 50 characters): $label" >&2
    exit 1
  fi
  case "$label" in
    .*|*/*|*:*)
      echo "ERROR: profile label contains unsupported characters: $label" >&2
      echo "       Use letters, numbers, spaces, hyphens, underscores, or apostrophes." >&2
      exit 1
      ;;
  esac
  if printf '%s' "$label" | LC_ALL=C grep -q '[[:cntrl:]]'; then
    echo "ERROR: profile label contains control characters." >&2
    exit 1
  fi
  return 0
}

shell_quote() {
  local escaped
  escaped=$(printf '%s' "$1" | sed "s/'/'\\\\''/g")
  printf "'%s'" "$escaped"
}

applescript_escape() {
  local escaped="$1"
  escaped=${escaped//\\/\\\\}
  escaped=${escaped//\"/\\\"}
  printf '%s' "$escaped"
}

# Slugify a display name into a safe data-dir folder name
# e.g. "Big Client" -> "ClaudeBigClient", "client-a" -> "ClaudeClientA"
slug() {
  local s
  s=$(echo "$1" | tr -cd '[:alnum:][:space:]-' | tr '-' ' ' | tr -s ' ')
  s=$(echo "$s" | awk '{
    for (i = 1; i <= NF; i++) {
      w = $i
      $i = toupper(substr(w, 1, 1)) tolower(substr(w, 2))
    }
    print
  }')
  echo "Claude$(echo "$s" | tr -d ' ')"
}

profile_display_name() {
  case "$1" in
    Work) printf '%s' "Work / Company" ;;
    Personal) printf '%s' "Personal" ;;
    *) printf '%s' "$1" ;;
  esac
}

profile_data_initialized() {
  local dir_slug="$1"
  local data="$HOME/$dir_slug"
  [ -d "$data" ] || return 1
  if [ -f "$data/config.json" ] && grep -q 'oauth:tokenCache' "$data/config.json" 2>/dev/null; then
    return 0
  fi
  [ -f "$data/Local State" ] && return 0
  [ -f "$data/Cookies" ] && return 0
  return 1
}

load_generated_launchers() {
  GENERATED_LABELS=()
  GENERATED_APPS=()
  GENERATED_DIRS=()

  shopt -s nullglob
  local app marker base label dir
  for app in "$APPS/Claude "*.app; do
    marker="$app/$MARKER_FILE"
    [ -f "$marker" ] || continue
    base=$(basename "$app" .app)
    label=$(marker_value "$marker" "label")
    [ -n "$label" ] || label=${base#Claude }
    dir=$(marker_value "$marker" "data-dir")
    [ -n "$dir" ] || dir=$(slug "$label")
    GENERATED_LABELS+=("$label")
    GENERATED_APPS+=("$app")
    GENERATED_DIRS+=("$dir")
  done
  shopt -u nullglob
}

print_generated_launchers() {
  local i
  echo "Found generated profile launcher(s):"
  for ((i = 0; i < ${#GENERATED_LABELS[@]}; i++)); do
    echo "  - Claude ${GENERATED_LABELS[$i]}"
    echo "    launcher: ${GENERATED_APPS[$i]}"
    echo "    local sign-in: ~/${GENERATED_DIRS[$i]}"
  done
}

open_generated_launcher_by_index() {
  local idx="$1"
  local label="${GENERATED_LABELS[$idx]}"
  local app="${GENERATED_APPS[$idx]}"
  echo "Opening Claude $label..."
  if [ "${CLAUDE_LAUNCHERS_NO_OPEN:-}" != "1" ]; then
    open "$app"
  fi
}

open_all_generated_launchers() {
  local i
  for ((i = 0; i < ${#GENERATED_LABELS[@]}; i++)); do
    open_generated_launcher_by_index "$i"
  done
}

start_fresh_generated_profile_by_index() {
  local idx="$1"
  local label="${GENERATED_LABELS[$idx]}"
  local dir="${GENERATED_DIRS[$idx]}"
  local data="$HOME/$dir"
  local ans

  echo
  echo "Claude $label can be started fresh by clearing this launcher's local sign-in:"
  echo "  ~/$dir"
  echo
  echo "This does NOT delete your Claude account."
  echo "This does NOT change your normal Claude app."
  echo "It only clears the saved local data for the Claude $label launcher on this Mac."

  if [ -n "${CLAUDE_LAUNCHERS_RESET_PROFILE_ANSWER:-}" ]; then
    ans="$CLAUDE_LAUNCHERS_RESET_PROFILE_ANSWER"
  elif can_prompt; then
    prompt_read "Clear Claude $label local sign-in and start fresh? [y/N] " ans
  else
    echo "  kept the saved local sign-in in ~/$dir"
    return 0
  fi

  case "$ans" in
    y|Y|yes|YES|Yes)
      rm -rf "$data"
      echo "  cleared local sign-in for Claude $label"
      echo "Next: open Claude $label and sign in with the right account."
      ;;
    *)
      echo "  kept the saved local sign-in in ~/$dir"
      ;;
  esac
}

maybe_reset_onboarding_profile_data() {
  local label="$1"
  local dir_slug="$2"
  local data="$HOME/$dir_slug"
  local ans

  if ! profile_data_initialized "$dir_slug"; then
    return 0
  fi

  echo
  echo "NOTE: Claude $label already has a saved sign-in in ~/$dir_slug."
  echo "That folder is only for this launcher on your Mac."
  echo "It does not change your normal Claude app or delete your Claude account online."
  echo "Choose yes only if the wrong account opens there and you want a fresh sign-in."

  if [ -n "${CLAUDE_LAUNCHERS_RESET_PROFILE_ANSWER:-}" ]; then
    ans="$CLAUDE_LAUNCHERS_RESET_PROFILE_ANSWER"
  elif can_prompt; then
    prompt_read "Clear this launcher's local sign-in and start fresh? [y/N] " ans
  else
    echo "  kept the saved sign-in in ~/$dir_slug"
    return 0
  fi

  case "$ans" in
    y|Y|yes|YES|Yes)
      rm -rf "$data"
      echo "  cleared local sign-in for Claude $label (your normal Claude app is unchanged)"
      ;;
    *)
      echo "  kept the saved sign-in in ~/$dir_slug"
      echo "  If the wrong account opens, sign out in Claude $label or re-run and choose start fresh."
      ;;
  esac
}

select_generated_launcher() {
  local prompt="$1"
  local answer i

  if [ "${#GENERATED_LABELS[@]}" -eq 1 ]; then
    SELECTED_GENERATED_INDEX=0
    return 0
  fi

  echo
  echo "$prompt"
  for ((i = 0; i < ${#GENERATED_LABELS[@]}; i++)); do
    echo "  $((i + 1))) Claude ${GENERATED_LABELS[$i]}"
  done

  if [ -n "${CLAUDE_LAUNCHERS_PROFILE_CHOICE:-}" ]; then
    answer="$CLAUDE_LAUNCHERS_PROFILE_CHOICE"
  elif can_prompt; then
    prompt_read "Select profile: " answer
  else
    echo "No profile selected."
    return 1
  fi

  case "$answer" in
    ''|*[!0-9]*)
      echo "ERROR: unknown profile selection: $answer" >&2
      exit 1
      ;;
  esac
  if [ "$answer" -lt 1 ] || [ "$answer" -gt "${#GENERATED_LABELS[@]}" ]; then
    echo "ERROR: unknown profile selection: $answer" >&2
    exit 1
  fi
  SELECTED_GENERATED_INDEX=$((answer - 1))
}

show_existing_setup_menu() {
  local choice names
  load_generated_launchers
  [ "${#GENERATED_LABELS[@]}" -gt 0 ] || return 1

  echo
  echo "Claude Profile Switcher is already set up."
  echo
  print_generated_launchers
  echo
  echo "What would you like to do next?"
  echo "  1) Open a generated Claude profile"
  echo "  2) Open all generated Claude profiles"
  echo "  3) Open the launchers folder"
  echo "  4) Create another profile"
  echo "  5) Fix wrong account / start fresh for a generated profile"
  echo "  6) Remove generated launchers (keep local sign-ins)"
  echo "  7) Remove launchers AND local generated profile data"
  echo "  8) Cancel"

  if [ -n "${CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE:-}" ]; then
    choice="$CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE"
  elif can_prompt; then
    prompt_read "Select [1]: " choice
  else
    echo
    echo "Run a generated launcher from $APPS, or run '$0 clean' to remove setup."
    return 0
  fi

  case "${choice:-1}" in
    1)
      select_generated_launcher "Which profile should I open?"
      open_generated_launcher_by_index "$SELECTED_GENERATED_INDEX"
      ;;
    2)
      open_all_generated_launchers
      ;;
    3)
      echo "Opening launchers folder: $APPS"
      if [ "${CLAUDE_LAUNCHERS_NO_OPEN:-}" != "1" ]; then
        open "$APPS"
      fi
      ;;
    4)
      if [ -n "${CLAUDE_LAUNCHERS_NEW_PROFILE_NAMES:-}" ]; then
        names="$CLAUDE_LAUNCHERS_NEW_PROFILE_NAMES"
      elif can_prompt; then
        echo "Enter profile names separated by spaces (example: ClientA ClientB)"
        prompt_read "Profiles: " names
      else
        echo "Run '$0 create ProfileName' to create another profile."
        return 0
      fi
      local new_labels=()
      read -r -a new_labels <<< "$names"
      create_setup "${new_labels[@]}"
      ;;
    5)
      select_generated_launcher "Which profile should start fresh?"
      start_fresh_generated_profile_by_index "$SELECTED_GENERATED_INDEX"
      ;;
    6)
      clean_setup
      ;;
    7)
      clean_setup --purge
      ;;
    8)
      echo "Cancelled. Nothing changed."
      ;;
    *)
      echo "ERROR: unknown selection: $choice" >&2
      exit 1
      ;;
  esac
  return 0
}

usage() {
  cat <<MSG
make_claude_launchers.sh - manage isolated Claude Desktop profiles

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
  --yes               Skip the interactive menu (assumes existing Work, creates Personal)

Examples:
  ./make_claude_launchers.sh
  ./make_claude_launchers.sh create Work Personal Clients
  ./make_claude_launchers.sh create --desktop --launch Personal
  ./make_claude_launchers.sh clean --purge

Note:
  Your normal Claude.app keeps its current login. Generated launchers open
  isolated profiles via --user-data-dir. Running profiles may appear as
  separate same-looking Claude Dock icons.
MSG
}

find_claude() {
  # Test / CI override (skips system-wide discovery)
  if [ -n "${CLAUDE_LAUNCHERS_CLAUDE_APP:-}" ] && [ -d "$CLAUDE_LAUNCHERS_CLAUDE_APP" ]; then
    echo "$CLAUDE_LAUNCHERS_CLAUDE_APP"
    return 0
  fi
  # Test mode: never discover the developer's real system Claude install.
  if [ "${CLAUDE_LAUNCHERS_TEST_MODE:-}" = "1" ]; then
    [ -d "$HOME/Applications/Claude.app" ] && { echo "$HOME/Applications/Claude.app"; return 0; }
    return 1
  fi
  for p in "/Applications/Claude.app" "$HOME/Applications/Claude.app"; do
    [ -d "$p" ] && { echo "$p"; return 0; }
  done
  local p
  p=$(osascript -e 'POSIX path of (path to application id "com.anthropic.claudefordesktop")' 2>/dev/null || true)
  [ -n "$p" ] && [ -d "$p" ] && { echo "${p%/}"; return 0; }
  p=$(osascript -e 'POSIX path of (path to application "Claude")' 2>/dev/null || true)
  [ -n "$p" ] && [ -d "$p" ] && { echo "${p%/}"; return 0; }
  p=$(mdfind 'kMDItemCFBundleIdentifier == "com.anthropic.claudefordesktop"' 2>/dev/null | head -n1 || true)
  [ -z "$p" ] && p=$(mdfind 'kMDItemFSName == "Claude.app"' 2>/dev/null | head -n1 || true)
  [ -n "$p" ] && [ -d "$p" ] && { echo "$p"; return 0; }
  return 1
}

create_setup() {
  require_tools osacompile osascript
  mkdir -p "$APPS"

  local DESKTOP_ALIASES=0
  local LAUNCH_AFTER_CREATE=0
  local SKIP_INTERACTIVE=0
  local EXISTING_PROFILE_LABEL=""
  local RAW_LABELS=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --desktop)
        DESKTOP_ALIASES=1
        ;;
      --no-desktop)
        DESKTOP_ALIASES=0
        ;;
      --launch)
        LAUNCH_AFTER_CREATE=1
        ;;
      --no-launch)
        LAUNCH_AFTER_CREATE=0
        ;;
      --yes|-y)
        SKIP_INTERACTIVE=1
        ;;
      --)
        shift
        while [ "$#" -gt 0 ]; do
          RAW_LABELS+=("$1")
          shift
        done
        break
        ;;
      --*)
        echo "ERROR: unknown create option: $1" >&2
        echo "Run '$0 help' for usage." >&2
        exit 1
        ;;
      *)
        RAW_LABELS+=("$1")
        ;;
    esac
    shift
  done

  if [ "${#RAW_LABELS[@]}" -eq 0 ] && [ "$SKIP_INTERACTIVE" = "0" ]; then
    if show_existing_setup_menu; then
      return 0
    fi
  fi

  if [ "${#RAW_LABELS[@]}" -eq 0 ]; then
    if [ "$SKIP_INTERACTIVE" = "0" ] && can_prompt; then
      echo
      echo "Claude Profile Switcher for Mac"
      echo "Your existing Claude app keeps its current login."
      echo "This script adds a second isolated profile for your other account."
      echo
      echo "Which account is your current Claude already signed into?"
      echo "  1) Work / Company"
      echo "  2) Personal"
      echo "  3) Custom profile names"
      echo "  4) Remove generated launchers (keep profile data)"
      echo "  5) Remove generated launchers AND profile data"
      echo "  6) Cancel"
      local choice
      prompt_read "Select [1]: " choice
      case "${choice:-1}" in
        1|"")
          EXISTING_PROFILE_LABEL="Work"
          RAW_LABELS=("Personal")
          echo
          echo "Your existing Claude stays as Work / Company."
          echo "I will create Claude Personal for your personal account."
          ;;
        2)
          EXISTING_PROFILE_LABEL="Personal"
          RAW_LABELS=("Work")
          echo
          echo "Your existing Claude stays as Personal."
          echo "I will create Claude Work for your work / company account."
          ;;
        3)
          echo "Enter profile names separated by spaces (example: Work Personal ClientA)"
          local names
          prompt_read "Profiles: " names
          read -r -a RAW_LABELS <<< "$names"
          ;;
        4)
          echo
          clean_setup
          exit 0
          ;;
        5)
          echo
          clean_setup --purge
          exit 0
          ;;
        6)
          echo "Cancelled. No launchers were created."
          exit 0
          ;;
        *)
          echo "ERROR: unknown selection: $choice" >&2
          exit 1
          ;;
      esac

      if [ "${#RAW_LABELS[@]}" -gt 0 ]; then
        echo
        local desktop_answer
        prompt_read "Create Desktop launchers too? [Y/n] " desktop_answer
        case "$desktop_answer" in
          n|N|no|NO|No)
            DESKTOP_ALIASES=0
            ;;
          *)
            DESKTOP_ALIASES=1
            ;;
        esac
        echo

        local launch_answer
        if [ "${#RAW_LABELS[@]}" -eq 1 ]; then
          prompt_read "Launch the new Claude profile now? [Y/n] " launch_answer
        else
          prompt_read "Launch the new Claude profile(s) now? [Y/n] " launch_answer
        fi
        case "$launch_answer" in
          n|N|no|NO|No)
            LAUNCH_AFTER_CREATE=0
            ;;
          *)
            LAUNCH_AFTER_CREATE=1
            ;;
        esac
        echo
      fi
    else
      case "${CLAUDE_LAUNCHERS_ONBOARDING_EXISTING:-Work}" in
        Personal)
          EXISTING_PROFILE_LABEL="Personal"
          RAW_LABELS=("Work")
          ;;
        *)
          EXISTING_PROFILE_LABEL="Work"
          RAW_LABELS=("Personal")
          ;;
      esac
    fi
  fi

  local LABELS=()
  local SEEN_DIRS="
"
  local label clean_label dir
  for label in "${RAW_LABELS[@]}"; do
    clean_label=$(trim_label "$label")
    if ! validate_label "$clean_label"; then
      continue
    fi
    dir=$(slug "$clean_label")
    case "$SEEN_DIRS" in
      *"
$dir
"*)
        echo "ERROR: duplicate profile data directory from labels: $clean_label -> ~/$dir" >&2
        echo "       Choose labels that map to different profile names." >&2
        exit 1
        ;;
    esac
    SEEN_DIRS="$SEEN_DIRS$dir
"
    LABELS+=("$clean_label")
  done
  if [ "${#LABELS[@]}" -eq 0 ]; then
    echo "ERROR: no valid profile labels were provided." >&2
    exit 1
  fi

  local CLAUDE_APP
  if ! CLAUDE_APP=$(find_claude); then
    cat >&2 <<MSG
ERROR: Claude Desktop is not installed (or could not be found).

  Install it from https://claude.ai/download and re-run this script.
  If it is installed in an unusual location, move it to /Applications.
MSG
    exit 1
  fi
  echo "Found Claude at: $CLAUDE_APP"

  local SRC_ICON=""
  local ICONS=("$CLAUDE_APP/Contents/Resources/"*.icns)
  if [ -e "${ICONS[0]}" ]; then
    SRC_ICON="${ICONS[0]}"
  fi
  [ -z "$SRC_ICON" ] && echo "NOTE: no source .icns found - launchers will use the default applet icon."

  if [ -n "$EXISTING_PROFILE_LABEL" ] && [ "${#LABELS[@]}" -eq 1 ]; then
    maybe_reset_onboarding_profile_data "${LABELS[0]}" "$(slug "${LABELS[0]}")"
  fi

  make_desktop_shortcut() {
    local app="$1" name="$2"
    local desktop="$HOME/Desktop"
    [ -d "$desktop" ] || mkdir -p "$desktop"
    local desktop_app="$desktop/$name.app"
    rm -rf "$desktop_app"
    if ! cp -cR "$app" "$desktop_app" 2>/dev/null; then
      cp -R "$app" "$desktop_app"
    fi
    echo "     desktop launcher: $desktop_app"
  }

  make_launcher() {
    local label="$1"
    local name="Claude $label"
    local dir; dir=$(slug "$label")
    local app="$APPS/$name.app"
    local data="$HOME/$dir"

    if [ -d "$data" ]; then
      echo "  -> profile '$label' already has data at ~/$dir (keeping it)"
    else
      echo "  -> creating new profile '$label' at ~/$dir"
    fi

    rm -rf "$app"   # only ever removes the launcher app, never the data dir
    local cmd escaped_cmd data_dir_abs
    data_dir_abs=$(shell_quote "$data")
    cmd="open -n -a $(shell_quote "$CLAUDE_APP") --args --user-data-dir=$data_dir_abs"
    escaped_cmd=$(applescript_escape "$cmd")
    if ! osacompile -o "$app" \
      -e "do shell script \"$escaped_cmd\"" \
      >/dev/null 2>&1; then
      echo "ERROR: failed to build launcher app: $app" >&2
      exit 1
    fi
    if [ -n "$SRC_ICON" ]; then
      cp "$SRC_ICON" "$app/Contents/Resources/applet.icns"
    fi
    printf 'generated-by=claude-fix\nlabel=%s\ndata-dir=%s\n' "$label" "$dir" >"$app/$MARKER_FILE"
    touch "$app"
    echo "     built launcher: $app"
    if [ "$DESKTOP_ALIASES" = "1" ]; then
      make_desktop_shortcut "$app" "$name"
    fi
  }

  launch_created_profiles() {
    local label app
    echo
    if [ "${#LABELS[@]}" -eq 1 ]; then
      echo "Launching your new Claude profile..."
    else
      echo "Launching your new Claude profile(s)..."
    fi
    for label in "${LABELS[@]}"; do
      app="$APPS/Claude $label.app"
      echo "  -> Claude $label"
      if [ "${CLAUDE_LAUNCHERS_NO_OPEN:-}" != "1" ]; then
        open "$app"
      fi
    done
  }

  print_completion_message() {
    local label
    echo
    echo "Done."
    if [ -n "$EXISTING_PROFILE_LABEL" ] && [ "${#LABELS[@]}" -eq 1 ]; then
      label="${LABELS[0]}"
      echo "Your existing Claude remains your $(profile_display_name "$EXISTING_PROFILE_LABEL") profile."
      echo "I created Claude $label for your $(profile_display_name "$label") account."
      echo
      if [ "$LAUNCH_AFTER_CREATE" = "1" ]; then
        if profile_data_initialized "$(slug "$label")"; then
          echo "Next: check the Claude $label window that just opened."
          echo "If it shows the wrong account, sign out there or re-run this script and choose start fresh."
          echo "If it is a fresh profile, sign in with your $(profile_display_name "$label") account"
          echo "and connect the matching email, calendar, Slack, Notion, or other tools there."
        else
          echo "Next: in the Claude $label window that just opened, sign in with your $(profile_display_name "$label") account,"
          echo "then connect the matching email, calendar, Slack, Notion, or other tools there."
        fi
      else
        echo "Next: open Claude $label from $APPS, sign in with your $(profile_display_name "$label") account,"
        echo "then connect the matching email, calendar, Slack, Notion, or other tools there."
      fi
      echo
      echo "Keep using your normal Claude app for $(profile_display_name "$EXISTING_PROFILE_LABEL")."
      echo "Use Claude $label when you want the other account and tools."
    else
      echo "Launchers are in: $APPS"
      if [ "$DESKTOP_ALIASES" = "1" ]; then
        echo "Desktop launchers were also created."
      fi
      if [ "$LAUNCH_AFTER_CREATE" = "1" ]; then
        echo
        echo "Next: in each new Claude window, sign in with the account for that profile"
        echo "and connect the matching tools there."
      else
        echo "Open each launcher and sign in with the account and tools you want isolated."
      fi
    fi
    echo
    echo "Dock note: running profiles may appear as separate same-looking Claude icons."
    if [ "${#LABELS[@]}" -eq 1 ]; then
      echo "Tip: drag Claude ${LABELS[0]} to your Dock for quick access to that profile."
    else
      echo "Tip: drag the launchers to your Dock. Each opens an isolated Claude profile."
    fi
  }

  echo "Creating ${#LABELS[@]} launcher(s)..."
  for label in "${LABELS[@]}"; do
    make_launcher "$label"
  done

  if [ "$LAUNCH_AFTER_CREATE" = "1" ]; then
    launch_created_profiles
  fi

  print_completion_message
  if [ "$LAUNCH_AFTER_CREATE" != "1" ] && [ "${CLAUDE_LAUNCHERS_NO_OPEN:-}" != "1" ]; then
    open "$APPS"
  fi
}

clean_setup() {
  local purge=0
  if [ "${1:-}" = "--purge" ]; then
    purge=1
    shift || true
  fi
  if [ "$#" -gt 0 ]; then
    echo "ERROR: unknown clean option: $1" >&2
    echo "Run '$0 help' for usage." >&2
    exit 1
  fi
  mkdir -p "$APPS"

  shopt -s nullglob
  local found=0 app base label data ans
  for app in "$APPS/Claude "*.app; do
    [ -e "$app" ] || continue
    # Only touch launchers this script generated, never the real Claude.app or
    # unrelated AppleScript applets that happen to share the "Claude *.app" name.
    if [ ! -f "$app/$MARKER_FILE" ]; then
      echo "  skip (not a generated launcher): $(basename "$app")"
      continue
    fi
    found=1
    base=$(basename "$app" .app)
    label=${base#Claude }
    data="$HOME/$(slug "$label")"

    echo "Removing launcher: $base.app"
    rm -rf "$app"

    if [ "$purge" = "1" ]; then
      if [ -d "$data" ]; then
        if [ -n "${CLAUDE_LAUNCHERS_PURGE_ANSWER:-}" ]; then
          ans="$CLAUDE_LAUNCHERS_PURGE_ANSWER"
        else
          printf "  Delete profile data at %s ? [y/N] " "$data"
          read -r ans </dev/tty 2>/dev/null || ans=""
        fi
        if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
          rm -rf "$data"
          echo "  deleted $data"
        else
          echo "  kept $data"
        fi
      fi
    elif [ -d "$data" ]; then
      echo "  (kept profile data at $data)"
    fi
  done
  shopt -u nullglob

  if [ "$found" = "0" ]; then
    echo "No generated Claude launchers found in $APPS. Nothing to clean."
    return 0
  fi

  echo
  echo "Cleaned - back to standard: only the normal Claude.app remains."
  [ "$purge" = "0" ] && echo "Profile data (~/Claude*) was kept. To remove it too, run: clean --purge"
  if [ "${CLAUDE_LAUNCHERS_NO_OPEN:-}" != "1" ]; then
    open "$APPS" 2>/dev/null || true
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_macos

  cmd="${1:-create}"
  case "$cmd" in
    clean)
      shift
      clean_setup "$@"
      ;;
    create)
      [ "$#" -gt 0 ] && shift
      create_setup "$@"
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      # No recognized subcommand -> treat all args as labels for "create"
      create_setup "$@"
      ;;
  esac
fi
