# ratmac-transit — slice/proj transition: final regen, write summary, status:done, mv tier → archive.
# Chain: ratmac-transit -> ratmac-regen -> ratmac-lint. Writes only under scheduler/ (R5). Reads state first (R9).
# All STOPs (R12) fire BEFORE any write or regen, so an ambiguous tier never half-transits.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('slice','proj')][string]$Tier,
    [string]$NewSlice,
    [Parameter(Mandatory)][string]$Summary,   # literal text OR a path to an existing file
    [switch]$NoSuccessor,
    [string]$Root,
    [string]$Proj,
    [string]$Ts,
    [switch]$Force
)
. "$PSScriptRoot/_common.ps1"

$stamp = Get-RatmacStamp $Ts
$p = Get-RatmacProj -Root $Root -Proj $Proj
$pdir = $p.Path
$touched = @()
$generated = @()

# Single carried regen result (mirrors close.ps1:138-139): success string unless ANY
# spawned regen returns non-zero, in which case it flips to FAILED and the rollup is stale.
$regenResult = 'proj rollup rebuilt (final)'

# resolve the sibling skill dir for spawning (R18: spawn another skill, never self)
$skillsRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$regenPs = Join-Path $skillsRoot 'ratmac-regen/scripts/regen.ps1'

if ($Tier -eq 'slice') {
    $slice = Get-RatmacActiveSlice -ProjPath $pdir
    if (-not $slice) {
        Write-Output "BLOCKED no active slice under $($p.Proj)"
        Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Active proj'=$p.Proj; 'Blocked items'='no active slice' }); exit 2
    }
    $sname = Split-Path $slice -Leaf

    # STOP: live tasks still in grad/ (R12 — never archive a slice with work in flight) unless -Force
    $grad = Join-Path $slice 'grad'
    $live = @(Get-ChildItem -LiteralPath $grad -Directory -Filter 't-*' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    if ($live.Count -gt 0 -and -not $Force) {
        Write-Output "HUMAN_DECISION_REQUIRED active tasks present: $($live -join ', ')"
        Write-Output (Write-RatmacContract @{
            'Run mode'='single'; 'Active proj'=$p.Proj; 'Active slice'=$sname
            'Human decisions required'='close/migrate live tasks (ratmac-close) then retry, or pass -Force'
            'Blocked items'=($live -join ', ')
        }); exit 3
    }

    # STOP: no successor and not explicitly terminal (R12) — decide before any write
    if (-not $NewSlice -and -not $NoSuccessor) {
        Write-Output "HUMAN_DECISION_REQUIRED no successor slice"
        Write-Output (Write-RatmacContract @{
            'Run mode'='single'; 'Active proj'=$p.Proj; 'Active slice'=$sname
            'Human decisions required'='pass -NewSlice <s-name> for the successor, or -NoSuccessor to end the line'
        }); exit 3
    }

    # STOP: archive collision (close-style guard) — pre-check BEFORE any write so Windows
    # Move-Item can never nest the source into an existing archive/<s-name> (R12, fires
    # before the contract). Placed after the STOP gates and before the first write.
    $archive = Join-Path $pdir 'archive'
    $dest = Join-Path $archive $sname
    if (Test-Path $dest) {
        Write-Output "BLOCKED archive collision: $dest already exists; cannot move $sname"
        Write-Output (Write-RatmacContract @{
            'Run mode'='single'; 'Active proj'=$p.Proj; 'Active slice'=$sname
            'Blocked items'="archive/$sname exists"
        }); exit 2
    }

    # 1. trigger regen so the final ## affects rollup reflects this slice before it freezes
    & pwsh -NoProfile -File $regenPs -Root $Root -Proj $p.Proj -Ts $stamp | Out-Null
    if ($LASTEXITCODE -ne 0) { $regenResult = "FAILED (regen exit $LASTEXITCODE; rollup stale)" }

    # 2. write summary.md — copy a supplied file verbatim, else wrap the literal text (Q5 one-pager)
    $summaryMd = Join-Path $slice 'summary.md'
    # canonical LF write (R4/R10): NOT Set-Content (CRLF on Windows) — transit.sh writes LF
    # via cat/printf, so without this summary.md diverges byte-for-byte across engines.
    if (Test-Path -LiteralPath $Summary -PathType Leaf) {
        $body = ((Get-Content -LiteralPath $Summary -Raw) -replace "`r`n","`n")
        if ($body.EndsWith("`n")) { $body = $body.Substring(0, $body.Length - 1) }
        Set-RatmacFileLines -Path $summaryMd -Lines @($body -split "`n")
    } else {
        $wrapped = @("---","time-created: $stamp","time-modified: $stamp","---","","# summary — $sname","",$Summary)
        Set-RatmacFileLines -Path $summaryMd -Lines @($wrapped)
    }
    $touched += ($summaryMd -replace '\\','/')

    # 3. status: done on slice state.md
    $sstate = Join-Path $slice 'state.md'
    if (Test-Path $sstate) {
        Set-RatmacFrontmatterValue -Path $sstate -Key 'status' -Value 'done' -Ts $stamp
        $touched += ($sstate -replace '\\','/')
    }

    # 3b. final proj-rollup regen BEFORE the mv (lifecycle step 7 regen-then-mv order):
    # regen enumerates only LIVE s-* children, so the closing slice's ## affects must be
    # folded into the proj rollup while the slice is still in place. Running this after the
    # mv would drop the contribution and empty the proj rollup when the last slice closes.
    & pwsh -NoProfile -File $regenPs -Root $Root -Proj $p.Proj -Ts $stamp | Out-Null
    if ($LASTEXITCODE -ne 0) { $regenResult = "FAILED (regen exit $LASTEXITCODE; rollup stale)" }

    # 4. mv slice dir → <proj>/archive/<s-name>  (collision pre-checked above)
    if (-not (Test-Path $archive)) { New-Item -ItemType Directory -Force -Path $archive | Out-Null }
    Move-Item -LiteralPath $slice -Destination $dest
    $touched += ($dest -replace '\\','/')

    # 5. proj-tier bookkeeping: close-slice log; if -NewSlice, point the proj at it (do NOT auto-create)
    $plog = Join-Path $pdir 'log.md'
    Add-RatmacLog -LogPath $plog -Verb 'close-slice' -Args $sname -Ts $stamp
    $touched += ($plog -replace '\\','/')

    $nextNote = ''
    if ($NewSlice) {
        $newName = if ($NewSlice -match '^s-') { $NewSlice } else { "s-$NewSlice" }
        # update proj state.md "active slice:" pointer (lives under ## scratch)
        $pstate = Join-Path $pdir 'state.md'
        if (Test-Path $pstate) {
            $lines = [System.Collections.ArrayList]@(Get-Content -LiteralPath $pstate)
            $sec = Find-RatmacSection -Lines $lines -Name 'scratch'
            if ($sec) {
                $set = $false
                for ($i=$sec.Start+1; $i -lt $sec.End; $i++) {
                    if ($lines[$i] -match '^active slice:') { $lines[$i] = "active slice: $newName"; $set=$true; break }
                }
                if (-not $set) { $lines.Insert($sec.Start+1, "active slice: $newName") }
            } else {
                [void]$lines.Add(''); [void]$lines.Add('## scratch'); [void]$lines.Add("active slice: $newName")
            }
            # canonical LF write (R4/R10): NOT Set-Content (CRLF on Windows). Follow-up
            # fm-set re-normalizes too, but write LF here so the file is never momentarily CRLF.
            Set-RatmacFileLines -Path $pstate -Lines @($lines)
            Set-RatmacFrontmatterValue -Path $pstate -Key 'time-modified' -Value $stamp -Ts $stamp
            $touched += ($pstate -replace '\\','/')
        }
        Add-RatmacLog -LogPath $plog -Verb 'active-slice' -Args $newName -Ts $stamp
        $nextNote = "ratmac-kickoff -Tier slice -Name $newName (NOT auto-created — kickoff is the next step)"
    } else {
        $nextNote = 'no successor (-NoSuccessor): slice line ended'
    }

    # 6. lint to verify the archived tree. NOTE: do NOT regen here — the proj rollup was
    # already settled at step 3b while the slice was live; a post-mv regen would re-enumerate
    # only the remaining live slices and drop the just-archived slice's affects (lifecycle 7).
    $lintPs = Join-Path $skillsRoot 'ratmac-lint/scripts/lint.ps1'
    $lintResult = 'ratmac-lint not run'
    if (Test-Path $lintPs) {
        $lintOut = & pwsh -NoProfile -File $lintPs -Root $Root 2>&1 | Out-String
        $lintResult = (($lintOut -split "`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
    }

    Write-Output "transit slice: $sname archived under $($p.Proj)"
    if ($NewSlice) { Write-Output "  next: $nextNote" } else { Write-Output "  $nextNote" }
    Write-Output (Write-RatmacContract @{
        'Run mode'='single'; 'Active proj'=$p.Proj; 'Active slice'="$sname (archived)"
        'Classification'='slice-transit'
        'Skill chain'='ratmac-transit -> ratmac-regen -> ratmac-lint'
        'Files touched'=(($touched | Select-Object -Unique) -join ', ')
        'Regen result'=$regenResult
        'Lint result'=$lintResult
        'Next safe action'=$nextNote
    })
    exit 0
}

# --- proj tier ---------------------------------------------------------------------
if ($Tier -eq 'proj') {
    $pstate = Join-Path $pdir 'state.md'

    # STOP: archive collision (close-style guard) — pre-check BEFORE any write so Windows
    # Move-Item can never nest the source into an existing archive/<p-name> (R12).
    $archive = Join-Path $p.Root 'archive'
    $dest = Join-Path $archive $p.Proj
    if (Test-Path $dest) {
        Write-Output "BLOCKED archive collision: $dest already exists; cannot move $($p.Proj)"
        Write-Output (Write-RatmacContract @{
            'Run mode'='single'; 'Active proj'=$p.Proj
            'Blocked items'="archive/$($p.Proj) exists"
        }); exit 2
    }

    # 1. final regen of proj ## affects rollup
    & pwsh -NoProfile -File $regenPs -Root $Root -Proj $p.Proj -Ts $stamp | Out-Null
    if ($LASTEXITCODE -ne 0) { $regenResult = "FAILED (regen exit $LASTEXITCODE; rollup stale)" }

    # 2. write proj summary.md — copy a supplied file verbatim, else wrap the literal text
    $summaryMd = Join-Path $pdir 'summary.md'
    # canonical LF write (R4/R10): NOT Set-Content (CRLF on Windows) — matches transit.sh.
    if (Test-Path -LiteralPath $Summary -PathType Leaf) {
        $body = ((Get-Content -LiteralPath $Summary -Raw) -replace "`r`n","`n")
        if ($body.EndsWith("`n")) { $body = $body.Substring(0, $body.Length - 1) }
        Set-RatmacFileLines -Path $summaryMd -Lines @($body -split "`n")
    } else {
        $wrapped = @("---","time-created: $stamp","time-modified: $stamp","---","","# summary — $($p.Proj)","",$Summary)
        Set-RatmacFileLines -Path $summaryMd -Lines @($wrapped)
    }
    $touched += ($summaryMd -replace '\\','/')

    # 3. retired log line + status: done
    $plog = Join-Path $pdir 'log.md'
    Add-RatmacLog -LogPath $plog -Verb 'retired' -Ts $stamp
    $touched += ($plog -replace '\\','/')
    if (Test-Path $pstate) {
        Set-RatmacFrontmatterValue -Path $pstate -Key 'status' -Value 'done' -Ts $stamp
        $touched += ($pstate -replace '\\','/')
    }

    # 4. mv proj dir → <schedRoot>/archive/<p-name>  (collision pre-checked above)
    if (-not (Test-Path $archive)) { New-Item -ItemType Directory -Force -Path $archive | Out-Null }
    Move-Item -LiteralPath $pdir -Destination $dest
    $touched += ($dest -replace '\\','/')

    # 5. lint to verify the archived tree
    $lintPs = Join-Path $skillsRoot 'ratmac-lint/scripts/lint.ps1'
    $lintResult = 'ratmac-lint not run'
    if (Test-Path $lintPs) {
        $lintOut = & pwsh -NoProfile -File $lintPs -Root $Root 2>&1 | Out-String
        $lintResult = (($lintOut -split "`n") | Where-Object { $_.Trim() } | Select-Object -First 1)
    }

    Write-Output "transit proj: $($p.Proj) retired → $($dest -replace '\\','/')"
    Write-Output (Write-RatmacContract @{
        'Run mode'='single'; 'Active proj'="$($p.Proj) (retired)"
        'Classification'='proj-retire'
        'Skill chain'='ratmac-transit -> ratmac-regen -> ratmac-lint'
        'Files touched'=(($touched | Select-Object -Unique) -join ', ')
        'Regen result'=$regenResult
        'Lint result'=$lintResult
        'Next safe action'='none — project archived'
    })
    exit 0
}
