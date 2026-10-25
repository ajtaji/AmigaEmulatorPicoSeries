# Where the tools find what is outside this repository. Each comes from an
# environment variable, or from tools\local.ps1 (not in git: set the variables
# there for your own machine), or else the default here.
#   PUREMETAL_FORGE     the PureMetal compiler  (default: PureMetalForge.exe on the PATH)
#   BOARD_LEASE_SCRIPT  a script that shares boards between several users of one bench:
#                       it defines Get-BoardLease / Release-BoardLease (default: none -
#                       the boards are yours alone)
$local = Join-Path $PSScriptRoot 'local.ps1'
if (Test-Path $local) { . $local }
if ($env:PUREMETAL_FORGE) { $PmfExe = $env:PUREMETAL_FORGE } else { $PmfExe = 'PureMetalForge.exe' }
