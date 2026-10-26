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
; The window's keys and the PC-to-Amiga map: the controls table (controls.pbi), shown in the Controls tab.
EnableExplicit

; The Neon Arcade Display Engine (https://github.com/ajtaji/Neon-Arcade-Dispay-Engine), cloned beside
; this repository; /CONSTANT GL_ENGINE_DIR$=<folder>/ points elsewhere (desktop/build.sh passes NEON_ENGINE_DIR)
CompilerIf Not Defined(GL_ENGINE_DIR$, #PB_Constant)
  #GL_ENGINE_DIR$ = #PB_Compiler_FilePath + "../../Neon-Arcade-Dispay-Engine/"
CompilerEndIf
XIncludeFile #GL_ENGINE_DIR$ + "GlTypes.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlUtilities.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlMath.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlSpriteFunctions.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlUI.pbi"
XIncludeFile #GL_ENGINE_DIR$ + "GlUIChrome.pbi"
; this frame is not drawn through DrawRetroCRT: with the CRT on (the engine's default) every pointer
; position is bent by its barrel curve - up to 28 px at 125%, worst at the top and bottom of the window
UI_UseCRT = #False
CompilerIf Defined(PLANT_CRT, #PB_Constant)
  UI_UseCRT = #True   ; only to see --pointer-test fail
CompilerEndIf

XIncludeFile "amiga_host.pbi"
XIncludeFile "amiga_sound.pbi"
XIncludeFile "disasm68k.pbi"
Declare ViewRunTests()
XIncludeFile "controls.pbi"
XIncludeFile "amiga_view.pbi"

Global Win.i, Gl.i, PhysW.i, PhysH.i
Global Quit.i, Paused.i, Warp.i, PowerCount.i
Global KeyCode.i, KeyChar.i, Wheel.i
Global Dim KeyDown.i(256)
Global Dim KeyMap.i(256)
Global PadCount.i
Global EmuAccum.d, EmuLastUs.q, EmuFrameUs.d = 1000000.0 / 60.0
Global FpsShown.d, FpsFrames.i, FpsSince.q, MipsShown.d, CycSince.i
Global ActiveTab.i, StatusLine.s, LastDraw.q
Global ShotFile.s, ShotAtMs.q
Global PicX.f, PicY.f, PicSX.f, PicSY.f, PicRows.i = #HOST_FRAME_H, MouseLastX.i, MouseLastY.i, MouseInPic.i
Global KbNoEsc.i, LastAmigaKey.i = -1

Procedure.q HostUs()
  ProcedureReturn ElapsedMilliseconds() * 1000
EndProcedure

; ---------------------------------------------------------------- keys: PC -> Amiga raw codes
; From the controls table (controls.pbi), which the Controls tab and the README show.
Procedure KeyMapInit()
  Protected i.i
  For i = 0 To 255 : KeyMap(i) = -1 : Next
  ControlsInit()
  ForEach Controls()
    If Controls()\kind = #CTL_KEY And Controls()\vk >= 0 And Controls()\vk <= 255
      KeyMap(Controls()\vk) = Controls()\code
    EndIf
  Next
  ; Esc is the Amiga's ESC in the window only: in full screen it leaves full screen (KbNoEsc)
EndProcedure

; ---------------------------------------------------------------- fonts and window size
; The chrome's fonts at their logical size times Neon_UIScale (GlUIChrome.pbi, hosting section 5a), rebuilt -
; the old ones freed - when the scale changes
Global FontsBuilt.i
Procedure BuildFonts()
  If FontsBuilt
    FreeGLFont(*Neon_FontUI) : FreeGLFont(*Neon_FontSmall) : FreeGLFont(*Neon_FontBold) : FreeGLFont(*Neon_FontMono)
  EndIf
  FontsBuilt = 1
  *Neon_FontUI = Neon_CreateFontPx("Segoe UI", Round(Neon_S(14), #PB_Round_Nearest))
  *Neon_FontSmall = Neon_CreateFontPx("Segoe UI", Round(Neon_S(12), #PB_Round_Nearest))
  *Neon_FontBold = Neon_CreateFontPx("Segoe UI", Round(Neon_S(15), #PB_Round_Nearest), #PB_Font_Bold)
  *Neon_FontMono = Neon_CreateFontPx("Consolas", Round(Neon_S(13), #PB_Round_Nearest))
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
  ; the display scale s = physical / logical client width, MEASURED (GlUIChrome.pbi section 5a; not
  ; DesktopResolutionX(), which can read 1.0 under per-monitor awareness): the chrome (Neon_UIScale) and the
  ; fonts follow it, and change with it on a monitor with another scale
  Protected sc.f = 1.0
  If Util_WinWidth > 0 : sc = PhysW / Util_WinWidth : EndIf
  If sc <= 0 : sc = 1.0 : EndIf
  If FontsBuilt = 0 Or Abs(sc - Neon_UIScale) > 0.005 : Neon_UIScale = sc : BuildFonts() : EndIf
EndProcedure

; ---------------------------------------------------------------- the machine
Procedure MachinePower()
  If HostRomName = "" Or HostRomName = "built-in boot ROM"
    ; no Kickstart: the emulator's own boot ROM starts DF0's bootblock
    HostUseBootRom()
  EndIf
  AmigaReset()
  PowerCount + 1
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
  ForEach Controls()
    If Controls()\kind = #CTL_JOY And KeyDown(Controls()\vk) : b | Controls()\code : EndIf
  Next
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
  ; an Amiga lowres pixel is two picture columns wide and a line two rows high
  inside = Bool(mx >= PicX And my >= PicY And mx < PicX + #AM_OUT_W * PicSX And my < PicY + PicRows * PicSY)
  If inside And MouseInPic
    dx = (mx - MouseLastX) / (PicSX * 2)
    dy = (my - MouseLastY) / (PicSY * 2)
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

; ---------------------------------------------------------------- --pointer-test
; The real pointer is shared with everyone on this desktop, so it is never moved: the chrome is driven with
; synthetic positions in the units WindowMouseX/Y give a DPI-aware window (physical pixels), through the same
; Neon_ChromeBeginFrame call. For every control four points: just inside its top-left and its bottom-right
; corner (a press must land on it), just right of it and just below it (a press must not). Every frame
; Neon_MX / Neon_MY must read the point back unbent. Controls at the top of the window (the toolbar, the tab
; strip), in the middle (the picture, which takes the Amiga's mouse; the panes' buttons) and at the bottom
; (the disk list's last row).
Global PtFile$, PtLog$, PtX.f, PtY.f, PtDown.i, PtCase.i, PtPoint.i, PtFrame.i, PtFails.i, PtPoints.i, PtWorst.f, PtDone.i
Global PtCount.i, Dim PtName$(40)

Procedure PtInit()
  Protected n$ = "Kickstart|Insert DF0|Pause|Step|Frame|Reset|Warp|Standard|Sound|Full screen|tab 0|tab 3|tab 6|tab 7|screen|Run tests|cop back|mem <<|mem ROM|disks Kickstart|disks Eject DF1|Choose folder|list first row|list last row"
  Protected i.i
  PtCount = CountString(n$, "|") + 1
  For i = 0 To PtCount - 1 : PtName$(i) = StringField(n$, i + 1, "|") : Next
  ClearList(ViewAdfFiles())
  For i = 1 To 400 : AddElement(ViewAdfFiles()) : ViewAdfFiles() = "disk " + Str(i) + ".adf" : Next   ; longer than its pane
  ViewAdfTop = 0
  Paused = 1                                     ; the machine stands still while it is measured
EndProcedure

; The page a control is drawn on.
Procedure.i PtPage(name$)
  If name$ = "Run tests" : ProcedureReturn 0 : EndIf
  If Left(name$, 4) = "cop " : ProcedureReturn 1 : EndIf
  If Left(name$, 4) = "mem " : ProcedureReturn 5 : EndIf
  If Left(name$, 6) = "disks " Or name$ = "Choose folder" Or Left(name$, 5) = "list " : ProcedureReturn 6 : EndIf
  ProcedureReturn 0
EndProcedure

Procedure.i PtRect(name$, *r.CtlRect)
  Protected *row.Neon_TabRowLayout, i.i
  If Left(name$, 4) = "tab "
    If FindMapElement(Neon_TabLayout(), "1") = 0 : ProcedureReturn 0 : EndIf
    *row = @Neon_TabLayout() : i = Val(Mid(name$, 5))
    If i >= *row\Count : ProcedureReturn 0 : EndIf
    ; the row's last pixel is the strip's underline, not a tab
    *r\x = *row\X(i) : *r\w = *row\W(i) : *r\y = *row\Y : *r\h = *row\H - 1
    ProcedureReturn 1
  EndIf
  If FindMapElement(Ctl(), name$) = 0 : ProcedureReturn 0 : EndIf
  CopyStructure(@Ctl(), *r, CtlRect)
  ProcedureReturn 1
EndProcedure

; One step, after each frame is drawn.
Procedure PtStep()
  Protected r.CtlRect, name$, inside.i, got$, ok.i, f.i
  If PtCase >= PtCount
    PtLog$ + "pointer-test: " + Str(PtPoints) + " points on " + Str(PtCount) + " controls, " + Str(PtFails) + " failures, scale " +
             StrF(Neon_UIScale, 2) + ", canvas " + Str(Util_BaseWidth) + "x" + Str(Util_BaseHeight) + " physical, window " +
             Str(Util_WinWidth) + "x" + Str(Util_WinHeight) + " logical, UI_UseCRT " + Str(UI_UseCRT) +
             ", worst pointer read-back error " + StrF(PtWorst, 2) + " px" + #LF$
    f = CreateFile(#PB_Any, PtFile$)
    If f : WriteString(f, PtLog$) : CloseFile(f) : EndIf
    PtDone = 1
    ProcedureReturn
  EndIf
  name$ = PtName$(PtCase)
  If PtFrame > 1
    If Abs(Neon_MX - PtX) > PtWorst : PtWorst = Abs(Neon_MX - PtX) : EndIf
    If Abs(Neon_MY - PtY) > PtWorst : PtWorst = Abs(Neon_MY - PtY) : EndIf
  EndIf
  PtFrame + 1
  Select PtFrame
    Case 1                                       ; the page that shows the control, the pointer away
      ActiveTab = PtPage(name$)
      PtX = 1 : PtY = 1 : PtDown = 0
    Case 2                                       ; drawn: go to the point
      If PtRect(name$, @r) = 0
        PtLog$ + "FAIL " + name$ + ": not drawn" + #LF$ : PtFails + 1
        PtFrame = 0 : PtPoint = 0 : PtCase + 1 : ProcedureReturn
      EndIf
      Select PtPoint
        Case 0 : PtX = r\x + 2 : PtY = r\y + 2
        Case 1 : PtX = r\x + r\w - 2 : PtY = r\y + r\h - 2
        Case 2 : PtX = r\x + r\w + 2 : PtY = r\y + r\h - 2
        Case 3 : PtX = r\x + r\w - 2 : PtY = r\y + r\h + 2
      EndSelect
      PtClicked$ = ""
      If Left(name$, 4) = "tab " : ActiveTab = 99 : EndIf   ; no tab selected: a press shows as the new value
    Case 3 : PtDown = 1                          ; press
    Case 4 : PtDown = 0                          ; release
    Case 6                                       ; what the press did
      PtRect(name$, @r)
      inside = Bool(PtPoint < 2)
      If Left(name$, 4) = "tab "
        got$ = "tab " + Str(ActiveTab)
        ok = Bool((got$ = name$) = inside)
      ElseIf name$ = "screen"
        ; the picture takes the Amiga's mouse: is the pointer in it?
        got$ = StringField("not in the picture|in the picture", 1 + MouseInPic, "|")
        ok = Bool(MouseInPic = inside)
      Else
        got$ = PtClicked$
        If got$ = "" : got$ = "nothing" : EndIf
        ok = Bool((PtClicked$ = name$) = inside)
      EndIf
      PtPoints + 1
      PtLog$ + StringField("FAIL|ok", 1 + ok, "|") + "  " + LSet(name$, 16) + " rect (" + StrF(r\x, 1) + "," + StrF(r\y, 1) + " " +
               StrF(r\w, 1) + "x" + StrF(r\h, 1) + ")  point (" + StrF(PtX, 0) + "," + StrF(PtY, 0) + ") " +
               StringField("outside|inside", 1 + inside, "|") + "  read back (" + StrF(Neon_MX, 1) + "," + StrF(Neon_MY, 1) + ")  press -> " + got$ + #LF$
      If ok = 0 : PtFails + 1 : EndIf
      If Left(name$, 4) = "tab " : ActiveTab = 0 : EndIf
      PtPoint + 1 : PtFrame = 0
      If PtPoint = 4 : PtPoint = 0 : PtCase + 1 : EndIf
  EndSelect
EndProcedure

; ---------------------------------------------------------------- full screen
; The Full screen button or F11: a borderless window over the monitor the window is on (no display-mode
; change) showing only the Amiga's picture - NTSC's 474 rows or PAL's 576 - at its real shape (a picture
; texel is 0.857 as wide as it is high NTSC, 1.040 PAL: the square-pixel rate over the hires dot rate, 12.27 /
; 14.32 MHz and 14.75 / 14.19 MHz), as large as fits and centred. The emulation, sound and frame rate are the
; window's. Esc leaves (and is not the Amiga's ESC there: End is), and the window's placement and style come
; back exactly. The PC mouse over the picture is still the Amiga's, mapped into the scaled picture.
Global FullScreen.i, FsStyle.i, FsPlacement.WINDOWPLACEMENT, FsCursorHidden.i, FsMouseX.f, FsMouseY.f, FsMouseMs.q
Global FsViewX.f, FsViewY.f, FsViewW.f, FsViewH.f
Global FtShotNow.i, FtShot$

Procedure FsShowCursor(show.i)
  If show And FsCursorHidden : ShowCursor_(#True) : FsCursorHidden = 0 : EndIf
  If show = 0 And FsCursorHidden = 0 : ShowCursor_(#False) : FsCursorHidden = 1 : EndIf
EndProcedure

Procedure EnterFullScreen()
  Protected hwnd.i = WindowID(Win), mi.MONITORINFO
  If FullScreen : ProcedureReturn : EndIf
  FsPlacement\length = SizeOf(WINDOWPLACEMENT) : GetWindowPlacement_(hwnd, @FsPlacement)
  FsStyle = GetWindowLongPtr_(hwnd, #GWL_STYLE)
  mi\cbSize = SizeOf(MONITORINFO) : GetMonitorInfo_(MonitorFromWindow_(hwnd, 2), @mi)   ; 2: the nearest monitor
  SetWindowLongPtr_(hwnd, #GWL_STYLE, FsStyle & ~(#WS_CAPTION | #WS_THICKFRAME | #WS_MINIMIZEBOX | #WS_MAXIMIZEBOX | #WS_SYSMENU))
  SetWindowPos_(hwnd, #HWND_TOP, mi\rcMonitor\left, mi\rcMonitor\top, mi\rcMonitor\right - mi\rcMonitor\left, mi\rcMonitor\bottom - mi\rcMonitor\top, #SWP_FRAMECHANGED | #SWP_NOOWNERZORDER | #SWP_SHOWWINDOW)
  FullScreen = 1 : KbNoEsc = 1 : FsMouseMs = ElapsedMilliseconds()
  MeasureWindow()                                ; the client size and the scale, measured again
EndProcedure

Procedure LeaveFullScreen()
  Protected hwnd.i = WindowID(Win)
  If FullScreen = 0 : ProcedureReturn : EndIf
  SetWindowLongPtr_(hwnd, #GWL_STYLE, FsStyle)
  SetWindowPlacement_(hwnd, @FsPlacement)
  SetWindowPos_(hwnd, 0, 0, 0, 0, 0, #SWP_FRAMECHANGED | #SWP_NOMOVE | #SWP_NOSIZE | #SWP_NOZORDER | #SWP_NOOWNERZORDER)
  FullScreen = 0 : KbNoEsc = 0 : FsShowCursor(1)
  MeasureWindow()
EndProcedure

; Width / height of the picture shown in full screen, for the standard in use.
Procedure.f FsShape()
  If AmigaNtsc : ProcedureReturn #AM_OUT_W * (12.2727 / 14.31818) / 474 : EndIf
  ProcedureReturn #AM_OUT_W * (14.75 / 14.1875) / #HOST_FRAME_H
EndProcedure

Procedure.i FsRows()
  If AmigaNtsc : ProcedureReturn 474 : EndIf
  ProcedureReturn #HOST_FRAME_H
EndProcedure

Procedure DrawFullScreen(pw.f, ph.f)
  Protected a.f = FsShape(), vw.f, vh.f
  Neon_Box(0, 0, pw, ph, 0, 0, 0)
  vw = pw : vh = vw / a
  If vh > ph : vh = ph : vw = vh * a : EndIf
  vw = Round(vw, #PB_Round_Nearest) : vh = Round(vh, #PB_Round_Nearest)   ; whole pixels, so it centres exactly
  FsViewW = vw : FsViewH = vh : FsViewX = Round((pw - vw) / 2, #PB_Round_Down) : FsViewY = Round((ph - vh) / 2, #PB_Round_Down)
  ViewDrawPictureShaped(FsViewX, FsViewY, FsViewW, FsViewH, FsRows())
  ; where the Amiga's mouse reads the picture from (MouseToAmiga)
  PicX = FsViewX : PicY = FsViewY : PicSX = FsViewW / #AM_OUT_W : PicSY = FsViewH / FsRows() : PicRows = FsRows()
  ; the cursor goes after two seconds still, and comes back when the mouse moves
  If Neon_MX <> FsMouseX Or Neon_MY <> FsMouseY : FsMouseX = Neon_MX : FsMouseY = Neon_MY : FsMouseMs = ElapsedMilliseconds() : FsShowCursor(1) : EndIf
  If ElapsedMilliseconds() - FsMouseMs > 2000 : FsShowCursor(0) : EndIf
EndProcedure

; A picture of the full-screen window, read before the flip (--fullscreen-test <log> <shot>).
Procedure FsShot()
  If FtShotNow And FtShot$ <> "" : SaveWindowShot(FtShot$) : EndIf
  FtShotNow = 0
EndProcedure

; The window's own keys and buttons, from the controls table (controls.pbi).
Procedure WindowAction(act.i)
  Select act
    Case #ACT_RUNPAUSE : Paused = 1 - Paused : EmuLastUs = HostUs()
    Case #ACT_STEP : StepInstruction()
    Case #ACT_FRAME : Paused = 1 : AmigaRunFrame()
    Case #ACT_RESET : MachinePower()
    Case #ACT_WARP : Warp = 1 - Warp
    Case #ACT_FULLSCREEN : If FullScreen : LeaveFullScreen() : Else : EnterFullScreen() : EndIf
    Case #ACT_LEAVEFULL : LeaveFullScreen()
  EndSelect
EndProcedure

; ---------------------------------------------------------------- --fullscreen-test
; Full screen by its own keys, without the real pointer or keyboard: the keys are posted to this window's
; GL gadget, and the mouse checks use the pointer test's synthetic point (PtOn). Checked under NTSC and then
; PAL: Esc in the window is the Amiga's ESC; F5 is the Amiga's F5 (not a window key); F11 covers the window's
; monitor, the scale and client size are measured again, the picture has the standard's real shape, fits and
; is centred, the PC mouse is the Amiga's inside it and not in the bars, the machine runs on; Esc leaves, is not
; passed to the Amiga, and the windowed rectangle comes back exactly; End is ESC; F12 pauses and runs.
Global FtOn.i, FtFile$, FtLog$, FtFails.i, FtStep.i, FtWait.i, FtWin.RECT, FtFrame.i, FtPaused.i, FtStd$, FtShotDone.i

Procedure FtCheck(ok.i, what$)
  FtLog$ + StringField("FAIL|ok", 1 + Bool(ok), "|") + "  " + what$ + #LF$
  If ok = 0 : FtFails + 1 : EndIf
EndProcedure

Procedure FtKey(vk.i, up.i)
  If up
    PostMessage_(GadgetID(Gl), #WM_KEYUP, vk, $C0000001)
  Else
    PostMessage_(GadgetID(Gl), #WM_KEYDOWN, vk, 1)
  EndIf
EndProcedure

Procedure FtCheckFull()
  Protected r.RECT, mi.MONITORINFO, hwnd.i = WindowID(Win), a.f = FsShape()
  GetWindowRect_(hwnd, @r) : mi\cbSize = SizeOf(MONITORINFO) : GetMonitorInfo_(MonitorFromWindow_(hwnd, 2), @mi)
  FtCheck(FullScreen, FtStd$ + ": F11 entered full screen")
  FtCheck(Bool(r\left = mi\rcMonitor\left And r\top = mi\rcMonitor\top And r\right = mi\rcMonitor\right And r\bottom = mi\rcMonitor\bottom),
          FtStd$ + ": the window covers its monitor (" + Str(r\left) + "," + Str(r\top) + " - " + Str(r\right) + "," + Str(r\bottom) + "; monitor " +
          Str(mi\rcMonitor\left) + "," + Str(mi\rcMonitor\top) + " - " + Str(mi\rcMonitor\right) + "," + Str(mi\rcMonitor\bottom) + ")")
  FtCheck(Bool(Abs(PhysW - (mi\rcMonitor\right - mi\rcMonitor\left)) <= 1 And Abs(Neon_UIScale - PhysW / Util_WinWidth) < 0.01),
          FtStd$ + ": client size and scale measured again: " + Str(PhysW) + "x" + Str(PhysH) + " physical, " + Str(Util_WinWidth) + " logical, scale " + StrF(Neon_UIScale, 3))
  FtCheck(Bool(Abs(FsViewW / FsViewH - a) < 0.005), FtStd$ + ": the picture " + StrF(FsViewW, 0) + "x" + StrF(FsViewH, 0) + " has the standard's shape " + StrF(FsViewW / FsViewH, 4) + " (" + StrF(a, 4) + ": " + Str(FsRows()) + " rows)")
  FtCheck(Bool(FsViewW <= PhysW And FsViewH <= PhysH And (Abs(FsViewW - PhysW) <= 1 Or Abs(FsViewH - PhysH) <= 1)), FtStd$ + ": as large as fits in " + Str(PhysW) + "x" + Str(PhysH))
  FtCheck(Bool(Abs(FsViewX * 2 + FsViewW - PhysW) <= 1 And Abs(FsViewY * 2 + FsViewH - PhysH) <= 1), FtStd$ + ": centred at " + StrF(FsViewX, 0) + "," + StrF(FsViewY, 0))
EndProcedure

; One step, after each frame is shown.
Procedure FtStep()
  Protected r.RECT, f.i
  If FtWait > 0 : FtWait - 1 : ProcedureReturn : EndIf
  FtStep + 1
  Select FtStep
    Case 1 : FtStd$ = "NTSC" : FtWait = 120                      ; the program under way
    Case 2 : GetWindowRect_(WindowID(Win), @FtWin) : LastAmigaKey = -1 : FtKey(#VK_ESCAPE, 0)
    Case 3 : FtKey(#VK_ESCAPE, 1) : FtWait = 3
    Case 4
      FtCheck(Bool(LastAmigaKey = $45 And FullScreen = 0), "Esc in the window is the Amiga's ESC and leaves the window as it is")
      LastAmigaKey = -1 : FtKey(#VK_F5, 0)
    Case 5 : FtKey(#VK_F5, 1) : FtWait = 3
    Case 6
      FtCheck(Bool(LastAmigaKey = $54), "F5 is the Amiga's F5 (the window's keys are F11, F12, Page Up / Down, Pause, Scroll Lock)")
      FtKey(#VK_F11, 0)
    Case 7 : FtKey(#VK_F11, 1) : FtWait = 8
    Case 8
      FtCheckFull()
      FtFrame = FrameCount
      PtOn = 1 : PtDown = 0 : PtX = FsViewX + FsViewW / 2 : PtY = FsViewY + FsViewH / 2 : FtWait = 3
    Case 9
      FtCheck(MouseInPic, FtStd$ + ": the PC mouse in the picture's middle is the Amiga's")
      If FsViewX >= 4 : PtX = FsViewX - 2 : PtY = FsViewY + FsViewH / 2 : Else : PtX = FsViewX + FsViewW / 2 : PtY = FsViewY - 2 : EndIf
      FtWait = 3
    Case 10
      FtCheck(Bool(MouseInPic = 0), FtStd$ + ": just outside the picture (" + StrF(PtX, 0) + "," + StrF(PtY, 0) + ") it is not")
      PtX = FsViewX + FsViewW - 2 : PtY = FsViewY + FsViewH - 2 : FtWait = 3
    Case 11
      FtCheck(MouseInPic, FtStd$ + ": the picture's bottom-right corner is the Amiga's")
      PtOn = 0
      FtCheck(Bool(FrameCount > FtFrame), FtStd$ + ": the machine ran on in full screen (" + Str(FrameCount - FtFrame) + " frames)")
      If FtShotDone = 0 : FtShotNow = 1 : FtShotDone = 1 : EndIf
      FtWait = 2
    Case 12 : LastAmigaKey = -1 : FtKey(#VK_ESCAPE, 0)
    Case 13 : FtKey(#VK_ESCAPE, 1) : FtWait = 8
    Case 14
      GetWindowRect_(WindowID(Win), @r)
      FtCheck(Bool(FullScreen = 0), FtStd$ + ": Esc left full screen")
      FtCheck(Bool(LastAmigaKey = -1), FtStd$ + ": Esc in full screen was not passed to the Amiga")
      FtCheck(Bool(r\left = FtWin\left And r\top = FtWin\top And r\right = FtWin\right And r\bottom = FtWin\bottom),
              FtStd$ + ": the window came back to " + Str(r\left) + "," + Str(r\top) + " - " + Str(r\right) + "," + Str(r\bottom) + " (was " +
              Str(FtWin\left) + "," + Str(FtWin\top) + " - " + Str(FtWin\right) + "," + Str(FtWin\bottom) + ")")
      FtCheck(Bool(Abs(Neon_UIScale - PhysW / Util_WinWidth) < 0.01 And PhysW < 10000), FtStd$ + ": scale measured again in the window: " + StrF(Neon_UIScale, 3))
      LastAmigaKey = -1 : FtKey(#VK_END, 0)
    Case 15 : FtKey(#VK_END, 1) : FtWait = 3
    Case 16
      FtCheck(Bool(LastAmigaKey = $45), "End is the Amiga's ESC")
      If FtStd$ = "NTSC"
        ; again under PAL: its 576 rows and its shape
        AmigaNtsc = 0 : MachinePower() : FtStd$ = "PAL" : FtKey(#VK_F11, 0) : FtStep = 6 : FtWait = 20
      EndIf
    Case 17 : FtPaused = Paused : FtKey(#VK_F12, 0)
    Case 18 : FtKey(#VK_F12, 1) : FtWait = 3
    Case 19 : FtCheck(Bool(Paused <> FtPaused), "F12 pauses / runs") : FtKey(#VK_F12, 0)
    Case 20 : FtKey(#VK_F12, 1) : FtWait = 3
    Case 21
      FtCheck(Bool(Paused = FtPaused), "F12 again puts it back")
      FtLog$ + "fullscreen-test: " + Str(FtFails) + " failures" + #LF$
      f = CreateFile(#PB_Any, FtFile$)
      If f : WriteString(f, FtLog$) : CloseFile(f) : EndIf
      Quit = 1
  EndSelect
EndProcedure

; ---------------------------------------------------------------- one frame of the window
Procedure Tick()
  Protected now.q, dt.f, mx.i, my.i, down.b, rdown.b, toolH.f, x.f, gw.f, gh.f, side.f, panelX.f, label.s
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

  ; the mouse as the window gives it: in a DPI-aware window these are already physical (canvas)
  ; pixels - scaling them again put every click 25% off at 125% (GlUIChrome.pbi, hosting section 5a)
  mx = WindowMouseX(Win) : my = WindowMouseY(Win)
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    If GetActiveWindow() = Win
      down = Bool(GetAsyncKeyState_(#VK_LBUTTON) & $8000)
      rdown = Bool(GetAsyncKeyState_(#VK_RBUTTON) & $8000)
    EndIf
  CompilerElse
    down = Bool(GetGadgetAttribute(Gl, #PB_OpenGL_Buttons) & #PB_OpenGL_LeftButton)
    rdown = Bool(GetGadgetAttribute(Gl, #PB_OpenGL_Buttons) & #PB_OpenGL_RightButton)
  CompilerEndIf
  If PtOn : mx = PtX : my = PtY : down = PtDown : rdown = 0 : EndIf   ; --pointer-test: the synthetic point, the same path
  Neon_ChromeBeginFrame(mx, my, down, Wheel, KeyCode, KeyChar, dt)
  MouseToAmiga(Neon_MX, Neon_MY, down, rdown)
  Wheel = 0 : KeyCode = 0 : KeyChar = 0

  SetGadgetAttribute(Gl, #PB_OpenGL_SetContext, #True)
  glBindFramebuffer(#GL_FRAMEBUFFER, 0)
  glDisable_(#GL_SCISSOR_TEST)
  glViewport_(GL_ViewportX, GL_ViewportY, GL_ViewportW, GL_ViewportH)
  glClearColor_(Neon_C_BgR, Neon_C_BgG, Neon_C_BgB, 1.0)
  glClear_(#GL_COLOR_BUFFER_BIT)
  glEnable_(#GL_BLEND) : glBlendFunc_(#GL_SRC_ALPHA, #GL_ONE_MINUS_SRC_ALPHA)

  If FullScreen
    DrawFullScreen(PhysW, PhysH)
    Neon_ChromeEndFrame()
    FsShot()
    SetGadgetAttribute(Gl, #PB_OpenGL_FlipBuffers, #True)
    If FtOn : FtStep() : EndIf
    ProcedureReturn
  EndIf
  toolH = Round(Neon_S(40), #PB_Round_Nearest)
  Neon_Box(0, 0, PhysW, toolH, Neon_C_HeadR, Neon_C_HeadG, Neon_C_HeadB)
  x = Neon_S(8)
  If Btn("Kickstart", x, Neon_S(6), Neon_S(104), toolH - Neon_S(12), "Kickstart...") : HostChooseRom() : EndIf : x + Neon_S(110)
  If Btn("Insert DF0", x, Neon_S(6), Neon_S(90), toolH - Neon_S(12), "Insert DF0...")
    label = OpenFileRequester("Insert a disk in DF0", ViewAdfFolder, "Amiga disks (*.adf)|*.adf|All files|*.*", 0)
    If label <> "" : HostInsert(0, label) : ViewAdfRefresh(GetPathPart(label)) : EndIf
  EndIf : x + Neon_S(96)
  label = "Pause" : If Paused : label = "Run" : EndIf
  If Btn("Pause", x, Neon_S(6), Neon_S(80), toolH - Neon_S(12), label + "  F12", Bool(Paused = 0)) : WindowAction(#ACT_RUNPAUSE) : EndIf : x + Neon_S(86)
  If Btn("Step", x, Neon_S(6), Neon_S(84), toolH - Neon_S(12), "Step  PgDn") : WindowAction(#ACT_STEP) : EndIf : x + Neon_S(90)
  If Btn("Frame", x, Neon_S(6), Neon_S(92), toolH - Neon_S(12), "Frame  PgUp") : WindowAction(#ACT_FRAME) : EndIf : x + Neon_S(98)
  If Btn("Reset", x, Neon_S(6), Neon_S(92), toolH - Neon_S(12), "Reset  Break") : WindowAction(#ACT_RESET) : EndIf : x + Neon_S(98)
  If Btn("Warp", x, Neon_S(6), Neon_S(90), toolH - Neon_S(12), "Warp  ScrLk", Warp) : WindowAction(#ACT_WARP) : EndIf : x + Neon_S(96)
  ; the standard: NTSC (the US A500) or PAL - switching it is a power cycle
  label = "NTSC" : If AmigaNtsc = 0 : label = "PAL" : EndIf
  If Btn("Standard", x, Neon_S(6), Neon_S(56), toolH - Neon_S(12), label) : AmigaNtsc = 1 - AmigaNtsc : MachinePower() : EndIf : x + Neon_S(62)
  label = "Mute" : If SoundMuted : label = "Sound" : EndIf
  If Btn("Sound", x, Neon_S(6), Neon_S(70), toolH - Neon_S(12), label, SoundMuted) : SoundMuted = 1 - SoundMuted : EndIf : x + Neon_S(76)
  If Btn("Full screen", x, Neon_S(6), Neon_S(124), toolH - Neon_S(12), "Full screen  F11") : WindowAction(#ACT_FULLSCREEN) : EndIf : x + Neon_S(130)
  Neon_Text(*Neon_FontMono, x + Neon_S(8), toolH / 2 - Neon_S(8), StrD(FpsShown, 1) + " fps  " + StrD(MipsShown, 2) + " M cycles/s (" + StringField("7.09|7.16", AmigaNtsc + 1, "|") + " real)   " + StatusLine, Neon_C_DimR, Neon_C_DimG, Neon_C_DimB)

  ; the picture: 736 x 576 hires half-lines (PAL's height; NTSC fills the top 474) as large as fits
  side = Round(Neon_S(620), #PB_Round_Nearest)
  If side > PhysW * 0.5 : side = PhysW * 0.5 : EndIf
  gw = PhysW - side - Neon_S(24) : gh = PhysH - toolH - Neon_S(24)
  PicSX = gw / #AM_OUT_W
  If gh / #HOST_FRAME_H < PicSX : PicSX = gh / #HOST_FRAME_H : EndIf
  PicSY = PicSX : PicRows = #HOST_FRAME_H
  PicX = Neon_S(12) + (gw - #AM_OUT_W * PicSX) / 2
  PicY = toolH + Neon_S(12) + (gh - #HOST_FRAME_H * PicSY) / 2
  ViewDrawPicture(PicX, PicY, PicSX)
  CtlSet("screen", PicX, PicY, #AM_OUT_W * PicSX, #HOST_FRAME_H * PicSY)
  If Halted
    Neon_Text(*Neon_FontBold, PicX + Neon_S(8), PicY + Neon_S(8), "CPU HALTED (double bus fault) at $" + Hex(M68kGetPC()), Neon_C_RedR, Neon_C_RedG, Neon_C_RedB)
  EndIf
  ; the power LED
  If (CiaPra(0) & 2) = 0
    Neon_Box(PicX, PicY + #HOST_FRAME_H * PicSY + Neon_S(4), Neon_S(24), Neon_S(6), 1.0, 0.1, 0.1)
  Else
    Neon_Box(PicX, PicY + #HOST_FRAME_H * PicSY + Neon_S(4), Neon_S(24), Neon_S(6), 0.35, 0.05, 0.05)
  EndIf
  If DrvMotor(0)
    Neon_Box(PicX + Neon_S(30), PicY + #HOST_FRAME_H * PicSY + Neon_S(4), Neon_S(24), Neon_S(6), 0.1, 1.0, 0.2)
  EndIf

  panelX = PhysW - side - Neon_S(6)
  ActiveTab = Neon_TabStrip(1, panelX, toolH + Neon_S(6), side, Neon_S(30), "CPU|Copper|Blitter|Custom|CIAs|Memory|Disks|Controls", ActiveTab)
  ViewDrawPanel(ActiveTab, panelX, toolH + Neon_S(40), side, PhysH - toolH - Neon_S(46))

  Neon_ChromeEndFrame()
  If ShotFile <> "" And now >= ShotAtMs : SaveWindowShot(ShotFile) : Quit = 1 : EndIf
  SetGadgetAttribute(Gl, #PB_OpenGL_FlipBuffers, #True)
  If PtOn : PtStep() : If PtDone : Quit = 1 : EndIf : EndIf
  If FtOn : FtStep() : EndIf
EndProcedure

Procedure KeyEvent(k.i, up.i)
  If k < 0 Or k > 255 : ProcedureReturn : EndIf
  If k = #PB_Shortcut_Escape And KbNoEsc : ProcedureReturn : EndIf   ; full screen: Esc is the window's (End is ESC)
  If KeyMap(k) >= 0
    If up Or KeyDown(k) = 0
      AmigaKey(KeyMap(k), up)
      If up = 0 : LastAmigaKey = KeyMap(k) : EndIf
    EndIf
  EndIf
  KeyDown(k) = 1 - up
EndProcedure

; ---------------------------------------------------------------- main
Procedure Main()
  Protected ev.i, k.i, et.i, rom.s, ext.s, adf.s, df1.s, a.s
  ; no larger than the work area (it is in physical pixels; OpenWindow takes logical ones), less the frame
  Protected wa.RECT, ww.i = 1500, wh.i = 860
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    SystemParametersInfo_(#SPI_GETWORKAREA, 0, @wa, 0)
    If (wa\right - wa\left) / DesktopResolutionX() - 40 < ww : ww = (wa\right - wa\left) / DesktopResolutionX() - 40 : EndIf
    If (wa\bottom - wa\top) / DesktopResolutionY() - 60 < wh : wh = (wa\bottom - wa\top) / DesktopResolutionY() - 60 : EndIf
  CompilerEndIf
  Gl = OpenGLWindow("Amiga 500 (PureMetal)", ww, wh, #PB_Window_SystemMenu | #PB_Window_ScreenCentered | #PB_Window_SizeGadget | #PB_Window_MinimizeGadget | #PB_Window_MaximizeGadget)
  If Gl = 0 : MessageRequester("Amiga", "OpenGL could not be started.") : End 1 : EndIf
  Win = Util_MainWindowID
  ; the engine binds Esc to a shortcut of its own; here Esc is the Amiga's ESC in the window and leaves full screen
  RemoveKeyboardShortcut(Win, #PB_Shortcut_Escape)
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
    ElseIf a = "--fullscreen-test" : k + 1 : FtFile$ = ProgramParameter(k) : FtOn = 1 : SoundMuted = 1
      If k + 1 < CountProgramParameters() And Left(ProgramParameter(k + 1), 2) <> "--" : k + 1 : FtShot$ = ProgramParameter(k) : EndIf
    ElseIf a = "--pointer-test" : k + 1 : PtFile$ = ProgramParameter(k) : PtOn = 1 : SoundMuted = 1
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
  If PtOn : PtInit() : EndIf
  Repeat
    Repeat
      ev = WindowEvent()
      Select ev
        Case #PB_Event_CloseWindow : Quit = 1
        Case #PB_Event_SizeWindow, #PB_Event_MoveWindow, #PB_Event_MaximizeWindow, #PB_Event_RestoreWindow : MeasureWindow()
        Case #PB_Event_Gadget
          If EventGadget() = Gl
            et = EventType()
            Select et
              Case #PB_EventType_KeyDown
                k = GetGadgetAttribute(Gl, #PB_OpenGL_Key)
                ; the window's own keys first (the controls table), then the Amiga's
                If ControlsAction(k, FullScreen)
                  WindowAction(ControlsAction(k, FullScreen))
                Else
                  KeyEvent(k, 0)
                EndIf
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
  If FullScreen : LeaveFullScreen() : EndIf
  If PtOn : End PtFails : EndIf   ; --pointer-test: the number of failures
  If FtOn : End FtFails : EndIf   ; --fullscreen-test: the number of failures
EndProcedure
Main()
