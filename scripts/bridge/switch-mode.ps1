# switch-mode.ps1 - Switch Claude Desktop between Chat/Cowork/Code modes
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Chat", "Cowork", "Code")]
    [string]$Mode
)

. "$PSScriptRoot\preamble.ps1"

[ClawBridgeWin32]::SetScreenReaderFlag()
$visible = [ClawBridgeWin32]::EnsureVisible()
if (-not $visible) { Write-Output "ERROR:WINDOW_NOT_FOUND"; exit 1 }

$claudeWin = Find-ClaudeWindow
if (-not $claudeWin) { Write-Output "ERROR:UIA_WINDOW_NOT_FOUND"; exit 1 }

# Find the radio button by name within the segmented control group
$walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
$radioType = [System.Windows.Automation.ControlType]::RadioButton

function Find-RadioButton {
    param($element, [string]$name, [int]$depth = 0, [int]$maxDepth = 15)
    if ($depth -gt $maxDepth) { return $null }

    $ct = $element.Current.ControlType
    $n = $element.Current.Name
    if ($ct -eq $radioType -and $n -eq $name) {
        return $element
    }

    $child = $walker.GetFirstChild($element)
    while ($child) {
        $found = Find-RadioButton $child $name ($depth + 1) $maxDepth
        if ($found) { return $found }
        $child = $walker.GetNextSibling($child)
    }
    return $null
}

$radio = Find-RadioButton $claudeWin $Mode

if (-not $radio) {
    Write-Output "ERROR:MODE_NOT_FOUND:$Mode"
    exit 1
}

# Check if already selected via SelectionItemPattern
try {
    $selPattern = $radio.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
    if ($selPattern.Current.IsSelected) {
        Write-Output "ALREADY:$Mode"
        exit 0
    }
    # Try to select via pattern
    $selPattern.Select()
    Start-Sleep -Milliseconds 500
    if ($selPattern.Current.IsSelected) {
        Write-Output "OK:$Mode"
        exit 0
    }
} catch {
    # SelectionItemPattern not available — fall back to click
}

# Fallback: use InvokePattern
try {
    $invokePattern = $radio.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $invokePattern.Invoke()
    Start-Sleep -Milliseconds 500
    Write-Output "OK:$Mode"
    exit 0
} catch {
    # InvokePattern not available either
}

# Fallback: SetFocus + Enter
$hwnd = [ClawBridgeWin32]::FindClaudeHwnd()
if ($hwnd -ne [IntPtr]::Zero) {
    [ClawBridgeWin32]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 200
}
$radio.SetFocus()
Start-Sleep -Milliseconds 200
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
Start-Sleep -Milliseconds 500

Write-Output "OK:$Mode"
