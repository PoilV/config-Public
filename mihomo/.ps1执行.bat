@echo off
if "%~1"=="" exit /b
if /i not "%~x1"==".ps1" exit /b
pwsh.exe -ExecutionPolicy Bypass -File "%~1"
exit /b