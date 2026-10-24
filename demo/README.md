# PureMetal on the Amiga

A demo for the Amiga 500 - and for this emulator - written entirely in PureMetal, with no inline
assembly, and compiled for the 68000 by PureMetal Forge.

- **"PUREMETAL"** in big shaded letters: three bitplanes, with a highlight that the copper sweeps
  through gold and white, line by line
- **copper bars**: three bars sliding on a sine behind everything
- **a sine scroller**: the text slid along by the blitter and cut into twenty sixteen-pixel
  columns, each on its own sine, with a rainbow down it
- **eight hardware sprites**: shaded balls on a Lissajous path
- **an original four-channel tune** on Paula: bass, lead, chords and drums. The drums are one-shot
  samples, ended by Paula's audio interrupt

The 68000 does very little of this itself: it points the custom chips at the data and moves the
numbers along. The copper's colour columns are filled by the blitter, a column of colours copied into
every line's MOVE in one blit; two copper lists are kept, and the one on the screen is never written.

## Files

| File | What it is |
|---|---|
| `demo.amiga` | the program |
| `demo_assets.amiga` | the logo, font, sprite, tables, samples and tune - generated, do not edit |
| `make_demo_assets.py` | makes `demo_assets.amiga`: `py -3 demo/make_demo_assets.py` (needs Pillow); `--check` says whether the committed file is current |
| `fonts/Lato-Regular.ttf` | the typeface of the logo and the scroller (SIL Open Font License 1.1, `fonts/OFL.txt`) |
| `PureMetalDemo.adf` | the built floppy: boot it in DF0 |
| `PureMetalDemo.rom` | the same program as a 256 KB ROM image (at $FC0000): it starts the demo with no disk and no Kickstart - use it where a Kickstart file goes |
| `PureMetalDemo.bin` | the program image itself, loaded at $40000 |

The three `PureMetalDemo` files are what the build below writes; the repository ignores `.adf`, `.rom`
and `.bin` files, so build them before running.

## Building

> Needs the PureMetal Forge compiler build of 2026-10-23 or later.

```
PureMetalForge.exe --compile demo/demo.amiga -o demo/PureMetalDemo.bin
```

The `.amiga` extension selects PureMetal Forge's Amiga 500 board: the program is loaded at $40000,
its variables start at $1000, and the compiler writes `PureMetalDemo.adf` beside the `.bin` - an
OFS bootblock that loads the program through the ROM's own floppy driver and jumps to it, with the
rest of the disk holding the program. No AmigaDOS files are on the disk and none are needed. The
program takes the machine over: interrupts and DMA off, its own vector table, then the copper,
bitplanes, sprites, blitter and audio turned on.

## Running

On this emulator's desktop program, or headless:

```
desktop/amiga_cli.exe --rom bootrom/bootrom.rom --adf demo/PureMetalDemo.adf --frames 500 --shot demo.png
desktop/amiga_cli.exe --rom demo/PureMetalDemo.rom --frames 500 --shot demo.png
```

The first boots the floppy the way an Amiga does (this emulator's own boot ROM reads the bootblock and
gives it the trackdisk request it uses); the second needs no disk at all.
