; The emulator's own boot ROM: starts a bootable disk with no Kickstart.
;
; It does what Kickstart's strap does for a disk that takes the machine over:
; reads the bootblock (sectors 0-1) from DF0 by disk DMA, checks "DOS" and the
; checksum, and enters it at +12 with A1 = a trackdisk request and A6 = a small
; ExecBase. The ExecBase's jump table holds what bootblocks use: AllocMem,
; AllocAbs, FreeMem, DoIO / SendIO / WaitIO / CheckIO (trackdisk CMD_READ,
; TD_MOTOR, CMD_UPDATE, CMD_CLEAR, TD_CHANGESTATE...), FindResident (none),
; Forbid / Permit / Disable / Enable, OpenLibrary (none), CacheClearU. Any
; other entry stops with its offset on the serial port and a red screen: loud,
; never a silent wrong answer. If the bootblock returns with D0 = 0 it jumps
; to A0, as the strap does.
;
; Assembled by tools/asm68k.py into bootrom/bootrom.rom (256 KB at $FC0000).

CUSTOM  = $DFF000
CIAA    = $BFE001
CIAB    = $BFD000
EXEC    = $000800           ; the ExecBase; its jump table below it
NLVO    = 140               ; jump table entries (-6 .. -840)
IOREQ   = $000C00           ; the trackdisk request handed to the bootblock
BOOTBLK = $001000           ; the bootblock (1024 bytes)
TRKRAW  = $07C000           ; one track of MFM words (6400 words)
TRKDATA = $07A000           ; that track decoded: 11 sectors x 512
ALLOCLO = $002000           ; AllocMem's first byte
STACKTOP = $07A000

; variables (low memory, below the ExecBase's jump table)
CURCYL  = $000100           ; head position (cylinder)
TRKNUM  = $000104           ; the track held in TRKDATA, -1 none
ALLOCP  = $000108           ; AllocMem's next byte
RESULT  = $00010C           ; DoIO error

        ORG $FC0000
        dc.l STACKTOP
        dc.l Reset

Reset:  lea     CUSTOM,a6
        move.w  #$7FFF,$9A(a6)
        move.w  #$7FFF,$96(a6)
        move.w  #$7FFF,$9C(a6)
        move.b  #3,CIAA+$200    ; OVL, LED outputs
        move.b  #2,CIAA         ; OVL off: chip RAM at 0
        lea     STACKTOP,sp
        move.w  #$0174,$32(a6)  ; SERPER
        move.w  #$0444,$180(a6) ; grey while starting
        move.b  #$FF,CIAB+$300  ; CIA-B port B: drive control outputs
        move.b  #$FF,CIAB+$100
        lea     Hello(pc),a0
        bsr     Say
; exception vectors: everything to a loud stop, autovectors to quiet ones
        lea     $8,a0
        lea     Unexpected(pc),a1
        moveq   #61,d0
.vec:   move.l  a1,(a0)+
        dbra    d0,.vec
        lea     IntQuiet(pc),a1
        lea     $64,a0
        moveq   #6,d0
.av:    move.l  a1,(a0)+
        dbra    d0,.av
; the ExecBase
        bsr     MakeExec
        move.l  #-1,TRKNUM
        clr.l   CURCYL
        move.l  #ALLOCLO,ALLOCP
; DF0: motor on, to cylinder 0
        bsr     MotorOn
        bsr     Seek0
; the bootblock: sectors 0 and 1
        lea     IOREQ,a1
        move.w  #2,28(a1)       ; CMD_READ
        move.l  #1024,36(a1)
        move.l  #BOOTBLK,40(a1)
        clr.l   44(a1)
        lea     EXEC,a6
        jsr     -456(a6)        ; DoIO
        tst.b   31(a1)
        bne     NoDisk
        cmp.l   #$444F5300,BOOTBLK ; "DOS" and a flag byte
        blo     NotBoot
        cmp.l   #$444F5307,BOOTBLK
        bhi     NotBoot
        ; checksum: the sum of the 256 longs, with each carry added back, is $FFFFFFFF
        lea     BOOTBLK,a0
        moveq   #0,d0
        move.w  #255,d1
.sum:   add.l   (a0)+,d0
        bcc.s   .nc
        addq.l  #1,d0
.nc:    dbra    d1,.sum
        not.l   d0
        bne     BadSum
        lea     CUSTOM,a6
        lea     Booting(pc),a0
        bsr     Say
        move.w  #$0000,$180(a6)
        lea     IOREQ,a1
        lea     EXEC,a6
        jsr     BOOTBLK+12
        tst.l   d0
        bne     BootFailed
        jmp     (a0)            ; the strap's way: D0 = 0, A0 = what to call

; ---------------------------------------------------------------- the ExecBase
MakeExec:
        lea     EXEC,a6
        ; the jump table: entry n at -6n is JSR Lvo_n (the slot is found from the return address)
        move.l  a6,a0
        move.w  #NLVO-1,d0
.jt:    subq.l  #6,a0
        move.w  #$4EB9,(a0)     ; JSR abs.L
        lea     Unimpl(pc),a1
        move.l  a1,2(a0)
        dbra    d0,.jt
        ; the entries that exist: JMP abs.L
        lea     LvoTable(pc),a2
.lt:    move.w  (a2)+,d0        ; the offset (negative)
        beq.s   .ltend
        move.w  (a2)+,d1        ; the handler, relative to LvoTable
        lea     LvoTable(pc),a1
        add.w   d1,a1
        move.w  #$4EF9,0(a6,d0.w)
        move.l  a1,2(a6,d0.w)
        bra.s   .lt
.ltend: ; the base itself
        move.l  a6,a0
        moveq   #(632/4)-1,d0
.clr:   clr.l   (a0)+
        dbra    d0,.clr
        move.w  #34,20(a6)      ; lib_Version
        move.w  #NLVO*6,16(a6)  ; lib_NegSize
        move.w  #632,18(a6)     ; lib_PosSize
        move.l  #$80000,62(a6)  ; MaxLocMem
        move.b  #50,530(a6)     ; VBlankFrequency
        move.b  #50,531(a6)     ; PowerSupplyFrequency
        move.l  a6,4            ; SysBase
        ; the trackdisk request
        lea     IOREQ,a1
        moveq   #(48/4)-1,d0
.ci:    clr.l   (a1)+
        dbra    d0,.ci
        rts

; offset, handler - LvoTable (0 ends)
LvoTable:
        dc.w    -120,LvDisable-LvoTable
        dc.w    -126,LvEnable-LvoTable
        dc.w    -132,LvNop-LvoTable     ; Forbid
        dc.w    -138,LvNop-LvoTable     ; Permit
        dc.w    -96,LvZero-LvoTable     ; FindResident: none
        dc.w    -198,LvAllocMem-LvoTable
        dc.w    -204,LvAllocAbs-LvoTable
        dc.w    -210,LvNop-LvoTable     ; FreeMem
        dc.w    -216,LvAvailMem-LvoTable
        dc.w    -456,LvDoIO-LvoTable
        dc.w    -462,LvDoIO-LvoTable    ; SendIO: done at once
        dc.w    -468,LvCheckIO-LvoTable
        dc.w    -474,LvWaitIO-LvoTable
        dc.w    -408,LvZero-LvoTable    ; OldOpenLibrary: none
        dc.w    -552,LvZero-LvoTable    ; OpenLibrary: none
        dc.w    -414,LvNop-LvoTable     ; CloseLibrary
        dc.w    -636,LvNop-LvoTable     ; CacheClearU
        dc.w    -642,LvNop-LvoTable     ; CacheClearE
        dc.w    -150,LvSuper-LvoTable   ; SuperState: already supervisor
        dc.w    -156,LvNop-LvoTable     ; UserState
        dc.w    0

LvNop:  rts
LvZero: moveq   #0,d0
        rts
LvDisable:
        move.w  #$4000,$DFF09A
        rts
LvEnable:
        move.w  #$C000,$DFF09A
        rts
LvSuper:
        moveq   #0,d0
        rts
LvAllocAbs:                     ; d0 = size, a1 = where -> d0 = a1
        move.l  a1,d0
        rts
LvAllocMem:                     ; d0 = size, d1 = flags -> d0 (cleared when MEMF_CLEAR)
        movem.l d1-d2/a0,-(sp)
        addq.l  #7,d0
        and.w   #$FFF8,d0
        move.l  ALLOCP,a0
        move.l  a0,d2
        add.l   d0,d2
        cmp.l   #TRKDATA,d2
        bhi.s   .none
        move.l  d2,ALLOCP
        move.l  a0,-(sp)
        btst    #16,d1          ; MEMF_CLEAR
        beq.s   .ok
        lsr.l   #2,d0
        bra.s   .cl2
.cl:    clr.l   (a0)+
.cl2:   subq.l  #1,d0
        bpl.s   .cl
.ok:    move.l  (sp)+,d0
        movem.l (sp)+,d1-d2/a0
        rts
.none:  movem.l (sp)+,d1-d2/a0
        moveq   #0,d0
        rts
LvAvailMem:
        move.l  #TRKDATA,d0
        sub.l   ALLOCP,d0
        rts
LvCheckIO:
        move.l  a1,d0
        rts
LvWaitIO:
        moveq   #0,d0
        move.b  31(a1),d0
        ext.w   d0
        ext.l   d0
        rts

; DoIO on the trackdisk request in A1: io_Command 28, io_Error 31, io_Actual 32,
; io_Length 36, io_Data 40, io_Offset 44.
LvDoIO: movem.l d1-d7/a0-a6,-(sp)
        lea     CUSTOM,a6
        clr.b   31(a1)
        clr.l   32(a1)
        move.w  28(a1),d0
        cmp.w   #2,d0           ; CMD_READ
        beq.s   .read
        cmp.w   #9,d0           ; TD_MOTOR: io_Actual = the old state
        beq.s   .motor
        cmp.w   #14,d0          ; TD_CHANGESTATE: 0 = a disk is in
        beq.s   .done
        cmp.w   #15,d0          ; TD_PROTSTATUS
        beq.s   .done
        bra.s   .done           ; CMD_UPDATE, CMD_CLEAR, TD_CHANGENUM...: nothing to do
.motor: tst.l   36(a1)
        beq.s   .off
        bsr     MotorOn
        bra.s   .done
.off:   bsr     MotorOff
        bra.s   .done
.read:  move.l  44(a1),d4       ; offset
        move.l  36(a1),d5       ; length
        move.l  40(a1),a3       ; data
        move.l  d5,32(a1)       ; io_Actual
.rl:    tst.l   d5
        beq.s   .done
        move.l  d4,d0
        divu    #5632,d0        ; track = offset / (11 * 512)
        moveq   #0,d6
        move.w  d0,d6           ; track
        swap    d0
        and.l   #$FFFF,d0
        move.l  d0,d7           ; byte offset in the track
        move.l  a1,-(sp)
        bsr     ReadTrack
        move.l  (sp)+,a1
        tst.l   d0
        bne.s   .err
        lea     TRKDATA,a0
        add.l   d7,a0
        move.l  #5632,d1
        sub.l   d7,d1           ; bytes left in this track
        cmp.l   d5,d1
        bls.s   .cp
        move.l  d5,d1
.cp:    sub.l   d1,d5
        add.l   d1,d4
        subq.l  #1,d1
.cpb:   move.b  (a0)+,(a3)+
        subq.l  #1,d1
        bpl.s   .cpb
        bra.s   .rl
.err:   move.b  #21,31(a1)      ; TDERR_TooFewSecs
.done:  moveq   #0,d0
        move.b  31(a1),d0
        movem.l (sp)+,d1-d7/a0-a6
        ext.w   d0
        ext.l   d0
        rts

; ---------------------------------------------------------------- the drive
MotorOn:
        move.b  #$FF,CIAB+$100
        move.b  #$7F,CIAB+$100  ; /MTR low
        move.b  #$77,CIAB+$100  ; select DF0 (the motor is latched)
        move.l  #100000,d1
.r:     btst    #5,CIAA         ; /RDY
        beq.s   .ok
        subq.l  #1,d1
        bne.s   .r
.ok:    rts
MotorOff:
        move.b  #$FF,CIAB+$100
        move.b  #$F7,CIAB+$100  ; /MTR high, select: latched off
        move.b  #$FF,CIAB+$100
        rts

; step out until /TK0
Seek0:  moveq   #100,d2
.s:     btst    #4,CIAA
        beq.s   .at
        move.b  #$77,CIAB+$100  ; DIR = 1 (out)
        move.b  #$76,CIAB+$100  ; /STEP low
        move.b  #$77,CIAB+$100
        bsr     Wait3ms
        subq.w  #1,d2
        bne.s   .s
.at:    clr.l   CURCYL
        rts

; ReadTrack: track d6 (cylinder * 2 + side) decoded into TRKDATA. d0 = 0 when all 11 sectors were found.
ReadTrack:
        movem.l d1-d7/a0-a5,-(sp)
        cmp.l   TRKNUM,d6
        bne.s   .go
        moveq   #0,d0
        bra     .ret
.go:    move.w  d6,d3
        lsr.w   #1,d3           ; cylinder
.step:  move.l  CURCYL,d2
        cmp.w   d2,d3
        beq.s   .side
        bhi.s   .in
        move.b  #$77,CIAB+$100  ; out (DIR = 1)
        move.b  #$76,CIAB+$100
        move.b  #$77,CIAB+$100
        subq.l  #1,CURCYL
        bra.s   .w
.in:    move.b  #$75,CIAB+$100  ; in (DIR = 0)
        move.b  #$74,CIAB+$100
        move.b  #$75,CIAB+$100
        addq.l  #1,CURCYL
.w:     bsr     Wait3ms
        bra.s   .step
.side:  btst    #0,d6           ; side 1 = /SIDE low
        beq.s   .s0
        move.b  #$73,CIAB+$100
        bra.s   .dma
.s0:    move.b  #$77,CIAB+$100
.dma:   move.w  #$7F00,$9E(a6)  ; ADKCON
        move.w  #$9500,$9E(a6)  ; MFMPREC, WORDSYNC, FAST
        move.w  #$4489,$7E(a6)
        move.l  #TRKRAW,$20(a6)
        move.w  #$8210,$96(a6)  ; DMAEN | DSKEN
        move.w  #$0002,$9C(a6)
        move.w  #$4000,$24(a6)
        move.w  #$8000+6400,$24(a6)
        move.w  #$8000+6400,$24(a6)
        move.l  #400000,d1      ; ~85 frames; a track is ~11
.wd:    btst    #1,$1F(a6)
        bne.s   .got
        subq.l  #1,d1
        bne.s   .wd
        moveq   #1,d0
        bra     .ret
.got:   move.w  #$4000,$24(a6)
        ; decode every sector after a sync word
        moveq   #0,d7           ; sectors found (a bit each)
        lea     TRKRAW,a1
.find:  cmp.l   #TRKRAW+2*(6400-541),a1 ; a sector is 540 words after its sync
        bhi.s   .end
        cmp.w   #$4489,(a1)
        bne.s   .nx
        cmp.w   #$4489,2(a1)
        beq.s   .nx
        move.l  2(a1),d0
        and.l   #$55555555,d0
        add.l   d0,d0
        move.l  6(a1),d1
        and.l   #$55555555,d1
        or.l    d1,d0
        move.l  d0,d1
        swap    d1
        and.w   #$FF,d1         ; track number
        cmp.w   d6,d1
        bne.s   .nx
        lsr.w   #8,d0
        and.w   #$FF,d0         ; sector
        cmp.w   #11,d0
        bhs.s   .nx
        bset    d0,d7
        lea     TRKDATA,a2
        mulu    #512,d0
        add.l   d0,a2
        lea     58(a1),a4       ; the odd longs
        lea     512(a4),a5      ; the even longs
        moveq   #127,d4
.dl:    move.l  (a4)+,d0
        and.l   #$55555555,d0
        add.l   d0,d0
        move.l  (a5)+,d1
        and.l   #$55555555,d1
        or.l    d1,d0
        move.l  d0,(a2)+
        dbra    d4,.dl
        lea     1078(a1),a1
.nx:    addq.l  #2,a1
        bra.s   .find
.end:   cmp.w   #$07FF,d7
        bne.s   .bad
        move.l  d6,TRKNUM
        moveq   #0,d0
        bra.s   .ret
.bad:   moveq   #2,d0
.ret:   movem.l (sp)+,d1-d7/a0-a5
        rts

Wait3ms:
        move.w  #2000,d0
.w:     dbra    d0,.w
        rts

; ---------------------------------------------------------------- loud stops
NoDisk: lea     MsgNoDisk(pc),a0
        bra.s   Stop
NotBoot:
        lea     MsgNotBoot(pc),a0
        bra.s   Stop
BadSum: lea     MsgBadSum(pc),a0
        bra.s   Stop
BootFailed:
        lea     MsgFailed(pc),a0
Stop:   lea     CUSTOM,a6
        bsr     Say
        move.w  #$0A00,$180(a6)
.s:     bra.s   .s

; A jump table entry nobody wrote: the return address says which.
Unimpl: move.l  (sp)+,d0
        sub.l   #EXEC+6,d0      ; JSR at -6n returns to -6n+6
        move.w  d0,d7           ; -6n
        lea     CUSTOM,a6
        lea     MsgUnimpl(pc),a0
        bsr     Say
        move.w  d7,d0
        neg.w   d0
        ext.l   d0
        bsr     SayDec
        moveq   #10,d2
        bsr     PutC
        move.w  #$0F00,$180(a6)
.s:     bra.s   .s

Unexpected:
        lea     CUSTOM,a6
        lea     MsgExc(pc),a0
        bsr     Say
        move.w  #$0F00,$180(a6)
.s:     bra.s   .s

IntQuiet:
        move.w  #$3FFF,$DFF09C
        rte

; ---------------------------------------------------------------- serial
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
SayDec: lea     $200,a1
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

Hello:      dc.b "bootrom: no Kickstart - booting the bootblock in DF0",10,0
Booting:    dc.b "bootrom: bootblock checksum good, entering it",10,0
MsgNoDisk:  dc.b "bootrom: STOP - no disk in DF0, or it could not be read",10,0
MsgNotBoot: dc.b "bootrom: STOP - DF0 has no DOS bootblock",10,0
MsgBadSum:  dc.b "bootrom: STOP - the bootblock checksum is wrong",10,0
MsgFailed:  dc.b "bootrom: STOP - the bootblock returned an error",10,0
MsgUnimpl:  dc.b "bootrom: STOP - exec function not in this boot ROM: offset -",0
MsgExc:     dc.b "bootrom: STOP - an exception nobody handles",10,0
        EVEN
        ORG $FFFFFE
        dc.w 0
