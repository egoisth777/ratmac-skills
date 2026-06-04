# ratmac-auto — orchestrator. INIT->CLASSIFY->EVIDENCE->ROUTE->EXECUTE->VERIFY->REPORT.
# CONSERVATIVE (mirrors arca-auto): AUTO-RUNS only the safe read/verify ops — regen + lint.
# For ANY write branch (kickoff/checkpoint/mutate/scope/close/transit) it STOPS with
# HUMAN_DECISION_REQUIRED naming the exact ratmac-* skill + args; it never guesses a write (R12).
# Stops on ambiguity (HUMAN_DECISION_REQUIRED, exit 3) or missing artifact (BLOCKED, exit 2).
[CmdletBinding()]
param(
    [string]$Intent,
    [ValidateSet('next-checkpoint','task-close','slice-transit','user-intervention')][string]$Until = 'user-intervention',
    [string]$Root,
    [string]$Proj,
    [string]$Ts
)
. "$PSScriptRoot/_common.ps1"

$skills = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent   # .../skills
function Skill($name,$verb){ Join-Path $skills "$name/scripts/$verb.ps1" }
$lc = ($Intent ?? '').ToLower()

# ---------------------------------------------------------------------------------
# INIT — note R-invariants loaded (composition: ratmac-init is the stateless loader).
# ---------------------------------------------------------------------------------
Write-Output "== ratmac-auto =="
Write-Output "Intent: $Intent"
Write-Output "Until: $Until"
Write-Output "INIT: R-invariants loaded (R4/R5/R6/R7/R9/R10/R11/R12/R18); ratmac-init contract in effect."

# ---------------------------------------------------------------------------------
# CLASSIFY — spawn ratmac-route (read-only) and capture its text.
# ---------------------------------------------------------------------------------
$routeArgs = @('-NoProfile','-File',(Skill 'ratmac-route' 'route'))
if ($Root) { $routeArgs += @('-Root',$Root) }
if ($Proj) { $routeArgs += @('-Proj',$Proj) }
if ($Ts)   { $routeArgs += @('-Ts',$Ts) }
$routeOut = & pwsh @routeArgs 2>&1 | Out-String
Write-Output "-- CLASSIFY (ratmac-route) --"
Write-Output $routeOut

# route may have BLOCKED (no resolvable project / missing proj state). Propagate.
if ($routeOut -match '(?m)^BLOCKED ' -or $routeOut -match '(?m)Blocked items:\s*\S') {
    if ($routeOut -match '(?m)^Active project:\s*(.+)$' -eq $false) {
        Write-Output "BLOCKED ratmac-route could not resolve the scheduler context (see route output above)."
        Write-Output (Write-RatmacContract @{
            'Run mode'='auto'; 'Classification'='BLOCKED'
            'Skill chain'='ratmac-route'
            'Lint result'='not-run'; 'Regen result'='not-run'
            'Blocked items'='route failed to resolve project/slice — fix scheduler context first'
            'Next safe action'='pass -Root <scheduler> / -Proj <p-name>, or repair the missing state.md'
        })
        exit 2
    }
}

# parse route fields
function RouteField($label){
    foreach ($line in ($routeOut -split "`r?`n")) {
        if ($line -match ("^" + [regex]::Escape($label) + ":\s*(.*)$")) { return $Matches[1].Trim() }
    }
    return ''
}
$proj    = RouteField 'Active project'
$mode    = RouteField 'Mode'
$slice   = RouteField 'Active slice'
$rawTasks = RouteField 'Active tasks'    # e.g. "[t-foo (active); t-bar (blocked)]"
$suggest = RouteField 'Suggested next-action mode'

$tasksInner = ($rawTasks -replace '^\[','' -replace '\]$','').Trim()
$taskList = @()
if ($tasksInner -ne '') { $taskList = @($tasksInner -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) }
$hasSlice = ($slice -and $slice -ne '—')
$activeTaskNames = @($taskList | ForEach-Object { ($_ -split '\s+')[0] })
$singleActive = if ($activeTaskNames.Count -eq 1) { $activeTaskNames[0] } else { '' }

# ---------------------------------------------------------------------------------
# EVIDENCE — read the active task state.md if exactly one is in flight.
# ---------------------------------------------------------------------------------
Write-Output "-- EVIDENCE --"
$taskStatus = ''
$evidence = ''
if ($singleActive -and $hasSlice) {
    try {
        $p = Get-RatmacProj -Root $Root -Proj $Proj
        $sp = Get-RatmacActiveSlice -ProjPath $p.Path
        if ($sp) {
            $tdir = Resolve-RatmacTask -SlicePath $sp -Task $singleActive
            if ($tdir) {
                $tstate = Join-Path $tdir 'state.md'
                if (Test-Path $tstate) {
                    $tfm = Read-RatmacFrontmatter $tstate
                    $taskStatus = "$($tfm['status'])"
                    $rel = Get-RatmacRelPath -AbsPath $tstate -Root $p.Root
                    $evidence = "task=$singleActive status=$taskStatus state=$rel"
                    Write-Output "  $evidence"
                } else { Write-Output "  (active task $singleActive has no state.md)" }
            } else { Write-Output "  (active task $singleActive not resolvable under grad/)" }
        }
    } catch { Write-Output "  (evidence read skipped: $($_.Exception.Message))" }
} else {
    Write-Output "  (no single active task to inspect; tasks=[$tasksInner])"
}

# helper: STOP emitters --------------------------------------------------------------
function Stop-Human($reason, $fields) {
    Write-Output "HUMAN_DECISION_REQUIRED $reason"
    $base = @{ 'Run mode'='auto'; 'Skill chain'='ratmac-route'; 'Lint result'='not-run'; 'Regen result'='not-run'
               'Active proj'=$proj; 'Active slice'=$slice; 'Active task'=$(if($tasksInner){$tasksInner}else{'—'}) }
    foreach ($k in $fields.Keys) { $base[$k] = $fields[$k] }
    Write-Output (Write-RatmacContract $base)
    exit 3
}

# ---------------------------------------------------------------------------------
# ROUTE — derive the branch from route classification + intent keywords.
# Safe (AUTO-RUN): regen, lint. Everything else is a WRITE → STOP with the command.
# ---------------------------------------------------------------------------------
Write-Output "-- ROUTE --"

# Hard stop conditions first (orchestration.md "stop conditions").
if (-not $mode -or $mode -eq '?' -or $mode -notin @('maintainer','sole','dual')) {
    Stop-Human "proj mode undefined or invalid (mode='$mode'); cannot classify safely" @{
        'Classification'='STOP-MODE'
        'Human decisions required'="set a valid mode: in $proj/state.md (maintainer|sole|dual)"
        'Next safe action'="fix mode: in $proj/state.md frontmatter, then re-run ratmac-auto"
    }
}
# scope-changing intent words → always escalate (orchestration.md).
if ($lc -match '\b(rewrite|redesign|scrap|re-architect|overhaul)\b') {
    Stop-Human "intent contains scope-changing words; needs a human design call" @{
        'Classification'='STOP-SCOPE'
        'Human decisions required'='rewrite/redesign/scrap is out of auto scope — decide direction by hand'
        'Next safe action'='clarify the scope change with a human before any scheduler write'
    }
}
# RQ14: "continue" intent but no active task to continue.
if ($lc -match '\b(continue|resume|carry on|keep going)\b' -and -not $singleActive) {
    Stop-Human "intent says continue but there is no single active task to resume (RQ14)" @{
        'Classification'='STOP'
        'Human decisions required'="which task? tasks=[$tasksInner]"
        'Next safe action'='name the task explicitly, or kickoff one: ratmac-kickoff -Tier task -Name <kebab>'
    }
}

# Branch derivation. WRITE branches map to the exact skill + args; only F/G auto-run.
$branch = $null
$writeCmd = $null

if     ($lc -match '\b(regen|rollup|rebuild|refresh)\b')                 { $branch = 'F' }   # safe
elseif ($lc -match '\b(lint|verify|check|audit|drift|dangling)\b')       { $branch = 'G' }   # safe
elseif ($lc -match '\b(start|new|create)\b.*\bproject\b' -or $lc -match '\bnew proj\b') {
    $branch = 'A'; $writeCmd = "ratmac-kickoff -Tier proj -Name <kebab> -Mode maintainer|sole|dual"
}
elseif ($lc -match '\b(start|new|create)\b.*\bslice\b') {
    $branch = 'B'; $writeCmd = "ratmac-kickoff -Tier slice -Name <kebab>"
}
elseif ($lc -match '\b(start|new|create|kickoff)\b.*\btask\b') {
    $branch = 'C'; $writeCmd = "ratmac-kickoff -Tier task -Name <kebab> [-Issue <id>] [-Sprint <id>]"
}
elseif ($lc -match '\b(checkpoint|pause|snapshot|note|progress|blocked)\b') {
    $branch = 'D'
    $writeCmd = "ratmac-checkpoint -Task $(if($singleActive){$singleActive}else{'<t-name>'}) -Note `"<note>`" [-AddAffects <p1>,<p2>] [-Status active|blocked]"
}
elseif ($lc -match '\b(ticket|cr feedback|ticket update|requirement change)\b') {
    $branch = 'E'; $writeCmd = "ratmac-mutate -Task $(if($singleActive){$singleActive}else{'<t-name>'}) -Kind ticket -Reason `"<short>`""
}
elseif ($lc -match '\b(replan|revise plan|new plan)\b') {
    $branch = 'F-plan'; $writeCmd = "ratmac-mutate -Task $(if($singleActive){$singleActive}else{'<t-name>'}) -Kind plan -Reason `"<short>`" [-Diff <task.md path>]"
}
elseif ($lc -match '\b(approach|pivot|re-approach)\b') {
    $branch = 'G-approach'; $writeCmd = "ratmac-mutate -Task $(if($singleActive){$singleActive}else{'<t-name>'}) -Kind approach -Reason `"<short>`""
}
elseif ($lc -match '\b(done|complete|finish|land(ed)?|ship(ped)?)\b') {
    $branch = 'H'; $writeCmd = "ratmac-close -Task $(if($singleActive){$singleActive}else{'<t-name>'}) -Status done -Cl <id> [-Outcome <text>]"
}
elseif ($lc -match '\b(abandon|drop|cancel|give up)\b') {
    $branch = 'I'; $writeCmd = "ratmac-close -Task $(if($singleActive){$singleActive}else{'<t-name>'}) -Status abandoned -Outcome `"<reason>`""
}
elseif ($lc -match '\b(scope|defer|discovered)\b') {
    $branch = 'J'; $writeCmd = "ratmac-scope -Slice $slice -Op +|- -Ref <goal-topic> -Reason `"<short>`""
}
elseif ($lc -match '\b(transit|close slice|end slice|next slice)\b') {
    $branch = 'K'; $writeCmd = "ratmac-transit -Tier slice [-NewSlice <name>] -Summary `"<text|path>`""
}
elseif ($lc -match '\b(retire|close project|end project)\b') {
    $branch = 'L'; $writeCmd = "ratmac-transit -Tier proj -Summary `"<text|path>`""
}

# No branch matched → ambiguous: do NOT guess a write (R12).
if (-not $branch) {
    Stop-Human "intent did not map to a single branch; auto will not guess a write" @{
        'Classification'='STOP'
        'Open questions'="route suggests: $suggest"
        'Human decisions required'='pick a branch and run that ratmac-* skill explicitly'
        'Next safe action'='re-run with a clearer -Intent, or invoke a ratmac-* write skill directly'
    }
}
Write-Output "  Classification: $branch (intent-keyed)"

# Status ambiguity guard for write branches that target the active task.
if ($branch -in @('D','E','F-plan','G-approach','H','I') -and $singleActive -and $taskStatus -and $taskStatus -notin @('active','blocked')) {
    Stop-Human "task '$singleActive' status is '$taskStatus' (not active/blocked); ambiguous for branch $branch" @{
        'Classification'="STOP ($branch)"
        'Human decisions required'="resolve task status before $branch"
        'Next safe action'="inspect $singleActive state.md; reconcile status, then run the write skill by hand"
    }
}

# ---------------------------------------------------------------------------------
# EXECUTE — AUTO-RUN only the safe branches (F=regen, G=lint). All writes STOP here.
# ---------------------------------------------------------------------------------
Write-Output "-- EXECUTE --"
$chain = 'ratmac-route'
$execOut = ''
$regenResult = 'not-run'
$lintResult  = 'not-run'

switch ($branch) {
    'F' {
        $a = @('-NoProfile','-File',(Skill 'ratmac-regen' 'regen'))
        if ($Root) { $a += @('-Root',$Root) }; if ($Proj) { $a += @('-Proj',$Proj) }; if ($Ts) { $a += @('-Ts',$Ts) }
        $execOut = & pwsh @a 2>&1 | Out-String
        Write-Output $execOut
        $chain += ' -> ratmac-regen'
        if ($execOut -match '(?m)Regen result:\s*(.+)$') { $regenResult = $Matches[1].Trim() }
        elseif ($execOut -match '(?m)regen:\s*(.+)$')     { $regenResult = $Matches[1].Trim() }
    }
    'G' {
        # handled in VERIFY below (lint is the verify op); nothing extra to execute.
    }
    default {
        # WRITE branch — STOP with the exact command line + evidence (R12 / RQ9a).
        Write-Output "HUMAN_DECISION_REQUIRED write branch '$branch' — auto will not perform a scheduler write."
        Write-Output "  run this: $writeCmd"
        if ($evidence) { Write-Output "  evidence: $evidence" }
        Write-Output (Write-RatmacContract @{
            'Run mode'='auto'; 'Classification'=$branch
            'Active proj'=$proj; 'Active slice'=$slice; 'Active task'=$(if($tasksInner){$tasksInner}else{'—'})
            'Skill chain'='ratmac-route'
            'Lint result'='not-run'; 'Regen result'='not-run'
            'Open questions'=$(if($evidence){$evidence}else{'—'})
            'Human decisions required'="confirm + run: $writeCmd"
            'Next safe action'=$writeCmd
            'Residual risk'='no scheduler files were written by auto (conservative stance)'
        })
        exit 3
    }
}

# ---------------------------------------------------------------------------------
# VERIFY — spawn ratmac-lint (read-only, R11) and capture its result.
# ---------------------------------------------------------------------------------
Write-Output "-- VERIFY (ratmac-lint) --"
$la = @('-NoProfile','-File',(Skill 'ratmac-lint' 'lint'))
if ($Root) { $la += @('-Root',$Root) }; if ($Proj) { $la += @('-Proj',$Proj) }
$lintOut = & pwsh @la 2>&1 | Out-String
Write-Output $lintOut
$chain += ' -> ratmac-lint'
if     ($lintOut -match '(?m)Lint result:\s*(.+)$') { $lintResult = $Matches[1].Trim() }
elseif ($lintOut -match '(?im)\b(\d+)\s+error') { $lintResult = "$($Matches[1]) error(s)" }
elseif ($lintOut.Trim() -ne '') { $lintResult = 'ran (see output)' }

# ---------------------------------------------------------------------------------
# REPORT — merge into the uniform auto contract.
# ---------------------------------------------------------------------------------
$nextSafe = switch ($branch) {
    'F' { 'review regen diff; run ratmac-lint again if drift remained' }
    'G' { 'review lint violations; fix flagged files then re-run ratmac-lint' }
    default { 'invoke the suggested ratmac-* write skill explicitly' }
}
Write-Output "-- REPORT --"
Write-Output (Write-RatmacContract @{
    'Run mode'='auto'
    'Active proj'=$proj; 'Active slice'=$slice; 'Active task'=$(if($tasksInner){$tasksInner}else{'—'})
    'Classification'=$branch
    'Skill chain'=$chain
    'Files touched'='— (auto ran only read/verify ops)'
    'Files generated'=$(if($branch -eq 'F' -and $regenResult -notmatch 'hash-stable'){'see regen output'}else{'— (none / hash-stable)'})
    'Lint result'=$lintResult
    'Regen result'=$regenResult
    'Open questions'=$(if($suggest){"route suggested: $suggest"}else{'—'})
    'Human decisions required'='— (safe branch auto-completed; any write still needs explicit skill invocation)'
    'Blocked items'='—'
    'Next safe action'=$nextSafe
    'Residual risk'='auto wrote nothing; only ratmac-regen (generated regions, R6/R10) may have changed bytes'
})
