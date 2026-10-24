; m68k_run - run a raw 68000 image headless on the Amiga emulator's 68000 core
; (AmigaEmulatorPicoSeries/desktop/m68k_core.pbi, included as it is) and report.
;
;   m68k_run <image.bin> --load <hex> [--entry <hex> --ssp <hex>] [--ram <bytes>]
;            [--cycles <n>] [--dump <hex>:<len> <file>]...
;
; Flat RAM from address 0 (1 MB unless --ram says otherwise); the image is laid
; down at --load. With no --entry the CPU resets the way the silicon does (SSP
; and PC from addresses 0 and 4). Everything above the RAM is a "hook" page:
; writes there are accepted and dropped, reads give 0 - the custom chips'
; addresses, for programs that touch them.
;
; It stops at:  a branch to itself ("bra.s *", $60FE)   -> halt=selfbranch, exit 0
;               an address error (odd word/long access)  -> halt=addresserror, exit 1
;               STOP                                     -> halt=stop,       exit 1
;               the CPU halting (double fault)           -> halt=halted,     exit 1
;               the cycle budget                         -> halt=budget,     exit 1
; and prints one line: halt=... pc=$xxxxxx cycles=n vec=<last exception vector>
; then d0-d7 and a0-a7. A dump is the bytes as the 68000 sees them (big-endian).
; Written by the 68000 compiler back end's work for its gates; kept here so the
; gates run this repository's own program. Build: desktop/build.sh m68k_run console
EnableExplicit
XIncludeFile "m68k_core.pbi"

Global *RunRam, RunRamBytes.i = $100000
Global RunHookWrites.i

Procedure.i M68kHookRd8(a.i)
  ProcedureReturn 0
EndProcedure
Procedure.i M68kHookRd16(a.i)
  ProcedureReturn 0
EndProcedure
Procedure M68kHookWr8(a.i, v.i)
  RunHookWrites + 1
EndProcedure
Procedure M68kHookWr16(a.i, v.i)
  RunHookWrites + 1
EndProcedure
Procedure M68kResetHook()
EndProcedure

Procedure.i RunHex(s.s)
  s = Trim(s)
  If Left(s, 1) = "$" : ProcedureReturn Val(s) : EndIf
  If LCase(Left(s, 2)) = "0x" : ProcedureReturn Val("$" + Mid(s, 3)) : EndIf
  ProcedureReturn Val("$" + s)
EndProcedure

; a guest byte (the host keeps each 16-bit word in its own byte order)
Procedure.i RunByte(a.i)
  ProcedureReturn PeekA(*RunRam + (a ! 1))
EndProcedure

OpenConsole()
Define runImg.s = ProgramParameter(0)
Define runLoad.i = 0, runEntry.i = -1, runSsp.i = -1, runBudget.q = 200000000
Define k.i, argn.i = CountProgramParameters(), opt.s
NewList dumpAt.i()
NewList dumpLen.i()
NewList dumpFile.s()
k = 1
While k < argn
  opt = ProgramParameter(k)
  Select opt
    Case "--load"   : k + 1 : runLoad = RunHex(ProgramParameter(k))
    Case "--entry"  : k + 1 : runEntry = RunHex(ProgramParameter(k))
    Case "--ssp"    : k + 1 : runSsp = RunHex(ProgramParameter(k))
    Case "--ram"    : k + 1 : RunRamBytes = Val(ProgramParameter(k))
    Case "--cycles" : k + 1 : runBudget = Val(ProgramParameter(k))
    Case "--dump"
      k + 1
      AddElement(dumpAt()) : dumpAt() = RunHex(StringField(ProgramParameter(k), 1, ":"))
      AddElement(dumpLen()) : dumpLen() = Val(StringField(ProgramParameter(k), 2, ":"))
      k + 1
      AddElement(dumpFile()) : dumpFile() = ProgramParameter(k)
    Default
      PrintN("m68k_run: unknown option " + opt) : End 2
  EndSelect
  k + 1
Wend
If runImg = ""
  PrintN("usage: m68k_run <image.bin> --load <hex> [--entry <hex> --ssp <hex>] [--cycles n] [--dump <hex>:<len> <file>]")
  End 2
EndIf
RunRamBytes = (RunRamBytes + 4095) & ~4095
*RunRam = AllocateMemory(RunRamBytes)
M68kMapHook(0, $1000000)
M68kMapRam(0, RunRamBytes, *RunRam)
Define fh.i = ReadFile(#PB_Any, runImg)
If Not fh : PrintN("m68k_run: cannot read " + runImg) : End 2 : EndIf
Define imgBytes.i = Lof(fh)
If runLoad + imgBytes > RunRamBytes
  PrintN("m68k_run: the image ($" + Hex(runLoad) + " + " + Str(imgBytes) + " bytes) does not fit the RAM")
  End 2
EndIf
Define *imgTmp = AllocateMemory(imgBytes + 2)
ReadData(fh, *imgTmp, imgBytes)
CloseFile(fh)
For k = 0 To imgBytes - 1
  PokeA(*RunRam + ((runLoad + k) ! 1), PeekA(*imgTmp + k))
Next
FreeMemory(*imgTmp)

M68kReset()
If runEntry >= 0
  M68kSetPC(runEntry)
  If runSsp >= 0 : Reg(15) = runSsp : EndIf
EndIf

Define runSpent.q = 0, runHalt.s = "", runPc.i, runWord.i
Repeat
  runSpent + M68kRun(20000)
  If M68kLastVec = 3 : runPc = M68kGetPC() & $FFFFFF : runHalt = "addresserror" : Break : EndIf
  runPc = M68kGetPC() & $FFFFFF
  If runPc < RunRamBytes - 1
    runWord = (RunByte(runPc) << 8) | RunByte(runPc + 1)
    If runWord = $60FE : runHalt = "selfbranch" : Break : EndIf
  EndIf
  If Halted : runHalt = "halted" : Break : EndIf
  If Stopped : runHalt = "stop" : Break : EndIf
  If runSpent >= runBudget : runHalt = "budget" : Break : EndIf
ForEver

Define outText.s = "halt=" + runHalt + " pc=$" + RSet(Hex(runPc), 6, "0") + " cycles=" + Str(runSpent) + " vec=" + Str(M68kLastVec) + " hookwrites=" + Str(RunHookWrites)
PrintN(outText)
outText = ""
For k = 0 To 7 : outText + " d" + Str(k) + "=" + RSet(Hex(Reg(k) & $FFFFFFFF), 8, "0") : Next
PrintN(Trim(outText))
outText = ""
For k = 0 To 7 : outText + " a" + Str(k) + "=" + RSet(Hex(Reg(8 + k) & $FFFFFFFF), 8, "0") : Next
PrintN(Trim(outText))

ResetList(dumpAt()) : ResetList(dumpLen()) : ResetList(dumpFile())
While NextElement(dumpAt())
  NextElement(dumpLen()) : NextElement(dumpFile())
  fh = CreateFile(#PB_Any, dumpFile())
  If fh
    For k = 0 To dumpLen() - 1
      If dumpAt() + k < RunRamBytes : WriteAsciiCharacter(fh, RunByte(dumpAt() + k)) : Else : WriteAsciiCharacter(fh, 0) : EndIf
    Next
    CloseFile(fh)
  EndIf
Wend
If runHalt = "selfbranch" : End 0 : EndIf
End 1
