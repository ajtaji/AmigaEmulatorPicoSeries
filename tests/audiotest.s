; Audio test ROM: channel 0 plays a 32-byte square wave by DMA at period 222
; (3546895 / 222 / 32 = 499.3 Hz) at volume 64, channel 1 one octave up at
; volume 32; the AUD0 interrupt (level 4) counts buffer restarts.
CUSTOM  = $DFF000
CIAA    = $BFE001
WAVE    = $001000
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
        lea     WAVE,a0
        moveq   #15,d0
.h:     move.b  #$60,(a0)+
        dbra    d0,.h
        moveq   #15,d0
.l:     move.b  #$A0,(a0)+
        dbra    d0,.l
        lea     Level4(pc),a0
        move.l  a0,$70
        clr.l   $100
        move.l  #WAVE,$A0(a6)   ; AUD0LC
        move.w  #16,$A4(a6)     ; AUD0LEN (words)
        move.w  #222,$A6(a6)    ; AUD0PER
        move.w  #64,$A8(a6)     ; AUD0VOL
        move.l  #WAVE,$B0(a6)
        move.w  #16,$B4(a6)
        move.w  #111,$B6(a6)
        move.w  #32,$B8(a6)
        move.w  #$C080,$9A(a6)  ; INTENA: master, AUD0
        move.w  #$8203,$96(a6)  ; DMAEN, AUD0, AUD1
        move.w  #$2000,sr
.w:     cmp.l   #500,$100       ; one second of buffers
        blo.s   .w
        move.w  #$2700,sr
        lea     Msg(pc),a0
.s:     move.b  (a0)+,d2
        beq.s   .e
.t:     btst    #13,$18(a6)
        beq.s   .t
        and.w   #$FF,d2
        or.w    #$100,d2
        move.w  d2,$30(a6)
        bra.s   .s
.e:     bra.s   .e
Level4: move.w  #$0080,$DFF09C
        addq.l  #1,$100
        rte
Msg:    dc.b "audiotest: 500 AUD0 interrupts",10,0
        EVEN
        ORG $FFFFFE
        dc.w 0
