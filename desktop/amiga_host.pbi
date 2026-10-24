; The Amiga on the PC: memory, the Kickstart and .ADF files, the picture, the
; serial port. Shared by the window program (amiga.pb) and the console runner
; (amiga_cli.pb). The machine itself is the shared source in ../amiga/.
EnableExplicit

; The machine's hot procedures are ProcedureRAM on the Pico; here they are plain.
Macro ProcedureRAM
  Procedure
EndMacro

#AUD_RING = 16384                 ; Paula's output ring, stereo pairs
CompilerIf Defined(AUD_RATE_48K, #PB_Constant)
  #AUD_RATE = 48000                ; a build to compare Paula's samples with the Picos' (tools/pico_demo_check.sh)
CompilerElse
  #AUD_RATE = 44100
CompilerEndIf
#AUD_MONO = 0
#AM_PROFILE = 0
#AM_BLIT_ASM = 0
#AM_AUDIO_ASM = 0
CompilerIf Defined(M68K_HIST, #PB_Constant)
  XIncludeFile "m68k_core_hist.pbi"   ; tools/gen_m68k.py --hist: counts opcodes
CompilerElse
  XIncludeFile "m68k_core.pbi"
CompilerEndIf
XIncludeFile "../amiga/chipset.pmi"
XIncludeFile "../amiga/cia.pmi"
XIncludeFile "../amiga/copper.pmi"
XIncludeFile "../amiga/denise.pmi"
XIncludeFile "../amiga/blitter.pmi"
XIncludeFile "../amiga/paula.pmi"
XIncludeFile "../amiga/input.pmi"
XIncludeFile "../amiga/machine.pmi"

#HOST_FRAME_H = 576                 ; two rows per Amiga line (interlace fills both)

Global *HostChip, *HostSlow, *HostRom, *HostExt, *HostAdf0, *HostAdf1
Global HostRomName.s, HostAdfName0.s, HostAdfName1.s, HostError.s
Global Dim HostFrame.l(#AM_OUT_W * #HOST_FRAME_H)
Global Dim HostPal.l(4096)
Global HostSerial.s, HostFrameReady.i, HostLace.i

; 12-bit Amiga colour -> 32-bit pixel (bytes R, G, B, A in memory)
Procedure HostPalInit()
  Protected c.i, r.i, g.i, b.i
  For c = 0 To 4095
    r = ((c >> 8) & 15) * 17
    g = ((c >> 4) & 15) * 17
    b = (c & 15) * 17
    HostPal(c) = r | (g << 8) | (b << 16) | ($FF << 24)
  Next
EndProcedure

Procedure AmigaLineDone(y.i)
  Protected x.i, *row, row.i
  If BplCon0 & 4
    HostLace = 1
    row = y * 2 + (LongFrame ! 1)
    If row >= #HOST_FRAME_H
      ProcedureReturn
    EndIf
    *row = @HostFrame(row * #AM_OUT_W)
    For x = 0 To #AM_OUT_W - 1
      PokeL(*row + x * 4, HostPal(LineBuf(x) & $FFF))
    Next
  Else
    HostLace = 0
    row = y * 2
    *row = @HostFrame(row * #AM_OUT_W)
    For x = 0 To #AM_OUT_W - 1
      PokeL(*row + x * 4, HostPal(LineBuf(x) & $FFF))
    Next
    CopyMemory(*row, *row + #AM_OUT_W * 4, #AM_OUT_W * 4)
  EndIf
EndProcedure

Global HostSerialStamp.i       ; 1: each serial line starts with the emulated time in ms
Procedure AmigaSerial(byte.i)
  If HostSerialStamp And (HostSerial = "" Or Right(HostSerial, 1) = #LF$) And byte <> 10
    HostSerial + "[" + Str(FrameCount * 20 + VPos * 20 / 313) + " ms emulated, " + Str(ElapsedMilliseconds()) + " host] "
  EndIf
  If byte = 10
    HostSerial + #LF$
  ElseIf byte >= 32 Or byte = 13
    If byte <> 13
      HostSerial + Chr(byte)
    EndIf
  EndIf
  If Len(HostSerial) > 65536
    HostSerial = Right(HostSerial, 32768)
  EndIf
EndProcedure

; Allocate the memories (chip RAM 512 KB, slow RAM 512 KB when slowKb > 0).
Procedure HostInit(slowKb.i)
  HostPalInit()
  If *HostChip = 0
    *HostChip = AllocateMemory($80000)
    *HostRom = AllocateMemory($80000)
    *HostExt = AllocateMemory($80000)
    *HostSlow = AllocateMemory($80000)
  EndIf
  ChipMask = $7FFFF
  ChipSetHost(*HostChip, $80000, *HostChip + $80000)
  AmigaSlowHost = *HostSlow
  AmigaSlowBytes = slowKb * 1024
  AmigaRomHost = *HostRom
  AmigaExtHost = *HostExt
EndProcedure

; n bytes of a big-endian image at *src into *dst, in host word order.
Procedure HostSwapCopy(*dst, *src, n.i)
  Protected k.i
  For k = 0 To n - 2 Step 2
    PokeA(*dst + k, PeekA(*src + k + 1))
    PokeA(*dst + k + 1, PeekA(*src + k))
  Next
EndProcedure

; A big-endian ROM image (256 or 512 KB) into the ROM area, in host word order.
; No extended ROM with it.
Procedure HostSetRom(*buf, n.i)
  HostSwapCopy(*HostRom, *buf, n)
  AmigaRomBytes = n
  AmigaExtBytes = 0
EndProcedure

Procedure.i HostLoadRom(path.s)
  Protected f.i, n.i, k.i, *buf
  f = ReadFile(#PB_Any, path)
  If f = 0
    HostError = "The Kickstart file " + path + " could not be opened."
    ProcedureReturn 0
  EndIf
  n = Lof(f)
  If n <> $40000 And n <> $80000 And n <> $100000
    CloseFile(f)
    HostError = "The Kickstart file " + path + " is " + Str(n) + " bytes; a Kickstart image is 262144 or 524288 bytes (1048576: an extended ROM at $E00000, then the ROM at $F80000). An Amiga Forever ROM that needs rom.key (11 bytes longer) is not supported."
    ProcedureReturn 0
  EndIf
  *buf = AllocateMemory(n)
  ReadData(f, *buf, n)
  CloseFile(f)
  If n = $100000
    ; one 1 MB file: $E00000-$E7FFFF then $F80000-$FFFFFF (how AROS's ROM is often shipped)
    HostSetRom(*buf + $80000, $80000)
    HostSwapCopy(*HostExt, *buf, $80000)
    AmigaExtBytes = $80000
  Else
    HostSetRom(*buf, n)
  EndIf
  FreeMemory(*buf)
  HostRomName = GetFilePart(path)
  ProcedureReturn 1
EndProcedure

; An extended ROM (512 KB, big-endian) at $E00000, beside the ROM already loaded:
; AROS's aros-ext.bin with its aros-rom.bin.
Procedure.i HostLoadExt(path.s)
  Protected f.i, n.i, *buf
  f = ReadFile(#PB_Any, path)
  If f = 0
    HostError = "The extended ROM " + path + " could not be opened."
    ProcedureReturn 0
  EndIf
  n = Lof(f)
  If n <> $80000
    CloseFile(f)
    HostError = "The extended ROM " + path + " is " + Str(n) + " bytes; it must be 524288."
    ProcedureReturn 0
  EndIf
  *buf = AllocateMemory(n)
  ReadData(f, *buf, n)
  CloseFile(f)
  HostSwapCopy(*HostExt, *buf, n)
  FreeMemory(*buf)
  AmigaExtHost = *HostExt
  AmigaExtBytes = n
  ProcedureReturn 1
EndProcedure

; The emulator's own boot ROM (bootrom/bootrom.s) in place of a Kickstart:
; boots a disk's bootblock with a small ExecBase (AllocAbs, DoIO on trackdisk...).
Procedure HostUseBootRom()
  HostSetRom(?HostBootRom, ?HostBootRomEnd - ?HostBootRom)
  HostRomName = "built-in boot ROM"
EndProcedure

DataSection
  HostBootRom:
  IncludeBinary #PB_Compiler_FilePath + "../bootrom/bootrom.rom"
  HostBootRomEnd:
EndDataSection

; Put an .ADF (901120 bytes, DD) in drive d.
Procedure.i HostLoadAdf(d.i, path.s)
  Protected f.i, n.i, *buf
  f = ReadFile(#PB_Any, path)
  If f = 0
    HostError = "The disk image " + path + " could not be opened."
    ProcedureReturn 0
  EndIf
  n = Lof(f)
  If n <> #ADF_BYTES
    CloseFile(f)
    HostError = "The disk image " + path + " is " + Str(n) + " bytes; an .ADF (double density) is 901120 bytes."
    ProcedureReturn 0
  EndIf
  If d = 0
    If *HostAdf0 = 0
      *HostAdf0 = AllocateMemory(#ADF_BYTES)
    EndIf
    *buf = *HostAdf0
    HostAdfName0 = GetFilePart(path)
  Else
    If *HostAdf1 = 0
      *HostAdf1 = AllocateMemory(#ADF_BYTES)
    EndIf
    *buf = *HostAdf1
    HostAdfName1 = GetFilePart(path)
  EndIf
  DriveEject(d)
  ReadData(f, *buf, n)
  CloseFile(f)
  DriveInsert(d, *buf, 1)
  ProcedureReturn 1
EndProcedure

Procedure HostEject(d.i)
  DriveEject(d)
  If d = 0
    HostAdfName0 = ""
  Else
    HostAdfName1 = ""
  EndIf
EndProcedure

; The picture as a PNG (the rows of the last frame).
Procedure.i HostSavePng(path.s)
  Protected img.i, x.i, y.i, c.i
  UsePNGImageEncoder()
  img = CreateImage(#PB_Any, #AM_OUT_W, #HOST_FRAME_H, 24)
  If img = 0
    ProcedureReturn 0
  EndIf
  StartDrawing(ImageOutput(img))
  For y = 0 To #HOST_FRAME_H - 1
    For x = 0 To #AM_OUT_W - 1
      c = HostFrame(y * #AM_OUT_W + x)
      Plot(x, y, RGB(c & $FF, (c >> 8) & $FF, (c >> 16) & $FF))
    Next
  Next
  StopDrawing()
  c = SaveImage(img, path, #PB_ImagePlugin_PNG)
  FreeImage(img)
  ProcedureReturn c
EndProcedure
