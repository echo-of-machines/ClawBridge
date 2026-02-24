# dump-tree.ps1 - Dump UIA tree of Claude Desktop for debugging
. "$PSScriptRoot\preamble.ps1"

$claudeWin = Find-ClaudeWindow
if (-not $claudeWin) { Write-Output "ERROR:WINDOW_NOT_FOUND"; exit 1 }

function Dump-Element($el, [int]$depth = 0, [int]$maxDepth = 6) {
    if ($depth -gt $maxDepth) { return }
    $indent = "  " * $depth
    try {
        $c = $el.Current
        $type = $c.ControlType.ProgrammaticName -replace 'ControlType\.', ''
        $name = if ($c.Name) { " Name='$($c.Name.Substring(0, [Math]::Min($c.Name.Length, 50)))'" } else { "" }
        $aid = if ($c.AutomationId) { " AId='$($c.AutomationId)'" } else { "" }
        $cls = if ($c.ClassName) { " Cls='$($c.ClassName.Substring(0, [Math]::Min($c.ClassName.Length, 60)))'" } else { "" }
        Write-Output "$indent[$type$name$aid$cls]"
    } catch {
        Write-Output "$indent[ERROR reading element]"
        return
    }

    $child = $script:tw.GetFirstChild($el)
    while ($null -ne $child) {
        Dump-Element $child ($depth + 1) $maxDepth
        $child = $script:tw.GetNextSibling($child)
    }
}

# Find main-content or dump top-level children
$mc = Find-ByAutomationId $claudeWin "main-content" 15
if ($mc) {
    Write-Output "=== main-content found ==="
    Dump-Element $mc 0 5
} else {
    Write-Output "=== No main-content, dumping top-level ==="
    Dump-Element $claudeWin 0 4
}

# Also look for TipTap specifically
Write-Output ""
Write-Output "=== TipTap search ==="
$tiptap = Find-ByClassContains $claudeWin "tiptap" 20
if ($tiptap) {
    $c = $tiptap.Current
    Write-Output "FOUND: Type=$($c.ControlType.ProgrammaticName) Class=$($c.ClassName) Name=$($c.Name)"
    $rect = $c.BoundingRectangle
    Write-Output "  Bounds: $($rect.X),$($rect.Y) $($rect.Width)x$($rect.Height)"
} else {
    Write-Output "NOT FOUND"
}

# Look for turn-form
Write-Output ""
Write-Output "=== turn-form search ==="
$tf = Find-ByAutomationId $claudeWin "turn-form" 20
if ($tf) {
    Write-Output "FOUND turn-form, dumping children:"
    Dump-Element $tf 0 4
} else {
    Write-Output "NOT FOUND"
}
