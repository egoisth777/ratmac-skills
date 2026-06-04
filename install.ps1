# install.ps1 — symlink ratmac-* skills into ~/.claude/skills for live update + self-evolution.
# develop = per-skill DIR symlink (whole-skill swap). debug = per-file symlink (hot single-file edit).
# Symlinks require Windows developer mode OR an elevated shell on first run. Junction fallback for develop.
[CmdletBinding()]
param(
    [ValidateSet('develop','debug')][string]$Mode = 'develop',
    [string]$ClaudeDir = (Join-Path $env:USERPROFILE '.claude/skills'),
    [string[]]$Only,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
$srcSkills = Join-Path $PSScriptRoot 'skills'

if (-not (Test-Path $ClaudeDir)) { New-Item -ItemType Directory -Force -Path $ClaudeDir | Out-Null }

function New-Link {
    param([string]$Path, [string]$Target, [string]$Type)  # Type: SymbolicLink | Junction
    New-Item -ItemType $Type -Path $Path -Target $Target -ErrorAction Stop | Out-Null
}

$skillDirs = Get-ChildItem -LiteralPath $srcSkills -Directory | Where-Object { $_.Name -like 'ratmac-*' }
if ($Only) { $skillDirs = $skillDirs | Where-Object { $Only -contains $_.Name } }

$results = @()
foreach ($sd in $skillDirs) {
    $name   = $sd.Name
    $source = $sd.FullName
    $target = Join-Path $ClaudeDir $name

    # existing target handling
    if (Test-Path $target) {
        $item = Get-Item -LiteralPath $target -Force
        $isLink = $item.LinkType -ne $null
        if ($isLink) {
            $existingTarget = (Get-Item -LiteralPath $target -Force).Target
            if ($existingTarget -and ((Resolve-Path $existingTarget -ErrorAction SilentlyContinue).Path -eq $source) -and $Mode -eq 'develop') {
                $results += "no-op:  $name (already linked)"; continue
            }
            if ($Force) { Remove-Item -LiteralPath $target -Force -Recurse }
            else { $results += "WARN:   $name exists as link to '$existingTarget' — pass -Force to relink"; continue }
        } else {
            if ($Force) { Remove-Item -LiteralPath $target -Force -Recurse }
            else { $results += "STOP:   $name exists as a REAL dir — refusing to destroy. Inspect, then -Force."; continue }
        }
    }

    if ($Mode -eq 'develop') {
        try { New-Link -Path $target -Target $source -Type 'SymbolicLink'; $results += "linked: $name -> $source (symlink)" }
        catch {
            try { New-Link -Path $target -Target $source -Type 'Junction'; $results += "linked: $name -> $source (junction fallback)" }
            catch { $results += "ERROR:  $name — symlink+junction both failed: $($_.Exception.Message)" }
        }
    }
    else {  # debug: mirror dir tree, per-file symlink
        New-Item -ItemType Directory -Force -Path $target | Out-Null
        Get-ChildItem -LiteralPath $source -Recurse -Directory | ForEach-Object {
            $rel = $_.FullName.Substring($source.Length).TrimStart('\','/')
            New-Item -ItemType Directory -Force -Path (Join-Path $target $rel) | Out-Null
        }
        $n = 0
        Get-ChildItem -LiteralPath $source -Recurse -File | ForEach-Object {
            $rel = $_.FullName.Substring($source.Length).TrimStart('\','/')
            $dst = Join-Path $target $rel
            if (Test-Path $dst) { Remove-Item -LiteralPath $dst -Force }
            try { New-Link -Path $dst -Target $_.FullName -Type 'SymbolicLink'; $n++ }
            catch { $results += "ERROR:  $name/$rel — $($_.Exception.Message)" }
        }
        $results += "mirrored: $name ($n files linked)"
    }
}

$results | ForEach-Object { Write-Output $_ }
Write-Output ""
Write-Output "Mode: $Mode | ClaudeDir: $ClaudeDir | skills: $($skillDirs.Count)"
Write-Output "Restart Claude Code (or /skills reload) to discover."
