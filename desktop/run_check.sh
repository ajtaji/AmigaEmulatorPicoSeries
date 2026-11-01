#!/bin/bash
# Regenerate the core, build the console checker and run the 68000 tests (the
# compact streams tools/vectors.py writes) through the shared runner, on
# Windows (Git Bash) or Linux.
#   desktop/run_check.sh [name filter]
set -e
cd "$(dirname "$0")/.."
. tools/env.sh
if [ "$host_os" = windows ]; then py=(py -3); else py=(python3); fi
"${py[@]}" tools/gen_m68k.py > /dev/null
rm -f desktop/m68k_check.exe desktop/m68k_check
desktop/build.sh m68k_check console
if [ "$host_os" = windows ]; then exe=desktop/m68k_check.exe; else exe=desktop/m68k_check; fi
"$exe" "$SST_680X0_DIR" "${1:-}"
