; Console run of the Amiga: no window.
;   amiga_cli --rom <kickstart> [--adf <disk>] [--frames N] [--shot out.png]
;             [--ext <extended ROM at $E00000>] [--slow KB] [--stamp]
;             [--dump-chip file] [--dump-track N file]
;   amiga_cli --boot <disk> [...]  no Kickstart: the built-in boot ROM starts
;             the disk's bootblock (bootrom/bootrom.s)
; Runs N frames (default 250, five seconds of PAL), prints what the machine
; sent on its serial port, the frame rate reached and where the CPU is, and
; saves the last picture.
XIncludeFile "amiga_host.pbi"

OpenConsole()
Define k.i, a.s, rom.s, ext.s, adf.s, shot.s, frames.i = 250, slowKb.i = 512, t0.i, t1.i, f.i
Define m.i, cyc0.i, dumpTrack.i = -1, dumpFile.s, w.i, chipFile.s, n.i, l.i, r.i, zl.i, zr.i, ll.q, rr.q, pl.i, pr.i
For k = 0 To CountProgramParameters() - 1
  a = ProgramParameter(k)
  If a = "--rom"
    k + 1 : rom = ProgramParameter(k)
  ElseIf a = "--ext"
    k + 1 : ext = ProgramParameter(k)
  ElseIf a = "--boot"
    k + 1 : adf = ProgramParameter(k) : rom = "*boot"

  ElseIf a = "--adf"
    k + 1 : adf = ProgramParameter(k)
  ElseIf a = "--frames"
    k + 1 : frames = Val(ProgramParameter(k))
  ElseIf a = "--shot"
    k + 1 : shot = ProgramParameter(k)
  ElseIf a = "--slow"
    k + 1 : slowKb = Val(ProgramParameter(k))
  ElseIf a = "--stamp"
    HostSerialStamp = 1
  ElseIf a = "--dump-chip"
    k + 1 : chipFile = ProgramParameter(k)
  ElseIf a = "--dump-track"
    k + 1 : dumpTrack = Val(ProgramParameter(k))
    k + 1 : dumpFile = ProgramParameter(k)
  EndIf
Next
If rom = ""
  PrintN("usage: amiga_cli --rom <kickstart> [--adf <disk>] [--frames N] [--shot out.png] [--slow KB]")
  PrintN("       amiga_cli --boot <disk.adf> [...]   (no Kickstart: the built-in boot ROM)")
  End 2
EndIf
HostInit(slowKb)
If rom = "*boot"
  HostUseBootRom()
ElseIf HostLoadRom(rom) = 0
  PrintN(HostError)
  End 2
EndIf
If ext <> "" And HostLoadExt(ext) = 0
  PrintN(HostError)
  End 2
EndIf
AmigaReset()
If adf <> ""
  If HostLoadAdf(0, adf) = 0
    PrintN(HostError)
    End 2
  EndIf
EndIf
If dumpTrack >= 0
  ; the MFM words DF0 would read for track dumpTrack (cylinder * 2 + side), big-endian
  DrvTrack(0) = dumpTrack >> 1
  DrvSide = dumpTrack & 1
  TrackBuild(0)
  f = CreateFile(#PB_Any, dumpFile)
  For w = 0 To #TRACK_WORDS - 1
    WriteByte(f, TrackBuf(w) >> 8)
    WriteByte(f, TrackBuf(w) & 255)
  Next
  CloseFile(f)
  PrintN("track " + Str(dumpTrack) + ": " + Str(#TRACK_WORDS) + " words in " + dumpFile)
  End 0
EndIf
t0 = ElapsedMilliseconds()
For f = 1 To frames
  AmigaRunFrame()
Next
t1 = ElapsedMilliseconds() - t0
If t1 < 1
  t1 = 1
EndIf
If HostSerial <> ""
  PrintN("serial:")
  PrintN(HostSerial)
EndIf
PrintN("frames " + Str(frames) + " in " + Str(t1) + " ms = " + StrF(frames * 1000.0 / t1, 1) + " fps (PAL is 50)")
PrintN("CPU cycles " + Str(AmigaCpuCycles) + "  PC=" + Hex(M68kGetPC()) + " SR=" + Hex(M68kGetSR()) + " stopped=" + Str(Stopped) + " halted=" + Str(Halted))
PrintN("DMACON=" + Hex(DmaCon) + " INTENA=" + Hex(IntEna) + " INTREQ=" + Hex(IntReq) + " BPLCON0=" + Hex(BplCon0) + " COP1LC=" + Hex(Cop1Lc) + " copper state " + Str(CopState))
PrintN("drive 0 track " + Str(DrvTrack(0)) + " motor " + Str(DrvMotor(0)) + " side " + Str(DrvSide))
; the last second of Paula's output: level and pitch of each side
; a hash of the whole ring as it stands: any change to Paula's output shows here
Define h.q = 0
For w = 0 To #AUD_RING * 2 - 1
  h = (h * 31 + (AudRing(w) & $FFFF)) & $FFFFFFFF
Next
PrintN("audio ring: " + Str(AudWr) + " pairs written, hash " + RSet(Hex(h), 8, "0"))
n = #AUD_RATE
If AudWr < n : n = AudWr : EndIf
If n > 0
  pl = 0 : pr = 0
  For w = AudWr - n To AudWr - 1
    l = AudRing((w & (#AUD_RING - 1)) * 2)
    r = AudRing((w & (#AUD_RING - 1)) * 2 + 1)
    ll + l * l : rr + r * r
    If Bool(l >= 0) <> Bool(pl >= 0) : zl + 1 : EndIf
    If Bool(r >= 0) <> Bool(pr >= 0) : zr + 1 : EndIf
    pl = l : pr = r
  Next
  PrintN("audio: last " + Str(n) + " samples, left rms " + Str(Sqr(ll / n)) + " " + Str(zl * #AUD_RATE / (2 * n)) + " Hz, right rms " + Str(Sqr(rr / n)) + " " + Str(zr * #AUD_RATE / (2 * n)) + " Hz")
EndIf
CompilerIf Defined(M68K_HIST, #PB_Constant)
  ; the opcode counts, for tools/hist_report.py
  f = CreateFile(#PB_Any, "m68k_hist.bin")
  For w = 0 To 65535
    WriteQuad(f, M68kHist(w))
  Next
  CloseFile(f)
  PrintN("opcode counts: m68k_hist.bin")
CompilerEndIf
If chipFile <> ""
  ; Paula's ring beside it (chipFile + ".aud"): AudWr, then each slot's left + right
  ; - the mono sample a #AUD_MONO platform writes there - as big-endian words
  f = CreateFile(#PB_Any, chipFile + ".aud")
  WriteLong(f, AudWr)
  For w = 0 To #AUD_RING - 1
    m = (AudRing(w * 2) + AudRing(w * 2 + 1)) / 2
    WriteByte(f, (m >> 8) & 255)
    WriteByte(f, m & 255)
  Next
  CloseFile(f)
  ; slow RAM beside it (chipFile + ".slow"), big-endian
  f = CreateFile(#PB_Any, chipFile + ".slow")
  For w = 0 To AmigaSlowBytes - 2 Step 2
    WriteByte(f, PeekA(AmigaSlowHost + w + 1))
    WriteByte(f, PeekA(AmigaSlowHost + w))
  Next
  CloseFile(f)
  ; chip RAM, big-endian as the 68000 sees it
  f = CreateFile(#PB_Any, chipFile)
  For w = 0 To $7FFFE Step 2
    WriteByte(f, PeekA(ChipHost + w + 1))
    WriteByte(f, PeekA(ChipHost + w))
  Next
  CloseFile(f)
EndIf
If shot <> ""
  If HostSavePng(shot)
    PrintN("picture: " + shot)
  EndIf
EndIf
End 0
