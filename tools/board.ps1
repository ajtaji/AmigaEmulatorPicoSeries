# Board work on a shared board under ONE lease, held only while the jobs run.
# The lease follows C:\PMFBuild\board-leases\lease.ps1 (the shared protocol:
# a ticket in queue\<Port>, the oldest live ticket takes the board, the lease
# file written in one call and released by rename-then-delete by its owner).
#
#   powershell -File tools\board.ps1 -Port COM7 -Jobs 'flash Diagnostics/x.picow Diagnostics/build/x.uf2 10',
#                                     'vectors Diagnostics/vectors.picow Diagnostics/build/vectors.uf2 --only ADD'
#
#   flash   <source> <output.uf2> [seconds]          build, upload, capture output
#   vectors <source> <output.uf2> <stream.py args>   build, upload, stream the 68000 tests
param(
    [string]$Port = 'COM7',
    [int]$Minutes = 5,
    [string[]]$Jobs
)
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lease_turn.ps1')

$root = Split-Path $PSScriptRoot -Parent

# build every image first, so the board is held only for the upload and the run
foreach ($job in $Jobs) {
    $w = $job -split '\s+'
    & (Join-Path $PSScriptRoot 'build.ps1') -Source $w[1] -Output $w[2] | Out-Null
}
$lease = Get-AmigaPort $Port 'amiga-68000' $Minutes
"lease taken $(Get-Date -Format T): $($lease.Tag)"
try {
    foreach ($job in $Jobs) {
        $w = $job -split '\s+'
        $kind = $w[0]
        if ($kind -eq 'flash') {
            $sec = 0; if ($w.Count -gt 3) { $sec = [int]$w[3] }
            & (Join-Path $PSScriptRoot 'build.ps1') -Source $w[1] -Output $w[2] -Port $Port -Seconds $sec
        } elseif ($kind -eq 'vectors') {
            & (Join-Path $PSScriptRoot 'build.ps1') -Source $w[1] -Output $w[2] -Port $Port -Seconds 0
            $rest = @(); if ($w.Count -gt 3) { $rest = $w[3..($w.Count - 1)] }
            & py -3 (Join-Path $PSScriptRoot 'stream.py') --port $Port @rest
            "vectors exit $LASTEXITCODE"
        } else {
            "unknown job: $job"
        }
    }
} finally {
    Release-BoardLease $lease
    "lease released $(Get-Date -Format T)"
}
