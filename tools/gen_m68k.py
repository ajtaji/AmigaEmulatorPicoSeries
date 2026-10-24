"""Generate the Motorola 68000 interpreter core.

Writes three files from one description:
  src/m68k.pico           PureMetal, Raspberry Pi Pico (RP2040)
  src/m68k.pico2          PureMetal, Raspberry Pi Pico 2 (RP2350)
  desktop/m68k_core.pbi   PureBasic (C back end, x64), for the desktop program

Edit this generator, never the generated files. Run:  py -3 tools/gen_m68k.py

Design (README.md has the full story):
  * Two-level decode. The first level is a 1024-entry label table indexed by
    opcode >> 6 (line, register field, opmode / size). Every handler ends in its
    own computed jump to the next instruction's handler. The low six bits of the
    opcode (the effective-address field) are decoded by small label tables
    (Src*, Alt*, Ctl) that compute the operand or its address and come back
    through a label variable (EaRet).
  * The program counter is a HOST pointer, PIP, into a fetch window: one 4 KB
    page of RAM or ROM, cut short so that any instruction starting below PEnd
    has all of its (at most ten) bytes inside the page. PIP stays on the opcode
    for the whole instruction; extension words are read at PIP + xo. The guest
    PC is PIP - PBase (32 bits; the bus sees the low 24).
  * Guest memory is 4096 pages of 4 KB (the 24-bit bus). Each page of RAM/ROM
    holds the guest's 16-bit words in HOST byte order, so a word is one PeekU
    and a byte is PeekA(host + (address XOR 1)). PageR/PageW hold the host
    address minus the page's guest base; 0 sends the access to the slow
    procedures, which call the machine's hooks and raise address errors.
  * Flags are kept apart and shifted to the host integer's sign bit: FN (N =
    sign), FZ (Z = FZ is 0), FV, FC, FX (sign = flag). The packed SR is built
    only on demand.
  * CLeft counts down 68000 clock cycles; M68kRun(n) runs at least n cycles.
"""
from pathlib import Path
import os, sys

ROOT = Path(__file__).resolve().parents[1]

IW = 32          # host integer width: 32 on the Picos, 64 on the PC
DESKTOP = False
TARGET = 'rp2040'

OUT = []
def e(s=''):
    OUT.append(s)

SIZES = ('B', 'W', 'L')
BITS = {'B': 8, 'W': 16, 'L': 32}
INC = {'B': 1, 'W': 2, 'L': 4}

def SH(s):
    """Shift that moves the size's most significant bit to the host sign bit."""
    return IW - BITS[s]

def shl(v, s):
    n = SH(s)
    return v if n == 0 else f'(({v}) << {n})'

def TOP():
    return '$80000000' if IW == 32 else '$8000000000000000'

def M24():
    return '$FFFFFF'

def L32(v):
    """A 32-bit result as the host keeps it: on the PC, masked to 32 bits."""
    return v if IW == 32 else f'(({v}) & $FFFFFFFF)'

# Every helper returns ONE parenthesised operand: PureMetal ranks shifts below
# + - and & | ! with * / (C-like, by ruling), PureBasic the other way round, so
# a bare shift inside a sum is a different program on the Pico than on the PC
# (tools/prec_check.py finds them).
#
# A shift sign-extends only a SIGNED operand on PureMetal: PeekU / PeekA are
# unsigned there, so `(PeekU(a) << 16) >> 16` zero-fills (Help/_langref '>>').
# A whole unsigned peek becomes the signed peek of the same width instead.
def _whole_call(v, name):
    if not v.startswith(name + '('):
        return False
    depth = 0
    for i in range(len(name), len(v)):
        depth += (v[i] == '(') - (v[i] == ')')
        if depth == 0:
            return i == len(v) - 1
    return False

def SX16(v):
    if _whole_call(v, 'PeekU'):
        return 'PeekW' + v[5:]
    return f'((({v}) << {IW - 16}) >> {IW - 16})'

def SX8(v):
    if _whole_call(v, 'PeekA'):
        return 'PeekB' + v[5:]
    return f'((({v}) << {IW - 8}) >> {IW - 8})'

def SX32(v):
    return v if IW == 32 else f'((({v}) << 32) >> 32)'

def SXS(v, s):
    if s == 'B':
        return SX8(v)
    if s == 'W':
        return SX16(v)
    return SX32(v)

def MASK(s):
    return {'B': '$FF', 'W': '$FFFF', 'L': '$FFFFFFFF'}[s]

# ---------------------------------------------------------------- labels and jumps
_lab_n = [0]
def newlab(p='L'):
    _lab_n[0] += 1
    return f'{p}{_lab_n[0]}'

def lab(name):
    """The C name the PureBasic C back end gives a label of M68kRun."""
    return 'll_m68krun_' + name.lower()

def label(name):
    e(f'{name}:')

def goto(name):
    e(f'  Goto {name}')

TABLES = {}   # name -> list of label names (64 entries), sub-tables of M68kRun

def table_goto(table, idx_pm, idx_c):
    if DESKTOP:
        e(f'  ! goto *m68k_{table.lower()}[{idx_c}];')
    else:
        e(f'  Goto {table}({idx_pm})')

def ea_call(table, ret, idx_pm='op & 63', idx_c='v_op & 63'):
    """Run table entry idx, which comes back to label ret."""
    if DESKTOP:
        e(f'  ! m68k_earet = &&{lab(ret)};')
    else:
        e(f'  EaRet = ?{ret}')
    table_goto(table, idx_pm, idx_c)

def ea_return():
    if DESKTOP:
        e('  ! goto *m68k_earet;')
    else:
        e('  Goto EaRet')

def PROC():
    return 'Procedure' if DESKTOP else 'ProcedureRAM'

# ---------------------------------------------------------------- registers
def dreg(i, s):
    """Read data register i (an expression 0..7) at size s, zero-extended."""
    if s == 'B':
        return f'PeekA(@Reg(0) + (({i}) << 2))'
    if s == 'W':
        return f'PeekU(@Reg(0) + (({i}) << 2))'
    return f'Reg({i})'

def dreg_c(n, s):
    if s == 'B':
        return f'PeekA(@Reg(0) + {n * 4})'
    if s == 'W':
        return f'PeekU(@Reg(0) + {n * 4})'
    return f'Reg({n})'

def set_dreg(i, s, v):
    if s == 'B':
        e(f'  PokeA(@Reg(0) + (({i}) << 2), {v})')
    elif s == 'W':
        e(f'  PokeU(@Reg(0) + (({i}) << 2), {v})')
    else:
        e(f'  Reg({i}) = {v}')

def OPR():
    """Register field 0..7 of bits 2..0 of the opcode."""
    return 'op & 7'

def OPR9():
    return '(op >> 9) & 7'

# ---------------------------------------------------------------- cycles
def charge(c):
    if isinstance(c, int):
        if c:
            e(f'  CLeft = CLeft - {c}')
    else:
        e(f'  CLeft = CLeft - ({c})')

def tail():
    """Advance past the instruction (xo bytes) and dispatch the next one."""
    e('  PIP = PIP + xo')
    next_op()

HIST = False      # --hist: the desktop core counts every opcode it runs (M68kHist), for profiling

def next_op():
    if DESKTOP:
        e('  If CLeft <= 0')
        e('    Goto Done')
        e('  EndIf')
        e('  If PIP >= PEnd')
        e('    Goto Resync')
        e('  EndIf')
        if HIST:
            # after the checks: a jump leaves PIP anywhere until Resync places it
            e('  M68kHist(PeekU(PIP)) + 1')
        e('  ! goto *m68k_dsp[*(unsigned short*)g_pip >> 6];')
    else:
        e('  NextOp()')

def dispatch_now():
    if DESKTOP:
        e('  ! goto *m68k_dsp[*(unsigned short*)g_pip >> 6];')
    else:
        e('  Goto Dispatch(PeekU(PIP) >> 6)')

# ---------------------------------------------------------------- flags
def nz(s, v):
    e(f'  FZ = {shl(v, s)}')
    e('  FN = FZ')

def clr_vc():
    e('  FV = 0')
    e('  FC = 0')

def flags_logic(s, v):
    nz(s, v)
    clr_vc()

def flags_add(s, a='vs', b='vd', r='vr', x=True, zsticky=False):
    """r = b + a (+X): N Z V C (and X)."""
    n = SH(s)
    sh = (lambda t: t) if n == 0 else (lambda t: f'({t}) << {n}')
    if zsticky:
        e(f'  FZ = FZ | ({shl(r, s)})')
        e(f'  FN = {shl(r, s)}')
    else:
        nz(s, r)
    e(f'  FV = {sh(f"({a} ! {r}) & ({b} ! {r})")}')
    e(f'  FC = {sh(f"({a} & {b}) | (({a} | {b}) & ~{r})")}')
    if x:
        e('  FX = FC')

def flags_sub(s, a='vs', b='vd', r='vr', x=True, zsticky=False):
    """r = b - a (-X): N Z V C (and X)."""
    n = SH(s)
    sh = (lambda t: t) if n == 0 else (lambda t: f'({t}) << {n}')
    if zsticky:
        e(f'  FZ = FZ | ({shl(r, s)})')
        e(f'  FN = {shl(r, s)}')
    else:
        nz(s, r)
    e(f'  FV = {sh(f"({a} ! {b}) & ({r} ! {b})")}')
    e(f'  FC = {sh(f"({a} & ~{b}) | ({r} & ~{b}) | ({a} & {r})")}')
    if x:
        e('  FX = FC')

def XBIT():
    """X as 0/1."""
    return f'((FX >> {IW - 1}) & 1)'

COND = {
    0: None,                    # T
    1: None,                    # F
    2: 'FC >= 0 And FZ <> 0',   # HI
    3: 'FC < 0 Or FZ = 0',      # LS
    4: 'FC >= 0',               # CC
    5: 'FC < 0',                # CS
    6: 'FZ <> 0',               # NE
    7: 'FZ = 0',                # EQ
    8: 'FV >= 0',               # VC
    9: 'FV < 0',                # VS
    10: 'FN >= 0',              # PL
    11: 'FN < 0',               # MI
    12: '(FN ! FV) >= 0',       # GE
    13: '(FN ! FV) < 0',        # LT
    14: '(FN ! FV) >= 0 And FZ <> 0',   # GT
    15: '(FN ! FV) < 0 Or FZ = 0',      # LE
}
CCNAME = ['T', 'F', 'HI', 'LS', 'CC', 'CS', 'NE', 'EQ', 'VC', 'VS', 'PL', 'MI', 'GE', 'LT', 'GT', 'LE']

# ---------------------------------------------------------------- memory
# Locals of M68kRun used here: t (host page), u (host address).
def rd(s, dst, a='ea'):
    """dst = the size-s value at guest address a (a full 32-bit value)."""
    e(f'  t = PageR(({a} >> 12) & $FFF)')
    if s == 'B':
        e('  If t <> 0')
        e(f'    {dst} = PeekA(t + (({a} & {M24()}) ! 1))')
        e('  Else')
        e(f'    {dst} = M68kRd8({a})')
        e('  EndIf')
        return
    if s == 'W':
        e(f'  If t <> 0 And ({a} & 1) = 0')
        e(f'    {dst} = PeekU(t + ({a} & {M24()}))')
    else:
        e(f'  If t <> 0 And ({a} & 1) = 0 And ({a} & $FFE) <> $FFE')
        e(f'    u = t + ({a} & {M24()})')
        e(f'    {dst} = (PeekU(u) << 16) | PeekU(u + 2)')
    e('  Else')
    e(f'    AeAddr = {a}')
    e(f'    {dst} = M68kRd{BITS[s]}({a})')
    e('    If AErr <> 0')
    e('      Goto AddrErr')
    e('    EndIf')
    e('  EndIf')

def wr(s, v, a='ea', err='AddrErr'):
    e(f'  t = PageW(({a} >> 12) & $FFF)')
    if s == 'B':
        e('  If t <> 0')
        e(f'    PokeA(t + (({a} & {M24()}) ! 1), {v})')
        e('  Else')
        e(f'    M68kWr8({a}, {v})')
        e('  EndIf')
        return
    if s == 'W':
        e(f'  If t <> 0 And ({a} & 1) = 0')
        e(f'    PokeU(t + ({a} & {M24()}), {v})')
    else:
        e(f'  If t <> 0 And ({a} & 1) = 0 And ({a} & $FFE) <> $FFE')
        e(f'    u = t + ({a} & {M24()})')
        e(f'    PokeU(u, {v} >> 16)')
        e(f'    PokeU(u + 2, {v})')
    e('  Else')
    e(f'    AeAddr = {a}')
    e(f'    M68kWr{BITS[s]}({a}, {v})')
    e('    If AErr <> 0')
    e(f'      Goto {err}')
    e('    EndIf')
    e('  EndIf')

# Extension words. xo is the byte offset of the next one from the opcode.
def ext_w(dst, signed=True):
    if signed:
        e(f'  {dst} = PeekW(PIP + xo)')
    else:
        e(f'  {dst} = PeekU(PIP + xo)')
    e('  xo = xo + 2')

def ext_l(dst):
    e(f'  {dst} = (PeekU(PIP + xo) << 16) | PeekU(PIP + xo + 2)')
    e('  xo = xo + 4')

def guest_pc(off='xo'):
    """Guest address of PIP + off."""
    return f'(PIP - PBase + {off})'

def index_ea(base):
    """ea = base + index register + d8, from the brief extension word at PIP+xo."""
    e('  u = PeekU(PIP + xo)')
    e('  If u & $800')
    e('    t = Reg((u >> 12) & 15)')
    e('  Else')
    e('    t = PeekW(@Reg(0) + ((u >> 10) & $3C))')
    e('  EndIf')
    e(f'  ea = {base} + t + PeekB(PIP + xo)')
    e('  xo = xo + 2')

# ---------------------------------------------------------------- EA tables
# Cycle counts of the effective-address calculation including the operand
# access (68000 User's Manual, table 8-1), by mode 0..6 and mode 7 reg 0..4.
EA_BW = {0: 0, 1: 0, 2: 4, 3: 4, 4: 6, 5: 8, 6: 10, 70: 8, 71: 12, 72: 8, 73: 10, 74: 4}
EA_L = {0: 0, 1: 0, 2: 8, 3: 8, 4: 10, 5: 12, 6: 14, 70: 12, 71: 16, 72: 12, 73: 14, 74: 8}

def ea_key(idx):
    m, r = idx >> 3, idx & 7
    return m if m < 7 else 70 + r

def ea_cyc(idx, s):
    k = ea_key(idx)
    t = EA_L if s == 'L' else EA_BW
    return t.get(k)

def emit_ea_address(idx, s, charge_it=True):
    """ea := the address of memory mode idx; size s matters for (An)+/-(An)."""
    m, r = idx >> 3, idx & 7
    inc = INC[s] if s else 0
    if s == 'B' and r == 7:
        inc = 2
    if m == 2:
        e(f'  ea = Reg({8 + r})')
    elif m == 3:
        e(f'  ea = Reg({8 + r})')
        e(f'  Reg({8 + r}) = ea + {inc}')
    elif m == 4:
        e(f'  ea = Reg({8 + r}) - {inc}')
        e(f'  Reg({8 + r}) = ea')
    elif m == 5:
        e(f'  ea = Reg({8 + r}) + PeekW(PIP + xo)')
        e('  xo = xo + 2')
    elif m == 6:
        index_ea(f'Reg({8 + r})')
    elif idx == 0x38:
        ext_w('ea')
    elif idx == 0x39:
        ext_l('ea')
    elif idx == 0x3A:
        e(f'  ea = {guest_pc()} + PeekW(PIP + xo)')
        e('  xo = xo + 2')
    elif idx == 0x3B:
        index_ea(guest_pc())
    else:
        raise ValueError(idx)
    if charge_it and s:
        charge(ea_cyc(idx, s))

def emit_tables():
    """Src{B,W,L}: vs = operand.  Alt{B,W,L}: ea = alterable memory operand.
    Ctl: ea = control operand (no cycles charged)."""
    for s in SIZES:
        names = []
        for idx in range(64):
            m, r = idx >> 3, idx & 7
            name = f'Src{s}{idx:02X}'
            names.append(name)
            label(name)
            if m == 0:
                e(f'  vs = {dreg_c(r, s)}')
                ea_return()
            elif m == 1:
                if s == 'B':
                    goto('IllegalOp')
                else:
                    e(f'  vs = {dreg_c(8 + r, s)}')
                    ea_return()
            elif idx < 0x3C:
                emit_ea_address(idx, s)
                goto(f'Rd{s}')
            elif idx == 0x3C:
                if s == 'B':
                    e('  vs = PeekA(PIP + xo)')
                    e('  xo = xo + 2')
                elif s == 'W':
                    ext_w('vs', signed=False)
                else:
                    ext_l('vs')
                charge(ea_cyc(idx, s))
                ea_return()
            else:
                goto('IllegalOp')
        TABLES[f'Src{s}'] = names
        label(f'Rd{s}')
        rd(s, 'vs')
        ea_return()
    for s in SIZES:
        names = []
        for idx in range(64):
            m = idx >> 3
            name = f'Alt{s}{idx:02X}'
            names.append(name)
            label(name)
            if 2 <= m <= 6 or idx in (0x38, 0x39):
                emit_ea_address(idx, s)
                ea_return()
            else:
                goto('IllegalOp')
        TABLES[f'Alt{s}'] = names
    names = []
    for idx in range(64):
        m = idx >> 3
        name = f'Ctl{idx:02X}'
        names.append(name)
        label(name)
        if m in (2, 5, 6) or idx in (0x38, 0x39, 0x3A, 0x3B):
            emit_ea_address(idx, None, charge_it=False)
            ea_return()
        else:
            goto('IllegalOp')
    TABLES['Ctl'] = names

# Read the source operand of op's EA field into vs (Dn inline).
def src(s, an_ok=True, data_only=False):
    ret = newlab('S')
    e('  If (op & $38) = 0')
    e(f'    vs = {dreg(OPR(), s)}')
    e(f'    Goto {ret}')
    e('  EndIf')
    if not an_ok or data_only:
        e('  If (op & $38) = 8')
        e('    Goto IllegalOp')
        e('  EndIf')
    ea_call(f'Src{s}', ret)
    label(ret)

def alt(s):
    """ea := the alterable memory operand of op's EA field."""
    ret = newlab('A')
    ea_call(f'Alt{s}', ret)
    label(ret)

def ctl():
    ret = newlab('C')
    ea_call('Ctl', ret)
    label(ret)

# ---------------------------------------------------------------- dispatch table
DISPATCH = ['IllegalOp'] * 1024

def slot(op_hi, handler):
    DISPATCH[op_hi] = handler

def slots(match, handler):
    """Assign handler to every slot (op >> 6) for which match(slot) is true."""
    for i in range(1024):
        if match(i):
            DISPATCH[i] = handler

def handler(name):
    e('')
    label(name)
    if TARGET == 'rp2350' and name in m68k_fast.FAST:
        # the hand-written fast path (tools/m68k_fast.py); it falls through to the code below
        e(f'  ASM Uses {m68k_fast.USES[name]}')
        for line in m68k_fast.FAST[name]:
            e(('    ' if not line.endswith(':') else '  ') + line)
        e('  EndASM')
    e('  op = PeekU(PIP)')
    e('  xo = 2')

def exc(vec, pc_expr, cyc):
    """Take exception vec, pushing pc_expr; cyc cycles in all."""
    e(f'  ExcPc = {pc_expr}')
    e(f'  ExcVec = {vec}')
    e(f'  ExcCyc = {cyc}')
    goto('TakeExc')

def need_super():
    e('  If (SrHi & $2000) = 0')
    goto('PrivViol')
    e('  EndIf')

def jump_to(target, cyc, fault_pc=None):
    """PC := target (a guest address held in a local other than t/u). cyc is
    the instruction's cycle count when it completes: a jump to an odd address
    faults on the fetch, after cyc - 8 cycles."""
    e(f'  If {target} & 1')
    e(f'    AeAddr = {target}')
    if fault_pc is None:
        e(f'    AePc = {target} - 4')
    else:
        e(f'    AePc = {fault_pc}')
    if isinstance(cyc, int):
        e(f'    AeBack = {8 - cyc}')
    else:
        e(f'    AeBack = 8 - ({cyc})')
    goto('JumpErr')
    e('  EndIf')
    e(f'  PIP = PBase + {target}')
    e('  If PIP < PStart')
    e('    PEnd = 0')
    e('  EndIf')

import m68k_ops
import m68k_fast

def generate(target):
    global IW, DESKTOP, TARGET
    OUT.clear()
    TABLES.clear()
    _lab_n[0] = 0
    for i in range(1024):
        DISPATCH[i] = 'IllegalOp'
    TARGET = target
    DESKTOP = target == 'desktop'
    IW = 64 if DESKTOP else 32
    m68k_ops.bind(sys.modules[__name__])
    m68k_fast.build()
    e('; Generated by tools/gen_m68k.py. Edit the generator, then regenerate.')
    if DESKTOP:
        e('; Motorola 68000 interpreter core, PureBasic (C back end, x64), for the desktop program.')
        e('; The same handlers as the Pico cores, with 64-bit flag shifts; the computed')
        e('; jumps are C labels-as-values (gcc && and goto *).')
    else:
        e('; Motorola 68000 interpreter core for the Raspberry Pi Pico series, PureMetal.')
    e(f'; Target: {target}. See README.md for the API, memory map and limits.')
    e(';')
    e('; Configuration, declared by the including program before XIncludeFile:')
    e(';   #M68K_ASM_TAIL 1 = inline-assembly dispatch tail, 0 = PureMetal Goto (Pico only)')
    e(';')
    e('; The including program defines these procedures (any order):')
    e(';   M68kHookRd8.i(a.i) / M68kHookRd16.i(a.i)       read from a hook page (a: 24-bit, even for 16)')
    e(';   M68kHookWr8(a.i, v.i) / M68kHookWr16(a.i, v.i)  write to a hook page')
    e(';   M68kResetHook()                                the RESET instruction')
    e('EnableExplicit')
    e('')
    if DESKTOP:
        e('Declare.i M68kHookRd8(a.i)')
        e('Declare.i M68kHookRd16(a.i)')
        e('Declare M68kHookWr8(a.i, v.i)')
        e('Declare M68kHookWr16(a.i, v.i)')
        e('Declare M68kResetHook()')
        e('#M68K_ASM_TAIL = 0')
        e('')
    e('#M68K_PAGES = 4096                 ; 16 MB in 4 KB pages')
    e('#M68K_RAM = 0                      ; page kinds')
    e('#M68K_ROM = 1')
    e('#M68K_HOOK = 2')
    e('')
    e('Global Dim Reg.l(16)               ; D0-D7 then A0-A7 (A7 = the active stack pointer)')
    e('Global Dim PageR.i(#M68K_PAGES)    ; host address minus guest page base, 0 = slow path')
    e('Global Dim PageW.i(#M68K_PAGES)')
    e('Global Dim PageK.a(#M68K_PAGES)')
    e('Global Dim Buf.u(8)                ; an instruction fetched across a page end')
    e('Global Dim EaCtlCyc.a(384)         ; LEA/PEA/JMP/JSR/MOVEM cycles: kind * 64 + EA field')
    if not DESKTOP:
        e('Global Dim Dispatch.Label(1024)')
        for t in ('SrcB', 'SrcW', 'SrcL', 'AltB', 'AltW', 'AltL', 'Ctl'):
            e(f'Global Dim {t}.Label(64)')
        e('Global EaRet.Label')
    e('Global PIP.i, PEnd.i, CLeft.i, FZ.i, FN.i, FC.i, FV.i, FX.i')
    e('Global PBase.i, PStart.i, Budget.i, SrHi.i, USP.i, SSP.i')
    e('Global IplLine.i, Stopped.i, Halted.i, TracePend.i, Ready.i, InitIndex.i')
    e('Global AErr.i, AeAddr.i, AePc.i, AeCode.i, AeBack.i, ExcPc.i, ExcVec.i, ExcCyc.i')
    e('Global M68kFetching.i, M68kCycles.i, M68kLastVec.i, M68kExceptions.i   ; the last exception taken, and how many')
    if TARGET == 'rp2350':
        e('Global M68kFastHit.i, M68kFastMiss.i   ; instructions done by a fast path (tools/m68k_fast.py) / handed back')
    if HIST:
        e('Global Dim M68kHist.q(65535)          ; --hist build: opcodes run, by opcode')
    if not DESKTOP:
        regs = 'PIP = r4, CLeft = r6, FZ = r8, FN = r9, FC = r10, PEnd = r11'
        e(f'ReserveRegister {regs}')
    e('')
    m68k_ops.emit_support()
    m68k_ops.emit_run()
    return '\n'.join(OUT) + '\n'

def main():
    global HIST
    sys.path.insert(0, str(Path(__file__).parent))
    out = ROOT
    if '--hist' in sys.argv:
        # a profiling core for the desktop only: desktop/m68k_core_hist.pbi (not checked in)
        HIST = True
        text = generate('desktop')
        (out / 'desktop/m68k_core_hist.pbi').write_text(text, newline=chr(10))
        print('desktop/m68k_core_hist.pbi', len(text.splitlines()), 'lines')
        return
    for target, name in (('rp2040', 'src/m68k.pico'), ('rp2350', 'src/m68k.pico2'),
                         ('desktop', 'desktop/m68k_core.pbi')):
        text = generate(target)
        p = out / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, newline='\n')
        print(name, len(text.splitlines()), 'lines')

if __name__ == '__main__':
    main()
