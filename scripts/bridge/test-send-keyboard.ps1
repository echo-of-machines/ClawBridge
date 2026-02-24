# test-send-keyboard.ps1 - Send message using ONLY keyboard (no mouse clicks)
param([string]$Message = "Say exactly: CLAWBRIDGE_KEYBOARD_OK")

. "$PSScriptRoot\preamble.ps1"

if (-not $Message) { Write-Output "ERROR:NO_MESSAGE"; exit 1 }

# Ensure Claude Desktop is visible
[ClawBridgeWin32]::SetScreenReaderFlag()
[ClawBridgeWin32]::EnsureVisible() | Out-Null

# Set clipboard BEFORE switching focus
[System.Windows.Forms.Clipboard]::SetText($Message)

# Bring Claude Desktop to foreground
$hwnd = [ClawBridgeWin32]::FindClaudeHwnd()
if ($hwnd -eq [IntPtr]::Zero) { Write-Output "ERROR:NO_HWND"; exit 1 }
[ClawBridgeWin32]::SetForegroundWindow($hwnd) | Out-Null

# Small delay to let foreground settle
Start-Sleep -Milliseconds 500

# All keyboard ops in rapid sequence:
# 1. Tab to focus the input field
# 2. Ctrl+A to select all (clear any existing text)
# 3. Ctrl+V to paste from clipboard
# 4. Enter to submit
[System.Windows.Forms.SendKeys]::SendWait("{TAB}")
Start-Sleep -Milliseconds 200
[System.Windows.Forms.SendKeys]::SendWait("^a")
Start-Sleep -Milliseconds 100
[System.Windows.Forms.SendKeys]::SendWait("^v")
Start-Sleep -Milliseconds 300
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

Write-Output "OK"
