#!/bin/bash
# The PureMetal demo on the Feather: speed, the time profile, and chip RAM at
# frame 1000 compared byte for byte with the PC's (amiga_cli --dump-chip).
#   tools/pico_demo_check.sh [rom]      (default demo/PureMetalDemo.rom)
cd "$(dirname "$0")/.."
rom=${1:-demo/PureMetalDemo.rom}
T=$(cygpath -w "${TEMP:-/tmp}")
# no stale result can pass: both dumps are made fresh by this run or the check fails
rm -f "$(cygpath -u "$T")"/chip_pc.bin* "$(cygpath -u "$T")"/chip_pico.bin*
# the PC side at the Picos' 48 kHz, so Paula's samples line up one for one
[ desktop/amiga_cli_48k.exe -nt desktop/amiga_cli.exe ] || (cd desktop && powershell.exe -NoProfile -Command "& 'C:\Program Files\PureBasic\Compilers\pbcompilerc.exe' 'amiga_cli.pb' /CONSOLE /OPTIMIZER /THREAD /CONSTANT 'AUD_RATE_48K=1' /EXE 'amiga_cli_48k.exe'" > /dev/null)
desktop/amiga_cli_48k.exe --rom "$rom" --frames 1000 --dump-chip "$T\chip_pc.bin" > /dev/null
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w tools/pico_machine.ps1)" -Port COM20 -Board feather2350 \
  -Rom "$rom" -Seconds 40 -Prof 6 -Dump "$T\chip_pico.bin" -DumpFrame 1000 -Minutes 3 2>&1 | grep -E "PROF|^frames|chip RAM|FATAL|ERROR|PM[0-9]" | head -6
py -3 - "$T\chip_pc.bin" "$T\chip_pico.bin" <<'PY'
import sys, os
if not (os.path.exists(sys.argv[1]) and os.path.exists(sys.argv[2])):
    sys.exit('FAILED: a dump is missing - the board run did not complete')
a = open(sys.argv[1], 'rb').read(); b = open(sys.argv[2], 'rb').read()
diff = sum(1 for x, y in zip(a, b) if x != y)
print('chip RAM at frame 1000:', 'IDENTICAL to the PC' if a == b else f'{diff} bytes differ from the PC')
# Paula: the PC keeps 16384 stereo slots, the Pico 4096 mono ones; the same
# sample number is at (number mod size) in each - compare the last 4096
import struct
pa = open(sys.argv[1] + '.aud', 'rb').read(); pb = open(sys.argv[2] + '.aud', 'rb').read()
wa, = struct.unpack_from('<I', pa); wb, = struct.unpack_from('<I', pb)
A = struct.unpack('>16384h', pa[4:]); B = struct.unpack('>4096h', pb[4:])
if wa != wb:
    print(f'audio: {wa} samples on the PC, {wb} on the Pico')
else:
    bad = sum(1 for i in range(wa - 4096, wa) if A[i % 16384] != B[i % 4096])
    print('audio, the last 4096 samples:', 'IDENTICAL to the PC' if bad == 0 else f'{bad} differ from the PC')
PY
