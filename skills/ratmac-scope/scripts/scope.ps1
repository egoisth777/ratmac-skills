# ratmac-scope — sole/dual scope expand/contract mid-slice: edit scope.md + scope-history.md + log, then regen.
# Writes only under scheduler/ (R5). Reads slice/proj state first (R9). Spawns ratmac-regen, never itself (R18).
# All STOPs (R12) fire BEFORE any write so an ambiguous scope mutation never half-applies.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('+','-')][string]$Op,
    [Parameter(Mandatory)][string]$Ref,          # goal topic (bare name; '.md' / path tail tolerated)
    [string]$Reason,
    [switch]$CreateGoal,                          # -Op + : scaffold goal/<ref>.md if missing
    [string]$Slice,                               # optional explicit slice ref; default = active slice
    [string]$Root,
    [string]$Proj,
    [string]$Ts
)
. "$PSScriptRoot/_common.ps1"

$stamp = Get-RatmacStamp $Ts
$date  = ($stamp -split '-')[0..2] -join '-'      # YYYY-MM-DD slice of the stamp (S14 history line)
$p = Get-RatmacProj -Root $Root -Proj $Proj
$pdir = $p.Path
$mode = Get-RatmacMode -ProjPath $pdir

# --- STOP: maintainer mode has no scope (contract stop-rule) -----------------------
if ($mode -eq 'maintainer') {
    Write-Output "BLOCKED maintainer mode has no scope (scope.md/scope-history.md exist only in sole|dual)"
    Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Active proj'=$p.Proj; 'Blocked items'='maintainer mode has no scope' }); exit 2
}

# --- resolve slice -----------------------------------------------------------------
if ($Slice) {
    $sname = if ($Slice -match '^s-') { $Slice } else { "s-$Slice" }
    $slice = Join-Path $pdir $sname
    if (-not (Test-Path $slice)) {
        Write-Output "BLOCKED slice '$sname' not found under $($p.Proj)"
        Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Active proj'=$p.Proj; 'Blocked items'="slice '$sname' missing" }); exit 2
    }
} else {
    $slice = Get-RatmacActiveSlice -ProjPath $pdir
    if (-not $slice) {
        Write-Output "BLOCKED no active slice under $($p.Proj)"
        Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Active proj'=$p.Proj; 'Blocked items'='no active slice' }); exit 2
    }
    $sname = Split-Path $slice -Leaf
}

$scope = Join-Path $slice 'scope.md'
$hist  = Join-Path $slice 'scope-history.md'
$slog  = Join-Path $slice 'log.md'
if (-not (Test-Path $scope)) {
    Write-Output "BLOCKED scope.md missing in $sname (slice not sole/dual-scoped); kickoff the slice under a sole|dual proj"
    Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Active proj'=$p.Proj; 'Active slice'=$sname; 'Blocked items'='scope.md missing' }); exit 2
}

# --- normalize the goal ref --------------------------------------------------------
$topic = ($Ref -replace '\\','/').Split('/')[-1] -replace '\.md$',''
$goalDir  = Join-Path $pdir 'goal'
$goalFile = Join-Path $goalDir "$topic.md"
$touched = @()
$generated = @()
$goalCreated = $false

# --- STOP / scaffold: -Op + on a missing goal item (contract stop-rule) ------------
if ($Op -eq '+' -and -not (Test-Path $goalFile)) {
    if (-not $CreateGoal) {
        Write-Output "HUMAN_DECISION_REQUIRED goal item missing: goal/$topic.md does not exist. Pass -CreateGoal to scaffold it, or create the goal item first."
        Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Active proj'=$p.Proj; 'Active slice'=$sname; 'Human decisions required'="goal/$topic.md missing — pass -CreateGoal" }); exit 3
    }
    # scaffold goal/<topic>.md from the goal-topic template (current: false; goal is SSoT, S12)
    $tpl = Join-Path (Split-Path $PSScriptRoot -Parent) '..' 'ratmac-kickoff/templates/goal-topic.md.tpl'
    $problem = if ($Reason) { $Reason } else { "TODO: describe goal $topic" }
    $body = Expand-RatmacTemplate -Path $tpl -Vars @{ STAMP=$stamp; NAME=$topic; PROBLEM=$problem }
    New-RatmacParentDir $goalFile
    # canonical LF write (R4/R10): NOT Set-Content (CRLF on Windows). Normalize CRLF and drop
    # the single trailing newline before splitting so the helper re-adds exactly one LF —
    # matching scope.sh's `printf '%s\n'` (aligned with kickoff.sh emit, see defect 6).
    $goalBody = ($body -replace "`r`n","`n")
    if ($goalBody.EndsWith("`n")) { $goalBody = $goalBody.Substring(0, $goalBody.Length - 1) }
    Set-RatmacFileLines -Path $goalFile -Lines @($goalBody -split "`n")
    $touched += ($goalFile -replace '\\','/')
    $goalCreated = $true
}
# --- STOP: -Op - on a ref that scope.md does not carry -----------------------------
if ($Op -eq '-' -and -not ((Get-Content -LiteralPath $scope -Raw) -match "\[\[(?:[^\]\|]*/)?$([regex]::Escape($topic))(?:\||\])")) {
    Write-Output "BLOCKED scope contract: '$topic' is not in $sname/scope.md (nothing to remove)"
    Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Active proj'=$p.Proj; 'Active slice'=$sname; 'Blocked items'="'$topic' not in scope" }); exit 2
}

# --- edit scope.md: add/remove the [[<topic>]] ref (regen scans these wikilinks) ---
$lines = [System.Collections.ArrayList]@(Get-Content -LiteralPath $scope)
$bullet = "- [[$topic]]"
$already = $false
$existingIdx = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match "\[\[(?:[^\]\|]*/)?$([regex]::Escape($topic))(?:\||\])") { $existingIdx = $i; $already = $true; break }
}
$scopeChanged = $false
if ($Op -eq '+') {
    if (-not $already) {
        # append the ref bullet after the last non-blank body line
        $insAt = $lines.Count
        while ($insAt -gt 0 -and $lines[$insAt-1].Trim() -eq '') { $insAt-- }
        $lines.Insert($insAt, $bullet)
        $scopeChanged = $true
    }
} else {
    if ($existingIdx -ge 0) { $lines.RemoveAt($existingIdx); $scopeChanged = $true }
}
if ($scopeChanged) {
    # canonical LF write (R4/R10): NOT Set-Content (CRLF on Windows). Follow-up fm-set
    # re-normalizes too, but write LF here so the file is never momentarily CRLF on disk.
    Set-RatmacFileLines -Path $scope -Lines @($lines)
    Set-RatmacFrontmatterValue -Path $scope -Key 'time-modified' -Value $stamp -Ts $stamp
    $touched += ($scope -replace '\\','/')
}

# --- append-only scope-history.md line (S14): "+/- <ref> <reason> <YYYY-MM-DD>" -----
$reasonText = if ($Reason) { $Reason } else { '—' }
$histLine = "$Op $topic $reasonText $date"
if (-not (Test-Path $hist)) {
    New-RatmacParentDir $hist
    # canonical LF write (R4/R10): NOT Set-Content (CRLF on Windows) — matches scope.sh's
    # printf create. Without this the freshly-created scope-history.md diverges byte-for-byte.
    Set-RatmacFileLines -Path $hist -Lines @("---","time-created: $stamp","time-modified: $stamp","---","","# scope-history — $sname","",$histLine)
} else {
    # canonical LF append (R4/R10): NOT Add-Content (CRLF on Windows) — matches scope.sh's
    # `printf '%s\n'` append.
    Add-RatmacFileLine -Path $hist -Line $histLine
    Set-RatmacFrontmatterValue -Path $hist -Key 'time-modified' -Value $stamp -Ts $stamp
}
$touched += ($hist -replace '\\','/')

# --- slice log line (S19): "<ts> scope+|- <ref>" -----------------------------------
Add-RatmacLog -LogPath $slog -Verb "scope$Op" -Args $topic -Ts $stamp
$touched += ($slog -replace '\\','/')

# --- post: trigger regen so scope-residual.md + goal-residual.md refresh (R18) -----
$regenPs = Join-Path (Split-Path $PSScriptRoot -Parent) '..' 'ratmac-regen/scripts/regen.ps1'
$regenResult = 'not run'
if (Test-Path $regenPs) {
    $regenArgs = @('-NoProfile','-File',$regenPs)
    if ($Root) { $regenArgs += @('-Root',$Root) }
    if ($Proj) { $regenArgs += @('-Proj',$Proj) }
    if ($Ts)   { $regenArgs += @('-Ts',$Ts) }
    & pwsh @regenArgs | Out-Null
    if ($LASTEXITCODE -eq 0) { $regenResult = 'regen spawned' }
    else { $regenResult = "FAILED (regen exit $LASTEXITCODE; rollup stale)" }
}

$verb = if ($Op -eq '+') { 'scope+' } else { 'scope-' }
Write-Output "$verb $topic in $sname$(if($goalCreated){' (goal item scaffolded, current: false)'}else{''})"
if (-not $scopeChanged -and $Op -eq '+') { Write-Output "  note: '$topic' already in scope (no-op add)" }
Write-Output (Write-RatmacContract @{
    'Run mode'='single'; 'Active proj'=$p.Proj; 'Active slice'=$sname
    'Classification'="scope-mutation:$Op"
    'Skill chain'='ratmac-scope -> ratmac-regen'
    'Files touched'=(($touched | Select-Object -Unique) -join ', ')
    'Regen result'=$regenResult
    'Next safe action'='ratmac-lint to verify scope/residual consistency'
})
