# uninstall.ps1 — sever ratmac-* links from ~/.claude/skills. Source repo untouched.
[CmdletBinding()]
param(
    [string]$ClaudeDir = (Join-Path $env:USERPROFILE '.claude/skills'),
    [string[]]$Only,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $ClaudeDir)) { Write-Output "nothing to do: $ClaudeDir absent"; return }

$entries = Get-ChildItem -LiteralPath $ClaudeDir -Directory | Where-Object { $_.Name -like 'ratmac-*' }
if ($Only) { $entries = $entries | Where-Object { $Only -contains $_.Name } }

foreach ($e in $entries) {
    $item = Get-Item -LiteralPath $e.FullName -Force
    if ($item.LinkType) {
        Remove-Item -LiteralPath $e.FullName -Force -Recurse
        Write-Output "removed link: $($e.Name)"
    } else {
        # debug-mode mirror: real dir of per-file symlinks
        $files = Get-ChildItem -LiteralPath $e.FullName -Recurse -File
        $allLinks = ($files.Count -eq 0) -or (($files | Where-Object { -not (Get-Item $_.FullName -Force).LinkType }).Count -eq 0)
        if ($allLinks -or $Force) {
            Remove-Item -LiteralPath $e.FullName -Recurse -Force
            Write-Output "removed mirror dir: $($e.Name)"
        } else {
            Write-Output "STOP: $($e.Name) is a real dir with non-symlink files — pass -Force to delete"
        }
    }
}
Write-Output "uninstall complete."
