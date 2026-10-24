#!/bin/bash
# Build a desktop program: desktop/build.sh <name> [console]
#   desktop/build.sh amiga_cli console   ->  desktop/amiga_cli.exe
#   desktop/build.sh amiga               ->  desktop/amiga.exe (the window program)
cd "$(dirname "$0")"
flags="/OPTIMIZER /THREAD /DPIAWARE"
[ "${2:-}" = "console" ] && flags="/CONSOLE /OPTIMIZER /THREAD"
powershell.exe -NoProfile -Command "& 'C:\Program Files\PureBasic\Compilers\pbcompilerc.exe' '$(cygpath -w "$1.pb")' $flags /CONSTANT 'GL_ENGINE_DIR\$=C:/Users/ajtaj/Desktop/Neon-Arcade-Dispay-Engine/' /EXE '$(cygpath -w "$1.exe")'" > "$1.build.log" 2>&1
if grep -q "Error\|error" "$1.build.log"; then cat "$1.build.log"; exit 1; fi
echo "built desktop/$1.exe"
