# test-send-atomic.ps1 - Test atomic focus + type + submit
param([string]$Message = "Say exactly: CLAWBRIDGE_ATOMIC_OK")

. "$PSScriptRoot\preamble.ps1"

# Add SendInput for atomic key injection
if (-not ([System.Management.Automation.PSTypeName]'ClawInput').Type) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class ClawInput {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT {
        public int type;
        public INPUTUNION u;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct INPUTUNION {
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public MOUSEINPUT mi;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
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

    public const int INPUT_KEYBOARD = 1;
    public const int INPUT_MOUSE = 0;
    public const uint KEYEVENTF_KEYUP = 0x02;
    public const uint MOUSEEVENTF_ABSOLUTE = 0x8000;
    public const uint MOUSEEVENTF_MOVE = 0x0001;
    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public const byte VK_CONTROL = 0x11;
    public const byte VK_V = 0x56;
    public const byte VK_RETURN = 0x0D;
    public const byte VK_TAB = 0x09;

    static INPUT MakeKey(ushort vk, bool up) {
        var input = new INPUT();
        input.type = INPUT_KEYBOARD;
        input.u.ki.wVk = vk;
        input.u.ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
        return input;
    }

    static INPUT MakeClick(int absX, int absY, bool down) {
        var input = new INPUT();
        input.type = INPUT_MOUSE;
        input.u.mi.dx = absX;
        input.u.mi.dy = absY;
        input.u.mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_MOVE |
            (down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP);
        return input;
    }

    // Convert screen coords to absolute coords (0-65535 range)
    static int ToAbs(int coord, int screenSize) {
        return (int)((coord * 65536L) / screenSize);
    }

    public static bool ForceForeground(IntPtr hwnd) {
        IntPtr fg = GetForegroundWindow();
        uint fgPid;
        uint fgThread = GetWindowThreadProcessId(fg, out fgPid);
        uint myThread = GetCurrentThreadId();
        AttachThreadInput(myThread, fgThread, true);
        bool ok = SetForegroundWindow(hwnd);
        AttachThreadInput(myThread, fgThread, false);
        return ok;
    }

    // Click at logical screen coordinates, then Ctrl+V, then click submit
    public static uint ClickPasteSubmit(
        int inputLogX, int inputLogY,
        int submitLogX, int submitLogY,
        int screenW, int screenH)
    {
        int iAbsX = ToAbs(inputLogX, screenW);
        int iAbsY = ToAbs(inputLogY, screenH);
        int sAbsX = ToAbs(submitLogX, screenW);
        int sAbsY = ToAbs(submitLogY, screenH);

        var inputs = new INPUT[] {
            // Click on input field
            MakeClick(iAbsX, iAbsY, true),
            MakeClick(iAbsX, iAbsY, false),
        };
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
        System.Threading.Thread.Sleep(500);

        // Ctrl+V paste
        var paste = new INPUT[] {
            MakeKey(VK_CONTROL, false),
            MakeKey(VK_V, false),
            MakeKey(VK_V, true),
            MakeKey(VK_CONTROL, true),
        };
        SendInput((uint)paste.Length, paste, Marshal.SizeOf(typeof(INPUT)));
        System.Threading.Thread.Sleep(500);

        // Click submit button
        var submit = new INPUT[] {
            MakeClick(sAbsX, sAbsY, true),
            MakeClick(sAbsX, sAbsY, false),
        };
        return SendInput((uint)submit.Length, submit, Marshal.SizeOf(typeof(INPUT)));
    }
}
"@
}

# Find elements
$claudeWin = Find-ClaudeWindow
if (-not $claudeWin) { Write-Output "ERROR:NO_WINDOW"; exit 1 }

$mc = Find-ByAutomationId $claudeWin "main-content" 20
if (-not $mc) { Write-Output "ERROR:NO_MAIN_CONTENT"; exit 1 }

$tiptap = Find-ByClassContains $mc "tiptap" 10
if (-not $tiptap) { Write-Output "ERROR:NO_INPUT"; exit 1 }

$submitBtn = Find-ByName $mc "Submit" "ControlType.Button" 10
if (-not $submitBtn) { $submitBtn = Find-ByName $mc "Send message" "ControlType.Button" 10 }
if (-not $submitBtn) { Write-Output "ERROR:NO_SUBMIT"; exit 1 }

# Get coordinates (physical from UIA, convert to logical for SendInput)
$tr = $tiptap.Current.BoundingRectangle
$inputLogX = [int](($tr.Left + $tr.Width / 2) / $script:dpiScale)
$inputLogY = [int](($tr.Top + $tr.Height / 2) / $script:dpiScale)

$sr = $submitBtn.Current.BoundingRectangle
$submitLogX = [int](($sr.Left + $sr.Width / 2) / $script:dpiScale)
$submitLogY = [int](($sr.Top + $sr.Height / 2) / $script:dpiScale)

# Get screen size (logical)
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$screenW = $screen.Width
$screenH = $screen.Height

Write-Output "Input logical: $inputLogX, $inputLogY"
Write-Output "Submit logical: $submitLogX, $submitLogY"
Write-Output "Screen: $screenW x $screenH"

# Set clipboard
[System.Windows.Forms.Clipboard]::SetText($Message)

# Force foreground
$hwnd = [ClawBridgeWin32]::FindClaudeHwnd()
[ClawInput]::ForceForeground($hwnd) | Out-Null
Start-Sleep -Milliseconds 500

# Atomic: click input, paste, click submit
$result = [ClawInput]::ClickPasteSubmit($inputLogX, $inputLogY, $submitLogX, $submitLogY, $screenW, $screenH)
Write-Output "SendInput result: $result"
Write-Output "OK"
