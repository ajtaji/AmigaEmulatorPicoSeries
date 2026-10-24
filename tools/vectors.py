"""Re-encode the SingleStepTests 680x0 JSON (68000/v1) as the compact stream the
test runner reads (Diagnostics/vectors_run.pmi, on the board and on the PC).

    py -3 tools/vectors.py <json.gz dir> <out dir>

One output file per input file, <name>.m68c, holding one group. Little-endian:
    group:  'G'  u8 name length, name, u32 count, then count tests
    test:   15 x u32  D0-D7, A0-A6        initial
            u32 USP, u32 SSP, u16 SR, u32 PC, u16 prefetch[2]
            u8 n, n x u32 (address << 8 | byte)        initial RAM
            u32 mask: bit k = final register k differs (0-14 D0-A6,
                      15 USP, 16 SSP, 17 SR, 18 PC), then a u32 per set bit
            u8 n, n x u32 (address << 8 | byte)        final RAM: only the
                      bytes that are new or changed
            u16 cycles
The end of a stream is 'Z'. This re-encodes the published tests; the runner
executes and judges them.
"""
import gzip, json, struct, sys
from pathlib import Path

REGS = ['d0', 'd1', 'd2', 'd3', 'd4', 'd5', 'd6', 'd7',
        'a0', 'a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'usp', 'ssp', 'sr', 'pc']

def ram_words(entries):
    return b''.join(struct.pack('<I', ((a & 0xFFFFFF) << 8) | (v & 0xFF)) for a, v in entries)

def enc_test(t):
    a, b = t['initial'], t['final']
    out = [struct.pack('<15I', *[a[r] & 0xFFFFFFFF for r in REGS[:15]])]
    out.append(struct.pack('<IIHIHH', a['usp'], a['ssp'], a['sr'], a['pc'], *a['prefetch']))
    if len(a['ram']) > 255 or len(b['ram']) > 255:
        raise ValueError('more than 255 RAM entries')
    out.append(struct.pack('<B', len(a['ram'])) + ram_words(a['ram']))
    mask = 0
    vals = []
    for k, r in enumerate(REGS):
        if a[r] != b[r]:
            mask |= 1 << k
            vals.append(b[r] & 0xFFFFFFFF)
    out.append(struct.pack('<I', mask) + b''.join(struct.pack('<I', v) for v in vals))
    init = {x & 0xFFFFFF: v for x, v in a['ram']}
    pf = a['prefetch']
    for i, byte in enumerate((pf[0] >> 8, pf[0] & 255, pf[1] >> 8, pf[1] & 255)):
        init.setdefault((a['pc'] + i) & 0xFFFFFF, byte)
    changed = [(x & 0xFFFFFF, v) for x, v in b['ram'] if init.get(x & 0xFFFFFF) != v]
    out.append(struct.pack('<B', len(changed)) + ram_words(changed))
    out.append(struct.pack('<H', t['length']))
    return b''.join(out)

def enc_group(name, tests):
    nb = name.encode()
    return b'G' + struct.pack('<B', len(nb)) + nb + struct.pack('<I', len(tests)) + b''.join(enc_test(t) for t in tests)

def main():
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    dst.mkdir(parents=True, exist_ok=True)
    total = 0
    size = 0
    for f in sorted(src.glob('*.json.gz')):
        name = f.name[:-len('.json.gz')]
        tests = json.load(gzip.open(f))
        blob = enc_group(name, tests)
        (dst / (name + '.m68c')).write_bytes(blob)
        total += len(tests)
        size += len(blob)
        print(name, len(tests), len(blob))
    print('total', total, 'tests', size, 'bytes')

if __name__ == '__main__':
    main()
