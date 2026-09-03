#Requires AutoHotkey v2.0
#SingleInstance Force
#MaxThreads 10
Persistent

; Modifier-only chords can generate repeated key events while a key is held.
; Keep AutoHotkey's flood protection enabled, but allow normal hold/retry use
; without showing the emergency hotkey-count dialog.
A_HotkeyInterval := 1000
A_MaxHotkeysPerInterval := 250

global BusyTagIsDictating := false
global BusyTagRuntimeScript := A_ScriptDir "\Set-BusyTagDictationState.ps1"
global BusyTagLogDirectory := EnvGet("LOCALAPPDATA") "\XferWorx\BusyTag-WisprFlow\Logs"
global BusyTagRequestFlag := BusyTagLogDirectory "\DictationRequested.flag"
global BusyTagStatusFile := BusyTagLogDirectory "\BusyTagAutomation.status"
global BusyTagPowerShellHostFile := EnvGet("LOCALAPPDATA") "\XferWorx\BusyTag-WisprFlow\Runtime\PowerShellHost.txt"
; 2026-08-20: Use the PowerShell host selected during installation.
; Prior 2026-08-20 logic:
global WindowsPowerShell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"

DirCreate(BusyTagLogDirectory)
try {
    selectedHost := Trim(FileRead(BusyTagPowerShellHostFile))
    if (selectedHost != "" && FileExist(selectedHost))
        WindowsPowerShell := selectedHost
} catch {
    ; Retain the built-in Windows PowerShell fallback when the selection file
    ; is unavailable or unreadable.
    selectedHost := ""
}
WriteBusyTagRuntimeStatus("Running")
SetDictationRequested(false)
OnExit(ShutdownBusyTagRuntime)

; The tilde (~) lets the original Ctrl+Windows keystrokes continue to Wispr Flow.
; Start hooks require the other modifier to already be held, so a standalone Ctrl
; or Windows press cannot enter dictation mode.
; 2026-09-03: Replace broad modifier listeners with chord-specific start hooks so
; standalone Ctrl presses do not trigger a color change.
; ~*LControl::UpdateBusyTagState()
; ~*RControl::UpdateBusyTagState()
; ~*LWin::UpdateBusyTagState()
; ~*RWin::UpdateBusyTagState()
; ~*LControl Up::UpdateBusyTagState()
; ~*RControl Up::UpdateBusyTagState()
; ~*LWin Up::UpdateBusyTagState()
; ~*RWin Up::UpdateBusyTagState()
;
; UpdateBusyTagState(*) {
;     global BusyTagIsDictating
;
;     ctrlIsDown := GetKeyState("LControl", "P") || GetKeyState("RControl", "P")
;     winIsDown := GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
;     chordIsDown := ctrlIsDown && winIsDown
;
;
;     if (chordIsDown && !BusyTagIsDictating) {
;         BusyTagIsDictating := true
;         SetDictationRequested(true)
;         RunBusyTagAction("Start")
;     } else if (!chordIsDown && BusyTagIsDictating) {
;         BusyTagIsDictating := false
;         SetDictationRequested(false)
;         RunBusyTagAction("Stop")
;     }
; }

~^LWin::StartBusyTagDictation()
~^RWin::StartBusyTagDictation()
~#LControl::StartBusyTagDictation()
~#RControl::StartBusyTagDictation()
~*LControl Up::StopBusyTagDictation()
~*RControl Up::StopBusyTagDictation()
~*LWin Up::StopBusyTagDictation()
~*RWin Up::StopBusyTagDictation()

; Starts dictation mode once AutoHotkey detects the second key of a Ctrl+Windows chord.
StartBusyTagDictation(*) {
    global BusyTagIsDictating

    if (BusyTagIsDictating)
        return

    BusyTagIsDictating := true
    SetDictationRequested(true)
    RunBusyTagAction("Start")
}

; Stops dictation mode when either key in an active Ctrl+Windows chord is released.
StopBusyTagDictation(*) {
    global BusyTagIsDictating

    if (!BusyTagIsDictating)
        return

    BusyTagIsDictating := false
    SetDictationRequested(false)
    RunBusyTagAction("Stop")
}

SetDictationRequested(isRequested) {
    global BusyTagRequestFlag

    if (isRequested) {
        try FileDelete(BusyTagRequestFlag)
        FileAppend(A_Now, BusyTagRequestFlag, "UTF-8")
    } else {
        try FileDelete(BusyTagRequestFlag)
    }
}

RunBusyTagAction(action) {
    global BusyTagRuntimeScript, WindowsPowerShell

    command := Format('"{1}" -NoProfile -ExecutionPolicy Bypass -File "{2}" -Action {3}',
        WindowsPowerShell, BusyTagRuntimeScript, action)

    try {
        exitCode := RunWait(command, A_ScriptDir, "Hide")
        if (exitCode != 0)
            TrayTip("BusyTag automation", "The " action " action failed. Check the Logs folder.", 5)
    } catch as err {
        TrayTip("BusyTag automation", err.Message, 5)
    }
}

; Writes the final runtime state and attempts one last restoration when AHK exits.
ShutdownBusyTagRuntime(*) {
    SetDictationRequested(false)
    WriteBusyTagRuntimeStatus("Stopping")
    RunBusyTagAction("Stop")
    WriteBusyTagRuntimeStatus("Stopped")
}

; Publishes a local marker so setup can verify this exact listener loaded.
WriteBusyTagRuntimeStatus(status) {
    global BusyTagStatusFile

    try FileDelete(BusyTagStatusFile)
    statusText := "Status=" status "`nPID=" ProcessExist() "`nScript=" A_ScriptFullPath "`nUpdated=" A_Now "`n"
    FileAppend(statusText, BusyTagStatusFile, "UTF-8")
}
