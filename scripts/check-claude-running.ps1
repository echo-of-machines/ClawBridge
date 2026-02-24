# check-claude-running.ps1 - Check if Claude Desktop is running
$procs = Get-Process -Name "Claude" -ErrorAction SilentlyContinue
if ($procs) {
    Write-Output "Claude Desktop is running (PID: $($procs[0].Id))"
} else {
    Write-Output "Claude Desktop is NOT running"
}
