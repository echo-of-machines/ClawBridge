# inspect-uia-deep.ps1 — Deep inspection of Claude Desktop's UIA tree
# Forces accessibility and uses TreeWalker for Chromium content

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$auto = [System.Windows.Automation.AutomationElement]
$tw = [System.Windows.Automation.TreeWalker]::RawViewWalker

# Find Claude window by class name (more reliable)
$root = $auto::RootElement
$classCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ClassNameProperty,
    "Chrome_WidgetWin_1"
)

$chromeWindows = $root.FindAll(
    [System.Windows.Automation.TreeScope]::Children,
    $classCondition
)

$claudeWin = $null
foreach ($w in $chromeWindows) {
    if ($w.Current.Name -like "*Claude*") {
        $claudeWin = $w
        break
    }
}

if (-not $claudeWin) {
    Write-Output "Claude Desktop window not found"
    exit 1
}

Write-Output "=== Claude Desktop Window ==="
Write-Output "Name: $($claudeWin.Current.Name)"
Write-Output "Class: $($claudeWin.Current.ClassName)"
Write-Output "ProcessId: $($claudeWin.Current.ProcessId)"
Write-Output ""

# Walk using TreeWalker (better for dynamic Chromium trees)
function Walk-Tree {
    param(
        [System.Windows.Automation.AutomationElement]$element,
        [int]$depth = 0,
        [int]$maxDepth = 8
    )

    if ($depth -gt $maxDepth) {
        Write-Output ("  " * $depth + "(max depth reached)")
        return
    }

    $indent = "  " * $depth
    try {
        $name = $element.Current.Name
        $cls = $element.Current.ClassName
        $ctrl = $element.Current.ControlType.ProgrammaticName
        $aid = $element.Current.AutomationId
        $role = $element.Current.AriaRole
        $ariaProps = $element.Current.AriaProperties
    } catch {
        Write-Output "${indent}(stale element)"
        return
    }

    # Truncate long names
    $displayName = $name
    if ($displayName.Length -gt 100) { $displayName = $displayName.Substring(0, 100) + "..." }

    $line = "${indent}[$ctrl] Name='$displayName'"
    if ($cls) { $line += " Class='$cls'" }
    if ($aid) { $line += " AId='$aid'" }
    if ($role) { $line += " AriaRole='$role'" }
    Write-Output $line

    # Show patterns
    try {
        $patterns = $element.GetSupportedPatterns()
        if ($patterns.Count -gt 0) {
            $patternNames = ($patterns | ForEach-Object { $_.ProgrammaticName }) -join ", "
            Write-Output "${indent}  Patterns: $patternNames"
        }
    } catch {}

    # Walk children via TreeWalker
    try {
        $child = $tw.GetFirstChild($element)
        $childCount = 0
        while ($child -ne $null -and $childCount -lt 50) {
            Walk-Tree -element $child -depth ($depth + 1) -maxDepth $maxDepth
            $child = $tw.GetNextSibling($child)
            $childCount++
        }
        if ($childCount -ge 50) {
            Write-Output ("  " * ($depth + 1) + "... (50+ children, truncated)")
        }
    } catch {
        Write-Output "${indent}  (error walking children: $_)"
    }
}

Write-Output "=== Full UIA Tree (TreeWalker, depth 8) ==="
Walk-Tree -element $claudeWin -depth 0 -maxDepth 8
