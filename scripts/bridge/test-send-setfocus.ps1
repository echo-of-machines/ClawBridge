# test-send-setfocus.ps1 - Send message using UIA SetFocus instead of Tab
param([string]$Message = "Say exactly: CLAWBRIDGE_SETFOCUS_OK")

. "$PSScriptRoot\preamble.ps1"

$claudeWin = Find-ClaudeWindow
if (-not $claudeWin) { Write-Output "ERROR:WINDOW_NOT_FOUND"; exit 1 }

# Find TipTap with deep search
$tiptap = Find-ByClassContains $claudeWin "tiptap" 25
if (-not $tiptap) { Write-Output "ERROR:TIPTAP_NOT_FOUND"; exit 1 }

# Set clipboard BEFORE switching focus
[System.Windows.Forms.Clipboard]::SetText($Message)

# Bring window to foreground
$hwnd = [ClawBridgeWin32]::FindClaudeHwnd()
if ($hwnd -eq [IntPtr]::Zero) { Write-Output "ERROR:NO_HWND"; exit 1 }
[ClawBridgeWin32]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 300

# Focus TipTap via UIA SetFocus
$tiptap.SetFocus()
Start-Sleep -Milliseconds 300

# Verify focus
$cls = $tiptap.Current.ClassName
Write-Output "TipTap class after SetFocus: $cls"
if ($cls -notlike "*focused*") {
    Write-Output "WARNING: TipTap not focused, trying anyway"
}

# Select all, paste, submit
[System.Windows.Forms.SendKeys]::SendWait("^a")
Start-Sleep -Milliseconds 100
[System.Windows.Forms.SendKeys]::SendWait("^v")
Start-Sleep -Milliseconds 300
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

Write-Output "OK"
