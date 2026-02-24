# test-accessibility-triggers-v3.ps1 - Deeper investigation of accessibility triggers
# Try: native COM IUIAutomation, all child HWNDs, active tree walking

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public class AccTriggerV3 {
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

    [DllImport("oleacc.dll")]
    public static extern int AccessibleObjectFromWindow(
        IntPtr hwnd, uint objId, ref Guid riid,
        [MarshalAs(UnmanagedType.IUnknown)] out object ppv);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint action, uint param, ref bool pvParam, uint fWinIni);

    [DllImport("oleacc.dll")]
    public static extern uint GetRoleText(uint role, StringBuilder text, uint cchTextMax);

    // UIA COM interface IDs
    public static readonly Guid CLSID_CUIAutomation8 = new Guid("E22AD333-B25F-460C-83D0-0581107395C9");
    public static readonly Guid CLSID_CUIAutomation = new Guid("FF48DBA4-60EF-4201-AA87-54103EEF594E");

    public const uint WM_GETOBJECT = 0x003D;
    public const uint SMTO_ABORTIFHUNG = 0x0002;
    public const uint OBJID_CLIENT = 0xFFFFFFFC;
    public const int UiaRootObjectId = -5;
    public const uint SPI_SETSCREENREADER = 0x0047;
    public const uint SPI_GETSCREENREADER = 0x0046;
    public const uint SPIF_SENDCHANGE = 0x02;

    public static List<string> childHwnds = new List<string>();

    static bool EnumCB(IntPtr hWnd, IntPtr lParam) {
        var sb = new StringBuilder(256);
        GetClassName(hWnd, sb, 256);
        string cls = sb.ToString();
        childHwnds.Add(hWnd.ToString() + " " + cls);
        EnumChildWindows(hWnd, EnumCB, IntPtr.Zero);
        return true;
    }

    public static string[] EnumAllChildren() {
        IntPtr main = FindWindow("Chrome_WidgetWin_1", "Claude");
        if (main == IntPtr.Zero) {
            // Try partial match
            return new string[] { "ERROR: Claude window not found" };
        }
        childHwnds.Clear();
        childHwnds.Add(main.ToString() + " Chrome_WidgetWin_1 (MAIN)");
        EnumChildWindows(main, EnumCB, IntPtr.Zero);
        return childHwnds.ToArray();
    }

    public static string TryWmGetObject(IntPtr hwnd) {
        IntPtr r1, r2;
        SendMessageTimeout(hwnd, WM_GETOBJECT, IntPtr.Zero, new IntPtr(UiaRootObjectId),
            SMTO_ABORTIFHUNG, 2000, out r1);
        SendMessageTimeout(hwnd, WM_GETOBJECT, IntPtr.Zero, new IntPtr(unchecked((int)OBJID_CLIENT)),
            SMTO_ABORTIFHUNG, 2000, out r2);
        return "UIA=" + r1 + " MSAA=" + r2;
    }

    public static bool IsScreenReaderFlagSet() {
        bool val = false;
        SystemParametersInfo(SPI_GETSCREENREADER, 0, ref val, 0);
        return val;
    }

    public static string QueryIAccessible(IntPtr hwnd) {
        Guid iidAcc = new Guid("618736e0-3c3d-11cf-810c-00aa00389b71");
        object acc;
        int hr = AccessibleObjectFromWindow(hwnd, OBJID_CLIENT, ref iidAcc, out acc);
        if (hr != 0) return "hr=" + hr + " (failed)";

        try {
            // Try to query IAccessible methods via reflection/COM
            Type t = acc.GetType();
            // accChildCount
            object childCount = t.InvokeMember("accChildCount",
                System.Reflection.BindingFlags.GetProperty, null, acc, null);
            // accName
            string name = "";
            try {
                object n = t.InvokeMember("accName",
                    System.Reflection.BindingFlags.GetProperty, null, acc, new object[] { 0 });
                if (n != null) name = n.ToString();
            } catch {}
            // accRole
            string role = "";
            try {
                object r = t.InvokeMember("accRole",
                    System.Reflection.BindingFlags.GetProperty, null, acc, new object[] { 0 });
                if (r != null) {
                    uint roleId = Convert.ToUInt32(r);
                    var sb = new StringBuilder(256);
                    GetRoleText(roleId, sb, 256);
                    role = sb.ToString();
                }
            } catch {}

            return "hr=0 children=" + childCount + " name='" + name + "' role='" + role + "'";
        } catch (Exception ex) {
            return "hr=0 but query failed: " + ex.Message;
        }
    }
}
"@

$auto = [System.Windows.Automation.AutomationElement]
$tw = [System.Windows.Automation.TreeWalker]::RawViewWalker

# Step 1: Check current screen reader flag state
$srFlag = [AccTriggerV3]::IsScreenReaderFlagSet()
Write-Output "Screen reader flag: $srFlag"

# Step 2: Enumerate ALL child HWNDs
Write-Output ""
Write-Output "=== All child HWNDs of Claude window ==="
$allHwnds = [AccTriggerV3]::EnumAllChildren()
foreach ($h in $allHwnds) {
    Write-Output "  $h"
}

# Step 3: Send WM_GETOBJECT to ALL Chrome_RenderWidgetHostHWND and other interesting HWNDs
Write-Output ""
Write-Output "=== WM_GETOBJECT responses ==="
foreach ($h in $allHwnds) {
    $parts = $h -split " ", 2
    $hwndVal = [IntPtr]::new([long]$parts[0])
    $cls = $parts[1]
    if ($cls -match "Chrome_RenderWidgetHostHWND|Chrome_WidgetWin_1|Intermediate D3D Window|RenderWidgetHostHWND") {
        $result = [AccTriggerV3]::TryWmGetObject($hwndVal)
        Write-Output "  $cls ($($parts[0])): $result"
    }
}

# Step 4: Query IAccessible on each render host
Write-Output ""
Write-Output "=== IAccessible queries ==="
foreach ($h in $allHwnds) {
    $parts = $h -split " ", 2
    $hwndVal = [IntPtr]::new([long]$parts[0])
    $cls = $parts[1]
    if ($cls -match "Chrome_RenderWidgetHostHWND") {
        $result = [AccTriggerV3]::QueryIAccessible($hwndVal)
        Write-Output "  $cls ($($parts[0])): $result"
    }
}

# Step 5: Try setting screen reader flag + WM_SETTINGCHANGE broadcast
Write-Output ""
Write-Output "=== Setting screen reader flag + broadcast ==="
# First unset it
$val = $false
[void][AccTriggerV3]::IsScreenReaderFlagSet()  # just read
# Now set it fresh
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class SRBroadcast {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SystemParametersInfo(uint action, uint param, ref bool pvParam, uint fWinIni);

    [DllImport("user32.dll")]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam,
        uint flags, uint timeout, out IntPtr result);

    public const uint SPI_SETSCREENREADER = 0x0047;
    public const uint SPIF_UPDATEINIFILE = 0x01;
    public const uint SPIF_SENDCHANGE = 0x02;
    public const uint WM_SETTINGCHANGE = 0x001A;
    public const uint SPI_SETSCREENREADER_COMBINED = 0x0047;
    public static readonly IntPtr HWND_BROADCAST = new IntPtr(0xFFFF);

    public static string SetAndBroadcast() {
        // Set the flag with both UPDATEINIFILE and SENDCHANGE
        bool val = true;
        bool ok = SystemParametersInfo(SPI_SETSCREENREADER, 1, ref val, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);

        // Also manually broadcast WM_SETTINGCHANGE
        IntPtr result;
        SendMessageTimeout(HWND_BROADCAST, WM_SETTINGCHANGE, new IntPtr(SPI_SETSCREENREADER),
            IntPtr.Zero, 0x0002, 5000, out result);

        return "Set=" + ok + " Broadcast result=" + result;
    }
}
"@
$broadcastResult = [SRBroadcast]::SetAndBroadcast()
Write-Output "  $broadcastResult"
Write-Output "  Waiting 3 seconds..."
Start-Sleep -Seconds 3

# Re-check WM_GETOBJECT responses after flag change
Write-Output ""
Write-Output "=== WM_GETOBJECT after screen reader broadcast ==="
foreach ($h in $allHwnds) {
    $parts = $h -split " ", 2
    $hwndVal = [IntPtr]::new([long]$parts[0])
    $cls = $parts[1]
    if ($cls -match "Chrome_RenderWidgetHostHWND") {
        $result = [AccTriggerV3]::TryWmGetObject($hwndVal)
        Write-Output "  $cls ($($parts[0])): $result"
        # Also try IAccessible
        $accResult = [AccTriggerV3]::QueryIAccessible($hwndVal)
        Write-Output "    IAccessible: $accResult"
    }
}

# Step 6: Use UIA to walk from render host
Write-Output ""
Write-Output "=== UIA walk from render host HWNDs ==="
foreach ($h in $allHwnds) {
    $parts = $h -split " ", 2
    $hwndVal = [IntPtr]::new([long]$parts[0])
    $cls = $parts[1]
    if ($cls -match "Chrome_RenderWidgetHostHWND") {
        try {
            $el = $auto::FromHandle($hwndVal)
            $childCount = 0
            $c = $tw.GetFirstChild($el)
            while ($null -ne $c) {
                $childCount++
                $childName = $c.Current.Name
                $childCtrl = $c.Current.ControlType.ProgrammaticName
                if ($childCount -le 3) {
                    Write-Output "    Child $childCount : $childCtrl Name='$childName'"
                }
                $c = $tw.GetNextSibling($c)
            }
            Write-Output "  HWND $($parts[0]): $childCount children via UIA"
        } catch {
            Write-Output "  HWND $($parts[0]): UIA error - $($_.Exception.Message)"
        }
    }
}

# Step 7: Try the Electron-specific approach - send IPC to enable accessibility
# Electron exposes app.setAccessibilitySupportEnabled(true)
# We can try to find the Electron window and manipulate it
Write-Output ""
Write-Output "=== Checking Electron command line ==="
$claudeProcs = Get-Process -Name "Claude" -ErrorAction SilentlyContinue
if ($claudeProcs) {
    foreach ($p in $claudeProcs) {
        try {
            $wmi = Get-CimInstance Win32_Process -Filter "ProcessId = $($p.Id)" -ErrorAction SilentlyContinue
            if ($wmi -and $wmi.CommandLine) {
                $cmd = $wmi.CommandLine
                if ($cmd.Length -gt 200) { $cmd = $cmd.Substring(0, 200) + "..." }
                Write-Output "  PID $($p.Id): $cmd"
            }
        } catch {}
    }
}
