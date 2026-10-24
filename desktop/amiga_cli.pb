; Console run of the Amiga: no window.
;   amiga_cli --rom <kickstart> [--adf <disk>] [--frames N] [--shot out.png]
;             [--slow KB] [--trace]
; Runs N frames (default 250, five seconds of PAL), prints what the machine
; sent on its serial port, the frame rate reached and where the CPU is, and
; saves the last picture.
XIncludeFile "amiga_host.pbi"

OpenConsole()
Define k.i, a.s, rom.s, adf.s, shot.s, frames.i = 250, slowKb.i = 512, t0.i, t1.i, f.i
Define cyc0.i
For k = 0 To CountProgramParameters() - 1
  a = ProgramParameter(k)
  If a = "--rom"
    k + 1 : rom = ProgramParameter(k)
  ElseIf a = "--adf"
    k + 1 : adf = ProgramParameter(k)
  ElseIf a = "--frames"
    k + 1 : frames = Val(ProgramParameter(k))
  ElseIf a = "--shot"
    k + 1 : shot = ProgramParameter(k)
  ElseIf a = "--slow"
    k + 1 : slowKb = Val(ProgramParameter(k))
  EndIf
Next
If rom = ""
  PrintN("usage: amiga_cli --rom <kickstart> [--adf <disk>] [--frames N] [--shot out.png] [--slow KB]")
  End 2
EndIf
HostInit(slowKb)
If HostLoadRom(rom) = 0
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
If shot <> ""
  If HostSavePng(shot)
    PrintN("picture: " + shot)
  EndIf
EndIf
End 0
