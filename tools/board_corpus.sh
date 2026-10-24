#!/bin/bash
# The whole 68000 corpus on a board, in short legs, each under its own lease
# (tools/board.ps1 -> lease.ps1), with a gap between legs for other workers.
#   tools/board_corpus.sh <port> <source> <output.uf2> <log> [legs]
cd "$(dirname "$0")/.."
port=$1; src=$2; out=$3; log=$4; legs=${5:-4}
for k in $(seq 1 $legs); do
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w tools/board.ps1)" -Port $port -Minutes 4 \
    -Jobs "vectors $src $out --part $k/$legs --log $log"
  [ $k -lt $legs ] && sleep 30
done
