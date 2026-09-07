# omni-free-llm 卸载（逐项可选，删前强提示）
# 不会删除：Node.js / Docker 本身 —— 其它项目可能在用
$ErrorActionPreference = "Continue"

Write-Host "=== omni-free-llm 卸载 ===" -ForegroundColor Cyan
Write-Host ""

$dir = $env:OMNI_DIR
if (-not $dir) { $dir = Join-Path $env:USERPROFILE ".omniroute" }
if ($args.Count -ge 1 -and $args[0]) { $dir = $args[0] }
$dir = $dir.TrimEnd('\', '/')

if ([string]::IsNullOrWhiteSpace($dir) -or $dir -match '^[A-Za-z]:$' -or $dir -eq $env:USERPROFILE) {
    Write-Host "X 拒绝操作：目录 '$dir' 不安全" -ForegroundColor Red
    Read-Host "按回车退出"; exit 1
}

$port = 20128
$cfgPath = Join-Path $dir "config.json"
$memDir  = Join-Path $dir "memory"
if (Test-Path $cfgPath) { try { $p = (Get-Content $cfgPath -Raw | ConvertFrom-Json).port; if ($p) { $port = [int]$p } } catch {} }

function HumanSize($bytes) { if ($bytes -ge 1GB) { "{0:N1} GB" -f ($bytes/1GB) } elseif ($bytes -ge 1MB) { "{0:N1} MB" -f ($bytes/1MB) } elseif ($bytes -ge 1KB) { "{0:N0} KB" -f ($bytes/1KB) } else { "$bytes B" } }
function DirSize($path) { if (Test-Path $path) { try { HumanSize (Get-ChildItem $path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } catch { "-" } } else { "-" } }

$memDays = 0; $memCnt = 0; $memSize = "-"
if (Test-Path $memDir) {
    $memDays = @(Get-ChildItem $memDir -Filter *.md -ErrorAction SilentlyContinue).Count
    $idxPath = Join-Path $memDir "index.json"
    if (Test-Path $idxPath) { try { $memCnt = @((Get-Content $idxPath -Raw | ConvertFrom-Json).items).Count } catch {} }
    $memSize = DirSize $memDir
}
$dirSize = DirSize $dir
$npmSize = "-"
try { $nr = (& npm root -g 2>$null); if ($nr -and (Test-Path (Join-Path $nr "omniroute"))) { $npmSize = DirSize (Join-Path $nr "omniroute") } } catch {}
$svc = "未运行"
try { if (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop) { $svc = "运行中" } } catch {}

# Node 怎么装的决定怎么卸：winget 能自动卸，官网 .msi 只能给手工步骤
$nodeDesc = "未安装"; $nodeWinget = $false; $nodeVer = ""
if (Get-Command node -ErrorAction SilentlyContinue) {
    $nodeVer = (& node -v 2>$null)
    $nodeDesc = "$nodeVer @ " + (Get-Command node).Source
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $wl = (winget list --id OpenJS.NodeJS 2>$null | Out-String)
        if ($wl -match "OpenJS.NodeJS") { $nodeWinget = $true }
    }
}
$npmCache = "-"; $npmCachePath = ""
try { $npmCachePath = (& npm config get cache 2>$null).Trim() } catch {}
if ($npmCachePath -and (Test-Path $npmCachePath)) { $npmCache = DirSize $npmCachePath }

Write-Host "可以删除的项目（逐项可选）：" -ForegroundColor White
Write-Host ""
Write-Host "  1  停止正在运行的服务                当前：$svc" -NoNewline; Write-Host "      可逆，随时能再启动" -ForegroundColor Green
if (Test-Path $memDir) { Write-Host "  2  全部对话记忆 memory\              $memDays 天 / $memCnt 条 / $memSize" -NoNewline; Write-Host "   ! 不可恢复" -ForegroundColor Red }
else { Write-Host "  2  全部对话记忆 memory\              （不存在，跳过）" }
if (Test-Path $cfgPath) { Write-Host "  3  配置 config.json（API key + 管理密码）" -NoNewline; Write-Host "        ! 不可恢复" -ForegroundColor Red }
else { Write-Host "  3  配置 config.json                  （不存在，跳过）" }
Write-Host "  4  整个安装目录（含 2、3 和数据库）  $dir  $dirSize" -NoNewline; Write-Host "   ! 不可恢复" -ForegroundColor Red
Write-Host "  5  全局 npm 包 omniroute             $npmSize" -NoNewline; Write-Host "              可重新安装" -ForegroundColor Green
Write-Host "  6  omni 命令（omni.cmd + 用户级 PATH 条目）" -NoNewline; Write-Host "      可逆" -ForegroundColor Green
Write-Host "  7  Docker 容器 omniroute" -NoNewline; Write-Host "                          可逆" -ForegroundColor Green
if ($nodeWinget) {
    Write-Host "  8  Node.js（$nodeVer，winget 装的）" -NoNewline; Write-Host "        ! 其它 Node 项目会失效" -ForegroundColor Red
} elseif ($nodeDesc -ne "未安装") {
    Write-Host "  8  Node.js（$nodeDesc）" -NoNewline; Write-Host "        不是 winget 装的，只能给你手工步骤" -ForegroundColor Yellow
} else {
    Write-Host "  8  Node.js                              （未安装，跳过）"
}
Write-Host "  9  npm 下载缓存与日志                    缓存 $npmCache" -NoNewline; Write-Host "        可重新下载" -ForegroundColor Green
Write-Host ""
Write-Host "始终不会删除：Node.js、Docker 本身 —— 其它项目可能正在用它们。" -ForegroundColor Green
Write-Host ""
$sel = Read-Host "输入要删除的编号，空格分隔（如 2 5）；a=一键全删（1-9，含 Node）；直接回车取消"
if ([string]::IsNullOrWhiteSpace($sel)) { Write-Host "已取消，什么都没有改动。" -ForegroundColor Green; Read-Host "按回车退出"; exit 0 }
$raw = $sel
# 逗号、全角逗号、顿号、分号都当分隔符，别让分隔符写法不同就静默什么都不做
$sel = $sel -replace '[,，、;；/]', ' '
if ($sel.Trim().ToLower() -eq "a" -or $sel.Trim().ToLower() -eq "all") { $sel = "1 2 3 4 5 6 7 8 9" }
$picked = @($sel -split '\s+' | Where-Object { $_ -match '^[1-9]$' })
if ($picked.Count -eq 0) {
    Write-Host ""
    Write-Host "X 没识别出任何有效编号，什么都没有改动。" -ForegroundColor Red
    Write-Host "  你输入的是：「$raw」"
    Write-Host "  请输入 1 到 9 之间的数字，多个用空格或逗号分隔（例：2 5 或 2,5）；"
    Write-Host "  想全部删除就只输入一个字母 a。"
    Read-Host "按回车退出"; exit 1
}
Write-Host ""
Write-Host ("已识别的编号：" + ($picked -join ' ')) -ForegroundColor Cyan
function Has($n) { return $picked -contains "$n" }

Write-Host ""
Write-Host "即将执行以下操作：" -ForegroundColor Red
if (Has 1) { Write-Host "  - 停止端口 $port 上的服务（$svc）" }

if ((Has 2) -or (Has 3) -or (Has 4)) {
    Write-Host ""
    Write-Host "  按文件类型列出将被删除的内容：" -ForegroundColor White
    if ((Has 4) -or (Has 2)) {
        if (Test-Path $memDir) {
            $n = @(Get-ChildItem $memDir -Filter *.md -ErrorAction SilentlyContinue).Count
            if ($n -gt 0) { Write-Host "    - 对话记录  *.md x $n        你和 AI 的全部问答原文（$memDir）" -ForegroundColor Red }
            if (Test-Path (Join-Path $memDir "index.json")) { Write-Host "    - 记忆索引  index.json        关键词索引，删了记忆检索就没了" -ForegroundColor Red }
        }
    }
    if (((Has 4) -or (Has 3)) -and (Test-Path $cfgPath)) { Write-Host "    - 配置文件  config.json        含 API key 与管理面板密码" -ForegroundColor Red }
    if (Has 4) {
        foreach ($it in @(
            @{f="storage.sqlite"; l="数据库    "; d="omniroute 的全部数据（提供者、用量、密钥）"},
            @{f="storage.sqlite-wal"; l="数据库日志"; d="未落盘的写入"},
            @{f=".env"; l="环境变量  "; d="含存储加密密钥"})) {
            $fp = Join-Path $dir $it.f
            if (Test-Path $fp) { Write-Host ("    - " + $it.l + "  " + $it.f + " (" + (DirSize $fp) + ")        " + $it.d) -ForegroundColor Red }
        }
        if (@(Get-ChildItem $dir -Filter "omni*.mjs" -ErrorAction SilentlyContinue).Count -gt 0) { Write-Host "    - 脚本      omni*.mjs        omni 命令本体（可重装恢复）" -ForegroundColor Red }
        if (Test-Path (Join-Path $dir "logs")) { Write-Host "    - 日志目录  logs\        服务运行日志" -ForegroundColor Red }
        if (Test-Path (Join-Path $dir "db_backups")) { Write-Host "    - 数据库备份 db_backups\        omniroute 自己做的备份" -ForegroundColor Red }
    }
    Write-Host ""
}

if (Has 4) { Write-Host "  - 删除整个目录 $dir（$dirSize）—— 含对话记忆、API key、管理密码、数据库，全部不可恢复" -ForegroundColor Red }
else {
    if ((Has 2) -and (Test-Path $memDir)) { Write-Host "  - 删除 $memDir —— $memDays 天 / $memCnt 条对话记忆，不可恢复" -ForegroundColor Red }
    if ((Has 3) -and (Test-Path $cfgPath)) { Write-Host "  - 删除 $cfgPath —— 含 API key 与管理密码，不可恢复" -ForegroundColor Red }
}
if (Has 5) { Write-Host "  - 卸载全局 npm 包 omniroute（$npmSize，之后可重新安装）" }
if (Has 6) { Write-Host "  - 删除 omni.cmd 并从用户级 PATH 移除安装目录" }
if (Has 7) { Write-Host "  - 删除 Docker 容器 omniroute（镜像会再问一次）" }
if (Has 8) {
    if ($nodeWinget) { Write-Host "  - 卸载 Node.js $nodeVer —— 这台机器上其它依赖 Node 的项目会失效" -ForegroundColor Red }
    elseif ($nodeDesc -ne "未安装") { Write-Host "  - Node.js 不是 winget 装的，脚本不动它，结束时给你手工步骤" -ForegroundColor Yellow }
}
if (Has 9) { Write-Host "  - 清空 npm 下载缓存（$npmCache）与日志" }
Write-Host ""

if (((Has 2) -or (Has 3) -or (Has 4)) -and ((Test-Path $cfgPath) -or (Test-Path $memDir))) {
    $bk = Read-Host "先把 config.json 和对话记忆备份一份再删？(Y/n)"
    if ($bk -ne "n" -and $bk -ne "N") {
        $bkDir = Join-Path $env:USERPROFILE "Desktop"
        if (-not (Test-Path $bkDir)) { $bkDir = $env:USERPROFILE }
        $ts = Get-Date -Format "yyyyMMdd-HHmmss"
        if (Test-Path $cfgPath) {
            $bkFile = Join-Path $bkDir ("omniroute-config-backup-" + $ts + ".json")
            try { Copy-Item $cfgPath $bkFile -Force; Write-Host "  [OK] 配置已备份到 $bkFile" -ForegroundColor Green }
            catch { Write-Host "  [!] 配置备份失败" -ForegroundColor Yellow }
        }
        if (Test-Path $memDir) {
            $memBk = Join-Path $bkDir ("omniroute-memory-backup-" + $ts)
            try { Copy-Item $memDir $memBk -Recurse -Force; Write-Host "  [OK] 对话记忆已备份到 $memBk" -ForegroundColor Green }
            catch { Write-Host "  [!] 记忆备份失败" -ForegroundColor Yellow }
        }
    }
    Write-Host ""
}

$ans = Read-Host "确认执行？输入 yes 继续（其它任何内容都会取消）"
if ($ans -ne "yes") { Write-Host "已取消，什么都没有改动。" -ForegroundColor Green; Read-Host "按回车退出"; exit 0 }
Write-Host ""

if ((Has 1) -or (Has 4) -or (Has 5)) {
    Write-Host "> 停止服务…" -ForegroundColor Cyan
    $omniMjs = Join-Path $dir "omni.mjs"
    if ((Test-Path $omniMjs) -and (Get-Command node -ErrorAction SilentlyContinue)) { try { & node $omniMjs down 2>$null | Out-Null } catch {} }
    $killed = 0
    try {
        foreach ($c in (Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction Stop)) { try { Stop-Process -Id $c.OwningProcess -Force -ErrorAction Stop; $killed++ } catch {} }
    } catch {
        foreach ($l in (netstat -ano | Select-String ":$port\s.*LISTENING")) { if ("$l" -match '(\d+)\s*$') { try { Stop-Process -Id $matches[1] -Force -ErrorAction Stop; $killed++ } catch {} } }
    }
    if ($killed -gt 0) { Write-Host "  已结束 $killed 个进程" } else { Write-Host "  端口 $port 上没有进程" }
}

if (Has 7) {
    Write-Host "> 清理 Docker…" -ForegroundColor Cyan
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        docker rm -f omniroute 2>$null | Out-Null; Write-Host "  已尝试删除容器 omniroute"
        if (docker images -q diegosouzapw/omniroute 2>$null) {
            $rmimg = Read-Host "  还有镜像 diegosouzapw/omniroute（数百 MB），一并删除？(y/N)"
            if ($rmimg -eq "y" -or $rmimg -eq "Y") { docker rmi -f diegosouzapw/omniroute:latest 2>$null | Out-Null; Write-Host "  已尝试删除镜像" }
            else { Write-Host "  已保留镜像" }
        }
    } else { Write-Host "  没装 Docker，跳过" }
}

if (Has 5) {
    Write-Host "> 卸载全局 npm 包…" -ForegroundColor Cyan
    if (Get-Command npm -ErrorAction SilentlyContinue) { cmd /c "npm uninstall -g omniroute" 2>$null | Out-Null; Write-Host "  已尝试卸载" }
    else { Write-Host "  没装 npm，跳过" }
}

if (Has 6) {
    Write-Host "> 清理 omni 命令…" -ForegroundColor Cyan
    $cmdFile = Join-Path $dir "omni.cmd"
    if (Test-Path $cmdFile) { try { Remove-Item $cmdFile -Force; Write-Host "  已删除 omni.cmd" } catch {} }
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($userPath) {
        $parts = $userPath -split ';' | Where-Object { $_ -and ($_.TrimEnd('\','/') -ne $dir) }
        $newPath = ($parts -join ';')
        if ($newPath -ne $userPath) { [Environment]::SetEnvironmentVariable('Path', $newPath, 'User'); Write-Host "  已移除 PATH 条目（需重开 cmd 窗口才生效）" }
        else { Write-Host "  PATH 里没有该条目" }
    }
}

if (Has 9) {
    Write-Host "> 清理 npm 缓存与日志…" -ForegroundColor Cyan
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        cmd /c "npm cache clean --force" 2>$null | Out-Null; Write-Host "  已清空 npm 缓存"
    }
    $npmLogs = Join-Path $env:APPDATA "npm-cache\_logs"
    if (Test-Path $npmLogs) { try { Remove-Item "$npmLogs\*.log" -Force -ErrorAction SilentlyContinue; Write-Host "  已删除 npm 日志" } catch {} }
}

if ((Has 8) -and $nodeWinget) {
    Write-Host "> 卸载 Node.js…" -ForegroundColor Cyan
    winget uninstall --id OpenJS.NodeJS --silent 2>$null | Out-Null
    winget uninstall --id OpenJS.NodeJS.LTS --silent 2>$null | Out-Null
    if (Get-Command node -ErrorAction SilentlyContinue) { Write-Host "  [!] node 命令仍在，可能需要重开终端或手动卸载" -ForegroundColor Yellow }
    else { Write-Host "  已卸载 Node.js" }
}

if (Has 4) {
    Write-Host "> 删除整个安装目录…" -ForegroundColor Cyan
    if (Test-Path $dir) {
        try { Remove-Item $dir -Recurse -Force -ErrorAction Stop; Write-Host "  已删除 $dir" }
        catch { Write-Host "  X 删除失败：$($_.Exception.Message)" -ForegroundColor Red }
    } else { Write-Host "  目录不存在" }
} else {
    if ((Has 2) -and (Test-Path $memDir)) {
        Write-Host "> 删除对话记忆…" -ForegroundColor Cyan
        try { Remove-Item $memDir -Recurse -Force -ErrorAction Stop; Write-Host "  已删除 $memDir" } catch { Write-Host "  X 删除失败" -ForegroundColor Red }
    }
    if ((Has 3) -and (Test-Path $cfgPath)) {
        Write-Host "> 删除配置…" -ForegroundColor Cyan
        try { Remove-Item $cfgPath -Force -ErrorAction Stop; Write-Host "  已删除 $cfgPath" } catch { Write-Host "  X 删除失败" -ForegroundColor Red }
    }
}

$defDir = Join-Path $env:USERPROFILE ".omniroute"
if ((Has 4) -and ($dir -ne $defDir) -and (Test-Path $defDir)) {
    Write-Host ""
    Write-Host "  另外发现 omniroute 的默认数据目录：$defDir（数据库、凭据都在这里）" -ForegroundColor Yellow
    $rmdef = Read-Host "  一并删除？(y/N)"
    if ($rmdef -eq "y" -or $rmdef -eq "Y") { try { Remove-Item $defDir -Recurse -Force; Write-Host "  已删除 $defDir" } catch { Write-Host "  X 删除失败" -ForegroundColor Red } }
    else { Write-Host "  已保留 $defDir" }
}

Write-Host ""
Write-Host ("[OK] 完成。本次处理的编号：" + ($picked -join ' ')) -ForegroundColor Green
if ((Has 8) -and (-not $nodeWinget) -and ($nodeDesc -ne "未安装")) {
    Write-Host ""
    Write-Host "关于 Node.js（不是 winget 装的，脚本没动）"
    Write-Host "  当前：$nodeDesc"
    Write-Host "  如果是官网 .msi 装的：设置 > 应用 > 已安装的应用 > 找到 Node.js > 卸载"
    Write-Host "  或命令行：winget uninstall --id OpenJS.NodeJS"
    Write-Host "  卸载后残留目录可手动删除：%ProgramFiles%\nodejs 和 %APPDATA%\npm"
}
if (Has 6) { Write-Host "提示：重开一个 cmd 窗口，omni 命令才会彻底消失。" -ForegroundColor Yellow }
