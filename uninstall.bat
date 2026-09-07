@echo off
chcp 65001 >nul 2>&1
setlocal
cd /d "%~dp0"
echo === omni-free-llm Windows 一键卸载 ===
echo.

set "PWSH="
if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" set "PWSH=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if "%PWSH%"=="" goto NO_PWSH

"%PWSH%" -ExecutionPolicy Bypass -NoProfile -File "%~dp0uninstall.ps1" %*
set "RC=%errorlevel%"
echo.
echo 按任意键关闭本窗口...
pause >nul
exit /b %RC%

:NO_PWSH
echo [!] 未找到 PowerShell，无法自动卸载。
echo     请手动删除目录 %%USERPROFILE%%\.omniroute，并执行 npm uninstall -g omniroute
echo.
echo 按任意键关闭本窗口...
pause >nul
exit /b 1
