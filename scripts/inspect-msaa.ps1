# inspect-msaa.ps1 — Use MSAA (IAccessible) to inspect Claude Desktop
# Also does a full exhaustive walk of the entire UIA tree

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

Write-Output "Claude found (PID: $($claudeWin.Current.ProcessId))"

# Full exhaustive walk — count ALL elements and catalog control types
$allElements = @()
$elementCount = 0

function Walk-All {
    param($element, [int]$depth = 0, [int]$maxDepth = 15)
    if ($depth -gt $maxDepth) { return }

    $script:elementCount++
    try {
        $ctrl = $element.Current.ControlType.ProgrammaticName
        $name = $element.Current.Name
        $cls = $element.Current.ClassName
        $aid = $element.Current.AutomationId

        # Log interesting elements (not just generic Pane/View)
        $isInteresting = $ctrl -notin @("ControlType.Pane") -or $cls -notin @("View", "", "Intermediate D3D Window", "RootView", "NonClientView", "WinFrameView", "ClientView", "WinCaptionButtonContainer")
        if ($isInteresting -or $aid -or ($name -and $name -ne "Claude" -and $name -ne "Chrome Legacy Window")) {
            $indent = "  " * [Math]::Min($depth, 10)
            $displayName = $name
            if ($displayName.Length -gt 60) { $displayName = $displayName.Substring(0, 60) + "..." }
            Write-Output "${indent}[d=$depth] $ctrl Name='$displayName' Cls='$cls' AId='$aid'"
        }
    } catch { return }

    try {
        $child = $tw.GetFirstChild($element)
        $count = 0
        while ($child -ne $null -and $count -lt 200) {
            Walk-All $child ($depth + 1) $maxDepth
            $child = $tw.GetNextSibling($child)
            $count++
        }
    } catch {}
}

Write-Output "`n=== Exhaustive UIA tree walk (depth 15) ==="
Walk-All $claudeWin 0 15
Write-Output "`nTotal elements found: $elementCount"

# Now try MSAA approach via COM
Write-Output "`n=== MSAA (IAccessible) approach ==="

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class MsaaInspector {
    [DllImport("oleacc.dll")]
    static extern int AccessibleObjectFromWindow(
        IntPtr hwnd, uint dwId, ref Guid riid,
        [MarshalAs(UnmanagedType.Interface)] out Accessibility.IAccessible ppvObject);

    [DllImport("oleacc.dll")]
    static extern int AccessibleChildren(
        Accessibility.IAccessible paccContainer, int iChildStart,
        int cChildren, [Out] object[] rgvarChildren, out int pcObtained);

    [DllImport("user32.dll")]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll")]
    public static extern IntPtr FindWindowEx(IntPtr parent, IntPtr childAfter, string cls, string wnd);

    const uint OBJID_CLIENT = 0xFFFFFFFC;

    public static string InspectWindow(string windowName) {
        IntPtr hwnd = FindWindow("Chrome_WidgetWin_1", windowName);
        if (hwnd == IntPtr.Zero) return "Window not found";

        // Find the renderer HWND
        IntPtr renderHwnd = IntPtr.Zero;
        EnumChildWindows(hwnd, renderHwnd);

        Guid iid = typeof(Accessibility.IAccessible).GUID;
        Accessibility.IAccessible acc;
        int hr = AccessibleObjectFromWindow(hwnd, OBJID_CLIENT, ref iid, out acc);
        if (hr != 0) return "IAccessible failed: hr=" + hr;

        var sb = new StringBuilder();
        WalkAccessible(acc, 0, 5, sb);
        return sb.ToString();
    }

    static void WalkAccessible(Accessibility.IAccessible acc, int depth, int maxDepth, StringBuilder sb) {
        if (depth > maxDepth) return;
        string indent = new string(' ', depth * 2);

        try {
            string name = acc.get_accName(0);
            string role = "";
            try { role = acc.get_accRole(0).ToString(); } catch {}
            string value = "";
            try { value = acc.get_accValue(0); } catch {}
            string state = "";
            try { state = acc.get_accState(0).ToString(); } catch {}

            if (name != null && name.Length > 80) name = name.Substring(0, 80) + "...";
            if (value != null && value.Length > 80) value = value.Substring(0, 80) + "...";

            sb.AppendLine(indent + "Role=" + role + " Name='" + (name ?? "") + "' Value='" + (value ?? "") + "'");
        } catch {
            sb.AppendLine(indent + "(error reading properties)");
            return;
        }

        try {
            int childCount = acc.accChildCount;
            if (childCount > 0 && childCount < 200) {
                object[] children = new object[childCount];
                int obtained;
                AccessibleChildren(acc, 0, childCount, children, out obtained);
                for (int i = 0; i < obtained; i++) {
                    if (children[i] is Accessibility.IAccessible childAcc) {
                        WalkAccessible(childAcc, depth + 1, maxDepth, sb);
                    }
                }
            }
        } catch {}
    }

    static void EnumChildWindows(IntPtr parent, IntPtr renderHwnd) {
        // placeholder
    }
}
"@ -ReferencedAssemblies "Accessibility"

Write-Output ([MsaaInspector]::InspectWindow("Claude"))
