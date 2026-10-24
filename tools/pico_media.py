"""Make the files the Pico build reads from its flash regions.

    py -3 tools/pico_media.py kick <kickstart.rom> <out.bin>   # 512 KB, host word order
    py -3 tools/pico_media.py adf <disk.adf> <out.bin>         # checked, as it is

then write them with the compiler's own uploader:

    PureMetalForge.exe --storage-write out.bin --offset $200000 --port COMn   (kickstart)
    PureMetalForge.exe --storage-write out.bin --offset $280000 --port COMn   (df0)

A 256 KB Kickstart is written twice (the Amiga sees it twice, at $F80000 and
$FC0000). The 68000 core keeps the guest's 16-bit words in host (little-endian)
byte order, so the image's byte pairs are swapped here once.
"""
import sys

def main():
    kind, src, dst = sys.argv[1], sys.argv[2], sys.argv[3]
    data = open(src, 'rb').read()
    if kind == 'kick':
        if len(data) not in (0x40000, 0x80000):
            raise SystemExit(f'{src} is {len(data)} bytes: a Kickstart image is 262144 or 524288 bytes '
                             '(an Amiga Forever ROM that needs rom.key is 11 bytes longer and is not supported)')
        if len(data) == 0x40000:
            data = data + data
        swapped = bytearray(len(data))
        swapped[0::2] = data[1::2]
        swapped[1::2] = data[0::2]
        open(dst, 'wb').write(swapped)
        print(f'{dst}: {len(swapped)} bytes, write at offset $200000')
    elif kind == 'adf':
        if len(data) != 901120:
            raise SystemExit(f'{src} is {len(data)} bytes: an .ADF (double density) is 901120 bytes')
        open(dst, 'wb').write(data)
        print(f'{dst}: {len(data)} bytes, write at offset $280000')
    else:
        raise SystemExit('kind is kick or adf')

if __name__ == '__main__':
    main()
