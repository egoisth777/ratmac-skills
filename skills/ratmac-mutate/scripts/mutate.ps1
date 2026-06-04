# ratmac-mutate — in-place plan/approach/ticket revision (S15, S16). One task per issue; revise, never fork.
# Writes only under scheduler/ (R5). Reads state first (R9).
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Task,
    [Parameter(Mandatory)][ValidateSet('plan','approach','ticket')][string]$Kind,
    [Parameter(Mandatory)][string]$Reason,
    [string]$Diff,          # path to replacement task.md (plan/approach) or appended ticket text
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
$tdir = Resolve-RatmacTask -SlicePath $slice -Task $Task
if (-not $tdir) {
    Write-Output "BLOCKED task '$Task' not found in grad/"
    Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Active proj'=$p.Proj; 'Blocked items'="task '$Task' not in grad/" }); exit 2
}
$taskMd  = Join-Path $tdir 'task.md'
$issueMd = Join-Path $tdir 'issue.md'
$stateMd = Join-Path $tdir 'state.md'
$logMd   = Join-Path $tdir 'log.md'
$touched = @()

switch ($Kind) {
  { $_ -in @('plan','approach') } {
    # S15 stop: task.md newer than state.md => likely already revised by hand
    if (-not $Force -and (Test-Path $taskMd) -and (Test-Path $stateMd)) {
        $tFm = Read-RatmacFrontmatter $taskMd
        $sFm = Read-RatmacFrontmatter $stateMd
        if ($tFm['time-modified'] -and $sFm['time-modified'] -and ($tFm['time-modified'] -gt $sFm['time-modified'])) {
            Write-Output "HUMAN_DECISION_REQUIRED task.md is newer than state.md — likely already revised manually (S15). Pass -Force to override."
            Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Active proj'=$p.Proj; 'Active task'=(Split-Path $tdir -Leaf); 'Human decisions required'='confirm in-place revise vs manual edit' }); exit 3
        }
    }
    if ($Diff) {
        if (-not (Test-Path $Diff)) {
            Write-Output "BLOCKED -Diff path '$Diff' not found"
            Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Blocked items'=$Diff }); exit 2
        }
        $new = Get-Content -LiteralPath $Diff -Raw
        # canonical LF write (R4/R10): NOT Set-Content (CRLF on Windows). Normalize CRLF in
        # the supplied diff and drop the single trailing newline before splitting so the
        # helper re-adds exactly one LF, matching mutate.sh's `cat "$DIFF" > "$TASK_MD"`.
        $newBody = ($new -replace "`r`n","`n")
        if ($newBody.EndsWith("`n")) { $newBody = $newBody.Substring(0, $newBody.Length - 1) }
        Set-RatmacFileLines -Path $taskMd -Lines @($newBody -split "`n")
        Set-RatmacFrontmatterValue -Path $taskMd -Key 'time-modified' -Value $stamp -Ts $stamp
    } else {
        # no diff supplied: just bump time-modified; agent edits task.md body separately
        if (Test-Path $taskMd) { Set-RatmacFrontmatterValue -Path $taskMd -Key 'time-modified' -Value $stamp -Ts $stamp }
    }
    $touched += ($taskMd -replace '\\','/')
    Add-RatmacLog -LogPath $logMd -Verb 'replan' -Args $Reason -Ts $stamp
    $touched += ($logMd -replace '\\','/')
    Write-Output "mutate ${Kind}: $(Split-Path $tdir -Leaf) — $Reason"
  }

  'ticket' {
    # append a ## ticket updates block to issue.md (S16)
    $upd = if ($Diff -and (Test-Path $Diff)) { Get-Content -LiteralPath $Diff -Raw } else { $Reason }
    $lines = [System.Collections.ArrayList]@(Get-Content -LiteralPath $issueMd)
    $sec = Find-RatmacSection -Lines $lines -Name 'ticket updates'
    $entry = "- $stamp — $upd"
    if ($sec) {
        $lines.Insert($sec.End, $entry)
    } else {
        [void]$lines.Add(''); [void]$lines.Add('## ticket updates'); [void]$lines.Add($entry)
    }
    # canonical LF write (R4/R10): NOT Set-Content (CRLF on Windows). The follow-up
    # Set-RatmacFrontmatterValue re-normalizes too, but write LF here so the file is never
    # momentarily CRLF on disk (matches mutate.sh's awk / printf LF output).
    Set-RatmacFileLines -Path $issueMd -Lines @($lines)
    Set-RatmacFrontmatterValue -Path $issueMd -Key 'time-modified' -Value $stamp -Ts $stamp
    $touched += ($issueMd -replace '\\','/')
    Add-RatmacLog -LogPath $logMd -Verb 'ticket-update' -Args $Reason -Ts $stamp
    $touched += ($logMd -replace '\\','/')
    Write-Output "mutate ticket: $(Split-Path $tdir -Leaf) — $Reason"
  }
}

Write-Output (Write-RatmacContract @{
    'Run mode'='single'; 'Active proj'=$p.Proj; 'Active slice'=(Split-Path $slice -Leaf); 'Active task'=(Split-Path $tdir -Leaf)
    'Files touched'=(($touched | Select-Object -Unique) -join ', ')
    'Skill chain'='ratmac-mutate'
    'Next safe action'='update task state.md via ratmac-checkpoint; ratmac-lint'
})
