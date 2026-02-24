# test-accessibility-triggers-v2.ps1 - Test more aggressive accessibility triggers
# Chromium enables accessibility when it receives specific WM_GETOBJECT messages
# particularly with UiaRootObjectId lParam or IAccessible2 queries

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class AccTrigger {
    [DllImport("user32.dll")]
    public static extern IntPtr FindWindow(string cls, string wnd);

    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr parent, EnumWindowsProc cb, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam,
        uint flags, uint timeout, out IntPtr result);

    [DllImport("user32.dll")]
    public static extern uint RegisterWindowMessage(string msg);

    [DllImport("oleacc.dll")]
    public static extern int AccessibleObjectFromWindow(
        IntPtr hwnd, uint objId, ref Guid riid,
        [MarshalAs(UnmanagedType.IUnknown)] out object ppv);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint action, uint param, ref bool pvParam, uint fWinIni);

    public const uint WM_GETOBJECT = 0x003D;
    public const uint SMTO_ABORTIFHUNG = 0x0002;
    public const uint OBJID_CLIENT = 0xFFFFFFFC;
    public const uint OBJID_WINDOW = 0x00000000;
    public const uint OBJID_NATIVEOM = 0xFFFFFFF0;
    public const int UiaRootObjectId = -5;
    public const uint SPI_SETSCREENREADER = 0x0047;
    public const uint SPIF_SENDCHANGE = 0x02;

    static IntPtr renderHwnd = IntPtr.Zero;

    static bool EnumCB(IntPtr hWnd, IntPtr lParam) {
        var sb = new StringBuilder(256);
        GetClassName(hWnd, sb, 256);
        if (sb.ToString() == "Chrome_RenderWidgetHostHWND") {
            renderHwnd = hWnd;
        }
        EnumChildWindows(hWnd, EnumCB, IntPtr.Zero);
        return true;
    }

    public static IntPtr FindRenderHost() {
        IntPtr main = FindWindow("Chrome_WidgetWin_1", "Claude");
        if (main == IntPtr.Zero) return IntPtr.Zero;
        renderHwnd = IntPtr.Zero;
        EnumChildWindows(main, EnumCB, IntPtr.Zero);
        return renderHwnd;
    }

    public static string TriggerMethod1_UiaRootObjectId(IntPtr hwnd) {
        // Send WM_GETOBJECT with lParam = UiaRootObjectId (-5)
        // This is what UIA clients send to get the IRawElementProviderSimple
        IntPtr result;
        SendMessageTimeout(hwnd, WM_GETOBJECT, IntPtr.Zero, new IntPtr(UiaRootObjectId),
            SMTO_ABORTIFHUNG, 5000, out result);
        return "WM_GETOBJECT(UiaRootObjectId) result=" + result;
    }

    public static string TriggerMethod2_ObjIdClient(IntPtr hwnd) {
        // Standard IAccessible query
        IntPtr result;
        SendMessageTimeout(hwnd, WM_GETOBJECT, IntPtr.Zero, new IntPtr(unchecked((int)OBJID_CLIENT)),
            SMTO_ABORTIFHUNG, 5000, out result);
        return "WM_GETOBJECT(OBJID_CLIENT) result=" + result;
    }

    public static string TriggerMethod3_IAccessible2(IntPtr hwnd) {
        // IAccessible2 uses a registered window message
        uint ia2msg = RegisterWindowMessage("wireProtocol");
        if (ia2msg == 0) return "RegisterWindowMessage failed";
        IntPtr result;
        SendMessageTimeout(hwnd, ia2msg, IntPtr.Zero, IntPtr.Zero,
            SMTO_ABORTIFHUNG, 5000, out result);
        return "wireProtocol msg=" + ia2msg + " result=" + result;
    }

    public static string TriggerMethod4_IAccessibleFromWindow(IntPtr hwnd) {
        // Query IAccessible COM interface
        Guid iid = new Guid("618736e0-3c3d-11cf-810c-00aa00389b71");
        object acc;
        int hr = AccessibleObjectFromWindow(hwnd, OBJID_CLIENT, ref iid, out acc);
        string info = "IAccessible hr=" + hr;
        if (acc != null) info += " (got object)";
        return info;
    }

    public static string TriggerMethod5_ScreenReaderFlag() {
        bool val = true;
        bool ok = SystemParametersInfo(SPI_SETSCREENREADER, 1, ref val, SPIF_SENDCHANGE);
        return "SPI_SETSCREENREADER set=" + ok;
    }

    public static string TriggerMethod6_AutomationFromHandle(IntPtr hwnd) {
        // Use UIA AutomationElement.FromHandle - this should internally send WM_GETOBJECT
        try {
            var el = System.Windows.Automation.AutomationElement.FromHandle(hwnd);
            string name = el.Current.Name;
            string cls = el.Current.ClassName;
            int childCount = 0;
            var walker = System.Windows.Automation.TreeWalker.RawViewWalker;
            var child = walker.GetFirstChild(el);
            while (child != null) {
                childCount++;
                child = walker.GetNextSibling(child);
            }
            return "FromHandle: name='" + name + "' cls='" + cls + "' children=" + childCount;
        } catch (Exception ex) {
            return "FromHandle error: " + ex.Message;
        }
    }

    public static string TriggerMethod7_AllCombined(IntPtr hwnd) {
        // Set screen reader flag first
        bool val = true;
        SystemParametersInfo(SPI_SETSCREENREADER, 1, ref val, SPIF_SENDCHANGE);
        System.Threading.Thread.Sleep(500);

        // Send WM_GETOBJECT with UiaRootObjectId
        IntPtr r1;
        SendMessageTimeout(hwnd, WM_GETOBJECT, IntPtr.Zero, new IntPtr(UiaRootObjectId),
            SMTO_ABORTIFHUNG, 5000, out r1);

        // Send WM_GETOBJECT with OBJID_CLIENT
        IntPtr r2;
        SendMessageTimeout(hwnd, WM_GETOBJECT, IntPtr.Zero, new IntPtr(unchecked((int)OBJID_CLIENT)),
            SMTO_ABORTIFHUNG, 5000, out r2);

        // Query IAccessible
        Guid iid = new Guid("618736e0-3c3d-11cf-810c-00aa00389b71");
        object acc;
        AccessibleObjectFromWindow(hwnd, OBJID_CLIENT, ref iid, out acc);

        // IAccessible2 wireProtocol
        uint ia2msg = RegisterWindowMessage("wireProtocol");
        if (ia2msg != 0) {
            IntPtr r3;
            SendMessageTimeout(hwnd, ia2msg, IntPtr.Zero, IntPtr.Zero,
                SMTO_ABORTIFHUNG, 5000, out r3);
        }

        // UIA FromHandle
        try {
            var el = System.Windows.Automation.AutomationElement.FromHandle(hwnd);
            var walker = System.Windows.Automation.TreeWalker.RawViewWalker;
            var child = walker.GetFirstChild(el);
            int count = 0;
            while (child != null) { count++; child = walker.GetNextSibling(child); }
            return "Combined: UiaRoot=" + r1 + " ObjClient=" + r2 + " children=" + count;
        } catch (Exception ex) {
            return "Combined result: UiaRoot=" + r1 + " ObjClient=" + r2 + " err=" + ex.Message;
        }
    }
}
"@ -ReferencedAssemblies UIAutomationClient, UIAutomationTypes

$auto = [System.Windows.Automation.AutomationElement]
$tw = [System.Windows.Automation.TreeWalker]::RawViewWalker

function Test-TreePopulated {
    $root = $auto::RootElement
    $cc = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ClassNameProperty, "Chrome_WidgetWin_1"
    )
    $wins = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cc)
    $cw = $null
    foreach ($w in $wins) { if ($w.Current.Name -like "*Claude*") { $cw = $w; break } }
    if (-not $cw) { return "NO_WINDOW" }

    function GCC($p, $cn) { $c = $tw.GetFirstChild($p); while ($null -ne $c) { if ($c.Current.ClassName -eq $cn) { return $c }; $c = $tw.GetNextSibling($c) }; return $null }
    $nav = $cw
    foreach ($cls in @("RootView","NonClientView","WinFrameView","ClientView","View","View","View")) {
        $nav = GCC $nav $cls
        if (-not $nav) { return "NAV_FAIL" }
    }
    $rh = GCC $nav "Chrome_RenderWidgetHostHWND"
    if (-not $rh) { return "NO_RENDER" }
    $count = 0
    function Count-Elements($el, [int]$d = 0, [int]$max = 12) {
        if ($d -gt $max) { return }
        $c = $tw.GetFirstChild($el)
        while ($null -ne $c) { $script:count++; Count-Elements $c ($d+1) $max; $c = $tw.GetNextSibling($c) }
    }
    Count-Elements $rh
    return $count
}

# Find render host HWND
$renderHost = [AccTrigger]::FindRenderHost()
Write-Output "Render host HWND: $renderHost"
if ($renderHost -eq [IntPtr]::Zero) { Write-Output "ERROR: No render host found"; exit 1 }

# Baseline
$baseline = Test-TreePopulated
Write-Output "Baseline: $baseline elements"
if ([int]$baseline -gt 10) {
    Write-Output "Tree already populated!"
    exit 0
}

# Test each method individually with a pause
Write-Output ""
Write-Output "=== Method 1: WM_GETOBJECT with UiaRootObjectId ==="
$r = [AccTrigger]::TriggerMethod1_UiaRootObjectId($renderHost)
Write-Output "  $r"
Start-Sleep -Seconds 2
$c1 = Test-TreePopulated
Write-Output "  Elements: $c1"

Write-Output ""
Write-Output "=== Method 2: WM_GETOBJECT with OBJID_CLIENT ==="
$r = [AccTrigger]::TriggerMethod2_ObjIdClient($renderHost)
Write-Output "  $r"
Start-Sleep -Seconds 2
$c2 = Test-TreePopulated
Write-Output "  Elements: $c2"

Write-Output ""
Write-Output "=== Method 3: IAccessible2 wireProtocol ==="
$r = [AccTrigger]::TriggerMethod3_IAccessible2($renderHost)
Write-Output "  $r"
Start-Sleep -Seconds 2
$c3 = Test-TreePopulated
Write-Output "  Elements: $c3"

Write-Output ""
Write-Output "=== Method 4: AccessibleObjectFromWindow ==="
$r = [AccTrigger]::TriggerMethod4_IAccessibleFromWindow($renderHost)
Write-Output "  $r"
Start-Sleep -Seconds 2
$c4 = Test-TreePopulated
Write-Output "  Elements: $c4"

Write-Output ""
Write-Output "=== Method 5: SPI_SETSCREENREADER flag ==="
$r = [AccTrigger]::TriggerMethod5_ScreenReaderFlag()
Write-Output "  $r"
Start-Sleep -Seconds 2
$c5 = Test-TreePopulated
Write-Output "  Elements: $c5"

Write-Output ""
Write-Output "=== Method 6: UIA AutomationElement.FromHandle on render host ==="
$r = [AccTrigger]::TriggerMethod6_AutomationFromHandle($renderHost)
Write-Output "  $r"
Start-Sleep -Seconds 2
$c6 = Test-TreePopulated
Write-Output "  Elements: $c6"

Write-Output ""
Write-Output "=== Method 7: ALL methods combined ==="
$r = [AccTrigger]::TriggerMethod7_AllCombined($renderHost)
Write-Output "  $r"
Start-Sleep -Seconds 3
$c7 = Test-TreePopulated
Write-Output "  Elements: $c7"

Write-Output ""
Write-Output "=== Summary ==="
Write-Output "  UiaRootObjectId: $c1"
Write-Output "  OBJID_CLIENT: $c2"
Write-Output "  IAccessible2 wireProtocol: $c3"
Write-Output "  AccessibleObjectFromWindow: $c4"
Write-Output "  SPI_SETSCREENREADER: $c5"
Write-Output "  AutomationElement.FromHandle: $c6"
Write-Output "  All combined: $c7"
