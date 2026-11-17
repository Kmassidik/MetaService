# Undoes the join on this Windows computer: stops the helper task, takes the tunnel service down,
# removes the logon task and deletes the join folder. The WireGuard program stays installed.
# Run in an ELEVATED PowerShell:  ~\.metaservice-join\leave.ps1
$ErrorActionPreference = 'Continue'
$JoinHome = Split-Path -Parent $MyInvocation.MyCommand.Path

function Say($text) { Write-Host "leave: $text" }

Say "Leaving MetaService on this computer."

# helper task first, so it does not race the folder delete
schtasks /end /tn 'MetaServiceHelper' 2>&1 | Out-Null
schtasks /delete /tn 'MetaServiceHelper' /f 2>&1 | Out-Null

# tunnel service (needs admin: this script is expected to run elevated)
$WgExe = "$env:ProgramFiles\WireGuard\wireguard.exe"
if (Test-Path $WgExe) {
  & $WgExe /uninstalltunnelservice metaservice 2>&1 | Out-Null
  Say "Tunnel service removed."
}

if (Test-Path "$JoinHome\mesh.conf") { Remove-Item -Force "$JoinHome\mesh.conf" -ErrorAction SilentlyContinue }
Remove-Item -Force -Recurse $JoinHome -ErrorAction SilentlyContinue
Say "Join folder deleted. The machine is out of the shared network."
