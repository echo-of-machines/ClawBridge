# test-msaa-tree.ps1 - Walk the MSAA/IAccessible tree deeply
# Since UIA doesn't work, check if MSAA exposes the full web content

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public class MSAAWalker {
    [DllImport("user32.dll")]
    public static extern IntPtr FindWindow(string cls, string wnd);

    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr parent, EnumWindowsProc cb, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);

    [DllImport("oleacc.dll")]
    public static extern int AccessibleObjectFromWindow(
        IntPtr hwnd, uint objId, ref Guid riid,
        [MarshalAs(UnmanagedType.IUnknown)] out object ppv);

    [DllImport("oleacc.dll")]
    public static extern int AccessibleChildren(
        [MarshalAs(UnmanagedType.IDispatch)] object paccContainer,
        int iChildStart, int cChildren,
        [MarshalAs(UnmanagedType.LPArray, SizeParamIndex = 2)] object[] rgvarChildren,
        out int pcObtained);

    [DllImport("oleacc.dll")]
    public static extern uint GetRoleText(uint role, StringBuilder text, uint cchTextMax);

    [DllImport("oleacc.dll")]
    public static extern uint GetStateText(uint state, StringBuilder text, uint cchTextMax);

    public const uint OBJID_CLIENT = 0xFFFFFFFC;
    public static readonly Guid IID_IAccessible = new Guid("618736e0-3c3d-11cf-810c-00aa00389b71");

    static IntPtr renderHwnd = IntPtr.Zero;
    static bool EnumCB(IntPtr hWnd, IntPtr lParam) {
        var sb = new StringBuilder(256);
        GetClassName(hWnd, sb, 256);
        if (sb.ToString() == "Chrome_RenderWidgetHostHWND") {
            // Take the FIRST one (which has the document)
            if (renderHwnd == IntPtr.Zero) renderHwnd = hWnd;
        }
        EnumChildWindows(hWnd, EnumCB, IntPtr.Zero);
        return true;
    }

    public static IntPtr FindFirstRenderHost() {
        IntPtr main = FindWindow("Chrome_WidgetWin_1", "Claude");
        if (main == IntPtr.Zero) return IntPtr.Zero;
        renderHwnd = IntPtr.Zero;
        EnumChildWindows(main, EnumCB, IntPtr.Zero);
        return renderHwnd;
    }

    static List<string> output = new List<string>();

    static string GetRole(object acc, int childId) {
        try {
            Type t = acc.GetType();
            object r = t.InvokeMember("accRole",
                System.Reflection.BindingFlags.GetProperty, null, acc, new object[] { childId });
            if (r != null) {
                uint roleId = Convert.ToUInt32(r);
                var sb = new StringBuilder(256);
                GetRoleText(roleId, sb, 256);
                return sb.ToString();
            }
        } catch {}
        return "?";
    }

    static string GetName(object acc, int childId) {
        try {
            Type t = acc.GetType();
            object n = t.InvokeMember("accName",
                System.Reflection.BindingFlags.GetProperty, null, acc, new object[] { childId });
            if (n != null) return n.ToString();
        } catch {}
        return "";
    }

    static string GetValue(object acc, int childId) {
        try {
            Type t = acc.GetType();
            object v = t.InvokeMember("accValue",
                System.Reflection.BindingFlags.GetProperty, null, acc, new object[] { childId });
            if (v != null) return v.ToString();
        } catch {}
        return "";
    }

    static int GetChildCount(object acc) {
        try {
            Type t = acc.GetType();
            object cc = t.InvokeMember("accChildCount",
                System.Reflection.BindingFlags.GetProperty, null, acc, null);
            return Convert.ToInt32(cc);
        } catch {}
        return 0;
    }

    static void WalkMSAA(object acc, int depth, int maxDepth) {
        if (depth > maxDepth) return;
        string indent = new string(' ', depth * 2);

        string role = GetRole(acc, 0);
        string name = GetName(acc, 0);
        string value = GetValue(acc, 0);
        int childCount = GetChildCount(acc);

        if (name.Length > 100) name = name.Substring(0, 100) + "...";
        if (value.Length > 100) value = value.Substring(0, 100) + "...";

        string line = indent + "[" + role + "] children=" + childCount;
        if (name.Length > 0) line += " name='" + name + "'";
        if (value.Length > 0) line += " value='" + value + "'";
        output.Add(line);

        if (childCount == 0) return;

        // Get children
        object[] children = new object[childCount];
        int obtained = 0;
        try {
            AccessibleChildren(acc, 0, childCount, children, out obtained);
        } catch {
            output.Add(indent + "  (AccessibleChildren failed)");
            return;
        }

        for (int i = 0; i < obtained; i++) {
            if (children[i] == null) continue;

            if (children[i] is int) {
                // Simple child element (no IAccessible of its own)
                int childId = (int)children[i];
                string cRole = GetRole(acc, childId);
                string cName = GetName(acc, childId);
                string cValue = GetValue(acc, childId);
                if (cName.Length > 100) cName = cName.Substring(0, 100) + "...";
                if (cValue.Length > 100) cValue = cValue.Substring(0, 100) + "...";
                string cLine = indent + "  [" + cRole + "]";
                if (cName.Length > 0) cLine += " name='" + cName + "'";
                if (cValue.Length > 0) cLine += " value='" + cValue + "'";
                output.Add(cLine);
            } else {
                // Full IAccessible child
                WalkMSAA(children[i], depth + 1, maxDepth);
            }
        }
    }

    public static string[] WalkFromHwnd(IntPtr hwnd, int maxDepth) {
        output.Clear();
        object acc;
        Guid iid = IID_IAccessible;
        int hr = AccessibleObjectFromWindow(hwnd, OBJID_CLIENT, ref iid, out acc);
        if (hr != 0) {
            return new string[] { "AccessibleObjectFromWindow failed hr=" + hr };
        }
        output.Add("Root IAccessible obtained (hr=0)");
        WalkMSAA(acc, 0, maxDepth);
        return output.ToArray();
    }
}
"@

$hwnd = [MSAAWalker]::FindFirstRenderHost()
Write-Output "First render host HWND: $hwnd"
if ($hwnd -eq [IntPtr]::Zero) { Write-Output "ERROR: No render host found"; exit 1 }

Write-Output ""
Write-Output "=== MSAA/IAccessible tree walk (max depth 8) ==="
$lines = [MSAAWalker]::WalkFromHwnd($hwnd, 8)
foreach ($l in $lines) {
    Write-Output $l
}
