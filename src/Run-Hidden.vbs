Option Explicit

' Run-Hidden.vbs
' Silent execution wrapper for win-power-toggle desktop shortcuts.
' Launches Switch-Mode.ps1 via PowerShell with -ExecutionPolicy Bypass and
' no visible console window.
'
' Examples:
'   wscript.exe "C:\path\to\win-power-toggle\src\Run-Hidden.vbs" battery
'   wscript.exe "C:\path\to\win-power-toggle\src\Run-Hidden.vbs" -Mode gaming

Function QuoteIfNeeded(ByVal value)
    Dim escaped
    escaped = Replace(value, """", "\""")
    If Len(escaped) = 0 Or InStr(escaped, " ") > 0 Or InStr(escaped, vbTab) > 0 Then
        QuoteIfNeeded = """" & escaped & """"
    Else
        QuoteIfNeeded = escaped
    End If
End Function

Dim argCount
argCount = WScript.Arguments.Count
If argCount = 0 Then
    WScript.Quit 1
End If

Dim fso, shell, scriptDir, psScriptPath
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScriptPath = fso.BuildPath(scriptDir, "Switch-Mode.ps1")

If Not fso.FileExists(psScriptPath) Then
    WScript.Quit 2
End If

Dim forwardedArgs, firstArgLower, i
firstArgLower = LCase(Trim(WScript.Arguments(0)))

If argCount = 1 And (firstArgLower = "battery" Or firstArgLower = "gaming") Then
    forwardedArgs = "-Mode " & firstArgLower
Else
    forwardedArgs = ""
    For i = 0 To argCount - 1
        If i > 0 Then
            forwardedArgs = forwardedArgs & " "
        End If
        forwardedArgs = forwardedArgs & QuoteIfNeeded(WScript.Arguments(i))
    Next
End If

Dim command
command = "powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & psScriptPath & """ " & forwardedArgs

' Window style 0 = hidden, False = do not block caller
shell.Run command, 0, False
WScript.Quit 0
