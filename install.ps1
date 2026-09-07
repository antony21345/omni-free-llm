# omni-free-llm 一键安装入口（Windows PowerShell）
# 零依赖：Windows 自带 PowerShell。检测 Node → 没有则引导安装 → 运行 install.mjs
$ErrorActionPreference = "Stop"

function Write-C($msg, $color) { Write-Host $msg -ForegroundColor $color -NoNewline; Write-Host "" }

# 检测 Node
$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
    Write-Host "✔ 检测到 Node $(& node -v)" -ForegroundColor Green
} else {
    Write-Host "⚠ 未检测到 Node.js，正在引导安装…" -ForegroundColor Yellow
    # 优先 winget（Win10/11 自带）
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Host "用 winget 安装 Node LTS…"
        winget install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements
    } else {
        Write-Host "未找到 winget。请手动下载安装 Node LTS：https://nodejs.org" -ForegroundColor Yellow
        Write-Host "装好后重新运行本脚本。" -ForegroundColor Yellow
        exit 1
    }
    # winget 安装后需要刷新 PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    $node = Get-Command node -ErrorAction SilentlyContinue
    if (-not $node) {
        Write-Host "✖ Node 安装后仍未就绪，请重开终端或手动装 https://nodejs.org" -ForegroundColor Red
        exit 1
    }
    Write-Host "✔ Node $(& node -v) 就绪" -ForegroundColor Green
}

# 定位 install.mjs
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Installer = Join-Path $ScriptDir "install.mjs"
if (-not (Test-Path $Installer)) {
    $BaseUrl = $env:OMNI_BASE_URL
    if (-not $BaseUrl) { Write-Host "✖ 找不到 install.mjs，请在本目录运行或设置 OMNI_BASE_URL" -ForegroundColor Red; exit 1 }
    Write-Host ">>> 从 $BaseUrl 下载 install.mjs …"
    $Installer = Join-Path $env:TEMP "omniroute-install.mjs"
    Invoke-WebRequest -Uri "$BaseUrl/install.mjs" -OutFile $Installer
}

Write-Host ">>> 运行安装器（交互式）…" -ForegroundColor Cyan
& node $Installer @args
