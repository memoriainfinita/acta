$actaDir    = "$HOME\.config\acta"
$actaFile   = "$actaDir\acta.json"
$actaLogFile= "$actaDir\acta-log.json"
$actaChains = "$actaDir\acta-chains.json"

# ── helpers ────────────────────────────────────────────────────────────────

function _acta_ensure {
    if (-not (Test-Path $actaDir)) {
        New-Item -ItemType Directory -Force $actaDir | Out-Null
    }
}

function _acta_load_file($path) {
    if (-not (Test-Path $path)) { return ,[System.Collections.ArrayList]@() }
    try {
        $raw = Get-Content $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $list = [System.Collections.ArrayList]@()
        foreach ($i in @($raw)) { if ($i) { $list.Add($i) | Out-Null } }
        return ,$list
    } catch {
        Write-Host "Error reading $path (may be corrupted) — $_" -ForegroundColor Red
        return ,[System.Collections.ArrayList]@()
    }
}

function _acta_save_file($path, $data) {
    try {
        _acta_ensure
        if ($data.Count -eq 0) { '[]' | Set-Content $path -ErrorAction Stop }
        else { $data | ConvertTo-Json -Depth 5 | Set-Content $path -ErrorAction Stop }
    } catch {
        Write-Host "Error saving $path — $_" -ForegroundColor Red
    }
}

function _acta_load   { return ,(_acta_load_file $actaFile) }
function _acta_save($d){ _acta_save_file $actaFile $d }

function _acta_next_id($data) {
    if ($data.Count -eq 0) { return 1 }
    return ($data | Measure-Object -Property id -Maximum).Maximum + 1
}

function _acta_print($s) {
    $tags = if ($s.tags -and $s.tags.Count -gt 0) { " [" + ($s.tags -join ", ") + "]" } else { "" }
    Write-Host "[$($s.id)] " -ForegroundColor DarkGray -NoNewline
    Write-Host "$($s.title)$tags" -ForegroundColor Cyan
    Write-Host "    $($s.description)" -ForegroundColor Gray
    Write-Host "    > $($s.command)" -ForegroundColor Yellow
    Write-Host "    created: $($s.created)  updated: $($s.updated)" -ForegroundColor DarkGray
    Write-Host ""
}

function _acta_log_entry($acta_id, $title, $exit_code) {
    $log = _acta_load_file $actaLogFile
    $log.Add([PSCustomObject]@{
        id        = (_acta_next_id $log)
        acta_id   = $acta_id
        title     = $title
        exit_code = $exit_code
        timestamp = (Get-Date -Format "yyyy-MM-dd HH:mm")
    }) | Out-Null
    _acta_save_file $actaLogFile $log
}

function _acta_parse_ids($raw) {
    $ids = [System.Collections.ArrayList]@()
    foreach ($token in $raw) {
        $items = if ($token -is [array]) { $token } else { "$token" -split "," }
        foreach ($item in $items) {
            $part = "$item".Trim()
            if ($part -eq "") { continue }
            $n = 0
            if ([int]::TryParse($part, [ref]$n)) { $ids.Add($n) | Out-Null }
            else { Write-Host "Invalid ID '$part' — must be a number." -ForegroundColor Red; return $null }
        }
    }
    return ,$ids
}

function _acta_parse_flags($tokens, $spec) {
    # spec: hashtable of flag name -> 'single' | 'multi'
    $result = @{}
    $i = 0
    while ($i -lt $tokens.Count) {
        $tok = "$($tokens[$i])"
        if (-not $spec.ContainsKey($tok)) {
            Write-Host "Unknown flag '$tok'. Valid: $($spec.Keys -join ', ')" -ForegroundColor Red
            return $null
        }
        $i++
        if ($spec[$tok] -eq 'multi') {
            $vals = [System.Collections.ArrayList]@()
            while ($i -lt $tokens.Count -and -not ("$($tokens[$i])" -like '--*')) {
                foreach ($v in @($tokens[$i])) { $vals.Add($v) | Out-Null }
                $i++
            }
            if ($vals.Count -eq 0) { Write-Host "Flag '$tok' needs at least one value." -ForegroundColor Red; return $null }
            $result[$tok] = $vals
        } else {
            if ($i -ge $tokens.Count -or "$($tokens[$i])" -like '--*') {
                Write-Host "Flag '$tok' needs a value." -ForegroundColor Red
                return $null
            }
            $result[$tok] = "$($tokens[$i])"
            $i++
        }
    }
    return $result
}

function _acta_run_one($s) {
    Write-Host "Running [$($s.id)] $($s.title)" -ForegroundColor Cyan
    $code = 0
    try {
        Invoke-Expression $s.command
        $code = if ($LASTEXITCODE) { $LASTEXITCODE } else { 0 }
        if ($code -ne 0) { Write-Host "Exited with code $code" -ForegroundColor Yellow }
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
        $code = 1
    }
    _acta_log_entry $s.id $s.title $code
}

function _acta_fzf_select($data) {
    $lines = $data | ForEach-Object {
        $tags = if ($_.tags -and $_.tags.Count -gt 0) { " [" + ($_.tags -join ",") + "]" } else { "" }
        "[$($_.id)] $($_.title)$tags — $($_.description)"
    }
    $selected = $lines | fzf --prompt="acta> "
    if (-not $selected) { return $null }
    $idStr = ($selected -replace '^\[(\d+)\].*', '$1')
    $n = 0
    if ([int]::TryParse($idStr, [ref]$n)) { return $n }
    return $null
}

# ── main ───────────────────────────────────────────────────────────────────

function acta {
    param(
        [Parameter(Position=0)][string]$action,
        [Parameter(Position=1, ValueFromRemainingArguments)][object[]]$args2
    )
    $p1 = if ($args2.Count -gt 0) { $args2[0] } else { "" }
    $p2 = if ($args2.Count -gt 1) { $args2[1] } else { "" }
    $p3 = if ($args2.Count -gt 2) { $args2[2] } else { "" }

    switch ($action) {

        # ── add ──────────────────────────────────────────────────────────
        "add" {
            if (-not $p1 -or -not $p2 -or -not $p3) {
                Write-Host 'Usage: acta add "title" "description" "command" [tag1 tag2 ...]' -ForegroundColor Yellow
                return
            }
            $tags = if ($args2.Count -gt 3) { @($args2[3..($args2.Count-1)]) } else { @() }
            $data = _acta_load
            $now  = Get-Date -Format "yyyy-MM-dd HH:mm"
            $data.Add([PSCustomObject]@{
                id          = (_acta_next_id $data)
                title       = $p1
                description = $p2
                command     = $p3
                tags        = $tags
                created     = $now
                updated     = $now
            }) | Out-Null
            _acta_save $data
            Write-Host "Added [$($data[-1].id)] $p1" -ForegroundColor Green
        }

        # ── edit ─────────────────────────────────────────────────────────
        "edit" {
            if (-not $p1) { Write-Host "Usage: acta edit <id>" -ForegroundColor Yellow; return }
            $n = 0
            if (-not [int]::TryParse($p1, [ref]$n)) { Write-Host "Invalid ID." -ForegroundColor Red; return }
            $data = _acta_load
            $s = $data | Where-Object { $_.id -eq $n }
            if (-not $s) { Write-Host "ID $n not found." -ForegroundColor Red; return }
            if ($args2.Count -gt 1) {
                $flags = _acta_parse_flags $args2[1..($args2.Count-1)] @{
                    '--title' = 'single'; '--desc' = 'single'; '--cmd' = 'single'; '--tags' = 'multi'
                }
                if ($null -eq $flags) { return }
                if ($flags.ContainsKey('--title')) { $s.title       = $flags['--title'] }
                if ($flags.ContainsKey('--desc'))  { $s.description = $flags['--desc'] }
                if ($flags.ContainsKey('--cmd'))   { $s.command     = $flags['--cmd'] }
                if ($flags.ContainsKey('--tags'))  { $s.tags        = @($flags['--tags'] | ForEach-Object { "$_" }) }
            } else {
                Write-Host "Editing [$($s.id)] $($s.title) — press Enter to keep current value" -ForegroundColor Cyan
                Write-Host ""
                $t = Read-Host "Title [$($s.title)]"
                $d = Read-Host "Description [$($s.description)]"
                $c = Read-Host "Command [$($s.command)]"
                $tg= Read-Host "Tags [$($s.tags -join ', ')] (space-separated)"
                if ($t)  { $s.title       = $t }
                if ($d)  { $s.description = $d }
                if ($c)  { $s.command     = $c }
                if ($tg) { $s.tags        = @($tg -split '\s+' | Where-Object { $_ }) }
            }
            $s.updated = Get-Date -Format "yyyy-MM-dd HH:mm"
            _acta_save $data
            Write-Host "Updated." -ForegroundColor Green
        }

        # ── list ─────────────────────────────────────────────────────────
        "list" {
            $data = _acta_load
            if ($data.Count -eq 0) { Write-Host "No acta yet."; return }
            if ($p1 -eq "--tag" -and $p2) {
                $data = $data | Where-Object { $_.tags -contains $p2 }
                if (-not $data) { Write-Host "No acta with tag '$p2'."; return }
            }
            @($data) | ForEach-Object { _acta_print $_ }
        }

        # ── search ───────────────────────────────────────────────────────
        "search" {
            if (-not $p1) { Write-Host "Usage: acta search <text>" -ForegroundColor Yellow; return }
            $data = _acta_load
            $results = $data | Where-Object {
                $_.title -match $p1 -or $_.description -match $p1 -or
                $_.command -match $p1 -or ($_.tags -and $_.tags -contains $p1)
            }
            if (-not $results) { Write-Host "No results for '$p1'."; return }
            @($results) | ForEach-Object { _acta_print $_ }
        }

        # ── run ──────────────────────────────────────────────────────────
        "run" {
            $data = _acta_load
            if ($data.Count -eq 0) { Write-Host "No acta yet."; return }
            if ($args2.Count -eq 0) {
                $id = _acta_fzf_select $data
                if ($null -eq $id) { return }
                $s = $data | Where-Object { $_.id -eq $id }
                if ($s) { _acta_run_one $s }
                return
            }
            $ids = _acta_parse_ids $args2
            if ($null -eq $ids) { return }
            if ($ids.Count -eq 0) { Write-Host "No valid IDs provided." -ForegroundColor Yellow; return }
            foreach ($id in $ids) {
                $s = $data | Where-Object { $_.id -eq $id }
                if (-not $s) { Write-Host "ID $id not found." -ForegroundColor Red; continue }
                _acta_run_one $s
            }
        }

        # ── delete ───────────────────────────────────────────────────────
        "delete" {
            $data = _acta_load
            if ($data.Count -eq 0) { Write-Host "No acta."; return }
            if ($args2.Count -gt 0) {
                $ids = _acta_parse_ids $args2
                if ($null -eq $ids) { return }
                if ($ids.Count -eq 0) { Write-Host "No valid IDs provided." -ForegroundColor Yellow; return }
                $deleted = [System.Collections.ArrayList]@()
                foreach ($id in $ids) {
                    $s = $data | Where-Object { $_.id -eq $id }
                    if (-not $s) { Write-Host "ID $id not found." -ForegroundColor Red; continue }
                    Write-Host "Deleted:" -ForegroundColor Green
                    _acta_print $s
                    $deleted.Add($id) | Out-Null
                }
                if ($deleted.Count -eq 0) { return }
                $new = [System.Collections.ArrayList]@()
                $data | Where-Object { $deleted -notcontains $_.id } | ForEach-Object { $new.Add($_) | Out-Null }
                _acta_save $new
                return
            }
            $data | ForEach-Object {
                Write-Host "[$($_.id)] $($_.title)" -ForegroundColor Cyan
                Write-Host "    $($_.description)" -ForegroundColor Gray
            }
            Write-Host ""
            $input_id = Read-Host "ID to delete"
            $n = 0
            if (-not [int]::TryParse($input_id.Trim(), [ref]$n)) {
                Write-Host "Invalid ID." -ForegroundColor Red; return
            }
            $new = [System.Collections.ArrayList]@()
            $data | Where-Object { $_.id -ne $n } | ForEach-Object { $new.Add($_) | Out-Null }
            if ($new.Count -eq $data.Count) { Write-Host "ID $n not found." -ForegroundColor Red; return }
            _acta_save $new
            Write-Host "Deleted." -ForegroundColor Green
        }

        # ── log ──────────────────────────────────────────────────────────
        "log" {
            if ($p1 -eq "clear") {
                _acta_save_file $actaLogFile ([System.Collections.ArrayList]@())
                Write-Host "Log cleared." -ForegroundColor Green
                return
            }
            $log = _acta_load_file $actaLogFile
            if ($log.Count -eq 0) { Write-Host "No log entries yet."; return }
            $log | ForEach-Object {
                $ok = if ($_.exit_code -eq 0) { "OK" } else { "FAIL($($_.exit_code))" }
                $color = if ($_.exit_code -eq 0) { "Green" } else { "Red" }
                Write-Host "$($_.timestamp) " -ForegroundColor DarkGray -NoNewline
                Write-Host "$ok " -ForegroundColor $color -NoNewline
                Write-Host "[$($_.acta_id)] $($_.title)" -ForegroundColor Cyan
            }
        }

        # ── chain ─────────────────────────────────────────────────────────
        "chain" {
            $chains = _acta_load_file $actaChains
            switch ($p1) {
                "add" {
                    $name = $p2; $desc = $p3
                    $rawids = if ($args2.Count -gt 3) { $args2[3..($args2.Count-1)] } else { @() }
                    if (-not $name -or -not $desc -or $rawids.Count -eq 0) {
                        Write-Host 'Usage: acta chain add "name" "description" id,id,id' -ForegroundColor Yellow; return
                    }
                    $ids = _acta_parse_ids $rawids
                    if ($null -eq $ids -or $ids.Count -eq 0) { return }
                    if ($chains | Where-Object { $_.name -eq $name }) {
                        Write-Host "Chain '$name' already exists. Use 'acta chain edit' to modify." -ForegroundColor Yellow; return
                    }
                    $chains.Add([PSCustomObject]@{
                        name        = $name
                        description = $desc
                        ids         = @($ids)
                        created     = (Get-Date -Format "yyyy-MM-dd HH:mm")
                    }) | Out-Null
                    _acta_save_file $actaChains $chains
                    Write-Host "Chain '$name' created ($($ids.Count) steps)." -ForegroundColor Green
                }
                "edit" {
                    if (-not $p2 -or $args2.Count -lt 3) {
                        Write-Host 'Usage: acta chain edit <name> [--name X] [--desc X] [--ids 1,4,7]' -ForegroundColor Yellow; return
                    }
                    $chain = $chains | Where-Object { $_.name -eq $p2 }
                    if (-not $chain) { Write-Host "Chain '$p2' not found." -ForegroundColor Red; return }
                    $flags = _acta_parse_flags $args2[2..($args2.Count-1)] @{
                        '--name' = 'single'; '--desc' = 'single'; '--ids' = 'multi'
                    }
                    if ($null -eq $flags) { return }
                    if ($flags.ContainsKey('--name')) {
                        $newName = $flags['--name']
                        if ($newName -ne $chain.name -and ($chains | Where-Object { $_.name -eq $newName })) {
                            Write-Host "Chain '$newName' already exists." -ForegroundColor Red; return
                        }
                        $chain.name = $newName
                    }
                    if ($flags.ContainsKey('--desc')) { $chain.description = $flags['--desc'] }
                    if ($flags.ContainsKey('--ids')) {
                        $ids = _acta_parse_ids $flags['--ids']
                        if ($null -eq $ids -or $ids.Count -eq 0) { return }
                        $chain.ids = @($ids)
                    }
                    _acta_save_file $actaChains $chains
                    Write-Host "Chain '$($chain.name)' updated." -ForegroundColor Green
                }
                "list" {
                    if ($chains.Count -eq 0) { Write-Host "No chains yet."; return }
                    $chains | ForEach-Object {
                        Write-Host "$($_.name)" -ForegroundColor Cyan -NoNewline
                        Write-Host " — $($_.description)" -ForegroundColor Gray
                        Write-Host "    steps: $($_.ids -join ' → ')" -ForegroundColor Yellow
                        Write-Host ""
                    }
                }
                "run" {
                    if (-not $p2) { Write-Host "Usage: acta chain run <name>" -ForegroundColor Yellow; return }
                    $chain = $chains | Where-Object { $_.name -eq $p2 }
                    if (-not $chain) { Write-Host "Chain '$p2' not found." -ForegroundColor Red; return }
                    $data = _acta_load
                    Write-Host "Running chain: $($chain.name)" -ForegroundColor Cyan
                    foreach ($id in $chain.ids) {
                        $s = $data | Where-Object { $_.id -eq $id }
                        if (-not $s) { Write-Host "ID $id not found — skipping." -ForegroundColor Yellow; continue }
                        _acta_run_one $s
                    }
                }
                "delete" {
                    if (-not $p2) { Write-Host "Usage: acta chain delete <name>" -ForegroundColor Yellow; return }
                    $new = [System.Collections.ArrayList]@()
                    $chains | Where-Object { $_.name -ne $p2 } | ForEach-Object { $new.Add($_) | Out-Null }
                    if ($new.Count -eq $chains.Count) { Write-Host "Chain '$p2' not found." -ForegroundColor Red; return }
                    _acta_save_file $actaChains $new
                    Write-Host "Chain '$p2' deleted." -ForegroundColor Green
                }
                default { Write-Host "Usage: acta chain <add|edit|list|run|delete>" -ForegroundColor Yellow }
            }
        }

        # ── export / import ──────────────────────────────────────────────
        "export" {
            $dest = if ($p1) { $p1 } else { ".\acta-export-$(Get-Date -Format 'yyyyMMdd-HHmm').json" }
            try {
                Copy-Item $actaFile $dest -ErrorAction Stop
                Write-Host "Exported to $dest" -ForegroundColor Green
            } catch { Write-Host "Export failed — $_" -ForegroundColor Red }
        }

        "import" {
            if (-not $p1) { Write-Host "Usage: acta import <file>" -ForegroundColor Yellow; return }
            if (-not (Test-Path $p1)) { Write-Host "File not found: $p1" -ForegroundColor Red; return }
            try {
                Get-Content $p1 -Raw | ConvertFrom-Json | Out-Null
            } catch { Write-Host "Invalid JSON file." -ForegroundColor Red; return }
            $confirm = Read-Host "This will overwrite current acta. Continue? (y/n)"
            if ($confirm -ne "y") { Write-Host "Cancelled."; return }
            Copy-Item $p1 $actaFile -Force
            Write-Host "Imported from $p1" -ForegroundColor Green
        }

        # ── push / pull (Forgejo via git) ────────────────────────────────
        "push" {
            try {
                git -C $actaDir add acta.json acta-log.json acta-chains.json 2>&1
                $msg = "acta: sync $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
                git -C $actaDir commit -m $msg 2>&1
                git -C $actaDir push 2>&1
                Write-Host "Pushed." -ForegroundColor Green
            } catch { Write-Host "Push failed — $_" -ForegroundColor Red }
        }

        "pull" {
            try {
                git -C $actaDir pull 2>&1
                Write-Host "Pulled." -ForegroundColor Green
            } catch { Write-Host "Pull failed — $_" -ForegroundColor Red }
        }

        # ── help ─────────────────────────────────────────────────────────
        default {
            Write-Host "acta — command snippet manager"
            Write-Host ""
            Write-Host "  acta add `"title`" `"description`" `"command`" [tag1 tag2 ...]"
            Write-Host "  acta edit <id> [--title X] [--desc X] [--cmd X] [--tags a b c]   (no flags = interactive)"
            Write-Host "  acta list [--tag <tag>]"
            Write-Host "  acta search <text>"
            Write-Host "  acta run [id[,id,...]]     (no id = fzf picker)"
            Write-Host "  acta delete [id[,id,...]]  (no id = interactive)"
            Write-Host "  acta log [clear]"
            Write-Host "  acta chain add|edit|list|run|delete"
            Write-Host "  acta chain edit <name> [--name X] [--desc X] [--ids 1,4,7]"
            Write-Host "  acta export [file]"
            Write-Host "  acta import <file>"
            Write-Host "  acta push / acta pull"
        }
    }
}
