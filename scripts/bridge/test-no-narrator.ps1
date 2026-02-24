# test-no-narrator.ps1 - Try to trigger accessibility WITHOUT Narrator
. "$PSScriptRoot\preamble.ps1"

Write-Output "Step 1: Set screen reader flag"
[ClawBridgeWin32]::SetScreenReaderFlag()

Write-Output "Step 2: Find Claude window HWND"
$hwnd = [ClawBridgeWin32]::FindClaudeHwnd()
if ($hwnd -eq [IntPtr]::Zero) { Write-Output "ERROR:NO_HWND"; exit 1 }
Write-Output "  HWND: $hwnd"

Write-Output "Step 3: Minimize + Restore to force re-render"
[ClawBridgeWin32]::ShowWindow($hwnd, 6) | Out-Null  # SW_MINIMIZE
Start-Sleep -Milliseconds 500
[ClawBridgeWin32]::ShowWindow($hwnd, 9) | Out-Null  # SW_RESTORE
Start-Sleep -Milliseconds 500
[ClawBridgeWin32]::ShowWindow($hwnd, 5) | Out-Null  # SW_SHOW

Write-Output "Step 4: Wait 3 seconds for tree to populate"
Start-Sleep -Seconds 3

Write-Output "Step 5: Check for main-content"
$claudeWin = Find-ClaudeWindow
if (-not $claudeWin) { Write-Output "ERROR:UIA_WINDOW_NOT_FOUND"; exit 1 }

$mc = Find-ByAutomationId $claudeWin "main-content" 15
if ($mc) {
    Write-Output "RESULT: main-content FOUND (no Narrator needed)"
} else {
    Write-Output "RESULT: main-content NOT FOUND (Narrator still needed)"
}

# Also check TipTap
$tiptap = Find-ByClassContains $claudeWin "tiptap" 25
if ($tiptap) {
    Write-Output "TipTap: FOUND"
} else {
    Write-Output "TipTap: NOT FOUND"
}
