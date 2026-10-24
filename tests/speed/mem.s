; Speed probe (mem): one five-instruction loop forever, interrupts and DMA off.
; The board's "cpu kcycles/s" line divided by the loop's cycles gives instructions/s.
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
        lea     $8000,a5
        moveq   #1,d1
.outer: moveq   #-1,d5
.loop:  move.w  -$10(a5),d0
        move.w  d0,-$20(a5)
        cmp.w   -$30(a5),d0
        move.w  d0,-$40(a5)
        dbra    d5,.loop
        bra.s   .outer
        ORG $FFFFFE
        dc.w 0
