# inspect-uia-walk.ps1 — Walk to Claude Desktop's web content via TreeWalker only

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

Write-Output "Found Claude window (PID: $($claudeWin.Current.ProcessId))"

# Navigate manually: Window > RootView > NonClientView > WinFrameView > ClientView > View > View > View > WebView/RenderHost
# Use TreeWalker the whole way

function Find-ChildByClass {
    param($parent, $className)
    $child = $tw.GetFirstChild($parent)
    while ($child -ne $null) {
        if ($child.Current.ClassName -eq $className) { return $child }
        $child = $tw.GetNextSibling($child)
    }
    return $null
}

function Find-ChildByControlType {
    param($parent, $typeName)
    $child = $tw.GetFirstChild($parent)
    while ($child -ne $null) {
        if ($child.Current.ControlType.ProgrammaticName -eq $typeName) { return $child }
        $child = $tw.GetNextSibling($child)
    }
    return $null
}

# Navigate to WebView
$rootView = Find-ChildByClass $claudeWin "RootView"
if (-not $rootView) { Write-Output "RootView not found"; exit 1 }
Write-Output "  -> RootView"

$ncView = Find-ChildByClass $rootView "NonClientView"
if (-not $ncView) { Write-Output "NonClientView not found"; exit 1 }
Write-Output "  -> NonClientView"

$frameView = Find-ChildByClass $ncView "WinFrameView"
if (-not $frameView) { Write-Output "WinFrameView not found"; exit 1 }
Write-Output "  -> WinFrameView"

$clientView = Find-ChildByClass $frameView "ClientView"
if (-not $clientView) { Write-Output "ClientView not found"; exit 1 }
Write-Output "  -> ClientView"

# From ClientView, walk through View layers
$current = $clientView
for ($i = 0; $i -lt 5; $i++) {
    $view = Find-ChildByClass $current "View"
    if (-not $view) { break }
    Write-Output "  -> View ($i)"
    $current = $view
}

# List all children of the deepest View
Write-Output "`n=== Children of deepest container ==="
$child = $tw.GetFirstChild($current)
$idx = 0
while ($child -ne $null) {
    Write-Output "  [$idx] ControlType=$($child.Current.ControlType.ProgrammaticName) Class='$($child.Current.ClassName)' Name='$($child.Current.Name)'"
    $child = $tw.GetNextSibling($child)
    $idx++
}

# Now find WebView and Chrome_RenderWidgetHostHWND specifically
Write-Output "`n=== Looking for WebView and RenderHost ==="

# Search all descendants by walking recursively
function Find-All-ByClass {
    param($parent, $className, [int]$maxDepth = 6, [int]$depth = 0)
    if ($depth -gt $maxDepth) { return }
    $child = $tw.GetFirstChild($parent)
    while ($child -ne $null) {
        if ($child.Current.ClassName -eq $className) {
            Write-Output "  FOUND '$className' at depth $depth"
            return $child
        }
        $result = Find-All-ByClass $child $className $maxDepth ($depth + 1)
        if ($result) { return $result }
        $child = $tw.GetNextSibling($child)
    }
    return $null
}

$webView = Find-All-ByClass $clientView "WebView" 8
$renderHost = Find-All-ByClass $clientView "Chrome_RenderWidgetHostHWND" 8

if ($webView) {
    Write-Output "`n=== WebView children ==="
    $child = $tw.GetFirstChild($webView)
    $idx = 0
    while ($child -ne $null -and $idx -lt 50) {
        $name = $child.Current.Name
        if ($name.Length -gt 100) { $name = $name.Substring(0, 100) + "..." }
        Write-Output "  [$idx] Type=$($child.Current.ControlType.ProgrammaticName) Class='$($child.Current.ClassName)' Name='$name' Role='$($child.Current.AriaRole)'"
        $patterns = $child.GetSupportedPatterns()
        if ($patterns.Count -gt 0) {
            Write-Output "        Patterns: $(($patterns | ForEach-Object { $_.ProgrammaticName }) -join ', ')"
        }
        $child = $tw.GetNextSibling($child)
        $idx++
    }
    if ($idx -eq 0) { Write-Output "  (no children - accessibility may not be enabled)" }
}

if ($renderHost) {
    Write-Output "`n=== Chrome_RenderWidgetHostHWND children ==="
    $child = $tw.GetFirstChild($renderHost)
    $idx = 0
    while ($child -ne $null -and $idx -lt 50) {
        $name = $child.Current.Name
        if ($name.Length -gt 100) { $name = $name.Substring(0, 100) + "..." }
        Write-Output "  [$idx] Type=$($child.Current.ControlType.ProgrammaticName) Class='$($child.Current.ClassName)' Name='$name' Role='$($child.Current.AriaRole)'"
        $child = $tw.GetNextSibling($child)
        $idx++
    }
    if ($idx -eq 0) { Write-Output "  (no children - accessibility may not be enabled)" }
}
