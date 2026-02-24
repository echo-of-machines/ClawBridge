# screenshot.ps1 - Capture a screenshot of the Claude Desktop window
# Outputs the path to the saved PNG file
param([string]$OutputPath)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ([System.Management.Automation.PSTypeName]'ScreenCap').Type) {
    Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;

public class ScreenCap {
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    public static extern bool PrintWindow(IntPtr hWnd, IntPtr hDC, uint flags);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int cmd);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left, Top, Right, Bottom;
    }

    static IntPtr found = IntPtr.Zero;
    static bool CB(IntPtr h, IntPtr lp) {
        var c = new StringBuilder(256); GetClassName(h, c, 256);
        if (c.ToString() == "Chrome_WidgetWin_1") {
            var t = new StringBuilder(256); GetWindowText(h, t, 256);
            if (t.ToString().Contains("Claude")) { found = h; return false; }
        }
        return true;
    }

    public static Bitmap Capture() {
        found = IntPtr.Zero;
        EnumWindows(CB, IntPtr.Zero);
        if (found == IntPtr.Zero) return null;

        ShowWindow(found, 9); // SW_RESTORE

        RECT r;
        GetWindowRect(found, out r);
        int w = r.Right - r.Left;
        int h = r.Bottom - r.Top;
        if (w <= 0 || h <= 0) return null;

        var bmp = new Bitmap(w, h);
        using (var g = Graphics.FromImage(bmp)) {
            IntPtr hdc = g.GetHdc();
            PrintWindow(found, hdc, 2); // PW_RENDERFULLCONTENT
            g.ReleaseHdc(hdc);
        }
        return bmp;
    }
}
"@
}

$bmp = [ScreenCap]::Capture()
if (-not $bmp) { Write-Output "ERROR:NO_WINDOW"; exit 1 }

if (-not $OutputPath) {
    $OutputPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "claude_screenshot.png")
}

$bmp.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

Write-Output $OutputPath
