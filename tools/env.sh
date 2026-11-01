# Where the scripts find what is outside this repository. Each comes from the
# environment, or from tools/local.sh (not in git: set them there for your own
# machine), or else the default here. Sourced by desktop/build.sh and
# desktop/run_check.sh, on Windows (Git Bash) and on Linux.
#   NEON_ENGINE_DIR  the Neon Arcade Display Engine checkout, ending in /
#                    (default: Neon-Arcade-Dispay-Engine beside this repository)
#   SST_680X0_DIR    the 68000 test streams tools/vectors.py writes
#                    (default: tests/680x0/compact in this repository)
#   PB_COMPILER      PureBasic 6 x64's C back end compiler
#                    (default: Windows C:\Program Files\PureBasic\Compilers\pbcompilerc.exe,
#                    Linux $PUREBASIC_HOME/compilers/pbcompilerc)
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$repo_root/tools/local.sh" ] && . "$repo_root/tools/local.sh"
if command -v cygpath > /dev/null; then
  host_os=windows
  : "${NEON_ENGINE_DIR:=$(cygpath -m "$repo_root/..")/Neon-Arcade-Dispay-Engine/}"
  : "${SST_680X0_DIR:=$(cygpath -w "$repo_root/tests/680x0/compact")}"
  : "${PB_COMPILER:=C:\\Program Files\\PureBasic\\Compilers\\pbcompilerc.exe}"
else
  host_os=linux
  : "${NEON_ENGINE_DIR:=$(cd "$repo_root/.." && pwd)/Neon-Arcade-Dispay-Engine/}"
  : "${SST_680X0_DIR:=$repo_root/tests/680x0/compact}"
  : "${PB_COMPILER:=$PUREBASIC_HOME/compilers/pbcompilerc}"
fi
