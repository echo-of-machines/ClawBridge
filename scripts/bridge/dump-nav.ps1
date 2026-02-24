# dump-nav.ps1 - Dump navigation/tab elements from Claude Desktop's UIA tree
. "$PSScriptRoot\preamble.ps1"

[ClawBridgeWin32]::SetScreenReaderFlag()
$visible = [ClawBridgeWin32]::EnsureVisible()
if (-not $visible) { Write-Output "ERROR:WINDOW_NOT_FOUND"; exit 1 }

$claudeWin = Find-ClaudeWindow
if (-not $claudeWin) { Write-Output "ERROR:UIA_WINDOW_NOT_FOUND"; exit 1 }

# Search for buttons, tabs, and navigation elements
$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$uia = [System.Windows.Automation.AutomationElement]

function Dump-Elements {
    param($element, [int]$depth = 0, [int]$maxDepth = 6)
    if ($depth -gt $maxDepth) { return }

    $indent = "  " * $depth
    $ct = $element.Current.ControlType.ProgrammaticName -replace "ControlType\.", ""
    $name = $element.Current.Name
    $cls = $element.Current.ClassName
    $aid = $element.Current.AutomationId

    # Show buttons, tabs, list items, and elements with interesting names
    $isInteresting = (
        $ct -eq "Button" -or
        $ct -eq "Tab" -or
        $ct -eq "TabItem" -or
        $ct -eq "MenuItem" -or
        $ct -eq "Hyperlink" -or
        $ct -eq "ListItem" -or
        ($name -and ($name -match "chat|cowork|code|project|home|new|switch|mode|tab|nav")) -or
        ($cls -and ($cls -match "nav|tab|sidebar|menu|header")) -or
        ($aid -and ($aid -match "nav|tab|sidebar|menu|header|mode"))
    )

    if ($isInteresting) {
        $parts = @("${indent}[$ct]")
        if ($name) { $parts += "Name='$name'" }
        if ($cls) { $parts += "Class='$cls'" }
        if ($aid) { $parts += "AId='$aid'" }
        $rect = $element.Current.BoundingRectangle
        if ($rect.Width -gt 0) {
            $parts += "@$([int]$rect.X),$([int]$rect.Y) $([int]$rect.Width)x$([int]$rect.Height)"
        }
        Write-Output ($parts -join " ")
    }

    $child = $walker.GetFirstChild($element)
    while ($child) {
        Dump-Elements $child ($depth + 1) $maxDepth
        $child = $walker.GetNextSibling($child)
    }
}

Write-Output "=== Claude Desktop Navigation Elements ==="
Dump-Elements $claudeWin 0 8
Write-Output "=== Done ==="
