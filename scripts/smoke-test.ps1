# smoke-test.ps1 — end-to-end on a throwaway scheduler tree. Drives the FULL ratmac lifecycle
# (kickoff proj/slice/task -> checkpoint -> scope -> close -> regen -> lint) with PINNED -Ts values
# and asserts each step. Uses ONLY the ratmac skill scripts under skills/ratmac-*/scripts/*.ps1.
# Exits 0 iff every assertion passes (else 1). Cleans the temp tree unless -KeepTemp.
[CmdletBinding()] param([switch]$KeepTemp)
$ErrorActionPreference = 'Stop'
$skills = Join-Path $PSScriptRoot '../skills'
function Skill($n,$v){ (Resolve-Path (Join-Path $skills "$n/scripts/$v.ps1")).Path }

# Invoke a skill script in an ISOLATED child pwsh, splatting a param hashtable so array
# params survive (pwsh -File flattens arrays to a single string; -Command + splat does not)
# and the child's `exit N` cannot kill this harness. Sets $script:LastSkillExit. Returns stdout.
function Invoke-Skill {
    param([string]$Script, [hashtable]$Params = @{})
    $payload = @{ Script = $Script; Params = $Params } | ConvertTo-Json -Depth 6 -Compress
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
    $runner = @'
$ErrorActionPreference = 'Stop'
$cfg = ($env:RATMAC_SMOKE_PAYLOAD | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) }) | ConvertFrom-Json
$p = @{}
foreach ($prop in $cfg.Params.PSObject.Properties) {
    $v = $prop.Value
    if ($v -is [Array]) { $p[$prop.Name] = @($v) } else { $p[$prop.Name] = $v }
}
& $cfg.Script @p
exit $LASTEXITCODE
'@
    $env:RATMAC_SMOKE_PAYLOAD = $b64
    try {
        $out = & pwsh -NoProfile -Command $runner 2>&1 | Out-String
        $script:LastSkillExit = $LASTEXITCODE
    } finally {
        Remove-Item Env:RATMAC_SMOKE_PAYLOAD -ErrorAction SilentlyContinue
    }
    return $out
}

# Resolve a skill's .sh script path (the OTHER engine, used by the cross-engine parity test).
function ShellSkill($n,$v){ (Resolve-Path (Join-Path $skills "$n/scripts/$v.sh")).Path }

# Invoke a skill script via `pwsh -File` (NOT the splat path). Used to assert the literal
# `pwsh -File mutate.ps1` invocation form works for scalar-only params (-Kind ticket/plan);
# arrays MUST NOT be passed this way (pwsh -File mis-binds space-separated tokens), which is
# why every array-param skill (checkpoint -AddAffects) is invoked via Invoke-Skill's splat.
# Sets $script:LastSkillExit. Returns stdout.
function Invoke-SkillFile {
    param([string]$Script, [string[]]$ArgList = @())
    $out = & pwsh -NoProfile -File $Script @ArgList 2>&1 | Out-String
    $script:LastSkillExit = $LASTEXITCODE
    return $out
}

# Resolve a real POSIX bash (Git Bash), NOT the WSL stub at C:\Windows\System32\bash.exe which
# may be uninstalled/broken — that stub silently fails and would make the cross-engine parity
# test (#2) a false pass. Derive from git's install, fall back to the usual Git-for-Windows
# locations. $null if none found (the parity test then records the miss instead of false-passing).
function Resolve-PosixBash {
    $cands = @()
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        $root = Split-Path (Split-Path $git.Source -Parent) -Parent
        $cands += (Join-Path $root 'bin/bash.exe')
        $cands += (Join-Path $root 'usr/bin/bash.exe')
    }
    $cands += 'C:/Program Files/Git/bin/bash.exe'
    $cands += 'C:/Program Files/Git/usr/bin/bash.exe'
    $cands += 'C:/Program Files (x86)/Git/bin/bash.exe'
    foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return (Resolve-Path $c).Path } }
    return $null
}
$script:PosixBash = Resolve-PosixBash

# Run the OTHER engine (bash *.sh) against an already-authored tree. Sets $script:LastShExit.
# Returns stdout. Used by the cross-engine byte-parity test (#2): a tree authored by the pwsh
# engine, regen/lint'd by the POSIX engine, must yield byte-identical GENERATED regions (R4).
function Invoke-Sh {
    param([string]$Script, [string[]]$ArgList = @())
    if (-not $script:PosixBash) { $script:LastShExit = 127; return '<no posix bash found>' }
    $out = & $script:PosixBash $Script @ArgList 2>&1 | Out-String
    $script:LastShExit = $LASTEXITCODE
    return $out
}

# --- throwaway scheduler root ------------------------------------------------------
$tmp   = Join-Path ([System.IO.Path]::GetTempPath()) ("ratmac-smoke-" + (Get-Date -Format 'yyyyMMddHHmmss'))
$sched = Join-Path $tmp 'scheduler'
New-Item -ItemType Directory -Force -Path $sched | Out-Null
$env:RATMAC_SCHEDULER_ROOT = $sched

# dot-source engine for read helpers used in assertions (read-only here)
. (Skill 'ratmac-kickoff' '_common')

$fail = @()
function Check($cond,$msg){ if ($cond){ Write-Output "  PASS $msg" } else { Write-Output "  FAIL $msg"; $script:fail += $msg } }

# Pull a single contract field's value out of a skill's stdout (the "Key: value" line inside
# the ```contract block). Returns '' if absent. Used to assert declared Skill chain / Regen /
# Lint result fields actually carry the side-effect verdict (R7 contract field set).
function Get-ContractField($text, $key) {
    $m = [regex]::Match($text, "(?m)^\s*$([regex]::Escape($key)):\s*(.*?)\s*$")
    if ($m.Success) { return $m.Groups[1].Value } else { return '' }
}

Write-Output "smoke tree: $tmp"

$proj  = Join-Path $sched 'p-test'
$slice = Join-Path $proj  's-smoke'

# === a. kickoff proj (mode sole) ===================================================
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='proj'; Name='p-test'; Mode='sole'; Ts='2026-06-03-00:00:00' } | Out-Null
$pstate = Join-Path $proj 'state.md'
Check (Test-Path $pstate) 'a. proj state.md exists'
$pTxt = if (Test-Path $pstate) { Get-Content -LiteralPath $pstate -Raw } else { '' }
Check ($pTxt -match '(?m)^mode:\s*sole')     'a. proj frontmatter mode: sole (S5)'
Check ($pTxt -match '(?m)^status:\s*active') 'a. proj frontmatter status: active (S5)'
Check (Test-Path (Join-Path $proj 'goal'))   'a. proj goal/ dir exists (sole)'

# === b. kickoff slice ==============================================================
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='slice'; Name='s-smoke'; Ts='2026-06-03-00:00:01' } | Out-Null
Check (Test-Path (Join-Path $slice 'state.md'))         'b. slice state.md exists'
Check (Test-Path (Join-Path $slice 'scope.md'))         'b. slice scope.md exists (sole)'
Check (Test-Path (Join-Path $slice 'scope-history.md')) 'b. slice scope-history.md exists (sole)'
Check (Test-Path (Join-Path $slice 'grad'))             'b. slice grad/ dir exists'
$pTxt2 = Get-Content -LiteralPath $pstate -Raw
Check ($pTxt2 -match '(?m)^active slice:\s*s-smoke') 'b. proj state.md "active slice:" -> s-smoke'

# === c. kickoff task ===============================================================
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='task'; Name='t-smoke'; Ts='2026-06-03-00:00:02' } | Out-Null
$tdir = Join-Path $slice 'grad/t-smoke'
foreach ($leaf in @('issue.md','task.md','state.md','log.md')) {
    Check (Test-Path (Join-Path $tdir $leaf)) "c. grad/t-smoke/$leaf exists"
}
$sTxt = Get-Content -LiteralPath (Join-Path $slice 'state.md') -Raw
Check ($sTxt -match '\[\[t-smoke\]\]') 'c. slice ## tasks table has [[t-smoke]] row'

# === d. checkpoint + AddAffects (RQ13 dedupe) ======================================
$tstate = Join-Path $tdir 'state.md'
Invoke-Skill (Skill 'ratmac-checkpoint' 'checkpoint') @{ Task='t-smoke'; Note='did a thing'; AddAffects=@('src/a.cpp','src/b.cpp'); Ts='2026-06-03-00:00:03' } | Out-Null
$aff1 = @(Get-RatmacAffectsList -Path $tstate -Section 'affects')
Check ($aff1 -contains 'src/a.cpp' -and $aff1 -contains 'src/b.cpp') 'd. task ## affects lists src/a.cpp + src/b.cpp'
# re-add a.cpp — must NOT duplicate (RQ13)
Invoke-Skill (Skill 'ratmac-checkpoint' 'checkpoint') @{ Task='t-smoke'; Note='re-add'; AddAffects=@('src/a.cpp'); Ts='2026-06-03-00:00:04' } | Out-Null
$aff2 = @(Get-RatmacAffectsList -Path $tstate -Section 'affects')
$nA = @($aff2 | Where-Object { $_ -eq 'src/a.cpp' }).Count
Check ($nA -eq 1) 'd. re-adding src/a.cpp is NOT duplicated (RQ13 dedupe)'

# === e. scope + (create goal) ======================================================
Invoke-Skill (Skill 'ratmac-scope' 'scope') @{ Op='+'; Ref='claim-lots'; CreateGoal=$true; Reason='discovered'; Ts='2026-06-03-00:00:05' } | Out-Null
$goalFile = Join-Path $proj 'goal/claim-lots.md'
Check (Test-Path $goalFile) 'e. goal/claim-lots.md created'
if (Test-Path $goalFile) {
    $gfm = Read-RatmacFrontmatter $goalFile
    Check ("$($gfm['current'])".ToLower() -eq 'false') 'e. goal/claim-lots.md current: false'
}
$scopeTxt = Get-Content -LiteralPath (Join-Path $slice 'scope.md') -Raw
Check ($scopeTxt -match 'claim-lots') 'e. scope.md references claim-lots'
$histTxt = Get-Content -LiteralPath (Join-Path $slice 'scope-history.md') -Raw
Check ($histTxt -match '(?m)^\+\s+claim-lots') 'e. scope-history.md has "+ claim-lots" line'

# === f. close task =================================================================
# satisfy the close done-gate: mark the seeded acceptance-criteria checkbox complete in issue.md
# (close STOPs with HUMAN_DECISION_REQUIRED on any unchecked '- [ ]' AC item, by contract).
$tissue = Join-Path $tdir 'issue.md'
(Get-Content -LiteralPath $tissue -Raw) -replace '(?m)^(\s*)-\s*\[\s\]', '$1- [x]' |
    Set-Content -LiteralPath $tissue -Encoding UTF8
Invoke-Skill (Skill 'ratmac-close' 'close') @{ Task='t-smoke'; Status='done'; Cl='12345'; Goal='claim-lots'; Ts='2026-06-03-00:00:06' } | Out-Null
$archived = Join-Path $slice 'archive/t-smoke'
Check (Test-Path $archived)    'f. task dir moved to s-smoke/archive/t-smoke'
Check (-not (Test-Path $tdir)) 'f. grad/t-smoke no longer present'
$atState = Join-Path $archived 'state.md'
if (Test-Path $atState) {
    $afm = Read-RatmacFrontmatter $atState
    Check ($afm['status'] -eq 'done') 'f. archived task state.md status: done'
}
$gfm2 = if (Test-Path $goalFile) { Read-RatmacFrontmatter $goalFile } else { @{} }
Check ("$($gfm2['current'])".ToLower() -eq 'true') 'f. goal/claim-lots.md current: true'
$sTxt2 = Get-Content -LiteralPath (Join-Path $slice 'state.md') -Raw
Check ($sTxt2 -match '\|\s*\[\[t-smoke\]\][^\n]*\|\s*done\s*\|') 'f. slice table row [[t-smoke]] status done'

# === g. regen idempotence (R10) ====================================================
Invoke-Skill (Skill 'ratmac-regen' 'regen') @{ Ts='2026-06-03-00:00:07' } | Out-Null   # run #1
$r2 = Invoke-Skill (Skill 'ratmac-regen' 'regen') @{ Ts='2026-06-03-00:00:08' }         # run #2, different -Ts
Check ($r2 -match 'hash-stable') 'g. regen run #2 reports hash-stable (R10 idempotence)'
$goalResid  = Join-Path $proj  'goal-residual.md'
$scopeResid = Join-Path $slice 'scope-residual.md'
Check (Test-Path $goalResid)  'g. proj goal-residual.md exists'
Check (Test-Path $scopeResid) 'g. slice scope-residual.md exists'
if (Test-Path $goalResid)  { Check ((Get-Content -LiteralPath $goalResid  -TotalCount 1) -match '^<!--\s*GENERATED') 'g. goal-residual.md starts with GENERATED sentinel' }
if (Test-Path $scopeResid) { Check ((Get-Content -LiteralPath $scopeResid -TotalCount 1) -match '^<!--\s*GENERATED') 'g. scope-residual.md starts with GENERATED sentinel' }
# slice state.md GENERATED affects fence populated (archived task affects rolled up)
$sliceAff = @(Get-RatmacAffectsList -Path (Join-Path $slice 'state.md') -Section 'affects')
Check ($sliceAff.Count -gt 0) 'g. slice state.md <!-- GENERATED --> affects fence populated'
$projAff = @(Get-RatmacAffectsList -Path $pstate -Section 'affects')
Check ($projAff.Count -gt 0) 'g. proj state.md affects fence populated'

# === h. lint -Strict ===============================================================
$null = Invoke-Skill (Skill 'ratmac-lint' 'lint') @{ Strict=$true }
$lintExit = $script:LastSkillExit
Check ($lintExit -eq 0) "h. lint -Strict exit code 0 (clean tree) [exit $lintExit]"

# === i. empty-affects regen (latent crash guard) ==================================
# Second project with a slice that has NO tasks => its affects union is empty.
# regen must NOT crash (Set-RatmacFence -Body @() was rejected by Mandatory binding
# before the AllowEmptyCollection fix), must still write an (empty) GENERATED affects
# fence into both slice + proj state.md, and must remain hash-stable on re-run (R10).
$projE  = Join-Path $sched 'p-empty'
$sliceE = Join-Path $projE 's-empty'
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='proj';  Name='p-empty'; Mode='sole'; Ts='2026-06-03-00:00:09' } | Out-Null
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='slice'; Name='s-empty'; Proj='p-empty'; Ts='2026-06-03-00:00:10' } | Out-Null
$peState = Join-Path $projE  'state.md'
$seState = Join-Path $sliceE 'state.md'
Check (Test-Path $peState) 'i. p-empty proj state.md exists'
Check (Test-Path $seState) 'i. s-empty slice state.md exists (no tasks => empty affects)'
# regen run #1: must exit 0 (no empty-array binding crash on Set-RatmacFence)
$null = Invoke-Skill (Skill 'ratmac-regen' 'regen') @{ Proj='p-empty'; Ts='2026-06-03-00:00:11' }   # run #1
$regenE1 = $script:LastSkillExit
Check ($regenE1 -eq 0) "i. regen run #1 on empty-affects proj exits 0 (no crash) [exit $regenE1]"
# both state.md files carry a GENERATED affects fence (empty body is fine)
function Test-Fence($p){ if (-not (Test-Path $p)) { return $false }
    $t = Get-Content -LiteralPath $p -Raw
    return (($t -match '<!--\s*GENERATED\s*-->') -and ($t -match '<!--\s*/GENERATED\s*-->')) }
Check (Test-Fence $seState) 'i. s-empty state.md has GENERATED...\/GENERATED affects fence (empty body)'
Check (Test-Fence $peState) 'i. p-empty state.md has GENERATED...\/GENERATED affects fence (empty body)'
# affects union must in fact be empty (proves we exercised the empty path)
Check (@(Get-RatmacAffectsList -Path $seState -Section 'affects').Count -eq 0) 'i. s-empty affects fence is empty (empty-affects path exercised)'
# regen run #2 with a distinct -Ts must report hash-stable (R10 holds on empty input)
$rE2 = Invoke-Skill (Skill 'ratmac-regen' 'regen') @{ Proj='p-empty'; Ts='2026-06-03-00:00:12' }     # run #2
Check ($rE2 -match 'hash-stable') 'i. regen run #2 on empty-affects proj reports hash-stable (R10)'

# === j. close ALONE rebuilds residuals (no following standalone regen) =============
# close spawns ratmac-regen internally (R18). Prove the spawn actually fires by checking
# close's OWN 'Regen result' contract field is not 'not run' AND that the residuals + the
# slice/proj ## affects fences are populated IMMEDIATELY after close — without any extra
# regen call. This pins close's self-rebuild so the chain can never silently no-op.
$projJ  = Join-Path $sched 'p-closealone'
$sliceJ = Join-Path $projJ 's-ca'
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='proj';  Name='p-closealone'; Mode='sole'; Ts='2026-06-03-00:01:00' } | Out-Null
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='slice'; Name='s-ca'; Proj='p-closealone'; Ts='2026-06-03-00:01:01' } | Out-Null
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='task';  Name='t-ca'; Proj='p-closealone'; Ts='2026-06-03-00:01:02' } | Out-Null
$tdirJ = Join-Path $sliceJ 'grad/t-ca'
Invoke-Skill (Skill 'ratmac-checkpoint' 'checkpoint') @{ Task='t-ca'; Proj='p-closealone'; Note='ca'; AddAffects=@('src/ca.cpp'); Ts='2026-06-03-00:01:03' } | Out-Null
(Get-Content -LiteralPath (Join-Path $tdirJ 'issue.md') -Raw) -replace '(?m)^(\s*)-\s*\[\s\]', '$1- [x]' |
    Set-Content -LiteralPath (Join-Path $tdirJ 'issue.md') -Encoding UTF8
$closeJ = Invoke-Skill (Skill 'ratmac-close' 'close') @{ Task='t-ca'; Proj='p-closealone'; Status='done'; Cl='1'; Ts='2026-06-03-00:01:04' }
$jRegen = Get-ContractField $closeJ 'Regen result'
Check ($jRegen -ne '' -and $jRegen -ne 'not run') "j. close's own 'Regen result' is not 'not run' (regen spawned) [$jRegen]"
# residuals + fences populated by close ALONE (no standalone regen ran)
$jSliceAff = @(Get-RatmacAffectsList -Path (Join-Path $sliceJ 'state.md') -Section 'affects')
Check ($jSliceAff -contains 'src/ca.cpp') 'j. slice ## affects fence populated right after close (no extra regen)'
$jProjAff  = @(Get-RatmacAffectsList -Path (Join-Path $projJ 'state.md') -Section 'affects')
Check ($jProjAff -contains 'src/ca.cpp') 'j. proj ## affects fence populated right after close (no extra regen)'
Check (Test-Path (Join-Path $projJ  'goal-residual.md'))  'j. proj goal-residual.md exists after close alone'
Check (Test-Path (Join-Path $sliceJ 'scope-residual.md')) 'j. slice scope-residual.md exists after close alone'

# === k. cross-engine byte parity (pwsh-authored tree, regen'd by BOTH engines) =====
# Author ONE tree with the pwsh engine in scheduler root A, then COPY it verbatim to root B
# (same project name p-xeng — the name is embedded in residuals, so both copies MUST share it
# for a fair byte compare). regen A with pwsh and B with the OTHER (POSIX) engine, same -Ts.
# The GENERATED ## affects fences (slice+proj state.md) and the whole-file residuals MUST be
# byte-identical across engines (R4 same-side-effects, R10/S20). diff must be empty — clean
# lint alone is NOT enough; the bytes must match.
$kRootA = Join-Path $tmp 'xeng-a'; $kRootB = Join-Path $tmp 'xeng-b'
New-Item -ItemType Directory -Force -Path $kRootA | Out-Null
# author the tree under root A using the pwsh engine (explicit -Root, not env)
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='proj';  Name='p-xeng'; Mode='sole'; Root=$kRootA; Ts='2026-06-03-00:02:00' } | Out-Null
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='slice'; Name='s-pp'; Root=$kRootA; Proj='p-xeng'; Ts='2026-06-03-00:02:01' } | Out-Null
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='task';  Name='t-pp'; Root=$kRootA; Proj='p-xeng'; Ts='2026-06-03-00:02:02' } | Out-Null
Invoke-Skill (Skill 'ratmac-scope' 'scope') @{ Op='+'; Ref='ship-it'; CreateGoal=$true; Reason='r'; Root=$kRootA; Proj='p-xeng'; Ts='2026-06-03-00:02:03' } | Out-Null
Invoke-Skill (Skill 'ratmac-checkpoint' 'checkpoint') @{ Task='t-pp'; Root=$kRootA; Proj='p-xeng'; Note='n'; AddAffects=@('src/zeta.cpp','src/alpha.cpp'); Ts='2026-06-03-00:02:04' } | Out-Null
# copy the pre-regen tree verbatim to root B (identical bytes + identical project name)
Copy-Item -LiteralPath $kRootA -Destination $kRootB -Recurse -Force
$projKa = Join-Path $kRootA 'p-xeng'   # regen'd by pwsh
$projKb = Join-Path $kRootB 'p-xeng'   # regen'd by the POSIX engine
# Delete the residuals authoring (scope's regen) already created, so the two engines must
# CREATE them FRESH — this exercises each engine's residual WRITE path cross-engine (CRLF-vs-LF
# parity), not just the idempotent-skip path which would mask a line-ending divergence.
foreach ($rt in @($projKa,$projKb)) {
    Remove-Item -LiteralPath (Join-Path $rt 'goal-residual.md') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $rt 's-pp/scope-residual.md') -Force -ErrorAction SilentlyContinue
}
# bash gets forward-slash drive paths (Git Bash `cd` mis-parses backslashes as escapes)
$kRootBsh = ($kRootB -replace '\\','/')
Invoke-Skill (Skill 'ratmac-regen' 'regen') @{ Root=$kRootA; Proj='p-xeng'; Ts='2026-06-03-00:02:09' } | Out-Null
$null = Invoke-Sh (ShellSkill 'ratmac-regen' 'regen') @('--root',$kRootBsh,'--proj','p-xeng','--ts','2026-06-03-00:02:09')
$kParityOk = $true; $kDiffs = @()
foreach ($rel in @('state.md','s-pp/state.md','goal-residual.md','s-pp/scope-residual.md')) {
    $fa = Join-Path $projKa $rel; $fb = Join-Path $projKb $rel
    $ta = if (Test-Path $fa) { [System.IO.File]::ReadAllText($fa) } else { "<missing $rel>" }
    $tb = if (Test-Path $fb) { [System.IO.File]::ReadAllText($fb) } else { "<missing $rel>" }
    if ($ta -ne $tb) { $kParityOk = $false; $kDiffs += $rel }
}
Check $kParityOk "k. pwsh-vs-POSIX regen byte-identical for GENERATED regions + residuals (diff empty)$(if($kDiffs){' [differ: '+($kDiffs -join ',')+']'})"
# the OTHER engine's lint on the pwsh-authored+pwsh-regen'd tree is also clean (parity, not just bytes)
$kRootAsh = ($kRootA -replace '\\','/')
$kLintSh = Invoke-Sh (ShellSkill 'ratmac-lint' 'lint') @('--root',$kRootAsh,'--proj','p-xeng','--strict')
Check ($script:LastShExit -eq 0) "k. POSIX lint --strict on pwsh-authored tree exits 0 [exit $script:LastShExit]"

# === l. degenerate input: EMPTY + 1-LINE state.md, route/lint/close don't crash =====
# A grad task with a 0-byte state.md and another with a single-line state.md must NOT throw
# (StrictMode / Read-RatmacFrontmatter / Get-RatmacAffectsList must tolerate them). route is
# read-only (exit 0), lint reports S5 errors deterministically (exit 1, not a crash), and
# close on the empty task BLOCKs on empty affects (exit 2). No stack-trace text in any output.
$projL  = Join-Path $sched 'p-degen'
$sliceL = Join-Path $projL 's-dg'
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='proj';  Name='p-degen'; Mode='sole'; Ts='2026-06-03-00:03:00' } | Out-Null
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='slice'; Name='s-dg'; Proj='p-degen'; Ts='2026-06-03-00:03:01' } | Out-Null
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='task';  Name='t-empty';  Proj='p-degen'; Ts='2026-06-03-00:03:02' } | Out-Null
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='task';  Name='t-oneline'; Proj='p-degen'; Ts='2026-06-03-00:03:03' } | Out-Null
[System.IO.File]::WriteAllText((Join-Path $sliceL 'grad/t-empty/state.md'),   '')          # EMPTY
[System.IO.File]::WriteAllText((Join-Path $sliceL 'grad/t-oneline/state.md'), "no fm`n")    # 1-LINE
function Test-NoStack($t){ -not ($t -match 'at <ScriptBlock>|System\.Management\.Automation|ParameterBindingException|\+ CategoryInfo|RuntimeException|Unhandled exception') }
$rtL = Invoke-Skill (Skill 'ratmac-route' 'route') @{ Proj='p-degen' }
Check ($script:LastSkillExit -eq 0 -and (Test-NoStack $rtL)) "l. route on degenerate tree exits 0, no stack trace [exit $script:LastSkillExit]"
$ltL = Invoke-Skill (Skill 'ratmac-lint' 'lint') @{ Proj='p-degen' }
$ltLExit = $script:LastSkillExit
Check ($ltLExit -eq 1 -and (Test-NoStack $ltL)) "l. lint on degenerate tree exits 1 (S5 errors), no stack trace [exit $ltLExit]"
# t-empty has no affects → close status:done BLOCKs (exit 2), no crash
$clL = Invoke-Skill (Skill 'ratmac-close' 'close') @{ Task='t-empty'; Proj='p-degen'; Status='done'; Ts='2026-06-03-00:03:04' }
$clLExit = $script:LastSkillExit
Check ($clLExit -eq 2 -and ($clL -match 'BLOCKED') -and (Test-NoStack $clL)) "l. close on empty-state task BLOCKs clean (exit 2), no stack trace [exit $clLExit]"

# === m. archive collision: pre-existing archive/<x> => BLOCKED exit 2, no nesting ===
# Pre-create the destination archive/<slice> and archive/<task>, then drive transit/close.
# Both must STOP with "BLOCKED archive collision" exit 2 BEFORE the mv, and must NOT create a
# nested archive/<x>/<x> (the Windows-mv footgun this guard exists to prevent).
$projM  = Join-Path $sched 'p-collide'
$sliceM = Join-Path $projM 's-co'
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='proj';  Name='p-collide'; Mode='sole'; Ts='2026-06-03-00:04:00' } | Out-Null
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='slice'; Name='s-co'; Proj='p-collide'; Ts='2026-06-03-00:04:01' } | Out-Null
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='task';  Name='t-co'; Proj='p-collide'; Ts='2026-06-03-00:04:02' } | Out-Null
# --- task-level collision (close): pre-create slice/archive/t-co ---
New-Item -ItemType Directory -Force -Path (Join-Path $sliceM 'archive/t-co') | Out-Null
Invoke-Skill (Skill 'ratmac-checkpoint' 'checkpoint') @{ Task='t-co'; Proj='p-collide'; Note='c'; AddAffects=@('src/co.cpp'); Ts='2026-06-03-00:04:03' } | Out-Null
(Get-Content -LiteralPath (Join-Path $sliceM 'grad/t-co/issue.md') -Raw) -replace '(?m)^(\s*)-\s*\[\s\]', '$1- [x]' |
    Set-Content -LiteralPath (Join-Path $sliceM 'grad/t-co/issue.md') -Encoding UTF8
$clM = Invoke-Skill (Skill 'ratmac-close' 'close') @{ Task='t-co'; Proj='p-collide'; Status='done'; Cl='2'; Ts='2026-06-03-00:04:04' }
Check ($script:LastSkillExit -eq 2 -and ($clM -match 'BLOCKED archive collision')) "m. close BLOCKs (exit 2) on pre-existing archive/t-co [exit $script:LastSkillExit]"
Check (-not (Test-Path (Join-Path $sliceM 'archive/t-co/t-co'))) 'm. close did NOT nest archive/t-co/t-co'
Check (Test-Path (Join-Path $sliceM 'grad/t-co')) 'm. close left grad/t-co in place (no half-move)'
# --- slice-level collision (transit): pre-create proj/archive/s-co ---
New-Item -ItemType Directory -Force -Path (Join-Path $projM 'archive/s-co') | Out-Null
$trM = Invoke-Skill (Skill 'ratmac-transit' 'transit') @{ Tier='slice'; NewSlice='s-next'; Summary='x'; Force=$true; Proj='p-collide'; Ts='2026-06-03-00:04:05' }
Check ($script:LastSkillExit -eq 2 -and ($trM -match 'BLOCKED archive collision')) "m. transit BLOCKs (exit 2) on pre-existing archive/s-co [exit $script:LastSkillExit]"
Check (-not (Test-Path (Join-Path $projM 'archive/s-co/s-co'))) 'm. transit did NOT nest archive/s-co/s-co'
Check (Test-Path $sliceM) 'm. transit left s-co in place (no half-move)'

# === n. proj rollup retains archived slice (closing the ONLY slice => non-empty) ====
# A sole proj with a single slice + one done task carrying affects. transit the slice with
# -NoSuccessor (closes the only slice). The proj ## affects rollup is regen'd BEFORE the mv
# (lifecycle 3b), so the archived slice's contributed paths must STILL appear in the proj
# fence afterward — closing the last slice must NOT empty the proj rollup.
$projN  = Join-Path $sched 'p-rollup'
$sliceN = Join-Path $projN 's-ru'
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='proj';  Name='p-rollup'; Mode='sole'; Ts='2026-06-03-00:05:00' } | Out-Null
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='slice'; Name='s-ru'; Proj='p-rollup'; Ts='2026-06-03-00:05:01' } | Out-Null
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='task';  Name='t-ru'; Proj='p-rollup'; Ts='2026-06-03-00:05:02' } | Out-Null
Invoke-Skill (Skill 'ratmac-checkpoint' 'checkpoint') @{ Task='t-ru'; Proj='p-rollup'; Note='n'; AddAffects=@('src/only.cpp'); Ts='2026-06-03-00:05:03' } | Out-Null
(Get-Content -LiteralPath (Join-Path $sliceN 'grad/t-ru/issue.md') -Raw) -replace '(?m)^(\s*)-\s*\[\s\]', '$1- [x]' |
    Set-Content -LiteralPath (Join-Path $sliceN 'grad/t-ru/issue.md') -Encoding UTF8
Invoke-Skill (Skill 'ratmac-close' 'close') @{ Task='t-ru'; Proj='p-rollup'; Status='done'; Cl='3'; Ts='2026-06-03-00:05:04' } | Out-Null
Invoke-Skill (Skill 'ratmac-transit' 'transit') @{ Tier='slice'; NoSuccessor=$true; Summary='done'; Proj='p-rollup'; Ts='2026-06-03-00:05:05' } | Out-Null
Check (Test-Path (Join-Path $projN 'archive/s-ru')) 'n. s-ru archived under proj'
$nProjAff = @(Get-RatmacAffectsList -Path (Join-Path $projN 'state.md') -Section 'affects')
Check ($nProjAff -contains 'src/only.cpp') 'n. proj ## affects still lists archived slice path after closing the only slice (non-empty)'

# === o. -Force + empty ## affects on status:done => BLOCKED exit 2 ===================
# The non-empty ## affects gate is data-integrity (S18): a done task with no affects record is
# permanent loss once archived, so -Force MUST NOT bypass it. Close a done task with empty
# affects AND -Force; it must still BLOCK exit 2 and the task must stay in grad/.
$projO  = Join-Path $sched 'p-forcegate'
$sliceO = Join-Path $projO 's-fg'
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='proj';  Name='p-forcegate'; Mode='sole'; Ts='2026-06-03-00:06:00' } | Out-Null
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='slice'; Name='s-fg'; Proj='p-forcegate'; Ts='2026-06-03-00:06:01' } | Out-Null
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='task';  Name='t-fg'; Proj='p-forcegate'; Ts='2026-06-03-00:06:02' } | Out-Null
$clO = Invoke-Skill (Skill 'ratmac-close' 'close') @{ Task='t-fg'; Proj='p-forcegate'; Status='done'; Force=$true; Cl='4'; Ts='2026-06-03-00:06:03' }
Check ($script:LastSkillExit -eq 2 -and ($clO -match 'BLOCKED need affects')) "o. -Force does NOT bypass empty-affects done-gate (BLOCKED exit 2) [exit $script:LastSkillExit]"
Check (Test-Path (Join-Path $sliceO 'grad/t-fg')) 'o. t-fg left in grad/ (not archived) after blocked -Force close'

# === p. mutate via `pwsh -File` for -Kind ticket AND -Kind plan =====================
# Drive mutate.ps1 through the literal `pwsh -File` invocation form (scalar params only —
# mutate has no array params, so -File is safe here). Both kinds must exit 0, leave their
# side-effect (## ticket updates entry / replan log line), and emit a contract block.
$projP  = Join-Path $sched 'p-mutate'
$sliceP = Join-Path $projP 's-mu'
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='proj';  Name='p-mutate'; Mode='sole'; Ts='2026-06-03-00:07:00' } | Out-Null
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='slice'; Name='s-mu'; Proj='p-mutate'; Ts='2026-06-03-00:07:01' } | Out-Null
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='task';  Name='t-mu'; Proj='p-mutate'; Ts='2026-06-03-00:07:02' } | Out-Null
$mutPs = Skill 'ratmac-mutate' 'mutate'
$tkP = Invoke-SkillFile $mutPs @('-Task','t-mu','-Kind','ticket','-Reason','revised scope','-Proj','p-mutate','-Ts','2026-06-03-00:07:03')
$tkPExit = $script:LastSkillExit
Check ($tkPExit -eq 0) "p. mutate -Kind ticket via pwsh -File exits 0 [exit $tkPExit]"
Check ($tkP -match '(?m)^```contract')                            'p. mutate ticket emits a contract block'
$issueP = Get-Content -LiteralPath (Join-Path $sliceP 'grad/t-mu/issue.md') -Raw
Check ($issueP -match '(?m)^##\s+ticket updates' -and $issueP -match '(?m)^-\s+\S.*revised scope') 'p. mutate ticket wrote a non-empty ## ticket updates line'
$plP = Invoke-SkillFile $mutPs @('-Task','t-mu','-Kind','plan','-Reason','replan approach','-Proj','p-mutate','-Ts','2026-06-03-00:07:04')
$plPExit = $script:LastSkillExit
Check ($plPExit -eq 0) "p. mutate -Kind plan via pwsh -File exits 0 [exit $plPExit]"
Check ($plP -match '(?m)^```contract')                            'p. mutate plan emits a contract block'
$logP = Get-Content -LiteralPath (Join-Path $sliceP 'grad/t-mu/log.md') -Raw
Check ($logP -match '(?m)^\S+\s+replan\b') 'p. mutate plan appended a non-empty replan log line'

# === q. lint filesystem read-only: zero new/removed OS-temp entries (R11) ===========
# R11 says lint NEVER writes — at the filesystem level, incl. /tmp. To prove lint leaves no scratch
# file / PID leak, point the child shell's temp dir (TMP/TEMP/TMPDIR) at a FRESH PRIVATE empty dir
# that no other process touches, run lint, then assert that private dir's immediate children are
# unchanged. We must NOT snapshot the shared OS temp dir (GetTempPath()) directly: on a real machine
# that dir is churned by unrelated concurrent processes (the harness, node, etc.), so its delta is
# non-deterministic and has nothing to do with lint. Isolating the temp dir scopes the measurement
# to exactly what lint itself writes (R4: same design as the POSIX suite). Lint resolves the smoke
# tree via -Proj/env, so its child shell has no excuse to touch its temp dir at all.
$qTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("ratmac-lintq-" + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $qTmp -Force
# NOTE: keep Sort-Object INSIDE the @() so an EMPTY private dir stays an empty array, not $null
# (a trailing `| Sort-Object` on an empty pipeline yields $null, which would make Compare-Object
# throw "ReferenceObject is null" — the snapshotted dir starts empty here, unlike the old shared dir).
$qBefore = @(Get-ChildItem -LiteralPath $qTmp -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Name } | Sort-Object)
$qSaveTmp = $env:TMP; $qSaveTemp = $env:TEMP; $qSaveTmpdir = $env:TMPDIR
try {
    $env:TMP = $qTmp; $env:TEMP = $qTmp; $env:TMPDIR = $qTmp
    $null = Invoke-Skill (Skill 'ratmac-lint' 'lint') @{ Proj='p-test'; Strict=$true }
} finally {
    $env:TMP = $qSaveTmp; $env:TEMP = $qSaveTemp; $env:TMPDIR = $qSaveTmpdir
}
$qAfter  = @(Get-ChildItem -LiteralPath $qTmp -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Name } | Sort-Object)
Remove-Item -LiteralPath $qTmp -Recurse -Force -ErrorAction SilentlyContinue
$qDelta = @(Compare-Object -ReferenceObject $qBefore -DifferenceObject $qAfter)
Check ($qDelta.Count -eq 0) "q. lint added/removed ZERO OS-temp entries (R11 filesystem read-only) [delta $($qDelta.Count)]"

# === r. declared Skill chain actually ran (observe each sibling's side-effect) ======
# Every skill emits a 'Skill chain' contract field naming the siblings it spawns. Assert each
# named sibling actually executed by observing its side-effect / verdict field — a declared
# chain that silently no-ops is a contract lie (R7/R18). Use a DEDICATED scheduler root with a
# single project so transit's internally-spawned lint (which scopes by root) resolves to a real
# pass/warn verdict instead of an ambiguous multi-project BLOCK.
$rRoot  = Join-Path $tmp 'chain'
New-Item -ItemType Directory -Force -Path $rRoot | Out-Null
$projR  = Join-Path $rRoot 'p-chain'
$sliceR = Join-Path $projR 's-ch'
# kickoff: chain = 'ratmac-kickoff' (no sibling) — assert field + its scaffold side-effect
$kkR = Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='proj';  Name='p-chain'; Mode='sole'; Root=$rRoot; Ts='2026-06-03-00:08:00' }
Check ((Get-ContractField $kkR 'Skill chain') -eq 'ratmac-kickoff' -and (Test-Path (Join-Path $projR 'state.md'))) 'r. kickoff Skill chain=ratmac-kickoff and its scaffold side-effect present'
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='slice'; Name='s-ch'; Root=$rRoot; Proj='p-chain'; Ts='2026-06-03-00:08:01' } | Out-Null
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='task';  Name='t-ch'; Root=$rRoot; Proj='p-chain'; Ts='2026-06-03-00:08:02' } | Out-Null
Invoke-Skill (Skill 'ratmac-checkpoint' 'checkpoint') @{ Task='t-ch'; Root=$rRoot; Proj='p-chain'; Note='n'; AddAffects=@('src/ch.cpp'); Ts='2026-06-03-00:08:03' } | Out-Null
(Get-Content -LiteralPath (Join-Path $sliceR 'grad/t-ch/issue.md') -Raw) -replace '(?m)^(\s*)-\s*\[\s\]', '$1- [x]' |
    Set-Content -LiteralPath (Join-Path $sliceR 'grad/t-ch/issue.md') -Encoding UTF8
# close: chain = 'ratmac-close -> ratmac-regen' — assert regen sibling ran (verdict + fence)
$clR = Invoke-Skill (Skill 'ratmac-close' 'close') @{ Task='t-ch'; Root=$rRoot; Proj='p-chain'; Status='done'; Cl='5'; Ts='2026-06-03-00:08:04' }
Check ((Get-ContractField $clR 'Skill chain') -match 'ratmac-close -> ratmac-regen') 'r. close declares chain ratmac-close -> ratmac-regen'
$clRRegen = Get-ContractField $clR 'Regen result'
Check ($clRRegen -ne '' -and $clRRegen -ne 'not run' -and (@(Get-RatmacAffectsList -Path (Join-Path $sliceR 'state.md') -Section 'affects') -contains 'src/ch.cpp')) "r. close's regen sibling actually ran (verdict + slice fence side-effect) [$clRRegen]"
# transit: chain = 'ratmac-transit -> ratmac-regen -> ratmac-lint' — assert lint sibling ran
$trR = Invoke-Skill (Skill 'ratmac-transit' 'transit') @{ Tier='slice'; NoSuccessor=$true; Summary='done'; Root=$rRoot; Proj='p-chain'; Ts='2026-06-03-00:08:05' }
Check ((Get-ContractField $trR 'Skill chain') -match 'ratmac-transit -> ratmac-regen -> ratmac-lint') 'r. transit declares chain ratmac-transit -> ratmac-regen -> ratmac-lint'
$trRLint = Get-ContractField $trR 'Lint result'
Check ($trRLint -ne '' -and $trRLint -ne 'ratmac-lint not run' -and ($trRLint -notmatch 'BLOCKED')) "r. transit's lint sibling actually ran (Lint result carries a real verdict) [$trRLint]"
$trRRegen = Get-ContractField $trR 'Regen result'
Check ($trRRegen -match 'rebuilt') "r. transit's regen sibling actually ran (Regen result verdict) [$trRRegen]"

# === s. cross-engine kickoff-Emit byte parity (scaffold path, not just regen) =======
# Defect 1/6/11: the kickoff Emit path (and the slice/task scaffold) used to write CRLF on pwsh
# (Set-Content) while kickoff.sh wrote LF, so the scaffolded state/issue/task/log/scope files
# diverged byte-for-byte across engines (and pwsh added a doubled trailing newline). Test k only
# regen's a pwsh-authored tree, so it never exercises the kickoff WRITE path cross-engine. Here we
# build an IDENTICALLY-SEEDED tree with each engine (pwsh under root A, the POSIX engine under root
# B, same names + pinned -Ts) and assert every kickoff-scaffolded file is byte-identical — locking
# the LF/UTF-8-no-BOM fix (R4 same-side-effects, R10 byte-idempotence) so it cannot regress.
$sRootA = Join-Path $tmp 'kemit-a'; $sRootB = Join-Path $tmp 'kemit-b'
New-Item -ItemType Directory -Force -Path $sRootA, $sRootB | Out-Null
# pwsh engine authors under root A
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='proj';  Name='p-em'; Mode='sole'; Root=$sRootA; Ts='2026-06-03-00:09:00' } | Out-Null
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='slice'; Name='s-em'; Root=$sRootA; Proj='p-em'; Ts='2026-06-03-00:09:01' } | Out-Null
Invoke-Skill (Skill 'ratmac-kickoff' 'kickoff') @{ Tier='task';  Name='t-em'; Root=$sRootA; Proj='p-em'; Ts='2026-06-03-00:09:02' } | Out-Null
# POSIX engine authors the SAME tree under root B (forward-slash root for Git Bash)
$sRootBsh = ($sRootB -replace '\\','/')
$null = Invoke-Sh (ShellSkill 'ratmac-kickoff' 'kickoff') @('--tier','proj','--name','p-em','--mode','sole','--root',$sRootBsh,'--ts','2026-06-03-00:09:00')
$null = Invoke-Sh (ShellSkill 'ratmac-kickoff' 'kickoff') @('--tier','slice','--name','s-em','--root',$sRootBsh,'--proj','p-em','--ts','2026-06-03-00:09:01')
$null = Invoke-Sh (ShellSkill 'ratmac-kickoff' 'kickoff') @('--tier','task','--name','t-em','--root',$sRootBsh,'--proj','p-em','--ts','2026-06-03-00:09:02')
$projSa = Join-Path $sRootA 'p-em'; $projSb = Join-Path $sRootB 'p-em'
$sParityOk = $true; $sDiffs = @()
foreach ($rel in @('state.md','log.md','s-em/state.md','s-em/log.md','s-em/scope.md','s-em/scope-history.md',
                   's-em/grad/t-em/issue.md','s-em/grad/t-em/task.md','s-em/grad/t-em/state.md','s-em/grad/t-em/log.md')) {
    $fa = Join-Path $projSa $rel; $fb = Join-Path $projSb $rel
    $ba = if (Test-Path $fa) { [System.IO.File]::ReadAllBytes($fa) } else { $null }
    $bb = if (Test-Path $fb) { [System.IO.File]::ReadAllBytes($fb) } else { $null }
    if ($null -eq $ba -or $null -eq $bb -or [Convert]::ToBase64String($ba) -ne [Convert]::ToBase64String($bb)) { $sParityOk = $false; $sDiffs += $rel }
}
Check $sParityOk "s. pwsh-vs-POSIX kickoff scaffold byte-identical (LF/no-BOM, no CRLF)$(if($sDiffs){' [differ: '+($sDiffs -join ',')+']'})"
# no CR bytes anywhere in the pwsh-authored scaffold (defects 1/6/11)
$sNoCr = $true
foreach ($rel in @('state.md','s-em/grad/t-em/state.md')) {
    $f = Join-Path $projSa $rel
    if (Test-Path $f) {
        $crCount = @([System.IO.File]::ReadAllBytes($f) | Where-Object { $_ -eq 13 }).Count
        if ($crCount -gt 0) { $sNoCr = $false }
    }
}
Check $sNoCr 's. pwsh kickoff scaffold has ZERO CR bytes (no CRLF / no doubled trailing newline)'

# --- report ------------------------------------------------------------------------
Write-Output ""
if ($fail.Count -eq 0) { Write-Output "SMOKE OK — all assertions passed" }
else { Write-Output "SMOKE FAILED — $($fail.Count): $($fail -join '; ')" }

if (-not $KeepTemp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
else { Write-Output "kept: $tmp" }
Remove-Item Env:RATMAC_SCHEDULER_ROOT -ErrorAction SilentlyContinue
exit $(if ($fail.Count -eq 0) { 0 } else { 1 })
