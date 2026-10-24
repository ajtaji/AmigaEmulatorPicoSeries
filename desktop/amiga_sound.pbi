; Paula on the PC's sound card: the mixer's 44.1 kHz 16-bit stereo ring
; (AudRing, amiga/paula.pmi) to waveOut, four 1024-pair buffers queued.
; Windows only; elsewhere the program is silent.
EnableExplicit

#SOUND_BUFFERS = 4
#SOUND_PAIRS = 1024

CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  Structure SoundWaveFormat
    wFormatTag.w : nChannels.w : nSamplesPerSec.l : nAvgBytesPerSec.l : nBlockAlign.w : wBitsPerSample.w : cbSize.w
  EndStructure
  Structure SoundWaveHeader
    *lpData : dwBufferLength.l : dwBytesRecorded.l : *dwUser : dwFlags.l : dwLoops.l : *lpNext : *reserved
  EndStructure
  Import "winmm.lib"
    waveOutOpen_(*handle, device.l, *format, callback.i, instance.i, flags.l) As "waveOutOpen"
    waveOutPrepareHeader_(handle.i, *header, size.l) As "waveOutPrepareHeader"
    waveOutUnprepareHeader_(handle.i, *header, size.l) As "waveOutUnprepareHeader"
    waveOutWrite_(handle.i, *header, size.l) As "waveOutWrite"
    waveOutReset_(handle.i) As "waveOutReset"
    waveOutClose_(handle.i) As "waveOutClose"
  EndImport
  #SOUND_WHDR_DONE = 1
  Global SoundHandle.i
  Global Dim SoundHeaders.SoundWaveHeader(#SOUND_BUFFERS)
  Global Dim SoundData.w(#SOUND_BUFFERS * #SOUND_PAIRS * 2)
CompilerEndIf
Global SoundOn.i, SoundMuted.i, SoundUnderruns.i, SoundQueued.i

Procedure.i SoundBegin()
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    Protected fmt.SoundWaveFormat, i.i
    fmt\wFormatTag = 1 : fmt\nChannels = 2 : fmt\nSamplesPerSec = #AUD_RATE : fmt\wBitsPerSample = 16
    fmt\nBlockAlign = 4 : fmt\nAvgBytesPerSec = #AUD_RATE * 4
    If waveOutOpen_(@SoundHandle, -1, @fmt, 0, 0, 0) <> 0
      SoundHandle = 0
      ProcedureReturn 0
    EndIf
    For i = 0 To #SOUND_BUFFERS - 1
      SoundHeaders(i)\lpData = @SoundData(i * #SOUND_PAIRS * 2)
      SoundHeaders(i)\dwBufferLength = #SOUND_PAIRS * 4
      SoundHeaders(i)\dwFlags = #SOUND_WHDR_DONE
    Next
    SoundOn = 1
    AudRd = AudWr
    ProcedureReturn 1
  CompilerElse
    ProcedureReturn 0
  CompilerEndIf
EndProcedure

; Hand every finished buffer the next samples. Returns the pairs still queued.
Procedure.i SoundPump()
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    Protected i.i, k.i, *dst, queued.i
    If SoundOn = 0
      AudRd = AudWr
      ProcedureReturn 0
    EndIf
    ; a ring that ran far ahead (paused sound, fast-forward) is cut back
    If AudWr - AudRd > #AUD_RING - #SOUND_PAIRS
      AudRd = AudWr - #SOUND_PAIRS * 2
    EndIf
    For i = 0 To #SOUND_BUFFERS - 1
      If SoundHeaders(i)\dwFlags & #SOUND_WHDR_DONE
        If SoundHeaders(i)\dwFlags & 2
          waveOutUnprepareHeader_(SoundHandle, @SoundHeaders(i), SizeOf(SoundWaveHeader))
        EndIf
        If AudWr - AudRd < #SOUND_PAIRS
          Continue
        EndIf
        *dst = @SoundData(i * #SOUND_PAIRS * 2)
        For k = 0 To #SOUND_PAIRS - 1
          If SoundMuted
            PokeL(*dst + k * 4, 0)
          Else
            PokeW(*dst + k * 4, AudRing((AudRd & (#AUD_RING - 1)) * 2))
            PokeW(*dst + k * 4 + 2, AudRing((AudRd & (#AUD_RING - 1)) * 2 + 1))
          EndIf
          AudRd + 1
        Next
        SoundHeaders(i)\dwFlags = 0
        waveOutPrepareHeader_(SoundHandle, @SoundHeaders(i), SizeOf(SoundWaveHeader))
        waveOutWrite_(SoundHandle, @SoundHeaders(i), SizeOf(SoundWaveHeader))
      EndIf
    Next
    For i = 0 To #SOUND_BUFFERS - 1
      If (SoundHeaders(i)\dwFlags & #SOUND_WHDR_DONE) = 0
        queued + #SOUND_PAIRS
      EndIf
    Next
    SoundQueued = queued
    ProcedureReturn queued
  CompilerElse
    AudRd = AudWr
    ProcedureReturn 0
  CompilerEndIf
EndProcedure

Procedure SoundEnd()
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    Protected i.i
    If SoundHandle
      waveOutReset_(SoundHandle)
      For i = 0 To #SOUND_BUFFERS - 1
        waveOutUnprepareHeader_(SoundHandle, @SoundHeaders(i), SizeOf(SoundWaveHeader))
      Next
      waveOutClose_(SoundHandle)
      SoundHandle = 0
    EndIf
  CompilerEndIf
  SoundOn = 0
EndProcedure
