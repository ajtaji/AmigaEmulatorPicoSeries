; CPU speed: 2,000,000 iterations of a five-instruction loop (ADD.L, EOR.L,
; LSL.L, MOVE.W to memory, DBRA nested) - 10 M instructions - between two
; serial messages. Interrupts and DMA off: the CPU alone.
CUSTOM  = $DFF000
CIAA    = $BFE001
        ORG $FC0000
        dc.l $00080000
        dc.l Start
Start:  lea     CUSTOM,a6
        move.w  #$7FFF,$9A(a6)
        move.w  #$7FFF,$96(a6)
        move.b  #3,CIAA+$200
        move.b  #2,CIAA
        lea     $80000,sp
        move.w  #$0174,$32(a6)
        lea     Go(pc),a0
        bsr     Say
        lea     $1000,a1
        moveq   #1,d1
        moveq   #0,d0
        moveq   #29,d5          ; 30 x 65536 = 1,966,080 iterations
.outer: moveq   #-1,d4
.loop:  add.l   d1,d0
        eor.l   d0,d2
        lsl.l   #1,d3
        move.w  d0,(a1)
        dbra    d4,.loop
        dbra    d5,.outer
        lea     Stop(pc),a0
        bsr     Say
.end:   bra.s   .end
Say:    move.b  (a0)+,d2
        beq.s   .e
.t:     btst    #13,$18(a6)
        beq.s   .t
        and.w   #$FF,d2
        or.w    #$100,d2
        move.w  d2,$30(a6)
        bra.s   Say
.e:     rts
Go:     dc.b "bench: go",10,0
Stop:   dc.b "bench: stop (9,830,400 instructions)",10,0
        EVEN
        ORG $FFFFFE
        dc.w 0
