"""A small 68000 assembler (Motorola syntax, the common subset), for the test
ROMs and programs of this project.

    py -3 tools/asm68k.py <source.s> <output.bin> [--listing out.lst]

Supported: labels (name: or a name at the start of a line), local labels
(.name, scoped to the last global label), NAME = expr / NAME EQU expr, ORG,
DC.B/W/L (numbers, labels, "strings"), DS.B/W/L, EVEN, CNOP 0,4, INCBIN.
Instructions: MOVE MOVEA MOVEQ LEA PEA CLR TST ADD ADDA ADDQ ADDI SUB SUBA SUBQ
SUBI CMP CMPA CMPI AND ANDI OR ORI EOR EORI NOT NEG NEGX EXT SWAP EXG MULU MULS
DIVU DIVS LSL LSR ASL ASR ROL ROR ROXL ROXR BTST BSET BCLR BCHG Bcc BRA BSR DBcc
DBRA JMP JSR RTS RTE RTR NOP STOP TRAP ILLEGAL MOVEM, MOVE to/from SR / CCR,
MOVE USP, ANDI/ORI/EORI to SR / CCR, TAS, Scc, LINK, UNLK, CHK.
Addressing: Dn An SP (An) (An)+ -(An) d(An) (d,An) d(An,Xn.s) abs.w abs(.l)
d(PC) label(PC) d(PC,Xn) #imm. Expressions: + - * / << >> & | ~ ( ), $hex,
%binary, 'c', decimal, labels, * (the current address).
The output is the raw big-endian bytes from the first ORG.
"""
import re, sys, struct

class AsmError(Exception):
    pass

COND = {'T': 0, 'RA': 0, 'F': 1, 'HI': 2, 'LS': 3, 'CC': 4, 'HS': 4, 'CS': 5, 'LO': 5, 'NE': 6, 'EQ': 7,
        'VC': 8, 'VS': 9, 'PL': 10, 'MI': 11, 'GE': 12, 'LT': 13, 'GT': 14, 'LE': 15}
SIZE = {'B': 0, 'W': 1, 'L': 2}

def reg_num(s):
    s = s.upper()
    if s == 'SP':
        return 15
    m = re.fullmatch(r'([DA])([0-7])', s)
    if not m:
        return None
    return int(m.group(2)) + (8 if m.group(1) == 'A' else 0)

class Asm:
    def __init__(self):
        self.syms = {}
        self.out = bytearray()
        self.org = None
        self.pc = 0
        self.pass2 = False
        self.last_global = ''
        self.listing = []

    # ---------------------------------------------------------- expressions
    def value(self, text):
        t = text.strip()
        def sym(m):
            name = m.group(0)
            if name.startswith('.'):
                name = self.last_global + name
            if name.upper() in ('D0', 'D1'):
                raise AsmError('a register in an expression: ' + text)
            if name in self.syms:
                return str(self.syms[name])
            if self.pass2:
                raise AsmError('undefined symbol ' + name)
            return '0'
        t = re.sub(r"'(.)'", lambda m: str(ord(m.group(1))), t)
        t = re.sub(r'\$([0-9A-Fa-f]+)', lambda m: str(int(m.group(1), 16)), t)
        t = re.sub(r'%([01]+)', lambda m: str(int(m.group(1), 2)), t)
        t = re.sub(r'(?<![\w.])\*(?![\w(])', str(self.pc), t)
        t = re.sub(r'\.?[A-Za-z_][\w.]*', sym, t)
        t = t.replace('/', '//')
        if not re.fullmatch(r'[\d\s+\-*/<>&|~()^]*', t):
            raise AsmError('bad expression: ' + text)
        try:
            return int(eval(t, {'__builtins__': {}}, {}))
        except Exception:
            raise AsmError('bad expression: ' + text)

    # ---------------------------------------------------------- operands
    def ea(self, op, size):
        """-> (mode, reg, extension words list, kind)"""
        o = op.strip()
        u = o.upper()
        r = reg_num(o)
        if r is not None:
            return (0, r, [], 'dn') if r < 8 else (1, r - 8, [], 'an')
        if o.startswith('#'):
            v = self.value(o[1:])
            if size == 2:
                return (7, 4, [(v >> 16) & 0xFFFF, v & 0xFFFF], 'imm')
            return (7, 4, [v & (0xFF if size == 0 else 0xFFFF)], 'imm')
        m = re.fullmatch(r'\(\s*(A[0-7]|SP)\s*\)', u)
        if m:
            return (2, reg_num(m.group(1)) - 8, [], 'mem')
        m = re.fullmatch(r'\(\s*(A[0-7]|SP)\s*\)\+', u)
        if m:
            return (3, reg_num(m.group(1)) - 8, [], 'mem')
        m = re.fullmatch(r'-\(\s*(A[0-7]|SP)\s*\)', u)
        if m:
            return (4, reg_num(m.group(1)) - 8, [], 'mem')
        # d(An,Xn[.s]) / (d,An,Xn) / d(PC,Xn)
        m = re.fullmatch(r'(.*)\(\s*(A[0-7]|SP|PC)\s*,\s*([DA][0-7]|SP)(\.[WL])?\s*\)', o, re.I)
        if not m:
            m2 = re.fullmatch(r'\(\s*([^,]+?)\s*,\s*(A[0-7]|SP|PC)\s*,\s*([DA][0-7]|SP)(\.[WL])?\s*\)', o, re.I)
            if m2:
                m = m2
        if m:
            d = self.value(m.group(1)) if m.group(1).strip() else 0
            base = m.group(2).upper()
            xr = reg_num(m.group(3))
            long_ = (m.group(4) or '.W').upper() == '.L'
            if base == 'PC':
                d = d - (self.pc + 2 + self.ext_offset)
                if self.pass2 and not -128 <= d < 128:
                    raise AsmError('PC index displacement out of range: ' + op)
                return (7, 3, [(xr << 12) | (0x800 if long_ else 0) | (d & 0xFF)], 'pcx')
            if self.pass2 and not -128 <= d < 128:
                raise AsmError('index displacement out of range: ' + op)
            return (6, reg_num(base) - 8, [(xr << 12) | (0x800 if long_ else 0) | (d & 0xFF)], 'mem')
        m = re.fullmatch(r'(.*)\(\s*(A[0-7]|SP|PC)\s*\)', o, re.I)
        if not m:
            m2 = re.fullmatch(r'\(\s*([^,]+?)\s*,\s*(A[0-7]|SP|PC)\s*\)', o, re.I)
            if m2:
                m = m2
        if m and m.group(1).strip() != '':
            d = self.value(m.group(1))
            base = m.group(2).upper()
            if base == 'PC':
                d = d - (self.pc + 2 + self.ext_offset)
                if self.pass2 and not -32768 <= d < 32768:
                    raise AsmError('PC displacement out of range: ' + op)
                return (7, 2, [d & 0xFFFF], 'pcd')
            if self.pass2 and not -32768 <= d < 32768:
                raise AsmError('displacement out of range: ' + op)
            return (5, reg_num(base) - 8, [d & 0xFFFF], 'mem')
        m = re.fullmatch(r'(.*)\.W', o, re.I)
        if m:
            v = self.value(m.group(1))
            return (7, 0, [v & 0xFFFF], 'mem')
        m = re.fullmatch(r'(.*)\.L', o, re.I)
        t = m.group(1) if m else o
        v = self.value(t)
        return (7, 1, [(v >> 16) & 0xFFFF, v & 0xFFFF], 'mem')

    # ---------------------------------------------------------- output
    def emit_words(self, words):
        for w in words:
            self.out += struct.pack('>H', w & 0xFFFF)
        self.pc += 2 * len(words)

    def emit_bytes(self, bs):
        self.out += bytes(bs)
        self.pc += len(bs)

    # ---------------------------------------------------------- instructions
    def split_ops(self, s):
        ops, depth, cur, q = [], 0, '', False
        for ch in s:
            if ch == '"' or ch == "'":
                q = not q
            if not q:
                if ch == '(':
                    depth += 1
                elif ch == ')':
                    depth -= 1
                elif ch == ',' and depth == 0:
                    ops.append(cur.strip())
                    cur = ''
                    continue
            cur += ch
        if cur.strip():
            ops.append(cur.strip())
        return ops

    def reglist(self, s):
        mask = 0
        for part in s.split('/'):
            part = part.strip()
            if '-' in part:
                a, b = part.split('-')
                ra, rb = reg_num(a), reg_num(b)
                for r in range(ra, rb + 1):
                    mask |= 1 << r
            else:
                mask |= 1 << reg_num(part)
        return mask

    def instr(self, mn, ops):
        size_s = None
        if '.' in mn:
            mn, size_s = mn.split('.', 1)
            size_s = size_s.upper()
        mn = mn.upper()
        size = SIZE.get(size_s, 1) if size_s not in ('S',) else 1
        self.ext_offset = 0
        def eaw(e):
            return (e[0] << 3) | e[1]
        def two(op_hi, src, dst_reg):
            pass
        n = len(ops)
        if mn in ('NOP', 'RTS', 'RTE', 'RTR', 'ILLEGAL', 'RESET', 'TRAPV'):
            self.emit_words([{'NOP': 0x4E71, 'RTS': 0x4E75, 'RTE': 0x4E73, 'RTR': 0x4E77, 'ILLEGAL': 0x4AFC,
                              'RESET': 0x4E70, 'TRAPV': 0x4E76}[mn]])
            return
        if mn == 'STOP':
            self.emit_words([0x4E72, self.value(ops[0].lstrip('#'))])
            return
        if mn == 'TRAP':
            self.emit_words([0x4E40 | (self.value(ops[0].lstrip('#')) & 15)])
            return
        if mn == 'LINK':
            self.emit_words([0x4E50 | (reg_num(ops[0]) - 8), self.value(ops[1].lstrip('#')) & 0xFFFF])
            return
        if mn == 'UNLK':
            self.emit_words([0x4E58 | (reg_num(ops[0]) - 8)])
            return
        if mn == 'SWAP':
            self.emit_words([0x4840 | reg_num(ops[0])])
            return
        if mn == 'EXT':
            self.emit_words([(0x48C0 if size == 2 else 0x4880) | reg_num(ops[0])])
            return
        if mn == 'EXG':
            a, b = reg_num(ops[0]), reg_num(ops[1])
            if a < 8 and b < 8:
                w = 0xC140 | (a << 9) | b
            elif a >= 8 and b >= 8:
                w = 0xC148 | ((a - 8) << 9) | (b - 8)
            else:
                if a >= 8:
                    a, b = b, a
                w = 0xC188 | (a << 9) | (b - 8)
            self.emit_words([w])
            return
        if mn == 'MOVEQ':
            self.emit_words([0x7000 | (reg_num(ops[1]) << 9) | (self.value(ops[0].lstrip('#')) & 0xFF)])
            return
        if mn in ('BRA', 'BSR') or (mn.startswith('B') and mn[1:] in COND and mn not in ('BTST', 'BSET', 'BCLR', 'BCHG')):
            cc = 1 if mn == 'BSR' else COND[mn[1:]]
            target = self.value(ops[0])
            d = target - (self.pc + 2)
            if size_s == 'S' or size_s == 'B':
                if self.pass2 and (not -128 <= d < 128 or d == 0):
                    raise AsmError('short branch out of range')
                self.emit_words([0x6000 | (cc << 8) | (d & 0xFF)])
            else:
                self.emit_words([0x6000 | (cc << 8), d & 0xFFFF])
            return
        if mn.startswith('DB'):
            cc = 1 if mn == 'DBRA' else COND[mn[2:]]
            target = self.value(ops[1])
            self.emit_words([0x50C8 | (cc << 8) | reg_num(ops[0]), (target - (self.pc + 2)) & 0xFFFF])
            return
        if mn.startswith('S') and mn[1:] in COND and mn not in ('SUB', 'SWAP'):
            e = self.ea(ops[0], 0)
            self.emit_words([0x50C0 | (COND[mn[1:]] << 8) | eaw(e)] + e[2])
            return
        if mn in ('JMP', 'JSR', 'PEA'):
            e = self.ea(ops[0], 2)
            base = {'JMP': 0x4EC0, 'JSR': 0x4E80, 'PEA': 0x4840}[mn]
            self.emit_words([base | eaw(e)] + e[2])
            return
        if mn == 'LEA':
            e = self.ea(ops[0], 2)
            self.emit_words([0x41C0 | ((reg_num(ops[1]) - 8) << 9) | eaw(e)] + e[2])
            return
        if mn in ('CLR', 'TST', 'NOT', 'NEG', 'NEGX'):
            e = self.ea(ops[0], size)
            base = {'CLR': 0x4200, 'TST': 0x4A00, 'NOT': 0x4600, 'NEG': 0x4400, 'NEGX': 0x4000}[mn]
            self.emit_words([base | (size << 6) | eaw(e)] + e[2])
            return
        if mn == 'TAS':
            e = self.ea(ops[0], 0)
            self.emit_words([0x4AC0 | eaw(e)] + e[2])
            return
        if mn in ('MULU', 'MULS', 'DIVU', 'DIVS', 'CHK'):
            e = self.ea(ops[0], 1)
            base = {'MULU': 0xC0C0, 'MULS': 0xC1C0, 'DIVU': 0x80C0, 'DIVS': 0x81C0, 'CHK': 0x4180}[mn]
            self.emit_words([base | (reg_num(ops[1]) << 9) | eaw(e)] + e[2])
            return
        if mn in ('LSL', 'LSR', 'ASL', 'ASR', 'ROL', 'ROR', 'ROXL', 'ROXR'):
            typ = {'AS': 0, 'LS': 1, 'ROX': 2, 'RO': 3}[mn[:-1]]
            d = 1 if mn.endswith('L') else 0
            if n == 1:
                e = self.ea(ops[0], 1)
                self.emit_words([0xE0C0 | (typ << 9) | (d << 8) | eaw(e)] + e[2])
                return
            if ops[0].startswith('#'):
                c = self.value(ops[0][1:]) & 7
                self.emit_words([0xE000 | (c << 9) | (d << 8) | (size << 6) | (typ << 3) | reg_num(ops[1])])
            else:
                self.emit_words([0xE020 | (reg_num(ops[0]) << 9) | (d << 8) | (size << 6) | (typ << 3) | reg_num(ops[1])])
            return
        if mn in ('BTST', 'BSET', 'BCLR', 'BCHG'):
            t = {'BTST': 0, 'BCHG': 1, 'BCLR': 2, 'BSET': 3}[mn]
            if ops[0].startswith('#'):
                self.ext_offset = 2
                e = self.ea(ops[1], 0)
                self.emit_words([0x0800 | (t << 6) | eaw(e), self.value(ops[0][1:]) & 0xFF] + e[2])
            else:
                e = self.ea(ops[1], 0)
                self.emit_words([0x0100 | (reg_num(ops[0]) << 9) | (t << 6) | eaw(e)] + e[2])
            return
        if mn == 'MOVEM':
            if '/' in ops[0] or '-' in ops[0] and reg_num(ops[0].split('-')[0]) is not None or reg_num(ops[0]) is not None:
                mask = self.reglist(ops[0])
                self.ext_offset = 2
                e = self.ea(ops[1], size)
                if e[0] == 4:
                    mask = int('{:016b}'.format(mask)[::-1], 2)
                self.emit_words([0x4880 | ((1 if size == 2 else 0) << 6) | eaw(e), mask] + e[2])
            else:
                mask = self.reglist(ops[1])
                self.ext_offset = 2
                e = self.ea(ops[0], size)
                self.emit_words([0x4C80 | ((1 if size == 2 else 0) << 6) | eaw(e), mask] + e[2])
            return
        if mn in ('ANDI', 'ORI', 'EORI') and ops[1].upper() in ('SR', 'CCR'):
            base = {'ORI': 0x0000, 'ANDI': 0x0200, 'EORI': 0x0A00}[mn]
            if ops[1].upper() == 'SR':
                self.emit_words([base | 0x7C, self.value(ops[0][1:]) & 0xFFFF])
            else:
                self.emit_words([base | 0x3C, self.value(ops[0][1:]) & 0xFF])
            return
        if mn in ('ADDI', 'SUBI', 'CMPI', 'ANDI', 'ORI', 'EORI') or (
                mn in ('ADD', 'SUB', 'CMP', 'AND', 'OR', 'EOR') and ops[0].startswith('#') and reg_num(ops[1]) is None or
                mn in ('AND', 'OR', 'EOR') and ops[0].startswith('#')):
            base = {'ORI': 0x0000, 'ANDI': 0x0200, 'SUBI': 0x0400, 'ADDI': 0x0600, 'EORI': 0x0A00, 'CMPI': 0x0C00,
                    'OR': 0x0000, 'AND': 0x0200, 'SUB': 0x0400, 'ADD': 0x0600, 'EOR': 0x0A00, 'CMP': 0x0C00}[mn]
            v = self.value(ops[0][1:])
            imm = [(v >> 16) & 0xFFFF, v & 0xFFFF] if size == 2 else [v & (0xFF if size == 0 else 0xFFFF)]
            self.ext_offset = 2 * len(imm)
            e = self.ea(ops[1], size)
            self.emit_words([base | (size << 6) | eaw(e)] + imm + e[2])
            return
        if mn in ('ADDQ', 'SUBQ'):
            v = self.value(ops[0][1:]) & 7
            e = self.ea(ops[1], size)
            self.emit_words([(0x5000 if mn == 'ADDQ' else 0x5100) | (v << 9) | (size << 6) | eaw(e)] + e[2])
            return
        if mn in ('ADDA', 'SUBA', 'CMPA') or (mn in ('ADD', 'SUB', 'CMP') and reg_num(ops[1]) is not None and reg_num(ops[1]) >= 8):
            e = self.ea(ops[0], size)
            base = {'ADDA': 0xD0C0, 'ADD': 0xD0C0, 'SUBA': 0x90C0, 'SUB': 0x90C0, 'CMPA': 0xB0C0, 'CMP': 0xB0C0}[mn]
            self.emit_words([base | ((reg_num(ops[1]) - 8) << 9) | ((1 if size == 2 else 0) << 8) | eaw(e)] + e[2])
            return
        if mn in ('ADD', 'SUB', 'CMP', 'AND', 'OR', 'EOR'):
            line = {'OR': 0x8000, 'SUB': 0x9000, 'CMP': 0xB000, 'EOR': 0xB000, 'AND': 0xC000, 'ADD': 0xD000}[mn]
            if reg_num(ops[1]) is not None and reg_num(ops[1]) < 8 and mn != 'EOR':
                e = self.ea(ops[0], size)
                self.emit_words([line | (reg_num(ops[1]) << 9) | (size << 6) | eaw(e)] + e[2])
            else:
                e = self.ea(ops[1], size)
                self.emit_words([line | (reg_num(ops[0]) << 9) | ((4 + size) << 6) | eaw(e)] + e[2])
            return
        if mn in ('MOVE', 'MOVEA'):
            if ops[0].upper() == 'SR':
                e = self.ea(ops[1], 1)
                self.emit_words([0x40C0 | eaw(e)] + e[2])
                return
            if ops[1].upper() in ('SR', 'CCR'):
                e = self.ea(ops[0], 1)
                self.emit_words([(0x46C0 if ops[1].upper() == 'SR' else 0x44C0) | eaw(e)] + e[2])
                return
            if ops[0].upper() == 'USP':
                self.emit_words([0x4E68 | (reg_num(ops[1]) - 8)])
                return
            if ops[1].upper() == 'USP':
                self.emit_words([0x4E60 | (reg_num(ops[0]) - 8)])
                return
            s = self.ea(ops[0], size)
            self.ext_offset = 2 * len(s[2])
            d = self.ea(ops[1], size)
            code = {0: 0x1000, 1: 0x3000, 2: 0x2000}[size]
            self.emit_words([code | (d[1] << 9) | (d[0] << 6) | eaw(s)] + s[2] + d[2])
            return
        raise AsmError('unknown instruction ' + mn)

    # ---------------------------------------------------------- lines
    def line(self, raw):
        text = raw.split(';')[0].rstrip()
        if re.match(r'^\s*\*', text):
            return
        if not text.strip():
            return
        m = re.match(r'^([.A-Za-z_][\w.]*)\s*(=|\bEQU\b)\s*(.+)$', text.strip(), re.I)
        if m:
            name = m.group(1)
            if name.startswith('.'):
                name = self.last_global + name
            self.syms[name] = self.value(m.group(3))
            return
        label = None
        m = re.match(r'^([.A-Za-z_][\w.]*):?(\s+|$)', text)
        if m and not text[0].isspace():
            label = m.group(1)
            text = text[m.end():]
        elif re.match(r'^\s*([.A-Za-z_][\w.]*):', text):
            m = re.match(r'^\s*([.A-Za-z_][\w.]*):', text)
            label = m.group(1)
            text = text[m.end():]
        if label:
            if label.startswith('.'):
                label = self.last_global + label
            else:
                self.last_global = label
            if not self.pass2 and label in self.syms:
                raise AsmError('label defined twice: ' + label)
            self.syms[label] = self.pc
        text = text.strip()
        if not text:
            return
        parts = text.split(None, 1)
        mn = parts[0]
        ops = self.split_ops(parts[1]) if len(parts) > 1 else []
        u = mn.upper()
        start = self.pc
        if u == 'ORG':
            v = self.value(ops[0])
            if self.org is None:
                self.org = v
            else:
                if v < self.pc:
                    raise AsmError('ORG backwards')
                self.emit_bytes([0] * (v - self.pc))
            self.pc = v
            return
        if u.startswith('DC.'):
            sz = SIZE[u[3]]
            for o in ops:
                if o.startswith('"'):
                    self.emit_bytes(o.strip('"').encode('latin-1'))
                    continue
                v = self.value(o)
                if sz == 0:
                    self.emit_bytes([v & 0xFF])
                elif sz == 1:
                    self.emit_words([v])
                else:
                    self.emit_words([v >> 16, v])
            return
        if u.startswith('DS.'):
            n = self.value(ops[0]) * {0: 1, 1: 2, 2: 4}[SIZE[u[3]]]
            self.emit_bytes([0] * n)
            return
        if u == 'EVEN':
            if self.pc & 1:
                self.emit_bytes([0])
            return
        if u == 'CNOP':
            al = self.value(ops[1])
            while self.pc % al:
                self.emit_bytes([0])
            return
        if u == 'INCBIN':
            data = open(ops[0].strip('"'), 'rb').read()
            self.emit_bytes(data)
            return
        if self.pc & 1:
            raise AsmError('an instruction at an odd address')
        self.instr(mn, ops)
        if self.pass2:
            self.listing.append('%06X  %-28s %s' % (start, self.out[len(self.out) - (self.pc - start):].hex(), raw.rstrip()))

    def run(self, lines):
        for p in (1, 2):
            self.pass2 = p == 2
            self.out = bytearray()
            self.pc = 0
            self.org = None
            self.last_global = ''
            self.listing = []
            for n, l in enumerate(lines, 1):
                try:
                    self.line(l)
                except AsmError as ex:
                    raise AsmError(f'line {n}: {ex}\n    {l.rstrip()}')
        return bytes(self.out)

def main():
    src, dst = sys.argv[1], sys.argv[2]
    a = Asm()
    try:
        data = a.run(open(src, encoding='latin-1').read().splitlines())
    except AsmError as ex:
        print('asm68k:', ex)
        sys.exit(1)
    open(dst, 'wb').write(data)
    if '--listing' in sys.argv:
        open(sys.argv[sys.argv.index('--listing') + 1], 'w').write('\n'.join(a.listing) + '\n')
    print(f'{dst}: {len(data)} bytes from ${a.org or 0:06X}')

if __name__ == '__main__':
    main()
