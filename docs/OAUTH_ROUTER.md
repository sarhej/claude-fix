# Optional OAuth / deep-link router (design)

**Status:** implementing  
**Branch:** `feat/oauth-router`  
**Problem:** With several Claude Desktop instances (same `Claude.app` + different `--user-data-dir`), OAuth/connector return URLs (`claude://`, etc.) go to whichever process last claimed the URL scheme — often the wrong profile.

## Goal

Optional helper that:

1. Becomes the default handler for Claude-related URL schemes.
2. Asks which profile should receive the link (last-used preselected).
3. Forwards the URL to that profile’s running process, or starts its launcher with the link.
4. Reclaims the schemes after Claude steals them back on launch.

## Non-goals

- Recolor Claude icons / clone Claude.app for Dock identity  
- Name anything “Claude Profiles”  
- On by default  
- Fix Anthropic in-app Desktop↔Code UI  

## Naming

| Piece | Name |
|-------|------|
| Product | claude-fix / Claude Fix |
| Helper app | `Claude Fix Links.app` in `~/Applications` |
| CLI | `claude-fix oauth-router on\|off\|status` |
| Bundle ID | `com.sarhej.claude-fix.links` |

## Schemes (v1)

- `claude://` (primary)  
- `msauth.com.anthropic.claudefordesktop` (Microsoft connector / desktop auth, if used)

## Behavior

- **Off (default):** no helper; Claude.app owns schemes as today.  
- **On:** install helper, register schemes, write state under `~/.claude-fix/oauth-router`.  
- **URL open:** chooser lists generated launchers only; cancel drops the URL.  
- **Forward:** if profile PID found → Apple Event (GURL) + activate; else `open` the launcher then retry / open with URL when possible.  
- **Reclaim:** on `oauth-router on`, each `create`/`upgrade`, and when a generated launcher starts (lightweight claim in launch-profile.sh or helper wake).  
- **clean / oauth-router off:** remove helper, restore default handler to Claude.app when possible.  
- **doctor:** report on/off, who owns `claude://`, helper path.

## Safety

- Never modify `/Applications/Claude.app`  
- Only route to launchers marked `generated-by=claude-fix`  
- Original icons only for the helper (simple generic / Claude Fix branding)
