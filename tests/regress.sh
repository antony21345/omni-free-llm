#!/usr/bin/env bash
# omni-free-llm 回归测试：自包含，从 install.mjs 现生成运行时脚本再验证，不依赖已安装的副本
cd "$(dirname "$0")/.." || exit 1
ROOT="$(pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# 缺 Node 时不整体失败：静态检查（语法/行尾/BOM/权限/提示语）照跑，只跳过需要 Node 的部分
HAVE_NODE=0; command -v node >/dev/null 2>&1 && HAVE_NODE=1
[ "$HAVE_NODE" = "0" ] && echo "注意：本机没有 Node，[4] 和 [5] 需要 Node 的检查将跳过"

echo "[1] 语法检查"
if [ "$HAVE_NODE" = "1" ]; then
  node --check install.mjs 2>/dev/null && ok "install.mjs" || no "install.mjs"
else
  ok "（跳过 install.mjs 语法检查，需要 Node）"
fi
for f in install.sh install.command uninstall.sh uninstall.command tests/regress.sh; do
  bash -n "$f" 2>/dev/null && ok "$f" || no "$f"
done

echo "[2] 编码与行尾（Windows 脚本必须 CRLF，Unix 脚本必须 LF）"
for f in install.bat install.ps1 uninstall.bat uninstall.ps1; do
  [ "$(grep -c $'\r' "$f")" -gt 0 ] && ok "$f CRLF" || no "$f 不是 CRLF（cmd 会解析失败）"
done
for f in install.sh install.command uninstall.sh uninstall.command; do
  [ "$(grep -c $'\r' "$f")" -eq 0 ] && ok "$f LF" || no "$f 混入 CR"
done
for f in install.ps1 uninstall.ps1; do
  head -c 3 "$f" | grep -q $'\xEF\xBB\xBF' && ok "$f 有 UTF-8 BOM" || no "$f 缺 BOM（PS 5.1 中文乱码）"
done

echo "[3] 可执行位"
for f in install.command uninstall.command install.sh uninstall.sh; do
  [ -x "$f" ] && ok "$f 可执行" || no "$f 缺 x 权限"
done

if [ "$HAVE_NODE" = "0" ]; then
  echo "[4][5] 跳过（需要 Node）"
else
echo "[4] 从 install.mjs 生成运行时脚本"
node -e "
const fs=require('fs');
import('$ROOT/install.mjs').then(m=>{
  fs.writeFileSync('$T/omni.mjs', m.OMNI_SCRIPT);
  fs.writeFileSync('$T/omni-mcp.mjs', m.MCP_SCRIPT);
  fs.writeFileSync('$T/omni-watchdog.mjs', m.WATCHDOG_SCRIPT);
  if(!m.DEFAULT_SYSTEM_PROMPT) process.exit(1);
});" 2>/dev/null && ok "三个模板导出成功" || no "模板导出失败"
for f in omni.mjs omni-mcp.mjs omni-watchdog.mjs; do
  node --check "$T/$f" 2>/dev/null && ok "生成的 $f 语法正确" || no "生成的 $f 语法错误（模板转义有问题）"
done

echo "[5] 功能冒烟（mock 上游）"
cat > "$T/srv.mjs" <<'MOCK'
import http from "node:http";
http.createServer((req,res)=>{
  if(req.url.includes("/api/health")){res.writeHead(200,{"Content-Type":"application/json"});res.end('{"ok":true}');return;}
  if(req.url.includes("/chat/completions")){
    let b="";req.on("data",c=>b+=c);
    req.on("end",()=>{const j=JSON.parse(b);
      console.error("msgs="+j.messages.length+" stream="+j.stream);
      res.writeHead(200,{"Content-Type":"text/event-stream"});
      res.write('data: {"model":"mock-m","choices":[{"delta":{"content":"## 标题\\n**粗体**回答"}}]}\n\n');
      res.write('data: {"usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15},"choices":[]}\n\n');
      res.write('data: [DONE]\n\n');res.end();});
    return;}
  res.writeHead(404);res.end();
}).listen(20999);
MOCK
cat > "$T/config.json" <<'CFG'
{"port":20999,"baseUrl":"http://localhost:20999/v1","healthUrl":"http://localhost:20999/api/health",
"apiKey":"t","model":"auto","systemPrompt":"测试","backend":"npm","startArgs":[],"os":"macos",
"dir":"t","memoryEnabled":true,"memoryTopN":3,"spinner":true}
CFG
node "$T/srv.mjs" & MOCKPID=$!
sleep 1.5
OUT=$(OMNI_DIR="$T" node "$T/omni.mjs" chat "冒烟测试问题" 2>&1)
echo "$OUT" | grep -q "粗体" && ok "chat 有返回" || no "chat 无返回"
echo "$OUT" | grep -q "输入 10 tok" && ok "token 统计" || no "token 统计缺失"
echo "$OUT" | grep -q "模型 mock-m" && ok "模型名显示" || no "模型名缺失"
echo "$OUT" | grep -q $'\x1b\[1;36m' && ok "markdown 标题上色" || no "标题未上色"
[ -f "$T/memory/index.json" ] && ok "长记忆落盘" || no "长记忆未落盘"
OMNI_DIR="$T" node "$T/omni.mjs" memory 2>&1 | grep -q "条记忆" && ok "omni memory" || no "omni memory 失败"
OMNI_DIR="$T" node "$T/omni.mjs" memory search 冒烟 2>&1 | grep -q "冒烟" && ok "omni memory search" || no "memory search 未命中"
OMNI_DIR="$T" node "$T/omni.mjs" status 2>&1 | grep -q "base_url" && ok "omni status" || no "omni status 失败"
OMNI_DIR="$T" node "$T/omni.mjs" editor 2>&1 | grep -q "base_url" && ok "omni editor" || no "omni editor 失败"
kill $MOCKPID 2>/dev/null; wait $MOCKPID 2>/dev/null
fi

echo "[6] 卸载脚本安全性"
# 自备数据：[5] 在缺 Node 时会被跳过，不能依赖它创建的文件
mkdir -p "$T/memory"
[ -f "$T/config.json" ] || printf '{"port":20999}\n' > "$T/config.json"
[ -f "$T/memory/index.json" ] || printf '{"items":[]}\n' > "$T/memory/index.json"
B=$(ls -a "$T" | wc -l)
printf '2 3\nn\nno\n' | bash uninstall.sh "$T" >/dev/null 2>&1
A=$(ls -a "$T" | wc -l)
[ "$B" = "$A" ] && ok "取消后文件数不变" || no "取消后文件被改动"
printf '2 3\nn\nno\n' | bash uninstall.sh "$T" 2>&1 | grep -q "按文件类型列出" && ok "按文件类型提示" || no "类型提示缺失"
printf '\n' | bash uninstall.sh "$T" 2>&1 | grep -q "已取消" && ok "回车即取消" || no "回车未取消"
bash uninstall.sh "$HOME" </dev/null 2>&1 | grep -q "拒绝操作" && ok "拒绝对 HOME 动手" || no "危险路径未拦截"
MENU=$(printf '\n' | bash uninstall.sh "$T" 2>&1)
echo "$MENU" | grep -q "Node.js" && ok "菜单含 Node 选项" || no "菜单缺 Node 选项"
echo "$MENU" | grep -q "npm 下载缓存" && ok "菜单含 npm 缓存选项" || no "菜单缺 npm 缓存选项"
echo "$MENU" | grep -q "Homebrew 本身" && ok "菜单说明 Homebrew 不自动删" || no "缺 Homebrew 说明"
echo "$MENU" | grep -qE '\$[A-Za-z_]' && no "菜单里有未展开的变量（变量边界问题）" || ok "菜单无未展开变量"
ALLSEL=$(printf 'a\nn\nno\n' | bash uninstall.sh "$T" 2>&1)
if [ "$HAVE_NODE" = "1" ]; then
  echo "$ALLSEL" | grep -q "卸载 Node.js" && ok "a 全选时包含 Node" || no "a 全选未包含 Node"
else
  # Node 不在时，菜单要么说明 brew 里还有残留可清，要么说明确实没什么可删 —— 不能笼统写「跳过」把人劝退
  echo "$ALLSEL" | grep -qE "brew 里还有残留|未安装且无残留" && ok "Node 未安装时菜单标注正确" || no "Node 未安装时菜单标注有误"
fi
echo "$ALLSEL" | grep -q "已取消" && ok "a 全选后仍可取消" || no "a 全选后取消失效"
[ -f "$T/config.json" ] && ok "a 全选取消后文件未动" || no "a 全选取消后文件被删"
printf 'a\nn\ny\n' | bash uninstall.sh "$T" 2>&1 | grep -q "需要完整的小写" && ok "输 y 会提示需要完整 yes" || no "输 y 时没有提示原因"
[ -f "$T/config.json" ] && ok "输 y 之后文件仍未动" || no "输 y 竟然执行了删除"

echo "[7] 编号输入的各种写法"
noansi(){ sed $'s/\033\[[0-9;]*m//g'; }
printf '1,2,3\nn\nno\n' | bash uninstall.sh "$T" 2>&1 | noansi | grep -q "已识别的编号：1 2 3$" && ok "逗号分隔可识别" || no "逗号分隔未识别"
printf '2、3\nn\nno\n' | bash uninstall.sh "$T" 2>&1 | noansi | grep -q "已识别的编号：2 3$" && ok "顿号分隔可识别" || no "顿号分隔未识别"
printf 'a\nn\nno\n' | bash uninstall.sh "$T" 2>&1 | noansi | grep -q "已识别的编号：1 2 3 4 5 6 7 8 9$" && ok "a 展开为 1-9" || no "a 未正确展开"
BADOUT=$(printf 'abc\n' | bash uninstall.sh "$T" 2>&1); BADRC=$?
echo "$BADOUT" | grep -q "没识别出任何有效编号" && ok "无效输入会明确报错" || no "无效输入被静默接受"
[ "$BADRC" != "0" ] && ok "无效输入以非零码退出" || no "无效输入却返回成功"

echo "[7b] 交互提示语不能吐出转义序列（只在真人终端可见，靠静态断言兜住）"
for f in uninstall.sh install.sh; do
  # 颜色变量必须用 $'...' 定义，普通单引号里的 \033 是字面字符，read -p 不会解释它
  if grep -qE "^[A-Z]+='\\\\033" "$f"; then no "$f 颜色变量用了普通单引号（read -p 会吐出 \\033）"; else ok "$f 颜色变量定义正确"; fi
  # read 的提示语里不许出现颜色变量
  if grep 'read -r -p' "$f" 2>/dev/null | grep -qE '\$\{(G|B|Y|R|D|BD)\}'; then no "$f 的 read 提示语含颜色变量"; else ok "$f 的 read 提示语是纯文本"; fi
done
if command -v expect >/dev/null 2>&1; then
  cat > "$T/p.exp" <<EXPEOF
set timeout 10
spawn bash $ROOT/uninstall.sh $T
expect "你的选择"
send "\r"
expect eof
EXPEOF
  POUT=$(LC_ALL=C expect "$T/p.exp" 2>&1)
  echo "$POUT" | grep -q '\\033' && no "真实终端下提示语吐出了字面 \\033" || ok "真实终端下提示语无字面转义序列"
else
  ok "（无 expect，跳过 TTY 渲染检查）"
fi

echo "[7c] 只删自己带来的：空壳文件与空目录该删，有别人内容的要留"
HA="$(mktemp -d)"; mkdir -p "$HA/.config/configstore"
printf '\n\n# >>> omni-free-llm >>>\nalias omni=x\n# <<< omni-free-llm <<<\n' > "$HA/.bashrc"
printf 'export FOO=1\n# >>> omni-free-llm >>>\nalias omni=y\n# <<< omni-free-llm <<<\n' > "$HA/.zshrc"
printf '{"a":1}\n' > "$HA/.config/configstore/update-notifier-omniroute.json"
printf 'a\nyes\n\n' | HOME="$HA" PATH=/usr/bin:/bin bash uninstall.sh >/dev/null 2>&1
[ ! -f "$HA/.bashrc" ] && ok "只有 alias 的空壳文件被删除" || no "空壳文件没被删"
[ -f "$HA/.zshrc" ] && grep -q 'export FOO=1' "$HA/.zshrc" && ok "有别人内容的文件保留且内容完好" || no "有内容的文件被误删或损坏"
[ ! -d "$HA/.config/configstore" ] && ok "空的 configstore 目录被删除" || no "空目录没被删"
[ -d "$HA/.config" ] && ok "~/.config 本身没被碰" || no "~/.config 被误删了！"
rm -rf "$HA" 2>/dev/null

HB="$(mktemp -d)"; mkdir -p "$HB/.config/configstore"
printf '{"a":1}\n' > "$HB/.config/configstore/update-notifier-omniroute.json"
printf '{"o":1}\n' > "$HB/.config/configstore/update-notifier-other.json"
printf 'a\nyes\n\n' | HOME="$HB" PATH=/usr/bin:/bin bash uninstall.sh >/dev/null 2>&1
[ -d "$HB/.config/configstore" ] && ok "configstore 有别人记录时保留目录" || no "误删了还有内容的 configstore"
[ -f "$HB/.config/configstore/update-notifier-other.json" ] && ok "别的工具的记录完好" || no "误删了别的工具的记录"
[ ! -f "$HB/.config/configstore/update-notifier-omniroute.json" ] && ok "只删掉 omniroute 自己的记录" || no "omniroute 记录没删掉"
rm -rf "$HB" 2>/dev/null

# alias 段已经被上一次卸载删掉的情况：靠 .omni-bak 作为「安装器动过它」的证据
HC="$(mktemp -d)"
printf '\n' > "$HC/.bashrc"
printf 'export PATH="$HOME/.local/bin:$PATH"\n' > "$HC/.zshrc"
printf '# >>> omni-free-llm >>>\n' > "$HC/.bashrc.omni-bak"
printf '# >>> omni-free-llm >>>\n' > "$HC/.zshrc.omni-bak"
printf 'a\nyes\n\n' | HOME="$HC" PATH=/usr/bin:/bin bash uninstall.sh >/dev/null 2>&1
[ ! -f "$HC/.bashrc" ] && ok "alias 已删但有 .omni-bak 时仍能清掉空壳" || no "空壳没被清掉（会让用户白跑一趟）"
[ -f "$HC/.zshrc" ] && ok "同场景下有内容的文件仍保留" || no "有内容的文件被误删"
rm -rf "$HC" 2>/dev/null

# 无关的空文件：没有任何证据说明是本工具创建的，绝不能删
HD="$(mktemp -d)"
printf '\n' > "$HD/.bashrc"
printf 'a\nyes\n\n' | HOME="$HD" PATH=/usr/bin:/bin bash uninstall.sh >/dev/null 2>&1
[ -f "$HD/.bashrc" ] && ok "空文件但无 .omni-bak 时不碰（不误删无关文件）" || no "误删了与本工具无关的空文件！"
rm -rf "$HD" 2>/dev/null

echo "[7d] 不承诺脚本做不到的事"
for f in install.command uninstall.command; do
  # 窗口关闭由终端设置决定，脚本控制不了，提示语不能这么写
  grep -q '关闭本窗口' "$f" && no "$f 承诺了「关闭本窗口」，但脚本做不到" || ok "$f 没有承诺关闭窗口"
done

echo "[8] 真正执行删除的路径（HOME 与 PATH 都隔离，不碰真实环境）"
D="$(mktemp -d)"; H="$(mktemp -d)"
mkdir -p "$D/memory"
printf '{"port":20999}\n' > "$D/config.json"
printf '## x\n\n**问：** a\n' > "$D/memory/2026-01-01.md"
printf '{"items":[{"id":"x","file":"2026-01-01.md","time":"2026-01-01T00:00:00Z","keywords":["a"],"summary":"a"}]}\n' > "$D/memory/index.json"
RUN=$(printf 'a\nn\nyes\n' | HOME="$H" PATH=/usr/bin:/bin bash uninstall.sh "$D" 2>&1)
echo "$RUN" | grep -q "› 删除整个安装目录" && ok "执行时打印了删除明细" || no "执行时没有明细（就是用户遇到的现象）"
echo "$RUN" | grep -q "本次处理的编号" && ok "结尾汇总了处理的编号" || no "结尾缺少汇总"
[ ! -d "$D" ] && ok "目标目录确实被删除了" || no "目标目录仍然存在"
rm -rf "$H" 2>/dev/null

echo
echo "通过 $PASS 项，失败 $FAIL 项"
exit $FAIL
