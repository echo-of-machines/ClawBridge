# read-response.ps1 - Read the latest assistant response from Claude Desktop
#
# Handles two known tree layouts:
# Layout A: cli-button-container > flat siblings (bg-bg-200 user, empty class assistant)
# Layout B: scroll area > font-claude-response class for assistant messages
#
# Tries Layout B first (current), falls back to Layout A.

. "$PSScriptRoot\preamble.ps1"

$claudeWin = Find-ClaudeWindow
if (-not $claudeWin) { Write-Output "ERROR:WINDOW_NOT_FOUND"; exit 1 }

$mc = Find-ByAutomationId $claudeWin "main-content" 15
if (-not $mc) { Write-Output "ERROR:NO_MAIN_CONTENT"; exit 1 }

# Recursive text extraction
function Get-AllText($el, [int]$maxD = 15, [int]$d = 0) {
    $texts = @()
    if ($d -gt $maxD) { return $texts }
    $child = $script:tw.GetFirstChild($el)
    while ($null -ne $child) {
        try {
            $n = $child.Current.Name
            $ct = $child.Current.ControlType.ProgrammaticName
            if ($ct -eq "ControlType.Text" -and $n -and $n.Length -gt 0) {
                $texts += $n
            }
        } catch {}
        $texts += @(Get-AllText $child $maxD ($d + 1))
        $child = $script:tw.GetNextSibling($child)
    }
    return $texts
}

# Find all elements matching a class substring
function Find-AllByClassContains($parent, [string]$substr, [int]$maxD = 20, [int]$d = 0) {
    $results = @()
    if ($d -gt $maxD) { return $results }
    $child = $script:tw.GetFirstChild($parent)
    while ($null -ne $child) {
        try {
            if ($child.Current.ClassName -like "*$substr*") {
                $results += $child
            }
        } catch {}
        $results += @(Find-AllByClassContains $child $substr $maxD ($d + 1))
        $child = $script:tw.GetNextSibling($child)
    }
    return $results
}

# --- Layout B: font-claude-response ---
$responseEls = @(Find-AllByClassContains $mc "font-claude-response" 20)
if ($responseEls.Count -gt 0) {
    $lastResponse = $responseEls[$responseEls.Count - 1]
    $textParts = @(Get-AllText $lastResponse)
    if ($textParts.Count -gt 0) {
        $responseText = ($textParts -join "`n").Trim()
        if ($responseText.Length -gt 0) {
            Write-Output "RESPONSE:$responseText"
            exit 0
        }
    }
    Write-Output "EMPTY_RESPONSE"
    exit 0
}

# --- Layout A: cli-button-container ---
$cli = Find-ByAutomationId $mc "cli-button-container" 10
if ($cli) {
    $wrapper = $script:tw.GetFirstChild($cli)
    if ($wrapper) { $msgContainer = $script:tw.GetFirstChild($wrapper) }
    if ($msgContainer) {
        $children = @()
        $ch = $script:tw.GetFirstChild($msgContainer)
        while ($null -ne $ch) { $children += $ch; $ch = $script:tw.GetNextSibling($ch) }

        for ($i = $children.Count - 1; $i -ge 0; $i--) {
            $el = $children[$i]
            try {
                $ctrl = $el.Current.ControlType.ProgrammaticName
                $cls = $el.Current.ClassName
                if ($ctrl -eq "ControlType.Button") { continue }
                if ($cls -like "*bg-bg-200*" -or $cls -like "*bg-bg-300*") { continue }
                if ($ctrl -eq "ControlType.Group") {
                    $textParts = @(Get-AllText $el)
                    if ($textParts.Count -gt 0) {
                        $responseText = ($textParts -join "`n").Trim()
                        if ($responseText.Length -gt 0) {
                            Write-Output "RESPONSE:$responseText"
                            exit 0
                        }
                    }
                }
            } catch { continue }
        }
    }
}

Write-Output "NO_RESPONSE"
