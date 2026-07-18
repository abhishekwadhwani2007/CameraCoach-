# Run this script as Administrator to allow phone → PC connections on port 8000
# Right-click this file → "Run with PowerShell" (as Administrator)

$ruleName = "PoseCoach Python Server"

# Remove old rule if it exists
netsh advfirewall firewall delete rule name="$ruleName" | Out-Null

# Add new inbound rule for port 8000
netsh advfirewall firewall add rule `
    name="$ruleName" `
    dir=in `
    action=allow `
    protocol=TCP `
    localport=8000 `
    description="Allows phone to reach the PoseCoach FastAPI backend"

Write-Host ""
Write-Host "✅ Firewall rule added. Your phone can now reach http://10.245.166.17:8000" -ForegroundColor Green
Write-Host ""
Read-Host "Press Enter to close"
