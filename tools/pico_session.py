"""Talk to the Pico build of the Amiga over USB serial: print what it says for
a while, optionally type keys, and save the picture it sends.

    py -3 tools/pico_session.py --port COMn [--seconds 20] [--shot pic.png --at 15]
                                [--keys "k45 k44"] [--log file]

--shot asks for a picture (the 's' command) --at seconds after the port opens
and writes it as a PNG (368 x 287: every other hires pixel, as the board sends
it). --keys sends commands (k + two hex digits presses and releases a key).
"""
import argparse, struct, sys, time, zlib
import serial

def png(path, w, h, rows):
    raw = b''.join(b'\x00' + bytes(r) for r in rows)
    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xFFFFFFFF)
    data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
    data += chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')
    open(path, 'wb').write(data)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', required=True)
    ap.add_argument('--seconds', type=float, default=20)
    ap.add_argument('--shot', default='')
    ap.add_argument('--at', type=float, default=10)
    ap.add_argument('--keys', default='')
    ap.add_argument('--log', default='')
    ap.add_argument('--dump', default='', help='write chip RAM (big-endian) here when --dump-frame has run')
    ap.add_argument('--dump-frame', type=int, default=400)
    a = ap.parse_args()
    log = open(a.log, 'a', encoding='utf-8') if a.log else None
    port = serial.Serial(a.port, 115200, timeout=0.1)
    port.dtr = True
    t0 = time.time()
    buf = b''
    asked = False
    keys_sent = False
    rows = None
    chip = None
    dump_sent = False
    while time.time() - t0 < a.seconds:
        if a.shot and not asked and time.time() - t0 >= a.at:
            port.write(b's')
            asked = True
        if a.keys and not keys_sent and time.time() - t0 >= 3:
            for k in a.keys.split():
                port.write(k.encode())
                time.sleep(0.15)
            keys_sent = True
        if a.dump and not dump_sent and time.time() - t0 >= 0.5:
            port.write(b'd%04X' % a.dump_frame)
            dump_sent = True
        buf += port.read(port.in_waiting or 1)
        while b'\n' in buf:
            line, buf = buf.split(b'\n', 1)
            s = line.decode('latin-1').rstrip('\r')
            if s == 'SHOT':
                rows = []
                continue
            if s == 'END' and rows is not None:
                png(a.shot, 368, len(rows), rows)
                print(f'picture: {a.shot} ({len(rows)} lines)')
                rows = None
                continue
            if s.startswith('CHIP'):
                chip = bytearray()
                print(s, flush=True)
                continue
            if s == 'CEND' and chip is not None:
                open(a.dump, 'wb').write(chip)
                print(f'chip RAM: {a.dump} ({len(chip)} bytes)')
                chip = None
                continue
            if chip is not None and s.startswith('C'):
                chip += bytes.fromhex(s[1:])
                continue
            if rows is not None and s.startswith('L'):
                px = []
                h = s[1:]
                for i in range(0, len(h) - 2, 3):
                    c = int(h[i:i + 3], 16)
                    px += [((c >> 8) & 15) * 17, ((c >> 4) & 15) * 17, (c & 15) * 17]
                rows.append(px[:368 * 3] + [0] * (368 * 3 - len(px[:368 * 3])))
                continue
            print(s, flush=True)
            if log:
                log.write(s + '\n')
    port.close()

if __name__ == '__main__':
    main()
