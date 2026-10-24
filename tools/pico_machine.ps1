# The Amiga on a PSRAM board, under the shared lease: build, write the
# Kickstart (or a test ROM) and optionally a disk into the flash regions,
# upload the firmware, then talk to it (tools/pico_session.py).
#
#   powershell -File tools\pico_machine.ps1 -Port COM20 -Board feather2350 -Rom tests\chiptest.rom
#              [-Adf disk.adf] [-Seconds 30] [-ShotAt 20] [-Shot docs\pico_chiptest.png]
#              [-Dump chip.bin -DumpFrame 400]   chip RAM after that frame (diff with amiga_cli --dump-chip)
#              [-Source private.picoplus2w -Speaker]   a private wrapper with the speaker's address;
#                 -Speaker takes the SPEAKER lease after the board's (BOARDS.md order) and puts the
#                 silent published build back on the board before giving the speaker up
param(
    [string]$Port = 'COM20',
    [string]$Board = 'feather2350',
    [string]$Rom = '',
    [string]$Adf = '',
    [int]$Seconds = 30,
    [int]$ShotAt = 20,
    [string]$Shot = '',
    [int]$Minutes = 5,
    [string]$Dump = '',
    [string]$Source = '',
    [switch]$Speaker,
    [int]$Prof = 0,
    [switch]$Unpaced,
    [int]$DumpFrame = 400
)
$ErrorActionPreference = 'Stop'
# the flash regions of each board's wrapper (srcmiga.<board>)
if ($Board -eq 'feather2350') { $KickOffset = '$040000'; $Df0Offset = '$0C0000' } else { $KickOffset = '$800000'; $Df0Offset = '$880000' }
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
$silent = Join-Path $root "src\amiga.$Board"
$src = $silent
if ($Source) { $src = (Resolve-Path $Source).Path }
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

if ($Speaker) {
    $silentUf2 = Join-Path $build "amiga_${Board}_silent.uf2"
    Forge ('--compile "' + $silent + '" -o "' + $silentUf2 + '"') (Join-Path $build 'pm_silent.log')
}
$lease = Get-AmigaPort $Port 'amiga-machine' $Minutes
"lease taken $(Get-Date -Format T): $($lease.Tag)"
$spk = $null
try {
    if ($Speaker) {
        $spk = Get-BoardLease -Port SPEAKER -Owner 'amiga-machine' -Minutes $Minutes
        "speaker lease taken $(Get-Date -Format T)"
    }
    if ($Rom) {
        Forge ('--storage-write "' + (Join-Path $build 'kick.bin') + '" --offset ' + $KickOffset + ' -t rp2350 --port ' + $Port) (Join-Path $build 'pm_kick.log')
    }
    if ($Adf) {
        Forge ('--storage-write "' + (Join-Path $build 'df0.bin') + '" --offset ' + $Df0Offset + ' -t rp2350 --port ' + $Port) (Join-Path $build 'pm_df0.log')
    }
    Forge ('--compile "' + $src + '" -o "' + $uf2 + '" --port ' + $Port) (Join-Path $build 'pm_upload.log')
    $args2 = @('--port', $Port, '--seconds', $Seconds)
    if ($Shot) { $args2 += @('--shot', $Shot, '--at', $ShotAt) }
    if ($Dump) { $args2 += @('--dump', $Dump, '--dump-frame', $DumpFrame) }
    if ($Prof) { $args2 += @('--prof', $Prof) }
    if ($Unpaced) { $args2 += @('--unpaced') }
    & py -3 (Join-Path $PSScriptRoot 'pico_session.py') @args2
} finally {
    if ($spk) {
        # a board still running a Bluetooth build keeps the speaker: the silent build goes back first
        try {
            Forge ('--compile "' + $silent + '" -o "' + $silentUf2 + '" --port ' + $Port) (Join-Path $build 'pm_silent_upload.log')
        } catch {
            "WARNING: the silent build did not go back on $Port ($_): the board may still hold the speaker"
        }
        Release-BoardLease $spk
        "speaker lease released $(Get-Date -Format T)"
    }
    Release-BoardLease $lease
    "lease released $(Get-Date -Format T)"
}
