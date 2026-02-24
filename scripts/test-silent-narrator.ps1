# test-silent-narrator.ps1 - Test silent Narrator approach

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$auto = [System.Windows.Automation.AutomationElement]
$tw = [System.Windows.Automation.TreeWalker]::RawViewWalker

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

function Find-ClaudeWindow {
    $root = $auto::RootElement
    $cc = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ClassNameProperty, "Chrome_WidgetWin_1"
    )
    $wins = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $cc)
    foreach ($w in $wins) {
        $name = $w.Current.Name
        if ($name -like "*Claude*" -or $name -like "*claude*") { return $w }
    }
    # List what we found for debug
    foreach ($w in $wins) {
        Write-Host "  Chrome_WidgetWin_1: '$($w.Current.Name)' PID=$($w.Current.ProcessId)"
    }
    return $null
}

function Test-TreePopulated {
    $cw = Find-ClaudeWindow
    if (-not $cw) { return "NO_WINDOW" }

    # Try to find main-content by AutomationId (more reliable than class navigation)
    $mc = Find-ByAutomationId $cw "main-content" 15
    if ($mc) {
        # Count children under main-content
        $count = 0
        $child = $tw.GetFirstChild($mc)
        while ($null -ne $child) {
            $count++
            $child = $tw.GetNextSibling($child)
        }
        return "main-content:$count"
    }

    # Fallback: count elements under first Chrome_RenderWidgetHostHWND
    $rh = $null
    $child = $tw.GetFirstChild($cw)
    $queue = @($child)
    $visited = 0
    while ($queue.Count -gt 0 -and $visited -lt 200) {
        $el = $queue[0]
        $queue = $queue[1..($queue.Count)]
        if ($null -eq $el) { continue }
        $visited++
        try {
            if ($el.Current.ClassName -eq "Chrome_RenderWidgetHostHWND") { $rh = $el; break }
        } catch {}
        try {
            $c = $tw.GetFirstChild($el)
            while ($null -ne $c) { $queue += $c; $c = $tw.GetNextSibling($c) }
        } catch {}
    }
    if (-not $rh) { return "NO_RENDER" }

    $count = 0
    $c = $tw.GetFirstChild($rh)
    while ($null -ne $c) { $count++; $c = $tw.GetNextSibling($c) }
    return "render:$count"
}

# Step 1: Baseline
Write-Output "=== Baseline ==="
$baseline = Test-TreePopulated
Write-Output "Tree state: $baseline"

if ($baseline -like "main-content:*") {
    $n = [int]($baseline -replace "main-content:", "")
    if ($n -gt 3) {
        Write-Output "Tree already populated! No trigger needed."
        exit 0
    }
}

# Step 2: Mute Narrator
Write-Output ""
Write-Output "=== Muting Narrator via registry ==="
$narratorRegPath = "HKCU:\Software\Microsoft\Narrator"
$narratorNoRoam = "HKCU:\Software\Microsoft\Narrator\NoRoam"

# Save and set volumes to 0
try {
    New-ItemProperty -Path $narratorRegPath -Name "InUserVoiceVolume" -Value 0 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $narratorRegPath -Name "VoiceVolume" -Value 0 -PropertyType DWord -Force | Out-Null
    if (-not (Test-Path $narratorNoRoam)) { New-Item -Path $narratorNoRoam -Force | Out-Null }
    New-ItemProperty -Path $narratorNoRoam -Name "VoiceVolume" -Value 0 -PropertyType DWord -Force | Out-Null
    Write-Output "  Voice volumes set to 0"
} catch {
    Write-Output "  Error setting volumes: $_"
}

# Step 3: Start Narrator
Write-Output ""
Write-Output "=== Starting Narrator (muted) ==="
Start-Process "Narrator.exe" -ErrorAction SilentlyContinue
Write-Output "  Narrator started, waiting 3 seconds..."
Start-Sleep -Seconds 3

# Step 4: Check tree with Narrator running
$withNarrator = Test-TreePopulated
Write-Output "  Tree with Narrator: $withNarrator"

# Step 5: Stop Narrator
Write-Output ""
Write-Output "=== Stopping Narrator ==="
Stop-Process -Name "Narrator" -Force -ErrorAction SilentlyContinue
Write-Output "  Narrator stopped"
Start-Sleep -Seconds 1

# Step 6: Verify tree persists
$afterStop = Test-TreePopulated
Write-Output "  Tree after stop: $afterStop"

# Step 7: Restore volumes
Write-Output ""
Write-Output "=== Restoring Narrator volumes ==="
try {
    New-ItemProperty -Path $narratorRegPath -Name "InUserVoiceVolume" -Value 100 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $narratorRegPath -Name "VoiceVolume" -Value 100 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $narratorNoRoam -Name "VoiceVolume" -Value 100 -PropertyType DWord -Force | Out-Null
    Write-Output "  Restored to 100"
} catch { Write-Output "  Error restoring: $_" }

# Summary
Write-Output ""
Write-Output "=== RESULT ==="
Write-Output "  Before: $baseline"
Write-Output "  During: $withNarrator"
Write-Output "  After:  $afterStop"
