# ratmac-close — task done or abandoned: freeze affects, set status, archive, regen (lifecycle "task done / abandoned").
# Writes only under scheduler/ (R5). Reads task state first (R9). Spawns ratmac-regen, never itself (R18).
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Task,
    [Parameter(Mandatory)][ValidateSet('done','abandoned')][string]$Status,
    [string]$Cl,
    [string]$Outcome,
    [string]$Goal,                       # [sole|dual] goal topic to flip current: true
    [string]$Root,
    [string]$Proj,
    [string]$Ts,
    [switch]$Force
)
. "$PSScriptRoot/_common.ps1"

$stamp = Get-RatmacStamp $Ts
$p = Get-RatmacProj -Root $Root -Proj $Proj
$slice = Get-RatmacActiveSlice -ProjPath $p.Path
if (-not $slice) {
    Write-Output "BLOCKED no active slice under $($p.Proj)"
    Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Active proj'=$p.Proj; 'Blocked items'='no active slice' }); exit 2
}
$sname = Split-Path $slice -Leaf
$tdir = Resolve-RatmacTask -SlicePath $slice -Task $Task
if (-not $tdir) {
    Write-Output "BLOCKED task '$Task' not found in $sname grad/"
    Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Active proj'=$p.Proj; 'Active slice'=$sname; 'Blocked items'="task '$Task' not in grad/" }); exit 2
}
$tname  = Split-Path $tdir -Leaf
$tstate = Join-Path $tdir 'state.md'
$tissue = Join-Path $tdir 'issue.md'
$tlog   = Join-Path $tdir 'log.md'
$mode   = Get-RatmacMode -ProjPath $p.Path
$touched = @()
$generated = @()

# --- done-only gates -------------------------------------------------------------
# The non-empty ## affects gate is data-integrity (S18): a done task with no affects
# record is permanent data loss once archived, so -Force MUST NOT bypass it (only an
# abandoned task may archive with empty affects). -Force bypasses only the softer
# AC-incomplete check.
if ($Status -eq 'done') {
    $affects = @(Get-RatmacAffectsList -Path $tstate)
    if ($affects.Count -eq 0) {
        Write-Output "BLOCKED need affects: task $tname has an empty ## affects list (status=done). Add affects via ratmac-checkpoint (status=done cannot archive empty, even with -Force)."
        Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Active proj'=$p.Proj; 'Active slice'=$sname; 'Active task'=$tname; 'Blocked items'='empty ## affects' }); exit 2
    }
    if (-not $Force -and (Test-Path $tissue)) {
        $unchecked = @(Get-Content -LiteralPath $tissue | Where-Object { $_ -match '^\s*-\s*\[\s\]' })
        if ($unchecked.Count -gt 0) {
            Write-Output "HUMAN_DECISION_REQUIRED AC incomplete: $($unchecked.Count) unchecked '- [ ]' item(s) in $tname/issue.md. Resolve them, or pass -Force to close anyway."
            Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Active proj'=$p.Proj; 'Active slice'=$sname; 'Active task'=$tname; 'Human decisions required'="$($unchecked.Count) unchecked AC item(s)" }); exit 3
        }
    }
}

# --- set status frontmatter on task state.md (lifecycle 2) -------------------------
Set-RatmacFrontmatterValue -Path $tstate -Key 'status' -Value $Status -Ts $stamp

# --- write outcome into ## scratch (replace body) ---------------------------------
if ($Outcome) {
    $lines = [System.Collections.ArrayList]@(Get-Content -LiteralPath $tstate)
    $sec = Find-RatmacSection -Lines $lines -Name 'scratch'
    if (-not $sec) {
        [void]$lines.Add(''); [void]$lines.Add('## scratch')
        $sec = Find-RatmacSection -Lines $lines -Name 'scratch'
    }
    for ($i=$sec.End-1; $i -gt $sec.Start; $i--) { $lines.RemoveAt($i) }
    $lines.Insert($sec.Start+1, $Outcome)
    # canonical LF write (R4/R10): NOT Set-Content (CRLF on Windows). The follow-up
    # Set-RatmacFrontmatterValue re-normalizes via the LF helper too, but write LF here so
    # the file is never momentarily CRLF on disk (matches close.sh's awk LF output).
    Set-RatmacFileLines -Path $tstate -Lines @($lines)
    Set-RatmacFrontmatterValue -Path $tstate -Key 'time-modified' -Value $stamp -Ts $stamp
}
$touched += ($tstate -replace '\\','/')

# --- task log line (lifecycle 3) --------------------------------------------------
$tlogArgs = if ($Status -eq 'done') { "cl:$(if($Cl){$Cl}else{'—'})" } else { "reason:$(if($Outcome){$Outcome}else{'—'})" }
Add-RatmacLog -LogPath $tlog -Verb "status:$Status" -Args $tlogArgs -Ts $stamp
$touched += ($tlog -replace '\\','/')

# --- slice log line (lifecycle 4) -------------------------------------------------
$slog = Join-Path $slice 'log.md'
Add-RatmacLog -LogPath $slog -Verb 'close-task' -Args "$tname status:$Status" -Ts $stamp
$touched += ($slog -replace '\\','/')

# --- [sole|dual] flip goal item current: true (lifecycle 5) -----------------------
$goalFlipped = $false
if ($Goal -and $mode -in @('sole','dual')) {
    $goalName = ($Goal -replace '\\','/').Split('/')[-1] -replace '\.md$',''
    $goalFile = Join-Path $p.Path "goal/$goalName.md"
    if (Test-Path $goalFile) {
        Set-RatmacFrontmatterValue -Path $goalFile -Key 'current' -Value 'true' -Ts $stamp
        $touched += ($goalFile -replace '\\','/')
        $goalFlipped = $true
    } else {
        Write-Output "  note: goal item '$goalName' not found at goal/$goalName.md — skipping current flip"
    }
}

# --- read slice-row frontmatter BEFORE the destructive move (R9) ------------------
# Read issue/sprint into locals from the pre-move state.md so a degenerate frontmatter
# can never throw AFTER Move-Item has already archived the dir (which would leave the
# slice row un-flipped and regen never spawned — a half-archived non-rollback state).
$afm = Read-RatmacFrontmatter $tstate
$rowIssue  = $afm['issue']
$rowSprint = $afm['sprint']

# --- mv grad/<t> -> <slice>/archive/<t> (lifecycle 9) -----------------------------
$archiveDir = Join-Path $slice 'archive'
if (-not (Test-Path $archiveDir)) { New-Item -ItemType Directory -Force -Path $archiveDir | Out-Null }
$dest = Join-Path $archiveDir $tname
if (Test-Path $dest) {
    Write-Output "BLOCKED archive collision: $dest already exists; cannot move $tname"
    Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Active proj'=$p.Proj; 'Active slice'=$sname; 'Active task'=$tname; 'Blocked items'="archive/$tname exists" }); exit 2
}
Move-Item -LiteralPath $tdir -Destination $dest
$tstate = Join-Path $dest 'state.md'   # re-point post-move (not re-read, just for record)

# --- slice table row -> status (lifecycle 10) -------------------------------------
$sstate = Join-Path $slice 'state.md'
Set-RatmacTaskRow -SliceStatePath $sstate -Task $tname -Issue $rowIssue -Sprint $rowSprint -Status $Status -Ts $stamp
$touched += ($sstate -replace '\\','/')

# --- trigger regen (lifecycle 6/7/8): spawn sibling skill, never self (R18) -------
# Forward the resolved $stamp (not the raw -Ts, which may be empty) so the spawned
# regen stamps identically. Surface the spawned regen's exit code: a non-zero regen
# means the ## affects rollups are stale, which the receipt must NOT hide.
$regenScript = Join-Path (Split-Path $PSScriptRoot -Parent) '..' 'ratmac-regen/scripts/regen.ps1'
$regenResult = 'not run'
if (Test-Path $regenScript) {
    $regenArgs = @('-NoProfile','-File',$regenScript,'-Ts',$stamp)
    if ($Root) { $regenArgs += @('-Root',$Root) }
    if ($Proj) { $regenArgs += @('-Proj',$Proj) }
    & pwsh @regenArgs | Out-Null
    if ($LASTEXITCODE -eq 0) { $regenResult = 'regen spawned' }
    else { $regenResult = "FAILED (regen exit $LASTEXITCODE; rollup stale)" }
}

Write-Output "close: $tname status:$Status -> archived under $sname/archive/"
if ($goalFlipped) { Write-Output "  goal '$Goal' flipped current: true" }
Write-Output (Write-RatmacContract @{
    'Run mode'='single'; 'Active proj'=$p.Proj; 'Active slice'=$sname; 'Active task'=$tname
    'Classification'="close-task:$Status"
    'Skill chain'='ratmac-close -> ratmac-regen'
    'Files touched'=(($touched | Select-Object -Unique) -join ', ')
    'Regen result'=$regenResult
    'Next safe action'='ratmac-lint to verify post-archive'
})
