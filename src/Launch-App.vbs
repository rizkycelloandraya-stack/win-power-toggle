Option Explicit

' Launch-App.vbs
' Silent launcher for the Win-Power-Toggle WPF desktop and system-tray app.
' Double-click this file (or create a shortcut to it) to open the GUI with
' no visible PowerShell console window.

Function QuoteIfNeeded(ByVal value)
    Dim escaped
    escaped = Replace(value, """", "\""")
    If Len(escaped) = 0 Or InStr(escaped, " ") > 0 Or InStr(escaped, vbTab) > 0 Then
        QuoteIfNeeded = """" & escaped & """"
    Else
        QuoteIfNeeded = escaped
    End If
End Function

Dim fso, shell, scriptDir, appScriptPath
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
appScriptPath = fso.BuildPath(scriptDir, "WinPowerToggle-App.ps1")

If Not fso.FileExists(appScriptPath) Then
    WScript.Quit 2
End If

Dim extraArgs, i
extraArgs = ""
For i = 0 To WScript.Arguments.Count - 1
    extraArgs = extraArgs & " " & QuoteIfNeeded(WScript.Arguments(i))
Next

Dim command
command = "powershell.exe -STA -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & appScriptPath & """" & extraArgs

shell.Run command, 0, False
WScript.Quit 0
