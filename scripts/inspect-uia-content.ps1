# inspect-uia-content.ps1 — Check Claude Desktop's WebView content

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

# Navigate directly: Window > RootView > NonClientView > WinFrameView > ClientView > View > View > View
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
    if (-not $nav) { Write-Output "Lost at $cls"; exit 1 }
}

# Now get WebView and RenderHost
$webView = Get-ChildByClass $nav "WebView"
$renderHost = Get-ChildByClass $nav "Chrome_RenderWidgetHostHWND"

Write-Output "WebView found: $($webView -ne $null)"
Write-Output "RenderHost found: $($renderHost -ne $null)"

# Check WebView children
if ($webView) {
    Write-Output "`n=== WebView children ==="
    $child = $tw.GetFirstChild($webView)
    $idx = 0
    while ($child -ne $null -and $idx -lt 50) {
        $name = $child.Current.Name
        if ($name.Length -gt 100) { $name = $name.Substring(0, 100) + "..." }
        Write-Output "  [$idx] Type=$($child.Current.ControlType.ProgrammaticName) Cls='$($child.Current.ClassName)' Name='$name' AId='$($child.Current.AutomationId)' Role='$($child.Current.AriaRole)'"
        try {
            $patterns = $child.GetSupportedPatterns()
            if ($patterns.Count -gt 0) {
                Write-Output "        Patterns: $(($patterns | ForEach-Object { $_.ProgrammaticName }) -join ', ')"
            }
        } catch {}
        $child = $tw.GetNextSibling($child)
        $idx++
    }
    if ($idx -eq 0) { Write-Output "  (no children)" }
}

# Check RenderHost children
if ($renderHost) {
    Write-Output "`n=== RenderHost children ==="
    $child = $tw.GetFirstChild($renderHost)
    $idx = 0
    while ($child -ne $null -and $idx -lt 50) {
        $name = $child.Current.Name
        if ($name.Length -gt 100) { $name = $name.Substring(0, 100) + "..." }
        Write-Output "  [$idx] Type=$($child.Current.ControlType.ProgrammaticName) Cls='$($child.Current.ClassName)' Name='$name' AId='$($child.Current.AutomationId)' Role='$($child.Current.AriaRole)'"

        # Walk one level deeper
        $grandchild = $tw.GetFirstChild($child)
        $gidx = 0
        while ($grandchild -ne $null -and $gidx -lt 20) {
            $gname = $grandchild.Current.Name
            if ($gname.Length -gt 80) { $gname = $gname.Substring(0, 80) + "..." }
            Write-Output "    [$gidx] Type=$($grandchild.Current.ControlType.ProgrammaticName) Cls='$($grandchild.Current.ClassName)' Name='$gname' Role='$($grandchild.Current.AriaRole)'"
            $grandchild = $tw.GetNextSibling($grandchild)
            $gidx++
        }

        $child = $tw.GetNextSibling($child)
        $idx++
    }
    if ($idx -eq 0) { Write-Output "  (no children)" }
}

# If both empty, the web content accessibility tree is not exposed
if (($webView -and $tw.GetFirstChild($webView) -eq $null) -and ($renderHost -and $tw.GetFirstChild($renderHost) -eq $null)) {
    Write-Output "`n=== FINDING: Web content accessibility is NOT enabled ==="
    Write-Output "Chromium only populates the accessibility tree when an assistive"
    Write-Output "technology is detected. Options to force it:"
    Write-Output "  1. --force-renderer-accessibility flag (but MSIX blocks CLI args)"
    Write-Output "  2. Set registry key to force Chromium accessibility"
    Write-Output "  3. Simulate an accessibility client connection"
}
