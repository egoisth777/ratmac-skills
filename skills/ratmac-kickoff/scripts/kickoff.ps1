# ratmac-kickoff — scaffold a proj | slice | task tier with required files (S2, S3, layout).
# Writes only under scheduler/ (R5). Reads parent state before writing (R9).
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('proj','slice','task')][string]$Tier,
    [Parameter(Mandatory)][string]$Name,
    # proj-only
    [ValidateSet('maintainer','sole','dual')][string]$Mode,
    [string]$Role,
    # task-only
    [string]$Issue,
    [string]$Sprint,
    [string]$BlockedBy,
    [string]$Problem,
    # common
    [string]$Root,
    [string]$Proj,
    [string]$Ts,
    [switch]$Force
)
. "$PSScriptRoot/_common.ps1"

$stamp = Get-RatmacStamp $Ts
$tplDir = Get-RatmacTemplateDir
$touched = @()

function Tpl($n,$vars) { Expand-RatmacTemplate -Path (Join-Path $tplDir $n) -Vars $vars }
function Emit($cond,$path,$content) {
    if ((Test-Path $path) -and -not $Force) { return $false }
    New-RatmacParentDir $path
    # canonical LF / UTF-8-no-BOM write (R4/R10): NOT Set-Content (which emits CRLF on
    # Windows and appends its own terminator, diverging byte-for-byte from kickoff.sh's
    # printf '%s\n'). Normalize any CRLF in the template, drop the single trailing newline
    # the template carries (the sh emit() strips it via $()), then split to lines so the
    # helper re-adds exactly one trailing LF — matching the sh side byte-for-byte.
    $body = ($content -replace "`r`n","`n")
    if ($body.EndsWith("`n")) { $body = $body.Substring(0, $body.Length - 1) }
    Set-RatmacFileLines -Path $path -Lines @($body -split "`n")
    $script:touched += ($path -replace '\\','/')
    return $true
}

switch ($Tier) {

  'proj' {
    if (-not $Mode) {
        Write-Output "HUMAN_DECISION_REQUIRED proj kickoff needs -Mode (maintainer|sole|dual)"
        Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Human decisions required'='pick -Mode' }); exit 3
    }
    $sched = Get-RatmacRoot -Root $Root
    $name = if ($Name -match '^p-') { $Name } else { "p-$Name" }
    $pdir = Join-Path $sched $name
    if ((Test-Path $pdir) -and -not $Force) {
        Write-Output "BLOCKED project '$name' already exists at $pdir (use -Force)"
        Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Blocked items'=$pdir }); exit 2
    }
    $roleText = if ($Role) { $Role } else { "TODO: describe $name direction" }
    Emit $true (Join-Path $pdir 'state.md') (Tpl 'proj-state.md.tpl' @{ STAMP=$stamp; NAME=$name; MODE=$Mode; ROLE=$roleText; SLICE='—' }) | Out-Null
    Emit $true (Join-Path $pdir 'log.md')   (Tpl 'proj-log.md.tpl'   @{ STAMP=$stamp; NAME=$name; MODE=$Mode }) | Out-Null
    # [sole|dual] goal dir is SSoT for deliverables (S12)
    if ($Mode -in @('sole','dual')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $pdir 'goal') | Out-Null
    }
    Write-Output "kickoff proj: $name (mode $Mode)"
    Write-Output (Write-RatmacContract @{
        'Run mode'='single'; 'Active proj'=$name
        'Files touched'=($touched -join ', ')
        'Skill chain'='ratmac-kickoff'
        'Next safe action'='ratmac-kickoff -Tier slice -Name <s-...>; then ratmac-lint'
    })
  }

  'slice' {
    $p = Get-RatmacProj -Root $Root -Proj $Proj
    $pdir = $p.Path
    $name = if ($Name -match '^s-') { $Name } else { "s-$Name" }
    $sdir = Join-Path $pdir $name
    if ((Test-Path $sdir) -and -not $Force) {
        Write-Output "BLOCKED slice '$name' already exists at $sdir (use -Force)"
        Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Active proj'=$p.Proj; 'Blocked items'=$sdir }); exit 2
    }
    $mode = Get-RatmacMode -ProjPath $pdir
    Emit $true (Join-Path $sdir 'state.md') (Tpl 'slice-state.md.tpl' @{ STAMP=$stamp; NAME=$name }) | Out-Null
    Emit $true (Join-Path $sdir 'log.md')   (Tpl 'slice-log.md.tpl'   @{ STAMP=$stamp; NAME=$name }) | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $sdir 'grad') | Out-Null
    # [sole|dual] scope files (S12, S14)
    if ($mode -in @('sole','dual')) {
        Emit $true (Join-Path $sdir 'scope.md')         (Tpl 'scope.md.tpl'         @{ STAMP=$stamp; NAME=$name }) | Out-Null
        Emit $true (Join-Path $sdir 'scope-history.md') (Tpl 'scope-history.md.tpl' @{ STAMP=$stamp; NAME=$name }) | Out-Null
    }
    # update proj state active-slice pointer + log
    $pstate = Join-Path $pdir 'state.md'
    if (Test-Path $pstate) {
        $lines = [System.Collections.ArrayList]@(Get-Content -LiteralPath $pstate)
        $sec = Find-RatmacSection -Lines $lines -Name 'scratch'
        if (-not $sec) {
            # no ## scratch section: append one with the pointer so the active-slice pointer is
            # ALWAYS set (parity with kickoff.sh, which now appends a scratch section + pointer
            # in the no-scratch case rather than silently doing nothing — see defect 22).
            [void]$lines.Add(''); [void]$lines.Add('## scratch')
            $sec = Find-RatmacSection -Lines $lines -Name 'scratch'
        }
        $set = $false
        for ($i=$sec.Start+1; $i -lt $sec.End; $i++) {
            if ($lines[$i] -match '^active slice:') { $lines[$i] = "active slice: $name"; $set=$true; break }
        }
        if (-not $set) { $lines.Insert($sec.Start+1, "active slice: $name") }
        # canonical LF write (R4/R10): NOT Set-Content (CRLF on Windows). The follow-up
        # Set-RatmacFrontmatterValue already rewrites via the LF helper, but route this
        # write through it too so the file is never momentarily CRLF on disk.
        Set-RatmacFileLines -Path $pstate -Lines @($lines)
        Set-RatmacFrontmatterValue -Path $pstate -Key 'time-modified' -Value $stamp -Ts $stamp
        $touched += ($pstate -replace '\\','/')
    }
    Add-RatmacLog -LogPath (Join-Path $pdir 'log.md') -Verb 'active-slice' -Args $name -Ts $stamp
    $touched += ((Join-Path $pdir 'log.md') -replace '\\','/')
    Write-Output "kickoff slice: $name under $($p.Proj)"
    Write-Output (Write-RatmacContract @{
        'Run mode'='single'; 'Active proj'=$p.Proj; 'Active slice'=$name
        'Files touched'=(($touched | Select-Object -Unique) -join ', ')
        'Skill chain'='ratmac-kickoff'
        'Next safe action'='ratmac-kickoff -Tier task -Name <t-...>; then ratmac-lint'
    })
  }

  'task' {
    $p = Get-RatmacProj -Root $Root -Proj $Proj
    $pdir = $p.Path
    $slice = Get-RatmacActiveSlice -ProjPath $pdir
    if (-not $slice) {
        Write-Output "BLOCKED no active slice under $($p.Proj); kickoff a slice first"
        Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Active proj'=$p.Proj; 'Blocked items'='no active slice' }); exit 2
    }
    $sname = Split-Path $slice -Leaf
    $mode = Get-RatmacMode -ProjPath $pdir
    # S15: maintainer mode requires an issue tag
    if ($mode -eq 'maintainer' -and -not $Issue) {
        Write-Output "BLOCKED maintainer mode requires -Issue <ticket-id> (S15)"
        Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Active proj'=$p.Proj; 'Active slice'=$sname; 'Blocked items'='missing -Issue' }); exit 2
    }
    $name = if ($Name -match '^t-') { $Name } else { "t-$Name" }
    $tdir = Join-Path $slice "grad/$name"
    if ((Test-Path $tdir) -and -not $Force) {
        Write-Output "BLOCKED task '$name' already exists at $tdir (use -Force)"
        Write-Output (Write-RatmacContract @{ 'Run mode'='single'; 'Active proj'=$p.Proj; 'Active slice'=$sname; 'Blocked items'=$tdir }); exit 2
    }
    $problem = if ($Problem) { $Problem } else { "TODO: state the problem" }
    Emit $true (Join-Path $tdir 'issue.md') (Tpl 'task-issue.md.tpl' @{ STAMP=$stamp; NAME=$name; PROBLEM=$problem }) | Out-Null
    Emit $true (Join-Path $tdir 'task.md')  (Tpl 'task-task.md.tpl'  @{ STAMP=$stamp; NAME=$name }) | Out-Null
    Emit $true (Join-Path $tdir 'state.md') (Tpl 'task-state.md.tpl' @{ STAMP=$stamp; NAME=$name; SPRINT=$Sprint; ISSUE=$Issue; BLOCKEDBY=$BlockedBy }) | Out-Null
    Emit $true (Join-Path $tdir 'log.md')   (Tpl 'task-log.md.tpl'   @{ STAMP=$stamp; NAME=$name }) | Out-Null
    # slice table row + slice log
    $sstate = Join-Path $slice 'state.md'
    Set-RatmacTaskRow -SliceStatePath $sstate -Task $name -Issue $Issue -Sprint $Sprint -Status 'active' -Ts $stamp
    $touched += ($sstate -replace '\\','/')
    Add-RatmacLog -LogPath (Join-Path $slice 'log.md') -Verb 'kickoff-task' -Args $name -Ts $stamp
    $touched += ((Join-Path $slice 'log.md') -replace '\\','/')
    Write-Output "kickoff task: $name under $sname"
    Write-Output (Write-RatmacContract @{
        'Run mode'='single'; 'Active proj'=$p.Proj; 'Active slice'=$sname; 'Active task'=$name
        'Files touched'=(($touched | Select-Object -Unique) -join ', ')
        'Skill chain'='ratmac-kickoff'
        'Next safe action'='fill issue.md/task.md; ratmac-checkpoint as work proceeds; ratmac-lint'
    })
  }
}
