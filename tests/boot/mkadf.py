"""Make tests/boot/boot.adf: bootblock.bin in sectors 0-1 (checksum fixed),
prog.bin from byte 1024 padded to 20 KB with a known pattern; prints the sum
the program must report.
    py -3 tests/boot/mkadf.py <bootblock.bin> <prog.bin> <out.adf>"""
import sys, struct
bb, pg, out = sys.argv[1:4]
boot = bytearray(open(bb, 'rb').read())
assert len(boot) == 1024, len(boot)
prog = bytearray(open(pg, 'rb').read())
PSIZE = 20480
assert len(prog) <= PSIZE - 64
x = 0x12345678
while len(prog) < PSIZE:
    x = (x * 1103515245 + 12345) & 0xFFFFFFFF
    prog += struct.pack('>H', x >> 16)
struct.pack_into('>L', boot, 4, 0)
s = 0
for i in range(256):
    s += struct.unpack_from('>L', boot, i * 4)[0]
    if s > 0xFFFFFFFF:
        s = (s & 0xFFFFFFFF) + 1
struct.pack_into('>L', boot, 4, (~s) & 0xFFFFFFFF)
disk = boot + prog + bytes(901120 - 1024 - PSIZE)
open(out, 'wb').write(disk)
total = sum(struct.unpack('>%dL' % (PSIZE // 4), prog)) & 0xFFFFFFFF
print(f'{out}: expect "prog: sum of the 20 KB = {total:08X}"')
