# MetaService join script for Windows. Served by the hub with the four placeholders filled in.
# The owner pastes one line in an ELEVATED PowerShell (Run as Administrator):
#   irm https://<hub>/j/<link>?os=windows&cpu=x86_64 | iex
# It installs WireGuard if missing, downloads the helper, installs the tunnel service and the
# logon task, starts the helper, and prints the 6-digit code to type in the panel.
# The script never reads a password: everything it needs admin for is this one elevation.

$ErrorActionPreference = 'Stop'
$LINK = '@LINK@'
$PUBLIC_URL = '@PUBLIC_URL@'
$WANT_OS = '@OS@'
$WANT_CPU = '@CPU@'

function Say($text) { Write-Host "join: $text" }
function Fail($text) { Write-Host "join: FAILED: $text"; exit 1 }

# --- checks -------------------------------------------------------------------------------------
if ($env:PROCESSOR_ARCHITECTURE -notmatch 'AMD64|ARM64') { Fail "this CPU ($env:PROCESSOR_ARCHITECTURE) does not match the link ($WANT_CPU)." }
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) { Fail "this PowerShell is not elevated. Right-click PowerShell and choose 'Run as administrator', then paste the command again." }

$JoinHome = "$env:USERPROFILE\.metaservice-join"
$HelperExe = "$JoinHome\bin\metaservice-agent.exe"
$ArchDir = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x86_64' }

# --- an old join leaves first (the same question the Linux script asks) -------------------------
if (Test-Path "$JoinHome\joined.env") {
  Say "This computer is already joined (state in $JoinHome)."
  $answer = Read-Host 'Leave that join first, then join again? [y/N]'
  if ($answer -ne 'y' -and $answer -ne 'Y') { Fail "the old join is still there, so nothing was joined." }
  Say "Leaving the old join:"
  if (Test-Path "$JoinHome\leave.ps1") { & "$JoinHome\leave.ps1" } else { Fail "the old join's leave script is missing; remove $JoinHome by hand." }
  if (Test-Path $JoinHome) { Fail "the old join is still there after leaving it." }
  Say "Old join removed. Joining again:"
}

# --- WireGuard ----------------------------------------------------------------------------------
$WgExe = "$env:ProgramFiles\WireGuard\wireguard.exe"
if (-not (Test-Path $WgExe)) {
  Say "Installing WireGuard (winget)..."
  winget install --id WireGuard.WireGuard --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
  if (-not (Test-Path $WgExe)) { Fail "WireGuard did not install. Install it from https://wireguard.com/install and run this command again." }
}

# --- the code and the registration --------------------------------------------------------------
$Digits = -join ((48..57) | Get-Random -Count 6 | ForEach-Object { [char]$_ })
$Register = Invoke-RestMethod -Method Post -Uri "$PUBLIC_URL/j/$LINK/register" -ContentType 'application/json' `
  -Body (@{ os = $WANT_OS; cpu = $WANT_CPU; hostname = $env:COMPUTERNAME; code = $Digits } | ConvertTo-Json)
Say "Your code: $Digits  — type it in the panel under 'Waiting for approval'."
Say "Waiting for the approval..."

# --- wait for approval, then fetch the helper and the tunnel config -----------------------------
$Deadline = (Get-Date).AddMinutes(15)
$Approved = $null
while ((Get-Date) -lt $Deadline) {
  Start-Sleep -Seconds 5
  try { $Approved = Invoke-RestMethod -Uri "$PUBLIC_URL/j/$LINK/status?code=$Digits" } catch { continue }
  if ($Approved.state -eq 'approved') { break }
  if ($Approved.state -eq 'refused') { Fail "the operator refused this join." }
}
if (-not $Approved -or $Approved.state -ne 'approved') { Fail "the approval never came within 15 minutes." }

# --- helper + tunnel config ---------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path "$JoinHome\bin", "$JoinHome\state" | Out-Null
Say "Downloading the helper for Windows $ArchDir..."
Invoke-WebRequest -Uri "$PUBLIC_URL/builds/metaservice-agent-windows-$ArchDir.exe" -OutFile "$HelperExe" -UseBasicParsing
Invoke-WebRequest -Uri "$PUBLIC_URL/builds/metaservice-agent-windows-$ArchDir.conf" -OutFile "$JoinHome\mesh.conf" -UseBasicParsing

# --- tunnel service (WireGuard's own service runner, admin once, runs at boot) ------------------
Say "Installing the tunnel service..."
& $WgExe /installtunnelservice "$JoinHome\mesh.conf" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "the tunnel service did not install (wireguard.exe exit $LASTEXITCODE)." }

# --- enrol + scheduled task ---------------------------------------------------------------------
Say "Enrolling..."
& $HelperExe enroll --root $Approved.root --name $Approved.name 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "the helper did not enrol (exit $LASTEXITCODE)." }

$Action = New-ScheduledTaskAction -Execute $HelperExe -Argument 'run'
$Trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
Register-ScheduledTask -TaskName 'MetaServiceHelper' -Action $Action -Trigger $Trigger -Description 'MetaService helper (joined machine)' -Force | Out-Null
Start-ScheduledTask -TaskName 'MetaServiceHelper'
Start-Sleep -Seconds 3

$Task = Get-ScheduledTask -TaskName 'MetaServiceHelper' -ErrorAction SilentlyContinue
if (-not $Task -or $Task.State -eq 'Running') { Say "Helper is running." } else { Say "Helper task state: $($Task.State) (check it if the machine stays offline in the panel)." }

Say ""
Say "Joined as $Approved.name. It shows as online in the panel in a few seconds."
Say "To leave later: run $JoinHome\leave.ps1 as administrator."
