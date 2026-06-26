# acta

Command snippet manager for PowerShell. Store titled, described commands with tags and timestamps, run them on demand, chain them into sequences, and sync via git.

*Acta* — Latin for official records, transactions, deeds.

## Installation

1. Copy `acta.ps1` to a permanent location (e.g. `$HOME\scripts\acta.ps1`)
2. Add to your PowerShell profile (`$PROFILE`):

```powershell
. "$HOME\scripts\acta.ps1"
```

Data files are stored in `$HOME\.config\acta\`:

| File | Contents |
|------|----------|
| `acta.json` | Snippets |
| `acta-log.json` | Execution history |
| `acta-chains.json` | Named chains |

## Commands

### Snippets

```powershell
# Add a snippet (tags optional)
acta add "title" "description" "command" [tag1 tag2 ...]

# List all snippets, optionally filtered by tag
acta list
acta list --tag vm

# Search by text or tag across all fields
acta search <text>

# Edit a snippet. With flags = partial non-interactive edit; no flags = interactive
acta edit <id>
acta edit <id> --title "new title" --desc "new desc" --cmd "new command" --tags a b c

# Delete one or more snippets directly (prints the deleted snippet for recovery)
acta delete <id>
acta delete 3,5,7

# Delete interactively (shows list, prompts for ID)
acta delete
```

### Running

```powershell
# Run one or more snippets by ID
acta run <id>
acta run 2,3,4        # runs in sequence

# Run with fzf interactive picker (no ID needed)
acta run
```

### Chains

Named sequences of snippets that run in order.

```powershell
acta chain add "name" "description" id,id,id
acta chain edit "name" --name "new name" --desc "new desc" --ids 1,4,7
acta chain list
acta chain run "name"
acta chain delete "name"
```

Example:
```powershell
acta chain add "boot-homelab" "Arrancar VM y servicios" 2,3,5
acta chain run "boot-homelab"
```

### Log

Execution history with timestamp and exit code.

```powershell
acta log           # show all entries
acta log clear     # clear log
```

Output format:
```
2026-05-15 04:00  OK   [2] Arrancar VM arr
2026-05-15 04:01  FAIL(1)  [5] SSH a VM
```

### Export / Import

```powershell
acta export                        # exports to acta-export-YYYYMMDD-HHmm.json
acta export path\to\backup.json    # exports to specified path
acta import path\to\backup.json    # overwrites current acta.json (prompts confirmation)
```

### Sync (Forgejo / git)

The `$HOME\.config\acta\` directory must be a git repo with a remote configured.

Setup (one time):
```powershell
cd $HOME\.config\acta
git init
git remote add origin <your-remote-url>    # e.g. GitHub, Forgejo, Gitea
```

Then:
```powershell
acta push    # commit + push acta.json, acta-log.json, acta-chains.json
acta pull    # pull latest from remote
```

## Data format

### acta.json

```json
[
  {
    "id": 1,
    "title": "Arrancar VM arr",
    "description": "Arranca la VM arr en modo headless",
    "command": "& 'C:\\Program Files\\Oracle\\VirtualBox\\VBoxManage.exe' startvm arr --type headless",
    "tags": ["vm", "virtualbox"],
    "created": "2026-05-15 03:00",
    "updated": "2026-05-15 03:00"
  }
]
```

### acta-log.json

```json
[
  {
    "id": 1,
    "acta_id": 2,
    "title": "Arrancar VM arr",
    "exit_code": 0,
    "timestamp": "2026-05-15 03:00"
  }
]
```

### acta-chains.json

```json
[
  {
    "name": "boot-homelab",
    "description": "Arrancar VM y servicios",
    "ids": [2, 3, 5],
    "created": "2026-05-15 03:00"
  }
]
```
