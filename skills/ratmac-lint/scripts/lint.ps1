# ratmac-lint — read-only schema + invariant + fence audit (R11: NEVER writes, even -Strict).
# Walks the resolved proj tree (proj state.md/log.md, each slice state.md/log.md, grad+archive
# task issue/task/state/log, residuals) and reports a violations table. Covers scheduler-sys
# invariants S5 (frontmatter), S7 (naming prefixes), S13 (residual sentinel), S15/S16 (issue tag),
# S18 (## affects on done tasks), S20 (GENERATED fence balance), plus dangling [[t-...]] links.
# -Strict adds the per-mode required-files layout audit (layout.md table). Mirrors arca-lint shape.
[CmdletBinding()]
param(
    [string]$Root,
    [string]$Proj,
    [switch]$Strict,
    [string[]]$Rules,
    [string]$Ts
)
. "$PSScriptRoot/_common.ps1"

# resolve the proj tree (read-only; STOP if unresolvable — before the contract, exit 2)
try { $p = Get-RatmacProj -Root $Root -Proj $Proj }
catch {
    Write-Output "BLOCKED $($_.Exception.Message)"
    Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Files touched'='— (read-only, R11)'; 'Blocked items'='no resolvable project' })
    exit 2
}
$pdir = $p.Path
$mode = Get-RatmacMode -ProjPath $pdir

$want = { param($r) (-not $Rules) -or ($Rules -contains $r) }

$violations = @()
function V($sev,$rule,$path,$msg,$fix){ $script:violations += [pscustomobject]@{ severity=$sev; rule=$rule; path=($path -replace '\\','/'); message=$msg; fix=$fix } }

# --- shared helpers ---------------------------------------------------------------
# every-md frontmatter audit (S5: time-created + time-modified mandatory on every file).
# Emits nothing to stdout (collector-only, like arca-lint's V).
function Audit-Frontmatter($path) {
    if (-not (Test-Path $path)) { return }
    $fm = Read-RatmacFrontmatter $path
    foreach ($k in @('time-created','time-modified')) {
        if (-not $fm.ContainsKey($k) -or "$($fm[$k])".Trim() -eq '') {
            if (& $want 'S5') { V 'error' 'S5' $path "missing $k frontmatter" "add ${k}: <YYYY-MM-DD-HH:MM:SS> to frontmatter" }
        }
    }
}

# S20: GENERATED / /GENERATED fence markers must balance (open==close, never close-before-open)
function Audit-Fence($path) {
    if (-not (Test-Path $path)) { return }
    $opens = 0; $closes = 0; $depth = 0; $bad = $false
    foreach ($ln in Get-Content -LiteralPath $path) {
        if ($ln -match '<!--\s*/GENERATED\s*-->') { $closes++; $depth--; if ($depth -lt 0) { $bad = $true } }
        elseif ($ln -match '<!--\s*GENERATED') { $opens++; $depth++ }
    }
    if (($opens -ne $closes -or $bad) -and (& $want 'S20')) {
        V 'error' 'S20' $path "unbalanced GENERATED fence ($opens open / $closes close)" 'restore matched <!-- GENERATED --> ... <!-- /GENERATED --> pair; rerun ratmac-regen'
    }
}

# dangling [[t-...]] link: target task dir must live in grad/ or archive/ of $slicePath
function Audit-DanglingTaskLinks($path, $slicePath) {
    if (-not (Test-Path $path) -or -not $slicePath) { return }
    if (-not (& $want 'dangling')) { return }
    $raw = Get-Content -LiteralPath $path -Raw
    foreach ($m in [regex]::Matches($raw, '\[\[(t-[^\]\|/]+)')) {
        $tgt = $m.Groups[1].Value.Trim()
        $inGrad    = Test-Path (Join-Path $slicePath "grad/$tgt")
        $inArchive = Test-Path (Join-Path $slicePath "archive/$tgt")
        if (-not $inGrad -and -not $inArchive) {
            V 'warn' 'dangling' $path "dangling link [[${tgt}]] — task in neither grad/ nor archive/" 'fix link target or kickoff the task'
        }
    }
}

# -Strict: assert a required file is present for the active mode (layout.md table)
function Audit-Required($path, $reason) {
    if (-not $Strict) { return }
    if (-not (& $want 'layout')) { return }
    if (-not (Test-Path $path)) {
        V 'error' 'layout' $path "required file missing ($reason)" 'scaffold via ratmac-kickoff for this tier/mode'
    }
}

$soleDual    = $mode -in @('sole','dual')
$maintDual   = $mode -in @('maintainer','dual')

# --- proj tier --------------------------------------------------------------------
$pstate = Join-Path $pdir 'state.md'
if (Test-Path $pstate) {
    Audit-Frontmatter $pstate
    $pfm = Read-RatmacFrontmatter $pstate
    if ((-not $pfm.ContainsKey('status') -or "$($pfm['status'])".Trim() -eq '') -and (& $want 'S5')) {
        V 'error' 'S5' $pstate 'state.md missing status' 'add status: active|done|abandoned'
    }
    if ((-not $pfm.ContainsKey('mode') -or "$($pfm['mode'])".Trim() -eq '') -and (& $want 'S5')) {
        V 'error' 'S5' $pstate 'proj state.md missing mode' 'add mode: maintainer|sole|dual'
    }
    Audit-Fence $pstate
} elseif (& $want 'S5') {
    V 'error' 'S5' $pstate 'proj state.md missing' 'scaffold proj via ratmac-kickoff -Tier proj'
}
# S7: proj dir name prefix
if (((Split-Path $pdir -Leaf) -notlike 'p-*') -and (& $want 'S7')) {
    V 'error' 'S7' $pdir "proj dir '$(Split-Path $pdir -Leaf)' lacks p- prefix" 'rename dir to p-<name> (breaks [[…]] links; fix manually)'
}
# -Strict proj-tier required files.
# NOTE: *-residual.md files are GENERATED lazily by ratmac-regen, NOT scaffolded by
# ratmac-kickoff, so a freshly-kicked-off tier legitimately lacks them until the first
# regen. They are therefore EXCLUDED from the -Strict required-files audit (only their
# S13 sentinel is checked, in Audit-Residual, once they exist) — keeping lint in agreement
# with kickoff's scaffold set. Run ratmac-regen to materialize residuals.
Audit-Required (Join-Path $pdir 'log.md') 'proj log.md (all modes)'
if ($soleDual) {
    Audit-Required (Join-Path $pdir 'goal') 'goal/ dir (sole|dual)'
}

# --- residuals (proj-level): S13 sentinel on line 1 -------------------------------
function Audit-Residual($path) {
    if (-not (Test-Path $path)) { return }
    Audit-Frontmatter $path
    if (& $want 'S13') {
        $first = (Get-Content -LiteralPath $path -TotalCount 1)
        if (-not ($first -match '^<!--\s*GENERATED')) {
            V 'warn' 'S13' $path 'residual missing "<!-- GENERATED" sentinel on line 1' 'rerun ratmac-regen (whole-file generated, S13)'
        }
    }
}
foreach ($r in @(Get-ChildItem -LiteralPath $pdir -Filter '*-residual.md' -File -ErrorAction SilentlyContinue)) { Audit-Residual $r.FullName }

# --- slice tier -------------------------------------------------------------------
foreach ($sdir in @(Get-ChildItem -LiteralPath $pdir -Directory -Filter 's-*' -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'archive' })) {
    $spath = $sdir.FullName
    # S7: slice dir prefix (already filtered to s-*, but assert for completeness on odd casing)
    if (($sdir.Name -notlike 's-*') -and (& $want 'S7')) {
        V 'error' 'S7' $spath "slice dir '$($sdir.Name)' lacks s- prefix" 'rename dir to s-<name>'
    }
    $sstate = Join-Path $spath 'state.md'
    if (Test-Path $sstate) {
        Audit-Frontmatter $sstate
        $sfm = Read-RatmacFrontmatter $sstate
        if ((-not $sfm.ContainsKey('status') -or "$($sfm['status'])".Trim() -eq '') -and (& $want 'S5')) {
            V 'error' 'S5' $sstate 'state.md missing status' 'add status: active|done|abandoned'
        }
        Audit-Fence $sstate
        Audit-DanglingTaskLinks $sstate $spath
    } elseif (& $want 'S5') {
        V 'error' 'S5' $sstate 'slice state.md missing' 'scaffold slice via ratmac-kickoff -Tier slice'
    }
    Audit-Required $sstate 'slice state.md (all modes)'
    Audit-Required (Join-Path $spath 'log.md') 'slice log.md (all modes)'
    if ($soleDual) {
        Audit-Required (Join-Path $spath 'scope.md') 'scope.md (sole|dual)'
        Audit-Required (Join-Path $spath 'scope-history.md') 'scope-history.md (sole|dual)'
        # scope-residual.md is regen-generated, not kickoff-scaffolded — excluded (see proj note).
    }
    # issues-residual.md is regen-generated, not kickoff-scaffolded — excluded (see proj note).
    # slice residuals: S13 sentinel
    foreach ($r in @(Get-ChildItem -LiteralPath $spath -Filter '*-residual.md' -File -ErrorAction SilentlyContinue)) { Audit-Residual $r.FullName }
    # slice log frontmatter
    Audit-Frontmatter (Join-Path $spath 'log.md')

    # --- task tier (grad/ + archive/) ---------------------------------------------
    foreach ($bucket in @('grad','archive')) {
        $bdir = Join-Path $spath $bucket
        if (-not (Test-Path $bdir)) { continue }
        foreach ($td in @(Get-ChildItem -LiteralPath $bdir -Directory -ErrorAction SilentlyContinue)) {
            $tpath = $td.FullName
            # S7: task dir prefix
            if (($td.Name -notlike 't-*') -and (& $want 'S7')) {
                V 'error' 'S7' $tpath "task dir '$($td.Name)' lacks t- prefix" 'rename dir to t-<kebab>'
            }
            # S5 frontmatter on issue/task/state/log
            foreach ($leaf in @('issue.md','task.md','state.md','log.md')) {
                Audit-Frontmatter (Join-Path $tpath $leaf)
            }
            $tstate = Join-Path $tpath 'state.md'
            if (Test-Path $tstate) {
                $tfm = Read-RatmacFrontmatter $tstate
                if ((-not $tfm.ContainsKey('status') -or "$($tfm['status'])".Trim() -eq '') -and (& $want 'S5')) {
                    V 'error' 'S5' $tstate 'state.md missing status' 'add status: active|blocked|done|abandoned'
                }
                # S15/S16: maintainer mode requires an issue: tag (one active task per issue)
                if ($maintDual -and $mode -eq 'maintainer' -and (& $want 'S15')) {
                    if (-not $tfm.ContainsKey('issue') -or "$($tfm['issue'])".Trim() -eq '') {
                        V 'error' 'S15' $tstate 'maintainer-mode task missing issue: tag' 'add issue: <ticket-id> (one active task per issue, S15/S16)'
                    }
                }
                # S18: a done task must carry a ## affects section
                if ("$($tfm['status'])".ToLower() -eq 'done' -and (& $want 'S18')) {
                    $tlines = [System.Collections.ArrayList]@(Get-Content -LiteralPath $tstate)
                    if (-not (Find-RatmacSection -Lines $tlines -Name 'affects')) {
                        V 'warn' 'S18' $tstate 'done task lacks "## affects" section' 'add ## affects with the files/assets touched (frozen on done, S18)'
                    }
                }
                Audit-Fence $tstate
                Audit-DanglingTaskLinks $tstate $spath
            } elseif (& $want 'S5') {
                V 'error' 'S5' $tstate 'task state.md missing' 'scaffold task via ratmac-kickoff -Tier task'
            }
            # dangling links may also live in issue.md / task.md
            Audit-DanglingTaskLinks (Join-Path $tpath 'issue.md') $spath
            Audit-DanglingTaskLinks (Join-Path $tpath 'task.md') $spath
        }
    }
}

# --- report (mirror arca-lint table shape) ----------------------------------------
$errs  = @($violations | Where-Object { $_.severity -eq 'error' }).Count
$warns = @($violations | Where-Object { $_.severity -eq 'warn' }).Count

Write-Output "| severity | rule | path | message | fix-hint |"
Write-Output "|---|---|---|---|---|"
foreach ($v in $violations) { Write-Output "| $($v.severity) | $($v.rule) | $($v.path) | $($v.message) | $($v.fix) |" }
if ($violations.Count -eq 0) { Write-Output "| pass | — | — | no violations | — |" }
Write-Output ""
Write-Output (Write-RatmacContract @{
    'Run mode'='single'
    'Active proj'=$p.Proj
    'Files touched'='— (read-only, R11)'
    'Lint result'=$(if($errs){"$errs error, $warns warn"}elseif($warns){"$warns warn"}else{'pass'})
    'Residual risk'=$(if($Strict){'strict: per-mode layout audit run'}else{'lenient default (RQ7/a); pass -Strict for the full layout audit'})
})
exit $(if ($errs -gt 0) { 1 } else { 0 })
