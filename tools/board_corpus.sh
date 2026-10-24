#!/bin/bash
# The whole 68000 corpus on the Pico W (COM7), in three runs of under 3 minutes,
# each under its own lease, a minute apart so other workers get their turns.
cd "$(dirname "$0")/.."
for k in 1 2 3; do
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w tools/board.ps1)" -Port COM7 -Minutes 5 \
    -Jobs "vectors Diagnostics/vectors.picow Diagnostics/build/vectors.uf2 --part $k/3 --log docs/board_corpus_picow.log"
  [ $k -lt 3 ] && sleep 60
done
