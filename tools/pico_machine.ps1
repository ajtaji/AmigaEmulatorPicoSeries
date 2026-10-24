# The Amiga on a PSRAM board, under the shared lease: build, write the
# Kickstart (or a test ROM) and optionally a disk into the flash regions,
# upload the firmware, then talk to it (tools/pico_session.py).
#
#   powershell -File tools\pico_machine.ps1 -Port COM20 -Board feather2350 -Rom tests\chiptest.rom
#              [-Adf disk.adf] [-Seconds 30] [-ShotAt 20] [-Shot docs\pico_chiptest.png]
param(
    [string]$Port = 'COM20',
    [string]$Board = 'feather2350',
    [string]$Rom = '',
    [string]$Adf = '',
    [int]$Seconds = 30,
    [int]$ShotAt = 20,
    [string]$Shot = '',
    [int]$Minutes = 5
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$pmf = 'C:\Users\ajtaj\Desktop\Github\PureBasicCode\OpenGl Work\ArduinoBasic\PureMetalForge.exe'
. (Join-Path $PSScriptRoot 'lease_turn.ps1')

function Forge([string]$arguments, [string]$log) {
    $p = Start-Process -FilePath $pmf -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru `
        -RedirectStandardOutput $log -RedirectStandardError ($log + '.err')
    Get-Content $log | Select-String -Pattern 'ERROR|VERIFIED|FLASH COMPLETE|uploaded|refus|PM[0-9]{4}' | ForEach-Object { $_.Line }
    if ($p.ExitCode -ne 0) { throw "compiler exit $($p.ExitCode): $log" }
}

$build = Join-Path $root 'Diagnostics\build'
[IO.Directory]::CreateDirectory($build) | Out-Null
$src = Join-Path $root "src\amiga.$Board"
$uf2 = Join-Path $build "amiga_$Board.uf2"
Forge ('--compile "' + $src + '" -o "' + $uf2 + '"') (Join-Path $build 'pm_build.log')
if ($Rom) {
    & py -3 (Join-Path $PSScriptRoot 'pico_media.py') kick $Rom (Join-Path $build 'kick.bin')
    if ($LASTEXITCODE -ne 0) { throw 'pico_media.py kick failed' }
}
if ($Adf) {
    & py -3 (Join-Path $PSScriptRoot 'pico_media.py') adf $Adf (Join-Path $build 'df0.bin')
    if ($LASTEXITCODE -ne 0) { throw 'pico_media.py adf failed' }
}

$lease = Get-AmigaPort $Port 'amiga-machine' $Minutes
"lease taken $(Get-Date -Format T): $($lease.Tag)"
try {
    if ($Rom) {
        Forge ('--storage-write "' + (Join-Path $build 'kick.bin') + '" --offset $200000 --port ' + $Port) (Join-Path $build 'pm_kick.log')
    }
    if ($Adf) {
        Forge ('--storage-write "' + (Join-Path $build 'df0.bin') + '" --offset $280000 --port ' + $Port) (Join-Path $build 'pm_df0.log')
    }
    Forge ('--compile "' + $src + '" -o "' + $uf2 + '" --port ' + $Port) (Join-Path $build 'pm_upload.log')
    $args2 = @('--port', $Port, '--seconds', $Seconds)
    if ($Shot) { $args2 += @('--shot', $Shot, '--at', $ShotAt) }
    & py -3 (Join-Path $PSScriptRoot 'pico_session.py') @args2
} finally {
    Release-BoardLease $lease
    "lease released $(Get-Date -Format T)"
}
