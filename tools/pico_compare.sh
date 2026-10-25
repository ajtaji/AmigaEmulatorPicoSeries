#!/bin/bash
# Chip RAM and Paula's output on a board against the PC at one frame, for any
# set-up: tools/pico_compare.sh <frame> <rom> [ext] [adf] [port] [board] [wrapper] [lease port]
# (the default board is the Feather on COM20). The machine is deterministic,
# so the two must be identical; the first frame where they are not is where a
# Pico-only difference shows itself.
cd "$(dirname "$0")/.."
frame=$1; rom=$2; ext=${3:-}; adf=${4:-}; port=${5:-COM20}; board=${6:-feather2350}; source=${7:-}; leaseport=${8:-}
T=$(cygpath -w "${TEMP:-/tmp}")
rm -f "$(cygpath -u "$T")"/cmp_pc.bin* "$(cygpath -u "$T")"/cmp_pico.bin*
[ desktop/amiga_cli_48k.exe -nt desktop/amiga_cli.exe ] || (cd desktop && powershell.exe -NoProfile -Command "& 'C:\Program Files\PureBasic\Compilers\pbcompilerc.exe' 'amiga_cli.pb' /CONSOLE /OPTIMIZER /THREAD /CONSTANT 'AUD_RATE_48K=1' /EXE 'amiga_cli_48k.exe'" > /dev/null)
args=(--rom "$rom" --frames "$frame" --dump-chip "$T\cmp_pc.bin")
[ -n "$ext" ] && args+=(--ext "$ext")
[ -n "$adf" ] && args+=(--adf "$adf")
desktop/amiga_cli_48k.exe "${args[@]}" > /dev/null
pargs=(-Port $port -Board $board -Rom "$rom" -Seconds 120 -Dump "$T\cmp_pico.bin" -DumpFrame $frame -Minutes 4)
[ -n "$ext" ] && pargs+=(-Ext "$ext")
[ -n "$adf" ] && pargs+=(-Adf "$adf")
[ -n "$source" ] && pargs+=(-Source "$source")
[ -n "$leaseport" ] && pargs+=(-LeasePort "$leaseport")
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w tools/pico_machine.ps1)" "${pargs[@]}" 2>&1 | tr -d '\r' | grep -E "chip RAM|FATAL|ERROR|PM[0-9]" | head -3
py -3 - "$T\cmp_pc.bin" "$T\cmp_pico.bin" <<'PY'
import sys, os
if not (os.path.exists(sys.argv[1]) and os.path.exists(sys.argv[2])):
    sys.exit('FAILED: a dump is missing - the board run did not complete')
a = open(sys.argv[1], 'rb').read(); b = open(sys.argv[2], 'rb').read()
d = [i for i in range(len(a)) if a[i] != b[i]]
print('chip RAM:', 'IDENTICAL to the PC' if not d else f'{len(d)} bytes differ, first at ${d[0]:05X}')
for i in d[:8]:
    print(f'  ${i:05X} pc {a[i]:02X} pico {b[i]:02X}')
if os.path.exists(sys.argv[1] + '.slow') and os.path.exists(sys.argv[2] + '.slow'):
    a = open(sys.argv[1] + '.slow', 'rb').read(); b = open(sys.argv[2] + '.slow', 'rb').read()
    d = [i for i in range(min(len(a), len(b))) if a[i] != b[i]]
    print('slow RAM:', 'IDENTICAL to the PC' if not d else f'{len(d)} bytes differ, first at ${0xC00000 + d[0]:06X}')
    for i in d[:8]:
        print(f'  ${0xC00000 + i:06X} pc {a[i]:02X} pico {b[i]:02X}')
PY
