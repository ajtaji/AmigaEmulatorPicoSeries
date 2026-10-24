; Chip test ROM: a 256 KB ROM image at $FC0000 (also seen at $F80000 and,
; through the overlay, at $000000 after reset). It turns the overlay off,
; builds a copper list (a colour per line), a 320x256 one-bitplane screen
; filled by the CPU and by the blitter, a sprite, and says what it did on the
; serial port. Used by the desktop runner and the Pico build as a smoke test.
CUSTOM  = $DFF000
CIAA    = $BFE001
COPLIST = $001000
SCREEN  = $010000
SPRDATA = $002000

        ORG $FC0000
        dc.l $00080000          ; reset SSP
        dc.l Start              ; reset PC

Start:  lea     CUSTOM,a6
        move.w  #$7FFF,$9A(a6)  ; INTENA: all off
        move.w  #$7FFF,$96(a6)  ; DMACON: all off
        move.w  #$7FFF,$9C(a6)  ; INTREQ: clear
        move.b  #3,CIAA+$200    ; CIA-A DDRA: OVL and LED are outputs
        move.b  #2,CIAA         ; OVL = 0: chip RAM at $000000
        lea     $80000,sp
        move.w  #$0174,$32(a6)  ; SERPER 19200 baud
        lea     Hello(pc),a0
        bsr     Say

; clear the screen (40 bytes x 256 lines)
        lea     SCREEN,a0
        move.w  #(40*256/4)-1,d0
.clr:   clr.l   (a0)+
        dbra    d0,.clr
; CPU: a checker band in the top 32 lines
        lea     SCREEN,a0
        moveq   #31,d1
.row:   moveq   #9,d0
        move.l  #$FF00FF00,d2
        btst    #3,d1
        beq.s   .col
        not.l   d2
.col:   move.l  d2,(a0)+
        dbra    d0,.col
        dbra    d1,.row

; blitter: fill a 128x64 block at x=96, y=96 (D = $FFFF, minterm $FF)
        move.w  #$8240,$96(a6)  ; DMAEN | BLTEN
        move.w  #$01FF,$40(a6)  ; BLTCON0: use D, LF = $FF
        move.w  #0,$42(a6)      ; BLTCON1
        move.l  #SCREEN+96*40+12,$54(a6) ; BLTDPT
        move.w  #40-16,$66(a6)  ; BLTDMOD
        move.w  #(64<<6)|8,$58(a6) ; BLTSIZE: 64 lines of 8 words
.wb:    btst    #6,$02(a6)      ; DMACONR BBUSY
        bne.s   .wb
; a second blit: an XOR of an 80x48 block over it (A = $FFFF from BLTADAT)
        move.w  #$035A,$40(a6)  ; use C and D, D = A xor C (A from BLTADAT)
        move.w  #$FFFF,$74(a6)  ; BLTADAT
        move.w  #$FFFF,$44(a6)
        move.w  #$FFFF,$46(a6)
        move.l  #SCREEN+120*40+18,$48(a6) ; BLTCPT
        move.l  #SCREEN+120*40+18,$54(a6) ; BLTDPT
        move.w  #40-10,$60(a6)
        move.w  #40-10,$66(a6)
        move.w  #(48<<6)|5,$58(a6)
.wb2:   btst    #6,$02(a6)
        bne.s   .wb2

; blitter lines and fill: a triangle (250,40) (300,150) (210,120), its edges
; drawn one dot per line with XOR, then filled (descending, inclusive)
        move.w  #250,d0
        move.w  #40,d1
        move.w  #300,d2
        move.w  #150,d3
        bsr     Line
        move.w  #300,d0
        move.w  #150,d1
        move.w  #210,d2
        move.w  #120,d3
        bsr     Line
        move.w  #210,d0
        move.w  #120,d1
        move.w  #250,d2
        move.w  #40,d3
        bsr     Line
        move.w  #$09F0,$40(a6)  ; A -> D
        move.w  #$000A,$42(a6)  ; inclusive fill, descending
        move.l  #SCREEN+150*40+38,d0 ; the last word of the area (x 208..319, y 40..150)
        move.l  d0,$50(a6)      ; BLTAPT
        move.l  d0,$54(a6)      ; BLTDPT
        move.w  #$FFFF,$44(a6)
        move.w  #$FFFF,$46(a6)
        move.w  #40-14,$64(a6)  ; BLTAMOD
        move.w  #40-14,$66(a6)  ; BLTDMOD
        move.w  #(111<<6)|7,$58(a6)
.wb3:   btst    #6,$02(a6)
        bne.s   .wb3

; the sprite: 16 lines of a diamond at (160, 100)
        lea     SPRDATA,a0
        move.w  #$6450,(a0)+    ; SPR0POS: VSTART $64, HSTART $50*2
        move.w  #$7400,(a0)+    ; SPR0CTL: VSTOP $74
        lea     Diamond(pc),a1
        moveq   #15,d0
.sp:    move.l  (a1)+,(a0)+
        dbra    d0,.sp
        clr.l   (a0)+
        move.w  #$0F00,$1A2(a6) ; COLOR17 red
        move.w  #$0FF0,$1A4(a6) ; COLOR18 yellow
        move.w  #$0FFF,$1A6(a6) ; COLOR19 white
        move.l  #SPRDATA,$120(a6) ; SPR0PT
        lea     $124(a6),a0     ; the other sprites point at an empty one
        moveq   #6,d0
.nsp:   move.l  #SPRDATA+16*4+4,(a0)+
        dbra    d0,.nsp

; the copper list: bitplane pointer, then COLOR00 changes every line
        lea     COPLIST,a0
        move.l  #$00E00001,(a0)+ ; BPL1PTH = $0001
        move.l  #$00E20000,(a0)+ ; BPL1PTL = $0000
        move.w  #$0120,(a0)+    ; SPR0PTH / SPR0PTL, every frame
        move.w  #SPRDATA>>16,(a0)+
        move.w  #$0122,(a0)+
        move.w  #SPRDATA&$FFFF,(a0)+
        move.w  #$0124,d3       ; SPR1PT-SPR7PT: the empty sprite
        moveq   #6,d4
.cs:    move.w  d3,(a0)+
        move.w  #(SPRDATA+16*4+4)>>16,(a0)+
        addq.w  #2,d3
        move.w  d3,(a0)+
        move.w  #(SPRDATA+16*4+4)&$FFFF,(a0)+
        addq.w  #2,d3
        dbra    d4,.cs
        move.w  #$2C07,d0       ; WAIT line $2C
        moveq   #0,d1
        move.w  #255,d2
.cl:    move.w  d0,(a0)+
        move.w  #$FFFE,(a0)+
        move.w  #$0180,(a0)+    ; COLOR00
        move.w  d1,d3
        lsr.w   #4,d3
        and.w   #$000F,d3
        move.w  d3,(a0)+
        add.w   #$0100,d0
        addq.w  #1,d1
        dbra    d2,.cl
        move.l  #$FFFFFFFE,(a0)+ ; end
        move.l  #COPLIST,$80(a6) ; COP1LC
        move.w  #0,$88(a6)      ; COPJMP1

        move.w  #$1200,$100(a6) ; BPLCON0: 1 plane, colour
        move.w  #0,$102(a6)
        move.w  #$0024,$104(a6) ; BPLCON2: sprites in front
        move.w  #0,$108(a6)
        move.w  #0,$10A(a6)
        move.w  #$2C81,$8E(a6)  ; DIWSTRT
        move.w  #$2CC1,$90(a6)  ; DIWSTOP
        move.w  #$0038,$92(a6)  ; DDFSTRT
        move.w  #$00D0,$94(a6)  ; DDFSTOP
        move.w  #$0FFF,$182(a6) ; COLOR01 white
        move.w  #$83E0,$96(a6)  ; DMAEN BPLEN COPEN BLTEN SPREN

        lea     Done(pc),a0
        bsr     Say
; count frames by VERTB, flash the LED, say a dot every 50 frames
        moveq   #0,d7
.frame: move.w  $1E(a6),d0      ; INTREQR
        btst    #5,d0
        beq.s   .frame
        move.w  #$0020,$9C(a6)  ; clear VERTB
        addq.l  #1,d7
        move.l  d7,d0
        divu    #50,d0
        swap    d0
        tst.w   d0
        bne.s   .frame
        bchg    #1,CIAA         ; the power LED
        move.w  #$012E,$30(a6)  ; SERDAT '.'
        bra.s   .frame

; Line: (d0,d1)-(d2,d3) on SCREEN (40 bytes a line), one dot per line, XOR
Line:   movem.l d0-d7/a0,-(sp)
        cmp.w   d1,d3           ; draw downwards (y1 <= y2)
        bge.s   .down
        exg     d0,d2
        exg     d1,d3
.down:  moveq   #0,d7           ; octant bits
        move.w  d2,d4
        sub.w   d0,d4           ; dx
        bge.s   .dxp
        neg.w   d4
        moveq   #1,d7           ; x goes left
.dxp:   move.w  d3,d5
        sub.w   d1,d5           ; dy (>= 0)
        cmp.w   d5,d4
        bge.s   .xmaj
        ; y major: SUD = 0, AUL = dy < 0 (never), SUL = dx < 0
        move.w  d4,d6           ; dmin
        move.w  d5,d4           ; dmax
        move.w  d6,d5
        moveq   #0,d6
        tst.w   d7
        beq.s   .oct
        moveq   #$08,d6         ; SUL
        bra.s   .oct
.xmaj:  ; x major: SUD = 1, AUL = dx < 0, SUL = dy < 0 (never)
        moveq   #$10,d6
        tst.w   d7
        beq.s   .oct
        moveq   #$14,d6         ; SUD | AUL
.oct:   ; d4 = dmax, d5 = dmin
        lea     SCREEN,a0
        mulu    #40,d1
        add.l   d1,a0
        move.w  d0,d1
        lsr.w   #3,d1
        and.w   #$FFFE,d1
        add.w   d1,a0
        and.w   #15,d0
        ror.w   #4,d0
        or.w    #$0B4A,d0       ; A C D, minterm XOR
.wbl:   btst    #6,$02(a6)
        bne.s   .wbl
        move.w  d0,$40(a6)
        add.w   d5,d5
        add.w   d5,d5           ; 4 dmin
        move.w  d5,$62(a6)      ; BLTBMOD
        move.w  d5,d1
        sub.w   d4,d1
        sub.w   d4,d1           ; 4 dmin - 2 dmax
        bge.s   .pos
        or.w    #$40,d6         ; SIGN
.pos:   or.w    #$03,d6         ; LINE | SING
        move.w  d6,$42(a6)
        move.w  d1,$52(a6)      ; BLTAPTL
        sub.w   d4,d1
        sub.w   d4,d1           ; 4 dmin - 4 dmax
        move.w  d1,$64(a6)      ; BLTAMOD
        move.l  a0,$48(a6)      ; BLTCPT
        move.l  a0,$54(a6)      ; BLTDPT
        move.w  #40,$60(a6)
        move.w  #40,$66(a6)
        move.w  #$8000,$74(a6)  ; BLTADAT
        move.w  #$FFFF,$72(a6)  ; BLTBDAT
        move.w  #$FFFF,$44(a6)
        move.w  #$FFFF,$46(a6)
        addq.w  #1,d4
        lsl.w   #6,d4
        addq.w  #2,d4
        move.w  d4,$58(a6)      ; BLTSIZE: (dmax + 1) lines, 2 words
.wbl2:  btst    #6,$02(a6)
        bne.s   .wbl2
        movem.l (sp)+,d0-d7/a0
        rts

; Say: send the 0-terminated text at (a0) on the serial port
Say:    move.b  (a0)+,d0
        beq.s   .end
.tbe:   btst    #13,$18(a6)     ; SERDATR TBE
        beq.s   .tbe
        and.w   #$FF,d0
        or.w    #$0100,d0       ; stop bit
        move.w  d0,$30(a6)
        bra.s   Say
.end:   rts

Hello:  dc.b "chiptest: overlay off, CPU and blitter drawing",10,0
Done:   dc.b "chiptest: copper, bitplane and sprite DMA on",10,0
        EVEN
Diamond:
        dc.w $0180,$0000, $03C0,$0180, $07E0,$03C0, $0FF0,$07E0
        dc.w $1FF8,$0FF0, $3FFC,$1FF8, $7FFE,$3FFC, $FFFF,$7FFE
        dc.w $FFFF,$7FFE, $7FFE,$3FFC, $3FFC,$1FF8, $1FF8,$0FF0
        dc.w $0FF0,$07E0, $07E0,$03C0, $03C0,$0180, $0180,$0000

        ORG $FFFFFE
        dc.w $0000
