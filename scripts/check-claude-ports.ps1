# check-claude-ports.ps1 - Check what ports Claude Desktop has open
$claudeProcs = Get-Process -Name "Claude" -ErrorAction SilentlyContinue
if (-not $claudeProcs) { Write-Output "No Claude processes"; exit 0 }

Write-Output "Claude processes:"
foreach ($p in $claudeProcs) {
    $wmi = Get-CimInstance Win32_Process -Filter "ProcessId = $($p.Id)" -ErrorAction SilentlyContinue
    $cmd = ""
    if ($wmi -and $wmi.CommandLine) {
        $cmd = $wmi.CommandLine
        if ($cmd.Length -gt 120) { $cmd = $cmd.Substring(0, 120) + "..." }
    }
    Write-Output "  PID=$($p.Id) MainTitle='$($p.MainWindowTitle)' Cmd=$cmd"
}

Write-Output ""
Write-Output "Ports owned by Claude processes:"
$pids = $claudeProcs | ForEach-Object { $_.Id }
$connections = Get-NetTCPConnection -ErrorAction SilentlyContinue | Where-Object { $_.OwningProcess -in $pids }
foreach ($c in $connections) {
    Write-Output "  PID=$($c.OwningProcess) $($c.LocalAddress):$($c.LocalPort) State=$($c.State)"
}

# Check specifically for common debug ports
Write-Output ""
Write-Output "Checking known debug ports (9222, 9229, 5858):"
foreach ($port in @(9222, 9229, 5858)) {
    $c = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    if ($c) { Write-Output "  Port $port OPEN (PID=$($c.OwningProcess))" }
    else { Write-Output "  Port $port not in use" }
}
