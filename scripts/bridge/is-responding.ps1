# is-responding.ps1 - Check if Claude Desktop is currently generating a response
# Returns: "RESPONDING" if generating, "IDLE" if not, "ERROR:*" on failure
. "$PSScriptRoot\preamble.ps1"

$claudeWin = Find-ClaudeWindow
if (-not $claudeWin) { Write-Output "ERROR:WINDOW_NOT_FOUND"; exit 1 }

$mc = Find-ByAutomationId $claudeWin "main-content" 15
if (-not $mc) { Write-Output "ERROR:NO_MAIN_CONTENT"; exit 1 }

# When Claude Desktop is generating a response, the Submit button becomes a
# "Stop" button. We detect this by looking for a button named "Stop Response"
# or "Stop" within main-content.
$stopBtn = Find-ByName $mc "Stop Response" "ControlType.Button" 15
if (-not $stopBtn) {
    $stopBtn = Find-ByName $mc "Stop" "ControlType.Button" 15
}

if ($stopBtn) {
    Write-Output "RESPONDING"
} else {
    Write-Output "IDLE"
}
