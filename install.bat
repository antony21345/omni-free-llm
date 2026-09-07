@echo off
chcp 65001 >nul 2>&1
setlocal
cd /d "%~dp0"
echo === omni-free-llm Windows 安装器 ===
echo.

where node >nul 2>&1
if errorlevel 1 goto NO_NODE

echo [OK] 检测到 Node:
node -v
echo.
node install.mjs %*
set "RC=%errorlevel%"
echo.
if not "%RC%"=="0" echo [X] 安装器异常退出，错误码 %RC%（上面就是原因，截图发我）
echo.
echo 按任意键关闭本窗口...
pause >nul
exit /b %RC%

:NO_NODE
echo [!] 未检测到 Node.js，正在尝试用 PowerShell 自动装 Node 并继续...
set "PWSH="
if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" set "PWSH=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if "%PWSH%"=="" goto NO_PWSH

echo [OK] 找到 PowerShell，正在启动 install.ps1...
"%PWSH%" -ExecutionPolicy Bypass -NoProfile -File "%~dp0install.ps1" %*
set "RC=%errorlevel%"
echo.
echo 按任意键关闭本窗口...
pause >nul
exit /b %RC%

:NO_PWSH
echo [!] 未找到 PowerShell。请手动二选一：
echo     1) 访问 https://nodejs.org 下载安装 Node LTS
echo     2) 或在 PowerShell 里运行: powershell -ExecutionPolicy Bypass -File install.ps1
echo.
echo 按任意键关闭本窗口...
pause >nul
exit /b 1
