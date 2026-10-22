' Starts ClaudeUsageTray without a console flash (window style 0).
Dim dir : dir = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & dir & "\ClaudeUsageTray.ps1""", 0, False
