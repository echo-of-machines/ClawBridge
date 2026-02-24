# inspect-uia.ps1 — Inspect Claude Desktop's UI Automation tree
# Phase 1: Discover what elements are exposed via Windows Accessibility

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$auto = [System.Windows.Automation.AutomationElement]

# Find Claude Desktop window
$root = $auto::RootElement
$condition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::NameProperty,
    "Claude"
)

$claudeWindows = $root.FindAll(
    [System.Windows.Automation.TreeScope]::Children,
    $condition
)

if ($claudeWindows.Count -eq 0) {
    # Try partial match - look for windows containing "Claude" in the name
    $allWindows = $root.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.Condition]::TrueCondition
    )

    Write-Output "=== All top-level windows ==="
    foreach ($w in $allWindows) {
        $name = $w.Current.Name
        $cls = $w.Current.ClassName
        $ctrl = $w.Current.ControlType.ProgrammaticName
        if ($name -like "*Claude*" -or $name -like "*claude*") {
            Write-Output "  MATCH: Name='$name' Class='$cls' Control='$ctrl'"
        }
    }

    # Also try by process name
    $claudeProcs = Get-Process -Name claude -ErrorAction SilentlyContinue | Where-Object {
        $_.MainWindowHandle -ne [IntPtr]::Zero
    }

    if ($claudeProcs) {
        Write-Output "`n=== Claude processes with windows ==="
        foreach ($proc in $claudeProcs) {
            Write-Output "  PID=$($proc.Id) MainWindowTitle='$($proc.MainWindowTitle)' Handle=$($proc.MainWindowHandle)"

            # Try to get UIA element from window handle
            try {
                $hwnd = $proc.MainWindowHandle
                $elem = $auto::FromHandle($hwnd)
                if ($elem) {
                    Write-Output "  UIA Element found: Name='$($elem.Current.Name)' Class='$($elem.Current.ClassName)'"
                }
            } catch {
                Write-Output "  Could not get UIA element: $_"
            }
        }
    } else {
        Write-Output "`nNo Claude processes with visible windows found."
        Write-Output "Is Claude Desktop running?"
    }

    exit
}

$claudeWin = $claudeWindows[0]
Write-Output "=== Claude Desktop Window Found ==="
Write-Output "Name: $($claudeWin.Current.Name)"
Write-Output "ClassName: $($claudeWin.Current.ClassName)"
Write-Output "ControlType: $($claudeWin.Current.ControlType.ProgrammaticName)"
Write-Output "AutomationId: $($claudeWin.Current.AutomationId)"
Write-Output "BoundingRect: $($claudeWin.Current.BoundingRectangle)"

# Recursively walk the tree (limited depth to avoid flooding)
function Walk-UIA {
    param(
        [System.Windows.Automation.AutomationElement]$element,
        [int]$depth = 0,
        [int]$maxDepth = 4
    )

    if ($depth -gt $maxDepth) { return }

    $indent = "  " * $depth
    $name = $element.Current.Name
    $cls = $element.Current.ClassName
    $ctrl = $element.Current.ControlType.ProgrammaticName
    $aid = $element.Current.AutomationId

    # Truncate long names
    if ($name.Length -gt 80) { $name = $name.Substring(0, 80) + "..." }

    Write-Output "${indent}[$ctrl] Name='$name' Class='$cls' AutomationId='$aid'"

    # Show supported patterns (tells us what we can do with this element)
    $patterns = $element.GetSupportedPatterns()
    if ($patterns.Count -gt 0) {
        $patternNames = ($patterns | ForEach-Object { $_.ProgrammaticName }) -join ", "
        Write-Output "${indent}  Patterns: $patternNames"
    }

    # Get children
    try {
        $children = $element.FindAll(
            [System.Windows.Automation.TreeScope]::Children,
            [System.Windows.Automation.Condition]::TrueCondition
        )

        foreach ($child in $children) {
            Walk-UIA -element $child -depth ($depth + 1) -maxDepth $maxDepth
        }
    } catch {
        Write-Output "${indent}  (error enumerating children: $_)"
    }
}

Write-Output "`n=== UI Automation Tree (depth 4) ==="
Walk-UIA -element $claudeWin -depth 0 -maxDepth 4
