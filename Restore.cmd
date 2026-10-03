@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Restore.ps1" %*
if errorlevel 1 echo Restore failed. Read the message above before retrying.
pause
