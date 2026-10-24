; A 68000 disassembler for the debug panes. Reads memory without side effects:
; only RAM and ROM pages (a hook page - the chips, the CIAs - reads as $FFFF
; and the text says so). Dis68k(addr) returns the text; DisLen is its length.
EnableExplicit

Global DisLen.i, DisPc.i, DisBad.i

Procedure.i DisWord(a.i)
  Protected t.i
  a = a & $FFFFFF
  t = PageR((a >> 12) & $FFF)
  If t = 0 Or (a & 1)
    DisBad = 1
    ProcedureReturn $FFFF
  EndIf
  ProcedureReturn PeekU(t + a)
EndProcedure

Procedure.i DisNext()
  Protected w.i
  w = DisWord(DisPc)
  DisPc + 2
  ProcedureReturn w
EndProcedure

Procedure.s DisHex(v.i, digits.i)
  ProcedureReturn "$" + RSet(Hex(v & $FFFFFFFF), digits, "0")
EndProcedure

Procedure.s DisSigned(v.i)
  If v < 0
    ProcedureReturn "-$" + Hex(-v)
  EndIf
  ProcedureReturn "$" + Hex(v)
EndProcedure

Procedure.s DisReg(n.i)
  If n < 8
    ProcedureReturn "D" + Str(n)
  ElseIf n = 15
    ProcedureReturn "SP"
  EndIf
  ProcedureReturn "A" + Str(n - 8)
EndProcedure

; The text of effective address (mode, reg) of size sz (0 B, 1 W, 2 L).
Procedure.s DisEa(mode.i, reg.i, sz.i)
  Protected w.i, d.i, x.s, pc.i
  Select mode
    Case 0 : ProcedureReturn "D" + Str(reg)
    Case 1 : ProcedureReturn DisReg(reg + 8)
    Case 2 : ProcedureReturn "(" + DisReg(reg + 8) + ")"
    Case 3 : ProcedureReturn "(" + DisReg(reg + 8) + ")+"
    Case 4 : ProcedureReturn "-(" + DisReg(reg + 8) + ")"
    Case 5
      d = Sx16(DisNext())
      ProcedureReturn DisSigned(d) + "(" + DisReg(reg + 8) + ")"
    Case 6
      w = DisNext()
      x = DisReg((w >> 12) & 15)
      If w & $800 : x + ".L" : Else : x + ".W" : EndIf
      d = ((w & $FF) ! $80) - $80
      ProcedureReturn DisSigned(d) + "(" + DisReg(reg + 8) + "," + x + ")"
    Case 7
      Select reg
        Case 0
          w = Sx16(DisNext())
          ProcedureReturn DisHex(w & $FFFFFF, 4) + ".W"
        Case 1
          w = DisNext() << 16
          w | DisNext()
          ProcedureReturn DisHex(w, 6)
        Case 2
          pc = DisPc
          d = Sx16(DisNext())
          ProcedureReturn DisHex((pc + d) & $FFFFFF, 6) + "(PC)"
        Case 3
          pc = DisPc
          w = DisNext()
          x = DisReg((w >> 12) & 15)
          If w & $800 : x + ".L" : Else : x + ".W" : EndIf
          d = ((w & $FF) ! $80) - $80
          ProcedureReturn DisHex((pc + d) & $FFFFFF, 6) + "(PC," + x + ")"
        Case 4
          If sz = 2
            w = DisNext() << 16
            w | DisNext()
            ProcedureReturn "#" + DisHex(w, 8)
          ElseIf sz = 1
            ProcedureReturn "#" + DisHex(DisNext(), 4)
          EndIf
          ProcedureReturn "#" + DisHex(DisNext() & $FF, 2)
      EndSelect
  EndSelect
  ProcedureReturn "?"
EndProcedure

Procedure.s DisSz(sz.i)
  ProcedureReturn StringField(".B|.W|.L", sz + 1, "|")
EndProcedure

Procedure.s DisCc(c.i)
  ProcedureReturn StringField("T|F|HI|LS|CC|CS|NE|EQ|VC|VS|PL|MI|GE|LT|GT|LE", c + 1, "|")
EndProcedure

Procedure.s DisRegList(mask.i, rev.i)
  Protected r.i, s.s, i.i, bit.i
  For r = 0 To 15
    i = r
    If rev : i = 15 - r : EndIf
    If mask & (1 << i)
      If s <> "" : s + "/" : EndIf
      s + DisReg(r)
    EndIf
  Next
  ProcedureReturn s
EndProcedure

; One instruction at addr.
Procedure.s Dis68k(addr.i)
  Protected op.i, line.i, s.s, sz.i, mode.i, reg.i, rg.i, om.i, d.i, w.i, t.s, pc.i, cnt.i
  DisBad = 0
  DisPc = addr
  op = DisNext()
  line = op >> 12
  mode = (op >> 3) & 7
  reg = op & 7
  rg = (op >> 9) & 7
  om = (op >> 6) & 7
  s = "DC.W " + DisHex(op, 4)
  Select line
    Case 0
      If op & $100
        If mode = 1
          t = StringField("MOVEP.W|MOVEP.L|MOVEP.W|MOVEP.L", ((op >> 6) & 3) + 1, "|")
          d = Sx16(DisNext())
          If op & $80
            s = t + " D" + Str(rg) + "," + DisSigned(d) + "(A" + Str(reg) + ")"
          Else
            s = t + " " + DisSigned(d) + "(A" + Str(reg) + "),D" + Str(rg)
          EndIf
        Else
          s = StringField("BTST|BCHG|BCLR|BSET", ((op >> 6) & 3) + 1, "|") + " D" + Str(rg) + "," + DisEa(mode, reg, 0)
        EndIf
      ElseIf rg = 4
        w = DisNext()
        s = StringField("BTST|BCHG|BCLR|BSET", ((op >> 6) & 3) + 1, "|") + " #" + Str(w & 255) + "," + DisEa(mode, reg, 0)
      Else
        sz = (op >> 6) & 3
        t = StringField("ORI|ANDI|SUBI|ADDI||EORI|CMPI|", rg + 1, "|")
        If (op & $FF) = $3C
          s = t + " #" + DisHex(DisNext() & $FF, 2) + ",CCR"
        ElseIf (op & $FF) = $7C
          s = t + " #" + DisHex(DisNext(), 4) + ",SR"
        ElseIf t <> "" And sz < 3
          If sz = 2
            w = DisNext() << 16
            w | DisNext()
            t + DisSz(sz) + " #" + DisHex(w, 8)
          Else
            t + DisSz(sz) + " #" + DisHex(DisNext() & ($FF + sz * $FF00), 2 + sz * 2)
          EndIf
          s = t + "," + DisEa(mode, reg, sz)
        EndIf
      EndIf
    Case 1, 2, 3
      sz = Val(StringField("0|0|2|1", line + 1, "|"))
      t = DisEa(mode, reg, sz)
      If om = 1
        s = "MOVEA" + DisSz(sz) + " " + t + "," + DisReg(rg + 8)
      Else
        s = "MOVE" + DisSz(sz) + " " + t + "," + DisEa(om, rg, sz)
      EndIf
    Case 4
      If op = $4E70 : s = "RESET"
      ElseIf op = $4E71 : s = "NOP"
      ElseIf op = $4E72 : s = "STOP #" + DisHex(DisNext(), 4)
      ElseIf op = $4E73 : s = "RTE"
      ElseIf op = $4E75 : s = "RTS"
      ElseIf op = $4E76 : s = "TRAPV"
      ElseIf op = $4E77 : s = "RTR"
      ElseIf op = $4AFC : s = "ILLEGAL"
      ElseIf (op & $FFF0) = $4E40 : s = "TRAP #" + Str(op & 15)
      ElseIf (op & $FFF8) = $4E50 : s = "LINK A" + Str(reg) + ",#" + DisSigned(Sx16(DisNext()))
      ElseIf (op & $FFF8) = $4E58 : s = "UNLK A" + Str(reg)
      ElseIf (op & $FFF8) = $4E60 : s = "MOVE A" + Str(reg) + ",USP"
      ElseIf (op & $FFF8) = $4E68 : s = "MOVE USP,A" + Str(reg)
      ElseIf (op & $FFC0) = $4E80 : s = "JSR " + DisEa(mode, reg, 2)
      ElseIf (op & $FFC0) = $4EC0 : s = "JMP " + DisEa(mode, reg, 2)
      ElseIf (op & $FFC0) = $40C0 : s = "MOVE SR," + DisEa(mode, reg, 1)
      ElseIf (op & $FFC0) = $44C0 : s = "MOVE " + DisEa(mode, reg, 1) + ",CCR"
      ElseIf (op & $FFC0) = $46C0 : s = "MOVE " + DisEa(mode, reg, 1) + ",SR"
      ElseIf (op & $FFC0) = $4800 : s = "NBCD " + DisEa(mode, reg, 0)
      ElseIf (op & $FFF8) = $4840 : s = "SWAP D" + Str(reg)
      ElseIf (op & $FFC0) = $4840 : s = "PEA " + DisEa(mode, reg, 2)
      ElseIf (op & $FFF8) = $4880 : s = "EXT.W D" + Str(reg)
      ElseIf (op & $FFF8) = $48C0 : s = "EXT.L D" + Str(reg)
      ElseIf (op & $FB80) = $4880
        w = DisNext()
        sz = 1 + ((op >> 6) & 1)
        If op & $400
          s = "MOVEM" + DisSz(sz) + " " + DisEa(mode, reg, sz) + "," + DisRegList(w, 0)
        Else
          s = "MOVEM" + DisSz(sz) + " " + DisRegList(w, Bool(mode = 4)) + "," + DisEa(mode, reg, sz)
        EndIf
      ElseIf (op & $FFC0) = $4AC0 : s = "TAS " + DisEa(mode, reg, 0)
      ElseIf (op & $F1C0) = $4180 : s = "CHK " + DisEa(mode, reg, 1) + ",D" + Str(rg)
      ElseIf (op & $F1C0) = $41C0 : s = "LEA " + DisEa(mode, reg, 2) + ",A" + Str(rg)
      Else
        sz = (op >> 6) & 3
        If sz < 3
          t = StringField("NEGX|CLR|NEG|NOT||TST", ((op >> 9) & 7) + 1, "|")
          If ((op >> 8) & 1) = 0 And t <> ""
            s = t + DisSz(sz) + " " + DisEa(mode, reg, sz)
          EndIf
        EndIf
      EndIf
    Case 5
      If ((op >> 6) & 3) = 3
        If mode = 1
          pc = DisPc
          s = "DB" + DisCc((op >> 8) & 15) + " D" + Str(reg) + "," + DisHex((pc + Sx16(DisNext())) & $FFFFFF, 6)
        Else
          s = "S" + DisCc((op >> 8) & 15) + " " + DisEa(mode, reg, 0)
        EndIf
      Else
        sz = (op >> 6) & 3
        cnt = rg
        If cnt = 0 : cnt = 8 : EndIf
        t = "ADDQ"
        If op & $100 : t = "SUBQ" : EndIf
        s = t + DisSz(sz) + " #" + Str(cnt) + "," + DisEa(mode, reg, sz)
      EndIf
    Case 6
      pc = DisPc
      d = op & $FF
      If d = 0
        d = Sx16(DisNext())
      Else
        d = (d ! $80) - $80
      EndIf
      t = "B" + DisCc((op >> 8) & 15)
      If ((op >> 8) & 15) = 0 : t = "BRA" : EndIf
      If ((op >> 8) & 15) = 1 : t = "BSR" : EndIf
      s = t + " " + DisHex((pc + d) & $FFFFFF, 6)
    Case 7
      s = "MOVEQ #" + DisSigned(((op & $FF) ! $80) - $80) + ",D" + Str(rg)
    Case 8, 9, 11, 12, 13
      t = StringField("OR|SUB||CMP|AND|ADD", line - 7, "|")
      If line = 11 And om >= 4 And om <= 6 : t = "EOR" : EndIf
      If om = 3 Or om = 7
        If line = 8
          s = StringField("DIVU|DIVS", Bool(om = 7) + 1, "|") + " " + DisEa(mode, reg, 1) + ",D" + Str(rg)
        ElseIf line = 12
          s = StringField("MULU|MULS", Bool(om = 7) + 1, "|") + " " + DisEa(mode, reg, 1) + ",D" + Str(rg)
        Else
          sz = 1 + Bool(om = 7)
          s = t + "A" + DisSz(sz) + " " + DisEa(mode, reg, sz) + ",A" + Str(rg)
        EndIf
      ElseIf om < 3
        s = t + DisSz(om) + " " + DisEa(mode, reg, om) + ",D" + Str(rg)
      Else
        sz = om - 4
        If mode <= 1 And t <> "EOR"
          If line = 8 And sz = 0
            s = "SBCD " + StringField("D" + Str(reg) + ",D" + Str(rg) + "|-(A" + Str(reg) + "),-(A" + Str(rg) + ")", mode + 1, "|")
          ElseIf line = 12 And sz = 0
            s = "ABCD " + StringField("D" + Str(reg) + ",D" + Str(rg) + "|-(A" + Str(reg) + "),-(A" + Str(rg) + ")", mode + 1, "|")
          ElseIf line = 12 And sz = 1 And mode = 0
            s = "EXG D" + Str(rg) + ",D" + Str(reg)
          ElseIf line = 12 And sz = 1 And mode = 1
            s = "EXG A" + Str(rg) + ",A" + Str(reg)
          ElseIf line = 12 And sz = 2 And mode = 1
            s = "EXG D" + Str(rg) + ",A" + Str(reg)
          ElseIf line = 9 Or line = 13
            s = t + "X" + DisSz(sz) + " " + StringField("D" + Str(reg) + ",D" + Str(rg) + "|-(A" + Str(reg) + "),-(A" + Str(rg) + ")", mode + 1, "|")
          EndIf
        ElseIf t = "EOR" And mode = 1
          s = "CMPM" + DisSz(sz) + " (A" + Str(reg) + ")+,(A" + Str(rg) + ")+"
        Else
          s = t + DisSz(sz) + " D" + Str(rg) + "," + DisEa(mode, reg, sz)
        EndIf
      EndIf
    Case 10 : s = "LINE-A " + DisHex(op, 4)
    Case 14
      If ((op >> 6) & 3) = 3
        t = StringField("AS|LS|ROX|RO", ((op >> 9) & 3) + 1, "|") + StringField("R|L", ((op >> 8) & 1) + 1, "|")
        s = t + " " + DisEa(mode, reg, 1)
      Else
        sz = (op >> 6) & 3
        t = StringField("AS|LS|ROX|RO", ((op >> 3) & 3) + 1, "|") + StringField("R|L", ((op >> 8) & 1) + 1, "|")
        If op & $20
          s = t + DisSz(sz) + " D" + Str(rg) + ",D" + Str(reg)
        Else
          cnt = rg
          If cnt = 0 : cnt = 8 : EndIf
          s = t + DisSz(sz) + " #" + Str(cnt) + ",D" + Str(reg)
        EndIf
      EndIf
    Case 15 : s = "LINE-F " + DisHex(op, 4)
  EndSelect
  DisLen = DisPc - addr
  If DisBad
    s + "   (not readable here)"
  EndIf
  ProcedureReturn s
EndProcedure
