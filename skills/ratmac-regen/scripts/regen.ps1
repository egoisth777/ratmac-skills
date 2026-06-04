# ratmac-regen — rebuild GENERATED content from source-of-truth (S13, S20). Idempotent (R10).
# Rebuilds: goal-residual / scope-residual / issues-residual (whole-file, S13) and the fenced
# ## affects rollups in slice + proj state.md (S20). Only generated regions are touched (R6).
[CmdletBinding()]
param(
    [string]$Root,
    [string]$Proj,
    [ValidateSet('all','proj','slice')][string]$Tier = 'all',
    [string]$Ts
)
. "$PSScriptRoot/_common.ps1"

$stamp = Get-RatmacStamp $Ts
$p = Get-RatmacProj -Root $Root -Proj $Proj
$pdir = $p.Path
$mode = Get-RatmacMode -ProjPath $pdir
$generated = @()
$rebuilt = 0

# --- whole-file residual writer (S13: GENERATED sentinel on line 1) ---------------
# Trailing-newline parity with regen.sh write_residual: the blank line after the
# "# <title>" header is emitted ONLY when the body is non-empty. An empty body leaves
# the header as the final content line (matching the sh path's "append body only if
# non-empty"), so both engines produce byte-identical empty-input residuals (R10/S13).
function Write-Residual($path, $title, $bodyLines) {
    $header = @('<!-- GENERATED — do not edit -->','---',"time-created: $stamp","time-modified: $stamp",'---','',"# $title")
    $body = @($bodyLines)
    if ($body.Count -gt 0) { $new = $header + @('') + $body }
    else { $new = $header }
    $old = if (Test-Path $path) { Get-Content -LiteralPath $path } else { @() }
    # compare ignoring the time-modified line (so stable input => stable result, R10)
    $strip = { param($a) ($a | Where-Object { $_ -notmatch '^time-(created|modified):' }) -join "`n" }
    if ((& $strip $old) -eq (& $strip $new)) { return $false }
    # preserve original time-created if present
    if (Test-Path $path) {
        $oldFm = Read-RatmacFrontmatter $path
        if ($oldFm['time-created']) {
            for ($i=0; $i -lt $new.Count; $i++) { if ($new[$i] -match '^time-created:') { $new[$i] = "time-created: $($oldFm['time-created'])"; break } }
        }
    }
    New-RatmacParentDir $path
    # write through the canonical LF / UTF-8-no-BOM helper, NOT Set-Content: pwsh Set-Content
    # emits CRLF on Windows, which diverges byte-for-byte from regen.sh's LF residuals and breaks
    # R4 cross-engine parity + R10 byte-idempotence (the fenced state.md path already uses this
    # helper for the same reason — see _common.ps1 Set-RatmacFileLines).
    Set-RatmacFileLines -Path $path -Lines @($new)
    return $true
}

# --- [sole|dual] goal-residual: goal items where current: false -------------------
if ($mode -in @('sole','dual')) {
    $goalDir = Join-Path $pdir 'goal'
    $pending = @()
    if (Test-Path $goalDir) {
        foreach ($g in Get-ChildItem -LiteralPath $goalDir -Filter '*.md' -File | Sort-Object Name) {
            $fm = Read-RatmacFrontmatter $g.FullName
            if ("$($fm['current'])".ToLower() -ne 'true') { $pending += "- [[/$(Split-Path $pdir -Leaf)/goal/$($g.BaseName)|$($g.BaseName)]]" }
        }
    }
    $gr = Join-Path $pdir 'goal-residual.md'
    if (Write-Residual $gr 'goal-residual (goal − current)' $pending) { $rebuilt++; $generated += ($gr -replace '\\','/') }
}

# --- per-slice residuals + fenced affects rollup ----------------------------------
$sliceRollups = @{}   # slice-name -> union of affects (for proj rollup)
foreach ($sdir in Get-ChildItem -LiteralPath $pdir -Directory -Filter 's-*' -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'archive' }) {
    $sname = $sdir.Name
    # union of ## affects from archived tasks (frozen lists, S18)
    $aff = [System.Collections.Generic.List[string]]::new()
    $arch = Join-Path $sdir.FullName 'archive'
    foreach ($td in @(Get-ChildItem -LiteralPath $arch -Directory -Filter 't-*' -ErrorAction SilentlyContinue)) {
        foreach ($a in (Get-RatmacAffectsList -Path (Join-Path $td.FullName 'state.md'))) { if (-not $aff.Contains($a)) { $aff.Add($a) } }
    }
    # also include in-flight grad task affects (live view)
    $grad = Join-Path $sdir.FullName 'grad'
    foreach ($td in @(Get-ChildItem -LiteralPath $grad -Directory -Filter 't-*' -ErrorAction SilentlyContinue)) {
        foreach ($a in (Get-RatmacAffectsList -Path (Join-Path $td.FullName 'state.md'))) { if (-not $aff.Contains($a)) { $aff.Add($a) } }
    }
    # ordinal (byte-order) sort to match regen.sh's LC_ALL=C sort -u — otherwise the two
    # engines emit the same set in different collation and churn each other's GENERATED
    # region forever, breaking the hash-stable drift signal (R6/R10/S20). $aff is already
    # deduped via .Contains during accumulation.
    $aff.Sort([System.StringComparer]::Ordinal)
    $sorted = @($aff)
    $sliceRollups[$sname] = $sorted
    $body = @($sorted | ForEach-Object { "- $_" })
    $sstate = Join-Path $sdir.FullName 'state.md'
    if (Test-Path $sstate) {
        if (Set-RatmacFence -Path $sstate -Body $body -Section 'affects' -Ts $stamp) { $rebuilt++; $generated += ($sstate -replace '\\','/') }
    }

    # [sole|dual] scope-residual: scope refs whose goal item is still current:false
    if ($mode -in @('sole','dual')) {
        $scope = Join-Path $sdir.FullName 'scope.md'
        $refs = @()
        if (Test-Path $scope) {
            foreach ($m in [regex]::Matches((Get-Content -LiteralPath $scope -Raw), '\[\[([^\]\|]+)')) {
                $refs += (($m.Groups[1].Value -split '/')[-1])
            }
        }
        $goalDir = Join-Path $pdir 'goal'
        $resid = @()
        foreach ($r in $refs) {
            $gf = Join-Path $goalDir "$r.md"
            if (Test-Path $gf) {
                $fm = Read-RatmacFrontmatter $gf
                if ("$($fm['current'])".ToLower() -ne 'true') { $resid += "- [[/$(Split-Path $pdir -Leaf)/goal/$r|$r]]" }
            } else { $resid += "- $r (goal item missing)" }
        }
        $sr = Join-Path $sdir.FullName 'scope-residual.md'
        if (Write-Residual $sr "scope-residual — $sname (scope − current)" $resid) { $rebuilt++; $generated += ($sr -replace '\\','/') }
    }

    # [maintainer|dual] issues-residual: open issue tags on grad tasks
    if ($mode -in @('maintainer','dual')) {
        $open = @()
        foreach ($td in @(Get-ChildItem -LiteralPath $grad -Directory -Filter 't-*' -ErrorAction SilentlyContinue)) {
            $fm = Read-RatmacFrontmatter (Join-Path $td.FullName 'state.md')
            if ($fm['issue'] -and $fm['status'] -ne 'done') { $open += "- $($fm['issue']) — [[$($td.Name)]] ($($fm['status']))" }
        }
        $ir = Join-Path $sdir.FullName 'issues-residual.md'
        if (Write-Residual $ir "issues-residual — $sname (open assigned issues)" $open) { $rebuilt++; $generated += ($ir -replace '\\','/') }
    }
}

# --- proj fenced affects rollup (union of LIVE slice rollups + ARCHIVED slices) ---
# Lifecycle step-7 durability (defect 2): the proj ## affects rollup is a CUMULATIVE record.
# transit freezes the closing slice's affects into the proj rollup via a regen-before-mv, but
# a later standalone regen rebuilds the proj rollup from live slices only and would ERASE the
# archived contribution — destroying the proj-level deliverable record on the next regen in a
# new slice. So fold each <proj>/archive/s-*/state.md's already-frozen ## affects rollup into
# the union too. (The archived slice's fenced rollup is read via Get-RatmacAffectsList, which
# skips the GENERATED markers and returns its bullets — the frozen union of that slice's tasks.)
if ($Tier -in @('all','proj')) {
    $pAff = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $sliceRollups.Keys) { foreach ($a in $sliceRollups[$k]) { if (-not $pAff.Contains($a)) { $pAff.Add($a) } } }
    $projArchive = Join-Path $pdir 'archive'
    foreach ($asd in @(Get-ChildItem -LiteralPath $projArchive -Directory -Filter 's-*' -ErrorAction SilentlyContinue)) {
        foreach ($a in (Get-RatmacAffectsList -Path (Join-Path $asd.FullName 'state.md'))) { if (-not $pAff.Contains($a)) { $pAff.Add($a) } }
    }
    # ordinal (byte-order) sort to match regen.sh's LC_ALL=C sort -u (see slice rollup note).
    $pAff.Sort([System.StringComparer]::Ordinal)
    $body = @(@($pAff) | ForEach-Object { "- $_" })
    $pstate = Join-Path $pdir 'state.md'
    if (Test-Path $pstate) {
        if (Set-RatmacFence -Path $pstate -Body $body -Section 'affects' -Ts $stamp) { $rebuilt++; $generated += ($pstate -replace '\\','/') }
    }
}

Write-Output "regen: $rebuilt generated region(s) rebuilt"
Write-Output (Write-RatmacContract @{
    'Run mode'='single'; 'Active proj'=$p.Proj
    'Files generated'=($generated -join ', ')
    'Regen result'=$(if($rebuilt -eq 0){'hash-stable (no drift)'}else{"$rebuilt regions rebuilt"})
    'Next safe action'='ratmac-lint to verify'
})
