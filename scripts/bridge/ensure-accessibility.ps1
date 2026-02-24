# ensure-accessibility.ps1 - Ensure Claude Desktop is visible and UIA tree is active
# Strategy: SetScreenReaderFlag + minimize/restore first, Narrator fallback if needed.
. "$PSScriptRoot\preamble.ps1"

[ClawBridgeWin32]::SetScreenReaderFlag()
$ok = [ClawBridgeWin32]::EnsureVisible()
if (-not $ok) { Write-Output "ERROR:WINDOW_NOT_FOUND"; exit 1 }
Start-Sleep -Milliseconds 500

$claudeWin = Find-ClaudeWindow
if (-not $claudeWin) { Write-Output "ERROR:UIA_WINDOW_NOT_FOUND"; exit 1 }

# Quick check — tree may already be active
$mc = Find-ByAutomationId $claudeWin "main-content" 15
if ($mc) { Write-Output "OK"; exit 0 }

# Tree not active yet. Try minimize/restore cycle to nudge Chromium.
$hwnd = [ClawBridgeWin32]::FindClaudeHwnd()
if ($hwnd -ne [IntPtr]::Zero) {
    [ClawBridgeWin32]::ShowWindow($hwnd, 6) | Out-Null  # SW_MINIMIZE
    Start-Sleep -Milliseconds 500
    [ClawBridgeWin32]::ShowWindow($hwnd, 9) | Out-Null  # SW_RESTORE
    Start-Sleep -Milliseconds 500
    [ClawBridgeWin32]::ShowWindow($hwnd, 5) | Out-Null  # SW_SHOW
    Start-Sleep -Seconds 3
}

$claudeWin = Find-ClaudeWindow
if (-not $claudeWin) { Write-Output "ERROR:UIA_WINDOW_NOT_FOUND"; exit 1 }
$mc = Find-ByAutomationId $claudeWin "main-content" 15
if ($mc) { Write-Output "OK"; exit 0 }

# Still no tree. Fall back to Narrator (muted via keyboard volume key).
Write-Output "NARRATOR_FALLBACK"
. "$PSScriptRoot\silent-narrator-trigger.ps1"

# Final check
$claudeWin = Find-ClaudeWindow
if (-not $claudeWin) { Write-Output "ERROR:UIA_WINDOW_NOT_FOUND"; exit 1 }
$mc = Find-ByAutomationId $claudeWin "main-content" 15
if ($mc) {
    Write-Output "OK"
} else {
    Write-Output "ERROR:NO_MAIN_CONTENT"
}
