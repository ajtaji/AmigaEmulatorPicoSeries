; Paula on the PC's sound card: the mixer's 16-bit stereo ring (AudRing,
; amiga/paula.pmi) through the engine's sound out (GL_AudioOpen / Next / Play,
; GlUtilities.pbi HOST SERVICES: waveOut on Windows, ALSA on Linux), four
; 1024-pair buffers queued.
EnableExplicit

#SOUND_BUFFERS = 4
#SOUND_PAIRS = 1024

Global SoundOn.i, SoundMuted.i, SoundUnderruns.i, SoundQueued.i

Procedure.i SoundBegin()
  If GL_AudioOpen(#AUD_RATE, #SOUND_PAIRS, #SOUND_BUFFERS) = #False
    ProcedureReturn 0
  EndIf
  SoundOn = 1
  AudRd = AudWr
  ProcedureReturn 1
EndProcedure

; Hand the card the next samples while it has a free buffer. Returns the pairs still queued.
Procedure.i SoundPump()
  Protected k.i, *dst
  If SoundOn = 0
    AudRd = AudWr
    ProcedureReturn 0
  EndIf
  ; a ring that ran far ahead (paused sound, fast-forward) is cut back
  If AudWr - AudRd > #AUD_RING - #SOUND_PAIRS
    AudRd = AudWr - #SOUND_PAIRS * 2
  EndIf
  ; a buffer is taken only when a whole one's samples are there: one taken is played
  While AudWr - AudRd >= #SOUND_PAIRS
    *dst = GL_AudioNext()
    If *dst = 0 : Break : EndIf
    For k = 0 To #SOUND_PAIRS - 1
      If SoundMuted
        PokeL(*dst + k * 4, 0)
      Else
        PokeW(*dst + k * 4, AudRing((AudRd & (#AUD_RING - 1)) * 2))
        PokeW(*dst + k * 4 + 2, AudRing((AudRd & (#AUD_RING - 1)) * 2 + 1))
      EndIf
      AudRd + 1
    Next
    GL_AudioPlay(*dst)
  Wend
  SoundQueued = GL_AudioQueued()
  ProcedureReturn SoundQueued
EndProcedure

Procedure SoundEnd()
  GL_AudioClose()
  SoundOn = 0
EndProcedure
