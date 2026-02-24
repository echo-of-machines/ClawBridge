# inspect-uia-text.ps1 — Try reading text content from Claude Desktop's web content

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$auto = [System.Windows.Automation.AutomationElement]
$tw = [System.Windows.Automation.TreeWalker]::RawViewWalker

# Navigate to Claude > RenderHost > Document
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

$doc = $tw.GetFirstChild($renderHost)
if (-not $doc) { Write-Output "Document not found"; exit 1 }

Write-Output "=== Document Element ==="
Write-Output "Name: '$($doc.Current.Name)'"
Write-Output "AId: '$($doc.Current.AutomationId)'"
Write-Output "ControlType: $($doc.Current.ControlType.ProgrammaticName)"

# Try ValuePattern
Write-Output "`n=== ValuePattern ==="
try {
    $valuePattern = $doc.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    $value = $valuePattern.Current.Value
    if ($value.Length -gt 500) { $value = $value.Substring(0, 500) + "..." }
    Write-Output "Value: '$value'"
    Write-Output "IsReadOnly: $($valuePattern.Current.IsReadOnly)"
} catch {
    Write-Output "ValuePattern error: $_"
}

# Try TextPattern
Write-Output "`n=== TextPattern ==="
try {
    $textPattern = $doc.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
    $docRange = $textPattern.DocumentRange
    $text = $docRange.GetText(-1)
    if ($text.Length -gt 2000) {
        Write-Output "Text length: $($text.Length) chars"
        Write-Output "First 2000 chars:"
        Write-Output $text.Substring(0, 2000)
    } else {
        Write-Output "Text ($($text.Length) chars):"
        Write-Output $text
    }
} catch {
    Write-Output "TextPattern error: $_"
}

# Try ScrollPattern
Write-Output "`n=== ScrollPattern ==="
try {
    $scrollPattern = $doc.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
    Write-Output "HorizontalScrollPercent: $($scrollPattern.Current.HorizontalScrollPercent)"
    Write-Output "VerticalScrollPercent: $($scrollPattern.Current.VerticalScrollPercent)"
    Write-Output "HorizontalViewSize: $($scrollPattern.Current.HorizontalViewSize)"
    Write-Output "VerticalViewSize: $($scrollPattern.Current.VerticalViewSize)"
} catch {
    Write-Output "ScrollPattern error: $_"
}

# Also check the Group child
Write-Output "`n=== Group child ==="
$group = $tw.GetFirstChild($doc)
if ($group) {
    Write-Output "Name: '$($group.Current.Name)'"
    Write-Output "ControlType: $($group.Current.ControlType.ProgrammaticName)"
    Write-Output "AriaRole: '$($group.Current.AriaRole)'"

    try {
        $patterns = $group.GetSupportedPatterns()
        Write-Output "Patterns: $(($patterns | ForEach-Object { $_.ProgrammaticName }) -join ', ')"
    } catch {}

    # Walk group's children
    $child = $tw.GetFirstChild($group)
    $idx = 0
    while ($child -ne $null -and $idx -lt 30) {
        $name = $child.Current.Name
        if ($name.Length -gt 80) { $name = $name.Substring(0, 80) + "..." }
        Write-Output "  [$idx] $($child.Current.ControlType.ProgrammaticName) Name='$name' AId='$($child.Current.AutomationId)' Role='$($child.Current.AriaRole)'"
        $child = $tw.GetNextSibling($child)
        $idx++
    }
    if ($idx -eq 0) { Write-Output "  (no children)" }
}
