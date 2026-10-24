; Disk test ROM: reads track 0 of DF0 the way trackdisk.device does - CIA-B
; selects the drive and turns the motor on, steps to track 0 (CIA-A /TK0),
; disk DMA reads a track after the sync word $4489, then the first sector is
; decoded (odd/even bits) and its first 16 bytes are sent on the serial port.
CUSTOM  = $DFF000
CIAA    = $BFE001
CIAB    = $BFD000
TRACK   = $020000
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
        lea     Hello(pc),a0
        bsr     Say
; CIA-B port B: all outputs, everything deselected (active low)
        move.b  #$FF,CIAB+$300  ; DDRB
        move.b  #$FF,CIAB+$100  ; PRB
; motor on for DF0: /MTR low, then select DF0 (the motor is latched on select)
        move.b  #$7F,CIAB+$100  ; /MTR = 0, all /SEL high
        move.b  #$77,CIAB+$100  ; /SEL0 = 0
; wait for /RDY (CIA-A PRA bit 5 low)
        move.l  #100000,d1
.rdy:   btst    #5,CIAA
        beq.s   .ready
        subq.l  #1,d1
        bne.s   .rdy
        lea     NoRdy(pc),a0
        bsr     Say
        bra     Done
.ready: lea     Ready(pc),a0
        bsr     Say
; step out to track 0: DIR = 1 (out), pulse /STEP while /TK0 is high
        moveq   #100,d2
.seek:  btst    #4,CIAA         ; /TK0
        beq.s   .at0
        move.b  #$77,CIAB+$100  ; DIR = 1 (bit 1 set), /STEP = 1
        move.b  #$76,CIAB+$100  ; /STEP = 0
        move.b  #$77,CIAB+$100  ; /STEP = 1
        bsr     Wait3ms
        subq.w  #1,d2
        bne.s   .seek
        lea     NoTk0(pc),a0
        bsr     Say
        bra     Done
.at0:   lea     AtTk0(pc),a0
        bsr     Say
        move.b  #$73,CIAB+$100  ; /SIDE = 0: the upper head... side 0 is /SIDE = 1
        move.b  #$77,CIAB+$100  ; side 0 (/SIDE = 1)
; disk DMA: sync on $4489, read 6400 words to TRACK
        move.w  #$7F00,$9E(a6)  ; ADKCON: clear precomp, MFMPREC, UARTBRK, WORDSYNC, MSBSYNC, FAST
        move.w  #$9500,$9E(a6)  ; ADKCON: set MFMPREC, WORDSYNC, FAST
        move.w  #$4489,$7E(a6)  ; DSKSYNC
        move.l  #TRACK,$20(a6)  ; DSKPT
        move.w  #$8210,$96(a6)  ; DMAEN | DSKEN
        move.w  #$0002,$9C(a6)  ; clear DSKBLK
        move.w  #$8000+6400,$24(a6) ; DSKLEN (twice)
        move.w  #$8000+6400,$24(a6)
        move.l  #4000000,d1
.wd:    btst    #1,$1F(a6)      ; INTREQR DSKBLK (low byte)
        bne.s   .done
        subq.l  #1,d1
        bne.s   .wd
        lea     NoBlk(pc),a0
        bsr     Say
        bra     Done
.done:  move.w  #$4000,$24(a6)  ; DMA off
        lea     GotBlk(pc),a0
        bsr     Say
; the track starts after the first sync: find the sector with sector number 0
        lea     TRACK,a1
        move.w  #6000,d7
.find:  cmp.w   #$4489,(a1)
        bne.s   .nxt
        cmp.w   #$4489,2(a1)
        beq.s   .nxt
        ; a1 points at the second sync word: the info long follows it
        move.l  2(a1),d0
        and.l   #$55555555,d0
        lsl.l   #1,d0
        move.l  6(a1),d1
        and.l   #$55555555,d1
        or.l    d1,d0           ; info: $FF tt ss nn
        move.l  d0,d6
        lsr.l   #8,d6
        and.w   #$FF,d6         ; sector number
        tst.w   d6
        beq.s   .sec0
.nxt:   addq.l  #2,a1
        dbra    d7,.find
        lea     NoSec(pc),a0
        bsr     Say
        bra     Done
.sec0:  ; data: 28 words after the info's first word (info 4, label 16, checks 8)
        lea     58(a1),a2       ; odd longs
        lea     512(a2),a3      ; even longs
        lea     Out(pc),a0
        moveq   #3,d7
.dec:   move.l  (a2)+,d0
        and.l   #$55555555,d0
        lsl.l   #1,d0
        move.l  (a3)+,d1
        and.l   #$55555555,d1
        or.l    d1,d0
        moveq   #7,d5
.hex:   rol.l   #4,d0
        move.w  d0,d1
        and.w   #15,d1
        move.b  HexTab(pc,d1.w),d2
        bsr     PutC
        dbra    d5,.hex
        moveq   #32,d2
        bsr     PutC
        dbra    d7,.dec
        moveq   #10,d2
        bsr     PutC
Done:   lea     Bye(pc),a0
        bsr     Say
.loop:  bra.s   .loop

HexTab: dc.b "0123456789ABCDEF"
        EVEN
; about 3 ms on a 7 MHz 68000
Wait3ms:
        move.w  #2000,d0
.w:     dbra    d0,.w
        rts

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

Out:    dc.b 0
Hello:  dc.b "disktest: DF0 motor on",10,0
Ready:  dc.b "disktest: drive ready",10,0
NoRdy:  dc.b "disktest: FAIL no /RDY",10,0
AtTk0:  dc.b "disktest: at track 0",10,0
NoTk0:  dc.b "disktest: FAIL never reached track 0",10,0
NoBlk:  dc.b "disktest: FAIL no DSKBLK interrupt",10,0
GotBlk: dc.b "disktest: track read by DMA",10,0
NoSec:  dc.b "disktest: FAIL sector 0 not found",10,0
Bye:    dc.b "disktest: end",10,0
        EVEN
        ORG $FFFFFE
        dc.w 0
