# read-response.ps1 - Read the last Claude response from the conversation

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$auto = [System.Windows.Automation.AutomationElement]
$tw = [System.Windows.Automation.TreeWalker]::RawViewWalker

$root = $auto::RootElement
$classCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ClassNameProperty, "Chrome_WidgetWin_1"
)
$chromeWindows = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $classCondition)
$claudeWin = $null
foreach ($w in $chromeWindows) {
    if ($w.Current.Name -like "*Claude*") { $claudeWin = $w; break }
}
if (-not $claudeWin) { Write-Output "ERROR: Claude window not found"; exit 1 }

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

$mainContent = Find-ByAutomationId $claudeWin "main-content" 15
if (-not $mainContent) { Write-Output "ERROR: main-content not found"; exit 1 }

# Strategy: do an in-order walk collecting ALL elements with markers.
# Each "Copy message" button marks a message boundary.
# Text after the LAST "Copy message" button (but before turn-form) = assistant response.

$allItems = [System.Collections.ArrayList]::new()

function Walk-InOrder($parent, [int]$depth = 0, [int]$maxDepth = 15) {
    if ($depth -gt $maxDepth) { return }
    $child = $tw.GetFirstChild($parent)
    while ($null -ne $child) {
        try {
            $ctrl = $child.Current.ControlType.ProgrammaticName
            $name = $child.Current.Name
            $aid = $child.Current.AutomationId

            if ($ctrl -eq "ControlType.Button" -and $name -eq "Copy message") {
                $null = $script:allItems.Add(@{ type = "marker"; name = "copy-message" })
            }
            elseif ($aid -eq "turn-form") {
                $null = $script:allItems.Add(@{ type = "marker"; name = "turn-form" })
                return  # Don't walk into the turn form
            }
            elseif ($ctrl -eq "ControlType.Text" -and $name -and $name.Trim().Length -gt 0 -and $name.Trim() -ne "`n") {
                $null = $script:allItems.Add(@{ type = "text"; name = $name.Trim() })
            }
        } catch {}
        Walk-InOrder $child ($depth + 1) $maxDepth
        $child = $tw.GetNextSibling($child)
    }
}

Walk-InOrder $mainContent 0 15

# Find the index of the last "copy-message" marker
$lastCopyIdx = -1
for ($i = 0; $i -lt $allItems.Count; $i++) {
    if ($allItems[$i].type -eq "marker" -and $allItems[$i].name -eq "copy-message") {
        $lastCopyIdx = $i
    }
}

if ($lastCopyIdx -lt 0) {
    Write-Output "ERROR: No messages found in conversation"
    exit 1
}

# Collect text items after the last copy-message marker (until turn-form or end)
$responseTexts = @()
for ($i = $lastCopyIdx + 1; $i -lt $allItems.Count; $i++) {
    $item = $allItems[$i]
    if ($item.type -eq "marker") { break }
    if ($item.type -eq "text") {
        $txt = $item.name
        # Filter UI noise
        if ($txt -notin @("Copy message", "Reply...", "Submit", "Toggle menu",
                          "Ask permissions", "Enter your turn", "Create PR",
                          "Open in VS Code", "Choose destination") -and
            $txt -notmatch '^\+\d+$' -and
            $txt -notmatch '^-\d+$' -and
            $txt -notmatch '^Opus' -and
            $txt -notmatch '^C:\\') {
            $responseTexts += $txt
        }
    }
}

$response = ($responseTexts -join "`n").Trim()

Write-Output "MARKERS: $($allItems.Count) items, last copy-message at index $lastCopyIdx"
Write-Output ""
Write-Output "=== RESPONSE ==="
Write-Output $response
Write-Output "=== END ==="
