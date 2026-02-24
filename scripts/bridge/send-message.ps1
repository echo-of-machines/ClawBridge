# send-message.ps1 - Send a message to Claude Desktop
# Uses UIA SetFocus to target TipTap input directly, clipboard paste, Enter to submit.
# No mouse clicks, no Tab — avoids DPI and tab-order issues.
param([string]$Message)

. "$PSScriptRoot\preamble.ps1"

if (-not $Message) { Write-Output "ERROR:NO_MESSAGE"; exit 1 }

# Ensure Claude Desktop is visible
[ClawBridgeWin32]::SetScreenReaderFlag()
$visible = [ClawBridgeWin32]::EnsureVisible()
if (-not $visible) { Write-Output "ERROR:WINDOW_NOT_FOUND"; exit 1 }

$claudeWin = Find-ClaudeWindow
if (-not $claudeWin) { Write-Output "ERROR:UIA_WINDOW_NOT_FOUND"; exit 1 }

# Find TipTap input (deep search — it's nested ~10 levels)
$tiptap = Find-ByClassContains $claudeWin "tiptap" 25
if (-not $tiptap) { Write-Output "ERROR:TIPTAP_NOT_FOUND"; exit 1 }

# Set clipboard BEFORE switching focus
[System.Windows.Forms.Clipboard]::SetText($Message)

# Bring Claude Desktop to foreground
$hwnd = [ClawBridgeWin32]::FindClaudeHwnd()
if ($hwnd -eq [IntPtr]::Zero) { Write-Output "ERROR:NO_HWND"; exit 1 }
[ClawBridgeWin32]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 300

# Focus TipTap directly via UIA (more reliable than Tab)
$tiptap.SetFocus()
Start-Sleep -Milliseconds 300

# Select all → paste → submit
[System.Windows.Forms.SendKeys]::SendWait("^a")
Start-Sleep -Milliseconds 100
[System.Windows.Forms.SendKeys]::SendWait("^v")
Start-Sleep -Milliseconds 300
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

Write-Output "OK"
