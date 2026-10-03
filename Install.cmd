@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Install.ps1" %*
if errorlevel 1 echo Installation failed. Read the message above before retrying.
pause
