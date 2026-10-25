"""Send the compact 68000 test stream (tools/vectors.py) to the board running
Diagnostics/vectors.picow and print what it reports. The board runs and judges
every test; this only moves bytes and collects the verdict lines.

    py -3 tools/stream.py --port COM7 [--only A,B] [--skip C] [--part k/n] [--log f]

Exit code 0 only when the board's last line is '... PASS'.
"""
import argparse, os, sys, threading, time
from pathlib import Path
import serial

# the streams tools/vectors.py writes: SST_680X0_DIR, or tests/680x0/compact here
STREAMS = Path(os.environ.get('SST_680X0_DIR') or Path(__file__).resolve().parent.parent / 'tests' / '680x0' / 'compact')

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', required=True)
    ap.add_argument('--dir', default=str(STREAMS))
    ap.add_argument('--only', default='', help='comma-separated file names (without .m68c) or prefixes')
    ap.add_argument('--skip', default='')
    ap.add_argument('--part', default='', help='k/n: the k-th of n slices of the file list, by size')
    ap.add_argument('--log', default='')
    ap.add_argument('--wait', type=float, default=40.0)
    args = ap.parse_args()
    files = sorted(Path(args.dir).glob('*.m68c'))
    if args.only:
        keys = args.only.split(',')
        files = [f for f in files if any(f.stem == k or f.stem.startswith(k) for k in keys)]
    if args.skip:
        keys = args.skip.split(',')
        files = [f for f in files if not any(f.stem == k or f.stem.startswith(k) for k in keys)]
    if args.part:
        k, n = map(int, args.part.split('/'))
        total = sum(f.stat().st_size for f in files)
        lo, hi = total * (k - 1) / n, total * k / n
        acc, sel = 0, []
        for f in files:
            mid = acc + f.stat().st_size / 2
            if lo <= mid < hi:
                sel.append(f)
            acc += f.stat().st_size
        files = sel
    if not files:
        raise SystemExit('no stream files selected')
    log = open(args.log, 'a', encoding='utf-8') if args.log else None
    def out(line):
        print(line, flush=True)
        if log:
            log.write(line + '\n')
            log.flush()
    port = None
    deadline = time.time() + args.wait
    while port is None:
        try:
            port = serial.Serial(args.port, 115200, timeout=0.2, write_timeout=None)
        except Exception:
            if time.time() > deadline:
                raise SystemExit(f'{args.port} did not open within {args.wait} s')
            time.sleep(0.5)
    port.dtr = True
    lines = []
    cond = threading.Condition()
    stop = [False]
    def reader():
        buf = b''
        while not stop[0]:
            try:
                chunk = port.read(port.in_waiting or 1)
            except Exception as ex:
                with cond:
                    lines.append(f'READ ERROR {ex}')
                    cond.notify_all()
                return
            if not chunk:
                continue
            buf += chunk
            while b'\n' in buf:
                ln, buf = buf.split(b'\n', 1)
                with cond:
                    lines.append(ln.decode('latin-1').rstrip('\r'))
                    cond.notify_all()
    threading.Thread(target=reader, daemon=True).start()
    seen = [0]
    def take(pred, timeout):
        end = time.time() + timeout
        with cond:
            while True:
                while seen[0] < len(lines):
                    ln = lines[seen[0]]
                    seen[0] += 1
                    out(ln)
                    if pred(ln):
                        return ln
                left = end - time.time()
                if left <= 0:
                    return None
                cond.wait(left)
    if take(lambda l: l.startswith('READY'), args.wait) is None:
        stop[0] = True
        raise SystemExit('the board never printed READY')
    t0 = time.time()
    size = sum(f.stat().st_size for f in files)
    def sender():
        for f in files:
            port.write(f.read_bytes())
        port.write(b'Z')
    threading.Thread(target=sender, daemon=True).start()
    last = take(lambda l: l.startswith('vectors '), 60 + size / 50000)
    dt = time.time() - t0
    out(f'host: {len(files)} files, {size} bytes in {dt:.1f} s ({size / dt / 1000:.0f} KB/s)')
    stop[0] = True
    port.close()
    if last is None:
        out('host: no final verdict from the board')
        sys.exit(1)
    sys.exit(0 if last.rstrip().endswith('PASS') else 1)

if __name__ == '__main__':
    main()
