"""Build the PureMetal Amiga demo's graphics, tables and music into demo/demo_assets.amiga.

    py -3 demo/make_demo_assets.py            # write demo/demo_assets.amiga (+ preview PNGs in demo/preview/)
    py -3 demo/make_demo_assets.py --check    # exit 1 if the committed file is not what this tool writes

Everything the demo shows or plays is DATA here and CODE in demo/demo.amiga: this tool renders and
encodes once, on the PC. The DataSection lands in chip RAM with the program (an A500's 512 KB is all
chip RAM), so the copper, the blitter, the bitplanes, the sprites and Paula fetch it where it is.

  Logo      "PUREMETAL" rendered from Lato Regular (fonts/Lato-Regular.ttf, SIL OFL 1.1), thickened,
            outlined and shaded: 3 bitplanes, 320 x 64. Colour 1 the outline, 2-6 the body's shades
            from light to dark, 7 the highlight; the copper replaces colour 7 line by line.
  Font      16 x 16 capitals, digits and punctuation from the same face, for the sine scroller.
  Ball      a 16 x 16 shaded ball for the eight hardware sprites (3 colours).
  Tables    a 256-entry sine (-127..127), a 512-entry rainbow (a hue wheel, twice, so a 148-line
            window never wraps), the copper bars' gradients, the logo's highlight shimmer, and
            Paula's note periods for a 32-byte wave at PAL clock 3,546,895 Hz.
  Waves     Paula's samples, 8-bit signed: a 16-byte square (lead), a 32-byte pulse (chords), a
            64-byte saw (bass), and one-shot drums - a kick (a falling sine), a snare (noise over a
            tone) and a hi-hat (bright noise) - and four bytes of silence for a channel to loop on.
  Song      an original tune, four channels: bass, lead, arpeggiated chords, drums. 16 rows a bar,
            six frames a row.
"""
import argparse, math, os, random, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

HERE = Path(__file__).resolve().parent
LATO = HERE / 'fonts' / 'Lato-Regular.ttf'
OUT = HERE / 'demo_assets.amiga'
PREVIEW = HERE / 'preview'
PAL_CLOCK = 3546895
FONT_CHARS = ' ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,!-:/\'?()+'


def dilate(img, n=1):
    for _ in range(n):
        img = img.filter(ImageFilter.MaxFilter(3))
    return img


# ---------------------------------------------------------------- the logo
def render_logo():
    """320 x 64 of colour numbers 0..7."""
    W, H = 320, 64
    text = 'PUREMETAL'
    font = ImageFont.truetype(str(LATO), 50, layout_engine=ImageFont.Layout.BASIC)
    box = font.getbbox(text)
    w, h = box[2] - box[0], box[3] - box[1]
    mask = Image.new('L', (W, H), 0)
    ImageDraw.Draw(mask).text(((W - w) // 2 - box[0], (H - h) // 2 - box[1]), text, font=font, fill=255)
    body = dilate(mask.point(lambda v: 255 if v >= 110 else 0), 1)
    outline = dilate(body, 2)
    ys = [y for y in range(H) for x in range(W) if body.getpixel((x, y))]
    top, bot = min(ys), max(ys)
    pic = [[0] * W for _ in range(H)]
    for y in range(H):
        t = (y - top) / max(1, bot - top)
        shade = 2 + min(4, int(t * 5))                 # 2 (light) .. 6 (dark), top to bottom
        for x in range(W):
            if body.getpixel((x, y)):
                # the highlight: a thin band a third of the way down
                pic[y][x] = 7 if abs(t - 0.30) < 0.07 else shade
            elif outline.getpixel((x, y)):
                pic[y][x] = 1
    return pic


def planes(pic, depth):
    """A picture of colour numbers -> depth bitplanes, each a list of 16-bit words, row by row."""
    H, W = len(pic), len(pic[0])
    out = []
    for p in range(depth):
        words = []
        for y in range(H):
            for wx in range(W // 16):
                v = 0
                for b in range(16):
                    if (pic[y][wx * 16 + b] >> p) & 1:
                        v |= 0x8000 >> b
                words.append(v)
        out.append(words)
    return out


LOGO_PALETTE = [0x000, 0x113, 0xFFF, 0xDDE, 0xBBC, 0x99B, 0x77A, 0xFFF]


# ---------------------------------------------------------------- the scroller font
def render_font():
    """16 x 16 glyphs, one 16-bit word a row."""
    font = ImageFont.truetype(str(LATO), 17, layout_engine=ImageFont.Layout.BASIC)
    glyphs = []
    for ch in FONT_CHARS:
        img = Image.new('L', (16, 16), 0)
        if ch != ' ':
            box = font.getbbox(ch)
            w, h = box[2] - box[0], box[3] - box[1]
            ImageDraw.Draw(img).text(((16 - w) // 2 - box[0], (16 - h) // 2 - box[1] + 1), ch, font=font, fill=255)
            img = dilate(img.point(lambda v: 255 if v >= 100 else 0), 1)
        rows = []
        for y in range(16):
            v = 0
            for x in range(16):
                if img.getpixel((x, y)):
                    v |= 0x8000 >> x
            rows.append(v)
        glyphs.append(rows)
    return glyphs


def font_map():
    """ASCII 32..127 -> the glyph number (unknown characters are the space)."""
    m = []
    for c in range(32, 128):
        ch = chr(c).upper()
        m.append(FONT_CHARS.index(ch) if ch in FONT_CHARS else 0)
    return m


# ---------------------------------------------------------------- the sprite ball
def render_ball():
    """16 x 16, colours 1-3: a lit sphere. Returns the sprite's (DATA, DATB) words, row by row."""
    words = []
    pic = []
    for y in range(16):
        row = []
        for x in range(16):
            dx, dy = x - 7.5, y - 7.5
            r = math.hypot(dx, dy)
            if r > 7.6:
                row.append(0)
                continue
            light = math.hypot(dx + 3, dy + 3)          # the light comes from the top left
            row.append(3 if light < 3.5 else 2 if light < 7 else 1)
        pic.append(row)
        a = b = 0
        for x in range(16):
            if row[x] & 1:
                a |= 0x8000 >> x
            if row[x] & 2:
                b |= 0x8000 >> x
        words += [a, b]
    return words, pic


BALL_COLOURS = [0x046, 0x29C, 0xCFF]                 # sprite colours 1-3: rim, body, highlight


# ---------------------------------------------------------------- tables
def hue(h):
    """A hue 0..1 -> a bright $0RGB."""
    h = (h % 1.0) * 6
    i = int(h)
    f = h - i
    q, t = 1 - f, f
    r, g, b = [(1, t, 0), (q, 1, 0), (0, 1, t), (0, q, 1), (t, 0, 1), (1, 0, q)][i]
    return (round(r * 15) << 8) | (round(g * 15) << 4) | round(b * 15)


def sine_table():
    return [round(127 * math.sin(2 * math.pi * i / 256)) for i in range(256)]


def rainbow():
    one = [hue(i / 256) for i in range(256)]
    return one + one


def bar_gradients():
    """Three copper bars, 16 lines each: dark at the edges, bright in the middle."""
    bases = [(15, 4, 2), (3, 15, 6), (5, 7, 15)]          # red, green, blue bars
    out = []
    for (r, g, b) in bases:
        for i in range(16):
            k = math.sin(math.pi * (i + 0.5) / 16)
            out.append((round(r * k) << 8) | (round(g * k) << 4) | round(b * k))
    return out


def shimmer():
    """The logo's highlight colour, line by line: a slow sweep through gold and white."""
    out = []
    for i in range(256):
        k = 0.5 + 0.5 * math.sin(2 * math.pi * i / 64)
        r = 15
        g = round(9 + 6 * k)
        b = round(2 + 13 * k * k)
        out.append((r << 8) | (g << 4) | b)
    return out


def note_freq(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def periods():
    """Paula's period for MIDI notes 0..127, for a 32-byte wave; 0 where it is out of Paula's range."""
    out = []
    for n in range(128):
        p = round(PAL_CLOCK / (note_freq(n) * 32))
        out.append(p if 60 <= p <= 65535 else 0)
    return out


# ---------------------------------------------------------------- Paula's samples
def s8(v):
    return max(-128, min(127, int(round(v))))


def waves():
    rnd = random.Random(1987)
    square16 = [s8(90 if i < 8 else -90) for i in range(16)]
    pulse32 = [s8(70 if i < 8 else -70) for i in range(32)]
    saw64 = [s8(110 - i * 220 / 63) for i in range(64)]
    kick = []
    phase = 0.0
    for i in range(1536):
        t = i / 1536
        f = 0.055 - 0.047 * min(1, t * 3)                # a falling pitch
        phase += 2 * math.pi * f
        kick.append(s8(120 * math.sin(phase) * (1 - t) ** 1.5))
    snare = []
    for i in range(1536):
        t = i / 1536
        tone = math.sin(2 * math.pi * i * 0.035) * 50 * (1 - t) ** 3
        snare.append(s8((rnd.uniform(-1, 1) * 100 * (1 - t) ** 2) + tone))
    hat = [s8(rnd.uniform(-1, 1) * 80 * (1 - i / 512) ** 2) for i in range(512)]
    silence = [0, 0, 0, 0]
    return dict(WaveSquare=square16, WavePulse=pulse32, WaveSaw=saw64,
                WaveKick=kick, WaveSnare=snare, WaveHat=hat, WaveSilence=silence)


# ---------------------------------------------------------------- the tune
NOTE = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def n(name):
    """'A3', 'C#4' -> MIDI."""
    s = 1 if '#' in name else 0
    return 12 * (int(name[-1]) + 1) + NOTE[name[0]] + s


def song():
    """Rows of (bass, lead, chord, drum). 0 = nothing new, 1 = note off; drum 2 kick, 3 snare, 4 hat.

    A minor, Am F C G, four bars of sixteen rows each, played twice: first bass, chords and drums,
    then the lead on top."""
    chords = [('A2', ['A3', 'C4', 'E4']), ('F2', ['F3', 'A3', 'C4']),
              ('C3', ['C4', 'E4', 'G4']), ('G2', ['G3', 'B3', 'D4'])]
    lead_bars = [
        ['A4', 0, 0, 'C5', 0, 'E5', 0, 0, 'D5', 0, 'C5', 0, 'B4', 0, 0, 0],
        ['A4', 0, 0, 0, 'F4', 0, 'A4', 0, 'C5', 0, 0, 'D5', 'C5', 0, 0, 0],
        ['E5', 0, 0, 'G5', 0, 'E5', 0, 'C5', 'D5', 0, 'E5', 0, 'G5', 0, 0, 0],
        ['D5', 0, 'B4', 0, 'G4', 0, 0, 0, 'A4', 0, 'B4', 0, 'D5', 0, 1, 0],
    ]
    drum = [2, 0, 4, 0, 3, 0, 4, 0, 2, 0, 2, 4, 3, 0, 4, 4]
    rows = []
    for verse in range(2):
        for bar, (root, triad) in enumerate(chords):
            for r in range(16):
                bass = n(root) if r in (0, 6, 8, 14) else (n(root) + 12 if r in (4, 12) else 0)
                chord = n(triad[r % 3]) if r % 2 == 0 else 0
                lead = 0
                if verse == 1:
                    v = lead_bars[bar][r]
                    lead = v if isinstance(v, int) else n(v)
                rows.append((bass, lead, chord, drum[r] if (verse or r % 4 == 0 or drum[r] == 3) else 0))
    return rows


SCROLL_TEXT = ('    PUREMETAL ON THE AMIGA ... A 68000 PROGRAM WRITTEN IN PUREMETAL AND COMPILED BY '
               'PUREMETAL FORGE: COPPER BARS, A BITPLANE LOGO, EIGHT HARDWARE SPRITES, A BLITTER '
               'SINE SCROLLER AND FOUR CHANNELS OF PAULA ... NO ASSEMBLY, NO OPERATING SYSTEM, '
               'JUST THE MACHINE ... GREETINGS TO EVERY 68000 STILL RUNNING!      ')


# ---------------------------------------------------------------- output
def data_lines(label, values, kind, per=16):
    out = [label + ':']
    for i in range(0, len(values), per):
        chunk = values[i:i + per]
        if kind == 'w':
            # signed: a .w holds -32768..32767, and a word's bits are what the chips read
            out.append('  Data.w ' + ', '.join(str(((v & 0xFFFF) ^ 0x8000) - 0x8000) for v in chunk))
        else:
            out.append('  Data.b ' + ', '.join(str(v) for v in chunk))
    return out


def generate(write_previews):
    logo = render_logo()
    lp = planes(logo, 3)
    glyphs = render_font()
    ball, ballpic = render_ball()
    rows = song()
    w = waves()
    out = ['; GENERATED by demo/make_demo_assets.py - do not edit; run the tool instead.',
           '; The PureMetal Amiga demo\'s graphics, tables and music (see the tool\'s header).',
           '',
           '#LOGO_W = 320', '#LOGO_H = 64', '#LOGO_PLANE_BYTES = %d' % (320 // 8 * 64),
           '#FONT_GLYPHS = %d' % len(glyphs), '#SONG_ROWS = %d' % len(rows),
           '#WAVE_KICK_WORDS = %d' % (len(w['WaveKick']) // 2),
           '#WAVE_SNARE_WORDS = %d' % (len(w['WaveSnare']) // 2),
           '#WAVE_HAT_WORDS = %d' % (len(w['WaveHat']) // 2),
           '',
           'DataSection']
    out += data_lines('LogoPlanes', lp[0] + lp[1] + lp[2], 'w')
    out += data_lines('LogoPalette', LOGO_PALETTE, 'w')
    out += data_lines('Font', [v for g in glyphs for v in g], 'w')
    out += data_lines('FontMap', font_map(), 'b')
    out += data_lines('Ball', ball, 'w')
    out += data_lines('BallColours', BALL_COLOURS, 'w')
    out += data_lines('Sine', sine_table(), 'b')
    out += data_lines('Rainbow', rainbow(), 'w')
    out += data_lines('BarGrad', bar_gradients(), 'w')
    out += data_lines('Shimmer', shimmer(), 'w')
    out += data_lines('Periods', periods(), 'w')
    for k in ('WaveSquare', 'WavePulse', 'WaveSaw', 'WaveKick', 'WaveSnare', 'WaveHat', 'WaveSilence'):
        out += data_lines(k, w[k], 'b')
    out += data_lines('Song', [v for r in rows for v in r], 'b')
    out += data_lines('ScrollText', [ord(c) for c in SCROLL_TEXT] + [0], 'b')
    out.append('EndDataSection')
    text = '\n'.join(out) + '\n'
    if write_previews:
        PREVIEW.mkdir(exist_ok=True)
        pal = [((c >> 8) * 17, ((c >> 4) & 15) * 17, (c & 15) * 17) for c in LOGO_PALETTE]
        img = Image.new('RGB', (320, 64))
        for y in range(64):
            for x in range(320):
                img.putpixel((x, y), pal[logo[y][x]])
        img.resize((640, 128), Image.NEAREST).save(PREVIEW / 'logo.png')
        f = Image.new('L', (16 * 16, 16 * ((len(glyphs) + 15) // 16)), 0)
        for i, g in enumerate(glyphs):
            for y in range(16):
                for x in range(16):
                    if g[y] & (0x8000 >> x):
                        f.putpixel(((i % 16) * 16 + x, (i // 16) * 16 + y), 255)
        f.resize((f.width * 3, f.height * 3), Image.NEAREST).save(PREVIEW / 'font.png')
    return text


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--check', action='store_true')
    a = ap.parse_args()
    text = generate(not a.check)
    if a.check:
        cur = OUT.read_text(encoding='utf-8') if OUT.exists() else ''
        if cur != text:
            print('demo_assets.amiga is NOT what make_demo_assets.py writes - run it')
            return 1
        print('demo_assets.amiga is current')
        return 0
    OUT.write_text(text, encoding='utf-8')
    print('wrote', OUT, '(%d lines)' % text.count('\n'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
