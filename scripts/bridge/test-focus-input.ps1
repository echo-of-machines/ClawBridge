# test-focus-input.ps1 - Try different approaches to focus the TipTap input
param([string]$Method = "all")

. "$PSScriptRoot\preamble.ps1"

$claudeWin = Find-ClaudeWindow
if (-not $claudeWin) { Write-Output "ERROR:WINDOW_NOT_FOUND"; exit 1 }

# Find TipTap with deeper search
$tiptap = Find-ByClassContains $claudeWin "tiptap" 25
if (-not $tiptap) { Write-Output "ERROR:TIPTAP_NOT_FOUND"; exit 1 }

$rect = $tiptap.Current.BoundingRectangle
$physCX = [int]($rect.X + $rect.Width / 2)
$physCY = [int]($rect.Y + $rect.Height / 2)
Write-Output "TipTap physical center: $physCX, $physCY"
Write-Output "DPI scale: $script:dpiScale"

$logCX = [int]($physCX / $script:dpiScale)
$logCY = [int]($physCY / $script:dpiScale)
Write-Output "TipTap logical center: $logCX, $logCY"

# Bring Claude Desktop to foreground
$hwnd = [ClawBridgeWin32]::FindClaudeHwnd()
if ($hwnd -eq [IntPtr]::Zero) { Write-Output "ERROR:NO_HWND"; exit 1 }
[ClawBridgeWin32]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 500

# Method 1: UIA SetFocus
if ($Method -eq "uia" -or $Method -eq "all") {
    Write-Output ""
    Write-Output "--- Method: UIA SetFocus ---"
    try {
        $tiptap.SetFocus()
        Start-Sleep -Milliseconds 300
        $cls = $tiptap.Current.ClassName
        Write-Output "After SetFocus, class: $cls"
        if ($cls -like "*focused*") { Write-Output "FOCUSED via UIA" }
        else { Write-Output "SetFocus did not add 'focused' class" }
    } catch {
        Write-Output "SetFocus failed: $_"
    }
}

# Method 2: Click via SendInput (MOUSEEVENTF_ABSOLUTE)
if ($Method -eq "sendinput" -or $Method -eq "all") {
    Write-Output ""
    Write-Output "--- Method: SendInput ABSOLUTE click ---"

    if (-not ([System.Management.Automation.PSTypeName]'ClawBridgeSendInput').Type) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class ClawBridgeSendInput {
    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT {
        public uint type;
        public MOUSEINPUT mi;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    public static extern int GetSystemMetrics(int nIndex);

    public const uint INPUT_MOUSE = 0;
    public const uint MOUSEEVENTF_MOVE = 0x0001;
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public const uint MOUSEEVENTF_ABSOLUTE = 0x8000;
    public const uint MOUSEEVENTF_VIRTUALDESK = 0x4000;

    public static void ClickAbsolute(int screenX, int screenY) {
        // Convert screen coords to normalized 0-65535 range
        int smCX = GetSystemMetrics(0); // SM_CXSCREEN
        int smCY = GetSystemMetrics(1); // SM_CYSCREEN
        int normX = (int)((screenX * 65535L) / smCX);
        int normY = (int)((screenY * 65535L) / smCY);

        INPUT[] inputs = new INPUT[3];
        // Move
        inputs[0].type = INPUT_MOUSE;
        inputs[0].mi.dx = normX;
        inputs[0].mi.dy = normY;
        inputs[0].mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE;
        // Down
        inputs[1].type = INPUT_MOUSE;
        inputs[1].mi.dx = normX;
        inputs[1].mi.dy = normY;
        inputs[1].mi.dwFlags = MOUSEEVENTF_LEFTDOWN | MOUSEEVENTF_ABSOLUTE;
        // Up
        inputs[2].type = INPUT_MOUSE;
        inputs[2].mi.dx = normX;
        inputs[2].mi.dy = normY;
        inputs[2].mi.dwFlags = MOUSEEVENTF_LEFTUP | MOUSEEVENTF_ABSOLUTE;

        uint sent = SendInput(3, inputs, Marshal.SizeOf(typeof(INPUT)));
        Console.WriteLine("SendInput returned: " + sent + " (expected 3)");
    }
}
"@
    }

    # Use logical coordinates for SendInput (it uses screen coords)
    Write-Output "Clicking at logical coords: $logCX, $logCY"
    [ClawBridgeSendInput]::ClickAbsolute($logCX, $logCY)
    Start-Sleep -Milliseconds 500

    # Re-find tiptap and check
    $tiptap2 = Find-ByClassContains $claudeWin "tiptap" 25
    if ($tiptap2) {
        $cls2 = $tiptap2.Current.ClassName
        Write-Output "After click, class: $cls2"
        if ($cls2 -like "*focused*") { Write-Output "FOCUSED via SendInput click" }
        else { Write-Output "Click did not focus TipTap" }
    }
}

# Method 3: Escape then Tab (dismiss any modal/selection, then tab to input)
if ($Method -eq "esctab" -or $Method -eq "all") {
    Write-Output ""
    Write-Output "--- Method: Escape + Tab ---"
    [System.Windows.Forms.SendKeys]::SendWait("{ESC}")
    Start-Sleep -Milliseconds 300
    [System.Windows.Forms.SendKeys]::SendWait("{TAB}")
    Start-Sleep -Milliseconds 300

    $tiptap3 = Find-ByClassContains $claudeWin "tiptap" 25
    if ($tiptap3) {
        $cls3 = $tiptap3.Current.ClassName
        Write-Output "After Esc+Tab, class: $cls3"
        if ($cls3 -like "*focused*") { Write-Output "FOCUSED via Esc+Tab" }
        else { Write-Output "Esc+Tab did not focus TipTap" }
    }
}

Write-Output ""
Write-Output "DONE"
