# inspect-uia-dom.ps1 — Walk Claude Desktop's web DOM via UIA

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
if (-not $claudeWin) { Write-Output "Claude window not found"; exit 1 }

# Navigate to RenderHost
function Get-ChildByClass($parent, $className) {
    $c = $tw.GetFirstChild($parent)
    while ($c -ne $null) {
        if ($c.Current.ClassName -eq $className) { return $c }
        $c = $tw.GetNextSibling($c)
    }
    return $null
}

$nav = $claudeWin
foreach ($cls in @("RootView", "NonClientView", "WinFrameView", "ClientView", "View", "View", "View")) {
    $nav = Get-ChildByClass $nav $cls
    if (-not $nav) { Write-Output "Navigation failed at $cls"; exit 1 }
}

$renderHost = Get-ChildByClass $nav "Chrome_RenderWidgetHostHWND"
if (-not $renderHost) { Write-Output "RenderHost not found"; exit 1 }

# Get the Document (RootWebArea)
$doc = $tw.GetFirstChild($renderHost)
if (-not $doc) { Write-Output "Document not found"; exit 1 }

Write-Output "=== RootWebArea Document ==="
Write-Output "Name: '$($doc.Current.Name)' AId: '$($doc.Current.AutomationId)'"
Write-Output ""

# Full recursive walk of the web content
function Walk-WebContent {
    param(
        [System.Windows.Automation.AutomationElement]$element,
        [int]$depth = 0,
        [int]$maxDepth = 10
    )

    if ($depth -gt $maxDepth) { return }

    $indent = "  " * $depth
    try {
        $name = $element.Current.Name
        $ctrl = $element.Current.ControlType.ProgrammaticName
        $aid = $element.Current.AutomationId
        $cls = $element.Current.ClassName
        $role = $element.Current.AriaRole
    } catch { return }

    $displayName = $name
    if ($displayName.Length -gt 80) { $displayName = $displayName.Substring(0, 80) + "..." }

    # Build output line
    $ctrlShort = $ctrl -replace "ControlType\.", ""
    $line = "${indent}[$ctrlShort]"
    if ($displayName) { $line += " '$displayName'" }
    if ($aid) { $line += " AId='$aid'" }
    if ($role) { $line += " role='$role'" }
    if ($cls) { $line += " cls='$cls'" }
    Write-Output $line

    # Show patterns for actionable elements
    try {
        $patterns = $element.GetSupportedPatterns()
        if ($patterns.Count -gt 0) {
            $interesting = @("ValuePatternIdentifiers.Pattern", "InvokePatternIdentifiers.Pattern",
                            "TextPatternIdentifiers.Pattern", "TogglePatternIdentifiers.Pattern",
                            "ScrollPatternIdentifiers.Pattern", "SelectionItemPatternIdentifiers.Pattern")
            $found = $patterns | Where-Object { $interesting -contains $_.ProgrammaticName }
            if ($found) {
                $patternNames = ($found | ForEach-Object { $_.ProgrammaticName -replace "PatternIdentifiers\.Pattern", "" }) -join ", "
                Write-Output "${indent}  -> Patterns: $patternNames"
            }
        }
    } catch {}

    # Walk children
    try {
        $child = $tw.GetFirstChild($element)
        $childCount = 0
        while ($child -ne $null -and $childCount -lt 80) {
            Walk-WebContent -element $child -depth ($depth + 1) -maxDepth $maxDepth
            $child = $tw.GetNextSibling($child)
            $childCount++
        }
        if ($childCount -ge 80) {
            Write-Output ("  " * ($depth + 1) + "... (80+ siblings, truncated)")
        }
    } catch {}
}

Write-Output "=== Web DOM Tree ==="
Walk-WebContent -element $doc -depth 0 -maxDepth 10
