"""Thumb fast paths for the RP2350 68000 core: hand-written assembly at the top
of the busiest handlers, for their commonest addressing modes.

Why: PureMetal keeps a procedure's locals in its stack frame, so a compiled
handler stores and reloads every intermediate value - ADD.L Dn,Dn measured
about 100 host cycles, a register-only loop 109 per 68000 instruction (the
Feather, tests/speed). A block here does the same instruction in 25-40.

The contract, which keeps the verified PureMetal code the authority:
- A block reads the opcode, picks a path by addressing mode, and jumps to its
  fall-back label (the PureMetal handler right after the block, which starts
  from scratch) for ANYTHING it does not do: other modes, a hook page (the
  chips, the CIAs), no page, an odd address, a long that crosses a page.
- A path changes nothing - no register, no memory, no flag, no cycle count,
  no PIP - until every check has passed. Then it does the whole instruction
  and dispatches the next (the NextOp tail).
- Registers: r4 = PIP, r6 = CLeft, r8 = FZ, r9 = FN, r10 = FC, r11 = PEnd
  (the core's reserved Globals); r0-r3 and r5 are scratch; r7 is the frame.
  FV and FX live in memory (global_fv, global_fx).
- RP2350 only: the M33 allows the unaligned 32-bit loads a long access makes
  (guest words are kept in host order; a long is the two halves swapped).

Every path is proven by the 68000 corpus on the board (state and cycles) and
by the demo's chip RAM matching the PC at frame 400.
"""

FAST = {}            # handler name -> list of asm lines (without ASM / EndASM)
USES = {}            # handler name -> the reserved Globals the block names

_n = [0]

def _lab(h, what):
    _n[0] += 1
    return f'fp_{h.lower()}_{what}_{_n[0]}'

# ---------------------------------------------------------------- fragments
def dispatch():
    """The NextOp tail, inline."""
    return ['cmp r6, #0',
            'ble __ul_m68krun_done',
            'cmp r4, r11',
            'bhs __ul_m68krun_resync',
            'ldrh r0, [r4]',
            'lsrs r0, r0, #6',
            'lsls r0, r0, #2',
            'ldr r1, =global_dispatch',
            'ldr r1, [r1, r0]',
            'bx r1']

COUNT = False     # True: count fast-path hits and fall-backs (M68kFastHit / M68kFastMiss) for the profile

def count(var):
    if not COUNT:
        return []
    return [f'ldr r1, =global_{var}', 'ldr r2, [r1]', 'adds r2, #1', 'str r2, [r1]']

def finish(cycles, length):
    out = count('m68kfasthit')
    c = cycles
    while c > 0:
        k = min(c, 255)
        out.append(f'subs r6, #{k}')
        c -= k
    out.append(f'adds r4, #{length}')
    return out + dispatch()

def reg_addr(dst, field_shift, an, tmp):
    """dst = the address of Reg(n): n = (op >> field_shift) & 7, + 8 for An. op in r0."""
    out = []
    if field_shift:
        out.append(f'lsrs {dst}, r0, #{field_shift}')
    else:
        out.append(f'movs {dst}, r0')
    out += [f'movs {tmp}, #7', f'ands {dst}, {tmp}']
    if an:
        out.append(f'adds {dst}, #8')
    out += [f'lsls {dst}, {dst}, #2', f'ldr {tmp}, =global_reg', f'adds {dst}, {dst}, {tmp}']
    return out

def ea_d16(dst, field_shift, ext_off, tmp):
    """dst = An + the sign-extended word at PIP + ext_off (op in r0)."""
    return reg_addr(dst, field_shift, True, tmp) + [
        f'ldr {dst}, [{dst}]',
        f'movs {tmp}, #{ext_off}',
        f'ldrsh {tmp}, [r4, {tmp}]',
        f'adds {dst}, {dst}, {tmp}']

def host_of(ea, dst, fb, table, size, nopage=None):
    """dst = the host address of guest ea through PageR/PageW; fall back on no
    page (or go to nopage), an odd address, or (size 4) a long that would cross
    the page."""
    out = [f'lsls {dst}, {ea}, #31', f'bne {fb}']           # odd
    if size == 4:
        # (ea & $FFE) = $FFE: the long's second word is on the next page
        out += [f'lsls {dst}, {ea}, #20', f'lsrs {dst}, {dst}, #21',
                f'ldr r1, ={0x7FF}', f'cmp {dst}, r1', f'beq {fb}']
    out += [f'lsls {dst}, {ea}, #8', f'lsrs {dst}, {dst}, #20', f'lsls {dst}, {dst}, #2',
            f'ldr r1, =global_{table}', f'ldr {dst}, [r1, {dst}]',
            f'cmp {dst}, #0', f'beq {nopage or fb}',
            f'lsls r1, {ea}, #8', f'lsrs r1, r1, #8', f'adds {dst}, {dst}, r1']
    return out

def load(size, val, host):
    if size == 2:
        return [f'ldrh {val}, [{host}]']
    return [f'ldr {val}, [{host}]', 'movs r1, #16', f'rors {val}, r1']

def store(size, val, host):
    if size == 2:
        return [f'strh {val}, [{host}]']
    return ['movs r1, #16', f'rors {val}, r1', f'str {val}, [{host}]', f'rors {val}, r1']

def flags_logic(size, val):
    """N, Z from val; V = C = 0 (MOVE, TST, CLR...)."""
    out = []
    if size == 2:
        out += [f'lsls r1, {val}, #16', 'mov r8, r1', 'mov r9, r1']
    else:
        out += [f'mov r8, {val}', f'mov r9, {val}']
    out += ['movs r1, #0', 'mov r10, r1', 'ldr r5, =global_fv', 'str r1, [r5]']
    return out

# ---------------------------------------------------------------- sources
# Each source returns (lines, ext_bytes, src_cycles_by_size): lines leave the
# operand in r2 (zero-extended for .W) and use r0 = op, r1, r3, r5.
def src(mode, size, fb, ext_off=2, src_regs='r5', hook=False):
    """hook: a word read from a page that is not RAM goes to the chips' read hook
    (M68kHookRd16, as M68kRd16 would) instead of falling back. Only for handlers
    whose every fall-back check comes BEFORE the source is read: a chip
    register read can have an effect (CLXDAT, the CIAs' ICR) and must not
    happen twice. The call leaves r0-r3 changed; op is read again."""
    if mode == 'Dn':
        return reg_addr('r3', 0, False, 'r1') + ([f'ldrh r2, [r3]'] if size == 2 else ['ldr r2, [r3]']), 0, 0
    if mode == 'An':
        return reg_addr('r3', 0, True, 'r1') + ([f'ldrh r2, [r3]'] if size == 2 else ['ldr r2, [r3]']), 0, 0
    if mode == 'imm':
        if size == 2:
            return [f'movs r1, #{ext_off}', 'ldrh r2, [r4, r1]'], 2, 4
        return [f'movs r1, #{ext_off}', 'ldr r2, [r4, r1]', 'movs r1, #16', 'rors r2, r1'], 4, 8
    if mode == 'd16':
        if src_regs == 'r3':      # r5 is taken (it holds a destination): ea in r3, host in r2
            return (ea_d16('r3', 0, ext_off, 'r1') + host_of('r3', 'r2', fb, 'pager', size)
                    + load(size, 'r2', 'r2')), 2, (8 if size == 2 else 12)
        if hook and size == 2:
            H, J = _lab('src', 'hook'), _lab('src', 'join')
            return (ea_d16('r5', 0, ext_off, 'r1') + host_of('r5', 'r3', fb, 'pager', size, nopage=H)
                    + load(size, 'r2', 'r3') + [f'b {J}', f'{H}:',
                    'lsls r0, r5, #8', 'lsrs r0, r0, #8', 'bl m68khookrd16', 'uxth r2, r0',
                    'ldrh r0, [r4]', f'{J}:']), 2, 8
        return (ea_d16('r5', 0, ext_off, 'r1') + host_of('r5', 'r3', fb, 'pager', size)
                + load(size, 'r2', 'r3')), 2, (8 if size == 2 else 12)
    raise ValueError(mode)

MODE_TEST = {   # how a block recognises the source mode in op (r0)
    'Dn': ('mode', 0), 'An': ('mode', 1), 'd16': ('mode', 5), 'imm': ('ea', 0x3C),
}

def mode_switch(h, modes, fb):
    """Branch to a path label per supported source mode; anything else to fb."""
    out = ['ldrh r0, [r4]', 'lsrs r1, r0, #3', 'movs r2, #7', 'ands r1, r2']
    labels = {}
    for m in modes:
        kind, v = MODE_TEST[m]
        lab = _lab(h, m)
        labels[m] = lab
        if kind == 'mode':
            out += [f'cmp r1, #{v}', f'beq {lab}']
    if 'imm' in modes:
        out += ['movs r1, #63', 'ands r1, r0', 'cmp r1, #60', f'beq {labels["imm"]}']
    out.append(f'b {fb}')
    return out, labels

import os
ONLY = [x for x in os.environ.get('M68K_FAST_ONLY', '').split(',') if x]   # bisecting: just these

def block(h, modes, body, uses):
    """body(mode, fb) -> the lines of one path, which end in a dispatch."""
    if ONLY and h not in ONLY:
        return
    fb = f'fp_{h.lower()}_fallback'
    out, labels = mode_switch(h, modes, fb)
    for m in modes:
        out.append(f'{labels[m]}:')
        out += body(m, fb)
    out.append(f'{fb}:')
    out += count('m68kfastmiss')
    FAST[h] = out
    USES[h] = uses_of(out)

ALL = 'CLeft, PIP, PEnd, FZ, FN, FC'

# ---------------------------------------------------------------- the handlers
def build():
    FAST.clear(); USES.clear()

    # MOVE.W / MOVE.L <ea>,Dn  (MoveW0, MoveL0)
    for size, h in ((2, 'MoveW0'), (4, 'MoveL0')):
        def body(m, fb, size=size):
            lines, ext, cyc = src(m, size, fb, hook=True)
            return (lines + reg_addr('r3', 9, False, 'r1')
                    + [('strh' if size == 2 else 'str') + ' r2, [r3]']
                    + flags_logic(size, 'r2') + finish(4 + cyc, 2 + ext))
        block(h, ['Dn', 'd16', 'imm', 'An'] if size == 4 else ['Dn', 'd16', 'imm'], body, ALL)

    # MOVEA.L <ea>,An (MoveL1): no flags
    def body_movea(m, fb):
        lines, ext, cyc = src(m, 4, fb)
        return lines + reg_addr('r3', 9, True, 'r1') + ['str r2, [r3]'] + finish(4 + cyc, 2 + ext)
    block('MoveL1', ['Dn', 'An', 'd16', 'imm'], body_movea, 'CLeft, PIP, PEnd')

    # MOVE.W / MOVE.L <ea>,(d16,An)  (MoveW5, MoveL5). The destination's host
    # address is found first (into r5), then the source into r2 - no stack: a
    # push/pop inside a block broke every handler of the procedure (bisected
    # on the board, 2026-10-24).
    for size, h in ((2, 'MoveW5'), (4, 'MoveL5')):
        def body(m, fb, size=size):
            ext = {'Dn': 0, 'd16': 2, 'imm': size}[m]
            out = ea_d16('r3', 9, 2 + ext, 'r1') + host_of('r3', 'r5', fb, 'pagew', size)
            lines, ext2, cyc = src(m, size, fb, src_regs='r3')
            out += lines + store(size, 'r2', 'r5') + flags_logic(size, 'r2')
            dcyc = 8 if size == 2 else 12
            return out + finish(4 + cyc + dcyc, 4 + ext)
        block(h, ['Dn', 'd16', 'imm'], body, ALL)

    # CMP.W <ea>,Dn (CMPWEaDn)
    def body_cmpw(m, fb):
        lines, ext, cyc = src(m, 2, fb, hook=True)
        return lines + reg_addr('r3', 9, False, 'r1') + [
            'ldrh r3, [r3]',
            'lsls r3, r3, #16', 'lsls r2, r2, #16',
            'subs r3, r3, r2',            # Dn - src in the top half: N Z V C of a word compare
            'mov r8, r3', 'mov r9, r3',
        ] + capture_vc(borrow=True, x=False, tag=_lab('cmpw', 'v')) + finish(4 + cyc, 2 + ext)
    block('CMPWEaDn', ['Dn', 'd16', 'imm'], body_cmpw, ALL)

    # BTST #n,Dn (BTSTI): Z = the bit is clear (FZ holds the bit), 10 cycles
    fbb = 'fp_btsti_fallback'
    FAST['BTSTI'] = ['ldrh r0, [r4]', 'movs r1, #56', 'tst r0, r1', f'bne {fbb}',
                     'movs r1, #2', 'ldrh r1, [r4, r1]', 'movs r2, #31', 'ands r1, r2',
                     'movs r2, #7', 'ands r2, r0', 'lsls r2, r2, #2', 'ldr r3, =global_reg',
                     'ldr r2, [r3, r2]', 'lsrs r2, r1', 'movs r1, #1', 'ands r2, r1',
                     'mov r8, r2'] + finish(10, 4) + [f'{fbb}:']
    USES['BTSTI'] = uses_of(FAST['BTSTI'])
    if ONLY and 'BTSTI' not in ONLY:
        del FAST['BTSTI'], USES['BTSTI']

    # SWAP Dn, EXT.W Dn, EXT.L Dn (their handlers also hold PEA / MOVEM: Dn mode only)
    def simple(h, body, cyc):
        fbx = f'fp_{h.lower()}_fallback'
        out = ['ldrh r0, [r4]', 'movs r1, #56', 'tst r0, r1', f'bne {fbx}',
               'movs r3, #7', 'ands r3, r0', 'lsls r3, r3, #2', 'ldr r1, =global_reg',
               'adds r3, r3, r1'] + body + finish(cyc, 2) + [f'{fbx}:']
        if not ONLY or h in ONLY:
            FAST[h] = out
            USES[h] = uses_of(out)
    simple('SwapPea', ['ldr r2, [r3]', 'movs r1, #16', 'rors r2, r1', 'str r2, [r3]']
           + flags_logic(4, 'r2'), 4)
    simple('ExtLMovemL', ['ldrh r2, [r3]', 'sxth r2, r2', 'str r2, [r3]'] + flags_logic(4, 'r2'), 4)
    simple('ExtWMovemW', ['ldrb r2, [r3]', 'sxtb r2, r2', 'strh r2, [r3]', 'uxth r2, r2']
           + flags_logic(2, 'r2'), 4)

    # CLR.W Dn / (d16,An): Z set, N V C clear; the memory form needs a RAM page
    # (the 68000 reads before it writes - a chip register is left to PureMetal)
    def body_clrw(m, fb):
        zero = ['movs r1, #0', 'mov r8, r1', 'mov r9, r1', 'mov r10, r1', 'ldr r5, =global_fv', 'str r1, [r5]']
        if m == 'Dn':
            return reg_addr('r3', 0, False, 'r1') + ['movs r2, #0', 'strh r2, [r3]'] + zero + finish(4, 2)
        return (ea_d16('r5', 0, 2, 'r1') + host_of('r5', 'r3', fb, 'pagew', 2)
                + ['movs r2, #0', 'strh r2, [r3]'] + zero + finish(16, 4))
    block('CLRW', ['Dn', 'd16'], body_clrw, None)

    # ADD.W / ADD.L / AND.W Dn,(d16,An): read, operate, write back (a RAM page)
    for h, size, kind, cyc in (('ADDWDnEa', 2, 'add', 16), ('ADDLDnEa', 4, 'add', 24), ('ANDWDnEa', 2, 'and', 16)):
        def body(m, fb, size=size, kind=kind, cyc=cyc):
            out = ea_d16('r5', 0, 2, 'r1') + host_of('r5', 'r3', fb, 'pagew', size)
            out += load(size, 'r2', 'r3')                         # vd
            out += reg_addr('r5', 9, False, 'r1')                 # &Dn
            if size == 2:
                out += ['ldrh r1, [r5]']
                if kind == 'add':
                    out += ['lsls r1, r1, #16', 'lsls r2, r2, #16', 'adds r2, r2, r1',
                            'mov r8, r2', 'mov r9, r2'] + capture_vc(False, True, _lab(h, 'v')) + ['lsrs r2, r2, #16']
                else:
                    out += ['ands r2, r1'] + flags_logic(2, 'r2')
            else:
                out += ['ldr r1, [r5]', 'adds r2, r2, r1', 'mov r8, r2', 'mov r9, r2'] + capture_vc(False, True, _lab(h, 'v'))
            out += store(size, 'r2', 'r3')
            return out + finish(cyc, 4)
        block(h, ['d16'], body, None)

    # MOVE.B <ea>,Dn (MoveB0): Dn, (d16,An) (a byte is at address ^ 1), #imm
    def body_moveb(m, fb):
        if m == 'Dn':
            lines, ext, cyc = reg_addr('r3', 0, False, 'r1') + ['ldrb r2, [r3]'], 0, 0
        elif m == 'imm':
            lines, ext, cyc = ['movs r1, #2', 'ldrb r2, [r4, r1]'], 2, 4
        else:
            lines = ea_d16('r5', 0, 2, 'r1') + [
                'lsls r3, r5, #8', 'lsrs r3, r3, #20', 'lsls r3, r3, #2',
                'ldr r1, =global_pager', 'ldr r3, [r1, r3]', 'cmp r3, #0', f'beq {fb}',
                'lsls r1, r5, #8', 'lsrs r1, r1, #8', 'movs r2, #1', 'eors r1, r2',
                'adds r3, r3, r1', 'ldrb r2, [r3]']
            ext, cyc = 2, 8
        return (lines + reg_addr('r3', 9, False, 'r1') + ['strb r2, [r3]',
                'lsls r1, r2, #24', 'mov r8, r1', 'mov r9, r1', 'movs r1, #0', 'mov r10, r1',
                'ldr r5, =global_fv', 'str r1, [r5]'] + finish(4 + cyc, 2 + ext))
    block('MoveB0', ['Dn', 'd16', 'imm'], body_moveb, None)

    # RTS: pop the PC (a RAM stack, the long on one page, an even target)
    fbr = 'fp_rts_fallback'
    rts = ['ldrh r0, [r4]', 'ldr r1, =$4E75', 'cmp r0, r1', f'bne {fbr}',
           'ldr r3, =global_reg', 'ldr r5, [r3, #60]'] + host_of('r5', 'r2', fbr, 'pager', 4) + [
           'ldr r2, [r2]', 'movs r1, #16', 'rors r2, r1',          # the return address
           'lsls r1, r2, #31', f'bne {fbr}',
           'adds r5, #4', 'str r5, [r3, #60]',
           'ldr r1, =global_pbase', 'ldr r1, [r1]', 'adds r4, r1, r2',   # PIP = PBase + target
           'ldr r1, =global_pstart', 'ldr r1, [r1]', 'cmp r4, r1', 'bhs fp_rts_in',
           'movs r1, #0', 'mov r11, r1', 'fp_rts_in:'] + count('m68kfasthit') + ['subs r6, #16'] + dispatch() + [f'{fbr}:'] + count('m68kfastmiss')
    if not ONLY or 'Misc4E' in ONLY:
        FAST['Misc4E'] = rts
        USES['Misc4E'] = uses_of(rts)

    # JSR abs.l: push the return address (a RAM stack), jump to an even target
    fbj = 'fp_jsr_fallback'
    jsr = ['ldrh r0, [r4]', 'ldr r1, =$4EB9', 'cmp r0, r1', f'bne {fbj}',
           'movs r1, #2', 'ldr r2, [r4, r1]', 'movs r1, #16', 'rors r2, r1',   # target
           'lsls r1, r2, #31', f'bne {fbj}',
           'ldr r3, =global_reg', 'ldr r5, [r3, #60]', 'subs r5, #4'] + host_of('r5', 'r0', fbj, 'pagew', 4) + [
           'str r5, [r3, #60]',
           'ldr r1, =global_pbase', 'ldr r1, [r1]', 'subs r3, r4, r1', 'adds r3, #6',    # the return address
           'movs r5, #16', 'rors r3, r5', 'str r3, [r0]',
           'adds r4, r1, r2',
           'ldr r1, =global_pstart', 'ldr r1, [r1]', 'cmp r4, r1', 'bhs fp_jsr_in',
           'movs r1, #0', 'mov r11, r1', 'fp_jsr_in:'] + count('m68kfasthit') + ['subs r6, #20'] + dispatch() + [f'{fbj}:'] + count('m68kfastmiss')
    if not ONLY or 'JSR' in ONLY:
        FAST['JSR'] = jsr
        USES['JSR'] = uses_of(jsr)

    # Bcc and BRA
    import gen_m68k
    for cc in [0] + list(range(2, 16)):
        name = 'BRA' if cc == 0 else f'B{gen_m68k.CCNAME[cc]}'
        if not ONLY or name in ONLY:
            bcc(cc, name)

def cond_true(cc, T, NT):
    """Branch to T when condition cc holds (the core's flag form), else fall through."""
    z = ['mov r1, r8', 'cmp r1, #0']
    n = ['mov r1, r9', 'cmp r1, #0']
    c = ['mov r1, r10', 'cmp r1, #0']
    nv = ['ldr r1, =global_fv', 'ldr r1, [r1]', 'mov r2, r9', 'eors r1, r2', 'cmp r1, #0']
    v = ['ldr r1, =global_fv', 'ldr r1, [r1]', 'cmp r1, #0']
    return {
        0: [f'b {T}'],
        2: c + [f'blt {NT}'] + z + [f'bne {T}'],
        3: c + [f'blt {T}'] + z + [f'beq {T}'],
        4: c + [f'bge {T}'],
        5: c + [f'blt {T}'],
        6: z + [f'bne {T}'],
        7: z + [f'beq {T}'],
        8: v + [f'bge {T}'],
        9: v + [f'blt {T}'],
        10: n + [f'bge {T}'],
        11: n + [f'blt {T}'],
        12: nv + [f'bge {T}'],
        13: nv + [f'blt {T}'],
        14: nv + [f'blt {NT}'] + z + [f'bne {T}'],
        15: nv + [f'blt {T}'] + z + [f'beq {T}'],
    }[cc]

def bcc(cc, name):
    """Bcc / BRA: not taken 8 (byte) or 12 (word) cycles, taken 10; an odd
    target is left to the PureMetal code (it takes the address error)."""
    fb = f'fp_{name.lower()}_fallback'
    T, NT, W = _lab(name, 't'), _lab(name, 'nt'), _lab(name, 'w')
    out = ['ldrh r0, [r4]'] + cond_true(cc, T, NT)
    out += [f'{NT}:', 'movs r1, #255', 'ands r1, r0', f'beq {W}']
    out += count('m68kfasthit') + ['subs r6, #8', 'adds r4, #2'] + dispatch()
    out += [f'{W}:'] + count('m68kfasthit') + ['subs r6, #12', 'adds r4, #4'] + dispatch()
    D = _lab(name, 'd')
    out += [f'{T}:', 'movs r1, #255', 'ands r1, r0', f'beq {D}', 'sxtb r1, r0']
    G = _lab(name, 'go')
    out += [f'b {G}', f'{D}:', 'movs r1, #2', 'ldrsh r1, [r4, r1]']
    out += [f'{G}:', 'lsls r2, r1, #31', f'bne {fb}',
            'adds r4, r4, r1', 'adds r4, #2',                 # PIP of the target
            'ldr r2, =global_pstart', 'ldr r2, [r2]', 'cmp r4, r2', f'bhs {G}_in',
            'movs r2, #0', 'mov r11, r2',                      # behind the window: resync
            f'{G}_in:'] + count('m68kfasthit') + ['subs r6, #10'] + dispatch()
    out.append(f'{fb}:')
    out += count('m68kfastmiss')
    FAST[name] = out
    USES[name] = uses_of(out)

def uses_of(lines):
    """The reserved Globals a block names (ASM Uses must list exactly those)."""
    import re
    text = ' '.join(lines)
    regs = set(re.findall(r'\br(\d+)\b', text))
    names = [('4', 'PIP'), ('6', 'CLeft'), ('8', 'FZ'), ('9', 'FN'), ('10', 'FC'), ('11', 'PEnd')]
    return ', '.join(n for r, n in names if r in regs)

def capture_vc(borrow, x, tag):
    """Right after an ARM adds/subs (N Z V C live): FV and FC (and FX) in the
    core's form - the flag in bit 31. Nothing here may set V or C before they
    are read: movs #imm, ldr, str and high-register movs leave both alone."""
    out = ['movs r1, #0', f'bvc {tag}', 'ldr r1, =$80000000', f'{tag}:',
           'ldr r5, =global_fv', 'str r1, [r5]',
           'movs r1, #0', 'sbcs r1, r1']          # r1 = C - 1: -1 when ARM's C is clear
    if not borrow:
        out.append('mvns r1, r1')                 # an add: the 68000's C is ARM's C
    out.append('mov r10, r1')
    if x:
        out += ['ldr r5, =global_fx', 'str r1, [r5]']
    return out

if __name__ == '__main__':
    build()
    for h, lines in FAST.items():
        print(h, len(lines))
