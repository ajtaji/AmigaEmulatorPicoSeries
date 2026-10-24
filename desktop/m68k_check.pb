; Console run of the 68000 single-instruction tests on the desktop core, through
; the same runner the board uses (Diagnostics/vectors_run.pmi).
;   m68k_check <dir of .m68c files> [name filter]
; Prints one verdict line per file and the totals; exit code 0 only when every
; test passed (corpus errata are counted apart, see README.md).
EnableExplicit
#VEC_POOL = 12
XIncludeFile "m68k_core.pbi"

Global *VBuf, VPos.i, VLen.i

Procedure.i RxByte()
  Protected c.i
  If VPos >= VLen
    ProcedureReturn 'Z'
  EndIf
  c = PeekA(*VBuf + VPos)
  VPos + 1
  ProcedureReturn c
EndProcedure

Procedure SayChar(c.i)
  Print(Chr(c))
EndProcedure

Procedure Say(t.s)
  Print(t)
EndProcedure

Procedure Num(v.i)
  Print(Str(v))
EndProcedure

Procedure SayHex(v.i, digits.i)
  Print(RSet(Hex(v & $FFFFFFFF), digits, "0"))
EndProcedure

Procedure Eol()
  PrintN("")
EndProcedure

Procedure.i Same32(a.q, b.q)
  ProcedureReturn Bool(((a ! b) & $FFFFFFFF) = 0)
EndProcedure

XIncludeFile "../Diagnostics/vectors_run.pmi"

OpenConsole()
Define dir.s = ProgramParameter(0)
Define filt.s = ProgramParameter(1)
If dir = ""
  PrintN("usage: m68k_check <dir of .m68c files> [name filter]")
  End 2
EndIf
If Right(dir, 1) <> "\"
  dir + "\"
EndIf
NewList files.s()
Define d.i = ExamineDirectory(#PB_Any, dir, "*.m68c")
If d = 0
  PrintN("cannot read " + dir)
  End 2
EndIf
While NextDirectoryEntry(d)
  If filt = "" Or FindString(LCase(DirectoryEntryName(d)), LCase(filt))
    AddElement(files())
    files() = DirectoryEntryName(d)
  EndIf
Wend
FinishDirectory(d)
SortList(files(), #PB_Sort_Ascending | #PB_Sort_NoCase)
Define tp.i, tf.i, tc.i, te.i, f.i, t0.i = ElapsedMilliseconds()
ForEach files()
  f = ReadFile(#PB_Any, dir + files())
  If f = 0
    PrintN("cannot open " + files())
    End 2
  EndIf
  VLen = Lof(f)
  *VBuf = AllocateMemory(VLen + 1)
  ReadData(f, *VBuf, VLen)
  CloseFile(f)
  VPos = 0
  VecStream()
  FreeMemory(*VBuf)
  tp + VTPass
  tf + VTFail
  tc + VTCyc
  te + VTErr
Next
PrintN("TOTAL pass " + Str(tp) + " fail " + Str(tf) + " cycles " + Str(tc) + " errata " + Str(te) + " in " + Str(ElapsedMilliseconds() - t0) + " ms")
If tf = 0 And tc = 0
  End 0
EndIf
End 1
