<#
.SYNOPSIS
  ratm-recite — open a recitation HTML doc in the browser for the user to read.

.DESCRIPTION
  Presentation only. The agent authors the recap as HTML; this script opens it.
  Alignment ("aligned" / "change X") happens in chat, NOT in the page.
  No server, no ports, no buttons, no signal file. (See design RR1/RR2.)

  Two authoring modes:
    full-doc : pass a complete .html file        -> opened as-is
    fragment : pass a body fragment + -Wrap      -> wrapped in assets/shell.html for styling

.PARAMETER Html
  Path to the HTML the agent wrote. A complete document, or a body fragment if -Wrap.

.PARAMETER Title
  Page title + header text. Used only with -Wrap.

.PARAMETER Wrap
  Wrap the fragment in assets/shell.html (consistent styling). Omit to open Html as-is.

.PARAMETER NoOpen
  Compose/resolve only; do not launch the browser. For tests.

.OUTPUTS
  The absolute path of the opened HTML file (stdout), so headless/SSH users can open it manually.

.EXAMPLE
  pwsh -File recite.ps1 -Html C:\tmp\recap.html

.EXAMPLE
  pwsh -File recite.ps1 -Html body-fragment.html -Wrap -Title 'ratmac skill set'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Html,
    [string]$Title = 'Recitation',
    [switch]$Wrap,
    [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Html)) {
    throw "Html path not found: $Html"
}

# Resolve the temp scratch dir (RR4: never write into the repo).
$scratch = Join-Path $env:TEMP 'ratm-recite'
if (-not (Test-Path -LiteralPath $scratch)) {
    New-Item -ItemType Directory -Path $scratch -Force | Out-Null
}

if ($Wrap) {
    # Compose: fragment -> shell.html slot. Fixed output name (RRQ2: overwrite, reuse one tab).
    $shell = Join-Path $PSScriptRoot '..\assets\shell.html'
    if (-not (Test-Path -LiteralPath $shell)) {
        throw "shell.html not found for -Wrap: $shell"
    }
    $shellHtml   = Get-Content -LiteralPath $shell -Raw
    $fragment    = Get-Content -LiteralPath $Html  -Raw
    $composed    = $shellHtml.Replace('<!-- CONTENT_SLOT -->', $fragment).Replace('__TITLE__', $Title)
    $outFile     = Join-Path $scratch 'recite.html'
    Set-Content -LiteralPath $outFile -Value $composed -Encoding UTF8
}
else {
    # Full doc: use as-is. Resolve to an absolute path for a clean file:// open + stdout.
    $outFile = (Resolve-Path -LiteralPath $Html).Path
}

if (-not $NoOpen) {
    Start-Process $outFile | Out-Null
}

# Always print the path so the user can open it manually if the browser didn't launch.
Write-Output $outFile
