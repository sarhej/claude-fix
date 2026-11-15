#!/bin/bash
#
# make_claude_launchers.sh
# Claude Profile Switcher for Mac — install: curl -fsSL .../main/make_claude_launchers.sh | bash
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
#   ./make_claude_launchers.sh create --claude-config-dir ~/.claude-personal Personal
#   ./make_claude_launchers.sh doctor
#   ./make_claude_launchers.sh oauth-router on
#   ./make_claude_launchers.sh help
#
set -euo pipefail

APPS="$HOME/Applications"
MARKER_FILE="Contents/Resources/claude-fix-generated"
LAUNCH_SCRIPT_REL="Contents/Resources/launch-profile.sh"
ROUTER_HELPER_REL="Contents/Resources/link-router.sh"
ROUTER_NAME="Claude Fix Links"
ROUTER_APP="$APPS/$ROUTER_NAME.app"
ROUTER_BUNDLE_ID="com.sarhej.claude-fix.links"
CLAUDE_BUNDLE_ID="com.anthropic.claudefordesktop"
# Release version of this script (Homebrew formula / tags).
SCRIPT_VERSION="1.4.0"
# v6 = optional oauth-router reclaim nudge from launch helpers
# v5 = optional CLAUDE_CONFIG_DIR on open (Desktop ↔ Claude Code handoff)
# v4 = focus only real Claude.app processes (not awk/ps false positives); fall through if focus fails
LAUNCHER_VERSION=6
ICON_COUNT=8
GENERATED_LABELS=()
GENERATED_APPS=()
GENERATED_DIRS=()
CLAUDE_APP=""
# When 1, CREATE_CLAUDE_CONFIG_DIR (may be empty) overrides any previous marker value.
CREATE_CLAUDE_CONFIG_DIR_SET=0
CREATE_CLAUDE_CONFIG_DIR=""

script_dir() {
  local src="${BASH_SOURCE[0]:-}"
  [ -n "$src" ] || return 1
  cd "$(dirname "$src")" && pwd
}

icons_cache_dir() {
  printf '%s' "${CLAUDE_LAUNCHERS_ICONS_CACHE:-$HOME/.claude-fix/icons}"
}

icons_raw_base() {
  printf '%s' "${CLAUDE_LAUNCHERS_ICONS_BASE:-https://raw.githubusercontent.com/sarhej/claude-fix/heads/main/icons}"
}

icons_cache_ready() {
  local cache
  cache=$(icons_cache_dir)
  [ -f "$cache/profile-0.icns" ] && [ -f "$cache/profile-1.icns" ] && [ -f "$cache/generate_icons.swift" ]
}

icon_download_disabled() {
  [ "${CLAUDE_LAUNCHERS_NO_ICON_DOWNLOAD:-}" = "1" ] && return 0
  [ "${CLAUDE_LAUNCHERS_TEST_MODE:-}" = "1" ] && [ "${CLAUDE_LAUNCHERS_ALLOW_ICON_DOWNLOAD:-}" != "1" ] && return 0
  return 1
}

download_icons_to_cache() {
  local cache base i name
  cache=$(icons_cache_dir)
  base=$(icons_raw_base)
  mkdir -p "$cache"
  for ((i = 0; i < ICON_COUNT; i++)); do
    name="profile-${i}.icns"
    if [ ! -f "$cache/$name" ]; then
      curl -fsSL "${base}/${name}" -o "$cache/$name" || return 1
    fi
  done
  if [ ! -f "$cache/generate_icons.swift" ]; then
    curl -fsSL "${base}/generate_icons.swift" -o "$cache/generate_icons.swift" || return 1
  fi
  return 0
}

ensure_icons_available() {
  if icons_dir >/dev/null 2>&1; then
    return 0
  fi
  if [ -n "${CLAUDE_LAUNCHERS_ICONS_DIR:-}" ]; then
    return 1
  fi
  if icon_download_disabled; then
    return 1
  fi
  echo "Downloading profile icons to $(icons_cache_dir)..."
  if download_icons_to_cache && icons_dir >/dev/null 2>&1; then
    echo "  profile icons ready"
    return 0
  fi
  echo "NOTE: could not download profile icons (check network or try again later)." >&2
  return 1
}

icons_dir() {
  local base cache
  if [ -n "${CLAUDE_LAUNCHERS_ICONS_DIR:-}" ]; then
    [ -d "$CLAUDE_LAUNCHERS_ICONS_DIR" ] || return 1
    printf '%s' "$CLAUDE_LAUNCHERS_ICONS_DIR"
    return 0
  fi
  if base=$(script_dir 2>/dev/null) && [ -d "$base/icons" ]; then
    printf '%s/icons' "$base"
    return 0
  fi
  if icons_cache_ready; then
    cache=$(icons_cache_dir)
    printf '%s' "$cache"
    return 0
  fi
  return 1
}

profile_icon_index() {
  local label="$1"
  case "$label" in
    Work) printf '0' ;;
    Personal) printf '1' ;;
    *)
      local hash num
      hash=$(printf '%s' "$label" | shasum -a 256 | awk '{print $1}')
      num=$((16#${hash:0:8}))
      printf '%s' $((2 + num % 6))
      ;;
  esac
}

profile_icon_letter() {
  local label="$1" first
  case "$label" in
    Work) printf 'W' ;;
    Personal) printf 'P' ;;
    *)
      first=$(printf '%s' "$label" | LC_ALL=C grep -o '[[:alnum:]]' | head -1)
      if [ -n "$first" ]; then
        printf '%s' "$first" | tr '[:lower:]' '[:upper:]'
      else
        printf '?'
      fi
      ;;
  esac
}

profile_icon_path() {
  local label="$1"
  local dir idx
  if ! dir=$(icons_dir); then
    return 1
  fi
  idx=$(profile_icon_index "$label")
  if [ -f "$dir/profile-${idx}.icns" ]; then
    printf '%s/profile-%s.icns' "$dir" "$idx"
    return 0
  fi
  return 1
}

generate_profile_icon() {
  local label="$1" output="$2"
  local dir idx letter script icon_path
  case "$label" in
    Work|Personal)
      if icon_path=$(profile_icon_path "$label"); then
        cp "$icon_path" "$output"
        return 0
      fi
      return 1
      ;;
    *)
      if ! dir=$(icons_dir); then
        return 1
      fi
      script="$dir/generate_icons.swift"
      if [ ! -f "$script" ]; then
        return 1
      fi
      idx=$(profile_icon_index "$label")
      letter=$(profile_icon_letter "$label")
      if swift "$script" --index "$idx" --letter "$letter" --output "$output" >/dev/null 2>&1; then
        return 0
      fi
      return 1
      ;;
  esac
}

dock_plist_path() {
  if [ -n "${CLAUDE_LAUNCHERS_DOCK_PLIST:-}" ]; then
    printf '%s' "$CLAUDE_LAUNCHERS_DOCK_PLIST"
    return 0
  fi
  printf '%s/Library/Preferences/com.apple.dock.plist' "$HOME"
}

dock_changes_disabled() {
  [ "${CLAUDE_LAUNCHERS_TEST_MODE:-}" = "1" ] && [ -z "${CLAUDE_LAUNCHERS_DOCK_PLIST:-}" ]
}

dock_file_url() {
  local path="$1"
  local abs
  abs=$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")
  case "$abs" in
    */) ;;
    *) abs="${abs}/" ;;
  esac
  python3 - "$abs" <<'PY'
import sys, urllib.parse
print("file://" + urllib.parse.quote(sys.argv[1], safe="/"))
PY
}

dock_persistent_app_count() {
  local plist="$1"
  python3 - "$plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as fh:
    data = plistlib.load(fh)
print(len(data.get("persistent-apps", [])))
PY
}

dock_persistent_app_url() {
  local plist="$1" index="$2"
  python3 - "$plist" "$index" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as fh:
    data = plistlib.load(fh)
apps = data.get("persistent-apps", [])
idx = int(sys.argv[2])
if 0 <= idx < len(apps):
    print(apps[idx].get("tile-data", {}).get("file-data", {}).get("_CFURLString", ""))
PY
}

dock_app_is_pinned() {
  local app_path="$1"
  local plist="$2"
  python3 - "$plist" "$app_path" <<'PY'
import os, plistlib, sys, urllib.parse

def normalize_url(path):
    path = os.path.abspath(path)
    if not path.endswith("/"):
        path += "/"
    return "file://" + urllib.parse.quote(path, safe="/")

def url_match(a, b):
    return urllib.parse.unquote(a or "").rstrip("/").lower() == urllib.parse.unquote(b or "").rstrip("/").lower()

def entry_is_valid(entry):
    tile = entry.get("tile-data", {})
    file_data = tile.get("file-data", {})
    if not file_data.get("_CFURLString"):
        return False
    if file_data.get("_CFURLStringType") != 15:
        return False
    if entry.get("tile-type") != "file-tile":
        return False
    if not tile.get("file-mod-date"):
        return False
    return True

plist = sys.argv[1]
app_path = sys.argv[2]
want = normalize_url(app_path)
label = os.path.basename(app_path).removesuffix(".app")

with open(plist, "rb") as fh:
    data = plistlib.load(fh)

for entry in data.get("persistent-apps", []):
    tile = entry.get("tile-data", {})
    url = tile.get("file-data", {}).get("_CFURLString", "")
    if url_match(url, want) or tile.get("file-label") == label:
        if entry_is_valid(entry):
            raise SystemExit(0)

raise SystemExit(1)
PY
}

dock_write_launcher_pins() {
  local plist="$1"
  local cleanup="$2"
  shift 2 || true
  python3 - "$plist" "$cleanup" "$@" <<'PY'
import json, os, plistlib, sys, urllib.parse, uuid

APPLE_EPOCH_OFFSET = 2082844800


def normalize_url(path):
    path = os.path.abspath(path)
    if not path.endswith("/"):
        path += "/"
    return "file://" + urllib.parse.quote(path, safe="/")


def url_match(a, b):
    return urllib.parse.unquote(a or "").rstrip("/").lower() == urllib.parse.unquote(b or "").rstrip("/").lower()


def apple_hfs_time(unix_time):
    return int(unix_time + APPLE_EPOCH_OFFSET)


def entry_url(entry):
    return entry.get("tile-data", {}).get("file-data", {}).get("_CFURLString", "")


def entry_label(entry):
    return entry.get("tile-data", {}).get("file-label", "")


def entry_is_valid(entry):
    tile = entry.get("tile-data", {})
    file_data = tile.get("file-data", {})
    if not file_data.get("_CFURLString"):
        return False
    if file_data.get("_CFURLStringType") != 15:
        return False
    if entry.get("tile-type") != "file-tile":
        return False
    if not tile.get("file-mod-date"):
        return False
    return True


def make_tile(app_path, url, label):
    stat = os.stat(app_path)
    parent_stat = os.stat(os.path.dirname(app_path))
    tile = {
        "tile-type": "file-tile",
        "GUID": str(uuid.uuid4()).upper(),
        "tile-data": {
            "file-data": {
                "_CFURLString": url,
                "_CFURLStringType": 15,
            },
            "file-label": label,
            "file-type": 41,
            "file-mod-date": apple_hfs_time(stat.st_mtime),
            "parent-mod-date": apple_hfs_time(parent_stat.st_mtime),
            "dock-extra": False,
            "is-beta": False,
        },
    }
    return tile


def matching_indices(apps, url, label):
    matches = []
    for idx, entry in enumerate(apps):
        if url_match(entry_url(entry), url) or entry_label(entry) == label:
            matches.append(idx)
    return matches


def group_launcher_indices(apps, launcher_urls):
    indices = []
    for idx, entry in enumerate(apps):
        if any(url_match(entry_url(entry), url) for url in launcher_urls):
            indices.append(idx)
    if len(indices) < 2:
        return
    tiles = [apps[idx] for idx in indices]
    for idx in reversed(indices):
        del apps[idx]
    insert_at = indices[0]
    for offset, tile in enumerate(tiles):
        apps.insert(insert_at + offset, tile)


plist_path = sys.argv[1]
cleanup = sys.argv[2] == "1"
app_paths = sys.argv[3:]

with open(plist_path, "rb") as fh:
    data = plistlib.load(fh)

apps = data.setdefault("persistent-apps", [])
results = []

if cleanup and len(sys.argv) > 3:
    cleanup_path = os.environ.get("CLAUDE_LAUNCHERS_CLAUDE_APP", "")
    if cleanup_path and os.path.exists(cleanup_path):
        cleanup_url = normalize_url(cleanup_path)
        removed = 0
        for idx in range(len(apps) - 1, -1, -1):
            if url_match(entry_url(apps[idx]), cleanup_url):
                del apps[idx]
                removed += 1
        if removed:
            results.append({"status": "cleanup", "removed": removed})

launcher_urls = []
for app_path in app_paths:
    base = os.path.basename(app_path)
    if not os.path.isdir(app_path):
        results.append({"app": base, "status": "failed", "reason": "launcher not found"})
        continue

    url = normalize_url(app_path)
    label = base.removesuffix(".app")
    launcher_urls.append(url)
    matches = matching_indices(apps, url, label)

    valid_idx = None
    for idx in matches:
        if entry_is_valid(apps[idx]):
            valid_idx = idx
            break

    if valid_idx is not None:
        for idx in reversed(matches):
            if idx != valid_idx:
                del apps[idx]
        results.append({"app": base, "status": "already"})
        continue

    stale = bool(matches)
    for idx in reversed(matches):
        del apps[idx]

    apps.append(make_tile(app_path, url, label))
    results.append({"app": base, "status": "repaired" if stale else "pinned"})

group_launcher_indices(apps, launcher_urls)

with open(plist_path, "wb") as fh:
    plistlib.dump(data, fh)

print(json.dumps(results))
PY
}

dock_launcher_url_matches() {
  local url="$1"
  local want="$2"
  local want_no_slash="${want%/}"
  local url_no_slash="${url%/}"
  [ "$url" = "$want" ] || [ "$url" = "$want_no_slash" ] || [ "$url_no_slash" = "$want_no_slash" ]
}

dock_persistent_app_label() {
  local plist="$1" index="$2"
  /usr/libexec/PlistBuddy -c "Print :persistent-apps:$index:tile-data:file-label" "$plist" 2>/dev/null || true
}

dock_remove_app_pins() {
  local app_path="$1"
  local plist="$2"
  python3 - "$plist" "$app_path" <<'PY'
import os, plistlib, sys, urllib.parse

def normalize_url(path):
    path = os.path.abspath(path)
    if not path.endswith("/"):
        path += "/"
    return "file://" + urllib.parse.quote(path, safe="/")

def url_match(a, b):
    return urllib.parse.unquote(a or "").rstrip("/").lower() == urllib.parse.unquote(b or "").rstrip("/").lower()

plist = sys.argv[1]
app_path = sys.argv[2]
want = normalize_url(app_path)
label = os.path.basename(app_path).removesuffix(".app")

with open(plist, "rb") as fh:
    data = plistlib.load(fh)

apps = data.get("persistent-apps", [])
removed = 0
for idx in range(len(apps) - 1, -1, -1):
    tile = apps[idx].get("tile-data", {})
    url = tile.get("file-data", {}).get("_CFURLString", "")
    entry_label = tile.get("file-label", "")
    if url_match(url, want) or entry_label == label:
        del apps[idx]
        removed += 1

with open(plist, "wb") as fh:
    plistlib.dump(data, fh)

print(removed)
PY
}

dock_cleanup_claude_duplicates() {
  local claude_app="$1"
  local plist="$2"
  dock_remove_app_pins "$claude_app" "$plist"
}

dock_restart() {
  if dock_changes_disabled; then
    return 0
  fi
  killall Dock >/dev/null 2>&1 || true
}

prompt_pin_to_dock_setting() {
  local prompt_msg="$1"
  local dock_answer

  if [ "${PIN_TO_DOCK:- -1}" -ge 0 ] 2>/dev/null; then
    return 0
  fi

  if [ -n "${CLAUDE_LAUNCHERS_DOCK_ANSWER:-}" ]; then
    case "$CLAUDE_LAUNCHERS_DOCK_ANSWER" in
      n|N|no|NO|No)
        PIN_TO_DOCK=0
        ;;
      *)
        PIN_TO_DOCK=1
        ;;
    esac
    return 0
  fi

  if ! can_prompt; then
    return 0
  fi

  prompt_read "$prompt_msg" dock_answer
  case "$dock_answer" in
    n|N|no|NO|No)
      PIN_TO_DOCK=0
      ;;
    *)
      PIN_TO_DOCK=1
      ;;
  esac
}

pin_launchers_to_dock() {
  local cleanup="${1:-0}"
  shift || true
  local apps=("$@")
  local plist claude_app removed=0
  local pinned=0 already=0 repaired=0 failed=0
  local app base changed=0
  local results_json status reason

  if dock_changes_disabled; then
    return 0
  fi

  plist=$(dock_plist_path)
  if [ ! -f "$plist" ]; then
    printf '%s\n' "NOTE: Dock preferences not found at $plist; skipping Dock pinning." >&2
    printf '%s\n' "       Drag launchers from ~/Applications onto the Dock, or re-run with --dock." >&2
    return 1
  fi

  claude_app=""
  if [ "$cleanup" = "1" ]; then
    claude_app=$(find_claude 2>/dev/null || true)
    if [ -n "$claude_app" ]; then
      export CLAUDE_LAUNCHERS_CLAUDE_APP="$claude_app"
    fi
  fi

  if ! results_json=$(dock_write_launcher_pins "$plist" "$cleanup" "${apps[@]}"); then
    echo "  Dock: FAILED to update com.apple.dock.plist" >&2
    return 1
  fi

  while IFS=$'\t' read -r status base reason removed; do
    case "$status" in
      cleanup)
        echo "Removed $removed duplicate Claude.app pin(s) from the Dock."
        changed=1
        ;;
      pinned)
        echo "  Dock: pinned $base"
        pinned=$((pinned + 1))
        changed=1
        ;;
      repaired)
        echo "  Dock: repaired stale pin for $base"
        repaired=$((repaired + 1))
        changed=1
        ;;
      already)
        echo "  Dock: already pinned $base"
        already=$((already + 1))
        ;;
      failed)
        if [ -n "$reason" ]; then
          echo "  Dock: FAILED $base ($reason)" >&2
        else
          echo "  Dock: FAILED $base (could not update com.apple.dock.plist)" >&2
        fi
        failed=$((failed + 1))
        ;;
    esac
  done < <(python3 -c 'import json,sys
for item in json.loads(sys.argv[1]):
    status = item.get("status", "")
    app = item.get("app", "launcher")
    reason = item.get("reason", "")
    removed = str(item.get("removed", ""))
    print("\t".join([status, app, reason, removed]))
' "$results_json")

  if [ "$changed" -eq 1 ]; then
    dock_restart
  fi

  echo
  if [ "$failed" -gt 0 ]; then
    echo "Dock pinning incomplete: $pinned pinned, $repaired repaired, $already already pinned, $failed failed." >&2
    echo "Try: $0 create --dock ${apps[*]##*/}" >&2
    echo "Or drag the launcher(s) from ~/Applications onto the Dock." >&2
    return 1
  fi
  if [ "$pinned" -eq 0 ] && [ "$repaired" -eq 0 ] && [ "$already" -gt 0 ]; then
    echo "Dock: all launcher(s) already pinned ($already)."
  elif [ "$pinned" -gt 0 ] || [ "$repaired" -gt 0 ]; then
    if [ "$already" -gt 0 ]; then
      echo "Dock: pinned $pinned launcher(s), repaired $repaired stale pin(s); $already already pinned."
    elif [ "$repaired" -gt 0 ] && [ "$pinned" -gt 0 ]; then
      echo "Dock: pinned $pinned launcher(s), repaired $repaired stale pin(s)."
    elif [ "$repaired" -gt 0 ]; then
      echo "Dock: repaired $repaired stale Dock pin(s)."
    else
      echo "Dock: pinned $pinned launcher(s)."
    fi
  fi
  return 0
}

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

# Expand a leading ~ to $HOME; leave absolute and relative paths as-is.
expand_user_path() {
  local p="$1"
  if [ "$p" = "~" ]; then
    printf '%s' "$HOME"
  elif [ "${p#"~/"}" != "$p" ]; then
    printf '%s/%s' "$HOME" "${p#"~/"}"
  else
    printf '%s' "$p"
  fi
}

wrappers_bin_dir() {
  printf '%s' "${CLAUDE_LAUNCHERS_WRAPPERS_DIR:-$HOME/.claude-fix/bin}"
}

cli_wrapper_name() {
  local label="$1"
  local s
  s=$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//')
  [ -n "$s" ] || s="profile"
  printf 'claude-%s' "$s"
}

write_cli_wrapper() {
  local label="$1"
  local config_dir="$2"
  local bin name path
  bin=$(wrappers_bin_dir)
  mkdir -p "$bin"
  name=$(cli_wrapper_name "$label")
  path="$bin/$name"
  cat >"$path" <<EOF
#!/bin/bash
# claude-fix CLI wrapper for profile $(shell_quote "$label")
export CLAUDE_CONFIG_DIR=$(shell_quote "$config_dir")
exec claude "\$@"
EOF
  chmod +x "$path"
  echo "     CLI wrapper: $path"
  echo "       (add $bin to your PATH, then run: $name)"
}

remove_cli_wrapper() {
  local label="$1"
  local path
  path="$(wrappers_bin_dir)/$(cli_wrapper_name "$label")"
  if [ -f "$path" ]; then
    rm -f "$path"
    echo "     removed CLI wrapper: $path"
  fi
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
    # Skip the optional link router (not a profile).
    [ "$(marker_value "$marker" "kind")" = "router" ] && continue
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

oauth_router_state_dir() {
  printf '%s' "${CLAUDE_LAUNCHERS_ROUTER_DIR:-$HOME/.claude-fix/oauth-router}"
}

oauth_router_enabled() {
  [ -f "$(oauth_router_state_dir)/enabled" ] && [ -d "$ROUTER_APP" ] && [ -f "$ROUTER_APP/$MARKER_FILE" ]
}

print_generated_launchers() {
  local i cfg
  echo "Found generated profile launcher(s):"
  for ((i = 0; i < ${#GENERATED_LABELS[@]}; i++)); do
    echo "  - Claude ${GENERATED_LABELS[$i]}"
    echo "    launcher: ${GENERATED_APPS[$i]}"
    echo "    local sign-in: ~/${GENERATED_DIRS[$i]}"
    cfg=$(marker_value "${GENERATED_APPS[$i]}/$MARKER_FILE" "claude-config-dir")
    if [ -n "$cfg" ]; then
      echo "    Claude Code config: $cfg"
    fi
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
      echo
      require_tools osacompile osascript
      if ensure_claude_app; then
        ensure_icons_available >/dev/null 2>&1 || true
        echo "Rebuilding launcher for Claude $label..."
        if ! make_launcher "$label" 0; then
          echo "NOTE: Could not rebuild launcher for Claude $label." >&2
          echo "Next: open Claude $label and sign in with the right account."
          return 0
        fi
        refresh_dock_after_start_fresh "$idx"
        maybe_open_after_start_fresh "$idx"
      else
        echo "NOTE: Could not rebuild launcher (Claude Desktop not found)."
        echo "Next: open Claude $label and sign in with the right account."
      fi
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
  local choice names ans
  load_generated_launchers
  [ "${#GENERATED_LABELS[@]}" -gt 0 ] || return 1

  if any_launcher_outdated; then
    echo
    echo "NOTE: Your Claude launchers are outdated."
    echo "Older launchers always open a NEW Claude window (duplicate Dock icons)."
    echo "Upgrade rebuilds launchers so re-clicking a profile focuses the same window,"
    echo "and quits extra Claude processes (keeps one per profile). Sign-ins are kept."
    if [ -n "${CLAUDE_LAUNCHERS_UPGRADE_ANSWER:-}" ]; then
      ans="$CLAUDE_LAUNCHERS_UPGRADE_ANSWER"
    elif can_prompt; then
      prompt_read "Upgrade launchers now (recommended)? [Y/n] " ans
    else
      ans="y"
    fi
    case "${ans:-y}" in
      n|N|no|NO|No)
        echo "  skipped upgrade"
        ;;
      *)
        upgrade_setup
        echo
        load_generated_launchers
        ;;
    esac
  fi

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
  echo "  8) Upgrade launchers + quit duplicate Claude windows"
  echo "  9) Cancel"

  if [ -n "${CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE:-}" ]; then
    choice="$CLAUDE_LAUNCHERS_MANAGEMENT_CHOICE"
  elif can_prompt; then
    prompt_read "Select [1]: " choice
  else
    echo
    echo "Run a generated launcher from $APPS, or run '$0 upgrade' / '$0 clean'."
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
      export CLAUDE_LAUNCHERS_FROM_MANAGEMENT=1
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
      upgrade_setup
      ;;
    9)
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
  upgrade              Rebuild launchers + quit duplicate Claude windows (keeps sign-ins)
  clean                Remove generated launchers (keeps your profile data)
  clean --purge        Remove generated launchers AND their profile data
  config-dir <label> <path|default>  Set or clear CLAUDE_CONFIG_DIR for a profile
  oauth-router on|off|status  Optional: route claude:// / connector OAuth to the right profile
  doctor               Report install, launchers, Code config dirs, wrappers, router
  version              Print script and launcher-helper versions
  help                 Show this help

Interactive default:
  Keeps your existing Claude login as-is and creates only the missing second
  profile (Work or Personal). If launchers are outdated, offers one-click upgrade.

Create options:
  --desktop            Also copy clickable launchers to your Desktop
  --no-desktop         Do not copy launchers to your Desktop
  --launch             Launch the created profile(s) after setup
  --no-launch          Do not launch profiles after setup
  --dock               Pin created launchers to the Dock (idempotent)
  --no-dock            Do not change the Dock
  --dock-cleanup       With --dock, remove duplicate Claude.app Dock pins first
  --claude-config-dir <path>
                       Pair Desktop with a Claude Code config dir (CLAUDE_CONFIG_DIR)
                       and install a CLI wrapper under ~/.claude-fix/bin
  --yes               Skip the interactive menu (assumes existing Work, creates Personal)

Upgrade options:
  --quit-duplicates    Quit extra Claude processes (default)
  --no-quit-duplicates Rebuild launchers only; leave running windows alone

Examples:
  ./make_claude_launchers.sh
  ./make_claude_launchers.sh create Work Personal Clients
  ./make_claude_launchers.sh create --desktop --launch Personal
  ./make_claude_launchers.sh create --dock --dock-cleanup Work Personal
  ./make_claude_launchers.sh create --claude-config-dir ~/.claude-personal Personal
  ./make_claude_launchers.sh config-dir Personal ~/.claude-personal
  ./make_claude_launchers.sh config-dir Personal default
  ./make_claude_launchers.sh doctor
  ./make_claude_launchers.sh oauth-router on
  ./make_claude_launchers.sh upgrade
  curl -fsSL https://raw.githubusercontent.com/sarhej/claude-fix/main/make_claude_launchers.sh | bash -s upgrade
  ./make_claude_launchers.sh clean --purge

Note:
  Your normal Claude.app keeps its current login. Generated launchers use
  original profile icons (not affiliated with Anthropic) and open isolated
  profiles via --user-data-dir. Re-clicking a profile focuses the existing
  window instead of spawning another Dock icon. On curl install, icons
  download to ~/.claude-fix/icons automatically. Pair Claude Code with
  --claude-config-dir so /desktop handoff finds the right transcript folder.
  Connector / OAuth return links: enable optional oauth-router (off by default).
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

ensure_claude_app() {
  if [ -n "$CLAUDE_APP" ] && [ -d "$CLAUDE_APP" ]; then
    return 0
  fi
  if ! CLAUDE_APP=$(find_claude); then
    cat >&2 <<MSG
ERROR: Claude Desktop is not installed (or could not be found).

  Install it from https://claude.ai/download and re-run this script.
  If it is installed in an unusual location, move it to /Applications.
MSG
    return 1
  fi
  return 0
}

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

write_launch_profile_script() {
  local script_path="$1"
  local claude_app="$2"
  local data_dir="$3"
  local config_dir="${4:-}"
  local open_env=""
  if [ -n "$config_dir" ]; then
    open_env=" --env CLAUDE_CONFIG_DIR=$(shell_quote "$config_dir")"
  fi
  cat >"$script_path" <<EOF
#!/bin/bash
# claude-fix launch helper (v${LAUNCHER_VERSION}): focus existing profile or open one new instance
set -euo pipefail
CLAUDE_APP=$(shell_quote "$claude_app")
DATA_DIR=$(shell_quote "$data_dir")
FLAG="--user-data-dir=\${DATA_DIR}"

# Match only real Claude binaries. Matching FLAG alone is wrong: this awk process
# itself appears in ps as "... -v flag --user-data-dir=..." and would false-positive,
# then exit without opening Claude.
# Do not "exit" early inside awk: with pipefail, that SIGPIPEs ps (exit 141).
pid="\$(
  ps -axo pid=,command= 2>/dev/null | awk -v flag="\$FLAG" '
  !found && index(\$0, "Claude.app/Contents/MacOS/Claude") {
    for (i = 2; i <= NF; i++) {
      if (\$i == flag) { print \$1; found = 1; break }
    }
  }'
)"

if [ -n "\$pid" ] && kill -0 "\$pid" 2>/dev/null; then
  if /usr/bin/osascript -e "tell application \\"System Events\\" to set frontmost of first process whose unix id is \$pid to true" >/dev/null 2>&1; then
    # Claude reclaims claude:// on launch; nudge the optional link router to take it back.
    if [ -f "\$HOME/.claude-fix/oauth-router/enabled" ]; then
      open -g "claude-fix://background" >/dev/null 2>&1 || true
    fi
    exit 0
  fi
  # Focus failed (permissions / stale window) — open a new instance below.
fi

if [ -f "\$HOME/.claude-fix/oauth-router/enabled" ]; then
  open -g "claude-fix://background" >/dev/null 2>&1 || true
fi
exec open -n -a "\$CLAUDE_APP"${open_env} --args --user-data-dir="\$DATA_DIR"
EOF
  chmod +x "$script_path"
}

launcher_is_current() {
  local app="$1"
  local marker="$app/$MARKER_FILE"
  local ver
  [ -f "$marker" ] || return 1
  [ -f "$app/$LAUNCH_SCRIPT_REL" ] || return 1
  ver=$(marker_value "$marker" "launcher-version")
  [ "$ver" = "$LAUNCHER_VERSION" ]
}

any_launcher_outdated() {
  local app
  load_generated_launchers
  local i
  for ((i = 0; i < ${#GENERATED_APPS[@]}; i++)); do
    app="${GENERATED_APPS[$i]}"
    if ! launcher_is_current "$app"; then
      return 0
    fi
  done
  return 1
}

# Keep one Claude process per --user-data-dir (and one default); quit extras.
quit_duplicate_claude_processes() {
  local killed=0
  local report
  if [ "${CLAUDE_LAUNCHERS_TEST_MODE:-}" = "1" ] && [ "${CLAUDE_LAUNCHERS_ALLOW_QUIT_DUPES:-}" != "1" ]; then
    return 0
  fi
  report=$(python3 - <<'PY'
import collections, os, signal, subprocess, sys

out = subprocess.check_output(["ps", "-axo", "pid=,command="], text=True, errors="replace")
by_key = collections.OrderedDict()
for line in out.splitlines():
    line = line.strip()
    if not line:
        continue
    parts = line.split(None, 1)
    if len(parts) < 2:
        continue
    try:
        pid = int(parts[0])
    except ValueError:
        continue
    cmd = parts[1]
    if "Claude.app/Contents/MacOS/Claude" not in cmd:
        continue
    key = "__default__"
    for token in cmd.split():
        if token.startswith("--user-data-dir="):
            key = token.split("=", 1)[1]
            break
    by_key.setdefault(key, []).append(pid)

killed = []
for key, pids in by_key.items():
    pids = sorted(pids)  # keep oldest
    for pid in pids[1:]:
        try:
            os.kill(pid, signal.SIGTERM)
            killed.append((key, pid))
        except ProcessLookupError:
            pass
        except PermissionError as e:
            print(f"  could not quit pid {pid}: {e}", file=sys.stderr)

for key, pid in killed:
    label = "default Claude" if key == "__default__" else key
    print(f"  quit duplicate pid {pid} ({label})")
print(str(len(killed)))
PY
)
  killed=$(printf '%s\n' "$report" | tail -n1)
  if [ "${killed:-0}" -gt 0 ]; then
    echo "Quit $killed duplicate Claude process(es). One window kept per profile."
  else
    echo "No duplicate Claude processes found."
  fi
}

upgrade_setup() {
  local quit_dupes=1
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --no-quit-duplicates)
        quit_dupes=0
        ;;
      --quit-duplicates)
        quit_dupes=1
        ;;
      --*)
        echo "ERROR: unknown upgrade option: $1" >&2
        echo "Run '$0 help' for usage." >&2
        exit 1
        ;;
      *)
        echo "ERROR: unexpected argument: $1" >&2
        exit 1
        ;;
    esac
    shift
  done

  require_tools osacompile osascript
  load_generated_launchers
  if [ "${#GENERATED_LABELS[@]}" -eq 0 ]; then
    echo "No generated Claude launchers found in $APPS."
    echo "Run '$0' first to create Work/Personal (or custom) profiles."
    return 1
  fi

  if ! ensure_claude_app; then
    return 1
  fi
  ensure_icons_available || true

  echo "Upgrading ${#GENERATED_LABELS[@]} launcher(s) to v${LAUNCHER_VERSION} (focus if already open)..."
  local i label
  for ((i = 0; i < ${#GENERATED_LABELS[@]}; i++)); do
    label="${GENERATED_LABELS[$i]}"
    make_launcher "$label" 0
  done

  if [ "$quit_dupes" = "1" ]; then
    echo
    echo "Cleaning duplicate running Claude windows..."
    quit_duplicate_claude_processes
  fi

  echo
  echo "Done. Launchers updated — clicking a profile opens it once; re-click focuses the same window."
  echo "If Dock icons still look stacked, wait a second or run: killall Dock"
  oauth_router_nudge
}

make_launcher() {
  local label="$1"
  local desktop_aliases="${2:-0}"
  local name="Claude $label"
  local dir; dir=$(slug "$label")
  local app="$APPS/$name.app"
  local data="$HOME/$dir"
  local launch_script
  local config_dir=""
  local existing_config=""

  if [ -z "$CLAUDE_APP" ] || [ ! -d "$CLAUDE_APP" ]; then
    ensure_claude_app || return 1
  fi

  if [ -f "$app/$MARKER_FILE" ]; then
    existing_config=$(marker_value "$app/$MARKER_FILE" "claude-config-dir")
  fi
  if [ "$CREATE_CLAUDE_CONFIG_DIR_SET" = "1" ]; then
    config_dir="$CREATE_CLAUDE_CONFIG_DIR"
  elif [ -n "$existing_config" ]; then
    config_dir="$existing_config"
  fi
  if [ -n "$config_dir" ]; then
    config_dir=$(expand_user_path "$config_dir")
  fi

  if [ -d "$data" ]; then
    echo "  -> profile '$label' already has data at ~/$dir (keeping it)"
  else
    echo "  -> creating new profile '$label' at ~/$dir"
  fi
  if [ -n "$config_dir" ]; then
    echo "  -> Claude Code config dir: $config_dir"
    mkdir -p "$config_dir"
  fi

  rm -rf "$app"   # only ever removes the launcher app, never the data dir
  if ! osacompile -o "$app" \
    -e 'do shell script "/bin/bash " & quoted form of ((POSIX path of (path to me)) & "Contents/Resources/launch-profile.sh")' \
    >/dev/null 2>&1; then
    echo "ERROR: failed to build launcher app: $app" >&2
    return 1
  fi
  rm -f "$app/Contents/Resources/Assets.car"
  launch_script="$app/$LAUNCH_SCRIPT_REL"
  write_launch_profile_script "$launch_script" "$CLAUDE_APP" "$data" "$config_dir"
  generate_profile_icon "$label" "$app/Contents/Resources/applet.icns" || true
  if [ -n "$config_dir" ]; then
    printf 'generated-by=claude-fix\nlabel=%s\ndata-dir=%s\nlauncher-version=%s\nclaude-config-dir=%s\n' \
      "$label" "$dir" "$LAUNCHER_VERSION" "$config_dir" >"$app/$MARKER_FILE"
  else
    printf 'generated-by=claude-fix\nlabel=%s\ndata-dir=%s\nlauncher-version=%s\n' \
      "$label" "$dir" "$LAUNCHER_VERSION" >"$app/$MARKER_FILE"
  fi
  # Ad-hoc sign so Gatekeeper accepts the edited bundle (launch-profile.sh + icon).
  # Skip in tests — codesign can block on the system keychain helper.
  if [ "${CLAUDE_LAUNCHERS_TEST_MODE:-}" != "1" ]; then
    codesign --force --deep -s - "$app" >/dev/null 2>&1 || true
  fi
  touch "$app"
  echo "     built launcher: $app"
  if [ -n "$config_dir" ]; then
    write_cli_wrapper "$label" "$config_dir"
  elif [ -n "$existing_config" ]; then
    remove_cli_wrapper "$label"
  fi
  if [ "$desktop_aliases" = "1" ]; then
    make_desktop_shortcut "$app" "$name"
  fi
  oauth_router_nudge
}

refresh_dock_after_start_fresh() {
  local idx="$1"
  local label="${GENERATED_LABELS[$idx]}"
  local app="$APPS/Claude $label.app"
  local plist removed=0

  if dock_changes_disabled; then
    return 0
  fi

  plist=$(dock_plist_path)
  if [ ! -f "$plist" ]; then
    printf '%s\n' "NOTE: Dock preferences not found at $plist; skipping Dock pinning." >&2
    return 0
  fi

  if [ ! -d "$app" ]; then
    printf '%s\n' "NOTE: Launcher not found at $app; skipping Dock pinning." >&2
    return 0
  fi

  removed=$(dock_remove_app_pins "$app" "$plist")
  echo
  echo "Updating Dock..."
  if [ "$removed" -gt 0 ]; then
    echo "  Dock: removed $removed stale pin(s) for $(basename "$app")"
  fi
  pin_launchers_to_dock 0 "$app"
}

maybe_open_after_start_fresh() {
  local idx="$1"
  local label="${GENERATED_LABELS[$idx]}"
  local open_now=-1
  local ans

  if [ -n "${CLAUDE_LAUNCHERS_LAUNCH_ANSWER:-}" ]; then
    case "$CLAUDE_LAUNCHERS_LAUNCH_ANSWER" in
      n|N|no|NO|No)
        open_now=0
        ;;
      *)
        open_now=1
        ;;
    esac
  elif can_prompt; then
    prompt_read "Open Claude $label now to sign in again? [Y/n] " ans
    case "$ans" in
      n|N|no|NO|No)
        open_now=0
        ;;
      *)
        open_now=1
        ;;
    esac
  else
    open_now=0
  fi

  if [ "$open_now" = "1" ]; then
    open_generated_launcher_by_index "$idx"
  else
    echo "Next: open Claude $label and sign in with the right account."
  fi
}

refresh_generated_launcher_icons() {
  local i label
  load_generated_launchers
  [ "${#GENERATED_LABELS[@]}" -gt 0 ] || return 0
  if ! icons_dir >/dev/null 2>&1; then
    return 0
  fi
  if ! ensure_claude_app >/dev/null 2>&1; then
    return 0
  fi
  require_tools osacompile osascript
  echo "Refreshing launcher icons for ${#GENERATED_LABELS[@]} profile(s)..."
  for ((i = 0; i < ${#GENERATED_LABELS[@]}; i++)); do
    label="${GENERATED_LABELS[$i]}"
    if make_launcher "$label" 0; then
      echo "  -> Claude $label"
    else
      echo "  -> Claude $label (skipped)" >&2
    fi
  done
}

create_setup() {
  require_tools osacompile osascript
  mkdir -p "$APPS"

  local had_icons=0
  if icons_dir >/dev/null 2>&1; then
    had_icons=1
  fi
  if ensure_icons_available; then
    if [ "$had_icons" = "0" ]; then
      load_generated_launchers
      if [ "${#GENERATED_LABELS[@]}" -gt 0 ]; then
        refresh_generated_launcher_icons
      fi
    fi
  fi

  local DESKTOP_ALIASES=0
  local LAUNCH_AFTER_CREATE=0
  local PIN_TO_DOCK=-1
  local DOCK_CLEANUP=0
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
      --dock)
        PIN_TO_DOCK=1
        ;;
      --no-dock)
        PIN_TO_DOCK=0
        ;;
      --dock-cleanup)
        DOCK_CLEANUP=1
        ;;
      --claude-config-dir)
        shift
        if [ "$#" -eq 0 ]; then
          echo "ERROR: --claude-config-dir requires a path" >&2
          exit 1
        fi
        case "$1" in
          --*)
            echo "ERROR: --claude-config-dir requires a path" >&2
            exit 1
            ;;
        esac
        CREATE_CLAUDE_CONFIG_DIR_SET=1
        CREATE_CLAUDE_CONFIG_DIR=$(expand_user_path "$1")
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

        if [ "$PIN_TO_DOCK" -lt 0 ]; then
          prompt_pin_to_dock_setting "Pin launchers to Dock? [Y/n] "
        fi
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

  if [ "$PIN_TO_DOCK" -lt 0 ]; then
    if [ "${CLAUDE_LAUNCHERS_FROM_MANAGEMENT:-}" = "1" ]; then
      prompt_pin_to_dock_setting "Pin new launcher(s) to Dock? [Y/n] "
    elif [ "$SKIP_INTERACTIVE" = "0" ]; then
      prompt_pin_to_dock_setting "Pin launchers to Dock? [Y/n] "
    fi
  fi

  if ! ensure_claude_app; then
    exit 1
  fi
  echo "Found Claude at: $CLAUDE_APP"

  if ! icons_dir >/dev/null 2>&1; then
    echo "NOTE: profile icons unavailable - launchers will use the default applet icon."
    echo "       Icons are downloaded automatically on curl install; retry when online or clone the repo."
  fi

  if [ -n "$EXISTING_PROFILE_LABEL" ] && [ "${#LABELS[@]}" -eq 1 ]; then
    maybe_reset_onboarding_profile_data "${LABELS[0]}" "$(slug "${LABELS[0]}")"
  fi

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
    if [ "$PIN_TO_DOCK" != "1" ]; then
      echo
      if [ "${#LABELS[@]}" -eq 1 ]; then
        echo "Tip: re-run with --dock to pin Claude ${LABELS[0]} to your Dock,"
        echo "or drag the launcher there yourself."
      else
        echo "Tip: re-run with --dock to pin launchers to your Dock,"
        echo "or drag them there yourself."
      fi
    fi
  }

  echo "Creating ${#LABELS[@]} launcher(s)..."
  local CREATED_APPS=()
  for label in "${LABELS[@]}"; do
    if ! make_launcher "$label" "$DESKTOP_ALIASES"; then
      exit 1
    fi
    CREATED_APPS+=("$APPS/Claude $label.app")
  done

  if [ "$PIN_TO_DOCK" = "1" ]; then
    echo
    echo "Updating Dock..."
    pin_launchers_to_dock "$DOCK_CLEANUP" "${CREATED_APPS[@]}"
  fi

  if [ "$LAUNCH_AFTER_CREATE" = "1" ]; then
    launch_created_profiles
  fi

  print_completion_message
  if [ "$LAUNCH_AFTER_CREATE" != "1" ] && [ "${CLAUDE_LAUNCHERS_NO_OPEN:-}" != "1" ]; then
    open "$APPS"
  fi
}

# --- Optional OAuth / deep-link router (Claude Fix Links) --------------------

running_profile_pid() {
  local data_dir="$1"
  local flag="--user-data-dir=${data_dir}"
  ps -axo pid=,command= 2>/dev/null | awk -v flag="$flag" '
  !found && index($0, "Claude.app/Contents/MacOS/Claude") {
    for (i = 2; i <= NF; i++) {
      if ($i == flag) { print $1; found = 1; break }
    }
  }'
}

write_router_resources() {
  local resources="$1"
  mkdir -p "$resources"

  cat >"$resources/focus.js" <<'JS'
ObjC.import('AppKit');

function code(s) {
  return ((s.charCodeAt(0) << 24) | (s.charCodeAt(1) << 16) | (s.charCodeAt(2) << 8) | s.charCodeAt(3)) >>> 0;
}

function run(argv) {
  var pid = parseInt(argv[0], 10);
  var url = argv.length > 1 ? argv[1] : '';
  var target = $.NSAppleEventDescriptor.descriptorWithProcessIdentifier(pid);
  var event = url
    ? $.NSAppleEventDescriptor.appleEventWithEventClassEventIDTargetDescriptorReturnIDTransactionID(code('GURL'), code('GURL'), target, -1, 0)
    : $.NSAppleEventDescriptor.appleEventWithEventClassEventIDTargetDescriptorReturnIDTransactionID(code('aevt'), code('rapp'), target, -1, 0);
  if (url) {
    event.setParamDescriptorForKeyword($.NSAppleEventDescriptor.descriptorWithString(url), code('----'));
  }
  var error = Ref();
  var reply = event.sendEventWithOptionsTimeoutError(3, 10, error);
  var app = $.NSRunningApplication.runningApplicationWithProcessIdentifier(pid);
  if (!app.isNil()) {
    app.activateWithOptions(3);
  }
  if (!reply || reply.isNil() || (error[0] && !error[0].isNil())) {
    throw new Error('Apple event was not delivered');
  }
}
JS

  cat >"$resources/claim.js" <<'JS'
ObjC.import('CoreServices');

function run(argv) {
  for (var i = 1; i < argv.length; i++) {
    $.LSSetDefaultHandlerForURLScheme($(argv[i]), $(argv[0]));
  }
}
JS

  cat >"$resources/link-router.sh" <<'ROUTER'
#!/bin/bash
# Runtime helper inside Claude Fix Links.app
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$HERE/../.." && pwd)"
MARKER="$APP_ROOT/Contents/Resources/claude-fix-generated"
APPS="${HOME}/Applications"
STATE_DIR="${HOME}/.claude-fix/oauth-router"
CLAUDE_BUNDLE_ID="com.anthropic.claudefordesktop"
SCHEMES=(claude msauth.com.anthropic.claudefordesktop claude-fix)

marker_value() {
  local marker="$1" key="$2"
  awk -F= -v key="$key" '$1 == key {print substr($0, length(key) + 2); exit}' "$marker" 2>/dev/null || true
}

claude_app() {
  local p
  p=$(marker_value "$MARKER" "claude-app")
  if [ -n "$p" ] && [ -d "$p" ]; then
    printf '%s' "$p"
    return 0
  fi
  for p in "/Applications/Claude.app" "$HOME/Applications/Claude.app"; do
    [ -d "$p" ] && { printf '%s' "$p"; return 0; }
  done
  return 1
}

list_profiles() {
  local app marker kind
  shopt -s nullglob
  for app in "$APPS/Claude "*.app; do
    marker="$app/Contents/Resources/claude-fix-generated"
    [ -f "$marker" ] || continue
    kind=$(marker_value "$marker" "kind")
    [ "$kind" = "router" ] && continue
    basename "$app" .app
  done
  shopt -u nullglob
}

running_profile_pid() {
  local data_dir="$1"
  local flag="--user-data-dir=${data_dir}"
  ps -axo pid=,command= 2>/dev/null | awk -v flag="$flag" '
  !found && index($0, "Claude.app/Contents/MacOS/Claude") {
    for (i = 2; i <= NF; i++) {
      if ($i == flag) { print $1; found = 1; break }
    }
  }'
}

cmd_claim() {
  local id="${1:-}"
  if [ -z "$id" ]; then
    id=$(marker_value "$MARKER" "bundle-id")
    id="${id:-com.sarhej.claude-fix.links}"
  fi
  /usr/bin/osascript -l JavaScript "$HERE/claim.js" "$id" "${SCHEMES[@]}" >/dev/null 2>&1
}

cmd_open() {
  local name="$1" url="${2:-}" app data_dir pid label marker
  app=$(claude_app) || {
    echo "Claude.app not found." >&2
    return 1
  }
  marker="$APPS/${name}.app/Contents/Resources/claude-fix-generated"
  if [ ! -f "$marker" ]; then
    echo "No Claude Fix launcher named ${name}." >&2
    return 1
  fi
  data_dir=$(marker_value "$marker" "data-dir")
  label=$(marker_value "$marker" "label")
  [ -n "$data_dir" ] || data_dir="Claude${label}"
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$name" >"$STATE_DIR/last-profile"

  pid=$(running_profile_pid "$HOME/$data_dir" || true)
  if [ -n "$pid" ]; then
    if ! /usr/bin/osascript -l JavaScript "$HERE/focus.js" "$pid" "$url" >/dev/null 2>&1; then
      if [ -n "$url" ]; then
        echo "Allow Claude Fix Links to control Claude in System Settings > Privacy & Security > Automation, then try again." >&2
        return 1
      fi
    fi
  else
    local args=() cfg
    cfg=$(marker_value "$marker" "claude-config-dir")
    [ -n "$cfg" ] && args+=(--env "CLAUDE_CONFIG_DIR=$cfg")
    args+=(-n -a "$app")
    [ -n "$url" ] && args+=("$url")
    args+=(--args "--user-data-dir=$HOME/$data_dir")
    open "${args[@]}" || return 1
  fi
  cmd_claim || true
}

case "${1:-}" in
  list) list_profiles ;;
  last) cat "$STATE_DIR/last-profile" 2>/dev/null || true ;;
  open) shift; cmd_open "$@" ;;
  claim) shift; cmd_claim "$@" ;;
  *)
    echo "usage: link-router.sh list|last|open NAME [URL]|claim [BUNDLE_ID]" >&2
    exit 2
    ;;
esac
ROUTER
  chmod +x "$resources/link-router.sh"
}

router_applet_source() {
  cat <<'APPLESCRIPT'
property claimUntil : missing value

on run
	my pick("")
	my keepClaiming()
end run

on open location theURL
	if theURL starts with "claude-fix:" then
		my keepClaiming()
		try
			do shell script my helper() & " claim"
		end try
	else
		my pick(theURL)
		my keepClaiming()
	end if
end open location

on keepClaiming()
	set claimUntil to (current date) + 60
end keepClaiming

on idle
	if claimUntil is not missing value and (current date) < claimUntil then
		try
			do shell script my helper() & " claim"
		end try
		return 3
	end if
	quit
	return 3
end idle

on helper()
	return "/bin/bash " & quoted form of ((POSIX path of (path to me)) & "Contents/Resources/link-router.sh")
end helper

on pick(theURL)
	set profileText to do shell script my helper() & " list"
	if profileText is "" then
		activate
		display alert "No Claude Fix profiles" message "Create a profile with claude-fix first, then try the sign-in link again." as warning
		return
	end if
	set profileNames to paragraphs of profileText
	set lastName to ""
	try
		set lastName to do shell script my helper() & " last"
	end try
	set preselect to item 1 of profileNames
	if profileNames contains lastName then set preselect to lastName
	set chosen to preselect
	if (count of profileNames) > 1 then
		if theURL is "" then
			set question to "Open which Claude Fix profile?"
		else
			set question to "Continue sign-in / connector in which profile?"
		end if
		activate
		set choice to choose from list profileNames with title "Claude Fix" with prompt question default items {preselect} OK button name "Open"
		if choice is false then return
		set chosen to item 1 of choice
	end if
	try
		do shell script my helper() & " open " & quoted form of chosen & " " & quoted form of theURL
	on error errText
		display alert "Couldn't open " & chosen message errText as warning
	end try
end pick
APPLESCRIPT
}

install_oauth_router() {
  local plist src tmp
  require_tools osacompile osascript plutil
  if ! ensure_claude_app; then
    return 1
  fi
  mkdir -p "$(oauth_router_state_dir)" "$APPS"
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/claude-fix-router.XXXXXX")
  src="$tmp/router.applescript"
  router_applet_source >"$src"
  rm -rf "$ROUTER_APP"
  if ! osacompile -s -o "$ROUTER_APP" "$src" >/dev/null 2>&1; then
    rm -rf "$tmp"
    echo "ERROR: failed to build $ROUTER_NAME" >&2
    return 1
  fi
  rm -rf "$tmp"
  rm -f "$ROUTER_APP/Contents/Resources/Assets.car"
  write_router_resources "$ROUTER_APP/Contents/Resources"
  printf 'generated-by=claude-fix\nkind=router\nbundle-id=%s\nclaude-app=%s\nlauncher-version=%s\n' \
    "$ROUTER_BUNDLE_ID" "$CLAUDE_APP" "$LAUNCHER_VERSION" >"$ROUTER_APP/$MARKER_FILE"

  plist="$ROUTER_APP/Contents/Info.plist"
  plutil -replace CFBundleIdentifier -string "$ROUTER_BUNDLE_ID" "$plist" >/dev/null
  plutil -replace CFBundleName -string "$ROUTER_NAME" "$plist" >/dev/null
  plutil -replace CFBundleDisplayName -string "$ROUTER_NAME" "$plist" >/dev/null 2>&1 || true
  plutil -replace LSUIElement -bool YES "$plist" >/dev/null
  plutil -replace NSAppleEventsUsageDescription -string \
    "Claude Fix Links sends sign-in and connector return URLs to the Claude profile you choose." \
    "$plist" >/dev/null
  plutil -replace CFBundleURLTypes -xml \
    '<array><dict><key>CFBundleURLName</key><string>Claude Fix links</string><key>CFBundleURLSchemes</key><array><string>claude</string><string>msauth.com.anthropic.claudefordesktop</string><string>claude-fix</string></array></dict></array>' \
    "$plist" >/dev/null

  if [ "${CLAUDE_LAUNCHERS_TEST_MODE:-}" != "1" ]; then
    codesign --force --deep -s - "$ROUTER_APP" >/dev/null 2>&1 || true
    /bin/bash "$ROUTER_APP/$ROUTER_HELPER_REL" claim >/dev/null 2>&1 || true
  fi
  touch "$(oauth_router_state_dir)/enabled"
  echo "Installed $ROUTER_NAME at $ROUTER_APP"
  echo "  claude:// and connector return links will ask which profile to use."
  echo "  Turn off with: $0 oauth-router off"
}

remove_oauth_router() {
  local state
  state=$(oauth_router_state_dir)
  if [ -d "$ROUTER_APP" ] && [ -f "$ROUTER_APP/$MARKER_FILE" ]; then
    if [ "$(marker_value "$ROUTER_APP/$MARKER_FILE" "kind")" = "router" ]; then
      if [ "${CLAUDE_LAUNCHERS_TEST_MODE:-}" != "1" ] && [ -f "$ROUTER_APP/$ROUTER_HELPER_REL" ]; then
        /bin/bash "$ROUTER_APP/$ROUTER_HELPER_REL" claim "$CLAUDE_BUNDLE_ID" >/dev/null 2>&1 || true
      fi
      echo "Removing $ROUTER_NAME (links go back to Claude.app when possible)"
      rm -rf "$ROUTER_APP"
    fi
  fi
  rm -f "$state/enabled"
}

oauth_router_nudge() {
  oauth_router_enabled || return 0
  [ "${CLAUDE_LAUNCHERS_TEST_MODE:-}" = "1" ] && return 0
  open -g "claude-fix://background" >/dev/null 2>&1 || true
}

default_handler_for_scheme() {
  local scheme="$1"
  case "$scheme" in
    claude|claude-fix|msauth.com.anthropic.claudefordesktop) ;;
    *) return 0 ;;
  esac
  /usr/bin/osascript -l JavaScript 2>/dev/null <<JS || true
ObjC.import('CoreServices');
var h = $.LSCopyDefaultHandlerForURLScheme('$scheme');
if (h && !h.isNil()) {
  console.log(ObjC.unwrap(h));
}
JS
}

oauth_router_status() {
  local handler
  echo "oauth-router:"
  if oauth_router_enabled; then
    echo "  state:   on"
    echo "  app:     $ROUTER_APP"
  elif [ -f "$(oauth_router_state_dir)/enabled" ]; then
    echo "  state:   enabled flag present but $ROUTER_NAME missing (run: oauth-router on)"
  else
    echo "  state:   off"
  fi
  handler=$(default_handler_for_scheme "claude" || true)
  if [ -n "$handler" ]; then
    echo "  claude:// handler: $handler"
  else
    echo "  claude:// handler: (unknown)"
  fi
  if [ -f "$(oauth_router_state_dir)/last-profile" ]; then
    echo "  last profile: $(cat "$(oauth_router_state_dir)/last-profile")"
  fi
}

oauth_router_setup() {
  local action="${1:-status}"
  case "$action" in
    on|enable)
      install_oauth_router
      ;;
    off|disable)
      remove_oauth_router
      echo "oauth-router off."
      ;;
    status|"")
      oauth_router_status
      ;;
    *)
      echo "ERROR: usage: $0 oauth-router on|off|status" >&2
      exit 1
      ;;
  esac
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

  # Turning off the router restores URL schemes before profile launchers go away.
  if oauth_router_enabled || [ -f "$(oauth_router_state_dir)/enabled" ]; then
    remove_oauth_router
  fi

  shopt -s nullglob
  local found=0 app base label data data_dir ans kind
  for app in "$APPS/Claude "*.app; do
    [ -e "$app" ] || continue
    # Only touch launchers this script generated, never the real Claude.app or
    # unrelated AppleScript applets that happen to share the "Claude *.app" name.
    if [ ! -f "$app/$MARKER_FILE" ]; then
      echo "  skip (not a generated launcher): $(basename "$app")"
      continue
    fi
    kind=$(marker_value "$app/$MARKER_FILE" "kind")
    [ "$kind" = "router" ] && continue
    found=1
    base=$(basename "$app" .app)
    label=$(marker_value "$app/$MARKER_FILE" "label")
    [ -n "$label" ] || label=${base#Claude }
    data_dir=$(marker_value "$app/$MARKER_FILE" "data-dir")
    [ -n "$data_dir" ] || data_dir=$(slug "$label")
    data="$HOME/$data_dir"

    echo "Removing launcher: $base.app"
    rm -rf "$app"

    if [ "$purge" = "1" ]; then
      if [ -d "$data" ]; then
        if [ -n "${CLAUDE_LAUNCHERS_PURGE_ANSWER:-}" ]; then
          ans="$CLAUDE_LAUNCHERS_PURGE_ANSWER"
        elif [ "${CLAUDE_LAUNCHERS_TEST_MODE:-}" = "1" ]; then
          printf "  Delete profile data at %s ? [y/N] " "$data"
          ans=""
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

config_dir_setup() {
  local label path
  if [ "$#" -ne 2 ]; then
    echo "ERROR: usage: $0 config-dir <label> <path|default>" >&2
    exit 1
  fi
  label=$(trim_label "$1")
  path="$2"
  if ! validate_label "$label"; then
    echo "ERROR: invalid profile label: $1" >&2
    exit 1
  fi
  require_tools osacompile osascript
  if ! ensure_claude_app; then
    return 1
  fi
  ensure_icons_available || true

  if [ ! -d "$APPS/Claude $label.app" ] || [ ! -f "$APPS/Claude $label.app/$MARKER_FILE" ]; then
    echo "ERROR: no generated launcher for profile '$label' in $APPS" >&2
    echo "       Create it first: $0 create --claude-config-dir <path> $label" >&2
    exit 1
  fi

  CREATE_CLAUDE_CONFIG_DIR_SET=1
  case "$path" in
    default|DEFAULT|none|NONE|-|"")
      CREATE_CLAUDE_CONFIG_DIR=""
      echo "Clearing Claude Code config dir for Claude $label (back to ~/.claude default)..."
      ;;
    *)
      CREATE_CLAUDE_CONFIG_DIR=$(expand_user_path "$path")
      echo "Setting Claude Code config dir for Claude $label..."
      ;;
  esac
  make_launcher "$label" 0
  echo "Done. Quit that profile (⌘Q) and reopen it from the launcher so the new env applies."
}

version_setup() {
  cat <<MSG
claude-fix $SCRIPT_VERSION
launcher-helper-version=$LAUNCHER_VERSION
MSG
}

doctor_setup() {
  local i app marker ver cfg wrap wrap_path status_line
  local outdated=0
  local wrappers_dir
  wrappers_dir=$(wrappers_bin_dir)

  echo "claude-fix doctor"
  echo "  script version:          $SCRIPT_VERSION"
  echo "  launcher helper version: $LAUNCHER_VERSION"
  if CLAUDE_APP=$(find_claude); then
    echo "  Claude.app:              $CLAUDE_APP"
  else
    echo "  Claude.app:              NOT FOUND"
  fi
  echo "  launchers folder:        $APPS"
  echo "  CLI wrappers folder:     $wrappers_dir"
  echo
  oauth_router_status

  load_generated_launchers
  if [ "${#GENERATED_LABELS[@]}" -eq 0 ]; then
    echo
    echo "No generated launchers found. Run: $0"
    return 0
  fi

  echo
  echo "Profiles:"
  for ((i = 0; i < ${#GENERATED_LABELS[@]}; i++)); do
    app="${GENERATED_APPS[$i]}"
    marker="$app/$MARKER_FILE"
    ver=$(marker_value "$marker" "launcher-version")
    cfg=$(marker_value "$marker" "claude-config-dir")
    wrap=$(cli_wrapper_name "${GENERATED_LABELS[$i]}")
    wrap_path="$wrappers_dir/$wrap"
    status_line="ok"
    if [ "$ver" != "$LAUNCHER_VERSION" ]; then
      status_line="OUTDATED (v${ver:-?}; run upgrade)"
      outdated=1
    fi
    echo "  - Claude ${GENERATED_LABELS[$i]}"
    echo "      launcher:     $app"
    echo "      data dir:     $HOME/${GENERATED_DIRS[$i]}"
    echo "      helper:       v${ver:-?} ($status_line)"
    if [ -n "$cfg" ]; then
      echo "      Code config:  $cfg"
    else
      echo "      Code config:  (default ~/.claude — /desktop handoff shared across profiles)"
    fi
    if [ -x "$wrap_path" ]; then
      echo "      CLI wrapper:  $wrap_path"
    elif [ -n "$cfg" ]; then
      echo "      CLI wrapper:  missing (re-run config-dir or create --claude-config-dir)"
    else
      echo "      CLI wrapper:  (none)"
    fi
  done

  echo
  if [ "$outdated" = "1" ]; then
    echo "Action: run \`$0 upgrade\` to rebuild outdated launchers."
  else
    echo "All launchers are on helper v$LAUNCHER_VERSION."
  fi
  case ":$PATH:" in
    *":$wrappers_dir:"*)
      echo "PATH includes $wrappers_dir."
      ;;
    *)
      echo "Tip: add wrappers to PATH:  export PATH=\"$wrappers_dir:\$PATH\""
      ;;
  esac
  if ! oauth_router_enabled; then
    echo "Tip: connector OAuth landing on the wrong profile? Try: $0 oauth-router on"
  fi
}

# Run when executed directly, or when piped to bash (curl | bash). Skip when sourced.
if [[ "${BASH_SOURCE[0]:-}" == "$0" || -z "${BASH_SOURCE[0]:-}" ]]; then
  require_macos

  cmd="${1:-create}"
  case "$cmd" in
    clean)
      shift
      clean_setup "$@"
      ;;
    upgrade)
      shift
      upgrade_setup "$@"
      ;;
    create)
      [ "$#" -gt 0 ] && shift
      create_setup "$@"
      ;;
    config-dir)
      shift
      config_dir_setup "$@"
      ;;
    oauth-router)
      shift
      oauth_router_setup "$@"
      ;;
    doctor)
      doctor_setup
      ;;
    version|--version)
      version_setup
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
