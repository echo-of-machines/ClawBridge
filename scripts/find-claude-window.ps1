# find-claude-window.ps1 - Find Claude Desktop's actual window
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$auto = [System.Windows.Automation.AutomationElement]
$tw = [System.Windows.Automation.TreeWalker]::RawViewWalker

# Method 1: List all Chrome_WidgetWin_1 windows
Write-Output "=== Chrome_WidgetWin_1 windows ==="
$root = $auto::RootElement
$cc = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ClassNameProperty, "Chrome_WidgetWin_1"
)
$wins = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cc)
foreach ($w in $wins) {
    Write-Output "  PID=$($w.Current.ProcessId) Name='$($w.Current.Name)' HWND=$($w.Current.NativeWindowHandle)"
}

# Method 2: Find windows by Claude Desktop process ID
Write-Output ""
Write-Output "=== Windows owned by Claude processes ==="
$claudeProcs = Get-Process -Name "Claude" -ErrorAction SilentlyContinue
if ($claudeProcs) {
    foreach ($p in $claudeProcs) {
        if ($p.MainWindowHandle -ne [IntPtr]::Zero) {
            Write-Output "  PID=$($p.Id) Title='$($p.MainWindowTitle)' HWND=$($p.MainWindowHandle)"
        }
    }
    # Also check by PID in UIA
    foreach ($w in $wins) {
        foreach ($p in $claudeProcs) {
            if ($w.Current.ProcessId -eq $p.Id) {
                Write-Output "  UIA match: PID=$($w.Current.ProcessId) Name='$($w.Current.Name)'"
            }
        }
    }
} else {
    Write-Output "  No Claude processes found"
}

# Method 3: Check ALL top-level windows for Claude PID
Write-Output ""
Write-Output "=== All top-level windows from Claude PIDs ==="
if ($claudeProcs) {
    $pids = $claudeProcs | ForEach-Object { $_.Id }
    $allWins = $root.FindAll([System.Windows.Automation.TreeScope]::Children,
        [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($w in $allWins) {
        if ($w.Current.ProcessId -in $pids) {
            Write-Output "  PID=$($w.Current.ProcessId) Class='$($w.Current.ClassName)' Name='$($w.Current.Name)'"
        }
    }
}
