#!/usr/bin/env bash
# omni-free-llm 卸载（逐项可选，删前强提示）
# 不会删除：Node.js / Homebrew / Docker 本身 —— 其它项目可能在用
set -u

# 用 $'...' 而不是 '...'：这样 \033 在赋值时就成了真正的 ESC 字符。
# read -p 的提示语不会解释转义序列，用普通单引号的话会把 \033[1m 原样吐给用户看。
G=$'\033[32m'; B=$'\033[36m'; Y=$'\033[33m'; R=$'\033[31m'; D=$'\033[0m'; BD=$'\033[1m'

DIR="${OMNI_DIR:-$HOME/.omniroute}"
[ $# -ge 1 ] && [ -n "${1:-}" ] && DIR="$1"
DIR="${DIR%/}"

echo -e "${BD}${B}=== omni-free-llm 卸载 ===${D}\n"

# 安全校验：拒绝对空路径 / 根 / HOME 本身动手
case "$DIR" in
  ""|"/"|"$HOME") echo -e "${R}✖ 拒绝操作：目录 '$DIR' 不安全${D}"; exit 1 ;;
esac

PORT=20128
if [ -f "$DIR/config.json" ]; then
  p=$(grep -o '"port"[[:space:]]*:[[:space:]]*[0-9]*' "$DIR/config.json" 2>/dev/null | grep -o '[0-9]*$' | head -1)
  [ -n "${p:-}" ] && PORT="$p"
fi

# ---- 摸清各项的实际体量，菜单里直接显示 ----
MEMDAYS=0; MEMCNT=0; MEMSIZE="-"
if [ -d "$DIR/memory" ]; then
  MEMDAYS=$(ls "$DIR/memory"/*.md 2>/dev/null | wc -l | tr -d " ")
  MEMCNT=$(grep -o '"id"' "$DIR/memory/index.json" 2>/dev/null | wc -l | tr -d " ")
  MEMSIZE=$(du -sh "$DIR/memory" 2>/dev/null | cut -f1 | tr -d " ")
fi
DIRSIZE=$(du -sh "$DIR" 2>/dev/null | cut -f1 | tr -d " ")
NPMSIZE="-"
if command -v npm >/dev/null 2>&1; then
  NR=$(npm root -g 2>/dev/null)
  [ -n "${NR:-}" ] && [ -d "$NR/omniroute" ] && NPMSIZE=$(du -sh "$NR/omniroute" 2>/dev/null | cut -f1 | tr -d " ")
fi
SVC="未运行"
if command -v lsof >/dev/null 2>&1 && [ -n "$(lsof -ti "tcp:$PORT" 2>/dev/null)" ]; then SVC="运行中"; fi

# Node 是不是 brew 装的？只有 brew 装的才能干净卸掉；官网安装包装的只给手工步骤
NODE_BREW=0; NODE_DESC="未安装"; NODE_SIZE="-"; NODE_WHEN=""
if command -v node >/dev/null 2>&1; then
  NODE_DESC="$(node -v 2>/dev/null) @ $(command -v node)"
  if command -v brew >/dev/null 2>&1 && brew list --formula 2>/dev/null | grep -qx node; then
    NODE_BREW=1
    NODE_SIZE=$(du -sh "$(brew --prefix 2>/dev/null)/Cellar/node" 2>/dev/null | cut -f1)
    # node 自己 + 它拉进来的依赖一起算，才是真实占用
    NODE_ALL=$( { echo "$(brew --prefix)/Cellar/node"; brew deps node 2>/dev/null | sed "s|^|$(brew --prefix)/Cellar/|"; } | xargs du -sk 2>/dev/null | awk '{t+=$1} END{if(t>1048576) printf "%.1fG", t/1048576; else printf "%.0fM", t/1024}')
    NODE_WHEN=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M" "$(brew --prefix 2>/dev/null)"/Cellar/node/* 2>/dev/null | head -1)
    NODE_DEPS=$(brew deps node 2>/dev/null | wc -l | tr -d " ")
  fi
fi
NPM_CACHE="-"; NPM_LOGS="-"
[ -d "$HOME/.npm/_cacache" ] && NPM_CACHE=$(du -sh "$HOME/.npm/_cacache" 2>/dev/null | cut -f1 | tr -d " ")
[ -d "$HOME/.npm/_logs" ] && NPM_LOGS="$(ls "$HOME/.npm/_logs"/*.log 2>/dev/null | wc -l | tr -d " ") 个 / $(du -sh "$HOME/.npm/_logs" 2>/dev/null | cut -f1)"

echo -e "${BD}可以删除的项目（逐项可选）：${D}\n"
echo -e "  ${G}1${D}  停止正在运行的服务                      当前：$SVC          ${G}可逆，随时能再启动${D}"
if [ -d "$DIR/memory" ]; then
  echo -e "  ${G}2${D}  全部对话记忆 memory/                    $MEMDAYS 天 / $MEMCNT 条 / $MEMSIZE   ${R}⚠ 不可恢复${D}"
else
  echo -e "  ${G}2${D}  全部对话记忆 memory/                    （不存在，跳过）"
fi
if [ -f "$DIR/config.json" ]; then
  echo -e "  ${G}3${D}  配置 config.json（API key + 管理密码）                        ${R}⚠ 不可恢复${D}"
else
  echo -e "  ${G}3${D}  配置 config.json                        （不存在，跳过）"
fi
echo -e "  ${G}4${D}  整个安装目录（含 2、3 和数据库）        $DIR  $DIRSIZE   ${R}⚠ 不可恢复${D}"
echo -e "  ${G}5${D}  全局 npm 包 omniroute                   $NPMSIZE              ${G}可重新安装${D}"
echo -e "  ${G}6${D}  shell 里的 omni 命令（alias）                                 ${G}可逆${D}"
echo -e "  ${G}7${D}  Docker 容器 omniroute                                         ${G}可逆${D}"
if [ "$NODE_BREW" = "1" ]; then
  echo -e "  ${G}8${D}  Node.js + ${NODE_DEPS:-0} 个依赖（brew 装于 ${NODE_WHEN}）  ${NODE_ALL:-$NODE_SIZE}   ${R}⚠ 其它 Node 项目会失效${D}"
elif [ "$NODE_DESC" != "未安装" ]; then
  echo -e "  ${G}8${D}  Node.js（${NODE_DESC}）                        ${Y}不是 brew 装的，只能给你手工步骤${D}"
else
  echo -e "  ${G}8${D}  Node.js                                 （未安装，跳过）"
fi
echo -e "  ${G}9${D}  npm 下载缓存与日志                      缓存 $NPM_CACHE / 日志 $NPM_LOGS   ${G}可重新下载${D}"
echo
echo -e "${G}脚本不会自动删除：${D}Homebrew 本身 —— 它不是这个安装器装的（装它的时间早得多）。"
echo -e "  选了 8 之后，卸载 Homebrew 的官方命令会在结束时打印给你，由你决定跑不跑。"
echo
# 说明用 echo -e 打印（颜色能正常渲染），read 的提示语只留纯文本 ——
# read -p 不解释转义序列，也不是所有终端都吃 ANSI，提示语里放颜色码会变成乱码。
echo -e "  选择方式："
echo -e "    · 删指定项：输入编号，多个用空格或逗号分隔，例如  ${BD}2 5${D}  或  ${BD}2,5${D}"
echo -e "    · 一键全删：输入一个字母  ${BD}a${D}   （等于选中 1-9 全部，含 Node.js）"
echo -e "    · 取消退出：直接按回车"
echo
read -r -p "你的选择: " SEL
RAW="${SEL:-}"
[ -z "$(echo "${SEL:-}" | tr -d ' ')" ] && { echo -e "${G}已取消，什么都没有改动。${D}"; exit 0; }
# 逗号、全角逗号、顿号、分号都当分隔符 —— 别让分隔符写法不同就静默什么都不做
SEL=$(echo "$SEL" | tr ',，、;；/' ' ' | tr -s ' ')
case "$(echo "$SEL" | tr -d ' ')" in a|A|all|ALL) SEL="1 2 3 4 5 6 7 8 9" ;; esac
# 只保留 1-9，其它一概丢掉
SEL_OK=""
for x in $SEL; do
  case "$x" in [1-9]) SEL_OK="$SEL_OK $x" ;; esac
done
SEL=$(echo "$SEL_OK" | tr -s ' ' | sed 's/^ //;s/ $//')
if [ -z "$SEL" ]; then
  echo
  echo -e "${R}✖ 没识别出任何有效编号，什么都没有改动。${D}"
  echo -e "  你输入的是：「${RAW}」"
  echo -e "  请输入 ${BD}1 到 9${D} 之间的数字，多个用空格或逗号分隔（例：${BD}2 5${D} 或 ${BD}2,5${D}）；"
  echo -e "  想全部删除就只输入一个字母 ${BD}a${D}。"
  exit 1
fi
has() { case " $SEL " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
echo -e "\n${B}已识别的编号：${BD}${SEL}${D}"

# ---- 强提示：把即将删除的具体内容摊开 ----
echo
echo -e "${BD}${R}即将执行以下操作：${D}"
has 1 && echo -e "  • 停止端口 $PORT 上的服务（${SVC}）"

# 按文件类型摊开，让用户清楚每类是什么、有多少
if has 2 || has 3 || has 4; then
  echo -e "\n  ${BD}按文件类型列出将被删除的内容：${D}"
  if has 4 || has 2; then
    n=$(ls "$DIR/memory"/*.md 2>/dev/null | wc -l | tr -d " ")
    [ "${n:-0}" -gt 0 ] && echo -e "    ${R}·${D} 对话记录  ${BD}*.md${D} × ${n}        你和 AI 的全部问答原文（$DIR/memory/）"
    [ -f "$DIR/memory/index.json" ] && echo -e "    ${R}·${D} 记忆索引  ${BD}index.json${D}        关键词索引，删了记忆检索就没了"
  fi
  if has 4 || has 3; then
    [ -f "$DIR/config.json" ] && echo -e "    ${R}·${D} 配置文件  ${BD}config.json${D}        ${R}含 API key 与管理面板密码${D}"
  fi
  if has 4; then
    for pat in "storage.sqlite:数据库    :omniroute 的全部数据（提供者、用量、密钥）" \
               "storage.sqlite-wal:数据库日志:未落盘的写入" \
               ".env:环境变量  :含存储加密密钥"; do
      f="${pat%%:*}"; rest="${pat#*:}"; label="${rest%%:*}"; desc="${rest#*:}"
      if [ -e "$DIR/$f" ]; then
        sz=$(du -h "$DIR/$f" 2>/dev/null | cut -f1)
        echo -e "    ${R}·${D} $label  ${BD}$f${D} ($sz)        $desc"
      fi
    done
    ls "$DIR"/omni*.mjs >/dev/null 2>&1 && echo -e "    ${R}·${D} 脚本      ${BD}omni*.mjs${D}        omni 命令本体（可重装恢复）"
    [ -d "$DIR/logs" ] && echo -e "    ${R}·${D} 日志目录  ${BD}logs/${D}        服务运行日志"
    [ -d "$DIR/db_backups" ] && echo -e "    ${R}·${D} 数据库备份 ${BD}db_backups/${D}        omniroute 自己做的备份"
  fi
  echo
fi
has 4 && echo -e "  ${R}• 删除整个目录 ${DIR}（${DIRSIZE}）—— 包含对话记忆、API key、管理密码、omniroute 数据库，全部不可恢复${D}"
if ! has 4; then
  has 2 && echo -e "  ${R}• 删除 $DIR/memory —— $MEMDAYS 天 / $MEMCNT 条对话记忆，不可恢复${D}"
  has 3 && echo -e "  ${R}• 删除 $DIR/config.json —— 含 API key 与管理密码，不可恢复${D}"
fi
has 5 && echo -e "  • 卸载全局 npm 包 omniroute（${NPMSIZE}，之后可重新安装）"
has 6 && echo -e "  • 从 ~/.bashrc 与 ~/.zshrc 移除 omni alias（改前会存 .omni-bak）"
has 7 && echo -e "  • 删除 Docker 容器 omniroute（镜像会再问一次）"
if has 8; then
  if [ "$NODE_BREW" = "1" ]; then
    echo -e "  ${R}• 卸载 Node.js 及其 ${NODE_DEPS:-0} 个 brew 依赖（${NODE_ALL:-$NODE_SIZE}）—— 这台机器上其它依赖 Node 的项目会失效${D}"
  elif [ "$NODE_DESC" != "未安装" ]; then
    echo -e "  ${Y}• Node.js 不是 brew 装的，脚本不动它，结束时给你手工步骤${D}"
  fi
fi
has 9 && echo -e "  • 清空 npm 下载缓存（${NPM_CACHE}）与日志（${NPM_LOGS}）"
echo

# 涉及不可恢复的内容就先问备份
if has 2 || has 3 || has 4; then
  if [ -f "$DIR/config.json" ] || [ -d "$DIR/memory" ]; then
    read -r -p "要先备份 config.json 和对话记忆吗？[y=备份 / 回车=不备份，直接删]: " bk
    if [ "${bk:-}" = "y" ] || [ "${bk:-}" = "Y" ]; then
      BKDIR="$HOME/Desktop"; [ -d "$BKDIR" ] || BKDIR="$HOME"
      TS=$(date +%Y%m%d-%H%M%S)
      if [ -f "$DIR/config.json" ]; then
        cp "$DIR/config.json" "$BKDIR/omniroute-config-backup-$TS.json" 2>/dev/null \
          && echo -e "  ${G}✔${D} 配置已备份到 $BKDIR/omniroute-config-backup-$TS.json" \
          || echo -e "  ${Y}⚠ 配置备份失败${D}"
      fi
      if [ -d "$DIR/memory" ]; then
        cp -R "$DIR/memory" "$BKDIR/omniroute-memory-backup-$TS" 2>/dev/null \
          && echo -e "  ${G}✔${D} 对话记忆已备份到 $BKDIR/omniroute-memory-backup-$TS" \
          || echo -e "  ${Y}⚠ 记忆备份失败${D}"
      fi
    fi
    echo
  fi
fi

echo -e "${BD}${R}最后一步：请完整输入小写的 yes（三个字母）才会真正执行。${D}"
read -r -p "确认执行？[输入 yes 执行 / 其它任何内容取消]：" ans
if [ "${ans:-}" != "yes" ]; then
  case "${ans:-}" in
    y|Y|Yes|YES|yES|yeS|YEs|yEs) echo -e "${Y}⚠ 你输入的是「${ans}」，需要完整的小写 ${BD}yes${D}${Y} 才会执行。${D}" ;;
  esac
  echo -e "${G}已取消，什么都没有改动。${D}"
  exit 0
fi
echo

if has 1 || has 4 || has 5; then
  echo -e "${B}› 停止服务…${D}"
  if [ -f "$DIR/omni.mjs" ] && command -v node >/dev/null 2>&1; then node "$DIR/omni.mjs" down >/dev/null 2>&1; fi
  if command -v lsof >/dev/null 2>&1; then
    pids=$(lsof -ti "tcp:$PORT" 2>/dev/null)
    if [ -n "${pids:-}" ]; then
      kill $pids 2>/dev/null; sleep 1
      pids=$(lsof -ti "tcp:$PORT" 2>/dev/null)
      [ -n "${pids:-}" ] && kill -9 $pids 2>/dev/null
      echo "  已结束占用端口 $PORT 的进程"
    else echo "  端口 $PORT 上没有进程"; fi
  else echo -e "  ${Y}⚠ 没有 lsof，跳过端口清理${D}"; fi
fi

if has 7; then
  echo -e "${B}› 清理 Docker…${D}"
  if command -v docker >/dev/null 2>&1; then
    docker rm -f omniroute >/dev/null 2>&1 && echo "  已删除容器 omniroute" || echo "  没有容器 omniroute"
    if docker images -q diegosouzapw/omniroute 2>/dev/null | grep -q .; then
      read -r -p "  还有镜像 diegosouzapw/omniroute（数百 MB），一并删除？(y/N)：" rmimg
      if [ "${rmimg:-}" = "y" ] || [ "${rmimg:-}" = "Y" ]; then
        docker rmi -f diegosouzapw/omniroute:latest >/dev/null 2>&1 && echo "  已删除镜像" || echo "  镜像删除失败（可能被占用）"
      else echo "  已保留镜像"; fi
    fi
  else echo "  没装 Docker，跳过"; fi
fi

if has 5; then
  echo -e "${B}› 卸载全局 npm 包…${D}"
  if command -v npm >/dev/null 2>&1; then
    if npm uninstall -g omniroute >/dev/null 2>&1; then echo "  已卸载"
    else echo -e "  ${Y}⚠ 失败${D}，可能需要权限：sudo npm uninstall -g omniroute"; fi
  else echo "  没装 npm，跳过"; fi
fi

if has 6; then
  echo -e "${B}› 清理 shell alias…${D}"
  for f in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$f" ] || continue
    grep -q '# >>> omni-free-llm >>>' "$f" 2>/dev/null || continue
    cp "$f" "$f.omni-bak" 2>/dev/null && echo "  已备份 $f → $f.omni-bak"
    sed -i.omni-tmp '/# >>> omni-free-llm >>>/,/# <<< omni-free-llm <<</d' "$f" 2>/dev/null && rm -f "$f.omni-tmp"
    echo "  已从 $f 移除 alias 段"
  done
fi

if has 9; then
  echo -e "${B}› 清理 npm 缓存与日志…${D}"
  if command -v npm >/dev/null 2>&1; then
    npm cache clean --force >/dev/null 2>&1 && echo "  已清空 npm 缓存" || echo -e "  ${Y}⚠ npm cache clean 失败${D}"
  fi
  if [ -d "$HOME/.npm/_logs" ]; then
    rm -f "$HOME/.npm/_logs"/*.log 2>/dev/null && echo "  已删除 npm 日志"
  fi
fi

if has 8 && [ "$NODE_BREW" = "1" ]; then
  echo -e "${B}› 卸载 Node.js 及其 brew 依赖…${D}"
  if [ -n "$(brew uses --installed node 2>/dev/null)" ]; then
    echo -e "  ${Y}⚠ 还有其它 brew 包依赖 node，已跳过以免连带损坏：${D}"
    brew uses --installed node 2>/dev/null | sed 's/^/      /'
  else
    brew uninstall node >/dev/null 2>&1 && echo "  已卸载 node" || echo -e "  ${Y}⚠ node 卸载失败${D}"
    brew autoremove >/dev/null 2>&1 && echo "  已用 brew autoremove 清掉不再被依赖的连带包" || true
  fi
fi

if has 4; then
  echo -e "${B}› 删除整个安装目录…${D}"
  if [ -d "$DIR" ]; then rm -rf "$DIR" && echo "  已删除 $DIR" || echo -e "  ${R}✖ 删除失败${D}，请手动删除 $DIR"; else echo "  目录不存在"; fi
else
  if has 2 && [ -d "$DIR/memory" ]; then
    echo -e "${B}› 删除对话记忆…${D}"
    rm -rf "$DIR/memory" && echo "  已删除 $DIR/memory" || echo -e "  ${R}✖ 删除失败${D}"
  fi
  if has 3 && [ -f "$DIR/config.json" ]; then
    echo -e "${B}› 删除配置…${D}"
    rm -f "$DIR/config.json" && echo "  已删除 $DIR/config.json" || echo -e "  ${R}✖ 删除失败${D}"
  fi
fi

# omniroute 的数据库/凭据固定落在 ~/.omniroute，哪怕安装目录选在别处
DEFDIR="$HOME/.omniroute"
if has 4 && [ "$DIR" != "$DEFDIR" ] && [ -d "$DEFDIR" ]; then
  echo
  echo -e "  ${Y}另外发现 omniroute 的默认数据目录：$DEFDIR${D}（数据库、凭据都在这里）"
  read -r -p "  一并删除？(y/N)：" rmdef
  if [ "${rmdef:-}" = "y" ] || [ "${rmdef:-}" = "Y" ]; then
    rm -rf "$DEFDIR" && echo "  已删除 $DEFDIR" || echo -e "  ${R}✖ 删除失败${D}"
  else echo "  已保留 $DEFDIR"; fi
fi

echo
echo -e "${G}✔ 完成。${D}本次处理的编号：${BD}${SEL}${D}"
has 6 && echo -e "${Y}提示：${D}重开终端（或 source ~/.bashrc）后 omni 命令才会彻底消失。"

# Homebrew 本身不是本工具装的，不自动删；把手工步骤打出来由你决定
if has 8 && command -v brew >/dev/null 2>&1; then
  LEFT=$(brew list --formula 2>/dev/null | wc -l | tr -d " ")
  echo
  echo -e "${BD}关于 Homebrew（脚本刻意不动它）${D}"
  echo -e "  Homebrew 不是这个安装器装的（装它的时间比本工具早得多），所以不在自动删除范围内。"
  echo -e "  目前 brew 里还剩 ${LEFT} 个 formula。"
  if [ "${LEFT:-0}" -eq 0 ]; then
    echo -e "  已经空了。要连 Homebrew 一起卸掉的话，自己跑这条官方卸载脚本："
  else
    echo -e "  ${R}注意：里面还有 ${LEFT} 个包，卸掉 Homebrew 会把它们全部带走。${D}确认无所谓再跑："
  fi
  echo -e "    ${B}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)\"${D}"
fi
if has 8 && [ "$NODE_BREW" != "1" ] && [ "$NODE_DESC" != "未安装" ]; then
  echo
  echo -e "${BD}关于 Node.js（不是 brew 装的，脚本没动）${D}"
  echo -e "  当前：$NODE_DESC"
  echo -e "  如果是从官网 .pkg 装的，手工删除："
  echo -e "    ${B}sudo rm -rf /usr/local/lib/node_modules /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx${D}"
  echo -e "    ${B}sudo pkgutil --forget org.nodejs.pkg${D}"
  echo -e "  如果是 nvm 装的：${B}nvm uninstall <版本>${D}"
fi
