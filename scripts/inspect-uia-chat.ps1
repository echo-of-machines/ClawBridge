# inspect-uia-chat.ps1 — Drill into the chat area of Claude Desktop

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$auto = [System.Windows.Automation.AutomationElement]
$tw = [System.Windows.Automation.TreeWalker]::RawViewWalker

# Navigate to Claude's inner document (the one with Name='Claude')
$root = $auto::RootElement
$classCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ClassNameProperty,
    "Chrome_WidgetWin_1"
)
$chromeWindows = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $classCondition)
$claudeWin = $null
foreach ($w in $chromeWindows) {
    if ($w.Current.Name -like "*Claude*") { $claudeWin = $w; break }
}
if (-not $claudeWin) { Write-Output "Claude window not found"; exit 1 }

# Find the inner RootWebArea with Name='Claude' (the actual app content, not the outer shell)
# It's at: RenderHost > RootWebArea(empty) > ... > RenderHost(2nd) > RootWebArea(Name='Claude')
# Use a deep walk to find it

function Find-Element {
    param($parent, [string]$matchAId, [string]$matchName, [string]$matchCtrl, [int]$maxDepth = 12, [int]$depth = 0)
    if ($depth -gt $maxDepth) { return $null }
    $child = $tw.GetFirstChild($parent)
    while ($child -ne $null) {
        try {
            $match = $true
            if ($matchAId -and $child.Current.AutomationId -ne $matchAId) { $match = $false }
            if ($matchName -and $child.Current.Name -ne $matchName) { $match = $false }
            if ($matchCtrl -and $child.Current.ControlType.ProgrammaticName -ne $matchCtrl) { $match = $false }
            if ($match) { return $child }
        } catch {}
        $found = Find-Element $child $matchAId $matchName $matchCtrl $maxDepth ($depth + 1)
        if ($found) { return $found }
        $child = $tw.GetNextSibling($child)
    }
    return $null
}

# Find main-content area
$mainContent = Find-Element $claudeWin "main-content" "" "" 15
if (-not $mainContent) {
    Write-Output "main-content not found. Accessibility may not be enabled."
    Write-Output "Ensure Narrator is running or screen reader flag is set."
    exit 1
}

Write-Output "=== Found main-content ==="
Write-Output "Cls: $($mainContent.Current.ClassName)"
Write-Output ""

# Deep walk of main-content
function Walk-Deep {
    param($element, [int]$depth = 0, [int]$maxDepth = 12)
    if ($depth -gt $maxDepth) { return }
    $indent = "  " * $depth
    try {
        $name = $element.Current.Name
        $ctrl = $element.Current.ControlType.ProgrammaticName -replace "ControlType\.", ""
        $aid = $element.Current.AutomationId
        $cls = $element.Current.ClassName

        # Shorten CSS class names - just show first class
        $clsShort = ""
        if ($cls) {
            $firstClass = ($cls -split "\s+")[0]
            if ($firstClass.Length -gt 40) { $firstClass = $firstClass.Substring(0, 40) + "..." }
            $clsShort = $firstClass
        }

        $displayName = $name
        if ($displayName.Length -gt 60) { $displayName = $displayName.Substring(0, 60) + "..." }

        $line = "${indent}[$ctrl]"
        if ($displayName) { $line += " '$displayName'" }
        if ($aid) { $line += " AId='$aid'" }
        if ($clsShort) { $line += " .$clsShort" }
        Write-Output $line

        # Show patterns for actionable elements
        $patterns = $element.GetSupportedPatterns()
        $interesting = $patterns | Where-Object {
            $_.ProgrammaticName -in @(
                "ValuePatternIdentifiers.Pattern",
                "InvokePatternIdentifiers.Pattern",
                "TextPatternIdentifiers.Pattern",
                "TogglePatternIdentifiers.Pattern",
                "SelectionItemPatternIdentifiers.Pattern"
            )
        }
        if ($interesting) {
            $pNames = ($interesting | ForEach-Object { $_.ProgrammaticName -replace "PatternIdentifiers\.Pattern", "" }) -join ", "
            Write-Output "${indent}  -> $pNames"
        }

        # For Value pattern, show the value
        if ($patterns | Where-Object { $_.ProgrammaticName -eq "ValuePatternIdentifiers.Pattern" }) {
            try {
                $vp = $element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
                $val = $vp.Current.Value
                if ($val -and $val.Length -gt 0) {
                    if ($val.Length -gt 80) { $val = $val.Substring(0, 80) + "..." }
                    Write-Output "${indent}  Value='$val'"
                }
            } catch {}
        }
    } catch { return }

    try {
        $child = $tw.GetFirstChild($element)
        $count = 0
        while ($child -ne $null -and $count -lt 100) {
            Walk-Deep $child ($depth + 1) $maxDepth
            $child = $tw.GetNextSibling($child)
            $count++
        }
    } catch {}
}

Write-Output "=== main-content subtree ==="
Walk-Deep $mainContent 0 12
