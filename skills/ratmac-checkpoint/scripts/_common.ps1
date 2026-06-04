# _common.ps1 — shared engine for all ratmac-* skills (canonical copy; mirrored into each skill dir).
# pwsh primary (R4). Dot-source from a skill script:  . "$PSScriptRoot/_common.ps1"
# No external modules. All functions prefixed Ratmac- to avoid collision.
# Scheduler-domain twin of arca-skills/_common.ps1. Writes only under scheduler/ (R5).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- canonical line-ending write (R4/R10): always LF, UTF-8 no BOM ------------------
# pwsh Set-Content/Add-Content emit CRLF on Windows; the POSIX engine writes LF. To
# keep every file byte-identical across engines (R4 same-side-effects, R10 byte-
# idempotence) we write LF explicitly through .NET. Lines are joined by "\n" with a
# single trailing "\n", matching how the sh engine's printf/awk pipelines land bytes.
$script:RatmacUtf8NoBom = [System.Text.UTF8Encoding]::new($false)
function Set-RatmacFileLines {
    param([Parameter(Mandatory)][string]$Path, [AllowEmptyCollection()][string[]]$Lines)
    $text = (@($Lines) -join "`n")
    if ($text.Length -gt 0) { $text += "`n" }
    [System.IO.File]::WriteAllText($Path, $text, $script:RatmacUtf8NoBom)
}
function Add-RatmacFileLine {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Line)
    [System.IO.File]::AppendAllText($Path, $Line + "`n", $script:RatmacUtf8NoBom)
}

# --- scheduler root resolution (RQ1: cwd-walk, env override) -----------------------
# Precedence: explicit -Root arg → env RATMAC_SCHEDULER_ROOT → cwd ancestor walk.
# A "scheduler root" is the dir that holds p-<name> project subtrees (or is named
# 'scheduler', or exposes an arca/scheduler mount). The wspace mount may point a
# p-<project> dir straight in; Get-RatmacProj copes with both shapes.
function Get-RatmacRoot {
    param([string]$Root)

    if ($Root) {
        $r = (Resolve-Path -LiteralPath $Root -ErrorAction SilentlyContinue)
        if ($r) { return $r.Path }
        throw "BLOCKED: -Root '$Root' does not exist."
    }
    if ($env:RATMAC_SCHEDULER_ROOT) {
        return (Resolve-Path -LiteralPath $env:RATMAC_SCHEDULER_ROOT).Path
    }

    # cwd ancestor walk: prefer arca/scheduler mount, then a 'scheduler' dir, then any
    # dir already holding p-<name> children.
    $dir = (Get-Location).Path
    while ($dir) {
        foreach ($cand in @((Join-Path $dir 'arca/scheduler'), (Join-Path $dir 'scheduler'))) {
            if (Test-Path $cand) { return (Resolve-Path -LiteralPath $cand).Path }
        }
        if ((Split-Path $dir -Leaf) -eq 'scheduler') { return $dir }
        if (@(Get-ChildItem -LiteralPath $dir -Directory -Filter 'p-*' -ErrorAction SilentlyContinue).Count -gt 0) { return $dir }
        $parent = Split-Path $dir -Parent
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    throw "BLOCKED: cannot resolve scheduler root. Set -Root <scheduler>, or RATMAC_SCHEDULER_ROOT, or run inside a scheduler tree."
}

# --- active project resolution (RQ10) ---------------------------------------------
# Returns @{ Root=<sched root>; Proj=<p-name>; Path=<abs p- dir> }.
# If $Root is itself a p-<name> dir (wspace mount shape), treat it as the proj.
# Else: explicit -Proj, else the single p-* child, else the one whose state.md is
# status: active, else STOP (caller decides).
function Get-RatmacProj {
    param([string]$Root, [string]$Proj)
    $sched = Get-RatmacRoot -Root $Root

    if ((Split-Path $sched -Leaf) -like 'p-*') {
        return @{ Root = (Split-Path $sched -Parent); Proj = (Split-Path $sched -Leaf); Path = $sched }
    }

    $projDirs = @(Get-ChildItem -LiteralPath $sched -Directory -Filter 'p-*' -ErrorAction SilentlyContinue)
    if ($Proj) {
        $p = $projDirs | Where-Object { $_.Name -eq $Proj } | Select-Object -First 1
        if ($p) { return @{ Root = $sched; Proj = $p.Name; Path = $p.FullName } }
        throw "BLOCKED: project '$Proj' not found under $sched"
    }
    if ($projDirs.Count -eq 1) {
        return @{ Root = $sched; Proj = $projDirs[0].Name; Path = $projDirs[0].FullName }
    }
    $active = @()
    foreach ($p in $projDirs) {
        $st = Join-Path $p.FullName 'state.md'
        if (Test-Path $st) {
            $fm = Read-RatmacFrontmatter $st
            if ($fm['status'] -eq 'active') { $active += $p }
        }
    }
    if ($active.Count -eq 1) { return @{ Root = $sched; Proj = $active[0].Name; Path = $active[0].FullName } }
    throw "BLOCKED: cannot pick active project (found $($projDirs.Count); $($active.Count) active). Pass -Proj <p-name>."
}

# --- active slice resolution ------------------------------------------------------
# Returns abs path of the active slice dir under a proj, or $null. Single non-archive
# s-* dir, else the one whose state.md is status: active.
function Get-RatmacActiveSlice {
    param([Parameter(Mandatory)][string]$ProjPath)
    $slices = @(Get-ChildItem -LiteralPath $ProjPath -Directory -Filter 's-*' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne 'archive' })
    if ($slices.Count -eq 0) { return $null }
    if ($slices.Count -eq 1) { return $slices[0].FullName }
    foreach ($s in $slices) {
        $st = Join-Path $s.FullName 'state.md'
        if (Test-Path $st) {
            $fm = Read-RatmacFrontmatter $st
            if ($fm['status'] -eq 'active') { return $s.FullName }
        }
    }
    return $null
}

# --- resolve a task ref to its grad/ dir under the active slice -------------------
function Resolve-RatmacTask {
    param([Parameter(Mandatory)][string]$SlicePath, [Parameter(Mandatory)][string]$Task)
    $name = ($Task -replace '\\','/').Split('/')[-1]
    if ($name -notmatch '^t-') { $name = "t-$name" }
    $grad = Join-Path $SlicePath "grad/$name"
    if (Test-Path $grad) { return $grad }
    return $null
}

# --- proj mode (maintainer | sole | dual), read from p-<name>/state.md ------------
function Get-RatmacMode {
    param([Parameter(Mandatory)][string]$ProjPath)
    $st = Join-Path $ProjPath 'state.md'
    if (-not (Test-Path $st)) { return $null }
    return (Read-RatmacFrontmatter $st)['mode']
}

# --- timestamps (RQ3: -Ts override else Get-Date) ---------------------------------
function Get-RatmacStamp {
    param([string]$Ts)
    if ($Ts) { return $Ts }
    return (Get-Date -Format 'yyyy-MM-dd-HH:mm:ss')
}
function Get-RatmacId {
    param([string]$Ts)
    if ($Ts) {
        if ($Ts -match '^\d{14}$') { return $Ts }
        $digits = ($Ts -replace '[^0-9]', '')
        if ($digits.Length -ge 14) { return $digits.Substring(0, 14) }
    }
    return (Get-Date -Format 'yyyyMMddHHmmss')
}

# --- template expansion ({{KEY}} → value) -----------------------------------------
function Expand-RatmacTemplate {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Vars
    )
    $text = Get-Content -LiteralPath $Path -Raw
    foreach ($k in $Vars.Keys) {
        $text = $text -replace [regex]::Escape("{{$k}}"), [string]$Vars[$k]
    }
    return $text
}

# --- frontmatter read (minimal YAML: scalars, inline [a,b] lists, block lists) -----
function Read-RatmacFrontmatter {
    param([Parameter(Mandatory)][string]$Path)
    # @(...) so an empty/1-line file yields an array with a valid .Count under
    # StrictMode (defect: scalar/null .Count + index throws instead of returning @{}).
    $lines = @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
    # tolerate a GENERATED sentinel on line 1 (residual files, S13)
    $start = 0
    if ($lines.Count -ge 1 -and $lines[0] -match '<!--\s*GENERATED') { $start = 1 }
    if ($lines.Count -lt ($start + 1) -or $lines[$start].Trim() -ne '---') { return @{} }
    $fm = @{}
    $i = $start + 1
    $curKey = $null
    while ($i -lt $lines.Count -and $lines[$i].Trim() -ne '---') {
        $line = $lines[$i]
        if ($line -match '^\s+-\s+(.*)$' -and $curKey) {
            if ($fm[$curKey] -isnot [System.Collections.ArrayList]) { $fm[$curKey] = [System.Collections.ArrayList]::new() }
            [void]$fm[$curKey].Add($Matches[1].Trim().Trim('"'))
        }
        elseif ($line -match '^([A-Za-z0-9_-]+):\s*(.*)$') {
            $curKey = $Matches[1]
            $val = $Matches[2].Trim()
            if ($val -eq '') { $fm[$curKey] = '' }
            elseif ($val -match '^\[(.*)\]$') {
                $items = $Matches[1].Split(',') | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ -ne '' }
                $fm[$curKey] = @($items)
            }
            else { $fm[$curKey] = $val.Trim('"') }
        }
        $i++
    }
    return $fm
}

# --- R9 concurrent-edit guard -----------------------------------------------------
# Snapshot a file's `time-modified` at read with (Read-RatmacFrontmatter $path)['time-modified'];
# call this just before the first mutating write. If the on-disk `time-modified` has
# advanced past the snapshot ($SeenTs), a hand-edit landed under us — STOP rather than
# clobber it (R9). Prints the HUMAN_DECISION_REQUIRED marker BEFORE the contract and
# exits 3 unless -NoExit, in which case it returns $false (caller decides).
# A missing file or absent snapshot is treated as fresh (returns $true).
function Assert-RatmacFresh {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$SeenTs,
        [switch]$NoExit
    )
    if (-not $SeenTs) { return $true }
    if (-not (Test-Path $Path)) { return $true }
    $cur = (Read-RatmacFrontmatter $Path)['time-modified']
    if (-not $cur) { return $true }
    # string compare is correct for the fixed-width yyyy-MM-dd-HH:mm:ss / yyyyMMddHHmmss stamps.
    if ([string]$cur -gt [string]$SeenTs) {
        if ($NoExit) { return $false }
        Write-Output "HUMAN_DECISION_REQUIRED concurrent edit: $Path time-modified ($cur) advanced past read snapshot ($SeenTs) — re-read and retry (R9)."
        exit 3
    }
    return $true
}

# --- frontmatter scalar set (bumps time-modified; in-place line rewrite) -----------
function Set-RatmacFrontmatterValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value,
        [string]$Ts
    )
    $lines = [System.Collections.ArrayList]@(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
    $stamp = Get-RatmacStamp $Ts
    $inFm = $false; $fmEnd = -1; $keyIdx = -1; $tmIdx = -1; $sawOpen = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') {
            if (-not $sawOpen) { $sawOpen = $true; $inFm = $true; continue }
            else { $fmEnd = $i; break }
        }
        if ($inFm -and $lines[$i] -match "^$([regex]::Escape($Key)):") { $keyIdx = $i }
        if ($inFm -and $lines[$i] -match '^time-modified:') { $tmIdx = $i }
    }
    if ($keyIdx -ge 0) { $lines[$keyIdx] = "${Key}: $Value" }
    elseif ($fmEnd -ge 0) { $lines.Insert($fmEnd, "${Key}: $Value") ; if ($tmIdx -ge $fmEnd) { $tmIdx++ } }
    if ($tmIdx -ge 0 -and $Key -ne 'time-modified') { $lines[$tmIdx] = "time-modified: $stamp" }
    elseif ($tmIdx -ge 0 -and $Key -eq 'time-modified') { } # already set above
    Set-RatmacFileLines -Path $Path -Lines @($lines)
}

# --- append-only log line (S19): "<ts> <verb> <args>" -----------------------------
function Add-RatmacLog {
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$Verb,
        [string]$Args = '',
        [string]$Ts
    )
    $stamp = Get-RatmacStamp $Ts
    $line = if ($Args) { "$stamp $Verb $Args" } else { "$stamp $Verb" }
    if (-not (Test-Path $LogPath)) {
        New-RatmacParentDir $LogPath
        Set-RatmacFileLines -Path $LogPath -Lines @("---","time-created: $stamp","time-modified: $stamp","---","",$line)
        return
    }
    Add-RatmacFileLine -Path $LogPath -Line $line
    Set-RatmacFrontmatterValue -Path $LogPath -Key 'time-modified' -Value $stamp -Ts $stamp
}

# --- find a body section's bounds: "## <name>" → (start, endExclusive) ------------
# Returns @{ Start=<idx of heading>; End=<idx of next heading or count> } or $null.
function Find-RatmacSection {
    # $Lines accepts an empty collection (AllowEmptyCollection + non-Mandatory): a
    # 0-element list from a malformed/empty file must return $null, not throw under
    # StrictMode. Typed [object[]] so both ArrayList and @() bind.
    param([AllowEmptyCollection()][object[]]$Lines, [Parameter(Mandatory)][string]$Name)
    $Lines = @($Lines)
    $start = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match "^##\s+$([regex]::Escape($Name))\s*$") { $start = $i; break }
    }
    if ($start -lt 0) { return $null }
    $end = $Lines.Count
    for ($i = $start + 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^##\s+') { $end = $i; break }
    }
    return @{ Start = $start; End = $end }
}

# --- task ## affects (S18): hand-edited bullet list; dedupe-add (RQ13) -------------
# Returns @{ Added=@(...); Dup=@(...) }.
function Add-RatmacAffects {
    param(
        [Parameter(Mandatory)][string]$StatePath,
        [Parameter(Mandatory)][string[]]$Paths,
        [string]$Ts
    )
    $lines = [System.Collections.ArrayList]@(Get-Content -LiteralPath $StatePath -ErrorAction SilentlyContinue)
    $sec = Find-RatmacSection -Lines $lines -Name 'affects'
    if (-not $sec) {
        # append an affects section at end
        [void]$lines.Add(''); [void]$lines.Add('## affects')
        $sec = @{ Start = $lines.Count - 1; End = $lines.Count }
    }
    # collect existing bullets in the section
    $existing = @()
    for ($i = $sec.Start + 1; $i -lt $sec.End; $i++) {
        if ($lines[$i] -match '^\s*-\s+(.*\S)\s*$') { $existing += $Matches[1].Trim() }
    }
    $added = @(); $dup = @()
    $insertAt = $sec.End
    foreach ($p in $Paths) {
        $norm = ($p -replace '\\','/').Trim()
        if ($norm -eq '') { continue }
        if ($existing -contains $norm) { $dup += $norm; continue }
        $lines.Insert($insertAt, "- $norm"); $insertAt++
        $existing += $norm; $added += $norm
    }
    Set-RatmacFileLines -Path $StatePath -Lines @($lines)
    if ($Ts) { Set-RatmacFrontmatterValue -Path $StatePath -Key 'time-modified' -Value (Get-RatmacStamp $Ts) -Ts $Ts }
    return @{ Added = $added; Dup = $dup }
}

# --- read a body section's bullet list ('- x') from any file ----------------------
# Reads bullets from ALL matching "## <Section>" headings, not just the first. The sh
# twin (ratmac_affects_list) re-enters its awk scan (ina=1) on every matching heading,
# so a malformed/hand-edited file with duplicate "## affects" headings must roll up the
# union of bullets across all of them on BOTH engines (R4 parity). Find-RatmacSection
# only returns the FIRST section's bounds, so we loop it from just past each section's
# end to pick up subsequent duplicate headings. The proper API (Add-RatmacAffects) only
# ever maintains one heading, so normal operation reads exactly one section.
function Get-RatmacAffectsList {
    param([Parameter(Mandatory)][string]$Path, [string]$Section = 'affects')
    if (-not (Test-Path $Path)) { return @() }
    # @(...) so empty/1-line files yield a valid .Count; early-return @() on empty so
    # we never hand a 0-element list onward in a way that trips StrictMode (defect:
    # close done-gate fed Find-RatmacSection a 0-element list and threw).
    $lines = @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
    if ($lines.Count -eq 0) { return @() }
    $out = @()
    $from = 0
    while ($from -lt $lines.Count) {
        $window = @($lines[$from..($lines.Count - 1)])
        $sec = Find-RatmacSection -Lines $window -Name $Section
        if (-not $sec) { break }
        $start = $from + $sec.Start
        $end   = $from + $sec.End
        for ($i = $start + 1; $i -lt $end; $i++) {
            $ln = $lines[$i]
            if ($ln -match '<!--') { continue }
            if ($ln -match '^\s*-\s+(.*\S)\s*$') { $out += $Matches[1].Trim() }
        }
        # advance past this section's terminating heading; if End == count, we are done.
        if ($end -ge $lines.Count) { break }
        $from = $end
    }
    return $out
}

# --- GENERATED fence rewrite (S20): replace lines between markers inside a file ----
# Marker pair: "<!-- GENERATED -->" ... "<!-- /GENERATED -->". If absent, append the
# fence under the named section (creating the section if needed). Returns $true if
# the file content changed (A10/R10 idempotence: identical region => no write).
#
# Marker scan: take ONLY the FIRST open->close pair; later/duplicate fences are
# ignored so a double or out-of-order GENERATED block can never be mis-spliced
# (defect: g1<g0 picked last-open/first-close and corrupted the file).
#
# Unbalanced fence (open marker with no matching close): we do NOT delete past the
# missing close (that would truncate user data and diverge from the sh engine).
# Instead we leave the dangling open in place and append a FRESH balanced fence at
# EOF, then write into that. Mirrored in _common.sh.
function Set-RatmacFence {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Body,        # the lines to place between the markers
        [string]$Section = 'affects',
        [string]$Ts
    )
    $lines = [System.Collections.ArrayList]@(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
    $created = $false
    $g0 = -1; $g1 = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($g0 -lt 0) {
            if ($lines[$i] -match '<!--\s*GENERATED\s*-->') { $g0 = $i }
        }
        elseif ($lines[$i] -match '<!--\s*/GENERATED\s*-->') { $g1 = $i; break }   # first open->close pair only
    }
    if ($g0 -ge 0 -and $g1 -lt 0) {
        # unbalanced: open marker, no close. Do not consume to EOF; append a fresh
        # balanced fence at end and target it. The dangling open is left untouched.
        if ($lines.Count -gt 0 -and "$($lines[$lines.Count - 1])".Trim() -ne '') { [void]$lines.Add('') }
        [void]$lines.Add('<!-- GENERATED -->'); $g0 = $lines.Count - 1
        [void]$lines.Add('<!-- /GENERATED -->'); $g1 = $lines.Count - 1
        $created = $true
    }
    if ($g0 -lt 0) {
        # need a fence: find/create the section, drop the fence right under its heading
        $sec = Find-RatmacSection -Lines $lines -Name $Section
        if (-not $sec) {
            [void]$lines.Add(''); [void]$lines.Add("## $Section")
            $sec = @{ Start = $lines.Count - 1; End = $lines.Count }
        }
        $ins = $sec.Start + 1
        $lines.Insert($ins, '<!-- GENERATED -->'); $g0 = $ins
        $lines.Insert($g0 + 1, '<!-- /GENERATED -->'); $g1 = $g0 + 1
        $created = $true
    }
    # capture old region
    $old = @(); for ($i = $g0 + 1; $i -lt $g1; $i++) { $old += $lines[$i] }
    $new = @($Body)
    # idempotent: identical region AND no fence newly materialized => no write. A
    # freshly-created fence (incl. empty body, no pre-existing fence) must always be
    # written so the S20 region exists on disk (defect: empty-body-no-fence skipped).
    if (-not $created -and ($old -join "`n") -eq ($new -join "`n")) { return $false }
    # remove old, insert new
    for ($i = $g1 - 1; $i -gt $g0; $i--) { $lines.RemoveAt($i) }
    $ins = $g0 + 1
    foreach ($b in $new) { $lines.Insert($ins, $b); $ins++ }
    Set-RatmacFileLines -Path $Path -Lines @($lines)
    if ($Ts) { Set-RatmacFrontmatterValue -Path $Path -Key 'time-modified' -Value (Get-RatmacStamp $Ts) -Ts $Ts }
    return $true
}

# --- slice ## tasks table: upsert a row -------------------------------------------
# Row form: | [[t-name]] | <issue> | <sprint> | <status> |
function Set-RatmacTaskRow {
    param(
        [Parameter(Mandatory)][string]$SliceStatePath,
        [Parameter(Mandatory)][string]$Task,
        [string]$Issue = '',
        [string]$Sprint = '',
        [Parameter(Mandatory)][string]$Status,
        [string]$Ts
    )
    $name = if ($Task -match '^t-') { $Task } else { "t-$Task" }
    $issue  = if ($Issue)  { $Issue }  else { '—' }
    $sprint = if ($Sprint) { $Sprint } else { '—' }
    $row = "| [[$name]] | $issue | $sprint | $Status |"
    $lines = [System.Collections.ArrayList]@(Get-Content -LiteralPath $SliceStatePath -ErrorAction SilentlyContinue)
    $sec = Find-RatmacSection -Lines $lines -Name 'tasks'
    if (-not $sec) {
        [void]$lines.Add(''); [void]$lines.Add('## tasks')
        [void]$lines.Add('| task | issue | sprint | status |')
        [void]$lines.Add('|---|---|---|---|')
        $sec = Find-RatmacSection -Lines $lines -Name 'tasks'
    }
    # ensure header rows present
    $hasHeader = $false
    for ($i = $sec.Start + 1; $i -lt $sec.End; $i++) { if ($lines[$i] -match '^\|\s*task\s*\|') { $hasHeader = $true; break } }
    if (-not $hasHeader) {
        $lines.Insert($sec.Start + 1, '|---|---|---|---|')
        $lines.Insert($sec.Start + 1, '| task | issue | sprint | status |')
        $sec = Find-RatmacSection -Lines $lines -Name 'tasks'
    }
    # find existing row for this task → replace; else append before section end
    $rowIdx = -1
    for ($i = $sec.Start + 1; $i -lt $sec.End; $i++) {
        if ($lines[$i] -match "\[\[$([regex]::Escape($name))\]\]") { $rowIdx = $i; break }
    }
    if ($rowIdx -ge 0) { $lines[$rowIdx] = $row }
    else {
        # insert after the last table row in the section
        $insAt = $sec.End
        for ($i = $sec.End - 1; $i -gt $sec.Start; $i--) { if ($lines[$i] -match '^\|') { $insAt = $i + 1; break } }
        $lines.Insert($insAt, $row)
    }
    Set-RatmacFileLines -Path $SliceStatePath -Lines @($lines)
    if ($Ts) { Set-RatmacFrontmatterValue -Path $SliceStatePath -Key 'time-modified' -Value (Get-RatmacStamp $Ts) -Ts $Ts }
}

# --- scheduler-relative path for display ("scheduler/p-.../...") ------------------
function Get-RatmacRelPath {
    param([Parameter(Mandatory)][string]$AbsPath, [Parameter(Mandatory)][string]$Root)
    $p = ($AbsPath -replace '\\','/')
    $r = ((Split-Path $Root -Parent) -replace '\\','/')
    if ($r -and $p.StartsWith($r)) { return $p.Substring($r.Length).TrimStart('/') }
    return $p
}

# --- uniform output contract (R7) -------------------------------------------------
function Write-RatmacContract {
    param([hashtable]$Fields)
    $order = @('Run mode','Active proj','Active slice','Active task','Classification','Skill chain',
               'Files touched','Files generated','Lint result','Regen result',
               'Open questions','Human decisions required','Blocked items','Next safe action','Residual risk')
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('```contract')
    foreach ($k in $order) {
        if ($Fields.ContainsKey($k)) {
            $v = $Fields[$k]
            if ($v -is [array]) { $v = ($v -join ', ') }
            [void]$sb.AppendLine("${k}: $v")
        }
    }
    [void]$sb.AppendLine('```')
    return $sb.ToString()
}

# --- guard: ensure parent dir exists ----------------------------------------------
function New-RatmacParentDir {
    param([Parameter(Mandatory)][string]$Path)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
}

# --- resolve the dir for this skill's templates (../templates relative to scripts) --
function Get-RatmacTemplateDir {
    return (Join-Path (Split-Path -Parent $PSScriptRoot) 'templates')
}
