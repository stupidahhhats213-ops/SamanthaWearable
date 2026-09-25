# Reports whether this PC can refresh or install through AltServer.
# Does not restart services, reinstall AltServer, or change firewall rules.
# If a Private-network allow rule is missing, the script prints the command it would run.

$ErrorActionPreference = "Continue"

function Write-Check($name, $ok, $detail) {
    $state = if ($ok) { "OK" } else { "CHECK" }
    Write-Output ("{0,-28} {1,-6} {2}" -f $name, $state, $detail)
}

Write-Output "AltServer check"
Write-Output "----------------"

$alt = Get-Process -Name AltServer -ErrorAction SilentlyContinue
Write-Check "AltServer process" ($null -ne $alt) $(if ($alt) { "pid $($alt.Id -join ',')" } else { "not running" })

$amds = Get-Service -Name "Apple Mobile Device Service" -ErrorAction SilentlyContinue
$amdsOk = $amds -and $amds.Status -eq "Running"
Write-Check "Apple Mobile Device Service" $amdsOk $(if ($amds) { "$($amds.Status) / $($amds.StartType)" } else { "service not installed" })

$bonjour = Get-Service -Name "Bonjour Service" -ErrorAction SilentlyContinue
Write-Check "Bonjour Service" ($bonjour -and $bonjour.Status -eq "Running") $(if ($bonjour) { "$($bonjour.Status) / $($bonjour.StartType)" } else { "service not found" })

$lan = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.254.*" -and $_.PrefixOrigin -ne "WellKnown" }
$lanLines = @($lan | ForEach-Object { "$($_.InterfaceAlias) $($_.IPAddress)" })
Write-Check "LAN IPv4" ($lanLines.Count -gt 0) ($(if ($lanLines) { $lanLines -join "; " } else { "no non-link-local IPv4" }))

$tailscale = Get-Process -Name tailscale-ipn, tailscaled -ErrorAction SilentlyContinue
$tsExe = @(
    "$env:ProgramFiles\Tailscale\tailscale.exe",
    "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
$tsDetail = "process not running"
if ($tsExe) {
    $tsStatus = & $tsExe status 2>&1 | Out-String
    $tsDetail = ($tsStatus -split "`n" | Select-Object -First 4) -join " | "
}
Write-Check "Tailscale" (-not $tailscale) $tsDetail
if ($tailscale) {
    Write-Output "Tailscale is running. Exit it before an AltStore refresh so it does not sit on the discovery path."
}

$rules = Get-NetFirewallRule -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match "AltServer" -or $_.Name -match "AltServer" }
$enabled = @($rules | Where-Object { $_.Enabled -eq "True" -and $_.Action -eq "Allow" -and $_.Direction -eq "Inbound" })
$privateAllow = @()
foreach ($rule in $enabled) {
    $profile = (Get-NetFirewallRule -Name $rule.Name -ErrorAction SilentlyContinue).Profile
    if ($profile -match "Private" -or $profile -eq "Any") {
        $privateAllow += $rule
    }
}
Write-Check "Firewall AltServer allow" ($privateAllow.Count -gt 0) ("inbound allow rules: $($enabled.Count); private/any: $($privateAllow.Count)")

if ($privateAllow.Count -eq 0) {
    Write-Output ""
    Write-Output "A Private-network inbound allow rule for AltServer was not found."
    Write-Output "This script will not change the firewall. The command it would run is:"
    Write-Output 'New-NetFirewallRule -DisplayName "AltServer" -Direction Inbound -Program "C:\Program Files (x86)\AltServer\AltServer.exe" -Action Allow -Profile Private -Enabled True'
}
