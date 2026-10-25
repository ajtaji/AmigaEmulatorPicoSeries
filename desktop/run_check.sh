#!/bin/bash
# Regenerate the core, build the console checker and run the 68000 tests (the
# compact streams tools/vectors.py writes) through the shared runner.
#   desktop/run_check.sh [name filter]
set -e
cd "$(dirname "$0")/.."
. tools/env.sh
py -3 tools/gen_m68k.py > /dev/null
powershell.exe -NoProfile -Command "& 'C:\Program Files\PureBasic\Compilers\pbcompilerc.exe' '$(cygpath -w desktop/m68k_check.pb)' /CONSOLE /OPTIMIZER /EXE '$(cygpath -w desktop/m68k_check.exe)'" > desktop/m68k_check.build.log || { cat desktop/m68k_check.build.log; exit 1; }
if grep -qi "error" desktop/m68k_check.build.log; then cat desktop/m68k_check.build.log; exit 1; fi
desktop/m68k_check.exe "$SST_680X0_DIR" "${1:-}"
