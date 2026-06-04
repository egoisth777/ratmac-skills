# ratmac-route — read-only discovery of scheduler land. "where am I?" (R-prefix: no writes).
[CmdletBinding()]
param(
    [string]$Root,
    [string]$Proj,
    [string]$Ts
)
. "$PSScriptRoot/_common.ps1"

try { $p = Get-RatmacProj -Root $Root -Proj $Proj }
catch {
    Write-Output ($_.Exception.Message)
    Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Blocked items'='no resolvable project' })
    exit 2
}
$pdir = $p.Path
$pstate = Join-Path $pdir 'state.md'
if (-not (Test-Path $pstate)) {
    Write-Output "BLOCKED proj state.md missing at $pstate"
    Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Active proj'=$p.Proj; 'Blocked items'=$pstate })
    exit 2
}
$pfm = Read-RatmacFrontmatter $pstate
$mode = $pfm['mode']

$slice = Get-RatmacActiveSlice -ProjPath $pdir
$sname = if ($slice) { Split-Path $slice -Leaf } else { '—' }

# active tasks in the active slice
$tasks = @()
if ($slice) {
    $grad = Join-Path $slice 'grad'
    if (Test-Path $grad) {
        foreach ($td in Get-ChildItem -LiteralPath $grad -Directory -Filter 't-*' -ErrorAction SilentlyContinue) {
            $tst = Join-Path $td.FullName 'state.md'
            $st = if (Test-Path $tst) { (Read-RatmacFrontmatter $tst)['status'] } else { '?' }
            $bb = if (Test-Path $tst) { @((Read-RatmacFrontmatter $tst)['blocked-by']) -join ',' } else { '' }
            $tasks += "$($td.Name) ($st$(if($bb){", blocked-by: $bb"}))"
        }
    }
}

# recent log entries (last 5 of slice log, else proj log)
function Tail($path, $n) {
    if (-not (Test-Path $path)) { return @() }
    $body = Get-Content -LiteralPath $path | Where-Object { $_ -match '^\d{4}-\d{2}-\d{2}' }
    return @($body | Select-Object -Last $n)
}
$recent = if ($slice) { Tail (Join-Path $slice 'log.md') 5 } else { Tail (Join-Path $pdir 'log.md') 5 }

# suggested next-action mode
$suggest =
    if (-not $slice) { 'new-slice' }
    elseif ($tasks.Count -eq 0) { 'new-task' }
    else { 'continue-task | new-task | scope-mutation | slice-transit' }

Write-Output "Active project: $($p.Proj)"
Write-Output "Mode: $(if($mode){$mode}else{'?'})"
Write-Output "Active slice: $sname"
Write-Output "Active tasks: [$($tasks -join '; ')]"
Write-Output "Recent log entries:"
$recent | ForEach-Object { Write-Output "  $_" }
Write-Output ""
Write-Output "Suggested next-action mode: $suggest"
Write-Output ""
Write-Output (Write-RatmacContract @{
    'Run mode'='single'
    'Active proj'=$p.Proj
    'Active slice'=$sname
    'Active task'=$(if($tasks.Count){($tasks -join '; ')}else{'—'})
    'Files touched'='— (read-only)'
    'Lint result'='not-run'
    'Next safe action'="pick a mode ($suggest); invoke the matching ratmac-* skill"
})
