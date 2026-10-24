# The shared lease (C:\PMFBuild\board-leases\lease.ps1) and its queue turn,
# for tools\board.ps1 and tools\pico_machine.ps1 (dot-sourced).
. C:\PMFBuild\board-leases\lease.ps1

# The queue turn of lease.ps1 (the oldest live ticket in queue\<Port> goes
# first), taken with .NET calls only: from this shell, Get-ChildItem does not
# see the queue folder [IO.Directory] has just made. Same tickets, same order.
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

# Is the port free to open? (Someone may hold it open outside the lease.)
function Test-PortFree([string]$Port) {
    try {
        $sp = New-Object System.IO.Ports.SerialPort $Port, 115200
        $sp.Open(); $sp.Close()
        return $true
    } catch { return $false }
}

# The lease, and a port nobody else holds open.
function Get-AmigaPort([string]$Port, [string]$Owner, [int]$Minutes) {
    for ($try = 1; ; $try++) {
        $lease = Get-AmigaLease $Port $Owner $Minutes
        if (Test-PortFree $Port) { return $lease }
        Release-BoardLease $lease
        "$(Get-Date -Format T): $Port is open in another program although no lease is held; lease given back, trying again in 60 s" | Out-Host
        if ($try -ge 30) { throw "$Port stayed busy outside the lease for 30 minutes" }
        Start-Sleep -Seconds 60
    }
}
