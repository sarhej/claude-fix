# Contributing to claude-fix

Thanks for wanting to help. Keep changes small and reviewable.

## Hard constraints (do not open PRs that break these)

- **Original icons only.** Ship or generate artwork from this repo’s `icons/`
  palette (symbols, letters, custom user images). Do **not** recolor Claude’s
  app icon, copy Anthropic assets into the project, or offer an “exact Claude
  icon” mode. Dock / Cmd-Tab must not look like Anthropic branding.
- **Never modify, patch, or re-sign** `/Applications/Claude.app`. Launchers
  point at it with `--user-data-dir` only. No per-profile clones of Claude.app
  for visual identity.
- **Naming.** Product stays **claude-fix** / Claude Fix. The optional link
  helper is **Claude Fix Links** only — do not introduce a “Claude Profiles”
  (or similar) branded picker app.
- **No affiliation claims.** Keep the third-party / not endorsed by Anthropic
  wording accurate.

## Preferred contributions

Bug fixes, docs, tests, safer launcher lifecycle (focus/reopen, resign after
bundle edits, migrations), and CI. Prefer focused PRs over large rewrites.

## Checks before you push

```bash
shellcheck make_claude_launchers.sh tests/run_tests.sh tests/lib/harness.sh
bash tests/run_tests.sh
```

## Questions

Open an issue describing the problem and the approach before a large PR.
