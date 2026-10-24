; Loaded at $40000 by bootblock.s. Says so on the serial port, sums the 20 KB
; it was loaded as (mkadf.py prints the sum it must be), counts 50 VBLANK
; interrupts, turns the screen green.
CUSTOM  = $DFF000
PSIZE   = 20480
        ORG $40000
        lea     CUSTOM,a6
        move.w  #$7FFF,$9A(a6)
        lea     Hello(pc),a0
        bsr     Say
        lea     $40000,a0
        move.w  #(PSIZE/4)-1,d1
        moveq   #0,d0
.s:     add.l   (a0)+,d0
        dbra    d1,.s
        move.l  d0,d3
        lea     MsgSum(pc),a0
        bsr     Say
        move.l  d3,d0
        bsr     SayHex
        moveq   #10,d2
        bsr     PutC
        lea     Vbl(pc),a0
        move.l  a0,$6C
        clr.l   Count
        move.w  #$7FFF,$9C(a6)
        move.w  #$C020,$9A(a6)  ; INTEN | VERTB
        move    #$2000,sr
.w:     cmp.l   #50,Count
        blo.s   .w
        move.w  #$7FFF,$9A(a6)
        lea     MsgVbl(pc),a0
        bsr     Say
        move.w  #$00F0,$180(a6)
.done:  bra.s   .done
Vbl:    addq.l  #1,Count
        move.w  #$0020,$DFF09C
        rte
PutC:   btst    #13,$18(a6)
        beq.s   PutC
        and.w   #$FF,d2
        or.w    #$0100,d2
        move.w  d2,$30(a6)
        rts
Say:    move.b  (a0)+,d2
        beq.s   .e
        bsr     PutC
        bra.s   Say
.e:     rts
SayHex: moveq   #7,d4
.h:     rol.l   #4,d0
        move.l  d0,d2
        and.w   #15,d2
        move.b  Digits(pc,d2.w),d2
        move.l  d0,-(sp)
        bsr     PutC
        move.l  (sp)+,d0
        dbra    d4,.h
        rts
Digits: dc.b "0123456789ABCDEF"
Count:  dc.l 0
Hello:  dc.b "prog: loaded at $40000 by the bootblock",10,0
MsgSum: dc.b "prog: sum of the 20 KB = ",0
MsgVbl: dc.b "prog: 50 VBLANK interrupts",10,0
        EVEN
