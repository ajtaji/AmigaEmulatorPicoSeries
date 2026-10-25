; Amiga 500 (OCS, PAL) for the desktop: the same machine source as the Pico
; build (../amiga/*.pmi and the generated 68000 core), drawn with the Neon
; Arcade Display Engine, Paula through the sound card.
;
; Build:  desktop/build.sh amiga      (pbcompilerc, /THREAD /DPIAWARE /OPTIMIZER)
; Run:    desktop\amiga.exe [--rom kick.rom] [--adf disk.adf] [--df1 disk.adf] [--mute]
;                           [--tab N] [--shot window.png --seconds S] [--fast]
;         (--shot saves the window after S seconds and closes: for checks without a person)
;
; Keys: the PC keyboard is the Amiga's (Windows keys = Amiga keys, Insert = Help).
; Mouse: over the picture the PC mouse moves the Amiga's, its buttons are its buttons.
; F5 run/pause, F6 step one instruction, F7 step one frame, F8 reset, F9 warp, F11 full screen.
EnableExplicit

CompilerIf Not Defined(GL_ENGINE_DIR$, #PB_Constant)
  CompilerError "Pass the Neon Arcade Display Engine's folder: /CONSTANT GL_ENGINE_DIR$=<folder>/ (desktop/build.sh does)"
CompilerEndIf
XIncludeFile #GL_ENGINE_DIR$ + "GlTypes.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlUtilities.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlMath.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlSpriteFunctions.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlUI.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlUIChrome.pbi"

XIncludeFile "amiga_host.pbi"
XIncludeFile "amiga_sound.pbi"
XIncludeFile "disasm68k.pbi"
Declare ViewRunTests()
XIncludeFile "amiga_view.pbi"

Global Win.i, Gl.i, PhysW.i, PhysH.i
Global Quit.i, Paused.i, Warp.i
Global KeyCode.i, KeyChar.i, Wheel.i
Global Dim KeyDown.i(256)
Global Dim KeyMap.i(256)
Global PadCount.i
Global EmuAccum.d, EmuLastUs.q, EmuFrameUs.d = 1000000.0 / 60.0
Global FpsShown.d, FpsFrames.i, FpsSince.q, MipsShown.d, CycSince.i
Global ActiveTab.i, StatusLine.s, LastDraw.q
Global ShotFile.s, ShotAtMs.q
Global PicX.f, PicY.f, PicScale.f, MouseLastX.i, MouseLastY.i, MouseInPic.i

Procedure.q HostUs()
  ProcedureReturn ElapsedMilliseconds() * 1000
EndProcedure

; ---------------------------------------------------------------- keys: PC -> Amiga raw codes
Procedure KeyMapInit()
  Protected i.i, s.s
  For i = 0 To 255 : KeyMap(i) = -1 : Next
  ; the main block
  s = "1234567890"
  For i = 1 To 10 : KeyMap(Asc(Mid(s, i, 1))) = i : Next
  s = "QWERTYUIOP"
  For i = 1 To 10 : KeyMap(Asc(Mid(s, i, 1))) = $10 + i - 1 : Next
  s = "ASDFGHJKL"
  For i = 1 To 9 : KeyMap(Asc(Mid(s, i, 1))) = $20 + i - 1 : Next
  s = "ZXCVBNM"
  For i = 1 To 7 : KeyMap(Asc(Mid(s, i, 1))) = $31 + i - 1 : Next
  KeyMap(192) = $00            ; ` ~
  KeyMap(189) = $0B            ; - _
  KeyMap(187) = $0C            ; = +
  KeyMap(220) = $0D            ; \ |
  KeyMap(219) = $1A            ; [
  KeyMap(221) = $1B            ; ]
  KeyMap(186) = $29            ; ;
  KeyMap(222) = $2A            ; '
  KeyMap(188) = $38            ; ,
  KeyMap(190) = $39            ; .
  KeyMap(191) = $3A            ; /
  KeyMap(#PB_Shortcut_Space) = $40
  KeyMap(#PB_Shortcut_Back) = $41
  KeyMap(#PB_Shortcut_Tab) = $42
  KeyMap(#PB_Shortcut_Return) = $44
  KeyMap(#PB_Shortcut_Escape) = $45
  KeyMap(#PB_Shortcut_Delete) = $46
  KeyMap(#PB_Shortcut_Up) = $4C
  KeyMap(#PB_Shortcut_Down) = $4D
  KeyMap(#PB_Shortcut_Right) = $4E
  KeyMap(#PB_Shortcut_Left) = $4F
  For i = 0 To 9 : KeyMap(#PB_Shortcut_F1 + i) = $50 + i : Next
  KeyMap(#PB_Shortcut_Insert) = $5F                 ; Help
  ; Shift and Ctrl are the key codes 16 and 17: #PB_Shortcut_Shift ($10000) and
  ; #PB_Shortcut_Control ($20000) are modifier FLAGS, and as indexes they wrote
  ; far past this array - a random crash at start-up, whichever heap block lay there
  KeyMap(16) = $60                                  ; Shift
  KeyMap(#PB_Shortcut_Capital) = $62
  KeyMap(17) = $63                                  ; Ctrl
  KeyMap(#PB_Shortcut_Menu) = $64                   ; Alt
  KeyMap(#PB_Shortcut_LeftWindows) = $66
  KeyMap(#PB_Shortcut_RightWindows) = $67
  ; the numeric pad
  KeyMap(#PB_Shortcut_Pad0) = $0F
  KeyMap(#PB_Shortcut_Pad1) = $1D : KeyMap(#PB_Shortcut_Pad2) = $1E : KeyMap(#PB_Shortcut_Pad3) = $1F
  KeyMap(#PB_Shortcut_Pad4) = $2D : KeyMap(#PB_Shortcut_Pad5) = $2E : KeyMap(#PB_Shortcut_Pad6) = $2F
  KeyMap(#PB_Shortcut_Pad7) = $3D : KeyMap(#PB_Shortcut_Pad8) = $3E : KeyMap(#PB_Shortcut_Pad9) = $3F
  KeyMap(#PB_Shortcut_Decimal) = $3C
  KeyMap(#PB_Shortcut_Subtract) = $4A
  KeyMap(#PB_Shortcut_Add) = $5E
  KeyMap(#PB_Shortcut_Multiply) = $5D
  KeyMap(#PB_Shortcut_Divide) = $5C
EndProcedure

; ---------------------------------------------------------------- fonts and window size
Procedure BuildFonts()
  *Neon_FontUI = Neon_CreateFontPx("Segoe UI", Round(14 * UiScale, #PB_Round_Nearest))
  *Neon_FontSmall = Neon_CreateFontPx("Segoe UI", Round(12 * UiScale, #PB_Round_Nearest))
  *Neon_FontBold = Neon_CreateFontPx("Segoe UI", Round(15 * UiScale, #PB_Round_Nearest), #PB_Font_Bold)
  *Neon_FontMono = Neon_CreateFontPx("Consolas", Round(13 * UiScale, #PB_Round_Nearest))
  GLFontSetSnapToPixel(*Neon_FontUI, #True) : GLFontSetSnapToPixel(*Neon_FontSmall, #True)
  GLFontSetSnapToPixel(*Neon_FontBold, #True) : GLFontSetSnapToPixel(*Neon_FontMono, #True)
EndProcedure

Procedure MeasureWindow()
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    Protected client.RECT
    GetClientRect_(WindowID(Win), @client)
    PhysW = client\right - client\left : PhysH = client\bottom - client\top
  CompilerElse
    PhysW = WindowWidth(Win, #PB_Window_InnerCoordinate) * Linux_DPIScale
    PhysH = WindowHeight(Win, #PB_Window_InnerCoordinate) * Linux_DPIScale
  CompilerEndIf
  If PhysW < 1 : PhysW = 1 : EndIf
  If PhysH < 1 : PhysH = 1 : EndIf
  ResizeGadget(Gl, 0, 0, WindowWidth(Win, #PB_Window_InnerCoordinate), WindowHeight(Win, #PB_Window_InnerCoordinate))
  GL_ViewportX = 0 : GL_ViewportY = 0 : GL_ViewportW = PhysW : GL_ViewportH = PhysH
  Util_BaseWidth = PhysW : Util_BaseHeight = PhysH
  Util_WinWidth = WindowWidth(Win, #PB_Window_InnerCoordinate) : Util_WinHeight = WindowHeight(Win, #PB_Window_InnerCoordinate)
EndProcedure

; ---------------------------------------------------------------- the machine
Procedure MachinePower()
  If HostRomName = "" Or HostRomName = "built-in boot ROM"
    ; no Kickstart: the emulator's own boot ROM starts DF0's bootblock
    HostUseBootRom()
  EndIf
  AmigaReset()
  ; a real frame's length for the standard (NTSC 59.96 Hz, PAL 49.92), and a clean picture: an NTSC
  ; frame leaves the rows below its last line alone
  EmuFrameUs = (#AM_CCK_LINE * (AmLinesShort + 1)) * 1000000.0 / AmCckHz
  FillMemory(@HostFrame(), #AM_OUT_W * #HOST_FRAME_H * 4, 0, #PB_Long)
  Paused = 0
  EmuAccum = 0
  EmuLastUs = HostUs()
  If HostRomName = "built-in boot ROM"
    StatusLine = "No Kickstart: the built-in boot ROM boots DF0's bootblock. Kickstart... for anything else."
  Else
    StatusLine = "Kickstart " + HostRomName
  EndIf
EndProcedure

Procedure HostChooseRom()
  Protected f.s = OpenFileRequester("Choose a Kickstart ROM image", ViewRomPath, "Kickstart images (*.rom;*.bin)|*.rom;*.bin|All files|*.*", 0)
  If f <> ""
    If HostLoadRom(f)
      ViewRomPath = f
      MachinePower()
    Else
      StatusLine = HostError
    EndIf
  EndIf
EndProcedure

Procedure HostInsert(d.i, path.s)
  If HostLoadAdf(d, path) = 0
    StatusLine = HostError
  Else
    If d = 0 And HostRomName = "built-in boot ROM"
      MachinePower()    ; the boot ROM reads DF0 once, at reset
    EndIf
    StatusLine = "DF" + Str(d) + ": " + GetFilePart(path)
  EndIf
EndProcedure

; The 68000 test corpus through the console checker (the same runner the board uses).
Procedure ViewRunTests()
  Protected p.i, out.s, line.s, exe.s, dir.s
  exe = GetPathPart(ProgramFilename()) + "m68k_check.exe"
  If FileSize(exe) <= 0
    ViewTestText = "m68k_check.exe is not beside this program (desktop/run_check.sh builds it)"
    ViewTestBad = 1
    ProcedureReturn
  EndIf
  ; the streams tools/vectors.py writes: SST_680X0_DIR, or tests/680x0/compact in the repository
  dir = GetEnvironmentVariable("SST_680X0_DIR")
  If dir = ""
    dir = GetPathPart(ProgramFilename()) + "..\tests\680x0\compact"
  EndIf
  p = RunProgram(exe, Chr(34) + dir + Chr(34), "", #PB_Program_Open | #PB_Program_Read | #PB_Program_Hide)
  If p = 0
    ViewTestText = "the checker could not be started"
    ViewTestBad = 1
    ProcedureReturn
  EndIf
  While ProgramRunning(p)
    If AvailableProgramOutput(p)
      line = ReadProgramString(p)
      If Left(line, 5) = "TOTAL" : out = line : EndIf
    EndIf
  Wend
  While AvailableProgramOutput(p)
    line = ReadProgramString(p)
    If Left(line, 5) = "TOTAL" : out = line : EndIf
  Wend
  ViewTestBad = Bool(ProgramExitCode(p) <> 0)
  CloseProgram(p)
  ViewTestText = out
  If out = "" : ViewTestText = "the checker printed no total" : ViewTestBad = 1 : EndIf
EndProcedure

Procedure ReadPads()
  Protected b.i
  If KeyDown(#PB_Shortcut_Pad8) : b | 1 : EndIf
  If KeyDown(#PB_Shortcut_Pad2) : b | 2 : EndIf
  If KeyDown(#PB_Shortcut_Pad4) : b | 4 : EndIf
  If KeyDown(#PB_Shortcut_Pad6) : b | 8 : EndIf
  If KeyDown(#PB_Shortcut_Pad0) : b | 16 : EndIf
  If PadCount > 0 And ExamineJoystick(0)
    If JoystickAxisY(0) < 0 : b | 1 : ElseIf JoystickAxisY(0) > 0 : b | 2 : EndIf
    If JoystickAxisX(0) < 0 : b | 4 : ElseIf JoystickAxisX(0) > 0 : b | 8 : EndIf
    If JoystickButton(0, 1) Or JoystickButton(0, 2) : b | 16 : EndIf
  EndIf
  JoyBits = b
EndProcedure

; Whole frames at the PAL rate (50 Hz); never more than three a pass. Warp: as fast as it goes.
Procedure Emulate()
  Protected now.q, n.i, t0.q
  now = HostUs()
  If EmuLastUs = 0 : EmuLastUs = now : EndIf
  If Paused Or HostRomName = ""
    EmuLastUs = now
    ProcedureReturn
  EndIf
  ReadPads()
  If Warp
    t0 = ElapsedMilliseconds()
    Repeat
      AmigaRunFrame() : FpsFrames + 1
    Until ElapsedMilliseconds() - t0 > 14
    EmuLastUs = HostUs()
    ProcedureReturn
  EndIf
  EmuAccum + (now - EmuLastUs) : EmuLastUs = now
  If EmuAccum > EmuFrameUs * 4 : EmuAccum = EmuFrameUs * 4 : EndIf
  While EmuAccum >= EmuFrameUs And n < 3
    AmigaRunFrame() : EmuAccum - EmuFrameUs : n + 1 : FpsFrames + 1
  Wend
  If SoundOn And SoundPump() < #SOUND_PAIRS And n < 3 And AudWr - AudRd < #SOUND_PAIRS
    AmigaRunFrame() : FpsFrames + 1 : EmuAccum - EmuFrameUs
  EndIf
EndProcedure

Procedure StepInstruction()
  Paused = 1
  Budget = 0 : CLeft = 0
  M68kRun(1)
  Budget = 0 : CLeft = 0
EndProcedure

; The window's back buffer as a PNG (read before the flip).
Procedure SaveWindowShot(file.s)
  Protected *buf = AllocateMemory(PhysW * PhysH * 4), img.i, x.i, y.i, c.l
  glReadPixels_(0, 0, PhysW, PhysH, #GL_RGBA, #GL_UNSIGNED_BYTE, *buf)
  img = CreateImage(#PB_Any, PhysW, PhysH, 24)
  StartDrawing(ImageOutput(img))
  For y = 0 To PhysH - 1
    For x = 0 To PhysW - 1
      c = PeekL(*buf + ((PhysH - 1 - y) * PhysW + x) * 4)
      Plot(x, y, RGB(c & 255, (c >> 8) & 255, (c >> 16) & 255))
    Next
  Next
  StopDrawing()
  UsePNGImageEncoder()
  SaveImage(img, file, #PB_ImagePlugin_PNG)
  FreeImage(img) : FreeMemory(*buf)
EndProcedure

; The PC mouse over the picture is the Amiga's mouse (in lowres pixels).
Procedure MouseToAmiga(mx.i, my.i, left.i, right.i)
  Protected inside.i, dx.i, dy.i
  inside = Bool(mx >= PicX And my >= PicY And mx < PicX + #AM_OUT_W * PicScale And my < PicY + #HOST_FRAME_H * PicScale)
  If inside And MouseInPic
    dx = (mx - MouseLastX) / (PicScale * 2)
    dy = (my - MouseLastY) / (PicScale * 2)
    If dx <> 0 : MouseLastX = mx : EndIf
    If dy <> 0 : MouseLastY = my : EndIf
    AmigaMouse(dx, dy, left, right)
  ElseIf inside
    MouseLastX = mx : MouseLastY = my
    AmigaMouse(0, 0, left, right)
  Else
    AmigaMouse(0, 0, 0, 0)
  EndIf
  MouseInPic = inside
EndProcedure

; ---------------------------------------------------------------- one frame of the window
Procedure Tick()
  Protected now.q, dt.f, mx.i, my.i, down.b, rdown.b, s.f, toolH.f, x.f, gw.f, gh.f, side.f, panelX.f, label.s
  now = ElapsedMilliseconds() : dt = (now - LastDraw) / 1000.0 : LastDraw = now
  If dt > 0.25 : dt = 0.25 : EndIf
  Emulate()
  If SoundOn : SoundPump() : EndIf
  If now - FpsSince >= 1000
    FpsShown = FpsFrames * 1000.0 / (now - FpsSince) : FpsFrames = 0
    MipsShown = (AmigaCpuCycles - CycSince) / ((now - FpsSince) * 1000.0)
    CycSince = AmigaCpuCycles
    FpsSince = now
  EndIf

  mx = WindowMouseX(Win) : my = WindowMouseY(Win)
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    mx = mx * PhysW / Util_WinWidth : my = my * PhysH / Util_WinHeight
    If GetActiveWindow() = Win
      down = Bool(GetAsyncKeyState_(#VK_LBUTTON) & $8000)
      rdown = Bool(GetAsyncKeyState_(#VK_RBUTTON) & $8000)
    EndIf
  CompilerElse
    down = Bool(GetGadgetAttribute(Gl, #PB_OpenGL_Buttons) & #PB_OpenGL_LeftButton)
    rdown = Bool(GetGadgetAttribute(Gl, #PB_OpenGL_Buttons) & #PB_OpenGL_RightButton)
  CompilerEndIf
  MouseToAmiga(mx, my, down, rdown)
  Neon_ChromeBeginFrame(mx, my, down, Wheel, KeyCode, KeyChar, dt)
  Wheel = 0 : KeyCode = 0 : KeyChar = 0

  SetGadgetAttribute(Gl, #PB_OpenGL_SetContext, #True)
  glBindFramebuffer(#GL_FRAMEBUFFER, 0)
  glDisable_(#GL_SCISSOR_TEST)
  glViewport_(GL_ViewportX, GL_ViewportY, GL_ViewportW, GL_ViewportH)
  glClearColor_(Neon_C_BgR, Neon_C_BgG, Neon_C_BgB, 1.0)
  glClear_(#GL_COLOR_BUFFER_BIT)
  glEnable_(#GL_BLEND) : glBlendFunc_(#GL_SRC_ALPHA, #GL_ONE_MINUS_SRC_ALPHA)

  s = UiScale : toolH = Round(40 * s, #PB_Round_Nearest)
  Neon_Box(0, 0, PhysW, toolH, Neon_C_HeadR, Neon_C_HeadG, Neon_C_HeadB)
  x = 8 * s
  If Neon_Button(x, 6 * s, 104 * s, toolH - 12 * s, "Kickstart...") : HostChooseRom() : EndIf : x + 110 * s
  If Neon_Button(x, 6 * s, 90 * s, toolH - 12 * s, "Insert DF0...")
    label = OpenFileRequester("Insert a disk in DF0", ViewAdfFolder, "Amiga disks (*.adf)|*.adf|All files|*.*", 0)
    If label <> "" : HostInsert(0, label) : ViewAdfRefresh(GetPathPart(label)) : EndIf
  EndIf : x + 96 * s
  label = "Pause" : If Paused : label = "Run" : EndIf
  If Neon_Button(x, 6 * s, 72 * s, toolH - 12 * s, label + "  F5", Bool(Paused = 0)) : Paused = 1 - Paused : EmuLastUs = HostUs() : EndIf : x + 78 * s
  If Neon_Button(x, 6 * s, 80 * s, toolH - 12 * s, "Step  F6") : StepInstruction() : EndIf : x + 86 * s
  If Neon_Button(x, 6 * s, 88 * s, toolH - 12 * s, "Frame  F7") : Paused = 1 : AmigaRunFrame() : EndIf : x + 94 * s
  If Neon_Button(x, 6 * s, 82 * s, toolH - 12 * s, "Reset  F8") : MachinePower() : EndIf : x + 88 * s
  If Neon_Button(x, 6 * s, 76 * s, toolH - 12 * s, "Warp  F9", Warp) : Warp = 1 - Warp : EndIf : x + 82 * s
  ; the standard: NTSC (the US A500) or PAL - switching it is a power cycle
  label = "NTSC" : If AmigaNtsc = 0 : label = "PAL" : EndIf
  If Neon_Button(x, 6 * s, 56 * s, toolH - 12 * s, label) : AmigaNtsc = 1 - AmigaNtsc : MachinePower() : EndIf : x + 62 * s
  label = "Mute" : If SoundMuted : label = "Sound" : EndIf
  If Neon_Button(x, 6 * s, 70 * s, toolH - 12 * s, label, SoundMuted) : SoundMuted = 1 - SoundMuted : EndIf : x + 76 * s
  Neon_Text(*Neon_FontMono, x + 8 * s, toolH / 2 - 8 * s, StrD(FpsShown, 1) + " fps  " + StrD(MipsShown, 2) + " M cycles/s (" + StringField("7.09|7.16", AmigaNtsc + 1, "|") + " real)   " + StatusLine, Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)

  ; the picture: 736 x 576 hires half-lines (PAL's height; NTSC fills the top 474) as large as fits
  side = Round(620 * s, #PB_Round_Nearest)
  If side > PhysW * 0.5 : side = PhysW * 0.5 : EndIf
  gw = PhysW - side - 24 * s : gh = PhysH - toolH - 24 * s
  PicScale = gw / #AM_OUT_W
  If gh / #HOST_FRAME_H < PicScale : PicScale = gh / #HOST_FRAME_H : EndIf
  PicX = 12 * s + (gw - #AM_OUT_W * PicScale) / 2
  PicY = toolH + 12 * s + (gh - #HOST_FRAME_H * PicScale) / 2
  ViewDrawPicture(PicX, PicY, PicScale)
  If Halted
    Neon_Text(*Neon_FontBold, PicX + 8 * s, PicY + 8 * s, "CPU HALTED (double bus fault) at $" + Hex(M68kGetPC()), Neon_C_RedR, Neon_C_RedG, Neon_C_RedB)
  EndIf
  ; the power LED
  If (CiaPra(0) & 2) = 0
    Neon_Box(PicX, PicY + #HOST_FRAME_H * PicScale + 4 * s, 24 * s, 6 * s, 1.0, 0.1, 0.1)
  Else
    Neon_Box(PicX, PicY + #HOST_FRAME_H * PicScale + 4 * s, 24 * s, 6 * s, 0.35, 0.05, 0.05)
  EndIf
  If DrvMotor(0)
    Neon_Box(PicX + 30 * s, PicY + #HOST_FRAME_H * PicScale + 4 * s, 24 * s, 6 * s, 0.1, 1.0, 0.2)
  EndIf

  panelX = PhysW - side - 6 * s
  ActiveTab = Neon_TabStrip(1, panelX, toolH + 6 * s, side, 30 * s, "CPU|Copper|Blitter|Custom|CIAs|Memory|Disks", ActiveTab)
  ViewDrawPanel(ActiveTab, panelX, toolH + 40 * s, side, PhysH - toolH - 46 * s)

  Neon_ChromeEndFrame()
  If ShotFile <> "" And now >= ShotAtMs : SaveWindowShot(ShotFile) : Quit = 1 : EndIf
  SetGadgetAttribute(Gl, #PB_OpenGL_FlipBuffers, #True)
EndProcedure

Procedure KeyEvent(k.i, up.i)
  If k < 0 Or k > 255 : ProcedureReturn : EndIf
  If KeyMap(k) >= 0
    If up Or KeyDown(k) = 0
      AmigaKey(KeyMap(k), up)
    EndIf
  EndIf
  KeyDown(k) = 1 - up
EndProcedure

; ---------------------------------------------------------------- main
Procedure Main()
  Protected ev.i, k.i, et.i, rom.s, ext.s, adf.s, df1.s, a.s
  UiScale = DesktopResolutionX() : If UiScale < 1 : UiScale = 1 : EndIf
  Gl = OpenGLWindow("Amiga 500 (PureMetal)", 1500, 860, #PB_Window_SystemMenu | #PB_Window_ScreenCentered | #PB_Window_SizeGadget | #PB_Window_MinimizeGadget | #PB_Window_MaximizeGadget)
  If Gl = 0 : MessageRequester("Amiga", "OpenGL could not be started.") : End 1 : EndIf
  Win = Util_MainWindowID
  BuildFonts()
  MeasureWindow()
  GL_SetVSync(1)
  KeyMapInit()
  HostInit(512)
  ViewInit()
  For k = 0 To CountProgramParameters() - 1
    a = LCase(ProgramParameter(k))
    If a = "--rom" : k + 1 : rom = ProgramParameter(k)
    ElseIf a = "--ext" : k + 1 : ext = ProgramParameter(k)
    ElseIf a = "--adf" : k + 1 : adf = ProgramParameter(k)
    ElseIf a = "--df1" : k + 1 : df1 = ProgramParameter(k)
    ElseIf a = "--mute" : SoundMuted = 1
    ElseIf a = "--pal" : AmigaNtsc = 0
    ElseIf a = "--ntsc" : AmigaNtsc = 1
    ElseIf a = "--fast" : Warp = 1
    ElseIf a = "--tab" : k + 1 : ActiveTab = Val(ProgramParameter(k))
    ElseIf a = "--shot" : k + 1 : ShotFile = ProgramParameter(k) : If ShotAtMs = 0 : ShotAtMs = 5000 : EndIf
    ElseIf a = "--seconds" : k + 1 : ShotAtMs = Val(ProgramParameter(k)) * 1000
    EndIf
  Next
  If rom <> ""
    If HostLoadRom(rom) = 0 : StatusLine = HostError : EndIf
    ViewRomPath = rom
    If ext <> ""
      If HostLoadExt(ext) = 0 : StatusLine = HostError : EndIf
    EndIf
  EndIf
  MachinePower()
  If adf <> "" : HostInsert(0, adf) : ViewAdfRefresh(GetPathPart(adf)) : EndIf
  If df1 <> "" : HostInsert(1, df1) : EndIf
  SoundBegin()
  PadCount = InitJoystick()
  FpsSince = ElapsedMilliseconds() : LastDraw = FpsSince
  If ShotFile <> "" : ShotAtMs + FpsSince : EndIf
  Repeat
    Repeat
      ev = WindowEvent()
      Select ev
        Case #PB_Event_CloseWindow : Quit = 1
        Case #PB_Event_SizeWindow, #PB_Event_MaximizeWindow, #PB_Event_RestoreWindow : MeasureWindow()
        Case #PB_Event_Menu
          If EventMenu() = 1001 : KeyEvent(#PB_Shortcut_Escape, 0) : KeyEvent(#PB_Shortcut_Escape, 1) : EndIf
        Case #PB_Event_Gadget
          If EventGadget() = Gl
            et = EventType()
            Select et
              Case #PB_EventType_KeyDown
                k = GetGadgetAttribute(Gl, #PB_OpenGL_Key)
                Select k
                  Case #PB_Shortcut_F5 : Paused = 1 - Paused : EmuLastUs = HostUs()
                  Case #PB_Shortcut_F6 : StepInstruction()
                  Case #PB_Shortcut_F7 : Paused = 1 : AmigaRunFrame()
                  Case #PB_Shortcut_F8 : MachinePower()
                  Case #PB_Shortcut_F9 : Warp = 1 - Warp
                  Case #PB_Shortcut_F11 : GL_ToggleFullscreen() : MeasureWindow()
                  Default : KeyEvent(k, 0)
                EndSelect
              Case #PB_EventType_KeyUp
                KeyEvent(GetGadgetAttribute(Gl, #PB_OpenGL_Key), 1)
              Case #PB_EventType_Input : KeyChar = GetGadgetAttribute(Gl, #PB_OpenGL_Input)
              Case #PB_EventType_MouseWheel : Wheel + GetGadgetAttribute(Gl, #PB_OpenGL_WheelDelta)
            EndSelect
          EndIf
      EndSelect
    Until ev = 0 Or Quit
    If Quit : Break : EndIf
    Tick()
  Until Quit
  SoundEnd()
EndProcedure
Main()
