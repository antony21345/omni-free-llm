#!/usr/bin/env bash
# omni-free-llm 一键安装入口（Linux / macOS / 国产 Linux：麒麟、统信 UOS、openEuler、Deepin 等）
# 零依赖：只需 bash（系统自带）。检测 Node → 没有则引导安装 → 运行 install.mjs
set -e

# 用 $'...' 而不是 '...'：普通单引号里的 \033 是字面字符，一旦用在 read -p 之类
# 不解释转义序列的地方，就会把 \033[32m 原样吐给用户看。
G=$'\033[32m'; B=$'\033[36m'; Y=$'\033[33m'; R=$'\033[31m'; D=$'\033[0m'

detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)
      if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "linux:${ID:-linux}"
      else echo "linux"; fi ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) echo "unknown" ;;
  esac
}
OS=$(detect_os)

# 检测 Node
if command -v node >/dev/null 2>&1; then
  echo -e "${G}✔${D} 检测到 Node $(node -v)"
else
  echo -e "${Y}⚠${D} 未检测到 Node.js，正在引导安装…"
  case "$OS" in
    macos)
      if command -v brew >/dev/null 2>&1; then
        # 注意：不要用 node@22 —— 它是 keg-only，不会 symlink 进 PATH，装完 command -v node 仍然找不到
        # 加 || true：set -e 下 brew 任何非零返回（哪怕只是警告）都会让脚本静默退出，成败交给下面的 command -v node 判断
        echo "正在用 Homebrew 安装 Node…"; brew install node || true
      else
        echo -e "请先安装 Homebrew（${B}https://brew.sh${D}），或直接下载 Node LTS 安装包：${B}https://nodejs.org${D}"
        exit 1
      fi ;;
    linux:debian|linux:ubuntu|linux:kylin|linux:uos|linux:deepin)
      echo "尝试用 NodeSource 安装 Node 22…"
      curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt-get install -y nodejs || {
        echo -e "${Y}自动安装失败${D}，请手动：sudo apt install nodejs npm 或下载 ${B}https://nodejs.org${D}"; exit 1; } ;;
    linux:openEuler|linux:rhel|linux:centos|linux:fedora|linux:rocky|linux:almalinux)
      echo "尝试用 dnf 安装 Node…"
      sudo dnf install -y nodejs npm || { echo -e "${Y}自动安装失败${D}，请下载 ${B}https://nodejs.org${D}"; exit 1; } ;;
    linux:*)
      echo -e "请按你的发行版安装 Node 22+（${B}https://nodejs.org${D} 下载，或用包管理器）。装好后重跑本脚本。"
      exit 1 ;;
  esac
  if ! command -v node >/dev/null 2>&1; then
    echo -e "${R}✖ Node 装好了但这个 shell 找不到它${D}"
    echo -e "  多半是 PATH 问题，不是 Node 没装上。诊断信息："
    echo -e "    brew:        $(command -v brew 2>/dev/null || echo 找不到)"
    echo -e "    期望 node:   $(brew --prefix 2>/dev/null)/bin/node"
    echo -e "    是否存在:    $([ -x "$(brew --prefix 2>/dev/null)/bin/node" ] && echo 是 || echo 否)"
    echo -e "    PATH:        $PATH"
    echo -e "  最快解决：${B}关掉这个窗口，重新开一个${D}，再跑一次。"
    exit 1
  fi
  echo -e "${G}✔${D} Node $(node -v) 就绪"
fi

# 定位 install.mjs（本地同目录，远程则下载）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="$SCRIPT_DIR/install.mjs"
if [ ! -f "$INSTALLER" ]; then
  BASE_URL="${OMNI_BASE_URL:-}"
  if [ -z "$BASE_URL" ]; then
    echo -e "${R}✖ 找不到 install.mjs${D}。请在本目录运行，或设置 OMNI_BASE_URL 指向托管地址。"
    exit 1
  fi
  echo ">>> 从 $BASE_URL 下载 install.mjs …"
  INSTALLER="$(mktemp --suffix=.mjs)"
  curl -fsSL "$BASE_URL/install.mjs" -o "$INSTALLER"
fi

echo -e "${B}>>> 运行安装器（交互式）…${D}"
exec node "$INSTALLER" "$@"
