; A bootblock in the usual shape: AllocAbs the load area, read the program
; with trackdisk (A1 = the request the strap hands over), motor off, jump.
; Runs wherever it is loaded (PC-relative only).
PROG    = $40000
PSIZE   = 20480                 ; to track 3: crosses sides and a cylinder
        ORG 0
        dc.b "DOS",0
        dc.l 0                  ; checksum, filled by mkadf.py
        dc.l 880
        move.l  a1,a5
        move.l  #PSIZE,d0
        lea     PROG,a1
        jsr     -204(a6)        ; AllocAbs
        tst.l   d0
        beq.s   .fail
        move.l  a5,a1
        move.w  #2,28(a1)       ; CMD_READ
        move.l  #PSIZE,36(a1)
        move.l  #PROG,40(a1)
        move.l  #1024,44(a1)
        jsr     -456(a6)        ; DoIO
        tst.l   d0
        bne.s   .fail
        move.l  a5,a1
        move.w  #9,28(a1)       ; TD_MOTOR off
        clr.l   36(a1)
        jsr     -456(a6)
        jmp     PROG
.fail:  moveq   #-1,d0
        rts
        ORG 1023
        dc.b 0
