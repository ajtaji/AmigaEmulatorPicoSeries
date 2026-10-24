# Boards are taken and given back ONLY through the shared lease script
# (C:\PMFBuild\board-leases\lease.ps1, see BOARDS.md there). Dot-sourced by
# tools\board.ps1 and tools\pico_machine.ps1.
. C:\PMFBuild\board-leases\lease.ps1

function Get-AmigaPort([string]$Port, [string]$Owner, [int]$Minutes) {
    return Get-BoardLease -Port $Port -Owner $Owner -Minutes $Minutes
}
