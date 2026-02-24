# show-claude-window.ps1 - Find and show Claude Desktop window even if hidden
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public class WindowFinder {
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder sb, int max);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int GetClassName(IntPtr hWnd, StringBuilder sb, int max);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int cmd);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    public const int SW_SHOW = 5;
    public const int SW_RESTORE = 9;
    public const int SW_SHOWDEFAULT = 10;

    static List<string> results = new List<string>();
    static List<IntPtr> claudeWindows = new List<IntPtr>();

    static bool EnumCB(IntPtr hWnd, IntPtr lParam) {
        uint pid;
        GetWindowThreadProcessId(hWnd, out pid);

        var sbTitle = new StringBuilder(256);
        GetWindowText(hWnd, sbTitle, 256);
        var sbClass = new StringBuilder(256);
        GetClassName(hWnd, sbClass, 256);

        string title = sbTitle.ToString();
        string cls = sbClass.ToString();
        bool visible = IsWindowVisible(hWnd);

        // Check if this belongs to a Claude Desktop process
        if (cls == "Chrome_WidgetWin_1" || cls == "Chrome_WidgetWin_0" ||
            title.Contains("Claude") || title.Contains("claude")) {
            results.Add("HWND=" + hWnd + " PID=" + pid + " Cls='" + cls + "' Title='" + title + "' Visible=" + visible);
            claudeWindows.Add(hWnd);
        }
        return true;
    }

    public static string[] FindAll() {
        results.Clear();
        claudeWindows.Clear();
        EnumWindows(EnumCB, IntPtr.Zero);
        return results.ToArray();
    }

    public static string ShowAll() {
        string result = "";
        foreach (var hwnd in claudeWindows) {
            ShowWindow(hwnd, SW_RESTORE);
            ShowWindow(hwnd, SW_SHOW);
            SetForegroundWindow(hwnd);
            result += "Showed HWND=" + hwnd + "; ";
        }
        return result.Length > 0 ? result : "No windows to show";
    }

    // Also find by specific PIDs
    static List<string> pidResults = new List<string>();
    static List<IntPtr> pidWindows = new List<IntPtr>();

    static bool PidEnumCB(IntPtr hWnd, IntPtr lParam) {
        uint pid;
        GetWindowThreadProcessId(hWnd, out pid);
        uint targetPid = (uint)lParam.ToInt64();
        if (pid == targetPid) {
            var sbTitle = new StringBuilder(256);
            GetWindowText(hWnd, sbTitle, 256);
            var sbClass = new StringBuilder(256);
            GetClassName(hWnd, sbClass, 256);
            bool visible = IsWindowVisible(hWnd);
            pidResults.Add("HWND=" + hWnd + " Cls='" + sbClass + "' Title='" + sbTitle + "' Visible=" + visible);
            pidWindows.Add(hWnd);
        }
        return true;
    }

    public static string[] FindByPid(uint pid) {
        pidResults.Clear();
        pidWindows.Clear();
        EnumWindows(PidEnumCB, new IntPtr(pid));
        return pidResults.ToArray();
    }

    public static string ShowByPid() {
        string result = "";
        foreach (var hwnd in pidWindows) {
            ShowWindow(hwnd, SW_RESTORE);
            ShowWindow(hwnd, SW_SHOW);
            SetForegroundWindow(hwnd);
            result += "Showed HWND=" + hwnd + "; ";
        }
        return result.Length > 0 ? result : "No windows for this PID";
    }
}
"@

# Find Claude Desktop main process
$mainProc = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq "Claude.exe" -and $_.CommandLine -notlike "*--type=*" -and $_.CommandLine -notlike "*claude-code*" -and $_.CommandLine -notlike "*native-binary*" }

if (-not $mainProc) {
    Write-Output "Claude Desktop main process not found"
    exit 1
}
Write-Output "Claude Desktop main process: PID=$($mainProc.ProcessId)"
Write-Output "Command: $($mainProc.CommandLine)"

# Find all windows for this PID
Write-Output ""
Write-Output "=== Windows for Claude Desktop main process ==="
$wins = [WindowFinder]::FindByPid([uint32]$mainProc.ProcessId)
foreach ($w in $wins) { Write-Output "  $w" }

# Try to show them
Write-Output ""
Write-Output "=== Attempting to show windows ==="
$r = [WindowFinder]::ShowByPid()
Write-Output "  $r"

# Also check all Chrome_WidgetWin windows
Write-Output ""
Write-Output "=== All Chrome/Claude windows ==="
$allWins = [WindowFinder]::FindAll()
foreach ($w in $allWins) { Write-Output "  $w" }
