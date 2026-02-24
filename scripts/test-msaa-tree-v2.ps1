# test-msaa-tree-v2.ps1 - Walk MSAA tree with detailed debug output

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Reflection;

public class MSAAWalker2 {
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

    public const uint OBJID_CLIENT = 0xFFFFFFFC;

    static IntPtr renderHwnd1 = IntPtr.Zero;
    static IntPtr renderHwnd2 = IntPtr.Zero;
    static int renderCount = 0;

    static bool EnumCB(IntPtr hWnd, IntPtr lParam) {
        var sb = new StringBuilder(256);
        GetClassName(hWnd, sb, 256);
        if (sb.ToString() == "Chrome_RenderWidgetHostHWND") {
            renderCount++;
            if (renderCount == 1) renderHwnd1 = hWnd;
            else if (renderCount == 2) renderHwnd2 = hWnd;
        }
        EnumChildWindows(hWnd, EnumCB, IntPtr.Zero);
        return true;
    }

    public static IntPtr[] FindRenderHosts() {
        IntPtr main = FindWindow("Chrome_WidgetWin_1", "Claude");
        if (main == IntPtr.Zero) return new IntPtr[0];
        renderHwnd1 = IntPtr.Zero;
        renderHwnd2 = IntPtr.Zero;
        renderCount = 0;
        EnumChildWindows(main, EnumCB, IntPtr.Zero);
        var result = new List<IntPtr>();
        if (renderHwnd1 != IntPtr.Zero) result.Add(renderHwnd1);
        if (renderHwnd2 != IntPtr.Zero) result.Add(renderHwnd2);
        return result.ToArray();
    }

    static List<string> output = new List<string>();

    static string RoleStr(uint roleId) {
        var sb = new StringBuilder(256);
        GetRoleText(roleId, sb, 256);
        return sb.ToString();
    }

    static void WalkAcc(object acc, int depth, int maxDepth) {
        if (depth > maxDepth) { output.Add(new string(' ', depth * 2) + "(max depth)"); return; }
        string indent = new string(' ', depth * 2);
        Type t = acc.GetType();

        // Get basic props
        string role = "?", name = "", value = "";
        int childCount = 0;

        try {
            object r = t.InvokeMember("accRole", BindingFlags.GetProperty, null, acc, new object[] { 0 });
            if (r != null) role = RoleStr(Convert.ToUInt32(r));
        } catch {}

        try {
            object n = t.InvokeMember("accName", BindingFlags.GetProperty, null, acc, new object[] { 0 });
            if (n != null) { name = n.ToString(); if (name.Length > 120) name = name.Substring(0, 120) + "..."; }
        } catch {}

        try {
            object v = t.InvokeMember("accValue", BindingFlags.GetProperty, null, acc, new object[] { 0 });
            if (v != null) { value = v.ToString(); if (value.Length > 120) value = value.Substring(0, 120) + "..."; }
        } catch {}

        try {
            object cc = t.InvokeMember("accChildCount", BindingFlags.GetProperty, null, acc, null);
            childCount = Convert.ToInt32(cc);
        } catch {}

        string line = indent + "[" + role + "] cc=" + childCount;
        if (name.Length > 0) line += " '" + name + "'";
        if (value.Length > 0) line += " val='" + value + "'";
        output.Add(line);

        if (childCount == 0) return;

        // Get children
        object[] children = new object[childCount];
        int obtained = 0;
        int hr = -1;
        try {
            hr = AccessibleChildren(acc, 0, childCount, children, out obtained);
        } catch (Exception ex) {
            output.Add(indent + "  ERROR AccessibleChildren: " + ex.Message);
            return;
        }

        output.Add(indent + "  (AccessibleChildren hr=" + hr + " obtained=" + obtained + "/" + childCount + ")");

        for (int i = 0; i < obtained; i++) {
            if (children[i] == null) {
                output.Add(indent + "  child[" + i + "] = null");
                continue;
            }

            Type ct = children[i].GetType();
            output.Add(indent + "  child[" + i + "] type=" + ct.Name + " isComObject=" + Marshal.IsComObject(children[i]));

            if (children[i] is int) {
                int childId = (int)children[i];
                string cRole = "?", cName = "";
                try {
                    object cr = t.InvokeMember("accRole", BindingFlags.GetProperty, null, acc, new object[] { childId });
                    if (cr != null) cRole = RoleStr(Convert.ToUInt32(cr));
                } catch {}
                try {
                    object cn = t.InvokeMember("accName", BindingFlags.GetProperty, null, acc, new object[] { childId });
                    if (cn != null) { cName = cn.ToString(); if (cName.Length > 100) cName = cName.Substring(0, 100) + "..."; }
                } catch {}
                output.Add(indent + "    SimpleChild id=" + childId + " [" + cRole + "] '" + cName + "'");
            } else if (Marshal.IsComObject(children[i])) {
                // It's a COM object - should be IAccessible
                WalkAcc(children[i], depth + 1, maxDepth);
            } else {
                output.Add(indent + "    Unknown child type: " + ct.FullName);
            }
        }
    }

    public static string[] WalkFromHwnd(IntPtr hwnd, int maxDepth) {
        output.Clear();
        Guid iid = new Guid("618736e0-3c3d-11cf-810c-00aa00389b71");
        object acc;
        int hr = AccessibleObjectFromWindow(hwnd, OBJID_CLIENT, ref iid, out acc);
        if (hr != 0) {
            return new string[] { "AccessibleObjectFromWindow failed hr=" + hr };
        }
        output.Add("Root IAccessible obtained for HWND " + hwnd);
        WalkAcc(acc, 0, maxDepth);
        return output.ToArray();
    }
}
"@

$hwnds = [MSAAWalker2]::FindRenderHosts()
Write-Output "Found $($hwnds.Length) render hosts"

foreach ($hwnd in $hwnds) {
    Write-Output ""
    Write-Output "=== HWND $hwnd ==="
    $lines = [MSAAWalker2]::WalkFromHwnd($hwnd, 6)
    foreach ($l in $lines) {
        Write-Output $l
    }
}
