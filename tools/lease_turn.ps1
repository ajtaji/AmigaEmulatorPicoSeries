# Taking and giving back a board. On a shared bench BOARD_LEASE_SCRIPT (tools\env.ps1)
# names the bench's lease script and every board step goes through it; with none, a
# lease is only a name. Dot-sourced by tools\board.ps1 and tools\pico_machine.ps1.
. (Join-Path $PSScriptRoot 'env.ps1')
if ($env:BOARD_LEASE_SCRIPT) {
    . $env:BOARD_LEASE_SCRIPT
} else {
    function Get-BoardLease([string]$Port, [string]$Owner, [int]$Minutes) { return @{ Tag = "$Port (not shared)" } }
    function Release-BoardLease($Lease) { }
}

function Get-AmigaPort([string]$Port, [string]$Owner, [int]$Minutes) {
    return Get-BoardLease -Port $Port -Owner $Owner -Minutes $Minutes
}
