# preamble.ps1 - Shared UIA helpers for ClawBridge scripts
# Dot-source this at the top of each bridge script: . "$PSScriptRoot\preamble.ps1"

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms

if (-not ([System.Management.Automation.PSTypeName]'ClawBridgeWin32').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class ClawBridgeWin32 {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int cmd);

    [DllImport("user32.dll")]
    public static extern void SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint flags, int dx, int dy, uint data, IntPtr extra);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint action, uint param, ref bool pvParam, uint fWinIni);

    [DllImport("shcore.dll")]
    public static extern int GetDpiForMonitor(IntPtr hMonitor, int dpiType, out uint dpiX, out uint dpiY);

    [DllImport("user32.dll")]
    public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);

    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public const int SW_RESTORE = 9;
    public const int SW_SHOW = 5;
    public const uint SPI_SETSCREENREADER = 0x0047;
    public const uint SPIF_UPDATEINIFILE = 0x01;
    public const uint SPIF_SENDCHANGE = 0x02;
    public const uint MONITOR_DEFAULTTONEAREST = 2;

    // Get DPI scale factor for the monitor containing the given window
    public static double GetScaleFactor(IntPtr hwnd) {
        try {
            IntPtr monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
            uint dpiX, dpiY;
            GetDpiForMonitor(monitor, 0, out dpiX, out dpiY);
            return dpiX / 96.0;
        } catch {
            return 1.0;
        }
    }

    // Click at UIA physical coordinates, adjusting for DPI-unaware process
    public static void Click(int physX, int physY, double scaleFactor) {
        // DPI-unaware process: SetCursorPos expects logical coords
        // UIA gives physical coords. Divide by scale to get logical.
        int logX = (int)(physX / scaleFactor);
        int logY = (int)(physY / scaleFactor);
        SetCursorPos(logX, logY);
        System.Threading.Thread.Sleep(50);
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, IntPtr.Zero);
        System.Threading.Thread.Sleep(50);
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, IntPtr.Zero);
    }

    // Legacy overload without scale factor (assumes 1.0)
    public static void Click(int x, int y) {
        Click(x, y, 1.0);
    }

    static IntPtr claudeHwnd = IntPtr.Zero;
    static bool FindCB(IntPtr hWnd, IntPtr lParam) {
        var sbCls = new StringBuilder(256);
        GetClassName(hWnd, sbCls, 256);
        if (sbCls.ToString() == "Chrome_WidgetWin_1") {
            var sbTitle = new StringBuilder(256);
            GetWindowText(hWnd, sbTitle, 256);
            if (sbTitle.ToString().Contains("Claude")) {
                claudeHwnd = hWnd;
                return false;
            }
        }
        return true;
    }

    public static IntPtr FindClaudeHwnd() {
        claudeHwnd = IntPtr.Zero;
        EnumWindows(FindCB, IntPtr.Zero);
        return claudeHwnd;
    }

    public static bool EnsureVisible() {
        IntPtr hwnd = FindClaudeHwnd();
        if (hwnd == IntPtr.Zero) return false;
        ShowWindow(hwnd, SW_RESTORE);
        ShowWindow(hwnd, SW_SHOW);
        return true;
    }

    public static void SetScreenReaderFlag() {
        bool val = true;
        SystemParametersInfo(SPI_SETSCREENREADER, 1, ref val, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);
    }
}
"@
}

$script:auto = [System.Windows.Automation.AutomationElement]
$script:tw = [System.Windows.Automation.TreeWalker]::RawViewWalker

# Get DPI scale factor for Claude's window
$script:dpiScale = 1.0
$hwnd = [ClawBridgeWin32]::FindClaudeHwnd()
if ($hwnd -ne [IntPtr]::Zero) {
    $script:dpiScale = [ClawBridgeWin32]::GetScaleFactor($hwnd)
}

function Find-ClaudeWindow {
    $root = $script:auto::RootElement
    $cc = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ClassNameProperty, "Chrome_WidgetWin_1"
    )
    $wins = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cc)
    foreach ($w in $wins) {
        if ($w.Current.Name -like "*Claude*") { return $w }
    }
    return $null
}

function Find-ByAutomationId($parent, [string]$aid, [int]$maxDepth = 15, [int]$depth = 0) {
    if ($depth -gt $maxDepth) { return $null }
    $child = $script:tw.GetFirstChild($parent)
    while ($null -ne $child) {
        try { if ($child.Current.AutomationId -eq $aid) { return $child } } catch {}
        $found = Find-ByAutomationId $child $aid $maxDepth ($depth + 1)
        if ($found) { return $found }
        $child = $script:tw.GetNextSibling($child)
    }
    return $null
}

function Find-ByClassContains($parent, [string]$substr, [int]$maxDepth = 15, [int]$depth = 0) {
    if ($depth -gt $maxDepth) { return $null }
    $child = $script:tw.GetFirstChild($parent)
    while ($null -ne $child) {
        try { if ($child.Current.ClassName -like "*$substr*") { return $child } } catch {}
        $found = Find-ByClassContains $child $substr $maxDepth ($depth + 1)
        if ($found) { return $found }
        $child = $script:tw.GetNextSibling($child)
    }
    return $null
}

function Find-ByName($parent, [string]$name, [string]$ctrlType, [int]$maxDepth = 15, [int]$depth = 0) {
    if ($depth -gt $maxDepth) { return $null }
    $child = $script:tw.GetFirstChild($parent)
    while ($null -ne $child) {
        try {
            if ($child.Current.Name -eq $name) {
                if (-not $ctrlType -or $child.Current.ControlType.ProgrammaticName -eq $ctrlType) {
                    return $child
                }
            }
        } catch {}
        $found = Find-ByName $child $name $ctrlType $maxDepth ($depth + 1)
        if ($found) { return $found }
        $child = $script:tw.GetNextSibling($child)
    }
    return $null
}
