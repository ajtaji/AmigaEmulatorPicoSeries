# The desktop programs on Windows and Linux

One source builds on both. Everything the programs need from the operating
system - the window and its GL context, drawing, keys, the mouse, full screen,
the pointer, the sound card, gamepads, the work area - comes through the
[Neon Arcade Display Engine](https://github.com/ajtaji/Neon-Arcade-Dispay-Engine)
(its HOST SERVICES section in `GlUtilities.pbi`); no program here calls the
operating system itself. Keys are `#PB_Shortcut_` codes, or the engine's
`#GL_Key_` codes for the keys PureBasic has none for (`controls.pbi`).

| Program | What it is |
|---|---|
| `amiga` | the window program |
| `amiga_cli` | the machine without a window (serial output, picture, chip RAM and sound dumps) |
| `m68k_check` | the 68000 core against SingleStepTests 680x0 |
| `m68k_run` | a 68000 program run on the bare core |

## Windows

PureBasic 6.41 x64 (C back end). Clone the engine beside this repository, then
from the repository:

```
"C:\Program Files\PureBasic\Compilers\pbcompilerc.exe" desktop\amiga.pb /OPTIMIZER /THREAD /DPIAWARE /EXE desktop\amiga.exe
"C:\Program Files\PureBasic\Compilers\pbcompilerc.exe" desktop\amiga_cli.pb /CONSOLE /OPTIMIZER /THREAD /EXE desktop\amiga_cli.exe
desktop\amiga.exe --adf demo\PureMetalDemo.adf
```

## Linux

PureBasic 6.41 x64 for Linux, with the packages its GTK 3 programs need, plus
ALSA (`libasound2`) for sound and X11 (the engine runs the window on X11, also
under a Wayland desktop through XWayland). Clone the engine beside this
repository, then from the repository:

```
export PUREBASIC_HOME=~/purebasic
$PUREBASIC_HOME/compilers/pbcompilerc desktop/amiga.pb -z -t -o desktop/amiga
$PUREBASIC_HOME/compilers/pbcompilerc desktop/amiga_cli.pb -z -t -cl -o desktop/amiga_cli
desktop/amiga --adf demo/PureMetalDemo.adf
```

Build the programs from a Linux file system: under WSL, a copy of both
repositories in the Linux home, not `/mnt/c` (from there the Linux compiler
includes a file twice and stops with "Procedure is already declared").

## The scripts (both systems)

`desktop/build.sh <name> [console]` builds `desktop/<name>` (`.exe` on
Windows, from Git Bash), and `desktop/run_check.sh` regenerates the core,
builds `m68k_check` and runs the 68000 tests. They take the compiler from
`PB_COMPILER`, the engine from `NEON_ENGINE_DIR` and the tests from
`SST_680X0_DIR` (defaults in `tools/env.sh`; your own in `tools/local.sh`).

## Checks that need no person

```
desktop/amiga --pointer-test <log>                   the pointer and every control agree (synthetic points)
desktop/amiga --fullscreen-test <log> [<pic.png>]    full screen by its own keys, NTSC and PAL
desktop/amiga --adf <disk> --shot <pic.png> --seconds S
desktop/amiga --adf <disk> --pace-log <log> --shot <pic.png> --seconds S   each drawn frame: the time and the emulated frames it ran
desktop/amiga_cli --rom tests/chiptest.rom --frames 300 --dump-chip <file>
```

Each prints or writes the same results on Windows and Linux: the machine is
deterministic, so `amiga_cli`'s serial output, CPU state, sound ring hash and
chip RAM dump are byte-identical between the two builds.
