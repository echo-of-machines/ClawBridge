# inspect-uia-webview.ps1 — Drill into Claude Desktop's WebView content

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$auto = [System.Windows.Automation.AutomationElement]
$tw = [System.Windows.Automation.TreeWalker]::RawViewWalker

# Find Claude window
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
if (-not $claudeWin) { Write-Output "Not found"; exit 1 }

# Find the Chrome_RenderWidgetHostHWND - this is the actual web content host
$renderCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ClassNameProperty,
    "Chrome_RenderWidgetHostHWND"
)
$renderHost = $claudeWin.FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    $renderCondition
)

if (-not $renderHost) {
    Write-Output "Chrome_RenderWidgetHostHWND not found"

    # Try finding the WebView Document instead
    $docCondition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Document
    )
    $doc = $claudeWin.FindFirst(
        [System.Windows.Automation.TreeScope]::Descendants,
        $docCondition
    )
    if ($doc) {
        Write-Output "Found Document element instead"
        $renderHost = $doc
    } else {
        Write-Output "No web content elements found at all"
        exit 1
    }
}

Write-Output "=== Web Content Host ==="
Write-Output "Name: $($renderHost.Current.Name)"
Write-Output "Class: $($renderHost.Current.ClassName)"
Write-Output "ControlType: $($renderHost.Current.ControlType.ProgrammaticName)"
Write-Output "AutomationId: $($renderHost.Current.AutomationId)"
Write-Output ""

# Walk deeper from the render host
function Walk-Tree {
    param(
        [System.Windows.Automation.AutomationElement]$element,
        [int]$depth = 0,
        [int]$maxDepth = 12
    )

    if ($depth -gt $maxDepth) { return }

    $indent = "  " * $depth
    try {
        $name = $element.Current.Name
        $cls = $element.Current.ClassName
        $ctrl = $element.Current.ControlType.ProgrammaticName
        $aid = $element.Current.AutomationId
        $role = $element.Current.AriaRole
    } catch { return }

    $displayName = $name
    if ($displayName.Length -gt 120) { $displayName = $displayName.Substring(0, 120) + "..." }

    $line = "${indent}[$ctrl]"
    if ($displayName) { $line += " Name='$displayName'" }
    if ($cls) { $line += " Cls='$cls'" }
    if ($aid) { $line += " AId='$aid'" }
    if ($role) { $line += " Role='$role'" }
    Write-Output $line

    # Show patterns for interesting elements
    try {
        $patterns = $element.GetSupportedPatterns()
        if ($patterns.Count -gt 0) {
            $patternNames = ($patterns | ForEach-Object { $_.ProgrammaticName }) -join ", "
            Write-Output "${indent}  Patterns: $patternNames"
        }
    } catch {}

    # Walk children
    try {
        $child = $tw.GetFirstChild($element)
        $childCount = 0
        while ($child -ne $null -and $childCount -lt 100) {
            Walk-Tree -element $child -depth ($depth + 1) -maxDepth $maxDepth
            $child = $tw.GetNextSibling($child)
            $childCount++
        }
        if ($childCount -ge 100) {
            Write-Output ("  " * ($depth + 1) + "... (100+ children, truncated)")
        }
    } catch {}
}

Write-Output "=== WebView Content Tree (depth 12) ==="
Walk-Tree -element $renderHost -depth 0 -maxDepth 12
