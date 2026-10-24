#!/bin/bash
# The PureMetal demo on the Feather: speed, the time profile, and chip RAM at
# frame 400 compared byte for byte with the PC's (amiga_cli --dump-chip).
#   tools/pico_demo_check.sh [rom]      (default demo/PureMetalDemo.rom)
cd "$(dirname "$0")/.."
rom=${1:-demo/PureMetalDemo.rom}
T=$(cygpath -w "${TEMP:-/tmp}")
desktop/amiga_cli.exe --rom "$rom" --frames 400 --dump-chip "$T\chip_pc.bin" > /dev/null
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w tools/pico_machine.ps1)" -Port COM20 -Board feather2350 \
  -Rom "$rom" -Seconds 40 -Prof 6 -Dump "$T\chip_pico.bin" -DumpFrame 400 -Minutes 3 2>&1 | grep -E "PROF|^frames|chip RAM|FATAL|ERROR|PM[0-9]" | head -6
py -3 - "$T\chip_pc.bin" "$T\chip_pico.bin" <<'PY'
import sys
a = open(sys.argv[1], 'rb').read(); b = open(sys.argv[2], 'rb').read()
diff = sum(1 for x, y in zip(a, b) if x != y)
print('chip RAM at frame 400:', 'IDENTICAL to the PC' if a == b else f'{diff} bytes differ from the PC')
PY
