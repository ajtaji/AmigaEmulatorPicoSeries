; What the window shows: the Amiga's picture and the debug panes (CPU, Copper,
; Blitter, Custom, CIAs, Memory, Disks). Every read here is side-effect free:
; registers from the emulation's own variables, memory only from RAM and ROM.
EnableExplicit

Structure ViewTexture
  sprite.GLSprite
  *pixels
EndStructure

Global ViewPic.ViewTexture
Global ViewMemAddr.i, ViewCopTop.i, ViewRomPath.s, ViewAdfFolder.s, ViewAdfTop.i
Global NewList ViewAdfFiles.s()
Global ViewTestText.s, ViewTestBad.i

; --pointer-test (amiga.pb): where each control was last drawn, in canvas units (physical pixels), and the
; control a synthetic press landed on - under the test a press is recorded, never acted on.
Global PtOn.i, PtClicked$
Structure CtlRect : x.f : y.f : w.f : h.f : EndStructure
Global NewMap Ctl.CtlRect()
Procedure CtlSet(name$, x.f, y.f, w.f, h.f)
  Ctl(name$)\x = x : Ctl()\y = y : Ctl()\w = w : Ctl()\h = h
EndProcedure
Procedure.b Btn(name$, x.f, y.f, w.f, h.f, label.s, lit.b = #False)
  CtlSet(name$, x, y, w, h)
  If Neon_Button(x, y, w, h, label, lit)
    If PtOn : PtClicked$ = name$ : ProcedureReturn #False : EndIf
    ProcedureReturn #True
  EndIf
  ProcedureReturn #False
EndProcedure

Procedure ViewTextureMake(*t.ViewTexture, w.i, h.i)
  *t\sprite\Width = w : *t\sprite\Height = h
  *t\pixels = AllocateMemory(w * h * 4)
  glGenTextures_(1, @*t\sprite\TextureID)
  glBindTexture_(#GL_TEXTURE_2D, *t\sprite\TextureID)
  glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_MIN_FILTER, #GL_LINEAR)
  glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_MAG_FILTER, #GL_NEAREST)
  glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_WRAP_S, #GL_CLAMP_TO_EDGE)
  glTexParameteri_(#GL_TEXTURE_2D, #GL_TEXTURE_WRAP_T, #GL_CLAMP_TO_EDGE)
  glTexImage2D_(#GL_TEXTURE_2D, 0, #GL_RGBA, w, h, 0, #GL_RGBA, #GL_UNSIGNED_BYTE, *t\pixels)
EndProcedure

; The engine's sprite draw samples a Windows texture bottom-up, so rows go in that order there.
Procedure ViewPicUpload()
  Protected y.i, *src, *dst
  For y = 0 To #HOST_FRAME_H - 1
    *src = @HostFrame(y * #AM_OUT_W)
    CompilerIf #PB_Compiler_OS = #PB_OS_Windows
      *dst = ViewPic\pixels + (#HOST_FRAME_H - 1 - y) * #AM_OUT_W * 4
    CompilerElse
      *dst = ViewPic\pixels + y * #AM_OUT_W * 4
    CompilerEndIf
    CopyMemory(*src, *dst, #AM_OUT_W * 4)
  Next
  glBindTexture_(#GL_TEXTURE_2D, ViewPic\sprite\TextureID)
  glTexSubImage2D_(#GL_TEXTURE_2D, 0, 0, 0, #AM_OUT_W, #HOST_FRAME_H, #GL_RGBA, #GL_UNSIGNED_BYTE, ViewPic\pixels)
EndProcedure

Procedure ViewInit()
  ViewTextureMake(@ViewPic, #AM_OUT_W, #HOST_FRAME_H)
EndProcedure

; The picture at (x, y), scale picture pixels per texel (the 4:3 PAL shape kept).
Procedure ViewDrawPicture(x.f, y.f, scale.f)
  ViewPicUpload()
  Neon_Box(x - 2, y - 2, #AM_OUT_W * scale + 4, #HOST_FRAME_H * scale + 4, 0, 0, 0)
  DrawGLSprite(@ViewPic\sprite, x, y, 0.0, scale, 1.0, 1.0, 1.0, 1.0, #True, -1, -1, -1, -1, #True)
EndProcedure

Procedure.f ViewLine(x.f, y.f, t.s, r.f = -1, g.f = 0, b.f = 0)
  If r < 0
    r = Neon_C_TextR : g = Neon_C_TextG : b = Neon_C_TextB
  EndIf
  Neon_Text(*Neon_FontMono, x, y, t, r, g, b)
  ProcedureReturn y + GLFontLineHeight(*Neon_FontMono)
EndProcedure

Procedure.s H2(v.i)
  ProcedureReturn RSet(Hex(v & $FF), 2, "0")
EndProcedure
Procedure.s H4(v.i)
  ProcedureReturn RSet(Hex(v & $FFFF), 4, "0")
EndProcedure
Procedure.s H6(v.i)
  ProcedureReturn RSet(Hex(v & $FFFFFF), 6, "0")
EndProcedure
Procedure.s H8(v.i)
  ProcedureReturn RSet(Hex(v & $FFFFFFFF), 8, "0")
EndProcedure

; ---------------------------------------------------------------- CPU
Procedure ViewCpu(x.f, y.f, w.f, h.f)
  Protected i.i, sr.i, f.s, a.i, lh.f, row.s, k.i, v.i, pc.i
  lh = GLFontLineHeight(*Neon_FontMono)
  Neon_Panel(x, y, w, h, "68000 CPU", Neon_C_AccR, Neon_C_AccG, Neon_C_AccB)
  y + Neon_S(34) : x + Neon_S(12)
  For i = 0 To 3
    y = ViewLine(x, y, "D" + Str(i) + " " + H8(Reg(i)) + "   D" + Str(i + 4) + " " + H8(Reg(i + 4)) + "   A" + Str(i) + " " + H8(Reg(i + 8)) + "   A" + Str(i + 4) + " " + H8(Reg(i + 12)))
  Next
  sr = M68kGetSR()
  f = ""
  For i = 0 To 4
    If sr & (16 >> i)
      f + Mid("XNZVC", i + 1, 1)
    Else
      f + "."
    EndIf
  Next
  pc = M68kGetPC()
  y = ViewLine(x, y, "PC " + H8(pc) + "   SR " + H4(sr) + " " + f + "  T" + Str((sr >> 15) & 1) + " S" + Str((sr >> 13) & 1) + " IPL" + Str((sr >> 8) & 7) + "   USP " + H8(M68kGetUSP()) + "  SSP " + H8(M68kGetSSP()))
  y = ViewLine(x, y, "interrupt line " + Str(IplLine) + "   stopped " + Str(Stopped) + "   halted " + Str(Halted) + "   cycles " + Str(AmigaCpuCycles), Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
  y + Neon_S(6)
  Neon_Text(*Neon_FontSmall, x, y, "DISASSEMBLY", Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB) : y + lh
  a = pc & $FFFFFF
  For i = 0 To 17
    row = H6(a) + "  " + Dis68k(a)
    If i = 0
      y = ViewLine(x, y, "> " + row, Neon_C_GrnR, Neon_C_GrnG, Neon_C_GrnB)
    Else
      y = ViewLine(x, y, "  " + row)
    EndIf
    a = (a + DisLen) & $FFFFFF
  Next
  y + Neon_S(6)
  Neon_Text(*Neon_FontSmall, x, y, "TESTS (SingleStepTests 680x0)", Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)
  If Btn("Run tests", x + Neon_S(260), y - Neon_S(2), Neon_S(120), Neon_S(20), "Run tests")
    ViewRunTests()
  EndIf
  y + lh + Neon_S(4)
  If ViewTestText <> ""
    If ViewTestBad
      y = ViewLine(x, y, ViewTestText, Neon_C_RedR, Neon_C_RedG, Neon_C_RedB)
    Else
      y = ViewLine(x, y, ViewTestText, Neon_C_GrnR, Neon_C_GrnG, Neon_C_GrnB)
    EndIf
  EndIf
EndProcedure

; ---------------------------------------------------------------- copper
Procedure ViewCopper(x.f, y.f, w.f, h.f)
  Protected i.i, a.i, ir1.i, ir2.i, t.s, lh.f, n.i
  lh = GLFontLineHeight(*Neon_FontMono)
  Neon_Panel(x, y, w, h, "Copper", Neon_C_VioR, Neon_C_VioG, Neon_C_VioB)
  y + Neon_S(34) : x + Neon_S(12)
  y = ViewLine(x, y, "COP1LC " + H6(Cop1Lc) + "   COP2LC " + H6(Cop2Lc) + "   PC " + H6(CopPc) + "   state " + StringField("run|wait|stopped", CopState + 1, "|") + "   COPCON " + H4(CopCon))
  y + Neon_S(6)
  Neon_Text(*Neon_FontSmall, x, y, "LIST AT COP1LC", Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)
  If Btn("cop back", x + Neon_S(200), y - Neon_S(2), Neon_S(28), Neon_S(20), "<")
    ViewCopTop = ViewCopTop - 16
    If ViewCopTop < 0 : ViewCopTop = 0 : EndIf
  EndIf
  If Btn("cop forward", x + Neon_S(232), y - Neon_S(2), Neon_S(28), Neon_S(20), ">")
    ViewCopTop + 16
  EndIf
  y + lh
  n = (h - (y - (y - 0)) - Neon_S(80)) / lh
  If n > 40 : n = 40 : EndIf
  a = Cop1Lc + ViewCopTop * 4
  For i = 0 To n - 1
    ir1 = ChipRd(a)
    ir2 = ChipRd(a + 2)
    If (ir1 & 1) = 0
      t = "MOVE $" + H4(ir2) + ",$DFF" + RSet(Hex(ir1 & $1FE), 3, "0")
    ElseIf ir2 & 1
      t = "SKIP v=$" + H2(ir1 >> 8) + " h=$" + H2(ir1 & $FE) + "  mask $" + H4(ir2 & $FFFE)
    Else
      t = "WAIT v=$" + H2(ir1 >> 8) + " h=$" + H2(ir1 & $FE) + "  mask $" + H4(ir2 & $FFFE)
      If ir1 = $FFFF And ir2 = $FFFE
        t = "WAIT $FFFF,$FFFE (end)"
      EndIf
    EndIf
    If a = CopPc
      y = ViewLine(x, y, H6(a) + "  " + H4(ir1) + " " + H4(ir2) + "  " + t, Neon_C_GrnR, Neon_C_GrnG, Neon_C_GrnB)
    Else
      y = ViewLine(x, y, H6(a) + "  " + H4(ir1) + " " + H4(ir2) + "  " + t)
    EndIf
    a + 4
    If ir1 = $FFFF And ir2 = $FFFE
      Break
    EndIf
  Next
EndProcedure

; ---------------------------------------------------------------- blitter
Procedure ViewBlitter(x.f, y.f, w.f, h.f)
  Neon_Panel(x, y, w, h, "Blitter", Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)
  y + Neon_S(34) : x + Neon_S(12)
  y = ViewLine(x, y, "BLTCON0 " + H4(BltCon0) + "   USE " + Mid("ABCD", 1, 4) + " = " + Str((BltCon0 >> 11) & 1) + Str((BltCon0 >> 10) & 1) + Str((BltCon0 >> 9) & 1) + Str((BltCon0 >> 8) & 1) + "   minterm $" + H2(BltCon0) + "   A shift " + Str((BltCon0 >> 12) & 15))
  y = ViewLine(x, y, "BLTCON1 " + H4(BltCon1) + "   B shift " + Str((BltCon1 >> 12) & 15) + StringField("|  LINE", (BltCon1 & 1) + 1, "|") + StringField("|  DESC", ((BltCon1 >> 1) & 1) + 1, "|") + StringField("|  FILL", Bool(BltCon1 & $18) + 1, "|"))
  y = ViewLine(x, y, "BLTSIZE " + H4(Cust(#R_BLTSIZE >> 1)) + "   " + Str(Cust(#R_BLTSIZE >> 1) & 63) + " words x " + Str((Cust(#R_BLTSIZE >> 1) >> 6) & 1023) + " lines")
  y = ViewLine(x, y, "AFWM " + H4(Cust(#R_BLTAFWM >> 1)) + "  ALWM " + H4(Cust(#R_BLTALWM >> 1)))
  y + Neon_S(6)
  y = ViewLine(x, y, "APT " + H6(BltApt) + "  mod " + Str(Sx16(Cust(#R_BLTAMOD >> 1))) + "   ADAT " + H4(BltAdat))
  y = ViewLine(x, y, "BPT " + H6(BltBpt) + "  mod " + Str(Sx16(Cust(#R_BLTBMOD >> 1))) + "   BDAT " + H4(BltBdat))
  y = ViewLine(x, y, "CPT " + H6(BltCpt) + "  mod " + Str(Sx16(Cust(#R_BLTCMOD >> 1))) + "   CDAT " + H4(BltCdat))
  y = ViewLine(x, y, "DPT " + H6(BltDpt) + "  mod " + Str(Sx16(Cust(#R_BLTDMOD >> 1))) + "   DDAT " + H4(BltDdat))
  y + Neon_S(6)
  y = ViewLine(x, y, "busy " + Str(BltActive) + "   zero " + Str(BltZero) + "   ends at cycle " + Str(BltEndCyc))
EndProcedure

; ---------------------------------------------------------------- custom registers
Procedure ViewCustom(x.f, y.f, w.f, h.f)
  Protected i.i, row.s, k.i, cx.i, cy.i, cr.i, cg.i, cb.i
  Neon_Panel(x, y, w, h, "Custom chips", Neon_C_GrnR, Neon_C_GrnG, Neon_C_GrnB)
  y + Neon_S(34) : x + Neon_S(12)
  y = ViewLine(x, y, "DMACON " + H4(DmaCon) + "  INTENA " + H4(IntEna) + "  INTREQ " + H4(IntReq) + "  ADKCON " + H4(AdkCon))
  y = ViewLine(x, y, "BPLCON0 " + H4(BplCon0) + " (" + Str((BplCon0 >> 12) & 7) + " planes" + StringField("| hires", Bool(BplCon0 & $8000) + 1, "|") + StringField("| HAM", Bool(BplCon0 & $800) + 1, "|") + StringField("| dual pf", Bool(BplCon0 & $400) + 1, "|") + StringField("| lace", Bool(BplCon0 & 4) + 1, "|") + ")  BPLCON1 " + H4(BplCon1) + "  BPLCON2 " + H4(BplCon2))
  y = ViewLine(x, y, "DIWSTRT " + H4(DiwStrt) + "  DIWSTOP " + H4(DiwStop) + "  DDFSTRT " + H4(DdfStrt) + "  DDFSTOP " + H4(DdfStop) + "  MOD " + H4(Bpl1Mod) + "/" + H4(Bpl2Mod))
  row = "BPLxPT"
  For i = 0 To 5
    row + " " + H6(BplPt(i))
  Next
  y = ViewLine(x, y, row)
  y = ViewLine(x, y, "beam: line " + Str(VPos) + " / " + Str(LinesThisFrame) + "   frame " + Str(FrameCount) + "   long frame " + Str(LongFrame))
  y + Neon_S(6)
  Neon_Text(*Neon_FontSmall, x, y, "COLOURS", Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)
  y + GLFontLineHeight(*Neon_FontMono)
  For i = 0 To 31
    k = Color(i)
    cx = i & 15 : cy = i >> 4 : cr = (k >> 8) & 15 : cg = (k >> 4) & 15 : cb = k & 15
    Neon_Box(x + cx * Neon_S(22), y + cy * Neon_S(22), Neon_S(20), Neon_S(20), cr / 15.0, cg / 15.0, cb / 15.0)
  Next
  y + Neon_S(50)
  Neon_Text(*Neon_FontSmall, x, y, "SPRITES", Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)
  y + GLFontLineHeight(*Neon_FontMono)
  For i = 0 To 7
    y = ViewLine(x, y, Str(i) + "  PT " + H6(SprPt(i)) + "  POS " + H4(SprPos(i)) + "  CTL " + H4(SprCtl(i)) + "  armed " + Str(SprArmed(i)) + "  state " + Str(SprState(i)))
  Next
  y + Neon_S(6)
  Neon_Text(*Neon_FontSmall, x, y, "AUDIO", Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)
  y + GLFontLineHeight(*Neon_FontMono)
  For i = 0 To 3
    y = ViewLine(x, y, Str(i) + "  on " + Str(AudOn(i)) + "  LC " + H6((Cust($50 + i * 8) << 16) | Cust($51 + i * 8)) + "  LEN " + H4(Cust($52 + i * 8)) + "  PER " + H4(Cust($53 + i * 8)) + "  VOL " + Str(Cust($54 + i * 8) & 127) + "  at " + H6(AudPt(i)))
  Next
EndProcedure

; ---------------------------------------------------------------- CIAs
Procedure ViewCias(x.f, y.f, w.f, h.f)
  Protected c.i
  Neon_Panel(x, y, w, h, "CIAs (8520)", Neon_C_RedR, Neon_C_RedG, Neon_C_RedB)
  y + Neon_S(34) : x + Neon_S(12)
  For c = 0 To 1
    CiaSync(c)
    Neon_Text(*Neon_FontSmall, x, y, StringField("CIA-A  $BFE001  (keyboard, OVL, LED, fire buttons, disk status)|CIA-B  $BFD000  (floppy controls, serial lines)", c + 1, "|"), Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)
    y + GLFontLineHeight(*Neon_FontMono)
    y = ViewLine(x, y, "PRA " + H2(CiaPra(c)) + " DDRA " + H2(CiaDdra(c)) + "   PRB " + H2(CiaPrb(c)) + " DDRB " + H2(CiaDdrb(c)) + "   SDR " + H2(CiaSdr(c)))
    y = ViewLine(x, y, "timer A " + H4(CiaTa(c)) + " latch " + H4(CiaTaLatch(c)) + " CRA " + H2(CiaCra(c)) + "   timer B " + H4(CiaTb(c)) + " latch " + H4(CiaTbLatch(c)) + " CRB " + H2(CiaCrb(c)))
    y = ViewLine(x, y, "TOD " + H6(CiaTod(c)) + "  alarm " + H6(CiaAlarm(c)) + "   ICR " + H2(CiaIcr(c)) + "  mask " + H2(CiaMask(c)))
    y + Neon_S(10)
  Next
  y = ViewLine(x, y, "OVL " + Str(AmigaOvl) + "   power LED " + StringField("bright|dim", ((CiaPra(0) >> 1) & 1) + 1, "|"))
  y = ViewLine(x, y, "keyboard queue " + Str((KbdTail - KbdHead) & (#KBD_QUEUE - 1)) + "   waiting for handshake " + Str(KbdWait))
EndProcedure

; ---------------------------------------------------------------- memory
Procedure ViewMemory(x.f, y.f, w.f, h.f)
  Protected i.i, k.i, a.i, row.s, asc.s, t.i, v.i, lh.f
  lh = GLFontLineHeight(*Neon_FontMono)
  Neon_Panel(x, y, w, h, "Memory", Neon_C_AccR, Neon_C_AccG, Neon_C_AccB)
  y + Neon_S(34) : x + Neon_S(12)
  Neon_Text(*Neon_FontSmall, x, y, "ADDRESS $" + H6(ViewMemAddr), Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)
  If Btn("mem <<", x + Neon_S(160), y - Neon_S(2), Neon_S(36), Neon_S(20), "<<") : ViewMemAddr = (ViewMemAddr - $1000) & $FFFFF0 : EndIf
  If Btn("mem <", x + Neon_S(200), y - Neon_S(2), Neon_S(28), Neon_S(20), "<") : ViewMemAddr = (ViewMemAddr - $100) & $FFFFF0 : EndIf
  If Btn("mem >", x + Neon_S(232), y - Neon_S(2), Neon_S(28), Neon_S(20), ">") : ViewMemAddr = (ViewMemAddr + $100) & $FFFFF0 : EndIf
  If Btn("mem >>", x + Neon_S(264), y - Neon_S(2), Neon_S(36), Neon_S(20), ">>") : ViewMemAddr = (ViewMemAddr + $1000) & $FFFFF0 : EndIf
  If Btn("mem PC", x + Neon_S(306), y - Neon_S(2), Neon_S(40), Neon_S(20), "PC") : ViewMemAddr = M68kGetPC() & $FFFFF0 : EndIf
  If Btn("mem SP", x + Neon_S(350), y - Neon_S(2), Neon_S(40), Neon_S(20), "SP") : ViewMemAddr = Reg(15) & $FFFFF0 : EndIf
  If Btn("mem copper", x + Neon_S(394), y - Neon_S(2), Neon_S(56), Neon_S(20), "copper") : ViewMemAddr = Cop1Lc & $FFFFF0 : EndIf
  If Btn("mem ROM", x + Neon_S(454), y - Neon_S(2), Neon_S(46), Neon_S(20), "ROM") : ViewMemAddr = $F80000 : EndIf
  y + lh + Neon_S(4)
  For i = 0 To 31
    a = (ViewMemAddr + i * 16) & $FFFFFF
    row = H6(a) + " "
    asc = ""
    For k = 0 To 15
      t = PageR(((a + k) >> 12) & $FFF)
      If t = 0
        row + " --"
        asc + " "
      Else
        v = PeekA(t + ((a + k) ! 1))
        row + " " + H2(v)
        If v >= 32 And v < 127 : asc + Chr(v) : Else : asc + "." : EndIf
      EndIf
    Next
    y = ViewLine(x, y, row + "  " + asc)
  Next
EndProcedure

; ---------------------------------------------------------------- disks and ROM
Declare HostChooseRom()
Declare HostInsert(d.i, path.s)

Procedure ViewAdfRefresh(folder.s)
  Protected dir.i
  If folder = "" : ProcedureReturn : EndIf
  ViewAdfFolder = folder
  ClearList(ViewAdfFiles())
  dir = ExamineDirectory(#PB_Any, folder, "*.adf")
  If dir
    While NextDirectoryEntry(dir)
      If DirectoryEntryType(dir) = #PB_DirectoryEntry_File
        AddElement(ViewAdfFiles())
        ViewAdfFiles() = DirectoryEntryName(dir)
      EndIf
    Wend
    FinishDirectory(dir)
  EndIf
  SortList(ViewAdfFiles(), #PB_Sort_Ascending | #PB_Sort_NoCase)
  ViewAdfTop = 0
EndProcedure

Procedure ViewDisks(x.f, y.f, w.f, h.f)
  Protected f.s, d.i, lh.f, y0.f = y, idx.i, last.i, rowY.f
  lh = GLFontLineHeight(*Neon_FontMono)
  Neon_Panel(x, y, w, h, "Kickstart and disks", Neon_C_AccR, Neon_C_AccG, Neon_C_AccB)
  y + Neon_S(34) : x + Neon_S(12)
  y = ViewLine(x, y, "Kickstart: " + HostRomName + "  (" + Str(AmigaRomBytes / 1024) + " KB)")
  If Btn("disks Kickstart", x, y + Neon_S(2), Neon_S(140), Neon_S(24), "Choose Kickstart...") : HostChooseRom() : EndIf
  y + Neon_S(34)
  For d = 0 To 1
    If d = 0 : f = HostAdfName0 : Else : f = HostAdfName1 : EndIf
    If f = "" : f = "(empty)" : EndIf
    y = ViewLine(x, y, "DF" + Str(d) + ": " + f + "   track " + Str(DrvTrack(d)) + "  motor " + StringField("off|on", DrvMotor(d) + 1, "|"))
    If Btn("disks Insert DF" + Str(d), x, y + Neon_S(2), Neon_S(110), Neon_S(22), "Insert DF" + Str(d) + "...")
      f = OpenFileRequester("Insert a disk in DF" + Str(d), ViewAdfFolder, "Amiga disks (*.adf)|*.adf|All files|*.*", 0)
      If f <> "" : HostInsert(d, f) : ViewAdfRefresh(GetPathPart(f)) : EndIf
    EndIf
    If Btn("disks Eject DF" + Str(d), x + Neon_S(118), y + Neon_S(2), Neon_S(90), Neon_S(22), "Eject DF" + Str(d)) : HostEject(d) : EndIf
    y + Neon_S(32)
  Next
  If Btn("Choose folder", x, y, Neon_S(130), Neon_S(24), "Choose folder...")
    f = PathRequester("Choose a folder of .ADF disks", ViewAdfFolder)
    If f <> "" : ViewAdfRefresh(f) : EndIf
  EndIf
  Neon_Text(*Neon_FontSmall, x + Neon_S(140), y + Neon_S(4), Neon_FitText(*Neon_FontSmall, ViewAdfFolder, w - Neon_S(160)), Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)
  y + Neon_S(30)
  Neon_Text(*Neon_FontSmall, x, y, "Click a disk to put it in DF0:", Neon_C_AmbR, Neon_C_AmbG, Neon_C_AmbB)
  y + lh
  ; the list fills the pane to its bottom (less its margin)
  Neon_ListBegin(7, x, y, w - Neon_S(24), h - (y - y0) - Neon_S(12), Neon_S(22), @ViewAdfTop)
  last = Neon_ListTop + Int(Neon_ListH / Neon_ListRowH) - 1
  ForEach ViewAdfFiles()
    idx = Neon_ListRow : rowY = Neon_ListY + (idx - Neon_ListTop) * Neon_ListRowH
    If idx = Neon_ListTop : CtlSet("list first row", Neon_ListX, rowY, Neon_ListW - Neon_S(10), Neon_ListRowH) : EndIf
    If idx = last : CtlSet("list last row", Neon_ListX, rowY, Neon_ListW - Neon_S(10), Neon_ListRowH) : EndIf
    If Neon_ListItem(ViewAdfFiles(), 0, Bool(ViewAdfFiles() = HostAdfName0))
      If PtOn
        PtClicked$ = "list row " + Str(idx)
        If idx = Neon_ListTop : PtClicked$ = "list first row" : EndIf
        If idx = last : PtClicked$ = "list last row" : EndIf
      Else
        HostInsert(0, ViewAdfFolder + ViewAdfFiles())
      EndIf
    EndIf
  Next
  Neon_ListEnd()
EndProcedure

Procedure ViewDrawPanel(tab.i, x.f, y.f, w.f, h.f)
  Select tab
    Case 0 : ViewCpu(x, y, w, h)
    Case 1 : ViewCopper(x, y, w, h)
    Case 2 : ViewBlitter(x, y, w, h)
    Case 3 : ViewCustom(x, y, w, h)
    Case 4 : ViewCias(x, y, w, h)
    Case 5 : ViewMemory(x, y, w, h)
    Case 6 : ViewDisks(x, y, w, h)
  EndSelect
EndProcedure
