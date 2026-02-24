# test-send-detached.ps1 - Launch a detached hidden PS process to send keys
param([string]$Message = "Say exactly: CLAWBRIDGE_DETACHED_OK")

# Write the actual send logic to a temp file, then run it detached
$tempScript = [System.IO.Path]::GetTempFileName() + ".ps1"

$scriptContent = @"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class W32 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EWP cb, IntPtr lp);
    public delegate bool EWP(IntPtr h, IntPtr lp);
    [DllImport("user32.dll",CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr h, StringBuilder s, int m);
    [DllImport("user32.dll",CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int m);
    static IntPtr found = IntPtr.Zero;
    static bool CB(IntPtr h, IntPtr lp) {
        var c = new StringBuilder(256); GetClassName(h,c,256);
        if (c.ToString()=="Chrome_WidgetWin_1") {
            var t = new StringBuilder(256); GetWindowText(h,t,256);
            if (t.ToString().Contains("Claude")) { found=h; return false; }
        }
        return true;
    }
    public static IntPtr FindClaude() { found=IntPtr.Zero; EnumWindows(CB,IntPtr.Zero); return found; }
}
'@

`$hwnd = [W32]::FindClaude()
if (`$hwnd -eq [IntPtr]::Zero) { exit 1 }

[System.Windows.Forms.Clipboard]::SetText("$($Message -replace '"','\"')")
[W32]::ShowWindow(`$hwnd, 9)
Start-Sleep -Milliseconds 300
[W32]::SetForegroundWindow(`$hwnd) | Out-Null
Start-Sleep -Milliseconds 500

# Tab to input, select all, paste, enter
[System.Windows.Forms.SendKeys]::SendWait("{TAB}")
Start-Sleep -Milliseconds 200
[System.Windows.Forms.SendKeys]::SendWait("^a")
Start-Sleep -Milliseconds 100
[System.Windows.Forms.SendKeys]::SendWait("^v")
Start-Sleep -Milliseconds 300
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
"@

Set-Content -Path $tempScript -Value $scriptContent -Encoding UTF8

# Run as a completely detached process (no window, no parent terminal)
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "powershell.exe"
$psi.Arguments = "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$tempScript`""
$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$psi.CreateNoWindow = $true
$psi.UseShellExecute = $true

$proc = [System.Diagnostics.Process]::Start($psi)
$proc.WaitForExit(10000)

# Cleanup
Remove-Item $tempScript -ErrorAction SilentlyContinue

Write-Output "OK (detached process exited: $($proc.ExitCode))"
