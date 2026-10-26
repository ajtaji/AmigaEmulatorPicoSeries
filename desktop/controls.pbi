; THE CONTROLS: one table that the keyboard code (KeyMapInit, ReadPads in amiga.pb), the window's shortcuts,
; the Controls tab (amiga_view.pbi) and the README's Controls section (tools/controls_readme.py) all read -
; so they cannot disagree.
;
; A row: kind, PC key (a key code as the window gives it), what the PC key is called, what it is on the
; Amiga, and a number: the Amiga raw key code for a key, the joystick bit for a joystick key, the action for
; a shortcut. Rows marked hidden are read by the code but shown as one summary row.
;
; Esc: in the window Esc is the Amiga's ESC; in full screen Esc leaves full screen and is not passed to the
; Amiga - End is ESC there (and always). The window's own keys are F11, F12, Page Up / Down, Pause and Scroll
; Lock: F1 - F10 are all the Amiga's.

#CTL_KEY = 0          ; an Amiga key (code = its raw key code)
#CTL_JOY = 1          ; the joystick in port 2 (code = the direction or fire bit)
#CTL_PAD = 2          ; the gamepad (a note: the code reads the first gamepad's stick and buttons 1 and 2)
#CTL_MOUSE = 3        ; the mouse in port 1 (a note)
#CTL_SHORTCUT = 4     ; the window's own (code = the action)
#CTL_NOTE = 5         ; a summary row of the Controls tab only

#ACT_RUNPAUSE = 1
#ACT_STEP = 2
#ACT_FRAME = 3
#ACT_RESET = 4
#ACT_WARP = 5
#ACT_FULLSCREEN = 6
#ACT_LEAVEFULL = 7

Structure CtlRow
  kind.i
  vk.i
  pc$
  amiga$
  code.i
  hidden.i
EndStructure
Global NewList Controls.CtlRow()

Procedure CtlAdd(kind.i, vk.i, pc$, amiga$, code.i = 0, hidden.i = 0)
  AddElement(Controls())
  Controls()\kind = kind : Controls()\vk = vk : Controls()\pc$ = pc$ : Controls()\amiga$ = amiga$
  Controls()\code = code : Controls()\hidden = hidden
EndProcedure

Procedure ControlsInit()
  Protected i.i, s$
  ClearList(Controls())
  ; the letters and digits by position (hidden: one summary row)
  CtlAdd(#CTL_NOTE, 0, "A-Z, 0-9, Space, Return", "the same keys")
  s$ = "1234567890"
  For i = 1 To 10 : CtlAdd(#CTL_KEY, Asc(Mid(s$, i, 1)), Mid(s$, i, 1), Mid(s$, i, 1), i, 1) : Next
  s$ = "QWERTYUIOP"
  For i = 1 To 10 : CtlAdd(#CTL_KEY, Asc(Mid(s$, i, 1)), Mid(s$, i, 1), Mid(s$, i, 1), $10 + i - 1, 1) : Next
  s$ = "ASDFGHJKL"
  For i = 1 To 9 : CtlAdd(#CTL_KEY, Asc(Mid(s$, i, 1)), Mid(s$, i, 1), Mid(s$, i, 1), $20 + i - 1, 1) : Next
  s$ = "ZXCVBNM"
  For i = 1 To 7 : CtlAdd(#CTL_KEY, Asc(Mid(s$, i, 1)), Mid(s$, i, 1), Mid(s$, i, 1), $31 + i - 1, 1) : Next
  CtlAdd(#CTL_KEY, #PB_Shortcut_Space, "Space", "SPACE", $40, 1)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Return, "Return", "RETURN", $44, 1)
  ; the keys that differ, or that the Amiga calls something else
  CtlAdd(#CTL_KEY, #PB_Shortcut_Escape, "Esc (in the window)", "ESC", $45)
  CtlAdd(#CTL_KEY, #PB_Shortcut_End, "End", "ESC", $45)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Insert, "Insert", "HELP", $5F)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Delete, "Delete", "DEL", $46)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Back, "Backspace", "BACKSPACE", $41)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Tab, "Tab", "TAB", $42)
  CtlAdd(#CTL_KEY, #PB_Shortcut_LeftWindows, "Left Windows", "LEFT AMIGA", $66)
  CtlAdd(#CTL_KEY, #PB_Shortcut_RightWindows, "Right Windows", "RIGHT AMIGA", $67)
  ; Shift and Ctrl are the key codes 16 and 17: #PB_Shortcut_Shift and #PB_Shortcut_Control are modifier FLAGS
  CtlAdd(#CTL_KEY, 16, "Shift", "SHIFT", $60)
  CtlAdd(#CTL_KEY, 17, "Ctrl", "CTRL", $63)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Menu, "Alt", "ALT", $64)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Capital, "Caps Lock", "CAPS LOCK", $62)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Up, "Up", "cursor up", $4C)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Down, "Down", "cursor down", $4D)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Right, "Right", "cursor right", $4E)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Left, "Left", "cursor left", $4F)
  CtlAdd(#CTL_NOTE, 0, "F1-F10", "F1-F10 (all ten are the Amiga's)")
  For i = 0 To 9 : CtlAdd(#CTL_KEY, #PB_Shortcut_F1 + i, "F" + Str(i + 1), "F" + Str(i + 1), $50 + i, 1) : Next
  CtlAdd(#CTL_KEY, 192, "`", "`", $00)
  CtlAdd(#CTL_KEY, 189, "-", "-", $0B)
  CtlAdd(#CTL_KEY, 187, "=", "=", $0C)
  CtlAdd(#CTL_KEY, 220, "\", "\", $0D)
  CtlAdd(#CTL_KEY, 219, "[", "[", $1A)
  CtlAdd(#CTL_KEY, 221, "]", "]", $1B)
  CtlAdd(#CTL_KEY, 186, ";", ";", $29)
  CtlAdd(#CTL_KEY, 222, "'", "'", $2A)
  CtlAdd(#CTL_KEY, 188, ",", ",", $38)
  CtlAdd(#CTL_KEY, 190, ".", ".", $39)
  CtlAdd(#CTL_KEY, 191, "/", "/", $3A)
  ; the numeric pad: the Amiga's own (keypad 8 2 4 6 0 are also the joystick, below)
  CtlAdd(#CTL_NOTE, 0, "Keypad 0-9 . - + * /", "keypad 0-9 . - + * /")
  CtlAdd(#CTL_KEY, #PB_Shortcut_Pad0, "Keypad 0", "keypad 0", $0F, 1)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Pad1, "Keypad 1", "keypad 1", $1D, 1)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Pad2, "Keypad 2", "keypad 2", $1E, 1)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Pad3, "Keypad 3", "keypad 3", $1F, 1)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Pad4, "Keypad 4", "keypad 4", $2D, 1)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Pad5, "Keypad 5", "keypad 5", $2E, 1)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Pad6, "Keypad 6", "keypad 6", $2F, 1)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Pad7, "Keypad 7", "keypad 7", $3D, 1)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Pad8, "Keypad 8", "keypad 8", $3E, 1)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Pad9, "Keypad 9", "keypad 9", $3F, 1)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Decimal, "Keypad .", "keypad .", $3C, 1)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Subtract, "Keypad -", "keypad -", $4A, 1)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Add, "Keypad +", "keypad +", $5E, 1)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Multiply, "Keypad *", "keypad *", $5D, 1)
  CtlAdd(#CTL_KEY, #PB_Shortcut_Divide, "Keypad /", "keypad /", $5C, 1)
  ; the mouse in port 1, the joystick in port 2
  CtlAdd(#CTL_MOUSE, 0, "PC mouse over the picture", "the mouse in port 1")
  CtlAdd(#CTL_MOUSE, 0, "Left / right mouse button", "the mouse's left / right button")
  CtlAdd(#CTL_JOY, #PB_Shortcut_Pad8, "Keypad 8", "joystick up (port 2)", 1)
  CtlAdd(#CTL_JOY, #PB_Shortcut_Pad2, "Keypad 2", "joystick down", 2)
  CtlAdd(#CTL_JOY, #PB_Shortcut_Pad4, "Keypad 4", "joystick left", 4)
  CtlAdd(#CTL_JOY, #PB_Shortcut_Pad6, "Keypad 6", "joystick right", 8)
  CtlAdd(#CTL_JOY, #PB_Shortcut_Pad0, "Keypad 0", "joystick fire", 16)
  CtlAdd(#CTL_PAD, 0, "Gamepad stick / d-pad", "joystick directions (port 2)")
  CtlAdd(#CTL_PAD, 0, "Gamepad button 1 or 2", "joystick fire")
  ; the window's own
  CtlAdd(#CTL_SHORTCUT, #PB_Shortcut_F12, "F12", "run / pause", #ACT_RUNPAUSE)
  CtlAdd(#CTL_SHORTCUT, #PB_Shortcut_PageDown, "Page Down", "step one instruction", #ACT_STEP)
  CtlAdd(#CTL_SHORTCUT, #PB_Shortcut_PageUp, "Page Up", "step one frame", #ACT_FRAME)
  CtlAdd(#CTL_SHORTCUT, #PB_Shortcut_Pause, "Pause / Break", "reset (a power cycle)", #ACT_RESET)
  CtlAdd(#CTL_SHORTCUT, #PB_Shortcut_Scroll, "Scroll Lock", "warp (as fast as it goes)", #ACT_WARP)
  CtlAdd(#CTL_SHORTCUT, #PB_Shortcut_F11, "F11", "full screen on / off", #ACT_FULLSCREEN)
  CtlAdd(#CTL_SHORTCUT, #PB_Shortcut_Escape, "Esc (in full screen)", "leave full screen", #ACT_LEAVEFULL)
EndProcedure

; The shortcut a key is in the window (full screen or not), or 0.
Procedure.i ControlsAction(vk.i, fullscreen.i)
  ForEach Controls()
    If Controls()\kind = #CTL_SHORTCUT And Controls()\vk = vk
      If Controls()\code = #ACT_LEAVEFULL And fullscreen = 0 : Continue : EndIf
      ProcedureReturn Controls()\code
    EndIf
  Next
  ProcedureReturn 0
EndProcedure
