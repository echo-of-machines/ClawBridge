# test-accessibility-triggers-v4.ps1 - Test Gemini's suggested triggers
# Key new ideas:
# 1. WM_GETOBJECT with lParam=1 (internal Chromium signal)
# 2. RegisterWindowMessage("IAccessible2_RegisterMessage")
# 3. Combination of SPI_SETSCREENREADER + WM_SETTINGCHANGE + WM_GETOBJECT(1)

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public class AccTriggerV4 {
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

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint action, uint param, ref bool pvParam, uint fWinIni);

    [DllImport("oleacc.dll")]
    public static extern int AccessibleObjectFromWindow(
        IntPtr hwnd, uint objId, ref Guid riid,
        [MarshalAs(UnmanagedType.IUnknown)] out object ppv);

    public const uint WM_GETOBJECT = 0x003D;
    public const uint WM_SETTINGCHANGE = 0x001A;
    public const uint SMTO_ABORTIFHUNG = 0x0002;
    public const uint OBJID_CLIENT = 0xFFFFFFFC;
    public const uint SPI_SETSCREENREADER = 0x0047;
    public const uint SPIF_UPDATEINIFILE = 0x01;
    public const uint SPIF_SENDCHANGE = 0x02;
    public static readonly IntPtr HWND_BROADCAST = new IntPtr(0xFFFF);

    static List<IntPtr> renderHosts = new List<IntPtr>();

    static bool EnumCB(IntPtr hWnd, IntPtr lParam) {
        var sb = new StringBuilder(256);
        GetClassName(hWnd, sb, 256);
        if (sb.ToString() == "Chrome_RenderWidgetHostHWND") {
            renderHosts.Add(hWnd);
        }
        EnumChildWindows(hWnd, EnumCB, IntPtr.Zero);
        return true;
    }

    public static IntPtr[] FindAllRenderHosts() {
        IntPtr main = FindWindow("Chrome_WidgetWin_1", "Claude");
        if (main == IntPtr.Zero) return new IntPtr[0];
        renderHosts.Clear();
        EnumChildWindows(main, EnumCB, IntPtr.Zero);
        return renderHosts.ToArray();
    }

    public static IntPtr GetMainWindow() {
        return FindWindow("Chrome_WidgetWin_1", "Claude");
    }

    // Method 1: WM_GETOBJECT with lParam=1 (Chromium internal signal)
    public static string TryLParam1(IntPtr hwnd) {
        IntPtr result = SendMessage(hwnd, WM_GETOBJECT, IntPtr.Zero, new IntPtr(1));
        return "WM_GETOBJECT(lParam=1) result=" + result;
    }

    // Method 2: IAccessible2_RegisterMessage
    public static string TryIA2Register(IntPtr hwnd) {
        uint msg = RegisterWindowMessage("IAccessible2_RegisterMessage");
        if (msg == 0) return "RegisterWindowMessage failed";
        IntPtr result = SendMessage(hwnd, msg, IntPtr.Zero, IntPtr.Zero);
        return "IA2_RegisterMessage (msg=" + msg + ") result=" + result;
    }

    // Method 3: Full combo - SPI flag + broadcast + WM_GETOBJECT(1)
    public static string TryFullCombo(IntPtr hwnd) {
        // Set screen reader flag
        bool val = true;
        SystemParametersInfo(SPI_SETSCREENREADER, 1, ref val, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);

        // Broadcast WM_SETTINGCHANGE
        IntPtr bcResult;
        SendMessageTimeout(HWND_BROADCAST, WM_SETTINGCHANGE, new IntPtr(SPI_SETSCREENREADER),
            IntPtr.Zero, SMTO_ABORTIFHUNG, 5000, out bcResult);

        System.Threading.Thread.Sleep(1000);

        // Now send WM_GETOBJECT with lParam=1
        IntPtr r1 = SendMessage(hwnd, WM_GETOBJECT, IntPtr.Zero, new IntPtr(1));

        // Also try OBJID_CLIENT
        IntPtr r2 = SendMessage(hwnd, WM_GETOBJECT, IntPtr.Zero, new IntPtr(unchecked((int)OBJID_CLIENT)));

        // Also try IAccessible2
        uint ia2msg = RegisterWindowMessage("IAccessible2_RegisterMessage");
        IntPtr r3 = IntPtr.Zero;
        if (ia2msg != 0) r3 = SendMessage(hwnd, ia2msg, IntPtr.Zero, IntPtr.Zero);

        // Also query IAccessible to establish COM connection
        Guid iid = new Guid("618736e0-3c3d-11cf-810c-00aa00389b71");
        object acc;
        int hr = AccessibleObjectFromWindow(hwnd, OBJID_CLIENT, ref iid, out acc);

        return "Combo: lParam1=" + r1 + " ObjClient=" + r2 + " IA2=" + r3 + " IAccHR=" + hr;
    }

    // Cleanup: unset screen reader flag
    public static void ClearScreenReaderFlag() {
        bool val = false;
        SystemParametersInfo(SPI_SETSCREENREADER, 0, ref val, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);
    }
}
"@

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

# Baseline
$baseline = Test-TreePopulated
Write-Output "Baseline: $baseline elements"
if ([int]$baseline -gt 10) {
    Write-Output "Tree already populated!"
    exit 0
}

$mainWin = [AccTriggerV4]::GetMainWindow()
$renderHosts = [AccTriggerV4]::FindAllRenderHosts()
Write-Output "Main window: $mainWin"
Write-Output "Render hosts: $($renderHosts -join ', ')"

# Test Method 1: WM_GETOBJECT with lParam=1 on ALL HWNDs
Write-Output ""
Write-Output "=== Method 1: WM_GETOBJECT(lParam=1) ==="
foreach ($rh in $renderHosts) {
    $r = [AccTriggerV4]::TryLParam1($rh)
    Write-Output "  RenderHost $rh : $r"
}
# Also try on main window
$r = [AccTriggerV4]::TryLParam1($mainWin)
Write-Output "  MainWindow: $r"
Start-Sleep -Seconds 2
$c1 = Test-TreePopulated
Write-Output "  Elements after: $c1"

# Test Method 2: IAccessible2_RegisterMessage
Write-Output ""
Write-Output "=== Method 2: IAccessible2_RegisterMessage ==="
foreach ($rh in $renderHosts) {
    $r = [AccTriggerV4]::TryIA2Register($rh)
    Write-Output "  RenderHost $rh : $r"
}
$r = [AccTriggerV4]::TryIA2Register($mainWin)
Write-Output "  MainWindow: $r"
Start-Sleep -Seconds 2
$c2 = Test-TreePopulated
Write-Output "  Elements after: $c2"

# Test Method 3: Full combo
Write-Output ""
Write-Output "=== Method 3: Full combo (SPI + broadcast + all messages) ==="
foreach ($rh in $renderHosts) {
    $r = [AccTriggerV4]::TryFullCombo($rh)
    Write-Output "  RenderHost $rh : $r"
}
Start-Sleep -Seconds 3
$c3 = Test-TreePopulated
Write-Output "  Elements after: $c3"

Write-Output ""
Write-Output "=== Summary ==="
Write-Output "  WM_GETOBJECT(1): $c1"
Write-Output "  IA2_RegisterMessage: $c2"
Write-Output "  Full combo: $c3"

if ([int]$c3 -le 10) {
    Write-Output ""
    Write-Output "=== All methods failed. Testing Silent Narrator ==="
    # Save current Narrator volume
    $savedVol = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Narrator" -Name "VoiceVolume" -ErrorAction SilentlyContinue).VoiceVolume
    Write-Output "  Saved Narrator volume: $savedVol"

    # Set volume to 0
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Narrator" -Name "VoiceVolume" -Value 0 -ErrorAction SilentlyContinue
    Write-Output "  Set Narrator volume to 0"

    # Start Narrator
    Write-Output "  Starting Narrator (muted)..."
    Start-Process "Narrator.exe"
    Start-Sleep -Seconds 3

    # Check tree
    $cNarrator = Test-TreePopulated
    Write-Output "  Elements with muted Narrator: $cNarrator"

    # Stop Narrator
    Stop-Process -Name "Narrator" -Force -ErrorAction SilentlyContinue
    Write-Output "  Narrator stopped"

    # Restore volume
    if ($null -ne $savedVol) {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Narrator" -Name "VoiceVolume" -Value $savedVol -ErrorAction SilentlyContinue
        Write-Output "  Restored Narrator volume to $savedVol"
    }

    Start-Sleep -Seconds 1
    $cAfter = Test-TreePopulated
    Write-Output "  Elements after Narrator stopped: $cAfter"
}
