# dump-all.ps1 - Dump ALL UIA elements from Claude Desktop (limited depth)
. "$PSScriptRoot\preamble.ps1"

[ClawBridgeWin32]::SetScreenReaderFlag()
$visible = [ClawBridgeWin32]::EnsureVisible()
if (-not $visible) { Write-Output "ERROR:WINDOW_NOT_FOUND"; exit 1 }

$claudeWin = Find-ClaudeWindow
if (-not $claudeWin) { Write-Output "ERROR:UIA_WINDOW_NOT_FOUND"; exit 1 }

$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$count = 0

function Dump-All {
    param($element, [int]$depth = 0, [int]$maxDepth = 5)
    if ($depth -gt $maxDepth) { return }

    $script:count++
    $indent = "  " * $depth
    $ct = $element.Current.ControlType.ProgrammaticName -replace "ControlType\.", ""
    $name = $element.Current.Name
    $cls = $element.Current.ClassName
    $aid = $element.Current.AutomationId

    $parts = @("${indent}[$ct]")
    if ($name) { $parts += "N='$($name.Substring(0, [Math]::Min($name.Length, 50)))'" }
    if ($cls) { $parts += "C='$($cls.Substring(0, [Math]::Min($cls.Length, 60)))'" }
    if ($aid) { $parts += "A='$aid'" }
    Write-Output ($parts -join " ")

    $child = $walker.GetFirstChild($element)
    while ($child) {
        Dump-All $child ($depth + 1) $maxDepth
        $child = $walker.GetNextSibling($child)
    }
}

Write-Output "=== Claude Desktop Full Tree (depth 5) ==="
Dump-All $claudeWin 0 5
Write-Output "=== $count elements ==="
