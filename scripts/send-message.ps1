# send-message.ps1 - Send a message to Claude Desktop via UIA + Win32
# Usage: powershell -File send-message.ps1 -Message "your message"

param(
    [string]$Message = "Hello from ClawBridge! This is an automated test message."
)

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class Win32Input {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, IntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public const int SW_RESTORE = 9;
    public const int SW_SHOW = 5;

    public static void Click(int x, int y) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(50);
        mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, IntPtr.Zero);
        System.Threading.Thread.Sleep(50);
        mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, IntPtr.Zero);
    }

    public static bool BringToFront(string windowName) {
        IntPtr hwnd = FindWindow("Chrome_WidgetWin_1", windowName);
        if (hwnd == IntPtr.Zero) return false;
        ShowWindow(hwnd, SW_RESTORE);
        return SetForegroundWindow(hwnd);
    }
}
"@

$auto = [System.Windows.Automation.AutomationElement]
$tw = [System.Windows.Automation.TreeWalker]::RawViewWalker

function Get-ChildByClass($parent, $className) {
    $c = $tw.GetFirstChild($parent)
    while ($null -ne $c) {
        if ($c.Current.ClassName -eq $className) { return $c }
        $c = $tw.GetNextSibling($c)
    }
    return $null
}

function Find-ByAutomationId($parent, [string]$aid, [int]$maxDepth = 15, [int]$depth = 0) {
    if ($depth -gt $maxDepth) { return $null }
    $child = $tw.GetFirstChild($parent)
    while ($null -ne $child) {
        try { if ($child.Current.AutomationId -eq $aid) { return $child } } catch {}
        $found = Find-ByAutomationId $child $aid $maxDepth ($depth + 1)
        if ($found) { return $found }
        $child = $tw.GetNextSibling($child)
    }
    return $null
}

function Find-ByClassContains($parent, [string]$substr, [int]$maxDepth = 15, [int]$depth = 0) {
    if ($depth -gt $maxDepth) { return $null }
    $child = $tw.GetFirstChild($parent)
    while ($null -ne $child) {
        try { if ($child.Current.ClassName -like "*$substr*") { return $child } } catch {}
        $found = Find-ByClassContains $child $substr $maxDepth ($depth + 1)
        if ($found) { return $found }
        $child = $tw.GetNextSibling($child)
    }
    return $null
}

function Find-ByName($parent, [string]$name, [string]$ctrlType, [int]$maxDepth = 15, [int]$depth = 0) {
    if ($depth -gt $maxDepth) { return $null }
    $child = $tw.GetFirstChild($parent)
    while ($null -ne $child) {
        try {
            if ($child.Current.Name -eq $name) {
                if (-not $ctrlType -or $child.Current.ControlType.ProgrammaticName -eq $ctrlType) {
                    return $child
                }
            }
        } catch {}
        $found = Find-ByName $child $name $ctrlType $maxDepth ($depth + 1)
        if ($found) { return $found }
        $child = $tw.GetNextSibling($child)
    }
    return $null
}

# --- Step 1: Find Claude Desktop ---
Write-Output "[1/5] Finding Claude Desktop..."
$root = $auto::RootElement
$classCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ClassNameProperty, "Chrome_WidgetWin_1"
)
$chromeWindows = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $classCondition)
$claudeWin = $null
foreach ($w in $chromeWindows) {
    if ($w.Current.Name -like "*Claude*") { $claudeWin = $w; break }
}
if (-not $claudeWin) { Write-Error "Claude Desktop not found"; exit 1 }
Write-Output "  Found (PID: $($claudeWin.Current.ProcessId))"

# --- Step 2: Bring window to foreground ---
Write-Output "[2/5] Bringing Claude to foreground..."
[Win32Input]::BringToFront("Claude") | Out-Null
Start-Sleep -Milliseconds 500

# --- Step 3: Find main-content and TipTap input ---
Write-Output "[3/5] Finding chat input..."
$mainContent = Find-ByAutomationId $claudeWin "main-content" 15
if (-not $mainContent) { Write-Error "main-content not found. Is accessibility enabled?"; exit 1 }
$tiptap = Find-ByClassContains $mainContent "tiptap" 10
if (-not $tiptap) { Write-Error "TipTap input not found"; exit 1 }
Write-Output "  Found TipTap input"

# Get tiptap bounding rect and click on it
$rect = $tiptap.Current.BoundingRectangle
if ($rect.IsEmpty) {
    Write-Output "  BoundingRect is empty, trying click at parent..."
    $parent = $tw.GetParent($tiptap)
    $rect = $parent.Current.BoundingRectangle
}
if (-not $rect.IsEmpty) {
    $clickX = [int]($rect.Left + $rect.Width / 2)
    $clickY = [int]($rect.Top + $rect.Height / 2)
    Write-Output "  Clicking at ($clickX, $clickY)..."
    [Win32Input]::Click($clickX, $clickY)
    Start-Sleep -Milliseconds 500
} else {
    Write-Output "  WARNING: No bounding rect available"
}

# --- Step 4: Type message ---
Write-Output "[4/5] Typing message..."
# Clear existing text
[System.Windows.Forms.SendKeys]::SendWait("^a")
Start-Sleep -Milliseconds 100
[System.Windows.Forms.SendKeys]::SendWait("{DELETE}")
Start-Sleep -Milliseconds 200

# Type message (escape SendKeys special chars)
$escaped = $Message -replace '([+^%~{}()])', '{$1}'
[System.Windows.Forms.SendKeys]::SendWait($escaped)
Start-Sleep -Milliseconds 500
Write-Output "  Typed: '$Message'"

# --- Step 5: Click Submit button ---
Write-Output "[5/5] Submitting..."
$submitBtn = Find-ByName $mainContent "Submit" "ControlType.Button" 10
if ($submitBtn) {
    $btnRect = $submitBtn.Current.BoundingRectangle
    if (-not $btnRect.IsEmpty) {
        $btnX = [int]($btnRect.Left + $btnRect.Width / 2)
        $btnY = [int]($btnRect.Top + $btnRect.Height / 2)
        Write-Output "  Clicking Submit at ($btnX, $btnY)..."
        [Win32Input]::Click($btnX, $btnY)
    } else {
        Write-Output "  Submit has no bounds, pressing Enter..."
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    }
} else {
    Write-Output "  Submit button not found, pressing Enter..."
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
}

Write-Output "`n=== Done - check Claude Desktop ==="
