"""Check an MFM track against the .ADF it came from, decoding it the way the
AmigaDOS trackdisk format is documented (not with the emulator's code):
sync $4489 $4489, then odd/even longs: info, 16 bytes of label, header
checksum, data checksum, 512 data bytes (all odd bits, then all even bits).

    py -3 tools/mfm_check.py <track.bin> <disk.adf> <track number>
"""
import struct, sys

def longs(words, i, n):
    return [(words[i + 2 * k] << 16) | words[i + 2 * k + 1] for k in range(n)]

def main():
    raw = open(sys.argv[1], 'rb').read()
    adf = open(sys.argv[2], 'rb').read()
    trk = int(sys.argv[3])
    words = list(struct.unpack('>%dH' % (len(raw) // 2), raw))
    found = {}
    i = 0
    while i < len(words) - 600:
        if words[i] == 0x4489 and words[i + 1] == 0x4489:
            p = i + 2
            odd, even = longs(words, p, 2)
            info = ((odd & 0x55555555) << 1) | (even & 0x55555555)
            fmt, t, sec, left = info >> 24, (info >> 16) & 255, (info >> 8) & 255, info & 255
            hdr = longs(words, p, 2 + 8)
            chk = 0
            for v in hdr:
                chk ^= v
            chk &= 0x55555555
            hco, hce = longs(words, p + 20, 2)
            hc = ((hco & 0x55555555) << 1) | (hce & 0x55555555)
            dco, dce = longs(words, p + 24, 2)
            dc = ((dco & 0x55555555) << 1) | (dce & 0x55555555)
            data_odd = longs(words, p + 28, 128)
            data_even = longs(words, p + 28 + 256, 128)
            dchk = 0
            for v in data_odd + data_even:
                dchk ^= v
            dchk &= 0x55555555
            data = b''.join(struct.pack('>I', ((o & 0x55555555) << 1) | (e & 0x55555555)) for o, e in zip(data_odd, data_even))
            want = adf[(trk * 11 + sec) * 512:(trk * 11 + sec + 1) * 512]
            ok = fmt == 0xFF and t == trk and hc == chk and dc == dchk and data == want
            # the clock bits: no two 1 bits in a row, no more than three 0 bits in a row
            bits = ''.join('{:016b}'.format(w) for w in words[p:p + 540])
            mfm_ok = '11' not in bits and '0000' not in bits
            print(f'sector {sec:2d} track {t} left {left:2d} header {"ok" if hc == chk else "BAD"} '
                  f'data checksum {"ok" if dc == dchk else "BAD"} data {"ok" if data == want else "DIFFERS"} '
                  f'MFM {"ok" if mfm_ok else "BAD"}')
            found[sec] = ok and mfm_ok
            i = p + 540
        else:
            i += 1
    good = sum(1 for v in found.values() if v)
    print(f'{good} of 11 sectors good')
    sys.exit(0 if good == 11 and len(found) == 11 else 1)

if __name__ == '__main__':
    main()
