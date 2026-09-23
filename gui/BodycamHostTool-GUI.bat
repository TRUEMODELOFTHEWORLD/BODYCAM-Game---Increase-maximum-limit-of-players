@echo off
start "Bodycam Host Tool" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%~dp0BodycamHostTool-GUI.ps1"
