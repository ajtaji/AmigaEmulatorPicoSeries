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
. C:\PMFBuild\board-leases\lease.ps1

# The queue turn of lease.ps1, taken with .NET calls only: from this shell,
# Get-ChildItem does not see the queue folder [IO.Directory] has just made.
function Get-AmigaLease([string]$Port, [string]$Owner, [int]$Minutes) {
    if ($Port -eq 'COM7' -and $Minutes -gt 15) { throw 'COM7: runs over 15 minutes go to COM6 or COM20' }
    $dir = 'C:\PMFBuild\board-leases'
    $qdir = Join-Path $dir "queue\$Port"
    [IO.Directory]::CreateDirectory($qdir) | Out-Null
    $path = Join-Path $dir "$Port.lease"
    $ticket = Join-Path $qdir ('{0:D19}-{1}-{2}' -f [DateTime]::UtcNow.Ticks, $Owner, $PID)
    [IO.File]::WriteAllText($ticket, "$Owner pid $PID")
    try {
        while ($true) {
            $first = $null
            $files = @()
            try { $files = [IO.Directory]::GetFiles($qdir) } catch {}
            if (-not [IO.File]::Exists($ticket)) {
                # the folder or the ticket went away under us: put the ticket back
                [IO.Directory]::CreateDirectory($qdir) | Out-Null
                [IO.File]::WriteAllText($ticket, "$Owner pid $PID")
                Start-Sleep -Seconds 1
                continue
            }
            foreach ($t in ($files | Sort-Object)) {
                $tpid = [int]([IO.Path]::GetFileName($t).Split('-')[-1])
                if (Get-Process -Id $tpid -ErrorAction SilentlyContinue) { $first = $t; break }
                try { [IO.File]::Delete($t) } catch {}
            }
            if ($first -eq $ticket) {
                $tag = '{0} {1} pid {2} until {3}' -f $Owner, (Get-Date -Format o), $PID, (Get-Date).AddMinutes($Minutes).ToString('HH:mm')
                try {
                    $fs = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
                    $b = [Text.Encoding]::UTF8.GetBytes($tag); $fs.Write($b, 0, $b.Length); $fs.Close()
                    return [pscustomobject]@{ Path = $path; Tag = $tag }
                } catch {
                    $age = $null
                    try { $age = (Get-Date) - [IO.File]::GetLastWriteTime($path) } catch {}
                    if ($age -and $age.TotalMinutes -gt 30) { Remove-BoardLeaseFile $path; continue }
                }
            }
            Start-Sleep -Seconds 5
        }
    } finally {
        try { [IO.File]::Delete($ticket) } catch {}
    }
}

$root = Split-Path $PSScriptRoot -Parent

# Is the port free to open? (Someone may hold it open outside the lease.)
function Test-PortFree([string]$Port) {
    try {
        $sp = New-Object System.IO.Ports.SerialPort $Port, 115200
        $sp.Open(); $sp.Close()
        return $true
    } catch { return $false }
}

for ($try = 1; ; $try++) {
    $lease = Get-AmigaLease $Port 'amiga-68000' $Minutes
    if (Test-PortFree $Port) { break }
    Release-BoardLease $lease
    "$(Get-Date -Format T): $Port is open in another program although no lease is held; lease given back, trying again in 60 s"
    if ($try -ge 30) { throw "$Port stayed busy outside the lease for 30 minutes" }
    Start-Sleep -Seconds 60
}
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
