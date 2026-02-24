# inspect-uia-conversation.ps1 - Inspect the conversation area to find message elements

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$auto = [System.Windows.Automation.AutomationElement]
$tw = [System.Windows.Automation.TreeWalker]::RawViewWalker

# Find Claude window
$root = $auto::RootElement
$classCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ClassNameProperty, "Chrome_WidgetWin_1"
)
$chromeWindows = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $classCondition)
$claudeWin = $null
foreach ($w in $chromeWindows) {
    if ($w.Current.Name -like "*Claude*") { $claudeWin = $w; break }
}
if (-not $claudeWin) { Write-Output "Claude window not found"; exit 1 }

function Find-ByAutomationId($parent, [string]$aid, [int]$maxDepth = 15, [int]$depth = 0) {
    if ($depth -gt $maxDepth) { return $null }
    $child = $tw.GetFirstChild($parent)
    while ($null -ne $child) {
        try { if ($child.Current.AutomationId -eq $aid) { return $child } } catch {}
        $found = Find-ByAutomationId $child $aid $maxDepth ($depth + 1)
        if ($found) { return $found }
        $child = $tw.GetNextSibling($child)
    }
    return $null
}

$mainContent = Find-ByAutomationId $claudeWin "main-content" 15
if (-not $mainContent) { Write-Output "main-content not found"; exit 1 }

# Walk the FULL main-content tree deeply, looking for text elements with message content
function Walk-Deep {
    param($element, [int]$depth = 0, [int]$maxDepth = 20)
    if ($depth -gt $maxDepth) { return }
    $indent = "  " * [Math]::Min($depth, 15)
    try {
        $name = $element.Current.Name
        $ctrl = $element.Current.ControlType.ProgrammaticName -replace "ControlType\.", ""
        $aid = $element.Current.AutomationId
        $cls = $element.Current.ClassName

        # Shorten class
        $clsShort = ""
        if ($cls) {
            $firstCls = ($cls -split "\s+")[0]
            if ($firstCls.Length -gt 50) { $firstCls = $firstCls.Substring(0, 50) + "..." }
            $clsShort = $firstCls
        }

        $displayName = $name
        if ($displayName.Length -gt 80) { $displayName = $displayName.Substring(0, 80) + "..." }

        # Only output if element has interesting properties
        $isInteresting = ($displayName -and $displayName.Length -gt 0) -or
                         ($aid -and $aid.Length -gt 0) -or
                         ($ctrl -notin @("Group", "Pane")) -or
                         ($clsShort -like "*message*") -or
                         ($clsShort -like "*font-claude*") -or
                         ($clsShort -like "*chat*") -or
                         ($clsShort -like "*conversation*") -or
                         ($clsShort -like "*reply*") -or
                         ($clsShort -like "*response*")

        if ($isInteresting) {
            $line = "${indent}[d=$depth $ctrl]"
            if ($displayName) { $line += " '$displayName'" }
            if ($aid) { $line += " AId='$aid'" }
            if ($clsShort) { $line += " .$clsShort" }

            # Show patterns
            $patterns = $element.GetSupportedPatterns()
            $pats = @()
            foreach ($p in $patterns) {
                $pn = $p.ProgrammaticName -replace "PatternIdentifiers\.Pattern", ""
                if ($pn -in @("Value", "Text", "Invoke", "Toggle", "Scroll")) { $pats += $pn }
            }
            if ($pats.Count -gt 0) { $line += " [" + ($pats -join ",") + "]" }

            Write-Output $line
        }
    } catch { return }

    try {
        $child = $tw.GetFirstChild($element)
        $count = 0
        while ($null -ne $child -and $count -lt 100) {
            Walk-Deep $child ($depth + 1) $maxDepth
            $child = $tw.GetNextSibling($child)
            $count++
        }
    } catch {}
}

Write-Output "=== Conversation tree (showing named/interesting elements) ==="
Walk-Deep $mainContent 0 20
