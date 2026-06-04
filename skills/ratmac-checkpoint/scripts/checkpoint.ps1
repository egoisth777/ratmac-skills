# ratmac-checkpoint — snapshot pause: bump task state.md, append log.md, optional ## affects add.
# Writes only under scheduler/ (R5). Reads state first (R9).
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Task,
    [Parameter(Mandatory)][string]$Note,
    [string[]]$AddAffects,
    [ValidateSet('active','blocked')][string]$Status,
    [string]$Root,
    [string]$Proj,
    [string]$Ts
)
. "$PSScriptRoot/_common.ps1"

$stamp = Get-RatmacStamp $Ts
$p = Get-RatmacProj -Root $Root -Proj $Proj
$slice = Get-RatmacActiveSlice -ProjPath $p.Path
if (-not $slice) {
    Write-Output "BLOCKED no active slice under $($p.Proj)"
    Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Active proj'=$p.Proj; 'Blocked items'='no active slice' }); exit 2
}
$tdir = Resolve-RatmacTask -SlicePath $slice -Task $Task
if (-not $tdir) {
    Write-Output "BLOCKED task '$Task' not found in $($slice) grad/ (archived tasks use ratmac-mutate or revive)"
    Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Active proj'=$p.Proj; 'Active slice'=(Split-Path $slice -Leaf); 'Blocked items'="task '$Task' not in grad/" }); exit 2
}
$tstate = Join-Path $tdir 'state.md'
$tlog   = Join-Path $tdir 'log.md'
$touched = @()
$generated = @()

# update ## status section (first line of note) + append the cross-session note to ## scratch
$noteLines = ($Note -split "`n")
$noteFirst = $noteLines[0]
# scratch entry = the remainder past the first line if present, else the whole first line
$noteRest  = if ($noteLines.Count -gt 1) { ($noteLines[1..($noteLines.Count-1)] -join ' ').Trim() } else { '' }
$scratchEntry = if ($noteRest) { $noteRest } else { $noteFirst }
$lines = [System.Collections.ArrayList]@(Get-Content -LiteralPath $tstate)
$sec = Find-RatmacSection -Lines $lines -Name 'status'
if ($sec) {
    # replace section body (everything between heading and next heading) with the note
    for ($i=$sec.End-1; $i -gt $sec.Start; $i--) { $lines.RemoveAt($i) }
    $lines.Insert($sec.Start+1, $noteFirst)
}
# append the note to ## scratch (contract + lifecycle require status + scratch + affects).
# Mirror close.ps1's scratch handling: create the section if absent, append at its end so
# cross-session scratch context is preserved (dated detail still lands in log.md per S19).
$scr = Find-RatmacSection -Lines $lines -Name 'scratch'
if (-not $scr) {
    [void]$lines.Add(''); [void]$lines.Add('## scratch')
    $scr = Find-RatmacSection -Lines $lines -Name 'scratch'
}
$lines.Insert($scr.End, "- $stamp $scratchEntry")
# canonical LF write (R4/R10): NOT Set-Content (CRLF on Windows). The follow-up
# Set-RatmacFrontmatterValue re-normalizes too, but write LF here so the file is never
# momentarily CRLF and the scratch bullet lands identically to checkpoint.sh's awk (LF).
Set-RatmacFileLines -Path $tstate -Lines @($lines)
Set-RatmacFrontmatterValue -Path $tstate -Key 'time-modified' -Value $stamp -Ts $stamp
$touched += ($tstate -replace '\\','/')

# affects add (S18, dedupe RQ13)
# The documented `-File -AddAffects a,b` form binds a SINGLE element ('a,b', quotes
# retained when copy-pasted) instead of a real [string[]], so split every incoming
# element on commas and strip surrounding quotes before Add-RatmacAffects — mirroring
# checkpoint.sh's add_affects_push so both engines interpret the comma form identically
# (R4 parity; see defects 3/19). The engine never splits, matching Add-RatmacAffects.
$affMsg = ''
if ($AddAffects) {
    $affPaths = @($AddAffects | ForEach-Object { $_.Trim('"') -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    if ($affPaths.Count -gt 0) {
        $r = Add-RatmacAffects -StatePath $tstate -Paths $affPaths -Ts $stamp
        $affMsg = "affects +$($r.Added.Count) (dup $($r.Dup.Count))"
    }
}

# status change → frontmatter + slice table + slice log
$statusChanged = $false
if ($Status) {
    $cur = (Read-RatmacFrontmatter $tstate)['status']
    if ($cur -ne $Status) {
        Set-RatmacFrontmatterValue -Path $tstate -Key 'status' -Value $Status -Ts $stamp
        $statusChanged = $true
        $tfm = Read-RatmacFrontmatter $tstate
        Set-RatmacTaskRow -SliceStatePath (Join-Path $slice 'state.md') -Task (Split-Path $tdir -Leaf) -Issue $tfm['issue'] -Sprint $tfm['sprint'] -Status $Status -Ts $stamp
        $touched += ((Join-Path $slice 'state.md') -replace '\\','/')
        Add-RatmacLog -LogPath (Join-Path $slice 'log.md') -Verb 'task-status' -Args "$(Split-Path $tdir -Leaf) status:$Status" -Ts $stamp
        $touched += ((Join-Path $slice 'log.md') -replace '\\','/')
    }
}

# append task log line
$logArgs = $noteFirst
if ($affMsg) { $logArgs += " | $affMsg" }
Add-RatmacLog -LogPath $tlog -Verb 'checkpoint' -Args $logArgs -Ts $stamp
$touched += ($tlog -replace '\\','/')

Write-Output "checkpoint: $(Split-Path $tdir -Leaf) — $noteFirst"
if ($affMsg) { Write-Output "  $affMsg" }
if ($statusChanged) { Write-Output "  status -> $Status (slice table + log updated)" }
Write-Output (Write-RatmacContract @{
    'Run mode'='single'; 'Active proj'=$p.Proj; 'Active slice'=(Split-Path $slice -Leaf); 'Active task'=(Split-Path $tdir -Leaf)
    'Files touched'=(($touched | Select-Object -Unique) -join ', ')
    'Skill chain'='ratmac-checkpoint'
    'Next safe action'='continue work, or ratmac-close when AC met; ratmac-lint to verify'
})
