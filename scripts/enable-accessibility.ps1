# enable-accessibility.ps1 — Enable Chromium accessibility for Claude Desktop
# Must be run before any UIA interaction with web content

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class AccessibilityEnabler {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, ref bool pvParam, uint fWinIni);

    [DllImport("user32.dll")]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll")]
    public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr childAfter, string cls, string wnd);

    [DllImport("oleacc.dll")]
    public static extern int AccessibleObjectFromWindow(
        IntPtr hwnd, uint dwId, ref Guid riid,
        [MarshalAs(UnmanagedType.IUnknown)] out object ppvObject);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr parentHandle, EnumWindowsProc callback, IntPtr lParam);

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder lpClassName, int nMaxCount);

    const uint SPI_SETSCREENREADER = 0x0047;
    const uint SPIF_SENDCHANGE = 0x02;
    const uint OBJID_CLIENT = 0xFFFFFFFC;
    const uint WM_GETOBJECT = 0x003D;

    static IntPtr foundRenderHwnd = IntPtr.Zero;

    static bool EnumCallback(IntPtr hWnd, IntPtr lParam) {
        var sb = new System.Text.StringBuilder(256);
        GetClassName(hWnd, sb, 256);
        string cls = sb.ToString();
        if (cls == "Chrome_RenderWidgetHostHWND") {
            foundRenderHwnd = hWnd;
            // Don't stop — find the LAST (innermost) one
        }
        // Recurse into children
        EnumChildWindows(hWnd, EnumCallback, IntPtr.Zero);
        return true;
    }

    public static string Enable() {
        // Step 1: Set screen reader flag
        bool val = true;
        SystemParametersInfo(SPI_SETSCREENREADER, 1, ref val, SPIF_SENDCHANGE);

        // Step 2: Find Claude window
        IntPtr mainHwnd = FindWindow("Chrome_WidgetWin_1", "Claude");
        if (mainHwnd == IntPtr.Zero) return "ERROR: Claude window not found";

        // Step 3: Find ALL Chrome_RenderWidgetHostHWND children (get innermost)
        foundRenderHwnd = IntPtr.Zero;
        EnumChildWindows(mainHwnd, EnumCallback, IntPtr.Zero);
        if (foundRenderHwnd == IntPtr.Zero) return "ERROR: No RenderWidgetHostHWND found";

        // Step 4: Send WM_GETOBJECT to trigger accessibility on the renderer
        SendMessage(foundRenderHwnd, WM_GETOBJECT, IntPtr.Zero, IntPtr.Zero);
        SendMessage(foundRenderHwnd, WM_GETOBJECT, IntPtr.Zero, new IntPtr(1));

        // Step 5: Query IAccessible on the renderer HWND
        Guid iid = new Guid("618736e0-3c3d-11cf-810c-00aa00389b71");
        object acc;
        int hr = AccessibleObjectFromWindow(foundRenderHwnd, OBJID_CLIENT, ref iid, out acc);

        return "OK: RenderHWND=" + foundRenderHwnd + " IAccessible.hr=" + hr;
    }
}
"@

$result = [AccessibilityEnabler]::Enable()
Write-Output $result

# Give Chromium a moment to build the tree
Start-Sleep -Seconds 2

# Verify by checking if main-content exists
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$tw = [System.Windows.Automation.TreeWalker]::RawViewWalker
$auto = [System.Windows.Automation.AutomationElement]

$root = $auto::RootElement
$classCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ClassNameProperty, "Chrome_WidgetWin_1"
)
$chromeWindows = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $classCondition)
$claudeWin = $null
foreach ($w in $chromeWindows) {
    if ($w.Current.Name -like "*Claude*") { $claudeWin = $w; break }
}

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
    if (-not $nav) { Write-Output "VERIFY FAILED: lost at $cls"; exit 1 }
}
$renderHost = Get-ChildByClass $nav "Chrome_RenderWidgetHostHWND"
$doc = $tw.GetFirstChild($renderHost)
$child = $tw.GetFirstChild($doc)
$childCount = 0
while ($child -ne $null) { $childCount++; $child = $tw.GetNextSibling($child) }

if ($childCount -le 1) {
    Write-Output "VERIFY: Tree still sparse ($childCount children). Starting Narrator briefly..."
    Start-Process narrator.exe
    Start-Sleep -Seconds 3
    Stop-Process -Name Narrator -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Write-Output "VERIFY: Narrator triggered and stopped. Re-checking..."

    # Re-check
    $doc = $tw.GetFirstChild($renderHost)
    $child = $tw.GetFirstChild($doc)
    $childCount = 0
    while ($child -ne $null) { $childCount++; $child = $tw.GetNextSibling($child) }
    Write-Output "VERIFY: Now $childCount children under outer doc"
} else {
    Write-Output "VERIFY: Tree populated ($childCount children)"
}
