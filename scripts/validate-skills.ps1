# validate-skills.ps1 — structural validator for the ratmac-* skill family.
# For each skills/ratmac-* dir asserts:
#   1. a SKILL.md exists with name + description frontmatter,
#   2. (except ratmac-init) a scripts/<verb>.ps1 + <verb>.sh pair at verb parity (R4),
#      where <verb> is the skill name minus the 'ratmac-' prefix.
# Reports a table; exits 1 if any skill fails a check, else 0.
[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
$skillsDir = (Resolve-Path (Join-Path $PSScriptRoot '../skills')).Path

# minimal frontmatter scalar probe (does the key exist with a non-empty value?)
function Has-FmKey($path, $key) {
    if (-not (Test-Path $path)) { return $false }
    $lines = Get-Content -LiteralPath $path
    if ($lines.Count -lt 1 -or $lines[0].Trim() -ne '---') { return $false }
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') { break }
        if ($lines[$i] -match "^$([regex]::Escape($key)):\s*(\S.*)$") { return $true }
    }
    return $false
}

$rows = @()
$failCount = 0
function Row($skill,$skillMd,$name,$desc,$ps1,$sh,$ok) {
    $script:rows += [pscustomobject]@{ skill=$skill; 'SKILL.md'=$skillMd; name=$name; description=$desc; 'verb.ps1'=$ps1; 'verb.sh'=$sh; result=$ok }
}

$dirs = @(Get-ChildItem -LiteralPath $skillsDir -Directory | Where-Object { $_.Name -like 'ratmac-*' } | Sort-Object Name)

foreach ($d in $dirs) {
    $skill   = $d.Name
    $verb    = $skill -replace '^ratmac-',''
    $isInit  = ($skill -eq 'ratmac-init')

    $skillMdPath = Join-Path $d.FullName 'SKILL.md'
    $hasMd   = Test-Path $skillMdPath
    $hasName = Has-FmKey $skillMdPath 'name'
    $hasDesc = Has-FmKey $skillMdPath 'description'

    if ($isInit) {
        $ps1 = 'n/a'; $sh = 'n/a'
        $ok  = $hasMd -and $hasName -and $hasDesc
    } else {
        $ps1Path = Join-Path $d.FullName "scripts/$verb.ps1"
        $shPath  = Join-Path $d.FullName "scripts/$verb.sh"
        $hasPs1  = Test-Path $ps1Path
        $hasSh   = Test-Path $shPath
        $ps1 = if ($hasPs1) { 'yes' } else { 'MISSING' }
        $sh  = if ($hasSh)  { 'yes' } else { 'MISSING' }
        $ok  = $hasMd -and $hasName -and $hasDesc -and $hasPs1 -and $hasSh
    }

    $mdCell   = if ($hasMd)   { 'yes' } else { 'MISSING' }
    $nameCell = if ($hasName) { 'yes' } else { 'MISSING' }
    $descCell = if ($hasDesc) { 'yes' } else { 'MISSING' }
    $result   = if ($ok) { 'PASS' } else { 'FAIL'; }
    if (-not $ok) { $script:failCount++ }
    Row $skill $mdCell $nameCell $descCell $ps1 $sh $result
}

# --- report table ------------------------------------------------------------------
Write-Output "| skill | SKILL.md | name | description | verb.ps1 | verb.sh | result |"
Write-Output "|---|---|---|---|---|---|---|"
foreach ($r in $rows) {
    Write-Output ("| {0} | {1} | {2} | {3} | {4} | {5} | {6} |" -f `
        $r.skill, $r.'SKILL.md', $r.name, $r.description, $r.'verb.ps1', $r.'verb.sh', $r.result)
}
Write-Output ""
$total = $rows.Count
$passed = $total - $failCount
Write-Output "validate-skills: $passed/$total skills pass ($failCount failing)"
exit $(if ($failCount -gt 0) { 1 } else { 0 })
