"""Which 68000 handlers a program spends its instructions in.

    desktop/amiga_cli_hist.exe --rom <rom> --frames N     (writes m68k_hist.bin)
    py -3 tools/hist_report.py m68k_hist.bin [top]

amiga_cli_hist.exe is amiga_cli built with /CONSTANT M68K_HIST=1 over the core
tools/gen_m68k.py --hist writes (desktop/m68k_core_hist.pbi): every opcode run
is counted. This groups the counts by the handler the RP2350 core dispatches
to (opcode >> 6), and lists the busiest opcodes themselves.
"""
import struct, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import gen_m68k

def main():
    counts = struct.unpack('<65536q', open(sys.argv[1], 'rb').read())
    top = int(sys.argv[2]) if len(sys.argv) > 2 else 30
    gen_m68k.generate('rp2350')            # fills the dispatch table
    total = sum(counts)
    by = {}
    for op, n in enumerate(counts):
        if n:
            h = gen_m68k.DISPATCH[op >> 6]
            by[h] = by.get(h, 0) + n
    print(f'{total:,} instructions')
    print('by handler:')
    for h, n in sorted(by.items(), key=lambda x: -x[1])[:top]:
        print(f'  {h:24s} {n:>12,} {100 * n / total:5.1f}%')
    print('busiest opcodes:')
    for op, n in sorted(enumerate(counts), key=lambda x: -x[1])[:top]:
        print(f'  ${op:04X} {gen_m68k.DISPATCH[op >> 6]:24s} {n:>12,} {100 * n / total:5.1f}%')

if __name__ == '__main__':
    main()
