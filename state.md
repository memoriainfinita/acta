---
created: 2026-05-15
last_updated: 2026-06-26
---

# acta — project state

## Status

Production-ready. In daily use.

## Files

| File | Location |
|------|----------|
| Source | `CODING GIT/ACTA/acta.ps1` |
| Active copy | `$HOME\scripts\acta.ps1` |
| Data | `$HOME\.config\acta\acta.json` |
| Log | `$HOME\.config\acta\acta-log.json` |
| Chains | `$HOME\.config\acta\acta-chains.json` |

Loaded via PowerShell profile (`$PROFILE`): `. "$HOME\scripts\acta.ps1"`

## Commands

`add` `edit` `list` `search` `run` `delete` `log` `chain` `export` `import` `push` `pull`

## History

### 2026-06-26 — Published to GitHub

- Public repo: https://github.com/memoriainfinita/acta (GPLv3)
- Added `.gitignore` (excludes `_BACKUPS/`, `acta-export-*.json`) and `LICENSE` (GPLv3 verbatim)
- README updated to v3: flag-based `edit`/`delete`, `chain edit`; generalized the Forgejo remote example
- Repo topics: powershell, cli, snippet-manager, command-line, productivity, windows
- Commit email set to elmmott@gmail.com (repo-local config)

### 2026-06-13 — v3: non-interactive edit/delete, chain edit

- `acta edit <id> --title X --desc X --cmd X --tags a b c` — flag-based partial edit; no flags = interactive mode (unchanged)
- `acta delete <id[,id,...]>` — direct delete, prints full deleted snippet for recovery via `acta add`; no id = interactive mode (unchanged)
- `acta chain edit <name> --name X --desc X --ids 1,4,7` — partial edit, validates name collision
- New helper `_acta_parse_flags` (generic single/multi flag parser)
- Bug fix: `_acta_fzf_select` used `$s.tags` instead of `$_.tags` — fzf picker never showed tags
- Tested against temp data dir; deployed to `$HOME\scripts\acta.ps1`
- Backup pre-change: `_BACKUPS/acta-2026-06-13.ps1`

### 2026-05-15 — v2: full feature set

- Tags: optional per snippet, filterable in list/search
- `acta edit <id>` — interactive field editor
- `acta run` without id — fzf interactive picker
- `acta log` — execution history (timestamp + exit code). `acta log clear` to reset.
- `acta chain` — named sequences: add/list/run/delete
- `acta export` / `acta import` — JSON backup and restore
- `acta push` / `acta pull` — git sync (Forgejo or any remote)
- Bug fix: `[object[]]` parameter type preserves int arrays (fixes `5,6,7` parsing)

### 2026-05-15 — v1: initial release

- `add` / `list` / `search` / `run` / `delete`
- JSON storage, error handling, `run id,id,id` multi-execution
- Born from frustration with pet's lack of non-interactive `add`
- Name: *acta* (Latin: official records)

## TODO

- [ ] Sync setup: `git init` + remote in `$HOME\.config\acta\` when push/pull is needed
- [ ] Add tags to snippets 2 and 3 (VM) via `acta edit`
- [x] Consider `acta chain edit` to modify existing chains — implemented 2026-06-13
