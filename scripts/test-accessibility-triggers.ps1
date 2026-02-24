# test-accessibility-triggers.ps1 - Test different ways to trigger Chromium accessibility
# without using Narrator

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$auto = [System.Windows.Automation.AutomationElement]
$tw = [System.Windows.Automation.TreeWalker]::RawViewWalker

# Helper to check if tree is populated
function Test-TreePopulated {
    $root = $auto::RootElement
    $cc = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ClassNameProperty, "Chrome_WidgetWin_1"
    )
    $wins = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cc)
    $cw = $null
    foreach ($w in $wins) { if ($w.Current.Name -like "*Claude*") { $cw = $w; break } }
    if (-not $cw) { return "NO_WINDOW" }

    # Navigate to the inner area and count elements
    function GCC($p, $cn) { $c = $tw.GetFirstChild($p); while ($null -ne $c) { if ($c.Current.ClassName -eq $cn) { return $c }; $c = $tw.GetNextSibling($c) }; return $null }
    $nav = $cw
    foreach ($cls in @("RootView","NonClientView","WinFrameView","ClientView","View","View","View")) {
        $nav = GCC $nav $cls
        if (-not $nav) { return "NAV_FAIL" }
    }
    $rh = GCC $nav "Chrome_RenderWidgetHostHWND"
    if (-not $rh) { return "NO_RENDER" }

    # Count total elements under render host (deep)
    $count = 0
    function Count-Elements($el, [int]$d = 0, [int]$max = 12) {
        if ($d -gt $max) { return }
        $c = $tw.GetFirstChild($el)
        while ($null -ne $c) { $script:count++; Count-Elements $c ($d+1) $max; $c = $tw.GetNextSibling($c) }
    }
    Count-Elements $rh
    return $count
}

# Baseline
$baseline = Test-TreePopulated
Write-Output "Baseline: $baseline elements"

if ([int]$baseline -gt 10) {
    Write-Output "Tree already populated! Accessibility is active."
    exit 0
}

# --- Test 1: Register UIA FocusChanged event handler ---
Write-Output "`n=== Test 1: UIA FocusChanged event handler ==="
$handler = {
    param($sender, $e)
    # do nothing - just having a handler registered should trigger Chromium
}
try {
    [System.Windows.Automation.Automation]::AddAutomationFocusChangedEventHandler(
        [System.Windows.Automation.AutomationFocusChangedEventHandler]$handler
    )
    Write-Output "  Registered FocusChanged handler"
    Start-Sleep -Seconds 3
    $result1 = Test-TreePopulated
    Write-Output "  Elements after FocusChanged handler: $result1"
    [System.Windows.Automation.Automation]::RemoveAutomationFocusChangedEventHandler(
        [System.Windows.Automation.AutomationFocusChangedEventHandler]$handler
    )
} catch {
    Write-Output "  Error: $_"
}

if ([int]$result1 -gt 10) {
    Write-Output "  SUCCESS! FocusChanged handler triggered accessibility."
    exit 0
}

# --- Test 2: Register UIA StructureChanged event handler ---
Write-Output "`n=== Test 2: UIA StructureChanged event handler ==="
$root = $auto::RootElement
$structHandler = {
    param($sender, $e)
    # do nothing
}
try {
    [System.Windows.Automation.Automation]::AddStructureChangedEventHandler(
        $root,
        [System.Windows.Automation.TreeScope]::Subtree,
        [System.Windows.Automation.StructureChangedEventHandler]$structHandler
    )
    Write-Output "  Registered StructureChanged handler"
    Start-Sleep -Seconds 3
    $result2 = Test-TreePopulated
    Write-Output "  Elements after StructureChanged handler: $result2"
    [System.Windows.Automation.Automation]::RemoveStructureChangedEventHandler(
        $root,
        [System.Windows.Automation.StructureChangedEventHandler]$structHandler
    )
} catch {
    Write-Output "  Error: $_"
}

if ([int]$result2 -gt 10) {
    Write-Output "  SUCCESS! StructureChanged handler triggered accessibility."
    exit 0
}

# --- Test 3: Register UIA PropertyChanged event handler ---
Write-Output "`n=== Test 3: UIA PropertyChanged event handler ==="
$propHandler = {
    param($sender, $e)
}
try {
    [System.Windows.Automation.Automation]::AddAutomationPropertyChangedEventHandler(
        $root,
        [System.Windows.Automation.TreeScope]::Subtree,
        [System.Windows.Automation.AutomationPropertyChangedEventHandler]$propHandler,
        [System.Windows.Automation.AutomationElement]::NameProperty
    )
    Write-Output "  Registered PropertyChanged handler"
    Start-Sleep -Seconds 3
    $result3 = Test-TreePopulated
    Write-Output "  Elements after PropertyChanged handler: $result3"
    [System.Windows.Automation.Automation]::RemoveAutomationPropertyChangedEventHandler(
        $root,
        [System.Windows.Automation.AutomationPropertyChangedEventHandler]$propHandler
    )
} catch {
    Write-Output "  Error: $_"
}

if ([int]$result3 -gt 10) {
    Write-Output "  SUCCESS! PropertyChanged handler triggered accessibility."
    exit 0
}

# --- Test 4: SetWinEventHook ---
Write-Output "`n=== Test 4: SetWinEventHook (Win32) ==="
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class WinEventHook {
    public delegate void WinEventDelegate(IntPtr hWinEventHook, uint eventType,
        IntPtr hwnd, int idObject, int idChild, uint dwEventThread, uint dwmsEventTime);

    [DllImport("user32.dll")]
    public static extern IntPtr SetWinEventHook(uint eventMin, uint eventMax,
        IntPtr hmodWinEventProc, WinEventDelegate lpfnWinEventProc,
        uint idProcess, uint idThread, uint dwFlags);

    [DllImport("user32.dll")]
    public static extern bool UnhookWinEvent(IntPtr hWinEventHook);

    public const uint EVENT_OBJECT_FOCUS = 0x8005;
    public const uint EVENT_OBJECT_NAMECHANGE = 0x800C;
    public const uint EVENT_OBJECT_SHOW = 0x8002;
    public const uint WINEVENT_OUTOFCONTEXT = 0x0000;

    public static WinEventDelegate Callback = (h, e, w, o, c, t, m) => { };
    public static IntPtr Hook = IntPtr.Zero;

    public static void Install() {
        Hook = SetWinEventHook(
            EVENT_OBJECT_FOCUS, EVENT_OBJECT_NAMECHANGE,
            IntPtr.Zero, Callback, 0, 0, WINEVENT_OUTOFCONTEXT
        );
    }

    public static void Uninstall() {
        if (Hook != IntPtr.Zero) UnhookWinEvent(Hook);
        Hook = IntPtr.Zero;
    }
}
"@
try {
    [WinEventHook]::Install()
    $hookOk = [WinEventHook]::Hook -ne [IntPtr]::Zero
    Write-Output "  SetWinEventHook installed: $hookOk"
    Start-Sleep -Seconds 3
    $result4 = Test-TreePopulated
    Write-Output "  Elements after WinEventHook: $result4"
    [WinEventHook]::Uninstall()
} catch {
    Write-Output "  Error: $_"
}

if ([int]$result4 -gt 10) {
    Write-Output "  SUCCESS! SetWinEventHook triggered accessibility."
    exit 0
}

Write-Output "`n=== No silent method worked. Summary ==="
Write-Output "  FocusChanged: $result1"
Write-Output "  StructureChanged: $result2"
Write-Output "  PropertyChanged: $result3"
Write-Output "  WinEventHook: $result4"
Write-Output ""
Write-Output "Fallback: Start Narrator briefly (3s), then stop."
