#!/bin/bash
# Build a desktop program, on Windows (Git Bash) or Linux: desktop/build.sh <name> [console]
#   desktop/build.sh amiga_cli console   ->  desktop/amiga_cli.exe (Windows), desktop/amiga_cli (Linux)
#   desktop/build.sh amiga               ->  desktop/amiga.exe / desktop/amiga (the window program)
# The compiler and the engine: tools/env.sh (PB_COMPILER, NEON_ENGINE_DIR).
cd "$(dirname "$0")"
. ../tools/env.sh
if [ "$host_os" = windows ]; then
  flags="/OPTIMIZER /THREAD /DPIAWARE"
  [ "${2:-}" = "console" ] && flags="/CONSOLE /OPTIMIZER /THREAD"
  # through PowerShell: Git Bash would turn /CONSOLE into a path
  powershell.exe -NoProfile -Command "& '$PB_COMPILER' '$(cygpath -w "$1.pb")' $flags /CONSTANT 'GL_ENGINE_DIR\$=$NEON_ENGINE_DIR' /EXE '$(cygpath -w "$1.exe")'" > "$1.build.log" 2>&1
  out="$1.exe"
else
  flags="-z -t"
  [ "${2:-}" = "console" ] && flags="-z -t -cl"
  "$PB_COMPILER" "$1.pb" $flags -co "GL_ENGINE_DIR\$=$NEON_ENGINE_DIR" -o "$1" > "$1.build.log" 2>&1
  out="$1"
fi
if grep -q "Error\|error" "$1.build.log" || [ ! -f "$out" ]; then cat "$1.build.log"; exit 1; fi
echo "built desktop/$out"
