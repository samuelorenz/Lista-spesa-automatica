@echo off
rem Doppio clic: rinomina le foto presenti in Scontrini\Nuovi e resta in ascolto per le nuove.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Rinomina-Scontrini.ps1" -Watch
pause
