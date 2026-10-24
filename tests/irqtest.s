; Interrupt test ROM: level 3 (VERTB), level 2 (CIA-A timer A at 100 Hz, and the
; keyboard's serial port), autovectors, RTE. After 100 frames it reports the
; counts and the key codes the keyboard sent (power-up: $FD then $FE).
CUSTOM  = $DFF000
CIAA    = $BFE001
        ORG $FC0000
        dc.l $00080000
        dc.l Start

Start:  lea     CUSTOM,a6
        move.w  #$7FFF,$9A(a6)
        move.w  #$7FFF,$96(a6)
        move.w  #$7FFF,$9C(a6)
        move.b  #3,CIAA+$200
        move.b  #2,CIAA
        lea     $80000,sp
        move.w  #$0174,$32(a6)
        lea     Level2(pc),a0
        move.l  a0,$68          ; autovector 2
        lea     Level3(pc),a0
        move.l  a0,$6C          ; autovector 3
        clr.l   $100            ; VERTB count
        clr.l   $104            ; timer A count
        clr.l   $108            ; keys received
        clr.l   $10C            ; key codes (up to 4)
; CIA-A timer A: continuous, 7094 E clocks = 100 Hz
        move.b  #$7F,CIAA+$D00  ; ICR: all off
        move.b  #7094&255,CIAA+$400
        move.b  #7094>>8,CIAA+$500
        move.b  #$11,CIAA+$E00  ; CRA: start, continuous, force load
        move.b  #$89,CIAA+$D00  ; ICR: timer A and SP on
        move.w  #$C028,$9A(a6)  ; INTENA: master, VERTB, PORTS
        move.w  #$2000,sr       ; interrupts on
.wait:  cmp.l   #100,$100
        blo.s   .wait
        move.w  #$2700,sr
        lea     Msg1(pc),a0
        bsr     Say
        move.l  $100,d0
        bsr     Dec
        lea     Msg2(pc),a0
        bsr     Say
        move.l  $104,d0
        bsr     Dec
        lea     Msg3(pc),a0
        bsr     Say
        move.l  $108,d0
        bsr     Dec
        lea     Msg4(pc),a0
        bsr     Say
        move.l  $10C,d0
        lea     HexTab(pc),a2
        moveq   #7,d5
.hx:    rol.l   #4,d0
        move.w  d0,d1
        and.w   #15,d1
        move.b  0(a2,d1.w),d2
        bsr     PutC
        dbra    d5,.hx
        moveq   #10,d2
        bsr     PutC
.end:   bra.s   .end

Level3: move.w  #$0020,$DFF09C ; clear VERTB
        addq.l  #1,$100
        rte

Level2: movem.l d0-d1,-(sp)
        move.b  CIAA+$D00,d0    ; ICR (reading clears it)
        btst    #0,d0
        beq.s   .nota
        addq.l  #1,$104
.nota:  btst    #3,d0
        beq.s   .nosp
        move.b  CIAA+$C00,d1    ; SDR: the key
        not.b   d1
        ror.b   #1,d1
        move.l  $10C,d0
        lsl.l   #8,d0
        move.b  d1,d0
        move.l  d0,$10C
        addq.l  #1,$108
        ; the handshake: serial port to output for a while, then back to input
        bset    #6,CIAA+$E00
        move.w  #200,d0
.hs:    dbra    d0,.hs
        bclr    #6,CIAA+$E00
.nosp:  move.w  #$0008,$DFF09C ; clear PORTS
        movem.l (sp)+,d0-d1
        rte

; Dec: d0 in decimal
Dec:    lea     $200,a1
        clr.b   -(a1)
.d:     divu    #10,d0
        swap    d0
        add.b   #'0',d0
        move.b  d0,-(a1)
        clr.w   d0
        swap    d0
        tst.l   d0
        bne.s   .d
        move.l  a1,a0
        bra     Say

PutC:   btst    #13,$18(a6)
        beq.s   PutC
        and.w   #$FF,d2
        or.w    #$0100,d2
        move.w  d2,$30(a6)
        rts
Say:    move.b  (a0)+,d2
        beq.s   .end
        bsr     PutC
        bra.s   Say
.end:   rts

HexTab: dc.b "0123456789ABCDEF"
Msg1:   dc.b "irqtest: VERTB ",0
Msg2:   dc.b " timer A ",0
Msg3:   dc.b " keys ",0
Msg4:   dc.b " codes $",0
        EVEN
        ORG $FFFFFE
        dc.w 0
