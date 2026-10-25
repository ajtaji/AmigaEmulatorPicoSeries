"""The 68000 instruction handlers and support procedures, emitted through gen_m68k."""

G = None

def bind(g):
    global G
    G = g
    for k in ('e', 'label', 'goto', 'newlab', 'handler', 'slot', 'slots', 'src', 'alt', 'ctl',
              'rd', 'wr', 'charge', 'tail', 'next_op', 'dispatch_now', 'nz', 'clr_vc',
              'flags_logic', 'flags_add', 'flags_sub', 'XBIT', 'COND', 'CCNAME', 'dreg',
              'dreg_c', 'set_dreg', 'OPR', 'OPR9', 'ext_w', 'ext_l', 'exc', 'need_super',
              'jump_to', 'SX8', 'SX16', 'SX32', 'SXS', 'MASK', 'SH', 'shl', 'TOP', 'L32',
              'BITS', 'INC', 'SIZES', 'ea_call', 'ea_return', 'table_goto', 'PROC',
              'guest_pc', 'index_ea', 'lab', 'M24'):
        globals()[k] = getattr(g, k)

def IW():
    return G.IW

def DESK():
    return G.DESKTOP

def PCNOW():
    return '(PIP - PBase)'

def PCX():
    """Guest address just past the bytes read so far (the next instruction at the end)."""
    return '(PIP - PBase + xo)'

def U32(v):
    """v as an unsigned 32-bit value, for the PC (64-bit host only)."""
    return f'(({v}) & $FFFFFFFF)' if DESK() else v

# ---------------------------------------------------------------- support procedures
def udiv_steps(hi, lo, v):
    """q, r := the 32-bit unsigned value hi:lo divided by v (16 bits), where
    hi < v so q fits 16 bits: restoring division a bit at a time, every value
    below $20000, so it is exact in a signed 32-bit .i."""
    e(f'  r = {hi}')
    e(f'  lo = {lo}')
    e('  q = 0')
    e('  For i = 15 To 0 Step -1')
    e('    r = (r << 1) | ((lo >> i) & 1)')
    e('    q = q << 1')
    e(f'    If r >= {v}')
    e(f'      r = r - {v}')
    e('      q = q | 1')
    e('    EndIf')
    e('  Next')

def emit_support():
    P = PROC()
    e('; ------------------------------------------------------------ slow memory paths')
    e('; Any address, any page kind. A word or long at an odd address is an address')
    e('; error: AErr = 1 and the caller raises it. Hook pages call the machine.')
    e(f'{P}.i M68kRd8(a.i)')
    e('  Protected p.i')
    e('  p = (a >> 12) & $FFF')
    e('  If PageK(p) = #M68K_HOOK')
    e('    ProcedureReturn M68kHookRd8(a & $FFFFFF) & 255')
    e('  EndIf')
    e('  ProcedureReturn PeekA(PageR(p) + ((a & $FFFFFF) ! 1))')
    e('EndProcedure')
    e('')
    e(f'{P}.i M68kRd16(a.i)')
    e('  Protected p.i')
    e('  If a & 1')
    e('    AErr = 1')
    e('    AeBack = 4')
    e('    AeCode = $10')
    e('    ProcedureReturn 0')
    e('  EndIf')
    e('  p = (a >> 12) & $FFF')
    e('  If PageK(p) = #M68K_HOOK')
    e('    ProcedureReturn M68kHookRd16(a & $FFFFFF) & $FFFF')
    e('  EndIf')
    e('  ProcedureReturn PeekU(PageR(p) + (a & $FFFFFF))')
    e('EndProcedure')
    e('')
    e(f'{P}.i M68kRd32(a.i)')
    e('  Protected h.i')
    e('  If a & 1')
    e('    AErr = 1')
    e('    AeBack = 8')
    e('    AeCode = $10')
    e('    ProcedureReturn 0')
    e('  EndIf')
    e('  h = M68kRd16(a)')
    e('  ProcedureReturn (h << 16) | M68kRd16(a + 2)')
    e('EndProcedure')
    e('')
    e(f'{P} M68kWr8(a.i, v.i)')
    e('  Protected p.i')
    e('  p = (a >> 12) & $FFF')
    e('  If PageK(p) = #M68K_RAM')
    e('    PokeA(PageW(p) + ((a & $FFFFFF) ! 1), v)')
    e('  Else')
    e('    M68kHookWr8(a & $FFFFFF, v & 255)')
    e('  EndIf')
    e('EndProcedure')
    e('')
    e(f'{P} M68kWr16(a.i, v.i)')
    e('  Protected p.i')
    e('  If a & 1')
    e('    AErr = 1')
    e('    AeBack = 4')
    e('    AeCode = 0')
    e('    ProcedureReturn')
    e('  EndIf')
    e('  p = (a >> 12) & $FFF')
    e('  If PageK(p) = #M68K_RAM')
    e('    PokeU(PageW(p) + (a & $FFFFFF), v)')
    e('  Else')
    e('    M68kHookWr16(a & $FFFFFF, v & $FFFF)')
    e('  EndIf')
    e('EndProcedure')
    e('')
    e(f'{P} M68kWr32(a.i, v.i)')
    e('  If a & 1')
    e('    AErr = 1')
    e('    AeBack = 8')
    e('    AeCode = 0')
    e('    ProcedureReturn')
    e('  EndIf')
    e('  M68kWr16(a, v >> 16)')
    e('  M68kWr16(a + 2, v)')
    e('EndProcedure')
    e('')
    e('; ------------------------------------------------------------ status register')
    e(f'{P}.i M68kGetSR()')
    e('  Protected f.i')
    e('  f = SrHi')
    e('  If FX < 0')
    e('    f = f | 16')
    e('  EndIf')
    e('  If FN < 0')
    e('    f = f | 8')
    e('  EndIf')
    e('  If FZ = 0')
    e('    f = f | 4')
    e('  EndIf')
    e('  If FV < 0')
    e('    f = f | 2')
    e('  EndIf')
    e('  If FC < 0')
    e('    f = f | 1')
    e('  EndIf')
    e('  ProcedureReturn f')
    e('EndProcedure')
    e('')
    e(f'{P} M68kSetCCR(v.i)')
    e(f'  FX = ((v >> 4) & 1) << {IW() - 1}')
    e(f'  FN = ((v >> 3) & 1) << {IW() - 1}')
    e('  FZ = ((v >> 2) & 1) ! 1')
    e(f'  FV = ((v >> 1) & 1) << {IW() - 1}')
    e(f'  FC = (v & 1) << {IW() - 1}')
    e('EndProcedure')
    e('')
    e('; Supervisor bit: A7 is the SSP in supervisor mode and the USP in user mode.')
    e(f'{P} M68kSetSuper(s.i)')
    e('  If s')
    e('    If (SrHi & $2000) = 0')
    e('      USP = Reg(15)')
    e('      Reg(15) = SSP')
    e('      SrHi = SrHi | $2000')
    e('    EndIf')
    e('  Else')
    e('    If SrHi & $2000')
    e('      SSP = Reg(15)')
    e('      Reg(15) = USP')
    e('      SrHi = SrHi & $A700 & ~$2000')
    e('    EndIf')
    e('  EndIf')
    e('EndProcedure')
    e('')
    e('; Load the whole SR. The interrupt mask, trace and supervisor bits are')
    e('; checked again at the next instruction boundary.')
    e(f'{P} M68kSetSR(v.i)')
    e('  M68kSetCCR(v)')
    e('  M68kSetSuper(v & $2000)')
    e('  SrHi = v & $A700')
    e('  PEnd = 0')
    e('EndProcedure')
    e('')
    e('; ------------------------------------------------------------ registers')
    e('Procedure.i M68kGetPC()')
    e(f'  ProcedureReturn {U32("PIP - PBase")}')
    e('EndProcedure')
    e('')
    e('Procedure M68kSetPC(pc.i)')
    e('  PBase = 0')
    e(f'  PIP = {U32("pc")}')
    e('  PEnd = 0')
    e('EndProcedure')
    e('')
    e('Procedure.i M68kGetUSP()')
    e('  If SrHi & $2000')
    e('    ProcedureReturn USP')
    e('  EndIf')
    e('  ProcedureReturn Reg(15)')
    e('EndProcedure')
    e('')
    e('Procedure.i M68kGetSSP()')
    e('  If SrHi & $2000')
    e('    ProcedureReturn Reg(15)')
    e('  EndIf')
    e('  ProcedureReturn SSP')
    e('EndProcedure')
    e('')
    e('Procedure M68kSetUSP(v.i)')
    e('  If SrHi & $2000')
    e('    USP = v')
    e('  Else')
    e('    Reg(15) = v')
    e('  EndIf')
    e('EndProcedure')
    e('')
    e('Procedure M68kSetSSP(v.i)')
    e('  If SrHi & $2000')
    e('    Reg(15) = v')
    e('  Else')
    e('    SSP = v')
    e('  EndIf')
    e('EndProcedure')
    e('')
    e('; ------------------------------------------------------------ memory map')
    e('; addr and bytes are multiples of 4096 inside the 16 MB bus. The host memory')
    e('; holds the guest\'s 16-bit words in host byte order (see README.md).')
    e('Procedure M68kMapRam(addr.i, bytes.i, host.i)')
    e('  Protected p.i')
    e('  For p = (addr >> 12) & $FFF To ((addr + bytes - 1) >> 12) & $FFF')
    e('    PageK(p) = #M68K_RAM')
    e('    PageR(p) = host - addr')
    e('    PageW(p) = PageR(p)')
    e('  Next')
    e('  PEnd = 0')
    e('EndProcedure')
    e('')
    e('Procedure M68kMapRom(addr.i, bytes.i, host.i)')
    e('  Protected p.i')
    e('  For p = (addr >> 12) & $FFF To ((addr + bytes - 1) >> 12) & $FFF')
    e('    PageK(p) = #M68K_ROM')
    e('    PageR(p) = host - addr')
    e('    PageW(p) = 0')
    e('  Next')
    e('  PEnd = 0')
    e('EndProcedure')
    e('')
    e('Procedure M68kMapHook(addr.i, bytes.i)')
    e('  Protected p.i')
    e('  For p = (addr >> 12) & $FFF To ((addr + bytes - 1) >> 12) & $FFF')
    e('    PageK(p) = #M68K_HOOK')
    e('    PageR(p) = 0')
    e('    PageW(p) = 0')
    e('  Next')
    e('  PEnd = 0')
    e('EndProcedure')
    e('')
    e('; ------------------------------------------------------------ exceptions')
    e('; The 68000\'s six-byte frame: SR, then the PC (written PC low, SR, PC high).')
    e(f'{P} M68kPushFrame(sr.i, pc.i)')
    e('  Protected sp.i')
    e('  sp = Reg(15) - 6')
    e('  Reg(15) = sp')
    e('  If sp & 1')
    e('    Halted = 1')
    e('    ProcedureReturn')
    e('  EndIf')
    e('  M68kWr16(sp + 4, pc)')
    e('  M68kWr16(sp, sr)')
    e('  M68kWr16(sp + 2, pc >> 16)')
    e('EndProcedure')
    e('')
    e('; Group 1 and 2 exceptions (TRAP, CHK, divide by zero, illegal, privilege, trace).')
    e('; (Every procedure that moves the PC does it itself: PIP is held in a register.)')
    e(f'{P} M68kException(vec.i, pc.i)')
    e('  Protected sr.i')
    e('  M68kLastVec = vec')
    e('  M68kExceptions = M68kExceptions + 1')
    e('  sr = M68kGetSR()')
    e('  M68kSetSuper(1)')
    e('  SrHi = SrHi & ~$8000')
    e('  TracePend = 0')
    e('  M68kPushFrame(sr, pc)')
    e('  pc = M68kRd32(vec << 2)')
    e('  PBase = 0')
    e(f'  PIP = {U32("pc")}')
    e('  PEnd = 0')

    e('EndProcedure')
    e('')
    e('; An interrupt of level lv (autovectored, as on the Amiga).')
    e(f'{P} M68kInterrupt(lv.i)')
    e('  Protected sr.i, pc.i')
    e('  M68kLastVec = 24 + lv')
    e('  M68kExceptions = M68kExceptions + 1')
    e('  sr = M68kGetSR()')
    e('  M68kSetSuper(1)')
    e('  SrHi = (SrHi & ~$8700) | (lv << 8)')
    e('  TracePend = 0')
    e('  Stopped = 0')
    e(f'  M68kPushFrame(sr, {U32("PIP - PBase")})')
    e('  pc = M68kRd32((24 + lv) << 2)')
    e('  PBase = 0')
    e(f'  PIP = {U32("pc")}')
    e('  PEnd = 0')

    e('  CLeft = CLeft - 44')
    e('EndProcedure')
    e('')
    e('; Address error: the 14-byte group 0 frame. code: the IR in bits 16-31, the')
    e('; status word (IR bits 5-15, R/W, I/N, function code) in bits 0-15.')
    e(f'{P} M68kAddressError(addr.i, pc.i, code.i)')
    e('  Protected sr.i, sp.i')
    e('  M68kLastVec = 3')
    e('  M68kExceptions = M68kExceptions + 1')
    e('  AErr = 0')
    e('  sr = M68kGetSR()')
    e('  M68kSetSuper(1)')
    e('  SrHi = SrHi & ~$8000')
    e('  TracePend = 0')
    e('  sp = Reg(15) - 14')
    e('  Reg(15) = sp')
    e('  If sp & 1')
    e('    Halted = 1')
    e('    ProcedureReturn')
    e('  EndIf')
    e('  M68kWr16(sp + 12, pc)')
    e('  M68kWr16(sp + 8, sr)')
    e('  M68kWr16(sp + 10, pc >> 16)')
    e('  M68kWr16(sp + 6, code >> 16)')
    e('  M68kWr16(sp + 4, addr)')
    e('  M68kWr16(sp, code)')
    e('  M68kWr16(sp + 2, addr >> 16)')
    e('  pc = M68kRd32(3 << 2)')
    e('  PBase = 0')
    e(f'  PIP = {U32("pc")}')
    e('  PEnd = 0')

    e('EndProcedure')
    e('')
    e('; Power-on reset: supervisor, interrupts masked, SSP and PC from vectors 0 and 1.')
    e('Procedure M68kReset()')
    e('  Protected pc.i')
    e('  SrHi = $2700')
    e('  M68kSetCCR(0)')
    e('  Reg(15) = M68kRd32(0)')
    e('  SSP = Reg(15)')
    e('  Stopped = 0')
    e('  Halted = 0')
    e('  TracePend = 0')
    e('  AErr = 0')
    e('  pc = M68kRd32(1 << 2)')
    e('  PBase = 0')
    e(f'  PIP = {U32("pc")}')
    e('  PEnd = 0')

    e('EndProcedure')
    e('')
    e('; The interrupt priority level the chips present (0 = none, 1-7).')
    e('Procedure M68kSetIpl(lv.i)')
    e('  IplLine = lv')
    e('  PEnd = 0')
    e('EndProcedure')
    e('')
    e('; An instruction boundary with something to do: trace, interrupt, STOP.')
    e('; Returns 0 when the CPU has nothing to run (stopped or halted).')
    e(f'{P}.i M68kEvents()')
    e('  If TracePend')
    e('    TracePend = 0')
    e(f'    M68kException(9, {U32("PIP - PBase")})')
    e('    CLeft = CLeft - 34')
    e('  EndIf')
    e('  If IplLine > ((SrHi >> 8) & 7) Or IplLine = 7')
    e('    If IplLine > ((SrHi >> 8) & 7)')
    e('      M68kInterrupt(IplLine)')
    e('    EndIf')
    e('  EndIf')
    e('  If Stopped Or Halted')
    e('    ProcedureReturn 0')
    e('  EndIf')
    e('  ProcedureReturn 1')
    e('EndProcedure')
    e('')
    e('; Build the fetch window around the guest PC (PIP - PBase).')
    e(f'{P} M68kRemap()')
    e('  Protected pc.i, t.i, i.i')
    e(f'  pc = {U32("PIP - PBase")}')
    e('  t = PageR((pc >> 12) & $FFF)')
    e('  If t <> 0 And (pc & $FFF) < $FF7')
    e('    PStart = t + (pc & $FFF000)')
    e('    PIP = t + (pc & $FFFFFF)')
    e('    PBase = PIP - pc')
    e('    PEnd = PStart + $FF8')
    e('  Else')
    e('    M68kFetching = 1')
    e('    For i = 0 To 4')
    e('      Buf(i) = M68kRd16(pc + i * 2)')
    e('    Next')
    e('    M68kFetching = 0')
    e('    AErr = 0')
    e('    PIP = @Buf(0)')
    e('    PBase = PIP - pc')
    e('    PStart = PIP')
    e('    PEnd = PIP + 1')
    e('  EndIf')
    e('EndProcedure')
    e('')
    emit_divide_procs()
    emit_cyc_tables()
    e('; Extra cycles of LEA, PEA, JMP, JSR and MOVEM by effective-address field.')
    e(f'{P} M68kInitCyc()')
    for i, c in G.CYC_INIT:
        e(f'  EaCtlCyc({i}) = {c}')
    e('EndProcedure')
    e('')

def emit_divide_procs():
    P = PROC()
    T = IW() - 1
    e('; DIVU / DIVS: register rg (0-7) divided by the 16-bit source v. Flags and')
    e('; cycles as the 68000 sets them, undefined flags included. Returns 1 for a')
    e('; divide by zero (the caller takes the exception).')
    e(f'{P}.i M68kDivU(rg.i, v.i)')
    if DESK():
        e('  Protected a.q, q.q, r.q, h.q, i.i, mc.i')
        e('  a = Reg(rg) & $FFFFFFFF')
    else:
        # no .n here: an unsigned quotient compared or divided as .n went wrong on
        # the RP2350 (corpus DIVU/DIVS); 32-bit .i with explicit unsigned steps instead
        e('  Protected a.i, q.i, r.i, h.i, i.i, mc.i, lo.i')
        e('  a = Reg(rg)')
    e('  v = v & $FFFF')
    e('  If v = 0')
    e(f'    FN = ((a >> 31) & 1) << {T}')
    e('    FZ = (a >> 16) & $FFFF')
    e('    FV = 0')
    e('    FC = 0')
    e('    ProcedureReturn 1')
    e('  EndIf')
    e('  If ((a >> 16) & $FFFF) >= v')
    e(f'    FV = 1 << {T}')
    e(f'    FN = 1 << {T}')
    e('    FZ = 1')
    e('    FC = 0')
    e('    CLeft = CLeft - 10')
    e('    ProcedureReturn 0')
    e('  EndIf')
    if DESK():
        e('  q = a / v')
        e('  r = a - q * v')
    else:
        udiv_steps('(a >> 16) & $FFFF', 'a & $FFFF', 'v')
    e(f'  Reg(rg) = (r << 16) | q')
    e(f'  FN = ((q >> 15) & 1) << {T}')
    e('  FZ = q')
    e('  FV = 0')
    e('  FC = 0')
    e('  mc = 38')
    e('  h = v << 16')
    e('  For i = 0 To 14')
    if DESK():
        e('    If a & $80000000')
        e('      a = ((a << 1) - h) & $FFFFFFFF')
        e('    Else')
        e('      a = (a << 1) & $FFFFFFFF')
    else:
        e('    If a < 0')
        e('      a = (a << 1) - h')
        e('    Else')
        e('      a = a << 1')
    if DESK():
        e('      If a >= h')
    else:
        e('      If (a ! $80000000) >= (h ! $80000000)')
    e('        a = a - h')
    e('        mc = mc + 1')
    e('      Else')
    e('        mc = mc + 2')
    e('      EndIf')
    e('    EndIf')
    e('  Next')
    e('  CLeft = CLeft - mc * 2')
    e('  ProcedureReturn 0')
    e('EndProcedure')
    e('')
    e(f'{P}.i M68kDivS(rg.i, v.i)')
    if DESK():
        e('  Protected a.q, d.q, q.q, r.q, aq.i, i.i, mc.i')
        e('  a = Reg(rg)')
    else:
        e('  Protected a.i, d.i, ua.i, ud.i, q.i, r.i, aq.i, i.i, mc.i, lo.i')
        e('  a = Reg(rg)')
    e(f'  d = {SX16("v")}')
    e('  If d = 0')
    e('    FN = 0')
    e('    FZ = 0')
    e('    FV = 0')
    e('    FC = 0')
    e('    ProcedureReturn 1')
    e('  EndIf')
    e('  mc = 6')
    e('  If a < 0')
    e('    mc = 7')
    e('  EndIf')
    if DESK():
        e('  q = Abs(a)')
        e('  r = Abs(d)')
        e('  If (q >> 16) >= r')
    else:
        e('  If a < 0')
        e('    ua = -a')
        e('  Else')
        e('    ua = a')
        e('  EndIf')
        e('  If d < 0')
        e('    ud = -d')
        e('  Else')
        e('    ud = d')
        e('  EndIf')
        e('  If ((ua >> 16) & $FFFF) >= ud')
    e(f'    FV = 1 << {T}')
    e(f'    FN = 1 << {T}')
    e('    FZ = 1')
    e('    FC = 0')
    e('    CLeft = CLeft - (mc + 2) * 2')
    e('    ProcedureReturn 0')
    e('  EndIf')
    if DESK():
        e('  aq = q / r')
    else:
        udiv_steps('(ua >> 16) & $FFFF', 'ua & $FFFF', 'ud')
        e('  aq = q')
    e('  mc = mc + 55')
    e('  If d >= 0')
    e('    If a < 0')
    e('      mc = mc + 1')
    e('    Else')
    e('      mc = mc - 1')
    e('    EndIf')
    e('  EndIf')
    e('  For i = 0 To 14')
    e('    If (aq & $8000) = 0')
    e('      mc = mc + 1')
    e('    EndIf')
    e('    aq = aq << 1')
    e('  Next')
    e('  CLeft = CLeft - mc * 2')
    if DESK():
        e('  q = a / d')
        e('  r = a - q * d')
    else:
        e('  If (a < 0) <> (d < 0)')
        e('    q = -q')
        e('  EndIf')
        e('  If a < 0')
        e('    r = -r')
        e('  EndIf')
    e('  If q > 32767 Or q < -32768')
    e(f'    FV = 1 << {T}')
    e(f'    FN = 1 << {T}')
    e('    FZ = 1')
    e('    FC = 0')
    e('    ProcedureReturn 0')
    e('  EndIf')
    e('  Reg(rg) = ((r & $FFFF) << 16) | (q & $FFFF)')
    e(f'  FN = ((q >> 15) & 1) << {T}')
    e('  FZ = q & $FFFF')
    e('  FV = 0')
    e('  FC = 0')
    e('  ProcedureReturn 0')
    e('EndProcedure')
    e('')

# ---------------------------------------------------------------- the interpreter
def emit_run():
    P = PROC()
    e('; ------------------------------------------------------------ the interpreter')
    e('; M68kRun(n): execute until at least n clock cycles are spent. Returns the')
    e('; cycles used; returns early when the CPU stops (STOP) or halts.')
    if not DESK():
        emit_pm_tail_macro()
    e(f'{P}.i M68kRun(n.i)')
    e('  Protected op.i, xo.i, ea.i, vs.i, vd.i, vr.i, t.i, u.i, x.i, y.i, rg.i')
    if DESK():
        e('  ; @@C_TABLES@@')
    e('  If Ready = 0')
    e('    M68kInitCyc()')
    if not DESK():
        e('    InitDispatch()')
    e('    Ready = 1')
    e('  EndIf')
    e('  If n <= 0')
    e('    ProcedureReturn 0')
    e('  EndIf')
    e('  Budget = n')
    e('  CLeft = n')
    e('  Goto Resync')
    e('')
    label('Resync')
    e('  If Halted')
    e('    CLeft = 0')
    goto('Done')
    e('  EndIf')
    e('  If TracePend Or Stopped Or IplLine > ((SrHi >> 8) & 7) Or (SrHi & $8000)')
    e('    If M68kEvents() = 0')
    e('      If CLeft > 0')
    e('        CLeft = 0')
    e('      EndIf')
    goto('Done')
    e('    EndIf')
    e('    If Halted')
    goto('Done')
    e('    EndIf')
    e('  EndIf')
    e('  If CLeft <= 0')
    goto('Done')
    e('  EndIf')
    e('  M68kRemap()')
    e('  If SrHi & $8000')
    e('    TracePend = 1')
    e('    PEnd = 0')
    e('  EndIf')
    dispatch_now()
    e('')
    G.emit_tables()
    emit_handlers()
    emit_exception_labels()
    e('')
    label('Done')
    e('  M68kCycles = M68kCycles + Budget - CLeft')
    e('  ProcedureReturn Budget - CLeft')
    e('EndProcedure')
    finish_tables()

def emit_pm_tail_macro():
    e('Macro NextOp()')
    e('  CompilerIf #M68K_ASM_TAIL = 1')
    e('    ASM Uses CLeft, PIP, PEnd')
    e('      cmp r6, #0')
    e('      ble __ul_m68krun_done')
    e('      cmp r4, r11')
    e('      bhs __ul_m68krun_resync')
    if G.PTRACE:
        e('      bl m68ktracecheck')
    e('      ldrh r0, [r4]')
    e('      lsrs r0, r0, #6')
    e('      lsls r0, r0, #2')
    e('      ldr r1, =global_dispatch')
    e('      ldr r1, [r1, r0]')
    e('      bx r1')
    e('    EndASM')
    e('  CompilerElse')
    e('    If CLeft <= 0')
    e('      Goto Done')
    e('    EndIf')
    e('    If PIP >= PEnd')
    e('      Goto Resync')
    e('    EndIf')
    e('    Goto Dispatch(PeekU(PIP) >> 6)')
    e('  CompilerEndIf')
    e('EndMacro')
    e('')

def emit_exception_labels():
    e('')
    label('IllegalOp')
    e('  op = PeekU(PIP)')
    exc(4, PCNOW(), 34)
    label('LineA')
    exc(10, PCNOW(), 34)
    label('LineF')
    exc(11, PCNOW(), 34)
    label('PrivViol')
    exc(8, PCNOW(), 34)
    label('TakeExc')
    e(f'  M68kException(ExcVec, {U32("ExcPc")})')
    e('  CLeft = CLeft - ExcCyc')
    goto('Resync')
    e('; A data access at AeAddr faulted (AeCode: $10 read, 0 write).')
    label('AddrErr')
    e('  AePc = PIP - PBase + xo - 2')
    label('AddrErrP')
    e('  If SrHi & $2000')
    e('    x = 5')
    e('  Else')
    e('    x = 1')
    e('  EndIf')
    e(f'  M68kAddressError(AeAddr, {U32("AePc")}, (op << 16) | (op & $FFE0) | AeCode | x)')
    e('  CLeft = CLeft - 50 + AeBack')
    goto('Resync')
    e('; A jump to an odd address: the fetch at AeAddr faults, AePc is pushed.')
    label('JumpErr')
    e('  If SrHi & $2000')
    e('    x = $1E')
    e('  Else')
    e('    x = $1A')
    e('  EndIf')
    e(f'  M68kAddressError(AeAddr, {U32("AePc")}, (op << 16) | (op & $FFE0) | x)')
    e('  CLeft = CLeft - 50 + AeBack')
    goto('Resync')

def finish_tables():
    """Emit the label tables: PureMetal fills arrays once; the PC gets static C arrays."""
    handlers = sorted(set(G.DISPATCH))
    if DESK():
        c = []
        def table(name, labels):
            c.append(f'  ! static void *{name}[{len(labels)}] = {{')
            for i in range(0, len(labels), 8):
                c.append('  !   ' + ', '.join('&&' + lab(l) for l in labels[i:i + 8]) + ',')
            c.append('  ! };')
        table('m68k_dsp', G.DISPATCH)
        for t, names in G.TABLES.items():
            table('m68k_' + t.lower(), names)
        c.append('  ! static void *m68k_earet;')
        idx = G.OUT.index('  ; @@C_TABLES@@')
        G.OUT[idx:idx + 1] = c
        return
    # PureMetal: a macro used once inside M68kRun fills the label arrays.
    m = ['Macro InitDispatch()']
    by = {}
    for i, h in enumerate(G.DISPATCH):
        by.setdefault(h, []).append(i)
    for h in sorted(by):
        idxs = by[h]
        i = 0
        while i < len(idxs):
            # longest run with a constant stride starting at idxs[i]
            j = i + 1
            if j < len(idxs):
                stride = idxs[j] - idxs[i]
                while j + 1 < len(idxs) and idxs[j + 1] - idxs[j] == stride:
                    j += 1
            n = j - i + 1 if j < len(idxs) else 1
            if n >= 3:
                stride = idxs[i + 1] - idxs[i]
                m.append(f'  For InitIndex = {idxs[i]} To {idxs[i + n - 1]} Step {stride}')
                m.append(f'    Dispatch(InitIndex) = ?{h}')
                m.append('  Next')
                i += n
            else:
                m.append(f'  Dispatch({idxs[i]}) = ?{h}')
                i += 1
    for t, names in G.TABLES.items():
        for k, l in enumerate(names):
            m.append(f'  {t}({k}) = ?{l}')
    m.append('EndMacro')
    m.append('')
    idx = G.OUT.index('; ------------------------------------------------------------ the interpreter')
    G.OUT[idx:idx] = m

# ---------------------------------------------------------------- handlers
def emit_handlers():
    emit_move()
    emit_line0()
    emit_line4()
    emit_line5()
    emit_bcc()
    emit_moveq()
    emit_alu_lines()
    emit_shifts()
    slots(lambda i: (i >> 6) == 0xA, 'LineA')
    slots(lambda i: (i >> 6) == 0xF, 'LineF')

def emit_cyc_tables():
    """EaCtlCyc(kind * 64 + ea): LEA 0, PEA 1, JMP 2, JSR 3, MOVEM r->m 4, MOVEM m->r 5."""
    kinds = [
        {2: 4, 5: 8, 6: 12, 70: 8, 71: 12, 72: 8, 73: 12},          # LEA
        {2: 12, 5: 16, 6: 20, 70: 16, 71: 20, 72: 16, 73: 20},      # PEA
        {2: 8, 5: 10, 6: 14, 70: 10, 71: 12, 72: 10, 73: 14},       # JMP
        {2: 16, 5: 18, 6: 22, 70: 18, 71: 20, 72: 18, 73: 22},      # JSR
        {2: 8, 4: 8, 5: 12, 6: 14, 70: 12, 71: 16},                 # MOVEM regs -> memory
        {2: 12, 3: 12, 5: 16, 6: 18, 70: 16, 71: 20, 72: 16, 73: 18},  # MOVEM memory -> regs
    ]
    G.CYC_INIT = []
    for k, tbl in enumerate(kinds):
        for idx in range(64):
            key = G.ea_key(idx)
            if key in tbl:
                G.CYC_INIT.append((k * 64 + idx, tbl[key]))

def ctl_cyc(kind):
    charge(f'EaCtlCyc({kind * 64} + (op & 63))')

# ---------------------------------------------------------------- MOVE
MOVE_DST_BW = {2: 4, 3: 4, 4: 4, 5: 8, 6: 10, 70: 8, 71: 12}
MOVE_DST_L = {2: 8, 3: 8, 4: 8, 5: 12, 6: 14, 70: 12, 71: 16}

def emit_move():
    for line, s in ((1, 'B'), (3, 'W'), (2, 'L')):
        for dm in range(8):
            if dm == 1 and s == 'B':
                continue
            subs = [(dm, None)] if dm != 7 else [(7, 0), (7, 1)]
            for dmode, dr in subs:
                name = f'Move{s}{dmode}' + ('' if dr is None else str(dr))
                if dr is None:
                    for r in range(8):
                        slot((line << 6) | (r << 3) | dmode, name)
                else:
                    slot((line << 6) | (dr << 3) | 7, name)
                handler(name)
                src(s)
                key = dmode if dmode != 7 else 70 + dr
                if dmode == 0:
                    set_dreg(OPR9(), s, 'vs')
                    flags_logic(s, 'vs')
                    charge(4)
                    tail()
                    continue
                if dmode == 1:
                    if s == 'W':
                        e(f'  Reg(8 + ((op >> 9) & 7)) = {SX16("vs")}')
                    else:
                        e('  Reg(8 + ((op >> 9) & 7)) = vs')
                    charge(4)
                    tail()
                    continue
                inc = INC[s]
                e('  rg = 8 + ((op >> 9) & 7)')
                if dmode == 2:
                    e('  ea = Reg(rg)')
                elif dmode == 3:
                    e('  ea = Reg(rg)')
                elif dmode == 4:
                    if s == 'B':
                        e('  If rg = 15')
                        e('    ea = Reg(rg) - 2')
                        e('  Else')
                        e('    ea = Reg(rg) - 1')
                        e('  EndIf')
                    else:
                        e(f'  ea = Reg(rg) - {inc}')
                    e('  Reg(rg) = ea')
                elif dmode == 5:
                    e('  ea = Reg(rg) + PeekW(PIP + xo)')
                    e('  xo = xo + 2')
                elif dmode == 6:
                    index_ea('Reg(rg)')
                elif dr == 0:
                    ext_w('ea')
                else:
                    ext_l('ea')
                err = newlab('ME')
                wr(s, 'vs', err=err)
                flags_logic(s, 'vs')
                if dmode == 3:
                    if s == 'B':
                        e('  If rg = 15')
                        e('    Reg(rg) = ea + 2')
                        e('  Else')
                        e('    Reg(rg) = ea + 1')
                        e('  EndIf')
                    else:
                        e(f'  Reg(rg) = ea + {inc}')
                charge(4 + (MOVE_DST_L if s == 'L' else MOVE_DST_BW)[key])
                tail()
                move_fault(err, s, dmode, dr)

def move_fault(err, s, dmode, dr):
    """A MOVE whose write faulted: the flags, register and pushed PC the 68000
    leaves depend on the destination mode and on when it prefetches."""
    label(err)
    T = IW() - 1
    srcmem = '(op & $38) >= $10 And (op & 63) <> $3C'
    e('  AePc = PIP - PBase + xo - 2')
    key = dmode if dmode != 7 else 70 + dr
    extra = ({2: 8, 3: 8, 4: 12, 5: 12, 6: 14, 70: 12} if s == 'L' else
             {2: 4, 3: 4, 4: 6, 5: 8, 6: 10, 70: 8}).get(key)
    if extra is not None:
        charge(extra)
    else:
        e(f'  If {srcmem}')
        charge(12 if s == 'L' else 8)
        e('  Else')
        charge(16 if s == 'L' else 12)
        e('  EndIf')
    def full():
        flags_logic(s, 'vs')
    def word():
        e(f'  FN = ((vs >> 15) & 1) << {T}')
        e('  FZ = vs & $FFFF')
        clr_vc()
    if s == 'L':
        # a long: N and Z from the whole value; -(An) has moved by 2 and the
        # low word (written first) is the faulting address
        if dmode == 4:
            e('  AePc = AePc + 2')
            e('  Reg(rg) = ea + 2')
            e('  AeAddr = ea + 2')
        elif dmode == 7 and dr == 1:
            e(f'  If {srcmem}')
            e('    AePc = AePc - 2')
            e('  EndIf')
        full()
    elif dmode in (2, 3):
        word()
    elif dmode == 4:
        e('  AePc = AePc + 2')
        e('  If (SrHi & $2000) = 0 And FC >= 0')
        e('    AeCode = AeCode | 8')
        e('  EndIf')
        charge(2)
        full()
    elif dmode in (5, 6) or dr == 0:
        full()
    else:
        e(f'  If {srcmem}')
        e('    AePc = AePc - 2')
        word()
        e('  Else')
        full()
        e('  EndIf')
    goto('AddrErrP')

# ---------------------------------------------------------------- line 0
def emit_line0():
    ops = {0: 'ORI', 1: 'ANDI', 2: 'SUBI', 3: 'ADDI', 5: 'EORI', 6: 'CMPI'}
    for k, nm in ops.items():
        for si, s in enumerate(SIZES):
            name = f'{nm}{s}'
            slot((k << 3) | si, name)   # slot = 0000 kkk 0 ss
            emit_imm_op(name, nm, s)
    # static bit operations: 0000 1000 tt
    for tt, nm in enumerate(('BTST', 'BCHG', 'BCLR', 'BSET')):
        name = f'{nm}I'
        slot((4 << 3) | tt, name)
        emit_bitop(name, nm, static=True)
    # dynamic bit operations and MOVEP: 0000 rrr 1 tt
    for tt, nm in enumerate(('BTST', 'BCHG', 'BCLR', 'BSET')):
        name = f'{nm}D'
        for r in range(8):
            slot((r << 3) | 4 | tt, name)
        emit_bitop(name, nm, static=False)

def emit_imm_op(name, nm, s):
    handler(name)
    if nm in ('ORI', 'ANDI', 'EORI') and s in ('B', 'W'):
        e('  If (op & 63) = $3C')
        goto(f'{nm}{"CCR" if s == "B" else "SR"}')
        e('  EndIf')
    if s == 'B':
        e('  vs = PeekA(PIP + 2)')
        e('  xo = 4')
    elif s == 'W':
        e('  vs = PeekU(PIP + 2)')
        e('  xo = 4')
    else:
        e('  vs = (PeekU(PIP + 2) << 16) | PeekU(PIP + 4)')
        e('  xo = 6')
    mem = newlab('M')
    e('  If (op & $38) <> 0')
    goto(mem)
    e('  EndIf')
    e(f'  vd = {dreg(OPR(), s)}')
    alu_body(nm, s)
    if nm != 'CMPI':
        set_dreg(OPR(), s, 'vr')
    if nm == 'CMPI':
        charge(14 if s == 'L' else 8)
    else:
        charge(16 if s == 'L' else 8)
    tail()
    label(mem)
    charge(8 if s == 'L' else 4)
    alt(s)
    rd(s, 'vd')
    alu_body(nm, s)
    if nm != 'CMPI':
        wr(s, 'vr')
        charge(12 if s == 'L' else 8)
    else:
        charge(4)
    tail()
    if nm in ('ORI', 'ANDI', 'EORI') and s in ('B', 'W'):
        emit_ccr_sr_op(nm, s)

def alu_body(nm, s):
    """vr = vd <op> vs with flags."""
    if nm in ('ORI', 'OR'):
        e('  vr = vd | vs')
        flags_logic(s, 'vr')
    elif nm in ('ANDI', 'AND'):
        e('  vr = vd & vs')
        flags_logic(s, 'vr')
    elif nm in ('EORI', 'EOR'):
        e('  vr = vd ! vs')
        flags_logic(s, 'vr')
    elif nm in ('ADDI', 'ADD', 'ADDQ'):
        e('  vr = vd + vs')
        flags_add(s)
    elif nm in ('SUBI', 'SUB', 'SUBQ'):
        e('  vr = vd - vs')
        flags_sub(s)
    elif nm in ('CMPI', 'CMP'):
        e('  vr = vd - vs')
        flags_sub(s, x=False)
    else:
        raise ValueError(nm)

def emit_ccr_sr_op(nm, s):
    name = f'{nm}{"CCR" if s == "B" else "SR"}'
    label(name)
    if s == 'W':
        need_super()
    e('  vs = PeekU(PIP + 2)')
    e('  x = M68kGetSR()')
    if s == 'B':
        e('  vs = (vs & $FF) | $FF00' if nm == 'ANDI' else '  vs = vs & $FF')
    if nm == 'ORI':
        e('  x = x | vs')
    elif nm == 'ANDI':
        e('  x = x & vs')
    else:
        e('  x = x ! vs')
    if s == 'B':
        e('  M68kSetCCR(x)')
    else:
        e('  M68kSetSR(x)')
    e('  xo = 4')
    charge(20)
    tail()

def emit_bitop(name, nm, static):
    handler(name)
    if static:
        e('  vs = PeekU(PIP + 2)')
        e('  xo = 4')
    else:
        mp = newlab('MOVEP')
        e('  If (op & $38) = 8')
        goto(mp)
        e('  EndIf')
        e(f'  vs = {dreg(OPR9(), "L")}')
    mem = newlab('M')
    e('  If (op & $38) <> 0')
    goto(mem)
    e('  EndIf')
    # Dn: long, bit number mod 32
    e('  x = vs & 31')
    e('  vd = Reg(op & 7)')
    e('  FZ = (vd >> x) & 1')
    if nm == 'BCHG':
        e('  Reg(op & 7) = vd ! (1 << x)')
    elif nm == 'BCLR':
        e('  Reg(op & 7) = vd & ~(1 << x)')
    elif nm == 'BSET':
        e('  Reg(op & 7) = vd | (1 << x)')
    base = {'BTST': 6, 'BCHG': 6, 'BCLR': 8, 'BSET': 6}[nm] + (4 if static else 0)
    charge(base)
    if nm != 'BTST':
        e('  If x > 15')
        charge(2)
        e('  EndIf')
    tail()
    label(mem)
    e('  x = vs & 7')
    if nm == 'BTST':
        if static:
            e('  If (op & 63) = $3C')
            goto('IllegalOp')
            e('  EndIf')
        ret = newlab('S')
        ea_call('SrcB', ret)
        label(ret)
        e('  FZ = (vs >> x) & 1')
        charge(4 + (4 if static else 0))
        if not static:
            e('  If (op & 63) = $3C')
            charge(2)
            e('  EndIf')
        tail()
    else:
        e('  y = vs')
        alt('B')
        rd('B', 'vd')
        e('  FZ = (vd >> (y & 7)) & 1')
        if nm == 'BCHG':
            e('  vr = vd ! (1 << (y & 7))')
        elif nm == 'BCLR':
            e('  vr = vd & ~(1 << (y & 7))')
        else:
            e('  vr = vd | (1 << (y & 7))')
        wr('B', 'vr')
        charge(8 + (4 if static else 0))
        tail()
    if not static:
        emit_movep(mp, nm)

def emit_movep(lbl, nm):
    """MOVEP in the dynamic bit-op slots: 0000 rrr 1 tt 001 aaa."""
    label(lbl)
    e('  ea = Reg(8 + (op & 7)) + PeekW(PIP + 2)')
    e('  xo = 4')
    e('  rg = (op >> 9) & 7')
    if nm == 'BTST':     # MOVEP.W (d16,Ay),Dx
        rd('B', 'x', 'ea')
        e('  ea = ea + 2')
        rd('B', 'y', 'ea')
        set_dreg('rg', 'W', '(x << 8) | y')
        charge(16)
    elif nm == 'BCHG':   # MOVEP.L (d16,Ay),Dx
        rd('B', 'x', 'ea')
        e('  ea = ea + 2')
        rd('B', 'y', 'ea')
        e('  vr = (x << 8) | y')
        e('  ea = ea + 2')
        rd('B', 'x', 'ea')
        e('  ea = ea + 2')
        rd('B', 'y', 'ea')
        e('  Reg(rg) = (vr << 16) | (x << 8) | y')
        charge(24)
    elif nm == 'BCLR':   # MOVEP.W Dx,(d16,Ay)
        e('  vs = Reg(rg)')
        wr('B', 'vs >> 8', 'ea')
        e('  ea = ea + 2')
        wr('B', 'vs', 'ea')
        charge(16)
    else:                # MOVEP.L Dx,(d16,Ay)
        e('  vs = Reg(rg)')
        wr('B', 'vs >> 24', 'ea')
        e('  ea = ea + 2')
        wr('B', 'vs >> 16', 'ea')
        e('  ea = ea + 2')
        wr('B', 'vs >> 8', 'ea')
        e('  ea = ea + 2')
        wr('B', 'vs', 'ea')
        charge(24)
    tail()

# ---------------------------------------------------------------- line 4
def emit_line4():
    L4 = 4 << 6
    # NEGX / CLR / NEG / NOT  (0100 0kk0 ss), MOVE from SR / to CCR / to SR in ss = 11
    for k, nm in enumerate(('NEGX', 'CLR', 'NEG', 'NOT')):
        for si, s in enumerate(SIZES):
            name = f'{nm}{s}'
            slot(L4 | (k << 3) | si, name)  # bits 11-8 = 0kk0 -> slot bits 5-2
            emit_unary(name, nm, s)
    slot(L4 | (0 << 3) | 3, 'MoveFromSR')
    emit_move_from_sr()
    slot(L4 | (2 << 3) | 3, 'MoveToCCR')
    emit_move_to_ccr_sr('MoveToCCR', False)
    slot(L4 | (3 << 3) | 3, 'MoveToSR')
    emit_move_to_ccr_sr('MoveToSR', True)
    # 0100 1000 00: NBCD; 01: SWAP/PEA; 10: EXT.W/MOVEM.W r->m; 11: EXT.L/MOVEM.L r->m
    slot(L4 | 0x20 | 0, 'NBCD')
    emit_nbcd()
    slot(L4 | 0x20 | 1, 'SwapPea')
    emit_swap_pea()
    slot(L4 | 0x20 | 2, 'ExtWMovemW')
    emit_ext_movem('ExtWMovemW', 'W')
    slot(L4 | 0x20 | 3, 'ExtLMovemL')
    emit_ext_movem('ExtLMovemL', 'L')
    # 0100 1010 ss: TST, 11: TAS / ILLEGAL
    for si, s in enumerate(SIZES):
        slot(L4 | 0x28 | si, f'TST{s}')
        emit_tst(f'TST{s}', s)
    slot(L4 | 0x28 | 3, 'TAS')
    emit_tas()
    # 0100 1100 1s: MOVEM memory -> registers
    slot(L4 | 0x30 | 2, 'MovemMW')
    emit_movem_m2r('MovemMW', 'W')
    slot(L4 | 0x30 | 3, 'MovemML')
    emit_movem_m2r('MovemML', 'L')
    # 0100 1110 01: TRAP, LINK, UNLK, MOVE USP, RESET ... RTR
    slot(L4 | 0x38 | 1, 'Misc4E')
    emit_misc4e()
    slot(L4 | 0x38 | 2, 'JSR')
    emit_jsr_jmp('JSR', True)
    slot(L4 | 0x38 | 3, 'JMP')
    emit_jsr_jmp('JMP', False)
    # 0100 rrr 110: CHK.W, 0100 rrr 111: LEA
    for r in range(8):
        slot(L4 | (r << 3) | 6, 'CHK')
        slot(L4 | (r << 3) | 7, 'LEA')
    emit_chk()
    emit_lea()

def emit_unary(name, nm, s):
    handler(name)
    mem = newlab('M')
    e('  If (op & $38) <> 0')
    goto(mem)
    e('  EndIf')
    e(f'  vd = {dreg(OPR(), s)}')
    unary_body(nm, s)
    set_dreg(OPR(), s, 'vr')
    charge(6 if s == 'L' else 4)
    tail()
    label(mem)
    alt(s)
    rd(s, 'vd')
    unary_body(nm, s)
    wr(s, 'vr')
    charge(12 if s == 'L' else 8)
    tail()

def unary_body(nm, s):
    if nm == 'CLR':
        e('  vr = 0')
        e('  FZ = 0')
        e('  FN = 0')
        clr_vc()
    elif nm == 'NOT':
        e('  vr = ~vd')
        flags_logic(s, 'vr')
    elif nm == 'NEG':
        e('  vs = vd')
        e('  vd = 0')
        e('  vr = 0 - vs')
        flags_sub(s)
    else:   # NEGX
        e('  vs = vd')
        e('  vd = 0')
        e(f'  vr = 0 - vs - {XBIT()}')
        flags_sub(s, zsticky=True)

def emit_move_from_sr():
    handler('MoveFromSR')
    mem = newlab('M')
    e('  If (op & $38) <> 0')
    goto(mem)
    e('  EndIf')
    set_dreg(OPR(), 'W', 'M68kGetSR()')
    charge(6)
    tail()
    label(mem)
    alt('W')
    rd('W', 'vd')
    e('  vr = M68kGetSR()')
    wr('W', 'vr')
    charge(8)
    tail()

def emit_move_to_ccr_sr(name, sr):
    handler(name)
    if sr:
        need_super()
    src('W', an_ok=False)
    if sr:
        e('  M68kSetSR(vs)')
    else:
        e('  M68kSetCCR(vs)')
    charge(12)
    tail()

def emit_nbcd():
    handler('NBCD')
    mem = newlab('M')
    e('  If (op & $38) <> 0')
    goto(mem)
    e('  EndIf')
    e(f'  vs = {dreg(OPR(), "B")}')
    e('  vd = 0')
    bcd_sub()
    set_dreg(OPR(), 'B', 'vr')
    charge(6)
    tail()
    label(mem)
    alt('B')
    rd('B', 'vs')
    e('  vd = 0')
    bcd_sub()
    wr('B', 'vr')
    charge(8)
    tail()

def bcd_add():
    """vr = vd + vs + X in BCD (bytes), flags as the 68000 leaves them."""
    T = IW() - 1
    e(f'  x = (vs & 15) + (vd & 15) + {XBIT()}')
    e('  y = (vs & $F0) + (vd & $F0)')
    e('  vr = x + y')
    e('  u = vr')
    e('  If x > 9')
    e('    vr = vr + 6')
    e('  EndIf')
    e('  If (vr & $3F0) > $90')
    e('    vr = vr + $60')
    e(f'    FX = 1 << {T}')
    e('  Else')
    e('    FX = 0')
    e('  EndIf')
    e('  FC = FX')
    e(f'  FV = ((~u & vr) & $80) << {IW() - 8}')
    e(f'  FN = (vr & $80) << {IW() - 8}')
    e('  FZ = FZ | (vr & $FF)')

def bcd_sub():
    """vr = vd - vs - X in BCD (bytes)."""
    T = IW() - 1
    e(f'  x = (vd & 15) - (vs & 15) - {XBIT()}')
    e('  y = (vd & $F0) - (vs & $F0)')
    e('  vr = x + y')
    e('  u = vr')
    e('  If x & $F0')
    e('    vr = vr - 6')
    e(f'    t = Bool(((vd - vs - 6 - {XBIT()}) & $300) > $FF)')
    e('  Else')
    e(f'    t = Bool(((vd - vs - {XBIT()}) & $300) > $FF)')
    e('  EndIf')
    e(f'  If ((vd - vs - t) & $100) > $FF')
    e('    vr = vr - $60')
    e('  EndIf')
    e(f'  FX = t << {T}')
    e('  FC = FX')
    e(f'  FV = ((u & ~vr) & $80) << {IW() - 8}')
    e(f'  FN = (vr & $80) << {IW() - 8}')
    e('  FZ = FZ | (vr & $FF)')

def emit_swap_pea():
    handler('SwapPea')
    pea = newlab('PEA')
    e('  If (op & $38) <> 0')
    goto(pea)
    e('  EndIf')
    e('  vd = Reg(op & 7)')
    e(f'  vr = (vd << 16) | ((vd >> 16) & $FFFF)')
    e('  Reg(op & 7) = vr')
    flags_logic('L', 'vr')
    charge(4)
    tail()
    label(pea)
    ctl()
    e('  vs = ea')
    e('  ea = Reg(15) - 4')
    wr('L', 'vs')
    e('  Reg(15) = ea')
    ctl_cyc(1)
    tail()

def emit_ext_movem(name, s):
    handler(name)
    mm = newlab('MOVEM')
    e('  If (op & $38) <> 0')
    goto(mm)
    e('  EndIf')
    if s == 'W':
        e(f'  vr = {SX8(dreg(OPR(), "B"))}')
        set_dreg(OPR(), 'W', 'vr')
        flags_logic('W', 'vr')
    else:
        e(f'  vr = {SX16(dreg(OPR(), "W"))}')
        e('  Reg(op & 7) = vr')
        flags_logic('L', 'vr')
    charge(4)
    tail()
    label(mm)
    emit_movem_r2m(s)

def emit_movem_r2m(s):
    """MOVEM registers -> memory; the mask is the first extension word."""
    k = INC[s]
    e('  vs = PeekU(PIP + 2)')
    e('  xo = 4')
    pre = newlab('PRE')
    e('  If (op & $38) = $20')
    goto(pre)
    e('  EndIf')
    e('  If (op & $38) = $18')
    goto('IllegalOp')
    e('  EndIf')
    ctl()
    e('  If (op & 63) >= $3A')
    goto('IllegalOp')
    e('  EndIf')
    e('  If (ea & 1) And vs <> 0')
    e('    AeAddr = ea')
    e(f'    AeBack = 4 - EaCtlCyc({4 * 64} + (op & 63))')
    e('    AeCode = 0')
    goto('AddrErr')
    e('  EndIf')
    e('  For rg = 0 To 15')
    e('    If vs & (1 << rg)')
    e('      vr = Reg(rg)')
    wr(s, 'vr')
    e(f'      ea = ea + {k}')
    charge(4 if s == 'W' else 8)
    e('    EndIf')
    e('  Next')
    ctl_cyc(4)
    tail()
    label(pre)
    # -(An): mask bit 0 = A7 ... bit 15 = D0; registers stored from A7 down.
    e('  ea = Reg(8 + (op & 7))')
    e('  y = ea')
    e('  If (ea & 1) And vs <> 0')
    e('    AeAddr = ea - 2')
    e(f'    AeBack = 4 - EaCtlCyc({4 * 64} + (op & 63))')
    e('    AeCode = 0')
    goto('AddrErr')
    e('  EndIf')
    e('  For rg = 15 To 0 Step -1')
    e('    If vs & (1 << (15 - rg))')
    e(f'      ea = ea - {k}')
    e('      vr = Reg(rg)')
    e('      If rg = 8 + (op & 7)')
    e('        vr = y')
    e('      EndIf')
    wr(s, 'vr')
    charge(4 if s == 'W' else 8)
    e('    EndIf')
    e('  Next')
    e('  Reg(8 + (op & 7)) = ea')
    ctl_cyc(4)
    tail()

def emit_movem_m2r(name, s):
    handler(name)
    k = INC[s]
    e('  vs = PeekU(PIP + 2)')
    e('  xo = 4')
    post = newlab('POST')
    e('  If (op & $38) = $18')
    goto(post)
    e('  EndIf')
    e('  If (op & $38) = $20')
    goto('IllegalOp')
    e('  EndIf')
    ctl()
    loop = newlab('LOOP')
    label(loop)
    e('  If (ea & 1) And vs <> 0')
    e('    AeAddr = ea')
    e(f'    AeBack = 8 - EaCtlCyc({5 * 64} + (op & 63))')
    e('    AeCode = $10')
    e('    If (op & $38) = $18')
    e('      Reg(8 + (op & 7)) = ea + 2')
    e('    EndIf')
    goto('AddrErr')
    e('  EndIf')
    e('  For rg = 0 To 15')
    e('    If vs & (1 << rg)')
    rd(s, 'vr')
    if s == 'W':
        e(f'      Reg(rg) = {SX16("vr")}')
    else:
        e('      Reg(rg) = vr')
    e(f'      ea = ea + {k}')
    charge(4 if s == 'W' else 8)
    e('    EndIf')
    e('  Next')
    e('  If (op & $38) = $18')
    e('    Reg(8 + (op & 7)) = ea')
    e('  EndIf')
    rd('W', 'vr')
    ctl_cyc(5)
    tail()
    label(post)
    e('  ea = Reg(8 + (op & 7))')
    goto(loop)

def emit_tst(name, s):
    handler(name)
    e('  If (op & 63) >= $3A')
    goto('IllegalOp')
    e('  EndIf')
    src(s, an_ok=False)
    flags_logic(s, 'vs')
    charge(4)
    tail()

def emit_tas():
    handler('TAS')
    e('  If op = $4AFC')
    goto('IllegalOp')
    e('  EndIf')
    mem = newlab('M')
    e('  If (op & $38) <> 0')
    goto(mem)
    e('  EndIf')
    e(f'  vd = {dreg(OPR(), "B")}')
    flags_logic('B', 'vd')
    set_dreg(OPR(), 'B', 'vd | $80')
    charge(4)
    tail()
    label(mem)
    alt('B')
    rd('B', 'vd')
    flags_logic('B', 'vd')
    wr('B', 'vd | $80')
    charge(10)
    tail()

def emit_misc4e():
    """0100 1110 01 xxxxxx: TRAP, LINK, UNLK, MOVE USP, RESET, NOP, STOP, RTE, RTS, TRAPV, RTR."""
    handler('Misc4E')
    sub = {0: 'TRAP', 1: 'TRAP', 2: 'LINK', 3: 'UNLK', 4: 'MoveToUsp', 5: 'MoveFromUsp'}
    e('  x = (op >> 3) & 7')
    for k, nm in sub.items():
        e(f'  If x = {k}')
        goto(f'Op{nm}')
        e('  EndIf')
    for k, nm in ((0x70, 'RESET'), (0x71, 'NOP'), (0x72, 'STOP'), (0x73, 'RTE'),
                  (0x75, 'RTS'), (0x76, 'TRAPV'), (0x77, 'RTR')):
        e(f'  If op = $4E{k:02X}')
        goto(f'Op{nm}')
        e('  EndIf')
    goto('IllegalOp')
    label('OpTRAP')
    exc('32 + (op & 15)', f'{PCNOW()} + 2', 34)
    label('OpLINK')
    e('  rg = 8 + (op & 7)')
    e('  vs = Reg(rg)')
    e('  ea = Reg(15) - 4')
    e('  If rg = 15')
    e('    vs = ea')
    e('  EndIf')
    wr('L', 'vs')
    e('  Reg(15) = ea')
    e('  Reg(rg) = ea')
    e('  Reg(15) = Reg(15) + PeekW(PIP + 2)')
    e('  xo = 4')
    charge(16)
    tail()
    label('OpUNLK')
    e('  ea = Reg(8 + (op & 7))')
    rd('L', 'vr')
    e('  Reg(15) = ea + 4')
    e('  Reg(8 + (op & 7)) = vr')
    charge(12)
    tail()
    label('OpMoveToUsp')
    need_super()
    e('  USP = Reg(8 + (op & 7))')
    charge(4)
    tail()
    label('OpMoveFromUsp')
    need_super()
    e('  Reg(8 + (op & 7)) = USP')
    charge(4)
    tail()
    label('OpRESET')
    need_super()
    e('  M68kResetHook()')
    charge(132)
    tail()
    label('OpNOP')
    charge(4)
    tail()
    label('OpSTOP')
    need_super()
    e('  M68kSetSR(PeekU(PIP + 2))')
    e('  Stopped = 1')
    e('  PIP = PIP + 4')
    charge(4)
    goto('Resync')
    label('OpRTE')
    need_super()
    e('  ea = Reg(15)')
    rd('W', 'vs')
    e('  ea = ea + 2')
    rd('L', 'vd')
    e('  Reg(15) = ea + 4')
    e('  M68kSetSR(vs)')
    e('  PBase = 0')
    e(f'  PIP = {U32("vd")}')
    e('  PEnd = 0')
    e('  If vd & 1')
    e('    AeAddr = vd')
    e('    AePc = vd - 4')
    e('    AeBack = -12')
    goto('JumpErr')
    e('  EndIf')
    charge(20)
    goto('Resync')
    label('OpRTS')
    e('  ea = Reg(15)')
    rd('L', 'vd')
    e('  Reg(15) = ea + 4')
    e(f'  vd = {U32("vd")}')
    jump_to('vd', 16)
    charge(16)
    next_op()
    label('OpTRAPV')
    e('  If FV < 0')
    exc(7, f'{PCNOW()} + 2', 34)
    e('  EndIf')
    charge(4)
    tail()
    label('OpRTR')
    e('  ea = Reg(15)')
    rd('W', 'vs')
    e('  ea = ea + 2')
    rd('L', 'vd')
    e('  Reg(15) = ea + 4')
    e('  M68kSetCCR(vs)')
    e(f'  vd = {U32("vd")}')
    jump_to('vd', 20)
    charge(20)
    next_op()

def emit_jsr_jmp(name, jsr):
    handler(name)
    ctl()
    e(f'  vd = {U32("ea")}')
    cyc = f'EaCtlCyc({(3 if jsr else 2) * 64} + (op & 63))'
    if jsr:
        e('  If vd & 1')
        e('    AeAddr = vd')
        e('    AePc = vd - 4')
        e(f'    AeBack = 16 - ({cyc})')
        goto('JumpErr')
        e('  EndIf')
        e(f'  vs = {PCX()}')
        e('  ea = Reg(15) - 4')
        wr('L', 'vs')
        e('  Reg(15) = ea')
    jump_to('vd', cyc)
    ctl_cyc(3 if jsr else 2)
    next_op()

def emit_chk():
    handler('CHK')
    src('W', data_only=True)
    e(f'  vd = {SX16(dreg(OPR9(), "W"))}')
    e(f'  vs = {SX16("vs")}')
    e('  FZ = vd & $FFFF')
    clr_vc()
    e('  If vd < 0')
    e(f'    FN = {TOP()}')
    e('    If vd > vs')
    exc(6, PCX(), 38)
    e('    EndIf')
    exc(6, PCX(), 40)
    e('  EndIf')
    e('  If vd > vs')
    e('    FN = 0')
    exc(6, PCX(), 38)
    e('  EndIf')
    charge(10)
    tail()

def emit_lea():
    handler('LEA')
    ctl()
    e('  Reg(8 + ((op >> 9) & 7)) = ea')
    ctl_cyc(0)
    tail()

# ---------------------------------------------------------------- line 5
def emit_line5():
    L5 = 5 << 6
    for q in range(8):
        for si, s in enumerate(SIZES):
            slot(L5 | (q << 3) | si, f'ADDQ{s}')
            slot(L5 | (q << 3) | 4 | si, f'SUBQ{s}')
    for s in SIZES:
        emit_addq(f'ADDQ{s}', 'ADDQ', s)
        emit_addq(f'SUBQ{s}', 'SUBQ', s)
    for cc in range(16):
        name = f'S{CCNAME[cc]}'
        slot(L5 | ((cc >> 1) << 3) | ((cc & 1) << 2) | 3, name)
        emit_scc(name, cc)

def emit_addq(name, nm, s):
    handler(name)
    e('  vs = (op >> 9) & 7')
    e('  If vs = 0')
    e('    vs = 8')
    e('  EndIf')
    mem = newlab('M')
    an = newlab('AN')
    e('  If (op & $38) <> 0')
    e('    If (op & $38) = 8')
    goto(an)
    e('    EndIf')
    goto(mem)
    e('  EndIf')
    e(f'  vd = {dreg(OPR(), s)}')
    alu_body(nm, s)
    set_dreg(OPR(), s, 'vr')
    charge(8 if s == 'L' else 4)
    tail()
    label(an)
    if s == 'B':
        goto('IllegalOp')
    else:
        op = '+' if nm == 'ADDQ' else '-'
        e(f'  Reg(8 + (op & 7)) = Reg(8 + (op & 7)) {op} vs')
        charge(8)
        tail()
    label(mem)
    alt(s)
    rd(s, 'vd')
    alu_body(nm, s)
    wr(s, 'vr')
    charge(12 if s == 'L' else 8)
    tail()

def emit_scc(name, cc):
    handler(name)
    db = newlab('DB')
    mem = newlab('M')
    e('  If (op & $38) <> 0')
    e('    If (op & $38) = 8')
    goto(db)
    e('    EndIf')
    goto(mem)
    e('  EndIf')
    cond_set('vr', cc)
    set_dreg(OPR(), 'B', 'vr')
    charge(4)
    e('  If vr')
    charge(2)
    e('  EndIf')
    tail()
    label(mem)
    alt('B')
    rd('B', 'vd')
    cond_set('vr', cc)
    wr('B', 'vr')
    charge(8)
    tail()
    # DBcc Dn,disp
    label(db)
    if cc != 1:
        if cc == 0:
            e('  xo = 4')
            charge(12)
            tail()
            return
        e(f'  If {COND[cc]}')
        e('    xo = 4')
        charge(12)
        tail()
        e('  EndIf')
    e(f'  vd = {U32(PCNOW() + " + 2 + PeekW(PIP + 2)")}')
    e(f'  vr = {dreg(OPR(), "W")} - 1')
    set_dreg(OPR(), 'W', 'vr')
    e('  If (vr & $FFFF) <> $FFFF')
    jump_to('vd', 10)
    charge(10)
    next_op()
    e('  EndIf')
    e('  xo = 4')
    charge(14)
    tail()

def cond_set(dst, cc):
    if cc == 0:
        e(f'  {dst} = $FF')
    elif cc == 1:
        e(f'  {dst} = 0')
    else:
        e(f'  If {COND[cc]}')
        e(f'    {dst} = $FF')
        e('  Else')
        e(f'    {dst} = 0')
        e('  EndIf')

# ---------------------------------------------------------------- line 6
def emit_bcc():
    L6 = 6 << 6
    for cc in range(16):
        name = 'BRA' if cc == 0 else ('BSR' if cc == 1 else f'B{CCNAME[cc]}')
        for k in range(4):
            slot(L6 | (cc << 2) | k, name)
        handler(name)
        e('  vs = op & $FF')
        if cc >= 2:
            e(f'  If Not ({COND[cc]})')
            e('    If vs = 0')
            e('      xo = 4')
            charge(12)
            e('    Else')
            charge(8)
            e('    EndIf')
            tail()
            e('  EndIf')
        e('  If vs = 0')
        e(f'    vd = {PCNOW()} + 2 + PeekW(PIP + 2)')
        e('    xo = 4')
        e('  Else')
        e(f'    vd = {PCNOW()} + 2 + {SX8("vs")}')
        e('  EndIf')
        e(f'  vd = {U32("vd")}')
        if cc == 1:
            e(f'  vs = {PCX()}')
            e('  ea = Reg(15) - 4')
            wr('L', 'vs')
            e('  Reg(15) = ea')
            jump_to('vd', 18)
            charge(18)
        else:
            jump_to('vd', 10)
            charge(10)
        next_op()

# ---------------------------------------------------------------- line 7
def emit_moveq():
    for r in range(8):
        for k in range(4):
            slot((7 << 6) | (r << 3) | k, 'MOVEQ')
    handler('MOVEQ')
    e(f'  vr = {SX8("op & $FF")}')
    e('  Reg((op >> 9) & 7) = vr')
    flags_logic('L', 'vr')
    charge(4)
    e('  PIP = PIP + 2')
    next_op()

# ---------------------------------------------------------------- lines 8, 9, B, C, D
def emit_alu_lines():
    lines = {8: 'OR', 9: 'SUB', 0xB: 'CMP', 0xC: 'AND', 0xD: 'ADD'}
    for ln, nm in lines.items():
        for r in range(8):
            for om in range(8):
                sl = (ln << 6) | (r << 3) | om
                if om < 3:
                    slot(sl, f'{nm}{SIZES[om]}EaDn')
                elif om == 3:
                    slot(sl, {'OR': 'DIVU', 'SUB': 'SUBAW', 'CMP': 'CMPAW', 'AND': 'MULU', 'ADD': 'ADDAW'}[nm])
                elif om == 7:
                    slot(sl, {'OR': 'DIVS', 'SUB': 'SUBAL', 'CMP': 'CMPAL', 'AND': 'MULS', 'ADD': 'ADDAL'}[nm])
                else:
                    slot(sl, f'{nm}{SIZES[om - 4]}DnEa')
        for si, s in enumerate(SIZES):
            emit_ea_dn(f'{nm}{s}EaDn', nm, s)
            emit_dn_ea(f'{nm}{s}DnEa', nm, s)
    for nm in ('SUBA', 'CMPA', 'ADDA'):
        for s in ('W', 'L'):
            emit_adda(f'{nm}{s}', nm, s)
    emit_mul('MULU', False)
    emit_mul('MULS', True)
    emit_div('DIVU', False)
    emit_div('DIVS', True)

def emit_ea_dn(name, nm, s):
    handler(name)
    src(s, an_ok=nm in ('ADD', 'SUB', 'CMP'))
    e(f'  vd = {dreg(OPR9(), s)}')
    alu_body(nm, s)
    if nm != 'CMP':
        set_dreg(OPR9(), s, 'vr')
    if s == 'L':
        charge(6)
        if nm != 'CMP':
            e('  If (op & $30) = 0 Or (op & 63) = $3C')
            charge(2)
            e('  EndIf')
    else:
        charge(4)
    tail()

def emit_dn_ea(name, nm, s):
    handler(name)
    special = newlab('X')
    e('  If (op & $30) = 0')
    goto(special)
    e('  EndIf')
    alt(s)
    rd(s, 'vd')
    e(f'  vs = {dreg(OPR9(), s)}')
    alu_body('EOR' if nm == 'CMP' else nm, s)
    wr(s, 'vr')
    charge(12 if s == 'L' else 8)
    tail()
    label(special)
    # register modes: ADDX / SUBX / ABCD / SBCD / EXG / CMPM / EOR Dn,Dn
    if nm == 'CMP':
        cm = newlab('CMPM')
        e('  If (op & $38) = 8')
        goto(cm)
        e('  EndIf')
        e(f'  vs = {dreg(OPR9(), s)}')
        e(f'  vd = {dreg(OPR(), s)}')
        e('  vr = vd ! vs')
        flags_logic(s, 'vr')
        set_dreg(OPR(), s, 'vr')
        charge(8 if s == 'L' else 4)
        tail()
        label(cm)
        emit_cmpm(s)
    elif nm in ('ADD', 'SUB'):
        emit_addx(nm, s)
    elif nm == 'OR':
        if s == 'B':
            emit_bcd_rr('SBCD')
        else:
            goto('IllegalOp')
    elif nm == 'AND':
        if s == 'B':
            emit_bcd_rr('ABCD')
        elif s == 'W':
            ay = newlab('EXGA')
            e('  If (op & $38) = 8')
            goto(ay)
            e('  EndIf')
            e('  x = (op >> 9) & 7')
            e('  y = op & 7')
            e('  vs = Reg(x)')
            e('  Reg(x) = Reg(y)')
            e('  Reg(y) = vs')
            charge(6)
            tail()
            label(ay)
            e('  x = 8 + ((op >> 9) & 7)')
            e('  y = 8 + (op & 7)')
            e('  vs = Reg(x)')
            e('  Reg(x) = Reg(y)')
            e('  Reg(y) = vs')
            charge(6)
            tail()
        else:
            e('  If (op & $38) = 0')
            goto('IllegalOp')
            e('  EndIf')
            e('  x = (op >> 9) & 7')
            e('  y = 8 + (op & 7)')
            e('  vs = Reg(x)')
            e('  Reg(x) = Reg(y)')
            e('  Reg(y) = vs')
            charge(6)
            tail()

def predec(s, reg_expr, dst):
    """dst = An - size (A7 keeps word alignment for bytes); An = dst."""
    if s == 'B':
        e(f'  If {reg_expr} = 15')
        e(f'    {dst} = Reg({reg_expr}) - 2')
        e('  Else')
        e(f'    {dst} = Reg({reg_expr}) - 1')
        e('  EndIf')
    else:
        e(f'  {dst} = Reg({reg_expr}) - {INC[s]}')
    e(f'  Reg({reg_expr}) = {dst}')

def postinc(s, reg_expr):
    if s == 'B':
        e(f'  If {reg_expr} = 15')
        e(f'    Reg({reg_expr}) = ea + 2')
        e('  Else')
        e(f'    Reg({reg_expr}) = ea + 1')
        e('  EndIf')
    else:
        e(f'  Reg({reg_expr}) = ea + {INC[s]}')

def emit_addx(nm, s):
    mem = newlab('XM')
    e('  If (op & $38) = 8')
    goto(mem)
    e('  EndIf')
    e(f'  vs = {dreg(OPR(), s)}')
    e(f'  vd = {dreg(OPR9(), s)}')
    if nm == 'ADD':
        e(f'  vr = vd + vs + {XBIT()}')
        flags_add(s, zsticky=True)
    else:
        e(f'  vr = vd - vs - {XBIT()}')
        flags_sub(s, zsticky=True)
    set_dreg(OPR9(), s, 'vr')
    charge(8 if s == 'L' else 4)
    tail()
    label(mem)
    e('  x = 8 + (op & 7)')
    e('  y = 8 + ((op >> 9) & 7)')
    charge(2 if s == 'L' else 6)
    predec_long_first(s, 'x')
    rd(s, 'vs')
    charge(8 if s == 'L' else 4)
    predec_long_first(s, 'y')
    rd(s, 'vd')
    if nm == 'ADD':
        e(f'  vr = vd + vs + {XBIT()}')
        flags_add(s, zsticky=True)
    else:
        e(f'  vr = vd - vs - {XBIT()}')
        flags_sub(s, zsticky=True)
    wr(s, 'vr')
    charge(20 if s == 'L' else 8)
    tail()

def predec_long_first(s, reg):
    """-(An) for ADDX/SUBX: a long is read low word first, so an odd An faults
    after moving by 2."""
    if s != 'L':
        predec(s, reg, 'ea')
        return
    e(f'  ea = Reg({reg}) - 2')
    e('  If ea & 1')
    e(f'    Reg({reg}) = ea')
    e('    AeAddr = ea')
    e('    AeBack = 0')
    e('    AeCode = $10')
    goto('AddrErr')
    e('  EndIf')
    e('  ea = ea - 2')
    e(f'  Reg({reg}) = ea')

def emit_bcd_rr(nm):
    mem = newlab('BM')
    e('  If (op & $38) = 8')
    goto(mem)
    e('  EndIf')
    e(f'  vs = {dreg(OPR(), "B")}')
    e(f'  vd = {dreg(OPR9(), "B")}')
    bcd_add() if nm == 'ABCD' else bcd_sub()
    set_dreg(OPR9(), 'B', 'vr')
    charge(6)
    tail()
    label(mem)
    e('  x = 8 + (op & 7)')
    e('  y = 8 + ((op >> 9) & 7)')
    predec('B', 'x', 'ea')
    rd('B', 'vs')
    predec('B', 'y', 'ea')
    rd('B', 'vd')
    bcd_add() if nm == 'ABCD' else bcd_sub()
    wr('B', 'vr')
    charge(18)
    tail()

def emit_cmpm(s):
    e('  x = 8 + (op & 7)')
    e('  y = 8 + ((op >> 9) & 7)')
    e('  ea = Reg(x)')
    postinc(s, 'x')
    charge(8 if s == 'L' else 4)
    rd(s, 'vs')
    charge(8 if s == 'L' else 4)
    e('  ea = Reg(y)')
    postinc(s, 'y')
    rd(s, 'vd')
    e('  vr = vd - vs')
    flags_sub(s, x=False)
    charge(4)
    tail()

def emit_adda(name, nm, s):
    handler(name)
    src(s)
    if s == 'W':
        e(f'  vs = {SX16("vs")}')
    e('  rg = 8 + ((op >> 9) & 7)')
    if nm == 'ADDA':
        e('  Reg(rg) = Reg(rg) + vs')
    elif nm == 'SUBA':
        e('  Reg(rg) = Reg(rg) - vs')
    else:
        e('  vd = Reg(rg)')
        e('  vr = vd - vs')
        flags_sub('L', x=False)
    if nm == 'CMPA':
        charge(6)
    elif s == 'W':
        charge(8)
    else:
        charge(6)
        e('  If (op & $30) = 0 Or (op & 63) = $3C')
        charge(2)
        e('  EndIf')
    tail()

def emit_mul(name, signed):
    handler(name)
    src('W', data_only=True)
    if signed:
        e(f'  vr = {SX16(dreg(OPR9(), "W"))} * {SX16("vs")}')
        e('  x = ((vs << 1) ! vs) & $FFFF')
    else:
        e(f'  vr = {dreg(OPR9(), "W")} * vs')
        e('  x = vs')
    e('  Reg((op >> 9) & 7) = vr')
    flags_logic('L', 'vr')
    e('  y = 38')
    e('  While x')
    e('    y = y + ((x & 1) << 1)')
    e('    x = x >> 1')
    e('  Wend')
    charge('y')
    tail()

def emit_div(name, signed):
    handler(name)
    src('W', data_only=True)
    e(f'  If M68kDiv{"S" if signed else "U"}((op >> 9) & 7, vs)')
    exc(5, PCX(), 38)
    e('  EndIf')
    tail()

# ---------------------------------------------------------------- line E
def emit_shifts():
    LE = 0xE << 6
    for r in range(8):
        for d in range(2):
            for si, s in enumerate(SIZES):
                slot(LE | (r << 3) | (d << 2) | si, f'Sh{"LR"[d]}{s}')
    for t in range(4):
        for d in range(2):
            slot(LE | (t << 3) | (d << 2) | 3, f'ShM{t}{"LR"[d]}')
    for d in range(2):
        for s in SIZES:
            emit_shift_reg(f'Sh{"LR"[d]}{s}', d, s)
    for t in range(4):
        for d in range(2):
            emit_shift_mem(f'ShM{t}{"LR"[d]}', t, d)

def shift_core(t, d, s, cnt):
    """vr = vd shifted (type t: 0 AS, 1 LS, 2 ROX, 3 RO; d: 0 right, 1 left) by
    cnt (a local, 0..63), with flags. vd is zero-extended to the size."""
    w = BITS[s]
    T = IW() - 1
    m = MASK(s)
    def M(x):
        return x if (s == 'L' and IW() == 32) else f'({x}) & {m}'
    sext = SXS('vd', s)
    zero = newlab('Z')
    done = newlab('D')
    e(f'  If {cnt} = 0')
    goto(zero)
    e('  EndIf')
    if t == 0 and d == 1:      # ASL
        e(f'  If {cnt} < {w}')
        e(f'    vr = {M(f"vd << {cnt}")}')
        e(f'    FC = ((vd >> ({w} - {cnt})) & 1) << {T}')
        # V: the top cnt+1 bits of vd are not all equal
        e(f'    x = {sext} >> ({w - 1} - {cnt})')
        e('    If x = 0 Or x = -1')
        e('      FV = 0')
        e('    Else')
        e(f'      FV = {TOP()}')
        e('    EndIf')
        e('  Else')
        e('    vr = 0')
        e(f'    If {cnt} = {w}')
        e(f'      FC = (vd & 1) << {T}')
        e('    Else')
        e('      FC = 0')
        e('    EndIf')
        e('    If vd <> 0')
        e(f'      FV = {TOP()}')
        e('    Else')
        e('      FV = 0')
        e('    EndIf')
        e('  EndIf')
        e('  FX = FC')
    elif t == 0:               # ASR
        e(f'  If {cnt} < {w}')
        e(f'    vr = {M(f"{sext} >> {cnt}")}')
        e(f'    FC = ((vd >> ({cnt} - 1)) & 1) << {T}')
        e('  Else')
        e(f'    If vd & {1 << (w - 1):#x}'.replace('0x', '$'))
        e(f'      vr = {"-1" if (s == "L" and IW() == 32) else m}')
        e(f'      FC = {TOP()}')
        e('    Else')
        e('      vr = 0')
        e('      FC = 0')
        e('    EndIf')
        e('  EndIf')
        e('  FX = FC')
        e('  FV = 0')
    elif t == 1 and d == 1:    # LSL
        e(f'  If {cnt} <= {w}')
        e(f'    vr = {M(f"vd << {cnt}")}')
        e(f'    FC = ((vd >> ({w} - {cnt})) & 1) << {T}')
        if IW() == 32 and w == 32:
            e(f'    If {cnt} = 32')
            e('      vr = 0')
            e(f'      FC = (vd & 1) << {T}')
            e('    EndIf')
        e('  Else')
        e('    vr = 0')
        e('    FC = 0')
        e('  EndIf')
        e('  FX = FC')
        e('  FV = 0')
    elif t == 1:               # LSR
        e(f'  If {cnt} <= {w}')
        e(f'    vr = {lsr("vd", cnt, s)}')
        e(f'    FC = ({lsr("vd", f"({cnt} - 1)", s)} & 1) << {T}')
        if IW() == 32 and w == 32:
            e(f'    If {cnt} = 32')
            e('      vr = 0')
            e('    EndIf')
        e('  Else')
        e('    vr = 0')
        e('    FC = 0')
        e('  EndIf')
        e('  FX = FC')
        e('  FV = 0')
    elif t == 3:               # ROL / ROR
        e(f'  x = {cnt} & {w - 1}')
        if d == 1:
            q = '(vd << x) | ' + lsr('vd', f'({w} - x)', s)
            e(f'  vr = {M(q)}')
            e('  If x = 0')
            e('    vr = vd')
            e('  EndIf')
            e(f'  FC = (vr & 1) << {T}')
        else:
            q = lsr('vd', 'x', s) + f' | (vd << ({w} - x))'
            e(f'  vr = {M(q)}')
            e('  If x = 0')
            e('    vr = vd')
            e('  EndIf')
            e(f'  FC = ((vr >> {w - 1}) & 1) << {T}')
        e('  FV = 0')
    else:                      # ROXL / ROXR, through X, one bit at a time
        e(f'  x = {cnt}')
        e(f'  While x > {w}')
        e(f'    x = x - {w + 1}')
        e('  Wend')
        e('  vr = vd')
        e(f'  y = {XBIT()}')
        e('  While x > 0')
        if d == 1:
            e(f'    u = ({lsr("vr", w - 1, s)}) & 1')
            e(f'    vr = {M("(vr << 1) | y")}')
        else:
            e('    u = vr & 1')
            e(f'    vr = {lsr("vr", 1, s)} | (y << {w - 1})')
        e('    y = u')
        e('    x = x - 1')
        e('  Wend')
        e(f'  FX = y << {T}')
        e('  FC = FX')
        e('  FV = 0')
    nz(s, 'vr')
    goto(done)
    label(zero)
    e('  vr = vd')
    e('  FV = 0')
    if t == 2:
        e('  FC = FX')
    else:
        e('  FC = 0')
    nz(s, 'vr')
    label(done)

def lsr(v, n, s):
    """Logical right shift of a size-s value (zero-extended for B/W)."""
    if s != 'L' or IW() == 64:
        if s == 'L':
            return f'(({v} & $FFFFFFFF) >> {n})'
        return f'({v} >> {n})'
    # 32-bit host, long: clear the bits the arithmetic shift copied in
    return f'(({v} >> {n}) & ~(($80000000 >> {n}) << 1))'

def emit_shift_reg(name, d, s):
    handler(name)
    e('  x = (op >> 9) & 7')
    e('  If op & $20')
    e('    x = Reg(x) & 63')
    e('  ElseIf x = 0')
    e('    x = 8')
    e('  EndIf')
    e('  rg = x')
    e(f'  vd = {dreg(OPR(), s)}')
    if s == 'L' and IW() == 64:
        e('  vd = vd & $FFFFFFFF')
    e('  y = (op >> 3) & 3')
    labs = [newlab('T') for _ in range(4)]
    out = newlab('O')
    for t in range(3):
        e(f'  If y = {t}')
        goto(labs[t])
        e('  EndIf')
    for t in (3, 0, 1, 2):
        label(labs[t])
        shift_core(t, d, s, 'rg')
        goto(out)
    label(out)
    set_dreg(OPR(), s, 'vr')
    charge(f'{8 if s == "L" else 6} + (rg << 1)')
    tail()

def emit_shift_mem(name, t, d):
    handler(name)
    e('  If op & $800')
    goto('IllegalOp')
    e('  EndIf')
    alt('W')
    rd('W', 'vd')
    e('  rg = 1')
    shift_core(t, d, 'W', 'rg')
    wr('W', 'vr')
    charge(8)
    tail()
