# dump-deep.ps1 - Deep dump of specific areas of Claude Desktop UIA tree
. "$PSScriptRoot\preamble.ps1"

$claudeWin = Find-ClaudeWindow
if (-not $claudeWin) { Write-Output "ERROR:WINDOW_NOT_FOUND"; exit 1 }

function Dump-Element($el, [int]$depth = 0, [int]$maxDepth = 10) {
    if ($depth -gt $maxDepth) { return }
    $indent = "  " * $depth
    try {
        $c = $el.Current
        $type = $c.ControlType.ProgrammaticName -replace 'ControlType\.', ''
        $name = if ($c.Name) { " Name='$($c.Name.Substring(0, [Math]::Min($c.Name.Length, 80)))'" } else { "" }
        $aid = if ($c.AutomationId) { " AId='$($c.AutomationId)'" } else { "" }
        $cls = if ($c.ClassName) { " Cls='$($c.ClassName.Substring(0, [Math]::Min($c.ClassName.Length, 80)))'" } else { "" }
        $rect = $c.BoundingRectangle
        $bounds = " @$([int]$rect.X),$([int]$rect.Y) $([int]$rect.Width)x$([int]$rect.Height)"
        Write-Output "$indent[$type$name$aid$cls$bounds]"
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

$mc = Find-ByAutomationId $claudeWin "main-content" 15
if (-not $mc) { Write-Output "ERROR:NO_MAIN_CONTENT"; exit 1 }

# Find the sticky bottom area (input container)
Write-Output "=== Searching for 'sticky bottom' container ==="
function Find-ByClassPrefix($parent, [string]$prefix, [int]$maxDepth = 10, [int]$depth = 0) {
    if ($depth -gt $maxDepth) { return @() }
    $results = @()
    $child = $script:tw.GetFirstChild($parent)
    while ($null -ne $child) {
        try {
            if ($child.Current.ClassName -like "$prefix*") {
                $results += $child
            }
        } catch {}
        $results += @(Find-ByClassPrefix $child $prefix $maxDepth ($depth + 1))
        $child = $script:tw.GetNextSibling($child)
    }
    return $results
}

$stickyEls = @(Find-ByClassPrefix $mc "sticky bottom" 15)
foreach ($s in $stickyEls) {
    Write-Output "--- Sticky bottom element ---"
    Dump-Element $s 0 8
}

# Also search for any Edit/Document controls (input fields)
Write-Output ""
Write-Output "=== Searching for Edit/Document controls ==="
function Find-ByControlType($parent, [string]$ctType, [int]$maxDepth = 15, [int]$depth = 0) {
    if ($depth -gt $maxDepth) { return @() }
    $results = @()
    $child = $script:tw.GetFirstChild($parent)
    while ($null -ne $child) {
        try {
            if ($child.Current.ControlType.ProgrammaticName -eq $ctType) {
                $results += $child
            }
        } catch {}
        $results += @(Find-ByControlType $child $ctType $maxDepth ($depth + 1))
        $child = $script:tw.GetNextSibling($child)
    }
    return $results
}

$edits = @(Find-ByControlType $mc "ControlType.Edit" 20)
$docs = @(Find-ByControlType $mc "ControlType.Document" 20)
Write-Output "Edit controls found: $($edits.Count)"
foreach ($e in $edits) {
    $c = $e.Current
    Write-Output "  Edit: Class='$($c.ClassName)' Name='$($c.Name)' @$([int]$c.BoundingRectangle.X),$([int]$c.BoundingRectangle.Y)"
}
Write-Output "Document controls found: $($docs.Count)"
foreach ($d in $docs) {
    $c = $d.Current
    Write-Output "  Doc: Class='$($c.ClassName)' Name='$($c.Name)' @$([int]$c.BoundingRectangle.X),$([int]$c.BoundingRectangle.Y)"
}

# Search entire window (not just main-content) for tiptap
Write-Output ""
Write-Output "=== Full window search for tiptap ==="
$tiptap = Find-ByClassContains $claudeWin "tiptap" 25
if ($tiptap) {
    $c = $tiptap.Current
    Write-Output "FOUND: Type=$($c.ControlType.ProgrammaticName) Class='$($c.ClassName)' Name='$($c.Name)'"
    Write-Output "  Bounds: $([int]$c.BoundingRectangle.X),$([int]$c.BoundingRectangle.Y) $([int]$c.BoundingRectangle.Width)x$([int]$c.BoundingRectangle.Height)"
} else {
    Write-Output "NOT FOUND in entire window"
}
