#!/usr/bin/env bash
# omni-free-llm 卸载（逐项可选，删前强提示）
# 不会删除：Node.js / Homebrew / Docker 本身 —— 其它项目可能在用
set -u

G='\033[32m'; B='\033[36m'; Y='\033[33m'; R='\033[31m'; D='\033[0m'; BD='\033[1m'

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
  MEMSIZE=$(du -sh "$DIR/memory" 2>/dev/null | cut -f1)
fi
DIRSIZE=$(du -sh "$DIR" 2>/dev/null | cut -f1)
NPMSIZE="-"
if command -v npm >/dev/null 2>&1; then
  NR=$(npm root -g 2>/dev/null)
  [ -n "${NR:-}" ] && [ -d "$NR/omniroute" ] && NPMSIZE=$(du -sh "$NR/omniroute" 2>/dev/null | cut -f1)
fi
SVC="未运行"
if command -v lsof >/dev/null 2>&1 && [ -n "$(lsof -ti "tcp:$PORT" 2>/dev/null)" ]; then SVC="运行中"; fi

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
echo
echo -e "${G}始终不会删除：${D}Node.js、Homebrew、Docker 本身 —— 其它项目可能正在用它们。"
echo
read -r -p "输入要删除的编号，空格分隔（如 2 5）；a=全部；直接回车取消：" SEL
[ -z "${SEL:-}" ] && { echo -e "${G}已取消，什么都没有改动。${D}"; exit 0; }
case "$SEL" in a|A|all|ALL) SEL="1 2 3 4 5 6 7" ;; esac
has() { case " $SEL " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# ---- 强提示：把即将删除的具体内容摊开 ----
echo
echo -e "${BD}${R}即将执行以下操作：${D}"
has 1 && echo -e "  • 停止端口 $PORT 上的服务（$SVC）"

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
has 4 && echo -e "  ${R}• 删除整个目录 $DIR（$DIRSIZE）—— 包含对话记忆、API key、管理密码、omniroute 数据库，全部不可恢复${D}"
if ! has 4; then
  has 2 && echo -e "  ${R}• 删除 $DIR/memory —— $MEMDAYS 天 / $MEMCNT 条对话记忆，不可恢复${D}"
  has 3 && echo -e "  ${R}• 删除 $DIR/config.json —— 含 API key 与管理密码，不可恢复${D}"
fi
has 5 && echo -e "  • 卸载全局 npm 包 omniroute（$NPMSIZE，之后可重新安装）"
has 6 && echo -e "  • 从 ~/.bashrc 与 ~/.zshrc 移除 omni alias（改前会存 .omni-bak）"
has 7 && echo -e "  • 删除 Docker 容器 omniroute（镜像会再问一次）"
echo

# 涉及不可恢复的内容就先问备份
if has 2 || has 3 || has 4; then
  if [ -f "$DIR/config.json" ] || [ -d "$DIR/memory" ]; then
    read -r -p "先把 config.json 和对话记忆备份一份再删？(Y/n)：" bk
    if [ "${bk:-}" != "n" ] && [ "${bk:-}" != "N" ]; then
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

read -r -p "确认执行？输入 yes 继续（其它任何内容都会取消）：" ans
if [ "${ans:-}" != "yes" ]; then echo -e "${G}已取消，什么都没有改动。${D}"; exit 0; fi
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
echo -e "${G}✔ 完成。${D}Node.js 等公共依赖按设计保留了。"
has 6 && echo -e "${Y}提示：${D}重开终端（或 source ~/.bashrc）后 omni 命令才会彻底消失。"
